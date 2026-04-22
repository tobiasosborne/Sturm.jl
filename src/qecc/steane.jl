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

# ── Syndrome extraction + correction (bead Sturm.jl-870) ─────────────────────
#
# Stabiliser supports for the [[7,1,3]] code (both X-type and Z-type — the
# code is CSS self-dual). Each support is an NTuple{4, Int}; the stabiliser
# index k ∈ {1,2,3} corresponds to bit k-1 (LSB first) of the syndrome.
#
#   g₁ = {1, 3, 5, 7}   — syndrome bit 1 (value 1)
#   g₂ = {2, 3, 6, 7}   — syndrome bit 2 (value 2)
#   g₃ = {4, 5, 6, 7}   — syndrome bit 3 (value 4)
#
# By construction, the syndrome value in binary equals the qubit index of a
# weight-1 error (Steane 1996 eq. 17 column structure). No lookup table
# needed — the identity function IS the correction map.
const _STEANE_STAB_SUPPORTS = (
    (1, 3, 5, 7),
    (2, 3, 6, 7),
    (4, 5, 6, 7),
)

"""
    syndrome_extract!(physical::NTuple{7, QBool}) -> (sx::UInt8, sz::UInt8)

Measure the six stabilisers of the [[7,1,3]] code via the ancilla-CNOT
protocol (Steane 1996 p. 21). Returns two 3-bit syndromes:

  * `sx` — from the three Z-type stabilisers, detects X (bit-flip) errors.
    Binary value equals the qubit index of a weight-1 X error; 0 for none.
  * `sz` — from the three X-type stabilisers, detects Z (phase-flip) errors.
    Same binary-value-equals-qubit-index convention.

Protocol per stabiliser:

  * **Z-type** (detects X error): allocate ancilla in |0⟩; CX from each
    data qubit in the support to the ancilla (`anc ⊻= data[i]`); measure
    the ancilla in the Z basis. Bit is 1 iff the data has an odd-weight
    X error on the support.

  * **X-type** (detects Z error): allocate ancilla in |0⟩; H on ancilla
    → |+⟩; CX from the ancilla to each data qubit in the support
    (`data[i] ⊻= anc`); H on ancilla; measure. Bit is 1 iff the data
    has an odd-weight Z error on the support.

Each stabiliser measurement uses a fresh ancilla consumed by `Bool(anc)`.
Six ancillas total per call; auto-cleanup (bead sv3) handles any that
escape.

`physical` wires are not consumed — the extraction is non-destructive
on the data register.

**v0.1 limitation**: this routine calls `Bool(anc)` directly, so it only
works in contexts where measurement is concrete (EagerContext,
DensityMatrixContext, HardwareContext). In TracingContext `Bool(q)`
errors loudly (session 38); a `cases`-based tracing variant is deferred
to bead 870 Phase 3.
"""
function syndrome_extract!(physical::NTuple{7, QBool})
    ctx = physical[1].ctx

    # X-error syndrome via Z-type stabilisers.
    sx = UInt8(0)
    for (k, support) in enumerate(_STEANE_STAB_SUPPORTS)
        anc = QBool(0.0)
        for i in support
            anc ⊻= physical[i]
        end
        if Bool(anc)
            sx |= UInt8(1) << (k - 1)
        end
    end

    # Z-error syndrome via X-type stabilisers (Hadamard-sandwich).
    sz = UInt8(0)
    for (k, support) in enumerate(_STEANE_STAB_SUPPORTS)
        anc = QBool(0.0)
        H!(anc)
        for i in support
            # `a ⊻= b` desugars to `a = a ⊻ b` and would attempt to setindex!
            # on the immutable NTuple `physical`. `a ⊻ b` is already in-place
            # (mutates a, returns a); evaluate for the side effect and discard.
            physical[i] ⊻ anc
        end
        H!(anc)
        if Bool(anc)
            sz |= UInt8(1) << (k - 1)
        end
    end

    return (sx, sz)
end

"""
    correct!(physical::NTuple{7, QBool}, sx::UInt8, sz::UInt8)

Apply the classical-conditioned Pauli correction indicated by the syndrome.
Since the syndrome value equals the error qubit index (see
`_STEANE_STAB_SUPPORTS` comment), the correction is the identity map:

  * `sx != 0` → apply `X!` to `physical[sx]` (undo an X bit-flip)
  * `sz != 0` → apply `Z!` to `physical[sz]` (undo a Z phase-flip)

A Y error splits into both X and Z syndromes; applying X then Z recovers
the Y (Y = iXZ up to a global phase, which is unobservable at the channel
level — CLAUDE.md "Global Phase and Universality").
"""
function correct!(physical::NTuple{7, QBool}, sx::UInt8, sz::UInt8)
    if sx != 0
        X!(physical[sx])
    end
    if sz != 0
        Z!(physical[sz])
    end
    return nothing
end

"""
    decode_with_correction!(::Steane, physical::NTuple{7, QBool}) -> QBool

Full error-correcting decode: extract syndromes, apply single-qubit Pauli
correction, then run the pure-inverse [`decode!`](@ref). Any weight-1
Pauli error (X, Y, or Z on any one of the 7 physical qubits) between
encoding and decoding is recovered deterministically — the Steane code
has distance 3.

The pure-inverse `decode!` is left unchanged as a primitive; this function
is the P6 (QECC-is-a-channel) endpoint.
"""
function decode_with_correction!(code::Steane, physical::NTuple{7, QBool})
    sx, sz = syndrome_extract!(physical)
    correct!(physical, sx, sz)
    return decode!(code, physical)
end

