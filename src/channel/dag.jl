# DAG node types for the tracing/channel representation.
# Each node represents a quantum operation in a circuit DAG.
#
# Controls are stored inline (max 2) to avoid per-node heap allocation.
# This makes nodes isbitstype, enabling stack allocation and eliminating
# the ~2M Vector{WireID} copies in a 2000-qubit QFT trace.

"""Abstract base type for all DAG nodes."""
abstract type DAGNode end

# Sentinel wire for unused control slots
const _ZERO_WIRE = WireID(UInt32(0))

# ── Inline controls helpers ─────────────────────────────────────────────────

"""Return controls as a tuple (zero allocation)."""
@inline function get_controls(ncontrols::UInt8, ctrl1::WireID, ctrl2::WireID)
    ncontrols == 0 && return ()
    ncontrols == 1 && return (ctrl1,)
    return (ctrl1, ctrl2)
end

"""Build inline controls from a Vector (backward compat, used at boundaries)."""
@inline function _inline_controls(ctrls::Vector{WireID})
    n = length(ctrls)
    n > 2 && error("Maximum 2 when()-controls supported, got $n. Deeper nesting requires Phase 3 flat DAG.")
    (UInt8(n),
     n >= 1 ? ctrls[1] : _ZERO_WIRE,
     n >= 2 ? ctrls[2] : _ZERO_WIRE)
end

"""Check if two nodes have the same controls."""
@inline function _same_controls(a, b)
    a.ncontrols == b.ncontrols && a.ctrl1 == b.ctrl1 && a.ctrl2 == b.ctrl2
end

# ── Node types ──────────────────────────────────────────────────────────────

"""Prepare a qubit: Ry(2·asin(√p))|0⟩ → state with P(|1⟩) = p."""
struct PrepNode <: DAGNode
    wire::WireID
    p::Float64
    ncontrols::UInt8
    ctrl1::WireID
    ctrl2::WireID
end
PrepNode(wire::WireID, p::Real) = PrepNode(wire, Float64(p), UInt8(0), _ZERO_WIRE, _ZERO_WIRE)
PrepNode(wire::WireID, p::Real, ctrls::Vector{WireID}) = PrepNode(wire, Float64(p), _inline_controls(ctrls)...)
get_controls(n::PrepNode) = get_controls(n.ncontrols, n.ctrl1, n.ctrl2)

"""Amplitude rotation: Ry(angle) on target wire."""
struct RyNode <: DAGNode
    wire::WireID
    angle::Float64
    ncontrols::UInt8
    ctrl1::WireID
    ctrl2::WireID
end
RyNode(wire::WireID, angle::Real) = RyNode(wire, Float64(angle), UInt8(0), _ZERO_WIRE, _ZERO_WIRE)
RyNode(wire::WireID, angle::Real, ctrls::Vector{WireID}) = RyNode(wire, Float64(angle), _inline_controls(ctrls)...)
get_controls(n::RyNode) = get_controls(n.ncontrols, n.ctrl1, n.ctrl2)

"""Phase rotation: Rz(angle) on target wire."""
struct RzNode <: DAGNode
    wire::WireID
    angle::Float64
    ncontrols::UInt8
    ctrl1::WireID
    ctrl2::WireID
end
RzNode(wire::WireID, angle::Real) = RzNode(wire, Float64(angle), UInt8(0), _ZERO_WIRE, _ZERO_WIRE)
RzNode(wire::WireID, angle::Real, ctrls::Vector{WireID}) = RzNode(wire, Float64(angle), _inline_controls(ctrls)...)
get_controls(n::RzNode) = get_controls(n.ncontrols, n.ctrl1, n.ctrl2)

"""CNOT: control → target."""
struct CXNode <: DAGNode
    control::WireID
    target::WireID
    ncontrols::UInt8
    ctrl1::WireID
    ctrl2::WireID
end
CXNode(control::WireID, target::WireID) = CXNode(control, target, UInt8(0), _ZERO_WIRE, _ZERO_WIRE)
CXNode(control::WireID, target::WireID, ctrls::Vector{WireID}) = CXNode(control, target, _inline_controls(ctrls)...)
get_controls(n::CXNode) = get_controls(n.ncontrols, n.ctrl1, n.ctrl2)

"""Measurement (type boundary): observe wire, produce classical result."""
struct ObserveNode <: DAGNode
    wire::WireID
    result_id::UInt32
end

"""Classical branching: switch on a measurement outcome."""
struct CasesNode <: DAGNode
    condition_id::UInt32
    true_branch::Vector{DAGNode}
    false_branch::Vector{DAGNode}
end

"""Discard a wire (partial trace)."""
struct DiscardNode <: DAGNode
    wire::WireID
end
