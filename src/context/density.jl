# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M2 (bead Sturm.jl-dc6i): a MINIMAL
# but real `DensityMatrixContext` — one `state_t` of `type = MIXED_TILED`,
# unitary `Ad` as conjugation `ρ ← UρU†` through the SAME ZYZ named-gate path
# (Orkan dispatches PURE/MIXED internally — audit §1), 1-local Kraus channels
# (`channel_1q`), and an EXACT partial trace. Enough for M3's Choi harness (DM
# executes channels ⇒ Choi is deterministic in one pass). We do NOT bind the
# header-private tiled-DM general-matrix entry (tiled-only, LOG_TILE_DIM-coupled
# — audit §8.5, the biggest M2 risk); everything lowers through the public ZYZ
# named-gate path. No multi-qubit channels (audit §8.4 — 1-local only).
#
# EXACT ptrace via the reset channel: the trace-and-reset channel with Kraus
# {|0⟩⟨0|, |0⟩⟨1|} maps `ρ ↦ ptrace_s(ρ) ⊗ |0⟩⟨0|_s` — the survivors' reduced
# state is the exact partial trace (no RNG, no collapse), and the slot returns
# to |0⟩ for recycling. Reuses `channel_1q`, which is DM-native and 1-local.
#
# Physics/spec grounding: PRD-v2 §3.9 ("Density contexts trace exactly"), §4.3.

"""
    DensityMatrixContext

A density-matrix context (`ORKAN_MIXED_TILED`) over one Orkan `state_t`. Shares
the entire `Ad` emitter with `EagerContext` (conjugation vs pure evolution is
Orkan-internal). Construct via `density(cap) do ctx … end` (regions.jl).
"""
struct DensityMatrixContext <: AbstractContext
    core::ContextCore
end

"""
    DensityMatrixContext(capacity; rng=nothing, strict=false)

Allocate a `capacity`-qubit MIXED_TILED state in |0…0⟩⟨0…0|.
"""
function DensityMatrixContext(capacity::Integer; rng=nothing, strict::Bool=false)
    st = _state_new(ORKAN_MIXED_TILED, Int(capacity))
    return DensityMatrixContext(ContextCore(st, ORKAN_MIXED_TILED, Int(capacity); rng=rng, strict=strict))
end

# The trace-and-reset (|0⟩) channel: K0=|0⟩⟨0|, K1=|0⟩⟨1|. ρ ↦ ptrace ⊗ |0⟩⟨0|.
# DERIVED from the canonical M11 channel value (S8 re-homing, principle 13):
# `reset_channel()` in channel/channel_values.jl is the single definition.
const _RESET_KRAUS = kraus_matrices(reset_channel())

"""
    _apply_channel_1q!(ctx::DensityMatrixContext, kmats, qubit)

Apply a 1-local channel given by 2×2 Kraus matrices `kmats` to Orkan `qubit`.
Builds the Julia-owned row-major Kraus buffer (under `GC.@preserve`), converts
via `kraus_to_superop`, applies the guarded `channel_1q`, and frees the
Orkan-`calloc`'d superop buffer with `Libc.free` in a `finally` (there is no
`superop_free` — audit §5).
"""
function _apply_channel_1q!(ctx::DensityMatrixContext, kmats::Vector{Matrix{ComplexF64}}, qubit::Int)
    nterms = length(kmats)
    nterms >= 1 || error("channel: need ≥1 Kraus operator")
    buf = Vector{ComplexF64}(undef, 4 * nterms)
    for (t, K) in enumerate(kmats)
        size(K) == (2, 2) || error("channel: 1q Kraus operators must be 2×2 (got $(size(K)))")
        o = 4 * (t - 1)
        buf[o+1] = K[1, 1]; buf[o+2] = K[1, 2]   # row-major
        buf[o+3] = K[2, 1]; buf[o+4] = K[2, 2]
    end
    GC.@preserve buf begin
        kr = OrkanKrausRaw(UInt8(1), ntuple(_ -> UInt8(0), 7), UInt64(nterms), pointer(buf))
        sop = orkan_kraus_to_superop(kr)
        try
            orkan_channel_1q!(_core(ctx).state, sop, qubit)
        finally
            sop.data != C_NULL && Libc.free(sop.data)
        end
    end
    nothing
end

