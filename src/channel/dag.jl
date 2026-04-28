# DAG node types for the tracing/channel representation.
# Each node represents a quantum operation in a circuit DAG.
#
# Controls are stored inline (max 2) to avoid per-node heap allocation.
# Fields ordered Float64-first to minimize padding (24 bytes, not 32).
#
# The hot path uses Vector{HotNode} (isbits union, inline storage at
# 25 bytes/element) instead of Vector{DAGNode} (abstract, boxed at
# ~56 bytes/element). CasesNode is NOT in HotNode — it's only used
# in test fixtures and deferred_measurement input.

"""Abstract base type for all DAG nodes."""
abstract type DAGNode end

# Sentinel for unused control slots in HotNode-flavoured DAG nodes
# (PrepNode/RyNode/RzNode/CXNode each carry a fixed-shape `ctrl1`,`ctrl2`
# pair populated from `ctx.control_stack`). When `ncontrols < 2`, the unused
# slots are filled with `_ZERO_WIRE`. Allocator invariant: `fresh_wire!`
# starts at 1 (see types/wire.jl), so `WireID(0)` is never a live wire — the
# sentinel cannot collide with a real control. Code that consumes `ctrl1`
# / `ctrl2` MUST gate on `ncontrols`, not on `wire == _ZERO_WIRE`, since
# the comparison is a soft check that a future allocator change could alias.
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
    n > 2 && error("Maximum 2 when()-controls supported, got $n")
    (UInt8(n),
     n >= 1 ? ctrls[1] : _ZERO_WIRE,
     n >= 2 ? ctrls[2] : _ZERO_WIRE)
end

"""Check if two nodes have the same controls."""
@inline function _same_controls(a, b)
    a.ncontrols == b.ncontrols && a.ctrl1 == b.ctrl1 && a.ctrl2 == b.ctrl2
end

# ── Node types (Float64 fields first to minimize padding) ───────────────────
#
# Field order: Float64 (8-byte aligned) first, then WireID (4-byte), then UInt8.
# This gives sizeof=24 instead of 32 for nodes with a Float64 field.

"""Prepare a qubit: Ry(2·asin(√p))|0⟩ → state with P(|1⟩) = p."""
struct PrepNode <: DAGNode
    p::Float64
    wire::WireID
    ctrl1::WireID
    ctrl2::WireID
    ncontrols::UInt8
end
PrepNode(wire::WireID, p::Real) = PrepNode(Float64(p), wire, _ZERO_WIRE, _ZERO_WIRE, UInt8(0))
function PrepNode(wire::WireID, p::Real, ctrls::Vector{WireID})
    nc, c1, c2 = _inline_controls(ctrls)
    PrepNode(Float64(p), wire, c1, c2, nc)
end
get_controls(n::PrepNode) = get_controls(n.ncontrols, n.ctrl1, n.ctrl2)

"""Amplitude rotation: Ry(angle) on target wire."""
struct RyNode <: DAGNode
    angle::Float64
    wire::WireID
    ctrl1::WireID
    ctrl2::WireID
    ncontrols::UInt8
end
RyNode(wire::WireID, angle::Real) = RyNode(Float64(angle), wire, _ZERO_WIRE, _ZERO_WIRE, UInt8(0))
function RyNode(wire::WireID, angle::Real, ctrls::Vector{WireID})
    nc, c1, c2 = _inline_controls(ctrls)
    RyNode(Float64(angle), wire, c1, c2, nc)
end
get_controls(n::RyNode) = get_controls(n.ncontrols, n.ctrl1, n.ctrl2)

"""Phase rotation: Rz(angle) on target wire."""
struct RzNode <: DAGNode
    angle::Float64
    wire::WireID
    ctrl1::WireID
    ctrl2::WireID
    ncontrols::UInt8
end
RzNode(wire::WireID, angle::Real) = RzNode(Float64(angle), wire, _ZERO_WIRE, _ZERO_WIRE, UInt8(0))
function RzNode(wire::WireID, angle::Real, ctrls::Vector{WireID})
    nc, c1, c2 = _inline_controls(ctrls)
    RzNode(Float64(angle), wire, c1, c2, nc)
end
get_controls(n::RzNode) = get_controls(n.ncontrols, n.ctrl1, n.ctrl2)

"""CNOT: control → target."""
struct CXNode <: DAGNode
    control::WireID
    target::WireID
    ctrl1::WireID
    ctrl2::WireID
    ncontrols::UInt8
end
CXNode(control::WireID, target::WireID) = CXNode(control, target, _ZERO_WIRE, _ZERO_WIRE, UInt8(0))
function CXNode(control::WireID, target::WireID, ctrls::Vector{WireID})
    nc, c1, c2 = _inline_controls(ctrls)
    CXNode(control, target, c1, c2, nc)
end
get_controls(n::CXNode) = get_controls(n.ncontrols, n.ctrl1, n.ctrl2)

"""Measurement (type boundary): observe wire, produce classical result."""
struct ObserveNode <: DAGNode
    wire::WireID
    result_id::UInt32
end

"""Classical branching: switch on a measurement outcome.
NOT in HotNode union — only used in test fixtures and deferred_measurement input."""
struct CasesNode <: DAGNode
    condition_id::UInt32
    true_branch::Vector{DAGNode}
    false_branch::Vector{DAGNode}
end

"""Discard a wire (partial trace)."""
struct DiscardNode <: DAGNode
    wire::WireID
end

# ── HotNode: isbits union for inline array storage ─────────────────────────
#
# Vector{HotNode} stores elements inline at max(sizeof) + 1 tag byte
# = 25 bytes/element. No GC boxing, no per-node heap allocation.
# CasesNode is excluded (not isbits — contains sub-DAG Vectors).
# When adding new isbits node types, add them to this union.
const HotNode = Union{RyNode, RzNode, CXNode, PrepNode, ObserveNode, DiscardNode}
