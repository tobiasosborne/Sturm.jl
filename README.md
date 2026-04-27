# Sturm.jl

A Julia quantum programming language where **functions are channels**, the **quantum-classical boundary is a type boundary**, **QECC is a higher-order function**, and **any Julia function is a quantum oracle**.

Sturm is not a circuit construction library. It is a quantum programming DSL with exactly four primitives, a type system that makes measurement implicit, library functions that make quantum algorithms disappear into higher-order patterns, and a reversible compiler that turns plain Julia code into quantum circuits automatically.

## Design Principles

These are axioms, not guidelines.

**P1. Functions are channels.** A Julia function with quantum arguments IS a completely positive map. There is no separate "channel" wrapper.

**P2. The quantum-classical boundary is a *cast*, like `Float64 → Int64`.** There is no `measure()` function. Measurement is what happens when a quantum value is cast to a classical type — with implied information loss, exactly as truncating a float loses the fractional part:

```julia
result = Bool(q)        # explicit cast: measurement
q = QBool(result)       # explicit cast: preparation
```

Because the cast loses information irreversibly, the compiler emits a **warning on implicit casts** — `x::Bool = q` without an explicit cast expression is flagged, just like implicit float-to-int truncation is flagged in sensible languages. The fix is always the same: wrap the RHS in an explicit cast. Information loss must be intentional.

The warning fires once per source location. For tight loops where the intent is unambiguous, wrap the block in `with_silent_casts(() -> ...)` to suppress within the current task.

**P3. Operations are operations.** No language-level distinction between unitaries, noise, preparation, or measurement. They are all channels.

**P4. Quantum control is lexical scope.** `when(q) do ... end` = quantum control. `if x ... end` = classical branch. The distinction is enforced by types — `if q::QBool` never auto-lifts to `when(q)` (see *if vs when* below for the three reasons).

**P5. No gates, no qubits.** The programmer works with registers (`QBool`, `QInt{W}`) and four primitives. Named gates (H, CNOT) are library functions. If your program reads like a circuit diagram, it is wrong.

**P6. QECC is a higher-order function.** Error correction is `Channel -> Channel`. It wraps a function in encoding and decoding. It is not an annotation or pragma.

**P7. The abstraction is dimension-agnostic across the entire Hilbert spectrum.** The core must extend *without modification* to: finite qudits (qutrits d=3, arbitrary `QDit{D}`), **anyons** (fusion categories, non-abelian braiding as a primitive), and — critically — **infinite-dimensional systems**. At minimum, Gaussian CV for quantum optics (bosonic modes, displacement, squeezing, beamsplitters, homodyne). Ideally, arbitrary infinite-d: Fock-space arithmetic, bosonic codes (cat, binomial, GKP), continuous-variable oracles. If any of these forces a change to the channel algebra, tracing infrastructure, or the P2 cast / P8 promotion rules, the abstraction is wrong.

**P8. Quantum promotion follows Julia's numeric tower.** Classical values auto-promote to quantum when combined with quantum values, just as `Int + Float64 -> Float64`. Initial construction is explicit (`QInt{8}(42)` is like `complex(1)`). Mixed operations promote the classical side.

**P9. Quantum registers are a numeric type for dispatch.** A plain Julia function works on a quantum argument exactly the way it works on `Float64` or `Complex` — via operator overloading, not via magic:

```julia
f(x) = x^2 + 3x + 1
f(5)              # Int      — works
f(5.0)            # Float64  — works (Float64's `*`, `+` are defined)
f(1 + 2im)        # Complex  — works (Complex's `*`, `+` are defined)
f(QInt{8}(5))     # quantum  — works (QInt's `*`, `+` are defined, P8)
```

Type-restricted methods wall out other types — quantum included, just like Float:

```julia
g(x::Int) = x^2 + 3x + 1
g(5.0)            # MethodError — Int-typed method does not match Float64
g(QInt{8}(5))     # MethodError — same rule, same reason
```

