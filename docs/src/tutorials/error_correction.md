# Error correction

**Goal.** Wrap a noise channel in a code and compute, exactly, what noise the
protected qubit actually sees — then watch the same wrapper make a *different*
kind of noise strictly worse, and understand why that is the honest outcome.

**Prerequisites.** [Installation](../getting_started/installation.md) and
[Your first program](../getting_started/first_program.md). No Bennett needed.
Reading [Teleportation](teleportation.md) first will help: this page reuses
the idea that a program *is* a channel.

**Time.** About twenty-five minutes. Every block was run as written; `# =>`
comments are real output, and every number here is exact — nothing on this
page is sampled.

```julia
using Sturm
using LinearAlgebra
using Sturm: bit_flip_code, Protect, physical_iid, bit_flip, phase_flip,
             classicalise, NoRecovery, nphysical, nlogical,
             distance, verify_distance
```

Those names are `public` but not exported: reachable as `Sturm.something`, and
importable by name as above, but never dumped into your namespace by a bare
`using Sturm`. The layering is deliberate — what a *program* does to itself is
exported; what an *experimenter* does to a program stays behind the module
name.

---

## The idea: correction is a function on channels

Most introductions to quantum error correction start with circuits: an encoder,
a syndrome measurement, a lookup table, a recovery gate. Sturm starts one level
up.

Fix a code. Then "protect with this code" is a *function that takes a channel
and returns a channel*: hand it the physical noise your hardware suffers, and
it hands you back the effective noise the logical qubit suffers. Encoder,
syndrome extraction, decoder and recovery are all inside the function; they
are how it is implemented, not what it is.

In Sturm that function is a value you can name and call:

```julia
enc = bit_flip_code()
protect = Protect(enc)
```

`protect` is now a callable. Feed it a physical noise model, get a logical
channel. That is the whole interface.

This framing is not a Sturm invention. A map from channels to channels is a
*superchannel*, and error correction is the textbook first example of one.

---

## Stage 1 — meet the code, honestly

```julia
nphysical(enc.code)          # => 3
nlogical(enc.code)           # => 1
distance(enc.code)           # => 1
verify_distance(enc.code)    # => 1
```

Three physical qubits carry one logical qubit. And the distance is **1**, not
3.

If you have seen the three-qubit repetition code before, that number will look
like a typo. It is not, and the library goes out of its way to prove it:
`distance` reports what the code *declares*, `verify_distance` brute-forces
the true minimum weight of a logical operator, and they agree.

Here is why. The code's stabilizers are `Z₁Z₂` and `Z₂Z₃`; its logical
operators are `X̄ = XXX` and `Z̄ = Z₁`. That last one is a **weight-one**
logical operator: a single `Z` on the first qubit flips the logical phase, and
because it commutes with both stabilizers, the syndrome is blank. Nothing
detects it. Nothing corrects it.

So this is a code that protects against one kind of error and is completely
blind to the other. Its name says so. It is not "the `[[3,1,3]]` code with the
distance left off"; it is a distance-1 code, and the rest of this page shows
you both halves of that fact.

---

## Stage 2 — bit-flip noise, suppressed

Build the physical noise model. `physical_iid(enc, 𝓝)` says "the same
single-qubit channel `𝓝`, independently, on each of the three physical
wires":

```julia
Φ = protect(physical_iid(enc, bit_flip(0.1)))
```

`Φ` is the logical channel. `protect` is the `Protect(enc)` value from above;
spelling it inline as `Protect(enc)(…)` means the same thing, and the rest of
this page does that. To read a number off it, `classicalise` gives the
channel's *classical shadow*: the matrix of transition probabilities between
computational-basis states. For a bit-flip channel that is exactly the flip
probability:

```julia
classicalise(Φ)[2, 1]        # => 0.028000000000000004
```

A physical flip rate of 10 % becomes a logical flip rate of 2.8 %. Sweep it,
printing the computed number next to the closed form `3p² − 2p³`:

```julia
for p in (0.01, 0.05, 0.1, 0.3, 0.5, 0.6)
    Φ = Protect(enc)(physical_iid(enc, bit_flip(p)))
    println(p, "  ", classicalise(Φ)[2, 1], "  ", 3p^2 - 2p^3)
end
# => 0.01  0.00029800000000000014  0.00029800000000000003
# => 0.05  0.007249999999999998    0.007250000000000001
# => 0.1   0.028000000000000004    0.028000000000000004
# => 0.3   0.21599999999999991     0.21600000000000003
# => 0.5   0.5000000000000003      0.5
# => 0.6   0.6480000000000001      0.6480000000000001
```

Every row matches the closed form to the last couple of bits — this is a
computed channel, not a fitted curve, and the tail digits are floating-point
noise from the density-matrix replay, not statistics. That is
majority vote, written out: the logical bit flips exactly when two or three of
the three physical qubits flipped.

Three features of that curve are worth naming.

**Below `p = ½` correction helps.** `3p² − 2p³ < p` there. At `p = 0.1` the
error rate drops by a factor of about 3.6; at `p = 0.01`, by a factor of about
34. The suppression is quadratic in `p`, which is the point of the exercise.

**At `p = ½` nothing happens.** `3(½)² − 2(½)³ = ½` exactly. A qubit that is
already maximally scrambled cannot be un-scrambled by voting.

**Above `p = ½` correction actively hurts.** At `p = 0.6` the logical rate is
`0.648`, worse than the physical `0.6`. The majority vote is confidently
wrong more often than a single qubit is. A one-sided test — "check that
protection helps" — would never have caught a sign error in the recovery
table. Checking both sides does.

The baseline for comparison is encoding and decoding with the correction
switched off:

```julia
Φ0 = Protect(enc, NoRecovery())(physical_iid(enc, bit_flip(0.1)))
classicalise(Φ0)[2, 1]       # => 0.09999999999999999
```

Exactly the physical rate, unchanged: encode, suffer, decode, no vote. All of
the improvement above came from the recovery step, not from the encoding.

---

## Stage 3 — phase noise, and the probe that cannot see it

Now run the same machinery on phase noise, which flips the *sign* of the `|1⟩`
component rather than the bit:

```julia
for p in (0.05, 0.1, 0.3)
    Φ = Protect(enc)(physical_iid(enc, phase_flip(p)))
    println(p, "  ", classicalise(Φ))
end
# => 0.05  [0.9999999999999997 3.749399456654642e-33; -1.8731406546477804e-50 0.9999999999999997]
# => 0.1   [0.9999999999999997 3.749399456654642e-33; -1.8731406546477804e-50 0.9999999999999997]
# => 0.3   [1.0 3.749399456654644e-33; -3.0080778888518096e-49 1.0]
```

The identity matrix, to floating point, at every rate — the off-diagonals are
`1e-33` and `1e-50`. If you stopped here you would report that the code
eliminates phase noise completely, at any rate, for free.

That conclusion is wrong, and the reason it is wrong is the single most
useful thing on this page.

`classicalise` is **phase-blind by construction**. It measures how often a
computational-basis state comes out as a different computational-basis state —
and a phase flip never does that. The library says so in the function's own
documentation and pins the blindness with a test: `classicalise` of the
identity channel and `classicalise` of a `Z` are deliberately equal. It is a
population probe. Populations are not the whole channel.

This is the same failure mode as the teleportation bug in
[the teleportation tutorial](teleportation.md): a measurement that looks in
one basis, blessing a protocol that destroyed the other. There it cost the
project a shipped bug. Here it would cost you a false claim about a code.

---

## Stage 4 — what phase noise actually does

To see the truth you need a coherent probe: compare channels at the Choi
level, which is what "these are the same channel" means. The harness for that
lives on the test side, at `test/choi.jl`, because it reaches below the
surface language to build its probe. Including that file also runs its own
nine-assertion self-test, so a `Test Summary` line appears before your output.

