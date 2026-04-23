# Sturm.jl-k8u — Proposer A design: QMod{d} Ry rotation at d ≥ 3

Bead: `Sturm.jl-k8u` ("QMod{d} spin-j Ry via per-wire factorisation"). Round: 3+1, Proposer A.
Scope: `_apply_spin_j_rotation!(ctx, wires, :θ, δ, Val(d))` for d ≥ 3 (shipping d = 3 and d = 5;
d = 4 and d ≥ 6 generalisable from the same template).

Ground truth: `q.θ += δ` on a `QMod{d}` register must apply `exp(−iδĴ_y)` on the
spin-`j = (d−1)/2` SU(2) irrep embedded in the qubit-encoded computational-basis labels
`|s⟩ = |j, j−s⟩_z`, Bartlett-deGuise-Sanders Eq. 5
(`docs/physics/bartlett_deGuise_sanders_2002_qudit_simulation.pdf`).

---

## §1 Verification of the orchestrator's d = 3 closed form

The orchestrator proposes

    d¹(δ) = G_{0,1}(2γ) · G_{1,2}(2β) · G_{0,1}(2γ)

where `G_{i,j}(θ)` is the 3×3 embedding of `Ry(θ)` with `cos(θ/2)` on the diagonal,
`−sin(θ/2)` above, `+sin(θ/2)` below, and

    γ = atan2( sin(δ/2),                        √2 · cos(δ/2) )
    β = atan2( sin(δ/2) · √(2 − sin²(δ/2)),    cos²(δ/2)      )

### 1.1 Independent algebraic check on the centre entry

I verify `M[1,1] = cos δ` (the trickiest entry — two signed off-diagonals feed into
it). Let `Cg ≡ cos γ`, `Sg ≡ sin γ`, `Cb ≡ cos β`, `c ≡ cos(δ/2)`, `s ≡ sin(δ/2)`.
Direct matrix multiplication: `M = G_{0,1}(2γ) · G_{1,2}(2β) · G_{0,1}(2γ)` gives

    M[1,1] = Sg · (−Sg) + Cg · (Cb · Cg) = −Sg² + Cg² · Cb.

From the `atan2` definitions (denominator `√(s² + 2c²) = √(1 + c²)`):
`Sg² = s²/(1+c²)`, `Cg² = 2c²/(1+c²)`, and `D_β² = s²(1+c²) + c⁴ = s² + c² = 1`,
so `Cb = c²` exactly. Plugging in:

    M[1,1] = −s²/(1+c²) + (2c²/(1+c²)) · c²
           = (2c⁴ − s²)/(1+c²)
           = (2c⁴ + c² − 1)/(1+c²)        (use s² = 1−c²)
           = (2c² − 1)(1+c²)/(1+c²)
           = 2c² − 1 = cos δ. ✓

### 1.2 Numerical verification

Full-matrix check via `scipy.linalg.expm(−iδ Ĵ_y)` on Sakurai spin-1 Ĵ_y, compared
against the three-Givens product over δ ∈ {π/3, 0.4, −π/3, π−10⁻⁴, π, −π, 2π−10⁻¹⁰,
10⁻⁶}: max elementwise error ≤ 4.25 · 10⁻¹⁶. The `atan2` branch (not plain `atan`)
is needed to get the right sign at δ < 0.

### 1.3 Singularity check

At δ = ±π: `c = 0`, `s = ±1`. `atan2(±1, 0⁺) = ±π/2` cleanly (no NaN) for both
γ and β denominators. At δ = 0 numerators vanish faster than denominators → γ=β=0
(identity). Docstring must mandate `atan2` (not `atan`) — this is the only
footgun.

**Conclusion on §1.** Orchestrator's closed form confirmed; algebra, numerics, and
branch analysis all check out.

---

## §2 d = 5 decomposition

I recommend **Option S (sandwich)** via

    exp(−iδ Ĵ_y) = Rz(π/2) · V · exp(−iδ Ĵ_z) · V^T · Rz(−π/2)    (*)

where `V ≡ d^j(π/2) = exp(−i(π/2) Ĵ_y)` is a real orthogonal (2j+1)×(2j+1) matrix,
**δ-independent**. Derivation:

1. SU(2) structure `[Ĵ_x, Ĵ_z] = −i Ĵ_y` gives `exp(+i(π/2)Ĵ_x) Ĵ_z exp(−i(π/2)Ĵ_x) = Ĵ_y`
   (verified at j=2 to 1.1e-15), so `exp(−iδ Ĵ_y) = U · exp(−iδ Ĵ_z) · U^†` with
   `U = exp(+i(π/2) Ĵ_x)`.
