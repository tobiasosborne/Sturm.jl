# Watrous 2018 §2.2 — Channel representations (Choi / Kraus / Stinespring)

**Source (local, gitignored):**
`docs/literature/watrous_2018_theory_of_quantum_information.pdf` — John Watrous,
*The Theory of Quantum Information*, Institute for Quantum Computing, University
of Waterloo. Per rule 4 (changed 2026-07-25) the PDF is **local only and
gitignored**; a fresh clone will not have it. Retrieve it from the author's page
if you need to re-check a locator.

**Edition / version pin (read off the document itself).** Title page: *"©2018
John Watrous. To be published by Cambridge University Press. Please note that
this is a draft, pre-publication copy only."* PDF metadata: Creator TeX,
Producer pdfTeX-1.40.17, CreationDate 2019-03-21, **598 pages**, A4. **Every
theorem, corollary, equation and page number below is from this draft build.**
The printed CUP 2018 hardback is a *different* typesetting and its page numbers
may differ; its theorem numbering is believed stable but has **not** been
verified here. Do not silently substitute a locator from another printing —
that is the mistake the Childs extraction (arXiv v3 vs PRX) caught earlier in
this session.

**Reading the PDF.** All page numbers below are the **printed book page**
(the number in the running header). `PDF page = book page + 8`. The section of
interest, §2.2 *Quantum channels*, is book pp. 72–100 = PDF pp. 80–108.

## What Sturm uses it for

This is the **load-bearing citation for PRD-v2 §4.4's stratum-2 theorem** and
for **§4.3's Stinespring dilation contract** (M11, bead `qmpo`; design
`docs/design/m11-82su-synthesis.md` §3.1–§3.2). Specifically it grounds:

| Sturm object | Grounded by |
|---|---|
| `KrausFamily`: TP is the **only** construction-time obligation; CP is free | Thm 2.22 (4)/(5) + Thm 2.26 (4)/(5) + Cor 2.27 (3) |
| `choi_matrix` as the canonical representative; `same_channel` = Choi equality | J is a **linear bijection** on `T(X,Y)` (p. 78, (2.65)/(2.66)) |
| `krausrank`, and why rank compression needs an eigendecomposition | Cor 2.21, Thm 2.22 (5)/(7), Cor 2.27 (4)/(6), and §3.3.4 p. 191 for the converse |
| `dilate` → isometry `Ṽ`, and TP ⟺ `Ṽ†Ṽ = I` | Cor 2.27 (5)/(6) + Thm 2.26 (6)/(7) |
| Zero-padding a Kraus family to a common rank; `M11.CHANNEL.KRAUS-FREEDOM` | Cor 2.23 (+ the padding reduction, see **Gap G1**) |
| "a dilation is fixed only up to the environment" | Cor 2.24 (+ the embedding step, see **Gap G2**) |
| `depolarizing`, `dephasing`/`pinch_channel`, `reset_channel` convention pins | §2.2.3 (2.152)/(2.153), (2.162), Example 2.15 (2.51) |
| `MixedUnitary` as a **distinct type**, not a flag | Def 4.2 p. 202 + Example 4.3 p. 202 (a unital channel that is *not* mixed-unitary) |
| scope exit = `ptrace!` is a legitimate channel | Cor 2.19 p. 76 |

---

## Notation (Ch. 1, needed to read §2.2 at all)

- `L(X,Y)` — linear operators `X → Y`; `L(X) = L(X,X)`.
- `T(X,Y)` — linear **maps** `L(X) → L(Y)`. `CP(X,Y)` ⊂ `T(X,Y)` the completely
  positive ones; `C(X,Y)` the **channels**.
- `Pos(X)`, `Herm(X)`, `D(X)` — positive semidefinite / Hermitian / density
  operators.