```julia
include(joinpath(pkgdir(Sturm), "test", "choi.jl"))

logical_choi(Φ) = choi(qin -> Sturm._adopt_qbool(qin.ctx,
        Sturm._replay_dm!(qin.ctx, Φ.dag, [qin.wire])[1]), 1; cap = 6)
```

Now ask whether the logical channel under physical phase noise `p` is a phase
flip at some rate `pZ`, and what that rate is. The theory says every single
`Z` is already a logical `Z̄` with a blank syndrome, so no correction ever
fires, and the logical phase flips whenever an *odd* number of the three
physical qubits did: `pZ = (1 − (1−2p)³)/2`.

```julia
for p in (0.05, 0.1, 0.3)
    Φ = Protect(enc)(physical_iid(enc, phase_flip(p)))
    pZ = (1 - (1 - 2p)^3) / 2
    println(p, "  matches: ",
            isapprox(logical_choi(Φ), Sturm.choi_matrix(phase_flip(pZ)); atol = 1e-10),
            "   pZ = ", pZ, "   pZ/p = ", pZ / p)
end
# => 0.05  matches: true   pZ = 0.13549999999999995   pZ/p = 2.709999999999999
# => 0.1   matches: true   pZ = 0.24399999999999994   pZ/p = 2.439999999999999
# => 0.3   matches: true   pZ = 0.46799999999999997   pZ/p = 1.56
```

Phase noise comes out **worse than it went in**, at every rate, by a factor
approaching 3 as `p → 0`. Not "unprotected" — amplified. You gave the noise
three independent chances to flip the logical phase instead of one.

For contrast, the same coherent probe confirms the bit-flip result exactly:

```julia
Φb = Protect(enc)(physical_iid(enc, bit_flip(0.1)))
isapprox(logical_choi(Φb), Sturm.choi_matrix(bit_flip(0.028)); atol = 1e-10)
# => true
```

That is the honest summary of this code: bit-flip rate `p ↦ 3p² − 2p³`
(better, quadratically), phase-flip rate `p ↦ (1 − (1−2p)³)/2` (worse, by up
to 3×). A real code has to handle both, which is why real codes are bigger.

---

## Stage 5 — encoding a state, and the things you cannot do to it

There is also a state-level interface. `encode_state` takes ownership of your
logical qubit and returns a code block; `decode_state` gives it back:

```julia
Sturm.eager(6) do ctx
    blk = encode_state(enc, QBool(true))
    Bool(decode_state(blk))
end
# => true
```

"Takes ownership" is literal — the handle you passed in is dead afterwards,
and using it again is an error rather than a stale read.

Now try to do something to the encoded qubit:

```julia
Sturm.eager(6) do ctx
    blk = encode_state(enc, QBool(true))
    not!(blk)                                 # WRONG — this is refused
end
# => ERROR: ArgumentError: not! on a CodeBlock is not available in M11
# => (ruling T3): shipping it would need a declared transversal X̄ gadget under
# => an explicit fault model (a bare physical X on every wire IS X̄ for the
# => bit-flip code, but blessing it as the cast spelling would silently promise
# => transversality for every code). M11 ships NO logical operations —
# => decode_state, the recovery program, and introspection are the entire block
# => surface.
```

(`M11` and `ruling T3` in that message are the project's internal names for
the milestone that built this and the decision that shaped it. They show up
verbatim in error text; the content of the message is the part in English.)

`not!`, `Bool`, `⊻=`, `dual`, `when` and `oracle` on a code block are all
refused, each with a message explaining what a correct implementation would
require. This is a design choice, not a gap someone forgot to fill. For *this*
code a physical `X` on all three wires really is a logical `X̄`, so the
operation could be shipped — but shipping it under the name `not!` would make
the same promise for every code someone adds later, including codes where it
is false. A refusal that explains itself beats an operation that is right by
accident.

---

## Honest limits

These are large and you should read them before quoting any number above.

- **This is the code-capacity model.** Encoder, decoder, syndrome extraction
  and recovery are all assumed *noiseless*, and the syndrome is *perfect*.
  Noise happens only in the one place the model puts it. Real hardware is not
  like this.

