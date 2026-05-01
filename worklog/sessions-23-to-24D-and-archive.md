## 2026-04-18 — Session 24D: Close `xcu` (multi-controlled gates on DensityMatrixContext)

`DensityMatrixContext` errored "not yet implemented" on every multi-controlled
variant of `apply_ry!`/`apply_rz!`/`apply_cx!`/`apply_ccx!` (density.jl lines
109/125/138/149). Consequence: any noise-circuit demo using nested `when()`
was broken. This bead ports EagerContext's Toffoli cascade to DM, via a
shared helper file.

### Key insight (from 4 parallel Sonnet Explore agents)

The bead's hint ("Toffoli cascade on density matrix via Kraus superop
composition") was half-right. Orkan's gate ABI is **state-type-agnostic**:
`orkan_ry!`, `orkan_cx!`, `orkan_ccx!` all dispatch internally on
`state->type` (`ORKAN_PURE` vs `ORKAN_MIXED_PACKED` vs `ORKAN_MIXED_TILED`)
and already compute `U ρ U†` on mixed states. There is no Kraus
decomposition needed for coherent gates — they are single-Kraus unitary
channels, and Orkan handles the `UρU†` conjugation internally.

Confirmed via Orkan source inspection:

- `gate.h` declares the full gate API without any density-specific variants.
- `orkan_channel_1q!` exists for *noise* channels (1-qubit Kraus), but is
  not needed for controlled unitaries.
- Orkan has NO multi-controlled primitive on either state type — the ceiling
  is `ccx` (1-target, 2-control Toffoli).

So the cascade mirroring EagerContext exactly is correct on DM, with zero
FFI changes.

### Refactor: shared `multi_control.jl`

Moved the 6 helpers (`_controlled_ry!`, `_controlled_rz!`,
`_toffoli_cascade_forward!`, `_toffoli_cascade_reverse!`,
`_multi_controlled_gate!`, `_multi_controlled_cx!`) out of `eager.jl` into a
new file `src/context/multi_control.jl`, typed on
`Union{EagerContext, DensityMatrixContext}` so both contexts dispatch to
them. The file must be included AFTER both context types are defined
(Julia cannot resolve a `Union{T, U}` type parameter until both are
available) — registered in `Sturm.jl` as the third `context/` include.

`eager.jl` and `density.jl` now have IDENTICAL `apply_ry!`/`apply_rz!`/
`apply_cx!`/`apply_ccx!` dispatch shapes (nc=0 → raw; nc=1 → ABC or CCX;
nc≥2 → cascade). No duplication.

### Ground-truth check triggered by user prompt mid-session

User asked "did you read the Nielsen and Chuang ground truth? are the
equations matched?" I had NOT — I copied comments from eager.jl forward
without verifying. Re-read `docs/physics/nielsen_chuang_4.3.md` and
verified algebraically:

- At ctrl=|0⟩: CX ≡ I, so `Ry(−θ/2)·Ry(θ/2) = I`. ✓
- At ctrl=|1⟩: CX ≡ X on target, composed (right-to-left) =
  `X·Ry(−θ/2)·X · Ry(θ/2)`. Using `X·Ry(α)·X = Ry(−α)`:
  `Ry(θ/2)·Ry(θ/2) = Ry(θ)`. ✓

Barenco et al. 1995 Lemma 7.2 had no local PDF — pre-existing docs gap
from eager.jl. Wrote `docs/physics/toffoli_cascade.md` with a self-
contained derivation (computational-basis induction on AND-reduction +
linearity + single-Kraus density-matrix extension). Pointed
`multi_control.jl`'s reference comment at the new local doc.

**Lesson for future agents:** when extracting/copying code with docstring
references, read the local physics doc before shipping. Do not copy the
reference forward. This is a literal letter-of-rule-4 issue.

### Tests — `test/test_density_matrix_mc.jl` (new)

17 testsets covering:

- Depth 2 nested-when CCRy / CCRz / CCX — deterministic cases on all
  control-bit combinations.
- Depth 2 `apply_cx!` inside nested-when — effective CCCX via cascade.
- Depth 2 `apply_ccx!` inside `when()` — uses the path that pushes `c1`
  onto the stack and runs multi-controlled CX with `c2`.
- Depth 3 triple-nested `when()` — effective 4-way AND. Verifies the
  Toffoli cascade allocates 2 workspace qubits and uncomputes them.
- Superposition entanglement: `c1=|+⟩, c2=|1⟩, t=|0⟩` nested-when should
  leave `c1` and `t` perfectly correlated across shots. 200/200 passed.
