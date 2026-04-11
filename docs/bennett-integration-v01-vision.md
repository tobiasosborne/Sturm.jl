# Bennett.jl + Sturm.jl Integration — v0.1 Vision Plan

**Date**: 2026-04-11
**Status**: Research complete, awaiting Bennett.jl pebbling maturity before implementation
**Prerequisite**: Bennett.jl pebbling (Bennett-an5) must be resolved first

---

## 1. Executive Summary

Bennett.jl is a working compiler that takes **any pure Julia function** and compiles it to a reversible circuit (NOT/CNOT/Toffoli) via LLVM IR extraction + Bennett's 1973 compute-copy-uncompute construction. It handles integers (8–64 bit), all arithmetic, branching, bounded loops, tuples, and **full IEEE 754 Float64** via a branchless soft-float library. 46 test files, 10K+ assertions, all ancillae verified zero.

Integrating this into Sturm.jl's `when(q) do f(x) end` is architecturally feasible and would be **transformative**: any classical function becomes a quantum oracle automatically. But it requires breaking changes to Sturm.jl, and the resulting circuits are too large for statevector simulation — they target future hardware and DAG/OpenQASM export.

### The Vision

```julia
# Programmer writes plain Julia:
f(x::Int8) = x^2 + 3x + 1

# Gets a quantum-controlled circuit automatically:
@context EagerContext() begin       # or TracingContext for export
    q = QBool(1/2)                  # control qubit in superposition
    x = QInt{8}(42)                 # quantum register
    when(q) do
        apply_oracle!(f, x)         # Bennett compiles f, executes controlled
    end
end
```

No circuit construction. No primitive decomposition. No hand-coded oracles. Write normal code, get quantum circuits.

---

## 2. What Bennett.jl Can Compile Today

### 2.1 Capabilities

| Category | Coverage | Example gate counts |
|---|---|---|
| Integer arithmetic (i8–i64) | Complete: +, -, *, /, %, &, \|, ^, ~, shifts | i8 add: 86 gates, i8 polynomial: 846 |
| Branching (if/else) | Complete via path-predicate phi resolution | nested if: 630 gates |
| Bounded loops | Unrolling with `max_loop_iterations` | collatz 20-iter: 28,172 gates |
| Float64 | Complete: +, -, *, /, <, ==, floor, ceil, abs | fadd: 93K, fmul: 265K, polynomial: 717K |
| Tuples / NTuples | extractvalue, insertvalue, pointer flattening | swap_pair: 80 gates |
| Controlled circuits | NOT→CNOT, CNOT→Toffoli, Toffoli→3 Toffolis | controlled increment: 144 gates |
| SHA-256 round | Compiles and verifies | 17,712 gates, 5,889 wires |

**Scaling law**: addition gates scale exactly 2x per width doubling (86 → 174 → 350 → 702).

### 2.2 Gate Count Reference

| Function | Width | Total Gates | NOT | CNOT | Toffoli | Wires |
|---|---|---|---|---|---|---|
| x + 1 | i8 | 86 | 2 | 56 | 28 | — |
| x + 1 | i16 | 174 | 2 | 112 | 60 | — |
| x + 1 | i32 | 350 | 2 | 224 | 124 | — |
| x + 1 | i64 | 702 | 2 | 448 | 252 | — |
| x² + 3x + 1 | i8 | 846 | 6 | 488 | 352 | 264 |
| x² + 3x + 1 | i16 | 3,102 | 6 | 1,744 | 1,352 | — |
| x*y + x - y | i8 | 876 | 20 | 504 | 352 | 272 |
| x*7 + 42 | i32 | 11,528 | 12 | 6,368 | 5,148 | — |
| nested if/else | i8 | 630 | 70 | 380 | 180 | — |
| collatz_steps (20 iter) | i8 | 28,172 | 1,306 | 16,898 | 9,968 | 8,878 |
| soft_fneg | i64 | 322 | 2 | 320 | 0 | — |
| soft_fadd | i64 | 93,402 | 5,218 | 63,946 | 24,238 | 27,550 |
| soft_fmul | i64 | 265,010 | 4,960 | 155,828 | 104,222 | — |
| Float64 x²+3x+1 | i64 | 717,680 | 20,380 | 440,380 | 256,920 | — |
| SHA-256 round | 10×UInt32 | 17,712 | — | — | — | 5,889 |
| controlled increment | i8 | 144 | 0 | 4 | 140 | — |
| controlled nested-if | i8 | 990 | 0 | 70 | 920 | — |

