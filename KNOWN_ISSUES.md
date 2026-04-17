# Known Issues

Terse register of smells and constraints that don't warrant a bead yet. Keep entries one line, no dates (git blame has those).

## Architectural constraints (deliberate)

- **Noise channels bypass the DAG IR.** `depolarise!`, `dephase!`, `amplitude_damp!` build Kraus matrices and call Orkan's superoperator ABI directly — they do not emit DAG nodes. A traced `Channel` cannot contain noise; OpenQASM export has no representation for it. Consequence: noise lives at simulation time, not circuit-compilation time. File header of `src/noise/channels.jl` documents this as the "ABI exception."
- **Classical branching in TracingContext is intermediate-only.** `ClassicalRef.convert(::Type{Bool})` always returns `false`; full classical branching on measurement outcomes is not emitted from user code into `CasesNode`s automatically. `CasesNode` is produced by test fixtures and consumed by `defer_measurements`.
- **`MAX_QUBITS = 30` hard cap in `EagerContext`.** 30 qubits = 16 GiB statevector; 43 qubits would be 128 TiB. Physics wall, not Sturm design. Circuit recycling and `oracle()` decomposition are the mitigations.
- **`apply_ccx!` is in `AbstractContext`** despite being a derived gate. Needed for `QInt.&` / `QInt.|` and Bennett's Toffoli output. Convention: primitives plus `apply_ccx!` is the context interface.

## Performance targets from prior sessions

- Session 3 brought DAG to 31 bytes/node (inline `HotNode` isbits union) and gate_cancel to 336 ms on 2000-qubit QFT. Any refactor that widens `HotNode` or breaks its isbits-ness should measure against `benchmarks/bench_qft.jl` and document the regression.
- OMP threads capped to `CPU_THREADS / 4` at load time to prevent oversubscription from nested parallelism.

## Pedagogical / expectation mismatches

- **`H!^2 = -I`**, not `I`. Global phase; the 4 primitives generate SU(2), not U(2). This is correct physics. Inside `when()`, apparent global phases become observable relative phases — use `_cz!()` from `library/patterns.jl` for true CZ.
- **`_oaa_phases_half` in `src/qsvt/circuit.jl` is hardcoded** `[-pi, -pi/2, pi/2]` because the NLFT pipeline cannot self-generate OAA phases (Chebyshev-basis degree doubling collapses for Chebyshev basis vectors). Documented inline.

## Known test gaps (no dedicated bead)

- `passes/` are not cross-validated against simulation output — passes test DAG structure not physical equivalence.
- `library/patterns.jl` covered only superficially by `test_patterns.jl`.
- Noise tests are single-qubit only.
- No test exercises `QDrift` / `Composite` determinism (blocked on the RNG-injection bead).

## Legacy / code that earns its keep by comment only

- `_wires_of` helpers in `src/passes/gate_cancel.jl` (~lines 268-291) are marked "Legacy API" — kept in case compat code needs them. Delete on the next gate_cancel refactor if no callers.
- `bennett-integration-implementation-plan.md` in `docs/` is the one kept Bennett doc (matches current test_bennett_integration.jl). The v01 vision doc and old `docs/PLAN.md` were deleted as stale.

## Non-versioned development constraints

- `Bennett.jl` is a dev-path dependency (`Pkg.develop(path="../Bennett.jl")`), not registered. Fresh clones need to `Pkg.develop` before `Pkg.instantiate` will resolve.
- Orkan shared library path resolution order: `ENV["LIBORKAN_PATH"]` -> sibling-repo build path -> system `"liborkan"`. First hit wins.

## What is NOT in here

- Anything with an active bead — those are tracked there.
- Historical decisions — those live in `WORKLOG.md`.
- Stylistic preferences — those live in `CLAUDE.md`.
