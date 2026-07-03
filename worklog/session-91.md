# Session 91 — 2026-07-03 — v2 language redesign: ground-up re-evaluation → Sturm-PRD-v2.md

**Bead:** `Sturm.jl-u9o6` (P1, feature). **Output:** `Sturm-PRD-v2.md` (DRAFT for argument).

## What happened

Full ground-up design re-evaluation of the language, requested by Tobias.
Five Sonnet research agents (Bennett.jl retrospective, BennettVM.jl
retrospective, Sturm surface-friction audit, quantum-PL landscape survey,
theory sweep) + first-hand reading of `qbool.jl`/`when.jl` + several rounds
of argument. Result: the v0.1 axioms survive; the primitive layer does not.

## Load-bearing findings (all verified, citations in PRD §1)

1. **P1/P4 formal tension**: quantum alternation has no channel-level
   semantics (Bădescu–Panangaden 1511.01567); controlled-U needs a
   phase-fixed representative (Gavorová et al. 2011.10031). v0.1's `when`
   silently fixes an SU(2) section — root cause of `_cz!`/`3yz` bug family.
2. **Soundness holes** (fix on main regardless of v2, PRD §8):
   `Bool(q)` inside `when()` = silent unconditional global collapse; bare
   `q.θ` = silent no-op; `qbool.jl:154` mixed xor applies Ry(π) as "X"
   (−iY, wrong under control); aliasing caught only by Orkan C asserts;
   consumed-flag/context-set desync; QSVT `Vector{QBool}` API.
3. **θ/φ primitives**: five defects (PRD §1.2) — θ-notation false off the
   φ=0 meridian, `+=` fakes commutativity, write-only property
   anti-idiomatic, su(2)-specific (P7 fails at QMod today), det=1
   obstruction generates the exception zoo.

## Design arc (for future agents — the rejected branches matter)

- **Rejected: generators as primitives** ("evolve under G", Stone's
  theorem as API). Tobias's philosophy: Nature gives processes, not
  Hamiltonians; generators are derived, and don't exist for discrete
  symmetries (Bennett permutations, braids). Process-first is strictly
  more general. `evolve!` stays as *library*.
- **Rejected: process values as surface** (`ctrl(X)(a,b)` style) — gate
  ontology through the front door. Process values are the *kernel/IR*.
- **Accepted: three layers** — surface = normal programming (casts, `⊻=`,
  `dual` conjugate views, `when`); kernel = process values (U(2) as
  quaternion+phase, `Perm` Bennett artifacts, `UnitaryDAG`) with
  `∘/⊗/adjoint/ctrl` and Ad-application (phase quotient crossed exactly
  once, at application, by ker(Ad)=U(1)); library = physicist
  conveniences.
- **Key new surface concept: `dual(q)`** — lazy involutive conjugate-basis
  view (Julia `transpose` idiom). `Bool(dual(q))` = X-basis readout;
  `not!(dual(q))` = Z; `dual(q) ⊻= r` = CZ (symmetric, visibly);
  `dual(x::QInt) += a` = Draper adder; generalizes to Weyl–Heisenberg
  (QMod) and x↔p (CV). Complementarity replaces Bloch coordinates.
- **Casts confirmed consuming** (Tobias's "Bool→Bool type lie" argument
  killed the non-consuming variant). Boundary algebra: qc∘cq = id,
  cq∘qc = pinching channel.
- **Teleportation in v2 surface** (PRD §7.1) — no gates, no rotations;
  no-cloning visible as handle consumption; denotes id channel (the test).

## Gotchas / process notes

- Tobias: **Julia idiomaticity is paramount** (new standing preference);
  skeptical of the QPL landscape — first-principles arguments only;
  v0.1 was "vibecoded with Opus 4.6, who was pretty reckless".
- MBQC universality claim for the surface (PRD §3.7) carries an explicit
  proof obligation; D1–D8 open decision points listed in PRD §9.
- New-citation distillations (4 theory papers + MBQC source) required in
  `docs/physics/` before any v2 implementation (rule 4) — tracked in PRD §9.

## Handoff

Next session: argue PRD §9 decision points with Tobias (D1 literals, D3
dynamic lifting, D8 migration are the hot ones); independently, the §8
soundness fixes on v0.1 are shovel-ready and shouldn't wait for v2.
