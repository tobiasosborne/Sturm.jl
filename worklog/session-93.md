# Session 93 — 2026-07-10 — PRD-v2 review round 6: full consequence audit

**Output:** `Sturm-PRD-v2-review-r6.md` (root, next to the PRD). Method:
main-thread consequence analysis + 4 subagents (citations / prior-art /
physics / Julia-idiom, Opus×3 + Sonnet×1, per Tobias's no-Fable-subagents
instruction) + **parser ground truth on Julia 1.12.5** (every PRD surface
form fed to `Meta.parse`/`Meta.lower`).

## The three blocking findings

1. **B1 — `dual(x) += a` and `dual(q) ⊻= r` are not valid Julia.**
   "invalid assignment location" — op-assign needs an assignable LHS
   (variable/field/index); a call is none, no `setcall!` hook exists,
   and the restriction is a 15-year defended invariant
   (julialang#227/#249/#3217, enforced at 9 sites in julia-syntax.scm).
   §7.2, §7.3, two §3.3 table rows, §3.4, §3.7, D5 bullet, CLAUDE.md
   118–119 all affected. Survived FIVE refinement rounds (incl. the
   Julia-idiom round!) because examples lived in prose. Bonus trap
   (verified live): `dual(x) = y` in a function body is a LOCAL METHOD
   DEFINITION that shadows `dual` for the whole body, breaking even
   earlier lines. Recommended spelling: bind-the-view
   (`x̂ = dual(x); x̂ ⊻= r`), runner-up `q[dual]` selector; new D11.
2. **B2 — the Draper row is semantically backwards.** Under the PRD's
   own lowering rule (ops through a view conjugate by F), translating
   the dual coordinate is a MODULATION on x (F†T_aF = M_∓a — the
   intertwining theorem), not addition. `Int(x)` would be unchanged.
   The QBool rows already obey "view swaps translation↔modulation"
   (not! ↦ X, not!∘dual ↦ Z); the Draper row was reverse-engineered
   from the v0.1 name `add_qft!` instead of derived. Fix strengthens
   the design: addition's spelling is `add!(x, a)`/`x + a` (Draper =
   kernel lowering choice); `x̂ += a` gets its true meaning (phase
   program); construct #3 generalizes to the G-translation/Ĝ-modulation
   torsor family — one P7 theorem. Pontryagin unit test:
   `superpose!(x); x̂ += a; Int(dual(x)) == a`.
3. **B3 — the arithmetic surface rests on an unmade decision.** Julia
   forces `x += a` ≡ `x = x + a`; fresh-output `+` (P9-required) makes
   `x += a` a rebind whose old register is silently traced ⇒ the sum
   decoheres — the §3.4 caveat hiding under the most innocent line in
   programming; mutate-first `+` breaks generic P9 code outright.
   Resolution: two-world registry (value world = ring ops fresh-output;
   action world = registered translation family + views), P9 generic
   path scoped to arithmetic/comparison (drop "bitwise" — action-world
   ⊻ has no value semantics; steer through oracle), D10 strict mode =
   garbage-decoheres-survivor detector (one mechanism catches the +=
   trap, the XOR-fold trap, and lost bindings). Also found: §3.4's
   caveat paragraph contradicts its own registration two ¶s up
   (describes value-world xor after registering action-world xor).

## Major findings (M1–M8, detail in the review doc)

when-streaming licensed by the ctrl homomorphism law + per-context
guardrail enforcement (M1); U2 equality is double-cover equality — H²
lands on (−1_quat, π), so "H∘H == identity" FAILS naive 5-float
equality; quotient must keep +I ≠ −I (Ry(2π) = −I is physics) (M2);
teleport's `&&` corrections are Eager-only + no §7 example uses cases
(M3); Bennett MBU cannot go under `when` — strategy selection must be
control-aware, and §1.1's own no-go explains why (M4); DM context
should execute channels not trajectories ⇒ exact one-run Choi tests
(M5); §8 stale post-reboot — retitle defect ledger → named v2
regression tests (M6); BV is the missing per-wire-dual example (QFT
basis does NOT recover s — verified numerically, N=3 s=5 spread
{1:.073, 3:.427, 5:.427, 7:.073}) + partial-consumption rule for
slices (M7); migrate @context from task_local_storage to
Base.ScopedValues — TLS does NOT inherit into @spawn/@async (verified
live), ScopedValues does, and 1.12 NEWS migrates Base itself (M8).

