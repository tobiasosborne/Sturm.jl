# Sturm.jl Work Log

Gotchas, learnings, decisions, and surprises. Updated every step.

---

## 2026-04-05 — Session 1: Project bootstrap

### Steps 1.1–1.6 — Project scaffold + Orkan FFI (all complete)
- **Gotcha: `Libdl` is a stdlib but still needs `[deps]` entry** in Project.toml on Julia 1.12. Otherwise `using Libdl` fails at precompile time.
- **Gotcha: Julia `π` is `Irrational`, not `Float64`.** Rotation wrapper signatures must accept `Real`, not `Float64`. Convert via `Float64(theta)` at the `@ccall` boundary.
- **Gotcha: Orkan qubit ordering = LSB.** Qubit 0 is the least significant bit of the basis state index. `|011>` = index 3 means q0=1, q1=1, q2=0. This is standard (same as Qiskit), but must be kept in mind for all multi-qubit tests.
- **Decision: single `ffi.jl` file** for all raw ccall wrappers (state + gates + channels). Used `@eval` loop to generate the 18 gate wrappers from name lists — avoids boilerplate.
- **Decision: `OrkanState` managed handle** uses Julia finalizer for automatic cleanup. The `OrkanStateRaw` is embedded (not heap-allocated separately), so no double-indirection.
- **No `measure()` in Orkan** — confirmed. Sturm.jl implements `probabilities()` and `sample()` in Julia by reading amplitudes from the Orkan state data pointer.
- 44 tests pass: struct sizes, state lifecycle, all gate types, Kraus→superop, managed handle, sampling.

## 2026-04-05 — Session 2: OOM crash recovery + memory safety

### WSL2 OOM crash investigation
- **Root cause: capacity doubling is exponential-on-exponential.** EagerContext doubled capacity (8→16→32 qubits). State memory is 2^n × 16 bytes, so doubling n from 16→32 goes from 1 MB to 64 GB. WSL2 has ~62 GB — OOM.
- **Contributing factor: OpenMP thread oversubscription.** No `OMP_NUM_THREADS` set, so Orkan spawned 64 threads (Threadripper 3970X) on top of Julia's threads.
- **Contributing factor: Orkan calls `exit()` on validation failure** via `GATE_VALIDATE`, killing the whole Julia process with no chance to catch.

### Fixes applied
- **Replaced doubling with additive growth.** `_grow_state!` now adds `GROW_STEP=4` qubits per resize, not 2×. Growth from 8→12→16→20 instead of 8→16→32.
- **Added `MAX_QUBITS=30` hard cap** (16 GB). `error()` with clear message if exceeded.
- **Added memory check before allocation.** Refuses to grow if new state would consume >50% of free RAM.
- **Set `OMP_NUM_THREADS` automatically** to `CPU_THREADS ÷ 4` (16 on this machine) in `__init__()`.
- **Gotcha: `ENV` mutations in top-level module code run at precompile time, not load time.** Must use `__init__()` for runtime side effects like setting environment variables.
- **Added `EagerContext` constructor guard** — rejects initial capacity > MAX_QUBITS.
- 8 new tests in `test_memory_safety.jl`. 4668 total tests pass.

### Bug fixes and missing tests
- **Bug: `Base.copy(::OrkanState)` called `new()` outside inner constructor.** Added private `OrkanState(::OrkanStateRaw)` inner constructor. Added copy test.
- **Missing tests added:** T! phase test (H·T·H gives P(1)≈sin²(π/8)), phi+theta deterministic combo (Ry(π/2)·Rz(π)·QBool(0.5) = |0⟩ deterministically — NOT |1⟩ as naively expected; Ry(π/2)|-> = |0⟩), XOR with consumed qubit throws.
- **Gotcha: Ry(π/2)|-> = |0⟩, not |1⟩.** Easy to get wrong by thinking "Ry rotates toward |1⟩". The Bloch sphere rotation direction matters: Ry(+π/2) rotates from -X toward +Z, i.e. |-> → |0⟩.

### Step 4.6: RUS T-gate
- **PRD §8.3 has a physics error.** The `rus_T!` code applies `anc ⊻= target` twice — CX·CX = I, so the ancilla is never entangled with the target. The protocol becomes a random phase walk, not a T gate. Verified numerically: P(1) ≈ 0.46 vs expected 0.15.
- **Implemented correct `t_inject!` via magic state injection.** Prepare |T⟩ = (|0⟩+e^{iπ/4}|1⟩)/√2 on ancilla, CX(target→anc), measure anc. If anc=1, apply S correction (T²·T†=T). Deterministic — always succeeds in 1 shot. Verified: matches direct T! to within statistical noise (N=10000).
- Kept PRD version as DSL control-flow demo (tests loop mechanics, dynamic allocation in loops).
- 5079 total tests pass.
