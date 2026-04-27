# Code Review: Area 3 — Library, Algorithms, Simulation, Block-Encoding, QSVT, QECC, Hardware

**Reviewer agent:** Sonnet 4.6 (read-only pass)
**Date:** 2026-04-27
**Scope:** `src/library/`, `src/simulation/`, `src/block_encoding/`, `src/qsvt/`, `src/qecc/`, `src/hardware/`

---

## Executive Summary

The codebase in this slice is architecturally sound and well-motivated. Physics derivations in `simulation/` and `block_encoding/` are the best-documented in the repository. Three recurring problems dominate:

1. **Rule 4 (Physics = Local PDF) is systematically violated** across all of `simulation/`, `block_encoding/`, and `qsvt/` — every physics citation points to `docs/literature/...` paths that do not exist at `docs/physics/`. ~15 files affected.

2. **Rule 11 (4-primitives only) is violated** in three library files with raw `apply_ry!`/`apply_rz!`/`apply_cx!` calls on bare `WireID`s: `coset.jl` (`_coset_init!`, `_runway_init!`), `patterns.jl` (`find` Bennett path), `shor.jl` (`_shor_mulmod_a!`).

3. **QSVT `evolve!(QSVT)` silently fails ~28% of the time** — `oaa_amplify!` returns `false` when post-selection fails and the caller gets the wrong state with no warning.

**Severity counts: P0 = 5, P1 = 7, P2 = 8**

---

## Cross-Cutting Finding 1 (P0): Rule 4 — `docs/literature/` is not `docs/physics/`

Files affected: all of `simulation/`, `block_encoding/`, `qsvt/` (15 files total). Papers missing from `docs/physics/`: Whitfield 2011 (1001.3855), Childs 2021 (1912.08854), Campbell 2019 (qDRIFT), Hagan-Wiebe 2023 (2206.06409), GSLW19 (1806.01838), Shende 2006, Grover-Rudolph 2002, BCKS-PRL15 (1412.4687), Laneve 2025 (2503.03026), Berntson-Sünderhauf 2025, Martyn 2021 (2105.02859).

Only `library/` (Beauregard 2003, Draper 2000, Gidney 2019) and `qecc/` (Steane 1996) are Rule 4 compliant.

**Recommendation:** Copy the 11 missing PDFs into `docs/physics/`, or update CLAUDE.md Rule 4 to formally accept `docs/literature/` paths.

---

## Cross-Cutting Finding 2 (P0): Rule 11 — Raw primitive calls on WireIDs in library code

| File | Function | Call | ~Line |
|------|----------|------|-------|
| `src/library/coset.jl` | `_coset_init!` | `apply_ry!(ctx, pad_anc[p+1], π/2)` | ~74 |
| `src/library/coset.jl` | `_runway_init!` | `apply_ry!(ctx, reg.wires[W+p+1], π/2)` | ~125 |
| `src/library/patterns.jl` | `find(f, T, Val{W})` | `apply_rz!(ctx, output_wires[1], π)` | ~515 |
| `src/library/shor.jl` | `_shor_mulmod_a!` | `apply_cx!(ctx, z_wires[i], y_wires[i])` ×2 | ~363-370 |

Fix pattern: wrap the WireID in `QBool(wire, ctx, false)` then use `.θ +=` / `.φ +=` / `⊻=`.

---

## Per-File Findings

### `src/library/patterns.jl`
- **(P0)** `find` Bennett path: `apply_rz!(ctx, output_wires[1], π)` — Rule 11 violation.
- **(P1)** `docs/physics/nielsen_chuang_5.2.md` cited but file does not exist in the directory (5.1.md and 5.3.md exist).
- **(P2)** Phase kickback in Grover is explained in words but no equation citation.
- Positive: `_cz!` correctly avoids the controlled-Rz(π) = CZ trap (Session 8 bug). `_multi_controlled_z!` is correct. `phase_estimate` correctly uses `ptrace!` on eigenstate.

