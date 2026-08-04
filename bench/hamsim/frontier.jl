# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# bench/hamsim/frontier.jl — the M12 frontier protocol (bead Sturm.jl-gmx0;
# merged from proposal B §8's skeleton + proposal A §9's protocol, per
# docs/design/m12-synthesis.md §8). For each (family, t, ε):
#
#   (a) CERTIFIED cost  = exp_count(plan_evolution(alg, hs, t; ε)) for
#       Trotter{2,4,6}, QDrift, Composite{2,4} and the Auto choice — the
#       proven-bound resource counts, the papers' operator-exponential unit;
#   (b) MEASURED cost (executed families, W ≤ 3): binary-search the minimal
#       resources whose EXACT dense (super)operator Choi distance ≤ ε —
#       r for Trotter, N for qDrift, r at the certified (K, N_B) for
#       Composite (proposal B §8's measured-error mode);
#   (c) reference curves: the Zlokapa envelope min_K(Kt + t²λ_K²/ε)
#       (docs/physics/zlokapa_2026_hamsim_lower_bounds.md, eq lb — an Ω(·)
#       bound: the SHAPE is normative, the constant is not) and the analytic
#       QSP overlay L·(t + log(1/ε)/loglog(1/ε)) (their eq qsp — ANALYTIC
#       ONLY, per the session-102 ruling: no implementation).
#
# ── α-MODE DISCIPLINE (R4 + c8rx; no silent substitution — Principle 1) ─────
# The exact α_comm DP is recomputed inside every plan_evolution call, so grid
# wall time forces a per-(family, order) decision made ONCE. That decision is
# `alpha_policy`, an EXPLICIT run configuration — never wall-clock, which made
# the gmx0-era CSVs load-dependent (bead Sturm.jl-c8rx: at load ~20 the same
# grid downgraded five L=256 families that a quiet box planned :exact, and
# two runs of the same code were not comparable):
#   :exact     every row plans at :exact; the only downgrade is the
#              deterministic AlphaCommBlowup memory-cap exit (the sanctioned
#              caller exit named by the exception itself). Wall-clock may
#              only ABORT, loudly (PROBE_TIMEBOX_S) — never select modes.
#   :budgeted  (default) the probe runs the SAME DP work-capped
#              (`alpha_comm_layered`, machine-independent propagation-step
#              budgets — the deterministic successor of the retired
#              0.2 s / 0.05 s wall thresholds).
#   :norm1     every grid row uses the explicit loose bound; no DP runs.
# Executed families always run exact (their DP support caps at 4^3 = 64).
# Modes stay recorded per row (frontier `alpha_mode` column + alpha CSV);
# `probe_seconds` stays as a DIAGNOSTIC column and influences nothing.

using Printf
using Statistics
using Random
using LinearAlgebra
using Sturm
using Sturm: PauliSum, nterms, iscommuting, plan_evolution, trajectory, exp_count,
             TrotterPlan, QDriftPlan, CompositePlan, evolve_plan,
             alpha_comm, alpha_comm_layered, AlphaCommBlowup,
             ALPHA_MAXWORDS_DEFAULT, AUTO_COMMUTING_GATE, composite_k,
             ALPHA_WORK_DEFAULT

const T_GRID = [0.5, 1.0, 2.0, 4.0, 8.0, 16.0, 32.0]     # log grid [0.5, 32]
const EPS_GRID = [1e-2, 1e-3, 1e-4]
const STRATS = [("T2", :trotter, 2), ("T4", :trotter, 4), ("T6", :trotter, 6),
                ("QD", :qdrift, 0), ("C2", :composite, 2), ("C4", :composite, 4)]