- **Isometries** (p. 18, eq. (1.98)): `U(X,Y) = { A ∈ L(X,Y) : A*A = 1_X }`.
  Existence forces `dim(Y) ≥ dim(X)`. `U(X) := U(X,X)` = unitaries (p. 18).
  ⚠ Watrous's `U(·,·)` therefore means **isometry**, not "unitary group" — this
  is exactly the symbol appearing in Cor 2.27(5), and misreading it is the
  single easiest way to misquote the dilation theorem.
- `vec` — the operator-vector correspondence; `E_{a,b}` matrix units.

## §2.2.1 — What a channel is (pp. 72–76)

**Definition 2.13** (p. 73, eq. (2.49)). A *quantum channel* is a linear map
`Φ : L(X) → L(Y)` that is (1) completely positive and (2) trace preserving.
The set is written `C(X,Y)`, and `C(X)` for `C(X,X)`.

Why *complete* positivity, in one example — **Example 2.16** (p. 74, eq.
(2.54)): applying `Φ` to `X` while a spectator register `Z` is present computes
`(Φ ⊗ 1_{L(Z)})(ρ)`, and this must be a density operator for *every* `Z` and
every `ρ ∈ D(X ⊗ Z)`. Positivity alone does not give this. (This is the
paragraph to cite when someone proposes a "channel" that is only positive.)

Three named channels the M11 constructors re-home:

- **Example 2.14** (p. 73, eq. (2.50)) — *unitary channel* `Φ(X) = U X U*`.
  This is the denotation arrow `channel(::ProcessValue)` (ruling S7): total,
  and manifestly many-to-one, since `U` and `e^{iθ}U` give the same `Φ`.
  That is `ker(Ad) = U(1)` at the value level — the content of the
  `M11.CHANNEL.AD-KERNEL` test.
- **Example 2.15** (p. 73, eq. (2.51)) — *replacement channel* `Φ(X) = Tr(X)σ`:
  discard `X`, produce `σ`. `reset_channel()` is `σ = |0⟩⟨0|`.
- **Corollary 2.19** (p. 76) — the trace map `Tr ∈ T(X,C)` **is** completely
  positive, hence a channel. This is the formal licence for §3.9's
  "scope exit traces the locals": `ptrace!` is a channel, not an escape hatch.
  (Proof route: `Tr*(α) = α·1_X` is CP by Prop 2.17 p. 75; adjoints of CP maps
  are CP by the Remark after Prop 2.18, p. 76.)

## §2.2.2 — The four representations (pp. 77–90)

Watrous defines four representations of an arbitrary `Φ ∈ T(X,Y)` and then
characterises CP, TP, and "channel" in each.

### The Choi representation (p. 78)

    J(Φ) = (Φ ⊗ 1_{L(X)})( vec(1_X) vec(1_X)* )                        (2.64)
    J(Φ) = Σ_{a,b ∈ Σ} Φ(E_{a,b}) ⊗ E_{a,b}          (for X = C^Σ)     (2.65)
    Φ(X) = Tr_X( J(Φ) (1_Y ⊗ X^T) )                                    (2.66)

`J : T(X,Y) → L(Y ⊗ X)` is a **linear bijection** (p. 78; the inverse is
(2.66)). Note the operand order: `J(Φ) ∈ L(Y ⊗ X)` — **output space first**.

> **Choi rank** (p. 78, immediately after (2.66)): *"For a given map
> `Φ ∈ T(X,Y)`, the rank of its Choi representation `J(Φ)` is called the Choi
> rank of `Φ`."*

Two Sturm consequences, both mechanical:

1. `same_channel(a,b) := Choi(a) ≈ Choi(b)` is **exactly** semantic equality of
   the denoted maps, because `J` is injective. It is not a heuristic.
2. `choi_matrix` is `O(4^W)` — hence ruling S6's refusal to put it behind
   `Base.isapprox`.

### Kraus representations (p. 79)

    Φ(X) = Σ_{a∈Σ} A_a X B_a*                                          (2.68)

*"Unlike the natural representation and Choi representation, however, Kraus
representations are **not unique**."* (p. 79). The `A_a = B_a` case is the
completely positive one (Thm 2.22).

