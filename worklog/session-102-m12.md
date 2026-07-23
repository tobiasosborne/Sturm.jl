# Session 102 — 2026-07-23 — M12 Ham-sim: scoping, Phase 0, design round (beads 90jq/v3yn/bog7)

Orchestrator session. Trigger: arXiv:2607.19852 published — Tobias wants a
complete, idiomatic, benchmarked Hamiltonian-simulation module (M12 epic
Sturm.jl-90jq). v0.1 impls consultable but NOT reference.

## The paper is not what the headline suggested

2607.19852 (Zlokapa–Allen–Harrow, MIT) is a **lower-bounds** paper:
G ≥ Ω(min_K(Kt + t²λ_K²/ε)) for arbitrary coefficient vectors (not
worst-case), via elementary local classical Hamiltonians. The matching
ALGORITHM is composite qDrift = **Hagan–Wiebe 2206.06409** (order-2p Suzuki
head + qDrift tail, optimal split where the tail second moment Σ_{j>K}a_j²
crosses ε). Implementation centerpiece is therefore HW, with ZAH supplying
the frontier envelope and the optimal-K rule. Moral for the module: dispatch
on problem type is a THEOREM (optimal K depends on the coefficient tail),
and block-encoding query counts are misleading about gate cost — QSVT
deferred with a clear conscience (Tobias ruled: analytic curves only).

## Decisions (Tobias, via review)

1. `evolve!(x, H, t; alg=…)` strategy objects: Trotter/QDrift/Composite/Auto;
   M10 steps/order kwargs stay as Trotter sugar.
2. QSVT/LCU/qubitization deferred; analytic frontier overlay only.
3. Randomization trajectory-level now (shots on Eager); API must lower to
   M11 mixture values with zero surface change. DM+randomized = loud error.
4. Full 3+1 design round (ran this session).
5. Post-synthesis rulings: **S3** bare `evolve!(x,H,t)` THROWS (ε mandatory,
   no default accuracy); **S9** deterministic ctrl-evolve! in M12 scope
   (_act! switch, R3-guarded).

## Phase 0 (v3yn, closed): 7 distillations, all from actual sources

campbell_2019_qdrift, campbell_2017_mixing_unitaries,
hastings_2016_incoherent_errors, hagan_wiebe_2023_composite,
chen_2021_concentration_random_products, zlokapa_2026_hamsim_lower_bounds,
suzuki_1991_fractal_decomposition (+ PDFs). 14 more papers (tex+pdf) in
docs/literature/ (gitignored). Catches worth remembering:

- **Campbell 2017 tex has a real typo**: derivation line reads 5ε⁵ where the
  theorem says 5ε² — arithmetic check confirms 5ε²; flagged in distillation.
- **Suzuki 1991 Fig. 1 caption mislabels p₃ as p₁** (verified numerically
  from Eq. 3.16). Never copy coefficient tables from that caption.
- **qDrift's ε is an ENSEMBLE property**: a single sampled circuit is only
  √ε-close (Campbell's own diamond-norm discussion; Chen et al concentration
  gives trajectory N ~ 1/ε² vs channel N ~ 1/ε). Test tolerances must pick
  the regime explicitly — this shaped ruling S10 and test H1.
- HW interleave recipe pinned operationally (partition ONCE; per outer step,
  A-sweep then fresh N_B-sample B-batch; palindromic under the same Suzuki
  recursion; every B-leaf freshly drawn — Υ batches per step).

## Design round (bog7, closed): proposals converged

A (physics-first) and B (host-language-first) INDEPENDENTLY chose: pure
classical planning / dumb executor over `_pauli_exp!`; symplectic bitmask
PauliWord{W} + canonical PauliSum{W}; **exact α_comm** via measure-
propagation DP (nested Pauli commutator norms ∈ {0, 2^{2p}} — the sum
collapses, no estimation, v0.1's silent 1e9×-looser fallback structurally
impossible); enumerated-ensemble superoperator tests (no sampling noise);
same-recursion outer loop for Composite. Convergence on this scale reads as
the design being forced by the constraints — good sign.

Synthesis = B's skeleton (lazy trajectory iterators, ε as call kwarg, order
cap 12, DM guard) + A's exactness (exact transcendental qDrift N criterion,
full-diamond-norm ε pinned with the factor-2 conversion in ONE function,
BoundReport auditability, stationary-point N_B). Full rulings S1–S14 in
docs/design/m12-synthesis.md.

