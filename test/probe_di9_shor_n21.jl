# di9 acceptance: shor_order_D at N=21 and N=15 post-fix.
#
# Expected per Beauregard / §5.3.1: with t=6, r=6 hit rate around 33%
# (each of the 6 PE peaks decodes to r=6 via continued fractions).
# Session 27 measured 0/20 on pre-fix code.

const T0 = time_ns()
_log(s) = (println(stderr, "[", round((time_ns()-T0)/1e6; digits=1), " ms] ", s); flush(stderr))
_log("ENTER")
using Sturm
_log("using Sturm OK")

function shor_hit_rate(a, N, r_expected, t, n_shots)
    n_hit = 0; n_trivial = 0; n_other = 0
    for _ in 1:n_shots
        @context EagerContext() begin
            r = shor_order_D(a, N, Val(t); verbose=false)
            if r == r_expected
                n_hit += 1
            elseif r == 1
                n_trivial += 1
            else
                n_other += 1
            end
        end
    end
    return (hit=n_hit, trivial=n_trivial, other=n_other)
end

for (a, N, r_expected, t, n_shots) in [
        (7, 15, 4, 3, 30),     # N=15 sanity check — was 50% pre-fix
        (2, 15, 4, 3, 20),
        (2, 21, 6, 6, 20),     # the target case — 0/20 pre-fix
        (4, 21, 3, 6, 10),     # order of 4 mod 21: 4, 16, 1 → r=3
    ]
    _log("=== a=$a N=$N r_expected=$r_expected t=$t ($(n_shots) shots) ===")
    t_case = time_ns()
    stats = shor_hit_rate(a, N, r_expected, t, n_shots)
    wall = round((time_ns() - t_case) / 1e9; digits=1)
    _log("  hits=$(stats.hit)/$n_shots  trivial=$(stats.trivial)  other=$(stats.other)  wall=$(wall)s")
end

_log("EXIT")
