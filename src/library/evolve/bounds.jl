# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M12 phases 1+2 (beads Sturm.jl-elsf
# / Sturm.jl-8yzf): the error-bound machinery — the EXACT α_comm engine
# (synthesis convergent core #3; proposal B §4 + proposal A §4), the Trotter
# step/error-bound registry (S13), the qDrift EXACT transcendental N criterion
# (S4), the Hagan–Wiebe composite resource rules (S7 + Fact HW), `BoundReport`
# auditability (S6), and THE single diamond↔spectral factor-2 pin (S5,
# proposal A D-A3).
#
# ── ε CONVENTION (S5 — pinned once, here) ───────────────────────────────────
# `ε` everywhere in M12 means the FULL diamond norm ‖·‖_⋄. Campbell states
# qDrift in the HALVED diamond distance d_⋄ = ½‖·‖_⋄ (docs/physics/
# campbell_2019_qdrift.md, eq δ); Hagan–Wiebe and Zlokapa use the full norm.
# The unitary conversion ‖𝒰 − 𝒱‖_⋄ ≤ 2‖U − V‖_∞ lives in ONE function,
# `_diamond_from_spectral` — the silent factor-of-2 bug class dies here.
#
# ── R1 (CLOSED, this implementation session) ────────────────────────────────
# The order-2p pure-Trotter chain was verified against the HW tex
# (docs/literature/2206.06409_src/main.tex, thm:trotter_cost proof):
#   spectral  ‖e^{iHτ} − TS_{2k}(τ)‖ ≤ (2α_comm(H,2k)/(2k+1))·(Υτ)^{2k+1}
#             (eq TS_intermediate_2, citing Childs Thm 10/eq 189 with the
#              α_comm-convention change explicitly noted by HW),
#   diamond   = 2 × spectral (eqs diamond_to_spectral_start–TS_intermediate_1
#              — the factor is EXACTLY 2, audited),
#   r steps   ‖·‖_⋄ ≤ (4rα/(2k+1))·(Υt/r)^{2k+1}   (eq trotter_diamond_error),
#   steps     r > (Υt)^{1+1/2k}/ε^{1/2k}·(4α/(2k+1))^{1/2k}
#              (eq TS_intermediate_3; the 4 = 2_spectral-const × 2_diamond).
# Distillation: docs/physics/hagan_wiebe_2023_composite.md (thm:trotter_cost).
# Order 1 keeps the TIGHT Childs E1 pair sum (docs/physics/
# childs_2019_trotter_error.md, eq E1); the E2 tight order-2 path stays a
# follow-on (its index ranges are still abbreviated in the distillation) —
# order 2 soundly uses the generic 2k formula at k = 1 (S13).

"""
    _diamond_from_spectral(x) -> 2x

THE factor-2 pin (S5): for unitaries, `‖𝒰 − 𝒱‖_⋄ ≤ 2‖U − V‖_∞`
(docs/physics/hagan_wiebe_2023_composite.md, eqs diamond_to_spectral_start–
TS_intermediate_1). Every spectral→diamond conversion in M12 goes through
this one function so the factor can never silently drift.
"""
_diamond_from_spectral(x::Float64) = 2x

"""
    ALPHA_MAXWORDS_DEFAULT

Default support-size cap of the α_comm measure propagation (≈ 4·10⁶ words ≈
10² MB of dict). A LOUD cap (`AlphaCommBlowup`), never a silent degrade —
calibration on the bench families is research step R4.
"""
const ALPHA_MAXWORDS_DEFAULT = 4_000_000

"""
    AlphaCommBlowup(support, layer, maxwords)

Thrown when the α_comm word-support exceeds `maxwords` at propagation layer
`layer`. The v0.1 `alpha_comm` p ≥ 3 silent-1e9×-substitution bug class is
structurally impossible: there is NO code path from `:exact` to `:norm1`
without the caller spelling it. The sanctioned exits are in the message.
"""
struct AlphaCommBlowup <: Exception
    support::Int
    layer::Int
    maxwords::Int
end
function Base.showerror(io::IO, e::AlphaCommBlowup)
    print(io,
        "AlphaCommBlowup: the exact α_comm word support reached $(e.support) " *
        "entries at nesting layer $(e.layer), over the maxwords = $(e.maxwords) " *
        "cap. Nothing was substituted. Explicit exits: raise `maxwords=`, opt " *
        "in to the LOOSE 1-norm bound `mode = :norm1` (a bound, NOT the " *
        "value — docs/physics/hagan_wiebe_2023_composite.md, Lemma " *
        "bounds_on_alpha_and_p), pick a lower order, or give explicit steps.")
end

