# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M12 phases 1+2 (beads Sturm.jl-elsf
# / Sturm.jl-8yzf): plans — the fully-resolved, immutable contracts the
# executor folds over (synthesis convergent core #1; S1: immutable plans +
# lazy trajectory). `plan_evolution` is a PURE classical function: it
# validates, fills every defaulted parameter from the CITED bounds, and
# returns a concrete plan — RNG-free (randomized plans carry the sampling
# TABLE; the draws happen at trajectory time). No `Union{…,Nothing}` survives
# past planning (the stored rng may be `nothing` = "resolve from the context
# at execution", a documented sentinel, not an unfilled resource); all
# interleaving arithmetic is unit-testable with no context; `exp_count` is
# arithmetic on plan fields and `length(collect(trajectory(plan[, rng])))`
# must equal it (a named test) — the bench counter never touches the hot path.

"""
    EvolvePlan{W}

Supertype of fully-resolved evolution plans on a width-`W` register. A plan
is DATA — the channel description. Concrete: [`TrotterPlan`](@ref),
[`QDriftPlan`](@ref), [`CompositePlan`](@ref). M11 adds a `channel(plan)`
lowering (the randomized plans denote mixed-unitary channels — NoiseN/
KrausFamily seams in channel/dag.jl); the surface signature does not move.
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

The `QDrift`/`Composite` methods below complete the randomized shapes
(phase 2, bead Sturm.jl-8yzf); `Auto` dispatch lives in auto.jl (S14's
reserved slot) — its surrogate-cost table is `evolve_plan`.
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

# ═══════════════════════════════════════════════════════════════════════════
#  M12 phase 2 (bead Sturm.jl-8yzf): the randomized plans
# ═══════════════════════════════════════════════════════════════════════════

"""
    QDriftPlan{W}

Campbell's randomized compiler as a plan (docs/physics/campbell_2019_qdrift.md,
Thm 1): `N` i.i.d. draws `j ∼ |a_j|/λ`, each applying
`exp(−i·sign(a_j)·(λt/N)·P_j)`. Fields: `ham`, `t` (SIGNED — the angle `τ`
carries the sign; bounds used `|t|`), `N`, `τ = λt/N` (the fixed per-sample
angle magnitude×sign), `cumw` (cumulative-|a| table for `searchsortedfirst`
sampling — O(log L) per draw, allocation-free), `rng` (the strategy's pinned
RNG, or `nothing` = resolve from the context core at execution — the
precedence pinned by a named test), and `report` (S6; `nothing` when `N` was
explicit).

The ε guarantee is a property of the ENSEMBLE channel (the mixture over
draws); a single trajectory is only ~√ε-close (campbell_2019_qdrift.md,
"Diamond norm distance"; docs/physics/chen_2021_concentration_random_products.md
— typical 1/√N vs average 1/N). `shots` owns the shot loop: one `evolve!`
call = ONE sampled trajectory; nothing is ever wrapped as a process value.
"""
struct QDriftPlan{W} <: EvolvePlan{W}
    ham::PauliSum{W}
    t::Float64
    N::Int
    τ::Float64
    cumw::Vector{Float64}
    rng::Any
    report::Union{BoundReport,Nothing}
end

"""
    CompositePlan{W}

