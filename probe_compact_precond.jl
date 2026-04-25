# probe_compact_precond.jl — Stage A0 of bead Sturm.jl-059.
#
# Goal: empirically confirm the soundness precondition for compact_state!:
# every slot that lands in `ctx.free_slots` is deterministically in |0⟩,
# i.e. the amplitude buffer satisfies
#   Σ |amps[i+1]|²  for i with (i & freed_bit_mask) ≠ 0   ≈   0
# at the moment the slot becomes free.
#
# This holds by construction in the current code path:
#   ptrace!(q::QInt|QBool|QCoset) → deallocate!(ctx, wire)
#                                  → _blessed_measure!(ctx, wire)
#                                  → measure!(ctx, wire)
# and `measure!` (src/context/eager.jl:267-275) explicitly resets the
# measured qubit's amplitude to the |0⟩ branch via an in-place swap.
#
# This probe verifies the invariant across realistic scenarios without
# modifying any `src/` code. If a future change ever bypasses `_blessed_measure!`
# on the deallocate path, this probe will fail.
#
# Tolerance: 1e-12 absolute. Floating-point round-off in the projection +
# renormalize loop is well below this.

using Sturm
using Sturm: EagerContext, QBool, QInt, QCoset, ptrace!, when

_t0 = time_ns()
_elapsed() = round((time_ns() - _t0) / 1e9, digits=2)
_log(msg) = (println("[$(rpad(_elapsed(), 7))s] $msg"); flush(stdout))

"""
    residual_norm_sq(ctx::EagerContext, freed_slots::Vector{Int}) -> Float64

Sum of |amp|² over basis indices where any of the given slot bits is set.
This is the precondition residual that `compact_state!` will check before
projecting onto the |0⟩ branch of the freed slots.

Reads ctx.orkan via unsafe_wrap (zero-copy view), same idiom as `measure!`.
"""
function residual_norm_sq(ctx::EagerContext, freed_slots::Vector{Int})
    isempty(freed_slots) && return 0.0
    dim = 1 << ctx.n_qubits
    mask = 0
    for s in freed_slots
        mask |= (1 << s)
    end
    amps = unsafe_wrap(Array{ComplexF64,1}, ctx.orkan.raw.data, dim)
    acc = 0.0
    @inbounds for i in 0:dim-1
        if (i & mask) != 0
            acc += abs2(amps[i + 1])
        end
    end
    return acc
end

const TOLERANCE = 1e-12
mutable struct ScenarioResult
    name::String
    residual::Float64
    ok::Bool
end
const RESULTS = ScenarioResult[]

function record!(name, ctx, freed_slots)
    r = residual_norm_sq(ctx, freed_slots)
    ok = r <= TOLERANCE
    push!(RESULTS, ScenarioResult(name, r, ok))
    _log("  $(ok ? "✓" : "✗") $name : residual = $(r)")
end

# Helper: snapshot the slot indices currently in free_slots after a ptrace.
freed_slot_snapshot(ctx) = copy(ctx.free_slots)

_log("ENTER probe_compact_precond")

# ── Scenario 1: single qubit |+⟩, ptraced ──────────────────────────────────
_log("scenario 1: single qubit |+⟩ ptraced")
@context EagerContext() begin
    ctx = current_context()
    a = QBool(0.5)
    freed_before = freed_slot_snapshot(ctx)
    ptrace!(a)
    freed_after = freed_slot_snapshot(ctx)
    new_freed = setdiff(freed_after, freed_before)
    record!("|+⟩ single qubit ptrace", ctx, new_freed)
end

# ── Scenario 2: Bell pair, ptrace one half (collapses correlated branch) ───
_log("scenario 2: Bell pair, ptrace one half")
@context EagerContext() begin
    ctx = current_context()
    a = QBool(0.5)
    b = QBool(0)
    b ⊻= a   # Bell pair (|00⟩ + |11⟩)/√2
    freed_before = freed_slot_snapshot(ctx)
    ptrace!(a)  # measure a, then reset slot to |0⟩
    new_freed = setdiff(freed_slot_snapshot(ctx), freed_before)
    record!("Bell pair, ptrace a", ctx, new_freed)
    ptrace!(b)
end

# ── Scenario 3: 3-qubit GHZ-like, ptrace all in sequence ───────────────────
_log("scenario 3: 3-qubit GHZ, sequential ptrace")
@context EagerContext() begin
    ctx = current_context()
    a = QBool(0.5)
    b = QBool(0); b ⊻= a
    c = QBool(0); c ⊻= b
    # GHZ: (|000⟩ + |111⟩)/√2
    freed_collected = Int[]
    seen = Set(freed_slot_snapshot(ctx))
    for q in (a, b, c)
        ptrace!(q)
        new_set = Set(freed_slot_snapshot(ctx))
        append!(freed_collected, sort!(collect(setdiff(new_set, seen))))
        seen = new_set
        record!("GHZ ptrace step (cumulative freed = $(length(freed_collected)))",
                ctx, freed_collected)
    end