- **There is no fault-tolerance claim and no threshold claim.** "`p_L < p`
  below break-even" is a statement about the code-capacity model and nothing
  more. It does not mean the code has a threshold, and it does not mean a
  circuit built from these pieces would work.

- **The library refuses to fake the lift.** `Sturm.fault_tolerant_lift` exists
  only to say no, in detail:

  ```julia
  Sturm.fault_tolerant_lift(Φ, nothing)
  # => ERROR: ArgumentError: fault_tolerant_lift: not available — a fault-tolerant
  # => lift is NOT canonical (the code alone does not determine it), and for
  # => universal gate sets no code of distance ≥ 2 admits an all-transversal
  # => implementation (Eastin–Knill, …). Supplying one needs FIVE ingredients M11
  # => does not have: (1) a fault model; (2) a gadget set with a per-code
  # => transversality declaration; (3) a magic-state / gate-teleportation protocol
  # => for the non-transversal remainder; (4) a syndrome-extraction schedule sound
  # => under a NOISY-syndrome model (M11's recovery assumes perfect extraction —
  # => the code-capacity model); and (5) threshold accounting. File the FT epic;
  # => do not fake it here.
  ```

  None of the five exists yet, and the error says so rather than returning
  something plausible.

- **The bit-flip code is distance 1.** Said three times on this page because
  it is the number people misremember. It corrects no phase errors and
  amplifies phase noise.

- **`classicalise` caps at 3 wires** and is phase-blind; `choi` builds a dense
  matrix and caps out around 6–7 wires. Both are analysis tools for laws, not
  for large programs.

- **`bit_flip_code()` is the only code that ships.** The `StabilizerCode` and
  `CodeEncoding` types are general — six well-formedness conditions checked
  over GF(2), a syndrome table that validates itself at construction — but
  Steane, Shor and the surface code are not in the box.

---

## What you learned

- Error correction is a function from channels to channels; `Protect(enc)` is
  that function as a callable value.
- `physical_iid` builds an i.i.d. physical noise model; `classicalise` reads a
  population number off the result; the Choi comparison reads the whole
  channel.
- The three-qubit bit-flip code suppresses bit-flip noise quadratically
  (`3p² − 2p³`), breaks even at `p = ½`, and hurts above it.
- The same code *amplifies* phase noise, by up to 3×, and the population probe
  cannot see that at all. Choosing the wrong probe is how you publish a wrong
  claim.
- Operations on an encoded block are refused rather than guessed at.

## Where next

- [Teleportation](teleportation.md) — the other page where a population-only
  probe blesses a broken program.
- [Functions are channels](../explanation/functions_are_channels.md) — the
  frame that makes "a function on channels" an ordinary idea.
- [Choosing a context](../getting_started/choosing_a_context.md) — noise
  channels need a density-matrix context; a state vector cannot hold the
  result.
- [QECC reference](../reference/qecc.md) — `StabilizerCode`, `CodeEncoding`,
  `Protect`, and the recovery policies.

**Physics sources.** Correctability conditions:
[Knill & Laflamme 1997](https://github.com/tobiasosborne/Sturm.jl/blob/main/docs/physics/knill_laflamme_1997_qec_conditions.md).
Stabilizer formalism:
[Gottesman 1997](https://github.com/tobiasosborne/Sturm.jl/blob/main/docs/physics/gottesman_1997_stabilizer_codes.md). The
superchannel framing:
[Chiribella, D'Ariano & Perinotti 2009](https://github.com/tobiasosborne/Sturm.jl/blob/main/docs/physics/chiribella_2009_quantum_combs.md).
Why no code has a universal transversal gate set:
[Eastin & Knill 2009](https://github.com/tobiasosborne/Sturm.jl/blob/main/docs/physics/eastin_knill_2009_no_universal_transversal.md).
The `3p² − 2p³` derivation:
[repetition-code effective noise](https://github.com/tobiasosborne/Sturm.jl/blob/main/docs/physics/repetition_code_effective_noise.md).
