"""
    TracingContext

Records quantum operations as DAG nodes instead of executing them.
Used by `trace()` to capture circuits for Channel representation,
optimisation passes, and OpenQASM export.

Implements all AbstractContext methods symbolically:
- allocate! returns a fresh WireID (no Orkan state allocated)
- apply_ry!/apply_rz!/apply_cx! append DAG nodes
- measure! appends ObserveNode and returns a Bool placeholder
"""
mutable struct TracingContext <: AbstractContext
    dag::Vector{DAGNode}
    control_stack::Vector{WireID}
    consumed::Set{WireID}
    _result_counter::UInt32

    function TracingContext()
        new(DAGNode[], WireID[], Set{WireID}(), UInt32(0))
    end
end

# ── Qubit allocation ─────────────────────────────────────────────────────────

function allocate!(ctx::TracingContext)::WireID
    fresh_wire!()
end

function deallocate!(ctx::TracingContext, wire::WireID)
    wire in ctx.consumed && error("Wire $wire already consumed")
    push!(ctx.dag, DiscardNode(wire))
    push!(ctx.consumed, wire)
end

# ── Wire resolution ──────────────────────────────────────────────────────────

function _resolve_tracing(ctx::TracingContext, wire::WireID)
    wire in ctx.consumed && error("Linear resource violation: wire $wire already consumed")
    return wire
end

# ── Control stack ────────────────────────────────────────────────────────────

function push_control!(ctx::TracingContext, wire::WireID)
    _resolve_tracing(ctx, wire)
    push!(ctx.control_stack, wire)
end

function pop_control!(ctx::TracingContext)
    isempty(ctx.control_stack) && error("Control stack underflow")
    pop!(ctx.control_stack)
end

current_controls(ctx::TracingContext) = copy(ctx.control_stack)

# ── Gate recording ───────────────────────────────────────────────────────────

function apply_ry!(ctx::TracingContext, wire::WireID, angle::Real)
    _resolve_tracing(ctx, wire)
    push!(ctx.dag, RyNode(wire, Float64(angle), copy(ctx.control_stack)))
end

function apply_rz!(ctx::TracingContext, wire::WireID, angle::Real)
    _resolve_tracing(ctx, wire)
    push!(ctx.dag, RzNode(wire, Float64(angle), copy(ctx.control_stack)))
end

function apply_cx!(ctx::TracingContext, control_wire::WireID, target_wire::WireID)
    _resolve_tracing(ctx, control_wire)
    _resolve_tracing(ctx, target_wire)
    push!(ctx.dag, CXNode(control_wire, target_wire, copy(ctx.control_stack)))
end

# ── Measurement (symbolic) ───────────────────────────────────────────────────

function measure!(ctx::TracingContext, wire::WireID)::Bool
    _resolve_tracing(ctx, wire)
    ctx._result_counter += 1
    push!(ctx.dag, ObserveNode(wire, ctx._result_counter))
    push!(ctx.consumed, wire)
    # In tracing mode, measurement returns a deterministic placeholder.
    # Classical branching (if/else on measurement) is recorded via CasesNode
    # when using the trace() function. For now, return false as default path.
    return false
end