### 2.3 Not Yet Supported

- General loops (data-dependent termination) — bounded unrolling only
- Recursion
- Dynamic dispatch
- Heap allocation (`store` instruction)
- `frem` (Julia calls libm)
- Float64 argument count capped at 3 by dispatch shim

### 2.4 Pipeline Architecture

```
Julia function          LLVM IR              Reversible Circuit
─────────────────      ─────────            ──────────────────
f(x::Int8)     ──►  extract_parsed_ir()  ──►  lower()  ──►  bennett()
                     (LLVM.jl C API)          (gates)       (fwd + copy + undo)
                                                                │
                                                                ▼
                                                          ReversibleCircuit
                                                            .n_wires
                                                            .gates (NOT/CNOT/Toffoli)
                                                            .input_wires
                                                            .output_wires
                                                            .ancilla_wires
```

### 2.5 Pebbling / Space Optimisation Status

Five construction strategies exist:

| Strategy | Space | Time | Status |
|---|---|---|---|
| Full Bennett | O(T) ancillae | O(T) gates | Working |
| Knill recursion | O(S log T) | O(T^{1+ε}) | Math verified, schedule WIP |
| EAGER cleanup | O(optimal) | O(T) | Working, minimal benefit on linear code |
| SAT pebbling | O(budget) | O(min gates) | Validated, not wired to circuit output |
| In-place ops (Cuccaro) | -50% per op | O(T) | Implemented, not integrated into pipeline |

**Active blocker**: Bennett-an5 (P1) — `pebbled_group_bennett()` achieves only 0.5% wire reduction because `GateGroup` does not track internal wire ranges. Until resolved, circuits carry 5–10x more ancillae than necessary.

---

## 3. How Sturm.jl `when()` Works Today

### 3.1 Mechanism

`when(ctrl) do ... end` pushes `ctrl.wire` onto `ctx.control_stack`. Every primitive operation called inside checks the stack and applies the appropriate controlled gate:

| Stack depth | Ry(θ) | CX(c,t) |
|---|---|---|
| 0 | `orkan_ry!` | `orkan_cx!` |
| 1 | Nielsen §4.3 decomposition: Ry(θ/2)·CX·Ry(-θ/2)·CX | `orkan_ccx!` |
| ≥2 | Toffoli cascade (Barenco 1995) + single-controlled gate | Toffoli cascade + CCX |

### 3.2 Context-specific Constraints

| Context | Max nesting | Mechanism |
|---|---|---|
| EagerContext | Unlimited | Toffoli cascade with workspace qubits |
| TracingContext | 2 | Inline `ctrl1, ctrl2, ncontrols` in node structs |
| DensityMatrixContext | 1 | Only `nc == 1` path implemented |

### 3.3 The 2-Control Ceiling (TracingContext)

DAG node structs store controls inline as two `WireID` fields + `UInt8` count. This was a deliberate performance decision: all 6 hot node types are `isbits` (24 bytes), stored inline in `Vector{HotNode}` at 25 bytes/element (tag byte). Any change to variable-length controls breaks `isbits` and kills the `HotNode` union inline storage.

### 3.4 Key Integration Points

Files that would need changes for Bennett integration:

1. `src/channel/dag.jl` — `_inline_controls`, node struct definitions, `HotNode` union
2. `src/context/tracing.jl` — `_inline_from_stack`, all `apply_*!` methods
3. `src/context/eager.jl` — gate dispatch, `_multi_controlled_gate!`
4. `src/context/density.jl` — `apply_ry!`/`apply_rz!` for nc ≥ 2
5. `src/context/abstract.jl` — interface definitions
6. `src/passes/deferred_measurement.jl` — `_add_control`
7. `src/passes/gate_cancel.jl` — `_can_merge`, `_register_and_block!`
8. `src/channel/openqasm.jl` — export for new node types
9. `src/simulation/pauli_exp.jl:191-220` — direct `control_stack` field access
10. `src/block_encoding/lcu.jl:72,102` — direct `control_stack` field access

---

## 4. Gate-to-Primitive Mapping

The mapping from Bennett gates to Sturm primitives is exact and lossless:

| Bennett gate | Sturm equivalent | Orkan ccall |
|---|---|---|
| `NOTGate(t)` | `q.theta += π` (X gate) | `orkan_ry!(state, t, π)` |
| `CNOTGate(c, t)` | `t xor= c` | `orkan_cx!(state, c, t)` |
| `ToffoliGate(c1, c2, t)` | `when(c1) do; t xor= c2; end` | `orkan_ccx!(state, c1, c2, t)` |

Orkan already has native `ccx` (Toffoli). The existing `orkan_ccx!` wrapper in `src/orkan/ffi.jl:225` is the direct call target.

**Toffoli maps to existing DAG representation**: A `ToffoliGate(c1, c2, t)` is a CX(c2, t) with c1 as a control. In the DAG: `CXNode(c2, t, ctrl1=c1, ncontrols=1)`. This already works in TracingContext without any changes to the HotNode union.

### Controlled-circuit overhead

When a Bennett circuit runs inside `when(q)`, every gate acquires the control from the stack:

| Original gate | Inside `when(q)` | Cost |
|---|---|---|
| NOT(t) | Controlled-NOT = CNOT(q, t) | 1 CX |
| CNOT(c, t) | Controlled-CNOT = Toffoli(q, c, t) | 1 CCX |
| Toffoli(c1, c2, t) | Controlled-Toffoli | 2 extra CCX + workspace qubit |

This is identical to Bennett.jl's `controlled()` overhead but applied at runtime by Sturm's control stack rather than at compile time. The overhead is the theoretical minimum for controlling arbitrary classical computation.

**Key insight**: We do NOT need Bennett's `controlled()` wrapper. Sturm's `when()` mechanism already adds the control. Using `when()` + `apply_reversible!` gives the same result with the same overhead but is more flexible — the same circuit can be used controlled or uncontrolled.

---

## 5. Breaking Changes Required

### 5A. Native `apply_ccx!` — bypass the control stack (PERFORMANCE-CRITICAL)

**Problem**: Bennett circuits are dominated by Toffoli gates. Float64 polynomial: 256,920 Toffolis. Each one routed through `when()` means 3 function calls + stack manipulation per Toffoli (`push_control!` → `apply_cx!` → `pop_control!`). For 256K Toffolis, this overhead is severe.

**Change**: Add `apply_ccx!(ctx, c1, c2, target)` as a direct method on all contexts:

```julia
# EagerContext — direct ccall, respects existing control stack
function apply_ccx!(ctx::EagerContext, c1::WireID, c2::WireID, target::WireID)
    q1, q2, qt = _resolve(ctx, c1), _resolve(ctx, c2), _resolve(ctx, target)
    nc = length(ctx.control_stack)
    if nc == 0
        orkan_ccx!(ctx.orkan.raw, q1, q2, qt)
    else
        _multi_controlled_ccx!(ctx, q1, q2, qt)  # Barenco cascade
    end
end

# TracingContext — record as CXNode with 1 inline control
function apply_ccx!(ctx::TracingContext, c1::WireID, c2::WireID, target::WireID)
    # Toffoli(c1, c2, t) = CX(c2, t) controlled on c1
    # If no stack controls: ncontrols=1, ctrl1=c1
    # If 1 stack control: ncontrols=2, ctrl1=stack[1], ctrl2=c1
    #   BUT the CX already has c2 as implicit control — this needs a CCXNode or decomposition
    ...
end
```

This is NOT a 5th primitive — it's a derived operation that shortcuts the control stack path for the hot case (nc=0). The DSL semantics remain 4 primitives. The user never writes `ccx!` — only the Bennett integration layer uses it.

**Impact**: `abstract.jl`, `eager.jl`, `tracing.jl`, `density.jl`. For TracingContext, Toffoli already maps to `CXNode` with `ncontrols=1` — minimal structural change.

### 5B. Batch qubit allocation for ancillae (ESSENTIAL)

**Problem**: Bennett circuits need hundreds to thousands of ancilla qubits. Current Sturm allocates one at a time via `allocate!(ctx)`, each doing Dict insertion + potential state vector resize.

**Change**: Add `allocate_batch!(ctx, n)` and `deallocate_batch!(ctx, wires)`:

```julia
function allocate_batch!(ctx::EagerContext, n::Int)::Vector{WireID}
    # Pre-grow state vector once to avoid repeated resizing
    needed = n - length(ctx.free_slots)
    if needed > 0 && ctx.n_qubits + needed > ctx.capacity
        _grow_to!(ctx, ctx.n_qubits + needed)
    end
    return [allocate!(ctx) for _ in 1:n]
end

function deallocate_batch!(ctx::EagerContext, wires::Vector{WireID})
    for w in wires
        deallocate!(ctx, w)
    end
end
```

**Impact**: `abstract.jl` (interface), `eager.jl`, `tracing.jl`, `density.jl`. Non-breaking — purely additive API.

### 5C. `SubcircuitNode` in the DAG IR (ARCHITECTURAL)

**Problem**: A Bennett-compiled Float64 polynomial has 717,680 gates. Recording each as individual `RyNode`/`CXNode` in TracingContext would create 717K nodes (~18 MB of DAG) for a single `when()` block. Gate cancellation would scan all of these with no understanding of the Bennett structure.

**Change**: New DAG node type for opaque subcircuits:

```julia
struct SubcircuitNode <: DAGNode
    label::Symbol                                # :bennett, :oracle, etc.
    circuit  # ::ReversibleCircuit (from Bennett.jl)
    wire_map::Vector{Pair{Int, WireID}}          # Bennett WireIndex → Sturm WireID
end
```

`SubcircuitNode` is NOT `isbits` (contains Vectors), so it lives outside the `HotNode` union — same treatment as `CasesNode` today. The HotNode inline path is completely untouched.

**Why this matters**:
- Keeps the DAG compact (1 node instead of 717K)
- Optimisation passes can treat it as opaque (skip) or decompose (expand into individual gates)
- OpenQASM export emits it as a `gate` subroutine definition
- No performance regression for the HotNode fast path

**Impact**: `dag.jl` (new node type), `tracing.jl` (recording), `gate_cancel.jl` (skip/decompose logic), `openqasm.jl` (subroutine export).

### 5D. `apply_reversible!` — the bridge function (NEW API)

The core new function that bridges the two systems:

```julia
"""
    apply_reversible!(ctx, circuit::ReversibleCircuit, input_map, output_map)

Execute a Bennett-compiled reversible circuit on a Sturm context.
Allocates ancilla qubits, executes gates, verifies ancillae return to |0⟩,
deallocates ancillae.

If called inside a `when()` block, all gates are automatically controlled
via the existing control stack mechanism.
"""
function apply_reversible!(ctx::AbstractContext,
                           circuit::ReversibleCircuit,
                           input_map::Dict{WireIndex, WireID},
                           output_map::Dict{WireIndex, WireID})
    # 1. Allocate ancilla qubits
    ancilla_map = Dict{WireIndex, WireID}()
    ancilla_wires = WireID[]
    for aw in circuit.ancilla_wires
        w = allocate!(ctx)
        ancilla_map[aw] = w
        push!(ancilla_wires, w)
    end

    # 2. Build full wire map: Bennett WireIndex → Sturm WireID
    wire_map = merge(input_map, output_map, ancilla_map)

    # 3. Execute each gate (control stack applies automatically)
    for gate in circuit.gates
        _apply_bennett_gate!(ctx, gate, wire_map)
    end

    # 4. Deallocate ancillae (Bennett guarantees they're |0⟩)
    for w in ancilla_wires
        deallocate!(ctx, w)
    end
end

# Gate dispatch — each maps to a Sturm primitive
function _apply_bennett_gate!(ctx, g::NOTGate, wm)
    apply_ry!(ctx, wm[g.target], π)          # X gate = Ry(π)
end

function _apply_bennett_gate!(ctx, g::CNOTGate, wm)
    apply_cx!(ctx, wm[g.control], wm[g.target])
end

function _apply_bennett_gate!(ctx, g::ToffoliGate, wm)
    apply_ccx!(ctx, wm[g.control1], wm[g.control2], wm[g.target])
end
```

When called inside `when(q) do ... end`, every gate automatically picks up the control from the stack. The controlled Bennett circuit emerges from Sturm's existing control mechanism.

---

## 6. Risks and Challenges

### 6A. Simulation is impossible for realistic Bennett circuits (FUNDAMENTAL)

This is the most important constraint.

