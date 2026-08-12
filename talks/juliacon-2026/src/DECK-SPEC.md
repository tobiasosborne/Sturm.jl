# DECK-SPEC — "Given an Oracle for f" (JuliaCon 2026, 15 min) — v2

This file is the CONTRACT for the deck build. The deck was rebuilt from
scratch in session 107 after the v1 deck was rejected (2026-08-12, direct
user feedback): **too much jargon, inauthentic, smug, exclusive**. The HTML
machinery (stage, engine, terminal band, components, build.py splice) was
kept; the content, structure, and register were replaced.

## Voice rules (normative — check every edit against these)

1. **No jargon without a plain-words translation on the same slide.**
   The oracle equation gets an "in words:" line. Banned unexplained:
   weakdep, Ref{Any}, φ-node, false-path sensitization, Choi, CPTP,
   Stinespring, MUX-frozen. Q&A backups may go deeper — a backup is
   entered because someone asked.
2. **No triumph.** No "zinger", no "signature moment", no "watch for six
   levers", no framework dunking (no toolkit is named unfavourably; the
   circuit-style contrast on s1 is "how most quantum software looks",
   which includes our own first attempt).
3. **Honesty beats impressiveness.** The SHA-256 loss (~2.4× worse than
   hand-tuned) is on a *linear* slide, not hidden. "What's left" (s14) is
   a real list, not a roadmap brag.
4. **Inclusive close.** The talk's thesis is "if you know Julia, you
   already know most of what's here." The audience should leave feeling
   *able*, not impressed-and-excluded.
5. Speaker notes are stage directions, not applause cues.

## Structure (user directive, 2026-08-12)

- **First third — the why (s0–s6):** Sturm.jl design decisions one per
  slide, each paired with the Julia feature that made it work
  ("Why Julia:" is the recurring last build of each decision slide).
- **Second part — Bennett (s7–s13):** the oracle question (s7), why
  reversibility is forced (s8), **Bennett's 1973 result explained in the
  animated slides** (s8 static build-up + s9 SMIL animation), then the
  headline feature: **"You don't have to rewrite your code"** (s10 live),
  scale + honesty (s11 costbars), the quantum lift (s12 entangle), the
  loop closing with `oracle(f, x)` (s13 live).
- **End — what is left (s14–s15):** honest open problems, warm close.

## Files (all under talks/juliacon-2026/src/ unless noted)

