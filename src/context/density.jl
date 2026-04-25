"""
    DensityMatrixContext

Executes quantum operations via Orkan's density matrix backend (MIXED_PACKED).
Supports noise channels (depolarise, dephase, amplitude_damp) that require
the full density matrix representation.

Same interface as EagerContext but uses ρ (density matrix) instead of |ψ⟩.
Orkan gate functions dispatch internally on state type — same gate call
works for both PURE and MIXED states.

`_compact_count` (bead Sturm.jl-amc) is incremented on each successful
`compact_state!` commit, mirroring `EagerContext`. Used by the auto-trigger
test scaffold and as a debugging hook.
"""
mutable struct DensityMatrixContext <: AbstractContext
    orkan::OrkanState
    n_qubits::Int
    wire_to_qubit::Dict{WireID, Int}
    consumed::Set{WireID}
    control_stack::Vector{WireID}
    capacity::Int
    free_slots::Vector{Int}
    _compact_count::Int

    function DensityMatrixContext(; capacity::Int=8)
        capacity > MAX_QUBITS && error(
            "DensityMatrixContext: initial capacity $capacity exceeds MAX_QUBITS ($MAX_QUBITS)"
        )
        orkan = OrkanState(ORKAN_MIXED_PACKED, capacity)
        # Initialise ρ = |0⟩⟨0| ⊗ ... ⊗ |0⟩⟨0|: ρ[0,0] = 1
        orkan[0, 0] = 1.0 + 0.0im
        new(orkan, 0, Dict{WireID, Int}(), Set{WireID}(), WireID[], capacity, Int[], 0)
    end
end

# ── Packed-buffer index helpers (mirror Orkan's index.h) ─────────────────────
#
# MIXED_PACKED is LAPACK 'L' lower-triangle column-major packed format. For a
# `dim × dim` Hermitian matrix with `dim = 2^n`, only entries `(r, c)` with
# `r ≥ c` are stored, in column order. Buffer length is `dim*(dim+1)/2`. The
# upper triangle is the conjugate of the lower; Orkan handles that in
# `state_packed_get`. These helpers stay in the lower triangle by
# construction — never call them with `r < c`.

@inline _dm_packed_len(dim::Int) = (dim * (dim + 1)) ÷ 2
@inline _dm_col_off(dim::Int, c::Int) = (c * (2 * dim - c + 1)) ÷ 2
@inline _dm_pack_idx(dim::Int, r::Int, c::Int) = _dm_col_off(dim, c) + (r - c)

# ── Qubit allocation (mirrors EagerContext) ──────────────────────────────────

function allocate!(ctx::DensityMatrixContext)::WireID
    wire = fresh_wire!()
    if !isempty(ctx.free_slots)
        qubit_idx = pop!(ctx.free_slots)
        ctx.wire_to_qubit[wire] = qubit_idx
        return wire
    end
    if ctx.n_qubits >= ctx.capacity
        _grow_density_state!(ctx)
    end
    qubit_idx = ctx.n_qubits
    ctx.wire_to_qubit[wire] = qubit_idx
    ctx.n_qubits += 1
    return wire
end

