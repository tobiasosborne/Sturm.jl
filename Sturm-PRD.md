# Sturm.jl — Product Requirements Document

## Version: 0.1.0 (Proof of Concept)

## One-line summary

A Julia quantum programming language where functions are channels, the quantum-classical boundary is a type boundary, and QECC is a higher-order function.

---

## 1. Design Principles (non-negotiable)

These are the axioms of the language. Every design decision must be consistent with them. If an implementation choice violates any principle, the implementation is wrong.

**P1. Functions are channels.** A Julia function with quantum arguments IS a CP map (completely positive, possibly trace non-increasing). Its type signature determines the channel type. Composition of functions is composition of channels. There is no separate "channel" wrapper the programmer must use. Trace-preserving (CPTP) maps are the common case, but trace non-increasing maps are first-class: post-selection, conditional operations, and probabilistic channels (like a single branch of RUS) are all expressible. The type system does not enforce trace preservation — that is a property the programmer or verifier may check, not a constraint the language imposes.

**P2. The quantum-classical boundary is a *cast* — like `Float64 → Int64`.** There is NO `measure()` function. Crossing the quantum/classical boundary is a type cast with implied information loss, exactly analogous to truncating a float to an integer. The language surfaces three cast directions:

- `x = Bool(q)` — explicit cast `QBool → Bool` (measurement). The compiler inserts the measurement channel.
- `q = QBool(x)` — explicit cast `Bool → QBool` (preparation).
- `f_classical = classicalise(ch)` — higher-order cast `Channel → function` (decoherence). Off-diagonal coherences of the process matrix are discarded, leaving a classical stochastic map. Just as `Bool(q)` decoheres a state, `classicalise(ch)` decoheres the channel itself.

**Compiler warning on implicit casts.** Because quantum→classical casting loses information irreversibly, an *implicit* assignment without an explicit cast expression — for example `x::Bool = q` or `y::Int = qi` — triggers a compiler warning, by direct analogy with the "implicit float-to-int truncation" warnings that sensible languages emit. The fix is always the same: wrap the RHS in an explicit cast (`Bool(q)`, `Int(qi)`). Information loss must be *intentional*.

This is the ONLY mechanism for crossing the boundary. Measurement, preparation, and decoherence are not operations — they are consequences of a type cast.

**P3. Operations are operations.** There is no language-level distinction between unitaries, measurements, preparations, noise channels, or partial traces. They are all channels. Whether the backend uses state vectors or density matrices is a compiler/runtime detail invisible to the programmer.

**P4. Quantum control is lexical scope.** `when(q) do ... end` means "control on q". `if x ... end` means "classical branch on x". The distinction is enforced by types: `when` takes `QBool`, `if` takes `Bool`. This is the quantum/classical boundary made syntactically explicit.

**P5. No gates, no qubits.** The programmer never names a gate and never manipulates individual qubits. The programmer works with quantum registers (`QBool`, `QInt{W}`, `QMod{N}`) and the four primitives (§3). Named gates (H, T, CNOT, etc.) exist only as convenience library functions. Individual qubit indexing (`q[i]`) exists for oracle construction but is not the normal mode of programming. The correct test for this principle: if a program reads like a circuit diagram transcribed into code, it is wrong.

**P6. QECC is a higher-order function.** Error correction wraps a channel (= function) in encoding/syndrome/correction/decoding channels. It is a function `Channel → Channel`. It is not a language feature, annotation, or pragma. It is a library function.

**P7. The abstraction is dimension-agnostic across the entire Hilbert spectrum.** The core type system and channel algebra must not assume qubits (d=2), nor any specific local dimension. All of the following must be expressible by *extending* the type hierarchy — never by modifying the core:

- **Finite qudits.** Qutrits (`QTrit`, d=3), arbitrary qudits (`QDit{D}`). The four primitives generalise to `Ry_D`, `Rz_D` on `su(D)` generators plus a controlled-shift for entanglement.
- **Anyons.** Fusion-category wires (`QAnyon{C}`), with braiding and F-/R-moves as primitive-level operations. Topological charge is a type parameter; composition is fusion, not tensor product.
- **Infinite-dimensional systems.** At minimum, **Gaussian CV** for quantum optics: bosonic modes (`QMode`), displacement, squeezing, beamsplitters, phase rotation, and homodyne/heterodyne measurement — all expressible as channels on a covariance-matrix context. Ideally, arbitrary infinite-dimensional systems: full Fock-space arithmetic, bosonic codes (cat, binomial, GKP), and continuous-variable oracles. A CV context stores a Gaussian covariance matrix (or a truncated Fock-basis density operator for non-Gaussian cases); the DSL surface is unchanged.

The test is mechanical: if adding qutrits, anyons, or a Gaussian optical mode requires *any* change to channel composition operators, the tracing infrastructure, `when()`, the cast rules of P2, or the promotion rules of P8, the abstraction is wrong. For v0.1 only d=2 is implemented, but no design decision may foreclose higher finite d, topological d, *or* infinite d. Wires carry a Hilbert-space descriptor (finite-d integer, fusion category, or CV tag), tracked by the context; primitives dispatch on it.

