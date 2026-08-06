# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M11 (bead Sturm.jl-qmpo), design
# `docs/design/m11-82su-synthesis.md` §3.3 (rulings S17–S20): the CODE VALUES —
# `StabilizerCode{N,K,S}` (the gauge-free code space + logical operators,
# validated over GF(2) with no floats) and `CodeEncoding{C,N,K}` (the GAUGE
# CHOICE: a concrete encoder circuit + a self-validating syndrome table). The
# separation is S19: two codes with identical stabilizers but different
# encoding circuits are the SAME code under DIFFERENT encodings — folding the
# encoder into the code value would re-import the F8 conflation one level down.
#
# Physics grounding:
#   docs/physics/gottesman_1997_stabilizer_codes.md — §3.2 stabilizer
#     formalism, [[n,k,d]], syndrome measurement, logical operators (the six
#     construction invariants below are its well-formedness conditions).
#   docs/physics/knill_laflamme_1997_qec_conditions.md — Thm 3.2 (basis form;
#     the projector spelling is the textbooks'): why a validated table decoder
#     is EXACT on the declared correctable set, and why `Θ(𝓝) = id_L` is the
#     correctability STATEMENT, not a precondition (KL Thm 3.3).
#   docs/physics/repetition_code_effective_noise.md — the [[3,1,1]] worked
#     numbers the M11 tests pin (p_L = 3p² − 2p³; break-even exactly p = ½;
#     phase-noise amplification (1−(1−2p)³)/2).
#
# SYNDROME BIT ORDER (pinned HERE, once): generator `i` contributes bit
# `2^(i−1)` — generator 1 is the LSB. This matches the synthesis §5 acceptance
# arm map (X₁ anticommutes with g₁ = Z₁Z₂ only ⇒ σ = 1). It is a CLASSICAL
# integer built from the generator LIST, not a register readout — the M6
# wire-1-=-MSB pin governs wires, not this index.

# --- GF(2) symplectic helpers (bitmask rows; no floats — S17) -----------------

# One generator as a 2N-bit GF(2) row: (x-mask, z-mask).
_gf2_row(w::PauliWord) = (w.x, w.z)

# Gaussian elimination over GF(2) on (x, z) mask pairs. Returns the reduced
# pivot rows (a basis of the span).
function _gf2_basis(rows::Vector{NTuple{2,UInt64}})
    basis = NTuple{2,UInt64}[]
    for r in rows
        x, z = r
        for (bx, bz) in basis
            # reduce by the basis row's leading bit
            lead = _gf2_lead(bx, bz)
            if _gf2_bit(x, z, lead)
                x ⊻= bx; z ⊻= bz
            end
        end
        (x == 0 && z == 0) || push!(basis, (x, z))
        # keep basis in reduced order: sort by leading bit for determinism
        sort!(basis; by = r2 -> _gf2_lead(r2[1], r2[2]), rev = true)
    end
    return basis
end

# The leading (highest) set bit position of the 128-bit row (x ≪ 64 | z view).
_gf2_lead(x::UInt64, z::UInt64) = x != 0 ? 64 + (63 - leading_zeros(x)) :
                                            (63 - leading_zeros(z))
_gf2_bit(x::UInt64, z::UInt64, pos::Int) =
    pos >= 64 ? ((x >> (pos - 64)) & 1) == 1 : ((z >> pos) & 1) == 1

# Is `w`'s row in the GF(2) span of `basis`?
function _gf2_in_span(basis::Vector{NTuple{2,UInt64}}, w::PauliWord)
    x, z = _gf2_row(w)
    for (bx, bz) in basis
        lead = _gf2_lead(bx, bz)
        if _gf2_bit(x, z, lead)
            x ⊻= bx; z ⊻= bz
        end
    end
    return x == 0 && z == 0
end

# --- The code value (S17) -----------------------------------------------------