"""
    _grow_density_state!(ctx::DensityMatrixContext)

Grow the MIXED_PACKED Orkan state by GROW_STEP qubits. The old ρ is embedded
in the top-left `old_dim × old_dim` block of the new buffer; entries beyond
that (rows/cols indexed by the new qubits) stay zero — the new qubits are in
|0⟩⟨0| by construction.

# Implementation
The packed buffer is column-major lower-triangular. Column `c` of the old
matrix has length `old_dim - c`; column `c` of the new matrix has length
`new_dim - c`. The column **offsets** differ between old and new because
`col_off(dim, c) = c*(2*dim - c + 1)/2` depends on `dim`. A single bulk
`unsafe_copyto!` of the whole old buffer would misroute every column except
column 0. Instead we copy column-by-column (one `unsafe_copyto!` per old
column), which is `old_dim` Julia memcopies and zero FFI crossings — the
old per-element `state_packed_set` path made `4^old_cap` ccalls (bead
Sturm.jl-amc, mirroring the eager fix in bead Sturm.jl-059).
"""
function _grow_density_state!(ctx::DensityMatrixContext)
    old_cap = ctx.capacity
    new_cap = old_cap + GROW_STEP
    new_cap > MAX_QUBITS && error(
        "DensityMatrixContext: capacity would grow to $new_cap qubits, exceeds MAX_QUBITS ($MAX_QUBITS)"
    )
    old_dim = 1 << old_cap
    new_dim = 1 << new_cap
    old_buf_len = _dm_packed_len(old_dim)
    new_buf_len = _dm_packed_len(new_dim)
    new_orkan = OrkanState(ORKAN_MIXED_PACKED, new_cap)
    old_buf = unsafe_wrap(Array{ComplexF64,1}, ctx.orkan.raw.data, old_buf_len)
    new_buf = unsafe_wrap(Array{ComplexF64,1}, new_orkan.raw.data, new_buf_len)
    @inbounds for c in 0:old_dim - 1
        old_start = _dm_col_off(old_dim, c) + 1   # 1-indexed for Julia
        new_start = _dm_col_off(new_dim, c) + 1
        strip_len = old_dim - c                    # entries in old column c
        unsafe_copyto!(new_buf, new_start, old_buf, old_start, strip_len)
        # Tail rows [old_dim, new_dim) of the new column stay zero (state_init
        # zeroed the whole buffer), which is correct: the new qubits are |0⟩.
    end
    # Columns [old_dim, new_dim) of the new buffer are entirely zero already.
    ctx.orkan = new_orkan
    ctx.capacity = new_cap
end

# ── State compaction (bead Sturm.jl-amc, mirror of Sturm.jl-059) ─────────────
#
# `n_qubits` and the Orkan state grow monotonically. After a burst of
# `_blessed_measure!`-driven `deallocate!` calls (the same Bennett ancilla
# cleanup pattern that motivated the pure-state fix), `free_slots`
# accumulates and `n_qubits` stays at its peak. Every subsequent gate then
# operates on the full `2^(2·n_qubits)` packed buffer regardless of how few
# wires are actually live. `compact_state!` reclaims the wasted dimension by
# projecting onto the |0⟩ branch of every freed slot in BOTH the row and
# column index — strictly stronger than the pure-state |0⟩ projection, which
# only hits the amplitude vector.
#
# Soundness: after `_blessed_measure!`, the freed slot satisfies
# `ρ[r, c] = 0 whenever (r & (1<<s)) != 0 OR (c & (1<<s)) != 0`. The pre-
# condition scan in `_compact_verify_freed_zero` walks the stored lower
# triangle and sums |ρ[r,c]|² over entries violating that rule. By
# Hermiticity, every upper-triangle violation has an equal-modulus partner
# in the lower triangle, so a lower-triangle scan is complete (no
# double-counting needed; the tolerance is for stored elements).
#
# Architecture: same compute-then-commit shape as EagerContext. Phase 1
# reads ctx only (delegated to `_compact_plan_impl`); Phase 2 verifies the
# DM-specific residual; Phase 3 builds the new packed buffer on the side
# via `_compact_scatter_dm!`; Phase 4 commits via infallible field writes.

"""
    _compact_plan(ctx::DensityMatrixContext) -> Union{Nothing, CompactPlan}

Validate `ctx` invariants and return a plan. Returns `nothing` if
`free_slots` is empty (fast-path no-op). Same logic as the EagerContext
plan — both contexts share the same meta layout — and reuses
`_compact_plan_impl`. Errors loud on every invariant violation with the
standard "compact_state!: ..." message prefix.
"""
_compact_plan(ctx::DensityMatrixContext) = _compact_plan_impl(
    ctx.n_qubits, ctx.capacity, ctx.free_slots, ctx.wire_to_qubit, ctx.consumed)

