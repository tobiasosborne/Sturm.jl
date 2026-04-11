# Sturm.jl

A Julia quantum programming language where **functions are channels**, the **quantum-classical boundary is a type boundary**, **QECC is a higher-order function**, and **any Julia function is a quantum oracle**.

Sturm is not a circuit construction library. It is a quantum programming DSL with exactly four primitives, a type system that makes measurement implicit, library functions that make quantum algorithms disappear into higher-order patterns, and a reversible compiler that turns plain Julia code into quantum circuits automatically.

## Design Principles

These are axioms, not guidelines.

**P1. Functions are channels.** A Julia function with quantum arguments IS a completely positive map. There is no separate "channel" wrapper.

**P2. The quantum-classical boundary is a type boundary.** There is no `measure()` function. Measurement happens when a quantum value is assigned to a classical type:

```julia
result::Bool = q    # measurement happens here, at the type boundary
```

**P3. Operations are operations.** No language-level distinction between unitaries, noise, preparation, or measurement. They are all channels.

**P4. Quantum control is lexical scope.** `when(q) do ... end` = quantum control. `if x ... end` = classical branch. The distinction is enforced by types.

**P5. No gates, no qubits.** The programmer works with registers (`QBool`, `QInt{W}`) and four primitives. Named gates (H, CNOT) are library functions. If your program reads like a circuit diagram, it is wrong.

**P6. QECC is a higher-order function.** Error correction is `Channel -> Channel`. It wraps a function in encoding and decoding. It is not an annotation or pragma.

**P7. The abstraction is dimension-agnostic.** The core must not assume d=2 in a way that forecloses qutrits or anyonic systems.

**P8. Quantum promotion follows Julia's numeric tower.** Classical values auto-promote to quantum when combined with quantum values, just as `Int + Float64 -> Float64`. Initial construction is explicit (`QInt{8}(42)` is like `complex(1)`). Mixed operations promote the classical side.

**P9. Any Julia function is a quantum oracle.** Write a plain Julia function `f(x::Int8) = x^2 + 3x + 1`. Call `oracle(f, x)` where `x` is a `QInt`. The function is compiled to a reversible circuit via [Bennett.jl](https://github.com/tobiasosborne/Bennett.jl) (LLVM IR extraction + Bennett's 1973 construction) and executed on the quantum register. Inside `when()`, it becomes a controlled oracle automatically. No manual circuit construction. No gate decomposition. Just write normal code.

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
    a = QBool(1/2)        # |+>
    b = QBool(0)           # |0>
    b xor= a                # Bell pair: (|00> + |11>)/sqrt(2)

    ra = Bool(a)
    rb = Bool(b)
    @assert ra == rb       # always correlated
end
```

### Teleportation

```julia
function teleport!(q::QBool)::QBool
    a = QBool(1/2)
    b = QBool(0)
    b xor= a               # create Bell pair

    a xor= q               # entangle input with Bell pair
    H!(q)                  # Hadamard (library gate, built from primitives)

    rq = Bool(q)           # type boundary = measurement
    ra = Bool(a)           # type boundary = measurement

    if ra; X!(b); end      # classical correction
    if rq; Z!(b); end
    return b               # teleported qubit
end
```

No circuit diagrams. No qubit indices. No `measure()` calls. The type boundary does the work.

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

`QInt{8}` carries width in the type. Julia specialises on it. The `+` operator is a reversible ripple-carry circuit built entirely from `xor=` and `when()`.

### Quantum Oracles from Plain Julia (P9)

Write normal Julia code. Get quantum circuits.

```julia
# Any pure Julia function:
f(x::Int8) = x^2 + 3x + 1

@context EagerContext() begin
    x = QInt{2}(2)            # 2-bit quantum register
    y = oracle(f, x)          # Bennett compiles f, executes on quantum register
    result = Int(y)            # type boundary = measurement
    @assert result == 3        # (4+6+1) mod 4 = 3
    @assert Int(x) == 2        # input preserved (Bennett keeps inputs intact)
end
```

Controlled oracles — just wrap in `when()`:

```julia
@context EagerContext() begin
    q = QBool(1/2)             # control in superposition
    x = QInt{2}(2)
    when(q) do
        y = oracle(f, x)       # controlled version — automatic
    end
end
```

Pre-compile for reuse across shots (like Enzyme's `gradient`):

```julia
qf = quantum(f)                # compile once, cache the circuit

@context EagerContext() begin
    x = QInt{2}(3)
    y = qf(x)                  # reuses cached circuit — no recompilation
end
```

Resource estimation without execution:

```julia
r = estimate_oracle_resources(f, Int8)
# => (gates=846, toffoli=352, t_count=2464, qubits=264, t_depth=...)
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
    b xor= a
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
# 10700+ tests (including 108 Bennett integration tests)
```

## Project Status

All 12 phases of the [implementation plan](docs/PLAN.md) are structurally complete:

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

See `WORKLOG.md` for detailed session notes and gotchas.

## License

AGPL-3.0
