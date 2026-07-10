# Bennett bridge audit — M7 pre-step (Sturm.jl-jv50)

Read-only audit, 2026-07-10. No Julia executed, no commits. Sources: live
`/home/tobias/Projects/Bennett.jl` @ `051f5402` (HEAD, 2026-06-15) and
`/home/tobias/Projects/BennettVM.jl` @ `b0467b8` (2026-06-15).

## Which repo is live

| Repo | State | Verdict |
|---|---|---|
| `Bennett.jl` | v0.5.0, HEAD `051f5402`, active to 2026-06-15, ~60 src files, full test tree | **LIVE — the compiler.** This is the M7 target. |
| `BennettVM.jl` | v0.1.0-dev, HEAD `b0467b8`, active to 2026-06-15, path-dep on Bennett.jl | **LIVE — the second lowering target** (`target=:reversible_vm`). Phase 2 (production) just opening; only the spike has shipped. |
| `bennett` (lowercase) | Single `PRD.md`, no git commits (empty history), last touched 2026-04-27 | **DEAD stub.** Ignore — a PRD sketch that never became a repo. |

---

## Q1 — Current Bennett.jl API surface

**Compile entry point.** `reversible_compile(f, arg_types; kw...) -> ReversibleCircuit`
(Julia function → reversible circuit via LLVM IR, walked as typed LLVM.jl
objects — no regex). Overloads: `(f, Type...)`, `(f, Type{<:Tuple})`,
`(parsed::ParsedIR)`, plus `CompileOptions`-bundle variants. Widths: scalar args
`Int8/16/32/64`, `UInt8/16/32/64`, `Float64`, `Bool`, and flat `NTuple`s of those.

**Artifact shape — `ReversibleCircuit` (`src/gates.jl`):**
```
struct ReversibleCircuit
    n_wires::Int
    gates::Vector{ReversibleGate}          # ordered, gates[1] applied first
    input_wires::Vector{WireIndex}         # WireIndex = Int, 1-based
    output_wires::Vector{WireIndex}
    ancilla_wires::Vector{WireIndex}
    input_widths::Vector{Int}              # e.g. [8] for Int8
    output_elem_widths::Vector{Int}        # e.g. [8,8] for Tuple{Int8,Int8}
    loop_check_wires::Vector{LoopGuard}    # 4th wire class — see Q2 risk
end
```
- **Instruction vocabulary: exactly three gates** — `NOTGate(target)`,
  `CNOTGate(control, target)`, `ToffoliGate(control1, control2, target)`. All
  `<: ReversibleGate`, all self-inverse (involutions). **No MCX (>2 controls),
  no measurement gate, no classical branch node.** MCX-4+ is composed from
  Toffolis + ancilla inside Bennett; it never appears as an artifact node.
- **Wire numbering:** 1-based `Int`. The constructor enforces a *four-set
  partition* of `1:n_wires` into input/output/ancilla/loop_check (input∩output
  overlap IS allowed — self-reversing prims write results onto input wires;
  all other pairs must be disjoint; union must cover `1:n_wires`).
- **Ancilla accounting:** ancillas ARE counted in `n_wires` and listed in
  `ancilla_wires`. Bennett's construction guarantees they return to |0⟩.
- Collection protocol: `ReversibleCircuit` iterates/indexes its gate vector
  (`for g in circuit`, `circuit[i]`, `length`).

**Strategy selection.** Two orthogonal knobs:
- `strategy=` on the *front-end* (`:auto | :tabulate | :expression`) — chooses
  IR-lowering vs classical value-table (QROM) baking.
- `bennett(lr; strategy::BennettStrategy=DefaultStrategy())` on the *back-end* —
  the compute/copy/uncompute construction variant. Six concrete strategies
  (`src/bennett_strategies.jl`): `DefaultStrategy` (forward + CNOT-copy +
  uncompute), `EagerStrategy`, `ValueEagerStrategy`, `CheckpointStrategy`,
  `PebbledStrategy(max_pebbles)`, `PebbledGroupStrategy(max_pebbles)`. **Every one
  emits only NOT/CNOT/Toffoli — all are unitary, none is measurement-based.**
  Arithmetic-family knobs: `add=:ripple|:cuccaro|:qcla|:auto`,
  `mul=:shift_add|:karatsuba|:qcla_tree|:auto`.

