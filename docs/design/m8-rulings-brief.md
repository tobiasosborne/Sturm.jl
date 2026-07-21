# M8 rulings brief — everything blocking M8 code, one page

> **⚖ RULED — 2026-07-21, session 98 (Tobias, in-session).**
> **F13 = OPTION D**: `Bool(q)`/`Int(x)` are the single measurement
> spelling in every context, returning the classical system as the
> context represents it (value / record / wire) — a registered exception
> to the Julia constructor convention. **All other items: standing
> recommendations adopted** (D15 = certified-block option; TR1–TR8 as
> recommended; `postselect` spelling; F15/F19 as recommended; F16
> scheduled pre-M8; ne0d approved). Full ruling record:
> `m8-i4ri-classical-control-design.md` §14. The items below are
> retained as the pre-ruling record.

*Session 98 (2026-07-21). M8 (`szx1`) is design-complete: both P0 gates
(`5hr7`, `i4ri`) closed with 3+1 syntheses committed. The critical path is
now **decisions, not design**. Each item below names its bead, where the
full option space lives, and the standing recommendation. Rule by editing
this file, replying in-session, or `bd comments`.*

## P0 — block all M8 code

1. **F13 — measurement spelling under Tracing/DM** (bead `vqas`;
   full options: `m8-i4ri-classical-control-design.md` §4).
   `Bool(q)` returning a token violates Julia's constructor convention, and
   the promised descriptive error on `if token` is unimplementable (native
   TypeError, verified non-interceptable on 1.12.5).
   **Recommendation (both blind proposers independently): Option A —
   `measure(q)` returns the context-appropriate token; `Bool(q)`/`Int(x)`
   stay honest scalar casts (Eager-only).**
   Sub-question: do `Bool(q)`/`Int(x)` *throw* under DM/Tracing (recommended)
   or degrade?
   **Session-98 addendum (Tobias dialogue,
   `m8-i4ri-classical-control-design.md` §12):** "measurement returns a
   `Bool`" has THREE coherent readings in DM-land — *sample* (Eager only),
   *record* (TP instrument, DM native), *assert/postselect* (CP-TNI, the
   outcome is an input, state subnormalized with weight p_b; factors as
   record + classical effect ⟨b| on the c-wire). Whatever spelling is
   ruled, the three must be distinct surface operations — one name
   silently covering two of them is the silent-wrongness pattern. The
   effects/postselection surface is its own bead (below).
   **Session-98 addendum 2 (context trichotomy + traceable subset,
   design doc §13):** the contexts exist for different reasons — Eager =
   runtime semantics (MCM hardware, prototyping), DM = physical
   denotation (record = deferred measurement as types), Tracing = the
   compiler. The IR names the measure node under EVERY option, so
   compiler visibility does not discriminate; what does: under Option A
   the traceable/portable subset is **lexical** (lintable at a glance),
   under Option D it is use-site-dependent (discovered at trace time by
   failure). Meanwhile Option D gained a principled foundation from the
   typing dialogue: one channel, one spelling, the cast returns the
   classical system represented as faithfully as the context allows
   (value ↔ record ↔ wire). The ruling is now a clean A-vs-D choice;
   §12's three-meanings rule holds under either.

2. **TR1–TR8 — UnitaryBlock design details** (bead `z1sa`;
   full options: `m8-5hr7-unitary-block-design.md` §8). One line each:
   - **TR1** block shape: square `UnitaryBlock{N}` + rename `UnitaryDAG` →
     `UnitaryBlock` (rec: yes — both proposers overrode the review's
     `{InPorts,OutPorts}`).
   - **TR2** Eager failure topology on guardrail violation (rec: tee+poison).
   - **TR3** `QBool(false)` scratch stays blessed; `within` is `public`
     kernel API, **not** an 8th surface construct (touches CLAUDE.md #11;
     jointly resolves F12/D15 — rule with item 3 below).
   - **TR4** M8 certificates: conservative combinator-carried set only
     (`NoAncilla`/`PermClean`/`MatchedPair`/`SeqCert`/`ParCert`/
     `AdjointCert`/`XportCert`), no SMT/solver (rec: yes).
   - **TR5** freeze `Perm.gates`/`MCX.controls` `Vector` → `NTuple` (F28;
     overlaps hygiene bead `bx11`).
   - **TR6** `oracle` targets full-width + structural range certificate
     (interacts with M7 follow-on `fy8l` — rule before starting it).
   - **TR7** `PhaseDelta` stays kernel-internal; zero-port blocks forbidden
     in M8 (rec: yes).
   - **TR8** `denoted_matrix` memory-budget cap (F25-consistent, ≈7 wires).

3. **D15 — arbitrary `QBool(p, φ)` literal inside `when`** (bead `xy4w`;
   options in PRD §9 D15). Controlled prep is phase-ambiguous. Candidates:
   (a) forbid; (b) admit only inside a certified compute/uncompute block;
   (c) pin a phase convention and prove control-stability.
   **Loud error until ruled — already shipped as spec text.** TR3's
   recommendation implies (b) as the natural resolution.

## P1/P2 — sequencing decisions (do not block the first M8 commits)

4. **F16 — context-parameterized handles `QBool{C}`/`QInt{W,C}`**
   (bead `4c0j`, F16 arm). The i4ri design makes this a **hard dependency
   of the F13 Option A cast work**, and the rebaselined plan (§3.0) lists
   it as the one genuinely-unscheduled pre-M8 gate. Decision needed:
   schedule the refactor pre-M8 (recommended) or fold into M8 itself.
   The F15 (numeric contract wording) and F19 (bicharacter trait) arms of
   `4c0j` are cheap-now/invasive-later but not M8-blocking.

5. **F31 PRD follow-up** (bead `ne0d`): replace the PRD intro's blanket
   "everything carries over from v0.1" with the plan §7 contract table
   (4 re-derived / 1 measured-verbatim / 1 gated-on-M11) and demote
   `Sturm-PRD.md` to historical. Mechanical once approved.

## Already ruled this session (no action needed)

- F30: `@cases m` on a raw register rejected; canonical `@cases measure(m)`
  (sugar deferred, gated on F13).
- F12 partial: guardrail 1 = qc casts banned, `|0⟩` alloc blessed (shipped
  in PRD, commit `93f36fd`); only the D15 literal case remains open.
- 6xdk endianness (session 97): wire-1 = MSB, kernel-wide.

**Once items 1–3 are ruled:** the paste-ready PRD wording ships from the two
design docs' §7 blocks (one review pass), `szx1` unblocks, and M8
implementation starts on the rebaselined plan §3.M8 seven-part split.
