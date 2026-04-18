"""
    AbstractContext

Interface that all quantum execution contexts must implement.
EagerContext executes immediately via Orkan. TracingContext builds a DAG.
"""
abstract type AbstractContext end

# ── Interface methods (must be implemented by subtypes) ───────────────────────

"""Allocate a fresh qubit wire in the context. Returns WireID."""
function allocate!(ctx::AbstractContext)
    error("allocate! not implemented for $(typeof(ctx))")
end

"""Deallocate a qubit wire (partial trace / discard)."""
function deallocate!(ctx::AbstractContext, wire::WireID)
    error("deallocate! not implemented for $(typeof(ctx))")
end

"""Allocate n fresh qubit wires. Returns Vector{WireID}."""
function allocate_batch!(ctx::AbstractContext, n::Int)::Vector{WireID}
    return WireID[allocate!(ctx) for _ in 1:n]
end

"""Deallocate a batch of qubit wires."""
function deallocate_batch!(ctx::AbstractContext, wires::Vector{WireID})
    for w in wires
        deallocate!(ctx, w)
    end
end

"""Apply Ry(angle) rotation to a wire, respecting the current control stack."""
function apply_ry!(ctx::AbstractContext, wire::WireID, angle::Real)
    error("apply_ry! not implemented for $(typeof(ctx))")
end

"""Apply Rz(angle) rotation to a wire, respecting the current control stack."""
function apply_rz!(ctx::AbstractContext, wire::WireID, angle::Real)
    error("apply_rz! not implemented for $(typeof(ctx))")
end

"""Apply CNOT with control_wire controlling target_wire."""
function apply_cx!(ctx::AbstractContext, control_wire::WireID, target_wire::WireID)
    error("apply_cx! not implemented for $(typeof(ctx))")
end

"""Apply Toffoli (CCX): target ⊻= c1 ∧ c2, respecting the current control stack."""
function apply_ccx!(ctx::AbstractContext, c1::WireID, c2::WireID, target::WireID)
    error("apply_ccx! not implemented for $(typeof(ctx))")
end

"""Measure a wire, collapse state, return classical Bool."""
function measure!(ctx::AbstractContext, wire::WireID)::Bool
    error("measure! not implemented for $(typeof(ctx))")
end

"""Push a control wire onto the control stack (for `when` blocks)."""
function push_control!(ctx::AbstractContext, wire::WireID)
    error("push_control! not implemented for $(typeof(ctx))")
end

"""Pop the most recent control wire from the control stack."""
function pop_control!(ctx::AbstractContext)
    error("pop_control! not implemented for $(typeof(ctx))")
end

"""Return the current control stack as a *copy* (callers may mutate safely)."""
function current_controls(ctx::AbstractContext)::Vector{WireID}
    error("current_controls not implemented for $(typeof(ctx))")
end

"""
    with_controls(f, ctx::AbstractContext, controls::Vector{WireID})

Run `f()` with the context's control stack set to `controls`. The original
stack is saved on entry and restored on exit, including on exception. Returns
the value of `f()`.

This is the public API for library code that needs to temporarily switch the
active controls (e.g. LCU PREPARE/SELECT isolation, Pauli-exp basis change
lifting). Prefer this over reaching into an implementation detail like
`ctx.control_stack` directly, which is not part of the `AbstractContext`
contract and may not exist on all backends (tensor-network / hardware
contexts).

Default implementation uses `current_controls` + `push_control!`/`pop_control!`,
so any context that implements those methods gets this for free.
"""
function with_controls(f, ctx::AbstractContext, controls::Vector{WireID})
    saved = current_controls(ctx)
    # Clear the current stack via the public pop API.
    for _ in 1:length(saved)
        pop_control!(ctx)
    end
    # Push the requested controls.
    for w in controls
        push_control!(ctx, w)
    end
    try
        return f()
    finally
        # Reverse: pop the pushed controls, then restore the original.
        for _ in 1:length(controls)
            pop_control!(ctx)
        end
        for w in saved
            push_control!(ctx, w)
        end
    end
end

"""
    with_empty_controls(f, ctx::AbstractContext)

Run `f()` with the context's control stack cleared; restore on exit. Thin
wrapper around `with_controls(f, ctx, WireID[])`. Used by operations whose
inner pieces are provably unconditional (LCU's `PREPARE`/`PREPARE†`, the
basis change + CNOT staircase in `pauli_exp!`) — clearing the stack avoids
emitting spurious controls on gates the physics says are unconditional.
"""
with_empty_controls(f, ctx::AbstractContext) = with_controls(f, ctx, WireID[])

# ── Context propagation via task-local storage ────────────────────────────────

"""
    current_context()

Retrieve the active Sturm context from task-local storage.
Set via `@context` macro.
"""
function current_context()
    ctx = get(task_local_storage(), :sturm_context, nothing)
    ctx === nothing && error("No active Sturm context. Use @context or pass a context explicitly.")
    return ctx::AbstractContext
end

"""
    @context ctx begin ... end

Execute a block with `ctx` as the active Sturm context.
Nested `@context` blocks override the outer context.
"""
macro context(ctx_expr, body)
    quote
        local old = get(task_local_storage(), :sturm_context, nothing)
        task_local_storage(:sturm_context, $(esc(ctx_expr)))
        try
            $(esc(body))
        finally
            if old === nothing
                delete!(task_local_storage(), :sturm_context)
            else
                task_local_storage(:sturm_context, old)
            end
        end
    end
end
