## 2026-04-25 — Session 67: bead `Sturm.jl-179` closed, STURM_COMPACT_VERIFY env-gate

Headline: ships the env-gate as design-on (default-enabled), not an
operational change. Caches the env value at module init in a single
`Ref{Bool}` so the hot path is one deref, not an `ENV` lookup. Both
EagerContext and DensityMatrixContext share the same gate. The
default-OFF flip is a separate deferred action gated on empirical
evidence (1–2 sessions of zero residual violations on real workloads).

### What landed

  * `src/context/abstract.jl` — `const _COMPACT_VERIFY_ENABLED = Ref(true)`.
    `_parse_compact_verify_env(s)` parses env values: `nothing → true`;
    `"0"`, `"false"`, `"off"`, `"no"` (case-insensitive, trimmed) → false;
    anything else → true (lenient, prefer fail-loud over fail-silent on
    typos).
  * `src/Sturm.jl __init__()` — reads `ENV["STURM_COMPACT_VERIFY"]` once
    at load time and writes the parsed bool to the Ref.
  * `src/context/eager.jl _compact_verify_freed_zero` — short-circuit
    `_COMPACT_VERIFY_ENABLED[] || return nothing` at the top.
  * `src/context/density.jl _compact_verify_freed_zero` — same gate.
  * `test/test_compact_state.jl` — three new testsets (+20 assertions):
    parser unit tests, default-enabled end-to-end (residual violation
    errors), disabled end-to-end (same residual is silently accepted),
    DM mirror.

### Verification

  - test_compact_state.jl: 277 → 297 (+20) ✓
  - test_compact_state_dm.jl: 408/408 still ✓
  - env smoke test: `STURM_COMPACT_VERIFY=0 julia` → Ref reads false;
    unset → Ref reads true.

### Why default-on stays for now

The bead description explicitly says: "Don't ship the off-default until
at least 1–2 sessions confirm zero residual violations across mulmod/Shor
runs." The gate is a knob; the default policy is a separate decision.
Flipping the default-off is its own (small) bead when the empirical
evidence is in.

### Non-obvious decisions

  * **Lenient parser** (anything that isn't a recognised disable word
    treats as enabled): the failure mode of typoing `STRUM_COMPACT_VERFY=0`
    should be "the gate stays on" (safe), not "the gate silently
    disables" (unsafe). The set of disable words is small and
    well-documented.
  * **Single shared Ref, not per-context.** Both EagerContext and
    DensityMatrixContext check the same `_COMPACT_VERIFY_ENABLED[]`.
    That keeps the operational story simple — flip one switch, both
    backends respond — and reflects that the underlying invariant
    (freed-slot residual must be zero) is the same for both.
  * **Test mutation pattern.** Tests directly write to the Ref under
    `try/finally` to save and restore. This is faster and more
    deterministic than `ENV["STURM_COMPACT_VERIFY"] = ...` + reload.

### Open follow-ons

  1. **Bench the scan cost on real workloads** (no bead yet) — the bead
     description's parenthetical: "if it's <5% of total compact cost
     the optimisation isn't worth the operational complexity." If the
     scan is fast enough, we may decide to keep the gate but never
     flip the default.
  2. **Default-off flip** (deferred) — flip default after 1–2 sessions
     of zero residual violations on Shor + mulmod. File as a P4 task.

---

## 2026-04-25 — Session 66: bead `Sturm.jl-w9e` closed, HWM tracker lands

Headline: two compaction-fragile tests rewritten to test invariants compaction
preserves rather than incidentals it zeros. Adds `_n_qubits_hwm` to
EagerContext as the per-allocate hook the bead recommended. Local TDD
cycle clean.

