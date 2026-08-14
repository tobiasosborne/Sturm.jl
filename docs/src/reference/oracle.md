# Reference — the oracle bridge

```@meta
CurrentModule = Sturm
```

*Dry, exhaustive lookup. For the practical guide — what compiles, what does
not, and a failing/working pair for every limit — see
[writing oracles](../howto/write_oracles.md).*

Surface construct 7 turns an ordinary Julia function into a reversible
operation. `oracle` is **exported**; the value types it produces are `public`
but not exported, because you never name one — construct 7 produces the query
and construct 3 (`⊻=`) applies it.

```julia
b ⊻= oracle(f, x)      # |x⟩|b⟩ ↦ |x⟩|b ⊕ f(x)⟩ ; x stays live
```

**Precondition.** The compiler front-end is a weak dependency. You must write
`using Bennett` alongside `using Sturm`, or `oracle` refuses at the call site
with the fix in the message. This keeps the LLVM-based compiler out of the
default `using Sturm` load path.

**Compilation is eager.** `f` is compiled at the `oracle(f, x)` call, so a
rejection names `f` at that line rather than surfacing downstream at the `⊻=`.

**Application is the same `⊻=` as everywhere else.** A plain register xor
`a ⊻= b` is the width-1, identity-function case of the same accumulate law —
not a separate construct. The query is always on the right-hand side; a swapped
call is a `MethodError`.

**Controlled application is free.** A compiled oracle is a phase-free
permutation, and a controlled permutation is still a permutation, so `when`
composes with no new controlled-lowering code path anywhere in the system.

---

```@docs
oracle
OracleQuery
CompiledOracle
```

## See also

- [Writing oracles](../howto/write_oracles.md) — the limits checklist.
- [Deutsch–Jozsa and Bernstein–Vazirani](../tutorials/deutsch_jozsa.md).
- [Reference: the library](library.md) — `find` builds its phase marker this
  way.
- [The seven constructs](../explanation/seven_constructs.md).