"""
    alpha_comm(hs::PauliSum{W}, order; mode = :exact, maxwords = ALPHA_MAXWORDS_DEFAULT)

The nested-commutator sum `α_comm(H, 2k)` driving the order-`2k` Trotter error
(docs/physics/hagan_wiebe_2023_composite.md, eq def:alpha_comm; restated
docs/physics/zlokapa_2026_hamsim_lower_bounds.md):

    α_comm(H, 2k) = Σ_{γ₁…γ_{2k+1}} (Π|h_γ|) ‖[H_{γ_{2k+1}},[…,[H_{γ₂},H_{γ₁}]…]]‖.

`mode = :exact` (default) computes it EXACTLY by measure propagation over
product words: for unit Pauli words each commutator layer is either 0 (the
pair commutes) or `2 ×` a unit word (it anticommutes) — so whether layer d+1
survives depends ONLY on the running product word (Markov), tuples aggregate
by word without loss (no norms of SUMS are ever taken — no triangle slack),
and every surviving (2k+1)-tuple contributes `Π|h| · 2^{2k}`. Support growth
is guarded by `maxwords` — overflow throws `AlphaCommBlowup`, never degrades.

`mode = :norm1` is the EXPLICIT-OPT-IN loose bound `2^{2k}·λ^{2k+1}`
(hagan_wiebe Lemma bounds_on_alpha_and_p) — clearly a bound, not the value;
no code path selects it for you. Signs are irrelevant (commutator norms are
sign-insensitive; a named test pins this).
"""
function alpha_comm(hs::PauliSum{W}, order::Integer;
                    mode::Symbol = :exact,
                    maxwords::Integer = ALPHA_MAXWORDS_DEFAULT) where {W}
    (iseven(order) && 2 ≤ order ≤ 2 * SUZUKI_MAX_P) || throw(DomainError(order,
        "alpha_comm: order must be an even 2 ≤ 2k ≤ $(2 * SUZUKI_MAX_P) — " *
        "α_comm(H, 2k) is the order-2k Suzuki object (order 1 uses the tight " *
        "pair sum `alpha_comm_pairs`)."))
    mode === :exact || mode === :norm1 || throw(ArgumentError(
        "alpha_comm: mode must be :exact or :norm1 (got :$mode) — there is " *
        "no estimation mode, by design."))
    L = nterms(hs)
    L == 0 && return 0.0
    mode === :norm1 && return 2.0^order * hs.λ^(order + 1)
    μ = Dict{PauliWord{W},Float64}()
    for j in 1:L                                    # depth-1 measure: μ₁(P_j) = |a_j|
        μ[hs.words[j]] = abs(hs.coeffs[j])          # words are unique post-merge
    end
    for layer in 2:(order + 1)
        ν = Dict{PauliWord{W},Float64}()
        for (w, ω) in μ, j in 1:L
            p = hs.words[j]
            commutes(p, w) && continue              # [P_j, w] = 0
            v = mulword_word(p, w)                  # else [P_j, w] = 2·(phase)·(p⋆w)
            ν[v] = get(ν, v, 0.0) + ω * abs(hs.coeffs[j])
            length(ν) > maxwords && throw(AlphaCommBlowup(length(ν), layer, Int(maxwords)))
        end
        μ = ν
        isempty(μ) && return 0.0                    # everything commuted out
    end
    return 2.0^order * sum(values(μ))               # each layer contributed a factor 2
end

"""
    alpha_comm_pairs(hs::PauliSum) -> Float64

The TIGHT first-order commutator sum `Σ_{i<j} |a_i||a_j|·‖[P_i,P_j]‖`
(= `Σ_{i<j, anticommuting} 2|a_i a_j|` exactly) — the eq-(E1) coefficient of
docs/physics/childs_2019_trotter_error.md. O(L²) popcounts; exact.
"""
function alpha_comm_pairs(hs::PauliSum{W}) where {W}
    s = 0.0
    L = nterms(hs)
    for i in 1:(L - 1), j in (i + 1):L
        commutes(hs.words[i], hs.words[j]) && continue
        s += 2.0 * abs(hs.coeffs[i]) * abs(hs.coeffs[j])
    end
    return s
end

