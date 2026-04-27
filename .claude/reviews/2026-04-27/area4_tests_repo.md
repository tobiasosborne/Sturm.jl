# Code Review: Area 4 — Tests, repo organisation, top-level docs

**Reviewer agent:** Sonnet (read-only pass; subagent could not Write to disk; this is the inlined summary)
**Date:** 2026-04-27
**Scope:** `test/` (all 86 files), `Project.toml`, `Manifest.toml`, top-level `README.md` / `CLAUDE.md` / `Sturm-PRD.md` / `KNOWN_ISSUES.md` / `WORKLOG.md`, root-level `probe_*.jl`, `examples/`, `docs/` tree

## Severity Counts

| Severity | Count |
|---|---|
| P0 | 4 |
| P1 | 14 |
| P2 | 8 |
| P3 | 4 |
| **Total** | **30** |

## P0/P1 findings (5 most critical, returned by agent)

### P0-A4.1 — 9 orphaned test files excluded from `runtests.jl`
The default CI run (no env var) skips:
- `test_shor.jl` (Shor impls A/B/C/D — but per agent, E and EH have NO coverage anywhere)
- `test_windowed_arithmetic.jl`
- `test_6xi_coset.jl`
- `test_b3l_runway.jl`
- `test_q84_types.jl`
- `test_qrunway_mid.jl`
- `test_6bn_ekera_hastad.jl`
- `test_p1z_add_qft_quantum.jl`
- `test_bennett_compact.jl` (the diagnostic-counter contract from session 74)

Excluded with no `STURM_FULL_TEST=1` ENV gate — meaning anyone running the test suite gets a false-green for these subsystems. Shor impls E and EH (the ones in production for the `2qp` perf bug investigation), QCoset, QRunway, windowed arithmetic, AND the gate-counter contract have zero default-run coverage.

### P0-A4.2 — `test_bennett_integration.jl` — 3 known-failing tests not marked `@test_broken`
Lines 291, 302, 344 (`@test _CIRCUIT_INC.n_wires <= 30` and `@test r.qubits == 26`) currently fail (wire count is 41, not 26 — confirmed during session 74 regression check). Not marked `@test_broken`, so the suite exits with `Some tests did not pass` and downstream CI rules misclassify the run.

### P0-A4.3 — README claims "10800+ tests"; actual count ~1948
Static `@test\b` count in the 62 runtests.jl-included files is **1,753**. Across all 71 test files (including orphans) it is **1,948**. The README figure does not correspond to any defensible accounting. Either the count is stale by a factor of 6×, or it includes some inflated metric (parametric-test expansions counted as separate?). Either way, README is not source-of-truth.

### P1-A4.1 — Two `docs/physics/` distillations missing
- `docs/physics/nielsen_chuang_5.2.md` — referenced by `src/library/patterns.jl:134` (the `phase_estimate` docstring). §5.1 and §5.3 distillations are present; §5.2 is the critical gap for Shor.
- `docs/physics/vedral_1996_adder.md` — referenced by `src/types/qint.jl:196`.

### P1-A4.2 — 11 `docs/literature/` PDFs absent and policy undocumented
Papers cited as "Local PDF: docs/literature/..." in src docstrings for the simulation, block-encoding, and QSVT pipeline (arXiv:1806.01838 GSLW19, 1912.08854 Childs 2021, 1412.4687 BCKS-PRL15, 2105.02859 Martyn 2021, 2503.03026 Laneve 2025, 2206.06409 Hagan-Wiebe, plus 5 others) are gitignored and absent. The two-tier docs system (committed in `docs/physics/`, gitignored in `docs/literature/`) is not described anywhere — neither in CLAUDE.md Rule 4 nor in README. Cross-references this slice's findings with Area 3, which independently flagged the same pattern.

## Coverage matrix bottom line

- **7 src files with NO default-run coverage** (covered only by excluded files): `shor.jl` (impls E/EH), `coset.jl`, `qrunway.jl`, `qcoset.jl`, `qrunway_mid.jl`, `arithmetic.jl` (windowed path), `eager.jl` (gate counters).
- **11 src files with PARTIAL coverage**: passes (structure-only, no physics cross-validation), shor A–D-semi (preflight/estimate only, no correctness), patterns.jl (missing non-eigenstate phase_estimate), simulation/composite (edge configs), block_encoding/prepare.
- **2 src files with KNOWN-FAILING or VACUOUS tests in the included suite**: `bennett/bridge.jl` (3 silent non-`@test_broken` failures in `test_bennett_integration.jl`) and hardware lifecycle (`@test true` at `test_hardware_lifecycle.jl:101`).
- **~40 src files with solid full coverage**: all of primitives, core DSL, context layer, QSVT pipeline, QECC, noise, hardware abstraction, channel IR, and most of the simulation layer.

## Status

The agent could not write the full per-test-file report to disk due to a permission denial on Write inside the subagent. The summary above represents the most critical findings; the agent's full P2/P3 list (~21 additional items) was not extracted before the agent terminated. Re-running the agent with explicit Write permission would recover them.
