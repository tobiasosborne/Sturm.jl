# Sturm.jl — Quantum Programming DSL

## What This Is

A Julia quantum programming language where functions are channels, the quantum-classical boundary is a type boundary, and QECC is a higher-order function.

Full PRD: `Sturm-PRD.md`.

**Backend: Orkan from day 1.** The EagerContext delegates to `../orkan/` (C17 statevector + density matrix simulator with OpenMP) via `ccall`. No pure-Julia simulator — Orkan IS the simulation engine. Julia owns the type system, DSL, compilation, and channel algebra. Orkan owns the linear algebra.

## Implementation Principles

These are NON-NEGOTIABLE. Every agent, every session, every commit.

0. **MAINTAIN THE WORKLOG.** Every step, every session: update `WORKLOG.md` with gotchas, learnings, surprising decisions, ABI mismatches, test failures and their root causes, anything a future agent would wish it knew. This is the project's institutional memory. If you hit something non-obvious, write it down before moving on.

1. **FAIL FAST, FAIL LOUD.** Assertions, not silent returns. Crashes, not corrupted state. `error()` with a clear message, not a quiet `nothing`. Get errors in front of eyeballs immediately.

2. **CORE CHANGES REQUIRE 3+1 AGENTS.** Any change to core types (`types/`), context interface (`context/abstract.jl`), primitives (`primitives/`), or the Orkan FFI layer requires: 2 proposer subagents (independent designs), 1 implementer. The orchestrating agent is the reviewer (+1). Proposers must not see each other's output. The implementer picks the better design (or synthesises). The orchestrator reviews for PRD conformance, idiomatic DSL usage, and test coverage before accepting.

3. **GROUND = PHYSICS.** Every quantum operation, every gate decomposition, every channel identity must be grounded in physics. Not pinned numbers. Not "it works on the test case." The physics must be right. If you derive a gate from the four primitives, prove it on paper first.

4. **PHYSICS = LOCAL PDF + EQUATION.** "Grounded in physics" means: a local PDF copy of the paper lives in `docs/physics/`, and the implementation references an explicit equation from that paper. No "based on Nielsen & Chuang" without the actual equation number.

5. **LITERATE CODING.** Every non-trivial function has a docstring explaining WHAT it does, WHY it exists, and WHICH equation/paper it implements. Comments explain intent, not mechanics. Julia docstrings use `"""..."""` above the function.

6. **BUGS ARE DEEP AND INTERLOCKED.** Never assume a bug is shallow. Investigate root causes. Quantum bugs are especially treacherous: a sign error in a phase rotation is invisible until entanglement amplifies it.

7. **GET FEEDBACK FAST.** Run `julia --project -e 'using Sturm; ...'` or the test suite after every non-trivial change. Don't code blind for 500 lines then check. Check every 50 lines.

8. **RESEARCH STEPS ARE EXPLICIT.** If you don't know what a step involves, mark it as a research step. Don't guess. Don't hallucinate an implementation. Research it properly.

9. **SKEPTICISM.** Be skeptical of everything: subagent output, previous agent work, your own assumptions, library documentation. Verify. Test. Reproduce.

10. **TEST-DRIVEN DEVELOPMENT.** Write the test first. Then write the code to make it pass. Tests live in `test/`. Every PR needs tests. Use `@testset` and `@test`. Statistical tests (measurement outcomes) use N>=1000 samples with tolerance.

11. **IDIOMATIC DSL — 4 PRIMITIVES ONLY.** All quantum code must be written using the four primitives. No imported gate matrices, no raw unitary arrays applied directly. The four primitives are:

    | # | Syntax | Semantics | QASM |
    |---|--------|-----------|------|
    | 1 | `QBool(p::Real)` | Preparation: Ry(2 arcsin sqrt(p))\|0> | `ry(2*arcsin(sqrt(p))) q` |
    | 2 | `q.theta += delta` | Amplitude rotation: Ry(delta) | `ry(delta) q` |
    | 3 | `q.phi += delta` | Phase rotation: Rz(delta) | `rz(delta) q` |
    | 4 | `a xor= b` | CNOT: b controls, a target | `cx b, a` |

    Every gate in `src/gates.jl` is built from these. Every new algorithm must do the same. A subagent that constructs a gate from a raw matrix is WRONG.