2. `Rz(π/2) Ĵ_y Rz(−π/2) = −Ĵ_x` (Rz-conjugation rotates Jy toward −Jx), so
   `Ĵ_x = Rz(π/2) · (−Ĵ_y) · Rz(−π/2)` and
   `U = Rz(π/2) · exp(−i(π/2) Ĵ_y) · Rz(−π/2) = Rz(π/2) V Rz(−π/2)`.
3. Insert into step 1; use that Rz commutes with the diagonal `exp(−iδ Ĵ_z)`:

        exp(−iδ Ĵ_y) = Rz(π/2) V Rz(−π/2) · exp(−iδ Ĵ_z) · Rz(π/2) V^T Rz(−π/2)
                    = Rz(π/2) · V · exp(−iδ Ĵ_z) · V^T · Rz(−π/2).

Numerically verified at j=2, δ ∈ {π/4, 0.7, −0.5, π/3}: max error ≤ 7.7e-16.

### 2.1 Why sandwich, not direct Givens

**Option D (direct Givens-QR of d^j(δ))**: 10 non-trivial adjacent Givens at d=5,
each with a δ-dependent angle that must be computed by runtime QR on a newly-built
5×5 matrix. No closed form in BO'L-Brennen 2005.

**Option S (sandwich)**: V is δ-independent; its 10-Givens decomposition is a
`const` table initialised at module load. Per-call cost: 2×V circuit + K Rz's +
outer Rz wrappers — no runtime matrix solve. Reuses the nrs Rz primitive verbatim.
Drop-in extensible to d = 7, 9, 11.

S wins on (i) no runtime QR, (ii) nrs reuse, (iii) extensibility.

### 2.2 Givens sequence for V = d^2(π/2)

V decomposes into EXACTLY 10 non-trivial adjacent Givens (numerically confirmed
via standard QR on the 5×5 orthogonal matrix with `±0.25, ±0.5, ±0.6124, 0` entries):
`V = G_{0,1}(θ₁) · G_{1,2}(θ₂) · … · G_{k_{10}, k_{10}+1}(θ₁₀)`. The 10 angles are
δ-independent reals for d = 5; stored in a `const NTuple{10, Float64}` initialised
at module load from a fixed QR routine applied to the precomputed d^2(π/2) matrix.
V^T = V^{−1} is free: same sequence in reverse order with negated angles.

### 2.3 How each G_{k,k+1}(θ) is realised on K qubits

Hamming-distance-1 pair: a controlled-Ry on the differing wire (conditioned on the
fixed bits). Hamming-distance-`h > 1` pair: CX-ladder bracket that reduces to
Hamming-1 through ≤ 1 forbidden transient, plus controlled-Ry, plus uncompute
(§4.1 derives the d=3 case; §4.2 discusses the Hamming-3 case that appears at d=5).

---

## §3 Qubit-level primitive sequence

Primitive inventory (verified by orchestrator):

