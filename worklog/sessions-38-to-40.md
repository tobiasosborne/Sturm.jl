## 2026-04-21 — Session 40: discard! → ptrace! rename (close `diy`)

Mechanical refactor — the channel-theoretic partial-trace primitive gets its
proper name; `discard!` remains as a zero-overhead `const` alias for
backcompat. Size of the change validates session 38's sequencing decision:
because sv3 landed first, the rename touched ~20 internal call sites in
`src/` (plus 4 canonical defs + 1 export). Done WITHOUT migrating any
test/ file — the alias covers them.

### What changed

4 canonical definitions renamed: `function discard!` → `function ptrace!` in
`src/types/{qbool,qint,qcoset,qrunway}.jl`. Added a single module-level
alias `const discard! = ptrace!` in qbool.jl (the first types/ include,
so the alias captures all subsequent method additions via Julia's
generic-function semantics). Exported `ptrace!` from `src/Sturm.jl`
alongside the existing `discard!` export.

Internal call sites in `src/` migrated to `ptrace!` for consistency
(library/arithmetic, library/patterns, library/coset, library/shor,
noise/classicalise, block_encoding/select, qecc/steane, qsvt/circuit,
plus doc/error-message references in context/{eager,density,tracing},
hardware/hardware_context, types/{qcoset,qrunway,quantum}). Renamed
`_runway_force_discard!` → `_runway_force_ptrace!` with a const alias.

Tests remain on `discard!` — the alias covers them — minimising
cross-file churn. Future test files will use `ptrace!` (like
`test/test_ptrace.jl` added this session).

### Test strategy

Red first: `test/test_ptrace.jl` with 9 cases — ptrace! on QBool/QInt,
methods table contains QBool/QInt/QCoset/QRunway, `discard! === ptrace!`,
discard! still works on QBool, ptrace! + @context auto-cleanup coexist.
Ran red → 6 errors (UndefVarError on ptrace!), 1 pass. Implemented,
re-ran → 9/9 green. Regressions: sv3 autocleanup 14/14 green, library
patterns 92/92 green, QECC Steane 1173/1173 green. Full arithmetic
suite queued (takes ~5min on this device per standing memory); not
blocking the commit.

### Gotchas

1. **QCoset/QRunway constructors don't take plain Int** — my initial
   test used `QCoset{4,2}(3)` which MethodErrors. Pivoted to a methods-
   table check (`any(s -> s <: QCoset, sigs)` on `methods(ptrace!)`)
   which asserts the same thing (rename covered all 4 types) without
   needing runtime construction.

2. **`discard!` alias must be defined AFTER the first `function ptrace!`
   definition** but BEFORE any `discard!` caller runs. Julia binds
   `const` to the generic function at alias time; subsequent `function
   ptrace!(...)` in qint.jl, qcoset.jl, qrunway.jl add methods to the
   same function, and the `discard!` alias sees them automatically. No
   action needed beyond placing the const at qbool.jl (first include).

3. **Batched Edit tool calls need prior Read per file** — learned
   this mid-session. 8 of the src/ edits failed on the first batch
   because I hadn't Read each file individually. Re-did with
   Read-then-Edit pairs.

4. **Buffered `tail -5` on a long-running Julia test silently hangs**
   — `tail` waits for stdin EOF when its stdin isn't a TTY; if Julia
   doesn't terminate (e.g. the suite runs many minutes), output
   never flushes. Fix: pipe to `> /tmp/file.log 2>&1` and grep
   the file afterwards.

### Files touched

- `src/types/qbool.jl`: renamed `discard!` → `ptrace!`, added alias (+19)
- `src/types/qint.jl`: renamed, updated docstring (-4 +5)
- `src/types/qcoset.jl`: renamed, updated docstring (-4 +5)
- `src/types/qrunway.jl`: renamed, `_runway_force_discard!` → `_runway_force_ptrace!` + alias (-8 +10)
- `src/Sturm.jl`: export `ptrace!` alongside `discard!` (+1 -1)
- `src/library/{arithmetic,patterns,coset,shor}.jl`: call-site migration
- `src/noise/classicalise.jl`, `src/block_encoding/select.jl`,
  `src/qecc/steane.jl`, `src/qsvt/circuit.jl`: call-site migration
