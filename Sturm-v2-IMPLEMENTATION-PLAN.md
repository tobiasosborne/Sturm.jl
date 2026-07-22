# Sturm v2 — Greenfield Implementation Plan

**Status: ACTIVE — REBASELINED 2026-07-21** (session 98, bead `rzkx`).
Originally written 2026-07-10 against `Sturm-PRD-v2.md` (review round 6).
This rebaseline folds in: the shipped state of **M0–M7** (14,965 tests
green); the GPT-5.6-sol xhigh adversarial review
(`docs/design/prd-v2-review-gpt56-2026-07-19.md`, findings F1–F37; triage
in `worklog/session-97.md`); the two M8 design-gate syntheses
(`docs/design/m8-5hr7-unitary-block-design.md`,
`docs/design/m8-i4ri-classical-control-design.md`); the `rlhj` PRD accuracy
patch (commit `93f36fd`); and the F31/F34/F35 rebaseline mandate itself.
This is the build order, the test map, the decision schedule, and the risk
ledger for the from-zero implementation under epic `Sturm.jl-u0xw`.

**D-point status (was: "D1–D13 ruled; D6/D7/D14 open").** D1–D14 all
ruled. **D6 split** (F37): the uniform cyclic Fourier dual `dual(::QMod{d})`
is unblocked for *all* d; only the parity-sensitive Weyl/Clifford/metaplectic
layer stays research-gated. **D7** (ccall shape) resolved by measurement at
M2. **D14** (BennettVM contract) ruled by Tobias (circuit-only bridge) and
shipped at M7. **D15 is newly OPEN** (arbitrary `QBool(p, φ)` literal inside
`when` — F12): a loud error until ruled, tracked as bead `xy4w` and gating M8.

**North star.** A best-in-class, Julia-idiomatic quantum programming
language that respects all physics and has beautiful ergonomics. The
operational reading of that sentence: the seven surface constructs and
nothing else; every law in the PRD is a named passing test; every
worked example in PRD §7 runs verbatim; if a construct fights Julia,
the construct is wrong; if a lowering fights quantum mechanics, the
lowering is wrong.

---

## 1. Ground rules of the build

1. **Law tests before features.** Each milestone starts by writing its
   PRD-named law tests (failing), then makes them pass. The §3.2
   boundary algebra, §4.2 kernel laws, §3.9 scope discipline, and the
   §3.3 Pontryagin unit tests are the spine of the suite.
2. **Distillations before code** (rule 4). Each milestone lists the
   `docs/physics/` distillations it must land *first*; docstrings cite
   the `.md`, and the boot lint enforces resolution.
3. **3+1 agent rule** for every core milestone (kernel, types, context
   interface, casts/primitives, Orkan FFI): two independent proposers,
   one implementer, orchestrator reviews. Flagged per milestone below.
   **A P0 design gate is a 3+1 round with no code output** — the M8
   gates `5hr7` and `i4ri` are exactly this: two blind proposals
   synthesised into a canonical design, staged for paste after Tobias
   rules (§3.0).
4. **The PRD's examples compile, forever.** `test/test_prd_examples.jl`
   (bead `hn90`) Meta.parses AND Meta.lowers every fenced Julia block in
   the PRD with stub macros — lowering is essential, B1 was a lowering
   error — and executes §7 under EagerContext as the surface grows. It
   shipped in milestone 0; **13/13 green** after the `rlhj` patch.
5. **Quarry policy — the deprecated branch is full of heresies.**
   `v0.1-deprecated` may be *consulted* (via `git show
   v0.1-deprecated:path`, never checkout) for the narrow items marked
   "quarry" below, each with a skepticism note. Categorically
   forbidden: anything touching θ/φ (BlochProxy, `gates.jl`, the
   `multi_control.jl` ABC-decomposition — that file IS the silent
   SU(2)-section choice §1.1 condemns), `_cz!` folklore, the v0.1
   `not!` lowering (Rz·Ry — wrong channel class), per-object consumed
   flags, the teleportation test, and every marginal-statistics test
   pattern. When in doubt: derive from the PRD, not the branch.
6. **One Julia process at a time** (standing constraint — parallel
   processes corrupt the depot cache). Agents doing research never run
   Julia while an implementation session is live.
7. **Version floor: Julia 1.11** (`Base.ScopedValues`, `public`).
   Target and CI on 1.12. Dependencies: none beyond Orkan (`ccall`)
   and Bennett.jl (bridge, wired as a weakdep extension — F36). `Test`
   in extras. This is a hard budget.
8. **Namespace = layering.** Surface constructs are `export`ed; kernel
   API (`U2`, `Perm`, `ctrl`, `view`, constants) is `public` —
   reachable as `Sturm.ctrl`, absent from `using Sturm`. The §2 layer
   table becomes mechanically enforced.
9. **Worklog + beads discipline** as ever (rule 0; `bd` for all
   tracking). Each milestone below maps to one bead (listed in §5).
   **Tracker caveat (session 97):** the embedded Dolt DB is degraded
   (`bd dep add` fails — missing `wisp_dependencies` table; `bd dolt
   push/pull` conflicts). The git-committed `.beads/issues.jsonl` is the
   canonical recovery source; gates are recorded as `--notes` until the
   tracker is repaired. See §6 risk 2.

---

## 2. Milestone graph

```
M0 scaffold ✓ ─→ M1 kernel ✓ ─→ M2 FFI+contexts ✓ ─→ M3 casts+Choi harness ✓
                                       │                        │
                                       └────────→ M4 views+dual+actions ✓ ─→ teleport ✓
                                                            │
                                              M5 when (streaming) ✓ ─→ deferred teleport ✓
                                                            │
                                              M6 QInt+arithmetic worlds ✓
                                                            │
                                              M7 Bennett bridge ✓ ─→ DJ ✓, BV ✓ (all 8 secrets)
                                                            │
                                    ══ PRE-M8 GATES (§3.0): z1sa · vqas · xy4w · F16 ══
                                                            │
                                              M8 Tracing + typed channel IR + certify +
                                                 classical-control IR + phase-faithful passes
                                                            │
                                              M9 QMod full-space perm + in-place-Perm contract +
                                                 injection ✓ + Shor ✓   (⚠ addq P1)
                                                            │
                                              M10 library HOFs ─→ Grover ✓
                                                            │
                                              M11 noise/Stinespring/QECC scaffold (⚠ F8 typing)
                                                            │
                                              M12+ horizon (hardware, QMod/D6, CV,
                                                    QSVT, Sextant viz)
```

