# Sturm v2 — Greenfield Implementation Plan

**Status: ACTIVE.** Written 2026-07-10 against `Sturm-PRD-v2.md` as
revised by review round 6 (all D1–D13 ruled; D6/D7/D14 open). This is
the build order, the test map, and the risk ledger for the from-zero
implementation under epic `Sturm.jl-u0xw`.

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
4. **The PRD's examples compile, forever.** `test/test_prd_examples.jl`
   (prototyped in review r6; bead `hn90`) Meta.parses AND Meta.lowers
   every fenced Julia block in the PRD with stub macros — lowering is
   essential, B1 was a lowering error — and executes §7 under
   EagerContext as the surface grows. It ships in milestone 0.
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
   and Bennett.jl (bridge); `Test` in extras. This is a hard budget.
8. **Namespace = layering.** Surface constructs are `export`ed; kernel
   API (`U2`, `Perm`, `ctrl`, `view`, constants) is `public` —
   reachable as `Sturm.ctrl`, absent from `using Sturm`. The §2 layer
   table becomes mechanically enforced.
9. **Worklog + beads discipline** as ever (rule 0; `bd` for all
   tracking). Each milestone below maps to one bead (listed in §5).

---

## 2. Milestone graph

```
M0 scaffold ─→ M1 kernel ─→ M2 FFI+contexts ─→ M3 casts+Choi harness
                                   │                    │
                                   └────────→ M4 views+dual+actions ─→ teleport ✓
                                                        │
                                              M5 when (streaming) ─→ deferred teleport ✓
                                                        │
                                              M6 QInt+arithmetic worlds
                                                        │
                                              M7 Bennett bridge ─→ DJ ✓, BV ✓
                                                        │
                                              M8 Tracing+DAG+cases+passes
                                                        │
                                              M9 QMod-thin + injection ✓ + Shor ✓
                                                        │
                                              M10 library HOFs ─→ Grover ✓
                                                        │
                                              M11 noise/Stinespring/QECC scaffold
                                                        │
                                              M12+ horizon (hardware, QMod/D6, CV,
                                                    QSVT, Sextant viz)
```

Worked examples are the acceptance gates: each lands in the earliest
milestone whose vocabulary suffices, as a Choi-level pipeline test.

---

## 3. Milestones

### M0 — Scaffold (beads `23o1` + `hn90`) — no quantum code

- **Files:** `Project.toml` (julia = "1.11"; `[compat]` pinned; no
  deps; Test in extras), `src/Sturm.jl` (module, empty exports,
  `public` stanza), `test/runtests.jl`.
- **Boot lints, both wired into runtests:** (a) physics-cite lint —
  grep `src/` for `docs/physics/….md` references, assert each
  resolves; (b) PRD doctest lint — parse+lower every fenced block of
  `Sturm-PRD-v2.md` with stub `@cases`/`@context` macros (the r6
  prototype, hardened into a testset).
- **Exit:** `Pkg.test()` green on 1.11 and 1.12.
- 3+1: no. Distillations: none. Quarry: none.

### M1 — Kernel process values and the algebra (bead `c52g` + successors) — pure Julia, no Orkan

- **Files:** `src/kernel/u2.jl`, `src/kernel/perm.jl`,
  `src/kernel/ctrl.jl`, `src/kernel/algebra.jl` (`∘`, `⊗`, `adjoint`),
  `src/kernel/constants.jl` (X, Z, H, S, T, Ry(θ), Rz(θ) as `U2`
  values — `public`, never exported).
- **U2:** immutable 5-float struct (unit quaternion + phase); Hamilton
  product (16 mul); single-scalar renormalization (policy: renormalize
  when |‖q‖²−1| > 2⁻⁴⁰, cadence tested); `denoted_matrix(u)::SMatrix`-
  style 2×2 for tests and Ad; **equality mod the double cover** —
  canonicalize (first nonzero quaternion component positive, φ folded
  mod 2π) and compare with atol; the quotient must keep **+I ≠ −I**.
