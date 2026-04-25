"""
    EagerContext

Executes quantum operations immediately via the Orkan C backend.
State vector simulation: amplitudes stored in Orkan's `state_t` (PURE mode).

Qubit recycling: after measurement collapses a qubit to |0> or |1>, the qubit
slot is reset to |0> and returned to a free-list for reuse by future allocations.
This prevents unbounded state vector growth in loops.
"""
mutable struct EagerContext <: AbstractContext
    orkan::OrkanState
    n_qubits::Int                      # total slots in use (live + recycled slots exist up to this)
    wire_to_qubit::Dict{WireID, Int}   # WireID → 0-based qubit index in Orkan state
    consumed::Set{WireID}              # wires that have been measured or discarded
    control_stack::Vector{WireID}      # active `when` controls
    capacity::Int                      # pre-allocated Orkan qubit count
    free_slots::Vector{Int}            # recycled qubit indices available for reuse
    _compact_count::Int                # bead 059: number of compact_state! commits
    _n_qubits_hwm::Int                 # bead w9e: peak n_qubits ever reached;
                                       #   bumped on allocate, never reset by compact

    function EagerContext(; capacity::Int=8)
        capacity > MAX_QUBITS && error(
            "EagerContext: initial capacity $capacity exceeds MAX_QUBITS ($MAX_QUBITS). " *
            "A $capacity-qubit statevector needs $(Base.format_bytes(_estimated_bytes(capacity)))."
        )
        orkan = OrkanState(ORKAN_PURE, capacity)
        orkan[0] = 1.0 + 0.0im
        new(orkan, 0, Dict{WireID, Int}(), Set{WireID}(), WireID[], capacity, Int[], 0, 0)
    end
end

# ── Qubit allocation ──────────────────────────────────────────────────────────

function allocate!(ctx::EagerContext)::WireID
    wire = fresh_wire!()

    if !isempty(ctx.free_slots)
        # Reuse a recycled slot — it's already in |0>. n_qubits unchanged,
        # HWM unchanged (no new peak).
        qubit_idx = pop!(ctx.free_slots)
        ctx.wire_to_qubit[wire] = qubit_idx
        return wire
    end

    if ctx.n_qubits >= ctx.capacity
        _grow_state!(ctx)
    end
    qubit_idx = ctx.n_qubits
    ctx.wire_to_qubit[wire] = qubit_idx
    ctx.n_qubits += 1
    # bead w9e: track all-time peak so tests can bound a function's HWM
    # even when compaction fires mid-execution and resets `n_qubits`.
    if ctx.n_qubits > ctx._n_qubits_hwm
        ctx._n_qubits_hwm = ctx.n_qubits
    end
    return wire
end

"""Maximum qubit capacity for EagerContext. 2^30 amplitudes × 16 bytes = 16 GB."""
const MAX_QUBITS = 30

"""Additive growth step: add 4 qubits per resize (×16 amplitudes, not ×2^old_cap)."""
const GROW_STEP = 4

"""
    _estimated_bytes(n_qubits) -> Int

Memory in bytes for a PURE statevector with `n_qubits` qubits.
"""
_estimated_bytes(n::Int) = (1 << n) * 16

"""
    _grow_state!(ctx::EagerContext)

Grow Orkan state capacity by GROW_STEP qubits (additive, not doubling).
Guards against exceeding MAX_QUBITS and checks available memory before allocating.
"""
function _grow_state!(ctx::EagerContext)
    old_cap = ctx.capacity
    new_cap = old_cap + GROW_STEP
    new_cap > MAX_QUBITS && error(
        "EagerContext: capacity would grow to $new_cap qubits " *
        "($(Base.format_bytes(_estimated_bytes(new_cap)))). " *
        "Hard limit is $MAX_QUBITS qubits ($(Base.format_bytes(_estimated_bytes(MAX_QUBITS)))). " *
        "Use qubit recycling (measure/discard) to free slots."
    )

    needed = _estimated_bytes(new_cap)
    avail = Sys.free_memory()
    if needed > avail ÷ 2  # refuse if we'd consume >50% of free RAM
        error(
            "EagerContext: growing to $new_cap qubits needs $(Base.format_bytes(needed)) " *
            "but only $(Base.format_bytes(avail)) free. Aborting to prevent OOM."
        )
    end

    old_dim = 1 << old_cap
    new_dim = 1 << new_cap
    new_orkan = OrkanState(ORKAN_PURE, new_cap)

    # Bulk copy via unsafe_wrap + unsafe_copyto!. The old FFI-per-element loop
    # (orkan_state_get for each i) made state growth O(2^n) FFI crossings,
    # which was catastrophic past ~16 qubits inside _multi_controlled_gate!'s
    # workspace allocation. See bead Sturm.jl-059.
    old_amps = unsafe_wrap(Array{ComplexF64,1}, ctx.orkan.raw.data, old_dim)
    new_amps = unsafe_wrap(Array{ComplexF64,1}, new_orkan.raw.data, new_dim)
    unsafe_copyto!(new_amps, 1, old_amps, 1, old_dim)
    # Remaining entries [old_dim+1 : new_dim] stay 0 (state_init! zeroed them).

    ctx.orkan = new_orkan
    ctx.capacity = new_cap