# Deterministic probe budgets (α policy :budgeted), in DP PROPAGATION STEPS —
# machine-independent replacements for the retired 0.2 s / 0.05 s wall-clock
# thresholds (c8rx). Calibration anchors, measured 2026-08-04 (steps are the
# unit precisely because wall varies by box: jpky's box did 2^20 steps in
# 25–50 ms; this one in 0.1–0.2 s):
#   L=256  order 2:  2^19.3 steps  → inside both gates (the row class the
#          old wall threshold flipped under load — first-call COMPILE alone
#          pushed 0.06 s → 0.52 s across the 0.2 s line);
#   L=256  order 4:  2^23.5 (≈2 s), order 6: 2^25.8 (≈12 s) → out of reach
#          under either regime; deterministically :norm1 now.
# Composite planning multiplies DP calls (composite_k evaluates ~3 candidates
# × 3 α_comm engine runs each), hence the tighter composite gate.
const PROBE_WORK_TROTTER = 4_194_304     # 2^22
const PROBE_WORK_COMPOSITE = 1_048_576   # 2^20 (ALPHA_WORK_DEFAULT's class)
# Wall-clock may only ABORT a run, loudly — it never selects what is computed
# (c8rx). Only reachable under alpha_policy = :exact, where one slow probe
# implies every (t, ε) cell of the family re-runs the same DP in
# plan_evolution and the grid would take days.
const PROBE_TIMEBOX_S = 600.0
const ANALYTIC_SELFCHECK_CAP = 100_000

"The Zlokapa frontier envelope min_K(Kt + t²λ_K²/ε), read off tail_λ (λ = 1)."
envelope(hs::PauliSum, t::Real, ε::Real) =
    minimum(K * t + t^2 * hs.tail_λ[K + 1]^2 / ε for K in 0:nterms(hs))

"The analytic QSP overlay L·(t + log(1/ε)/loglog(1/ε)) (zlokapa eq qsp)."
qsp_overlay(L::Int, t::Real, ε::Real) = L * (t + log(1 / ε) / log(log(1 / ε)))

# ── α probes ────────────────────────────────────────────────────────────────

struct AlphaProbe
    order::Int
    mode_trotter::Symbol
    mode_composite::Symbol
    alpha::Float64        # NaN when unknown (blowup / probe skipped)
    norm1::Float64        # the HW Lemma bound 2^2k·λ^{2k+1}
    seconds::Float64      # NaN when the probe did not run
    note::String
end

