# Bennett.jl Integration — Implementation Plan

**Date**: 2026-04-11
**Method**: Red-Green TDD. Every step: write failing test, write minimum code, verify green.
**Prerequisite**: Vision plan at `docs/bennett-integration-v01-vision.md`
**Bennett.jl API**: Stable at v0.4.0. Located at `../Bennett.jl/`. Do NOT modify Bennett.jl.

---

## Step 0: Add Bennett.jl dependency

**Files**: `Project.toml`

```bash
cd /home/tobiasosborne/Projects/Sturm.jl
julia --project -e 'using Pkg; Pkg.develop(path="../Bennett.jl")'
julia --project -e 'using Bennett; println(gate_count(reversible_compile(x -> x + Int8(1), Int8)))'
```

**Verify**: prints `(total = 86, NOT = 2, CNOT = 56, Toffoli = 28)`.

**Commit**: `feat: add Bennett.jl as dev dependency`

---

## Step 1: `apply_ccx!` on EagerContext

**Goal**: Direct Toffoli gate bypassing control stack for nc=0. Correct multi-controlled path for nc>=1.

### Step 1a: RED — basic Toffoli truth table

**File**: `test/test_bennett_integration.jl` (NEW)

```julia
using Test
using Sturm

@testset "Bennett Integration" begin

@testset "apply_ccx!" begin
    @testset "EagerContext" begin
        @testset "Toffoli flips target when both controls are |1>" begin
            @context EagerContext() begin
                ctx = current_context()
                c1 = QBool(1.0)   # |1>
                c2 = QBool(1.0)   # |1>
                t  = QBool(0.0)   # |0>
                Sturm.apply_ccx!(ctx, c1.wire, c2.wire, t.wire)
                @test Bool(t) == true
            end
        end

        @testset "Toffoli does not flip when one control is |0>" begin
            @context EagerContext() begin
                ctx = current_context()
                c1 = QBool(1.0)
                c2 = QBool(0.0)   # |0>
                t  = QBool(0.0)
                Sturm.apply_ccx!(ctx, c1.wire, c2.wire, t.wire)
                @test Bool(t) == false
            end
        end

        @testset "Toffoli does not flip when both controls are |0>" begin
            @context EagerContext() begin
                ctx = current_context()
                c1 = QBool(0.0)
                c2 = QBool(0.0)
                t  = QBool(0.0)
                Sturm.apply_ccx!(ctx, c1.wire, c2.wire, t.wire)
                @test Bool(t) == false
            end
        end

        @testset "Toffoli toggles: apply twice = identity" begin
            @context EagerContext() begin
                ctx = current_context()
                c1 = QBool(1.0)
                c2 = QBool(1.0)
                t  = QBool(0.0)
                Sturm.apply_ccx!(ctx, c1.wire, c2.wire, t.wire)
                Sturm.apply_ccx!(ctx, c1.wire, c2.wire, t.wire)
                @test Bool(t) == false   # back to |0>
            end
        end
    end
end

end # top-level testset
```

**Run**: `julia --project test/test_bennett_integration.jl` — expect `MethodError: no method matching apply_ccx!`

### Step 1b: GREEN — implement `apply_ccx!` on abstract + eager

**File**: `src/context/abstract.jl` — add after `apply_cx!` (after line 34):

```julia
"""Apply Toffoli (CCX): target ⊻= c1 ∧ c2, respecting the current control stack."""
function apply_ccx!(ctx::AbstractContext, c1::WireID, c2::WireID, target::WireID)
    error("apply_ccx! not implemented for $(typeof(ctx))")
end
```

**File**: `src/context/eager.jl` — add after `apply_cx!` (after the `apply_cx!` function, before the multi-controlled section):

```julia
function apply_ccx!(ctx::EagerContext, c1::WireID, c2::WireID, target::WireID)
    q1 = _resolve(ctx, c1)
    q2 = _resolve(ctx, c2)
    qt = _resolve(ctx, target)
    nc = length(ctx.control_stack)
    if nc == 0
        orkan_ccx!(ctx.orkan.raw, q1, q2, qt)
    else
        # CCX inside when(): treat as CX(c2, target) controlled on [stack..., c1]
        # Push c1 as extra control, delegate to existing multi-controlled CX
        push!(ctx.control_stack, c1)
        try
            if length(ctx.control_stack) == 1
                # Only c1 on stack: just CCX
                orkan_ccx!(ctx.orkan.raw, q1, q2, qt)
            else
                _multi_controlled_cx!(ctx, c2, target)
            end
        finally
            pop!(ctx.control_stack)
        end
    end
end
```

**Run**: `julia --project test/test_bennett_integration.jl` — expect all 4 tests GREEN.

### Step 1c: RED — Toffoli inside `when()` (controlled-Toffoli)

Add to `test/test_bennett_integration.jl`, inside the `"apply_ccx!"` testset:

```julia
        @testset "Toffoli inside when() — controlled-Toffoli" begin
            @context EagerContext() begin
                ctx = current_context()
                ctrl = QBool(1.0)   # control ON
                c1 = QBool(1.0)
                c2 = QBool(1.0)
                t  = QBool(0.0)
                when(ctrl) do
                    Sturm.apply_ccx!(ctx, c1.wire, c2.wire, t.wire)
                end
                @test Bool(t) == true   # all controls on → flip
            end
        end

        @testset "Toffoli inside when() — control OFF" begin
            @context EagerContext() begin
                ctx = current_context()
                ctrl = QBool(0.0)   # control OFF
                c1 = QBool(1.0)
                c2 = QBool(1.0)
                t  = QBool(0.0)
                when(ctrl) do
                    Sturm.apply_ccx!(ctx, c1.wire, c2.wire, t.wire)
                end
                @test Bool(t) == false  # outer control off → no flip
            end
        end
```

**Run**: should be GREEN immediately (the nc>=1 path is implemented).

### Step 1d: GREEN on TracingContext

Add to test:

```julia
    @testset "TracingContext" begin
        @testset "apply_ccx! records CXNode with 1 control" begin
            ctx = TracingContext()
            w1 = Sturm.allocate!(ctx)
            w2 = Sturm.allocate!(ctx)
            w3 = Sturm.allocate!(ctx)
            Sturm.apply_ccx!(ctx, w1, w2, w3)
            node = ctx.dag[end]
            @test node isa CXNode
            @test node.control == w2
            @test node.target == w3
            @test node.ncontrols == 1
            @test node.ctrl1 == w1
        end
    end
```

**File**: `src/context/tracing.jl` — add after `apply_cx!`:

```julia
function apply_ccx!(ctx::TracingContext, c1::WireID, c2::WireID, target::WireID)
    _check_wire(ctx, c1)
    _check_wire(ctx, c2)
    _check_wire(ctx, target)
    # CCX(c1, c2, target) = CX(c2, target) controlled on c1
    # Plus any existing stack controls
    nc_stack, sc1, sc2 = _inline_from_stack(ctx.control_stack)
    if nc_stack == 0
        push!(ctx.dag, CXNode(c2, target, c1, _ZERO_WIRE, UInt8(1)))
    elseif nc_stack == 1
        push!(ctx.dag, CXNode(c2, target, sc1, c1, UInt8(2)))
    else
        error("apply_ccx! inside >1 nested when(): would need 3+ controls, exceeds DAG limit")
    end
end
```

### Step 1e: GREEN on DensityMatrixContext

Add to test:

```julia
    @testset "DensityMatrixContext" begin
        @testset "apply_ccx! produces correct density matrix" begin
            @context DensityMatrixContext() begin
                ctx = current_context()
                c1 = QBool(1.0)
                c2 = QBool(1.0)
                t  = QBool(0.0)
                Sturm.apply_ccx!(ctx, c1.wire, c2.wire, t.wire)
                @test Bool(t) == true
            end
        end
    end
```

**File**: `src/context/density.jl` — add after `apply_cx!`:

```julia
function apply_ccx!(ctx::DensityMatrixContext, c1::WireID, c2::WireID, target::WireID)
    q1 = _resolve(ctx, c1)
    q2 = _resolve(ctx, c2)
    qt = _resolve(ctx, target)
    if isempty(ctx.control_stack)
        orkan_ccx!(ctx.orkan.raw, q1, q2, qt)
    elseif length(ctx.control_stack) == 1
        error("Multi-controlled Toffoli (>0 additional controls) not yet implemented for DensityMatrixContext")
    else
        error("Multi-controlled Toffoli (>1 additional controls) not yet implemented for DensityMatrixContext")
    end
end
```

**Commit**: `feat: apply_ccx! — native Toffoli on all contexts`

---

## Step 2: Batch qubit allocation

### Step 2a: RED — allocate_batch! returns n qubits

Add to `test/test_bennett_integration.jl`:

```julia
@testset "Batch allocation" begin
    @testset "allocate_batch! returns n fresh qubits" begin
        @context EagerContext() begin
            ctx = current_context()
            wires = Sturm.allocate_batch!(ctx, 5)
            @test length(wires) == 5
            @test length(unique(wires)) == 5  # all distinct
        end
    end

    @testset "deallocate_batch! releases all qubits" begin
        @context EagerContext() begin
            ctx = current_context()
            wires = Sturm.allocate_batch!(ctx, 3)
            Sturm.deallocate_batch!(ctx, wires)
            # After deallocation, free_slots should have 3 entries
            @test length(ctx.free_slots) >= 3
        end
    end

    @testset "TracingContext batch allocation" begin
        ctx = TracingContext()
        wires = Sturm.allocate_batch!(ctx, 4)
        @test length(wires) == 4
        @test length(unique(wires)) == 4
    end
end
```

