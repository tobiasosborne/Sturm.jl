# Sturm v2 PRD — Processes, Views, and Casts

**Status: DRAFT for argument.** This document is the outcome of the 2026-07-03
ground-up design re-evaluation (bead `Sturm.jl-u9o6`), revised 2026-07-04
(bead `Sturm.jl-oqu3`): citation audit completed (attributions corrected in
§1.1/§3.5/§3.7), prior-art sweep folded in (§3.3, §4.1, §4.5), the D5
porting experiment **executed** (results in §9), the §8 defect list
re-verified at file:line against main, and — same day, after argument —
views de-magicked (`view(V, q)` mechanism with `dual` as the type-derived
instance, §3.3) plus the scope discipline added (§3.9: scope is the
Stinespring boundary; traces have no backaction and are silent). D1, D2,
and D9 were RESOLVED the same day via the Julia-idiom research round
(rulings in §9; DJ worked example in §7.4). It supersedes the
primitive-layer sections of `Sturm-PRD.md` (the θ/φ rotation surface) and
restates the affected axioms. Everything not explicitly changed here —
contexts, Orkan FFI, the Bennett bridge, QECC-as-HOF, promotion, the
channel-IR passes discipline — carries over from v0.1.

> The one-paragraph summary: v0.1's axioms were right and its primitive layer
> was wrong. The two Bloch-angle rotations are *coordinates pretending to be
> operators* — dishonest physics (θ only increments on the φ=0 meridian; `+=`
> asserts commutativity rotations don't have), anti-idiomatic Julia (a
> write-only pseudo-property), not dimension-agnostic (su(2)-specific), and
> the generator of the project's entire escape-hatch zoo (`not!`, `_cz!`,
> controlled-Pauli folklore). v2 replaces them with a **three-layer design**:
> a *surface* that is normal programming (casts, `⊻=`, conjugate views,
> `when`), a *kernel* of definite process values where control and adjoint
> are well-defined by theorem, and a *library* of physicist conveniences.
> Complementarity replaces coordinates. Bohr, not Bloch.

---

## 1. Diagnosis: why v0.1's primitive layer must go

### 1.1 The formal tension (P1 vs P4)

Two theorem-grade facts, surfaced during the re-evaluation, show that v0.1's
`when` never had the semantics its axioms claimed:

- **Quantum alternation has no channel-level semantics** (Bădescu &
  Panangaden, arXiv:1511.01567). `if q then skip else phase(θ)` is a
  controlled-phase, yet `skip` and `phase(θ)` denote the *same channel*.
  Alternation is also non-monotone in the CP order, so coherent control and
  unbounded recursion can never mix.
- **Controlled-U cannot be constructed from black-box access to U**
  (Araújo–Feix–Costa–Brukner, arXiv:1309.7976, the original single-exact-
  query no-go; strongest form Gavorová–Seidel–Touati, arXiv:2011.10031 — a
  topological obstruction, Borsuk–Ulam via their "Topological Lemma", that
  survives approximation, postselection, and relaxed causal order — all
  three literal in the paper). Control requires a *phase-fixed
  representative* — in our gloss, a section of U(d) → PU(d); the papers
  phrase it as the non-existence of a continuous phase choice. The flip
  side is the constructive half of the argument: Araújo et al. themselves
  show control IS implementable given side-information about *where* U
  acts (extending 1⊗U to 1⊕U). A kernel process value is exactly that
  side-information made explicit and typed. The no-go pair does not merely
  forbid the surface from controlling channels; it *derives* the kernel.

v0.1 squares this circle operationally: the control stack lifts the primitive
*sequence*, silently fixing an SU(2) section. Concretely, every
`apply_ry!`/`apply_rz!` call self-selects an ABC decomposition against the
control stack (`src/context/multi_control.jl`) — sound only because the
primitives are two *fixed* generators, never a caller-supplied unitary. The
escape was principled but implicit; the moment anything else is lifted, the
same code path is the no-go. That undocumented section-choice is the root
cause of the `_cz!` ≠ controlled-Rz(π) folklore, the recurring `3yz`
(X vs −iY) bug family, and the defensive comment blocks copy-pasted across
four files.

Additionally, sound coherent-control bodies must be unitary, must not touch
the control, and must leave control disentangled at exit. Attribution,
precisely (the earlier draft lumped these): Bădescu–Panangaden's own §1
already posits guard-externality and reversibility as Conditions I and III
on any alternation; Yuan–Villanyi–Carbin (Quantum Control Machine,
OOPSLA 2024 — arXiv:2304.15000) prove that injectivity (Thm 4.4) plus
synchronization (Def 4.7) are jointly sound *and complete* for
unitarity-with-disentangled-control (Thms 4.8/4.9); Ying–Yu–Feng
(arXiv:1402.5172) supply only guard-externality (Def 2.1(4)) — their
general guarded composition deliberately admits non-unitary branches,
which is precisely the road the denotation problem above closes. v0.1
enforces none of this: `Bool(q)` inside `when()` today performs a silent
unconditional global collapse.

### 1.2 The five defects of `q.θ += δ` / `q.φ += δ`

1. **Asymmetric honesty.** `q.φ += δ` is true physics (Rz increments the
   azimuth of every state). `q.θ += δ` increments the polar angle only on
   the φ=0 meridian; elsewhere Ry is a rotation about Y, not a θ-increment.
2. **False commutativity.** `+=` on two "fields" notates a commutative
   structure. SU(2) is not commutative.
3. **Anti-idiomatic Julia.** A write-only pseudo-property via `getproperty`
   interception, a `_RotationApplied` sentinel, and a no-op `setproperty!`.
   Verified failure modes: bare `q.θ` is a **silent no-op**; `q.θ .+= δ`
   dies inside broadcast machinery; every rotation is a dynamic dispatch.
4. **Not dimension-agnostic.** θ/φ are Bloch coordinates — qubit-specific.
   `QMod` is the strain made visible: hand-rolled spin-j rotations for
   d ∈ {3,5} only, everything else a loud error. The axiom fails P7 in the
   v0.1 codebase today.
5. **The SU(2) determinant obstruction generates the exception zoo.**
   det = 1 makes X, H, CZ, controlled-Paulis unreachable exactly; hence
   `not!` (a named exception in the constitution), `_cz!`,
   `_multi_controlled_pauli_exp!`, and the block-encoding warning blocks.
   Meanwhile rule 11's own success criterion fails: `_diffusion!` and
   `_select!` *are* circuit diagrams transliterated into rotation ops.

### 1.3 The philosophical error of the first redesign attempt

An intermediate proposal ("evolve under generator G", Stone's theorem as the
API) was rejected on operational grounds: **Nature does not hand out
Hamiltonians; it hands out processes.** Dynamics is a representation of
(ℝ, +); generators are *derived* when the representation is sufficiently
nice, and do not exist at all for discrete symmetries (permutations —
i.e. every Bennett artifact — and braids). The process-first view is
strictly more general and is the project's philosophy. Generators live in
the library (`evolve!`), never in the kernel.

A second intermediate proposal (surface code written as `ctrl(X)(a, b)`)
was rejected as gate-level thinking re-entering through the front door.
Process values are the correct *kernel*; they are not the *surface*.

---

## 2. The three-layer architecture

