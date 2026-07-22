# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M8 (bead Sturm.jl-szx1), design gate
# `docs/design/m8-5hr7-unitary-block-design.md` §1.3/§2.2: the process-value
# ALGEBRA on `UnitaryBlock` — `adjoint` (rule 6, `AdjointCert`), `∘` (rule 4,
# `SeqCert`), `⊗` (rule 5, `ParCert`). Each produces a CERTIFIED block (the cert
# set is closed under these combinators), so a composed/adjointed block stays a
# process value and remains a valid `ctrl` argument. `UnitaryBlock <: ProcessValue` already
# inherits the generic `isapprox` (compares `denoted_matrix`, `src/kernel/algebra.jl`);
# these three methods SPECIALIZE the generic `∘`/`⊗` (which would fall back to a
# lazy `Seq`/`Tensor`) and supply the missing `adjoint`.
#
# PORT REMAPPING (F28 / §1.2). Two independently-certified blocks carry disjoint
# SSA `PortID`s and lineages; composing them requires positional identification of
# the shared boundary (`∘`) or a fresh disjoint boundary (`⊗`), plus fresh internal
# ancilla labels so no two nodes collide. The remapper rewrites a frozen body into
# fresh immutable nodes (never mutates the source — the source block stays valid).
#
# Physics grounding:
#   docs/physics/wharton_koch_quaternion_bloch.md — (pq)† = q̄†p̄† ⇒ adjoint
#     reverses composition and daggers each leaf; the block adjoint mirrors it.
#   docs/physics/bennett_1973_logical_reversibility.md — the adjoint of a clean
#     compute/uncompute program is clean (rule 6, §2.2).

# --- Fresh-label bookkeeping -------------------------------------------------

_maxid(b::UnitaryBlock) = maximum(
    Int[p.id.id for p in b.boundary];
    init = maximum(Int[nd.out.id.id for nd in b.body.nodes if nd isa AllocN]; init = 0))

_maxlin(b::UnitaryBlock) = maximum(
    Int[p.lineage for p in b.boundary];
    init = maximum(Int[nd.out.lineage for nd in b.body.nodes if nd isa AllocN]; init = 0))

"""
    _remap_nodes(nodes, idmap::Dict{PortID,PortID}, portmap::Dict{PortID,Port}) -> Vector{Node}

Rewrite a frozen node stream through a `PortID → PortID` map (for referenced edges)
and a `PortID → Port` map (for allocated ports, carrying the new lineage). Produces
fresh immutable nodes; the source is untouched (F28).
"""
function _remap_nodes(nodes, idmap::Dict{PortID,PortID}, portmap::Dict{PortID,Port})
    out = Node[]
    for nd in nodes
        if nd isa ApplyN
            push!(out, ApplyN(nd.v, Tuple(idmap[p] for p in nd.ports)))
        elseif nd isa AllocN
            push!(out, AllocN(portmap[nd.out.id]))
        elseif nd isa TraceN
            push!(out, TraceN(idmap[nd.in], nd.cert))
        else
            error("_remap_nodes: unexpected node $(typeof(nd)) in a UnitaryBlock body")
        end
    end
    return out
end

"""
    _rebase(b::UnitaryBlock, target_boundary, id_off, lin_off) -> (nodes, idmap)

Remap block `b` so its boundary ports become `target_boundary` (positional) and its
internal ancilla ports are shifted by `id_off`/`lin_off` into a fresh disjoint range.
Returns the remapped node vector and the `PortID` map (its boundary half is reused
by `⊗` to build the composed boundary).
"""
function _rebase(b::UnitaryBlock{N}, target_boundary, id_off::Int, lin_off::Int) where {N}
    idmap = Dict{PortID,PortID}()
    portmap = Dict{PortID,Port}()
    for i in 1:N
        idmap[b.boundary[i].id] = target_boundary[i].id
    end
    for nd in b.body.nodes
        nd isa AllocN || continue
        old = nd.out
        newport = Port(PortID(old.id.id + id_off), old.kind, old.lineage + lin_off)
        idmap[old.id] = newport.id
        portmap[old.id] = newport
    end
    return (_remap_nodes(b.body.nodes, idmap, portmap), idmap)
end

# --- adjoint (rule 6) --------------------------------------------------------

