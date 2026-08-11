# DECK-SPEC — "Given an Oracle for f" (JuliaCon 2026, 15 min)

This file is the CONTRACT for the deck build. Agents implement EXACTLY this.
Where this spec conflicts with the background brief
(`/tmp/claude-1000/-home-tobiasosborne-Projects-Sturm-jl/3a44604b-e4e8-4509-8819-66a04b10e664/scratchpad/talk-brief.md`),
THIS SPEC WINS. The brief is for flavor/context only.

## Files (all under talks/juliacon-2026/src/ unless noted)

| File | Owner | Contents |
|---|---|---|
| `frame.html` | agent FRAME | Full HTML document: `<head>` + all CSS + stage shell + chrome (badge rail, terminal band, help overlay, timer HUD) + literal markers `{{SLIDES}}`, `{{ENGINE_JS}}`, `{{COMPONENTS_JS}}`, `{{CIRCUITS_JSON}}` where content is spliced |
| `engine.js` | agent FRAME | Deck engine (nav, builds, hash, still, timer, notes, shadow terminal, SMIL hooks, component lifecycle) |
| `slides-a.html` | agent SLIDES-A | `<section>` elements for slides s0–s8, concatenated, nothing else |
| `slides-b.html` | agent SLIDES-B | `<section>` elements for slides s9–s16 + hidden backups, nothing else |
| `components.js` | agent COMPONENTS | The three interactive components + registry |
| `circuits.json` | DONE (exists) | Real extracted gate lists (see §Components) |
| `../talk.html` | build.py (orchestrator) | The final single self-contained file |

Do not write files owned by another agent. Fragments must not contain
`<html>`, `<head>`, or `<body>` tags (frame.html owns the document).

## Design tokens (single-theme, deliberately dark; commit fully — no media queries)

```css
:root{
  --bg:#0E1116;          /* stage ground — blue-biased near-black */
  --panel:#151A22;       /* raised panels */
  --code-bg:#10151C;     /* code blocks */
  --band:#0A0D11;        /* terminal band (darkest) */
  --ink:#E8E6E1;         /* warm off-white body text */
  --ink-strong:#FFFFFF;
  --muted:#8A93A6;       /* blue-gray muted */
  --line:#232A35;        /* hairlines */
  /* Julia brand, lifted for legibility on the dark ground: */
  --purple:#B385D6;  --green:#5CBD6A;  --red:#E06C5F;  --blue:#6B8FE8;
  /* raw brand (only inside light figure cards): #9558B2 #389826 #CB3C33 #4063D8 */
  --gold:#E0B45F;        /* the "Given" highlight + timer amber */
}
```
Every color in the deck comes from these tokens — no ad-hoc hex values.

- Body/display type: `system-ui, -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif`.
  Display headings weight 700, `letter-spacing:-0.015em`, `text-wrap:balance`.
- Code: `"JuliaMono", ui-monospace, "Cascadia Code", "SF Mono", Menlo, Consolas, monospace`
  (JuliaMono picked up if installed locally; graceful fallback).
- The oracle equation and physics quotes: `Georgia, "Times New Roman", serif`, italic —
  the one serif voice in the deck ("paper" voice).
- Sizing in container-query units (`cqh`/`cqw`) exactly like a 1280×720 stage:
  frametitle 4.2cqh; body text 3.0cqh; lead 3.4cqh; small 2.3cqh; code 2.5cqh
  (code may drop to 2.1cqh when >10 lines). Line-height 1.45–1.55.
- Code blocks: `--code-bg` panel, 1px `--line` border, radius 10px, padding
  2.2cqh; syntax highlighting is MINIMAL two-tone: comments in `--muted`,
  strings/keywords MAY use `--green`/`--purple` sparingly; never rainbow.
  Mark emphasized lines with `<mark>` → background rgba of `--gold` at 12%,
  no color change of text.

## Stage geometry

- Letterboxed 16:9 stage exactly like: `#deck` fixed inset 0 flex-center on
  near-black backdrop; `#stage` width `min(100vw,177.78vh)`, height
  `min(56.25vw,100vh)`, `container-type:size`, background `--bg`.
