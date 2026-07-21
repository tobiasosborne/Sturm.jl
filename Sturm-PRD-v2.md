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
(rulings in §9; DJ worked example in §7.4). Revised again 2026-07-10
(**review round 6** — `Sturm-PRD-v2-review-r6.md`, beads `la0y`/`8fte`):
every surface form was fed to the Julia 1.12.5 parser and the call-LHS
op-assign spellings (`dual(x) += a`, `dual(q) ⊻= r`) died — D11
(bind-the-view mutation idiom), D12 (the value-world/action-world
arithmetic registry), and D13 (`when` operational semantics) are ruled
in their place; the Draper table row was corrected (the view op-assign
is *modulation*, not addition — §3.3, the review's B2); D3 and D10 were
resolved; the citation set survived a second audit with one inversion
fixed (Chen–Stoudenmire–White, §9) and the §3.9/§4.2 positioning
hardened against Silq, current Q#, and "Control as a Constructor"
(arXiv:2508.21756). Normative code blocks in this document are
doctest-linted from milestone 0 (bead `hn90`) — round 6's meta-lesson.
It supersedes the primitive-layer sections of `Sturm-PRD.md` (the θ/φ
rotation surface) and restates the affected axioms. Everything not explicitly changed here —
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
  topological obstruction, their homogeneous-function Lemma 1, an
  elementary winding/homotopy argument (Borsuk–Ulam supplies only the
  even-dimensional intuition), that survives approximation,
  postselection, and relaxed causal order — all three literal in the
  paper). Control requires a *phase-fixed
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

Additionally, sound coherent-control bodies must be unitary and must not
touch the control; and the control *machine's* path/scratch workspace must
be synchronized — disentangled from program data — at exit. The user's
semantic guard is **not** covered by that last condition: a controlled
unitary generally entangles it (`(α|0⟩+β|1⟩)|ψ⟩ ↦ α|0⟩|ψ⟩ + β|1⟩U|ψ⟩` — CNOT
on `|+⟩|0⟩` is the simplest case, and required elsewhere in this PRD), and
kickback onto it is physics; the guard remains a live quantum output.
Attribution, precisely (the earlier draft lumped these): Bădescu–Panangaden's
own §1 already posits guard-externality and reversibility as Conditions I and
III on any alternation; Yuan–Villanyi–Carbin (Quantum Control Machine,
OOPSLA 2024 — arXiv:2304.15000) prove that injectivity (Thm 4.4) plus
synchronization (Def 4.7) are jointly sound *and complete* for
unitarity-with-synchronized-control-*machine* workspace (Thms 4.8/4.9 —
their result is about disentangling the control-flow/path scratch from
program data, not about the user's semantic guard); Ying–Yu–Feng
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
angle, or a process value, it is not surface code. And the converse —
the acceptance bar the D5 port actually used: **if it reads like
ordinary Julia with a few casts and views, it is probably right.**

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
  typing context, exactly our consumed set; Guppy (arXiv:2510.13082)
  moves ownership at `measure(q: qubit @owned)`. Spelling consumption as
  the host language's own *cast syntax* appears to be unprecedented —
  OpenQASM 3 is the near-miss that proves the gap: it has both a
  classical cast system and a `measure` keyword, never merged. Sturm
  enforces at runtime (§4.5) — deliberately between Q# (no linear
  *typing* by design, though the modern QDK does runtime-enforce clean
  release at `use`-block exit — see §3.9's landscape table) and
  Silq/Twist/Guppy's static rejection; the P2 warning is the static
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
representative). Semantics table (spellings per the D11/D12 rulings, §9):

| Surface expression | Meaning | v0.1 spelling it replaces |
|---|---|---|
| `Bool(dual(q))` | conjugate-basis measurement | `H!(q); Bool(q)` |
| `not!(dual(q))` | phase flip (Z = the ℤ₂ **modulation**) | `q.φ += π` |
| `q̂ = dual(q); q̂ ⊻= r` — or `when(r) do not!(dual(q)) end` | phase-entanglement (CZ); symmetric **by theorem** (required test): `q̂ ⊻= r` ≡ `r̂ ⊻= q` | `_cz!(q, r)` folklore |
| `x̂ = dual(x); x̂ += a` | **modulation** — an honest `+=` on the dual register: `Int(dual(x))` shifts by `a`; the phase-kick program under phase estimation and Draper's own inner loop | hand-rolled per-wire phase loops |
| `add!(x, a)` (construct 3, §3.4) | **addition** — translation of x; the kernel lowers it through the dual picture (Draper: F† ∘ phases ∘ F) or as a ripple adder, its choice | `add_qft!` (100 lines of per-wire phase bookkeeping) |
| `Int(dual(x))` | Fourier sampling | `fourier_sample` plumbing |

