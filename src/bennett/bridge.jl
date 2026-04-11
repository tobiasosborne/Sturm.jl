# Bennett.jl integration: execute reversible circuits on Sturm contexts.
#
# Gate mapping (exact, lossless):
#   NOTGate(t)            → apply_ry!(ctx, t, π)     [X gate]
#   CNOTGate(c, t)        → apply_cx!(ctx, c, t)
#   ToffoliGate(c1, c2, t) → apply_ccx!(ctx, c1, c2, t)
#
# If called inside when(), all gates are automatically controlled
# via the existing control stack — no need for Bennett's controlled().

using Bennett: ReversibleCircuit, ReversibleGate,
               NOTGate, CNOTGate, ToffoliGate, WireIndex,
               reversible_compile, gate_count, t_depth

"""
    apply_reversible!(ctx, circuit, input_map)

Execute a Bennett-compiled reversible circuit on a Sturm context.

`input_map` maps Bennett `WireIndex` → Sturm `WireID` for all non-ancilla wires
(both input and output). Ancilla qubits are allocated internally and deallocated
after execution (Bennett's construction guarantees they return to |0⟩).

If called inside a `when()` block, all gates automatically pick up the
quantum control from the control stack.
"""
function apply_reversible!(ctx::AbstractContext,
                           circuit::ReversibleCircuit,
                           input_map::Dict{WireIndex, WireID})
    wire_map = copy(input_map)

    # Allocate ancilla qubits (all start at |0⟩)
    ancilla_sturm = WireID[]
    for aw in circuit.ancilla_wires
        w = allocate!(ctx)
        wire_map[aw] = w
        push!(ancilla_sturm, w)
    end

    try
        for gate in circuit.gates
            _apply_bennett_gate!(ctx, gate, wire_map)
        end
    finally
        # Deallocate ancillae — Bennett guarantees they're |0⟩
        for w in ancilla_sturm
            deallocate!(ctx, w)
        end
    end
end

@inline function _apply_bennett_gate!(ctx::AbstractContext, g::NOTGate,
                                       wm::Dict{WireIndex, WireID})
    apply_ry!(ctx, wm[g.target], π)
end

@inline function _apply_bennett_gate!(ctx::AbstractContext, g::CNOTGate,
                                       wm::Dict{WireIndex, WireID})
    apply_cx!(ctx, wm[g.control], wm[g.target])
end

@inline function _apply_bennett_gate!(ctx::AbstractContext, g::ToffoliGate,
                                       wm::Dict{WireIndex, WireID})
    c1 = wm[g.control1]
    c2 = wm[g.control2]
    if c1 == c2
        # Toffoli(a, a, t) = CNOT(a, t) since a ∧ a = a
        apply_cx!(ctx, c1, wm[g.target])
    else
        apply_ccx!(ctx, c1, c2, wm[g.target])
    end
end

"""
    build_wire_map(circuit, input_sturm_wires, output_sturm_wires)

Map Bennett circuit input/output wire indices to Sturm WireIDs.
"""
function build_wire_map(circuit::ReversibleCircuit,
                        input_sturm::Vector{WireID},
                        output_sturm::Vector{WireID})::Dict{WireIndex, WireID}
    length(input_sturm) == length(circuit.input_wires) ||
        error("Input wire count mismatch: got $(length(input_sturm)), " *
              "circuit expects $(length(circuit.input_wires))")
    length(output_sturm) == length(circuit.output_wires) ||
        error("Output wire count mismatch: got $(length(output_sturm)), " *
              "circuit expects $(length(circuit.output_wires))")

    wm = Dict{WireIndex, WireID}()
    for (bw, sw) in zip(circuit.input_wires, input_sturm)
        wm[bw] = sw
    end
    for (bw, sw) in zip(circuit.output_wires, output_sturm)
        wm[bw] = sw
    end
    return wm
end

"""
    apply_oracle!(ctx, f, arg_type, input_wires, output_wires; kw...)

Compile a plain Julia function `f` to a reversible circuit via Bennett.jl
and execute it on the Sturm context. Returns the compiled circuit for
resource inspection.

If called inside `when()`, the oracle is automatically controlled.
"""
function apply_oracle!(ctx::AbstractContext, f, arg_type::Type,
                        input_wires::Vector{WireID},
                        output_wires::Vector{WireID}; kw...)
    circuit = reversible_compile(f, arg_type; kw...)
    wm = build_wire_map(circuit, input_wires, output_wires)
    apply_reversible!(ctx, circuit, wm)
    return circuit
