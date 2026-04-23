# Proposer B review — Sturm.jl-ixd, d=5 Ry via Euler sandwich

Scope: independent audit of the orchestrator's d=5 decomposition. NOT redesign.

## §1 Algebraic sanity check of the Euler sandwich

On SU(2):

    Rz(π/2)·Rx(δ)·Rz(-π/2) = Ry(δ)    (*)

Proof: under conjugation by Rz(π/2), σx ↦ σy (standard Pauli rotation lemma;
Rz(α)σxRz(-α) = cos α · σx + sin α · σy; at α=π/2 this is σy). Both Rx and Ry
are exponentials of their generators, so the conjugacy lifts from generators
to the finite rotations. Equivalently,

    Rx(δ) = Ry(π/2)·Rz(δ)·Ry(-π/2)     (**)

because conjugating σz by Ry(π/2) gives σx.

Substituting (**) into (*):

    Ry(δ) = Rz(π/2)·Ry(π/2)·Rz(δ)·Ry(-π/2)·Rz(-π/2).                    (†)

SU(2) → U(2j+1) is a group homomorphism (the spin-j functor), so (†) lifts
verbatim to the irrep:

    exp(-i δ Ĵ_y) = Rz_j(π/2) · Ry_j(π/2) · Rz_j(δ) · Ry_j(-π/2) · Rz_j(-π/2).

This is exactly the identity the orchestrator uses — signs match.

Spin-1/2 sign cross-check against Sturm primitives. Sturm defines
`apply_ry!(w, δ) ≡ exp(-iδY/2)`, `apply_rz!(w, δ) ≡ exp(-iδZ/2)` (from
`eager.jl` → `orkan_ry`, no sign flip). Ĵ_y at j=1/2 is Y/2, so `q.θ += δ` on
d=2 realises exp(-iδY/2) = Ry(δ) with the textbook sign. The sandwich
composition with the literal δ passed to `apply_rz!(w, δ)` therefore matches
the analytic target at d=2, which is precisely what current k8u and nrs
tests already verify. No polarity flip is hiding at the base case.

## §2 Givens spot-check — op (3, 0.9272952...)

Pick the FIRST Givens in the list: `(pair_lo=3, θ=0.9272952180016122)`.
This is the outermost / leftmost factor in V5, i.e. V5 = G_{3,4}(θ)·(rest).

Equivalently, QR-style, G_{3,4}(-θ)·V5 should zero entry (4,0) using (3,0).
So θ = atan2( V5[4,0], V5[3,0] ) is expected.

Wigner d²(π/2), column 0 (Bartlett labelling `|s⟩ = |j, j-s⟩_z`, so row
index s corresponds to m = j - s = 2, 1, 0, -1, -2):

    [0.25, 0.5, √6/4, 0.5, 0.25]

So V5[3,0] = 0.5, V5[4,0] = 0.25, and atan2(0.25, 0.5) = atan(1/2) =
0.46364760900080606. The Givens angle for the Ry(θ) block that zeros V5[4,0]
is twice this (because Ry rotates by θ/2 per 2×2 block):
θ = 2·atan(1/2) = 0.9272952180016122. **Exact match** to the listed angle.
Verified numerically (Python wigner_d): 2·np.arctan(0.5) =
0.9272952180016122 to machine precision. Givens decomposition is consistent.

## §3 Per-Givens circuit audit

Encoding (LE): label s = b0 + 2·b1 + 4·b2 with wires[1]=w0=b0 (LSB),
wires[2]=w1, wires[3]=w2 (MSB).

    s=0: |000⟩   s=1: |100⟩   s=2: |010⟩   s=3: |110⟩   s=4: |001⟩
    (leakage) s=5: |101⟩   s=6: |011⟩   s=7: |111⟩

(Throughout I write qubit kets as |w0 w1 w2⟩; `w0` first matches LE.)

**H=1 audit — pair (2,3).** b_lo = binary(2,3) = (0,1,0), b_hi = (1,1,0).
diff_bits = {0} (wire w0). target = w0. non-diff bits = {1, 2} with
(w1, w2) = (1, 0) as ctrl pattern. Circuit: `:crry((w1=1, w2=0), w0, θ)`.

