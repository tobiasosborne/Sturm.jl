# Multi-Path Arithmetic Compilation — Plan

**Status:** proposal (2026-04-14). No code changes yet. Tracked under `Sturm.jl-7nx`
follow-ups; individual strategy beads filed below.

**TL;DR.** Sturm.jl's arithmetic (`+`, `-`, `*`, comparisons on `QInt{W}`) is
currently hard-wired to a ripple-carry lowering. We want to give users a menu
of state-of-the-art circuit families — QFT / Draper / Cuccaro / QCLA / Karatsuba
/ Sun-Borissov polylog multiplier — selectable as optimisation strategies.

Big finding from today's investigation: **Bennett.jl (`../Bennett.jl`) has
already built the multi-path framework internally**, shipping `add=` and
`mul=` kwargs with Sun-Borissov's April 2026 polylog multiplier
(`:qcla_tree`), Draper QCLA (`:qcla`), Cuccaro (`:cuccaro`), ripple-carry
(`:ripple`), shift-add (`:shift_add`), and Karatsuba (`:karatsuba`). Bennett's
public `reversible_compile(f, T; add, mul, …)` surface already exposes them.

Therefore Sturm's job is **not** to re-implement circuit families — it is to
(1) surface Bennett's existing strategy kwargs cleanly through the DSL, (2)
offer a handful of **DSL-native** paths (notably a pure-QFT adder) for cases
where going through LLVM IR is wasteful, and (3) provide a cost-model-aware
dispatcher that can pick a strategy given an objective (depth / T-depth /
ancilla / gate count). The infrastructure is mostly plumbing.

---

## 1. Motivation

- Every non-trivial quantum algorithm performs arithmetic; the arithmetic
  dominates depth, T-count, and ancilla budget at moderate n. A compiler that
  hard-codes ripple-carry leaves orders of magnitude of resource savings on
  the floor (see §4 for numbers).
- P9 (PRD §1) promises that any Julia function becomes a quantum oracle
  automatically. "Automatic" doesn't mean "fixed lowering" — for the same
  source `f(x) = x * y`, a user optimising for shallow circuits wants
  Sun-Borissov (O(log²W) depth, 56 Toffoli-depth at W=32); a user optimising
  for qubits wants shift-add (5 024 Toffoli, O(W) ancillae).
- No mainstream quantum framework (Qiskit, Cirq, tket, Catalyst, Quipper,
  BQSKit) surfaces arithmetic strategy selection as a first-class option
  today. This is a feature.

## 2. Current state (2026-04-14)

| Path | Files | What it does | Strategy selection |
|---|---|---|---|
| Hand-written QInt arithmetic | `src/types/qint.jl` | `+` `-` `*` on `QInt{W}` via ripple-carry + 3-Toffoli/2-CNOT stages (VBE-style). Consumes inputs; returns fresh QInt. | None — single lowering. |
| Bennett oracle | `src/bennett/bridge.jl` (`oracle(f, x; kw...)`) | Accepts arbitrary classical `f`; compiles via Bennett LLVM-IR extraction; runs on context's control stack. `kw...` is already plumbed through to `reversible_compile`. | Implicit — Bennett's internal dispatch (`:auto`) picks memory and arithmetic strategies per allocation site. User-controlled kwargs `add=`, `mul=`, `bennett=` flow through untouched. |
| Library primitives | `src/library/patterns.jl` | QFT (`superpose!`, `interfere!`), `phase_estimate`, `fourier_sample`, `find`/`amplify`, `_cz!`, `_hadamard_all!`. | N/A (not arithmetic paths). |

Pass pipeline: `src/passes/{gate_cancel,deferred_measurement,optimise}.jl`. No
arithmetic-level rewrite pass exists.

## 3. Bennett.jl v0.5-ish delta since our April 12 assessment

From today's investigation of `../Bennett.jl`:

### New memory strategies (all 4 shipped April 12)
- `shadow_memory.jl` — static-index stores/loads via CNOT-only protocol (3W per store, W per load, zero Toffoli). 297× smaller than MUX EXCH at W=8.
- `qrom.jl` — Babbush-Gidney read-only-table dispatch, 4(L−1) Toffoli. 134× smaller than MUX tree at L=4, W=8.
- `feistel.jl` — 4-round Feistel bijective hash, 8W Toffoli. 148× smaller than 3-node Okasaki at W=32.
- Universal dispatcher `_pick_alloca_strategy()` in `lower.jl` picks per allocation site.

### New arithmetic strategies (shipped April 13–14, still engineering)
- `qcla.jl` — Draper carry-lookahead adder: O(log W) Toffoli-depth, out-of-place.
- `mul_qcla_tree.jl` — **Sun-Borissov 2026 polylog multiplier** (arxiv 2604.09847). O(log²W) Toffoli-depth, self-reversing. The backing algorithm is *the* April-2026 state-of-the-art depth-optimal Clifford+T multiplier.
- `partial_products.jl`, `parallel_adder_tree.jl`, `fast_copy.jl` — the three submodules Sun-Borissov requires.
- Public kwargs: `add ∈ {:ripple, :cuccaro, :qcla, :auto}`, `mul ∈ {:shift_add, :karatsuba, :qcla_tree, :auto}`.

### Key architectural additions
- `self_reversing::Bool` flag on `LoweringResult`. When set, `bennett()` skips the outer forward+copy+uncompute wrap. Sun-Borissov's multiplier and Cuccaro adder return clean ancillae by construction, so wrapping is wasteful.
- Soft-float `soft_fdiv` subnormal bug fixed April 14.
- Exports: `toffoli_depth(c)`, `t_depth(c; decomp=:ammr|:nc_7t)` canonical cost metrics.

### Measured multiplier trade-offs at W=32 (from Bennett's `BENCHMARKS.md`)

| Strategy | Total gates | Toffoli | Toffoli-depth | T-count |
|---|---|---|---|---|
| `:shift_add` | 11 202 | 5 024 | 190 | 35 168 |
| `:karatsuba` | 36 778 | 12 276 | 132 | 85 932 |
| `:qcla_tree` (Sun-Borissov) | 54 614 | 24 212 | **56** ← 3.4× shallower | 169 484 |

Picking a multiplier is now a genuine Pareto-frontier decision: depth vs
Toffoli vs T-count vs ancilla. A cost-model-driven dispatcher is exactly what
a compiler should supply.

## 4. Literature landscape (full detail in `docs/literature/arithmetic_circuits/`)

Two canonical references now live in `docs/literature/arithmetic_circuits/`:

- `Nickerson_survey_2024_2406.03867.pdf` — arxiv 2406.03867. Comprehensive 2024 survey covering ripple-carry (VBE 1996, Cuccaro 2004, Takahashi 2005), QFT-based (Draper 2000, Beauregard 2003), carry-lookahead (Draper-Kutin-Rains-Svore 2006), multipliers (Kepley-Steinberg 2015, Parent-Roetteler-Mosca 2017, Gidney 2019, Dutta-Kayal 2018), and modular exponentiation (Beauregard 2003, Häner-Roetteler-Svore 2016, arxiv 1605.08927). Anchor for selection-axis analysis.
- `Sun_Borissov_polylog_multiplier_2026_2604.09847.pdf` — arxiv 2604.09847. Sun (softwareQ) & Borissov (Waterloo), April 14 2026. **New state-of-the-art** Clifford+T multiplier at O(log²W) depth AND O(log²W) T-depth, with O(W²) gates and O(W) ancillae. Explicit coefficients (depth 3·log²W + 17·log W + 20). Indicator-controlled copying + binary adder tree. This is the paper that makes the depth-vs-T-depth Pareto curve move.

### Strategy menu — addition

