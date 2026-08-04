# Knill & Laflamme 1997 — A Theory of Quantum Error-Correcting Codes

**Source (local, gitignored):**
`docs/physics/knill_laflamme_1997_qec_conditions.pdf`. Per rule 4 the PDF is
not committed; a fresh clone re-downloads from arXiv:quant-ph/9604034.

**Version pin (read off the document itself).** Margin stamp:
**`arXiv:quant-ph/9604034v1 26 Apr 1996`**; title page: *"A Theory of
Quantum Error-Correcting Codes"*, Emanuel Knill, Raymond Laflamme, Los
Alamos, **LA-UR-96-1300**, dated April 1995. Published as **PRA 55, 900
(1997)** under the (article-less) title *"Theory of quantum error-correcting
codes"*.

⚠ **Numbering trap.** Everything below is pinned to the **arXiv v1**
numbering (sections 1–7, equations (1)–(45), Theorems 3.1–3.6 and 5.1–5.5),
which is what is on disk. The PRA print is a different typesetting with its
own numbering — do not mix pins. Page numbers are from the local 36-page
build.

⚠ **Dimension-counting trap.** KL's *"(n,k)-quantum code"* (§3.1, p. 10)
means a **k-dimensional** subspace of an **n-dimensional** Hilbert space —
dimensions, not qubit counts. Their `(2^r, 2)` is Gottesman's `[r, 1]` /
Sturm's `[[r, 1]]`. Convert before comparing any bound.

## What Sturm uses it for

Synthesis §7 item **P3** (`qecc/codes.jl`, `qecc/superchannel.jl`): the QEC
conditions, why a table decoder is *exact* on the declared correctable set,
and why `Θ(𝓝) = id_L` is the correctability *statement* rather than a
precondition.

| Sturm object (M11) | Grounded by |
|---|---|
| the QEC conditions (necessary AND sufficient) | Theorem 3.2, eqs (19)–(20), pp. 13–15 |
| the "projector form" `P Kᵢ†Kⱼ P = α_{ij} P` — exact provenance | G1 below (⚠ not a displayed KL equation) |
| `TableDecoder` exactness: recovery = syndrome projections + conditional unitaries, zero error on the declared set | proof of Thm 3.2, eqs (21)–(25), pp. 14–15 |
| `Θ(𝓝) = id_L` **is** correctability | Theorem 3.3, p. 17 |
| channel-level (Choi) verification of recovery — the M11 test discipline | Theorem 3.4, p. 17 |
| code ⊗ syndrome factorisation; syndrome as a subsystem; detectable-vs-correctable | Theorem 3.5, p. 18 |
| measurement + `@cases`-shaped recovery implementation | §4, pp. 19–21 |
| degenerate codes are allowed by the conditions | pp. 15–16 + example eqs (26)–(29) |
| why marginal/pure-state figures of merit deceive (wm28 resonance) | Theorem 5.3 + Pauli example, pp. 27–29 |
| code-capacity model is KL's own stated assumption (ruling S27) | §6, p. 32 |

## Setup and vocabulary (§2, pp. 4–9)

Noise is a **superoperator** `$` with `ρ_f = Σ_a A_a ρ_i A_a†` (eqs (2)–(3));
the `A_a = ⟨μ_a|U|e⟩` (eq (4)) are called **interaction operators** — today's
Kraus operators — with `Σ_a A_a†A_a = I` (eq (5)). Non-uniqueness under
change of environment basis is stated explicitly (p. 6): two sets differing
that way are *"physically equivalent"* (cf. Watrous Cor. 2.23/2.24 for the
modern unitary-freedom statement — `watrous_2018_channel_representations.md`).

For one encoded qubit the conditions first appear as eqs (6)–(7), p. 6:
`⟨0_L|A_a†A_b|1_L⟩ = 0` and `⟨0_L|A_a†A_b|0_L⟩ = ⟨1_L|A_a†A_b|1_L⟩`, read as
(i) corrupted logicals stay orthogonal and (ii) *"we must learn nothing about
the actual state of the code"* — the same two-halves reading Gottesman gives
his (2.8)/(2.9).

