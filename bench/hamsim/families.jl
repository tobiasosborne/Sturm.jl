# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# bench/hamsim/families.jl — the M12 frontier model roster (bead Sturm.jl-gmx0;
# docs/design/m12-synthesis.md §8: model families = coefficient tails × word
# ensembles; proposal B §8 / proposal A §9).
#
# ── NORMALIZATION (one bench choice, recorded once, here) ───────────────────
# Every family is normalized to λ = Σ|a_j| = 1, matching the Zlokapa setup
# (docs/physics/zlokapa_2026_hamsim_lower_bounds.md, eq h-main-indep: sorted
# coefficients with Σ a_j = 1, unit-norm words). Then `t` IS the papers'
# dimensionless λt, the envelope min_K(Kt + t²λ_K²/ε) (their eq lb) is
# directly comparable across families, and qDrift's certified N = N(λ, t, ε)
# is family-independent by construction (Campbell's compiler is
# structure-blind — a feature of the report, not a bug). Rescaling time does
# not change any physics.
#
# ── THE TWO ENSEMBLE CLASSES ────────────────────────────────────────────────
# * STRUCTURED chains (ising/heisenberg, src/library/evolve/hamiltonian.jl):
#   nearest-neighbour commutator structure keeps the exact α_comm DP support
#   linear in L — the exact-α tier. W ∈ {2, 3} executed; W ∈ {8..64}
#   analytic-only (costs come from plans; no execution needed).
# * TAIL families: coefficient generators uniform / power-law j^{−γ},
#   γ ∈ {0.5, 1, 2} / exponential 2^{−j}, L ∈ {16, 64, 256, 1024}, attached
#   to SEEDED random distinct 2-local Pauli words on the smallest W with
#   9·C(W,2) ≥ L. Dense random connectivity makes the α DP support grow
#   toward min(4^W, L^layers) — exactly the regime that probes the
#   ALPHA_MAXWORDS_DEFAULT cap (research step R4).
#
# Seeded reproducibility: every random family carries an explicit seed; the
# roster is a pure function of (fast::Bool).

using Random
using Sturm
using Sturm: PauliSum, PauliTerm, nterms, ising_chain, heisenberg_chain

"One bench model: a normalized canonical Hamiltonian plus its provenance tags."
struct BenchFamily
    name::String
    coeffs::String        # "structured" | "uniform" | "powerlaw-γ" | "exp"
    W::Int
    L::Int                # nterms AFTER canonicalization (merged, zero-free)
    executed::Bool        # W ≤ 3: measured-mode tier runs
    hs::Any               # PauliSum{W}
end

# Normalize to λ = 1 through the canonical constructor (twice: once to merge
# and measure λ, once to rebuild scaled — the single canonicalization path).
function _normalized(W::Int, terms::Vector{PauliTerm})
    hs0 = PauliSum{W}(terms)
    hs0.λ > 0 || error("bench families: λ = 0 — a degenerate model is a roster bug.")
    hs0.c_I == 0 || error("bench families: identity words are not part of the " *
                          "roster (they would be invisible to every cost curve).")
    hs = PauliSum{W}([(hs0.coeffs[j] / hs0.λ, String(hs0.words[j]))
                      for j in 1:nterms(hs0)])
    abs(hs.λ - 1) ≤ 1e-12 || error("bench families: normalization drifted (λ = $(hs.λ)).")
    return hs
end

"Smallest W whose distinct strictly-2-local word count 9·C(W,2) covers L."
function width_for(L::Int)
    for W in 3:64
        9 * binomial(W, 2) ≥ L && return W
    end
    error("bench families: no W ≤ 64 supports L = $L distinct 2-local words.")
end