✓ = **SHIPPED** (M0–M7, session 95–96). The double bar is the review-imposed
freeze: **no M8 code until the §3.0 gates clear.** Dependency chain is now
strictly linear M7 → gates → M8 → M9 → M10 → M11 (the old "M8 parallel with
M7" claim is retired — F34, §3.0).

Worked examples are the acceptance gates: each lands in the earliest
milestone whose vocabulary suffices, as a Choi-level pipeline test.

---

## 3. Milestones

### M0 — Scaffold (beads `23o1` + `hn90`) — SHIPPED (session 95)

- Shipped: `Project.toml` (julia = "1.11", no runtime deps, Bennett as
  weakdep, Test in extras), `src/Sturm.jl`, `test/runtests.jl`.
- Both boot lints wired: physics-cite lint (grep `src/` for
  `docs/physics/….md`, assert resolution) and the PRD doctest lint
  (parse+lower every fenced block). **13/13 green** post-`rlhj`.
- **Exit met:** `Pkg.test()` green on 1.11 and 1.12.

### M1 — Kernel process values and the algebra (bead `c52g` + successors) — SHIPPED (session 95, 12,752 tests)

- Shipped: `src/kernel/u2.jl`, `perm.jl`, `ctrl.jl`, `algebra.jl`,
  `constants.jl` (X, Z, H, S, T, Ry, Rz as `public` `U2` values).
- **U2** immutable quaternion+phase; **equality is structural `==`**,
  **semantic comparison is `≈`/`same_process`** (double-cover, phase-
  inclusive) — the F26 split, already the shipped choice and now
  normative (`rlhj`). +I ≠ −I preserved; `Ry(2π) == −I ≠ I`.
- **Perm** = reversible instruction list + wire count; `ctrl(::Perm)::Perm`
  (closure named-tested); `adjoint` = reversed inverse.
- **ctrl** is the single choke point (`Ctrl{V}` lazy wrapper), total on
  U2/Perm; grep-lint confines controlled lowerings to `src/kernel/` +
  `src/orkan/`. **M8 adds exactly one method, `ctrl(::UnitaryBlock)`**
  (5hr7 §1.4) — the header already promises this.
- All named kernel laws green.
- **Carried debt for M8 (F28, ruling TR5):** `MCX.controls`/`Perm.gates`
  are `Vector`s — a sealed IR block embedding them is mutable-through-
  aliasing. M8 must refactor these to `NTuple` storage with vector-
  accepting, defensively-copying constructors *before* the IR seals
  them (§3.0, §3.M8).

### M2 — Orkan FFI + contexts + regions — SHIPPED (session 95, 13,573 tests)

- Shipped: `src/orkan/ffi.jl`, `state.jl`, `ad.jl`;
  `src/context/{abstract,eager,density,regions}.jl`.
- **D7 resolved by measurement**: 24/24 v0.1 ccall signatures verified
  against the live headers; ZYZ θ≈0/π singular folds, phase-exact
  ABC/sqrt-V/clean-ancilla-ladder written at this boundary and nowhere
  else. Handles owned by the context, deterministic cleanup.
- **Regions (§3.9)** on `Base.ScopedValues.with`; per-region owned set;
  single-sourced consumed set; scope-exit trace; `ptrace!`; escape
  tracking added (session 95).
- **Carried debt (F5, i4ri):** the shipped `_measure_wire!(::DM)` throws
  and `_instrument!` pinches-and-keeps — both are *correct* and become
  the foundation of M8's DM classical-control executor (the §3.8
  portability table was wrong, not the code).

### M3 — QBool, casts, linearity, and the Choi harness — SHIPPED (session 95, 13,711 tests)

- Shipped: `src/types/wire.jl`, `qbool.jl`, `src/surface/casts.jl`,
  `test/choi.jl`.
- **D1 literal** `QBool(p, φ=0)`; consuming casts; P2 implicit-cast
  warning; use-after-consume errors with register identity.
- **Choi harness** on the DM context — coherent-probe pinching (the wm28
  gate) live. **Choi cap corrected to ≈7 wires** (F25/`rlhj`: a 15-wire
  Choi is a 30-qubit DM = 2⁶⁰ entries — the old "15-wire" figure was
  ~2× wrong in the exponent). Larger channels use sampling / randomized
  reference-assisted probes.
- **Carried debt (F16):** `QBool` stores `ctx::AbstractContext` (dynamic
  dispatch). M8's context-dependent cast return type forces the
  `QBool{C}` / `QInt{W,C}` refactor — a **hard pre-M8 prerequisite**
  (§3.0).
- **Carried debt (F27):** the D1 pole-degeneracy test is restated at the
  density-matrix level (handles are identity; states compare up to
  phase) — done in `rlhj`.

### M4 — Views, `dual`, the action family — and teleportation — SHIPPED (session 95, 13,772 tests)

- Shipped: `src/kernel/views.jl`, `src/surface/{dual,actions}.jl`.
- X↔Z swap, CZ symmetry, views-unwrap-processes-compose all green.
- **Teleportation §7.1** — `Choi(teleport) ≈ Choi(id)`, **perfect
  1024/1024 incl. the |i⟩ Y-probe**; the wm28 regression killed forever.
- **Spec-grade finding:** `DualView` must be **mutable** — an immutable
  struct's `===` is structural, which broke `dual(dual(q)) === q`.

### M5 — `when`: streaming ctrl with guardrails (D13) — SHIPPED (session 95, 13,822 tests)

- Shipped: `src/surface/when.jl`; control stack in contexts.
- Streaming `ctrl(op)` op-by-op; guardrails as runtime laws;
  **§8.1 closed BY CONSTRUCTION** (the most dangerous v0.1 hole);
  deferred teleport one-run `Choi ≈ J(id)`.
- **⚠ AMENDED BY THE M8 5hr7 GATE (F1).** The Eager `|1⟩`-marginal
  clean-ancilla check is a **sound fail-fast per-run assertion** — it
  never accepts a dirty run (verified against the reviewer's adversarial
  CNOT-on-`|+⟩` case, it fires loudly). But it is **not a structural
  witness**: it certifies the *run*, not the *program*, and under Tracing
  there is no state to check. M8 replaces the *witness role* with a
  structural `CleanCert` (`NoAncilla`/`PermClean`/`MatchedPair`, 5hr7 §2)
  and **demotes the marginal check to a debug cross-check** that the
  certificate was honoured. D13 is amended accordingly (5hr7 §7.9).
  This is a redesign of M5's *witness*, not of M5's shipped behaviour.

