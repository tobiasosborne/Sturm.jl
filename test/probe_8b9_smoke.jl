# Sturm.jl-8b9 smoke test: shor_order_D_semi side-by-side with shor_order_D.

const T0 = time_ns()
_log(s) = (println(stderr, "[", round((time_ns()-T0)/1e6; digits=1), " ms] ", s); flush(stderr))
_log("ENTER")
using Sturm
_log("using Sturm OK")

function hit_rates(impl::Function, a, N, r_expected, t, n_shots)
    n_hit = 0; n_triv = 0; n_other = 0
    for _ in 1:n_shots
        @context EagerContext() begin
            r = impl(a, N, Val(t); verbose=false)
            if r == r_expected
                n_hit += 1
            elseif r == 1
                n_triv += 1
            else
                n_other += 1
            end
        end
    end
    return (hit=n_hit, triv=n_triv, other=n_other, rate=n_hit/n_shots)
end

for (a, N, r_exp, t, n) in [
        (7, 15, 4, 3, 30),
        (2, 15, 4, 3, 30),
        (2, 21, 6, 6, 15),
        (4, 21, 3, 6, 10),
    ]
    _log("=== N=$N a=$a r_expected=$r_exp t=$t  (shots=$n) ===")

    t_d = time_ns()
    stats_D = hit_rates(shor_order_D, a, N, r_exp, t, n)
    wall_D = round((time_ns() - t_d) / 1e9; digits=1)
    _log("  impl D      hit=$(stats_D.hit)/$n ($(round(stats_D.rate*100;digits=1))%) triv=$(stats_D.triv) other=$(stats_D.other)  wall=$(wall_D)s")

    t_s = time_ns()
    stats_S = hit_rates(shor_order_D_semi, a, N, r_exp, t, n)
    wall_S = round((time_ns() - t_s) / 1e9; digits=1)
    _log("  impl D_semi hit=$(stats_S.hit)/$n ($(round(stats_S.rate*100;digits=1))%) triv=$(stats_S.triv) other=$(stats_S.other)  wall=$(wall_S)s")
end

_log("EXIT")
