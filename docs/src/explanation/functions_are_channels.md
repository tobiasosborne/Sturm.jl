# Functions are channels

*This page is the "why". It explains the one idea the rest of Sturm is built
out of. No prior quantum-computing course assumed; a couple of terms are
defined as they arrive.*

A **channel** is the most general thing physics lets you do to a quantum
system: prepare it, act on it, let it interact with something you then forget
about, measure part of it. Every honest quantum operation is one, and channels
compose — do one after another and you have a channel again.

Sturm's central claim is that you already have a language for composing things
like that, and it is Julia. A function that takes registers and returns
registers **is** a channel. Not "models" one, not "compiles to" one. Its
signature is its boundary; its body is the composition; its local variables are
the part of the world it interacts with and then forgets.

```julia
function teleport(ψ::QBool)
    b = QBool(0.5)                # a fair quantum coin
    c = false ⊻ b                 # xor into a fresh false: an entangled pair
    b ⊻= ψ                        # correlate the payload with Alice's half
    m_phase = Bool(dual(ψ))       # conjugate-basis readout (consumes ψ)
    m_value = Bool(b)
    m_value && not!(c)            # ordinary conditionals, ordinary flips —
    m_phase && not!(dual(c))      # one of them in the conjugate view
    return c
end
```

That is quantum teleportation. It has no gates in it, no circuit, no rotation
angle, no matrix. It has two casts, an xor, a conjugate view, and two ordinary
Julia `if`s written with `&&`. And its *theorem* — the thing teleportation
actually claims — is a statement about the function as a whole: **`teleport`
denotes the identity channel.** Whatever state you hand it, the same state
comes out the other end.

```julia
using Sturm

Sturm.eager(4) do ctx
    Bool(teleport(QBool(true)))
end
# => true
```

Three consequences fall out of taking "functions are channels" literally, and
the rest of this page is those three.

---

## 1. Scope is the environment

A channel is allowed to interact with a system it then throws away — that
throwing-away is what makes channels more general than unitary evolution, and
it is where irreversibility and noise come from. In Sturm that system is your
local variables.

A register you allocate inside a scope, and neither return nor measure, is
part of the environment. At scope exit it is **traced out**: measured and
discarded, silently, with no effect you can observe on anything that survives.

```julia
using Sturm

Sturm.eager(4) do ctx
    inside = 0
    region() do
        a = QBool(0.5); b = QBool(0.5)
        inside = length(Sturm.live_wires(Sturm.current_context()))
        nothing                            # neither a nor b escapes
    end
    (inside, length(Sturm.live_wires(ctx)))
end
# => (2, 0)
```

Return one and it lives:

```julia
using Sturm

Sturm.eager(4) do ctx
    q = region() do
        QBool(true)                        # escapes through the return value
    end
    (length(Sturm.live_wires(ctx)), Bool(q))
end
# => (1, true)
```

Look back at `teleport`. Nothing frees `b`, nothing frees `ψ` — they are
consumed by their measurement casts, and `c` is returned. There is no cleanup
code because there is nothing to clean up: the scope boundary *is* the physics.

This silent trace is the one place Sturm deliberately says nothing. Everywhere
else the project's rule is to fail loudly rather than continue quietly — but a
trace has **no backaction**: nothing you can measure afterwards can tell you
when, or whether, it happened. Warning about it would be warning about
something that cannot affect you. See
[contexts and scope](contexts_and_scope.md).

## 2. Casts are the boundary

The other place a channel meets the ordinary world is where classical data
becomes quantum and back. In Sturm that crossing is a **type cast** — the same
notation Julia already uses for `Float64(3)` — and never an `if`, a special
statement, or a `measure` verb.

- `QBool(p, φ)` and `QInt{W}(n)` go classical → quantum: they allocate fresh
  wires and prepare them.
- `Bool(q)` and `Int(x)` go quantum → classical. They **consume** the handle;
  after the cast the register is gone.

The two directions satisfy two laws, and both are testable statements about
the composite channel rather than about any single run.

**Measure a definite preparation and you get your bit back.**

```julia
using Sturm

[Sturm.eager(1) do ctx
     Bool(QBool(b))
 end for b in (false, true)]
# => Bool[0, 1]
```

**Prepare from a measurement and you have destroyed something.** Round-tripping
the *other* way is not the identity — it is a *pinching*, which flattens the
state onto the measurement basis and wipes the phase relations:

```julia
using Sturm, Random

# with the round trip: the conjugate-basis reading is a coin flip
Sturm.shots(2; N = 2000, rng = MersenneTwister(0x9)) do ctx
    q = plus()          # |+⟩ — definite in the conjugate basis
    b = Bool(q)         # measure ...
    r = QBool(b)        # ... and re-prepare from the classical bit
    Bool(dual(r))       # read in the conjugate basis
end |> outs -> count(outs) / length(outs)
# => 0.497

# without it: the same reading is deterministic
Sturm.shots(2; N = 2000, rng = MersenneTwister(0x9)) do ctx
    q = plus()
    Bool(dual(q))
end |> outs -> count(outs) / length(outs)
# => 0.0
```