### Step 2b: GREEN — implement on abstract + all contexts

**File**: `src/context/abstract.jl` — add after `deallocate!`:

```julia
"""Allocate n fresh qubit wires. Returns Vector{WireID}."""
function allocate_batch!(ctx::AbstractContext, n::Int)::Vector{WireID}
    return WireID[allocate!(ctx) for _ in 1:n]
end

"""Deallocate a batch of qubit wires."""
function deallocate_batch!(ctx::AbstractContext, wires::Vector{WireID})
    for w in wires
        deallocate!(ctx, w)
    end
end
```

Default implementations on `AbstractContext` using the existing single-wire methods. No per-context override needed yet (EagerContext can add a pre-grow optimisation later).

**Commit**: `feat: allocate_batch!/deallocate_batch! for ancilla management`

---

## Step 3: `apply_reversible!` — the bridge function

### Step 3a: RED — apply a trivial Bennett circuit (single NOT gate)

```julia
@testset "apply_reversible!" begin
    @testset "single NOTGate on EagerContext" begin
        using Bennett: ReversibleCircuit, NOTGate, WireIndex
        @context EagerContext() begin
            ctx = current_context()
            q = QBool(0.0)   # |0>

            # Trivial circuit: one NOT gate on wire 1
            # Input: wire 1, Output: wire 1, no ancillae
            circuit = ReversibleCircuit(
                1,                                    # n_wires
                [NOTGate(1)],                         # gates
                WireIndex[1],                         # input_wires
                WireIndex[1],                         # output_wires
                WireIndex[],                          # ancilla_wires
                [1],                                  # input_widths (1-bit)
                [1]                                   # output_elem_widths
            )

            input_map = Dict{WireIndex, WireID}(1 => q.wire)
            Sturm.apply_reversible!(ctx, circuit, input_map)

            @test Bool(q) == true  # NOT flipped |0> to |1>
        end
    end
end
```

### Step 3b: GREEN — implement `apply_reversible!`

**File**: `src/bennett/bridge.jl` (NEW)

```julia
# Bennett.jl integration: execute reversible circuits on Sturm contexts.
#
# Gate mapping:
#   NOTGate(t)         → apply_ry!(ctx, t, π)    [X gate = Ry(π)]
#   CNOTGate(c, t)     → apply_cx!(ctx, c, t)
#   ToffoliGate(c1,c2,t) → apply_ccx!(ctx, c1, c2, t)
#
# If called inside when(), all gates are automatically controlled
# via the existing control stack — no need for Bennett's controlled().

using Bennett: ReversibleCircuit, ReversibleGate,
               NOTGate, CNOTGate, ToffoliGate, WireIndex

"""
    apply_reversible!(ctx, circuit, input_map)

Execute a Bennett-compiled reversible circuit on a Sturm context.

`input_map` maps Bennett `WireIndex` → Sturm `WireID` for input AND output wires.
Ancilla qubits are allocated internally, verified to return to |0⟩ by
Bennett's construction guarantee, and deallocated.

If called inside a `when()` block, all gates automatically pick up the
quantum control from the control stack.
"""
function apply_reversible!(ctx::AbstractContext,
                           circuit::ReversibleCircuit,
                           input_map::Dict{WireIndex, WireID})
    # Build wire map: Bennett WireIndex → Sturm WireID
    wire_map = copy(input_map)

    # Allocate ancilla qubits (all start at |0⟩)
    ancilla_sturm = WireID[]
    for aw in circuit.ancilla_wires
        w = allocate!(ctx)
        wire_map[aw] = w
        push!(ancilla_sturm, w)
    end

    try
        # Execute each gate
        for gate in circuit.gates
            _apply_bennett_gate!(ctx, gate, wire_map)
        end
    finally
        # Deallocate ancillae (Bennett guarantees they're |0⟩)
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
    apply_ccx!(ctx, wm[g.control1], wm[g.control2], wm[g.target])
end
```

**File**: `src/Sturm.jl` — add include after `control/when.jl` (after line 25):

```julia
# Bennett.jl reversible circuit integration
include("bennett/bridge.jl")
```

**Run**: should be GREEN.

### Step 3c: RED — multi-gate circuit with ancillae (CNOT + Toffoli)

```julia
    @testset "CNOTGate maps to CX" begin
        using Bennett: CNOTGate
        @context EagerContext() begin
            ctx = current_context()
            a = QBool(0.0)
            b = QBool(1.0)

            circuit = ReversibleCircuit(
                2, [CNOTGate(2, 1)],      # target=1, control=2
                WireIndex[1], WireIndex[1], WireIndex[],
                [1], [1]
            )
            input_map = Dict{WireIndex, WireID}(1 => a.wire, 2 => b.wire)
            Sturm.apply_reversible!(ctx, circuit, input_map)

            @test Bool(a) == true   # a ⊻= b (b=1 → a flipped)
        end
    end
```