| Layer | Contents | Who sees it | Gate-ontology allowed? |
|---|---|---|---|
| **Surface** | registers as numeric types; casts; `⊻=`/`not!`; `dual` views; `when`; `cases`; promotion; Bennett `oracle` | users, all algorithm code | **No.** |
| **Kernel / IR** | process values (definite representatives); `∘`, `⊗`, `adjoint`, `ctrl`; Ad-application; linearity enforcement | compiler, library authors | Yes — this is the LLVM of Sturm. |
| **Library** | `evolve!(q, H, t)`, `amplify`, `phase_estimate`, `superpose!`, named constants, QECC | physicists wanting standard things easy | Values, not surface syntax. |

**The lowering contract.** Every surface construct has a defined lowering to
kernel operations; every kernel process value has a channel denotation via
the adjoint representation (§4.3). Correctness claims are stated at the
channel level; control and adjoint are performed at the kernel level;
programs are written at the surface level. The layers exist because a
theorem forbids collapsing them (§1.1).

The test for surface code is unchanged from v0.1 in spirit and finally
achievable in practice: **if your program reads like a circuit diagram, it
is wrong.** The v2 corollary: if your program mentions a gate, a rotation
angle, or a process value, it is not surface code.

---

## 3. Surface specification

### 3.1 Registers (unchanged in spirit)

`QBool`, `QInt{W}`, `QMod{d}`, … are numeric types for Julia's dispatch
(P9). Generic functions ride operator overloading (P8); type-restricted
functions go through `oracle(f, q)` (Bennett). Nothing here changes except
what operations exist.

### 3.2 Casts and the boundary algebra

- **Preparation (cq):** `QBool(p::Real)` allocates at √(1−p)|0⟩ + √p|1⟩;
  `QBool(b::Bool)` is the definite-bit cast. The full quantum literal is
  **`QBool(p::Real, φ::Real = 0.0)`** (relative phase; positional default
  on the `Complex(x, y)`/`Complex(x)` pattern — ruling and required tests
  in D1, §9). `DomainError` for p ∉ [0,1]; named library constants
  (`plus()`, `minus()`, `magic_T()`) are sugar on this constructor.
- **Measurement (qc):** `Bool(q)` / `Int(x)` are **consuming** casts. The
  register handle dies at the cast: after collapse the information is
  classical, and a live quantum handle to it would be a type lie. Implicit
  casts warn (unchanged P2 discipline).
- **The boundary algebra** (normative, testable):
  - `Bool(QBool(b)) == b` — qc ∘ cq = identity on classical data;
  - `QBool(Bool(q))` — cq ∘ qc = the **pinching channel** (complete
    dephasing in the computational basis).
  The cast pair composes to decoherence. This is the operational content of
  the boundary and each identity is a required test.
- **Basis'd measurement is a cast of a view, never gate-then-measure:**
  `Bool(dual(q))` is the conjugate-basis instrument (§3.3).
- **Positioning.** Linear consumption at measurement is anticipated at the
  type level — Silq (PLDI 2020) rejects reuse statically; Twist (POPL 2022,
  arXiv:2205.02287) has a T-Measure rule that removes the qubit from the
  typing context, exactly our consumed set. Spelling consumption as the
  host language's own *cast syntax* appears to be unprecedented. Sturm
  enforces at runtime (§4.5) — deliberately between Q#'s convention-only
  stance and Silq/Twist's static rejection; the P2 warning is the static
  shadow of the runtime rule.

### 3.3 `dual` — the conjugate view (the one new quantum concept)

Classical programming lacks exactly one thing quantum programming needs:
**complementarity**. v2 exposes it as a single construct:

```julia
dual(q)    # conjugate-basis view; lazy, zero-cost, involutive: dual(dual(q)) === q
```

`dual` is a reinterpreting *view* in the precise idiom of Julia's
`transpose(A)` / `adjoint(A)`: not an operation on the data, a different way
of addressing it. Operations on the view dispatch through the
reinterpretation (kernel-level conjugation by the basis-change
representative). Semantics table:

| Surface expression | Meaning | v0.1 spelling it replaces |
|---|---|---|
| `Bool(dual(q))` | conjugate-basis measurement | `H!(q); Bool(q)` |
| `not!(dual(q))` | phase flip | `q.φ += π` |
| `dual(q) ⊻= r` | phase-entanglement (CZ); **symmetric, and the notation shows it**: `dual(q) ⊻= r` ≡ `dual(r) ⊻= q` | `_cz!(q, r)` folklore |
| `dual(x::QInt) += a` | Draper addition — arithmetic in the view where it is cheap | `add_qft!` (100 lines of per-wire phase bookkeeping) |
| `Int(dual(x))` | Fourier sampling | `fourier_sample` plumbing |

**`dual` is Pontryagin duality, not an analogy.** Every register type
carries an underlying locally compact abelian group G of computational
labels; `dual(q)` addresses the register through the character group Ĝ,
and the basis change is the Fourier transform on G:

| Register | G | view pair | basis change |
|---|---|---|---|
| `QBool` | ℤ₂ | Z↔X (self-dual) | H |
| `QInt{W}` | ℤ_{2^W} | value↔Fourier | QFT |
| `QMod{d}` | ℤ_d | clock↔shift (Weyl–Heisenberg) | F_d |
| CV mode | ℝ | x↔p | Fourier (the original) |

The semantics table's separate facts are corollaries of this one theorem:
involutivity `dual(dual(q)) === q` is Pontryagin's duality theorem;
`dual(x) += a` = Draper addition is translation-in-G ↔ modulation-in-Ĝ
(the Fourier intertwining relation); the CZ symmetry
`dual(q) ⊻= r ≡ dual(r) ⊻= q` is the symmetry of the pairing
G × Ĝ → U(1). This is P7 achieved *by the surface*: one theorem covers
every abelian register. Anyons are the honest exception — fusion
categories are not groups, so whether a useful `dual` exists there is
genuinely open (D6), exactly as the process-first kernel predicts: braid
process values exist regardless; characters may not.

**Views are ordinary kernel machinery; `dual` is not a keyword.** The
general mechanism is a *parametric view*: `view(V, q)` for any
unitary-witnessed process value `V` — a lazy wrapper whose every
operation lowers by conjugation. Unitaries lower as Ad_{V†} ∘ op ∘ Ad_V;
measurement casts lower as the conjugated *instrument* (so
`Bool(dual(q))` is not a special case); `when` lowers by conjugating the
control wire of `ctrl`. `dual(q)` is then an ordinary function:
`view(F_G, q)`, with F_G supplied by the register type. Its surface
privilege is not mechanical but a P5 fact: §2 forbids surface code from
mentioning process values, and `dual` is the unique view constructor that
takes no process-value argument — the type's declared arithmetic already
fixes F_G, up to discrete, fixed-once conventions of the two's-complement
sort (choice of generator, sign of the character). The basis choice is
exactly as "arbitrary" as the type's labeling commitment, which was
already made when we called the register `QInt`. Library authors reach
for `view(V, q)` freely — QSVT's SELECT conjugates by the Y-axis value
this way; the executed D5 port (§9) confirms such conjugations arise only
inside `src/simulation`/`src/qsvt` internals, never in algorithm code.
Users never see a `V`.