| Strategy | Depth | Gates | Ancilla | Notes |
|---|---|---|---|---|
| Ripple-carry (VBE 1996, Cuccaro 2004) | O(W) | O(W) | O(W) or 0 (Takahashi) | Simple, local, nearest-neighbour friendly |
| QFT adder (Draper 2000) | O(W log W) / O(log W) known-constant | O(W²) rotations | O(W) | Output in Fourier basis — composes cheaply with other QFT ops, expensive with ripple |
| Carry-lookahead (Draper-Kutin-Rains-Svore 2006) | O(log W) | O(W log W) | O(W) | True sub-linear depth; careful uncomputation |
| QCLA (Bennett `:qcla`) | O(log W) Toffoli | O(W) Toffoli | O(W) | Out-of-place; already shipped in Bennett. |

### Strategy menu — multiplication

| Strategy | Depth | T-depth | T-count | Ancilla | When |
|---|---|---|---|---|---|
| Schoolbook (shift-add) | O(W²) | O(W²) | O(W²) | O(W) | Tiny W, ancilla-constrained |
| Karatsuba | O(W^1.158) | O(W^1.158) | O(W^1.585) | O(W^1.427) | Moderate W, T-count matters |
| Toom-Cook | O(W^1.057) | O(W^1.057) | O(W^1.585) | O(W^1.245) | Intermediate T-count regime |
| Wallace tree | O(log W) via parallel adder summation | — | O(W²) | O(W²) | Historical; largely subsumed |
| Schönhage-Strassen (Zalka 1998, Nie et al. 2023) | O(log² W)* | — | O(W log W log log W)* | O(W log W log log W)* | Cryptographic scale, W ≥ 2^40 |
| **Sun-Borissov 2604.09847** | **O(log² W)** | **O(log² W)** | **O(W²)** | **O(W)** | **Moderate W, depth-critical; new 2026 Pareto frontier** |

\* Huge hidden constants.

### Selection axes

Depth / T-depth / T-count / ancilla / connectivity / output basis. See the
full 1 000-word survey in the WORKLOG Session 18 entry for the detailed
per-axis table; for the plan itself what matters is that **no single
strategy dominates** — the compiler must accept a cost function and pick.

## 5. Sturm-level design

Given Bennett already owns the per-strategy circuit implementations, Sturm's
layer is thin. Three surfaces:

### 5.1 Pass-through from `oracle`/`quantum`/`f(q)` to Bennett

`oracle(f, x; kw...)` already splats `kw...` into `reversible_compile`
(`src/bennett/bridge.jl` line 158). **The plumbing is free.** A user can
already write:

```julia
y = oracle(f, x; add=:qcla, mul=:qcla_tree)
```

and get Sun-Borissov multiplication + QCLA addition. This works today for
every `QInt{W}` operation routed through Bennett.

Work to do: (a) document this in the README / docstrings; (b) decide which
Bennett kwargs are Sturm's public API vs. escape-hatch; (c) ensure `quantum(f)`
cache keys include strategy kwargs so switching strategies doesn't share a
cache entry (see §5.4).

### 5.2 Sturm-native strategy overrides on `QInt` arithmetic

`src/types/qint.jl` defines `+`, `-`, `*` hard-wired to ripple-carry. Two
cases where we want a non-Bennett path:

1. **Pure-QFT adder** (Draper 2000). If a user already has `QInt` data in the
   Fourier basis (because the previous op was a QFT for phase estimation or
   for another Draper adder), going through Bennett round-trips out of and
   back into Fourier basis. A DSL-native `@strategy DraperQFT a + b` keeps the
   data in-basis. This is the clearest win; Bennett cannot see DSL-level QFT
   context.
2. **Classical-operand specialisation** (Beauregard). When one operand is a
   compile-time-known classical `Int`, the rotation angles can be precomputed
   offline, collapsing an O(W log W) Draper adder to O(log W) depth with
   zero quantum control overhead on the classical operand. Again, this is a
   DSL-level rewrite Bennett doesn't see.