- Workspace recycling: after a depth-3 cascade, `length(ctx.wire_to_qubit)`
  reports 4 user qubits (c1, c2, c3, t), confirming the 2 workspace
  ancillae were correctly deallocated.

Registered in `test/runtests.jl` immediately after `test_density_matrix.jl`.

### Verification

- `test_density_matrix.jl` 1753/1753 (regression)
- `test_density_matrix_mc.jl` 17/17 (new)
- `test_noise.jl` 506/506 (regression)
- `test_when.jl` 507/507 (regression after refactor)
- Classicalise testset 12/12

### Process notes

The 4-parallel-Sonnet Explore pattern was effective for this bead: one
afternoon's worth of disambiguation done in maybe 3 minutes of parallel
exploration. Template for future big beads: spawn agents that each cover
(a) the "before" state of a module, (b) the reference implementation to
mirror, (c) existing test patterns, (d) the FFI / lower-layer surface.
Keep each under 800 words with code excerpts; synthesise the convergent
findings before reading ground truth in detail.

### Files touched

- `src/context/multi_control.jl` (new, 102 lines): shared cascade helpers.
- `src/context/eager.jl`: removed helpers (−108 lines), kept the dispatch
  in `apply_*!`.
- `src/context/density.jl`: restructured `apply_ry!`/`apply_rz!`/`apply_cx!`
  to mirror eager.jl's nc=0/1/≥2 tree; replaced four
  `error("not yet implemented")` with cascade calls.
- `src/Sturm.jl`: include `context/multi_control.jl` after both context
  files.
- `test/test_density_matrix_mc.jl` (new), `test/runtests.jl` (include).
- `docs/physics/toffoli_cascade.md` (new): self-contained derivation of
  the multi-controlled cascade, with the density-matrix extension
  explicit.
- `WORKLOG.md`: this entry.

---

## 2026-04-18 — Session 24C: Close `f23` (P2 implicit quantum→classical cast warning)

The P2 axiom says measurement is a cast with implied information loss, and
implicit assignments (`x::Bool = q`) must warn. Prior to this session the
codebase defined `Base.Bool(q::QBool) = convert(Bool, q)` — one path for
both explicit constructor calls AND implicit annotated assignments — so
nothing could distinguish them. This bead fixes that.

### Design (from the conversation, not agent-proposed)

Split the constructor from `convert`:

- `Base.Bool(q::QBool)` / `Base.Int(q::QInt{W})` hold the actual
  measurement. Silent, the blessed explicit path.
- `Base.convert(::Type{Bool}, q::QBool)` / `convert(::Type{Int}, q::QInt{W})`
  emit the P2 warning, then delegate to the constructor.

Julia desugars `x::Bool = q` to `x = convert(Bool, q)`, so implicit
assignments flow through the warning path; explicit `Bool(q)` calls skip
it entirely. No macro rewriting, no special hooks — just the standard
Julia conversion system doing what it already did, with the warning added
on the convert side.

### Warning helper (`src/types/quantum.jl`)

- `_first_user_frame(frames)` walks the stacktrace and returns the first
  frame whose `file` is outside `src/types/quantum.jl:_STURM_SRC_ROOT`
  (= the parent of `src/types/`). That is the user's call site.
- `_warn_implicit_cast(::Type{From}, ::Type{To})` emits
  `@warn … maxlog=1 _id=(:sturm_implicit_cast, file, line)` with
  `_file=file _line=line` so the reported location is the user's site, not
  the Sturm internal line. `_id` tuples dedupe per source location: loop
  iterations at one site share one warning; two different sites each get
  their own.
- `with_silent_casts(f)` flips `task_local_storage(:sturm_implicit_cast_silent, true)`
  for the duration of `f()`, restoring the previous value in `finally`.
  Nests correctly via save/restore, parallels the `@context` macro.

### `if q`, `classicalise(ch)` — out of scope

