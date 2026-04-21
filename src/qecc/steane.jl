# Steane [[7,1,3]] code: encodes 1 logical qubit into 7 physical qubits.
# Can correct any single-qubit error (distance 3).
#
# Ref: Steane, "Multiple Particle Interference and Quantum Error Correction",
# arXiv:quant-ph/9601029v3, 1996. See docs/physics/steane_1996.pdf.
# Encoder: Figure 3, §3.3. Generator matrix G_s: equation (5).
# Target codeword state: |C⟩ = |G_s⟩ from equation (6) with all φ_j = 0.
#
# The code is a CSS code based on the classical [7,4,3] Hamming code, with
# stabilizers given by the rows of G_s as both X-type and Z-type operators.
#
# Stabilizer generators (X-type, from rows of G_s eq. 5):
#   g1 = X₁X₃X₅X₇    (row 3 of G_s: positions where row 3 has 1)
#   g2 = X₂X₃X₆X₇    (row 2 of G_s)
#   g3 = X₄X₅X₆X₇    (row 1 of G_s)
#
# Stabilizer generators (Z-type, same positions):
#   g4 = Z₁Z₃Z₅Z₇
#   g5 = Z₂Z₃Z₆Z₇
#   g6 = Z₄Z₅Z₆Z₇
#
# Logical operators (transversal):
#   X_L = X₁X₂X₃X₄X₅X₆X₇
#   Z_L = Z₁Z₂Z₃Z₄Z₅Z₆Z₇
#
# Codewords (|C⟩ = logical |0⟩_L, orbit of |0000000⟩ under stabilizer group):
#   |0000000⟩, |1010101⟩, |0110011⟩, |1100110⟩,
#   |0001111⟩, |1011010⟩, |0111100⟩, |1101001⟩
# and |¬C⟩ = logical |1⟩_L = |C⟩ ⊕ |1111111⟩.

"""
    Steane <: AbstractCode

The Steane [[7,1,3]] quantum error-correcting code.
"""
struct Steane <: AbstractCode end

"""
    encode!(::Steane, logical::QBool) -> NTuple{7, QBool}

Encode a logical qubit into 7 physical qubits using the Steane code.
Maps α|0⟩ + β|1⟩ → α|C⟩ + β|¬C⟩ where |C⟩ is the [[7,1,3]] codeword
state (Steane 1996 eq. 6 with φ_j = 0).

Implements Steane 1996 Figure 3 exactly. The logical qubit is placed
internally at physical position 3 (matching the paper's |00Q0000⟩
initial state). Post-encoding, all 7 qubits are transversally entangled;
no single output index is the "logical qubit" — the information is
spread across all seven.

The input `logical` is consumed; 7 fresh `QBool` wrappers are returned.
"""
function encode!(::Steane, logical::QBool)
    check_live!(logical)
    ctx = logical.ctx

    # Physical qubits: q[3] = logical input, q[1,2,4,5,6,7] = fresh ancillas |0⟩
    # Initial state: |00Q0000⟩ per Steane 1996 Fig 3.
    q = Vector{QBool}(undef, 7)
    for i in 1:7
        if i == 3
            q[i] = logical
        else
            wire = allocate!(ctx)
            q[i] = QBool(wire, ctx, false)
        end
    end

    # Step 1: Two CNOTs from data qubit q[3] — per Steane 1996 page 18.
    # Transforms |1⟩_Q ancilla-start from |0010000⟩ to |0010110⟩ ∉ |C⟩,
    # ensuring logical |1⟩ encodes to |¬C⟩ after the generator fan-out.
    q[5] ⊻= q[3]
    q[6] ⊻= q[3]

    # Step 2: Hadamard on the three "pivot" positions of G_s (eq. 5).
    # Columns 1, 2, 4 of G_s each have exactly one `1` (rows 3, 2, 1 resp.).
    # These seed the equal-weight superposition over the code.
    H!(q[1])
    H!(q[2])
    H!(q[4])

    # Step 3: CNOT fan-out per row of G_s — each pivot qubit broadcasts to
    # the other positions in its stabilizer's support.
    # q[1] broadcasts g1 = X₁X₃X₅X₇ to targets {3, 5, 7}.
    q[3] ⊻= q[1]
    q[5] ⊻= q[1]
    q[7] ⊻= q[1]

    # q[2] broadcasts g2 = X₂X₃X₆X₇ to targets {3, 6, 7}.
    q[3] ⊻= q[2]
    q[6] ⊻= q[2]
    q[7] ⊻= q[2]

    # q[4] broadcasts g3 = X₄X₅X₆X₇ to targets {5, 6, 7}.
    q[5] ⊻= q[4]
    q[6] ⊻= q[4]
    q[7] ⊻= q[4]

    # Transfer ownership: mark input QBool consumed; rewrap all wires fresh.
    logical.consumed = true
    out = ntuple(i -> QBool(q[i].wire, ctx, false), 7)
    return out
end

"""
    decode!(::Steane, physical::NTuple{7, QBool}) -> QBool

Decode the Steane code: extract the logical qubit by inverting the encoder.
For v0.1: pure circuit inverse (no syndrome extraction, no correction).
Full error correction via syndrome measurement is deferred to Sturm.jl-971.

Returns the logical qubit (recovered at internal position 3). The six
ancilla qubits are discarded (return to |0⟩ in the error-free case).
"""
function decode!(::Steane, physical::NTuple{7, QBool})
    q = collect(physical)

    # Reverse-order inverse of the encoder. CNOT and H are self-inverse
    # (up to an unphysical global phase from H!² = -I on each ancilla).

    # Undo Step 3: CNOT fan-outs in reverse.
    q[7] ⊻= q[4]; q[6] ⊻= q[4]; q[5] ⊻= q[4]
    q[7] ⊻= q[2]; q[6] ⊻= q[2]; q[3] ⊻= q[2]
    q[7] ⊻= q[1]; q[5] ⊻= q[1]; q[3] ⊻= q[1]

    # Undo Step 2: Hadamard (self-inverse).
    H!(q[4])
    H!(q[2])
    H!(q[1])

    # Undo Step 1: initial CNOTs from q[3].
    q[6] ⊻= q[3]
    q[5] ⊻= q[3]

    # Partial-trace the six ancilla qubits (positions 1, 2, 4, 5, 6, 7).
    for i in (1, 2, 4, 5, 6, 7)
        ptrace!(q[i])
    end

    return q[3]  # logical qubit recovered at position 3
end
