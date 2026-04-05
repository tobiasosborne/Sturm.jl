# Sturm.jl Implementation Plan

Each step is <=200 LOC. Steps within a phase are sequential. Tests run after every step.

---

## Phase 1: Project Skeleton + Orkan FFI

### Step 1.1 — Project scaffold (~30 LOC)
- `Project.toml` (name, uuid, version, compat)
- `src/Sturm.jl` module skeleton with empty includes
- `test/runtests.jl` skeleton
- **Test:** `julia --project -e 'using Sturm'` loads without error

### Step 1.2 — Orkan FFI types (~60 LOC)
- `src/orkan/ffi.jl`
- Julia constants: `PURE`, `MIXED_PACKED`, `MIXED_TILED`
- Julia struct `OrkanStateRaw` matching C `state_t` layout (24 bytes with padding)
- Julia struct `OrkanKrausRaw` matching C `kraus_t` layout (24 bytes)
- Julia struct `OrkanSuperopRaw` matching C `superop_t` layout (16 bytes)
- `const LIBORKAN` pointing to `../orkan/cmake-build-release/src/liborkan.so`
- **Test:** `sizeof(OrkanStateRaw) == 24`, `sizeof(OrkanSuperopRaw) == 16`

### Step 1.3 — Orkan FFI state functions (~80 LOC)
- `src/orkan/ffi.jl` (append)
- `orkan_state_init!(state, qubits)` — wraps `state_init` with `data=NULL`
- `orkan_state_free!(state)` — wraps `state_free`
- `orkan_state_plus!(state, qubits)` — wraps `state_plus`
- `orkan_state_len(state)` — wraps `state_len`
- `orkan_state_get(state, row, col)` — wraps `state_get`
- `orkan_state_set!(state, row, col, val)` — wraps `state_set`
- **Test:** create PURE 1-qubit state, verify len==2, set amplitude, get it back, free

### Step 1.4 — Orkan FFI gate functions (~100 LOC)
- `src/orkan/ffi.jl` (append)
- Wrap all 18 gate functions: `orkan_x!`, `orkan_y!`, `orkan_z!`, `orkan_h!`, `orkan_s!`, `orkan_sdg!`, `orkan_t!`, `orkan_tdg!`, `orkan_hy!`, `orkan_rx!`, `orkan_ry!`, `orkan_rz!`, `orkan_p!`, `orkan_cx!`, `orkan_cy!`, `orkan_cz!`, `orkan_swap!`, `orkan_ccx!`
- Each is a thin `@ccall` wrapper with input validation (qubit bounds, distinct qubits)
- **Test:** create 1-qubit |0>, apply X, verify state is |1>. Create 2-qubit, apply CX, verify.

### Step 1.5 — Orkan FFI channel functions (~60 LOC)
- `src/orkan/ffi.jl` (append)
- `orkan_kraus_to_superop(kraus)` — wraps `kraus_to_superop`, returns `OrkanSuperopRaw`
- `orkan_channel_1q!(state, sop, target)` — wraps `channel_1q`
- `orkan_superop_free!(sop)` — `Libc.free(sop.data)`
- **Test:** build identity Kraus (1 term, 2x2 identity), convert to superop, verify data non-null, free

### Step 1.6 — OrkanState managed handle (~100 LOC)
- `src/orkan/state.jl`
- `mutable struct OrkanState` — wraps `OrkanStateRaw` with a finalizer
- Constructor: `OrkanState(type, qubits)` — allocates via `state_init`, registers finalizer
- `Base.getindex`, `Base.setindex!` for element access
- `probabilities(s::OrkanState)` — reads `|amp|^2` (PURE) or diagonal (MIXED) into Julia Vector
- `sample(s::OrkanState)` — samples one basis state index from probability distribution
- `n_qubits(s)`, `state_length(s)`, `Base.copy(s)`
- **Test:** create 2-qubit state, apply H+CX via raw FFI, read probabilities, verify Bell state [0.5, 0, 0, 0.5]

---

## Phase 2: Core Types

### Step 2.1 — WireID and AbstractContext (~80 LOC)
- `src/types/wire.jl` — `struct WireID; id::UInt32; end`, counter, `fresh_wire!()`
- `src/context/abstract.jl` — `abstract type AbstractContext end`
- Interface methods (stubs that error): `allocate!`, `deallocate!`, `apply_ry!`, `apply_rz!`, `apply_cx!`, `measure!`, `push_control!`, `pop_control!`, `current_controls`
- **Test:** `WireID` creation, uniqueness