### Step 3d: RED — real `reversible_compile` output

```julia
    @testset "reversible_compile Int8 increment" begin
        using Bennett: reversible_compile, simulate, gate_count
        circuit = reversible_compile(x -> x + Int8(3), Int8)
        @test gate_count(circuit).total > 0

        # Verify via Bennett's own simulator
        @test simulate(circuit, Int8(5)) == Int8(8)
        @test simulate(circuit, Int8(-1)) == Int8(2)  # wrapping

        # Now execute on Sturm EagerContext
        @context EagerContext(capacity=30) begin
            ctx = current_context()

            # Allocate 8 input qubits for the value 5 = 0b00000101
            input_wires_sturm = WireID[]
            for i in 1:8
                bit = (5 >> (i - 1)) & 1
                q = QBool(Float64(bit))
                push!(input_wires_sturm, q.wire)
            end

            # Allocate output wires (start at |0⟩)
            output_wires_sturm = WireID[]
            for _ in 1:8
                q = QBool(0.0)
                push!(output_wires_sturm, q.wire)
            end

            # Build wire map
            input_map = Dict{WireIndex, WireID}()
            for (i, bw) in enumerate(circuit.input_wires)
                input_map[bw] = input_wires_sturm[i]
            end
            for (i, bw) in enumerate(circuit.output_wires)
                input_map[bw] = output_wires_sturm[i]
            end

            Sturm.apply_reversible!(ctx, circuit, input_map)

            # Read output: measure each output qubit
            result = 0
            for (i, w) in enumerate(output_wires_sturm)
                # Create a temporary QBool to measure
                # Actually, we need to measure via the context
                bit = Sturm.measure!(ctx, w)
                result |= Int(bit) << (i - 1)
            end
            @test reinterpret(Int8, UInt8(result)) == Int8(8)
        end
    end
```

**Note**: This test needs enough qubits for inputs + outputs + ancillae. Int8 increment: 8 input + 8 output + ~70 ancillae = ~86 qubits. **This EXCEEDS MAX_QUBITS=30**. The test must either:
- Use a smaller function (e.g., 2-bit increment, ~18 wires)
- Or use TracingContext (no simulation, just DAG capture)

**Revised test — use 2-bit function to stay under 30 qubits:**

```julia
    @testset "reversible_compile 2-bit NOT" begin
        using Bennett: reversible_compile, simulate, gate_count

        f_not(x::UInt8) = ~x & UInt8(0x03)   # 2-bit NOT (mask to 2 bits)
        circuit = reversible_compile(f_not, UInt8)

        # Verify Bennett-side
        @test simulate(circuit, UInt8(0)) == UInt8(3)   # ~0b00 = 0b11
        @test simulate(circuit, UInt8(1)) == UInt8(2)   # ~0b01 = 0b10

        # Verify: total wires must fit in EagerContext
        @test circuit.n_wires <= 30

        # Execute on Sturm
        @context EagerContext(capacity=circuit.n_wires + 2) begin
            ctx = current_context()

            # Allocate input wires for value 0b01 = 1
            input_map = Dict{WireIndex, WireID}()
            for (i, bw) in enumerate(circuit.input_wires)
                bit = (1 >> (i - 1)) & 1
                q = QBool(Float64(bit))
                input_map[bw] = q.wire
            end

            # Allocate output wires
            for (i, bw) in enumerate(circuit.output_wires)
                q = QBool(0.0)
                input_map[bw] = q.wire
            end

            Sturm.apply_reversible!(ctx, circuit, input_map)

            # Read output
            result = 0
            for (i, bw) in enumerate(circuit.output_wires)
                bit = Sturm.measure!(ctx, input_map[bw])
                result |= Int(bit) << (i - 1)
            end
            @test result == 2   # ~0b01 & 0b11 = 0b10 = 2
        end
    end
```

**Verified**: identity Int8 = 17 wires, x+1 Int8 = 26 wires. Both fit under MAX_QUBITS=30. Use identity for trivial tests, x+1 for Toffoli-exercising tests.

### Step 3e: RED — apply_reversible! inside `when()`

```julia
    @testset "apply_reversible! inside when() — controlled" begin
        using Bennett: NOTGate
        @context EagerContext() begin
            ctx = current_context()
            ctrl = QBool(1.0)   # ON
            target = QBool(0.0) # |0>

            circuit = ReversibleCircuit(
                1, [NOTGate(1)],
                WireIndex[1], WireIndex[1], WireIndex[], [1], [1]
            )
            input_map = Dict{WireIndex, WireID}(1 => target.wire)

            when(ctrl) do
                Sturm.apply_reversible!(ctx, circuit, input_map)
            end

            @test Bool(target) == true  # ctrl=1 → NOT applied
        end
    end

    @testset "apply_reversible! inside when() — control OFF" begin
        using Bennett: NOTGate
        @context EagerContext() begin
            ctx = current_context()
            ctrl = QBool(0.0)   # OFF
            target = QBool(0.0) # |0>

            circuit = ReversibleCircuit(
                1, [NOTGate(1)],
                WireIndex[1], WireIndex[1], WireIndex[], [1], [1]
            )
            input_map = Dict{WireIndex, WireID}(1 => target.wire)

            when(ctrl) do
                Sturm.apply_reversible!(ctx, circuit, input_map)
            end

            @test Bool(target) == false  # ctrl=0 → NOT NOT applied
        end
    end
```