### Stinespring representations (pp. 79–80)

    Φ(X) = Tr_Z( A X B* ),        A, B ∈ L(X, Y ⊗ Z)                   (2.71)

Again *"Stinespring representations always exist for a given map `Φ`, and are
**not unique**."* (p. 79). The `A = B` case ⟺ CP (p. 80).

### Proposition 2.20 — the dictionary (pp. 80–81)

For collections `{A_a}, {B_a} ⊂ L(X,Y)` indexed by `Σ`, the four statements are
equivalent: `K(Φ) = Σ_a A_a ⊗ B̄_a` (2.74 — the bar is complex conjugation, and
`pdftotext` drops it, so re-check it in the rendered PDF if you depend on it);
`J(Φ) = Σ_a vec(A_a) vec(B_a)*` (2.75); the Kraus form (2.76); and the
Stinespring form (2.78) with

    Z = C^Σ,    A = Σ_{a∈Σ} A_a ⊗ e_a,    B = Σ_{a∈Σ} B_a ⊗ e_a        (2.77)

**⚠ (2.77) is the tensor-factor ordering pin. `A ∈ L(X, Y ⊗ Z)` with
`A = Σ_a A_a ⊗ e_a` means, in Dirac notation, `A|ψ⟩ = Σ_a (A_a|ψ⟩)_Y ⊗ |a⟩_Z`:
the OUTPUT SYSTEM leads, the ENVIRONMENT trails.** See **Gap G3** — Sturm's
`StinespringDilation` pins the opposite order, deliberately, and the two are
not the same matrix.

### Corollary 2.21 — you can always hit the Choi rank exactly (p. 81)

For `Φ ∈ T(X,Y)` nonzero with `r = rank(J(Φ))`: (1) for **any** alphabet with
`|Σ| = r` there is a Kraus representation `Φ(X) = Σ_{a∈Σ} A_a X B_a*` (2.81);
(2) for **any** `Z` with `dim(Z) = r` there is a Stinespring representation
(2.82). Proof: write `J(Φ) = Σ_a u_a v_a*` with `{u_a}` a basis of `im(J(Φ))`,
then `vec(A_a) = u_a`, `vec(B_a) = v_a` (2.83)–(2.86).

### Theorem 2.22 — CP ⟺ Choi ⟺ Kraus ⟺ Stinespring (pp. 82–84)

For `Φ ∈ T(X,Y)` nonzero, the following are **equivalent**:

1. `Φ` is completely positive.
2. `Φ ⊗ 1_{L(X)}` is positive.
3. `J(Φ) ∈ Pos(Y ⊗ X)`.
4. `Φ(X) = Σ_{a∈Σ} A_a X A_a*` for some `{A_a} ⊂ L(X,Y)` and some `Σ`. (2.87)
5. Statement 4 holds with `|Σ| = rank(J(Φ))`.
6. `Φ(X) = Tr_Z(A X A*)` for some `A ∈ L(X, Y⊗Z)`, some `Z`. (2.88)
7. Statement 6 holds with `dim(Z) = rank(J(Φ))`.

Proof structure (p. 83): `(1)⇒(2)⇒(3)⇒(5)⇒(4)⇒(1)` and `(5)⇒(7)⇒(6)⇒(1)`.
The `(3)⇒(5)` step is the spectral theorem applied to `J(Φ) ⪰ 0`, which is
where the *number* `rank(J(Φ))` enters.

**Attribution** (§2.5 Bibliographic remarks, p. 123): *"Theorem 2.22 is an
amalgamation of results that are generally attributed to Stinespring (1955),
Kraus (1971, 1983), and Choi (1975). Stinespring and Kraus also proved more
general results holding for infinite-dimensional spaces; Theorem 2.22 presents
only the finite-dimensional analogues."* This is why the synthesis (§7) drops a
separate `stinespring_1955_dilation.md`: Watrous is the finite-dimensional
statement Sturm actually implements, in one place, freely available.

