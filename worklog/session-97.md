# Session 97 — 2026-07-19 — GPT-5.6 adversarial PRD review triaged + 6xdk RULED

## HANDOFF — state at session close

**Where we are:** Tobias commissioned an external adversarial review of
`Sturm-PRD-v2.md` + the implementation plan (`codex exec -m gpt-5.6-sol`,
reasoning xhigh, read-only sandbox; he was explicitly willing to dump
M0–M7 and restart if it surfaced structural blockers). **Verdict: NO
RESTART.** The reviewer's conclusion and the orchestrator's independent
verification agree: the core architecture (phase-fixed process values,
consuming casts, Pontryagin views, ctrl choke point) survived — the
review's own non-findings list confirms every load-bearing physics claim.
The serious findings cluster at **M8/M9, which don't exist yet**. In every
case where the spec self-contradicts, the shipped code already chose the
sound side (structural `==` + semantic `≈`; DM scalar measurement rejected
loud). Full report archived: `docs/design/prd-v2-review-gpt56-2026-07-19.md`
(37 findings, F1–F37). Triage below; beads filed.

**⚠ M8 (szx1) IS NOW GATED** on two P0 design beads (noted on szx1 itself
because `bd dep` is broken — see tracker-degradation gotcha):
- **`5hr7`** — UnitaryDAG port typing + STRUCTURAL clean-ancilla
  certificate + phase-preserving pass contract (review F1/F2/F3). Key:
  the M5 Eager |1⟩-marginal assert is sound fail-fast *per-run*
  enforcement (verified against the reviewer's adversarial CNOT case —
  it fires loudly), but Tracing cannot run state assertions, so M8 needs
  matched-compute/uncompute or Perm-by-construction certificates; and
  Choi comparison is phase-blind, so pass tests must ALSO compare
  ctrl-wrapped pre/post values or the Cirq/Qiskit controlled-phase bug
  class re-enters via the pass pipeline.
- **`i4ri`** — the classical-control IR (review F4/F5/F6/F13/F30). The
  §3.6 "traced classical computation" story needs an explicit mechanism
  (staged lifting vs restricted classical SSA/CFG à la Jasp); `cases`
  needs branch-join typing + a token-correlation record (block-
  accumulating immediately destroys ∑ᵢ|i⟩⟨i|⊗ρᵢ for reused tokens); the
  §3.8 portability table's "DM ✓ for if/&&" contradicts
  DM-executes-channels (code already rejects it — the TABLE is wrong);
  `Bool(q)::ClassicalBit` violates Julia constructor convention and the
  promised `if token` error is unimplementable (Julia's own TypeError
  fires; not interceptable) — needs a Tobias-grade idiomaticity ruling.

**Other beads filed this session:** `addq` P1 (M9 mulmod! is NOT a
permutation on the padded space — N=15: 0 and 15 both ↦ 0 — plus the
in-place-Perm contract doesn't exist; blocks 8oo9's QMod arm, noted
there); `rlhj` P1 (PRD accuracy patch round: F9 U(d)-not-SU(d), F12
prep-cast-under-when contradiction, F10/F11 foundations wording, F14
effectful-`+`-on-views honesty, F25 Choi cap is 2× wrong — 15-wire Choi
needs a 2^60-entry DM, real cap ≈7 wires, F26/F27 equality wording, F36
`using Bennett`); `w6z0`-class P2s: plan rebaseline + v0.1-contract
consolidation pre-M8 (F31/F34/F35), rulings bundle (F15 numeric
contract / F19 bicharacter trait / F16 `QBool{C}` context parameter —
cheap now, invasive post-M8), M11 QECC superchannel typing (F8/F33),
D6 split (F37 — GOOD news: uniform cyclic F_d dual is unblocked for all
d; parity traps are Clifford-layer only); P3 hygiene sweep
(F28 freeze Perm / F29 dedicated duplicate-control error / F17
ownership docs / F32 CV-anyon hedge). Findings verified AGAINST CODE and
downgraded where the code already fails loud: F17 (dangling handles die
at abstract.jl dead-wire check), F29 (duplicate/conjugate nested
controls die at the `_act!`-prepends-full-stack aliasing backstop).

