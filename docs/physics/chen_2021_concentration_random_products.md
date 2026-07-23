# Chen–Huang–Kueng–Tropp 2021 — Concentration for Random Product Formulas

**Source (local):** `docs/physics/chen_2021_concentration_random_products.pdf`
— C.-F. Chen, H.-Y. Huang, R. Kueng, J. A. Tropp, *Concentration for random
product formulas* (arXiv:2008.11751). LaTeX source at
`docs/literature/2008.11751_src/main.tex` (§2 Main Results, `thm:allinput`,
`cor:exp_allinput`, `thm:fixedinput`, `cor:exp_fixedinput`,
`thm:summary_of_errors`, `cor:randomsuzuki`). Underlies/generalizes
Campbell's original qDRIFT average-channel guarantee (`campbell2019random`
in the bib — restated at line 199-203 of the source as the reference point
this paper improves on).

## What Sturm uses this for

Hagan–Wiebe's Composite channel (`hagan_wiebe_2023_composite.md`) resamples
a FRESH batch of `N_B` i.i.d. qDrift draws at every outer step, and every
diamond-norm bound it cites (Theorem `thm:QDrift`, and hence Theorem 2.1's
cost bound) is stated for the AVERAGE qDrift channel `𝒰_QD = 𝔼_V[V·V†]`.
An actual run of `evolve!` under the Composite mode does not execute the
average channel — it executes ONE randomly-sampled trajectory (a fixed,
if random, sequence of gates) per shot. This paper is what licenses that
substitution: it proves that a SINGLE typical realization of a random
product formula is close to the ideal unitary in diamond norm too, with an
explicit, only-mildly-worse gate count — so an average-channel error bound
can be read as (and requires reproving for) a high-probability
single-trajectory guarantee. Any Composite-mode `evolve!` correctness test
that samples one Julia RNG trajectory and diamond-norm-compares it to
`e^{-iHt}` is implicitly relying on THIS paper, not on `thm:QDrift` alone.

## Setup

`n`-qubit Hamiltonian `H = Σ_j h_j`, `λ := Σ_j ‖h_j‖`. The qDRIFT random
product formula (Eq. `eq:qDRIFT`, restating Campbell): at each of `N` steps,
draw `X_k ~ X` i.i.d. from `X = (λ/‖h_j‖)·h_j` with probability
`p_j = ‖h_j‖/λ`, and apply `V_k = exp(-i(t/N)X_k)`. The realized product
formula is `V^{(N)} = V_N⋯V_1` (a single random unitary — one draw per
gate). The paper's central question (line 337-339): is qDRIFT's
`L`-independent gate count `N = O(λ²t²/ε)` (Eq. `eq:qDRIFT_gate_count`) a
property of the AVERAGE channel `𝒱^{(N)}(X) := 𝔼[V_N⋯V_1 X V_1†⋯V_N†]`
only, or does a single sampled instance already inherit it? Answer: a
single instance already inherits it, up to a `√n` overhead.

## The main concentration inequalities (§2, Main Results)

Two distinct operational settings, two different norms:

**(1) Worst-case over ALL input states/observables — diamond distance.**
`dist_⋄(U₁,U₂) = max_{|ψ⟩} max_{‖O‖≤1} |⟨O⟩_{U₁|ψ⟩} − ⟨O⟩_{U₂|ψ⟩}|`
(Eq. line 388-390; equals the trace-norm diamond distance between the two
unitary channels). Theorem `thm:allinput` (**qDRIFT: Gate complexity for
small diamond distance**): drawing `V_N⋯V_1` with gate count

    N ≥ Ω((n + log(1/δ)) t²λ²/ε²)                                    (eq:randomgate)

guarantees, WITH PROBABILITY AT LEAST `1-δ`, that
`max_{|ψ⟩} max_{‖O‖≤1} |⟨O⟩_{V_N⋯V_1|ψ⟩} − ⟨O⟩_{e^{-iHt}|ψ⟩}| < ε` for
THIS SINGLE sampled realization — a genuine tail/concentration bound, not
an expectation. Corollary `cor:exp_allinput` restates it as an expected
error: `𝔼[diamond-distance-type quantity] ≲ sqrt(nt²λ²/N)` — compare
against the AVERAGE-CHANNEL bound from Campbell,
`‖𝔼_V[…] − ideal‖ ≲ t²λ²/N` (no square root): the single-instance error
is `sqrt(·)`-worse than the average-channel error, i.e. scales as `1/√N`
rather than `1/N` in the same regime — the price of not being allowed to
average over many resampled trajectories.