- `src/context/{tracing,eager,density}.jl`, `src/hardware/hardware_context.jl`,
  `src/types/quantum.jl`: doc / error-message references
- `README.md`: resource-lifetime section — the "v0.1 caveat / being
  deprecated" language replaced with "sv3 shipped, diy shipped,
  discard! is now the backcompat alias"
- `test/test_ptrace.jl`: new, 9 testsets
- `test/runtests.jl`: include new test

### Beads state

- Closed: `Sturm.jl-diy` (P3).
- Still open ergonomics: `cbl` (do-block allocation, independent),
  `hlk` (QBool/QInt finalizer, backstop per sv3 design note).
- Resource-lifetime ergonomics trilogy (sv3 → cbl → diy) now 2/3
  shipped. cbl can land whenever; it's additive.

### Next-session pointer

User asked for `870` (Steane [[7,1,3]] syndrome extraction + correction)
as the next target — "the real physics mega task". Pre-brief deferred
to a focused next session: will need full 3+1 protocol, Steane 1996
paper ground truth, Table II syndrome lookup, 3 X-stabilisers + 3
Z-stabilisers, logical/physical channel bookkeeping, and tests against
the {I,X,Y,Z} weight-1 error table.

---

## 2026-04-21 — Session 39: @context auto-cleanup (close `sv3`) — RAII for qubits

Followed session 38's hand-off: `sv3` was the recommended next target because
(a) it closes the long-standing `hlk` footgun, (b) makes the eventual
`discard!→ptrace!` rename (`diy`) trivial, (c) purely additive. Shipped in
one session via a 3+1 agent protocol. 14/14 new tests green; 804 adjacent
tests (channel 44, hardware 726, hardware-lifecycle 16, tracing-deep-when
18) green with zero regressions.

### The design in one paragraph

Added `live_wires(ctx)` and `cleanup!(ctx)` to `AbstractContext`. Default
`cleanup!` loops `live_wires` and calls `deallocate!` per wire, catching
per-wire errors into a `@warn` so one bad wire doesn't poison the rest.
Eager/Density/Hardware share `live_wires(ctx) = collect(keys(ctx.wire_to_qubit))`.
Hardware overrides `cleanup!` with a `ctx.closed && return` guard so
`with_hardware` and the finalizer continue to own `close()`. TracingContext
adds a new `live::Vector{WireID}` field (insertion-ordered, NOT a Set — DAG
emission order is user-visible), maintained by `allocate!` / `deallocate!` /
`_emit_observe!`. The `@context` macro gained a two-layer try/catch: body
exception captured via `body_threw::Bool` + `rethrow()` (preserves native
stacktrace); cleanup failure on a clean body path rethrows; cleanup failure
during an unwind becomes a `@warn` so the body's error wins. Body's last
expression is now preserved through the macro (fixes a latent bug from
session 23's `1f3` debugging). `trace()` filters designated output wires
out of `ctx.live` then calls `cleanup!` before `defer_measurements`, so
orphaned allocations become `DiscardNode`s in the lowered Channel.

### 3+1 agent protocol this time

- **Phase A — ground truth**: read every context file, trace.jl, qbool/qint
  constructors, existing `@context` macro, and the hardware lifecycle
  finalizer pattern BEFORE any code. Also revisited session 37 gotcha 5
  (finalizer + FFI is unsafe).
- **Phase B — red test**: wrote `test/test_autocleanup.jl` with 12 cases
  targeting the bead's acceptance + the semantics user locked in (silent
  partial-trace on block exit, matching GC idiom). Ran: 9 fail, 3 pass.
