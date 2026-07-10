# Quantum Alternation: Prospects and Problems

Source: Costin Bădescu and Prakash Panangaden, "Quantum Alternation:
Prospects and Problems". In: *Proceedings 12th International Workshop on
Quantum Physics and Logic* (QPL 2015), eds. C. Heunen, P. Selinger, J.
Vicary. **EPTCS 195** (2015), pp. **33–42**. doi:10.4204/EPTCS.195.3.
arXiv:1511.01567 [quant-ph]. PDF in
`docs/physics/badescu_panangaden_1511.01567.pdf`.

This is the paper PRD-v2 §1.1 cites for the headline fact that **quantum
alternation (coherent `if`/`case`) has no channel-level / superoperator
semantics**, and that PRD-v2 §3.5 cites for the `when` guardrails
(Conditions I and III). It is the formal spine of axiom P4 ("quantum
control is an operation on *process values*, never on channels") and of
the three-layer stratification (surface channels vs kernel process
values). The paper is deliberately negative — its own Conclusion (p.41)
calls it "a very negative, or perhaps schizophrenic, paper" — and that
negativity IS the load-bearing content for Sturm: it derives *why* the
kernel must hold definite unitary representatives.

Citations are `[n]` in the paper's own numbering: [1] Altenkirch–Grattage
(QML), [11] Selinger (QPL superoperator semantics), [13] Ying–Yu–Feng
(alternation / superposition of programs, arXiv:1402.5172), [12] Ying
(quantum recursion / second quantisation), [7] Kitaev–Shen–Vyalyi
(measuring operators), [8] Kraus (Kraus theorem), [10] Raginsky
(Radon–Nikodym for quantum operations).

---

## The framework and the three "should" conditions (§1, pp. 34–35)

States are density operators on a finite-dimensional Hilbert space; a
quantum operation is a **superoperator** T : S(ℋ) → S(ℋ) (CP,
trace-nonincreasing). `qbit = ℂ²`; classical projections Π₀ = |0⟩⟨0|,
Π₁ = |1⟩⟨1|. Alternation of two superoperators T₀,T₁ with respect to a
qubit q "should" be a superoperator Altq(T₀,T₁) : S(qbit⊗ℋ) → S(qbit⊗ℋ)
satisfying three posited conditions (all STATED in §1, the Introduction,
pp. 34–35 — themes recur later, so treat "§1" as the statement locus, not
the only locus):

- **Condition I (typing / guard-externality, p. 34).** The typing
  judgement for `⟨q:qbit,Γ⟩ if q then P else Q ⟨q:qbit,Γ'⟩` requires the
  branches P, Q to be typed in a context that **cannot access the guard
  qubit q**. Rationale given (p. 34): (a) alternation of reversible
  branches is reversible only if the branches cannot touch q; (b) q is a
  consumed resource superposing the branches. Note the contrast with
  measurement: quantum branching does *not* extract classical
  information from q, so q does **not** collapse to a classical state.
- **Condition II (classical reduction, p. 34).** If q is in a classical
  state Πᵢ (i∈{0,1}), then Altq(T₀,T₁) = I ⊗ Tᵢ — coherent alternation
  degenerates to ordinary local operation on the classical branch. As a
  linear map on qbit⊗ℋ this forces the block action
  ρ = [[A,B],[C,D]] ↦ [[T₀A, *],[*, T₁D]] (the off-diagonal `*` blocks
  undetermined by the diagonal, p. 35).
- **Condition III (reversibility, p. 35).** If T₀ and T₁ are reversible
  (T(ρ)=UρU†), then Altq(T₀,T₁) is reversible. Motivation (p. 35): if
  the off-diagonal `*` blocks were left null, Alt could be implemented by
  "measurement followed by merging"; Condition III is precisely what
  rules out a measurement-based implementation and pins the "quantum"
  (coherent) character of the branch.

**Closed-system definition that meets all three (Eq. 1, p. 35).** For
unitaries U₀,U₁ and guard q,
```
Altq(U₀, U₁) = Π₀ ⊗ U₀ + Π₁ ⊗ U₁                         (Eq. 1)
```
generalising to the multi-qubit `case` over ℓ+1 = 2ⁿ classical branches
(Eq. 2, p. 35):
```
Altq̄(U₀,…,U_ℓ) = Σ_{k=0}^{ℓ} Π_k ⊗ U_k                    (Eq. 2)
```
Eq. 2 is noted to be a special case of a **measuring operator** ([7],
Kitaev–Shen–Vyalyi); the Πₖ may be replaced by projections onto pairwise
orthogonal subspaces (p. 35). **Key:** these definitions are well-defined
because they are stated on **specific chosen unitary operators**, not on
their superoperator equivalence classes — "all quantum operations
considered in this section are pure operations associated with a specific
unitary operator defined within the program" (p. 35).

---

## THE NO-GO: alternation has no superoperator semantics (§2 end, p. 37)

The central negative result. It is delivered as **prose, not a numbered
theorem** (an audit fact — see verdict below). The argument (p. 37, last
paragraph of §2):

> The conditional statement `if q₀ then skip else q₁ *= e^{iθ}`
> implements a **controlled phase**. Since `skip` and `q₁ *= e^{iθ}` are
> **physically indistinguishable as quantum operations** [they denote the
> identical superoperator ρ↦ρ], it follows that quantum alternation is
> **not directly physically realizable**. … this example shows that
> **there is no structural semantics for quantum alternation which is
> based on superoperators with extensional equality.**

The mechanism, stated as a no-go: two branches equal as superoperators
(`skip ≃ e^{iθ}·`) alternate to **different** operators (identity vs
controlled-phase). So Alt cannot be a function of the superoperator
equivalence classes — the global phase that superoperators quotient away
is exactly what alternation promotes to an observable **relative** phase.

**This is the P4 no-go.** Restated in Sturm's vocabulary: quantum control
is *not* well-defined on channels (CPTP maps / superoperators); it is
well-defined only on definite unitary **representatives**.

---

## The Kraus-level counterexample — the exact phase mechanism (§3, p. 39)

The paper's positive construction is a **Kraus** semantics (category **C**:
objects = Hilbert spaces, morphisms = Kraus decompositions 𝒮, composition
by multiset product with √ℓ multiplicity-folding, Eq. 4, p. 38). Quantum
alternation of two Kraus decompositions is (p. 38):
```
𝒮 • 𝒯 = { Π₀ ⊗ E/√|𝒯| + Π₁ ⊗ F/√|𝒮| | E∈𝒮, F∈𝒯 }
```
This works at the Kraus level, but **cannot be lifted to superoperators**
(p. 39, the sentence after the semantics table):

