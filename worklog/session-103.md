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

## jpky SHIPPED — Auto ranks on a budgeted-exact α, not a heuristic

The bead offered two fixes (exact O(L²) pair-sum anchor; budgeted exact probe).
The implementer found the construction that **is both**, and it is better than
either: `alpha_comm_layered` runs the SAME exact α_comm DP under a propagation
budget, stops at the deepest completed layer `d`, and closes the rest with the
1-norm step, giving the proven bound

> (‡) `α ≤ 2^{2k} · λ^{2k+1−d} · M_d`

whose endpoints are exactly the bead's two options: **`d = 1` IS `:norm1`**,
**`d = 2` IS the pair-sum anchor** (`M_2 == alpha_comm_pairs` identically —
both are `Σ_{i≠j, anticommuting}|a_i||a_j|`, so the "new" anchor needed no new
code), `d = 2k+1` is exact, and it is monotone in `d`. **So the ranking is
still a ranking of PROVEN costs** — the docstring's central claim survives
untouched, and no heuristic was introduced. Only the O(L log L) claim was
retired (in auto.jl, strategies.jl, and an m12-synthesis amendment).

*Orchestrator verification of (‡):* with `M_d` the coefficient mass at depth
`d` (the per-layer factor 2 EXCLUDED), the true nested-commutator norm is
`2^{d−1}M_d`; at `d = 2k+1` the bound is `2^{2k}M_{2k+1}` = exactly `α_comm`;
at `d = 1`, `M_1 = λ` gives `2^{2k}λ^{2k+1}` = exactly the standard 1-norm
bound; monotonicity is `M_{d+1} ≤ λM_d`. Endpoints and interpolation check out.

**Regret (both tiers re-run; BEFORE re-derived from the preserved gmx0 CSVs
with the same statistic, not quoted from session 102):**

| | BEFORE | AFTER |
|---|---|---|
| analytic (588 cells) regret == 1 | 63.3 % | **91.8 %** |
| p90 / p99 / max | 4.39 / 19.9 / **43.5** | 1 / 2.12 / **3.27** |
| cells > 2× / > 10× | 121 / 22 | **9 / 0** |
| exec (126 cells) regret == 1 | 85.7 % | **96.0 %** (max 1.82 → **1.08**) |

Headline cell `ising-W64, t=16, ε=1e-4`: **43.5 → 1.0**. Zero bound violations.

### The seductive wrong answer — DO NOT RESURRECT

The orchestrator's brief offered, as fix option (a), a geometric commutativity
discount (`α ≈ norm1 · s₁^{2k}`, `s₁ = α_pairs/λ²`). The implementer checked it
against the gmx0 α table **before writing code**: it fits the structured chains
to three digits and is wrong by **2.6 × 10³×** on exp-L256 at order 6, in the
**under**-estimating direction — i.e. it would have converted Auto's one-sided
failure mode (over-picks QDrift, never violates ε) into a two-sided one. (‡)
costs the same and is a theorem. *Lesson: a discount that fits the cases you
looked at is not a bound.*

### Other gotchas worth carrying

- **Inclusion–exclusion does not survive bounding.** `αAB = α(H) − α(A) − α(B)`
  is exact, but subtracting *upper* bounds yields neither an upper nor a lower
  bound — hence `alpha_comm_cross_layered`'s two branches (all-exact ⇒ the
  identity; else `min` of two separately-proven bounds). Subtlest thing in the
  change.
- **Budget check goes at the TOP of the per-word loop**, not the bottom, or a
  layer finishing exactly at budget is misreported as an incomplete stop.
- **Depth-1 mass must be `hs.λ` verbatim**, not a re-sum of dict values, or the
  `d=1 ≡ :norm1` identity picks up dict-iteration-order rounding (and the test
  still needs `≈`, rtol 1e-14).
- **Don't size a Julia suite `timeout` from the last run's wall time.** The
  implementer's `timeout 1800` (baseline 11m12s) killed a COMPLETE post-change
  run at 30 min because other agents had the box at load 20. Check `uptime`
  first. Cost a full run.
