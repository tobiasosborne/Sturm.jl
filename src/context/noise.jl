# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M11 (bead Sturm.jl-qmpo), design
# `docs/design/m11-82su-synthesis.md` §3.1/§3.2 (rulings S3, S12, S13, S16,
# S29): APPLICATION of channel values — PRD-v2 §4.3's "channel-level values
# apply through the same surface", per context:
#
#   DM      — native and EXACT: 1-local factors through Orkan's `channel_1q`
#             (the only channel entry Orkan has — V3), lazy composites
#             recursed structurally. One run IS the channel.
#   Tracing — RECORD a `NoiseN` carrying the real value; the IR holds the
#             channel, NEVER a dilation (S12).
#   Eager   — LOUD by default (a statevector cannot hold a mixed state);
#             `stinespring = true` is the explicit, greppable, per-call-site
#             opt-in (S12) that dilates + traces — ONE quantum-jump
#             unravelling per run, NOT the channel (S16). Never a context-
#             level policy.
#
# GUARDRAIL (S3, the udtl discipline): every entry here calls
# `_assert_no_control` FIRST — noise under a live control frame is guardrail 1
# (P4: control on a non-unitary effect is unrepresentable). The guard sits at
# these public entries, NEVER at the shared `_apply_channel_1q!` lowering
# (three callers, each caller's legitimacy decided by the caller — see
# `apply_channel!`'s docstring in density.jl).

"""
    apply!(ctx::AbstractContext, ch::ChannelValue, wires::NTuple{K,WireID};
           stinespring::Bool = false)

Apply the channel value `ch` to `wires` (position 1 = `ch`'s MSB wire) — the
context/wire layer of PRD-v2 §4.3's channel application (S13). Validates
control-freedom (guardrail 1 — S3), width, liveness, and wire distinctness,
then lowers per context (see the file header). `stinespring` is the pure-
context dilation opt-in (S12); it is a NO-OP on DM (native application is
exact — strictly better than dilating) and a LOUD error under Tracing (the IR
records the channel, never a dilation).
"""
function apply!(ctx::AbstractContext, ch::ChannelValue, wires::NTuple{K,WireID};
                stinespring::Bool = false) where {K}
    _assert_no_control(ctx, "noise channel application")
    K == nwires(ch) || throw(ArgumentError(
        "apply!: channel $(_chlabel(ch)) acts on $(nwires(ch)) wires but $K given"))
    for w in wires
        haskey(_core(ctx).wire_to_slot, w) || error(
            "apply!: wire $w is not live in this context (consumed, traced, or foreign)")
    end
    if K > 1
        for i in 1:K, j in (i + 1):K
            wires[i] == wires[j] && throw(ArgumentError(
                "apply!: aliased wires — positions $i and $j are both $(wires[i]); " *
                "a channel's wires must be distinct registers"))
        end
    end
    _apply_channel_value!(ctx, ch, wires, stinespring)
    return ctx
end

apply!(ctx::AbstractContext, ch::ChannelValue, wires::AbstractVector{WireID};
       stinespring::Bool = false) =
    apply!(ctx, ch, Tuple(wires); stinespring)

_chlabel(f::KrausFamily) = f.label
_chlabel(::MixedUnitary) = :mixed_unitary
_chlabel(::ChannelTensor) = :tensor
_chlabel(::ChannelSeq) = :seq

"""
    apply_noise!(q::AbstractQubit, ch::ChannelValue; stinespring=false) -> q
    apply_noise!(x::QInt{W},      ch::ChannelValue; stinespring=false) -> x

The handle layer (S13; named `apply_noise!` because `noise!` is shipped
`DAGBuilder` vocabulary — V11). On a qubit handle: `ch` must be 1-wire. On a
`QInt{W}`: a 1-wire `ch` applies i.i.d. to ALL W wires (the physical-noise
idiom); a W-wire `ch` applies across the register (wire 1 = MSB). The handle
stays LIVE — noise is a channel from the register to itself, not a cast.
"""
function apply_noise!(qb::AbstractQubit, ch::ChannelValue; stinespring::Bool = false)
    nwires(ch) == 1 || throw(ArgumentError(
        "apply_noise!: channel $(_chlabel(ch)) acts on $(nwires(ch)) wires; a qubit " *
        "handle has 1 — apply to a register, or build the 1-local factor"))
    apply!(contextof(qb), ch, (qb.wire,); stinespring)
    return qb
end

