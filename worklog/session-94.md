# Session 94 — 2026-07-10 — Review r6 executed + greenfield implementation plan

Tobias accepted all round-6 findings ("implement all your findings they
are all good") and asked for a detailed greenfield implementation plan.
North star recorded: best-in-class Julia-idiomatic quantum language,
all physics respected, beautiful ergonomics; deprecated branch = full
of heresies, consult sparingly and skeptically.

## What shipped

1. **`Sturm-PRD-v2.md` revised in place** (1018 → ~1600 lines), all r6
   findings folded (beads `la0y` + `8fte`, both CLOSED):
   - Header records round 6; §1.1 Gavorová mechanism fixed (Lemma 1,
     winding argument — Borsuk–Ulam demoted to even-d intuition).
   - §3.3 rebuilt: semantics table split Draper row into `add!(x, a)`
     (translation; Draper = kernel lowering) + `x̂ += a` (modulation —
     honest `+=` on the dual register); D11 spelling rule (bind the
     view; the two parser traps named); B2 correction REGISTERED in
     the text ("addition is addition — Draper is how the kernel does
     it"); Pontryagin ¶ now states the translation↔modulation SWAP +
     the two sign-pin unit tests; "registers are numbers; views are
     addressing modes" (views don't ride P9); wrapper-identity /
     mightalias-shaped-hook note; Qwerty ¶ reworded (no "considered
     and rejected"; ASDF cited; canonicity-buys-the-view).
   - §3.4 = "The action family" (D12): two-world registry table;
     quantum-addend corrected (ŷ += x = controlled modulation;
     add!(y,x) = addition); xor registration hardened with
     julialang#249/#3217 as informed deviation; generic-f caveat
     mechanism fixed; P9 scoped (bitwise → oracle); MBU-under-ctrl
     exclusion normative; oracle returns opaque query, x stays live.
   - §3.5 + D13: streaming ctrl licensed by the homomorphism law;
     per-context guardrail enforcement; clean-ancilla lemma;
     classical-side-effects + anti-control-sandwich footnotes.
   - §3.6 + D3 RESOLVED: ClassicalBit/ClassicalInt tokens (Jasp-shaped,
     Proto-Quipper parameter/state); measure→traced-classical→
     parameterized-circuit blessed; no 2^W cases tables.
   - §3.7: T-gadget-correction-is-non-Pauli caveat.
   - §3.8: seven-construct table updated (action family; bound-view
     actions; D-refs); context-portability matrix (one sensitive row);
     DM-executes-channels normative ¶ (one-run Choi harness + the two
     probe rules).
   - §3.9: CV vacuum fix; "Why not Silq auto-uncompute?" defense +
     end-of-scope landscape table (owning the inversion); regions on
     Base.ScopedValues; `region() do end` (D10); trace-timing
     invisibility meta-note + seeded-RNG rule; strict mode =
     lost-binding detector.
   - §4.1: U2 double-cover equality normative (H² = (−1,π); +I ≠ −I;
     Ry(2π) = −I is physics); survey-scoped IR-novelty + Wharton–Koch;
     ctrl(Perm) is a Perm.
   - §4.2: ∘ right-to-left convention; Control-as-a-Constructor
     2508.21756 cited (Sturm = implementation instantiation); Qiskit
     #4949 + pytket <0.17 corrections; combinator named `within(V)`;
     view-fusion pass specified.
   - §6 P9 scoped; §7 gains 7.1 convention-pin note, **7.1b deferred
     teleport**, 7.2/7.3 rewritten, 7.4 robustness note, **7.5 BV**,
     **7.6 injection ladder (cases + literals + non-Pauli correction)**,
     **7.7 shor_order capstone**; §8 reframed as the defect ledger →
     named v2 regression tests; §9: D1 string-macro future note, D2
     additions (partial-consumption error; view identity), D3/D8/D10
     RESOLVED, D11/D12/D13 RESOLVED entries, **D14 filed (BennettVM
     contract — needs Tobias)**; citations TODO corrected (CSW
     inversion fixed + 8 new sources); §10 updated.
2. **CLAUDE.md updated:** rule 11 table + text (D11/D12/D13 spellings;
   two-world registry; inverse slogan); Phase Discipline gains the
   translation↔modulation swap law, U2 double-cover equality gotcha
   (NEVER assert Ry(2π)==I), MBU-under-ctrl ban; convention 2 extended
   (registered exceptions incl. bound-view ops, #249 acknowledgment);
   convention 6 → ScopedValues + region() + hot-path note; NEW
   conventions 8 (namespace = layering via `public`) and 9 (PRD
   examples compile forever).
3. **Doctest lint executed on the revised PRD:** 11/11 fenced blocks
   parse AND lower clean (stub @cases/@context macros; lowering-stage
   checking is what catches B1-class rot). Prototype = the shape of
   test/test_prd_examples.jl (hn90).
4. **`Sturm-v2-IMPLEMENTATION-PLAN.md`** (new, root): north star,
   9 ground rules (incl. quarry policy with the heresy list),
   milestone graph M0→M11 + horizon, per-milestone files/named
   tests/distillations/3+1 flags/quarry notes/exit criteria,
   cross-cutting workstreams (Choi harness, numerics, error policy,
   namespace, perf), risk register (Bennett audit, Orkan ABI, D6, D14).
5. **Bead graph wired:** new milestone beads `puig`(M1b) → `dc6i`(M2)
   → `77m2`(M3) → `3nld`(M4) → `o5yh`(M5) → `80g6`(M6) → `jv50`(M7pre)
   → `7a0v`(M7) → `szx1`(M8) → `8oo9`(M9) → `8fo5`(M10) → `qmpo`(M11),
   chained onto existing `23o1` → `c52g`; c52g updated with the r6
   equality spec; 23o1 updated with the PRD-lint deliverable; `la0y` +
   `8fte` closed as executed. (bd dep add worked — the yl52
   missing-table issue did not bite this session.)

## Gotchas for future agents

- The PRD deliberately still *mentions* `dual(x) += a`/`dual(q) ⊻= r`
  in four places — all as "this is not writable Julia" explanations.
  Do not "fix" those mentions into live code, and do not delete them:
  they are the registered correction trail.
- The PRD doctest lint MUST lower, not just parse (B1 was a lowering
  error), and needs stub @cases/@context macros that pass their
  arguments through so branch bodies get checked.
- Next session: milestone 0 (`23o1` + `hn90`) is ready — everything it
  needs is specified; after that, `c52g` requires the 3+1 round.