### M6 — `QInt{W}`, wire handles, and the two arithmetic worlds (D12) — SHIPPED (session 95, 14,711 tests)

- Shipped: `src/types/qint.jl`, `src/surface/arithmetic.jl`, QFT node.
- **D2** `x[i]` typed wire handle; **all 4 Pontryagin sign pins green**
  (incl. the F²-vs-unwrap integer-negation signature). Two-world
  registry (action world in-place, value world fresh-output); strict-mode
  lost-binding detector.
- **Carried ruling debt (F15):** "registers are numeric types" is
  sharpened to "number-like handles" with a published operator/trait
  interface (a ruling, not a blocker — M6 shipped; the ruling refines
  wording and routes branch-heavy generic code through `oracle`).
- **Carried decision debt (F23/F24):** `Int(x)` machine-width bound for
  `W ≥ WORD_SIZE`; `QMod{N}` type-stability when `N` is a runtime arg.
  Both bite at M9 (Shor doubles width to `QInt{2W}`); listed as M9
  entry considerations.

### M7 — Bennett bridge: `oracle`, kickback, DJ and BV — SHIPPED (session 96, 14,965 tests)

- Shipped: `src/bennett/bridge.jl`, weakdep `ext/SturmBennettExt.jl`.
- `oracle(f, x)` → `CompiledOracle`/`OracleQuery`; `b ⊻= oracle` D9
  accumulate; **MBU-free by the type boundary** (`ctrl(Perm)=Perm`
  discharges the M5 when-oracle IOU + the §3.4 MBU-under-ctrl named test).
- `_role_tables` = **the single MSB/LSB remap choke point** (Bennett
  pos-1=LSB vs Sturm wire-1=MSB), lint-enforced. **Zero-tail |0⟩
  witness** (Bennett couples output width to compute width).
- **DJ §7.4 / BV §7.5 verbatim.** **6xdk RULED & SHIPPED** (session 97):
  wire-1=MSB wins kernel-wide; §7.5 readout is `evalpoly(2, reverse(bits))`;
  **§7.7 Shor had the same bug** (F21) — the modular-power control loop is
  now `2W:-1:1`. BV testset extended from palindromic {0,2,5} to **all 8
  3-bit secrets** (bv_s7 needs `eager(26)`). Targeted run **239/239 green**.
- **Carried decision debt (F22):** `shor_order` returning the order from
  one continued-fraction denominator is a candidate divisor, not the
  order — repetition/modular-verification/LCM is a real M9 semantic
  decision (below).

---

### 3.0 — PRE-M8 GATES and the proof/semantic decision schedule (F34)

The review's F34 charge: proof and semantic decisions that constrain the
M8 IR were scheduled *after* it. This section pulls them forward and names
where each now lives. **M8 code may not begin until every gate here is
cleared.** The two design rounds (`5hr7`, `i4ri`) are **RESOLVED** as
canonical synthesised designs; what remains are three Tobias-grade rulings
and one refactor.

**Design gates — RESOLVED (canonical syntheses landed, session 98):**

- **`5hr7`** — typed channel IR + structural clean-ancilla certificate +
  phase-preserving pass contract (F1/F2/F3; touches F9/F10/F12/F25/F26/F28/F33).
  Design: `docs/design/m8-5hr7-unitary-block-design.md`. Splits
  `UnitaryDAG` into `ChannelDAG` (not a process value) and
  `UnitaryBlock{N} <: ProcessValue` (certified fixed-port unitary); the
  `CleanCert` closed constructor set is the state-independent F1 witness;
  the pass contract preserves the phase-inclusive `≈` representative and
  is enforced by `PASS_REGISTRY` + boot lint.
- **`i4ri`** — classical-control IR (F4/F5/F6/F13/F30). Design:
  `docs/design/m8-i4ri-classical-control-design.md`. A **restricted
  classical SSA EDSL** (not staged lifting, not a host tracer):
  `ClassicalBit`/`ClassicalWord{W}` tokens flow only through T1–T4
  (`cases`/whitelisted total primitives/`select`/return), never
  control-flow or indexing position; the token **is** the pinched-live
  classical record (reuses shipped `_instrument!`); `cases` join-typing
  is quantum-port-signature equality; DM executes the exact instrument
  sum via `ctrl`-off-the-c-wire.

**Ruling gates — ✅ RESOLVED (Tobias, session 98; i4ri doc §14, RULINGS
commit 8313932). PRD wording applied by `w5rw` (e834d36); F16 landed
(`vanm`, 22f4994). M8 code is UNGATED.**

- **`vqas`** (F13 — measurement verb spelling). **RULED: Option D**,
  overruling both proposers' Option-A recommendation — `Bool(q)`/`Int(x)`
  are the SINGLE spelling in every context, returning the classical system
  as the context represents it (Eager scalar / DM record token / Tracing
  wire token); there is NO `measure` verb; `if token` raises Julia's
  native `TypeError`; portable idiom `cases(Bool(q))` / `@cases Bool(m)`;
  tracer pre-flight lint mandated (PRD §3.6/§3.8/D3 as shipped).
- **`z1sa`** (TR1–TR8 from `5hr7` §8). **RULED: all eight as
  recommended** (session 98). Consolidated rulings on:
  TR1 `UnitaryBlock{N}` square shape + rename; TR2 Eager failure
  topology (poison-on-failed-seal); TR3 canonical scratch spelling
  (`QBool(false)` blessed, `within` stays `public`, seven surface
  constructs preserved); TR4 certificate completeness (conservative
  closed constructors); TR5 `Perm`/`MCX` immutability refactor; TR6
  under-sized oracle targets; TR7 phase-delta scope + zero-port scalar
  blocks; TR8 `denoted_matrix` memory-budget cap.
- **`xy4w`** (D15 — arbitrary `QBool(p, φ)` literal inside `when`).
  **RULED: option (b)** (session 98) — admitted only inside a certified
  compute/uncompute unitary block (`MatchedPair`, PRD §4.1a) whose
  ancilla the §3.9 witness cleans; a bare literal under `when` stays a
  loud error naming D15 (PRD D15 as shipped).