| Circuit | Ancilla wires | Total qubits | Statevector memory |
|---|---|---|---|
| Int8 polynomial | 264 | ~272 | 2^272 × 16 bytes = **impossible** |
| Float64 add | 27,550 | ~27,614 | **impossible** |
| SHA-256 round | 5,889 | ~5,953 | **impossible** |

EagerContext (Orkan statevector) maxes out at 30 qubits = 16 GB. Bennett-compiled circuits for anything beyond trivial functions exceed this by 240+ orders of magnitude.

**Consequence**: Bennett-compiled circuits can ONLY be used with:
- **TracingContext** — records the DAG without simulating. Always works. The primary use case.
- **Future hardware** — when millions of physical qubits exist. The stated target.
- **EagerContext for tiny cases** — Int2/Int4 functions with aggressive pebbling might fit under 30 qubits.

This is not a bug — it's the nature of quantum oracle compilation. Hand-coded Grover oracles also need ancillae; Bennett just makes the ancilla cost explicit and automated rather than manual and ad-hoc.

**Mitigation strategies**:
1. **Pebbling**: With aggressive pebbling (Knill/EAGER), ancilla counts drop by 5–10x. An Int8 polynomial might go from 264 to ~50 ancillae. Still too large for EagerContext, but the gap narrows.
2. **Tiny-width testing**: Compile Int2/Int4 functions for EagerContext verification. Small enough to simulate while exercising the full pipeline.
3. **TracingContext is the primary target**: Most realistic use of Bennett-compiled circuits is DAG capture → OpenQASM export → real hardware.

### 6B. The pebbling gap is a real blocker

Current pebbling achieves only 0.5% wire reduction on SHA-256 (32 wires out of 5,889). The `GateGroup` wire-range tracking bug (Bennett-an5) is the active P1 blocker. Until pebbling works at scale, circuits are 5–10x larger than necessary.

**Recommendation**: Resolve Bennett-an5 before integration. The integration is mechanically straightforward; the value proposition depends on circuits being tractably sized.

### 6C. Controlled-phase subtlety

When a Bennett circuit runs inside `when(q)`, every Toffoli becomes a controlled-Toffoli. The Sturm control stack handles this via the Barenco cascade (already implemented in `_multi_controlled_gate!`). But controlled-Toffoli decomposition costs 2 extra Toffolis per original Toffoli. For a 256K-Toffoli Float64 polynomial, that's 768K Toffolis controlled. At 7 T-gates per Toffoli = **5.4M T-gates**.

This is the theoretical minimum for controlling arbitrary classical computation. No shortcut exists — this is the price of universality.

### 6D. Testing strategy needs rethinking

Since Bennett circuits can't be simulated on EagerContext at realistic sizes:

1. **Tiny-width verification**: Compile Int2/Int4 functions, small enough for EagerContext (~10–20 qubits total). Verify statevector against known-correct answers.
2. **TracingContext structural tests**: Verify DAG is well-formed, gate counts match expectations, wire allocation/deallocation is symmetric.
3. **Bennett-level verification**: `verify_reversibility` in Bennett.jl (classical bit-vector simulation) already proves correctness of the reversible circuit. The Sturm integration just maps wires to qubits.
4. **OpenQASM export**: Export and verify the QASM is valid and structurally correct.
5. **Round-trip**: Bennett compile → Sturm trace → OpenQASM → independent QASM simulator.

### 6E. Package dependency structure

Bennett.jl is at `../research-notebook/Bennett.jl/`. Options:

| Option | Approach | Pros | Cons |
|---|---|---|---|
| A (recommended) | Bennett.jl as dev dependency | Clean separation, independent development | Requires package registration or path dep |
| B | Vendor into `Sturm.jl/src/bennett/` | Simple, one repo | Couples codebases, duplicated maintenance |
| C | Shared interface package | Minimal coupling | Over-engineering for two consumers |

**Recommendation**: Option A. Bennett.jl already has its own `Project.toml`. Add via `] dev ../research-notebook/Bennett.jl`.

### 6F. Known Bennett.jl Gotchas Relevant to Integration

