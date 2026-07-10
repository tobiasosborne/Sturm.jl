# Unit Quaternions and the Bloch Sphere

Source: K. B. Wharton and D. Koch, "Unit Quaternions and the Bloch
Sphere", *J. Phys. A: Math. Theor.* **48** (2015) 235302.
DOI: 10.1088/1751-8113/48/23/235302. arXiv:1411.4999v2 [quant-ph],
23 Apr 2015. PDF in `docs/physics/wharton_koch_1411.4999.pdf`.

This is the citation PRD-v2 §4.1 attaches to the `U2` process value:
"the quaternion↔SU(2) identification itself is textbook (cite
Wharton–Koch, arXiv:1411.4999); the novelty is the
*persistent-IR-with-quaternion-composition* engineering choice." The
paper grounds the *representation* (unit quaternion + phase for U(2),
Hamilton product = composition, the double cover, why `Ry(2π) = −I`).
It does NOT ground Sturm's IR engineering, and — see the WARNING below —
its own spinor→quaternion map is an idiosyncratic one whose axis
labels must NOT be copied into the operator representation.

The bulk of the paper (Sections 3–5: time reversal, broken symmetry,
"second-order qubits", global-phase-as-hidden-variable) is foundational
speculation *irrelevant* to Sturm. We distill only Section 2 and the
Appendix — the mathematics of the quaternion↔spinor/operator map.

---

## The two objects the paper maps between (pp. 4–5)

- A **spinor** `|χ⟩ = (a, b)ᵀ`, `a,b ∈ ℂ`, normalized `⟨χ|χ⟩ = 1`.
  Spinors distinguish global phase: `|χ⟩` and `exp(iα)|χ⟩` are
  *different* spinors at the *same* Bloch point.
- A **unit quaternion** `q ∈ ℍ`, `|q|² = 1`. The set of unit
  quaternions IS the unit 3-sphere S³, and S³ ≅ SU(2) as groups. This
  isomorphism is the whole point: unit quaternions and SU(2) are the
  same group in different notation.

Bloch angles (Eq. 1, p. 4): `ψ = e^{−iφ/2} cos(θ/2)|0⟩ + e^{iφ/2}
sin(θ/2)|1⟩`. Global phase drops under S³ → S² (the Hopf fibration),
and — a topological fact the paper leans on — there is *no continuous
global section*, so phase cannot be removed continuously over the whole
Bloch sphere (pp. 2, 21). This is the same non-existence-of-a-section
fact that PRD-v2 §4.1 invokes against the v0.1 "H!² = −I is a feature"
SU(2)-section doctrine.

## Quaternion algebra — the Hamilton product convention (Appendix, p. 23)

Hamilton's rules, stated verbatim in the Appendix (right-handed,
`ijk = −1`):

```
i² = j² = k² = ijk = −1
ij =  k      ji = −k
jk =  i      kj = −i
ki =  j      ik = −j
```

Quaternions do NOT commute. Write `q = A + iB + jC + kD` (real part A,
imaginary parts B,C,D). Then (Appendix, p. 23):

- Conjugate: `q̄ = A − iB − jC − kD`.
- Norm: `|q|² = q q̄ = q̄ q = A² + B² + C² + D²`.
- Conjugate of a product REVERSES order: `‾(pq) = q̄ p̄` (p. 23) —
  exactly like a Hermitian conjugate of a matrix product. This is the
  identity that makes `adjoint` a Hamilton conjugation, and its
  order-reversal is why `adjoint(V ∘ W) = adjoint(W) ∘ adjoint(V)`.
- Unit quaternions are closed under multiplication:
  `(pq)‾(pq) = p q q̄ p̄ = p p̄ = 1` (p. 23).

Exponential form (Eq. 30, p. 24), for a *pure* unit quaternion `v̂`
(no real part, `v̂² = −1`):

```
exp(v̂ θ) ≡ cos(θ) + v̂ sin(θ)              (Eq. 30)
```

Angles add ONLY when the two exponentials share the same axis `v̂`;
otherwise expand via Eq. 30 (Hamilton-multiply). Two exponential forms
name the same quaternion: `exp(v̂ θ) = exp(−v̂ (−θ))` (p. 24) — this is
the sign ambiguity underlying the double cover.

