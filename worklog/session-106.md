# Session 106 — 2026-08-06 — M11 SHIPPED (qmpo, slices 1–8, serial main-thread) + stale-clone recovery

Tobias: "fork serially by yourself through the issues. Assemble and keep the
big picture as you work, notice gaps, issues, raise beads." Serial main-thread
implementation (the session-105 mode); the 3+1 design obligation for M11 was
already discharged by the 82su round + rulings T1–T6, so this session was
implementer + self-review against the synthesis, slice by slice, one commit
and one targeted green run per slice.

## ⚠ Gotcha first: the local clone was a STALE PARALLEL LINEAGE

This machine's checkout was frozen at session 97 (2026-07-19) while sessions
98–105 continued on origin — and `git merge-base main origin/main` FAILED
(no common ancestor: the remote history was rewritten when the committed
physics PDFs were stripped, session 103). Symptoms: `bd ready` showed beads
(rlhj, 5hr7, i4ri, addq) that had shipped weeks earlier; I re-did rlhj's
9-finding PRD patch before noticing (remote 8890ded already had it —
verified identical finding coverage, my duplicate discarded).

Recovery, for the next agent who hits this:
- `git log --oneline origin/main | grep <bead>` BEFORE working any bead on a
  clone that might be stale; "ahead N, behind M" with both large = rewritten
  history, not divergent work.
- Local main hard-reset to origin/main (content-identical modulo the
  deliberately-untracked PDFs).
- The embedded Dolt DB was ALSO stale AND divergent; `bd dolt pull` still
  hits the session-97 merge-conflict wall. Fix that worked: `dolt fetch` +
  `dolt merge origin/main` + `dolt conflicts resolve --theirs issues
  dependencies` + commit, INSIDE `.beads/embeddeddolt/Sturm_jl` (the dolt
  CLI, not bd). Remote dolt was canonical (sessions 98–105 pushed it).
- **The git-committed issues.jsonl had rotted**: last export was session 98
  while the tracker advanced 7 sessions — the very file session 97 named
  "the canonical recovery source". Re-exported (347 issues) and committed;
  EXPORT THE JSONL AT EVERY SESSION CLOSE or the recovery story is fiction.

## M11 shipped — the slice ledger (all per docs/design/m11-82su-synthesis.md)

Suite: 8 commits c97401b..84104ca + runtests wiring; five new test files
(test_m11_{noise,stinespring,dag,qecc,analysis}.jl) now in runtests.jl.

1. **Values (S1–S8)**: `ChannelValue` stratum-2 tree — `KrausFamily{W,R,L}`
   (frozen row-major = Orkan kraus_t layout), `MixedUnitary{W,R}` (distinct
   dispatch class, ∘/⊗-closed), lazy `ChannelTensor`/`ChannelSeq` (V3:
   Orkan's only channel entry is 1-local, so lazy is load-bearing). TP at
   construction (1e-12, never renormalises); `channel(v)` quotient (total,
   no inverse); `same_channel` = Choi (never `isapprox`/`==`); nine
   convention-pinned named families; `reset_channel`/`pinch_channel` re-home
   density.jl's Kraus consts (principle 13).
   **Finding: `Base.:∘` has a `ComposedFunction` catch-all for ANY pair**, so
   mixed ProcessValue×ChannelValue composition CANNOT be left to MethodError
   — it silently builds garbage. Explicit ArgumentError refusal methods; the
   stratification test caught it (`⊗`/`ctrl`/`adjoint` are fine — Sturm-owned,
   no catch-all).
2. **Application (S3/S12/S13/S16/S29)**: `apply!(ctx, ch, wires;
   stinespring)` + `apply_noise!` handle layer (`noise!` is DAGBuilder
   vocabulary, V11); guard at the entries, never the shared 1q lowering (S3);
   DM native/exact with ChannelTensor recursion; Tracing records `NoiseN`
   with the REAL family (stinespring=true is a loud error — IR never holds a
   dilation); Eager loud naming density/shots/stinespring; `_replay_dm!`
   NoiseN branch through the full guarded entry. test_m5's placeholder
   "no NoiseN executor yet" pin flipped to assert the executed channel.
   test/choi.jl's `pinch_channel(q)` helper renamed `pinch_handle!` (it
   shadowed the new src constructor in Main).
3. **Stinespring (S9–S16, F33)**: `ChannelArtifact`/`StinespringDilation{W,E}`
   subtype NOTHING; env-leading pin (S10 — deliberately transposes Watrous;
   header says why the book layout must not be restored); Householder
   completion with bitwise-exact first-d columns (S9); catalogue class P
   (mixed-unitary; dense 1-local detection + `_u2_from_matrix` into kernel
   values; real-amplitude Ry prep tree + X-sandwich multiplex) / class D
   (amplitude damping, R1 sign verified against kernel Ry and pinned at
   MATRIX level — a −√γ K₁ is the same channel, invisible to Choi) / class X
   loud naming unitary_kq. Env region-owned, traced at exit (S15); DM
   `MixedUnitary{W≥2}` + stinespring=true routes to the emitter (exact on
   DM). 76 asserts green first run.
4. **DAG algebra (S28, risk R-c)**: ∘/⊗ on `ChannelDAG` with a NEW
   full-vocabulary remapper — R2 resolved as the synthesis suspected: the
   block-algebra remapper refuses barriers by design; this one covers all six
   node kinds, recursive into nested CasesN branch DAGs, with a
   bare-record-id upgrade path (found by the COUT-UNION test). The ∘ seam
   identifies id AND lineage (composites of endomorphisms certify). The
   negative control has teeth: naive concatenation of two independently
   traced DAGs (PortIDs genuinely collide — every trace numbers from 1)
   silently fuses wires: |00⟩ stays |00⟩ where proper ⊗ gives |++⟩.