**Sturm reading of 4 ⇒ CP.** `KrausFamily` is *constructed* from an operator-sum
`{K_i}` with `K_i = K_i` on both sides. By statement 4, **complete positivity is
free** — there is nothing to check. Only trace preservation is a real
obligation. This is ruling S5 ("TP checked at construction; CP free"), and this
theorem is its whole justification.

### Corollary 2.23 — Kraus freedom is a unitary mixing (pp. 84–85)

> Let `{A_a : a ∈ Σ}, {B_a : a ∈ Σ} ⊂ L(X,Y)` satisfy
> `Σ_a A_a X A_a* = Σ_a B_a X B_a*` for all `X ∈ L(X)` (2.99). **There exists a
> unitary `U ∈ U(C^Σ)`** such that
>
>     B_a = Σ_{b∈Σ} U(a,b) A_b                                         (2.100)
>
> for all `a ∈ Σ`.

Proof (p. 85): equal maps ⇒ equal Chois ⇒ `Σ vec(A_a)vec(A_a)* = Σ
vec(B_a)vec(B_a)*` (2.102); bundle into purifications `u = Σ vec(A_a) ⊗ e_a`,
`v = Σ vec(B_a) ⊗ e_a` (2.103) with `Tr_Z(uu*) = Tr_Z(vv*)` (2.104); apply
**Theorem 2.12** (*Unitary equivalence of purifications*, p. 72: if
`Tr_Y(uu*) = Tr_Y(vv*)` then `v = (1_X ⊗ U)u` for some `U ∈ U(Y)`).

This is the **first half of PRD-v2 §4.4's stratum-2 theorem**, and it is what
`M11.CHANNEL.KRAUS-FREEDOM` exercises: build `B_a` from `A_a` by a unitary
mixing `U`, assert `same_channel(a,b)` while `a != b` structurally.

### Corollary 2.24 — Stinespring freedom is a unitary on the environment (p. 85)

> Let `A, B ∈ L(X, Y⊗Z)` satisfy `Tr_Z(A X A*) = Tr_Z(B X B*)` for every
> `X ∈ L(X)` (2.107). **There exists a unitary `U ∈ U(Z)`** such that
>
>     B = (1_Y ⊗ U) A                                                  (2.108)

Proof (p. 85): slice `A_a = (1_Y ⊗ e_a*)A`, `B_a = (1_Y ⊗ e_a*)B` (2.109), so
(2.107) *is* (2.99); apply Cor 2.23. Watrous notes the two corollaries are
"essentially equivalent" (p. 85).

This is the **second half of the stratum-2 theorem** — with the caveat in
**Gap G2**: the hypothesis is that `A` and `B` share **one and the same** `Z`.

### Theorem 2.26 — trace preservation (pp. 87–89)

For `Φ ∈ T(X,Y)` the following are equivalent: (1) `Φ` is TP; (2) `Φ*` is
unital; (3) `Tr_Y(J(Φ)) = 1_X`; (4) **there exist** `{A_a},{B_a}` with
`Φ(X) = Σ A_a X B_a*` and `Σ_a A_a* B_a = 1_X`; (5) **for all** such
`{A_a},{B_a}`, `Σ_a A_a* B_a = 1_X` must hold; (6) there exist
`A,B ∈ L(X,Y⊗Z)` with `Φ(X) = Tr_Z(A X B*)` and `A*B = 1_X`; (7) for **every**
such `A,B`, `A*B = 1_X`.

The `(4) ⟺ (5)` and `(6) ⟺ (7)` "there exists / for all" pairing is the reason
`KrausFamily`'s TP check is representation-independent: if **one** operator-sum
form of `Φ` satisfies `Σ K_i† K_i = 1`, **every** one does. So checking the
family the user handed us is checking the channel, not the representative.

