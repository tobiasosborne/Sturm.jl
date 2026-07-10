# Sturm.jl — Quantum Programming DSL (v2 rebuild)

## What This Is

A Julia quantum programming language where functions are channels, the
quantum-classical boundary is a type boundary, and QECC is a higher-order
function.

**Spec:** `Sturm-PRD-v2.md` (normative). `Sturm-PRD.md` (v0.1) remains for
the parts v2 explicitly carries over — contexts, Orkan FFI, Bennett bridge,
QECC-as-HOF, promotion, channel-IR passes discipline.

## ⚠ REBOOT STATUS (2026-07-04)

**This branch begins at zero.** The complete v0.1 implementation (~60 test
files, Shor, QSVT, Steane, hardware transport — a working prototype) lives
on the **`v0.1-deprecated`** branch with full history. It was deprecated
deliberately: the v0.1 primitive layer (Bloch-angle rotations `q.θ += δ` /
`q.φ += δ`) is condemned by PRD-v2 §1, and the codebase is saturated with
it. We rebuild from the spec.

**Reimport policy.** v0.1 code returns from `v0.1-deprecated` only through
the v2 design gates: it must be re-expressed against the v2 surface/kernel,
pass the 3+1 agent rule where applicable, arrive with its tests rewritten
to v2 vocabulary, and carry its `docs/physics/` distillations with it.
Never bulk-copy. The deprecated branch is a quarry, not a library.
Institutional memory (`WORKLOG.md`, `worklog/`, beads) carries across the
reboot — read session-91/92 for how v2 was derived.

**Backend: Orkan from day 1.** The EagerContext delegates to `../orkan/`
(C17 statevector + density matrix simulator with OpenMP) via `ccall`. No
pure-Julia simulator — Orkan IS the simulation engine. Julia owns the type
system, DSL, compilation, and channel algebra. Orkan owns the linear
algebra.

## Implementation Principles

These are NON-NEGOTIABLE. Every agent, every session, every commit.

0. **MAINTAIN THE WORKLOG.** Every step, every session: update `WORKLOG.md`
   (index) + `worklog/` shards with gotchas, learnings, surprising
   decisions, ABI mismatches, test failures and their root causes, anything
   a future agent would wish it knew. If you hit something non-obvious,
   write it down before moving on.

1. **FAIL FAST, FAIL LOUD.** Assertions, not silent returns. Crashes, not
   corrupted state. `error()` with a clear message, not a quiet `nothing`.
   One principled exception, from PRD-v2 §3.9: implicit operations
   *without backaction* (scope-exit traces) are silent by design; implicit
   operations *with* backaction (P2 casts) warn. Do not "fix" the silence
   of traces.

2. **CORE CHANGES REQUIRE 3+1 AGENTS.** Any change to core types
   (`types/`), the context interface, the kernel (process values, `ctrl`,
   views), primitives/casts, or the Orkan FFI layer requires: 2 proposer
   subagents (independent designs), 1 implementer. The orchestrating agent
   is the reviewer (+1). Proposers must not see each other's output. The
   implementer picks the better design (or synthesises). The orchestrator
   reviews for PRD conformance, idiomatic DSL usage, and test coverage.

3. **GROUND = PHYSICS.** Every quantum operation, every kernel identity,
   every channel law must be grounded in physics. Not pinned numbers. Not
   "it works on the test case." If you derive something, prove it on paper
   first. The v0.1 teleportation bug (wm28: shipped protocol teleported
   only the diagonal; marginal-statistics test was blind to it) is the
   canonical cautionary tale — channel-level tests (Choi), not marginals.

4. **PHYSICS = LOCAL PDF + EQUATION (two-tier policy).** Every cited paper
   needs a local source plus an explicit equation reference:
   - `docs/physics/` — canonical, committed: original PDFs AND short
     Markdown distillations (`docs/physics/<author>_<topic>.md`) with
     theorems/equations/page numbers. Docstrings cite the `.md`.
   - `docs/literature/` — gitignored scratch space.
   Lint: a runtests boot pass greps `src/` for `docs/physics/...\.md`
   references and asserts each path resolves. PRD-v2 §9 "Citations TODO"
   lists the ~16 distillations the v2 build needs — write each before the
   code that cites it.

5. **LITERATE CODING.** Every non-trivial function has a docstring: WHAT,
   WHY, WHICH equation/paper. Comments explain intent, not mechanics.