"""
    alpha_comm_cross(hs::PauliSum{W}, K, order; mode = :exact, maxwords = …)
        -> (αA, αAB)

The head α and the CROSS commutator sum of the canonical split A = terms 1:K,
B = the rest: `α_comm({A,B}, 2k) = α_comm(H) − α_comm(A) − α_comm(B)` by
inclusion–exclusion — exact, because each tuple's contribution is
label-independent (docs/physics/hagan_wiebe_2023_composite.md, the additive
split at line 249). Three guarded engine calls share `maxwords`. With
`mode = :norm1`, the explicit-opt-in HW Lemma bounds:
`αA ≤ 2^{2k}λ_A^{2k+1}`, `αAB ≤ 2^{2k}·Σ_{l=1}^{2k} λ_A^l λ_B^{2k+1−l}`.
Consumed by the phase-2 Composite planner; tested (partition identity) now.
"""
function alpha_comm_cross(hs::PauliSum{W}, K::Integer, order::Integer;
                          mode::Symbol = :exact,
                          maxwords::Integer = ALPHA_MAXWORDS_DEFAULT) where {W}
    L = nterms(hs)
    0 ≤ K ≤ L || throw(DomainError(K,
        "alpha_comm_cross: the head size K must satisfy 0 ≤ K ≤ L = $L."))
    A = _subsum(hs, 1:Int(K))
    B = _subsum(hs, (Int(K) + 1):L)
    if mode === :norm1
        αA = 2.0^order * A.λ^(order + 1)
        αAB = 2.0^order * sum(A.λ^l * B.λ^(order + 1 - l) for l in 1:order; init = 0.0)
        return (αA, αAB)
    end
    αH = alpha_comm(hs, order; mode, maxwords)
    αA = alpha_comm(A, order; mode, maxwords)
    αB = alpha_comm(B, order; mode, maxwords)
    αAB = αH - αA - αB
    αAB ≥ -1e-9 * max(1.0, αH) || error(
        "alpha_comm_cross: negative cross term $αAB from an exact identity — " *
        "an internal inconsistency (inclusion–exclusion is exact in ℝ; this " *
        "is a bug, not fp noise).")
    return (αA, max(αAB, 0.0))
end

"""
    BoundReport

An auditable derived resource (S6, proposal A D-A4): `value` (the r, N, or
error bound — per `formula`), the `formula` symbol, the `citation` string
(`"docs/physics/<name>.md — <locus>"` — the boot lint resolves the path), and
the `inputs` NamedTuple it was computed from. Plans carry their reports;
conformance tests assert against them, so formula drift breaks a NAMED test.
"""
struct BoundReport
    value::Float64
    formula::Symbol
    citation::String
    inputs::NamedTuple
end

# Guarded real→step-count ceiling: a non-finite or astronomically large step
# count is a caller/scale error, reported loudly (never an InexactError deep
# in a ceil).
function _steps_ceil(rreal::Float64, what::AbstractString)
    isfinite(rreal) || error(
        "$what: the derived step count is not finite ($rreal) — check t, ε, " *
        "and the Hamiltonian scale.")
    rreal < 2.0^62 || error(
        "$what: the derived step count $rreal is astronomically large — the " *
        "requested (t, ε) is out of reach for this formula; raise ε, lower " *
        "|t|, or choose another strategy.")
    return max(1, ceil(Int, rreal))
end

# The order-dispatched α for the step/error formulas (order 1 → tight pairs;
# order 2k → the DP / :norm1 opt-in).
function _alpha_for(hs::PauliSum, order::Int, alpha_mode::Symbol, maxwords::Integer)
    order == 1 && return alpha_comm_pairs(hs)
    return alpha_comm(hs, order; mode = alpha_mode, maxwords)
end