Trace on the 8 states:
 - |000⟩ s=0: ctrl (w1,w2)=(0,0) ≠ (1,0). Identity. OK.
 - |100⟩ s=1: ctrl (0,0) ≠ (1,0). Identity. OK.
 - |010⟩ s=2: ctrl (1,0) == (1,0), target w0=0 → cos(θ/2)|010⟩ + sin(θ/2)|110⟩
   = cos(θ/2)|s=2⟩ + sin(θ/2)|s=3⟩. Matches G_{2,3}(θ) column 2. OK.
 - |110⟩ s=3: ctrl (1,0) matches, target=1 → -sin(θ/2)|010⟩ + cos(θ/2)|110⟩
   = -sin(θ/2)|s=2⟩ + cos(θ/2)|s=3⟩. Matches G_{2,3}(θ) column 3. OK.
 - s ∈ {4..7}: w2=1 for s=4 (|001⟩), s=5 (|101⟩), s=6 (|011⟩), s=7 (|111⟩).
   ctrl (·, w2=1) ≠ (·, 0); all identity. In particular leakage (5,6,7) is
   untouched and s=4 stays at s=4. OK.

Subspace action: I_0 ⊕ I_1 ⊕ G_{2,3}(θ) ⊕ I_4, leakage identity. Matches
target exactly. No sign issue (H=1 has no CX-scratch).

**H=3 audit — pair (3,4).** b_lo = binary(3,3) = (1,1,0), b_hi =
binary(4,3) = (0,0,1). diff_bits = {0, 1, 2} (all wires). H=3. pivot =
diff_bits[end] = 2 (w2, the MSB).

Forward CX chain (pivot controls others):
 - CX(ctrl=w2, tgt=w0)
 - CX(ctrl=w2, tgt=w1)

After the chain, on basis states: w2=0 leaves (w0,w1) alone; w2=1 flips both.
Map:
 - s=0 |000⟩ → |000⟩  (s=0)
 - s=1 |100⟩ → |100⟩  (s=1)
 - s=2 |010⟩ → |010⟩  (s=2)
 - s=3 |110⟩ → |110⟩  (s=3) — should be paired with s=4
 - s=4 |001⟩ → |111⟩  — now differs from s=3 |110⟩ only in w2
 - s=5 |101⟩ → |011⟩  (leakage)
 - s=6 |011⟩ → |101⟩  (leakage)
 - s=7 |111⟩ → |001⟩

Post-CX, the pair (s=3, s=4) sits at (|110⟩, |111⟩) differing in w2 only.
b_lo_post at pivot bit (w2) is 0, b_hi_post is 1. Per the spec,
`b_lo_post[pivot] == 0` → pass `+θ` (no sign flip). Controls for the
CRy are the non-pivot bits of post-CX state: (w0=1, w1=1).

`:crry((w0=1, w1=1), w2=pivot, +θ)`: only acts on states with w0=w1=1:
|110⟩ and |111⟩. On |110⟩ (w2=0) → cos(θ/2)|110⟩ + sin(θ/2)|111⟩; on |111⟩
→ -sin(θ/2)|110⟩ + cos(θ/2)|111⟩.

Now uncompute the CX chain (reverse):
 - CX(w2, w1), CX(w2, w0)

After uncompute, each "post-CX branch" maps back. For the s=3 leg:
mix `cos(θ/2)|110⟩_post + sin(θ/2)|111⟩_post` uncomputes (w2=0 branch
unchanged; w2=1 branch flips w0 and w1):
|110⟩_post → |110⟩_pre (s=3); |111⟩_post → |001⟩_pre (s=4). So the
s=3 column becomes `cos(θ/2)|s=3⟩ + sin(θ/2)|s=4⟩`. For the s=4 leg, by
symmetry, `-sin(θ/2)|s=3⟩ + cos(θ/2)|s=4⟩`. Matches G_{3,4}(+θ) exactly.

Leakage check: s=5,6,7 pre-CX map to post-CX states |011⟩, |101⟩, |001⟩,
none of which have (w0,w1)=(1,1), so the CRy acts as identity. Uncompute
restores them. Leakage stays in leakage, but critically the **in-subspace
→ leakage transfer is zero**: s=3 and s=4 ONLY end up in span{|s=3⟩,|s=4⟩}.

No sign error. The "b_lo_post[pivot]" rule gave `+θ` here and that is what
numerical verification confirms. The risk flagged in k8u (CX-scratch sign
flip on the d=3 G_{12}) recurs as exactly this polarity rule; the orchestrator
has encoded it correctly.

**Potential bug to watch.** The H=2 pair (1,2) has pivot on some mid-weight
wire. I did not trace it by hand; recommend an identical-style unit test
per-pair to pin the polarity for all four pairs independently. The
"SIGN FIX" clause is the most likely place for an off-by-one.

