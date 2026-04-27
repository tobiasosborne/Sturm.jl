"""
    to_openqasm(ch::Channel) -> String
    to_openqasm(dag::AbstractVector{<:DAGNode},
                input_wires::AbstractVector{WireID},
                output_wires::AbstractVector{WireID}) -> String

Export to OpenQASM 3.0.

The Channel form works on lowered circuits (no CasesNode); `trace()`
auto-lowers via `defer_measurements`. The raw-DAG form additionally
supports CasesNode → OpenQASM 3 dynamic-circuit `if (c[i] == 1) { ... }`
emission, for users who want to preserve classical branching in the
output.

Maps DAG nodes to QASM instructions:

  PrepNode(p)  → ry(2*asin(sqrt(p))) q
  RyNode(θ)    → ry(θ) q       (cry if 1 control; error if more)
  RzNode(θ)    → rz(θ) q       (crz if 1 control; error if more)
  CXNode       → cx control, target  (ccx if 1 extra; error if more)
  ObserveNode  → c[i] = measure q
  DiscardNode  → reset q       (partial trace ≈ reset)
  CasesNode    → if (c[i] == 1) { ... } [else { ... }]
"""
function to_openqasm(dag::AbstractVector{<:DAGNode},
                     input_wires::AbstractVector{WireID},
                     output_wires::AbstractVector{WireID})::String
    lines = String[]
    push!(lines, "OPENQASM 3.0;")
    push!(lines, "include \"stdgates.inc\";")
    push!(lines, "")

    # Wire collection (recursive over CasesNode bodies)
    all_wires = Set{WireID}()
    _collect_wires!(all_wires, dag)
    for w in input_wires; push!(all_wires, w); end
    for w in output_wires; push!(all_wires, w); end

    sorted_wires = sort(collect(all_wires); by=w -> w.id)
    wire_idx = Dict(w => i - 1 for (i, w) in enumerate(sorted_wires))
    n_qubits = length(sorted_wires)
    push!(lines, "qubit[$n_qubits] q;")

    # Pre-pass: assign bit indices to ObserveNodes by encounter order
    # (recursive over nested CasesNode branches). CasesNode emission then
    # references condition_id → bit_index via this map.
    result_to_bit = Dict{UInt32,Int}()
    _collect_observes!(result_to_bit, dag, Ref(0))
    if !isempty(result_to_bit)
        push!(lines, "bit[$(length(result_to_bit))] c;")
    end
    push!(lines, "")

    for node in dag
        _emit_node!(lines, node, wire_idx, result_to_bit, "")
    end

    return join(lines, "\n") * "\n"
end

# Channel-level dispatch: thin wrapper. ch.dag has no CasesNode (auto-lowered
# by trace()), so the dynamic-circuit emission paths are inert.
function to_openqasm(ch::Channel{In,Out}) where {In,Out}
    # Empty NTuple{0,WireID} would `collect` to Vector{Union{}}, which fails
    # method dispatch. Build properly-typed Vector{WireID}.
    in_wires = WireID[ch.input_wires...]
    out_wires = WireID[ch.output_wires...]
    return to_openqasm(ch.dag, in_wires, out_wires)
end

# ── Pre-pass: assign bit indices to all ObserveNodes (top-level + nested) ────

function _collect_observes!(map::Dict{UInt32,Int},
                            dag::AbstractVector{<:DAGNode},
                            counter::Ref{Int})
    for node in dag
        if node isa ObserveNode
            map[node.result_id] = counter[]
            counter[] += 1
        elseif node isa CasesNode
            _collect_observes!(map, node.true_branch, counter)
            _collect_observes!(map, node.false_branch, counter)
        end
    end
end

# ── Per-node emit (push to lines vector with proper indentation) ─────────────

function _emit_node!(lines::Vector{String}, node::PrepNode, idx, _map, indent::AbstractString)
    if node.p ≈ 0.0
        return  # |0⟩ is the default, no instruction needed
    end
    q = "q[$(idx[node.wire])]"
    angle = 2 * asin(sqrt(node.p))
    push!(lines, indent * "ry($angle) $q;")
end

function _emit_node!(lines::Vector{String}, node::RyNode, idx, _map, indent::AbstractString)
    q = "q[$(idx[node.wire])]"
    line = if node.ncontrols == 0
        "ry($(node.angle)) $q;"
    elseif node.ncontrols == 1
        c = "q[$(idx[node.ctrl1])]"
        "cry($(node.angle)) $c, $q;"
    else
        error("OpenQASM: multi-controlled Ry not supported (ncontrols=$(node.ncontrols))")
    end
    push!(lines, indent * line)
end

function _emit_node!(lines::Vector{String}, node::RzNode, idx, _map, indent::AbstractString)
    q = "q[$(idx[node.wire])]"
    line = if node.ncontrols == 0
        "rz($(node.angle)) $q;"
    elseif node.ncontrols == 1
        c = "q[$(idx[node.ctrl1])]"
        "crz($(node.angle)) $c, $q;"
    else
        error("OpenQASM: multi-controlled Rz not supported (ncontrols=$(node.ncontrols))")
    end
    push!(lines, indent * line)
end

function _emit_node!(lines::Vector{String}, node::CXNode, idx, _map, indent::AbstractString)
    ctrl = "q[$(idx[node.control])]"
    tgt = "q[$(idx[node.target])]"
    line = if node.ncontrols == 0
        "cx $ctrl, $tgt;"
    elseif node.ncontrols == 1
        extra = "q[$(idx[node.ctrl1])]"
        "ccx $extra, $ctrl, $tgt;"
    else
        error("OpenQASM: multi-controlled CX not supported (ncontrols=$(node.ncontrols))")
    end
    push!(lines, indent * line)
end

function _emit_node!(lines::Vector{String}, node::ObserveNode, idx, map, indent::AbstractString)
    q = "q[$(idx[node.wire])]"
    haskey(map, node.result_id) || error(
        "openqasm: ObserveNode references result_id $(node.result_id) " *
        "not in classical-bit map (wire-collection pass missed it)"
    )
    bit = map[node.result_id]
    push!(lines, indent * "c[$bit] = measure $q;")
end

function _emit_node!(lines::Vector{String}, node::DiscardNode, idx, _map, indent::AbstractString)
    push!(lines, indent * "reset q[$(idx[node.wire])];")
end

# OpenQASM 3 dynamic-circuit emission for CasesNode.
# Empty cases (both branches []) emits nothing — the preceding ObserveNode
# already recorded the measurement.
function _emit_node!(lines::Vector{String}, node::CasesNode, idx, map, indent::AbstractString)
    has_then = !isempty(node.true_branch)
    has_else = !isempty(node.false_branch)
    if !has_then && !has_else
        return
    end
    haskey(map, node.condition_id) || error(
        "openqasm: CasesNode references condition_id $(node.condition_id) " *
        "not in classical-bit map — every CasesNode must follow an " *
        "ObserveNode that produced this id (bead Sturm.jl-nemp)"
    )
    bit = map[node.condition_id]
    push!(lines, indent * "if (c[$bit] == 1) {")
    inner = indent * "    "
    if has_then
        for op in node.true_branch
            _emit_node!(lines, op, idx, map, inner)
        end
    end
    if has_else
        push!(lines, indent * "} else {")
        for op in node.false_branch
            _emit_node!(lines, op, idx, map, inner)
        end
    end
    push!(lines, indent * "}")
end

# ── Wire collection (recursive over CasesNode bodies) ────────────────────────

function _collect_wires!(set::Set{WireID}, dag::AbstractVector{<:DAGNode})
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
