# Grover search

**Goal.** Search an unstructured space with a plain Julia predicate, stop at
exactly the right moment, and check that the success probability really is the
textbook one.

**Prerequisites.** [Installation](../getting_started/installation.md) with the
**Bennett** setup (`find` compiles your predicate through the oracle bridge),
and [Deutsch–Jozsa and Bernstein–Vazirani](deutsch_jozsa.md), which introduces
`oracle` and phase kickback.

**Time.** About fifteen minutes. Every block was run as written; `# =>`
comments are real output. Where a number is a finite sample it says so.

```julia
using Sturm, Bennett
using Random
```

---

## Stage 1 — search with a predicate

You have a property, you want something with that property, and you have no
structure to exploit — no sorted order, no index, nothing but the ability to
check a candidate. Classically you check candidates one at a time: `N/2` on
average, `N` in the worst case. Grover's algorithm gets there in about `√N`.

In Sturm, "the property" is a Julia predicate and the whole search is one
call:

```julia
Sturm.eager(16; rng = MersenneTwister(0x11)) do ctx
    find(v -> v == 2, Val(2))
end
# => 2
```

`find(p, ::Val{W})` searches all `W`-bit integers `0:2^W-1` for one satisfying
`p`. `Val(W)` puts the width in the type, which is how the register knows how
wide to be.

At three bits:

```julia
Sturm.eager(22; rng = MersenneTwister(0xA1)) do ctx
    find(v -> v == 6, Val(3); nsolutions = 1)
end
# => 6
```

The predicate can be anything Julia can compute and the bridge can compile —
it does not have to be an equality test:

```julia
Sturm.eager(22; rng = MersenneTwister(0x11)) do ctx
    find(v -> mod(v * v, 8) == 1, Val(3))
end
# => 1        (1² = 1 mod 8; so are 3, 5 and 7 — any of them is a valid answer)
```

---

## Stage 2 — the iteration count is not a tuning knob

Grover's algorithm is a rotation. Each iteration turns the state by a fixed
angle toward the marked subspace; run too few and you have not arrived, run
too many and you *rotate past it* and the success probability comes back down.
There is a right number of iterations and it is computable in advance:

`k* = round(π/(4θ) − 1/2)` with `θ = arcsin(√(M/2^W))`, where `M` is the
number of marked states.

`find` computes it for you, but you can ask:

```julia
Sturm.grover_iterations(1, 2)   # => 1
Sturm.grover_iterations(1, 3)   # => 2
Sturm.grover_iterations(1, 4)   # => 3
Sturm.grover_iterations(2, 4)   # => 2
Sturm.grover_iterations(1, 5)   # => 4
```

And the success probability at that count is `sin²((2k*+1)θ)`, exactly:

| marked `M` | width `W` | `k*` | success probability |
|---|---|---|---|
| 1 | 2 | 1 | 1.0 |
| 1 | 3 | 2 | 0.9453124999999999 |
| 1 | 4 | 3 | 0.9613189697265625 |
| 2 | 4 | 2 | 0.9453124999999999 |
| 1 | 5 | 4 | 0.9991823155432941 |

Two of these are worth a second look. **`M = 1, W = 2` is exactly 1.0** — one
marked state in four, one iteration, and the rotation lands precisely on the
answer. Not 0.9999. One. The same happens for `M = 2, W = 3`:

```julia
Sturm.grover_iterations(2, 3)   # => 1     with success probability exactly 1.0
```

The other rows are *not* 1. Grover is a probabilistic algorithm almost
everywhere, and the standard wrapper is amplify, measure, check the predicate
yourself, repeat if it failed. `find` returns a genuine measurement outcome,
so on a bad draw it can return a non-solution. That is not a bug in the
implementation, it is the algorithm.

---

## Stage 3 — is the success probability really `sin²((2k+1)θ)`?

The deterministic cases you can just check. Four targets, four exact hits:

```julia
Sturm.eager(16; rng = MersenneTwister(0x33)) do ctx; find(v -> v == 0, Val(2)) end  # => 0
Sturm.eager(16; rng = MersenneTwister(0x33)) do ctx; find(v -> v == 1, Val(2)) end  # => 1
Sturm.eager(16; rng = MersenneTwister(0x33)) do ctx; find(v -> v == 2, Val(2)) end  # => 2
Sturm.eager(16; rng = MersenneTwister(0x33)) do ctx; find(v -> v == 3, Val(2)) end  # => 3
```

> **Why four copies instead of a loop?** Writing `for target in 0:3` and
> passing `v -> v == target` puts a *captured variable* in the predicate, and
> the bridge cannot narrow a captured value to a fixed-width reversible
> circuit:
>
> ```julia
> search_for(target) = Sturm.eager(16) do ctx      # WRONG — will not compile
>     find(v -> v == target, Val(2))
> end
> search_for(1)
> # => ERROR: oracle(f, x): Bennett could not compile `f` to a fixed reversible
> # =>   circuit — _narrow_inst: no method for Bennett.IRLoad — narrowing is not
> # =>   yet supported for this IR node type …
> ```
>
> It fails loudly at the `oracle` call rather than compiling something wrong.
> Predicates that close over a literal are fine; a predicate that closes over a
> variable is the first thing to check when a compile is refused. More on this
> in [how to write oracles](../howto/write_oracles.md).