**(2) Fixed (but arbitrary/unknown) input state — trace distance.**
Theorem `thm:fixedinput` (**qDRIFT: Gate complexity for fixed input**):
for ANY fixed `|ψ⟩`, gate count

    N ≥ Ω(t²λ² log(1/δ)/ε²)                                          (eq:singlerandomgate)

guarantees, with probability `≥ 1-δ`, that the single sampled output state
`V_N⋯V_1|ψ⟩` is `ε`-close in trace distance to the ideal `e^{-itH}|ψ⟩` —
note NO `n`-dependence (an `n`-fold improvement over the worst-case-input
bound (1), since one no longer has to control every one of the `2ⁿ`-dim
input directions simultaneously — the diamond norm's extra `n` in bound (1)
is literally `log(dim) = log(2ⁿ) = n·log2`, the usual matrix-concentration
dimensional factor). Corollary `cor:exp_fixedinput`: expected error
`≲ sqrt(t²λ²/N)`, i.e. `1/√N` again, no `n`.

**(3) The general martingale bound this specializes.** Theorem
`thm:summary_of_errors` (**general concentration bounds for products of
random unitaries**) is the mechanism behind both (1) and (2), stated for
ANY causal random product `V = V_N⋯V_1` approximating a target
`U = U_N⋯U_1` where each step obeys `‖V_k − 𝔼_{k-1}V_k‖ ≤ a_k` (per-step
fluctuation) and `‖𝔼_{k-1}V_k − U_k‖ ≤ b_k` (per-step bias), `𝔼_{k-1}`
denoting conditional expectation given `V_1,…,V_{k-1}` (causality, Eq.
`eq:causality` — each step's randomness may depend on the PAST but not the
future, satisfied trivially by i.i.d. qDrift draws). Then:

    ‖𝒰 − 𝒱‖_⋄            ≤ 2Σ_k a_k                          (worst case, deterministic bound)
    𝔼‖𝒰 − 𝒱‖_⋄            ≲ sqrt(n Σ_k a_k²) + 2Σ_k b_k        (TYPICAL/single-realization case)
    𝔼‖𝒰(ρ) − 𝒱(ρ)‖_1      ≲ sqrt(Σ_k a_k²) + 2Σ_k b_k          (fixed input)
    ‖𝒰 − 𝔼[𝒱]‖_⋄          ≤ 2Σ_k b_k                          (AVERAGE-channel case)

(Theorem `thm:summary_of_errors`, line 526-541; `≲` suppresses absolute
constants). **This is the pinned inequality**: it is a genuine
matrix/vector-martingale concentration result (built on the machinery in
Appendix `sec:intro_martingale`, "Matrix and vector valued martingales",
via a Freedman-type inequality, Cor. `cor:freedman`) — the fluctuation term
`sqrt(nΣa_k²)` (resp. `sqrt(Σa_k²)` for fixed input) is a TAIL/concentration
term (finite with high probability, not just in expectation — Theorems
`thm:allinput`/`thm:fixedinput` are the tail-probability versions of this
same expectation bound), while the bias term `2Σb_k` is a purely
deterministic, non-random systematic-error term. The qualitative punchline
(line 429-436): the AVERAGE-channel error (`Σb_k` only, `∝ 1/N`) is smaller
than the TYPICAL single-realization error (`sqrt(Σa_k²)` term added,
`∝ 1/√N`) — averaging over resampled trajectories removes the fluctuation
term entirely but is not physically realizable as a single run; single
realizations pay a `√N` (equivalently `1/√ε`-worse-than-average) but ARE
physically realizable and still concentrate.

## What this licenses

Any diamond-norm or trace-distance bound proved for the AVERAGE qDrift
channel (Campbell's, or Hagan–Wiebe's `thm:QDrift`/Theorem 2.1 built on
top of it) is a bound on `‖𝒰 − 𝔼[𝒱]‖_⋄`, i.e. the bottom line of Theorem
`thm:summary_of_errors` above. It is NOT automatically a bound on any given
sampled trajectory — that requires the SEPARATE, larger `N`-scaling from
the "typical case" or "fixed input" lines. Concretely, for Sturm's
Composite `evolve!`:

- If a test compares ONE EagerContext-sampled Composite-channel run against
  `expm(-iHt)` via `‖·‖` (state/channel-level, per `CLAUDE.md` principle 12
  — never marginals), the correct target tolerance to size `N_B` against
  is the TYPICAL/fixed-input line of Theorem `thm:summary_of_errors`
  (equivalently Theorem `thm:fixedinput`'s `N ≥ Ω(t²λ²log(1/δ)/ε²)` if a
  probabilistic high-confidence guarantee is wanted), NOT the bare
  average-channel `4λ_B²t²/ε` from Hagan–Wiebe's `thm:QDrift` — using the
  average-channel `N_B` and expecting a single run to hit `ε` is
  under-provisioned by roughly a factor of `1/ε` relative to the correct
  single-trajectory count (`1/ε²` vs `1/ε` scaling — Cor. `cor:exp_allinput`
  vs Theorem `thm:QDrift`).
- Conversely, if a test instead statistically AVERAGES over many
  independently-reseeded EagerContext runs (N≥1000 samples per `CLAUDE.md`
  principle 10) and compares the resulting empirical channel/state
  statistics to the ideal channel, the weaker average-channel bound
  (`4λ_B²t²/ε`, `1/ε` scaling) is the correct, tighter target — this is
  literally what `𝔼[𝒱]` means operationally.
- The per-step qDrift FRESH resampling in Hagan–Wiebe's operational
  construction (`hagan_wiebe_2023_composite.md` §(b)) is exactly the
  "causal, small-step" random-product setting of Theorem
  `thm:summary_of_errors` (each outer step's `B`-batch is i.i.d., new
  randomness each step, satisfying causality trivially) — so this paper's
  concentration bound applies per-step-batch, then composes across the `r`
  Composite outer steps by the same triangle-inequality/subadditivity
  argument Hagan–Wiebe already use for their own per-step error budgeting
  (their Eq. `eq:err_to_err_per_iter`, `‖X^{∘r}-Y^{∘r}‖_⋄ ≤ r‖X-Y‖_⋄`).

## Secondary result used incidentally: the Mixing Lemma

Lemma `lem:mixing_maintext` (**Mixing lemma**, a sharpened version of
Hastings/Campbell's randomized-compiling mixing lemma): for fixed unitary
`U_k` and random unitary `V_k`, `‖𝒰_k − 𝔼𝒱_k‖_⋄ ≤ 4‖U_k − 𝔼V_k‖` — i.e. an
AVERAGE channel's diamond-distance error is controlled LINEARLY by the
average OPERATOR-norm error of the underlying random unitary (not
quadratically, despite the channel being a bilinear/quadratic function of
the unitary) — noted here because it is the general mechanism behind why
qDrift-type average-channel bounds (Hagan–Wiebe's Theorem `thm:QDrift`,
ultimately Campbell's) can be derived from operator-norm single-step
bounds at all; not itself directly used by the Composite `evolve!` design
but underlies why the operator-norm bookkeeping in both papers transfers
cleanly to diamond-norm channel bookkeeping.

## Used by Sturm for

Justifies treating a single sampled qDrift/Composite trajectory (what
`EagerContext` actually executes) as obeying a high-probability diamond- or
trace-distance guarantee, rather than only an average-channel guarantee —
required whenever `evolve!`'s Composite mode (`hagan_wiebe_2023_composite.md`)
is tested against a single run instead of an ensemble average. Pins the
CORRECT `N_B`/`N` scaling (`1/ε²`, single-trajectory, Theorem
`thm:allinput`/`thm:fixedinput`) to use for such single-run tests, as
opposed to the weaker `1/ε` average-channel scaling (Hagan–Wiebe's
`thm:QDrift`) which is only valid as a statement about `𝔼[channel]`, i.e.
for statistically-averaged multi-run tests. Any M11+ Composite-mode test
suite needs to pick, and document, which of these two regimes it is
targeting before choosing a tolerance.
