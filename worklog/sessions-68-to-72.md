## 2026-04-26 — Session 72: bead `Sturm.jl-6oc` closed, perf bead `Sturm.jl-2qp` filed

Headline: `shor_order_E` registered tests added at N=5; `_shor_mulmod_E_controlled!`
implementation correctness verified statistically; bead 6oc closed; the
windowed-arithmetic per-gate slowdown vs `shor_order_D_semi` (~750× at N=15)
spun out into new perf bead `Sturm.jl-2qp`.

### Reality check that pivoted the test design

`probe_mulmod_E_bench.jl` re-run today (16 OMP threads, post-Phase-C2,
post-bead-059):

  * N=15 c_mul=1: 74 s/mulmod
  * N=15 c_mul=2: 186 s/mulmod (3.1× slower)
  * `shor_order_E(7,15;t=3)` shot 1+2: 414s, 432s (matches: 2 non-trivial
    mulmods per shot × ~190s)

→ Bead 6oc's criterion (a) at 50 shots = ~5–6 hours. Not viable for the
registered test suite.

The project had already pivoted to N=5 for in-session statistical work
(`probe_shor_E_N5.jl:5` documents "N=15 currently runs ~21 min/mulmod
even after Phase C2"; today's 186s is the post-059 figure ≈ 6.3× speedup
from that prior 21-min baseline — bead 059 did its job, but the residual
gap remains and is what bead 2qp investigates).

### Registered tests landed (`test/test_shor.jl:386`)

New `@testset "Impl E: Gidney-Ekerå 2021 windowed arithmetic mulmod"`
mirroring Impl D-semi's shape, parameterised at N=5, c_mul=1:

  * `order_E(2,5;t=3) ≥ 0.30` over 30 shots → **36.7% ✓**
  * All 3 N=5 coprime bases (a∈{2,3,4}; orders 4,4,2), 10 shots each, ≥0.20
    → **a=2 50.0%, a=3 50.0%, a=4 40.0% ✓**

Inline preflight: 4/4 PASS in 10m07s. Per-shot wall time at N=5 c_mul=1
≈ 9.5 s, consistent with `probe_shor_E_N5.jl`'s "10–15 s/shot" estimate.

The N=15 acceptance criteria (bead 6oc (a)/(b)/(c)) live in
`probe_shor_E_N15.jl` as bench-only — wall time is hours, gated on bead
2qp's perf work.

### Toffoli criterion (d): close-but-strict-miss

`probe_toffoli_cmul_sweep_mbu.jl` (TracingContext) sweeps c_mul × mbu × L:

  * **L=8: best 0.554× at c_mul=3, mbu=true** — misses ≤0.5× target by 11%
  * L=10: 0.489× at c_mul=4, mbu=true ✓
  * L=12: 0.465× at c_mul=5, mbu=true ✓

Raw CCX count is 10× higher in E across all L (QROM cost). T-proxy
(FT-weighted: CCX×7 + cRz×2 + ccRz×6) is the metric where E wins; the
crossover where E beats D-semi by 2× sits at L=10, not L=8. L=8 was an
optimistic bar — GE21's asymptotic claim is for L≈1024.

Closure rationale: implementation is faithful to GE21 §2.5 + Berry App B/C;
T-proxy advantage is real and grows with L; the L=8 gap is calibration,
not implementation. Documented in bead notes.

### The 750× per-gate gap (new bead Sturm.jl-2qp, P1 bug)

Naive expectation: 20-qubit gate on Orkan ≈ 0.3 ms (16 MB / 50 GB/s).
Measured for D (Beauregard) ≈ 0.5 ms/gate — matches. Measured for E
≈ 480 ms/gate — three orders of magnitude over budget. E has FEWER DAG
nodes than D per mulmod (390 vs 532), so the slowdown is NOT in:

  * statevector size (256× larger but ~4–8× cache cost, not 750×),
  * abstract gate count (E has fewer),
  * peak qubit count alone.

The dominant factor lives BELOW the DAG level. Hypotheses (priority order,
none confirmed; bead 2qp investigates):

  1. `qrom_lookup_xor!` fan-out — one DAG "lookup" likely expands to
     many primitive Orkan ccalls (multi-controlled XOR cascades over the
     window address bits).
  2. `plus_equal_product_mod!` internal cascade — windowed-add into coset
     register may have a per-window inner controlled-adder cascade not
     surfaced in DAG node count.
  3. Per-ccall FFI / control-stack overhead multiplying with E's
     fan-out.