* `apply_ry!(ctx, w, θ)`, `apply_rz!(ctx, w, θ)` — primitive.
* `apply_cx!(ctx, c, t)`, `apply_ccx!(ctx, c1, c2, t)` — primitive.
* `_controlled_ry!(ctx, c, t, θ)` — ABC helper in `src/context/multi_control.jl:34`.
  Emits `2 Ry + 2 CX` with the current control stack cleared for the inner four
  gates (then the caller's control stack is re-applied by `apply_*!` dispatch).
* `push_control!` / `pop_control!` / `with_empty_controls` — low-level stack.
* `when(f, ctrl::QBool)` — high-level control block.
* **No `apply_x!`**: use `apply_ry!(w, π)` (introduces `−1` phase that cancels in
  sandwich pairs `Ry(π) · … · Ry(−π) = Ry(π) · … · Ry(π)†`).

### 3.1 d = 3 line-by-line: `_apply_spin_j_rotation!(ctx, (w_lsb, w_msb), :θ, δ, Val(3))`

Wire layout: `wires[1] = w_lsb` (bit 0), `wires[2] = w_msb` (bit 1). Encoding:
`|0⟩_d = |00⟩`, `|1⟩_d = |01⟩` (LSB set), `|2⟩_d = |10⟩` (MSB set). Forbidden: `|11⟩`.

Compute angles:

    γ = atan2(sin(δ/2), √2 · cos(δ/2))
    β = atan2(sin(δ/2) · √(2 − sin²(δ/2)), cos²(δ/2))

The sequence `G_{0,1}(2γ) · G_{1,2}(2β) · G_{0,1}(2γ)` is applied left-to-right on the
statevector, so the RIGHTMOST G-factor fires FIRST.

    # G_{0,1}(2γ): rotate |0⟩_d ↔ |1⟩_d, i.e. the pair (|00⟩,|01⟩). Differing bit = w_lsb.
    # Both partners have w_msb = 0, so apply Ry(2γ) on w_lsb conditioned on w_msb=0,
    # implemented by negating w_msb with an Ry(π) bracket and using the standard C-Ry.
    apply_ry!(ctx, w_msb, π)                    # X up to −i phase
    _controlled_ry!(ctx, w_msb, w_lsb, 2γ)      # C-Ry with ctrl=w_msb
    apply_ry!(ctx, w_msb, -π)                   # undo (phase cancels with first Ry(π))

    # G_{1,2}(2β): rotate |1⟩_d ↔ |2⟩_d = (|01⟩, |10⟩). Hamming distance 2.
    # CORRECT bracket direction: CX(w_lsb → w_msb). See §4.1 for the leakage
    # derivation — the OTHER direction CX(w_msb → w_lsb) would leak.
    # CX(w_lsb → w_msb) swaps (|01⟩, |11⟩) and leaves (|00⟩, |10⟩) fixed, so label 1
    # is routed transiently onto the forbidden |11⟩ and label 2 stays on |10⟩, making
    # them a Hamming-1 pair under w_lsb.
    apply_cx!(ctx, w_lsb, w_msb)
    _controlled_ry!(ctx, w_msb, w_lsb, 2β)      # Ry(2β) on w_lsb when w_msb=1
    apply_cx!(ctx, w_lsb, w_msb)                # uncompute; forbidden amplitude returns to |01⟩

    # G_{0,1}(2γ) again (same as first):
    apply_ry!(ctx, w_msb, π)
    _controlled_ry!(ctx, w_msb, w_lsb, 2γ)
    apply_ry!(ctx, w_msb, -π)

**Gate count per d = 3 `q.θ += δ` call (excluding `when` wrapping):**

* 2 × G_{0,1}: each = 2 Ry(±π) + `_controlled_ry!` (2 Ry + 2 CX) = 4 Ry + 2 CX, so 8 Ry + 4 CX
* 1 × G_{1,2}: 2 CX (bracket) + `_controlled_ry!` (2 Ry + 2 CX) = 2 Ry + 4 CX

Total: **10 Ry + 8 CX** per `q.θ += δ` at d = 3.

Under `when(ctrl)`: each primitive picks up one more control from the stack.
`apply_ry!` becomes `C-Ry` (2 Ry + 2 CX), `apply_cx!` becomes `CCX` (primitive).
`_controlled_ry!` nests cleanly (it sets the empty-stack ABC then re-raises controls
via the `apply_ry!` dispatch on the original stack). Expected blow-up: ~2× gate count,
consistent with the `nrs` reviewer's observations.

### 3.2 d = 5 sequence sketch

    # Middle: Rz(δ) via nrs factorisation on K=3 wires — VERBATIM reuse of the
    # existing :φ branch:
    for i in 1:K
        apply_rz!(ctx, wires[i], δ * (1 << (i - 1)))
    end

becomes wrapped:

    # Outer Rz(−π/2) on the d-level register — same nrs factorisation with angle −π/2:
    _nrs_rz_branch!(ctx, wires, -π/2)                      # reuses :φ code

    # V^T circuit: 10 adjacent Givens with fixed angles (precomputed from W(π/2) at d=5):
    _apply_fixed_givens!(ctx, wires, V_pi2_d5_angles_reversed_neg, Val(5))

    # Rz(δ) middle via nrs:
    _nrs_rz_branch!(ctx, wires, δ)

    # V circuit: 10 adjacent Givens with same angles (non-reversed):
    _apply_fixed_givens!(ctx, wires, V_pi2_d5_angles, Val(5))

    # Outer Rz(+π/2):
    _nrs_rz_branch!(ctx, wires, π/2)

where `V_pi2_d5_angles` is a `const NTuple{10, Float64}` computed at module load
from a known Wigner d^2(π/2) matrix. Each `G_{k, k+1}(θ_k)` in the 10-Givens sweep
is realised by the same CX-bracket pattern as §3.1, generalised to K = 3 wires with
the forbidden states `|101⟩, |110⟩, |111⟩` avoided (see §4).

**Gate count per d = 5 `q.θ += δ` call:**

* 2 × Rz outer: 2 × 3 = 6 Rz
* 2 × V circuit: 2 × 10 Givens × (~4 Ry + ~4 CX avg) = ~80 Ry + ~80 CX
* 1 × Rz middle: 3 Rz

Total: **~80 Ry + 9 Rz + ~80 CX** per `q.θ += δ` at d = 5.

---

## §4 Leakage proof

### 4.1 d = 3: `|11⟩_{qubit}` stays invariant

Claim: starting from `a|00⟩ + b|01⟩ + c|10⟩ + 0·|11⟩`, amplitude on `|11⟩` remains 0
after the 3-Givens sequence.

**G_{0,1}(2γ) block** (Ry(π)-bracket): the composite gadget
`Ry(π)_{msb} · C-Ry(2γ) · Ry(−π)_{msb}` is the standard "C-Ry on msb=0" construction;
net effect is Ry(2γ) on the `(|00⟩,|01⟩)` subspace, identity on `(|10⟩,|11⟩)`. So
|11⟩ → |11⟩ exactly — 0 in, 0 out. ✓

**G_{1,2}(2β) block** (CX(w_lsb → w_msb)-bracket):

1. `apply_cx!(w_lsb, w_msb)` swaps `(|01⟩, |11⟩)` and fixes `(|00⟩, |10⟩)`.
   State `a|00⟩ + b|01⟩ + c|10⟩ + 0|11⟩` → `a|00⟩ + 0|01⟩ + c|10⟩ + b|11⟩`.
2. `_controlled_ry!(w_msb, w_lsb, 2β)` rotates `(|10⟩, |11⟩)`:
   `(c, b) → (c cos β − b sin β, c sin β + b cos β) ≡ (c', b')`.
3. `apply_cx!(w_lsb, w_msb)` again swaps `(|01⟩, |11⟩)` back.
   Final: `a|00⟩ + b'|01⟩ + c'|10⟩ + 0|11⟩`. ✓

The |11⟩ amplitude AT EXIT equals the |01⟩ amplitude pre-step 3, which is 0 (step 1
evacuated it to |11⟩, step 2 is a rotation on `w_msb=1` subspace that doesn't touch
|01⟩). ✓

**Second G_{0,1}(2γ)**: same as first, transparent on |11⟩.

**Why bracket direction matters.** The alternative `CX(w_msb → w_lsb)` would swap
`(|10⟩, |11⟩)` instead of `(|01⟩, |11⟩)`, routing label 2 to |11⟩ WHILE label 1 stays
on |01⟩ with `w_msb=0`. The subsequent controlled-Ry (acting on `w_msb=1`) then
rotates label 2's amplitude with whatever junk sits on |10⟩ post-step-1 (which is
nothing in our case) — but the uncompute CX then BACKS OUT AMPLITUDE that the
rotation produced on |11⟩, NOT from |11⟩. Net: |11⟩ carries a non-zero residual.
This is the nrs-Proposer-B leakage bug. **Direction matters — must be lsb→msb at d=3.**

