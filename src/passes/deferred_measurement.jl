# Deferred measurement pass.
# Replaces measure-then-classically-control patterns with quantum control.
#
# Ref: "Principle of Deferred Measurement" — Nielsen & Chuang, §4.4.
# Measurements can be moved to the end of a circuit if their outcomes
# only control subsequent quantum operations.

"""
    defer_measurements(dag::Vector{DAGNode}) -> Vector{DAGNode}

Identify ObserveNodes followed by CasesNodes where both branches contain
only quantum operations (no further measurements). Replace with controlled
operations: true_branch gets the measurement wire as control,
false_branch gets an anti-controlled version (X + control + X).

For v0.1: operates on the simple pattern where an ObserveNode is
immediately followed by a CasesNode referencing it. More complex
patterns (multiple uses of the same measurement result, non-adjacent
nodes) are deferred to future work.
"""
function defer_measurements(dag::Vector{DAGNode})::Vector{DAGNode}
    result = DAGNode[]
    i = 1

    while i <= length(dag)
        node = dag[i]

        if node isa ObserveNode && i < length(dag) && dag[i + 1] isa CasesNode
            cases = dag[i + 1]
            if cases.condition_id == node.result_id && _is_pure_quantum(cases)
                # Replace with quantum-controlled operations
                wire = node.wire
                # True branch: add wire as control
                for op in cases.true_branch
                    push!(result, _add_control(op, wire))
                end
                # False branch: X + control + X (anti-control)
                if !isempty(cases.false_branch)
                    push!(result, RyNode(wire, π, WireID[]))  # X gate
                    for op in cases.false_branch
                        push!(result, _add_control(op, wire))
                    end
                    push!(result, RyNode(wire, π, WireID[]))  # X gate (undo)
                end
                i += 2  # skip both ObserveNode and CasesNode
                continue
            end
        end

        push!(result, node)
        i += 1
    end

    return result
end

"""Check that a CasesNode contains only pure quantum operations (no measurements)."""
function _is_pure_quantum(cases::CasesNode)::Bool
    for op in cases.true_branch
        op isa ObserveNode && return false
        op isa CasesNode && return false
    end
    for op in cases.false_branch
        op isa ObserveNode && return false
        op isa CasesNode && return false
    end
    return true
end

"""Add a control wire to a DAG node."""
function _add_control(node::RyNode, ctrl::WireID)
    RyNode(node.wire, node.angle, [node.controls..., ctrl])
end
function _add_control(node::RzNode, ctrl::WireID)
    RzNode(node.wire, node.angle, [node.controls..., ctrl])
end
function _add_control(node::CXNode, ctrl::WireID)
    CXNode(node.control, node.target, [node.controls..., ctrl])
end
function _add_control(node::DAGNode, ctrl::WireID)
    error("Cannot add control to $(typeof(node))")
end