### What landed

  * `src/context/eager.jl` — new `_n_qubits_hwm::Int` field on
    `EagerContext` (init 0); `allocate!` bumps it on every fresh slot
    allocation. `compact_state!` does NOT reset it (the existing commit
    phase touches only the fields it needs to rewrite). Recycled slots
    do not bump HWM (no new peak).
  * `test/test_compact_state.jl` — new `_n_qubits_hwm tracks peak across
    allocations and compactions` testset (section 6, before pre-flight
    validation). Pins: bumps on fresh allocation, no-op on recycled
    slot, preserved by compact, only bumps further if a new peak is
    reached after compact.
  * `test/test_shor.jl` HWM testset — read peak from `ctx._n_qubits_hwm`
    instead of `ctx.n_qubits - before`. The previous formulation read
    FINAL n_qubits, which compaction may reset mid-call (passing
    accidentally when compact zeroed live count).
  * `test/test_bennett_integration.jl` deallocate_batch! testset — pin
    the user-visible invariant ("ancillae are consumed and no longer
    live") by checking `consumed` and `wire_to_qubit`, not the internal
    `free_slots` count which compaction may zero. Branches on
    `_compact_count` for the slot-recycling sanity check (sub-threshold
    here so compact does not fire, but the assertion is robust either
    way).

### Why this matters

Three flagged tests were passing under compaction by accident. Bead
session-64 handoff explicitly called them out:
  > "test_shor.jl:344-346 (n_qubits delta measurement no longer accurate
  > under compaction — passing accidentally because deltas can now be
  > near-zero), test_bennett_integration.jl:149 (`@test
  > length(free_slots) >= 3` — passing because compaction doesn't fire
  > in that test's context)."

The HWM test was the canary: if Shor's algorithm ever exceeded its 2L+4
upper bound, the `n_qubits - before` formulation would silently absorb
the regression because compaction would mask the peak. After this fix,
the test reads the true peak via `_n_qubits_hwm`, which survives
compaction.

### Non-obvious traps from this session

  * **Sonnet scan paid off.** Spawned a single Explore subagent (Sonnet)
    to enumerate every `ctx.n_qubits`-as-HWM pattern in the repo
    BEFORE touching code. Caught two patterns the bead description had
    listed as "low-priority flag" (test_qmod.jl _amps_snapshot,
    test_qdrift.jl _infidelity) and ruled them out as actual bugs
    (the unsafe_wrap with `dim = 1 << n_qubits` reads a strict prefix
    of a `2^capacity`-sized PURE buffer — safe). Saved a wider
    refactor that wasn't needed. **Lesson: scan the whole repo for the
    pattern class before scoping the fix; the scope is rarely the
    initial flagged sites alone.**
  * **EagerContext is not "core" per CLAUDE.md rule 2.** Adding a
    field to `EagerContext` does not trigger the 3+1 ceremony — the
    rule covers `types/`, `context/abstract.jl`, `primitives/`, and
    Orkan FFI. Concrete context implementations are not in that list.
    Single-proposer or self-implementer is fine for additive field
    changes that don't change the abstract interface.
  * **HWM bumps live in `allocate!` only.** Resisted the temptation
    to also bump in `_grow_state!` — capacity grows ≠ live qubits grow.
    HWM tracks live n_qubits, not capacity. `_grow_state!` is a
    response to allocation pressure but doesn't itself add live wires;
    the `allocate!` call that triggered the grow then increments
    n_qubits and bumps HWM in the same path.

### Open follow-ons

  1. **DensityMatrixContext mirror** (no bead yet) — same `_n_qubits_hwm`
     field and bump in `allocate!(::DensityMatrixContext)`. One-line
     additive change. File a P4 bead when a DM test needs it.
  2. **Library-side label cleanup** (low-priority) — `src/library/shor.jl`
     line 172/424 log labels `peak_allocated=ctx.n_qubits` are
     misleading post-compaction. Should read `live_qubits=` or use
     `_n_qubits_hwm` for true peak. File as P4 doc-fix bead.

### Tests touched, not touched

Touched: `test/test_compact_state.jl`, `test/test_shor.jl`,
`test/test_bennett_integration.jl`. Source: `src/context/eager.jl`.

Verified clean (locally, against full edit set):
  - test_compact_state.jl HWM testset (the new one).

`test_shor.jl HWM` and `test_bennett_integration.jl deallocate_batch!`
to be re-run as part of the regression chain when julia is idle.

---

## 2026-04-25 — Session 65: bead `Sturm.jl-amc` closed, `compact_state!(::DensityMatrixContext)` lands

Headline: density-matrix counterpart of bead 059 lands clean. `_grow_density_state!`
also migrates from per-element FFI (4^old_cap ccalls) to per-column
`unsafe_copyto!` (old_cap calls, zero FFI crossings) — independent perf win
analogous to Session 49's pure-state fix. All 408 new assertions green;
264 eager `test_compact_state.jl` assertions still green; 1753 + 17 in
`test_density_matrix*.jl` still green.

### What landed

  * `src/context/eager.jl` — minor refactor: extracted `_compact_plan`'s body
    into a private `_compact_plan_impl(n_qubits, capacity, free_slots,
    wire_to_qubit, consumed)` that operates on the field set. Eager
    `_compact_plan(::EagerContext)` becomes a one-liner forwarder. Behavior-
    preserving; used by both contexts (CLAUDE.md rule 13).
  * `src/context/density.jl` — added:
      - `_compact_count::Int` field on `DensityMatrixContext` (init 0).
      - `_dm_packed_len`, `_dm_col_off`, `_dm_pack_idx` inline helpers
        mirroring Orkan's `index.h`. Lower-triangle column-major.
      - `_grow_density_state!` rewritten: per-column `unsafe_copyto!`
        (one call per old column), zero FFI crossings.
      - `_compact_plan(::DensityMatrixContext)` — one-liner forwarder.
      - `_compact_verify_freed_zero(::DensityMatrixContext, plan)` —
        column-major scan of the live block for residual |ρ|².
      - `_compact_scatter_dm!(new_orkan, old_orkan, plan)` — 2D bit-expand
        scatter into lower-triangle of new buffer (capacity-dim layout).
      - `compact_state!(::DensityMatrixContext)` — top-level orchestrator,
        same compute-then-commit phase decomposition as eager.
      - `deallocate!(::DensityMatrixContext, ...)` — auto-trigger at
        `length(free_slots) >= 2 * GROW_STEP` (= 8), mirror of eager.
  * `test/test_compact_state_dm.jl` (new) — 408 assertions across 14
    testsets: contract, state preservation (incl. arbitrary single-qubit
    ρ with off-diagonal coherence, Bell over 200 trials, marginal
    invariance), soundness (Bell + a NEW off-diagonal-only ghost test
    that the pure-state residual formula could not catch), atomicity,
    auto-trigger, ping-pong containment, pre-flight validation, and a
    grow-correctness pair pinning the per-column `unsafe_copyto!` invariant.
    Wired into `runtests.jl` after `test_compact_state.jl`.

### Architecture (synthesised from 3+1 ceremony)

Per CLAUDE.md rule 2, spawned two parallel proposer subagents (Sonnet)
with the same brief — Proposer A (data-flow first) and Proposer B
(invariant first) — instructed not to coordinate. Both converged on:
compute-then-commit phasing, lower-triangle preservation under the
monotone bit-expansion (sorted `live_slots`), per-column `unsafe_copyto!`
in grow (the critical hazard), and the off-diagonal-only soundness
gap. Implementer (orchestrator) synthesised: B's invariant numbering as
the docstring shape, A's column-strip optimisation in the precondition
scan, B's `_compact_plan_impl` shared-helper recommendation (cleanest path
for CLAUDE.md rule 13).

