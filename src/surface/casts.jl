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
    Bool(q::QBool) -> Bool | ClassicalBit

The MEASUREMENT cast (qc, §3.2), THE measurement spelling in every context
(Ruling D, §3.6/§14 — no separate `measure` verb). It denotes the q→c channel;
its RETURN is the classical system that channel outputs, represented as faithfully
as the context allows:

- EAGER (a point state IS its value): a real `Bool`. Measures in the computational
  basis, CONSUMES the handle (single-sourced consumed set, §4.5), recycles the
  slot, returns the outcome (M3 behaviour, unchanged).
- DM (a distribution inside ρ): a `ClassicalBit` TOKEN — a handle to the pinched,
  still-live classical record Σᵢ|i⟩⟨i|_C ⊗ ρ̃ᵢ (`_instrument!`, no new primitive).
  Branch on it with `cases`; the record is summed at region exit / `discard!`.

The context-varying return is inference-clean because `_here` returns the concrete
`C` (F16), so `_cast_bool(ctx::C, …)` dispatches statically. Explicit `Bool(q)`
does NOT warn; only the implicit `convert(Bool, q)` path warns/throws (P2, Ruling
D: `convert(Bool,·)` stays Eager-honest).
"""
function Base.Bool(q::AbstractQubit{C}) where {C}
    ctx = _here(q)
    # Guardrail 1 (§3.5): measurement under a live `when` control is a loud error
    # BEFORE any backaction — measurement-under-ctrl is unrepresentable (§4.4).
    _assert_no_control(ctx, "measurement cast Bool(q)")
    _assert_live(ctx, q.wire)
    return _cast_bool(ctx, q.wire)      # Eager: Bool (measure+consume); DM: ClassicalBit token
end

"""
    _cast_bool(ctx::EagerContext, w) -> Bool

The Eager (trajectory) qc: sample+collapse+retire (`_measure_wire!`), then mark
the handle consumed on the single-sourced set (§4.5). The DM sibling
(`_cast_bool(::DensityMatrixContext, …)` → `ClassicalBit`) lives in
surface/tokens.jl, alongside the token type it builds (Ruling D).
"""
function _cast_bool(ctx::EagerContext, w::WireID)
    b = _measure_wire!(ctx, w)
    mark_consumed!(ctx, w)
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

# NOTE (M8, Ruling D): the former `_measure_wire!(::DensityMatrixContext, …)` LOUD
# placeholder (a scalar outcome is a trajectory, not a channel) is RETIRED. Under
# §14 Ruling D the DM measurement cast returns the classical RECORD as a
# `ClassicalBit`/`ClassicalWord` token (`_cast_bool`/`_cast_int(::DensityMatrixContext,
# …)`, surface/tokens.jl) via `_instrument_record!` (density.jl) — no scalar, no
# throw. `_measure_wire!` now exists ONLY on `EagerContext` (the trajectory unravel).

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
function Base.convert(::Type{Bool}, q::AbstractQubit)
    @warn "implicit measurement of a QBool (P2): a quantum→classical cast " *
          "collapses state — write `Bool(q)` explicitly to silence this"
    return Bool(q)
end
