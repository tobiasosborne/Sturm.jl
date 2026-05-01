## 2026-04-27 — Session 74: bead `Sturm.jl-2qp` diagnosed (n_qubits ratchet at peak)

Investigation bead. Goal: explain the ~750× per-DAG-gate slowdown of
`_shor_mulmod_E_controlled!` vs `mulmod_beauregard!` at N=15. Result: the
bead's three hypotheses (fan-out / per-window cascade / FFI overhead) are
all REJECTED. Real root cause is the n_qubits ratchet during Bennett bursts
in `qrom_lookup_xor!`. A naive in-`apply_reversible!` compaction fix
REGRESSES due to grow/shrink thrashing on the Orkan buffer; the proper fix
needs an in-place compaction primitive (filed as a separate bead).

### Diagnostic instrumentation (kept)

Added module-level counters to `src/context/eager.jl`:
  * `_APPLY_COUNT_{RY,RZ,CX,CCX}` — per-primitive ccall counts
  * `_APPLY_NC_*` — control-stack-depth (nc) buckets at gate entry
  * `_APPLY_NQ_MAX`, `_APPLY_NQ_SUM_2`, `_APPLY_NQ_BUCKETS` — per-gate
    sampling of `ctx.n_qubits` at the moment each ccall fires (the
    "effective state-volume" is what dominates wall time when ccalls are
    memory-bound)

Public API: `reset_gate_counts!()`, `gate_counts()`. Exported from
`Sturm.jl`. Cost: ~3 ns Ref-increment per primitive entry, negligible vs
ccall cost. 21 tests in `test/test_bennett_compact.jl` pin the contract.

### What the data showed

`probe_count_DE.jl` runs ONE mulmod each of D-Beauregard and E-windowed
at N=15, then prints fan-out and per-call timings:

```
D N=15 L=4
  wall                            : 51 ms
  apply_*! total                  : 3500 (CX 1284, RY 196, RZ 1780, CCX 240)
  fan-out (ccalls per DAG node)   : 6.58×
  peak n_qubits at gate           : 12     (16 KB statevector)
  per-ccall                       : 14.5 µs

E c_mul=2 N=15
  wall                            : 192_565 ms   ← 3700× slower than D
  apply_*! total                  : 2154   ← FEWER than D
  fan-out                         : 5.52× (E/D = 0.62)
  peak n_qubits at gate           : 28     (4 GB statevector)
  per-ccall                       : 86_342 µs    ← 5947× D
  nq histogram                    : [12-15:158] [16-19:492] [20-23:948]
                                    [24-27:100] [28-31:456]
```

Hypotheses (i)/(ii)/(iii) all rejected: E emits FEWER ccalls than D, and
99% of E's ccalls are at nc=0 (only 18 cx + 145 rz + 90 rz are at nc≥1).
The cost is per-ccall, not per-call-count.

### Root cause

956 of E's 2154 ccalls (44%) run while `n_qubits ∈ [20, 31]` — peak 28,
which is a 4 GB statevector. The "true" working set is ~12 wires; the gap
is Bennett ancillae + scratch register held during a QROM burst.

`apply_reversible!` allocates K Bennett ancillae (typically 3–7 for the
Sturm-side QROMs at c_mul ≤ 2), runs the compiled gates, then deallocates
the ancillae one-by-one in a `finally` block. Each `deallocate!` checks
`length(free_slots) >= 2 * GROW_STEP` (= 8) and only fires `compact_state!`
when crossed. For sub-threshold bursts (K < 8) the threshold is NEVER
crossed, so n_qubits stays at the burst peak. The 948 gates of QFT/IQFT/
add_qft_quantum that run BETWEEN the forward QROM and the uncompute QROM
each scan a 4 GB statevector instead of a 16 KB one. Memory bandwidth at
2 × 50 GB/s ≈ 100 GB/s and 4 GB / 100 GB/s = 40 ms/gate matches the
measured 86 ms/gate average (which factors in the 25% in-burst gates that
also run at n=28).

### Two fix attempts, both rejected

**Attempt 1** — explicit `compact_state!(ctx)` at end of
`apply_reversible!`'s `finally` block.

  * Result: 192s → 334s (75% slower, c_mul=2). c_mul=1: 73s → 165s (2.3×).
  * Why: compaction fires after FORWARD QROM, between forward and uncompute.
    The next QROM (uncompute) immediately re-allocates K ancillae,
    triggering `_grow_state!`, which copies the entire 64 MB / 1 GB
    statevector. With cap≥24 the post-compact `GC.gc(false)` pass is
    expensive at 4 GB heap footprint. Net: compact-then-regrow thrashing
    dominates any savings on the inter-burst gates.

