# Library patterns: higher-order quantum operations built from the DSL.
# These are standard algorithms expressed using the 4 primitives.

# ── QFT: superpose and interfere ─────────────────────────────────────────────
# Ref: Nielsen & Chuang, §5.1 "The quantum Fourier transform", Eq. (5.2)-(5.4).
# See docs/physics/nielsen_chuang_5.1.md
#
# QFT on W qubits: for each qubit j (MSB first), apply H, then controlled
# phase rotations R_k = Rz(2π/2^k) from qubits j+1..W. Finish with
# bit-reversal (swap MSB↔LSB).
#
# All gates decompose to primitives:
#   H! = Rz(π) · Ry(π/2)
#   controlled-Rz(θ) = when(ctrl) { target.φ += θ }
#   swap! = 3× ⊻=

"""
    superpose!(x::QInt{W})

Apply the Quantum Fourier Transform in-place. Transforms computational
basis states to frequency-domain superpositions.

For |0⟩^W: produces uniform superposition (1/√(2^W)) Σ|k⟩.
"""
function superpose!(x::QInt{W}) where {W}
    check_live!(x)
    ctx = x.ctx

    # QFT circuit: MSB-first, little-endian storage means wires[W] is MSB
    for j in W:-1:1
        qj = QBool(x.wires[j], ctx, false)
        H!(qj)

        # Controlled phase rotations from higher-significance qubits
        for k in 1:(j - 1)
            ctrl = QBool(x.wires[j - k], ctx, false)
            # R_{k+1} = Rz(2π/2^{k+1}) = Rz(π/2^k)
            angle = π / (1 << k)
            when(ctrl) do
                qj.φ += angle
            end
        end
    end

    # Bit reversal: swap wires[i] ↔ wires[W+1-i]
    for i in 1:(W ÷ 2)
        j = W + 1 - i
        qi = QBool(x.wires[i], ctx, false)
        qj = QBool(x.wires[j], ctx, false)
        swap!(qi, qj)
    end

    return x
end

"""
    interfere!(x::QInt{W})

Apply the inverse QFT in-place. Transforms frequency-domain back to
computational basis.

interfere!(superpose!(|0⟩)) = |0⟩.
"""
function interfere!(x::QInt{W}) where {W}
    check_live!(x)
    ctx = x.ctx

    # Inverse QFT = reverse bit-reversal, then reverse gates with negated phases

    # Bit reversal first (same as forward — swap is self-inverse)
    for i in 1:(W ÷ 2)
        j = W + 1 - i
        qi = QBool(x.wires[i], ctx, false)
        qj = QBool(x.wires[j], ctx, false)
        swap!(qi, qj)
    end

    # Inverse of the H + controlled-phase block: LSB first, negated angles
    for j in 1:W
        # Inverse controlled phases (applied before H, in reverse order)
        for k in (j - 1):-1:1
            ctrl = QBool(x.wires[j - k], ctx, false)
            angle = -π / (1 << k)  # negated for inverse
            qj = QBool(x.wires[j], ctx, false)
            when(ctrl) do
                qj.φ += angle
            end
        end

        qj = QBool(x.wires[j], ctx, false)
        H!(qj)  # H is self-inverse
    end

    return x
end

# ── Fourier sampling ─────────────────────────────────────────────────────────

"""
    fourier_sample(oracle!::Function, n::Int) -> Int

Deutsch-Jozsa / Bernstein-Vazirani pattern:
  1. Prepare |0⟩^n
  2. superpose (QFT / Hadamard)
  3. Apply oracle
  4. interfere (inverse QFT)
  5. Measure

`oracle!` receives a QInt{n} in superposition and applies a phase oracle.
Returns the measured integer.
"""
function fourier_sample(oracle!::Function, ::Val{N}) where {N}
    ctx = current_context()
    x = QInt{N}(ctx, 0)
    superpose!(x)
    oracle!(x)
    interfere!(x)
    return Int(x)
end

# ── Phase estimation ─────────────────────────────────────────────────────────

"""
    phase_estimate(unitary!::Function, eigenstate::QBool, ::Val{P}) -> Int

Estimate the phase of a unitary applied to an eigenstate.
`unitary!` is a function that applies U to a QBool.
`eigenstate` is a QBool in an eigenstate of U (e.g., |1⟩ for Z gate).
`P` is the number of precision qubits.

Returns an integer k such that the eigenvalue is approximately e^{2πik/2^P}.

Ref: Nielsen & Chuang, §5.2 "Phase estimation", Fig. 5.2.
See docs/physics/nielsen_chuang_5.2.md
"""
function phase_estimate(unitary!::Function, eigenstate::QBool, ::Val{P}) where {P}
    ctx = eigenstate.ctx

    # Allocate P precision qubits, all |0⟩, then superpose
    prec = QInt{P}(ctx, 0)
    superpose!(prec)

    # Controlled-U^{2^j} for each precision qubit j (MSB first after QFT ordering)
    for j in 1:P
        ctrl = QBool(prec.wires[j], ctx, false)
        # Apply U^{2^{j-1}} controlled on precision qubit j
        power = 1 << (j - 1)
        when(ctrl) do
            for _ in 1:power
                unitary!(eigenstate)
            end
        end
    end

    # Inverse QFT on precision register
    interfere!(prec)

    # Measure precision register
    discard!(eigenstate)
    return Int(prec)
