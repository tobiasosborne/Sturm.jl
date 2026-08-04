# Session 105 — 2026-08-04 — nms1 + 42cs + c8rx closed (distillations; classicalise row 7; bench α-policy determinism)

Tobias: "continue work ... yourself serially ... hard challenging high
cognition work ... notice anything odd ... no coding/review subagents."
Chose `nms1` (the hard gate on `qmpo`/M11 slices 5–6). All five PDFs
downloaded to `docs/physics/` (gitignored — `git check-ignore` verified on
every one), all read in full on the main thread, three distillations
written, PRD §9 flipped to six-of-six ✅, `nms1` closed.

## Finding 1 — the Eastin–Knill slogan in PRD §5 overclaimed (fixed)

"No code admits a universal transversal gate set" is **false without the
hypothesis**: Theorem 1/Corollary 1 need the code to detect an arbitrary
error on any single subsystem/part (`d ≥ 2` for distance-`d`), plus
nontrivial encoding. Trivial escape: identity encoding, one block — every
unitary is transversal. And the escape is not hypothetical for us: **M11's
own `[[3,1,1]]` bit-flip code has `d = 1`, fails the hypothesis, and
carries a continuous transversal logical family** — `e^{iθZ₁}` acts on the
code space as `e^{iθZ̄}`, walking through exactly the proof step that
local error detection is supposed to close (`PHⱼP ∝ P` fails for
`Hⱼ = Zⱼ`). The bit-flip code's transversal non-universality is still
true but for an elementary reason (a product operator maps `|000⟩` to a
product state; `α|000⟩+β|111⟩` is entangled — so the transversal logical
group is just `⟨e^{iθZ̄}, X̄⟩`). PRD §5 refusal text now carries the
qualifier and the sentinel; the future `qecc/ft.jl` docstring must split
the citation: E–K for `d ≥ 2` caller codes, the elementary argument for
the acceptance example. Filed as distillation G1/G2, not a bead — it is
done, not pending.

## Finding 2 — the "projector form" `P Kᵢ†Kⱼ P = α_{ij} P` is not in the KL paper

Everyone (including our own PRD §9 entry and the Gottesman distillation's
G3) implied the projector *display* belongs to KL. It does not: arXiv
quant-ph/9604034v1 displays the **basis form** (Thm 3.2, eqs (19)–(20))
and derives `⟨i_L|A_a†A_b|j_L⟩ = α_{ab}δ_{ij}` inside the proof. The
projector spelling is the textbooks' (N&C Thm 10.1). Right physics, right
attribution of the *conditions* — but there is no KL equation number to
pin for that display, and a future agent hunting for it would conclude
the citation was fabricated. §9 entry and Gottesman G3 corrected.

## Finding 3 — combs pin discipline: the PRL asserts, the EPL proves

The PRL (0712.1325) states the realization converse only in **endnote
[16]** ("can be proved within an axiomatic introduction...") — no proof.
The single-slot factorisation `Θ(𝓝) = Tr_M[D∘(𝓝⊗id_M)∘E]` is **EPL
0804.0180 Theorem 1, eq. (23)**, proved; N-slot is PRA 0904.4483 Theorem
3. Watrous's p. 123 "CDP (2008)" credit resolves to the EPL paper, not
the PRL. Downloaded 0804.0180 on a hunch before reading anything —
confirmed. Best single sentence in the whole exercise: **EPL Application
1 states that error correction IS the supermap `S̃(E) = DEC` "with the
additional constraint that the ancilla B ... must be one-dimensional"**
— P4's memoryless-case license is a verbatim primary-source sentence,
not an inference chain.

## Bonus pins that will matter later

- **KL Thm 3.3** (left superoperator inverse) is *the* source for
  "`Θ(𝓝) = id_L` is the correctability statement, not a precondition";
  **KL Thm 3.4** (error 0 ⟺ completely entangled state fixed) is the
  primary-source license for Choi-level QECC tests.
- **KL Thm 5.3's sharp example**: `F_p = 1/3` while `F_e = 0` for
  `{σₓ,σ_y,σ_z}/√3` — the 1996 ancestor of the wm28 marginals-are-blind
  lesson, quotable in the M11 test-suite docstring.
