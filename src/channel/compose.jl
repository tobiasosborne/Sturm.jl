# Channel composition operators.

"""
    ≫(f::Channel, g::Channel) -> Channel

Sequential composition: connect output wires of f to input wires of g.
Requires n_outputs(f) == n_inputs(g).
"""
function Base.:>>(f::Channel{InF, Mid}, g::Channel{Mid, OutG}) where {InF, Mid, OutG}
    # Build wire renaming: g's input wires → f's output wires
    rename = Dict{WireID, WireID}()
    for i in 1:Mid
        rename[g.input_wires[i]] = f.output_wires[i]
    end

    # Rename wires in g's DAG
    merged_dag = copy(f.dag)
    for node in g.dag
        push!(merged_dag, _rename_node(node, rename))
    end

    # g's output wires, renamed
    out = ntuple(i -> get(rename, g.output_wires[i], g.output_wires[i]), OutG)
    return Channel{InF, OutG}(merged_dag, f.input_wires, out)
end

"""
    ⊗(f::Channel, g::Channel) -> Channel

Parallel (tensor) composition: disjoint wire sets, concatenated DAGs.

Errors loudly (Sturm.jl-5jlo) when the two operand channels share any
WireID — anywhere in either DAG, including ancillae and controls. Without
this check, a user composing two channels that happened to share a wire
ID (e.g. from `reset_wire_counter!` between two `trace()` calls, or from
hand-constructed channels in tests) would silently get aliased wires
producing wrong physics.
"""
function ⊗(f::Channel{InF, OutF}, g::Channel{InG, OutG}) where {InF, OutF, InG, OutG}
    fw = _collect_wires(f)
    gw = _collect_wires(g)
    shared = intersect(fw, gw)
    isempty(shared) ||
        error("⊗: operand channels must have disjoint wire IDs; shared: " *
              join(sort!([w.id for w in shared]), ", "))
    merged_dag = vcat(f.dag, g.dag)
    in_wires = (f.input_wires..., g.input_wires...)
    out_wires = (f.output_wires..., g.output_wires...)
    return Channel{InF + InG, OutF + OutG}(merged_dag, in_wires, out_wires)
end

# Sturm.jl-5jlo helper: collect every WireID referenced by a Channel
# (input wires, output wires, and every DAG node's target + controls).
# Excludes _ZERO_WIRE (the sentinel for unused control slots).
function _collect_wires(ch::Channel)
    s = Set{WireID}()
    for w in ch.input_wires;  push!(s, w); end
    for w in ch.output_wires; push!(s, w); end
    for node in ch.dag
        _add_node_wires!(s, node)
    end
    delete!(s, _ZERO_WIRE)
    return s
end

@inline function _add_node_wires!(s::Set{WireID}, n::PrepNode)
    push!(s, n.wire)
    n.ncontrols >= 1 && push!(s, n.ctrl1)
    n.ncontrols >= 2 && push!(s, n.ctrl2)
end
@inline function _add_node_wires!(s::Set{WireID}, n::RyNode)
    push!(s, n.wire)
    n.ncontrols >= 1 && push!(s, n.ctrl1)
    n.ncontrols >= 2 && push!(s, n.ctrl2)
end
@inline function _add_node_wires!(s::Set{WireID}, n::RzNode)
    push!(s, n.wire)
    n.ncontrols >= 1 && push!(s, n.ctrl1)
    n.ncontrols >= 2 && push!(s, n.ctrl2)
end
@inline function _add_node_wires!(s::Set{WireID}, n::CXNode)
    push!(s, n.control); push!(s, n.target)
    n.ncontrols >= 1 && push!(s, n.ctrl1)
    n.ncontrols >= 2 && push!(s, n.ctrl2)
end
@inline function _add_node_wires!(s::Set{WireID}, n::ObserveNode)
    push!(s, n.wire)
end
@inline function _add_node_wires!(s::Set{WireID}, n::DiscardNode)
    push!(s, n.wire)
end

# ── Wire renaming helpers ────────────────────────────────────────────────────

function _rename_wire(w::WireID, rename::Dict{WireID, WireID})
    get(rename, w, w)
end

function _rename_controls(node, rename)
    nc = node.ncontrols
    c1 = nc >= 1 ? _rename_wire(node.ctrl1, rename) : _ZERO_WIRE
    c2 = nc >= 2 ? _rename_wire(node.ctrl2, rename) : _ZERO_WIRE
    (c1, c2, nc)
end

function _rename_node(node::PrepNode, rename)
    c1, c2, nc = _rename_controls(node, rename)
    PrepNode(node.p, _rename_wire(node.wire, rename), c1, c2, nc)
end
function _rename_node(node::RyNode, rename)
    c1, c2, nc = _rename_controls(node, rename)
    RyNode(node.angle, _rename_wire(node.wire, rename), c1, c2, nc)
end
function _rename_node(node::RzNode, rename)
    c1, c2, nc = _rename_controls(node, rename)
    RzNode(node.angle, _rename_wire(node.wire, rename), c1, c2, nc)
end
function _rename_node(node::CXNode, rename)
    c1, c2, nc = _rename_controls(node, rename)
    CXNode(_rename_wire(node.control, rename), _rename_wire(node.target, rename), c1, c2, nc)
end
function _rename_node(node::ObserveNode, rename)
    ObserveNode(_rename_wire(node.wire, rename), node.result_id)
end
function _rename_node(node::DiscardNode, rename)
    DiscardNode(_rename_wire(node.wire, rename))
end
function _rename_node(node::CasesNode, rename)
    CasesNode(node.condition_id,
              [_rename_node(n, rename) for n in node.true_branch],
              [_rename_node(n, rename) for n in node.false_branch])
end
