# Gate cancellation and rotation merging pass.
# Operates on a DAG (Vector{DAGNode}) and returns an optimised DAG.
#
# Uses per-wire candidate tracking for O(n) performance instead of
# backward linear scan (O(n²)). Commutation rules:
# - Rz on the control wire of a CX commutes with that CX
#   Physics: (Rz(θ)⊗I)·CNOT = CNOT·(Rz(θ)⊗I) — Nielsen & Chuang §4.2
# - Non-unitary nodes (Observe, Discard, Cases) are barriers

"""
    gate_cancel(dag::Vector{DAGNode}) -> Vector{DAGNode}

Optimise a DAG by:
1. Merging same-axis rotations on the same wire: Ry(a)…Ry(b) → Ry(a+b)
2. Cancelling inverse rotations: Ry(θ)…Ry(-θ) → removed
3. Cancelling CX pairs: CX(c,t)…CX(c,t) → removed
4. Removing identity rotations (angle ≈ 0)

Commutation-aware: Rz on the control wire of a CX does not block merging.
Iterates until no further simplifications are found.

Complexity: O(n) per pass, typically 1–3 passes to converge.
"""
function gate_cancel(dag::Vector{HotNode})::Vector{HotNode}
    result = dag
    changed = true
    while changed
        result, changed = _cancel_pass(result)
    end
    return result
end

# Backward compat: accept abstract Vector{DAGNode} (from tests / lowered output of
# `defer_measurements`). Errors loudly on any non-HotNode (typically a
# residual CasesNode — `defer_measurements(dag; strict=false)` may return one
# if the branches contain a non-pure-quantum op). Silently stripping would
# discard user-meaningful structure (Rule 1: fail fast, fail loud). See
# Sturm.jl-eiq.
function gate_cancel(dag::Vector{DAGNode})::Vector{HotNode}
    bad = findfirst(n -> !(n isa HotNode), dag)
    if bad !== nothing
        node = dag[bad]
        error("gate_cancel operates on HotNode only; got $(typeof(node)) at index " *
              "$bad. Lower classical-control IR first via `defer_measurements(dag)` " *
              "or `optimise(ch, :deferred)`. CasesNode is an intermediate IR form " *
              "that must be either lowered to controlled gates or emitted directly " *
              "(via the raw-DAG `to_openqasm`).")
    end
    gate_cancel(HotNode[n for n in dag])
end

# ── Merging ────────────────────────────────────────────────────────────

"""Check if two nodes can be merged (same type, same wire, same controls)."""
_can_merge(::DAGNode, ::DAGNode) = false
_can_merge(a::RyNode, b::RyNode) = a.wire == b.wire && _same_controls(a, b)
_can_merge(a::RzNode, b::RzNode) = a.wire == b.wire && _same_controls(a, b)
_can_merge(a::CXNode, b::CXNode) = a.control == b.control && a.target == b.target && _same_controls(a, b)

"""Merge two rotation nodes. Returns `nothing` if the result is identity."""
function _merge_rotations(a::RyNode, b::RyNode)
    total = mod(a.angle + b.angle + π, 2π) - π
    abs(total) < 1e-10 ? nothing : RyNode(total, a.wire, a.ctrl1, a.ctrl2, a.ncontrols)
end

function _merge_rotations(a::RzNode, b::RzNode)
    total = mod(a.angle + b.angle + π, 2π) - π
    abs(total) < 1e-10 ? nothing : RzNode(total, a.wire, a.ctrl1, a.ctrl2, a.ncontrols)
end

# CX · CX = I
_merge_rotations(::CXNode, ::CXNode) = nothing

# ── Per-wire indexed cancellation pass ────────────────────────────────
#
# Instead of scanning backward through the entire result for each node,
# we maintain per-wire candidate tables:
#   ry_cand[wire] = index of the last unblocked RyNode on this wire
#   rz_cand[wire] = index of the last unblocked RzNode on this wire
#   cx_cand[(ctrl,tgt)] = index of the last unblocked CXNode on this pair
#
# Blocking rules encode the commutation physics:
#   - Ry on wire w blocks: rz_cand[w], all CX involving w
#   - Rz on wire w blocks: ry_cand[w], CX where w is TARGET (not control!)
#   - CX(c,t) blocks: ry_cand[c], ry_cand[t], rz_cand[t] (not rz_cand[c]!)
#   - Any node on wire w blocks candidates that have w as a when()-control
#   - Non-unitary nodes block everything on their wires

