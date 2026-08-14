# Sturm.jl

**A Julia quantum programming language in which functions are channels, the
quantum–classical boundary is a type cast, and error correction is a
higher-order function.**

Sturm is a domain-specific language embedded in Julia for writing quantum
programs that read like programs. There are no gates, no circuits, and no
rotation angles in the language you write: you prepare a register with a cast,
act on it with ordinary-looking operators, and read it back with another cast —
and it is the compiler, not you, that decides what unitaries those become.
Underneath sits
[Orkan](https://github.com/Timo59/orkan), a C17 statevector and density-matrix
simulator that does the linear algebra while Julia owns the type system.

Here is a complete quantum program. It prepares a fair quantum coin, entangles a
second register with it, and measures both.

```julia
using Sturm

Sturm.eager(2) do ctx        # a 2-qubit sandbox, torn down when the block exits
    a = QBool(0.5)           # a fair quantum coin — |0⟩ and |1⟩, equally weighted
    b = false ⊻ a            # xor a fresh `false` with it: now they are entangled
    Bool(a) == Bool(b)       # => true — on every single run, forever
end
```

Each individual outcome is a coin flip (`(true, true)` and `(false, false)` come
up about equally often), but the two *always agree*. That agreement is the
entanglement, and nowhere did you write a Hadamard or a CNOT. `QBool(0.5)` is a
cast from a probability into a quantum register; `⊻` is exclusive-or, doing what
exclusive-or does; `Bool(q)` is a cast back out, which *consumes* its argument
because measurement is destructive and the type system says so.

> **The house rule.** If your program reads like a circuit diagram, it is wrong.
> If it mentions a gate, a rotation angle, or a matrix, it is not surface code.
> If it reads like ordinary Julia with a few casts and views, it is probably
> right.

## Where to go

The documentation is split four ways by what you are trying to do.

**Learning — start here, in order.**

- [Installation](getting_started/installation.md) — Julia 1.11+, building the
  Orkan backend, and the one-line check that it worked.
- [Your first program](getting_started/first_program.md) — a real REPL session,
  line by line, with real random outcomes.
- [Choosing a context](getting_started/choosing_a_context.md) — sampling versus
  exact distributions versus building a circuit as data, and how big each one
  can get.

**Tutorials — worked algorithms, start to finish.**

- [Teleportation](tutorials/teleportation.md) — the flagship: no-cloning made
  visible in the types.
- [Deutsch–Jozsa & Bernstein–Vazirani](tutorials/deutsch_jozsa.md) — phase
  kickback from an ordinary Julia function.
- [Grover search](tutorials/grover.md) — amplitude amplification as a
  higher-order function.
- [Shor order finding](tutorials/shor.md) — modular arithmetic and the
  continued-fraction driver.
- [Hamiltonian simulation](tutorials/hamiltonian_simulation.md) — Trotter,
  QDrift, and error bounds you can hold the code to.
- [Error correction](tutorials/error_correction.md) — encoding a program, not a
  gate set.

**Tasks — you know what you want, you want the recipe.**

- [Measure statistics](howto/measure_statistics.md) — getting probabilities out,
  and which of the three tools is the right one.
- [Write oracles](howto/write_oracles.md) — turning a Julia function into a
  reversible quantum operation.

**Understanding — why the language is shaped this way.**

- [Functions are channels](explanation/functions_are_channels.md)
- [The seven constructs](explanation/seven_constructs.md)
- [Views and duality](explanation/views_and_duality.md)
- [Contexts and scope](explanation/contexts_and_scope.md)
- [Phase discipline](explanation/phase_discipline.md)
- [Gotchas](explanation/gotchas.md) — the traps, as wrong-versus-right pairs.

**Reference — dry lookup.**

- [Surface](reference/surface.md) ·
  [Contexts](reference/contexts.md) ·
  [Kernel](reference/kernel.md) ·
  [Channels](reference/channels.md) ·
  [Library](reference/library.md) ·
  [QECC](reference/qecc.md) ·
  [Oracle](reference/oracle.md)

## Status, honestly

Sturm is a research language under active development, version `0.2.0-dev`. It
is **not a registered Julia package** — you install it from a git checkout, and
you build its simulator backend yourself.

What works today: the kernel of definite operations, three execution contexts
(sampling, density-matrix, and a non-executing tracing context that builds the
program as data), all seven surface constructs, the Bennett bridge that compiles
ordinary Julia functions into reversible operations, a channel-level
intermediate representation with optimisation passes, and library
implementations of Grover search, phase estimation, Shor's order finding,
Hamiltonian simulation, and stabiliser-code error correction. The test suite
carries about 28,000 assertions and compares whole channels, not measurement
marginals.

What does not exist:

- **No hardware backend.** Everything runs on the Orkan simulator. There is no
  transport to a real device, and no plans documented here for one.
- **A hard size ceiling.** Sampling tops out around 30 qubits (16 GiB of
  amplitudes); the exact density-matrix context tops out far lower. See
  [choosing a context](getting_started/choosing_a_context.md) for the table.
- **Error correction is code-capacity only.** Encode, decode, and effective
  logical noise are real; a fault-tolerant lift of an arbitrary gate set is
  refused on purpose, because no such thing exists for a general stabiliser
  code.
- **`oracle` needs a sibling checkout.** The Julia-function-to-reversible-
  operation compiler lives in [Bennett.jl](https://github.com/tobiasosborne/Bennett.jl)
  and loads as an optional extension. Without it, `oracle` raises an error
  naming the fix.
- **No continuous integration.** Tests are run locally, by hand.
- **No published benchmark numbers.** There are none in this documentation
  because none have been measured; invented ones would be worse than silence.

## Reading further

The normative design document is [`Sturm-PRD-v2.md`](https://github.com/tobiasosborne/Sturm.jl/blob/main/Sturm-PRD-v2.md)
in the repository root. Every paper the implementation leans on has a short
distillation — theorem numbers, equations, page pins — committed under
`docs/physics/`; the PDFs themselves are deliberately not in the repository,
because they are third-party copyrighted work and this repository is public.

Sturm.jl is licensed **AGPL-3.0-only**.