"""
    rand2local_terms(W, L, coeffs, seed) -> Vector{PauliTerm}

`L` DISTINCT random strictly-2-local Pauli words on `W` wires (seeded shuffle
of the full combo list — sampling without replacement, so canonicalization
merges nothing and L is exact), zipped with the coefficient vector `coeffs`
(assigned in shuffle order; the canonical sort re-orders by |a| afterwards).
"""
function rand2local_terms(W::Int, L::Int, coeffs::Vector{Float64}, seed::Integer)
    length(coeffs) == L || error("rand2local_terms: coeffs length ≠ L.")
    combos = [(i, j, a, b) for i in 1:(W - 1) for j in (i + 1):W
              for a in ('X', 'Y', 'Z') for b in ('X', 'Y', 'Z')]
    length(combos) ≥ L || error(
        "rand2local_terms: only $(length(combos)) distinct 2-local words on " *
        "W = $W wires < L = $L.")
    shuffle!(MersenneTwister(seed), combos)
    terms = PauliTerm[]
    for (n, (i, j, a, b)) in enumerate(combos[1:L])
        s = fill('I', W); s[i] = a; s[j] = b
        push!(terms, PauliTerm(coeffs[n], String(s)))
    end
    return terms
end

# Coefficient-tail generators (pre-normalization scale is irrelevant).
coeffs_uniform(L)      = ones(Float64, L)
coeffs_powerlaw(L, γ)  = Float64[j^(-γ) for j in 1:L]
coeffs_exp(L)          = Float64[2.0^(-j) for j in 1:L]   # subnormal ≥ 2^{-1074}: still exact nonzero

function _tail_family(tag::String, L::Int, coeffs::Vector{Float64}, seed::Integer;
                      executed::Bool = false, W::Int = width_for(L))
    hs = _normalized(W, rand2local_terms(W, L, coeffs, seed))
    return BenchFamily("$(tag)-L$(L)-W$(W)", tag, W, nterms(hs), executed, hs)
end

function _chain_family(kind::Symbol, W::Int; executed::Bool = false)
    terms = kind === :ising ? ising_chain(W) : heisenberg_chain(W)
    hs = _normalized(W, terms)
    return BenchFamily("$(kind)-W$(W)", "structured", W, nterms(hs), executed, hs)
end

"""
    bench_families(; fast = false) -> Vector{BenchFamily}

The roster. Full: 6 executed (W ≤ 3) + 8 structured analytic (ising/heisenberg,
W ∈ {8, 16, 32, 64}) + 20 tail analytic (5 coefficient laws × L ∈
{16, 64, 256, 1024}). `fast`: a 4-family smoke subset.
"""
function bench_families(; fast::Bool = false)
    if fast
        return BenchFamily[
            _chain_family(:ising, 3; executed = true),
            _tail_family("uniform", 16, coeffs_uniform(16), 0xf001; executed = true, W = 3),
            _chain_family(:ising, 16),
            _tail_family("uniform", 64, coeffs_uniform(64), 0xf002),
        ]
    end
    fams = BenchFamily[
        # -- executed tier (W ≤ 3): measured frontier + bound slack ----------
        _chain_family(:ising, 2; executed = true),
        _chain_family(:ising, 3; executed = true),
        _chain_family(:heisenberg, 3; executed = true),
        _tail_family("uniform", 16, coeffs_uniform(16), 0xa001; executed = true, W = 3),
        _tail_family("powerlaw-1", 16, coeffs_powerlaw(16, 1.0), 0xa002; executed = true, W = 3),
        _tail_family("exp", 16, coeffs_exp(16), 0xa003; executed = true, W = 3),
    ]
    for W in (8, 16, 32, 64)
        push!(fams, _chain_family(:ising, W))
        push!(fams, _chain_family(:heisenberg, W))
    end
    for L in (16, 64, 256, 1024)
        push!(fams, _tail_family("uniform", L, coeffs_uniform(L), 0xb000 + L))
        push!(fams, _tail_family("powerlaw-0.5", L, coeffs_powerlaw(L, 0.5), 0xb100 + L))
        push!(fams, _tail_family("powerlaw-1", L, coeffs_powerlaw(L, 1.0), 0xb200 + L))
        push!(fams, _tail_family("powerlaw-2", L, coeffs_powerlaw(L, 2.0), 0xb300 + L))
        push!(fams, _tail_family("exp", L, coeffs_exp(L), 0xb400 + L))
    end
    return fams
end
