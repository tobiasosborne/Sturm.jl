# Sturm.jl-ixd Proposer A audit: QMod{5} Ry via Euler sandwich

Scope: d=5 only (d=4 deferred). Role: independent audit + TDD plan.

## §1 Algebraic sanity check of the Euler sandwich

Claim: `exp(-iδĴ_y)_j = Rz_j(π/2) · Ry_j(π/2) · Rz_j(δ) · Ry_j(-π/2) · Rz_j(-π/2)`.

At spin-1/2 with Pauli generators and Sturm's sign convention (`Ry(δ) = exp(-iδY/2)`,
`Rz(δ) = exp(-iδZ/2)`), the standard SU(2) Euler-frame identity is

    Rz(π/2) · Rx(δ) · Rz(-π/2) = Ry(δ)                (*)
    Rx(δ) = Ry(π/2) · Rz(δ) · Ry(-π/2)                 (**)

Substituting (**) into (*) gives `Ry(δ) = Rz(π/2)·Ry(π/2)·Rz(δ)·Ry(-π/2)·Rz(-π/2)` —
exactly the orchestrator's sandwich. Both (*) and (**) are sign-correct because in
Sturm's convention both rotations carry a `−i` half-angle exponent; the functor SU(2) →
U(2j+1) is a group homomorphism, so every identity in SU(2) lifts to every spin-j irrep.
Therefore the sandwich holds on the spin-2 irrep too.

**Numerical confirmation**: I reproduced the identity at j=2, δ=0.7, getting
`err = 6.7e-16` — consistent with the orchestrator's 4e-16 claim. The sandwich is
algebraically grounded (not a lucky fit) and matches at machine epsilon.

**Sign check against Sturm**: `_apply_spin_j_rotation!` (`src/types/qmod.jl:423`)
implements `:φ` as `apply_rz!(wires[i+1], δ · 2^i)` — this is the nrs factorisation of
`exp(-iδĴ_z)` on the Bartlett-deGuise-Sanders labelling `|s⟩ = |j, j-s⟩_z`. So the
sandwich's outer `Rz(±π/2)` reuse the already-shipped primitive verbatim. No sign
mismatch at the Julia boundary.

## §2 Givens angle spot-check

I verified the Givens list produces V5 (the 5x5 orthogonal `Ry_j(π/2)` block). Product
`G1 · G2 · … · G10` (left factor outermost, half-angle convention `c=cos(θ/2),
s=sin(θ/2)`) reconstructed `V5` to **err = 8.65e-9**, NOT the 3.3e-16 the orchestrator
claims. Every product order and embedding convention I tried gives the same 8.65e-9;
sign flips or no-half conventions give O(1) errors.

The angles agree with simple closed forms (e.g. first θ = `2·atan(1/2)` matches the
Julia `Float64` literal to the ULP), so this is **NOT** a printed-truncation bug.
Leading hypothesis: the orchestrator's 3.3e-16 was checked against a slightly different
reference `V5` (perhaps the product definition used to DERIVE the angles), not the
`expm(-iπ/2 · Ĵ_y)` reference.

**Spot check on first Givens (lo=3, θ = 2·atan(½))**: this angle gives `cos(θ/2) = 2/√5`,
`sin(θ/2) = 1/√5`, which is a known tangent-half angle appearing in the first column
elimination of the spin-2 raising/lowering ladder. The angle is *physically plausible*.

**Action required before implementation**: regenerate the Givens list from the V5
produced by `expm(-iπ/2·Ĵ_y)` directly, at full `Float64` precision (save as Julia
constants, not as string literals). 8.65e-9 × 10 composed Givens × 14 later primitives
could accumulate past the 1e-10 test criterion. This is the most concrete bug-class
finding of this audit.

## §3 Per-Givens circuit audit (k8u-style bug hunt)

I traced pair (0,1) H=1 and pair (3,4) H=3 on all 8 basis states.