- **`@test a && b rtol = 1e-12` is an invalid test macro call** — `rtol`
  attaches to a single comparison only.

### Reporting honesty (worth imitating)

The box was at load ≈ 20 from concurrent agents, so the bench's wall-clock α
probes downgraded five L=256 families' PLANNING to `:norm1` where gmx0 used
`:exact`. Rather than quietly shipping the mixed comparison, the implementer
reported the 483-cell identical-probe-mode subset (63.1 % → 95.0 %, p90 4.79 →
1, max 43.5 → 2.31) AND re-measured the five residuals at the library default,
where all five have regret 1. **The headline AFTER numbers are therefore
pessimistic, not flattering.** Filed as bead `c8rx`: wall-clock probe
thresholds must become explicit run configuration, since they make frontier
CSVs non-reproducible across machines — session 102 predicted this as gotcha
(d); this session it bit.

### Accepted latency change (orchestrator ruling)

Auto now sometimes picks Composite where it picked QDrift, and the chosen
shape's exact-α planning takes **5–12 s** on L=1024 dense families (was
instant) for a ~2.5× cheaper circuit (2584 vs 6403 exponentials). This is NOT a
change to the shipped-bound path — `plan_evolution` still derives its number
from `alpha_comm` under the caller's own `alpha_mode`, and the new `alpha_work`
kwarg budgets DISPATCH only. Verdict: acceptable, a good trade for a compiler.
Measured safety: all 10 families with L ≥ 256 × {t=0.5,4,32} × {ε=1e-2,1e-4} =
60 cells probed at default `:exact` planning, **0 `AlphaCommBlowup`** — the cap
only bites at order ≥ 4 on dense L=1024, and Auto only picks order-2 there.

## M11 design round (82su) — COMPLETE, awaiting 6 rulings

2 blind Opus proposers (A 1470 lines, B 1274) + Opus synthesiser →
`docs/design/m11-82su-synthesis.md`, 31 rulings S1–S31. Verdict: **synthesis,
not a pick** — A owns the channel-value algebra and numerics (it read Orkan's
headers and let them shape the design), B owns the typed superchannel surface,
the code representation and the anti-tests.

**Convergences** (independent, therefore load-bearing): the dilation lives
OUTSIDE the process-value tree — both rejected "a `ProcessValue` that `ctrl`
refuses" for the same reason, that `Tensor`/`UnitaryBlock`/`certify` are other
doors, so refusal must be replicated at many sites instead of zero;
`effective_logical_noise` is a **compiler transformation on `ChannelDAG`**, not
a runtime value, and explicitly NOT a `ChannelPass` (that law is
Choi-PRESERVING; a superchannel changes the denotation by design);
physical/logical labels ride the register type, never the `Port`;
`fault_tolerant_lift` = interface + loud refusal, grounded by B on
**Eastin–Knill** — non-canonical BY THEOREM, not by gap.

**Adjudications worth remembering:** completion algorithm landed where neither
proposal was — run Householder, then overwrite `U[:,1:d] := Ṽ`, making the
contract assertion EXACT and deleting A's `diag(R̃)` phase fix (B's
`GS_PIVOT_TOL=1e-8` was exactly the in-algorithm rank tolerance A warned
against: it can fail loud on VALID input, data-dependently). Env wires LEAD/MSB
because that matches `Ctrl`'s control-leading convention, so the dense artifact
and the structured emission agree with no permutation — which is what lets the
three-way test detect an ordering bug instead of being fooled by two
compensating ones.

**The round found four real shipped defects** — see `udtl` below, plus:
`_replay_dm!` errors on `NoiseN`; `ChannelDAG` has no channel-level `∘`/`⊗`
though PRD §4.4 promises them; `select` has no host-scalar methods, so a
syndrome program is not portable to Eager.

