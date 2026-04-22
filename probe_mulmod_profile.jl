# probe_mulmod_profile.jl — Use Julia's @profile to identify the hotspot in
# _shor_mulmod_E_controlled! at N=15.

using Sturm
using Sturm: _shor_mulmod_E_controlled!
using Profile

_t0 = time_ns()
_elapsed() = round((time_ns() - _t0) / 1e9, digits=2)
_log(msg) = (println("[$(rpad(_elapsed(), 7))s] $msg"); flush(stdout))

_log("ENTER probe_mulmod_profile")

# Warmup
_log("warmup: N=3")
@context EagerContext() begin
    target = QCoset{2, 1}(1, 3)
    ctrl = QBool(1)
    _shor_mulmod_E_controlled!(target, 2, ctrl; c_mul=1)
    ptrace!(target); ptrace!(ctrl)
end
_log("warmup done")

# Profile a single N=15 mulmod — but use SMALLER case so we don't wait 7 min.
# N=7 at W=3 cpad=1 c_mul=1: peak ~14 qubits, should finish in seconds.
_log("profile run: N=7 cpad=1 c_mul=1")
Profile.clear()
@profile begin
    @context EagerContext() begin
        target = QCoset{3, 1}(1, 7)
        ctrl = QBool(1)
        _shor_mulmod_E_controlled!(target, 3, ctrl; c_mul=1)
        ptrace!(target); ptrace!(ctrl)
    end
end
_log("profile done")

# Dump top hotspots
_log("TOP HOTSPOTS (top 25 by count):")
io = IOBuffer()
Profile.print(io; maxdepth=20, mincount=5, format=:flat, sortedby=:count, C=false)
for line in split(String(take!(io)), '\n')[1:min(50, end)]
    println(line)
end
flush(stdout)

_log("EXIT probe_mulmod_profile")