Specialising to `A_a = B_a`: `Σ_a K_a† K_a = 1_X`. That is the quantity
`KRAUS_TP_ATOL` bounds, and `‖Σ K†K − 1‖_∞` is the deviation the error message
must name (ruling S4).

Specialising (6)/(7) to `A = B`: `A*A = 1_X`, i.e. **`A` is an isometry**
(eq. (1.98)). So `Ṽ†Ṽ = I` is not a convenient extra property of the dilation —
**it is trace preservation, restated**. That is the content of the
`M11.DILATE.ISOMETRY` test, and the reason a TP-validated `KrausFamily` can
never produce a non-isometric `Ṽ`.

### Corollary 2.27 — the channel characterisation (p. 89) — **the dilation contract**

> For `Φ ∈ T(X,Y)` the following are equivalent:
>
> 1. `Φ` is a channel.
> 2. `J(Φ) ∈ Pos(Y⊗X)` **and** `Tr_Y(J(Φ)) = 1_X`.
> 3. There exist an alphabet `Σ` and `{A_a : a ∈ Σ} ⊂ L(X,Y)` with
>    `Σ_a A_a* A_a = 1_X` and `Φ(X) = Σ_a A_a X A_a*`.          (2.129)
> 4. Statement 3 holds for `|Σ| = rank(J(Φ))`.
> 5. **There exists an isometry `A ∈ U(X, Y ⊗ Z)`**, for some choice of a
>    complex Euclidean space `Z`, such that
>
>        Φ(X) = Tr_Z( A X A* )                                        (2.130)
>
> 6. Statement 5 holds under the requirement `dim(Z) = rank(J(Φ))`.

**This is F33's contract, verbatim.** Statement 3 is the `KrausFamily`
invariant. Statement 5 is `dilate`. Statement 6 says the minimal environment
dimension is the Choi rank. Combining 5 with **Prop 2.20 (2.77)** gives the
Dirac form the PRD quotes:

    A|ψ⟩ = Σ_{a} (A_a|ψ⟩) ⊗ |a⟩_Z            (Watrous ordering: system, env)

Watrous does **not** write that Dirac line himself; it is (2.77) instantiated at
`A_a = B_a` and read through the isometry of Cor 2.27(5). Cite it as
"Cor 2.27(5) with Prop 2.20 (2.77)", not as a display equation of the book.

Two more results in the neighbourhood that M11 touches:

- **Proposition 2.28** (p. 90): `C(X,Y)` is **compact and convex**. This is why
  `MixedUnitary` (a convex combination of unitary channels) is automatically a
  channel with no further validation, and why `pauli_channel(px,py,pz)` needs
  only `p ⪰ 0`, `Σp ≤ 1`.
- **Theorem 2.31 (Choi)** (p. 97, §2.2.4): for a channel with a **linearly
  independent** Kraus set `{A_a}`, `Φ` is an extreme point of `C(X,Y)` iff
  `{A_b* A_a : (a,b) ∈ Σ×Σ}` is linearly independent. Not needed by M11; noted
  so that a future `EnsembleChannel`/extremality question has its locator.

### The converse of minimality (§3.3.4, p. 191)

`Cor 2.21` / `Thm 2.22(5),(7)` / `Cor 2.27(4),(6)` give **existence** at the
Choi rank. The **lower bound** — that you cannot do better — is stated by
Watrous later, in §3.3.4, in the paragraph preceding Theorem 3.62 (book p. 191):

> *"One has, by Theorem 2.22, that a given complex Euclidean space `Z` admits a
> Stinespring representation `Φ(X) = Tr_Z(A₀ X A₁*)` of `Φ` ... **if and only
> if** the dimension of `Z` is at least as large as the Choi rank of `Φ`."*

So: **minimal Kraus rank = minimal environment dimension = Choi rank**, with
existence from §2.2.2 and the converse from p. 191. (The converse is also one
line from (2.75): `J(Φ) = Σ_{a∈Σ} vec(A_a)vec(A_a)*` is a sum of `|Σ|` rank-≤1
operators, so `rank(J(Φ)) ≤ |Σ|`. Use whichever citation you prefer; both are
in this book.) There is **no** numbered "minimal Kraus rank" corollary inside
§2.2.2 itself — see **Gap G4**.