**Corrections the synthesiser made to its own inputs** (law 9 working): A was
wrong that amplitude damping is unexecutable (B's `ctrl(Ry(2θ))`+`ctrl(X)`
circuit yields the textbook family with shipped machinery only — and damping is
A's own env-ordering sentinel); A wrongly rejected B's `certify(trace(...))`
encoder (the isometry factors as alloc∘unitary and the unitary part certifies);
B's claimed `_replay_branch_controlled!` gap is already closed
(`tracing.jl:530` fails closed — test only). **And the ORIGINAL PROPOSER PROMPT
was wrong**: it asserted "the plan names `classicalise`" — it appears nowhere
in the v2 plan or PRD-v2; it is an unlogged v0.1 carried contract whose spec
text (`Sturm-PRD.md:457`) carries a silent single-qubit defect. A inherited the
brief's error; B caught it. *Lesson: a design brief is not evidence.*

## P1 defect found by the round: noise under `when` is SILENT (bead `udtl`)

Both blind proposers found it independently; orchestrator reproduced by
inspection. `apply_channel!` (`density.jl:86`) never calls
`_assert_no_control`, while every other guardrail-1 site does (casts, `ptrace!`,
`cases`). `when.jl:69` row 9 documents the ban in a comment table — *"BANNED —
forward hook (M8/M11)"* — **and it was never wired**. `apply_channel!` is
`public`, so it is reachable as `Sturm.apply_channel!`; called inside a `when`
body on DM it applies the channel UNCONDITIONALLY. Silent wrong physics = the
wm28 class. P1 not P0 only because M11 has not shipped, so nothing exercises it
under control yet.

**FIXED this session** — `_assert_no_control(ctx, "noise channel apply_channel!")`
now opens `apply_channel!`, BEFORE `_flush_wire!`, so the throw precedes any
backaction. RED test proved real backaction first (1 passed / 6 failed, ρ
demonstrably changed); GREEN 7/7 + 8/8 + 6/6 across 3 testsets in
`test_m5_when.jl`. Suite 27439 → **27460**.

⚠ **The orchestrator's stated placement rationale was WRONG, and the fixing
agent said so** (verified independently before accepting): the brief and the
first draft of this worklog claimed the guard must sit at `apply_channel!`
rather than `_apply_channel_1q!` because *"row 8 makes region-exit traces under
control legitimate and they share that lowering"*. At code level that is false.
`_trace_and_free!` (`abstract.jl:347`) branches on
`isempty(core.control_stack)`; under control it takes the clean-ancilla ASSERT
branch and never reaches the Kraus lowering. So **no current path reaches
`_apply_channel_1q!` under a live control stack**, and a guard there would have
been REDUNDANT, not breaking. The placement is still right, for the honest
reason: the caller owns the policy, and a future DM row-8 lowering that ran the
reset channel under control would be legal. The agent wrote the caveat into the
code comments rather than repeat a justification a reader would discover is
false — the correct call. *Lesson: a plausible mechanism is not a verified one;
the orchestrator asserted this twice before anyone checked the branch.*

Two further findings from the same fix: **row 10 (`cases`) was ALSO still
labelled a forward hook** though M8 wired it — same stale-comment class, also
fixed; and `TracingContext` has **no** `apply_channel!` method at all while
`NoiseN` is only constructible through the `DAGBuilder` seam, so there is no
second silent hole today — but M11's noise surface must wire the guard when it
lands. The prior review's claim that `_replay_branch_controlled!` needs a
refusal is **wrong**: `tracing.jl:530` already fails closed (now pinned by
test, no code added).

New `when.jl` note ends with the rule this whole bug argues for: *"when a row
says BANNED, grep for its `_assert_no_control` before believing it."*

**Boot-lint gotcha worth knowing:** the lints grep `src/` as TEXT — the bare
word "controlled" in a comment outside `src/kernel/` + `src/orkan/` fails the
suite. (`uncontrolled` is safe.)

## Also filed

- `83a8` — M12's `_assert_randomized_legal` tells users the DM lowering "is
  M11's mixture value… until it lands". **M11 does not close it**:
  `MixedUnitary{W,R}` targets enumerated `R ≤ 16`, qDrift needs `R ~ 10⁴`. The
  S10 guard itself is sound and stays; only the forward promise is wrong. Note
  a possible collapse: ONE qDrift step is a mixed-unitary channel with only `L`
  terms, so an N-step ensemble may be an N-fold composition of a cheap channel
  rather than a 10⁴-term object — check that first.
- `jiae` — rewritten after the Childs extraction (see below).
- `c8rx` — bench probe reproducibility (above).

## jiae: the bead's premise was partly wrong (research, verified)

Sonnet extracted Childs Prop. 16 / Eq. (152) p.39; **orchestrator verified
against the PDF directly**. Index ranges — the thing the bead was blocked on —
are NOT a `γ₃>γ₂>γ₁` chain: ONE outer sum over pivot `γ₁`, with `γ₂` and `γ₃`
ranging INDEPENDENTLY over `(γ₁,Γ]`, and the partial sums INSIDE the norm
(triangle inequality applied only across `γ₁`). Norm is spectral; no diamond
norm appears in the paper, so `_diamond_from_spectral`'s ×2 still applies on
top. Local PDF is **arXiv:1912.08854v3**, self-described as a "slightly
enhanced version" of the PRX article — Prop/Eq numbers are version-specific and
citations must pin the version. Do NOT conflate with Thm 11 / Cor 12
(pp.21–22), a different, looser, unrestricted-index asymptotic bound — which is
what Sturm uses today.

**Why the premise is partly wrong:** `alpha_comm_pairs` is cheap because nested
commutator norms of SINGLE Pauli words are exactly 0 or 2^{2p}. Eq. (152)
instead needs the spectral norm of a **sum** of Pauli words — exponentially
hard in general — and bounding it by the coefficient 1-norm IS the extra
triangle-inequality step, which collapses (152) straight back to the loose form
already shipped. **A naive implementation buys nothing.** The escape hatch, now
the bead's actual design question: for local/structured H most terms commute
with `H_{γ₁}`, so the inner commutator collapses to a few words on bounded
support where the exact spectral norm IS computable by direct diagonalisation
behind a loud support-size gate. Decide: exact-on-bounded-support with visible
fallback, or close as "no tightening available at acceptable cost". Both
respectable; a silent 1-norm relaxation dressed as "the tight bound" is the
v0.1 `alpha_comm` bug class.

The extractor correctly flagged that Prop. 15/16 contain **no `r`** at all;
orchestrator supplied the missing telescoping proof for the distillation:
`U^r − V^r = Σ_{k=0}^{r−1} U^k(U−V)V^{r−1−k}` ⇒ `‖U^r−V^r‖ ≤ r‖U−V‖` by
unitary invariance, valid since `S₂(t/r)` and `e^{−i(t/r)H}` are both unitary.
Hence E2 r-step = `(t³/r²)[C₁₂/12 + C₂₄/24]`.

Sturm's CURRENT E1 (`Σ_{i<j}‖[H_i,H_j]‖`) is likewise a looser COROLLARY of
Prop. 15, not Prop. 15 itself — same computability caveat, same decision.

## ✅ TOBIAS RULED T1–T6 — *"approve it all"* — M11 IMPLEMENTATION UNBLOCKED

All six as recommended (full text in `m11-82su-synthesis.md` §10 banner):

- **T1** — replace PRD §5's `encode(ch, code) :: Channel → Channel` (and the
  §1445 P6 restatement) with the three typed operations. **This closes
  carried-contract verdict (c)** — the LAST one in plan §7 — so the reboot's
  contract audit completes: every carried v0.1 contract is now either
  re-derived (4), re-verified verbatim (1: Orkan FFI), or re-derived-at-M11
  (this one). Own reviewed pass, NOT inside M11 commits. **§4.4 goes two
  strata → three** (process values / channel **representations** /
  denotations) — the high-value edit, because today "`ctrl` cannot touch a
  channel" holds partly *for lack of any object to try it on*, and
  `KrausFamily` destroys that accident. The middle stratum must therefore
  carry the theorem explicitly: a channel's representation is non-unique
  exactly in the ways `ctrl` can see (Kraus freedom; Stinespring uniqueness
  only up to partial isometry; Tang–Wright), so controlling one would make the
  observable answer depend on an arbitrary representative.