### `src/library/arithmetic.jl`
- **(P2)** `_apply_ctrls(ctx, ctrls::NTuple{N,...})` matches only N ∈ {0,1,2}. Passing 3+ controls silently hits a MethodError with no guard. Document the limit or extend.
- **(P2)** `modadd!` comment step numbering skips step 9 (matches Beauregard Fig. 5 but the comment jumps 8→10).
- Overall: Best-implemented file in the slice. DSL primitives used throughout. Rule 4 compliant.

### `src/library/coset.jl`
- **(P0)** `_coset_init!` ~line 74: `apply_ry!(ctx, pad_anc[p+1], π/2)` — Rule 11 + P5 violation.
- **(P0)** `_runway_init!` ~line 125: `apply_ry!(ctx, reg.wires[W+p+1], π/2)` — same.
- **(P2)** `coset_add!` does not assert that `N < 2^W` (the modulus constraint from Gidney §4). A malformed call silently produces wrong results.
- Rule 4 compliant (Gidney 2019 arXiv:1905.08488 IS in `docs/physics/`).

### `src/library/shor.jl`
- **(P0)** `_shor_mulmod_a!` ~lines 363-370: 3-CNOT swap via `apply_cx!(ctx, z_wires[i], y_wires[i])` on raw WireIDs — Rule 11 + P5 violation.
- **(P1)** `shor_factor_A` and `shor_factor_B` have identical classical reduction bodies — bead `dxk` confirms, still present. Extract shared `_shor_classical_reduction(N, x, r)` helper.
- **(P1)** No confirmed tests for impl C, D, D-semi. The `apply_cx!` violation in impl C suggests it has not been exercised against a known-correct expected state.
- **(P2)** `rand(2:(N-1))` in both functions is not seeded — add `rng::AbstractRNG = Random.default_rng()` kwarg matching `qdrift.jl` pattern.
- Rule 4 compliant for existing references (N&C §5.3, Beauregard 2003 both in `docs/physics/`).

### `src/simulation/hamiltonian.jl`
- **(P0 — Rule 4)** See Cross-Cutting Finding 1.
- **(P2)** No Hermitian validation in `PauliHamiltonian` constructor. Acceptable for v0.1 but undocumented.

### `src/simulation/pauli_exp.jl`
- **(P0 — Rule 4)** See Cross-Cutting Finding 1.
- **(P2)** `_PAULI_PHASE_TOL = 1e-9` magic constant without a precision derivation comment.
- Positive: File-header ZYZ derivation of Y basis change is excellent. All gate ops use DSL primitives. `_pauli_exp!` control-stack save/clear/restore is correct.

### `src/simulation/trotter.jl`
- **(P0 — Rule 4)** See Cross-Cutting Finding 1.
- **(P2)** `Suzuki{1}()` would dispatch to `Val{0}` and produce a confusing MethodError. Add a constructor guard: `K >= 2 || throw(ArgumentError("use Trotter1 for K=1"))`.
- Positive: `_suzuki_p(K)` coefficient recursion is correct per Suzuki 1991. `Val{K}` dispatch is idiomatic Julia.

### `src/simulation/qdrift.jl`
- **(P0 — Rule 4)** See Cross-Cutting Finding 1.
- **(P1)** No determinism test (KNOWN_ISSUES confirms). Add a seeded-RNG test: same seed → same operator sequence.
- Positive: `AbstractRNG` correctly threaded via `alg.rng`. KNOWN_ISSUES concern resolved.

### `src/simulation/composite.jl`
- **(P0 — Rule 4)** See Cross-Cutting Finding 1.
- **(P1)** `samples_per_step = max(1, alg.qdrift_samples ÷ alg.steps)` silently loses fractional samples. Use `cld(alg.qdrift_samples, alg.steps)` for the first `r` steps (where `r = qdrift_samples % steps`) and `alg.qdrift_samples ÷ alg.steps` for the rest, or emit a `@warn` on uneven division.
- **(P1)** No determinism test (same as qdrift.jl).

### `src/simulation/error_bounds.jl`
- **(P0 — Rule 4)** See Cross-Cutting Finding 1.
- **(P2)** `alpha_comm` is O(n!) in Hamiltonian term count. No `@warn` for large inputs. Acceptable for v0.1 but worth a KNOWN_ISSUES entry.
- Positive: Correctly errors for p≥3 rather than silent fallback.