> The semantics defined above cannot be lifted to a semantics of
> superoperators, because quantum alternation does not preserve
> extensional equality. Indeed, the Kraus decompositions {U₀}•{V₀} and
> {U₁}•{V₁} are extensionally equal **if and only if there exists a phase
> θ such that U₀ = e^{iθ}U₁ and V₀ = e^{iθ}V₁**, so {U₀}•{V₀} ≃ {U₁}•{V₁}
> may not hold even if {U₀}≃{U₁} and {V₀}≃{V₀}.

This is the **exact counterexample mechanism** the task asks for:
{Uᵢ} and {Vᵢ} being equal as superoperators means each pair differs by
*some* phase; the alternation is equal only if they differ by the *same*
phase θ *jointly*. Independent per-branch phases — invisible to the
superoperator — survive into and distinguish the controlled result.
Conclusion (p. 39): "The failure of quantum alternation to preserve
extensional equality shows that **there is no compositional superoperator
semantics which satisfies the definition of alternation** given in the
introduction."

---

## The one numbered result: non-monotonicity ⇒ recursion incompatible (§3, p. 39)

The category **Q** of superoperators (Selinger [11]) is CPO-enriched and
traced monoidal — this is what gives QPL its **recursion** semantics
(least fixed points in the Löwner ⊑ order). The only formally set-off
result in the paper:

> **Proposition** (p. 39, unnamed/unnumbered). *Quantum alternation is not
> monotone with respect to the ⊑ order.*