**6xdk RULED AND SHIPPED** (Tobias: "choose whatever is easiest"; the
GPT-5.6 reviewer independently adjudicated identically — F20): the M6
wire-1=MSB pin WINS (kernel-wide). Applied: PRD §7.5 readout is now
`evalpoly(2, reverse(bits))` + an endianness-ruling paragraph; **§7.7
Shor had the SAME bug** (review F21, previously unnoticed): `for j in
1:2W` gave wire 1 (MSB) the a^(2^0) factor, computing a^bitrev(k) —
loop reversed to `2W:-1:1`. `test_m7_bennett.jl` BV testset extended
from palindromic {0,2,5} to ALL 8 3-bit secrets (non-palindromic
1/3/4/6 were the blind spot; new fixtures bv_s1/s3/s4/s6/s7).
**Verified: targeted run 239/239 green** (PRD doctest lint + M2 helpers
+ choi.jl + full M7 file; driver in scratchpad, temp-env
Pkg.develop(Sturm)+develop(Bennett) pattern works).

**Next step:** claim `5hr7` + `i4ri` (the M8 design gates, 3+1-grade
design rounds, no code), or the cheap `rlhj` PRD patch round first.

## Gotchas / learnings

- **Tracker is DEGRADED — handle with care.** (a) The local embedded
  Dolt DB was missing recent state (6xdk absent!) until
  `bd import .beads/issues.jsonl` restored it — **the git-committed
  jsonl is the canonical recovery source.** (b) `bd dep add` errors with
  `table not found: wisp_dependencies` (schema table missing in the
  embedded DB) — dependency wiring is currently IMPOSSIBLE; gates were
  recorded as `--notes` on szx1/8oo9 instead. (c) `bd dolt push` is
  rejected (local behind remote) and `bd dolt pull` hits a merge
  conflict that embedded mode can't resolve (`@autocommit` rollback).
  Next session: consider `bd init --force` + re-import from jsonl, or
  server mode. The jsonl in git holds everything (318 issues,
  19 memories, exported this session).
- **bv_s7 (three-term parity) Bennett-compiles past 24 wires** — the
  verbatim BV test needs `eager(26)` (2^26 statevector ≈ 1 GiB,
  transient, fine). Capacity errors from `eager(cap)` are loud and
  name the fix.
- **Targeted-run recipe that works** (no Pkg.test, serial, OMP=16):
  temp env + `Pkg.develop` both Sturm and Bennett, then include in
  runtests order: `test_prd_examples.jl`, `test_m2_common.jl`,
  `choi.jl`, `test_m7_bennett.jl`. ~65 s wall.
- **codex exec pattern for external review:** `-m gpt-5.6-sol
  -c model_reasoning_effort="xhigh" -s read-only -o <report.md>`,
  prompt via stdin, ran ~35 min, ~30 tool calls, zero retries. Prompt
  archived in the report's provenance header. Worth repeating at M8
  design time.

## Review triage summary (orchestrator's independent assessment)

Reviewer rated 9 findings P0; after verification against spec + shipped
code the honest split is:

- **Genuine P0 design gates (pre-M8/M9):** F4+F6+F5+F30+F13 → `i4ri`;
  F2+F1+F3 → `5hr7`; F7 → `addq`. None invalidate shipped code.
- **Real-but-cheap spec fixes:** F20/F21 (SHIPPED this session),
  F9/F10/F11/F12/F14/F25/F26/F27/F36 → `rlhj`.
- **Rulings/design-debt:** F15/F16/F19, F8/F33, F31/F34/F35, F37.
- **Downgraded after code check:** F1 (Eager check is sound fail-fast;
  the gap is Tracing-side), F17/F29 (fail loud today), F13's TypeError
  half (Julia names the token type in its native error).
- **Reviewer misses:** none material found; its non-findings section
  (boundary algebra, U2 double cover, ctrl homomorphism, Perm closure,
  views-unwrap, MBU exclusion, silent trace, teleport/injection
  circuits all confirmed sound) is the strongest no-restart evidence.