end

# ── Grover search & amplitude amplification ──────────────────────────────────
# Ref: Grover (1996), "A fast quantum mechanical algorithm for database search",
#      Proc. 28th STOC, pp. 212-219.
# Ref: Brassard, Høyer, Mosca, Tapp (2002), "Quantum Amplitude Amplification
#      and Estimation", Contemporary Mathematics 305, Theorem 2-3.
#
# The Grover operator is G = A · S₀ · A⁻¹ · S_χ where:
#   S_χ = oracle (flip phase of marked states)
#   A   = preparation (uniform superposition for standard Grover)
#   S₀  = 2|0⟩⟨0| - I (reflection about zero)
#
# All operations decompose to the 4 primitives via existing library:
#   Multi-controlled Z → Toffoli cascade (Barenco et al. 1995, Lemma 7.2)
#   Each Toffoli = when(c) { target ⊻= c2 } (uses CCX from Orkan)

"""
    _optimal_iterations(n_items::Int, n_marked::Int) -> Int

Optimal Grover iteration count for M marked items among N total.
Returns ⌊π/(4·arcsin(√(M/N)))⌋.

Ref: Boyer, Brassard, Høyer, Tapp (1998), Theorem 1.
"""
function _optimal_iterations(n_items::Int, n_marked::Int)
    (n_marked <= 0 || n_marked >= n_items) && return 0
    floor(Int, π / (4 * asin(sqrt(n_marked / n_items))))
end

# ── Multi-controlled Z via Toffoli cascade ───────────────────────────────────
# Ref: Barenco et al. (1995), "Elementary gates for quantum computation",
# Phys. Rev. A 52(5):3457-3467, Lemma 7.2.
#
# n-controlled Z decomposes into O(n) Toffolis with n-2 ancillae.
# The cascade computes AND of controls into ancillae, applies CZ,
# then uncomputes.

"""
    _cz!(a::QBool, b::QBool)

Controlled-Z gate: |11⟩ → -|11⟩, all other states unchanged.
CZ = CP(π). Decomposed into 2 CNOTs + 3 Rz rotations.

Note: our Z! = Rz(π) ≠ standard Z = diag(1,-1). CZ requires the
standard diag(1,1,1,-1), not controlled-Rz(π) = diag(1,1,-i,i).

Ref: Nielsen & Chuang §4.3, Eq. (4.9): CP(θ) decomposition.
"""
function _cz!(a::QBool, b::QBool)
    b.φ += π/2       # Rz(π/2) on target
    b ⊻= a            # CX
    b.φ -= π/2        # Rz(-π/2) on target
    b ⊻= a            # CX
    a.φ += π/2        # Rz(π/2) on control
end

"""
    _multi_controlled_z!(qubits::Vector{QBool})

Phase flip controlled on ALL qubits being |1⟩: |1...1⟩ → -|1...1⟩.
Uses proper CZ decomposition and Toffoli cascade with n-2 ancillae.

Ref: Barenco et al. (1995), Lemma 7.2.
"""
function _multi_controlled_z!(qubits::Vector{QBool})
    n = length(qubits)
    n >= 1 || error("_multi_controlled_z! requires at least 1 qubit")

    if n == 1
        # For 1 qubit in diffusion context (X·Z·X), Rz(π) gives correct
        # relative phase (-1 between |0⟩ and |1⟩). Global phase unobservable.
        Z!(qubits[1]); return
    end
    if n == 2
        _cz!(qubits[1], qubits[2]); return
    end

    ctx = qubits[1].ctx

    # Allocate n-2 ancillae (all |0⟩)
    ancillae = [QBool(ctx, 0) for _ in 1:(n - 2)]

    # Forward: compute AND chain via Toffolis
    when(qubits[1]) do; ancillae[1] ⊻= qubits[2]; end
    for k in 2:(n - 2)
        when(ancillae[k - 1]) do; ancillae[k] ⊻= qubits[k + 1]; end
    end

    # CZ (not controlled-Rz!) between last ancilla and last qubit
    _cz!(ancillae[n - 2], qubits[n])

    # Backward: uncompute ancillae
    for k in (n - 2):-1:2
        when(ancillae[k - 1]) do; ancillae[k] ⊻= qubits[k + 1]; end
    end
    when(qubits[1]) do; ancillae[1] ⊻= qubits[2]; end

    for anc in ancillae; discard!(anc); end
