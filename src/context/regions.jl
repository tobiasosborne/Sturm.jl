# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M2 (bead Sturm.jl-dc6i): regions —
# the Stinespring reading of scope (PRD-v2 §3.9). A function is a channel on its
# signature (P1); locals it allocates and neither consumes nor returns are the
# Stinespring ENVIRONMENT, and scope is the dilation boundary — so they are
# traced at region exit. That trace has NO backaction (no-signaling), so it is
# SILENT by design — the one principled exception to FAIL-LOUD (CLAUDE.md #1;
# §3.9: "implicit ops without backaction are silent"). Do not "fix" the silence.
#
# Deterministic lifecycle: `eager`/`density` are Base-shaped resource do-blocks
# (`open`, `lock`, `mktempdir`) whose `finally` calls `teardown!` → `state_free`
# — memory freed even on a thrown exception mid-region. NEVER a GC finalizer
# (nondeterministic; finalizer + FFI is unsafe — audit §5, v0.1 bead sv3). The
# manual form is `region() do … end` (D10 ruling: a bare-noun do-block; "scope"
# was rejected as doubly claimed by Julia's lexical scope + `Base.ScopedValues`).
#
# Context propagation is `Base.ScopedValue`-based (CLAUDE.md conv 6): bindings
# inherit into `Threads.@spawn`/`@async` children (task_local_storage does NOT —
# a silent-missing-context bug class, deleted), and `with(sv => ctx) do … end`
# IS a genuine try/finally — the deterministic exit a region needs.

import Base.ScopedValues: ScopedValue, with

"""
    CURRENT_CONTEXT

The active context as a `Base.ScopedValue` (read once per surface entry via
`current_context()`, then threaded explicitly through kernel call chains —
ScopedValue access allocates; CLAUDE.md conv 6).
"""
const CURRENT_CONTEXT = ScopedValue{AbstractContext}()

"""
    current_context() -> AbstractContext

The active context, or a loud error if none is bound. Read ONCE at a surface
entry; do not re-read in a per-op hot loop.
"""
function current_context()
    v = Base.ScopedValues.get(CURRENT_CONTEXT)
    v === nothing && error("No active Sturm context — use `eager(cap) do ctx … end`, `density(cap) do ctx … end`, or `@context ctx begin … end`")
    return something(v)
end

# --- Region owned-set stack & the exit trace ---------------------------

_enter_region!(ctx::AbstractContext) = (push!(_core(ctx).region_stack, WireID[]); nothing)

"""
    _escaped_wires(val) -> Vector{WireID}

The wires a region's RETURN VALUE carries out of the region — its survivors. A
returned typed handle (`QBool`, `QInt`, `WireRef`, `DualView`, or a `Tuple` of
them) escapes; anything else (a scalar `Bool` outcome, a bare `WireID` the caller
extracted, `nothing`) escapes NOTHING. This is what lets `_exit_region!`
distinguish a handle handed back to the caller (re-homed to the enclosing region,
NOT traced) from an owned local dropped at scope exit (traced, §3.9). Handles are
recognised structurally, so a bare `WireID` return (a caller who threw the handle
away and kept the raw id) is correctly NOT an escape — the id's wire is traced.
"""
_escaped_wires(::Any) = WireID[]
_escaped_wires(t::Tuple) = isempty(t) ? WireID[] : reduce(vcat, map(_escaped_wires, t))

"""
    _exit_region!(ctx, retval = nothing)

Pop the current region frame and SILENTLY trace every wire it owns that is still
live, unconsumed, and NOT escaped by `retval` (the derived form of `ptrace!` —
§4.5's region boundary is not a third consumption mechanism). Escaped wires (a
returned handle's wires) are re-homed to the enclosing region's owned set (they
outlive this scope), or simply left live if this is the outermost region.
Consumed/returned handles are skipped for free by the single-sourced consumed set
+ liveness. Views borrow (they register no owned wire), so their death traces
nothing.
"""
function _exit_region!(ctx::AbstractContext, retval = nothing)
    core = _core(ctx)
    frame = pop!(core.region_stack)
    escaped = Set{WireID}(_escaped_wires(retval))
    _strict_check!(ctx, frame, escaped)
    enclosing = isempty(core.region_stack) ? nothing : core.region_stack[end]
    for w in frame
        if w in escaped
            enclosing === nothing || push!(enclosing, w)   # re-home the survivor
            continue
        end
        if haskey(core.wire_to_slot, w) && !(w in core.consumed)
            _trace_and_free!(ctx, w)
        end
    end
    nothing
end

"""
    _strict_check!(ctx, frame, escaped)

The D10 lost-binding detector (M6). SIGNATURE of the bug: at region exit, a
register wire being TRACED (owned by this frame, live, unconsumed, not escaped)
is the value-world entangling PARENT of a wire that SURVIVES (escaped, or owned
by an enclosing region). That is the `x = x + a` rebind trap — the fresh sum
survives while the dropped original is torn down, so the sum decoheres — reported
as a CLASSICAL programming error (a lost Julia binding), never quantum nagging.

Off by default (`strict = false` → immediate return, the §3.9 silent-trace
doctrine intact) and armed only by `eager(...; strict=true)` / `density(...;
strict=true)`. FALSE-POSITIVE discipline (each a named negative test): a parent
that is CONSUMED (measured) is excluded from `traced`, so `s = x + a; Int(x)`
does not flag; a parent that is ITSELF escaped/returned is never in `traced`, so
`return (x, s)` (both handles kept) does not flag.
"""
function _strict_check!(ctx::AbstractContext, frame::Vector{WireID}, escaped::Set{WireID})
    core = _core(ctx)
    (core.strict && !isempty(core.parent)) || return nothing
    traced = Set{WireID}(w for w in frame
        if haskey(core.wire_to_slot, w) && !(w in core.consumed) && !(w in escaped))
    for (child, parents) in core.parent
        survives = (child in escaped) ||
            (haskey(core.wire_to_slot, child) && !(child in traced) && !(child in core.consumed))
        survives || continue
        bad = filter(p -> p in traced, parents)
        isempty(bad) || _lost_binding_error(bad, child)
    end
    return nothing