**P8. Quantum promotion follows Julia's numeric tower.** When a classical value (`Bool`, `Integer`) participates in an operation with a quantum value (`QBool`, `QInt{W}`), the classical value auto-promotes to the corresponding quantum type — just as `Int + Float64 → Float64`. Initial quantum construction is explicit: `QInt{8}(42)` is preparation (a physical operation), analogous to `complex(1)`. Mixed-type methods extract context and width from the quantum operand. Promotion is always classical→quantum; quantum→classical requires measurement via P2. Gates (`H!`, `X!`, etc.) and quantum control (`when`) do NOT participate in promotion — they require exact quantum types. Implementation: mixed-type methods are defined directly (NOT via `Base.promote_rule`/`Base.convert`, because `convert(QInt{W}, ::Integer)` would require a quantum context as a side-effect, which violates Julia convention). The context is extracted from the quantum operand.

**P9. Any Julia function is a quantum oracle — automatically, via dispatch.** A plain Julia function written against classical types becomes a reversible quantum oracle the moment it is applied to a quantum argument. No macro, no wrapper, no manual lifting:

```julia
f(x::Int64) = x^2 + 3x + 1     # ordinary Julia
y = f(q)                       # q::QInt{64} — Just Works
```

The mechanism is a three-layer compile-time lift, chosen to match the ergonomics of `ForwardDiff.Dual` and `Enzyme.gradient`:

1. **Dispatch fallback.** A generated catch-all method `(f::Function)(args::Quantum...)` fires only when no more-specific user method exists. At compile time it inspects `hasmethod(f, classical_types_of(args))`; if a classical method exists, it lowers the call to `oracle(f, args...)`, otherwise it raises `MethodError`. Scoping the fallback to argument types Sturm owns (`<:Quantum`) avoids method piracy.
2. **Bennett compilation.** `oracle` hands `f` to Bennett.jl, which extracts LLVM IR and emits a reversible circuit, auto-dispatching the cheapest memory strategy per allocation site (Shadow / MUX / QROM / Feistel). The compiled circuit is cached keyed on `(f, argtypes)` — a single LLVM pass per (function, signature) pair, amortised across shots.
3. **Context integration.** Inside `when(ctrl) do … end`, the cached reversible circuit is lifted to its controlled form automatically through Sturm's existing control stack. No `controlled(f)` handle, no separate declaration.

`quantum(f)` remains as the *explicit* pre-compile handle — useful when the caller wants to pay the LLVM-IR cost up front and reuse the cached circuit deliberately, the same pattern as `g = gradient(f)`. But it is sugar on top of the automatic path, not a requirement. User overloads of `f` on quantum types always win (Julia dispatch), so domain-specific quantum versions can shadow the automatic lift wherever that is desired.

The principle: the user writes Julia; the language makes it quantum. The same classical code must run correctly on classical arguments and produce a valid reversible circuit on quantum arguments, with no change to the source of `f`.

---

## 2. Type System

### 2.1 Quantum types

```julia
abstract type Quantum end
abstract type QDit{D} <: Quantum end    # D = local dimension (2 for qubit, 3 for qutrit, ...)

struct QBool <: QDit{2}                 # single qubit — control type
    wire::WireID
    ctx::CompilationContext
end

struct QInt{W} <: QDit{2}               # W-qubit register
    wires::NTuple{W, WireID}
    ctx::CompilationContext
end

struct QMod{N} <: QDit{2}               # modular arithmetic register
    val::QInt
    ctx::CompilationContext
end

struct QArray{T<:Quantum, N} <: Quantum
    elements::Array{T, N}
    ctx::CompilationContext
end

# ── Future extensions (NOT implemented in v0.1, but must not be foreclosed) ──
# struct QTrit <: QDit{3} ... end        # qutrit
# struct QTritInt{W} <: QDit{3} ... end  # W-qutrit register (base-3 arithmetic)
# struct QAnyon{C<:FusionCategory} <: Quantum ... end  # anyonic system
```

Design notes:
- `QDit{D}` is the abstract supertype parameterised by local Hilbert space dimension. All qubit types have `D=2`. Adding qutrits means adding `QDit{3}` subtypes; the channel algebra, tracing infrastructure, and composition operators must not change. If they do, the abstraction is wrong.
- `QBool` is NOT a special case of `QInt{1}`. It is its own type. This is deliberate: `QBool` is the type of control wires and the type that participates in `when` blocks. Conflating it with `QInt{1}` muddies the semantics. Conversion between them is explicit.
- Width `W` is a type parameter on `QInt`. Julia specialises on it. `QInt{8} + QInt{8}` and `QInt{16} + QInt{16}` compile to different circuits at zero runtime cost via generated functions.
- `QMod{N}` carries the modulus in the type parameter. All arithmetic auto-reduces mod N. Type infection: `QMod{N} op QInt → QMod{N}`.
- `WireID` is an opaque handle (UInt32 or similar). It is NOT a qubit index. It is a symbolic reference into the compilation context's wire graph. Wires carry a dimension `D` (2 for qubit, 3 for qutrit, etc.) tracked by the context.
- `CompilationContext` is the DAG being built. All quantum values in a computation share the same context. It is the "circuit under construction."

### 2.2 Classical types at the boundary

The quantum→classical boundary is Julia's standard conversion system:

```julia
function Base.convert(::Type{Bool}, q::QBool)
    # In tracing mode: insert ObserveNode, return ClassicalRef
    # In eager mode: collapse state, return Bool
end

function Base.convert(::Type{Int}, q::QInt{W}) where {W}
    # Measure all W qubits, return classical Int
end
```

The quantum→classical boundary for channels (higher-order type boundary):

```julia
function classicalise(ch::Channel{In,Out})
    # Discard off-diagonal coherences in the channel's process matrix.
    # Returns a classical stochastic map (ordinary Julia function).
    # This IS decoherence, expressed as a type boundary crossing at the channel level.
end
```