- **T2** — `classicalise` gets its own §7 verdict **(c) re-derived**; name
  split `classicalise` / `record_distribution` stands.
- **T3** — **ship NO logical ops on a `CodeBlock`** (overrides proposer B).
  `not!`/`Bool`/`⊻=`/`dual`/`when`/`oracle` all refuse loudly. On a noisy
  block "transversal measure + majority" ≠ "decode then measure" — two
  different channels; offering either under the `Bool` cast spelling silently
  picks a protocol, i.e. F8 reappearing at the cast level inside the milestone
  meant to close F8.
- **T4** — `encode_state` is an **ownership transfer**, not a third
  consumption site; §4.5's "exactly two places" stands.
- **T5** — *"export what a program does to itself; `public` what the
  experimenter does to a program"* ⇒ export only `encode_state`,
  `decode_state`.
- **T6** — Orkan `unitary_kq` approved in principle, **after** M11; the
  KAK/QSD alternative needs its own 3+1 round (new constructor of controlled
  lowerings ⇒ must go through the `ctrl` choke point).

## M11 physics sources acquired (gitignored, per the new rule 4)

- **Watrous, *Theory of Quantum Information* §2.2.2** — the recommended
  Stinespring/Kraus citation: free, author-hosted, finite-dimensional (unlike
  Stinespring 1955's C\*-algebra setting, which is also paywalled). Verified
  locators: **Thm 2.22** Kraus↔Stinespring↔Choi; **Cor. 2.21/2.27** minimal
  Kraus rank = Choi rank; **Cor. 2.27(5)** the isometry form = exactly F33's
  `V|ψ⟩ = ΣᵢKᵢ|ψ⟩|i⟩`; **Cor. 2.23/2.24** non-uniqueness of the completion.
  Orchestrator spot-checked the title page and grepped the numbering.
- **Gottesman thesis (arXiv:quant-ph/9705052)** — stabilizer codes §3.2; its
  own §6.2–6.3 derives the threshold theorem, so no separate threshold source
  is needed. PDF + LaTeX source.
- Distillation lists reconciled 8 + 6 → **6**, two now sourced.

## M11 distillations — 3 of 6 written; and a P1 conflict found

`docs/physics/`: **`watrous_2018_channel_representations.md`** (461 lines — the
path PRD §4.4 already cites normatively), **`gottesman_1997_stabilizer_codes.md`**
(471 lines, quoted from `Thesis.tex`), **`repetition_code_effective_noise.md`**
(282 lines, an in-repo derivation note; every formula verified by exact rational
enumeration over all 2³/2³/4³ patterns — `depolarizing(1)` → logical
(¼,¼,¼,¼) is the sharp endpoint check).

**Version traps recorded** (both would have produced uncheckable citations):
Watrous is the 2018 CUP *pre-publication draft*, **PDF page = book page + 8**,
and the printed hardback is a different typesetting. Gottesman's local PDF
**title page says "2024"** — arXiv regenerates from TeX and `Thesis.sty`
typesets `\the\year` — so for that source **page numbers are build-dependent
while section/equation numbers are stable**; cite equations.

### ⚠ F3 — environment-ordering conflict (P1, filed)

**PRD-v2 line 2281 (§9) writes `V|ψ⟩ = Σᵢ Kᵢ|ψ⟩|i⟩_E` — environment
TRAILING**, following Watrous exactly (eq 2.77 / Cor 2.27(5): `A = Σ_a A_a ⊗
e_a`, output leading). **Synthesis S10 pins the OPPOSITE** — "environment wires
LEAD (MSB)", `Ṽ[i·d + s + 1, t + 1] = Kᵢ[s+1, t+1]`. Same channel (they differ
by the swap `Y⊗Z → Z⊗Y`, invisible to `Tr_Z`), **different matrices**. The
synthesis's own contract test `M11.DILATE.KRAUS-RECONSTRUCT` is true only in
S10's layout — in Watrous's the Kraus blocks are a **strided** extraction, not
contiguous rows — and Cor 2.24's freedom reads `B = (U ⊗ 1_Y)A` in Sturm's
layout, not the book's `(1_Y ⊗ U)A`.

