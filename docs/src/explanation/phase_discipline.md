# Phase discipline

*This is the "why" for the kernel — the layer under the surface, where
definite operations live. You never write any of this in a Sturm program. You
should know it exists, because it is the part that is easy to get wrong and
this project's answer to that is structural.*

Surface code has no gates. But something underneath has to know that flipping a
bit is `X`, that a Hadamard is a Hadamard, and how to build a controlled
version of an arbitrary operation. That something is the **kernel**, and the
values it holds are called process values: definite operations, not channels.

An intermediate representation is not a user language, so the kernel is
allowed to have gates. What it is not allowed to do is be sloppy about phase.

---

## Global phase is not meaningless

Everyone learns that the overall phase of a quantum state is unobservable.
Multiply everything by `e^{iθ}` and no measurement can tell. That is true, and
it is the source of the single most persistent bug class in quantum software.

Because the moment you **control** an operation, its global phase becomes
completely observable. The controlled version applies the phase on one branch
and not the other, and a relative phase between branches is exactly what
interference measures.

Watch it happen. `−I` and `+I` are the same operation up to global phase:

```julia
using Sturm

Sturm.same_channel(Sturm.channel(Sturm.NEG_I), Sturm.channel(Sturm.I2))
# => true
```

Control them both, and they are not:

```julia
using Sturm

round.(real.(Sturm.denoted_matrix(Sturm.ctrl(Sturm.I2))); digits = 12)
# => [1.0 0.0 0.0 0.0
#     0.0 1.0 0.0 0.0
#     0.0 0.0 1.0 0.0
#     0.0 0.0 0.0 1.0]

round.(real.(Sturm.denoted_matrix(Sturm.ctrl(Sturm.NEG_I))); digits = 12)
# => [1.0 0.0  0.0  0.0
#     0.0 1.0  0.0  0.0
#     0.0 0.0 -1.0  0.0
#     0.0 0.0  0.0 -1.0]

Sturm.same_channel(Sturm.channel(Sturm.ctrl(Sturm.NEG_I)),
                   Sturm.channel(Sturm.ctrl(Sturm.I2)))
# => false
```

The identity and "the identity times −1" become the identity and a real,
measurable, two-qubit phase operation. So the kernel keeps the phase. Its
one-qubit value type is an element of `U(2)` — a unit quaternion for the
rotation part plus an explicit phase — and `Sturm.I2` and `Sturm.NEG_I` are
two different named constants that are **never** merged.

## `Ry(2π) = −I`, and that is physics

The classic surprise:

```julia
using Sturm

Sturm.Ry(2π) ≈ Sturm.NEG_I   # => true
Sturm.Ry(2π) ≈ Sturm.I2      # => false
Sturm.Ry(4π) ≈ Sturm.I2      # => true
```

Rotating a spin-½ system by a full turn does not bring it back. It takes two
full turns. This is spinor 4π-periodicity — a real, experimentally confirmed
property of half-integer spin, not a numerical artefact and not a convention to
be normalised away. A test asserting `Ry(2π) == I` would be asserting wrong
physics.

It also matters practically: `ctrl(Ry(2π))` is a genuine controlled-`−I`, which
by the section above is a real operation.

## `==` and `≈` mean different things

This is the sharpest everyday edge in the kernel, because both return a `Bool`
and nothing stops you picking the wrong one.

- **`==` is exact structural equality.** Same fields, same values.
- **`≈` is the physically meaningful comparison.** For process values that is
  *double-cover equality*: a quaternion and its negation, with the phase
  shifted by π, describe the same operation, so `(q, φ)` and `(−q, φ+π)` are
  equal under `≈` and different under `==`.

```julia
using Sturm

Sturm.H ∘ Sturm.H ≈ Sturm.I2    # => true
Sturm.H ∘ Sturm.H == Sturm.I2   # => false
Sturm.H ∘ Sturm.H
# => Sturm.U2(-1.0000000000000002, 0.0, 0.0, 0.0, 3.141592653589793)
```

`H` squared lands on `(−1, 0, 0, 0, π)`. That is the *other representative* of
`+I` — the same operation, written the other way round. Exactly right, and
`==` cannot see it.

The same trap in the other direction:

```julia
using Sturm

Sturm.adjoint(Sturm.X) == Sturm.X   # => false
Sturm.adjoint(Sturm.X) ≈ Sturm.X    # => true
```

`X` is self-adjoint as an operator, but its adjoint has a negated phase field,
so `==` says no. **Rule of thumb: if you are asking a question about physics,
use `≈`. `==` is for asking whether two values are literally the same object.**

Floating-point laws compare with `≈`, always.

## `ctrl` is the only place controlled operations are built

Every major quantum framework has shipped a controlled-decomposition phase bug.
Cirq, Qiskit and pytket each carried a global-phase field in their gate
representation and *still* had these bugs survive for years, in codebases with
large test suites and expert maintainers.

