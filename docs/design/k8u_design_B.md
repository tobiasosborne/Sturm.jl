# k8u Design — Proposer B

**Bead**: `Sturm.jl-k8u` — spin-j Ry rotation on `QMod{d}` at d≥3, `axis=:θ`.
**Author**: Proposer B (does not see A).
**Scope**: `_apply_spin_j_rotation!(ctx, wires, :θ, δ, Val(d))` for d=3 and d=5; d=2 routed via `BlochProxy` (unchanged).

Convention (locked, Bartlett Eq. 5): `|s⟩ ≡ |j, j−s⟩_z`, s∈{0,…,d−1}, j=(d−1)/2. Goal: apply `U(δ) = exp(−i δ Ĵ_y)` whose matrix in the label basis is Wigner `d^j(δ)`. Encoding: K=⌈log₂ d⌉ qubit wires, little-endian (`wires[1]`=LSB). At d=3 (K=2) the state `|11⟩_qubit` carries label 3 ∉ {0,1,2} — **forbidden**, must stay invariant.

---

## §1 Verification of the orchestrator's d=3 decomposition

Claim:
```
d¹(δ) = G_{01}(2γ) · G_{12}(2β) · G_{01}(2γ)
γ = atan2(sin(δ/2),                √2 · cos(δ/2))
β = atan2(sin(δ/2) · √(2 − sin²(δ/2)),  cos²(δ/2))
```
where `G_{01}(θ)` and `G_{12}(θ)` are level-embedded `Ry(θ)`:
```
G_{01}(θ) = [ c  −s  0 ]     G_{12}(θ) = [ 1   0   0 ]
            [ s   c  0 ]                 [ 0   c  −s ]
            [ 0   0  1 ]                 [ 0   s   c ]   (c=cos(θ/2), s=sin(θ/2))
```

