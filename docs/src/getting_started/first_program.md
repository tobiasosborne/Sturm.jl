# Your first program

*A real session, in order, with real outputs. Everything below runs as written
once you have finished [installation](installation.md). Where an output is
random I say so and show a value that actually came up.*

## Start a session

```console
$ cd ~/Projects/Sturm.jl
$ julia --project
```

```julia-repl
julia> using Sturm
```

The first call into the library in a fresh session takes about 40 seconds to
compile. After that it is quick.

`using Sturm` gives you the whole quantum vocabulary: `QBool`, `not!`, `dual`,
`when`, `QInt`, `add!`, `cases`, `oracle`, and a handful more. It does *not*
give you `eager` — that one is deliberately reachable as `Sturm.eager`, because
opening an execution context is a different kind of act from writing quantum
code, and the layering is visible in the namespace. If you find yourself
opening a lot of contexts, `using Sturm: eager, density` is the shorthand.

## A sandbox to run in

Quantum registers do not float free. They live in a **context**: a simulator
state with a fixed capacity, opened for the duration of a block and torn down
afterwards, whether the block returns or throws.

```julia-repl
julia> Sturm.eager(1) do ctx
           Bool(QBool(true))
       end
true
```

`Sturm.eager(1)` says "give me a one-qubit sandbox." Inside, `QBool(true)`
prepares a register holding a definite `true`, and `Bool(...)` reads it back
out. `true` in, `true` out — no surprise, which is the point: the first thing
to establish is that nothing quantum happens unless you ask for it.

## A coin that is not a coin

Now ask for it. `QBool` also takes a *probability*.

```julia-repl
julia> Sturm.eager(1) do ctx
           Bool(QBool(0.5))
       end
true
```

**That output is random.** Run the same block again and you may well get
`false`. Here are twelve consecutive runs from the session that wrote this page:

```julia-repl
julia> [Sturm.eager(1) do ctx; Bool(QBool(0.5)) end for _ in 1:12]
12-element Vector{Bool}:
 1
 0
 1
 0
 0
 1
 0
 0
 1
 0
 1
 1
```

Six `true`, six `false`, in no pattern. Yours will differ. This is a genuine quantum
measurement of a superposition, sampled by the simulator — not a call to `rand`
dressed up.

## Two registers that agree

A single random bit is not interesting. Two random bits that always match are.

```julia-repl
julia> Sturm.eager(2) do ctx
           a = QBool(0.5)     # a fair quantum coin
           b = QBool(false)   # a register holding a definite false
           b ⊻= a             # b ← b xor a
           (Bool(a), Bool(b))
       end
(false, false)
```

Random again — but only *jointly*. Over a thousand runs with a fixed seed:

```julia-repl
julia> using Random

julia> outs = Sturm.shots(2; N = 1000, rng = MersenneTwister(2718)) do ctx
           a = QBool(0.5)
           b = QBool(false)
           b ⊻= a
           (Bool(a), Bool(b))
       end;

julia> count(t -> t == (true, true), outs)
495

julia> count(t -> t == (false, false), outs)
505

julia> count(t -> t[1] != t[2], outs)
0
```

495 and 505, split about evenly, and **zero disagreements**. Not "few". Zero.
`Sturm.shots(f, capacity; N)` runs `f` in `N` fresh contexts and collects the
return values; it is the sanctioned way to get a distribution out of a sampling
program.

Two classical coins that always match are not two coins — they are one coin,
copied. These are not copies: neither register had a value before it was
measured. That is the difference, and it is what `b ⊻= a` bought you.

## Measurement consumes

One more thing to meet early, because it will happen to you:

```julia-repl
julia> Sturm.eager(1) do ctx
           q = QBool(true)
           Bool(q)
           Bool(q)
       end
ERROR: register WireID(1) already consumed — a measurement cast consumes its
input (§3.2/§4.5); a live handle to measured (now classical) data is a type lie,
and you cannot read it again
```

Measuring a register destroys the quantum state it named. Sturm makes the handle
dead at that moment and says so. This is not a restriction bolted on for safety;
it is the no-cloning theorem showing up as a use-after-free.

## What each line actually did

Now the second pass. The same program, physically.

```julia
Sturm.eager(2) do ctx
    a = QBool(0.5)
    b = QBool(false)
    b ⊻= a
    (Bool(a), Bool(b))
end
```

**`Sturm.eager(2) do ctx … end`** allocates a two-qubit state vector — four
complex amplitudes — initialised to `|00⟩`, binds it as the current context for
the duration of the block, and frees it on the way out. "Eager" means this
context *samples*: measurements return real outcomes and collapse the state, one
trajectory per run, exactly like a physical run of the experiment. It is one of
three choices; see [choosing a context](choosing_a_context.md).

**`a = QBool(0.5)`** is a **preparation cast**: it takes a classical value — the
probability `0.5` — and produces a quantum register. It allocates a fresh wire
in `|0⟩` and prepares the state
`√(1−p)|0⟩ + √p·e^{iφ}|1⟩`, here `(|0⟩ + |1⟩)/√2`. The optional second argument
is that phase `φ`; `QBool(0.5)` and `QBool(0.5, π)` have the *same* measurement
statistics and are physically different states, which is a distinction the
[views and duality](../explanation/views_and_duality.md) page is about. The
value returned is a handle, not a number: you cannot add it, compare it, or use
it as a dictionary key, and trying says so loudly.

**`b = QBool(false)`** prepares `|0⟩` — one register, definite.

**`b ⊻= a`** is exclusive-or, and it is the whole of entanglement in this
language. On classical bits, `b ⊻= a` sets `b` to `b xor a`. On quantum
registers it does the same thing to every branch of the superposition at once:
`a` was in both `|0⟩` and `|1⟩`, so afterwards the pair is in `|00⟩` and `|11⟩`,
and in neither separately. The joint state is
`(|00⟩ + |11⟩)/√2` — a Bell pair.

Read the assignment carefully: **the target is on the left, the control on the
right.** `b ⊻= a` changes `b` and leaves `a` alone. It returns the same handle
it mutated, which is why the `⊻=` rebinding is a genuine no-op and the operation
is physical rather than a Julia rebind. Nowhere did the word CNOT appear.

**`Bool(a)`** is the **measurement cast**, the boundary crossing in the other
direction. It samples an outcome according to the Born rule, collapses the
state, retires the handle, and hands you an ordinary Julia `Bool`. Once `a`
collapses to `false`, the `|11⟩` branch is gone, so `b` is now certainly
`false` — which is why `Bool(b)` on the next line agrees, every time, and why
those thousand runs had zero disagreements.

Note what is *not* here. No gates. No circuit. No rotation angles, no matrices,
no `H` and no `CNOT`. Four lines of ordinary-looking Julia — a cast, a cast, an
xor, two casts — and the physics came out right. That is the entire design
claim of the language.

## Where next

- [Choosing a context](choosing_a_context.md) — you have met the sampling
  context; there are two more, and they answer different questions.
- [Teleportation](../tutorials/teleportation.md) — the same four constructs,
  arranged into something genuinely surprising.
- [The seven constructs](../explanation/seven_constructs.md) — the complete
  vocabulary, which is smaller than you expect.
- [Gotchas](../explanation/gotchas.md) — the traps, before you fall into them.
