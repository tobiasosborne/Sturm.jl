# The seven constructs

*This is the whole user-facing quantum language on one page. Not a tutorial —
a map. Each construct gets its syntax, what it means physically, and one
snippet you can run.*

Sturm's surface vocabulary is seven forms. That is not a subset or a starting
point; it is the complete list. Everything else you will write in a Sturm
program is ordinary Julia — functions, loops, `if`, tuples, `do` blocks.

| # | Form | Role |
|---|---|---|
| 1 | `QBool(p, φ)`, `QInt{W}(n)`, `QMod{N}(v)` | **preparation cast** — classical value in, register out |
| 2 | `Bool(q)`, `Int(x)` (consuming) | **measurement cast** — register in, classical value out |
| 3 | `not!(a)`, `a ⊻= b`, `add!(x, a)` | **the action family** — flips, entanglement, translations |
| 4 | `dual(q)`; `q̂ ⊻= r`, `x̂ += a` | **the conjugate view** and its modulations |
| 5 | `when(q) do … end` | **coherent control** |
| 6 | `cases` / `@cases` | **classical branching** on an outcome |
| 7 | `oracle(f, x)` | **the Bennett bridge** — an ordinary function, made reversible |

The house rule, worth memorising before anything else:

> **If your program reads like a circuit diagram, it is wrong. If it mentions
> a gate, a rotation angle, or a process value, it is not surface code. If it
> reads like ordinary Julia with a few casts and views, it is probably right.**

---

## 1. `QBool(p, φ)` — preparation

`QBool(b::Bool)` prepares a definite `|0⟩` or `|1⟩`. `QBool(p, φ)` prepares
the state with Born probability `p` of reading `1` and relative phase `φ` —
`p` is a probability, not an amplitude, and it must lie in `[0,1]` or you get
a `DomainError` rather than a silent widening to complex numbers.

`QInt{W}(n)` is the same idea `W` wires wide; `QMod{N}(v)` is the modular
register behind order finding.

```julia
using Sturm

Sturm.eager(4) do ctx
    Int(QInt{3}(5))
end
# => 5
```

Three named literals cover the states you reach for constantly:
`plus()` is `QBool(0.5)`, `minus()` is `QBool(0.5, π)`, and `magic_T()` is
`QBool(0.5, π/4)` — the phase-bearing resource state.

```julia
using Sturm, Random

Sturm.shots(1; N = 2000, rng = MersenneTwister(4)) do ctx
    Bool(QBool(0.5))
end |> outs -> count(outs) / length(outs)
# => 0.4925
```

**Physics.** This is the classical → quantum half of the type boundary. It
allocates fresh wires in `|0⟩` and applies an exact preparation — for
`QBool(true)` that is exactly one bit flip, never a rotation that happens to
land there.

## 2. `Bool(q)` / `Int(x)` — measurement

The measurement cast has **one spelling in every context**. There is no
`measure` verb, and no separate DSL for "measure and keep" — because there is
no such thing.

It **consumes** its argument. After `Bool(q)`, the handle `q` is dead; touching
it again is a loud error naming the register. That is no-cloning, made visible
in the type system rather than documented in a comment.

```julia
using Sturm

[Sturm.eager(1) do ctx
     Bool(QBool(b))
 end for b in (false, true)]
# => Bool[0, 1]
```

**What comes back depends on the context**, and this is the one place the name
`Bool` may return something that is not a `Bool`:

| Context | `Bool(q)` returns |
|---|---|
| `Sturm.eager` | a genuine `Bool` — sample, collapse, retire |
| `Sturm.density` | a **record token** naming a live classical record |
| `Sturm.trace` | a **wire token** naming a measurement node in the IR |

One name, three faithful answers — see
[contexts and scope](contexts_and_scope.md). A compiler-inserted *implicit*
cast (assigning a register into a `Bool`-typed slot) still measures, but warns
first, because collapse is a real effect and you should have asked for it.

## 3. `not!`, `⊻=`, `add!` — the action family

These are the operations that *do* something to a register in place. They all
mutate and return the same handle, which is what makes `a ⊻= b` a physical
operation rather than a rebinding.

```julia
using Sturm

Sturm.eager(4) do ctx
    a = QBool(false); b = QBool(true)
    not!(a)          # a: false → true
    a ⊻= b           # a ← a ⊕ b
    (Bool(a), Bool(b))
end
# => (false, true)
```