6. **BUGS ARE DEEP AND INTERLOCKED.** Never assume a bug is shallow.
   Quantum bugs are treacherous: a sign error in a phase is invisible
   until entanglement amplifies it — and controlled-phase bugs recurred in
   Cirq/Qiskit/pytket for *years* (PRD-v2 §4.2) despite dedicated fields.

7. **GET FEEDBACK FAST.** Run `julia --project -e 'using Sturm; ...'` or
   the test suite after every non-trivial change. Check every 50 lines.

8. **RESEARCH STEPS ARE EXPLICIT.** If you don't know what a step
   involves, mark it as a research step. Don't guess. Don't hallucinate.

9. **SKEPTICISM.** Be skeptical of everything: subagent output, previous
   agents' work, your own assumptions, the PRD's own claims. Verify. Test.
   Reproduce.

10. **TEST-DRIVEN DEVELOPMENT.** Write the test first. Tests live in
    `test/`. Every PR needs tests. Statistical tests use N>=1000 samples
    with tolerance. The normative laws in PRD-v2 (§3.2 boundary algebra,
    §4.2 kernel laws, §3.9 scope) are each a named required test.

11. **IDIOMATIC DSL — THE SEVEN SURFACE CONSTRUCTS.** All user-facing
    quantum code is written with the v2 surface vocabulary (PRD-v2 §3.8),
    which supersedes v0.1's five-construct table:

    | # | Surface form | Role |
    |---|--------------|------|
    | 1 | `QBool(p, φ=0)` / `QBool(b)` (D1) | preparation cast (cq) |
    | 2 | `Bool(q)`, `Int(x)` — **consuming** | measurement cast (qc) |
    | 3 | `a ⊻= b`, `not!(a)`, `add!(x, ±a)`, P8 mixed forms | action family: translations / flips / entanglement (D12) |
    | 4 | `dual(q)`; bound-view actions `q̂ ⊻= r`, `x̂ += a` | conjugate view (Pontryagin) + Ĝ-modulations (D11) |
    | 5 | `when(q) do … end` | coherent control (D13: streaming licensed) |
    | 6 | `cases` / `@cases` | classical branching on outcomes (D3: tokens under Tracing) |
    | 7 | `oracle(f, x)` | Bennett bridge |

    There are NO rotation primitives on the surface. There is no CNOT
    gate: entanglement is composed (`a ⊻= b`, `when` + body). CZ is
    `q̂ = dual(q); q̂ ⊻= r` or `when(r) do not!(dual(q)) end` — call-LHS
    op-assign (`dual(q) ⊻= r`) is NOT valid Julia, and `dual(x) = y` is
    a local-method-definition trap (PRD-v2 D11). Conjugate-basis
    measurement is `Bool(dual(q))`. Addition is `add!(x, a)` — Draper
    is the KERNEL's lowering of it; the view op-assign `x̂ += a` is
    MODULATION (phases), not addition (PRD-v2 §3.3, r6/B2). Arithmetic
    obeys the two-world registry (PRD-v2 §3.4/D12): ring ops are value
    world (fresh outputs); the bijective action family is registered
    in-place; `x += a` on a bare register is a lost-binding trap.
    Views are addressing modes, not numbers — they do not ride P9.
    Angles live in the kernel (process values: `U2` quaternion+phase,
    `Perm`, `UnitaryDAG`) and are reached only through library HOFs.
    **If your program reads like a circuit diagram, it is wrong. If it
    mentions a gate, a rotation angle, or a process value, it is not
    surface code. If it reads like ordinary Julia with a few casts and
    views, it is probably right.**

12. **FULL PIPELINE TESTS WITH VERIFICATION.** Every algorithm: construct
    via DSL → execute on EagerContext → compare against the
    mathematically expected result. For channels, compare at the channel
    level (Choi/diamond), not output marginals — marginals passed v0.1's
    broken teleportation.

13. **NO DUPLICATED PRIMITIVES — USE THE DSL.** Before implementing ANY
    quantum subroutine, check what the kernel and library already provide.
    If it exists, import it. If it doesn't, add it once in the right place.

