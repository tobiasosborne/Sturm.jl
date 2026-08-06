# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M11 (bead Sturm.jl-qmpo), design
# `docs/design/m11-82su-synthesis.md` ruling S28: CHANNEL-LEVEL `∘` and `⊗` on
# `ChannelDAG` — the §4.4 stratum-2 composition the PRD promises and M8 never
# needed. This is the substrate `effective_logical_noise` splices on (slice 6).
#
# WHY NOT `_rebase`/`_remap_nodes` (research step R2, resolved): the
# block-algebra remapper serves `UnitaryBlock` bodies and REFUSES the barrier
# nodes by design (`MeasureN`/`CasesN`/`NoiseN` never appear in a certified
# block). A `ChannelDAG` holds all six node kinds, `CasesN` carries NESTED
# branch DAGs sharing the parent's `PortID` namespace (tracing materializer),
# and `MeasureN.out` ids may have no full `Port` anywhere (an internally-
# consumed record is deliberately not a `cout` — T4). So this file carries its
# own remapper covering the full vocabulary, recursive into branches.
#
# THE SEAM RULE (S28, the wm28-class hazard): `a ∘ b` (b runs FIRST) relabels
# BOTH operands into one fresh `PortID`/lineage namespace, then identifies
# `b.qout[i]` with `a.qin[i]` AS ONE PORT — same id, same lineage. The seam is
# one physical resource; lineage identification is what lets a composite of
# endomorphisms certify (`certify` compares boundary lineage in order). Naive
# node concatenation without relabeling silently FUSES unrelated wires whose
# `PortID`s collide — the negative-control test pins that failure mode.

# --- The full-vocabulary remapper ---------------------------------------------

# Deterministically assign fresh ids to every port of `dag` (boundary, allocs,
# measurement records — recursively through CasesN branches), EXCEPT ids
# pre-seeded in `idmap` (the seam). Full `Port`s (with fresh lineage == fresh
# id) are minted for ports known in full; bare record ids get id entries only.
function _dag_fresh_ids!(idmap::Dict{PortID,PortID}, portmap::Dict{PortID,Port},
                         ctr::Base.RefValue{Int}, dag::ChannelDAG)
    fresh_port!(p::Port) = begin
        if haskey(idmap, p.id)
            # Already id-mapped (e.g. a MeasureN.out seen as a bare id during
            # the node walk, now appearing in full as a cout Port): upgrade to
            # a full Port under the SAME new id.
            haskey(portmap, p.id) ||
                (portmap[p.id] = Port(idmap[p.id], p.kind, idmap[p.id].id))
            return nothing
        end
        ctr[] += 1
        np = Port(PortID(ctr[]), p.kind, ctr[])
        idmap[p.id] = np.id
        portmap[p.id] = np
        nothing
    end
    fresh_id!(pid::PortID) = begin
        haskey(idmap, pid) && return nothing
        ctr[] += 1
        idmap[pid] = PortID(ctr[])
        nothing
    end
    walk(nodes) = begin
        for nd in nodes
            if nd isa AllocN
                fresh_port!(nd.out)
            elseif nd isa MeasureN
                fresh_id!(nd.out)
            elseif nd isa CasesN
                for br in nd.branches
                    for p in br.qin
                        fresh_port!(p)
                    end
                    walk(br.nodes)
                    for p in br.qout
                        fresh_port!(p)
                    end
                    for p in br.cout
                        fresh_port!(p)
                    end
                end
            end
        end
        nothing
    end
    for p in dag.qin
        fresh_port!(p)
    end
    walk(dag.nodes)
    for p in dag.qout
        fresh_port!(p)                       # endomorphic wires are already mapped
    end
    for p in dag.cout
        fresh_port!(p)
    end
    return nothing
end

_rm(idmap, pid::PortID) = get(idmap, pid) do
    error("ChannelDAG remap: node references unmapped port $pid — the DAG is not " *
          "self-contained (a branch leaked a foreign PortID)")
end

# Rewrite `p` through the maps: prefer the minted full Port (fresh lineage);
# a seam target arrives as a full Port in `portmap` from the OTHER operand.
_rp(idmap, portmap, p::Port) = haskey(portmap, p.id) ? portmap[p.id] :
    Port(_rm(idmap, p.id), p.kind, _rm(idmap, p.id).id)

function _remap_dag_nodes(nodes, idmap, portmap)
    out = Node[]
    for nd in nodes
        if nd isa ApplyN
            push!(out, ApplyN(nd.v, Tuple(_rm(idmap, p) for p in nd.ports)))
        elseif nd isa AllocN
            push!(out, AllocN(_rp(idmap, portmap, nd.out)))
        elseif nd isa TraceN
            push!(out, TraceN(_rm(idmap, nd.in), nd.cert))
        elseif nd isa MeasureN
            push!(out, MeasureN(_rm(idmap, nd.in), _rm(idmap, nd.out)))
        elseif nd isa NoiseN
            push!(out, NoiseN(nd.ch, Tuple(_rm(idmap, p) for p in nd.ports)))
        elseif nd isa CasesN
            branches = ChannelDAG[]
            for br in nd.branches
                push!(branches, ChannelDAG(
                    Tuple(_remap_dag_nodes(br.nodes, idmap, portmap)),
                    Tuple(_rp(idmap, portmap, p) for p in br.qin),
                    Tuple(_rp(idmap, portmap, p) for p in br.qout),
                    Tuple(_rp(idmap, portmap, p) for p in br.cout)))
            end
            push!(out, CasesN(_rm(idmap, nd.sel), Tuple(branches)))
        else
            error("ChannelDAG remap: unexpected node $(typeof(nd))")
        end
    end
    return out
