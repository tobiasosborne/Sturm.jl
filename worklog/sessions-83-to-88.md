## 2026-05-05 — Session 88: 4ceh QSVT post-selection-rate root-cause investigation (open, handoff)

Filed and investigated bead `Sturm.jl-4ceh` (P1 bug). Surfaced from session
87's u1er Phase 2 random-2x2 demo: the QSVT post-selection success rate for
multi-ancilla block encodings (m ≥ 2) is consistently far below the naïve
GSLW Theorem 17 prediction. Conditional-on-success output matches the
analytical reference, so amplitude is leaking out of the flag-zero
subspace somewhere and the existing tests (which only check conditional
distributions and use loose `n_success > 30` thresholds) don't catch it.

**Hypothesis tried and falsified**:
`qsvt_reflect!` (src/qsvt/circuit.jl line 228) applies
`ancillas[1].φ += -2*phases[j]` — a single-qubit Rz on ancilla 0 — instead
of the GSLW canonical `Π^φ = e^{iφ(2|0⟩⟨0|^m − I)}`. For m=1 these are
identical; for m≥2 they differ. The natural fix was to route the rotation
through the existing `_reflect_ancilla_phase!` helper (line 605, written
for OAA in bead 1g7, which IS the canonical multi-controlled reflection).

Empirically:

| Case               | m | Single-Rz (current) | Multi-controlled (canonical) |
|--------------------|---|---------------------|------------------------------|
| H = Z              | 1 | 100% ✓              | 100% ✓                       |
| 3-Pauli H          | 2 | ~37%                | 35% (worse)                  |

Conditional output matched the analytical reference under both. So the
phases from `qsvt_phases` are calibrated for the single-Rz convention,
not the canonical Π^φ — replacing the rotation broke the calibration.
Reverted; comment block on `qsvt_reflect!` documents the failed attempt
so future agents don't repeat it (commit 328726f).

**Empirical structure surfaced for the next investigator**: across four
distinct 3-Pauli-term Hamiltonians with sign polynomial, the measured
success rate ≈ `⟨ψ|(H/α)²|ψ⟩` exactly — the one-step block-encoding
success probability, NOT the iterated QSVT result.

| | r²/α² (one-step) | Measured |
|---|---|---|
| Random case 1 | 0.470 | 0.50 |
| Random case 2 | 0.379 | 0.40 |
| Random case 3 | 0.479 | 0.46 |
| Probe2 H      | 0.347 | 0.37 |

The Hamsim **cos** test on the same m=2 ising BE gets ~80% success when
r²/α² = 0.375 — the rule isn't universal. Polynomial-parity dependence
I don't yet understand.

**Live hypotheses on the bead** (none confirmed):
- H6: implemented polynomial under single-Rz convention is `P(A/α)·(H/α)`,
  not `P(A/α)` — extra `(H/α)` factor. Matches the sign-poly observation
  but doesn't explain cos.
- H7: LCU PREPARE pad-state leakage (when L is not a power of 2, e.g. L=3
  → m=2 with `|11⟩` as a padding slot). Doesn't explain cos either (L=3 too).
- H8: `qsvt_phases` introduces a parity-dependent normalization (BS-25 →
  Laneve-25 → `phi[end] += π/2`).

**Concrete next-step probe** (for the next agent):
Take a 1-qubit BE that gives 100% (e.g. H = Z), pad it to m=2 by adding a
tautological identity ancilla wire that doesn't participate in the encoded
operator. Same eigenvalues, same polynomial, different m. If the padded
version tanks success → H7 (PREPARE pads are the culprit). If not → H6/H8,
and the next move is to hand-multiply qsvt_reflect for n=3 phases on a
tiny m=2 BE and compute the polynomial actually implemented.

**Tooling left for the next agent**:
- `/tmp/4ceh_probe1.jl` — clean rate measurement on H=Z and ising-cos.
  Reproduces the sign m=1 → 100% / cos m=2 → 80% baseline.
- `/tmp/4ceh_probe2.jl` — minimal m=2 reproduction (3 Pauli terms, 400 shots).
- Bead `Sturm.jl-4ceh` notes contain the full hypothesis matrix and reasoning.

**Bead state**: `4ceh` claimed/in_progress, code reverted, all findings
recorded. **Do not repeat the multi-controlled-reflection swap** — it's
documented as a dead end. Start with the H7 padding probe.