- **Perm:** representation decision for the 3+1 round — proposal
  baseline: stored reversible instruction list (X/CX/CCX over wire
  indices) + wire count; `ctrl(::Perm)::Perm` (prepend control to every
  instruction — closure is a one-liner and a named test);
  `adjoint(::Perm)` = reversed inverse list.
- **ctrl:** the single choke point. Representation: `Ctrl{V}` lazy
  wrapper carrying control count + inner value, itself a process value
  (`ctrl(ctrl(g))` wraps again); **total** on U2, Perm, and (from M8)
  UnitaryDAG; nothing else in the codebase may ever construct a
  controlled lowering (grep-lint in CI: `orkan_cx|controlled` appears
  only under `src/kernel/` + `src/orkan/`).
- **Named law tests** (all quotient-equality/≈, against dense matrices
  built *in tests only*): `Ry(a)∘Ry(b) ≈ Ry(a+b)`; `H∘H == I` (and it
  FAILS under naive tuple equality — regression-test the equality
  predicate itself); `Ry(2π) == −I ≠ I`; X/Z/H exact elements;
  `ctrl(g∘h) == ctrl(g)∘ctrl(h)`; `adjoint(ctrl(g)) ==
  ctrl(adjoint(g))`; `ctrl` distinguishes `g` from `e^{iα}g`;
  reassociation `(1⊗V)∘ctrl(W)∘(1⊗V†) == ctrl(V∘W∘V†)`;
  `ctrl(Perm) isa Perm`.
- 3+1: **YES** (kernel). Distillations first: Tang–Wright 2508.00055;
  Control-as-a-Constructor 2508.21756; Wharton–Koch 1411.4999; cf.
  Stuelpnagel 1964. Quarry: none — deriving this from v0.1 `gates.jl`
  would import the SU(2) heresy.

### M2 — Orkan FFI + contexts + regions

- **Files:** `src/orkan/ffi.jl`, `src/orkan/state.jl`;
  `src/context/abstract.jl`, `eager.jl`, `density.jl` (minimal),
  `regions.jl`.
- **FFI:** every `ccall` wrapped with error checking; handles owned by
  the context, freed in deterministic cleanup; **resolve D7 here** —
  read the *current* Orkan headers (the headers are the truth), and if
  both a general-1q entry and rz/ry/rz exist, measure both; the ZYZ
  θ≈0/π singularity branch is written at this boundary and nowhere
  else. Ad application: U2 → Orkan (phase dropped HERE only, uncontrolled
  path); `Ctrl{U2}` → controlled decomposition; Perm → replay.
- **Regions (§3.9):** `@context` built on `Base.ScopedValues.with`;
  `region() do … end`; per-region owned set; single-sourced consumed
  set on the context; scope-exit trace (Eager lowering:
  measure-and-discard; DM: exact ptrace); `ptrace!`; reset-on-recycle
  (fresh = canonical state invariant); strict mode scaffold (parent-
  edge tracking for the lost-binding detector — the detector itself
  can land with M6 when fresh-output ops exist).
- **Tests:** apply/measure round-trips vs dense reference (1–3 wires);
  ScopedValue context propagation incl. into `Threads.@spawn` child;
  region exit traces owned-only; trace-timing invariance (statistics
  equal whether helper inherits region or uses `region()`); seeded
  tests never assert trace placement (policy test).
- 3+1: **YES** (context interface + FFI). Quarry: v0.1
  `src/orkan/ffi.jl` for ccall *names/shapes* — verify every signature
  against the live headers, trust nothing else; v0.1 `abstract.jl`'s
  finalizer-rejection comment (sv3) is prior art for the region design.

### M3 — QBool, casts, linearity, and the Choi harness