**Spelling rule (D11).** Julia's op-assignment demands an assignable
location (a variable, field, or index) — `dual(x) += a` is a syntax
error ("invalid assignment location"; a fifteen-year language
invariant, julialang #227/#249/#3217), and `dual(x) = y` inside a
function body silently *defines a local method* shadowing `dual` for
the whole body. The idiom is therefore **bind the view, then work in
the picture**: `x̂ = dual(x); x̂ += a; x̂ += b` — which also makes
batching visible (one F-sandwich, not two; the view-fusion pass, §4.2).
Translation-family operators on a *bound view* mutate the viewed
register in place and return the same view (the §3.4 registration,
extended); `dual`'s docstring must name both parser traps.

**Correction registered (review r6, B2).** An earlier draft's table row
read "`dual(x) += a` = Draper addition". That was backwards: under this
section's own lowering rule, translating the *dual* label is a
**modulation** of x — F†T_aF = M_∓a, the intertwining theorem — so the
view spelling kicks phases and leaves `Int(x)` unchanged, while
*addition* is spelled as addition (`add!`, or value-world `x + a`) and
Draper is the kernel's business. The QBool rows always obeyed the
correct rule (`not!` ↦ X is the ℤ₂ translation; `not!(dual(·))` ↦ Z is
the ℤ₂ modulation); the row had been reverse-engineered from the v0.1
function name rather than derived. The moral improved: **addition is
addition — Draper is how the kernel does it.**

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
involutivity `dual(dual(q)) === q` is Pontryagin's duality theorem; the
view **swaps translation and modulation** (the Fourier intertwining
relation: a conjugated translation *is* a modulation — so `x̂ += a`
kicks phases on x, `add!(x, a)` read in the dual picture *is* the
per-wire phase program, and for `QBool` the swap is the familiar pair
`not!` ↦ X, `not!(dual(·))` ↦ Z); the CZ symmetry `q̂ ⊻= r ≡ r̂ ⊻= q`
is the symmetry of the pairing G × Ĝ → U(1). This is P7 achieved *by
the surface*: one theorem covers every abelian register. The
sign-fixing **Pontryagin unit test** (required) pins every "fixed-once"
convention at once: `superpose!(x); x̂ = dual(x); x̂ += a;
Int(dual(x)) == a` — modulation shifts the dual outcome by exactly `a`
(phase estimation in one line); its translation twin is
`add!(x, 1)` on |0⟩ ⇒ `Int(x) == 1`, not `2^W − 1`. Anyons are the honest exception — fusion
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

**Registers are numbers; views are addressing modes.** Views do NOT
ride P9: the ring operations (`*`, `^`, `&`) do not exist on a view, so
generic numeric code handed one MethodErrors honestly — the same wall as
`g(x::Int)` in the P9 section. The translation family, by contrast, *is*
defined on a view — that is how `x̂ += a` modulates — and because Julia
lowers `x̂ += a` to `x̂ = +(x̂, a)`, **that `+` method is necessarily
effectful**: a bare `+(x̂, a)`, a `map(+, …)`, or any generic code that
reaches the view mutates the underlying register. This is exactly the
julialang #249/#3217 update-operator trap owned for `xor` in §3.4;
we adopt it *knowingly* here too and scope it to views — which is
precisely why views are addressing modes excluded from every generic
value API, never number-like values. (An earlier draft claimed the
mutate-in-place convention "can never leak into generic value code";
that was wrong — `+` on a view can — and it is withdrawn.) A view
supports exactly the casts, the translation family, and `when`; nothing
else.
Wrapper identity is not view identity: each `dual(q)` call constructs a
fresh wrapper (`dual(dual(q)) === q` by unwrap, but
`dual(q) === dual(q)` is `false`), so consumed-set and aliasing
bookkeeping key on (parent wire, transform) — a Sturm-owned hook
*shaped like* Base's `dataids`/`mightalias` protocol (which is
documented but not public API; do not call Base's internals).

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
`>>` is compiled to a *synthesized circuit* (its companion compiler
paper, ASDF arXiv:2501.13262, names "synthesizing circuits from basis
translations" as the core compilation problem), and Qwerty never treats
a basis change as a passive view. Structurally it cannot: `>>` maps
between *arbitrary* user-named bases — a strictly more general
construct — and only `dual`'s narrowing to the one canonical
character-group dual makes a pure reinterpretation possible. The
zero-cost, involutive, `transpose`-idiom view — reinterpretation
dispatching through kernel conjugation, never synthesis — appears to be
novel. The distillation must cite Qwerty *and* ASDF; the
canonicity-buys-the-view point is the differentiator.

**Where H went:** nowhere — it was never a process in this picture. H is
the change of description between the two views, and surface code only ever
needs the views. Materializing a view as a process — basis change as an
operation on an existing entangled register — is applying the view's
unitary as a process value: processes compose, views unwrap. Grover's
diffusion is the canonical customer (§5, D4).

### 3.4 The action family: translations, flips, entanglement (D12)

Surface construct 3 is one P7-parametric family — **the register's
group acting on itself, and its dual**: `not!(q)` (translation by 1 on
ℤ₂), `add!(x, ±a)` / `sub!` (translation on ℤ_{2^W}; the kernel lowers
via Draper or ripple, §3.3), `a ⊻= b` (translation in (ℤ₂)^W by a
register), the bound-view forms (`x̂ += a` — Ĝ-modulation; `q̂ ⊻= r` —
CZ), and the Perm form below. All are bijections of the register —
that is *why* they may mutate in place — plus `swap!` (library sugar:
three `⊻=`) and the P8 mixed forms. `not!` is now *derivable* (the
kernel's X is exact in U(2), §4.1) but kept as the idiomatic flip.
Normative fix carried into v2: the mixed `xor(a::QBool, b::Bool)` must
lower to the kernel's exact X, not `Ry(π)` (v0.1 latent phase bug at
`qbool.jl:154`).

The P8 mixed forms extend to views, with the corrected (r6/B2) reading:
`ŷ += x` with `x::QInt` and `ŷ = dual(y)` is **controlled modulation**
ω^{xy} — the cross-phase kernel inside QFT-multiplication and phase
estimation (v0.1 had no honest spelling for it); quantum-addend
*addition* |x⟩|y⟩ → |x⟩|y+x⟩ is `add!(y, x)` — in-place, bijective,
same lowering family with controlled phases in place of phases. And
note that `+=` on a *bound dual view* is honest where `q.θ +=` was not:
it translates the dual register's own label (an abelian group acting on
itself); the θ-increment notated a commutativity SU(2) does not have.

**`⊻=` also applies `Perm` values (D9 ruling, §9):** `b ⊻= oracle(f, x)`
lowers the Bennett `Perm` target-accumulatingly into `b` —
|x⟩|b⟩ → |x⟩|b ⊕ f(x)⟩ for *any* initial state of `b`, which is what
makes phase kickback ordinary surface code (§7.4). `a ⊻= b` is the W=1,
f=identity case of this same method family, not a separate construct.
`oracle(f, x)` itself returns an *opaque query value*: the only surface
operation on it is `⊻=` application (binding it to a variable is legal;
there is nothing else to do with it), and applying it leaves `x` live —
the Perm reads the argument wires control-like and consumes nothing.

**Named convention exception (alongside `not!`), with its risk
registered honestly:** Sturm's `Base.xor` methods on registers — and
the D11 translation-family methods on *bound views* — mutate their
first argument in place and return the same handle; that is what makes
`a ⊻= b` (which Julia lowers to `a = xor(a, b)`) and `x̂ += a` physical
operations rather than rebinds. Julia's core team spent 2011–2016
rejecting mutating update-operators for the general language
(julialang #249/#3217) precisely because they trap generic code
("`x += y` … you expect this to have no effect on the caller's value");
we adopt the pattern *knowing that*, on two grounds: no-cloning means
there is no value reading a caller could legitimately have expected for
the entangler, and the exception is scoped to the bijective action
family — it is **never generalized to ring ops** (see the two-world
registry below). Note the mixed-direction asymmetry, both directions
wanted: `q ⊻= true` flips `q` in place (kernel X); `c = false ⊻ b`
promotes the classical side to a *fresh* |0⟩ register and entangles it
(the Bell-pair idiom of §7.1).

**The two-world registry (D12 ruling).** Julia's syntax makes
`x += a` ≡ `x = x + a` non-negotiable, so the arithmetic surface splits
by physics:

| Form | World | Effect |
|---|---|---|
| `s = a + b`, `p = a * b`, generic P9 code | **value** | fresh output register; inputs stay live (reversible dataflow); garbage discipline via `oracle` |
| `a ⊻= b`, `not!(a)`, `add!(x, a)`, `b ⊻= oracle(f, x)` | **action** (registered) | in-place bijection; handle stable |
| `x̂ += a`, `x̂ ⊻= r` on a bound view | **action** (registered, D11) | in-place translation/modulation through the view |
| `x += a` on a *bare register* | value **rebind** | legal but it is the lost-binding pattern: the old register is silently traced at region exit and, if it was superposed, the adder has already entangled it with the survivor — the sum decoheres. D10's strict mode flags exactly this (§3.9); the docs teach `add!` or the view idiom instead |

Ring operations between quantum values are value-world by force: an
in-place `x*y` or `x^2` is not even a bijection of the register
(irreversible), and a mutating `+` would silently clobber inputs under
generic read-reuse code — P9 is a pillar, so `+` allocates.

**Caveat on the generic-f path (P8/P9), mechanism corrected (r6):**
`b ⊻= f(x)` with a hand-written generic `f` is unsafe for multi-step
logic either way the operators could have been defined. Under the
registered action-world `⊻`, a fold like `x[1] ⊻ x[2] ⊻ x[3]`
accumulates *into wire 1 in place* — corrupting the input register
rather than allocating garbage; under value-world arithmetic, the
intermediates are fresh registers that leave scope entangled and the
silent boundary trace (§3.9) then correctly reports a decohered
survivor — the interference the algorithm needed is already gone (the
computation did it, not the trace). Consequence for P9's generic-path
promise: it is scoped to **arithmetic and comparison operators**;
generic *bitwise* logic does not have value semantics on registers and
goes through `oracle(f, x)`, where Bennett's compute-copy-uncompute
restores value semantics *by construction*. This is the quantum
contract of §3.9 applied to P9's generic path.

**Bennett strategy selection is control-aware (normative).** The
bridge's cost model may choose measurement-based uncompute (MBU) —
measure ancillas, branch classically, fix up. MBU's *composite channel*
equals the unitary uncompute, but it is not a process value, and §4.4
makes measurement under `ctrl` unrepresentable. Therefore: under a
nonzero control stack (or inside a traced `when` body), MBU-flavored
strategies are **excluded** from selection; outside, they remain
available. This is §1.1's theorem walking — two implementations equal
*as channels* are distinguishable *under control* — and it is the
cleanest live illustration of why the channel/process-value
stratification exists. Without this rule, the first `when`-wrapped QROM
oracle ships a soundness bug.

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

1. The body must trace to a **unitary-witnessed** value: any **measurement
   (qc) cast** (`Bool`, `Int`), `ptrace!`, `cases`, or noise channel inside
   `when` is a **loud error**. Canonical fresh-|0⟩ allocation — spelled
   `QBool(false)` — is *permitted*: it is the blessed alloc-inside-`when`
   scratch pattern (the compute–uncompute lemma below), a preparation
   *without* backaction, not a qc cast. An arbitrary literal `QBool(p, φ)`
   (p ∉ {0}, or φ ≠ 0) under `when` is neither — controlled preparation is
   phase-ambiguous (different unitary extensions of the preparation differ
   by a global phase observable under outer `ctrl`), so it awaits an
   explicit ruling and is a loud error naming **D15** until then.
2. The body must not operate on the control register — loud error.
3. No unbounded recursion/iteration under `when` — bounded unrolling only.

The ban has a direction: `cases` inside `when` is guardrail 1; `when`
inside a `cases` branch is fine — each branch is an ordinary
post-measurement channel. Nesting composes (`ctrl` is closed). The control
register participates as input *and* output (kickback is physics).

**Operational semantics (D13 ruling).** The definition above ("trace,
then apply ctrl(V)") is the *semantics*; the §4.2 homomorphism law
`ctrl(g ∘ h) ≈ ctrl(g) ∘ ctrl(h)` is the license to implement it
**streamingly** — applying `ctrl(op)` op-by-op as the body executes.
That is v0.1's control stack, now justified by a law instead of an
accident, and it fixes the enforcement story per context:

- **Eager (streaming):** guardrail 1 is a runtime law — any
  cast/`ptrace!`/`cases`/noise attempt while the control stack is
  nonempty is a loud error (v0.1 defect §8.1's fix, promoted to
  semantics). Guardrail 2 is a per-op aliasing check that **sees
  through views** (`when(q) do not!(dual(q)) end` is aliased — views
  resolve to parent wires). Clean-ancilla exit (§3.9): assert the
  ancilla's |1⟩-block norm is exactly 0 before dealloc — cheap on a
  statevector. Streaming soundness for alloc-inside-`when` is the
  compute–uncompute lemma: alloc (uncontrolled) → ctrl(U) → dealloc
  (uncontrolled) equals ctrl(dealloc ∘ U ∘ alloc) *provided* U cleans
  the ancilla in the control=1 branch — the §3.9 witness is exactly
  that proviso, and an unclean ancilla under a superposed control would
  decohere the control, which is why the unwitnessed case errs loudly.
- **Tracing (materialize):** the body traces to a `UnitaryDAG` with
  witness; guardrails are checked on the DAG; materialization is what
  enables the §4.2 reassociation pass and ctrl-of-DAG fusion.
- **Required law test:** streaming and materialized execution of the
  same body denote the same channel (Choi-compared on small instances).

Two semantic footnotes, stated so users don't discover them: *classical*
side effects in a `when` body (printing, pushing to a Julia array) are
stream/trace-time effects, not controlled effects — a wart every
embedded circuit DSL shares; and the body's closure runs exactly once
under either strategy. Anti-control has no dedicated form: the idiom is
the `not!` sandwich (`not!(q); when(q) do … end; not!(q)`) or `cases`
after measurement — blessed here so Grover-style zero-reflections don't
go hunting for an `unless`.

### 3.6 `cases` — the classical branch (Kleisli layer)

Unchanged in role: branching on measurement outcomes is `cases`/`@cases`,
the operational shadow of dynamic lifting (Proto-Quipper, POPL 2023
arXiv:2204.13041). **D3 is RESOLVED (r6):** under `TracingContext`,
`Bool(q)` returns a `ClassicalBit` token and `Int(x)` a `ClassicalInt`
token — Proto-Quipper's *parameter* (circuit-generation-time value) as
opposed to a *state* (execution-time value); `if token` / `token && …`
throw a descriptive error pointing to `cases`. The shipped precedent is
qrisp's Jasp (a measured value is a dynamic tracer; the host `if` is
refused; branching goes through a dedicated construct), with
Proto-Quipper-Dyn as the type-theoretic backing. **`cases` does not
scale to 2^W branch tables and is not asked to:** the blessed pattern
for wide outcomes is *measure → (traced) classical computation →
classically-parameterized circuit* — a `ClassicalInt` flows through
ordinary Julia arithmetic/indexing, and only *branching* on it is
diverted to `cases`. Under Eager this is literally ordinary code; under
Tracing it is dynamic lifting at full width, again the Jasp model
(dynamic loop bounds and indices, compiled once, no 2^W table). The
QROM measurement-based-uncompute case that motivated the worry lowers
this way.

### 3.7 Universality of the surface (claim, with proof obligation)

**Claim:** {preparation casts (with D1 literals), `⊻=`/`not!`, `dual`,
measurement casts, classical control} is computationally universal.

**Argument:** one-bit teleportation makes H a *gadget*, not a gate:
prepare |+⟩ (a cast), entangle with CZ (`q̂ ⊻= r` after `q̂ = dual(q)`,
or `when` + `not!(dual(·))`), measure in the conjugate basis, correct
with Pauli flips — the MBQC elementary-wire identity (Raussendorf–Browne–Briegel, quant-ph/0301052 §II; note this is
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
Implementer caveat verified in review r6: the T-gadget's correction (S)
is a **non-Pauli Clifford**, so Pauli-frame tracking alone cannot close
the ladder — the correction needs live classical feedback (available in
the generating set) or a recursive S-gadget; {H, X, Z, CNOT} are all
real matrices, which is *why* S must be injected and the complex unit
enters only through literals. In practice, continuous operations reach
users through library HOFs compiled to the kernel; the universality
claim is about *closure*, not about hand-writing T-gadgets.

### 3.8 The v2 surface vocabulary (normative table)

The v0.1 constitution's five-construct table (CLAUDE.md rule 11) is
superseded by:

| # | Surface form | Role | Lowering (kernel) |
|---|---|---|---|
| 1 | `QBool(p, φ=0)` / `QBool(b)` (D1) | preparation cast (cq) | allocate + literal `U2` |
| 2 | `Bool(q)`, `Int(x)` — consuming | measurement cast (qc) | instrument; consumes handle |
| 3 | `a ⊻= b`, `not!(a)`, `add!(x, ±a)`, P8 mixed forms | the action family: translations / flips / entanglement (D12) | kernel X / T_a / `ctrl(X)` |
| 4 | `dual(q)`; bound-view actions `q̂ ⊻= r`, `x̂ += a` | conjugate view (Pontryagin) + Ĝ-modulations (D11) | conjugation by F_G |
| 5 | `when(q) do … end` | coherent control | trace/stream body → `ctrl(V)` (D13) |
| 6 | `cases` / `@cases` | classical branching | Kleisli / dynamic lifting (D3) |
| 7 | `oracle(f, x)` | Bennett bridge | `Perm` value |

Everything quantum a user writes is these seven; arithmetic and generic
Julia code ride P8/P9 as before (generic path scoped to
arithmetic/comparison — §3.4). Rows 3–4 are one family seen twice:
G-translations and their Ĝ-duals, with views as the addressing mode
(registers are numbers; views are not). If a program needs an angle, it
needs the library; if a library function needs an angle, it builds a
process value.

**Context portability (normative table).** Exactly one row of the
surface is context-sensitive:

| Construct | Eager | DM | Tracing | Hardware |
|---|---|---|---|---|
| casts, action family, `dual`, `when`, `oracle` | ✓ | ✓ | ✓ | ✓ |
| `if` / `&&` on a measured outcome | ✓ | ✓ | ✗ token error → use `cases` (D3) | ✓ |
| `cases` / `@cases` | ✓ | ✓ (exact, both branches) | ✓ (`CasesNode`) | ✓ |

**DensityMatrixContext executes channels, not trajectories
(normative).** Measurement and `cases` on the DM context apply the full
instrument — all branches evolve, weighted, block-accumulated (each
branch's local ancillae traced to the common output signature first;
Born weights ride in the unnormalized branches). One run therefore
yields the *exact* channel, which is what makes the Choi-level test
discipline (rule 12) cheap: `Choi(teleport) ≈ Choi(id)` is a
deterministic one-run assertion, no shot averaging. Trajectory sampling
remains available as an explicit shot API. Harness note: the Choi state
of a W-wire channel lives on 2W wires, but the DM-context test evaluates it
as a *density matrix* — 2^{4W} complex entries — so the binding limit is
memory, not the pure-state qubit ceiling. Orkan's ~30-qubit (≈2^{30}-
amplitude) budget therefore caps an exact dense-Choi law test at **≈7
wires** (4W ≲ 30), NOT 15 — a 15-wire Choi would be a 30-qubit density
matrix, 2^{60} complex numbers (~16 EiB). Still ample for the named laws,
which are all small; wider channels need randomized reference-assisted,
stabilizer, or tensor-network Chois rather than a dense one. Two test-design
rules bought with review-r6 derivations: the cq∘qc pinching test must
probe a *coherent* input (pinching and identity coincide on diagonal
inputs), and teleport-class channel tests must probe a Z-*sensitive*
state (|i⟩ or |+⟩) — the X-outcome-labeling bug class turns teleport
into a Z-error channel invisible to Z-basis probes (wm28's family).

### 3.9 Scope is the Stinespring boundary

Registers obey a scope discipline that is not a convenience feature but
the P1 denotation itself:

- **Entry: allocation is initialization.** A fresh register comes into
  existence in the canonical state its type declares — |e_G⟩, the basis
  state of the group identity, for finite G (|0⟩ for
  `QBool`/`QInt`/`QMod`); the vacuum for CV (which is *not* a
  group-basis state — |x=0⟩ is non-normalizable, so the finite-G
  phrasing deliberately does not generalize); the trivial charge for
  anyons. There is no uninitialized register and no bare-allocation
  surface form; `QBool(p)` builds from the canonical state by
  construction, and the choice is the quantum computational model's,
  not ours. (A fresh |0⟩ read through `dual` is
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

**Why not Silq-style auto-uncompute? (positioning, owned explicitly.)**
Silq (PLDI 2020) *uncomputes* `qfree`/`lifted` temporaries at scope
exit — running the classical-reversible computation backwards — and
rejects dropping anything else as a type error; a forgotten
Grover-oracle ancilla is thus *repaired* in Silq and *silently mixes
the survivors* in Sturm. We accept that trade deliberately, on four
grounds: (i) qfree-scope is narrow — genuinely quantum locals
(discarded syndromes, environment modes, anything non-classically-
reversible) are *rejected* by Silq's discipline and correctly traced by
Sturm's, and discard-as-trace is the honest general denotation;
(ii) auto-uncompute silently ~doubles a block's gate cost — Sturm makes
the expensive thing (uncompute) explicit and the free thing (trace)
implicit, Silq the reverse, and cost transparency is a design value
here; (iii) purity-on-demand already exists *by construction* through
Bennett's `oracle` (compute-copy-uncompute); (iv) the opt-in strict
mode below catches the forgotten-uncompute *bug* without making the
*semantics* nag. The design space's newest point, Qurts
(arXiv:2411.10835, affine types + lifetimes for uncomputation), sits on
Silq's side of the trade. The end-of-scope landscape, for honesty about
how contrarian this is:

| Language | End-of-scope discipline |
|---|---|
| Q# (current QDK) | must-be-clean: runtime error unless |0⟩ at `use`-exit |
| ProjectQ | must-be-clean: simulator raises on superposed dealloc |
| Guppy | must-be-consumed: implicit discard is a compile error |
| Silq / Qurts | auto-uncompute lifted values; reject the rest |
| Quipper | explicit: assertive termination or explicit discard |
| QWIRE / Proto-Quipper | explicit `discard` = partial trace (the denotation, at the call site) |
| **Sturm** | **automatic, silent trace = the P1 denotation at region exit** |

The discard-equals-trace *denotation* is standard (QWIRE); making it
automatic, silent, and the meaning of scope itself is the departure —
it inverts the dominant "superposed at scope exit = probable bug"
stance, because under P1 it is not a bug, it is a channel.

Mechanics, in order of the frictions they resolve:

- **Regions, not GC.** Julia finalizers are nondeterministic; the trace
  is part of the denotation and must sit at a definite circuit position
  (on `TracingContext` the DAG would otherwise depend on GC timing).
  Region boundaries are explicit: `@context` blocks (deterministic
  cleanup — v0.1 shipped this in bead `sv3`; v2 builds it on
  `Base.ScopedValues.with`, see below), functions executed *as
  channels* (traced bodies, `oracle`, `Channel` invocation — the
  signature names the outputs), `when` bodies, and the manual form
  **`region() do … end` (D10 ruling)** — a bare-noun do-block in Base's
  own resource idiom (`open`, `lock`, `mktempdir`); "scope" was
  rejected as doubly claimed in Julia (lexical scope +
  `Base.ScopedValues`). Plain eagerly-executed helper functions have no
  exit hook in Julia and inherit the enclosing region — and this is
  *provably harmless*, not a compromise: traces have no backaction, so
  trace *timing* is denotationally invisible; where a region boundary
  falls is purely a resource/DAG-shape question. (Corollary for the
  test discipline: the pure-context measure-and-discard lowering
  advances the RNG, so *seeded* tests must never assert trace
  placement — statistics are invariant, streams are not.) A GC
  finalizer may at most *detect* a lost handle in debug builds, never
  trace it.
- **Context propagation is `ScopedValue`-based.** `current_context()`
  reads a `Base.ScopedValue` (stdlib since 1.11), not
  `task_local_storage`: ScopedValue bindings inherit into
  `Threads.@spawn`/`@async` children (TLS does not — verified, a
  silent-missing-context bug class deleted outright), and
  `with(sv => ctx) do … end` is a genuine `try`/`finally` — exactly the
  deterministic exit a region needs. Julia 1.12's own NEWS migrates
  Base the same way. The binding is immutable per scope (correct for
  propagation); v2's concurrency assumption until a real story is
  designed: one region, one task.
- **Strict mode (D10 ruling): the lost-binding detector.** The `x += a`
  rebind trap (§3.4), the generic-f fold trap, and "a handle survived
  to teardown" are one defect signature: *at region exit, a traced
  register that is an entangling-op parent of a surviving register*.
  Debug/strict mode tracks one parent edge per fresh-output op and
  flags exactly that — as a **classical** programming error (a lost
  binding), never as quantum nagging. The default remains silent; the
  doctrine above is untouched.
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
  the θ≈0/π coordinate singularity of any three-angle chart (cf.
  Stuelpnagel 1964 — a topological fact about SO(3), extending
  immediately to SU(2); not a convention choice) is confined to that
  single extraction site, while composition itself stays chart-free.
  **Equality is double-cover equality (normative — review r6/M2).** The
  5-float representation is 2-to-1 onto U(2): (q, φ) ~ (−q, φ+π) are
  the *same* element, and exact H satisfies H² = (−1_quat, π) — the
  *other* representative of +I — so the law `H ∘ H ≈ I` fails
  naive tuple equality. Semantic process-value comparison is therefore
  mod that ℤ₂ — a dedicated `isapprox`/`same_process` predicate
  (canonicalize, compare both representatives, or compare the denoted
  matrices e^{iφ}R(q)). It is deliberately **not** Julia `==`/`hash`:
  tolerance-based equality is non-transitive and would corrupt any dict or
  cache keyed on process values, so `==` stays *exact-structural* (it does
  not identify drifted double-cover representatives — that is
  `same_process`'s job, and the shipped kernel implements exactly this
  split). The quotient predicate carries two guardrails: the quotient must
  **never merge +I with −I** — `Ry(2π) = (1_quat, π) = −I` is physics
  (spinor 4π-periodicity) and ctrl(−I) is a real CZ-grade operation, so
  a test asserting `Ry(2π) == I` is *wrong* and "fixing" H² by
  quotienting the global sign would re-import the SU(2)-section disease
  at the equality predicate; and float laws compare with ≈ — the
  "exact" claims here are group-structural (X, Z, H land on exact
  elements; no section residue), never claims about float arithmetic.
  Prior art: no surveyed compiler or simulator uses quaternion+phase as
  its persistent 1q IR (surveyed: Qiskit's `OneQubitEulerDecomposer` /
  narrow `Quaternion` utility, tket's `EulerAngleReduction`
  fuse-to-matrix, VOQC/SQIR matrix semantics, staq, quartz, queso;
  Fraxis/FQS quaternions parameterize VQE ansätze) — the quaternion↔
  SU(2) identification itself is textbook (cite Wharton–Koch,
  arXiv:1411.4999); the novelty is the *persistent-IR-with-quaternion-
  composition* engineering choice.
- `Perm` — reversible permutation (every Bennett.jl artifact). Canonical
  0/1 matrices: **no phase freedom at all** — and closed under control:
  **ctrl(Perm) is a Perm** (a controlled permutation is a permutation),
  so controlled oracles never leave the zero-phase-freedom corner. The
  classical-reversible corner is the best-behaved under control, as
  befits a Bennett-centric language, and that one-line closure fact is
  the proof.
- `UnitaryDAG` — a `Channel`-style DAG carrying a unitarity witness
  (produced by tracing `when` bodies and library circuits).
- Future per-register-type structures (P7): **U(d)** values for `QMod{d}`
  (phase-carrying: a definite representative is φ + `SU(d)` modulo the ℤ_d
  center, `(S, φ) ~ (ζS, φ − arg ζ)`, ζ^d = 1 — `SU(d)` *alone* would
  discard exactly the global-phase information `ctrl`/P4 needs, re-importing
  the §1 disease at the qudit layer, because Fourier/Weyl/Clifford
  representatives carry determinant-dependent phases observable under
  control), symplectic+displacement for CV, braid-group elements for anyons
  (discrete — the process-first view covers them; a generator view never
  could).

A register type declares its symmetry structure the way a Julia number type
declares its arithmetic. The kernel is parametric in it.

### 4.2 The algebra (normative laws = required tests)

`∘` (composition), `⊗` (parallel), `adjoint`, `ctrl`. Convention,
stated once: `∘` is right-to-left matrix composition ("apply the right
operand first"), so `V ∘ W ∘ V†` means V·W·V†. Laws (each `==` below is the
semantic U(2)-quotient predicate of §4.1 — `≈`/`same_process` on floats,
**never** Julia `==`, which stays exact-structural):

- `Ry(a) ∘ Ry(b) ≈ Ry(a+b)` — dynamics as a representation of (ℝ, +),
  now a testable identity on quaternions (and `Ry(2π) ≈ −I`, `≉ I`:
  the double cover is physics, §4.1);
- `ctrl(g ∘ h) ≈ ctrl(g) ∘ ctrl(h)` — `ctrl` is a group homomorphism
  U(d) → U(2d), **not** a channel map (it distinguishes `g` from
  `e^{iα}g`; that is its job);
- `adjoint(ctrl(g)) ≈ ctrl(adjoint(g))`;
- `ctrl` is closed: `ctrl(ctrl(g))` is Toffoli-grade control, no special
  case. Single-qubit gate fusion becomes quaternion arithmetic — v0.1's
  `gate_cancel` commutation table is subsumed for 1q rotations by exact
  group multiplication *before anything touches Orkan*.

Two further normative constraints, both bought with other people's bugs:

- **`ctrl` is the only constructor of controlled lowerings in the entire
  system.** Cirq, Qiskit, and pytket each carry a dedicated global-phase
  field, and each shipped controlled-decomposition phase bugs for years
  anyway (Cirq #1161/#4275; Qiskit #4949 — diagonal gate's phase wrong
  precisely when used in a *controlling* circuit — and #7167's
  general phase-tracking cluster plus the `.control()` AttributeError
  family; pytket's QControlBox, buggy < 0.17.0) — because the bug lives
  at whichever call site builds the controlled circuit, and there were
  many. The representation alone does not fix this class; a single
  choke point, total on process values, does. (Tang–Wright,
  arXiv:2508.00055 Thm 1.1, is the formal statement of why control
  makes global phase physical.) The *concept* now has categorical prior
  art — "Control as a Constructor" (arXiv:2508.21756: control functors
  extending props to controlled props, with a ≤3-qubit completeness
  payoff) — which supports rather than competes: Sturm's contribution
  is the *implementation instantiation*, one total code path on
  phase-fixed values, where the mainstream's per-gate `.controlled()`
  entries are many (even Qiskit 2.3's `control(annotated=true)`
  transpiler deferral centralizes only partially, per gate entry, not
  total on phase-carrying values).
- **Control-scope reassociation is a kernel law, not folklore:**
  `(1 ⊗ V) ∘ ctrl(W) ∘ (1 ⊗ V†) == ctrl(V ∘ W ∘ V†)` when `V` acts only
  on the body's wires. v0.1 hand-proves and hand-codes this identity at
  three independent sites (`modadd!`'s `ctrls` kwarg, `_pauli_exp!`'s
  control-stack surgery, the QSVT reflector) to avoid controlling whole
  circuit bodies. In v2 it is (a) a tested law on process values, (b) the
  kernel pass that narrows control scope automatically, and (c) a named
  combinator for library authors: **`within(V) do … end`** (ruled — the
  name is Q#'s own `within…apply`, the one mainstream construct that
  matches a v2 kernel law exactly; the distillation cites it as
  precedent). A second pass rides the same machinery: **view-fusion** —
  lazy views lower per-operation, so adjacent same-picture operations
  emit F† … F pairs that must cancel (on Tracing, a kernel pass; on
  Eager, a per-wire "current picture" tag flushed at basis-crossing
  ops — v0.1's `add_qft!` batching, generalized). Without it,
  `x̂ += a; x̂ += b` costs four Fourier sandwiches instead of two. The
  most-repeated non-trivial idiom in the v0.1 library must not remain
  hand-rolled.

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
  outputs). Process *applications* lie in `im(Ad)`; a program is a composite
  in the symmetric monoidal category **generated by** those applications
  together with preparation, instruments, classical control, and trace —
  measurement, discard, reset, and noise are CPTP but *not* unitary
  conjugations, so they lie outside `im(Ad)` itself (§4.4's stratification).
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
- **P8 / P9 — Promotion; registers are numeric types.** Unchanged in
  mechanism, *scoped* in promise (D12): the generic path covers
  arithmetic and comparison operators (value world — fresh outputs,
  inputs live); bitwise logic on registers is action-world (`⊻`
  mutates — the registered exception) and generic bitwise code goes
  through `oracle`, where Bennett restores value semantics by
  construction. Views are not numeric and do not ride P9 at all.

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

**Convention pin and portability.** The X-readout labeling is forced:
|+⟩ ↦ `false` (it falls out of the instrument lowering F†P_kF);
reversing it turns this listing into a *Z-error channel that Z-marginal
tests cannot see* — wm28's failure class reproduced from the convention
side — so the required Choi test probes |i⟩ or |+⟩, never just Z
states. And the `&&`-corrections make this listing **Eager/DM/Hardware
only**: under Tracing, measurement returns a token (D3) and the
branching must be `cases` — or use the deferred variant below, which is
fully context-portable.

### 7.1b Teleportation, deferred — the same channel, no branching

```julia
"""
    teleport_deferred(ψ::QBool) -> QBool

The deferred-measurement variant: corrections run coherently BEFORE any
cast, so there is no classical branching and the listing traces as-is.
Denotes the same identity channel (a free second Choi test). Note what
does NOT appear: no casts at all — ψ and b are simply not returned, so
the region traces them (§3.9), which is exactly measure-and-discard.
"""
function teleport_deferred(ψ::QBool)
    b = QBool(0.5)
    c = false ⊻ b                # Bell pair on (b, c)
    b ⊻= ψ

    when(b) do                   # deferred X-correction
        not!(c)
    end
    when(dual(ψ)) do             # deferred Z-correction: control read in the
        not!(dual(c))            # conjugate basis — |−⟩⟨−| ⊗ Z, exactly
    end
    return c                     # ψ, b: owned, unreturned — traced, silently
end
```

### 7.2 Addition is addition (Draper is how the kernel does it)

```julia
add!(x, a)          # in-place x ← x + a (mod 2^W); the kernel lowers via the
                    # dual picture (Draper) or a ripple adder — its choice
s = x + a           # value world: fresh output register, x stays live (D12)
```

v0.1's `add_qft!` was 100 lines of per-wire phase bookkeeping; those
lines still die — inside the kernel's lowering of T_a, which is where
"no gates in surface code" wanted them all along. The dual-*view*
op-assign is a different (and also indispensable) operation — an honest
`+=` on the dual register (§3.3, r6/B2):

```julia
x̂ = dual(x)
x̂ += a              # modulation: Int(dual(x)) shifts by a; Int(x) unchanged —
                    # the phase-kick program under phase estimation
```

### 7.3 CZ symmetry is a theorem, and both spellings are writable

```julia
q̂ = dual(q); q̂ ⊻= r    # controlled-Z: X through q's dual view, control r
r̂ = dual(r); r̂ ⊻= q    # the SAME channel — symmetry of the pairing G × Ĝ
                        # (two CZs in sequence = identity: the lines above are
                        #  alternative spellings, and running both proves it)
```

Equivalently `when(r) do not!(dual(q)) end`. The symmetry
`q̂ ⊻= r ≡ r̂ ⊻= q` is a required Choi-level test; the one-line
`dual(q) ⊻= r` of earlier drafts is not writable Julia (D11).

### 7.4 Deutsch–Jozsa over an arbitrary Julia function (D9)

> **Precondition (weakdep, F36).** `oracle(f, x)` ships in the
> `SturmBennettExt` package extension (Project.toml `[weakdeps]`/
> `[extensions]`), so this example and §7.5 require `using Bennett`
> *alongside* `using Sturm` to activate the bridge — `using Sturm` alone
> does not load it. (`using` cannot appear inside the function body; it is
> the caller's session/module import.)

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

**Why the ℤ_{2^N} dual decides DJ** (worth one sentence, because it is
a coincidence with a boundary): the k=0 row of the QFT *is* the
uniform-average row of H^⊗N, and DJ interrogates only that
component — outcome 0 has amplitude (1/2^N)Σ_x(−1)^{f(x)} = ±1
(constant) / 0 (balanced), insensitive even to the F-vs-F† direction
*for outcome 0 alone*. **The pattern does not port**: for any protocol
reading nonzero outcomes — Bernstein–Vazirani first among them — the
register dual and the per-wire duals are inequivalent (D2), and §7.5 is
the required counter-example.

### 7.5 Bernstein–Vazirani — the per-wire duals (D2 made operational)

```julia
"""
    bernstein_vazirani(f, ::Val{N}) -> Int

`f(x) = s·x mod 2` for a secret s; one query recovers s exactly. The
readout is the PER-WIRE duals — the (ℤ₂)^N Fourier basis. The §7.4
pattern `Int(dual(x))` would NOT recover s: the register dual is
Fourier on ℤ_{2^N}, a provably different unitary (D2) — for N=3, s=5
its outcome distribution is {1: 0.073, 3: 0.427, 5: 0.427, 7: 0.073},
spread and tied. Copy-pasting §7.4 here is the canonical D2 bug.
"""
function bernstein_vazirani(f, ::Val{N}) where {N}
    x = QInt{N}(0)
    superpose!(x)                           # H^⊗N materialization (§5)
    b = minus()
    b ⊻= oracle(f, x)                       # (−1)^{s·x} kickback (§3.4)

    bits = [Bool(dual(x[i])) for i in 1:N]  # ℤ₂ dual of each wire — legal
                                            # under D2; consumes x wire-wise
    return evalpoly(2, reverse(bits))       # s — bits is wire-1=MSB-first (M6
                                            # pin); evalpoly wants LSB-first.
                                            # b traced (§3.9)
end
```

**Endianness ruling (bead 6xdk, 2026-07-19).** `x[i]` follows the M6
wire-1 = MSB pin, so `bits` comes out MSB-first and the readout must
`reverse` it before `evalpoly`. An earlier draft's `# s, LSB-first`
comment assumed the opposite convention and returned `reverse_bits(s)`
for every non-palindromic secret (empirically confirmed on all 8 3-bit
secrets; the listing's own s=5 is palindromic and masked it). §7.7's
control schedule obeys the same pin: wire 2W is the LSB and takes the
a^{2⁰} factor.

### 7.6 Magic-state injection — `cases`, literals, and the ladder

§3.7's universality argument as running code: the literal is the
resource, `cases` is the adaptive step, and the correction ladder
terminates on native Z. (`@cases m …` measures `m` — consuming it — and
runs the branch on outcome 1; under Tracing it captures both branches,
§3.6.)

```julia
function inject_S!(ψ::QBool)
    m = QBool(0.5, π/2)       # |i⟩ — the S resource is a literal (D1)
    m ⊻= ψ                    # entangle: CNOT, target m, control ψ
    @cases m begin
        not!(dual(ψ))         # outcome 1: Z-correction — native (§3.3)
    end
    return ψ
end

function inject_T!(ψ::QBool)
    m = QBool(0.5, π/4)       # magic_T() — the T resource
    m ⊻= ψ
    @cases m begin
        inject_S!(ψ)          # outcome 1: S-correction — the ladder recurses,
    end                       # and inject_S!'s own correction is native Z
    return ψ
end
```

The T-gadget's correction is a **non-Pauli** Clifford (S) — this
example is precisely why the surface needs live classical adaptivity
and not just Pauli-frame bookkeeping (§3.7).

### 7.7 Order finding (Shor) — the capstone composition

```julia
"""
    shor_order(a, N, ::Val{W}) -> Int

Order finding for a mod N: oracle-grade modular arithmetic, coherent
control, Fourier sampling, and classical post-processing — nothing but
the seven constructs and library verbs. (Sketch: the production version
uses the semiclassical iQFT and coset registers, both ported on paper
in D5.)
"""
function shor_order(a, N, ::Val{W}) where {W}
    k = QInt{2W}(0)
    superpose!(k)                    # phase register
    y = QMod{N}(1)                   # work register ≡ 1 (mod N)

    c = a % N
    for j in 2W:-1:1                 # classical loop, quantum body (P8/P9).
                                     # LSB-upward: wire j weighs 2^(2W−j)
                                     # (M6 MSB pin — 6xdk ruling), so wire
                                     # 2W takes c = a^(2^0), wire 1 the top
        when(k[j]) do                # wire-handle control (D2)
            mulmod!(y, c)            # library: in-place y ← c·y (mod N) —
        end                          # bijective (gcd(c, N) = 1), action world
        c = powermod(c, 2, N)
    end

    r = Int(dual(k))                 # Fourier-sample the phase register;
                                     # y is traced silently at exit (§3.9) —
                                     # that trace is WHY order finding works
    return denominator(rationalize(r / 4^W; tol = 1 / (2N^2)))
end
```

---

## 8. The v0.1 defect ledger (evidence base → named v2 regression tests)

*(Reframed post-reboot, review r6/M6: main was gutted in round 4, so
"fix on main" is moot — the file:line references below resolve on
branch `v0.1-deprecated`. The ledger's job now is (a) evidence for the
v2 design decisions and (b) a list of **named regression tests v2 must
ship**: 8.1 → the §3.5 runtime guardrail test; 8.2 → gone with the
surface; 8.3 → §3.4's exact-X law test; 8.4 → DSL-level aliasing with
register identity, incl. through views; 8.5 → the single-sourced
consumed set + wire-handle tests (D2); 8.6 → typed-register library
APIs from day one; 8.7 → kernel `ctrl` is total, no control-count cap;
8.8 → §7.1's Choi test on a Z-sensitive probe.)* Each verified defect,
as found on v0.1:

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
  Future note (r6): if a compact *multi-qubit named-state* literal is
  ever wanted, the precedented route is a string macro
  (QuantumClifford.jl's `S"XXX ZZI"`) — discrete vocabularies suit
  string macros; the continuous (p, φ) chart does not. Recorded so the
  next research round doesn't reopen it.
  Required tests: at the north pole the chart degenerates — `QBool(1, φ)`
  and `QBool(1, φ′)` prepare the same one-wire state for every φ, φ′ (all
  are `|1⟩` up to an unobservable global phase). The test therefore compares
  the **prepared density matrices** (or preparation-channel Chois):
  `ρ(QBool(1, φ)) ≈ ρ(QBool(1, φ′)) ≈ ρ(QBool(true))`, while asserting the
  **handles are distinct** — each call allocates a fresh register, so `==`
  on the handles is identity, never state (comparing handles by current
  state would need context inspection and fail under entanglement). A fact
  about literals, made once;
  dispatch check `QBool(true)` hits the `Bool` method
  (`Bool <: Integer <: Real`, more-specific wins); `Float64(φ)` before
  the ccall boundary for `Irrational` args.
- **D2 — `dual` and sub-registers: a semantic fork, not "IR care".**
  `dual(x)` for `x::QInt{W}` is Fourier on ℤ_{2^W}; the per-wire duals are
  Fourier on (ℤ₂)^W — different groups on the same wires, provably
  different unitaries (the QFT is not a tensor product across any
  register cut — its core carries small but nonzero cross-cut
  entanglement: Chen–Stoudenmire–White, arXiv:2210.08468, Thm 1/Cor 1;
  the *maximality* of the standard QFT's operator entanglement is a
  bit-reversal artifact and is due to Tyson quant-ph/0306144 / Nielsen
  et al. quant-ph/0208077, per the review-r6 citation ruling; Qwerty
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
  - **Additions from review r6:** (i) *partial consumption is a loud
    error* — after `Bool(dual(x[3]))` consumes wire 3, `Int(x)` errors
    ("register partially consumed: wire 3 of x is dead; measure the
    remaining wires explicitly"); a set-intersection check on the
    single-sourced consumed set, never a silent reinterpretation of
    `Int`. (ii) *Wrapper identity is not view identity* — bookkeeping
    keys on (parent wire, transform); the aliasing hook is Sturm-owned,
    shaped like Base's `dataids`/`mightalias` (documented but
    non-public — do not call Base's internals). (iii) The worked
    counter-example for the two-groups theorem is §7.5 (BV), a required
    test.
- **D3 — dynamic lifting: RESOLVED (2026-07-10, review r6).** Ruling in
  §3.6: `ClassicalBit`/`ClassicalInt` tokens under `TracingContext`
  (Proto-Quipper's *parameter* vs *state*); `if token` errors
  descriptively toward `cases`; and the 2^W scale question is answered
  by **blessing measure → traced classical computation →
  classically-parameterized circuit as ordinary code** — `cases` is for
  branching, never for outcome tables. Shipped precedent: qrisp's Jasp
  (dynamic tracer + `control()`, width-scalable traced classical
  feedback, no 2^W table); type-theoretic backing: Proto-Quipper-Dyn.
  (v0.1's hardcoded-`false` `ClassicalRef` remains unacceptable.)
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
  deliberately deferred); Draper is `add!(x, a)` with the O(L) angle
  emission moving into the kernel lowering (correction from review
  r6/B2: the *view* op-assign is modulation, §3.3), and the coset layer
  inherits the same one-liner. Library-internal escapes concentrate exactly where §5 now
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
- **D8 — migration & deprecation: RESOLVED BY THE REBOOT (round 4).**
  There is no in-place migration: v0.1 lives whole on
  `v0.1-deprecated`, main rebuilt from zero, reimport only through the
  v2 gates (CLAUDE.md reimport policy). Deprecation warnings, rewrite
  order, and test-suite migration are all moot.
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
- **D10 — region spelling & strict mode: RESOLVED (2026-07-10, review
  r6).** Rulings folded into §3.9: the manual form is
  **`region() do … end`** (Base's bare-noun do-block resource idiom;
  "scope" rejected — doubly claimed by Julia's lexical scope and
  `Base.ScopedValues`); eager helpers inheriting the enclosing region
  is *provably harmless* (trace timing is denotationally invisible —
  no backaction); and the debug/strict mode is the **lost-binding
  detector** — at region exit, flag a traced register that is an
  entangling-op parent of a surviving register, as a *classical* error
  (one mechanism catches the `x += a` rebind trap, the generic-f fold
  trap, and lost handles). `@context` propagation itself moves to
  `Base.ScopedValues` (inherits into spawned tasks; `try`/`finally`
  exit; Julia ≥ 1.11).
- **D11 — spelling of view mutation: RESOLVED (2026-07-10, review r6).**
  Julia's op-assign needs an assignable location; call-LHS forms are
  unwritable (and `dual(x) = y` is a local-method-definition trap).
  Ruling in §3.3: **bind the view, then op-assign the binding**
  (`x̂ = dual(x); x̂ += a`) — translation-family operators on bound
  views mutate the register in place and return the same view (the
  §3.4 registration, extended); **views are addressing modes, not
  numbers** (no ring ops; views don't ride P9). Runner-up recorded for
  history: `q[dual]` selector-indexing (Colon-style token; same
  `setindex!` machinery as D2) — rejected because `[]` would then mean
  both part-selection and chart-reinterpretation on one type, and
  Julia spells reinterpretation as a function (`transpose(A)`, not
  `A[transpose]`).
- **D12 — the arithmetic registry: RESOLVED (2026-07-10, review r6).**
  Ruling in §3.4: the **two-world registry** — value world (ring ops
  allocate fresh outputs; P9 generic code, scoped to arithmetic/
  comparison) vs action world (the bijective G-translation/
  Ĝ-modulation family + `⊻` + bound-view ops, registered in-place with
  the julialang #249/#3217 risk acknowledged). `x += a` on a bare
  register is legal but is the lost-binding pattern (D10 strict mode
  flags it). Construct 3 is the action family; `not!` is its ℤ₂ case.
- **D13 — `when` operational semantics: RESOLVED (2026-07-10, review
  r6).** Ruling in §3.5: streaming execution licensed by the `ctrl`
  homomorphism law (Eager: runtime guardrails — cast-under-control is
  a loud error, aliasing sees through views, clean-ancilla asserted at
  |1⟩-norm 0; Tracing: materialize `UnitaryDAG` + witness, enabling
  reassociation and fusion). Required law test: streaming ≡
  materialized at the Choi level.
- **D14 — the BennettVM contract. RESOLVED (2026-07-10, Tobias):
  ruling (A), circuit-only bridge.** The ONLY artifact that crosses the
  Bennett→Sturm boundary is a reversible circuit convertible losslessly
  to a kernel `Perm` (Bennett's NOT/CNOT/Toffoli are the 0/1/2-control
  cases of `MCX`; see `docs/design/bennett-v2-compat-audit.md`). Sturm
  owns replay (the M2 `Perm` path). BennettVM is out of scope: a
  function whose compilation requires the VM (unbounded loops, dynamic
  memory) makes `oracle(f, x)` a LOUD error naming the limitation —
  never a silent fallback. The control-aware strategy rule (§3.4) is
  enforced by the type boundary itself: Bennett has no measurement
  gate, a `Perm` is unitary by construction, so an MBU artifact cannot
  cross; if Bennett ever grows MBU it must return a DISTINCT type, not
  a `ReversibleCircuit`. Revisit as a new decision point if BennettVM
  matures into a backend candidate (option C of the audit).
- **D15 — arbitrary `QBool(p, φ)` literals inside `when` (OPEN).**
  Guardrail 1 (§3.5) bans measurement casts and permits only canonical
  fresh-|0⟩ allocation (`QBool(false)`) as controlled scratch — that case
  is closed by the compute–uncompute lemma. A general literal `QBool(p, φ)`
  with p ∉ {0} or φ ≠ 0 is a preparation channel/isometry with **no
  canonical controlled implementation**: distinct unitary extensions of the
  preparation differ by a global phase that becomes observable under outer
  `ctrl` — the same phase-ambiguity §1 and D6/F9 turn on. Until ruled, such
  a literal inside `when` is a **loud error** naming this decision, never a
  silent lowering (fail-loud, CLAUDE.md §1). Candidate resolutions, none yet
  chosen: (a) forbid them outright; (b) admit them only as part of a
  certified compute/uncompute unitary block whose ancilla the §3.9 witness
  cleans; (c) pin one phase convention and *prove* it control-stable. This
  is a genuine open point — do not invent the ruling (raised by the GPT-5.6
  review, F12).
- **Citations TODO (rule 4; audited twice — r6 corrections baked in).**
  Before implementation, `docs/physics/` distillations for:
  Bădescu–Panangaden 1511.01567 (Conditions I/III ↔ guardrails 2/1 —
  the mapping is verified; the conditions are invoked across the paper,
  so soften any "§1" locator); Gavorová et al. 2011.10031 (the
  obstruction is their homogeneous-function **Lemma 1**, an elementary
  winding argument — Borsuk–Ulam is even-d intuition only; mark the
  U(d)→PU(d) "section" phrasing as our gloss); Araújo et al. 1309.7976
  (the single-query no-go AND the 1⊕U possibility — the kernel
  argument); Yuan–Villanyi–Carbin 2304.15000 (OOPSLA1 2024: Thm 4.4,
  Def 4.7, Thms 4.8/4.9 — numbering verified against the published
  version); Ying–Yu–Feng 1402.5172 (cite ONLY for guard-externality,
  Def 2.1(4)); Fu–Kishida–Ross–Selinger 2204.13041 (dynamic lifting;
  the parameter/state vocabulary §3.6 uses); qrisp/Jasp docs (the
  shipped D3 precedent); Hietala et al. 1912.02250 (VOQC §3.3 —
  verbatim quote verified); Raussendorf–Browne–Briegel
  quant-ph/0301052 (the H-wire identity — NOT Zhou–Leung–Chuang);
  Zhou–Leung–Chuang quant-ph/0002039 + Gottesman–Chuang
  quant-ph/9908010 (gate teleportation / correction ladder — the
  injection circuit is theirs) + Bravyi–Kitaev quant-ph/0403025 (whose
  headline is *distillation*; cite the ensemble with roles straight);
  Qwerty 2404.12603 **+ ASDF 2501.13262** (nearest prior art for
  `dual`; `>>` is synthesized — never claim they "considered and
  rejected" the view reading, they simply don't discuss it; the
  canonicity-buys-the-view point is ours); Chen–Stoudenmire–White
  2210.08468 (**corrected use — the paper shows the QFT's core
  operator entanglement is SMALL** (bit-reversal artifact aside); cite
  it for "not a tensor product across any cut", or cite the early
  results (Tyson 2003; Nielsen et al. 2003) if a maximality claim is
  ever needed; the small-entanglement reading is *good* news for
  QFT-based lowerings); Gross quant-ph/0602001 + Appleby
  quant-ph/0412001 (odd/even d — D6); Tang–Wright 2508.00055 (control
  exposes global phase — §4.2); **"Control as a Constructor"
  2508.21756** (categorical prior art for the §4.2 choke point; Sturm
  = the implementation instantiation); Silq (PLDI 2020) + Qurts
  2411.10835 (the auto-uncompute pole §3.9 argues against) + Guppy
  2510.13082 (consuming-measurement neighbor; must-be-consumed pole);
  Wharton–Koch 1411.4999 (textbook quaternion↔SU(2) — the §4.1 IR
  claim is "novel as an IR choice", not "novel representation"); cf.
  Stuelpnagel 1964 (SO(3); the SU(2) extension is standard). Q#'s
  `within…apply` is the named precedent for §4.2's `within`.

---

## 10. What survives from v0.1 (migration sketch)

**Survives unchanged:** contexts + Orkan FFI; `Channel` DAG + passes +
measurement-barrier discipline (the DAG *gains* a unitarity witness and
becomes a kernel process value); Bennett bridge; casts (minus the
non-consuming debate — v2 confirms consuming); `cases`; promotion; QECC;
`ptrace!`; the entire test-discipline and physics-citation regime.

**Rewritten:** `qbool.jl` surface (BlochProxy deleted); `gates.jl`
(constants move to kernel); `patterns.jl` / `arithmetic.jl` (shrink onto
the translation family + views + kernel `ctrl` — the D5 port sketches
the exact shrinkage per function); `when` (new lowering, D13);
QSVT/block-encoding API (typed registers, bead `jlaw`, plus kernel
`adjoint` replacing hand-written `oracle_adj!` pairs);
`test_teleportation.jl` (protocol is wrong on v0.1, §8.8 — v2 ships the
Choi-level test from day one).

**Deleted concepts:** Bloch-angle mutation; the SU(2)-only doctrine and its
`H!² = −I` teaching; `_cz!` and controlled-Pauli folklore; the `not!`
*exception* (the function stays; its specialness dissolves).
