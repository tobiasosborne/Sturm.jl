# Reference — contexts, regions and statistics

```@meta
CurrentModule = Sturm
```

*Dry, exhaustive lookup. For the ideas behind this page see
[contexts and scope](../explanation/contexts_and_scope.md); for a task recipe
see [getting probabilities out](../howto/measure_statistics.md).*

A **context** decides what running your program means. The same source text
runs unchanged under all three. Everything here except `@context`, `region`
and `ptrace!` is `public` but not exported — spell it `Sturm.eager`,
`Sturm.density`, and so on.

| Context | What it is | `Bool(q)` returns |
|---|---|---|
| `EagerContext` | a statevector; one trajectory per run | a `Bool` |
| `DensityMatrixContext` | the full state; the exact channel in one run | a record token |
| `TracingContext` | no state, no backend calls; builds the IR | a wire token |

---

## The contexts

```@docs
AbstractContext
EagerContext
DensityMatrixContext
TracingContext
```

## Entering a context

The resource forms construct a context, bind it, open a region, and free the
backend state in a `finally` — deterministic even if the body throws, and never
a garbage-collector finaliser. `@context` binds an *existing* context without
freeing it. `trace` is the only way to drive the tracing context.

```@docs
eager
density
trace
@context
current_context
trace_nonportable
```

## Regions and scope

A region's exit is the boundary at which owned, unconsumed registers are traced
out. What survives is what the region returns. `ptrace!` closes one early and
explicitly; it is forbidden inside a `when` body, because a forgetful map
cannot be controlled.

```@docs
region
ptrace!
```

## Primitives

The lower-level operations a library author reaches for. `apply!` is the
application kernel — it checks wire count, aliasing on register identity, and
liveness before anything reaches the backend.

```@docs
allocate!
apply!
apply_channel!
apply_noise!
teardown!
q
sqrt_u2
```

## Reading state out

Both return a **copy** and exist for tests and inspection, not for algorithms.

```@docs
statevector
density_matrix
```

## Statistics and analysis

Three different tools for three different questions — `shots` (sampled, eager)
lives in [the surface reference](surface.md). `record_distribution` reads a
density-context record exactly and without backaction. `classicalise` analyses
a *channel description*, is capped, and is deliberately phase-blind: never an
equivalence test.

```@docs
record_distribution
classicalise
CLASSICALISE_MAXWIRES
```

## See also

- [Choosing a context](../getting_started/choosing_a_context.md).
- [Getting probabilities out](../howto/measure_statistics.md).
- [Contexts and scope](../explanation/contexts_and_scope.md).
- [Reference: channels](channels.md) — the IR that the tracing context builds.