- **Terminal band**: a permanent strip at the bottom of the stage,
  height 26cqh, background `--band`, top border 1px `--line`. Content:
  a faint traffic-light trio (grey dots) top-left, tiny caption
  `live terminal` in `--muted` 1.6cqh bottom-right. During the talk the
  REAL terminal window physically overlays this strip. The engine renders
  shadow-terminal output INTO this band (see keys). Slides NEVER put
  content into the band area: `.slide` gets `padding-bottom:29cqh`.
- **Badge rail**: right edge, vertical flex, six chips, each 5.2cqh circle +
  1.7cqh label under it. Chips: ①…⑥ with labels
  `reflection` / `lowering table` / `semantics` / `reflection stack` /
  `types=physics` / `dispatch refuses` (②/③ shortened from `dispatch=…` after
  render testing showed mid-word wraps in the rail). Unlit: `--line` border, `--muted` text.
  Lit: filled with (in order) --purple, --blue, --green, --purple, --gold, --red;
  ink-strong text; subtle 300ms transition + one-time 600ms glow when first lit.
  Lever→slide mapping (lit when slide index ≥ introducing slide, engine-computed):
  ①→s4, ④→s4 (second build), ②→s5, ③→s6, ⑤→s12, ⑥→s15.
- Slide number bottom-right ABOVE the band (`current/16`), 1.8cqh `--muted`.
- Progress hairline: 2px `--purple` bar across the very top of the stage,
  width = slide progress fraction.

## Slide markup contract

```html
<section class="slide" id="s4" data-title="① The compiler is a library"
         data-band="live"        <!-- live | shadow | off  (band caption state) -->
         data-notes="Speaker note text …">
  <h2 class="frametitle">① The compiler is a library<span class="rule"></span></h2>
  <div class="body"> …
    <div class="build">…appears on first advance…</div>
    <div class="build">…second advance…</div>
  </div>
  <template class="shadow-term">
julia&gt; c = reversible_compile(f, Int8)
ReversibleCircuit: 482 gates (NOT=14, CNOT=300, Toffoli=168) …
  </template>
</section>
```

- `.build` elements advance in document order on →/space before the deck
  moves to the next slide. `.build.shown` = visible. Transition: opacity +
  translateY(1.2cqh), 400ms.
- `data-band="live"`: band caption shows `● LIVE` in `--green` pulsing softly.
  `shadow`: caption `shadow output — press D`. `off`: plain band.
- `<template class="shadow-term">`: plain text, rendered by the engine into
  the band with a **typewriter effect** (~24 chars/frame; instant when
  `prefers-reduced-motion`) when the speaker presses **D**. Press D again to
  clear. Lines starting with `julia>` render the prompt in `--green`.
- Hidden/backup slides: `<section class="slide backup" id="fallback">` etc.
  NOT in the linear order; reachable only by hash or hotkey. Backups:
  `#fallback`, `#pebbling`, `#vmtape`, `#numbers-full`, `#stepper`.
- Interactive mounts: `<div class="component" data-component="costbars"></div>`.

## Engine API + keys (engine.js — agent FRAME)

- `window.Deck = { idx, order:[ids], go(i), enterHooks }`. On slide enter:
  update badge rail, band state, hash (`#s4` / `#fallback`), slide counter,
  progress bar; call `DeckComponents[name].onEnter(el)` for components on
  that slide, `.onLeave(el)` for the departed one; restart SMIL clocks on
  the entered slide: for each inline `<svg>` with class `smil`, call
  `svg.setCurrentTime(0)` (guard with try/catch).
- Keys: `→`/`Space`/`PgDn` advance build-then-slide; `←`/`PgUp` reverse;
  `Home`/`End`; `F` fullscreen; `?` help overlay (Esc closes); `D` shadow
  terminal toggle; `T` timer HUD toggle; `N` speaker-notes overlay toggle
  (bottom-left, 2.0cqh, `--muted`, max 3 lines); `0` jump to `#fallback`;
  `S` jump to `#stepper`; `B` (from a backup) return to the last linear
  slide. Number keys map nowhere else. Click right/left thirds of the
  stage = next/prev.
