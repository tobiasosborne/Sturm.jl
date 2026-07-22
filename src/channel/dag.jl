# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M8 (bead Sturm.jl-szx1), design gate
# `docs/design/m8-5hr7-unitary-block-design.md` §1.2: the CHANNEL IR — the
# effect-typed, deeply-immutable `ChannelDAG`. It is the general (possibly
# non-unitary) denotation of a `when` body / traced library circuit WHILE it is
# being built: it allocates ancillas (isometry), acts, deallocates (coisometry),
# and may measure / branch / apply noise.
#
# `ChannelDAG` is NOT a `ProcessValue` (design §1.1). It sits on the CHANNEL level
# of PRD-v2 §4.4, so `ctrl(::ChannelDAG)` is a deliberate `MethodError` — control
# on a non-unitary effect is unrepresentable (P4), which the shipped no-catch-all
# `ctrl` discipline (`src/kernel/ctrl.jl`) gives for FREE (no method is written).
# A `ChannelDAG` becomes a `UnitaryBlock` (a process value) ONLY through `certify`
# (`src/channel/cert.jl`), which mints a structural clean-ancilla certificate.
#
# NODES ARE EFFECT-TYPED, NEVER GATE-NAMED (the plan forbids importing the v0.1
# Ry/Rz/CX node vocabulary): a node carries a PROCESS VALUE (`ApplyN.v`) or an
# effect (alloc/trace/measure/cases/noise). `MeasureN`/`CasesN`/`NoiseN` are the
# UNITARY-PASS BARRIERS (CLAUDE.md "Channel IR vs Unitary Methods"); their
# presence disqualifies a sub-DAG from promotion (`certify` refuses them), which
# is exactly the seam where the parallel i4ri classical-control round attaches
# (design §6).
#
# DEEP IMMUTABILITY (F28, design §4). `nodes` and all port tuples are FROZEN
# (`NTuple`, no live-`Vector` aliasing). Mutable BUILDERS (`src/channel/builder.jl`)
# are used during tracing/pass construction; `freeze`/`certify` copy into
# immutable nodes and discard the builder. This is why `Perm`/`MCX` were refactored
# to `NTuple` storage (`src/kernel/perm.jl`): a sealed block embedding a live-Vector
# `Perm` would not be deeply immutable.
#
# ── WIRE MODEL (implementer refinement of the design sketch — flagged) ──────────
# The design §1.2 node sketch writes `ApplyN(v, ports::NTuple{K,PortID})` and
# `AllocN(out::PortID)`, and §1.2 prose says "every node consumes existing edges
# and creates fresh ones". A strict per-op SSA re-versioning is not needed by the
# parts-1..3 tests and complicates matrix replay; this slice adopts a LINEAGE-
# CENTRIC IN-PLACE model that is faithful to §1.2's load-bearing claim (lineage,
# not width, is identity) and directly supports the `denoted_matrix` replay:
#   • A quantum WIRE is identified by its LINEAGE (`Port.lineage`). `ApplyN` acts
#     IN PLACE on the wires named by its ports (lineage-preserving); `AllocN`
#     introduces a fresh |0⟩ wire (fresh lineage); `TraceN` discards one.
#   • `AllocN` carries a full `Port` (not a bare `PortID`) so the fresh lineage is
#     recorded at the birth site (design §2.4: alloc IS the Stinespring dilation).
#   • The endomorphism check compares `qin` vs `qout` LINEAGE in order.
# The `PortID`/lineage split is retained exactly as §1.2 specifies (SSA name vs
# physical identity); the refinement is only that in-place ops keep the PortID
# rather than minting a fresh one per op. Documented as a deviation in the M8 report.

"""
    Node

Abstract supertype of the effect-typed channel-IR nodes (design §1.2). Concrete
kinds: `ApplyN` (unitary application), `AllocN` (isometry / ancilla birth),
`TraceN` (coisometry / discard), and the three UNITARY-PASS BARRIERS `MeasureN`
(instrument / qc cast), `CasesN` (Kleisli join — i4ri seam), `NoiseN` (channel
value). All deeply immutable (F28).
"""
abstract type Node end

"""
    KrausFamily(nwires::Int)

RESERVED SEAM (design §6): a placeholder for a noise channel's Kraus operators,
carried by `NoiseN`. A `NoiseN` is a unitary-pass barrier and `certify` refuses
any DAG containing one, so this slice needs only the type to shape the node
signature; the concrete Kraus algebra lands with the channel-pass framework
(NOT this slice).
"""
struct KrausFamily
    nwires::Int
end

"""
    ChannelDAG

The effect-typed channel IR (design §1.2). Topologically-ordered `nodes`, with
typed quantum in/out ports (`qin`/`qout` — they need NOT match: `AllocN` adds,
`TraceN` removes) and classical/token outputs (`cout`, from measurement/cases).

NOT a `ProcessValue`: it has no `ctrl` method and no unitary-pass method (both
`MethodError` — design §1.1, test `M8.PORT.CHANNEL-NOT-PROCESS`). Promotion to a
`UnitaryBlock` is via `certify` only. Frozen on construction (F28).
"""
struct ChannelDAG
    nodes::NTuple{M,Node} where {M}
    qin::NTuple{A,Port} where {A}
    qout::NTuple{B,Port} where {B}
    cout::NTuple{C,Port} where {C}
    ChannelDAG(nodes::Tuple{Vararg{Node}}, qin::Tuple{Vararg{Port}},
               qout::Tuple{Vararg{Port}}, cout::Tuple{Vararg{Port}}) =
        new(nodes, qin, qout, cout)
