# cases() — classical conditional control on a measurement outcome.
#
# Distinct from `when()` in src/control/when.jl: when() is COHERENT control
# (no measurement; the qubit stays quantum). cases() is CLASSICAL control
# (the qubit IS measured; one of two thunks runs based on the outcome).
#
# Per axiom P4: same syntactic surface form must not hide two different
# channels. `when()` and `cases()` are visually distinct primitives — Sturm
# does not collapse them into a single `if` form (which would be the type-lie
# Cirq commits with `with_classical_controls`).
#
# Per axiom P2: the quantum→classical boundary is a cast. cases() is the
# only sanctioned construct that combines the cast with conditional control;
# raw `Bool(q)` inside a TracingContext errors loudly with a migration
# message pointing here.
#
# Refs:
#   - Bug: Sturm.jl-322 — TracingContext silent mis-trace of `if Bool(q)`.
#   - Prior art: Qiskit `with circuit.if_test((c, 1))`, Q# `if M(q) == One`,
#     OpenQASM 3 `if (c == 1) { ... }`, MQT IfElseOperation.

"""
    cases(q::QBool, then::Function, else_::Function = () -> nothing)

Classical conditional on a measurement outcome of `q`. The qubit `q` is
consumed (measured); based on the outcome, exactly one of `then` and `else_`
runs in eager / hardware execution. Under TracingContext, BOTH branches are
traced into separate sub-DAGs and combined into a `CasesNode` for the
deferred-measurement pass to lower.

`then` and `else_` are zero-argument thunks. Use the `@cases` macro for
two-block syntax — Julia doesn't support chained `do`-blocks, so the
function form takes the thunks positionally.

# Examples

EagerContext (syndrome correction):

    @context EagerContext() begin
        ancilla = QBool(1.0); target = QBool(0.0)
        cases(ancilla, () -> X!(target))    # if ancilla measured 1, flip target
        @assert Bool(target) === true
    end

TracingContext (captured into CasesNode for OpenQASM dynamic-circuit export):

    ch = trace(1) do q
        target = QBool(0)
        cases(q, () -> X!(target))
        target
    end
    # ch contains a controlled-X (q controls X on target), via auto-lowering.

Empty cases (record measurement in IR without classical branching — e.g.,
for OpenQASM `measure q -> c;` output):

    cases(q, () -> nothing)
"""
function cases(q::QBool, then::Function, else_::Function = () -> nothing)
    check_live!(q)
    return _cases_dispatch(q.ctx, q, then, else_)
end

# Default per-context dispatch: synchronous measure-and-run-one-thunk.
# Covers EagerContext, DensityMatrixContext, HardwareContext.
function _cases_dispatch(ctx::AbstractContext, q::QBool,
                         then::Function, else_::Function)
    consume!(q)
    result = _blessed_measure!(ctx, q.wire)
    if result
        then()
    else
        else_()
    end
    return nothing
end

# TracingContext: trace BOTH branches into sub-DAGs, then emit a CasesNode.
# The thunks may emit any quantum operations (rotations, CX, when(), etc.)
# but must NOT contain a nested measurement (Bool(q) / Int(q)) — that
# pattern errors loudly via the measure!(::TracingContext) override, and
# defer_measurements would refuse to lower it anyway.
function _cases_dispatch(ctx::TracingContext, q::QBool,
                         then::Function, else_::Function)
    consume!(q)
    cond_id = _emit_observe!(ctx, q.wire)
    saved_dag = ctx.dag

    ctx.dag = DAGNode[]
    then()
    then_branch = ctx.dag

    ctx.dag = DAGNode[]
    else_()
    else_branch = ctx.dag

    ctx.dag = saved_dag
    push!(ctx.dag, CasesNode(cond_id, then_branch, else_branch))
    return nothing
end

# ── Macro form: two `begin … end` blocks for ergonomic two-branch syntax ──────
#
# Julia does NOT support chained do-blocks (`f(x) do … end do … end` is a
# parse error), so we can't mirror `when(q) do … end` directly. The macro
# accepts one or two trailing block expressions:
#
#   @cases q begin then_body end                 → cases(q, () -> then_body)
#   @cases q begin then_body end begin else end  → cases(q, () -> then_body, () -> else)

"""
    @cases q begin … end
    @cases q begin … end begin … end

Macro form of `cases()` taking one or two `begin … end` blocks. The first
block is the then-branch (runs on measurement outcome `1`); the optional
second block is the else-branch.

See [`cases`](@ref) for full semantics.
"""
macro cases(args...)
    if length(args) == 2
        q, then_block = args
        return :(cases($(esc(q)), () -> $(esc(then_block))))
    elseif length(args) == 3
        q, then_block, else_block = args
        return :(cases($(esc(q)), () -> $(esc(then_block)), () -> $(esc(else_block))))
    else
        return :(error("@cases requires 2 or 3 arguments: q, then_block, [else_block]; got $(length(args))"))
    end
end
