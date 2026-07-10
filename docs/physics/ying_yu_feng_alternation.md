# Alternation in Quantum Programming: From Superposition of Data to Superposition of Programs (QGCL)

Source: M. Ying, N. Yu, Y. Feng, "Alternation in Quantum Programming:
From Superposition of Data to Superposition of Programs", arXiv:1402.5172v1
[cs.PL], 20 Feb 2014. No journal-ref is attached on arXiv (single version,
v1, as of this distillation); cite as an arXiv preprint. PDF in
`docs/physics/ying_yu_feng_1402.5172.pdf` (61 pp.).

This is the citation PRD-v2 attaches, in exactly one place (§1.1 and the
§9 Citations-TODO list), to **guard-externality**: "Ying–Yu–Feng
(arXiv:1402.5172) supply only guard-externality (Def 2.1(4)); their
general guarded composition deliberately admits non-unitary branches" —
and the §9 TODO entry repeats the scope note verbatim: "cite ONLY for
guard-externality, Def 2.1(4)". This distillation exists to pin down what
Def 2.1(4) actually says, check it against the PRD's use, and audit
whether the "ONLY" is honest (see Caveats).

The bulk of the paper (quantum walks as the motivating paradigm, the
weakest-precondition calculus for QGCL, algebraic laws for program
verification/transformation, quantum choice, the probabilistic-choice
correspondence via local variables — §§4–8 and the Appendices) is a full
programming-language semantics for a construct Sturm does NOT adopt in
that generality. We distill only what grounds the PRD's citation: the
syntax/side-condition of Definition 2.1 clause 4, and enough of §3 (the
guarded-composition machinery) to verify the "deliberately admits
non-unitary branches" claim.

---

## QGCL syntax and Definition 2.1 (pp. 9–11)

QGCL is Ying–Yu–Feng's language, an extension of Sanders–Zuliani's qGCL
with a genuinely new construct, *quantum alternation*, alongside the
already-known *classical alternation* (branching that consumes a
measurement outcome). Both are introduced together, as clauses of one
inductive definition, so the guard-externality condition can be read
against its explicit contrast case.

**Definition 2.1** (p. 10, continuing to p. 11) inductively defines QGCL
programs `P` together with three variable sets: `var(P)` (classical),
`qvar(P)` (quantum), `cvar(P)` ("coin" — a distinguished subset of
`qvar(P)`). The five clauses:

1. `abort`, `skip` — the empty programs. (p. 10)
2. `U[q]` — a unitary transformation applied to quantum variables `q`.
   (p. 10)
3. **Classical alternation** (p. 11, Eq. 17):
   ```
   P ≡ measure (m · M[q:x] = m → P_m) end
   ```
   Measurement `M` is performed on quantum variables `q`, the outcome is
   stored in classical variable `x`, and then subprogram `P_m` runs for
   the reported outcome `m`. The only side-condition is `x ∉ ⋃_m var(P_m)`
   (an outcome-variable hygiene condition, "for technical convenience" —
   p. 12). Explicitly stated (p. 12): "it is not required that the
   measured quantum variables `q` do not occur in `P_m`" — i.e.
   classical alternation's guard system is allowed to be internal to the
   branches. This is the paper's own contrast case for clause 4, below.
4. **Quantum alternation — Definition 2.1(4)** (p. 11, Eq. 18):
   ```
   P ≡ qif [q] (i · |i⟩ → P_i) fiq
   ```
   Given: `q` a sequence of distinct quantum variables, `{|i⟩}` an
   orthonormal basis of `type(q)` (the "coin" space), `{P_i}` a family of
   programs indexed by the basis states. The side-condition, stated as
   part of the clause (p. 11):
   ```
   q ∩ ( ⋃_i qVar(P_i) ) = ∅
   ```
   i.e. the coin/guard variables `q` are disjoint from every branch
   program's quantum-variable set. Immediately after the definition
   (p. 12), the paper glosses this condition in prose: *"it is required
   that the variables in q do not appear in any P_i's. This indicates
   that the 'coin system' q is external to programs P_i's."* This
   sentence is the paper's own name for the condition — **guard-
   externality** — and it is exactly, and only, this disjointness
   requirement in clause 4 of Definition 2.1.
