# probe_shor_E_N5_all_bases.jl — Hit-rate sweep over all coprime bases of N=5.
#
# N=5 is prime, so every a ∈ {2,3,4} is coprime. Classical orders:
#   a=2 mod 5 → r=4
#   a=3 mod 5 → r=4
#   a=4 mod 5 → r=2
#
# This is the "solid" end-to-end demonstration that shor_order_E works for
# every valid input, at the largest N the device can run in session-length
# wall time. The N=15 bead criterion (b) is blocked by Sturm.jl-059 (perf).

using Sturm
using Sturm: shor_order_E

_t0 = time_ns()
_elapsed() = round((time_ns() - _t0) / 1e9, digits=2)
_log(msg) = (println("[$(rpad(_elapsed(), 7))s] $msg"); flush(stdout))

function probe_base(; N::Int=5, a::Int, t::Int=3,
                     cpad::Int=1, c_mul::Int=1, shots::Int=5)
    true_r = 1; while powermod(a, true_r, N) != 1; true_r += 1; end
    _log("a=$a (true_r=$true_r), $shots shots")
    hits = Dict{Int, Int}()
    for s in 1:shots
        s_t0 = time_ns()
        r = @context EagerContext() begin
            shor_order_E(a, N, Val(t); cpad=cpad, c_mul=c_mul)
        end
        s_dt = round((time_ns() - s_t0) / 1e9, digits=2)
        hits[r] = get(hits, r, 0) + 1
        marker = (r == true_r) ? "✓" : " "
        _log("  shot $s/$shots: r=$r $marker  ($(s_dt)s)")
    end
    hit = get(hits, true_r, 0)
    hit_pct = round(100 * hit / shots, digits=0)
    _log("  → r=$true_r hit rate: $hit/$shots ($(hit_pct)%)")
    return hits, hit_pct
end

_log("ENTER probe_shor_E_N5_all_bases")

# Single shot each base for warmup + smoke
for a in [2, 3, 4]
    _log("smoke a=$a")
    r = @context EagerContext() begin
        shor_order_E(a, 5, Val(3); cpad=1, c_mul=1)
    end
    _log("  smoke r=$r")
end

# 5 shots per coprime base
results = Dict{Int, Any}()
for a in [2, 3, 4]
    hits, pct = probe_base(; N=5, a=a, shots=5)
    results[a] = (hits=hits, hit_pct=pct)
end

_log("SUMMARY — shor_order_E at N=5:")
for a in sort(collect(keys(results)))
    hit_pct = results[a].hit_pct
    _log("  a=$a: hit rate = $(hit_pct)%")
end

_log("EXIT probe_shor_E_N5_all_bases")
