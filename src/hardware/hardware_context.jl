# HardwareContext — AbstractContext that batches gates locally and round-trips
# to a backend (real device or IdealisedSimulator) on measurement.
#
# Flush trigger (locked design decision): only on measurement and on close.
# Gates accumulate in `pending`; measure! flushes synchronously and returns the
# Bool from the response. Long classical-only gate sequences cost zero
# round-trips.
#
# Slot management: client-side `free_slots` mirrors the device's free pool so
# we don't need a round-trip per allocate!. `next_slot` walks 0..capacity-1
# for never-used positions; recycled positions come from `free_slots`.
#
# measure! semantics (matches HW4 simulator contract): the device recycles the
# slot on measurement. We mark the wire consumed AND return the slot to
# free_slots immediately; we do NOT queue an extra op_discard.

mutable struct HardwareContext <: AbstractContext
    transport::AbstractTransport
    session_id::String
    capacity::Int

    pending::Vector{ProtocolOp}                # buffered ops, flushed on measure/close
    free_slots::Vector{Int}                    # client-side free pool
    next_slot::Int                             # next never-used slot in [0, capacity)

    wire_to_qubit::Dict{WireID,Int}            # WireID → device qubit index
    consumed::Set{WireID}
    control_stack::Vector{WireID}

    next_measure_id::Int                       # monotonic counter for measure ids
    last_results::Dict{String,Bool}            # most recent flush's results
    total_duration_ms::Float64                 # accumulated device time
    closed::Bool
end

function HardwareContext(transport::AbstractTransport;
                         capacity::Integer=16,
                         gate_time_ms::Real=1.0)
    capacity > 0 || throw(ArgumentError("capacity must be positive"))
    resp = request(transport, open_session_request(;
        capacity=capacity, gate_time_ms=gate_time_ms))
    resp["ok"] === true ||
        error("HardwareContext: open_session failed: $(get(resp, "err", "?")) — $(get(resp, "detail", ""))")
    sid = String(resp["session_id"])
    ctx = HardwareContext(
        transport, sid, Int(capacity),
        ProtocolOp[], Int[], 0,
        Dict{WireID,Int}(), Set{WireID}(), WireID[],
        0, Dict{String,Bool}(), 0.0, false,
    )
    # Best-effort cleanup if the user forgets to call close. Finalizers can't
    # safely do FFI/IO directly during GC, so we defer via @spawn — that hands
    # close() to the regular task scheduler. Errors are swallowed; the worst
    # case is a leaked server-side session that the device's own session
    # reaper will eventually collect.
    finalizer(_finalize_hardware_context, ctx)
    return ctx
end

function _finalize_hardware_context(ctx::HardwareContext)
    ctx.closed && return
    Threads.@spawn try
        close(ctx)
    catch
    end
end

# ── Internal helpers ──────────────────────────────────────────────────────────

@inline function _check_open(ctx::HardwareContext)
    ctx.closed && error("HardwareContext is closed; cannot perform further operations")
end

function _resolve(ctx::HardwareContext, wire::WireID)::Int
    wire in ctx.consumed && error("Linear resource violation: wire $wire already consumed")
    haskey(ctx.wire_to_qubit, wire) || error("Wire $wire not found in HardwareContext")
    return ctx.wire_to_qubit[wire]
end

# ── Allocation / deallocation ─────────────────────────────────────────────────

function allocate!(ctx::HardwareContext)::WireID
    _check_open(ctx)
    local slot::Int
    if !isempty(ctx.free_slots)
        slot = pop!(ctx.free_slots)
    elseif ctx.next_slot < ctx.capacity
        slot = ctx.next_slot
        ctx.next_slot += 1
    else
        error("HardwareContext: device capacity $(ctx.capacity) exhausted; " *
              "free a qubit via measure! or discard! before allocating another")
    end
    wire = fresh_wire!()
    ctx.wire_to_qubit[wire] = slot
    push!(ctx.pending, op_alloc(slot))
    return wire