There is **no CNOT gate** in this language. Entanglement is *composed*: xor a
register into a fresh `false` and you have a Bell pair.

```julia
using Sturm, Random

Sturm.shots(2; N = 1000, rng = MersenneTwister(7)) do ctx
    b = QBool(0.5)         # a fair quantum coin
    c = false ⊻ b          # a fresh false, entangled with it
    Bool(b) == Bool(c)     # perfectly correlated, every shot
end |> outs -> count(outs) / length(outs)
# => 1.0
```

For integer registers the family is `add!`/`sub!` (cyclic addition mod `2^W`,
which **wraps** rather than erroring), `x ⊻= y` (bitwise, a genuinely
different group action on the same register), and `superpose!` (a uniform
superposition over all values).

```julia
using Sturm

Sturm.eager(6) do ctx
    x = QInt{3}(2); add!(x, 3); sub!(x, 1); Int(x)
end
# => 4

Sturm.eager(8) do ctx
    x = QInt{3}(5); y = QInt{3}(3); x ⊻= y; (Int(x), Int(y))
end
# => (6, 3)
```

`x[i]` slices out one wire as a borrowed handle — wire 1 is the most
significant bit:

```julia
using Sturm

Sturm.eager(4) do ctx
    x = QInt{3}(5)                        # 5 = 0b101
    (Bool(x[1]), Bool(x[2]), Bool(x[3]))
end
# => (true, false, true)
```

## 4. `dual(q)` — the conjugate view

`dual` is not an operation. It is a different **way of addressing** the same
register — the conjugate basis, in the sense that position and momentum are
conjugate. It is a lazy wrapper: free to build, and `dual(dual(q)) === q`
returns the literal same object.

Operating *through* the view swaps two roles: what was a translation becomes a
modulation. `not!(q)` flips the value; `not!(dual(q))` flips the *sign* and
leaves the value alone.

```julia
using Sturm

Sturm.eager(2) do ctx
    q = QBool(false); not!(dual(q)); Bool(q)
end
# => false      -- the value is untouched

Sturm.eager(2) do ctx
    q = plus(); not!(dual(q)); Bool(dual(q))
end
# => true       -- but |+⟩ became |−⟩
```

Conjugate-basis *readout* is `Bool(dual(q))`, and it is the construct whose
absence broke version 0.1's teleportation. The full story, including the two
spelling traps, is in [views and duality](views_and_duality.md).

## 5. `when` — coherent control

`when(q) do … end` runs the body **coherently controlled** on `q`. Nothing
collapses; the body's effect happens on the branch where `q` is `|1⟩` and not
on the other, and both branches stay in superposition.

```julia
using Sturm

Sturm.eager(4) do ctx
    a = QBool(true); b = QBool(true); c = QBool(false)
    when(a) do
        when(b) do
            not!(c)
        end
    end
    (Bool(a), Bool(b), Bool(c))
end
# => (true, true, true)

Sturm.eager(4) do ctx
    a = QBool(true); b = QBool(false); c = QBool(false)
    when(a) do; when(b) do; not!(c) end end
    Bool(c)
end
# => false
```

Nesting `when` gives you a doubly-controlled flip with no extra vocabulary —
what a circuit language would call a Toffoli.

Three things are **banned** in a body, all with loud errors, because a channel
is not a controllable thing (this is a theorem, not a policy):

1. **No measurement, trace, `cases`, or noise.** Control on a non-unitary
   effect is not representable.
2. **The body may not touch its own control** — not as a target, not as an
   operation's control, not through a view.
3. **Scratch allocated in the body must come back to `|0⟩`** before the body
   ends, or the check fires.

```julia
# WRONG — for illustration
when(q) do
    Bool(r)
end
```

```
measurement cast Bool(q) is forbidden inside a `when` body (guardrail 1):
a control frame is live, and control on a non-unitary effect (measurement,
trace, noise) is unrepresentable by axiom P4 — the body must trace to a
unitary-witnessed value.
```

```
the `when` body operates on its control register WireID(1) (guardrail 2):
a body must not read or write its guard — not as a target, not as an
op-control, not through a view. (Legal kickback names a DIFFERENT register as
the target and lets the control pick up phase through the `ctrl` mechanism.)
```

## 6. `cases` — classical branching

`cases` branches on a value that has **already been measured**. It is the
classical sibling of `when`, and the distinction matters: `when` is coherent
and collapses nothing; `cases` acts on a record that already exists.

