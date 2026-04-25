# probe_toffoli_vbz_sweep.jl — Sturm.jl-vbz Phase D4 bench.
#
# Sibling of probe_toffoli_cmul_sweep_mbu.jl (Session 61, Stage 4 of 9ij).
# That probe established the mbu=true ratios; this one adds a mbu_compute=true
# column to exercise the Berry App B Theorem 2 clean-ancilla forward QROM.
#
# Run:
#   LIBORKAN_PATH=.../liborkan.so OMP_NUM_THREADS=16 \
#     julia --project probe_toffoli_vbz_sweep.jl
#
# Outputs: per-L tables comparing (mbu, mbu_compute) ∈ {(F,F), (T,F), (T,T)},
# then a 6oc(d) verdict line for L=8 — the bead's headline target.

using Sturm
using Sturm: mulmod_beauregard!, _shor_mulmod_E_controlled!
using Sturm: CXNode, RyNode, RzNode

_t0 = time_ns()
_elapsed_ms() = round((time_ns() - _t0) / 1e6, digits=1)
_log(msg) = (println("[$(rpad(_elapsed_ms(), 8))ms] $msg"); flush(stdout))

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
    t_proxy = 7*ccx + 14*cccx + 1*rot + 2*crot + 6*ccrot
    return (; cnot, ccx, cccx, rot, crot, ccrot, toff, t_proxy)
end

_log("ENTER probe_toffoli_vbz_sweep")

results = Vector{Any}()
for L in (8, 10, 12)
    N = (1 << L) - 1
    _log("L=$L N=$N")

    # D — naïve mulmod_beauregard! reference (the same baseline the 9ij probe used).
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
    println(rpad("c_mul", 6) * rpad("mbu", 6) * rpad("mbu_compute", 13) *
            rpad("CCX", 8) * rpad("T-proxy", 10) * "E/D")
    println("─" ^ 56)
    best_full = (1e9, -1)
    for c_mul in 2:5,
        (mbu, mbu_compute) in [(false, false), (true, false), (true, true)]
        ch = trace(1) do ctrl
            ctx    = ctrl.ctx
            target = QCoset{L, 1}(ctx, 1, N)
            _shor_mulmod_E_controlled!(target, 2, ctrl;
                                          c_mul=c_mul, mbu=mbu, mbu_compute=mbu_compute)
            ptrace!(target)
            return ctrl
        end
        c     = gate_counts(ch)
        ratio = round(c.t_proxy / cD.t_proxy, digits=3)
        println(rpad(string(c_mul), 6) *
                rpad(string(mbu), 6) *
                rpad(string(mbu_compute), 13) *
                rpad(string(c.ccx), 8) *
                rpad(string(c.t_proxy), 10) *
                "$(ratio)×")
        if mbu && mbu_compute && ratio < best_full[1]
            best_full = (ratio, c_mul)
        end
    end
    push!(results, (L=L, cD=cD, best_full=best_full))
    println()
end

# ── 6oc(d) verdict ───────────────────────────────────────────────────────────
println("═" ^ 56)
println("Best (mbu=true, mbu_compute=true) ratios:")
target = 0.5
for r in results
    verdict = r.best_full[1] <= target ? "✓" : "✗"
    println("  L=$(r.L):  $(r.best_full[1])× at c_mul=$(r.best_full[2])  $verdict")
end
_log("EXIT probe_toffoli_vbz_sweep")
