# Narrow the PE bug. Two questions:
#   (1) Does phase_estimate itself work at t=6 on a known eigenstate?
#   (2) Does shor_order_D(2, 21) work at smaller t (t=3, t=4)?

const T0 = time_ns()
_log(s) = (println(stderr, "[", round((time_ns()-T0)/1e6; digits=1), " ms] ", s); flush(stderr))
_log("ENTER")
using Sturm
_log("using Sturm OK")

# ────────────────────────────────────────────────────────────────────
# Q1: phase_estimate(Z!, |1⟩, Val(t)) — eigenphase 1/2, expect ỹ = 2^(t-1)
# ────────────────────────────────────────────────────────────────────

_log("Q1: phase_estimate(Z!, |1⟩, Val(t)) across t=3..6")
for tt in 3:6
    expected = 1 << (tt - 1)   # 2^(t-1), since Z has phase 1/2
    hits = 0; n = 20
    yts = Int[]
    for _ in 1:n
        @context EagerContext() begin
            eig = QBool(1)   # |1⟩ is eigenstate of Z with eigenvalue -1 = e^{iπ}
            yt = phase_estimate(Z!, eig, Val(tt))
            push!(yts, yt)
            if yt == expected; hits += 1; end
        end
    end
    _log("  t=$tt expected ỹ=$expected: $hits/$n hits  (ỹ distribution: $(sort(yts)))")
end

# ────────────────────────────────────────────────────────────────────
# Q2: phase_estimate on |1⟩_L for mulmod-by-2 at N=21 — s/r = s/6
# Manually compose: U_a!(y) = mulmod_beauregard!(y, 2, 21, QBool-always-1)
# but wrap in phase_estimate. Reuse the machinery.
# ────────────────────────────────────────────────────────────────────

_log("Q2: shor_order_D(2, 21) at different t values")
for tt in 3:6
    hits_r6 = 0; hits_r3 = 0; hits_r2 = 0; hits_r1 = 0; n_other = 0
    n = 15
    for _ in 1:n
        @context EagerContext() begin
            r = shor_order_D(2, 21; t=tt, verbose=false)
            if r == 6; hits_r6 += 1
            elseif r == 3; hits_r3 += 1
            elseif r == 2; hits_r2 += 1
            elseif r == 1; hits_r1 += 1
            else n_other += 1
            end
        end
    end
    total_period = hits_r6 + hits_r3 + hits_r2
    _log("  t=$tt  r=6:$hits_r6  r=3:$hits_r3  r=2:$hits_r2  r=1:$hits_r1  other:$n_other  " *
         "(period-factor rate: $(round(total_period/n*100; digits=1))%)")
end

_log("EXIT")
