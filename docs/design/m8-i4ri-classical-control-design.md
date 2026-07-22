# M8 Design Gate — classical-control IR (bead i4ri)

**Status:** SYNTHESIZED CANONICAL DESIGN (3+1 round, implementer synthesis).
**Gates:** all M8 code (TracingContext, D3 tokens, `cases`, passes) and the
M11 QECC syndrome path.
**Answers review findings:** F4, F5, F6, F13, F30 (`docs/design/prd-v2-review-gpt56-2026-07-19.md`).
**Blocked on:** one ⚠ **TOBIAS RULING** (F13 measurement spelling) before PRD
wording lands. F30 is ruled here; F13 option space is presented, not decided.

This document synthesizes two independent blind proposals:
- **Proposal A** — `docs/design/m8-i4ri-proposal-A-codex.md` (codex, gpt-5.6 xhigh)
- **Proposal B** — `docs/design/m8-i4ri-proposal-B-claude.md` (Claude Opus)

The two **converged** on every major axis (restricted classical IR not staged
lifting; copyable tokens + explicit correlation record not affine tokens; DM
measurement returns token + `cases`; `measure(q)` recommended for F13;
`@cases measure(m)` for F30). Where they differed in mechanism detail this
document adjudicates and records the provenance in §11. All Julia-semantics
claims below were re-verified against the installed `julia` (1.12.x) binary;
the transcript is summarized in §9.0.

---

## 0. One-paragraph thesis

There is **one physical object** under F4/F5/F6: the classical record of an
instrument, Σᵢ |i⟩⟨i|_C ⊗ ρ̃ᵢ. Sturm already builds it — the shipped DM
`_instrument!` pinch (`src/context/density.jl:135`) produces exactly
ρ ↦ Σ_b P_b ρ P_b on the measured wire, leaving it **live, not consumed, not
reset**. A **measurement token is a handle to that pinched-but-still-live
classical record**; `cases` conditions later operations on it; the token dies
(its record is summed out = the wire is traced) at its **last use**. That
single denotation answers "what does the IR store" (F6), makes DM branching an
exact channel (F5), and reuses shipped kernel code with **no new physics
primitive**. The classical-control *mechanism* (F4) is then a **restricted
combinator EDSL over that record** — never a general host tracer, because Julia
cannot trace `if`/`for`/indexing on a symbolic value (§9.0), and pretending it
can is exactly F4's bug.

---

## 1. F4 — the classical-control mechanism

### 1.1 The choice: restricted classical IR, not staged dynamic lifting

