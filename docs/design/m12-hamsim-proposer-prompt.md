# M12 Proposer Prompt — Hamiltonian Simulation Module (bead Sturm.jl-bog7)

You are ONE of TWO independent proposers (CLAUDE.md Principle 2: 3+1 rule).
You must NOT see the other proposer's output. Your deliverable is a DESIGN
DOCUMENT, not code. Do not modify `src/` or `test/`. Do NOT run Julia
(standing rule: concurrent Julia processes corrupt the compile cache).

## Mission

Design the M12 Hamiltonian-simulation module for Sturm.jl v2: the strategy
layer behind `evolve!`, covering deterministic product formulas (Suzuki
order-2k), qDrift, and composite qDrift (Hagan–Wiebe) — the proven
gate-count frontier per arXiv:2607.19852 — plus the error-bound machinery,
`Auto` dispatch, channel-level verification harness, and benchmark design.

## Decisions already made by Tobias (2026-07-23) — NOT up for redesign

1. **Surface**: `evolve!(x, H, t; alg=...)` with strategy objects
   (`Trotter(...)`, `QDrift(...)`, `Composite(...)`, `Auto()` default).
   Current M10 kwargs `steps`/`order` remain as sugar for `Trotter`.
2. **Scope**: product formulas only. QSVT/LCU/qubitization are DEFERRED
   (analytic cost curves may appear in benchmark reports; no implementation).
3. **Randomization is trajectory-level for now**: per-shot classical
   sampling of a deterministic circuit (via the `shots` HOF on Eager).
   The API must be designed to lower to M11's future Kraus/mixture values
   with ZERO surface change, but M12 does not build channel values.
4. Process: you propose; a second proposer proposes independently; an
   implementer synthesizes; the orchestrator reviews.

## Ground truth you MUST read (all local)

