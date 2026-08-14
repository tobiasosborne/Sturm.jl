# Writing oracles with `oracle(f, x)`

*A task recipe. Assumes you can already write a small program and run it — see
[your first program](../getting_started/first_program.md).*

`oracle(f, x)` takes an **ordinary Julia function** and a live quantum
register, and gives you back a value you apply with `⊻=`:

```julia
b ⊻= oracle(f, x)      # |x⟩|b⟩ ↦ |x⟩|b ⊕ f(x)⟩ ; x stays live
```

That is the whole interface. There is no gate list, no circuit, no ancilla
bookkeeping — the compiler runs `f` forwards, copies the answer out, and runs
`f` backwards to erase every intermediate, so the scratch it borrowed comes
back to `|0⟩` and never entangles with your data. This is Bennett's 1973
construction, done for you (distilled in
[`docs/physics/bennett_1973_logical_reversibility.md`](https://github.com/tobiasosborne/Sturm.jl/blob/main/docs/physics/bennett_1973_logical_reversibility.md)).

## Setup: you need Bennett loaded

The compiler front-end lives behind a weak dependency, so `using Sturm` alone
does not load it. Add `using Bennett`:

```julia
using Sturm, Bennett
```

Without it, `oracle` refuses at the call site — loudly, with the fix in the
message:

```
oracle(f, x): the Bennett backend is not loaded — add `using Bennett`
alongside `using Sturm` to activate the `SturmBennettExt` extension
(the reversible-compile frontend is a weak dependency; …).
```

Installation is covered in [installation](../getting_started/installation.md).

## The shape that works

```julia
using Sturm, Bennett

inc(x) = x + one(x)

Sturm.eager(20) do ctx
    x = QInt{3}(5)
    b = QInt{3}(0)
    b ⊻= oracle(inc, x)
    (Int(x), Int(b))
end
# => (5, 6)     -- x preserved, b holds 0 ⊕ inc(5)
```

Three things to read off that:

- **`x` is still live afterwards.** The oracle preserves its input; that is
  what makes it usable inside interference.
- **`b` accumulates by XOR**, it is not overwritten. Start from `QInt{W}(0)`
  if you want `b == f(x)`.
- **`f` is written generically** — `one(x)`, `typeof(x)(3)`, `zero(x)` — because
  the compiler calls it at a fixed machine width chosen from `W`. Hard-coding
  `Int` literals fights that.

### Phase kickback: the reason oracles exist

Point the accumulation at a `|−⟩` and the XOR becomes a sign:

```julia
using Sturm, Bennett

f_lsb(x) = x & one(x)          # the secret is s = 001

Sturm.eager(20) do ctx
    x = QInt{3}(0)
    superpose!(x)               # every input at once
    b = minus()                 # |−⟩, the kickback ancilla
    b ⊻= oracle(f_lsb, x)       # ↦ (−1)^f(x) |x⟩|−⟩
    [Bool(dual(x[i])) for i in 1:3]
end
# => Bool[0, 0, 1]     -- the secret, recovered in one query (wire 1 is the MSB)
```

That is Bernstein–Vazirani, in six lines, with no gates in sight. The full
story is in the [Deutsch–Jozsa tutorial](../tutorials/deutsch_jozsa.md).

### Under `when`, for free

A compiled oracle is a phase-free permutation, and a controlled permutation is
still a permutation — so `oracle` composes with coherent control with no extra
machinery:

```julia
using Sturm, Bennett

add3(x) = x + typeof(x)(3)

Sturm.eager(22) do ctx
    c = QBool(true); x = QInt{2}(0); b = QInt{2}(0)
    when(c) do
        b ⊻= oracle(add3, x)
    end
    (Bool(c), Int(b))
end
# => (true, 3)

Sturm.eager(22) do ctx
    c = QBool(false); x = QInt{2}(0); b = QInt{2}(0)
    when(c) do
        b ⊻= oracle(add3, x)
    end
    (Bool(c), Int(b))
end
# => (false, 0)     -- the control was |0⟩, so nothing fired
```

---

## The limits, as a checklist

Every one of these fails **loudly**, and all the compile-time ones fail at the
`oracle(f, x)` call site naming `f` — never downstream at `⊻=`, never with a
quietly wrong answer.

### 1. No data-dependent loops

A loop whose trip count depends on the *value* of `x` leaves behind a
convergence flag that cannot be uncomputed, so the scratch does not return to
`|0⟩`.

```julia
# WRONG — for illustration; this throws at the oracle() call
function countdown(x)
    acc = x; c = zero(x)
    while acc != zero(x)         # trip count depends on x
        acc -= one(x); c += one(x)
    end
    return c
end

b ⊻= oracle(countdown, x; optimize = false, max_loop_iterations = 6)
```

```
oracle(f, x): `f` compiles to a data-dependent loop whose convergence flag
cannot be uncomputed — it is not a clean reversible oracle (its scratch does
not return to |0⟩). Increasing max_loop_iterations fixes overflow, not the
garbage flag: a genuinely data-dependent loop keeps its guard at any K.
Rewrite `f` with a statically-bounded loop (a compile-time trip count fully
unrolls with no guard), or restructure the computation.
```

```julia
# RIGHT — a statically bounded loop unrolls with no guard
using Sturm, Bennett

function popcount2(x)
    c = zero(x)
    for i in 0:1                 # trip count is a compile-time constant
        c += (x >> typeof(x)(i)) & one(x)
    end
    return c
end

[Sturm.eager(22) do ctx
     x = QInt{2}(v); b = QInt{2}(0); b ⊻= oracle(popcount2, x); Int(b)
 end for v in 0:3]
# => [0, 1, 1, 2]
```

> **Watch the optimizer when you reproduce this.** With the default
> `optimize = true`, Bennett folds a simple countdown to a closed form and the
> call *succeeds* — the rejection above only appears with `optimize = false`.
> That is not a bug; it means the optimizer removed the data dependence. Do not
> rely on it for a genuinely value-dependent loop.

### 2. `count_ones` does not compile

The obvious way to write a parity oracle is the one that fails:

```julia
# WRONG — for illustration
b ⊻= oracle(v -> count_ones(v) % 2, x)
```

```
oracle(f, x): Bennett could not compile `f` to a fixed reversible circuit —
ArgumentError: lower_shl!/lshr!/ashr!: constant shift k=4 out of [0, W] for
W=3 (…). If `f` needs unbounded loops or runtime-sized memory it requires the
BennettVM (out of scope — circuit-only bridge); rewrite with statically-bounded
loops and fixed-width state.
```

`count_ones` lowers to a shift-and-mask popcount whose shift constants are
sized for the host word, not for your `W` wires. Write the mask yourself:

```julia
# RIGHT — explicit, width-honest bit extraction
using Sturm, Bennett

f_lsb(x)   = x & one(x)                    # a single bit
parity2(x) = (x ⊻ (x >> one(x))) & one(x)  # parity of a 2-bit input

[Sturm.eager(22) do ctx
     x = QInt{2}(v); b = QBool(false); b ⊻= oracle(parity2, x); Bool(b)
 end for v in 0:3]
# => Bool[0, 1, 1, 0]
```

### 3. Width bounds: `W ∈ 1:64`

`W` is Bennett's native ceiling, and `QInt{W}` guards its own literal
constructor well before that:

```julia
# WRONG — for illustration
x = QInt{65}(0)
```

```
DomainError with 65:
QInt{65}(n) literal range check: width W=65 is outside the machine-shift
range 1:62 — `1 << W` would overflow a signed host Int. This path is
unreachable under the backend qubit budget; the guard fails loud rather than
silently wrapping.
```

In practice the binding constraint is much smaller: a simulated `W`-wire
oracle needs `W` input wires, `W` target wires and a pile of scratch, all
inside your context capacity.

### 4. One input register, one output register

`oracle` takes exactly one `QInt{W}`. Multi-register oracles and `QBool`
inputs are designed for but not implemented, and both are honest
`MethodError`s rather than a catch-all that guesses:

```julia
# WRONG — for illustration
b ⊻= oracle((a, c) -> a + c, x, y)
```

```
MethodError: no method matching oracle(::var"#…", ::QInt{2,…}, ::QInt{2,…})
Closest candidates are:
  oracle(::Any, ::QInt{W}; kwargs...) where W
```

```julia
# WRONG — for illustration
b ⊻= oracle(add3, some_qbool)
```

```
MethodError: no method matching oracle(::typeof(add3), ::QBool{…})
```

Pack multiple inputs into one wider `QInt{W}` and slice inside `f`.

### 5. The query is always on the right of `⊻=`

```julia
# WRONG — for illustration
oracle(add3, x) ⊻ b
```

```
MethodError: no method matching xor(::Sturm.OracleQuery{…}, ::QInt{2,…})
```

There is deliberately no method with the query on the left: the target is the
thing that gets mutated, and `b ⊻= q` reads left-to-right as "accumulate into
`b`".

### 6. The target must be a distinct register

Aliasing the accumulation target into the preserved input is rejected before
anything runs:

```julia
# WRONG — for illustration
x[1] ⊻= oracle(inc, x)
```

```
oracle target aliases its input register: wire WireID(1) is shared between the
`⊻=` target `b` and the oracle input `x`. The kickback target must be a
DISTINCT register — the output block cannot overlap the preserved input block.
```

### 7. The target must be wide enough

If `f(x)` needs more bits than `b` has, the scratch cannot come back clean and
the clean-ancilla check fires — again, before you get a wrong number:

```julia
# WRONG — for illustration: add3 needs 2 bits, b has 1
x = QInt{2}(3); b = QBool(false)
b ⊻= oracle(add3, x)
```

```
clean-ancilla witness FAILED for WireID(4): its |1⟩-marginal is 1.0 > 1.0e-10.
A scratch ancilla must be uncomputed to a DISENTANGLED |0⟩ before it leaves a
`when` body — otherwise tracing it would decohere the control (a silent wrong
channel).
```

A one-bit target is fine when `f` genuinely returns one bit:

```julia
using Sturm, Bennett

Sturm.eager(22) do ctx
    x = QInt{2}(3)
    b = QBool(false)
    b ⊻= oracle(v -> v & one(v), x)
    Bool(b)
end
# => true
```

---

## What about `if`?

Branches are fine. Bennett flattens control flow, so both spellings compile
and give the same answer:

```julia
using Sturm, Bennett

function bif(x)                              # a plain branch
    if x > typeof(x)(1)
        return x - typeof(x)(1)
    else
        return x
    end
end

bsel(x) = ifelse(x > typeof(x)(1), x - typeof(x)(1), x)   # guarded select

Sturm.eager(22) do ctx
    x = QInt{2}(3); b = QInt{2}(0); b ⊻= oracle(bif, x); (Int(x), Int(b))
end
# => (3, 2)

Sturm.eager(22) do ctx
    x = QInt{2}(3); b = QInt{2}(0); b ⊻= oracle(bsel, x); (Int(x), Int(b))
end
# => (3, 2)
```

The honest caveat is **cost, not correctness**: a reversible circuit has no
"skip this block", so a branch computes *both* arms and selects. Writing
`ifelse` makes that explicit and keeps you from expecting a saving that is not
there. Where a branch does bite is when it hides a data-dependent loop — then
you are back at limit 1.

## Gotchas

- **Capacity is the limit you will hit first.** An oracle borrows scratch
  wires inside a nested region, so a `QInt{3}` oracle can easily need twenty
  wires. Budget for it; running short is a loud
  `context capacity (N wires) exceeded`.

- **`f` is compiled eagerly, at the `oracle(f, x)` call.** If `f` is bad you
  learn at that line, with `f` named — not three lines later at the `⊻=`.

- **Compile once, apply many.** Each `oracle(f, x)` call recompiles. In a loop
  (Grover, say) that cost is real, though small compared with simulating the
  state.

- **`f` must be pure.** Anything Bennett cannot see as fixed-width arithmetic
  on the argument — global state, allocation, `Vector`s sized at runtime — is
  out of scope for the circuit bridge.

- **Sturm counts wire 1 as the most significant bit**, Bennett counts
  position 1 as the least significant. The bridge does the remap in exactly
  one place, so you never see it — but it is why `x[1]` is the MSB when you
  slice.

## Where next

- [Deutsch–Jozsa and Bernstein–Vazirani](../tutorials/deutsch_jozsa.md) — the
  two canonical one-query algorithms, end to end.
- [Grover search](../tutorials/grover.md) — `find` builds its phase marker
  from an oracle.
- [The seven constructs](../explanation/seven_constructs.md) — where `oracle`
  sits in the surface language.
- [Reference: the oracle bridge](../reference/oracle.md).