1. **False-path sensitization**: Branchless soft-float eliminated this for Float64, but new functions with complex CFGs may still trigger it. The path-predicate phi resolver is the general solution.
2. **LLVM IR instability**: LLVM may introduce new intrinsics not yet handled. Each unhandled intrinsic is a compile error, not a silent failure (fail-fast).
3. **`@noinline` breaks the pipeline**: Bennett requires inlinable functions — `@noinline` produces `alloca`/`store`/`load` IR that isn't handled.
4. **NaN sign bit non-determinism**: `soft_fdiv` returns +NaN where hardware returns -NaN. Tests must use `isnan()` not bit-exact equality for NaN-producing inputs.
5. **`_name_counter` save/restore**: Required for nested callee compilation. Already handled in Bennett.jl but fragile if the pipeline is extended.

---

## 7. Opportunities

### 7A. Automatic oracle compilation (THE BIG WIN)

Today, every Grover oracle is hand-coded using `phase_flip!` and 4 primitives:

```julia
# BEFORE: hand-coded oracle
function my_oracle!(x::QInt{8})
    # 50+ lines of manual decomposition into primitives
    # error-prone, takes hours to implement
end
```

With Bennett integration:

```julia
# AFTER: automatic compilation
f(x::Int8) = x^2 + 3x + 1 == 42    # plain Julia predicate

@context TracingContext() begin
    q = QBool(1/2)
    x = QInt{8}(0)
    when(q) do
        apply_oracle!(f, x)          # compiled automatically
    end
end
```

Any Julia predicate → quantum oracle. Write normal code, get quantum circuits.

### 7B. Shor's algorithm becomes trivial

Modular exponentiation is the hard part of Shor's. Currently impossible in Sturm.jl without hand-coding hundreds of lines of modular arithmetic. With Bennett:

```julia
f(x::Int64, N::Int64) = powermod(x, e, N)   # plain Julia
circuit = reversible_compile(f, Int64, Int64)
# → use in phase_estimate as the oracle
```

### 7C. Block encodings from arbitrary functions

For QSVT/QSP, the block encoding oracle is often a classical function:

```julia
select_circuit = reversible_compile(select_function, input_types...)
# → embed in BlockEncoding for QSVT
```

### 7D. Float64 quantum oracles (UNPRECEDENTED)

No existing quantum framework can compile `f(x::Float64) = x^2 + 3x + 1` into a quantum circuit. Bennett.jl can. This enables quantum algorithms over continuous variables via discretisation — a capability that exists in the literature only as hand-crafted circuits for specific functions.

### 7E. Automatic resource estimation

Bennett.jl reports exact gate counts, T-counts (`toffoli_count × 7`), and T-depths. Sturm.jl can provide immediate resource estimates for any quantum algorithm:

```julia
resources = estimate_resources(f, Int64)
# → "Your Grover search for this predicate needs 1.2M T-gates and 5,000 qubits"
```

Computed automatically, not estimated.

### 7F. Quantum advantage boundary

With exact gate/qubit counts for any classical function compiled to a quantum oracle, Sturm.jl can answer: "Is this problem worth running on a quantum computer?" Compare the quantum circuit cost (T-gates, qubits, depth) against the classical compute cost. This is a practical quantum advantage calculator.

---

## 8. What This Changes About Sturm.jl's Identity

This integration shifts Sturm.jl from "a quantum DSL where you write circuits using 4 primitives" to **"a quantum programming language where you write normal code and the compiler handles the quantum part."**

The 4 primitives remain the foundation. But the programmer no longer needs to think in primitives for classical subroutines:

| Level | Who writes it | Example |
|---|---|---|
| Primitives | DSL internals | `q.theta += π; q.phi += π/2` |
| Library gates | Framework | `H!(q); swap!(a,b)` |
| Patterns | Framework | `superpose!(); fourier_sample()` |
| **Compiled oracles** | **Programmer writes plain Julia** | **`when(q) do f(x) end`** |

### Consistency with design principles

- **P1 (functions are channels)**: Preserved. The Bennett-compiled function is a channel — a CPTP map from quantum registers to quantum registers.
- **P2 (type boundary = measurement)**: Preserved. No measurements happen inside the compiled oracle. The type boundary still governs when classical values emerge.
- **P3 (operations are operations)**: Preserved. The compiled oracle is just another operation.
- **P4 (quantum control = lexical scope)**: Preserved. `when(q) do ... end` is still the only quantum control construct.
- **P5 (no gates, no qubits in user-facing code)**: **Strengthened**. The programmer writes `f(x) = x^2 + 3x + 1`, not gate sequences.
- **P6 (QECC is a higher-order function)**: Preserved. Error correction wraps channels, including compiled oracles.
- **P7 (dimension-agnostic)**: Preserved. Bennett circuits are classical (d=2) but the integration layer doesn't assume d=2.
- **P8 (quantum promotion)**: Extended. Classical Julia functions promote to quantum operations via Bennett compilation.