Papers (docs/literature/, tex source in `<id>_src/`, PDFs alongside):
- **2607.19852** (Zlokapa–Allen–Harrow, "Optimal Lower Bounds for
  Hamiltonian Simulation") — the frontier Θ(min_K(Kt + t²λ_K²/ε)), the
  optimal-K lemma (cut until tail second moment Σ_{j>K} a_j² ≲ ε), and
  Appendix A's re-derivation of the composite cost bound (Fact HW).
- **2206.06409** (Hagan–Wiebe, "Composite Quantum Simulations") — THE
  algorithm to implement: Thm 2.1 cost bound and the operational
  interleaving of order-2p Trotter (head) with qDrift (tail). Read the
  actual construction, not just the bound.
- **1811.08017** (Campbell, qDrift) — Thm 1: diamond error
  ε ≤ (2λ²t²/N)e^{2λt/N}; the sampling distribution p_j = a_j/λ.
- **1912.08854** (Childs–Su–Tran–Wiebe–Zhu, Trotter error) — commutator
  scaling α_comm; already distilled at
  docs/physics/childs_2019_trotter_error.md.
- **1612.02689** (Campbell, mixing lemma), **1612.01011** (Hastings),
  **2008.11751** (Chen–Huang–Kueng–Tropp, concentration) — why mixture
  errors compose in diamond norm and why typical ≈ average.
- **suzuki_1991_JMP32_400.pdf** — recursive fractal decomposition,
  Eq. (1.1)/(3.14–3.16): the order-2k coefficients.
- Optional context: 1805.08385 (randomized permutation Trotter),
  1910.06255 (stochastic sparsification) — you may propose these as
  additional strategies ONLY if they fit cleanly; they are not required.

Existing v2 code you MUST read:
- `src/library/evolve.jl` — `PauliTerm`, `_normalize_hamiltonian`,
  `_pauli_exp!`, `evolve!` orders 1–2. This is the seed to extend.
- `src/library/{grover.jl,qpe.jl}` — library-layer conventions (exports vs
  `public`, docstring citation style, region usage).
- `src/surface/cases.jl` (`shots`), `src/context/{eager,density}.jl`,
  `src/kernel/{u2.jl,ctrl.jl}`, `src/channel/dag.jl` (KrausFamily seam,
  NoiseN barrier), `test/test_m10_library.jl` (op_matrix harness, test
  conventions), `test/choi.jl`, `test/runtests.jl` (boot lints: citation
  lint, `\bcontrolled\b` word ban outside kernel/orkan).
- `Sturm-PRD-v2.md` §1.3, §2, §5 (evolve! is library; "Nature does not
  hand out Hamiltonians"), §4.1/§4.1a (unitarity witness), §3.9.

## Hard constraints (violations = rejected design)

- NO `Hamiltonian` kernel value. H stays a library-level value
  (`Vector{PauliTerm}` or a light wrapper — your call, argue it).
- NO wrapping the stochastic ensemble as `UnitaryBlock`/ProcessValue —
  the CPTP average is a channel; individual sampled branches are ordinary
  `apply!` sequences. `certify` refuses barriers by design.
- NO non-unitary effects under a live control frame (`_assert_no_control`).
- NO surface spelling for angles/gates; everything reachable only through
  the `evolve!` HOF signature.
- FAIL FAST: no silent bound fallbacks (v0.1's `alpha_comm` p≥3 silently
  substituted a bound up to 1e9× looser — that class of bug is banned).
  Unsupported orders/parameters must `error()`/`throw`.
- Core `Project.toml` gains NO dependencies. Benchmarks live in `bench/`
  with their own environment.
- Every equation you rely on cites a `docs/physics/<name>.md` distillation
  (Phase 0, running in parallel, is writing: campbell_2019_qdrift,
  campbell_2017_mixing_unitaries, hastings_2016_incoherent_errors,
  hagan_wiebe_2023_composite, chen_2021_concentration_random_products,
  zlokapa_2026_hamsim_lower_bounds, suzuki_1991_fractal_decomposition —
  cite these names).
- The word "controlled" (whole word) is lint-banned outside
  `src/kernel|orkan` — use "ctrl"/"conditional" in docstrings.
- Julia idiomaticity is paramount; width as type parameter; type-stable
  hot paths; explicit RNG threading for all randomness.

## v0.1 lessons you MUST design against (from the quarry report)

1. Basis-change sign bug shipped TWICE (`H!` vs `Ry(-π/2)`: H!†ZH! = −X)
   — invisible to measurement-statistics tests. Design deterministic
   amplitude/matrix-level tests as the default, statistics as supplements.
2. GQSP operator-ordering bug passed |P(z)|²-statistical tests "by
   mathematical coincidence" — ordering must be pinned by full-operator
   comparison against dense `expm`.
3. qDrift/composite interleave schedule silently truncated remainders
   (`max(1, total÷steps)`) — your schedule must be exact and tested.
4. Marginal (Z-population) tests are structurally blind to phase/ordering
   bugs. Channel-level or full-operator comparisons only.
5. Large-N statistical ground-truth tests took 13+ min and got KILLED in
   CI — design the fast/heavy test tiering up front.
6. LSB-first Orkan wire ordering cost a debugging cycle — pin conventions
   in one place with a test.

## Design questions your document MUST answer

1. **Strategy types**: exact Julia definitions for `Trotter`, `QDrift`,
   `Composite`, `Auto` (fields, defaults, validation, what's exported vs
   `public`). How `steps`/`order` sugar maps onto them. Where files live
   (`src/library/evolve.jl` split into a subdirectory?).
2. **Hamiltonian representation**: keep `(coeff, word::String)` PauliTerm
   or upgrade (e.g. bitmask X/Z encoding enabling symbolic Pauli algebra)?
   Must support: λ = Σ|a_j|, sorting, tail second moments, and exact
   nested-commutator norms. Argue the choice; migration from M10's type.
3. **Suzuki order-2k**: recursion scheme (Val-dispatch vs runtime),
   coefficient generation and their exactness, stage counts Υ = 2·5^(p−1).
4. **α_comm**: exact computation via Pauli algebra ([P,Q] of Pauli strings
   is a Pauli string up to scalar) — algorithm, complexity guard (the
   (2p+1)-fold sum explodes; where do you cap and how do you fail loud),
   and the `trotter_steps(H, t, ε; order)` API on top.
5. **QDrift**: sampler design (cumulative distribution, rng), N selection
   from ε, interaction with `shots` (who owns the per-shot loop?).
6. **Composite**: head/tail split via the optimal-K criterion, the
   interleaving schedule (exact), parameter surface (what the user may
   override), N_B choice (Fact HW's last term: 4Υλ_B²t²/(N_Bε)).
7. **Auto**: the dispatch rule from (a⃗ sorted, t, ε, L, optionally
   α_comm) — grounded in the optimal-K lemma, with the decision boundary
   testable against benchmarks.
8. **Verification architecture**: named tests per CLAUDE.md #10/#12 —
   deterministic op-matrix tests, bound-conformance (untuned), ensemble-
   averaged-superoperator channel tests for randomized strategies (how
   exactly is the average built and compared; sample counts; norms),
   amplitude probes, tier assignment (CI vs heavy).
9. **bench/ design**: environment, metrics (operator-exponential count as
   the paper's unit — where is the counter instrumented without polluting
   the hot path?), frontier-curve protocol, model Hamiltonians
   (coefficient-tail families: uniform, power-law, exponential).
10. **Forward compatibility**: how each strategy later lowers to M11
    mixture/Kraus values; whether a future ctrl-`evolve!` (QPE on
    e^{-iHt}) is precluded by anything you propose (it must not be).

## Deliverable

Write your complete design to the file path given in your task message.
Sketch key type/function signatures in Julia (no full implementations).
Cite papers by equation/theorem numbers. Flag every open question you
could not resolve as an explicit research step (Principle 8). Your final
text response should be a ~30-line executive summary of the design.
