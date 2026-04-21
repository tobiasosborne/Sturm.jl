# IdealisedSimulator — Orkan-backed in-process model of the hardware device.
#
# A IdealisedSimulator owns N independent sessions. Each session has its own
# EagerContext at the configured capacity. The simulator translates the wire
# protocol (ProtocolOp + Dict envelopes from src/hardware/protocol.jl) into
# direct calls on EagerContext.
#
# Slot management contract (see bead Sturm.jl-7it):
#   - The CLIENT picks qubit indices in [0, capacity).
#   - The SERVER maintains qubit_to_wire :: Dict{Int, WireID}.
#   - alloc(k):  k must be in range AND not currently in qubit_to_wire.
#   - any op on k:  k must be in qubit_to_wire.
#   - measure(k, id):  result stored under id; mapping deleted (recycled).
#   - discard(k):  mapping deleted; EagerContext.deallocate! handles reset.
#
# Errors return {ok: false, err: <code>, detail: <msg>} per protocol.jl.

mutable struct _SimSession
    eager::EagerContext
    qubit_to_wire::Dict{Int,WireID}   # device qubit idx → internal WireID
end

mutable struct IdealisedSimulator
    capacity::Int               # max qubits the simulator will accept
    gate_time_ms::Float64       # nominal time per unitary gate
    realtime::Bool              # if true, sleep duration_ms on each submit
    sessions::Dict{String,_SimSession}
    next_session_id::Int

    function IdealisedSimulator(; capacity::Integer=16,
                                  gate_time_ms::Real=1.0,
                                  realtime::Bool=false)
        capacity > 0 || throw(ArgumentError("capacity must be positive"))
        gate_time_ms >= 0 || throw(ArgumentError("gate_time_ms must be non-negative"))
        new(Int(capacity), Float64(gate_time_ms), realtime,
            Dict{String,_SimSession}(), 1)
    end
end

# ── Top-level dispatch ────────────────────────────────────────────────────────

"""
    dispatch!(sim::IdealisedSimulator, msg::AbstractDict) -> Dict{String,Any}

Process a single protocol message. Routes by `msg["op"]`. Returns an `ok` or
`err` response Dict. Never throws on protocol-level errors — they become
`{ok: false, err: ...}` responses. Genuine bugs (assertion failures, Orkan
crashes) still throw.
"""
function dispatch!(sim::IdealisedSimulator, msg::AbstractDict)::Dict{String,Any}
    haskey(msg, "v") || return err_response("missing_version"; detail="message lacks 'v' field")
    if msg["v"] != PROTOCOL_VERSION
        return err_response("version_mismatch";
                            detail="server speaks v$PROTOCOL_VERSION, got v$(msg["v"])")
    end
    haskey(msg, "op") || return err_response("missing_op"; detail="message lacks 'op' field")
    op = msg["op"]
    if op == "open_session"
        return _do_open_session(sim, msg)
    elseif op == "close_session"
        return _do_close_session(sim, msg)
    elseif op == "submit"
        return _do_submit(sim, msg)
    else
        return err_response("unknown_message_op"; detail=String(op))
    end
end

# ── Session lifecycle ─────────────────────────────────────────────────────────

function _do_open_session(sim::IdealisedSimulator, msg::AbstractDict)::Dict{String,Any}
    requested = Int(get(msg, "capacity", sim.capacity))
    if requested > sim.capacity
        return err_response("capacity_exceeded";
            detail="requested $requested, sim max $(sim.capacity)")
    end
    if requested <= 0
        return err_response("invalid_capacity"; detail="must be positive")
    end
    sid = string("s_", lpad(string(sim.next_session_id; base=16), 4, '0'))
    sim.next_session_id += 1
    eager = EagerContext(; capacity=requested)
    sim.sessions[sid] = _SimSession(eager, Dict{Int,WireID}())
    resp = ok_response()
    resp["session_id"] = sid
    return resp
end

function _do_close_session(sim::IdealisedSimulator, msg::AbstractDict)::Dict{String,Any}
    haskey(msg, "session_id") || return err_response("missing_session_id")
    sid = String(msg["session_id"])
    haskey(sim.sessions, sid) || return err_response("unknown_session"; detail=sid)
    delete!(sim.sessions, sid)
    return ok_response()
end

# ── Submit (the hot path) ─────────────────────────────────────────────────────

