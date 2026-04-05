# DAG node types for the tracing/channel representation.
# Each node represents a quantum operation in a circuit DAG.

"""Abstract base type for all DAG nodes."""
abstract type DAGNode end

"""Prepare a qubit: Ry(2·asin(√p))|0⟩ → state with P(|1⟩) = p."""
struct PrepNode <: DAGNode
    wire::WireID
    p::Float64           # preparation probability
    controls::Vector{WireID}
end
PrepNode(wire::WireID, p::Real) = PrepNode(wire, Float64(p), WireID[])

"""Amplitude rotation: Ry(angle) on target wire."""
struct RyNode <: DAGNode
    wire::WireID
    angle::Float64
    controls::Vector{WireID}
end
RyNode(wire::WireID, angle::Real) = RyNode(wire, Float64(angle), WireID[])

"""Phase rotation: Rz(angle) on target wire."""
struct RzNode <: DAGNode
    wire::WireID
    angle::Float64
    controls::Vector{WireID}
end
RzNode(wire::WireID, angle::Real) = RzNode(wire, Float64(angle), WireID[])

"""CNOT: control → target."""
struct CXNode <: DAGNode
    control::WireID
    target::WireID
    controls::Vector{WireID}   # additional controls from when() stack
end
CXNode(control::WireID, target::WireID) = CXNode(control, target, WireID[])

"""Measurement (type boundary): observe wire, produce classical result."""
struct ObserveNode <: DAGNode
    wire::WireID
    result_id::UInt32    # unique ID for the classical result
end

"""Classical branching: switch on a measurement outcome."""
struct CasesNode <: DAGNode
    condition_id::UInt32       # ObserveNode result_id to branch on
    true_branch::Vector{DAGNode}
    false_branch::Vector{DAGNode}
end

"""Discard a wire (partial trace)."""
struct DiscardNode <: DAGNode
    wire::WireID
end