"""
    trotter_steps(hs::PauliSum, t, ε; order = 2, alpha_mode = :exact,
                  maxwords = ALPHA_MAXWORDS_DEFAULT) -> BoundReport

The proven step count `r` for `‖𝒰(t) − formula^{∘r}‖_⋄ ≤ ε` (`ε` = FULL
diamond norm, S5), with EXACT α_comm by default:

- order 1 (`:childs_E1_diamond`): diamond(r) = 2·(t²/2r)·α₁ = t²α₁/r
  (docs/physics/childs_2019_trotter_error.md eq E1; ×2 through
  `_diamond_from_spectral`) ⇒ `r = ⌈2·(t²α₁/2)/ε⌉`;
- even order 2k (`:hw_trotter_2k`): r from eq TS_intermediate_3
  (docs/physics/hagan_wiebe_2023_composite.md, thm:trotter_cost; R1-verified),
  `r = ⌈(Υ|t|)^{1+1/2k}/ε^{1/2k} · (2·2α/(2k+1))^{1/2k}⌉` — the inner 2 is
  the spectral constant of eq TS_intermediate_2, the outer 2 is
  `_diamond_from_spectral`.

A commuting Hamiltonian (α ≡ 0) yields `r = 1` exactly — no division, no
special case. Bounds use `|t|` (backwards evolution is legal).
"""
function trotter_steps(hs::PauliSum{W}, t::Real, ε::Real;
                       order::Integer = 2, alpha_mode::Symbol = :exact,
                       maxwords::Integer = ALPHA_MAXWORDS_DEFAULT) where {W}
    ord = _check_order(order)
    (isfinite(ε) && ε > 0) || throw(DomainError(ε,
        "trotter_steps: ε must be a finite positive full-diamond-norm target."))
    T = abs(Float64(t))
    α = _alpha_for(hs, ord, alpha_mode, maxwords)
    if ord == 1
        rreal = _diamond_from_spectral(T^2 * α / 2) / ε
        r = _steps_ceil(rreal, "trotter_steps(order = 1)")
        return BoundReport(Float64(r), :childs_E1_diamond,
            "docs/physics/childs_2019_trotter_error.md — eq (E1); ×2 per " *
            "docs/physics/hagan_wiebe_2023_composite.md eqs " *
            "diamond_to_spectral_start–TS_intermediate_1",
            (α₁ = α, t = T, ε = Float64(ε), order = 1, alpha_mode = alpha_mode))
    end
    k = ord ÷ 2
    Υ = suzuki_sweep_count(ord)
    c = _diamond_from_spectral(2.0 * α) / (2k + 1)         # = 4α/(2k+1), factored
    rreal = (Υ * T)^(1 + 1 / (2k)) / Float64(ε)^(1 / (2k)) * c^(1 / (2k))
    r = _steps_ceil(rreal, "trotter_steps(order = $ord)")
    return BoundReport(Float64(r), :hw_trotter_2k,
        "docs/physics/hagan_wiebe_2023_composite.md — thm:trotter_cost, eq " *
        "TS_intermediate_3 (R1-verified against the tex)",
        (α = α, t = T, ε = Float64(ε), order = ord, Υ = Υ, alpha_mode = alpha_mode))
end

"""
    trotter_error_bound(hs::PauliSum, t, r; order = 2, alpha_mode = :exact,
                        maxwords = ALPHA_MAXWORDS_DEFAULT) -> BoundReport

The inverse direction (conformance tests, reports): the PROVEN full-diamond
error bound of the order-`order` formula at `r` steps. `value` is the diamond
bound; `inputs.spectral` is the spectral half (what a realized `op_matrix`
distance is compared against; the ×2 rides `_diamond_from_spectral` — a named
test pins `value == 2 × inputs.spectral`).

- order 1: spectral = `(t²/2r)·α₁` (childs eq E1);
- order 2k: spectral = `r·(2α/(2k+1))·(Υ|t|/r)^{2k+1}` (hagan_wiebe eqs
  TS_intermediate_2 × r; R1-verified).
"""
function trotter_error_bound(hs::PauliSum{W}, t::Real, r::Integer;
                             order::Integer = 2, alpha_mode::Symbol = :exact,
                             maxwords::Integer = ALPHA_MAXWORDS_DEFAULT) where {W}
    ord = _check_order(order)
    r ≥ 1 || throw(DomainError(r, "trotter_error_bound: need r ≥ 1 steps."))
    T = abs(Float64(t))
    α = _alpha_for(hs, ord, alpha_mode, maxwords)
    if ord == 1
        spectral = T^2 * α / (2r)
        return BoundReport(_diamond_from_spectral(spectral), :childs_E1_diamond,
            "docs/physics/childs_2019_trotter_error.md — eq (E1)",
            (spectral = spectral, α₁ = α, t = T, r = Int(r), order = 1,
             alpha_mode = alpha_mode))
    end
    k = ord ÷ 2
    Υ = suzuki_sweep_count(ord)
    spectral = r * (2.0 * α / (2k + 1)) * (Υ * T / r)^(2k + 1)
    return BoundReport(_diamond_from_spectral(spectral), :hw_trotter_2k,
        "docs/physics/hagan_wiebe_2023_composite.md — eq TS_intermediate_2 " *
        "× r (thm:trotter_cost)",
        (spectral = spectral, α = α, t = T, r = Int(r), order = ord, Υ = Υ,
         alpha_mode = alpha_mode))
end