"""
    apply_channel!(ctx::DensityMatrixContext, kmats, w::WireID)

Apply a 1-local Kraus channel (2×2 operators) to wire `w`. Flushes `w` first
(fusion commutes only with disjoint ops). M2 scaffold for M3/M11 noise & Choi.

GUARDRAIL 1 (§3.5, row 9 of the `src/surface/when.jl` dispatch table; bead
Sturm.jl-udtl): noise inside a `when` body is a LOUD error. A Kraus channel is
not a process value, and control on a non-unitary effect is unrepresentable by
axiom P4 — applying it unconditionally under a live control frame is silently
wrong physics (the wm28 class). This entry point is `public`, hence reachable as
`Sturm.apply_channel!`, so the ban must be enforced here and not merely lint-ed.

PLACEMENT — the guard belongs at THIS public noise entry point, NOT at the shared
`_apply_channel_1q!` lowering. That lowering serves three callers, and each one's
legitimacy under control is decided by the CALLER, never by the lowering:

- this one (row 9) — BANNED under control, by the assert below;
- `trace_wire!`/`_RESET_KRAUS` — the explicit `ptrace!` carries its OWN
  `_assert_no_control` (regions.jl), while the IMPLICIT region-exit release of
  body-owned scratch is the SANCTIONED §3.9 path under control (row 8);
- `_instrument!`/`_PINCH_KRAUS` — the qc cast's channel denotation, whose ban
  lives at the cast (casts.jl).

Guarding the shared lowering would therefore encode a caller's policy in a
primitive. It is also not currently redundant-but-harmless in the way it looks:
today the row-8 release under control takes `_trace_and_free!`'s no-measurement
branch (abstract.jl) and never reaches this lowering — but tracing a
certified-clean ancilla under control IS legal physics, so a DM lowering that did
run the reset channel there must not be pre-banned by a primitive. Both halves are
pinned in `test/test_m5_when.jl`: the row-9 ban, and the no-over-fire battery
(reset, pinch, uncontrolled noise, row-8 region exit) with a white-box pin that
`_apply_channel_1q!` itself stays unguarded.
"""
function apply_channel!(ctx::DensityMatrixContext, kmats::Vector{Matrix{ComplexF64}}, w::WireID)
    _assert_no_control(ctx, "noise channel apply_channel!")
    _flush_wire!(ctx, w)
    _apply_channel_1q!(ctx, kmats, q(ctx, w))
    return ctx
end

"""
    trace_wire!(ctx::DensityMatrixContext, w)

EXACT partial trace of wire `w` via the reset channel: `ρ ↦ ptrace_w(ρ) ⊗
|0⟩⟨0|_w`. Deterministic (no RNG); the slot returns to |0⟩ for recycling.
"""
function trace_wire!(ctx::DensityMatrixContext, w::WireID)
    _flush_all!(ctx)
    _apply_channel_1q!(ctx, _RESET_KRAUS, _core(ctx).wire_to_slot[w])
    nothing
end

"""
    density_matrix(ctx::DensityMatrixContext) -> Matrix{ComplexF64}

The current `2^capacity × 2^capacity` density matrix (flushes pending fusion).
Test/readout use.
"""
function density_matrix(ctx::DensityMatrixContext)
    _flush_all!(ctx)
    return _density(_core(ctx).state, _core(ctx).capacity)
end

# The complete-dephasing (pinching) Kraus set {P0, P1} = {|0⟩⟨0|, |1⟩⟨1|}: the
# CHANNEL denotation of the qc measurement cast with its classical bit traced out
# (§3.8). CPTP. Distinct from `_RESET_KRAUS`, which resets to |0⟩; the pinch
# leaves the diagonal in place and kills only the coherences.
# DERIVED from the canonical M11 channel value (S8 re-homing, principle 13):
# `pinch_channel()` in channel/channel_values.jl is the single definition.
const _PINCH_KRAUS = kraus_matrices(pinch_channel())

"""
    _instrument!(ctx::DensityMatrixContext, w::WireID)

Apply the pinching (complete-dephasing) channel to wire `w` in place — the
CHANNEL denotation of the qc measurement cast on a density context (§3.8: DM
executes channels, so `cq∘qc = pinching` is realized exactly in one pass, no
sampling). `ρ ↦ Σ_b P_b ρ P_b` kills the off-diagonal (basis) coherences and
leaves the wire live (NOT consumed, NOT reset). Reuses the M2 1-local
`_apply_channel_1q!` / `channel_1q`. INTERNAL — the M3 Choi harness reaches it as
`Sturm._instrument!`; M8's `@cases` will reuse the same denotation.
"""
function _instrument!(ctx::DensityMatrixContext, w::WireID)
    _flush_wire!(ctx, w)
    _apply_channel_1q!(ctx, _PINCH_KRAUS, q(ctx, w))
    nothing
end

"""
    _instrument_record!(ctx::DensityMatrixContext, w::WireID) -> WireID

The DM measurement cast's record realization (Ruling D, M8 i4ri design §2.1): pinch
wire `w` in place (`_instrument!` — the classical record Σᵢ|i⟩⟨i|_C ⊗ ρ̃ᵢ, kept
LIVE, no reset), then split the ONE physical slot's two roles:

- the QUANTUM handle DIES (affine): `w` is removed from `wire_to_slot` and marked
  consumed on the single-sourced set (§4.5), so any later quantum use of the
  original handle — `Bool(q)` again, `not!(q)`, `apply!(…, w)` — fails loud (law L1);
- the CLASSICAL RECORD lives on: a FRESH `WireID` `rec` re-homes the SAME Orkan
  slot and is registered in the enclosing region's owned set, so the record is
  traced (summed) at region exit unless `discard!`ed first (last-use, design §2.2).

Returns `rec`, the token's record-wire handle. No new physics primitive — reuses
the shipped pinch + slot bookkeeping. The measured wire is "still-live c-wire",
NEVER "an ordinary quantum handle" (design §6).
"""
function _instrument_record!(ctx::DensityMatrixContext, w::WireID)
    _instrument!(ctx, w)                              # pinch; the record stays on the slot
    core = _core(ctx)
    slot = core.wire_to_slot[w]
    delete!(core.wire_to_slot, w)                     # the quantum identity dies (affine)
    mark_consumed!(ctx, w)                            # single-sourced consumed set (§4.5)
    core.wire_counter += 1
    rec = WireID(core.wire_counter)
    core.wire_to_slot[rec] = slot                     # the record lives on the SAME slot, new identity
    isempty(core.region_stack) || push!(core.region_stack[end], rec)  # region owns it → summed at exit
    return rec
end
