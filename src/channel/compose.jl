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
"""
function ⊗(f::Channel{InF, OutF}, g::Channel{InG, OutG}) where {InF, OutF, InG, OutG}
    merged_dag = vcat(f.dag, g.dag)
    in_wires = (f.input_wires..., g.input_wires...)
    out_wires = (f.output_wires..., g.output_wires...)
    return Channel{InF + InG, OutF + OutG}(merged_dag, in_wires, out_wires)
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