function _do_submit(sim::IdealisedSimulator, msg::AbstractDict)::Dict{String,Any}
    haskey(msg, "session_id") || return err_response("missing_session_id")
    sid = String(msg["session_id"])
    haskey(sim.sessions, sid) || return err_response("unknown_session"; detail=sid)
    sess = sim.sessions[sid]

    haskey(msg, "ops") || return err_response("missing_ops")
    ops_raw = msg["ops"]
    ops_raw isa AbstractVector || return err_response("malformed_ops"; detail="not a vector")

    results = Dict{String,Any}()
    n_gates = 0

    for (idx, raw) in enumerate(ops_raw)
        raw isa AbstractDict || return err_response("malformed_op";
            detail="op $idx is not a dict")
        local op::ProtocolOp
        try
            op = from_json_dict(raw)
        catch e
            e isa ProtocolError || rethrow()
            return err_response("malformed_op"; detail="op $idx: $(e.msg)")
        end

        err = _execute_op!(sess, op, results)
        err === nothing || return err  # err is itself an err_response Dict
        if op.verb in (:ry, :rz, :cx, :ccx)
            n_gates += 1
        end
    end

    duration_ms = n_gates * sim.gate_time_ms
    if sim.realtime && duration_ms > 0
        sleep(duration_ms / 1000)
    end

    return ok_response(; results=results, duration_ms=duration_ms)
end

# Returns nothing on success, or an err_response Dict on failure.
function _execute_op!(sess::_SimSession, op::ProtocolOp,
                      results::Dict{String,Any})::Union{Nothing,Dict{String,Any}}
    f = op.fields
    if op.verb === :alloc
        q = Int(f["qubit"])
        0 <= q < sess.eager.capacity || return err_response("qubit_out_of_range";
            detail="qubit $q not in [0, $(sess.eager.capacity))")
        haskey(sess.qubit_to_wire, q) && return err_response("alloc_conflict";
            detail="qubit $q already allocated in this session")
        wire = allocate!(sess.eager)
        sess.qubit_to_wire[q] = wire
        return nothing

    elseif op.verb === :discard
        q = Int(f["qubit"])
        haskey(sess.qubit_to_wire, q) || return err_response("qubit_not_allocated";
            detail="discard on un-allocated qubit $q")
        wire = sess.qubit_to_wire[q]
        delete!(sess.qubit_to_wire, q)
        deallocate!(sess.eager, wire)
        return nothing

    elseif op.verb === :ry
        q = Int(f["qubit"])
        haskey(sess.qubit_to_wire, q) || return err_response("qubit_not_allocated";
            detail="ry on un-allocated qubit $q")
        apply_ry!(sess.eager, sess.qubit_to_wire[q], Float64(f["theta"]))
        return nothing

    elseif op.verb === :rz
        q = Int(f["qubit"])
        haskey(sess.qubit_to_wire, q) || return err_response("qubit_not_allocated";
            detail="rz on un-allocated qubit $q")
        apply_rz!(sess.eager, sess.qubit_to_wire[q], Float64(f["theta"]))
        return nothing

    elseif op.verb === :cx
        c = Int(f["control"]); t = Int(f["target"])
        haskey(sess.qubit_to_wire, c) || return err_response("qubit_not_allocated";
            detail="cx control $c not allocated")
        haskey(sess.qubit_to_wire, t) || return err_response("qubit_not_allocated";
            detail="cx target $t not allocated")
        apply_cx!(sess.eager, sess.qubit_to_wire[c], sess.qubit_to_wire[t])
        return nothing

    elseif op.verb === :ccx
        c1 = Int(f["c1"]); c2 = Int(f["c2"]); t = Int(f["target"])
        for (label, q) in (("c1", c1), ("c2", c2), ("target", t))
            haskey(sess.qubit_to_wire, q) || return err_response("qubit_not_allocated";
                detail="ccx $label $q not allocated")
        end
        apply_ccx!(sess.eager,
                   sess.qubit_to_wire[c1],
                   sess.qubit_to_wire[c2],
                   sess.qubit_to_wire[t])
        return nothing

    elseif op.verb === :measure
        q = Int(f["qubit"])
        id = String(f["id"])
        haskey(sess.qubit_to_wire, q) || return err_response("qubit_not_allocated";
            detail="measure on un-allocated qubit $q")
        wire = sess.qubit_to_wire[q]
        # Use EagerContext's internal blessed-measure path so the P2 antipattern
        # warning stays silent — this IS the device-level measurement primitive.
        result = _blessed_measure!(sess.eager, wire)
        delete!(sess.qubit_to_wire, q)  # measure recycles on the EagerContext side
        results[id] = result
        return nothing

    elseif op.verb === :barrier
        return nothing

    else
        return err_response("unknown_verb"; detail=String(op.verb))
    end
end
