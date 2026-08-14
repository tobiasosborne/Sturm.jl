# Sturm.jl

[![License](https://img.shields.io/badge/License-AGPL_3.0-7aa2f7.svg?style=flat-square)](LICENSE)
[![Julia](https://img.shields.io/badge/Julia-1.11%2B-9558B2.svg?style=flat-square)](https://julialang.org/)
[![Backend](https://img.shields.io/badge/backend-Orkan_C17-f24f4f.svg?style=flat-square)](#installation)
[![Surface](https://img.shields.io/badge/surface-7_constructs_·_0_gates-2ea043.svg?style=flat-square)](#the-seven-constructs)

**Write quantum programs as ordinary Julia — no gates, no circuit diagrams, no
rotation angles — with the quantum/classical boundary enforced by the type
system instead of by convention.**

A classical bit is one of two things, and if you don't know which, that is
just ignorance: a coin under a cup. A quantum bit is different in a way that
is easy to state and hard to un-hear — **which question you ask decides what
there is to see.** Prepare one in the even blend of `0` and `1`, ask *"which
one are you?"*, and you get a coin flip. Ask the *conjugate* question instead
— not "which one" but "how do the two line up?" — and the very same state
answers identically every single time, with no randomness at all. Nothing
about the state differed between those two runs. The question did. That is
**complementarity**, and it, rather than the slogan "0 and 1 at the same
time", is what a quantum program actually computes with.

Most toolkits hand you that physics as a wiring diagram: a grid of wires,
boxes labelled `H` and `CNOT`, rotation angles you tune by hand. Sturm takes
the other road. A register is a Julia value. `dual(q)` is that same register
addressed by the conjugate question. `Bool(q)` is a **cast** out of the
quantum world, and it consumes its argument, because measurement really does
destroy what it reads. Entanglement is not a gate you look up — it is
`a ⊻= b`, ordinary exclusive-or, on registers that happen to be quantum.

```julia
using Sturm

# Ask "which one are you?" a thousand times. It is a coin.
flips = Sturm.shots(1; N = 1000) do ctx
    Bool(QBool(0.5))                # prepare an even blend, then measure it
end
sum(flips) / 1000                   # => 0.496   (yours will differ — it is random)

# Ask the *other* question of the very same state. It is never random.
Sturm.eager(1) do ctx
    Bool(dual(QBool(0.5)))          # => false   every run, forever
end
```

Same state, two questions, two completely different answers. That gap is
where quantum computing lives.

## No gates, no circuits, no angles

Here is quantum teleportation — moving an unknown quantum state from one
register to another — written the way most toolkits ask you to write it:

```julia
# ILLUSTRATION ONLY. This is not Sturm; no such API exists here.
c = Circuit(3)
h!(c, 1); cnot!(c, 1, 2)          # ...which wire was the Bell pair again?
cnot!(c, 0, 1); h!(c, 0)
m0 = measure!(c, 0); m1 = measure!(c, 1)
m1 == 1 && x!(c, 2)
m0 == 1 && z!(c, 2)
```

Every line of that is correct, and none of them says what the program is
*for*. Here is the same protocol in Sturm:

```julia
using Sturm

"Teleport a qubit. This function denotes the identity channel — that is the theorem."
function teleport(ψ::QBool)
    b = QBool(0.5)                # a fair quantum coin
    c = false ⊻ b                 # xor it into a fresh `false` — that is a Bell pair
    b ⊻= ψ                        # correlate the payload with Alice's half

    m_phase = Bool(dual(ψ))       # read ψ with the conjugate question (consumes ψ)
    m_value = Bool(b)             # read b with the ordinary one

    m_value && not!(c)            # ordinary Julia conditionals, ordinary flips —
    m_phase && not!(dual(c))      # one of them in the dual view
    return c
end

Sturm.eager(4) do ctx
    Bool(teleport(QBool(true)))         # => true    a definite bit survives the trip
end
Sturm.eager(4) do ctx
    Bool(dual(teleport(QBool(0.5))))    # => false   and so does a conjugate one
end
```

Two things worth noticing. First, `ψ` is *gone* after `Bool(dual(ψ))` — the
cast consumed it, so "teleport it and keep the original" is not a rule to
remember, it is a program you cannot write. That is the no-cloning theorem,
expressed as ownership. Second, the *second* check is the one that matters: a
merely classical copier passes the first and fails the second. Sturm's own
history is the cautionary tale — a teleportation routine shipped in v0.1 that
moved only the classical part, and its measurement-average test stayed green
the whole time, because the old surface had no way to *write* `Bool(dual(ψ))`.

> **The house rule.** If your program reads like a circuit diagram, it is
> wrong. If it mentions a gate, a rotation angle, or a matrix, it is not
> surface code. If it reads like ordinary Julia with a few casts and views, it
> is probably right.

## Installation

Sturm is not yet registered. It needs three things side by side: itself, the
[Orkan](https://github.com/Timo59/orkan) simulator (C17, built once with
CMake), and [Bennett.jl](https://github.com/tobiasosborne/Bennett.jl) if you
want the `oracle` bridge.

```bash
git clone https://github.com/tobiasosborne/Sturm.jl
git clone https://github.com/tobiasosborne/Bennett.jl
git clone https://github.com/Timo59/orkan

cd orkan && cmake --preset release && cmake --build --preset release
cd ../Sturm.jl && julia --project -e 'using Pkg; Pkg.instantiate()'
julia --project -e 'using Sturm'          # should print nothing and exit 0
```

Sturm finds `liborkan.so` by looking next door, so a fresh clone beside a
*built* `orkan` needs no configuration. If you keep it elsewhere, set
`LIBORKAN_PATH` before the first `using Sturm` (it is read once, at load).
Requires Julia 1.11 or newer. Run the test suite with `julia --project -e
'using Pkg; Pkg.test()'` — 27,875 assertions, no CI, run locally. Full details
including CMake prerequisites:
**[installation guide](docs/src/getting_started/installation.md)**.

## The seven constructs

This is the entire user-facing quantum vocabulary — seven forms, no eighth.
You have already met the first four: they are what `teleport` is made of.

**1. Preparation** — `QBool`, `QInt{W}`, `QMod{N}` turn an ordinary Julia
literal into a live quantum register. **2. Measurement** — `Bool(q)` and
`Int(x)` cross back, and they *consume*: the handle is dead afterwards, and
touching it again is a loud error rather than a silent wrong answer.

```julia
Sturm.eager(4) do ctx
    x = QInt{4}(9)                # prepare: a 4-bit register holding 9
    Int(x)                        # => 9   measure: and now x is gone
end

Sturm.eager(1) do ctx
    q = QBool(true); Bool(q); Bool(q)
end                               # ERROR: register WireID(1) already consumed
```

**3. Actions** — `not!`, `⊻=`, `add!`. These mutate in place and return the
same register, which is what makes `a ⊻= b` a physical operation rather than a
rebinding. `⊻=` between two registers is how you entangle; there is no CNOT.

```julia
Sturm.eager(5) do ctx
    a = QBool(false); b = QBool(true)
    a ⊻= b                        # a ← a XOR b — target on the left, control on the right
    x = QInt{3}(5); add!(x, 4)    # wraps mod 8, like any fixed-width integer
    (Bool(a), Bool(b), Int(x))    # => (true, true, 1)
end
```

**4. The conjugate view** — `dual(q)` is a lazy, zero-cost *addressing mode*,
not an operation. It is the "other question" from the opening paragraph, and
it swaps the roles of value and phase.

```julia
Sturm.eager(3) do ctx
    x = QInt{3}(5)
    x̂ = dual(x)
    x̂ += 1                        # shifts the CONJUGATE reading of x...
    Int(x)                        # => 5   ...and leaves x itself untouched
end
```

`add!(x, 1)` and `x̂ += 1` both read as "add one" and are genuinely different
physical operations — the first moves the value, the second moves the phase.
See [views and duality](docs/src/explanation/views_and_duality.md).

**5. Coherent control** — `when(q) do … end` runs a body *under* a quantum
condition, with no measurement and no collapse. The body is ordinary code.
Measuring inside one is refused loudly: control over an irreversible step is
not something that exists physically, so it is not something you can spell.

```julia
Sturm.eager(3) do ctx
    c = QBool(true); x = QInt{2}(1)
    when(c) do
        add!(x, 1)
    end
    (Int(x), Bool(c))             # => (2, true)   — and (1, false) if c were false
end
```

**6. Classical branching** — `cases` / `@cases` branch on an outcome you
*already* measured. Unlike `when`, this is ordinary control flow.

```julia
Sturm.eager(2) do ctx
    m = Bool(QBool(0.5))
    a = QBool(false)
    cases(m) do
        not!(a)
    end
    (m, Bool(a))                  # => (true, true) or (false, false) — always agreeing
end
```

**7. The Bennett bridge** — `oracle(f, x)` takes an ordinary Julia function
and makes it quantum. Its own section is below.

## The Bennett bridge: your classical code, unchanged

Quantum algorithms need to call classical functions — a predicate, a hash, a
modular exponent — on a superposition of inputs. Ordinarily you rewrite that
function as a circuit by hand. You do not have to here.
[Bennett's 1973 construction](docs/physics/bennett_1973_logical_reversibility.md)
makes any computation reversible: run it, copy out the answer, run it
backwards to wipe every intermediate. `oracle(f, x)` does that automatically —
compiling `f` from its LLVM IR down to a reversible permutation — and hands
the result to the same `⊻=` you already know:

```julia
using Sturm, Bennett

Sturm.eager(20) do ctx
    x = QInt{3}(5); b = QInt{3}(0)
    b ⊻= oracle(v -> v + one(v), x)   # b ← b XOR f(x); x survives untouched
    (Int(x), Int(b))                  # => (5, 6)
end
```

Put `x` into a superposition first and that same line queries *every* input at
once. Deutsch–Jozsa — decide in a single query whether a function is constant
or balanced — is then four lines:

```julia
allzero(x) = zero(x)                  # constant
lowbit(x)  = (x >> 0x00) & 0x01       # balanced

Sturm.eager(18) do ctx
    x = QInt{3}(0); superpose!(x)     # all eight 3-bit inputs at once
    b = minus()                       # the ancilla that turns f's answer into a phase
    b ⊻= oracle(lowbit, x)            # one query
    Int(dual(x)) == 0                 # => false   (balanced; `allzero` gives true)
end
```

**Limits, stated up front.** The bridge crosses *fixed, finite* permutations
only. Unbounded loops and runtime-sized memory are refused at the `oracle`
call, naming your function. Widths run 1–64 bits. One register in, one scalar
out. And some ordinary Julia simply will not compile — `count_ones` is a known
case — which you learn at compile time with the reason attached, not at
runtime with garbage. Details:
**[writing oracles](docs/src/howto/write_oracles.md)**.

## A flagship: Grover search over your own predicate

`find(p, Val(W))` searches the `2^W` `W`-bit integers for one satisfying an
arbitrary Julia predicate, using roughly `√(2^W)` queries instead of `2^W`.
You write the predicate. Sturm compiles it, builds the amplitude-amplification
loop, and measures.

```julia
using Sturm, Bennett

Sturm.eager(16) do ctx
    find(v -> v == 2, Val(2))              # => 2    one solution in four, found for sure
end

Sturm.eager(22) do ctx
    find(v -> v == 6, Val(3); nsolutions = 1)   # => 6    (succeeds ~94.5% of runs)
end
```

The 3-bit case is honest about being probabilistic: with one solution among
eight, two Grover iterations put the success probability at
`sin²(5·asin(1/√8)) ≈ 0.945`, and the test suite checks the measured rate
against exactly that formula over 1,000 seeded trials rather than against a
pinned number. The 2-bit case really is deterministic. Walkthrough:
**[Grover tutorial](docs/src/tutorials/grover.md)**. The same library ships
`amplify` (bring your own phase marker), `phase_estimate`, `shor_order`
(order finding with verified classical post-processing), and `evolve!` for
Hamiltonian simulation with proven error bounds.

## Three contexts, one program

The same program means different things depending on what you want from it,
and Sturm makes you say which. `Sturm.eager(cap)` runs **one trajectory**: a
statevector, real mid-circuit measurement, `Bool(q)` returns an honest
`Bool`, and `if` works. `Sturm.density(cap)` computes the **exact channel**
on a density matrix: no sampling, no shot noise, `Bool(q)` returns a *record
token* rather than a value (there is no single outcome to give you), and you
read distributions off it with `record_distribution`. `Sturm.trace(f, n)`
**executes nothing** — it builds the program as data, for optimization passes
to chew on. The `cap` argument is a qubit count and sets the memory: an eager
context holds `2^cap` amplitudes, a density one `2^(2·cap)`.

```julia
Sturm.eager(1)   do ctx; typeof(Bool(QBool(0.5))) end   # => Bool
Sturm.density(1) do ctx; typeof(Bool(QBool(0.5))) end   # => ClassicalBit{DensityMatrixContext}

Sturm.density(1) do ctx
    Sturm.record_distribution(Bool(QBool(0.3)))         # => [0.7, 0.3]  exactly, in one run
end
```

The seven constructs arrive with `using Sturm`; the context entry points are
namespaced, so they are written `Sturm.eager(…)` above, or brought in
directly with `using Sturm: eager, density`. Which to reach for, and why the
answer is not always Eager:
**[choosing a context](docs/src/getting_started/choosing_a_context.md)**.

## Error correction is a higher-order function

Most frameworks give you a library of encoded gates. Sturm gives you a
transformation of *programs*: `Protect(code)` is a callable that maps a noise
channel on physical qubits to the effective noise a logical qubit sees.

```julia
using Sturm
using Sturm: bit_flip_code, bit_flip, physical_iid, Protect, classicalise

enc     = bit_flip_code()
protect = Protect(enc)

for p in (0.1, 0.5, 0.6)                        # physical bit-flip rate
    logical = protect(physical_iid(enc, bit_flip(p)))
    println(p, "  ->  ", round(classicalise(logical)[2, 1]; digits = 3))
end
# prints:   0.1  ->  0.028      correction helps
#           0.5  ->  0.5        exact break-even
#           0.6  ->  0.648      correction actively hurts
```

Those numbers are the closed form `3p² − 2p³`, computed rather than assumed;
the crossover at `p = 0.5` is where a three-way majority vote stops being
worth taking. The `[[3,1,1]]` code shipped here is a *bit*-flip code and
nothing else: it declares distance 1, corrects zero phase errors, and
measurably makes phase noise **worse** — stated in its own docstring, because
a code that quietly oversold itself would be the more dangerous artifact. See
**[error correction](docs/src/tutorials/error_correction.md)**.

## Status and what is missing

Milestones M1–M12 are implemented and tested: the kernel, all three contexts,
the seven surface constructs, the Bennett bridge, the channel IR with its
optimization passes, modular arithmetic and Shor's order finding, the Grover
and phase-estimation library, Hamiltonian simulation with four strategies,
and the code-capacity error-correction layer. That is 27,875 test assertions,
run locally. Version `0.2.0-dev`; the API is not frozen.

What is **not** here, plainly:

- **No hardware backend.** Everything runs on the Orkan simulator. There is no
  transpiler, no device calibration, no queue submission.
- **Simulator-sized problems only.** A statevector of `cap` qubits is `2^cap`
  complex amplitudes; the practical ceiling is around 30. Density-matrix work
  is quadratically worse, which caps exact channel comparisons near 7 qubits.
  Exceeding a capacity is a loud error naming the limit, not a slow crawl.
- **Error correction is code-capacity only.** Encoder, decoder and syndrome
  extraction are assumed perfect; there is no fault-tolerance or threshold
  claim, and `fault_tolerant_lift` exists specifically to *refuse* and list
  the five ingredients a real one would need. One code ships — the `[[3,1,1]]`
  bit-flip repetition code. No surface or Steane-style codes.
- **Oracles are fixed finite permutations.** Unbounded loops, runtime-sized
  memory, and widths over 64 bits are rejected at compile time.
- **No benchmarks yet.** No performance numbers are published because none
  have been measured properly, and inventing them would be worse than the gap.

The principle throughout: **fail loud, never silently wrong.** Error messages
name the register, the rule, and usually the fix.

## Documentation

**Learn** — [installation](docs/src/getting_started/installation.md) ·
[your first program](docs/src/getting_started/first_program.md) ·
[choosing a context](docs/src/getting_started/choosing_a_context.md)

**Do** — [teleportation](docs/src/tutorials/teleportation.md) ·
[Deutsch–Jozsa & Bernstein–Vazirani](docs/src/tutorials/deutsch_jozsa.md) ·
[Grover search](docs/src/tutorials/grover.md) ·
[Shor's algorithm](docs/src/tutorials/shor.md) ·
[Hamiltonian simulation](docs/src/tutorials/hamiltonian_simulation.md) ·
[error correction](docs/src/tutorials/error_correction.md) ·
[measuring statistics](docs/src/howto/measure_statistics.md) ·
[writing oracles](docs/src/howto/write_oracles.md)

**Understand** — [functions are channels](docs/src/explanation/functions_are_channels.md) ·
[the seven constructs](docs/src/explanation/seven_constructs.md) ·
[views and duality](docs/src/explanation/views_and_duality.md) ·
[contexts and scope](docs/src/explanation/contexts_and_scope.md) ·
[phase discipline](docs/src/explanation/phase_discipline.md) ·
[gotchas](docs/src/explanation/gotchas.md)

**Look up** — [surface](docs/src/reference/surface.md) ·
[contexts](docs/src/reference/contexts.md) · [kernel](docs/src/reference/kernel.md) ·
[channels](docs/src/reference/channels.md) · [library](docs/src/reference/library.md) ·
[error correction](docs/src/reference/qecc.md) · [oracle](docs/src/reference/oracle.md)

Build the manual with `julia --project=docs docs/make.jl`, then open
`docs/build/index.html`. The design specification is
[`Sturm-PRD-v2.md`](Sturm-PRD-v2.md); every Julia block in it is parsed by the
test suite on every run, so its examples cannot rot.

## How claims are sourced

Every quantum operation, kernel identity, and error bound here is grounded in
a named paper and a specific equation, not in a passing test case. The
citations live in [`docs/physics/`](docs/physics/) as short distillations —
theorem numbers, equations, page pins — and docstrings link to those files; a
lint in the test suite checks that every citation in `src/` resolves. The PDFs
themselves are **never committed**: they are third-party copyrighted work and
this repository is public. If a distillation names a paper you do not have,
download it; the `.md` tells you exactly which result to look for.
Load-bearing ones include
[Bennett 1973](docs/physics/bennett_1973_logical_reversibility.md) (reversible
computation), [Grover 1996](docs/physics/grover_1996_search.md),
[Gottesman 1997](docs/physics/gottesman_1997_stabilizer_codes.md) (stabilizer
codes), [Childs 2019](docs/physics/childs_2019_trotter_error.md) (Trotter
error), and [Eastin–Knill 2009](docs/physics/eastin_knill_2009_no_universal_transversal.md)
(why fault tolerance is refused rather than faked).

## Contributing

Issues are tracked with [beads](https://github.com/steveyegge/beads) (`bd
ready` shows available work). Changes to the core types, the context
interface, the kernel, or the Orkan FFI go through design review with
independent proposals first — these are the parts where a sign error stays
invisible until entanglement amplifies it, and the controlled-phase bug class
recurred in Cirq, Qiskit and pytket for *years*. Tests come first, at the
channel level rather than measurement averages. There is no CI; run
`Pkg.test()` before you push.

The previous prototype — Shor, QSVT, the Steane code, hardware transport —
lives on the [`v0.1-deprecated`](../../tree/v0.1-deprecated) branch, retired
deliberately: its primitives were Bloch-sphere angles, coordinates pretending
to be operators, and everything built on them inherited that. The axioms
survived the rebuild; the primitives did not.

## License

AGPL-3.0-only. Every file carries the header.
