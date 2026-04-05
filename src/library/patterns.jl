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