- **Files:** `src/types/wire.jl` (WireID + the typed wire-handle
  wrapper — shared with D2's `x[i]` design), `src/types/qbool.jl`,
  `src/surface/casts.jl`; `test/choi.jl` (harness).
- **D1 literal:** `QBool(p::Real, φ::Real = 0.0)`; DomainError outside
  [0,1] (never widen to Complex); `QBool(::Bool)` dispatch test;
  `Float64(φ)` before the ccall; pole-degeneracy tests
  `QBool(1, φ) == QBool(true)`; `plus()`, `minus()`, `magic_T()`.
- **Consuming casts:** `Bool(q)` consumes (single-sourced set);
  implicit-cast warning (P2); use-after-consume errors with register
  identity in the message.
- **The Choi harness** (the test discipline's backbone):
  `choi(f, nin)` on the DM context — DM executes *channels*
  (instrument semantics), so Choi is deterministic in one run; 2W-wire
  cost noted (cap: 15-wire channels).
- **Named law tests:** `Bool(QBool(b)) == b`; Choi(cq∘qc) == the
  pinching Choi — probed on a **coherent** input; error taxonomy test
  (S13 policy: DomainError/ArgumentError/error(), no custom hierarchy).
- 3+1: **YES** (types + casts). Quarry: none.

### M4 — Views, `dual`, the action family — and teleportation

- **Files:** `src/kernel/views.jl` (`view(V, q)` mechanism, DualView,
  dispatch-time unwrap `dual(v::DualView) = v.parent`),
  `src/surface/dual.jl`, `src/surface/actions.jl` (`not!`, `Base.xor`
  family with the registered mutation convention, mixed forms lowering
  to exact X).
- **Semantics:** ops through a view lower by conjugation (direction
  fixed once per register type, pinned by the Pontryagin tests);
  measurement through a view = conjugated instrument (`Bool(dual(q))`);
  translation-family ops on *bound views* mutate-and-return-self
  (`q̂ ⊻= r` = CZ); **views are not numeric** — no ring ops, no P9.
- **Aliasing/identity:** bookkeeping keys on (parent wire, transform);
  Sturm-owned `mightalias`-shaped hook; `dual(q) === dual(q)` is false
  but `dual(dual(q)) === q` (both tested).
- **Named tests:** X↔Z swap (`not!` vs `not!(dual)` Chois); CZ
  symmetry `q̂ ⊻= r ≡ r̂ ⊻= q` at Choi level; views-unwrap-processes-
  compose (no F ever *applied* by unwrapping — the integer-negation
  signature test arrives with M6's QInt); **teleportation §7.1** —
  `Choi(teleport) ≈ Choi(id)` probed on |i⟩ and |+⟩ (the wm28
  regression, killed forever); X-outcome labeling pinned (|+⟩ ↦ false).
- 3+1: **YES** (views are kernel machinery). Distillations first:
  Qwerty 2404.12603 + ASDF 2501.13262 (the view-vs-synthesis
  differentiator, worded per r6).
- Quarry: **none.** (v0.1 has no views; nearest v0.1 code is `H!` —
  heresy.)

### M5 — `when`: streaming ctrl with guardrails (D13)

- **Files:** `src/surface/when.jl`; control stack in contexts.
- **Streaming semantics:** apply `ctrl(op)` op-by-op (licensed by the
  homomorphism law); guardrails as *runtime laws* on Eager/DM: any
  cast/`ptrace!`/`cases`/noise under nonzero control stack is a loud
  error (**the §8.1 regression test — most dangerous v0.1 hole,
  closed by construction**); per-op aliasing check that resolves views
  to parents (`when(q) do not!(dual(q)) end` errors); alloc-inside-
  `when` = clean-ancilla pattern — dealloc asserts |1⟩-block norm 0.
- **`when(dual(q))`:** conjugated control wire; the guardrail-2 check
  still sees q.
- **Named tests:** nested `when` = Toffoli-grade (vs dense reference);
  kickback (control is input *and* output); anti-control sandwich;
  clean-ancilla soundness incl. superposed and entangled controls;
  cast-under-control loud error; **deferred teleport §7.1b** — same
  Choi as §7.1, fully portable (streaming≡materialized cross-check
  completes in M8 when Tracing exists).
- 3+1: **YES.** Distillations first (the §3.5 lore, five papers):
  Bădescu–Panangaden 1511.01567; Gavorová 2011.10031 (Lemma 1 wording);
  Araújo 1309.7976; Yuan–Villanyi–Carbin 2304.15000; Ying–Yu–Feng
  1402.5172.
- Quarry: v0.1 `when.jl`/`multi_control.jl` **only as a defect
  exhibit** — the ABC decomposition self-selecting against the control
  stack is the §1.1 heresy; v2's controlled lowerings come from
  `ctrl`-value decomposition in the kernel, never from a surface path.

### M6 — `QInt{W}`, wire handles, and the two arithmetic worlds (D12)

- **Files:** `src/types/qint.jl`, `src/surface/arithmetic.jl`,
  Fourier lowering in `src/kernel/` (F_G supplied by the register
  type).
- **D2 mechanics:** `x[i]` returns the typed wire handle (borrow,
  aliasing hook, no fresh consumed flags — §8.5 regression);
  `dual(x[i])` legal (ℤ₂ dual of the slice); `dual(x)[i]` defined-to-
  throw descriptive ArgumentError; partial-consumption: `Int(x)` after
  a consumed slice errors loudly.
- **Action world:** `add!(x, ±a)` (Draper lowering: F† ∘ phases ∘ F —
  the 100 lines die in the kernel), `x ⊻= y` transversal, quantum-
  addend `add!(y, x)` (controlled phases); modulation `x̂ += a` and
  controlled modulation `ŷ += x` through views.
- **Value world:** `x + a` / `x + y` fresh-output (copy-then-add!
  lowering); P8 promotion; comparison deferred to M7 (comparator =
  oracle territory). Strict-mode lost-binding detector completes here
  (fresh-output ops now exist to track).
- **Named tests:** BOTH sign pins — `add!(x, 1)` on |0⟩ ⇒ `Int(x)==1`;
  Pontryagin unit test `superpose!; x̂ += a; Int(dual(x)) == a`;
  **F² = parity as a process vs views-unwrap** — `dual(dual(x))` is
  identity while applying F twice negates (the normative
  integer-negation signature test); value-world `s = x + a` leaves x
  live; `x += a` rebind flagged by strict mode, silent by default.
  `superpose!` and `Int(dual(x))` land here (QFT emission).
- 3+1: **YES** (types). Distillations first: Chen–Stoudenmire–White
  2210.08468 (with the r6-corrected reading: cite for
  not-a-tensor-product / small core entanglement).
- Quarry: v0.1 `add_qft!` only to *count the lines that die*; the
  Draper phase schedule is re-derived from F†D_aF = T_a (verified in
  r6), not copied.

### M7 — Bennett bridge: `oracle`, kickback, DJ and BV

- **Files:** `src/bennett/bridge.jl`.
- **Pre-step (research bead):** audit Bennett.jl's current API against
  v2 needs — it was built against v0.1; the bridge contract (Perm
  artifact shape, strategy kwargs, cache keying) must be re-confirmed,
  and **D14 (the BennettVM execution contract) needs Tobias's
  paragraph before this milestone hardens.**
- **Semantics:** `oracle(f, x)` returns the opaque query value;
  `b ⊻= oracle(f, x)` applies the Perm target-accumulatingly (D9);
  `x` stays live; **strategy selection is control-aware — MBU excluded
  under nonzero control stack / traced `when` bodies** (named test:
  `when(c) do b ⊻= oracle(f, x) end` never selects MBU; §3.4).
- **Named tests:** kickback = ordinary surface code — **DJ §7.4**
  (one query, exact) and **BV §7.5** (per-wire duals; and the negative
  control: register-dual readout does NOT recover s — the D2
  copy-paste bug, pinned as a test).
- 3+1: **YES** (FFI-adjacent bridge). Quarry: v0.1 `bridge.jl` —
  D9's gate-level verification already vetted its accumulate idiom;
  reuse the *interface shape*, re-derive the semantics.

### M8 — TracingContext, UnitaryDAG, tokens, `cases`, passes

- **Files:** `src/context/tracing.jl`, `src/channel/` (Channel DAG
  with **unitarity witness**; nodes carry process values, not gate
  names), `src/surface/cases.jl`, `src/passes/`.
- **D3 mechanics:** `Bool(q)`/`Int(x)` under Tracing return
  `ClassicalBit`/`ClassicalInt` tokens; `if token` errors toward
  `cases`; measure → traced classical computation → parameterized
  circuit blessed (width-scalable, no 2^W tables).
- **`when` under Tracing:** materialize body to UnitaryDAG + witness;
  **streaming ≡ materialized Choi law test** (closes M5's IOU).
- **Passes** (unitary-block discipline, measurement barriers —
  carried): reassociation (narrows control scope — subsumes v0.1's
  three hand-rolled sites), view-fusion (F†F cancellation; Eager twin:
  per-wire picture tag), 1q quaternion fusion (subsumes gate_cancel
  for rotations), deferred measurement. `within(V) do … end` lands.
- **DM `cases`:** exact instrument semantics (per-branch ancilla trace
  to common signature, then block-accumulate) — Choi through `cases`
  is one-run deterministic.
- 3+1: **YES** (IR is kernel). Distillations first: Fu et al.
  2204.13041; qrisp/Jasp docs (D3 precedent note).
- Quarry: v0.1 `channel/` + `passes/` for the DAG plumbing shapes
  (isbits node layout, barrier discipline — both sound ideas), with
  skepticism: v0.1 nodes encode Ry/Rz/CX names — v2 nodes carry
  process values; do not import the node vocabulary.

### M9 — Capstones: QMod-thin, the injection ladder, order finding

- **QMod{N} thin:** value embedding in ⌈log₂N⌉ wires; `mulmod!(y, c)`
  = Bennett-compiled `v -> (c*v) % N` Perm (gcd(c,N)=1 ⇒ bijective ⇒
  action world) — QMod arithmetic rides M7, no hand-rolled Beauregard
  yet (that returns with QSVT-era work if profiling demands it).
- **Universality writeup** (§3.7 proof obligation) in `docs/physics/`
  with RBB/ZLC/Gottesman–Chuang/Bravyi–Kitaev distillations (roles per
  r6: injection circuit = GC/ZLC; BK = distillation).
- **Worked examples land:** `inject_S!`/`inject_T!` §7.6 (channel
  test: Choi ≈ S/T on random probes, both outcomes exercised; the
  non-Pauli S-correction path tested explicitly); `shor_order` §7.7
  end-to-end for small N (15, 21) with seeded statistics.
- **The §8 ledger closes:** all eight defect classes have named green
  regression tests by end of M9 (8.1→M5, 8.3→M4, 8.4→M2/M4, 8.5→M6,
  8.6→API-shape review, 8.7→M1 totality, 8.8→M4; 8.2 died with the
  surface).
- 3+1: no (composition of existing core). Distillations: the four
  universality papers.

### M10 — Library HOFs

- `amplify`/`find` (Grover: nested `when` + `not!(dual(·))` for the
  multi-controlled Z — *exact*, no Toffoli-cascade folklore; diffusion
  = H^⊗n materialization via kernel value, the D4 answer), Grover
  pipeline test; `phase_estimate` (controlled modulation +
  `Int(dual)`); `evolve!` (Trotter first; the QSVT pipeline is
  M12-horizon and returns through the reimport gates with its
  `docs/physics/` distillations); `interfere!`; `within` public.
- Quarry: the D5 port notes (worklog session-92) sketch the exact
  per-function shrinkage — use them as the spec; the v0.1 function
  bodies only as line-count exhibits.

### M11 — Noise, Stinespring fallback, QECC scaffold

- Kraus channel values applied through the same surface; pure-context
  policy: loud error (default) or Stinespring dilation fallback
  (allocate environment, apply dilated value, `ptrace!`);
  `classicalise`; `encode(ch, code)` HOF skeleton. Steane re-derivation
  is its own later epic (reimport gates, Choi-level encode∘decode
  tests).

### M12+ — Horizon (not planned in detail here)

Hardware transport (carried design), QMod{d} conjugate structures
(D6 — the d mod 4 Gauss-sum and odd/even-d traps are research-gated),
CV/anyons (P7 arms), QSVT/block-encoding reimport, OpenQASM export,
Sextant visualization hooks.

---

## 4. Cross-cutting workstreams

- **Test harness:** `choi(f, n)` (DM, exact, one-run); Eager-vs-DM
  statistical agreement (N ≥ 1000, ±3σ policy); seeded tests never
  assert trace placement or RNG-stream identity across lowering
  changes; every PRD "required test" gets a `@testset` named after its
  PRD section (grep-able coverage map).
- **Numerics policy:** U2 canonicalization + atol constants in one
  file (`kernel/numerics.jl`), documented against §4.1; renorm cadence
  benchmarked once.
- **Performance:** per-wire 1q fusion buffer in Eager (flush at
  entangling/measure/barrier — quaternion products before any Orkan
  call); per-wire picture tag for view fusion; context passed through
  kernel call chains (ScopedValue read once per surface entry).
  `@code_warntype` gate on: apply path, xor path, cast path.
- **Error policy (S13):** DomainError (chart violations), ArgumentError
  (well-formed-but-forbidden, D2-style, with the suggestion in the
  message), `error()` with register identities for guardrails. No
  custom exception hierarchy.
- **Docs:** every non-trivial function cites its distillation;
  `dual`'s docstring carries the two parser traps (call-LHS op-assign;
  `dual(x) = y` local-method shadowing) and the JuliaLang#20978
  cautionary tale.

## 5. Bead map (filed/updated at plan commit)

| Milestone | Bead | Status |
|---|---|---|
| epic | `u0xw` | open (umbrella) |
| M0 | `23o1` + `hn90` | open — 23o1 gains the PRD-lint deliverable |
| M1 | `c52g` (U2) + new: Perm/ctrl/algebra+laws | c52g updated with r6 equality spec |
| M2 | new: FFI + contexts + regions | |
| M3 | new: QBool + casts + Choi harness | |
| M4 | new: views + dual + action family + teleport | |
| M5 | new: when streaming + guardrails | |
| M6 | new: QInt + arithmetic worlds | |
| M7 | new: Bennett audit (research) → bridge + DJ/BV | |
| M8 | new: Tracing + DAG + cases + passes | |
| M9 | new: capstones + §8 ledger closure | |
| M10 | new: library HOFs | |
| M11 | new: noise + QECC scaffold | |

Dependency chain is linear through M5, then M6→M7→M8→M9→M10→M11; M8
can start in parallel with M7 if staffing allows (no shared files).

## 6. Risk register

1. **Bennett.jl v2-compatibility** (M7): built against v0.1; audit
   bead runs *before* bridge work; **D14 (BennettVM contract) needs
   Tobias** — one normative paragraph, requested.
2. **Orkan ABI drift** (M2): v0.1 ccall shapes may be stale — the
   current headers are the only truth; D7 (ccall shape) resolved by
   measurement at M2.
3. **D6 (QMod{d} duals):** research-gated; two verified traps (Gauss
   sum d mod 4; 2⁻¹ mod d parity) mean the general-d `dual` does NOT
   ship until the distillations exist. QMod-thin (M9) deliberately
   avoids it (no `dual(::QMod)` yet).
4. **Choi cap:** 15-wire channels max under the 30-qubit Orkan cap —
   fine for laws; capstone statistics use sampling, not Choi.
5. **Concurrency:** v2 assumption "one region, one task" is stated,
   not enforced beyond ScopedValue correctness — revisit when a real
   parallel story is designed.
6. **Ergonomics regressions:** any new surface form must pass the two
   slogans (§2) AND the parser (rule 4 of §1 — everything normative is
   doctest-linted; nothing enters the PRD as prose-only code again).
