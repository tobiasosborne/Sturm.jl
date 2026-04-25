# probe_mc_dealloc_cost.jl — Measure the per-call cost of
# `_multi_controlled_gate!` workspace alloc + cascade + dealloc at ~20-qubit
# scale, isolated from JIT and Bennett.jl. Bead Sturm.jl-059 Stage A0.
#
# Goal: figure out whether replacing per-call workspace allocation
# (`allocate!` + `_blessed_measure!`-on-`deallocate!`) with a pool yields
# enough to bend the N=15 c_mul=2 mulmod wall-clock from ~21 min to seconds.

using Sturm
using Sturm: allocate!, deallocate!, current_controls, push_control!, pop_control!,
             apply_ry!, apply_rz!, apply_cx!, apply_ccx!, EagerContext, WireID
using Sturm: with_empty_controls

_t0 = time_ns()
_elapsed() = round((time_ns() - _t0) / 1e9, digits=2)
_log(msg) = (println("[$(rpad(_elapsed(), 7))s] $msg"); flush(stdout))

_log("ENTER probe_mc_dealloc_cost")

# Scale: 20-qubit state matches the hot path during _shor_mulmod_E_controlled!
# at N=15 c_mul=2 (peak ~20 live qubits per the bead).
const N_LIVE = 18
const N_CALLS = 200

# Build a context and pad it to N_LIVE live qubits.
_log("setup: allocate $N_LIVE live qubits")
ctx = EagerContext(capacity=24)
live = [allocate!(ctx) for _ in 1:N_LIVE]
_log("setup done — context has $(length(live)) live wires")

# ── Bench 1 — pure allocate + deallocate (no gate) ──────────────────────────

_log("bench1: $N_CALLS × (allocate! + deallocate!)  no gate")
# Warmup
for _ in 1:5
    w = allocate!(ctx); deallocate!(ctx, w)
end
t1 = time_ns()
for _ in 1:N_CALLS
    w = allocate!(ctx)
    deallocate!(ctx, w)
end
dt1 = (time_ns() - t1) / 1e6
_log("  bench1: $(round(dt1, digits=2)) ms total = $(round(dt1/N_CALLS*1000, digits=2)) µs/call")

# ── Bench 2 — alloc + 1 ccx + alloc-and-recover (mimics multi-control body) ──

_log("bench2: $N_CALLS × (alloc + ccx + reverse + dealloc)  -- 2-control synthetic")
c1 = live[1]; c2 = live[2]; tgt = live[3]
# Warmup
for _ in 1:5
    push_control!(ctx, c1); push_control!(ctx, c2)
    try
        apply_rz!(ctx, tgt, 0.1)
    finally
        pop_control!(ctx); pop_control!(ctx)
    end
end
t2 = time_ns()
for _ in 1:N_CALLS
    push_control!(ctx, c1); push_control!(ctx, c2)
    try
        apply_rz!(ctx, tgt, 0.1)   # depth-2 control → _multi_controlled_gate!
    finally
        pop_control!(ctx); pop_control!(ctx)
    end
end
dt2 = (time_ns() - t2) / 1e6
_log("  bench2: $(round(dt2, digits=2)) ms total = $(round(dt2/N_CALLS*1000, digits=2)) µs/call")

# ── Bench 3 — same depth-2 RZ but with a SINGLE shared workspace allocated
# once outside the loop. Manually simulates the workspace-pool we want to
# add to `_multi_controlled_gate!`.
_log("bench3: $N_CALLS × (cascade fwd + RZ + cascade rev) with POOLED workspace")
ws = allocate!(ctx)   # one workspace ancilla, never freed during the loop
saved = [c1, c2]
# Warmup
for _ in 1:5
    with_empty_controls(ctx) do
        apply_ccx!(ctx, c1, c2, ws)            # cascade forward
        # single-controlled rz: NC&C ABC
        apply_rz!(ctx, tgt,  0.05)
        apply_cx!(ctx, ws, tgt)
        apply_rz!(ctx, tgt, -0.05)
        apply_cx!(ctx, ws, tgt)
        apply_ccx!(ctx, c1, c2, ws)            # cascade reverse
    end
end
t3 = time_ns()
for _ in 1:N_CALLS
    with_empty_controls(ctx) do
        apply_ccx!(ctx, c1, c2, ws)
        apply_rz!(ctx, tgt,  0.05)
        apply_cx!(ctx, ws, tgt)
        apply_rz!(ctx, tgt, -0.05)
        apply_cx!(ctx, ws, tgt)
        apply_ccx!(ctx, c1, c2, ws)
    end
end
dt3 = (time_ns() - t3) / 1e6
deallocate!(ctx, ws)
_log("  bench3: $(round(dt3, digits=2)) ms total = $(round(dt3/N_CALLS*1000, digits=2)) µs/call")

# ── Summary ────────────────────────────────────────────────────────────────
_log("SUMMARY")
_log("  pure alloc+dealloc        : $(round(dt1/N_CALLS*1000, digits=2)) µs/call")
_log("  current depth-2 RZ        : $(round(dt2/N_CALLS*1000, digits=2)) µs/call")
_log("  pooled-workspace RZ       : $(round(dt3/N_CALLS*1000, digits=2)) µs/call")
_log("  estimated win per call    : $(round((dt2 - dt3)/N_CALLS*1000, digits=2)) µs")
_log("  win × 90 calls/mulmod     : $(round((dt2 - dt3)/N_CALLS*90, digits=2)) ms / mulmod")

_log("EXIT probe_mc_dealloc_cost")
