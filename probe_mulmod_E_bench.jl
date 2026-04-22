# probe_mulmod_E_bench.jl — Isolate the N=15 perf issue (bead Sturm.jl-059).
#
# Test a single _shor_mulmod_E_controlled! call at N=15 W=4 cpad=1
# across c_mul ∈ {1, 2}. If c_mul=1 is fast and c_mul=2 is slow → the Val(w)
# ragged-window path or the 4-entry QROM is the hotspot. If both are slow →
# the depth-2-controls-in-add_qft_quantum path is the hotspot.

using Sturm
using Sturm: _shor_mulmod_E_controlled!

_t0 = time_ns()
_elapsed() = round((time_ns() - _t0) / 1e9, digits=2)
_log(msg) = (println("[$(rpad(_elapsed(), 7))s] $msg"); flush(stdout))

_log("ENTER probe_mulmod_E_bench")

# Warmup — JIT-compile the path via a small case first.
_log("warmup: N=3 W=2 cpad=1 c_mul=1")
@context EagerContext() begin
    target = QCoset{2, 1}(1, 3)
    ctrl = QBool(1)
    t_start = time_ns()
    _shor_mulmod_E_controlled!(target, 2, ctrl; c_mul=1)
    dt = round((time_ns() - t_start) / 1e3, digits=0)
    _log("  warmup c_mul=1: $(dt)µs")
    ptrace!(target); ptrace!(ctrl)
end

# N=15 c_mul=1
_log("N=15 W=4 cpad=1 c_mul=1")
@context EagerContext() begin
    target = QCoset{4, 1}(7, 15)
    ctrl = QBool(1)
    t_start = time_ns()
    _shor_mulmod_E_controlled!(target, 4, ctrl; c_mul=1)
    dt = round((time_ns() - t_start) / 1e9, digits=2)
    _log("  N=15 c_mul=1 mulmod: $(dt)s")
    ptrace!(target); ptrace!(ctrl)
end

# N=15 c_mul=2 — same state size but uses Val(w) ragged path (w=2,2,1)
_log("N=15 W=4 cpad=1 c_mul=2")
@context EagerContext() begin
    target = QCoset{4, 1}(7, 15)
    ctrl = QBool(1)
    t_start = time_ns()
    _shor_mulmod_E_controlled!(target, 4, ctrl; c_mul=2)
    dt = round((time_ns() - t_start) / 1e9, digits=2)
    _log("  N=15 c_mul=2 mulmod: $(dt)s")
    ptrace!(target); ptrace!(ctrl)
end

_log("EXIT probe_mulmod_E_bench")