Should be GREEN immediately — `apply_ry!` inside the `when()` block checks the control stack.

**Commit**: `feat: apply_reversible! — execute Bennett circuits on Sturm contexts`

---

## Step 4: `SubcircuitNode` in the DAG

### Step 4a: RED — SubcircuitNode can be constructed and stored

```julia
@testset "SubcircuitNode" begin
    @testset "construction and storage" begin
        using Bennett: ReversibleCircuit, NOTGate, WireIndex
        circuit = ReversibleCircuit(
            1, [NOTGate(1)],
            WireIndex[1], WireIndex[1], WireIndex[], [1], [1]
        )
        wire_map = Dict{WireIndex, WireID}(1 => WireID(UInt32(42)))
        node = Sturm.SubcircuitNode(:bennett, circuit, wire_map)
        @test node isa Sturm.DAGNode
        @test node.label == :bennett
    end
end
```

### Step 4b: GREEN — add SubcircuitNode to dag.jl

**File**: `src/channel/dag.jl` — add before the `HotNode` const (before line 131):

```julia
"""Opaque subcircuit (e.g., Bennett-compiled reversible circuit).
NOT in HotNode — contains heap-allocated fields (same treatment as CasesNode).
Passes should treat as opaque or decompose explicitly."""
struct SubcircuitNode <: DAGNode
    label::Symbol
    circuit::ReversibleCircuit
    wire_map::Dict{WireIndex, WireID}
end
```

**Note**: This requires `using Bennett: ReversibleCircuit, WireIndex` at the top of dag.jl, OR defining the struct with `Any` for `circuit` and documenting the expected type. The cleaner approach: since `dag.jl` is included BEFORE the Bennett bridge, and we don't want to couple dag.jl to Bennett types, use `Any`:

```julia
struct SubcircuitNode <: DAGNode
    label::Symbol
    circuit::Any                          # ReversibleCircuit (from Bennett.jl)
    wire_map::Dict{Int, WireID}           # Bennett WireIndex (Int) → Sturm WireID
end
```

This avoids coupling dag.jl to Bennett.jl directly. The `bridge.jl` file is where the typed interface lives.

### Step 4c: RED — TracingContext records SubcircuitNode

```julia
    @testset "TracingContext records SubcircuitNode" begin
        using Bennett: ReversibleCircuit, NOTGate, WireIndex
        @context TracingContext() begin
            ctx = current_context()
            q = QBool(0.0)

            circuit = ReversibleCircuit(
                1, [NOTGate(1)],
                WireIndex[1], WireIndex[1], WireIndex[], [1], [1]
            )
            input_map = Dict{WireIndex, WireID}(1 => q.wire)

            Sturm.apply_reversible!(ctx, circuit, input_map)

            # Should record as SubcircuitNode, not individual gates
            # Filter out the PrepNode from QBool allocation
            sub_nodes = filter(n -> n isa Sturm.SubcircuitNode, ctx.full_dag)
            @test length(sub_nodes) == 1
            @test sub_nodes[1].label == :bennett
        end
    end
```

### Step 4d: GREEN — add SubcircuitNode recording path in bridge.jl

Add a TracingContext-specific method in `bridge.jl`:

```julia
function apply_reversible!(ctx::TracingContext,
                           circuit::ReversibleCircuit,
                           input_map::Dict{WireIndex, WireID})
    # Record as opaque SubcircuitNode instead of expanding gates
    # Convert to Dict{Int, WireID} for the DAG-level representation
    int_map = Dict{Int, WireID}(Int(k) => v for (k, v) in input_map)

    # Ancilla wires are noted but not allocated in TracingContext
    # (they're internal to the subcircuit)
    for aw in circuit.ancilla_wires
        int_map[Int(aw)] = allocate!(ctx)
    end

    push!(ctx.full_dag, SubcircuitNode(:bennett, circuit, int_map))
end
```

**Note**: TracingContext uses `ctx.dag` (Vector{HotNode}) for the hot path. SubcircuitNode is NOT isbits, so it cannot go in `ctx.dag`. Need to check how CasesNode is handled — it goes into a separate storage or the full DAG. Let me check...

Actually, looking at the code, TracingContext has a single `dag::Vector{HotNode}` field. CasesNode is NOT in it — CasesNode only appears in `Channel` objects constructed from deferred_measurement pass output, not from TracingContext directly.

