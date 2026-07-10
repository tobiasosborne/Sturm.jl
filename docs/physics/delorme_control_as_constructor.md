# Delorme & Perdrix (2025) — Control as a Constructor

**Citation**: Delorme, N. & Perdrix, S. *Diagrammatic Reasoning with Control
as a Constructor, Applications to Quantum Circuits*. arXiv:2508.21756
[quant-ph]. Submitted 29 Aug 2025; version cited here is **v3 (14 Jan 2026)**.
Université de Lorraine, CNRS, INRIA, LORIA, Nancy, France. License CC BY 4.0.

**Local PDF**: `docs/physics/caac_2508.21756.pdf` (committed canon).

**Status in pipeline**: categorical **prior art** for the M1 kernel design in
which `ctrl` is a *constructor* on process values (PRD-v2 §4.2). This paper
grounds three specific §4.2 claims — the **homomorphism/functoriality** of
`ctrl` over `∘`, the **phase-sensitivity** of control, and the **control-scope
reassociation law** (`within(V) do … end`). It does NOT prove the
black-box no-go that motivates "control has no channel-level semantics" — it
cites that no-go (its ref [3], Araújo et al. 2014) and deliberately works
*around* it in the white-box setting, which is precisely Sturm's setting. See
"Caveats / citation audit" at the end.

Companion distillations: for the phase-quotient physics see PRD-v2 §4.1/§4.3;
for the black-box no-go proper, the Bădescu–Panangaden / Gavorová sources
cited in PRD-v2 §1 (not this paper).

---

## What this paper does (one-line)