## §4 Global phase and `when()`

Rz_j(α) in the nrs factorisation has factored form `exp(-iαj) · Π_i
apply_rz!(w_{i+1}, α·2^i)`. The `exp(-iαj)` is a global phase in the
uncontrolled case but becomes a relative phase under `when(ctrl)`. For the
sandwich:

  - outer Rz(±π/2): prefactor `exp(∓iπj/2)` — FIXED, does not depend on δ.
    Both outer factors contribute `exp(-iπj/2)·exp(+iπj/2) = 1`. **Cancel
    exactly**, even under `when()`. No residual controlled phase from them.
  - middle Rz(δ): prefactor `exp(-iδj)`. This DOES depend on δ and becomes
    `exp(-iδj·|ctrl=1⟩⟨ctrl=1|)` under control — an observable relative
    phase.

The Ry_j(±π/2) Givens sequences are products of `apply_ry!`/`apply_cx!`
primitives, each of which is SU(2) or just a permutation — they contribute
no global phase.

Verdict: the controlled-sandwich differs from controlled-exp(-iδĴ_y) by the
controlled Rz(δ) global-phase `exp(-iδj·n_ctrl)`. At j=2, δ=π this is
`exp(-i2π) = 1`, but at generic δ it is physical and will show up in any
interferometric test. Two options:

(i) **Absorb and document (recommended).** This is the same policy choice
    as nrs Session 55 for Rz directly; matching nrs policy keeps the spin-j
    API uniform. Document that `when(c) q.θ += δ` carries the same
    controlled-j·δ phase that `when(c) q.φ += δ` carries, i.e. it IS
    `controlled-exp(-iδĴ_y)` up to the standard SU(d) vs U(d) convention.
(ii) **Phase-clean by compensating Rz on the control wire** (`when(c):
     apply_rz!(c, -2jδ)`) just before the middle `q.φ += δ`. Simple; adds
     one gate; turns the sandwich into a true `controlled-exp(-iδĴ_y)`. If
     csw needs a specific phase convention (e.g. it composes sandwiches
     inside larger phase-estimation contexts), do this. If csw only
     consumes measurement statistics, (i) is cheaper.

Recommend (i) unless csw's downstream usage explicitly demands (ii).
Locking in (i) matches §8.4 of the qudit magic-gate survey and keeps a
single global-phase policy across all three primitives.

## §5 TDD plan (minimum set)

All tests live in `test/test_qmod.jl` with `_amps_snapshot` helper.

1. **Subspace preservation (c).** 1000 random δ∈[-2π,2π] sequences of
   `q.θ += δ` and `q.φ += δ` on QMod{5}; assert leakage amplitudes
   (labels 5,6,7) ≤ 1e-12 after each step. Fail-loud on the first step
   that drifts.
2. **Column 0 at δ=π/4.** Prepare QMod{5} in |0⟩; `q.θ += π/4`; read full
   8-amplitude snapshot; compare first 5 entries to the analytic
   [0.7286, 0.6036, 0.3062, 0.1036, 0.0214] (±1e-10). All positive.
   Explicitly assert NOT the bead's broken `[c⁴, -2c³s, √6c²s², -2cs³, s⁴]`
   signs. Leakage (entries 5,6,7) ≤ 1e-14.
3. **Column 0 at δ∈{π/3, -π/4, 2π−10⁻¹⁰}.** Same shape, against Wigner
   d²(δ) column 0 computed analytically (tests own the closed-form).
4. **Rz consistency** (regression guard for shared infra). `q.φ += π/2`
   on |s⟩ for s∈{0..4}: phases should be `exp(-iπ/2·(j-s))`.
5. **Ry+Rz mixed composition.** `q.θ += δ₁; q.φ += δ₂; q.θ += δ₃` on |0⟩;
   compare to analytic `exp(-iδ₃Ĵ_y)·exp(-iδ₂Ĵ_z)·exp(-iδ₁Ĵ_y)|0⟩` up to
   a single global phase (extract via first nonzero amplitude).
6. **Periodicity.** `q.θ += 2π` is identity on the spin-j=2 (integer-j)
   irrep (up to global phase); assert amplitude ratio to input = global
   phase, |ratio|=1 to 1e-12, same ratio across all 5 components.
7. **Controlled-Ry under `when`.** Allocate QBool `c`, QMod{5} `q=|0⟩`.
   Put `c` in `|+⟩`. Inside `when(c) q.θ += π/3`. Measure `c` in X-basis
   and check the conditional state on `q` for the two outcomes matches
   analytic `exp(±iπ/3Ĵ_y/2)`-averaged — or the chosen phase convention
   from §4. Include a test that FIXES the phase convention so future
   changes can't silently flip it.
