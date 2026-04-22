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
using Bennett: emit_qrom!, WireAllocator, wire_count,
               LoweringResult, bennett
import Bennett: allocate! as _bennett_wa_allocate!

# Pick the narrowest Julia integer type that fits a W-bit quantum register,
# so that Bennett extracts LLVM IR at the right numeric type. Hardcoding Int8
# regardless of W forced every function to be compiled against 8-bit
# semantics: for W > 8 the IR still gets uniformly narrowed to W bits by
# Bennett, but constants, comparisons, and type-dispatch paths inside the
# user function all see Int8, which is a type lie (q93).
#
# signed=true (default) matches Julia's native `Int` convention; set
# signed=false when f's behaviour depends on unsigned reinterpretation.
function _bennett_arg_type(W::Int; signed::Bool=true)
    W >= 1 || error("_bennett_arg_type: W must be >= 1, got $W")
    if W <= 8
        return signed ? Int8  : UInt8
    elseif W <= 16
        return signed ? Int16 : UInt16
    elseif W <= 32
        return signed ? Int32 : UInt32
    elseif W <= 64
        return signed ? Int64 : UInt64
    else
        error("_bennett_arg_type: W=$W exceeds Int64/UInt64 (max 64 bits)")
    end
end

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

Any keyword arguments are forwarded to `Bennett.reversible_compile`, so
strategy hints like `add=:qcla`, `mul=:qcla_tree`, `optimize=false`, or
`max_loop_iterations=N` pass straight through.

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

Keyword arguments are forwarded to `Bennett.reversible_compile`; use them
to compare strategies without executing the circuit:

```julia
r_ripple = estimate_oracle_resources(x -> x + x, Int8; bit_width=8, add=:ripple)
r_qcla   = estimate_oracle_resources(x -> x + x, Int8; bit_width=8, add=:qcla)
@show r_ripple.toffoli, r_qcla.toffoli
```
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
    oracle(f, x::QInt{W}; signed=true, kw...) -> QInt{W}

Compile a plain Julia function `f` to a reversible quantum circuit via Bennett.jl
and execute it on the quantum register `x`. Returns a new `QInt{W}` containing
`f(x)`. The input register `x` is preserved (Bennett's construction keeps inputs
intact).

The classical argument type handed to Bennett is selected to fit `W`: Int8 for
W≤8, Int16 for W≤16, Int32 for W≤32, Int64 for W≤64. Pass `signed=false` to use
the corresponding `UInt*` variant instead. Widths beyond 64 error out.

Any other keyword arguments are forwarded to `Bennett.reversible_compile`.
Strategy hints let the caller choose between Pareto-frontier arithmetic circuit
families — for example `add ∈ {:ripple, :cuccaro, :qcla, :auto}` or
`mul ∈ {:shift_add, :karatsuba, :qcla_tree, :auto}`:

```julia
y = oracle(x -> x * x, x; mul=:qcla_tree)   # Sun-Borissov polylog multiplier
```

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
function oracle(f, x::QInt{W}; signed::Bool=true, kw...) where W
    check_live!(x)
    ctx = x.ctx

    arg_type = _bennett_arg_type(W; signed=signed)
    circuit = reversible_compile(f, arg_type; bit_width=W, kw...)

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
Caches Bennett circuits keyed on `(W, sorted_kwargs)`, so calling
`qf(x; mul=:shift_add)` and `qf(x; mul=:qcla_tree)` produce two distinct
cached circuits instead of one silently reused from the first call.
Created via `quantum(f)`.

Callable on `QInt{W}`: `qf(x; kw...)` is equivalent to `oracle(f, x; kw...)`
but reuses a cached circuit on subsequent calls with the same width and
strategy kwargs.

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
    cache::Dict{Any, ReversibleCircuit}
end

"""
    quantum(f) -> QuantumOracle

Wrap a plain Julia function as a quantum oracle with circuit caching.
The returned object is callable on `QInt{W}` registers.

Parallel to Enzyme's `gradient(f, x)` pattern: `quantum(f)` transforms
a classical function into a quantum-callable one.
"""
quantum(f) = QuantumOracle(f, Dict{Any, ReversibleCircuit}())

