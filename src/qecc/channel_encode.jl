# Higher-order QECC encode: encode(ch::Channel, code::AbstractCode) -> Channel
#
# PRD P6: "QECC is a higher-order function (Channel → Channel). It wraps a
# function in encoding and decoding. It is not a language feature, annotation,
# or pragma. It is a library function."
#
# PRD §8.5 reference program:
#   ch = trace(teleport!)
#   ch_enc = encode(ch, Steane())      # higher-order QECC
#   qasm = to_openqasm(ch_enc)
#
# v0.1 scope (this file):
#   - Input channel must be a pure unitary: no ObserveNode, CasesNode,
#     DiscardNode, or PrepNode inside the DAG.
#   - All rotation angles must be multiples of π/2 (Clifford-only).
#     Non-Clifford gates (T, T†, arbitrary Ry/Rz) are rejected — they
#     require magic-state distillation, deferred to v0.2.
#   - No nested when() controls (ncontrols must be 0). Nested-control
#     transversalization for CSS codes requires additional machinery
#     (Steane trick / syndrome extraction), deferred to v0.2.
#   - The channel must be transversal-preserving under the code: for
#     Steane [[7,1,3]], the code is CSS self-dual, so transversal
#     Cliffords (X/Y/Z/H/S/CNOT on each physical qubit pair) are valid
#     logical operations.
#
# v0.2 follow-ups (tracked separately):
#   - Sturm.jl-971: syndrome extraction + correction (measurement handling)
#   - T gate via magic-state teleportation
#   - General controlled logical operations

const _CLIFFORD_ANGLE_TOL = 1e-10

"""Check whether `θ` is close to a multiple of π/2 (a Clifford angle for Ry/Rz)."""
@inline function _is_clifford_angle(θ::Float64)
    k = θ / (π/2)
    abs(k - round(k)) < _CLIFFORD_ANGLE_TOL
end

"""
    encode(ch::Channel{In, Out}, code::AbstractCode) -> Channel{In, Out}

Wrap a logical channel in the given error-correcting code (PRD P6). The
result is a new Channel with the same logical input/output signature,
but internally every logical qubit is represented as a code-block of
physical qubits, and every logical gate is implemented transversally.

Currently supports Clifford unitary channels only. See the file header
for v0.1 scope and v0.2 deferred work.

# Example
```julia
ch = trace(1) do q; X!(q); q; end          # Channel{1,1}, logical X
ch_enc = encode(ch, Steane())              # Channel{1,1}, transversal X on [[7,1,3]]
```
"""
function encode(ch::Channel{In, Out}, code::AbstractCode) where {In, Out}
    _assert_clifford_unitary(ch)

    # Build the encoded channel by tracing a new circuit in a fresh context.
    # Inside: encode every logical input, replay the DAG transversally, decode
    # every logical output.
    return trace(In) do logical_inputs...
        # Normalize: trace passes a single QBool for In==1, varargs otherwise.
        # Collect into a tuple either way.
        qs = In == 1 ? (logical_inputs[1],) : logical_inputs

        # Encode each logical input into a physical block.
        # `blocks[i]` is NTuple{N, QBool} where N depends on the code.
        blocks = map(q -> encode!(code, q), qs)

        # Wire map: original logical WireID → tuple of physical WireIDs.
        wire_map = Dict{WireID, Tuple{Vararg{WireID}}}()
        for i in 1:In
            wire_map[ch.input_wires[i]] = ntuple(j -> blocks[i][j].wire, length(blocks[i]))
        end

        # Replay each node of the original DAG transversally.
        ctx = current_context()
        for node in ch.dag
            _emit_transversal!(ctx, node, wire_map)
        end

        # Decode each logical output.
        # ch.output_wires indexes into the ORIGINAL context's wires; look up
        # the corresponding physical block via wire_map and decode it.
        if Out == 0
            return nothing
        elseif Out == 1
            block_wires = wire_map[ch.output_wires[1]]
            block = ntuple(i -> QBool(block_wires[i], ctx, false), length(block_wires))
            return decode!(code, block)
        else
            return ntuple(Out) do i
                block_wires = wire_map[ch.output_wires[i]]
                block = ntuple(j -> QBool(block_wires[j], ctx, false), length(block_wires))
                decode!(code, block)
            end
        end
    end
