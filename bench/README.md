# bench/ — M12 Hamiltonian-simulation frontier harness

The M12 phase-4 bench (bead `Sturm.jl-gmx0`): frontier cost curves for
`evolve!`'s strategy family and validation of `Auto`'s dispatch rule against
the Zlokapa–Allen–Harrow envelope. Own environment (`bench/Project.toml`,
Sturm dev-pathed, stdlibs only); nothing here ships in `src/`.

## Run

```bash
julia --project=bench -e 'using Pkg; Pkg.instantiate()'   # once
julia --project=bench bench/hamsim/run.jl --fast          # ~2 min smoke
julia --project=bench bench/hamsim/run.jl --only=exec     # measured tier
julia --project=bench bench/hamsim/run.jl --only=analytic # cost curves
julia --project=bench bench/hamsim/run.jl                 # full grid
julia --project=bench bench/hamsim/run.jl --alpha=exact   # exact-α policy
```

Output: `bench/out/{frontier,auto,alpha}-<tag>.csv` (gitignored) plus a
printed summary.

**α policy (c8rx).** Which grid rows plan at `:exact` vs `:norm1` α is an
explicit run configuration — `--alpha=budgeted` (default; the probe
work-caps the exact-α DP with machine-independent step budgets),
`--alpha=exact` (exact everywhere; only the deterministic
`AlphaCommBlowup` cap exit downgrades), or `--alpha=norm1`. It is NEVER
decided by wall-clock — the gmx0-era timed probes made mode selection
load-dependent, and it bit in session 103 (five L=256 families planned
differently on a loaded box). Non-default policies get their own file tag
(`frontier-all-exact.csv`), so runs under different policies never shadow
each other and are never accidentally compared.

**Determinism.** Given the same command (thus the same policy), two runs on
any machine at any load emit identical CSVs — except the `probe_seconds`
diagnostic column of `alpha-*.csv` (wall-clock, kept for calibration; it
influences nothing). Wall-clock can only ABORT a run loudly
(`PROBE_TIMEBOX_S`, `--alpha=exact` only), never change what is computed.

## What is measured

Every family is normalized to λ = Σ|aⱼ| = 1 (the ZAH convention), so `t` is
the papers' dimensionless λt. Grid: t ∈ {0.5,…,32} (log), ε ∈ {1e-2,1e-3,1e-4}
(full diamond norm, S5). Cost unit: operator exponentials = `exp_count(plan)`.

- **Certified cost** — `exp_count(plan_evolution(alg, hs, t; ε))` for
  Trotter{2,4,6}, QDrift, Composite{2,4}, Auto: the proven-bound resource
  count, exactly what a user gets.
- **Measured cost** (executed families, W ≤ 3) — binary-searched minimal
  resources whose *exact* dense (super)operator Choi distance to e^{−iHt}
  is ≤ ε. Deterministic plans compare as unitaries of their own sweeps;
  randomized plans as exact enumerated ensemble superoperators (zero
  sampling noise). Choi trace-norm lower-bounds the diamond norm, so
  measured costs are if anything optimistic and `slack` upper-bounds the
  constants' true looseness.
- **Reference curves** — the ZAH envelope `min_K(Kt + t²λ_K²/ε)` (eq lb; an
  Ω(·) bound — shape normative, constant not) and the analytic QSP overlay
  `L(t + log(1/ε)/loglog(1/ε))` (eq qsp; analytic only, per ruling — no
  implementation, and per ZAH's own thesis its query count hides an O(L)
  SELECT construction cost).

## Columns

`frontier-*.csv`: one row per (family, t, ε, strategy).
`certified_cost` empty ⇒ skipped, reason in `skipped`. `plan_kind` shows
Composite degenerations (K=0 → QDriftPlan, K=L → TrotterPlan). `slack` =
certified/measured. `cert_over_env` = certified/envelope. `alpha_mode` is
the α_comm mode the row's planning ACTUALLY used (`:norm1` only ever by the
bench's explicit opt-in, recorded — never silent).

`auto-*.csv`: per cell — Auto's choice, its certified cost, the best
concrete strategy, `regret` = auto_cost/best_cost, measured-argmin agreement
(executed tier), the proxy-K (second-moment seed) vs exact `composite_k`
disagreement flag, and the α provenance of the CHOSEN dispatch row
(`auto_alpha_layers` = the shallowest exact DP depth behind it,
`auto_alpha_exact` = whether every α it consumed was the exact α_comm; empty
for rows that consume no α — QDrift and the exactness fast paths).

`alpha-*.csv`: the R4 probe table — per (family, order): the modes the grid
rows plan at, exact α_comm value (empty when the policy's probe did not
prove it exact; a budget stop records the proven partial bound `B_d` in the
note instead), the :norm1 bound, their ratio (the DP's tightness win),
probe seconds (diagnostic only — the one nondeterministic column), the
downgrade reason if any (cap hit / work budget / policy), and the run's
α policy.

## Interpretation

Read the frontier per (family, ε) along t: Trotter (high order) owns tight-ε
/ structured cells, QDrift owns loose-ε short-t cells with flat coefficient
tails, Composite owns the head-heavy interior (power-law/exp tails) — that
crossover structure IS the ZAH theorem, and Auto's job is to sit on the
lower envelope of the certified curves (regret ≈ 1). Regret > 1 marks cells
where Auto's BUDGETED α surrogate (`alpha_comm_layered`, bead
`Sturm.jl-jpky`: exact wherever the DP fits `ALPHA_WORK_DEFAULT`, a proven
partial-depth bound otherwise) ranked strategies differently than exact-α
planning — read it together with `auto_alpha_layers`/`auto_alpha_exact`,
which say whether the row was ranked at exact α at all. Disagreement with
the *measured* argmin additionally folds in each bound's constant looseness
(per-strategy `slack`), which the dispatch rule cannot see by design —
proven costs only, never tuned constants.

Self-check: every executed configuration re-asserts
`exp_count(plan) == length(collect(trajectory(plan[, rng])))` — the one
invariant that keeps the whole report honest.
