# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M11 (bead Sturm.jl-qmpo), design
# `docs/design/m11-82su-synthesis.md` rulings S18/S25 + Tobias rulings T3/T4
# (session 103): the `CodeBlock` handle and the state-level encode/decode
# channels.
#
# T4 (ruled): `encode_state` is an OWNERSHIP TRANSFER, not a third consumption
# site — the logical qubit's information does not leave the program, it is
# re-homed into the block. §4.5's "exactly two places" count stands.
# Mechanically it follows `_instrument_record!`'s re-homing pattern: the old
# handle's WireID is unmapped (any later use fails "not live") and marked on
# the single-sourced consumed set (so cast-path messages are right), while the
# physical wire lives on under the block.
#
# T3 (ruled, overriding proposer B): a `CodeBlock` supports NO surface
# constructs in M11 — `not!`, `Bool`, `⊻=`, `dual`, `when`, `oracle` are all
# LOUD refusals. Reason of record: on a NOISY block, "transversal measure +
# majority vote" and "decode, then measure" are DIFFERENT CHANNELS, so
# offering either under the cast spelling silently picks a fault-tolerance
# protocol — F8 reappearing at the cast level, inside the milestone whose job
# was to close F8. Each refusal names what shipping it would need.

"""
    CodeBlock{C,N,Ctx} <: AbstractQRegister{Ctx}

A handle to `N` physical wires holding one encoded block under a
`CodeEncoding` (S25). Supports exactly: `decode_state`, the recovery path
(slice 6's `effective_logical_noise` / the surface syndrome program), and
introspection (`encoding`, `wires`). Every logical surface operation is a loud
refusal in M11 (T3) — see the file header for the reason of record.
"""
struct CodeBlock{C<:StabilizerCode,N,Ctx<:AbstractContext} <: AbstractQRegister{Ctx}
    ctx::Ctx
    enc::CodeEncoding{C,N}
    wires::NTuple{N,WireID}
end

encoding(b::CodeBlock) = b.enc      # contextof rides the generic .ctx accessor

# Re-home a live wire under a fresh WireID (the T4 ownership transfer;
# `_instrument_record!`'s pattern): the old handle dies loudly, the physical
# wire lives on under the new identity, region-registered.
function _transfer_wire!(ctx::AbstractContext, w::WireID)
    core = _core(ctx)
    haskey(core.wire_to_slot, w) || error(
        "encode_state: wire $w is not live (already consumed, traced, or transferred)")
    _flush_wire!(ctx, w)          # drain pending 1q fusion under the OLD identity
    slot = core.wire_to_slot[w]
    delete!(core.wire_to_slot, w)
    mark_consumed!(ctx, w)
    core.wire_counter += 1
    nw = WireID(core.wire_counter)
    core.wire_to_slot[nw] = slot
    isempty(core.region_stack) || push!(core.region_stack[end], nw)
    return nw
end

"""
    encode_state(e::CodeEncoding{C,N,K}, qs::QBool...) -> CodeBlock

The state-level encoding channel `E = U_enc ∘ (· ⊗ |0⟩^{N−K})` (S18): takes
ownership of the `K` logical qubits (T4 — an OWNERSHIP TRANSFER: the input
handles die loudly, their wires are re-homed into the block; §4.5's two
consumption sites are untouched), allocates `N − K` fresh `|0⟩` wires, and
applies the encoding's certified unitary. Logical inputs sit on block wires
`1..K` (MSB-first), fresh ancillas on `K+1..N`.
"""
function encode_state(e::CodeEncoding{C,N,K}, qs::AbstractQubit...) where {C,N,K}
    length(qs) == K || throw(ArgumentError(
        "encode_state: $(nameof(typeof(e.code)))[$(e.code.name)] encodes K = $K logical " *
        "qubit(s); got $(length(qs))"))
    ctx = contextof(qs[1])
    for q in qs
        contextof(q) === ctx || throw(ArgumentError(
            "encode_state: logical inputs live in different contexts"))
    end
    logical = ntuple(i -> _transfer_wire!(ctx, qs[i].wire), K)
    fresh = ntuple(_ -> allocate!(ctx), N - K)
    wires = (logical..., fresh...)
    apply!(ctx, e.encoder, wires)
    return CodeBlock{C,N,typeof(ctx)}(ctx, e, wires)
