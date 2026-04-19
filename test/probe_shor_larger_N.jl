# shor_order_D / shor_factor_D verification at N > 15.
#
# 6kx bead's acceptance mentioned N=15, N=21, N=35. Session 26 only
# exercised N=15; this probe fills the gap. Verbose per-shot logging
# per feedback_verbose_eager_flush.md; conservative t (counter width)
# to keep wall time per shot inside a few minutes.
#
# Expected orders (coprime base a=2 against each N):
#     N=15, r(2) = 4      (already covered by probe_6kx_minimal.jl)
#     N=21, r(2) = 6
#     N=35, r(2) = 12
#
# Resource budget (HWM = t + L + (L+1) + 1 during mulmod):
#     N=21 L=5 t=6:  18 qubits,  4 MiB statevector
#     N=35 L=6 t=6:  20 qubits, 16 MiB statevector
#     N=35 L=6 t=7:  21 qubits, 32 MiB statevector
#
# Run directly:
#   LIBORKAN_PATH=… julia --project test/probe_shor_larger_N.jl

const T0 = time_ns()
_ms() = round((time_ns() - T0) / 1e6; digits=1)
function _log(stage::AbstractString)
    free_gib = round(Sys.free_memory() / 1024^3; digits=2)
    println(stderr, "[", rpad(_ms(), 10), " ms] [free=", free_gib, " GiB] ", stage)
    flush(stderr)
end

_log("ENTER probe_shor_larger_N.jl")

_log("using Sturm (precompile + Orkan init)…")
using Sturm
using Test
_log("using Sturm OK")

# ──────────────────────────────────────────────────────────────────────────
# S1: N=21 a=2 t=6  — expect r=6
# ──────────────────────────────────────────────────────────────────────────

_log("STAGE 1: shor_order_D(2, 21; t=6) — expect r=6   20 shots")
let
    t_stage = time_ns()
    n_shots = 20
    hit_r6 = Ref(0); n_r3 = Ref(0); n_r2 = Ref(0); n_r1 = Ref(0); n_other = Ref(0)
    for i in 1:n_shots
        t_shot = time_ns()
        @context EagerContext() begin
            r = shor_order_D(2, 21; t=6, verbose=false)
            if r == 6
                hit_r6[] += 1
            elseif r == 3
                n_r3[] += 1   # factor of 6, acceptable partial
            elseif r == 2
                n_r2[] += 1
            elseif r == 1
                n_r1[] += 1   # trivial ỹ=0
            else
                n_other[] += 1
            end
        end
        shot_ms = round((time_ns() - t_shot) / 1e6; digits=1)
        if i <= 3 || i % 5 == 0
            _log("  shot $i/$n_shots  ($(shot_ms) ms)  r=6:$(hit_r6[])  r=3:$(n_r3[])  " *
                 "r=2:$(n_r2[])  r=1:$(n_r1[])  other:$(n_other[])")
        end
    end
    stage_ms = round((time_ns() - t_stage) / 1e6; digits=1)
    rate = hit_r6[] / n_shots
    _log("STAGE 1 done: r=6 hit $(hit_r6[])/$n_shots = $(round(rate * 100; digits=1))%  " *
         "total $(stage_ms) ms  ($(round(stage_ms / n_shots; digits=1)) ms/shot)")
    @test rate >= 0.15                         # r=6 is less resolved at t=6 than r=4 at t=3
    @test n_other[] == 0
end

# ──────────────────────────────────────────────────────────────────────────
# S2: N=35 a=2 t=6  — expect r=12
# ──────────────────────────────────────────────────────────────────────────