"""
    StabilizerCode{N,K,S}

An `[[N, K]]` stabilizer code: `S = N − K` generators (`PauliWord{N}` +
`signs` — `PauliWord` is deliberately sign-free, V13, so a code with a `−1`
generator is unrepresentable without the field), `K` logical X/Z pairs, and a
`declared_distance` (an honest DECLARATION — `verify_distance` computes the
truth by brute force for N ≤ 8; the M11 bit-flip code has distance 1, and the
suite refuses to imply otherwise).

Validated at construction over GF(2), no floats (S17):
  1. `S == N − K`; no identity generator;
  2. generators pairwise commute;
  3. symplectic (GF(2)) rank of the generator set is `S` — independent;
  4. every logical commutes with every generator (normaliser membership);
  5. `X̄ᵢ` anticommutes with `Z̄ᵢ` and commutes with `Z̄ⱼ` (j ≠ i); logicals
     commute within each family;
  6. no logical lies in the stabilizer GROUP (GF(2) span — else it would act
     trivially on the code space).
"""
struct StabilizerCode{N,K,S}
    name::Symbol
    stabilizers::NTuple{S,PauliWord{N}}
    signs::NTuple{S,Int8}
    logical_x::NTuple{K,PauliWord{N}}
    logical_z::NTuple{K,PauliWord{N}}
    declared_distance::Int
    function StabilizerCode{N,K,S}(name::Symbol, stabs::NTuple{S,PauliWord{N}},
                                   signs::NTuple{S,Int8},
                                   lx::NTuple{K,PauliWord{N}},
                                   lz::NTuple{K,PauliWord{N}},
                                   declared_distance::Int) where {N,K,S}
        S == N - K || throw(ArgumentError(
            "StabilizerCode: S = $S generators but N − K = $(N - K)"))
        for σ in signs
            σ == 1 || σ == -1 || throw(ArgumentError(
                "StabilizerCode: generator signs must be ±1 (got $σ)"))
        end
        for (i, g) in enumerate(stabs)
            is_identity(g) && throw(ArgumentError(
                "StabilizerCode: generator $i is the identity"))
        end
        for i in 1:S, j in (i + 1):S
            commutes(stabs[i], stabs[j]) || throw(ArgumentError(
                "StabilizerCode: generators $i and $j anticommute — not a stabilizer group"))
        end
        basis = _gf2_basis(NTuple{2,UInt64}[_gf2_row(g) for g in stabs])
        length(basis) == S || throw(ArgumentError(
            "StabilizerCode: generators are GF(2)-dependent (symplectic rank " *
            "$(length(basis)) < S = $S) — remove the redundant generator"))
        for (fam, ops) in ((:X̄, lx), (:Z̄, lz))
            for (i, L) in enumerate(ops)
                for (j, g) in enumerate(stabs)
                    commutes(L, g) || throw(ArgumentError(
                        "StabilizerCode: logical $fam$i anticommutes with generator $j — " *
                        "not in the normaliser"))
                end
                _gf2_in_span(basis, L) && throw(ArgumentError(
                    "StabilizerCode: logical $fam$i lies in the stabilizer group — " *
                    "it acts trivially on the code space"))
            end
        end
        for i in 1:K, j in 1:K
            if i == j
                commutes(lx[i], lz[i]) && throw(ArgumentError(
                    "StabilizerCode: X̄$i and Z̄$i commute — a logical pair must anticommute"))
            else
                commutes(lx[i], lz[j]) || throw(ArgumentError(
                    "StabilizerCode: X̄$i and Z̄$j anticommute — logical pairs must be disjoint"))
            end
            i < j && (commutes(lx[i], lx[j]) || throw(ArgumentError(
                "StabilizerCode: X̄$i and X̄$j anticommute")))
            i < j && (commutes(lz[i], lz[j]) || throw(ArgumentError(
                "StabilizerCode: Z̄$i and Z̄$j anticommute")))
        end
        return new{N,K,S}(name, stabs, signs, lx, lz, declared_distance)
    end
end

function StabilizerCode(name::Symbol, stabs, signs, lx, lz, declared_distance::Int)
    isempty(stabs) && isempty(lx) && throw(ArgumentError(
        "StabilizerCode: need at least one generator or logical to fix N"))
    N = _pw_width(isempty(stabs) ? first(lx) : first(stabs))
    S = length(stabs)
    K = length(lx)
    length(lz) == K || throw(ArgumentError(
        "StabilizerCode: $(length(lx)) X̄ vs $(length(lz)) Z̄ logicals"))
    return StabilizerCode{N,K,S}(name, Tuple(stabs), NTuple{S,Int8}(Int8.(signs)),
                                 Tuple(lx), Tuple(lz), declared_distance)
end
_pw_width(::PauliWord{N}) where {N} = N

nphysical(::StabilizerCode{N}) where {N} = N
nlogical(::StabilizerCode{N,K}) where {N,K} = K
stabilizers(c::StabilizerCode) = c.stabilizers
distance(c::StabilizerCode) = c.declared_distance

"""
    syndrome(code::StabilizerCode{N,K,S}, err::PauliWord{N}) -> Int

The syndrome of a Pauli error: bit `i−1` (generator 1 = LSB — the pin in this
file's header) is 1 iff `err` anticommutes with generator `i`. Exact GF(2)
symplectic arithmetic, no floats.
"""
function syndrome(code::StabilizerCode{N,K,S}, err::PauliWord{N}) where {N,K,S}
    σ = 0
    for i in 1:S
        commutes(code.stabilizers[i], err) || (σ |= 1 << (i - 1))
    end
    return σ
end