The returned `ClassicalRef` (tracing mode) behaves like a `Bool`/`Int` but is still a node in the DAG. When used in `if`, it records both branches. When used in `when`, the compiler can optimise away the measurement (deferred measurement).

### 2.3 Subtyping relationship

```
Quantum
├── QDit{D}                    # abstract, parameterised by local dimension
│   ├── QBool     (D=2)       # single qubit, control type
│   ├── QInt{W}   (D=2)       # W-qubit register
│   └── QMod{N}   (D=2)       # modular register
└── QArray{T, N}               # array of quantum values
```

`QBool` and `QInt{W}` are siblings, not parent-child. Conversion is explicit:

```julia
QBool(q::QInt{1})    # extract single-wire QInt as QBool
QInt{1}(q::QBool)    # wrap QBool as single-wire QInt
```

### 2.4 Categorical structure

The channel algebra has the structure of a symmetric monoidal category with duals (compact closed category):

- **Objects**: quantum types (`QBool`, `QInt{W}`, ...) and classical types (`Bool`, `Int`, ...)
- **Morphisms**: channels (= Julia functions with quantum arguments)
- **Sequential composition** `≫`: function composition. `f ≫ g` feeds output of `f` into `g`.
- **Parallel composition** `⊗`: tensor product. `f ⊗ g` runs `f` and `g` on independent subsystems.
- **Duals**: every type has a dual (the "bra" to its "ket"). Enables cups and caps for teleportation, entanglement swapping.

This is the correct framework for:
- String diagrams / ZX-calculus (visual reasoning about channels)
- Fusion categories (anyonic systems, post-v0.1)
- Categorical quantum mechanics (Abramsky-Coecke framework)

For v0.1, only `≫` and `⊗` on `Channel` values are implemented. The full compact closed structure (duals, traces, yanking) is a future extension, required for anyonic systems.

### 2.5 Linear resource tracking

Quantum values must be consumed exactly once (no-cloning theorem). In the v0.1 POC, enforce this at runtime:

```julia
function consume!(q::QBool)
    q.consumed && error("Linear resource violation: wire $(q.wire) already consumed")
    q.consumed = true
end
```

Every operation that destroys a quantum value (measurement via type boundary, uncomputation, explicit discard) calls `consume!`. Every operation that reads a quantum value (controlled operations, entangling gates) checks `q.consumed == false`.

Future: enforce linearity at compile time via a macro or custom pass. For v0.1, runtime checks are sufficient.

---

## 3. Primitives

Exactly four. Everything else is derived.

| # | Syntax | Semantics | QASM |
|---|--------|-----------|------|
| 1 | `QBool(p::Real)` | Preparation: Ry(2 arcsin √p)\|0⟩. P(\|1⟩) = p | `ry(2*arcsin(sqrt(p))) q` |
| 2 | `q.θ += δ` | Amplitude rotation: Ry(δ) | `ry(δ) q` |
| 3 | `q.φ += δ` | Phase rotation: Rz(δ) | `rz(δ) q` |
| 4 | `a ⊻= b` | CNOT: b controls, a target | `cx b, a` |

Implementation of `.θ` and `.φ`:

```julia
struct BlochProxy
    wire::WireID
    axis::Symbol   # :θ or :φ
    ctx::CompilationContext
end

Base.getproperty(q::QBool, s::Symbol) = begin
    s == :θ && return BlochProxy(q.wire, :θ, q.ctx)
    s == :φ && return BlochProxy(q.wire, :φ, q.ctx)
    getfield(q, s)
end

# Only += and -= are defined. No read access.
function Base.:(+=)(proxy::BlochProxy, δ::Real)
    if proxy.axis == :θ
        push!(proxy.ctx, RyNode(proxy.wire, δ))
    else
        push!(proxy.ctx, RzNode(proxy.wire, δ))
    end
end
```

Attempting to read `q.θ` as a value (rather than using `+=`) returns a `BlochProxy`, which is useless as a number. The type system prevents misuse. You cannot observe the Bloch angles without measurement.

### 3.1 Derived gates (standard library, NOT primitives)

```julia
# These live in src/gates.jl as convenience functions.
# They are NOT part of the language spec.

X!(q::QBool)  = q.θ += π
Z!(q::QBool)  = q.φ += π
S!(q::QBool)  = q.φ += π/2
T!(q::QBool)  = q.φ += π/4
H!(q::QBool)  = (q.φ += π; q.θ += π/2)   # up to global phase

# Swap is three CNOTs
function swap!(a::QBool, b::QBool)
    a ⊻= b
    b ⊻= a
    a ⊻= b
end
```

---

## 4. Quantum Control: `when`

```julia
function when(f::Function, ctrl::QBool)
    push_control!(ctrl.ctx, ctrl.wire)
    f()
    pop_control!(ctrl.ctx)
end
```

Usage:

```julia
when(flag) do
    target.φ += π/4    # controlled-T
end
```

Nesting composes controls via Toffoli ancillae (handled by the compilation context, not the programmer):

```julia
when(a) do
    when(b) do
        target.θ += π   # Toffoli: controlled-controlled-X
    end
end
```

Key semantic distinction:
- `when(q::QBool) do ... end` — quantum control. `q` remains quantum. No measurement.
- `if x::Bool ... end` — classical control. `x` was obtained by measurement (type boundary crossing). The branch is classical.