end

# ── State compaction (bead Sturm.jl-059) ──────────────────────────────────────
#
# `n_qubits` and the Orkan state grow monotonically: once the high-water-mark
# is reached, every gate operates on `2^n_qubits` amplitudes regardless of
# how many wires are actually live. After a burst of `_blessed_measure!`-
# driven `deallocate!` calls (e.g. the Bennett ancilla cleanup at the end
# of `apply_reversible!`), `free_slots` accumulates and `n_qubits` stays
# stuck at its peak. `compact_state!` reclaims the wasted dimension.
#
# Soundness: A0 (probe_compact_precond.jl) empirically verified that every
# slot in `free_slots` is deterministically |0⟩ — `_blessed_measure!`
# resets the slot via amplitude swap before adding it to the free list
# (see `measure!` at lines ~267-275). This means the live tensor factor
# can be extracted exactly by projecting onto the |0⟩ branch of the
# freed bits. Verification of this precondition runs by default; any
# violation `error()`s loud (CLAUDE.md rule 1).
#
# Architecture: compute-then-commit. Phase 1 reads `ctx` only; Phase 2
# verifies the residual norm; Phase 3 builds the new Orkan state on the
# side; Phase 4 commits via a sequence of infallible field writes. At
# every line of `compact_state!`, `ctx` is either fully old or fully new
# — never half. Synthesised from Proposer A (data-flow) + Proposer B
# (invariant-first) ceremony per CLAUDE.md rule 2.

"""
Plan struct returned by `_compact_plan(ctx)`. Computed read-only on `ctx`;
the rest of `compact_state!` reads only this. Returning `nothing` from
`_compact_plan` means the fast-path no-op fired.
"""
struct CompactPlan
    old_n::Int
    new_n::Int
    new_capacity::Int
    live_wires::Vector{WireID}     # sorted by WireID.id (stable across calls)
    old_slots::Vector{Int}         # sorted ascending; old_slots[k] = wire_to_qubit[live_wires[k]]
    freed_mask::UInt64             # OR of (1 << s) for s in free_slots; max old_n=30 fits
end

"""
    _compact_plan(ctx::EagerContext) -> Union{Nothing, CompactPlan}

Validate `ctx` invariants and return a plan. Returns `nothing` if
`free_slots` is empty (fast-path no-op for `compact_state!`). Errors loud
on any invariant violation — every check has a precise message.

The body is factored into `_compact_plan_impl` (operating on the field set)
so `DensityMatrixContext` can reuse it verbatim — both contexts carry the
same `n_qubits / capacity / free_slots / wire_to_qubit / consumed` layout
relevant to the plan, and the plan itself is buffer-shape-agnostic.
"""
_compact_plan(ctx::EagerContext) = _compact_plan_impl(
    ctx.n_qubits, ctx.capacity, ctx.free_slots, ctx.wire_to_qubit, ctx.consumed)