## Gotchas / process notes

- The scouting quarry report (v0.1-deprecated) is a payload of test-design
  lessons now encoded as requirements: marginal tests are structurally blind
  (GQSP ordering bug passed |P|² tests "by coincidence"); the H!-vs-Ry(−π/2)
  basis-change sign bug shipped TWICE; interleave remainder truncation
  (max(1,÷)); 13-min statistical tests killed in CI → tier from day one;
  v0.1's QSVT is STILL broken (two open bugs) — do not quarry its code.
- Only ONE agent may run Julia at a time (v0.1 rule, compile-cache clashes)
  — proposers/distillers were banned from Julia; implementer has exclusive
  rights this session.
- Beads: 90jq epic; v3yn+bog7 closed; elsf (phase 1 deterministic core,
  implementer running at session write time) → ze22 (channel harness) →
  8yzf (randomized) → gmx0 (bench/frontier).

## Implementer addendum (elsf, phase 1 — deterministic core SHIPPED)

`src/library/evolve/` (7 files, ~1204 LOC) supersedes the M10 single-file
`evolve.jl`; `test/test_m12_hamsim.jl` (460 LOC, 912 asserts) wired into
runtests. Suite 25750 → **27122 green**. S3/S9 implemented as ruled.

- **R1 CLOSED**: order-2k chain verified against the HW tex
  (`docs/literature/2206.06409_src/main.tex`, thm:trotter_cost proof):
  spectral `(2α/(2k+1))(Υτ)^{2k+1}` (TS_intermediate_2, HW's own
  α-convention note vs Childs Thm 10/eq 189); diamond = EXACTLY 2×
  (diamond_to_spectral_start–TS_intermediate_1); steps rule
  TS_intermediate_3 (the 4 = 2_spectral × 2_diamond). So steps-from-ε ships
  for ALL orders ≤ 12, not just 1–2. Order 1 keeps tight Childs E1; E2
  tight order-2 `min` path still gated on completing the distillation's
  index ranges (S13 follow-on). The ×2 lives in ONE function
  (`_diamond_from_spectral`, bounds.jl) with a named test pinning
  `report.value == 2 × inputs.spectral`.
- **R3 PASSED** (audit in evolve.jl header): `_pauli_exp!` allocates no
  scratch — the CNOT-ladder parity target is a REGISTER wire, so the §3.9
  clean-ancilla seal never sees evolve!-owned ancillas; guardrail 2 fires
  if the evolved register overlaps the control; identity-word `gphase`
  becomes a genuine relative phase (`ctrl(gphase)` is real). T9 compares
  `when(c) evolve!` vs dense block-diag ctrl-expm PHASE-SENSITIVELY (no
  up-to-phase normalization) and pins the |0⟩ branch to exact identity.
- Gotchas: (a) `Matrix .- I` ERRORS in Julia (UniformScaling is not
  broadcastable) — use `-`; this was the one red in the first full run,
  invisible in the T9 repro script because the repro omitted the assert
  lines. (b) Test files are NOT standalone: `approx_upto_phase` etc. come
  from the runtests preamble (choi.jl), so a scratch-env include of
  test_m10_library.jl shows phantom GROVER.CHANNEL errors — harness
  context, not code. (c) Don't pipe Pkg.test through `tail -N` — the one
  errored-test detail scrolled out; capture the full log. (d)
  `alpha_comm_cross` inclusion–exclusion needs a loud negative-cross guard
  (exact in ℝ; fp noise floored at 1e-9·max(1,αH), anything worse errors).
