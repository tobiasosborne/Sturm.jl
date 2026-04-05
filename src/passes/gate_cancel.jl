# Gate cancellation and rotation merging pass.
# Operates on a DAG (Vector{DAGNode}) and returns an optimised DAG.

"""
    gate_cancel(dag::Vector{DAGNode}) -> Vector{DAGNode}

Optimise a DAG by:
1. Cancelling adjacent inverse rotations: Ry(θ) then Ry(-θ) → removed
2. Merging adjacent same-axis rotations: Ry(a) then Ry(b) → Ry(a+b)
3. Removing rotations by 0 (or ≈ 0)

Only merges consecutive nodes on the same wire with identical controls.
Does not reorder nodes (preserving causal order).
"""
function gate_cancel(dag::Vector{DAGNode})::Vector{DAGNode}
    result = DAGNode[]

    for node in dag
        if !isempty(result) && _can_merge(result[end], node)
            merged = _merge_rotations(result[end], node)
            if merged === nothing
                pop!(result)  # merged to zero — remove both
            else
                result[end] = merged  # replace last with merged
            end
        else
            push!(result, node)
        end
    end

    return result
end

"""Check if two nodes can be merged (same type, same wire, same controls)."""
function _can_merge(a::DAGNode, b::DAGNode)::Bool
    return false  # default: no merging
end

function _can_merge(a::RyNode, b::RyNode)::Bool
    a.wire == b.wire && a.controls == b.controls
end

function _can_merge(a::RzNode, b::RzNode)::Bool
    a.wire == b.wire && a.controls == b.controls
end

"""Merge two rotation nodes. Returns nothing if the result is identity (angle ≈ 0)."""
function _merge_rotations(a::RyNode, b::RyNode)
    total = a.angle + b.angle
    # Normalize to [-π, π] range and check for zero
    total = mod(total + π, 2π) - π
    abs(total) < 1e-10 ? nothing : RyNode(a.wire, total, copy(a.controls))
end

function _merge_rotations(a::RzNode, b::RzNode)
    total = a.angle + b.angle
    total = mod(total + π, 2π) - π
    abs(total) < 1e-10 ? nothing : RzNode(a.wire, total, copy(a.controls))
end