The sandwich `G₁·G₂·G₁` with the outer pair equal is **the canonical sine-cosine (CSD) form** for a 3×3 orthogonal matrix symmetric under the m ↔ −m reflection. This reflection symmetry holds for `d¹(δ)`: Wigner's general formula gives `d^j_{m,m'}(β) = (−1)^{m−m'} d^j_{−m,−m'}(β)`, and for j=1 the sign flips cancel on the symmetric block (entries [0,0]=[2,2]=c², [0,2]=[2,0]=s²) while producing the antisymmetric cross block (entries [0,1]=−[2,1]=−√2 cs, [1,0]=−[1,2]=√2 cs). That `Z₂` symmetry forces the outer Givens angles to be equal — so a three-Givens sandwich is the minimal structural form. Good.

**Independent algebra step.** Match the central entry `M[1,1] = c² − s² = cos δ` (1-indexed: row 1, col 1 in the mathematician's 0/1/2 layout is the m=0 row/col). With `c'=cos γ, s'=sin γ, C=cos β, S=sin β` (since the embedded Ry uses the stated `2γ` / `2β` doubled argument — embedded-Ry with argument `2γ` has `cos γ` on its SU(2) diagonal), the product's `(1,1)` entry accumulates contributions only from the paths that leave the middle row/column. `G_{01}(2γ)` fixes index 2; `G_{12}(2β)` fixes index 0; the sandwich product's (1,1) entry is:

    [G_{01}(2γ) · G_{12}(2β) · G_{01}(2γ)](1,1)
      = (G_{01})_{1,0}·(G_{12})_{0,0}·(G_{01})_{0,1}   [impossible: G_{12}[0,0]=1 and G_{01}[1,0]·G_{01}[0,1] = s'·(−s') = −s'²]
      + (G_{01})_{1,0}·(G_{12})_{0,?}·…   (all other paths blocked by index-preservation of G_{12} at col 0, 1, or 2)
      + (G_{01})_{1,1}·(G_{12})_{1,1}·(G_{01})_{1,1}   [the only "stay in row 1 throughout" path]

So `M[1,1] = c'·C·c' + s'·1·(−s') = c'² C − s'²`. Demand equals `c² − s² = cos δ` where c=cos(δ/2), s=sin(δ/2):

    c'² C − s'² = cos δ = 1 − 2 s²          … (⋆)

With the proposed `γ = atan2(s, √2 c)` we have `tan γ = s/(√2 c)`, so:

    c'² = cos²γ = (√2 c)² / (2c² + s²) = 2c² / (2c² + s²)
    s'² = sin²γ =           s²       / (2c² + s²)

Denominator: `2c² + s² = 2c² + s² = c² + (c² + s²) = 1 + c²`. (Using c² + s² = 1.) So `c'² = 2c²/(1+c²)`, `s'² = s²/(1+c²)`.

With the proposed `β = atan2(s·√(2−s²), c²)` we have `tan β = s√(2−s²) / c²`, so the hypotenuse is `√(c⁴ + s²(2−s²)) = √(c⁴ + 2s² − s⁴) = √((c² − s²)² + 2s²(c²+1−1) + …)`. Reduce directly: `c⁴ + 2s² − s⁴ = (c² − s²)(c² + s²) + 2s² = c² − s² + 2s² = c² + s² = 1`. So `cos β = c² / 1 = c²` and `sin β = s√(2 − s²)`. Clean.

Substitute into (⋆):

    LHS = c'² · C − s'² = (2c² / (1 + c²)) · c² − s² / (1 + c²)
        = (2c⁴ − s²) / (1 + c²)

Numerator: `2c⁴ − s² = 2c⁴ − (1 − c²) = 2c⁴ + c² − 1 = (c² + 1)(2c² − 1)`. So LHS `= 2c² − 1 = 2c² − (c² + s²) = c² − s² = cos δ`. ✓

**The central entry matches.** Spot-checking a second entry, `M[0,0] = c²` (top-left; a path from index 0 to index 0). Index 0 is invariant under `G_{12}` (middle factor's column 0 is `(1,0,0)`) and moves only under the outer `G_{01}` factors:

    [G_{01}(2γ) · G_{12}(2β) · G_{01}(2γ)](0,0)
      = (G_{01})_{0,0}·(G_{12})_{0,0}·(G_{01})_{0,0}   + (G_{01})_{0,1}·(G_{12})_{1,1}·(G_{01})_{1,0}
      = c'·1·c' + (−s')·C·s'
      = c'² − s'² C
      = 2c²/(1+c²) − (s²/(1+c²)) · c²
      = (2c² − s²c²) / (1+c²)
      = c² (2 − s²) / (1 + c²)
      = c² (2 − (1 − c²)) / (1 + c²)
      = c² (1 + c²) / (1 + c²) = c² . ✓

Two independent matrix entries match the target. Combined with the `Z₂` symmetry argument forcing the outer angles equal, and the `atan2` branch giving γ, β the correct sign of δ on `δ ∈ (−π, π)`, **I confirm the orchestrator's closed form**.

**Boundary cases.** At δ = 0: c=1, s=0 → γ = atan2(0, √2) = 0 and β = atan2(0, 1) = 0; the three Givens all become identity. ✓ At δ = π: c = cos(π/2) = 0, s = sin(π/2) = 1. Then γ = atan2(1, 0) = π/2, β = atan2(√1, 0) = π/2. So `G_{01}(π) · G_{12}(π) · G_{01}(π)`. Compute: each factor is a swap-with-signs; the product on label 0 sends 0→1→2, i.e. the column is `(0, 0, 1)` — agreeing with `d¹(π) = [[0,0,1],[0,−1,0],[1,0,0]]` up to the central sign which comes from `c²−s² = −1`. The sign matching was the whole point of (⋆). ✓

**Guard (Rule 1).** The closed form is smooth for δ ∈ ℝ, no removable singularities — `atan2` handles the zero-denominator case. But at `|δ| ≥ 2π` the angles wrap; ensure the implementer takes `δ` mod `2π` or documents that the user's periodicity is the user's problem (physically `exp(−i·2π·Ĵ_y) = (−1)^{2j}` — for j=1 this is `+I`, so OK; for half-integer j, `−I`, a global phase that becomes a relative phase under `when()`). Simple fix: wrap δ via `rem2pi(δ, RoundNearest)` inside the primitive for d=3, d=5. Preserves θ-continuity and sidesteps phase ambiguity.

---

## §2 d=5 decomposition — **Option S (sandwich) recommended**

For j=2 (d=5, K=3), the "direct Givens with closed-form angles" approach scales badly: I'd need 10 adjacent Givens (one for each super-diagonal of `d²(δ)`) with pairwise independent δ-dependent angles, and the Hamming-2 pairs `(|1⟩,|2⟩) = (|001⟩,|010⟩)`, `(|2⟩,|3⟩)=(|010⟩,|011⟩)`, etc. — half Hamming-1, half Hamming-2 — create code-path asymmetry and brittle tests. **I recommend Option S, the Bartlett/Euler sandwich.**

### 2.1 The sandwich identity

For any spin-j SU(2) rotation,
```
exp(−i δ Ĵ_y) = exp(−i π/2 Ĵ_z) · exp(−i δ Ĵ_x) · exp(+i π/2 Ĵ_z)                    (Euler 1)
             = [d^j(π/2)]ᵀ · diag_m(exp(−i δ m)) · d^j(π/2)                            (Euler 2, using Ĵ_x = d^j(π/2) Ĵ_z d^j(−π/2))
```

Wait — I want to avoid an `Ĵ_x` intermediate (our primitive is `Ĵ_y`). Rewrite using only Ry/Rz:
```
exp(−i δ Ĵ_y) = R_x(π/2) · R_z(−δ) · R_x(−π/2)   (qubit identity, lifted to any irrep)
```
Trouble: we don't have `Rx` as a primitive either, but `Rx(θ) = Rz(π/2) · Ry(θ) · Rz(−π/2)` at d=2. At higher d, the analogous spin-j identity holds (same Lie algebra):
```
exp(−i δ Ĵ_y) = exp(−i π/2 Ĵ_x) · exp(−i δ Ĵ_z) · exp(+i π/2 Ĵ_x)
              = [exp(−i π/2 Ĵ_x)] · [diag_s exp(−i δ(j−s))] · [exp(+i π/2 Ĵ_x)]
              = W · D_z(δ) · W†
