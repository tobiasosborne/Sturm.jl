# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M12 phase 2 (bead Sturm.jl-8yzf):
# `Auto` dispatch — S14's reserved slot, the S8 merge of proposal A §7 (full
# candidate table, skipped-rows-with-reason, deterministic tie-break) and
# proposal B §6 (exactness fast paths; O(L log L) SURROGATE-cost dispatch).
#
# ── THE DIVISION OF LABOR (S8) ──────────────────────────────────────────────
# `evolve_plan` is PURE and CHEAP: it ranks candidates by their PROVEN costs
# computed from norm-bound α surrogates only (`alpha_mode = :norm1`, HW Lemma
# bounds_on_alpha_and_p) — Auto NEVER runs the exact α_comm DP (its job is
# O(L log L) dispatch; the DP can be exponential). The CHOSEN strategy's
# PLANNING then re-derives its resources with exact α per the phase-1
# conventions (`plan_evolution(::Auto)` below), so the shipped circuit's bound
# is always the exact one; the surrogate only picked the shape. A surrogate
# row that fails loudly (out-of-reach step ceiling) is recorded as a
# skipped-with-reason row, never silently dropped (A §7.3); if EVERY row is
# skipped the dispatch itself errors.
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
skipped), the `report` behind the cost (`nothing` when skipped), and
`skipped` — `nothing` for a live row, else the human-readable reason the row
was excluded (visible, never silent).
"""
struct PlanRow
    alg::EvolveAlg
    cost::Float64
    report::Union{BoundReport,Nothing}
    skipped::Union{String,Nothing}
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
# DomainError/ArgumentError (caller bugs) propagate.
function _candidate_row(f, alg::EvolveAlg)
    try
        (cost, report) = f()
        return PlanRow(alg, cost, report, nothing)
    catch err
        err isa ErrorException || rethrow()
        return PlanRow(alg, Inf, nothing, err.msg)
    end
end

"""
    AUTO_COMMUTING_GATE

Size gate on `Auto`'s O(L²) `iscommuting` exactness fast path (B §6/R4):
above it the check is skipped — skipping a FAST PATH is not a silent bound
substitution (the dispatch below is still proven-cost); the constant is a
loud engineering cap awaiting bench calibration (research step R4).
"""
const AUTO_COMMUTING_GATE = 2048

"""
    evolve_plan(hs::PauliSum{W}, t, ε;
                trotter_orders = (2, 4, 6), composite_orders = (2, 4)) -> EvolveChoice

The PURE `Auto` dispatch rule (public; S8). In order:

1. **Exactness fast paths** (physics, not heuristics): `nterms ≤ 1` ⇒
   `Trotter(order = 1, steps = 1)` — a single Pauli exponential IS
   `e^{−iHt}` exactly; `iscommuting(hs)` (gated `L ≤ AUTO_COMMUTING_GATE`) ⇒
   the same — commuting terms make S₁ exact (α ≡ 0; no bound is evaluated,
   so no division-by-zero path exists — docs/physics/childs_2019_trotter_error.md,
   the α → 0 degeneracy).
2. **Surrogate costs** (norm-bound α ONLY — `:norm1`; the DP never runs):
   `QDrift` via the exact transcendental N (S4 — λ-only, no α);
   `Trotter(order)` for `order ∈ trotter_orders` via the 2k step rule;
   `Composite(order)` for `order ∈ composite_orders` at the second-moment
   `K*` (zlokapa Lemma) with the S7 `N_B` — rows whose `K*` hits 0/L are
   skipped with reason (those regimes are the pure rows).
3. **Argmin + tie-breaks**: deterministic > randomized, lower order,
   Trotter > Composite (S8).

`ε` is the FULL diamond norm (S5). The chosen strategy carries FREE
resources — `plan_evolution` refills them with exact α (the surrogate picked
the shape, never the shipped bound).
"""
function evolve_plan(hs::PauliSum{W}, t::Real, ε::Real;
                     trotter_orders = (2, 4, 6),
                     composite_orders = (2, 4)) where {W}
    (isfinite(ε) && ε > 0) || throw(DomainError(ε,
        "evolve_plan: ε must be a finite positive full-diamond-norm target."))
    L = nterms(hs)
    T = abs(Float64(t))
    # 1 — exactness fast paths (resources PINNED: the plan needs no ε)
    if L ≤ 1 || (L ≤ AUTO_COMMUTING_GATE && iscommuting(hs))
        alg = Trotter(order = 1, steps = 1)
        why = L ≤ 1 ? "single non-identity term: one Pauli exponential is exact" :
                      "pairwise-commuting terms: the order-1 formula is exact (α ≡ 0)"
        rep = BoundReport(Float64(L), :exact_fast_path,
            "docs/physics/childs_2019_trotter_error.md — commuting terms make " *
            "the product formula exact (every commutator vanishes)",
            (L = L, reason = why))
        return EvolveChoice(alg, Float64(L), [PlanRow(alg, Float64(L), rep, nothing)])
    end
    table = PlanRow[]
    # 2 — surrogate candidate costs (:norm1 α only; O(L log L) total)
    push!(table, _candidate_row(QDrift()) do
        rep = qdrift_samples(hs.λ, T, ε)
        (rep.value, rep)
    end)
    for order in trotter_orders
        push!(table, _candidate_row(Trotter(; order)) do
            rep = trotter_steps(hs, T, ε; order, alpha_mode = :norm1)
            (rep.value * suzuki_sweep_count(order) * L, rep)
        end)
    end
    for order in composite_orders
        alg = Composite(; order)
        Υ = suzuki_sweep_count(order)
        # second-moment K* seed only (no refinement DP; norm1 pieces are O(1))
        K = L
        for cand in 0:L
            if hs.tail_m2[cand + 1] * T^2 ≤ ε
                K = cand
                break
            end
        end
        if K == 0 || K == L
            push!(table, PlanRow(alg, Inf, nothing,
                "K* = $K degenerates to pure " * (K == 0 ? "qDrift" : "Trotter") *
                " (covered by that row; zlokapa second-moment rule)"))
            continue
        end
        push!(table, _candidate_row(alg) do
            pq = _composite_RP_RQ(hs, K, T, ε; order, alpha_mode = :norm1)
            n = composite_nb(K, pq.Υ, pq.R_P, pq.R_Q)
            rep = composite_steps(hs, K, T, ε; order, N_B = n, alpha_mode = :norm1)
            (Υ * (Υ * K + n) * rep.value, rep)
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
    plan_evolution(alg::Auto, hs, t; ε, alpha_mode = :exact, maxwords = …)

`Auto` planning (S8 merge): `evolve_plan` picks the strategy SHAPE from
surrogate costs; the chosen shape is then planned with EXACT α per the
phase-1 conventions (`Composite` re-derives K/N_B/steps exactly; `Trotter`
re-derives steps exactly; `QDrift`'s N is already exact — S4 has no α). A
fast-path choice arrives fully pinned and is planned WITHOUT ε (the ε was
consumed by the dispatch decision; passing it on would trip rule 5, and
rightly — nothing is left for it to size).
"""
function plan_evolution(alg::Auto, hs::PauliSum{W}, t::Real;
                        ε::Union{Real,Nothing} = nothing,
                        alpha_mode::Symbol = :exact,
                        maxwords::Integer = ALPHA_MAXWORDS_DEFAULT) where {W}
    ε === nothing && throw(ArgumentError(
        "evolve!: give a target accuracy ε=… or explicit resources " *
        "(steps=…/N=…) — there is no default accuracy (S3)."))
    choice = evolve_plan(hs, t, ε).choice
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
