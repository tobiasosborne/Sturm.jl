# Session 103 — 2026-07-24 — M11 design round relaunch + M12 follow-ons (orchestrated)

Orchestrator session. Tobias: "orchestrate work, delegate coding/review to
Opus subagents (**no codex this session**), sonnet for summarisation/code
queries/web research; watch for stale beads; post-reboot work only."

## Bead hygiene: the graph is already clean

Checked first, per the standing instruction. **No stale beads to sweep.** All
14 open beads are post-reboot (M7–M12 follow-ons + the M11 gate + the epic).
The v0.1-era clusters — the 4ceh QSVT bug family (`4ceh`/`l5s5`/`grq5`/`p2gr`/
`92di`/`d2eb`/`50k1`/`5lu4`/`mvvz`) and the qudit epic (`goi`/`dj3`/`csw`/
`jr7`/`7qm`) — are all `❄ deferred` from session 96's sweep, 50 deferred
total.

- **Display gotcha worth knowing:** `bd blocked` lists DEFERRED issues too, so
  it shows the whole 4ceh cluster as "blocked P0s" and reads alarmingly. It is
  not a staleness signal. Cross-check with `bd list --status=open` before
  reacting to anything `bd blocked` reports.
- **Tracker inconsistency (harmless):** `bd stats` reports "Ready to Work: 3"
  while `bd ready` lists 10. Not chased.

## Dispatch (4 agents, wave 1)

Julia contention is the binding constraint (v0.1 rule: only ONE agent may run
Julia at a time — shared compile-cache clashes). So exactly one agent holds
**exclusive Julia rights**; everyone else is explicitly banned from running it,
including one-liners.

| Agent | Model | Bead | Julia |
|---|---|---|---|
| Proposer A | Opus | 82su (blind) | ✗ banned |
| Proposer B | Opus | 82su (blind) | ✗ banned |
| Implementer | Opus | jpky | **✓ exclusive** |
| Extractor | Sonnet | jiae (literature only) | ✗ banned |

**82su relaunch.** The staged proposer prompt
(`docs/design/m11-82su-proposer-prompt.md`, written session 102, git-tracked)
was reused after refreshing its stale context line (it claimed "M0–M10
shipped, suite 26136" — now M0–M12, 27328) and adding session-102 to the
required reading. Session 102's attempt died because both blind codex jobs
were externally stopped by a concurrent interactive codex session; this
session substitutes 2 blind Opus subagents, which satisfies the 3+1 rule
identically (separate contexts ⇒ genuinely blind). Proposals land at
`docs/design/m11-82su-proposal-{A,B}.md`; each proposer is forbidden to read
the other's path.

**Orchestrator = reviewer (+1)**, and read F8/F33 in
`docs/design/prd-v2-review-gpt56-2026-07-19.md` + plan §M11 up front rather
than reviewing cold. Shipped M11-relevant surface for judging the proposals:
`KrausFamily(nwires)` is a *placeholder stub* in `src/channel/dag.jl`;
`NoiseN` already exists as a unitary-pass barrier that `certify` refuses; DM
already applies 1-local Kraus channels through Orkan
(`_apply_channel_1q!` → `kraus_to_superop`); and `when.jl`'s dispatch table
row 9 already BANS `apply_channel!` under control — so the "noise inside
`when` is a loud error" guardrail the design round is asked about is
*already shipped*, and a proposal that reinvents it is duplicating.

Agents write reports to scratchpad; the orchestrator owns `WORKLOG.md`,
`worklog/`, beads, and all commits (concurrent writes to one worklog file
would conflict).

## ⚠ POLICY CHANGE — physics PDFs are NEVER committed (CLAUDE.md rule 4 amended)

Tobias, this session: *"the pdfs should be gitignored. someone got sloppy."*
then *"delete all problematic pdfs from the public repo."*

**How it surfaced.** The M11 sourcing agent landed Watrous's *Theory of
Quantum Information* as the recommended Stinespring source. Spot-checking its
title page (law 9 — verify subagent output) turned up a verbatim notice:
*"made available for personal use only and must not be sold or redistributed."*
`docs/physics/` was **committed** per rule 4, and `gh repo view` confirms
github.com/tobiasosborne/Sturm.jl is **PUBLIC** — so the rule as written
mandated redistribution.

**It was never just Watrous.** 27 PDFs / 19 MB were tracked, including
plainly copyrighted journal and conference works: Barenco (Phys Rev A 1995),
Suzuki (J Math Phys 1991), Stuelpnagel (SIAM Review 1964), Bennett (IBM J Res
Dev 1973), Grover (STOC 1996), Shor (1995). The arXiv preprints are a weaker
concern (license silent, not prohibitive) but go the same way for uniformity.

**Fix (tip):** `docs/physics/*.pdf` + `**/*.pdf` gitignored; all 27 untracked
with `git rm --cached` (**files remain on disk** — every citation stays
locally re-checkable); rule 4 rewritten from *"canonical, committed: original
PDFs AND distillations"* to **"commit the `.md`, keep the PDF local"**, with
an explicit warning that a **missing PDF in a fresh clone is EXPECTED** and
must not be "fixed" by committing the file. Rule 4's intent — a named source
plus an exact equation pin, so any claim is re-checkable — is untouched; only
the binary-blob-in-git half is gone.

- **Checked before acting:** the runtests citation lint
  (`test/runtests.jl:29`) matches `docs/physics/[A-Za-z0-9_\-]+\.md` — `.md`
  paths ONLY, deliberately blind to PDFs. Untracking cannot break it.

**History purge (ordered by Tobias, separate step).** Untracking fixes the tip
and all future commits but leaves ~19 MB of PDFs fetchable from earlier
commits. `git-filter-repo` is installed. **Sequencing matters and is the
trap:** a rewrite requires a quiet, clean tree, and the jpky implementer was
mid-flight with uncommitted `src/library/evolve/` work when the order came —
rewriting under a live agent would have destroyed or orphaned its work. So:
(1) commit+push the untracking, (2) let in-flight agents land and commit,
(3) purge with a backup bundle taken first.

**Known cost, accepted:** every commit SHA after the first PDF commit changes.
The worklog shards cite SHAs heavily as institutional memory (`fec6a36` the
reboot, `405a38f`, `77327ae`, …); those become historical-only references.
Beads `f9ka` (closed, superseded) and `wuji` record the analysis.

<!-- RESULTS APPENDED BELOW AS AGENTS LAND -->