**Refactor gate — F16: ✅ LANDED (`vanm` 3+1, commit 22f4994 — `QBool{C}`
/ `QInt{W,C}` / `WireRef{C}`, typed `_here`, F15 loud surface, F19
duality trait; suite 25245/25245).** As originally stated: the cast path
cannot be type-stable while `QBool` erases context into
`ctx::AbstractContext` and M8 makes the cast return type context-dependent.
Parameterise handles internally — `QBool{C}`, `QInt{W,C}` — keeping the
ergonomic constructors and partially-parameterised signatures. This is the
**one genuinely unscheduled decision** F34 surfaced that is not already
absorbed by a design doc or a ruling; it is now an explicit pre-M8 gate and
a hard dependency of the `i4ri` `measure` return-type story (i4ri R2).

**Where the deferred proofs/decisions now live (F34 audit):**

| F34 concern | Old schedule | New home |
|---|---|---|
| Universality/adaptivity proof "before implementation" (§3.7) — constrains `cases`/literals | M9 writeup | The *constraints it drives* are frozen in `i4ri` (restricted classical IR: no token in control-flow; `cases` join rule) and `5hr7` (certified literals: `QBool(false)` blessed, arbitrary literals → D15/`xy4w`). The `docs/physics/` **writeup** stays M9 but is no longer load-bearing for the M8 IR. |
| M7 traced semantics (`OracleQuery`/`Perm`, control-aware strategy, borrow ownership) that M8 depends on | "M8 ∥ M7" | **M7 SHIPPED.** Dependency discharged; the parallelism claim is retired (§2). |
| F1/F2/F3 (witness, port typing, phase-blind passes) before the M8 IR | implicit in M8 | `5hr7` (resolved design; code gated on `z1sa`). |
| F4/F5/F6/F13/F30 (classical-control semantics) before `cases`/tokens | implicit in M8 | `i4ri` (resolved design; surface spelling gated on `vqas`). |
| F7 (modular multiplication not a permutation) before Shor | M9 as written | `addq` (P1, filed; M9 text rebaselined below — the fix is *not* designed here). |
| F8 (QECC superchannel typing) before `encode` | M11 as written | Filed for M11 (F8 typing bead); M11 text rebaselined below. |
| F9 (U(d) not SU(d)) before any qudit value | D6/M12 | `rlhj` (shipped: QMod values carry the U(1) phase, center quotient stated). |

### M8 — TracingContext, typed channel IR, classical control, phase-faithful passes — GATED (bead `szx1`)

**Entry criteria: all of §3.0 cleared** (`z1sa`, `vqas`, `xy4w`, F16
refactor). Build order is the seven-part split from `5hr7` §7.10, with the
`i4ri` classical layer as part (7):

1. **Typed immutable `ChannelDAG`** (`src/channel/`): `Port`/`PortID` SSA
   edges with **resource lineage** (width equality is not identity —
   5hr7 §1.2); effect-typed nodes `ApplyN/AllocN/TraceN/MeasureN/CasesN/NoiseN`;
   `MeasureN`/`CasesN`/`NoiseN` are the unitary-pass **barriers**; nodes
   carry process values, **never gate names**. `ChannelDAG` is **not** a
   `ProcessValue` and has no `ctrl` method (P4 → `MethodError` for free).
   Deep-immutable (F28): freeze on construction; do the `Perm`/`MCX`
   `NTuple` refactor here (M1 debt / TR5).
2. **Unitary-candidate tracing + structural sealer** (`src/channel/cert.jl`):
   `certify(::ChannelDAG)::UnitaryBlock` or a loud `ArgumentError`. The
   closed `CleanCert` constructor set — `NoAncilla`, `PermClean` (Bennett
   `(★)`), `MatchedPair` (`within` = C†∘M∘C), `SeqCert`, `ParCert`,
   `AdjointCert`, `XportCert` — discharges the universal invariant
   `(I−ιι†)Wι=0` **structurally, no state/Choi/sampling**. The F1
   adversary (`a = QBool(false); a ⊻= r; drop a`) is rejected structurally
   even when the Eager marginal is 0.
3. **`UnitaryBlock` application/adjoint/control** (`src/kernel/unitary_block.jl`):
   `UnitaryBlock{N} <: ProcessValue` inherits `∘`/`⊗`/`adjoint`/
   `denoted_matrix`/`≈`; `ctrl(::UnitaryBlock)` is the **one** method added
   to the choke point, sound by the §4.2 control-scope-reassociation law
   (Alloc/Trace stay uncontrolled; only `ApplyN`s are control-wrapped).
4. **Eager tee-tracing + debug assertions**: Eager streams *and* records
   the transcript; region exit attempts structural sealing; the M5
   `|1⟩`-marginal check survives **only as a demoted debug cross-check**
   (F1). Failure topology = ruling TR2 (poison the context).
5. **Channel-pass framework**: channel passes preserve Choi/diamond; may
   not promote a result to `UnitaryBlock`.
6. **Representative-preserving unitary-pass framework**: `PASS_REGISTRY`
   + boot lint mirroring the `ctrl` choke point; every `UnitaryPass`
   preserves the phase-inclusive `≈` representative (tier 1a) **or**
   reports an explicit phase delta reattached before sealing (tier 1b).
   Passes: reassociation, view-fusion, 1q-quaternion-fusion (all δ=0),
   deferred measurement, `within`. **Choi equality of uncontrolled values
   is NOT a unitary-pass proof** (F3, Tang–Wright Thm 1.1) — every unitary
   pass carries a `ctrl`-wrapped pre/post channel test.
7. **Classical-control IR (`i4ri`) — F13 ruled Option D (no measure
   verb)**: `ClassicalBit`/`ClassicalWord{W}` tokens returned by the
   `Bool(q)`/`Int(x)` casts under DM/Tracing; `cases`/`@cases`
   with quantum-port-signature join-typing (`cases` returns `nothing`;
   branch-dependent classical values via `select`/`ClassicalTable`, not a
   phi); copyable tokens + retained correlation record traced at last use;
   DM c-wire executor (`_instrument!` + `ctrl`-off-c-wire + `_trace_and_free!`,
   **no new physics primitive**); `shots` HOF over Eager for trajectories.
   `@cases Bool(m)` (Ruling D spelling; F30 ruled: register-accepting
   `@cases m` rejected).