| File | Contents |
|---|---|
| `frame.html` | Full HTML document: head + all CSS + stage shell + chrome (terminal band, help overlay, timer HUD, notes, counter, progress hairline) + markers `{{SLIDES}}`, `{{ENGINE_JS}}`, `{{COMPONENTS_JS}}`, `{{CIRCUITS_JSON}}`. The v1 badge rail is REMOVED. |
| `engine.js` | Deck engine (nav, builds, hash, still, timer, notes, shadow terminal, SMIL hooks, component lifecycle). No lever logic. |
| `slides-a.html` | `<section>` elements s0–s7 (part 1 + part 2 opener), nothing else |
| `slides-b.html` | `<section>` elements s8–s15 + backups, nothing else |
| `components.js` | `costbars` (s11), `entangle` (s12), `stepper` (#stepper) — unchanged from v1 |
| `circuits.json` | Real extracted gate lists (unchanged) |
| `../talk.html` | The final single self-contained file (build.py) |

Fragments must not contain `<html>`, `<head>`, or `<body>` tags.

## Design tokens, geometry, engine API

Unchanged from v1 except:
- **No badge rail**: `#rail` element, its CSS, `LEVERS`, `updateRail`,
  `maybeRailFlash` are all deleted. `.slide` padding is now symmetric
  (`6cqh 6cqw 29cqh 6cqw`).
- **Timer checkpoints**: s6 by 5:00 (end of part 1), s9 by 8:00, s13 by
  11:30, s15 by 14:00.
- Everything else (tokens, terminal band, builds, shadow-term templates,
  `?still`, print CSS, reduced motion, keys incl. `0`→#fallback,
  `S`→#stepper, `B` back) is as in v1 and as implemented.

## SVG assets (spliced by build.py)

- `{{SVG:pipeline}}` → s7 (figure-card, second build)
- `{{SVG:bennett}}` → s9 (SMIL-animated construction; engine restarts its
  clock on slide enter)
- `{{IMG:democast}}` → #fallback only
- `{{SVG:circuit23}}` → unused (build.py prints a note; fine)

## THE SLIDES (content normative; **bold** numbers verified 2026-08-11)

### Part 1 — the why

- **s0 Title** (band off). Unchanged from v1: eyebrow `JuliaCon 2026`,
  "**Given** an Oracle for *f*" (Given in gold, f serif), four Julia dots,
  `Sturm.jl · Bennett.jl · BennettVM.jl` + roles line
  (`…a reversible interpreter`, not "VM"), byline.
- **s1 What I wanted** (band off). Lead: "To write quantum programs in the
  language I already write." Two-column contrast: generic circuit-style
  pseudocode (`circuit.h(0)` …) vs the real Sturm Bell-pair three-liner
  (`q = QBool(0.5); r = false ⊻ q; Bool(q), Bool(r)`). Build: the map of
  part 1 — design decisions one at a time, each with the Julia feature
  that made it work.
- **s2 Quantum data is a value, not a wire.** Real M6-test vocabulary:
  `QInt{4}(3)`, `add!(x, 2)`, `superpose!(x)`, `s = x + 2`. Builds: width
  in the type / `x < y` returns a *quantum* bool; Why Julia: first-class
  user types — "behave like a number without pretending to be one".
- **s3 Crossing the boundary is a type conversion.** `QBool(0.7)` /
  `Bool(q)`. Builds: measurement consumes (use-after → error);
  `Bool(QBool(b)) == b` is a named law test; Why Julia: constructors are
  already the conversion idiom.
- **s4 Scope is physical.** The `eager(4) do ctx … end` block; local `r`
  discarded exactly at `end`. Builds: discarding is a physical operation,
  so it needs a definite moment (not GC); Why Julia: do-block =
  try/finally, deterministic scope exit.
- **s5 Control flow can be quantum.** `when(c) do add!(x, 3) end` (real,
  test_m6). Builds: measuring inside errors at the exact call; Why Julia:
  do-block syntax — `when` is a function taking a closure, not a macro.
- **s6 What physics forbids, dispatch forbids.** The
  `ctrl(Protect(enc))` MethodError transcript. Builds: the theorem lives
  in the method table, not the docs; "we didn't write a checker — we
  didn't write the method." **5:00 checkpoint.**

### Part 2 — Bennett

- **s7 "Given an oracle for f …"** (band off). The equation
  `O_f |x⟩|y⟩ = |x⟩|y ⊕ f(x)⟩` at 4.6cqh + **plain-words translation**
  ("your function, installed as a gate"). Build 1: Grover/Shor/DJ/QPE all
  start from this sentence; the papers never say where the oracle comes
  from. Build 2: `{{SVG:pipeline}}` — "here's where: an ordinary Julia
  function, compiled."
- **s8 A quantum computer can't forget** (band off). AND truth table with
  the three collapsing rows `<mark>`ed; "three different pasts, one
  output". Builds: QM only runs what can be undone; "so your function
  can't run as-is … that sounds like it means rewriting everything."
- **s9 Bennett, 1973: keep it, copy it, undo it** (band live; SMIL).
  Left 55% `{{SVG:bennett}}`; right: the three steps in plain words
  (compute / copy / uncompute, colour-coded to the animation's phases).
  Builds: cost ≈ 2× gates + scratch, "not a rewrite — a transformation",
  step 3 is a for-loop with a negative step; the live equality
  `gs[14:23] == reverse(gs[1:10]) → true` ("checked in CI"). Shadow-term:
  the 23-gate compile + equality transcript. **8:00 checkpoint.**
  Speaker note: open in silence, let the animation run one loop.
- **s10 You don't have to rewrite your code** (band live) — LIVE BEAT.
  `f(x::Int8) = x*x + Int8(3)*x + Int8(1)` → `reversible_compile(f, Int8)`.
  Builds: the **482**-gate result line; "no macros, no special types, f is
  unchanged — you can still call it"; Why Julia: `code_llvm` gives any
  package the compiler's view of any function, in-process.
- **s11 Even code you didn't write** (band off) — `costbars` (3 consumed
  steps: **482** → **63,058** → **11,027,852**, axis rescales). Build: the
  sin is `Base.sin`, unchanged, ≤1 ULP; honesty — SHA-256 round **1,632**
  vs hand-optimized **683** (~2.4× worse), "the point isn't beating the
  experts. It's not *needing* to be one."
- **s12 …and it becomes quantum** (band live) — `entangle` (7 consumed
  steps). Header: `cc = controlled(reversible_compile(x -> !x, Bool))` +
  promotion note. Build after: "One function call — controlled(·) — is
  the entire quantum lift." (v1's "I never wrote a quantum gate" headline
  is REMOVED.) Shadow-term unchanged.
- **s13 The loop closes: oracle(f, x)** (band live) — LIVE BEAT. The DJ
  function verbatim (M7-test vocabulary), `b ⊻= oracle(f, x)` marked.
  Build: what DJ asks + "everything from the first half is on this
  screen". Weakdep/extension plumbing is Q&A material (notes), not slide
  material. Shadow-term: two eager DJ calls. **11:30 checkpoint.**

### Part 3 — what's left

- **s14 What's left** (band off). Four plain panels: **Cost** (the 2.4×);
  **Loops without a bound** (BennettVM runs Collatz forward and backward
  bit-for-bit, but that reversibility can't become a quantum oracle —
  "physics, not engineering, as far as we can tell"); **Hardware**
  (everything ran on a simulator); **Error correction** (toy code works
  end-to-end, honest above/below threshold, real codes next). Build:
  also open — multi-register oracles, wider arithmetic, compile speed.
- **s15 Thank you** (band off). The s10 code panel byte-identical (quiet
  callback). Builds: "If you know Julia, you already know most of what's
  here." / gold: "That was the whole point." Then "Ancillae restored to
  zero. Thank you." Footer: github + AGPL + "issues and questions
  genuinely welcome". **14:00 checkpoint.**

### Backups (class="slide backup"; reachable by hash, keys 0/S, B returns)

- `#fallback` — recorded run (key 0). Unchanged.
- `#teleport` — NEW (was linear s12 in v1): the 9-line teleport function
  with margin annotations, softened (no aphorism, no issue-number
  jargon); 200/200 probe transcript in shadow-term.
- `#pebbling`, `#vmtape`, `#numbers-full`, `#stepper` — unchanged from v1.

## Components (components.js — UNCHANGED from v1)

`costbars` now lives on **s11**, `entangle` on **s12**; `stepper` stays on
`#stepper`. The component registry, gate JSON schema, consumed-advance
contract, and all internal captions are untouched.

## Verified-numbers appendix (single source of truth)

482 (NOT 14/CNOT 300/Toffoli 168), depth 89, Toffoli-depth 36, 249 anc ·
23 gates (NOT 6/CNOT 15/Toffoli 2), 16 wires, 10 anc, depth 9 ·
simulate(c1, 3) = 4 · f(5) = 41 · 63,058 · **11,027,852** (1,629,722 /
7,059,276 / 2,338,854; 38.8 s compile; sin(1.2345) bit-identical) ·
QCLA 56 vs 180 · QROM 4(L−1) · shadow 24 vs 7,122 · SHA 1,632 vs 683 ·
Collatz circuit 14,074 / 2,320 / 8,868 · DJ warm ≈2.1 s, first oracle call
20.8 s cold · teleport probe 200/200 in 0.25 s · wm28 1024/1024 vs ≈512 ·
TTFX 20.7 s → 0.99 s · suites ≈692k / >27k.

## Snippet provenance (part 1 slides — all real committed code)

- s1/s4 Bell pair & scope: `test/test_m4_views.jl` (teleport preamble
  idiom `false ⊻ q`), `eager(n) do ctx … end` used throughout the suite.
- s2 QInt: `test/test_m6_qint.jl` (add!/superpose!/register+scalar `+`).
- s3 casts: `test/test_m3_qbool.jl:85–87` — `Bool(QBool(b)) == b` is the
  named qc∘cq law test.
- s5 when: `test/test_m6_qint.jl:168–172` (controlled `add!`);
  measurement-inside-when errors: `test/test_m5_when.jl:50–56`.
- s6: `Protect` — `src/qecc/superchannel.jl`; `ctrl` has no `Protect`
  method by design.
- s13 DJ: `test/test_m7_bennett.jl` (superpose!/minus()/oracle/Int(dual)).