- `if q::QBool` currently hits Julia's runtime `TypeError: non-boolean
  used in boolean context`. Julia's `if` does NOT auto-call `Bool(cond)` —
  the runtime checks `isa(cond, Bool)` and errors otherwise. The PRD §P4
  claim that `if q` emits the P2 warning + measures + branches is
  unreachable without source-level macro rewriting. Deferred; not f23.
- `classicalise(f)` has no implicit entry point (only invoked by name),
  so the channel-level cast is already behaviorally "explicit". The bead's
  "classicalise behaves the same way" acceptance criterion is satisfied
  with no code change.

### Regression: existing test code used implicit casts

Running `test_bell.jl` / `test_teleportation.jl` / `test_rus.jl` after the
fix surfaced eight `::Bool = q` / `::Int = qi` call sites in our own test
code. That is exactly what the warning is supposed to flag — the tests
were written in the pre-axiom style. Converted all eight to explicit
`Bool(q)` / `Int(q)` forms. Same measurement semantics, now silent in
the new logger output. The warning mechanism catching our own code is
itself a validation that the dispatch split works.

### Gotcha: `local _::Bool = q` is invalid Julia syntax

First draft of `test_implicit_cast.jl` used `local _::Bool = q` to
anonymise an unused measurement result. Julia rejects with
`syntax: type declaration for global "_" not at top level` — `_` cannot
carry a type annotation. Renamed to `local dummy::Bool = q`. Leaving this
note because it is not an intuitive syntax error if you have not hit it.

### Stale PRD examples (not fixing here — scope)

`Sturm-PRD.md` contains ~10 `::Bool = q` / `::Int = qi` pedagogical
examples. These now would trigger warnings if copy-pasted. Flagged on
`zv1` (docs refresh) — not expanding f23's scope.

### Verification

- `test/test_implicit_cast.jl` (new): 14 passes. Covers explicit silent,
  implicit warns, both QBool and QInt, message text includes the fix
  suggestion, `with_silent_casts` suppresses + returns block value +
  nests.
- `test_bell.jl` 2002/2002, `test_teleportation.jl` 1002/1002,
  `test_rus.jl` 205/205 — all green after the explicit-cast conversion.

### Files touched

- `src/types/quantum.jl`: `_first_user_frame`, `_warn_implicit_cast`,
  `with_silent_casts`, P2 header comment.
- `src/types/qbool.jl`: split `Base.Bool` / `Base.convert`.
- `src/types/qint.jl`: split `Base.Int` / `Base.convert`.
- `src/Sturm.jl`: export `with_silent_casts`.
- `test/test_implicit_cast.jl` (new), `test/runtests.jl` (include).
- `test/test_bell.jl`, `test/test_teleportation.jl`, `test/test_rus.jl`:
  convert to explicit casts.
- `README.md`: one-line note about `with_silent_casts` opt-out.
- `WORKLOG.md`: this entry.

---

## 2026-04-18 — Session 24B: Close `q93` (oracle arg-type inference from W)

`bridge.jl` hardcoded `Int8` as the classical argument type Bennett compiles
against, regardless of `QInt{W}` width. Bennett's `_narrow_ir` pass then
uniformly rewrote widths to `W`, which papered over the mismatch for simple
modular arithmetic — but it is still a type lie (constants, comparisons, and
any Julia dispatch path inside `f` sees Int8 when the register is 16 bits).

### Fix

New helper `_bennett_arg_type(W; signed=true)` in `src/bennett/bridge.jl`
picks the narrowest fitting `Int*` / `UInt*`: W≤8→Int8, W≤16→Int16,
W≤32→Int32, W≤64→Int64; `signed=false` flips to the `UInt*` variant;
W>64 errors. Both `oracle(f, x; signed=true, kw...)` and the `QuantumOracle`
call operator route through the helper. The cache key on `QuantumOracle`
widens from `(W, kwargs)` to `(W, signed, kwargs)` so switching signedness
forces a recompile rather than silently reusing a stale circuit (the same
discipline Session 20 applied for strategy kwargs).

### Ground-truth probe results (not in the bead acceptance test)

Bead's acceptance test was `oracle(x -> x * 1000, QInt{16}(v))`. This
cannot run on this machine:

1. `reversible_compile` with an IR containing a multiplication grows Orkan's
   register above the 30-qubit `MAX_QUBITS` cap even at `W=4` — 69 qubits
   for `estimate_oracle_resources(x -> x * 10, Int8; bit_width=4)`. At
   `W=16` it would be far worse.
2. The README (lines ~146-200) advertises `strategy=:tabulate` as a kwarg
   on `reversible_compile`, supposedly landed by Bennett-cfjx per Session
   22. It is NOT present in the current Bennett source — the signature is
   `(bit_width, add, mul, optimize, max_loop_iterations, compact_calls)`
   only. Either Session 22 misreported, or the feature was reverted
   upstream. README is stale on this point. **Filed as a separate concern**
   — not expanding q93 scope.

Because of (1) + (2), q93 tests stay at `W=2` (the largest width that
actually fits mul-bearing circuits today). The type-system fix is verified
via direct unit tests on `_bennett_arg_type` plus regression on existing
W=2 paths.

### Test additions — `test/test_bennett_integration.jl`

- `_bennett_arg_type` returns correct type across the full W range for both
  `signed=true` and `signed=false`. 32 cases.
- Out-of-range (`W ≤ 0` or `W > 64`) errors.
- `oracle` at W=2 works with both `signed=true` (default) and
  `signed=false`. Regression + new path.
- `QuantumOracle` cache distinguishes `signed=true` from `signed=false`
  with the same W — `length(qf.cache) == 2` after two calls.
- The pre-existing `haskey(qf.cache, (W, ()))` tests in the
  "caches circuit across calls" and "different widths use different cache
  entries" testsets updated to the new `(W, signed, ())` shape. Two lines.

### Files touched

- `src/bennett/bridge.jl`: `_bennett_arg_type` helper; `oracle` +
  `QuantumOracle` call operator take `signed::Bool=true`; cache key widens
  to `(W, signed, kwargs)`.
- `test/test_bennett_integration.jl`: new `@testset verbose=true "arg-type
  selection by W"` block; two existing `haskey` asserts updated.