- **Named tests:** the 5hr7 `M8.*` battery (19 tests incl. the phase
  sentinel `M8.PASS.PHASE-SENTINEL`, `M8.CERT.STATE-IS-NOT-WITNESS`, and
  the strengthened `M8.WHEN.STREAM-MATERIALIZED-CTRL`) and the i4ri
  `L1–L21` battery (incl. `L2` instrument sum, `L4` cases-exact Choi, `L5`
  repeated-token correlation with the mandatory **phase form** — pinched
  records are diagonal-blind, the wm28 lesson). The M5 streaming≡materialized
  IOU closes here.
- **DM `cases`:** exact instrument semantics, one-run deterministic Choi.
- 3+1: **YES** (IR is kernel — already run as the `5hr7`+`i4ri` gates).
  Distillations first: Fu et al. 2204.13041; qrisp/Jasp docs (D3
  precedent); Bădescu–Panangaden (`docs/physics/badescu_panangaden_*.md`,
  the controlled-alternation obstruction); Tang–Wright
  (`docs/physics/tang_wright_2025_controlled_unitaries.md` Thm 1.1) and
  Delorme (`docs/physics/delorme_control_as_constructor.md`) for the phase
  sentinel.
- Quarry: v0.1 `channel/` + `passes/` for DAG plumbing *shapes* only
  (isbits node layout, barrier discipline). Skepticism: v0.1 nodes encode
  Ry/Rz/CX names — v2 nodes carry process values; do not import the node
  vocabulary.
- **Residual M8 blockers explicitly outside these two designs** (flagged,
  not resolved): F29 pairwise alias checks among *nested controls* incl.
  dual views before relying on a flat control count; a future quantum-φ
  `cases` join (deferred); `SU(d)`-only values are incompatible with the
  pass contract unless they carry their `U(1)` phase (F9 — enforced from
  M9/M12).

### M9 — Capstones: QMod full-space permutation, the injection ladder, order finding — (bead `8oo9`; ⚠ `addq` P1)

**⚠ REBASELINED for the `addq` P1 bug (F7). DESIGNED — see
[`docs/design/m9-addq-inplace-perm-design.md`](docs/design/m9-addq-inplace-perm-design.md)
(3+1 synthesis of proposals A/B; closes F7/F22/F23/F24).** The M9-as-written
`mulmod!(y, c)` = Bennett-compiled `v -> (c*v) % N` Perm is **not a permutation
of the physical Hilbert basis**: for `N=15` in 4 wires, basis states 0 and 15
both map to 0 — many-to-one, not unitary. The resolved work items (full detail
in the design doc):

- **Full-space permutation (eq 1).** `mulmod!(y::QMod{N,W,C}, c)` denotes
  `v ↦ (c̄·v mod N) for v < N, else v` (`c̄ = mod(c,N)`, identity on the padded
  tail) — a genuine bijection of the `2^⌈log₂N⌉` basis states; `gcd(c̄,N)=1`,
  `N ≥ 2` preconditions, loud `DomainError` naming `c/N/gcd` before any
  allocation. Bennett callable is a fixed-`W` overflow-free double-and-add, NOT
  `(c*v)%N` (Bennett narrows mod `2^W`).
- **In-place-Perm compiler contract** — `verify_inverse_pair(f, finv, Val(W)) →
  compile_inplace_perm(pair) → CompiledInplacePerm{W}`, in `src/bennett/inplace.jl`
  (+ `ext/SturmBennettExt.jl` for the two compilations through the **existing**
  `_BENNETT_BACKEND`, + `src/library/modular.jl` for `mulmod!`). Compute/swap/
  uncompute against a **separately compiled** `f⁻¹` (`adjoint(U_f)` gives `f∘f`,
  wrong) into **one frozen kernel `Perm`** of width `2W + max(A_f,A_g)` (shared
  ancilla pool); `W + max(A_f,A_g)` fresh scratch per application; one `_act!`.
  Inverse agreement proved **before any quantum action**: Tier E exhaustive
  replay of the compiled `Perm` for `W ≤ PERM_EQ_MAXW (=20)`, else a **registered,
  closed** analytic/structural proof (`FullSpaceMulProof{N,W}`) — no `check=false`,
  no sampling-as-proof, no open witness trait. Private construction choke point
  `_compiled_inplace_perm` (boot-lint gated, like `_ctrl`). `public`, not
  exported, NOT an eighth surface construct. Its own 3+1 round (this doc).
- **§4.1a certificate** — the composite carries **`PermClean`** (declared clean
  ports = copy block ∪ ancilla pool), justified by the inverse-pair theorem, via
  a second combinator-carried route `compile_inplace_perm ⇒ PermClean`. **No new
  `CleanCert` variant.** MBU excluded **by construction** in every context (a
  `Perm` has no measurement node) ⇒ safe to reuse inside `when`; `ctrl^k(Perm)=Perm`.
- **QMod values are U(d), not SU(d)** (F9/`rlhj`): the modular process value
  carries its `U(1)` phase (canonical zero-phase `Perm`).
- **F23/F24 (width & type-stability):** `Int(x)` stays an honest machine-`Int`
  cast, throwing **before** backaction for `W ≥ Sys.WORD_SIZE`; the wide qc cast
  is **`BigInt(x)`** (a constructor-spelled cast, no `measure` verb). `QMod{N,W,C}`
  — modulus **static** in the type (matching the *already-shipped* `QInt{W,C}`
  F16/`vanm` convention), `W` derived, **no runtime modulus field**; entry
  `shor_order(a, ::Val{N})`. Repair the `1 << W` overflow at `qint.jl:66-67`
  **and** `arithmetic.jl:79,167` (`mod(a, 1<<W)` — missed by both proposals) with
  `big(1) << W`; reject `W ≤ 0`.
- **`shor_order` return contract** (F22): `shor_order(a, ::Val{N}; max_samples=32)`
  — bounded repeated fresh sampling, `gcd(a,N)=1` precondition (→
  `NonCoprimeBaseError` w/ factor), `a₀==1 ⇒ 1` guard, exact `BigInt` continued
  fractions (`Q = big(1)<<(2W)`, no `4^W`/`rationalize`), skip `q=1`, `lcm`
  accumulation with contamination reset, `powermod` verification, exact
  prime-strip minimization, `OrderFindingFailure` at the retry limit. Never
  returns `nothing`, a raw denominator, or an unverified LCM. Corrected `2W:-1:1`
  control schedule (F21).
