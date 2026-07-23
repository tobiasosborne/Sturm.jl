# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M12 phase 1 (bead Sturm.jl-elsf):
# the symplectic Pauli-word algebra — the exact-integer core the whole M12
# error-bound machinery stands on (design: docs/design/m12-synthesis.md,
# convergent core #2/#3; proposal B §2, proposal A D-A2).
#
# ── WHY BITMASKS (and not strings) ──────────────────────────────────────────
# Every M12 requirement lands on one fact: the product of two Pauli words is a
# Pauli word with a phase i^k, computed by two XORs and a popcount, and
# commutation is the symplectic form. That single fact makes ‖[P,Q]‖ ∈ {0, 2}
# EXACT and makes α_comm exactly computable (bounds.jl) — unmeetable on strings
# without O(W) reparses in inner loops.
#
# ── THE ENDIANNESS PIN (v0.1 lesson 6 — pinned HERE and NOWHERE else) ───────
# String char j = wire j = MSB-first (the F21/M10 convention) ↦ mask bit
# (W − j). Every string↔mask conversion and per-wire letter read lives in THIS
# file (`PauliWord{W}(::AbstractString)`, `letter_at`, `Base.String`); the
# round-trip + MSB pin test is M12.PAULI.ALGEBRA.

"""
    PauliWord{W}

A Pauli word on `W` wires as a symplectic pair of bitmasks: bit `(W − j)` of
`x`/`z` is set iff the letter on wire `j` has an X/Z component (`Y` = both,
`I` = neither). The operator convention is `Op(w) = i^{|x∧z|}·X^x·Z^z` (each
`Y = i·XZ` per wire), which makes `Op` Hermitian. `W ≤ 64` — wider registers
error LOUDLY (UInt64 masks; a mask widening is a future change, never a wrap).
Construct from a length-`W` string over `"IXYZ"`: `PauliWord{3}("XYZ")`.
docs/physics/hagan_wiebe_2023_composite.md (the `H_i` unit words of
eq def:alpha_comm); docs/physics/childs_2019_trotter_error.md.
"""
struct PauliWord{W}
    x::UInt64
    z::UInt64
    function PauliWord{W}(x::UInt64, z::UInt64) where {W}
        (W isa Int && 1 ≤ W ≤ 64) || error(
            "PauliWord: width W = $W is unsupported — need 1 ≤ W ≤ 64 (UInt64 " *
            "symplectic masks; a wider register needs a mask widening, which " *
            "must be a deliberate change, not a silent wrap).")
        (W == 64 || (x >> W == 0 && z >> W == 0)) || error(
            "PauliWord{$W}: mask bits set beyond wire $W (x = $x, z = $z) — " *
            "an internal endianness/width bug.")
        return new{W}(x, z)
    end
end

"""
    PauliWord{W}(word::AbstractString) -> PauliWord{W}

Parse a length-`W` string over `"IXYZ"` (char 1 = wire 1 = MSB — THE endianness
pin, this file only). Wrong length ⇒ `DimensionMismatch`; a letter outside the
alphabet ⇒ `ArgumentError` (the M10 messages, kept verbatim).
"""
function PauliWord{W}(word::AbstractString) where {W}
    length(word) == W || throw(DimensionMismatch(
        "evolve!: Pauli word \"$word\" has length $(length(word)) ≠ register width $W."))
    x = UInt64(0); z = UInt64(0)
    for (j, c) in enumerate(word)
        b = UInt64(1) << (W - j)          # THE PIN: char j = wire j = mask bit (W − j)
        if c == 'X'
            x |= b
        elseif c == 'Y'
            x |= b; z |= b
        elseif c == 'Z'
            z |= b
        elseif c != 'I'
            throw(ArgumentError(
                "evolve!: Pauli word \"$word\" has a letter outside \"IXYZ\"."))
        end
    end
    return PauliWord{W}(x, z)
end

"""
    letter_at(w::PauliWord{W}, j) -> Char

The Pauli letter (`'I'`/`'X'`/`'Y'`/`'Z'`) on wire `j` (1 = MSB). Lives next to
the parse pin so the bit↔wire map has exactly one home.
"""
function letter_at(w::PauliWord{W}, j::Integer) where {W}
    xb = (w.x >> (W - j)) & 1
    zb = (w.z >> (W - j)) & 1
    return xb == 1 ? (zb == 1 ? 'Y' : 'X') : (zb == 1 ? 'Z' : 'I')
end

"The string spelling of `w` (round-trips with `PauliWord{W}(::AbstractString)`)."
Base.String(w::PauliWord{W}) where {W} = String([letter_at(w, j) for j in 1:W])

"`true` iff `w` is the identity word (both masks zero)."
is_identity(w::PauliWord) = w.x == 0 && w.z == 0

"""
    commutes(p::PauliWord{W}, q::PauliWord{W}) -> Bool

The symplectic form: `p` and `q` commute iff
`popcount(p.x ∧ q.z) + popcount(p.z ∧ q.x)` is even; otherwise they
ANTIcommute (Pauli words never partially commute). Exact integer arithmetic —
this is what makes every nested-commutator norm in α_comm exact (bounds.jl).
"""
commutes(p::PauliWord{W}, q::PauliWord{W}) where {W} =
    iseven(count_ones(p.x & q.z) + count_ones(p.z & q.x))

"""
    mulword(p::PauliWord{W}, q::PauliWord{W}) -> (k::Int, r::PauliWord{W})

The exact product `Op(p)·Op(q) = i^k · Op(r)` with `r = (p.x ⊻ q.x, p.z ⊻ q.z)`
and the phase power `k ∈ 0:3` tracked exactly:
`k = c_p + c_q − c_r + 2·|p.z ∧ q.x| (mod 4)`, `c_w = |w.x ∧ w.z|` (the per-`Y`
`i` of the Hermitian convention plus the `Z`-past-`X` reordering sign). Norms
never need `k`, but the test suite pins it against dense kron anyway — the
algebra layer is where a v0.1-class sign bug would enter (lesson 1).
"""
function mulword(p::PauliWord{W}, q::PauliWord{W}) where {W}
    rx = p.x ⊻ q.x
    rz = p.z ⊻ q.z
    cp = count_ones(p.x & p.z)
    cq = count_ones(q.x & q.z)
    cr = count_ones(rx & rz)
    k = mod(cp + cq - cr + 2 * count_ones(p.z & q.x), 4)
    return (k, PauliWord{W}(rx, rz))
end

"""
    mulword_word(p, q) -> PauliWord{W}

The phase-free product WORD `p ⋆ q` (the α_comm measure-propagation only needs
the word: per-tuple commutator norms are phase-insensitive).
"""
mulword_word(p::PauliWord{W}, q::PauliWord{W}) where {W} =
    PauliWord{W}(p.x ⊻ q.x, p.z ⊻ q.z)