12. **FULL PIPELINE TESTS WITH VERIFICATION.** Every quantum algorithm must have end-to-end tests: construct circuit via DSL primitives -> execute on EagerContext -> compare output statevector/measurement statistics against the mathematically expected result. Not "does it run without errors." The test must verify the actual output against a known-correct answer.

13. **NO DUPLICATED PRIMITIVES — USE THE DSL.** Before implementing ANY quantum subroutine, check what `src/gates.jl` and `src/library/patterns.jl` already provide. If it exists, import it. If it doesn't, add it once in the right place.

14. **THE SEVEN DESIGN PRINCIPLES ARE AXIOMS.** P1-P7 from the PRD (SS1) are non-negotiable. If an implementation choice violates any principle, the implementation is wrong. In particular:
    - P1: Functions are channels. No separate "channel" wrapper the programmer must use.
    - P2: No `measure()` function. Type boundary only.
    - P5: No gates, no qubits in user-facing code. Registers and primitives.
    - P7: Nothing in the core may assume d=2 in a way that forecloses higher d.

## Julia Conventions

1. **Module name is `Sturm`.** `using Sturm` brings the public API into scope.
2. **Mutation convention.** Functions that mutate quantum state end with `!` (e.g., `H!`, `swap!`, `depolarise!`). The four primitives are the exception — they use operator syntax.
3. **Type stability.** Functions should be type-stable. Use `@code_warntype` to check hot paths.
4. **No unnecessary dependencies.** Core Sturm.jl depends only on Orkan (via `ccall`). No Qiskit, no Cirq, no other quantum frameworks. Only `Test` in extras.
5. **Width as type parameter.** `QInt{W}` carries width in the type. Julia specialises on it. Use `where {W}` dispatch, not runtime branching on width.
6. **Context propagation via task-local storage.** `current_context()` reads from `task_local_storage(:sturm_context)`. The `@context` macro sets it.

## Orkan FFI

Sturm.jl calls Orkan via `ccall` to a shared library (`liborkan.so` / `liborkan.dylib`). The FFI layer lives in `src/orkan/`. Julia manages the DSL, type system, and DAG. Orkan manages the state vector and density matrix.

Key boundary: Julia allocates/frees Orkan state handles. Every `ccall` is wrapped in a Julia function with proper error checking. The Orkan pointer is owned by the context and freed in a finalizer.

```
Julia (Sturm.jl)                    C (Orkan)
─────────────────                   ─────────
QBool, QInt, types                  -
CompilationContext, DAG             -
when(), ⊻=, .θ+=, .φ+=             -
EagerContext          ──ccall──►    orkan_state_create()
  apply_ry!()         ──ccall──►    orkan_gate_ry()
  apply_rz!()         ──ccall──►    orkan_gate_rz()
  apply_cx!()         ──ccall──►    orkan_gate_cx()
  measure!()          ──ccall──►    orkan_measure()
```

## File Structure

```
Sturm.jl/
  Project.toml
  src/
    Sturm.jl              # module definition, exports
    orkan/                 # FFI bindings to liborkan
      ffi.jl               # raw ccall wrappers
      state.jl             # OrkanState handle + finalizer
    types/                 # WireID, QBool, QInt, ClassicalRef
    context/               # AbstractContext, EagerContext, DensityMatrixContext, TracingContext
    primitives/            # preparation, rotation, entangle, boundary
    control/               # when.jl
    noise/                 # depolarise, dephase, amplitude_damp, classicalise
    channel/               # Channel struct, trace, compose, openqasm
    passes/                # deferred_measurement, gate_cancel, clifford_simp
    qecc/                  # AbstractCode, Steane
    library/               # patterns.jl (superpose, interfere, fourier_sample, phase_estimate)
    gates.jl               # convenience gates built from 4 primitives
  test/
    runtests.jl
    test_primitives.jl
    test_bell.jl
    test_teleportation.jl
    ...
```

## Build & Test

```bash
# Run tests
julia --project -e 'using Pkg; Pkg.test()'

# Quick REPL check
julia --project -e 'using Sturm; ...'

# Activate and develop
julia --project
]test
```

## License

AGPL-3.0. Every file.


<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:ca08a54f -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd dolt push
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->