end

"""
    decode_state(blk::CodeBlock{C,N}) -> QBool  (K = 1; an NTuple for K > 1)

The state-level decoding channel `D = (id_K ⊗ Tr_{N−K}) ∘ U_enc†` (S18): apply
`adjoint(encoder)` — exact by construction — then TRACE the `N − K` scratch
wires (the code-capacity D map; on a noisy block the scratch holds the error
record and tracing it is the honest channel denotation, §3.9) and re-home the
`K` logical wires as fresh `QBool` handles. Consumes the block.
"""
function decode_state(blk::CodeBlock{C,N}) where {C,N}
    ctx = blk.ctx
    for w in blk.wires
        haskey(_core(ctx).wire_to_slot, w) || error(
            "decode_state: block wire $w is not live (block already decoded or traced)")
    end
    apply!(ctx, decoder(blk.enc), blk.wires)
    K = nlogical(blk.enc)
    outs = ntuple(i -> _adopt_qbool(ctx, blk.wires[i]), K)
    for i in (K + 1):N
        _trace_and_free!(ctx, blk.wires[i])
    end
    return K == 1 ? outs[1] : outs
end

# --- The S25/T3 refusals (each names what shipping it would need) -------------

_refuse_block(op::AbstractString, needs::AbstractString) = throw(ArgumentError(
    "$op on a CodeBlock is not available in M11 (ruling T3): shipping it would " *
    "need $needs. M11 ships NO logical operations — decode_state, the recovery " *
    "program, and introspection are the entire block surface."))

not!(::CodeBlock) = _refuse_block("not!",
    "a declared transversal X̄ gadget under an explicit fault model (a bare " *
    "physical X on every wire IS X̄ for the bit-flip code, but blessing it as " *
    "the cast spelling would silently promise transversality for every code)")

Base.Bool(::CodeBlock) = _refuse_block("Bool",
    "a readout-protocol RULING: on a noisy block, transversal-measure-plus-" *
    "majority and decode-then-measure are DIFFERENT channels — offering either " *
    "under the cast spelling silently picks a fault-tolerance protocol (F8 at " *
    "the cast level). Decode first: Bool(decode_state(blk))")

Base.xor(::CodeBlock, ::Any) = _refuse_block("⊻=",
    "a transversal-CNOT gadget declaration (CSS-transversality is code-" *
    "dependent) plus the block-pair alias discipline")
Base.xor(::Any, ::CodeBlock) = _refuse_block("⊻=",
    "a transversal-CNOT gadget declaration (CSS-transversality is code-" *
    "dependent) plus the block-pair alias discipline")
Base.xor(::CodeBlock, ::CodeBlock) = _refuse_block("⊻=",
    "a transversal-CNOT gadget declaration (CSS-transversality is code-" *
    "dependent) plus the block-pair alias discipline")

dual(::CodeBlock) = _refuse_block("dual",
    "the code's conjugate structure (the dual of an encoded block is a view " *
    "through the LOGICAL group, which requires declared logical operators as " *
    "the block's translation family — X̄/Z̄ gadgets again)")

when(f, ::CodeBlock) = _refuse_block("when",
    "a coherent logical-control gadget: controlling on an encoded block means " *
    "ctrl by its LOGICAL Z̄ subspace, a code-dependent multi-wire control " *
    "structure with its own clean-ancilla obligations")

oracle(f, ::CodeBlock) = _refuse_block("oracle",
    "logical-level Bennett compilation — an oracle over encoded blocks is a " *
    "fault-tolerant lift of the compiled Perm (see fault_tolerant_lift's " *
    "five missing ingredients)")
