# probe_count_DE.jl — Bead Sturm.jl-2qp step (i): per-primitive ccall fan-out.
#
# Hypothesis from the bead: the ~750× per-DAG-gate slowdown of
# _shor_mulmod_E_controlled! vs mulmod_beauregard! at N=15 is dominated by
# fan-out from abstract DAG nodes into many primitive Orkan ccalls
# (apply_cx! / apply_ry! / apply_rz! / apply_ccx! entries).
#
# This probe times one mulmod and reads the diagnostic counters bumped on
# every apply_*! entry, plus a control-stack-depth breakdown. Cross-
# referenced against probe_toffoli_DE.jl's DAG node counts:
#
#   N=15 D (Beauregard) — 532 DAG nodes/mulmod (12 CCX + 400 cRz + 120 ccRz)
#   N=15 E (windowed)   — 390 DAG nodes/mulmod (130 CCX + 170 cRz + 90 ccRz)
#
# If E's per-DAG-node ccall ratio is much higher than D's, the fan-out
# hypothesis (i) is confirmed.

using Sturm
using Sturm: _shor_mulmod_E_controlled!, mulmod_beauregard!

_t0 = time_ns()
_elapsed() = round((time_ns() - _t0) / 1e9, digits=2)
_log(msg) = (println("[$(rpad(_elapsed(), 7))s] $msg"); flush(stdout))

# Pretty-print a counters NamedTuple.
function _show_counts(label::AbstractString, c, dt_ms::Real, dag_nodes::Int)
    bucket_str(b) = "[nc=0:$(b[1]) 1:$(b[2]) 2:$(b[3]) 3:$(b[4]) ≥4:$(b[5])]"
    println()
    println("== $label ==")
    println("  wall time       : $(round(dt_ms, digits=2)) ms")
    println("  DAG nodes (ref) : $dag_nodes")
    println("  apply_*! total  : $(c.total)")
    println("    apply_ry!     : $(c.ry)   $(bucket_str(c.nc_ry))")
    println("    apply_rz!     : $(c.rz)  $(bucket_str(c.nc_rz))")
    println("    apply_cx!     : $(c.cx)  $(bucket_str(c.nc_cx))")
    println("    apply_ccx!    : $(c.ccx) $(bucket_str(c.nc_ccx))")
    fanout = c.total / max(dag_nodes, 1)
    per_call_us = (dt_ms * 1000) / max(c.total, 1)
    println("  fan-out         : $(round(fanout, digits=2))× ccalls per DAG node")
    println("  per-ccall time  : $(round(per_call_us, digits=2)) µs")
    println("  n_qubits at gate (per-ccall sampling):")
    println("    peak n_qubits : $(c.nq_max)")
    avg_nq = c.total > 0 ? log2(c.nq_sum_2 / c.total) : 0.0
    println("    avg n_qubits  : $(round(avg_nq, digits=2))  (= log2 of mean 2^nq)")
    bucket_labels = ["0-3", "4-7", "8-11", "12-15", "16-19", "20-23", "24-27", "28-31", "≥32"]
    nq_str = join(["[$(bucket_labels[i]):$(c.nq_buckets[i])]" for i in 1:9 if c.nq_buckets[i] > 0], " ")
    println("    nq histogram  : $nq_str")
    flush(stdout)
end

_log("ENTER probe_count_DE")

# Warmup: JIT-compile both paths via small N=3 cases first.
_log("warmup: N=3 D + E paths")
@context EagerContext() begin
    x = QInt{3}(1)
    ctrl = QBool(1)
    mulmod_beauregard!(x, 2, 3, ctrl)
    ptrace!(x); ptrace!(ctrl)
end
@context EagerContext() begin
    target = QCoset{2, 1}(1, 3)
    ctrl = QBool(1)
    _shor_mulmod_E_controlled!(target, 2, ctrl; c_mul=1)
    ptrace!(target); ptrace!(ctrl)
