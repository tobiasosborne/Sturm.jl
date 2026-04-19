# Shor DAG scaling benchmark.
#
# Traces each implementation under TracingContext (no Orkan simulation)
# and records DAG size, per-type gate counts, wire HWM, and wall-clock
# build time as a function of the register width L and counter width t.
#
# Preflight cost model + async OOM watchdog (Sturm.jl-8jx).
# Every stage prints to stderr with explicit flush — any stall is visible
# at the last printed line (principle: feedback_verbose_eager_flush).
#
# Invoke:
#     LIBORKAN_PATH=…/liborkan.so julia --project test/bench_shor_scaling.jl
#
# Environment overrides:
#     STURM_BENCH_BUDGET_GB     — per-case memory budget (default: 30% of free RAM)
#     STURM_BENCH_WATCHDOG_GB   — watchdog aborts if free RAM drops below this (default: 4.0)
#     STURM_BENCH_ONLY          — comma-separated impls, e.g. "A,C" (default: A,B,C)
#     STURM_BENCH_MAX_L         — skip cases with L greater than this (default: no cap)
#     STURM_BENCH_DRY_RUN=1     — print the preflight table and exit without tracing

using Sturm
using Sturm: CXNode, RyNode, RzNode, ObserveNode, DiscardNode, HotNode
using Sturm: _wire_counter

@inline function LOG(msg::AbstractString)
    println(stderr, msg)
    flush(stderr)
end

_ms(start_ns) = round((time_ns() - start_ns) / 1e6, digits=1)

fmt_bytes(b::Real) =
    b < 1024        ? "$(round(Int, b)) B"  :
    b < 1024^2      ? "$(round(b/1024,     digits=1)) KB" :
    b < 1024^3      ? "$(round(b/1024^2,   digits=1)) MB" :
                      "$(round(b/1024^3,   digits=2)) GB"

# ── Cost model ─────────────────────────────────────────────────────────────
#
# Per-node storage: HotNode is an isbits-union, 25 bytes/element in
# TracingContext.dag (confirmed Session 3, WORKLOG 2026-04-06).
const NODE_BYTES = 25

# Julia runtime + GC churn + Vector re-growth overhead. A Vector{HotNode}
# at peak may hold 2× the final element count during doubling, and Julia's
# GC retains dead backing briefly. Empirically ~3× the raw `gates × NODE_BYTES`
# is a safe upper bound.
const RUNTIME_OVERHEAD = 3.0