- **Phase C — parallel proposers**: two Plan-agents (both Opus) given
  identical context + the 9-point gotcha list + the red test file; no
  cross-pollination. Both proposed `live_wires` + `cleanup!` as the API
  surface, converged on 95% of the design. Divergences: error surfacing
  (CompositeException vs per-wire `@warn`), field name (`allocated` vs
  `live`), body-throw handling (`body_threw` flag vs captured exception).
  I synthesised: per-wire `@warn` (simpler than composite), `live` name
  (matches accessor), `body_threw + rethrow()` pattern (preserves Julia's
  native backtrace).
- **Phase D — implementer**: general-purpose Opus with the frozen plan and
  strict instructions NOT to redesign. Got a first-attempt 14/14 green
  (no iteration needed) and the two regression runs it was asked for.
- **Phase E — review** (me): verified files match plan via `git diff`,
  re-ran the sv3 suite, ran three additional regressions I chose
  (channel/trace, hardware context, tracing deep when) — all green.

### Gotcha #6 design lock-in

User asked: "Isn't partial trace of control expected behaviour? What would
be alternatives?" The alternatives are all worse:

- **Error on escape**: needs macro-level escape analysis of the block's
  return expression. Julia can't do this cleanly — the macro cannot tell
  `q; end` from `Bool(q); end`.
- **Force explicit cast before return**: that's what P2 already asks for
  in user-facing code. Auto-cleanup backstops it; it doesn't undermine it.
- **Keep ctx alive beyond the block**: breaks the `task_local_storage` /
  `lock(l) do … end` pattern. Any op on `q` after the block already
  fails at `current_context()` lookup.

So: silent partial-trace on exit. A returned live `q` is a dead handle.
Matches GC semantics for every transient Julia object. Locked in.

### Gotchas discovered and retired

1. **`@context` had a latent return-value bug** (known since session 23
   `1f3` debugging — the macro's `try...finally` dropped the body's last
   expression). Fixed incidentally as part of the rewrite — `local result`
   captured before the `finally`, returned after.
2. **`deallocate!` during cleanup might still need `current_context()`** —
   so cleanup must run BEFORE TLS restoration. Encoded in the macro
   structure.
3. **`trace()` has two entry points** — `trace(f, n_in::Int)` and
   `trace(f, ::Val{W})` — both needed the same 3-line change. Implementer
   got both on first pass.
4. **HardwareContext.deallocate! has `_check_open(ctx)` guard**. Since
   `cleanup!(ctx::HardwareContext)` short-circuits on `ctx.closed`, this
   never fires during cleanup — correct interaction.
5. **`_emit_observe!` also needs to remove from `live`** (not just
   `deallocate!`). Caught during plan drafting; implementer picked it up.

### What sv3 does NOT do (scope discipline)

