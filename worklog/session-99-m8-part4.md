# Session 99 — M8 part 4: Eager tee-tracing, block execution, TR2 poison (bead Sturm.jl-szx1)

Second slice of M8. Slice 1 (commit 9886402) shipped the typed `ChannelDAG`,
`certify`, and `UnitaryBlock{N}` + `ctrl(::UnitaryBlock)`. This slice implements
plan §M8 part 4: closes the ad.jl execution seams, adds Eager tee-tracing with a
structural clean-ancilla seal as the witness, demotes the M5 marginal to a debug
cross-check, and implements the TR2 poison-on-failed-seal failure topology.

Design gate: `docs/design/m8-5hr7-unitary-block-design.md` §1.4, §2.5, §5, §8-TR2.
Reviewed by the orchestrator (this slice is NOT committed by the implementer).

## What shipped

- **ad.jl block execution (design §1.4).** Closed the two fail-loud stubs:
  - `_emit!(ctx, ::UnitaryBlock, qs)` — UNCONTROLLED replay: `AllocN`→fresh |0⟩
    kernel scratch slot, `ApplyN`→`_emit!` the value, `TraceN`→free the certified-
    clean slot (recycled |0⟩, no measurement).
  - `_apply_controlled!(ctx, k, controls, ::UnitaryBlock, targets)` — CONTROLLED
    replay: alloc/trace stay UNCONTROLLED, only `ApplyN`s are control-wrapped (the
    §4.2 control-scope-reassociation law made executable). `ctrl(::UnitaryBlock)`
    now EXECUTES on Eager.
  - Added `_apply_controlled!(…, inner::Ctrl, …)` — ∧_k of an already-controlled
    value flattens to ∧_{k+j}(inner) (Delorme Eq 14). Needed because a block's
    `ApplyN` may hold a `Ctrl` (e.g. `ctrl(Z)` in a `MatchedPair` body).

- **Eager tee-tracing (design §5).** A `WhenFrame` (a `DAGBuilder` + `WireID→PortID`
  map) per live `when` region, on a new `ContextCore.when_frames::Vector{Any}` stack.
  The streaming body ALSO tee-records: `allocate!`→`AllocN`, `_act!`→`ApplyN` (the
  UNCONTROLLED transcript value), region-exit trace→`TraceN`. At body exit
  `_seal_when_frame!` structurally verifies each body-owned scratch ancilla is
  released by a matched compute/uncompute — THE WITNESS (F1: a program property,
  universally quantified over inputs, not a runtime marginal).

- **Demoted marginal (design §2.5).** The M5 `_clean_ancilla_assert!` (|1⟩-marginal)
  is no longer the `when` witness. It survives as `_clean_ancilla_debug!`, gated by
  `DEBUG_CLEAN_ANCILLA[]` (default false) — an independent fail-fast cross-check.
  The marginal methods themselves are UNCHANGED (still the M7-oracle `_free_clean!`
  witness, backed there by Bennett `(★)` PermClean-by-construction).

- **TR2 poison (design §8).** A failed seal sets `ContextCore.poison` and throws;
  `_require_open` (reached by every `_here`) then fails every subsequent surface op
  loud, naming the original seal failure. Streaming runs effects before the late
  seal, so the failure cannot be unwound — poison, not rollback.

## Gotchas / non-obvious decisions (read before touching this)

- **U2 self-adjoint `==` is representation-brittle.** The shipped `certify`
  `_check_matched_pair` compares the compute/uncompute with exact `==`
  (`v₁ == adjoint(v₂)`). That works for `Perm` (exact generator reversal) but FAILS
  for a self-adjoint `U2`: `adjoint(X) = U2(0,-1,0,0,-π/2) ≠ X = U2(0,1,0,0,π/2)` as
  stored fields, even though `X† = X` as an operator (the conjugate flips the vector
  part AND the phase). M5's `not!(a); not!(a)` (X;X) would be wrongly rejected. The
  tee-seal (`_seal_check_scratch`) therefore compares with the kernel's PHASE-
  INCLUSIVE process `≈` plus a same-ports check — NOT a state/Choi/sample, so F1
  still holds. Documented deviation from the shipped `==` check.

- **Pure-scratch `when` bodies are zero-port.** `when(q) do a=QBool(false); not!(a);
  not!(a) end` denotes identity on ZERO external wires. `certify(…)→UnitaryBlock`
  rejects that (TR7 forbids zero-port blocks). So the streaming seal does the
  scratch-cleanliness ANALYSIS directly (reusing `_footprint`/`adjoint`), it does NOT
  wrap the whole body in a `UnitaryBlock`. The `certify→UnitaryBlock` path is what
  the `M8.WHEN.STREAM-MATERIALIZED` law test materializes (via `_when_capture`, which
  returns a block only for external-boundary NoAncilla bodies).