"""
    probe_family(hs; policy, force_exact = false) -> Dict{Int,AlphaProbe}

One α probe per order ∈ {2, 4, 6}, deciding the grid's per-(family, order)
`alpha_mode` DETERMINISTICALLY from `policy` (c8rx — two runs of the same
command must plan the same cells at the same exactness, whatever the load):

  * `:exact` — one unbudgeted exact-α probe per order against the DEFAULT
    maxwords cap. A blowup at order 2k implies blowups at every higher order
    (the DP propagates strictly more layers over a superset support), so
    higher probes are skipped as "cap hit by implication". Wall-clock is a
    LOUD ABORT only (`PROBE_TIMEBOX_S`), never a downgrade.
  * `:budgeted` — the probe runs the SAME DP work-capped
    (`alpha_comm_layered`; step budgets are machine-independent). Completion
    within `PROBE_WORK_TROTTER` steps ⇒ Trotter rows plan `:exact`; within
    `PROBE_WORK_COMPOSITE` too ⇒ Composite rows as well. A budget or cap
    stop ⇒ `:norm1`, with the proven partial-depth bound `B_d` recorded in
    the note (the value the DP *did* prove — never substituted for α).
    Each probe costs ≤ the budget, so all three orders are always probed.
  * `:norm1` — every grid row uses the explicit loose bound; no DP runs.

`force_exact` (executed families) overrides any policy: modes stay `:exact`
(their DP support caps at 4^3 = 64), times recorded, never downgraded.
"""
function probe_family(hs::PauliSum; policy::Symbol, force_exact::Bool = false)
    probes = Dict{Int,AlphaProbe}()
    blown = false
    for order in (2, 4, 6)
        norm1 = 2.0^order * hs.λ^(order + 1)
        if !force_exact && policy === :norm1
            probes[order] = AlphaProbe(order, :norm1, :norm1, NaN, norm1, NaN,
                "policy :norm1 (no DP run)")
            continue
        elseif blown
            probes[order] = AlphaProbe(order, :norm1, :norm1, NaN, norm1, NaN,
                "cap hit by implication (lower order blew up)")
            continue
        end
        t0 = time()
        if force_exact || policy === :exact
            try
                α = alpha_comm(hs, order)
                dt = time() - t0
                if !force_exact && dt > PROBE_TIMEBOX_S
                    error("probe_family: the exact-α probe (order $order) took " *
                        @sprintf("%.1f", dt) * " s > PROBE_TIMEBOX_S = " *
                        "$PROBE_TIMEBOX_S s. Under alpha_policy = :exact every " *
                        "(t, ε) cell of this family re-runs the same DP inside " *
                        "plan_evolution, so the grid would multiply this cost " *
                        "~$(length(T_GRID) * length(EPS_GRID))×. ABORTING LOUDLY " *
                        "— nothing was silently downgraded (c8rx). Rerun with " *
                        "alpha_policy = :budgeted or :norm1.")
                end
                probes[order] = AlphaProbe(order, :exact, :exact, α, norm1, dt, "")
            catch e
                e isa AlphaCommBlowup || rethrow()
                dt = time() - t0
                blown = true
                probes[order] = AlphaProbe(order, :norm1, :norm1, NaN, norm1, dt,
                    "ALPHA_MAXWORDS_DEFAULT HIT: support=$(e.support) layer=$(e.layer)")
            end
        else                                        # policy === :budgeted
            la = alpha_comm_layered(hs, order; work = PROBE_WORK_TROTTER)
            dt = time() - t0
            if la.exact
                mc = la.work ≤ PROBE_WORK_COMPOSITE ? :exact : :norm1
                note = mc === :exact ? "" :
                    "work gate: composite rows at :norm1 (DP work $(la.work) > " *
                    "PROBE_WORK_COMPOSITE = $PROBE_WORK_COMPOSITE)"
                probes[order] = AlphaProbe(order, :exact, mc, la.value, norm1, dt, note)
            else
                probes[order] = AlphaProbe(order, :norm1, :norm1, NaN, norm1, dt,
                    @sprintf("work budget: proven partial bound B_%d=%.6g; ",
                             la.layers, la.value) * _sanitize(la.reason))
            end
        end
    end
    return probes
end

# ── certified costs ─────────────────────────────────────────────────────────

struct Cert
    cost::Float64          # Inf when skipped
    plan::Any              # nothing when skipped
    mode::Symbol
    kind::String           # concrete plan type (degenerations visible)
    K::Int                 # -1 = not applicable
    N_B::Int               # -1 = not applicable
    r::Int                 # steps (Trotter/Composite) or N (QDrift)
    skipped::String
end

_describe(p::TrotterPlan) = ("TrotterPlan", -1, -1, p.steps)
_describe(p::QDriftPlan) = ("QDriftPlan", -1, -1, p.N)
_describe(p::CompositePlan) = ("CompositePlan", p.K, p.N_B, p.steps)

_sanitize(msg::AbstractString) =
    first(replace(replace(msg, "," => ";"), "\n" => " "), 140)

"Certified cost of one candidate strategy; loud out-of-reach errors become skipped rows."
function certified(kind::Symbol, order::Int, hs::PauliSum, t::Float64, ε::Float64,
                   probes::Dict{Int,AlphaProbe})
    alg = kind === :qdrift ? QDrift() :
          kind === :trotter ? Trotter(; order) : Composite(; order)
    mode = kind === :qdrift ? :exact :
           kind === :trotter ? probes[order].mode_trotter : probes[order].mode_composite
    try
        plan = kind === :qdrift ? plan_evolution(alg, hs, t; ε) :
               plan_evolution(alg, hs, t; ε, alpha_mode = mode)
        (pk, K, NB, r) = _describe(plan)
        return Cert(Float64(exp_count(plan)), plan, mode, pk, K, NB, r, "")
    catch e
        if e isa AlphaCommBlowup
            return Cert(Inf, nothing, mode, "", -1, -1, -1,
                        "alpha-blowup support=$(e.support) layer=$(e.layer)")
        elseif e isa ErrorException
            return Cert(Inf, nothing, mode, "", -1, -1, -1, _sanitize(e.msg))
        end
        rethrow()
    end