# Canonicalise (W, signed, kwargs) into a stable cache key. Sorting by kwarg
# name makes the key invariant under call-site ordering; including `signed`
# and every other kwarg prevents silent reuse when the arg-type or strategy
# hints (add=, mul=, optimize=, …) change between calls.
function _oracle_cache_key(W::Int, signed::Bool, kw)
    isempty(kw) && return (W, signed, ())
    kv = sort!(collect(pairs(kw)); by=first)
    return (W, signed, Tuple(kv))
end

# ═══════════════════════════════════════════════════════════════════════════
# oracle_table: classical tabulation + QROM for functions Bennett cannot lower
# ═══════════════════════════════════════════════════════════════════════════
#
# `oracle(f, x)` extracts LLVM IR from `f` and symbolically lowers it. That path
# chokes on complex stdlib calls like `powermod`, `invmod`, or soft-float poly
# — Session 24's attempt at Shor's algorithm hit "Undefined SSA variable: %__v2"
# lowering `powermod`'s IR. The idiomatic fallback is to *evaluate `f`
# classically on all 2^W inputs* and emit the result via Babbush-Gidney QROM
# (Bennett's `emit_qrom!`), at cost 2·(2^W − 1) Toffoli and T-count independent
# of `W_out`. Use when:
#
#   * `f` uses stdlib numerics Bennett cannot yet lower symbolically;
#   * W is small (≤ ~12) so the 2^W classical evaluations are cheap;
#   * you want a single controlled lookup rather than symbolic IR.
#
# Auto-controls inside `when()` via the existing control stack.

"""
    oracle_table(f, x::QInt{W_in}, ::Val{W_out}) -> QInt{W_out}

Evaluate `f` classically on every W_in-bit input, emit a Babbush-Gidney QROM
(Bennett.jl `emit_qrom!`) for the resulting table, and execute it on the
Sturm context. Returns a fresh `QInt{W_out}` holding `f(x) & (2^W_out − 1)`
for the superposition of inputs in `x`; the input register is preserved.

This complements [`oracle`](@ref): `oracle` extracts and symbolically lowers
the LLVM IR of `f`; `oracle_table` skips the IR entirely and bakes the
function's value table into a QROM. Use when `f` calls stdlib numerics that
Bennett cannot lower (`powermod`, `invmod`, soft-float transcendentals, etc.)
or when a single-shot table lookup is strictly cheaper than symbolic
decomposition.

`f` receives a plain Julia `Int`; the returned integer is masked to W_out
bits.

Cost: `2 · (2^W_in − 1)` Toffoli, T-count `4 · (2^W_in − 1)`, independent of
W_out. Plus W_in ancillae (unary-iteration tree, self-uncomputing).

If called inside `when()`, the QROM is automatically controlled via the
existing control stack.

# Example
```julia
@context EagerContext() begin
    k = QInt{4}(0); superpose!(k)
    y = oracle_table(k -> powermod(7, k, 15), k, Val(4))
    # `y` now holds 7^k mod 15 entangled with k.
end
```
"""
# Module-private cache: data-hash → compiled QROM circuit. Bennett's
# `emit_qrom!` + `bennett(lr)` is the expensive part of `oracle_table` —
# two shots that share the same table (same `(a, N, W_in, W_out)` in Shor's
# case) compile the circuit once and reuse it on every subsequent call.
const _ORACLE_TABLE_CACHE = Dict{Tuple{UInt64, Int, Int}, ReversibleCircuit}()

function oracle_table(f, x::QInt{W_in}, ::Val{W_out}) where {W_in, W_out}
    check_live!(x)
    W_in  >= 1 || error("oracle_table: W_in must be ≥ 1, got $W_in")
    1 <= W_out <= 64 || error("oracle_table: W_out must be 1..64, got $W_out")
    ctx = x.ctx

    # Classical evaluation: build the W_out-bit lookup table.
    mask = W_out == 64 ? typemax(UInt64) : (UInt64(1) << W_out) - UInt64(1)
    L = 1 << W_in
    data = Vector{UInt64}(undef, L)
    @inbounds for k in 0:(L - 1)
        data[k + 1] = UInt64(f(k)) & mask
    end

    # Cache by content-hash. Two tables with the same values (regardless of
    # which `f` produced them) share a circuit — this is correct because the
    # circuit depends only on the table contents, not on the function body.
    key = (hash(data), W_in, W_out)
    circuit = get!(_ORACLE_TABLE_CACHE, key) do
        wa = WireAllocator()
        gates = ReversibleGate[]
        idx_wires_b = _bennett_wa_allocate!(wa, W_in)
        data_out_b  = emit_qrom!(gates, wa, data, idx_wires_b, W_out)
        lr = LoweringResult(gates, wire_count(wa), idx_wires_b, data_out_b,
                            [W_in], [W_out], Set{Int}())
        bennett(lr)
    end

    # Execute on the Sturm context. `apply_reversible!` handles ancillae and
    # picks up the active control stack automatically inside `when()`.
    input_wires = WireID[x.wires[i] for i in 1:W_in]
    output_wires_tuple = ntuple(Val(W_out)) do _
        allocate!(ctx)
    end
    output_vec = WireID[output_wires_tuple[i] for i in 1:W_out]
    wm = build_wire_map(circuit, input_wires, output_vec)
    apply_reversible!(ctx, circuit, wm)

    return QInt{W_out}(output_wires_tuple, ctx, false)