# ═══════════════════════════════════════════════════════════════════════════
#  M12 phase 2 (bead Sturm.jl-8yzf): qDrift + composite resource rules
# ═══════════════════════════════════════════════════════════════════════════
#
# ── THE qDRIFT CRITERION (S4 — exact, windowless) ───────────────────────────
# Campbell's appendix bounds ONE qDrift segment (duration t/N, sample j with
# p_j = |a_j|/λ, apply exp(−i·sign(a_j)·(λt/N)·P_j)) in the halved diamond
# distance by the EXACT remainder series d ≤ Σ_{n≥2} x^n/n! = e^x − 1 − x,
# x = 2λ|t|/N (docs/physics/campbell_2019_qdrift.md, Thm 1 / App. B — the
# "(or solve exact expression in appendix)" pseudocode line). Subadditivity
# over N segments and the ×2 full-diamond pin (S5) give
#
#     ‖𝒰(t) − 𝓔^{∘N}‖_⋄ ≤ 2N(e^{2λ|t|/N} − 1 − 2λ|t|/N)  =: f(N).      (S4)
#
# f is STRICTLY decreasing in N: with g(x) = e^x − 1 − x, d/dN [N·g(c/N)]
# = g(x) − x·g′(x) = e^x(1 − x) − 1 < 0 for all x > 0 (log-inequality
# x + log(1−x) < 0). So "the least N with f(N) ≤ ε" is well-posed and found
# by a doubling bracket + integer bisection — no closed-form validity window
# (the HW restatement's ε < λt·ln2/2 exists only to license THEIR closed form
# N = 4λ²t²/ε via e^x ≤ 2; the exact criterion needs none).
#
# ── DIRECTION OF THE ASYMPTOTE (deviation from the proposal-A property) ─────
# Since e^x − 1 − x > x²/2 STRICTLY for x > 0, f(N) > 4λ²t²/N, so the exact
# criterion demands MORE samples than the naive asymptote:
#     ⌈4λ²t²/ε⌉ ≤ N_exact ≈ 4λ²t²/ε + 2λ|t|/3,
# (verified numerically; proposal A's "N_exact ≤ ⌈4λ²t²/ε⌉" has the
# inequality backwards). The named test pins the correct two-sided sandwich
# and the ratio → 1. The exact criterion IS tighter than the honest
# window-form closed bound (Campbell's full-diamond (4λ²t²/N)e^{2λ|t|/N}):
# f(N) ≤ that for all N, so N_exact ≤ the window-form N wherever the window
# holds. NOTE (worklog flag): HW eq qdrift_diamond_distance requotes
# Campbell's HALVED-distance bound as the FULL norm — a factor-2-optimistic
# transcription; Sturm's f(N) keeps Campbell's own convention, honestly ×2.

"The S4 criterion value f(N) = 2N(e^{2λ|t|/N} − 1 − 2λ|t|/N) — full ‖·‖_⋄."
function _qdrift_criterion(λ::Float64, T::Float64, N::Integer)
    x = 2.0 * λ * T / N
    return 2.0 * N * (expm1(x) - x)          # expm1: accurate for small x
end

"""
    qdrift_error_bound(λ, t, N) -> BoundReport

The PROVEN full-diamond error bound of `N` qDrift samples at coupling weight
`λ` and time `t`: `value = 2N(e^{2λ|t|/N} − 1 − 2λ|t|/N)` — Campbell's exact
remainder series composed over `N` segments, ×2 through the S5 convention
(docs/physics/campbell_2019_qdrift.md, Thm 1 / eq δ — Campbell's d is the
HALVED diamond distance; the file-header note pins the conversion). The
inverse direction of [`qdrift_samples`](@ref); what the T5 channel test
asserts against, untuned.
"""
function qdrift_error_bound(λ::Real, t::Real, N::Integer)
    N ≥ 1 || throw(DomainError(N, "qdrift_error_bound: need N ≥ 1 samples."))
    λ ≥ 0 || throw(DomainError(λ, "qdrift_error_bound: λ = Σ|a_j| is ≥ 0 by construction."))
    T = abs(Float64(t))
    return BoundReport(_qdrift_criterion(Float64(λ), T, N), :campbell_exact_series,
        "docs/physics/campbell_2019_qdrift.md — Thm 1 / App. B exact series; " *
        "halved-distance ×2 per the S5 pin (eq δ)",
        (λ = Float64(λ), t = T, N = Int(N)))
end