### 4.2 d = 5: forbidden levels {|101⟩, |110⟩, |111⟩}

Encoding (LE): s=0=`000`, 1=`100`, 2=`010`, 3=`110`, 4=`001`; forbidden = 5,6,7.
Adjacent pairs by Hamming distance: (0,1)=1, (1,2)=2, (2,3)=1, (3,4)=3. The
Hamming-3 pair (3,4) = (|110⟩, |001⟩) is the hard one: naive CX-ladders traverse
|101⟩ or |111⟩ (leakage).

**Recommended v0.1 construction: Toffoli-based workspace ancilla.** Brennen-Bullock-
O'Leary 2005 `brennen_bullock_oleary_2005_efficient_qudit_circuits.pdf` Thm. 3:
allocate one clean ancilla, compute `is_pair_{(s,s+1)}` via ≤2 CCX into the ancilla,
apply controlled-Ry on the ancilla, uncompute. Leakage-free by construction (the
ancilla only flips when the register is in one of the two pair states). Cost per
Hamming-≥2 Givens: 1 ancilla + 2 CCX + 1 CRy + 2 CCX uncompute.

Alternative options the implementer may explore (but is not required to for v0.1):
(i) Gray-code reordering the 10-Givens sweep to eliminate Hamming-≥2 pairs;
(ii) direct leakage-free CX ladders for the specific Hamming-2 pair (1,2) — the
d=3 derivation in §4.1 generalises (the `CX(w_lsb → w_mid)` bracket direction
routes label 1 to |110⟩ which IS a forbidden state, so that direction FAILS at d=5;
the opposite direction `CX(w_mid → w_lsb)` routes label 2 to |110⟩, also forbidden
— Hamming-2 at d=5 does NOT have a clean single-CX bracket because BOTH forbidden
images at `(w_msb=0, *)` are indistinguishable from label 3 or 4). So for d=5, even
the Hamming-2 pair (1,2) likely needs the ancilla construction. This is an argument
for taking Thm. 3 uniformly for all Hamming-≥2 pairs at d=5.