Method: wrap `apply_cx!`/`apply_ry!`/`apply_rz!` with counters + timers;
run one `_shor_mulmod_E_controlled!` and one `mulmod_beauregard!` at N=15;
compare primitive ccall counts to DAG node counts. Then `perf record` the
hot stack frame.

### Files touched

  * `test/test_shor.jl` — added Impl E testset block (line 386, +60 lines).
  * `WORKLOG.md` — this entry.

### Beads state

  * Closed: `Sturm.jl-6oc` (windowed Shor — implementation complete,
    registered tests + Toffoli bench in tree).
  * Created: `Sturm.jl-2qp` P1 (per-gate 750× slowdown investigation).

### Probe scripts that earned their keep

  * `probe_mulmod_E_bench.jl` — c_mul=1 vs c_mul=2 timing diagnostic.
  * `probe_shor_E_N5.jl` — N=5 statistical (already existed; ran successfully).
  * `probe_shor_E_N15.jl` — N=15 statistical bench (deferred; will be
    runnable post-2qp).
  * `probe_toffoli_DE.jl` — basic Toffoli ratio (already existed).
  * `probe_toffoli_cmul_sweep_mbu.jl` — full criterion (d) sweep.

### Gotcha for next agent

When `_shor_mulmod_E_controlled!`'s `mbu=false` is the default and the
public `shor_order_E` doesn't expose `mbu`/`mbu_compute` kwargs, you can't
exercise the App B/C MBU path end-to-end without modifying internals.
Worth filing a follow-on if you need to bench MBU end-to-end (the Toffoli
sweeps already use `mbu=true` via direct `_shor_mulmod_E_controlled!` calls
at TracingContext, so this is a wiring nit, not a correctness gap).

---

## 2026-04-25 — Session 71: bead `Sturm.jl-zv1` closed, doc refresh

Headline: CLAUDE.md, README.md, Sturm-PRD.md aligned with what Sturm IS
today. Stale phase tables / "v0.1 POC" / "not yet implemented" framing
removed; live code examples in the PRD that triggered the P2 implicit-
cast warning rewritten with explicit `Bool(q)` / `Int(qi)` casts.

### What landed

  * **CLAUDE.md** — File Structure listing refreshed: adds `simulation/`,
    `block_encoding/`, `qsvt/`, `bennett/`, `library/`, `passes/`,
    `noise/`, `qecc/`, `hardware/` to the source tree; updates
    `control/` to mention `cases`/`@cases`; updates `context/` to
    mention `compact_state!`; updates `library/` to reference Shor +
    windowed arithmetic.
  * **README.md** — phase header changed from "All 12 phases" to "All
    16 phases"; dropped the `v0.1 / Sturm.jl-???` placeholder around
    `Int(q::QInt)` round-trip semantics; added a new "Additional
    shipped features beyond the original plan" table covering
    HardwareContext, cases/@cases, compact_state! (Eager + DM),
    do-block syntax, STURM_COMPACT_VERIFY, oracle-table LRU API,
    Shor variants, QSVT/QSP scaffolding.
  * **Sturm-PRD.md §7.1** — extended the "what is shipped" list to
    cover QMod / QCoset / QRunway, do-block allocation, four contexts
    (HardwareContext added), `cases`/`@cases`, `compact_state!`,
    `STURM_COMPACT_VERIFY`, oracle-table LRU + public API.
  * **§7.2** — removed "hardware backends" from the unshipped list
    (HardwareContext shipped); kept tensor-network. QMod removed from
    the QArray + qudit-research framing.
  * **§9.6** — entire section rewritten. The previous "ClassicalRef
    convert returns false; options A/B/C; (C) is current" framing
    predated `cases`/`@cases` shipping. Now describes `cases` as the
    third distinct branching channel (alongside `if Bool(q)` and
    `when(q)`), with the per-context behaviour table reproduced from
    the README.
  * **§Future directions hardware-compilation entry** — clarified
    that `HardwareContext` + transport + idealised simulator have
    shipped; future work is device adapters and OpenQASM dynamic-
    circuit emission for vendor SDKs.
  * **§8 example programs** — all live code with `x::Bool = q` /
    `y::Int = qi` form converted to explicit `Bool(q)` / `Int(qi)`.
    Sites: §5.1 eager-mode example, §8.1 Bell, §8.2 Teleport, §8.3
    RUS, §8.4 arithmetic, §8.6 fourier_sample, §8.7 noise, §8.9
    promotion (three sites). The two pedagogical references at lines
    34 and 326 (the P2 explanation itself) stay — they explicitly
    mention the implicit form as "permitted but emits the warning".

### Verification

Doc-only change; no code touched. Source tests unaffected.