The reason is not carelessness. It is that a framework with gates has dozens of
places that build controlled circuits — a decomposition here, a synthesis pass
there, a peephole rewrite somewhere else — and the phase bug can live in any
one of them, each individually plausible. Testing the uncontrolled gate cannot
find it, and testing the controlled one requires knowing to look.

Sturm's answer is to make the surface area one function:

- **`Sturm.ctrl` is the single construction site for controlled operations,
  system-wide.** A build-time check greps the source tree and fails if any file
  other than the kernel's control module so much as names the constructor. If
  `ctrl` is right, controlled lowering is right everywhere, because there is
  nowhere else.
- **The surface funnels into it.** `when(q) do … end` streams its body through
  `ctrl`; there is no other path, because there are no gates for you to
  decompose by hand.

Two structural facts fall out that are worth knowing:

**Controls are flat, not nested.** Nested controls commute, so
`ctrl(ctrl(X))` is a single two-control value rather than a control of a
control:

```julia
using Sturm

Sturm.ctrl(Sturm.ctrl(Sturm.X))
# => Sturm.Ctrl{Sturm.U2}(2, Sturm.U2(0.0, 1.0, 0.0, 0.0, 1.5707963267948966))

Sturm.nwires(Sturm.ctrl(Sturm.ctrl(Sturm.X)))
# => 3
```

**There is no catch-all method.** `ctrl` is total by having one method for each
kind of process value, and an unhandled kind is an honest `MethodError`. The
important consequence is what that *excludes*: there is no `ctrl` for a channel,
and there never will be. Controlling a measurement is not a thing you can do,
and the absence of a method says so for free:

```julia
using Sturm

Sturm.ctrl(Sturm.bit_flip(0.1))
```

```
MethodError: no method matching ctrl(::Sturm.KrausFamily{1, 2, 8})
Closest candidates are:
  ctrl(::Sturm.Perm)
  ctrl(::Sturm.U2)
  ctrl(::Sturm.Ctrl)
  …
```

That is the same law you meet at the surface as "no measurement inside a `when`
body" — see [the seven constructs](seven_constructs.md).

There is one happy special case. A reversible classical permutation
(`Sturm.Perm`) has no phase freedom at all, and `ctrl` of one is *another
permutation* — the classical-reversible corner is closed under control, so
nothing new has to be constructed and there is no phase to get wrong.

That closure is why a compiled [`oracle`](../howto/write_oracles.md) composes
with `when` for free, with no new controlled-lowering code anywhere.

## Why Choi comparison is not a correctness criterion

`Sturm.same_channel(a, b)` compares two channels at the level of their
canonical matrix representation. It is the right tool for asking "do these two
descriptions denote the same physical map?", and it is deliberately blind to
two things: the arbitrary freedom in how a channel is factored, and global
phase.

That second blindness is why it is **barred** from one specific job: checking
that an optimisation rewrote a process value correctly. Re-read the very first
demonstration on this page —

```julia
Sturm.same_channel(Sturm.channel(Sturm.NEG_I), Sturm.channel(Sturm.I2))
# => true
```

— and notice that a rewrite which dropped a factor of `−1` would pass. Then the
value gets controlled somewhere downstream and the dropped phase becomes
observable. That is, precisely and exactly, the industry bug described above,
reintroduced through the test suite instead of the code.

So Sturm's optimisation passes are checked two ways at once: the rewritten
value must match *as a representative* (phase included), **and** its controlled
form must match at the channel level. Both, for every registered pass, or the
build fails.

Two related tools with the same warning label:

- **`Sturm.classicalise`** produces a channel's classical shadow, and is even
  blinder — `classicalise(channel(I2))` and `classicalise(channel(Z))` are
  identical, on purpose. Never a channel-equivalence test.
- **`Sturm.same_channel` is a named function, never `Base.isapprox`.** Building
  the comparison matrix costs exponential work in the wire count; that must not
  hide behind a `≈`.

## Views unwrap, processes compose

One more phase-adjacent rule, because its failure mode is a sign error.

`dual` is a view — a way of *addressing* a register. Sturm lowers it by
unwrapping the wrapper, not by applying the basis transform. That matters
because the transform in question is a Fourier transform, and applying one
twice is not the identity but the parity map. An implementation that lowered a
double `dual` by applying the transform twice would negate every integer, and
the bug would surface as silent sign errors inside phase estimation.

The signature of that bug — integer negation under double duals — is written
down in the source as the thing not to do. See
[views and duality](views_and_duality.md).

## Where next

- [The seven constructs](seven_constructs.md) — why the surface has no gates.
- [Views and duality](views_and_duality.md) — the other half of the phase
  story.
- [Common gotchas](gotchas.md) — `==` vs `≈` and friends, as symptoms.
- [Reference: the kernel](../reference/kernel.md) — `U2`, `Perm`, `ctrl`, and
  the named constants.
- [Reference: channels](../reference/channels.md) — `same_channel`,
  `choi_matrix`, and the channel IR.