Most general norm-preserving transform (p. 24): `q' = e^{û φ} q e^{v̂ θ}`
(a left and a right multiplication); inverse conjugates BOTH without
swapping sides: `q = e^{−û φ} q' e^{−v̂ θ}`.

## Pauli matrices and the `−iσ⃗ ↔ (i,j,k)` correspondence (Eqs. 8, 31; pp. 6–7, 25)

Pauli matrices (Eq. 31, p. 25):

```
σ_x = [[0, 1],[1, 0]]   σ_y = [[0,−i],[i, 0]]   σ_z = [[1, 0],[0,−1]]
```

The rotation operator (Eq. 8, p. 7):

```
R_n̂(γ) = cos(γ/2) I − i sin(γ/2) (n̂ · σ⃗)      (Eq. 8)
```

The key algebraic fact (p. 7, p. 25): the three matrices `u_n ≡ −i σ_n`
obey the SAME multiplication algebra as the imaginary quaternions
`i, j, k`. So a unit quaternion IS an SU(2) matrix once you pick the
identification `(i,j,k) ↔ −i(σ_a,σ_b,σ_c)` for some assignment of axes.
*Which* axis assignment is a convention — and the paper makes TWO
different choices in two different roles. This is the trap.

---

## ⚠ CONVENTION WARNING — the paper's map M_i is NOT the operator convention

The paper's headline map `M_i` (Eq. 3, p. 5) sends a **spinor state**
to a quaternion by `q = a + b·j`, explicitly

```
M_i[|χ⟩] = q = Re(a) + i·Im(a) + j·Re(b) + k·Im(b)      (Eq. 3)
```

This state map forces an *idiosyncratic* axis labeling (p. 25): under
`M_i`, `u_x = −iσ_x ↔ k`, `u_y = −iσ_y ↔ −j` (note the MINUS), and
`u_z = −iσ_z ↔ i`. Consequently Table 1 (p. 7) lists

```
Pauli X ↔ e^{±k π/2} = ±k        (right-multiplication on the state q)
Pauli Y ↔ e^{±j π/2} = ±j
Pauli Z ↔ e^{±i π/2} = ±i
Hadamard ↔ ±(i+k)/√2
```

These `X↔k, Y↔−j, Z↔i` labels are artifacts of the state-map choice
`q = a + bj` and of Table 1 describing gates as **right-multiplications
acting on a state quaternion**. Sturm's `U2` is a **process value (an
operator)**, not a state; it composes by operator multiplication, not by
right-acting on a stored spinor. **Do NOT transcribe Table 1's axis
labels into the `U2` representation.** A silently mixed convention here
is exactly the class of phase/sign bug PRD-v2 §4.1 and CLAUDE.md
principle 6 warn about.

---

## PINNED CONVENTION for the Sturm `U2` process value (adopt verbatim)

Use the **standard, right-handed operator convention** `(i,j,k) ↔
−i(σ_x, σ_y, σ_z)`, which is the one Eq. (8) yields directly with no
axis relabeling. This is a deliberate departure from the paper's `M_i`
state labels (see warning). Under it:

**Quaternion.** Store `q = (w, x, y, z)` with `w` real, `(x,y,z)` the
`(i,j,k)` components; unit norm `w²+x²+y²+z² = 1`. (Paper's `A,B,C,D`.)

**Quaternion → SU(2) matrix** (the single load-bearing correspondence):

```
U(q) = w·I − i (x σ_x + y σ_y + z σ_z)
     = [[ w − i z ,  −y − i x ],
        [  y − i x ,   w + i z ]]
```

Verification against Eq. (8): a rotation by γ about unit axis `n̂` is the
quaternion `q = (cos(γ/2), sin(γ/2) n_x, sin(γ/2) n_y, sin(γ/2) n_z)`,
and `U(q) = cos(γ/2) I − i sin(γ/2) n̂·σ⃗ = R_n̂(γ)` exactly. This map is
a group isomorphism unit-quaternions → SU(2): `U(p q) = U(p) U(q)` with
the Hamilton product above (`ij=k`), and `U(q̄) = U(q)†`.

**Hamilton product `p q`** (composition of SU(2) parts; 16 real
multiplies, 12 adds — the "16 multiplications" of the task and PRD §4.1):

```
(p q)_w = p_w q_w − p_x q_x − p_y q_y − p_z q_z
(p q)_x = p_w q_x + p_x q_w + p_y q_z − p_z q_y
(p q)_y = p_w q_y − p_x q_z + p_y q_w + p_z q_x
(p q)_z = p_w q_z + p_x q_y − p_y q_x + p_z q_w
```

Because `U(pq) = U(p)U(q)`, quaternion product = matrix composition;
right-to-left matrix order (PRD §4.2's `∘`) means `V ∘ W` stores the
Hamilton product `q_V q_W`.

**Adjoint** = conjugate `q̄ = (w, −x, −y, −z)` (unit ⇒ inverse = conjugate).

**The gates, in THIS convention** (SU(2) part; det=1 pure-quaternion form):

```
X ↔ q = (0, 1, 0, 0) = i     U(i)   = −i σ_x
Y ↔ q = (0, 0, 1, 0) = j     U(j)   = −i σ_y
Z ↔ q = (0, 0, 0, 1) = k     U(k)   = −i σ_z
H ↔ q = (0, 1/√2, 0, 1/√2)   U      = −i (σ_x+σ_z)/√2
Ry(γ) ↔ q = (cos(γ/2), 0, sin(γ/2), 0)
Rz(γ) ↔ q = (cos(γ/2), 0, 0, sin(γ/2))
Rx(γ) ↔ q = (cos(γ/2), sin(γ/2), 0, 0)
```

## Why `U2` needs a SEPARATE U(1) phase — U(2) = (SU(2) × U(1)) / ℤ₂

`U(q)` above always has **det = +1** (it is SU(2)). But `X, Y, Z, H`
as *unitaries* have det = −1 (`U(i) = −iσ_x`, not `σ_x`; `σ_x` itself is
in U(2)\SU(2)). So a bare quaternion cannot represent the textbook gates
on the nose — it represents them *up to a global phase*. That phase is
the fifth float. Write any `M ∈ U(2)` as

```
M = e^{iφ} S ,   S ∈ SU(2) ,   S = U(q) .
```

`U2` = (unit quaternion `q`, phase `φ`) = 5 floats. Composition:
`(q₁,φ₁) ∘ (q₂,φ₂) = (q₁ q₂,  φ₁+φ₂ mod 2π)` — Hamilton-multiply the
quaternions, ADD the phases. The phase quotient is crossed **once, at
application** (PRD §4.3 Ad), never by convention in library code.
Example: `X = e^{iπ/2} U(i)`, i.e. `(q=(0,1,0,0), φ=π/2)`.

The map (q, φ) ↦ e^{iφ}U(q) is **2-to-1**: since `U(−q) = −U(q)`,

```
(q, φ)  and  (−q, φ+π)  denote the SAME U(2) element.
```

That ℤ₂ is the `(q,φ) ~ (−q, φ+π)` equality quotient PRD §4.1 declares
normative. Two consequences the paper's sign-ambiguity discussion
(Eq. 30, p. 24: `exp(v̂θ)=exp(−v̂(−θ))`) directly underwrites:

- **Exact H² lands on the OTHER representative of +I.** `q_H² =
  (1/2)(i+k)(i+k) = (1/2)(i² + ik + ki + k²) = (1/2)(−1 − j + j − 1)
  = −1` (using `ik=−j, ki=j`). So `q_H ∘ q_H = (−1_quat)` with the
  phases summing to the sign that makes it `(−1_quat, π) ≡ +I`. Naive
  5-tuple equality fails `H∘H == I`; equality must be taken mod the ℤ₂
  (canonicalize, or compare the denoted matrices `e^{iφ}U(q)`).
- **NEVER merge +I with −I.** `(−1_quat, 0)` denotes `−I`, and it is
  identified only with `(+1_quat, π)` — *not* with `(+1_quat, 0) = I`.
  So `−I ≠ I`. `Ry(2π)`: `q = (cos π, 0, sin π, 0) = (−1,0,0,0) =
  −1_quat`, giving `Ry(2π) = −I ≠ I`. This is spinor 4π-periodicity
  (`Ry(4π) = +I`), it is physics, and `ctrl(−I)` is a real CZ-grade
  operation. A test asserting `Ry(2π) == I` is WRONG (PRD §4.1, §4.2).

## The double cover SU(2) → SO(3), and the Bloch/rotation action

`U(q)` and `U(−q)` are *distinct* SU(2)/U(2) elements (differ by −I),
but they induce the *same* rotation of the Bloch **vector** — the
conjugation action. The paper gives this action for pure quaternions
(Eqs. 5, 6, and Appendix p. 24): a Bloch-vector rotation of `v̂` about
axis `n̂` by angle θ is the sandwich

```
v̂'  =  exp(n̂ θ/2)  v̂  exp(−n̂ θ/2)          (Appendix, p. 24)
```

The half-angle `θ/2` and the `q`/`−q` sign freedom are precisely the
2-to-1 cover SU(2) → SO(3): both `±q` give the same SO(3) rotation.
This is the *observable* level (SO(3) = Bloch rotations, phase-blind);
the `U2` process value lives one level up at SU(2)×U(1)/ℤ₂ = U(2),
which retains the phase that SO(3) discards. Sturm keeps that phase on
purpose (PRD §4.1): `ctrl` promotes global phase to relative phase, so
the SU(2)/U(2) level — not the SO(3) level — is the correct home for a
process value under control (cf. Tang–Wright 2508.00055, PRD §4.2).

*(NOTE on Eqs. 5–6, p. 6: the paper's own pure-quaternion → Bloch-vector
map `f`, `q̂ = q̄ i q`, `f[q̂] = q̂_k x̂ − q̂_j ŷ + q̂_i ẑ`, carries the
SAME idiosyncratic `M_i` axis relabeling flagged above — `i→z, k→x,
−j→y`. Under the pinned standard convention the sandwich `q̄ (x σ⃗) q`
rotates the vector `(x,y,z)` with the identity axis labeling; use the
standard form, not Eqs. 5–6's relabeled `f`.)*

---

## Relevance to Sturm v2

1. **`U2` = 5 floats (unit quaternion + U(1) phase) is the correct data
   type for a U(2) process value** (PRD §4.1, milestone M1). The paper
   supplies the group isomorphism (unit quaternions ≅ SU(2)) that makes
   Hamilton-product composition exact and matrix-free — 16 real
   multiplies vs ~50 for a complex 2×2 product (PRD §4.1). Store
   `(w, x, y, z, φ)`.

2. **Pinned correspondence (adopt verbatim):** `U(q) = w·I − i(x σ_x +
   y σ_y + z σ_z) = [[w−iz, −y−ix],[y−ix, w+iz]]`, Hamilton product with
   `ij=k`, adjoint = conjugate. Gates: `X=i, Y=j, Z=k, H=(i+k)/√2` in
   the SU(2) part, each with a det-fixing phase `φ` (e.g. `X` carries
   `φ=π/2`). Do NOT use the paper's `M_i`/Table 1 axis labels
   (`X↔k, Z↔i`) — those are state-map artifacts (see warning).

3. **Equality is the ℤ₂ double-cover equality `(q,φ) ~ (−q,φ+π)`**
   (PRD §4.1, normative). Implement equality by canonicalization or by
   comparing denoted matrices `e^{iφ}U(q)` with `≈` on floats. Required
   law tests: `H ∘ H == I` (must pass — lands on `(−1_quat,π)`), and
   `Ry(2π) == −I ≠ I` (must distinguish — spinor periodicity). Do NOT
   "fix" `H²` by quotienting the global sign; that re-imports the
   condemned SU(2)-section disease at the equality predicate.

4. **Phase discipline.** Phases add under composition; the phase
   quotient is crossed once, at application (Ad, PRD §4.3), never by
   convention in library code. `U(q)` being always-det-1 is *why* the
   separate phase float exists — it is the U(2)/SU(2) coset label.

5. **Numerics.** Unit-norm drift is repaired by ONE scalar rescale
   `q ← q/|q|` (PRD §4.1) — cheaper and better-conditioned than
   re-orthogonalizing a drifting complex 2×2. Euler/ZYZ extraction (the
   θ≈0/π chart singularity) happens ONCE at the Orkan FFI boundary and
   only there; Hamilton composition is chart-free.

6. **What NOT to take from this paper.** Sections 3–5 (time reversal via
   left-multiplication, "second-order qubits", global-phase-as-hidden-
   variable, the broken `i`-symmetry) are foundational speculation with
   no bearing on Sturm. Left-multiplications by non-`exp(iθ)` quaternions
   are non-unitary (p. 8) and have no place in the `U2` algebra, which is
   pure U(2). Cite this paper ONLY for the textbook quaternion↔SU(2)
   identification of §2 and the Appendix.