**Attempt 2** — `compact_state!(ctx)` at end of `_pep_mod_iter!`, after
`ptrace!(scratch)`.

  * Result: 192s → 195s (neutral, c_mul=2). c_mul=1: 73s → 165s (2.3×, same
    regression).
  * Why: too late. The 948 inter-burst gates ALREADY ran at peak by the
    time the iteration boundary fires. Compaction at the boundary helps
    only the NEXT iteration's gates — but those are also at peak again
    (each iter has its own QROM bursts). And the c_mul=1 case has 8 such
    boundaries per mulmod × ~10s GC.gc(false) overhead = full regression.

Both attempts reverted. Diagnostic counters kept. Test file
`test/test_bennett_compact.jl` rewritten to pin counter behaviour without
asserting the perf gap (which IS still there).

### Path to the actual fix (filed as new bead)

The compaction has to drop n_qubits during the gates BETWEEN forward and
uncompute QROM, WITHOUT triggering `_grow_state!` on the next QROM
allocation. That requires decoupling logical wire layout from the Orkan
buffer size — a "logical-only" `compact_state!` variant that:

  1. Reorganises `wire_to_qubit` to map live wires to indices [0, len-1].
  2. Keeps the Orkan buffer at its current capacity (no realloc).
  3. Sets `n_qubits` to `len(live)` so subsequent gates only operate on
     the first `2^new_n` amplitudes (Orkan gates already obey n_qubits;
     freed slot amplitudes are |0⟩, so the joint state factor is exact).
  4. Tracks "logical free slots" so the next allocate! returns those
     indices first, only growing the Orkan buffer when logical slots run
     out.

Cost per compact: one in-place amplitude scatter (or none, if free slots
are already at the high indices, which is typical post-Bennett). No
malloc/free, no GC pass, no copy. Should be < 1 ms per compaction at
n=28.

