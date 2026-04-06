# Compile exp(-iθ P₁⊗P₂⊗…⊗Pₙ) into the 4 Sturm DSL primitives.
#
# Algorithm (standard Pauli gadget decomposition):
#   1. Basis change: rotate each non-Z, non-I site into the Z eigenbasis
#   2. CNOT staircase: compute parity of all active qubits onto a pivot
#   3. Rz(2θ) on the pivot qubit (factor of 2: Rz(φ) = exp(-iφZ/2))
#   4. Reverse CNOT staircase
#   5. Reverse basis change
#
# ═══════════════════════════════════════════════════════════════════════════
# PHYSICS DERIVATION — Basis changes
# ═══════════════════════════════════════════════════════════════════════════
#
# We need V_k such that V_k · P_k · V_k† = Z for each non-I site.
# Then: exp(-iθ P) = (⊗_k V_k†) · exp(-iθ Z^⊗m) · (⊗_k V_k)
#
# ── Z site: V = I (already diagonal) ──
#
# ── X site: V = Ry(-π/2) ──
#   Proof: Ry(-π/2) · X · Ry(π/2) = ?
#   Ry(θ) = [[cos(θ/2), -sin(θ/2)], [sin(θ/2), cos(θ/2)]]
#   Let c = s = 1/√2 (for θ = ±π/2).
#   Ry(-π/2) = [[c, s], [-s, c]]
#   Ry(π/2)  = [[c, -s], [s, c]]
#   X · Ry(π/2) = [[0,1],[1,0]] · (1/√2)[[1,-1],[1,1]] = (1/√2)[[1,1],[1,-1]]
#   Ry(-π/2) · X · Ry(π/2) = (1/√2)[[c,s],[-s,c]] · (1/√2)[[1,1],[1,-1]]
#     R0C0: c + s = √2 · (1/√2) = 1.  R0C1: c - s = 0.
#     R1C0: -s + c = 0.                R1C1: -s - c = -√2 · (1/√2) = -1.
#   Result: [[1,0],[0,-1]] = Z  ✓
#
#   In primitives:
#     Basis change:   q.θ -= π/2   (Ry(-π/2))
#     Undo:           q.θ += π/2   (Ry(π/2))
#
# ── Y site: V = Rx(π/2) ──
#   Proof: Rx(π/2) = cos(π/4)I - i sin(π/4)X = (I - iX)/√2
#   Rx(π/2) · Y · Rx(-π/2):
#     Rx(-π/2) = (I + iX)/√2
#     Y · Rx(-π/2) = (1/√2)(Y + iYX) = (1/√2)(Y + i(iZ)) = (1/√2)(Y - Z)
#       where YX = [[0,-i],[i,0]][[0,1],[1,0]] = [[−i,0],[0,i]] = iZ ✓
#     Rx(π/2) · (1/√2)(Y - Z) = (1/2)(I - iX)(Y - Z)
#       = (1/2)(Y - Z - iXY + iXZ)
#       XY = [[0,1],[1,0]][[0,-i],[i,0]] = [[i,0],[0,-i]] = -iZ
#       XZ = [[0,1],[1,0]][[1,0],[0,-1]] = [[0,-1],[1,0]] = iY
#       = (1/2)(Y - Z - i(-iZ) + i(iY))
#       = (1/2)(Y - Z - Z - Y)
#       = (1/2)(-2Z) = -Z
#
#   Hmm, that gives -Z! Let me redo with opposite convention.
#   We need V† · Z · V = Y, i.e., V · Y · V† = Z.
#   Rx(π/2)·Y·Rx(-π/2) = -Z means Rx(-π/2)·(-Z)·Rx(π/2) = Y,
#   equivalently Rx(-π/2)·Z·Rx(π/2) = -Y.
#   So try V = Rx(-π/2) instead:
#   Rx(-π/2) · Y · Rx(π/2) = (Rx(π/2) · Y · Rx(-π/2))† = (-Z)† = -Z. Same!
#
#   The issue: both Rx(±π/2) give Z → ±Y, never exactly Y. But the sign
#   goes into the Rz angle: V† · exp(-iθZ) · V = exp(-iθ V†ZV).
#   If V†ZV = -Y: exp(-iθ(-Y)) = exp(+iθY).
#   If V†ZV = +Y: exp(-iθY) ← this is what we want.
#
#   Let me carefully redo V = Rx(π/2):
#   V†·Z·V = Rx(-π/2)·Z·Rx(π/2) = ?
#
#   Rx(π/2)  = (1/√2)[[1, -i], [-i, 1]]
#   Rx(-π/2) = (1/√2)[[1, i], [i, 1]]
#
#   Z · Rx(π/2) = [[1,0],[0,-1]] · (1/√2)[[1,-i],[-i,1]] = (1/√2)[[1,-i],[i,-1]]
#   Rx(-π/2) · Z · Rx(π/2) = (1/√2)[[1,i],[i,1]] · (1/√2)[[1,-i],[i,-1]]
#     = (1/2)[[1+i², -i-i], [i+i, -i²-1]]
#     i² = -1.
#     R0C0: 1+(-1)·i ... no, element-by-element:
#     R0C0: 1·1 + i·i = 1 + i² = 1 - 1 = 0
#     R0C1: 1·(-i) + i·(-1) = -i - i = -2i
#     R1C0: i·1 + 1·i = 2i
#     R1C1: i·(-i) + 1·(-1) = -i² - 1 = 1 - 1 = 0
#     = (1/2)[[0, -2i], [2i, 0]] = [[0, -i], [i, 0]] = Y  ✓✓✓
#
#   So V = Rx(π/2) gives V†·Z·V = Y. Perfect!
#
#   Rx(π/2) in Euler ZYZ decomposition:
#     Rx(θ) = Rz(-π/2) · Ry(θ) · Rz(π/2)
#   Proof (verified in Proposer B's derivation and confirmed numerically):
#     Rz(-π/2)·Ry(π/2)·Rz(π/2)
#     = [[e^{iπ/4},0],[0,e^{-iπ/4}]] · [[c,-s],[s,c]] · [[e^{-iπ/4},0],[0,e^{iπ/4}]]
#     Entry (1,2): e^{iπ/4}·(-s)·e^{iπ/4} = -s·e^{iπ/2} = -s·i = -i/√2
#     Entry (2,1): e^{-iπ/4}·s·e^{-iπ/4} = s·e^{-iπ/2} = -is = -i/√2
#     = (1/√2)[[1, -i], [-i, 1]] = Rx(π/2) ✓
#
#   In Sturm primitives (temporal order = left to right):
#     Basis change Rx(π/2):     q.φ += π/2;  q.θ += π/2;  q.φ -= π/2
#     Undo Rx(-π/2):            q.φ += π/2;  q.θ -= π/2;  q.φ -= π/2
#
# ═══════════════════════════════════════════════════════════════════════════
# CNOT staircase: parity computation
# ═══════════════════════════════════════════════════════════════════════════
#
# After diagonalisation, we need exp(-iθ Z⊗Z⊗…⊗Z) on the m active qubits.
# Z^⊗m has eigenvalue (-1)^{b₁+…+bₘ} on |b₁…bₘ⟩ — it depends only on
# the PARITY. We compute parity into a single pivot via a CNOT cascade:
#
#   For active qubits [i₁, i₂, …, iₘ]: iₘ is the pivot.
#   Apply: i₂ ⊻= i₁, i₃ ⊻= i₂, …, iₘ ⊻= iₘ₋₁
#   Now iₘ holds ⊕ of all active qubits.
#   Apply Rz(2θ) to iₘ (factor of 2: Rz(φ) = exp(-iφZ/2)).
#   Reverse the CNOT cascade.
#
# Ref: Whitfield et al. (2011), arXiv:1001.3855, Section 4.
#      Local PDF: docs/literature/quantum_simulation/applications_chemistry/1001.3855.pdf

