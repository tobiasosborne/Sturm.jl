# The Necessary and Sufficient Conditions for Quantum Control Flow

Source: Charles Yuan, Agnes Villanyi, and Michael Carbin, "Quantum
Control Machine: The Limits of Control Flow in Quantum Programming."
*Proc. ACM Program. Lang.* **8**, OOPSLA1, Article 94 (April 2024).
DOI: 10.1145/3649811. arXiv:2304.15000v5 [quant-ph], submitted 28 Apr
2023, last revised 26 Mar 2024. **Venue is OOPSLA 2024, PACMPL Vol. 8
No. OOPSLA1** — NOT POPL, NOT PLDI; this is the venue the session-92
audit corrected. PDF in
`docs/physics/yuan_villanyi_carbin_2304.15000.pdf` (35 pp., verified via
`pdfinfo`: Title "Quantum Control Machine", Creator "LaTeX with acmart
2024/02/04 v2.03" — the genuine ACM-typeset PDF, not a scraped mirror).

This is the citation PRD-v2 §1.1 and §3.5 attach to `when`'s
soundness/completeness guardrails, and PRD-v2 §9's Citations TODO names
it explicitly: "Yuan–Villanyi–Carbin 2304.15000 (OOPSLA1 2024: Thm 4.4,
Def 4.7, Thms 4.8/4.9 — numbering verified against the published
version)." That numbering is confirmed correct below (§4, pp. 15–17).

---

## What problem the paper solves

