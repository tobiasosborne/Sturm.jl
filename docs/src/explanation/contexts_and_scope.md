# Contexts and scope

*This is the "why" behind `eager` / `density` / `trace` and behind regions.
It explains how the same source text can mean three different things, and why
the cleanup at scope exit says nothing.*

Write a program in Sturm and you have written a channel. But a channel is a
mathematical object, and there is more than one honest question you can ask
about it:

- *What would one run on a machine look like?*
- *What map on states does it denote, exactly?*
- *What is its structure, as data I can optimise?*

Those are three different questions with three different answers, and Sturm
answers them by running the **same program** under three different **contexts**.
Nothing in your source text changes.

```julia
using Sturm

coin(ctx) = Bool(QBool(0.5))

Sturm.eager(1)   do ctx; typeof(coin(ctx)) end
# => Bool

Sturm.density(1) do ctx; typeof(coin(ctx)) end
# => Sturm.ClassicalBit{Sturm.DensityMatrixContext}
```

---

## Value, record, wire

The measurement cast has one spelling in every context — there is no `measure`
verb and no per-context dialect. What it *returns* is the classical system the
measurement outputs, as faithfully as the context can express it:

| Context | `Bool(q)` returns | Because |
|---|---|---|
| `Sturm.eager` | a **value** — a genuine `Bool` | in one trajectory, a point state *is* its value |
| `Sturm.density` | a **record** — a live token | the exact channel has no single outcome; it has a record with a distribution |
| `Sturm.trace` | a **wire** — a symbolic handle | nothing has executed; the record names a node in the IR |

This is a deliberate, knowing exception to the usual expectation that a
constructor named `Bool` returns a `Bool`. The alternative — three different
verbs — would make every algorithm three programs, and the whole point of the
design is that it is one.

Three separate meanings do stay separate, though, and they are separate
*operations*, not separate spellings of one:

- **sample** — take one outcome. Native to `eager`; `Sturm.shots` is how you
  get a distribution out of it.
- **record** — the cast itself, in every context.
- **assert** — postselection. Always explicit, never implicit.

### `Sturm.eager` — one trajectory

An eager context is a statevector. `Bool(q)` samples, collapses, and retires
the handle, so ordinary Julia control flow works on the result and mid-circuit
measurement with feed-forward is exactly what it looks like.

Its capacity argument is a qubit count and sets the memory: a flat
`2^capacity` vector of `ComplexF64`, 16 bytes an amplitude. `capacity = 20` is
16 MiB; `capacity = 30` is roughly 16 GiB, which is about where the simulator
tops out.

### `Sturm.density` — the exact channel, in one run

A density-matrix context stores the full state, so it executes the channel
rather than a trajectory. There is no sampling error and no shot count: a
Choi-level assertion is a single deterministic run.

Its partial trace is exact rather than stochastic, its measurement produces a
record token whose distribution you can read with `Sturm.record_distribution`
without disturbing anything, and it is the only context where a noise channel
can be applied at all. Memory is `2^(2·capacity)` entries, so the qubit ceiling
is about half the eager one.

### `Sturm.trace` — the compiler's view

The tracing context **executes nothing**. It has no simulator state, makes no
calls into the backend, and materialises your program into an intermediate
representation instead:

```julia
using Sturm

g = Sturm.trace(1) do q
    not!(q); not!(dual(q)); q
end

typeof(g)                       # => Sturm.ChannelDAG
length(g.nodes)                 # => 2
[typeof(n) for n in g.nodes]    # => DataType[Sturm.ApplyN, Sturm.ApplyN]
Sturm.has_barrier(g)            # => false
```

`has_barrier` is the predicate the whole optimisation discipline hinges on. A
measurement, a classical branch, or a noise channel is a **barrier** — the IR
represents channels, not circuits, and most optimisation methods from the
literature assume unitary circuits and would be wrong across one.

```julia
using Sturm

g = Sturm.trace(1) do q
    Bool(q); nothing
end
(length(g.nodes), Sturm.has_barrier(g))
# => (1, true)
```

Sealing a barrier-free program into a certified unitary block is `certify`;
handing it one with a barrier is refused by name:

```
certify: DAG contains a measurement/cases/noise BARRIER — it is a channel, not
a unitary block; control and unitary passes are unrepresentable on it.
```

---

## Scope is the boundary

A function is a channel on its signature. Its local registers — allocated,
neither returned nor consumed — are the part of the world the channel
interacts with and then forgets. That is not an analogy; it is how Sturm
implements scope.

`region() do … end` opens such a scope on the current context. At exit, every
register the region owns and has not consumed is traced out:

```julia
using Sturm

Sturm.eager(4) do ctx
    inside = 0
    region() do
        a = QBool(0.5); b = QBool(0.5)
        inside = length(Sturm.live_wires(Sturm.current_context()))
        nothing
    end
    (inside, length(Sturm.live_wires(ctx)))
end
# => (2, 0)
```

What survives is what the region **returns**. A returned register (or a tuple
of them, or a view of one) is re-homed into the enclosing scope; anything else
— a scalar, `nothing` — is not, and its registers go:

```julia
using Sturm

Sturm.eager(4) do ctx
    q = region() do
        QBool(true)
    end
    (length(Sturm.live_wires(ctx)), Bool(q))
end
# => (1, true)
```

You can also close a register early and explicitly with `ptrace!`:

```julia
using Sturm

Sturm.eager(4) do ctx
    q = QBool(0.5)
    ptrace!(ctx, q.wire)
    length(Sturm.live_wires(ctx))
end
# => 0
```

Early or late makes no observable difference — moving *when* a register is
traced changes nothing about the statistics of anything that survives. That
invariance is a tested law, and it is what licenses the silence discussed
below.

### Binding a context

`Sturm.eager(cap) do ctx … end` and `Sturm.density(cap) do ctx … end` do three
things: construct the context, bind it as the current one, and open a region.
On the way out they trace the region and then free the backend state — in a
real `try`/`finally`, so it happens even if your body throws.

Cleanup is deliberately **never** a garbage-collector finaliser. Finalisers run
at unpredictable times in arbitrary contexts, and mixing that with a foreign
memory allocation is how you get crashes nobody can reproduce. Scope exit is
deterministic; the GC is not invited.

`@context ctx begin … end` binds an *existing* context for a block without
freeing it, which is what you want when a function needs to run inside a
context somebody else owns:

```julia
using Sturm

Sturm.eager(2) do ctx
    @context ctx begin
        Sturm.current_context() === ctx
    end
end
# => true
```

Outside any context, asking for one is a loud error with the three ways in:

```
No active Sturm context — use `eager(cap) do ctx … end`,
`density(cap) do ctx … end`, or `@context ctx begin … end`
```

The binding is a scoped value, which means it **inherits into spawned tasks** —
the older task-local-storage mechanism does not, and that difference is a real
bug class this project sidesteps by construction:

```julia
using Sturm

Sturm.eager(1) do ctx
    @context ctx begin
        t = Threads.@spawn Sturm.current_context()
        fetch(t) === ctx
    end
end
# => true
```

---

## Why the silence is physics

Sturm's standing rule is to fail loudly: assertions rather than silent returns,
crashes rather than corrupted state. Scope-exit tracing is the one deliberate
exception, and it is worth being precise about why.

Tracing a register has **no backaction**. Nothing you can do to the registers
that survive can reveal when — or whether — some other register was traced.
That is no-signalling, and it is the same reason the timing invariance above
holds. A warning would be a warning about an event that, by construction,
cannot affect you.

Contrast an *implicit measurement*: assigning a register into a `Bool`-typed
slot triggers a compiler-inserted cast, which collapses state. That one warns,
every time, because collapse is a real effect on the state you still hold:

```
Warning: implicit measurement of a QBool: a quantum→classical cast collapses
state — write `Bool(q)` explicitly to silence this
```

Implicit and harmless is silent. Implicit and consequential warns. Explicit is
always silent. That is the whole rule, and "fix the silence of traces" is the
one change that would break it.

There is an opt-in exception for people who want more noise: `strict = true` on
a context arms a detector for the specific programming error of dropping a
still-entangled handle — see
[the lost-binding trap](views_and_duality.md).
It is off by default precisely so the common path stays quiet.

---

## The namespace rule

`using Sturm` gives you the seven surface constructs and their sugar, and
nothing else. The contexts, the kernel, the channel IR and the library
internals are **public but not exported** — documented, supported, reachable as
`Sturm.eager`, `Sturm.ctrl`, `Sturm.certify`, and never dumped into your
namespace.

That is why every snippet in these docs writes `Sturm.eager(...)` rather than
`eager(...)`. The bare form is an `UndefVarError` with a helpful hint:

```
UndefVarError: `eager` not defined in `Main`
Hint: a global variable of this name also exists in Sturm.
```

If you type it constantly, import it once and be explicit about what you took:

```julia
using Sturm
using Sturm: eager, density, shots
```

The layering is the point: what a *program* does to itself is exported; what an
*experimenter* does to a program stays qualified.

## Where next

- [Choosing a context](../getting_started/choosing_a_context.md) — the short
  decision guide.
- [Getting probabilities out](../howto/measure_statistics.md) — `shots`,
  `record_distribution`, and what each is exact about.
- [Functions are channels](functions_are_channels.md) — why scope is the
  environment.
- [Reference: contexts](../reference/contexts.md).
