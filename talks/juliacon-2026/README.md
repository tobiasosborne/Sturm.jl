# JuliaCon 2026 — "Given an Oracle for *f*"

A 15-minute JuliaCon talk about Sturm.jl (a quantum programming DSL),
Bennett.jl (a Julia→reversible-circuit compiler), and BennettVM.jl (a
reversible interpreter backend) — delivered as a single self-contained
HTML slide deck with a live terminal demo running alongside it.

## Contents

| Path | What |
|---|---|
| `src/DECK-SPEC.md` | Normative slide-by-slide contract for the deck build (design tokens, engine API, per-slide content, verified numbers). |
| `src/frame.html`, `src/engine.js`, `src/slides-a.html`, `src/slides-b.html`, `src/components.js`, `src/circuits.json`, `src/build.py` | Deck sources; spliced by `build.py` into `talk.html`. |
| `talk.html` | The built deck (generated — run `src/build.py` to produce it; not committed pre-built). |
| `demoenv/` | A dual-develop Julia environment (Sturm.jl + Bennett.jl `Pkg.develop`'ed side by side) for the live demo — generated, not committed. |
| `warmup.jl` | Runnable backstage warm-up script: pays every JIT/precompile cost, defines every function the live beats need. |
| `DEMO-RUNBOOK.md` | The full stage runbook — day-before checklist, backstage procedure, live-beat table, fallback drill, timing checkpoints, Q&A ammunition. |

## Opening the deck

Build it first (see below), then open directly from disk — no server
needed:

```
file:///home/tobiasosborne/Projects/Sturm.jl/talks/juliacon-2026/talk.html
```

Keys: `→`/`Space`/`PgDn` advance (build-then-slide) · `←`/`PgUp`
reverse · `Home`/`End` · `F` fullscreen · `?` help overlay (`Esc`
closes) · `D` toggle shadow-terminal transcript in the terminal band ·
`T` toggle timer HUD (`Shift+T` resets it) · `N` toggle speaker notes ·
`0` jump to the `#fallback` recorded-run backup · `S` jump to the
`#stepper` 23-gate-walkthrough backup · `B` return to the last linear
slide from any backup · number keys map nowhere else · clicking the
right/left third of the stage advances/reverses. URL hash addresses
slides directly (`#s4`) and backups (`#fallback`, `#pebbling`,
`#vmtape`, `#numbers-full`, `#stepper`). Append `?still` to force every
build step and component to its final state (screenshot/print mode).

Full stage procedure, live-command table, and fallback drill:
**`DEMO-RUNBOOK.md`**.

## Rebuilding the deck

```bash
cd /home/tobiasosborne/Projects/Sturm.jl/talks/juliacon-2026
python3 src/build.py
```

Splices `frame.html` + `slides-a.html` + `slides-b.html` + `engine.js` +
`components.js` + `circuits.json`, and inlines three SVG assets (plus
one base64-embedded recording) from the sibling `Bennett.jl` checkout's
`docs/src/assets/`, into `talk.html`. Requires no packages beyond the
Python standard library.

## Running the warm-up

The live demo needs a dedicated environment (Sturm's own project cannot
`using Bennett` — it's a weakdep) and two environment variables set
*before* Julia starts:

```bash
# one-time / after any rebuild of either sibling package:
julia -e '
using Pkg
Pkg.activate("talks/juliacon-2026/demoenv")
Pkg.develop(path="/home/tobiasosborne/Projects/Sturm.jl")
Pkg.develop(path="/home/tobiasosborne/Projects/Bennett.jl")
Pkg.precompile()'

# every session, before starting julia:
export OMP_NUM_THREADS=16
export LIBORKAN_PATH=/home/tobiasosborne/Projects/orkan/cmake-build-release/src/liborkan.so
julia --project=talks/juliacon-2026/demoenv
```

Then at the `julia>` prompt:

```julia
include("talks/juliacon-2026/warmup.jl")
```

This pays every JIT/precompile cost the live beats will hit (notably a
first-ever `oracle()` call, ~20.8 s cold) and defines every function the
four live beats call. It prints a cheat-sheet at the end listing the
nine lines to retype (once, in a specific order) so they land in REPL
history for `↑`+`Enter` on stage — see `DEMO-RUNBOOK.md` §(b)–(c) for
why retyping is necessary (`include()` does not populate interactive
REPL history) and the exact procedure.

## License

AGPL-3.0, matching the parent `Sturm.jl` repository — see `LICENSE` at
the repo root. Every file in this talk folder, including the deck
sources and this warm-up script, is covered.
