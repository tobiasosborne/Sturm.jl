## 2026-04-23 — Session 57: `ixd` (Sturm.jl-ixd) — QMod{5} Ry via Euler sandwich, orchestrator catches a 1e-8 angle-transcription bug

Claimed `Sturm.jl-ixd` (QMod{d} Ry at d ≥ 4). csw critical-path only
needs d ∈ {3, 5} — k8u shipped d=3, ixd ships d=5. d=4 filed as
follow-on `Sturm.jl-2bf` (power-of-2, no leakage; may beat sandwich
with a simpler direct-Givens decomposition).

### Euler sandwich identity at spin-j

    exp(-iδ Ĵ_y) = Rz_j(π/2) · Ry_j(π/2) · Rz_j(δ) · Ry_j(-π/2) · Rz_j(-π/2)

All five factors are spin-j SU(2) rotations (functor SU(2) → U(2j+1)):
  * `Rz_j(α)` — the δ-dependent middle uses the existing nrs per-wire
    factorisation (K single-qubit Rz's). Reused verbatim.
  * `Ry_j(±π/2)` — δ-INDEPENDENT fixed unitaries; precompute once per d.

Verified numerically to 4e-16 at d=5 for δ ∈ {π/4, π/3, 0.7, −0.5,
0, π}.

### Orchestrator-level pre-dispatch work

Unlike k8u (where I derived d=3 closed form), ixd needed a substantially
heavier orchestrator pass because the sandwich requires a fixed multi-
qubit circuit for Ry_j(π/2) at d=5 (NOT just a pair of angles). I:

  1. Computed `V₅ = d²(π/2)` (5×5 real orthogonal) from the Wigner
     formula (matrix exponential of Ĵ_y in the Bartlett label basis).
  2. QR-decomposed V₅ into 10 adjacent-pair Givens, recording
     `(pair_lo, 2·atan2(b, a))` for each.
  3. Mapped each Givens to a qubit circuit based on Hamming distance
     between the level pair's binary encodings:
       * H=1 → single multi-controlled Ry (controls on the K-1 bits that
         agree between the pair, polarity set to the shared value).
       * H≥2 → forward CX chain from pivot=last-differing-bit to each
         other differing bit, reducing the pair to Hamming-1 in pivot,
         multi-controlled Ry on pivot, uncompute the CX chain.
       * Sign fix (k8u-style): if post-CX lower label has pivot-bit = 1,
         negate θ. (At d=5, both H=2 and H=3 Givens happen to have
         pivot=0 for the lower label, so no negation needed — verified
         numerically.)
  4. Composed the 10-Givens circuit as an 8×8 matrix, verified it matches
     `V₅ ⊕ I_3` (leakage labels 5, 6, 7 identity) to 3e-16.
  5. Composed the full sandwich against `exp(-iδĴ_y) ⊕ I_3` — match to
     machine epsilon on the d=5 subspace modulo a known global phase
     `ξ(δ) = exp(iδ[j − (2^K−1)/2]) = exp(-1.5iδ)` (same kind of
     controlled-phase observable as the nrs Rz path; §8.4 policy).

### 3+1 round

Dispatched 2 reviewer proposers (narrower scope than k8u since
orchestrator did the derivation). Key findings:

  * **Both confirm** Euler sandwich algebra and sign conventions.
  * **Both confirm** the bead's "expected formula"
    `[c⁴, −2c³s, √6 c²s², −2cs³, s⁴]` for d²(π/4) col 0 has WRONG signs
    on odd-m rows. Actual column 0 is ALL POSITIVE:
    `(0.7286, 0.6036, 0.3062, 0.1036, 0.0214)`. Tests use numerical
    Wigner as ground truth.
  * **Both spot-check** one Givens op (pair indices 3 and 2) successfully.
  * **Both flag** H=2 pair (1,2) and H=3 pair (3,4) as highest-risk
    untested cases — orchestrator adds a "full d²(δ) matrix match on all
    5 columns" test to cover them end-to-end.
  * **Both agree** on accepting the `ξ(δ) = exp(-1.5iδ)` controlled
    phase under `when()` (same policy as nrs Rz).
  * **Both agree** on splitting d=4 to a follow-on bead.
  * **A flagged** a (false) precision mismatch that turned out to be a
    product-order interpretation issue — orchestrator brief was
    ambiguous, now corrected in the design docs.

Designs at `docs/design/ixd_design_{A,B}.md`.

### THE 1e-8 BUG THE ORCHESTRATOR CAUGHT (Rule 6 again)

TDD flow: wrote tests first (RED: 247 pass, 8 ixd testsets error — no
d=5 implementation yet). Implemented `_apply_spin_j_ry_d5!`, ran:
**384 pass, 114 fail**. All subspace-preservation, periodicity, random-
sequence, distribution tests PASSED. The AMPLITUDE-MAGNITUDE tests
FAILED with errors up to ~5e-9.

Investigation:
  * At δ=0, sandwich = identity exactly. ✓
  * At δ=π, amplitudes on s=0..3 should be exactly 0 (d²(π) maps
    |0⟩→|4⟩); Sturm gives magnitudes ~1e-8 there. ✗
  * `Ry(+π/2)·Ry(-π/2) = bit-exact identity`. But `Ry(+π/2)` alone
    differs from "expected V₅ col 0" by ~1e-9. The pair is internally
    self-consistent — meaning Sturm was computing SOME unitary that's
    perfectly invertible, just NOT V₅.

Root cause: **the hardcoded const `_RY_J_HALFPI_D5_OPS` had angles that
were 1.5e-8 off from the true QR-computed values**. I had transcribed
16-digit decimals from an early print statement whose source later lost
precision through some refactor path (or I hallucinated digits). Fresh
QR-produced angles match to Float64 bit precision; the stored const did
not.

Fix:
  * Replaced the const with full-precision Float64 literals via `repr(θ)`.
  * Added a regression test that recomputes V₅ from the Wigner formula
    and Givens-decomposes at test time, asserting bit-identical agreement
    with `Sturm._RY_J_HALFPI_D5_OPS`. If a future edit truncates the
    literals, this test fails.

After the fix: **519/519 GREEN** (498 + 21 new ixd testsets).

**Lesson**: when shipping a primitive whose correctness depends on
precomputed numerical constants, write a regression test that recomputes
them and asserts bit-equality. Also: ALWAYS dump to `repr(x)` when
generating Float64 literals, NEVER to `round(x, digits=N)` or similar.
Session 56 (k8u) taught: verify the 4×4/8×8 circuit matrix against the
target BEFORE shipping. Session 57 extends: verify the stored CONSTANTS
match a from-scratch recomputation.

### Implementation

`src/types/qmod_ry_d5.jl` (new, ~170 lines):
  * `const _RY_J_HALFPI_D5_OPS` — 10 (pair_lo, angle) tuples, full Float64
    precision, fixed sequence for Ry_j(+π/2) at d=5.
  * `_givens_block_d5!(ctx, wires, pair_lo, θ)` — emit qubit primitives
    for one Givens. Dispatches on `pair_lo ∈ {0, 1, 2, 3}`, hand-derived
    from Hamming-distance analysis, every branch matched in the
    orchestrator's pre-verified per-block matrix table.
  * `_apply_ry_j_halfpi_d5!(ctx, wires, sign)` — forward or reverse
    dressing (reverse = reversed op order with negated angles).
  * `_apply_spin_j_ry_d5!(ctx, wires, δ)` — the full sandwich.

`src/types/qmod.jl`:
  * `include("qmod_ry_d5.jl")` after `_apply_spin_j_ry_d3!`.
  * `_apply_spin_j_rotation!` dispatcher: `:θ` now branches d=3 / d=5 /
    else-error-with-pointer-to-2bf.

`test/test_qmod.jl` (+~240 lines):
  * 9 new ixd testsets (criterion (a) d²(π/4) col 0, full d²(δ) matrix
    on all 5 columns for 4 δ values, leakage-free 50-random, 2π-periodic,
    when(ctrl) on superposition control, 1000-random subspace
    preservation, Int(q) distribution, hardcoded-angles regression).
  * Updated the d≥4 deferral test to cover d ∈ {4, 6, 7, 8} (d=5 now
    ships; 2bf bead referenced for d=4).

### Files touched

  * `src/types/qmod_ry_d5.jl` — new (170 lines).
  * `src/types/qmod.jl` — dispatcher update, include, docstring.
  * `test/test_qmod.jl` — 10 new testsets (+240 lines).
  * `docs/design/ixd_design_A.md` — new (proposer A's audit).
  * `docs/design/ixd_design_B.md` — new (proposer B's audit).
  * `WORKLOG.md` — this entry.
  * Beads: `ixd` closed; `2bf` (d=4 Ry) created.

Not touched: `src/Sturm.jl` public API, `src/context/*`, other types.

### TDD cycle

  * RED: tests written first, 247 pass + 8 errors (d=5 still stubbed).
  * Implementation added; first run: 384 pass, 114 fail (amplitude bug).
  * Debug trace via `Ry(+π/2)·Ry(-π/2)` → I (self-consistent) vs.
    `Ry(+π/2)` vs. V₅ (off by 1e-9) identified the const as the culprit.
  * Fresh-angle regeneration script found up to 1.5e-8 discrepancy in
    the stored const.
  * Fixed const → **519/519 GREEN on second run**.

Adjacent-test sanity (Rule 9): `test_primitives` 711/711,
`test_when` 507/507, `test_qint` 562/562, `test_ptrace` 9/9,
`test_autocleanup` 14/14, `test_implicit_cast` 14/14. 1817 adjacent +
519 qmod = 2336 clean assertions, **zero regressions**.

### `when()` composition analysis

Under `when(ctrl) do q.θ += δ end` at d=5:
  * ctrl=0 branch: identity on q.
  * ctrl=1 branch: full sandwich = ξ(δ)·exp(-iδĴ_y). Relative phase
    between branches = ξ(δ) = exp(-1.5iδ). Observable and δ-dependent.

This is the SAME kind of controlled-phase observable as the nrs Rz path
at d=5 (§8.4 policy). It's `-1.5` at d=5 vs. `j` at a generic d for Rz
— both are known, documented, compile-time-predictable, and unavoidable
without paying extra gates for phase cleanup.

### What's unlocked / what's next

  * **`Sturm.jl-csw`** (full-pipeline qudit tests at d=3, d=5) — now
    unblocked on the Ry side. csw also needs primitive `q.θ₂` (squeezing),
    `q.θ₃` (cubic phase), SUM at d>2, and library gates X_d/H_d/F_d/T_d.
  * **`Sturm.jl-os4`** (squeezing `q.θ₂`) — diagonal primitive, same
    pattern as nrs Rz. Unblocked.
  * **`Sturm.jl-mle`** (cubic-phase magic `q.θ₃`) — same pattern as os4.
  * **`Sturm.jl-p38`** (SUM `a ⊻= b` at d > 2) — independent. Unblocked.
  * **`Sturm.jl-2bf`** (d=4 Ry) — follow-on filed this session;
    orchestrator MUST numerically verify before shipping (mandate baked
    into bead description per k8u/ixd learnings).

### `bd dolt push` STATUS

Same secret-scanning URL as Sessions 51-56. Local beads this session:
`ixd` closed, `2bf` created.

---

## 2026-04-23 — Session 56: `k8u` (Sturm.jl-k8u) — QMod{3} Ry shipped, orchestrator catches a sign bug both proposers missed

Claimed `Sturm.jl-k8u` (QMod{d} Ry rotation — the θ-axis follow-on from
nrs, which shipped Rz at all d but deferred Ry because neither nrs
proposer closed the decomposition math). Full 3+1 round in one session.

### Orchestrator does the hard physics BEFORE dispatching proposers

Rather than dispatch proposers blind and hope one would close the
decomposition, I **derived and numerically verified the d=3 closed form
myself** first, then gave it to both proposers as ground truth:

    d¹(δ) = G_{01}(2γ) · G_{12}(2β) · G_{01}(2γ)
    γ = atan2(sin(δ/2),                √2 · cos(δ/2))
    β = atan2(sin(δ/2)·√(2−sin²(δ/2)),  cos²(δ/2))

Matches Wigner d¹(δ) to 1.1e-16 across δ ∈ {π/3, π/4, ±π/2, ±π, 2.718,
0, 2π−10⁻¹⁰}. First attempt used `acos(c²)` for β — failed at δ < 0
because `acos` returns [0, π] regardless of sign. Fix: signed `atan2`
with denominator `cos²(δ/2)` and numerator `sin(δ/2)·√(2−sin²(δ/2))`.
Plain `atan`/`acos` DO NOT work; `atan2` is mandatory. (Rule 3/4 —
physics claim has an algebraic derivation + numerical ground truth.)

Proposers got the closed form in the brief, were told to **independently
verify** (show one matrix-element algebra step). Both did — A verified
`M[1,1] = cos δ` via `(2c⁴−s²)/(1+c²) = 2c²−1`; B verified two entries
(`M[1,1]` and `M[0,0]`) plus the m↔−m Z₂ symmetry argument for why the
outer Givens angles must be equal. Both confirmed atan2 necessity.

### Strong convergence across the two proposers

Both designs land at `/tmp/k8u_design_{A,B}.md` (394 + 409 lines);
copied to `docs/design/k8u_design_{A,B}.md` for durability.

  * **d=3**: both adopt the orchestrator's closed form directly. Both
    adopt the same qubit-circuit decomposition (G_{01}: Ry(π) bracket +
    controlled-Ry; G_{12}: CX-scratch + controlled-Ry + CX-scratch).
    10 Ry + 8 CX per `q.θ += δ` at d=3.
  * **d=5**: both picked **Option S (Euler sandwich)** —
    `exp(−iδĴ_y) = W · exp(−iδĴ_z) · W†` with `W = exp(−iπ/2 Ĵ_x)` a
    δ-INDEPENDENT spin-j unitary. Outer dressing precomputed once at
    module init via Brennen-Bullock-O'Leary QR of d^j(π/2) into adjacent
    Givens; middle is the existing nrs Rz path (K gates). Rejected
    Option D (direct Givens with δ-dependent angles at d=5) as
    per-call-expensive and brittle.
  * **d=3 G_{12} CX direction**: A explicitly flagged this as a latent
    bug in prior proposer designs — must be `CX(w_l → w_m)` not the
    reverse. B derived the same direction after a mid-doc correction.

### THE BUG BOTH PROPOSERS MISSED (Rule 6 in action)

Both proposers wrote the G_{12} qubit circuit as:

    apply_cx!(ctx, w_l, w_m)
    _controlled_ry!(ctx, w_m, w_l, 2β)    # ← WRONG ANGLE SIGN
    apply_cx!(ctx, w_l, w_m)

and claimed it realises G_{12}(2β). It does not. I wrote a Julia
verification script building the 4×4 qubit unitary of that circuit and
comparing against the target `I ⊕ G_{12}(2β)` (identity on |00⟩, |11⟩;
2D rotation on {|01⟩, |10⟩}):

    β=0.3     ||circuit − G_{12}(+2β)||_∞ = 0.591
              ||circuit − G_{12}(−2β)||_∞ = 0.0  ←

The circuit realises **G_{12}(−2β)**, not G_{12}(+2β). Fix: pass `−2β`
to `_controlled_ry!`. Then the FULL d=3 decomposition passes:

    δ=π/3   ||U[subspace] − d¹(δ)||_∞ = 1.11e-16     |11⟩ fixed to 1.0
    δ=π/4   = 1.11e-16                               |11⟩ fixed
    δ=−π/2  = 1.11e-16                               |11⟩ fixed
    …       all machine-epsilon

This is exactly the hazard CLAUDE.md Rule 6 warns about: quantum bugs
are deep and interlocked. A sign error in a 2-level rotation inside a
CX-scratch would have passed "|11⟩ stays empty" unit tests (still does —
the fix preserves subspace), but CORRUPTED every downstream amplitude
by up to 0.6 in ℓ∞. Without numerical verification of the qubit-circuit
4×4 unitary against its target, we would have shipped a broken primitive
that looked correct in leakage-style tests.

**Lesson for ixd implementer** (d ≥ 4 follow-on): when lowering any
Givens block to a qubit circuit, VERIFY the 2^K × 2^K matrix
numerically against the target before integration. The BBO Thm. 3
ancilla-based constructions for d=5 have more room for sign errors.
Baked into the ixd bead description as an explicit orchestrator check.

### Why ship d=3 only, defer d=5 to `ixd`

The bead originally asked for both d=3 and d=5. I split and filed
`Sturm.jl-ixd` (d ≥ 4 Ry via the sandwich) because:

  1. Rule 1 (fail loud, not quietly-wrong). d=3 decomposition now has
     orchestrator-level numerical verification. d=5 requires a new
     Givens QR on d^2(π/2) + multiple Hamming-≥2 CX-scratch routes that
     NEITHER proposer fully spelled out — shipping both at once risks
     repeating the sign bug at bigger scale.
  2. The d=3 sign bug is exactly the evidence this risk is real. If I
     missed a sign in the 3 Givens at d=3 (where I verified every step
     on paper), the 10+ Givens at d=5 would have more.
  3. Matches the Session 55 (`nrs`) precedent — ship one d-class cleanly,
     defer the other with a clear follow-on bead. The consumers (csw
     acceptance, library gates X_d/H_d/F_d) can proceed against d=3 now.

### Implementation

`src/types/qmod.jl` +~100 lines:
  * New `_apply_spin_j_ry_d3!(ctx, wires::NTuple{2, WireID}, δ)` helper
    (+docstring with the algebraic identity, the atan2 convention, the
    sign-fix note, and the gate-count breakdown).
  * Dispatch added to `_apply_spin_j_rotation!`: `:θ` now branches on d
    (d=3 → helper; d ≥ 4 → error with pointer to `Sturm.jl-ixd`).

Critical dispatch detail: **use `push_control!`/public `apply_ry!`/
`pop_control!` — NOT `_controlled_ry!` directly**. The latter wraps in
`with_empty_controls`, which would DROP any outer `when(ctrl)` control
from the stack. Using the public `apply_ry!` at non-empty stack lets
the context dispatcher (`src/context/eager.jl:141–151`) lift through
all outer controls via `_multi_controlled_gate!`. This gave the correct
semantics for `when(outer_ctrl) q.θ += δ` — verified by the test that
checks Bell-shaped control on a QMod{3} target (full 8-amp statevector
match).

`test/test_qmod.jl` +~175 lines:
  * 9 new k8u testsets (criterion-(a) d¹(π/3) column 0; full-matrix
    check across 3 columns × 6 δ values; 50-random-Ry leakage; 2π-
    periodicity; mixed Ry+Rz analytic comparison; when(ctrl)-on-Bell;
    1000-random subspace preservation; Monte-Carlo distribution of
    Int(q) over N=4000; d=2 BlochProxy regression).
  * Updated the ak2 deferral test from "d ∈ {3, 4, 5, 8}" to
    "d ∈ {4, 5, 8}", pointing at `Sturm.jl-ixd` instead of `k8u`.
  * Added `using LinearAlgebra` at file top (needed for `Diagonal` in
    the mixed-rotation analytic test).

### TDD cycle

Tests written FIRST (Rule 10): 145 pass / 3 fail / 8 error on the first
run (RED) — errors from `:θ` still stubbed; the 3 failures from the
updated ak2 test expecting "Sturm.jl-ixd" in an error that still said
"Sturm.jl-k8u". After implementing the helper + dispatch: **244/244
GREEN** on first try. The sign fix was applied BEFORE testing (caught
at orchestrator synthesis via the 4×4 numerical check), so no
red-green-red cycle was needed for the subtle physics bug.

Adjacent-test sanity (Rule 9): `test_primitives` (711/711),
`test_when` (507/507), `test_qint` (562/562), `test_implicit_cast`
(14/14), `test_ptrace` (9/9), `test_autocleanup` (14/14). **1817
adjacent + 244 qmod = 2061 clean assertions, zero regressions.**

### `when()` composition cleanliness

Per proposer convergence + orchestrator verification: `exp(−iδĴ_y)` has
det = 1 on the spin-j irrep (Ĵ_y is traceless), so unlike the Rz path
there is NO SU(d) vs U(d) global-phase cost to pay under control. The
`Ry(±π)` brackets inside G_{01} cancel identically (`Ry(π) · Ry(−π) = I`
exactly in SU(2), not just up to phase), and this cancellation survives
control-stack lifts because `C-U · C-U⁻¹ = C-I = I`. Verified by the
"when(::QBool) q.θ += π/3 on superposition control" test — all 8
amplitudes match the ideal Bell-split product state to 1e-10.

### Files touched

  * `src/types/qmod.jl` — +~100 lines (new helper + dispatch).
  * `test/test_qmod.jl` — +~175 lines (9 new testsets + ak2 update +
    `using LinearAlgebra`).
  * `docs/design/k8u_design_A.md` (new, 394 lines, durable copy of
    proposer A).
  * `docs/design/k8u_design_B.md` (new, 409 lines, durable copy of
    proposer B).
  * `WORKLOG.md` — this entry.
  * Beads: `k8u` closed; `ixd` (d ≥ 4 Ry) created.

No edits to `src/Sturm.jl` (helper is internal — no new export),
`src/types/qbool.jl` (Rule 11 frozen), `src/context/*.jl` (no new
primitives needed), `src/primitives/`, or any other user-facing file.

### What's unlocked / what's next

  * **csw acceptance** — can now proceed against d=3 Ry. The d=5
    requirement blocks on `ixd`.
  * **u2n library gates at d=3** — `X_d!`, `H_d!`, `F_d!`, `T_d!`,
    `QuditToffoli!` at d=3 now have both their Ry and Rz primitives.
  * **`Sturm.jl-ixd`** (d ≥ 4 Ry) — sandwich approach, proposer-
    convergent design already in the bead description. Critical-path
    follow-on. Bead description includes the "MUST numerically verify
    every Givens block's qubit-lowering before integration" mandate
    that caught the d=3 sign bug.
  * **`Sturm.jl-os4`** (squeezing `q.θ₂`) — diagonal primitive; reduces
    to per-wire factorisation like the nrs Rz path. Unblocked.
  * **`Sturm.jl-mle`** (cubic-phase magic `q.θ₃`) — same pattern as os4.
  * **`Sturm.jl-p38`** (SUM `a ⊻= b` at d > 2) — independent of both
    nrs and k8u. Unblocked.

Recommendation: `ixd` is critical-path for csw; os4/mle/p38 are
independent easy wins. Either order works; I'd start `ixd` next to
unblock csw fastest.

### `bd dolt push` STATUS

Will attempt this session after local commit. GH secret-scanning on
the historical OAuth blob has been the blocker for Sessions 51-55.

---

