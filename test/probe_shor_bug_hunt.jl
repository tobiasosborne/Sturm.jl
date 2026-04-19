# Bug hunt: shor_order_D fails at N=21 with 0/20 r=6 hits.
# Narrow: is the bug (A) mulmod_beauregard! at L=5, (B) PE cascade at t>3,
# or (C) something specific to N=21?
#
# Three targeted experiments:
#   EXP-A: mulmod_beauregard! direct correctness at L=5, N=21, all a∈{2,4,5,8,10,11,13,16,17,19,20}
#          and all x_0∈{0..N-1}, ctrl=|1⟩. NO PE cascade — just the arithmetic.
#          Expected: all Int(x) == (a * x_0) mod N.
#   EXP-B: shor_order_D(7, 15; t=6). Same N=15 that worked at t=3, bigger
#          counter. a_j = [7,4,1,1,1,1] — only 2 mulmods fire. If this
#          works, counter width t isn't the issue.
#   EXP-C: shor_order_D(7, 15; t=4). Same N=15, t=4. a_j = [7,4,1,1].

const T0 = time_ns()
_ms() = round((time_ns() - T0) / 1e6; digits=1)
function _log(stage::AbstractString)
    free_gib = round(Sys.free_memory() / 1024^3; digits=2)
    println(stderr, "[", rpad(_ms(), 10), " ms] [free=", free_gib, " GiB] ", stage)
    flush(stderr)
end

_log("ENTER probe_shor_bug_hunt.jl")
using Sturm
using Test
_log("using Sturm OK")

# ─────────────────────────────────────────────────────────────────────────
# EXP-A: mulmod_beauregard! correctness at L=5 N=21
# ─────────────────────────────────────────────────────────────────────────

_log("EXP-A: mulmod_beauregard! direct correctness, L=5, N=21")
let
    t_exp = time_ns()
    n_cases = Ref(0); n_fail = Ref(0)
    for a in 1:20
        gcd(a, 21) == 1 || continue
        for x0 in 0:20
            @context EagerContext() begin
                x = QInt{5}(x0)
                ctrl = QBool(1)
                mulmod_beauregard!(x, a, 21, ctrl)
                got = Int(x)
                expected = (a * x0) % 21
                n_cases[] += 1
                if got != expected
                    n_fail[] += 1
                    _log("  FAIL a=$a x0=$x0  got=$got  expect=$expected")
                end
            end
        end
    end
    exp_ms = round((time_ns() - t_exp) / 1e6; digits=1)
    _log("EXP-A done: $(n_cases[]) cases, $(n_fail[]) fail, $(exp_ms) ms " *
         "($(round(exp_ms / max(n_cases[], 1); digits=1)) ms/case)")
    @test n_fail[] == 0
end

# ─────────────────────────────────────────────────────────────────────────
# EXP-B: shor_order_D at N=15, bigger counter
# ─────────────────────────────────────────────────────────────────────────

_log("EXP-B: shor_order_D(7, 15; t=4) — 20 shots, expect r=4 at reasonable rate")
let
    t_stage = time_ns()
    n_shots = 20
    hits = Ref(0); others = Ref{Vector{Int}}(Int[])
    for i in 1:n_shots
        @context EagerContext() begin
            r = shor_order_D(7, 15; t=4, verbose=false)
            if r == 4
                hits[] += 1
            else
                push!(others[], r)
            end
        end
        i <= 3 && _log("  shot $i (r hit $(hits[])/$i)")
    end
    stage_ms = round((time_ns() - t_stage) / 1e6; digits=1)
    rate = hits[] / n_shots
    _log("EXP-B done: r=4 hit $(hits[])/$n_shots = $(round(rate * 100; digits=1))%, others=$(others[])  " *
         "total $(stage_ms) ms  ($(round(stage_ms / n_shots; digits=1)) ms/shot)")
    @test rate >= 0.2    # loose — t=4 adds noise but should still work
end

# ─────────────────────────────────────────────────────────────────────────
# EXP-C: shor_order_D at N=15, t=6
# ─────────────────────────────────────────────────────────────────────────

_log("EXP-C: shor_order_D(7, 15; t=6) — 10 shots")
let
    t_stage = time_ns()
    n_shots = 10
    hits = Ref(0); others = Ref{Vector{Int}}(Int[])
    for i in 1:n_shots
        @context EagerContext() begin
            r = shor_order_D(7, 15; t=6, verbose=false)
            if r == 4
                hits[] += 1
            else
                push!(others[], r)
            end
        end
        _log("  shot $i (r hit $(hits[])/$i)")
    end
    stage_ms = round((time_ns() - t_stage) / 1e6; digits=1)
    rate = hits[] / n_shots
    _log("EXP-C done: r=4 hit $(hits[])/$n_shots = $(round(rate * 100; digits=1))%, others=$(others[])  " *
         "total $(stage_ms) ms")
    @test rate >= 0.2
end

_log("EXIT probe_shor_bug_hunt.jl")