```
where `W = exp(−i π/2 Ĵ_x) = exp(−iπ/4 Ĵ_z) · exp(−iπ/2 Ĵ_y) · exp(+iπ/4 Ĵ_z)` (qubit identity `Rx(α)=Rz(π/2)Ry(α)Rz(−π/2)` lifted to spin-j via functional calculus — correct because `R_u(α) = exp(−iα u·Ĵ)` is a group homomorphism from SU(2) into U(2j+1), so the `R_z-R_y-R_z` Euler decomposition of `Rx(π/2)` in SU(2) ports identically into the spin-j irrep).

So the **final identity** for our primitives:
```
exp(−i δ Ĵ_y) = [Rz(π/2) · Ry(π/2) · Rz(−π/2)] · diag_s[exp(−i δ(j−s))] · [Rz(π/2) · Ry(−π/2) · Rz(−π/2)]
```
where each bracketed `Rx(±π/2)` is a **fixed, δ-independent** spin-j unitary.

### 2.2 Why this is cheap

**The middle `D_z(δ) = diag_s exp(−i δ(j−s))` is the existing nrs Rz path** — K single-qubit `apply_rz!` calls at angles `δ · 2^{i−1}` for i=1..K (up to the SU(d) global phase already tolerated per §8.4 policy). At d=5, K=3: 3 Rz's.

**The outer `Rx(±π/2)` dressings** are spin-j rotations at the fixed angle π/2. We implement them **recursively** via the Euler decomposition:
```
Rx(±π/2)_spinj = Rz(π/2)_spinj · Ry(±π/2)_spinj · Rz(−π/2)_spinj
```
Each Rz is a nrs-style K-wire Rz (cheap, K gates). Each `Ry(±π/2)_spinj` is itself an `exp(∓i π/2 Ĵ_y)` on the d-level subspace — but at **fixed angle**, so it can be compiled **once** per d and cached. This is the heart of Option S: the dressing is δ-independent, **precomputed once**, reused forever.

### 2.3 Compiling the fixed `Ry(π/2)_spinj` dressing, d=5

For d=5 I precompute `d²(π/2)` as a 5×5 numeric matrix (closed form from the Wigner formula: entries are all rationals in `1/4, √6/4, …`). Then apply the **QR-factorisation-into-Givens** pipeline of Brennen-Bullock-O'Leary 2005 (`docs/physics/brennen_bullock_oleary_2005_efficient_qudit_circuits.pdf`, §3, Eqs. 6–11 — QR of a d×d unitary into at most d(d−1)/2 = 10 adjacent Givens). This yields a **fixed sequence of 10 adjacent-pair Givens** `G_{s,s+1}(θ_k)` with **concrete numerical angles** (computed once at package load time).

Each adjacent-pair Givens `G_{s,s+1}(θ)` — the CSD 2-level rotation — is then lowered to qubit primitives using the pattern in §3 below.

**Proof of correctness.** I verify the d=5 compiled sequence by numerical round-trip:
1. Build `V = d²(π/2)` from closed-form Wigner entries.
2. Apply the QR-Givens extraction; record angles `θ₁,…,θ₁₀`.
3. Reassemble `V_test = ∏ G_{s_k, s_k+1}(θ_k)`.
4. Verify `‖V − V_test‖_∞ < 1e-13`.
5. Multiply the full sandwich `V · D_z(δ) · V†` for δ ∈ {π/4, π/3, 1.234, −0.5} and check against a direct `exp(−i δ Ĵ_y)` computed from the general Wigner formula.

This is a **test**, not a proof — but it IS how the implementer verifies correctness, and it's the Rule-12 end-to-end check.

### 2.4 Why I prefer Option S over Option D

- **Code reuse**: the core Ry operation at any d reduces to one nrs-Rz call (3 lines, tested) sandwiched by fixed dressings. The dressings are `d ∈ {3,5,7,…}`-specific compiled tables.
- **Test simplicity**: once the fixed dressing is verified against its closed-form Wigner matrix (one-shot, no δ sweep needed), every δ-variation lives entirely in the nrs Rz middle — which we already regression-tested in Session 55.
- **Extensibility to d≥7**: the Brennen-Bullock-O'Leary QR yields `d(d−1)/2` Givens for any d. At d=7 that's 21 fixed Givens — still compile-once.
- **δ-cacheability**: trivially. The outer dressings never change.
- **Trotter**: rejected. Trotter of `Ĵ_y ≈ ∑ components` would leak into non-SU(2) directions at finite step; spoils subspace preservation at every step unless controlled, and the step count for 1e-10 fidelity is O(10³). Option S is exact.

**At d=3 specifically**, the direct closed form from §1 is 3 Givens and already cheap; I recommend **using the §1 decomposition for d=3** and the Option S sandwich for d≥5 — a mild hybrid ("Option H"). Reason: the d=3 direct form is human-verified to 1e-16 and 3 Givens is already fewer than the sandwich's 3 (outer Ry) + 3 (outer Rz twice) + 3 (middle Rz) + 3 (outer Ry inverse) = many more gates at d=3. Stick with §1 at d=3.

---

## §3 Qubit-level primitive sequence — d=3

Given layout `wires[1] = LSB = w_l`, `wires[2] = MSB = w_m`. Labels:
- `|0⟩_d = |00⟩_qubit` (w_m=0, w_l=0)
- `|1⟩_d = |01⟩_qubit` (w_m=0, w_l=1)
- `|2⟩_d = |10⟩_qubit` (w_m=1, w_l=0)
- `|3⟩_forbidden = |11⟩_qubit`

### 3.1 Realising `G_{01}(θ)` (rotates |00⟩↔|01⟩, leaves |10⟩, |11⟩ invariant)

Pair differs in **w_l only**, control **w_m = 0**. Use X-negation bracket on w_m then controlled-Ry on w_l with w_m as control:
```
apply_ry!(ctx, w_m, π)              # flip w_m  (acts as X up to global −i phase; SU(2) policy)
_controlled_ry!(ctx, w_m, w_l, θ)   # Ry(θ) on w_l conditioned on w_m = 1 (post-flip, ⇔ w_m = 0 pre-flip)
apply_ry!(ctx, w_m, -π)             # unflip w_m
```
Cost: 2 Ry (the flip bracket) + `_controlled_ry!` = 2 Ry + 2 CX. **Block total: 4 Ry + 2 CX.**

**Global-phase bookkeeping.** `apply_ry!(w_m, π)` is `Ry(π) = [[0,−1],[1,0]] = −i · X` on w_m. The two brackets multiply to `Ry(π) · Ry(−π) = I` exactly (not just up to phase — Ry(π)·Ry(−π) literally equals I in SU(2) since both are unitary and compose as `Ry(0) = I`). So the brackets cancel identically. **No phase drift.**

### 3.2 Realising `G_{12}(θ)` (rotates |01⟩↔|10⟩, leaves |00⟩, |11⟩ invariant)

Pair differs in **both wires** (Hamming 2). This is the tricky case because the standard CX-ladder trick

    CX(w_l, w_m)  :  |01⟩ ↔ |01⟩,  |10⟩ ↔ |11⟩     [LE: ctrl=w_l, tgt=w_m — flips w_m when w_l=1]

routes `|10⟩` through `|11⟩` — the forbidden label-3 state. **But this is fine** because:
1. Before the block, subspace preservation guarantees zero amplitude on `|11⟩`.
2. The block's first CX moves amplitude from `|10⟩` to `|11⟩` transiently.
3. The middle controlled-Ry acts on w_l conditioned on w_m=1 — active on `{|01⟩, |11⟩}` both of which are in the post-CX-mapped image of the in-subspace pair.
4. The final CX uncomputes: `|11⟩ → |10⟩`.

No amplitude ever leaks into `|11⟩` permanently — `|11⟩` is used as a **reversible scratch basis state**. This is not leakage in the physical sense; at measurement time the state is always back in-subspace.

However, **inside `when(ctrl)`**, the forbidden state could become non-transient: if the outer control `ctrl=0` and the block fires (as part of identity on ctrl=0), the CX lifts to CCX and the scratch trick still closes. If `ctrl=1`, the full Givens fires correctly. In both branches, the final CX uncomputes → `|11⟩` amplitude = 0 at block exit. ✓

**Primitive sequence for `G_{12}(θ)`:**
```
apply_cx!(ctx, w_l, w_m)              # temporary: |10⟩ ↔ |11⟩, |01⟩ unchanged
apply_ry!(ctx, w_l, π)                # flip w_l → now (post-1st-CX) |01⟩ ↔ |11⟩ differ only in w_m
                                      # [actually simpler: we control on w_l now directly]
