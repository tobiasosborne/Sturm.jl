## 2026-04-25 — Session 64 end: handoff for next agent

`Sturm.jl-059` closed in this session — `compact_state!(::EagerContext)`
landed and delivered **6.3× speedup at N=15 c_mul=2** (~21 min → 3.3 min).
All 4600+ assertions in adjacent test files still green; no regressions.

Orient yourself before touching anything:

```bash
git log --oneline -8        # 2026-04-25 commits, this session is 5 files +1 new
bd ready -n 10              # open work queue
bd list --status=open -n 30 # full open set
bd memories sturm-jl-059-root-cause-confirmed-2026-04
```

### Where the project stands

  * `compact_state!(::EagerContext)` lives at `src/context/eager.jl`,
    around line 165–390. No-op default `compact_state!(::AbstractContext) = ctx`
    in `src/context/abstract.jl`. Auto-fires from `deallocate!` when
    `length(free_slots) >= 2 * GROW_STEP`.
  * 264-assertion test scaffold at `test/test_compact_state.jl` (wired into
    `runtests.jl`). Covers contract, state preservation, soundness,
    atomicity, auto-trigger, pre-flight validation.
  * Six investigation probes at the repo root (`probe_compact_precond.jl`,
    `probe_mc_dealloc_cost.jl`, `probe_qrom_cold.jl`,
    `probe_add_qft_isolated.jl`, `probe_peak_qubits.jl`,
    `probe_mulmod_phases.jl`). Re-run any of these to validate after
    changes that touch `EagerContext`, `_grow_state!`, `_blessed_measure!`,
    or `apply_reversible!`.

### Open beads worth picking up next

Top-of-queue pickup candidates filed as follow-ons of `Sturm.jl-059`:

  1. **`Sturm.jl-amc` (P3, NEW)** — `compact_state!` for
     `DensityMatrixContext`. Same architecture, 2D row+col scatter on the
     `2^(2n)` density-matrix buffer. Also migrate `_grow_density_state!`
     from per-element FFI to bulk `unsafe_wrap`+`unsafe_copyto!` while in
     here. Reference impl: `src/context/eager.jl:_compact_scatter!`.
     Test scaffold: mirror `test/test_compact_state.jl`. CLAUDE.md
     rule 2 — touches `src/context/`, requires 3+1 agents.
  2. **`Sturm.jl-w9e` (P3, NEW)** — Rewrite the audit-flagged tests that
     pass under compaction by accident. Specifically
     `test/test_shor.jl:344-346` (n_qubits delta) and
     `test/test_bennett_integration.jl:149` (`free_slots >= 3`). Use
     `ctx._compact_count` (new field on `EagerContext`) to disambiguate
     "compaction fired" from "ancillae weren't returned". Cheap, high-
     signal cleanup.
  3. **`Sturm.jl-179` (P3, NEW)** — Add `STURM_COMPACT_VERIFY` env-gate
     for the residual-norm precondition scan. Currently always-on per
     CLAUDE.md rule 1; A8 of bead 059 was to flip it off after empirical
     confirmation. Don't ship the off-default until at least 1–2
     sessions confirm zero residual violations across mulmod/Shor runs.
  4. **`Sturm.jl-2fg` (P4, NEW)** — `:unsafe_copyto!` shortcut in
     `_compact_scatter!` for the contiguous-live case (live slots already
     `0..k-1`, only `n_qubits` is wrong). Detection trivial; perf win is
     small (~few % on small contexts) but the code path is cleaner.
  5. **`Sturm.jl-83t` (P4, NEW)** — `compact_state!` protocol verb for
     `HardwareContext`. Server-side compaction already fires (since
     `_SimSession.eager` is a normal `EagerContext`); this would expose
     a CLIENT-SIDE request-compact API for long device sessions.
  6. **`Sturm.jl-ao1` (P3)** — Hand-rolled Babbush-Gidney unary
     iteration QROM. Filed in Session 63; still relevant for L=8 6oc(d)
     tightening below 0.500×, independent of bead 059. Ground truth at
     `docs/physics/babbush_2018_qrom_linear_T.pdf` §III.C Fig 10.
  7. **Qudit track** — `csw, 2bf, p38, mle, os4, jba, dj3, …` all still
     unblocked. Parallel to the Shor critical path.
  8. **Multi-mulmod perf bench** (no bead yet) — `probe_mulmod_phases.jl`
     only times one mulmod. Across-mulmod state behaviour (capacity sticky
     between mulmods, repeated compact cycles) is the natural next perf
     inquiry. File a bead with description "extend probe_mulmod_phases.jl
     to N×mulmod sequences, expect compact's win to compound".