"""
    estimate_gates(impl, L, t) -> Int

Back-of-envelope gate-count projection per implementation. Deliberately
over-estimating: the point is to skip cases that might OOM, so under-
estimation is the dangerous direction.

  * Impl A — value-oracle lift: one QROM with 2^t entries, each L-bit
    wide. Measured scaling across L=4..9/t=2L is ~17·2^t (nearly
    L-independent; the per-output-bit CX fanout is dominated by internal
    unary decoding). Formula: `(L + 1) · 2^(t+2)` — calibrated to stay
    ≥ actual at every measured point, max ratio 2.3× at L=9.

  * Impl B — phase-estimation HOF: 2^t − 1 mulmod calls per shot, each
    with a 2^(L+1)-entry QROM producing an L-bit output. The naïve
    `2^(t+L+1)` (previous ship) under-counts by 16–20× because each
    QROM entry emits (L+12) gates for output fanout. Empirical exact
    fit is `(L + 12) · 2^(t+L+1)` — ratio 0.997–1.003 across L=4..8
    on the 2026-04-18 big run. Shipped with +2 safety margin:
    `(L + 14) · 2^(t + L + 1)`, ratio 1.05–1.13× (conservative).

    The previous bug (2^(t+L+1) alone) greenlit L=8/t=16 at 2.34 GB
    projected memory. Actual DAG was 15.74 GB. We didn't OOM only
    because 60 GB was free. Fixed here.

    At L=9/t=18 this predicts 5.78 G gates = 433 GB — skipped on any
    reasonable budget.

  * Impl C — controlled-U^(2^j) cascade: t mulmod calls per shot, each
    with forward+inverse QROM over 2^L entries and L-bit output.
    Empirical fit: `(4L + 50) · t · 2^L` matches L=4..9 measurements to
    within 2% across all six data points. Formula uses 1.3× safety
    margin: `(5L + 65) · t · 2^L` — min ratio 1.31× at every measured
    point.

  * Impl D — Beauregard arithmetic mulmod cascade: same t mulmod calls
    as impl C, but each is Beauregard 2003 Fig. 7 c-U_a instead of a
    packed QROM. Empirical fit: per-mulmod gates ≈ `77·L²` (L=5/L=6
    measurements agree to 0.5%), slope = 3.0 → O(L^3) per order-find at
    fixed t, O(L^4) at t = 2L. Formula uses 1.30× safety margin:
    `100 · t · L^2`. Mulmods with classical constant a_j = 1 are
    skipped at runtime (identity op), so the est/actual ratio can
    inflate for cases where many a_j's saturate to 1 (e.g. N=15 with
    `a=7` has order 4, so a_j ∈ {7,4,1,1,1,1,1,1} at t=8 — only 2
    non-trivial, ratio ≈5×). This is fine: over-estimation for
    preflight is safe.

  Calibration table (t=2L; ratios = est / actual, all ≥ 1):

      L   t    A actual    A est     A ratio    C actual    C est     C ratio
      4   8       4 204    5 120       1.22        8 305   10 880       1.31
      5  10      15 173   24 576       1.62       21 961   28 800       1.31
      6  12      65 742  114 688       1.74       55 609   72 960       1.31
      7  14     270 605  524 288       1.94      136 641  179 200       1.31
      8  16   1 114 458  2 359 296     2.12      328 289  430 080       1.31
      9  18   4 587 953  10 485 760    2.29      774 937  1 013 760     1.31

Used ONLY to decide whether to run a case; actual gate counts come from
the trace and are reported in the summary as est-vs-actual ratio.
"""
function estimate_gates(impl::Symbol, L::Int, t::Int)
    if impl === :A
        (L + 1) * (1 << (t + 2))            # (L + 1) · 2^(t+2)
    elseif impl === :B
        (L + 14) * (1 << (t + L + 1))       # (L + 14) · 2^(t+L+1) — 10% safety margin
    elseif impl === :C
        (5 * L + 65) * t * (1 << L)         # (5L + 65) · t · 2^L
    elseif impl === :D
        # Beauregard arithmetic mulmod, O(L^4) at t = 2L.
        # Calibrated from L=5..6 all-non-trivial runs (2026-04-19):
        #   per-mulmod gates ≈ 77·L² (L=5: 1940/mulmod, L=6: 2779/mulmod;
        #   ratio fits 77·L² to 0.5%).  Empirical slope (ln gates vs ln L)
        #   = 3.0 at fixed t, i.e. O(L^3) per order-find for fixed t, or
        #   O(L^4) at t = 2L — matches Beauregard §3 "O(n^3 k_max)" with
        #   exact QFT (k_max = L).
        # Formula `100·t·L²` applies 1.30× safety margin over the fit.
        # L=4 N=15 a=7 is NOT representative: only 2 of 8 mulmods fire
        # (a_j = 7,4,1,1,1,1,1,1 skipped after order saturation), so the
        # est-vs-actual ratio inflates to 5× at L=4. Preflight erring on
        # the high side is correct — never under-budget.
        100 * t * L * L
    else
        error("unknown impl $impl")
    end
end

"""
    estimate_bytes(impl, L, t) -> Int

Projected peak RAM in bytes for the DAG alone, including runtime overhead.
Does NOT include classical precompute tables (Impl A's 2^t UInt64 mod-N
table is ~8·2^t bytes extra — negligible until t > 30).
"""
function estimate_bytes(impl::Symbol, L::Int, t::Int)
    round(Int, estimate_gates(impl, L, t) * NODE_BYTES * RUNTIME_OVERHEAD)
end

"""
    preflight(impl, L, t; budget_bytes) -> NamedTuple

Returns a verdict on whether this case should be run.  `ok=false` means
the projected memory exceeds the configured budget and the case MUST be
skipped — not running it is the whole point.
"""
function preflight(impl::Symbol, L::Int, t::Int; budget_bytes::Int)
    gates = estimate_gates(impl, L, t)
    mem   = estimate_bytes(impl, L, t)
    ok    = mem <= budget_bytes
    (ok=ok, gates=gates, mem=mem, budget=budget_bytes)
end

# ── OOM watchdog ───────────────────────────────────────────────────────────
#
# Async task that samples free system memory every second. If free RAM
# drops below a hard floor, we exit(137) — the same signal the kernel
# OOM-killer would use, but from userspace, so the last few lines of
# stderr make it into the log instead of being silently truncated.

const WATCHDOG_ACTIVE = Ref(true)