**Related beads filed this session**:
- `Sturm.jl-zh8u` (P2) — projector via Lin-Tong Lemma 5 LCU
- `Sturm.jl-jlaw` (P2) — `Vector{QBool}` → typed register hygiene

---

## 2026-05-04 — Session 87: u1er QSVT eigenvalue filter / sign polynomial shipped

Bead `Sturm.jl-u1er` (P2 → CLOSED). First concrete non-Hamsim QSVT atom
of the mt9 epic. HHL explicitly excluded from the epic per user direction.

Three deliverables across two commits:

**Phase 1 (commit 08f2b68)** — `sign_polynomial(δ, ε)` in
`src/qsvt/polynomials.jl`. Lin-Tong 2020 Lemma 3 odd-parity Chebyshev
coefficients: `|S(x)| ≤ 1` on `[-1,1]`, `|S(x) − sign(x)| ≤ ε` on
`[-1,-δ] ∪ [δ,1]`, degree `O((1/δ) log(1/ε))`. Construction: DCT-I of
`erf(K·x)` at Chebyshev–Lobatto nodes with `K = √(log(2/ε))/δ`, automatic
degree from Chebyshev tail, final rescale `(1 − ε/4)` for QSP downscaling
headroom.

Three new `docs/physics/` distillations per Rule 4 (none existed for the
QSVT pipeline before this commit — the existing src cited `docs/literature/`
only):
- `berntson_sunderhauf_2025_complementary_polynomials.md` — BS-25 P→Q
  (FFT, provably stable). Algorithm 1 with explicit error bound.
- `laneve_2025_gqsp_nlft.md` — Laneve-25 (P,Q) → phase factors via NLFT
  inverse / RHW. Theorem 5 NLFT bridge, §4.3 RHW algorithm.
- `lin_tong_2020_ground_state_prep.md` — Lemma 3 (the polynomial),
  Lemma 5 (reflector → projector, deferred to bead `zh8u`).

`test/test_qsvt_sign_polynomial.jl` — TDD red→green, 570 tests covering
shape, Lemma 3 (1) and (2), degree scaling, and integration with
`qsvt_phases` (verifies BS-25 → Laneve-25 pipeline accepts the polynomial
and emits 2d+1 phases for odd parity). Wired into `test/runtests.jl`.

**Phase 2 (commit 0472374)** — End-to-end `sign(H)` on a 1-qubit
block-encoded H = Z. Build H = Z directly as `PauliHamiltonian{1}`, then
run the shipped pipeline:

```julia
cheb = sign_polynomial(δ=0.5, ε=0.05)
phi  = qsvt_phases(cheb; epsilon=1e-3)         # BS-25 → Laneve-25 RHW
@context EagerContext() begin
    sys = [QBool(0.5)]                          # |+⟩ via P2 prep cast
    success = qsvt_reflect!(sys, be_of_Z, phi)
    if success
        sys[1].φ += π                           # ┐ Hadamard via primitives
        sys[1].θ += π / 2                       # ┘ no named gate
        Bool(sys[1])                            # → 1 with prob > 0.85
    end
end
```

Statistical acceptance (400 shots): post-selection > 50%, `P(1)|success
> 0.85`. Both pass on real Orkan. Zero named gates in new code; Hadamard
synthesised via the rotation primitives.

**Random 2x2 demo (commit 7eaaba4)** — Sturdier check after user pushback
("Z is too simple and won't expose real problems"). Three deterministic-
seed (`MersenneTwister(0xc0ffee)`) random Hermitians of the form
`a_X·X + a_Y·Y + a_Z·Z`, eigenvectors not aligned with the computational
basis. Reference computed via spectral decomposition (`eigen(Hermitian(H/α))`),
fully independent of the QSVT pipeline. Maximum residual `|Δ| = 0.041`
(case 2) on 600 shots — all within polynomial slack.

| case | a_X | a_Y | a_Z | α | λ/α | P(1) exp | P(1) meas | post-sel |
|---|---|---|---|---|---|---|---|---|
| 1 | 0.156 | -0.049 | 0.326 | 0.532 | ±0.687 | 0.201 | 0.203 | 300/600 |
| 2 | -0.178 | 0.489 | -0.374 | 1.041 | ±0.616 | 0.660 | 0.619 | 239/600 |
| 3 | -0.090 | 0.446 | 0.160 | 0.697 | ±0.693 | 0.890 | 0.924 | 276/600 |

The post-selection rates ~50% (vs. naïvely-predicted ~97%) led to the
4ceh bug filing and Session 88's investigation above.