"""
    qdrift_samples(λ, t, ε) -> BoundReport

The least integer `N` with `2N(e^{2λ|t|/N} − 1 − 2λ|t|/N) ≤ ε` (`ε` = FULL
diamond norm, S5) — the EXACT transcendental criterion of S4
(docs/physics/campbell_2019_qdrift.md, Thm 1: the appendix's exact remainder
series, not the asymptote), solved by doubling bracket + integer bisection
(f strictly decreasing in N — proof in the section header above). No
validity-window special case exists (S4 kills it). Properties pinned by the
named test: `⌈4λ²t²/ε⌉ ≤ N ≤ ⌈4λ²t²/ε⌉ + ⌈2λ|t|/3⌉ + 2`, ratio → 1.

`inputs.bound` is the realized criterion value f(N) ≤ ε — the untuned number
the T5 channel conformance test compares the exact ensemble Choi distance to.
"""
function qdrift_samples(λ::Real, t::Real, ε::Real)
    (isfinite(ε) && ε > 0) || throw(DomainError(ε,
        "qdrift_samples: ε must be a finite positive full-diamond-norm target."))
    λ ≥ 0 || throw(DomainError(λ, "qdrift_samples: λ = Σ|a_j| is ≥ 0 by construction."))
    lam = Float64(λ)
    T = abs(Float64(t))
    citation = "docs/physics/campbell_2019_qdrift.md — Thm 1 (exact appendix " *
               "series, S4); ×2 halved-distance pin (S5)"
    if lam == 0.0 || T == 0.0                    # no non-identity weight: exact at N = 1
        return BoundReport(1.0, :campbell_exact_N, citation,
            (λ = lam, t = T, ε = Float64(ε), bound = 0.0))
    end
    hi = 1
    while _qdrift_criterion(lam, T, hi) > ε
        hi ≥ 2^62 && error(
            "qdrift_samples: N exceeded 2^62 without meeting ε = $ε — the " *
            "requested (λ, t, ε) is out of reach; raise ε or lower |t|.")
        hi *= 2
    end
    lo = max(1, hi ÷ 2)                          # f(lo) may fail, f(hi) holds
    while lo < hi                                # invariant: f(hi) ≤ ε
        mid = (lo + hi) ÷ 2
        if _qdrift_criterion(lam, T, mid) ≤ ε
            hi = mid
        else
            lo = mid + 1
        end
    end
    return BoundReport(Float64(hi), :campbell_exact_N, citation,
        (λ = lam, t = T, ε = Float64(ε), bound = _qdrift_criterion(lam, T, hi)))
end

# ── COMPOSITE RESOURCES (Fact HW / HW Thm 2.1; S7) ──────────────────────────
#
# For the canonical split A = terms 1:K, B = the tail, outer/inner order 2k
# matched (HW's own convention, main.tex line 490):
#
#   P(T) = T^{2k+1}·(4Υ^{2k+1}/(2k+1))·(Υ·α_comm(A,2k) + α_comm({A,B},2k))
#                                       (HW eq def:p_of_t)
#   Q(T) = 4Υλ_B²T²/N_B                 (HW eq def:q_of_t)
#   r    = ⌈(P/ε)^{1/2k} + Q/ε⌉         (HW thm:higher_order_cost_fixed)
#   cost = Υ(ΥL_A + N_B)·r operator exponentials.
#
# We carry R_P := (P/ε)^{1/2k} (the product-formula repetition weight) and
# R_Q := 4Υλ_B²T²/ε (the qDrift weight at N_B = 1), so r = ⌈R_P + R_Q/N_B⌉.
#
# NEGATIVE-dt SLOTS (research step R3 — CLOSED against the tex): outer p ≥ 2
# stages carry a (1−4u_k) < 0 scale. HW's Lemma lem:diamond_dist_higher_order
# bounds every slot duration via |1−4u_k| ≤ 1 ⇒ |t_i| ≤ t — the ABSOLUTE
# value — and both per-slot error bounds are even in t_i (Trotter spectral
# bounds use |t|; the qDrift bound is quadratic). So negative-dt B-slots are
# covered by the SAME accounting: |dt| in error bookkeeping, sign in angles.
# Composite is NOT restricted to outer order 2.

"R_P and R_Q of the Fact-HW step rule (see section header). Exact α by default."
function _composite_RP_RQ(hs::PauliSum{W}, K::Integer, t::Real, ε::Real;
                          order::Integer = 2, alpha_mode::Symbol = :exact,
                          maxwords::Integer = ALPHA_MAXWORDS_DEFAULT) where {W}
    (iseven(order) && 2 ≤ order ≤ 2 * SUZUKI_MAX_P) || throw(DomainError(order,
        "composite: the (matched inner/outer) order must be an even 2 ≤ order ≤ " *
        "$(2 * SUZUKI_MAX_P) (docs/physics/hagan_wiebe_2023_composite.md, Def 5.1)."))
    (isfinite(ε) && ε > 0) || throw(DomainError(ε,
        "composite: ε must be a finite positive full-diamond-norm target."))
    L = nterms(hs)
    0 < K < L || throw(DomainError(K,
        "_composite_RP_RQ: interior split 0 < K < L = $L required (K = 0/L " *
        "normalize to pure QDrift/Trotter plans BEFORE any composite arithmetic)."))
    k = order ÷ 2
    Υ = suzuki_sweep_count(order)
    T = abs(Float64(t))
    (αA, αAB) = alpha_comm_cross(hs, K, order; mode = alpha_mode, maxwords)
    λB = hs.tail_λ[K + 1]
    P = T^(2k + 1) * (4.0 * Float64(Υ)^(2k + 1) / (2k + 1)) * (Υ * αA + αAB)
    R_P = (P / ε)^(1 / (2k))
    R_Q = 4.0 * Υ * λB^2 * T^2 / ε
    return (R_P = R_P, R_Q = R_Q, αA = αA, αAB = αAB, λB = λB, Υ = Υ, k = k, T = T)
