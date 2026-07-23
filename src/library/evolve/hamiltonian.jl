# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M12 phase 1 (bead Sturm.jl-elsf):
# `PauliTerm` (the KEPT user input spelling, M10) and the canonical
# `PauliSum{W}` library value with its prefix tables (design synthesis
# convergent core #2; proposal B §2). NOT a kernel value — PRD-v2 §1.3
# ("Nature does not hand out Hamiltonians"): `H` stays a library-level value.
#
# ── CANONICAL INVARIANTS (established by the constructor, relied on
#    everywhere downstream) ────────────────────────────────────────────────
#   • duplicate words MERGED — exact, e^{−iaP}·e^{−ibP} = e^{−i(a+b)P} (S12;
#     changelog: M10 applied duplicates as separate equal-word factors);
#   • exact-zero coefficients dropped;
#   • the identity word split into `c_I` (an exact deterministic phase,
#     applied ONCE per plan through `_act!` — conditional under a live ctrl
#     frame — and EXCLUDED from λ: it commutes with everything, so keeping it
#     in λ or in a sampling distribution could only loosen every bound);
#   • terms sorted |coeff|-DESCENDING, ties broken (x, z)-lexicographically —
#     `K`-cuts, λ_K tails and schedules are reproducible (proposal A §2).
#
# The suffix tables `tail_λ`/`tail_m2` (`tail_λ[K+1] = Σ_{j>K}|a_j|`) are the
# O(1)-per-K inputs of the optimal-K rule, docs/physics/
# zlokapa_2026_hamsim_lower_bounds.md (Lemma 7) — precomputed here, consumed
# by the M12 phase-2 Composite/Auto planners.

"""
    PauliTerm(coeff, word)

A single weighted Pauli word `(coeff, word)` where `word` is a length-W string
over `"IXYZ"` (char 1 = wire 1 = MSB). The user-facing INPUT format: a
Hamiltonian is a `Vector{PauliTerm}` or any iterable of
`(::Real, ::AbstractString)` pairs — normalized once into the canonical
`PauliSum{W}` (docs/physics/childs_2019_trotter_error.md).
"""
struct PauliTerm
    coeff::Float64
    word::String
end
PauliTerm(c::Real, w::AbstractString) = PauliTerm(Float64(c), String(w))

"""
    PauliSum{W}

The canonical library-level Hamiltonian value `H = c_I·I + Σ_j coeffs[j]·P_j`
(see the file header for the invariants). Fields:

- `coeffs` — SIGNED coefficients, |a|-descending, merged, zero-free;
- `words`  — the matching non-identity `PauliWord{W}`s (unique);
- `λ`      — `Σ_j |coeffs[j]|` (identity EXCLUDED; docs/physics/campbell_2019_qdrift.md, eq λ);
- `c_I`    — the identity-word coefficient, split out exactly;
- `tail_λ` — `tail_λ[K+1] = Σ_{j>K} |a_j|` (length L+1; `λ_K` suffix table);
- `tail_m2`— `tail_m2[K+1] = Σ_{j>K} a_j²` (tail second moments —
  docs/physics/zlokapa_2026_hamsim_lower_bounds.md, Lemma 7).

Construct with `PauliSum{W}(H)` from a `Vector{PauliTerm}`, any iterable of
`(coeff, word)` pairs, or a `PauliSum{W}` (identity pass-through). Accepted
anywhere `evolve!` accepts `H`.
"""
struct PauliSum{W}
    coeffs::Vector{Float64}
    words::Vector{PauliWord{W}}
    λ::Float64
    c_I::Float64
    tail_λ::Vector{Float64}
    tail_m2::Vector{Float64}
end

# The single canonicalization path (merge → drop zeros → split identity →
# sort → suffix tables). Every PauliSum construction funnels through here.
function _canonical(::Type{PauliSum{W}}, words::Vector{PauliWord{W}},
                    coeffs::Vector{Float64}) where {W}
    acc = Dict{PauliWord{W},Float64}()
    c_I = 0.0
    for (w, c) in zip(words, coeffs)
        if is_identity(w)
            c_I += c
        else
            acc[w] = get(acc, w, 0.0) + c
        end
    end
    ws = collect(keys(acc))
    cs = Float64[acc[w] for w in ws]
    keep = findall(!iszero, cs)                     # exact zeros dropped
    ws = ws[keep]; cs = cs[keep]
    ord = sortperm(collect(eachindex(cs));
                   by = i -> (-abs(cs[i]), ws[i].x, ws[i].z))
    ws = ws[ord]; cs = cs[ord]
    L = length(cs)
    λ = sum(abs, cs; init = 0.0)
    tail_λ = zeros(Float64, L + 1)
    tail_m2 = zeros(Float64, L + 1)
    for j in L:-1:1
        tail_λ[j] = tail_λ[j + 1] + abs(cs[j])
        tail_m2[j] = tail_m2[j + 1] + cs[j]^2
    end
    return PauliSum{W}(cs, ws, λ, c_I, tail_λ, tail_m2)
end

PauliSum{W}(hs::PauliSum{W}) where {W} = hs        # idempotent pass-through

