# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M1: the `Perm` process value —
# the phase-free classical-reversible corner (PRD-v2 §4.1). Represented as a
# list of multiply-controlled-NOT (`MCX`) generators, matching the Bennett
# bridge's output vocabulary. The marquee fact: ctrl(Perm) is a Perm (a
# controlled permutation is a permutation) — the classical corner is closed
# under control, so controlled oracles never leave the zero-phase-freedom
# corner.
#
# Wire/bit convention (shared with Ctrl): wire 1 is the MOST significant bit.
# For an n-wire register and basis index b ∈ 0:2^n−1, wire c holds bit
# (b >> (n − c)) & 1, so wire 1 = MSB, wire n = LSB. This matches Ctrl's
# "controls are the leading wires" and Tensor's "first factor is leftmost".
#
# Physics grounding:
#   docs/physics/delorme_control_as_constructor.md — ctrl is a constructor;
#     its closure on the reversible corner (Perm ⊗ Perm, ctrl(Perm)) is the
#     classical instance of the control functor.
#   docs/physics/wharton_koch_quaternion_bloch.md — Perm carries no phase
#     freedom (canonical 0/1 matrices), the extreme of the U(2) story.

"""
    MCX(controls, target)

One reversible generator: a multiply-controlled NOT. `controls` is a list of
1-based wire indices (empty ⇒ a bare `X` on `target`); the target bit flips iff
every control wire is `1`. Every `MCX` is an INVOLUTION. Negative controls
(control-on-`|0⟩`) are expressed by conjugating the control wire with `X`
generators, not a polarity flag — keeping every generator uniformly
"flip target iff controls = |1…1⟩", which is what makes the `ctrl` closure a
one-liner. Not itself a `ProcessValue`.

STORAGE (M8/F28 immutability refactor, design `m8-5hr7` §4, TR5): `controls` is
an immutable `NTuple` (frozen), not a `Vector`, so an `MCX` (and any `Perm` /
`UnitaryBlock` that embeds it) is DEEPLY immutable — no live-`Vector` aliasing
can mutate a sealed block out from under a certificate. The public constructor
accepts any integer vector/tuple and defensively freezes it. The field type is
the abstract `NTuple{K,Int} where K` (variable length): this is deliberate —
pinning `K` into a type parameter would explode compilation for wide Bennett
generators, and hiding the length behind an abstract field keeps generator
iteration on the runtime (non-unrolled) path (verified: a 3000-generator tuple
behind an abstract field compiles in ~15 ms vs ~7.5 s if the length is concrete).
"""
struct MCX
    controls::NTuple{K,Int} where {K}
    target::Int
    # Frozen-tuple internal path (the sealer/combinators build tuples directly).
    MCX(controls::Tuple{Vararg{Int}}, target::Integer) = new(controls, Int(target))
end

"""
    MCX(controls::AbstractVector, target) -> MCX

Vector-accepting public constructor: defensively freezes `controls` into an
immutable tuple (F28 — the incoming vector may be mutated by the caller after
the call without affecting the stored `MCX`).
"""
MCX(controls::AbstractVector{<:Integer}, target::Integer) =
    MCX(NTuple{length(controls),Int}(controls), target)

"""
    Perm(n, gates)

A reversible permutation on `n` wires as an ordered list of `MCX` generators
(`gates[1]` applied first). Compact (linear in circuit size — a Bennett
artifact stays small; the explicit 2^n permutation vector is exponential and
rejected for storage) and phase-free by construction (PRD-v2 §4.1).

STORAGE (M8/F28 immutability refactor, design `m8-5hr7` §4, TR5): `gates` is a
frozen `NTuple{M,MCX} where M` (abstract length — see `MCX`), NOT a `Vector`, so
a `Perm` embedded in a sealed `UnitaryBlock` is deeply immutable. The public
constructors accept a vector or tuple of `MCX` and freeze it; the internal
combinators (`∘`, `⊗`, `adjoint`, `ctrl`) build a `Vector{MCX}` and freeze once
at construction — never mutating a stored field.
"""
struct Perm <: ProcessValue
    n::Int
    gates::NTuple{M,MCX} where {M}
    Perm(n::Integer, gates::Tuple{Vararg{MCX}}) = new(Int(n), gates)
end

"""
    Perm(n, gates::AbstractVector{MCX}) -> Perm

Vector-accepting public constructor: defensively freezes the generator list into
an immutable tuple (F28). This is the form every test fixture and the Bennett
extension use (`Perm(n, [MCX(...), ...])`).
"""
Perm(n::Integer, gates::AbstractVector{MCX}) = Perm(n, Tuple(gates))

nwires(p::Perm) = p.n

# Read the frozen generator list back as a mutable Vector for the combinators
# below (they concat/reverse/offset — pure Vector algebra — then freeze once).
_gatevec(p::Perm) = collect(MCX, p.gates)