**Keep S10, fix the documents.** Env-leading matches `Ctrl`'s control-leading
convention, so in the executable tier — where the environment IS the control —
the dense artifact and the structured emission agree with no permutation, which
is what lets the three-way test catch an ordering bug rather than be fooled by
two compensating ones. The next PRD pass must either restate §9 in Sturm's
order or add one explicit clause saying Sturm transposes the book's convention.
Without it a future agent WILL "fix" the code back to the book and break the
contract silently.

### Citation-precision items in the §4.4 block the T1 pass just landed

All three claims are TRUE and derivable from Watrous, but the citations do more
work than the source supports verbatim — worth correcting because this project
cites to be re-checkable:

- *"determined only up to a **partial isometry** on the environment"* —
  Watrous's strongest statement is **Cor 2.24, a UNITARY `U ∈ U(Z)` on a
  SHARED environment**. The partial-isometry form is Cor 2.24 **plus** an
  embedding step (pad both dilations into a common `Z`, licensed by Cor
  2.27(5) + the p.191 "iff `dim Z ≥` Choi rank"). Derived, not quoted.
- *"zero-padding to a common rank"* — Cor 2.23 already **assumes** a shared
  index alphabet; padding is the trivial reduction TO that hypothesis, which
  Watrous does not take.
- *"minimal Kraus rank = Choi rank"* needs a **two-part** citation: existence
  from Cor 2.21 / Thm 2.22(5),(7) / Cor 2.27(4),(6); the **converse** only
  from §3.3.4 p.191. Synthesis §7 and PRD §9 both write "Cor. 2.21 / 2.27" as
  if one locator sufficed.