end

# ── Diffusion operator ──────────────────────────────────────────────────────

"""
    _diffusion!(x::QInt{W})

Reflection about |0⟩^W: S₀ = 2|0⟩⟨0| - I.
Circuit: X all, multi-controlled Z, X all.
"""
function _diffusion!(x::QInt{W}) where {W}
    check_live!(x)
    ctx = x.ctx
    qs = [QBool(x.wires[i], ctx, false) for i in 1:W]
    for q in qs; X!(q); end
    _multi_controlled_z!(qs)
    qs = [QBool(x.wires[i], ctx, false) for i in 1:W]
    for q in qs; X!(q); end
end

# ── Phase oracle ─────────────────────────────────────────────────────────────

"""
    phase_flip!(x::QInt{W}, target::Integer)

Mark a computational basis state by flipping its phase: |target⟩ → -|target⟩.
All other states unchanged.

Circuit: X qubits where target has a 0 bit (mapping |target⟩ to |1...1⟩),
multi-controlled Z, undo X. Built entirely from the 4 primitives.
"""
function phase_flip!(x::QInt{W}, target::Integer) where {W}
    check_live!(x)
    (0 <= target < (1 << W)) || error("phase_flip!: target $target out of range for QInt{$W}")
    ctx = x.ctx

    qs = [QBool(x.wires[i], ctx, false) for i in 1:W]
    for i in 1:W
        if (target >> (i - 1)) & 1 == 0; X!(qs[i]); end
    end
    _multi_controlled_z!(qs)
    qs = [QBool(x.wires[i], ctx, false) for i in 1:W]
    for i in 1:W
        if (target >> (i - 1)) & 1 == 0; X!(qs[i]); end
    end
end

"""
    phase_flip!(x::QInt{W}, targets::AbstractVector{<:Integer})

Mark multiple basis states by flipping each of their phases.
"""
function phase_flip!(x::QInt{W}, targets::AbstractVector{<:Integer}) where {W}
    for t in targets; phase_flip!(x, t); end
end

# ── Amplitude amplification ─────────────────────────────────────────────────

"""
    _hadamard_all!(x::QInt{W})

Apply H to each qubit independently. NOT the same as QFT (superpose!).
H^⊗W on |0⟩ = QFT on |0⟩ = uniform superposition, but on arbitrary
states they differ. Grover's diffusion operator requires H^⊗W.
"""
function _hadamard_all!(x::QInt{W}) where {W}
    check_live!(x)
    ctx = x.ctx
    for i in 1:W
        qi = QBool(x.wires[i], ctx, false)
        H!(qi)
    end
end

"""
    amplify(oracle!::Function, prepare!::Function, unprepare!::Function,
            ::Val{W}; n_marked::Int=1, iterations::Int=-1) -> Int

Amplitude amplification: the general form of Grover's algorithm.

`prepare!(x::QInt{W})` maps |0⟩ to the initial superposition.
`unprepare!(x::QInt{W})` is the inverse of prepare! (A†).
`oracle!(x::QInt{W})` flips the phase of marked states.
Returns the measured integer (type boundary = measurement).

Ref: Brassard et al. (2002), Algorithm 1 / Theorem 3.
"""
function amplify(oracle!::Function, prepare!::Function, unprepare!::Function,
                 ::Val{W}; n_marked::Int=1, iterations::Int=-1) where {W}
    ctx = current_context()
    iters = iterations >= 0 ? iterations : _optimal_iterations(1 << W, n_marked)

    x = QInt{W}(ctx, 0)
    prepare!(x)

    for _ in 1:iters
        oracle!(x)
        unprepare!(x)
        _diffusion!(x)
        prepare!(x)
    end

    return Int(x)
end

# ── find: the crown jewel ───────────────────────────────────────────────────

"""
    find(oracle!::Function, ::Val{W}; n_marked::Int=1) -> Int

Search for an input satisfying the oracle using Grover's algorithm.
The user writes a phase oracle; the library finds the answer.

`oracle!(x::QInt{W})` flips the phase of marked states, typically
via `phase_flip!(x, target)`. Returns a classical Int.

# Examples

```julia
# Find the number 5
result = find(Val(3)) do x
    phase_flip!(x, 5)
end

# Find any even number
result = find(Val(3), n_marked=4) do x
    phase_flip!(x, [0, 2, 4, 6])
end
```

Ref: Grover (1996). Special case of `amplify` where A = A† = H^⊗W.
"""
function find(oracle!::Function, ::Val{W}; n_marked::Int=1) where {W}
    amplify(oracle!, _hadamard_all!, _hadamard_all!, Val(W); n_marked=n_marked)
end