### Step 2.2 — EagerContext struct (~150 LOC)
- `src/context/eager.jl`
- `mutable struct EagerContext <: AbstractContext`
  - `orkan::OrkanState` (the Orkan handle, PURE backend)
  - `n_qubits::Int`
  - `wire_to_qubit::Dict{WireID, Int}` (maps wires to Orkan qubit indices)
  - `consumed::Set{WireID}` (linear resource tracking)
  - `control_stack::Vector{WireID}`
- `allocate!(ctx)` — adds qubit to Orkan state (requires resize: create new state with n+1, copy amplitudes, free old). Returns `WireID`.
- `deallocate!(ctx, wire)` — marks consumed, partial trace (for now: error if entangled, just shrink state)
- **Test:** create EagerContext, allocate 2 wires, verify n_qubits==2

### Step 2.3 — EagerContext gate dispatch (~120 LOC)
- `src/context/eager.jl` (append)
- `apply_ry!(ctx, wire, angle)` — maps wire to qubit index, handles control stack (if controls: use multi-controlled decomposition; for v0.1 single control only → use Orkan `ccx` or manual decomposition). Calls `orkan_ry!`.
- `apply_rz!(ctx, wire, angle)` — same pattern, calls `orkan_rz!`
- `apply_cx!(ctx, control_wire, target_wire)` — calls `orkan_cx!`. If control stack non-empty, becomes Toffoli via `orkan_ccx!`
- `measure!(ctx, wire)` — reads probabilities from Orkan state for this qubit, samples, collapses state (apply projection + renormalize via Orkan ops), returns Bool
- **Test:** allocate 1 qubit, apply_ry!(ctx, w, pi) (X gate), measure, verify true. Apply H (ry pi/2 + rz pi), measure statistics over 1000 trials.

### Step 2.4 — EagerContext measurement implementation (~150 LOC)
- `src/context/eager.jl` (append)
- `measure!(ctx, wire)` full implementation:
  1. Compute marginal probability of qubit being |1>: sum |amp|^2 for all basis states with that qubit bit set
  2. Sample: `rand() < p1` → outcome=1, else outcome=0
  3. Collapse: zero out amplitudes inconsistent with outcome, renormalize
  4. Mark wire consumed
  5. Return `outcome == 1`
- Helper: `marginal_prob(ctx, qubit_idx)` — walks Orkan state data
- Helper: `collapse!(ctx, qubit_idx, outcome)` — projects + renormalizes
- **Test:** QBool(1/2) → measure 1000x → count within 47%-53%. QBool(0) → always false. QBool(1) → always true.

---

## Phase 3: QBool and Primitives

### Step 3.1 — QBool type (~80 LOC)
- `src/types/qbool.jl`
- `mutable struct QBool; wire::WireID; ctx::AbstractContext; consumed::Bool; end`
- `consume!(q)` — checks not already consumed, marks consumed
- `check_live!(q)` — errors if consumed
- `BlochProxy` struct: `wire::WireID, axis::Symbol, ctx::AbstractContext`
- `Base.getproperty(q::QBool, s::Symbol)` — returns `BlochProxy` for `:θ` and `:φ`
- **Test:** create QBool (mock), access .θ and .φ, verify BlochProxy returned

### Step 3.2 — Preparation primitive QBool(p) (~80 LOC)
- `src/primitives/preparation.jl`
- `QBool(ctx::EagerContext, p::Real)` — allocates wire, applies `Ry(2*asin(sqrt(p)))` to prepare state with P(|1>)=p
- `QBool(p::Real)` — uses `current_context()`, calls above
- Handle edge cases: p=0 (no rotation needed, |0>), p=1 (Ry(pi) = X), p=0.5 (Ry(pi/2))
- **Test:** QBool(0) → measure always false. QBool(1) → always true. QBool(0.5) → ~50/50 over 1000.

### Step 3.3 — Rotation primitives (.θ += δ, .φ += δ) (~60 LOC)
- `src/primitives/rotation.jl`
- Define `add_rotation!(proxy::BlochProxy, δ::Real)`:
  - `:θ` → `apply_ry!(proxy.ctx, proxy.wire, δ)`
  - `:φ` → `apply_rz!(proxy.ctx, proxy.wire, δ)`