end

"Auto's certified plan: evolve_plan picks the shape; the shape is planned at the family's α mode (mirrors auto.jl's S8 division of labor)."
function certified_auto(hs::PauliSum, t::Float64, ε::Float64,
                        probes::Dict{Int,AlphaProbe})
    ec = evolve_plan(hs, t, ε)
    ch = ec.choice
    label = ch isa QDrift ? "QD" :
            ch isa Trotter ? "T$(ch.order)" : "C$(ch.order)"
    nskip = count(r -> r.skipped !== nothing, ec.table)
    # α provenance of the CHOSEN row (bead Sturm.jl-jpky): the shallowest
    # exact DP depth behind the ranking, and whether every α it consumed was
    # the exact α_comm. Empty for rows that consume no α (QDrift; fast paths).
    chosen = ec.table[findfirst(r -> r.alg == ch, ec.table)]
    alayers = isempty(chosen.alpha) ? "" : string(minimum(a.layers for a in chosen.alpha))
    aexact = isempty(chosen.alpha) ? "" : string(all(a -> a.exact, chosen.alpha))
    try
        (mode, plan) = if ch isa Trotter && ch.steps !== nothing   # exactness fast path
            (:exact, plan_evolution(ch, hs, t))
        elseif ch isa QDrift
            (:exact, plan_evolution(ch, hs, t; ε))
        elseif ch isa Trotter
            m = probes[ch.order].mode_trotter
            (m, plan_evolution(ch, hs, t; ε, alpha_mode = m))
        else
            m = probes[ch.order].mode_composite
            (m, plan_evolution(ch::Composite, hs, t; ε, alpha_mode = m))
        end
        (pk, K, NB, r) = _describe(plan)
        return (label = label, nskip = nskip, alayers = alayers, aexact = aexact,
                cert = Cert(Float64(exp_count(plan)), plan, mode, pk, K, NB, r, ""))
    catch e
        e isa Union{AlphaCommBlowup,ErrorException} || rethrow()
        msg = e isa AlphaCommBlowup ?
              "alpha-blowup support=$(e.support) layer=$(e.layer)" : _sanitize(e.msg)
        return (label = label, nskip = nskip, alayers = alayers, aexact = aexact,
                cert = Cert(Inf, nothing, :exact, "", -1, -1, -1, msg))
    end
end

# ── measured tier (executed families) ───────────────────────────────────────

"Least x ∈ [lo, hi] with pred(x), assuming monotone pred; `nothing` if pred(hi) fails."
function bsearch_min(pred, lo::Int, hi::Int)
    pred(hi) || return nothing
    while lo < hi
        mid = lo + (hi - lo) ÷ 2
        pred(mid) ? (hi = mid) : (lo = mid + 1)
    end
    return hi
end

"""
    measured_min(kind, order, hs, t, ε, cert, gt) -> (cost, plan) | nothing

The measured-error mode: minimal resources whose exact Choi distance to
e^{−iHt} is ≤ ε, bracketed above by the certified resources (the certified
FULL-diamond bound ≤ ε dominates the Choi distance, so the predicate is
guaranteed at the bracket top — its failure would be a bound violation and
throws). Composite plans that degenerated to pure strategies return
`nothing` (covered by the pure rows).
"""
function measured_min(kind::Symbol, order::Int, hs::PauliSum, t::Float64,
                      ε::Float64, cert::Cert, gt)
    cert.plan === nothing && return nothing
    mk(r) = kind === :trotter ? plan_evolution(Trotter(; order, steps = r), hs, t) :
            plan_evolution(Composite(; order, K = cert.plan.K,
                                     N_B = cert.plan.N_B, steps = r), hs, t)
    local pred
    if kind === :trotter
        pred = r -> begin
            p = mk(r)
            choi_dist(ad_super(sweep_unitary(p.sweep, gt.wm)^r), gt.Sex, gt.d) ≤ ε
        end
        hi = cert.plan.steps
    elseif kind === :qdrift
        pred = N -> choi_dist(qdrift_step_super(hs, hs.λ * t / N, gt.wm)^N,
                              gt.Sex, gt.d) ≤ ε
        hi = cert.plan.N
    else
        cert.plan isa CompositePlan || return nothing        # degenerate split
        pred = r -> choi_dist(composite_super(mk(r), gt.wm, gt.d), gt.Sex, gt.d) ≤ ε
        hi = cert.plan.steps
    end
    x = bsearch_min(pred, 1, hi)
    x === nothing && error(
        "measured_min($kind, order=$order, t=$t, ε=$ε): the certified resources " *
        "FAIL the measured Choi-≤-ε predicate — the Choi distance lower-bounds " *
        "the certified diamond bound, so this is a bound violation in src/. " *
        "STOP: do not bench this path further; report it.")
    plan = kind === :qdrift ? plan_evolution(QDrift(N = x), hs, t) : mk(x)
    return (Float64(exp_count(plan)), plan)