"""
    _basis_change!(q::QBool, op::PauliOp)

Rotate the Pauli eigenbasis to the Z eigenbasis.
After this, the Pauli operator on this qubit is equivalent to Z.

- pauli_I: error (should not be called on identity sites)
- pauli_Z: no-op (already diagonal)
- pauli_X: Ry(-π/2) maps X → Z
- pauli_Y: Rx(π/2) = Rz(-π/2)·Ry(π/2)·Rz(π/2) maps Y → Z

See full derivation at top of this file.
"""
@inline function _basis_change!(q::QBool, op::PauliOp)
    if op == pauli_Z
        return
    elseif op == pauli_X
        q.θ -= π/2
    elseif op == pauli_Y
        q.φ += π/2
        q.θ += π/2
        q.φ -= π/2
    else
        error("_basis_change!: unexpected PauliOp $op (identity sites should be skipped)")
    end
end

"""
    _basis_unchange!(q::QBool, op::PauliOp)

Inverse of `_basis_change!`.
- pauli_Z: no-op
- pauli_X: Ry(+π/2)
- pauli_Y: Rx(-π/2) = Rz(-π/2)·Ry(-π/2)·Rz(π/2)
"""
@inline function _basis_unchange!(q::QBool, op::PauliOp)
    if op == pauli_Z
        return
    elseif op == pauli_X
        q.θ += π/2
    elseif op == pauli_Y
        q.φ += π/2
        q.θ -= π/2
        q.φ -= π/2
    else
        error("_basis_unchange!: unexpected PauliOp $op")
    end
