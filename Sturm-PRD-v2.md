# Sturm v2 PRD — Processes, Views, and Casts

**Status: DRAFT for argument.** This document is the outcome of the 2026-07-03
ground-up design re-evaluation (bead `Sturm.jl-u9o6`). It supersedes the
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

Two theorem-grade facts, discovered during the re-evaluation, show that v0.1's
`when` never had the semantics its axioms claimed:

- **Quantum alternation has no channel-level semantics** (Bădescu &
  Panangaden, arXiv:1511.01567). `if q then skip else phase(θ)` is a
  controlled-phase, yet `skip` and `phase(θ)` denote the *same channel*.
  Alternation is also non-monotone in the CP order, so coherent control and
  unbounded recursion can never mix.
- **Controlled-U cannot be constructed from black-box access to U**
  (Araújo–Feix–Costa–Brukner, arXiv:1309.7976; strongest form
  Gavorová–Seidel–Touati, arXiv:2011.10031 — a topological obstruction that
  survives postselection, approximation, and indefinite causal order).
  Control requires a *phase-fixed representative*, i.e. a section of
  U(d) → PU(d).

v0.1 squares this circle operationally: the control stack lifts the primitive
*sequence*, silently fixing an SU(2) section. That undocumented section-choice
is the root cause of the `_cz!` ≠ controlled-Rz(π) folklore, the recurring
`3yz` (X vs −iY) bug family, and the defensive comment blocks copy-pasted
across four files.

Additionally, sound coherent-control bodies must be unitary, must not touch
the control, and must leave control disentangled at exit
(Yuan–Villanyi–Carbin, arXiv:2304.15000; Ying–Yu–Feng, arXiv:1402.5172).
v0.1 enforces none of this: `Bool(q)` inside `when()` today performs a
silent unconditional global collapse.

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
  `QBool(b::Bool)` is the definite-bit cast. The full quantum literal
  `QBool(p, φ)` (relative phase) is **open decision point D1** (§9).
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

**Dimension-agnosticism of `dual`:** `QInt{W}` → Fourier-basis view (QFT as
a change of description, not an algorithm); `QMod{d}` → Weyl–Heisenberg
clock↔shift view; CV mode → position↔momentum (where the concept is not an
analogy but the original). This is P7 achieved *by the surface*.

**Where H went:** nowhere — it was never a process in this picture. H is
the change of description between the two views, and surface code only ever
needs the views. Materializing a view as a process (basis change as an
operation on an existing entangled register) is a kernel matter (§9, D4).

### 3.4 Entanglement and flips

`a ⊻= b` (CNOT-composition), `not!` (now *derivable* — the kernel's X is
exact in U(2), see §4.1 — but kept as the idiomatic surface flip),
`swap!`, and the P8 mixed forms. Normative fix carried into v2: the mixed
`xor(a::QBool, b::Bool)` must lower to the kernel's exact X, not `Ry(π)`
(v0.1 latent phase bug at `qbool.jl:154`).

### 3.5 `when` — control flow, with theorem-shaped guardrails

`when(q) do … end` **stays on the surface**: it reads as control flow,
which is normal programming. Its semantics is new:

> `when(q, body)` ≡ trace `body` to a unitary-witnessed process value `V`;
> apply `ctrl(V)` to `(q, wires of body)`.

The guardrails are soundness requirements, not lints (citations in §1.1):

1. The body must trace to a **unitary-witnessed** value: any cast, `ptrace!`,
   `cases`, or noise channel inside `when` is a **loud error**.
2. The body must not operate on the control register — loud error.
3. No unbounded recursion/iteration under `when` — bounded unrolling only.

Nesting composes (`ctrl` is closed). The control register participates as
input *and* output (kickback is physics).

### 3.6 `cases` — the classical branch (Kleisli layer)

Unchanged in role: branching on measurement outcomes is `cases`/`@cases`,
the operational shadow of dynamic lifting (Proto-Quipper, POPL 2023
arXiv:2204.13041). What `Bool(q)` returns under `TracingContext` is **open
decision point D3** (§9): the leading candidate is a `ClassicalBit` token on
which `if` MethodErrors loudly, pointing to `cases`.

### 3.7 Universality of the surface (claim, with proof obligation)

**Claim:** {preparation casts (with D1 literals), `⊻=`/`not!`, `dual`,
measurement casts, classical control} is computationally universal.

**Argument:** arbitrary single-register preparation + xor-entanglement +
measurement + classical correction = gate teleportation / magic-state
injection = measurement-based QC. Continuity enters through *preparation*
(quantum literals), never through mutation primitives. No algorithm can
force a gate back into surface code.

**Proof obligation (research step, rule 8):** write it up properly in
`docs/physics/` with the MBQC citations before v2 implementation begins.
In practice, continuous operations reach users through library HOFs
compiled to the kernel; the universality claim is about *closure*, not
about hand-writing T-gadgets.

---

## 4. Kernel specification

### 4.1 Process values

A **process value** is a definite representative of a symmetry-structure
element — data, not denotation. One abstract type, trait-stratified:

- `U2` — element of U(2) as **unit quaternion + phase** (5 floats).
  Composition = quaternion multiplication: exact, matrix-free. X, Z, H are
  *exact* elements (the v0.1 doctrine "H!² = −I is a feature" dissolves —
  it was an SU(2)-section artifact, not physics).
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
| `Perm` | replay as CX/CCX | same |
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
# surface mutation forms (⊻=, not!, dual-view ops) are sugar that
# consume-and-rebind the same handle internally
```

Enforcement is runtime and **single-sourced on the context's consumed set**
(v0.1's per-object flag becomes at most a cache; the demonstrated
drift-desync between the two mechanisms is thereby fixed). Runtime
linearity is the correct choice for a Julia embedding; a decade of typed
attempts elsewhere (linear wires abandoned as proof-hostile by their own
authors, arXiv:1912.02250) supports this. Aliasing (`when(a){not!(a)}`,
`f(y, y)`) must be caught at the DSL level, not by Orkan's C assertions.

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

### 7.2 Draper addition is addition

```julia
dual(x) += a        # v0.1: add_qft!(x, a) — 100 lines of phase bookkeeping
```

### 7.3 CZ symmetry is visible

```julia
dual(q) ⊻= r        # ≡ dual(r) ⊻= q — controlled-Z, symmetric by notation
```

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
   caught only by Orkan C assertions; must error at the DSL level.
5. Linearity drift: `q.consumed` flag vs `ctx.consumed` set desync
   (demonstrated via `_qbool_views`). Single-source on the context.
6. QSVT/block-encoding `Vector{QBool}` public API (bead `jlaw`).
7. The ≥3-control cap in `_apply_ctrls` cites an unaudited "depth budget" —
   audit or lift.

---

## 9. Open decision points and research steps

- **D1 — quantum literals.** Is `QBool(p, φ)` the right literal syntax, or
  is that φ a Bloch coordinate re-entering through the constructor?
  Position for: literals name *points* (states), not *processes*;
  coordinates on a state space are honest. Position against: two
  real parameters on a constructor is a coordinate chart with opinions.
  Needed for surface universality (§3.7).
- **D2 — `dual` composition with indexing.** `dual(x[3])`, `dual` of a
  sub-register of an entangled whole, views-of-views. Needs IR care;
  `transpose`-style wrapper composition is the model.
- **D3 — dynamic lifting.** What `Bool(q)` returns under `TracingContext`:
  leading candidate a `ClassicalBit` token; `if token` MethodErrors
  pointing to `cases`. (v0.1's hardcoded-`false` `ClassicalRef` is
  unacceptable.)
- **D4 — materializing views.** When (if ever) surface code needs basis
  change as a *process* on existing entangled data; kernel wrap + library
  name if so. Current suspicion: essentially never.
- **D5 — the porting experiment (research step).** Port five v0.1 library
  algorithms (teleport, Deutsch–Jozsa, Grover, Draper/Beauregard
  arithmetic, one QSVT flow) to the v2 surface **on paper**; count escapes
  into kernel vocabulary. Acceptance bar for the surface design: escapes
  confined to library internals.
- **D6 — `QMod`/CV conjugate structures (research step).** Weyl–Heisenberg
  `dual` for `QMod{d}`; symplectic story for CV. P7's anyon arm: braid
  process values exist; whether anyons have a useful `dual` is open — do
  not assume.
- **D7 — Orkan interface.** General 1q-unitary ccall vs Euler ZYZ
  decomposition (3 calls); measure before choosing.
- **D8 — migration & deprecation.** θ/φ proxies: deprecate with loud
  warnings for one release, or remove atomically? `gates.jl` and
  `patterns.jl` rewrite order; test-suite migration strategy.
- **Citations TODO (rule 4).** Before implementation: add `docs/physics/`
  distillations for Bădescu–Panangaden (1511.01567), Gavorová et al.
  (2011.10031), Araújo et al. (1309.7976), Yuan–Villanyi–Carbin
  (2304.15000), and an MBQC/gate-teleportation source for §3.7.

---

## 10. What survives from v0.1 (migration sketch)

**Survives unchanged:** contexts + Orkan FFI; `Channel` DAG + passes +
measurement-barrier discipline (the DAG *gains* a unitarity witness and
becomes a kernel process value); Bennett bridge; casts (minus the
non-consuming debate — v2 confirms consuming); `cases`; promotion; QECC;
`ptrace!`; the entire test-discipline and physics-citation regime.

**Rewritten:** `qbool.jl` surface (BlochProxy deleted); `gates.jl`
(constants move to kernel); `patterns.jl` / `arithmetic.jl` (shrink onto
`dual` + kernel `ctrl`); `when` (new lowering); QSVT/block-encoding API
(typed registers, bead `jlaw`, plus kernel `adjoint` replacing hand-written
`oracle_adj!` pairs).

**Deleted concepts:** Bloch-angle mutation; the SU(2)-only doctrine and its
`H!² = −I` teaching; `_cz!` and controlled-Pauli folklore; the `not!`
*exception* (the function stays; its specialness dissolves).