### Three prerequisites remain unsourced — and this is a LIVE GATE

`knill_laflamme_1997_qec_conditions.md`, `chiribella_2009_quantum_combs.md`,
`eastin_knill_2009_no_universal_transversal.md`. The rule-4 boot lint greps
`src/` and asserts each cited `docs/physics/*.md` resolves, so **no `src/` file
may cite those three filenames until they exist** — M11 slices 5–6
(`qecc/codes.jl`, `qecc/superchannel.jl`, `qecc/ft.jl`) are exactly the ones
that would. All three are free arXiv (quant-ph/9604034; 0712.1325 / 0904.4483;
0811.4262) — the agent was write-restricted to `docs/physics/*.md` so it
downloaded nothing.

Two mitigations found on disk, both worth knowing:
- **Knill–Laflamme's physics is already local**: Gottesman §2.3 **eq (2.10)**
  states `⟨ψ_i|E_a†E_b|ψ_j⟩ = C_ab δ_ij`, proves it necessary AND sufficient,
  and attributes it. Only the projector form `P K_i† K_j P = α_ij P` that PRD
  §9 quotes belongs to the KL paper itself. Retargeting §9 to Gottesman is a
  normative PRD edit, not a distillation decision.
- **Combs (P4) has a real on-disk locator**: Watrous **Exercise 2.6(b)(c)**
  (pp. 121–122) gives exactly the `Ψ = Ξ₁(Φ ⊗ 1)Ξ₀` factorisation, credited to
  Chiribella–D'Ariano–Perinotti (2008) at p.123 — but it is **exercise**
  strength, unproved, and Sturm's `Θ = D∘R∘𝓝∘E` is its no-memory (`V = ℂ`)
  case. The agent correctly declined to create a `chiribella_*.md` on that
  basis, since it would mis-attribute a distillation.
- **Bonus, stronger than the synthesis claimed**: Gottesman §5.2 p.38
  explicitly calls M11's own recovery circuit **non-transversal**, which
  grounds S27 better than the synthesis's own argument. And `signs` on
  `StabilizerCode` is *grounded*, not merely prudent — §3.4 p.23, "Overall
  phase factors get dropped".
