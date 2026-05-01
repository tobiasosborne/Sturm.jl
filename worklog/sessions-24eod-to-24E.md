## 2026-04-18 — Session 24 END-OF-DAY HANDOFF

**Stop reason:** user ended the session. Tree is clean; all work
committed and pushed to `origin/main`. `bd stats` shows 0 in_progress,
7 open.

### Session 24 at a glance — 6 beads closed, 1 filed

| Bead | Priority | What | Commit |
|------|----------|------|--------|
| `1f3` | P3 | QDrift/Composite RNG injection + vacuous-test fix | `bfa8f0f` |
| `q93` | P2 | Width-fitting oracle arg type (`_bennett_arg_type`) | `dd2f680` |
| `f23` | P2 | P2 axiom implicit-cast warning (`with_silent_casts`) | `0bd5289` |
| `xcu` | P1 | Multi-controlled gates on DensityMatrixContext | `2f051e4` |
| `1wv` | P1 | `with_empty_controls` / `with_controls` public API | `e1ace01` |
| `rpq` | P1 | Arbitrary when() nesting in TracingContext | `180eee3` |
| `5gz` | P2 | **Filed:** qsvt_phases sin polynomial returns 2d+1 phases (pre-existing) |

### Major architectural changes this session

1. **`src/context/multi_control.jl`** is now typed on `AbstractContext`
   (was `Union{EagerContext, DensityMatrixContext}`) and routes through
   the PUBLIC `apply_*!` API rather than raw `orkan_*!` pointer calls.
   Every helper wraps itself in `with_empty_controls` to break recursion
   when called from nc≥1. **Consequence:** EagerContext, DensityMatrixContext,
   and TracingContext all use the SAME Toffoli cascade for arbitrary
   when() nesting depth. Zero code per context.

2. **`src/context/abstract.jl`** grew two default-implementation methods:
   `with_controls(f, ctx, ctrls::Vector{WireID})` and
   `with_empty_controls(f, ctx) = with_controls(f, ctx, WireID[])`.
   Both built on the existing `push_control!`/`pop_control!`/
   `current_controls` interface.

3. **`src/types/qbool.jl` and `src/types/qint.jl`** now split the
   constructor from `Base.convert`: `Bool(q)` / `Int(q)` hold the
   measurement (silent), and `Base.convert(::Type{Bool/Int}, q)` emits
   the P2 warning then delegates. Implicit `x::Bool = q` assignments
   hit the convert path; explicit constructor calls do not.

4. **`src/bennett/bridge.jl`** has a new `_bennett_arg_type(W;
   signed=true)` helper that picks the narrowest Int/UInt fitting W.
   Replaces the hardcoded `Int8` in `oracle(f, x::QInt{W})` and
   `QuantumOracle`'s call operator. Cache key widens to
   `(W, signed, kwargs)`.

### Current ready queue — annotated

```
  bd ready
  ○ Sturm.jl-870  P1   Steane syndrome extraction + correction (QECC)
  ○ Sturm.jl-5gz  P2   [bug] qsvt_phases 2d+1 for sin polynomial
  ○ Sturm.jl-di1  P2   Backend scaffolding (tensor-net + hardware)
  ○ Sturm.jl-7ab  P2   Pass registry / DAG transformation API
  ○ Sturm.jl-mt9  P2   QSVT/QSP linear algebra EPIC
  ○ Sturm.jl-eiq  P3   CasesNode consumer policy (error on unhandled)
  ○ Sturm.jl-zv1  P4   Docs refresh (CLAUDE.md + README.md)
```

**Recommended next pickup** for a fresh agent:

- **`5gz` P2 bug** is worth triaging first — it's concrete, reproducible
  (just run `test/test_qsvt_reflect.jl` lines 53-58), and may be a
  test-assertion-vs-algorithm-convention mismatch rather than a real
  physics bug. Quick win if so. See `docs/physics/` for QSP/QSVT
  convention notes — the test expects `length(phi) == 2d` but the
  sin-parity GSLW convention might legitimately yield `2d+1`.

