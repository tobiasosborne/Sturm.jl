# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M2 (bead Sturm.jl-dc6i): the
# `AbstractContext` interface and the shared `ContextCore` — everything a
# concrete context (Eager / DensityMatrix) inherits by composition. The key
# structural fact (audit §1.3): Orkan's gate functions dispatch on state type
# INTERNALLY, so the SAME gate sequence realises `Ad` as `UψU†` (PURE) and as
# `UρU†` (MIXED). Therefore both contexts share the ENTIRE primitive-gate
# vocabulary and the whole `Ad` emitter (ad.jl); they differ ONLY in storage
# type, trace lowering (`trace_wire!`), and channel support. One `state_t` per
# context (a pre-sized register file); wires are SLOTS inside it (audit §5).
#
# WIRE↔ORKAN-INDEX PIN (§3.3, the classic silent killer): `q(ctx, wire)` is the
# SINGLE source of truth for the slot map. Orkan is little-endian (verified:
# qubit `j` addresses bit `j`; the MSB wire is the highest slot). The reference
# harness embeds a value's denoted matrix through this same map — so a bit-order
# slip localises to exactly one function. `q` is used nowhere else.
#
# Physics/spec grounding: PRD-v2 §3.9 (scope/regions), §4.2/§4.3 (Ad, ctrl
# choke point), §4.5 (single-sourced consumed set), §8.4 (aliasing on identity);
# `docs/design/orkan-abi-audit-m2.md`.

"""
    AbstractContext

Supertype of every execution context. A concrete context holds a `ContextCore`
(`ctx.core`) and provides `trace_wire!` (the §3.9 partial-trace lowering) plus,
for density contexts, channel support. The interface (public where marked):
`allocate!`, `deallocate!`/`ptrace!`, `apply!`, `q`, `consumed`/`mark_consumed!`,
`rng`, `teardown!`, `live_wires`.
"""
abstract type AbstractContext end

"""
    ContextCore

The per-context register file and bookkeeping, shared by all concrete contexts
via composition (Julia structs do not inherit fields; a shared inner struct is
the idiomatic alternative). Fields:

- `state` — the ONE Orkan `state_t` (PURE or MIXED); freed once, at teardown.
- `storage`, `capacity` — storage-type tag and the fixed qubit capacity.
- `high_water`, `free_slots` — slot allocator; recycled slots re-enter as |0⟩.
- `wire_to_slot` — the `q(ctx,·)` map (§3.3), the sole wire→Orkan-index truth.
- `consumed` — the SINGLE-SOURCED linearity set (§4.5); qc casts (M3) and
  `ptrace!` are its only writers.
- `fusion` — per-wire 1q `U2` accumulator, flushed at any entangling/measure/
  trace/readout boundary (a `U2∘U2` fuse is exact — Hamilton product).
- `region_stack` — per-region owned-wire frames (§3.9 exit trace).
- `control_stack` — the M5 `when` coherent-control frames (PRD-v2 §3.5/D13): a
  FLAT `Vector{WireID}` of the live control wires (parent-resolved). Depth `k`
  ⇒ the action family lowers each op as `ctrl^k` via `_act!` (surface/when.jl);
  nested controls commute (Delorme Eq 14) so a flat vector IS the faithful
  normal form. Consulted at three funnels: `_act!` (wrap + guardrail 2),
  `_assert_no_control` (guardrail 1: cast/trace/noise under control), and
  `_trace_and_free!` (the §3.9 clean-ancilla witness). Rides the ctx object
  into `Threads.@spawn` children exactly as `region_stack` does.
- `parent`, `strict` — the D10 lost-binding detector (M6): `parent` maps a
  fresh-output child wire to the value-world entangling-parent wires that fed it
  (a `Vector` because `x + y` has two sources per output wire); `strict` arms the
  region-exit check (`_strict_check!`, regions.jl). Written ONLY by value-world
  ring ops under `strict`; inert (empty) on the default path.
- `wire_counter` — monotone id source for fresh `WireID`s (never reused).
- `rng` — Julia-owned reproducibility (Orkan has no RNG, audit §6); `nothing`
  means the task-global default. Untyped: the measure-and-discard path is cold,
  and typing it would force a `Random` dependency `src/` may not take.
- `closed` — lifecycle flag (F16 §5.1): set by `teardown!` when the Orkan
  `state_t` is freed. A handle returned from `eager do … end` stores this
  torn-down context; rebinding it with `@context` would otherwise reach freed
  FFI storage, so `_require_open` (via `_here`) fails LOUD before any state
  read/alloc/FFI touch. A pure safety check — it never alters a live channel.
- `when_frames` — the M8 EAGER TEE-TRACING stack (bead szx1, design §5): one
  `WhenFrame` per live `when` region. While a `when` body streams, its ops are
  ALSO tee-recorded into the top frame's `DAGBuilder`; at body exit the transcript
  is structurally SEALED — the certificate, not a runtime marginal, is the
  clean-ancilla witness (F1/D13). EMPTY on the default path (zero overhead when
  not under `when`; the element type is `Any` so `abstract.jl` needs no M8/`when.jl`
  forward reference — the concrete `WhenFrame` lives in `surface/when.jl`).
- `poison` — the TR2 FAILURE TOPOLOGY (design §8/TR2): a streaming Eager `when`
  runs effects BEFORE its late seal, so a FAILED seal cannot be unwound. On seal
  failure the context is POISONED (this field set to the seal's error message) and
  every subsequent surface op fails loud (via `_require_open`) naming the original
  seal failure. `nothing` on the healthy path.
"""
mutable struct ContextCore
    state::OrkanStateRaw
    storage::Cint
    capacity::Int
    high_water::Int
    free_slots::Vector{Int}
    wire_to_slot::Dict{WireID,Int}
    consumed::Set{WireID}
    fusion::Dict{WireID,U2}
    region_stack::Vector{Vector{WireID}}
    control_stack::Vector{WireID}
    parent::Dict{WireID,Vector{WireID}}
    strict::Bool
    wire_counter::Int
    rng::Any
    closed::Bool
    when_frames::Vector{Any}
    poison::Union{Nothing,String}
