# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M8 (bead Sturm.jl-szx1), design gate
# `docs/design/m8-5hr7-unitary-block-design.md` §4: the MUTABLE `DAGBuilder`.
# Immutability of the IR (F28) is achieved by building in a mutable builder and
# FREEZING copies into immutable nodes on `freeze`/`certify` — the builder is then
# discarded. This is `public` kernel tooling: it is what the surface `when`/`within`
# tracer (later slices) and the M8 law tests use to construct `ChannelDAG`s
# directly, without hand-managing `PortID`/lineage bookkeeping.
#
# The builder assigns each fresh wire a distinct `PortID` AND a distinct `lineage`
# (physical-resource identity, §1.2). In-place ops keep the same `PortID`/lineage
# (the lineage-centric in-place model, `src/channel/dag.jl` header).

"""
    DAGBuilder()

A mutable channel-IR builder. Fields (all internal): the `nodes` accumulated so
far, the boundary `inputs` in declaration order, the currently-`live` quantum
`PortID`s (their order fixes `qout`), the `id2port` resolution map, and monotone
`PortID`/lineage counters. Freeze with `freeze(b)` / promote with `certify(b)`.
"""
mutable struct DAGBuilder
    nodes::Vector{Node}
    inputs::Vector{Port}
    live::Vector{PortID}
    couts::Vector{Port}
    id2port::Dict{PortID,Port}
    nextid::Int
    nextlin::Int
end
DAGBuilder() = DAGBuilder(Node[], Port[], PortID[], Port[], Dict{PortID,Port}(), 1, 1)

function _fresh_qport!(b::DAGBuilder, width::Int)
    p = Port(PortID(b.nextid), QuantumPort(width), b.nextlin)
    b.nextid += 1
    b.nextlin += 1
    b.id2port[p.id] = p
    return p
end

"""
    input!(b::DAGBuilder; width=1) -> PortID

Declare a boundary quantum input wire (fresh `PortID`, fresh lineage). Added to the
boundary and the live set; its position fixes its slot in `qin` (and, if it
survives, `qout`).
"""
function input!(b::DAGBuilder; width::Int = 1)
    p = _fresh_qport!(b, width)
    push!(b.inputs, p)
    push!(b.live, p.id)
    return p.id
end

"""
    alloc!(b::DAGBuilder; width=1) -> PortID

Allocate a fresh `|0⟩` scratch wire (an `AllocN` — the Stinespring dilation, §2.4).
Fresh `PortID`/lineage; added to the live set but NOT the boundary. Must later be
released with `trace!` carrying a certificate, or `certify` rejects it (F1).
"""
function alloc!(b::DAGBuilder; width::Int = 1)
    p = _fresh_qport!(b, width)
    push!(b.nodes, AllocN(p))
    push!(b.live, p.id)
    return p.id
end

"""
    apply_node!(b::DAGBuilder, v::ProcessValue, ports::PortID...) -> b

Append an `ApplyN` of process value `v` to `ports` (position 1 = `v`'s MSB wire),
in place. `length(ports)` must equal `nwires(v)` (fail-loud).
"""
function apply_node!(b::DAGBuilder, v::ProcessValue, ports::PortID...)
    length(ports) == nwires(v) || error(
        "apply_node!: $(typeof(v)) has $(nwires(v)) wires but $(length(ports)) ports given")
    for pid in ports
        haskey(b.id2port, pid) || error("apply_node!: unknown/dead port $pid")
    end
    push!(b.nodes, ApplyN(v, ports))
    return b
end

"""
    trace!(b::DAGBuilder, pid::PortID; cert=nothing) -> b

Release a scratch wire (a `TraceN` — the coisometry, §2.4), removing it from the
live set. `cert` is the structural clean-ancilla certificate; a `nothing` cert is
the unmatched-discard the sealer rejects (F1).
"""
function trace!(b::DAGBuilder, pid::PortID; cert::Union{Nothing,CleanCert} = nothing)
    idx = findfirst(==(pid), b.live)
    idx === nothing && error("trace!: port $pid is not live")
    deleteat!(b.live, idx)
    push!(b.nodes, TraceN(pid, cert))
    return b
end

"""
    measure!(b::DAGBuilder, pid::PortID; ttype=Bool) -> PortID   [BARRIER]

Append a `MeasureN` (instrument / qc cast): consumes quantum `pid`, produces a
classical token port (added to `cout`). A unitary-pass barrier — `certify` refuses
any DAG containing it. RESERVED SEAM for the i4ri round.
"""
function measure!(b::DAGBuilder, pid::PortID; ttype::DataType = Bool)
    idx = findfirst(==(pid), b.live)
    idx === nothing && error("measure!: port $pid is not live")
    deleteat!(b.live, idx)
    out = Port(PortID(b.nextid), ClassicalPort(ttype), b.nextlin)
    b.nextid += 1; b.nextlin += 1
    b.id2port[out.id] = out
    push!(b.couts, out)
    push!(b.nodes, MeasureN(pid, out.id))
    return out.id
end

"""
    noise!(b::DAGBuilder, ports::PortID...; nwires=length(ports)) -> b   [BARRIER]

Append a `NoiseN` (channel value) — a unitary-pass barrier. RESERVED SEAM.
"""
function noise!(b::DAGBuilder, ports::PortID...; nwires::Int = length(ports))
    push!(b.nodes, NoiseN(KrausFamily(nwires), ports))
    return b
end

"""
    freeze(b::DAGBuilder; qout=nothing) -> ChannelDAG

Freeze the builder into an immutable `ChannelDAG` (F28): `qin` = declared inputs,
`qout` = the live quantum ports (in live order) unless overridden, `cout` = the
classical token ports. The builder is discarded after freezing.
"""
function freeze(b::DAGBuilder; qout = nothing)
    qout_ports = qout === nothing ? Port[b.id2port[pid] for pid in b.live] : qout
    return ChannelDAG(Tuple(b.nodes), Tuple(b.inputs), Tuple(qout_ports), Tuple(b.couts))
end

"""
    certify(b::DAGBuilder) -> UnitaryBlock

Convenience: `certify(freeze(b))`.
"""
certify(b::DAGBuilder) = certify(freeze(b))
