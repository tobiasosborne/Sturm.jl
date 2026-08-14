# Deutsch–Jozsa and Bernstein–Vazirani

**Goal.** Take a function you already wrote, in ordinary Julia, and ask a
quantum question about it — with one query instead of the many a classical
computer would need.

**Prerequisites.** [Installation](../getting_started/installation.md),
including the **Bennett** setup: these algorithms go through the oracle
bridge, so you need `using Bennett` alongside `using Sturm`. Also
[Your first program](../getting_started/first_program.md).

**Time.** About twenty minutes. Every block was run as written; `# =>`
comments are real output.

```julia
using Sturm, Bennett
using Random
```

If you forget the `using Bennett`, the first `oracle(...)` call tells you so
by name rather than failing somewhere downstream.

---

## The setup

Suppose someone hands you a function `f` on 3-bit inputs and promises it is
either **constant** (the same answer for all eight inputs) or **balanced**
(true for exactly four of them). Which is it?

Classically you have to look. One input tells you nothing. Two might tell you
"balanced" if they disagree, but if they agree you keep going, and in the
worst case you check five of the eight before you can be sure. In general:
`2^{N-1} + 1` queries.

Quantumly: one. That is the Deutsch–Jozsa theorem, and it is what we are about
to run.

---

## Stage 1 — write the function in ordinary Julia

Nothing quantum here. These are Julia predicates you could call from the REPL:

```julia
all_zero(x)   = false          # constant
all_one(x)    = true           # constant
parity_lsb(x) = isodd(x)       # balanced: true for half the inputs
half_split(x) = x >= 0x04      # balanced: true for the top half
```

`isodd`. Not "the Z-parity oracle", not a circuit, not a gate list. `isodd`.

---

## Stage 2 — the algorithm, in seven lines

```julia
function deutsch_jozsa(f, ::Val{N}) where {N}
    x = QInt{N}(0)           # an N-wire register holding 0
    superpose!(x)            # put it in an equal superposition of all 2^N values
    b = minus()              # an ancilla in |−⟩

    b ⊻= oracle(f, x)        # ONE query: xor f(x) into b

    return Int(dual(x)) == 0 # read x in the conjugate basis; all-zero ⇔ constant
end
```

Run it:

```julia
Sturm.eager(18) do ctx; deutsch_jozsa(all_zero,   Val(3)) end   # => true
Sturm.eager(18) do ctx; deutsch_jozsa(all_one,    Val(3)) end   # => true
Sturm.eager(18) do ctx; deutsch_jozsa(parity_lsb, Val(3)) end   # => false
Sturm.eager(24) do ctx; deutsch_jozsa(half_split, Val(3)) end   # => false
```

And at four bits:

```julia
Sturm.eager(18) do ctx; deutsch_jozsa(all_zero,   Val(4)) end   # => true
Sturm.eager(18) do ctx; deutsch_jozsa(parity_lsb, Val(4)) end   # => false
```

Correct in every case, from a single `⊻=`.

**You did not rewrite your function.** That is the beat worth stopping on.
`parity_lsb` is `isodd(x)`. You did not transcribe it into gates, you did not
decompose it into Toffolis, you did not look up a reversible adder. You passed
the Julia function to `oracle` and the bridge compiled it — through Bennett,
which extracts the compiled code and turns it into a reversible permutation,
with every scratch bit provably returned to zero.

**What `⊻=` did.** `b ⊻= oracle(f, x)` is the same operator as `a ⊻= b`
between two registers; the oracle just supplies a fancier right-hand side. It
means `|x⟩|b⟩ ↦ |x⟩|b ⊕ f(x)⟩`, with `x` preserved. Because `b` was prepared
in `|−⟩`, the xor turns into a *sign*: the amplitude of every `x` with
`f(x) = 1` gets multiplied by `−1`, and `b` comes out exactly as it went in,
disentangled. The information landed on `x` as a pattern of signs. This is
phase kickback, and in Sturm it is not a special mechanism — it is what `⊻=`
does when the target happens to be `|−⟩`.

**What `Int(dual(x))` did.** `dual(x)` is the conjugate view of the register:
the same wires, addressed in the Fourier-conjugate basis. Reading a sign
pattern requires reading in the basis where signs are values, and that is what
the dual view is for. For a constant `f`, every amplitude got the same sign,
so nothing changed and the register is still exactly where `superpose!` put
it — which reads as all-zeros in the conjugate basis. For a balanced `f`, the
signs interfere and it cannot be.

Note `b` never appears again. It is a local; when the function's scope ends it
is discarded, silently and with no effect on anything, because it was left
disentangled.

---

## Stage 3 — Bernstein–Vazirani: read a secret in one query

Same machine, harder question. Now `f(x) = s · x mod 2` for some hidden
`N`-bit string `s`: the parity of the bits of `x` that `s` selects. Find `s`.

Classically you need `N` queries — feed in `1, 2, 4, …` and read one bit of
`s` each time. Quantumly, one.

The functions, again ordinary Julia:

```julia
bit(x, k) = (x >> k) & 0x01
s001(x) = bit(x, 0x00) == 0x01                        # secret 0b001 = 1
s101(x) = xor(bit(x, 0x00), bit(x, 0x02)) == 0x01     # secret 0b101 = 5
s110(x) = xor(bit(x, 0x01), bit(x, 0x02)) == 0x01     # secret 0b110 = 6
```

The algorithm is the Deutsch–Jozsa program with one line changed:

```julia
function bernstein_vazirani(f, ::Val{N}) where {N}
    x = QInt{N}(0)
    superpose!(x)
    b = minus()

    b ⊻= oracle(f, x)                        # the same single query

    bits = [Bool(dual(x[i])) for i in 1:N]   # PER-WIRE duals, wire 1 first
    return evalpoly(2, reverse(bits))
end
```

```julia
Sturm.eager(22) do ctx; bernstein_vazirani(s001, Val(3)) end   # => 1
Sturm.eager(22) do ctx; bernstein_vazirani(s101, Val(3)) end   # => 5
Sturm.eager(22) do ctx; bernstein_vazirani(s110, Val(3)) end   # => 6
```

The secret, exactly, from one query. `x[i]` borrows wire `i` of the register
as a single-qubit handle; `Bool(dual(x[i]))` reads that one wire in the
conjugate basis.

---

## Stage 4 — the line you cannot copy-paste

Look at the two readouts side by side:

```julia
# fragments, for comparison — not a runnable block
Int(dual(x))                            # Deutsch–Jozsa: the REGISTER dual
[Bool(dual(x[i])) for i in 1:N]         # Bernstein–Vazirani: the PER-WIRE duals
```

They look like the same idea at two granularities. They are not the same
transform. The register dual is the Fourier transform of the integers mod
`2^N`. The per-wire duals are `N` independent two-element Fourier transforms —
one per bit. Different groups, different unitaries, different answers.

Reach for the Deutsch–Jozsa readout on a Bernstein–Vazirani state and you do
not get the secret. You get a spread:

```julia
outs = Sturm.shots(20; N = 400, rng = MersenneTwister(0xD1)) do ctx
    x = QInt{3}(0)
    superpose!(x)
    b = minus()
    b ⊻= oracle(s101, x)          # secret is 5
    Int(dual(x))                  # WRONG readout for this problem
end
```

The frequencies over 400 shots, against the exact distribution:

| outcome | measured | exact |
|---|---|---|
| 0 | 0.0 | 0 |
| 1 | 0.0825 | 0.073 |
| 2 | 0.0 | 0 |
| 3 | 0.405 | 0.427 |
| 4 | 0.0 | 0 |
| 5 | 0.43 | 0.427 |
| 6 | 0.0 | 0 |
| 7 | 0.0825 | 0.073 |

The even outcomes vanish exactly, and the odd ones split four ways; `5` shows
up often, but so does `3`, and one shot cannot tell you which is the secret.
(The measured column is 400 seeded shots, so it wobbles by a couple of points;
the zeros are exact.) The
project's test suite pins this distribution deliberately, as a negative
control — because "it worked on the secrets that happen to be palindromes" is
exactly the kind of accident that ships.

The lesson generalises past this example: in Sturm, `dual` is an *addressing
mode*, and which register you address it on is part of the physics. Addressing
a whole register and addressing its wires one at a time are different
questions.

---

## Honest limits of the oracle bridge

`oracle(f, x)` compiles a real Julia function, which means it inherits real
limits. All of these fail **loudly, at the `oracle(...)` call**, not silently
and not downstream:

- **Fixed-size computation only.** Functions needing an unbounded loop, or a
  loop whose termination condition cannot be uncomputed, are rejected.
- **`count_ones` does not compile.** This bites, because popcount is the
  natural way to write a parity oracle. Spell it out with `xor` and shifts, as
  above.
- **Width 1 to 64.** That is the bridge's ceiling.
- **One input register, one scalar output.** Multi-register oracles are
  designed for and not yet built.
- **The target must be a separate register.** Aliasing the target into the
  input — `x[1] ⊻= oracle(f, x)` — is refused.
- **An undersized target is refused, not truncated.** If `f`'s output needs
  more bits than the target has, you get an error rather than a quietly
  mangled state.

And the practical one, which is not a bridge limit but will shape what you can
run: **compiled oracles use scratch wires**, and scratch wires cost memory. The
`Sturm.eager(cap)` capacity in each example above is the smallest that fits;
raise it and the state vector doubles per wire. The three-term parity oracle
for the secret `0b111` needs 26 wires — about a gigabyte — which is why it is
not in the list above.

See [writing oracles](../howto/write_oracles.md) for how to work within these.

---

## What you learned

- `oracle(f, x)` turns an ordinary Julia function into a reversible quantum
  operation. You do not rewrite the function.
- `b ⊻= oracle(f, x)` is the ordinary xor action with an oracle on the right;
  with `b = minus()` it becomes phase kickback.
- `dual` is how you read a sign pattern, and the register dual and the
  per-wire duals are genuinely different transforms.
- Both algorithms are the same six lines with a different readout — which is
  the actual content of the Bernstein–Vazirani result.
- The bridge's limits are loud and at the call site.

## Where next

- [Grover search](grover.md) — the same phase-kickback marker, iterated.
- [How to write oracles](../howto/write_oracles.md) — what compiles, what does
  not, and how to check.
- [Views and duality](../explanation/views_and_duality.md) — why the register
  dual and the per-wire duals differ.
- [Shor's order finding](shor.md) — where the register dual is the *right*
  readout.

**Physics sources.**
[Deutsch & Jozsa 1992](https://github.com/tobiasosborne/Sturm.jl/blob/main/docs/physics/deutsch_jozsa_1992.md),
[Bernstein & Vazirani 1997](https://github.com/tobiasosborne/Sturm.jl/blob/main/docs/physics/bernstein_vazirani_1997.md), and for
the compile-and-uncompute construction underneath `oracle`,
[Bennett 1973](https://github.com/tobiasosborne/Sturm.jl/blob/main/docs/physics/bennett_1973_logical_reversibility.md).
