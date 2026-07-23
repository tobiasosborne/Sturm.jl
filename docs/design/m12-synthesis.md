# M12 Synthesis — Orchestrator Review of Proposals A & B (bead Sturm.jl-bog7)

Reviewer: orchestrating agent, 2026-07-23. Inputs: `m12-proposal-A.md`
(physics-first), `m12-proposal-B.md` (host-language-first), both against
`m12-hamsim-proposer-prompt.md`. Verdict: **synthesis** — B's skeleton,
A's exactness machinery. Neither proposal is discarded; every ruling below
names its source.

## Convergent core (both proposers independently; SETTLED)

1. Pure classical planning layer; the quantum executor is a dumb fold of
   `_pauli_exp!` over `(term, θ)` pairs. All interleaving arithmetic and
   sampling is unit-testable with no context; exponential counts are exact
   properties of plan data; the bench counter never touches the hot path.
2. `PauliWord{W}` symplectic (x,z) bitmasks + canonical `PauliSum{W}`
   (merged, zero-dropped, |a|-descending, identity split into an exact
   gphase, W ≤ 64 loud). `PauliTerm` strings stay the input spelling;
   endianness pinned in ONE place with a round-trip test.
3. α_comm computed EXACTLY by measure-propagation over product words
   (nested Pauli commutator norm ∈ {0, 2^{2p}}); loud blowup guard; the
   loose 1-norm bound only via explicit caller opt-in. No silent
   substitution path exists.
4. Suzuki 2p by the closed-form u_p recursion; Υ = 2·5^{p−1}; palindrome +
   Σ=1 invariants asserted; order pinned by 2^{2p} scaling-signature tests.
5. Composite = the SAME recursion applied at the outer level to [A, B]
   (HW Def 5.1); fresh tail samples per B-slot; exact slot/count algebra
   (no `÷`, no remainder class); K = 0 / K = L normalize to pure
   QDrift/Trotter plans before scheduling (one code path).
6. K default from the ZAH optimal-K second-moment rule on precomputed
   suffix tables, then local refinement on the true cost.
7. Verification: exact enumerated ensemble superoperators (Choi-trace-norm
   consequence of the cited diamond bound + N/r scaling signatures),
   seeded trajectory replay vs dense products, deterministic full-operator
   tests as the default tier, HEAVY env-gated statistics, all bounds
   untuned.
8. bench/ with its own environment; cost = `exp_count(plan)`; frontier
   protocol vs the Zlokapa envelope with analytic QSP overlay; model
   families = coefficient tails × word ensembles.
9. Strategies exported; plans/machinery `public`; no new core deps.

## Rulings on divergences

| # | Question | Ruling | Rationale |
|---|----------|--------|-----------|
| S1 | Schedule representation | **B**: immutable plans + lazy `trajectory(plan[, rng])` iterator; one-step sweep shared across steps | Memory never scales with r·L (A materializes the full vector); equally testable via `collect` |
| S2 | Where ε lives | **B**: `ε` is an `evolve!` kwarg (call property); strategies carry resources only | `Trotter(order=4)` reusable across accuracies; one spelling per meaning |
| S3 | Bare `evolve!(x,H,t)` | **B**: errors, demanding `ε=` or explicit resources — pending Tobias sign-off (deviates from the approved sketch, where the bare call ran Auto at a default ε) | A default ε=1e-3 is a silent-fallback of exactly the banned class; A's own proposer flagged it (O1) |
| S4 | qDrift N rule | **A**: exact transcendental criterion 2N(e^{2λt/N}−1−2λt/N) ≤ ε by bisection | Strictly tighter than the asymptote; kills B's validity-window special case entirely |
| S5 | ε norm convention | **A** (D-A3): ε = FULL diamond norm everywhere; the spectral→diamond factor 2 lives in one function | The silent factor-of-2 class dies in one place |
| S6 | Bound auditability | **A**: `BoundReport` (value, formula symbol, citation, inputs); plans carry them | Conformance tests assert against reports; formula drift breaks a named test |
| S7 | N_B default | **A**: stationary point N_B* = √(Υ·L_A·R_Q/R_P) + integer scan on the true ⌈·⌉ cost | Exact and cheap; ZAH's N_B = K is the documented asymptotic special case |
| S8 | Auto output | **A**: `evolve_plan` returns the full candidate table with skipped-rows-with-reason; **B**: exactness fast paths (single term / commuting ⇒ order-1 exact, α≡0) and O(L log L) surrogate-only dispatch | Merge both: fast paths first, surrogate costs for dispatch, exact α for the chosen strategy's planning, table always visible |
| S9 | ctrl-`evolve!` | **B**: deterministic strategies switch `_pauli_exp!` to `_act!` now (T9: vs dense ctrl(expm)); randomized assert empty control stack | Cheap, unblocks QPE-on-e^{−iHt}; guarded by research step R3 (fall back to A's defer-all if the §3.9 audit fails) |
| S10 | DM + randomized | **B**: `error()` naming M11 | One trajectory under DM silently misrepresents the CPTP average — the exact bug class Principle 1 kills |
| S11 | Order cap | **B**: loud cap at order 12 (Υ = 6250) | Beyond it Suzuki coefficients are numerically useless; the error message says so and names the cap |
| S12 | Duplicate-word merging | **B**'s note adopted; equality e^{−iaP}e^{−ibP} = e^{−i(a+b)P} documented | Exact; changelog note for the observable-ordering change (canonical vs user order — both proposers) |
| S13 | Trotter order 1/2 bounds | **A**'s registry: keep E1 (+E2 pending R1) tight paths, generic 2k formula otherwise, `min` once distillation completes | Continuity with M10 tests |
| S14 | File layout | Merge: `pauli.jl`, `hamiltonian.jl`, `suzuki.jl`, `bounds.jl` (α_comm + steps/N rules + BoundReport + the factor-2 pin), `strategies.jl`, `plans.jl` (plan_evolution, trajectory, exp_count), `auto.jl`, `evolve.jl` (executor + entry) under `src/library/evolve/` | Names follow B's plan vocabulary; A's bounds consolidation |

## Research steps carried into implementation (union of A + B)

- R1 (both): transcribe/verify the order-2p pure-Trotter step prefactor
  (HW main.tex 536–539 ↔ Childs 2021 Thm 10/Eq. 189) incl. the
  diamond-vs-spectral factor-2 audit; complete E2 index ranges in
  childs_2019_trotter_error.md before wiring the order-2 `min` path.
- R2 (A): confirm from HW's algorithm listing that N_B is per B-invocation
  and B-slots draw fresh samples. (The Phase-0 distillation's recipe §
  already states both; re-verify against the listing during implementation.)
- R3 (A+B): negative-dt B-slots for outer p ≥ 2 (|dt| accounting), and the
  `_pauli_exp!`-under-live-frame §3.9 audit before T9 lands.
- R4 (A+B): calibrate ALPHA_BUDGET / maxwords and the Auto commuting-gate
  constant on the bench families; both stay loud caps.
- R6 (A): sweep test_prd_examples.jl and fixtures for bare `evolve!` calls
  before the S3 rule lands.

## Resolved by Tobias (2026-07-23, after review)

- **S3**: RULED — bare `evolve!(x,H,t)` throws `ArgumentError` demanding
  `ε=` or explicit resources; `evolve!(x,H,t; ε=…)` runs Auto. No default
  accuracy anywhere.
- **S9**: RULED — deterministic ctrl-`evolve!` IS in M12 scope (`_act!`
  switch + T9), guarded by research step R3; fall back to deferral if the
  §3.9 audit fails.
