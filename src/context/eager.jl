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

    function EagerContext(; capacity::Int=8)
        orkan = OrkanState(ORKAN_PURE, capacity)
        orkan[0] = 1.0 + 0.0im
        new(orkan, 0, Dict{WireID, Int}(), Set{WireID}(), WireID[], capacity, Int[])
    end
end

# ── Qubit allocation ──────────────────────────────────────────────────────────

function allocate!(ctx::EagerContext)::WireID
    wire = fresh_wire!()

    if !isempty(ctx.free_slots)
        # Reuse a recycled slot — it's already in |0>
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
    return wire
end

"""Double the Orkan state capacity by tensoring with |0...0>."""
function _grow_state!(ctx::EagerContext)
    old_cap = ctx.capacity
    new_cap = old_cap * 2
    old_dim = 1 << old_cap

    new_orkan = OrkanState(ORKAN_PURE, new_cap)
    for i in 0:old_dim-1
        new_orkan[i] = ctx.orkan[i]
    end

    ctx.orkan = new_orkan
    ctx.capacity = new_cap
end

"""Deallocate a wire: measure it (discarding result) and recycle the slot."""
function deallocate!(ctx::EagerContext, wire::WireID)
    wire in ctx.consumed && error("Wire $wire already consumed")
    # Measure to collapse, then recycle — measure! handles everything
    measure!(ctx, wire)
end

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
    if isempty(ctx.control_stack)
        orkan_ry!(ctx.orkan.raw, target, angle)
    elseif length(ctx.control_stack) == 1
        _controlled_ry!(ctx, ctx.control_stack[1], wire, angle)
    else
        error("Multi-controlled Ry (>1 control) not yet implemented")
    end
end

function apply_rz!(ctx::EagerContext, wire::WireID, angle::Real)
    target = _resolve(ctx, wire)
    if isempty(ctx.control_stack)
        orkan_rz!(ctx.orkan.raw, target, angle)
    elseif length(ctx.control_stack) == 1
        _controlled_rz!(ctx, ctx.control_stack[1], wire, angle)
    else
        error("Multi-controlled Rz (>1 control) not yet implemented")
    end
end

function apply_cx!(ctx::EagerContext, control_wire::WireID, target_wire::WireID)
    ctrl = _resolve(ctx, control_wire)
    tgt = _resolve(ctx, target_wire)
    if isempty(ctx.control_stack)
        orkan_cx!(ctx.orkan.raw, ctrl, tgt)
    elseif length(ctx.control_stack) == 1
        extra_ctrl = _resolve(ctx, ctx.control_stack[1])
        orkan_ccx!(ctx.orkan.raw, extra_ctrl, ctrl, tgt)
    else
        error("Multi-controlled CX (>1 additional control) not yet implemented")
    end
end

# ── Controlled rotation decompositions ────────────────────────────────────────
# C-Ry(θ) = Ry(θ/2) · CX · Ry(-θ/2) · CX

function _controlled_ry!(ctx::EagerContext, ctrl_wire::WireID, target_wire::WireID, angle::Real)
    ctrl = _resolve(ctx, ctrl_wire)
    tgt = _resolve(ctx, target_wire)
    orkan_ry!(ctx.orkan.raw, tgt, angle / 2)
    orkan_cx!(ctx.orkan.raw, ctrl, tgt)
    orkan_ry!(ctx.orkan.raw, tgt, -angle / 2)
    orkan_cx!(ctx.orkan.raw, ctrl, tgt)
end

# C-Rz(θ) = Rz(θ/2) · CX · Rz(-θ/2) · CX
function _controlled_rz!(ctx::EagerContext, ctrl_wire::WireID, target_wire::WireID, angle::Real)
    ctrl = _resolve(ctx, ctrl_wire)
    tgt = _resolve(ctx, target_wire)
    orkan_rz!(ctx.orkan.raw, tgt, angle / 2)
    orkan_cx!(ctx.orkan.raw, ctrl, tgt)
    orkan_rz!(ctx.orkan.raw, tgt, -angle / 2)
    orkan_cx!(ctx.orkan.raw, ctrl, tgt)
end

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
    qubit = _resolve(ctx, wire)
    dim = 1 << ctx.n_qubits
    mask = 1 << qubit

    # Compute P(|1>)
    p1 = 0.0
    for i in 0:dim-1
        if (i & mask) != 0
            p1 += abs2(ctx.orkan[i])
        end
    end

    # Sample
    outcome = rand() < p1

    # Collapse: zero out inconsistent amplitudes, renormalize
    norm_sq = 0.0
    for i in 0:dim-1
        bit_set = (i & mask) != 0
        if bit_set != outcome
            ctx.orkan[i] = 0.0 + 0.0im
        else
            norm_sq += abs2(ctx.orkan[i])
        end
    end

    if norm_sq > 0
        factor = 1.0 / sqrt(norm_sq)
        for i in 0:dim-1
            amp = ctx.orkan[i]
            if abs2(amp) > 0
                ctx.orkan[i] = amp * factor
            end
        end
    end

    # Reset qubit to |0> by swapping amplitudes so the measured bit is 0.
    # If outcome was |1>, we need to move all surviving amplitudes from
    # bit=1 positions to bit=0 positions (effectively applying X to this qubit).
    if outcome
        for i in 0:dim-1
            if (i & mask) == 0
                # Swap (i, i|mask): surviving amps are at i|mask, move to i
                j = i | mask
                ctx.orkan[i] = ctx.orkan[j]
                ctx.orkan[j] = 0.0 + 0.0im
            end
        end
    end

    # Recycle: mark consumed, return slot to free list
    push!(ctx.consumed, wire)
    delete!(ctx.wire_to_qubit, wire)
    push!(ctx.free_slots, Int(qubit))

    return outcome
end
