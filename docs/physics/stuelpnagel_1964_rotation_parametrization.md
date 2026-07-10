# On the Parametrization of the Three-Dimensional Rotation Group

Source: John Stuelpnagel, "On the Parametrization of the
Three-Dimensional Rotation Group", *SIAM Review* **6**(4):422–430,
October 1964. DOI: [10.1137/1006093](https://doi.org/10.1137/1006093).
Research Institute for Advanced Studies (RIAS), Baltimore, MD.

Local PDF: `docs/physics/stuelpnagel_1964_rotation_parametrization.pdf`.
This is the **NASA reprint** (public domain — US Government work; the
research was supported in part by NASA Contract NASr-103, alongside
AFOSR and ONR). Obtained from the NASA Technical Reports collection via
the Internet Archive (item `nasa_techdoc_19640008534`, NTRS accession
19640008534); it is the identical text of the SIAM Review article. The
reprint carries its own internal pagination `-1-`…`-15-`; the SIAM
pagination is pp. 422–430. Citations below use the **reprint** page
numbers (as printed) plus section headings.

This is the canonical reference for the classical theorem that **SO(3)
admits no global singularity-free 3-parameter chart**, and for the
quaternion (Euler–Rodrigues) parametrization as the minimal
singularity-free representation. The result is elementary topology and
is reproduced in countless secondary sources; here the primary is in
hand.

## Notation (§2, p. -3-/-4-)

- `R` — the rotation group SO(3): real orthogonal 3×3 matrices with
  determinant 1. Stuelpnagel notes (intro, p. -3-) that Euler already
  showed in 1776 that this group is itself a 3-dimensional manifold.
- `U` — the unit quaternions, realized as 2×2 complex unitary matrices
  of determinant 1 (i.e. SU(2)). Every element has the form with
  coefficients `u₁,u₂,u₃,u₄` satisfying `Σ uᵢ² = 1`, so **`U` is
  topologically the unit 3-sphere `S³`**.
- The motivating problem is rigid-body attitude: integrate the matrix
  ODE `Ẋ(t) = Ω(t) X(t)`, `X(0) = I`, where `Ω(t)` is the (skew)
  angular-velocity operator. A parametrization is judged by parameter
  count, the form of the transformed ODE, numerical error
  susceptibility, and ease of recovering the output rotation.

## Theorem 1 — SO(3) is RP³, the 2-to-1 image of S³ (§3 "The topology of R", p. -4-)

Define `γ : U → R` by the explicit quadratic map `γ(u)`
(reprint p. -4-, the 3×3 matrix whose entries are quadratic forms in
`u₁…u₄`, e.g. the (1,1) entry `u₁² + u₂² − u₃² − u₄²`; this is exactly
the Euler–Rodrigues / quaternion-to-rotation formula). Then:

- `γ(u)` is orthogonal with determinant 1 for all `u ∈ U`;
- `γ(u)γ(v) = γ(uv)` — **`γ` is a continuous group homomorphism**;
- since `U` is compact and connected, `γ(U)` is a compact connected
  subgroup of `R`; the only such subgroups are `{I}`, the fixed-axis
  rotation groups, and `R` itself, and since `γ(U)` fixes no axis,
  **`γ(U) = R` (γ is onto)**;
- **`γ(u) = γ(v)` if and only if `u = −v`** — so `γ` is exactly
  **two-to-one**.

Consequently `R ≅ S³ / {±1}`: **SO(3) is topologically the 3-sphere
with antipodal points identified, i.e. real projective 3-space RP³.**
This is the double cover `SU(2) → SO(3)` stated as a topological fact.

## Theorem 2 — No global non-singular 3-parameter chart of SO(3) (§4, p. -5-)

This is the load-bearing result. Stuelpnagel proves it as an elementary
corollary of **Brouwer's invariance of domain** (stated §2, p. -4-,
after Hurewicz–Wallman: *if A and B are homeomorphic subsets of Euclidean
space Eⁿ and A is open, then B is open*):

> There is **no homeomorphism `h` of `R` into `E³`.**