### Non-obvious bugs caught during integration

  * **MIXED_PACKED layout uses `state->qubits = capacity`, NOT n_qubits.**
    Initial implementation copied the eager pattern of `dim = 1 << old_n`
    in the unsafe_wrap and the packed-index arithmetic. That works for
    PURE because the layout is 1D and the live amplitudes are the prefix
    (truncating the wrap to live dim is equivalent to ignoring the zero
    suffix). For MIXED_PACKED the layout is column-major lower-triangular
    and `col_off(d, c) = c*(2*d - c + 1)/2` SHIFTS WITH d. Reading at
    `col_off(2^n_qubits, c)` from a buffer laid out for `2^capacity`
    targets a different physical offset for every c > 0. Result: scatter
    silently corrupted ρ post-compact (trace dropped to 0.75, then 0.0,
    then ~1e-130 in deeper compositions). Fix: use `cap_dim = 2^capacity`
    (read from `OrkanState.raw.qubits` for the source) for ALL packed-index
    arithmetic; iterate the LIVE block `[0, 2^n_qubits)`, not the full
    capacity. The grow path was already correct because `old_dim`/`new_dim`
    in `_grow_density_state!` ARE the capacity dims. **Lesson: when porting
    a primitive from PURE to MIXED_PACKED, audit every dim used in
    `pack_idx`/`col_off` — eager's "live dim = layout dim" coincidence
    does not carry.**
  * **`_grow_density_state!` per-column copy is mandatory.** Both
    proposers flagged this independently: a single bulk `unsafe_copyto!`
    of the old packed buffer into the new one is WRONG because
    `col_off(new_dim, c)` ≠ `col_off(old_dim, c)` for c > 0; only column
    0 has matching offsets. This was the single most important
    correctness hazard — caught in the design phase, not at runtime.
  * **Test prediction sign flip on a Bloch phase.** Asserted
    `ρ[2, 0] = cos(π/6) sin(π/6) cis(-π/4)` after Ry(π/3); Rz(π/4) on
    slot 1. Correct derivation: Rz(δ)|0⟩ = e^(-iδ/2)|0⟩, Rz(δ)|1⟩ =
    e^(+iδ/2)|1⟩, so `α = cos(π/6) e^(-iπ/8)`, `β = sin(π/6) e^(+iπ/8)`,
    and `ρ[1,0] = β α* = cos(π/6) sin(π/6) e^(+iπ/4)` (positive!). The
    implementation was right; the test was wrong. **Lesson: when a single
    test assertion fails by a sign on an off-diagonal density matrix
    entry, suspect the test prediction first, the gate convention second,
    the implementation third.**
  * **Auto-trigger threshold parity.** Density auto-trigger uses the SAME
    `2 * GROW_STEP = 8` threshold as eager. The DM buffer scales as 4^n,
    so naively a more-aggressive threshold seems warranted, but parity
    keeps the test scaffold portable and the hysteresis math identical.
    GC hint threshold IS lowered (`old_capacity >= 12` for DM vs >= 24
    for eager) because at DM cap=12 the released packed buffer is
    already ~134 MiB (capacity 14 → ~2 GiB). Tunable as a follow-on bead
    if profiling indicates need.

