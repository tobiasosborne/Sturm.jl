# Gavorová, Seidel & Touati (2024) — Topological Obstructions to Quantum Computation with Unitary Oracles

**Citation**: Gavorová, Z., Seidel, M. & Touati, Y. *Topological obstructions
to quantum computation with unitary oracles.* Phys. Rev. A **109**, 032625
(28 Mar 2024). arXiv:2011.10031 (submitted 19 Nov 2020). quant-ph.
DOI: 10.1103/PhysRevA.109.032625.

**Local PDF**: `docs/physics/gavorova_2011.10031.pdf` (16 pp.).

**Status in pipeline**: ground-truth source for the **`when`/`ctrl` guardrails
of PRD-v2 §3.5** (milestone M5) — specifically the strongest-form no-go that
*controlled-U cannot be constructed from black-box access to U*, for **any
number of queries**, even approximately, even with postselection, even under
relaxed causal order. This is the impossibility that *derives* the kernel: the
surface may not control channels, only phase-fixed process values. Cited by
PRD-v2 §1 (lines ~57–72) and §3.5, and listed in the D5 prior-art sweep
(line ~1538).

The companion positive result (control IS possible given side-information about
*where* U acts) is due to Araújo–Feix–Costa–Brukner (arXiv:1309.7976, ref. [36]
in this paper), which this paper reviews and strengthens.

---

## What this paper does (one line)

It unifies oracle algorithms as **continuous functions of the oracle**
`U ∈ U(d)` and derives their limitations from the **topology of U(d)** via one
elementary lemma about homogeneous maps to the circle (**Lemma 1**). The
headline application is the **if clause** (controlled-U): no quantum-circuit
algorithm, with any number of queries to `U` and `U†`, can implement it — not
approximately, not with postselection, not with relaxed causal order.

---

## The if-clause task (what "control from a black box" means here)

Following Araújo et al. [36], the paper identifies the if clause with the
operator (eq. (1)):

> `cϕ(U) := |0⟩⟨0| ⊗ I + e^{iϕ(U)} |1⟩⟨1| ⊗ U`

for **some** real function `ϕ`. When `ϕ ≡ 0` this is exactly controlled-U,
`c0(U)`. Two facts the paper stresses:

- **`c0(U)` is implementable given a +1 eigenstate or a classical description
  of U** (used in phase estimation, ref. [7]) — "Such information is not
  available in our oracle setting." (lines ~183–187). This is precisely the
  side-information escape hatch.
- **The freedom in `ϕ(U)` is necessary**: it "grants the if clause an
  insensitivity to U's global phase." The oracle is a black box up to global
  phase, so any implementable control must tolerate an arbitrary phase choice
  `ϕ(U)`. (lines ~181–183).

The generalized task (eq. (2)) is the **m-th controlled power**:

> `cᵐ_ϕ(U) := |0⟩⟨0| ⊗ I + e^{iϕ(U)} |1⟩⟨1| ⊗ Uᵐ`

The if clause is `m = 1`.

---

## Lemma 1 — EXACT STATEMENT (the M5 audit target)

Quoted verbatim from the paper (p. 5, immediately after the Borsuk–Ulam
theorem statement):

> **Lemma 1.** Let `m ∈ Z`. If a continuous m-homogeneous function
> `f : U(d) → S¹` exists, then `d` divides `m`.

Supporting definition (Definition 5, homogeneity, p. 5):

> A function `f : X → Y` is **m-homogeneous** for some `m ∈ Z` iff
> `f(λx) = λᵐ f(x)` for any `x ∈ X` and any scalar `λ` such that `λx ∈ X`.

On `U(d)` the scalars are restricted to the unit circle `λ ∈ S¹`
(`U(d)` is closed only under unit-modulus rescaling).

**Why this is the obstruction.** A supposed if-clause algorithm `A(U)` is a
*continuous, 0-homogeneous* function of `U` (continuity of query composition;
0-homogeneity because the oracle enters as a superoperator `ρ ↦ UρU†`, phase
cancels). Extracting the control cross-term builds a continuous, **1**-homogeneous
map `f̂ : U(d) → S¹` (Theorem 1 proof, eq. (10) and following, pp. 5–6). By
Lemma 1 this forces `d | 1`, i.e. `d = 1` — impossible for any nontrivial
oracle. Determinant is the canonical *allowed* case: `det(λU) = λᵈ det(U)` is
**d**-homogeneous, and `d | d`, which is exactly why the Dong–Nakayama–Soeda–Murao
algorithm [54] can build `cᵈ_ϕ` (with `ϕ = det(U)^{-1}`) using `d` queries.
(lines ~568–572, ~595–599).