"""
    _compact_plan_impl(n_qubits, capacity, free_slots, wire_to_qubit, consumed)
        -> Union{Nothing, CompactPlan}

Internal: shared plan-builder for state-owning contexts (EagerContext,
DensityMatrixContext). Operates only on the field arguments — no buffer
access, no FFI — so it is correct for any context whose state-meta layout
matches eager's. Errors loud on every invariant violation.
"""
function _compact_plan_impl(n_qubits::Int, capacity::Int, free_slots::Vector{Int},
                            wire_to_qubit::Dict{WireID, Int},
                            consumed::Set{WireID})::Union{Nothing, CompactPlan}
    isempty(free_slots) && return nothing

    # Invariant: capacity ≥ n_qubits (otherwise allocate would have grown).
    capacity >= n_qubits ||
        error("compact_state!: invariant violation — capacity ($(capacity)) < n_qubits ($(n_qubits))")

    # Invariant: every free_slot index is in [0, n_qubits).
    for s in free_slots
        (0 <= s < n_qubits) ||
            error("compact_state!: free_slots contains out-of-range index $s (n_qubits=$(n_qubits))")
    end

    # Invariant: free_slots has no duplicates.
    if length(unique(free_slots)) != length(free_slots)
        error("compact_state!: free_slots contains duplicates: $(free_slots)")
    end

    # Invariant: free_slots and live-slot set are disjoint.
    free_set = Set(free_slots)
    live_slot_vals = collect(values(wire_to_qubit))
    for s in live_slot_vals
        s in free_set &&
            error("compact_state!: slot $s appears in BOTH free_slots and wire_to_qubit values — corruption")
    end

    # Invariant: wire_to_qubit has no duplicate slot values (no two wires share a slot).
    if length(unique(live_slot_vals)) != length(live_slot_vals)
        error("compact_state!: wire_to_qubit has duplicate slot indices — two wires share a slot")
    end

    # Invariant: every live wire is NOT in `consumed`.
    for w in keys(wire_to_qubit)
        w in consumed &&
            error("compact_state!: wire $(w) is in BOTH wire_to_qubit and consumed — corruption")
    end

    # Invariant: live + freed slot count fits in n_qubits.
    if length(wire_to_qubit) + length(free_slots) > n_qubits
        error("compact_state!: live ($(length(wire_to_qubit))) + freed ($(length(free_slots))) " *
              "exceeds n_qubits ($(n_qubits))")
    end

    # Build the plan. Order live wires by their *old slot index* ascending,
    # NOT by WireID.id. The invariant is: `old_slots[k] == wire_to_qubit[live_wires[k]]`.
    # This lets `_compact_scatter!` use a monotonic bit-mask scatter
    # (cache-friendly) AND keeps the new `wire_to_qubit` consistent with
    # the scatter (wire at old slot `old_slots[k]` ends up at new slot k-1).
    # Sorting by WireID.id and then re-sorting old_slots was a bug — it broke
    # the slot↔wire correspondence and silently permuted amplitudes within
    # the live set (regressed test_shor.jl statistical tests until fixed).
    # The same monotonicity is what makes the DM scatter's lower-triangle
    # preservation property hold (see density.jl).
    live_wires = sort!(collect(keys(wire_to_qubit)), by = w -> wire_to_qubit[w])
    old_slots = Int[wire_to_qubit[w] for w in live_wires]   # ascending by construction
    new_n = length(live_wires)

    # Capacity hysteresis. Three constraints:
    #   (a) keep GROW_STEP headroom so a Bennett K-ancilla burst (typical
    #       K up to ~15) right after the compact does not immediately re-grow;
    #   (b) bound shrink delta to 2*GROW_STEP per compact. This caps the
    #       compact-then-grow oscillation: if we shrink from capacity 28 to
    #       20 (delta 8) and then grow back, the grow trajectory is
    #       20→24→28, with the largest transient at the 24→28 step
    #       (4 GiB) — within the half-RAM check in `_grow_state!`. Without
    #       this cap, the trajectory could be 17→21→25→29, hitting
    #       29 (8 GiB transient > available/2 on a 10-GiB-free machine);
    #   (c) clamp to MAX_QUBITS to stay within the Orkan limit.
    floor_cap = max(new_n + GROW_STEP, capacity - 2 * GROW_STEP)
    new_capacity = min(floor_cap, MAX_QUBITS)
    new_capacity >= new_n ||
        error("compact_state!: hysteresis clamp produced new_capacity=$new_capacity < new_n=$new_n")

    # Build the freed-bit mask (UInt64, plenty for n_qubits ≤ 30).
    freed_mask = UInt64(0)
    for s in free_slots
        freed_mask |= UInt64(1) << s
    end

    return CompactPlan(n_qubits, new_n, new_capacity, live_wires, old_slots, freed_mask)
end