_log("STAGE 2: shor_order_D(2, 35; t=6) — expect r=12   10 shots")
let
    t_stage = time_ns()
    n_shots = 10
    hit_r12 = Ref(0); hit_r6 = Ref(0); hit_r4 = Ref(0); hit_r3 = Ref(0)
    hit_r2 = Ref(0); hit_r1 = Ref(0); n_other = Ref(0)
    for i in 1:n_shots
        t_shot = time_ns()
        @context EagerContext() begin
            r = shor_order_D(2, 35; t=6, verbose=false)
            if r == 12
                hit_r12[] += 1
            elseif r == 6;  hit_r6[]  += 1
            elseif r == 4;  hit_r4[]  += 1
            elseif r == 3;  hit_r3[]  += 1
            elseif r == 2;  hit_r2[]  += 1
            elseif r == 1;  hit_r1[]  += 1
            else            ; n_other[] += 1
            end
        end
        shot_ms = round((time_ns() - t_shot) / 1e6; digits=1)
        _log("  shot $i/$n_shots  ($(shot_ms) ms)  r=12:$(hit_r12[]) r=6:$(hit_r6[]) " *
             "r=4:$(hit_r4[]) r=3:$(hit_r3[]) r=2:$(hit_r2[]) r=1:$(hit_r1[]) other:$(n_other[])")
    end
    stage_ms = round((time_ns() - t_stage) / 1e6; digits=1)
    # r=12 at t=6 has peaks every 64/12 ≈ 5.33 — quite granular. Hit rate
    # on r=12 directly is low, but continued-fractions often falls on a
    # factor (r=6, r=4, r=3, r=2). All valid period factors.
    period_factors = hit_r12[] + hit_r6[] + hit_r4[] + hit_r3[] + hit_r2[]
    _log("STAGE 2 done: r=12 hits $(hit_r12[])/$n_shots  period-factor hits " *
         "$(period_factors)/$n_shots  total $(stage_ms) ms " *
         "($(round(stage_ms / n_shots; digits=1)) ms/shot)")
    @test n_other[] == 0
    @test period_factors >= n_shots ÷ 2        # ≥ 50% land on a factor of 12
end

# ──────────────────────────────────────────────────────────────────────────
# S3: shor_factor_D(21) smoke — expect {3, 7}
# ──────────────────────────────────────────────────────────────────────────

_log("STAGE 3: shor_factor_D(21) — 5 attempts, expect {3, 7}")
let
    t_stage = time_ns()
    n_attempts = 5
    hits = Ref(0)
    for i in 1:n_attempts
        t_att = time_ns()
        @context EagerContext() begin
            fs = shor_factor_D(21)
            if Set(fs) == Set([3, 7])
                hits[] += 1
            end
        end
        att_ms = round((time_ns() - t_att) / 1e6; digits=1)
        _log("  attempt $i: hits $(hits[])/$i  ($(att_ms) ms)")
    end
    stage_ms = round((time_ns() - t_stage) / 1e6; digits=1)
    _log("STAGE 3 done: $(hits[])/$n_attempts successes  total $(stage_ms) ms")
    @test hits[] >= 1                          # at least 20% recover {3, 7}
end

# ──────────────────────────────────────────────────────────────────────────
# S4: shor_factor_D(35) smoke — expect {5, 7}
# ──────────────────────────────────────────────────────────────────────────

_log("STAGE 4: shor_factor_D(35) — 3 attempts, expect {5, 7}")
let
    t_stage = time_ns()
    n_attempts = 3
    hits = Ref(0)
    for i in 1:n_attempts
        t_att = time_ns()
        @context EagerContext() begin
            fs = shor_factor_D(35)
            if Set(fs) == Set([5, 7])
                hits[] += 1
            end
        end
        att_ms = round((time_ns() - t_att) / 1e6; digits=1)
        _log("  attempt $i: hits $(hits[])/$i  ($(att_ms) ms)")
    end
    stage_ms = round((time_ns() - t_stage) / 1e6; digits=1)
    _log("STAGE 4 done: $(hits[])/$n_attempts successes  total $(stage_ms) ms")
    @test hits[] >= 1                          # at least 1 of 3 recovers {5, 7}
end

_log("EXIT probe_shor_larger_N.jl")
