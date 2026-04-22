# probe_toffoli_DE.jl — Bead Sturm.jl-6oc acceptance criterion (d).
#
# Trace the mulmod inner loop of impls D (Beauregard) and E (GE21 windowed)
# across L ∈ {4, 5, 6, 7, 8} and compare Toffoli counts. The intended metric:
# E ≤ 0.5× D at L=8.
#
# "Toffoli count" here includes:
#   * CXNode with ncontrols=1 (CCX — classic Toffoli)
#   * CXNode with ncontrols=2 (CCCX — decomposes to several Toffolis,
#     conservatively counted as 1 "Toffoli-equivalent" DAG node)
#   * Ry/Rz with ncontrols=1 (controlled rotation, ~2 Toffoli in FT encoding)
#   * Ry/Rz with ncontrols=2 (doubly-controlled rotation, more expensive)
#
# We report each count separately + a weighted T-count proxy.
#
# This runs on TracingContext — NO simulation, NO state vector. Fast across
# all L sizes.

using Sturm
using Sturm: mulmod_beauregard!, _shor_mulmod_E_controlled!
using Sturm: CXNode, RyNode, RzNode

_t0 = time_ns()
_elapsed() = round((time_ns() - _t0) / 1e3, digits=1)
_log(msg) = (println("[$(rpad(_elapsed(), 8))ms] $msg"); flush(stdout))

"""
    gate_counts(ch::Channel) -> NamedTuple

Count gates in the channel's DAG by (op type, control depth).
Returns:
  (
    cnot,      # CXNode nc=0
    ccx,       # CXNode nc=1 — Toffolis
    cccx,      # CXNode nc=2 — CCCX (deeper would go through cascade)
    rot,       # Ry/Rz nc=0
    crot,      # Ry/Rz nc=1
    ccrot,     # Ry/Rz nc=2
    toffoli_total,    # ccx + cccx (raw CCX-family node count)
    t_count_proxy,    # weighted: ccx*1 + cccx*5 + crot*2 + ccrot*6
    total_nodes,
  )
"""
function gate_counts(ch)
    cnot = ccx = cccx = rot = crot = ccrot = 0
    total = 0
    for node in ch.dag
        total += 1
        if node isa CXNode
            if node.ncontrols == 0
                cnot += 1
            elseif node.ncontrols == 1
                ccx += 1
            else
                cccx += 1
            end
        elseif node isa RyNode || node isa RzNode
            if node.ncontrols == 0
                rot += 1
            elseif node.ncontrols == 1
                crot += 1
            else
                ccrot += 1
            end
        end
    end
    toffoli_total = ccx + cccx
    # FT T-count proxy: each CCX ≈ 7 T-gates, CCCX decomposes to ~2 CCX = 14 T,
    # controlled-Rz ≈ 2 T, CC-Rz ≈ 6 T. Plain Rz ≈ 1 T. Plain CNOT = 0 T.
    t_count_proxy = 7*ccx + 14*cccx + 1*rot + 2*crot + 6*ccrot
    return (; cnot, ccx, cccx, rot, crot, ccrot, toffoli_total, t_count_proxy, total_nodes=total)
end

function trace_mulmod_D(; L::Int, N::Int, a::Int)
    ctx_in_trace(ch) = ch  # sentinel
    return trace(Val(L + 1)) do reg
        # reg is QInt{L+1}: wires[1..L] = x, wires[L+1] = ctrl
        ctx = reg.ctx
        x_wires = ntuple(i -> reg.wires[i], L)
        x = QInt{L}(x_wires, ctx, false)
        ctrl = QBool(reg.wires[L + 1], ctx, false)
        mulmod_beauregard!(x, a, N, ctrl)
        return reg
    end
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

_log("ENTER probe_toffoli_DE")

# Sweep: compare D and E at matching L, with suitable (W, cpad, c_mul) for E.
# For each N, pick:
#   L = W = ceil(log2(N+1))
#   cpad = 1 (minimum coset)
#   c_mul = 2 for L ≥ 4 (windowing kicks in)
# N = 2^L - 1 for each L (gives the "worst case" gate count for that L).

# Pick `a` coprime to each N.
# N=15: gcd(7,15)=1 ✓
# N=31: 31 prime, any a
# N=63: 63 = 9·7, pick a=2 (gcd=1)
# N=127: 127 prime
# N=255: 255 = 3·5·17, pick a=2 (gcd=1)
cases = [
    (L=4,  N=15,    a=7),
    (L=5,  N=31,    a=7),
    (L=6,  N=63,    a=2),
    (L=7,  N=127,   a=2),
    (L=8,  N=255,   a=2),
]

println()
println("L | N   | D (CCX, CCCX, cRot, ccRot)  | E (c_mul=2)                | E/D Toff | E/D T-proxy")
println("-" ^ 105)
for case in cases
    L = case.L; N = case.N; a = case.a
    _log("  tracing D L=$L N=$N")
    ch_D = trace_mulmod_D(; L=L, N=N, a=a)
    counts_D = gate_counts(ch_D)
    _log("    D: CCX=$(counts_D.ccx) CCCX=$(counts_D.cccx) cRz=$(counts_D.crot) ccRz=$(counts_D.ccrot) → toff=$(counts_D.toffoli_total) T-proxy=$(counts_D.t_count_proxy)")

    _log("  tracing E L=$L N=$N (W=$L cpad=1 c_mul=2)")
    ch_E = trace_mulmod_E(; W=L, cpad=1, c_mul=2, N=N, a=a)
    counts_E = gate_counts(ch_E)
    _log("    E: CCX=$(counts_E.ccx) CCCX=$(counts_E.cccx) cRz=$(counts_E.crot) ccRz=$(counts_E.ccrot) → toff=$(counts_E.toffoli_total) T-proxy=$(counts_E.t_count_proxy)")

    ratio_toff = round(counts_E.toffoli_total / max(counts_D.toffoli_total, 1), digits=2)
    ratio_t = round(counts_E.t_count_proxy / max(counts_D.t_count_proxy, 1), digits=2)
    _log("    ratio (E/D): toff=$(ratio_toff) T-proxy=$(ratio_t)")
end

_log("EXIT probe_toffoli_DE")
