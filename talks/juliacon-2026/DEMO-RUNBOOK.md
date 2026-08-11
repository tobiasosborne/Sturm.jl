# DEMO-RUNBOOK — "Given an Oracle for f" (JuliaCon 2026, 15 min)

Normative source: `src/DECK-SPEC.md` (slide plan, engine keys, verified
numbers). This runbook is the STAGE-SIDE companion — what the presenter
(Tobias) actually does, in order, on the day and on stage. Where a number
or command here is quoted from the spec, it is **verified** (measured
2026-08-11 on the speaker's machine) — do not improvise a substitute
number under pressure; use the pre-baked one instead (that is the whole
point of the shadow terminal, §d).

Companion files: `warmup.jl` (runnable backstage warm-up), `README.md`
(folder overview, how to open/rebuild the deck).

---

## (a) Day-before checklist

Run this the evening before, not the morning of — anything that fails
here needs time to fix.

1. **Rebuild the demo environment** (dual-develop: Sturm's own project
   cannot `using Bennett` — it's a weakdep — so the demo needs a separate
   environment with both packages `Pkg.develop`'ed side by side):
   ```bash
   julia -e '
   using Pkg
   Pkg.activate("talks/juliacon-2026/demoenv")
   Pkg.develop(path="/home/tobiasosborne/Projects/Sturm.jl")
   Pkg.develop(path="/home/tobiasosborne/Projects/Bennett.jl")
   Pkg.precompile()'
   ```
   Run this from `/home/tobiasosborne/Projects/Sturm.jl`. Do this even if
   `demoenv/` already exists from a previous rehearsal — a stale Manifest
   pointing at moved/rebuilt sibling checkouts is the single most likely
   silent failure mode. One Julia process at a time; let it finish.

2. **Orkan lib check** — confirm the shared library the demo will
   `ccall` into actually exists and is the release build:
   ```bash
   ls -la /home/tobiasosborne/Projects/orkan/cmake-build-release/src/liborkan.so
   ```
   If missing: `cd ../orkan && cmake --preset release && cmake --build cmake-build-release`.
   This is a build-time check only — the ENV VAR that points at it
   (`LIBORKAN_PATH`) is set fresh every session at REPL-launch time (§b),
   never baked into `demoenv`.

3. **Rebuild and smoke-test the deck.** From `talks/juliacon-2026/`:
   ```bash
   python3 src/build.py
   ```
   produces `talk.html`. Open it two ways:
   - Normal: `file:///home/tobiasosborne/Projects/Sturm.jl/talks/juliacon-2026/talk.html`
     — click through all 17 slides (s0–s16) once with →, confirm every
     build step advances, the badge rail lights on schedule, and both
     figures render without console errors (open devtools, check for
     red): the s3 pipeline diagram (static SVG) and the s7 Bennett
     construction (the only SMIL-animated figure in the deck — confirm
     its animation actually runs, and restarts when you re-enter s7).
   - **`?still` smoke test**: append the query string,
     `talk.html?still#s8` (and repeat for a few other slide hashes,
     especially s8/s11/s12 which carry components) — every `.build`
     should already be `.shown`, `costbars`/`entangle`/`stepper` should
     jump straight to final state, and there should be zero visible
     transition/flash. This is the screenshot-safety check; it also
     catches components that silently fail to mount.
   - Also visit each backup by hash once: `#fallback`, `#pebbling`,
     `#vmtape`, `#numbers-full`, `#stepper` — confirm they render and
     that `#fallback`'s embedded recording plays/displays.

4. **Terminal setup.**
   - **Glyph check**: open the deck at `#s12` and confirm the `⊻` operator
     renders as a proper wedge-with-bar, not a boxed/underlined fallback —
     the deck's mono stack falls back through JuliaMono → DejaVu; on a
     freshly imaged venue machine install JuliaMono or any font with
     U+22BB before trusting the teleport slide. Same check in the terminal:
     type `⊻` at the REPL once.
   - **Font size ≥ 24 pt**, monospace. Stage lighting washes out small
     text far worse than a laptop screen suggests — err large (28–32 pt
     is safer than 24 if the venue allows it).
   - **Light background, dark text.** Counter-intuitive next to the
     deck's deliberately dark theme, but under bright stage/projector
     lighting a light terminal with high-contrast dark text reads better
     from the back of the room than white-on-black, which tends to bloom
     and wash out. Use the terminal app's default light profile (e.g.
     macOS Terminal.app "Basic", GNOME Terminal's light preset).
   - Turn OFF terminal bell, autocomplete popups, and any prompt
     decoration wider than `julia> ` (a fancy PS1/starship prompt eats
     the ↑-recall's visual real estate and can wrap the pre-baked
     numbers awkwardly).

5. **Window layout.**
   - Browser: fullscreen (`F` in the deck, or the OS fullscreen
     shortcut) showing `talk.html`. The stage element sizes itself to
     `min(100vw, 177.78vh)` × `min(56.25vw, 100vh)` — on an exact 16:9
     display (e.g. 1920×1080) it fills the screen edge-to-edge with no
     letterboxing; on anything else (16:10 laptop panels, ultrawide
     projectors) there will be black bars and the stage sits inset.
   - Terminal: a **separate real window**, physically dragged to overlay
     the deck's terminal band — the permanent dark strip at the bottom
     of the stage (26cqh of stage height, with a grey traffic-light trio
     top-left and a faint "live terminal" caption). The band is a
     visual target, not a programmatic hook: with the deck fullscreen at
     1920×1080 the band occupies roughly `y ∈ [799, 1080]` (26% of
     1080px ≈ 281px), full width. Drag the terminal window to that
     rectangle by eye — the band's top hairline and grey dots make the
     alignment easy to see. Optional automation on Linux
     (`wmctrl`/`xdotool`, both already usable on this machine):
     ```bash
     wmctrl -r "Terminal" -e 0,0,799,1920,281
     ```
     adjust the window-title match and numbers to the actual venue
     resolution — **verify this at the venue**, not from a guess made at
     home; projector resolutions vary and letterboxing math changes with
     it.
   - Do this BEFORE the talk starts, and re-verify it after any
     projector-resolution renegotiation (common when a venue's AV switches
     inputs between speakers).

6. **Resolution notes.** Ask the AV team the actual output resolution in
   advance if possible. If it isn't exactly 16:9, the deck still works
   (it letterboxes), but the terminal-overlay math in step 5 needs
   redoing for that aspect ratio. Bring a laptop-only rehearsal photo of
   the correctly-aligned layout as a reference to redo it quickly.

---

## (b) Backstage warm-up procedure

Do this **immediately before walking on stage** — not hours before (the
machine may sleep/idle and cool caches) — but with enough buffer (10–15
min) that a surprise (e.g. a stale `demoenv`) doesn't become a crisis.

1. Open a terminal, position it (§a.5), set env vars **before** starting
   Julia (`LIBORKAN_PATH` is read in Sturm's `__init__` — setting it
   after `using Sturm` has already run in that session does nothing):
   ```bash
   export OMP_NUM_THREADS=16
   export LIBORKAN_PATH=/home/tobiasosborne/Projects/orkan/cmake-build-release/src/liborkan.so
   cd /home/tobiasosborne/Projects/Sturm.jl
   julia --project=talks/juliacon-2026/demoenv
   ```

2. At the `julia>` prompt:
   ```julia
   include("talks/juliacon-2026/warmup.jl")
   ```
   Expected timeline (all eagerly printed, per-stage, as it happens —
   the screen should never sit blank):

   | stage | expected |
   |---|---|
   | env checks | instant |
   | `using Sturm` | fast |
   | `using Bennett` | ~1 s |
   | define f/dj_const/dj_bal/deutsch_jozsa/teleport | instant |
   | warm `reversible_compile(f, Int8)` | ~0.2 s |
   | warm FIRST `simulate` call | **~2.8 s (JIT)** — expected, don't worry |
   | warm `verify_reversibility` | ~0.2 s |
   | warm 23-gate `reversible_compile` | ~0.2 s |
   | warm mirror-equality check | ~60 ms |
   | warm `controlled` + 2× `simulate` | ~0.3 s |
   | warm FIRST `oracle()` call (dj_const) | **~20.8 s COLD** — the big one, expected |
   | warm `deutsch_jozsa(dj_bal, ...)` | ~2.1 s (now warm) |
   | warm 200-shot teleport probe | ~0.25 s |

   Total ≈ 30 s. Every stage **asserts its expected value** (f(5)=41,
   reversibility, the mirror equality, `cc`'s two truth-table rows, DJ
   `true`/`false`, the 200-shot probe): a ✅ means "produced the number
   the deck's pre-baked transcript claims", not merely "didn't throw".
   On mismatch the script prints a loud ❌ with the actual value and
   exits(1) — `STAGE READY` is never printed. If any stage errors or
   asserts instead of timing out slowly, STOP — do not walk on stage
   with a broken session. Diagnose now (most likely: stale `demoenv`,
   wrong env var, or a rebuilt-but-not-restarted `liborkan.so`). Re-run
   `include(...)` in a fresh `julia` process after fixing — the script
   is idempotent (redefinitions are harmless).

3. **Retype the nine live lines once**, in the exact REVERSE-stage order
   `warmup.jl` prints at the end, pressing Enter after each. This is the
   step that actually populates REPL history — `include()` does not.
   `warmup.jl` has already bound `c`, `c1` and `cc` to the warm objects,
   so every seeding line executes cleanly even though the lines that USE
   them are retyped before the lines that DEFINE them. All nine are warm,
   so retyping costs no visible time.

   Reverse-stage order still buys recency (each beat's line is the most
   recent match for its own prefix) but it does **not** buy a fixed
   ↑-count: running a recalled line appends it to history, so any count
   you memorise drifts by one after every beat, and the optional s12 beat
   shifts everything after it. **Recall by prefix, not by count** — see
   §c. Rehearse the prefixes backstage until they are reflex.

4. **Ctrl-L** to clear the visible screen. (History is untouched — only
   the visible scrollback is cleared. Do this last, right before opening
   the deck, so the terminal looks pristine when the band's real window
   overlay is exposed.)

5. Switch to the browser, confirm `talk.html` is open at `#s0` (Home
   key if not), confirm fullscreen. You are ready.

---

## (c) The four live beats

Every command below is warm and already in REPL history (per §b.3). On
stage, recall it **by prefix**: type the 2–3 characters in the "recall"
column, press **↑** (Julia's prefix history search jumps to the most
recent line starting with what you typed), **read the line on screen**,
press Enter. Never type from scratch on stage, and never count ↑ presses
— counts drift as soon as you run anything (§b.3).

**Backup recall, works for every beat:** **Ctrl+R**, type a distinctive
substring (`dj_bal`, `false, false`, `gates`), accept the match, check
the line, run it. Rehearse both backstage so the accept-vs-execute
keystroke of your build is muscle memory.

Prefix notes: the trailing space in `c = ` is what skips `c1 = …` and
`count(…)`; `Stu` matches both s13 lines, so use Ctrl+R for the second
one rather than pressing ↑ twice and hoping.

| Slide | Recall (type → ↑) | Command(s) | Expected output | Timing | Say while it runs |
|---|---|---|---|---|---|
| **s2** — "The answer, immediately" | `f(x` then `c = ` | `f(x::Int8) = x*x + Int8(3)*x + Int8(1)` then `c = reversible_compile(f, Int8)` | (silent) then `ReversibleCircuit: 482 gates (NOT=14, CNOT=300, Toffoli=168) · depth 89 · 249 ancillae` | ~0.2 s warm | "That's an ordinary Julia function. That's its LLVM IR turned into Toffolis. Nothing on this screen is a quantum library. The `Int8(3)` is Julia promotion, not ceremony." |
| **s7** — "The theorem is a for-loop" | `c1` then `gs` | `c1 = reversible_compile(x -> x + UInt8(1), UInt8; bit_width=3, add=:ripple, fold_constants=true)` then `gs = c1.gates; gs[14:23] == reverse(gs[1:10])` | `… 23 gates (NOT=6, CNOT=15, Toffoli=2) …` then `true` | ~0.2 s + ~60 ms | OPEN IN SILENCE first — let the SMIL construction animation run ~5 s before speaking at all. Then: "Every gate is its own inverse — Bennett's 1973 theorem is a for-loop with a negative step. And it's a doctest: CI fails if the theorem does." |
| **s11** — "I never wrote a quantum gate" | `cc`, `simulate(cc, t`, `simulate(cc, f` | `cc = controlled(reversible_compile(x -> !x, Bool))` then `simulate(cc, true, false)` then `simulate(cc, false, false)` | (silent), `true`, `false` | ~0.3 s total | Terminal first: the three recalled lines, proving `cc` behaves as a controlled-NOT. THEN drive the on-slide `entangle` component (→/Space, 7 consumed advances — the deck's own live two-branch statevector, running the SAME 20-gate compiled circuit in the browser): "the deck is running the compiled circuit right now." One more advance reveals the headline. Pause three full seconds after saying "I never wrote a quantum gate." This is the signature moment — do not rush it. 10:00 hard checkpoint lands here. |
| **s13** — "The loop closes: oracle(f, x)" | `Stu` then Ctrl+R `dj_b` | `Sturm.eager(18) do _; deutsch_jozsa(dj_const, Val(2)); end` then `Sturm.eager(18) do _; deutsch_jozsa(dj_bal, Val(2)); end` | `true`, `false` | ~2.1 s each, warm | "Here's the whole talk in five lines. `f` is the same ordinary-function idea we compiled at 0:35. One query each." If Orkan misbehaves here: press D, keep walking — do not debug live. |

**Conditional 5th beat — s12, "Teleportation, zero gates"** (band:
shadow, not one of the four LIVE slides — normally shown via `D`).
If, and only if, you are AHEAD of the clock at s12: run it live instead.
Retype `count(_ -> teleport_ok(), 1:200)` as a tenth history line (it
was warmed in §b.2; recall it with prefix `cou`) → expect `200`,
~0.25 s. Otherwise leave this one as shadow-only; press D and narrate
over the pre-baked transcript.

---

## (d) Fallback drill

**The 10-second rule.** If a live command has not returned within
~10 seconds of its expected timing in the table above, or errors, STOP.
Do not retype it, do not read the stack trace aloud, do not diagnose on
stage. You have exactly one move: press **D**.

- **Key D — shadow output, per live slide.** Every live-band slide
  (s2, s7, s11, s13) and s12 carries a `<template class="shadow-term">`
  with the exact pre-baked, verified transcript for that beat. Pressing
  D types it into the terminal band with a typewriter effect (D again
  clears it). It is not a "simulation" caveat to mention out loud — it
  is the same numbers the real command would have produced; narrate
  over it exactly as written in §c, present tense, no hedging.
- **Key 0 — recorded-run fallback.** If the terminal itself is
  unusable (Orkan crashed the process, the machine froze, the window
  layout is wrecked) rather than just one slow command: press **0** to
  jump straight to `#fallback`, a full-slide recorded demo run
  (`demo.cast`/`demo.svg`), captioned "recorded run — the live machine
  is having a moment." Narrate over it the same way. Press **B** to
  return to the last linear slide once past the trouble spot.
- **Known behavior — reverse navigation resets components.** Stepping
  **Left** back over an interactive component (`costbars`, `entangle`,
  `stepper`) resets that component's consumed steps in ONE keypress —
  it does not un-step gate by gate. So a single ← on s8/s11/#stepper
  puts the component back to its start; to show it again you simply
  advance again (→/Space) through its steps. Related: the stepper's
  on-slide **⟲ run all** button advances the component's internal state
  without the engine knowing, so the engine's step count and what you
  see can disagree afterwards. **Don't mix ⟲ run all with
  arrow-stepping mid-demo** — pick one for the duration of that slide
  (arrows on stage, ⟲ only if you are showing the autoplay in Q&A).
  Neither is a failure; both look like one if it surprises you live.
- **Never debug, never apologize.** No "sorry", no "let me just—", no
  visible troubleshooting. The moment a live command misbehaves, the
  talk's on-screen state should look BETTER within two seconds (shadow
  transcript or recorded slide), not worse. The audience forgives a
  smooth pivot; they remember a stalled REPL prompt and an apology far
  longer than either.

---

## (e) Timing checkpoints and the shed list

Timer HUD (key `T`) checkpoints, turns `--gold` when behind, `--red`
when >30 s behind:

| Checkpoint | Slide | Budget |
|---|---|---|
| 1 | s3 | by 2:00 |
| 2 | s10 | by 8:30 |
| 3 | s11 | by 10:00 |
| 4 | s16 | by 14:00 |

**Shed list, in drop order** (cut the first item first; only move to the
next if still behind after cutting the previous one):

1. **s4 build-2**, the Julia-1.12-reflection-stack aside (`InteractiveUtils._dump_function` / `Base._which` / `specialize_method`). Explicitly marked in the spec as the first thing to cut — small, ~10 s.
2. **s9's Carmack hostile-review aside** (the `Pkg.test()` 4m06-vs-90s war story) — drop the aside, keep the false-path-sensitization story itself (50 s budget either way).
3. **s12 in full** (OPTIONAL-A, ~40 s) — skip the whole slide (teleportation-in-zero-gates) if behind; only ever ADD the live 200-shot variant (§c conditional beat) if you are instead ahead.
4. **s14 panel (b)**, the QECC-as-HOF `ctrl(Protect(enc))` MethodError panel (~25 s) — bridge straight from panel (a) ("the marginals lied") to s15 with: "error correction is a higher-order function on channels — and here's what happens when you try to control one."
5. **s16, down to two lines.** Absolute last resort: if time is genuinely short, say only "That word 'given' has been doing the work for forty years. In Julia, it's a function call." and let the slide (unchanged code panel, all six badges lit) carry the rest in silence.

---

## (f) Q&A ammunition

Reachable only by hash (no dedicated hotkey except `S`) — have these
hashes memorized or bookmarked in the address bar, since the engine maps
number keys nowhere and only `0`/`S` are assigned:

| Key / hash | Backup slide | One-line answer |
|---|---|---|
| **S** → `#stepper` | "Q&A: 23 gates, one at a time" | The `stepper` component walks all 23 gates of the increment circuit one at a time (arrow-driven, or `⟲ run all` at 6 gates/s), with compute/copy/uncompute phase bands and a live ancilla-state readout — "here's gate 1 through 23, and the ancillae really do come back to zero." |
| `#pebbling` | "Q&A: the space–time dial" | Bennett strategies trade time for space via Knill's pebbling recursion, `F(n,s) = min_m F(m,s)+F(m,s−1)+F(n−m,s−1)`, finite iff `n ≤ 2^(s−1)` — six pluggable `BennettStrategy` subtypes let you dial where you sit on that curve. |
| `#vmtape` | (BennettVM history tape) | BennettVM's `unrun!` walks back through a three-layer tape — injective steps log nothing, min-cut deltas borrow Enzyme's idea, checkpoint+replay borrows `rr`'s — so a long forward-run loop doesn't have to store every intermediate step to reverse exactly. |
| `#numbers-full` | (full benchmark table) | The full table, warts included: the QCLA/QROM/shadow-memory wins, the honest SHA-256 loss (1,632 vs 683 Toffoli, ~2.4×), the persistent-map surprise (naive linear scan beats a purpose-built structure 2,400× at depth 128), and the precompile-workload TTFX win (20.7 s → 0.99 s). |

Return to the linear deck from any backup with **B**.

---

## Quick reference — all engine keys

`→` / `Space` / `PgDn` advance · `←` / `PgUp` reverse · `Home`/`End` ·
`F` fullscreen · `?` help overlay (Esc closes) · `D` shadow terminal
toggle · `T` timer HUD toggle (`Shift+T` reset) · `N` speaker notes
toggle · `0` → `#fallback` · `S` → `#stepper` · `B` return from a backup
· click right/left thirds of the stage = next/prev.