function start_watchdog(abort_threshold_bytes::Int; interval_s::Float64=1.0)
    Threads.@spawn begin
        while WATCHDOG_ACTIVE[]
            free = Int(Sys.free_memory())
            if free < abort_threshold_bytes
                LOG("")
                LOG("!!! OOM WATCHDOG: free RAM $(fmt_bytes(free)) < threshold " *
                    "$(fmt_bytes(abort_threshold_bytes)). Aborting before kernel kills us.")
                LOG("!!! Exit 137 (simulated SIGKILL). See WORKLOG entry for Sturm.jl-8jx.")
                flush(stderr)
                exit(137)
            end
            sleep(interval_s)
        end
    end
end

# ── DAG analysis ───────────────────────────────────────────────────────────

"""
    node_breakdown(ctx::TracingContext)

Count DAG nodes by type. `toffoli` counts CX entries with `ncontrols ≥ 1`
(each counts as one CCX — higher-arity was already expanded to ≤ 2-control
via the shared cascade). Returns a NamedTuple.
"""
function node_breakdown(ctx::TracingContext)
    cx = 0; tof = 0; ry = 0; rz = 0; obs = 0; disc = 0
    for n in ctx.dag
        if n isa CXNode
            if Int(n.ncontrols) == 0; cx += 1; else; tof += 1; end
        elseif n isa RyNode
            ry += 1
        elseif n isa RzNode
            rz += 1
        elseif n isa ObserveNode
            obs += 1
        elseif n isa DiscardNode
            disc += 1
        end
    end
    (cx=cx, toffoli=tof, ry=ry, rz=rz, observe=obs, discard=disc,
     total_gates = cx + tof + ry + rz,
     total_nodes = length(ctx.dag))
end

# ── Tracing with preflight ─────────────────────────────────────────────────

function trace_impl(impl::Symbol, a::Int, N::Int, t::Int, L::Int;
                    budget_bytes::Int)
    LOG("────────────────────────────────────────────────────────────────")
    pf = preflight(impl, L, t; budget_bytes=budget_bytes)
    LOG("  impl=$impl  a=$a  N=$N  t=$t  L=$L")
    LOG("  preflight:  est_gates≈$(pf.gates)   est_mem≈$(fmt_bytes(pf.mem))   " *
        "budget=$(fmt_bytes(pf.budget))   ok=$(pf.ok)")

    if !pf.ok
        LOG("  SKIP: projected memory exceeds budget by " *
            "$(round(pf.mem / pf.budget, digits=2))×")
        return (impl=impl, L=L, t=t, N=N, a=a, ok=false, skipped=true,
                wall_ms=0.0, wires=0, est_gates=pf.gates, est_mem=pf.mem,
                reason="preflight")
    end

    wire_before = _wire_counter[]
    wall0 = time_ns()
    ctx = TracingContext()
    # Pre-reserve DAG capacity based on our estimate — eliminates Vector
    # doubling spikes that are the real OOM risk. Cap at budget / NODE_BYTES
    # so a wildly-wrong estimate can't pre-allocate beyond what we can hold.
    sizehint_n = min(pf.gates, fld(budget_bytes, NODE_BYTES))
    sizehint!(ctx.dag, sizehint_n)
    LOG("  [+$(_ms(wall0))ms] TracingContext created " *
        "(wire_counter before=$wire_before, sizehint=$sizehint_n)")

    t_ms, r_out = 0.0, 0
    try
        if impl === :A
            LOG("  [+$(_ms(wall0))ms] impl A: shor_order_A — starting")
            r_out = Sturm.@context ctx begin
                shor_order_A(a, N; t=t)
            end
        elseif impl === :B
            LOG("  [+$(_ms(wall0))ms] impl B: shor_order_B — starting")
            r_out = Sturm.@context ctx begin
                shor_order_B(a, N; t=t)
            end
        elseif impl === :C
            LOG("  [+$(_ms(wall0))ms] impl C: shor_order_C — starting")
            r_out = Sturm.@context ctx begin
                shor_order_C(a, N; t=t, verbose=false)
            end
        elseif impl === :D
            LOG("  [+$(_ms(wall0))ms] impl D: shor_order_D — starting")
            r_out = Sturm.@context ctx begin
                shor_order_D(a, N; t=t, verbose=false)
            end
        else
            error("unknown impl $impl")
        end
        t_ms = _ms(wall0)
    catch e
        t_ms = _ms(wall0)
        LOG("  [+$(t_ms)ms] FAILED with: $(sprint(showerror, e))")
        return (impl=impl, L=L, t=t, N=N, a=a, ok=false, skipped=false,
                wall_ms=t_ms, wires=0, est_gates=pf.gates, est_mem=pf.mem,
                err=sprint(showerror, e))
    end

    wire_after = _wire_counter[]
    wires = Int(wire_after - wire_before)
    nb = node_breakdown(ctx)
    actual_bytes = nb.total_nodes * NODE_BYTES
    LOG("  [+$(t_ms)ms] DONE impl=$impl  wires=$wires  gates=$(nb.total_gates)  " *
        "(cx=$(nb.cx) toffoli=$(nb.toffoli) ry=$(nb.ry) rz=$(nb.rz))  " *
        "obs=$(nb.observe) disc=$(nb.discard)  dag_nodes=$(nb.total_nodes)  " *
        "dag_bytes=$(fmt_bytes(actual_bytes))")
    LOG("  est-vs-actual: gates est $(pf.gates) / actual $(nb.total_gates) = " *
        "$(round(pf.gates / max(nb.total_gates, 1), digits=2))×")

    # Help the GC reclaim this case's DAG before the next iteration.
    empty!(ctx.dag); ctx = nothing; GC.gc()

    return (impl=impl, L=L, t=t, N=N, a=a, ok=true, skipped=false,
            wall_ms=t_ms, wires=wires, nb=nb,
            est_gates=pf.gates, est_mem=pf.mem)