**Views unwrap; processes compose.** As a *process*, the Fourier value
satisfies F² = parity (x ↦ −x mod 2^W), F⁴ = 1: if `dual` were sugar for
"apply F", then `dual(dual(x))` would negate every integer. As a *view*
it unwraps by dispatch — `dual(dual(x)) === x` — which is precisely
Pontryagin's canonical double-dual identification ev : G → Ĝ̂ (no antipode
in it), and precisely Julia's `transpose(transpose(A)) === A`: structural
identity, while physically permuting a copy twice costs two passes.
Generic stacked views compose (`view(V, view(W, q)) == view(W ∘ V, q)`);
`dual` specifically unwraps — implemented as a dispatch-time unwrap on
the wrapper's nominal type (`dual(v::DualView) = v.parent`, Base's exact
`adjtrans.jl` pattern), never by evaluating the represented transform.
This distinction is normative — an implementation that lowers `dual` by
*applying* F is wrong, and the signature of the error is integer negation
under double duals. Julia has made this same category of mistake before
and repaired it at cost: JuliaLang/julia#20978, where pre-0.7
`ctranspose = conj ∘ transpose` by fiat forced `transpose` recursive and
broke non-numeric matrices.

**`dual` composes with `when`:** `when(dual(q)) do … end` is coherent
control in the conjugate basis, lowered by conjugating the control wire of
`ctrl(V)` with the basis change; the §3.5 guardrails apply unchanged. No
D5 algorithm needed it, but it falls out of the lowering for free and MUST
be defined — a view that composes with casts but not with `when` would be
a seam in the surface.

**Prior art.** The nearest neighbour is Qwerty (Adams et al.,
arXiv:2404.12603): first-class basis values (`std`, `pm`, `fourier[N]`)
and Fourier-basis measurement as a primitive — but its basis translation
`>>` is explicitly a value-changing *synthesized unitary*; its authors
considered and rejected the view reading. The zero-cost, involutive,
`transpose`-idiom view — reinterpretation dispatching through kernel
conjugation, never synthesis — appears to be novel. The distillation must
cite Qwerty; the differentiator is the whole point.

**Where H went:** nowhere — it was never a process in this picture. H is
the change of description between the two views, and surface code only ever
needs the views. Materializing a view as a process — basis change as an
operation on an existing entangled register — is applying the view's
unitary as a process value: processes compose, views unwrap. Grover's
diffusion is the canonical customer (§5, D4).

### 3.4 Entanglement and flips

`a ⊻= b` (CNOT-composition), `not!` (now *derivable* — the kernel's X is
exact in U(2), see §4.1 — but kept as the idiomatic surface flip),
`swap!` (library sugar: three `⊻=`), and the P8 mixed forms. Normative fix
carried into v2: the mixed `xor(a::QBool, b::Bool)` must lower to the
kernel's exact X, not `Ry(π)` (v0.1 latent phase bug at `qbool.jl:154`).

The P8 mixed forms extend to views: `dual(y) += x` with `x::QInt` is the
quantum-addend Draper adder (v0.1's `add_qft_quantum!`) — the same
lowering with controlled phases in place of phases. And note that `+=` on
a dual view is honest where `q.θ +=` was not: modular addition and its
dual modulation genuinely commute (an abelian group acting on itself); the
θ-increment notated a commutativity SU(2) does not have.

**`⊻=` also applies `Perm` values (D9 ruling, §9):** `b ⊻= oracle(f, x)`
lowers the Bennett `Perm` target-accumulatingly into `b` —
|x⟩|b⟩ → |x⟩|b ⊕ f(x)⟩ for *any* initial state of `b`, which is what
makes phase kickback ordinary surface code (§7.4). `a ⊻= b` is the W=1,
f=identity case of this same method family, not a separate construct.

**Named convention exception (alongside `not!`):** Sturm's `Base.xor`
methods on registers mutate their first argument in place and return the
same handle — that is what makes `a ⊻= b` (which Julia lowers to
`a = xor(a, b)`) a physical operation rather than a rebind. A no-bang
Base function that mutates is a deviation from both Base convention and
Sturm's own rule 2; it is deliberate, and this paragraph is its
registration.

**Caveat on the generic-f path (P8/P9):** `b ⊻= f(x)` with a hand-written
generic `f` is safe only if `f` is written accumulate-in-place. A naive
XOR-fold (`reduce(⊻, …)` style) allocates fresh intermediates that are
never uncomputed; they leave scope entangled, and the silent boundary
trace (§3.9) then correctly reports a decohered survivor — the
interference the algorithm needed is already gone (the computation did
it, not the trace). For multi-step classical logic, use
`oracle(f, x)` — Bennett's compute-copy-uncompute guarantees garbage-free
ancillae by construction. This is the quantum contract of §3.9 applied to
P9's generic path.

### 3.5 `when` — control flow, with theorem-shaped guardrails

`when(q) do … end` **stays on the surface**: it reads as control flow,
which is normal programming. Its semantics is new:

> `when(q, body)` ≡ trace `body` to a unitary-witnessed process value `V`;
> apply `ctrl(V)` to `(q, wires of body)`.

The guardrails are soundness requirements, not lints. Guardrails 1 and 2
are Bădescu–Panangaden's own Conditions III and I (their §1); the
unitary-witness requirement is exactly the Yuan–Villanyi–Carbin
soundness/completeness pair (Thms 4.8/4.9); guardrail 3 is the
non-monotonicity result (§1.1):

1. The body must trace to a **unitary-witnessed** value: any cast, `ptrace!`,
   `cases`, or noise channel inside `when` is a **loud error**.
2. The body must not operate on the control register — loud error.
3. No unbounded recursion/iteration under `when` — bounded unrolling only.

The ban has a direction: `cases` inside `when` is guardrail 1; `when`
inside a `cases` branch is fine — each branch is an ordinary
post-measurement channel. Nesting composes (`ctrl` is closed). The control
register participates as input *and* output (kickback is physics).

### 3.6 `cases` — the classical branch (Kleisli layer)

Unchanged in role: branching on measurement outcomes is `cases`/`@cases`,
the operational shadow of dynamic lifting (Proto-Quipper, POPL 2023
arXiv:2204.13041). What `Bool(q)` returns under `TracingContext` is **open
decision point D3** (§9): the leading candidate is a `ClassicalBit` token on
which `if` MethodErrors loudly, pointing to `cases`.

### 3.7 Universality of the surface (claim, with proof obligation)

**Claim:** {preparation casts (with D1 literals), `⊻=`/`not!`, `dual`,
measurement casts, classical control} is computationally universal.

**Argument:** one-bit teleportation makes H a *gadget*, not a gate:
prepare |+⟩ (a cast), entangle with CZ (`dual(q) ⊻= r`), measure in the
conjugate basis, correct with Pauli flips — the MBQC elementary-wire
identity (Raussendorf–Browne–Briegel, quant-ph/0301052 §II; note this is
NOT the Zhou–Leung–Chuang gadget, which is CNOT + Z-measurement — the
earlier draft conflated them). Non-Clifford power enters by magic-state
injection (Bravyi–Kitaev, quant-ph/0403025) with the Zhou–Leung–Chuang
correction ladder (quant-ph/0002039 §IV.A and the §III.C recursion;
Gottesman–Chuang, quant-ph/9908010): the T-gadget's correction is S, the
S-gadget's is Z, and Z is native (`not!(dual(q))`). Continuity enters
through *preparation* (quantum literals), never through mutation
primitives. No algorithm can force a gate back into surface code.

**Entailment (settles half of D1):** universality *requires* the
phase-bearing literal. Casts, `⊻=`, `not!`, and both `dual` flips generate
only real-amplitude stabilizer operations; no composition of them, nor any
measurement of them, manufactures the e^{iπ/4} of a magic state. If §3.7
is an axiom, a relative-phase literal is not optional — only its spelling
remains open (D1).

**Proof obligation (research step, rule 8):** write it up properly in
`docs/physics/` with the citations above before v2 implementation begins.
In practice, continuous operations reach users through library HOFs
compiled to the kernel; the universality claim is about *closure*, not
about hand-writing T-gadgets.

### 3.8 The v2 surface vocabulary (normative table)

The v0.1 constitution's five-construct table (CLAUDE.md rule 11) is
superseded by:

| # | Surface form | Role | Lowering (kernel) |
|---|---|---|---|
| 1 | `QBool(p)` / `QBool(b)` / phase literal (D1) | preparation cast (cq) | allocate + literal `U2` |
| 2 | `Bool(q)`, `Int(x)` — consuming | measurement cast (qc) | instrument; consumes handle |
| 3 | `a ⊻= b`, `not!(a)`, P8 mixed forms | flips / entanglement | kernel X / `ctrl(X)` |
| 4 | `dual(q)` | conjugate view (Pontryagin) | conjugation by F_G |
| 5 | `when(q) do … end` | coherent control | trace body → `ctrl(V)` |
| 6 | `cases` / `@cases` | classical branching | Kleisli / dynamic lifting |
| 7 | `oracle(f, x)` | Bennett bridge | `Perm` value |

Everything quantum a user writes is these seven; arithmetic and generic
Julia code ride P8/P9 as before. If a program needs an angle, it needs the
library; if a library function needs an angle, it builds a process value.

### 3.9 Scope is the Stinespring boundary

Registers obey a scope discipline that is not a convenience feature but
the P1 denotation itself:

- **Entry: allocation is initialization.** A fresh register comes into
  existence in the canonical state of its type — |e_G⟩, the basis state
  of the declared group's identity element (|0⟩ for `QBool`/`QInt`/`QMod`,
  the vacuum for CV, the trivial charge for anyons). There is no
  uninitialized register and no bare-allocation surface form; `QBool(p)`
  builds from |e_G⟩ by construction, and the choice is the quantum
  computational model's, not ours. (A fresh |0⟩ read through `dual` is
  uniformly random — complementarity working as specified, not a bug.)
