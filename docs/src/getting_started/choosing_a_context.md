# Choosing a context

*Every Sturm program runs inside a context. There are three, they answer
different questions, and the same source code means something different in each.
This page is the decision.*

A **context** is the thing that owns the quantum state your registers are
handles into. You open one for the duration of a block; it is torn down when the
block exits, even on an exception. What you cannot do is run quantum code
without one — [`QBool`](../reference/surface.md) outside any context raises

```
No active Sturm context — use `eager(cap) do ctx … end`, `density(cap) do ctx … end`, or `@context ctx begin … end`
```

## The decision, in four lines

1. **You want to run the program and see what happens.** Use `eager`. This is
   almost always the right answer, and the only one that gives you plain `Bool`
   outcomes and ordinary `if` statements.
2. **You want the exact probabilities, or you want to add noise.** Use
   `density`. It computes the channel instead of sampling a trajectory — no
   shot noise, no seed, and noise channels are only representable here.
3. **You do not want to run the program at all** — you want it as data, to
   inspect or optimise. Use `trace`.
4. **You want a distribution out of a program that runs on `eager`.** Do not
   switch contexts. Use `Sturm.shots`, which runs the `eager` program many
   times.

## `eager` — sampling

```julia
Sturm.eager(capacity) do ctx
    …
end
```

The simulator holds a **state vector**: one complex amplitude per basis state.
Measurement draws a real outcome from the Born rule, collapses the state, and
hands you a value. One run is one trajectory — one run of the experiment,
mid-circuit measurement and feed-forward included.

```julia
using Sturm

Sturm.eager(2) do ctx
    a = QBool(0.5)
    b = QBool(false)
    b ⊻= a
    (Bool(a), Bool(b))
end
# => (false, false)
#    Random per run. (true, true) is equally likely; a mismatch never occurs.
```

`Bool(q)` here returns **a real Julia `Bool`**, so ordinary host control flow
works: `if Bool(q) … end`, `m && not!(c)`, `count(outs)`. That is the practical
reason `eager` is the beginner's context.

### What `capacity` costs

`capacity` is a qubit count, and it sets the memory footprint directly: a pure
state on `n` qubits is a flat vector of `2^n` `ComplexF64` amplitudes, 16 bytes
each.

| `capacity` | amplitudes | RAM |
|---|---|---|
| 10 | 1,024 | 16 KiB |
| 20 | 1,048,576 | 16 MiB |
| 26 | 67,108,864 | 1 GiB |
| 30 | 1,073,741,824 | 16 GiB |

Every four extra qubits multiply the requirement by sixteen. Around 30 qubits is
the practical ceiling on ordinary hardware — a *memory* ceiling, not an
algorithmic one. Ask for more than you can afford and the allocation, not
Sturm, is what fails.

Ask for too little and Sturm fails, clearly:

```
context capacity (1 wires) exceeded — grow the `eager(cap)`/`density(cap)` capacity
```

Budget generously. Capacity is cheap at small sizes, and several constructs —
`oracle` above all — allocate scratch wires of their own that you never named.

## `density` — exact channels

```julia
Sturm.density(capacity) do ctx
    …
end
```

The simulator holds a **density matrix**: the full `2^n × 2^n` operator. Nothing
is sampled. A program's *distribution* is computed rather than estimated, and
mixed states — the ones a noisy process actually produces — are representable.

```julia
Sturm.density(2) do ctx
    a = QBool(0.5)
    b = QBool(false)
    b ⊻= a
    round.(real.(Sturm.density_matrix(ctx)), digits = 4)
end
# => [0.5  0.0  0.0  0.5
#     0.0  0.0  0.0  0.0
#     0.0  0.0  0.0  0.0
#     0.5  0.0  0.0  0.5]
```

Those corner `0.5`s are the coherence — the thing a table of measurement
frequencies cannot see, and the reason channel-level checks live here.

**The catch, and it bites everyone once:** in this context `Bool(q)` does *not*
return a `Bool`. There is no trajectory to sample, so the cast dephases the wire
and returns a **record token** — a live, non-destructive handle to the
measurement result.

```julia
Sturm.density(2) do ctx
    a = QBool(0.5)
    b = QBool(false)
    b ⊻= a
    m = Bool(a)                        # a token, not a Bool
    (typeof(m), Sturm.record_distribution(m))
end
# => (Sturm.ClassicalBit{Sturm.DensityMatrixContext}, [0.4999999999999999, 0.5000000000000001])
```

`Sturm.record_distribution` reads the outcome probabilities straight off the
matrix diagonal with no backaction — call it as often as you like, the state is
bitwise unchanged. And exact means exact: preparing `QBool(0.3)` and reading its
record gives `[0.7000000000000001, 0.29999999999999993]`, not a sample mean.