5. `P1; P2` — sequential composition, with a similar hygiene
   side-condition on classical variables. (p. 11)

**What Def 2.1(4) does NOT require.** It does not require the `P_i`
themselves to be unitary — they are arbitrary QGCL programs, and QGCL
programs include clause-3 classical alternation (i.e. mid-branch
measurement) and, recursively, further quantum alternation. Def 2.1(4)
is purely a *syntactic disjointness* condition on variable sets; it says
nothing about what kind of quantum operation is admissible inside a
branch.

---

## Guarded composition is defined for super-operators, not just unitaries (§3, pp. 12–18)

The paper's semantic machinery for quantum alternation is built in three
explicit stages of generality (§3, "Guarded Compositions of Quantum
Operations"):

- **§3.1, Definition 3.1 (p. 12)** — guarded composition of *unitary
  operators*: `⊔ᵢ|i⟩ → Uᵢ` acting as `|i⟩|ψ⟩ ↦ |i⟩(Uᵢ|ψ⟩)` on the coin
  ⊗ system space. Lemma 3.1(1) (p. 13): this composite is itself unitary.
  The paper notes explicitly (p. 13) this is nothing but the quantum
  multiplexor (QMUX) already known in circuit synthesis — the
  *unitary-only* special case.
- **§3.2–3.3, Definitions 3.2–3.4 (pp. 14–16)** — the general tool,
  *operator-valued functions* `F: Δ → L(H)` subject to `Σ_δ F(δ)†F(δ) ⊑
  I` (Def 3.2, p. 14; a sub-normalization/Löwner-order condition, with
  equality — "full" — for unitaries and for complete measurements).
  Example 3.2 (p. 14) states plainly that both a unitary operator AND a
  quantum measurement `{M_m}` are instances of an operator-valued
  function; Definition 3.4 (pp. 15–16) then guards a *family* of
  operator-valued functions `F_i` (not necessarily unitary) along a coin
  basis, with explicit conditional-probability-like coefficients `λ`
  (Eq. 25, p. 16) needed precisely because non-full/non-unitary branches
  can have different "weights." Example 3.3 (p. 17) instantiates this on
  two genuine quantum *measurements* in different bases — an explicit,
  worked, non-unitary guarded composition.
- **§3.4, Definition 3.5 (pp. 17–18)** — guarded composition of
  *super-operators* `E_i` (general CPTP maps, via all their Kraus
  operator-sum representations): `⊔ᵢ|i⟩ → E_i`. This is the fully
  general construct quantum alternation (Def 2.1(4)) is denoted by in the
  paper's semantics (§4, "Denotational Semantics"). Example 3.4 (p. 18)
  shows the composition of two *unitary* super-operators is itself
  generally a whole *set* of super-operators (relative-phase
  non-uniqueness) — a non-triviality that only arises because the
  framework is built to host non-unitary branches from the outset, not
  as an afterthought.

This confirms, textually, the PRD's parenthetical: quantum alternation's
governing definition (Def 2.1(4)) imposes only the coin-disjointness
condition; the semantic object it denotes (guarded composition of
super-operators, Def 3.5) is deliberately built to admit measurement and
other non-unitary branches — QGCL's classical alternation (clause 3) and
quantum alternation (clause 4) can nest inside each other's branches
freely; nothing in Def 2.1(4) or in §3's generality forbids a `P_i` that
itself measures.

---

## Relevance to Sturm v2

1. **What Sturm may cite this paper for, precisely.** The guard-
   externality condition PRD-v2 §3.5 guardrail 2 needs ("the body must
   not operate on the control register") has its literal syntactic
   ancestor in **Definition 2.1(4)**'s side-condition `q ∩ (⋃ᵢ qVar(Pᵢ))
   = ∅`, glossed by the paper itself (p. 12) as "the 'coin system' q is
   external to programs P_i's." Cite `Def 2.1(4)`, p. 11 (side-condition)
   / p. 12 (the "external" gloss), for this and nothing else.
2. **What Sturm must NOT take from this paper: unitarity of branches.**
   QGCL's quantum alternation does not require, and its semantics (Def
   3.5, guarded composition of super-operators) is explicitly engineered
   to NOT require, that branches be unitary. Sturm's `when` is strictly
   narrower: PRD-v2 §3.5 guardrail 1 (body must trace to a
   unitary-witnessed value; any cast/`ptrace!`/`cases`/noise inside
   `when` is a loud error) is a Sturm-specific soundness requirement with
   NO support from this paper — it comes from Yuan–Villanyi–Carbin's
   injectivity+synchronization soundness/completeness pair (Thms 4.8/4.9,
   arXiv:2304.15000) instead. Do not cite Ying–Yu–Feng for guardrail 1.
3. **Guard-externality alone is not sufficient for Sturm's guardrails.**
   Bădescu–Panangaden's own §1 (arXiv:1511.01567) independently posits
   guard-externality-like and reversibility conditions (their Conditions
   I and III) for a channel-level denotation to exist at all — those,
   not Ying–Yu–Feng, are what PRD-v2 §3.5 guardrails 2 and 1 are
   actually attributed to in the normative text (`§3.5`: "guardrails 1
   and 2 are Bădescu–Panangaden's own Conditions III and I"). Ying–Yu–
   Feng is cited alongside as an *independent* corroboration that the
   externality idea is not an isolated invention — a different, weaker
   role than being the source of a guardrail.
4. **The QMUX reading (Def 3.1, p. 12–13) is a useful mental model** for
   `when`'s streaming semantics (PRD-v2 §3.5 "Operational semantics"):
   a coin-basis-indexed family of unitaries composed along an orthogonal
   coin decomposition is exactly a quantum multiplexor, i.e. what
   `ctrl(V)` builds when the control register carries the coin. This is
   consistent with, but not additional licence beyond, what
   Yuan–Villanyi–Carbin and PRD-v2 §4.2's `ctrl` homomorphism already
   establish; it is offered here only as intuition, not as a citation
   Sturm should attach anywhere in code.

---

## Caveats — citation-audit verdict

**Verdict: the PRD's attribution is honest and precise.** Checked against
the actual text:

- The PRD's locator "Def 2.1(4)" is exactly right: Definition 2.1 spans
  pp. 10–11 with five numbered clauses, and clause 4 (p. 11) is quantum
  alternation with the `q ∩ ⋃ᵢ qVar(Pᵢ) = ∅` side-condition, glossed by
  the authors themselves (p. 12) in language ("the 'coin system' q is
  external to programs P_i's") that is the direct textual source of the
  term "guard-externality." No stretch, no reconstruction needed.
- The PRD's qualifier "supply only guard-externality... their general
  guarded composition deliberately admits non-unitary branches" is also
  verified: Def 2.1(4) is a bare syntactic disjointness condition with no
  unitarity requirement on the `Pᵢ`, and §3's guarded-composition
  machinery is explicitly built in three stages of increasing generality
  (unitary-only Def 3.1 → operator-valued-function Def 3.4, worked on
  measurements in Example 3.3 → super-operator Def 3.5) specifically so
  that measurement and other non-unitary branches are first-class. The
  word "deliberately" in the PRD is earned — Example 3.3 (two
  measurements guarded together) is presented as a positive illustration
  of the framework's reach, not a degenerate edge case.
- One nuance worth flagging for future citation hygiene, though it does
  not contradict the PRD: the guard-externality *gloss* ("external to
  programs") is prose commentary immediately following the definition
  (p. 12), one page after the formal side-condition itself (p. 11). A
  reader who opens only to p. 11 sees the equation, not the word
  "external"; the PRD's own locator "Def 2.1(4)" is still correct
  (that IS where the condition lives), but a maximally precise citation
  would say "Def 2.1(4), p. 11, glossed p. 12" rather than leaving the
  reader to hunt across a page break for the English sentence that
  supplies the name. This is a page-locator refinement, not a
  correction — no change to the PRD's substantive claim is needed.
- No other mismatch found: the PRD does not attribute unitarity,
  soundness, or completeness results to this paper (those citations
  correctly go to Yuan–Villanyi–Carbin and Bădescu–Panangaden elsewhere
  in §1.1/§3.5), so there is no over-claiming to correct.