- **Exit: unconsumed owned locals are traced.** At a region boundary,
  every register the region allocated and neither consumed nor returned
  is implicitly `ptrace!`d. This is forced, not chosen: a function that
  allocates locals and returns outputs denotes a channel *on its
  signature* only if the locals are traced — locals are the Stinespring
  environment, and function scope is the dilation boundary. Every
  function is a channel by construction (P1), with the trace as its
  closing parenthesis.

**Forgotten uncompute is correct behaviour, not an error.** The partial
trace has no backaction: for every observable still reachable, tracing a
register and simply never touching it again are *identical* — the
survivors' reduced state is invariant under any channel on the traced
system (no-signaling). A skipped uncompute means the entangling
computation itself already made the survivors' reduced state mixed; the
trace only makes the bookkeeping honest. If you wanted a pure output,
uncompute before the boundary — that is the quantum contract, and the
language does not nag about it. The normative warning rule, stated once:
**implicit operations with backaction warn (P2 casts — measurement
collapses); implicit operations without backaction are silent (traces).**
Explicit `ptrace!` remains available to close a register early.

Mechanics, in order of the frictions they resolve:

- **Regions, not GC.** Julia finalizers are nondeterministic; the trace
  is part of the denotation and must sit at a definite circuit position
  (on `TracingContext` the DAG would otherwise depend on GC timing).
  Region boundaries are explicit: `@context` blocks (deterministic
  cleanup shipped in v0.1, bead `sv3` — `src/context/abstract.jl`, whose
  comment already rejects finalizers as unsafe), functions executed *as
  channels* (traced bodies, `oracle`, `Channel` invocation — the
  signature names the outputs), `when` bodies, and a do-block region form
  for manual scoping (spelling: D10). Plain eagerly-executed helper
  functions have no exit hook in Julia and inherit the enclosing region;
  a GC finalizer may at most *detect* a lost handle in debug builds,
  never trace it.
- **`ptrace!` ≠ reset.** Tracing forgets a wire; making it fresh again is
  a physical channel (measure-and-flip, or active reset). The allocator
  invariant "fresh = |e_G⟩" is maintained by reset-on-recycle. No
  observable on the survivors changes either way (no-signaling again),
  but conflating the two channels is a physics bug.
- **Lowering on pure contexts.** A genuine partial trace of an entangled
  wire leaves a mixed survivor state, which a statevector cannot hold.
  Sanctioned lowerings, mirroring §4.3: measure-and-discard the traced
  wire — exact for all downstream statistics by no-signaling, and a valid
  per-shot unraveling — or the Stinespring option, keeping the wire alive
  but inaccessible as explicit environment. Density contexts trace
  exactly.
- **Inside `when`, the boundary is checked.** Alloc-inside-`when` is the
  clean-ancilla pattern (compute–use–uncompute); there the body must stay
  unitary, so scope exit requires the |e_G⟩/unitarity witness — under
  which the deallocation is not a trace at all (the composite is unitary
  on the surviving wires). Without the witness, guardrail 1 (§3.5) fires
  loudly. Trace under `ctrl` is never a quiet degradation; it is
  unrepresentable (§4.4). Bennett `Perm` bodies carry the witness by
  construction.
- **Ownership: views borrow.** Scope exit traces *owned* registers only.
  `dual(q)`, `view(V, q)`, and `x[i]` borrow; their death traces nothing.
  Returning a view of a dying local is a loud error (or an explicit
  ownership transfer — D2). Consumed handles are skipped for free by the
  single-sourced consumed set (§4.5).

With this section, §4.5's "exactly two places" is refined rather than
revised: consumption happens at qc casts and `ptrace!`; the region
boundary is not a third mechanism but the *derived* form — an implicit
`ptrace!` of whatever the region still owns.

---

## 4. Kernel specification

### 4.1 Process values

A **process value** is a definite representative of a symmetry-structure
element — data, not denotation. One abstract type, trait-stratified:

- `U2` — element of U(2) as **unit quaternion + phase** (5 floats).
  Composition = quaternion multiplication: exact, matrix-free. X, Z, H are
  *exact* elements (the v0.1 doctrine "H!² = −I is a feature" dissolves —
  it was an SU(2)-section artifact, not physics). Numerics policy
  (normative): drift off the unit sphere is repaired by a single scalar
  rescale — cheaper and better-conditioned than re-orthogonalizing a
  drifting complex 2×2 — and a Hamilton product is 16 real multiplies
  against ~50 for complex matrix product, so fusion gets cheaper as well
  as exacter. Euler/ZYZ extraction happens ONCE, at the Orkan boundary;
  the θ≈0/π coordinate singularity of any three-angle chart (Stuelpnagel
  1964 — a topological fact, not a convention choice) is confined to that
  single extraction site, while composition itself stays chart-free.
  Prior art: no surveyed compiler or simulator uses quaternion+phase as
  its persistent 1q IR (Qiskit's `Quaternion` class is a narrow
  Euler-reordering utility; Fraxis/FQS quaternions parameterize VQE
  ansätze) — the combination appears novel.