# ── Coherent (measurement-free) syndrome correction — bead 870 P3 ────────────
#
# `syndrome_extract! + correct!` measure the 6 ancillas via `Bool(anc)` and
# apply a classical-conditioned X/Z. That pipeline errors loudly inside
# TracingContext (session 38: `Bool(q)` inside trace errors by design),
# so `encode(ch, Steane())` — which wraps its body in a `trace()` — needs
# a measurement-free variant.
#
# `syndrome_correct!` uses the same CNOT-based syndrome extraction but
# replaces "measure + classical branch" with **coherent `when()`-based
# multi-controls**: for each candidate error location j ∈ 1..7, apply the
# appropriate Pauli controlled on the 3 ancillas encoding binary(j). For
# zero-bits in binary(j), negative polarity via the X!-sandwich idiom.
# Ancillas are then `ptrace!`'d.
#
# Correctness (weight-≤1 error input):
#   - After the stabiliser CNOTs, the ancilla register holds |binary(k)⟩
#     deterministically (k = error location, 0 = no error).
#   - The 7 multi-controlled Paulis fire iff the ancilla value matches j.
#     Exactly one fires (or none for k=0), correcting the error.
#   - Data and ancillas end up in a product state (data = codeword,
#     ancillas = |binary(k)⟩), so the ptrace! acts on a classical bitstring
#     register and yields the corrected data without residual entanglement.
#
# Runs in any context that supports `when()` + `ptrace!` — i.e. every
# concrete context (Eager/Density/Hardware) and TracingContext.

"""
Internal: apply `action()` coherently, controlled on the 3 ancillas `ancs`
jointly encoding the binary value `j` (bit 0 ↔ ancs[1], bit 1 ↔ ancs[2],
bit 2 ↔ ancs[3]). Uses the standard X!-sandwich idiom to flip polarity
on zero-bits. `j` must satisfy 1 ≤ j ≤ 7.
"""
function _when_ancs_equal!(ancs::NTuple{3, QBool}, j::Int, action::Function)
    @assert 1 <= j <= 7 "_when_ancs_equal!: j must be in 1..7 (got $j)"
    b1 = (j & 1) != 0
    b2 = (j & 2) != 0
    b3 = (j & 4) != 0
    # Invert polarity on bits that are 0 in binary(j).
    b1 || X!(ancs[1])
    b2 || X!(ancs[2])
    b3 || X!(ancs[3])
    when(ancs[1]) do
        when(ancs[2]) do
            when(ancs[3]) do
                action()
            end
        end
    end
    # Restore polarity — X! is self-inverse (its channel is X, X·X = I).
    b1 || X!(ancs[1])
    b2 || X!(ancs[2])
    b3 || X!(ancs[3])
    return nothing
end

"""
    syndrome_correct!(physical::NTuple{7, QBool})

Coherent (measurement-free) syndrome extraction + correction for the Steane
[[7,1,3]] code. Equivalent to `syndrome_extract! + correct!` as a channel
on the data register, but uses `when()`-based multi-controls instead of
`Bool(anc)` + classical branching, so it runs in TracingContext (needed
by `encode(ch, Steane())`).

Protocol per basis (Steane 1996 §3.3–3.5, Theorem 6; p. 21 ancilla-CNOT):

  1. Allocate 3 fresh ancillas in |0⟩ (for Z-basis: also H to |+⟩).
  2. For each of the 3 stabilisers k ∈ {1,2,3}, CNOT from each data qubit
     in the support to ancilla k (for Z-basis: from ancilla to data, with
     H-sandwich on the ancilla).
  3. For each candidate error location j ∈ 1..7, apply the corresponding
     Pauli (X or Z) to `physical[j]` controlled on the 3 ancillas
     encoding binary(j). Only one fires for weight-1 errors.
  4. `ptrace!` the 3 ancillas — they hold classical syndrome bits,
     product-state with the corrected data, so tracing is clean.

Then repeat for the other basis (X-type stabilisers detect Z errors).

`physical` wires are not consumed.
"""
function syndrome_correct!(physical::NTuple{7, QBool})
    # ── Basis 1: Z-type stabilisers detect X errors (corrected with X!) ─────
    # NTuple immutability: `sx_ancs[k] ⊻= physical[i]` desugars to a
    # setindex! on the tuple and errors. The raw `a ⊻ b` primitive is
    # in-place on `a` — same idiom used on the NTuple data side of
    # syndrome_extract! for the X-type stabilisers.
    sx_ancs = ntuple(_ -> QBool(0.0), 3)
    for (k, support) in enumerate(_STEANE_STAB_SUPPORTS)
        for i in support
            sx_ancs[k] ⊻ physical[i]
        end
    end
    for j in 1:7
        _when_ancs_equal!(sx_ancs, j, () -> X!(physical[j]))
    end
    for anc in sx_ancs; ptrace!(anc); end

    # ── Basis 2: X-type stabilisers detect Z errors (corrected with Z!) ─────
    # H-sandwich: CX ancilla→data under H conjugation = CZ. Equivalent to
    # measuring the X-basis parity of the data support.
    sz_ancs = ntuple(_ -> QBool(0.0), 3)
    for anc in sz_ancs; H!(anc); end
    for (k, support) in enumerate(_STEANE_STAB_SUPPORTS)
        for i in support
            # NTuple immutability: `a ⊻= b` desugars to a setindex!. The raw
            # `a ⊻ b` primitive is already in-place (see syndrome_extract!).
            physical[i] ⊻ sz_ancs[k]
        end
    end
    for anc in sz_ancs; H!(anc); end
    for j in 1:7
        _when_ancs_equal!(sz_ancs, j, () -> Z!(physical[j]))
    end
    for anc in sz_ancs; ptrace!(anc); end

    return nothing
end
