# Hamiltonian simulation

**Goal.** Evolve a register under a Hamiltonian you write down as a list of
Pauli words — and understand why the library refuses to run until you tell it
how accurate you want the answer.

**Prerequisites.** [Installation](../getting_started/installation.md) and
[Your first program](../getting_started/first_program.md). No Bennett needed.
Helpful but not required: some acquaintance with the idea that a Hamiltonian
generates time evolution through `e^{-iHt}`.

**Time.** About twenty minutes. Every block below was run as written; `# =>`
comments are real output. Statistical lines are seeded finite samples and
say so.

```julia
using Sturm
using Random
```

---

## Stage 1 — one qubit, one term

The simplest Hamiltonian is a single Pauli operator. `H = X` on one qubit
drives a Rabi oscillation: start in `|0⟩`, evolve for time `t`, and the
probability of measuring `1` is exactly `sin²(t)`.

A Hamiltonian in Sturm is any iterable of `(coefficient, Pauli word)` pairs.
The word is a string over `"IXYZ"`, one character per wire, character 1 being
wire 1.

```julia
for t in (pi/8, pi/4, pi/2)
    outs = Sturm.shots(1; N = 4000, rng = MersenneTwister(0x1234)) do ctx
        x = QInt{1}(0)
        evolve!(x, [(1.0, "X")], t; steps = 1, order = 2)
        Int(x)
    end
    println(count(==(1), outs) / length(outs), "  vs  ", sin(t)^2)
end
# => 0.145    vs  0.14644660940672624
# => 0.5025   vs  0.4999999999999999
# => 1.0      vs  1.0
```

`evolve!(x, H, t; …)` mutates `x` in place and hands the same handle back —
it is a member of the action family, like `not!` and `add!`, so there is no
lost-binding trap here. `QInt{W}(n)` prepares a `W`-wire register holding the
integer `n`; `Int(x)` measures it and consumes it.

A single-term Hamiltonian is a special case: there is nothing to interleave,
so `steps = 1` is not an approximation. It is exact, which is why the numbers
above track `sin²(t)` to sampling noise.

---

## Stage 2 — the error budget is mandatory

Now two terms that do not commute. `H = Z⊗Z + ½ X⊗I` on two wires:

```julia
H = [(1.0, "ZZ"), (0.5, "XI")]
```

Try to evolve without saying how well:

```julia
Sturm.eager(2) do ctx
    x = QInt{1}(0)
    evolve!(x, [(1.0, "X")], 1.0)
end
# => ERROR: ArgumentError: evolve!: give a target accuracy ε=… or explicit
# =>        resources (steps=…/N=…) — there is no default accuracy (S3).
```

(The `(S3)` at the end is an internal reference to the design decision that
put the rule there; the rule itself is the sentence in front of it.)

This is deliberate, and it is the most opinionated thing in the library. Every
practical method for simulating `e^{-iHt}` is an approximation, so *some*
accuracy is always being chosen. Most frameworks choose one for you silently.
Sturm makes you say it, because a silently chosen accuracy is a number that
ends up in your paper without anybody having read it.

You satisfy the requirement in one of two ways.

**Say how many steps.** You are in control of the resources and you accept
whatever accuracy results:

```julia
outs = Sturm.shots(2; N = 4000, rng = MersenneTwister(0x77)) do ctx
    x = QInt{2}(0)
    evolve!(x, H, 1.0; steps = 40, order = 2)
    Int(x)
end
[count(==(v), outs) / length(outs) for v in 0:3]
# => [0.83825, 0.0, 0.16175, 0.0]
```

The exact answer, from exponentiating the 4×4 matrix directly, is
`[0.83827…, 0, 0.16173…, 0]`. The two odd outcomes are exactly zero, and the
sampled frequencies track the exact ones to within the noise of 4000 shots.

**Say how accurate.** You state a target error `ε` and the library derives the
resources from a proven bound:

```julia
outs = Sturm.shots(2; N = 4000, rng = MersenneTwister(0x77)) do ctx
    x = QInt{2}(0)
    evolve!(x, H, 1.0; alg = Trotter(order = 4), ε = 1e-3)
    Int(x)
end
[count(==(v), outs) / length(outs) for v in 0:3]
# => [0.83825, 0.0, 0.16175, 0.0]
```

Both land on the exact distribution to sampling noise. The difference is which
end of the trade you fixed.

The second form is the one to reach for. `ε` is a bound on how far the
simulated evolution is from the true one *as a channel* — worst case over all
inputs, including inputs entangled with something you are not looking at. It
is not a fidelity on one state.

---

## Stage 3 — let the library plan

Drop the strategy and give only `ε`, and the library chooses:

```julia
outs = Sturm.shots(2; N = 4000, rng = MersenneTwister(0x77)) do ctx
    x = QInt{2}(0)
    evolve!(x, H, 1.0; ε = 1e-3)
    Int(x)
end
[count(==(v), outs) / length(outs) for v in 0:3]
# => [0.838, 0.0, 0.162, 0.0]
```

That is `Auto()`: it prices each candidate strategy using bounds it can
prove, and picks the cheapest. The candidates are the four strategy
descriptors the library exports:

| Strategy | What it is |
|---|---|
| `Trotter(order = p, steps = r)` | the deterministic Suzuki product formula |
| `QDrift(N = …)` | Campbell's randomized compiler: sample terms by weight |
| `Composite(order = p, K = …)` | a deterministic head over the heavy terms, randomized tail for the rest |
| `Auto()` | pick the cheapest of the above that meets `ε` |

You do not have to choose. `Auto()` is what a bare `ε = …` means.

If you want to see the plan before running it, `Sturm.plan_evolution` is a
pure function — it computes resources and returns them without touching a
context:

```julia
hs = Sturm.PauliSum{2}(H)              # the canonical form of the Hamiltonian
for eps in (1e-2, 1e-4, 1e-6)
    println(eps, " -> ", Sturm.plan_evolution(Trotter(order = 4), hs, 1.0; ε = eps).steps)
end
# => 0.01   -> 125
# => 0.0001 -> 394
# => 1.0e-6 -> 1245
```

Tightening the budget by two decades costs about 3× the steps — the signature
of a fourth-order formula, whose error falls like `1/r⁴`.

> **Do not read `steps` as cost.** A higher-order formula does more elementary
> work per step, because the Suzuki recursion fans each step out into many
> sub-steps. `Sturm.exp_count` counts what actually runs — the number of Pauli
> exponentials:
>
> ```julia
> for o in (2, 4)
>     pl = Sturm.plan_evolution(Trotter(order = o), hs, 1.0; ε = 1e-6)
>     println("order ", o, ": steps = ", pl.steps, ", exponentials = ", Sturm.exp_count(pl))
> end
> # => order 2: steps = 578,  exponentials = 2312
> # => order 4: steps = 1245, exponentials = 24900
> ```
>
> On this tiny two-term Hamiltonian the fourth-order formula is an order of
> magnitude *more* expensive than the second-order one, because there is not
> enough error to save. Higher order is not automatically better. Deciding
> which is cheapest at a given `ε` is exactly what `Auto()` does for you.

There is a real price for this: deriving resources from `ε` prices the plan on
an exact bound, and on Hamiltonians with hundreds of terms that computation
takes seconds. That is planning time, not a hang.

---

## Stage 4 — ready-made Hamiltonians

Three model families ship with the library, for when you want a benchmark
rather than a bespoke Hamiltonian:

```julia
Sturm.ising_chain(3)
# => Sturm.PauliTerm[Sturm.PauliTerm(1.0, "ZZI"), Sturm.PauliTerm(1.0, "IZZ"),
# =>  Sturm.PauliTerm(1.0, "XII"), Sturm.PauliTerm(1.0, "IXI"), Sturm.PauliTerm(1.0, "IIX")]

Sturm.heisenberg_chain(3)
# => Sturm.PauliTerm[Sturm.PauliTerm(1.0, "XXI"), Sturm.PauliTerm(1.0, "YYI"),
# =>  Sturm.PauliTerm(1.0, "ZZI"), Sturm.PauliTerm(1.0, "IXX"),
# =>  Sturm.PauliTerm(1.0, "IYY"), Sturm.PauliTerm(1.0, "IZZ")]
```

