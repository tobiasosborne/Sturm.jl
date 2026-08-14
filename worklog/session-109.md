# Session 109 — 2026-08-14

## Deck PDF export

`talks/juliacon-2026/talk.pdf` generated via the Playwright-cached Chrome
headless shell (`~/.cache/ms-playwright/chromium_headless_shell-1228/...`,
Chrome-for-Testing 149) — there is no system chromium on this box (session-108
note stands), but the Playwright cache has one and its `--print-to-pdf`
honors the deck's `@page 1280px 720px` print CSS. 25 pages = 19 linear slides
+ 6 backups; `?still` + `smilToEnd` verified to hold under print (s0b chimera
shows END state on its page). Left untracked pending a user call on
committing generated PDFs.

## Full docs generation (bead 6zs4) — Documenter site + README + tutorials

User directive: Bennett.jl-grade docs, "next level, inviting, engaging",
README beginner-accessible; Sonnet survey fan-out then Opus writers.

**Phase 1 — 6 Sonnet surveyors** (parallel, each wrote a digest to the session
scratchpad): kernel+channel, types+surface, context+orkan, library/bennett/
qecc, api/tests/PRD, Bennett.jl-docs exemplar. ~3,700 digest lines.

**Phase 2 — 4 Opus writers** (parallel, disjoint file ownership, shared
WRITERS-BRIEF with fixed sitemap + voice contract + "verify every snippet
live" rule): README.md (445 lines) · Documenter scaffold + getting_started
(make.jl, docs/Project.toml, index, installation, first_program,
choosing_a_context) · six tutorials (teleportation incl. the wm28 story shown
as a Choi matrix, DJ/BV, Grover, Shor, hamsim, QECC incl. phase-noise
amplification) · explanation×6 + howto×2 + reference×7 (263 @docs entries,
zero missing docstrings by checker script).

**Verification discipline held**: every runnable block in every page executed
live (Bennett weakdep via scratch envs — bare `julia --project` cannot
`using Bennett`); full `julia --project=docs docs/make.jl` build exit 0, one
benign size warning (reference/library.html).

### Gotchas / findings (future agents)

- **Documenter rejects links out of docs/src/** ("outside build directory").
  Physics citations from doc pages must be full GitHub blob URLs, NOT
  `../../physics/*.md`. Caught by writer 2's build, corrected mid-flight.
- **`eager` is `public`, not exported** — docs spell `Sturm.eager(cap) do ctx`
  or `using Sturm: eager, density` once. First smoke test failed on this.
- **`when(a) do when(b) do … end end` on ONE line MIS-parses** (Julia 1.12):
  it is NOT a syntax error — the inner do-block parses as the outer lambda's
  parameter tuple and the outer body is EMPTY. Silent wrong-shape, worse than
  an error. `src/library/grover.jl` docstring carried exactly this form;
  fixed to multi-line (docstring + file-header comment), verified by running
  the corrected example (185/200 hits on |111⟩, theory 0.945). Never write
  one-line nested `when`.
- **Captured-variable closures do not Bennett-compile**
  (`find(v -> v == target, …)` with `target` a variable → `_narrow_inst: no
  method for Bennett.IRLoad`); literal predicates work. Documented in
  grover tutorial + write_oracles howto.
- **The brief's "guarded-ifelse instead of branches" oracle claim was WRONG**
  (writer 4 tested it): plain `if` and `ifelse` both compile; the real
  caveat is both arms are computed. Docs state the real thing.
- **Strict-mode lost-binding detector** fires only when the rebound register
  SURVIVES the region (`x = x + 1; return x` throws; `x = x + 1; Int(x)`
  passes silently). Docs use the form that errors.
- **`pkill -f bridge.py` kills your own compound bash command** (its cmdline
  contains the pattern). Anchor: `pkill -f '^python3 bridge\.py$'`.
- Chrome headless `--screenshot` never fires with an open SSE stream under
  `--virtual-time-budget` (page never goes network-idle); use `--timeout=N`.
- `.gitignore` gained `docs/build/` + the experiment's generated files.
- Static assertion sites: 1,279 `@test` + 223 `@test_throws` (grep). The
  README/index quote the runtime count from this session's `Pkg.test` run.

## Live terminal mirror experiment (user-directed, option A)

`talks/juliacon-2026/live-terminal-experiment/`: bridge.py (stdlib SSE server
polling `tmux capture-pane` at 10 Hz, serves the deck same-origin at
127.0.0.1:8123), live.js (paints `#band-out` with deck-native term-line/
term-prompt markup ONLY while connected AND slide is `data-band="live"`;
`?livealways` for testing), make_live.py (regenerates talk-live.html from
../talk.html — a generated copy, never edit by hand). Main deck untouched.
END-TO-END VERIFIED by headless screenshots: real tmux content in the band
("MIRROR-TEST-42", ● LIVE · mirror), AND the fallback (bridge dead → stock
scripted deck, no dead rectangle). Read-only by design: presenter types in
the real terminal (laptop screen), projector mirrors — runbook workflow
unchanged. Await user verdict before any main-deck adoption.