8. **Leakage dedicated test.** Prep `q` in `|0⟩`; apply 10 randomised
   θ/φ primitives; sum of |amp|² on labels 5,6,7 ≤ 1e-12.
9. **Int(q) distribution.** Prep `q=|0⟩`; `q.θ += π/4`; sample Int(q)
   N=10000 times; χ² against [0.531, 0.364, 0.0938, 0.0107, 0.00046]
   (|amps|²); Bonferroni-safe tolerance.
10. **d ∈ {4, 6, 7, 8}** calls `q.θ += δ` still errors loudly with the
    d=4-follow-on-bead pointer for d=4, and a d≥6-bead pointer for others.
    d=3 and d=5 must succeed.
11. **Gate-count regression.** Wrap with TracingContext; assert exactly
    30 pre-lowering ops (20 CX + 10 CRy) per `q.θ += δ` at d=5. Locks the
    decomposition choice; any future re-derivation must update explicitly.
12. **Per-pair polarity.** For each of the four Givens pairs (0,1),(1,2),
    (2,3),(3,4): apply ONE Givens at θ=0.3 against the target 8×8 block
    unitary; L∞ error ≤ 1e-12. This catches the §3 polarity risk pair-by-
    pair.

## §6 Risks and edge cases

 * `atan2` at δ = ±2π: sin(δ/2)=0, cos(δ/2)=±1. All five fixed Ry_j(±π/2)
   angles are δ-independent — no atan2 branch issue there. No concern.
 * Integer overflow in `δ·2^i`: K=3, max shift 4, fine in `Float64`.
 * Workspace ancilla under outer `when(ctrl)`. A `:crry` with 2 explicit
   controls becomes 3 controls inside `when`; `_multi_controlled_gate!`
   allocates ancillas. With 10 `:crry` ops in sequence, each allocates +
   frees its own scratch (`push_control!/pop_control!` is balanced, the
   workspace pool returns the ancilla). Risk: if an ancilla is allocated
   inside a CRy's ctrl-reduction and not freed because an intermediate
   CX aborts (it won't — all CX are unconditional) — none, but pin this
   with a test that asserts the workspace count is restored after a
   `q.θ += δ` under `when`. Also: multiple nested `when`s layer ancillas;
   the existing `_multi_controlled_cx!` path already handles this for
   k8u d=3, so d=5 is no new territory.
 * Floating-point error budget. 44 primitive ops per call; each Ry/CX
   is O(ε_machine) ≈ 2e-16. Additive worst case ~10⁻¹⁴, well under the
   bead's 10⁻¹⁰ tolerance, consistent with the reported 3e-16 full-
   circuit error. Iterating 10 calls should still stay ≤ 10⁻¹³. No issue.
 * Hidden Orkan sign assumption. `apply_ry!`/`apply_rz!` use the
   `exp(-iδ·σ/2)` convention — `_apply_spin_j_ry_d3!` already relies on
   this, so the sandwich does too. Don't silently switch Orkan
   conventions.

## §7 Scope call — split d=4 to a follow-on

**Agree with the split.** Rationale:
 1. csw critical path needs d=5 ONLY (per bead description). Shipping d=5
    unblocks csw immediately; blocking on d=4 delays csw for no reason.
 2. d=4 is a power of 2 — the K=2 binary encoding has NO leakage, which
    means the Givens polarity rules in §3 are simpler (every pair has
    H ∈ {1, 2}, never H=3) and a different decomposition may be cheaper
    (e.g. reuse of native 2-qubit Ry decompositions in the literature).
    Treating d=4 as a separate optimisation opportunity is strictly more
    flexible than shoehorning it into the same pass.
 3. Testing: d=4 requires its own Wigner table (spin-3/2) and test matrix;
    stuffing both into one bead raises review cost without benefit.

Follow-on bead description (suggested): *"QMod{4} Ry via Euler sandwich
(spin-3/2) — dedicated derivation. d=4 is power-of-2 (no leakage
states), so the Givens sequence on the 4×4 subspace is strictly shorter
than d=5 (expect 6 Givens instead of 10). Verify whether a direct
2-qubit Ry decomposition without the sandwich is cheaper before
committing. Tests mirror ixd with Wigner d^{3/2} analytic references."*

REVIEW COMPLETE
