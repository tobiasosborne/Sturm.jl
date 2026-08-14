# Shor's order finding

**Goal.** Run the quantum part of Shor's algorithm — finding the
multiplicative order of a number modulo `N` — and see how a probabilistic
quantum measurement is turned into an exact, verified integer.

**Prerequisites.** [Installation](../getting_started/installation.md) and
[Deutsch–Jozsa and Bernstein–Vazirani](deutsch_jozsa.md) for the register-dual
readout. Bennett is loaded through the modular-arithmetic path, so keep
`using Bennett` alongside `using Sturm`.

**Time.** About twenty minutes, plus patience — the quantum runs on this page
take minutes of wall-clock simulation each.

```julia
using Sturm, Bennett
using Random
```

---

## Two sentences of number theory

Fix a modulus `N` and a base `a` coprime to it. The powers `a, a², a³, …`
eventually come back to `1`; the smallest exponent `r` with `aʳ ≡ 1 (mod N)`
is the **order** of `a`. Finding `r` is the one step of Shor's factoring
algorithm that a classical computer cannot do quickly, and everything else in
Shor's algorithm — the reduction from factoring to order finding, and the
extraction of a factor from `r` — is ordinary number theory you could do by
hand.

That is the whole background. `shor_order` does the hard step.

---

## Stage 1 — the cases with no quantum work

`shor_order(a, Val(N))` is careful about the situations where the answer is
already known. Order 1 short-circuits:

```julia
shor_order(1,  Val(15))    # => 1
shor_order(16, Val(15))    # => 1     (16 ≡ 1 mod 15)
```

And if `a` shares a factor with `N`, there is no order to find — but you have
just found a factor, which was the point of the exercise:

```julia
shor_order(6, Val(15))
# => ERROR: NonCoprimeBaseError: gcd(6, 15) = 3 ≠ 1 — the base shares a factor
# =>   with the modulus, so 3 is a nontrivial factor of 15 (found classically).
# =>   No order to find (Shor 1995, p.15 reduction).
```

The exception carries the factor. This is not an error condition that got
dressed up; it is Shor's own classical shortcut, and the message says which
branch of the algorithm you landed in.

Notice these run outside any context. No quantum resources were touched.

---

## Stage 2 — a real run

Now something the classical shortcut cannot answer. The order of `2` modulo
`5` is `4`, because `2, 4, 8≡3, 16≡1`:

```julia
Sturm.eager(23; rng = MersenneTwister(0xA1)) do ctx
    shor_order(2, Val(5))
end
# => 4
```

More, across three moduli. Each was run as
`Sturm.eager(cap; rng = MersenneTwister(seed)) do ctx; shor_order(a, Val(N)) end`:

| call | capacity | result | true order | wall clock |
|---|---|---|---|---|
| `shor_order(2, Val(3))` | 16 | 2 | 2 | 258 s |
| `shor_order(2, Val(5))` | 23 | 4 | 4 | 44 s |
| `shor_order(3, Val(5))` | 23 | 4 | 4 | 89 s |
| `shor_order(4, Val(5))` | 23 | 2 | 2 | 58 s |
| `shor_order(3, Val(7))` | 23 | 6 | 6 | 146 s |

Every entry in the "true order" column is checkable in one line of classical
Julia — `k = 1; while powermod(a, k, N) != 1; k += 1; end` — which is exactly
how it was produced. The timings are from a laptop with several other
simulations running; treat them as an order of magnitude, not a benchmark.
Note that they do not track `N`: the number of quantum samples the driver
needs before it can *prove* an answer varies from run to run.

---

## Stage 3 — what actually happens inside

There are two halves, and the split is the interesting part.

**The quantum half is one experiment**, run once per sample and returning a
single integer. It is written in surface code, and you can read it in
`src/library/shor.jl`: a phase register `k` of `2W` wires is put into equal
superposition with `superpose!`; a work register `y = QMod{N}(1)` holds a value
modulo `N`; then a ladder of controlled multiplications,

