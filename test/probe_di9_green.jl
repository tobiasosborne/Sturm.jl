# GREEN-check harness for di9 fix. Runs the same probes as
# probe_di9_inverse.jl with per-stage eager-flush logging so we can
# verify the fix end-to-end without waiting for @testset's batch output.

const T0 = time_ns()
_log(s) = (println(stderr, "[", round((time_ns()-T0)/1e6; digits=1), " ms] ", s); flush(stderr))
_log("ENTER")
using Sturm
_log("using Sturm OK")

function leak_rate(build!::Function; n_shots::Int=100)
    n_true = 0
    for _ in 1:n_shots
        @context EagerContext() begin
            ctrl = QBool(1/2)
            build!(ctrl)
            ctrl.θ -= π/2
            if Bool(ctrl); n_true += 1; end
        end
    end
    return n_true / n_shots
end

n_ok = 0; n_fail = 0

_log("=== GREEN check — Stage I add_qft ∘ sub_qft under ctrl ===")
for (L, a, v) in [(1,1,0), (2,2,0), (3,3,1), (4,7,3), (4,2,5), (5,2,3), (5,4,7)]
    r = leak_rate(ctrl -> begin
        y = QInt{L+1}(v)
        superpose!(y)
        when(ctrl) do
            add_qft!(y, a)
            sub_qft!(y, a)
        end
        interfere!(y)
        discard!(y)
    end)
    ok = r < 0.05
    ok ? (global n_ok += 1) : (global n_fail += 1)
    _log("  $(ok ? "✓" : "❌") I   L=$L a=$a v=$v  leak=$(round(r*100;digits=1))%")
end

_log("=== GREEN check — Stage II modadd(a)∘modadd(N-a) ctrls=(c,) ===")
for (L, N, a, b) in [(2,3,2,0), (3,5,2,0), (3,5,3,1), (3,5,4,3),
                     (4,15,7,3), (4,15,2,5), (5,21,2,3), (5,21,4,7)]
    r = leak_rate(ctrl -> begin
        y = QInt{L+1}(b); anc = QBool(0)
        superpose!(y)
        modadd!(y, anc, a, N; ctrls=(ctrl,))
        modadd!(y, anc, mod(N - a, N), N; ctrls=(ctrl,))
        interfere!(y); discard!(y); discard!(anc)
    end)
    ok = r < 0.05
    ok ? (global n_ok += 1) : (global n_fail += 1)
    _log("  $(ok ? "✓" : "❌") II  L=$L N=$N a=$a b=$b  leak=$(round(r*100;digits=1))%")
end

_log("=== GREEN check — Stage III modadd(a)∘modadd(N-a) ctrls=(c,|1⟩) ===")
for (L, N, a, b) in [(3,5,2,1), (4,15,7,3), (4,15,2,5), (5,21,2,3)]
    r = leak_rate(ctrl -> begin
        xj = QBool(1); y = QInt{L+1}(b); anc = QBool(0)
        superpose!(y)
        modadd!(y, anc, a, N; ctrls=(ctrl, xj))
        modadd!(y, anc, mod(N - a, N), N; ctrls=(ctrl, xj))
        interfere!(y); discard!(y); discard!(anc); discard!(xj)
    end)
    ok = r < 0.05
    ok ? (global n_ok += 1) : (global n_fail += 1)
    _log("  $(ok ? "✓" : "❌") III L=$L N=$N a=$a b=$b  leak=$(round(r*100;digits=1))%")
end

_log("=== GREEN check — Stage IV mulmod∘inverse mulmod ===")
for (L, N, a, x0) in [(3,5,2,1), (3,5,2,3), (4,15,7,1), (4,15,7,11), (5,21,2,1)]
    a_inv = invmod(a, N)
    r = leak_rate(ctrl -> begin
        x = QInt{L}(x0)
        mulmod_beauregard!(x, a, N, ctrl)
        mulmod_beauregard!(x, a_inv, N, ctrl)
        discard!(x)
    end; n_shots=40)
    ok = r < 0.05
    ok ? (global n_ok += 1) : (global n_fail += 1)
    _log("  $(ok ? "✓" : "❌") IV  L=$L N=$N a=$a x0=$x0  leak=$(round(r*100;digits=1))%")
end

_log("=== SUMMARY: $n_ok pass / $n_fail fail ===")
_log("EXIT")