Branch on a token with [`cases`](../explanation/seven_constructs.md), never with
a host `if`. A host `if` fails immediately, which is the good outcome:

```julia
Sturm.density(1) do ctx
    m = Bool(QBool(0.5))
    if m; println("no"); end
end
# ERROR: TypeError: non-boolean (Sturm.ClassicalBit{Sturm.DensityMatrixContext})
#        used in boolean context
```

### Noise lives here and only here

```julia
Sturm.density(1) do ctx
    q = QBool(false)
    Sturm.apply_noise!(q, Sturm.bit_flip(0.25))
    Sturm.record_distribution(Bool(q))
end
# => [0.7499999999999999, 0.25]
```

A quarter of the population flipped, exactly. The same call on `eager` is
refused, with the reason and the alternatives:

```
apply!: a statevector cannot hold the mixed state a noise channel produces.
Choose explicitly: density(cap) executes the exact channel in one run;
shots(…) samples trajectories; stinespring=true dilates + traces — ONE
quantum-jump unravelling per run, NOT the channel.
```

### What `capacity` costs here

A density matrix is the *square* of a state vector, so the same `capacity`
argument buys you far less:

| `capacity` | matrix entries | RAM |
|---|---|---|
| 5 | 1,024 | 16 KiB |
| 8 | 65,536 | 1 MiB |
| 10 | 1,048,576 | 16 MiB |
| 13 | 67,108,864 | 1 GiB |
| 15 | 1,073,741,824 | 16 GiB |

Every *two* extra qubits multiply the requirement by sixteen. In practice, exact
density-matrix work means single-digit qubit counts. This is why the exactness
argument does not simply win: you buy precision with size.

## `trace` — the program as data

```julia
Sturm.trace(f, nin)
```

The third context **executes nothing**. There is no simulator state at all, no
call into the C backend, no amplitudes. Running your function under it records
what it *would* have done into a channel graph — the intermediate representation
that optimisation passes read.

```julia
g = Sturm.trace(1) do q
    not!(q)
    not!(dual(q))
    q
end

typeof(g)         # => Sturm.ChannelDAG
length(g.nodes)   # => 2      (two operations recorded)
length(g.qin)     # => 1      (one register in)
length(g.qout)    # => 1      (one register out)
```

Note the shape of the call: `trace(f, nin)` hands `f` its `nin` input registers
as boundary ports, runs the body once as ordinary Julia — loops unroll, `if`s on
classical values resolve — and freezes the result. Measurements become nodes
rather than outcomes:

```julia
g = Sturm.trace(1) do q
    m = Bool(q)
    r = QBool(false)
    cases(m) do; not!(r) end
    r
end

length(g.nodes)      # => 3
map(typeof, g.nodes) # => (Sturm.MeasureN, Sturm.AllocN, Sturm.CasesN)
```

`Bool(q)` here returns a *symbolic* token naming an output port. Asking it for a
distribution is refused, and the message says why:

```
record_distribution: a Tracing token is SYMBOLIC — a trace-time record has no
distribution (the compiler context executes nothing). Introspect on the DM
context, or `shots` on Eager.
```

You will not reach for `trace` on day one. Reach for it when you want to see, or
rewrite, the program a piece of surface code denotes.

## Side by side

| | `eager` | `density` | `trace` |
|---|---|---|---|
| What it holds | state vector, `2^n` amplitudes | density matrix, `2^{2n}` entries | nothing — a graph |
| A run is | one sampled trajectory | the exact channel | a recording |
| `Bool(q)` returns | `Bool` | a record token | a symbolic wire token |
| Host `if` on the result | works | `TypeError` — use `cases` | `TypeError` — use `cases` |
| Noise channels | refused | native | recorded |
| Practical ceiling | ~30 qubits | single digits | no state, so no ceiling |
| Get statistics with | `Sturm.shots` | `Sturm.record_distribution` | neither — nothing ran |
| Randomness | yes; seed with `rng =` | none | none |

## One source, three meanings

The single spelling `Bool(q)` returning three different kinds of thing is
deliberate, not an oversight. There is one *operation* — cross the boundary from
quantum to classical — and each context outputs the most faithful thing it can:
a sampling context has an actual outcome, a channel context has a record, and a
compiler context has a wire. Writing three verbs would have hidden the fact that
it is one operation.

The practical consequence is that porting a program from `eager` to `density`
is not free. Anywhere you wrote `if Bool(q)` or `m && not!(c)`, you must write
`cases(m) do … end`. Programs written with `when` and `cases` from the start run
unchanged in both.

## Related

- [Measure statistics](../howto/measure_statistics.md) — `shots` versus
  `record_distribution` versus `classicalise`, and which one you actually want.
- [Contexts and scope](../explanation/contexts_and_scope.md) — why scope exit
  silently discards registers, and why that is correct.
- [Contexts reference](../reference/contexts.md) — the full API.