end

# ── Scenario 4: arbitrary rotations + entanglement, then ptrace ────────────
_log("scenario 4: arbitrary state, multi-qubit ptrace")
@context EagerContext() begin
    ctx = current_context()
    a = QBool(0.3)
    b = QBool(0.7)
    c = QBool(0)
    a.φ += π / 5
    b.θ += π / 7
    c ⊻= a
    when(b) do
        c.φ += π / 3
    end
    freed_collected = Int[]
    seen = Set(freed_slot_snapshot(ctx))
    for q in (c, a, b)
        ptrace!(q)
        new_set = Set(freed_slot_snapshot(ctx))
        append!(freed_collected, sort!(collect(setdiff(new_set, seen))))
        seen = new_set
        record!("arbitrary state, freed=$(length(freed_collected))",
                ctx, freed_collected)
    end
end

# ── Scenario 5: multi-allocate + multi-ptrace mimicking _pep_mod_iter! ─────
_log("scenario 5: alloc-burst then ptrace-burst (Bennett ancilla pattern)")
@context EagerContext() begin
    ctx = current_context()
    base = QInt{4}(5)             # 4 wires base register
    scratch = QInt{4}(0)          # fresh scratch
    # Apply some gates to entangle scratch with base, then uncompute
    for j in 1:4
        sj = QBool(scratch.wires[j], ctx, false)
        bj = QBool(base.wires[j], ctx, false)
        sj ⊻= bj                    # CNOT
    end
    # Uncompute: CNOTs are self-inverse, so re-apply restores scratch=|0⟩
    for j in 1:4
        sj = QBool(scratch.wires[j], ctx, false)
        bj = QBool(base.wires[j], ctx, false)
        sj ⊻= bj
    end
    # Now ptrace scratch (it should be in |0⟩^4 deterministically)
    freed_before = freed_slot_snapshot(ctx)
    ptrace!(scratch)
    new_freed = setdiff(freed_slot_snapshot(ctx), freed_before)
    record!("alloc-burst+uncompute+ptrace (scratch QInt{4})", ctx, new_freed)
    ptrace!(base)
end

# ── Scenario 6: QCoset ptrace (matches mulmod cleanup) ─────────────────────
_log("scenario 6: QCoset alloc + gates + ptrace")
@context EagerContext() begin
    ctx = current_context()
    target = QCoset{3, 1}(5, 7)
    b = QCoset{3, 1}(ctx, 0, 7)
    # Apply some controlled SWAPs (mimics mulmod step 2)
    ctrl = QBool(1)
    when(ctrl) do
        for j in 1:4   # Wtot=4
            swap!(QBool(target.reg.wires[j], ctx, false),
                  QBool(b.reg.wires[j],      ctx, false))
        end
    end
    freed_before = freed_slot_snapshot(ctx)
    ptrace!(b)
    new_freed = setdiff(freed_slot_snapshot(ctx), freed_before)
    record!("QCoset ptrace after controlled-SWAP", ctx, new_freed)
    ptrace!(target); ptrace!(ctrl)
end

# ── Scenario 7: real mulmod, snapshot at end ───────────────────────────────
_log("scenario 7: full mulmod cleanup snapshot")
@context EagerContext() begin
    ctx = current_context()
    target = QCoset{3, 1}(1, 7)
    ctrl = QBool(1)
    Sturm._shor_mulmod_E_controlled!(target, 3, ctrl; c_mul=1)
    # After the mulmod call, scratch + b are all freed (ptraced internally)
    record!("post-mulmod N=7 c_mul=1, all internal ancillae freed",
            ctx, copy(ctx.free_slots))
    ptrace!(target); ptrace!(ctrl)
end

# ── Summary ───────────────────────────────────────────────────────────────
_log("")
_log("─── SUMMARY ───")
all_ok = all(r.ok for r in RESULTS)
for r in RESULTS
    flag = r.ok ? "✓" : "✗ FAIL"
    _log("  $flag  residual=$(rpad(round(r.residual, sigdigits=3), 14)) $(r.name)")
end
_log("")
if all_ok
    _log("ALL SCENARIOS PASS — precondition holds, residual < $(TOLERANCE).")
    _log("compact_state! soundness assumption is empirically validated.")
else
    _log("FAILURES OBSERVED — precondition does not hold in some scenario.")
    _log("compact_state! design must be revisited before implementation.")
    error("probe_compact_precond: precondition violated in $(count(r->!r.ok, RESULTS)) scenarios")
end

_log("EXIT probe_compact_precond")