"""
    _compact_verify_freed_zero(ctx::DensityMatrixContext, plan) -> nothing

Verify the DM-specific soundness precondition: every entry of ρ in a freed
row OR column is zero. Computed as the sum of |ρ[r,c]|² over the stored
lower-triangle entries (r ≥ c) where `(r | c) & freed_mask != 0`. Errors
loud if above tolerance. CLAUDE.md rule 1.

# Why scanning the lower triangle is sufficient
By Hermiticity, ρ[r,c] = conj(ρ[c,r]), so |ρ[r,c]|² = |ρ[c,r]|² for r≠c.
Every upper-triangle violation has an equal-modulus lower-triangle
partner, and the diagonal is invariant. A genuine reset failure leaves
residual ≥ ~1/(2^n) in stored entries, which is many orders of magnitude
above the floating-point tolerance even at n=20.

# Tolerance
`1e-10 * max(1, n_freed)` — same shape as the eager check. The DM gate
sequences accumulate noise as `eps() · O(2^(2n))` per stored element, but
the gap to a real violation is still huge (~1/(2^n) vs ~eps()·G·2^(2n)).
"""
function _compact_verify_freed_zero(ctx::DensityMatrixContext, plan::CompactPlan)
    # bead Sturm.jl-179: env-gated. When `STURM_COMPACT_VERIFY=0` the scan
    # is skipped. Default is on (fail-loud).
    _COMPACT_VERIFY_ENABLED[] || return nothing
    # The Orkan packed buffer is laid out for `state->qubits = ctx.capacity`,
    # NOT for the live `n_qubits`. Packed indices use the buffer's dim
    # `cap_dim = 2^capacity` (not `2^n_qubits`) — `_dm_col_off(d, c)` depends
    # on `d`. Iterating only over the live block `[0, 2^old_n)` is sufficient
    # because state_init zeros every entry and gates only touch the live
    # region; entries outside the live block are guaranteed zero.
    cap_dim = 1 << ctx.capacity
    live_dim = 1 << plan.old_n
    buf = unsafe_wrap(Array{ComplexF64,1}, ctx.orkan.raw.data, _dm_packed_len(cap_dim))
    mask = plan.freed_mask
    residual = 0.0
    @inbounds for c in 0:live_dim - 1
        col_off = _dm_col_off(cap_dim, c)
        col_freed = (UInt64(c) & mask) != 0
        col_len = live_dim - c
        if col_freed
            # Whole live-block strip must be zero: every entry has c-bit in freed_mask.
            for offset in 0:col_len - 1
                residual += abs2(buf[col_off + offset + 1])
            end
        else
            # Column is live; only rows where r has a freed bit violate.
            for offset in 0:col_len - 1
                r = c + offset
                if (UInt64(r) & mask) != 0
                    residual += abs2(buf[col_off + offset + 1])
                end
            end
        end
    end
    n_freed = count_ones(plan.freed_mask)
    tol = 1e-10 * max(1.0, Float64(n_freed))
    if residual > tol
        error("compact_state! (DensityMatrixContext): precondition violated — freed slots are not |0⟩.\n" *
              "  residual |ρ|² over freed rows/cols (lower triangle of live block) = $(residual) (tolerance = $(tol))\n" *
              "  free_slots     = $(ctx.free_slots)\n" *
              "  n_qubits       = $(plan.old_n), capacity = $(ctx.capacity), buffer dim = $(cap_dim)\n" *
              "A slot was returned to free_slots without being reset to |0⟩. The\n" *
              "deallocate path MUST go through _blessed_measure!. See bead Sturm.jl-amc.")
    end
    return nothing
end