- **KL §6 admits the code-capacity model** in one sentence ("assumes that
  no errors are produced during operations") — S27's honesty clause has a
  primary source now.
- **KL Thm 5.5's binomial bound requires `A₀ ∝ I`** — amplitude damping
  fails the hypothesis; never quote the classical bound for it.
- ⚠ KL "(n,k)-code" counts **dimensions**, not qubits ((2^r,2) = [[r,1]]).
- ⚠ Version traps, again, everywhere: KL local PDF is arXiv **v1** with
  its own numbering (PRA print renumbers); EPL/PRA local PDFs carry
  regenerated `\today` headers ("2018"/"2024" on 2008/2009 papers) — the
  Gottesman `\the\year` trap is a genus, not a species. Trust margin
  stamps; pin theorems, not header dates or print pages.
- Eastin–Knill is a NIST work, "not subject to US copyright" (p. 4) —
  rule 4 unchanged (uniform policy), noted for the record.

## Gate run

No `src/` change. PRD julia-fence parse pass: **13 fences, 0 failures**
(matches the session-99 pin). Rule-4 lint replicated by hand: all 25
`docs/physics/*.md` paths cited from `src/` resolve. `git check-ignore`
confirms all five new PDFs are ignored.

## Tracker

`nms1` closed (three distillations + §9 marks + lint green + no PDF
committed = its acceptance criteria, verbatim). `qmpo` (M11 slices) loses
its last distillation blocker.

---

## Second bead, same session — 42cs: classicalise logged as carried-contract row 7

Executed ruling T2 (2026-07-25, approved as recommended) per the bead's own
analysis: **added as (c) now**, not deferred to already-discharged at M11 —
the table's whole point is that a carried contract is visible *before* it
is consumed (F8 was catchable for exactly that reason). "Audit complete"
now explicitly means *every carried contract has an explicit verdict*, not
*every verdict is (a)*.

Edits, all four kept mutually consistent:

1. **Plan §7**: row 7 (`classicalise`, verdict **(c) — spec ruled S31/T2,
   gated on M11**) carrying the full S31 contract (arity from ports, exact
   by replay, loud above `CLASSICALISE_MAXWIRES`, PHASE-BLIND docstring
   flag + the deliberate `classicalise(id) == classicalise(Ad_Z)` test,
   `record_distribution` as the separate token operation) and the V10
   provenance: the defect is **in the v0.1 spec text itself**
   (`Sturm-PRD.md:457` — "returns 2×2 column-stochastic matrix").
2. **Plan §7 counts**: 5/1/0 → **5/1/1**, with the history chain
   (4/1/1 → T1 → 5/1/0 → T2 → 5/1/1) and the F31-enumeration hedge kept
   true: the *six F31 enumerated* remain fully audited; row 7 is the one
   F31's list missed.
3. **PRD §10**: matching summary row 7 + counts paragraph.
4. **PRD §5 QECC bullet**: "closure of the **last** carried-contract
   verdict (c)" was falsified by the new row — reworded to "closed the (c)
   on contract 6 (the last of the six F31 enumerated)" with a pointer to
   row 7. This was the only stale claim a repo-wide grep for
   last-(c)/zero-(c) phrasing found.

Follow-through made durable, not prose (session-104 lesson): `qmpo` now
carries a note that its classicalise slice must flip BOTH row-7 verdicts to
(a) and BOTH counts paragraphs to 6/1/0.

Gate: 13 PRD fences, 0 parse failures (no fence added — table/prose only).

---

## Third bead, same session — c8rx: wall-clock can no longer pick what the bench computes

The gmx0-era `probe_family` chose each (family, order)'s `alpha_mode` by
timing the exact-α DP against `PROBE_TROTTER_S = 0.2` / `PROBE_COMPOSITE_S
= 0.05` seconds — so mode selection was a function of machine load, and it
bit in session 103 (load ~20 downgraded five L=256 families the baseline
had planned exact). Fix, per the bead's ruled direction:

- **`alpha_policy` is now an explicit run configuration** —
  `run_frontier(; alpha_policy = :budgeted)` /
  `run.jl --alpha=exact|budgeted|norm1`:
  `:exact` (only the deterministic `AlphaCommBlowup` cap exit downgrades),
  `:budgeted` (default — the probe runs the SAME DP work-capped via
  `alpha_comm_layered`; `PROBE_WORK_TROTTER = 2^22`,
  `PROBE_WORK_COMPOSITE = 2^20` **propagation steps**, machine-independent;
  a budget stop records the proven partial bound `B_d` in the note),
  `:norm1` (no DP). `force_exact` (executed families) overrides any policy,
  as before. **Wall-clock survives only as a loud ABORT**
  (`PROBE_TIMEBOX_S = 600`, `:exact` only, with rerun instructions) — it
  never selects modes.
- Non-default policies get their own CSV tag (`frontier-all-exact.csv`) so
  runs under different policies can never shadow or be compared to each
  other by accident; the alpha CSV gains a `policy` column; the R4 summary
  prints the policy and the deterministic budget downgrades as their own
  category (cap hits stay separate).
- **The old determinism claim was false and nobody had noticed**: run.jl
  and README said "identical commands emit identical CSVs" while modes
  were load-dependent AND `probe_seconds` differs every run. Both now
  state the true claim: identical CSVs across machines and loads given
  the same policy, *except* the `probe_seconds` diagnostic column.
- RELATED item decided with it: `evolve!` docstring now documents the
  exact-α planning latency (5–12 s at L=1024 dense when Auto picks
  Composite; ranking stays budgeted-fast; escape = `plan_evolution`'s
  `alpha_mode = :norm1`). The planning-budget knob is NOT filed, per the
  bead ("only if it actually bites").

**Verification (all run, not asserted):** `--fast` twice under `:budgeted`
→ frontier/auto CSVs **byte-identical**, alpha identical modulo
`probe_seconds` (awk column-wise diff); `--fast` under all three policies
green with correct tags; `:norm1` semantics checked in-CSV (48 executed
rows exact via force_exact; 40 analytic rows norm1; the 8 analytic
`:exact` rows are QDrift, which consumes no α); budgeted==exact on the
fast subset (no downgrades there, so the CSVs must and do agree);
`probe_family` twice on exp-L1024-W16 → identical downgrades with `B_2`
recorded. Sturm loads and the new docstring renders.

**Measurement that settled the calibration** (steps, not guesses):
L=256 order 2 costs **2^19.3 steps** (inside both gates — this is the row
class the wall threshold flipped under load; first-call *compile* alone
pushed 0.06 s → 0.52 s across the old 0.2 s line, so the load lottery
included compile noise); orders 4/6 cost **2^23.5 / 2^25.8** (≈2 s / 12 s
wall) — out of reach under either regime, deterministically `:norm1` now.
Same steps, different walls across boxes (jpky's box: 2^20 ≈ 25–50 ms;
this one: 0.1–0.2 s) — which is exactly why steps are the unit.
