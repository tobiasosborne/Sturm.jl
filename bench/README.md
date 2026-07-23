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
```

Output: `bench/out/{frontier,auto,alpha}-<tag>.csv` (gitignored) plus a
printed summary. Fully seeded — identical commands emit identical CSVs.

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
(executed tier), and the proxy-K (second-moment seed) vs exact
`composite_k` disagreement flag.

`alpha-*.csv`: the R4 probe table — per (family, order): exact α_comm value,
the :norm1 bound, their ratio (the DP's tightness win), probe seconds, and
whether ALPHA_MAXWORDS_DEFAULT was hit.

## Interpretation

Read the frontier per (family, ε) along t: Trotter (high order) owns tight-ε
/ structured cells, QDrift owns loose-ε short-t cells with flat coefficient
tails, Composite owns the head-heavy interior (power-law/exp tails) — that
crossover structure IS the ZAH theorem, and Auto's job is to sit on the
lower envelope of the certified curves (regret ≈ 1). Regret > 1 marks cells
where Auto's :norm1 surrogate ranked strategies differently than exact-α
planning; disagreement with the *measured* argmin additionally folds in each
bound's constant looseness (per-strategy `slack`), which the dispatch rule
cannot see by design — proven costs only, never tuned constants.

Self-check: every executed configuration re-asserts
`exp_count(plan) == length(collect(trajectory(plan[, rng])))` — the one
invariant that keeps the whole report honest.