"""
    _compact_scatter_dm!(new_orkan, old_orkan, plan) -> nothing

Project the old packed buffer onto the |0⟩ branch of every freed slot (in
both the row and column index) and copy into the new packed buffer in
compact layout. Outer loop over `c_new` in `[0, new_n_dim)`, inner loop
over `r_new` in `[c_new, new_n_dim)` — covering exactly the lower triangle
of the new live block.

# Buffer-vs-live dim
Both Orkan states are laid out for their `state->qubits = capacity`, NOT
for the live `n_qubits`. The scatter writes lower-triangle entries of the
LIVE block `[0, 2^new_n)²` into the new buffer using **capacity**-dim
packed indices; entries outside the live block stay zero from
`state_init`. Reads from the old buffer use the OLD capacity dim. This is
the same `col_off`-shifts-with-dim trap as in `_grow_density_state!`.

For each `(r_new, c_new)`:
  - decode `c_old = bit_expand(c_new, live_slots)` once per outer iteration
  - decode `r_old = bit_expand(r_new, live_slots)`
  - read `old_buf[pack_idx(old_cap_dim, r_old, c_old) + 1]` — guaranteed
    to land in the lower triangle because `live_slots` is sorted
    ascending, so bit-expand is monotone (`r_new ≥ c_new ⟹ r_old ≥ c_old`)
  - write to `new_buf[pack_idx(new_cap_dim, r_new, c_new) + 1]`

Cost: `O(2^(2·new_n) · new_n)` (live-block lower-triangle × per-element
bit-expansion). Auditable, no clever bit tricks.
"""
function _compact_scatter_dm!(new_orkan::OrkanState, old_orkan::OrkanState, plan::CompactPlan)
    old_cap_dim = 1 << Int(old_orkan.raw.qubits)
    new_cap_dim = 1 << Int(new_orkan.raw.qubits)
    new_n_dim = 1 << plan.new_n
    old_buf = unsafe_wrap(Array{ComplexF64,1}, old_orkan.raw.data, _dm_packed_len(old_cap_dim))
    new_buf = unsafe_wrap(Array{ComplexF64,1}, new_orkan.raw.data, _dm_packed_len(new_cap_dim))
    live_slots = plan.old_slots
    new_n = plan.new_n
    @inbounds for c_new in 0:new_n_dim - 1
        # Bit-expand c_new into c_old via the live-slot map.
        c_old = 0
        for k in 0:new_n - 1
            bit = (c_new >> k) & 1
            c_old |= bit << live_slots[k + 1]
        end
        new_col_off = _dm_col_off(new_cap_dim, c_new)
        old_col_off = _dm_col_off(old_cap_dim, c_old)
        col_len = new_n_dim - c_new   # active rows of this column in the new live block
        for offset in 0:col_len - 1
            r_new = c_new + offset
            r_old = 0
            for k in 0:new_n - 1
                bit = (r_new >> k) & 1
                r_old |= bit << live_slots[k + 1]
            end
            new_buf[new_col_off + offset + 1] = old_buf[old_col_off + (r_old - c_old) + 1]
        end
    end
    return nothing
end

