# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M12 phase 2 (bead Sturm.jl-8yzf):
# `Auto` dispatch — S14's reserved slot, the S8 merge of proposal A §7 (full
# candidate table, skipped-rows-with-reason, deterministic tie-break) and
# proposal B §6 (exactness fast paths; surrogate-cost dispatch). Phase 5
# (bead Sturm.jl-jpky) replaced the ranking surrogate; see below.
#
# ── THE DIVISION OF LABOR (S8) ──────────────────────────────────────────────
# `evolve_plan` is PURE and BUDGETED: it ranks candidates by their PROVEN
# surrogate costs. The CHOSEN strategy's PLANNING then re-derives its
# resources with exact α per the phase-1 conventions (`plan_evolution(::Auto)`
# below), so the shipped circuit's bound is always the exact one; the
# surrogate only picked the shape. A surrogate row that fails loudly
# (out-of-reach step ceiling) is recorded as a skipped-with-reason row, never
# silently dropped (A §7.3); if EVERY row is skipped the dispatch itself
# errors.
#
# ── THE RANKING SURROGATE (bead Sturm.jl-jpky — bench-driven replacement) ───
# Phase 4's bench (bead Sturm.jl-gmx0) measured this dispatch against the
# certified frontier and found a ONE-SIDED cost-optimality failure: with the
# ranking α taken from the HW 1-norm Lemma (`mode = :norm1`) alone, structured
# Hamiltonians inflated α by 2·10³–3.4·10⁹× (ising-W64 at order 6), which
# inflates a deterministic row's cost by that ratio^{1/2k} — 40–45× — so
# `Auto` over-picked QDrift. Worst analytic cell: regret 43.5 at
# (ising-W64, t = 16, ε = 10⁻⁴). It never violated ε (planning re-derives
# exactly) and never UNDER-picked; it simply paid too much.
#
# The fix keeps the ranking a ranking of PROVEN costs and makes the proof
# tighter: every deterministic row's α is now `alpha_comm_layered` — the SAME
# exact measure-propagation DP the shipped bound uses, run under a
# propagation-step budget (`ALPHA_WORK_DEFAULT`) and stopped at the deepest
# COMPLETED layer d, with the remaining layers closed by the 1-norm step
# M_{d+1} ≤ λ·M_d:
#
#     α_comm(H, 2k) ≤ 2^{2k}·λ^{2k+1−d}·M_d        (bounds.jl, ineq. (‡))
#
# — the HW 1-norm bound at d = 1, the tight Childs-E1 pair sum at d = 2, the
# EXACT α at d = 2k+1, and monotonically tighter in between. Consequences:
#
#   * the dispatch is still a ranking of proven upper bounds, so the failure
#     mode stays ONE-SIDED (a deterministic row can be over-priced, never
#     under-priced ⇒ `Auto` can over-pick QDrift, never under-pick it);
#   * cheap-DP Hamiltonians are ranked at EXACT α — on the gmx0 roster every
#     structured chain through W = 64 (heisenberg through order 4) and every
#     tail family through L = 64, plus order 2 at L = 256; the 43.5× cell
#     collapses to regret 1;
#   * expensive-DP Hamiltonians degrade VISIBLY: the row records the depth it
#     reached and why it stopped (`PlanRow.alpha`), never an invisible
#     downgrade. That is the whole difference between this and the v0.1
#     α_comm bug that bounds.jl's header names.
#
# COST: O(L) scan + at most `ALPHA_WORK_DEFAULT` propagation steps per
# candidate order (an O(L²)-class budget), never the unbounded DP. This is a
# deliberate move away from phase 2's O(L log L) claim — bought with bench
# evidence, and capped so it can never blow up.
#
# ── DISPATCH IS A THEOREM, NOT A HEURISTIC ──────────────────────────────────
# The candidate set {Trotter(2p), QDrift, Composite(2p, K*)} spans the ZAH
# frontier: Composite(K) interpolates Trotter (K = L) and qDrift (K = 0), and
# min_K(Kt + t²λ_K²/ε) is the PROVEN lower-bound envelope no strategy in this
# class beats (docs/physics/zlokapa_2026_hamsim_lower_bounds.md, thm:gate /
# eq:composite). The K* seed is the optimal-split second-moment rule (their
# Lemma "Optimal deterministic-randomized split") on the precomputed tail_m2
# table.