```julia
# a fragment from the implementation, for reading
when(k[j]) do
    mulmod!(y, c)          # y ↦ c·y mod N, in place
end
```

with `c` squared classically between steps; and finally `BigInt(dual(k))` —
the phase register read in its **register dual**, the Fourier basis of the
integers mod `2^{2W}`. That readout is the one from Deutsch–Jozsa, and here it
is the right one: the information really is encoded across the whole register
as a periodic phase, not bit by bit.

The work register `y` is never measured. It is a local; it is traced away when
the region ends. That trace is not an implementation detail you could optimise
out — it is *why the algorithm works*. Discarding `y` is what leaves `k`
holding a clean periodic phase instead of a state entangled with the
multiplication history.

**The classical half is exact.** One sample is a noisy estimate of `s/r` for
an unknown `s`, so `shor_order` takes samples until it can prove an answer:
continued fractions to extract a candidate denominator, `lcm` accumulation
across samples, `powermod` to *verify* that the candidate really is an
exponent that works, and a prime-stripping descent to make it minimal. All in
`BigInt`, no floating point anywhere.

The consequence is worth stating plainly: **every value `shor_order` returns
is exact and verified.** It never returns a multiple of the order, never
returns a plausible-looking wrong answer. If the samples do not settle within
`max_samples` (32 by default) it throws `OrderFindingFailure` instead.

---

## Honest limits

**The simulated sizes are small, and here is why.** The phase register alone
is `2W` wires where `W = ndigits(N-1; base=2)`, plus the `W`-wire work
register, plus scratch for the compiled modular multiplication. Every wire
doubles the state vector, so the capacity numbers on this page — 16, 23 — are
already tens of megabytes to a gigabyte of amplitudes. `N = 3, 5, 7` run
exactly, and are what this page shows. The textbook `N = 15` needs a wider
phase register and a wider compiled multiplier on top of it; we did not run
it, and the growth above is why. No amount of cleverness in Sturm changes
that — it is the cost of simulating a quantum computer on a classical one,
not a limitation of the implementation.

If you came here hoping to factor something, that is the honest answer. This
is a correct implementation at demonstration scale.

- **`shor_order` is order finding, not factoring.** The reduction to
  factoring — pick a random `a`, find `r`, hope `r` is even and
  `a^{r/2} ≢ −1`, take `gcd(a^{r/2} ± 1, N)` — is classical and is not
  wrapped for you.
- **Runs take minutes.** Not because of the classical post-processing, which
  is instant, but because each phase sample is a full statevector simulation
  over `3W` wires, and the driver may need several samples.
- **`W` is derived from `N`, never passed.** You cannot hand it a width
  inconsistent with the modulus, which removes a whole class of setup bug.
- **`max_samples` is a real bound.** Thirty-two uninformative samples in a row
  and it gives up loudly.
- **This is not the *only* implementation choice.** The file that implements
  it is normative in the design spec and is deliberately not refactored for
  cleverness.

---

## What you learned

- The order of `a` mod `N` is the hard step of factoring; `shor_order` is that
  step.
- The classical shortcuts (order 1, shared factor) short-circuit before any
  quantum work, and a shared factor is reported as a *result*, not a failure.
- The quantum kernel is a superposed phase register, a ladder of
  `when`-controlled `mulmod!` calls, and a register-dual readout.
- Discarding the work register is load-bearing physics, not cleanup.
- The classical driver turns noisy samples into a verified exact integer, or
  throws.

## Where next

- [Grover search](grover.md) — the other flagship, with a very different
  readout.
- [Views and duality](../explanation/views_and_duality.md) — the register dual
  as a Fourier transform, and why it is the right readout here.
- [Contexts and scope](../explanation/contexts_and_scope.md) — why the traced
  work register makes the algorithm work.
- [Library reference](../reference/library.md) — `shor_order`, `mulmod!`,
  `QMod`, and the error types.

**Physics source.**
[Shor order finding](https://github.com/tobiasosborne/Sturm.jl/blob/main/docs/physics/shor_order_finding.md) — the phase-estimate
structure, the continued-fraction bound, and the classical reduction.