- Build-step handoff to components: if the current slide has a component
  whose `onStep(el, k)` returns `true`, the component CONSUMES the advance
  (used by costbars & stepper); otherwise the engine advances builds/slides.
- `?still` query: all builds `.shown`, components jump to final state
  (`onStill(el)`), timers off, transitions 0ms — for screenshots.
- Timer HUD (T): elapsed mm:ss top-left, 1.9cqh, `--muted`; turns `--gold`
  when behind checkpoint, `--red` when >30s behind. Checkpoints:
  s3 by 2:00, s10 by 8:30, s11 by 10:00, s16 by 14:00. Timer starts on
  first advance from s0 (not on load). Reset: Shift+T.
- Hash routing on load; `hashchange` listener.
- `prefers-reduced-motion`: kill typewriter animation (instant), build
  transitions to 0ms, no badge glow.
- Print CSS: each `.slide` (including backups, at the end) on its own page,
  builds shown, stage colors preserved
  (`print-color-adjust:exact`), and a rule forcing SMIL-animated elements
  visible: `@media print { svg.smil [opacity], svg.smil * { opacity:1 !important } }`.

## Components (components.js — agent COMPONENTS)

Registry: `window.DeckComponents = { name: {mount(el), onEnter(el), onLeave(el), onStep(el,k)→bool, onStill(el)} }`.
Engine calls `mount` once on load for every `[data-component]`.
`{{CIRCUITS_JSON}}` is spliced into frame.html as
`<script id="circuits" type="application/json">…</script>`; components read
`JSON.parse(document.getElementById('circuits').textContent)`.
Gate JSON schema: `{"t":"NOT","target":n}`, `{"t":"CNOT","control":c,"target":n}`,
`{"t":"TOF","c1":a,"c2":b,"target":n}`. Wires are 1-based.

### 1. `costbars` (slide s8) — the rescaling log chart
- Three horizontal bars, revealed by consumed advances (onStep):
  step1: `Int8  x*x + 3x + 1` → **482**;
  step2: `Float64  x + x` → **63,058**;
  step3: `Float64  sin(x)` → **11,027,852**.
- On each reveal the AXIS RESCALES (600ms ease) so the previous champion
  visibly shrinks while the new bar sweeps in — that's the gasp mechanic.
  Log10 scale; axis ticks 10⁰ 10² 10⁴ 10⁶ 10⁸ as faint labels; single hue
  (`--blue` fills, 4px rounded data-end), value as direct label in `--ink`
  `tabular-nums` at bar end, bar label left in `--muted`. No gridlines, no
  legend (single measure). Sub-caption under chart (appears with step3):
  `measured 2026-08-11 · 1,629,722 NOT · 7,059,276 CNOT · 2,338,854 Toffoli · ≤1 ULP vs Base.sin`.
- After step3 a fourth consumed advance reveals the honesty footer row
  (slide provides it as a normal `.build` — costbars consumes only 3 steps
  then returns false).

### 2. `entangle` (slide s11) — the *real* two-branch statevector
- Uses `circuits.controlled_not` (20 gates, 50 wires, ctrl wire 50,
  input x = wire 1, output bit = wire 42). Truth: reversible gates are
  permutations, so a state prepared as (|ctrl=0⟩+|ctrl=1⟩)/√2 ⊗ |x=0,anc=0⟩
  is ALWAYS exactly two computational branches with amplitudes 1/√2.
  Simulate the two branches as two 50-entry bit arrays; apply each gate to
  both branches.
- Visual: two "branch cards" side by side, each showing chips for
  `ctrl`, `x`, `out` (wires 50, 1, 42) plus an `ancillae` pill showing
  `Σ=0`/`Σ=k` (count of set ancilla bits, wires 9–41 — from the JSON
  ancilla_wires). Between them a center column: gate counter `k/20`, the
  current gate's name, amplitude labels `1/√2` on each card, and a norm
  readout `‖ψ‖ = 1.0000000000`.