**Design decision**: Two options:
1. Add a `subcircuits::Vector{SubcircuitNode}` field to TracingContext
2. Expand Bennett gates individually into the HotNode DAG

Option 2 is simpler for v0.1 and works with all existing passes (gate_cancel, openqasm). The DAG will be large for big circuits, but TracingContext has no simulation cost — it's just memory. Optimize later with Option 1 if needed.

**Revised approach for Step 4**: Skip SubcircuitNode for v0.1. TracingContext expands Bennett gates individually. This uses the SAME `apply_reversible!` as EagerContext (the generic AbstractContext method). The DAG gets individual RyNode/CXNode entries.

**Test revision**:

```julia
    @testset "TracingContext expands Bennett gates into DAG" begin
        using Bennett: ReversibleCircuit, NOTGate, CNOTGate, WireIndex
        ctx = TracingContext()
        w1 = Sturm.allocate!(ctx)
        w2 = Sturm.allocate!(ctx)

        circuit = ReversibleCircuit(
            2, [CNOTGate(1, 2), NOTGate(2)],
            WireIndex[1, 2], WireIndex[1, 2], WireIndex[], [1, 1], [1, 1]
        )
        input_map = Dict{WireIndex, WireID}(1 => w1, 2 => w2)

        Sturm.apply_reversible!(ctx, circuit, input_map)

        # Should have CXNode + RyNode(π) in the DAG
        types = [typeof(n) for n in ctx.dag]
        @test CXNode in types
        @test RyNode in types   # NOT = Ry(π)
    end
```

This should be GREEN immediately with the generic `apply_reversible!`.

**Commit**: `feat: SubcircuitNode type in DAG (for future opaque recording)`

---

## Step 5: Wire mapping helper

### Step 5a: RED — `build_wire_map` convenience

```julia
@testset "Wire mapping" begin
    @testset "build_wire_map for single-arg circuit" begin
        using Bennett: reversible_compile, WireIndex
        circuit = reversible_compile(x -> x + Int8(1), Int8)

        @context EagerContext(capacity=30) begin
            ctx = current_context()
            # Create 8 input qubits for value 5
            input_qubits = [QBool(Float64((5 >> (i-1)) & 1)) for i in 1:8]
            # Create 8 output qubits (|0>)
            output_qubits = [QBool(0.0) for _ in 1:8]

            wm = Sturm.build_wire_map(circuit,
                                       [q.wire for q in input_qubits],
                                       [q.wire for q in output_qubits])
            @test length(wm) == length(circuit.input_wires) + length(circuit.output_wires)
        end
    end
end
```

### Step 5b: GREEN — implement in bridge.jl

```julia
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
```

**Commit**: `feat: build_wire_map helper for Bennett circuit wire mapping`

---

## Step 6: End-to-end integration test

### Step 6a: RED/GREEN — end-to-end identity (17 wires, fits easily)

```julia
    @testset "end-to-end: identity Int8" begin
        using Bennett: reversible_compile, simulate, WireIndex

        circuit = reversible_compile(identity, Int8)
        @test circuit.n_wires == 17   # verified: fits in MAX_QUBITS=30

        test_val = Int8(42)
        @test simulate(circuit, test_val) == test_val  # sanity: Bennett side

        @context EagerContext(capacity=circuit.n_wires + 2) begin
            ctx = current_context()

            # Allocate input qubits encoding test_val
            input_wires = WireID[]
            for i in 1:8
                bit = (reinterpret(UInt8, test_val) >> (i - 1)) & 1
                push!(input_wires, QBool(Float64(bit)).wire)
            end

            # Allocate output qubits (all |0⟩)
            output_wires = WireID[]
            for i in 1:8
                push!(output_wires, QBool(0.0).wire)
            end

            wm = Sturm.build_wire_map(circuit, input_wires, output_wires)
            Sturm.apply_reversible!(ctx, circuit, wm)

            # Read output by measuring each qubit
            result_bits = UInt8(0)
            for (i, w) in enumerate(output_wires)
                bit = Sturm.measure!(ctx, w)
                result_bits |= UInt8(bit) << (i - 1)
            end
            @test reinterpret(Int8, result_bits) == test_val
        end
    end
```

### Step 6b: RED/GREEN — end-to-end increment (26 wires, exercises Toffoli)

