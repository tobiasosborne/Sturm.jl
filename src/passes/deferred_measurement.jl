# Deferred measurement pass.
# Replaces measure-then-classically-control patterns with quantum control.
#
# Ref: "Principle of Deferred Measurement" — Nielsen & Chuang, §4.4.
# Measurements can be moved to the end of a circuit if their outcomes
# only control subsequent quantum operations.

"""
    defer_measurements(dag::Vector{DAGNode}; strict::Bool=false) -> Vector{DAGNode}

Identify ObserveNodes followed by CasesNodes and lower them per Nielsen-Chuang
§4.4 (principle of deferred measurement):

  - Empty CasesNode (both branches `[]`): drop the CasesNode, keep the
    ObserveNode (records measurement in IR for OpenQASM emission).
  - Pure-quantum CasesNode: replace ObserveNode + CasesNode with controlled
    gates. True branch gets the measurement wire as control; false branch
    is anti-controlled (X + control + X wrapper).

If `strict=true`, errors on un-lowerable patterns (CasesNode containing nested
measurements, orphaned CasesNode without preceding ObserveNode, condition_id
mismatch). The `trace()` function calls with `strict=true` to fail loudly on
nested measurements that can't be deferred.

For v0.1: operates on the simple pattern where an ObserveNode is immediately
followed by a CasesNode referencing it. More complex patterns (multiple uses
of the same measurement result, non-adjacent nodes) are deferred to future
work.
"""
function defer_measurements(dag::Vector{DAGNode}; strict::Bool=false)::Vector{DAGNode}
    result = DAGNode[]
    i = 1

    while i <= length(dag)
        node = dag[i]

        if node isa ObserveNode && i < length(dag) && dag[i + 1] isa CasesNode
            cases = dag[i + 1]
            if cases.condition_id == node.result_id
                if isempty(cases.true_branch) && isempty(cases.false_branch)
                    # Empty cases: keep the measurement, drop the empty branching.
                    push!(result, node)
                    i += 2
                    continue
                elseif _is_pure_quantum(cases)
                    wire = node.wire
                    for op in cases.true_branch
                        push!(result, _add_control(op, wire))
                    end
                    if !isempty(cases.false_branch)
                        push!(result, RyNode(wire, π))  # X gate
                        for op in cases.false_branch
                            push!(result, _add_control(op, wire))
                        end
                        push!(result, RyNode(wire, π))  # X gate (undo)
                    end
                    i += 2
                    continue
                elseif strict
                    error(
                        "defer_measurements: CasesNode for measurement #$(node.result_id) " *
                        "contains a nested measurement (ObserveNode or another CasesNode in a branch). " *
                        "Cannot lower to deferred-measurement controlled gates. " *
                        "Restructure the trace to remove nested measurements inside cases() bodies."
                    )
                end
            elseif strict
                error(
                    "defer_measurements: CasesNode condition_id=$(cases.condition_id) " *
                    "does not match preceding ObserveNode result_id=$(node.result_id)."
                )
            end
        end

        if node isa CasesNode && strict
            error(
                "defer_measurements: orphaned CasesNode (condition_id=$(node.condition_id)) " *
                "without an immediately preceding ObserveNode."
            )
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

"""Add a control wire to a DAG node (inline controls)."""
function _add_control(node::RyNode, ctrl::WireID)
    n = node.ncontrols
    n >= 2 && error("Cannot add control: already at maximum 2")
    n == 0 ? RyNode(node.angle, node.wire, ctrl, _ZERO_WIRE, UInt8(1)) :
             RyNode(node.angle, node.wire, node.ctrl1, ctrl, UInt8(2))
end
function _add_control(node::RzNode, ctrl::WireID)
    n = node.ncontrols
    n >= 2 && error("Cannot add control: already at maximum 2")
    n == 0 ? RzNode(node.angle, node.wire, ctrl, _ZERO_WIRE, UInt8(1)) :
             RzNode(node.angle, node.wire, node.ctrl1, ctrl, UInt8(2))
end
function _add_control(node::CXNode, ctrl::WireID)
    n = node.ncontrols
    n >= 2 && error("Cannot add control: already at maximum 2")
    n == 0 ? CXNode(node.control, node.target, ctrl, _ZERO_WIRE, UInt8(1)) :
             CXNode(node.control, node.target, node.ctrl1, ctrl, UInt8(2))
end
function _add_control(node::DAGNode, ctrl::WireID)
    error("Cannot add control to $(typeof(node))")
end

# ── AbstractPass wrapper (Sturm.jl-7ab) ─────────────────────────────────────
#
# Channel-aware: defer_measurements is the canonical lowering for
# ObserveNode + CasesNode → controlled gates (Nielsen-Chuang §4.4).
# handles_non_unitary = true.

"""
    DeferMeasurementsPass(strict::Bool = false) <: AbstractPass

Lower `ObserveNode + CasesNode` pairs to controlled-gate sequences per
Nielsen-Chuang §4.4 (deferred measurement). Wraps [`defer_measurements`](@ref).

  * `strict = true`: error on un-lowerable patterns (used by `trace()`).
  * `strict = false` (default): leave un-lowerable patterns intact.
"""
Base.@kwdef struct DeferMeasurementsPass <: AbstractPass
    strict::Bool = false
end

pass_name(::Type{DeferMeasurementsPass}) = :deferred
handles_non_unitary(::Type{DeferMeasurementsPass}) = true

run_pass(p::DeferMeasurementsPass, dag::Vector{DAGNode}) =
    defer_measurements(dag; strict = p.strict)

register_pass!(:deferred, DeferMeasurementsPass())
register_pass!(:defer_measurements, DeferMeasurementsPass())