end

# ── Scaling schedule ───────────────────────────────────────────────────────
#
# Every case uses t = 2L for textbook Shor precision. The `impls` field is
# only a hint — preflight will skip any case whose projected memory exceeds
# the budget regardless of what's requested here.
const CASES = [
    (L=4,  t=8,  N=15,     a=7,  impls=[:A, :B, :C, :D]),
    (L=5,  t=10, N=21,     a=2,  impls=[:A, :B, :C, :D]),
    (L=6,  t=12, N=35,     a=2,  impls=[:A, :B, :C, :D]),
    (L=7,  t=14, N=65,     a=2,  impls=[:A, :B, :C, :D]),
    (L=8,  t=16, N=129,    a=2,  impls=[:A, :B, :C, :D]),
    (L=9,  t=18, N=257,    a=2,  impls=[:A, :B, :C, :D]),
    (L=10, t=20, N=527,    a=2,  impls=[:A, :B, :C, :D]),
    (L=11, t=22, N=1025,   a=2,  impls=[:A, :B, :C, :D]),
    (L=12, t=24, N=4095,   a=2,  impls=[:A, :B, :C, :D]),
    (L=13, t=26, N=8193,   a=2,  impls=[:A, :B, :C, :D]),
    (L=14, t=28, N=16383,  a=2,  impls=[:A, :B, :C, :D]),
    (L=16, t=32, N=65535,  a=2,  impls=[:A, :B, :C, :D]),
    (L=18, t=36, N=262143, a=2,  impls=[:A, :B, :C, :D]),
]

# ── Env parsing ────────────────────────────────────────────────────────────

function parse_impl_filter()
    s = get(ENV, "STURM_BENCH_ONLY", "")
    isempty(s) && return Set([:A, :B, :C])
    Set(Symbol(uppercase(strip(x))) for x in split(s, ","))
end

parse_max_L() = parse(Int, get(ENV, "STURM_BENCH_MAX_L", "99"))

function resolve_budget_bytes(free_bytes::Int)
    override = get(ENV, "STURM_BENCH_BUDGET_GB", "")
    if !isempty(override)
        return round(Int, parse(Float64, override) * 1024^3)
    end
    # 30% of free RAM: previous session greenlit 20 GB impl B on a 60 GB box
    # (40% = 24 GB budget) and the kernel OOM-killed anyway. 30% leaves more
    # headroom for Julia's GC overhead and any other processes on the system.
    return round(Int, 0.30 * free_bytes)
end

function resolve_watchdog_bytes()
    # 4 GB floor by default — WSL's OOM-killer tends to fire before `free`
    # hits zero because the kernel keeps reserve pages for itself.
    override = get(ENV, "STURM_BENCH_WATCHDOG_GB", "4.0")
    return round(Int, parse(Float64, override) * 1024^3)
end

# ── Main ───────────────────────────────────────────────────────────────────