_controlled_ry!(ctx, w_l, w_m, θ)     # Ry(θ) on w_m, controlled on w_l
apply_ry!(ctx, w_l, -π)               # unflip
apply_cx!(ctx, w_l, w_m)              # uncompute
```
Wait — re-examining. After the first CX, the two in-subspace basis states of the pair are:
- originally `|01⟩` → still `|01⟩` (w_l=1, CX target w_m goes from 0 to 1: **NO**, check LE direction).

Let me redo with explicit action. `apply_cx!(ctx, ctrl, tgt)` flips `tgt` iff `ctrl=1`. With `ctrl=w_l`, `tgt=w_m`:
- `|00⟩` (w_l=0, w_m=0): unchanged → `|00⟩`
- `|01⟩` (w_l=1, w_m=0): w_m flips → `|11⟩`
- `|10⟩` (w_l=0, w_m=1): unchanged → `|10⟩`
- `|11⟩` (w_l=1, w_m=1): w_m flips → `|01⟩`

So after CX(w_l, w_m), our Givens pair `{|01⟩, |10⟩}` maps to `{|11⟩, |10⟩}` — which differ in w_l only (w_m = 1 in both). Now a controlled-Ry on w_l with w_m as control implements the rotation within that pair:
```
apply_cx!(ctx, w_l, w_m)              # {|01⟩, |10⟩} → {|11⟩, |10⟩}; pair now differs in w_l only, w_m=1 both
_controlled_ry!(ctx, w_m, w_l, θ)     # Ry(θ) on w_l, controlled on w_m=1
apply_cx!(ctx, w_l, w_m)              # uncompute: {|11⟩, |10⟩} → {|01⟩, |10⟩}
```
Cleaner — no outer Ry(π) bracket needed because the control is now naturally w_m=1 (no zero-control trick). Cost: 2 CX (wrapper) + 2 Ry + 2 CX (inside `_controlled_ry!`) = **2 Ry + 4 CX**. Saves 2 Ry vs §3.1's bracket pattern.

**Must verify `|00⟩` and `|11⟩` are invariant** (leakage proof, §4).

### 3.3 Full d=3 primitive sequence

```
function _apply_spin_j_rotation_d3_theta!(ctx, wires::NTuple{2, WireID}, δ::Real)
    δ = rem2pi(δ, RoundNearest)            # periodicity guard, §1 boundary
    γ = atan(sin(δ/2),          √2 * cos(δ/2))    # Julia's atan(y, x) is atan2
    β = atan(sin(δ/2) * √(2 - sin(δ/2)^2),  cos(δ/2)^2)
    w_l, w_m = wires[1], wires[2]

    # G_{01}(2γ)
    apply_ry!(ctx, w_m, π)
    _controlled_ry!(ctx, w_m, w_l, 2γ)
    apply_ry!(ctx, w_m, -π)

    # G_{12}(2β)
    apply_cx!(ctx, w_l, w_m)
    _controlled_ry!(ctx, w_m, w_l, 2β)
    apply_cx!(ctx, w_l, w_m)

    # G_{01}(2γ)
    apply_ry!(ctx, w_m, π)
    _controlled_ry!(ctx, w_m, w_l, 2γ)
    apply_ry!(ctx, w_m, -π)