**Caching.** Two module-level caches, both keyed by identity + kwargs:
- `_compile_cache :: Dict{Tuple,ReversibleCircuit}` keyed on
  `(objectid(parsed), max_loop_iterations, compact_calls, add, mul,
  fold_constants, target, auto_self_reversing, mem, persistent_impl, hashcons)`
  — behind a `ReentrantLock`. NB: keyed on `objectid(parsed)`, so it only hits
  across repeat compiles if the same `ParsedIR` instance is reused.
- `_extract_parsed_ir_cached` memoises IR extraction on `(f, types, optimize, mem)`.
- (v0.1 bridge added its own `oracle_table`/`qrom_lookup_xor` LRU caches on the
  *Sturm* side, keyed on `(hash(data), W_in, W_out)`.)

**QROM primitives** the v0.1 bridge leaned on (still present): `emit_qrom!`,
`WireAllocator`, `wire_count`, `LoweringResult`, `bennett(lr)`. Resource
inspection: `gate_count`, `t_count`, `t_depth`, `toffoli_depth`,
`ancilla_count`, `peak_live_wires`, `verify_reversibility`.

---

## Q2 — Fit to v2's `Perm`

Sturm v2 kernel (`src/kernel/perm.jl`):
`Perm(n::Int, gates::Vector{MCX})`, `MCX(controls::Vector{Int}, target::Int)`,
**wire 1 = MSB**, `MCX` supports an arbitrary number of controls.

**Gate-vocabulary fit: PERFECT, lossless, trivial.** Bennett's three gates are
the 0/1/2-control cases of `MCX`:
```
NOTGate(t)              → MCX(Int[],       t)
CNOTGate(c, t)          → MCX([c],         t)
ToffoliGate(c1, c2, t)  → MCX([c1, c2],    t)
```
`MCX` is strictly more general; there is **zero representational impedance** at
the gate level. A Bennett `ReversibleCircuit` maps to `Perm(n_wires, [MCX…])`.

Impedances (all bridge-side, none require Bennett.jl changes):