"""
    adjoint(b::UnitaryBlock{N}) -> UnitaryBlock{N}

`(alloc → W → trace)† = alloc → W† → trace` with the program REVERSED and every
`ApplyN` daggered, and the alloc/trace ends SWAPPED (a former alloc releases at the
reversed end, a former trace re-allocates — design §2.2 rule 6). Same boundary
(endomorphism preserved); cert `AdjointCert(b.cert)`. Sound because a clean block's
image invariance is an equality (unitarity), so `W†` preserves the clean subspace too.
"""
function Base.adjoint(b::UnitaryBlock{N}) where {N}
    id2port = Dict{PortID,Port}()
    for p in b.boundary
        id2port[p.id] = p
    end
    for nd in b.body.nodes
        nd isa AllocN && (id2port[nd.out.id] = nd.out)
    end
    newnodes = Node[]
    for nd in reverse(collect(b.body.nodes))
        if nd isa ApplyN
            push!(newnodes, ApplyN(adjoint(nd.v), nd.ports))
        elseif nd isa AllocN
            # former alloc → release (trace) at the reversed end.
            push!(newnodes, TraceN(nd.out.id, AdjointCert(NoAncilla())))
        elseif nd isa TraceN
            # former trace → re-allocate the same scratch port at the reversed end.
            push!(newnodes, AllocN(id2port[nd.in]))
        else
            error("adjoint(UnitaryBlock): unexpected node $(typeof(nd))")
        end
    end
    newbody = ChannelDAG(Tuple(newnodes), b.body.qin, b.body.qout, ())
    return UnitaryBlock{N}(b.boundary, newbody, AdjointCert(b.cert))
end

# --- ∘ (rule 4): same boundary, apply b first --------------------------------

"""
    ∘(a::UnitaryBlock{N}, b::UnitaryBlock{N}) -> UnitaryBlock{N}

Series composition on the SAME `N`-wire boundary (apply `b` first, `∘` is
right-to-left): denotes `A·B`. `b`'s boundary is identified POSITIONALLY with `a`'s
(wire `i` of `a` = wire `i` of `b`); `b`'s internal ancilla are relabeled fresh to
avoid collision. Cert `SeqCert(a.cert, b.cert)` (each block's ancilla stays local —
§2.2 rule 4). Returns a certified block, so `ctrl(a∘b)` is well-typed and equals
`ctrl(a)∘ctrl(b)` (test `M8.CTRL.BLOCK-HOMOMORPHISM`).
"""
function Base.:∘(a::UnitaryBlock{N}, b::UnitaryBlock{N}) where {N}
    (bnodes, _idmap) = _rebase(b, a.boundary, _maxid(a) + 1, _maxlin(a) + 1)
    nodes = vcat(bnodes, collect(a.body.nodes))   # b first, then a
    body = ChannelDAG(Tuple(nodes), a.body.qin, a.body.qout, ())
    return UnitaryBlock{N}(a.boundary, body, SeqCert(a.cert, b.cert))
end

# --- ⊗ (rule 5): disjoint boundary -------------------------------------------

"""
    ⊗(a::UnitaryBlock{Na}, b::UnitaryBlock{Nb}) -> UnitaryBlock{Na+Nb}

Parallel composition on DISJOINT wires (`a` on the leading/MSB block, `b` trailing):
denotes `A ⊗ B`. `b`'s boundary AND ancilla are remapped to a fresh disjoint range
beyond `a`'s labels; the composed boundary is `a.boundary ++ remapped(b.boundary)`.
Cert `ParCert(a.cert, b.cert)` (§2.2 rule 5).
"""
function ⊗(a::UnitaryBlock{Na}, b::UnitaryBlock{Nb}) where {Na,Nb}
    id_off = _maxid(a) + 1
    lin_off = _maxlin(a) + 1
    # fresh boundary ports for b (disjoint ids/lineages).
    bbound = Port[Port(PortID(p.id.id + id_off), p.kind, p.lineage + lin_off) for p in b.boundary]
    (bnodes, _idmap) = _rebase(b, bbound, id_off, lin_off)
    newboundary = (a.boundary..., bbound...)
    nodes = vcat(collect(a.body.nodes), bnodes)
    body = ChannelDAG(Tuple(nodes), newboundary, newboundary, ())
    return UnitaryBlock{Na + Nb}(newboundary, body, ParCert(a.cert, b.cert))
end