### Proof mechanism of Lemma 1 (the topological engine)

Elementary **homotopy / winding-number** argument on `U(d)` (pp. 6–7,
lines ~659–892; a shorter proof is in Appendix D):

1. Build a loop `U(t) = e^{i2πt} I`, `t ∈ [0,1]`, and a "staircase" loop `U''`
   that raises the phase of each of the `d` diagonal coordinates one at a time.
2. Show `U(t)` and `U''(t)` are **homotopic** as paths in `U(d)` (Fig. 5:
   sequential vs. simultaneous coordinate increase are homotopic inside a cube).
3. An `m`-homogeneous `f` maps `U(t)` to `f(U(t)) = e^{im2πt} f(I)` — a loop of
   **winding number m** on `S¹`. It maps `U''` to a loop of winding number that
   is a multiple of `d` (each of the `d` sub-intervals contributes one turn).
4. Homotopic loops on `S¹` have equal winding number, so `m = kd`, i.e. `d | m`.
   (lines ~882–892).

The Borsuk–Ulam theorem (`f : Sⁿ → Rⁿ` continuous ⇒ ∃ antipodal `x` with
`f(x)=f(-x)`) supplies only a **special case**: Appendix A proves Theorem 1
explicitly for **`d` even and `m` odd** (title line ~1907: "Proof of Theorem 1
(d even, m odd)"), embedding `S³ → U(d)` oddly and using `SU(2) ≅ S³`. The
full result needs the homogeneity/winding lemma, not Borsuk–Ulam.

---

## Main theorems and numbers

- **Theorem 1** (if-clause dichotomy, p. 5). Let `d` = oracle dimension,
  `m ∈ Z`, `ε ∈ [0, 1/2)`.
  - **If `d | m`**: a postselection oracle algorithm ε-approximately achieves
    `(cᵐ_ϕ, {id, inv})` for some `ϕ`, using `|m|` queries.
  - **If `d ∤ m`**: **no** postselection oracle algorithm **and no
    process-matrix algorithm** achieves it, for **any number of queries**.

  The if clause is `m = 1`, so `d ∤ 1` for all `d ≥ 2` ⇒ impossible. The bound
  `ε < 1/2` is the *worst-case postselection diamond distance* (Definition 4),
  so even success probability arbitrarily close to random guessing is ruled out.

- **Appendix C alternative proof (m=1 only)**: `SU(d)` is a **d-fold cover of
  `PU(d)`**; there is no continuous map `PU(d) → U(d)` matching a unitary
  superoperator to an operator (lines ~579–583). This is the covering-space
  face of the same obstruction — the "no continuous phase section" statement.

- **Theorem 2** (p. 8): "Process tomography of Definition 6 is impossible" —
  matrix (not superoperator) tomography of a unitary oracle is obstructed by
  the same mechanism, so the tomography escape from Theorem 1 fails.

- **Theorem 3** (neutralization, p. 10): for `s = (id)ᵐ`, `ε ∈ [0,1)`, if a
  postselection oracle algorithm ε-approximately neutralizes `s` then `d | m`.
  So `d` queries can be neutralized (spin-echo generalization, ref. [54]) but
  most query counts cannot. Applies to parallel and sequential queries alike.

- **Corollary 1** (p. 11): for any `t` with `t(U)ᵈ = U`, the 1/d-th power task
  `(t, {id, inv})` is impossible for `ε < 1/2d`, any number of queries.

- Also covered: oracle **neutralization**, **`U^{1/d}`**, **transpose `Uᵀ`**,
  and **inverse `U†`** algorithms all inherit obstructions from Lemma 1
  (abstract; §IV).

**Robustness — all three literal in the paper.** Abstract (lines ~22–23):
"No number of queries to U and U† lets quantum circuits implement the if clause,
even if admitting **approximations, postselection and relaxed causality**."
Approximation = the `ε`-band of Def. 4; postselection = the postselection
oracle-algorithm model (Def. 1); relaxed causal order = the process-matrix
model, which Theorem 1 also excludes.

---

## The positive half (side-information — this is what derives the kernel)

Ref. [36] (Araújo, Feix, Costa, Brukner) is reviewed here: control **is**
implementable in linear optics because "the gate U in Fig. 1b is not completely
unknown: its position is known, revealing that on the lower path-modes it acts
as the identity." They "suggested adding the direct-sum composition `U ⊕ I` to
the quantum-circuit model." (lines ~195–199). I.e. control becomes possible the
moment you know **where** `U` acts — the difference between `1 ⊗ U` (black box,
forbidden) and `1 ⊕ U` (located, allowed). A phase reference / +1-eigenstate /
classical description likewise unlocks `c0(U)` (lines ~183–184).

---

## Relevance to Sturm v2

This is the *structural* justification for the channel/process-value
stratification — PRD-v2's P4 theorem ("quantum control is an operation on
process values, never on channels") and the §3.5 `when` guardrails.

- **What oracle access CANNOT give you**: control of a black-box channel
  `U ↦ UρU†`. Sturm's surface deals in channels; therefore the surface may not
  offer `ctrl` on a bare channel. `when(q) do body end` is only sound because
  the body first **traces to a unitary-witnessed process value `V`** (a
  phase-fixed representative) and `ctrl(V)` is applied — never `ctrl` of an
  opaque channel. Lemma 1 is *why* the unitary witness (guardrail 1) is a
  soundness requirement, not a lint.

- **What breaks the no-go (the escape Sturm takes)**: a **phase-fixed
  representative** — equivalently, `U ⊕ I` located side-information, a +1
  eigenstate, or a classical description. A **kernel process value** (`U2`
  = quaternion + explicit phase, `Perm`, `UnitaryDAG`) *is* exactly this
  side-information made explicit and typed. The kernel holds definite phase;
  the phase quotient `U(d) → PU(d)` is crossed once, at application, by Ad's
  kernel (§4.3). The no-go pair does not merely forbid — it **derives** the
  kernel/surface boundary.

- **`ctrl` as the single choke point** (§4.2): because control is impossible
  without the phase reference, *every* controlled lowering must be built where
  the phase is definite. Any code path that tried to control something
  phase-ambiguous would be re-treading the impossibility. This grounds the
  system-wide invariant that only `ctrl` constructs controlled decompositions.

### PRD §3.5 / §1 wording audit (M5: "Lemma 1 wording")

The PRD (§1, lines ~57–72) reads:

> "Controlled-U cannot be constructed from black-box access to U
> (Araújo–Feix–Costa–Brukner, arXiv:1309.7976, the original single-exact-query
> no-go; strongest form Gavorová–Seidel–Touati, arXiv:2011.10031 — a
> topological obstruction, their **homogeneous-function Lemma 1**, an elementary
> **winding/homotopy argument (Borsuk–Ulam supplies only the even-dimensional
> intuition)**, that survives **approximation, postselection, and relaxed causal
> order — all three literal in the paper**). Control requires a *phase-fixed
> representative* — in our gloss, a section of `U(d) → PU(d)`; the papers phrase
> it as the non-existence of a continuous phase choice."

**Verdict: the PRD's wording SURVIVES the audit, verbatim-accurate on every
load-bearing claim.** Point by point:

| PRD claim | Paper | Status |
|---|---|---|
| "homogeneous-function Lemma 1" | Lemma 1 is exactly about continuous **m-homogeneous** `f : U(d) → S¹` | ✅ exact |
| "topological obstruction" | Derived from "the topology of the space U(d)" (line ~285) | ✅ |
| "elementary winding/homotopy argument" | Proof of Lemma 1: homotopy of loops, winding numbers on `S¹` (self-described "elementary", lines ~659, 882–892) | ✅ exact |
| "Borsuk–Ulam supplies only the even-dimensional intuition" | Appendix A proves only the **d even, m odd** special case via Borsuk–Ulam; full result needs Lemma 1 (lines ~564–565, ~1907) | ✅ accurate — "even-dimensional" = d even |
| "survives approximation, postselection, and relaxed causal order — all three literal" | Abstract lines ~22–23 verbatim; Theorem 1 covers ε-approx (Def. 4), postselection (Def. 1), and process-matrix / relaxed-causality models | ✅ literal |
| "section of `U(d) → PU(d)` … non-existence of a continuous phase choice" | Appendix C: `SU(d)` is a d-cover of `PU(d)`, no continuous `PU(d) → U(d)` (lines ~579–583) — the section (right-inverse of the projection) is the "matching operator" map | ✅ correct gloss |
| Araújo "original single-exact-query no-go" | ref. [36] proved impossibility "from only **one** query" (lines ~189–191) | ✅ |
| positive half: "extending 1⊗U to 1⊕U" (line ~72) | ref. [36] "suggested adding the direct sum composition U ⊕ I" (line ~199) | ✅ exact |

**One precision note for future citation** (not an error, a sharpening): the
paper's own strongest phrasing is "**No number of queries to U and U†**"
(abstract). If the PRD ever needs to rebut "but with many queries…", cite that
clause and Theorem 1's `d ∤ m` branch ("for **any** number of queries") — the
single-query framing belongs to Araújo [36], the any-query strengthening to
this paper. The PRD already attributes this split correctly.