*Proof (p. -5-, verbatim structure).* `R` is a compact 3-manifold, so
each point `r` has a neighborhood `Uᵣ` homeomorphic to an open subset of
`E³`. If a homeomorphism `h : R → E³` existed, then each `h(Uᵣ)` would be
open in `E³` by Brouwer's theorem, so `h(R) = ⋃ᵣ h(Uᵣ)` would be open.
But `R` is compact, so `h(R)` is compact (continuous image of a compact
space). **No Euclidean space contains a non-empty open compact subset**,
a contradiction. ∎

Restated in the Conclusion (§7, p. -14-/-15-): *"no 3-dimensional
parametrization can be both global and nonsingular. If the
parametrization is global … then there must be points where the
parameter values are not uniquely defined, and in this case the
derivatives of the parameters are … not defined, so the transformed
differential equations become singular at these points, that is, the
derivatives become infinite."* Every global 3-parameter chart therefore
has a singular set on which the attitude ODE blows up.

## Theorem 3 — Minimal embedding dimension is five (§3–§4, pp. -4- to -6-)

Stuelpnagel records the sharper facts (attributing the E⁴ result to
H. Hopf, 1940, ref. [1], via the homology ring of projective 3-space):

- `R` **cannot** be embedded topologically in `E⁴` (Hopf 1940);
- `R` **can** be embedded in `E⁵` (Hopf); Stuelpnagel gives an explicit
  5-parameter embedding (§4, p. -6-) by stereographic projection of the
  6-parameter "first-two-columns" chart `M ⊂ S⁵ ⊂ E⁶`;
- hence **five is the least number of parameters admitting a 1-1 global
  (homeomorphic) representation** of the rotation group.

So the parameter-count ladder is: 3 = manifold dimension but **never
global+nonsingular** (Thm 2); 4 = quaternions, global and nonsingular
but **2-to-1** (Thm 1); 5 = minimal **1-to-1 global nonsingular**;
6 = the simplest explicit 1-to-1 global chart (first two columns).

## The quaternion method (§5, pp. -8- to -10-)