§3.1 (pp. 10–11) formalises: a code `C` is a subspace; a **recovery
(super)operator** `R` is a superoperator on the coding space; a **quantum
error-correcting code is the pair `(C, R)`**; `(C, R)` is **`A`-correcting**
iff the error `E(C, RA) = 0`, i.e. every `R_r A_a` acts on `C` as a scalar
(Theorem 3.1, p. 12 — the scalar `λ_{ra}` cannot depend on the state, by
linearity). Note the recovery-operator abstraction is introduced *precisely*
to cover implementations by *"a combination of unitary operations and
classical measurements or by unitary operations alone"* (p. 11) — the DM
and Eager execution paths of M11 are both inside its scope by design.

## Theorem 3.2 — the KL conditions (pp. 13–15)

> **Theorem 3.2** *The code `C` can be extended to an `A`-correcting code
> iff for all basis elements `|i_L⟩, |j_L⟩` (`i ≠ j`) and operators
> `A_a, A_b` in `A`*
>
>     ⟨i_L| A_a†A_b |i_L⟩ = ⟨j_L| A_a†A_b |j_L⟩        (19)
>     ⟨i_L| A_a†A_b |j_L⟩ = 0                           (20)
>
> *... we can define an `A`-correcting code as one which satisfies Eq.(19)
> and Eq.(20) for any one (and therefore every) basis of the code.* (p. 13)

The forward proof (p. 14) computes the now-standard chain ending in
`⟨i_L|A_a†A_b|j_L⟩ = α_{ab} δ_{ij}` with `α_{ab}` a basis-independent matrix
— the matrix Gottesman calls `C_{ab}` in his eq (2.10).

**The converse construction is a table decoder** (pp. 14–15). Let `V^i` be
the span of `{A_a|i_L⟩}`; by (20) these are orthogonal. Choose aligned
orthonormal bases `|ν_r^i⟩` (aligned via unitaries `U_i` with
`U_i A_a|0_L⟩ = A_a|i_L⟩`, whose existence is exactly eq (19)); then

    R_r = V_r Σ_i |ν_r^i⟩⟨ν_r^i|,   V_r|ν_r^i⟩ = |i_L⟩        (21)–(23)

plus `O`, the projection onto the unreached complement. Each `R_r` is a
**projection (syndrome measurement outcome `r`) followed by a unitary
correction**, and eqs (24)–(25) verify `R_r A_a = β⁰_{ar}·1` on `C`.
**This is why ruling S20's `TableDecoder` is exact on the declared set**:
the syndrome→correction lookup is not an approximation whose quality has to
be argued — it is the very recovery whose existence the conditions
guarantee, with error exactly 0 (`E(C, RA) = 0`, not merely small).
Everything outside the declared set is uncovered by the theorem.

**Degeneracy is allowed** (pp. 15–16): eq (19) *"does not require that the
logical states have zero inner products when two different interactions are
applied"* — two errors may map into the same subspace, *"a novel feature of
quantum error-correcting codes which does not exist in their classical
counterparts."* The explicit `{|00⟩, |11⟩}` example, eqs (26)–(29), needs
only **two** recovery operators for **three** linearly independent
interaction operators. (Same fact as Gottesman's singular-`C_{ab}`
definition of degeneracy.)

## Theorems 3.3–3.6 — the four equivalent characterizations (pp. 17–19)

These are the abstract's *"four others"*, and two of them are the exact
statements M11's design leans on:

- **Theorem 3.3** (p. 17): *"`C` is an `A`-correcting code iff the
  restriction of `A` to `C` has a left superoperator inverse."* Proof: by
  Thm 3.1, `RA` acts on `C` as `R_r A_a = λ_{ra} I`, i.e. *"`RA` is a
  superoperator equivalent to the identity (by a change of basis on the
  environment)."* **This is the source for "`Θ(𝓝) = id_L` is the
  correctability statement rather than a precondition"**: correctability of
  `𝓝` by `(C, R)` *is defined by* the composite being the identity channel
  on the logical space. `effective_logical_noise` evaluated on a correctable
  channel returning `id_L` is not a happy accident to test for — it is the
  definition of correctable, and the test is the definition read backwards.
