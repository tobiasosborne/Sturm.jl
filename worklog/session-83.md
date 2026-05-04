## 2026-05-04 — Session 83: bd resync from origin + ph26 doc sweep + viz-frontend epic plan

Three streams: re-cloned beads from origin (canonical), shipped the ph26 doc-sweep
(README is now the source of truth for the DSL surface), and filed a 34-bead
plan for a best-in-class web visualization frontend after deep-research on
Classiq Studio + survey of code-viz tooling used by working software engineers.

### Stream 1 — bd sync from GitHub remote

Local `.beads/embeddeddolt/` had diverged from origin (local refs/dolt/data
`f1b3947`, origin `155e6d4`); `bd dolt pull` hit a merge conflict. User clarified
beads-on-GitHub is canonical, local is not. Resolution:

- Moved `.beads/embeddeddolt/` to `.beads/embeddeddolt.bak.20260504-082047/`.
- `git update-ref refs/dolt/data 155e6d4...` to reset local ref.
- `bd bootstrap --yes` succeeded after fixing `.beads/config.yaml` sync URL
  from `git+ssh://git@github.com/...` to `git+https://github.com/...` (matches
  origin auth — git over SSH was failing for the user's HTTPS-credential setup).
- 10,532 chunks downloaded; ended on 198 issues (was 204 locally), 0 in-progress,
  5 blocked, 47 open, 42 ready.

Future agents: if `bd bootstrap` fails with SSH permission denied, fix the URL
in `.beads/config.yaml` first. The dolt remote URL must match whatever auth
scheme works for `git push origin main`.

### Stream 2 — ph26 doc sweep (PRD + CLAUDE.md + 5 src docstrings)

Closed `Sturm.jl-ph26` (commit `92d781d`). README was rewritten in session 81
(commit `1d17cab`) to drop CNOT (`a ⊻= b`) from the primitives table and reframe
the DSL as **two rotation primitives + two P2 casts + the `when` binder**, with
`not!` as the one named exception. Five other docs still claimed "four
primitives":

- **PRD §1 (P5 + P7) and §3 (full primitives section)** — rewrote §3 with the
  5-row surface-form table + new §3.1 "The named exception: `not!`" + §3.2
  derived gates with `swap!` rebuilt from `when` + `not!` (no more `a ⊻= b`).
  §7.1 shipped-features list updated. §9.5 reframed as "library convenience
  operator" instead of primitive #4.
- **CLAUDE.md** — Rule 11 rewritten as "TWO ROTATIONS, TWO CASTS, ONE BINDER";
  Rule 3 (physics ground), Global-Phase section ("two rotation primitives
  generate SU(2)"), mutation-convention rule, Orkan-FFI ASCII, file-structure
  comment all aligned.
- **5 src docstrings** — `gates.jl`, `library/{patterns,shor,arithmetic}.jl`,
  `types/qint.jl` headers updated to "rotation primitives + when + not!" or
  similar, with the `⊻=` operator explicitly framed as library convenience sugar
  for `when(b) do; not!(a); end`.

Deliberately **not** touched: `worklog/*` and `WORKLOG-archive.md` (historical
record — the "four primitives" framing was correct *at time of writing*;
sessions-80-to-82 even narrates this transition); `docs/literature/*` surveys
and `docs/physics/qudit_*.md` distillations (external-paper notes / design
alternatives). Touching those would rewrite history.

8 files / 79 ins / 45 del. Doc-only — smoke test (load + Bell pair) green.
Pushed in commit `92d781d`.

### Stream 3 — Viz-frontend deep research + 34-bead epic plan

User asked: investigate Classiq's visualization (they brag about it; suspicion
is "totally standard stuff dressed up for physicists") AND survey best-in-class
code-viz tooling for real software engineers (Rust/TS/Go), since the goal is
to add a web-viz frontend to Sturm.jl that's ground-up software-engineering
quality, not physicist-textbook circuit diagrams.

Two parallel sonnet deep-web research agents launched. Reports saved to
`../research-notebook/raw/classiq-eval/CLASSIQ_VISUALIZATION_DEEPDIVE.md` and
`../research-notebook/raw/code-viz-survey/CODE_VIZ_BEST_IN_CLASS.md`.

Key findings:

1. **Classiq Studio is standard React+TypeScript+(~70% confidence)React Flow**
   with Dagre/ELK layout. The pixels are not novel — the *semantic layer* is.
   Two views: Functional Block (default, hierarchical DAG, double-click drill
   down) + Variables View (typed-wire flow overlay). The reason no other tool
   does this isn't rendering — it's that no other tool has a high-level IR to
   draw from. **Sturm's channel DAG is exactly the same kind of asset.**

2. **Important Classiq engineering signal** (their July 2025 blog): large
   circuits hit a 1.6 GB JSON payload wall; fixed via ID-reference
   deduplication (`{id → Operation}` flat dict, reconstruct tree client-side)
   → 22 MB. **Plan for the flat-dict shape from day one** — bead p0b enforces this.

3. **No Classiq visualization patent exists.** US11720812 ("Graphical
   Representation of Quantum Circuit") is IBM's. Their viz IP is essentially
   nil — design freely.

4. **Convergent stack circa 2026**: React Flow (`@xyflow/react`, MIT) + ELK.js
   (Eclipse Layout Kernel JS port — only JS layout that handles **named ports**
   natively, critical for control/target/ancilla anchoring) + Monaco Editor
   (MIT, the VS Code editor) + WebGL fallback (Pixi.js or Sigma.js) above ~1k
   nodes. Stripe, Typeform, every AI pipeline builder use this exact stack.

5. **What Classiq does NOT have** (Sturm's opening to surpass): bidirectional
   code↔diagram sync (Compiler Explorer pattern), live EagerContext streaming
   (Tracy pattern), per-node decoherence overlay (`DensityMatrixContext`-fed),
   open-source.

Filed as 1 epic + 33 atom tasks across 9 phases (priority P2 for MVP path,
P3 for enhancements):

- **EPIC**: Sturm.jl-02nv
- **Phase 0 — Design** (P2): subproject layout `1ypa`; JSON wire-schema `pv3p`
- **Phase 1 — Julia serializer** (P2): `to_json` w/ ID-dedup `wmj5`; source-range
  capture in DSL macros `8jps`; per-node cost surfacing `a0ut`; golden snapshots
  `pzv6`
- **Phase 2 — MVP viewer** (P2): Vite/React/TS scaffold `grr6`; React Flow + ELK
  with named ports `6g5j`; channel-node React renderers `g105`; pan/zoom/minimap
  + drill-down `ikrj`; **MVP completion gate `dy1y`** (file-drop + golden
  screenshots)
- **Phase 3 — source↔DAG sync** (P2, killer feature): Monaco pane `18si`;
  click→source `ui6x`; cursor→DAG `dre8`; URL state `bs83`
- **Phase 4 — live streaming** (P3): WebSocket `ol1k`; event protocol `5e8x`;
  live-timeline view `n9gn`; replay controls `0eth`
- **Phase 5 — Compiler-Explorer multipane** (P3): pane manager `xokd`; shared
  selection `trrx`; pass-pipeline diff viewer `43xc`
- **Phase 6 — semantic zoom + sandwich** (P3): zoom-conditional rendering
  `8s9o`; sandwich callers/callees split `l29d`
- **Phase 7 — DM noise overlay** (P3, Sturm-unique): per-node decoherence color
  `bu0r`; animation along edges `6s0b`
- **Phase 8 — deployment** (P3): VS Code Webview `d1cl`; Jupyter widget `fhel`;
  static HTML export `afbl`; Graphviz `to_dot()` `ezga`
- **Phase 9 — perf scale-up** (P3): WebGL fallback `0qje`; streaming JSON
  parser `hizr`; 10k-gate bench `66p7`

**Critical path to MVP**: 1ypa → pv3p → (wmj5 || 8jps || a0ut) → pzv6 → grr6 →
6g5j → g105 → ikrj → **dy1y**. Once dy1y closes, Sturm has a publishable
best-in-class viewer; everything after is enhancement.

### Stream 3a — bd dep tooling glitch (recurring from session 82)

`bd dep add --type blocks` fails on this DB with `Error 1146: table not found:
wisp_dependencies`. Pre-existing schema gap from earlier sync — session 82's
worklog already noted "bd dep is broken on this DB; dependency chain lives in
prose notes instead". Session 83 workaround: used `bd link --type parent-child`
which emits the cycle-check failure as a *warning* instead of an *error* and
proceeds to create the link. The 33 viz parent-child relations were recorded;
however `bd dep tree` / `bd dep list` / `bd ready` cannot display them because
they query the same missing table. Filed `Sturm.jl-yl52` (P2 bug) so a future
bd-binary upgrade or schema migration can systematically clear this.

The user-facing impact: `bd ready` shows ALL viz beads as ready, which is
misleading — only the two Phase-0 atoms (1ypa subproject layout, pv3p JSON
schema) should be picked up first. Epic Sturm.jl-02nv has an explicit
phase-ordering note in its description block to compensate.

### Carryover

- `Sturm.jl-yl52` — bd dep tooling needs schema repair / bd binary upgrade.
- `.beads/embeddeddolt.bak.20260504-082047/` exists locally (the diverged dolt
  state from before the resync). Safe to delete after verifying nothing was
  lost — the 198 origin issues are all that matter; the local 204 had 6 stale
  experimental entries that never made it to GitHub.
- The 33 viz beads are unblocked-from-bd's-perspective but actually
  prerequisite-ordered. Phase 0 (1ypa, pv3p) is the only legitimate "ready"
  set. Don't pick up later phases without their actual prereqs done.