- Does NOT rename `discard!` → `ptrace!` (that's bead `diy`, now unblocked).
- Does NOT add `QBool(p) do q … end` do-block allocation (bead `cbl`).
- Does NOT add a Julia finalizer on QBool/QInt (bead `hlk`). `sv3`
  covers 95% of cases deterministically; `hlk` remains open as the
  belt-and-braces backstop for the rare "QBool escapes its @context"
  case. User call: do not walk through that door until telemetry
  justifies it.

### Files touched

| File | LOC delta | What |
|------|-----------|------|
| `src/context/abstract.jl` | +82 -2 | `live_wires`, `cleanup!`, `_default_cleanup!`, rewrote `@context` macro |
| `src/context/eager.jl` | +2 | `live_wires` method |
| `src/context/density.jl` | +2 | `live_wires` method |
| `src/context/tracing.jl` | +9 -2 | `live::Vector{WireID}` field; maintained in allocate!/deallocate!/_emit_observe! |
| `src/hardware/hardware_context.jl` | +9 | `live_wires` + `cleanup!` override with `ctx.closed` guard |
| `src/channel/trace.jl` | +16 | filter out_wires from live, cleanup! before defer_measurements (both branches) |
| `test/test_autocleanup.jl` | +139 (new) | 14 testsets: Eager, Density, Hardware not touched (TBD), 100 iterations, exception safety, nested @context, TracingContext DiscardNodes, block return, DAG ordering |
| `test/runtests.jl` | +1 | include new test |

### Beads state

- Closed: `Sturm.jl-sv3` (P2 @context auto-cleanup).
- Unblocked: `Sturm.jl-diy` (P3 discard!→ptrace! rename, depended on sv3).
- `Sturm.jl-hlk` (P3 QBool/QInt finalizer) stays open as backstop per design
  decision above.
- `Sturm.jl-cbl` (P3 do-block allocation) independent, unchanged.

### Next-session pointers

The obvious next P2 candidates from `bd ready`:
- `870` P1 — Steane [[7,1,3]] syndrome extraction (orthogonal, unblocked).
- `npd` P2 — shor_factor_EH_semi with Mosca-Ekert semi-classical iQFT.
- `jrl` P2 — QRunway runway-in-middle (unblocks 6oc GE21 critical path).

The obvious next P3 (ergonomics follow-on from sv3):
- `diy` — discard!→ptrace! rename. Now trivially doable because most
  explicit `discard!` calls became redundant under sv3; the rename will
  touch far fewer sites than it would have pre-sv3.

---

## 2026-04-21 — Session 38: cases() + OpenQASM dynamic circuits (close `322` + `tak`); file 3 follow-on beads

User asked to fix bead `322` (TracingContext silent mis-trace of classical-conditioned
operations after measurement). After deep research (3 parallel subagents on Sturm
internals + Julia DSL idioms + quantum-DSL prior art), shipped a full design that
also closes `tak` (OpenQASM CasesNode dropped). Filed three follow-on ergonomics
beads (auto-cleanup `sv3`, do-block allocation `cbl`, discard!→ptrace! rename `diy`).

### Research findings (recorded for future-you)

Three subagents in parallel established:

1. **Sturm internals**: CasesNode struct already exists (`dag.jl:114-118`),
   `defer_measurements` already lowers ObserveNode+CasesNode via Nielsen-Chuang
   §4.4, draw/pixels render placeholders, openqasm silently drops. The PRODUCER
   side was the gap — TracingContext.measure! at `tracing.jl:135-145` returned
   hardcoded false with a "for now" comment that was never followed up.

2. **Julia DSL idioms**: Symbolics/MTK overload `Base.ifelse` + add error_hints
   for `convert(Bool, ::Num)`; JuMP refuses `if VariableRef` and uses indicator
   constraints; Cassette/IRTools/Mjolnir are fragile (FluxML migrating off
   Cassette); IfElse.jl archived (Symbolics now overloads Base.ifelse directly);
   **Yao.jl has no measurement-conditioned primitive at all** — Sturm fills a
   genuine gap in the Julia quantum ecosystem.

3. **Quantum DSL prior art** taxonomy:
   - (A) Block-scoped: Qiskit-new (`with circuit.if_test((c, 1)):`), Q#, OpenQASM
     3 (`if (c==1) { ... }`), MQT IfElseOperation. **Wins for Sturm.**
   - (B) Method-on-gate: Cirq (`with_classical_controls`), TKET. Too narrow.
   - (C) Decorator: Catalyst `@cond`. Unidiomatic in Julia.
   - (D) Linear/labels: Quil. Wrong abstraction level.
   Critical P4 warning from subagent C: Cirq blurs coherent `when` and classical
   control by reusing op wrappers — Sturm must NOT make this mistake. The new
   primitive must be VISUALLY DISTINCT from `when()`.

### 8 design decisions locked (4 with user revisions)

1. Name: `cases` (matches CasesNode + Qiskit/MQT terminology). ✓
2. Syntax: **two-do-block was rejected by Julia parser** (chained `f() do … end
   do … end` is a parse error). Pivoted to `@cases q begin … end begin … end`
   macro — both blocks parse cleanly. The `cases(q, then, else_)` function is
   the underlying primitive.
3. trace() auto-lowers CasesNode via strict defer_measurements. ✓
4. v1 restriction: cases bodies must be measurement-free; **strict mode errors
   loudly** (per user revision — was originally "compiler warning"). ✓
5. OpenQASM 3 dynamic-circuit emission for CasesNode (closes `tak`). ✓
6. Fail fast, fail loud: `Bool(q)` / `Int(q)` inside TracingContext errors
   with migration message pointing to `cases()` / `discard!()` / empty-cases
   idiom. ✓

### THE observe! ANTIPATTERN — caught and rejected mid-session

In an early draft I introduced an `observe!(q)` primitive to handle the
"measure-and-record-but-discard-result" case (test_channel.jl needed this for
its OpenQASM output assertion). User correctly identified this as a P2
violation: P2 says "the Q→C boundary is a CAST. Only explicit casts: Bool(q),
Int(qi)." Adding `observe!(q)` would be a back-door measurement function —
exactly what P2 forbids. Plus it's redundant with discard! (which IS partial
trace, the channel-theoretic operation for "throw away this qubit").