"""
    PlanRow

One row of the `Auto` candidate table (S8/A §7): the candidate strategy
SHAPE (`alg`), its proven surrogate `cost` (operator exponentials; `Inf` when
skipped), the `report` behind the cost (`nothing` when skipped), `skipped` —
`nothing` for a live row, else the human-readable reason the row was excluded
(visible, never silent) — and `alpha`, the α provenance the cost was priced
from (bead Sturm.jl-jpky): one [`AlphaLayered`](@ref) per α the row consumed
(`:H` for a Trotter row; `:A` + `:cross` for a Composite row), each carrying
the DP depth it reached, whether that depth made it EXACT, and — when it did
not — the loud reason the budget stopped it. Rows that consume no α at all
(QDrift's S4 criterion is λ-only; the exactness fast paths have α ≡ 0 by
physics) carry an empty vector, which is itself the honest statement.
"""
struct PlanRow
    alg::EvolveAlg
    cost::Float64
    report::Union{BoundReport,Nothing}
    skipped::Union{String,Nothing}
    alpha::Vector{AlphaLayered}
end

"""
    EvolveChoice

The result of [`evolve_plan`](@ref): the chosen strategy shape (`choice` —
resources FREE unless an exactness fast path pinned them; the subsequent
planning fills them with exact α), its surrogate `cost`, and the full
candidate `table` including skipped rows (S8: the table is always visible).
"""
struct EvolveChoice
    choice::EvolveAlg
    cost::Float64
    table::Vector{PlanRow}
end

"Deterministic-first sort key (S8 tie-breaks): cost, then deterministic >
randomized, then lower order, then Trotter > QDrift > Composite."
function _dispatch_key(row::PlanRow)
    a = row.alg
    det = a isa Trotter ? 0 : 1
    ord = a isa Trotter ? a.order : (a isa Composite ? a.order : 0)
    fam = a isa Trotter ? 0 : (a isa QDrift ? 1 : 2)
    return (row.cost, det, ord, fam)
end

# Evaluate one candidate, catching ONLY the loud out-of-reach `error()` class
# (_steps_ceil / qdrift_samples overflow) into a skipped-with-reason row —
# A §7.3: a selection heuristic degrading VISIBLY, never a bound substitution.
# DomainError/ArgumentError (caller bugs) propagate. The closure returns
# `(cost, report, alpha_provenance)`.
function _candidate_row(f, alg::EvolveAlg)
    try
        (cost, report, alpha) = f()
        return PlanRow(alg, cost, report, nothing, alpha)
    catch err
        err isa ErrorException || rethrow()
        return PlanRow(alg, Inf, nothing, err.msg, AlphaLayered[])
    end
end

"""
    AUTO_COMMUTING_GATE

Size gate on `Auto`'s O(L²) `iscommuting` exactness fast path (B §6/R4):
above it the check is skipped — skipping a FAST PATH is not a silent bound
substitution (the dispatch below is still proven-cost); the constant is a
loud engineering cap. R4 (bench gmx0) measured the worst case (a fully
commuting L = 2048 sum) at 6.8 ms and recommended KEEPING 2048 until a
larger commuting family appears.
"""
const AUTO_COMMUTING_GATE = 2048