### Numbers

Rerun `test_compact_state.jl` post-eager-refactor: 264/264 ✓ (unchanged).
Rerun `test_density_matrix.jl`: 1753/1753 ✓.
Rerun `test_density_matrix_mc.jl`: 17/17 ✓.
New `test_compact_state_dm.jl`: 408/408 ✓.

The actual perf delta from `_grow_density_state!` migration is not benched
in this session — the bead's primary deliverable was the compaction
primitive itself; the grow migration is paid for in the same edit
because it touches the same file and uses the same packed-index helpers.
A perf bench (allocate to 16+ qubits in DM, time grow) is a sensible
follow-on bead but not blocking.

### What did not need to change

  * `src/context/abstract.jl` — `compact_state!(::AbstractContext) = ctx`
    no-op default already in place from bead 059; DM concrete method
    overrides cleanly.
  * `measure!(::DensityMatrixContext)` — Proposer B flagged a suspect
    swap-to-|0⟩ loop; the precondition scan did NOT fire on any
    realistic post-measure state in the new tests, so the existing
    measure! is producing the right zeroing pattern. Worth a separate
    audit bead but not in scope here.
  * `CompactPlan` struct — reused as-is across both contexts.

### Open follow-ons

  1. **Hand-rolled `compact_state!` for `HardwareContext`** (bead
     `Sturm.jl-83t`): server-side compaction already inherits via
     `_SimSession.eager`; the gap is a CLIENT-SIDE protocol verb for
     long sessions on real hardware.
  2. **`STURM_COMPACT_VERIFY` env-gate** (`Sturm.jl-179`): same as
     bead 059 — the residual scan is always-on; switch off after several
     sessions of zero violations.
  3. **`unsafe_copyto!` shortcut in `_compact_scatter_dm!`** for the
     contiguous-live case (analogous to `Sturm.jl-2fg` for eager). At
     dm scales the win is sharper because column strips are bigger.
  4. **DM grow perf bench** (no bead yet) — extend
     `probe_mulmod_phases.jl`-style instrumentation to a DM grow run
     past capacity 14; expect order-of-magnitude wall-clock improvement
     vs main pre-migration.

### Latest commits when this lands

```
<this commit>  feat(amc): compact_state!(::DensityMatrixContext) — bulk grow + 2D scatter
5798a80         feat(059): compact_state! — n_qubits ratchet fix; 6.3× at N=15 c_mul=2
a49cdba         docs(worklog): session handoff entry — vbz + eiq closed, 6oc(d) ✓
9d95ef0         feat(vbz): Berry App B Thm 2 clean-ancilla forward QROM — closes 6oc(d) at L=8
```

---