"""
    compact_state!(ctx::DensityMatrixContext) -> ctx

Compact the MIXED_PACKED density matrix by remapping every live wire to a
slot in `0..k-1` (where `k = length(live_wires(ctx))`) and shrinking the
packed buffer from `2^old_n × 2^old_n` to `2^k × 2^k` (lower triangle
stored). Returns `ctx` (chain-friendly).

# Why
After a burst of `_blessed_measure!`-driven `deallocate!` calls, slots are
returned to `ctx.free_slots` but `ctx.n_qubits` stays at its peak. Every
subsequent gate runs on `2^(2·n_qubits)` matrix elements — even when most
slots are recycled. `compact_state!` projects onto the live tensor factor
and rebuilds a contiguous layout, restoring `O(4^k)` per-gate cost. See
bead Sturm.jl-amc (mirror of Sturm.jl-059).

# Precondition (CLAUDE.md rule 1: FAIL FAST, FAIL LOUD)
Every entry `ρ[r, c]` with the freed bit set in EITHER `r` OR `c` must be
zero. This is guaranteed by `_blessed_measure!` (the projective collapse
followed by the swap-to-|0⟩ reset). `compact_state!` verifies the
precondition by summing `|ρ[r,c]|²` over all stored lower-triangle entries
where `(r | c) & freed_mask != 0`, and `error()`s with a diagnostic if
above tolerance.

# Postcondition
- `ctx.wire_to_qubit[w]` ∈ `0..k-1` for every live `w`. Wire identity
  preserved; only the slot index changes.
- `ctx.n_qubits == k`, `ctx.capacity == hysteresis(old_capacity, k)`.
- `ctx.free_slots == []`.
- `ctx.consumed`, `ctx.control_stack` unchanged.
- `ρ_new[r_new, c_new] == ρ_old[expand(r_new), expand(c_new)]` for every
  `(r_new, c_new)`, where `expand` places bit `k` at `live_slots[k+1]`.
- `Tr(ρ_new) == Tr(ρ_old) == 1` — the trace is preserved because all
  population was already on the live |0⟩-branch by precondition.

# Atomicity
Compute-then-commit. If any phase throws (input validation, precondition
check, OOM during new state allocation), `ctx` is left in its pre-call
state. Phase 4 is a sequence of infallible mutable-struct field writes.

# Idempotence
Calling `compact_state!` when `free_slots` is empty is a fast-path no-op.

# Trigger
`deallocate!(::DensityMatrixContext, ...)` calls `compact_state!`
automatically when `length(free_slots) >= 2 * GROW_STEP`, identical to the
eager threshold (calibrated against Bennett's typical K-ancilla burst).

# Complexity
Time `O(2^(2·old_n) + 2^(2·new_n) · new_n)` — the first term is the
precondition scan (full old packed buffer), the second is the scatter.
Memory: one new `OrkanState` of packed length `2^new_n*(2^new_n+1)/2`.
"""
function compact_state!(ctx::DensityMatrixContext)
    # Phase 1+2 — read-only validation + precondition verification.
    plan = _compact_plan(ctx)
    plan === nothing && return ctx     # fast-path no-op
    _compact_verify_freed_zero(ctx, plan)

    # Phase 3 — build new state. May throw on OOM; if so, ctx is unchanged
    # and `new_orkan` is dropped (finalizer reclaims the C buffer).
    new_orkan = OrkanState(ORKAN_MIXED_PACKED, plan.new_capacity)
    _compact_scatter_dm!(new_orkan, ctx.orkan, plan)

    # Pre-build the new wire_to_qubit so Phase 4 has only infallible writes.
    new_w2q = Dict{WireID, Int}()
    for (k, w) in enumerate(plan.live_wires)
        new_w2q[w] = k - 1
    end

    # Snapshot pre-commit capacity for the GC heuristic.
    old_capacity = ctx.capacity

    # Phase 4 — atomic commit. Mutable-struct field assignment is infallible.
    ctx.orkan = new_orkan
    ctx.capacity = plan.new_capacity
    ctx.n_qubits = plan.new_n
    ctx.wire_to_qubit = new_w2q
    empty!(ctx.free_slots)
    ctx._compact_count += 1

    # GC hint at lower threshold than eager: the DM packed buffer scales as
    # 4^cap, so a "big enough buffer to be worth a GC pass" is reached much
    # earlier. At cap=12 the released buffer is ~134 MiB; at cap=14 it is
    # ~2 GiB. Below cap=12 the GC pause cost dominates the saved memory.
    if old_capacity >= 12
        GC.gc(false)
    end
    return ctx
end

"""Deallocate a wire: measure it (discarding result) and recycle the slot.

Mirrors the eager auto-trigger pattern (bead Sturm.jl-059): when enough
slots have accumulated in `free_slots`, fire `compact_state!` to reclaim
the dimension. Threshold `2 * GROW_STEP = 8` — same as eager, calibrated
against Bennett's K-ancilla burst pattern.
"""
function deallocate!(ctx::DensityMatrixContext, wire::WireID)
    wire in ctx.consumed && error("Wire $wire already consumed")
    # Partial trace = measure-and-discard. Blessed P2 path (used by ptrace!).
    _blessed_measure!(ctx, wire)
    if length(ctx.free_slots) >= 2 * GROW_STEP
        compact_state!(ctx)
    end
    return nothing
end

live_wires(ctx::DensityMatrixContext) = collect(keys(ctx.wire_to_qubit))

# ── Wire resolution ──────────────────────────────────────────────────────────

function _resolve(ctx::DensityMatrixContext, wire::WireID)::UInt8
    wire in ctx.consumed && error("Linear resource violation: wire $wire already consumed")
    haskey(ctx.wire_to_qubit, wire) || error("Wire $wire not found in context")
    return UInt8(ctx.wire_to_qubit[wire])
end

# ── Control stack ────────────────────────────────────────────────────────────

function push_control!(ctx::DensityMatrixContext, wire::WireID)
    _resolve(ctx, wire)
    push!(ctx.control_stack, wire)
end

function pop_control!(ctx::DensityMatrixContext)
    isempty(ctx.control_stack) && error("Control stack underflow")
    pop!(ctx.control_stack)
end

current_controls(ctx::DensityMatrixContext) = copy(ctx.control_stack)

# ── Gate application (delegates to Orkan, same as EagerContext) ──────────────

