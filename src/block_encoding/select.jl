# SELECT oracle for LCU block encoding.
#
# ═══════════════════════════════════════════════════════════════════════════
# PHYSICS
# ═══════════════════════════════════════════════════════════════════════════
#
# Given H = Σ_j h_j P_j  (L terms, each P_j a Pauli string on N qubits),
# SELECT acts on an ancilla register |j⟩ (a = ⌈log₂ L⌉ qubits) and a
# system register |ψ⟩:
#
#   SELECT |j⟩|ψ⟩ = |j⟩ · sign(h_j) · P_j |ψ⟩      for j < L
#   SELECT |j⟩|ψ⟩ = |j⟩|ψ⟩                           for j ≥ L (padding)
#
# The sign is separated from the magnitude because PREPARE encodes
# sqrt(|h_j|/λ) in the ancilla amplitudes, and the sign must be applied
# by SELECT. The LCU identity then gives:
#
#   ⟨0|^a (PREPARE† ⊗ I) · SELECT · (PREPARE ⊗ I) |0⟩^a = H / λ
#
# ═══════════════════════════════════════════════════════════════════════════
# THE SESSION 8 BUG AND WHY _pauli_exp! IS THE ONLY CORRECT APPROACH
# ═══════════════════════════════════════════════════════════════════════════
#
# The 4 DSL primitives generate SU(2) (det = +1), not U(2). This means:
#   - X! = Ry(π) ≠ Pauli X = diag(0,1;1,0).  Inside when(), controlled-Ry(π) ≠ CNOT.
#   - Z! = Rz(π). Inside when(), controlled-Rz(π) = diag(1,1,-i,i) ≠ CZ = diag(1,1,1,-1).
#
# You CANNOT naively compose X!, Z!, Y! inside when() to get controlled-Paulis.
#
# The proven correct approach: use _pauli_exp! with θ = π/2.
#   exp(-i(π/2)·P) = cos(π/2)I - i·sin(π/2)P = 0·I - i·1·P = -i·P
#
# So _pauli_exp!(qubits, term, π/2) gives -i·P on the system, which is
# channel-equivalent to P (global phase -i is unobservable). For negative
# sign: pass sgn=-1 in the PauliTerm coefficient, giving exp(+iπ/2·P) = +iP,
# which is channel-equivalent to -P.
#
# The factor -i (or +i) is CONSISTENT across all terms, so it factors out
# of the LCU sum: Σ_j sqrt(|h_j|/λ)·(-i·sgn_j·P_j) = -i · Σ_j (h_j/λ)·P_j = -i·H/λ.
# The overall -i is a global phase on the block encoding, unobservable.
#
# ═══════════════════════════════════════════════════════════════════════════
# CONTROL MECHANISM
# ═══════════════════════════════════════════════════════════════════════════
#
# Each term j must be applied only when the ancilla register holds |j⟩.
# We use the standard bit-flip + multi-control pattern:
#
# 1. For each ancilla qubit k where bit k of j is 0: apply X (flip it).
#    Now ancilla = all-|1⟩ iff it was |j⟩.
#
# 2. Multi-controlled application of the Pauli string:
#    - 1 ancilla: single when() block.
#    - ≥2 ancillas: Toffoli (AND) cascade reduces all controls to a single
#      workspace qubit, then when(workspace) calls _pauli_exp!.
#
# 3. Unflip the ancilla qubits (same X gates as step 1).
#
# The _pauli_exp! function has a built-in controlled-gate optimisation:
# when called inside when(), it saves and clears the control stack, applies
# basis changes and CNOT staircase unconditionally, restores the stack for
# the Rz pivot only, then clears and restores again. This is proven correct:
#   V · controlled(Rz) · V† = controlled(V · Rz · V†)
# where V = basis_change · CNOT_staircase acts only on target qubits.
#
# The Toffoli cascade uses single-control CNOTs only (when(a) { w ⊻= b }),
# which are natively supported by the EagerContext.
#
# ═══════════════════════════════════════════════════════════════════════════
# SELF-ADJOINTNESS
# ═══════════════════════════════════════════════════════════════════════════
#
# SELECT² on branch j gives (-i·sgn·P)² = (-1)·(sgn²)·P² = -I (since P²=I
# for any Pauli string). All branches get the same factor -I, which is a
# global phase. So SELECT is self-adjoint up to global phase.
#
# Ref: Berry, Childs, Cleve, Kothari, Somma (2015),
#      "Simulating Hamiltonian dynamics with a truncated Taylor series",
#      PRL 114:090502, Section II.
#      arXiv:1412.4687
#      Local PDF: docs/literature/quantum_simulation/lcu_taylor_series/1412.4687.pdf
#
# Ref: Barenco et al. (1995), "Elementary gates for quantum computation",
#      Phys. Rev. A 52(5):3457-3467, Lemma 7.2.
#      (Toffoli cascade for multi-controlled gates.)