end

"""
    ChannelDAG(nodes, qin, qout, cout=()) -> ChannelDAG

Vector/tuple-accepting constructor: defensively freezes each collection into an
immutable tuple (F28). `cout` defaults to empty (a purely quantum block).
"""
ChannelDAG(nodes, qin, qout, cout = ()) =
    ChannelDAG(Tuple(nodes), Tuple(qin), Tuple(qout), Tuple(cout))

# --- Concrete effect nodes ---------------------------------------------------

"""
    ApplyN(v::ProcessValue, ports::NTuple{K,PortID})

Apply the process value `v` to the wires named by `ports` (position 1 = `v`'s MSB
wire), IN PLACE (lineage-preserving). `v` is a kernel process value — `U2`,
`Perm`, `Ctrl`, `Tensor`, `Seq`, or a nested `UnitaryBlock` — NEVER a gate name.
`length(ports)` must equal `nwires(v)` (per-wire ports for this slice; wider
`QuantumPort`s are a reserved seam).
"""
struct ApplyN <: Node
    v::ProcessValue
    ports::NTuple{K,PortID} where {K}
    ApplyN(v::ProcessValue, ports::Tuple{Vararg{PortID}}) = new(v, ports)
end
ApplyN(v::ProcessValue, ports::AbstractVector{PortID}) = ApplyN(v, Tuple(ports))
ApplyN(v::ProcessValue, ports::PortID...) = ApplyN(v, ports)

"""
    AllocN(out::Port)

Ancilla birth: the Stinespring DILATION step (design §2.4), an isometry
`ι : H_D → H_D ⊗ |0⟩_A` (PRD-v2 §3.9 — the region IS the Stinespring boundary).
`out` is a fresh quantum `Port` initialized to `|0⟩` with a FRESH lineage.
(Carries a full `Port`, not a bare `PortID` — see the wire-model note above.)
"""
struct AllocN <: Node
    out::Port
end

"""
    TraceN(in::PortID, cert::Union{Nothing,CleanCert})

Ancilla discard: the environment coisometry `ι† = I ⊗ ⟨0|` (design §2.4), valid
on the reachable image only. `cert` is the structural clean-ancilla certificate
that witnesses this `TraceN`'s scratch returns to `|0⟩` for all inputs; a
`nothing` cert is an UNMATCHED discard, which `certify` rejects loudly (the F1
adversary — test `M8.CERT.STATE-IS-NOT-WITNESS`).
"""
struct TraceN <: Node
    in::PortID
    cert::Union{Nothing,CleanCert}
end
TraceN(in::PortID) = TraceN(in, nothing)

"""
    MeasureN(in::PortID, out::PortID)   [BARRIER]

An instrument (the qc measurement cast): consumes a quantum port `in`, produces a
classical token port `out`. A UNITARY-PASS BARRIER — `certify` refuses any DAG
containing it (a `UnitaryBlock` never holds an instrument, design §1.3). Its
token/record semantics is the i4ri gate (design §6 seam); typed here so the
signature is shaped for that round.
"""
struct MeasureN <: Node
    in::PortID
    out::PortID
end

"""
    CasesN(sel::PortID, branches::NTuple{B,ChannelDAG})   [BARRIER]

A Kleisli join: classical branching on the discriminant token `sel`, one
`ChannelDAG` branch per outcome. A UNITARY-PASS BARRIER — `certify` refuses it.
RESERVED SEAM (design §6): the `sel` classical-token port and the branch DAGs are
the attach points; the tokens / correlation record / linear-join semantics live
in the parallel i4ri round, NOT this slice.
"""
struct CasesN <: Node
    sel::PortID
    branches::NTuple{B,ChannelDAG} where {B}
    CasesN(sel::PortID, branches::Tuple{Vararg{ChannelDAG}}) = new(sel, branches)
end
CasesN(sel::PortID, branches::AbstractVector{ChannelDAG}) = CasesN(sel, Tuple(branches))

"""
    NoiseN(kraus::KrausFamily, ports::NTuple{K,PortID})   [BARRIER]

A noise channel value applied to `ports`. A UNITARY-PASS BARRIER — `certify`
refuses it. RESERVED SEAM: shaped for the channel-pass framework (NOT this slice).
"""
struct NoiseN <: Node
    kraus::KrausFamily
    ports::NTuple{K,PortID} where {K}
    NoiseN(kraus::KrausFamily, ports::Tuple{Vararg{PortID}}) = new(kraus, ports)
end
NoiseN(kraus::KrausFamily, ports::AbstractVector{PortID}) = NoiseN(kraus, Tuple(ports))

# --- Barrier / structural predicates -----------------------------------------

"""
    is_barrier(n::Node) -> Bool

Whether `n` is a unitary-pass barrier (`MeasureN`/`CasesN`/`NoiseN`) — the nodes
`certify` refuses and unitary passes must never cross (design §1.2, §3.3).
"""
is_barrier(::Node) = false
is_barrier(::MeasureN) = true
is_barrier(::CasesN) = true
is_barrier(::NoiseN) = true

"""
    has_barrier(dag::ChannelDAG) -> Bool

Whether any node is a barrier. `certify` fails loudly when true (design §2.3).
"""
has_barrier(dag::ChannelDAG) = any(is_barrier, dag.nodes)