# Dispatch shape mirrors EagerContext exactly — Orkan's gate ABI dispatches
# internally on state type, so the same nc=0/1/≥2 tree works for MIXED_PACKED.
# Multi-control (nc ≥ 2) uses the shared Toffoli cascade in multi_control.jl.

function apply_ry!(ctx::DensityMatrixContext, wire::WireID, angle::Real)
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

function apply_rz!(ctx::DensityMatrixContext, wire::WireID, angle::Real)
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

function apply_cx!(ctx::DensityMatrixContext, control_wire::WireID, target_wire::WireID)
    ctrl = _resolve(ctx, control_wire)
    tgt  = _resolve(ctx, target_wire)
    nc = length(ctx.control_stack)
    if nc == 0
        orkan_cx!(ctx.orkan.raw, ctrl, tgt)
    elseif nc == 1
        extra_ctrl = _resolve(ctx, ctx.control_stack[1])
        orkan_ccx!(ctx.orkan.raw, extra_ctrl, ctrl, tgt)
    else
        _multi_controlled_cx!(ctx, control_wire, target_wire)
    end
end

function apply_ccx!(ctx::DensityMatrixContext, c1::WireID, c2::WireID, target::WireID)
    q1 = _resolve(ctx, c1)
    q2 = _resolve(ctx, c2)
    qt = _resolve(ctx, target)
    nc = length(ctx.control_stack)
    if nc == 0
        orkan_ccx!(ctx.orkan.raw, q1, q2, qt)
    else
        # CCX inside when(): treat c2 as the cx-control and c1 as one more
        # stack control, then run the generic multi-control CX path.
        push!(ctx.control_stack, c1)
        try
            _multi_controlled_cx!(ctx, c2, target)
        finally
            pop!(ctx.control_stack)
        end
    end
end

# ── Measurement for density matrix ───────────────────────────────────────────

"""
    measure!(ctx::DensityMatrixContext, wire::WireID) -> Bool

Measure a single qubit from the density matrix:
1. Compute P(|1⟩) from diagonal elements of ρ
2. Sample outcome
3. Project: apply Kraus operator |outcome⟩⟨outcome| and renormalize trace
4. Reset qubit to |0⟩ and recycle slot
"""
function measure!(ctx::DensityMatrixContext, wire::WireID)::Bool
    _warn_direct_measure()   # P2 antipattern warning, suppressed inside Bool/Int casts
    qubit = _resolve(ctx, wire)
    dim = 1 << ctx.n_qubits
    mask = 1 << qubit

    # Compute P(|1⟩) from diagonal of ρ
    p1 = 0.0
    for i in 0:dim-1
        if (i & mask) != 0
            p1 += real(ctx.orkan[i, i])
        end
    end

    outcome = rand() < p1

    # Project: zero out rows/cols inconsistent with outcome, renormalize
    for r in 0:dim-1
        for c in 0:dim-1
            r_bit = (r & mask) != 0
            c_bit = (c & mask) != 0
            if r_bit != outcome || c_bit != outcome
                ctx.orkan[r, c] = 0.0 + 0.0im
            end
        end
    end

    # Renormalize trace to 1
    trace = 0.0
    for i in 0:dim-1
        trace += real(ctx.orkan[i, i])
    end
    if trace > 0
        factor = 1.0 / trace
        for r in 0:dim-1
            for c in 0:dim-1
                val = ctx.orkan[r, c]
                if abs2(val) > 0
                    ctx.orkan[r, c] = val * factor
                end
            end
        end
    end

    # Reset qubit to |0⟩ if outcome was |1⟩
    if outcome
        for r in 0:dim-1
            for c in 0:dim-1
                if (r & mask) == 0
                    j_r = r | mask
                    j_c = c | mask
                    ctx.orkan[r, c] = ctx.orkan[j_r, j_c]
                    ctx.orkan[j_r, j_c] = 0.0 + 0.0im
                    # Also handle the cross terms
                    if (c & mask) == 0
                        ctx.orkan[r, c | mask] = 0.0 + 0.0im
                    end
                end
            end
        end
    end

    # Recycle
    push!(ctx.consumed, wire)
    delete!(ctx.wire_to_qubit, wire)
    push!(ctx.free_slots, Int(qubit))

    return outcome
end