**Proof (p. 39), a concrete counterexample.** With 𝒮={U}, 𝒯={V},
ρ=[[A,B],[C,D]] with B≠0: then 𝒮 ⊑ 𝒮 and ∅ ⊑ 𝒯, yet
```
(𝒮•𝒯 − 𝒮•∅)(ρ) = [[0, UBV†],[VCU†, VDV†]]
```
which is **not positive** (a zero diagonal entry with a nonzero row means
the matrix is non-positive), so 𝒮•𝒯 ⋢ 𝒮•∅. Monotonicity fails. ∎

**Consequence (pp. 40–41).** "Since a CP map T is a pure operation
ρ↦EρE† if and only if all operations completely dominated by it are
nonnegative multiples [10], it appears that the **reversibility condition
(III) makes quantum alternation fundamentally incompatible with the
standard order on CP maps**." And (p. 41): "the fact that quantum
alternation is not monotone using the Löwer order… Certainly, **combining
recursion with quantum alternation will require some radically new
idea**." (The paper leaves Ying's second-quantisation route [12] open —
so the incompatibility is with the *standard* CPO/Löwner recursion
semantics, not a claim that no recursion scheme could ever coexist.)

---

## Stinespring form — environment = tensor of environments (§3, p. 40)

The paper re-expresses alternation via **Stinespring** dilations:
T(ρ) = V†(ρ⊗I_𝒜)V, ancilla 𝒜 = environment. For 𝒮•𝒯 the Stinespring
pair is (ℰ=𝒜'⊗𝒜, W) with
```
Wψ = Σ_{E∈𝒮,F∈𝒯} Altq(Ê,F̂)† ψ ⊗ |F⟩ ⊗ |E⟩
```
"the environment of the quantum alternation is the tensor product of the
environments of the operations involved" (p. 40). Relevant to Sturm
because P1/§3.9 make **scope = the Stinespring boundary** (locals =
environment, traced at region exit): this section is the paper's own
statement that alternation's environment composes as a tensor of the
branch environments.

---

## What the paper says SURVIVES

1. **Closed-system alternation on chosen unitaries is fine** (Eqs. 1–2,
   pp. 35–36). Given *specific* unitary representatives U₀,U₁, Alt is
   well-defined, meets all three conditions, and gives the intuitive
   controlled-U / `case` construct. Examples (pp. 36–37): controlled-U as
   `if q₀ then skip else q₁*=U`, Toffoli as two nested `if`s, QFT with
   controlled-phase `Rₖ`, Deutsch (`if`) and Deutsch–Jozsa (`case`).
2. **A Kraus semantics exists** (§3) — it just does not descend to
   superoperators and does not support recursion under the standard order.
3. The failure is specifically at the **extensional/superoperator** level
   and at the **recursion** level; the paper suggests physical readings
   (Mach–Zehnder interferometers, p. 41) and a canonical
   Radon–Nikodym-based decomposition ([2,3,10], p. 41) as open directions.

---

## Relevance to Sturm v2 (P4, §1.1, §3.5) — and citation audit

### The claims Sturm attaches to this paper

**§1.1 (P1 vs P4 tension), lines 52–56.**
- "Quantum alternation has no channel-level semantics." — **SUPPORTED**
  (§2 p.37; §3 p.39). Precise wording: no *compositional superoperator*
  semantics *with extensional equality*.
- "`if q then skip else phase(θ)` is a controlled-phase, yet `skip` and
  `phase(θ)` denote the same channel." — **SUPPORTED**, essentially
  verbatim from p.37 (paper's guard is q₀, phase acts on q₁; identical
  content).
- "Alternation is also non-monotone in the CP order, so coherent control
  and unbounded recursion can never mix." — **SUPPORTED** by the
  Proposition (p.39) + pp.40–41. One nuance for honesty: the paper shows
  incompatibility with the **standard** Löwner/CPO recursion semantics and
  explicitly leaves Ying's second-quantisation route [12] open. Read
  "can never mix" as "never mix under the standard CPO recursion
  semantics." This is exactly why PRD guardrail 3 restricts to **bounded
  unrolling** rather than claiming recursion is meaningless.

**§1.1 line 86–88 and §3.5 lines 468–472 (the guardrail mapping).**
- "Bădescu–Panangaden's own §1 posits guard-externality and reversibility
  as Conditions I and III." — **SUPPORTED**: Condition I = the typing
  judgement forbidding branch access to the guard (guard-externality,
  p.34); Condition III = reversibility (p.35). Both are stated in §1
  (Introduction). PRD guardrail 2 (body must not touch the control) ↔
  Condition I; guardrail 1 (body must trace to a unitary-witnessed value)
  ↔ Condition III. The `guardrails 2/1 ↔ Conditions I/III` mapping in the
  PRD is **verified correct**.
- "the unitary-witness requirement is the Yuan–Villanyi–Carbin
  soundness/completeness pair" — not this paper (that is arXiv:2304.15000,
  distilled separately); no claim about B–P here.