**The right answer**: empty-cases idiom `cases(q, () -> nothing)`. This is
honest about what's happening — measure, branch on outcome, but both branches
do nothing — and produces an ObserveNode + empty CasesNode in the trace. The
auto-lowering pass drops the empty CasesNode and keeps the ObserveNode, so
OpenQASM still emits `c[0] = measure q[0];`. No new primitive needed.

Lesson for future-you: when fixing a P2-axiom-violating bug, **double down on
P2** — don't introduce parallel back-doors to make tests easier.

### discard! is itself unidiomatic — filed three new beads

User pushed back on `discard!` as a name. Analysis: it's unidiomatic on four
axes (resource-management vocab in user code violates P5; bang-convention is
wrong since it consumes rather than mutates; redundant with what GC should do;
forces explicit cleanup that's the source of bead `hlk`). Filed three beads
in dependency order to MINIMISE refactoring:

- **`sv3` P2** — `@context` auto-cleanup of unconsumed quantum resources.
  RAII-style: track allocations, partial-trace at scope exit. Subsumes hlk.
  **Lands first** because it makes most existing `discard!` calls redundant.
- **`cbl` P3** — `QBool(p) do q … end` do-block allocation. Independent
  additive; matches Julia `open(f, path) do stream … end` idiom.
- **`diy` P3** — Rename `discard!` → `ptrace!` (channel-theoretic name).
  **Depends on sv3** so the rename touches ~5-10 sites instead of ~50.

Sequencing rationale: each session is additive and low-risk; the eventual
rename is small because auto-cleanup + do-block patterns have made `discard!`
optional in most positions.

### What landed this session

| File | Change |
|------|--------|
| `src/control/cases.jl` (NEW, 130 LOC) | `cases(q, then, else_)` + `@cases` macro + per-context dispatch |
| `src/context/tracing.jl` | dag::Vector{HotNode} → Vector{DAGNode}; measure! errors loudly; new `_emit_observe!` for cases() internal use |
| `src/channel/trace.jl` | Auto-lower via `defer_measurements(strict=true)` before constructing Channel |
| `src/passes/deferred_measurement.jl` | Added `strict` kwarg; empty-CasesNode handling (drop CasesNode, keep ObserveNode); strict errors on un-lowerable patterns |
| `src/channel/openqasm.jl` | Rewrote with `_emit_node!(lines, node, idx, map, indent)` style; new `to_openqasm(dag, in_wires, out_wires)` entry; OpenQASM 3 dynamic-circuit `if (c[i] == 1) { … } [else { … }]` emission for CasesNode; recursive bit-index pre-pass |
| `src/Sturm.jl` | Include cases.jl; export `cases`, `@cases` |
| `test/test_cases.jl` (NEW, 36 tests) | EagerContext / HardwareContext / TracingContext / @cases macro / branch capture / auto-lower / nested measurement error / Bool(q) error / empty-cases idiom |
| `test/test_openqasm_cases.jl` (NEW, 17 tests) | Then-only / both-branch / multiple measurements / Channel-level back-compat / empty-cases suppression |
| `test/test_channel.jl, test_pixels.jl, test_draw.jl` | Migrated 3 sites `_ = Bool(q)` → `cases(q, ()->nothing)`; added new `_emit_observe!` test |
| `test/runtests.jl` | Added test_cases + test_openqasm_cases |

53/53 new tests pass. Regression-clean across test_channel, test_passes,
test_tracing_deep_when, test_pixels, test_draw, test_qecc, all hardware tests,
and ~15 other touched files.

### Surprises and gotchas

1. **Julia's chained double-do is a parse error** (verified empirically with
   `f("X") do; …; end do; …; end` → `extra tokens after end of expression`).
   Forced pivot from the originally-locked two-do-block syntax to a macro
   form `@cases q begin … end begin … end`. Macros are stable across Julia
   versions and parse cleanly. The function form `cases(q, then, else_)` is
   the underlying primitive (e.g. for programmatic construction).