- `Perm` — reversible permutation (every Bennett.jl artifact). Canonical
  0/1 matrices: **no phase freedom at all** — the classical-reversible
  corner is the best-behaved under control, as befits a Bennett-centric
  language.
- `UnitaryDAG` — a `Channel`-style DAG carrying a unitarity witness
  (produced by tracing `when` bodies and library circuits).
- Future per-register-type structures (P7): SU(d) values for `QMod{d}`,
  symplectic+displacement for CV, braid-group elements for anyons
  (discrete — the process-first view covers them; a generator view never
  could).

A register type declares its symmetry structure the way a Julia number type
declares its arithmetic. The kernel is parametric in it.

### 4.2 The algebra (normative laws = required tests)

`∘` (composition), `⊗` (parallel), `adjoint`, `ctrl`. Laws:

- `Ry(a) ∘ Ry(b) == Ry(a+b)` — dynamics as a representation of (ℝ, +),
  now a testable identity on quaternions;
- `ctrl(g ∘ h) == ctrl(g) ∘ ctrl(h)` — `ctrl` is a group homomorphism
  U(d) → U(2d), **not** a channel map (it distinguishes `g` from
  `e^{iα}g`; that is its job);
- `adjoint(ctrl(g)) == ctrl(adjoint(g))`;
- `ctrl` is closed: `ctrl(ctrl(g))` is Toffoli-grade control, no special
  case. Single-qubit gate fusion becomes quaternion arithmetic — v0.1's
  `gate_cancel` commutation table is subsumed for 1q rotations by exact
  group multiplication *before anything touches Orkan*.

Two further normative constraints, both bought with other people's bugs:

- **`ctrl` is the only constructor of controlled lowerings in the entire
  system.** Cirq, Qiskit, and pytket each carry a dedicated global-phase
  field, and each shipped controlled-decomposition phase bugs for years
  anyway (Cirq #1161/#4275; Qiskit #7167 plus the `.control()`
  AttributeError cluster; pytket ≤0.17's QControlBox) — because the bug
  lives at whichever call site builds the controlled circuit, and there
  were many. The representation alone does not fix this class; a single
  choke point, total on process values, does. (Tang–Wright,
  arXiv:2508.00055 Thm 1.1, is the formal statement of why control makes
  global phase physical.)
- **Control-scope reassociation is a kernel law, not folklore:**
  `(1 ⊗ V) ∘ ctrl(W) ∘ (1 ⊗ V†) == ctrl(V ∘ W ∘ V†)` when `V` acts only
  on the body's wires. v0.1 hand-proves and hand-codes this identity at
  three independent sites (`modadd!`'s `ctrls` kwarg, `_pauli_exp!`'s
  control-stack surgery, the QSVT reflector) to avoid controlling whole
  circuit bodies. In v2 it is (a) a tested law on process values, (b) the
  kernel pass that narrows control scope automatically, and (c) a named
  combinator for library authors (`conjugated_by(V) do … end` — name
  open). The most-repeated non-trivial idiom in the v0.1 library must not
  remain hand-rolled.

### 4.3 Application: the adjoint representation

States are never user-facing; a register is a handle into a context that
owns the state. Application of a process value is the **adjoint
representation**:

> Ad : U(d) → CPTP,  Ad_g(ρ) = g ρ g†,  with ker(Ad) = U(1).

**The phase quotient is crossed exactly once, at application, by Ad's
kernel — never by a convention in library code.** Algebra on values
preserves phase (`ctrl` can still act); application forgets it (Nature
does). Dispatch is (value kind × context kind):

| Process value | Pure context | Density context |
|---|---|---|
| `U2` | Euler ZYZ → existing Orkan `rz/ry/rz` (phase droppable *here only*) | same, as conjugation |
| `ctrl(·)`, multi-register | controlled decomposition → `orkan_cx` etc. | same |
| `Perm` | replay stored reversible circuit (Bennett artifact) | same |
| `UnitaryDAG` | replay nodes | replay nodes |

**Channel-level values** (Kraus families — noise) apply through the same
surface. On a density context: Kraus→superop (existing path). On a pure
context, two sanctioned options replacing v0.1's hard error: (a) error
loudly (default), (b) **Stinespring fallback** — allocate environment,
apply dilated process value, `ptrace!` — making pure-vs-mixed a context
performance choice, never a semantic one.

### 4.4 The stratification (what `ctrl` can never touch)

| Level | Objects | Operations | `ctrl`? |
|---|---|---|---|
| Process values | `U2`, `Perm`, `UnitaryDAG` | `∘`, `⊗`, `adjoint`, `ctrl` | ✔ closed |
| Channels | denotations; casts, noise, `ptrace!`, `cases` | composition, tensor | ✘ impossible, by theorem |

Denotation (value → channel) is a quotient, always available, never
invertible. Measurement was never a process value; therefore
measurement-under-`ctrl` is not an error case — it is *unrepresentable*.

### 4.5 Linearity: surface B, single mechanism

Application, casts, and discard all follow one type discipline —
**channels consume their input handles and produce output handles**:

```julia
q  = QBool(p)        # cq: consumes nothing quantum, produces a handle
b  = Bool(q)         # qc: consumes q, produces a Bool
ptrace!(q)           # trace: consumes q, produces nothing
q ⊻= r; not!(q)      # unitary mutation: the handle stays live —
                     # linearity is a boundary discipline
```

**Where consumption happens — exactly two places.** Handles are stable
identities; unitary application mutates in place and never invalidates a
handle (it is a channel from the register to itself). Consumption occurs
at the qc casts and at `ptrace!` — the two places quantum information
actually exits the program; region boundaries are the derived form of the
second (§3.9), not a third mechanism. (An earlier draft said mutation
forms "consume-and-rebind the same handle internally"; that was a
fiction — binary forms like `false ⊻ b` in §7.1 use `b` as a control and
`b` remains live afterwards, which no rebinding story can express. The
honest rule is simpler and is stated above.)

Enforcement is runtime and **single-sourced on the context's consumed set**
(v0.1's per-object flag becomes at most a cache; the demonstrated
drift-desync between the two mechanisms — `QInt` views manufacture fresh
flags, see §8.5 — is thereby fixed). This positions Sturm deliberately
between Q# (no linearity, by design) and Silq/Twist (static linear
typing): the *semantics* is theirs — Twist's T-Measure rule removes the
qubit from the typing context, exactly our consumed set — while the
*enforcement* is runtime, which a decade of typed embeddings supports for
a host-language DSL (QWIRE's own authors moved to concrete indices for
VOQC after finding the abstract-qubit machinery unworkable for proofs in
practice — arXiv:1912.02250 §3.3; quote their framing, not ours).
Aliasing (`when(a){not!(a)}`, `f(y, y)`, register-vs-slice overlap) must
be caught at the DSL level with register identities in the error message —
today's check lives in the Orkan FFI shim and leaks raw physical indices
(§8.4).

---

## 5. Library

- `evolve!(q, H, t)` — Hamiltonian simulation: *constructs* a process value
  (exactly, or via Trotter/QDrift/QSVT) and applies it. Generators are
  derived objects and this is their home. Philosophy note: this is
  functionality to make standard physics easy, not a statement that
  Hamiltonians are fundamental.