The compiler enforces this. `when` only accepts `QBool`. `if` only accepts `Bool` (or `ClassicalRef` in tracing mode).

---

## 5. Dual-mode execution

The same source code runs in two modes. The `CompilationContext` type determines which:

### 5.1 Eager mode (simulation)

`QBool` wraps actual simulator state. Operations execute immediately. Type-boundary crossings (`x::Bool = q`) collapse the state and return a real `Bool`.

```julia
ctx = EagerContext(backend=:statevector)  # or :densitymatrix, :stabiliser
q = QBool(ctx, 1/2)
r = QBool(ctx, 0)
r ⊻= q
result::Bool = q    # actually collapses state, returns Bool
```

### 5.2 Tracing mode (compilation)

`QBool` wraps a symbolic wire. Operations append nodes to a DAG. Type-boundary crossings insert `ObserveNode` and return `ClassicalRef`.

```julia
ch = trace(my_function!)    # returns Channel value
```

The `trace` function:
1. Creates a `TracingContext`.
2. Creates symbolic `QBool`/`QInt` inputs with fresh `WireID`s.
3. Calls the user's function with these symbolic inputs.
4. Collects the DAG from the context.
5. Returns a `Channel` value.

### 5.3 The Channel representation (internal)

```julia
struct Channel{In, Out}
    dag::DAG                    # directed acyclic graph of nodes
    input_wires::Vector{WireID}
    output_wires::Vector{WireID}
end
```

Channel algebra (available after tracing):

```julia
# Sequential composition
f ≫ g       # output wires of f connect to input wires of g

# Parallel composition
f ⊗ g       # side by side, no interaction

# Inspection
depth(ch)
gate_count(ch)
draw(ch)             # string diagram or circuit diagram
to_openqasm(ch)      # export

# Optimisation
optimise(ch, :clifford_simp)
optimise(ch, :cancel_adjacent)

# QECC (higher-order function)
encode(ch, Steane())
encode(ch, Surface(17))

# Dagger (only valid if ch is unitary — runtime error otherwise)
dagger(ch)

# Compile to hardware
compile(ch, target=:generic)
```

---

## 6. Deferred measurement optimisation

This is a compiler pass on the `Channel` DAG, not a language feature.

The pass identifies `ObserveNode`s whose classical output feeds ONLY into `CasesNode`s that control quantum operations. In this case, the measurement is unnecessary: the classical control can be replaced by quantum control (`when`), and the `ObserveNode` is removed.

Criteria for deferral:
1. The `ClassicalRef` from the `ObserveNode` is used ONLY as the condition in `CasesNode`s.
2. Every branch of every `CasesNode` contains only quantum operations (no classical side effects, no I/O, no loop control).

If both hold, replace:
- `ObserveNode(q) → ClassicalRef(c)` + `CasesNode(c, branch0, branch1)`

with:
- `ControlledNode(q, branch1)` + `AntiControlledNode(q, branch0)`

This is the Principle of Deferred Measurement expressed as a compiler rewrite rule.

---

## 7. Implementation Plan — v0.1 POC Scope

### 7.1 What to build (in order)

**Phase 1: Core types and primitives**
- [ ] `WireID`, `CompilationContext` (DAG-based)
- [ ] `QBool` with `.θ +=`, `.φ +=`, `⊻=`
- [ ] `QBool(p)` preparation
- [ ] `Base.convert(::Type{Bool}, ::QBool)` — measurement as type boundary
- [ ] `when(f, ctrl::QBool)` — quantum control
- [ ] Runtime linear resource checking
- [ ] Unit tests for all four primitives

**Phase 2: Eager execution backend**
- [ ] `EagerContext` with state vector backend
- [ ] State vector simulation: apply Ry, Rz, CNOT to a complex vector
- [ ] Measurement: sample from probability distribution, collapse state
- [ ] Classical branching after measurement
- [ ] Test: Bell state preparation and measurement statistics
- [ ] Test: teleportation protocol

**Phase 3: QInt{W} and arithmetic**
- [ ] `QInt{W}` type with W-qubit registers
- [ ] `Base.:+`, `Base.:-`, `Base.:*` via ripple-carry adder circuits
- [ ] `Base.convert(::Type{Int}, ::QInt{W})` — multi-qubit measurement
- [ ] Comparisons returning `QBool`
- [ ] Test: quantum addition verified against classical

**Phase 4: Library patterns (higher-order channels)**
- [ ] `superpose(x::QInt{W})` — uniform superposition
- [ ] `interfere(x::QInt{W})` — inverse QFT / Hadamard transform
- [ ] `fourier_sample(oracle!, n)` — the Fourier sampling pattern
- [ ] Test: fourier_sample with constant oracle returns 0
- [ ] Test: fourier_sample with balanced oracle returns nonzero

**Phase 5: Tracing and Channel representation**
- [ ] `TracingContext` that builds DAG instead of executing
- [ ] `ClassicalRef` type for deferred classical values
- [ ] `trace(f)` function
- [ ] `Channel{In, Out}` struct
- [ ] `≫` and `⊗` composition operators
- [ ] `to_openqasm(ch)` export
- [ ] Test: trace teleportation, verify DAG structure

**Phase 6: Optimisation passes**
- [ ] Gate cancellation (adjacent inverse gates)
- [ ] Deferred measurement pass (§6)
- [ ] Clifford simplification
- [ ] Test: deferred measurement on RUS protocol

