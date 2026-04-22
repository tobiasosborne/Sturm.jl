# probe_shor_E_N15.jl — Statistical acceptance probe for Sturm.jl-6oc.
#
# Bead acceptance criterion (a): shor_order_E(7, 15, Val(3)) r=4 hit rate
# ≥ 30% over 50 shots. Criterion (c): shor_factor_E(15) → {3, 5} ≥ 50%
# over 20 shots.
#
# This is a PROBE, not a test. Runtime on this device at cpad=1 is
# ~10-30s per shot × 50 shots = ~20 min. Run overnight or as a bench.
#
# Usage:
#   OMP_NUM_THREADS=16 LIBORKAN_PATH=... julia --project probe_shor_E_N15.jl
# Optional kwargs via ENV or edit main() call below.

using Sturm
using Sturm: shor_order_E, shor_factor_E

_t0 = time_ns()
_ms() = round((time_ns() - _t0) / 1e3, digits=1)
_elapsed() = round((time_ns() - _t0) / 1e9, digits=1)
_log(msg) = (println("[$(rpad(_ms(), 8))s] $msg"); flush(stdout))

function probe_shor_order_E(; N::Int=15, a::Int=7, t::Int=3,
                             cpad::Int=1, c_mul::Int=2, shots::Int=50)
    _log("BEGIN probe_shor_order_E N=$N a=$a t=$t cpad=$cpad c_mul=$c_mul shots=$shots")

    # True period of a mod N — for hit-rate reporting only (classical oracle).
    true_r = 1
    while powermod(a, true_r, N) != 1; true_r += 1; end
    _log("  true order r = $true_r  (classical reference)")

    hits = Dict{Int, Int}()
    for s in 1:shots
        s_t0 = time_ns()
        r = @context EagerContext() begin
            shor_order_E(a, N, Val(t); cpad=cpad, c_mul=c_mul)
        end
        s_dt = round((time_ns() - s_t0) / 1e9, digits=1)
        hits[r] = get(hits, r, 0) + 1
        _log("  shot $s/$shots: r=$r  ($(s_dt)s, total $(_elapsed())s)")
    end

    _log("DONE — distribution:")
    for k in sort(collect(keys(hits)))
        pct = round(100 * hits[k] / shots, digits=1)
        marker = (k == true_r) ? "  ← TRUE ORDER" : ""
        _log("    r=$k:  $(hits[k])/$shots  ($(pct)%)$marker")
    end
    hit = get(hits, true_r, 0)
    hit_pct = round(100 * hit / shots, digits=1)
    _log("HIT RATE r=$true_r: $(hit)/$shots = $(hit_pct)%")
    return (hits=hits, hit_rate=hit_pct, true_r=true_r)
end

function probe_shor_factor_E(; N::Int=15, shots::Int=20,
                              cpad::Int=1, c_mul::Int=2)
    _log("BEGIN probe_shor_factor_E N=$N shots=$shots cpad=$cpad c_mul=$c_mul")
    expected = sort(collect(Set([gcd(N, a) for a in 2:(N-1) if gcd(N, a) > 1])))
    filter!(d -> d > 1 && d < N, expected)
    _log("  classical factors of $N: $expected")

    hits = 0
    for s in 1:shots
        s_t0 = time_ns()
        fs = @context EagerContext() begin
            shor_factor_E(N; cpad=cpad, c_mul=c_mul, max_attempts=4)
        end
        s_dt = round((time_ns() - s_t0) / 1e9, digits=1)
        ok = sort(fs) == expected
        ok && (hits += 1)
        _log("  shot $s/$shots: factors=$fs  $(ok ? "✓" : "✗")  ($(s_dt)s, total $(_elapsed())s)")
    end
    hit_pct = round(100 * hits / shots, digits=1)
    _log("FACTORS HIT RATE: $hits/$shots = $(hit_pct)%")
    return (hits=hits, hit_rate=hit_pct)
end

_log("ENTER probe_shor_E_N15")

# Phase A: does the windowed path even work at (7, 15, t=3) with c_mul=2?
# Single smoke shot first.
_log("smoke: 1 shot at cpad=1 c_mul=2 (verify windowed path runs at N=15)")
r0 = @context EagerContext() begin
    shor_order_E(7, 15, Val(3); cpad=1, c_mul=2, verbose=true)
end
_log("smoke result: r=$r0")

# Phase B: 50-shot statistical on order-finding.
result_order = probe_shor_order_E(; N=15, a=7, t=3, cpad=1, c_mul=2, shots=50)

# Phase C: 20-shot factoring (only runs if phase A was reasonable).
if result_order.hit_rate > 5.0
    _log("proceeding to shor_factor_E probe")
    result_factor = probe_shor_factor_E(; N=15, shots=20, cpad=1, c_mul=2)
else
    _log("skipping factor probe — order hit rate too low")
end

_log("EXIT probe_shor_E_N15")