end

# ── DAG validation ──────────────────────────────────────────────────────────

"""Reject channels containing non-unitary or non-Clifford nodes."""
function _assert_clifford_unitary(ch::Channel)
    for (i, node) in enumerate(ch.dag)
        _assert_node_clifford_unitary(node, i)
    end
end

function _assert_node_clifford_unitary(n::RyNode, idx::Int)
    n.ncontrols == 0 || error(
        "encode(::Channel, ::AbstractCode) v0.1: node $idx (Ry) has nested " *
        "when-controls. Nested-control transversalization requires syndrome " *
        "extraction and is deferred to v0.2.")
    _is_clifford_angle(n.angle) || error(
        "encode(::Channel, ::AbstractCode) v0.1: node $idx Ry angle $(n.angle) " *
        "is not a Clifford angle (multiple of π/2). Non-Clifford rotations " *
        "require magic-state distillation, deferred to v0.2.")
end

function _assert_node_clifford_unitary(n::RzNode, idx::Int)
    n.ncontrols == 0 || error(
        "encode(::Channel, ::AbstractCode) v0.1: node $idx (Rz) has nested " *
        "when-controls. Deferred to v0.2.")
    _is_clifford_angle(n.angle) || error(
        "encode(::Channel, ::AbstractCode) v0.1: node $idx Rz angle $(n.angle) " *
        "is not a Clifford angle. Deferred to v0.2.")
end

function _assert_node_clifford_unitary(n::CXNode, idx::Int)
    n.ncontrols == 0 || error(
        "encode(::Channel, ::AbstractCode) v0.1: node $idx (CX) has nested " *
        "when-controls. Deferred to v0.2.")
end

_assert_node_clifford_unitary(::PrepNode, idx::Int) = error(
    "encode(::Channel, ::AbstractCode) v0.1: node $idx is a PrepNode. " *
    "Mid-circuit preparation is deferred to v0.2. Use only input/output wires.")

_assert_node_clifford_unitary(::ObserveNode, idx::Int) = error(
    "encode(::Channel, ::AbstractCode) v0.1: node $idx is an ObserveNode. " *
    "Measurement requires syndrome extraction (Sturm.jl-971), deferred to v0.2.")

_assert_node_clifford_unitary(::DiscardNode, idx::Int) = error(
    "encode(::Channel, ::AbstractCode) v0.1: node $idx is a DiscardNode. " *
    "Partial trace on encoded blocks is deferred to v0.2.")

# ── Transversal emission ────────────────────────────────────────────────────

"""
Emit a transversal version of `node` into `ctx`, using `wire_map` to resolve
original (logical) wire IDs to tuples of physical wire IDs.
"""
function _emit_transversal!(ctx::AbstractContext, n::RyNode,
                            wire_map::Dict{WireID, Tuple{Vararg{WireID}}})
    phys_wires = wire_map[n.wire]
    for w in phys_wires
        apply_ry!(ctx, w, n.angle)
    end
end

function _emit_transversal!(ctx::AbstractContext, n::RzNode,
                            wire_map::Dict{WireID, Tuple{Vararg{WireID}}})
    phys_wires = wire_map[n.wire]
    for w in phys_wires
        apply_rz!(ctx, w, n.angle)
    end
end

function _emit_transversal!(ctx::AbstractContext, n::CXNode,
                            wire_map::Dict{WireID, Tuple{Vararg{WireID}}})
    # Transversal CNOT between two code blocks: pairwise CX between
    # corresponding physical wires. Valid for CSS codes (Steane in v0.1).
    c_wires = wire_map[n.control]
    t_wires = wire_map[n.target]
    length(c_wires) == length(t_wires) || error(
        "encode: transversal CNOT requires same block size, got " *
        "$(length(c_wires)) vs $(length(t_wires))")
    for i in 1:length(c_wires)
        apply_cx!(ctx, c_wires[i], t_wires[i])
    end
end