1. **Bit order — REAL, must be reconciled.** Sturm pins **wire 1 = MSB**
   (`src/types/qint.jl:11` "THE ENDIANNESS PIN … WIRE 1 = MSB", kernel-wide:
   Perm/Ctrl/QFT/QInt all MSB-leading). The v0.1 bridge treated Bennett as
   **little-endian** (`oracle` docstring: "Extract input wires from QInt
   (little-endian)", positional `x.wires[i] for i in 1:W`). Bennett numbers
   wires in its own allocation order and reports the bit→wire mapping only
   *positionally* via `input_wires` / `output_wires`. So the bridge must
   translate every `WireIndex` in every `MCX` from Bennett's numbering into the
   MSB-first register position. **Action:** probe Bennett's bit-significance→
   wire order empirically (compile `x->x`, drive a known basis state, read which
   output wire carries which bit) and build the index remap once; do NOT assume
   a direction. This is the single most bug-prone step (a silent bit-reversal
   passes marginal tests — the wm28 class of bug).

2. **Ancilla wires ride in `Perm.n`.** A `Perm` is a permutation on *all* its
   wires. Bennett's ancillas return to |0⟩, so the full `n_wires` circuit IS a
   permutation and the natural `Perm` is on `n = n_wires` (I/O + ancilla +
   loop_check). The Sturm context allocates the ancilla/loop wires, applies, and
   deallocates — exactly the v0.1 `apply_reversible!` shape, now expressed as
   `ctrl`/apply of a `Perm`. Perm cannot be shrunk to just I/O wires (the
   scratch is essential to the MCX decomposition).

3. **`loop_check_wires` are NOT clean ancillas — the sharp risk.** The 4th wire
   class holds a convergence flag that is `1` iff a data-dependent loop
   converged within `max_loop_iterations` — it does **not** return to |0⟩. Under
   `when`, §3.5/§3.9 require every body-allocated ancilla to exit at |1⟩-block
   norm exactly 0 or the superposed control decoheres. A loop-carrying oracle
   therefore produces a `Perm` whose loop-check wire violates the clean-ancilla
   exit. **The bridge must reject (loud error) any `ReversibleCircuit` with
   non-empty `loop_check_wires` when applied under a nonzero control stack.**
   Loop-free circuits (all DJ/BV/arithmetic cases) have empty `loop_check_wires`
   and are unaffected.

4. **`b ⊻= oracle(f, x)` accumulate idiom — already sound (D9-verified).**
   Bennett's compute-copy-uncompute copies `f(x)` into the output wires by
   CNOT/Toffoli and never reads an output wire as a control (D9 ruling, gate-
   level verified against v0.1 `bridge.jl`). So mapping the `Perm`'s output
   wires onto a preset target `b` yields `b ⊕ f(x)` by linearity — the kickback
   idiom. The bridge just points the output wires at `b`'s wires instead of
   fresh |0⟩ (v0.1's fresh-|0⟩ `oracle` was a caller choice, not a gate
   constraint). No Bennett change needed.

**Verdict: FITS Perm with a lossless gate mapping + a bridge-side wire-index
remap.** No Bennett.jl API change required for the artifact shape.

---

## Q3 — MBU under control

**MBU does not exist in Bennett.jl's circuit backend.** Every strategy
(`DefaultStrategy` … `PebbledGroupStrategy`) emits only NOT/CNOT/Toffoli;
`ReversibleGate` has no measurement subtype and there is no classical-branch
node (grep for measurement across `src/` finds only comments / resource
estimation). Measurement-based uncomputation appears **only as a documented
future optimisation** in the Sturm-side `qrom_lookup_xor!` docstring (the O(√L)
Babbush-2018-AppC / Gidney-2019-Fig3 alternative) — unbuilt.

Consequence: the §3.4 MBU-exclusion requirement is **satisfied structurally,
for free, today.** Because a `Perm` *is* a phase-free unitary permutation and
every Bennett artifact is exactly that, the type boundary is the enforcement:
an MBU lowering is not a permutation, cannot be a `Perm`, and therefore cannot
cross into a `when`-body process value. There is nothing to exclude because
nothing MBU-flavored can be constructed.

**Smallest API answer:** none needed now. The bridge simply requests a unitary
`BennettStrategy` and lets `Perm` be the witness. Two forward-looking notes for
when MBU eventually lands in Bennett:
- If MBU is added as a *distinct return type* (not `ReversibleCircuit`), the
  type boundary keeps enforcing exclusion automatically — bridge never lifts it.
- If MBU were ever folded into `ReversibleCircuit` as a new `MeasureGate`
  subtype, *then* Bennett would need a `bennett(lr; strategy=…)` /
  `reversible_compile(…; allow_measurement=false)` constraint the bridge can
  set. That is the only scenario requiring a Bennett API addition, and it is not
  the current design. **Recommendation: keep MBU out of `ReversibleCircuit`;
  make it a separate artifact type** so the boundary stays the enforcement.

---

## Q4 — BennettVM.jl and the concrete D14 question

**What BennettVM IS:** the *second lowering target* of Bennett.jl, selected by
`reversible_compile(…; target=:reversible_vm)`. Where `ReversibleCircuit` is a
**fixed permutation circuit** (great for a quantum oracle, but cannot express
unbounded loops or runtime-sized memory), BennettVM is a **reversible
interpreter** for terminating computations of statically-unknown length. It
returns a `VMProgram`, **not** a `ReversibleCircuit`, and a `VMProgram` is
**not a permutation on a fixed wire set** — it has a program counter, a step/
unstep history tape, frames, and (Phase 2) runtime memory.

Wiring: Bennett.jl holds a write-once hook `_REVERSIBLE_VM_BACKEND::Ref{Any}`
(`src/Bennett.jl:419`); BennettVM's `__init__` registers its `lower_vm` entry
there (Bennett must not name BennettVM — that would be a dependency cycle). So
`using BennettVM` activates `target=:reversible_vm`; absent it, the VM path
errors loud. BennettVM currently **pins** Bennett.jl at SHA `31b63a6`
(`BENNETT_JL_PIN.md`) — a few commits behind current HEAD `051f5402` — and is a
path-dep; both co-develop. BennettVM Phase 2 is just opening (spike done, PRD v4
authored); it is **not yet a shippable execution target.**

Why this matters for the boundary: a `VMProgram` **cannot become a `Perm`.** The
whole point of the VM is the cases a fixed circuit can't represent. So for
Sturm's `oracle`, only the `target=:circuit` (default) path yields something the
Perm bridge can consume. This is the crux D14 must rule on.

### The D14 question, concretely, for Tobias

> **When a user writes `oracle(f, x)` and `f` needs the VM (unbounded loop /
> runtime-sized memory) so Bennett returns a `VMProgram` rather than a
> `ReversibleCircuit`, what does Sturm do with it?**

Three grounded options:

- **Option A — Circuit-only bridge; VM is out of scope for M7 (RECOMMENDED for
  M7).** Sturm's `oracle` consumes only `target=:circuit` → `ReversibleCircuit`
  → `Perm`. If Bennett can only compile `f` via the VM (loop-carrying, dynamic
  memory), `oracle(f,x)` raises a loud error ("not a fixed permutation; the VM
  lowering is not representable as a `when`-body process value"). Rationale:
  BennettVM Phase 2 is unfinished; a `Perm` is the entire v2 contract for the
  reversible corner; the VM adds nothing DJ/BV/QMod/Shor-mulmod need (all
  bounded-width, loop-free). D14 becomes a one-paragraph "circuit target only;
  VM deferred." **Lowest risk, unblocks M7 immediately.**

- **Option B — BennettVM as a *bounded-unrolling front-end* that still emits a
  Perm.** Under a control stack, §3.5 already forbids unbounded iteration
  (guardrail 3: bounded unrolling only). So a `when`-body oracle is *always*
  loop-bounded, which is exactly what `ReversibleCircuit` already handles via
  `max_loop_iterations` + `loop_check_wires`. Here BennettVM never crosses the
  boundary at all; it stays a Bennett-internal tool for resource estimation /
  replay, and Sturm only ever ingests circuits. D14 says: "the VM is a Bennett
  implementation detail; the only artifact that crosses into Sturm is a `Perm`;
  replay is Bennett's, never Sturm's."

- **Option C — BennettVM as a distinct *Sturm context / execution backend*.**
  The `VMProgram` crosses the boundary and Sturm treats it as an alternative
  lowering target with its own replay semantics (the VM owns step/unstep). This
  is the heaviest: it means a second execution model beside Orkan, a non-`Perm`
  process value that must define its own `ctrl`/compose/adjoint, and a channel-
  level equivalence story. Only justified if Sturm must run oracles whose length
  is genuinely runtime-unknown *outside* any `when` — which no current milestone
  (M7–M11) requires. **Highest risk; defer unless a capstone demands it.**

Concretely the paragraph D14 needs from Tobias answers three sub-questions:
(1) *Artifact:* `Perm` only, or also `VMProgram`? (2) *Replay owner:* Bennett/VM,
or Sturm? (3) *VM role:* Bennett-internal tool (A/B) or Sturm execution backend
(C)? The code strongly favors **A or B** — the `Perm` is the whole reversible-
corner contract, `when` already bans the unbounded case, and BennettVM Phase 2
isn't ready to be a backend.

---

## Q5 — Version / health (assessed from Project.toml + commits; no Julia run)

- **Bennett.jl:** `version = "0.5.0"`. `[compat] julia = "1.10"` (lower bound;
  no upper cap). **Being actively developed *on* Julia 1.12.5** — the
  `Project.toml` comments de-list JET because "JET 0.10 crashes precompiling on
  Julia 1.12.5" (Bennett-37ib). That is strong positive evidence Bennett.jl
  itself loads and tests on 1.12; only the JET *hygiene* test tool is disabled,
  and its testset self-skips (try/catch) while JET is absent. Deps are minimal
  and 1.12-safe: `LLVM` (compat `9, 10`), `PrecompileTools`, stdlib
  `InteractiveUtils`. Active to 2026-06-15; healthy commit cadence.
- **BennettVM.jl:** `version = "0.1.0-dev"`, `[compat] julia = "1.10"`, single
  dep = `Bennett` (path/pin). Validated at pin SHA: Bennett full `Pkg.test`
  ~688k Pass / 1 Broken; BennettVM `6450/6450` (per `BENNETT_JL_PIN.md`, fresh
  subprocess, orchestrator-verified). No CI badges visible in-repo; the health
  signal is the pinned-validation record in the PIN doc + WORKLOG.
- **Caveat:** `compat julia = "1.10"` only sets a *floor*; there is no CI
  artifact in-tree proving 1.12 green. The JET-disable comment is the closest
  evidence and it points the right way. Recommend the M7 bridge re-run
  Bennett's suite on the project's 1.12.x as a gate before hardening.

---

## Q6 — v0.1 bridge shape and drift

v0.1 `src/bennett/bridge.jl` (from `v0.1-deprecated`) consumed this Bennett
surface. Drift vs current Bennett.jl HEAD `051f5402`:

| v0.1 bridge consumed | Current Bennett.jl | Drift |
|---|---|---|
| `ReversibleCircuit`, `.gates`, `.input_wires`, `.output_wires`, `.ancilla_wires` | present; `+ .input_widths, .output_elem_widths, .loop_check_wires` | **Additive.** New `loop_check_wires` 4th class (see Q2 risk 3). Field-name-stable. |
| `NOTGate`, `CNOTGate`, `ToffoliGate`, `WireIndex`, `ReversibleGate` | present, exported, unchanged | **None.** |
| `reversible_compile(f, arg_type; kw…)` | present; kwargs expanded (`add/mul/strategy/mem/persistent_impl/hashcons/target/auto_self_reversing`); strict unknown-kwarg rejection | **Additive + stricter.** v0.1's `add=:qcla`, `mul=:qcla_tree`, `optimize`, `max_loop_iterations` still pass through. New `_reject_unknown_kwargs` means a typo'd kwarg now errors loud (good). |
| `gate_count`, `t_depth` | present (`gate_count` returns NamedTuple `(total, NOT, CNOT, Toffoli)`) | **None.** |
| `emit_qrom!`, `WireAllocator`, `wire_count`, `LoweringResult`, `bennett`, `allocate!` | all present/exported | **None.** `LoweringResult` signature is `(gates, n_wires, in_wires, out_wires, in_widths, out_widths)` — matches v0.1 usage. |
| `bennett(lr)` returns `ReversibleCircuit` | same, now with `strategy=` kwarg + `_compile_cache` memoisation | **Additive.** |
| n/a in v0.1 | new `target=:reversible_vm` → `VMProgram` via `_REVERSIBLE_VM_BACKEND` hook | **New surface** — the D14 subject. v0.1 predates it. |

The v0.1 bridge's gate mapping is v0.1-specific and **does not carry**: it
lowered `NOTGate` to `apply_rz!(π); apply_ry!(π)` (the condemned Bloch-angle
rotation surface). In v2 the mapping is into `Perm`/`MCX` (Q2), and `NOT` is
`MCX([], t)` — exact `X`, no rotation. So reuse the *interface shape*
(which fields, which entry points, the ancilla alloc/dealloc + accumulate
pattern) and re-derive the lowering against the kernel.

---

## Bottom line

- **Artifact-shape verdict: FITS `Perm`.** Bennett's NOT/CNOT/Toffoli are the
  0/1/2-control cases of `MCX` — lossless, no Bennett.jl change needed. The only
  real conversion work is a **bridge-side wire-index remap** to reconcile
  Bennett's numbering with Sturm's MSB-first pin, plus routing ancilla/loop
  wires through the context.

- **MBU-exclusion answer: satisfied for free.** Bennett emits no measurement;
  every artifact is a unitary `Perm`; the type boundary is the enforcement. No
  API addition needed now. Keep any future MBU as a *separate return type*, not
  a `ReversibleCircuit` node, and the boundary keeps enforcing §3.4 automatically.

- **D14 for Tobias:** what happens to a `VMProgram` (Bennett's non-permutation
  VM lowering) at the Sturm boundary? Options **A** (circuit-only bridge; VM out
  of scope — recommended for M7), **B** (VM stays Bennett-internal; only `Perm`
  crosses; `when` already bans the unbounded case), or **C** (VM as a distinct
  Sturm context — heavy, defer). Code favors A/B.

- **Single biggest M7 risk: the MSB/LSB bit-order remap.** Sturm pins wire 1 =
  MSB kernel-wide; the v0.1 bridge treated Bennett as little-endian. A silent
  bit-reversal survives marginal tests and only surfaces once entanglement
  amplifies it (the wm28 teleportation-bug class). Probe Bennett's bit→wire
  order empirically and verify the `Perm` at the channel/permutation level
  (`denoted_permutation`), never on output marginals. Second-order risk:
  `loop_check_wires` are not clean ancillas — the bridge must reject
  loop-carrying circuits under a control stack.