"""
    _select!(ancillas::Vector{QBool}, system::Vector{QBool}, H::PauliHamiltonian{N})

Apply the SELECT oracle: for each term j of H, apply sign(h_j)·P_j to the
system register controlled on the ancilla register being in state |j⟩.

Each Pauli string is applied via `_pauli_exp!` with θ = π/2, giving
exp(-i(π/2)·sgn·P) = -i·sgn·P. The factor -i is a consistent global phase
across all terms.

For multi-qubit ancilla registers (a ≥ 2), a Toffoli cascade reduces all
ancilla controls to a single workspace qubit before entering the when()
block that _pauli_exp! sees.

SELECT is self-adjoint up to global phase: SELECT² = -I per branch.

Ref: BCKS-PRL15 arXiv:1412.4687, Section II.
"""
function _select!(ancillas::Vector{QBool}, system::Vector{QBool},
                   H::PauliHamiltonian{N}) where {N}
    length(system) == N || error(
        "_select!: expected $N system qubits, got $(length(system))")
    a = length(ancillas)
    a >= 1 || error("_select!: need at least 1 ancilla qubit")
    L = nterms(H)
    L <= (1 << a) || error(
        "_select!: $L terms need $(Int(ceil(log2(L)))) ancilla qubits, got $a")

    for j in 0:(L - 1)
        term = H.terms[j + 1]
        sgn = term.coeff >= 0 ? 1 : -1

        if _support_count(term) == 0
            # All-identity term: the _pauli_exp! approach gives -i·sgn·P for non-identity
            # terms, but cannot apply a scalar phase -i·sgn to the identity (no Ry/Rz
            # decomposition of scalar×I exists on a single qubit). This means the -i
            # phase factor does NOT apply uniformly to identity terms, breaking the LCU.
            #
            # KNOWN LIMITATION: Hamiltonians with identity terms (e.g., H = c₀I + H')
            # should subtract the identity component classically before block encoding:
            #   block_encode_lcu(H - c₀I), then add c₀ to the result classically.
            # This is standard practice — the identity term is an energy offset.
            #
            # For now: error on identity terms to prevent silent wrong results.
            error("_select!: all-identity term (term $(j+1), coeff=$(term.coeff)) is not " *
                  "supported in block encoding. Remove the identity component from the " *
                  "Hamiltonian before calling block_encode_lcu (it is a classical energy offset).")
        end

        # Step 1: Flip ancilla bits where j has a 0.
        _flip_for_index!(ancillas, j)

        # Step 2: Apply sign(h_j)·P_j controlled on all ancilla qubits = |1⟩.
        _multi_controlled_pauli_exp!(ancillas, system, term.ops, sgn)

        # Step 3: Unflip (restore ancilla state).
        _flip_for_index!(ancillas, j)
    end
    return nothing
end

"""
    _select_adj!(ancillas::Vector{QBool}, system::Vector{QBool}, H::PauliHamiltonian{N})

Adjoint of the SELECT oracle.

Since _pauli_exp! with θ = π/2 gives exp(-iπ/2·sgn·P), the adjoint uses
θ = -π/2 giving exp(+iπ/2·sgn·P). Terms are applied in reverse order.

Ref: BCKS-PRL15 arXiv:1412.4687, Section II.
"""
function _select_adj!(ancillas::Vector{QBool}, system::Vector{QBool},
                       H::PauliHamiltonian{N}) where {N}
    length(system) == N || error(
        "_select_adj!: expected $N system qubits, got $(length(system))")
    a = length(ancillas)
    a >= 1 || error("_select_adj!: need at least 1 ancilla qubit")
    L = nterms(H)

    # Reverse order for adjoint
    for j in (L - 1):-1:0
        term = H.terms[j + 1]
        sgn = term.coeff >= 0 ? 1 : -1

        if _support_count(term) == 0
            error("_select_adj!: all-identity term (term $(j+1), coeff=$(term.coeff)) is not " *
                  "supported in block encoding. Remove the identity component first.")
        end

        _flip_for_index!(ancillas, j)
        _multi_controlled_pauli_exp_adj!(ancillas, system, term.ops, sgn)
        _flip_for_index!(ancillas, j)
    end
    return nothing
end

# ═══════════════════════════════════════════════════════════════════════════
# Internal helpers
# ═══════════════════════════════════════════════════════════════════════════

"""
    _flip_for_index!(ancillas::Vector{QBool}, j::Int)

Apply X! to each ancilla qubit k where bit k of index j is 0.
After this, the ancilla register = all-|1⟩ iff it was in state |j⟩.
Applying twice is an identity (X! is self-inverse).
"""
@inline function _flip_for_index!(ancillas::Vector{QBool}, j::Int)
    a = length(ancillas)
    for k in 1:a
        if (j >> (k - 1)) & 1 == 0
            X!(ancillas[k])
        end
    end
    return nothing
end