- `WORKLOG.md`: this entry.

### Lesson for future agents

The README and WORKLOG Session 22 both claimed `strategy=:tabulate` was a
Bennett-level kwarg. A quick `grep -r tabulate` on
`/home/tobiasosborne/Projects/Bennett.jl` would have surfaced the
discrepancy in seconds. Before writing any acceptance test that depends on
an upstream feature, verify the feature still exists in upstream — session
summaries and docs drift.

### Stale README entries discovered

1. Lines ~146-200 describe `strategy=:tabulate` as a live Bennett kwarg.
   Not present. Would need either the Bennett kwarg to land, or the README
   to stop advertising it.
2. The bit_width=2 polynomial showcase claims 9 wires via `:auto →
   :tabulate`. Today's `estimate_oracle_resources(x -> x^2 + 3x + 1,
   Int8; bit_width=2)` would need confirming once we have a reliable
   tabulate path.

Not fixing in this session — filing under the existing `zv1` docs-refresh
bead would be cleanest. Flagged in the bead's notes at close time.

---

## 2026-04-18 — Session 24: Close `1f3` (QDrift / Composite RNG injection)

Picked up Session 23's in-progress bead. Code for `rng::AbstractRNG` threading
had already landed; what was outstanding was end-to-end verification of the
`@context` closure pattern, and — discovered this session — a vacuous test.

### Ground truth before coding

Per the user's standing preference (`feedback_ground_truth_first`): read
`src/simulation/qdrift.jl`, `src/simulation/composite.jl`,
`test/test_qdrift.jl`, `test/test_composite.jl`, and the `@context` macro in
`src/context/abstract.jl` BEFORE running anything. Confirmed:

- QDrift: `rng::AbstractRNG` field, constructor kwarg, `_sample(dist, alg.rng)`
  threaded at `qdrift.jl:122`.
- Composite: `rng` field + kwarg, threaded in BOTH branches of
  `_apply_composite!` (pure-qDRIFT degenerate case at `composite.jl:106` via
  `QDrift(..., rng=alg.rng)`, and the interleaved loop at `composite.jl:123`
  via `_sample(dist, alg.rng)`).
- `@context` macro at `context/abstract.jl:93-107` returns the body's last
  expression via `try ... finally`. The `run_once()` closure pattern is sound:
  `a` as the trailing expression of the `begin...end` becomes the return
  value.

### Gotcha: the committed Composite test was vacuous

The Session-23 committed test used
`Composite(steps=2, qdrift_samples=10, cutoff=0.5, …)` with
`ising(Val(3), J=1.0, h=0.5)`. At cutoff=0.5 both coefficients satisfy
`|hⱼ| ≥ cutoff`, so `_partition` puts ALL terms in the Trotter partition and
returns `B = nothing`. Control flow takes the degenerate branch
(`composite.jl:99-102`) which never consults the RNG. The
`amps_a == amps_b` assertion held, but only because the circuit is fully
deterministic — not because the RNG was threaded.

Probed via:

```
julia> _partition(ising(Val(3), J=1.0, h=0.5), 0.5)
# A=nterms=5, B=nothing           ← vacuous at cutoff=0.5

