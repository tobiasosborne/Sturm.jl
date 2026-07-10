# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M2 (bead Sturm.jl-dc6i): the
# `EagerContext` — the PRIMARY path, a PURE statevector delegated to Orkan.
# Holds one `state_t` of `type = PURE`; all `Ad` application is the shared
# emitter (ad.jl). The ONLY thing specific here is the trace lowering:
# measure-and-discard (§3.9's sanctioned pure-context unraveling), which is
# exact for all downstream statistics by no-signaling and advances the RNG —
# hence seeded tests must never assert trace placement (§3.9 corollary).
#
# Physics/spec grounding: PRD-v2 §3.9 (trace lowerings; ptrace ≠ reset).

"""
    EagerContext

A pure-statevector context (`ORKAN_PURE`) over one Orkan `state_t` of fixed
capacity. Construct via the `eager(cap) do ctx … end` resource form (regions.jl)
— that binds the ScopedValue and guarantees `teardown!` on exit; a bare
`EagerContext` is possible but you then own the `state_free`.
"""
struct EagerContext <: AbstractContext
    core::ContextCore
end

"""
    EagerContext(capacity; rng=nothing, strict=false)

Allocate a `capacity`-qubit PURE state in |0…0⟩ and wrap it. Prefer the
`eager(...)` resource form for deterministic teardown.
"""
function EagerContext(capacity::Integer; rng=nothing, strict::Bool=false)
    st = _state_new(ORKAN_PURE, Int(capacity))
    return EagerContext(ContextCore(st, ORKAN_PURE, Int(capacity); rng=rng, strict=strict))
end

"""
    trace_wire!(ctx::EagerContext, w)

Measure-and-discard lowering of the partial trace (§3.9). Flush, draw the traced
wire's outcome from the context RNG over its marginal, collapse+renormalize, and
reset the slot to |0⟩ (measure-and-flip: `ptrace! ≠ reset`, but the recycled
slot must satisfy "fresh = |e_G⟩"). Silent — no backaction.
"""
function trace_wire!(ctx::EagerContext, w::WireID)
    _flush_all!(ctx)
    core = _core(ctx)
    slot = core.wire_to_slot[w]
    p1 = _marginal_p1(core.state, slot)
    outcome = _draw(core) < p1 ? 1 : 0
    _collapse!(core.state, slot, outcome)
    outcome == 1 && _emit_x!(ctx, slot)   # flip |1⟩→|0⟩ so the recycled slot is |0⟩
    nothing
end

"""
    statevector(ctx::EagerContext) -> Vector{ComplexF64}

A COPY of the current amplitude vector (flushes pending 1q fusion first). Length
`2^capacity`; basis index bit `j` is Orkan qubit / slot `j`. Test/readout use.
"""
function statevector(ctx::EagerContext)
    _flush_all!(ctx)
    return _statevector(_core(ctx).state)
end