"""
    _compact_verify_freed_zero(ctx::EagerContext, plan::CompactPlan) -> nothing

Verify the soundness precondition: every slot in `free_slots` is in |0⟩.
Computed as the residual norm² over basis indices where any freed bit is
set. Errors loud if above tolerance. CLAUDE.md rule 1.

Tolerance: `1e-10 * max(1, length(free_slots))`. Floating-point noise from
gate sequences accumulates at `eps() · O(2^n)`; a single failed reset
(the bug case) leaves residual ≥ ~0.5, six orders of magnitude above the
tolerance — the gap is huge.
"""
function _compact_verify_freed_zero(ctx::EagerContext, plan::CompactPlan)
    # bead Sturm.jl-179: env-gated. When `STURM_COMPACT_VERIFY=0` the scan
    # is skipped — useful only for hot-path workloads that have empirically
    # confirmed the precondition holds. Default is on (fail-loud).
    _COMPACT_VERIFY_ENABLED[] || return nothing
    old_dim = 1 << plan.old_n
    old_amps = unsafe_wrap(Array{ComplexF64,1}, ctx.orkan.raw.data, old_dim)
    residual = 0.0
    @inbounds for i in 0:old_dim - 1
        if (UInt64(i) & plan.freed_mask) != 0
            residual += abs2(old_amps[i + 1])
        end
    end
    n_freed = count_ones(plan.freed_mask)
    tol = 1e-10 * max(1.0, Float64(n_freed))
    if residual > tol
        error("compact_state!: precondition violated — freed slots are not |0⟩.\n" *
              "  residual norm² = $(residual) (tolerance = $(tol))\n" *
              "  free_slots     = $(ctx.free_slots)\n" *
              "  n_qubits       = $(plan.old_n), old_dim = $(old_dim)\n" *
              "A slot was returned to free_slots without being reset to |0⟩. The\n" *
              "deallocate path MUST go through _blessed_measure!. See bead Sturm.jl-059.")
    end
    return nothing
end

"""
    _compact_scatter!(new_orkan, old_orkan, plan) -> nothing

Project the old amplitude buffer onto the |0⟩ branch of the freed slots
and copy into the new (smaller) buffer in compact layout. Outer loop is
over the new (small) index space j; for each j we decode its bits and
re-encode them at the corresponding *old* slot positions in `old_index`.
Freed slots default to bit=0 in `old_index` — the |0⟩ branch.

Auditable, no clever bit tricks. Cost: O(2^new_n · new_n).

# Fast path (bead Sturm.jl-2fg)
When `live_slots == 0:new_n-1` — the typical Bennett-ancilla-burst
post-state where the freed slots are at the high end — the bit-expand
collapses to identity (`old_index == j` for every j) and the scatter
becomes a prefix copy. We detect this with a single range comparison
(no allocation) and short-circuit to `unsafe_copyto!`. Saves the
`O(new_n)` inner loop per element; meaningful on small contexts and
asymptotically free on large ones (bandwidth-bound).
"""
function _compact_scatter!(new_orkan::OrkanState, old_orkan::OrkanState, plan::CompactPlan)
    old_dim = 1 << plan.old_n
    new_dim = 1 << plan.new_n
    old_amps = unsafe_wrap(Array{ComplexF64,1}, old_orkan.raw.data, old_dim)
    new_amps = unsafe_wrap(Array{ComplexF64,1}, new_orkan.raw.data, new_dim)
    live_slots = plan.old_slots
    new_n = plan.new_n
    # Contiguous-live fast path: if every live wire is already at slot k
    # for k in 0..new_n-1, bit-expand is identity. Detection is a single
    # vector-vs-range elementwise comparison — no allocation.
    if live_slots == 0:new_n - 1
        unsafe_copyto!(new_amps, 1, old_amps, 1, new_dim)
        return nothing
    end
    @inbounds for j in 0:new_dim - 1
        old_index = 0
        for k in 0:new_n - 1
            bit = (j >> k) & 1
            old_slot = live_slots[k + 1]
            old_index |= bit << old_slot
        end
        new_amps[j + 1] = old_amps[old_index + 1]
    end
    return nothing
end

