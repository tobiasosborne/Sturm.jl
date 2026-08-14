# Session 108 — 2026-08-13/14 — JuliaCon deck v3 user pass (bead `108g`, OPEN)

**⚠ HANDOFF + CONCURRENCY WARNING (read first).** The user is mid-review of
the deck ("here are my comments as I go through it") — bead `Sturm.jl-108g`
stays **in_progress**; expect more directives. **Another agent is updating
the docs in this repo concurrently**, so the tree will be busy: `git pull
--rebase` before every push, stage NARROWLY (talks/ + worklog/ only), and do
NOT touch `docs/physics/childs_2019_trotter_error.md`,
`src/library/evolve/bounds.jl`, `src/library/evolve/suzuki.jl` — those dirty
files are bead `Sturm.jl-jiae`'s in-flight WIP from another session (tight
Childs Trotter bounds). Do not commit them, do not revert them.

## What changed (all under talks/juliacon-2026/, built talk.html rebuilt)

Deck is now **19 linear slides**; ids stable, four new: s0a/s0b/s0c inserted
after s0. All user directives 2026-08-13, DECK-SPEC updated per change
(spec is v3 and remains the contract — check edits against its voice rules,
now SIX of them).

1. **Retitle** (s0, `<title>`, spec, README, runbook, warmup banner):
   "Quantum programming in ordinary Julia, assisted by LLM agents".
   ⚠ OPEN: the title promises LLM agents; NO slide delivers that beat yet
   (flagged in spec s0 entry, "pending user direction"). Likely next ask.
2. **s0a "All the quantum you need today"** — intro-to-QC on faith:
   reversible computation + H + measurement; universality pinned to Shi
   quant-ph/0205115 + Aharonov quant-ph/0301040 (both verified); T = hardware
   efficiency only; footer apology + quantum.country pointer.
3. **s0b "Why?"** — the chimera slide (sparse, animated, grounded). Inline
   SMIL SVG: Qiskit-vocabulary Python panel + the schematic it means,
   stitched by a gold suture. Dunk carried by verbatim quotes: Heunen/
   Lemonnier/McNally/Rice POPL 2026 (arXiv:2507.11676, "circuits akin to
   assembly languages", "circuit description languages") + QASMBench ACM TQC
   2021 (arXiv:2005.13018 §1.2, OpenQASM "similar to traditional HDL like
   Verilog and VHDL"; "Qiskit is mainly based on Python"). Critique licence
   is scoped to THIS slide only (voice rule 2 rewritten accordingly).
4. **s0c "The dream"** — separation of concerns, two panels (classical
   natural / quantum lawful) + bridge line = the talk's structure.
5. **s3 retitled** "Crossing the classical/quantum boundary is a type
   conversion".
6. **s9 Bennett animation recolored to deck dark palette.** New TALK-LOCAL
   asset `src/assets/bennett_construction_dark.svg` (mechanical hex remap of
   the Bennett.jl original; build.py now splices the local file). Light
   original stays in Bennett.jl for its white-bg docs. Wrapper is `.svg-panel`
   (new frame.html rule), NOT a light figure-card. Phase colours now
   compute=blue/copy=gold/uncompute=green AND the s9 step list uses the same
   classes (fixed a pre-existing list/animation colour mismatch).
7. **s10** — new grounded build: hard to name another language where the
   move is possible; candidates = bytecode runtimes (Python dis/Numba
   LLVM-HPC 2015, JVM, .NET; untyped ⇒ research projects); closest real
   attempt Qiskit ClassicalFunction (tweedledum, typed Int1 subset),
   deprecated Qiskit 1.4 / removed 2.0. Full refs in s10 data-notes.
8. **s15** — gold "That was the whole point." DELETED (user disliked it).
9. **Em dashes: ZERO, everywhere** (voice rule 6). Slides, notes, engine/
   component strings, spec, runbook, README, warmup, built talk.html, and
   the two Bennett.jl SVG label strings ("1 · forward: compute" etc. —
   committed in the Bennett.jl repo). En dashes in proper names stay.
   Verify with `grep -rc '—'` after ANY edit; the user cares.

## Engine/tooling gotchas discovered

- **SMIL vs ?still**: still/print used to show SMIL SVGs at frame 0 (the s0b
  chimera was INVISIBLE in screenshots). Fix in engine.js: `smilToEnd`
  (pauseAnimations + setCurrentTime(60)) applied in `restartSMIL` when STILL
  and in `stillEverything`. New SMIL SVGs must follow the s0b pattern: base
  attributes = FINAL state, entrance animated via `values` + `keyTimes`
  holds from t=0 (no `begin` offsets, no opacity-0 base attrs).
- **Screenshots**: no chromium on this box now; `firefox --headless
  --profile "$(mktemp -d)" --window-size=1280,720 --screenshot out.png
  "file://$PWD/talk.html?still#sXX"` works (fresh profile mandatory, else
  "Firefox is already running"). ⊻ renders as underlined-V in headless
  (DejaVu fallback) — cosmetic, fine with JuliaMono installed.
- **Paths**: README/runbook/warmup had `/home/tobiasosborne/...` baked in;
  machine home is `/home/tobias/...`. Fixed everywhere.
- **warmup.jl OMP check**: was hard-pinned to "16" (bigger-box leftover);
  now requires an explicit cap 1..Sys.CPU_THREADS (this box: 12). README/
  runbook say 12.
- **demoenv/ created this session** (user ran the Pkg.develop setup live);
  it is generated, now gitignored. ⚠ The full warm-up run was IN PROGRESS
  at session end — outcome NOT verified. Next agent: ask the user whether
  `STAGE READY ✅` appeared; any `❌ WARM-UP ASSERTION FAILED` line is a real
  breakage in Sturm/Bennett, not the script.

## Open items for the next talk agent

- LLM-agents beat (title promises it; nothing delivers it). Wait for user.
- Timing: FOUR new slides sit before the old s6@5:00 checkpoint; checkpoints
  were NOT rebalanced (ids unchanged). A timed dry run will likely force
  either trimming or checkpoint edits (engine.js CHECKPOINTS + spec + notes).
- `{{SVG:pipeline}}` / `{{SVG:circuit23}}` build notes are pre-existing and
  deliberate (session 107), not regressions.
- Bennett.jl sibling has the SVG label commit; keep talk-local dark variant
  in sync if the original ever regenerates.