end

"""
    composite_nb(K, Υ, R_P, R_Q) -> Int

The S7 default `N_B`: stationary point of the RELAXED cost
`Υ(ΥK + N_B)(R_P + R_Q/N_B)` — `N_B* = √(Υ·K·R_Q/R_P)` (the same structure as
HW's Lemma lem:optimal_nb_higher_order, docs/physics/hagan_wiebe_2023_composite.md
§(e)) — then an integer scan {⌊N_B*⌋−1 … ⌈N_B*⌉+1} ∩ [1,∞) on the TRUE ceiled
cost `Υ(ΥK + n)·⌈R_P + R_Q/n⌉` (ties → smaller n). `R_P = 0` (fully commuting
head + zero cross term) makes the stationary point diverge — HW note the
degeneracy; the relaxed optimum then sits at r = 1, i.e. `N_B* = R_Q` (the
paper's "any N_B > 0" case pinned to the cost-optimal choice).
"""
function composite_nb(K::Integer, Υ::Integer, R_P::Float64, R_Q::Float64)
    R_Q ≥ 0 || error("composite_nb: R_Q = $R_Q < 0 — an internal inconsistency.")
    nbstar = R_P > 0 ? sqrt(Υ * K * R_Q / R_P) : max(R_Q, 1.0)
    isfinite(nbstar) || error(
        "composite_nb: the stationary N_B* is not finite ($nbstar) — check the " *
        "(t, ε) scale.")
    lo = max(1, floor(Int, nbstar) - 1)
    hi = max(lo, min(ceil(Int, nbstar) + 1, 2^40))
    best_n = 0
    best_c = Inf
    for n in lo:hi
        r = max(1.0, ceil(R_P + R_Q / n))
        c = Υ * (Υ * K + n) * r
        if c < best_c                                # ties → smaller n (first hit)
            best_c = c
            best_n = n
        end
    end
    return best_n
end

"""
    composite_steps(hs::PauliSum, K, t, ε; order = 2, N_B, alpha_mode = :exact,
                    maxwords = ALPHA_MAXWORDS_DEFAULT) -> BoundReport

The proven outer repetition count `r = ⌈(P/ε)^{1/2k} + Q/ε⌉` of the order-`2k`
composite channel at head size `K` and `N_B` samples per B-slot (Fact HW —
docs/physics/zlokapa_2026_hamsim_lower_bounds.md eq:HW-cost, reproduced from
docs/physics/hagan_wiebe_2023_composite.md thm:higher_order_cost_fixed), with
EXACT α_comm by default. `value` is r; `inputs` carries the full audit trail
(K, N_B, αA, αAB, λ_B, Υ, R_P, R_Q — the cost is `Υ(ΥK + N_B)·r`).
"""
function composite_steps(hs::PauliSum{W}, K::Integer, t::Real, ε::Real;
                         order::Integer = 2, N_B::Integer,
                         alpha_mode::Symbol = :exact,
                         maxwords::Integer = ALPHA_MAXWORDS_DEFAULT) where {W}
    N_B ≥ 1 || throw(DomainError(N_B, "composite_steps: need N_B ≥ 1 samples per B-slot."))
    pq = _composite_RP_RQ(hs, K, t, ε; order, alpha_mode, maxwords)
    r = _steps_ceil(pq.R_P + pq.R_Q / N_B, "composite_steps(order = $order)")
    return BoundReport(Float64(r), :hw_fact_thm21,
        "docs/physics/hagan_wiebe_2023_composite.md — thm:higher_order_cost_fixed " *
        "(Fact HW, docs/physics/zlokapa_2026_hamsim_lower_bounds.md eq:HW-cost)",
        (K = Int(K), N_B = Int(N_B), order = Int(order), Υ = pq.Υ, t = pq.T,
         ε = Float64(ε), αA = pq.αA, αAB = pq.αAB, λB = pq.λB,
         R_P = pq.R_P, R_Q = pq.R_Q, alpha_mode = alpha_mode))
end