"""
    compact_state!(ctx::EagerContext) -> ctx

Compact the Orkan PURE statevector by remapping every live wire to a slot
in `0..k-1` (where `k = length(live_wires(ctx))`) and shrinking the
amplitude buffer from `2^n_qubits` to `2^k`. Returns `ctx` (chain-friendly).

# Why
After a burst of `_blessed_measure!`-driven `deallocate!` calls, slots are
returned to `ctx.free_slots` but `ctx.n_qubits` and the Orkan state stay
at the high-water-mark. Every subsequent gate then runs on `2^n_qubits`
amplitudes — even when most slots are recycled. `compact_state!`
projects onto the live tensor factor and rebuilds a contiguous layout,
restoring `O(2^k)` per-gate cost.

See bead Sturm.jl-059 for the empirical motivation (N=15 c_mul=1 Shor
mulmod takes 6.3 minutes wall-clock with a 7-live / 26-allocated state).

# Precondition (CLAUDE.md rule 1: FAIL FAST, FAIL LOUD)
Every slot in `ctx.free_slots` MUST be in |0⟩. This is guaranteed by
`_blessed_measure!`, which performs an amplitude-swap reset before
returning the slot to the free list (eager.jl `measure!`, the
post-collapse swap). `compact_state!` verifies this precondition by
computing the residual norm² over freed bits and `error()`s with a
diagnostic if violated. Verification is mandatory in v0.1; the
`STURM_COMPACT_VERIFY` env-gate is reserved for stage A8 of the bead.

# Postcondition
- `ctx.wire_to_qubit[w]` ∈ `0..k-1` for every live `w`. Wire identity is
  preserved; only the slot index changes.
- `ctx.n_qubits == k`, `ctx.capacity == min(k + GROW_STEP, MAX_QUBITS)`.
- `ctx.free_slots == []`.
- `ctx.consumed`, `ctx.control_stack` unchanged (they store WireIDs, not
  slots, so the remap is transparent to them).
- The new Orkan state's amplitudes are exactly the |0⟩-branch projection
  of the old buffer, permuted into compact layout.

# Atomicity
Compute-then-commit. If any phase throws (input validation, residual
check, OOM during new state allocation, OOB during scatter), `ctx` is
left in its pre-call state. The commit phase is a sequence of infallible
field writes with no intervening fallible calls.

# Idempotence
Calling `compact_state!` when `free_slots` is empty is a fast-path no-op
(returns `ctx` immediately, no allocation, no scatter, no counter bump).

# Complexity
Time `O(2^k · k + 2^old_n)` (the `2^old_n` term is the precondition
scan; can be folded into the scatter in a future optimisation but is
kept separate here for auditability). Memory: one new `OrkanState` of
size `2^k`; the old state is GC'd via finalizer.

# Trigger
`deallocate!` calls `compact_state!` automatically when
`length(free_slots) >= 2 * GROW_STEP`, calibrated against Bennett's
K-ancilla burst pattern (K up to ~7 per `apply_reversible!` should not
fire mid-burst; compaction triggers only across wider library
boundaries). Manual invocation is supported and idempotent.

# Worked example
`n_qubits=4`, `free_slots=[1,3]`, live wires at slots `[0,2]`. Old
amplitudes (precondition: bits 1 and 3 must be 0):
    amps[0b0000] = α    amps[0b0100] = β    (others ≈ 0)
After compact, live_wires gets new slots `[0, 1]`. For each new index j:
    j = 0b00 → bit 0 = 0 → old_index = 0       → new_amps[1] = α
    j = 0b01 → bit 0 = 1 at old_slot 0 → old_index = 1   → new_amps[2] = old_amps[2]  (≈ 0)
    j = 0b10 → bit 1 = 1 at old_slot 2 → old_index = 4   → new_amps[3] = β
    j = 0b11 → bits at old slots 0,2   → old_index = 5   → new_amps[4] = old_amps[6] (≈ 0)

# See also
Bead Sturm.jl-059 (root cause + design history). The `AbstractContext`
default is a no-op (see `src/context/abstract.jl`).
"""
function compact_state!(ctx::EagerContext)
    # Phase 1+2 — read-only validation + precondition verification.
    plan = _compact_plan(ctx)
    plan === nothing && return ctx     # fast-path no-op
    _compact_verify_freed_zero(ctx, plan)

    # Phase 3 — build new state. May throw on OOM; if so, ctx is unchanged
    # and `new_orkan` is dropped (finalizer reclaims the C buffer).
    new_orkan = OrkanState(ORKAN_PURE, plan.new_capacity)
    _compact_scatter!(new_orkan, ctx.orkan, plan)

    # Pre-build the new wire_to_qubit so Phase 4 has only infallible writes.
    new_w2q = Dict{WireID, Int}()
    for (k, w) in enumerate(plan.live_wires)
        new_w2q[w] = k - 1
    end

    # Snapshot pre-commit capacity so we can decide afterwards whether the
    # released old Orkan buffer is large enough to be worth a GC pass.
    old_capacity = ctx.capacity

    # Phase 4 — atomic commit. No fallible calls between assignments;
    # Julia field assignment on a mutable struct cannot throw.
    ctx.orkan = new_orkan
    ctx.capacity = plan.new_capacity
    ctx.n_qubits = plan.new_n
    ctx.wire_to_qubit = new_w2q
    empty!(ctx.free_slots)
    ctx._compact_count += 1

    # If the released buffer was big (≥256 MiB at 24 qubits) force an
    # incremental GC pass so its finalizer runs and the C heap is freed
    # before the next `_grow_state!`. Otherwise transient memory peak
    # would be (old big buffer) + (new grown buffer) at the next grow.
    # For small states the GC pass is more expensive than the saved
    # memory and slows tight loops; skip it.
    if old_capacity >= 24
        GC.gc(false)
    end
    return ctx
