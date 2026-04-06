"""
    to_openqasm(ch::Channel) -> String

Export a Channel as an OpenQASM 3.0 string.

Maps DAG nodes to QASM instructions:
  PrepNode(p) → reset q; ry(2*asin(sqrt(p))) q
  RyNode(θ)   → ry(θ) q
  RzNode(θ)   → rz(θ) q
  CXNode       → cx control, target
  ObserveNode  → bit = measure q
  DiscardNode  → reset q  (partial trace ≈ reset)
"""
function to_openqasm(ch::Channel{In, Out}) where {In, Out}
    lines = String[]
    push!(lines, "OPENQASM 3.0;")
    push!(lines, "include \"stdgates.inc\";")
    push!(lines, "")

    # Collect all wires used
    all_wires = Set{WireID}()
    _collect_wires!(all_wires, ch.dag)
    for w in ch.input_wires; push!(all_wires, w); end
    for w in ch.output_wires; push!(all_wires, w); end

    # Wire → qubit index mapping
    sorted_wires = sort(collect(all_wires), by=w -> w.id)
    wire_idx = Dict(w => i - 1 for (i, w) in enumerate(sorted_wires))
    n_qubits = length(sorted_wires)

    push!(lines, "qubit[$n_qubits] q;")

    # Count measurements for bit declarations
    n_bits = count(n -> n isa ObserveNode, ch.dag)
    if n_bits > 0
        push!(lines, "bit[$n_bits] c;")
    end
    push!(lines, "")

    # Emit instructions
    bit_counter = 0
    for node in ch.dag
        line = _node_to_qasm(node, wire_idx, Ref(bit_counter))
        if line !== nothing
            if node isa ObserveNode
                bit_counter += 1
            end
            push!(lines, line)
        end
    end

    return join(lines, "\n") * "\n"
end

function _node_to_qasm(node::RyNode, idx, _)
    q = "q[$(idx[node.wire])]"
    if node.ncontrols == 0
        "ry($(node.angle)) $q;"
    elseif node.ncontrols == 1
        c = "q[$(idx[node.ctrl1])]"
        "cry($(node.angle)) $c, $q;"
    else
        error("OpenQASM: multi-controlled Ry not supported")
    end
end

function _node_to_qasm(node::RzNode, idx, _)
    q = "q[$(idx[node.wire])]"
    if node.ncontrols == 0
        "rz($(node.angle)) $q;"
    elseif node.ncontrols == 1
        c = "q[$(idx[node.ctrl1])]"
        "crz($(node.angle)) $c, $q;"
    else
        error("OpenQASM: multi-controlled Rz not supported")
    end
end

function _node_to_qasm(node::CXNode, idx, _)
    ctrl = "q[$(idx[node.control])]"
    tgt = "q[$(idx[node.target])]"
    if node.ncontrols == 0
        "cx $ctrl, $tgt;"
    elseif node.ncontrols == 1
        extra = "q[$(idx[node.ctrl1])]"
        "ccx $extra, $ctrl, $tgt;"
    else
        error("OpenQASM: multi-controlled CX not supported")
    end
end

function _node_to_qasm(node::ObserveNode, idx, bit_ref)
    q = "q[$(idx[node.wire])]"
    "c[$(bit_ref[])] = measure $q;"
end

function _node_to_qasm(node::PrepNode, idx, _)
    q = "q[$(idx[node.wire])]"
    if node.p ≈ 0.0
        nothing  # |0⟩ is default, no instruction needed
    else
        angle = 2 * asin(sqrt(node.p))
        "ry($angle) $q;"
    end
end

function _node_to_qasm(node::DiscardNode, idx, _)
    "reset q[$(idx[node.wire])];"
end

function _node_to_qasm(node::CasesNode, idx, bit_ref)
    nothing  # Classical branching not emitted for now
end

# ── Wire collection ──────────────────────────────────────────────────────────

function _collect_wires!(set::Set{WireID}, dag::Vector{DAGNode})
    for node in dag
        _collect_wires!(set, node)
    end
end

function _collect_wires!(s::Set{WireID}, n::RyNode)
    push!(s, n.wire); for w in get_controls(n); push!(s, w); end
end
function _collect_wires!(s::Set{WireID}, n::RzNode)
    push!(s, n.wire); for w in get_controls(n); push!(s, w); end
end
function _collect_wires!(s::Set{WireID}, n::CXNode)
    push!(s, n.control); push!(s, n.target); for w in get_controls(n); push!(s, w); end
end
function _collect_wires!(s::Set{WireID}, n::ObserveNode)
    push!(s, n.wire)
end
function _collect_wires!(s::Set{WireID}, n::PrepNode)
    push!(s, n.wire); for w in get_controls(n); push!(s, w); end
end
function _collect_wires!(s::Set{WireID}, n::DiscardNode)
    push!(s, n.wire)
end
function _collect_wires!(s::Set{WireID}, n::CasesNode)
    _collect_wires!(s, n.true_branch)
    _collect_wires!(s, n.false_branch)
end