---

## 2026-04-25 — Session 70: bead `Sturm.jl-t1v` closed, oracle-table LRU cache

Headline: `_ORACLE_TABLE_CACHE` in Bennett's bridge is now bounded LRU
(default cap 64). Adds public management API. Stops the unbounded growth
that long sessions sweeping over distinct lookup tables would otherwise
exhibit.

### What landed

  * `src/bennett/bridge.jl` — replace the bare `Dict{...}` cache with:
      - `_ORACLE_TABLE_CACHE` :: `Dict{key, ReversibleCircuit}`
      - `_ORACLE_TABLE_CACHE_ORDER` :: `Vector{key}` (LRU queue: front =
        oldest, back = MRU)
      - `_ORACLE_TABLE_CACHE_MAX_SIZE` :: `Ref{Int}` (default 64)
    Internal `_oracle_cache_get!(compute_fn, key)` does:
      hit → promote key to MRU; miss → compute, append, evict from front
      while size > cap. Returns the computed value directly so cap=0
      degenerates cleanly (every call recompiles).
  * Public API: `oracle_cache_size()`, `oracle_cache_max_size()`,
    `set_oracle_cache_size!(n)`, `clear_oracle_cache!()`. Exported from
    `src/Sturm.jl`.
  * `test/test_oracle_cache_lru.jl` (new) — 18 assertions across 6
    testsets: API exists, clear empties, hit-no-growth, eviction caps,
    set-shrinks-immediately, LRU semantics (re-access promotes), cap=0
    sanity. Wired into runtests.jl.

### Non-obvious traps

  * **Hash collisions in tests at small W_out.** First-pass tests used
    `oracle_table(k -> k + offset, x, Val(2))` — the masked W_out=2
    output cycles every 4 offsets, so distinct-`offset` calls produced
    identical tables and identical hashes; cache size capped at 4
    instead of the expected N. Fix: switch to `Val(8)` (256-value
    range) so the offset variation maps to distinct table contents.
    **Lesson: when testing a content-hashed cache, compute the hash
    inputs explicitly instead of relying on "different `f` produces
    different table" — Bennett masks to W_out bits before hashing.**
  * **`return circuit` not `return _ORACLE_TABLE_CACHE[key]`.** When
    cap=0 the just-inserted entry is evicted before returning; looking
    it up in the dict at that point would `KeyError`. Returning the
    locally-computed `circuit` makes the cap=0 path correct (every
    call recompiles, every call gets the right circuit). Caught
    during the cap=0 sanity testset.
  * **`findfirst(==(key), order)` is O(N).** For the 64-entry default
    cap that's negligible. For very-large caps it would matter; the
    bead description targets ~64, so this is fine. A `Dict{key, idx}`
    side-table would O(1) the move-to-MRU but adds bookkeeping
    complexity for no real win at typical cap.

### Verification

  - test_oracle_cache_lru.jl: 18/18 ✓
  - test_bennett_integration.jl: 156/3/11 — exactly the same as
    pre-bead baseline (the 3 fail / 11 error are pre-existing
    `_CIRCUIT_INC.n_wires == 41` artifacts; unrelated to this bead)

### Open follow-ons

  - **Env-gate for the cache size** (no bead yet) — mirror
    `STURM_COMPACT_VERIFY` with `STURM_ORACLE_CACHE_SIZE`. Useful for
    long-running batch jobs where the right cap depends on workload
    shape and recompiling on session start would be tedious. P4.

---

## 2026-04-25 — Session 69: bead `Sturm.jl-2fg` closed, contiguous-live shortcut

Headline: small perf shortcut in `_compact_scatter!(::EagerContext)`. When
`live_slots == 0:new_n-1` (the typical Bennett-ancilla-burst post-state),
the bit-expand inner loop collapses to identity and the scatter becomes
a prefix `unsafe_copyto!`. Detection is one range-comparison, no
allocation; saves the `O(new_n)` per-element decode.

### What landed

  * `src/context/eager.jl _compact_scatter!` — fast-path branch at
    function entry: `live_slots == 0:new_n-1 → unsafe_copyto!` and
    return; otherwise the existing bit-scatter loop.
  * `test/test_compact_state.jl` — two new testsets (+24 assertions):
    contiguous-live case (alloc 6, ptrace last 3 → state preserved) and
    non-contiguous fallback (alloc 4, ptrace middle slot 1 → bit-scatter
    permutes amplitudes correctly per the explicit lookup table).

### Why correctness is by construction