julia> _partition(ising(Val(3), J=1.0, h=0.5), 0.75)
# A=nterms=2, B=nterms=3          ← 2 ZZ in Trotter, 3 X in qDRIFT
```

**Lesson for future tests on `Composite`**: pick the cutoff BY INSPECTING
the Hamiltonian's coefficient magnitudes, not by mirroring whatever the
construction docstring happens to default to. A `_partition(H, cutoff)` probe
before committing an RNG-threading test catches this trivially.

### Fix

Both committed testsets hardened with an alt-seed sanity check
(`amps_a != amps_c` where `a = seed 42`, `c = seed 99`). The Composite test
also switches to `cutoff=0.75` with a rationale comment inline
(`test_composite.jl:309-329`). Now:

- If the RNG kwarg is stored but not threaded → same-seed equal still holds
  (vacuous), alt-seed differ FAILS loudly. Test catches the bug.
- If the RNG is threaded correctly → both assertions hold.

### Verification (targeted probe, not full suite)

```
LIBORKAN_PATH=…/liborkan.so julia --project -e '…'
[1/3] sample-sequence determinism: OK
[2/3] QDrift end-to-end determinism: OK (same-seed equal, alt-seed differ)
[3/3] Composite end-to-end determinism: OK (same-seed equal, alt-seed differ)
ALL OK
```

Full `test_qdrift.jl` / `test_composite.jl` runs skipped per the
`sturm-jl-test-suite-slow` memory — the modified testsets were exercised
as-written by the probe.

### Bead closure

`Sturm.jl-1f3` closed. End-to-end verification done. The reproducibility
contract (seeded `rng` → byte-identical Orkan amplitudes) now has a test
that actually exercises the qDRIFT partition.

### Environment note

`LIBORKAN_PATH` is `/home/tobiasosborne/Projects/orkan/…` on this device.
The memory entry `device-performance-do-not-run-full-test-suite` had
`/home/tobias/Projects/orkan/…`; that path does not exist here. The correct
prefix is `/home/tobiasosborne/`. (Not updating the memory this session;
leaving as a known discrepancy.)

### Files touched

- `test/test_qdrift.jl` (lines 466-485): `run_once(seed)`, alt-seed assertion.
- `test/test_composite.jl` (lines 309-329): `cutoff=0.5 → 0.75`,
  `run_once(seed)`, alt-seed assertion, rationale comment.
- `WORKLOG.md`: this entry.

---

## 2026-04-17 — Session 23: Harmonise repo against PRD and vision

Full-day session. Shape: (1) stocktake across the whole codebase (122 files, ~9.5k src LOC), (2) beads triage — delete the future-vision epics that no longer match direction, (3) file replacement beads covering the real state-based findings, (4) revise PRD/docs to match current code + the "four pillars" vision from user's blog draft, (5) execute a run of easy beads.

### Vision (from author's blog + A1 discussion)

Sturm.jl is NOT a new language. It is Julia, extended. Quantum algorithms written in idiomatic Julia at the level of channels / operators / higher-order patterns, compiled by the package to circuits. Four pillars:

1. **Expressive** — no gates, no qubits in user code; registers and higher-order patterns.
2. **Compiler quality** — DAG IR optimised by publishable passes; new circuit-construction papers shippable as transformations.
3. **Extensible** — new pass APIs integrate in hours (as the Bennett.jl + Sun-Borissov experience demonstrated).
4. **Backend-agnostic** — Orkan, simulators, tensor networks, hardware all substitutable behind `AbstractContext`.

Everything else in the PRD (`P1`–`P9`) reads under this framing. See Sturm-PRD.md after this session's revision.

### Beads harmonisation

**Deleted 10** (multi-path arithmetic Phases 2-7: `xfk, adj, 2l4, 5se, 3ii, 3px`; oracle decompose subsumed by Bennett `:tabulate`: `16l, 25u`; P7 future arms: `wzj, 5ta`).

**Closed 2** (`k3m` incoherent — the literal `f(q)` syntax the P9 bead asked for is rejected by Julia and by the PRD; `mjk` done — Phase 1 test coverage exists, bridge cache sorts kwargs).

**Kept 1** (`f23` — the P2 implicit-cast warning is a legit current-state gap).

**Filed 15 new**, all traceable to stocktake findings. Priorities follow the user's G1 rule: P0/P1 = red-flashing emergency, ergonomics/nice-to-have pushed to P3/P4. See `bd list --status=open -n 20`.

**Also deleted** `docs/PLAN.md`, `docs/bennett-integration-v01-vision.md`, `docs/multi-path-arithmetic-plan.md` — three stale docs; git history preserves them. `docs/bennett-integration-implementation-plan.md` is current and kept.

**Created `KNOWN_ISSUES.md`** at project root — bullet register of architectural constraints (noise outside DAG IR by design), performance targets (31 bytes/node from Session 3), hard caps (30-qubit MAX_QUBITS), and test gaps that don't warrant individual beads.

**PRD revised** to remove "v0.1 POC" framing throughout, rewrite §7 as a current-state inventory (what is shipped, what is not, what is excluded by design), correct §9.2 (EagerContext is Orkan-backed, not a dense Julia vector as the old PRD said), align §2.5 / §9.4 / §9.6 to the real code, update §11 deps and §12 non-goals. Axioms P1-P9 untouched. ~300 lines net-down; see commit `a9752fa`.

### Beads worked this session

- **`wmo` P0 bug** (closed, commit `c162959`) — `alpha_comm(H, p≥3)` previously returned a naive triangle bound silently; per WORKLOG Session 4 that can be 10^9× looser than the true commutator-scaling value. Changed to throw `ErrorException` with a message directing users to `trotter_error(H, t, order; method=:naive)` (which bypasses `alpha_comm` entirely and uses `(λt)^(p+1)` directly). 7 new tests in `test_error_bounds.jl`, 68/68 pass.

- **`ndm` P1 task** (closed, commit `679cdea`) — orphaned `qsvt!` in `src/qsvt/circuit.jl` had a 13-line WARNING block stating it was broken for general block encodings. `qsvt_combined_reflect!` + `oaa_amplify!` is the working path (what `evolve!(…, QSVT(ε))` dispatches to). Deleted the function, docstring, WARNING block (~80 LOC). Removed 2 associated tests from `test_qsvt_phase_factors.jl` and the import. 162/162 pass.

- **`w4g` P1 task** (closed, commit `ba6e295`) — `Base.:<(::QInt, ::QInt)` and `Base.:(==)(::QInt, ::QInt)` plus their 4 Integer-mixed overloads silently measured both operands and returned a deterministic QBool. Violated P1 (functions are channels) and P9 (quantum registers as numeric type for reversible dispatch). Deleted all 6 definitions (~50 LOC). Removed 5 testsets from `test_qint.jl` and 4 from `test_promotion.jl`. Short comment at the deletion site points future readers to `oracle(f, q)` for quantum comparators. 562 + 2043 tests pass.

- **`lpj` P4 task** (closed, commit `3b60acf`) — `src/bennett/auto_dispatch.jl` was a 45-line stub holding `_P9_CACHE`, `_P9_LOCK`, `clear_auto_cache!()` for the Julia-forbidden literal `f(q)` catch-all. No callers outside the test. Deleted the file, removed include from `src/Sturm.jl`, deleted the "infrastructure exported" testset from `test_p9_auto_dispatch.jl`. Remaining 13 P9 tests pass (Quantum abstract type, classical_type trait, classical_compile_kwargs, existing dispatch paths).

- **`1f3` P3 feature** (in_progress, not closed) — QDrift and Composite RNG injection. Code changes are in this commit but END-TO-END VERIFICATION IS PARTIAL. See next-session pickup below.

### `1f3` state at stop time — PICK THIS UP FIRST

**Code landed (this commit):**

- `Project.toml`: added `Random = "9a3f8284-..."` to `[deps]`. `Random` is a stdlib but Julia still requires declaration in `[deps]` for non-Base modules.
- `src/simulation/qdrift.jl`:
  - `using Random: AbstractRNG, default_rng` at top
  - `QDrift` struct gained `rng::AbstractRNG` field; constructor has `rng::AbstractRNG = default_rng()` kwarg
  - `_sample(dist)` became `_sample(dist, rng::AbstractRNG = default_rng())` (backward-compat)
  - `_apply_qdrift!` now passes `alg.rng` to `_sample`
- `src/simulation/composite.jl`:
  - `Composite` gained `rng::AbstractRNG` field; constructor `rng::AbstractRNG = default_rng()` kwarg
  - `_apply_composite!` threads `alg.rng` in BOTH places: the pure-qDRIFT branch (constructs a `QDrift(..., rng=alg.rng)`) and the interleaved Trotter+qDRIFT loop (`_sample(dist, alg.rng)`)
- Test files `test_qdrift.jl` and `test_composite.jl`:
  - `using Random: MersenneTwister` at top
  - New testset `RNG injection: _sample is deterministic with seeded RNG` in `test_qdrift.jl` — verifies two `MersenneTwister(42)` give byte-identical sample sequences; different seed produces different sequence. **This part ran green.**
  - New testset `QDrift rng kwarg is stored and threaded to sampling` in `test_qdrift.jl`, and a parallel `Composite rng kwarg ...` in `test_composite.jl` — end-to-end: two seeded `evolve!` calls on identical |0…0⟩ produce identical Orkan amplitudes.

**Gotcha found and fixed but NOT re-verified:**

First attempt used two back-to-back `@context EagerContext() begin ... end` blocks with `amps_a = [_amp(...) for i in 0:7]` inside the first block and `@test amps_a == amps_b` inside the second. Failed with `UndefVarError: amps_a not defined in Main`. The `@context` macro introduces a scope via its `try ... finally` that hides inner assignments from the outer scope. Fix: wrap each run in a local function `run_once() = @context EagerContext() begin ...; a; end` that returns the amps list as the block's final expression (before `discard!`s? no — discards before the return); then `amps_a = run_once(); amps_b = run_once(); @test amps_a == amps_b`. This is now the committed shape but the probe was interrupted mid-execution.

Looking more carefully: `run_once()` returns `a` but the `@context ... end` ends with `a` AFTER the `for q in qs; discard!(q); end`. The `discard!`s clean up; the state is captured in `a` beforehand. Should be fine.

**Next steps to close `1f3`:**

1. Run the targeted probe to re-verify:
   ```
   LIBORKAN_PATH=/home/tobiasosborne/Projects/orkan/cmake-build-release/src/liborkan.so julia --project -e '
   using Sturm, Test; using Sturm: _QDriftDist, _sample, _amp; using Random: MersenneTwister
   H = ising(Val(3), J=1.0, h=0.5)
   run_qd() = @context EagerContext() begin
       qs = [QBool(0.0) for _ in 1:3]
       evolve!(qs, H, 0.5, QDrift(samples=10, rng=MersenneTwister(42)))
       a = [_amp(qs[1].ctx, i) for i in 0:7]
       for q in qs; discard!(q); end
       a
   end
   a = run_qd(); b = run_qd()
   @test a == b
   println("ok")
   '
   ```
2. If green, run the full `test_qdrift.jl` once (slow — ~13 minutes on this machine due to the N=24 Ising ground-truth test) OR skip and trust CI.
3. Also run `test_composite.jl`.
4. `bd close Sturm.jl-1f3 --reason="..."` + commit + push.

**Risk:** if the `run_once()` closure pattern doesn't work with `@context` either (TLS semantics across function calls are subtle), an alternative is to set `amps_a` via a `Ref{Vector{ComplexF64}}()` written inside the `@context` block. The macro expansion of `@context ctx body` is in `src/context/abstract.jl:~98`; look there if you need to debug scoping.

### Remaining easy-ish open beads

After `1f3` closes, low-friction candidates:

- **`eiq` P3** — CasesNode consumer policy. Touch `channel.jl` compat constructor, `openqasm.jl` line ~112, renderer warnings. Mechanical.
- **`q93` P2** — oracle Int8 hardcoding. Needs a small inference function: W → smallest signed/unsigned integer type.
- **`zv1` P4** — Refresh CLAUDE.md + README. Documentation sweep.

Harder beads that need design first:

- **`1wv` P1** — `with_empty_controls(f, ctx)` method on `AbstractContext`. Touches `pauli_exp.jl` (~line 200) and `lcu.jl` (lines 72-96). Needs a review to make sure no subtle semantics change.
- **`rpq` P1** — Arbitrary `when()` nesting in `TracingContext`. Requires either widening `HotNode` (kills 25-byte isbits, regresses Session 3 perf) or adding a cold-path node variant. User's earlier preference: option B (cold-path `DeepCtrlNode`).
- **`xcu` P1** — Multi-controlled gates on `DensityMatrixContext`. Density-matrix Toffoli via Kraus superop composition is non-trivial.
- **`870` P1** — Steane syndromes. This is QECC framework + 3 X-stabilisers + 3 Z-stabilisers + Table II lookup — a real bit of work.

### Environment gotchas for next agent

- Fresh clone requires `Pkg.develop(path="../Bennett.jl")` then `Pkg.instantiate()` (Bennett is dev-pathed, not registered). Listed in KNOWN_ISSUES.md.
- Orkan shared library: `LIBORKAN_PATH=/home/tobiasosborne/Projects/orkan/cmake-build-release/src/liborkan.so`.
- bd uses SSH now (`git+ssh://git@github.com/tobiasosborne/Sturm.jl.git`). `bd dolt push` works without interactive prompt.
- Per saved feedback: the full test suite is slow. Use targeted `julia --project -e '...'` probes against specific test files; trust CI for regressions. Even individual test files (qdrift.jl, composite.jl) hit minute+ runtimes because of large-N Ising / Heisenberg ground-truth tests. For quick verification run only the relevant testset rather than `include()`ing the whole file.

