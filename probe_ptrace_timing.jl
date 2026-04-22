# probe_ptrace_timing.jl — isolate measure!/ptrace! cost at 20 qubits.

using Sturm

_t0 = time_ns()
_elapsed() = round((time_ns() - _t0) / 1e3, digits=1)
_log(msg) = (println("[$(rpad(_elapsed(), 8))µs] $msg"); flush(stdout))

function bench_ptrace(n_qubits::Int; n_iters::Int=50)
    @context EagerContext() begin
        # Allocate n_qubits persistent qubits, in some non-trivial state
        persistent = [QBool(0) for _ in 1:(n_qubits - 1)]
        for p in persistent; H!(p); end  # put each in |+⟩ so state is uniform

        # Warm up with one iteration
        victim = QBool(0)
        H!(victim)
        ptrace!(victim)

        # Now time n_iters: allocate a qubit, put it in some state, ptrace.
        t0 = time_ns()
        for _ in 1:n_iters
            v = QBool(0)
            H!(v)
            ptrace!(v)
        end
        dt = round((time_ns() - t0) / 1e6, digits=2)
        per_call = round(dt / n_iters, digits=2)
        println("ptrace! n_qubits=$n_qubits (n=$n_iters): total $(dt)ms, per-call $(per_call)ms")
        flush(stdout)

        for p in persistent; ptrace!(p); end
    end
end

_log("ENTER probe_ptrace_timing")
bench_ptrace(10; n_iters=50)
bench_ptrace(15; n_iters=30)
bench_ptrace(18; n_iters=20)
bench_ptrace(20; n_iters=10)
_log("EXIT probe_ptrace_timing")