## §2.2.3 — Named channels, for the constructor convention pins (pp. 91–95)

- **Isometric / unitary channels** (p. 91): `Φ(X) = A X B*` with `A = B` an
  isometry is a channel by Cor 2.27; `K(Φ) = A ⊗ B̄` (2.142),
  `J(Φ) = vec(A)vec(B)*` (2.143). The identity channel has the rank-one Choi
  `vec(1_X)vec(1_X)*` (p. 92) — the reference matrix for
  `M11.QECC.ENCODE-DECODE-ID`.
- **Replacement channels** (p. 93): `Φ(X) = ⟨A,X⟩B` (2.144); with `A = 1_X`,
  `B = σ ∈ D(Y)` it is the replacement channel. `reset_channel()`.
- **Completely depolarizing channel** `Ω ∈ C(X)` (p. 93):

      Ω(X) = Tr(X) ω,     ω = 1_X / dim(X)                    (2.152)/(2.153)
      J(Ω) = (1_X ⊗ 1_X) / dim(X)                             (2.155)

  ⚠ Watrous's `Ω` is the **fully** depolarizing channel (Sturm's
  `depolarizing(1)`). Ruling S8 pins Sturm's one-parameter family as
  `ρ ↦ (1−p)ρ + p·1/2`, i.e. `(1−p)·id + p·Ω` on one qubit — an interpolation to
  Watrous's `Ω`, **not** the `(p/3)ΣPρP` convention. Cite (2.152)/(2.153) for
  the `p = 1` endpoint, and state the interpolation in the docstring; the book
  does not define the one-parameter family.
- **Completely dephasing channel** `Δ ∈ C(X)` (p. 94):

      Δ(X) = Σ_{a∈Σ} X(a,a) E_{a,a}                                   (2.162)

  *"replacing every off-diagonal entry of a given operator `X` by 0 and leaving
  the diagonal entries unchanged"*, and *"an ideal channel for classical
  communication"*. This is **exactly** Sturm's pinch: `pinch_channel()` /
  `_PINCH_KRAUS`, and it is the `Δ_in`/`Δ_out` in `classicalise`'s
  `Δ_out ∘ 𝓔 ∘ Δ_in` (ruling S31). It is also, on p. 96, how Watrous *defines*
  a classical register: *"a classical register [is] any register that ... would
  be unaffected by an application of the completely dephasing channel `Δ` at any
  moment during its existence"* — the cleanest available statement of why
  `classicalise` is **phase-blind by construction** and can never be a
  channel-equivalence test (`M11.CLASSICALISE.IS-PHASE-BLIND`, the F3-barred
  criterion).
- **Transpose map** `T` (pp. 93–94): `J(T) = W` the swap operator (2.159), which
  is not PSD for `|Σ| ≥ 2`, so `T` is not CP. Useful as a negative control if a
  test ever wants a non-CP map.

## §4.1.1 — Mixed-unitary channels (p. 202)

**Definition 4.2** (p. 202): `Φ ∈ C(X)` is *mixed unitary* if there are an
alphabet `Σ`, a probability vector `p ∈ P(Σ)` and unitaries `{U_a} ⊂ U(X)` with

    Φ(X) = Σ_{a∈Σ} p(a) U_a X U_a*                                     (4.1)

— *"equivalently, a convex combination of unitary channels."*

**Example 4.3** (p. 202): on `X = C³`, `Φ(X) = ½Tr(X)1 − ½X^T` is **unital but
not mixed unitary**. Two Sturm consequences:

1. `MixedUnitary` must be its own type, not a boolean flag on `KrausFamily`
   (ruling S2): "mixed-unitary" is a genuine subclass, and membership is not
   decidable by inspecting a family's unitality.