Introduces **controlled props**: standard props (strict symmetric monoidal
categories on one generating object) equipped with a **control functor**
`C : P_endo → P_endo` that maps each object `n` to `1 + n` and each
endomorphism `f : n → n` to its controlled version `C(f) : (1+n) → (1+n)`,
subject to coherence laws (Fig 3, Eqs 13–15). As the headline application,
controllable quantum circuits are axiomatised with a **complete set of
relations acting on at most three qubits** (Theorem 2 / Fig 5), whereas any
complete axiomatisation in the *plain* prop setting provably requires
relations on arbitrarily many qubits (Theorem 1's necessity, from ref [10]).
Control-as-constructor is what buys the bounded-arity completeness.

Two headline structural facts, both load-bearing for Sturm:

1. **Control is a functor, not a monoidal functor.** `C(g ∘ f) = C(g) ∘ C(f)`
   and `C(id_n) = id_{1+n}` hold (functoriality), but
   `C(f ⊗ g) ≠ C(f) ⊗ C(g)` in general — control does *not* distribute over
   `⊗` (it acts on one extra wire). The ⊗-behaviour is fixed instead by the
   coherence laws (Eqs 13–15).
2. **Control makes global phase physical.** A controlled *global phase* gate
   is a *Z-rotation* — the framework's cleanest witness that `C` distinguishes
   `e^{iα}·id` from `id`.

---

## Definitions and coherence laws (with numbers and pages)

### Definition 1 (control functor), p. 6

> Given a prop **P**, a *control functor* is a functor
> `C : P_endo → P_endo` mapping any object `n ∈ ℕ` to the object `1 + n` and
> mapping any morphism `f : n → n` to a morphism `C(f) : (1+n) → (1+n)`,
> satisfying the coherence laws of Figure 3.

`P_endo` is the sub-prop of endomorphisms (morphisms `n → n`). Graphically,
`C(f)` is a bullet on an added control wire connected to the box `f`, enclosed
in a dotted box (functorial-box notation, ref [26] Melliès).

**Coherence laws (Fig 3, p. 7):**
- **Eq 13**: `C(f ⊗ id_1) = C(f) ⊗ id_1` — control is unaffected by an
  untouched trailing wire.
- **Eq 14**: `C(C(f)) ∘ (σ_{1,1} ⊗ id_n) = (σ_{1,1} ⊗ id_n) ∘ C(C(f))` —
  **nested controls commute** (swapping the two control wires is a symmetry).
- **Eq 15**: the symmetry `σ_{1,1}` satisfies the **conjugation law** (it is
  left-invertible by definition in a prop).

**Consequences noted just after Fig 3 (p. 7) — no separate equation number:**
> the functoriality of `C` additionally implies `C(g ∘ f) = C(g) ∘ C(f)`
> (whenever `g ∘ f` is defined), and `C(id_n) = id_{1+n}` (in particular
> `C(⌈empty⌉) = ‖wire‖`). However, `C` is not monoidal because
> `C(f ⊗ g) ≠ C(f) ⊗ C(g)` in general.

This paragraph is the **direct source** for Sturm's §4.2 homomorphism law
`ctrl(g ∘ h) == ctrl(g) ∘ ctrl(h)` and `ctrl(id) == id`.

### Definition 2 (controlled prop), p. 8
A prop equipped with a distinguished control functor `C`.

### Definition 3 (conjugated prop) + Equation 16 (the conjugation law), p. 9

> A *conjugated prop* **P** is a controlled prop such that Equation (16) is
> satisfied for any `f ∈ P(m,m)`, `g ∈ P(n,m)`, `h ∈ P(m,n)` such that
> `P ⊢ h ∘ g = id_n`:
>
> **(16)** `C(h ∘ f ∘ g) = (id_1 ⊗ h) ∘ C(f) ∘ (id_1 ⊗ g)`.

The text (p. 9): *"Equation (16) is known as the **conjugation law**. This law
is particularly important in algorithm design where the compute-uncompute
pattern `g⁻¹ ∘ f ∘ g` is often used to prepare and release ancillary bits (or
qubits) and implement oracles. This law can be used as much as possible in
some compilation processes to minimize the scope of control as explained in
[17]."* ([17] = proto-Quipper with reversing/control.)

**Eq 16 IS Sturm's §4.2 control-scope reassociation law**, verbatim up to
naming: set `g = V†`, `h = V`, `f = W` with `V` acting only on the body's
wires (so `V ∘ V† = id`, i.e. `h ∘ g = id`). Then
`(1 ⊗ V) ∘ C(W) ∘ (1 ⊗ V†) == C(V ∘ W ∘ V†)`. This is the categorical name and
proof-context for `within(V) do … end`. **CQC is proven to be a conjugated
prop** (Proposition 2, p. 13), so the law is derivable, not assumed.

### Definition 4 (points), p. 9
A control functor has *points* if there exist `false : 0 → 1` and
`true : 0 → 1` that respectively annihilate / fire the controlled operation
when plugged into the control wire. Pure-unitary props (`Qubit`) have **no
points** (all morphisms are endomorphisms) — points appear only once ancillae
(state preparation `▷` / post-selected measurement `◁`) enter (§6).

---

## The phase-sensitivity result (grounds §4.2 "distinguishes g from e^{iα}g")

The standard control functor in `FdHilb₂` is (Example 2, p. 8):

> `C_{|1⟩} : U ↦ |0⟩⟨0| ⊗ I_{2ⁿ} + |1⟩⟨1| ⊗ U`.

The paper then shows control turns an *unobservable global phase* into an
*observable relative phase*. In the interpretation of controllable quantum
circuits (Definition 8, p. 12):

> `⟦⊙_α⟧_c := e^{iα}` (the global-phase generator `⊙_α : 0 → 0`),
> `⟦C(C)⟧_c := |0⟩⟨0| ⊗ I_{2ⁿ} + |1⟩⟨1| ⊗ ⟦C⟧_c`.

Hence `⟦C(⊙_α)⟧_c = diag(1, e^{iα})` — a **Z-rotation**. Section 5 opening
(p. 12) states it plainly:

> *"a Z-rotation gate can be seen as a controlled global phase gate, and a
> CNOT gate can be seen as a controlled NOT gate."*

So `C(e^{iα}·id) ≠ C(id)`: the global phase `e^{iα}·id`, which is the identity
channel under `Ad` (physically undetectable in isolation), becomes a
*genuinely different operation* under control. This is exactly the property
PRD-v2 §4.2 demands of `ctrl` ("it distinguishes `g` from `e^{iα}g`; that is
its job"), and the mechanism behind the multi-year Cirq/Qiskit/pytket
controlled-phase bugs. (Delorme–Perdrix demonstrate the phenomenon
concretely; the *formal* "control exposes global phase" statement PRD-v2 §4.2
attributes to Tang–Wright arXiv:2508.00055 Thm 1.1 — a different paper.)

Corollary: `⊙_α` alone is not a control functor's fixpoint, and the map
`U ↦ Σ_k |k⟩⟨k| ⊗ Uᵏ` **fails to be a control functor** for `d > 2` because it
is not functorial (Example 2, p. 8) — a reminder that "controlled version" is
constrained, not free.

---

## Adjoint / dagger compatibility (grounds `adjoint(ctrl(g)) == ctrl(adjoint(g))`)

For controllable quantum circuits **CQC** equipped with the dagger functor
`(·)†` (Definition on p. 12), the control functor commutes with dagger:

> `(C(C))† = C(C†)`   (stated as part of the CQC dagger-functor definition,
> p. 12, just before Proposition 1).

**Proposition 1 (p. 12):** `CQC ⊢ C† ∘ C = id_n = C ∘ C†` for any
`C ∈ CQC(n,n)` — every quantum circuit has a derivable inverse, by induction
on generators. Together these give Sturm's §4.2 law
`adjoint(ctrl(g)) == ctrl(adjoint(g))`.

The `unitary controlled prop` abstraction (Definition 14, Appendix A, p. 22)
packages exactly this: a controlled prop of endomorphisms with a dagger
functor `(·)†` satisfying `(C(f))† = C(f†)` and `f ∘ f† = id`.

---

## The completeness payoff (why control-as-constructor is structurally superior)

- **Theorem 1 (ref [10], restated p. 11):** the plain prop **QC** is
  universally complete for `Qubit`, but (ref [10]) *every* complete relation
  set for unitary quantum circuits as a plain prop **requires at least one
  relation acting on `n` qubits for every `n ∈ ℕ`** — an unbounded family. The
  culprit is the multi-controlled Z-rotation `λⁿ(α)` (Eq 27, p. 10), whose
  vanilla-circuit realisation is exponential in `n`.
- **Theorem 2 (p. 14):** the controlled prop **CQC** is universally complete
  for `Qubit`, with a relation set `R_c` (Fig 5, Eqs 28–36) **acting on at
  most three qubits**. The added structural equations (Eqs 33–36) are all
  instances of the conjugation law.
- **Corollary 1 (p. 14):** as a *conjugated prop* **CCQC** (generators `⊙_α`,
  `H`; relations 28–32) it is universally complete — the conjugation-law
  instances (33–36) come for free.

Mechanism, stated in the concluding remark to §5 (p. 14):

> *"the context rule saying that if we have `CQC ⊢ C₁ = C₂` then
> `CQC ⊢ C(C₁) = C(C₂)` comes at free cost by definition of the control as a
> constructor. In some sense, the controlled prop formalism extracts the
> structural equations that are specific to control."*

This is the categorical statement of Sturm's design thesis: making `ctrl` a
constructor (not a per-gate operation) means an equation proved on `f`
*automatically* holds on `C(f)` — one choke point, no per-site re-derivation.
Any controllable circuit reduces to gates controlled by **≤ 2 qubits**
(Eqs 37–39, Lemma 2 p. 25), matching Sturm's Toffoli-grade `ctrl(ctrl(·))`
closure.

---

## §7 Polycontrolled props (grounds multi-basis control / CZ idioms)

Props may carry *several* control functors (`polycontrolled props`, §7). Key
properties (p. 18) that Sturm may reach for when reasoning about
control-in-a-different-basis:

- **Definition 11 (compatibility), Eq 44:**
  `C₁(C₂(f)) ∘ (σ_{1,1} ⊗ id_n) = (σ_{1,1} ⊗ id_n) ∘ C₂(C₁(f))`.
- **Definition 12 (commutativity), Eq 45:** `C₂(g) ∘ C₁(f) = C₁(f) ∘ C₂(g)`.
- **Definition 13 (exhaustivity), Eq 46:**
  `C_ℓ(f) ∘ … ∘ C₁(f) = id_1 ⊗ f` — a family of controls that together fire `f`
  exactly once (Example 8: `(C_{|k⟩})_{0≤k<d}` in `FdHilb_d`).

A single control functor already suffices for a rich structure: p. 8 notes
*"other control functors can be obtained by conjugating the control wire with
some invertible morphism … one can recover the various examples described in
Example 2 by conjugating the control qubit with NOT or Hadamard gates."*
Thus `C_{|0⟩}`, `C_{|+⟩}`, `C_{|−⟩}` (Example 2, p. 8) are `C_{|1⟩}` with a
basis change on the control wire — the categorical backbone of Sturm's
"control in a different basis = conjugate the wire" idea (e.g. the CZ /
`Bool(dual(q))` family). Sturm's kernel `ctrl` is the single `C_{|1⟩}`; other
bases are derived, not primitive.

---

## Relevance to Sturm v2

M1 kernel design (PRD-v2 §4.2) treats `ctrl` as a **constructor on process
values** (`U2`, `Perm`, `UnitaryDAG`), never an operation on channels. This
paper is the categorical prior art that legitimises that stance and supplies
proofs for three of the §4.2 laws:

1. **`ctrl(g ∘ h) == ctrl(g) ∘ ctrl(h)` and `ctrl(id) == id`** — functoriality
   of the control functor `C` (Definition 1 + the p. 7 consequence). Sturm's
   `ctrl` is `C`; the homomorphism law is `C`'s functoriality, and the
   streaming license in §3.9/D13 ("apply `ctrl(op)` op-by-op as the body
   executes") is exactly `C(g ∘ f) = C(g) ∘ C(f)` read left-to-right.

2. **`adjoint(ctrl(g)) == ctrl(adjoint(g))`** — the CQC dagger-functor law
   `(C(C))† = C(C†)` (p. 12) plus Proposition 1.

3. **Control-scope reassociation `(1 ⊗ V) ∘ ctrl(W) ∘ (1 ⊗ V†) == ctrl(V ∘ W ∘
   V†)`** — the **conjugation law** (Definition 3, Eq 16), with **CQC proven a
   conjugated prop** (Proposition 2). This is the categorical foundation and
   name-precedent for Sturm's `within(V) do … end` combinator and the
   control-scope-narrowing kernel pass. The paper explicitly frames this law
   as a *compilation* device for minimising control scope (p. 9) — precisely
   Sturm's use.

4. **Phase sensitivity** — `C(⊙_α)` is a Z-rotation (§5, Definition 8): control
   turns an unobservable global phase into an observable operation. This
   grounds §4.2's "`ctrl` distinguishes `g` from `e^{iα}g`" and the
   phase-fixed-representative discipline (U2 = quaternion + phase, §4.1) that
   feeds `ctrl`.

5. **The single-choke-point thesis** — the paper's "context rule … comes at
   free cost by definition of the control as a constructor" (p. 14) is the
   categorical statement of PRD-v2 §4.2's "`ctrl` is the only constructor of
   controlled lowerings in the entire system." An equation proved on `f`
   descends to `C(f)` for free; Cirq/Qiskit/pytket's many per-gate
   `.control()` entry points are the anti-pattern the constructor eliminates.
   **Sturm's distinct contribution is the implementation instantiation** —
   one total code path on phase-carrying process values reaching Orkan — where
   this paper provides the equational theory.

6. **Bounded-arity completeness (Theorems 1 & 2)** is the deeper "why": making
   control a constructor is not mere convenience — it *provably* circumvents
   the unbounded-arity relations that plain-prop circuit theories require. This
   is the structural sense in which control-as-constructor "is the structural
   invariant that Cirq/Qiskit/pytket lacked" (CLAUDE.md phase discipline).

**Setting match — this is why the citation is honest.** The paper works in a
**white-box** setting: the implementation of the unitary as a circuit is
*known* (Conclusion, p. 19). Sturm's `ctrl` acts on **process values** =
definite representatives = known circuits. Same setting. The black-box no-go
(Araújo et al. 2014, "quantum circuits cannot control unknown operations",
this paper's ref [3]; and Zhou et al., ref [35]) governs *unknown* unitaries
and does **not** apply here — the paper says so explicitly (p. 19). Sturm's
process values are never unknown, so `ctrl`-as-constructor is on firm ground.

**What NOT to import.** The paper is a diagrammatic/equational completeness
result, not a numerics or lowering recipe. Its `H + ⊙_α` generating set and
Euler-angle formulas (Fig 4, β₀–β₃ table, p. 11) are for *rewriting*, not for
Sturm's Orkan lowering (which uses ZYZ per §4.3). Import the *laws and their
proofs*, not the gate set.

---

## Caveats / citation audit

- **PRD-v2 §4.2 cites this paper correctly.** It calls it "categorical prior
  art … which supports rather than competes," with Sturm's contribution being
  "the implementation instantiation." That framing is accurate: the paper
  proves the *equational* structure (functoriality, conjugation law,
  ≤3-qubit completeness); it does not claim a single-implementation-path
  engineering result. No inverted or over-claimed citation found.

- **The paper does NOT establish the no-go** that motivates "quantum control
  has no channel-level semantics" (PRD-v2 §1). It *cites* the black-box no-go
  (ref [3] Araújo/Feix/Costa/Brukner 2014; ref [35] Zhou et al. 2011) and
  deliberately works *around* it in the white-box setting. Do not cite
  Delorme–Perdrix for the no-go itself — cite Bădescu–Panangaden
  (arXiv:1511.01567) / Araújo et al. (arXiv:1309.7976) / Gavorová et al.
  (arXiv:2011.10031) as PRD-v2 §1 already does. Delorme–Perdrix is prior art
  for control *being a valid, complete constructor in the white-box setting*,
  which is the complementary positive statement.

- **The "control exposes global phase" formal theorem** PRD-v2 §4.2 attributes
  to Tang–Wright (arXiv:2508.00055 Thm 1.1) is a *different* source.
  Delorme–Perdrix *demonstrate* the phenomenon concretely (`C(⊙_α)` = Z-rot)
  but do not phrase it as the Tang–Wright theorem; keep the two citations
  distinct.

- **Functoriality is over `∘` only.** `C(f ⊗ g) ≠ C(f) ⊗ C(g)` (p. 3, p. 7).
  Any Sturm code assuming `ctrl` distributes over `⊗` would be wrong; the
  ⊗-interaction is governed by the coherence laws (Eqs 13–15), and the
  expected parallel behaviour is *derived* from them (derivation on p. 7),
  not a monoidal-functor freebie.