Quantum algorithms need control flow that depends on data *held in
superposition* (e.g. the phase-estimation-driven branch inside Shor's
period-finding, or Grover's diffusion). Classical control flow is built
on a program counter (`pc`) that a conditional jump updates by reading
data and choosing a new `pc` value. The paper's core observation:
**naively lifting the conditional jump — or any non-injective
transition semantics, including β-reduction, i.e. the λ-calculus — to
superposition is not merely hard, it is impossible**, because such a
lift cannot be realized as a unitary operator. This is proved as a
genuine no-go theorem (Thm 4.4, "No-Embedding"), formalizing an informal
1999/2004 conjecture of van Tonder that a "quantum λ-calculus" admitting
superpositions of λ-terms cannot exist, since β-reduction identifies
distinct terms (`λx.x` and `(λx.x)(λx.x)` both reduce to `λx.x`) and is
therefore non-injective (p. 6, p. 15).

Having shown *what fails*, §4.2 supplies the positive result Sturm
cites: the **necessary and sufficient conditions** under which control
flow *is* correctly realizable in superposition.

## The formal setup (transition systems, p. 15)

A **transition system** `(S, T)` is a set of computation states `S`
plus a partial transition function `T : S ⇀ S` (Turing machines,
register machines, and the λ-calculus are all instances; T is
β-reduction for the latter). Lifted to quantum data, `T` acts as a
linear map **T** on the Hilbert space `H_S` spanned by `{|s⟩ | s ∈ S}`.
`T` is **physically realizable** as a genuine quantum operation only if
**T** is unitary over `H_S` — and **T** is unitary over `H_S` exactly
when `T` is injective (p. 15). Definitions 4.2/4.3 (**Classical
Embedding**, **Quantum Embedding**, p. 15) formalize the fallback for
non-injective `T`: embed into an auxiliary Hilbert space `H_L` with a
*fixed* ancilla state `|η₀⟩` (fixed — no cheating by presetting `|η₀⟩`
to the expected output) such that `U(|ψ⟩⊗|η₀⟩) = |ψ'⟩⊗|η'⟩` is
**separable** for every valid transition `T|ψ⟩ = |ψ'⟩`.

## THE TWO CONDITIONS (verbatim)

The project's session-92 audit is correct: the paper gives **two**
conditions, not three. Quoted verbatim from the paper's own
Contributions list, §1.5, p. 6:

> "(Section 4.2) We define the necessary and sufficient conditions for
> control flow in superposition to be correctly realizable as part of a
> quantum program. **First, each programming abstraction must have
> injective state transition semantics. Second, a program must not
> entangle the states of data and control flow in its final output, a
> condition we term synchronization.**"

And restated at the end of §4.2 (p. 17):

> "Together, injectivity and synchronization provide a complete
> specification for the forms of control flow in superposition that are
> correctly realizable on a quantum computer — the programming
> abstractions must have injective semantics, and the program must be
> synchronized."

### Condition 1 — Injectivity, established via Theorem 4.4 (No-Embedding, p. 15)

> "**Theorem 4.4 (No-Embedding).** If the state transition function `T`
> is not injective, then no quantum embedding exists for the transition
> system `(S, T)`."

Proof sketch (p. 15–16): take `s₁ ≠ s₂` with `T(s₁) = T(s₂) = s'`
(injectivity failure), form `|ψ⟩ = (1/√2)(|s₁⟩ − |s₂⟩)`; by linearity
`T|ψ⟩ = 0`. Any purported quantum embedding `U` would then have to send
`|ψ⟩⊗|η₀⟩ ↦ 0`, contradicting unitarity (unitary operators preserve
norm, and `|ψ⟩⊗|η₀⟩` has norm 1). So *no* auxiliary-space trick, however
large, can rescue a non-injective transition function once superposed
inputs interfere destructively — this is the formal reason a "quantum
conditional jump" or "quantum λ-calculus" cannot be built by brute-force
lifting the classical one. Note precisely what Thm 4.4 *is*: a necessity
result (non-injective ⟹ unrealizable), not itself a definition of
"injectivity" — injectivity is an ordinary set-theoretic property of `T`
used throughout §3–4; Thm 4.4 is simply the paper's most specific
citable anchor for why the surface must enforce it. §4.2 additionally
*presupposes* injectivity as a standing hypothesis when defining
synchronized systems (p. 16: "We consider transition systems in which
`T` is injective and `S = C × D`...").

### Condition 2 — Synchronization, Definition 4.7 (p. 16)

Setup: split state `S = C × D` into **control state** `C` (the part
that is discarded/not an explicit output — e.g. a program counter) and
**data state** `D` (the actual output). Definition 4.6 (**Final
State**, p. 16) fixes the notion of "the state after `t` instructions
starting from `|κ₀⟩ ⊗ |δ₀⟩`." Then:

> "**Definition 4.7 (Synchronization).** The transition system `(S, T)`
> is synchronized at initial control state `|κ₀⟩` and termination time
> `t` if there exists some final control state `|κ'⟩ ∈ H_C` such that
> for any input `|δ₀⟩ ∈ H_D`, there exists some output `|δ'⟩ ∈ H_D`
> such that the final state of the machine after executing `t`
> instructions, as defined in Definition 4.6, is `|ψ⟩ = |κ'⟩ ⊗ |δ'⟩`."

In words: no matter what data comes in, the control register lands on
**the same** final value `|κ'⟩` for every basis input — so the control
and data registers factor apart (are separable/disentangled) at the
end, and by linearity this extends to any superposition of inputs (p.
16: "by linearity it suffices to show that the final value of `|κ'⟩` is
fixed across all values of `|δ₀⟩` in computational basis"). This is
exactly Sturm's "clean-ancilla exit" / "control disentangled at exit"
requirement, stated at the transition-system level of abstraction.

## The soundness/completeness pair — Theorems 4.8 and 4.9 (p. 17)

These two theorems are what make injectivity + synchronization jointly
**necessary and sufficient** — this is the "soundness/completeness
pair" PRD-v2 cites:

> "**Theorem 4.8 (Soundness).** If a transition system is injective and
> synchronized, then given any input data `|δ₀⟩`, it produces a final
> state after `t` instructions in which the output data `|δ'⟩` is
> separable from the control state. Furthermore, its mapping from input
> data to output data is a unitary operator."

> "**Theorem 4.9 (Completeness).** If a transition system is not
> synchronized, then either there exists some input `|δ₀⟩` for which it
> produces a final state `|ψ⟩` after `t` instructions in which data and
> control are entangled, or its mapping from input data to output data
> is not injective and hence not unitary."

Proof of 4.8 (p. 17): linearity — decompose `|δ₀⟩ = Σᵢ γᵢ|δᵢ⟩` in the
computational basis; synchronization gives `Tᵗ(|κ₀⟩⊗|δᵢ⟩) = |κ'⟩⊗|δᵢ'⟩`
for the *same* `|κ'⟩` for every `i`; superpose and factor out `|κ'⟩` —
the induced data map `Σγᵢ|δᵢ⟩ ↦ Σγᵢ|δᵢ'⟩` is linear and norm-preserving
(since **T** is unitary), i.e. itself unitary. Proof of 4.9 (p. 17): if
not synchronized, two basis inputs `|δ_A⟩ ≠ |δ_B⟩` drive the control to
*different* final states `|κ_A⟩ ≠ |κ_B⟩`; superposing the two data
inputs and propagating gives an entangled final state
`(1/√2)(|κ_A⟩⊗|δ_A'⟩ + |κ_B⟩⊗|δ_B'⟩)` unless `|δ_A'⟩ = |δ_B'⟩` — but if
`|δ_A'⟩ = |δ_B'⟩` while `|δ_A⟩ ≠ |δ_B⟩`, the data map itself is
non-injective (two inputs collapse to one output), hence non-unitary.
So: **not-synchronized ⟹ (entangled output) ∨ (non-unitary data map)** —
the exact contrapositive making synchronization necessary for a "clean"
unitary computation over the data, on top of Thm 4.4's separate
necessity argument for injectivity.

## Relevance to Sturm v2

1. **This is the formal license for `when`'s three guardrails**
   (PRD-v2 §3.5), specifically the *unitary-witness* requirement: `when`
   traces its body to a value that must be unitary-witnessed, on pain
   of loud error. Thm 4.8 says injective + synchronized ⟹ separable
   output AND unitary data map; Thm 4.9 says failing synchronization
   forces either entanglement or non-unitarity. Sturm's guardrail 1
   ("the body must trace to a unitary-witnessed value") and its
   corollary "control disentangled at exit" are precisely what these
   two theorems certify as sufficient (4.8) and necessary (4.9, by
   contrapositive) at the transition-system level, one abstraction
   layer below Sturm's circuit-level `ctrl`.

2. **Guardrail 2** ("the body must not operate on the control
   register") is the operational shadow of the `C × D` split (p. 16):
   `when`'s control wire *is* the paper's `C`, the body's wires are `D`;
   letting the body touch `C` breaks the clean `C × D` factoring the
   whole synchronization argument depends on.

3. **Injectivity (Thm 4.4) is why casts are banned inside `when`.** A
   measurement collapse or `ptrace!` is exactly a non-injective
   transition (many pre-images map to one classical outcome) — Thm 4.4
   says such a thing has NO quantum embedding, full stop, not even via a
   bigger ancilla space. This is why guardrail 1 ("any cast, `ptrace!`,
   `cases`, or noise channel inside `when` is a loud error") is not a
   convenience restriction but the direct, unavoidable consequence of
   the no-go theorem.

4. **The no-go half (Thm 4.4) is also why `ctrl` cannot be built
   generically from an arbitrary callable/channel** — reinforcing
   (independently of the Araújo/Gavorová control-of-black-box no-go
   already cited elsewhere in PRD-v2 §1.1) that coherent control must
   act on *process values with a known injective/unitary structure*,
   never on an opaque channel that might internally measure or discard.

5. **What this paper does NOT supply**: it says nothing about *how* to
   represent a process value (that's Wharton–Koch/U2), nothing about
   controlled-unitary constructibility from black-box access (that's
   Araújo et al./Gavorová et al.), and nothing about guard-externality
   for classical branches (that's Bădescu–Panangaden and Ying–Yu–Feng).
   Its sole contribution to Sturm is the abstract soundness/completeness
   criterion for *coherent* control flow — cite it only for Thm 4.4,
   Def 4.7, Thm 4.8, Thm 4.9 (and, if useful, the §1.5 Contributions
   restatement).

---

## Caveats — audit of PRD-v2's wording against the paper

Checked PRD-v2 lines ~88–90 (§1.1) and ~469–471 (§3.5), plus the §9
Citations TODO entry, against the paper text (verified via `pdftotext`
extraction of the committed PDF, cross-checked against page headers
`94:15`–`94:17`):

- **Numbering is correct.** Thm 4.4 (p. 15, No-Embedding), Def 4.7
  (p. 16, Synchronization), Thm 4.8 (p. 17, Soundness), Thm 4.9 (p. 17,
  Completeness) all match the published version exactly. The §9 note
  "numbering verified against the published version" checks out.
- **"Injectivity (Thm 4.4)" is a slightly loose label** (minor, not a
  correctness issue): Thm 4.4 does not *define* injectivity — it proves
  that *failing* injectivity forecloses any quantum embedding.
  Injectivity itself is an ordinary property of `T`, introduced in
  prose (§3, §4.1) with no dedicated definition number. PRD-v2's
  shorthand "injectivity (Thm 4.4)" is defensible as "the theorem that
  makes injectivity mandatory," but a stickler reading Thm 4.4 in
  isolation would not find "injectivity" *defined* there — only its
  necessity established. Recommend PRD-v2 phrasing (if revised) read
  "injectivity (necessity: Thm 4.4)" to preempt this reading, though the
  current text is not wrong, only slightly compressed.
- **"Jointly sound and complete... (Thms 4.8/4.9)" is accurate.** Thm
  4.8 is literally titled "Soundness" and Thm 4.9 "Completeness," and
  their statements are exactly the sufficiency/necessity pair PRD-v2
  invokes for "unitarity-with-disentangled-control." No mismatch found.
- **§3.5's "the unitary-witness requirement is exactly the
  Yuan–Villanyi–Carbin soundness/completeness pair (Thms 4.8/4.9)"** —
  accurate at the level of formal analogy (transition-system `C×D` ↔
  Sturm's control wire + body wires), though it is worth flagging
  explicitly (which PRD-v2 does not) that the paper's theorems are
  stated over abstract *transition systems* `(S, T)`, one level of
  abstraction below Sturm's circuit-level `ctrl(V)` on process values;
  the correspondence is a faithful instantiation, not a literal
  quotation, and PRD-v2's prose does not overclaim a direct citation
  of Sturm-specific vocabulary from the paper (correct — the paper
  never mentions `when`, `ctrl`, or process values).
- **Venue: confirmed OOPSLA 2024** (Proc. ACM Program. Lang. Vol. 8, No.
  OOPSLA1, Article 94, publication date April 2024; DOI
  10.1145/3649811) — matches PRD-v2's "OOPSLA1 2024" and CLAUDE.md's
  correction note. No mismatch.
- **"TWO (not three) conditions"**: confirmed. The paper's own
  Contributions list (§1.5, p. 6) and the §4.2 closing summary (p. 17)
  both explicitly say "injectivity and synchronization" — two named
  conditions. (Bădescu–Panangaden's separate Conditions I/III, cited
  alongside in PRD-v2 §3.5 for guardrails 1/2, belong to a *different*
  paper and are not part of this count — no conflation found in the
  PRD-v2 text checked.)
- **No mismatches found** beyond the minor "Thm 4.4 defines injectivity"
  compression noted above; PRD-v2's attribution of guardrail
  justification to this paper is faithful to the source.