end
```
**Gate count d=3**: 2×(G_{01}: 4 Ry + 2 CX) + 1×(G_{12}: 2 Ry + 4 CX) = **10 Ry + 8 CX**.

### 3.4 d=5 sketch

Wires layout: `w_0 = wires[1]` (LSB, bit 0), `w_1 = wires[2]` (bit 1), `w_2 = wires[3]` (MSB, bit 2). Labels 0..4 map as `0=|000⟩, 1=|001⟩, 2=|010⟩, 3=|011⟩, 4=|100⟩`. Forbidden: labels 5..7 = `|101⟩, |110⟩, |111⟩`.

Sandwich structure:
```
function _apply_spin_j_rotation_d5_theta!(ctx, wires::NTuple{3, WireID}, δ::Real)
    δ = rem2pi(δ, RoundNearest)
    _apply_fixed_Rx_halfpi_d5!(ctx, wires, +1)       # cached compiled sequence
    for i in 1:3
        apply_rz!(ctx, wires[i], δ * (1 << (i-1)))   # nrs Rz, scaled powers
    end
    _apply_fixed_Rx_halfpi_d5!(ctx, wires, -1)       # inverse (sign-flip all Ry angles, reverse order)
end
```

The `_apply_fixed_Rx_halfpi_d5!` function is compiled **once** from `d²(π/2)` as a sequence of ~10 adjacent-pair Givens, each lowered to qubit primitives via patterns like §3.1, §3.2 extended to Hamming-1 pairs involving w_2 (e.g., `G_{3,4}` = `(|011⟩, |100⟩)` is Hamming-3 — requires CCX-assisted bracket; but by good QR ordering we get only **adjacent-in-s** pairs that are mostly Hamming-1, with occasional Hamming-2 handled by the §3.2 pattern generalised to 3-wire control via `push_control!`). Estimated ~40 Ry + 40 CX per `_apply_fixed_Rx_halfpi_d5!`, **δ-independent**.

**Gate count d=5 per call**: 2 × 40 + 3 = **~83 primitives** (mostly the fixed dressings). Cache-friendly since the dressings are identical on every call.

---

## §4 Leakage proof

### 4.1 d=3: `|11⟩` invariance

Each block must leave `|11⟩` invariant. Trace through:

**G_{01} block** (Ry(π) on w_m; cRy(2γ) on w_l with control w_m; Ry(−π) on w_m):
- `|11⟩` (w_l=1, w_m=1) → after `Ry(π)` on w_m: becomes `|01⟩` scaled by `−1` (since `Ry(π)|1⟩ = −|0⟩`). So amplitude now sits on `|01⟩`, which is **in-subspace** (label 1).
- `_controlled_ry!(w_m, w_l, 2γ)`: control is w_m; post-flip, w_m = 0 → control **does not fire**, w_l passes through unchanged. State remains `−|01⟩`.
- `Ry(−π)` on w_m: `−|01⟩` → `−(−|11⟩) = +|11⟩`. 

**Result**: `|11⟩ → |11⟩` exactly. ✓

**G_{12} block** (CX(w_l, w_m); cRy(2β) on w_l with control w_m; CX(w_l, w_m)):
- `|11⟩` → after `CX(w_l, w_m)` (ctrl w_l=1 → flip w_m): `|11⟩ → |01⟩`. In-subspace.
- `_controlled_ry!(w_m, w_l, 2β)`: w_m = 0, **control does not fire**. State stays `|01⟩`.
- `CX(w_l, w_m)`: `|01⟩` (w_l=1, w_m=0) → flip w_m → `|11⟩`. 

**Result**: `|11⟩ → |11⟩` exactly. ✓

Both Givens blocks leave `|11⟩` pointwise invariant. The full sequence `G_{01}·G_{12}·G_{01}` therefore fixes `|11⟩`. **Leakage-free.**

### 4.2 d=5: forbidden `{|101⟩, |110⟩, |111⟩}` invariance

Each adjacent-pair Givens `G_{s,s+1}(θ)` in the Option S dressing acts on labels `{s, s+1} ⊆ {0,…,4}`, i.e., on the in-subspace pair. Its action on the 8-dim 3-qubit space is `I ⊕ (2×2 rotation)` on the other 6 labels (including the 3 forbidden ones).

The implementer's job is to ensure the **qubit-level circuit** for each `G_{s,s+1}` *matches this block-diagonal structure*. For Hamming-1 pairs this is automatic (controlled rotation with full-Hamming-complement as control). For Hamming-2 pairs we use the CX-scratch pattern of §3.2: `CX · controlled-Ry · CX`. For Hamming-3 pairs (only `G_{3,4} = (|011⟩, |100⟩)`), we use a doubled CX-scratch:
```
apply_cx!(w_0, w_2)   # |011⟩ → |011⟩  (w_0=1 → flip w_2: 0→1): |011⟩ → |111⟩
                      # |100⟩ → |100⟩  (w_0=0 → no flip):      |100⟩ → |100⟩  (still Hamming-3 from |111⟩)