**Phase 7: Density matrix backend**
- [ ] `DensityMatrixContext` implementing `AbstractContext` interface
- [ ] Density matrix simulation: ρ → E(ρ) = Σ Kᵢ ρ Kᵢ† for Kraus operators
- [ ] Same four primitives produce Kraus operators instead of unitaries
- [ ] Type-boundary measurement: partial trace + projection on density matrix
- [ ] Test: Bell state as density matrix matches state vector statistics
- [ ] Test: teleportation produces correct output density matrix

**Phase 8: Noise channels**
- [ ] `depolarise!(q, p)` — depolarising channel as DAG node
- [ ] `dephase!(q, p)` — dephasing channel
- [ ] `amplitude_damp!(q, γ)` — amplitude damping
- [ ] Noise channels compose naturally with unitaries in the DAG
- [ ] `classicalise(ch)` — higher-order type boundary: quantum channel → classical stochastic map
- [ ] Test: depolarising channel on pure state produces correct mixed state
- [ ] Test: classicalise(identity_channel) produces identity stochastic map
- [ ] Test: classicalise(hadamard) produces uniform stochastic map

**Phase 9: QECC as higher-order function**
- [ ] `encode(ch::Channel, code::AbstractCode)` interface
- [ ] Steane [[7,1,3]] code implementation
- [ ] Test: encode a single-qubit channel, verify logical operation

### 7.2 What is explicitly OUT of scope for v0.1

- Stabiliser backend
- Hardware compilation targets (IBM, IonQ, etc.)
- `QMod{N}` modular arithmetic
- `QArray` 
- Compile-time linearity checking
- Performance optimisation of the simulator
- Any GUI, notebook integration, or visualisation beyond text

### 7.3 File structure

```
Sturm.jl/
├── Project.toml
├── src/
│   ├── Sturm.jl                  # module definition, exports
│   ├── types/
│   │   ├── wire.jl               # WireID
│   │   ├── qbool.jl              # QBool, BlochProxy
│   │   ├── qint.jl               # QInt{W}
│   │   └── classical_ref.jl      # ClassicalRef
│   ├── context/
│   │   ├── abstract.jl           # AbstractContext interface
│   │   ├── eager.jl              # EagerContext + state vector sim
│   │   ├── density.jl            # DensityMatrixContext + density matrix sim
│   │   └── tracing.jl            # TracingContext + DAG builder
│   ├── primitives/
│   │   ├── preparation.jl        # QBool(p) constructors
│   │   ├── rotation.jl           # .θ += δ, .φ += δ
│   │   ├── entangle.jl           # ⊻=
│   │   └── boundary.jl           # convert(Bool, QBool), convert(Int, QInt)
│   ├── noise/
│   │   ├── depolarise.jl         # depolarise!(q, p)
│   │   ├── dephase.jl            # dephase!(q, p)
│   │   ├── amplitude_damp.jl     # amplitude_damp!(q, γ)
│   │   └── classicalise.jl       # classicalise(ch) — higher-order type boundary
│   ├── control/
│   │   └── when.jl               # when(f, ctrl) quantum control
│   ├── channel/
│   │   ├── channel.jl            # Channel{In,Out} struct
│   │   ├── trace.jl              # trace(f) → Channel
│   │   ├── compose.jl            # ≫, ⊗
│   │   └── openqasm.jl           # to_openqasm export
│   ├── passes/
│   │   ├── deferred_measurement.jl
│   │   ├── gate_cancel.jl
│   │   └── clifford_simp.jl
│   ├── qecc/
│   │   ├── abstract.jl           # AbstractCode interface
│   │   └── steane.jl             # Steane [[7,1,3]]
│   ├── library/
│   │   └── patterns.jl           # superpose, interfere, fourier_sample, phase_estimate
│   └── gates.jl                  # Convenience: H!, X!, Z!, T!, S!, swap!
└── test/
    ├── runtests.jl
    ├── test_primitives.jl
    ├── test_bell.jl
    ├── test_teleportation.jl
    ├── test_rus.jl
    ├── test_arithmetic.jl
    ├── test_patterns.jl          # fourier_sample, phase_estimate
    ├── test_tracing.jl
    ├── test_deferred_measurement.jl
    ├── test_density_matrix.jl
    ├── test_noise.jl
    ├── test_classicalise.jl
    └── test_qecc.jl
```

---

## 8. Reference Programs

These programs define the language by example. If the implementation cannot run these exactly as written, the implementation is wrong.

### 8.1 Bell state

```julia
using Sturm

ctx = EagerContext()

a = QBool(ctx, 1/2)     # |+⟩
b = QBool(ctx, 0)        # |0⟩
b ⊻= a                   # Bell pair: (|00⟩ + |11⟩)/√2

ra::Bool = a
rb::Bool = b
@assert ra == rb          # always correlated
```

### 8.2 Teleportation

```julia
function teleport!(q::QBool) :: QBool
    a = QBool(1/2)
    b = QBool(0)
    b ⊻= a

    a ⊻= q

    rq::Bool = q
    ra::Bool = a

    if ra; b.θ += π; end
    if rq; b.φ += π; end
    return b
end
```

### 8.3 Repeat-until-success

```julia
function rus_T!(target::QBool)
    while true
        anc = QBool(1/8)
        anc ⊻= target
        anc ⊻= target

        ok::Bool = anc

        if ok; return; end
        target.φ -= π/4
    end
end
```

### 8.4 Quantum arithmetic

```julia
ctx = EagerContext()

a = QInt{8}(ctx, 42)
b = QInt{8}(ctx, 17)
s = a + b

result::Int = s           # measurement via type boundary
@assert result == 59
```

