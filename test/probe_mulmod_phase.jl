# Does mulmod_beauregard! leak phase on the ctrl=|1⟩ branch?
#
# Protocol: prepare ctrl=|+⟩ via Ry(π/2)|0⟩ (QBool(1/2)), apply mulmod with
# ctrl, apply Ry(-π/2) (inverse of prep), measure ctrl. If mulmod preserves
# ctrl EXACTLY as |+⟩ (no phase leak), ctrl is back at |0⟩ and measure = false
# every shot. Any shots giving measure=true means phase leak on |1⟩ branch
# of ctrl, probability = sin²(ξ/2) for phase ξ.
#
# Test at L=5 N=21 for various (a, x0). If phase is x-dependent, different
# x0 values should give different measure-true rates.

const T0 = time_ns()
_log(s) = (println(stderr, "[", round((time_ns()-T0)/1e6; digits=1), " ms] ", s); flush(stderr))
_log("ENTER")
using Sturm
_log("using Sturm OK")

for (L, N, a, x0_list) in [
        (4, 15, 7, [0, 1, 2, 7, 13, 14]),
        (4, 15, 2, [0, 1, 3, 5, 8, 14]),
        (5, 21, 2, [0, 1, 4, 8, 11, 16, 20]),
        (5, 21, 4, [0, 1, 4, 11]),
        (5, 21, 16, [0, 1, 2, 11]),
    ]
    _log("=== L=$L N=$N a=$a ===")
    for x0 in x0_list
        n_true = 0; n_shots = 80
        for _ in 1:n_shots
            @context EagerContext() begin
                x = QInt{L}(x0)
                ctrl = QBool(1/2)    # |+⟩ = Ry(π/2)|0⟩
                mulmod_beauregard!(x, a, N, ctrl)
                ctrl.θ -= π/2        # inverse Ry(-π/2)
                m = Bool(ctrl)
                if m; n_true += 1; end
            end
        end
        rate = n_true / n_shots
        flag = rate > 0.1 ? "  ⚠⚠ LEAK" : (rate > 0.05 ? "  ⚠ leak?" : "")
        _log("  x0=$x0  ctrl=true: $n_true/$n_shots = $(round(rate*100;digits=1))%$flag")
    end
end

_log("EXIT")