"""
    composite_error_bound(hs::PauliSum, K, t, r; order = 2, N_B,
                          alpha_mode = :exact, maxwords = …) -> BoundReport

The inverse direction (T11 conformance): the PROVEN full-diamond error bound
of the order-`2k` composite channel at `r` outer iterations —
`value = P(T)/r^{2k} + Q(T)/r` (HW's per-iteration bound × r, eqs
def:p_of_t/def:q_of_t + eq:err_to_err_per_iter). Untuned; the exact ensemble
superoperator distance is asserted ≤ this value.
"""
function composite_error_bound(hs::PauliSum{W}, K::Integer, t::Real, r::Integer;
                               order::Integer = 2, N_B::Integer,
                               alpha_mode::Symbol = :exact,
                               maxwords::Integer = ALPHA_MAXWORDS_DEFAULT) where {W}
    r ≥ 1 || throw(DomainError(r, "composite_error_bound: need r ≥ 1 outer iterations."))
    N_B ≥ 1 || throw(DomainError(N_B, "composite_error_bound: need N_B ≥ 1."))
    # P/Q at a reference ε = 1 (they are ε-free; _composite_RP_RQ folds ε only
    # into R_P/R_Q, so recover P = R_P^{2k}·ε and Q = R_Q·ε at ε = 1).
    pq = _composite_RP_RQ(hs, K, t, 1.0; order, alpha_mode, maxwords)
    k = pq.k
    P = pq.R_P^(2k)
    Q = pq.R_Q / N_B
    return BoundReport(P / Float64(r)^(2k) + Q / r, :hw_composite_error,
        "docs/physics/hagan_wiebe_2023_composite.md — eqs def:p_of_t/def:q_of_t " *
        "× eq:err_to_err_per_iter (thm:higher_order_cost_fixed proof)",
        (K = Int(K), N_B = Int(N_B), r = Int(r), order = Int(order), Υ = pq.Υ,
         t = pq.T, αA = pq.αA, αAB = pq.αAB, λB = pq.λB, P = P, Q = Q,
         alpha_mode = alpha_mode))
end

"""
    composite_k(hs::PauliSum, t, ε; order = 2, N_B = nothing,
                alpha_mode = :exact, maxwords = …) -> Int

The default head size `K` (S6 ruling chain): seed with the ZAH optimal-split
second-moment rule — the least `K` with `Σ_{j>K} a_j²·t² ≤ ε` (the λ-free
restatement of `Σ_{j>K*}(a_j/λ)² ≤ ε/(λt)²`; docs/physics/
zlokapa_2026_hamsim_lower_bounds.md, Lemma "Optimal deterministic-randomized
split" — read off the precomputed `tail_m2` suffix table) — then LOCAL
refinement on the TRUE Fact-HW cost at the candidates {⌈K₀/2⌉, K₀, min(2K₀,L)}
(proposal A §6.1; three budget-guarded α_comm calls per interior candidate).
Endpoint candidates cost as their pure strategies (K = 0 → the S4 qDrift N;
K = L → the Trotter step rule) so the refinement can degenerate honestly.
Ties → larger K (the deterministic-leaning tie-break, S8 spirit).
"""
function composite_k(hs::PauliSum{W}, t::Real, ε::Real;
                     order::Integer = 2, N_B::Union{Integer,Nothing} = nothing,
                     alpha_mode::Symbol = :exact,
                     maxwords::Integer = ALPHA_MAXWORDS_DEFAULT) where {W}
    (isfinite(ε) && ε > 0) || throw(DomainError(ε,
        "composite_k: ε must be a finite positive full-diamond-norm target."))
    L = nterms(hs)
    L == 0 && return 0
    T = abs(Float64(t))
    T == 0.0 && return 0
    # second-moment seed: least K with tail_m2[K+1]·T² ≤ ε (tail_m2 nonincreasing)
    K0 = L
    for K in 0:L
        if hs.tail_m2[K + 1] * T^2 ≤ ε
            K0 = K
            break
        end
    end
    Υ = suzuki_sweep_count(order)
    cands = sort(unique(clamp.([cld(K0, 2), K0, min(2 * K0, L)], 0, L)))
    best_K = -1
    best_c = Inf
    for K in cands
        c = if K == 0
            qdrift_samples(hs.λ, T, ε).value
        elseif K == L
            Υ * L * trotter_steps(hs, T, ε; order, alpha_mode, maxwords).value
        else
            pq = _composite_RP_RQ(hs, K, T, ε; order, alpha_mode, maxwords)
            n = N_B === nothing ? composite_nb(K, pq.Υ, pq.R_P, pq.R_Q) : Int(N_B)
            r = max(1.0, ceil(pq.R_P + pq.R_Q / n))
            Υ * (Υ * K + n) * r
        end
        if c < best_c || (c == best_c && K > best_K)   # ties → larger K
            best_c = c
            best_K = K
        end
    end
    return best_K
end