function _cancel_pass(dag::Vector{HotNode})
    n = length(dag)
    result = Vector{HotNode}()
    sizehint!(result, n)
    deleted = BitSet()    # indices in result that were cancelled
    changed = false

    # Candidate tables
    ry_cand = Dict{WireID, Int}()
    rz_cand = Dict{WireID, Int}()
    cx_cand = Dict{Tuple{WireID,WireID}, Int}()

    for node in dag
        merged = _try_merge_node!(node, result, deleted, changed,
                                  ry_cand, rz_cand, cx_cand)
        if merged
            changed = true
        else
            push!(result, node)
            idx = length(result)
            _register_and_block!(node, idx, ry_cand, rz_cand, cx_cand)
        end
    end

    # Compact: remove cancelled entries
    if !isempty(deleted)
        result = HotNode[result[i] for i in eachindex(result) if !(i in deleted)]
    end

    return result, changed
end

# ── Try merge (function barrier for type-stable dispatch) ─────────────

function _try_merge_node!(node::RyNode, result, deleted, changed,
                          ry_cand, rz_cand, cx_cand)
    j = get(ry_cand, node.wire, 0)
    j > 0 && !(j in deleted) && _can_merge(result[j], node) || return false
    m = _merge_rotations(result[j], node)
    if m === nothing
        push!(deleted, j)
        delete!(ry_cand, node.wire)
    else
        result[j] = m
    end
    return true
end

function _try_merge_node!(node::RzNode, result, deleted, changed,
                          ry_cand, rz_cand, cx_cand)
    j = get(rz_cand, node.wire, 0)
    j > 0 && !(j in deleted) && _can_merge(result[j], node) || return false
    m = _merge_rotations(result[j], node)
    if m === nothing
        push!(deleted, j)
        delete!(rz_cand, node.wire)
    else
        result[j] = m
    end
    return true
end

function _try_merge_node!(node::CXNode, result, deleted, changed,
                          ry_cand, rz_cand, cx_cand)
    key = (node.control, node.target)
    j = get(cx_cand, key, 0)
    j > 0 && !(j in deleted) && _can_merge(result[j], node) || return false
    push!(deleted, j)
    delete!(cx_cand, key)
    return true
end

# Default: non-mergeable nodes (Observe, Discard, Cases, Prep)
_try_merge_node!(::DAGNode, result, deleted, changed,
                 ry_cand, rz_cand, cx_cand) = false

# ── Register candidate + apply blocking rules ────────────────────────

function _register_and_block!(node::RyNode, idx, ry_cand, rz_cand, cx_cand)
    w = node.wire
    ry_cand[w] = idx
    # Ry blocks Rz on same wire (don't commute)
    delete!(rz_cand, w)
    # Ry blocks CX involving this wire
    _remove_cx_with_wire!(cx_cand, w)
    # Acting on a control wire invalidates candidates controlled by it
    for c in get_controls(node)
        delete!(ry_cand, c)
        delete!(rz_cand, c)
        _remove_cx_with_wire!(cx_cand, c)
    end
end

function _register_and_block!(node::RzNode, idx, ry_cand, rz_cand, cx_cand)
    w = node.wire
    rz_cand[w] = idx
    # Rz blocks Ry on same wire
    delete!(ry_cand, w)
    # Rz blocks CX where w is TARGET (Rz on CX target doesn't commute)
    # Rz does NOT block CX where w is CONTROL (commutation rule!)
    _remove_cx_with_target!(cx_cand, w)
    for c in get_controls(node)
        delete!(ry_cand, c)
        delete!(rz_cand, c)
        _remove_cx_with_wire!(cx_cand, c)
    end
end

function _register_and_block!(node::CXNode, idx, ry_cand, rz_cand, cx_cand)
    ctrl, tgt = node.control, node.target
    # CX blocks Ry on control and target
    delete!(ry_cand, ctrl)
    delete!(ry_cand, tgt)
    # CX blocks Rz on TARGET only (Rz on control commutes!)
    delete!(rz_cand, tgt)
    # CX blocks other CX on these wires, then register self
    _remove_cx_with_wire!(cx_cand, ctrl)
    _remove_cx_with_wire!(cx_cand, tgt)
    cx_cand[(ctrl, tgt)] = idx
    for c in get_controls(node)
        delete!(ry_cand, c)
        delete!(rz_cand, c)
        _remove_cx_with_wire!(cx_cand, c)
    end