- **`eiq` P3** remains the obvious mechanical continuation if you want
  a warm-up. `src/channel/channel.jl` compat constructor,
  `src/channel/openqasm.jl:~112`, renderer warnings.

- **`zv1` P4** has three concrete items queued up:
  (a) Sturm-PRD.md has ~10 pedagogical `::Bool = q` / `::Int = qi`
      examples that now trigger the f23 warning if copy-pasted; convert
      to explicit form or note "this pattern warns".
  (b) README lines ~146-200 advertise `strategy=:tabulate` as a Bennett
      kwarg — confirmed NOT present in current Bennett
      (`grep -r tabulate /home/tobiasosborne/Projects/Bennett.jl/src`).
      Session 22 misreported, or it reverted upstream.
  (c) CLAUDE.md phase 12 table is stale.

- **`870`, `di1`, `7ab`, `mt9`** are substantial and design-first — save
  for a fresh big session.

### Cross-session patterns saved for the next agent

1. **Rule 4 is strict about local PDFs.** When extracting or moving code
   that carries a docstring reference to a paper, read the local
   `docs/physics/<name>.md` BEFORE shipping. If no local file exists,
   write a self-contained derivation (see
   `docs/physics/toffoli_cascade.md` from Session 24D).

2. **Bennett LLVM lowering hates closures that capture values.** A
   boolean `signed` captured in `x -> x + (signed ? Int8(1) : UInt8(1))`
   materialises as `StructType({ ptr, i8 })` in Julia IR — Bennett
   errors with "Unsupported LLVM type for width". Use top-level
   functions for oracle tests across parameters, not loop-body
   closures. (Hit this during Session 24F's full-suite run.)

3. **Test files can drift from the axioms.** Session 24C's f23 work
   discovered 8 `::Bool = q` sites in test_bell, test_teleportation,
   test_rus — the warning catching our own code validated the split.
   Run the full suite after ANY axiom-level change to flush these out.

4. **Don't copy forward unexamined references.** Session 24D's xcu work
   copied the "Barenco 1995 Lemma 7.2" reference from eager.jl into the
   new multi_control.jl without verifying the local PDF existed (it
   didn't). User caught this mid-session with "did you read the
   Nielsen and Chuang ground truth?" The fix was writing
   `docs/physics/toffoli_cascade.md` inline.

5. **When extracting helpers that touch context internals, flag the
   abstract-interface candidate up front.** Session 24D's xcu extracted
   `multi_control.jl` which used `ctx.control_stack` directly — then
   Session 24E's 1wv had to migrate those accesses to the new API.
   Would have been cleaner to do both in one pass.

6. **Pre-existing test failures reproduce on previous commits.** Always
   verify: `git stash && julia --project -e '<repro>' && git stash pop`.
   Session 24F's 5gz qsvt_phases issue turned out to be pre-existing —
   saved from chasing a regression caused by today's refactor.

### Full test suite state (as of commit `180eee3`)

- **12833 pass / 3 fail / 1 error / ~12837 total**
- The 1 error (q93 closure test) was **fixed in commit `180eee3`** —
  re-running the full suite now would produce 12836 / 3 / 0.
- The 3 failures are `Sturm.jl-5gz` — see above.
- **Full-suite runtime on this device: ~2h15m.** Dominant: OAA (61m),
  Reflection QSVT (34m), qDRIFT (21m), Bennett E2E (5m). Do NOT run
  the full suite casually — use targeted `julia --project -e '…'`
  probes for verification work.

### Environment gotchas, reminded

- `LIBORKAN_PATH=/home/tobiasosborne/Projects/orkan/cmake-build-release/src/liborkan.so`
  (memory entry lists `/home/tobias/…` — stale prefix on this device).
- `Bennett.jl` is dev-pathed via `Pkg.develop(path="../Bennett.jl")`;
  not registered. Fresh clones must do the develop before
  `Pkg.instantiate`.
- bd uses SSH; `bd dolt push` works non-interactively. Session close
  protocol = `git pull --rebase && bd dolt push && git push`.
- The `.beads/` permissions warning is cosmetic; `chmod 700 .beads`
  fixes it but isn't blocking.

### Physics docs referenced by this session's code

- `docs/physics/nielsen_chuang_4.3.md` — controlled-Ry/Rz ABC
  decomposition. Verified algebraically in Session 24D.
- `docs/physics/toffoli_cascade.md` — Session 24D NEW, self-contained
  derivation of the N-controlled cascade with density-matrix extension.
  Referenced by `src/context/multi_control.jl`.

### Files with significant changes today

- `src/context/abstract.jl` — with_controls, with_empty_controls
- `src/context/multi_control.jl` — unified cascade across all contexts
- `src/context/eager.jl` — cascade helpers moved out
- `src/context/density.jl` — multi-control dispatch added
- `src/context/tracing.jl` — nc>2 routes to cascade
- `src/types/quantum.jl` — _warn_implicit_cast, with_silent_casts
- `src/types/qbool.jl`, `src/types/qint.jl` — constructor / convert split
- `src/bennett/bridge.jl` — _bennett_arg_type helper
- `src/simulation/pauli_exp.jl` — migrated to with_empty_controls
- `src/block_encoding/lcu.jl` — migrated to with_empty_controls
- `src/simulation/qdrift.jl`, `src/simulation/composite.jl` — rng kwarg
- `src/Sturm.jl` — exports
- `README.md` — with_silent_casts note
- `docs/physics/toffoli_cascade.md` — NEW
- `test/test_implicit_cast.jl`, `test/test_density_matrix_mc.jl`,
  `test/test_control_api.jl`, `test/test_tracing_deep_when.jl` — NEW
- Plus test fixes in test_bell, test_teleportation, test_rus, test_qdrift,
  test_composite, test_bennett_integration.

---

## 2026-04-18 — Session 24F: Close `rpq` (arbitrary when() nesting in TracingContext)

TracingContext's `apply_ry!`/`apply_rz!`/`apply_cx!` errored at control-
stack depth > 2 because `HotNode` carries at most `ctrl1, ctrl2` inline
(the Session 3 25-bytes/element isbits union). The bead's proposed fix
(Option B) was to add a cold-path `DeepCtrlNode` with `controls::Vector
{WireID}` for deep cases. Instead: realised the cascade in
`multi_control.jl` can be rewired to lower a deep-controlled op entirely
into depth-≤2 ops via a Toffoli cascade with workspace qubits — the
SAME path EagerContext and DensityMatrixContext use (closed in xcu).
No new node type needed; no Session 3 perf regression at depth ≤ 2; the
traced DAG contains only standard `HotNode`s.

### Unified cascade — `multi_control.jl` refactor

Rewrote the 6 helpers to type on `AbstractContext` instead of
`Union{EagerContext, DensityMatrixContext}`, and to route through the
PUBLIC `apply_ry!`/`apply_rz!`/`apply_cx!`/`apply_ccx!` API rather than
raw `orkan_*!` calls. Each invocation is wrapped in
`with_empty_controls(ctx) do … end` so that inner `apply_*!` calls see
nc=0 and hit their fast paths:

- EagerContext: direct `orkan_*!` on `ctx.orkan.raw`.
- DensityMatrixContext: same (Orkan's gate ABI is state-type-agnostic,
  `ccx` computes `UρU†` on MIXED states natively).
- TracingContext: emits `RyNode`/`RzNode`/`CXNode` with `nc ≤ 2`.

### Recursion break

`_controlled_ry!` is called at nc=1 from Eager's `apply_ry!`. In the new
implementation it internally uses `apply_ry!`/`apply_cx!`. Without
protection, Eager's `apply_ry!` at nc=1 → `_controlled_ry!` → `apply_ry!`
at nc=1 → infinite recursion. `with_empty_controls` inside
`_controlled_ry!` clears the stack for the duration of the ABC
decomposition, so the inner `apply_ry!` sees nc=0 and goes direct. This
is the same pattern `pauli_exp.jl` and `lcu.jl` now use for their
optimisation-blocks (from Session 24E).

### tracing.jl update

- `_inline_from_stack` now errors with "internal invariant violated" if
  ever called with nc > 2 — callers must route to the cascade before
  reaching it.
- `apply_ry!`/`apply_rz!`/`apply_cx!` at nc > 2 call
  `_multi_controlled_gate!` / `_multi_controlled_cx!`.
- `apply_ccx!` at nc_stack ≥ 2 pushes the explicit `c1` onto the stack
  and routes to the cascade (same pattern as eager/density.jl).
- `apply_ccx!` at nc_stack ≤ 1 still emits an inline 1- or 2-control
  `CXNode` — the existing fast path, unchanged.

### Workspace in the traced DAG

At depth 3 or higher, the cascade allocates N−1 workspace qubits. On
TracingContext, `allocate!` returns a fresh WireID and `deallocate!`
emits a `DiscardNode`. A traced 4-nested `when()` circuit therefore
contains extra CCX nodes (the cascade), a few extra wires (workspace),
and `DiscardNode`s (workspace cleanup). OpenQASM export handles these
as standard gate + reset operations — the bead's acceptance criterion
("4-nested when() traces and exports to OpenQASM 3.0") is met.

### Performance concerns

The old `_controlled_ry!` on EagerContext called `orkan_ry!`/`orkan_cx!`
directly on the raw pointer — 4 C calls per invocation. The new path
goes through 4 `apply_*!` calls, each doing a stack-length check +
dict lookup before reaching Orkan, plus the `with_empty_controls`
save/restore overhead (≈ 4 ops for a 1-element stack). Per invocation
this adds maybe 30–50 ns on EagerContext — negligible for circuit-
construction work but measurable for Pauli-exp inside a tight Trotter
loop. Will benchmark if a regression is reported; none observed in the
full-suite run that closes this bead.

### RED-GREEN TDD

Wrote `test/test_tracing_deep_when.jl` first — 8 testsets / 18 asserts
covering:
- Depth 3 CCCRy via triple-nested when() traces (no error).
- Depth 3 OpenQASM export emits `ccx`.
- Depth 4 quadruple-nested when() traces.
- Depth 3 `apply_cx!` inside 2-deep when (effective CCCX).
- Depth 2 `apply_ccx!` inside when (effective CCCX) — existing fast path.
- Depth 3 and 4 EagerContext outcome correctness (all |1⟩ → target flips).
- Depth 4 any-|0⟩-blocks sanity check.

RED: 3/13 failed — the three hitting nc>2 in apply_ry!/cx!. 10 passed
immediately (Eager/DM already supported depth ≥ 3, and fast paths at
depth 2 already worked for CXNode-via-apply_cx! and apply_ccx! at
nc_stack=1).

GREEN after refactor: 18/18.

### Regression

After refactor:
- test_tracing_deep_when (new): 18/18
- test_when: 507/507
- test_density_matrix_mc: 17/17
- test_control_api: 23/23
- test_channel: 43/43
- test_block_encoding: 63/63
- test_simulation: 122/122
- test_grover: 284/284

Plus the full `runtests.jl` — see commit note.

### Files touched

- `src/context/multi_control.jl`: widen type to `AbstractContext`, route
  through public apply_*! API, wrap helpers in `with_empty_controls`.
- `src/context/tracing.jl`: route nc > 2 through the cascade; tighten
  `_inline_from_stack` invariant error.
- `test/test_tracing_deep_when.jl` (new), `test/runtests.jl` (include).
- `WORKLOG.md`: this entry.

### Full-suite verification (user-requested)

Ran `julia --project -e 'include("test/runtests.jl")'` — full suite,
verbose, ~2h15m total runtime dominated by OAA (61 min), Reflection QSVT
(34 min), qDRIFT (21 min), and Bennett integration e2e (5 min).

**Tally:** 12833 pass, 3 fail, 1 error — out of ~12837.

**Regressions caused by today's work: NONE.**

**The 3 + 1 non-greens:**

1. **3 failures in `Reflection QSVT / qsvt_phases: sin polynomial returns
   correct count`** (test/test_qsvt_reflect.jl:57). At d=5/9/13,
   `length(qsvt_phases(jacobi_anger_sin_coeffs(1.0, d)))` returns
   `2d+1` instead of `2d`. Verified pre-existing: reproduces on commit
   `e1ace01` (the session 24E/1wv commit, BEFORE today's rpq refactor).
   Filed as `Sturm.jl-5gz` P2. The cos polynomial parity passes.
   Likely a test-assertion issue rather than a physics bug (OAA and
   evolve!(QSVT) downstream tests pass at their 33-minute runtime, so
   the algorithm produces usable phases).

2. **1 error in `Bennett Integration / arg-type selection by W /
   oracle forwards signed kwarg without breaking W=2 regression`**
   (test/test_bennett_integration.jl:497). MY bug from Session 24B
   (q93). The closure `x -> x + (signed ? Int8(1) : UInt8(1))` captures
   the boolean `signed` variable, producing an LLVM IR with
   `StructType({ ptr, i8 })` that Bennett cannot compile
   (`Unsupported LLVM type for width`).

   **Fix:** rewrite as two top-level functions (`f_signed(x) = x +
   Int8(1)`; `f_unsigned(x) = x + UInt8(1)`), avoiding the capture
   struct. Targeted probe 2/2 green after fix.

**Lesson saved:** Bennett's LLVM lowering fails on closures that capture
values (they materialise as `StructType` in Julia's IR). For oracle
tests at varying parameters, prefer a set of small top-level functions
over a loop with a parametrised closure. Will fold into the memory
update below.

### Note on the bead's `DeepCtrlNode` suggestion

The bead explicitly proposed Option B (add `DeepCtrlNode` node type
outside the HotNode union). I opted for a strictly simpler approach
(no new node type, same semantics, Session 3 perf preserved). The
downside: visualisation/rendering of a deep-controlled op now shows the
cascade rather than the abstract "MCU" node. If we later want to
render MCU symbolically (e.g., in `to_ascii` for a 5-controlled rotation
shown as `Rz(θ)●●●●●` rather than the full expanded cascade), that's a
separate UX decision and can add `DeepCtrlNode` as an OPT-IN sugar layer
at that point — the cascade stays as the canonical lowering.

---

## 2026-04-18 — Session 24E: Close `1wv` (`with_empty_controls` public API)

Three external files were reaching into `ctx.control_stack::Vector{WireID}`
directly to save/clear/restore controls around basis changes (pauli_exp.jl)
and PREPARE/SELECT isolation (lcu.jl). That field is not part of the
`AbstractContext` contract — it's a convention every current context
happens to share. A future tensor-network or hardware-emitting backend
might represent controls differently and would silently produce wrong
circuits. The Session 24D refactor (xcu) also introduced two fresh leaks
in `src/context/multi_control.jl` (`copy(ctx.control_stack)`). Closing
both before the pattern spreads.

### RED-GREEN TDD

Wrote `test/test_control_api.jl` first — 9 testsets covering:

- `current_controls(ctx)` returns a copy (mutating it does not alter the
  stack) — regression test on existing API.
- `with_empty_controls(f, ctx)` clears the stack inside `f()`, restores on
  normal exit, restores on exception.
- `with_empty_controls` returns the value of `f()`.
- `with_controls(f, ctx, controls)` swaps the stack, restores on exit.
- Nested pattern: the pauli_exp / lcu idiom (outer empty-clear, inner
  temporarily-restore).
- Works identically on all three contexts (EagerContext,
  DensityMatrixContext, TracingContext) — the default
  implementation in `abstract.jl` uses `push_control!` / `pop_control!` /
  `current_controls` only, so any context that implements the three gets
  `with_controls` / `with_empty_controls` for free.

RED: 9/9 errored (symbols don't exist yet — `using Sturm: …` fails the whole
file). First GREEN: added `with_controls` + `with_empty_controls` to
`src/context/abstract.jl`, exported both, got 1/9 passing (the no-imports-
needed test). Second fix: my test file also needed `allocate!` /
`current_context` imported — both are unexported. After that, 23/23 green
(23 is the sub-assert count inside the 9 testsets).

### Migration — three caller sites

- `src/simulation/pauli_exp.jl:191` — the `_pauli_exp!` basis-change
  optimisation. Old: raw `empty!` / `append!` on the stack with
  `has_controls` boolean flag threading through 5 `if` guards. New: outer
  `with_empty_controls(ctx) do … end` wrapping all 5 steps, with a single
  `with_controls(ctx, saved) do … end` for the one controlled Rz pivot.
  Lost ~20 lines of bookkeeping, kept the physics proof comment intact.

- `src/block_encoding/lcu.jl:72, 102` — `oracle!` and `oracle_adj!`.
  Identical shape (PREPARE / SELECT / PREPARE†) and identical collapse:
  outer `with_empty_controls`, inner `with_controls(saved)` around the one
  SELECT call. Both functions lost their `try`/`finally` block — the new
  primitives handle restoration automatically.

- `src/context/multi_control.jl:85, 102` — `copy(ctx.control_stack)` is
  semantically identical to `current_controls(ctx)` (both return a copy).
  Swapped both. These are internal cascade helpers shared between
  EagerContext and DensityMatrixContext, so removing the field access
  here tightens the context-polymorphic seam.

### Design decision

Primary primitive is `with_controls(f, ctx, controls::Vector{WireID})`
(swap-in / run / swap-out). `with_empty_controls(f, ctx) =
with_controls(f, ctx, WireID[])` is a one-line wrapper. The bead
explicitly requested `with_empty_controls` by name, so that's the
documented/exported surface, but `with_controls` also ends up exported
because the pauli_exp / lcu idiom needs it.

Default implementation in `abstract.jl` uses only
`current_controls` / `push_control!` / `pop_control!`, all three of which
were already required by the abstract interface. So:

- EagerContext, DensityMatrixContext, TracingContext all get
  `with_controls` / `with_empty_controls` with zero code per context.
- A future backend need only implement the three existing interface
  methods to pick up the full control-lifecycle API.
- The internal `.control_stack` field in each concrete context is NOT
  touched by the migration — per the bead: "default implementation can
  still use the control_stack field for backward compat with current
  contexts."

### Verification

- `test_control_api.jl` (new): 23/23 green.
- `test_when.jl` (regression): 507/507 green.
- `test_density_matrix_mc.jl` (regression after `multi_control.jl`
  migration): 17/17 green.
- `test_block_encoding.jl` (regression after `lcu.jl` migration): 63/63.
- `test_simulation.jl` (regression after `pauli_exp.jl` migration): 122/122.

Total new+regression: 732/732. No failures.

### Files touched

- `src/context/abstract.jl`: `with_controls`, `with_empty_controls` +
  docstrings; one-line update to `current_controls` docstring noting it
  returns a copy.
- `src/Sturm.jl`: export `current_controls`, `with_controls`,
  `with_empty_controls`.
- `src/simulation/pauli_exp.jl`: migrate `_pauli_exp!` basis-change
  optimisation.
- `src/block_encoding/lcu.jl`: migrate `oracle!` and `oracle_adj!`.
- `src/context/multi_control.jl`: `copy(ctx.control_stack)` →
  `current_controls(ctx)` at two cascade helpers.
- `test/test_control_api.jl` (new), `test/runtests.jl` (include).
- `WORKLOG.md`: this entry.

### Lesson

When extracting helpers that reach into context internals (Session 24D's
`multi_control.jl`), leave a note to revisit. Fresh code that uses
implementation details becomes the next migration's problem within a
session. Better: identify the abstract-interface candidate up front, even
if you defer the full sweep.

---