end

function deallocate!(ctx::HardwareContext, wire::WireID)
    _check_open(ctx)
    wire in ctx.consumed && error("Wire $wire already consumed")
    haskey(ctx.wire_to_qubit, wire) || error("Wire $wire not found in HardwareContext")
    slot = ctx.wire_to_qubit[wire]
    delete!(ctx.wire_to_qubit, wire)
    push!(ctx.consumed, wire)
    push!(ctx.free_slots, slot)
    push!(ctx.pending, op_discard(slot))
end

live_wires(ctx::HardwareContext) = collect(keys(ctx.wire_to_qubit))

function cleanup!(ctx::HardwareContext)
    # Don't attempt cleanup on a closed session — with_hardware / finalizer own close().
    ctx.closed && return
    _default_cleanup!(ctx)
    return nothing
end

# ── Control stack ─────────────────────────────────────────────────────────────

function push_control!(ctx::HardwareContext, wire::WireID)
    _resolve(ctx, wire)  # validate wire is live
    push!(ctx.control_stack, wire)
end

function pop_control!(ctx::HardwareContext)
    isempty(ctx.control_stack) && error("Control stack underflow")
    pop!(ctx.control_stack)
end

current_controls(ctx::HardwareContext) = copy(ctx.control_stack)

# ── Gate application ──────────────────────────────────────────────────────────
# Same nc=0 / nc=1 / nc>=2 dispatch pattern as EagerContext — and same
# multi_control.jl cascade for the deep cases. The nc=1 case for Ry/Rz routes
# through _controlled_ry!/_rz! (4-gate ABC decomposition); for CX/CCX we emit
# a CCX directly because the device has a native ccx verb.

function apply_ry!(ctx::HardwareContext, wire::WireID, angle::Real)
    _check_open(ctx)
    nc = length(ctx.control_stack)
    if nc == 0
        slot = _resolve(ctx, wire)
        push!(ctx.pending, op_ry(slot, Float64(angle)))
    elseif nc == 1
        _controlled_ry!(ctx, ctx.control_stack[1], wire, angle)
    else
        _multi_controlled_gate!(ctx, wire, angle, _controlled_ry!)
    end
end

function apply_rz!(ctx::HardwareContext, wire::WireID, angle::Real)
    _check_open(ctx)
    nc = length(ctx.control_stack)
    if nc == 0
        slot = _resolve(ctx, wire)
        push!(ctx.pending, op_rz(slot, Float64(angle)))
    elseif nc == 1
        _controlled_rz!(ctx, ctx.control_stack[1], wire, angle)
    else
        _multi_controlled_gate!(ctx, wire, angle, _controlled_rz!)
    end
end

function apply_cx!(ctx::HardwareContext, ctrl_wire::WireID, target_wire::WireID)
    _check_open(ctx)
    nc = length(ctx.control_stack)
    if nc == 0
        push!(ctx.pending, op_cx(_resolve(ctx, ctrl_wire), _resolve(ctx, target_wire)))
    elseif nc == 1
        push!(ctx.pending, op_ccx(
            _resolve(ctx, ctx.control_stack[1]),
            _resolve(ctx, ctrl_wire),
            _resolve(ctx, target_wire),
        ))
    else
        _multi_controlled_cx!(ctx, ctrl_wire, target_wire)
    end
end

function apply_ccx!(ctx::HardwareContext, c1::WireID, c2::WireID, target::WireID)
    _check_open(ctx)
    nc = length(ctx.control_stack)
    if nc == 0
        push!(ctx.pending, op_ccx(
            _resolve(ctx, c1), _resolve(ctx, c2), _resolve(ctx, target),
        ))
    else
        # CCX inside when(): treat as CX(c2, target) with extra control c1.
        # Mirrors EagerContext at src/context/eager.jl:179-188.
        push!(ctx.control_stack, c1)
        try
            _multi_controlled_cx!(ctx, c2, target)
        finally
            pop!(ctx.control_stack)
        end
    end