**Pair (0,1), H=1**: bits (0,0,0) ↔ (1,0,0); diff = {bit 0}. Target = w1,
`ctrl_pattern = [(w2,0),(w3,0)]`. The circuit is one multi-CRy with two 0-controls
firing only when (w2=0, w3=0). In-subspace: acts as `I3 ⊕ Ry(θ)_{0,1} ⊕ I3` — correct.
Leakage |5⟩,|6⟩,|7⟩ all have at least one of {w2,w3}≠0 OR the pattern is |w1=0,w2=0,w3=0⟩
which is label 0 (not leakage). Leakage labels 5=(1,0,1), 6=(0,1,1), 7=(1,1,1) all have
w3=1, so control fails; CRy is identity. 

**Pair (3,4), H=3**: bits (1,1,0) ↔ (0,0,1); diff = {0,1,2}; pivot = bit 2 (w3).
Forward CX chain: `CX(w3→w1); CX(w3→w2)`. Under this chain, |3⟩=(1,1,0) stays
(w3=0 so no flips); |4⟩=(0,0,1) becomes (1,1,1). The pair is now (110)↔(111), differing
only in pivot. `b_lo_post[pivot] = 0`, so sign = +θ. Multi-CRy with ctrl `(w1=1,w2=1)`,
target w3. Uncompute CX chain restores (|3⟩,|4⟩). Leakage under forward CX:

    |5⟩=(1,0,1) → (0,1,1)  [w3=1 flips w1,w2]
    |6⟩=(0,1,1) → (1,0,1)
    |7⟩=(1,1,1) → (0,0,1)

All three have at least one of w1,w2 equal to 0 post-chain, so the CRy never fires.
Reverse CX chain restores each state exactly to its original leakage label. Leakage
closed under the construction.

**Sign polarity**: the orchestrator's rule `sign = −1 iff b_lo_post[pivot]=1` is
correct and matches the Ry basis-order convention (`Ry` on qubit rotates (|0⟩,|1⟩)
in that order; swapping lower/upper reverses the angle). No sign bug detected.

**Possible bug class not tested**: I did not check H=2 (pair (1,2)). Recommend
explicitly unit-testing the H=2 pair (bits (1,0,0) ↔ (0,1,0), pivot=bit 1, single-CX
`CX(w2→w1)`, then CRy on w2 with ctrl (w3=0)). This pair is where a pivot-selection
sign error most likely hides.

## §4 Global-phase / `when()` analysis

The sandwich equals `exp(-iδĴ_y)` up to a **δ-dependent** global phase α(δ). Under
`when(ctrl)` this becomes an observable **controlled** relative phase. Source of the
phase:

- Outer Rz(±π/2): the nrs factorisation drops the `exp(-iδj)` SU(d)/U(d) prefactor.
  At fixed ±π/2 this is a constant phase `exp(∓iπj/2)` per call — **these two cancel
  exactly** (product is 1). So the two outer Rz brackets contribute zero controlled
  phase under `when`.
- Inner Rz(δ): drops `exp(-iδj)` = `exp(-2iδ)` at j=2. This IS δ-dependent and IS
  observable under `when`.
- Ry(±π/2) fixed: these are δ-independent unitaries applied as qubit-level circuits.
  They contribute a **fixed** global phase from the CX-scratch/CRy composition, which
  under `when` becomes a fixed controlled phase `exp(iϕ_fixed)`.

So under `when(c) q.θ += δ` the circuit realises `exp(-iδĴ_y) · exp(iϕ_fixed) ·
exp(-2iδ)` with the relative (ctrl=1 vs ctrl=0) phase equal to `exp(iϕ_fixed) ·
exp(-2iδ)`. **Fixed part cancels between consecutive calls**; **δ-dependent part
accumulates and is observable**.

**Recommendation**: DOCUMENT and ACCEPT the δ-dependent controlled phase (consistent
with CLAUDE.md §8.4 policy: SU(d) convention, `when` lifts observe the raising/lowering
phase). Do NOT insert a correcting global-phase rotation — Sturm has no global-phase
primitive and adding one would violate Rule 11. If a user needs phase-clean controlled
Ry, they should compose `when(c) { q.φ += 2δ; q.θ += δ }` (i.e., pre-cancel the inner
Rz phase with an explicit φ-correction) — this should be a documented recipe, not a
hidden correction. Add a `_controlled_ry_j!` helper for this common case after ixd
lands.

## §5 TDD plan

Test file: extend `test/test_qmod.jl`. Naming per k8u pattern.