"""
    _multi_controlled_phase_flip!(ctrls, system)

Apply -I (Rz(2π)) to system[1], controlled on all ctrl qubits being |1⟩.
Used for all-identity Pauli terms with negative sign.

Rz(2π) = diag(-1,-1) = -I. Inside a controlled block, this gives
controlled(-I), flipping the phase of the controlled subspace.

Uses same Toffoli cascade as _multi_controlled_pauli_exp!.
Rz(2π) is self-adjoint: Rz(2π)² = Rz(4π) = I.
"""
function _multi_controlled_phase_flip!(ctrls::Vector{QBool}, system::Vector{QBool})
    nc = length(ctrls)

    if nc == 1
        when(ctrls[1]) do
            system[1].φ += 2π
        end
    else
        ctx = ctrls[1].ctx
        nw = nc - 1
        work = [QBool(ctx, 0) for _ in 1:nw]

        when(ctrls[1]) do
            work[1] ⊻= ctrls[2]
        end
        for k in 2:nw
            when(work[k - 1]) do
                work[k] ⊻= ctrls[k + 1]
            end
        end

        when(work[nw]) do
            system[1].φ += 2π
        end

        for k in nw:-1:2
            when(work[k - 1]) do
                work[k] ⊻= ctrls[k + 1]
            end
        end
        when(ctrls[1]) do
            work[1] ⊻= ctrls[2]
        end

        for w in work
            discard!(w)
        end
    end
    return nothing
end

"""
    _multi_controlled_pauli_exp!(ctrls, system, ops, sgn)

Apply exp(-i(π/2)·sgn·P) to system, controlled on ALL ctrl qubits being |1⟩.

For 1 control qubit: single when() block. _pauli_exp! internally optimises
by clearing the control stack for basis changes and CNOT staircase, restoring
it only for the Rz pivot.

For ≥2 control qubits: Toffoli (AND) cascade reduces all controls into a
single workspace qubit, then a single when() on that workspace qubit calls
_pauli_exp!. The cascade uses only single-control CNOTs.

Ref: Barenco et al. (1995), Phys. Rev. A 52(5):3457, Lemma 7.2.
"""
function _multi_controlled_pauli_exp!(ctrls::Vector{QBool}, system::Vector{QBool},
                                       ops::NTuple{N, PauliOp}, sgn::Int) where {N}
    nc = length(ctrls)
    unit_term = PauliTerm{N}(Float64(sgn), ops)

    if nc == 1
        # Single control: when() pushes 1 control on the stack.
        # _pauli_exp! clears it for V/V†, restores for Rz pivot.
        when(ctrls[1]) do
            _pauli_exp!(system, unit_term, π / 2)
        end
    else
        # Toffoli cascade: AND-reduce nc controls into 1 workspace qubit.
        # nw = nc - 1 workspace qubits needed.
        ctx = ctrls[1].ctx
        nw = nc - 1
        work = [QBool(ctx, 0) for _ in 1:nw]

        # Forward AND chain
        when(ctrls[1]) do
            work[1] ⊻= ctrls[2]
        end
        for k in 2:nw
            when(work[k - 1]) do
                work[k] ⊻= ctrls[k + 1]
            end
        end

        # Apply Pauli controlled on single cascade output
        when(work[nw]) do
            _pauli_exp!(system, unit_term, π / 2)
        end

        # Backward: uncompute AND chain (same gates, reverse order)
        for k in nw:-1:2
            when(work[k - 1]) do
                work[k] ⊻= ctrls[k + 1]
            end
        end
        when(ctrls[1]) do
            work[1] ⊻= ctrls[2]
        end

        for w in work
            discard!(w)
        end
    end
    return nothing
end

"""
    _multi_controlled_pauli_exp_adj!(ctrls, system, ops, sgn)

Adjoint of _multi_controlled_pauli_exp!. Uses θ = -π/2 instead of +π/2,
giving exp(+i(π/2)·sgn·P).
"""
function _multi_controlled_pauli_exp_adj!(ctrls::Vector{QBool}, system::Vector{QBool},
                                           ops::NTuple{N, PauliOp}, sgn::Int) where {N}
    nc = length(ctrls)
    unit_term = PauliTerm{N}(Float64(sgn), ops)

    if nc == 1
        when(ctrls[1]) do
            _pauli_exp!(system, unit_term, -π / 2)
        end
    else
        ctx = ctrls[1].ctx
        nw = nc - 1
        work = [QBool(ctx, 0) for _ in 1:nw]

        # Forward AND chain (same as forward — Toffoli cascade is self-inverse)
        when(ctrls[1]) do
            work[1] ⊻= ctrls[2]
        end
        for k in 2:nw
            when(work[k - 1]) do
                work[k] ⊻= ctrls[k + 1]
            end
        end

        # Adjoint Pauli: θ = -π/2
        when(work[nw]) do
            _pauli_exp!(system, unit_term, -π / 2)
        end

        # Backward: uncompute AND chain
        for k in nw:-1:2
            when(work[k - 1]) do
                work[k] ⊻= ctrls[k + 1]
            end
        end
        when(ctrls[1]) do
            work[1] ⊻= ctrls[2]
        end

        for w in work
            discard!(w)
        end
    end
    return nothing
end
