# Session 96 — 2026-07-10 — M7 SHIPPED (Bennett bridge) + bead hygiene sweep

## HANDOFF — state at session close

**Where we are:** M7 (Bennett bridge, bead 7a0v) shipped via the full
orchestrated 3+1 pattern; suite green at **14,965 tests (+254)**,
orchestrator-re-verified independently. `oracle(f, x)` compiles ordinary
Julia through Bennett.jl → kernel `Perm`; `b ⊻= oracle(f, x)` is the D9
accumulate; DJ §7.4 and BV §7.5 execute VERBATIM from the PRD. The M5
`when`-controlled-oracle IOU and the §3.4 MBU-exclusion named test are
both discharged. Bead hygiene: `bd ready` now surfaces ONLY post-reboot
work (4 closed as mooted incl. wm28; 82 deferred with label
`v0.1-quarry` until 2026-12-31).

**Next step: M8 (Tracing/UnitaryDAG/cases/passes, bead szx1)** — was
already unblocked in parallel per plan; M8 owes the cases/noise
`_assert_no_control` hooks and the streaming ≡ materialized Choi law
(M5 IOU #2). Note `bkv` (speculative tracer) and `7kg` (pass
equivalence harness) are pre-reboot beads left open deliberately —
both are M8-adjacent content; triage them when claiming szx1.

