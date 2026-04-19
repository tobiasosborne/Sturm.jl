# Sturm.jl-6kx minimal probe — smallest viable test for shor_order_D.
#
# Order-finding with Beauregard arithmetic mulmod. Compares the per-shot
# wall time and HWM qubit count to the published impl C numbers
# (302 s/shot, 26 qubits HWM at L=4 / t=3) — impl D should be dramatically
# cheaper since it uses Beauregard's 2n+3-qubit circuit instead of a
# packed (L+1)-bit QROM index.
#
# Stages:
#   S1. Single verbose shot, N=15 a=7 t=3. Asserts r ∈ {1, 2, 4} (1 on
#       trivial ỹ=0, 2 on ỹ=4, 4 on ỹ ∈ {2, 6}). Captures wall time, HWM,
#       peak free-RAM.
#   S2. 30 shots, N=15 a=7 t=3. Asserts hit rate on r=4 ≥ 0.3 (matches
#       impl A's test tolerance).  Prints per-shot (ỹ, r) so a stall or
#       regression is visible.
#   S3. 20 shots, N=15 a=2 t=3.  Asserts hit rate on r=4 ≥ 0.3.
#   S4. shor_factor_D(15)  — verify classical reduction reaches {3, 5}.
#
# Run directly:
#   LIBORKAN_PATH=… julia --project test/probe_6kx_minimal.jl
# NOT via Pkg.test — per sturm-jl-test-suite-slow memory.

const T0 = time_ns()
_ms() = round((time_ns() - T0) / 1e6; digits=1)
function _log(stage::AbstractString)
    free_gib = round(Sys.free_memory() / 1024^3; digits=2)
    println(stderr, "[", rpad(_ms(), 10), " ms] [free=", free_gib, " GiB] ", stage)
    flush(stderr)
end

_log("ENTER probe_6kx_minimal.jl")

_log("using Sturm (precompile + Orkan init)…")
using Sturm
using Test
_log("using Sturm OK")

# ──────────────────────────────────────────────────────────────────────────
# S1: single verbose shot — establish baseline wall / HWM
# ──────────────────────────────────────────────────────────────────────────

_log("STAGE 1: single verbose shot  shor_order_D(7, 15; t=3)  ─ baseline metrics")
let
    t_stage = time_ns()
    @context EagerContext() begin
        ctx = current_context()
        r = shor_order_D(7, 15; t=3, verbose=true)
        stage_ms = round((time_ns() - t_stage) / 1e6; digits=1)
        _log("STAGE 1 done: r=$r  wall=$(stage_ms) ms  hwm=$(ctx.n_qubits)  cap=$(ctx.capacity)")
        @test r in (1, 2, 4)       # 1=ỹ=0 trivial; 2=ỹ=4; 4=ỹ∈{2,6}
    end
end

# ──────────────────────────────────────────────────────────────────────────
# S2: hit-rate at r=4, a=7, N=15, t=3, 30 shots
# ──────────────────────────────────────────────────────────────────────────

_log("STAGE 2: hit-rate  shor_order_D(7, 15; t=3) → r=4  over 30 shots")
let
    t_stage = time_ns()
    n_shots = 30
    hits = Ref(0); n_r2 = Ref(0); n_r1 = Ref(0); n_other = Ref(0)
    for i in 1:n_shots
        @context EagerContext() begin
            r = shor_order_D(7, 15; t=3, verbose=false)
            if r == 4
                hits[] += 1
            elseif r == 2
                n_r2[] += 1
            elseif r == 1
                n_r1[] += 1
            else
                n_other[] += 1
            end
        end
        if i % 5 == 0
            _log("  shot $i/$n_shots  r=4:$(hits[])  r=2:$(n_r2[])  r=1:$(n_r1[])  " *
                 "other:$(n_other[])")
        end
    end
    stage_ms = round((time_ns() - t_stage) / 1e6; digits=1)
    avg_ms = round(stage_ms / n_shots; digits=1)
    rate = hits[] / n_shots
    _log("STAGE 2 done: r=4 hit $(hits[])/$n_shots = $(round(rate * 100; digits=1))%  " *
         "total $(stage_ms) ms  ($(avg_ms) ms/shot)")
    @test rate >= 0.3
    @test n_other[] == 0           # no spurious r values
end

# ──────────────────────────────────────────────────────────────────────────
# S3: a=2 variant (also r=4 for N=15)
# ──────────────────────────────────────────────────────────────────────────

_log("STAGE 3: hit-rate  shor_order_D(2, 15; t=3) → r=4  over 20 shots")
let
    t_stage = time_ns()
    n_shots = 20
    hits = Ref(0); n_r2 = Ref(0); n_r1 = Ref(0); n_other = Ref(0)
    for i in 1:n_shots
        @context EagerContext() begin
            r = shor_order_D(2, 15; t=3, verbose=false)
            if r == 4
                hits[] += 1
            elseif r == 2
                n_r2[] += 1
            elseif r == 1
                n_r1[] += 1
            else
                n_other[] += 1
            end
        end
        if i % 5 == 0
            _log("  shot $i/$n_shots  r=4:$(hits[])  r=2:$(n_r2[])  r=1:$(n_r1[])  " *
                 "other:$(n_other[])")
        end
    end
    stage_ms = round((time_ns() - t_stage) / 1e6; digits=1)
    rate = hits[] / n_shots
    _log("STAGE 3 done: r=4 hit $(hits[])/$n_shots = $(round(rate * 100; digits=1))%  " *
         "total $(stage_ms) ms  ($(round(stage_ms / n_shots; digits=1)) ms/shot)")
    @test rate >= 0.3
    @test n_other[] == 0
end

# ──────────────────────────────────────────────────────────────────────────
# S4: shor_factor_D(15) — classical reduction smoke test
# ──────────────────────────────────────────────────────────────────────────

_log("STAGE 4: shor_factor_D(15) — 10 attempts, expect {3, 5}")
let
    t_stage = time_ns()
    n_attempts = 10
    hits = Ref(0)
    for i in 1:n_attempts
        @context EagerContext() begin
            fs = shor_factor_D(15)
            if Set(fs) == Set([3, 5])
                hits[] += 1
            end
        end
        _log("  attempt $i: hits so far $(hits[])/$i")
    end
    stage_ms = round((time_ns() - t_stage) / 1e6; digits=1)
    _log("STAGE 4 done: $(hits[])/$n_attempts successes  total $(stage_ms) ms")
    @test hits[] >= 3              # loose: at least 30% of runs recover {3,5}
end

_log("EXIT probe_6kx_minimal.jl")