"""
    verify_distance(code::StabilizerCode{N}) -> Int

The TRUE distance, by brute force (N ≤ 8): the minimum weight of a Pauli word
that commutes with every generator yet lies outside the stabilizer group — a
non-trivial logical operator. Use it in tests instead of trusting
`declared_distance` (the M11 bit-flip code declares — and verifies to — 1).
"""
function verify_distance(code::StabilizerCode{N,K,S}) where {N,K,S}
    N <= 8 || throw(ArgumentError(
        "verify_distance: brute force is 4^N — capped at N = 8 (got N = $N)"))
    basis = _gf2_basis(NTuple{2,UInt64}[_gf2_row(g) for g in code.stabilizers])
    best = N + 1
    for xm in 0:(2^N - 1), zm in 0:(2^N - 1)
        (xm == 0 && zm == 0) && continue
        w = PauliWord{N}(UInt64(xm), UInt64(zm))
        wt = count_ones(UInt64(xm) | UInt64(zm))
        wt >= best && continue
        all(g -> commutes(g, w), code.stabilizers) || continue
        _gf2_in_span(basis, w) && continue
        best = wt
    end
    best <= N || error("verify_distance: no logical operator found — not a valid [[N,K>0]] code?")
    return best
end

# --- The encoding value (S19/S20) ---------------------------------------------

"""
    CodeEncoding{C,N,K}

A GAUGE CHOICE for a code (S19): the `code`, a concrete `encoder` (a certified
`UnitaryBlock{N}` — the unitary part of `E = U ∘ (· ⊗ |0⟩^{N−K})`; the decoder
is `adjoint(encoder)`, EXACT by construction — S18), and the syndrome
`corrections` table (`2^S` entries, `corrections[σ+1]` is applied on syndrome
σ). The table is SELF-VALIDATING at construction (S20):
`syndrome(code, corrections[σ+1]) == σ` for every σ — a mis-entered table is a
construction error, not a silent physics bug (risk R-d). What it does NOT
check: minimum weight. That is decoder QUALITY, not well-formedness — a valid
table that corrects to the wrong coset representative yields a worse (but
honestly computed) logical channel.
"""
struct CodeEncoding{C<:StabilizerCode,N,K}
    code::C
    encoder::UnitaryBlock{N}
    corrections::Vector{PauliWord{N}}
    function CodeEncoding(code::StabilizerCode{N,K,S},
                          encoder::UnitaryBlock{N},
                          corrections::AbstractVector{PauliWord{N}}) where {N,K,S}
        length(corrections) == 2^S || throw(ArgumentError(
            "CodeEncoding: table has $(length(corrections)) entries; need 2^S = $(2^S)"))
        for σ in 0:(2^S - 1)
            got = syndrome(code, corrections[σ + 1])
            got == σ || throw(ArgumentError(
                "CodeEncoding: corrections[$(σ + 1)] = $(String(corrections[σ + 1])) has " *
                "syndrome $got, not $σ — the table is mis-entered (S20 self-validation)"))
        end
        return new{typeof(code),N,K}(code, encoder, copy(corrections))
    end
end

"""
    decoder(e::CodeEncoding) -> UnitaryBlock

`adjoint(e.encoder)` — exact by construction (S18): one representation of the
encode/decode pair, so an encode/decode mismatch is unrepresentable.
"""
decoder(e::CodeEncoding) = adjoint(e.encoder)

code(e::CodeEncoding) = e.code
nphysical(e::CodeEncoding) = nphysical(e.code)
nlogical(e::CodeEncoding) = nlogical(e.code)

"""
    bit_flip_code() -> CodeEncoding

The validated `[[3,1,1]]` bit-flip repetition code: stabilizers `Z₁Z₂`, `Z₂Z₃`
(signs +1), logicals `X̄ = XXX`, `Z̄ = Z₁`; encoder `q2 ⊻= q1; q3 ⊻= q1`
(traced and certified — R3); table {0↦I, 1↦X₁, 2↦X₃, 3↦X₂} (the header's
generator-1-=-LSB pin). Declared — and `verify_distance`-verified — distance
**1**: `Z₁` is a weight-1 logical, so this code detects/corrects NO Z error
and AMPLIFIES phase noise (the wm28-shaped anti-test pins that). It also sits
below the Eastin–Knill hypothesis (d = 1 — the theorem needs d ≥ 2), which is
why `e^{iθZ̄}` is a continuous transversal logical family here
(docs/physics/eastin_knill_2009_no_universal_transversal.md, G1/G2).
"""
function bit_flip_code()
    stabs = (PauliWord{3}("ZZI"), PauliWord{3}("IZZ"))
    codev = StabilizerCode(:bit_flip_3, stabs, (Int8(1), Int8(1)),
                           (PauliWord{3}("XXX"),), (PauliWord{3}("ZII"),), 1)
    enc = certify(trace(3) do q1, q2, q3
        q2 ⊻= q1
        q3 ⊻= q1
        (q1, q2, q3)
    end)
    table = [PauliWord{3}("III"), PauliWord{3}("XII"),
             PauliWord{3}("IIX"), PauliWord{3}("IXI")]
    return CodeEncoding(codev, enc, table)
end