The probabilistic case needs sampling, and sampling through the compiler
bridge is slow — a thousand runs means a thousand oracle compiles. The next
stage does the same measurement with a hand-written marker instead, which
costs nothing to compile, and lands on `sin²(5θ)`.

The project's own test suite runs the sampled comparison for `find` itself as
a regression check, with a statistical bound rather than a fixed tolerance —
so the claim "this really is the textbook success probability" is pinned in
the suite, not just asserted here.

---

## Stage 4 — what `find` is made of

`find` is a convenience wrapper. Underneath are two pieces you can use
directly.

**`amplify(mark!, x; iterations)`** is the Grover iterate loop: it applies your
phase-marking body and then the diffusion operator, `iterations` times, in
place. The marker is a `do` block, and it must be a pure phase operation — no
measurement inside, which the language enforces anyway, since measuring under
coherent control is forbidden.

```julia
Sturm.eager(6) do ctx
    x = QInt{3}(0)
    superpose!(x)
    amplify(x; iterations = 2) do reg
        when(reg[1]) do          # phase-flip |111⟩
            when(reg[2]) do
                not!(dual(reg[3]))
            end
        end
    end
    Int(x)
end
# => 7
```

No Bennett here — the marker is hand-written surface code, so nothing gets
compiled and six wires suffice. That means you can afford statistics. Over
2000 seeded shots:

```julia
outs = Sturm.shots(6; N = 2000, rng = MersenneTwister(0x4242)) do ctx
    x = QInt{3}(0)
    superpose!(x)
    amplify(x; iterations = 2) do reg
        when(reg[1]) do
            when(reg[2]) do
                not!(dual(reg[3]))
            end
        end
    end
    Int(x)
end
count(==(7), outs) / length(outs)
# => 0.9545
```

The theoretical success probability for one marked state in eight after two
iterations is `sin²(5θ) = 0.9453124999999999` — the `M = 1, W = 3` row of the
table above. The measured `0.9545` sits under two standard errors of it
(`σ ≈ 0.005` at 2000 shots), and the seven wrong answers share the remaining
weight almost evenly, each around `0.006`. This is the rotation picture
working exactly as advertised, on a program written entirely in surface
constructs.

That marker is worth reading closely, because it is surface code doing
something a circuit diagram would call a doubly-controlled Z. There is no gate
named. Nesting `when` nests coherent control; `not!` in the dual view is the
operation that flips a *sign* rather than a bit. Nested `when`s compose into
higher control automatically — the library never builds a controlled
decomposition by hand, which is precisely the code path where other frameworks
have shipped multi-year phase bugs.

> Write the nesting on separate lines. Collapsing it to one line —
> `when(a) do when(b) do … end end` — is not valid Julia: the parser reads the
> inner `when(b) do` as the outer block's argument list and rejects it.

**`superpose!(x)`** puts the register into the equal superposition that
diffusion reflects about. `amplify` does not do this for you: it amplifies
about whatever state you are already in.

The marker `find` uses is the phase kickback from
[the previous tutorial](deutsch_jozsa.md): a `|−⟩` ancilla, `⊻=` the oracle
into it, ancilla discarded. It is allocated and released inside each
iteration, so the wire count does not grow with the iteration count.

---

## Honest limits

- **`find` counts the solutions classically if you do not tell it.** Leave
  `nsolutions` out and it scans `0:2^W-1` with your predicate to get `M`. That
  is an `O(N)` classical loop — fine for a correctness demonstration, and
  obviously not part of any speedup. Supply `nsolutions` when you know it.
- **The result is a measurement.** Verify it. `find` does not re-check the
  predicate for you.
- **Simulated, so no speedup.** Running Grover on a simulator costs at least
  what the classical scan costs. The `√N` is a claim about a quantum computer,
  not about this program's wall-clock time.
- **Your predicate has to compile.** Same bridge limits as
  [the oracle tutorial](deutsch_jozsa.md): no unbounded loops, no
  `count_ones`, widths 1 to 64 — plus the captured-variable restriction above.
  Every one of these is a loud refusal at the `oracle` call, never a wrong
  circuit.
- **Scratch wires cost memory.** The `eager(cap)` numbers above are the
  smallest that fit for those predicates. A more complicated predicate
  compiles to more scratch, and every extra wire doubles the state vector.

---

## What you learned

- `find(p, Val(W))` searches with an ordinary Julia predicate.
- The iteration count is derived, not tuned; too many iterations is as bad as
  too few.
- The success probability is `sin²((2k+1)θ)` exactly, and is exactly 1 in a
  couple of small cases.
- `amplify` is the reusable core; `superpose!` sets up the state it reflects
  about; the marker is a `do` block written in ordinary surface constructs.

## Where next

- [Shor's order finding](shor.md) — the other flagship algorithm, and the one
  where the register dual is the right readout.
- [How to write oracles](../howto/write_oracles.md) — getting a predicate to
  compile.
- [Measuring statistics](../howto/measure_statistics.md) — `shots` and what to
  do with the vector it returns.
- [Library reference](../reference/library.md) — `find`, `amplify`,
  `grover_iterations`.

**Physics source.** [Grover 1996](https://github.com/tobiasosborne/Sturm.jl/blob/main/docs/physics/grover_1996_search.md) — the
search algorithm, the rotation picture, and the optimal iteration count.