A catch-all that secretly routed `g(q)` through Bennett would lie about the type contract — Julia rightly forbids overriding `Base.Function`, and so does Sturm. For type-restricted classical functions the bridge is explicit: [`oracle(f, q)`](https://github.com/tobiasosborne/Bennett.jl) compiles the LLVM IR to a reversible circuit, and the opt-in macro `@quantum_lift` adds a specific `f(::QInt{W})` method so that `f(q)` works at the call site. `quantum(f)` pre-compiles once for reuse, the same pattern as `Enzyme.gradient(f)`. Inside `when()`, every path auto-controls via the existing control stack. The autodiff analogy is exact: our P8 + generic path is `ForwardDiff.Dual`; our `oracle` / `@quantum_lift` / `quantum` is `Enzyme.gradient`. Neither adds a catch-all on `Function`; neither needs to.

## The Four Primitives

Everything in Sturm is built from exactly four operations:

| # | Syntax | What it does | QASM equivalent |
|---|--------|-------------|-----------------|
| 1 | `QBool(p)` | Prepare qubit with P(\|1>) = p | `ry(2*asin(sqrt(p))) q` |
| 2 | `q.theta += d` | Amplitude rotation Ry(d) | `ry(d) q` |
| 3 | `q.phi += d` | Phase rotation Rz(d) | `rz(d) q` |
| 4 | `a xor= b` | CNOT (b controls, a target) | `cx b, a` |

Every gate, every algorithm, every error-correcting code is derived from these four.

## Examples

### Bell State

```julia
using Sturm

@context EagerContext() begin
    a = QBool(1/2)              # |+>
    b = QBool(0)                # |0>
    when(a) do                  # Bell pair: (|00> + |11>)/sqrt(2)
        X!(b)                   # b is flipped exactly when a is |1>
    end

    ra = Bool(a)
    rb = Bool(b)
    @assert ra == rb            # always correlated
end
```

There is no CNOT gate. There is a control structure (`when`) and a flip operation (`X!`). The same channel that a circuit diagram would label "CNOT" is composed at the language level from a *lexical scope* and an *unconditional flip*. CNOT is what you call this channel when you read it back as a diagram, not what you write to compose it.

### Teleportation

```julia
function teleport!(q::QBool)::QBool
    a = QBool(1/2)
    b = QBool(0)
    when(a) do; X!(b); end       # create Bell pair

    when(q) do; X!(a); end       # entangle input with Bell pair
    H!(q)                        # Hadamard (library gate, built from primitives)

    rq = Bool(q)                 # type boundary = measurement
    ra = Bool(a)                 # type boundary = measurement

    if ra; X!(b); end            # classical correction (post-measurement Bool)
    if rq; Z!(b); end
    return b                     # teleported qubit
end
```

No circuit diagrams. No qubit indices. No `measure()` calls. No named two-qubit gates. The type boundary handles measurement; `when` handles control; the rest is unconditional single-qubit operations.

### Quantum Arithmetic

```julia
@context EagerContext() begin
    a = QInt{8}(42)
    b = QInt{8}(17)
    s = a + b              # quantum ripple-carry adder

    result = Int(s)        # type boundary = measurement
    @assert result == 59
end
```

`QInt{8}` carries width in the type. Julia specialises on it. The `+` operator is a reversible ripple-carry circuit composed from `when()` and the rotation primitives — no two-qubit gates are imported.

### Quantum Oracles from Plain Julia (P9)

Julia's dispatch treats quantum registers as a numeric type. Generic functions work automatically through P8 operator overloads; type-restricted ones lift explicitly through Bennett.

**Generic functions just work** — same as `Float64` or `Complex`:

```julia
f(x) = x + 1     # generic — no type annotation

f(5)             # 6
f(5.0)           # 6.0
f(QInt{2}(3))    # QInt holding (3+1) mod 4 = 0  (via Base.:+(::QInt, ::Int))
```

**Type-restricted functions lift explicitly** — `oracle(f, q)` routes `f` through [Bennett.jl](https://github.com/tobiasosborne/Bennett.jl), which extracts LLVM IR and synthesises a reversible circuit. A cost-model dispatcher picks the cheapest sound strategy:

```julia
f(x::Int8) = x^2 + 3x + 1     # typed Int8 → walls out Float64 AND QInt{W}

estimate_oracle_resources(f, Int8; bit_width=2)
# → (gates=26, toffoli=6, t_count=42, qubits=9, t_depth=...)   # :auto → :tabulate
```

Nine qubits for a polynomial with two multiplies, because Bennett's `:auto` flipped to **`:tabulate`** — at `W ≤ 4` with a multiplicative IR, evaluating `f` classically on all `2^W` inputs and emitting the result via Babbush-Gidney QROM is strictly cheaper than symbolic lowering. The alternative is `:expression`, which compiles the LLVM IR in full:

```julia
estimate_oracle_resources(f, Int8; bit_width=2, strategy=:expression)
# → (gates=126, toffoli=36, t_count=252, qubits=43, t_depth=14)
```

43 wires and 13 over Orkan's 30-qubit statevector cap — the forward+copy+uncompute pattern holds every SSA intermediate live simultaneously. For pure additive functions the dispatcher keeps `:expression` with ripple-carry because tabulation would cost more than the symbolic path; it only flips to `:tabulate` when the cost model favours it. When `:auto` does pick `:expression`, adder/multiplier choice is controlled orthogonally (`add=:qcla`, `mul=:qcla_tree`, …).

**When the cost model can't help**: `W > 4`, impure functions, or anything `:auto` routes to `:expression` on a register Orkan can't hold. Decompose the call into smaller oracles — Bennett guarantees its ancillae are at `|0⟩` on return and Sturm recycles them:

```julia
@context EagerContext() begin
    x      = QInt{2}(2)
    xsq    = oracle(y -> y * y, x)     # peak 19 wires, ancillae freed on return
    threex = oracle(y -> 3y, x)        # peak 23 wires, reuses freed slots
    y      = xsq + threex + QInt{2}(1) # native P8 ripple-carry stitches the chain
    @assert Int(y) == 3                # (4+6+1) mod 4 = 3
    @assert Int(x) == 2                # input preserved
end
```

Automatic IR-level decomposition for cases the dispatcher can't cover is tracked as Sturm beads `Sturm.jl-16l` (auto-pass on the LLVM IR) and `Sturm.jl-25u` (opt-in `oracle(f, q; decompose=true)` kwarg).

There is no catch-all on `Base.Function`: Julia forbids it, and it would lie about the type contract — just as `f(::Int)` does not silently accept `Float64`. For typed functions the user wants to feel implicit, the opt-in sugar is `@quantum_lift`, which adds a specific `f(::QInt{W})` method so `f(q)` works directly at the call site (tracked under the `k3m` bead).

Controlled oracles — just wrap in `when()`:

```julia
sq(x::Int8) = x * x            # 19 wires at W=2 — fits a single oracle call

@context EagerContext() begin
    q = QBool(1/2)             # control in superposition
    x = QInt{2}(2)
    when(q) do
        y = oracle(sq, x)      # controlled version — automatic
    end
end
```

Pre-compile for reuse across shots (like Enzyme's `gradient`):

```julia
qsq = quantum(sq)              # compile once, cache the circuit

@context EagerContext() begin
    x = QInt{2}(3)
    y = qsq(x)                 # reuses cached circuit — no recompilation
end
```

Resource estimation without execution — useful for comparing Bennett strategies:

```julia
estimate_oracle_resources(f, Int8; bit_width=2)                              # :auto
# → (gates=26,  toffoli=6,  t_count=42,  qubits=9,  t_depth=...)   # picks :tabulate

estimate_oracle_resources(f, Int8; bit_width=2, strategy=:expression)        # LLVM-native
# → (gates=126, toffoli=36, t_count=252, qubits=43, t_depth=14)

estimate_oracle_resources(f, Int8; bit_width=2, strategy=:expression, mul=:qcla_tree)
# → (gates=282, toffoli=80, t_count=..., qubits=63, t_depth=...)   # shallower but wider
```

### Quantum Promotion (P8)

Classical values auto-promote when combined with quantum values — same as Julia's numeric tower:

```julia
@context EagerContext() begin
    a = QInt{8}(42)        # explicit construction, like complex(1)
    s = a + 17             # 17 auto-promotes to QInt{8}(17)
    t = 5 + a              # commutative

    q = QBool(0.0)
    q ⊻= true              # classical true → X gate (no qubit allocated)

    result = Int(s)        # type boundary = measurement
    @assert result == 59
end
```

### `if` vs `when` (P4)

`if` is classical. `when` is quantum. The two are distinct channels — not sugar for each other. `if q::QBool` never auto-lifts to coherent control:

```julia
@context EagerContext() begin
    q = QBool(1/2)                # quantum bit in superposition
    t = QBool(0)

    # ── Coherent quantum control: the only way to get controlled-X ─────────
    when(q) do
        t.θ += π                   # q=|0⟩ branch: t unchanged
    end                             # q=|1⟩ branch: t flipped; q and t remain entangled

    # ── Post-measurement classical branch: q collapses, entanglement is gone
    s = QBool(1/2)
    u = QBool(0)
    if Bool(s)                     # explicit measurement cast — P2
        u.θ += π                   # classical `if`: branch on the measured bit
    end                             # s is now a classical outcome; no superposition
end
```

`if q` without `Bool(...)` emits the P2 implicit-cast warning and then behaves as `if Bool(q)` — measurement, then classical branch. It does NOT silently become `when(q)`.

**Why not auto-lift `if q` to `when(q)`?** Three reasons:

1. **Two distinct channels, one syntax would be a type lie.** `when(q)` entangles target with control across both branches. `if Bool(q)` measures, destroys superposition, branches on the outcome. A user who writes `if q ...` without thinking about which one they want should not silently get either — they should get the P2 warning, same discipline as implicit float-to-int truncation.

2. **It breaks composition with `oracle(f, q)`.** If `f(x::Int) = (x > 0) ? x+1 : x-1` contains an `if`, Bennett compiles that `if` as an **in-circuit reversible branch** (Toffoli-guarded writes) when you call `oracle(f, q)`. That is a third distinct semantics. Auto-lifting `if q` would mean the exact same `if` in user source means three different things — classical branch, post-measurement branch, or reversible branch — depending on whether the enclosing function is called classically, cast-then-branched, or lifted as an oracle. The user cannot tell from the source which is happening.

3. **It's not Julia-idiomatic.** Julia's `if x` is defined on `x::Bool`. Types that want a boolean reading define `Base.Bool(::T)`, and `if x` becomes `if Bool(x)`. For `QBool`, `Bool(q)` is measurement — P2. `if q` with no overload already does the honest thing. The ForwardDiff.jl analogue is exact: `if x > 0` on a `Dual` also measures-then-branches (strips the dual); autodiff-safe code uses `ifelse` or similar branchless primitives. Sturm's `when` is the branchless-coherent primitive; `if` is the measure-then-branch one. Both have their place; one syntactic form may not mean both.

### Classical control on a measurement outcome

For real execution — `EagerContext`, `DensityMatrixContext`, `HardwareContext` — the natural pattern just works:

```julia
@context HardwareContext(transport) begin
    ancilla = QBool(1.0); target = QBool(0)
    if Bool(ancilla)            # ← round-trip to device: measure, await, return Bool
        X!(target)              # ← plain Julia branch on the classical result
    end
    @assert Bool(target)
end
```

`Bool(q)` is the P2 cast — measurement. On `HardwareContext` it flushes pending ops, blocks on the device response, returns the classical Bool. The `if` is plain Julia. This is exactly the dynamic-circuit pattern IBM/Quantinuum hardware supports, exposed at zero ceremony.

`Int(q::QInt)` does the same for multi-bit registers (one round-trip per bit currently; batched all-bits-in-one-round-trip is a follow-on). Use `if`, `switch`, `while` over the result freely — it's a regular Julia value.

**The footgun is `TracingContext` only**, because tracing runs the function once symbolically and Julia's `if` is opaque to runtime tracing — there's no way to capture both arms without source-level rewriting (Cassette/IRTools, which the Julia DSL ecosystem has moved away from). For the symbolic-tracing path (building a `Channel` for OpenQASM export, or feeding the optimisation passes), use the explicit primitive **`cases()`** / **`@cases`**:

```julia
ch = trace(1) do q
    target = QBool(0)
    cases(q, () -> X!(target))    # both branches captured into a CasesNode
    target
end
# trace() auto-lowers via Nielsen-Chuang deferred measurement →
# controlled gates from the measurement wire. ch.dag has no CasesNode left.
```

Macro form with two `begin` blocks (Julia doesn't support chained `do` blocks):

```julia
@cases q begin
    X!(target)        # then-branch (measurement = 1)
end begin
    Z!(target)        # else-branch (measurement = 0, optional)
end
```

| Context | `if Bool(q) … end` | `cases(q, then, else_)` |
|---------|--------------------|--------------------------|
| `EagerContext` | ✓ measure + classical branch | ✓ same effect |
| `HardwareContext` | ✓ **round-trip + classical branch** | ✓ same effect |
| `DensityMatrixContext` | ✓ sampled measure + classical branch | ✓ same effect |
| `TracingContext` | ✗ errors loudly (silent mis-trace footgun) | ✓ captures both branches into `CasesNode` |

For tracing-only "record a measurement without classical branching" (e.g., to get `c[0] = measure q[0];` in OpenQASM output), use the empty form `cases(q, () -> nothing)`.

This gives **three distinct channels with three distinct syntactic forms** — `if` is post-measurement classical, `when` is coherent control, `cases` is mid-circuit measurement with traced classical-conditioned operations. The 1:1 OpenQASM 3 lowering target for `cases` is `if (c[i] == 1) { … } [else { … }]` (matches Qiskit-new `with circuit.if_test(...)`, Q# `if M(q) == One`, MQT `IfElseOperation`).

### Resource lifetime: scope, not `free()` (corollary of P1 + P5)

A QBool is a Julia object. When it leaves scope, what happens?

In channel theory the answer is **partial trace** — the unique completely-positive map that "forgets" a subsystem. There is no `malloc`/`free` for qubits; partial trace IS the cleanup operation, mathematically. The questions are (a) what to call it in code and (b) when to invoke it.

Sturm follows Julia's resource-management idiom, not C's. Julia has two patterns and Sturm uses both:

- **GC for transient objects** — you don't `close()` a temporary array; the runtime reclaims it. Translated: a `QBool` allocated inside `@context EagerContext() begin … end` is partial-traced at block exit, the same way `lock(l) do … end` releases the lock at exit. You write no manual cleanup.
- **`do`-block for short explicit lifetimes** — mirrors `open(f, path) do stream … end`. Translated: `QBool(p) do q … end` partial-traces `q` at the do-block exit, even on exception.

```julia
# Idiomatic — qubits live for the @context block, no manual cleanup
@context EagerContext() begin
    a = QBool(1/2); b = QBool(0)
    when(a) do; X!(b); end
    Bool(b)
    # a auto-partial-traced at `end`
end

# Do-block — explicit short lifetime, exception-safe
QBool(0.5) do q
    H!(q)
    Bool(q)
    # q partial-traced here regardless of how the block exits
end
```

The channel-theoretic name for the explicit primitive is **`ptrace!(q)`** (partial trace) — used when scope-driven cleanup doesn't fit (e.g., a qubit must die mid-scope to free a slot for re-allocation on a capacity-bounded device). It should be rare in idiomatic code.

**Why not `discard!`?** The old spelling `discard!(q)` is unidiomatic on four axes: (a) it speaks C-style resource-management vocabulary in user-facing code (P5 violation in spirit — Sturm shouldn't expose wire/resource concepts to users); (b) the bang-convention is wrong, since the qubit is **destroyed**, not mutated; (c) the name is silent on the physics — the operation IS partial trace and should be named for that; (d) requiring users to call it explicitly was the footgun behind bead `Sturm.jl-hlk` (forgotten `discard!` leaks slots until `MAX_QUBITS` errors). `discard!` remains as a zero-overhead `const` alias for backcompat; prefer `ptrace!`.

**Current shipped state**: `@context` auto-partial-traces unconsumed resources at block exit (bead `Sturm.jl-sv3` ✓). `ptrace!` is the canonical explicit primitive (bead `Sturm.jl-diy` ✓); `discard!` aliases to it. `QBool(p) do q … end` and `QInt{W}(value) do reg … end` do-block allocation are now supported (bead `Sturm.jl-cbl` ✓) — partial-trace fires at block exit on either normal return or exception, and is suppressed if the body explicitly consumes the resource via `Bool(q)` / `Int(reg)` / `ptrace!`.

The overall design target: **users don't write resource-cleanup primitives.** Quantum mechanics doesn't change the Julia resource-management story; partial trace is what GC means for qubits.

### Deutsch-Jozsa in One Line

```julia
@context EagerContext() begin
    # The programmer writes domain logic (the oracle):
    function my_oracle!(x::QInt{3})
        b = x[3]           # MSB
        Z!(b)              # flip phase when MSB = 1
    end

    # Deutsch-Jozsa is a library call, not a hand-written circuit:
    outcome = fourier_sample(my_oracle!, Val(3))
    @assert outcome != 0   # balanced oracle -> always nonzero
end
```

The programmer never touched a superposition, never interfered, never measured manually. `fourier_sample` is a higher-order channel that handles the quantum mechanics.

### Phase Estimation

```julia
@context EagerContext() begin
    eigenstate = QBool(1)  # |1> is eigenstate of Z
    result = phase_estimate(Z!, eigenstate, Val(3))
    phase = result / 2^3   # 2/8 = 0.25
end
```

### Noise Channels

Noise is just another operation. No special syntax:

```julia
@context DensityMatrixContext() begin
    q = QBool(1/2)         # |+> as density matrix
    depolarise!(q, 0.1)    # 10% depolarising noise
    result = Bool(q)       # type boundary, same as always
end
```

### Tracing and OpenQASM Export

```julia
ch = trace(2) do a, b
    H!(a)
    when(a) do; X!(b); end
    (a, b)
end
# ch is a Channel{2,2}: the Bell state circuit as data

qasm = to_openqasm(ch)     # export to OpenQASM 3.0
println(qasm)
```

### Channel Composition

```julia
h_gate = trace(1) do q; H!(q); q; end
double_h = h_gate >> h_gate    # sequential: H . H = I
parallel = h_gate tensor h_gate  # parallel: H on two independent qubits
```

### Error Correction

```julia
@context EagerContext() begin
    q = QBool(0)
    physical = encode!(Steane(), q)   # 1 logical -> 7 physical qubits
    # ... noise happens ...
    recovered = decode!(Steane(), physical)  # 7 physical -> 1 logical
    @assert Bool(recovered) == false
end
```

### Visualization

Two complementary renderers are built in, both reading straight from the `Channel` DAG:

**Terminal (`to_ascii` / `Base.show`)** — Unicode box-drawing with opt-in ANSI colour. At the REPL just evaluate a `Channel`:

```julia
julia> ch = trace(2) do a, b; H!(a); when(a) do; X!(b); end; (a, b); end
q0: ─Z──Ry(π/2)──●─
                 │
q1: ─────────────⊕─
```

Set `IOContext(io, :color => true)` to colour gates green, controls/targets yellow, measurement red; `:unicode => false` for pure ASCII; `:compact => true` for dense Level-A packing (QFT-8 goes from 336 to 196 chars).

**Pixel-art PNG (`to_png`)** — 1 pixel per wire, 3 pixels per column, colours from the [Birren industrial safety palette](https://en.wikipedia.org/wiki/Faber_Birren). Scales to thousand-wire circuits where terminals and LaTeX give up.

```julia
to_png(ch, "bell.png")                                   # seafoam wires, red measurement
to_png(ch, "bell.png"; scheme=:birren_light)             # dark-on-beige
to_png(qft_256, "qft256.png"; column_width=3)            # 511×2310 px, 887 KB
```

A `to_png` on a 1000-wire GHZ cascade finishes in ~70 ms and writes a 42 KB PNG. Control pixel colour matches the wire by default; target uses its RGB complement; overpass connectors show a darkened-wire "shadow" flanking the vertical line only on uninvolved wires. The default `compact=true` uses Level-A ASAP scheduling, so QFT renders at textbook O(n) depth.

See `examples/` for `bell.png`, `ghz8.png`, `steane_encode.png`, `teleport.png`, `qft{16,32,64,256}.png`, `ghz1000.png`.

### Classicalise: Higher-Order Type Boundary

Just as `Bool(q)` decoheres a quantum state, `classicalise(f)` decoheres a quantum channel into a classical stochastic map:

```julia
M = classicalise(X!)
# M = [0 1; 1 0] -- the classical bit-flip matrix

M = classicalise(H!)
# M = [0.5 0.5; 0.5 0.5] -- uniform: H decoheres to a fair coin
```

## Backend

Sturm.jl delegates all linear algebra to [Orkan](https://github.com/tobiasosborne/orkan), a C17 statevector and density matrix simulator with OpenMP parallelism. Classical function compilation is handled by [Bennett.jl](https://github.com/tobiasosborne/Bennett.jl), which extracts LLVM IR from plain Julia functions and compiles them to reversible circuits via Bennett's 1973 construction. Julia owns the type system, DSL, compilation, and channel algebra. Orkan owns the state vectors. Bennett.jl owns the classical-to-reversible compilation.

Bennett.jl v0.4 auto-dispatches four memory strategies per allocation site — Sturm oracles inherit them transparently:

| Strategy | When it fires | Cost | Reference |
|----------|--------------|------|-----------|
| Shadow | static index | 3W CNOT / W CNOT per op | Enzyme-adapted (Moses & Churavy 2020) |
| MUX EXCH | dynamic index | 7k–14k gates | — |
| QROM | read-only constant tables | 4(L−1) Toffoli, W-independent | Babbush-Gidney 2018 |
| Feistel hash | bijective key hash | 8W Toffoli | Luby-Rackoff 1988 |

Any pure Julia function handed to `oracle(f, x)` picks the cheapest correct lowering for every `store`/`load` — so a 4-entry `UInt8` table lookup compiles to 118 gates via QROM instead of ~7 500 via MUX fallback. Mutable state (`Ref`, mutable arrays, `NTuple`) and full IEEE 754 `Float64` (branchless soft-float) also compile without source changes.

Three backends share the same DSL interface:

| Backend | State | Use case |
|---------|-------|----------|
| `EagerContext` | Statevector | Fast simulation, default |
| `DensityMatrixContext` | Density matrix | Noise channels, mixed states |
| `TracingContext` | DAG | Circuit capture, optimisation, export |

## Install

```julia
# Requires Orkan built as a shared library
julia> ] add https://github.com/tobiasosborne/Sturm.jl
```

## Test

```bash
julia --project -e 'using Pkg; Pkg.test()'
# 10800+ tests (108 Bennett integration, 74 pixel renderer, 53 ASCII drawer)
```

## Project Status

All 16 phases of the [implementation plan](docs/PLAN.md) are structurally complete:

| Phase | What | Status |
|-------|------|--------|
| 1-5 | Orkan FFI, core types, QBool, gates, contexts | Complete |
| 6 | QInt{W}, quantum arithmetic | Complete |
| 7 | QFT, fourier_sample, phase_estimate | Complete |
| 8 | TracingContext, Channel, OpenQASM export | Complete |
| 9 | Gate cancellation, deferred measurement | Complete |
| 10 | DensityMatrixContext | Complete |
| 11 | Noise channels, classicalise | Complete |
| 12 | QECC (Steane [[7,1,3]]) | Complete (encoding circuit needs verification) |
| 13 | Trotter-Suzuki simulation (evolve!, ising, heisenberg) | Complete |
| 14 | P8 quantum promotion (mixed-type arithmetic) | Complete |
| 15 | P9 Bennett.jl integration (`oracle`, `quantum`) | Complete |
| 16 | Visualization (`to_ascii`, `to_png`, Birren palette) | Complete |

Additional shipped features beyond the original plan:

| What | Notes |
|------|-------|
| `HardwareContext` + transport (TCP/IPC) + idealised simulator | Dynamic-circuit pattern (mid-circuit measurement → classical branch) works on `HardwareContext` |
| `cases(q, then, [else_])` / `@cases q begin … end` | Mid-circuit measurement primitive for `TracingContext`; `if Bool(q)` is the natural form on Eager / Density / Hardware |
| `compact_state!` for `EagerContext` and `DensityMatrixContext` | Reclaims the n_qubits ratchet after Bennett ancilla bursts; auto-triggered from `deallocate!` |
| `QBool(p) do q … end` and `QInt{W}(value) do reg … end` | Do-block allocators with auto partial-trace on exit (mirrors Julia's `open(f, path) do …`) |
| `STURM_COMPACT_VERIFY` env-gate | Opt out of the `compact_state!` residual scan in hot paths |
| `oracle_table` LRU cache + `clear_oracle_cache!` / `set_oracle_cache_size!` | Bounded cache (default 64); public management API |
| Shor's algorithm impls A/B/C/D/D-semi + windowed arithmetic | Beauregard 2L+4 HWM; Gidney-Ekerå mulmod |
| QSVT / QSP block-encoding primitives | Pillar 4 quantum linear algebra scaffolding |

See `WORKLOG.md` for detailed session notes and gotchas.

## License

AGPL-3.0