end

function ContextCore(state::OrkanStateRaw, storage::Cint, capacity::Int; rng=nothing, strict::Bool=false)
    return ContextCore(state, storage, capacity, 0, Int[], Dict{WireID,Int}(),
        Set{WireID}(), Dict{WireID,U2}(), Vector{WireID}[], WireID[],
        Dict{WireID,Vector{WireID}}(), strict, 0, rng, false, Any[], nothing)
end

"""
    _require_open(ctx, op) -> ctx

Fail loud if `ctx`'s Orkan `state_t` has been torn down (F16 §5.1). Called by
`_here` before any operation touches state — a dangling handle from a closed
`eager`/`density` block must not reach freed FFI storage. ErrorException (a
lifecycle/liveness failure, not a well-formed-but-forbidden op — S13).
"""
@inline function _require_open(ctx::AbstractContext, op::AbstractString)
    core = _core(ctx)
    core.closed && error(
        "$op: the owning context has been torn down (its Orkan state is freed) — " *
        "this is a dangling handle from a closed `eager`/`density` block (F16 §5.1).")
    core.poison === nothing || error(
        "$op: this context is POISONED and unusable — a `when` body failed to seal " *
        "structurally (design TR2). Streaming Eager `when` runs effects before its " *
        "late seal, so a failed seal cannot be unwound; the context is dead. Original " *
        "seal failure: $(core.poison)")
    return ctx
end

"""
    _core(ctx) -> ContextCore

The shared core of any concrete context (which stores it in a `core` field).
"""
_core(ctx::AbstractContext) = ctx.core

# --- Slot allocator (low-level; no region/consumed bookkeeping) ---------

function _take_slot!(core::ContextCore)
    isempty(core.free_slots) || return pop!(core.free_slots)
    core.high_water < core.capacity ||
        error("context capacity ($(core.capacity) wires) exceeded — grow the `eager(cap)`/`density(cap)` capacity")
    s = core.high_water
    core.high_water += 1
    return s
end

# Recycled slots are already |0⟩ (measure-and-flip on trace, or matched
# compute/uncompute for scratch) — the "fresh = |e_G⟩" invariant holds.
_return_slot!(core::ContextCore, s::Int) = push!(core.free_slots, s)

# Kernel-internal scratch ancillas (ad.jl): raw slots, NOT registered in any
# region owned set and NOT given a WireID — a pure kernel borrow.
_alloc_scratch!(core::ContextCore) = _take_slot!(core)
_free_scratch!(core::ContextCore, s::Int) = _return_slot!(core, s)

# --- Wire lifecycle -----------------------------------------------------

