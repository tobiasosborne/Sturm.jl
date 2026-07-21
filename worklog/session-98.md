# Session 98 — 2026-07-21 — Orchestrated: M8 design gates 3+1 + Tobias rulings (F13 = D)

## HANDOFF — state at session close

**Where we are:** Fully-orchestrated session (subagents: 2× codex
gpt-5.6-sol xhigh proposers, 4× Opus, 1× Sonnet). Both M8 P0 design
gates CLOSED with 3+1 syntheses committed; plan rebaselined; and — the
session's centerpiece — a live design dialogue with Tobias produced the
**F13 RULING: Option D** plus wholesale adoption of every other standing
recommendation. M8 (`szx1`) is no longer decision-blocked: it now gates
on two WORK beads — `w5rw` (PRD+CLAUDE.md wording round under Ruling D)
and `vanm` (F16 `QBool{C}` refactor, core types, 3+1).

**Shipped this session (chronological):**
- **Tracker repaired** via `bd import .beads/issues.jsonl` (local Dolt DB
  had again lost session-97 state). After the import **`bd dep add`
  WORKS again** — M8's gates are real dependencies now, not notes.
- **Stale sweep:** `u9o6` closed (PRD draft long since delivered);
  pre-reboot stragglers `7kg`/`bkv` labeled `v0.1-quarry` + deferred
  (subsumed by 5hr7/szx1 and i4ri respectively).
- **`rlhj` CLOSED** (93f36fd): 9-finding PRD accuracy patch (U(d) QMod,
  ≈7-wire Choi cap, structural `==`/semantic `same_process` split, D15
  filed, guardrail-1 qc-cast wording, F10/F11/F14/F27/F36). Lint 13/13.
- **`i4ri` CLOSED** (85b11d0): classical-control IR 3+1. Blind proposers
  CONVERGED (restricted classical SSA over staged lifting; copyable
  tokens + correlation record over affine; DM token+cases; both
  recommended a measure verb — later overruled by Tobias, see below).
  Orchestrator review caught **L5 defect**: X^m⊗Z^m on |00⟩ does NOT
  give ½(|00⟩⟨00|+|11⟩⟨11|) — Z fixes |0⟩; population form needs X on
  both, Z-record correlation is coherent-probe-only (wm28 discipline).
- **`5hr7` CLOSED** (776c92a): UnitaryBlock 3+1. Both proposers
  independently **overrode the review's own {InPorts,OutPorts}** toward
  a square endomorphism block. Synthesis: B's proof-term constructor set
  as the concrete form of A's (I−ιι†)Wι=0 invariant + A's
  AdjointCert/XportCert + resource lineage; two-tier phase contract;
  19-test battery incl. the gphase(π/3) sentinel.
- **`rzkx` CLOSED** (376f5f0): plan rebaselined (F31/F34/F35). §7
  contract table (4 re-derived / 1 measured-verbatim / 1 gated-on-M11);
  **caught one real silent import: v0.1's Choi-only pass-certification
  is phase-blind — barred**. §3.0 decision schedule; risk register
  refreshed (ruling latency was the critical path — now discharged).