end

function _register_and_block!(node::DAGNode, idx, ry_cand, rz_cand, cx_cand)
    # Non-unitary / unknown: barrier on all wires
    for w in _barrier_wires(node)
        delete!(ry_cand, w)
        delete!(rz_cand, w)
        _remove_cx_with_wire!(cx_cand, w)
    end
end

# ── Helpers ───────────────────────────────────────────────────────────

# Collect wires for barrier nodes (allocation-tolerant — only called for rare barrier nodes).
#
# A "barrier" is a node whose presence invalidates the "two adjacent unitaries
# on this wire are eligible to fuse/cancel" reasoning gate_cancel relies on.
# Every non-unitary node is a barrier (CLAUDE.md "Channel IR vs Unitary Methods"):
#   * ObserveNode  — projective measurement, irreversible.
#   * DiscardNode  — partial trace, dimension-reducing.
#   * PrepNode     — wire reset to |p⟩; the wire's pre-prep history is no longer
#                     observable from the post-prep gates' point of view, so
#                     cancelling across a prep would erase information already
#                     committed to the channel's Choi matrix.
#   * CasesNode    — classical branching ⇒ mixture of channels; cancellation
#                     of a gate before/after a cases must hold IN BOTH branches,
#                     which gate_cancel does not analyse, so we conservatively
#                     barrier on every wire touched by either branch.
_barrier_wires(n::ObserveNode) = (n.wire,)
_barrier_wires(n::DiscardNode) = (n.wire,)
_barrier_wires(n::PrepNode)    = (n.wire,)
function _barrier_wires(n::CasesNode)
    s = Set{WireID}()
    for node in n.true_branch;  _collect_wires!(s, node); end
    for node in n.false_branch; _collect_wires!(s, node); end
    s
end
_barrier_wires(::DAGNode) = ()

# _collect_wires! methods are defined in channel/openqasm.jl (included before passes)

# Remove CX candidates involving a wire (as control or target)
function _remove_cx_with_wire!(cx_cand, w::WireID)
    isempty(cx_cand) && return
    to_del = nothing
    for key in keys(cx_cand)
        if key[1] == w || key[2] == w
            if to_del === nothing
                to_del = Tuple{WireID,WireID}[key]
            else
                push!(to_del, key)
            end
        end
    end
    if to_del !== nothing
        for key in to_del
            delete!(cx_cand, key)
        end
    end
end

# Remove CX candidates where wire is the target only
function _remove_cx_with_target!(cx_cand, w::WireID)
    isempty(cx_cand) && return
    to_del = nothing
    for key in keys(cx_cand)
        if key[2] == w
            if to_del === nothing
                to_del = Tuple{WireID,WireID}[key]
            else
                push!(to_del, key)
            end
        end
    end
    if to_del !== nothing
        for key in to_del
            delete!(cx_cand, key)
        end
    end
end

# Note: an earlier `_wires_of(::DAGNode) -> Set{WireID}` family lived here as
# a "legacy API". Grep confirmed zero callers across src/ and test/ — the
# new gate_cancel pipeline routes through `_register_and_block!` +
# `_barrier_wires`, which avoid the per-call `Set` allocation entirely. The
# block was removed (sweep bead ks0t).

# ── AbstractPass wrapper (Sturm.jl-7ab) ─────────────────────────────────────
#
# Barrier-aware: gate_cancel treats ObserveNode/DiscardNode as hard barriers
# via _barrier_wires (above), and errors loudly on CasesNode (the
# Vector{DAGNode} overload). Either way, no silent corruption, so
# handles_non_unitary = true.

"""
    GateCancelPass <: AbstractPass

Commutation-aware rotation merging + self-inverse cancellation. Wraps
[`gate_cancel`](@ref). Barrier-aware: treats ObserveNode/DiscardNode as
hard barriers, errors on CasesNode.
"""
struct GateCancelPass <: AbstractPass end

pass_name(::Type{GateCancelPass}) = :cancel
handles_non_unitary(::Type{GateCancelPass}) = true

run_pass(::GateCancelPass, dag::Vector{DAGNode}) =
    DAGNode[n for n in gate_cancel(dag)]

register_pass!(:cancel, GateCancelPass())
register_pass!(:cancel_adjacent, GateCancelPass())