### Non-obvious traps from this session

  * **The bead's hypothesis can be wrong.** `Sturm.jl-059` was filed
    pinning workspace alloc/dealloc inside `_multi_controlled_gate!`. It
    accounts for 0.04% of the cost. The real bottleneck (n_qubits
    ratchet → 2^n_qubits per gate even on mostly-recycled state) was
    invisible until I wrote `probe_peak_qubits.jl` and watched
    `ctx.n_qubits` directly. **Lesson: always run an instrumented probe
    before committing to a fix design.**
  * **`live_wires` ordering inconsistency silently corrupts state.**
    Sorting `live_wires` by `WireID.id` AND `old_slots` ascending makes
    the two arrays inconsistent (`old_slots[k] != wire_to_qubit[live_wires[k]]`).
    The compact then permutes amplitudes within the live set. Symmetric
    unit tests (Bell correlations, basis-state amplitude checks) all
    passed because they're invariant under wire permutation; only the
    Shor statistical tests caught it. Sort `live_wires` BY their old
    slot index, then `old_slots[k] == wire_to_qubit[live_wires[k]]`
    holds by construction. **Lesson: when a compact-like primitive
    permutes amplitudes, the unit tests must include a phase-sensitive
    case (e.g. interference / order-finding) — not just basis or
    correlation.**
  * **Compact's free-slot threshold and shrink-delta are independent
    knobs.** First trying `threshold=8, no shrink-delta` OOM'd on N=15
    c_mul=2 (capacity oscillation 17→21→25→29 hit memory wall).
    Second trying `threshold=16, no shrink-delta` lost the small-N win
    (compact rarely fired). Third try `threshold=8, shrink-delta=2·GROW_STEP`
    works. The threshold controls how OFTEN compact fires; the delta
    controls how AGGRESSIVE each compact is. Tune them independently.
    Saved as the design rationale in src/context/eager.jl comments.
  * **Conditional `GC.gc(false)` after compact** is needed when
    pre-compact capacity ≥ 24 — otherwise the next `_grow_state!` runs
    while the old big Orkan buffer is still alive (Julia GC is async),
    doubling transient memory pressure. Cheap when it fires (incremental
    GC), skipped on small contexts where the GC pause cost outweighs
    the saved memory.
  * **`live_wires(ctx)` is documented as ordering-undefined** (Dict
    iteration). Any primitive that depends on live-wire ordering MUST
    sort explicitly. Tests that rely on ordering will be flaky.
  * **Pre-existing `test_bennett_integration.jl` failures** (3 fail +
    11 error) are unrelated to this session — `_CIRCUIT_INC.n_wires == 41`
    not 26 as the test name claims. Confirmed by `git stash` + re-run.

### Session sequence for the full story

Read Session 64 (this entry) for the compaction work; Sessions 62–63 for
the immediately preceding `eiq`/`vbz` story; earlier sessions in
`WORKLOG-archive.md`.

### Environment (inherit these — unchanged)

  * `LIBORKAN_PATH=/home/tobiasosborne/Projects/orkan/cmake-build-release/src/liborkan.so`
  * `OMP_NUM_THREADS=16`
  * Never run the full test suite — run individual files via
    `julia --project -e 'using Sturm, Test; include("test/test_X.jl")'`.
  * Julia runs strictly serial on this device.
  * Verbose output must eager-flush stage by stage.

### Latest commits on main (will be the topmost on push)

```
<this commit>  feat(059): compact_state! — n_qubits ratchet fix; 6.3× at N=15 c_mul=2
a49cdba         docs(worklog): session handoff entry — vbz + eiq closed, 6oc(d) ✓
9d95ef0         feat(vbz): Berry App B Thm 2 clean-ancilla forward QROM — closes 6oc(d) at L=8
de79042         fix(eiq): CasesNode consumer fail-loud / warn-once policy
```

---

## 2026-04-25 — Session 64: bead `Sturm.jl-059` closed, `compact_state!` lands

Headline: `_shor_mulmod_E_controlled!` at N=15 c_mul=2 went from **~21 min → 3.3 min** (6.3×). All three benchmark cases win, no regressions across 4600+ tests in adjacent test files.

### Root cause was *not* what the bead said