- **Theorem 3.4** (p. 17): *"`B` has error 0 on `C` iff
  `I ⊗ B Σ_i |i_L⟩|i_L⟩ = λ Σ_i |i_L⟩|i_L⟩`"* — checking zero error **for
  all pure states** is equivalent to checking **one** state, the completely
  entangled one. This is the completely-entangled-state (Choi-state)
  characterization, and it is the primary-source license for M11's test
  discipline: compare `Choi(D∘R∘𝓝∘E)` against `Choi(id_L)` — a single
  channel-level identity — rather than sampling logical inputs. (The
  equality is between *ensembles*: both sides must induce the same density
  matrix.)
- **Theorem 3.5** (p. 18): `C` is `A`-correcting iff there is an isomorphism
  `σ : H ≅ (C ⊗ E) ⊕ D` with `A_a|Ψ⟩ = σ(|Ψ⟩ ⊗ |E(a)⟩)`, the vector
  `|E(a)⟩ ∈ E` depending on `A_a` alone. *"The final state in `E` is called
  the **error syndrome**."* `D` is the summand *"normally never reached"*,
  usable *"for error detection if so desired"* — the explicit
  correctable-vs-detectable split. A **perfect** code: `D` empty and the
  `|E(a)⟩` span `E`. This subsystem picture (error info factors into a
  syndrome tensor leg, touching the logical leg not at all) is the
  structural reason syndrome extraction can be a measurement of fresh
  ancillas without back-action on the logical state.
- **Theorem 3.6** (p. 19): the information-theoretic identity
  `S(ρ̄) − S(ρ) = log k` (Nielsen–Schumacher, their ref [24]). Not used by
  M11; listed for completeness.

## §4 — Implementing recovery (pp. 19–21): the `@cases` shape

The recovery of Thm 3.2 *"consists only of projections followed by unitary
operators conditional on the result of the projections"* (p. 19). To realise
it with standard-basis measurements: adjoin an ancilla `M`, apply
`V = Σ_r P_r ⊗ V_r` — *"a generalization of the standard controlled-not
operations in quantum computing"* (p. 20) — measure `M`, then apply the
correction `U_r` selected by the outcome. That is, structurally:
syndrome-extraction entanglers (`a ⊻= q` forms), measurement casts on the
ancillas, `@cases` on the records, Pauli corrections — the M11 acceptance
example is this paragraph written in Sturm surface syntax.

Two further remarks worth pinning: replacing measurement + conditional
correction by the coherent `Σ_r U_r ⊗ |r_M⟩⟨r_M|` transfers the
environment's information into `M`, and *"the only effective way in which
`M` can be reused for subsequent operations is to dissipate that information
by a measurement"* (p. 20) — fresh-or-measured ancillas per round are
physics, not bookkeeping. And for codes with an identity interaction
component (`C = σ(C ⊗ |a₀⟩)`), encode/decode can share one circuit `D` with
recovery = `D`, measure `E`, restore `|a₀⟩`, re-encode `D⁻¹` (p. 21) —
the decoder-is-adjoint-of-encoder rule of PRD §5 in its 1996 form.

## §5 — e-error correction, bounds, and the fidelity honesty results

- Error basis eq (31): `{I, σ_z, σ_x, σ_xσ_z}` up to sign — an operator
  *"induces (at most) `e` errors"* if it is an `r`-fold tensor product with
  all but `e` factors the identity; an **`e`-error-correcting** code
  recovers from all such (p. 23).
- **Theorem 5.1** (p. 26): a `(2^r, k)` `e`-error-correcting code must have
  `r ≥ 4e + ⌈log k⌉`. The worked case (pp. 24–26, via reduced density
  matrices, eqs (33)–(38)): **no one-error-correcting `(2⁴, 2)` code
  exists** — five qubits is minimal (their ref [15] is the five-qubit code).
  Theorem 5.2 (p. 26) is the reduced-density-matrix restatement of
  correctability used in the proof.
- **Theorem 5.3** (p. 27): pure-state fidelity `F_p = 1 − ε` only bounds the
  **entangled-state fidelity** by `F_e ≥ 1 − 3ε/2`, and the bound is sharp:
  for `A = {σ_x/√3, σ_y/√3, σ_z/√3}`, `F_p = 1/3` while **`F_e = 0`** —
  the three states `I ⊗ σ_i |e⟩` are all orthogonal to the entangled `|e⟩`
  (pp. 28–29). Their conclusion (p. 31): the gap matters *"lest one be
  deceived into believing that a fidelity of 1/3 might be adequate."*
  **This is the wm28 lesson in its 1996 primary source**: a worst-case
  *pure-state* (unentangled-probe) figure of merit can read 1/3 while the
  channel is, on entangled inputs, as wrong as possible. Entangled probes —
  Choi-level comparison — see what product probes cannot. M11's
  channel-level test discipline cites Thm 3.4 for the mechanism and this
  example for the necessity.