end

# ── the protocol driver ─────────────────────────────────────────────────────

"Second-moment K* seed (auto.jl's rule): least K with tail_m2[K+1]·t² ≤ ε."
function k_seed(hs::PauliSum, t::Float64, ε::Float64)
    for K in 0:nterms(hs)
        hs.tail_m2[K + 1] * t^2 ≤ ε && return K
    end
    return nterms(hs)
end

function run_frontier(; fast::Bool = false, only::Symbol = :all,
                      alpha_policy::Symbol = :budgeted,
                      outdir::String = joinpath(@__DIR__, "..", "out"))
    alpha_policy in (:exact, :budgeted, :norm1) || throw(ArgumentError(
        "run_frontier: alpha_policy must be :exact, :budgeted or :norm1 " *
        "(got :$alpha_policy). The α mode of a run is explicit configuration, " *
        "never a wall-clock consequence (c8rx)."))
    t_start = time()
    mkpath(outdir)
    fams = bench_families(fast = fast)
    only === :all || (fams = [f for f in fams if (only === :exec) == f.executed])
    tgrid = fast ? [1.0, 8.0] : T_GRID
    egrid = fast ? [1e-2, 1e-3] : EPS_GRID
    tag = fast ? "fast" : String(only)
    # non-default policies get their own file tag so runs never shadow each
    # other; a CSV is only comparable to another CSV with the same policy.
    alpha_policy === :budgeted || (tag *= "-" * String(alpha_policy))
    println("α policy: :$alpha_policy (deterministic mode selection — c8rx)")

    frontier_rows = String[]
    auto_rows = String[]
    alpha_rows = String[]
    violations = String[]
    selfchecks = 0
    selfcheck_skipped_big = 0
    regrets = Float64[]
    disagreements = String[]
    exec_cells = 0
    agree_cells = 0
    kdis = 0
    kcells = 0
    slack = Dict(s[1] => Float64[] for s in STRATS)
    cert_over_env = Dict{String,Vector{Float64}}()
    meas_over_env = Float64[]
    winners = Dict{Tuple{String,Float64},Vector{String}}()   # (family, ε) → per-t winner
    commuting_gate_hit = false
    max_L = 0

    for fam in fams
        hs = fam.hs
        max_L = max(max_L, fam.L)
        fam.L > AUTO_COMMUTING_GATE && (commuting_gate_hit = true)
        @printf("· %-22s L=%-4d W=%-2d %s\n", fam.name, fam.L, fam.W,
                fam.executed ? "[executed]" : "[analytic]")
        flush(stdout)
        probes = probe_family(hs; policy = alpha_policy,
                              force_exact = fam.executed)
        for o in (2, 4, 6)
            p = probes[o]
            push!(alpha_rows, join([fam.name, o, p.mode_trotter, p.mode_composite,
                @sprintf("%.6g", p.alpha), @sprintf("%.6g", p.norm1),
                isnan(p.alpha) ? "" : @sprintf("%.3g", p.norm1 / p.alpha),
                isnan(p.seconds) ? "" : @sprintf("%.3f", p.seconds),
                _sanitize(p.note), alpha_policy], ","))
        end
        gt0 = nothing
        if fam.executed
            wm = family_wordmats(hs)
            F = exact_factor(ham_matrix(hs, wm))
            gt0 = (wm = wm, F = F, d = 1 << fam.W)
            drep = orkan_replay_check(hs, fam.W, wm)
            drep ≤ 1e-9 || error(
                "orkan_replay_check($(fam.name)): executor/dense replay " *
                "distance $drep > 1e-9 — the pipe itself is broken; stop.")
        end
        for t in tgrid
            gt = gt0 === nothing ? nothing :
                 (wm = gt0.wm, d = gt0.d, Sex = ad_super(u_exact(gt0.F, t)))
            for ε in egrid
                env = envelope(hs, t, ε)
                qsp = qsp_overlay(fam.L, t, ε)
                certs = Dict{String,Cert}()
                meas = Dict{String,Float64}()
                for (label, kind, order) in STRATS
                    c = certified(kind, order, hs, t, ε, probes)
                    certs[label] = c
                    mcost = NaN
                    if fam.executed && c.plan !== nothing
                        selfcheck_plan(c.plan) || error(
                            "selfcheck: exp_count ≠ trajectory length for the " *
                            "certified $label plan at ($(fam.name), t=$t, ε=$ε).")
                        selfchecks += 1
                        m = measured_min(kind, order, hs, t, ε, c, gt)
                        if m !== nothing
                            (mcost, mplan) = m
                            selfcheck_plan(mplan) || error(
                                "selfcheck: exp_count ≠ trajectory length for the " *
                                "measured $label plan at ($(fam.name), t=$t, ε=$ε).")
                            selfchecks += 1
                            meas[label] = mcost
                            push!(slack[label], c.cost / mcost)
                            push!(meas_over_env, mcost / env)
                        end
                    elseif c.plan !== nothing && exp_count(c.plan) ≤ ANALYTIC_SELFCHECK_CAP
                        selfcheck_plan(c.plan) || error(
                            "selfcheck: exp_count ≠ trajectory length (analytic " *
                            "$label at $(fam.name), t=$t, ε=$ε).")
                        selfchecks += 1
                    elseif c.plan !== nothing
                        selfcheck_skipped_big += 1
                    end
                    push!(frontier_rows, join([fam.name, fam.coeffs, fam.L, fam.W,
                        fam.executed, t, ε, label, c.mode,
                        isfinite(c.cost) ? @sprintf("%.10g", c.cost) : "",
                        c.kind, c.K, c.N_B, c.r,
                        isnan(mcost) ? "" : @sprintf("%.10g", mcost),
                        isnan(mcost) ? "" : @sprintf("%.4g", c.cost / mcost),
                        @sprintf("%.6g", env),
                        isfinite(c.cost) ? @sprintf("%.4g", c.cost / env) : "",
                        @sprintf("%.6g", qsp), c.skipped], ","))
                    if isfinite(c.cost)
                        push!(get!(cert_over_env, fam.coeffs, Float64[]), c.cost / env)
                    end
                end
                # winner map (certified argmin over the six concrete
                # strategies) — an explicit deterministic scan in STRATS
                # order (ties → first, i.e. deterministic-first), with a
                # loud self-consistency assert: an early --fast run once
                # emitted a winner label contradicting the SAME cell's
                # best_cost two statements later (never reproduced); if
                # that ever recurs this catches it in-iteration.
                best_label = ""
                best_cost = Inf
                for (label, _, _) in STRATS
                    c = certs[label].cost
                    if isfinite(c) && c < best_cost
                        best_label = label
                        best_cost = c
                    end
                end
                isempty(best_label) && error(
                    "frontier: every strategy skipped at ($(fam.name), t=$t, ε=$ε).")
                certs[best_label].cost == best_cost == minimum(
                    c.cost for c in values(certs) if isfinite(c.cost)) || error(
                    "frontier: winner bookkeeping inconsistent at " *
                    "($(fam.name), t=$t, ε=$ε): $best_label/$best_cost vs certs.")
                push!(get!(winners, (fam.name, ε), String[]),
                      @sprintf("t=%g:%s", t, best_label))
                # Auto row
                au = certified_auto(hs, t, ε, probes)
                if au.cert.plan === nothing
                    push!(violations, "Auto plan failed at ($(fam.name), t=$t, ε=$ε): $(au.cert.skipped)")
                end
                regret = au.cert.cost / best_cost
                isfinite(regret) && push!(regrets, regret)
                regret > 1.0 + 1e-12 && push!(disagreements,
                    @sprintf("%s t=%g ε=%g: Auto=%s cost=%.4g vs best=%s cost=%.4g (regret %.3f)",
                             fam.name, t, ε, au.label, au.cert.cost, best_label,
                             best_cost, regret))
                Ks = k_seed(hs, t, ε)
                Ke = try
                    composite_k(hs, t, ε; order = 2,
                                alpha_mode = probes[2].mode_composite)
                catch e
                    e isa Union{AlphaCommBlowup,ErrorException} || rethrow()
                    -1
                end
                if Ke ≥ 0
                    kcells += 1
                    Ks != Ke && (kdis += 1)
                end
                margmin = ""
                agree = ""
                if fam.executed && !isempty(meas)
                    exec_cells += 1
                    margmin = argmin(meas)
                    ag = margmin == au.label
                    ag && (agree_cells += 1)
                    agree = string(ag)
                    ag || push!(disagreements,
                        @sprintf("%s t=%g ε=%g: Auto chose %s; measured argmin %s (measured %s=%.4g)",
                                 fam.name, t, ε, au.label, margmin, margmin, meas[margmin]))
                end
                push!(auto_rows, join([fam.name, fam.L, t, ε, au.label,
                    isfinite(au.cert.cost) ? @sprintf("%.10g", au.cert.cost) : "",
                    best_label, @sprintf("%.10g", best_cost),
                    isfinite(regret) ? @sprintf("%.4g", regret) : "",
                    margmin, agree, Ks, Ke, Ks != Ke && Ke ≥ 0, au.nskip,
                    au.alayers, au.aexact], ","))
            end
        end
    end

    # ── emit ────────────────────────────────────────────────────────────────
    open(joinpath(outdir, "frontier-$tag.csv"), "w") do io
        println(io, "family,coeffs,L,W,executed,t,eps,strategy,alpha_mode," *
                    "certified_cost,plan_kind,K,N_B,steps_or_N,measured_cost," *
                    "slack,envelope,cert_over_env,qsp_overlay,skipped")
        foreach(r -> println(io, r), frontier_rows)
    end
    open(joinpath(outdir, "auto-$tag.csv"), "w") do io
        println(io, "family,L,t,eps,auto_choice,auto_cost,best_strategy," *
                    "best_cost,regret,measured_argmin,agree,K_seed,K_exact2," *
                    "K_disagree,auto_skipped_rows,auto_alpha_layers,auto_alpha_exact")
        foreach(r -> println(io, r), auto_rows)
    end
    open(joinpath(outdir, "alpha-$tag.csv"), "w") do io
        println(io, "family,order,mode_trotter,mode_composite,alpha_exact," *
                    "alpha_norm1,norm1_over_exact,probe_seconds,note,policy")
        foreach(r -> println(io, r), alpha_rows)
    end

    # ── summary (the report payload) ────────────────────────────────────────
    println("\n══ WINNERS (certified argmin per cell) ══")
    for ((name, ε), ws) in sort(collect(winners); by = k -> (k[1][1], k[1][2]))
        @printf("  %-22s ε=%-6g %s\n", name, ε, join(ws, " "))
    end
    println("\n══ AUTO REGRET (chosen certified cost / best certified cost) ══")
    if !isempty(regrets)
        @printf("  cells=%d  regret==1: %d (%.1f%%)  median=%.4g  p90=%.4g  max=%.4g\n",
                length(regrets), count(≈(1.0), regrets),
                100 * count(≈(1.0), regrets) / length(regrets),
                median(regrets), quantile(regrets, 0.9), maximum(regrets))
    end
    println("\n══ DISAGREEMENTS (regret > 1 or Auto ≠ measured argmin) ══")
    foreach(d -> println("  ", d), disagreements)
    isempty(disagreements) && println("  (none)")
    if exec_cells > 0
        @printf("\n══ AUTO vs MEASURED argmin agreement: %d/%d (%.1f%%) ══\n",
                agree_cells, exec_cells, 100 * agree_cells / exec_cells)
    end
    println("\n══ BOUND SLACK (certified/measured), executed tier ══")
    for (label, v) in sort(collect(slack))
        isempty(v) && continue
        @printf("  %-3s n=%-3d min=%.3g med=%.3g max=%.3g\n",
                label, length(v), minimum(v), median(v), maximum(v))
    end
    println("\n══ ENVELOPE (cost / min_K(Kt + t²λ_K²/ε)) ══")
    for (cl, v) in sort(collect(cert_over_env))
        @printf("  certified %-14s n=%-4d min=%.3g med=%.3g max=%.3g\n",
                cl, length(v), minimum(v), median(v), maximum(v))
    end
    if !isempty(meas_over_env)
        @printf("  measured (exec)      n=%-4d min=%.3g med=%.3g max=%.3g\n",
                length(meas_over_env), minimum(meas_over_env),
                median(meas_over_env), maximum(meas_over_env))
    end
    @printf("\n══ K RULE: proxy (2nd-moment seed) vs exact composite_k(order 2): %d/%d cells disagree ══\n",
            kdis, kcells)
    println("\n══ R4 CALIBRATION ══")
    println("  α policy: :$alpha_policy — mode selection is run configuration " *
            "(c8rx); wall-clock never picks modes, probe_seconds is diagnostic only")
    caphits = [r for r in alpha_rows if occursin("HIT", r) || occursin("implication", r)]
    println("  ALPHA_MAXWORDS_DEFAULT = $(ALPHA_MAXWORDS_DEFAULT): " *
            (isempty(caphits) ? "never hit on this grid" :
             "$(length(caphits)) (family, order) probes hit the cap (see alpha-$tag.csv)"))
    foreach(r -> println("    ", r), caphits)
    budgethits = [r for r in alpha_rows if occursin("work budget", r) ||
                                           occursin("work gate", r)]
    println("  PROBE_WORK_TROTTER/COMPOSITE = $PROBE_WORK_TROTTER/" *
            "$PROBE_WORK_COMPOSITE steps: " *
            (isempty(budgethits) ? "no deterministic budget downgrades" :
             "$(length(budgethits)) (family, order) probes downgraded by the " *
             "work budget (deterministic — see alpha-$tag.csv)"))
    foreach(r -> println("    ", r), budgethits)
    tcomm = max_L > 0 ? (@elapsed iscommuting(fams[end].hs)) : NaN
    println("  AUTO_COMMUTING_GATE = $(AUTO_COMMUTING_GATE): max grid L = $max_L — " *
            (commuting_gate_hit ? "GATE HIT" : "never gates") *
            @sprintf(" (iscommuting at L=%d: %.3g s)", fams[end].L, tcomm))
    nexact = count(r -> endswith(r, ",true"), auto_rows)
    nprov = count(r -> !endswith(r, ","), auto_rows)
    println("  ALPHA_WORK_DEFAULT = $(ALPHA_WORK_DEFAULT) (Auto's ranking budget): " *
            "$nexact/$nprov α-consuming chosen rows ranked at EXACT α_comm " *
            "(the rest carry a proven partial-depth bound; see " *
            "auto_alpha_layers in auto-$tag.csv)")
    @printf("\n══ self-checks: %d passed, %d skipped (analytic, exp_count > %d) ══\n",
            selfchecks, selfcheck_skipped_big, ANALYTIC_SELFCHECK_CAP)
    if !isempty(violations)
        println("\n!! VIOLATIONS / FAILURES (investigate before trusting the run) !!")
        foreach(v -> println("  ", v), violations)
    end
    @printf("\nwall time: %.1f s  (tag=%s, %d families, %d frontier rows)\n",
            time() - t_start, tag, length(fams), length(frontier_rows))
    return nothing
end