end

# ═══════════════════════════════════════════════════════════════════════════
# QuantumOracle callable (with kwargs for strategy overrides)
# ═══════════════════════════════════════════════════════════════════════════

function (qo::QuantumOracle)(x::QInt{W}; signed::Bool=true, kw...) where W
    check_live!(x)
    ctx = x.ctx

    # Cache lookup / compile — key on (W, signed, sorted kwargs) so that
    # callers switching strategy (e.g. mul=:qcla_tree) or signedness get a
    # fresh compilation.
    key = _oracle_cache_key(W, signed, kw)
    arg_type = _bennett_arg_type(W; signed=signed)
    circuit = get!(qo.cache, key) do
        reversible_compile(qo.f, arg_type; bit_width=W, kw...)
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

# ═══════════════════════════════════════════════════════════════════════════
# qrom_lookup_xor!: XOR-into-existing-target QROM (Sturm.jl-6oc Phase A)
# ═══════════════════════════════════════════════════════════════════════════

"""
    qrom_lookup_xor!(target::QInt{W}, addr::QInt{Ccmul},
                     table::QROMTable{Ccmul, W, N}) -> target

XOR a classical table entry into an existing quantum target register,
indexed by a quantum address: `|a⟩|t⟩ → |a⟩|t ⊕ T[a]⟩`.

Atomic lookup primitive for windowed quantum arithmetic (Gidney 2019
arXiv:1905.07682 §3.1 Fig 2) and the QROM of Babbush et al. 2018
(arXiv:1805.03662 §III.C Fig 10, unary-iteration tree). Unlike
[`oracle_table`](@ref), this variant XORs into an *existing* target register
rather than allocating a fresh one — required by `plus_equal_product!`
and the windowed mulmod path.

Self-inverse: two successive calls with the same `addr` return `target` to
its prior state (naïve O(L) uncomputation). The O(√L) measurement-based
alternative (Babbush 2018 Appendix C, Gidney 2019 Fig 3) is a future
optimisation.

# Cost
  `4·(2^Ccmul − 1)` Toffoli via Babbush-Gidney unary iteration.

# Automatic control
Called inside `when(c) do … end`, the entire QROM inherits `c` via Sturm's
control stack (same mechanism as [`oracle_table`](@ref)).
"""
function qrom_lookup_xor!(target::QInt{W},
                          addr::QInt{Ccmul},
                          table::QROMTable{Ccmul, W, N}) where {W, Ccmul, N}
    check_live!(target); check_live!(addr)
    addr.ctx === target.ctx ||
        error("qrom_lookup_xor!: addr and target must share a context")
    ctx = target.ctx

    data = collect(UInt64, table.data)
    key = (hash(data), Ccmul, W)
    circuit = get!(_QROM_LOOKUP_XOR_CACHE, key) do
        wa = WireAllocator()
        gates = ReversibleGate[]
        idx_wires_b = _bennett_wa_allocate!(wa, Ccmul)
        data_out_b  = emit_qrom!(gates, wa, data, idx_wires_b, W)
        lr = LoweringResult(gates, wire_count(wa), idx_wires_b, data_out_b,
                            [Ccmul], [W], Set{Int}())
        bennett(lr)
    end

    input_wires = WireID[addr.wires[i]   for i in 1:Ccmul]
    output_vec  = WireID[target.wires[i] for i in 1:W]
    wm = build_wire_map(circuit, input_wires, output_vec)
    apply_reversible!(ctx, circuit, wm)

    return target
end

const _QROM_LOOKUP_XOR_CACHE = Dict{Tuple{UInt64, Int, Int}, ReversibleCircuit}()