The breaking changes (`apply_ccx!`, `SubcircuitNode`, batch allocation) are all **internal**. The user-facing API gets simpler, not more complex.

---

## 9. Implementation Plan

### Phase 0: Pre-integration (Bennett.jl side) — CURRENT

**Must happen before any Sturm.jl work begins.**

- [ ] Resolve Bennett-an5 (pebbling wire reduction) — determines whether circuits are tractably sized
- [ ] Add `reversible_compile` with pebbling as default construction
- [ ] Verify Int2/Int4 functions compile with ancilla counts under 25–30 (simulable in Sturm EagerContext)
- [ ] Integrate Cuccaro in-place adder into main pipeline (halves per-addition ancillae)
- [ ] Stabilise the `ReversibleCircuit` struct as the integration contract

### Phase 1: Foundation (Sturm.jl side, ~1 session)

1. Add Bennett.jl as a `dev` dependency in `Project.toml`
2. Add `apply_ccx!(ctx, c1, c2, target)` to all three contexts
   - EagerContext: direct `orkan_ccx!` call (nc=0), Barenco cascade (nc≥1)
   - TracingContext: record as `CXNode` with 1 inline control
   - DensityMatrixContext: implement or error with clear message
3. Add `allocate_batch!(ctx, n)` and `deallocate_batch!(ctx, wires)` (additive API)
4. Add `apply_reversible!(ctx, circuit, input_map, output_map)` in new file `src/bennett/bridge.jl`
5. Tests: tiny Int2/Int4 circuits on EagerContext, verify statevectors match `simulate()` output

### Phase 2: DAG integration (~1 session, requires 3+1 for SubcircuitNode)