### Files touched this session

`Sturm-PRD.md`, `KNOWN_ISSUES.md` (new), `Project.toml`, `src/simulation/error_bounds.jl`, `src/simulation/qdrift.jl`, `src/simulation/composite.jl`, `src/types/qint.jl`, `src/Sturm.jl`, `src/qsvt/circuit.jl`, `test/test_error_bounds.jl`, `test/test_qsvt_phase_factors.jl`, `test/test_qint.jl`, `test/test_promotion.jl`, `test/test_qdrift.jl`, `test/test_composite.jl`, `test/test_p9_auto_dispatch.jl`, `.beads/config.yaml`. Deleted: `src/bennett/auto_dispatch.jl`, `docs/PLAN.md`, `docs/bennett-integration-v01-vision.md`, `docs/multi-path-arithmetic-plan.md`.

### Beads state at end of session

Total: 40. Open: 15 (1f3 in_progress). Closed: 25 this session (4 this session + 2 harmonisation closures + 37 historical; deleted 10 harmonisation).

Run `bd ready` or `bd list --status=open -n 30` to see the current queue.

---

## Earlier sessions archived

Sessions 1–22 (2026-04-05 → 2026-04-15) moved to
[`WORKLOG-archive.md`](WORKLOG-archive.md) on 2026-04-19. They cover:

- **Session 1** (2026-04-05) — project bootstrap, Orkan FFI.
- **Session 2** (2026-04-05) — OOM recovery, memory safety, Phase 6–12 scaffolding (QInt, QFT, Channel, QECC skeleton), Grover, literature survey (100 papers / 9 categories), Choi-phase-polynomials research direction.
- **Session 3** (2026-04-06) — gate cancellation (commutation-aware), optimise(ch, :pass), 149× gate_cancel speedup, isbits-union HotNode (31 B/node).
- **Session 4** (2026-04-06) — quantum-simulation literature survey (~170 papers), simulation module (PauliHamiltonian, Trotter1/2, Suzuki), 3-reviewer code review, 21 issues fixed.
- **Session 5** (2026-04-07) — P8 quantum promotion (numeric tower for QInt + Integer).
- **Session 6** (2026-04-07) — simulation module idiomatic review.
- **Session 7** (2026-04-07) — simulation refactors, qDRIFT, Composite, P0 controlled-pauli_exp! optimisation.
- **Session 8** (2026-04-08) — PDE paper formalisation (Childs et al. 2604.05098), gap analysis.
- **Session 9** (2026-04-08) — literature re-download (90 PDFs), QSVT deprecation (Motlagh → BS+Laneve), Block Encoding Phase 1, QSVT Phase 2.
- **Session 10** (2026-04-08) — Weiss algorithm, RHW factorisation, phase extraction, qsvt_protocol! circuit, BE algebra, controlled-oracle fix, multi-controlled Rz/Ry/CX.
- **Session 11** (2026-04-08) — 5-agent ground-truth review, GQSP operator-ordering fix (critical), reflection QSVT circuit, `evolve!(..., QSVT(ε))` for cos(Ht/α).
- **Session 12** (2026-04-09) — combined QSVT / GSLW Theorem 56 (7 bugs found and fixed, sin parity fix).
- **Session 13** (2026-04-09) — OAA implementation + two critical bugs (BS+NLFT degree-doubling phase collapse, single-qubit Rz ≠ multi-ancilla reflection). Rogue-background-agent gotcha.
- **Session 14** (2026-04-11) — Bennett.jl integration research + 74/74 tests.
- **Session 15** (2026-04-12) — Steane [[7,1,3]] encoder rewrite per Steane 1996 Fig 3, higher-order `encode(Channel, code)`, Grover-from-predicate (`find(f, T, Val(W))`), 2 Bennett upstream bugs fixed, v0.2 direction research (4-backend matrix + viz layer).
- **Session 16** (2026-04-12) — ASCII circuit drawer, pixel-art PNG renderer (Birren palette, 1000-wire GHZ in 70 ms), compact Level-A scheduling, Bennett v0.4 downstream assessment.
- **Session 17** (2026-04-14) — axiom refinement (P2 measurement-as-cast, P7 infinite-dimensional, P9 auto-dispatch spec).
- **Session 18** (2026-04-14) — Bennett.jl v0.5 assessment, multi-path arithmetic compilation plan (7-phase roll-out).
- **Session 19** (2026-04-14) — P9 hits Julia's `cannot add methods to builtin Function` wall, axiom reframed (generic path via P8 + explicit `oracle`/`@quantum_lift`/`quantum`). P4 corollary (`if q` never auto-lifts to `when(q)`).
- **Session 20** (2026-04-14) — multi-path arithmetic Phase 1, P8 bitwise (`⊻`, `&`, `|`) + shifts (`<<`, `>>`) on QInt, QuantumOracle cache-key bug fixed.
- **Session 21** (2026-04-15) — README audit against axioms, oracle decomposition honesty (43-qubit LLVM-lowering reality), Approach A/B idioms.
- **Session 22** (2026-04-15) — Bennett `:tabulate` adoption (zero Sturm-side changes, README rewrite).

For reasoning and design decisions made during any of the above, see the archive.