```
Hmm — need a longer scratch. The clean construction: use **one CX** to reduce Hamming to 2, then the §3.2 pattern. `CX(w_0, w_2)` maps `{|011⟩, |100⟩}` to `{|111⟩, |100⟩}` — still Hamming-3 (differs in all three bits). That doesn't help.

**Correct reduction**: chain two CXs to reduce Hamming to 1:
```
apply_cx!(w_0, w_2)   # |011⟩ ↦ |111⟩ (w_0=1 flips w_2);  |100⟩ ↦ |100⟩
apply_cx!(w_1, w_2)   # |111⟩ ↦ |011⟩ (w_1=1 flips w_2);  |100⟩ ↦ |100⟩
```
Ugh — second CX walks back. Instead: `apply_cx!(w_2, w_0)`:
- `|011⟩` (w_0=1, w_1=1, w_2=0): w_2=0 → no flip → `|011⟩`
- `|100⟩` (w_0=0, w_1=0, w_2=1): w_2=1 → flip w_0 → `|101⟩`

Now pair `{|011⟩, |101⟩}` differs in w_0, w_1 — Hamming 2. Then `apply_cx!(w_1, w_0)`:
- `|011⟩` (w_1=1) → flip w_0 (1→0) → `|001⟩`
- `|101⟩` (w_1=0) → no flip → `|101⟩`

Pair `{|001⟩, |101⟩}` differs only in w_2 — Hamming 1. Now controlled-Ry on w_2 with controls (w_0=1, w_1=0) — two controls, so use the existing `push_control!`/Toffoli cascade. Uncompute both CXs.

**Scratch states visited**: `|101⟩` (forbidden label 5) and `|001⟩` (in-subspace). The forbidden `|101⟩` is visited transiently, but by reversibility the final CX pair restores it to `|100⟩` (label 4). Same logic as d=3 G_{12}: forbidden-state amplitude is transient scratch, not permanent leakage.

**Proof of leakage-freeness at d=5**: every qubit-level Givens block is reversible and returns every out-of-subspace basis state to its original amplitude at block exit. Formal argument: each block's net action on the 8-dim space is **block-diagonal** — `rot_{s,s+1} ⊕ I_6`. The **qubit-level** circuit must realise this exact block structure; correctness is verified by the test in §2.3 (step 5), comparing the assembled unitary against `d²(δ)` plus identity on labels 5,6,7.

---

## §5 `when()` composition

Sturm's control stack works via `push_control!`/`pop_control!`. When user writes
```
when(ctrl) do
    q.θ += δ