### 8.5 Tracing and QECC

```julia
ch = trace(teleport!)                  # Channel{QBool, QBool}
ch_opt = optimise(ch, :deferred)       # defer measurements if possible
ch_enc = encode(ch_opt, Steane())      # QECC: higher-order function
qasm = to_openqasm(ch_enc)            # export
```

### 8.6 Higher-order channels (demonstrating that algorithms are library functions)

The whole point of the DSL is that the programmer never thinks about qubits or gates.
Quantum algorithms are patterns — higher-order functions on channels. The programmer
calls them, not implements them.

```julia
# ── Fourier sampling: a library function, not a user-written algorithm ──
# superpose, interfere, fourier_sample live in src/library/patterns.jl

# The programmer writes an oracle as a plain function:
function my_oracle!(x::QInt{4})
    # mark some states — this is domain logic, not quantum plumbing
    when(x[1]) do
        x[4].φ += π
    end
end

# Deutsch-Jozsa is ONE LINE:
outcome = fourier_sample(my_oracle!, 4)    # returns classical Int
is_constant = (outcome == 0)

# The programmer never touched a superposition, never interfered,
# never manually measured. fourier_sample is a higher-order channel:
# it takes a channel (the oracle), wraps it in the Fourier sampling
# pattern, and returns a classical result.
```

The library functions that make this work:

```julia
# src/library/patterns.jl — these are LIBRARY code, not user code

"""Apply QFT to a quantum register (uniform superposition from |0⟩)."""
function superpose(x::QInt{W}) :: QInt{W} where {W}
    # Implementation uses θ and φ rotations + ⊻=
    # The programmer never calls this directly for standard algorithms
end

"""Apply inverse QFT / Hadamard interference."""
function interfere(x::QInt{W}) :: QInt{W} where {W} end

"""Fourier sampling: superpose → apply oracle → interfere → measure."""
function fourier_sample(oracle!::Function, n::Int) :: Int
    x = QInt{n}(0)
    x = superpose(x)
    oracle!(x)
    x = interfere(x)
    result::Int = x        # type boundary = measurement
    return result
end

"""Phase estimation: given a unitary channel and an eigenstate, estimate phase."""
function phase_estimate(unitary!::Function, eigenstate::QInt{W}, precision::Int) :: Int where {W}
    # Higher-order channel: takes a function, returns classical data
end

"""Amplitude estimation: estimate probability of oracle accepting."""
function amplitude_estimate(oracle!::Function, n::Int, precision::Int) :: Float64
    # Composes fourier_sample with phase_estimate
end
```

This is the design pattern: quantum algorithms are not programs the user writes.
They are library functions — higher-order channels that compose other channels.
The user writes domain logic (oracles, cost functions, state preparation).
The library handles the quantum mechanics.

### 8.7 Noise channels and decoherence

```julia
# Noise is just another operation. No special syntax.
@context DensityMatrixContext() begin
    q = QBool(1/2)          # |+⟩ as density matrix
    depolarise!(q, 0.1)     # 10% depolarising noise — just a channel
    result::Bool = q         # measurement: type boundary, same as always
end
```

### 8.8 Classicalise — higher-order type boundary

```julia
# Trace a quantum function to get a Channel value
ch = trace(teleport!)                # Channel{QBool, QBool}

# Classicalise: quantum channel → classical stochastic map
# This IS decoherence at the channel level.
# Just as QBool → Bool decoheres a state,
# Channel → Function decoheres a channel.
f = classicalise(ch)                 # ordinary Julia function Bool → Bool

# f is now a classical stochastic map: the diagonal of the process matrix.
# For teleportation (a unitary channel), this is the identity map.
@assert f(true) == true
@assert f(false) == false
```

### 8.9 Quantum promotion (numeric tower)

```julia
# Classical values auto-promote when combined with quantum values (P8).
# This follows Julia's convention: Int + Float64 → Float64.
ctx = EagerContext()

# Explicit construction is preparation — like complex(1) or big(42)
a = QInt{8}(ctx, 42)

# Classical 17 auto-promotes to QInt{8}(17) using a's context and width
s = a + 17
result::Int = s
@assert result == 59

# Commutative: classical on either side
b = QInt{8}(ctx, 10)
t = 5 + b
result2::Int = t
@assert result2 == 15

# XOR with Bool: true = X gate, false = no-op
q = QBool(ctx, 0.0)
q ⊻= true                    # equivalent to X!(q)
@assert Bool(q) == true

# Overflow wraps: 300 mod 256 = 44
c = QInt{8}(ctx, 42)
u = c + 300
result3::Int = u
@assert result3 == 86         # (42 + 44) mod 256

# Gates do NOT participate in promotion — they require exact quantum types
# H!(true)   → MethodError    (correct: use QBool(true) then H!)
# when(true)  → MethodError    (correct: use if for classical control)
```

---

## 9. Key Implementation Details

### 9.1 The CompilationContext DAG

The DAG is a list of nodes. Each node is one of:

```julia
abstract type DAGNode end

struct PrepNode <: DAGNode
    output::WireID
    p::Float64
end

struct RyNode <: DAGNode
    wire::WireID
    angle::Float64
    controls::Vector{WireID}   # from active when() blocks
end

struct RzNode <: DAGNode
    wire::WireID
    angle::Float64
    controls::Vector{WireID}
end

struct CXNode <: DAGNode
    control::WireID
    target::WireID
    controls::Vector{WireID}   # additional controls from when() nesting
end

struct ObserveNode <: DAGNode
    quantum_wire::WireID
    classical_wire::WireID     # output
end

struct CasesNode <: DAGNode
    classical_wire::WireID
    branches::Dict{Int, Vector{DAGNode}}   # value → sub-DAG
end

struct DiscardNode <: DAGNode
    wire::WireID               # partial trace
end

# ── Noise channel nodes (require density matrix backend for execution) ──

struct DepolariseNode <: DAGNode
    wire::WireID
    p::Float64                 # depolarising probability
end

struct DephaseNode <: DAGNode
    wire::WireID
    p::Float64                 # dephasing probability
end

struct AmplitudeDampNode <: DAGNode
    wire::WireID
    γ::Float64                 # damping rate
end
```

Every `RyNode`, `RzNode`, and `CXNode` carries a `controls` field populated from the current `when()` stack. This is how quantum control is compiled: `when(q) do target.φ += δ end` produces `RzNode(target, δ, [q])`.

### 9.2 State vector backend (EagerContext)

State is a `Vector{ComplexF64}` of length 2^n where n is the number of live qubits. Operations apply the appropriate matrix to the relevant qubit indices.

For v0.1, this can be a dense state vector with no optimisation. Correctness over performance. The interface is:

```julia
mutable struct EagerContext <: AbstractContext
    state::Vector{ComplexF64}
    n_qubits::Int
    wire_to_qubit::Dict{WireID, Int}    # maps symbolic wires to qubit indices
    control_stack::Vector{WireID}
end

allocate!(ctx::EagerContext) :: WireID
apply_ry!(ctx::EagerContext, wire::WireID, angle::Float64)
apply_rz!(ctx::EagerContext, wire::WireID, angle::Float64)
apply_cx!(ctx::EagerContext, control::WireID, target::WireID)
measure!(ctx::EagerContext, wire::WireID) :: Bool    # internal only, never user-facing
deallocate!(ctx::EagerContext, wire::WireID)
```

### 9.3 Density matrix backend (DensityMatrixContext)

State is a `Matrix{ComplexF64}` of size 2^n × 2^n. Unitary operations apply as ρ → U ρ U†. Noise channels apply Kraus operators: ρ → Σᵢ Kᵢ ρ Kᵢ†.

Same interface as `EagerContext`. The programmer's code does not change — only the context type differs:

```julia
mutable struct DensityMatrixContext <: AbstractContext
    ρ::Matrix{ComplexF64}
    n_qubits::Int
    wire_to_qubit::Dict{WireID, Int}
    control_stack::Vector{WireID}
end

allocate!(ctx::DensityMatrixContext) :: WireID
apply_ry!(ctx::DensityMatrixContext, wire::WireID, angle::Float64)    # ρ → Ry ρ Ry†
apply_rz!(ctx::DensityMatrixContext, wire::WireID, angle::Float64)    # ρ → Rz ρ Rz†
apply_cx!(ctx::DensityMatrixContext, control::WireID, target::WireID) # ρ → CX ρ CX†
apply_depolarise!(ctx::DensityMatrixContext, wire::WireID, p::Float64) # Kraus: ρ → (1-p)ρ + p/3(XρX+YρY+ZρZ)
apply_dephase!(ctx::DensityMatrixContext, wire::WireID, p::Float64)
apply_amplitude_damp!(ctx::DensityMatrixContext, wire::WireID, γ::Float64)
measure!(ctx::DensityMatrixContext, wire::WireID) :: Bool             # sample + partial trace
deallocate!(ctx::DensityMatrixContext, wire::WireID)
```

If a noise channel node is encountered in `EagerContext` (state vector), it must error with a clear message: "Noise channels require DensityMatrixContext." This enforces P3 (operations are operations) while being honest about backend capabilities.

### 9.4 Context propagation

The POC must solve: how does `QBool(1/2)` inside a function body know which context to use?

Option A (explicit): every function takes `ctx` as first argument. Verbose but clear.
Option B (task-local): store context in `task_local_storage()`. Functions access it implicitly.

For v0.1, use **Option B** with a fallback error if no context is active:

```julia
function current_context()
    ctx = get(task_local_storage(), :sturm_context, nothing)
    ctx === nothing && error("No active Sturm context. Use `ctx = EagerContext()` first.")
    return ctx
end

macro context(ctx_expr, body)
    quote
        task_local_storage(:sturm_context, $(esc(ctx_expr)))
        try
            $(esc(body))
        finally
            delete!(task_local_storage(), :sturm_context)
        end
    end
end

# Usage:
@context EagerContext() begin
    q = QBool(1/2)     # finds context via task_local_storage
    # ...
end
```

### 9.5 The ⊻= operator

Julia does not have `Base.xor!` for custom types. Override `Base.xor` and handle assignment:

```julia
# a ⊻= b  desugars to  a = a ⊻ b  in Julia
# So we return a NEW QBool with the same wire but with a CX applied

function Base.xor(a::QBool, b::QBool)
    @assert a.ctx === b.ctx "Cannot entangle qubits from different contexts"
    push!(a.ctx, CXNode(control=b.wire, target=a.wire, controls=current_controls(a.ctx)))
    return a   # return same object — the mutation happened in the DAG
end
```

### 9.6 Handling `if` on ClassicalRef in tracing mode

In tracing mode, `x::Bool = q` returns a `ClassicalRef`, not a real `Bool`. When the programmer writes `if x ... end`, Julia will call `Bool(x)` on the `ClassicalRef`.