- Guardrail 3 (no unbounded recursion under `when`) ↔ the
  non-monotonicity result. — **SUPPORTED** (Proposition, p.39).

**§3.4 lines 447–458 (control-aware Bennett strategy / MBU exclusion).**
The rule "measurement-based uncompute is excluded under a nonzero control
stack" is "§1.1's theorem walking — two implementations equal as channels
are distinguishable under control." — **SUPPORTED** by the exact
phase-representative counterexample (p.39): equal-as-superoperator branches
that differ by an unobservable phase become distinguishable after
alternation. The paper's own Condition-III discussion (p.35 — Alt with
null off-diagonals is "measurement followed by merging", which
reversibility forbids) is the direct antecedent of "measurement under
`ctrl` is unrepresentable."

### AUDIT VERDICT

**All Sturm claims that cite this paper are faithful to the text.** Two
locator/precision refinements (both already anticipated by the PRD's r6
self-note at lines 1534–1538, "soften any '§1' locator"):

1. **No theorem numbers exist for the main no-go.** The channel-level
   no-go ("no superoperator semantics with extensional equality") is
   PROSE — the final paragraph of §2 (p.37) and the paragraph after the
   §3 semantics table (p.39). The ONLY formally set-off, named result in
   the paper is the unnamed, unnumbered **Proposition** on p.39
   (non-monotonicity). Any Sturm text implying a numbered theorem for the
   channel no-go should cite by **page/section** (p.37 §2; p.39 §3), not
   by a theorem number. The Conditions I/II/III, by contrast, ARE cleanly
   set off and enumerated in §1 (pp.34–35), so "their §1" is a correct
   locator *for the Conditions* — the r6 softening is prudent but the
   Conditions genuinely live in §1.

2. **Two distinct counterexamples, do not conflate.** (a) The *phase-
   representative* counterexample (p.37 controlled-phase; p.39
   iff-condition U₀=e^{iθ}U₁ ∧ V₀=e^{iθ}V₁) is the argument against a
   *superoperator/channel* semantics — this is the one grounding P4. (b)
   The *CP-order* counterexample in the Proposition's proof (p.39,
   ρ with B≠0 giving a non-positive difference) is the argument against
   *recursion/monotonicity* — grounding guardrail 3. Sturm's §1.1 lists
   both ("no channel-level semantics" AND "non-monotone in the CP order");
   keep them attributed to their respective mechanisms.

### The structural takeaway for Sturm

This paper is the physics proof that Sturm's **three-layer split is
forced, not stylistic**: control cannot be an operation on the *surface*
(channels/superoperators — where global phase is quotiented and casts /
measurement live), so it must be an operation on the **kernel** (process
values — definite unitary representatives that carry the U(1) phase, per
`U2` = quaternion + phase, cf. `wharton_koch_quaternion_bloch.md`). A
kernel process value is exactly "a specific unitary operator defined
within the program" (paper, p.35) made explicit and typed. `when` lowers
to `ctrl` on a traced, unitary-witnessed process value; the guardrails are
Conditions I/III turned into loud errors; the recursion ban is the
non-monotonicity Proposition. If Sturm ever tried to let `when` control a
*channel* (a cast, a measurement, a noise map), this paper says the result
has no well-defined semantics — which is why guardrail 1 is a soundness
requirement, not a lint.