- **Theorem 5.5** (p. 30): for `A = {√(1−p) I, A′}` i.i.d. on `n` qubits,
  `F(C, RA^{⊗r}) ≥ 1 − Σ_{k>e} C(r,k) p^k (1−p)^{r−k}` — the classical
  binomial bound. ⚠ **Its hypothesis is `A₀ ∝ I`** (p. 29): *"When `A₀` is
  not a scalar multiple of the identity, then additional terms must be added
  to the bounds. We defer the discussion of this case to future papers."*
  Amplitude damping (`A₀ = diag(1, √(1−γ))`) fails the hypothesis — do not
  quote the binomial bound for it. M11's exact DM enumeration
  (`repetition_code_effective_noise.md`) sidesteps the bound entirely.

## §6 — the code-capacity admission (p. 32)

> *"The present work on quantum error-correction assumes that no errors are
> produced during operations. ... We do not believe that this assumption
> will remain valid in the context of large scale quantum calculations."*

Ruling **S27**'s model — noiseless encoder/recovery/decoder, perfect
syndrome extraction, no fault-tolerance or threshold claim — is not a Sturm
simplification of KL; it is KL's own stated regime, flagged by the authors
as the thing fault tolerance must eventually replace. Cite this sentence
whenever the docstring says "code-capacity model".

## Gaps, divergences, and traps

**G1 — the "projector form" is not a displayed KL equation.** The PRD's
spelling `P Kᵢ†Kⱼ P = α_{ij} P` appears **nowhere as a display in arXiv
v1**. What KL display is the basis form, Thm 3.2 eqs (19)–(20), plus
`⟨i_L|A_a†A_b|j_L⟩ = α_{ab} δ_{ij}` inside the proof (p. 14). Sandwiching
with `P = Σ_i |i_L⟩⟨i_L|` gives the projector form — equivalent, one line,
but the *display* convention is the textbooks' (Nielsen–Chuang Thm 10.1;
Gottesman's eq (2.10) is the matrix-element form with attribution).
**Attribute the conditions to KL; pin the equation to Thm 3.2 (19)–(20); do
not invent a KL equation number for the projector display.** (PRD §9 entry
adjusted accordingly, 2026-08-04.)

**G2 — sufficiency here is constructive, and the construction is the
decoder M11 ships.** Gottesman §2.3 also proves the iff (via his
(2.11)/(2.12) diagonalisation); what the KL proof adds for Sturm is the
*shape* of the recovery — eqs (21)–(23) are syndrome projections plus
coset-representative corrections, i.e. the table decoder, so exactness needs
no separate argument.

**G3 — no stabilizer formalism.** 1996 predates the stabilizer machinery;
codes here are bare subspaces and recovery operators. Everything about
generators, syndromes as anticommutation bits, GF(2) validation, and
`N(S) − S` lives in `gottesman_1997_stabilizer_codes.md`. This file grounds
*correctability*; that one grounds *construction*.

**G4 — no channel-distance content.** "Error 0" is exact; imperfect
recovery is handled via fidelity (§5.3–5.4), not diamond/Choi distance. For
tolerance-based channel comparison semantics use
`watrous_2018_channel_representations.md` (and note its G6: no diamond norm
there either).

**G5 — vocabulary dictionary.** KL "interaction operators" = Kraus
operators = the elements of an M11 `KrausFamily`; KL `$` = channel; KL
"recovery superoperator" = the composed correction channel `R`; KL
`(C, R)` pair = M11's (`StabilizerCode` + `CodeEncoding`-derived recovery);
KL eq (5) = trace preservation. Their families *not* satisfying eq (5)
(sub-superoperators, used for the `e`-error analysis) are CP-TNI objects —
the same regime PRD §3.6/P1 reserves for explicit postselection.