end

@noinline _lost_binding_error(parents, child) = error(
    "lost binding (D10, strict): register wire(s) $(parents) are being traced at " *
    "region exit, but a fresh value-world output (wire $(child)) derived from them " *
    "by a ring op (`x + a` / `x + y`) survives and is entangled with them — the sum " *
    "has decohered. You likely wrote `x = x + a`, which rebinds `x` to the fresh sum " *
    "and drops the original handle. Use `add!(x, a)` for in-place addition, `x̂ += a` " *
    "for a dual-view modulation, or keep BOTH handles live (return/consume the input).")

"""
    _record_parent!(ctx, child::WireID, par::WireID)

Record a value-world entangling edge `child ← par` (child = a fresh-output wire,
par = a live input wire it copied from). Written ONLY by ring ops (`+`/`-`) and
ONLY under `strict` — the action family (in-place, no fresh child) records
nothing. Feeds `_strict_check!`.
"""
function _record_parent!(ctx::AbstractContext, child::WireID, par::WireID)
    push!(get!(() -> WireID[], _core(ctx).parent, child), par)
    nothing
end

# --- @context and region() ---------------------------------------------

"""
    @context ctx begin … end

Bind an existing context for the block (via `Base.ScopedValues.with` — a genuine
try/finally, inheriting into spawned children) and open a region whose owned
locals are traced at block exit. Does NOT free the `state_t` (that is
`eager`/`density`'s job).
"""
macro context(ctx, body)
    quote
        local c = $(esc(ctx))
        with(CURRENT_CONTEXT => c) do
            _enter_region!(c)
            local __ok = false
            local __val = nothing
            try
                __val = $(esc(body))
                __ok = true
                __val
            finally
                _exit_region!(c, __ok ? __val : nothing)
            end
        end
    end
end

"""
    region() do … end

Open a nested region on the current context; its owned locals are traced at
exit. Eager helpers that DON'T open a region inherit the enclosing one — provably
harmless, since trace timing is denotationally invisible (no backaction, §3.9).
"""
function region(f)
    c = current_context()
    _enter_region!(c)
    ok = false
    val = nothing
    try
        val = f()
        ok = true
        return val
    finally
        _exit_region!(c, ok ? val : nothing)
    end
end

# --- ptrace! (explicit early close; a consumption site, §4.5) ----------

"""
    ptrace!(ctx, w::WireID)
    ptrace!(w::WireID)

Explicitly trace and close wire `w` (Eager: measure-and-discard; DM: exact
partial trace). One of the two consumption sites (with qc casts, M3) — marks `w`
consumed on the single-sourced set. Silent, no backaction (§3.9). The single-
argument form uses `current_context()`.
"""
function ptrace!(ctx::AbstractContext, w::WireID)
    # Guardrail 1 (§3.5): an EXPLICIT trace inside a `when` body is a loud error
    # (control on a forgetful map is unrepresentable). This is distinct from the
    # IMPLICIT region-exit trace of a body-owned ancilla, which is the sanctioned
    # clean-ancilla path (`_trace_and_free!` asserts, does not measure) — same
    # mechanism, branched on the caller's intent.
    _assert_no_control(ctx, "explicit ptrace!")
    _trace_and_free!(ctx, w)
    mark_consumed!(ctx, w)
    nothing
end
ptrace!(w::WireID) = ptrace!(current_context(), w)

# --- Resource do-blocks (deterministic teardown even on throw) ---------

"""
    eager(cap; rng=nothing, strict=false) do ctx … end

Run `f(ctx)` with a fresh `capacity=cap` PURE context bound as the current
context inside its own region. Frees the Orkan `state_t` in a `finally` — even
if the body throws (the process-memory safety net). Returns the body's value
(copy your results out; `ctx` and its state do not outlive the block).
"""
function eager(f, capacity::Integer; rng=nothing, strict::Bool=false)
    ctx = EagerContext(capacity; rng=rng, strict=strict)
    try
        return with(CURRENT_CONTEXT => ctx) do
            _enter_region!(ctx)
            ok = false
            val = nothing
            try
                val = f(ctx)
                ok = true
                return val
            finally
                _exit_region!(ctx, ok ? val : nothing)
            end
        end
    finally
        teardown!(ctx)
    end
end

"""
    density(cap; rng=nothing, strict=false) do ctx … end

As `eager`, but a MIXED_TILED density-matrix context.
"""
function density(f, capacity::Integer; rng=nothing, strict::Bool=false)
    ctx = DensityMatrixContext(capacity; rng=rng, strict=strict)
    try
        return with(CURRENT_CONTEXT => ctx) do
            _enter_region!(ctx)
            ok = false
            val = nothing
            try
                val = f(ctx)
                ok = true
                return val
            finally
                _exit_region!(ctx, ok ? val : nothing)
            end
        end
    finally
        teardown!(ctx)
    end
end