The Hagan–Wiebe composite channel as a plan (docs/physics/
hagan_wiebe_2023_composite.md, Def 5.1 / Thm 2.1): `steps` outer iterations,
each walking `outer` (one step's `(:A|:B, scale)` slot list — shared across
steps, S1; `composite_outer_slots`). An `:A` slot replays `head_sweep` (the
inner order-`2p` sweep over the head terms 1:K at UNIT duration — angles
scale linearly, so the actual angle is `θ_unit·scale·t/steps`); a `:B` slot
draws `N_B` FRESH tail samples `j ∼ |a_j|/λ_B` (R2), each at angle
`sign(a_j)·λ_B·scale·(t/steps)/N_B`. Negative scales (outer p ≥ 2) are
R3-covered (|dt| in bounds, sign in angles — suzuki.jl header). `K = 0`/`K =
L` never reach this struct: they normalize to `QDriftPlan`/`TrotterPlan`
BEFORE scheduling (one code path; synthesis convergent core #5).
"""
struct CompositePlan{W} <: EvolvePlan{W}
    ham::PauliSum{W}
    t::Float64
    steps::Int
    K::Int
    N_B::Int
    order::Int
    outer::Vector{Tuple{Symbol,Float64}}
    head_sweep::Vector{Tuple{Int,Float64}}
    λ_B::Float64
    cumw_tail::Vector{Float64}
    rng::Any
    report::Union{BoundReport,Nothing}
end

"Cumulative-|a| sampling table over `hs.coeffs[r]` (empty range ⇒ empty table)."
_cumabs(hs::PauliSum, r::AbstractUnitRange) = cumsum(abs.(hs.coeffs[r]))

"""
    plan_evolution(alg::QDrift, hs, t; ε = nothing) -> QDriftPlan

Free `N` REQUIRES `ε` (S3 as ruled) and derives it from the EXACT
transcendental criterion (S4, `qdrift_samples`); explicit `N` forbids `ε`
(rule 5 — a tolerance that cannot influence anything is a caller bug). The
degenerate `nterms == 0` Hamiltonian (pure identity) plans `N = 0` — an
empty trajectory; the evolution IS the exact `gphase` the executor applies.
"""
function plan_evolution(alg::QDrift, hs::PauliSum{W}, t::Real;
                        ε::Union{Real,Nothing} = nothing) where {W}
    local N::Int
    local report::Union{BoundReport,Nothing}
    if alg.N === nothing
        ε === nothing && throw(ArgumentError(
            "evolve!: give a target accuracy ε=… or explicit resources " *
            "(steps=…/N=…) — there is no default accuracy (S3)."))
        report = qdrift_samples(hs.λ, t, ε)
        N = Int(report.value)
    else
        ε === nothing || throw(ArgumentError(
            "evolve!: ε=$(ε) was given but the strategy has no free " *
            "parameter (N = $(alg.N) is explicit) — a tolerance that cannot " *
            "influence anything is a caller bug. Drop ε= or drop N=."))
        N = alg.N
        report = nothing
    end
    L = nterms(hs)
    if L == 0
        return QDriftPlan{W}(hs, Float64(t), 0, 0.0, Float64[], alg.rng, report)
    end
    return QDriftPlan{W}(hs, Float64(t), N, hs.λ * Float64(t) / N,
                         _cumabs(hs, 1:L), alg.rng, report)
end

"""
    plan_evolution(alg::Composite, hs, t; ε = nothing, alpha_mode = :exact,
                   maxwords = ALPHA_MAXWORDS_DEFAULT) -> EvolvePlan

Resolution (B §1.3 rules 4/5 completed for the randomized shapes): any free
parameter among `K`/`N_B`/`steps` REQUIRES `ε`; all three explicit forbids
`ε`. Defaults: `K` from `composite_k` (ZAH second-moment seed + Fact-HW
refinement), `N_B` from `composite_nb` (S7 stationary point + integer scan),
`steps` from `composite_steps` (Fact HW) — exact α_comm throughout unless the
caller opts into `:norm1`.

Degenerations (one code path, BEFORE scheduling): `K == 0` returns the pure
`QDriftPlan` (both `N_B` AND `steps` pinned map to `N = steps·Υ·N_B`, the
composite total-sample count; a PARTIAL pin cannot be honored across the
degeneration and throws); `K == L` returns the pure `TrotterPlan` (a pinned
`N_B` has no tail to sample and throws).
"""
function plan_evolution(alg::Composite, hs::PauliSum{W}, t::Real;
                        ε::Union{Real,Nothing} = nothing,
                        alpha_mode::Symbol = :exact,
                        maxwords::Integer = ALPHA_MAXWORDS_DEFAULT) where {W}
    L = nterms(hs)
    alg.K === nothing || alg.K ≤ L || throw(DomainError(alg.K,
        "Composite: the head size K must satisfy 0 ≤ K ≤ L = $L (canonical, " *
        "|a|-descending term count)."))
    anyfree = alg.K === nothing || alg.N_B === nothing || alg.steps === nothing
    if anyfree
        ε === nothing && throw(ArgumentError(
            "evolve!: give a target accuracy ε=… or explicit resources " *
            "(K=…/N_B=…/steps=… all pinned) — there is no default accuracy (S3)."))
    else
        ε === nothing || throw(ArgumentError(
            "evolve!: ε=$(ε) was given but the strategy has no free parameter " *
            "(K, N_B, steps all explicit) — a tolerance that cannot influence " *
            "anything is a caller bug. Drop ε= or free a parameter."))
    end
    K = alg.K === nothing ?
        composite_k(hs, t, ε; order = alg.order, N_B = alg.N_B, alpha_mode, maxwords) :
        alg.K
    Υ = suzuki_sweep_count(alg.order)
    if K == 0                                    # pure qDrift (convergent core #5)
        if alg.N_B !== nothing && alg.steps !== nothing
            # exp_count-preserving map: Υ B-slots per outer step, N_B each.
            return plan_evolution(QDrift(N = alg.steps * Υ * alg.N_B, rng = alg.rng),
                                  hs, t)
        elseif alg.N_B === nothing && alg.steps === nothing
            return plan_evolution(QDrift(rng = alg.rng), hs, t; ε)
        else
            throw(ArgumentError(
                "evolve!: Composite degenerated to pure qDrift (K = 0) but only " *
                "one of N_B/steps is pinned — the partial pin cannot be honored " *
                "across the degeneration. Pin both (N = steps·Υ·N_B) or neither."))
        end
    elseif K == L                                # pure Trotter (convergent core #5)
        alg.N_B === nothing || throw(ArgumentError(
            "evolve!: Composite degenerated to pure Trotter (K = L) but N_B = " *
            "$(alg.N_B) is pinned — there is no tail to sample. Drop N_B= or " *
            "choose K < L."))
        return plan_evolution(Trotter(order = alg.order, steps = alg.steps), hs, t;
                              ε = alg.steps === nothing ? ε : nothing,
                              alpha_mode, maxwords)
    end
    # interior split: derive N_B, then steps, via Fact HW (exact α by default)
    local N_B::Int
    local steps::Int
    local report::Union{BoundReport,Nothing}
    if alg.N_B === nothing || alg.steps === nothing
        pq = _composite_RP_RQ(hs, K, t, ε; order = alg.order, alpha_mode, maxwords)
        N_B = alg.N_B === nothing ? composite_nb(K, pq.Υ, pq.R_P, pq.R_Q) : alg.N_B
        if alg.steps === nothing
            report = composite_steps(hs, K, t, ε; order = alg.order, N_B,
                                     alpha_mode, maxwords)
            steps = Int(report.value)
        else
            steps = alg.steps
            report = nothing
        end
    else
        N_B = alg.N_B
        steps = alg.steps
        report = nothing
    end
    head = _subsum(hs, 1:K)
    # the head slice of a canonical sum is canonical in the SAME order — the
    # global indices 1:K of `head_sweep` must be the plan's `ham` indices.
    head.words == hs.words[1:K] || error(
        "plan_evolution(Composite): the canonical head slice reordered under " *
        "re-canonicalization — an internal invariant violation (pauli.jl " *
        "_canonical must be order-stable on already-canonical input).")
    head_sweep = _build_sweep(head, alg.order, 1.0)
    return CompositePlan{W}(hs, Float64(t), steps, K, N_B, alg.order,
                            composite_outer_slots(alg.order), head_sweep,
                            hs.tail_λ[K + 1], _cumabs(hs, (K + 1):L),
                            alg.rng, report)
end

"""
    trajectory(plan::TrotterPlan) -> iterator of (term_index, θ)

The LAZY execution schedule (S1): the shared one-step sweep repeated `steps`
times — `Iterators.flatten(Iterators.repeated(sweep, steps))`, element type
`Tuple{Int,Float64}`. Deterministic plans iterate WITHOUT an RNG; the
randomized plans REQUIRE `trajectory(plan, rng)` (the zero-arg form throws,
below). Execution is a dumb fold of `_pauli_exp!` over this iterator
(evolve.jl).
"""
trajectory(plan::TrotterPlan) =
    Iterators.flatten(Iterators.repeated(plan.sweep, plan.steps))

"Deterministic plans ignore a supplied rng (uniform call shape for harnesses)."
trajectory(plan::TrotterPlan, _rng) = trajectory(plan)

# --- Randomized trajectories (S1: lazy, streaming; draws happen at iteration
#     time in iteration order — a seeded rng fully pins the sequence) ---------

@noinline _trajectory_needs_rng(what) = error(
    "trajectory(::$what) requires an RNG: randomized plans have no " *
    "deterministic schedule — call trajectory(plan, rng) (explicit; the " *
    "executor resolves alg.rng, else the context core's rng). There is no " *
    "hidden global default at the API surface (explicit-RNG hard constraint).")

trajectory(::QDriftPlan) = _trajectory_needs_rng("QDriftPlan")
trajectory(::CompositePlan) = _trajectory_needs_rng("CompositePlan")

# One uniform [0,1) draw. `nothing` = Julia's task-global stream — the SAME
# sentinel convention as the context core's `_draw` (context/abstract.jl);
# reachable only through the executor's context-rng resolution, never by the
# zero-arg trajectory (which throws above).
_rand01(rng) = rng === nothing ? rand() : rand(rng)

"""
    _qdrift_draw(cumw, λ, rng) -> Int

One qDrift index draw `j ∼ |a_j|/λ` via `searchsortedfirst` on the
cumulative-|a| table (docs/physics/campbell_2019_qdrift.md, eq E: p_j =
|a_j|/λ). The `min` clamps the measure-zero fp edge `ξ·λ ≥ cumw[end]`.
"""
function _qdrift_draw(cumw::Vector{Float64}, λ::Float64, rng)
    return min(searchsortedfirst(cumw, _rand01(rng) * λ), length(cumw))
end

"""
    trajectory(plan::QDriftPlan, rng) -> iterator of (term_index, θ)

`N` streamed i.i.d. draws, each `(j, sign(a_j)·λt/N)` (campbell_2019_qdrift.md,
Thm 1 — the fixed-angle rule; the sign fold is the standard reduction to
positive coefficients). Lazy: the k-th pair is drawn when iterated, so
element order = application order = draw order (T6 pins the replay).
"""
trajectory(plan::QDriftPlan{W}, rng) where {W} =
    Base.Generator(1:plan.N) do _
        j = _qdrift_draw(plan.cumw, plan.ham.λ, rng)
        (j, flipsign(plan.τ, plan.ham.coeffs[j]))
    end

# One composite slot as a lazy (term, θ) iterator. τslot = scale·t/steps.
function _composite_slot(plan::CompositePlan, kind::Symbol, τslot::Float64, rng)
    if kind === :A
        return Base.Generator(plan.head_sweep) do (j, θu)
            (j, θu * τslot)                          # unit-duration sweep, scaled
        end
    end
    kind === :B || error("_composite_slot: unknown slot kind :$kind — a corrupted plan.")
    θmag = plan.λ_B * τslot / plan.N_B
    return Base.Generator(1:plan.N_B) do _
        off = _qdrift_draw(plan.cumw_tail, plan.λ_B, rng)
        j = plan.K + off
        (j, flipsign(θmag, plan.ham.coeffs[j]))
    end
end

"""
    trajectory(plan::CompositePlan, rng) -> iterator of (term_index, θ)

The lazy composite schedule: `steps` outer iterations × the `outer` slot
list; `:A` slots replay the shared inner head sweep at `scale·t/steps`, `:B`
slots stream `N_B` FRESH tail draws each (hagan_wiebe_2023_composite.md,
Def 5.1 — fresh randomness per B-leaf is what the per-step mixing argument
consumes; R2). Element order = application order.
"""
function trajectory(plan::CompositePlan{W}, rng) where {W}
    τstep = plan.t / plan.steps
    return Iterators.flatten(
        _composite_slot(plan, kind, scale * τstep, rng)
        for _ in 1:plan.steps for (kind, scale) in plan.outer)
end

"""
    exp_count(plan) -> Int

The operator-exponential count — the papers' cost unit
(docs/physics/zlokapa_2026_hamsim_lower_bounds.md; hagan_wiebe Thm 2.1 cost
line) — as PLAN ARITHMETIC: `steps × length(sweep)` = r·Υ·L′ for a
`TrotterPlan`; `N` for a `QDriftPlan`; `r·Σ_slots(A ↦ Υ·K, B ↦ N_B)` =
`r·Υ·(Υ·K + N_B)` for a `CompositePlan` (Fact HW's `Υ(ΥL_A + N_B)·r`,
computed from the actual slot list — no closed-form shortcut that could
drift from the schedule). Verified against the trajectory length for ALL
strategies (named test); never instrumented in the hot path.
"""
exp_count(plan::TrotterPlan) = plan.steps * length(plan.sweep)
exp_count(plan::QDriftPlan) = plan.N
exp_count(plan::CompositePlan) =
    plan.steps * sum(kind === :A ? length(plan.head_sweep) : plan.N_B
                     for (kind, _) in plan.outer)