```julia
    @testset "end-to-end: x+1 Int8" begin
        using Bennett: reversible_compile, simulate, WireIndex

        f(x::Int8) = x + Int8(1)
        circuit = reversible_compile(f, Int8)
        @test circuit.n_wires == 26   # verified: fits in MAX_QUBITS=30

        # Test multiple values
        for test_val in Int8[0, 1, 42, 127, -1, -128]
            expected = test_val + Int8(1)  # wrapping
            @test simulate(circuit, test_val) == expected

            @context EagerContext(capacity=circuit.n_wires + 2) begin
                ctx = current_context()

                input_wires = WireID[]
                for i in 1:8
                    bit = (reinterpret(UInt8, test_val) >> (i - 1)) & 1
                    push!(input_wires, QBool(Float64(bit)).wire)
                end

                output_wires = WireID[]
                for i in 1:8
                    push!(output_wires, QBool(0.0).wire)
                end

                wm = Sturm.build_wire_map(circuit, input_wires, output_wires)
                Sturm.apply_reversible!(ctx, circuit, wm)

                result_bits = UInt8(0)
                for (i, w) in enumerate(output_wires)
                    bit = Sturm.measure!(ctx, w)
                    result_bits |= UInt8(bit) << (i - 1)
                end
                @test reinterpret(Int8, result_bits) == expected
            end
        end
    end
```

**Commit**: `test: end-to-end Bennett → Sturm integration test`

---

## Step 7: Register test file in runtests.jl

**File**: `test/runtests.jl` — add at the end, before the closing `end`:

```julia
    include("test_bennett_integration.jl")
```

**Run full suite**: `julia --project -e 'using Pkg; Pkg.test()'`

**Commit**: `test: add Bennett integration tests to full suite`

---

## Step 8: Exports and user-facing API

### Step 8a: RED — `apply_oracle!` high-level function

```julia
@testset "apply_oracle!" begin
    @testset "compile and execute plain Julia function" begin
        using Bennett: WireIndex
        # This test may skip if circuit doesn't fit in 30 qubits
        @context EagerContext(capacity=30) begin
            ctx = current_context()
            # Prepare input register as individual QBools (manual for now)
            input_val = Int8(7)
            input_wires = WireID[]
            for i in 1:8
                bit = (reinterpret(UInt8, input_val) >> (i - 1)) & 1
                push!(input_wires, QBool(Float64(bit)).wire)
            end

            output_wires = WireID[]
            for _ in 1:8
                push!(output_wires, QBool(0.0).wire)
            end

            result = Sturm.apply_oracle!(ctx, identity, Int8,
                                          input_wires, output_wires)
            # Measure output
            result_bits = UInt8(0)
            for (i, w) in enumerate(output_wires)
                bit = Sturm.measure!(ctx, w)
                result_bits |= UInt8(bit) << (i - 1)
            end
            @test reinterpret(Int8, result_bits) == input_val
        end
    end
end
```

### Step 8b: GREEN — implement `apply_oracle!`

Add to `src/bennett/bridge.jl`:

```julia
"""
    apply_oracle!(ctx, f, arg_type, input_wires, output_wires; kw...)

Compile a plain Julia function `f` to a reversible circuit and execute it
on the Sturm context. Input qubits encode the function argument; output
qubits receive f(input).

If called inside `when()`, the oracle is automatically controlled.

# Arguments
- `f`: pure Julia function (e.g., `x -> x + Int8(3)`)
- `arg_type`: argument type (e.g., `Int8`)
- `input_wires`: Vector{WireID} — qubits encoding the input value
- `output_wires`: Vector{WireID} — qubits to receive the output (must be |0⟩)
- `kw...`: passed to `reversible_compile` (e.g., `max_loop_iterations=20`)
"""
function apply_oracle!(ctx::AbstractContext, f, arg_type::Type,
                        input_wires::Vector{WireID},
                        output_wires::Vector{WireID}; kw...)
    circuit = reversible_compile(f, arg_type; kw...)
    wm = build_wire_map(circuit, input_wires, output_wires)
    apply_reversible!(ctx, circuit, wm)
    return circuit  # return for resource inspection
end
```

### Step 8c: Exports

**File**: `src/Sturm.jl` — add to exports:

```julia
# Bennett integration
export apply_reversible!, apply_oracle!, build_wire_map
```

**Commit**: `feat: apply_oracle! — compile and execute plain Julia as quantum oracle`

---

## Step 9: Resource estimation

### Step 9a: RED

```julia
@testset "Resource estimation" begin
    @testset "estimate_oracle_resources" begin
        resources = Sturm.estimate_oracle_resources(x -> x + Int8(1), Int8)
        @test resources.gates > 0
        @test resources.toffoli >= 0
        @test resources.t_count == resources.toffoli * 7
        @test resources.qubits > 0
    end
end
```

### Step 9b: GREEN

Add to `src/bennett/bridge.jl`:

```julia
"""
    estimate_oracle_resources(f, arg_type; kw...) -> NamedTuple

Resource estimates for compiling `f` as a reversible quantum oracle.
Returns gate count, Toffoli count, T-count (7 × Toffoli), qubit count, T-depth.
"""
function estimate_oracle_resources(f, arg_type::Type; kw...)
    circuit = reversible_compile(f, arg_type; kw...)
    gc = gate_count(circuit)
    return (gates=gc.total, toffoli=gc.Toffoli, t_count=gc.Toffoli * 7,
            qubits=circuit.n_wires, t_depth=t_depth(circuit))
end
```