end

"""Deallocate a wire: measure it (discarding result) and recycle the slot.

After the slot lands in `free_slots`, fire `compact_state!` if enough slots
have accumulated to make compaction worthwhile (bead Sturm.jl-059). The
threshold `2 * GROW_STEP` (= 8 with GROW_STEP=4) is calibrated against
typical alloc/dealloc patterns: small enough to fire on a `ptrace!(q::QInt)`
that releases ~5+ wires (capturing the per-iter cleanup in
`_pep_mod_iter!`), while the cap-delta hysteresis in `compact_state!`
bounds the resulting capacity-shrink-then-grow cycle to two GROW_STEPs at a
time, keeping transient memory pressure within the half-RAM check in
`_grow_state!` even on memory-constrained machines (~10 GiB free).
"""
function deallocate!(ctx::EagerContext, wire::WireID)
    wire in ctx.consumed && error("Wire $wire already consumed")
    # Partial trace = measure-and-discard. measure! handles collapse + recycle.
    # Blessed: this is the P2-blessed partial-trace path used by ptrace!(q).
    _blessed_measure!(ctx, wire)
    if length(ctx.free_slots) >= 2 * GROW_STEP
        compact_state!(ctx)
    end
    return nothing
end

live_wires(ctx::EagerContext) = collect(keys(ctx.wire_to_qubit))

# ── Wire → qubit resolution ──────────────────────────────────────────────────

function _resolve(ctx::EagerContext, wire::WireID)::UInt8
    wire in ctx.consumed && error("Linear resource violation: wire $wire already consumed")
    haskey(ctx.wire_to_qubit, wire) || error("Wire $wire not found in context")
    return UInt8(ctx.wire_to_qubit[wire])
end

# ── Control stack ─────────────────────────────────────────────────────────────

function push_control!(ctx::EagerContext, wire::WireID)
    _resolve(ctx, wire)
    push!(ctx.control_stack, wire)
end

function pop_control!(ctx::EagerContext)
    isempty(ctx.control_stack) && error("Control stack underflow")
    pop!(ctx.control_stack)
end

current_controls(ctx::EagerContext) = copy(ctx.control_stack)

# ── Gate application ──────────────────────────────────────────────────────────

function apply_ry!(ctx::EagerContext, wire::WireID, angle::Real)
    target = _resolve(ctx, wire)
    nc = length(ctx.control_stack)
    if nc == 0
        orkan_ry!(ctx.orkan.raw, target, angle)
    elseif nc == 1
        _controlled_ry!(ctx, ctx.control_stack[1], wire, angle)
    else
        _multi_controlled_gate!(ctx, wire, angle, _controlled_ry!)
    end
end

function apply_rz!(ctx::EagerContext, wire::WireID, angle::Real)
    target = _resolve(ctx, wire)
    nc = length(ctx.control_stack)
    if nc == 0
        orkan_rz!(ctx.orkan.raw, target, angle)
    elseif nc == 1
        _controlled_rz!(ctx, ctx.control_stack[1], wire, angle)
    else
        _multi_controlled_gate!(ctx, wire, angle, _controlled_rz!)
    end
end