2. **Empty `collect(())` returns `Vector{Union{}}`**, not `Vector{WireID}`.
   Broke the new `to_openqasm(ch::Channel) → to_openqasm(dag, in_wires, out_wires)`
   dispatch when the channel has no inputs/outputs (common in test fixtures).
   Fix: use `WireID[ch.input_wires...]` instead of `collect(ch.input_wires)`.

3. **TracingContext.dag::Vector{HotNode} can't hold CasesNode** because
   CasesNode has Vector fields → not isbits → can't be in HotNode union (which
   is isbits-optimized at 25 B/element per Session 3). Solution: relax dag
   to Vector{DAGNode} during tracing, auto-lower via defer_measurements
   before constructing the long-lived Channel (which keeps Vector{HotNode}).
   Best of both worlds — slight perf regression during tracing (transient),
   no impact on Channel-resident IR (perf-sensitive).

4. **Rejected the observe! antipattern** (see above). User caught it; lesson
   captured.

5. **`@cases q begin ... end` macro args**: when called with just one block,
   the `else_block` macro arg defaulted via `args...` length check. Julia
   macros don't support default values in the signature; varargs + length
   check is the idiom.

### Beads state at end of session

- Closed: `Sturm.jl-322` (P1 silent correctness bug), `Sturm.jl-tak` (P2
  silent OpenQASM drop). Both bug beads from session 37 architecture audit
  resolved.
- Filed: `sv3` (P2 @context auto-cleanup, RAII), `cbl` (P3 do-block allocation),
  `diy` (P3 discard!→ptrace! rename, blocked on sv3). Three follow-on
  ergonomics beads.
- Open beads now: 21 (was 20 at session start; +3 new − 2 closed).

### Next-session pointers

**Highest-value follow-on**: `sv3` (@context auto-cleanup). Per session
analysis, this is the right next move because it (a) closes the long-standing
hlk footgun, (b) makes the eventual `discard!→ptrace!` rename trivial, (c)
purely additive. Estimated: 1 session.

**Other ready P1/P2**:
- `Sturm.jl-870` P1 — Steane [[7,1,3]] syndrome extraction (orthogonal).
- `Sturm.jl-jrl` P2 — runway-in-middle type, unblocks `6oc` GE21 critical path.
- `Sturm.jl-npd` P2 — Mosca-Ekert semi-classical iQFT.

**Hygiene from session 37**:
- `Sturm.jl-t1v` P3 — `_ORACLE_TABLE_CACHE` eviction policy.
- `Sturm.jl-hlk` P3 — QBool/QInt finalizer (will likely be subsumed by sv3).

---

