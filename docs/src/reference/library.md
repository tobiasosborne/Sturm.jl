# Reference — the algorithm library

```@meta
CurrentModule = Sturm
```

*Dry, exhaustive lookup. The tutorials are the place to learn these:
[Grover](../tutorials/grover.md), [Shor](../tutorials/shor.md),
[Hamiltonian simulation](../tutorials/hamiltonian_simulation.md).*

These are the physicist-facing higher-order functions — algorithms written
against the surface language, not new primitives. `amplify`, `find`,
`phase_estimate`, `evolve!`, `interfere!`, `shor_order`, and the four `evolve!`
strategy descriptors are **exported**; everything else on this page is `public`
but not exported.

---

## Amplitude amplification and search

`amplify` runs the Grover iterate with a caller-supplied phase marker — you put
the register into the state you want to amplify about first. `find` is the
batteries-included form: it builds the marker from a predicate through the
[oracle bridge](oracle.md), so it needs `using Bennett`.

One honest caveat carried in the docstring: if you do not supply `nsolutions`,
`find` counts them by scanning classically. That is a correctness convenience
for demonstrations, not part of the quantum speedup.

```@docs
amplify
find
grover_iterations
interfere!
```

## Phase estimation

Textbook QPE: a phase register, a conditional-power ladder, and a readout in
the register's Fourier dual. The eigenstate must be prepared by the caller and
stays live afterwards.

```@docs
phase_estimate
```

## Order finding

`shor_order` is the capstone: repeated quantum phase samples, classical
continued-fraction post-processing, and exact verification. Every value it
returns has been checked; when it cannot answer it throws rather than guessing.
A non-coprime base is not a failure — the error carries the factor it found,
which is Shor's classical shortcut.

```@docs
shor_order
NonCoprimeBaseError
OrderFindingFailure
```

## Hamiltonian simulation

`evolve!` simulates `e^{-iHt}` in place. `H` is any iterable of
`(coefficient, Pauli word)` pairs, a vector of `PauliTerm`, or a `PauliSum`.

**There is no default accuracy.** A bare `evolve!(x, H, t)` with neither a
target error nor explicit resources is an `ArgumentError` — the library will
not silently pick a step count for you. Two calling styles:

```julia
evolve!(x, H, t; steps = 40, order = 2)            # explicit resources
evolve!(x, H, t; alg = Trotter(order = 4), ε = 1e-6)  # accuracy-driven
```

`QDrift` and `Composite` are randomized: **one call is one sampled
trajectory**, not the averaged channel. Both are therefore refused on the
density and tracing contexts, and inside a `when` body — loudly, in each case.

```@docs
evolve!
Trotter
QDrift
Composite
Auto
```

### Model families

Ready-made benchmark Hamiltonians.

```@docs
ising_chain
heisenberg_chain
powerlaw_chain
```

### Pauli algebra

The symplectic representation `evolve!` normalises into: exact integer
commutator and product algebra, no string re-parsing in hot loops.

```@docs
PauliWord
PauliTerm
PauliSum
letter_at
commutes
mulword
mulword_word
is_identity
nterms
iscommuting
```

### Product formulas and error bounds

Suzuki's fractal recursion, with a hard cap; the exact nested-commutator
bounds that turn a target accuracy into a step count; and the randomized
counterparts. `BoundReport` carries the value together with which formula
produced it and its citation.

```@docs
suzuki_stage_scales
suzuki_sweep_count
SUZUKI_MAX_P
alpha_comm
alpha_comm_pairs
alpha_comm_cross
alpha_comm_layered
alpha_comm_cross_layered
AlphaLayered
AlphaCommBlowup
ALPHA_MAXWORDS_DEFAULT
ALPHA_WORK_DEFAULT
trotter_steps
trotter_error_bound
qdrift_samples
qdrift_error_bound
composite_steps
composite_error_bound
composite_nb
composite_k
composite_outer_slots
BoundReport
```

### Plans and automatic strategy choice

`plan_evolution` turns a strategy plus an accuracy target into an immutable
plan. `Auto` ranks candidates by *proven* surrogate cost — it never
under-prices, so its documented failure mode is one-sided: it may over-price a
strategy and pick a more expensive one than necessary.

```@docs
EvolveAlg
EvolvePlan
TrotterPlan
QDriftPlan
CompositePlan
plan_evolution
evolve_plan
EvolveChoice
PlanRow
trajectory
exp_count
AUTO_COMMUTING_GATE
```

## Internals (public, not exported)

Documented and reachable, but not the teaching surface. Listed so that the
reference is complete.

### Grover and phase-marking builders

```@docs
_mcz_all_ones!
_grover_diffuse!
_phase_mark_oracle!
_pauli_exp!
```

### Order-finding internals

```@docs
_shor_phase_sample
_cf_denominator
_minimize_order
_ideal_mulmod_perm
```

### The in-place permutation compiler

The machinery behind `mulmod!`. Given a function and a separately compiled
inverse, it builds a clean in-place permutation and then *verifies* it — either
exhaustively or against a registered analytic proof. A wrong inverse is
rejected with a counterexample.

```@docs
compile_inplace_perm
verify_inverse_pair
VerifiedInversePair
CompiledInplacePerm
AbstractInplaceProof
FullSpaceMulProof
InverseContractError
permclean_cert
```

## See also

- [Reference: the surface](surface.md) — `mulmod!`, `superpose!` and the
  register types these HOFs operate on.
- [Reference: the oracle bridge](oracle.md) — what `find` uses internally.
- [Hamiltonian simulation tutorial](../tutorials/hamiltonian_simulation.md).