Original hypothesis (workspace alloc/dealloc inside `_multi_controlled_gate!`)
was wrong. Empirical measurement showed it accounts for **~50 ms / 1260 s
= 0.04%** of the cost. The real bottleneck was a state-size ratchet:

  * Bennett ancilla allocations during `apply_reversible!` push
    `EagerContext.n_qubits` up to ~26 transient.
  * After ancilla cleanup, slots are returned to `free_slots` but
    `n_qubits` is sticky upward, and the Orkan state never shrinks.
  * Every subsequent gate operates on `2^n_qubits` amplitudes regardless
    of how few wires are actually live (probed: N=15 c_mul=1 mulmod ends
    with `live=7` but `n_qubits=26` → 2^19 = 500k× more amplitudes per
    gate than necessary).

Probes that converged on this: `probe_mc_dealloc_cost.jl` (rules out
workspace), `probe_qrom_cold.jl` (rules out Bennett compile),
`probe_add_qft_isolated.jl` (shows controlled add_qft cost is 4ms at
15 live, 41ms at 18, **12,000ms at 25** — the 1700× scaling reveals the
ratchet), `probe_peak_qubits.jl` (confirms the n_qubits HWM directly),
`probe_compact_precond.jl` (validates the soundness assumption empirically).

### What landed: `compact_state!(::EagerContext)`

Three files touched in `src/`, one new test file:

  * `src/context/eager.jl` — new `_compact_count` field on EagerContext;
    new `CompactPlan` struct + `_compact_plan` validator + `_compact_verify_freed_zero`
    pre-condition scan + `_compact_scatter!` projection loop +
    `compact_state!` orchestrator. Auto-trigger added to `deallocate!`.
  * `src/context/abstract.jl` — `compact_state!(::AbstractContext) = ctx`
    no-op default so library code can call uniformly.
  * `src/Sturm.jl` — exported `compact_state!`.
  * `test/test_compact_state.jl` (new) — 264 assertions across 6 testsets:
    contract (no-op fast path, return-self, slot-remap, wire identity,
    consumed-set preservation), state preservation (single-qubit amps,
    Bell correlations across 200 shots, compact-then-gate equivalence,
    random stress), soundness (entangled-discard error path), atomicity
    (failed compact leaves ctx unchanged), auto-trigger (deallocate
    threshold + ping-pong containment), and pre-flight validation
    (per-error-message coverage). Wired into `runtests.jl`.

### Architecture: compute-then-commit (synthesised from 3+1 ceremony)

Per CLAUDE.md rule 2 (core change requires 2 proposers + 1 implementer +
orchestrator review), spawned two parallel proposer subagents — Proposer A
(data-flow first) and Proposer B (invariant first). Implementer-as-orchestrator
synthesised: B's compute-then-commit skeleton + 8 pre-flight error checks +
audit counter, A's no-op AbstractContext default + `unsafe_copyto!` shortcut
intent (deferred), B's auditable scatter loop. Phase 1 (validate read-only),
Phase 2 (verify residual norm), Phase 3 (build new state on the side),
Phase 4 (atomic commit via 5 infallible field writes). At every line of the
function `ctx` is either fully old or fully new — never half-state.

### Three iterations to get the perf-vs-memory trade-off right

The first implementation worked at small N but OOM'd at N=15 c_mul=2.
The compact-then-grow oscillation drove `_grow_state!` along an off-grid
trajectory (17→21→25→29) and the half-RAM check in `_grow_state!`
(`needed > avail/2`) blocked allocations at cap=29 (8 GiB needed, ~10 GiB
free). Iteration 2 (threshold=4·GROW_STEP=16) avoided the OOM but lost
the small-N win because compact rarely fired. Iteration 3 (current):
keep threshold=2·GROW_STEP=8, but **bound shrink-delta to 2·GROW_STEP
per compact** so each compact-grow cycle stays within the original
+4 grow-grid (20→24→28 trajectory; 24→28 transient = 4 GiB, fits half-RAM
check). Plus a conditional `GC.gc(false)` only when `old_capacity >= 24`
to free the released big buffer before the next grow doubles transient
memory. Skipped on small contexts where the GC pause cost outweighs
the saved memory. **Lesson: free-slot threshold and shrink-delta are
distinct knobs and both matter. The first controls how often compact
fires; the second controls how aggressive each compact is.**

### Subtle bug found during integration: scatter-vs-rebuild ordering

The original synthesis sorted `live_wires` by `WireID.id` then *also* sorted
`old_slots` ascending. The two orderings then disagreed: `old_slots[k]`
was no longer `wire_to_qubit[live_wires[k]]`. Result: amplitudes were
permuted *within* the live set during compact, silently corrupting the
state. test_shor.jl's statistical tests caught it — exact-state assertions
in test_compact_state.jl (Bell correlations, basis-state reconstruction)
passed because they were symmetric under wire permutation, but Shor's
order-finding has phase relationships that aren't. **Lesson: sort
`live_wires` BY their old slot index ascending, so `old_slots[k] ==
wire_to_qubit[live_wires[k]]` holds by construction.**