end

"""
    estimate_oracle_resources(f, arg_type; kw...) -> NamedTuple

Resource estimates for compiling `f` as a reversible quantum oracle.
Returns gate count, Toffoli count, T-count (7 per Toffoli), qubit count, T-depth.
"""
function estimate_oracle_resources(f, arg_type::Type; kw...)
    circuit = reversible_compile(f, arg_type; kw...)
    gc = gate_count(circuit)
    return (gates=gc.total, toffoli=gc.Toffoli, t_count=gc.Toffoli * 7,
            qubits=circuit.n_wires, t_depth=t_depth(circuit))
end

# ── Ergonomic API: oracle(f, x) and quantum(f) ─────────────────────────────
# Parallels Enzyme.gradient(f, x): a higher-order function that takes a plain
# Julia function and a quantum register, compiles via Bennett, and executes.

"""
    oracle(f, x::QInt{W}; kw...) -> QInt{W}

Compile a plain Julia function `f` to a reversible quantum circuit via Bennett.jl
and execute it on the quantum register `x`. Returns a new `QInt{W}` containing
`f(x)`. The input register `x` is preserved (Bennett's construction keeps inputs
intact).

If called inside `when()`, the oracle is automatically controlled.

# Example
```julia
@context EagerContext() begin
    x = QInt{2}(3)
    y = oracle(x -> x + Int8(1), x)
    @assert Int(y) == 0   # (3+1) mod 4 = 0
    @assert Int(x) == 3   # input preserved
end
```
"""
function oracle(f, x::QInt{W}; kw...) where W
    check_live!(x)
    ctx = x.ctx

    circuit = reversible_compile(f, Int8; bit_width=W, kw...)

    # Extract input wires from QInt (little-endian)
    input_wires = WireID[x.wires[i] for i in 1:W]

    # Allocate output wires (all |0⟩)
    output_wires_tuple = ntuple(Val(W)) do _
        allocate!(ctx)
    end
    output_vec = WireID[output_wires_tuple[i] for i in 1:W]

    # Build map + execute (control stack applies automatically if inside when())
    wm = build_wire_map(circuit, input_wires, output_vec)
    apply_reversible!(ctx, circuit, wm)

    return QInt{W}(output_wires_tuple, ctx, false)
end

"""
    QuantumOracle{F}

A pre-compiled quantum oracle wrapping a plain Julia function `f`.
Caches Bennett circuits per bit-width. Created via `quantum(f)`.

Callable on `QInt{W}`: `qf(x)` is equivalent to `oracle(f, x)` but
reuses the cached circuit instead of recompiling.

# Example
```julia
qf = quantum(x -> x * x + Int8(3) * x + Int8(1))

@context EagerContext() begin
    x = QInt{2}(2)
    y = qf(x)           # first call compiles, subsequent calls reuse
    @assert Int(y) == 3  # (4+6+1) mod 4 = 3
end
```
"""
struct QuantumOracle{F}
    f::F
    cache::Dict{Int, ReversibleCircuit}
end

"""
    quantum(f) -> QuantumOracle

Wrap a plain Julia function as a quantum oracle with circuit caching.
The returned object is callable on `QInt{W}` registers.

Parallel to Enzyme's `gradient(f, x)` pattern: `quantum(f)` transforms
a classical function into a quantum-callable one.
"""
quantum(f) = QuantumOracle(f, Dict{Int, ReversibleCircuit}())

function (qo::QuantumOracle)(x::QInt{W}; kw...) where W
    check_live!(x)
    ctx = x.ctx

    # Cache lookup / compile
    circuit = get!(qo.cache, W) do
        reversible_compile(qo.f, Int8; bit_width=W, kw...)
    end

    input_wires = WireID[x.wires[i] for i in 1:W]
    output_wires_tuple = ntuple(Val(W)) do _
        allocate!(ctx)
    end
    output_vec = WireID[output_wires_tuple[i] for i in 1:W]

    wm = build_wire_map(circuit, input_wires, output_vec)
    apply_reversible!(ctx, circuit, wm)

    return QInt{W}(output_wires_tuple, ctx, false)
end
