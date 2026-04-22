# probe_toffoli_cmul_sweep.jl — At fixed L=8, sweep c_mul ∈ {1,2,3,4,5} to
# find the optimal window size for bead Sturm.jl-6oc criterion (d).

using Sturm
using Sturm: mulmod_beauregard!, _shor_mulmod_E_controlled!
using Sturm: CXNode, RyNode, RzNode

_t0 = time_ns()
_elapsed() = round((time_ns() - _t0) / 1e3, digits=1)
_log(msg) = (println("[$(rpad(_elapsed(), 8))ms] $msg"); flush(stdout))

function gate_counts(ch)
    cnot = ccx = cccx = rot = crot = ccrot = 0
    for node in ch.dag
        if node isa CXNode
            if node.ncontrols == 0;    cnot += 1
            elseif node.ncontrols == 1; ccx += 1
            else;                      cccx += 1
            end
        elseif node isa RyNode || node isa RzNode
            if node.ncontrols == 0;    rot += 1
            elseif node.ncontrols == 1; crot += 1
            else;                      ccrot += 1
            end
        end
    end
    toff = ccx + cccx
    t_proxy = 7*ccx + 14*cccx + 1*rot + 2*crot + 6*ccrot
    return (; cnot, ccx, cccx, rot, crot, ccrot, toff, t_proxy)
end

function trace_mulmod_E(; W::Int, cpad::Int, c_mul::Int, N::Int, a::Int)
    return trace(1) do ctrl
        ctx = ctrl.ctx
        target = QCoset{W, cpad}(ctx, 1, N)
        _shor_mulmod_E_controlled!(target, a, ctrl; c_mul=c_mul)
        ptrace!(target)
        return ctrl
    end
end

_log("ENTER probe_toffoli_cmul_sweep")

# D baseline at L=8, N=255, a=2
_log("baseline D at L=8 N=255")
ch_D = trace(Val(9)) do reg
    ctx = reg.ctx
    x = QInt{8}(ntuple(i -> reg.wires[i], 8), ctx, false)
    ctrl = QBool(reg.wires[9], ctx, false)
    mulmod_beauregard!(x, 2, 255, ctrl)
    return reg
end
cD = gate_counts(ch_D)
_log("  D: CCX=$(cD.ccx) cRz=$(cD.crot) ccRz=$(cD.ccrot) T-proxy=$(cD.t_proxy)")

# Sweep c_mul
for c_mul in [1, 2, 3, 4, 5]
    _log("E L=8 N=255 cpad=1 c_mul=$c_mul")
    ch_E = trace_mulmod_E(; W=8, cpad=1, c_mul=c_mul, N=255, a=2)
    cE = gate_counts(ch_E)
    ratio_t = round(cE.t_proxy / cD.t_proxy, digits=3)
    ratio_toff = round(cE.toff / max(cD.toff, 1), digits=1)
    _log("  E(c_mul=$c_mul): CCX=$(cE.ccx) cRz=$(cE.crot) ccRz=$(cE.ccrot) T-proxy=$(cE.t_proxy)  →  E/D toff=$(ratio_toff)×  T-proxy=$(ratio_t)×")
end

_log("EXIT probe_toffoli_cmul_sweep")