"""
    allocate!(ctx) -> WireID

Allocate a fresh wire in the canonical state |0⟩ = |e_G⟩ (§3.9 "allocation is
initialization"). The wire is registered in the enclosing region's owned set
(if any), so region exit will trace it unless it is consumed or returned first.
"""
function allocate!(ctx::AbstractContext)
    core = _core(ctx)
    slot = _take_slot!(core)
    core.wire_counter += 1
    w = WireID(core.wire_counter)
    core.wire_to_slot[w] = slot
    isempty(core.region_stack) || push!(core.region_stack[end], w)
    # M8 EAGER TEE-TRACING (design §5): a wire born under a live `when` frame is
    # body-owned SCRATCH — record its AllocN so the body-exit seal can match it to
    # a certified trace (forward-ref to `surface/when.jl`; gated to zero overhead).
    isempty(core.when_frames) || _tee_record_alloc!(ctx, w)
    return w
end

"""
    q(ctx, w::WireID) -> Int

The Orkan slot (qubit index) of a live wire — THE wire↔index map (§3.3). Errors
loud on a dead/unknown wire (using a traced or consumed handle is a bug).
"""
function q(ctx::AbstractContext, w::WireID)
    core = _core(ctx)
    haskey(core.wire_to_slot, w) ||
        error("wire $w is not live in this context (already traced/consumed, or from another context)")
    return core.wire_to_slot[w]
end

live_wires(ctx::AbstractContext) = collect(keys(_core(ctx).wire_to_slot))

# --- Linearity bookkeeping (single-sourced, §4.5) ----------------------

consumed(ctx::AbstractContext) = _core(ctx).consumed
is_consumed(ctx::AbstractContext, w::WireID) = w in _core(ctx).consumed
mark_consumed!(ctx::AbstractContext, w::WireID) = (push!(_core(ctx).consumed, w); nothing)

# --- Control stack (M5 `when`, §3.5/D13) --------------------------------
#
# The push/pop machinery `when` (surface/when.jl) drives, mirroring
# `region_stack`. `_act!` (the control-aware apply! sibling), the guardrail-1
# assertion, and the clean-ancilla witness all read `control_stack`; see
# surface/when.jl for the semantics and the physics licenses. INTERNAL.

"`true` iff a `when` control frame is live (the action family must control ops)."
_under_control(ctx::AbstractContext) = !isempty(_core(ctx).control_stack)

"Push a (parent-resolved) control wire; `when` pairs this with a `finally` pop."
_push_control!(ctx::AbstractContext, w::WireID) = (push!(_core(ctx).control_stack, w); nothing)

"""
    _pop_control!(ctx, w)

Pop the control frame, asserting LIFO integrity (`last === w`). A fired assert
means a `try`/`finally` nesting bug corrupted the stack — a fail-loud tripwire,
never a silent `pop!` (CLAUDE.md #1).
"""
function _pop_control!(ctx::AbstractContext, w::WireID)
    cs = _core(ctx).control_stack
    (!isempty(cs) && last(cs) === w) ||
        error("control-stack LIFO violation popping $w (top = $(isempty(cs) ? "∅" : last(cs))) — a `when` try/finally nesting bug")
    pop!(cs)
    nothing
end

"""
    _assert_no_control(ctx, what)

Guardrail 1 (§3.5): a non-unitary effect (`what`) attempted while a `when`
control frame is live is a LOUD error, thrown BEFORE any backaction. Control on
a measurement / trace / noise channel is unrepresentable by axiom P4 (§4.4);
the body must trace to a unitary-witnessed value (Yuan–Villanyi–Carbin Thm 4.4
No-Embedding; Bădescu–Panangaden reversibility Condition III, p.35). This is the
v0.1 §8.1 "most dangerous hole", promoted from a lint to a semantic law.
"""
function _assert_no_control(ctx::AbstractContext, what::AbstractString)
    _under_control(ctx) && error(
        "$what is forbidden inside a `when` body (guardrail 1, §3.5 / §4.4): a " *
        "control frame is live, and control on a non-unitary effect (measurement, " *
        "trace, noise) is unrepresentable by axiom P4 — the body must trace to a " *
        "unitary-witnessed value (Yuan–Villanyi–Carbin Thm 4.4; Bădescu–Panangaden " *
        "Condition III, p.35). This is the v0.1 §8.1 regression, closed by law.")
    nothing
end

# --- RNG / teardown -----------------------------------------------------

rng(ctx::AbstractContext) = _core(ctx).rng
_draw(core::ContextCore)::Float64 = core.rng === nothing ? rand() : rand(core.rng)

"""
    teardown!(ctx)

Free the context's Orkan `state_t` (once). Called by the `eager`/`density`
resource form's `finally` — NEVER from a GC finalizer (audit §5: finalizer +
FFI is unsafe; runs in arbitrary GC contexts). `state_free` is NULL-safe/
idempotent, so a stray double-call is harmless, but the invariant is single-free.
"""
function teardown!(ctx::AbstractContext)
    core = _core(ctx)
    core.closed && return nothing          # idempotent (state_free is NULL-safe too)
    orkan_state_free!(core.state)
    core.closed = true                     # arm the dangling-handle guard (F16 §5.1)
    return nothing