end
_log("  warmup done")

# ── D (Beauregard) at N=15, L=4 ─────────────────────────────────────────────
_log("D mulmod_beauregard! at N=15 L=4")
function run_D()
    ctx_box = Ref{EagerContext}()
    @context EagerContext() begin
        ctx = current_context()
        ctx_box[] = ctx
        x = QInt{4}(7)
        ctrl = QBool(1)
        reset_gate_counts!()
        ctx._n_qubits_hwm = ctx.n_qubits  # reset HWM to current live count
        t0 = time_ns()
        mulmod_beauregard!(x, 4, 15, ctrl)
        dt_ms = (time_ns() - t0) / 1e6
        c = gate_counts()
        hwm = ctx._n_qubits_hwm
        nq_now = ctx.n_qubits
        ptrace!(x); ptrace!(ctrl)
        (c, dt_ms, hwm, nq_now)
    end
end
d_counts, d_dt_ms, d_hwm, d_nq_now = run_D()
println("  D peak n_qubits during call: $d_hwm  (n_qubits at end: $d_nq_now)")
_show_counts("D-beauregard N=15 L=4", d_counts, d_dt_ms, 532)

# ── E (windowed) at N=15, c_mul=1 ───────────────────────────────────────────
_log("E _shor_mulmod_E_controlled! at N=15 c_mul=1")
function run_E(c_mul::Int)
    @context EagerContext() begin
        ctx = current_context()
        target = QCoset{4, 1}(7, 15)
        ctrl = QBool(1)
        reset_gate_counts!()
        ctx._n_qubits_hwm = ctx.n_qubits
        t0 = time_ns()
        _shor_mulmod_E_controlled!(target, 4, ctrl; c_mul=c_mul)
        dt_ms = (time_ns() - t0) / 1e6
        c = gate_counts()
        hwm = ctx._n_qubits_hwm
        nq_now = ctx.n_qubits
        ptrace!(target); ptrace!(ctrl)
        (c, dt_ms, hwm, nq_now)
    end
end
e1_counts, e1_dt_ms, e1_hwm, e1_nq_now = run_E(1)
println("  E c_mul=1 peak n_qubits: $e1_hwm  (n_qubits at end: $e1_nq_now)")
_show_counts("E-windowed N=15 c_mul=1", e1_counts, e1_dt_ms, 390)

# ── E (windowed) at N=15, c_mul=2 ───────────────────────────────────────────
_log("E _shor_mulmod_E_controlled! at N=15 c_mul=2")
e2_counts, e2_dt_ms, e2_hwm, e2_nq_now = run_E(2)
println("  E c_mul=2 peak n_qubits: $e2_hwm  (n_qubits at end: $e2_nq_now)")
_show_counts("E-windowed N=15 c_mul=2", e2_counts, e2_dt_ms, 390)

# ── Cross-comparison ─────────────────────────────────────────────────────────
println()
println("== cross-comparison ==")
println("  D total ccalls            : $(d_counts.total)")
println("  E (c_mul=1) total ccalls  : $(e1_counts.total)")
println("  E (c_mul=2) total ccalls  : $(e2_counts.total)")
println("  E/D fanout ratio (c_mul=2): $(round(e2_counts.total / max(d_counts.total, 1), digits=2))×")
println("  D wall time / ccall       : $(round(d_dt_ms * 1000 / max(d_counts.total, 1), digits=2)) µs")
println("  E (c_mul=1) wall / ccall  : $(round(e1_dt_ms * 1000 / max(e1_counts.total, 1), digits=2)) µs")
println("  E (c_mul=2) wall / ccall  : $(round(e2_dt_ms * 1000 / max(e2_counts.total, 1), digits=2)) µs")
println("  E/D wall ratio (c_mul=2)  : $(round(e2_dt_ms / max(d_dt_ms, 1e-9), digits=2))×")

_log("EXIT probe_count_DE")