function apply_noise!(x::QInt{W}, ch::ChannelValue; stinespring::Bool = false) where {W}
    if nwires(ch) == 1
        for w in x.wires                       # i.i.d.: same 1-local factor, each wire
            apply!(contextof(x), ch, (w,); stinespring)
        end
    elseif nwires(ch) == W
        apply!(contextof(x), ch, x.wires; stinespring)
    else
        throw(ArgumentError(
            "apply_noise!: channel $(_chlabel(ch)) acts on $(nwires(ch)) wires; " *
            "QInt{$W} takes a 1-wire factor (applied i.i.d.) or a $W-wire channel"))
    end
    return x
end

# --- DM: native, exact ---------------------------------------------------------

function _apply_channel_value!(ctx::DensityMatrixContext, ch::KrausFamily{W},
                               wires::NTuple{K,WireID}, stinespring::Bool) where {W,K}
    if W == 1
        _flush_wire!(ctx, wires[1])
        _apply_channel_1q!(ctx, kraus_matrices(ch), q(ctx, wires[1]))
    else
        # k-local dense DM noise is DEFERRED in M11 (synthesis §4.2: the
        # MIXED_TILED write-back path is unverified — R5). i.i.d./local noise
        # never needs it: build a ChannelTensor of 1-local factors.
        error("apply!: a $(W)-wire dense KrausFamily has no native DM lowering in M11 " *
              "(deferred — the k-local write-back path is unverified). Represent local " *
              "noise as a ⊗ of 1-wire factors; genuinely correlated $(W)-wire noise " *
              "needs the k-local entry (see the M11 defer list).")
    end
    nothing
end

function _apply_channel_value!(ctx::DensityMatrixContext, ch::MixedUnitary{W},
                               wires::NTuple{K,WireID}, stinespring::Bool) where {W,K}
    if W == 1
        _flush_wire!(ctx, wires[1])
        _apply_channel_1q!(ctx, kraus_matrices(ch), q(ctx, wires[1]))
    elseif stinespring
        # Σᵢ wᵢ Ad_{Uᵢ} on W ≥ 2 wires: the dilation is executable for exactly
        # this class (S14 class P), and on DM the region-exit trace is EXACT —
        # the composite is the true channel, not an unravelling.
        _emit_dilation!(ctx, ch, wires)
    else
        error("apply!: a $(W)-wire MixedUnitary has no native DM lowering in M11 " *
              "(Orkan's channel entry is 1-local). Its Stinespring dilation IS " *
              "executable (class P): pass stinespring=true to dilate + trace " *
              "(EXACT on DM), or decompose into 1-wire factors.")
    end
    nothing
end

function _apply_channel_value!(ctx::DensityMatrixContext, ch::ChannelTensor,
                               wires::NTuple{K,WireID}, stinespring::Bool) where {K}
    na = nwires(ch.a)
    _apply_channel_value!(ctx, ch.a, ntuple(i -> wires[i], na), stinespring)
    _apply_channel_value!(ctx, ch.b, ntuple(i -> wires[na + i], K - na), stinespring)
    nothing
end

function _apply_channel_value!(ctx::DensityMatrixContext, ch::ChannelSeq,
                               wires::NTuple{K,WireID}, stinespring::Bool) where {K}
    _apply_channel_value!(ctx, ch.b, wires, stinespring)     # b runs FIRST
    _apply_channel_value!(ctx, ch.a, wires, stinespring)
    nothing
end

# --- Tracing: record the channel, never a dilation (S12) -----------------------

function _apply_channel_value!(ctx::TracingContext, ch::ChannelValue,
                               wires::NTuple{K,WireID}, stinespring::Bool) where {K}
    stinespring && throw(ArgumentError(
        "apply!: stinespring=true is meaningless under Tracing — the IR records " *
        "the CHANNEL (a NoiseN barrier), never a dilation (S12); the executing " *
        "context chooses its lowering at run time"))
    push!(_trec(ctx), NoiseN(ch, ntuple(i -> _pid(ctx, wires[i]), K)))
    nothing
end

# --- Eager: loud by default; explicit dilation opt-in (S12/S16) ----------------

function _apply_channel_value!(ctx::EagerContext, ch::ChannelValue,
                               wires::NTuple{K,WireID}, stinespring::Bool) where {K}
    if !stinespring
        error("apply!: a statevector cannot hold the mixed state a noise channel " *
              "produces. Choose explicitly: density(cap) executes the exact channel " *
              "in one run; shots(…) samples trajectories; stinespring=true dilates + " *
              "traces — ONE quantum-jump unravelling per run, NOT the channel.")
    end
    _emit_dilation!(ctx, ch, wires)          # slice 3: the choke-point emitter
    nothing
end
