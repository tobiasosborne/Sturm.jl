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
    # Vector{DAGNode} (not Vector{HotNode}) so that cases() can append CasesNode
    # mid-trace. The trace() entry point auto-lowers CasesNodes via
    # defer_measurements before constructing a Channel, which keeps the
    # long-lived Channel.dag::Vector{HotNode} (Session 3 perf win) untouched.
    dag::Vector{DAGNode}
    control_stack::Vector{WireID}
    consumed::Set{WireID}
    live::Vector{WireID}    # sv3: insertion-ordered live-wire set; cleanup! emits DiscardNodes for orphans
    _result_counter::UInt32

    function TracingContext(; sizehint::Int=256)
        dag = DAGNode[]
        sizehint > 0 && sizehint!(dag, sizehint)
        new(dag, WireID[], Set{WireID}(), WireID[], UInt32(0))
    end
end

# ── Qubit allocation ─────────────────────────────────────────────────────────

function allocate!(ctx::TracingContext)::WireID
    wire = fresh_wire!()
    push!(ctx.live, wire)
    wire
end

function deallocate!(ctx::TracingContext, wire::WireID)
    wire in ctx.consumed && error("Wire $wire already consumed")
    push!(ctx.dag, DiscardNode(wire))
    push!(ctx.consumed, wire)
    filter!(!=(wire), ctx.live)
end

live_wires(ctx::TracingContext) = copy(ctx.live)

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

# Inline controls from the control stack — zero allocation at the hot path
# (nc ≤ 2). Deeper nesting routes through the shared Toffoli cascade in
# `multi_control.jl`, which lowers to depth-≤2 DAG nodes via workspace
# qubits — no `DeepCtrlNode` is needed because the cascade fully expands
# the deep-controlled op inside the trace.
@inline function _inline_from_stack(stack::Vector{WireID})
    n = length(stack)
    n > 2 && error("_inline_from_stack: internal invariant violated, expected nc ≤ 2 but got $n — caller should have routed to the cascade")
    nc = UInt8(n)
    c1 = n >= 1 ? stack[1] : _ZERO_WIRE
    c2 = n >= 2 ? stack[2] : _ZERO_WIRE
    (nc, c1, c2)
end

function apply_ry!(ctx::TracingContext, wire::WireID, angle::Real)
    _resolve_tracing(ctx, wire)
    nc = length(ctx.control_stack)
    if nc <= 2
        ncu, c1, c2 = _inline_from_stack(ctx.control_stack)
        push!(ctx.dag, RyNode(Float64(angle), wire, c1, c2, ncu))
    else
        _multi_controlled_gate!(ctx, wire, angle, _controlled_ry!)
    end
end

function apply_rz!(ctx::TracingContext, wire::WireID, angle::Real)
    _resolve_tracing(ctx, wire)
    nc = length(ctx.control_stack)
    if nc <= 2
        ncu, c1, c2 = _inline_from_stack(ctx.control_stack)
        push!(ctx.dag, RzNode(Float64(angle), wire, c1, c2, ncu))
    else
        _multi_controlled_gate!(ctx, wire, angle, _controlled_rz!)
    end
end

function apply_cx!(ctx::TracingContext, control_wire::WireID, target_wire::WireID)
    _resolve_tracing(ctx, control_wire)
    _resolve_tracing(ctx, target_wire)
    nc = length(ctx.control_stack)
    if nc <= 2
        ncu, c1, c2 = _inline_from_stack(ctx.control_stack)
        push!(ctx.dag, CXNode(control_wire, target_wire, c1, c2, ncu))
    else
        _multi_controlled_cx!(ctx, control_wire, target_wire)
    end
end

function apply_ccx!(ctx::TracingContext, c1::WireID, c2::WireID, target::WireID)
    _resolve_tracing(ctx, c1)
    _resolve_tracing(ctx, c2)
    _resolve_tracing(ctx, target)
    # CCX(c1, c2, target) = CX(c2, target) with c1 as an extra control on
    # top of any stack controls.
    nc_stack = length(ctx.control_stack)
    if nc_stack == 0
        push!(ctx.dag, CXNode(c2, target, c1, _ZERO_WIRE, UInt8(1)))
    elseif nc_stack == 1
        sc1 = ctx.control_stack[1]
        push!(ctx.dag, CXNode(c2, target, sc1, c1, UInt8(2)))
    else
        # Deep nesting: push c1 onto the stack and route to the cascade
        # (same pattern as eager/density.jl at apply_ccx!).
        push!(ctx.control_stack, c1)
        try
            _multi_controlled_cx!(ctx, c2, target)
        finally
            pop!(ctx.control_stack)
        end
    end
end

# ── Measurement (symbolic) ───────────────────────────────────────────────────

function measure!(ctx::TracingContext, wire::WireID)::Bool
    error(
        "Bool(q) / Int(q) inside TracingContext is ambiguous: in tracing mode the " *
        "result is always a placeholder, so any branching on it (e.g. `if Bool(q) … end`) " *
        "would silently mis-trace.\n" *
        "Use `cases(q, () -> then_body, () -> else_body)` (or `@cases q begin … end`) " *
        "for measurement-conditioned operations — both branches will be captured into the trace.\n" *
        "Use `discard!(q)` if you only want to throw the qubit away (partial trace).\n" *
        "Use `cases(q, () -> nothing)` if you want a measurement record in the IR (e.g. for " *
        "OpenQASM `measure q -> c;` output) without classical branching."
    )
end

# ── cases() internal: emit ObserveNode without going through measure! ─────────
#
# cases() in src/control/cases.jl needs to record the measurement in the trace
# without triggering measure!'s loud error. _emit_observe! is the internal
# primitive — DO NOT call from user code.
function _emit_observe!(ctx::TracingContext, wire::WireID)::UInt32
    _resolve_tracing(ctx, wire)
    ctx._result_counter += 1
    push!(ctx.dag, ObserveNode(wire, ctx._result_counter))
    push!(ctx.consumed, wire)
    filter!(!=(wire), ctx.live)
    return ctx._result_counter
end