Mechanism: a `@strategy <StrategyName> expr` macro that wraps `expr` with a
task-local storage entry:

```julia
task_local_storage(:sturm_arithmetic_strategy, StrategyName) do
    expr
end
```

The `+`/`-`/`*` methods on `QInt` read this key; absent it, they use the
default (ripple-carry today; `:auto` → `:qcla_tree` in a future heuristic).
Strategy-specific methods live in `src/arithmetic/strategies/{ripple,draper,qft,bennett_passthrough}.jl`.

### 5.3 The strategy registry

Central file `src/arithmetic/strategies.jl`:

```julia
abstract type ArithmeticStrategy end
struct RippleCarry    <: ArithmeticStrategy end   # hand-written, current default
struct DraperQFT      <: ArithmeticStrategy end   # DSL-native QFT adder
struct BeauregardFA   <: ArithmeticStrategy end   # classical-operand specialization
struct BennettPath{S} <: ArithmeticStrategy end   # S is Bennett's add=/mul= symbol
struct Auto           <: ArithmeticStrategy end   # cost-model dispatcher

# Each strategy declares the ops it supports and its resource profile
supports(::Type{RippleCarry}, ::typeof(+), ::Type{QInt{W}}) where W = true
profile(::Type{RippleCarry}, ::typeof(+), W::Int) =
    ArithProfile(toffoli=3W, t_depth=nothing, depth=O(W), ancilla=W)
```

`BennettPath{:qcla_tree}` etc. is a thin shim: it constructs a classical
Julia closure for the requested op and hands it to `oracle(f, x;
mul=:qcla_tree)`. So the "seven strategies" menu is really "three DSL-native
+ N Bennett forwards."

### 5.4 Cost-model dispatcher (`Auto`)

Given a target objective, `Auto` picks a strategy. Objectives surface as a
keyword argument threaded through `@context` or `@strategy`:

```julia
@context EagerContext() objective=:min_t_depth begin
    y = f(x)        # dispatches to the lowest-T-depth strategy for each op
end
```

Objectives: `:min_depth`, `:min_t_depth`, `:min_t_count`, `:min_gates`,
`:min_ancilla`, `:balanced`. Per-(strategy, W) resource profiles come from
Bennett's existing cost-metric machinery (`toffoli_depth`, `t_depth` with
`decomp=:ammr|:nc_7t`) plus hand-coded DSL-native profiles.

Selection is rule-based, not ML: a small table of per-objective-per-op
strategies, with width thresholds. Far simpler than SAT-based synthesis and
sufficient for the regime we care about.

### 5.5 Interaction with DAG / `when()` / passes

- Strategy selection happens at **lowering time** (when `+` fires during
  tracing), not as a post-hoc DAG rewrite. This avoids the macro-op-node
  infrastructure that Option A in the survey required.
- Inside `when(ctrl)`, the selected strategy's gate sequence is automatically
  lifted to its controlled form via the existing control stack — same
  discipline as Bennett's own controlled lift. Controlled-QFT and
  controlled-QCLA have well-studied phase structures; they work.
- `gate_cancel` and `defer_measurements` run post-lowering on the DAG,
  agnostic to which strategy produced the gates. No pass-pipeline change.

## 6. User-facing API (final sketch)

```julia
# Default (no strategy hint) — uses today's ripple-carry, unchanged
@context EagerContext() begin
    a = QInt{32}(5); b = QInt{32}(3)
    c = a + b
end

# Explicit strategy hint — a single op
@context EagerContext() begin
    c = @strategy DraperQFT a + b
end

# Block-level hint — every arithmetic op inside uses Sun-Borissov multiplication
@context EagerContext() begin
    @strategy BennettPath{:qcla_tree} begin
        y = x * x + x       # mul=:qcla_tree, add uses default
    end
end

# Objective-driven — Auto picks per op to minimise T-depth
@context EagerContext() objective=:min_t_depth begin
    y = f(x)                # mul dispatches to :qcla_tree, add to :qcla
end

# Escape hatch to raw Bennett kwargs
y = oracle(f, x; add=:qcla, mul=:qcla_tree, bennett=:pebbled_group)
```