**⚠ OPEN P1 RULING NEEDED (bead 6xdk): PRD §7.5 BV example is
bit-reversed.** The verbatim example returns `reverse_bits(s)` for
non-palindromic secrets under the M6 wire-1=MSB pin
(orchestrator-reproduced, all 8 3-bit secrets: s=1→4, s=3→6, s=4→1;
the PRD's own s=5 is palindromic and masks it). Root cause: the
example's `# s, LSB-first` comment assumes `x[i]` is LSB-first —
contradicting the M6 endianness pin. The PRD is normative; do not
patch it without a ruling. Tests pin palindromic secrets (0, 2, 5)
meanwhile, matching what the PRD actually asserts.

## M7 — what shipped

- `src/bennett/bridge.jl` (core, names NO Bennett type): `CompiledOracle`
  (Perm + role tables, x-independent) + `OracleQuery` (adds live handles);
  `oracle` + write-once `_BENNETT_BACKEND` hook (mirrors Bennett's own VM
  hook); `Base.xor(::AbstractQubit|::QInt{Wb}, ::OracleQuery)` with the
  actions.jl return-value discipline; `_apply_oracle!` choreography;
  `_free_clean!` = assert-|0⟩-then-drop-slot, NEVER measure.
- `ext/SturmBennettExt.jl` (weakdep; the ONLY file naming Bennett types):
  `reversible_compile(f, covering_type; bit_width=W,
  auto_self_reversing=false)`; four loud compile rejections
  (non-`ReversibleCircuit`/VM → D14; dirty `loop_check_wires`; in∩out
  overlap; output-read-as-control (per-circuit D9 re-verification));
  NOT/CNOT/Toffoli → MCX; `_role_tables` = THE single MSB/LSB remap.
- Kernel seam (the milestone's one core change, 3+1-gated): additive
  `AbstractVector{WireID}` siblings of `apply!`/`_act!` — `Perm` wire
  count is runtime data (up to ~749 observed); `NTuple{n}` would
  type-explode.
- Boot-lint: `input_wires[`/`output_wires[` indexing allowed ONLY inside
  `_role_tables` (function-scoped, self-tested, non-vacuous).
- `Project.toml`: `[weakdeps]`+`[extensions]`+`[compat]` Bennett, and the
  Julia 1.11 `[sources] Bennett = {path = "../Bennett.jl"}` mechanism for
  the unregistered dep — worked first try; `Pkg.test()` resolves Bennett
  v0.5.0 + LLVM into the test manifest; `using Sturm` alone never touches
  LLVM (verified: core loads, `oracle` stub errors loud).

## The 3+1 round — what each stage caught (the pattern keeps paying)

- **Proposal B's decisive empirical find:** Bennett couples OUTPUT width
  to the compute width `W` — a Bool-valued `f` at `bit_width=W` emits a
  W-bit output block, `f(x)` in bit 0, zero-extended. Proposal A's
  exact-width-match contract could not express DJ at all. Ruling adopted
  B's contract: `b` sets `Wb ≤ W`, low bits accumulate, the high tail is
  the **zero-tail |0⟩ witness** — an under-sized `b` fails LOUD instead
  of silently decohering `x` (verified: `QBool ⊻= oracle(x->x+1, x=3)`
  throws; `x=0` passes).
- **Proposal A's decisive catches:** B's `objectid(f)`-keyed cache is a
  correctness footgun (GC can recycle an objectid → silent wrong-oracle
  hit) — M7 ships NO Sturm-side cache; and B's loop-reject error text
  overpromised ("raise max_loop_iterations" does NOT remove the guard
  for genuinely data-dependent loops — probe-proven).
- **Both blind proposers independently** argued PAST the audit's weaker
  rule to **unconditional** loop-check rejection, from the same physics:
  the convergence flag is x-correlated garbage the user cannot reach;
  tracing it decoheres superposed inputs invisibly to marginals (wm28
  class); the type system cannot distinguish definite from superposed x.
- **Implementer's find (→ bead 6xdk):** the PRD §7.5 bit-reversal above.
- **Orchestrator review:** independently re-ran the suite (14,965 green),
  reproduced the BV reversal on all 8 secrets, verified the Bennett UUID,
  read bridge/ext line-by-line.

## Gotchas / learnings (future agents)

1. **Bennett is positionally little-endian** (position 1 = LSB in
   `input_wires`/`output_wires`); Sturm pins wire 1 = MSB. Remap =
   per-block reversal `sturm bit j ↔ bennett position W−j+1`, in
   `_role_tables` ONLY (lint-enforced). Probe:
   `docs/design/bennett-bit-order-probe.md`, re-validated at Bennett HEAD
   `b6f13802` after Tobias pulled mid-session (artifact files
   `gates.jl`/`simulator.jl`/`bennett_strategies.jl` byte-identical
   across the pull; all ~30 new commits are compiler front-end).
2. **`optimize=false` is required to exercise loop guards in tests** —
   the default optimizer folds simple countdowns to closed form (empty
   `loop_check_wires`) and a naive suite silently tests the wrong path.
3. **`reversible_compile(f, UInt8)`**, not a tuple form; width via
   `bit_width=W` (genuine mod-2^W narrowing, verified).
4. **Anonymous closures capturing runtime data don't Bennett-compile**
   (`x -> s·x` with captured `s` → `IRLoad` narrowing error, loud and
   correctly attributed). Test oracles must be top-level literal
   functions. UX papercut, Bennett-side (Bennett-2unc / U85).
5. **`_free_clean!` vs `deallocate!`:** outside a control stack
   `deallocate!` measure-and-discards — it would silently collapse an
   x-entangled dirty wire and MISS the under-sized-b bug. Assert-then-drop
   is uniform under/outside `when` and loud on dirty. This is why the
   zero-tail witness works.
6. **DM Choi is infeasible for oracle-sized circuits** (3-bit f → 10–25
   wires; 2^{2n} DM). The "exact on DM" intent is met with exact Eager
   statevector amplitudes/marginals (no sampling) + basis-exhaustive
   permutation equivalence (a Perm is phase-free ⇒ basis-exhaustive =
   channel). Documented in the test-file CAPACITY NOTE.
7. **The `[sources]` mechanism (Julia 1.11) handles unregistered
   weakdeps in the test target cleanly** — `[weakdeps]` + `[extras]` +
   `[targets] test` + `[sources] path`. No Requires.jl, no hard dep.
8. **Bead-tool gotcha:** `bd label add` takes `[issue-id...] [label]`
   (label LAST) — a label-first call mislabeled 81 issues with a bead id
   as the label (caught and reverted same session via `bd label list-all`).

## Bead hygiene sweep (sedj)

Closed as mooted: wm28 (v2 ships Choi-level teleport tests), 2i0
(ScopedValues already shipped), hlk (regions replace finalizers), 7pz
(exact atomic X in kernel). Deferred 82 v0.1-era beads to 2026-12-31,
label `v0.1-quarry` (QSVT/4ceh cluster, QMod/qudit, Shor follow-ons,
Sextant/viz epic, old review nits — matches the plan's "M12+ horizon"
line). Left open deliberately: bkv, 7kg (M8-adjacent content).

## Beads filed this session

- **6xdk (P1, bug):** PRD §7.5 BV bit-reversal — NEEDS RULING.
- fy8l (P2): QBool-input + multi-register oracle.
- id8p (P2): Bennett full-suite hardening gate on project Julia.
- hh3t (P3): signed covering type.
- nr00 (P4): loop-oracle admission via all-converged witness.
- (closed this session: eq0a distillations, rnzk probe, sedj sweep,
  7a0v M7 itself.)