- Named constants (`X`, `Z`, `H`, …) are kernel values exported to library
  authors, **not** surface vocabulary.
- HOFs: `amplify`, `phase_estimate`, `superpose!`, `interfere!`, `find` —
  re-expressed over the v2 surface + kernel; expected to *shrink*
  (`_cz!`, `_multi_controlled_z!` cascades, and the QFT-arithmetic
  plumbing are subsumed by `dual` and kernel `ctrl`).
- Bennett bridge: `oracle(f, x)` produces `Perm` values; controlled oracles
  are canonical (§4.1). Unchanged API, cleaner semantics.
- The library is also where views get *materialized*: `amplify`'s
  diffusion conjugates live, entangled registers by H^⊗n — a basis change
  as a process, not a view. This is the answer to D4: rarely, but
  definitely; the kernel value `H` wrapped by a library name, never
  surface vocabulary. `superpose!(x)` is the second customer (D9 round):
  preparing a QInt's uniform superposition is H^⊗W applied to |0⟩ — a
  real operation, not a reinterpretation — and it stays a library
  materialization (a uniform-superposition *literal* is deliberately
  deferred until call-site pressure demands one).
- QSVT and block-encoding internals are declared first-class kernel
  territory: Remez/Weiss-derived phase sequences, PREPARE's Grover–Rudolph
  rotation tree, and SELECT's Y-basis conjugations are continuous,
  data-dependent process-value constructions with no surface spelling —
  by design, not by omission. The D5 acceptance bar is that none of it
  leaks past the HOF signature.
- QECC (P6): unchanged — `encode(ch, code)` is `Channel → Channel`.

---

## 6. The axioms, v2 restatement

- **P1 — Functions are channels.** Unchanged, *strengthened*: under §4.5
  every primitive visibly has channel type (consume inputs, produce
  outputs); a program is a composite in the image of Ad.
- **P2 — The boundary is a cast.** Unchanged, sharpened by the boundary
  algebra (§3.2): qc ∘ cq = id, cq ∘ qc = pinching.
- **P3 — Operations are operations.** Unchanged (Stinespring fallback makes
  it truer: any channel applies in any context).
- **P4 — Control.** *Restated:* quantum control is an operation on process
  values, never on channels (theorem). Surface form `when`; kernel form
  `ctrl`; the guardrails of §3.5 are part of the axiom.
- **P5 — No gates, no qubits.** *Refined:* no gates **in surface code** —
  the surface's quantum vocabulary is casts, xor, `dual`, `when`, and
  nothing else. The kernel may hold definite unitaries because an IR is
  not a user language. Complementarity, not coordinates.
- **P6 — QECC is a higher-order function.** Unchanged.
- **P7 — Dimension-agnostic.** *Restated as parametricity:* a register type
  carries (Hilbert space, symmetry structure, conjugate structure); the
  channel algebra, casts, `dual`, `when`/`ctrl`, and promotion never
  mention dimension. Finite d, CV, and (via discrete symmetry structures)
  anyons are instances, not extensions.
- **P8 / P9 — Promotion; registers are numeric types.** Unchanged.

---

## 7. Worked examples (normative)

### 7.1 Teleportation

```julia
"""
    teleport(ψ::QBool) -> QBool

Denotes the identity channel — that is the theorem, and the test:
Choi(trace(teleport, 1)) ≈ Choi(id).
"""
function teleport(ψ::QBool)
    b = QBool(0.5)                # a fair quantum coin
    c = false ⊻ b                 # xor into a fresh false: Bell pair

    b ⊻= ψ                        # correlate payload with Alice's half
    m_phase = Bool(dual(ψ))       # conjugate-basis readout (consumes ψ)
    m_value = Bool(b)

    m_value && not!(c)            # ordinary conditionals, ordinary flips —
    m_phase && not!(dual(c))      # one of them in the dual view
    return c
end
```

No gates, no rotations, no process values. No-cloning is visible in the
surface: the input handle dies at its cast; "teleport and keep" is
unwritable. The deferred-measurement variant (corrections under `when`
before the casts) must denote the same channel — a free second test.