end

"""
    pauli_exp!(qubits::Vector{QBool}, term::PauliTerm{N}, theta::Real)

Apply exp(-i θ h P₁⊗…⊗Pₙ) to the given qubits, where h = term.coeff
and Pⱼ = term.ops[j]. The total rotation angle is θ·h.

The all-identity term is a global phase (unphysical for channels) and is skipped.

Gate count: 2·|S| single-qubit rotations + 2·(|S|-1) CNOTs + 1 Rz,
where |S| is the number of non-identity sites.

Ref: Whitfield et al. (2011), arXiv:1001.3855, Section 4.
"""
function pauli_exp!(qubits::Vector{QBool}, term::PauliTerm{N}, theta::Real) where {N}
    length(qubits) == N || error(
        "pauli_exp!: expected $N qubits for PauliTerm{$N}, got $(length(qubits))")
    for q in qubits; check_live!(q); end

    _support_count(term) == 0 && return nothing   # all-identity = global phase

    angle = 2.0 * theta * term.coeff

    # Step 1: basis change (rotate non-Z,non-I sites to Z basis)
    @inbounds for k in 1:N
        term.ops[k] != pauli_I && _basis_change!(qubits[k], term.ops[k])
    end

    # Step 2: CNOT staircase (compute parity onto last active qubit)
    # Walk active sites left-to-right; each XORs into the next active site.
    prev_active = 0
    last_active = 0
    @inbounds for k in 1:N
        if term.ops[k] != pauli_I
            if prev_active > 0
                qubits[k] ⊻= qubits[prev_active]
            end
            prev_active = k
            last_active = k
        end
    end

    # Step 3: Rz(2·θ·h) on the pivot (last active qubit)
    @inbounds qubits[last_active].φ += angle

    # Step 4: reverse CNOT staircase
    prev_active = 0
    @inbounds for k in N:-1:1
        if term.ops[k] != pauli_I
            if prev_active > 0
                qubits[prev_active] ⊻= qubits[k]
            end
            prev_active = k
        end
    end

    # Step 5: reverse basis change
    @inbounds for k in N:-1:1
        term.ops[k] != pauli_I && _basis_unchange!(qubits[k], term.ops[k])
    end

    return nothing
end

"""
    pauli_exp!(reg::QInt{W}, term::PauliTerm{W}, theta::Real)

Convenience: apply exp(-iθhP) to a QInt register.
"""
function pauli_exp!(reg::QInt{W}, term::PauliTerm{W}, theta::Real) where {W}
    check_live!(reg)
    ctx = reg.ctx
    qubits = [QBool(reg.wires[i], ctx, false) for i in 1:W]
    pauli_exp!(qubits, term, theta)
    return nothing
end
