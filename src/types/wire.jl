# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M2 (bead Sturm.jl-dc6i): a MINIMAL
# `WireID` — a stable, opaque wire identity. M2 needs wire identity NOW for
# three things the region/context layer cannot express without it: the
# single-sourced consumed set (§4.5), the per-region owned set (§3.9), and the
# §8.4 aliasing check that must key on *register identity* (not raw Orkan
# index) and fire BEFORE the FFI shim's index checks.
#
# This is the identity core only. M3's `src/types/` grows the typed handles
# (`QBool`, `QInt{W}`, `x[i]` slices) as a LAYER over this `WireID`; the
# identity does not change, so M3 adds without reworking (design deviation
# D-A2, adopted by the M2 synthesis directive).
#
# Physics/spec grounding: PRD-v2 §3.9 (scope = Stinespring boundary; owned
# locals traced at region exit), §4.5 (consumption single-sourced), §8.4
# (aliasing with register identity).

"""
    WireID(id)

An opaque, immutable wire identity. `id` is a per-context monotone integer the
allocator assigns; two `WireID`s are equal iff their ids match (value type ⇒
`==`/`hash` are structural and correct for use as `Dict`/`Set` keys). A
`WireID` is NOT an Orkan qubit index — the context maps `WireID → Orkan slot`
through `q(ctx, ·)`, the single source of truth for that map (§3.3 endianness
pin). Recycling an Orkan slot mints a FRESH `WireID`, so a stale handle never
silently aliases a reused slot.

Deliberately minimal for M2 (identity only). M3 wraps this with typed register
handles; the identity is invariant across that layering.
"""
struct WireID
    id::Int
end

Base.show(io::IO, w::WireID) = print(io, "WireID(", w.id, ")")