## 7. Phased roll-out

Filed as beads; each phase is independent and shippable.

### Phase 1 — document and expose Bennett pass-through (`Sturm.jl-gkp`, P1)

Zero-risk baseline. Document `oracle(f, x; add=..., mul=...)` in the README,
PRD, and `bridge.jl` docstrings. Verify the cache key in `quantum(f)` (the
`QuantumOracle` struct in `bridge.jl`) includes kwargs so strategy changes
don't share cache entries with default compiles. Add integration tests that
assert `oracle(f, x; mul=:qcla_tree)` and `oracle(f, x; mul=:shift_add)`
produce different gate counts on the same function.

### Phase 2 — strategy registry + `@strategy` macro (`Sturm.jl-m4v`, P1)

Add `src/arithmetic/strategies.jl` (types + registry) and `src/arithmetic/macros.jl` (`@strategy` macro using task-local storage). Teach `QInt`'s `+`/`-`/`*` methods to read the strategy hint. Default remains `RippleCarry`; no behavioural change absent a hint. Tests: hint propagation, block-level scoping, nesting.

### Phase 3 — DSL-native Draper QFT adder (`Sturm.jl-drp`, P2)

First non-Bennett strategy. Pure DSL (four primitives + QFT library call).
Validates that the registry + macro support a genuine DSL-native path. Tests:
exhaustive QInt{4} addition (256 cases), QFT-adder vs ripple-carry roundtrip
equivalence on classical inputs, basis-state preservation inside `when()`.

### Phase 4 — Bennett pass-through strategies as registered entries (`Sturm.jl-bpx`, P2)

`BennettPath{:qcla}`, `BennettPath{:qcla_tree}`, `BennettPath{:cuccaro}`,
`BennettPath{:karatsuba}`, `BennettPath{:shift_add}`. Each is a ~10-line shim
forwarding to `oracle(f, x; kw)` with a Julia closure representing the op.
Tests: strategy selection surfaces Bennett's measured gate/Toffoli counts.

### Phase 5 — Auto dispatcher + cost-model objectives (`Sturm.jl-auto`, P2)

Objective kwarg on `@context` and `@strategy`. Per-(strategy, op, W) profile
table, rule-based selection. Tests: `objective=:min_t_depth` picks Sun-Borissov for multiplication at W≥32; `objective=:min_ancilla` picks shift-add; tied regimes break deterministically.

### Phase 6 — Beauregard classical-operand adder (`Sturm.jl-bgr`, P3)

Constant-folding specialisation: when one operand is compile-time `Int`,
lower to precomputed rotations. Big win for loops with fixed increments and
for Shor-style modular exponentiation. Blocked on the registry but otherwise
independent.

### Phase 7 — benchmark and publish the trade-off table (`Sturm.jl-bmk`, P3)

Run each strategy on a standard benchmark suite (ripple-carry addition,
Karatsuba vs schoolbook multiplication, Shor's period-finding modular
exponentiation). Publish Toffoli / Toffoli-depth / T-count numbers in
`BENCHMARKS.md`. Validates that Sturm's overhead over raw Bennett is small
(≤5%).

## 8. Risks

- **Phase coherence inside `when()`.** The Session-8 bug (CLAUDE.md Global
  Phase section) — controlled-Rz(π) ≠ CZ — applies to every strategy that
  uses `φ +=` for phase gates. Draper QFT is the highest-risk family because
  it is phase-dense. Mitigation: every strategy has a dedicated
  `test_<strategy>_controlled.jl` that asserts the controlled lift matches
  the classical-operand tensor product.