5. **Codes (S17–S20, T3/T4)**: `StabilizerCode{N,K,S}` + signs + six GF(2)
   invariants (bitmask symplectic elimination, no floats);
   syndrome generator-1-=-LSB pin (matches the synthesis arm map; the M6 MSB
   pin governs WIRES, not this classical index — documented once in
   codes.jl); `verify_distance` brute force; `CodeEncoding` with the S20
   self-validating table; `bit_flip_code()` with the session-105
   Eastin–Knill honesty (d=1). `encode_state` = T4 ownership transfer via
   the `_instrument_record!` re-homing pattern — PLUS a pre-transfer
   `_flush_wire!` (a pending 1q fusion under the old WireID broke
   `_flush_all!`; the CODESPACE test caught it). Six T3 refusals.
   **Physics slip caught by a failing test**: XXX/ZZZ ANTICOMMUTE (odd
   overlap) — my invariant-5 violation example was a valid pair; the clean
   violation needs an S=0 construction.
6. **Superchannel (S21–S27, T1)**: `PhysicalChannel`/`LogicalChannel`
   (validated: arity, endomorphic lineage, NO cout — an instrument would
   smuggle a record into the syndrome path); callable `Protect`;
   `effective_logical_noise` = D∘R∘𝓝∘E spliced with the slice-4 ∘ under the
   NAMED code-capacity model; recovery = H-sandwich phase-kickback ctrl(word)
   extraction (any Pauli generator; −1 signs refused → Steane epic) + nested
   binary CasesN correction tree + NEW `trace_record!` builder verb + replay
   record-TraceN branch (the block accumulation, exact on DM);
   `physical_iid`; S24 refusal; TRANSFORM_REGISTRY with a registry-DRIVEN law
   testset (an entry without a law arm fails the suite). ft.jl: the
   five-ingredient Eastin–Knill refusal.
   Tests: Θ(bit_flip(p)^⊗3) = bit_flip(3p²−2p³) at 6 p's; TWO-SIDED
   break-even (p=0.6 hurts — a sign-flipped table cannot pass);
   phase-noise AMPLIFICATION (the wm28-shaped anti-test); the 4³ Pauli
   brute-force INDEPENDENT reference enumerator vs the executed Choi
   (principle 3); spec law assembled with NO slice-4 ∘ (independent negative
   control on the splicer).
7. **Analysis (S30/S31, T2)**: `classicalise` (arity from ports — the v0.1
   always-2×2 spec defect unrepresentable; exact by per-column DM replay;
   PHASE-BLIND flagged + the DELIBERATE classicalise(id)==classicalise(Ad_Z)
   test) vs `record_distribution` (DM-only, bitwise-no-backaction pin,
   non-consuming, distribution-never-a-value). S30 host twins: `select`
   scalar methods with the same totality messages **plus a host `zext`** —
   discovered necessary mid-test: the portable syndrome word is
   `zext(select(b1,1,0),Val(2)) + 2*zext(select(b2,1,0),Val(2))` and tokens
   cannot ride `select` branches (static values only, per design).
8. **M11.PORTABLE.SYNDROME**: ONE surface recovery listing runs under Eager
   (host scalars — all three single-X errors corrected), DM (exact: encode →
   inject X₂ → recover → decode ≈ J(id) on a coherent probe), and Tracing
   (MeasureN + CasesN materialise; DM replay reproduces the streamed
   behaviour). Plus the T2 carried-contract flip IN THE SAME LANDING: plan §7
   + PRD §10 row 7 → (a), counts → **6/1/0 — every carried v0.1 contract now
   has a closed verdict**.

## Gate run

PRD doctest lint 15/15 (no fence changes; table/prose edits only). All five
M11 files + m5/m8-channel/m8-passes/m8-tracing/m8-i4ri/m3/choi green on
targeted serial runs (never the full suite, per standing rule). Physics-cite
lint unaffected (new files cite watrous/gottesman/knill_laflamme/chiribella/
eastin_knill/repetition_code .md distillations — all resolve).

## Tracker

- `qmpo` CLOSED (this session). `udtl` had closed remotely (session 98-era);
  its guardrail-1 battery extended here (M11.NOISE.GUARDRAIL-1 through the
  new handle layer).
- Filed: **Steane epic** (P3 — CSS split, Cleve–Gottesman encoder synthesis,
  sign-aware extraction, real decoders; the −1-sign refusal in
  `_recovery_dag` points here), **Orkan unitary_kq T6 follow-through** (P2 —
  now unblocked, "after M11" is now; carries the R5 MIXED_TILED write-back
  verification), **SturmLinearAlgebraExt** Kraus compression (P4),
  **test-file standalone hygiene** (P4 — the i4ri/m3/m10 import couplings
  that bit the targeted runs).
- jsonl re-exported at close (the rot lesson above).

## Handoff

M0→M12-phase-5 all shipped; M11 closes the v0.1 carried-contract audit at
6/1/0. Ready next: `xmrd` (flat classical-SSA vocabulary), `pwsu`
(EnsembleChannel — the M12 promise), the new unitary_kq bead (cross-repo),
`eyho` (postselection surface), `h6p7` (uniform F_d dual), Steane epic.
The natural milestone path: M12 horizon items (hardware transport / QMod
duals) or the Steane epic on the fresh M11 machinery.