end

# ── Measurement (the only synchronous op — flushes the pending buffer) ──────

function measure!(ctx::HardwareContext, wire::WireID)::Bool
    _warn_direct_measure()
    _check_open(ctx)
    slot = _resolve(ctx, wire)
    id = "m" * string(ctx.next_measure_id; base=16)
    ctx.next_measure_id += 1
    push!(ctx.pending, op_measure(slot, id))

    # The device recycles on measure (HW4 contract). Reflect that locally:
    # mark wire consumed, return slot to client-side free pool.
    push!(ctx.consumed, wire)
    delete!(ctx.wire_to_qubit, wire)
    push!(ctx.free_slots, slot)

    flush!(ctx)
    haskey(ctx.last_results, id) ||
        error("HardwareContext: server did not return a result for measurement '$id'")
    return ctx.last_results[id]
end

# ── Flush and close ───────────────────────────────────────────────────────────

"""
    flush!(ctx::HardwareContext)

Send all queued ops to the backend in a single submit, parse the response,
update `last_results` and `total_duration_ms`, and clear `pending`. No-op if
nothing is queued. Public for benchmarking; called automatically by `measure!`
and `close`.
"""
function flush!(ctx::HardwareContext)
    _check_open(ctx)
    isempty(ctx.pending) && return
    msg = submit_request(ctx.session_id, ctx.pending)
    resp = request(ctx.transport, msg)
    resp["ok"] === true ||
        error("HardwareContext: backend rejected submit: $(get(resp, "err", "?")) — $(get(resp, "detail", ""))")
    raw = get(resp, "results", Dict{String,Any}())
    ctx.last_results = Dict{String,Bool}(String(k) => v::Bool for (k, v) in raw)
    ctx.total_duration_ms += Float64(get(resp, "duration_ms", 0.0))
    empty!(ctx.pending)
    return
end

function Base.close(ctx::HardwareContext)
    ctx.closed && return
    try
        flush!(ctx)
    catch
        # Even if flush fails, attempt to close the session to avoid orphaning
        # device resources. Re-raise after the close attempt.
        try
            request(ctx.transport, close_session_request(ctx.session_id))
        catch
        end
        ctx.closed = true
        rethrow()
    end
    request(ctx.transport, close_session_request(ctx.session_id))
    ctx.closed = true
    return
end

Base.show(io::IO, ctx::HardwareContext) = print(io,
    "HardwareContext(session=", ctx.session_id, ", capacity=", ctx.capacity,
    ", live=", length(ctx.wire_to_qubit), ", pending=", length(ctx.pending),
    ctx.closed ? ", CLOSED" : "", ")")

# ── Convenience wrapper: with_hardware (Rust-style RAII) ─────────────────────

"""
    with_hardware(f, transport::AbstractTransport;
                  capacity=16, gate_time_ms=1.0) -> Any

Open a HardwareContext on `transport`, set it as the active Sturm context for
the duration of `f`, run `f(ctx)`, and unconditionally close the context on
exit (including on exception). Equivalent to:

```julia
ctx = HardwareContext(transport; ...)
try
    @context ctx; f(ctx)
finally
    close(ctx)
end
```

Use this instead of bare `HardwareContext` + `@context` whenever the lifetime
of the context matches a single function call. Avoids leaking device sessions.
"""
function with_hardware(f::Function, transport::AbstractTransport;
                       capacity::Integer=16, gate_time_ms::Real=1.0)
    ctx = HardwareContext(transport;
        capacity=capacity, gate_time_ms=gate_time_ms)
    old = get(task_local_storage(), :sturm_context, nothing)
    task_local_storage(:sturm_context, ctx)
    try
        return f(ctx)
    finally
        if old === nothing
            delete!(task_local_storage(), :sturm_context)
        else
            task_local_storage(:sturm_context, old)
        end
        try
            close(ctx)
        catch
        end
    end
end