"""
    evolve_plan(hs::PauliSum{W}, t, ε;
                trotter_orders = (2, 4, 6), composite_orders = (2, 4),
                maxwords = ALPHA_MAXWORDS_DEFAULT,
                alpha_work = ALPHA_WORK_DEFAULT) -> EvolveChoice

The PURE `Auto` dispatch rule (public; S8). In order:

1. **Exactness fast paths** (physics, not heuristics): `nterms ≤ 1` ⇒
   `Trotter(order = 1, steps = 1)` — a single Pauli exponential IS
   `e^{−iHt}` exactly; `iscommuting(hs)` (gated `L ≤ AUTO_COMMUTING_GATE`) ⇒
   the same — commuting terms make S₁ exact (α ≡ 0; no bound is evaluated,
   so no division-by-zero path exists — docs/physics/childs_2019_trotter_error.md,
   the α → 0 degeneracy).
2. **Proven surrogate costs under an α budget** (bead Sturm.jl-jpky; the file
   header carries the derivation and the bench evidence): `QDrift` via the
   exact transcendental N (S4 — λ-only, no α); `Trotter(order)` for
   `order ∈ trotter_orders` via the 2k step rule at
   `α = alpha_comm_layered(hs, order; work = alpha_work).value` (an explicitly
   requested `order = 1` uses the tight Childs-E1 pair sum instead — the
   default set is even orders only, so that the candidate table stays the
   phase-2 shape the bench measured);
   `Composite(order)` for `order ∈ composite_orders` at the second-moment
   `K*` (zlokapa Lemma) with the S7 `N_B`, priced from
   `alpha_comm_cross_layered` — rows whose `K*` hits 0/L are skipped with
   reason (those regimes are the pure rows). Every α used is a PROVEN upper
   bound on `α_comm` (exact when the budget covered the DP), and every row
   reports which — `PlanRow.alpha`.
3. **Argmin + tie-breaks**: deterministic > randomized, lower order,
   Trotter > Composite (S8).

`ε` is the FULL diamond norm (S5). The chosen strategy carries FREE
resources — `plan_evolution` refills them with exact α (the surrogate picked
the shape, never the shipped bound). Costs here are therefore RANKING costs:
they are upper bounds on what planning will certify, and the ranking is
one-sided in exactly that direction.
"""
function evolve_plan(hs::PauliSum{W}, t::Real, ε::Real;
                     trotter_orders = (2, 4, 6),
                     composite_orders = (2, 4),
                     maxwords::Integer = ALPHA_MAXWORDS_DEFAULT,
                     alpha_work::Integer = ALPHA_WORK_DEFAULT) where {W}
    (isfinite(ε) && ε > 0) || throw(DomainError(ε,
        "evolve_plan: ε must be a finite positive full-diamond-norm target."))
    L = nterms(hs)
    T = abs(Float64(t))
    εf = Float64(ε)
    # 1 — exactness fast paths (resources PINNED: the plan needs no ε)
    if L ≤ 1 || (L ≤ AUTO_COMMUTING_GATE && iscommuting(hs))
        alg = Trotter(order = 1, steps = 1)
        why = L ≤ 1 ? "single non-identity term: one Pauli exponential is exact" :
                      "pairwise-commuting terms: the order-1 formula is exact (α ≡ 0)"
        rep = BoundReport(Float64(L), :exact_fast_path,
            "docs/physics/childs_2019_trotter_error.md — commuting terms make " *
            "the product formula exact (every commutator vanishes)",
            (L = L, reason = why))
        return EvolveChoice(alg, Float64(L),
                            [PlanRow(alg, Float64(L), rep, nothing, AlphaLayered[])])
    end
    # The full-sum α estimates are shared between the Trotter row of an order
    # and the Composite row of the same order (a pure per-call memo — the same
    # DP, run once).
    αcache = Dict{Int,AlphaLayered}()
    # Order 1 is not an α_comm(H, 2k) object at all: its α IS the tight Childs
    # E1 pair sum, exact in O(L²) and needing no budget (`_alpha_for`'s
    # dispatch, mirrored). It is not in the default candidate set — see the
    # `trotter_orders` note in the docstring — but an explicit request works.
    αfull(order::Int) = get!(αcache, order) do
        order == 1 ?
            AlphaLayered(alpha_comm_pairs(hs), 1, 2, true, L * L, "", :H) :
            alpha_comm_layered(hs, order; maxwords, work = alpha_work)
    end
    table = PlanRow[]
    # 2 — surrogate candidate costs (proven α bounds under `alpha_work`)
    push!(table, _candidate_row(QDrift()) do
        rep = qdrift_samples(hs.λ, T, εf)
        (rep.value, rep, AlphaLayered[])            # S4 is λ-only: no α exists
    end)
    for order in trotter_orders
        push!(table, _candidate_row(Trotter(; order)) do
            a = αfull(Int(order))
            rep = _trotter_steps_report(a.value, T, εf, Int(order),
                                        a.exact ? :exact : :layered)
            (rep.value * suzuki_sweep_count(order) * L, rep, [a])
        end)
    end
    for order in composite_orders
        alg = Composite(; order)
        Υ = suzuki_sweep_count(order)
        # second-moment K* seed only (no refinement DP; the chosen strategy's
        # planning re-derives K with exact-α refinement — S8's split of labor)
        K = L
        for cand in 0:L
            if hs.tail_m2[cand + 1] * T^2 ≤ εf
                K = cand
                break
            end
        end
        if K == 0 || K == L
            push!(table, PlanRow(alg, Inf, nothing,
                "K* = $K degenerates to pure " * (K == 0 ? "qDrift" : "Trotter") *
                " (covered by that row; zlokapa second-moment rule)",
                AlphaLayered[]))
            continue
        end
        push!(table, _candidate_row(alg) do
            cr = alpha_comm_cross_layered(hs, K, Int(order); maxwords,
                                          work = alpha_work, αH = αfull(Int(order)))
            pq = _composite_RP_RQ_from(cr.αA, cr.αAB, hs.tail_λ[K + 1], T, εf,
                                       Int(order))
            n = composite_nb(K, pq.Υ, pq.R_P, pq.R_Q)
            rep = _composite_steps_report(pq, K, n, εf, Int(order),
                                          cr.exact ? :exact : :layered)
            (Υ * (Υ * K + n) * rep.value, rep, [cr.provA, cr.provAB])
        end)
    end
    # 3 — argmin with the S8 tie-break chain
    live = filter(r -> r.skipped === nothing, table)
    isempty(live) && error(
        "evolve_plan: every candidate strategy was skipped — the requested " *
        "(t = $t, ε = $ε) is out of reach for the whole candidate set. Rows: " *
        join([r.skipped for r in table], " | "))
    best = live[argmin([_dispatch_key(r) for r in live])]
    return EvolveChoice(best.alg, best.cost, table)
