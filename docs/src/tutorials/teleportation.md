# Teleportation

**Goal.** Move an unknown qubit from one register to another using nothing but
a shared entangled pair and two bits of correction — and then check that what
you built really is the identity channel, not a convincing imitation of one.

**Prerequisites.** [Installation](../getting_started/installation.md) (a built
Orkan; no Bennett needed for this page) and
[Your first program](../getting_started/first_program.md). You should
recognise `QBool`, `Bool(q)`, `⊻=`, `not!`, `dual`, and `when`.

**Time.** About twenty minutes. Every code block on this page was run as
written; the `# =>` comments are the real output.

This is the page where Sturm's central claim earns its keep. Teleportation is
the classic first "real" quantum protocol, and it is also the classic first
place where a wrong implementation looks right. This project shipped one. We
will build the correct protocol in stages, then build the broken one on
purpose, and watch a test that only looks at measurement frequencies bless
them both.

```julia
using Sturm
using Random
```

---

## Stage 1 — a shared pair

Teleportation needs a resource: two qubits prepared so that measuring either
one tells you the other. In Sturm you make one with two lines.

```julia
agree = Sturm.shots(2; N = 2000, rng = MersenneTwister(0x5EED)) do ctx
    b = QBool(0.5)          # a fair quantum coin: √½|0⟩ + √½|1⟩
    c = false ⊻ b           # xor b into a fresh false — this entangles them
    Bool(b) == Bool(c)      # measure both
end

all(agree)                  # => true
count(agree) / length(agree) # => 1.0
```

`Sturm.shots(f, capacity; N)` runs `f` in `N` fresh contexts and collects what
it returns — the sanctioned way to get a distribution out of a program that
measures. `capacity` is the number of qubits the context can hold.

Two things worth pausing on. `QBool(0.5)` is a **preparation cast**: it names
a classical number (a probability) and hands back a live quantum handle. And
`false ⊻ b` is the ordinary Julia xor operator, read as "make a fresh
`false`, then xor `b` into it". Because `b` is in superposition, the result is
not a copy of a bit — it is the entangled pair
`√½|00⟩ + √½|11⟩`. Half the time both read `0`, half the time both read `1`,
and never one of each:

```julia
both = Sturm.shots(2; N = 2000, rng = MersenneTwister(0x5EED)) do ctx
    b = QBool(0.5); c = false ⊻ b
    Bool(b) && Bool(c)
end
count(both) / length(both)  # => 0.5
```

There is no `CNOT` here, and there was never going to be. Entanglement in
Sturm is *composed* out of the action family (`⊻=`, `not!`), not summoned by
naming a gate.

---

## Stage 2 — the deferred protocol

Now the protocol. Alice holds an unknown qubit `ψ` and half of a pair; Bob
holds the other half. Alice mixes `ψ` into her half; Bob applies two
corrections. Classically you would measure Alice's qubits and send Bob two
bits. Coherently, you skip the measurement and let `when` do the conditioning:

```julia
function teleport(ψ::QBool)
    b = QBool(0.5)
    c = false ⊻ b            # the shared pair: b is Alice's, c is Bob's
    b ⊻= ψ                   # mix the payload into Alice's half

    when(b) do               # correction 1: flip Bob's qubit if Alice's is 1
        not!(c)
    end
    when(dual(ψ)) do         # correction 2: flip Bob's qubit *in the dual view*
        not!(dual(c))        #   if the payload reads 1 in the conjugate basis
    end
    return c                 # ψ and b are locals: discarded when the scope ends
end
```

`when(q) do … end` is **coherent control**: the body runs on the branch where
`q` is `1`, with no collapse and no classical bit anywhere. `dual(q)` is the
**conjugate view** — the same register addressed in the Fourier-conjugate
basis, the basis where `|+⟩` and `|−⟩` are the two definite values. The two
corrections are the same correction seen from the two halves of a
Fourier-dual pair, which is exactly why the surface spells them the same way.

Does it work? Send in the two definite values and read them back:

```julia
Sturm.eager(4) do ctx; Bool(teleport(QBool(false))) end   # => false
Sturm.eager(4) do ctx; Bool(teleport(QBool(true)))  end   # => true
```

Now send in the two definite values of the *other* basis. `plus()` is `|+⟩`
and `minus()` is `|−⟩`, and `Bool(dual(c))` reads the output in that same
conjugate basis:

```julia
Sturm.eager(4) do ctx; Bool(dual(teleport(plus())))  end  # => false
Sturm.eager(4) do ctx; Bool(dual(teleport(minus()))) end  # => true
```

Four for four, deterministically. And a state that is neither — a qubit with
a 30 % chance of reading `1` — arrives with its probability intact:

```julia
outs = Sturm.shots(4; N = 4000, rng = MersenneTwister(0xC0FFEE)) do ctx
    Bool(teleport(QBool(0.3)))
end
count(outs) / length(outs)   # => 0.3065
```

**What physically happened.** Nothing was copied — no-cloning forbids it, and
notice that `ψ` never appears in the return value. `ψ` and `b` are locals of
`teleport`; when the function's scope ends they are traced away, which is the
physical act of forgetting them. The information did not travel through the
two `when` bodies either; it was already spread across the pair the moment
`b ⊻= ψ` ran. The corrections just undo the randomisation.

---

## Stage 3 — the same protocol with classical branching

The deferred version never measures. The textbook version does: Alice
measures both her qubits, phones Bob two bits, and Bob acts on them. Sturm
spells classical branching on a measured outcome with `cases`:

```julia
function teleport_cases(ψ::QBool)
    b = QBool(0.5)
    c = false ⊻ b
    b ⊻= ψ

    m_phase = Bool(dual(ψ))          # measure the payload in the conjugate basis
    m_value = Bool(b)                # measure Alice's half in the ordinary one

    cases(m_value) do; not!(c) end       # X correction, conditioned on a record
    cases(m_phase) do; not!(dual(c)) end # Z correction, in the dual view
    return c
end
```

```julia
Sturm.eager(4) do ctx; Bool(teleport_cases(QBool(false))) end  # => false
Sturm.eager(4) do ctx; Bool(teleport_cases(QBool(true)))  end  # => true
Sturm.eager(4) do ctx; Bool(dual(teleport_cases(plus())))  end # => false
Sturm.eager(4) do ctx; Bool(dual(teleport_cases(minus()))) end # => true

outs = Sturm.shots(4; N = 4000, rng = MersenneTwister(0xC0FFEE)) do ctx
    Bool(teleport_cases(QBool(0.3)))
end
count(outs) / length(outs)   # => 0.307
```

`cases` and `when` look similar and are not interchangeable. `when` conditions
on a **live quantum register**, coherently, keeping every branch. `cases`
conditions on an **already-measured outcome**, classically. Handing a live
register to `cases` is rejected with a message telling you to measure first;
measuring *inside* a `when` body is rejected too, because a measurement under
coherent control is not a thing that exists.

Notice `m_phase = Bool(dual(ψ))`. The measurement cast consumes its argument —
after that line `ψ` is dead, and touching it again is a loud error rather than
a silent read of a stale handle. That is the same no-cloning rule, enforced by
the type system rather than by your memory.

> **A portability note.** Under an eager context `Bool(q)` hands you a real
> Julia `Bool`, so `m_value && not!(c)` would work just as well. Under a
> density-matrix context it hands you a *record token* instead, and `&&` on a
> token is a type error. `cases` is the spelling that means the same thing in
> both. See [choosing a context](../getting_started/choosing_a_context.md).

---

## Stage 4 — the bug that passed its tests

Here is the version this project actually shipped, in its first incarnation.
Everything is the same except that the conjugate-basis correction is missing:

```julia
function teleport_broken(ψ::QBool)      # WRONG — for illustration only
    b = QBool(0.5)
    c = false ⊻ b
    b ⊻= ψ
    when(b) do
        not!(c)
    end
    return c                             # no dual-view correction
end
```

Test it the way a reasonable person tests it — send in `0`, send in `1`, check
what comes out:

```julia
Sturm.eager(4) do ctx; Bool(teleport_broken(QBool(false))) end  # => false
Sturm.eager(4) do ctx; Bool(teleport_broken(QBool(true)))  end  # => true
```

Green. Both values survive the trip. Ship it.

Now send in `|+⟩` and read the output in the conjugate basis, where the
correct protocol answered `false` every single time:

```julia
broken = Sturm.shots(4; N = 2000, rng = MersenneTwister(0xB1B)) do ctx
    Bool(dual(teleport_broken(plus())))
end
count(broken) / length(broken)  # => 0.523      a fair coin — the answer is gone

good = Sturm.shots(4; N = 2000, rng = MersenneTwister(0xB1B)) do ctx
    Bool(dual(teleport(plus())))
end
count(good) / length(good)      # => 0.0        deterministic, as it should be
```

The broken protocol teleports *classical* bits perfectly and destroys
everything else. It is a fax machine wearing a quantum protocol's clothes.

This is not a hypothetical. The first version of Sturm shipped exactly this
bug, and its test suite was green, because the test only ever looked at
outcome frequencies in the computational basis — and a classical
copy-the-bit-and-resend gives *identical* frequencies there. A test state
prepared a quarter turn out of phase came back reading a 50/50 coin in the
basis where it should have been deterministic, and nothing in the suite
noticed. What made the bug possible
was that the old surface language had no way to *say* `Bool(dual(ψ))`; there
was no conjugate-basis readout to forget to write. The fix was a language
change, not a patch.