`Sturm.powerlaw_chain(W; γ, J)` is the third. All three take the same shape as
your hand-written list and can be passed straight to `evolve!`.

---

## Honest limits

- **Randomized strategies run one trajectory per call.** `QDrift` and
  `Composite` sample; a single `evolve!` gives you one draw from an ensemble,
  and the `ε` guarantee belongs to the average over draws. Averaging is your
  job — that is what `Sturm.shots` is for.

- **Randomized strategies are refused where they would lie.** On a
  density-matrix context, one trajectory is not the channel, and the library
  says so rather than quietly running it:

  ```julia
  Sturm.density(2) do ctx
      x = QInt{1}(0)
      evolve!(x, [(1.0, "X")], 1.0; alg = QDrift(), ε = 1e-2)
  end
  # => ERROR: evolve!(QDrift): a randomized strategy samples ONE trajectory —
  # =>   one unravelling of the qDrift/composite CHANNEL — and running it on a
  # =>   density-matrix context would silently misrepresent the CPTP average …
  # =>   Run randomized strategies under `eager`/`shots`, or use a deterministic
  # =>   strategy (legal on DM).
  ```

  The same refusal fires inside a `when` body: controlling a mixture is not
  the same as mixing controlled things, and the library will not pretend
  otherwise. Deterministic `Trotter` *is* legal under `when`, which is what
  makes phase estimation on `e^{-iHt}` compose.

- **`Auto()` never under-prices, and sometimes over-prices.** It ranks by
  bounds it can prove. A bound that is loose in your particular case makes it
  pick a more expensive strategy than necessary. It will not pick one that
  misses your `ε`.

- **The order cap is 12.** `Trotter(order = p)` accepts even orders up to 12
  and refuses loudly above it.

- **Simulation size is memory-bound.** Each wire doubles the state vector.
  This is Orkan's ceiling, not the library's.

---

## What you learned

- A Hamiltonian is a list of `(coefficient, Pauli word)` pairs; `evolve!`
  mutates the register in place.
- There is no default accuracy. Give `ε` (and let the library derive
  resources) or give resources (and accept the accuracy).
- `ε` is a channel-level bound, not a single-state fidelity.
- `Trotter`, `QDrift`, `Composite` and `Auto` are the strategy vocabulary; the
  planning happens in a pure function you can call yourself.
- Randomized strategies are one trajectory per call, and are refused in the
  two places where that would silently give a wrong answer.

## Where next

- [Grover search](grover.md) — another library higher-order function, this one
  taking a predicate.
- [Measuring statistics](../howto/measure_statistics.md) — `shots`,
  `record_distribution`, and which one you actually want.
- [Choosing a context](../getting_started/choosing_a_context.md) — why a
  density-matrix context changes what `evolve!` will accept.
- [Library reference](../reference/library.md) — full signatures for
  `evolve!` and the strategy types.

**Physics sources.** The product formulas and their error bounds:
[Suzuki 1991](https://github.com/tobiasosborne/Sturm.jl/blob/main/docs/physics/suzuki_1991_fractal_decomposition.md),
[Childs et al. 2019](https://github.com/tobiasosborne/Sturm.jl/blob/main/docs/physics/childs_2019_trotter_error.md). The
randomized compiler: [Campbell 2019](https://github.com/tobiasosborne/Sturm.jl/blob/main/docs/physics/campbell_2019_qdrift.md).
The head/tail interleave:
[Hagan & Wiebe 2023](https://github.com/tobiasosborne/Sturm.jl/blob/main/docs/physics/hagan_wiebe_2023_composite.md).
