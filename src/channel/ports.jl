# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M8 (bead Sturm.jl-szx1), design gate
# `docs/design/m8-5hr7-unitary-block-design.md` §1.2: graph-local PORT identity
# for the channel IR. A `PortID` names an SSA edge / local slot in a REUSABLE
# graph — distinct from the runtime `WireID` (`src/types/wire.jl`), which names a
# live resource in ONE execution context. The IR is symbolic and context-free;
# `PortID`/`Port` are its wire vocabulary.
#
# RESOURCE LINEAGE (design §1.2, load-bearing). A unitary block must be an
# ENDOMORPHISM on the same ordered physical boundary. Width equality is NOT
# identity: it cannot tell "same handle after a unitary" from "input discarded, a
# same-shaped fresh output returned". Each `Port` therefore carries a `lineage`
# tag — the physical-resource identity. The sealer's endomorphism check compares
# LINEAGE, not width (`certify`, `src/channel/cert.jl`; test
# `M8.PORT.ENDOMORPHIC-BLOCK`). An in-place op that keeps a surface handle
# versions it as distinct SSA `PortID`s SHARING one lineage.

"""
    PortID(id::Int)

An SSA edge / local slot name in a reusable channel graph. Graph-local and
context-free (unlike `WireID`, which is a live per-context resource handle). Deep
immutable (a bare `Int` wrapper).
"""
struct PortID
    id::Int
end

"""
    PortKind

Abstract supertype of the two port kinds a channel edge can carry
(design §1.2):

  • `QuantumPort(width)`  — a quantum wire-bundle; `width` is runtime DATA
    (dimension-agnostic, P7), never a type parameter.
  • `ClassicalPort(ttype)` — a classical token port (`ClassicalBit`/`Int`); the
    attach point for the parallel i4ri classical-control IR (§6 seam).
"""
abstract type PortKind end

"""
    QuantumPort(width::Int)

A quantum wire-bundle of `width` qubits. `width` is runtime data (P7). The M8
part-1..3 replay (`denoted_matrix(::UnitaryBlock)`) supports `width == 1` ports
(one qubit per port); wider bundles are a documented reserved seam — the type
records the width, the small-scale matrix replay expands each port to that many
contiguous wire slots.
"""
struct QuantumPort <: PortKind
    width::Int
end

"""
    ClassicalPort(ttype::DataType)

A classical token port carrying a value of `ttype` (`ClassicalBit`/`ClassicalInt`
in the i4ri round). RESERVED SEAM: typed here so `MeasureN`/`CasesN` node
signatures are shaped for the classical-control round; its token/record
semantics is the i4ri gate, not this slice (design §6).
"""
struct ClassicalPort <: PortKind
    ttype::DataType
end

"""
    Port(id::PortID, kind::PortKind, lineage::Int)

A typed channel edge: an SSA name (`id`), a `kind` (quantum width / classical
type), and a `lineage` — the physical-resource identity (design §1.2). Two ports
with the same `lineage` are the same physical wire at two SSA versions; the
endomorphism check compares lineage. Deep immutable.
"""
struct Port
    id::PortID
    kind::PortKind
    lineage::Int
end

"""
    is_quantum(p::Port) -> Bool

Whether `p` carries a quantum wire-bundle (vs a classical token port).
"""
is_quantum(p::Port) = p.kind isa QuantumPort

"""
    portwidth(p::Port) -> Int

Qubit width of a quantum port (1 for a bare qubit). Classical ports have no
qubit width and error loudly (CLAUDE.md #1) — they never enter the unitary replay.
"""
function portwidth(p::Port)
    k = p.kind
    k isa QuantumPort || error("portwidth: $(p) is not a quantum port")
    return k.width
end