```julia
using Sturm

Sturm.eager(4) do ctx
    m = Bool(QBool(true))
    a = QBool(false)
    cases(m) do
        not!(a)
    end
    Bool(a)
end
# => true
```

`@cases` adds multiway sugar, and `Sturm.select` builds a value from an
outcome without branching at all:

```julia
using Sturm

Sturm.eager(6) do ctx
    m = Bool(QBool(true))
    sel = Sturm.select(m, 2, 1)        # a static choice, driven by the record
    a = QBool(false); b = QBool(false)
    @cases sel begin
        1 => not!(a)
        2 => not!(b)
        _ => nothing
    end
    (sel, Bool(a), Bool(b))
end
# => (2, false, true)
```

Under the eager context the selector is a real scalar and one arm runs. Under
the density context it is a record token and `cases` realises the exact
instrument-sum channel — all arms, correctly weighted, in one run. Same source
text, both times.

Handing `cases` a live quantum register is refused, with the fix in the
message:

```
cases/@cases takes a CLASSICAL outcome, never a raw quantum register:
measure first — `cases(Bool(q)) do … end`. A register-accepting form would
hide the quantum→classical (measurement) instrument boundary.
```

## 7. `oracle(f, x)` — the Bennett bridge

`oracle` compiles an ordinary Julia function into a reversible operation and
pairs it with a live register. You apply it with the *same* `⊻=` from
construct 3 — construct 7 produces the query, construct 3 consumes it.

```julia
using Sturm, Bennett          # the compiler is a weak dependency

inc(x) = x + one(x)

Sturm.eager(20) do ctx
    x = QInt{3}(5)
    b = QInt{3}(0)
    b ⊻= oracle(inc, x)
    (Int(x), Int(b))
end
# => (5, 6)      -- x preserved, b holds 0 ⊕ inc(5)
```

Point it at a `minus()` and the XOR becomes a sign — phase kickback, the
engine of Deutsch–Jozsa, Bernstein–Vazirani and Grover. Everything it can and
cannot compile is in [writing oracles](../howto/write_oracles.md).

---

## Why there are no gates

You may have noticed what is missing. There is no `H`, no `CNOT`, no `Rz(θ)`,
no circuit object, no qubit index. That is deliberate, and the reason is worth
telling honestly.

A quantum framework that exposes gates has to let you build **controlled**
versions of them, because controlled operations are how algorithms are made.
The moment it does, it faces a subtle problem: a gate's *global phase* is
invisible on its own — physically meaningless, safe to drop — but becomes
completely observable the moment the gate is controlled. Drop it in a
decomposition and you have introduced an error that no test on the
uncontrolled gate can detect.

Every major quantum framework has shipped that bug. Cirq, Qiskit and pytket
each carried a global-phase field in their gate representation *and still*
shipped controlled-decomposition phase bugs that survived for years, through
large test suites and dedicated maintainers. Not because anyone was careless
— because the bug can live at *any* of the dozens of call sites that build a
controlled circuit, and each of those sites is individually plausible.

Sturm's answer is structural rather than diligent:

- **There is exactly one function in the whole system that constructs a
  controlled operation.** A build-time check enforces that no other file may
  even name it. If controlled lowering is right there, it is right everywhere.
- **The surface has no gates**, so there is no second path. `when` funnels
  into that one function; `dual` composes rather than applying; `oracle`
  produces a permutation, and a controlled permutation is still a permutation.
- **Global phase is kept, never quotiented away.** The kernel works in `U(2)`
  and knows that `+I` and `−I` are different operations, because under control
  they are. See [phase discipline](phase_discipline.md).

The gate vocabulary still exists — it is the kernel's internal representation,
reachable as `Sturm.X`, `Sturm.H`, `Sturm.ctrl` for library authors and
tests. It is just not a user language. An intermediate representation never
should be.

## Where next

- [Functions are channels](functions_are_channels.md) — the idea underneath.
- [Views and duality](views_and_duality.md) — construct 4 in full.
- [Contexts and scope](contexts_and_scope.md) — where constructs 1, 2 and 6
  change meaning.
- [Phase discipline](phase_discipline.md) — the kernel side of the gate story.
- [Common gotchas](gotchas.md).
- [Reference: the surface](../reference/surface.md) — every docstring.
- [Reference: the algorithm library](../reference/library.md) — the
  higher-order functions written out of these seven forms.