function main()
    free_bytes     = Int(Sys.free_memory())
    total_bytes    = Int(Sys.total_memory())
    budget_bytes   = resolve_budget_bytes(free_bytes)
    watchdog_bytes = resolve_watchdog_bytes()
    impl_filter    = parse_impl_filter()
    max_L          = parse_max_L()
    dry_run        = get(ENV, "STURM_BENCH_DRY_RUN", "") in ("1", "true", "yes")

    LOG("═══════════════════════════════════════════════════════════════")
    LOG("SHOR DAG SCALING BENCHMARK   date=$(time())")
    LOG("Using TracingContext — no Orkan simulation, no statevector cost.")
    LOG("Metrics: wall ms, DAG wires, gates (CX/Toffoli/Ry/Rz), node bytes")
    LOG("System:   total RAM = $(fmt_bytes(total_bytes))   free = $(fmt_bytes(free_bytes))")
    LOG("Policy:   per-case budget = $(fmt_bytes(budget_bytes))   " *
        "watchdog floor = $(fmt_bytes(watchdog_bytes))")
    LOG("Filters:  impls=$(sort(collect(impl_filter)))   max_L=$max_L   dry_run=$dry_run")
    LOG("═══════════════════════════════════════════════════════════════")

    # ── Global preflight table ─────────────────────────────────────────────
    LOG("")
    LOG("▶ GLOBAL PREFLIGHT (no execution yet)")
    LOG(rpad("impl", 6) * rpad("L", 5) * rpad("t", 5) *
        rpad("est_gates", 16) * rpad("est_mem", 14) * "verdict")
    LOG("─" ^ 70)
    for c in CASES
        c.L > max_L && continue
        for impl in c.impls
            impl in impl_filter || continue
            pf = preflight(impl, c.L, c.t; budget_bytes=budget_bytes)
            verdict = pf.ok ? "run" : "skip (over budget $(round(pf.mem/pf.budget, digits=2))×)"
            LOG(rpad(string(impl), 6) * rpad(string(c.L), 5) * rpad(string(c.t), 5) *
                rpad(string(pf.gates), 16) *
                rpad(fmt_bytes(pf.mem), 14) *
                verdict)
        end
    end
    LOG("")

    if dry_run
        LOG("DRY RUN — exiting before execution (STURM_BENCH_DRY_RUN=1).")
        return
    end

    # ── Start OOM watchdog ────────────────────────────────────────────────
    LOG("▶ Starting OOM watchdog task (floor=$(fmt_bytes(watchdog_bytes))).")
    start_watchdog(watchdog_bytes)

    # ── Run ────────────────────────────────────────────────────────────────
    results = []
    for c in CASES
        if c.L > max_L
            LOG("")
            LOG("▶ CASE L=$(c.L) t=$(c.t) N=$(c.N): SKIP (L > STURM_BENCH_MAX_L=$max_L)")
            continue
        end
        LOG("")
        LOG("▶ CASE L=$(c.L) t=$(c.t) N=$(c.N) a=$(c.a)")
        for impl in c.impls
            if !(impl in impl_filter)
                LOG("  impl=$impl: skipped (STURM_BENCH_ONLY filter)")
                continue
            end
            res = trace_impl(impl, c.a, c.N, c.t, c.L; budget_bytes=budget_bytes)
            push!(results, res)
        end
    end

    WATCHDOG_ACTIVE[] = false

    # ── Summary table ──────────────────────────────────────────────────────
    LOG("")
    LOG("═══════════════════════════════════════════════════════════════")
    LOG("SUMMARY TABLE")
    LOG("═══════════════════════════════════════════════════════════════")
    LOG(rpad("impl", 6) * rpad("L", 5) * rpad("t", 5) * rpad("wires", 10) *
        rpad("gates", 14) * rpad("toffoli", 12) * rpad("wall_ms", 12) *
        rpad("est_gates", 14) * "status")
    LOG("─" ^ 95)
    for r in results
        wires_s = r.skipped ? "—" : string(r.wires)
        gates_s = (r.ok && !r.skipped) ? string(r.nb.total_gates) : "—"
        tof_s   = (r.ok && !r.skipped) ? string(r.nb.toffoli)     : "—"
        wall_s  = r.skipped ? "—" : string(r.wall_ms)
        status  = r.skipped ? "SKIP" : (r.ok ? "ok" : "FAIL")
        LOG(rpad(string(r.impl), 6) * rpad(string(r.L), 5) * rpad(string(r.t), 5) *
            rpad(wires_s, 10) * rpad(gates_s, 14) * rpad(tof_s, 12) *
            rpad(wall_s, 12) * rpad(string(r.est_gates), 14) * status)
    end
    LOG("")
    LOG("DONE.")
end

main()