end

"""
    plan_evolution(alg::Auto, hs, t; ε, alpha_mode = :exact, maxwords = …,
                   alpha_work = ALPHA_WORK_DEFAULT)

`Auto` planning (S8 merge): `evolve_plan` picks the strategy SHAPE from
budgeted proven surrogate costs; the chosen shape is then planned with EXACT
α per the phase-1 conventions (`Composite` re-derives K/N_B/steps exactly;
`Trotter` re-derives steps exactly; `QDrift`'s N is already exact — S4 has no
α). `alpha_work` budgets the DISPATCH only; `alpha_mode`/`maxwords` govern
the SHIPPED bound and are untouched by it. A fast-path choice arrives fully
pinned and is planned WITHOUT ε (the ε was consumed by the dispatch decision;
passing it on would trip rule 5, and rightly — nothing is left for it to
size).
"""
function plan_evolution(alg::Auto, hs::PauliSum{W}, t::Real;
                        ε::Union{Real,Nothing} = nothing,
                        alpha_mode::Symbol = :exact,
                        maxwords::Integer = ALPHA_MAXWORDS_DEFAULT,
                        alpha_work::Integer = ALPHA_WORK_DEFAULT) where {W}
    ε === nothing && throw(ArgumentError(
        "evolve!: give a target accuracy ε=… or explicit resources " *
        "(steps=…/N=…) — there is no default accuracy (S3)."))
    choice = evolve_plan(hs, t, ε; maxwords, alpha_work).choice
    if choice isa Trotter && choice.steps !== nothing        # exactness fast path
        return plan_evolution(choice, hs, t)
    elseif choice isa QDrift
        return plan_evolution(choice, hs, t; ε)
    elseif choice isa Trotter
        return plan_evolution(choice, hs, t; ε, alpha_mode, maxwords)
    else
        return plan_evolution(choice::Composite, hs, t; ε, alpha_mode, maxwords)
    end
end