- Deviations from the letter of the synthesis, all argued in-file:
  model families live in hamiltonian.jl (no separate models.jl); no
  auto.jl yet (Auto is a phase-2 stub, S14's slot reserved); sugar
  extension `order=…, ε=…` (no steps) derives steps — M10-accepted calls
  are bit-for-bit unchanged; `_pauli_exp!` keeps an M10-compatible
  `PauliTerm` method alongside the `(PauliWord, θ)` form.
- Phase 2 (8yzf) inherits: QDrift/Composite/Auto planning (stubs error
  naming the bead — tested), S4 exact transcendental N, S7 N_B stationary
  rule, optimal-K, S10 DM+randomized guard (must land WITH randomized
  execution — today the planning stub fires first), trajectory(plan, rng),
  T5–T8/T11 channel harness (ze22), bench frontier (gmx0), E2 tight path.

## Implementer addendum (8yzf + ze22, phases 2+3 — randomized strategies SHIPPED)

`src/library/evolve/` gains `auto.jl` (+~380 LOC across bounds/plans/suzuki/
evolve); `test/test_m12_random.jl` (176 asserts CI + 3 HEAVY) wired into
runtests after test_m12_hamsim. Suite 27122 → **27298 green** (27301 w/
STURM_TEST_HEAVY=1). S4/S7/S8/S10 as ruled; stub tests repurposed.

- **Proposal-A property test was BACKWARDS**: "N_exact ≤ ⌈4λ²t²/ε⌉" is false
  — e^x−1−x > x²/2 strictly, so the S4 exact criterion demands MORE than the
  naive asymptote: ⌈4λ²t²/ε⌉ ≤ N_exact ≈ 4λ²t²/ε + 2λ|t|/3 (verified
  numerically; the correct two-sided sandwich is the named test). The exact
  criterion IS tighter than the honest windowed closed form — the S4 ruling's
  intent survives; only the inequality direction in A §5's test was wrong.
- **HW misquote flag**: HW eq qdrift_diamond_distance restates Campbell's
  HALVED-distance bound as the FULL norm (factor-2 optimistic; Campbell's own
  raw full-norm bound is 4λ²t²/N·e^x, distillation-verified). Sturm's S4
  criterion keeps Campbell's convention honestly ×2. Fact HW's Q-term is used
  VERBATIM for Composite (as ruled) — its qDrift component inherits HW's
  optimistic quote; T11's exact-ensemble conformance passes with big margin,
  but if a future adversarial case grazes the bound, revisit Q → 2Q.
- **R2 CLOSED** (tex): Lemma lem:diamond_dist_higher_order expands the outer
  step as Υ pairs 𝒰_B(t_i)∘𝒰_A(t_i), each 𝒰̃_B an independent qDrift channel
  (fresh draws, per-invocation N_B); each 𝒰̃_A a FULL inner order-2k sweep
  (matched orders, line 490) — hence the Υ(ΥL_A + N_B) cost. NOTE the
  distillation §(b) line "𝒰_A replaced by its L_A-term first-order Trotter
  sweep" contradicts the cost formula (that's the §4 first-order construction
  leaking into the higher-order paragraph); the cost line pins the truth.
- **R3 CLOSED** (tex, same lemma): negative (1−4u_k) outer scales are covered
  by HW's own |1−4u_k| ≤ 1 ⇒ |t_i| ≤ t accounting, and both per-slot bounds
  are even in t_i — |dt| in bounds, sign in angles. Composite NOT restricted
  to outer order 2.
- Gotchas: (a) top-level replay tests must be up-to-phase — the uncontrolled
  Ad path drops U2.φ at application (§4.3, `_emit_u2!`), so gphase/H/S†
  phases are unphysical at top level (T9 already pins ctrl-visibility);
  a phase-sensitive opnorm compare of a seeded qDrift replay fails by O(1).
  (b) `Composite(order = 2, K, N_B, …)` without the leading `;` passes K
  POSITIONALLY — no positional ctor exists, loud MethodError, but easy typo.
  (c) Statistics is NOT in test extras — hand-roll mean/stderr/quantile.
- Design decisions argued in-file: K = 0 degeneration with BOTH N_B+steps
  pinned maps to QDrift N = steps·Υ·N_B (exp_count-preserving); partial pins
  across a degeneration throw; K = L + pinned N_B throws. TracingContext is
  guarded alongside DM (one traced trajectory = the S10 bug class at the DAG
  level) — an extension beyond the letter of S10, same physics. Auto's
  composite candidate uses the second-moment K* seed only (norm1, no
  refinement); the chosen strategy's planner re-derives K with exact-α
  refinement (S8's division of labor).
- Leftovers for gmx0 (bench): R4 calibration (ALPHA_MAXWORDS_DEFAULT,
  AUTO_COMMUTING_GATE = 2048), frontier protocol vs the Zlokapa envelope +
  QSP overlay, Auto-regret table, proxy-K vs exact-K disagreement rate.
  E2 tight order-2 min path still gated on the distillation (S13 follow-on).
