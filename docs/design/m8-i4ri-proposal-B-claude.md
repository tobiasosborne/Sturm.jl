# Design Proposal — M8 classical-control IR (bead i4ri)

Proposer: Claude (blind proposal, 3+1 round). Read-only analysis of
`Sturm-PRD-v2.md`, the GPT-5.6 review (F4/F5/F6/F13/F30), the M8/M11 plan,
and `src/{context,surface,types}`. Every Julia-semantic claim below was run
against the installed `julia` binary; the transcripts are cited inline.

---

## 0. One-paragraph thesis

There is **one physical object** underneath F4/F5/F6, and naming it collapses
the whole gate: the classical record of an instrument,
Σᵢ |i⟩⟨i|_C ⊗ ρᵢ. Sturm already builds it — the shipped DM `_instrument!`
pinch (`density.jl:135`) produces exactly Σᵢ Pᵢ ρ Pᵢ on the measured wire, and
the shipped `ctrl`/`when` machinery already applies operations conditioned on a
wire. **A measurement token is a handle to a pinched-but-still-live classical
wire; `cases` is `ctrl` off that wire; the token dies (its wire is traced =
Σᵢ summed out) at its last use.** This single denotation answers "what does the
IR store" (b), makes DM branching exact-channel (c), and reuses existing kernel
code. The classical-control *mechanism* (a) is then a **restricted combinator
EDSL over that record** — never a general host tracer, because Julia cannot
trace `if`/`for`/indexing on a symbolic value (verified below), and pretending
otherwise is precisely F4's bug.

---

## 1. (a) F4 — the classical-control mechanism

### 1.1 The choice, and why