---

## Stage 5 — the real check: it is a channel identity

Frequencies in one basis are not evidence. Frequencies in two bases are better
evidence. But the thing you actually want to claim is stronger than any
sampling statement:

> `teleport` and "do nothing" are the **same channel**.

A channel is what a function *is* in this language — the complete input/output
behaviour, including how it treats superpositions and entanglement with things
outside the function. Two channels are equal or they are not; there is a
matrix that settles it (the Choi matrix), and comparing those matrices is the
project's standard of proof.

The comparison harness lives on the test side, at `test/choi.jl` — it is
deliberately not part of the shipped library, because it reaches below the
surface language to build its probe. If you have the repository checked out
you can run it directly. Including the file also runs its own nine-assertion
self-test, so expect a `Test Summary` line before your own output.

```julia
using LinearAlgebra
include(joinpath(pkgdir(Sturm), "test", "choi.jl"))

J = choi(teleport, 1; cap = 4)
round.(real.(J); digits = 4)
# => 4×4 Matrix{Float64}:
# =>  0.5  0.0  0.0  0.5
# =>  0.0  0.0  0.0  0.0
# =>  0.0  0.0  0.0  0.0
# =>  0.5  0.0  0.0  0.5

bell = ComplexF64[1 0 0 1; 0 0 0 0; 0 0 0 0; 1 0 0 1] ./ 2   # the identity channel
J ≈ bell                       # => true
J ≈ Diagonal(diag(J))          # => false   — off-diagonals present
```

Those two corner entries, the `0.5`s off the diagonal, are the whole ball
game. They are the part of the channel that remembers phase. The `cases`
version passes the identical test, and lands on the identical matrix:

```julia
J2 = choi(teleport_cases, 1; cap = 4)
J2 ≈ bell                      # => true
J2 ≈ J                         # => true
```

Two protocols, one coherent and one measurement-based, that are literally the
same channel. That equality is the theorem; the two implementations are just
two ways of writing it down.

And the broken one:

```julia
J3 = choi(teleport_broken, 1; cap = 4)
round.(real.(J3); digits = 4)
# => 4×4 Matrix{Float64}:
# =>  0.5  0.0  0.0  0.0
# =>  0.0  0.0  0.0  0.0
# =>  0.0  0.0  0.0  0.0
# =>  0.0  0.0  0.0  0.5

J3 ≈ bell                      # => false
J3 ≈ Diagonal(diag(J3))        # => true    — nothing but the diagonal
```

You can *see* it. The broken protocol teleported the diagonal. The corners are
gone. No amount of sampling in the computational basis would ever have shown
you that, and one look at the matrix shows you nothing else.

---

## Honest limits

- `choi` is a test harness, not a public API. It is exact but dense: it builds
  the full density matrix of a `cap`-qubit system, so memory grows as
  `4^cap`. Six or seven wires is the practical ceiling. It is the right tool
  for a law, the wrong tool for a big program.
- The eager context samples. Every number on this page that came from
  `Sturm.shots` is a finite-sample estimate with a fixed seed; rerun with a
  different `rng` and the last digit moves. The deterministic `# =>` values
  (`false`, `true`) and the Choi matrices are exact.
- `teleport` here is a one-qubit channel. Nothing on this page addresses
  teleporting a wide register, or teleportation through a noisy pair.

---

## What you learned

- Entanglement is composed from `QBool(0.5)` and `⊻`, not from a gate name.
- `when` conditions coherently on a live register; `cases` conditions
  classically on a measured record. They are different operations and the
  language keeps them apart.
- `dual(q)` is the conjugate view — the second basis you must check, and the
  construct whose absence caused a real shipped bug.
- Measurement casts consume. A dead handle errors loudly instead of lying.
- The claim "this function is the identity" is a statement about channels, and
  it is checkable as a matrix equality rather than a sampling argument.

## Where next

- [Deutsch–Jozsa and Bernstein–Vazirani](deutsch_jozsa.md) — turn an ordinary
  Julia predicate into a quantum oracle and query it once.
- [Views and duality](../explanation/views_and_duality.md) — why `dual` is an
  addressing mode rather than an operation, and what it swaps.
- [Functions are channels](../explanation/functions_are_channels.md) — the
  idea Stage 5 is testing.
- [The seven surface constructs](../explanation/seven_constructs.md) — the
  complete vocabulary; this page used five of them.
- [Gotchas](../explanation/gotchas.md) — including the traps around `dual` and
  op-assignment that this page carefully stepped over.