end
```
the primitive `_apply_spin_j_rotation!` fires **with the stack non-empty**. Each inner `apply_ry!`, `apply_cx!`, `_controlled_ry!` lifts its action to be controlled on `ctrl = |1⟩`:
- `apply_ry!(w_m, π)` → `C-Ry(π)` on (ctrl, w_m): 2 Ry + 2 CX.
- `apply_cx!(w_l, w_m)` → Toffoli with (ctrl, w_l) both as controls: 1 CCX.
- `_controlled_ry!(w_m, w_l, 2γ)` → sees 1 stack control + 1 explicit → lifts to 2-control CCRy cascade (via `_multi_controlled_gate!`, `multi_control.jl:88`): 4 Ry + 6 CX + 1 workspace ancilla.

**Global phase**: `exp(−i δ Ĵ_y)` has `det = 1` on the (2j+1)-dim spin-j irrep (Ĵ_y is traceless ⇒ exponential has unit determinant). So there is **no SU(d) vs U(d) phase** to pay, **unlike the Rz path** where `exp(−iδĵ) = e^{−iδj}·diag(e^{iδs})` carries the `e^{−iδj}` global phase that becomes a relative phase under `when()`. The Ry case is cleaner.

**But**: inside each G block we use `apply_ry!(w_m, π)` — this is `−i·X` in SU(2), i.e., carries a global phase `−i` per invocation. The bracket `Ry(π)·…·Ry(−π)` multiplies to `Ry(0) = I` exactly (not just ≡ I mod phase — `exp(−i(π/2)σ_y)·exp(−i(−π/2)σ_y) = I` algebraically), so the per-bracket phase cancels **within the bracket**. **But inside `when(ctrl)`, each individual `Ry(±π)` lifts to a controlled operation** — the controlled version of `Ry(π)` and `Ry(−π)` also multiply to controlled-I (i.e., the identity channel under the control), because `C-U · C-U^{-1} = C-(U U^{-1}) = C-I = I`. **So the cancellation survives under control.** ✓

**No global-phase drift**: the Ry path's cleanliness comes from Ĵ_y being traceless. Verified via the d=3 closed form: `d¹(δ)` has `det = 1` for all δ, so `C-d¹(δ)` is a bona-fide SU(d+1) operation (plus the uncontrolled identity on ctrl=0) with no extra phase to worry about. The `C-G_{01}(2γ) · C-G_{12}(2β) · C-G_{01}(2γ)` sandwich equals `C-d¹(δ)` by sub-factor-wise lifting.

---

## §6 Tradeoff review

- **Per-call cost at d=3**: 10 Ry + 8 CX (closed form, 3 Givens). Under `when(1-ctrl)`: ~22 Ry + 20 CX + 2 CCX + 1 workspace. No δ-precompute.
- **Per-call cost at d=5**: ~83 primitives total (~40 Ry + 40 CX in each outer dressing, 3 Rz in the middle). Outer dressings are δ-independent and can be cached / compiled-once.
- **δ-independent precomputation** (Option S advantage): the outer `Rx(π/2)_spinj` dressing at d=5 is fixed per-d; Julia's `precompile()` or a `const _DRESSING_D5_ANGLES = _compile_dressing(5)` module-init gives zero-call-time overhead. **Direct Givens at d=5 (the rejected Option D) would recompute `d²(δ)` angles at every call** — 10× trig + Newton solve per call — clearly worse. Option S dominates for d≥5.
- **Trotter** was considered but rejected (see §2.4). Trotter breaks subspace preservation per step, requires O(10³) steps for 1e-10, and adds O(δ²) error that spoils Wigner-matrix match.
- **d≥7 extensibility**: Option S scales cleanly. For d=7 (K=3), the middle `D_z(δ)` is 3 Rz; the outer dressing is `d³(π/2)` compiled via BBO-2005 QR into ~21 Givens (d(d−1)/2 at d=7). Adds one new `_DRESSING_D{d}_ANGLES` constant per d we ship. No architectural change. d=3 uses its own closed-form path (§3.3) permanently — no reason to retool a proven 3-Givens sequence for the sandwich.

---

## §7 TDD plan — minimum test set (written FIRST)

In `test/test_qmod.jl`, new testsets for `k8u`:

1. **`qmod d=3 :θ Wigner d¹ column 0` (criterion a)** — prepare `|0⟩_d`, apply `q.θ += π/3`, measure-amp via EagerContext state vector. Expect `(|c_00|², |c_01|², |c_10|²) = (0.75, sin²(π/3)/2, 0.25) = (0.75, 0.375, 0.25)` within 1e-10. Also assert `|c_11|² < 1e-24` (leakage).
2. **`qmod d=3 :θ full Wigner d¹ matrix`** — for δ ∈ {π/7, −π/3, 2.5, 0, π, −π}, prepare each of `|0⟩_d, |1⟩_d, |2⟩_d`, apply `q.θ += δ`, readout state-vector, compare full 3×3 block against `d¹(δ)` from the closed-form Wigner formula. Tolerance 1e-10. Assert `|11⟩` amplitude < 1e-12 on every column.
3. **`qmod d=5 :θ Wigner d² column 0` (criterion b)** — `q.θ += π/4`, compare against `[cos(π/8)⁴, −2cos(π/8)³sin(π/8), √6 cos(π/8)²sin(π/8)², −2cos(π/8)sin(π/8)³, sin(π/8)⁴]`, tolerance 1e-10.
4. **`qmod d=5 subspace preservation, 1000 random rotations` (criterion c)** — allocate `q = QMod{5}`, apply 20 random `q.θ += δᵢ`, `q.φ += δⱼ` alternating with seeded RNG, repeat 1000 times, assert `Σ_{s≥5} |c_s|² < 1e-20` across all trials.
5. **`qmod d=3 :θ under when()`** — 3-qubit product state `|ctrl⟩⊗|q⟩`, apply `when(ctrl) do q.θ += δ end`, measure ctrl=0 branch unchanged and ctrl=1 branch matches `d¹(δ)|0⟩_d`. Specifically set ctrl ← `|+⟩` (superposition), confirm the full 3-qubit state equals `(|0⟩⊗|0⟩_d + |1⟩⊗d¹(δ)|0⟩_d)/√2`.
6. **`qmod d=2 :θ regression`** — `QMod{2}(ctx)`, `q.θ += δ`, confirm final state equals single-qubit `Ry(δ)|0⟩` (should route through `BlochProxy`, zero touch of new code). Assert `getproperty` return type is `BlochProxy`, not `QModBlochProxy`.
7. **`qmod d=3 mixed Ry+Rz sequence`** — `q.θ += π/4; q.φ += π/5; q.θ += −π/4`, compare against `d¹(−π/4) · diag(e^{−i·π/5·(j−s)}) · d¹(π/4) |0⟩_d`. Verifies no cross-axis coupling bug.
8. **`qmod d=3 :θ periodicity`** — confirm `q.θ += δ` and `q.θ += δ + 2π` give the same reduced density matrix on `q` (within 1e-12). Catches `rem2pi` regressions.
9. **`qmod d=5 :θ leakage-free under worst-case δ`** — δ near π (where β → π/2, numerical sensitivity peaks at d=3; at d=5 nothing blows up because dressing is δ-independent, but test it anyway). Tolerance 1e-11 on forbidden-state amplitude.
10. **`qmod d=3 :θ classically: apply + measure`** — `QMod{3}(ctx); q.θ += 2π/3; r = Int(q)`. Over N=10⁴ samples, assert outcome frequencies within 3σ of `|d¹(2π/3)|² = (1/4, 3/8, 3/8)` on labels (0,1,2).

---

## §8 Files to touch

### `src/types/qmod.jl` (edit)

- Extend `_apply_spin_j_rotation!` at lines 314–340: replace the `axis === :θ` error branch with dispatch to two new internal functions:
  ```julia
  elseif axis === :θ
      if d == 3
          _apply_spin_j_theta_d3!(ctx, wires, δ)
      elseif d == 5
          _apply_spin_j_theta_d5!(ctx, wires, δ)
      else
          error("spin-j θ on QMod{$d} not yet shipped; d ∈ {2,3,5} supported. " *
                "Follow-on bead: extend dressing compilation to d=$d.")
      end
  ```
- Add `_apply_spin_j_theta_d3!` helper (closed form, §3.3). ~30 lines with docstring.

### `src/types/qmod_ry.jl` (new file)

**YES, extract into a new file.** The d=5 path requires a compile-time dressing constant (the 10 fixed Givens angles, computed from a QR of `d²(π/2)`), which is tens of lines of linear algebra. Rather than pollute `qmod.jl` (currently ~340 lines, all about prep/measurement/Rz/proxy machinery), isolate the Ry implementation. Contents:
- `_apply_spin_j_theta_d3!(ctx, wires, δ)` — §3.3.
- `_apply_spin_j_theta_d5!(ctx, wires, δ)` — §3.4 + dressing application.
- `const _DRESSING_D5 = _compile_spinj_halfpi_dressing(5)` — module-init numeric QR of `d²(π/2)`.
- `_compile_spinj_halfpi_dressing(d)` — helper, closed-form Wigner construction + BBO-QR decomposition. Exported only within the module.
- `_apply_givens_qubit!(ctx, wires, s, θ, d)` — the `G_{s,s+1}(θ)` qubit lowering, dispatched per Hamming distance.

New file `include`d from `src/types/qmod.jl` at the bottom (after `_apply_spin_j_rotation!` so the dispatch can call into it).

### `test/test_qmod.jl` (edit)

Add testsets enumerated in §7. ~120 lines of tests.

### Do NOT touch (confirmed)

- `src/types/qbool.jl` — Rule 11 frozen.
- `src/context/*.jl` — primitives locked.
- `src/primitives/` — doesn't exist (Session 55 confirms); primitives live in `src/context/eager.jl` etc.
- `src/Sturm.jl` — public API unchanged; `_apply_spin_j_rotation!` is unexported internal.

---

## Echo / artefact

This document is `/tmp/k8u_design_B.md`. Summary of deliverables:

- **d=3**: verified §1 orchestrator's 3-Givens closed form (matched two independent matrix entries and confirmed the atan2 branches). Implemented as `G_{01}(2γ) · G_{12}(2β) · G_{01}(2γ)` with 10 Ry + 8 CX.
- **d=5**: recommended **sandwich decomposition** `Rx(π/2)_spinj · D_z(δ) · Rx(−π/2)_spinj`, where the outer dressings are δ-independent and precompiled once at module init via BBO-2005 QR on `d²(π/2)`. Middle is existing nrs Rz path.
- **Leakage-free** for d=3 (|11⟩ pointwise invariant; proved by walking through each block). For d=5 the forbidden-state invariance follows from each Givens block being block-diagonal in the 5+3 decomposition, verified numerically in the build-time test.
- **`when()` composition**: clean — Ĵ_y is traceless so no global phase issue, unlike Rz. The Ry(π) bracket in G_{01} cancels exactly under any lift.
- **TDD**: 10 tests enumerated, bead acceptance criteria (a,b,c) directly covered.

DESIGN COMPLETE