**Idiom hygiene during u1er**: zero named gates in new code. Hadamard
spelled `q.φ += π; q.θ += π/2` (the rotation primitives directly) per
the README rule that Hadamard "has no Julia-classical counterpart; when
you need one, write the rotation primitives directly". The existing
`Vector{QBool}` antipattern in `qsvt_reflect!` was untouched; refactor
is filed as `jlaw` to land before more QSVT atoms.

**Related beads filed during u1er**:
- `Sturm.jl-zh8u` (P2) — Lin-Tong Lemma 5 projector LCU + GSLW19 Lemma 29
  shift, builds `Π_{<µ}` from the reflector. Foundation for ground-state
  prep. Includes the `H − µI` shift that brings non-zero thresholds online.
- `Sturm.jl-jlaw` (P2) — `Vector{QBool}` → typed register hygiene across
  QSVT/block-encoding API. Sequencing: ship before more QSVT atoms.

**Test count after u1er**: 590 in `test_qsvt_sign_polynomial` (215+575
in the QSVT triangle).

---

## 2026-05-04 — Session 86: Sextant.jl PRD + PLAN + CLAUDE.md (fresh-agent handoff docs)

User asked for a PRD + plan in Sextant.jl so a fresh agent (or human
contributor) can pick up work without prior context. Three docs landed in
Sextant.jl commit `d43da79`:

- **`CLAUDE.md`** — local conventions + bd-tracking quirks. Key points:
  Sextant beads live in Sturm.jl's bd db with `sextant` label (no `bd init`
  here for now); reading order for fresh agents (CLAUDE → PRD → PLAN →
  research reports → Sturm/CLAUDE.md for shared engineering discipline);
  the wisp_dependencies caveat (yl52); session-close protocol mirroring
  Sturm.jl's. Explicitly defers the development-discipline rules (TDD,
  fail-fast, no parallel Julia, etc.) to Sturm/CLAUDE.md as authoritative —
  Sextant inherits, doesn't duplicate.

