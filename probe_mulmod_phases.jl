# probe_mulmod_phases.jl — Time each phase of one _shor_mulmod_E_controlled!
# call. Bead Sturm.jl-059 root-cause hunt.

using Sturm
using Sturm: plus_equal_product_mod!, swap!, QCoset, QBool, EagerContext, ptrace!
using Sturm: when

_t0 = time_ns()
_elapsed() = round((time_ns() - _t0) / 1e9, digits=2)
_log(msg) = (println("[$(rpad(_elapsed(), 7))s] $msg"); flush(stdout))

mutable struct Lap
    t::UInt64
end
function lap!(L::Lap)
    now = time_ns()
    dt = round((now - L.t) / 1e6, digits=1)
    L.t = now
    return dt
end

_log("ENTER probe_mulmod_phases")

# Warmup
_log("warmup: N=3 c_mul=1")
@context EagerContext() begin
    target = QCoset{2, 1}(1, 3)
    ctrl = QBool(1)
    Sturm._shor_mulmod_E_controlled!(target, 2, ctrl; c_mul=1)
    ptrace!(target); ptrace!(ctrl)
end
_log("warmup done")

function timed_mulmod(; W::Int, Cpad::Int, N::Int, a::Int, c_mul::Int)
    _log("BENCH: N=$N W=$W Cpad=$Cpad a=$a c_mul=$c_mul")
    @context EagerContext() begin
        target = QCoset{W, Cpad}(1, N)
        ctrl = QBool(1)
        ctx = target.reg.ctx

        a_inv = invmod(a, N)
        minus_a_inv = mod(N - a_inv, N)

        L = Lap(time_ns())

        b = QCoset{W, Cpad}(ctx, 0, N)
        _log("  alloc b: $(lap!(L)) ms (live=$(length(ctx.wire_to_qubit)))")

        plus_equal_product_mod!(b, a, target.reg; window=c_mul, ctrls=(ctrl,))
        _log("  pep1 (k=$a): $(lap!(L)) ms (live=$(length(ctx.wire_to_qubit)))")

        Wtot = W + Cpad
        when(ctrl) do
            for j in 1:Wtot
                swap!(QBool(target.reg.wires[j], ctx, false),
                      QBool(b.reg.wires[j], ctx, false))
            end
            for j in 1:Cpad
                swap!(QBool(target.pad_anc[j], ctx, false),
                      QBool(b.pad_anc[j], ctx, false))
            end
        end
        _log("  cswap target↔b: $(lap!(L)) ms")

        plus_equal_product_mod!(b, minus_a_inv, target.reg;
                                window=c_mul, ctrls=(ctrl,))
        _log("  pep2 (k=$minus_a_inv): $(lap!(L)) ms (live=$(length(ctx.wire_to_qubit)))")

        ptrace!(b)
        _log("  ptrace b: $(lap!(L)) ms")

        ptrace!(target); ptrace!(ctrl)
    end
    _log("BENCH done\n")
end

timed_mulmod(W=3, Cpad=1, N=7, a=3, c_mul=1)
timed_mulmod(W=4, Cpad=1, N=15, a=4, c_mul=1)
timed_mulmod(W=4, Cpad=1, N=15, a=4, c_mul=2)

_log("EXIT probe_mulmod_phases")