For the 4 Hamming-1 adjacent pairs (including (0,1) and (2,3)), direct C-Ry with
the existing `_controlled_ry!` + Ry(π) negation brackets works (generalisation of
§3.1 first-G-block).

---

## §5 `when()` composition

**Global-phase policy.** `exp(−iδ Ĵ_y)` has determinant +1 on the spin-j irrep —
genuinely SU(d), no phase drift under control. The `:θ` branch is thus **phase-clean
under `when`**, unlike `:φ` (Rz) which has a `exp(−iδj)` prefactor that becomes a
relative controlled phase under `when`. This asymmetry is beneficial and correct
(Campbell 2014 / CLAUDE.md Global Phase section force the Rz cost; Ry has none).

**Ry(π) brackets inside G_{0,1}.** `Ry(π) = −iY` has determinant `−1` as a qubit
unitary, so individually each Ry(π) is a −1 phase. Under `when(ctrl)`, each becomes
`C-Ry(π) = I ⊕ (−iY)`. The PAIR `Ry(π) · … · Ry(−π)` composes to
`(−iY)(…)(+iY) = Y(…)Y` up to `+1`: the phases cancel unconditionally AND controlled
(when ctrl=1: `(iY)(…)(−iY)`; when ctrl=0: `I · … · I`). So the G_{0,1} block
introduces no phase drift, under control or otherwise. ✓

**Docstring warning.** `Ry(+π)` and `Ry(−π)` are NOT interchangeable here — the sign
matters under control. Do not "simplify".

---

## §6 Tradeoff review

| Aspect | d = 3 (direct) | d = 5 (sandwich) |
|---|---|---|
| Ry / CX / Rz per call | 10 / 8 / 0 | ~80 / ~80 / 9 |
| Angle solve | closed-form (2 atan2) | precomputed const |
| δ-independent precompute | none | the V circuit (10-Givens const table) |
| Ancilla | 0 | 1 per Hamming-≥2 Givens (returned) |
| Extends to d ≥ 7 | new closed form per d | drop-in (same sandwich identity) |

**Rejected: Trotter.** `exp(−iδ Ĵ_y)` via Suzuki-Trotter of Jz, Jx gives only
`O(δ²/N)` error — can't hit the 1e-10 acceptance.

**Rejected for v0.1: Klappenecker-Rötteler 7-gate form at d=3.** Fewer gates than
my 18, but angles require a numerical solve per δ. The orchestrator's closed form
(§1) + sandwich generalisation (§2) is more uniform across d. Follow-on
`optimise-k8u-d3` bead can lower once green.

**Extensibility.** Sandwich identity (*) holds for ANY j. Per-d cost: one offline
QR of `d^j(π/2)`, stored as a const Givens angle table. d ≥ 7 is drop-in. Even d
(4, 6, 8) also works in principle but the Bartlett Eq. 13 `e^{−iπ/d}` on X_d may
interact with the sandwich; deferred to a follow-on bead (k8u acceptance is d = 3,
5 only).

---

## §7 TDD plan — minimum test set

Tests written FIRST, before any implementation (tolerance 1e-10 unless noted):

1. **d = 3, δ = π/3, column 0 (bead (a))**: `q = QMod{3}(); q.θ += π/3`; assert
   `|a[0]| ≈ 0.75`, `|a[1]| ≈ sin(π/3)/√2`, `|a[2]| ≈ 0.25`, `|a[3]| < 1e-12`.
