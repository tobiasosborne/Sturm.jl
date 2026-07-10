# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M3 (bead Sturm.jl-77m2): the
# MEASUREMENT cast (qc, PRD-v2 §3.2) — `Bool(q::QBool)`, the consuming
# quantum→classical boundary. The handle DIES at the cast: after collapse the
# information is classical, and a live quantum handle to it would be a type lie
# (§3.2). Consumption is recorded on the context's SINGLE-SOURCED consumed set
# (§4.5) — the same set `ptrace!` writes, so use-after-consume, double-consume,
# and region-exit trace are ONE mechanism, never the v0.1 §8.5 desync of drifting
# flags.
#
# Eager vs DM (the one place they diverge): a `Bool(q)` returns a definite scalar
# outcome. On a PURE (Eager) context that is a trajectory unraveling — sample,
# collapse, retire. On a MIXED (density) context a scalar outcome is a
# TRAJECTORY, not a channel, and "DM executes channels, not trajectories" (§3.8)
# — so DM `Bool` fails loud (ArgumentError), deferring scalar lifting to the D3
# classical-token machinery (M8 `cases`/tokens). The channel denotation of qc on
# DM (the pinching instrument) is available for the Choi harness via
# `_instrument!` (density.jl), not as surface `Bool`.
#
# P2 (implicit casts warn): the ONLY implicit measurement in M3 is the
# compiler-inserted `Base.convert(Bool, ::QBool)` (assignment into a `Bool` slot,
# `Vector{Bool}` insertion, a `::Bool`-annotated return). That path @warns (it
# has BACKACTION — collapse — §3.9's rule: implicit ops WITH backaction warn;
# only backaction-free traces are silent) then measures. Explicit `Bool(q)` is
# silent (the user asked). Neither is type piracy — `QBool` is ours.
#
# Physics/spec grounding: PRD-v2 §3.2 (boundary algebra), §3.8 (DM executes
# channels), §3.9 (regions; backaction-warn rule), §4.5 (single-sourced
# consumption), §4.4/D3 (measurement scalars route through tokens), S13 (error
# taxonomy: DomainError / ArgumentError / error()+identity).

"""
    _assert_live(ctx, w::WireID)

Fail loud if wire `w` cannot be measured: already consumed (use-after-consume /
double-consume) or not live in this context (retired, e.g. traced at region
exit). Both are `error()` carrying the register identity — a linearity/liveness
guardrail (S13). The cross-context case is caught EARLIER, in `Bool`, by the
`q.ctx === current_context()` identity check (ArgumentError).
"""
function _assert_live(ctx::AbstractContext, w::WireID)
    is_consumed(ctx, w) &&
        error("register $w already consumed — a measurement cast consumes its " *
              "input (§3.2/§4.5); a live handle to measured (now classical) data " *
              "is a type lie, and you cannot read it again")
    haskey(_core(ctx).wire_to_slot, w) ||
        error("register $w is not live in this context — it was traced at region " *
              "exit or otherwise retired (a dangling handle)")
    nothing
end

"""
    Bool(q::QBool) -> Bool

The MEASUREMENT cast (qc, §3.2). Measures `q` in the computational basis,
CONSUMES the handle (records it on the single-sourced consumed set, §4.5),
recycles the wire's slot, and returns the outcome. Eager-only in M3: on a
density context a scalar outcome is a trajectory (not a channel) and throws
(ArgumentError, D3/§3.8 — use `@cases`/tokens (M8) or the Choi harness). Explicit
`Bool(q)` does NOT warn; the implicit `convert(Bool, q)` path does (P2).
"""
function Base.Bool(q::QBool)
    ctx = q.ctx
    ctx === current_context() ||
        throw(ArgumentError("Bool(q): register $(q.wire) belongs to a different " *
            "context than the active one — a handle escaped its context/region. " *
            "(Handles store their owning context precisely to catch this: WireIDs " *
            "are per-context, so id collisions across contexts would otherwise " *
            "silently target the wrong qubit.)"))
    _assert_live(ctx, q.wire)
    b = _measure_wire!(ctx, q.wire)     # Eager: sample+collapse+retire; DM: throws
    mark_consumed!(ctx, q.wire)         # single-sourced set (§4.5) — reached only on Eager success
    return b
end

"""
    _measure_wire!(ctx::EagerContext, w::WireID) -> Bool

The Eager qc unraveling: the M2 measure-and-discard trace path MINUS the discard
— it KEEPS the drawn outcome (reusing `trace_wire!` would draw and throw the
outcome away, then a second draw would double-advance the RNG). Flush, draw `w`'s
outcome from the context RNG over its marginal, projectively collapse+
renormalize, reset the slot to |0⟩ (measure-and-flip, the "fresh = |e_G⟩"
recycle invariant), retire the wire and recycle the slot. All of `_flush_all!`,
`_marginal_p1`, `_draw`, `_collapse!`, `_emit_x!`, `_return_slot!` are M2.
"""
function _measure_wire!(ctx::EagerContext, w::WireID)::Bool
    core = _core(ctx)
    _flush_all!(ctx)                            # realize all pending 1q fusion first
    slot = core.wire_to_slot[w]
    p1 = _marginal_p1(core.state, slot)
    out = _draw(core) < p1 ? 1 : 0
    _collapse!(core.state, slot, out)
    out == 1 && _emit_x!(ctx, slot)             # |1⟩→|0⟩ so the recycled slot is |0⟩
    delete!(core.wire_to_slot, w)
    _return_slot!(core, slot)
    return out == 1
end

"""
    _measure_wire!(ctx::DensityMatrixContext, w::WireID)

Fails loud: a scalar `Bool` outcome on a density (channel-executing) context is a
TRAJECTORY, not a channel (§3.8). Scalar lifting of a measurement outcome is the
D3 classical-token problem, deferred to M8 (`cases`/tokens). For the
channel-level statement (`cq∘qc = pinching`), use the Choi harness, which
measures the instrument channel directly (`_instrument!`, density.jl).
"""
_measure_wire!(::DensityMatrixContext, w::WireID) =
    throw(ArgumentError("Bool(q) returns a scalar outcome, which on a " *
        "density-matrix context is a trajectory, not a channel (§3.8: a " *
        "DensityMatrixContext executes channels, not trajectories). Scalar " *
        "lifting of a measurement outcome is the D3 classical-token problem, " *
        "deferred to M8 (`@cases`/tokens). For the channel-level cq∘qc=pinching " *
        "statement, use the Choi harness (it measures the instrument channel)."))

"""
    convert(::Type{Bool}, q::QBool) -> Bool

The IMPLICIT measurement cast (P2). The compiler inserts `convert` at
`Bool`-typed assignment/return/collection sites; unlike explicit `Bool(q)` this
is not the user asking, so it WARNS (implicit op WITH backaction — measurement
collapses — §3.9) then performs the measurement. Write `Bool(q)` to make the
measurement explicit and silence this. Deliberately NOT `maxlog`-deduped: a
collapse is a physical event and every one is worth naming (CLAUDE.md #1 FAIL
LOUD), and a per-site dedup makes the warning non-deterministic to test.
"""
function Base.convert(::Type{Bool}, q::QBool)
    @warn "implicit measurement of a QBool (P2): a quantum→classical cast " *
          "collapses state — write `Bool(q)` explicitly to silence this"
    return Bool(q)
end