**The negative of this example already exists on main.** v0.1's shipped
`teleport!` (test/test_teleportation.jl) has no conjugate-basis readout —
v0.1 has no vocabulary for one — so it measures the payload in the
computational basis and teleports only the diagonal. Its test passes,
because the test checks Z-marginals, which a classical feed-forward copy
also satisfies; coherence is in fact destroyed (verified empirically
during the D5 port: an injected |i⟩ input reads P(Y=+1) ≈ 0.5). The
missing construct is exactly `Bool(dual(ψ))`, and the Choi-level test in
the docstring above is exactly what would have caught it. This is the
sharpest single piece of evidence in this document that the v0.1 surface
was too poor to state what the algorithm means. (Bug filed:
`Sturm.jl-wm28`, independent of v2's schedule.)

### 7.2 Draper addition is addition

```julia
dual(x) += a        # v0.1: add_qft!(x, a) — 100 lines of phase bookkeeping
```

### 7.3 CZ symmetry is visible

```julia
dual(q) ⊻= r        # ≡ dual(r) ⊻= q — controlled-Z, symmetric by notation
```

### 7.4 Deutsch–Jozsa over an arbitrary Julia function (D9)

```julia
"""
    deutsch_jozsa(f, ::Val{N}) -> Bool

`f` is an ordinary Julia function on N-bit integers, promised constant or
balanced; compiled to a reversible `Perm` by the Bennett bridge. Returns
`true` iff `f` is constant. One oracle query — that is the theorem.
"""
function deutsch_jozsa(f, ::Val{N}) where {N}
    x = QInt{N}(0)
    superpose!(x)            # library materialization (§5): H^⊗N on |0⟩
    b = minus()              # |−⟩ literal: QBool(0.5, π)  (D1)

    b ⊻= oracle(f, x)        # Perm applied target-accumulatingly (§3.4):
                             # |x⟩|−⟩ → (−1)^f(x) |x⟩|−⟩ — kickback on x

    return Int(dual(x)) == 0 # Fourier-sample x; all-zero ⇔ constant.
                             # b goes out of scope: traced, silently (§3.9)
end
```

No gates, no angles, one new `⊻=` method. The ancilla needs no explicit
`ptrace!` — scope is the Stinespring boundary and the trace has no
backaction. Every construct is from the §3.8 table.

---

## 8. v0.1 soundness fixes — independent of the redesign

To be fixed on main regardless of v2's schedule (each is a verified defect):

1. `Bool(q)` inside `when()` silently performs unconditional global
   collapse, including of the control. Must be a loud error
   (`measure!` checks `control_stack`). **Most dangerous hole.**
2. Bare `q.θ` is a silent no-op (inert `BlochProxy` read). Make it scream
   (or accelerate its retirement).
3. `qbool.jl:154`: mixed `xor(a::QBool, b::Bool)` applies `Ry(π)` ("X
   gate" comment) = −iY; wrong channel when lifted by `when()`.
4. Aliased control/target (`when(a){not!(a)}`, `add_qft_quantum!(y,y)`)
   caught only at the Orkan FFI shim (`_check_distinct`,
   `src/orkan/ffi.jl:183` — a Julia error since commit `c3d4c00`, so the
   earlier "C assertions only" phrasing was stale), but keyed to raw
   physical qubit indices ("got 0, 0") with no register identity, and
   absent from `when`/arithmetic at the DSL level. Must error at the DSL
   level with WireIDs/register names.
5. Linearity drift: `q.consumed` flag vs `ctx.consumed` set desync
   (demonstrated via `_qbool_views`: `x[1]` manufactures a fresh flag, so
   `Bool(x[1])` leaves `x.consumed == false`). Single-source on the
   context.
6. QSVT/block-encoding `Vector{QBool}` public API (bead `jlaw`).
7. `_apply_ctrls` caps at 2 controls (errors at ≥3) citing an unaudited
   "depth budget" (`src/library/arithmetic.jl:181-189`) — audit or lift.
8. `teleport!` (test/test_teleportation.jl) is physically wrong — no
   conjugate-basis readout; teleports the diagonal only; the
   marginal-statistics test cannot see it (§7.1). Fix the protocol and
   upgrade the test to channel level. Bug bead: `Sturm.jl-wm28`.

---

## 9. Open decision points and research steps

- **D1 — quantum literals: RESOLVED (2026-07-04, Julia-idiom research
  round).** §3.7 *entails* a phase-bearing literal (real stabilizer ops
  cannot manufacture e^{iπ/4}); the spelling is now ruled:
  **`QBool(p::Real, φ::Real = 0.0)`** — one positional-default method,
  on Base's own two-real-DOF constructor pattern (`Complex(x, y)` /
  `Complex(x)`, `base/complex.jl`; likewise `Rational`). `QBool(0.5)`
  call sites are untouched. `p ∉ [0,1]` throws `DomainError` (Base's
  convention for continuous-domain violations — and it falls out of the
  real `sqrt`/`asin` lowering for free, provided the implementation never
  widens to `Complex`). φ is unrestricted. Named library constants
  (`plus() = QBool(0.5)`, `minus() = QBool(0.5, π)`,
  `magic_T() = QBool(0.5, π/4)`) are thin sugar on the constructor —
  Base's `im = Complex(false, true)` pattern. `QBool(β::Complex)` may be
  added later as an amplitude-interop method (runner-up; the
  Riemann-ratio reading is rejected — it has a pole at `QBool(true)`).
  Why this is not a Bloch relapse: the dispositive test is whether a
  form supports `+=`/composition (the killed primitive) or single-shot
  construction only (a literal names a point); and (p, φ) are
  operational — Born probability and relative phase — not bare
  geometric angles. Deliberately NOT generalized: `QMod{d}`/CV literals
  get their own amplitude-tuple design (Base's numeric tower has no
  uniform N-ary constructor scheme either — `Complex`, `Rational`,
  `Quaternion` are each bespoke); `(p, φ)` is the d=2 chart, full stop.
  Required tests: `QBool(1, φ) == QBool(1, φ′) == QBool(true)` (chart
  degenerates at the poles — a fact about literals, made once);
  dispatch check `QBool(true)` hits the `Bool` method
  (`Bool <: Integer <: Real`, more-specific wins); `Float64(φ)` before
  the ccall boundary for `Irrational` args.
- **D2 — `dual` and sub-registers: a semantic fork, not "IR care".**
  `dual(x)` for `x::QInt{W}` is Fourier on ℤ_{2^W}; the per-wire duals are
  Fourier on (ℤ₂)^W — different groups on the same wires, provably
  different unitaries (the QFT has maximal operator entanglement across
  every register cut: Chen–Stoudenmire–White, arXiv:2210.08468; Qwerty
  states the same fact as `fourier[N] ≠ pm^⊗N`). So `dual(x[3])` must NOT
  mean "wire 3 of `dual(x)`" — no such local object exists.
  **RESOLVED (2026-07-04): ruling (i), define-and-throw.**
  - `dual(x[i])` is legal — the ℤ₂ dual of the slice. `dual(x)[i]` is a
    **defined method that throws a descriptive `ArgumentError`** (never a
    bare MethodError): the Base idiom for "in-bounds index, mathematically
    forbidden operation" is `Symmetric`/`Hermitian` `setindex!` on
    off-diagonal entries and `UpperTriangular` `setindex!` into the zero
    triangle (`stdlib/LinearAlgebra/src/symmetric.jl:267`,
    `triangular.jl:270` — `@noinline` throw-helper pattern). Leaving it
    undefined would be the `gcd(pi, pi)` MethodError smell
    (JuliaLang/julia#51673): the call *looks* well-formed precisely
    because `dual(x[i])` and `x[i]` both are. Defining-to-throw keeps
    `hasmethod` honest. The message must state the group-mismatch reason
    and suggest `dual(x[i])`. No custom exception type (YAGNI —
    `NotImplementedError` has sat unmerged in JuliaLang/julia#50196 for
    years; `ArgumentError` + message is the ecosystem answer).
    Construction stays total: `dual(x)` itself never throws — rejection
    lives at the point of use (the LinearMaps.jl `adjoint(::FunctionMap)`
    lesson).
  - `x[i]` ships as **`getindex` sugar for the kernel view mechanism**,
    returning a distinguishable wire-handle wrapper — NOT a bare `QBool`.
    Aliasing getindex is idiomatic for reference types (`Dict` returns
    the stored object; wires are no-clone, hence reference-like), but the
    `SubArray`-vs-`Array` type split is the model: a typed wrapper gives
    Sturm a `Base.dataids`/`mightalias`-style dispatchable aliasing hook
    at the DSL level (owner id + wire index), structurally eliminating
    the consumed-flag desync class of §8.5 instead of re-deriving it from
    a side table. Views borrow, never own (§3.9); returning a view of a
    dying local is a loud error.
  - Involution is a **dispatch-time unwrap on the wrapper's nominal
    type** (`dual(v::DualView) = v.parent`), exactly Base's
    `adjtrans.jl:280` pattern; generic views compose by wrapping.
    Cautionary precedent to cite in the docstring: JuliaLang/julia#20978
    ("Taking matrix transposes seriously") — pre-0.7 Julia defined
    `ctranspose = conj ∘ transpose` by fiat and broke; defining one
    operation as the *evaluation* of a composition, rather than
    structurally, is the same category of bug as lowering `dual` by
    applying F (§3.3: F² = parity, integer negation).
- **D3 — dynamic lifting.** What `Bool(q)` returns under `TracingContext`:
  leading candidate a `ClassicalBit` token; `if token` MethodErrors
  pointing to `cases`. (v0.1's hardcoded-`false` `ClassicalRef` is
  unacceptable.) Scale constraint from the D5 port: the QROM
  measurement-based uncompute branches on a W-bit outcome through a
  2^W-entry classical table — `cases` must either scale past two-way
  branches, or the PRD blesses "measure, compute classically, apply a
  classically-parameterized circuit" as ordinary code (it is, under
  Eager; under Tracing it is dynamic lifting at full width).
- **D4 — materializing views: resolved by counterexample.** Grover's
  diffusion conjugates live entangled registers by H^⊗n — a view
  materialized as a process. Answer: kernel value + library wrap (§5).
  The suspicion "essentially never" was wrong for exactly one of the five
  D5 algorithms, and that one is load-bearing.
- **D5 — the porting experiment: RUN (2026-07-04), bar met.** All five
  algorithms ported on paper against the v0.1 sources; user-level escapes
  = 0 for all five. Highlights: Grover's `_multi_controlled_z!`
  Toffoli-cascade-with-ancilla dissolves into nested `when` +
  `not!(dual(·))` — exact, because CZ's angle is π and kernel `ctrl` is
  closed; DJ's *trailing* `interfere!`+measure collapses into
  `Int(dual(x))` (correction from the D9 round: the *leading*
  `superpose!` does NOT collapse — H^⊗W on |0⟩ is a materialization,
  §5, not a reinterpretation; a uniform-superposition literal is
  deliberately deferred); Draper is `dual(x) += a` with the O(L) angle emission
  moving into the lowering, and the coset layer inherits the same
  one-liner. Library-internal escapes concentrate exactly where §5 now
  licenses them: Grover's diffusion (D4), the control-scope reassociation
  idiom (now a §4.2 law), QSVT phase sequences, PREPARE's rotation tree,
  SELECT's Y-basis change. Open residue: D2 (indexing), D9 (oracle ×
  dual), and the §7.1/§8.8 finding that v0.1's teleport was physically
  wrong for lack of this vocabulary.