- Override `Base.:+(proxy::BlochProxy, δ::Real)` to return a `RotationResult` (or use a different mechanism since Julia's `+=` desugars to `x = x + δ`)
- Actually: override via a mutable proxy approach. `proxy.val += δ` doesn't work directly. Use `Base.setproperty!` on QBool or a custom `+=` pattern.
- **Decision:** Use the pattern from the PRD — define `Base.:(+=)` on `BlochProxy` (this isn't standard Julia, so likely: intercept via `setproperty!` on the parent, or use a macro). Simplest v0.1: `rotate_θ!(q, δ)` and `rotate_φ!(q, δ)` as functions, plus the property-based syntax via a `Ref`-like proxy.
- **Test:** QBool(0), q.θ += π → measure true. QBool(0), q.φ += π → measure, verify still |0> (phase on |0> is unobservable). QBool(0.5), q.φ += π then q.θ += π/2 → deterministic outcome.

### Step 3.4 — Entanglement primitive (⊻=) (~60 LOC)
- `src/primitives/entangle.jl`
- `Base.xor(a::QBool, b::QBool)` — `a ⊻= b` desugars to `a = a ⊻ b`
  - Assert same context
  - Check both live
  - `apply_cx!(ctx, b.wire, a.wire)` (b controls, a target)
  - Return `a` (same object, mutation happened in Orkan state)
- **Test:** QBool(0) ⊻= QBool(1) → measure first qubit, verify true. Bell state: QBool(0.5), QBool(0), b ⊻= a → measure both, verify always equal.

### Step 3.5 — Type boundary measurement (~80 LOC)
- `src/primitives/boundary.jl`
- `Base.convert(::Type{Bool}, q::QBool)` — calls `measure!(q.ctx, q.wire)`, consumes q, returns Bool
- `Base.Bool(q::QBool)` — delegates to convert
- **Test:** `x::Bool = q` syntax works. Consumed qubit throws on second use. Bell state ra==rb always.

### Step 3.6 — Quantum control: when() (~80 LOC)
- `src/control/when.jl`
- `when(f::Function, ctrl::QBool)`:
  - `check_live!(ctrl)`
  - `push_control!(ctrl.ctx, ctrl.wire)`
  - `f()`
  - `pop_control!(ctrl.ctx)`
- Nested `when` pushes multiple controls
- **Test:** `when(flag) do; target.φ += π/4; end` — verify controlled phase. Prepare |+>|0>, controlled-X, verify Bell state.

### Step 3.7 — Linear resource tracking (~50 LOC)
- `src/types/qbool.jl` (enhance)
- Every operation that reads a qubit calls `check_live!`
- Every operation that destroys a qubit calls `consume!`
- `discard!(q::QBool)` — explicit discard (partial trace)
- **Test:** use after measure throws. Double consume throws. ⊻= with consumed qubit throws.

---

## Phase 4: Context Propagation + Gates + Integration Tests

### Step 4.1 — Context propagation (@context macro) (~60 LOC)
- `src/context/propagation.jl`
- `current_context()` — reads `task_local_storage(:sturm_context)`, errors if absent
- `@context` macro — sets context in task-local storage, restores on exit
- `QBool(p)` (no ctx arg) — uses `current_context()`
- **Test:** `@context EagerContext() begin q = QBool(0.5); r::Bool = q end` works. Nested contexts. Missing context errors.

### Step 4.2 — Convenience gates (~80 LOC)
- `src/gates.jl`
- `X!(q)`, `Z!(q)`, `S!(q)`, `T!(q)`, `H!(q)` — all built from θ and φ rotations
- `swap!(a, b)` — three CNOTs
- `Y!(q)` = `q.θ += π; q.φ += π` (up to global phase)
- All check linearity
- **Test:** X! flips. H! creates superposition. H! twice returns to original. T! applies pi/4 phase.

### Step 4.3 — Primitive unit tests (~150 LOC)
- `test/test_primitives.jl`
- QBool(0) always false, QBool(1) always true
- QBool(0.5) ~50% (N=10000, tolerance ±3%)
- q.θ += π on QBool(0) gives true
- q.φ += π on QBool(0.5) + q.θ += π/2 gives deterministic outcome
- a ⊻= b on (QBool(0), QBool(1)) gives (true, true)
- Linear resource violations throw

### Step 4.4 — Bell state test (~60 LOC)
- `test/test_bell.jl`
- Prepare Bell pair: a=QBool(0.5), b=QBool(0), b ⊻= a
- Measure both, assert ra==rb (N=1000, all must match)
- GHZ state: 3 qubits, assert all equal (N=1000)

### Step 4.5 — Teleportation test (~80 LOC)
- `test/test_teleportation.jl`
- Implement `teleport!` from PRD §8.2
- Test: prepare known state, teleport, verify measurement statistics match
- Run 1000 trials, verify output distribution matches input preparation

### Step 4.6 — RUS test (~80 LOC)
- `test/test_rus.jl`
- Implement `rus_T!` from PRD §8.3
- Test: apply to known state, verify T-gate statistics
- Compare against direct T application

---

## Phase 5: EagerContext Qubit Resize (Dynamic Allocation)

### Step 5.1 — Dynamic qubit allocation (~150 LOC)
- `src/context/eager.jl` (rewrite `allocate!`)
- Problem: Orkan state is fixed-size at init. Adding a qubit means creating a new state with n+1 qubits.
- Strategy: pre-allocate a pool of N qubits (e.g. 16). `allocate!` returns next free qubit. When pool exhausted, double the pool (create new Orkan state with 2N qubits, tensor-product old state with |0>^N, copy).
- `deallocate!` marks qubit as free but doesn't shrink (compaction is future work)
- **Test:** allocate 5 qubits sequentially, verify each gets unique WireID and qubit index. Deallocate one, verify it's marked consumed.

### Step 5.2 — Controlled gate decomposition (~120 LOC)
- `src/context/eager.jl` (enhance control stack handling)
- Single control: `Ry(θ)` controlled = decompose into CX + Ry(θ/2) + CX + Ry(-θ/2) (standard decomposition)
- Single control: `Rz(θ)` controlled = decompose into CX + Rz(θ/2) + CX + Rz(-θ/2)
- Two controls: use Orkan's `ccx` for Toffoli, plus decomposition for controlled-Ry/Rz
- **Test:** controlled-X via `when(a) do b.θ += π end` produces same result as CX. Controlled-Z via `when(a) do b.φ += π end`.

---

## Phase 6: QInt{W} and Arithmetic

### Step 6.1 — QInt{W} type (~100 LOC)
- `src/types/qint.jl`
- `struct QInt{W}; wires::NTuple{W,WireID}; ctx::AbstractContext; end`
- Constructor: `QInt{W}(ctx, value::Int)` — allocates W qubits, prepares classical value in computational basis (apply X to qubits where bit is 1)
- `QInt{W}(value::Int)` — uses current_context
- `Base.convert(::Type{Int}, q::QInt{W})` — measures all W qubits, assembles classical Int
- `Base.getindex(q::QInt{W}, i)` — returns `QBool` for wire i
- **Test:** QInt{8}(42) → measure → 42. QInt{4}(0) → measure → 0.

### Step 6.2 — Quantum ripple-carry adder (~180 LOC)
- `src/types/qint.jl` (append)
- `Base.:+(a::QInt{W}, b::QInt{W})` — ripple-carry addition using only ⊻= and when()
- Allocate W+1 output register (carry), propagate carries
- Uses ancilla qubits, uncomputes them
- **Test:** QInt{8}(42) + QInt{8}(17) → 59. QInt{8}(200) + QInt{8}(100) → 44 (mod 256).

### Step 6.3 — Quantum subtraction and comparison (~120 LOC)
- `src/types/qint.jl` (append)
- `Base.:-(a::QInt{W}, b::QInt{W})` — via adder with 2's complement
- `Base.:<(a::QInt{W}, b::QInt{W})::QBool` — returns QBool indicating a < b
- `Base.:(==)(a::QInt{W}, b::QInt{W})::QBool` — returns QBool indicating equality
- **Test:** QInt{8}(10) - QInt{8}(3) → 7. QInt{8}(5) < QInt{8}(10) → true.

---

## Phase 7: Library Patterns

### Step 7.1 — superpose and interfere (~120 LOC)
- `src/library/patterns.jl`
- `superpose(x::QInt{W})` — apply QFT / Hadamard transform (uniform superposition from |0>)
- For W=1: just H!. For general W: QFT using θ, φ rotations and ⊻= (built from primitives only)
- `interfere(x::QInt{W})` — inverse QFT
- **Test:** superpose |0> → uniform amplitudes. interfere(superpose(|0>)) → |0>.

### Step 7.2 — fourier_sample (~80 LOC)
- `src/library/patterns.jl` (append)
- `fourier_sample(oracle!, n)` — superpose → oracle → interfere → measure
- **Test:** constant oracle → returns 0 (Deutsch-Jozsa). Balanced oracle → returns nonzero.

### Step 7.3 — Phase estimation stub (~100 LOC)
- `src/library/patterns.jl` (append)
- `phase_estimate(unitary!, eigenstate, precision)` — higher-order channel
- Uses controlled-unitary powers + inverse QFT
- **Test:** phase_estimate with Z gate on |1> → phase = 0.5 (pi = 0.5 * 2pi)

---

## Phase 8: Tracing and Channel Representation

### Step 8.1 — DAG node types (~80 LOC)
- `src/channel/dag.jl`
- Abstract type `DAGNode`
- `PrepNode`, `RyNode`, `RzNode`, `CXNode`, `ObserveNode`, `CasesNode`, `DiscardNode`
- Each carries `controls::Vector{WireID}` where applicable
- **Test:** construct nodes, verify fields

### Step 8.2 — TracingContext (~120 LOC)
- `src/context/tracing.jl`
- `mutable struct TracingContext <: AbstractContext`
  - `dag::Vector{DAGNode}`
  - `wire_counter`, `control_stack`, `consumed`
- Implements all `AbstractContext` methods by appending nodes to DAG
- `allocate!` returns symbolic WireID
- `apply_ry!` appends `RyNode`
- `measure!` appends `ObserveNode`, returns `ClassicalRef`
- **Test:** trace a simple circuit (H + CX), verify DAG has correct nodes

### Step 8.3 — ClassicalRef type (~60 LOC)
- `src/types/classical_ref.jl`
- `struct ClassicalRef; wire::WireID; ctx::TracingContext; end`
- `Base.convert(::Type{Bool}, c::ClassicalRef)` — in tracing mode, records branch
- **Test:** ClassicalRef created by tracing-mode measurement

### Step 8.4 — trace() function and Channel struct (~120 LOC)
- `src/channel/channel.jl` + `src/channel/trace.jl`
- `struct Channel{In,Out}; dag; input_wires; output_wires; end`
- `trace(f::Function)` — creates TracingContext, runs f with symbolic inputs, returns Channel
- **Test:** `ch = trace(teleport!)` produces Channel with correct wire counts

### Step 8.5 — Channel composition (≫ and ⊗) (~100 LOC)
- `src/channel/compose.jl`
- `≫(f::Channel, g::Channel)` — sequential: connect output wires of f to input wires of g, merge DAGs
- `⊗(f::Channel, g::Channel)` — parallel: disjoint wire sets, concatenate DAGs
- **Test:** compose two single-qubit channels, verify DAG. Parallel compose, verify independent wires.

### Step 8.6 — OpenQASM export (~150 LOC)
- `src/channel/openqasm.jl`
- `to_openqasm(ch::Channel)` — walks DAG, emits OpenQASM 3.0 string
- Map: PrepNode → `reset q; ry(angle) q`, RyNode → `ry(θ) q`, RzNode → `rz(θ) q`, CXNode → `cx q1, q2`, ObserveNode → `bit = measure q`
- Handle controlled operations
- **Test:** `to_openqasm(trace(teleport!))` produces valid OpenQASM

---

## Phase 9: Optimisation Passes

### Step 9.1 — Gate cancellation pass (~120 LOC)
- `src/passes/gate_cancel.jl`
- Walk DAG, cancel adjacent inverse gates: Ry(θ) followed by Ry(-θ), etc.
- Merge adjacent same-axis rotations: Ry(a) + Ry(b) → Ry(a+b)
- **Test:** Ry(π) then Ry(-π) → empty. Ry(π/4) then Ry(π/4) → Ry(π/2).

### Step 9.2 — Deferred measurement pass (~150 LOC)
- `src/passes/deferred_measurement.jl`
- Identify ObserveNodes whose ClassicalRef feeds only CasesNodes with pure-quantum branches
- Replace with ControlledNode + AntiControlledNode
- **Test:** measure-then-classically-control pattern defers to quantum control

---

## Phase 10: Density Matrix Backend

### Step 10.1 — DensityMatrixContext struct (~100 LOC)
- `src/context/density.jl`
- `mutable struct DensityMatrixContext <: AbstractContext`
  - `orkan::OrkanState` (type = MIXED_PACKED or MIXED_TILED)
  - Same interface as EagerContext
- Constructor: choose PACKED vs TILED based on qubit count
- `allocate!`, `deallocate!` — same resize strategy
- **Test:** create DensityMatrixContext, allocate 1 qubit, verify Orkan state type is MIXED

### Step 10.2 — DensityMatrixContext gate + measure (~150 LOC)
- `src/context/density.jl` (append)
- `apply_ry!`, `apply_rz!`, `apply_cx!` — delegate to same Orkan gate functions (they dispatch on state type internally)
- `measure!` — read diagonal probabilities, sample, apply projection via Kraus operators (|0><0| or |1><1|), renormalize trace to 1
- **Test:** Bell state via density matrix, verify same statistics as state vector (N=10000, tolerance ±3%)

### Step 10.3 — Density matrix verification tests (~100 LOC)
- `test/test_density_matrix.jl`
- Pure state ρ has Tr(ρ²) = 1
- Bell state partial trace → Tr(ρ²) = 0.5
- Teleportation via density matrix matches state vector

---

## Phase 11: Noise Channels

### Step 11.1 — Noise channel functions (~120 LOC)
- `src/noise/depolarise.jl` — `depolarise!(q::QBool, p::Real)`: builds Kraus operators {sqrt(1-p)*I, sqrt(p/3)*X, sqrt(p/3)*Y, sqrt(p/3)*Z}, converts to superop, applies via `orkan_channel_1q!`
- `src/noise/dephase.jl` — `dephase!(q::QBool, p::Real)`: Kraus {sqrt(1-p)*I, sqrt(p)*Z}
- `src/noise/amplitude_damp.jl` — `amplitude_damp!(q::QBool, γ::Real)`: Kraus {[[1,0],[0,sqrt(1-γ)]], [[0,sqrt(γ)],[0,0]]}
- Error if context is EagerContext (state vector): "Noise channels require DensityMatrixContext"
- **Test:** depolarise(q, 0) leaves state unchanged. depolarise(q, 1) → maximally mixed. dephase(q, 1) on |+> → mixed.

### Step 11.2 — classicalise (higher-order type boundary) (~120 LOC)
- `src/noise/classicalise.jl`
- `classicalise(ch::Channel)` — compute process matrix of channel, discard off-diagonals, return classical stochastic map as Julia function
- Implementation: trace channel with density matrix, read output for each computational basis input, extract transition probabilities
- **Test:** classicalise(identity) → identity map. classicalise(X) → bit-flip. classicalise(H) → uniform.

---

## Phase 12: QECC

### Step 12.1 — QECC interface + Steane code (~180 LOC)
- `src/qecc/abstract.jl` — `abstract type AbstractCode end`, `encode(ch::Channel, code::AbstractCode)::Channel`
- `src/qecc/steane.jl` — `struct Steane <: AbstractCode end`
- Steane [[7,1,3]]: encode 1 logical qubit into 7 physical qubits
- Encoding circuit: prepare |0>^7, apply stabilizer generators using ⊻= and when()
- `encode(ch, Steane())` wraps channel in encoding/decoding
- **Test:** encode single-qubit identity channel, verify logical operation correct

---

## Dependency Graph

```
1.1 → 1.2 → 1.3 → 1.4 → 1.5 → 1.6
                                   ↓
                    2.1 → 2.2 → 2.3 → 2.4
                                        ↓
              3.1 → 3.2 → 3.3 → 3.4 → 3.5 → 3.6 → 3.7
                                                      ↓
                              4.1 → 4.2 → 4.3 → 4.4 → 4.5 → 4.6
                                                   ↓           ↓
                                           5.1 → 5.2    6.1 → 6.2 → 6.3
                                                                       ↓
                                                              7.1 → 7.2 → 7.3
                                                                ↓
                                                 8.1 → 8.2 → 8.3 → 8.4 → 8.5 → 8.6
                                                                                    ↓
                                                                          9.1 → 9.2
                                                   ↓
                                      10.1 → 10.2 → 10.3
                                                      ↓
                                            11.1 → 11.2
                                                      ↓
                                                    12.1
```

## Total: 42 steps, ~4000 LOC estimated