- **Oracle-under-`when` (M7) interlock.** `oracle(f,x)` inside a `when` allocates
  scratch (`allocate!`→`AllocN`), applies its `Perm` (`_act!`→`ApplyN`), and frees
  via `_free_clean!` — NOT the region-exit trace. If `_free_clean!` didn't record a
  matching `TraceN`, the frame's `AllocN`s would be unmatched and the seal would fail,
  breaking M7. Fix: `_free_clean!` records a `TraceN` with a `PermClean` cert (the
  oracle IS Bennett-clean by construction). The seal TRUSTS a `PermClean`-carrying
  trace (skips the writer analysis) — the discriminator between the oracle's clean
  `Perm` and the F1 adversary `a ⊻= r` (also a `Perm`) is the combinator-carried cert,
  never structure.

- **Free-without-measure kept on the seal path.** `_trace_and_free!` under control
  still frees the scratch slot WITHOUT measuring (as before). The seal (after region
  exit) decides cleanliness; a dirty release poisons the context, so the recycled
  dirty slot is never observed. This preserves the M5 no-extra-RNG-draw determinism.
  KNOWN GAP (documented): on the ERROR path (body throws mid-way, seal skipped) a
  dirty scratch could be recycled without poison — but the M5 error-path bodies
  allocate no scratch, and a caught mid-body error already leaves a questionable
  context. Old code masked the body error with the marginal throw; new code surfaces
  the body error.

- **`Ctrl(` token lint.** The `Ctrl(`/`_ctrl(` construction lint greps ALL of src/
  (comments included) and allows those tokens only in `kernel/ctrl.jl`. An ad.jl
  comment `∧_k(Ctrl(j,v))` tripped it — reworded to avoid the `Ctrl(` literal.

## Files

- `src/orkan/ad.jl` — block execution seams + `_apply_controlled!(::Ctrl)`.
- `src/context/abstract.jl` — `when_frames`/`poison` fields; `_require_open` poison
  check; `allocate!` + `_trace_and_free!` tee hooks.
- `src/surface/when.jl` — `WhenFrame`, tee recorders, `_seal_when_frame!`,
  `_seal_check_scratch`, `_poison_seal!`, `_clean_ancilla_debug!`,
  `DEBUG_CLEAN_ANCILLA`, `_when_capture`; `_when_core` push/pop/seal; `_act!` hooks.
- `src/bennett/bridge.jl` — `_free_clean!` records the oracle's `PermClean` trace.
- `test/test_m8_when_materialize.jl` — part-4 law tests (20 tests); wired in runtests.

## `within` — NOT built this slice (correct per §7.10)

§7.10's build order does not place `within` in part 4; it is the combinator form of
`MatchedPair` acquisition, spanning the deferred syntactic verifier work. The
`MatchedPair` cert + checker already shipped in slice 1; the streaming seal reaches
the same clean-ancilla guarantee for `when` bodies structurally. Left as a documented
seam (TR3: when built, `within` is `public` kernel API, not an 8th surface construct,
and gets the deferred MatchedPair compute-field cross-check). Not scope-crept.

## Orchestrator review fixes (post-review deltas)

- **FIX 1 — one matched-pair discipline.** Introduced `_is_adjoint_pair(v1, v2)` in
  `src/channel/cert.jl`, used by BOTH `_check_matched_pair` (certify) and
  `_seal_check_scratch` (streaming seal) — no fork. Two tiers: (A) exact structural
  provenance `v1 == adjoint(v2)` (Perm/`within` — no numerics); (B) phase-inclusive
  `v1 ≈ adjoint(v2)` (float-law, PRD §4.1) for self-adjoint `U2`. Updated cert.jl's
  §2.2 "NEVER isapprox" comment: the prohibition targets runtime OBSERVATION
  (state/Choi/sample), not comparing two program VALUES with the kernel's `≈`. Test:
  `M8.CERT.MATCHED-PAIR-DISCIPLINE` — a `certify(MatchedPair)` with X compute/uncompute
  (which exact `==` rejected pre-fix) now seals; tier A still exact for Perm.

- **FIX 2 — poison on mid-body throw with live scratch.** `_when_core` now wraps the
  body in try/catch; `_when_error_poison!` poisons the context (naming the escaped
  exception) when an error escapes with any un-sealed `AllocN`, then rethrows the
  ORIGINAL error. No scratch ⇒ propagate unpoisoned (M5 `not!(r); error()` unwind
  idiom preserved). Tests: `M8.TR2.MIDBODY-POISON` (scratch ⇒ poisoned, original
  surfaces) and `M8.TR2.MIDBODY-NO-SCRATCH` (no scratch ⇒ usable). A failed SEAL's
  poison message takes precedence over the mid-body message.

Full suite after fixes: `Sturm.jl boot lints | 25398 25398 5m31.4s`, exit 0.

## M5 test changes: NONE

All 40 M5 tests pass UNCHANGED. The dirty-ancilla cases (b)/(d) still throw
`ErrorException` — now via the structural seal + TR2 poison rather than the marginal
assert. No test asserted the |1⟩-marginal as the witness, so no witness-reframing was
needed in the M5 suite.