- **D6 — `QMod`/CV conjugate structures (research step).** Weyl–Heisenberg
  `dual` for `QMod{d}`; symplectic story for CV. Two verified traps for
  the QMod arm: quadratic Gauss-sum normalization phases bifurcate by
  d mod 4 (Berndt–Evans 1981; Planat–Rosu quant-ph/0506128) — a uniform
  phase-convention code path is silently wrong across parity classes; and
  displacement-operator machinery needs 2⁻¹ mod d, which exists only for
  odd d (Gross quant-ph/0602001; Appleby quant-ph/0412001) — even d
  requires the twisted, period-doubled convention. `dual` for `QMod{d}`
  is one theorem but at least two code paths. P7's anyon arm: braid
  process values exist; whether anyons have a useful `dual` is open — do
  not assume (fusion categories are not groups, §3.3).
- **D7 — Orkan interface.** General 1q-unitary ccall vs Euler ZYZ
  decomposition (3 calls); measure before choosing. Note the ZYZ chart
  singularity at θ≈0/π lives at this boundary and only here (§4.1); the
  ccall shape decides where that branch gets written.
- **D8 — migration & deprecation.** θ/φ proxies: deprecate with loud
  warnings for one release, or remove atomically? `gates.jl` and
  `patterns.jl` rewrite order; test-suite migration strategy.
- **D9 — Bennett `oracle` × `dual` composition: RESOLVED (2026-07-04).**
  The spelling is **`b ⊻= oracle(f, x)`** — one new method on the
  existing `Base.xor` family (`xor(b::QBool, p::Perm)` and the multi-bit
  analogue), applying the `Perm` value target-accumulatingly into `b`.
  No eighth vocabulary item: `a ⊻= b` (CNOT) is literally the W=1,
  f=identity case of the same law. Physics verified at the gate level
  against the v0.1 bridge (`v0.1-deprecated:src/bennett/bridge.jl`):
  Bennett-compiled circuits are built from NOT/CNOT/Toffoli, all
  target-accumulating, and never read the designated output wire as a
  control — so feeding a |−⟩ (or any) initial target implements
  `target ⊕= f(x)` by linearity (Nielsen–Chuang §1.4.4), which is
  exactly phase kickback. v0.1's `oracle(f, x)` fresh-|0⟩ convention was
  a caller-side choice on top of `apply_oracle!`, not a gate constraint;
  the accumulate idiom already existed in the QROM path
  (`qrom_lookup_xor!`). Rejected: `oracle!(f, x, b)` (an eighth
  construct, reads like a gate call); `apply(oracle(f), (x, b))`
  (mentions a process value — banned from surface by §2; it is the
  *lowering* of the `⊻=` method, not a spelling). Worked example: §7.4.
  Note v0.1 never actually built ancilla-kickback DJ (its tests
  hand-wrote phase closures) — this is new, normative design.
- **D10 — region spelling for eager code.** Functions run *as channels*
  get the §3.9 boundary from their signature; plain eagerly-executed
  helpers have no exit hook in Julia and inherit the enclosing region.
  Open: the do-block region form's name (`region() do … end`?
  `@scope begin … end`?), and whether a debug/strict mode should flag
  handles surviving to `@context` teardown. Careful with the second: the
  quantum contract (§3.9) says traces are silent — but a handle that
  reaches context teardown unreferenced usually means a *lost binding*,
  not a chosen trace, and a lost binding is a classical programming
  error, not a quantum one. If flagged at all, flag it as such.
- **Citations TODO (rule 4).** Before implementation, `docs/physics/`
  distillations for: Bădescu–Panangaden 1511.01567 (incl. their §1
  Conditions I–III — primary source for §3.5's guardrails); Gavorová et
  al. 2011.10031 (mark the U(d)→PU(d) "section" phrasing as our gloss —
  the paper speaks of continuous phase functions); Araújo et al.
  1309.7976 (the single-query no-go AND the 1⊕U possibility — the kernel
  argument); Yuan–Villanyi–Carbin 2304.15000 (OOPSLA 2024, not POPL:
  Thm 4.4, Def 4.7, Thms 4.8/4.9); Ying–Yu–Feng 1402.5172 (cite ONLY for
  guard-externality, Def 2.1(4) — its general framework deliberately
  admits non-unitary branches); Fu–Kishida–Ross–Selinger 2204.13041
  (dynamic lifting); Hietala et al. 1912.02250 (VOQC §3.3 — quote their
  abstract-vs-concrete-qubits framing); Raussendorf–Browne–Briegel
  quant-ph/0301052 (the H-wire identity — NOT Zhou–Leung–Chuang);
  Zhou–Leung–Chuang quant-ph/0002039 + Gottesman–Chuang quant-ph/9908010
  (correction ladder); Bravyi–Kitaev quant-ph/0403025 (injection); Qwerty
  2404.12603 (nearest prior art for `dual`); Chen–Stoudenmire–White
  2210.08468 (QFT operator entanglement — D2); Gross quant-ph/0602001 +
  Appleby quant-ph/0412001 (odd/even d — D6); Tang–Wright 2508.00055
  (control exposes global phase — §4.2).

---

## 10. What survives from v0.1 (migration sketch)

**Survives unchanged:** contexts + Orkan FFI; `Channel` DAG + passes +
measurement-barrier discipline (the DAG *gains* a unitarity witness and
becomes a kernel process value); Bennett bridge; casts (minus the
non-consuming debate — v2 confirms consuming); `cases`; promotion; QECC;
`ptrace!`; the entire test-discipline and physics-citation regime.

**Rewritten:** `qbool.jl` surface (BlochProxy deleted); `gates.jl`
(constants move to kernel); `patterns.jl` / `arithmetic.jl` (shrink onto
`dual` + kernel `ctrl` — the D5 port sketches the exact shrinkage per
function); `when` (new lowering); QSVT/block-encoding API (typed
registers, bead `jlaw`, plus kernel `adjoint` replacing hand-written
`oracle_adj!` pairs); `test_teleportation.jl` (protocol is wrong today,
§8.8 — the fix and its Choi-level test land with or before v2).

**Deleted concepts:** Bloch-angle mutation; the SU(2)-only doctrine and its
`H!² = −I` teaching; `_cz!` and controlled-Pauli folklore; the `not!`
*exception* (the function stays; its specialness dissolves).
