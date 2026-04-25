# probe_add_qft_isolated.jl — isolate `add_qft_quantum!` cost under
# a depth-1 outer control (matching _pep_mod_iter!'s `_apply_ctrls(ctrls)`).
# Compare uncontrolled vs controlled at the actual mulmod state size.

using Sturm
using Sturm: add_qft_quantum!, EagerContext, QInt, QBool, when, ptrace!

_t0 = time_ns()
_elapsed() = round((time_ns() - _t0) / 1e9, digits=2)
_log(msg) = (println("[$(rpad(_elapsed(), 7))s] $msg"); flush(stdout))

_log("ENTER probe_add_qft_isolated")

# N=7 mulmod state shape: target(5) + b(5) + ctrl(1) + scratch(4) = 15 live
# N=15 mulmod state shape: target(6) + b(6) + ctrl(1) + scratch(5) = 18 live
function bench(; Wtot, padding_n, label)
    @context EagerContext() begin
        y = QInt{Wtot}(0)
        b = QInt{Wtot}(3)
        ctrl = QBool(1)
        padding = [QBool(0) for _ in 1:padding_n]
        live_total = 2*Wtot + 1 + padding_n

        # Warmup
        when(ctrl) do; add_qft_quantum!(y, b); end

        # Time 5 controlled add_qft calls
        t = time_ns()
        for _ in 1:5
            when(ctrl) do
                add_qft_quantum!(y, b)
            end
        end
        dt_c = round((time_ns() - t) / 1e6, digits=1)
        _log("  $label  Wtot=$Wtot live=$live_total ctrl: 5 calls = $(dt_c) ms ($(round(dt_c/5, digits=1)) ms/call)")

        # Time 5 uncontrolled add_qft calls
        t = time_ns()
        for _ in 1:5
            add_qft_quantum!(y, b)
        end
        dt_u = round((time_ns() - t) / 1e6, digits=1)
        _log("  $label  Wtot=$Wtot live=$live_total free: 5 calls = $(dt_u) ms ($(round(dt_u/5, digits=1)) ms/call)")

        for p in padding; ptrace!(p); end
        ptrace!(b); ptrace!(y); ptrace!(ctrl)
    end
end

# Match the mulmod state size for N=7 c_mul=1
bench(Wtot=4, padding_n=6, label="N=7-shape")

# Match N=15 c_mul=1/2
bench(Wtot=5, padding_n=7, label="N=15-shape")

# Larger to confirm scaling
bench(Wtot=5, padding_n=14, label="20-qubit")

_log("EXIT probe_add_qft_isolated")