end

# --- ∘ (S28): b runs first; the seam is one port -------------------------------

"""
    ∘(a::ChannelDAG, b::ChannelDAG) -> ChannelDAG

Series composition of channel DAGs — `b` runs FIRST (the kernel convention).
Both operands are relabeled into one fresh `PortID`/lineage namespace, then
`b.qout[i]` is identified with `a.qin[i]` as ONE port (same id, SAME lineage —
the seam is one physical resource, which is what lets a composite of
endomorphisms `certify`). Nested `CasesN` branches remap recursively. The
composite's `qin` is `b`'s, `qout` is `a`'s, and `cout` is the ordered union
(`b`'s records, then `a`'s). Loud on arity or port-kind mismatch. Classical
seams (feeding a record across the join) are not expressible in M11 — a
record either escapes as `cout` or is consumed inside its own operand.
"""
function Base.:∘(a::ChannelDAG, b::ChannelDAG)
    length(a.qin) == length(b.qout) || throw(ArgumentError(
        "∘(ChannelDAG): arity mismatch — a takes $(length(a.qin)) quantum inputs, " *
        "b yields $(length(b.qout)) outputs"))
    for i in eachindex(b.qout)
        b.qout[i].kind == a.qin[i].kind || throw(ArgumentError(
            "∘(ChannelDAG): seam port $i kind mismatch ($(b.qout[i].kind) vs $(a.qin[i].kind))"))
    end
    ctr = Ref(0)
    bid = Dict{PortID,PortID}(); bport = Dict{PortID,Port}()
    _dag_fresh_ids!(bid, bport, ctr, b)
    # Seed a's map with the seam: a.qin[i] IS remapped(b.qout[i]) — id AND lineage.
    aid = Dict{PortID,PortID}(); aport = Dict{PortID,Port}()
    for i in eachindex(a.qin)
        seam = bport[b.qout[i].id]
        aid[a.qin[i].id] = seam.id
        aport[a.qin[i].id] = seam
    end
    _dag_fresh_ids!(aid, aport, ctr, a)
    nodes = vcat(_remap_dag_nodes(b.nodes, bid, bport),
                 _remap_dag_nodes(a.nodes, aid, aport))
    qin = Tuple(bport[p.id] for p in b.qin)
    qout = Tuple(aport[p.id] for p in a.qout)
    cout = (Tuple(bport[p.id] for p in b.cout)..., Tuple(aport[p.id] for p in a.cout)...)
    return ChannelDAG(Tuple(nodes), qin, qout, cout)
end

# --- ⊗ (S28): disjoint juxtaposition, a leads (MSB) ----------------------------

"""
    ⊗(a::ChannelDAG, b::ChannelDAG) -> ChannelDAG

Parallel composition — `a` on the leading (MSB) wire block. Both operands are
relabeled into one fresh disjoint namespace; boundaries and record outputs
concatenate (`a` first). No seam, no identification.
"""
function ⊗(a::ChannelDAG, b::ChannelDAG)
    ctr = Ref(0)
    aid = Dict{PortID,PortID}(); aport = Dict{PortID,Port}()
    _dag_fresh_ids!(aid, aport, ctr, a)
    bid = Dict{PortID,PortID}(); bport = Dict{PortID,Port}()
    _dag_fresh_ids!(bid, bport, ctr, b)
    nodes = vcat(_remap_dag_nodes(a.nodes, aid, aport),
                 _remap_dag_nodes(b.nodes, bid, bport))
    qin = (Tuple(aport[p.id] for p in a.qin)..., Tuple(bport[p.id] for p in b.qin)...)
    qout = (Tuple(aport[p.id] for p in a.qout)..., Tuple(bport[p.id] for p in b.qout)...)
    cout = (Tuple(aport[p.id] for p in a.cout)..., Tuple(bport[p.id] for p in b.cout)...)
    return ChannelDAG(Tuple(nodes), qin, qout, cout)
end

# --- Lifting a channel value into the IR ---------------------------------------

"""
    channel_dag(ch::ChannelValue, n::Int) -> ChannelDAG

Lift a channel value into a one-node `ChannelDAG`: `n` boundary wires (must
equal `nwires(ch)` — the arity is taken from the value, never assumed) carrying
a single `NoiseN`. The building block for `physical_iid` and the DAG-splicing
superchannel (slice 6).
"""
function channel_dag(ch::ChannelValue, n::Int)
    n == nwires(ch) || throw(ArgumentError(
        "channel_dag: channel acts on $(nwires(ch)) wires, not $n"))
    ports = Tuple(Port(PortID(i), QuantumPort(1), i) for i in 1:n)
    node = NoiseN(ch, Tuple(p.id for p in ports))
    return ChannelDAG((node,), ports, ports, ())
end
