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

# ── Scope-based cleanup (bead sv3) ────────────────────────────────────────────

"""
    live_wires(ctx::AbstractContext) -> Vector{WireID}

Snapshot of wires currently allocated in `ctx` and not yet consumed.
Returned as a fresh vector — `cleanup!` iterates while mutating the context.
Ordering is implementation-defined but must be stable within a single call.

Each backend implements this in terms of its own live-set representation:
EagerContext/DensityMatrixContext/HardwareContext use `keys(wire_to_qubit)`;
TracingContext maintains its own insertion-ordered `live::Vector{WireID}`.
"""
function live_wires(ctx::AbstractContext)
    error("live_wires not implemented for $(typeof(ctx))")
end

"""
    cleanup!(ctx::AbstractContext)

Partial-trace every wire returned by `live_wires(ctx)`. Called automatically
by the `@context` macro at block exit (in `finally`, so also on exception).

Default implementation loops over `live_wires(ctx)` and calls `deallocate!`
on each, catching per-wire errors into `@warn` — one bad wire does not poison
the rest of cleanup. Backends can override for bulk-discard optimisations
(e.g. `HardwareContext` short-circuits when `ctx.closed`).

This is deterministic cleanup tied to scope (mirrors `lock(l) do … end` /
`open(f, path) do stream … end`), NOT a Julia finalizer. Finalizer + FFI is
unsafe (runs in arbitrary GC contexts); scope-driven cleanup is safe.
"""
function cleanup!(ctx::AbstractContext)
    _default_cleanup!(ctx)
end

function _default_cleanup!(ctx::AbstractContext)
    wires = live_wires(ctx)
    for w in wires
        try
            deallocate!(ctx, w)
        catch err
            @warn "Sturm @context: cleanup failed for wire" wire=w exception=(err, catch_backtrace())
        end
    end
    return nothing
end

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

Unconsumed quantum resources allocated inside the block are partial-traced at exit (bead sv3).
"""
macro context(ctx_expr, body)
    quote
        local ctx = $(esc(ctx_expr))
        local old = get(task_local_storage(), :sturm_context, nothing)
        task_local_storage(:sturm_context, ctx)
        local result
        local body_threw = false
        try
            try
                result = $(esc(body))
            catch
                body_threw = true
                rethrow()
            end
        finally
            # Scope-based cleanup of any unconsumed quantum resources (bead sv3).
            # Runs BEFORE TLS restoration so deallocate! paths that consult
            # current_context() still see their own ctx.
            try
                cleanup!(ctx)
            catch cleanup_err
                # Body exception wins — a cleanup failure during an unwind is
                # almost always a consequence of the body's error, and losing
                # the user's exception to expose ours is worse.
                if body_threw
                    @warn "Sturm @context: cleanup! failed during exception unwind" exception=(cleanup_err, catch_backtrace())
                else
                    # Restore TLS before rethrowing so the caller sees a sane stack.
                    if old === nothing
                        delete!(task_local_storage(), :sturm_context)
                    else
                        task_local_storage(:sturm_context, old)
                    end
                    rethrow(cleanup_err)
                end
            end
            if old === nothing
                delete!(task_local_storage(), :sturm_context)
            else
                task_local_storage(:sturm_context, old)
            end
        end
        result
    end
end