1. **d=5 Ry column 0 (acceptance criterion (a))**: `q.θ += π/4`, measure the
   statevector. Compare 5 in-subspace amplitudes to `[c⁴, 2c³s, √6 c²s², 2cs³, s⁴]` at
   c=cos(π/8), s=sin(π/8); tolerance 1e-10. **All signs positive** (NOT the bead's
   broken formula — use `exp(-iδĴ_y)` reference or the Wikipedia Wigner closed form).
2. **Leakage preservation**: same circuit, assert amplitudes at qubit basis indices
   5, 6, 7 are each < 1e-12.
3. **Subspace preservation under random sequences (c)**: 1000 random (axis,δ) pairs
   with axis∈{:θ,:φ}, δ∈Uniform(-π,π); after each, assert sum of in-subspace
   amplitudes² > 1 − 1e-10.
4. **Sandwich-composition identity**: two sequential `q.θ += δ1; q.θ += δ2` equals
   `q.θ += δ1+δ2` at tolerance 1e-10 (up to fixed global phase).
5. **Ry–Rz mixing**: sequence `q.θ += a; q.φ += b; q.θ += c` matches
   `exp(-icĴ_y)·exp(-ibĴ_z)·exp(-iaĴ_y)` (applied to |0⟩_d, take absolute values to
   ignore global phase) to 1e-10.
6. **Periodicity**: `q.θ += 2π` equals identity up to global phase (integer spin j=2).
   In-subspace amplitudes at `δ=2π` match `δ=0` to 1e-10.
7. **`when` composition**: `QBool(ctrl) ? q.θ += δ : I` — verify ctrl=0 branch has
   unchanged q, ctrl=1 branch has rotated q, superposition case entangles correctly.
   Tolerance 1e-10 on amplitudes.
8. **Int(q) measurement distribution**: prepare `q.θ += π/4`, measure 1000 times,
   compare empirical histogram to theoretical `|ψ_s|²` with χ² tolerance.
9. **d=4,6,7,8 still error loudly**: `@test_throws` with message pointing to the
   follow-on bead.
10. **H=2 Givens pair (1,2)**: explicit block-matrix unit test on the qubit circuit
    for pair (1,2) matching `I ⊕ G_{1,2}(θ) ⊕ I`. This is where polarity bugs hide.

## §6 Risks

- **Givens-angle precision (§2 finding)**: use exact `Float64` constants regenerated
  at full precision. Adopt as Julia `const V5_GIVENS = ((3, 2*atan(1,2)), …)` via
  closed-form expressions where available.
- `atan2` is correct across the full δ range (orchestrator already uses `atan(y,x)`).
- K=3, max shift `δ·2²=4δ`, no integer overflow.
- **Workspace ancilla under `when(outer)`**: the 2-control CRy allocates 1 ancilla.
  Inside `when(c_outer)` the stack has 3 controls, so `_multi_controlled_gate!`
  (`src/context/multi_control.jl:88`) allocates 2 ancillas. The allocate/deallocate
  pattern is `try…finally` — safe across exceptions. No known conflict, but worth a
  targeted test: `when(c_outer) q.θ += π/4` with assertion that qubit count before
  and after is equal.
- **Floating-point accumulation**: 44 primitive slots × √N gate noise ≈ 1e-14 end to
  end at double precision. Comfortable under the 1e-10 criterion *provided* §2's
  8.6e-9 issue is resolved.

## §7 Scope

Agree with splitting d=4 to a follow-on bead. csw critical path only needs d=5, and
d=4 has a simpler closed form (power-of-2 storage, no leakage subspace) that deserves
its own 3+1 round. Proposed follow-on bead description:

> "Sturm.jl-ixe: QMod{4} Ry via power-of-2 specialisation. K=2, no leakage subspace.
> Spin-3/2 irrep on 4 basis states; Bartlett Eq. 5 with j=3/2. Euler sandwich applies
> but simplifies because V4 decomposes into just 6 Givens (2+2+2 structure). No
> multi-controlled ancilla needed at d=4 since K=2. Gate count target: <20 primitives.
> Tests identical shape to ixd's but substituting d=4."

REVIEW COMPLETE

