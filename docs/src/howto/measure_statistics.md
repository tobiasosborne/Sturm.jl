# Getting probabilities out

*A task recipe. Assumes you can already write a small program and run it with
`Sturm.eager(cap) do ctx … end` — see
[your first program](../getting_started/first_program.md).*

Sturm gives you three different tools for "what are the odds?", and they answer
three different questions. Pick from this decision list before reaching for any
of them:

1. **You want a sample** — one run, one outcome, like a real machine.
   → run under `Sturm.eager`, and `Bool(q)` hands you a genuine `Bool`.
2. **You want a distribution by sampling** — many runs, count them.
   → `Sturm.shots(f, capacity; N)`, then count the returned vector yourself.
3. **You want the exact distribution, no sampling error** — one run, real
   numbers. → run under `Sturm.density`, where `Bool(q)` returns a *record
   token*, and read it with `Sturm.record_distribution`.

There is a fourth tool, `Sturm.classicalise`, that looks like it belongs on
this list and does not. It analyses a *channel description*, never a running
program, and it is deliberately blind to phase. It is covered at the bottom so
you can recognise it and walk past it.

`eager`, `density`, `shots`, `record_distribution` and `classicalise` are all
[public but not exported](../explanation/contexts_and_scope.md),
so they are spelled `Sturm.eager`, `Sturm.shots`, and so on — or imported once
with `using Sturm: eager, density, shots`.

---

## 1. One sample, the ordinary way

Under the eager context a measurement cast behaves exactly like a measurement
on hardware: it samples, it collapses the state, and it retires the handle.

```julia
using Sturm

Sturm.eager(1) do ctx
    Bool(QBool(0.5))
end
# => false   (or true — this is one trajectory of a fair coin)
```

That is the whole contract. `QBool(0.5)` prepares a state with Born
probability `0.5` of reading `1`; `Bool(...)` reads it. Ordinary Julia control
flow works on the result, because the result is an ordinary `Bool`.

Seed the context's generator when you want a reproducible trajectory:

```julia
using Sturm, Random

Sturm.eager(1; rng = MersenneTwister(0x5107)) do ctx
    Bool(QBool(0.5))
end
```

## 2. A sampled distribution: `shots`

`Sturm.shots(f, capacity; N = 1000, rng = nothing)` runs `f` in `N` fresh
eager contexts and collects each return value into a vector. It is the only
sanctioned way to build a distribution out of scalar outcomes.

```julia
using Sturm, Random

outs = Sturm.shots(1; N = 2000, rng = MersenneTwister(0x5107)) do ctx
    Bool(QBool(0.25))
end

typeof(outs)              # => Vector{Bool}
length(outs)              # => 2000
count(outs) / length(outs)  # => 0.2465   (true value 0.25)
```

**There is no histogram helper.** You compute the statistic yourself —
`count(outs)/N`, `sum(outs)/N`, `[count(==(v), outs) for v in 0:7]`. That is
deliberate: the return of `f` is whatever you wrote, so Sturm has no idea what
"the" statistic is.

`shots` is also how you check a correlation rather than a marginal. Return the
comparison, not the values:

```julia
using Sturm, Random

outs = Sturm.shots(2; N = 1000, rng = MersenneTwister(7)) do ctx
    b = QBool(0.5)        # a fair quantum coin
    c = false ⊻ b         # xor into a fresh false: an entangled pair
    Bool(b) == Bool(c)
end
count(outs) / length(outs)   # => 1.0   (perfectly correlated, every shot)
```

Anything you can measure, you can put in the return value — a tuple, an `Int`
from `Int(x)`, a derived `Bool`.

```julia
using Sturm, Random

outs = Sturm.shots(3; N = 800, rng = MersenneTwister(11)) do ctx
    x = QInt{3}(0)
    superpose!(x)          # H on every wire: the uniform superposition
    Int(x)
end
sort(unique(outs))         # => [0, 1, 2, 3, 4, 5, 6, 7]
```

### Sizing `capacity`

The first argument to `shots` (and to `eager`/`density`) is a **qubit count**,
and it sets the memory footprint. An eager context is a flat `2^capacity`
vector of `ComplexF64`, so 16 bytes per amplitude: `capacity = 20` is 16 MiB,
`capacity = 26` is 1 GiB, `capacity = 30` is about 16 GiB. A density context
stores the full matrix, `2^(2·capacity)` entries, so its ceiling is roughly
half the qubit count for the same RAM.

Count generously but not wildly: the capacity has to cover every wire your
program allocates *including scratch it never shows you* — an
[`oracle`](write_oracles.md) call in particular can need a dozen ancillas.
Running out is a loud error, never a wrong answer:

```
context capacity (8 wires) exceeded — grow the `eager(cap)`/`density(cap)` capacity
```

## 3. The exact distribution: `record_distribution` on a density context

Under `Sturm.density`, `Bool(q)` does *not* return a `Bool`. It returns a
**record token** — a handle naming an already-measured, still-live classical
record. This is not an inconsistency: a density-matrix context executes the
channel, and a channel has no single outcome to hand back.

```julia
using Sturm

Sturm.density(1) do ctx
    typeof(Bool(QBool(0.5)))
end
# => Sturm.ClassicalBit{Sturm.DensityMatrixContext}
```

`Sturm.record_distribution(t)` reads that token's outcome probabilities
straight off the density matrix. Exact, no sampling, and **no backaction** —
you may call it as often as you like:

```julia
using Sturm

Sturm.density(2) do ctx
    u = QBool(0.3)
    m = Bool(u)                     # a record token, not a Bool
    Sturm.record_distribution(m)
end
# => [0.7000000000000001, 0.29999999999999993]
```

