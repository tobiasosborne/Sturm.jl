"""
    DensityMatrixContext

Executes quantum operations via Orkan's density matrix backend (MIXED_PACKED).
Supports noise channels (depolarise, dephase, amplitude_damp) that require
the full density matrix representation.

Same interface as EagerContext but uses ρ (density matrix) instead of |ψ⟩.
Orkan gate functions dispatch internally on state type — same gate call
works for both PURE and MIXED states.
"""
mutable struct DensityMatrixContext <: AbstractContext
    orkan::OrkanState
    n_qubits::Int
    wire_to_qubit::Dict{WireID, Int}
    consumed::Set{WireID}
    control_stack::Vector{WireID}
    capacity::Int
    free_slots::Vector{Int}

    function DensityMatrixContext(; capacity::Int=8)
        capacity > MAX_QUBITS && error(
            "DensityMatrixContext: initial capacity $capacity exceeds MAX_QUBITS ($MAX_QUBITS)"
        )
        orkan = OrkanState(ORKAN_MIXED_PACKED, capacity)
        # Initialise ρ = |0⟩⟨0| ⊗ ... ⊗ |0⟩⟨0|: ρ[0,0] = 1
        orkan[0, 0] = 1.0 + 0.0im
        new(orkan, 0, Dict{WireID, Int}(), Set{WireID}(), WireID[], capacity, Int[])
    end
end

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

function _grow_density_state!(ctx::DensityMatrixContext)
    old_cap = ctx.capacity
    new_cap = old_cap + GROW_STEP
    new_cap > MAX_QUBITS && error(
        "DensityMatrixContext: capacity would grow to $new_cap qubits, exceeds MAX_QUBITS ($MAX_QUBITS)"
    )
    # Density matrix growth: new MIXED state, copy old elements
    old_dim = 1 << old_cap
    new_orkan = OrkanState(ORKAN_MIXED_PACKED, new_cap)
    for r in 0:old_dim-1
        for c in 0:old_dim-1
            new_orkan[r, c] = ctx.orkan[r, c]
        end
    end
    ctx.orkan = new_orkan
    ctx.capacity = new_cap
end

function deallocate!(ctx::DensityMatrixContext, wire::WireID)
    wire in ctx.consumed && error("Wire $wire already consumed")
    measure!(ctx, wire)
end

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

function apply_ry!(ctx::DensityMatrixContext, wire::WireID, angle::Real)
    target = _resolve(ctx, wire)
    if isempty(ctx.control_stack)
        orkan_ry!(ctx.orkan.raw, target, angle)
    elseif length(ctx.control_stack) == 1
        ctrl = _resolve(ctx, ctx.control_stack[1])
        tgt = target
        orkan_ry!(ctx.orkan.raw, tgt, angle / 2)
        orkan_cx!(ctx.orkan.raw, ctrl, tgt)
        orkan_ry!(ctx.orkan.raw, tgt, -angle / 2)
        orkan_cx!(ctx.orkan.raw, ctrl, tgt)
    else
        error("Multi-controlled Ry (>1 control) not yet implemented")
    end
end

function apply_rz!(ctx::DensityMatrixContext, wire::WireID, angle::Real)
    target = _resolve(ctx, wire)
    if isempty(ctx.control_stack)
        orkan_rz!(ctx.orkan.raw, target, angle)
    elseif length(ctx.control_stack) == 1
        ctrl = _resolve(ctx, ctx.control_stack[1])
        tgt = target
        orkan_rz!(ctx.orkan.raw, tgt, angle / 2)
        orkan_cx!(ctx.orkan.raw, ctrl, tgt)
        orkan_rz!(ctx.orkan.raw, tgt, -angle / 2)
        orkan_cx!(ctx.orkan.raw, ctrl, tgt)
    else
        error("Multi-controlled Rz (>1 control) not yet implemented")
    end
end

function apply_cx!(ctx::DensityMatrixContext, control_wire::WireID, target_wire::WireID)
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