- Interaction: onStep consumes advances: step1 prepares (cards appear,
  branch B's ctrl chip = 1, caption `H on the control — a superposition of
  two classical worlds`); each further advance runs gates in chunks of 5
  with a fast animated flip of changed chips (5 consumed steps: 5,10,15,20);
  final consumed step: the two cards' kets typeset as
  `|ctrl,x,out⟩ = |0,0,0⟩` and `|1,0,1⟩`, ancilla pills flash `Σ=0`,
  and the verdict line appears: `(|0,0,0⟩ + |1,0,1⟩)/√2 — entangled`,
  with `entangled` in `--red`. Reduced-motion: chips update instantly.
- The point (put as small caption, always visible): `the deck is running the
  compiled circuit — 20 gates on both branches, live in your browser`.

### 3. `stepper` (backup slide #stepper) — the 23-gate walkthrough
- Uses `circuits.x_plus_1` (23 gates, 16 wires; input [1,2,3] LSB-first,
  output wires from JSON, 10 ancillae). Draw with JS into an inline SVG:
  16 horizontal wires (thin `--line` strokes, labels x₁..x₃ / out / anc in
  `--muted` 1.6cqh), gates as columns: NOT = ⊕ ring in `--green`,
  CNOT = dot+⊕ with vertical stem in `--blue`, Toffoli = two dots+⊕ in
  `--purple`. Current-gate column highlighted with a `--gold` underglow.
- State: wire bit values as filled/hollow dots at the RIGHT edge, updated
  per step; input preset x=3 (binary 011).
- onStep: each advance executes ONE gate (arrow-key–driven). Three phase
  bands tinted behind columns: compute (1–10), copy (11–13), uncompute
  (14–23) with tiny phase labels. After gate 23 a final consumed step shows:
  `out = 4  ·  every ancilla back to 0  ·  gs[14:23] == reverse(gs[1:10])`.
  Also a `⟲ run all` on-slide button (mouse) that autoplays at 6 gates/s.
- onStill: jump to end state.

## SVG assets (spliced by build.py — do NOT inline them yourselves)

Markers available inside slide fragments:
- `{{SVG:pipeline}}`   → Bennett pipeline diagram (960×250, light card)
- `{{SVG:circuit23}}`  → static 23-gate circuit (912×534, light card)
- `{{SVG:bennett}}`    → SMIL-animated construction (912×534, light card).
  build.py adds class `smil` to its root for the engine's setCurrentTime(0).
- `{{IMG:democast}}`   → `<img>` with base64 data-URI of the animated
  terminal recording (960×776) — used ONLY on `#fallback`.
The three light-background SVGs must be wrapped by the slide author in
`<figure class="figure-card">` (white card, radius 12px, padding 1.2cqh,
subtle shadow) — they were authored on `#fbfbfe` and stay that way; the
card frames them as "paper figures" on the dark stage.

## THE SLIDES (content is normative; notes = speaker script summary)

Numbers in **bold** are verified: measured on this machine 2026-08-11 or
pinned in the repos' committed docs. Do not alter them.

### s0 — Title  (band: off)
- Eyebrow: `JuliaCon 2026`. Title (display, ~7cqh): **Given an Oracle for *f***
  (the word "Given" in `--gold`; *f* serif italic).
- Subtitle: `Sturm.jl · Bennett.jl · BennettVM.jl` with the three package
  roles in one muted line: `a quantum language · a reversible compiler · a reversible VM`.
- Footer: Tobias J. Osborne — Leibniz Universität Hannover · `github.com/tobiasosborne`.
- Four Julia-dot ornament (小 circles in the four raw brand colors) under the title.
- notes: "Terminal already warm, docked bottom. Say nothing about it."

### s1 — The word  (band: off)
- Center, serif italic, huge (~6cqh): `O_f |x⟩|y⟩ = |x⟩|y ⊕ f(x)⟩`
  (hand-set with spans/sub/sup; no MathJax).
- build 1: caption fades in below (3.4cqh): `“Given an oracle for f …”` with
  **Given** in `--gold`.
- build 2: muted row: `Grover · Shor · Deutsch–Jozsa · phase estimation · QSVT`.
- notes: "Every quantum algorithm starts here. You don't need the equation —
  only the word under it. *Given.* That word is where quantum software dies.
  f is ordinary code — x²+3x+1, SHA-256, your loss function — and every
  framework answers it with a circuit-drawing API and good luck."

### s2 — The answer, immediately  (band: live) — LIVE BEAT 1
- Top code panel (the ONLY content besides thesis):
  ```julia
  f(x::Int8) = x*x + Int8(3)*x + Int8(1)

  c = reversible_compile(f, Int8)
  ```
- build 1 (shadow of the live result, static, muted):
  `ReversibleCircuit: 482 gates (NOT=14, CNOT=300, Toffoli=168) · depth 89 · 249 ancillae`
- build 2 (thesis, display 4.6cqh, `--ink-strong`):
  **Every Julia function is already a quantum gate.**
  sub (3cqh, muted): *you just have to run it backwards.*
- shadow-term: the transcript above with the full printed summary.
- notes: "TYPE IT LIVE (↑+Enter). ~0.2 s warm — **measured**. 'That's an
  ordinary Julia function; that's its LLVM IR turned into Toffolis. Nothing
  on this screen is a quantum library.' The Int8(3) is Julia promotion,
  not ceremony."

### s3 — Three packages, one arrow  (band: off)
- `{{SVG:pipeline}}` in a figure-card, full width.
- Under it one line, mono, 2.6cqh:
  `f(x) → Bennett.jl → NOT/CNOT/Toffoli → controlled(·) → Sturm.jl: oracle(f, x)`
  and a muted fork note: `↳ target = :reversible_vm → BennettVM.jl`.
- build 1: the claim (3.2cqh): `Julia is uniquely placed to be a quantum
  programming language — I won't argue it abstractly. Watch for six levers.`
  (badge rail pulses once, all six chips outline-flash).
- notes: "Bennett gets the next seven minutes. Sturm is the language it
  feeds. BennettVM gets forty-five seconds and earns them."

### s4 — ① The compiler is a library  (band: off; lights lever 1, then 4)
- Code (verbatim, src/extract/entry.jl):
  ```julia
  ir_string = sprint(io -> code_llvm(io, f, arg_types;
                         debuginfo = :none, optimize, dump_module = true))
  mod = parse(LLVM.Module, ir_string)
  ```
- Line under (3cqh): `A runtime function value in — the compiler's IR out.
  In-process. While f is still callable.`
- build 1 (muted): `C++: write a clang plugin. Python: there is no IR.
  Julia: two lines, and it works for anything that reaches LLVM.`
- build 2 (lights lever ④; small panel): `Julia 1.12 outlines slow paths —
  some closures have no .instance to compile. Fix: rebuild
  InteractiveUtils._dump_function from Base._which + specialize_method +
  typeinf_code. The reflection stack is just more Julia you can call.`
- notes: "Lever ① — this is the slide the whole talk stands on. The build-2
  aside is the FIRST thing to cut if behind."

### s5 — ② Dispatch is the lowering table  (band: off; lights lever 2)
- Code:
  ```julia
  _lower_inst!(ctx, inst::IRBinOp,  …) = lower_binop!(…)
  _lower_inst!(ctx, inst::IRICmp,   …) = lower_icmp!(…)
  _lower_inst!(ctx, inst::IRSelect, …) = lower_select!(…)
  _lower_inst!(ctx, inst::IRPhi,    …) = lower_phi!(…)
  # … 13 instruction types, 13 methods …
  _lower_inst!(ctx, inst::IRInst, …) =
      error("no lowering for $(typeof(inst))")
  ```
- build 1: `No switch. No visitor. Adding an instruction = adding a method —
  from any package. The catch-all's only job is to be loud.`
- notes: "In a C++ compiler this is a 400-case switch."

### s6 — ③ The entire simulator  (band: off; lights lever 3)
- Three lines alone, code 2.6cqh (verbatim src/simulator.jl:1–3):
  ```julia
  @inline apply!(b, g::NOTGate)     = (b[g.target] ⊻= true;                          nothing)
  @inline apply!(b, g::CNOTGate)    = (b[g.target] ⊻= b[g.control];                  nothing)
  @inline apply!(b, g::ToffoliGate) = (b[g.target] ⊻= b[g.control1] & b[g.control2]; nothing)
  ```
- build 1 (3.2cqh): `This is not an excerpt. This is the simulator.`
  muted sub: `union-splitting on three concrete gate types — a 28k-gate
  circuit simulates with <200 KiB allocated.`
- notes: "When someone asks what the gate set is, I don't have a spec
  document. I have this file."

### s7 — The theorem is a for-loop  (band: live) — LIVE BEAT 2 + ANIMATION
- Layout: left 55% `{{SVG:bennett}}` in figure-card (SMIL loops; engine
  restarts its clock on slide enter); right 45% code:
  ```julia
  append!(all_gates, lr.gates)             # compute
  _emit_copy_gates!(all_gates,             # copy the answer out
                    lr.output_wires, copy_wires)
  for i in length(lr.gates):-1:1           # uncompute
      push!(all_gates, lr.gates[i])
  end
  ```
- build 1 (the punchline, 3.4cqh): `Every gate is its own inverse — Bennett's
  1973 theorem is a for-loop with a negative step.`
- build 2 (mono, `--green`): `julia> gs[14:23] == reverse(gs[1:10])` ↵ `true`
  with muted tag `— and it's a doctest: CI fails if the theorem does.`
- shadow-term:
  `julia> c1 = reversible_compile(x -> x + UInt8(1), UInt8; bit_width=3, add=:ripple, fold_constants=true)` /
  `… 23 gates (NOT=6, CNOT=15, Toffoli=2) …` /
  `julia> gs = c1.gates; gs[14:23] == reverse(gs[1:10])` / `true`
- notes: "OPEN IN SILENCE — let the animation run ~5s before speaking.
  Cost law: 2× gates + one ancilla per output bit. Then the live equality.
  Backup stepper on key S if Q&A wants gate-by-gate."

### s8 — What arithmetic costs  (band: off) — component `costbars`
- `<div class="component" data-component="costbars"></div>` fills the body.
- After the 3 consumed steps, build 1 (the honesty row, small table 2.4cqh):
  `QCLA 32-bit multiply — Toffoli-depth 56 vs 180 schoolbook · QROM T-count
  exactly 4(L−1), width-independent (matches Babbush–Gidney) · shadow-memory
  store 24 CNOT vs a 7,122-gate MUX` then in `--gold`:
  `SHA-256 round: 1,632 Toffoli vs hand-optimized 683 — ~2.4× worse. It's in
  our own benchmark table.`
- notes: "sin costs 5,000× x+x and is still ≤1 ULP. **11,027,852 gates —
  measured this week**, 38.8 s compile. Then the honesty row: 'a benchmark
  table you can't lose in is a marketing document.'"

### s9 — `0.5 + 0.5 == 0.0`  (band: off)
- The failing expression alone, mono 5.5cqh, `--red` equals-sign.
- build 1 (3 short lines): `The datapath is branchless — every path computes,
  always. A subtraction-path condition wire fired on the addition path.
  VLSI has a name for this: false-path sensitization (Bergamaschi, 1992).`
- build 2 (muted): `No published system converts a multi-way φ-node from an
  arbitrary CFG into a correct reversible MUX tree. That part is uncharted.`
- notes: "War story, 50 s budget. Sheddable line: the hostile-review aside
  (Carmack persona caught Pkg.test() at 4m06 vs a claimed ~90 s)."

### s10 — A loop wants an interpreter  (band: off)
- Top line: `Collatz as a circuit (max_loop_iterations = 20):`
  `**14,074 gates · 2,320 Toffoli · 8,868 ancillae**` — muted: `bounded,
  MUX-frozen, convergence-guarded. It works. It's also the wrong shape.`
- Code:
  ```julia
  vm = reversible_compile(collatz_steps, Int64; target = :reversible_vm)
  run!(rs, vm);  unrun!(rs, vm)
  rs.current == rs.initial     # true — bit-for-bit
  isempty(rs.history)          # true — the tape is drained
  ```
- build 1: `“every ancilla returns to zero” becomes isempty(history) — same
  theorem, different data structure.`
- build 2 (one line, muted): `three-layer tape: injective steps log nothing ·
  min-cut deltas (Enzyme's idea) · checkpoint+replay (rr's idea)`.
- notes: "BennettVM's one beat, 45 s. Backup #vmtape if Q&A."

### s11 — I never wrote a quantum gate  (band: live) — LIVE BEAT 3 + `entangle`
- Small code header:
  ```julia
  cc = controlled(reversible_compile(x -> !x, Bool))
  ```
  with muted note `controlled: NOT→CNOT, CNOT→Toffoli, Toffoli→3 Toffoli+ancilla`.
- `<div class="component" data-component="entangle"></div>` (the two-branch
  live simulation; consumes 7 advances).
- build 1 (after component finishes; display 4.4cqh, `--ink-strong`):
  **I never wrote a quantum gate.**
- shadow-term: `julia> simulate(cc, true, false)` / `true` /
  `julia> simulate(cc, false, false)` / `false` /
  `julia> show_ket(apply_as_permutation(cc, plus_control()))` /
  `(|0,0,0⟩ + |1,0,1⟩)/√2    ‖ψ‖ = 1.0`
- notes: "THE SIGNATURE MOMENT. Live: three ↑+Enter lines. Then the deck's
  own sim: 'the deck is running the compiled circuit right now.' THREE-SECOND
  PAUSE after the headline. 10:00 hard checkpoint lands here."

### s12 — Teleportation, zero gates  (band: shadow; lights lever 5)
- The 9-line teleport function verbatim (test/test_m4_views.jl:24-33 —
  in the brief §B5). Code 2.3cqh.
- Right margin annotations (small, muted, arrows): `fair quantum coin` /
  `Bell pair` / `conjugate-basis readout — CONSUMES ψ` / `ordinary
  conditionals — one in the dual view`.
- build 1: aphorism footer (serif italic 2.8cqh):
  `“If your program reads like a circuit diagram, it is wrong.”`
- build 2 (muted, one line): `⊻= mutates — against Julia precedent (#249,
  #3217) and correct here: no-cloning means no caller could expect a value.`
- shadow-term: `julia> count(_ -> teleport_ok(), 1:200)` / `200` /
  `# |+⟩ probe, X-basis readout: 200/200 deterministic — 0.25 s`
- notes: "OPTIONAL-A: sheddable in full (40 s). If kept and ahead of clock,
  run the 200-shot live beat — **measured 0.25 s**."

### s13 — The loop closes: oracle(f, x)  (band: live) — LIVE BEAT 4
- DJ code verbatim (brief §B6, 7 lines).
- build 1 (muted): `oracle(f, x) crosses a weakdep extension — the only file
  in Sturm that names a Bennett type; using Sturm never pays LLVM's
  precompile. Both package seams are the same trick: a Ref{Any}(nothing)
  filled by the downstream package's __init__.`
- shadow-term: `julia> Sturm.eager(18) do _; deutsch_jozsa(dj_const, Val(2)); end` /
  `true` / `julia> Sturm.eager(18) do _; deutsch_jozsa(dj_bal, Val(2)); end` /
  `false` / `# one query each — ~2 s warm`
- notes: "Here's the whole talk in five lines. f is the SAME ordinary
  function idea we compiled at 0:35. Live: two calls, **~2.1 s each,
  measured**. If Orkan misbehaved in the green room: press D, keep walking."

### s14 — Two lessons  (band: off)
- Two panels. (a) `The marginals lied`: `Our first teleport moved the value
  and dropped the phase. Its test passed — output statistics looked fine.
  The fixed one reads 1024/1024 on a probe where the broken one reads ≈512.
  Test the whole channel, not what leaks out of it.`
- (b) `Error correction is a function`:
  ```julia
  Protect(enc)(physical_iid(enc, bit_flip(p)))   # channel in → channel out
  ```
  `pinned two-sided: helps below p = ½, hurts above — a sign-flipped decoder
  passes any one-sided test.`
- notes: "50 s. Panel (b) is sheddable (25 s) — bridge straight to s15 with
  'error correction is a higher-order function on channels — and here's what
  happens when you try to control one.'"

### s15 — The zinger  (band: off; lights lever 6)
- REPL transcript, huge (3.6cqh mono):
  ```
  julia> ctrl(Protect(enc))
  ERROR: MethodError: no method matching ctrl(::Protect{…})
  ```
- build 1 (3.2cqh): `Bădescu–Panangaden: a quantum if has no channel
  semantics. Gavorová et al.: controlled-U cannot be built from black-box U.
  In most frameworks that's documentation. Here it's a MethodError.`
- build 2 (display 4cqh): **The no-go theorem and the method table are the
  same object.**
- notes: "Read the error slowly. This is lever ⑥ and the Sturm thesis in
  one screen."

### s16 — unchanged  (band: off)
- BYTE-IDENTICAL visual of s2's code panel (same f, same compile line), same
  position — plus: all six badges lit in the rail (the frametitle IS the word
  `unchanged`; no separate caption — a caption duplicating the title was
  removed after render review); URLs footer (2.0cqh):
  `github.com/tobiasosborne — Sturm.jl · Bennett.jl · BennettVM.jl · AGPL-3.0`.
- build 1 (the close, display 4.2cqh): `That word “given” has been doing the
  work for forty years.` then `--gold` line: **In Julia, it's a function call.**
- build 2 (2.8cqh, muted): `Ancillae restored to zero. Thank you.`
- notes: "If time is short: say only the last two lines and let the slide
  carry the rest."

### Backups (class="slide backup")
- `#fallback` — `{{IMG:democast}}` full-height in a figure-card, caption
  `recorded run — the live machine is having a moment`. (Key 0.)
- `#pebbling` — Knill recursion `F(1,s)=1 · F(n,1)=∞ · F(n,s)=min_m F(m,s)+
  F(m,s−1)+F(n−m,s−1)` + `finite ⟺ n ≤ 2^(s−1)` + the six BennettStrategy
  names. Title: `Q&A: the space–time dial`.
- `#vmtape` — the L1/L2/L3 table (from brief §D2).
- `#numbers-full` — full benchmark table incl. persistent-map row
  (`linear scan beats Okasaki 2,400× at depth 128`) + suite sizes
  (**692k** Bennett asserts / **27k+** Sturm) + TTFX 20.7 s → 0.99 s.
- `#stepper` — the `stepper` component + title `Q&A: 23 gates, one at a time`.

## Verified-numbers appendix (single source of truth for all agents)

482 (NOT 14/CNOT 300/Toffoli 168), depth 89, Toffoli-depth 36, 249 anc ·
23 gates (NOT 6/CNOT 15/Toffoli 2), 16 wires, 10 anc, depth 9 ·
simulate(c1, 3) = 4 · f(5) = 41 · 63,058 · **11,027,852** (1,629,722 /
7,059,276 / 2,338,854; 38.8 s compile; sin(1.2345) bit-identical) ·
QCLA 56 vs 180 · QROM 4(L−1) · shadow 24 vs 7,122 · SHA 1,632 vs 683 ·
Collatz circuit 14,074 / 2,320 / 8,868 · DJ warm ≈2.1 s, first oracle call
20.8 s cold · teleport probe 200/200 in 0.25 s · wm28 1024/1024 vs ≈512 ·
TTFX 20.7 s → 0.99 s · suites ≈692k / >27k.