- **Rulings brief** (docs/design/m8-rulings-brief.md) written for Tobias.
- **Design dialogue with Tobias** (recorded as i4ri doc §§12–14):
  - §12: PVM branch P_bρP_b (CP-TNI, subnormalized) **factors through
    the record** as instrument + classical effect ⟨b| — no contradiction;
    three-meanings rule (sample/record/assert must be distinct ops);
    effects = explicit `postselect(record,v)` surface, TP-record stays
    DM default; L22–L24. Bead `eyho`.
  - §13: **context trichotomy** (Tobias): Eager = runtime semantics
    (MCM hardware, prototyping); DM = physical denotation (record IS
    deferred measurement as types); Tracing = the compiler. Traceable-
    subset argument: under split vocabulary the compiler-food boundary
    is lexical; under one spelling it is use-site-dependent.
  - §14: **RULINGS.** F13 = **OPTION D** — `Bool(q)`/`Int(x)` single
    spelling everywhere, returning the classical system as the context
    represents it (value/record/wire); registered exception to the
    constructor convention. D15 = certified-block option (b). TR1–TR8
    all as recommended. `postselect` spelling. F15/F19 as recommended;
    F16 scheduled pre-M8. ne0d approved. Consequential re-spellings of
    the Option-A-form design text are listed in §14 (portable idiom
    `cases(Bool(q))`/`@cases Bool(m)`; L3 no-throw; tracer pre-flight
    lint mandated since the boundary can't be lexical).

**Bead state:** closed this session: u9o6, rlhj, i4ri, 5hr7, rzkx, vqas,
xy4w, z1sa. Created: vqas/xy4w/z1sa (ruled+closed same session), ne0d
(approved, closes with w5rw), eyho (P2 feature), **vanm** (F16 refactor,
P1, 3+1, pre-M8), **w5rw** (wording round, P1). Deferred: 7kg, bkv
(v0.1-quarry). `szx1` now depends on: vanm, w5rw (+ closed gates).

**Next step (in order):**
1. **`w5rw`** — single implementer + orchestrator review: apply ALL
   staged wording under Ruling D (7 items listed in the bead: i4ri §7
   re-spelled to D, 5hr7 §7 with TRs, trichotomy preamble, D15(b),
   postselect ¶ + P1 CP-TNI widening, ne0d intro table, CLAUDE.md
   registered-exception entry). Doctest lint must stay green; NO
   measure verb may appear anywhere.
2. **`vanm`** — F16 `QBool{C}`/`QInt{W,C}` (core types ⇒ 3+1 round).
3. Then `szx1` M8 implementation per plan §3.M8 + the two design docs.
4. `fy8l` is governed by TR6 (ruled) — unblocked after w5rw.

## Gotchas / learnings

- **⚠ CROSS-REPO DISPATCH RULE (new, from a real collision):** `id8p`
  (run Bennett.jl full suite) was dispatched as idle-capacity work while
  **another agent was actively developing Bennett.jl** — Tobias caught
  it; both julia procs killed cleanly (`Pkg.test` parent + child; ~226
  CPU-min lost, no source damage — Pkg.test doesn't write the tree).
  Rule: before dispatching any job that touches a sibling repo, check
  quiescence (`git -C ../X status`, ask Tobias). id8p is back to OPEN
  with an abort note; rerun only when Bennett is quiescent.
- **Tracker degraded AGAIN at session start** (session-97 gotcha
  repeated): `bd show` missing recent beads until
  `bd import .beads/issues.jsonl`. The git jsonl is the canonical
  recovery source. **After import, `bd dep add` works** (the
  wisp_dependencies failure was the un-imported schema state).
  `bd dolt push` still untested against the remote-conflict gotcha —
  attempted at close, see below.
- **codex exec pattern for blind proposers works well:**
  `codex exec -m gpt-5.6-sol -c model_reasoning_effort="xhigh"
  -s read-only -o <out.md> - < prompt.md`, run_in_background, ~25–35 min
  each; `-o` captures the final message as the proposal doc verbatim.
- **3+1 convergence signal:** on BOTH gates the blind proposers agreed
  on every major axis, and on 5hr7 both independently overrode the
  reviewer's own suggestion (square block) — strong evidence the designs
  are attractor states, not prompt echoes.
- **Review catches this session** (each a real defect): L5 population/
  phase form conflation (orchestrator); B's under-specified endomorphism
  width check (5hr7 synthesizer); B's TypeError message overclaim (i4ri
  synthesizer, re-verified unqualified type name on 1.12.5); v0.1
  Choi-only pass criterion (rzkx implementer).
- **Physics from the Tobias dialogue worth remembering:** postselection
  = record + classical effect (CP-TNI factors through TP); "the cast's
  output type is Bool in every context — what varies is whether you get
  the system or a sample"; a point state IS its value (why Eager's raw
  `Bool` return is faithful under Ruling D).
