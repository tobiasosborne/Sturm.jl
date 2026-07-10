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
const _RESET_KRAUS = Matrix{ComplexF64}[
    ComplexF64[1 0; 0 0],   # |0⟩⟨0|
    ComplexF64[0 1; 0 0],   # |0⟩⟨1|
]

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
"""
function apply_channel!(ctx::DensityMatrixContext, kmats::Vector{Matrix{ComplexF64}}, w::WireID)
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
const _PINCH_KRAUS = Matrix{ComplexF64}[
    ComplexF64[1 0; 0 0],   # |0⟩⟨0|
    ComplexF64[0 0; 0 1],   # |1⟩⟨1|
]

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