### `src/simulation/models.jl`
- **(P0 — Rule 4)** See Cross-Cutting Finding 1.
- No other findings. Clean, well-documented. Equation citations (Childs 2021 Eq.(99), Eq.(288)) are specific and correct.

### `src/simulation/evolve.jl`
- No findings. Clean delegation.

### `src/block_encoding/types.jl`
- **(P0 — Rule 4)** GSLW19 PDF not in `docs/physics/`.

### `src/block_encoding/prepare.jl`
- **(P0 — Rule 4)** Shende 2006, Grover-Rudolph 2002 not in `docs/physics/`.
- **(P1)** `_rotation_tree!` does not validate that input coefficients are non-negative. `acos` of a negative ratio silently produces wrong angles. Add `@assert all(c -> c >= 0, coefficients)`.
- Positive: X!-sandwich for conditional-on-|0⟩ is correct and well-commented. DSL primitives used throughout.

### `src/block_encoding/select.jl`
- **(P0 — Rule 4)** BCKS-PRL15 not in `docs/physics/`.
- Positive: Outstanding inline documentation including explicit Session 8 bug discussion. Uses `_pauli_exp!` correctly.

### `src/block_encoding/lcu.jl`
- **(P0 — Rule 4)** GSLW19 not in `docs/physics/`.
- No other findings. Clean GSLW19 construction.

### `src/block_encoding/algebra.jl`
- **(P0 — Rule 4)** GSLW19 not in `docs/physics/`.
- **(P2)** No test for `BlockEncoding * BlockEncoding` on a concrete pair. The ancilla-wire threading in the product is non-trivial.

### `src/qsvt/conventions.jl`
- **(P0 — Rule 4)** Laneve 2025 not in `docs/physics/`.
- DSL primitives used correctly.

### `src/qsvt/polynomials.jl`
- **(P0 — Rule 4)** Martyn 2021, GSLW19 not in `docs/physics/`.
- **(P2)** `chebyshev_eval` uses Clenshaw recurrence without citing Clenshaw 1955.

### `src/qsvt/phase_factors.jl`
- **(P0 — Rule 4)** Laneve 2025, Berntson-Sünderhauf 2025 not in `docs/physics/`.
- **(P1)** `rhw_factorize` uses O(n³) dense `A \ rhs`. Documented inline as temporary but no bead tracking upgrade to O(n log² n) Levinson-Durbin. File a bead.
- **(P1)** `_bs_algorithm1` sample-count heuristic: `max(8*(d+1), Int(ceil((d+1)/max(delta, 1e-6))))`. No overflow guard or clamp for extreme `delta`/`d` combinations. Add an `@assert N < MAX_SAMPLES` guard.
- **(P2)** `REAL_TOL = 1e-12` not derived from a precision analysis of the NLFT pipeline.

### `src/qsvt/circuit.jl`
- **(P0 — Rule 4)** All citations use `docs/literature/...`. See Cross-Cutting Finding 1.
- **(P1)** `evolve!(QSVT)` calls `oaa_amplify!` once and returns regardless of success. With ~28% failure probability, ~1-in-4 calls silently return the pre-amplification state. Add at minimum: `success || @warn "OAA post-selection failed; state is unnormalized"`.
- **(P1)** `_oaa_phases_half` hardcodes phases for degree-3 OAA only. If someone increases the OAA degree, it silently produces wrong phases. Rename to `_oaa_phases_half_deg3` or add an error guard on degree != 3.
- **(P2)** `_lift_combined_to_be` hardcodes `alpha = 2.0` without a comment citing GSLW19 Theorem 58.
- **(P2)** `qsvt_reflect!` uses `if Bool(a)` (correct explicit P2 cast) but lacks a comment explaining this is post-selection, not classical branching.

### `src/qecc/abstract.jl`
- No findings.