- **`Sextant-PRD.md`** — vision document (~400 lines). Sections: one-line
  summary; why-this-exists (the Discourse 2017+2022 community-want gap);
  four pillars (idiomatic, REPL-first, substrate not application, static
  export beats live server); nine design principles (P1 Profile.jl is the
  foundation, P2 REPL-usable on day one, P3 versioned schema, P4 extension
  API as the only public seam, P5 static export primary, P6 monorepo, P7
  sampled coverage OK for v1.0, P8 license-free deps, P9 golden-snapshot
  testing); explicit non-goals list (custom tracer, JET overlays, multi-
  pane, semantic zoom, WebGL fallback — all deferred); layered-stack
  architecture diagram; Trace data model spec (flat ID-keyed dict per
  Classiq's lesson, extensions slot for downstream packages); extension API
  contract sketch; public API surface (provisional names); license.

- **`PLAN.md`** — six-phase bead plan with full Sturm.jl-XXXX IDs and an
  ASCII critical-path diagram. Each phase has a status table (bead ID,
  title, status, prerequisite). Section per phase explaining the goal.
  Calls out the two milestones explicitly: `wse6` (REPL milestone — Sextant
  becomes useful with no JS) and `akqx` (MVP gate — registerable in
  General). Reference materials section pointing at the three deep-research
  reports in `~/Projects/research-notebook/raw/`. "After v1.0" section
  noting the JuliaCon-talk pitch as a possibility.

- **`README.md`** — updated index pointing at the three docs.

No bead filed for this — it's documentation following a closed bead (aywf).
The work is captured here in the worklog and in Sextant's git history.

### What an agent will see

- Sextant.jl repo lands them in CLAUDE.md
- CLAUDE.md tells them: read PRD next, then PLAN, then claim a bead
- PLAN tells them: next ready is `uo0f` (JSON schema spec, design-doc-only)
- bd shows them the bead description; the prerequisite chain in PLAN.md
  guides them past the broken `bd ready` / wisp_dependencies issue
- Three deep-research reports in research-notebook explain the *why*

### Next ready bead — confirmed

`Sturm.jl-uo0f` (sx-0b) — JSON wire-schema v0.1 spec. Pure design doc
(no code). Lands `Sextant.jl/docs/SCHEMA.md` with the full spec + a worked
Bell-pair example. Lock the contract before any tracer code is written.

---

## 2026-05-04 — Session 85: Sextant.jl scaffolded + GitHub repo shipped (sx-0a closed)

Closed bead `Sturm.jl-aywf` (sx-0a — project scaffold). Sextant.jl bootstrap
shipped at https://github.com/tobiasosborne/Sextant.jl, local checkout at
`~/Projects/Sextant.jl/` (sibling of Sturm.jl, not nested). Initial commit
4ce55b8.

Files committed:
- `Project.toml` — UUID `4e87280d-b85f-4806-ba75-75b359194199`, AGPL-3.0,
  Julia 1.11 compat, Test in extras
- `src/Sextant.jl` — module skeleton with elevator-pitch docstring
- `test/runtests.jl` — module-loads testset, passes
- `LICENSE` — AGPL-3.0 (copied from Sturm.jl, same license)
- `README.md` — pitch ("the missing graphical Cthulhu"), architecture table,
  6-phase roadmap, status, install/test
- `.gitignore` — Julia + Vite/Node frontend + IDE/OS standards
- `.github/workflows/CI.yml` — Julia 1.11+1.12 matrix on ubuntu-latest
- `docs/SCHEMA.md` — placeholder for v0.1 wire-schema (lands sx-0b)
- `frontend/README.md` — placeholder for the React Flow + ELK + Monaco viewer
  (scaffolds at sx-2a)

Decisions:
- **Repo lives at `~/Projects/Sextant.jl`**, sibling of Sturm.jl. NOT nested
  under Sturm.jl — it's a peer package, not a subpackage.
- **No `bd init` in Sextant** for now — beads continue to live in the Sturm.jl
  bd database with the `sextant` label. Argument: avoids fragmenting tracking
  during bootstrap; can split later if Sextant grows independent contributors.
- **GitHub repo is public** (matches Sturm.jl posture; fits "gift to the Julia
  community" framing).
- **`.gitignore` excludes `frontend/node_modules/`, `frontend/dist/`** so the
  Vite scaffold landing in sx-2a won't pollute git.

Smoke test: `julia --project -e 'using Pkg; Pkg.test()'` → 1 pass / 1 total.

### Next ready beads in Sextant

- `Sturm.jl-uo0f` (sx-0b) — JSON wire-schema v0.1 with extension slots
- `Sturm.jl-pxfk` (sx-1a) — Profile.jl + FlameGraphs.jl → Trace value
- `Sturm.jl-wse6` (sx-1b) — AbstractTrees + Base.show REPL renderer (the
  "Tim Holy ships this first" bead — REPL-usable before any JS)

The MVP-of-MVP is `pxfk + wse6`: a working `print_tree(trace(mergesort, rand(1000)))`
in the REPL. One week of effort; validates the data model before frontend
investment.

---

## 2026-05-04 — Session 84: viz scope expansion → Sextant.jl substrate split

Continuation of session 83 within the same day. User pushed the viz scope:
"this should function as a plain Julia vis as well if no quantum gets called.
This is very much in line with sturm.jl being as julia as possible. I realise
this makes the scope 'all of julia' but, there you go." The original 34-bead
Sturm-only viz plan was wrong-shaped for that. Sonnet deep-research agent
launched on Julia code-vis tooling (saved at
`../research-notebook/raw/code-viz-survey/JULIA_CODE_VIZ_SURVEY.md`); findings:

- **The Julia community has wanted a graphical, source-linked, type-annotated
  call-graph navigator for years and nobody has built it.** Cthulhu.jl is REPL
  only; PProf.jl gives flame graphs but the call-graph view is minimal;
  Compiler Explorer/Godbolt supports Julia for assembly only (no typed IR, no
  call structure). Discourse threads from 2017 and 2022 explicitly request a
  call-graph generator; both go unresolved.
- **The right MVP-Julia stack is NOT a custom IRTools dynamo.** Profile.jl is
  stdlib; FlameGraphs.jl already produces an `AbstractTrees`-compatible call
  tree. Build a thin bridge — the classical execution graph already exists.
  IRTools/Cassette/IRTracker are for "complete call capture" (vs sampled),
  which is a Phase-N enhancement, not a foundation. (Cassette is broken on
  Julia 1.12; IRTracker.jl was archived May 2025 — reimplement only when
  sampled coverage is genuinely insufficient.)
- **Bonito.jl is the right Julia↔React bridge** (WebSocket binary serializer,
  ES6 module loading), but file-drop offline viewer is the right MVP — it
  validates the visual design without coupling to Julia process lifecycle.
- **Hybrid quantum-classical execution-graph viz has zero prior art.** QVis,
  Quff, IBM classical-feedforward, all stop at "show classical `if` as a box
  inside a circuit diagram." The Sturm vision is genuinely novel.

Reframed the plan after the user said "what would an expert software engineer
julia expert do?" The expert answer is to build the generic Julia execution
trace package FIRST (Sextant.jl, separate AGPL-3.0), then layer Sturm-specific
quantum extensions ON TOP via a clean extension API. Tim Holy / Jameson Nash /
Kristoffer Carlsson would ship the REPL `print_tree` view in week one and the
file-drop static-HTML viewer in week two; Bonito + live mode comes later.

### Bead restructure

- **Closed all 33 viz atoms from session 83** (1ypa through 66p7) with a single
  supersession note pointing to the new structure. Substantially all of their
  work moved to Sextant. The original `Sturm.jl-02nv` epic is KEPT but rewrote
  its description to be the Sturm-side quantum overlay parent (links to
  Sextant epic + the 6 Sturm-quantum atoms).
- **Filed Sextant.jl epic Sturm.jl-pggr + 22 atoms** (still under Sturm.jl bead
  prefix; will move to Sextant.jl's own bead repo when the package is created).
  Phase 0 scaffold (aywf project + uo0f schema), Phase 1 Julia tracer (pxfk
  Profile bridge, wse6 print_tree, wscn to_json, xlhw goldens), Phase 2 frontend
  MVP (rg1s scaffold, a6so React Flow + ELK, hgca classical node renderer, xpqc
  drill-down, **akqx MVP gate** — the bead that makes Sextant registerable in
  General), Phase 3 source↔DAG sync (okad Monaco, dyg3 click→source, 1x1z
  cursor→DAG, g8b9 URL state), Phase 4 live mode (br9n Bonito bridge, j8em
  live updates, 580c replay), Phase 5 deployment (0u0c to_html, g8f7 Pluto, w2io
  VS Code), Phase 6 extension API (bnxj — the seam that lets Sturm extend cleanly).
- **Filed 6 Sturm-quantum-overlay atoms**: rl1s channel-DAG to_json + Sextant
  extension wiring, 5igx quantum node React renderers, **nh4w hybrid Shor demo
  gate** (the Sturm-MVP bead — answers the user's "will it show all of Shor?"
  question end-to-end), 0h7t quantum goldens, 2vfo DM noise overlay (P3,
  Sturm-unique), fwlh quantum-flavoured VS Code/Pluto hooks (P3).

### Critical paths

- **Sextant MVP**: aywf → uo0f → pxfk → wse6 (REPL-usable here, ~1 week of
  effort) → wscn → xlhw → rg1s → a6so → hgca → xpqc → **akqx** (registerable
  in General).
- **Sturm-quantum MVP**: requires Sextant up to bnxj (extension API). Then
  rl1s → 5igx → **nh4w** (hybrid Shor renders end-to-end).

### Architectural decisions captured

1. **Separate package (Sextant.jl)** — the Julia community gets a generic tool;
   Sturm extends it via the extension API; layering is honest and discoverable.
2. **No custom tracer for MVP** — Profile.jl + FlameGraphs.jl is the substrate.
   IRTools dynamo is filed nowhere yet (will be added to a "richer-trace-data"
   epic once MVP is in users' hands).
3. **File-drop offline viewer as MVP** — Bonito live mode is Phase 4; MVP
   doesn't need it. Validates the visual design first.
4. **Monorepo for Sextant** — `frontend/` as a subdir of Sextant.jl, not a
   separate `Sextant-viz` repo. Julia ecosystem doesn't usually fragment
   frontends out; one repo means one CI, one release, one source of truth.
5. **REPL `print_tree` from day one** — implementing `AbstractTrees.children`
   on the Trace type makes the package useful before any JS exists. Tim Holy
   discipline: ship a working primitive, then layer the GUI.

### Carryover

- **Sextant.jl GitHub repo doesn't exist yet** — needs to be created (`aywf`
  bead). When it is, decide whether to give it its own bd database or keep
  beads under Sturm.jl with the `sextant` label. Argument for separate db:
  community contributors shouldn't need to know about Sturm to file Sextant
  issues. Argument for unified: everything stays under one Dolt remote for now,
  decoupling can happen later.
- The `Sturm.jl-yl52` wisp_dependencies bug remains open — `bd dep` writes
  silently warn and create the link (parent-child workaround); reads still
  fail. The 28 new parent-child links exist in the DB but `bd dep tree` /
  `bd ready` cannot display them. Phase ordering is in the epic descriptions.

---

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
