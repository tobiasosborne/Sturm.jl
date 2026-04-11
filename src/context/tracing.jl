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
    dag::Vector{HotNode}
    control_stack::Vector{WireID}
    consumed::Set{WireID}
    _result_counter::UInt32

    function TracingContext(; sizehint::Int=256)
        dag = HotNode[]
        sizehint > 0 && sizehint!(dag, sizehint)
        new(dag, WireID[], Set{WireID}(), UInt32(0))
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

# Inline controls from the control stack — zero allocation.
# Reads directly from the stack without copy().
@inline function _inline_from_stack(stack::Vector{WireID})
    n = length(stack)
    n > 2 && error("Maximum 2 when()-controls supported, got $n")
    nc = UInt8(n)
    c1 = n >= 1 ? stack[1] : _ZERO_WIRE
    c2 = n >= 2 ? stack[2] : _ZERO_WIRE
    (nc, c1, c2)
end

function apply_ry!(ctx::TracingContext, wire::WireID, angle::Real)
    _resolve_tracing(ctx, wire)
    nc, c1, c2 = _inline_from_stack(ctx.control_stack)
    push!(ctx.dag, RyNode(Float64(angle), wire, c1, c2, nc))
end

function apply_rz!(ctx::TracingContext, wire::WireID, angle::Real)
    _resolve_tracing(ctx, wire)
    nc, c1, c2 = _inline_from_stack(ctx.control_stack)
    push!(ctx.dag, RzNode(Float64(angle), wire, c1, c2, nc))
end

function apply_cx!(ctx::TracingContext, control_wire::WireID, target_wire::WireID)
    _resolve_tracing(ctx, control_wire)
    _resolve_tracing(ctx, target_wire)
    nc, c1, c2 = _inline_from_stack(ctx.control_stack)
    push!(ctx.dag, CXNode(control_wire, target_wire, c1, c2, nc))
end

function apply_ccx!(ctx::TracingContext, c1::WireID, c2::WireID, target::WireID)
    _resolve_tracing(ctx, c1)
    _resolve_tracing(ctx, c2)
    _resolve_tracing(ctx, target)
    # CCX(c1, c2, target) = CX(c2, target) controlled on c1 + stack controls
    nc_stack, sc1, sc2 = _inline_from_stack(ctx.control_stack)
    if nc_stack == 0
        push!(ctx.dag, CXNode(c2, target, c1, _ZERO_WIRE, UInt8(1)))
    elseif nc_stack == 1
        push!(ctx.dag, CXNode(c2, target, sc1, c1, UInt8(2)))
    else
        error("apply_ccx! inside >1 nested when(): would need 3+ controls, exceeds DAG inline limit")
    end
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
