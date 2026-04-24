# probe_toffoli_cmul_sweep_mbu.jl — Stage 4 of Sturm.jl-9ij.
#
# Session 50b swept c_mul ∈ {1..5} at L=8, mbu=false only, finding the E/D
# T-proxy ratio bottoming at 0.61× (c_mul=3). Bead 6oc criterion (d) asks
# for ≤0.5× at L=8. This probe adds the mbu=true column and extends to
# L ∈ {8, 10, 12} so the MBU-vs-L asymptotic behaviour is visible alongside
# the bead's headline L=8 number.
#
# Run:
#   LIBORKAN_PATH=.../liborkan.so julia --project probe_toffoli_cmul_sweep_mbu.jl
#
# Outputs: one table per L, then a two-line summary of the best mbu=true
# ratio vs the 0.5× target.

using Sturm
using Sturm: mulmod_beauregard!, _shor_mulmod_E_controlled!
using Sturm: CXNode, RyNode, RzNode

_t0 = time_ns()
_elapsed() = round((time_ns() - _t0) / 1e3, digits=1)
_log(msg) = (println("[$(rpad(_elapsed(), 8))ms] $msg"); flush(stdout))

function gate_counts(ch)
    cnot = ccx = cccx = rot = crot = ccrot = 0
    for n in ch.dag
        if n isa CXNode
            n.ncontrols == 0 ? (cnot += 1) :
            n.ncontrols == 1 ? (ccx  += 1) :
                               (cccx += 1)
        elseif n isa RyNode || n isa RzNode
            n.ncontrols == 0 ? (rot   += 1) :
            n.ncontrols == 1 ? (crot  += 1) :
                               (ccrot += 1)
        end
    end
    toff    = ccx + cccx
    # Session 50b T-proxy weights.
    t_proxy = 7*ccx + 14*cccx + 1*rot + 2*crot + 6*ccrot
    return (; cnot, ccx, cccx, rot, crot, ccrot, toff, t_proxy)
end

_log("ENTER probe_toffoli_cmul_sweep_mbu")

results = Vector{Any}()
for L in (8, 10, 12)
    N = (1 << L) - 1
    _log("L=$L N=$N")

    ch_D = trace(Val(L + 1)) do reg
        ctx  = reg.ctx
        x    = QInt{L}(ntuple(i -> reg.wires[i], L), ctx, false)
        ctrl = QBool(reg.wires[L + 1], ctx, false)
        mulmod_beauregard!(x, 2, N, ctrl)
        return reg
    end
    cD = gate_counts(ch_D)
    _log("  D baseline: T-proxy=$(cD.t_proxy) CCX=$(cD.ccx)")

    println()
    println(rpad("c_mul", 6) * rpad("mbu", 7) * rpad("CCX", 8) *
            rpad("T-proxy", 10) * "E/D")
    println("─" ^ 44)
    best_mbu = (1e9, -1)
    for c_mul in 2:5, mbu in (false, true)
        ch = trace(1) do ctrl
            ctx    = ctrl.ctx
            target = QCoset{L, 1}(ctx, 1, N)
            _shor_mulmod_E_controlled!(target, 2, ctrl; c_mul=c_mul, mbu=mbu)
            ptrace!(target)
            return ctrl
        end
        c     = gate_counts(ch)
        ratio = round(c.t_proxy / cD.t_proxy, digits=3)
        println(rpad(string(c_mul), 6) *
                rpad(string(mbu), 7) *
                rpad(string(c.ccx), 8) *
                rpad(string(c.t_proxy), 10) *
                "$(ratio)×")
        if mbu && ratio < best_mbu[1]
            best_mbu = (ratio, c_mul)
        end
    end
    push!(results, (L=L, cD=cD, best_mbu=best_mbu))
    println()
end

# ── Summary / 6oc criterion (d) verdict ─────────────────────────────────────
println("═" ^ 44)
println("MBU-best ratios across L:")
target = 0.5
for r in results
    verdict = r.best_mbu[1] <= target ? "✓" : "✗"
    println("  L=$(r.L):  $(r.best_mbu[1])× at c_mul=$(r.best_mbu[2])  $verdict")
end
_log("EXIT probe_toffoli_cmul_sweep_mbu")