2. The class-P executable dilation (`Σ_i |i⟩⟨i|_E ⊗ U_i` after preparing
   `|χ⟩_E = Σ√p_i|i⟩`) is available **exactly** on (4.1)'s shape. There is no
   convention by which a general unital channel is made to fit it. The
   catalogue's class X refusal is a statement about this definition, not an
   implementation shortfall.

---

## Gaps, divergences, and things NOT in this source

These are the entries a future agent should read first. Each is a place where
Sturm's design says something the source does **not** literally say.

**G1 — "zero-padding to a common rank" is not in Corollary 2.23.**
PRD-v2 §4.4 says a Kraus family is determined *"only up to zero-padding to a
common rank and a unitary mixing of its operators"*. Cor 2.23's hypothesis is
that **both** families are indexed by the **same** alphabet `Σ`. Two families of
different sizes are brought under that hypothesis by appending zero operators to
the shorter one — which is harmless (a zero operator contributes nothing to
(2.68) and nothing to (2.75)) but is a *step Watrous does not take*. The PRD
sentence is therefore "Cor 2.23 **after** padding", and the padding is the
trivial reduction, not a second theorem. Cite it that way in code comments.

**G2 — "partial isometry" is not Watrous's word.**
PRD-v2 §4.4 says a Stinespring dilation is *"determined only up to a partial
isometry on the environment"*. The strongest statement in §2.2.2 is **Cor 2.24**:
a **unitary** `U ∈ U(Z)` on a **shared** environment space `Z`. The
partial-isometry form is what you get after first embedding two dilations with
`dim(Z_A) ≠ dim(Z_B)` into a common `Z` of the larger dimension (licensed by
Cor 2.27(5), which quantifies over "some choice of `Z`", together with the
p. 191 "if and only if dim(Z) ≥ Choi rank" statement), and then applying
Cor 2.24. The composite `Z_A → Z_B` is then an isometry / partial isometry
rather than a unitary. **The PRD claim is true and derivable from this source,
but it is Cor 2.24 + an embedding argument, not a quotable theorem.** Do not
attribute the phrase "partial isometry" to Watrous.

**G3 — ⚠ THE ENVIRONMENT-ORDERING DIVERGENCE (highest-risk item).**
Watrous (2.77) and Cor 2.27(5) put the dilation in `L(X, Y ⊗ Z)`:
**output system leading, environment trailing** — `A|ψ⟩ = Σ_a (A_a|ψ⟩)|a⟩_E`.
PRD-v2 §9's paraphrase, `V|ψ⟩ = Σᵢ Kᵢ|ψ⟩|i⟩_E`, follows Watrous exactly.

Sturm's implementation pins the **opposite** order. Synthesis ruling **S10**
("Environment wires LEAD (MSB)") fixes

    Ṽ[i·d + s + 1, t + 1] = Kᵢ[s + 1, t + 1]

with `i` the environment index and `d = 2^W` the system dimension, i.e. the
environment index varies **slowest** — this is `A = Σ_a e_a ⊗ A_a ∈ Z ⊗ Y`.
The two dilations differ by the swap `W : Y⊗Z → Z⊗Y` and denote the **same
channel** (`Tr_Z` is insensitive to it), so neither is wrong — but they are
**different matrices**, and the `M11.DILATE.KRAUS-RECONSTRUCT` assertion (which
*is* the contract) is only true in S10's layout. Under Watrous's layout the
Kraus blocks are a **strided** extraction, not contiguous rows.

Consequences to carry into the code:
- The docstring of `dilate` must state the ordering **and** state that it is the
  transpose of the book's, with this file as the reference.
- Cor 2.24's freedom becomes `B = (U ⊗ 1_Y) A` in Sturm's layout, not
  `(1_Y ⊗ U) A`.
- S10's third argument (env-leading = control-leading, matching `Ctrl`) is a
  *Sturm* argument about `apply!` and `ctrl` conventions. It has no counterpart
  in the source, and should not be presented as one.