function PauliSum{W}(H) where {W}
    words = PauliWord{W}[]
    coeffs = Float64[]
    for t in H
        pt = t isa PauliTerm ? t : PauliTerm(t[1], t[2])
        push!(words, PauliWord{W}(pt.word))
        push!(coeffs, pt.coeff)
    end
    return _canonical(PauliSum{W}, words, coeffs)
end

"Number of non-identity terms (the `L` of every cost formula)."
nterms(hs::PauliSum) = length(hs.coeffs)

"""
    _subsum(hs::PauliSum{W}, r) -> PauliSum{W}

The canonical sub-Hamiltonian of the terms at (canonical-order) indices `r` —
the head/tail slices of the α_comm partition identity (bounds.jl) and of the
phase-2 Composite planner. Re-canonicalized (a slice of a canonical sum is
already canonical; the shared path keeps one code route).
"""
_subsum(hs::PauliSum{W}, r) where {W} =
    _canonical(PauliSum{W}, hs.words[r], hs.coeffs[r])

"""
    iscommuting(hs::PauliSum) -> Bool

`true` iff all pairs of (non-identity) terms commute — the O(L²) exactness
predicate: a commuting Hamiltonian makes the first-order formula EXACT
(α_comm ≡ 0; every step bound collapses to r = 1). Used by tests and by the
phase-2 `Auto` fast path.
"""
function iscommuting(hs::PauliSum{W}) where {W}
    L = nterms(hs)
    for i in 1:(L - 1), j in (i + 1):L
        commutes(hs.words[i], hs.words[j]) || return false
    end
    return true
end

# ---------------------------------------------------------------------------
# Model library — the coefficient-tail families of the M12 bench/test suite
# ---------------------------------------------------------------------------

"""
    ising_chain(W; J = 1.0, h = 1.0) -> Vector{PauliTerm}

The 1-D open-boundary transverse-field Ising chain on `W ≥ 2` wires:
`H = J·Σ_{j<W} Z_j Z_{j+1} + h·Σ_j X_j` — the standard nearest-neighbour
benchmark family of the Trotter-error literature
(docs/physics/childs_2019_trotter_error.md), with structured commutators
(cheap exact α_comm) and uniform coefficients (qDrift's worst case, λ = Θ(L)
— docs/physics/campbell_2019_qdrift.md).
"""
function ising_chain(W::Integer; J::Real = 1.0, h::Real = 1.0)
    W ≥ 2 || throw(DomainError(W, "ising_chain: need W ≥ 2 wires."))
    terms = PauliTerm[]
    for j in 1:(W - 1)
        s = fill('I', W); s[j] = 'Z'; s[j + 1] = 'Z'
        push!(terms, PauliTerm(J, String(s)))
    end
    for j in 1:W
        s = fill('I', W); s[j] = 'X'
        push!(terms, PauliTerm(h, String(s)))
    end
    return terms
end

"""
    heisenberg_chain(W; J = 1.0) -> Vector{PauliTerm}

The 1-D open-boundary Heisenberg chain on `W ≥ 2` wires:
`H = J·Σ_{j<W} (X_j X_{j+1} + Y_j Y_{j+1} + Z_j Z_{j+1})` — the uniform-λ
nearest-neighbour regime (`λ = ΛL`), docs/physics/campbell_2019_qdrift.md
("Asymptotics comparison"); docs/physics/childs_2019_trotter_error.md.
"""
function heisenberg_chain(W::Integer; J::Real = 1.0)
    W ≥ 2 || throw(DomainError(W, "heisenberg_chain: need W ≥ 2 wires."))
    terms = PauliTerm[]
    for j in 1:(W - 1), letter in ('X', 'Y', 'Z')
        s = fill('I', W); s[j] = letter; s[j + 1] = letter
        push!(terms, PauliTerm(J, String(s)))
    end
    return terms
end

"""
    powerlaw_chain(W; γ = 2.0, J = 1.0) -> Vector{PauliTerm}

A long-range power-law ZZ chain with transverse field on `W ≥ 2` wires:
`H = J·Σ_{i<j} |i−j|^{−γ} Z_i Z_j + J·Σ_j X_j` — the power-law
coefficient-TAIL family (`a ∝ d^{−γ}`) whose head-heavy spectrum is where the
composite frontier lives (docs/physics/zlokapa_2026_hamsim_lower_bounds.md,
the coefficient-tail model families; docs/physics/hagan_wiebe_2023_composite.md
§d partitioning guidance).
"""
function powerlaw_chain(W::Integer; γ::Real = 2.0, J::Real = 1.0)
    W ≥ 2 || throw(DomainError(W, "powerlaw_chain: need W ≥ 2 wires."))
    terms = PauliTerm[]
    for i in 1:(W - 1), j in (i + 1):W
        s = fill('I', W); s[i] = 'Z'; s[j] = 'Z'
        push!(terms, PauliTerm(J * Float64(j - i)^(-γ), String(s)))
    end
    for j in 1:W
        s = fill('I', W); s[j] = 'X'
        push!(terms, PauliTerm(J, String(s)))
    end
    return terms
end
