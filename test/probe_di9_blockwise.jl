# Block-wise X-basis leak hunt for di9.
#
# Protocol for every block B:
#     ctrl = QBool(1/2)               # |+⟩ = Ry(π/2)|0⟩
#     when(ctrl) do B() end            # or a doubly-controlled variant
#     ctrl.θ -= π/2                    # inverse prep
#     m = Bool(ctrl)                   # should be FALSE if ctrl preserved
# A leak of ξ radians gives P(m=true) = sin²(ξ/2).
# 50% = π/2, 100% = π, 0% = 0.
#
# Stages (narrowing the leak to the smallest culprit block):
#   A: baseline — empty when(ctrl).                         Expected 0%.
#   B: when(ctrl) add_qft!(y, a).                            y ∈ Fourier of random v.
#   C: when(c1) when(c2=|1⟩) add_qft!(y, a).                 Doubly-controlled.
#   E: modadd!(y, anc, a, N; ctrls=(ctrl,)).                 Singly-controlled modadd.
#   F: modadd!(y, anc, a, N; ctrls=(ctrl, |1⟩)).             Doubly-controlled (mulmod shape).

const T0 = time_ns()
_log(s) = (println(stderr, "[", round((time_ns()-T0)/1e6; digits=1), " ms] ", s); flush(stderr))
_log("ENTER")
using Sturm
using Sturm: add_qft!, sub_qft!, modadd!, mulmod_beauregard!, superpose!, interfere!, discard!
_log("using Sturm OK")

function leak_rate(build_circuit::Function; n_shots::Int=200)
    n_true = 0
    for _ in 1:n_shots
        @context EagerContext() begin
            ctrl = QBool(1/2)
            build_circuit(ctrl)
            ctrl.θ -= π/2
            if Bool(ctrl); n_true += 1; end
        end
    end
    return n_true / n_shots
end

_log("=== STAGE A: empty when(ctrl) ===")
r = leak_rate(ctrl -> (when(ctrl) do; end))
_log("  Stage A  leak = $(round(r*100;digits=1))%")

_log("=== STAGE B: when(ctrl) add_qft!(y, a) — y=Φ(v) ===")
for (L, N, a, v) in [(4,15,7,3), (4,15,2,5), (5,21,2,3), (5,21,4,7), (5,21,16,11)]
    r = leak_rate(ctrl -> begin
        y = QInt{L+1}(v)
        superpose!(y)
        when(ctrl) do
            add_qft!(y, a)
        end
        interfere!(y)
        discard!(y)
    end)
    _log("  Stage B  L=$L N=$N a=$a v=$v  leak = $(round(r*100;digits=1))%")
end

_log("=== STAGE C: when(c1) when(c2=|1⟩) add_qft!(y, a) ===")
for (L, N, a, v) in [(4,15,7,3), (4,15,2,5), (5,21,2,3), (5,21,4,7)]
    r = leak_rate(ctrl -> begin
        c2 = QBool(1)
        y = QInt{L+1}(v)
        superpose!(y)
        when(ctrl) do
            when(c2) do
                add_qft!(y, a)
            end
        end
        interfere!(y)
        discard!(y)
        discard!(c2)
    end)
    _log("  Stage C  L=$L N=$N a=$a v=$v  leak = $(round(r*100;digits=1))%")
end

_log("=== STAGE E: modadd! with ctrls=(ctrl,) ===")
for (L, N, a, b) in [(4,15,7,3), (4,15,2,5), (5,21,2,3), (5,21,4,7)]
    r = leak_rate(ctrl -> begin
        y = QInt{L+1}(b)
        anc = QBool(0)
        superpose!(y)
        modadd!(y, anc, a, N; ctrls=(ctrl,))
        interfere!(y)
        discard!(y)
        discard!(anc)
    end)
    _log("  Stage E  L=$L N=$N a=$a b=$b  leak = $(round(r*100;digits=1))%")
end

_log("=== STAGE F: modadd! with ctrls=(ctrl, xj=|1⟩) ===")
for (L, N, a, b) in [(4,15,7,3), (4,15,2,5), (5,21,2,3), (5,21,4,7)]
    r = leak_rate(ctrl -> begin
        xj = QBool(1)
        y = QInt{L+1}(b)
        anc = QBool(0)
        superpose!(y)
        modadd!(y, anc, a, N; ctrls=(ctrl, xj))
        interfere!(y)
        discard!(y)
        discard!(anc)
        discard!(xj)
    end)
    _log("  Stage F  L=$L N=$N a=$a b=$b  leak = $(round(r*100;digits=1))%")
end

_log("EXIT")
