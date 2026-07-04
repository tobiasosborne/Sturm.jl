# Session 92 — 2026-07-04 — PRD-v2 refinement round 2: evidence-backed revision

## Round 4 — THE REBOOT (same session, Tobias's call)

**v0.1 is deprecated wholesale. Main begins at zero.**

- Branch `v0.1-deprecated` created at `f44edb7` (the PRD rounds-2+3
  commit) and pushed — the complete v0.1 tree, full history, lives there.
- Main gutted: 323 files removed (`src/`, `test/`, `docs/`, `examples/`,
  `benchmarks/`, `bin/`, `probe_*.jl`, `Project.toml`, `KNOWN_ISSUES.md`).
  This is a normal deletion commit, NOT a history rewrite — nothing is
  lost, `git log` on main still reaches all of v0.1.
- Kept on main (judgment call, flagged to Tobias): both PRDs, CLAUDE.md
  (rewritten), README (stub), LICENSE, .gitignore, AGENTS.md, `.beads/`
  (tracker infra), WORKLOG.md + worklog/ + WORKLOG-archive.md
  (institutional memory, rule 0).
- CLAUDE.md rewritten for the v2 era: reboot status + reimport policy
  ("the deprecated branch is a quarry, not a library"); rule 11 now the
  seven-construct v2 table (PRD-v2 §3.8); v0.1's "H!² = −I is a feature"
  doctrine REMOVED and replaced by the v2 Phase Discipline (U(2) kernel,
  Ad quotient crossed once, ctrl choke point, views-unwrap law); rule 1
  gains the §3.9 no-backaction exception; rule 3/12 cite the wm28
  teleportation lesson (channel-level tests, not marginals); target file
  structure with build order (kernel/ first, law tests first).
- Reimport policy (normative, in CLAUDE.md): v0.1 code returns only
  re-expressed against v2 surface/kernel + 3+1 gates + rewritten tests +
  physics distillations. Never bulk-copy.

**Gotcha for future agents:** wm28 (teleport bug) file paths now resolve
only on `v0.1-deprecated`. When quarrying, `git show v0.1-deprecated:path`
beats checking the branch out.

## Round 3 (same session, after argument with Tobias)

Two design discussions, both folded into the PRD:

1. **`dual` de-magicked (§3.3 rewritten).** Tobias: dual must not be a
   magic keyword — it's a regular channel, Ad of *some* unitary; QFT is a
   basis choice. Resolution: kernel gets a parametric view `view(V, q)`
   (lazy wrapper; ops lower by conjugation — works for instruments and
   `when` too); `dual` = ordinary function `view(F_G, q)` with F_G
   supplied by the register type. Its surface privilege is a P5 fact,
   not a mechanism: it's the unique view constructor taking no
   process-value argument (the type's declared arithmetic fixes F_G).
   Defended against "arbitrary": given the type's group, Ĝ is canonical
   (Pontryagin); residual freedom is discrete two's-complement-style
   convention. Side effect: kills the QSVT/SELECT Y-basis carve-out
   (library uses view(V_y, q)). NEW NORMATIVE LAW — **views unwrap,
   processes compose**: F² = parity as a process (dual-as-apply-F would
   negate integers under double dual!); dual(dual(x)) === x by the
   canonical double-dual identification = transpose idiom. An impl that
   lowers dual by applying F is WRONG; signature of the bug is integer
   negation.
2. **Scope discipline (new §3.9).** Tobias: out-of-scope ⇒ auto-ptrace;
   into-scope ⇒ initialized, canonically |0⟩⟨0|. Assessment: P1-FORCED,
   not convenience — locals are the Stinespring environment; function
   scope is the dilation boundary. IMPORTANT PHYSICS CORRECTION from
   Tobias (I had it wrong in discussion): forgotten uncompute is CORRECT
   BEHAVIOUR, not a footgun — ptrace has NO backaction (survivors'
   reduced state invariant under any channel on the traced system;
   tracing ≡ never touching). The entangling computation mixed the
   survivors, not the trace. Resulting normative rule: **implicit ops
   with backaction warn (P2 casts); implicit ops without backaction are
   silent (traces)**. No nagging. Frictions documented in §3.9: regions
   not GC (finalizers nondeterministic; @context cleanup exists since
   sv3); ptrace ≠ reset (recycle needs a reset channel); pure-context
   lowering (measure-and-discard is exact by no-signaling, or
   Stinespring keep-alive); when-bodies need the clean-ancilla witness
   (witnessed dealloc is not a trace; unwitnessed fires guardrail 1);
   views borrow, never own. §4.5 refined: region boundary = derived
   implicit ptrace!, not a third consumption mechanism. New D10: region
   spelling for eager helpers (no exit hooks in Julia).

---

## Round 2 (original entry)

**Bead:** `Sturm.jl-oqu3` (P1, task). **Output:** revised `Sturm-PRD-v2.md`
(495 → 765 lines). **New bug filed:** `Sturm.jl-wm28` (teleportation, P1).

## What happened

Tobias: "continue work on refining and improve the new prd. I am not yet
100% happy with it." Method: main-thread first-hand critique + four Sonnet
subagents in parallel — (A) D5 porting experiment run against the real
codebase, (B) web citation audit of every load-bearing arXiv reference,
(C) prior-art sweep on `dual`/quaternion-kernel/consuming-casts, (D)
file:line re-verification of the §8/§1.2 defect claims. All four reports
folded into the PRD.

NOTE: the worklog-referenced bead `u9o6` (session 91) does not exist in the
beads DB — `oqu3` supersedes the reference.

## Headline results

1. **D5 EXECUTED, bar met.** All five algorithms (teleport, DJ, Grover,
   Draper/Beauregard, QSVT sign-filter) port with **0 user-level escapes**.
   Grover's `_multi_controlled_z!` Toffoli-cascade-with-ancilla dissolves
   into nested `when` + `not!(dual(·))` (exact — CZ angle is π, ctrl is
   closed). DJ's `superpose!`/`interfere!` sandwich collapses to
   `Int(dual(x))`. Library-internal escapes concentrate in QSVT/PREPARE/
   SELECT (continuous phase data — sanctioned in §5).
2. **v0.1's shipped teleportation is physically WRONG** (`wm28`): no
   conjugate-basis readout (v0.1 has no vocabulary for one) → teleports
   the diagonal only; Z-marginal test can't see it; empirically verified
   (|i⟩ input reads P(Y=+1)≈0.5). Now §7.1's negative example + §8.8.
   CAVEAT for whoever picks up wm28: the investigating agent's quick
   H!-insert patch STILL read ≈0.5 on its Sdg;H!;Bool harness — either the
   patch or the harness is wrong; needs a from-scratch paper derivation.
3. **`dual` = Pontryagin duality** — new framing in §3.3. Involutivity,
   Draper-as-translation↔modulation, CZ symmetry, and P7 all become
   corollaries of one theorem. Anyons rightly stay open (fusion categories
   aren't groups).
4. **Citation corrections** (§1.1/§3.5/§3.7): the three coherent-control
   conditions redistribute — Bădescu–Panangaden §1 Conditions I/III are the
   primary guardrail source; Yuan–Villanyi–Carbin is OOPSLA 2024 (not
   POPL) and gives injectivity+synchronization ⟺ unitary+disentangled
   (Thms 4.4/4.8/4.9, Def 4.7); Ying–Yu–Feng supports ONLY
   guard-externality (its framework deliberately admits non-unitary
   branches). H-via-(CZ+|+⟩+X-measure) is Raussendorf–Browne–Briegel, NOT
   Zhou–Leung–Chuang (CNOT+Z-measure). "Section of U(d)→PU(d)" flagged as
   our gloss. Araújo's 1⊕U constructive half added as the positive
   argument FOR the kernel (process value = the side-information that
   makes control possible).
5. **New §4.2 normative constraints from SDK archaeology**: Cirq/Qiskit/
   pytket all had global-phase fields and shipped controlled-phase bugs
   2018–2023 anyway → `ctrl` must be the ONLY constructor of controlled
   lowerings (single choke point). Control-scope reassociation
   ((1⊗V)∘ctrl(W)∘(1⊗V†) = ctrl(V∘W∘V†)) promoted from hand-rolled idiom
   (3 independent sites in v0.1!) to kernel law + pass + named combinator.
6. **Linearity contradiction resolved** (§4.5): old text said mutation
   forms "consume-and-rebind" but §7.1's `c = false ⊻ b` keeps `b` live.
   New rule: handles are stable identities; consumption happens at qc
   casts and `ptrace!` ONLY. Positioning: semantics = Twist's T-Measure;
   enforcement = runtime (VOQC §3.3 justifies for host-embedded DSLs).
7. **D1 half-settled by entailment**: §3.7 universality REQUIRES a
   phase-bearing literal (real stabilizer ops can't manufacture e^{iπ/4});
   only the spelling remains open.
8. **D2 sharpened to a theorem**: register dual (ℤ_{2^W} QFT) ≠ per-wire
   dual ((ℤ₂)^W Walsh–Hadamard) — different groups, same wires; QFT has
   maximal operator entanglement (Chen–Stoudenmire–White 2210.08468).
   Plus: v0.1 has NO public wire-indexing form — all five D5 algorithms
   use a private QBool constructor that bypasses cast discipline. `x[i]`
   as a checked aliasing view is a v2 prerequisite.
9. **D4 resolved by counterexample**: Grover's diffusion materializes
   H^⊗n on live entangled registers — "essentially never" was wrong.
10. **Prior art**: `dual` is novel; nearest neighbor Qwerty
    (arXiv:2404.12603) has first-class bases + Fourier-measurement but
    explicitly REJECTS the zero-cost view reading. Quaternion+phase as
    persistent 1q fusion IR: novel combination (Qiskit's Quaternion is a
    narrow Euler-reordering utility). Consuming-cast semantics
    anticipated by Silq/Twist; cast-syntax spelling is novel.
11. **New sections**: §3.8 normative seven-construct surface table (v2
    analogue of rule 11's table); D9 (oracle × dual composition — the one
    thing D5 couldn't classify); D6 gained two verified qudit traps
    (Gauss-sum d mod 4 bifurcation; even/odd-d metaplectic asymmetry —
    Gross/Appleby).

## Gotchas / corrections to prior claims

- **§8.4 was stale**: aliasing IS caught in Julia (`_check_distinct`,
  `src/orkan/ffi.jl:183`, since c3d4c00/2026-04-05) — but only at the FFI
  shim, leaking physical indices. PRD §8.4 reworded.
- `_apply_ctrls` cap is **2 controls** (errors at ≥3), not "≥3 cap".
- All other §8/§1.2 defect claims re-verified CONFIRMED at file:line,
  empirically reproduced (agent D ran a live REPL).
- bd dolt push is failing (non-fast-forward) — needs `bd dolt pull` before
  session close.

## Open next steps

- Tobias to argue/accept the revised draft (it's his call — doc is DRAFT
  for argument).
- `wm28` teleportation fix (P1, independent of v2).
- Citations-TODO list in §9 is now precise enough to write the
  `docs/physics/` distillations mechanically (~16 papers).
- D2 ruling (slice-vs-dual), D1 spelling, D9 example — the three genuinely
  open surface questions left.