Using the 2-to-1 map `γ` of Thm 1 (four parameters, one redundant), the
rigid-body ODE `Ẋ = ΩX` on `R` **lifts to a linear ODE `u̇ = σ(t) u`
on `U`** (`σ ∈ 𝔰𝔲(2)`), with `γ(u(t)) = X(t)`. Key verdict (p. -9-,
emphasis Stuelpnagel's): *"the original linear equation is transformed
into a linear equation; this was not the case with the [5-dimensional]
method, so this method is obviously far superior."* The failure of `γ`
to be 1-1 *"causes no difficulty, since γ is a local homeomorphism."*
He also notes (§5, p. -9-/-10-) that **three parameters cannot** deliver
a singularity-free local homeomorphism: that would force the parameter
set to be a covering space of `R`, and `S³` (needing ≥ 4 parameters) is
the only covering space of `R` besides `R` itself.

## The three common 3-parameter charts and how each fails (§6, pp. -10- to -13-)

Each is global-but-singular, exactly as Thm 2 forces:

1. **Euler angles** (§6, p. -11-): factor `X` into rotations about
   three body axes. The coefficient matrix of the transformed ODE has
   **determinant `cos θ`** (in Stuelpnagel's roll/pitch/yaw convention,
   `φ, θ, ψ`), so the chart is **singular at `θ = ±π/2`** — the angles
   are not uniquely determined and their derivatives blow up. *(The
   exact location of the degenerate set depends on the Euler convention:
   for the ZYZ convention Sturm uses, the singularity sits at the second
   angle `θ = 0` or `θ = π` — the poles / gimbal lock. The
   **existence** of such a set is convention-independent and is the
   content of Thm 2; only its **coordinates** move with the convention.)*
2. **Exponential / skew-symmetric ("rotation vector")** chart (§6,
   p. -11-/-12-): every rotation is `exp S` for skew-symmetric `S`; the
   transformed ODE has a **pole at rotation angle `σ = 2π`**, "just as we
   would expect from the nature of the map."
3. **Cayley** chart, `X = (I − S)(I + S)⁻¹` (§6, p. -12-/-13-): yields a
   **well-defined, non-singular** differential equation, but **cannot
   represent any rotation of trace −1** — i.e. it **omits all 180°
   rotations** ("will not even allow 180° rotations about a fixed axis").
   It trades the singularity for a hole in the range: still not a global
   nonsingular chart of *all* of SO(3).

## Conclusion of the paper (§7, pp. -14- to -15-)

Citing Robinson (WADC TR 58-17, ref. [3]), Stuelpnagel endorses the
**quaternion method as best for unrestricted rotations**: it gives
linear transformed equations using only one redundant parameter and
represents the most general motion; its only cost is a final `γ` map to
recover the rotation after integrating. Euler angles remain useful only
for their direct roll/pitch/yaw readout. And, restated once more: **no
3-parameter parametrization is simultaneously global and nonsingular.**

## Relevance to Sturm v2

This paper is the physics/topology ground under two M1/M2 kernel
decisions (PRD-v2 §4.1 "Process values", D7 "Orkan interface"):

1. **Why the kernel's persistent 1q process value is a quaternion, not
   an Euler triple.** Thm 2 is a *topological* obstruction, not a
   numerical nuisance: there is provably no smooth global 3-parameter
   chart of SO(3), and the same obstruction lifts immediately to
   SU(2) = `U` (its double cover, Thm 1). Any three-angle (ZYZ) chart
   therefore *must* carry a coordinate singularity — the θ≈0/π gimbal
   degeneracy where `det = cos θ` (or the convention-shifted analogue)
   vanishes and angle extraction is ill-conditioned. PRD-v2 §4.1 cites
   exactly this: *"the θ≈0/π coordinate singularity of any three-angle
   chart (cf. Stuelpnagel 1964 — a topological fact about SO(3),
   extending immediately to SU(2); not a convention choice) is confined
   to that single extraction site, while composition itself stays
   chart-free."* Storing `U2` as unit quaternion + phase keeps
   composition on the smooth 4-parameter cover (`S³`, Hamilton product,
   exact and matrix-free), where **no singularity exists**.

2. **Why ZYZ extraction is confined to exactly one place — the Orkan
   FFI boundary (D7).** Because the singularity is unavoidable in *any*
   3-angle chart but *absent* from the quaternion representation, the
   only place it can appear is the one site that must convert to a
   3-angle form for an external consumer. PRD-v2 D7 fixes that site at
   the Orkan `ccall` boundary (Euler ZYZ triple vs general 1q-unitary
   entry point): *"the ZYZ chart singularity at θ≈0/π lives at this
   boundary and only here."* Thm 2 is the reason there is a "here" at
   all — the branch cannot be designed away, only quarantined to a
   single, tested extraction function.

3. **The double cover is physics, and the sign is real (Thm 1).**
   `γ(u) = γ(v) ⇔ u = −v` is precisely the 2-to-1 structure that
   PRD-v2 §4.1 encodes as **double-cover equality**: `(q, φ) ~ (−q,
   φ+π)`. Stuelpnagel's `γ` is the group homomorphism whose non-1-1-ness
   is the whole point — it must *not* be quotiented away at the equality
   predicate, because `Ry(2π) = −I ≠ I` (spinor 4π-periodicity) and
   `ctrl(−I)` is a real CZ-grade operation. The kernel lives on the
   `S³` cover (like `U`), crosses to SO(3)/U(2) only at application, and
   never merges `+I` with `−I`. This paper is the classical statement
   that the two-sheeted cover is a genuine topological feature of the
   rotation group, not a representational artifact.

Caveat / scope: Stuelpnagel works in SO(3) and its ODE integration; the
lift to SU(2)/U(2) and the phase quotient are Sturm's (§4.1) — the paper
supplies the topology (no global 3-chart; 2-to-1 quaternion cover; RP³),
not the U(2)-with-explicit-phase construction. Euler-angle singularity
*coordinates* in §6 are stated in Stuelpnagel's roll/pitch/yaw
convention; Sturm's ZYZ convention relocates the degenerate set to
θ≈0/π, but Thm 2 guarantees a degenerate set exists in every case.
