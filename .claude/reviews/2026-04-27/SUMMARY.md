# Code Review Summary — 2026-04-27

Four parallel review agents (Sonnet 4.6) covered the Sturm.jl codebase across non-overlapping slices. Each was instructed to apply five focuses (Julia/Sturm idiomaticity, code quality, code smells, test coverage, repo tidiness). Reports for each area are in this directory.

## Total findings

| Area | Slice | P0 | P1 | P2 | P3 | Total |
|---|---|---|---|---|---|---|
| Area 1 | core types, context, control, gates | 3 | 11 | 18 | 5 | 37 |
| Area 2 | IR / passes / Bennett bridge / noise | 4 | 9 | 14 | 4 | 31 |
| Area 3 | library / simulation / QSVT / QECC / hardware | 5 | 7 | 8 | 0 | 20 |
| Area 4 | tests, repo organisation, top-level docs | 4 | 14 | 8 | 4 | 30 |
| **Total** | | **16** | **41** | **48** | **13** | **118** |

## Headline P0 findings (verified by orchestrator)

1. **Bennett `NOTGate → apply_ry!(ctx, t, π)`** at `src/bennett/bridge.jl:81` — `Ry(π) = −iY`, not X. Inside `when(ctrl)` becomes controlled-Ry(π), wrong relative phase between branches. Session 8 bug applied to every controlled oracle. Same pattern at `src/passes/deferred_measurement.jl:51,55` for the false-branch X in `defer_measurements`. Both confirmed by direct grep.

2. **`pointer(data)` without `GC.@preserve`** in `src/noise/channels.jl` `_apply_kraus!` — dangling pointer race between Julia GC and Orkan ccall. Zero `GC.@preserve` calls in the entire codebase (verified).

3. **`orkan_channel_1q!` missing `_check_qubit`** at `src/orkan/ffi.jl:247` — every other gate wrapper guards; this one doesn't. OOB index SIGABRTs Julia. Confirmed by direct grep.

4. **`classical_type(::Type{<:QInt}) = Int8`** for all widths at `src/types/qint.jl:20` — silent truncation for any path not using `_bennett_arg_type(W)`. Same in `QCoset`. Confirmed.

5. **`_wire_counter` non-atomic** at `src/types/wire.jl:19` — race under threading produces colliding `WireID`s. Confirmed.

6. **`measure!` MIXED_PACKED upper-triangle write** in `src/context/density.jl` — corrupts post-measurement density matrix. Plus the same per-element FFI hot loop already fixed for `EagerContext` in bead `059` (still present in DM context).

7. **`_cases_dispatch(::TracingContext)` lacks try/finally** in `src/control/cases.jl` — exception during branch leaves `ctx.dag` in a partial state, permanent corruption.

8. **Rule 4 (Physics = local PDF) violated by `docs/literature/` paths** — 15 files in `simulation/`, `block_encoding/`, `qsvt/` cite `docs/literature/...` paths that don't exist (gitignored?). 11 PDFs missing. Two `docs/physics/.md` distillations missing (5.2 N&C, Vedral 1996).

9. **Rule 11 (4-primitives only) violated** — raw `apply_ry!`/`apply_rz!`/`apply_cx!` on bare WireIDs at: `src/library/coset.jl` `_coset_init!` ~line 74 and `_runway_init!` ~line 125; `src/library/patterns.jl` `find` Bennett path ~line 515; `src/library/shor.jl` `_shor_mulmod_a!` ~lines 363-370.

10. **9 orphaned test files excluded from `runtests.jl`** — Shor impls E/EH, QCoset, QRunway, windowed arithmetic, and the 2qp gate-counter contract have zero default-CI coverage.

11. **`test_bennett_integration.jl` 3 known-failing tests not `@test_broken`** — suite silently red.

12. **README "10800+ tests" overstated by ~6×** — actual count ~1948 across all files, ~1753 in default-run.

## Cross-cutting themes

- **Global-phase confusion at the Sturm↔Bennett boundary.** P0-A2.1 and P0-A2.3 are the same conceptual error: using `Ry(π)` as a substitute for `X` in code that runs inside `when()`. Both have been documented as the Session 8 bug; the codebase has explicit warnings about this in CLAUDE.md but the bug pattern keeps reappearing where `Ry(π) = -iY` is treated as a textbook X. Should be tagged in every relevant docstring + linter check.

- **FFI memory-safety hygiene is uneven.** Some ccalls have validators, some don't (P0-A2.4). Some pass raw pointers without `GC.@preserve` (P0-A2.2). The whole codebase has zero `GC.@preserve` — concerning given the pattern.

- **Caches are unbounded.** `_QROM_LOOKUP_XOR_CACHE`, `QuantumOracle.cache`. Bead `t1v` already fixed `_ORACLE_TABLE_CACHE`; the sibling caches missed the same treatment.

- **Test coverage misrepresented.** `runtests.jl` excludes 9 important files; README inflates count by 6×. Two distinct accuracy problems with the same root: nobody is auditing the test surface against the public API.

- **Docs split between `docs/physics/` (committed) and `docs/literature/` (apparently gitignored).** Whichever the policy is, it's undocumented. CLAUDE.md says `docs/physics/` is the only valid path; 15 src files cite `docs/literature/`.

## Fileable beads

P0s and P1s map to ~30 distinct underlying issues (some P0s span multiple files, e.g. Rule 4 covers 15 files but is one cross-cutting bead). Filing plan:

- **One bead per distinct P0 root cause** (~10 beads).
- **One bead per major P1 architectural smell** (~10 beads).
- **Sweep beads** (one per area) to cover the remaining P2/P3 nits cleanly.