**Commit**: `feat: estimate_oracle_resources for automatic resource estimation`

---

## Step 10: OpenQASM export for expanded Bennett circuits

### Step 10a: RED

```julia
@testset "OpenQASM export of Bennett circuit" begin
    using Bennett: ReversibleCircuit, NOTGate, CNOTGate, WireIndex
    ch = trace(2) do a, b
        circuit = ReversibleCircuit(
            2, [CNOTGate(1, 2)],
            WireIndex[1, 2], WireIndex[1, 2], WireIndex[], [1, 1], [1, 1]
        )
        input_map = Dict{WireIndex, WireID}(1 => a.wire, 2 => b.wire)
        Sturm.apply_reversible!(current_context(), circuit, input_map)
        (a, b)
    end
    qasm = to_openqasm(ch)
    @test contains(qasm, "cx")
end
```

Should be GREEN immediately — expanded Bennett gates are standard RyNode/CXNode entries in the DAG, which `to_openqasm` already handles.

**Commit**: `test: OpenQASM export of Bennett-integrated circuits`

---

## Summary: Commit Sequence

| # | Commit | Files changed | Tests added |
|---|--------|---------------|-------------|
| 0 | `feat: add Bennett.jl as dev dependency` | Project.toml, Manifest.toml | — |
| 1 | `feat: apply_ccx! — native Toffoli on all contexts` | abstract.jl, eager.jl, tracing.jl, density.jl | ~8 |
| 2 | `feat: allocate_batch!/deallocate_batch!` | abstract.jl | ~3 |
| 3 | `feat: apply_reversible! — execute Bennett circuits` | NEW bennett/bridge.jl, Sturm.jl | ~6 |
| 4 | `feat: SubcircuitNode type in DAG` | dag.jl | ~2 |
| 5 | `feat: build_wire_map helper` | bridge.jl | ~1 |
| 6 | `test: end-to-end Bennett → Sturm` | test_bennett_integration.jl | ~2 |
| 7 | `test: add to full test suite` | runtests.jl | — |
| 8 | `feat: apply_oracle! high-level API` | bridge.jl, Sturm.jl exports | ~1 |
| 9 | `feat: estimate_oracle_resources` | bridge.jl | ~1 |
| 10 | `test: OpenQASM export of Bennett circuits` | test_bennett_integration.jl | ~1 |

**Total**: ~10 commits, ~25 new tests, 4 files modified, 1 new file, 1 new test file.

---

## Critical Questions to Resolve During Implementation

1. **What is the smallest Bennett circuit that fits in 30 qubits?** RESOLVED:
   - `identity Int8`: 17 wires, 10 gates, 1 ancilla — **use for basic tests**
   - `x+1 Int8`: 26 wires, 100 gates, 10 ancillae — **use for end-to-end (has Toffoli)**
   - `x+3 Int8`: 26 wires, 102 gates, 10 ancillae — also fits
   - `x>>1 Int8`: 25 wires, 26 gates, 9 ancillae — fits
   - `x*2 Int8`: 25 wires, 24 gates, 9 ancillae — fits
   - `NOT Int8`: 33 wires — **DOES NOT FIT** (>30)
   - `x&0x0f Int8`: 33 wires — **DOES NOT FIT**

2. **Does `apply_ry!(ctx, wire, π)` exactly equal NOT?** Ry(π)|0⟩ = |1⟩ and Ry(π)|1⟩ = -|0⟩. The -1 global phase is unobservable in measurement but matters for controlled gates. Verify that this matches Bennett's NOTGate semantics. If the phase matters (inside `when()`), may need `X!` instead (which is also `q.theta += π`, so identical).

3. **Wire index alignment**: Bennett uses 1-based WireIndex (Int). Sturm uses WireID (UInt32, also conceptually 1-based but generated by `fresh_wire!()`). The mapping is explicit via `Dict{WireIndex, WireID}` — no implicit alignment assumed.

4. **Ancilla deallocation order**: Bennett guarantees ancillae return to |0⟩ after the circuit completes. `deallocate!` on EagerContext calls `measure!`, which collapses to |0⟩ or |1⟩. If the ancilla is indeed |0⟩, the measurement returns false and the qubit is recycled. If the ancilla is NOT |0⟩ (Bennett bug), the measurement returns true and the qubit is recycled in |0⟩ state (Orkan resets after measure) — but the computation is silently wrong. Consider adding an assertion: `@assert !measure!(ctx, w) "Bennett ancilla wire not zero — reversible circuit bug"`.

5. **`when()` + Bennett + ancillae**: When `apply_reversible!` runs inside `when()`, the ancilla allocation happens unconditionally (qubits are allocated regardless of control state). This is correct: controlled gates on |0⟩ ancillae with control=|0⟩ do nothing. The ancillae stay |0⟩ in the ctrl=|0⟩ branch.