```julia
using Sturm

Sturm.density(2) do ctx
    u = QBool(0.3)
    m  = Bool(u)
    ρ0 = Sturm.density_matrix(ctx)
    d1 = Sturm.record_distribution(m)
    d2 = Sturm.record_distribution(m)
    (d1 == d2, Sturm.density_matrix(ctx) == ρ0)
end
# => (true, true)   -- repeatable, and the state is bitwise unchanged
```

Branch on a token with [`cases`](../explanation/seven_constructs.md),
never a host `if`. Then read the corrected register's distribution the same
way:

```julia
using Sturm

Sturm.density(3) do ctx
    m = Bool(QBool(0.5))
    a = QBool(false)
    cases(m) do
        not!(a)
    end
    Sturm.record_distribution(Bool(a))
end
# => [0.4999999999999999, 0.5000000000000001]
```

### When to use which

| You want | Context | Call | Exact or sampled |
|---|---|---|---|
| one outcome, feed-forward control flow | `eager` | `Bool(q)` | one trajectory |
| a distribution over program outputs | `eager` | `Sturm.shots(f, cap; N)` | sampled, error `~1/√N` |
| a distribution over one measurement record | `density` | `Sturm.record_distribution(m)` | **exact** |
| the whole state, for a test | `eager` / `density` | `Sturm.statevector(ctx)` / `Sturm.density_matrix(ctx)` | exact |

`statevector`/`density_matrix` return a **copy** and exist for tests and
inspection, not for algorithms:

```julia
using Sturm

Sturm.eager(1) do ctx
    q = plus()
    Sturm.statevector(ctx)
end
# => ComplexF64[0.7071067811865475 + 0.0im, 0.7071067811865476 + 0.0im]
```

```julia
using Sturm

Sturm.density(1) do ctx
    q = QBool(0.25)
    Sturm.density_matrix(ctx)
end
# => ComplexF64[0.7499999999999999+0.0im  0.4330127018922193-0.0im
#               0.4330127018922193+0.0im  0.25+0.0im]
```

Note the off-diagonal entries: that is coherence, and it is exactly what a
probability table cannot show you. See
[why marginals lie](../explanation/functions_are_channels.md).

## 4. What `classicalise` is (and is not)

`Sturm.classicalise(g)` takes a **channel value or a traced program**, never a
live run, and returns the column-stochastic matrix
`M[i+1, j+1] = probability of reading i given input basis state j`.

```julia
using Sturm

Sturm.classicalise(Sturm.bit_flip(0.25))
# => [0.7499999999999999  0.25
#     0.25                0.7499999999999999]
```

It is **deliberately phase-blind**, and that is not a limitation to work
around — it is what a classical shadow means:

```julia
using Sturm

Sturm.classicalise(Sturm.channel(Sturm.I2))   # => [1.0 0.0; 0.0 1.0]
Sturm.classicalise(Sturm.channel(Sturm.Z))    # => [1.0 0.0; 0.0 1.0]
```

The identity and a phase flip have the same classical shadow. So
`classicalise` is never a channel-equivalence test — for that you want
`Sturm.same_channel`, and even that has a sharp edge described in
[phase discipline](../explanation/phase_discipline.md).

It is capped at three wires, loudly:

```
ArgumentError: classicalise: 4 wires exceeds CLASSICALISE_MAXWIRES = 3
```

## Gotchas

- **`record_distribution` on an eager `Bool` is a `MethodError`, on purpose.**
  There is no token to introspect: the scalar already *is* the answer, and
  there is no distribution left to read.

  ```
  MethodError: no method matching record_distribution(::Bool)
  Closest candidates are:
    record_distribution(::Sturm.ClassicalToken)
  ```

- **`record_distribution` on a traced program throws.** Under the tracing
  context nothing has executed, so the record is symbolic:

  ```
  ArgumentError: record_distribution: a Tracing token is SYMBOLIC — a trace-time
  record has no distribution (the compiler context executes nothing).
  Introspect on the DM context, or `shots` on Eager.
  ```

- **`if m` on a density-context token is a Julia `TypeError`**, not a Sturm
  error and not silently wrong:

  ```
  TypeError: non-boolean (Sturm.ClassicalBit{Sturm.DensityMatrixContext}) used in boolean context
  ```

  Use [`cases`](../explanation/seven_constructs.md)
  to branch and `Sturm.select` to pick a value.

- **A measurement cast consumes its handle.** Reading twice is an error, in
  every context:

  ```
  register WireID(1) already consumed — a measurement cast consumes its input;
  a live handle to measured (now classical) data is a type lie, and you cannot
  read it again
  ```

- **Noise needs a density context.** Applying a noise channel under `eager`
  refuses rather than approximating:

  ```
  apply!: a statevector cannot hold the mixed state a noise channel produces.
  Choose explicitly: density(cap) executes the exact channel in one run;
  shots(…) samples trajectories; stinespring=true dilates + traces — ONE
  quantum-jump unravelling per run, NOT the channel.
  ```

- **Statistics are not a correctness proof.** A program can have perfect
  measurement statistics in one basis and be badly wrong — that is
  [the whole point of the channel-level story](../explanation/functions_are_channels.md).

## Where next

- [Choosing a context](../getting_started/choosing_a_context.md) — the fuller
  eager / density / tracing decision.
- [Contexts and scope](../explanation/contexts_and_scope.md) — why the same
  program means three different things.
- [Common gotchas](../explanation/gotchas.md) — symptom → why → fix.
- [Reference: contexts](../reference/contexts.md) — every docstring.
