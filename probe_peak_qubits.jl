# probe_peak_qubits.jl — measure peak live qubit count during one
# _shor_mulmod_E_controlled! by polling the context. Bead Sturm.jl-059.

using Sturm
using Sturm: EagerContext, QCoset, QBool, ptrace!

_t0 = time_ns()
_elapsed() = round((time_ns() - _t0) / 1e9, digits=2)
_log(msg) = (println("[$(rpad(_elapsed(), 7))s] $msg"); flush(stdout))

_log("ENTER probe_peak_qubits")

# Run the mulmod in a Task and poll a shared peak counter from another Task.
function probe_peak(W, Cpad, N, a, c_mul)
    _log("setup N=$N W=$W c_mul=$c_mul")
    @context EagerContext() begin
        target = QCoset{W, Cpad}(1, N)
        ctrl = QBool(1)
        ctx = target.reg.ctx

        # warmup once to pay JIT
        Sturm._shor_mulmod_E_controlled!(target, a, ctrl; c_mul=c_mul)
        _log("warmup mulmod done — live=$(length(ctx.wire_to_qubit)) capacity=$(ctx.capacity) n_qubits=$(ctx.n_qubits)")

        # Now spawn a poller and run a second mulmod.
        peak_live = Ref(length(ctx.wire_to_qubit))
        peak_nq   = Ref(ctx.n_qubits)
        peak_cap  = Ref(ctx.capacity)
        stop = Ref(false)
        # NOTE: julia_serial_only — the poller task runs in the same Julia
        # process; this is fine. It samples shared state, no Orkan calls.
        poller = @async begin
            while !stop[]
                live = length(ctx.wire_to_qubit)
                if live > peak_live[]; peak_live[] = live; end
                if ctx.n_qubits > peak_nq[]; peak_nq[] = ctx.n_qubits; end
                if ctx.capacity > peak_cap[]; peak_cap[] = ctx.capacity; end
                # tight loop, no sleep — we want to catch transient peaks
                yield()
            end
        end

        t = time_ns()
        Sturm._shor_mulmod_E_controlled!(target, a, ctrl; c_mul=c_mul)
        dt = round((time_ns() - t) / 1e6, digits=1)
        stop[] = true
        wait(poller)
        _log("  mulmod 2: $(dt) ms — peak_live=$(peak_live[]) peak_nq=$(peak_nq[]) peak_cap=$(peak_cap[])")
        _log("  end-state: live=$(length(ctx.wire_to_qubit)) n_qubits=$(ctx.n_qubits) capacity=$(ctx.capacity) free_slots=$(length(ctx.free_slots))")

        ptrace!(target); ptrace!(ctrl)
    end
end

probe_peak(3, 1, 7, 3, 1)
probe_peak(4, 1, 15, 4, 1)

_log("EXIT probe_peak_qubits")