- `M11.DILATE.ENV-LEADING` on `amplitude_damping(0.3)` is the test that catches
  a reader who "corrected" the code back to the book's convention.

**G4 — no named minimality corollary inside §2.2.2.**
"Minimal Kraus rank = Choi rank" is assembled from existence (Cor 2.21 /
Thm 2.22(5),(7) / Cor 2.27(4),(6)) plus the converse, which is stated only in
§3.3.4 p. 191 (or derived in one line from (2.75)). There is no
"Corollary: the minimal number of Kraus operators is `rank J(Φ)`" to cite. Write
the two-part citation.

**G5 — nothing here is an algorithm.**
Watrous proves existence of the isometry; he does not give a numerical recipe,
and in particular says nothing about **unitary completion** of an isometry to a
square unitary (ruling S9's Householder construction). That is numerical linear
algebra (Golub & Van Loan §5.1–5.2) and the synthesis §7 correctly says **no
distillation is owed** for it. Do not cite this file for the completion step.
Equally: Watrous's `Z` in Cor 2.27(5) is an abstract space of dimension `≥`
Choi rank; the choice `dim(Z) = 2^E` with `E = ⌈log₂ R⌉` **wires**, and the
zero-padding of the family from `R` to `2^E` operators, is Sturm's discretisation
(and is exactly why `M11.DILATE.KRAUS-RECONSTRUCT` asserts `≈ 0` for the padded
indices).

**G6 — no diamond-norm / channel-distance content is quoted here.**
`same_channel` is Choi equality with a tolerance. Watrous's Chapter 3 (the
completely bounded trace norm, §3.3) is the right source if a diamond-norm test
is ever wanted; it is deliberately **not** distilled here, because M11 does not
use it. Do not cite this file for diamond-norm claims.

**G7 — a partial, on-disk source for `chiribella_2009_quantum_combs.md`
(landed 2026-08-04; this locator is now the cross-check, not the source).**
Synthesis §7's **P4** (superchannel = "circuit with a hole", and the
factorisation `Θ(𝓝) = Tr_M[D ∘ (𝓝 ⊗ id_M) ∘ E]`) is now sourced at theorem
strength by the CDP supermaps paper (EPL 83, 30004 (2008), Thm 1 — see the
combs distillation, incl. its G1 pin-discipline warning). The partial
locator in *this* book remains worth recording:

- **Exercise 2.6(b)(c)**, book pp. 121–122. Let `Ξ ∈ CP(Y⊗X, W⊗Z)` be such that
  for every channel `Φ ∈ C(X,Y)` there is a channel `Ψ ∈ C(Z,W)` with
  `Ξ(J(Φ)) = J(Ψ)` (2.314). Then (c): *"there exist channels
  `Ξ₀ ∈ C(Z, X⊗V)` and `Ξ₁ ∈ C(Y⊗V, W)`, for some choice of a complex Euclidean
  space `V`, for which ... `Ψ = Ξ₁ (Φ ⊗ 1_{L(V)}) Ξ₀`"* (2.316).
  That **is** the superchannel realisation theorem, with `V` the memory wire.
- **§2.5 Bibliographic remarks, p. 123**: *"Exercise 2.6 is representative of a
  related result of Chiribella, D'Ariano, and Perinotti (2008)"*, and
  *"Gutoski and Watrous (2007) and Chiribella, D'Ariano, and Perinotti (2009)
  generalized this result to quantum processes having inputs and outputs that
  alternate for multiple steps."*

Caveats, stated because they matter: (i) it is an **exercise**, stated without
proof, so it is a weaker citation than a theorem; (ii) Sturm's
`Θ(𝓝) = D ∘ R ∘ 𝓝 ∘ E` is the case `V = C` (**no memory wire**) — the
memoryless special case, which the synthesis (S27, §4.2 "Correlated /
non-Markovian noise") already names as the modelling restriction. So this
exercise licenses the *general* shape and shows precisely what M11 is choosing
not to use.