- **Cache-key collisions on `quantum(f)`.** If the cache keys off `(f,
  argtypes)` only, switching `mul=` silently reuses a stale circuit.
  Mitigation: key off `(f, argtypes, strategy_kwargs)` as a sorted tuple.
- **QFT output-basis mismatch.** Composing a Draper adder with a ripple-carry
  op requires an explicit QFT/IQFT round-trip. Silent insertion of these
  costs makes `@strategy DraperQFT` a footgun if the user doesn't know. The
  registry's `profile()` function must flag output basis; the dispatcher
  must warn when mixing incompatible strategies.
- **Bennett strategy flux.** Bennett's arithmetic strategies are still
  engineering (`_pick_add_strategy` partially implemented). The
  `BennettPath{S}` shims couple to symbol names that may churn. Mitigation:
  version-check Bennett on import; maintain a compat layer in
  `src/bennett/bridge.jl`.
- **P9 auto-dispatch interaction.** When P9's `f(q)` catch-all ships
  (`Sturm.jl-k3m`), it must respect the active strategy hint. The fallback
  needs to read `task_local_storage(:sturm_arithmetic_strategy)` too, not
  just call `oracle(f, q)` with defaults.
- **Endianness drift.** Several papers (Beauregard, Thapliyal) use big-endian
  conventions; Sturm is little-endian. Strategy implementers must convert.

## 9. Open design questions

1. Should `@strategy` be a macro or a context kwarg? Macros are syntactically
   crisper; context kwargs compose with `@context`. Proposal: support both —
   context kwarg sets the default, macro overrides per expression.
2. Per-`QInt{W}` strategy as a type parameter (Option C in the survey) vs.
   task-local storage? Type-parameter approach fights against P8
   (promotion) — `QInt{8,RippleCarry} + Int` would need to decide promotion
   strategy at construction. Not worth the complexity for v0.2.
3. Should strategy selection be visible in the DAG nodes themselves (e.g.
   `AdderNode{RippleCarry}`) or only during lowering (gate-level nodes, no
   macro-op)? Proposal: gate-level only for v0.2; reconsider when a
   ZX-rewriting pass (`Sturm.jl-79j`) lands and benefits from macro-ops.
4. Should `Auto` ever call a Bennett strategy that hasn't been marked stable
   yet? Proposal: no — `Auto` only selects from registry entries flagged
   `stable=true`.

## 10. Beads filed

- `Sturm.jl-mjk` P1 — document + test Bennett kwarg pass-through (Phase 1)
- `Sturm.jl-xfk` P1 — strategy registry + `@strategy` macro (Phase 2)
- `Sturm.jl-adj` P2 — DSL-native Draper QFT adder (Phase 3, blocked on xfk)
- `Sturm.jl-2l4` P2 — Bennett pass-through as registered entries (Phase 4, blocked on xfk)
- `Sturm.jl-5se` P2 — Auto dispatcher + objectives (Phase 5, blocked on 2l4)
- `Sturm.jl-3ii` P3 — Beauregard classical-operand adder (Phase 6, blocked on adj)
- `Sturm.jl-3px` P3 — benchmark suite + trade-off table (Phase 7, blocked on 5se)

Each phase's bead carries its own acceptance criteria in `--acceptance`.

## 11. Why this order

Phase 1 is pure documentation of a capability that already works. It has the
highest ROI-per-line and zero risk — if Bennett's `add=:qcla_tree` surfaces
Sun-Borissov's polylog multiplier for any Julia function, every current
Sturm user can use it *today* with no Sturm changes, just by passing the
kwarg. The plan's headline deliverable exists once Phase 1 ships.

Phase 2 (registry + `@strategy`) is the foundation for DSL-native paths.
Phase 3 (Draper QFT) is the first genuine DSL-native strategy — it proves
the registry works for non-Bennett paths.

Phases 4–7 are refinement: more strategies, a dispatcher, and measurement.
They are individually small; the architectural decisions are all made in
1–3.
