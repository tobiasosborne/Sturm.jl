# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M12 phase 1 (bead Sturm.jl-elsf):
# the error-bound machinery — the EXACT α_comm engine (synthesis convergent
# core #3; proposal B §4 + proposal A §4), the Trotter step/error-bound
# registry (S13), `BoundReport` auditability (S6), and THE single
# diamond↔spectral factor-2 pin (S5, proposal A D-A3).
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