1. Add `SubcircuitNode` to `dag.jl` (non-isbits, outside HotNode union, same treatment as CasesNode)
2. TracingContext records `apply_reversible!` as single SubcircuitNode
3. Update `gate_cancel.jl` to skip SubcircuitNodes (conservative — don't optimise inside them)
4. Update `openqasm.jl` to emit SubcircuitNode as a QASM `gate` subroutine definition
5. Tests: trace a `when()` block containing a Bennett circuit, verify DAG structure, export to OpenQASM

### Phase 3: User-facing API (~1 session)

1. High-level `apply_oracle!` function:

```julia
"""
    apply_oracle!(f::Function, register::QInt{W}; kw...)

Compile `f` to a reversible circuit via Bennett.jl and execute it
on the quantum register. If called inside `when()`, automatically controlled.
"""
function apply_oracle!(f::Function, register::QInt{W}; kw...) where W
    circuit = reversible_compile(f, _julia_type(W); kw...)
    input_map, output_map = _build_wire_maps(circuit, register)
    apply_reversible!(register.ctx, circuit, input_map, output_map)
end
```

2. Resource estimation:

```julia
"""
    estimate_resources(f, types...) -> NamedTuple

Gate count, T-count, qubit count, T-depth for the compiled circuit.
"""
function estimate_resources(f, types...)
    circuit = reversible_compile(f, types...)
    gc = gate_count(circuit)
    return (gates=gc.total, toffoli=gc.Toffoli, t_count=gc.Toffoli * 7,
            qubits=circuit.n_wires, t_depth=t_depth(circuit))
end
```

3. Integration with `phase_flip!` for Grover:

```julia
# Compile a Julia predicate into a phase oracle
function phase_flip!(f::Function, register::QInt{W}; kw...) where W
    circuit = reversible_compile(f, _julia_type(W); kw...)
    # ... execute circuit, flip phase on output=1, uncompute ...
end
```

4. Caching: compile once, reuse across shots. `@bennett_cache` macro or LRU cache keyed on `(f, types)`.

### Phase 4: Optimisation (~future sessions)

1. Wire pebbling integration (once Bennett-an5 is resolved)
2. Gate cancellation across Bennett circuit boundaries (expand SubcircuitNode → cancel adjacent gates at boundaries)
3. T-count optimisation (choose Toffoli decomposition: 7T standard, 4T with measurement, etc.)
4. Caching compiled circuits across `when()` calls
5. Parallelise Bennett compilation (compile oracle while constructing the surrounding circuit)
6. Resource-aware compilation: given a qubit budget, choose pebbling strategy automatically

---

## 10. Research Questions

These are open questions that should be investigated during or after implementation:

1. **Can Bennett circuits be optimised by Sturm's existing passes?** If a SubcircuitNode is expanded into individual gates, can `gate_cancel` merge adjacent rotations at the boundaries? How much does this save?

2. **Choi phase polynomials for Bennett circuits?** (Sturm.jl-d99) If Choi phase polynomials extend to channels, can Bennett-compiled oracles be optimised via phase polynomial methods? The oracle is a unitary (all ancillae return to |0⟩), so the Choi matrix should be rank-1.

3. **MCGS on Bennett circuits?** (Sturm.jl-qfx) The MCGS trilogy operates on compute graphs. A Bennett-compiled circuit IS a compute graph. Can MCGS find shorter equivalent circuits?

4. **Incremental Bennett compilation?** If `f(x) = g(h(x))`, can we compile `h` and `g` separately and compose the circuits? This would enable modular oracle construction.

5. **What is the minimum pebble count for practical functions?** Knill's `min_pebbles(n) = 1 + ceil(log2(n))`. For Int8 polynomial (n ≈ 264 groups), that's ~9 pebbles → ~9 simultaneously-live groups. What does the actual wire count come out to?

6. **Can Sturm's `QInt` arithmetic use Bennett-compiled circuits?** Currently `QInt{W} + QInt{W}` uses a hand-coded ripple-carry adder. Bennett.jl compiles `x + y` for `Int8` to 86 gates. Are these equivalent? Is one better? Could Bennett replace the hand-coded arithmetic entirely?

---

## 11. File Locations Reference

### Bennett.jl (at `../research-notebook/Bennett.jl/`)

| File | Purpose |
|---|---|
| `src/Bennett.jl` | Module entry, exports, SoftFloat dispatch, `reversible_compile` |
| `src/ir_extract.jl` | LLVM IR → ParsedIR via LLVM.jl C API |
| `src/lower.jl` | ParsedIR → gates, phi resolution, MUX, loop unrolling |
| `src/bennett.jl` | Bennett construction (forward + copy + reverse) |
| `src/controlled.jl` | Gate promotion, `controlled()` wrapper |
| `src/gates.jl` | NOTGate, CNOTGate, ToffoliGate, ReversibleCircuit |
| `src/simulator.jl` | Bit-vector simulator with ancilla verification |
| `src/diagnostics.jl` | gate_count, t_count, depth, verify_reversibility |
| `src/adder.jl` | Ripple-carry + Cuccaro in-place adder |
| `src/multiplier.jl` | Shift-and-add multiplier |
| `src/pebbling.jl` | Knill recursion |
| `src/pebbled_groups.jl` | GateGroup-level pebbling with wire reuse |
| `src/sat_pebbling.jl` | SAT-based pebbling (Meuli 2019) |
| `src/eager.jl` | Dead-end wire cleanup |
| `src/value_eager.jl` | PRS15 Algorithm 2 value-level EAGER |
| `src/softfloat/` | IEEE 754 branchless soft-float (fadd, fmul, fdiv, ...) |

### Sturm.jl integration points

| File | What changes |
|---|---|
| `Project.toml` | Add Bennett.jl dependency |
| `src/Sturm.jl` | Include new `bennett/bridge.jl` |
| `src/bennett/bridge.jl` | NEW: `apply_reversible!`, `apply_oracle!`, wire mapping |
| `src/context/abstract.jl` | Add `apply_ccx!`, `allocate_batch!`, `deallocate_batch!` |
| `src/context/eager.jl` | Implement `apply_ccx!` (direct `orkan_ccx!`) |
| `src/context/tracing.jl` | Implement `apply_ccx!` (record as CXNode with 1 control) |
| `src/context/density.jl` | Implement `apply_ccx!` or error |
| `src/channel/dag.jl` | Add `SubcircuitNode` |
| `src/passes/gate_cancel.jl` | Handle SubcircuitNode (skip or decompose) |
| `src/channel/openqasm.jl` | Emit SubcircuitNode as subroutine |
| `test/test_bennett_integration.jl` | NEW: integration tests |