### Numbers (all on this 16-thread, ~10-GiB-free WSL2 box)

  * **N=7 c_mul=1 mulmod**: 14.5s → 6.3s (2.3×). peak `n_qubits`: 22 → 6.
  * **N=15 c_mul=1 mulmod**: 378s (6.3 min) → 75s (5.0×). peak `n_qubits`:
    26 → 10.
  * **N=15 c_mul=2 mulmod**: ~21 min → 3.3 min (6.3×). pep1=84s, pep2=116s.
    No OOM. Memory cycles between ~1 GiB and ~5 GiB during the run, GC
    keeps it bounded.

### Open follow-ons (file as new beads when picked up)

  * **DensityMatrixContext compact**: 2D row+col permutation on the
    `2^(2n)` density-matrix buffer. Same algorithm shape, more index
    arithmetic. `_grow_density_state!` is also still on per-element FFI
    (vs eager.jl's bulk `unsafe_copyto!`); migrate that too.
  * **HardwareContext compact protocol**: server-side compaction for
    real-device `_SimSession`. Currently `compact_state!(::HardwareContext)`
    inherits the AbstractContext no-op; for long sessions on a real
    device this could be a meaningful win.
  * **`STURM_COMPACT_VERIFY` env-gate** (bead-A8): the residual-norm scan
    runs by default. After empirical confirmation across many sessions,
    add an env-var to disable it in release. Currently always-on; cost is
    O(2^old_n) per compact.
  * **Audit-flagged tests**: `test_shor.jl:344-346` (n_qubits delta
    measurement no longer accurate under compaction — passing accidentally
    because deltas can now be near-zero), `test_bennett_integration.jl:149`
    (`@test length(free_slots) >= 3` — passing because compaction doesn't
    fire in that test's context). Rewrite to test invariants compaction
    preserves rather than incidentals.
  * **`probe_mulmod_phases.jl` does not bench multi-mulmod runs**.
    Across-mulmod state behaviour (capacity sticky, repeated compaction
    cycles) is the natural next perf inquiry.

### Tests touched, not touched

Touched: `test/test_compact_state.jl` (new), `test/runtests.jl` (wired in).
Verified clean: `test_compact_state` (264), `test_autocleanup` (14),
`test_qint` (562), `test_qmod` (519), `test_arithmetic`'s 4 testsets
(809+2130+269+24=3232), `test_shor` (47+2 broken — same as main),
`test_ptrace` (9). **Did not run full suite** (per memory
`sturm-jl-test-suite-slow`).

Pre-existing failures observed but unrelated to this change:
`test_bennett_integration.jl` has 3 fail + 11 error on main (`_CIRCUIT_INC.n_wires
== 41`, not 26 as test name claims; downstream OOM at capacity=43>MAX=30).
Confirmed by `git stash` + re-run.

### Probes (in repo root, untracked)

  * `probe_mc_dealloc_cost.jl` — workspace alloc/dealloc per-call cost.
    Showed pool would save 0.04%.
  * `probe_qrom_cold.jl` — fresh-table QROM compile cost. Showed Bennett
    cache works, ~17 ms cold compile.
  * `probe_add_qft_isolated.jl` — controlled add_qft cost as a function
    of live-qubit count. Showed the 280× scaling that pinned the bottleneck.
  * `probe_peak_qubits.jl` — direct measurement of `ctx.n_qubits` HWM
    via a poller task during one mulmod.
  * `probe_mulmod_phases.jl` — phase-by-phase wall clock for one mulmod.
    Used as the perf bench.
  * `probe_compact_precond.jl` — Stage A0 soundness probe. Ran 11 realistic
    scenarios including a real N=7 mulmod; residual-norm² over freed slots
    was exactly 0.0 in every case. Empirical validation that `_blessed_measure!`
    deterministically resets to |0⟩ before pushing to `free_slots`.

### Memories saved

  * `sturm-jl-059-root-cause-confirmed-2026-04` — preserves the root-cause
    finding so a future agent doesn't have to re-derive it.

### Latest commits (when this lands)

bead 059 description + design field updated via `bd update` to reflect
the corrected root cause and the chosen architecture. `bd close
Sturm.jl-059` after these tests are committed.

---