- **Physics gate (CLAUDE.md #4, prerequisite BEFORE code):** amend
  `docs/physics/bennett_1973_logical_reversibility.md` with an "Inverse-assisted
  in-place permutation" subsection (eq ★ and eq 3); **add the missing**
  `docs/physics/shor_order_finding.md` + a local primary-source PDF (phase-sample
  eq, continued-fraction theorem, `Q ≥ N²`, repetition/LCM, `powermod` verify,
  success-probability threshold for the §9.6 statistical test).
- **PRD amendments are STAGED** in the design doc §8 (§7.7 driver rewrite; §7.6
  `Bool(m)`/`@cases` wording; §3.4 in-place action paragraph + MBU qualifier;
  §4.1a generalized `PermClean` bullet; §3.1/§3.2 `QMod{N,W,C}` + `Int`/`BigInt`
  bounds) — applied post-`vanm` under the doctest lint, not by this round.

- **Universality writeup** (§3.7 proof obligation) in `docs/physics/` with
  RBB/ZLC/Gottesman–Chuang/Bravyi–Kitaev distillations (injection circuit
  = GC/ZLC; BK = distillation). No longer gates the M8 IR (§3.0).
- **Worked examples land:** `inject_S!`/`inject_T!` §7.6 (channel test:
  Choi ≈ S/T on random probes, both outcomes, the non-Pauli S-correction
  path explicit; `@cases Bool(m)` per the `i4ri`/F30 ruling + session-98
  Ruling D — the stale `@cases measure(m)` spelling is retired, there is no
  `measure` verb); `shor_order` §7.7 end-to-end for small N (15, 21) — the
  ≥1000-trial statistical order-finding suite, permutation-bijectivity
  tables, controlled-Choi, inverse-contract, overflow-boundary, and QMod
  inference tests of the design doc §9.
- **The §8 ledger:** §8.1 already closed at M5 (shipped). Remaining defect
  classes get named green regressions by end of M9 (8.3→M4, 8.4→M2/M4,
  8.5→M6, 8.6→API-shape review, 8.7→M1 totality, 8.8→M4; 8.2 died with the
  surface).
- 3+1: **DONE** for the in-place-Perm contract (design doc = A/B synthesis;
  reviewed by orchestrator); otherwise composition of existing core.
  Distillations: the four universality papers, the Bennett in-place
  subsection (eq 3), and the **new** `shor_order_finding.md` (+ local PDF).

### M10 — Library HOFs — (bead new)

- `amplify`/`find` (Grover: nested `when` + `not!(dual(·))` for the
  multi-controlled Z — *exact*, no Toffoli-cascade folklore; diffusion
  = H^⊗n materialization via kernel value, the D4 answer), Grover
  pipeline test; `phase_estimate` (controlled modulation + `Int(dual)`);
  `evolve!` (Trotter first; the QSVT pipeline is M12-horizon and returns
  through the reimport gates with its `docs/physics/` distillations);
  `interfere!`; `within` public (its certificate role is `MatchedPair`,
  5hr7 §2.2).
- Quarry: the D5 port notes (worklog session-92) sketch the exact
  per-function shrinkage — use them as the spec; the v0.1 function
  bodies only as line-count exhibits.

### M11 — Noise, Stinespring fallback, QECC scaffold — (bead new; ⚠ F8/F33 typing)

- Kraus channel values applied through the same surface; pure-context
  policy: loud error (default) or **Stinespring dilation fallback** — but
  the dilation contract must be specified (F33): Kraus-rank padding,
  isometry synthesis `V|ψ⟩ = Σ K_i|ψ⟩|i⟩`, unitary completion tolerances,
  environment ownership, and the rule that the dilation is an **execution
  artifact, never a controllable representative** of the channel.
- **`encode(ch, code)` needs re-typing before it is implemented (F8).**
  The single `Channel → Channel` HOF conflates three distinct operations:
  protecting physical noise `Θ(𝓝) = D∘R∘𝓝∘E : Chan(P,P) → Chan(L,L)`;
  encoding a state; and fault-tolerantly lifting a logical algorithm
  (not canonical — needs transversal gadgets/magic-state protocols/fault
  model). Replace with typed operations (`encode_state`,
  `effective_logical_noise(::Channel{P,P}, code)`, `fault_tolerant_lift`)
  modelled as superchannels/combs with explicit port types. **This is a
  carried-contract re-derivation gate** (§7, verdict c). Steane
  re-derivation is its own later epic (reimport gates, Choi-level
  encode∘decode tests).
- The `i4ri` classical-control IR is the substrate for the syndrome path
  (one syndrome token drives several corrections via `select`/`ClassicalTable`
  — the canonical copyable-token customer, i4ri §2.2).

### M12+ — Horizon (not planned in detail here)

Hardware transport (carried design, F8-typed ports), **QMod{d} conjugate
structures** — D6 is now **split** (F37): the uniform cyclic Fourier dual
`dual(::QMod{d})` is unblocked for all d and can land early; only the
parity-sensitive Weyl/Clifford/metaplectic phases (the d mod 4 Gauss-sum,
2⁻¹ mod d) stay research-gated. CV/anyons (P7 arms) are **narrowed to a
research extension** (F32): the current tensor/control/trace interface is
proved only for finite-dimensional abelian-label registers; CV
(Gaussian/non-Gaussian under control, no finite Choi) and anyons (fusion
sectors, braided monoidal structure) need new traits, not "mere instances."
QSVT/block-encoding reimport, OpenQASM export, Sextant visualization hooks.

---

## 4. Cross-cutting workstreams

- **Test harness:** `choi(f, n)` (DM, exact, one-run, **≈7-wire cap** by
  memory budget — F25/TR8); Eager-vs-DM statistical agreement (N ≥ 1000,
  ±3σ policy); `shots(f; N)` over Eager for channels too large to Choi;
  seeded tests never assert trace placement or RNG-stream identity across
  lowering changes; every PRD "required test" gets a `@testset` named after
  its PRD section (grep-able coverage map).
- **Numerics policy:** U2 canonicalization + atol constants in one file
  (`kernel/numerics.jl`), documented against §4.1; **`==` is structural,
  `≈`/`same_process` is semantic** (F26 — never put tolerance-`≈` into
  `Base.==`; it is not transitive and would corrupt caches/dicts of
  process values). Renorm cadence benchmarked once.
- **Performance:** per-wire 1q fusion buffer in Eager; per-wire picture
  tag for view fusion; context passed through kernel call chains
  (ScopedValue read once per surface entry). **F16 handle-context
  parameterisation** (`QBool{C}`, `QInt{W,C}`) is the type-stability
  precondition for the M8 cast/action/tracing paths. `@code_warntype`
  gate on: apply path, xor path, cast path.
- **Deep immutability (F28):** process values (`U2`, `Perm`, `ChannelDAG`,
  `CleanCert`, `UnitaryBlock`) are frozen on construction — no immutable
  struct wrapping a live `Vector`. Mutable builders during tracing/pass
  construction; freeze-copy on `certify`/`commit`. `Perm`/`MCX` `NTuple`
  refactor (TR5) is the M8 prerequisite.
- **Error policy (S13):** DomainError (chart violations), ArgumentError
  (well-formed-but-forbidden, D2-style, with the suggestion in the
  message), `error()` with register identities for guardrails. No custom
  exception hierarchy. **Token footguns (i4ri):** bare `if token`/`&&`/`||`
  is Julia's native, non-interceptable `TypeError` — documentation must
  **not** promise a Sturm-dispatched error there; Sturm-owned methods
  (`convert(Bool, ::token)`, `getindex(::Array, ::token)`) throw
  descriptive errors pointing at `measure`/`cases`/`select`.
- **Docs:** every non-trivial function cites its distillation; `dual`'s
  docstring carries the two parser traps (call-LHS op-assign; `dual(x) = y`
  local-method shadowing) and the JuliaLang#20978 cautionary tale.

## 5. Bead map (rebaselined 2026-07-21)

| Milestone / gate | Bead | Status |
|---|---|---|
| epic | `u0xw` | open (umbrella) |
| M0 | `23o1` + `hn90` | **SHIPPED** (13/13 doctest lint) |
| M1 | `c52g` (+ Perm/ctrl/algebra) | **SHIPPED** (12,752) |
| M2 | FFI + contexts + regions | **SHIPPED** (13,573; D7 resolved) |
| M3 | QBool + casts + Choi harness | **SHIPPED** (13,711) |
| M4 | views + dual + actions + teleport | **SHIPPED** (13,772) |
| M5 | when streaming + guardrails | **SHIPPED** (13,822; witness amended by 5hr7) |
| M6 | QInt + arithmetic worlds | **SHIPPED** (14,711) |
| M7 | Bennett bridge + DJ/BV | **SHIPPED** (14,965; 6xdk fixed) |
| M8 design gate | `5hr7` | **RESOLVED** (canonical synthesis; awaits `z1sa` rulings for PRD paste) |
| M8 design gate | `i4ri` | **RESOLVED** (canonical synthesis; awaits `vqas` ruling for PRD paste) |
| M8 ruling gate | `vqas` (F13 measure verb) | **OPEN — Tobias** |
| M8 ruling gate | `z1sa` (TR1–TR8) | **OPEN — Tobias** |
| M8 ruling gate | `xy4w` (D15 literal-under-when) | **OPEN — Tobias** |
| M8 refactor gate | F16 (`QBool{C}`/`QInt{W,C}`) | open — land before M8 cast work |
| M8 | `szx1` | **GATED** on the four rows above |
| M9 | `8oo9` (capstones) | open; **⚠ `addq` P1** (full-space perm + in-place-Perm contract) blocks the QMod arm |
| M9 bug | `addq` | open (P1, F7) |
| M10 | library HOFs | open |
| M11 | noise + QECC scaffold | open; **⚠ F8** QECC superchannel re-typing gate |
| PRD accuracy patch | `rlhj` | **APPLIED** (commit `93f36fd`, 9 findings) |
| this rebaseline | `rzkx` | in progress |

Dependency chain is now **strictly linear**: M7 (done) → §3.0 gates → M8
→ M9 → M10 → M11. The old "M8 can start in parallel with M7" line is
**deleted** (F34: M8 depends on M7's traced `OracleQuery`/`Perm` semantics,
control-aware strategy, and borrow ownership — a semantic dependency the
file-overlap argument missed).

## 6. Risk register (refreshed 2026-07-21 — F35)

**Retired (resolved by shipped work):**
- ~~Bennett.jl v2-compatibility~~ — resolved: M7 shipped, D14 ruled
  (circuit-only bridge), weakdep extension green.
- ~~Orkan ABI drift / D7~~ — resolved: 24/24 ccall signatures verified
  against live headers at M2.
- ~~D14 open~~ — ruled and shipped (session 95).
- ~~D6 fully research-gated~~ — **downgraded**: F37 split unblocks the
  uniform cyclic `dual(::QMod{d})` for all d (now an M12 early item);
  only the Weyl/Clifford/metaplectic parity layer remains gated.

**Live:**
1. **Ruling latency (M8-blocking).** M8 cannot start until `vqas` (F13
   measure verb), `z1sa` (TR1–TR8), and `xy4w` (D15) are ruled by Tobias,
   and the F16 handle-context refactor lands. The designs are done; the
   critical path is now *decisions*, not analysis.
2. **Tracker fragility.** The embedded Dolt DB is degraded (session 97):
   `bd dep add` fails (missing `wisp_dependencies` table — gates recorded
   as `--notes`), `bd dolt push/pull` conflicts. **`.beads/issues.jsonl`
   in git is the canonical recovery source.** Risk: a gate/dependency is
   lost because it lives only in a note. Mitigation: this plan §3.0/§5
   duplicates every gate in prose; consider `bd init --force` + re-import,
   or server mode, next session.
3. **`addq` — M9 modular-permutation P1 (F7).** `mulmod!` as planned is
   not unitary on the padded space; the fix (full-space permutation +
   a new in-place-Perm compiler contract via `f⁻¹`) is unbuilt and is the
   load-bearing M9 step. The Shor capstone cannot land until it exists.
4. **State-dependent `when` witness (F1).** The M5 Eager marginal check is
   sound fail-fast but not a structural witness; under Tracing it is
   inapplicable. Mitigated by the `5hr7` `CleanCert` design, but the
   structural sealer + the M5 demotion are real M8 work with a subtle
   correctness burden (the F1 adversary must be rejected structurally).
5. **Phase-sensitive pass correctness (F3).** Choi is phase-blind
   (`Ad_U = Ad_{e^{iα}U}`); a Choi-only pass check re-admits the
   Cirq/Qiskit/pytket controlled-phase bug class the moment a pass output
   reaches `ctrl`. Mitigated by the `5hr7` `≈`-representative contract +
   `ctrl`-wrapped pass tests + `PASS_REGISTRY` boot lint — but the
   discipline must hold for *every future pass* (QSVT synthesis included).
6. **Classical-control IR scope (F4/F6).** Julia cannot trace `if`/`for`/
   indexing on a symbolic token; the `i4ri` restricted SSA EDSL covers
   teleport/injection/syndrome/bit-uniform QROM but **not** arbitrary
   Julia. Immediate branch accumulation destroys token correlation (F6) —
   the record must survive to a token's last use. Risk: users reach for an
   unsupported classical construct; mitigation is the fail-loud T1–T4
   boundary + descriptive owned-method errors.
7. **F16 sequencing.** The handle-context parameterisation is invasive
   (touches every cast/action signature) and is a *prerequisite* of M8,
   not a within-M8 task. Cheap now, expensive if deferred into the middle
   of M8 (i4ri R2). Scheduled as an explicit pre-M8 gate (§3.0).
8. **Choi capacity (corrected).** Exact DM Choi is **≈7 wires**, not 15
   (F25 — a 15-wire Choi is a 2⁶⁰-entry DM). Law tests use small exact
   Chois; capstone/large-channel statistics use `shots`/randomized
   reference-assisted probes. The old risk-4 "15-wire" figure was wrong.
9. **Concurrency.** The "one region, one task" assumption is stated, not
   enforced beyond ScopedValue correctness — revisit when a real parallel
   story is designed.
10. **Ergonomics regressions.** Any new surface form must pass the two
    slogans (§2 of CLAUDE.md #11) AND the doctest lint. The M8 designs
    hold the line at **seven surface constructs** (TR3: `within` stays
    `public`, not an 8th construct; `measure` per `vqas` replaces the
    `Bool(q)`-token overload, not adds to it).

---

## 7. Carried v0.1 contracts — consolidation (F31)

**F31's charge.** The PRD introduction says *"Everything not explicitly
changed here — contexts, Orkan FFI, the Bennett bridge, QECC-as-HOF,
promotion, the channel-IR passes discipline — carries over from v0.1."*
That is not a safe normative-incorporation rule: v0.1 contains sampled DM
measurement, task-local context propagation, and gate-named DAG nodes, some
changed only implicitly. Below, every carried contract is given an explicit
verdict — **(a)** already re-derived in v2 (with citation), **(b)** carried
verbatim deliberately (with the reason it is v2-safe), or **(c)** NEEDS
re-derivation (listed as a gate on the milestone that consumes it).
**Nothing is silently imported.**

| # | Carried contract | Verdict | Where / why |
|---|---|---|---|
| 1 | **Contexts** (Abstract/Eager/DM/Tracing, regions, propagation) | **(a) re-derived** | v2 §3.9 (regions = Stinespring boundary), §3.8 portability, `Base.ScopedValues` **replacing task-local storage** (session 93/95 — TLS does not inherit into `@spawn`); shipped at M2. The one v0.1 clause explicitly overturned: DM `if`/`&&` on a scalar outcome (the §3.8 table said ✓) — **wrong**, re-derived by `i4ri` (DM returns a token; exact instrument sum; scalar only in trajectory/`shots` mode). The shipped code already rejected the v0.1 behaviour. |
| 2 | **Orkan FFI** (ccall names/shapes, handle ownership, ZYZ singularity boundary) | **(b) verbatim, re-verified** | Carried deliberately: ccall shapes are ABI facts, not design choices. v2-safe because **re-verified by measurement** against the live headers at M2 (24/24 signatures current, session 95), never trusted from the branch. CLAUDE.md fixes the ZYZ θ≈0/π singularity at this boundary and only here. |
| 3 | **Bennett bridge** (oracle artifact shape, D9 accumulate, strategy selection) | **(a) re-derived** | v2 M7 (`src/bennett/bridge.jl`), D9 + D14 (circuit-only) ruled; the MBU-under-`ctrl` exclusion and the MSB/LSB remap choke point are v2-native. The v0.1 *interface shape* was reused; the *semantics* re-derived (session 96). |
| 4 | **Promotion** (P8 overloads, two-world arithmetic registry, P9) | **(a) re-derived** | v2 §3.4/D12 two-world registry; shipped at M6 (value-world fresh-output + P8 promotion tested). Carried debt, **not blocking**: F15 sharpens "registers are numeric types" → "number-like handles" with a published trait interface (a ruling refining wording, since M6 shipped). |
| 5 | **Channel-IR passes discipline** ("partition at measurement barriers; unitary methods only on unitary blocks") | **(a) re-derived — the load-bearing half by `5hr7`** | The *barrier-partition idea* carries over v2-safe (it is a type invariant in v2: a barrier-containing DAG never promotes to `UnitaryBlock`, §3.M8). But v0.1's *correctness criterion* — Choi equivalence certifies a pass — is **unsafe** (F3: Choi is phase-blind) and is **re-derived** by `5hr7` §3: phase-inclusive `≈` for unitary-block passes + `ctrl`-wrapped tests + `PASS_REGISTRY` lint. Do not carry the Choi-only criterion. |
| 6 | **QECC-as-HOF** (`encode(ch, code) :: Channel → Channel`) | **(c) NEEDS re-derivation — gates M11** | F8: the single `Channel → Channel` signature conflates protecting noise `Θ(𝓝)=D∘R∘𝓝∘E`, encoding a state, and fault-tolerantly lifting a logical algorithm (non-canonical). **Not v2-safe as carried.** Re-typed into `encode_state` / `effective_logical_noise(::Channel{P,P}, code)` / `fault_tolerant_lift` as superchannels/combs with explicit port types — an explicit gate on M11 (§3.M11, filed as the F8 typing bead). |

**Verdict counts: (a) re-derived = 4 · (b) verbatim = 1 · (c) needs
re-derivation = 1.** The single (c) — QECC-as-HOF — is not consumed until
M11, so no shipped code depends on it; it is gated there. The single (b) —
Orkan FFI — is safe only because it was re-verified against the live headers,
not trusted. Contract 5 is (a) with a sharp caveat: carry the barrier idea,
**never** the Choi-only pass-correctness criterion.

> **Recommendation to fold into the PRD (F31 fix sketch).** Replace the
> intro's blanket "everything carries over" sentence with the table above,
> and move `Sturm-PRD.md` to purely historical status. This is a PRD edit,
> not a plan edit — filed as follow-up, not performed here (the plan
> represents the state; the PRD wording change is a separate normative
> action requiring its own review pass).