## Agent-verified results

- **Physics agent (independent re-derivation + numpy):** every
  derivation-level PRD claim CORRECT — teleport denotes id (Choi
  verified; X-labeling forced |+⟩↦false, reversal = Z-error channel
  invisible to Z-marginals = wm28 class), DJ-in-QFT-basis works
  (uniform row coincidence), universality chain holds (T-gadget
  correction S is non-Pauli — needs live feedback), reassociation law,
  boundary algebra Chois, no-backaction, streaming clean-ancilla,
  F†D_aF = T_{+a} sign conventions, deferred teleport, D6 traps.
- **Citation agent:** 12/13 hold as-used (QCM thm numbers, YYF,
  Tang–Wright, VOQC quote, RBB-vs-ZLC all verbatim-confirmed). ONE
  INVERTED: Chen–Stoudenmire–White 2210.08468 is titled "QFT Has
  SMALL Entanglement" — cited for "maximal operator entanglement",
  the claim the paper debunks (bit-reversal artifact). D2 conclusion
  unaffected. Gavorová mechanism = homogeneous-function Lemma 1
  (winding argument), Borsuk–Ulam only even-d intuition. pytket bound
  is <0.17 not ≤0.17; Qiskit #4949 is the cleaner controlled exhibit.
- **Prior-art agent:** Qwerty "authors considered and rejected the
  view reading" is UNSUPPORTED — reword (their `>>` maps arbitrary
  bases, which is why it must synthesize; dual's canonicity is what
  enables the view). §4.2 must cite "Control as a Constructor"
  (arXiv:2508.21756) — categorical prior art. §3.9 needs a "why not
  Silq auto-uncompute" defense (+ cite Qurts 2411.10835). Q#
  "convention-only" outdated (current QDK runtime-enforces clean
  release). Scope-discipline survey: silent-trace-as-P1-denotation is
  novel AND contrarian (all linear-typed languages run the opposite
  discipline). Consuming-cast-spelling novelty confirmed (OpenQASM 3
  = near-miss). Quaternion-IR claim survives (scope the survey, cite
  Wharton–Koch). D3 DE-RISKED: qrisp/Jasp ships exactly the
  ClassicalBit-token design incl. the 2^W answer (traced classical
  computation, no branch table).
- **Julia-idiom agent:** #249/#3217 quotes (Karpinski/Bezanson) are
  verbatim the generic-code trap B3 analyzes — cite as informed
  deviation in §3.4's registration. dataids/mightalias NOT public API
  (D2's "-style" phrasing correct). D10 naming: `region() do end`
  ("scope" now doubly claimed by Julia). 1.11/1.12: `public` keyword
  = mechanical namespace enforcement of the three-layer table.

## Rulings now possible

D3 (Jasp-shaped tokens + bless measure→classical→parameterized
circuit), D10 (region(); trace timing denotationally invisible ⇒
eager-helper inheritance provably harmless), new D11 (view-mutation
spelling), D12 (arithmetic registry), D13 (when operational
semantics).

## Meta-lesson (process, rule 10 vindicated)

Five review rounds missed a parse error because normative code lived
in prose. **PRD examples must compile: test/test_prd_examples.jl
Meta.parses every normative fenced block; §7 runs under Eager once
milestone 0 lands.** The constitution gets CI too.

## Gotchas for future agents

- NEVER assert `Ry(2π) == identity` in U2 law tests — it equals −I
  and that's physics (ctrl(−I) = CZ-grade); "fixing" it reintroduces
  the SU(2)-section disease at the equality predicate.
- The §7.4 DJ pattern (`Int(dual(x)) == 0`) must not be copy-pasted
  for BV — different dual groups; BV needs `Bool(dual(x[i]))`.
- TLS does not inherit into spawned tasks; ScopedValues does
  (verified 1.12.5) — don't build @context v2 on TLS.
- Teleport channel tests must probe |i⟩ or |+⟩; Z-basis probes are
  blind to the X-labeling bug class (and to wm28).