F4 forces a choice between (1) **staged dynamic lifting** (stop, read outcome,
resume/retrace a continuation per outcome) and (2) a **restricted classical
SSA/CFG IR**. The PRD §3.6 text ("a `ClassicalInt` flows through ordinary Julia
arithmetic/indexing, compiled once … dynamic loop bounds and indices") assumes a
non-existent third option: that Julia can trace arbitrary host code on a
symbolic value the way Jasp's JAX tracer traces Python. **It cannot** (§9.0):
`if token` and `token && x` throw Julia's native, non-interceptable `TypeError`;
`for x in token` / `arr[token]` need `iterate`/`getindex` on concrete values.
Jasp compiles-once only because qrisp rewrites Python **source/AST** into JAXPR
before tracing — a whole-language metacircular compiler. Sturm has no such layer,
and CLAUDE.md rule 7 ("if a construct fights the host language, the construct is
wrong") forbids building one via `@generated`/`IRTools` source surgery for the
general case.

**Decision: option (2), sharply restricted.** Staged retrace (1) is rejected as
the *default* because (a) it re-executes host effects per outcome (non-idempotent
user code runs more than once), (b) it cannot produce one channel/DAG for
DM/Tracing/Hardware, and (c) it breaks the deterministic one-run Choi discipline
(CLAUDE.md #12). It survives only as the explicit shot/trajectory mode of §3.3.

### 1.2 The build model — ordinary Julia runs ONCE at build time

The circuit is built by **ordinary Julia executed once at trace/build time**.
Every value known at build time — static loop bounds (`for i in 1:W`), static
indices (`x[i]`), register widths, `ntuple`, type dispatch — runs concretely and
unrolls normally. The **only** value not concrete at build time is a
**measurement token**. A token may flow through exactly these channels:

| # | Token use | Lowering | Denotation |
|---|---|---|---|
| **T1** | `cases(t) do … end` / `@cases` | condition off the token record | Σᵢ \|i⟩⟨i\|_C ⊗ 𝓑ᵢ (§2) |
| **T2** | whitelisted **total** classical primitives → new token | classical SSA node | pure function y = f(i) of the label |
| **T3** | `select(t, table)` bounded multiplexer | `cases` fanned over a static tuple | Σᵢ \|i⟩⟨i\| ⊗ tableᵢ |
| **T4** | classical **return** value of the reified function | classical output port | the record escapes as a classical wire |

The rule, stated once: **a token may sit in *data* position (through T1–T4) but
never in *control-flow* or *indexing* position.** This is dynamic lifting with an
honestly-bounded classical layer — the Jasp model minus the host-source tracer
Julia does not have. *(Rule taken verbatim from Proposal B §1.2; it is the
crispest statement of the boundary.)*

### 1.3 The supported classical subset (exact)

Classical token types (neither subtypes `Bool`, `Integer`, nor `Number`):

- **`ClassicalBit`** — an opaque handle to a 1-bit record.
- **`ClassicalWord{W}`** — an unsigned W-bit word (W ≥ 1). *Chosen over
  `ClassicalInt` (Proposal A §2.3): the measurement domain is the finite basis
  ℤ_{2^W}, not machine `Int`; width is in the IR type, arithmetic wraps mod 2^W,
  and hardware lowering has an explicit bit width.* Static bit extraction
  `w[i]::ClassicalBit` at a **build-time** index `i` is field access on the bit
  register (not array indexing).

All supported operations are **pure, deterministic, total on their finite
domains, side-effect-free**:

| Type | Supported operations (T2) |
|---|---|
| `ClassicalBit` | `!`, `~`, `&`, `\|`, `xor`/`⊻`, `==`/`!=` against a literal |
| `ClassicalWord{W}` | modular `+`, `-`, `*`; bitwise `&`,`\|`,`xor`,`~`; unsigned comparison **against a build-time constant** → `ClassicalBit`; shift by a build-time constant; bit extraction `w[i]` at a build-time index |
| Either | `select(pred, a, b)` / `select(t, table)`; total lookup in an immutable `ClassicalTable` (T3) |

- **Width changes are explicit** (zero-extend / truncate / concat helpers);
  never by implicit Julia conversion.
- **`ClassicalTable`** (Proposal A §2.4) is an immutable snapshot captured at
  trace start; lookup must be **total** — if the token domain exceeds the table,
  construction requires an explicit default or tracing fails. This is the *only*
  form of token-indexed lookup; ordinary arrays/dicts/strings cannot be indexed
  by a token.

**Static loops unroll; token-bounded loops are rejected.** A Julia loop is
supported iff its bounds and iteration protocol are concrete at trace time:

```julia
syndrome = measure(syndrome_register)      # ClassicalWord{W} token
location = decoder[syndrome]               # ClassicalTable lookup (T3), total
for j in 1:N                               # N host integer — unrolls
    @cases location == j begin             # (== against build-time j) → guard
        correct!(data[j])
    end
end
```

Wide feed-forward (QROM/MBU, F4's motivating worry) is expressible **without a
2^W table**: the classical value parameterizes a circuit *uniform in its bits* —
a static `for j in 1:W` loop that per-bit conditions a kernel operation
(`@cases w[j] begin … end`), the semiclassical/Pauli-frame pattern. IR size
follows the *written* static computation; the tracer must never enumerate 2^W
arms merely because a word's domain has that size (law **L13**, §8).

### 1.4 The loud-rejection boundary (F4 demands it be explicit)

No fallback concretization, no default value, no hard-coded `false`. Anything
outside T1–T4 is rejected, and most rejections are **free — Julia throws first**
(§9.0 confirms each):

- `if t`, `t && x`, `t || x`, `t ? a : b`, `while t` → Julia's native
  non-boolean `TypeError`. **Not interceptable**; only the token's *type name*
  surfaces. We name the token type descriptively so the message reads
  `non-boolean (Outcome) used in boolean context` (§9.0 confirms the unqualified
  name propagates; the module prefix does **not** — do not promise `Sturm.` in
  docs).
- `arr[t]`, `t:end`, `iterate(t)`, `rand(t)`, allocation sized by `t`,
  `Val(t)`, hashing a token → no method → `MethodError`/`ArgumentError`. Where
  **Sturm owns** the method (`getindex(::AbstractArray, ::ClassicalWord)`,
  `convert(Bool, ::ClassicalBit)`, `Bool(::token)`, `iterate(::token)`) we
  define a fallback throwing a **descriptive** Sturm error pointing to
  `select`/`cases`/`measure` (§9.0 confirms we control these).
- two runtime tokens through a non-whitelisted op (`t₁ * t₂` where both are
  runtime, `t₁ ÷ t₂`) → descriptive `error()`: "combining two measurement
  outcomes needs a quantum arithmetic circuit before measurement, or a `select`;
  classical post-processing is limited to the register's group operations
  (§3.6)."

Documentation must **not** promise a Sturm-dispatched exception from bare
`if token` / `&&` / `||` — that is Julia-native and uncustomizable beyond the
type name.

---

## 2. F6 — token & join semantics; what the IR stores

### 2.1 The token IS the classical record (physics)

An instrument that keeps its outcome is ρ ↦ Σᵢ (Pᵢ ρ Pᵢ): the measured wire,
**pinched not discarded**, *is* the classical register C carrying
Σᵢ |i⟩⟨i|_C ⊗ ρ̃ᵢ. This is the shipped `_instrument!` channel
(`src/context/density.jl:135`; `_PINCH_KRAUS = {|0⟩⟨0|, |1⟩⟨1|}`). Therefore:

> **A `ClassicalBit`/`ClassicalWord{W}` token is an owning handle to the
> instrument's classical record.** Under **Tracing** it is an SSA value naming
> that record's node; under **DM** it is realized as the pinched-but-live
> "c-wire" in the same density matrix; under **Eager** (§3) it is a plain
> scalar.

`cases`/classical-control conditions later operations on the record. Under DM
this is `ctrl` **off the c-wire**: because the c-wire is already dephased,
coherent `ctrl` off it is *exactly* classical control (its off-diagonals are
already zero, so the deferred-measurement principle makes it exact):
`cases(t) do B end ⟼ Σᵢ |i⟩⟨i|_C ⊗ 𝓑ᵢ(·)`. This is **not** banned by `when`
guardrail 1 (which forbids *measurement/trace/noise* under `when`,
`src/surface/when.jl` row 10): conditioning off an *existing* classical wire is
a unitary-witnessed `ctrl`, not a new instrument. *(The c-wire realization is
Proposal B's §2.1; adopted as the DM executor because it reuses `_instrument!` +
`ctrl` + `_trace_and_free!` verbatim and fits the shipped single-dense-density-
matrix Orkan backend with zero new machinery — see §11 for why this beat
Proposal A's separate sparse-rows executor.)*

**Denotational spec (Proposal A §3.2, adopted as the abstract meaning).** With
γ the complete joint assignment of live outcomes, the exact post-measurement
state is the hybrid cq record

  σ_CQ = Σ_γ |γ⟩⟨γ|_C ⊗ ρ̃_γ,   ρ̃_γ unnormalized, Tr ρ̃_γ = Born weight.

A deterministic classical SSA op y = f(γ) (T2) **extends** the record to
Σ_γ |γ, f(γ)⟩⟨γ, f(γ)| ⊗ ρ̃_γ — it does not split or sample. `cases` with
branch channels 𝓔_v and selector g(γ) gives
σ'_CQ = Σ_γ |γ⟩⟨γ|_C ⊗ 𝓔_{g(γ)}(ρ̃_γ); **the classical record survives the
branch**, so a second `cases` on the same token sees the same outcome. At final
quantum-only output, tracing the record recovers the expected channel:
Tr_C(σ_CQ) = Σ_γ ρ̃_γ.

The c-wire model is the *operational realization* of this denotation on the
shipped Orkan DM backend; A's abstract σ_CQ is the *meaning* every executor
(DM, Tracing, a future sparse-rows optimization) must agree with.

### 2.2 Copyable tokens + explicit record — DECISION (not affine)

F6 asks: affine (use-once) tokens, or an explicit correlation record?
**Explicit record; tokens are copyable.** A classical outcome is physically
copyable (fan-out is free); forcing tokens affine would break repeated
feed-forward, Pauli-frame processing, and the M11 syndrome path — the canonical
customer, where one syndrome drives several corrections. Both proposals rejected
affine tokens for this reason.

- **Quantum handles stay affine** — enforced by the *existing* single-sourced
  `consumed` set (`src/context/abstract.jl:156`). **Unchanged.**
- **Classical tokens are freely reusable**; `s2 = syndrome` copies the handle,
  creating no new measurement. The correlation Σ_γ|γ⟩⟨γ|⊗ρ̃_γ is retained until
  the token's **last use**, when the record is traced (= Σ summed). **Immediate
  block-accumulation — F6's bug — is exactly tracing the record too early; the
  fix is: never trace the record before the token is dead.**

**Last-use / liveness.** Two equivalent framings, both adopted:
- *DM (Proposal B):* the c-wire is an **owned** resource; it dies at region exit
  (`_trace_and_free!`, §3.9) or explicit `discard(t)`. Reuses shipped ownership
  machinery.
- *Tracing (Proposal A):* SSA **liveness** — a record may be coalesced only when
  no future node reads a value that distinguishes it, *and* that value is not a
  classical output. Coalescing is an optimization; correctness must hold without
  it.

Both are the same rule at different layers; the DM executor uses ownership,
the Tracing pass uses SSA liveness.

### 2.3 The join-typing rule (exact)

> **Cases join.** `cases(t) do … end` has branches {𝓑ᵥ}, one per value v of the
> discriminant token `t`; each branch runs in its own §3.9 region. After each
> branch's owned-and-unreturned locals are traced to a common signature, the
> join is well-typed **iff every branch presents the identical live-quantum
> *port signature*** — the ordered set of (port identity `WireID`, register type
> & width, live/consumed status, owning region, borrow/view parent). Formally,
> for `cases(t, {v ↦ 𝓑ᵥ})` to type-check:
>
> 1. Every pre-existing quantum port is live in **every** arm, or consumed in
>    **every** arm — never consumed in only some.
> 2. A surviving pre-existing port keeps the same `WireID` and register grouping.
> 3. Branch-local owned registers are consumed or traced before branch exit; a
>    branch-local register may **not** escape the join.
> 4. Views / `WireRef`s keep the same parent relationships across arms.
> 5. Each arm returns `nothing`; **`cases` returns `nothing`** — no quantum φ.
> 6. Branch-local classical SSA values do not escape; a branch-dependent
>    classical value is built explicitly with `select` (T3), **not** a phi at the
>    `cases` join.
>
> The node denotes 𝓔(ρ) = Σᵥ (|v⟩⟨v|_C ⊗ 𝓑ᵥ)(P_v ρ P_v), with C the retained
> record traced at `t`'s last use.

Loud join errors (each a named negative test, §8): measuring a port in only the
`true` arm; returning a fresh `QBool` from each arm; leaving a branch-local
ancilla live; consuming a port in one arm that another leaves live; rebinding an
outer handle to a different register in one arm.

This conservative rule deliberately **avoids quantum φ nodes** (branch-dependent
register *identity*/ownership transfer). Quantum φ is a separate future design
gate. **Classical conditionals use `select`, not a `cases` phi** *(Proposal A's
position, adopted over Proposal B's optional classical-`Phi` node: keeping the
join rule purely about quantum ports is simpler and more idiomatic, and the
syndrome path needs only `ClassicalTable`/`select`, never a cases-phi — §11)*.

### 2.4 IR record shapes (Tracing)

```
Token          := CBit(ValueID) | CWord{W}(ValueID)        # SSA name of a record
ClassicalNode  := Measure(wire) → ValueID                  # birth: pinch + keep
                | BitOp(op, ValueID...)                     # T2: !, &, |, xor, ~
                | WordOp(op, ValueID..., consts...)         # T2: +,-,*, shift, slice (mod 2^W)
                | CmpConst(ValueID, literal) → CBit         # word vs build-time const
                | Select(pred::ValueID, table)              # T3 multiplexer
                | TableLookup(ClassicalTable, ValueID)      # T3 total lookup
MeasureNode      instrument; quantum_inputs; classical_output::ValueID; consumed_ports
CasesNode        selector::ValueID
                 arms :: NTuple{K, (labels, ChannelRegion)} # identical PortSig
                 join :: PortSig                            # asserted == across arms
                 last_use :: Bool                           # if set, trailing trace(record)
```

`MeasureNode`, `CasesNode`, discard, reset, and noise are **channel nodes** and
therefore **barriers to unitary-only passes** (CLAUDE.md "Channel IR vs Unitary
Methods"; law **L18**). A maximal unitary region inside an arm may carry a
phase-fixed process witness (F3/§4.1); the containing channel IR must not. The
CFG is **structured**: `CasesNode` is the only runtime branch; no arbitrary
jumps, no backedges, no token-dependent loops in M8; classical conditionals use
`Select`, not general φ. It is a DAG with nested branch regions, not a general
cyclic CFG.

Under **DM** the same structure is *executed*, not stored: `Measure` →
`_instrument!` (pinch, keep wire); `CasesNode` → `ctrl`-off-c-wire over each arm,
accumulated by Orkan's linearity; `last_use` → `trace_wire!`. Reuses
`_instrument!`, `ctrl`/`_act!`, and `_trace_and_free!` — **no new physics
primitive.**

---

## 3. F5 — corrected DM portability table + shot/trajectory surface

### 3.1 Why the shipped code is right and the table is wrong

For instruments 𝓜ᵢ(ρ) = Pᵢ ρ Pᵢ, exact DM execution must evolve **all**
branches: 𝓔(ρ) = Σᵢ 𝓔ᵢ(𝓜ᵢ(ρ)). A scalar `Bool` selects one i and
renormalizes — a *trajectory*, not a channel. Ordinary Julia `if` can run only
the selected branch; it cannot form the sum. The shipped
`_measure_wire!(::DensityMatrixContext, …)` already throws
(`src/surface/casts.jl`, the `ArgumentError`) — **the table is wrong; the code
is right.**

### 3.2 Corrected §3.8 context-portability table

The controlling axis is **scalar-outcome (trajectory/shot) vs token
(channel/circuit)**. Eager unravels one trajectory → outcomes are scalars, host
`if` works. DM builds a channel, Tracing builds a circuit, Hardware builds a
device program — all three yield tokens and branch through `cases`.

| Construct | Eager | DM (exact) | Tracing | Hardware |
|---|---|---|---|---|
| casts (cq), action family, `dual`, `when`, `oracle` | ✓ | ✓ | ✓ | ✓ |
| `measure(q)` result | scalar `Bool`/int | **token** | **token** | **token** |
| `Bool(q)` / `Int(x)` return a **scalar** | ✓ | ✗ throws → `measure`/`cases` | ✗ throws → `measure`/`cases` | ✗ (build time) |
| host `if` / `&&` / `\|\|` on the outcome | ✓ | ✗ → `cases` | ✗ → `cases` | ✗ → `cases` |
| whitelisted finite classical SSA (T2/T3) | ordinary Julia | ✓ (symbolic) | ✓ (IR) | capability-checked |
| `cases` / `@cases` | run selected arm | **all correlated arms (exact)** | `CasesNode` | device conditional |
| concrete-bounded Julia loop | run | trace-time unroll | trace-time unroll | compile-time unroll |
| token-bounded loop / arbitrary token indexing | n/a after scalar | ✗ | ✗ | ✗ |
| exact one-run channel / Choi | ✗ (trajectory) | ✓ | IR only | target-dependent |

`cases` is the **one fully portable** branch construct (in Eager it runs the
taken arm). `if`/`&&` is the Eager-only ergonomic shortcut, valid exactly where
outcomes are scalars. A hardware target must advertise supported classical
opcodes, word widths, branch depth, and dynamic-control capability; unsupported
classical ops or `cases` are **compile errors before submission** — no backend
may silently substitute independent shots, outcome enumeration, or host retrace
(law **L17**). Completed hardware **shot results** are ordinary Julia values
*after* execution; host `if` on them is post-processing, not mid-circuit control.

### 3.3 Shot / trajectory surface

**Baseline for M8 (Proposal B §3.3):** do **not** invent a second branching
surface. Scalar-`Bool` branching *is* the Eager (trajectory) contract — Eager
already samples one instrument branch and returns a scalar
(`_measure_wire!(::EagerContext)` in `casts.jl`). To sample trajectories, run
under Eager via an explicit HOF:

```julia
results = shots(f, args...; N=1000)   # run f under Eager (trajectory) N×,
                                      # collecting scalar outcomes / return values
```

Inside `f`, ordinary `if` / `Bool(q)` / `Int(x)` work and each run is one
trajectory. This keeps DM/Tracing/Hardware strictly channel/circuit-valued and
confines every scalar-`if` program to the trajectory contract, where it is
physically honest. (This also relieves F25: large channels that cannot be
Choi-tested are estimated by `shots`.)

**Named future — density trajectories (Proposal A §4.2).** Eager is a
*statevector* (pure-state) trajectory simulator; it cannot sample trajectories
of a **noisy (Kraus)** channel. When noise lands (M8-noise/M11, `when.jl` row 9),
density trajectories get a **distinct wrapper type**, not a Boolean mode flag:

```julia
trajectory(DensityMatrixContext, capacity; rng) do ctx … end   # → TrajectoryContext{DM}
```

Its observation samples one branch and returns a scalar; it must **not** be
accepted by exact-channel/Choi APIs (they are different execution modes with
different types — law **L16**). This is scoped as the noise-era refinement, not
M8-baseline; M8 ships only `shots` over Eager.

---

## 4. F13 — `Bool(q)` / measurement spelling ⚠ **TOBIAS RULING REQUIRED**

Both proposers independently recommend the same answer (Option A, `measure`) but
**neither decides** — this is a Tobias-grade idiomaticity ruling. PRD §3.6/§3.8
wording (§7 below) is written against Option A and must be re-spelled if another
option is chosen.

### 4.1 Verified Julia constraints (§9.0 transcript)

1. Julia does **not** enforce that `Bool(x)` returns `Bool` — a constructor may
   return anything (`Bool(::Tok)` returned a `CBit`). So `Bool(q)::ClassicalBit`
   under Tracing is *mechanically possible* but breaks the reader's contract
   that `Bool(·)` yields a `Bool`.
2. A typed `Bool` slot / field / `::Bool` return **re-checks** and throws:
   a token cannot silently occupy a `Bool` binding (threw `MethodError` in the
   verified path — loud either way). So the implicit path `convert(Bool, q)`
   (`casts.jl`) **cannot** be the token-producing path under Tracing/DM.
3. `if token`, `token && x`, `token || x` throw Julia's **native, non-
   interceptable** `TypeError`; only the token's *type name* surfaces (and
   **unqualified** — `Outcome`, not `Sturm.Outcome`). The PRD-promised
   "descriptive Sturm error on `if token` pointing to `cases`" is
   **unimplementable**.

### 4.2 Option space

**Option A — `measure(q)` token verb; `Bool`/`Int` stay honest scalar casts. ★ RECOMMENDED (both proposers).**
`measure(q)` / `measure(x::QInt)` is the token-producing observation: a real
`Bool`/`Int` under Eager/shot, a `ClassicalBit`/`ClassicalWord{W}` token under
DM/Tracing/Hardware. `Bool(q)` / `Int(x)` remain the **scalar** casts, valid
only where a scalar is honest (Eager/shot); under DM/Tracing they **throw**,
pointing to `measure`/`cases`. Portable idiom everywhere: `cases(measure(q)) do … end`.
- *Pro:* `Bool` always returns `Bool` (convention preserved); `convert(Bool,·)`
  stays honest and Eager-only (keeps the P2 implicit-cast warning intact);
  casts (P2 boundary) and observations are cleanly separated; the `@cases
  measure(m)` boundary is a single explicit measurement.
- *Con:* two spellings ("cast" + "measure"); §7 examples migrate
  `Bool(q)`→`measure(q)`; `measure` return type varies by context.
- **Dependency (Proposal B R2):** `measure`'s per-context return type is
  inference-clean **only once handles carry their context as a type parameter**
  (`QBool{C}`, `QInt{W,C}` — F16's fix). Currently `QBool` stores
  `ctx::AbstractContext` (`src/types/qbool.jl`), forcing dynamic dispatch.
  **Under Option A, F16 is a hard prerequisite of M8**, not optional. Flagged.

**Option B — dedicated result constructors `ClassicalBit(q)` / `ClassicalWord(x)`.**
Always return the named wrapper; a separate op (`Bool(b)`) extracts a scalar in
trajectory mode. *Pro:* strong constructor consistency; one surface result type.
*Con:* two-step Eager use is cumbersome; `if ClassicalBit(q)` still cannot work;
"token" leaks into ordinary Eager code; more surface types.

**Option C — read-verb `observe(q)` / `readout(q)` / `q[]`.** Same semantics as
A, different verb. `measure` has the strongest quantum precedent; `read`/`q[]`
risk suggesting a non-destructive lookup, and `q[]` collides with `x[i]`
wire-addressing on `QInt`. `observe`/`readout` avoid the collision.

**Option D — retain `Bool(q)`/`Int(x)` returning tokens (status-quo PRD).**
*Pro:* no example churn; preserves the cast slogan verbatim. *Con:* a
constructor named `Bool` returns a non-`Bool`; return type depends on runtime
context (F16 failure at the busiest M8 site); `convert(Bool,·)` cannot be the
token path; `if token` is Julia's ugly native `TypeError`. **Not recommended.**

**Option E — macro/overdub rewrite of host `if`.** Rejected for M8: Jasp/JAX-
scale source surgery, semantics depend on whether the enclosing function was
rewritten, conflicts with the explicit-`cases` distinction, violates CLAUDE.md
rule 7.

### 4.3 Recommendation

**Adopt Option A, verb spelled `measure`.** It is the only option that keeps
`Bool`/`Int`/`convert` honest to Julia, makes the portable path a single idiom
`cases(measure(q))`, and is inference-clean once F16 lands. Mitigations for the
un-interceptable `if token`: (1) name the token type descriptively so the native
message reads `non-boolean (Outcome) …`; (2) own the recoverable footguns —
`convert(Bool, ::ClassicalBit)`, `Bool(::token)`, `getindex(::AbstractArray,
::ClassicalWord)` throw descriptive Sturm errors (§9.0 confirms we control
these), so `x::Bool = measure(q)` and `arr[t]` get a good message; only bare
`if t` / `t && …` stays Julia-native, and the portable idiom keeps users out of
that position.

> ⚠ **TOBIAS MUST RULE ON:** (a) the observation verb (`measure` vs `observe`
> vs `q[]`); and (b) whether `Bool(q)` / `Int(x)` **throw** vs silently degrade
> under DM/Tracing. The IR, join rule, and exact-DM semantics are valid under
> Options A–D; only the surface spelling and the §3.6/§3.8 vocabulary row change.

---

## 5. F30 — `@cases m` measurement sugar — RULING

**Ruling: `@cases` / `cases` take a *token*, never a raw quantum register;
measurement stays visibly spelled.** The normative form (under the recommended
F13 spelling) is:

```julia
@cases measure(m) begin … end          # or  cases(measure(m)) do … end
```

A register-accepting `@cases m` hides the P2 quantum→classical boundary
(measurement is an instrument; it must be spelled) and would create a second,
implicit measurement syntax — exactly what F30 flags. The macro evaluates the
selector expression **exactly once**, so the quantum handle is consumed once. A
bare quantum-register operand throws `ArgumentError` with a direct suggestion.

**On "visible sugar" (the two proposals split; adjudicated).** Proposal B would
permit `@cases m` *only* as visible sugar macro-expanding to `@cases measure(m)`
(so `@macroexpand` shows the measurement); Proposal A rejects even that.
**Decision: reject the register form for M8** (Proposal A's strict line). The
sugar's expansion depends on the verb Tobias picks (F13), and A's concern —
that even visible sugar smuggles a qc boundary into a construct documented as
"branch on a classical outcome" — is real. The visible-sugar ergonomic is
recorded as a **deferred option gated on the F13 ruling**, not shipped in M8.

The §7.6 injection examples become:

```julia
@cases measure(m) begin
    not!(dual(ψ))
end
```

Under `when`, `@cases` / `measure` remain **banned** (guardrail 1, the existing
`when.jl` row-10 forward hook — measurement under coherent control is
P4-forbidden). M8 must wire `cases`/`measure` through `_assert_no_control`.

---

## 6. Fit with the shipped context model

- `WireID` remains the quantum port identity; the `consumed` set
  (`abstract.jl:156`) remains the **single source** of quantum liveness —
  unchanged.
- `measure` still consumes the measured handle; the classical record is **new
  state**, realized under DM as the pinched live c-wire (`_instrument!`,
  `density.jl:135`), under Tracing as an SSA node. It must **not** be encoded by
  pretending a measured wire is still an ordinary quantum handle.
- Branch construction snapshots/forks region ownership + consumption metadata;
  branch-local region exit traces only branch-local owned wires
  (`_trace_and_free!`, §3.9).
- `when` guardrail 1 stands: `measure` and `cases` under a nonzero control stack
  are loud errors (`when.jl` rows 4–7, 10).
- The DM executor reuses `_instrument!`, `ctrl`/`_act!`, `_trace_and_free!` —
  **no new Orkan/kernel primitive** is introduced by M8's physics.

---

## 7. Proposed PRD replacement wording (paste-ready **after** the F13 ruling)

> **✅ APPLIED to `Sturm-PRD-v2.md` (session 98, bead `w5rw`), RE-SPELLED to
> Option D per §14.** These blocks are the historical Option-A staging;
> **do not paste them verbatim** — the shipped PRD wording (§3.6, §3.8, and
> the §7.1/§7.6 consequential edits) follows §14's consequential-re-spelling
> list: every `measure(q)` below reads `Bool(q)` (resp. `Int(x)`), the
> portable idiom is `cases(Bool(q))` / `@cases Bool(m)`, `ClassicalInt`
> reads `ClassicalWord{W}`, and L3's DM/Tracing *throw* is dropped (the cast
> returns a record/wire handle; only `convert(Bool, ·)` / typed `Bool` slots
> stay loud). The blocks are retained as the design record.

> The blocks below assume Option A (`measure`). If Tobias rules otherwise,
> substitute the chosen verb/spelling; the physics is unchanged.

### 7.1 Replacement for §3.6

> ### 3.6 Classical outcomes and `cases`
>
> A consuming observation is written `measure(q)`. Under an eager or explicit
> trajectory (`shots`) context it returns an ordinary Julia scalar. Under
> `TracingContext`, exact `DensityMatrixContext`, and hardware compilation it
> returns a symbolic **token** — a `ClassicalBit` or fixed-width
> `ClassicalWord{W}` — a handle to the instrument's classical record
> Σᵢ|i⟩⟨i|_C ⊗ ρ̃ᵢ (physically the measured wire, pinched and kept live).
>
> Tokens are **not** subtypes of `Bool`, `Integer`, or `Number`; they form a
> restricted finite SSA language. The circuit is built by ordinary Julia run
> **once** at build time — static loops, static indices, and widths are all
> concrete; the *only* non-concrete value is a token. A token may flow through:
> (T1) `cases`/`@cases` as a branch discriminant; (T2) the register's total
> finite-group primitives (`xor`/`⊻`/`!`/`~` on bits; `+`/`-`, constant `*`,
> constant shift mod 2^W, and static bit-slice on words; comparison against a
> build-time constant) producing new tokens; (T3) a bounded `select(t, table)`
> or a total `ClassicalTable` lookup; (T4) a classical return value. **Width
> changes are explicit.**
>
> A token in **control-flow or indexing position** — `if`/`&&`/`||`/`?:`/
> `while`, `arr[t]`, `iterate(t)`, an allocation size, value-dispatch, a
> process-value/`U2`/type-parameter/FFI argument — is rejected, mostly by
> Julia's own `TypeError`/`MethodError`, and by descriptive Sturm errors where
> Sturm owns the method. `if token` and short-circuit Boolean syntax produce
> Julia's native non-boolean `TypeError`; Sturm does not and cannot replace that
> message. This is dynamic lifting with a restricted classical layer — **not**
> arbitrary Julia compiled once. Under Eager, tokens do not exist: outcomes are
> scalars and ordinary `if` applies.
>
> Runtime classical branching is explicit:
>
> ```julia
> @cases selector begin
>     false => begin … end
>     true  => begin … end
> end
> ```
>
> The binary shorthand `@cases selector begin body end` means `true => body`,
> `false => identity`. Multiway cases use concrete disjoint labels plus an
> optional final `_` default and must cover the selector domain. The selector is
> evaluated **once**. `@cases` accepts a classical selector or an explicit
> observation (`@cases measure(m)`); a bare quantum register is rejected.
>
> Tokens are **copyable, not affine**: reusing a token in multiple `cases`
> refers to the same measurement record. Executors retain the joint record
> Σ_γ|γ⟩⟨γ|_C ⊗ ρ̃_γ until the distinguishing classical values are dead (their
> record traced out); **immediate summation of measurement branches while any
> token or derived value remains live is forbidden** — it destroys feed-forward
> correlation.
>
> Every `cases` arm begins with the same quantum environment and must end with
> the same quantum **port signature**: identical live `WireID`s, register
> shapes, consumed status, ownership, and borrow/view relationships. A port
> consumed in only some arms, a surviving branch-local allocation, or a
> branch-dependent returned handle is a loud join error. **`cases` returns
> `nothing`;** quantum φ values are not inferred, and a branch-dependent
> *classical* value is built with `select`. Wide feed-forward is a finite
> classical SSA over concrete unrolled structure — never an implicit 2^W-arm
> outcome table. Tracing lowers observation to `MeasureNode`, classical
> computation to typed SSA nodes, and branching to an acyclic `CasesNode` with
> nested channel regions; there are no symbolic loop backedges or general φ nodes
> in M8.

### 7.2 Replacement for §3.8 (surface table row 2 + portability)

> | # | Surface form | Role | Lowering |
> |---|---|---|---|
> | 2 | `measure(q)` — consuming; trajectory conveniences `Bool(q)` / `Int(x)` | quantum→classical observation | instrument + classical token |
> | 6 | `cases` / `@cases` | classical branching on outcomes | structured `CasesNode` |
>
> `@cases` accepts a classical selector or an explicit observation; a bare
> quantum register is rejected — write `@cases measure(m)`.
>
> Context portability:
>
> | Construct | Eager | Exact DM | Tracing | Hardware |
> |---|---|---|---|---|
> | prep, actions, `dual`, `when`, `oracle` | ✓ | ✓ | ✓ | ✓ |
> | `measure(q)` | scalar | token | token | token |
> | `Bool(q)` / `Int(x)` (scalar) | ✓ | ✗ | ✗ | ✗ |
> | host `if` / `&&` / `\|\|` on the outcome | ✓ | ✗ → `cases` | ✗ → `cases` | ✗ → `cases` |
> | whitelisted finite classical SSA | ordinary Julia | ✓ | ✓ | capability-checked |
> | `cases` / `@cases` | selected arm | all correlated arms (exact) | `CasesNode` | device conditional |
> | token-bounded loop / arbitrary token index | n/a after scalar | ✗ | ✗ | ✗ |
>
> `DensityMatrixContext` executes **channels, not trajectories**. For an
> instrument {𝓜ᵢ} and branch channels 𝓔ᵢ, exact branching denotes
> ρ ↦ Σᵢ 𝓔ᵢ(𝓜ᵢ(ρ)). A measurement therefore yields a **token**, never a
> scalar `Bool`; its classical record is the pinched, still-live wire, traced
> (summed) only at the token's last use — immediate block-accumulation would
> destroy feed-forward correlation. Scalar density-matrix measurement is
> available only through an explicit trajectory mode (`shots` over Eager, or a
> future `TrajectoryContext{DensityMatrixContext}` for noisy channels), which
> samples/normalizes one branch and is **not** an exact-channel execution mode.
> Completed hardware shot results are ordinary Julia values only *after*
> execution; mid-circuit hardware feedback remains token-plus-`cases`. Hardware
> compilation checks classical opcode, width, table, and dynamic-branch
> capabilities before submission; an unsupported feature is a compile error,
> never a silent lowering to host retrace or independent shots.

### 7.3 Consequential edits (non-§3.6/§3.8)

- §7.1 `&&` teleportation is **Eager/shot only**, not DM-portable; the portable
  form uses `cases(measure(dual(ψ)))` (or the deferred coherent variant).
- §7.6 replaces both `@cases m` occurrences with `@cases measure(m)`.
- D3 must drop the claim of arbitrary Julia indexing / dynamic loop bounds.
- The promise of a descriptive Sturm exception from `if token` becomes Julia's
  native `TypeError`.
- CLAUDE.md surface-row 2 follows the F13 ruling.

---

## 8. Named law tests (PRD-style; each a grep-able testset name)

- **L1 — Consuming Observation.** `measure(q)` consumes every measured port
  exactly once in every context; any later use of `q`, a view of `q`, or a
  parent register fails before state mutation. (extends `casts.jl` consumed
  test.)
- **L2 — Instrument Sum (F5).** Exact DM execution of `cases` denotes
  𝓔(ρ) = Σᵢ 𝓔ᵢ(𝓜ᵢ(ρ)); a one-run exact DM result equals a dense reference
  for small systems.
- **L3 — DM-scalar rejection (F5).** Under `DensityMatrixContext`, `Bool(q)` /
  `Int(x)` throw `ArgumentError`; `measure(q)` returns a token. (extends the
  shipped `_measure_wire!(::DM)` throw.)
- **L4 — cases-exact Choi (F5).** `Choi(teleport) ≈ Choi(id)` is a
  **deterministic one-run** DM assertion on a Z-sensitive input (|i⟩ or |+⟩);
  both `cases` arms provably evolve, Born-weighted.
- **L5 — Repeated-token correlation (F6).** For a fair `m = measure(q)`, two
  later `cases` on the same token stay correlated. Population form: X^m on a
  and X^m on b (both fresh |0⟩) gives ½|00⟩⟨00| + ½|11⟩⟨11|, **not** the
  independent mixture ¼ Σ over 00/01/10/11. Phase form (mandatory — pinched
  records are blind on diagonal inputs, the wm28 lesson): X^m on a and Z^m on
  b with b half of an entangled probe pair; the Choi of the composite must
  show the correlated X⊗Z record, not the product of marginal channels.
  *(Orchestrator review correction: the original statement applied X^m⊗Z^m to
  |00⟩ and claimed ½(|00⟩⟨00|+|11⟩⟨11|), but Z fixes |0⟩ — that output
  requires X^m on both wires; the Z-branch is only visible coherently.)*
- **L6 — Derived-token correlation (F6).** If `n = !m`, branches on `m` and `n`
  are perfectly anticorrelated; classical SSA creates no new stochastic record.
- **L7 — Classical-record forgetting (F6).** Summing hybrid rows is permitted
  only after the distinguishing SSA value *and every value derived from it* are
  dead; early coalescing followed by token reuse is rejected/caught by L5.
- **L8 — Branch-join identity (F6).** A `CasesNode` is constructible iff all arms
  present identical quantum port signatures (identity, liveness, shape,
  ownership, borrow/view).
- **L9 — Partial-consumption join rejection (F6).** One arm consuming a port
  another leaves live fails at the join, naming the port and the disagreeing
  arms (build-time under Tracing / run-time under Eager/DM).
- **L10 — Branch-local escape rejection (F6).** A branch-local owned register may
  not survive a join; returning distinct registers from different arms fails; no
  quantum φ is inferred.
- **L11 — Host-Boolean rejection (F4).** `if token`, `token && x`, `token || x`
  raise Julia's native non-boolean `TypeError`; no test expects a Sturm-
  dispatched exception from these.
- **L12 — Reject-branch/index (F4).** `arr[t]`, `for x in t`, `t₁*t₂` (two
  runtime tokens) throw (`MethodError`/`ArgumentError`/descriptive Sturm
  `error`), asserted with `@test_throws`.
- **L13 — No implicit domain expansion (F4).** A `ClassicalWord{W}` operation
  emits IR proportional to the *written* expression; branching on or comparing a
  word never creates 2^W arms.
- **L14 — Static-loop unroll (F4).** A `for j in 1:W` per-bit conditioned circuit
  (wide feed-forward, no 2^W table) builds and its DM channel matches the
  reference.
- **L15 — Static-table totality (F4).** A `ClassicalTable` lookup is accepted
  only when total for every possible index; incomplete lookup without a default
  fails during tracing.
- **L16 — Exact-vs-trajectory separation (F5).** An exact DM run is deterministic
  and returns the instrument sum; a density trajectory selects one normalized
  branch; a single trajectory is never accepted as an exact Choi evaluation.
- **L17 — Hardware capability (F5).** Compilation of unsupported classical
  opcodes/`cases` fails before submission, naming the missing capability; it
  never silently substitutes host retrace, outcome enumeration, or shots.
- **L18 — Channel barrier (F3).** No unitary-only pass may move, fuse, cancel, or
  compare across `MeasureNode`, `CasesNode`, discard, reset, or noise. Classical
  constant-folding/CSE may operate on the classical SSA graph without changing
  token provenance.
- **L19 — convert honesty (F13).** `convert(Bool, ::ClassicalBit)` throws a
  descriptive Sturm error (never a silent wrong `Bool`); `x::Bool = measure(q)`
  under Tracing throws, naming `cases`.
- **L20 — cases-not-measure (F30).** `@cases q` on an unmeasured register throws
  with a suggestion; `@cases measure(q)` works; measurement/`@cases` under
  `when` throws (guardrail 1).
- **L21 — streaming ≡ materialized (carried M5 IOU).** `when`-body streamed vs
  materialized to a unitary block compare equal at Choi; `CasesNode` blocks are
  **excluded** from unitary passes (F3 partition), compared channel-level.

---

## 9. Risks, verification, alternatives rejected

### 9.0 Julia-semantics verification (re-run this round)

Against the installed `julia`:

1. `Bool(::Tok)` returning a non-`Bool` **works** (constructor not enforced) —
   confirms F13 constraint 1.
2. `if Tok()` / `Tok() && true` → `TypeError: non-boolean (Tok) used in boolean
   context`; **not interceptable**, type name is **unqualified** (`Tok`, not
   `Sturm.Tok`) — confirms F13 constraint 3 and *tightens* Proposal B's claim
   (do not promise a `Sturm.` prefix in the message).
3. A typed `Bool` slot rejects a token (threw in the verified path) — confirms
   constraint 2; a token cannot silently occupy a `Bool` binding.
4. `arr[Tok()]` with no method → `ArgumentError`; a Sturm-owned
   `getindex(::Array, ::Tok)` throws a **descriptive** error — confirms we
   control the recoverable footguns. *(Proposal B labeled these `MethodError`;
   the exact exception type is `ArgumentError`/`MethodError` depending on path —
   immaterial, all loud.)*

### 9.1 Risks

- **R1 — exact classical records grow.** Exact channel execution necessarily
  retains every still-distinguishable measurement history; no representation
  erases correlation without changing the channel. The c-wire model spends **one
  Orkan slot per live token** until last use — physically correct (the record
  *is* a system), bounded by concurrent live tokens, and within the §3.8 Choi
  budget for every law test. Mitigations (SSA liveness, coalesce-after-last-use,
  sparse assignments, decision diagrams) are **optimizations**; M8 correctness
  holds without them.
- **R2 — `measure` return type varies by context (F16).** Accepted; it is a
  *function*, monomorphic within a context once handles carry `C`
  (`QBool{C}`/`QInt{W,C}`). **F16 is a hard M8 dependency under Option A.**
- **R3 — un-interceptable `if token`.** Cannot be fully fixed (§9.0). Best
  effort: descriptive type name + owned-method guards + a portable idiom that
  avoids branch position. Documented as a Julia-semantics limit, not a bug.
- **R4 — host side effects in branch closures.** Exact DM/Tracing construct
  every arm, so ordinary Julia side effects in a branch closure run at
  *construction* time, not conditionally at quantum runtime. Portable `cases`
  bodies should contain Sturm ops + whitelisted SSA only. A token cannot silently
  drive a side effect because it cannot become a host `Bool`, index, or bound.

### 9.2 Alternatives rejected

- **Staged dynamic lifting as default (F4 option 1).** Re-runs host effects per
  outcome; cannot yield one DM channel or one DAG; breaks one-run Choi. Kept only
  as the explicit `shots` mode.
- **Full Julia→classical-SSA tracer (Jasp parity).** Requires host source/AST
  surgery Julia lacks natively (CLAUDE.md rule 7). The restricted combinator EDSL
  covers teleport, injection, syndrome, and bit-uniform QROM without it.
- **Affine (use-once) tokens.** Classical outcomes are copyable; use-once breaks
  repeated feed-forward and syndrome processing. The explicit live-record model is
  strictly more expressive and physically exact.
- **Immediate branch accumulation.** Replacing the record by Σᵢρ̃ᵢ *while a token
  is live* turns correlated feedback into independent feedback — physically
  wrong. Legal only after the outcome is forgotten.
- **Separate sparse-hybrid-rows DM executor (Proposal A §3.4).** A valid
  denotation and a good *optimization*, but it needs a new block-diagonal
  executor structure the shipped single-dense-density-matrix Orkan backend does
  not provide; the c-wire model reuses `_instrument!`/`ctrl`/`_trace_and_free!`
  verbatim. Kept as a documented future optimization, not the M8 baseline.
- **Classical φ at the `cases` join (Proposal B `Phi` node).** `select`/
  `ClassicalTable` cover branch-dependent classical values with a simpler join
  rule (quantum-ports-only); rejected for M8.
- **Register-accepting `@cases m` (even as visible sugar).** Smuggles a qc
  boundary into a "branch on outcome" construct; deferred, gated on F13.
- **`Bool(q)` returning tokens (F13 Option D) / macro-overdub of `if`
  (Option E).** See §4.2.

---

## 10. Tobias rulings this design waits on

1. ⚠ **F13 — measurement spelling (blocking PRD wording).**
   (a) verb: `measure` (recommended) vs `observe` vs `q[]`;
   (b) do `Bool(q)` / `Int(x)` **throw** vs silently degrade under DM/Tracing.
2. **F13 dependency acknowledgement — F16 first.** Option A is inference-clean
   only with context-parameterized handles (`QBool{C}`, `QInt{W,C}`); confirm F16
   is scheduled **before** M8 cast work.
3. **(Informational, already ruled here, confirm)** F30: register-accepting
   `@cases m` rejected for M8; visible-sugar deferred and gated on (1).

Everything else in this document (F4 mechanism, F5 table, F6 tokens/record/join,
the c-wire DM realization, the law tests) is decided and ready for the
orchestrator's review; only the surface *spelling* rows depend on ruling (1).

---

## 11. Provenance (which piece came from A, B, or new)

| Piece | Source | Why |
|---|---|---|
| F4: restricted classical IR (reject staged lifting) | **A + B converged** | both derived it independently from the Julia-tracer impossibility |
| "token in data position, never control-flow/index position" rule | **B** §1.2 | crispest single-sentence boundary |
| Supported-subset detail: `ClassicalWord{W}` over `ClassicalInt`, `ClassicalTable` totality, explicit width changes | **A** §2.3–2.4 | finite-domain typing is more rigorous |
| Static-loop unroll / no-2^W-table QROM pattern | **A + B converged** | identical |
| F6: copyable tokens + explicit correlation record (reject affine) | **A + B converged** | classical info is copyable; M11 needs reuse |
| c-wire denotation as the **DM executor** realization | **B** §2.1 | reuses `_instrument!`/`ctrl`/`_trace_and_free!`; fits shipped single-dense-DM Orkan; deferred-measurement exact |
| Abstract σ_CQ = Σ_γ\|γ⟩⟨γ\|⊗ρ̃_γ as the **denotational meaning** | **A** §3.2 | the executor-independent spec every backend must match |
| Join-typing rule (quantum port signature, `cases` returns `nothing`) | **A + B converged**, enumerated form from **A** §3.6 | crisper clause list |
| Classical conditionals via `select` (no `cases` phi) | **A** | simpler join; syndrome path needs only `select`/`ClassicalTable` |
| F5: DM returns token, `if`/`&&` rejected, scalar only in trajectory | **A + B converged** | matches shipped `_measure_wire!(::DM)` throw |
| Shot surface = `shots` over Eager (M8 baseline) | **B** §3.3 | Eager already IS the trajectory context; minimal |
| `TrajectoryContext{DM}` for noisy trajectories | **A** §4.2, scoped as future | needed only once Kraus noise lands |
| F13: Option A `measure` recommended; full option space; TOBIAS flag | **A + B converged**; F16-dependency emphasis from **B** R2 | both recommend A independently |
| F13 Julia facts | **A + B**, **re-verified this round** (§9.0) | tightened B's unqualified-type-name claim |
| F30: register form rejected for M8, visible-sugar deferred | **A** (strict) over **B** (permit visible sugar) | A's qc-boundary concern + sugar depends on unresolved F13 |
| Law-test suite (L1–L21) | merged from **A** §7 (17 laws) + **B** §6 (10 laws) | union, deduplicated |
| PRD §3.6/§3.8 replacement wording | synthesized, closest to **A** §8 | A's blocks were paste-ready; merged B's c-wire paragraph |

---

## 12. Addendum (session 98, dialogue with Tobias) — postselection, effects, and subnormalized DM states

Raised by Tobias against §2/§3: a PVM branch **is** executable in the DM
context as a CP but non-TP map — ρ ↦ P_b ρ P_b, tr = p_b, state
subnormalized — and there are often reasons to prefer this (heralded
protocols, success probabilities, conditional-state analysis). Question:
does admitting it contradict the record semantics above?

**Resolution: no contradiction — the branch map FACTORS THROUGH the
record.** ρ ↦ P_b ρ P_b is exactly (1) the TP instrument
ρ ↦ Σᵢ |i⟩⟨i|_C ⊗ P_i ρ P_i (the §2 record), followed by (2) the
classical **effect** ⟨b| on the record wire: (⟨b|⊗I)(·)(|b⟩⊗I). The
non-TP part is a classical co-state; the record is the universal object
from which every outcome-conditioned CP map is derived by pairing the
c-wire with an effect. Postselection therefore needs no new measurement
primitive — it strengthens the case for the record being the primitive.

**The three-meanings observation (sharpens F13).** "Measurement returns
a `Bool` in DM-land" now has three physically coherent readings:
1. **sample** it — Born-rule dice; Eager/trajectory only;
2. **record** it — TP instrument; the DM native semantics (§2);
3. **assert** it — postselect: the outcome is an *input*, the state pays
   tr = p_b. Produces a definite `Bool` with *no* sampling.
One spelling silently covering any two of these is the
silent-wrongness pattern the project exists to kill. Whatever F13
spelling is ruled, sample/record/assert must be **three distinct surface
operations**.

**Normative consequences (design commitments, pending PRD wording):**
- DM native execution **stays TP-record**; nothing in §2–§3 changes.
- Effects are an **explicit opt-in surface** (working name
  `postselect(record, v)`; final spelling is an F13-adjacent ruling),
  never a mode of a cast. The result visibly carries or exposes the
  weight p; entering the CP-TNI regime is always loud in the source.
- **Banned under `when`** like every qc-boundary op (controlled
  postselection is as unrepresentable as controlled measurement);
  guardrail 1 covers it with no change.
- **P1 wording**: if/when effects are surfaced, the P1 generator list
  (post-rlhj "generated by" form) gains *classical effects /
  postselection*, and the honest denotation class widens from CPTP to CP
  trace-non-increasing, with tr carrying the accumulated postselection
  probability (weights multiply under composition). Gated PRD edit.
- **Law-test discipline**: Choi law tests stay on TP record semantics by
  default. A postselected comparison must **declare its weight
  convention** — raw J (weights significant, tr J = p·d) vs conditional
  J/p — explicitly; a silent choice is a wm28-class blindness.

**Additional named law tests:**
- **L22 — Effect factorization.** `postselect(measure(q), b)` denotes
  ρ ↦ P_b ρ P_b exactly (record-then-effect ≡ direct branch map);
  verified densely on small fixtures.
- **L23 — Weight composition.** Two sequential postselections compose
  with tr = p₁·p₂|₁ (the chain rule); the weight of a composite equals
  the probability of the joint postselection history.
- **L24 — No silent subnormalization.** Every API that assumes TP input
  (Choi law harness, `same_process`, guardrail witnesses) rejects a
  subnormalized state loudly; subnormalization is reachable only through
  the explicit effect surface.

Tracked as bead `eyho` (postselection/effects surface, M8-or-later);
the F13 ruling brief is updated with the three-meanings observation.

---

## 13. Addendum 2 (session 98, dialogue with Tobias) — why the contexts exist, and the traceable-subset argument

**The context trichotomy (Tobias's framing, adopted).** The three contexts
exist for categorically different reasons, and the PRD should say so as a
"why contexts" preamble (staged wording, lands with the F13 package):

1. **Eager — runtime semantics.** The execution model of hardware capable
   of projective *mid-circuit* measurement with feed-forward (trapped
   ions et al.), and the prototyping/shot-statistics simulator. Outcomes
   are real at the moment they occur; values flow; host `if` works.
   Hardware relates to Eager at *runtime only* — device programs are
   compiled via Tracing, then execute Eager-like.
2. **DM — physical denotation.** The platonic state of the system under
   channels: the normative semantics, where law tests (one-run Choi) and
   correctness licenses live. The record semantics of §2 **is the
   principle of deferred measurement expressed as types**: the record
   wire is "the measurement not yet read," carried as correlation until
   last use.
3. **Tracing — the compiler.** The IR for optimization reasoning.
   Measurement is a first-class named node with a Bool-typed output
   wire; `cases` nodes are its consumers; both are the barriers of the
   5hr7 pass discipline. Canonical measurement optimizations: the
   **deferred-measurement rewrite** (for no-MCM backends: measure +
   `cases`-on-record → coherent control off the unmeasured wire +
   terminal measurement; license = Choi equality, defined in DM) and
   **dead-record elimination** (record never consumed ⇒ measurement is
   pinching; wire subsequently traced ⇒ node chain collapses to trace).

**Registered pushback (for accuracy):** the cast is not uninteresting on
no-MCM hardware — terminal readout is still the cast, and the boundary
algebra (qc∘cq = id, cq∘qc = pinching) is context-independent normative
structure. What is MCM-specific is the *value-returning, branch-on-it*
usage.

**The traceable-subset argument (sharpens F13, distinct from the Julia-
convention argument).** The IR node identity is spelling-independent —
a measure node is recorded whether the user wrote `Bool(q)` or
`measure(q)`, so "the compiler needs to see it" does not by itself
discriminate the F13 options. The genuine surface consequence is
**program classification**: a program branching via host `if Bool(q)` is
Eager-pinned and *cannot* be traced even in principle (the trace would
record one branch); a program in token+`cases` vocabulary traces,
optimizes, and ports. Under a split vocabulary (Option A family) that
boundary is **lexical** — visible at a glance, mechanically lintable.
Under a single spelling (Option D) the same text is traceable or not
depending on how the result is *used*, discovered at trace time by
failure. Status of the F13 axis after sessions-98 dialogue:
- **Option D gained a principled foundation** (one channel, one
  spelling; the cast returns the classical system, represented as
  faithfully as the context allows: value/point ↔ record/distribution ↔
  wire/no-state);
- **Option A gained the traceable-subset argument** (the spelling marks
  the compiler-food subset).
Both are coherent; the ruling (bead `vqas`) is now a clean choice
between these two positions, with the three-meanings rule (§12)
holding under either.

---

## 14. RULINGS (2026-07-21, Tobias, session 98) — F13 = OPTION D; all standing recommendations adopted

**F13 RULED: Option D — one spelling.** `Bool(q)` / `Int(x)` are THE
measurement spelling in every context. The cast denotes the q→c channel;
its return is the classical system that channel outputs, represented as
faithfully as the context allows: **value** (Eager — a point state IS its
value), **record handle** (DM — distribution inside ρ), **wire handle**
(Tracing — no state yet). This is a **registered exception** to the Julia
constructor convention, adopted knowingly alongside `not!` and the view
op-assigns (CLAUDE.md Julia conventions #2 gains this entry). The
three-meanings rule (§12) stands: sample (Eager-native) / record (the
cast, everywhere) / assert (`postselect`, explicit) remain distinct
operations.

**Consequential re-spellings of this document's Option-A-form statements**
(the body above is the historical record; these deltas govern):
- Every `measure(q)` in §§1–8 reads `Bool(q)` (resp. `Int(x)`); the
  portable idiom is `cases(Bool(q))` / `@cases Bool(m)` — which lands F30
  back on the original review's preferred form.
- **L3 re-spelled:** under DM/Tracing `Bool(q)` does NOT throw — it
  returns the record/wire handle. What remains loud: `convert(Bool, ·)`
  (the P2 implicit-cast path) stays Eager-only — typed `Bool` slots
  re-check and throw (§9.0 fact 2), and the owned-method guards
  (`convert(Bool, ::ClassicalBit)` etc.) carry descriptive errors.
  `if Bool(q)` under DM/Tracing dies with Julia's native TypeError on
  the handle type — mitigated by descriptive type naming only (§4.3).
- The **traceable-subset boundary is use-site-dependent under D**
  (accepted cost, §13): a program is compiler-food iff its outcomes flow
  only through T1–T4. Mitigation: this is mechanically checkable at
  trace time and SHOULD become a tracer pre-flight lint listing each
  offending use site, since it cannot be lexical.
- **F16 is now even harder a prerequisite**: the context-varying return
  of `Bool(q)` itself demands `QBool{C}`/`QInt{W,C}` for inference-clean
  hot paths — scheduled as an explicit pre-M8 work item.

**Also ruled (recommendations adopted wholesale):**
- **D15 (xy4w)** = option (b): `QBool(p, φ)` literals under `when` are
  admitted only inside a certified compute/uncompute unitary block whose
  ancilla the §3.9 witness cleans; loud error naming D15 otherwise.
- **TR1–TR8 (z1sa)**: all standing recommendations — square
  `UnitaryBlock{N}` + rename; tee+poison Eager failure; `within` is
  `public` kernel API, not an 8th surface construct; conservative
  combinator-carried certificate set; `Perm`/`MCX` freeze to `NTuple`;
  oracle targets full-width + structural range certificate (governs
  `fy8l`); `PhaseDelta` kernel-internal, zero-port blocks forbidden;
  `denoted_matrix` memory-budget cap.
- **Effects surface (eyho)**: spelling `postselect(record, v)`, explicit
  opt-in, weight visible (§12 commitments unchanged).
- **F15/F19 (4c0j)**: numeric-contract wording → "number-like handles"
  trait; bicharacter trait as recommended. **F16**: pre-M8 refactor,
  scheduled.
- **F31 PRD follow-up (ne0d)**: approved as recommended.