### `src/qecc/steane.jl`
- **(P1)** `syndrome_correct!` coherent correction path has no test coverage (KNOWN_ISSUES confirms). Required for P6 compliance (`encode(ch, Steane())`).
- **(P2)** X-stabilizer CNOT direction comment says "evaluate for side effect" — replace with `# CX(physical[i] → anc): physical[i] controls, anc is target, per Steane Eq. (6)`.
- **(P2)** `_when_ancs_equal!` nested `when()` is correct but verbose. Consider Toffoli cascade for consistency with `_multi_controlled_z!` in patterns.jl.
- Rule 4 compliant (`docs/physics/steane_1996.pdf` exists).

### `src/qecc/channel_encode.jl`
- **(P2)** `_emit_transversal!` calls `apply_ry!`/`apply_rz!` directly on WireIDs. This is the DAG-replay infrastructure layer (below the DSL boundary), which is architecturally acceptable. Add a comment explaining why direct context calls are acceptable here.
- **(P2)** `_CLIFFORD_ANGLE_TOL = 1e-10` without a floating-point precision justification.
- **(P2)** v0.1 scope limitations are documented inline but not linked to open beads.

### `src/hardware/hardware_context.jl`
- **(P1)** `_finalize_hardware_context` spawns a task that swallows all errors silently. A GC-triggered flush failure produces no signal. Change `catch` to `catch e; @error "hardware finalizer: $e"`.
- **(P2)** No atomic CAS for the `ctx.closed` double-close guard.

### `src/hardware/transport.jl`
- **(P1)** `TCPTransport` blocks indefinitely on stalled server (no timeout). Document in KNOWN_ISSUES.
- No other findings.

### `src/hardware/protocol.jl`
- **(P1)** `_parse_object!`, `_parse_array!`, `_parse_string!` use `@assert` for input invariants. These are parsing untrusted network input. An `AssertionError` propagates past `catch e isa ProtocolError` in `_handle_connection` and kills the connection task. Replace `@assert _peek(p) == '{'` with `_peek(p) == '{' || throw(ProtocolError("expected '{', got '$(Char(_peek(p)))'"))`.
- **(P2)** Hand-rolled JSON parser is correct but adds ~200 lines of maintenance burden. Consider JSON3.jl.

### `src/hardware/simulator.jl`
- Direct `apply_ry!`/`apply_cx!` calls in `_execute_op!` are architecturally correct at the transport layer (below the DSL boundary). Not a Rule 11 violation.
- **(P2)** `sim.next_session_id += 1` is not thread-safe. Two concurrent `open_session` calls from separate `@async` tasks can produce duplicate session IDs. Use `Threads.Atomic{Int}` + `Threads.atomic_add!`.

### `src/hardware/server.jl`
- **(P1)** `@async` per connection means all connections are cooperative-scheduled on one thread. For CPU-intensive simulator sessions this starves the accept loop. Use `Threads.@spawn` for v0.2.
- **(P2)** Bare `catch` in `_handle_connection` swallows connection errors silently. Add `@debug` logging.

---

## Severity Count Summary

| Severity | Count |
|----------|-------|
| P0 | 5 (Rule 4 ×1 covering 15 files; Rule 11 ×4 distinct sites) |
| P1 | 7 |
| P2 | 8 |

## Recommended Actions (Priority Order)

1. **(P0)** Fix 4 Rule 11 violations: wrap WireIDs in `QBool` before primitive ops in `coset.jl`, `patterns.jl`, `shor.jl`.
2. **(P0)** Resolve `docs/physics/` vs `docs/literature/` — copy 11 missing PDFs or update CLAUDE.md Rule 4.
3. **(P1)** Add `@warn` / retry to `evolve!(QSVT)` for `oaa_amplify!` failure.
4. **(P1)** Add seeded-RNG determinism tests for `QDrift` and `Composite`.
5. **(P1)** File a bead for `rhw_factorize` O(n³) → Levinson-Durbin upgrade.
6. **(P2)** Extract shared classical reduction from `shor_factor_A`/`B` (bead `dxk`).
7. **(P2)** Replace `@assert` with `ProtocolError` throws in protocol.jl parser.
8. **(P2)** Fix composite `samples_per_step` silent truncation.