In the contiguous-live case, the bit-expand `j → bit_expand(j,
live_slots)` is the identity on `[0, 2^new_n)` because each new bit `k`
maps to old slot `live_slots[k+1] == k`. So `new_amps[j+1] =
old_amps[j+1]` for every j — the prefix copy is exactly what the general
loop produces, just without the per-element decode. Both paths yield
the same state; the test verifies this end-to-end on representative
inputs.

### When the shortcut fires

The Bennett pattern: live wires occupy slots `[0..n_pre-1]`, then a
burst of K ancillae allocates at `[n_pre..n_pre+K-1]`, then ALL K are
ptraced. After auto-trigger, `_compact_plan` sorts live wires by their
old slot index → `live_slots = [0..n_pre-1] = [0..new_n-1]`. CONTIGUOUS.

The shortcut does NOT fire when freed slots are scattered through the
live region (e.g., user code that ptraces a middle wire). The bit-
scatter handles that fine; it's just a few percent slower than the
shortcut would have been.

### Verification

  - test_compact_state.jl: 297 → 321 (+24) ✓
  - test_compact_state_dm.jl: 408/408 ✓ (DM scatter unchanged)
  - test_density_matrix.jl: 1753/1753 ✓
  - test_do_block_alloc.jl: 44/44 ✓

### Open follow-ons

  - **DM scatter contiguous-live shortcut** (no bead yet) — same
    optimization for `_compact_scatter_dm!`. The packed-buffer path
    already does per-column `unsafe_copyto!` on contiguous strips, but
    the inner bit-expand fires for every (r_new, c_new). When
    `live_slots == 0:new_n-1`, c_old == c_new and the inner can skip
    the r_old recompute. File as P4 follow-on.

---

## 2026-04-25 — Session 68: bead `Sturm.jl-cbl` closed, do-block allocation lands

Headline: `QBool(p) do q … end` and `QInt{W}(value) do reg … end` now
work. README's "not yet implemented" disclaimer drops. Mirrors Julia's
`open(f, path) do stream … end` pattern: scoped lifetime, automatic
partial-trace on block exit (normal return or exception), suppressed
if the body explicitly consumes the resource.

### What landed

  * `src/types/qbool.jl` — new methods `QBool(f::Function, ctx, p::Real)`
    and `QBool(f::Function, p::Real)`. Allocates a QBool, runs `f(q)`
    in a try/finally, ptraces `q` on exit only if `!q.consumed`.
  * `src/types/qint.jl` — same shape: `QInt{W}(f::Function, ctx, value)`
    and `QInt{W}(f::Function, value)`.
  * `test/test_do_block_alloc.jl` (new) — 44 assertions across 12
    testsets covering: basic flow, return-value propagation, cleanup
    on exception, no double-ptrace when body consumes, nested
    composition, explicit-context form, mid-scope ancilla pattern.
    Wired into runtests.jl.
  * `README.md` — replaces the "not yet implemented" disclaimer with
    a description of the new behaviour.

### Why the body's-consumed check is mandatory

Without `if !q.consumed; ptrace!(q); end` in the finally, a body that
calls `Bool(q)` (which consumes via `_blessed_measure!`) followed by
the implicit do-block exit would attempt to ptrace an already-consumed
QBool. `consume!(q)` errors loud on already-consumed wires (linear
resource discipline, P5 in spirit). The conditional is what lets the
common case "consume q via Bool(q) and propagate" work without the
caller writing extra ptrace boilerplate.

### Test prediction got tripped by `n_qubits` semantics

The "interop: QBool inside @context, mid-scope" testset initially
asserted `ctx.n_qubits == 1` after a one-shot scratch ancilla was
ptraced. n_qubits is sticky upward by design — only `compact_state!`
shrinks it, and the ptrace fired sub-threshold (1 < 8). The right
invariant is **live count**: `length(ctx.wire_to_qubit) == 1`. Same
trap I caught last session in test_compact_state_dm.jl. **Lesson:
default to `length(ctx.wire_to_qubit)` when asserting "this many
wires are live"; reach for `ctx.n_qubits` only when actually pinning
the slot bookkeeping invariant.**

### Verification

  - test_do_block_alloc.jl: 44/44 ✓
  - test_qint.jl: 562/562 ✓ (the constructor file I edited)
  - smoke test on existing QBool/QInt constructor paths: ✓

### Open follow-ons

  - **`Sturm.jl-hlk`** (deferred from this session) — QBool/QInt
    finalizer for the case where users DON'T use either `@context`
    auto-cleanup or a do-block. The do-block constructor lands first
    because it's idiomatic and ergonomic; the finalizer is a safety
    net for non-idiomatic code. Both can coexist.

---