Alternative routes (each its own bead):

  * Use `mbu=true` (Berry et al. 2019 measurement-based uncompute) to
    free Bennett ancillae during the uncompute. Orthogonal to the
    n_qubits ratchet, but reduces peak K.
  * Switch the QROM construction to one with lower peak ancilla count
    (Babbush-Gidney's hand-rolled unary iteration, bead `ao1`).
  * Use `mbu_compute=true` (Berry App B clean-ancilla forward, bead
    `vbz`) to reduce forward-QROM ancilla peak.

### Lessons for future agents

  * **Hypothesis (i) wasn't the bug.** The bead listed three hypotheses in
    priority order; the diagnostic refuted all three. ALWAYS check the
    null hypothesis first via instrumentation. The fan-out hypothesis
    sounded plausible — but cost ratio E/D = 0.62 (E emits FEWER), and
    the real cost is per-call, not call-count.

  * **Per-gate `ctx.n_qubits` sampling is the metric that matters when
    statevectors are memory-bound.** Static "peak n_qubits during call"
    (via `_n_qubits_hwm`) is monotonic and over-counts. The histogram
    of `ctx.n_qubits` at every `apply_*!` entry decomposes the wall-time
    cost into "where in the dimension distribution does this workload
    spend its ccalls".

  * **Compact-then-regrow thrashing is real.** `compact_state!` at
    cap=28 costs O(2^28 amplitudes) for the residual scan plus a
    `GC.gc(false)` if old_capacity ≥ 24. If the next gate immediately
    grows the buffer back, you've paid all that for nothing AND you
    pay `_grow_state!`'s copy cost. Compaction is only a win when the
    state stays compact for many subsequent gates.

  * **`STURM_COMPACT_VERIFY=0` was not enough on its own.** The verify
    scan is one cost; the buffer realloc + GC is another. Disabling
    verify alone reduces compact cost ~50%, not enough to make
    Attempt 1 viable.

  * **The `@context` macro hides inner assignments from the outer
    scope** (Session 23 already noted). My first probe used
    `local d_counts; @context begin ...; d_counts = ... end` and got
    `UndefVarError`. Fix: closure-returning-tuple — `function run_D()
    @context begin ...; return (counts, dt); end end` then call
    `d_counts, d_dt = run_D()`.

### Files touched

  * `src/context/eager.jl` (+102 LOC): counter Refs, `_bump_nc!`,
    `_sample_nq!`, `reset_gate_counts!`, `gate_counts`, sampling calls
    in `apply_ry!`/`apply_rz!`/`apply_cx!`/`apply_ccx!`.
  * `src/Sturm.jl` (+2 LOC): export `reset_gate_counts!, gate_counts`.
  * `test/test_bennett_compact.jl` (NEW, 100 LOC): 21 tests pinning the
    counter contract.
  * `probe_count_DE.jl` (NEW): the diagnostic harness.
  * `WORKLOG.md`: this entry.

### Beads state at end of session

  * `Sturm.jl-2qp` — investigation done, hypotheses refuted, true root
    cause documented. Will close with reference to the new follow-up
    bead. Diagnostic counters merged.
  * NEW BEAD (to file): "in-place compact_state! variant for Bennett
    ancilla bursts" — P1, blocks Sturm-scale windowed-arithmetic perf.

---

## 2026-04-26 — Session 73: bead `Sturm.jl-7ab` closed (AbstractPass + registry)

Headline: Pillar 3 ("extensibility") realised at the pass layer.
`AbstractPass` + `handles_non_unitary` trait + symbol/instance-keyed
registry land. Existing `gate_cancel` and `defer_measurements` wrap into
`GateCancelPass` and `DeferMeasurementsPass`. `optimise(ch, :symbol)`
backward-compat preserved byte-identical. New 34-test
`test_passes_registry.jl` testset passes; existing 49-test
`test_passes.jl` still passes.

### Design (3+1 — two Opus proposers, synthesis review, single implementer)

Two Opus proposers ran independently with the same brief (read recon
agents' output, no awareness of each other). Both arrived at ~90% the
same shape: `abstract type AbstractPass`, `run_pass(p, ::Vector{DAGNode})
-> Vector{DAGNode}`, runtime gate via `handles_non_unitary`, default
`false` (conservative — assumes unsafe). Differences synthesised:

  * **Trait dispatches on `Type{<:AbstractPass}`, not on instance** (A's
    pick). The channel-safety property belongs to the algorithm, not to
    a configured instance — `MyPass(strict=true)` and `MyPass(strict=false)`
    can't sensibly disagree.
  * **`Dict{Symbol, AbstractPass}` registry storing instances** (B's pick).
    Direct symbol back-compat path; `registered_passes()` returns
    instances ready for `Sturm.jl-7kg` enumeration.
  * **`Base.@kwdef` for `DeferMeasurementsPass`** (B's pick). Ergonomic
    `DeferMeasurementsPass(strict=true)`.
  * **Explicit `register_pass!` calls at module scope** (A's pick).
    Explicit > `__init__` magic per CLAUDE.md.
  * **Full remediation guidance in the gate's error message** (B's pick).
    "Lower measurements first / mark channel-aware / partition" — three
    concrete paths.

### handles_non_unitary semantics (crucial)

`true` means EITHER (a) channel-aware (operates correctly across
non-unitary nodes — `DeferMeasurementsPass`) OR (b) barrier-aware
(treats them as hard barriers, optimises only within unitary subblocks
— `GateCancelPass`'s existing `_barrier_wires` machinery). Both are
safe; both opt in. `false` (default) means "naive about barriers" — a
ZX simp / phase-poly extraction that doesn't know about measurement and
would silently corrupt. The runtime gate fires on `false` × any
non-unitary node.

This semantics preserves backward compat: `optimise(ch_with_measurement,
:cancel)` STILL works because `GateCancelPass` is barrier-aware (true).

### Files touched

  * `src/passes/abstract.jl` — NEW. AbstractPass, traits, registry, helpers.
  * `src/passes/gate_cancel.jl` — appended `GateCancelPass` wrapper +
    `register_pass!(:cancel, ...)` + `register_pass!(:cancel_adjacent, ...)`.
  * `src/passes/deferred_measurement.jl` — appended `DeferMeasurementsPass`
    (`Base.@kwdef`) + `register_pass!(:deferred, ...)` +
    `register_pass!(:defer_measurements, ...)`.
  * `src/passes/optimise.jl` — REPLACED. Now hosts the three `optimise`
    method dispatches (`Vector{<:AbstractPass}`, single `AbstractPass`,
    `Symbol`). Symbol path delegates to `get_pass(name)` with `:all`
    special-cased to `[get_pass(:deferred), get_pass(:cancel)]`.
  * `src/Sturm.jl` — included `passes/abstract.jl` BEFORE the existing
    pass files. Exported `AbstractPass`, `run_pass`, `pass_name`,
    `handles_non_unitary`, `GateCancelPass`, `DeferMeasurementsPass`,
    `register_pass!`, `registered_passes`, `get_pass`.
  * `test/test_passes_registry.jl` — NEW. 34 tests; 10 testsets covering
    built-in registration, `:bogus` error formatting, trait declarations,
    Vector + single-pass + Pipeline composition, runtime gate firing AND
    bypass via override, user-side `register_pass!` + Symbol dispatch,
    `DeferMeasurementsPass(strict=true)` propagation.
  * `test/runtests.jl` — added `include("test_passes_registry.jl")`
    after the existing `test_passes.jl` line.

### Gotchas hit and recorded for next agent

  * **Defining a struct inside `@testset` triggers a Julia world-age
    issue when methods on it are then called from the same expansion.**
    First test run errored: "Got exception outside of a @test" inside the
    testset that did `struct MyNaivePass <: AbstractPass end` then
    immediately `optimise(ch, MyNaivePass())`. Fix: hoist all
    fixture-pass struct definitions and method overrides to module-top
    (above the `@testset` block). The testset only references them.
  * **`ptrace!(q)` returns `Vector{WireID}`, not `nothing`.** The `trace`
    function only accepts `QBool`, `Tuple`, or `nothing` as the do-block
    return value. A naive `trace(1) do q; q.θ += π/4; ptrace!(q); end`
    errors with "trace: unexpected return type Vector{WireID}". Fix:
    explicit `nothing` (or `;`) on the next line.
  * **`Bool(q)` inside `trace()` is forbidden by P4 axiom** — produces
    a loud error with remediation pointing at `cases(q, () -> nothing)`
    or `ptrace!(q)`. Initial test attempt used `Bool(q)` to construct an
    `ObserveNode`; correct path is `ptrace!(q)` for a `DiscardNode`
    (which trips the same `_is_non_unitary` gate). The error is exactly
    the kind P4 was designed to surface.

### Out of scope (separate beads — NOT done here)

  * Sim-equivalence harness — `Sturm.jl-7kg` (sibling, open). Now
    unblocked: `registered_passes()` returns instances ready for the
    diamond-norm property tests.
  * Pass cost / effect reporting — not in 7ab description.
  * Barrier partitioner — `Sturm.jl-vmd`, defunct unless `Sturm.jl-d99`
    (Choi phase polynomials on channels) fails as a research direction.
  * Pass lookup by string name (Dict-of-strings) — Symbol keys cover
    every current use case.

### Beads state

  * Closed: `Sturm.jl-7ab`.
  * Now actionable: `Sturm.jl-7kg` (sim-equivalence harness — direct
    consumer of `registered_passes()`).

### Handoff — concrete next steps

Three priority candidates, in descending leverage. Pick ONE, claim with
`bd update <id> --claim`, and use the entry points below as the cold
start.

#### A. `Sturm.jl-2qp` (P1 BUG — 750× per-gate slowdown in shor_order_E)

This is the only P1. Unblocks N=15 statistical acceptance for the closed
6oc bead; would let `probe_shor_E_N15.jl` finish in <hour rather than
~6 hours; gates user-scale windowed-arithmetic work generally.

  1. **Reproduce**:
     `OMP_NUM_THREADS=16 LIBORKAN_PATH=/home/tobiasosborne/Projects/orkan/cmake-build-release/src/liborkan.so julia --project probe_mulmod_E_bench.jl`
     Expect ~74 s/mulmod at N=15 c_mul=1, ~186 s at c_mul=2. D-semi at
     N=15 t=3 is ~250 ms/mulmod (factor 750× per-gate).
  2. **Read first**: `src/library/shor.jl:902-961` (`_shor_mulmod_E_controlled!`),
     then `src/library/arithmetic.jl:582-1265` (`plus_equal_product_mod!`,
     `qrom_lookup_xor!`, `_binary_to_unary!`, `_fredkin!`,
     `qrom_lookup_xor_cleanancilla!`). Top-down trace.
  3. **Investigate hypotheses in priority order** (per bead 2qp):
       (i)   `qrom_lookup_xor!` fan-out — wrap
             `apply_cx!`/`apply_ry!`/`apply_rz!` in `src/context/eager.jl`
             with a `Ref{Int}` counter at the top of the file; run one
             `_shor_mulmod_E_controlled!` and one `mulmod_beauregard!` at
             N=15 with the counter; compare primitive ccall counts to the
             DAG node count from `probe_toffoli_DE.jl`. If E's ratio
             (ccalls / DAG nodes) is much higher than D's, the fan-out
             hypothesis is confirmed.
       (ii)  If fan-out is the cause, profile inside `qrom_lookup_xor!`
             (`src/bennett/bridge.jl:523`) and `plus_equal_product_mod!`
             internals to find which abstract DAG node is exploding.
       (iii) If counts are comparable, use `Profile.@profile` /
             `using ProfileView` for stack-frame-level hot-spot.
  4. **Closure**: identify root cause, file fix bead (likely a perf-fix
     bead with concrete code change), re-run probe_mulmod_E_bench.jl,
     verify ≥10× speedup.

#### B. `Sturm.jl-7kg` (P2 FEATURE — pass sim-equivalence harness)

Sibling unblocked by today's 7ab work. The new `registered_passes()`
enumeration is the harness's foundation.

  1. **Read first**: `CLAUDE.md` lines 71-95 (Channel IR vs Unitary
     Methods); `test/test_passes.jl` for the existing structural-test
     pattern; `KNOWN_ISSUES.md:24` for the gap statement.
  2. **Design**: harness lives in `test/test_pass_equivalence.jl`. For
     each `pass in registered_passes()`:
       * generate random small channels (W ≤ 4 wires, ≤ 20 nodes)
       * if `handles_non_unitary(pass) == false`: only unitary
         channels; statevector compare via `EagerContext`
       * if `true`: include channels with `ObserveNode`/`DiscardNode`;
         compare measurement statistics via N-shot sampling, OR
         compare Choi matrices via partial-trace construction
  3. **Property assertion**: `‖simulate(pass(ch)) − simulate(ch)‖ ≤ ε`
     (operator-1 norm on statevector / diamond-norm on channels;
     statevector L1 is fine for v0.1).
  4. **Closure**: harness asserts existing GateCancelPass + DeferMeasurementsPass
     are CPTP-equivalent on the random suite; ε = 1e-10 for
     deterministic passes.

#### C. `Sturm.jl-dxk` (P2 BUG — Parker-Plenio iQFT D-semi/E twin)

Quick-win extraction. Probably one session.

  1. **Read** `src/library/shor.jl:1163-1235` (`shor_order_D_semi`) and
     `1313-1386` (`shor_order_E`). The two semi-classical iQFT loops are
     byte-for-byte identical except for the mulmod call (line 1206 vs
     1361) — verify with `diff <(sed -n 1163,1235p src/library/shor.jl)
     <(sed -n 1313,1386p src/library/shor.jl)`.
  2. **Extract** `_parker_plenio_iqft!(target, mulmod_fn, ::Val{t}, N::Int) -> y_tilde::Int`
     into a new section of `src/library/shor.jl` (or `src/library/patterns.jl`
     if it's general enough — the construction is from Parker & Plenio
     2000 arXiv:quant-ph/0002014, not Shor-specific).
  3. **`mulmod_fn`** is a closure: `(target, a_j, ctrl) -> ...`. For
     D-semi: `(t, a, c) -> mulmod_beauregard!(t, a, N, c)`. For E:
     `(t, a, c) -> _shor_mulmod_E_controlled!(t, a, c; c_mul=c_mul)`.
  4. **Tests**: existing `test_shor.jl` Impl D-semi + Impl E testsets
     must keep passing. Run via:
     `OMP_NUM_THREADS=16 LIBORKAN_PATH=... julia --project -e 'using Sturm, Test; include("test/test_shor.jl")'`
     (~15 minutes total).
  5. **Closure**: bead dxk closes; future Mosca-Ekert variant (`npd`)
     becomes a 5-line wrapper around the same helper.

### Environment reminders for next agent

  * `OMP_NUM_THREADS=16` — confirmed working on this device (64 HW
    threads); Sturm respects pre-set value, won't downcap.
  * `LIBORKAN_PATH=/home/tobiasosborne/Projects/orkan/cmake-build-release/src/liborkan.so`
  * Julia processes MUST be strictly serial on this device (per saved
    feedback memory) — never run two `julia --project` concurrently.
  * Verbose output: `println + flush(stdout)` per stage, ENTER/EXIT
    tags, wall-clock per shot. Blank-screen-waiting is a fail.
  * Slow-test discipline: `probe_*.jl` for benches, `test_*.jl` for
    registered. Never put a >10-min test in the registered suite.

---

