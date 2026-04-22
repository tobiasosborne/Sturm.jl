# One-shot probe: does shor_order_E(7, 15, Val(3); cpad=1, c_mul=2) complete
# in a reasonable time after the Phase C2 ctrls-kwarg refactor?

using Sturm
using Sturm: shor_order_E

_t0 = time_ns()
_elapsed() = round((time_ns() - _t0) / 1e9, digits=2)
_log(msg) = (println("[$(rpad(_elapsed(), 7))s] $msg"); flush(stdout))

_log("ENTER probe_one_shot_N15")
_log("single shot: shor_order_E(7, 15, Val(3); cpad=1, c_mul=2, verbose=true)")

r = @context EagerContext() begin
    shor_order_E(7, 15, Val(3); cpad=1, c_mul=2, verbose=true)
end

_log("result: r=$r")
_log("EXIT probe_one_shot_N15")
