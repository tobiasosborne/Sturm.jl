# probe_addq_timing.jl — Synthetic bench for add_qft_quantum! performance.
#
# Goal: isolate the slow path in _shor_mulmod_E_controlled! at N=15. The
# hypothesis is that add_qft_quantum! under when(ctrl) is the hotspot —
# each inner Rz becomes depth-2-controlled, triggering _multi_controlled_gate!
# which allocates/deallocates workspace per call + runs 6 Orkan gates.
#
# Tests:
#   (a) add_qft_quantum! WITHOUT when(ctrl)   — baseline
#   (b) add_qft_quantum! UNDER when(ctrl)      — depth-2 controls
#   (c) single apply_rz! with depth-2 controls — bare primitive cost
#
# All on a 20-qubit state (padding qubits allocated first to reach the
# same state size as N=15 mulmod).

using Sturm
using Sturm: add_qft_quantum!

_t0 = time_ns()
_elapsed() = round((time_ns() - _t0) / 1e9, digits=2)
_log(msg) = (println("[$(rpad(_elapsed(), 7))s] $msg"); flush(stdout))

_log("ENTER probe_addq_timing")

function bench_path(; controlled::Bool)
    L = 5
    padding_n = 14  # total live ≈ 2L + 1 + 14 = 25 at peak... actually this overshoots
    padding_n = 9   # more reasonable: 2L+1+9 = 20
    @context EagerContext() begin
        y = QInt{L}(0)
        b = QInt{L}(3)
        ctrl = QBool(1)
        # Padding qubits to reach 20-qubit state
        padding = [QBool(0) for _ in 1:padding_n]

        # Warm up JIT with one call
        superpose!(y)
        if controlled
            when(ctrl) do; add_qft_quantum!(y, b); end
        else
            add_qft_quantum!(y, b)
        end
        interfere!(y)

        # Time 10 repeated calls
        t0 = time_ns()
        for _ in 1:10
            superpose!(y)
            if controlled
                when(ctrl) do; add_qft_quantum!(y, b); end
            else
                add_qft_quantum!(y, b)
            end
            interfere!(y)
        end
        dt = round((time_ns() - t0) / 1e6, digits=1)
        label = controlled ? "controlled" : "uncontrolled"
        _log("  10× add_qft_quantum! ($label) on 20-qubit state: $(dt)ms")

        # Cleanup
        for p in padding; ptrace!(p); end
        ptrace!(b); ptrace!(y); ptrace!(ctrl)
    end
end

_log("(a) uncontrolled add_qft_quantum!")
bench_path(; controlled=false)

_log("(b) controlled add_qft_quantum! (when(ctrl))")
bench_path(; controlled=true)

# (c) Bare apply_rz! at depth-2 controls
function bench_rz_depth2()
    @context EagerContext() begin
        target = QBool(0)
        c1 = QBool(1)
        c2 = QBool(1)
        padding = [QBool(0) for _ in 1:17]   # 3 + 17 = 20

        # Warm up
        when(c1) do
            when(c2) do
                target.φ += π/4
            end
        end

        # Time 100 depth-2 Rz
        t0 = time_ns()
        for _ in 1:100
            when(c1) do
                when(c2) do
                    target.φ += π/4
                end
            end
        end
        dt = round((time_ns() - t0) / 1e3, digits=1)
        _log("  100× depth-2 Rz on 20-qubit state: $(dt)ms ($(round(dt/100, digits=2))ms/call)")

        for p in padding; ptrace!(p); end
        ptrace!(target); ptrace!(c1); ptrace!(c2)
    end
end

_log("(c) bare depth-2 apply_rz!")
bench_rz_depth2()

_log("EXIT probe_addq_timing")