end

# --- Primitive gate vocabulary (what the Ad emitter lowers to) ----------
#
# Each takes Orkan qubit indices (Ints) and calls the guarded FFI wrapper on
# the one shared `state_t`. Because Orkan dispatches PURE/MIXED internally, the
# SAME emitter serves both contexts (Ad on ψ, conjugation on ρ).

for (g, sym) in ((:_emit_x!, :orkan_x!), (:_emit_y!, :orkan_y!), (:_emit_z!, :orkan_z!),
                 (:_emit_h!, :orkan_h!), (:_emit_s!, :orkan_s!), (:_emit_t!, :orkan_t!))
    @eval $g(ctx::AbstractContext, target::Int) = $sym(_core(ctx).state, target)
end
for (g, sym) in ((:_emit_rx!, :orkan_rx!), (:_emit_ry!, :orkan_ry!),
                 (:_emit_rz!, :orkan_rz!), (:_emit_p!, :orkan_p!))
    @eval $g(ctx::AbstractContext, target::Int, θ::Real) = $sym(_core(ctx).state, target, θ)
end
# The 2q/3q (entangling) emitters live in `orkan/ad.jl` — the single confined
# ctrl-lowering site the choke-point grep-lint requires; see there.

# --- 1q fusion buffer ---------------------------------------------------

"""
    _fuse!(ctx, w, u)

Accumulate a 1q `U2` on wire `w` into the per-wire fusion buffer. `u` applies
AFTER any pending op `P`, so the buffered value becomes `u ∘ P` (exact Hamilton
fuse). Nothing reaches Orkan until a flush.
"""
function _fuse!(ctx::AbstractContext, w::WireID, u::U2)
    core = _core(ctx)
    core.fusion[w] = haskey(core.fusion, w) ? u ∘ core.fusion[w] : u
    return ctx
end

"""
    _flush_wire!(ctx, w)

Emit (via ZYZ) and clear any pending fused 1q op on wire `w`. Called before any
op that entangles/measures/reads `w`.
"""
function _flush_wire!(ctx::AbstractContext, w::WireID)
    core = _core(ctx)
    if haskey(core.fusion, w)
        u = pop!(core.fusion, w)
        _emit_u2!(ctx, u, core.wire_to_slot[w])
    end
    nothing
end

"""
    _flush_all!(ctx)

Flush every pending fused op — before any global readout, measurement, or trace.
"""
function _flush_all!(ctx::AbstractContext)
    core = _core(ctx)
    for w in collect(keys(core.fusion))
        _flush_wire!(ctx, w)
    end
    nothing
end

# --- Trace-and-free (generic; `trace_wire!` is per concrete type) -------

"""
    _trace_and_free!(ctx, w)

Lower the partial trace of wire `w` (measure-and-discard on Eager, exact reset
channel on DM — `trace_wire!`), leaving its slot in |0⟩, then retire the
`WireID` and recycle the slot. Silent, no backaction (§3.9 principled exception
to FAIL-LOUD).
"""
function _trace_and_free!(ctx::AbstractContext, w::WireID)
    core = _core(ctx)
    haskey(core.wire_to_slot, w) || error("cannot trace wire $w: not live in this context")
    if isempty(core.control_stack)
        trace_wire!(ctx, w)                 # measure-and-discard (Eager) / exact ptrace (DM)
    else
        # A body-owned ancilla leaving a `when` region (M8 design §5). The WITNESS
        # is now the STRUCTURAL body-exit seal (`_seal_when_frame!`, surface/when.jl),
        # not this per-run marginal: record a TraceN into the tee-frame so the seal
        # can verify a matched compute/uncompute (F1 — a state marginal cannot certify
        # a universally-quantified containment). The DEMOTED marginal survives as a
        # DEBUG cross-check (`_clean_ancilla_debug!`), off by default. A clean ancilla
        # is freed WITHOUT measuring (certified |0⟩); if the later seal fails, the
        # context is poisoned (TR2) so this early free is never observed.
        isempty(core.when_frames) || _tee_record_trace!(ctx, w, nothing)
        _clean_ancilla_debug!(ctx, w)
    end
    slot = core.wire_to_slot[w]
    delete!(core.wire_to_slot, w)
    _return_slot!(core, slot)
    nothing
end

deallocate!(ctx::AbstractContext, w::WireID) = _trace_and_free!(ctx, w)
