# probe_shor_E_N5.jl — Smaller-N statistical probe for bead Sturm.jl-6oc.
#
# N=15 (bead's canonical acceptance target) takes ~21 min per mulmod on
# this device even after the Phase C2 ctrls-kwarg refactor — tracked as
# perf bead Sturm.jl-059. Meanwhile, N=5 is small enough that statistical
# acceptance is reachable in a single session (~10-15s per shot).
#
# Period of 2 mod 5 is r=4. Ideal distribution for t=3: ỹ ∈ {0, 2, 4, 6}
# with uniform probability 1/4 each → shor returns r ∈ {1, 4, 2, 4}, so
# r=4 shows up ~50% of the time in the ideal case. Coset deviation
# perturbs slightly at cpad=1.

using Sturm
using Sturm: shor_order_E, shor_factor_E

_t0 = time_ns()
_elapsed() = round((time_ns() - _t0) / 1e9, digits=2)
_log(msg) = (println("[$(rpad(_elapsed(), 7))s] $msg"); flush(stdout))

function probe_shor_order_E_N5(; a::Int=2, t::Int=3,
                               cpad::Int=1, c_mul::Int=1, shots::Int=20)
    N = 5
    true_r = 1; while powermod(a, true_r, N) != 1; true_r += 1; end
    _log("BEGIN probe N=$N a=$a t=$t cpad=$cpad c_mul=$c_mul shots=$shots true_r=$true_r")

    hits = Dict{Int, Int}()
    for s in 1:shots
        s_t0 = time_ns()
        r = @context EagerContext() begin
            shor_order_E(a, N, Val(t); cpad=cpad, c_mul=c_mul)
        end
        s_dt = round((time_ns() - s_t0) / 1e3, digits=0)
        hits[r] = get(hits, r, 0) + 1
        marker = (r == true_r) ? "✓" : " "
        _log("  shot $s/$shots: r=$r $marker  ($(s_dt)ms, total $(_elapsed())s)")
    end

    _log("DONE — distribution:")
    for k in sort(collect(keys(hits)))
        pct = round(100 * hits[k] / shots, digits=1)
        tag = (k == true_r) ? "  ← TRUE ORDER" : ""
        _log("    r=$k:  $(hits[k])/$shots  ($(pct)%)$tag")
    end
    hit = get(hits, true_r, 0)
    hit_pct = round(100 * hit / shots, digits=1)
    _log("HIT RATE r=$true_r: $(hit)/$shots = $(hit_pct)%")
    return (hits=hits, hit_rate=hit_pct, true_r=true_r)
end

_log("ENTER probe_shor_E_N5")

# Single smoke shot first — verify c_mul=1 works end-to-end at N=5.
_log("smoke: 1 shot at cpad=1 c_mul=1")
r0 = @context EagerContext() begin
    shor_order_E(2, 5, Val(3); cpad=1, c_mul=1, verbose=true)
end
_log("smoke result: r=$r0")

# 20-shot statistical on shor_order_E(2, 5; t=3).
result = probe_shor_order_E_N5(; a=2, t=3, cpad=1, c_mul=1, shots=20)

_log("EXIT probe_shor_E_N5 — hit_rate=$(result.hit_rate)%")
