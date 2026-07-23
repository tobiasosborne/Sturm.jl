# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M12 phase 1 (bead Sturm.jl-elsf):
# plans — the fully-resolved, immutable contracts the executor folds over
# (synthesis convergent core #1; S1: immutable plans + lazy trajectory).
# `plan_evolution` is a PURE classical function: it validates, fills every
# defaulted parameter from the CITED bounds, and returns a concrete plan. No
# `Union{…,Nothing}` survives past planning; all interleaving arithmetic is
# unit-testable with no context; `exp_count` is arithmetic on plan fields and
# `length(collect(trajectory(plan)))` must equal it (a named test) — the
# bench counter never touches the hot path.

"""
    EvolvePlan{W}

Supertype of fully-resolved evolution plans on a width-`W` register. A plan
is DATA — the channel description. Phase 2 (bead Sturm.jl-8yzf) adds the
randomized plans and, with M11, a `channel(plan)` lowering; the surface
signature does not move.
"""
abstract type EvolvePlan{W} end

"""
    TrotterPlan{W}

The deterministic product-formula plan: `ham` (canonical), `t`, `steps` (r),
`sweep` — ONE step's materialized `(term, θ)` schedule (suzuki.jl; angles are
step-independent, so the single sweep is SHARED across steps — memory never
scales with r·L, S1) — and `report`, the `BoundReport` that sized `steps`
(`nothing` when `steps` was explicit; S6).
"""
struct TrotterPlan{W} <: EvolvePlan{W}
    ham::PauliSum{W}
    t::Float64
    steps::Int
    sweep::Vector{Tuple{Int,Float64}}
    report::Union{BoundReport,Nothing}
end

"""
    plan_evolution(alg::EvolveAlg, hs::PauliSum{W}, t; ε = nothing, …) -> EvolvePlan{W}

Resolve a strategy REQUEST into a concrete plan (pure, RNG-free, no context).
For `Trotter`: explicit `steps` forbids `ε` (a tolerance that cannot
influence anything is a caller bug); free `steps` REQUIRES `ε` (S3 as ruled —
no default accuracy anywhere) and derives `r` from `trotter_steps` (exact
α_comm by default; `alpha_mode = :norm1` is the caller's explicit opt-in).

QDrift / Composite / Auto planning is M12 phase 2 (bead Sturm.jl-8yzf) and
fails loud here.
"""
function plan_evolution(alg::Trotter, hs::PauliSum{W}, t::Real;
                        ε::Union{Real,Nothing} = nothing,
                        alpha_mode::Symbol = :exact,
                        maxwords::Integer = ALPHA_MAXWORDS_DEFAULT) where {W}
    local steps::Int
    local report::Union{BoundReport,Nothing}
    if alg.steps === nothing
        ε === nothing && throw(ArgumentError(
            "evolve!: give a target accuracy ε=… or explicit resources " *
            "(steps=…/N=…) — there is no default accuracy (S3)."))
        report = trotter_steps(hs, t, ε; order = alg.order,
                               alpha_mode, maxwords)
        steps = Int(report.value)
    else
        ε === nothing || throw(ArgumentError(
            "evolve!: ε=$(ε) was given but the strategy has no free " *
            "parameter (steps = $(alg.steps) is explicit) — a tolerance " *
            "that cannot influence anything is a caller bug. Drop ε= or " *
            "drop steps=."))
        steps = alg.steps
        report = nothing
    end
    sweep = _build_sweep(hs, alg.order, Float64(t) / steps)
    return TrotterPlan{W}(hs, Float64(t), steps, sweep, report)
end

# --- Phase-2 stubs: FAIL LOUD, never silently fall back (S10-adjacent) ------
for A in (:QDrift, :Composite, :Auto)
    @eval function plan_evolution(alg::$A, hs::PauliSum{W}, t::Real;
                                  kwargs...) where {W}
        error("plan_evolution($($A)): M12 phase 2 (bead Sturm.jl-8yzf): " *
              "randomized strategies not yet implemented")
    end
end

"""
    trajectory(plan::TrotterPlan) -> iterator of (term_index, θ)

The LAZY execution schedule (S1): the shared one-step sweep repeated `steps`
times — `Iterators.flatten(Iterators.repeated(sweep, steps))`, element type
`Tuple{Int,Float64}`. Deterministic plans iterate WITHOUT an RNG (the
randomized `trajectory(plan, rng)` arrives with phase 2). Execution is a dumb
fold of `_pauli_exp!` over this iterator (evolve.jl).
"""
trajectory(plan::TrotterPlan) =
    Iterators.flatten(Iterators.repeated(plan.sweep, plan.steps))

"""
    exp_count(plan) -> Int

The operator-exponential count — the papers' cost unit
(docs/physics/zlokapa_2026_hamsim_lower_bounds.md; hagan_wiebe Thm 2.1 cost
line) — as PLAN ARITHMETIC: `steps × length(sweep)` = r·Υ·L′ for a
`TrotterPlan`. Verified once against the trajectory length (named test);
never instrumented in the hot path.
"""
exp_count(plan::TrotterPlan) = plan.steps * length(plan.sweep)