function apply_cx!(ctx::EagerContext, control_wire::WireID, target_wire::WireID)
    ctrl = _resolve(ctx, control_wire)
    tgt = _resolve(ctx, target_wire)
    nc = length(ctx.control_stack)
    if nc == 0
        orkan_cx!(ctx.orkan.raw, ctrl, tgt)
    elseif nc == 1
        extra_ctrl = _resolve(ctx, ctx.control_stack[1])
        orkan_ccx!(ctx.orkan.raw, extra_ctrl, ctrl, tgt)
    else
        # Multi-controlled CX: AND-reduce stack controls into workspace,
        # then CCX(workspace, cx_ctrl, target).
        _multi_controlled_cx!(ctx, control_wire, target_wire)
    end
end

function apply_ccx!(ctx::EagerContext, c1::WireID, c2::WireID, target::WireID)
    q1 = _resolve(ctx, c1)
    q2 = _resolve(ctx, c2)
    qt = _resolve(ctx, target)
    nc = length(ctx.control_stack)
    if nc == 0
        # Fast path: direct CCX, no control stack overhead
        orkan_ccx!(ctx.orkan.raw, q1, q2, qt)
    else
        # CCX inside when(): treat as CX(c2, target) with extra control c1
        push!(ctx.control_stack, c1)
        try
            _multi_controlled_cx!(ctx, c2, target)
        finally
            pop!(ctx.control_stack)
        end
    end
end

# ── Controlled rotation + Toffoli cascade helpers live in multi_control.jl ───
#   (shared with DensityMatrixContext; included after both context types are
#   defined so the `Union{EagerContext, DensityMatrixContext}` type resolves).

# ── Measurement with qubit recycling ──────────────────────────────────────────

"""
    measure!(ctx::EagerContext, wire::WireID) -> Bool

Measure a single qubit:
1. Compute marginal probability of qubit being |1>
2. Sample outcome
3. Collapse state (project + renormalize)
4. Reset qubit to |0> and recycle the slot
"""
function measure!(ctx::EagerContext, wire::WireID)::Bool
    _warn_direct_measure()   # P2 antipattern warning, suppressed inside Bool/Int casts
    qubit = _resolve(ctx, wire)
    dim = 1 << ctx.n_qubits
    mask = 1 << qubit

    # Zero-copy view of the Orkan PURE-state amplitude buffer as a Julia
    # Vector{ComplexF64}. Avoids 2^n FFI crossings per measurement — those
    # per-element `orkan_state_get` calls dominated the cost at 20+ qubits
    # (~100ms per measure vs ~1ms expected), blowing up
    # _shor_mulmod_E_controlled! to 7–20 min per call (bead Sturm.jl-059).
    #
    # Safety: valid for the duration of this function only — `amps` aliases
    # Orkan's internal buffer. No gate or allocation happens between
    # unsafe_wrap and the last access, so the pointer stays live.
    amps = unsafe_wrap(Array{ComplexF64,1}, ctx.orkan.raw.data, dim)

    # Compute P(|1>)
    p1 = 0.0
    @inbounds for i in 0:dim-1
        if (i & mask) != 0
            p1 += abs2(amps[i + 1])
        end
    end

    # Sample
    outcome = rand() < p1

    # Collapse: zero out inconsistent amplitudes, renormalize
    norm_sq = 0.0
    @inbounds for i in 0:dim-1
        bit_set = (i & mask) != 0
        if bit_set != outcome
            amps[i + 1] = 0.0 + 0.0im
        else
            norm_sq += abs2(amps[i + 1])
        end
    end

    if norm_sq > 0
        factor = 1.0 / sqrt(norm_sq)
        @inbounds for i in 0:dim-1
            amp = amps[i + 1]
            if abs2(amp) > 0
                amps[i + 1] = amp * factor
            end
        end
    end

    # Reset qubit to |0> by swapping amplitudes so the measured bit is 0.
    # If outcome was |1>, we need to move all surviving amplitudes from
    # bit=1 positions to bit=0 positions (effectively applying X to this qubit).
    if outcome
        @inbounds for i in 0:dim-1
            if (i & mask) == 0
                # Swap (i, i|mask): surviving amps are at i|mask, move to i
                j = i | mask
                amps[i + 1] = amps[j + 1]
                amps[j + 1] = 0.0 + 0.0im
            end
        end
    end

    # Recycle: mark consumed, return slot to free list
    push!(ctx.consumed, wire)
    delete!(ctx.wire_to_qubit, wire)
    push!(ctx.free_slots, Int(qubit))

    return outcome
end