"""
    denoted_permutation(p::Perm) -> Vector{Int}

The permutation `p` induces on basis indices `0:2^n−1`, replayed with cheap
bit-ops (its NORMAL FORM: two different gate lists denoting one permutation
give equal vectors). Gated at `PERM_EQ_MAXW` — above it, errors LOUDLY rather
than returning a wrong structural answer (CLAUDE.md #1 FAIL LOUD). `out[b+1]`
is the image of basis index `b`.
"""
function denoted_permutation(p::Perm)
    p.n <= PERM_EQ_MAXW || error("Perm: width $(p.n) exceeds PERM_EQ_MAXW=$PERM_EQ_MAXW; semantic denotation intractable — compare on a probe set instead")
    n = p.n
    N = 1 << n
    out = Vector{Int}(undef, N)
    for b in 0:(N-1)
        s = b
        for g in p.gates
            fire = true
            for c in g.controls
                if ((s >> (n - c)) & 1) == 0
                    fire = false
                    break
                end
            end
            if fire
                s ⊻= (1 << (n - g.target))
            end
        end
        out[b+1] = s
    end
    return out
end

"""
    denoted_matrix(p::Perm) -> Matrix{ComplexF64}

The 2^n × 2^n 0/1 permutation matrix `M` with `M * e_b = e_{perm[b]}`, built
from `denoted_permutation`. Test/Ad cross-checks only (small `n`).
"""
function denoted_matrix(p::Perm)
    perm = denoted_permutation(p)
    N = length(perm)
    M = zeros(ComplexF64, N, N)
    for b in 0:(N-1)
        M[perm[b+1]+1, b+1] = one(ComplexF64)
    end
    return M
end

"""
    ctrl(p::Perm) -> Perm

Prepend ONE new control wire (the new MSB, wire 1) to EVERY generator, shifting
all existing wire indices by `+1`. A controlled `MCX` is an `MCX` with more
controls, so the result is still a `Perm` — the one-line closure fact that
proves "the classical-reversible corner is the best-behaved under control"
(PRD-v2 §4.1; `docs/physics/delorme_control_as_constructor.md`, the control
functor on the reversible prop). Shifting preserves every existing wire's bit
position (wire i → wire i+1 in an (n+1)-wire register has the same bit
`n−i`), so the added wire is a clean new MSB control.
"""
function ctrl(p::Perm)
    newgates = Vector{MCX}(undef, length(p.gates))
    for (i, g) in enumerate(p.gates)
        shifted = Int[c + 1 for c in g.controls]
        pushfirst!(shifted, 1)
        newgates[i] = MCX(shifted, g.target + 1)
    end
    return Perm(p.n + 1, newgates)
end

"""
    adjoint(p::Perm) -> Perm

Reverse the generator list. Every `MCX` is an involution, so per-generator
inversion is a no-op and `(G_k ⋯ G_1)† = G_1 ⋯ G_k` is just the reversed order.
"""
Base.adjoint(p::Perm) = Perm(p.n, reverse(_gatevec(p)))

"""
    ∘(a::Perm, b::Perm) -> Perm

Composition (apply `b` first): run `b`'s generators, then `a`'s. Widths must
match (fail loud).
"""
function Base.:∘(a::Perm, b::Perm)
    @assert a.n == b.n "Perm ∘: width mismatch ($(a.n) vs $(b.n))"
    return Perm(a.n, vcat(_gatevec(b), _gatevec(a)))
end

"""
    ⊗(a::Perm, b::Perm) -> Perm

Parallel composition on disjoint wires: `a` on the leading (MSB) block, `b`'s
generators offset by `a.n`. `Perm ⊗ Perm` is again a `Perm` — the reversible
corner is closed under `⊗` as well as under `ctrl`
(`docs/physics/delorme_control_as_constructor.md`).
"""
function ⊗(a::Perm, b::Perm)
    off = a.n
    newgates = _gatevec(a)
    for g in b.gates
        push!(newgates, MCX(Int[c + off for c in g.controls], g.target + off))
    end
    return Perm(a.n + b.n, newgates)
end

"""
    isapprox(a::Perm, b::Perm; atol=U2_ATOL, rtol=0) -> Bool

Semantic (permutation-level) equality: two different generator lists can denote
one permutation, so structural `==` (left as the struct default) is too strong.
`≈` compares the induced permutation vectors via `denoted_permutation` (cheaper
than materializing the 2^n × 2^n matrices, and mirrors `U2`'s discipline of
routing the semantic equality through `≈` while keeping `==` structural — so
the `==`/`hash` contract is untouched). Gated at `PERM_EQ_MAXW`.
"""
function Base.isapprox(a::Perm, b::Perm; atol::Real=U2_ATOL, rtol::Real=0)
    a.n == b.n || return false
    return denoted_permutation(a) == denoted_permutation(b)
end
