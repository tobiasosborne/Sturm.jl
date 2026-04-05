# Steane [[7,1,3]] code: encodes 1 logical qubit into 7 physical qubits.
# Can correct any single-qubit error (distance 3).
#
# Ref: Steane, "Error Correcting Codes in Quantum Theory",
# Phys. Rev. Lett. 77, 793 (1996). See docs/physics/steane_1996.pdf.
#
# Encoding circuit uses the stabilizer generators of the code.
# The Steane code is a CSS code based on the classical [7,4,3] Hamming code.
#
# Stabilizer generators (X-type):
#   g1 = X₁X₃X₅X₇
#   g2 = X₂X₃X₆X₇
#   g3 = X₄X₅X₆X₇
#
# Stabilizer generators (Z-type):
#   g4 = Z₁Z₃Z₅Z₇
#   g5 = Z₂Z₃Z₆Z₇
#   g6 = Z₄Z₅Z₆Z₇
#
# Logical operators:
#   X_L = X₁X₂X₃X₄X₅X₆X₇
#   Z_L = Z₁Z₂Z₃Z₄Z₅Z₆Z₇

"""
    Steane <: AbstractCode

The Steane [[7,1,3]] quantum error-correcting code.
"""
struct Steane <: AbstractCode end

"""
    encode!(::Steane, logical::QBool) -> NTuple{7, QBool}

Encode a logical qubit into 7 physical qubits using the Steane code.

The logical qubit state α|0⟩ + β|1⟩ is mapped to:
  α|0₇⟩_L + β|1₇⟩_L

where |0₇⟩_L and |1₇⟩_L are the 7-qubit codewords.

Encoding circuit (from stabilizer generators):
  1. Place logical qubit on physical qubit 1
  2. Prepare ancillas 2-7 in |0⟩
  3. Apply CNOT network to entangle according to Hamming parity checks
"""
function encode!(::Steane, logical::QBool)
    check_live!(logical)
    ctx = logical.ctx

    # Physical qubits: q1 = logical, q2-q7 = fresh ancillas in |0⟩
    q = Vector{QBool}(undef, 7)
    q[1] = logical

    for i in 2:7
        wire = allocate!(ctx)
        q[i] = QBool(wire, ctx, false)
    end

    # Step 1: Prepare |+⟩ on ancilla qubits 4, 5, 6, 7
    # (These will spread the X stabilizers)
    H!(q[4])
    H!(q[5])
    H!(q[6])
    H!(q[7])

    # Step 2: CNOT network for X-type stabilizers
    # g3 = X₄X₅X₆X₇: q4 controls q5, q6 (already in superposition via H)
    # The encoding uses CNOTs from the H'd ancillas to create the code space

    # Hamming parity matrix for [7,4,3]:
    # bit 1: checks 1,3,5,7 (parity of positions with bit 0 set)
    # bit 2: checks 2,3,6,7 (parity of positions with bit 1 set)
    # bit 3: checks 4,5,6,7 (parity of positions with bit 2 set)

    # CNOT from q4 → q1, q2, q3 (spread X stabilizer g3 pattern)
    q[1] ⊻= q[4]
    q[2] ⊻= q[5]
    q[3] ⊻= q[4]
    q[3] ⊻= q[5]

    # Additional CNOTs for the full code
    q[1] ⊻= q[6]
    q[2] ⊻= q[6]
    q[1] ⊻= q[7]
    q[2] ⊻= q[7]
    q[3] ⊻= q[7]

    # Create fresh QBool wrappers for the output (logical is absorbed)
    logical.consumed = true
    out = ntuple(i -> QBool(q[i].wire, ctx, false), 7)
    return out
end

"""
    decode!(::Steane, physical::NTuple{7, QBool}) -> QBool

Decode the Steane code: extract logical qubit from 7 physical qubits.
For v0.1: inverse of encoding circuit (no error correction syndrome).
Full syndrome extraction and correction deferred.
"""
function decode!(::Steane, physical::NTuple{7, QBool})
    q = collect(physical)
    ctx = q[1].ctx

    # Inverse of encoding: reverse CNOT order
    q[3] ⊻= q[7]
    q[2] ⊻= q[7]
    q[1] ⊻= q[7]
    q[2] ⊻= q[6]
    q[1] ⊻= q[6]
    q[3] ⊻= q[5]
    q[3] ⊻= q[4]
    q[2] ⊻= q[5]
    q[1] ⊻= q[4]

    # Undo H on ancillas
    H!(q[4])
    H!(q[5])
    H!(q[6])
    H!(q[7])

    # Discard ancillas (should be |0⟩ if no errors)
    for i in 2:7
        discard!(q[i])
    end

    return q[1]  # logical qubit recovered
end