`0.497` versus `0.0` is the price of the round trip, measured. The information
that was in the phase is not recoverable from the bit, and Sturm makes that
visible in the types: the cast consumed the register, so there is nothing left
to be wrong about.

That casts consume is also why **no-cloning is visible in the surface syntax**.
`teleport` cannot "teleport and keep": the input handle `ψ` dies at
`Bool(dual(ψ))`, so a program that used it afterwards would not compile past
its first run — it errors, naming the consumed register.

## 3. Why marginal tests lie

Here is the part that cost this project a real bug, and the reason the
codebase tests channels rather than outputs.

Take `teleport` and break it in a way that looks harmless: read the payload in
the computational basis instead of the conjugate one.

```julia
# WRONG — for illustration. The payload is read in the wrong basis.
function teleport_broken(ψ::QBool)
    b = QBool(0.5); c = false ⊻ b; b ⊻= ψ
    m_value = Bool(b)
    m_psi   = Bool(ψ)          # computational, not `Bool(dual(ψ))`
    m_value && not!(c)
    m_psi   && not!(dual(c))
    return c
end
```

Now test it the way most people first reach for: send in `|1⟩`, measure the
output, check you get `1`. Run it a thousand times.

```julia
using Sturm, Random

for (name, tp) in (("good", teleport), ("broken", teleport_broken))
    z  = Sturm.shots(4; N = 1000, rng = MersenneTwister(3)) do ctx
        Bool(tp(QBool(true)))            # send |1⟩, read the same basis
    end
    xb = Sturm.shots(4; N = 1000, rng = MersenneTwister(5)) do ctx
        Bool(dual(tp(minus())))          # send |−⟩, read the conjugate basis
    end
    println(name, "  same-basis: ", count(z) / 1000,
                  "   conjugate-basis: ", count(xb) / 1000)
end
# => good    same-basis: 1.0   conjugate-basis: 1.0
# => broken  same-basis: 1.0   conjugate-basis: 0.485
```

The broken version is **perfect** on the test. One thousand shots, one
thousand correct answers. It is also completely wrong: it transmits the
classical bit and destroys everything else, and in the conjugate basis it is a
coin flip.

This is not a hypothetical. Version 0.1 of this project shipped exactly that
teleportation, with exactly that green test, for exactly that reason — its
surface language had no way to *spell* a conjugate-basis readout, so the
algorithm could not be written correctly and the test could not see the
difference. The fix was not a better test. The fix was a language in which
`Bool(dual(ψ))` is something you can write.

### What the real contract looks like

A marginal is a shadow of a channel. Two different channels can cast the same
shadow. So the contract Sturm holds itself to is stated on the channel:

> `teleport` denotes the identity channel.

and checked by comparing the *whole* input–output map, not one basis of it.
The tools for that:

- **Run under [`Sturm.density`](contexts_and_scope.md)**, where a program
  executes the exact channel in a single run — no shots, no sampling error,
  and `Sturm.density_matrix(ctx)` shows the off-diagonal coherences a
  probability table cannot.
- **Compare channel values with `Sturm.same_channel`**, which compares the
  canonical matrix representation of the map itself rather than any particular
  factorisation of it.
- **Probe every basis, not one.** The cheap version of the discipline is what
  the loop above does: test in the computational basis *and* in the conjugate
  view.

One sharp edge, since it is the same bug class one level up:
`same_channel` cannot see a global phase, so it must never be used to check
that a *value* which may later be controlled was rewritten correctly. That
story is told in [phase discipline](phase_discipline.md).

---

## Where this goes

If functions are channels, a few things follow that Sturm takes seriously:

- **Quantum control is not "call this function conditionally."** You cannot
  control a channel — you can only control a definite operation. That is why
  `when(q) do … end` bodies may not measure or discard, and why the error you
  get says so. See [the seven constructs](seven_constructs.md).
- **Error correction transforms programs, not gates.** If a program is a
  channel, protecting it is a function from channels to channels — which is
  literally how Sturm spells it. See [reference: QECC](../reference/qecc.md).
- **The same source text means different things in different contexts**,
  because "what a channel *is*" and "what one run of it *does*" are different
  questions. See [contexts and scope](contexts_and_scope.md).

## Where next

- [The seven constructs](seven_constructs.md) — the entire surface language.
- [Views and duality](views_and_duality.md) — what `dual` actually is.
- [Contexts and scope](contexts_and_scope.md) — value, record, wire.
- [Teleportation, end to end](../tutorials/teleportation.md).