F4 forces a choice between (1) **staged dynamic lifting** (stop, read outcome,
resume/retrace a continuation) and (2) a **restricted classical SSA/CFG IR**.
The PRD §3.6 text ("a `ClassicalInt` flows through ordinary Julia
arithmetic/indexing, compiled once … dynamic loop bounds and indices") is a
*third, non-existent* option: it presumes Julia can trace arbitrary host code
on a symbolic value the way Jasp's JAX tracer traces Python. It cannot. Verified:

- `if token` and `token && x` throw `TypeError: non-boolean (T) used in
  boolean context` — Julia lowers boolean context to an *internal* type check
  with **no overloadable hook**; the throw cannot be intercepted or its message
  customized (only the type name `T` is surfaced). (transcript `jltest.jl`,
  `jltest2.jl`.)
- `for x in token` / `arr[token]` require `iterate`/`getindex` methods that
  take concrete values; with none they `MethodError` (`jltest3.jl`).

Jasp compiles-once only because qrisp rewrites Python **source/AST** into JAXPR
before tracing; that is a whole-language metacircular compiler. Sturm has no
such layer and rule 7 ("if a construct fights the host language, the construct
is wrong") forbids building one via `@generated`/`IRTools` source surgery for
the general case. **So option (2), sharply restricted.** Staged retrace (1) is
rejected as the *default* because it re-executes host effects per outcome
(non-idempotent user code runs twice) and cannot produce a single channel/DAG
for DM/Tracing/Hardware; it survives only as the explicit shot mode of §3 (c).

### 1.2 The precise supported subset

The circuit is still built by **ordinary Julia executed once at trace/build
time**. Everything with a value known at build time (static loop bounds like
`for i in 1:W`, static indices `x[i]`, register widths, `ntuple`, dispatch on
types) runs concretely and unrolls normally — verified: a `for i in 1:W` loop
over symbolic-bit algebra builds a node with no trouble (`jltest3.jl`). The
**only** thing not concrete at build time is a **measurement token**. A token
may flow through exactly these channels:

| # | Token use | Lowering | Denotation |
|---|---|---|---|
| T1 | `cases(t) do … end` / `@cases` | `ctrl` off the token wire | Σᵢ\|i⟩⟨i\|_C ⊗ 𝓑ᵢ (§2) |
| T2 | whitelisted **total** classical primitives → new token | classical SSA node | pure function of the label i |
| T3 | `select(t, (a₀,a₁,…))` bounded multiplexer | one `cases` fanned over a static tuple | Σᵢ\|i⟩⟨i\| ⊗ actionᵢ |
| T4 | classical **return** value of the reified function | classical output port | classical wire escapes as record |

Whitelisted T2 primitives are the **finite-abelian-group operations of the
register's own dual structure (§3.4/D12)** plus static bit-slicing — all total,
bounded fan-in, side-effect-free:

- `ClassicalBit`: `xor`, `⊻`, `!`/`~` (the Pauli-frame algebra — this is all
  teleportation and the injection ladder need).
- `ClassicalInt{W}`: `+`, `-`, and multiply/shift **by a build-time constant**,
  all mod 2^W; static bit extraction `t[i]::ClassicalBit` for a build-time `i`
  (this is *field access on the bit register*, not array indexing).
- comparison of a `ClassicalInt` to a **build-time constant** → `ClassicalBit`
  (a `cases` guard).

Wide QROM/MBU (F4's motivating worry) is expressible **without a 2^W table**:
the classical value parameterizes a circuit *uniform in its bits* — a static
`for j in 1:W` loop that per-bit classically-controls a kernel operation
(`cases(t[j]) do … end`), exactly the semiclassical/Pauli-frame pattern. The
`select` combinator (T3) is offered only for genuinely enumerated small tables
and its fan is bounded by a build-time tuple length, never by 2^W.

### 1.3 The loud-rejection boundary (F4 demands it be explicit)

Anything not T1–T4 is rejected, and most rejections are **free — Julia throws
first**:

- `if t`, `t && x`, `t || x`, `t ? a : b`, `while t` → Julia `TypeError`
  (native, non-interceptable). We *document* this as the token-in-branch error
  and name the token type so the message reads `non-boolean (Sturm.Outcome)
  used in boolean context` (verified the type name propagates, `jltest2.jl`).
- `arr[t]`, `t:end`, `iterate(t)`, `rand(t)`, allocation sized by `t`,
  dispatch-on-value: no method exists → `MethodError`. Where we **own** the
  method (`getindex(::AbstractArray, ::ClassicalInt)`, `getindex(::Tuple, …)`)
  we define a fallback that throws a *descriptive* Sturm error pointing to
  `select`/`cases` (verified working, `jltest3.jl`).
- `t₁ * t₂`, `t₁ ÷ t₂` (two runtime tokens through a non-group op) → **not
  whitelisted**, descriptive `error()`: "combining two measurement outcomes
  through `*` needs a quantum arithmetic circuit before measurement, or a
  `select`; classical post-processing is limited to the register's group
  operations (§3.6)."

The rule stated once: **a token may sit in data position (through T1–T4) but
never in control-flow or indexing position.** This is dynamic lifting with an
honestly-bounded classical layer — the Jasp model minus the host-language
tracer Julia does not have.

---

## 2. (b) F6 — token & join semantics; what the IR stores

### 2.1 The token is the classical record (physics)

An instrument keeping its outcome is
ρ ↦ Σᵢ (Pᵢ ρ Pᵢ) — the measured wire, **pinched not discarded**, *is* the
classical register C carrying Σᵢ|i⟩⟨i|_C ⊗ ρᵢ. This is the shipped
`_instrument!` channel (`density.jl:119–139`). So:

> **A `ClassicalBit`/`ClassicalInt` token is an owning handle to a
> pinched-but-live classical wire (the "c-wire").** Under Tracing it is an SSA
> value naming that wire's node; under DM it is that wire; under Eager (§3) it
> is a plain scalar.

`cases`/classical-control lowers to `ctrl` **off the c-wire**. Because the
c-wire is already dephased, coherent `ctrl` off it is *exactly* classical
control (off-diagonals are already zero, so deferred-measurement is exact):
cases(t) do B end  ⟼  Σᵢ |i⟩⟨i|_C ⊗ 𝓑ᵢ(·).
This is **not** banned by guardrail 1 (which forbids *measurement/trace/noise*
under `when`): controlling off an existing classical wire is a unitary-witnessed
`ctrl`, not a new instrument.

### 2.2 Affine tokens vs explicit record — DECISION: explicit record

F6 asks: affine (use-once) tokens, or an explicit correlation record? **Explicit
record.** A classical outcome is physically *copyable* (fan-out is free); forcing
tokens affine would break repeated feed-forward, syndrome processing, and the
teleport double-correction where one measurement drives both an X and a Z fix.
Instead:

- **Quantum handles stay affine** — enforced by the *existing* single-sourced
  `consumed` set (`abstract.jl:154–158`, §4.5). Unchanged.
- **Classical tokens are freely reusable**, but their c-wire is **owned**. The
  correlation Σᵢ|i⟩⟨i|⊗ρᵢ is retained *in the live c-wire* until the token's
  **last use**, at which point the c-wire is traced (= Σᵢ summed = the
  "block-accumulate" the PRD wanted, now correctly *deferred to last use*).
  Immediate block-accumulation — F6's bug — is exactly tracing the c-wire too
  early; the fix is: **never trace the c-wire before the token is dead.**

Last-use is decided by the existing region/ownership machinery: a token is dead
at region exit (its c-wire is an owned local → `_trace_and_free!`, §3.9) or at an
explicit `discard(t)`. Two `cases` on the same token both `ctrl` off the one
live c-wire ⇒ the joint channel keeps Σᵢ|i⟩⟨i|⊗(𝓑'ᵢ∘𝓑ᵢ) ⇒ correlation
preserved by construction.

### 2.3 The join-typing rule (exact)

> **Cases join.** `cases(t) do … end` has branches {𝓑ᵢ}, one per value i of
> discriminant token `t`; each branch runs in its own §3.9 region. After each
> branch's owned-and-unreturned locals are traced to a common signature, the
> join is well-typed **iff every branch presents (1) the identical set of live
> quantum register identities with identical ownership and width — the *output
> port signature* — and (2) type-compatible classical outputs (a classical
> phi).** A branch that consumes a handle another leaves live, or returns a
> different register set, or measures inside a branch under a live control, is a
> **loud error** (build-time under Tracing, run-time under Eager/DM). The node
> denotes 𝓔(ρ) = Σᵢ (|i⟩⟨i|_C ⊗ id)·(𝓑ᵢ ⊗ id)·(Pᵢ ρ Pᵢ ⊗ |i⟩⟨i|_C), with C
> the retained c-wire, traced at `t`'s last use.

### 2.4 IR record shapes (Tracing)

```
Token          := CBit(node) | CInt{W}(node)         # SSA name of a c-wire
ClassicalNode  := Measure(wire)                       # birth: pinch + keep
                | XorB(Token,Token) | NotB(Token)     # T2 group algebra
                | AddC(Token,Token) | ShlC(Token,Int) | BitC(Token,Int) | …
                | Phi(branch_outputs)                 # cases join, classical
CasesNode      := disc :: Token                        # the c-wire(s)
                  branches :: NTuple{K, Unitary/ChannelDAG}  # identical port sig
                  ports_in :: PortSig                  # asserted == across branches
                  ports_out :: PortSig                 #   "
                  last_use :: Bool                     # if true, trailing trace(C)
```

`CasesNode` is a **channel node**, not a unitary block: it contains a genuine
instrument (measurement barrier). It must therefore live on the channel side of
the F3 partition — no unitary-only pass may cross it (CLAUDE.md "Channel IR vs
Unitary Methods"). The `ports_in/out` equality check is the mechanical form of
the §2.3 rule and is the single site that enforces linearity at the join.

Under DM the same structure is *executed* rather than stored: `Measure` →
`_instrument!` (pinch, keep wire); `CasesNode` → `ctrl`-off-c-wire over each
branch, block-accumulated by Orkan's linearity; `last_use` → `trace_wire!`.
Reuses `_instrument!`, `ctrl`/`_act!`, and `_trace_and_free!` — **no new physics
primitive.**

---

## 3. (c) F5 — corrected DM portability table + shot mode

### 3.1 Why the shipped code is right and the table is wrong

For instruments 𝓜ᵢ(ρ)=PᵢρPᵢ, exact DM execution must evolve **all** branches:
𝓔(ρ)=Σᵢ 𝓔ᵢ(𝓜ᵢ(ρ)). A scalar `Bool` selects one i and renormalizes — a
*trajectory*, not a channel. Ordinary Julia `if` can only run the selected
branch; it cannot form the sum. The shipped `_measure_wire!(::DensityMatrix…)`
already throws (`casts.jl:115–121`) — correct. **The table is wrong; the code is
right.**

### 3.2 Corrected §3.8 context-portability table

The controlling axis is **scalar-outcome (trajectory/shot) vs token
(channel/circuit)**. Eager unravels one trajectory, so its outcomes are scalars
and host `if` works. DM builds a channel, Tracing builds a circuit, Hardware
builds a device program — all three yield tokens and branch through `cases`.

| Construct | Eager | DM | Tracing | Hardware |
|---|---|---|---|---|
| casts (cq), action family, `dual`, `when`, `oracle` | ✓ | ✓ | ✓ | ✓ |
| `Bool(q)` / `Int(x)` return a **scalar** | ✓ | ✗ (token) | ✗ (token) | ✗ (token) |
| `measure(q)` (token verb, §4) | ✓ (Bool) | ✓ (token) | ✓ (token) | ✓ (token) |
| `if` / `&&` on a measured outcome | ✓ | ✗ → `cases` | ✗ → `cases` | ✗ → `cases` |
| `cases` / `@cases` | ✓ | ✓ (exact, all branches) | ✓ (`CasesNode`) | ✓ (device cond.) |

`cases` is the **one fully portable** branch construct (works in Eager too — it
runs the taken branch). `if`/`&&` is the Eager-only ergonomic shortcut, valid
exactly where outcomes are scalars.

### 3.3 Shot/trajectory mode surface — minimal, no new branching

Do **not** invent a second branching surface. Scalar-`Bool` branching *is* the
Eager (trajectory) contract. To sample trajectories of an otherwise-channel
program, run it under Eager (or a Kraus-sampling Eager for noise) via an explicit
HOF:

```
sample(f, args...; shots=N)   # runs f under trajectory (Eager) unraveling N×,
                              # collecting scalar outcomes / return values
```

`sample` executes the program in scalar-outcome mode, so ordinary `if`/`Bool(q)`
inside `f` work and each shot is one trajectory. This keeps DM/Tracing/Hardware
strictly channel/circuit-valued and confines every scalar-`if` program to the
trajectory contract, where it is physically honest. (This also gives F25 relief:
large channels that cannot be Choi-tested are estimated by `sample`.)

---

## 4. (d) F13 — `Bool(q)` return convention — **TOBIAS RULING REQUIRED**

### 4.1 The three verified constraints

1. Julia does **not** enforce that `Bool(x)` returns `Bool` — a constructor may
   return anything (`Bool(Tok)` returned a `CBit`, `jltest.jl`). So
   `Bool(q)::ClassicalBit` under Tracing is *mechanically possible* but breaks
   the reader's contract that `Bool(·)` yields a `Bool`.
2. `convert(Bool, q)` **cannot** return a non-`Bool`: typed slots / struct
   fields / `::Bool` returns re-check the result and throw `TypeError`
   (`x::Bool = CBit(1)` threw even with a custom `convert`, `jltest2.jl`). So the
   implicit-measurement path `convert(Bool,q)` (`casts.jl:134`) is **incompatible
   with a token-returning cast** — under Tracing/DM there can be no
   token-producing `convert(Bool, …)`.
3. The promised "descriptive error on `if token` pointing to `cases`" is
   **unimplementable**: `if token` throws Julia's native, non-interceptable
   `TypeError`; only the token's *type name* is surfaced (`jltest.jl`).

### 4.2 Option space

**Option A — separate token verb; `Bool`/`Int` stay honest scalar casts
(RECOMMENDED).**
`measure(q)` (and `measure(x::QInt)`) is the token-producing observation:
returns a real `Bool`/`Int` under Eager, a `ClassicalBit`/`ClassicalInt` token
under DM/Tracing/Hardware. `Bool(q)`/`Int(x)` remain the **scalar** casts, valid
only where a scalar is honest (Eager/shot); under DM/Tracing they throw pointing
to `measure`/`cases`. Portable idiom everywhere: `cases(measure(q)) do … end`.
- *Pro:* `Bool` always returns `Bool` (convention preserved); `convert(Bool,·)`
  stays honest and Eager-only; casts (P2 boundary) and observations are cleanly
  separated; type-stable **per context** once handles carry their context
  (F16's `QBool{C}` fix — a required dependency).
- *Con:* two spellings for "measure"; §7 examples change (`Bool(dual(ψ))` →
  `measure(dual(ψ))` for portability); `measure` return type varies across
  contexts (acceptable for a *function*; each context is monomorphic).

**Option B — context-dependent `Bool(q)` (status quo PRD text).**
- *Pro:* one spelling; no example churn.
- *Con:* violates constructor convention; return type depends on runtime
  context (F16 inference failure at the busiest M8 site); `convert(Bool,·)`
  cannot be the token path (breaks the implicit-cast story under Tracing); the
  `if token` error is Julia's ugly native `TypeError`. The review condemns this.

**Option C — read-verb spelled `q[]` / `observe(q)`.** As A but the verb is
`getindex`/`observe`. `q[]` reads nicely ("read the register") and cannot be
confused with a cast, but overloads `getindex` on a register (collides with
`x[i]` wire-addressing on `QInt`). `observe`/`readout` avoid the collision.

### 4.3 Recommendation (for Tobias to rule)

**Adopt Option A**, verb spelled **`measure`**. Rationale: it is the only option
that keeps `Bool`/`Int`/`convert` honest to Julia, makes the portable path a
single idiom `cases(measure(q))`, and is inference-clean once F16's context
parameter lands. Mitigation for the un-interceptable `if token`: (1) name the
token type so the native message reads `non-boolean (Sturm.Outcome) used in
boolean context`; (2) **do** own the recoverable footguns —
`convert(Bool, ::ClassicalBit)` and `getindex(::AbstractArray, ::ClassicalInt)`
throw *descriptive* Sturm errors (verified we control these, `jltest2/3.jl`), so
`x::Bool = measure(q)`, `::Bool` returns, and `arr[t]` all get a good message;
only the bare `if t`/`t && …` remains Julia-native, and the portable idiom keeps
users out of that position. **Tobias must rule on: verb spelling (`measure` vs
`observe` vs `q[]`), and whether `Bool(q)`/`Int(x)` throw vs silently degrade
under DM/Tracing.** Do not merge this without his idiomaticity call.

---

## 5. (e) F30 — `@cases m` measurement sugar — RULING

**Ruling: `@cases`/`cases` take a *token*, never a raw register; measurement
stays a visible cast.** `@cases measure(m) begin … end` (or
`cases(measure(m)) do … end`) is the normative form. A register-accepting
`@cases m` hides the P2 quantum→classical boundary (measurement is an
instrument; it must be spelled) and would make measurement a second, implicit
syntax — the exact overloading F30 flags.

If ergonomics are wanted, permit `@cases m begin … end` **only** as *visible*
sugar that macro-expands to `@cases measure(m)` with the `measure` call
syntactically present in the expansion (so `@macroexpand` shows the
measurement). This keeps "measurement is always spelled" true at the source
level. Recommend shipping the strict token form in the §7.6 examples; the sugar
is optional and gated on the §4 ruling (it must expand to whatever verb Tobias
picks). Under `when`, `@cases`/`measure` remain **banned** (guardrail 1, the
existing `when.jl:70` forward hook — measurement under control is P4-forbidden).

---

## 6. Named law tests (PRD-style exact statements)

1. **L-DM-scalar (F5).** Under `DensityMatrixContext`, `Bool(q)` and `Int(x)`
   throw `ArgumentError`; `measure(q)` returns a token. *(extends the shipped
   `casts.jl:115` test.)*
2. **L-cases-exact (F5/c).** `Choi(teleport) ≈ Choi(id)` is a **deterministic
   one-run** DM assertion, probed on a Z-sensitive input (|i⟩ or |+⟩, §3.8);
   both `cases` branches provably evolve (Born-weighted).
3. **L-cases-correlation (F6).** A channel that measures `m=measure(q)` once and
   applies `X^m` to q₁ **and** `Z^m` to q₂ equals the correlated channel
   Σₘ|m⟩⟨m|⊗(Xᵐ⊗Zᵐ), **not** the product of independently-averaged branches.
   Discriminating probe: an entangled input where losing the correlation changes
   the Choi. *(The direct executable statement of Σᵢ|i⟩⟨i|⊗ρᵢ retention.)*
4. **L-join-ports (F6).** A `cases` whose branches disagree on live output port
   set/ownership throws loud — build-time (Tracing) / run-time (Eager/DM). A
   branch that consumes a handle another leaves live is the pinned negative.
5. **L-token-record (F6/b).** After `cases`, before token death, a second
   `cases` on the same token observes the correlation (test 3 with the two uses
   *split* across two `cases`); after explicit `discard(t)` the c-wire is traced
   and Σᵢ is taken (a subsequent use of `t` throws use-after-discard).
6. **L-reject-branch (F4).** `if t`, `t && x`, `t || x` throw Julia `TypeError`;
   `arr[t]`, `for x in t`, `t₁*t₂` throw (`MethodError` / descriptive Sturm
   `error`). Asserted with `@test_throws`.
7. **L-static-ok (F4).** A `for j in 1:W` per-bit classically-controlled circuit
   (wide feed-forward, no 2^W table) builds and its DM channel matches the
   reference — the positive of test 6.
8. **L-convert-honest (F13).** `convert(Bool, ::ClassicalBit)` throws a
   descriptive Sturm error (never a silent wrong `Bool`); `x::Bool = measure(q)`
   under Tracing throws with a message naming `cases`.
9. **L-cases-not-measure (F30).** `@cases q` on an unmeasured register throws (or
   `@macroexpand @cases q` shows an explicit `measure`); `@cases measure(q)`
   works. Measurement/`@cases` under `when` throws (guardrail 1).
10. **L-streaming≡materialized (carried M5 IOU).** Unchanged: `when`-body
    streamed vs materialized to `CasesNode`-free unitary block compare equal at
    Choi — but note `CasesNode` blocks are **excluded** from unitary passes (F3
    partition).

---

## 7. PRD wording changes (precise replacement text)

**§3.6, replace the "ordinary Julia arithmetic/indexing … compiled once"
sentence with:**

> Under `TracingContext`/`DensityMatrixContext`, `measure(q)` returns a
> classical **token** (`ClassicalBit`/`ClassicalInt`) — a handle to the
> instrument's classical record Σᵢ|i⟩⟨i|_C ⊗ ρᵢ, physically the measured wire
> pinched and kept live. The circuit is built by ordinary Julia run **once** at
> build time (static loops, static indices, widths — all concrete); the *only*
> non-concrete value is a token. A token may flow through: (T1) `cases`/`@cases`
> as a branch discriminant; (T2) the register's total finite-group primitives
> (`xor`/`⊻`/`!` on bits; `+`/`-`/const-`*`/const-shift mod 2^W and static
> bit-slice on ints) producing new tokens; (T3) a bounded `select(t, table)`
> multiplexer; (T4) a classical return. A token in **control-flow or indexing
> position** (`if`/`&&`/`while`/`?:`, `arr[t]`, `iterate(t)`, an allocation size)
> is rejected — mostly by Julia's own `TypeError`/`MethodError`, and by
> descriptive Sturm errors where Sturm owns the method. This is dynamic lifting
> with a restricted classical layer (the Jasp model minus a host-source tracer,
> which Julia lacks); it is **not** arbitrary Julia compiled once. Under Eager,
> tokens do not exist — outcomes are scalars and ordinary `if` applies.

**§3.8 table:** replace with the §3.2 table above (adds the `measure` row; DM/
Tracing/Hardware `if`/`&&` become ✗→`cases`; adds the scalar-cast row).

**§3.8 DM paragraph:** keep "executes channels, not trajectories"; append: "A
measurement therefore yields a token, never a scalar `Bool`; its classical
record is the pinched, still-live c-wire, traced (summed) only at the token's
last use — immediate block-accumulation would destroy feed-forward correlation
(F6)."

**§7.1 teleport:** change the portability note from "Eager/DM/Hardware only" to
"**Eager/shot only** (scalar `&&`); portable form uses
`cases(measure(dual(ψ)))` / the deferred variant §7.1b."

**§7.6 injection:** rewrite `@cases m begin … end` → `@cases measure(m) begin …
end`; delete "`@cases m … measures `m``" and add "`@cases` takes a token;
measurement is the visible `measure` cast (§4/F13 ruling)."

---

## 8. Risks and alternatives considered

- **R1 — the c-wire model spends a physical qubit per live token.** True: a
  retained classical record costs one Orkan slot until last use. Physically
  correct (the record *is* a system) and bounded by concurrent live tokens;
  Orkan's 30-qubit / 15-wire Choi budget (§3.8) absorbs every law test.
  Mitigation: trace eagerly at proven last-use; strict-mode leak check reuses
  the existing region machinery.
- **R2 — `measure` return type varies by context (F16).** Accepted; it is a
  *function*, monomorphic within a context once handles carry `C` (`QBool{C}`).
  This makes F16's context-parameterization a **hard dependency of M8**, not
  optional. Flagged for the implementer.
- **R3 — un-interceptable `if token`.** Cannot be fully fixed (verified). Best
  effort: descriptive type name + owned-method guards on the recoverable
  footguns + a portable idiom that avoids branch position. Documented as a
  known Julia-semantics limit, not a bug.
- **Alt considered — staged retrace (F4 option 1) as default.** Rejected:
  re-runs host effects per outcome, cannot yield one DM channel or one DAG,
  breaks the deterministic one-run Choi discipline. Kept only as the explicit
  `sample`/shot mode.
- **Alt considered — a full Julia→classical-SSA tracer (Jasp parity).** Rejected
  under rule 7: requires host source/AST surgery Julia does not support natively;
  the restricted combinator EDSL covers teleport, injection, syndrome, and
  bit-uniform QROM without it.
- **Alt considered — affine (use-once) tokens.** Rejected: classical outcomes
  are copyable; use-once breaks repeated feed-forward and syndrome processing.
  The explicit live-c-wire record is strictly more expressive and physically
  exact.
- **Interaction with F3 (phase-sensitive passes).** `CasesNode` is a
  channel-side node (contains a measurement barrier); it must be excluded from
  every unitary-only pass. This proposal keeps `cases` on the channel side of
  the F3 partition by construction — no unitary witness is ever attached to a
  `CasesNode`.