2. **d = 3, all 3 columns**: for `|0⟩_d, |1⟩_d, |2⟩_d` preps (via raw `apply_ry!`/
   `apply_cx!`), apply `q.θ += δ` for δ ∈ {π/3, 0.4, −π/3, 2π − 0.01}, compare against
   analytically computed d¹(δ) column s = 0, 1, 2.
3. **d = 5, δ = π/4, column 0 (bead (b))**: mirror test 1. **Pin the sign convention
   in the implementation docstring — ground truth is `exp(−iδĴ_y)[:, 0]` with Ĵ_y the
   Sakurai spin-j matrix; signs on odd rows are +, not − as an unwary reading of the
   bead's quoted "d² column 0" might suggest (§1.2 of this design).**
4. **Subspace preservation, random sequences (bead (c))**: N = 1000 runs, each with
   random d ∈ {3, 5} and a random-length sequence of `q.θ +=` / `q.φ +=` rotations
   at uniform angles; assert `|a[s]| < 1e-12` for all s ≥ d at the end.
5. **`when(ctrl) q.θ += δ` on d=3**: Bell-control + rotation; measurement counts
   show ctrl=1 branch matches d¹(π/3) col 0 on q, ctrl=0 branch leaves q in |0⟩_d.
6. **Leakage-free per-block**: TracingContext dump during one `q.θ += π/3` call at
   d = 3; assert after each G block (between blocks, not within) `|a[s ≥ d]| = 0`
   to 1e-12.
7. **d = 2 regression**: existing ak2 parity tests must still pass.
8. **Mixed Ry + Rz at d = 3**: random initial state; apply sequence
   `q.θ += 0.3; q.φ += 0.5; q.θ += −0.2; q.φ += π/3`; compare against analytical
   `exp(−iπ/3 Ĵ_z)·exp(+i 0.2 Ĵ_y)·exp(−i 0.5 Ĵ_z)·exp(−i 0.3 Ĵ_y)|ψ⟩`.
9. **`when` phase asymmetry**: `when(ctrl) q.φ += δ` carries `exp(−iδj)` relative
   phase (nrs test line 576 already asserts this); `when(ctrl) q.θ += δ` carries NO
   relative global phase — new test.
10. **Edge angles**: δ ∈ {±π, 0, 2π} — verify `atan2` branch is NaN-free and output
    matches d^j(δ).

---

## §8 Files to touch

* **`src/types/qmod.jl`**: extend `_apply_spin_j_rotation!`'s `:θ` branch.
  Dispatch: d=3 → `_spin_j_ry_d3!`; d=5 → `_spin_j_ry_sandwich!(_, _, _, Val(5))`;
  d ≥ 7 → same sandwich helper (extensible; error for d not in precomputed table
  with a `k8u-extend` bead pointer); d = 4 → error (follow-on bead, outside k8u
  acceptance). Existing `:φ` branch (lines 321–328) unchanged.
* **NEW `src/types/qmod_ry.jl`** (~150–250 LoC: two helpers, per-d angle tables,
  leakage-free Givens bracket helper). Avoids pushing `qmod.jl` past 600 lines;
  precedent is `qint_bitwise.jl`/`qint_shifts.jl`.
* **`test/test_qmod.jl`**: new `@testset "k8u: spin-j Ry at d ≥ 3"` with the 10
  tests from §7. Delete the current `"ak2 d>2: q.θ += δ errors"` testset (lines
  370–388) — it guards the stub k8u replaces.
* **No new physics PDF**: Bartlett 2002 + Sakurai already local. Sandwich identity
  is standard SU(2) algebra; cite Sakurai Ch. 3 in the docstring.

**Not touched:** `src/types/qbool.jl` (Rule 11 frozen), `src/context/*.jl` (no new
primitives needed), `src/Sturm.jl` public API.

---

## Appendix — key numerical ground truths

* d=3 closed form: algebra `M[1,1] = cos δ` confirmed; numerics 1.1e-16 across 9 δ
  values incl. ±π.
* d=5 sandwich `exp(−iδĴ_y) = Rz(π/2)·V·exp(−iδĴ_z)·V^T·Rz(−π/2)` with
  `V = d^j(π/2)` real orthogonal — verified at δ ∈ {π/4, 0.7, −0.5, π/3} to 7.7e-16.
* d=5 V factors into exactly 10 non-trivial adjacent Givens (explicit QR).
* d=3 leakage-free CX-bracket direction: `CX(w_lsb → w_msb)` (nrs-Proposer-B's
  direction leaks — §4.1 derives the correction).

DESIGN COMPLETE
