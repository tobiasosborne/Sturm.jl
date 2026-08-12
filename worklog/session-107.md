# Session 107 — 2026-08-12 — JuliaCon 2026 deck REDONE from scratch (v2)

## What happened

Tobias rejected the session-106/107-era deck outright: **"100% not what I
want: full of jargon, not authentic, smug, exclusive."** The HTML
machinery was explicitly OK; the content was not. Direct structural
directive:

1. first ~1/3 = the **why**: Sturm.jl design decisions one by one, each
   with why Julia is perfect for it;
2. then Bennett.jl illustrating the headline feature **"you don't have to
   rewrite your code"** — but FIRST explain Bennett's 1973 result in an
   animated slide or two;
3. end with **what is left**.

## What was done

Content fully rewritten (`src/slides-a.html`, `src/slides-b.html`,
`src/DECK-SPEC.md` → v2 with normative **voice rules**); machinery kept
(`engine.js`, `components.js`, `frame.html`, `build.py`, terminal band,
shadow-term, `?still`, print CSS).

New linear structure (16 slides, s0–s15):

- **Part 1 (s0–s6)** — title; "What I wanted" (circuit-style vs Sturm
  contrast); five decision slides, each ending in a "Why Julia:" build:
  values-not-wires (QInt), boundary-as-conversion (casts +
  `Bool(QBool(b)) == b` law), scope-is-physical (do-block = try/finally),
  quantum control flow (`when` is a closure-taking function, not a
  macro), what-physics-forbids-dispatch-forbids (`ctrl(Protect(enc))`
  MethodError). All snippets are REAL committed test code — provenance
  table added to DECK-SPEC.
- **Part 2 (s7–s13)** — the oracle sentence with a plain-words
  translation of the equation; "a quantum computer can't forget" (AND
  truth table, marked collapsing rows); **Bennett 1973 animated** (SMIL
  SVG + three plain-words steps + live `gs[14:23] == reverse(gs[1:10])`);
  **"You don't have to rewrite your code"** (the 482-gate live beat, now
  the title of its own slide); "Even code you didn't write" (costbars;
  honesty row: SHA-256 ~2.4× worse, "the point isn't beating the experts —
  it's not needing to be one"); "…and it becomes quantum" (entangle
  component; v1's "I never wrote a quantum gate" headline REMOVED);
  oracle/DJ live beat.
- **Part 3 (s14–s15)** — "What's left": four honest panels (cost,
  unbounded loops incl. the VM-can't-cross-into-an-oracle boundary,
  hardware, QECC); close: "If you know Julia, you already know most of
  what's here. That was the whole point."

Removed entirely: the badge rail / "six levers" conceit (element, CSS,
`LEVERS`, `updateRail`, `maybeRailFlash`), "the zinger", "signature
moment" stage directions, weakdep/`Ref{Any}` plumbing on slides (now Q&A
notes), the false-path-sensitization war-story slide, the "Two lessons"
slide. Teleportation moved from linear to backup `#teleport` (annotations
kept, aphorism dropped). Pipeline SVG dropped from linear flow (marker
kept in build.py, prints "unused" note — deliberate).

Engine checkpoints now s6@5:00, s9@8:00, s13@11:30, s15@14:00.
`DEMO-RUNBOOK.md` §a/§b/§c/§d/§e/§f updated to the new beat map
(s9/s10/s12/s13 live; `#teleport` conditional Q&A beat); `warmup.jl`
relabeled + retype order re-derived for the new beat order (s9 lines
seed LAST now — reverse-stage). `julia` parse-check passed
(Meta.parseall only, no package load, serial).

## Verification

- All four live-beat commands/numbers unchanged from the verified
  2026-08-11 appendix — no new numbers were invented.
- Headless-chromium screenshots of every linear slide + `#teleport` at
  1280×720 `?still`: two overflow bugs found and fixed (s7 pipeline
  figure clipped → replaced with a one-line arrow; s9 right column
  overflow → compressed to 2.2cqh). Everything else clean.
- `node --check` on engine.js/components.js; build.py marker validation.

## Gotchas for future agents

- **The rejection was about REGISTER, not facts.** Every number survived;
  what died was the conceit (badge rail, levers, zinger) and unexplained
  jargon. DECK-SPEC v2 now has explicit voice rules — check edits against
  them before adding anything clever.
- The ⊻ glyph renders as an underlined-V in headless chromium (DejaVu
  fallback); fine on a machine with JuliaMono. Runbook §a.4 covers it.
- `worklog` numbering: the Aug-11 deck-build sessions never wrote a shard;
  this session is 107. The stale "session 108" self-reference in an early
  DECK-SPEC draft was corrected before commit.