14. **THE NINE AXIOMS ARE AXIOMS.** P1–P9 as restated in PRD-v2 §6 are
    non-negotiable. Highlights that bite daily:
    - P1: functions are channels; scope is the Stinespring boundary
      (§3.9) — locals are environment, traced at region exit.
    - P2: the boundary is a cast; casts consume; implicit casts warn.
      qc∘cq = id, cq∘qc = pinching — both are required tests.
    - P4: quantum control is an operation on **process values**, never on
      channels (theorem — PRD-v2 §1.1). Surface `when`; kernel `ctrl`;
      guardrails (§3.5) are part of the axiom.
    - P5: no gates in surface code. The kernel may hold definite
      unitaries; an IR is not a user language.
    - P7: dimension-agnostic by parametricity — a register type declares
      (Hilbert space, symmetry structure, conjugate structure).
    - P9: registers are numeric types; generic code rides P8 overloads;
      typed functions go through `oracle`. NO catch-all on `Function`.

## Phase Discipline (replaces v0.1's "Global Phase and Universality")

The v0.1 doctrine ("the DSL lives in SU(2); H!² = −I is a feature; do not
fix it") is **dissolved** — it was an artifact of the condemned rotation
surface, not physics. The v2 rules:

- The kernel works in **U(2)** (quaternion + phase). X, Z, H are exact.
- The phase quotient is crossed **exactly once**, at application, by
  Ad's kernel (PRD-v2 §4.3) — never by convention in library code.
- `ctrl` is a homomorphism on process values and **the single choke
  point** that constructs controlled lowerings, system-wide (§4.2). No
  other code path may build a controlled decomposition. This is the
  structural invariant that Cirq/Qiskit/pytket lacked.
- Views unwrap; processes compose (§3.3). `dual(dual(x)) === x`
  structurally; but F² = parity as a *process*. An implementation that
  lowers `dual` by applying F is wrong — the signature of the bug is
  integer negation under double duals.
- The view SWAPS translation and modulation (Pontryagin): `not!` ↦ X,
  `not!(dual(·))` ↦ Z; `add!(x, a)` translates, `x̂ += a` modulates.
  An implementation where the dual-view op-assign changes `Int(x)` is
  wrong (PRD-v2 §3.3, review r6/B2).
- **U2 equality is double-cover equality**: (q, φ) ~ (−q, φ+π); exact
  H² lands on (−1_quat, π) ≡ +I. NEVER merge +I with −I —
  `Ry(2π) = −I` is physics (spinor periodicity) and `ctrl(−I)` is a
  real operation. A test asserting `Ry(2π) == I` is WRONG. Float laws
  compare with ≈ (PRD-v2 §4.1).
- Bennett strategy selection is control-aware: measurement-based
  uncompute is EXCLUDED under a nonzero control stack / inside `when`
  bodies (PRD-v2 §3.4) — measurement under `ctrl` is unrepresentable.

## Channel IR vs Unitary Methods — HALLUCINATION RISK

Sturm's IR represents **channels** (CPTP maps), NOT unitaries. When the
DAG returns to the v2 codebase it will contain non-unitary nodes
(measurement, classical branching, discard). Most optimization methods
from the literature assume unitary circuits and will produce WRONG
RESULTS on a channel DAG. MANDATORY: partition at measurement barriers;
apply unitary-only methods (phase polynomials, ZX, SAT synthesis, DD
equivalence) ONLY to unitary blocks — in v2 these carry an explicit
unitarity witness (PRD-v2 §4.1); channel-level equivalence is Choi/diamond,
never unitary comparison. See `Sturm-PRD.md` for the full protocol; it
carries over verbatim.

## Julia Conventions

1. **Module name is `Sturm`.**
2. **Mutation convention.** State-mutating functions end with `!`
   (`not!`, `add!`, `swap!`, `ptrace!`). Casts use constructor syntax
   (`QBool(p)`, `Bool(q)`, `Int(x)`). Views are lazy wrappers in the
   `transpose` idiom (`dual(q)`, kernel `view(V, q)`), borrow rather than
   own, and unwrap involutively. Registered exceptions (PRD-v2
   §3.4/D11/D12 — adopted knowing julialang#249/#3217 rejected the
   pattern for the general language): `not!` (no-cloning forbids
   `b = !b`); the register `Base.xor` methods and the
   translation-family methods on BOUND VIEWS (`x̂ += a`, `q̂ ⊻= r`),
   which mutate in place and return the same handle — that is what
   makes `a ⊻= b` and `b ⊻= oracle(f, x)` physical operations rather
   than rebinds. Scope is the bijective action family ONLY — never
   ring ops (`+`/`*` between registers allocate fresh outputs; P9).
3. **Type stability.** Check hot paths with `@code_warntype`.
4. **No unnecessary dependencies.** Core Sturm.jl depends only on Orkan
   (via `ccall`). Only `Test` in extras.
5. **Width as type parameter.** `QInt{W}` carries width in the type; use
   `where {W}` dispatch, not runtime branching.
6. **Context propagation via `Base.ScopedValues`** (Julia ≥ 1.11 —
   NOT task_local_storage, which does not inherit into
   `Threads.@spawn`/`@async` children; verified on 1.12.5).
   `current_context()` reads a `ScopedValue`; `@context` binds it via
   `with(...)` — a genuine `try`/`finally`, which IS the deterministic
   scope cleanup PRD-v2 §3.9 demands (regions, never GC finalizers).
   The manual region form is `region() do … end` (D10). Don't re-read
   `current_context()` in per-op hot loops — pass the context through
   kernel-internal call chains (ScopedValue access allocates).
7. **Julia idiomaticity is paramount** (standing preference from Tobias).
   If a construct fights the host language, the construct is wrong.
8. **Namespace = layering.** Surface constructs are `export`ed; kernel
   API (`U2`, `Perm`, `ctrl`, `view`, named constants) is marked
   `public` (Julia 1.11) — documented, reachable as `Sturm.ctrl`, not
   dumped into `using Sturm`. The §2 layer table gets mechanical
   enforcement at the namespace level.
9. **The PRD's examples compile, forever.** `test/test_prd_examples.jl`
   Meta.parses every fenced Julia block in Sturm-PRD-v2.md at every
   test run, and executes the §7 examples under EagerContext once the
   surface exists (bead hn90). Round 6's lesson: five review rounds
   missed a parse error because normative code lived in prose.

## Orkan FFI

Sturm.jl calls Orkan via `ccall` to `liborkan.so`/`.dylib`. The FFI layer
lives in `src/orkan/`. Julia allocates/frees Orkan state handles; every
`ccall` is wrapped in a Julia function with error checking; pointers are
owned by the context and freed via the context's deterministic cleanup.
The v2 ccall surface (general 1q-unitary entry point vs Euler ZYZ triple)
is open — PRD-v2 D7; the ZYZ chart singularity at θ≈0/π is handled at
this boundary and only here. DSL-level checks (aliasing with register
identity, PRD-v2 §8.4) fire BEFORE the FFI shim's index checks.

## File Structure (target — nothing exists yet; build in this order)

```
Sturm.jl/
  Project.toml           # milestone 0: scaffold
  src/
    Sturm.jl             # module definition, exports
    kernel/              # process values: U2 (quat+phase), Perm,
                         #   UnitaryDAG; ∘ ⊗ adjoint ctrl; views; Ad
    types/               # WireID, QBool, QInt{W}, QMod{d}, ... (+ x[i])
    context/             # AbstractContext, EagerContext, DM, Tracing;
                         #   regions & scope cleanup (§3.9)
    orkan/               # FFI bindings
    surface/             # casts, ⊻=/not!, dual, when, cases (§3.8)
    library/             # evolve!, amplify, phase_estimate, arithmetic …
    bennett/             # oracle bridge (Perm values)
    qecc/                # encode(ch, code)
  test/                  # law tests first: §3.2, §4.2, §3.9
  docs/physics/          # distillations (PRD-v2 §9 list) — before code
```

The v0.1 tree (for reference while quarrying) is on `v0.1-deprecated`.

## Build & Test

```bash
julia --project -e 'using Pkg; Pkg.test()'   # once milestone 0 lands
julia --project -e 'using Sturm; ...'
```

## License

AGPL-3.0. Every file.

## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see
full workflow context and commands.

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

Rules: use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate,
or markdown TODO lists. Run `bd prime` for the session close protocol. Use
`bd remember` for persistent knowledge — do NOT use MEMORY.md files.

## Session Completion

**When ending a work session**, complete ALL steps. Work is NOT complete
until `git push` succeeds.

1. **File issues for remaining work**
2. **Run quality gates** (if code changed)
3. **Update issue status**
4. **PUSH TO REMOTE** (mandatory):
   ```bash
   git pull --rebase
   bd dolt push
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** — stashes, stale branches
6. **Verify** — all changes committed AND pushed
7. **Hand off** — context for next session

CRITICAL: never stop before pushing; never say "ready to push when you
are" — YOU push. If push fails, resolve and retry until it succeeds.
