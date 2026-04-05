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