For v0.1 tracing, intercept this by making `ClassicalRef` callable as a boolean, but recording both branches. This requires the `if` to be rewritten as a function-based branch:

```julia
# In tracing mode, the user writes:
#   if x; branch_a; else; branch_b; end
#
# This must be captured. Two approaches:
#
# A) Require the user to use a macro @qif in tracing mode (REJECTED: violates P2)
# B) Use Julia's overloadable ifelse() for simple cases,
#    and require do-block form for complex cases in tracing mode:
#
#    branch(x) do val
#        if val; ...; else; ...; end
#    end
#
# For v0.1: support eager mode fully. Tracing mode supports only
# do-block branching. Document this as a known limitation.
# Full transparent if-interception is a post-v0.1 goal
# (requires Julia compiler plugin or Cassette.jl-style overdubbing).
```

This is the one place where the ideal (transparent `if`) meets implementation reality. Document it honestly. In eager mode, measurement returns a real `Bool` and `if` works natively. In tracing mode, branching requires `branch(x) do val ... end` for v0.1.

---

## 10. Testing Requirements

Every test must be deterministic (seeded RNG) or statistical (run N times, check distribution within tolerance).

### 10.1 Primitive tests

- `QBool(0)` always measures to `false`
- `QBool(1)` always measures to `true`
- `QBool(1/2)` measures to `true` ≈50% of the time (N=10000, tolerance ±3%)
- `q.θ += π` on `QBool(0)` gives `QBool(1)` (i.e. X gate)
- `q.φ += π` on `QBool(1/2)` followed by `q.θ += π/2` gives deterministic outcome (H Z H = X)
- `a ⊻= b` on `(QBool(0), QBool(1))` gives `(QBool(1), QBool(1))`

### 10.2 Entanglement tests

- Bell state: prepare `a=QBool(1/2)`, `b=QBool(0)`, `b ⊻= a`. Measure both. Assert `ra == rb` every time (N=1000).
- GHZ state: 3 qubits. Assert all three measurements equal (N=1000).

### 10.3 Protocol tests

- Teleportation: prepare known state, teleport, verify measurement statistics match original state.
- RUS: run `rus_T!`, verify output state has correct phase (compare to direct T application).

### 10.4 Arithmetic tests

- `QInt{8}(42) + QInt{8}(17)` measures to `59`
- `QInt{8}(200) + QInt{8}(100)` wraps to `44` (mod 256)
- `QInt{8}(10) - QInt{8}(3)` measures to `7`

### 10.5 Tracing tests

- `trace(teleport!)` produces a `Channel` with correct wire counts
- DAG contains expected node types in expected order
- `to_openqasm(trace(teleport!))` produces valid OpenQASM 3.0

### 10.6 Linearity tests

- Using a `QBool` after measurement throws an error
- Attempting to `⊻=` with a consumed qubit throws an error

### 10.7 Density matrix tests

- Bell state prepared via `DensityMatrixContext` gives same measurement statistics as state vector (N=10000, tolerance ±3%)
- Teleportation via density matrix produces correct output state
- Pure state ρ = |ψ⟩⟨ψ| has Tr(ρ²) = 1
- After partial trace of Bell state, reduced state has Tr(ρ²) = 0.5 (maximally mixed)

### 10.8 Noise channel tests

- `depolarise!(q, 0.0)` on pure state leaves state unchanged
- `depolarise!(q, 1.0)` on any state produces maximally mixed state (ρ = I/2)
- `dephase!(q, 1.0)` on |+⟩ produces maximally mixed state
- `dephase!(q, p)` on |0⟩ leaves state unchanged (no off-diagonal to kill)
- `amplitude_damp!(q, 1.0)` on |1⟩ produces |0⟩
- Noise channel on `EagerContext` (state vector) throws clear error message

### 10.9 Classicalise tests

- `classicalise(identity_channel)` produces identity stochastic map
- `classicalise(X_channel)` produces bit-flip stochastic map
- `classicalise(hadamard_channel)` produces uniform stochastic map (both inputs → 50/50 output)
- `classicalise(depolarised_identity)` produces stochastic map with correct diagonal entries

---

## 11. Dependencies

Minimal for v0.1:

```toml
[deps]
# None required for core. State vector sim is pure Julia.

[extras]
Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"
```

No Qiskit. No Cirq. No external quantum frameworks. The point is that Sturm.jl stands alone.

---

## 12. Non-goals and future directions

These are recorded for context but must NOT influence v0.1 design decisions except where P7 (dimension-agnosticism) applies.

- **Qutrit/qudit types**: `QTrit <: QDit{3}`, `QDitInt{D,W} <: QDit{D}`. The type hierarchy and channel algebra must accommodate these without modification.
- **Anyonic systems**: `QAnyon{C<:FusionCategory}` with braiding as the entangling primitive. Requires full compact closed category structure (duals, traces). The `≫` and `⊗` operators must still work; braiding replaces CNOT.
- **Lean 4 verification layer**: prove channel composition preserves CP, deferred measurement equivalence, QECC distance. Generates Julia type definitions with correctness certificates.
- **Hardware compilation**: `compile(ch, target=:ibm_eagle)` maps logical circuit to physical topology with routing and scheduling.
- **Compile-time linearity**: replace runtime `consume!` checks with a macro or compiler plugin that proves linear usage statically.
- **Variational / hybrid algorithms**: classical optimiser loop calling `trace` + `evaluate` repeatedly. The channel representation makes parameter extraction natural.
