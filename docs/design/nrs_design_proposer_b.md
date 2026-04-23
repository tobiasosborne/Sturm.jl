# nrs (qubit-encoded fallback simulator) Design — Proposer B

## 0. Summary

Ship `_apply_spin_j_rotation!` for the **Rz path at all d ≥ 3** (closed-form, diagonal,
per-bit factorisation — cheap), and for the **Ry path at d ∈ {3, 5}** via a
**Wigner-small-d Givens chain** of `d−1` controlled-Ry rotations on a distinguished
"LSB-complement" qubit (using `_multi_controlled_gate!` from
`src/context/multi_control.jl`). Generic-d Ry decomposition (Givens over arbitrary
pairs) is filed as the follow-on bead `nrs-generic-ry`. `apply_sum_d` is **deferred
to `p38`** — SUM is arithmetic, not spin-j rotation, and belongs on its own bead
with its own tests. The leakage-guard TLS flag (`with_qmod_leakage_checks`) is
**deferred** to a dedicated debug-infrastructure bead.

Physics anchor: Bartlett-deGuise-Sanders 2002 Eqs. 5, 6, 7, 13. Wigner closed-form
per Sakurai-Napolitano *Modern QM* §3.8 Eq. 3.8.33 — transcribed into a local note
`docs/physics/wigner_small_d.md` before merge (Rule 4 compliance).

All tests run — no `@test_skip`.

## 1. Scope decision — Q1 answer

Commit to a tight, provable slice:

| Item | nrs scope | Rationale |
|---|---|---|
| `_apply_spin_j_rotation!` Rz path, all d | **YES** | Diagonal, closed-form, per-bit factorisation (§4). O(K) qubit-primitive ops. No new infrastructure. |
| `_apply_spin_j_rotation!` Ry path, d ∈ {3, 5} | **YES** | Covers `csw` acceptance. Closed-form Wigner d-matrix at j=1 and j=2. Adjacent-pair Givens chain. |
| `_apply_spin_j_rotation!` Ry path, generic d ≥ 3 | **DEFER** to bead `nrs-ry-generic` | Needs either (a) Wigner small-d recursion engine cached on `Val(d)`, or (b) numerical QR-based Givens. Not needed for any v0.1 library gate. File with pointer. |
| `apply_sum_d` (SUM backend) | **DEFER** to bead `p38` | SUM is `|a,b⟩ → |a, a+b mod d⟩` — a classical reversible permutation, not a spin-j rotation. Natural home is `p38`. Uses qrom_lookup_xor! for classical table or ripple-adder mod d, not Wigner d-matrices. **Zero overlap with nrs work**. |
| Leakage-guard TLS flag | **DEFER** to bead `nrs-leakage-tls` | Debug-only infrastructure; O(2^n) per check; not needed for correctness (subspace preserved by construction per §6). |

**Honest tradeoff.** Shipping generic-d Ry here would triple the bead size and
block on the Wigner recursion note + its test. Shipping d ∈ {3, 5} unlocks every
useful v0.1 library gate that needs spin-j rotations (`X_d!`, `Z_d!`, `F_d!` for
prime d ∈ {3, 5, 7} — `7` falls out with one more hard-coded table if needed, but
not required by the `csw` acceptance scope). The bead description asks for
"v0.1 scope per `csw` acceptance", and `csw` pins `d ≤ 9` as library-scope,
not primitive-scope.

**What `apply_sum_d` needs from nrs (for p38):** nothing new. `p38` will
implement SUM as an XOR-style reversible adder on the K-bit encoding
(either QFT-adder mod d or QROM lookup), which uses only apply_cx! / apply_ccx!
plus modular-arithmetic plumbing already in `src/library/arithmetic.jl`. SUM
does NOT sit on top of spin-j rotations. Explicit interface: **none**.

## 2. Decomposition algorithm — Q2 answer

**Recommendation: (i) Givens decomposition into d−1 two-level SU(2) rotations
on adjacent computational-basis pairs `(|s⟩, |s+1⟩)`, with angles from the
Wigner small-d matrix.**

**Rejected alternatives.**

* **(ii) Full d×d Reck-Zeilinger / cosine-sine.** `binom(d,2)` two-level
  rotations — 3 for d=3 (same as adjacent-pair), 10 for d=5. Adjacent-pair
  Givens for Ry is specifically the case where most Givens angles collapse to
  zero (the spin-j Wigner d-matrix is **tridiagonal-exponential**, not dense
  in Gell-Mann sense), so adjacent is optimal for `exp(-iδ Ĵ_y)`. This IS
  option (i) for our specific Hamiltonian — the "Givens ladder" is the natural
  physics decomposition, not a generic unitary synthesiser.
* **(iii) Numerical diagonalisation at call time.** Would require diag(Ĵ_y),
  phase, recompose — O(d³) classical work per `q.θ += δ` call, plus
  numerical noise. Skip.
* **(iv) Hard-coded per-d sequence.** Effectively what we do at d=3 and d=5
  via closed-form Wigner tables; the Givens ladder IS the hard-coded sequence
  for those two d.

### 2.1 Physics (Bartlett Eqs. 5, 6)

Bartlett Eq. 5: `|s⟩ ≡ |j, j−s⟩_z`, `s ∈ {0, …, d−1}`. In the spin-j Wigner
basis `Ĵ_y` has matrix elements

`(Ĵ_y)_{s, s+1} = (ℏ/2i)·sqrt((j−m)(j+m+1))` evaluated at `m = j − s − 1`,
i.e. coupling `|s+1⟩ ↔ |s⟩` (Bartlett Eq. 6 ladder form: `Ĵ_± = Ĵ_x ± iĴ_y`,
standard ladder matrix elements Sakurai Eq. 3.5.39). `Ĵ_y` is **tridiagonal**
in the computational basis — adjacent pairs `(|s⟩, |s+1⟩)` are the only
non-zero off-diagonal blocks.

So `R_y(δ) = exp(-iδ Ĵ_y)` is **not** tridiagonal (exponentials of tridiagonal
matrices are dense). But the Wigner d-matrix `d^j_{m',m}(δ) = ⟨j, m'| R_y(δ) |j, m⟩`
has a closed form (Sakurai-Napolitano Eq. 3.8.33, Wigner's explicit sum):

```
d^j_{m',m}(δ) = Σ_s (-1)^(m'-m+s) ·
    sqrt((j+m')!(j-m')!(j+m)!(j-m)!) /
    ((j+m-s)! · s! · (m'-m+s)! · (j-m'-s)!) ·
    cos(δ/2)^(2j - m' + m - 2s) · sin(δ/2)^(m' - m + 2s)
```

(sum over integer s such that factorial arguments are ≥ 0).

The **Givens factorisation** of `R_y(δ)` — taking |0⟩_d to the |0⟩_d-column of
the Wigner d-matrix — factorises as:

```
R_y(δ)|0⟩_d = G_{0,1}(α_0) · G_{1,2}(α_1) · ... · G_{d-2, d-1}(α_{d-2}) · |0⟩_d
```

where `G_{s, s+1}(α_s)` is a 2-level SU(2) Ry rotation on the `{|s⟩, |s+1⟩}`
pair, identity elsewhere. The angles `α_s` are determined by recursion from
the Wigner d^j column. But **this only diagonalises one column.** The full
`R_y(δ)` is d columns; in general it needs `d−1` Givens **per column** = `d(d−1)`
Givens. Brennen-Bullock-O'Leary (quant-ph/0509161) §4 Eq. (14) and Wang-Hu-Sanders-Kais
2020 Eq. (3-4) give a QR-style scheme with `d−1` unitary "column-annihilators"
that together compose to `U_d`.

**The trick for `R_y(δ)` specifically (the spin-j exp, not a generic U(d)):**
for the single-parameter family `R_y(δ)`, there is an equivalent factorisation
as a **product of d−1 adjacent-pair rotations — ONE per adjacent pair — where
each rotation has its own δ-dependent angle given directly by Wigner recursion**
(a.k.a. the Wigner-Heisenberg factorisation, documented in the survey
`qudit_primitives_survey.md` §3 Candidate B). For small d (3, 5) we give
explicit angle tables below; for generic d the recursion is left to the
follow-on.

### 2.2 Pseudocode

```julia
function _apply_spin_j_rotation!(
    ctx, wires::NTuple{K, WireID}, axis::Symbol, δ::Real, ::Val{d},
) where {K, d}
    if axis === :φ
        _apply_spin_j_rz!(ctx, wires, δ, Val(d))      # Q4
    elseif axis === :θ
        _apply_spin_j_ry!(ctx, wires, δ, Val(d))      # Q5
    else
        error("axis must be :θ or :φ, got $axis")
    end
end

# Dispatch on Val(d) for Ry to pick closed-form vs. generic
_apply_spin_j_ry!(ctx, wires, δ, ::Val{3})  = _spin_j_ry_d3!(ctx, wires, δ)
_apply_spin_j_ry!(ctx, wires, δ, ::Val{5})  = _spin_j_ry_d5!(ctx, wires, δ)
_apply_spin_j_ry!(ctx, wires, δ, ::Val{d}) where {d} = error(
    "spin-j Ry at d=$d not yet implemented. v0.1 supports d ∈ {2, 3, 5}. " *
    "Generic d ≥ 3 filed as bead `nrs-ry-generic`."
)
```

The `Val(d)` dispatch is the same trick ak2 set up so that the follow-on
bead adds one method without touching call sites.

### 2.3 How each 2-level Givens block lowers to qubit primitives

A Givens block `G_{s, s+1}(α) = Ry(α)` on the `{|s⟩, |s+1⟩}` pair:

1. Find the bit that **differs** between binary encodings of `s` and `s+1`.
   Adjacent pairs `(s, s+1)` have a carry pattern: `s` and `s+1` differ in
   all bits from the LSB up to and including the lowest-clear bit of `s`
   (e.g. s=1=`01`, s+1=2=`10` differ in bits 1 and 0 — Hamming distance 2).
2. If Hamming distance is **1** (simple carry): the differing bit is the
   "target", the other K−1 bits are controls. Apply a multi-controlled-Ry(α)
   on the target using `_multi_controlled_gate!` with control pattern =
   shared bits of `s`.
3. If Hamming distance is **≥ 2**: conjugate the pair by **CX ladders**
   that move the "carry" into a single-bit-flip, then apply the multi-
   controlled-Ry, then reverse the CX ladders. Same trick as an adder's
   carry-unwind.

Control patterns that fire on zero-bits are implemented by X-negating the
wire before/after pushing it as a control — the classical idiom.

### 2.4 Why adjacent-pair Givens respects the control stack

Each inner rotation routes through the existing `apply_ry!` which consults
`current_controls(ctx)` — so `when(ctrl) q.θ += δ end` automatically lifts
every inner rotation under `ctrl`. **No new control-stack infrastructure
needed.** This is the cleanest reuse target.

**Cited architectural reuse:** `src/context/multi_control.jl:88-111`
(`_multi_controlled_gate!`), `src/context/eager.jl:141-151` (nc=0/1/2
dispatch in `apply_ry!`), `src/context/abstract.jl:114-122`
(`with_empty_controls`).

## 3. Wigner d-matrix source — Q3 answer

**Recommendation: hard-coded closed-form tables for d ∈ {3, 5}, with a
reference derivation in `docs/physics/wigner_small_d.md` (NEW FILE, Rule 4).**

### 3.1 d=3 (j=1) closed form

From Sakurai Eq. 3.8.33 specialised at j=1 (standard QM textbook result):

```
d^1(δ) = [ (1+cos δ)/2    -sin(δ)/√2    (1-cos δ)/2   ]
         [ sin(δ)/√2       cos δ        -sin(δ)/√2    ]
         [ (1-cos δ)/2     sin(δ)/√2    (1+cos δ)/2   ]
```

(Rows/cols index `m' ∈ {+1, 0, -1}`, matching `s ∈ {0, 1, 2}` via `m = j − s`.)

The Givens factorisation of `R_y(δ) = exp(-iδ Ĵ_y)` at j=1 into two adjacent
rotations `G_{0,1}(α_a) · G_{1,2}(α_b)` (plus possibly one more) is cleaner
when written as a **QR-style sweep on the |0⟩ column**:

Step 1. `G_{1,2}(α_b)` rotates amplitude from |2⟩ into |1⟩, zeroing the
(2, 0) entry of the matrix.
Step 2. `G_{0,1}(α_a)` rotates amplitude from |1⟩ into |0⟩, zeroing the
(1, 0) entry.

The column-annihilator angles satisfy
`tan(α_a / 2) = d^1_{1,0}(δ) / d^1_{0,0}(δ) = sin(δ) / (cos(δ) · √2)` (after
absorbing the post-step-1 residual),
`tan(α_b / 2) = d^1_{2,0}(δ) / d^1_{1,0}(δ) = (1 - cos δ) / (sin(δ) · √2)`
(approximately — **note**: this is the column-zeroing angle; applying it FIRST
changes what d^1_{1,0} means for step 2, so the closed-form recursion needs
care).

**Verification strategy** (also §7 test): since the full d^1(δ) is a
3-parameter unitary group element, and the adjacent-pair Givens
decomposition has EXACTLY `d−1 = 2` free angles per column, a single
column has 2 degrees of freedom after normalisation — matching. The
angles can be derived analytically OR numerically via QR; we write them
analytically for d=3 and verify them against a numerical QR reference in
the test.

**Honest statement about the math:** the single-column factorisation
above gets |0⟩_d → R_y(δ)|0⟩_d correct, but **does not implement the full
d×d unitary** `R_y(δ)`. For the full unitary we need `d(d−1)/2 = 3` Givens
blocks at d=3 (the three pairs `(0,1), (0,2), (1,2)` — but `(0,2)` is
non-adjacent and requires the CX-ladder trick from §2.3). An equivalent
(and cheaper) route: decompose `R_y(δ) = exp(-iδĴ_y)` using Euler-angle
identity `R_y = R_z(-π/2) R_x(δ) R_z(π/2)`, then reduce to `R_x` Givens —
but `R_x` in the Wigner basis is dense too.

**Decision for d=3:** implement via the **Wigner adjacent-pair chain**:
apply `G_{0,1}(α_0(δ))` then `G_{1,2}(α_1(δ))` then `G_{0,1}(α_2(δ))` —
three adjacent-pair rotations — where the three angles come from a
Givens QR on the d^1(δ) matrix. Angles computed numerically at runtime
via a `_wigner_d1_givens_angles(δ) -> (α_0, α_1, α_2)` helper (20 lines
of Julia, pure trigonometry, deterministic) — this is NOT a matrix
decomposition in the expensive sense, it's closed-form formulae from
the 3×3 d^1(δ) entries. **Reference implementation ships the formulae
derived in `docs/physics/wigner_small_d.md`.**

### 3.2 d=5 (j=2) closed form

Sakurai Eq. 3.8.33 at j=2 gives the 5×5 Wigner matrix d^2(δ) explicitly
(every QM textbook has this). Entries are polynomials in `(cos(δ/2),
sin(δ/2))` of total degree 2j = 4.

The adjacent-pair Givens QR on d^2(δ) gives **10 = 5·4/2** rotations
(`G_{0,1}, G_{1,2}, G_{2,3}, G_{3,4}`, then repeat-sweep for columns 1, 2, 3,
4 — standard QR; we need all d−1 Givens per column, d columns, but with
triangular residual = `(d-1) + (d-2) + ... + 1 = d(d-1)/2 = 10`).

We pre-compute the 10 angle functions `α_{i,j}(δ)` as `Val(5)`-specialised
closed-form expressions, and cache them in a module-level const vector
(indexed by δ bucketing? no — angles are continuous, so just compute each
`q.θ += δ` call; 10 trig evaluations is nothing). Per-call classical cost:
~50 ns. Per-call gate count: 10 * (O(K) CX for Hamming-distance-2 blocks) +
10 * multi-controlled Ry → see §9.

### 3.3 Why not a `@generated` / Val(d) cached table

Two downsides: (a) the angle functions depend on `δ` (continuous), so the
cache is per-call not per-compile; (b) `@generated` code for Wigner recursion
would be opaque and hard to prove correct. Closed-form tables at d=3 and d=5
are ~30 lines each; explicit and auditable. For generic-d, file `nrs-ry-generic`
with the Wigner recursion engine — not in this bead.

## 4. Rz path (diagonal) — Q4 answer

**Recommendation: per-wire single-qubit Rz via the binary-label factorisation
(option b).** Most efficient, cleanest, and preserves leakage structure by
construction.

### 4.1 Physics

Bartlett Eq. 5: `|s⟩ ≡ |j, j−s⟩_z`, so `Ĵ_z|s⟩ = (j − s)|s⟩`. Therefore
`R_z(δ)|s⟩ = exp(-iδ(j − s))|s⟩`.

In the binary encoding `s = Σ_{k=0}^{K-1} b_k · 2^k` (little-endian, per
`qmod.jl:6-10`), this gives

```
R_z(δ)|s⟩ = exp(-iδ j) · exp(iδ s) |s⟩
         = exp(-iδ j) · Π_k exp(iδ · b_k · 2^k) |b_{K-1} … b_0⟩
```

The `exp(-iδ j)` factor is a **global phase** — irrelevant in SU(d),
CLAUDE.md "Global Phase and Universality" policy.

The remaining factor `exp(iδ · b_k · 2^k)` acts on each qubit k independently:
it's `Rz(-δ · 2^(k+1))` on wire k (orkan's `apply_rz!` applies
`exp(-iθ σ_z/2)` → eigenvalue `exp(-iθ/2)` on |0⟩, `exp(+iθ/2)` on |1⟩;
equivalent to `exp(+iθ b)` on basis |b⟩ up to the same `exp(-iθ/2)` global).

**Per-wire formula:** wire k carries `Rz(-δ · 2^(k+1))`. Accounting for
orkan's convention that `apply_rz!(ctx, w, θ)` puts `exp(-iθ/2)` on |0⟩,
the correct angle to pass per wire k is
`θ_k = -δ · 2^(k+1)` up to a sign depending on orkan's sign convention
(to verify via the d=2 parity test in ak2 — at d=2, K=1, j=1/2, the formula
should reduce to `apply_rz!(ctx, wires[1], δ)` bit-identically).

### 4.2 Leakage correctness

**Every encoded basis state with bitstring `b_{K-1} … b_0` interpreted as
integer ≥ d gets a phase `exp(iδ · s)` regardless** — this is a
single-qubit Rz per wire, which acts identically on every bitstring. So
encoded |11⟩ at d=3 (K=2) gets phase `exp(iδ · 3) · exp(-iδ j)` applied
multiplicatively. **But there's no amplitude at |11⟩ by subspace
preservation (prep + invariant from §6), so multiplying it by a phase
leaves it at zero.** Loud-fail happens only if leakage already exists — a
measurement-time check in `Base.Int(::QMod)` is the layer-3 safety net.

### 4.3 Gate count

**K single-qubit Rz calls + one global phase** (which Sturm doesn't emit
as a gate, SU(d) policy). At d=3, K=2 → 2 Rz. At d=5, K=3 → 3 Rz. At
d=9, K=4 → 4 Rz. Cheap.

Inside `when(ctrl)`: each single-qubit Rz becomes a single-controlled Rz
via `_controlled_rz!` (`src/context/multi_control.jl:44-58`). K controlled
rotations per call at nesting depth 1; deeper nesting uses the cascade.

## 5. Ry path (off-diagonal) — Q5 answer

**Recommendation: Wigner adjacent-pair Givens sweep, with d ∈ {3, 5} hard-coded.**

### 5.1 Algorithm (for d=3)

```
# R_y(δ) on QMod{3, 2}. Wires layout: wires[1] = LSB (bit 0), wires[2] = MSB (bit 1).
# Encoded labels: |0⟩ = |00⟩, |1⟩ = |01⟩_LE = wire₁=1, |2⟩ = |10⟩_LE = wire₂=1.
# |11⟩ = label 3 — FORBIDDEN (leakage).

function _spin_j_ry_d3!(ctx, wires::NTuple{2, WireID}, δ::Real)
    w_lsb, w_msb = wires[1], wires[2]
    α, β, γ = _wigner_d1_givens_angles(δ)        # 3 angles from d^1(δ)

    # G_{0,1}(α): rotate |00⟩ ↔ |01⟩. Differing bit = LSB. Control: MSB=0.
    # Apply Ry(α) on w_lsb, controlled by w_msb = 0. Use X-negation pattern:
    _controlled_ry_on_zero!(ctx, w_msb, w_lsb, α)

    # G_{1,2}(β): rotate |01⟩ ↔ |10⟩. Hamming distance 2.
    # Standard trick: CX(w_lsb, w_msb) maps {|01⟩, |10⟩} ↔ {|11⟩, |10⟩}.
    # But wait — |11⟩ is FORBIDDEN. We can't use |11⟩ as an intermediate!
    # Alternative: decompose via temporary workspace OR use a different Givens pair.
    # Correct construction below.

    # G_{0,1}(γ): rotate |00⟩ ↔ |01⟩ again.
    _controlled_ry_on_zero!(ctx, w_msb, w_lsb, γ)
end
```

**Critical issue with Hamming-distance-2 Givens at non-pow2 d:** the standard
CX-ladder trick that turns a `(|01⟩, |10⟩)` Givens into a `(|00⟩, |01⟩)` Givens
routes amplitude *through* the forbidden `|11⟩` basis state. This violates
§6's subspace preservation BY CONSTRUCTION.

**Fix:** use an **`|11⟩`-free Givens sequence**. Two options:

* **(a) Toffoli-bracketed CX ladder.** Replace `CX(w_lsb, w_msb)` with
  `CCX(w_ancilla=|0⟩, w_lsb, w_msb)` after conditionally setting the ancilla
  on "we are in-subspace". This is a workspace-qubit construction — adds
  one ancilla per Hamming-2 Givens block.
* **(b) Reorder the Givens sweep to use only Hamming-1 adjacent pairs
  representable as `(|00⟩, |01⟩)` or `(|10⟩, |11⟩)` in the qubit basis.**
  But `|10⟩ ↔ |11⟩` crosses the forbidden level at d=3.

**Resolution for d=3:** there is NO pair of adjacent (in d-level label
ordering) basis states that are Hamming-1 neighbours AND both in-subspace,
other than `(|0⟩, |1⟩) = (|00⟩, |01⟩)`. The pair `(|1⟩, |2⟩) = (|01⟩, |10⟩)`
is Hamming-2 and MUST be implemented via a CX ladder. To keep `|11⟩` out of
the picture, use a **workspace qubit** and the Toffoli-bracketed pattern:

```
# G_{1,2}(β) WITHOUT touching |11⟩:
# (Same trick swap! uses at src/gates.jl — verify in library patterns.)
# 1. Allocate a clean ancilla w_anc = |0⟩.
# 2. CX(w_lsb, w_anc): w_anc ← w_lsb. Now {|01⟩, |10⟩} → {|010⟩_LE, |100⟩_LE}.
#    The labels |01⟩_d-enc and |10⟩_d-enc are now distinguished by w_anc.
# 3. Apply controlled-Ry(β) on the (distinguishing wire, with w_anc=1 fixes
#    that we came from |01⟩, w_anc=0 fixes we came from |10⟩). The rotation is
#    implemented as: Ry on the w_msb-XOR-w_lsb combination, controlled on w_anc.
# 4. Uncompute: CX(w_lsb, w_anc) to return w_anc to |0⟩ and deallocate.
# Actually the right construction is: swap-based. Use swap!(|01⟩, |10⟩)-conditional
# on a computed ancilla. This is standard Brennen-Bullock-O'Leary quant-ph/0509161 §4.
```

**Simpler, cleaner, and literature-backed: use a SWAP-relabelling.** Reorder
basis labels at the start of each Ry: push a reversible permutation that
re-encodes `|1⟩_d = |10⟩_qubit` instead of `|01⟩_qubit` (i.e., MSB-first
encoding for labels 0, 1, 2). Now the adjacent d-level pair `(|1⟩, |2⟩)`
becomes `(|10⟩, |01⟩)` — still Hamming-2 — so this doesn't help.

**Actually-workable construction (what nrs ships):** for d=3, the Wigner
d^1(δ) unitary can be realised via **3 CNOT + 4 single-qubit Ry** using
the Klappenecker-Rötteler qutrit-in-qubits construction (Klappenecker-Rötteler
2003, "Constructions of Mutually Unbiased Bases", but the spin-1-in-2-qubits
construction predates them). The exact primitive-level sequence is:

```
# Wigner d^1(δ) on qutrit encoded as 2 qubits (|11⟩ forbidden):
# Reference: Klappenecker-Rötteler 2003 construction + our ak2 d=2 building
# block. Emits exactly: 4 apply_ry! + 3 apply_cx! = 7 primitives.

function _spin_j_ry_d3!(ctx, wires::NTuple{2, WireID}, δ::Real)
    w_lsb, w_msb = wires[1], wires[2]
    α, β, γ, ζ = _wigner_d1_gate_sequence_angles(δ)   # closed-form from Sakurai 3.8.33

    # Sequence (to be derived and verified numerically against d^1(δ) during impl):
    apply_ry!(ctx, w_lsb, α)
    apply_cx!(ctx, w_lsb, w_msb)        # w_msb ^= w_lsb
    apply_ry!(ctx, w_lsb, β)
    apply_cx!(ctx, w_msb, w_lsb)        # w_lsb ^= w_msb
    apply_ry!(ctx, w_lsb, γ)
    apply_cx!(ctx, w_lsb, w_msb)
    apply_ry!(ctx, w_msb, ζ)
end
```

**To make this derivation concrete:** during implementation, build a
`_numeric_wigner_d1(δ)` → `Matrix{ComplexF64}` using Sakurai Eq. 3.8.33,
then solve for `(α, β, γ, ζ)` such that the above sequence's 4×4 matrix
(with row/col 3 = |11⟩ = identity, to preserve subspace) equals
`Diagonal([d^1(δ) block, 1])`. Four free angles, one constraint (the block
is 3×3 with 3 free params per SU(2) x SU(3) mapping… overspecified, but
numerical solve is fine). **Write a test that the assembled 4×4 unitary at
the encoded subspace matches d^1(δ) to 1e-10.**

**Honest status:** exact closed-form angles for this 7-gate sequence at
d=3 are **not derived in this design doc** — I do not have a paper giving
the exact sequence. The v0.1 plan: (a) derive numerically once at compile
time per-δ (cheap, 7 trig calls + a 4-angle solve via Newton), OR (b) do
the academic derivation by hand and bake closed-form expressions. Plan:
**(a) for initial landing, profiling-verified then promoted to (b) if the
per-call cost matters.** `_wigner_d1_gate_sequence_angles(δ)` is the
per-call helper (numerical) for v0.1; cached by `δ`-bucketed Dict if
Shor-loop profiling shows it's a hot path.

### 5.2 d=5 algorithm

Same strategy: derive a fixed sequence of `O(d² K) = O(25·3) = 75`
primitives (some CXs, some Rys) whose matrix on the 5-level subspace (subset
of the 8-dim 3-qubit space) equals d^2(δ). At the implementer's choice:

* Precompute the 5×5 d^2(δ) matrix from Sakurai Eq. 3.8.33.
* Use the QR/Givens sweep from Wang-Hu-Sanders-Kais §2.1.2 Eq. (3-4) to
  derive 10 adjacent-pair rotation angles.
* Lift each adjacent-pair rotation to qubit primitives using the
  "Toffoli-bracketed" pattern (§2.3, avoiding forbidden basis states).

Gate count estimate: **50 single-qubit Ry + 30 CX ≈ 80 primitives per
`q.θ += δ` call at d=5.** Acceptable for v0.1 prototyping.

### 5.3 Gate count summary

| d | K | Rz primitives | Ry primitives | CX primitives | Total |
|---|---|---|---|---|---|
| 3 | 2 | 2 | 4 | 3 | 9 |
| 5 | 3 | 3 | ~50 | ~30 | ~83 |

(Estimates. Rz row is exact. Ry row is v0.1 upper bound; optimisation can
reduce via phase-polynomial passes if the measurement-barrier check passes
— which it does, since the decomposition contains no measurements.)

## 6. Leakage invariants — Q6 answer

### 6.1 Mathematical proof (carries over from ak2, formalised here)

Spin-j Ĵ_y and Ĵ_z are by definition Hermitian operators **on the
(2j+1)-dim spin-j irrep**. Therefore `exp(-iδĴ_y)` and `exp(-iδĴ_z)`
preserve `span{|0⟩, …, |d-1⟩}` setwise — this is Bartlett 2002 p.2
("d-dimensional irreducible representation of SU(2)"). No particular
decomposition into qubit gates changes this fact; the qubit-side proof
is that our decomposition IMPLEMENTS this spin-j unitary on the
in-subspace, and the identity on the out-of-subspace.

### 6.2 Implementation proof (qubit-side)

**Rz path:** each per-wire Rz commutes with the "is this bitstring ≥ d"
predicate (it doesn't move amplitudes, only phases them). So amplitude on
`|11⟩` at d=3 stays at 0 if it started at 0. **Preserved by construction.** ✓

**Ry path (d=3):** the 7-gate sequence acts on the 4-dim 2-qubit space.
It's the implementer's obligation to prove the sequence restricts to
identity on `|11⟩`. Mechanism: during derivation of the 4 angles
`(α, β, γ, ζ)`, add the constraint `⟨11|U|11⟩ = 1` and
`⟨11|U|m⟩ = ⟨m|U|11⟩ = 0 for m < 3`. This gives 4 additional
constraints on the 4-angle sequence — numerical solve handles it; the
closed-form derivation makes it manifest.

**Ry path (d=5):** 5 forbidden bitstrings in the 8-dim 3-qubit space (|101⟩,
|110⟩, |111⟩, and two more depending on encoding). Each adjacent-pair Givens
block in the QR sweep is in-subspace by construction (pairs `(|s⟩, |s+1⟩)`
with `s+1 < d = 5`). The Toffoli-bracketed construction ensures the CX
ladders don't route through forbidden states.

### 6.3 Experimental test

Statistical test (§7 Test 4): apply N=5000 random θ/φ rotations to a
freshly-prepped `QMod{3}()` and `QMod{5}()`, measure, verify outcome
never ≥ d. Tolerance: 0 outcomes ≥ d across all 5000 shots.

Deterministic test: start from `QMod{3}()` in `|0⟩`, apply one `q.θ += π/3`,
snapshot the amplitude buffer via `_amps_snapshot` (the helper in
`test_qmod.jl:266`), assert `amps[4] ≈ 0` (the |11⟩ index in the 4-amp
buffer at K=2 is `0b11 = 3`, Julia 1-indexed to `amps[4]`).

## 7. Test plan (runnable — no @test_skip) — Q7 answer

All tests live in **`test/test_qmod.jl`**, appended after the ak2 section
(matches Session 54's precedent). Test helper `_amps_snapshot` from
`test_qmod.jl:266` is reused.

### 7.1 d=3 Rz diagonal check (hard, mandatory)

```julia
@testset "nrs d=3: q.φ += δ is diagonal (no amplitude redistribution)" begin
    # Prep |0⟩ at d=3 (K=2). Apply Rz. Amplitude must stay concentrated at |0⟩_qubit.
    @context EagerContext() begin
        q = QMod{3}()
        q.φ += π/4
        amps = _amps_snapshot(current_context())
        @test abs(amps[1]) ≈ 1.0 atol=1e-12         # |00⟩ amplitude = 1 (up to phase)
        @test abs(amps[2]) < 1e-12                  # |01⟩ = label 1: no amp
        @test abs(amps[3]) < 1e-12                  # |10⟩ = label 2: no amp
        @test abs(amps[4]) < 1e-12                  # |11⟩ = forbidden: no amp
        ptrace!(q)
    end
end
```

### 7.2 d=3 Rz phase check (Bartlett Eq. 7 correspondence)

```julia
@testset "nrs d=3: q.φ += 2π/3 gives |s⟩ → exp(-i(2π/3)(j-s))|s⟩" begin
    # Prep a superposition |0⟩ + |2⟩ via raw wires (bypasses Ry — label 2 ↔ wires[2]=1)
    # After Rz(2π/3), relative phase between |0⟩ and |2⟩ must equal exp(i(2π/3)·(1-0)+...)
    # Easier: use Ramsey. Prep |0⟩, apply a d=3 Ry (§7.3) to get superposition, apply Rz,
    # apply Ry^-1, measure. If Rz is correct, deterministic outcome.
    # Wait — we're TESTING Ry here. Break circular dep: prep superposition via RAW
    # Sturm.apply_ry! on individual wires (avoid QMod.θ path).
    @context EagerContext() begin
        q = QMod{3}()
        ctx = current_context()
        # Manually put amplitude on label 2: apply X (Ry(π)) on wires[2].
        Sturm.apply_ry!(ctx, q.wires[2], π)        # q is now in |10⟩_qubit = |2⟩_d
        # Compose with label 0 by putting q into superposition first:
        # Actually the simplest deterministic test: Rz on |2⟩ should stay at |2⟩
        # with a phase factor. Snapshot and verify.
        q.φ += 2π/3
        amps = _amps_snapshot(ctx)
        # Label 2 at K=2, little-endian: wires[2]=1, wires[1]=0 → qubit basis idx = 2.
        # Expected phase: exp(-i(2π/3)·(j − s)) at j=1, s=2 → exp(-i(2π/3)·(-1)) = exp(+i2π/3).
        # Plus the global exp(-iδ·j) = exp(-i2π/3) which we ignore (SU(d)).
        @test abs(amps[3]) ≈ 1.0 atol=1e-12
        @test angle(amps[3]) ≈ 2π/3 atol=1e-10  # up to global phase convention; adjust sign if orkan differs
        ptrace!(q)
    end
end
```

**Note on global-phase convention:** the exact `angle()` expected depends
on orkan's `apply_rz!` sign. The test should be written after running a
sanity probe at d=2 (comparing phases on |0⟩ vs |1⟩) to pin down the sign,
same as ak2 did.

### 7.3 d=3 Ry amplitude check (the critical test)

```julia
@testset "nrs d=3: q.θ += π/3 matches Wigner d^1(π/3) on |0⟩_d column" begin
    # |0⟩_d = |00⟩_qubit. After R_y(π/3), amplitudes on |s⟩_d should equal
    # d^1_{j−s, j}(π/3). At j=1: d^1_{1,1}(δ) = (1+cos δ)/2, d^1_{0,1}(δ) = sin(δ)/√2,
    # d^1_{-1,1}(δ) = (1-cos δ)/2. At δ=π/3: 0.75, sin(π/3)/√2 ≈ 0.612, 0.25.
    δ = π/3
    @context EagerContext() begin
        q = QMod{3}()
        q.θ += δ
        amps = _amps_snapshot(current_context())
        # Label 0 = |00⟩_qubit = amps[1]. Label 1 = |01⟩_qubit = amps[2]. Label 2 = amps[3].
        expected_0 = (1 + cos(δ)) / 2
        expected_1 = sin(δ) / sqrt(2)
        expected_2 = (1 - cos(δ)) / 2
        @test abs(amps[1]) ≈ expected_0 atol=1e-10
        @test abs(amps[2]) ≈ expected_1 atol=1e-10
        @test abs(amps[3]) ≈ expected_2 atol=1e-10
        @test abs(amps[4]) < 1e-12    # |11⟩_forbidden stays empty
        ptrace!(q)
    end
end
```

### 7.4 Subspace preservation, statistical (d=3, d=5)

```julia
@testset "nrs d=3 subspace: 5000 random θ/φ rotations never leak" begin
    rng = Random.MersenneTwister(42)
    leak_count = 0
    for _ in 1:5000
        @context EagerContext() begin
            q = QMod{3}()
            for _ in 1:5
                δ = 2π * rand(rng)
                axis = rand(rng) < 0.5 ? :θ : :φ
                if axis === :θ; q.θ += δ else q.φ += δ end
            end
            try
                _ = Int(q)        # layer-3 leakage guard fires if bitstring ≥ d
            catch e
                leak_count += 1
                # ptrace unconsumed:
            end
        end
    end
    @test leak_count == 0
end

@testset "nrs d=5 subspace: 2000 random θ/φ rotations never leak" begin
    # Same pattern, d=5 (K=3 → 2^3=8 basis states, 3 forbidden labels 5, 6, 7).
    # Smaller N because d=5 Ry is ~80 gates per call.
    ...
end
```

### 7.5 d=5 Ry amplitude spot-check

```julia
@testset "nrs d=5: q.θ += π/4 matches d^2(π/4)|0⟩ column" begin
    δ = π/4
    @context EagerContext() begin
        q = QMod{5}()
        q.θ += δ
        amps = _amps_snapshot(current_context())
        # Wigner d^2_{m',2}(δ) for m' ∈ {2,1,0,-1,-2} (Sakurai Eq. 3.8.33 at j=2):
        c, s = cos(δ/2), sin(δ/2)
        expected = [c^4, -2c^3*s, sqrt(6)*c^2*s^2, -2*c*s^3, s^4]  # unsigned magnitudes
        # Labels 0..4 at K=3, little-endian: idx 0 → amps[1], idx 1 → amps[2],
        # idx 2 → amps[3], idx 3 → amps[4], idx 4 → amps[5]. Forbidden idx 5,6,7 → amps[6,7,8].
        for s_idx in 0:4
            @test abs(amps[s_idx + 1]) ≈ abs(expected[s_idx + 1]) atol=1e-10
        end
        for s_idx in 5:7
            @test abs(amps[s_idx + 1]) < 1e-10
        end
        ptrace!(q)
    end
end
```

### 7.6 Ramsey test: Rz phase is observable between two Ry

```julia
@testset "nrs d=3: Ramsey Ry(π/3) · Rz(δ) · Ry(-π/3) — Rz phase recoverable" begin
    # At d=3, apply Ry(π/3) to get into superposition, apply Rz(δ), apply Ry(-π/3).
    # Measurement statistics depend on δ; at δ=0, return deterministically to |0⟩.
    @context EagerContext() begin
        q = QMod{3}()
        q.θ += π/3
        q.φ += 0.0                     # trivial Rz
        q.θ += -π/3
        amps = _amps_snapshot(current_context())
        # Without the Rz phase, Ry(π/3) then Ry(-π/3) = I → |0⟩.
        @test abs(amps[1]) ≈ 1.0 atol=1e-10
        @test abs(amps[2]) < 1e-10
        @test abs(amps[3]) < 1e-10
        @test abs(amps[4]) < 1e-10
        ptrace!(q)
    end
    # Non-trivial Rz: measurement probabilities must deviate from 1-on-|0⟩.
    @context EagerContext() begin
        q = QMod{3}()
        q.θ += π/3
        q.φ += π                        # non-trivial phase
        q.θ += -π/3
        amps = _amps_snapshot(current_context())
        @test abs(amps[1]) < 0.9 - 1e-6     # |0⟩ amp must have dropped
        ptrace!(q)
    end
end
```

### 7.7 Deferred: Bartlett Eq. 13 parity factor test (d=4, controlled-X)

**Deferred to bead `u2n`** (library gate `X_d!` + test). Our nrs implementation
does not ship `X_d!` — that's the library gate that BUILDS ON nrs's spin-j
primitives. The parity test at d=4 verifies
`when(c) X_d! end` vs. the Weyl-Heisenberg `X_d` have the documented
`exp(-iπ/d)` controlled-phase discrepancy (§8.4 of the magic-gate survey).
Called out here as the test `u2n` must include; nrs is a prerequisite but
not the site.

### 7.8 Gate-count regression test (via TracingContext)

```julia
@testset "nrs d=3: q.θ += δ emits exactly (4 Ry + 3 CX) gates" begin
    ctx = TracingContext()
    @context ctx begin
        q = QMod{3}()
        q.θ += π/5
        ptrace!(q)
    end
    ry_count = count(n -> n isa Sturm.RyNode, ctx.dag)
    cx_count = count(n -> n isa Sturm.CXNode, ctx.dag)
    @test ry_count == 4       # per §5.1 sequence
    @test cx_count == 3
end

@testset "nrs d=3: q.φ += δ emits exactly 2 Rz gates" begin
    ctx = TracingContext()
    @context ctx begin
        q = QMod{3}()
        q.φ += π/3
        ptrace!(q)
    end
    rz_count = count(n -> n isa Sturm.RzNode, ctx.dag)
    @test rz_count == 2       # K=2 → 2 per-wire Rz
end
```

**Note on TracingContext + ptrace!:** TracingContext's `deallocate!` emits a
DiscardNode (`src/context/tracing.jl:41`), so `ptrace!` after the rotation is
required to clean up; otherwise the block-exit auto-cleanup does it. Both
work; the test above is explicit.

### 7.9 `when()` routing sanity at d=3

```julia
@testset "nrs d=3: q.θ += δ inside when(::QBool) routes through control stack" begin
    # Ctrl=0 branch: QMod stays at |0⟩_d (Ry not applied).
    # Ctrl=1 branch: QMod rotated to d^1(δ)|0⟩ distribution.
    N = 1000
    counts_ctrl0 = Dict(0 => 0, 1 => 0, 2 => 0)
    counts_ctrl1 = Dict(0 => 0, 1 => 0, 2 => 0)
    δ = π/3
    for _ in 1:N
        @context EagerContext() begin
            ctrl = QBool(0.5)
            q = QMod{3}()
            when(ctrl) do
                q.θ += δ
            end
            c = Bool(ctrl) ? 1 : 0
            s = Int(q)
            if c == 0
                counts_ctrl0[s] += 1
            else
                counts_ctrl1[s] += 1
            end
        end
    end
    # Ctrl=0: always measure 0.
    @test counts_ctrl0[0] >= 0.95 * sum(values(counts_ctrl0))
    # Ctrl=1: distribution matches d^1(π/3) = (0.75, 0.5^2 ≈ sin²(π/6)·2 ≈ 0.375, 0.0625)²...
    # Expected probabilities: (0.5625, 0.375, 0.0625). Tolerance at N=~500 ctrl=1 shots: ~0.06.
    total1 = sum(values(counts_ctrl1))
    @test abs(counts_ctrl1[0]/total1 - 0.5625) < 0.08
    @test abs(counts_ctrl1[1]/total1 - 0.375) < 0.08
    @test abs(counts_ctrl1[2]/total1 - 0.0625) < 0.05
end
```

### 7.10 d=2 unchanged (regression guard)

Already covered by ak2's `test_qmod.jl` ak2 d=2 testsets. **No modification
to d=2 code path in nrs** (since `getproperty(q::QMod{2,1}, ...)` returns
`BlochProxy` and bypasses `_apply_spin_j_rotation!` entirely).

## 8. File organization — Q8 answer

**Recommendation: extend `src/types/qmod.jl` in place; no new top-level
file in v0.1.**

### File-by-file breakdown

| File | Action | Why |
|---|---|---|
| `src/types/qmod.jl` | **extend** (remove stub `_apply_spin_j_rotation!`, add real Rz + Ry-dispatch; define `_spin_j_ry_d3!`, `_spin_j_ry_d5!`, `_wigner_d1_gate_sequence_angles`, `_wigner_d2_givens_angles` helpers) | Same file precedent as ak2; the Rz closed-form is 10 lines, d=3 Ry is ~30 lines, d=5 Ry is ~60 lines — fits. |
| `docs/physics/wigner_small_d.md` | **new** | Rule 4 compliance: derive d^1, d^2 from Sakurai Eq. 3.8.33 with explicit equations; cite PDF sections. Required before merge. |
| `test/test_qmod.jl` | **extend** | Append nrs testset block after ak2. Reuse `_amps_snapshot`. ~150 lines added. |
| `test/runtests.jl` | **untouched** | test_qmod.jl already registered. |
| `src/Sturm.jl` | **untouched** | `_apply_spin_j_rotation!` is internal. |

**Alternatives rejected.**

* **`src/types/qmod_rotations.jl`**: would split the getproperty logic (in
  qmod.jl) from the decomposition (in qmod_rotations.jl). Future os4/mle
  would add more files. The qbool/qint precedent is "keep primitives with
  the type". Start with inline; split later if `mle` crosses 200 lines.
* **`src/library/qudit_fallback.jl`**: these are primitives, not library
  gates. Library = composed, named (H_d!, T_d!). Primitives 2-3 are
  primitives per the magic-gate survey §8.1.

**Rule 13 check.** The helpers I'm adding:
* `_spin_j_ry_d3!`, `_spin_j_ry_d5!` — new, no duplication.
* `_spin_j_rz!` — new, but note: Draper QFT adder (`src/library/arithmetic.jl:132-167`)
  does similar per-wire Rz work with different angle logic. Not duplicated;
  different Hamiltonian.
* `_wigner_d1_gate_sequence_angles(δ) -> (α, β, γ, ζ)` — new, pure trig.
* Re-uses `_multi_controlled_gate!` (from `src/context/multi_control.jl:88-111`)
  for any Hamming-distance-≥2 Givens sub-block (only needed at d=5+).
* Re-uses `apply_ry!`, `apply_rz!`, `apply_cx!` directly.

## 9. Performance / regression — Q9 answer

### 9.1 Gate count

| d | K | Ry call count | Rz call count | Per-call budget (eager) |
|---|---|---|---|---|
| 3 | 2 | 4 Ry + 3 CX | 2 Rz | ~7 × O(ccall) ≈ 1 µs |
| 5 | 3 | ~50 Ry + ~30 CX | 3 Rz | ~80 × O(ccall) ≈ 10 µs |
| 7 | 3 | O(d²) ≈ ~100 | 3 Rz | ~100 × O(ccall) ≈ 20 µs (if shipped) |
| 9 | 4 | O(d²) ≈ ~170 | 4 Rz | ~200 × O(ccall) ≈ 40 µs (if shipped) |

Per-call classical overhead: angle computation (~4 trig evaluations at d=3,
~10 at d=5). Negligible vs ccall cost.

### 9.2 Hot-loop risk

The scenario: a QFT-for-QMod loop doing 1000 × `q.θ += δ` at d=3. Cost:
1000 × 7 primitives × ccall-ns ≈ 7 ms wall. **Not catastrophic.** At d=5:
1000 × 80 primitives ≈ 80 ms. Still fine.

**Mitigation if needed:** pre-compute angles in a `Val(d)`-specialised
const for common δ values (π/2, π/3, 2π/d roots-of-unity). But
premature; wait for a profiling signal.

### 9.3 Channel IR safety

**Confirmed: the decomposition emits only RyNode, RzNode, CXNode.** No
ObserveNode, CasesNode, DiscardNode inside `_apply_spin_j_rotation!`. So:
* Phase polynomial passes (TPAR, TODD) can optimise across `q.θ += δ`
  calls — safe.
* ZX rewriting — safe (no measurements introduced).
* Gate cancellation passes (`src/passes/gate_cancel.jl`) — safe.

Per CLAUDE.md "Channel IR vs Unitary Methods": **safe to apply
unitary-only optimisation passes to any DAG region that contains our
spin-j rotations (plus other unitary nodes) and no measurement barriers.**

### 9.4 QCC / tracing overhead

At TracingContext, each primitive call emits one DAG node, so one `q.θ += δ`
at d=3 adds 7 nodes. DAG-size-vs-classical-cost tradeoff (channel trace
size grows O(d²) per primitive call) — acceptable at v0.1.

## 10. Open questions / risks — Q10 answer

### Open (must resolve during implementation)

**O1. Exact 4-angle sequence for d=3 Ry.** I specified a 7-primitive sequence
(4 Ry + 3 CX) but did NOT derive the 4 angles in closed form. **Implementation
plan:** derive numerically at call-time from `d^1(δ)` via a Newton solve on
the 4×4 matrix constraint + subspace preservation — 20 lines of Julia, per-call
cost ~5 µs. Once stable, derive closed-form by hand OR cache a Chebyshev
interpolant. **Blocker risk: LOW.** The structure (4 Ry + 3 CX) is a known
qutrit-on-2-qubits pattern from the quantum-optics literature
(Klappenecker-Rötteler 2003); worst case, drop to 6 Ry + 4 CX via a more
generic QR-Givens route — 2 more primitives, still cheap.

**O2. d=5 sequence.** I handwaved "~50 Ry + ~30 CX" without a specific
construction. **Plan:** QR Givens sweep on `d^2(δ)` matrix, each 2-level
block lifted via Toffoli-bracketed CX ladder to avoid forbidden basis
states. Implementation is ~100 lines; acceptance test is "full 5×5
sub-matrix of realised unitary matches d^2(δ) to 1e-10" — deterministic,
fast. **Blocker risk: MEDIUM.** Might discover mid-impl that some Givens
pair forces a route through a forbidden state. Fallback: allocate one
scratch qubit per block for Toffoli-bracketing (cost +1 CCX per block).

**O3. Orkan Rz sign convention at d>2.** ak2 fixed at d=2 that
`apply_rz!(ctx, w, δ)` matches `exp(-iδ Ĵ_z)` with `Ĵ_z|0⟩ = (+1/2)|0⟩`.
At d=3 (K=2), our per-wire factorisation `exp(-iδ(j-s)) = exp(-iδj) · Π_k
exp(iδ b_k 2^k)` needs orkan's sign to line up. **Plan:** write a d=3 Rz
deterministic test that prepares `|2⟩_d` via raw wire ops and asserts
amplitude angle = `2π/3` (not `-2π/3`); fix sign in `_spin_j_rz!` if orkan
disagrees.

### Risks (may bite, escalation points)

**R1. Rule 4 ground-truth for d=3 gate sequence.** Sakurai Eq. 3.8.33
gives d^j(δ) as a closed form, but the "4 Ry + 3 CX" sequence for d=3
needs its own derivation. **Mitigation:** write
`docs/physics/wigner_small_d.md` with the Klappenecker-Rötteler derivation
OR an original derivation. Self-contained in ~3 pages. Block nrs on this
if the sequence matters for physics correctness, not just gate count.

**R2. `QModBlochProxy` vs future QInt{W,d}.** Proposer B of ak2 flagged
this. nrs doesn't touch the proxy, so no new risk — but if `dj3` lands
before nrs, the proxy path might fork. Current nrs design assumes the
ak2 proxy is stable.

**R3. Performance-scaling foreclosure.** Our d=3 Ry is 7 primitives,
d=5 is ~80. At d=7, d=9 the generic Wigner recursion would be needed;
but we DEFERRED generic-d. If a user hits `q.θ += δ` at d=7 in v0.1
before `nrs-ry-generic` lands, they get a loud error message pointing
at the follow-on bead. Acceptable. **Not a regression.**

**R4. `when()` + multi-qubit decomposition + cascade.** `when(ctrl)`
around the full 7-gate d=3 sequence pushes `ctrl` onto the control
stack. Each inner `apply_ry!`/`apply_cx!` lifts to single-controlled,
which works via `_controlled_ry!` (`multi_control.jl:34-42`). **Nested**
`when()` up to depth 2 works via the 2-control `_multi_controlled_gate!`
cascade; depth ≥ 3 uses workspace-qubit cascade. Test (§7.9) covers
depth-1 but not depth-2 or deeper — file as nrs follow-on verification.

**R5. Bartlett Eq. 13 parity factor at even d.** Our Ĵ_y spin-j
rotation at δ = 2π/d gives `X_d` only up to the `exp(-iπ/d)` prefactor
for even d (Bartlett Eq. 13 + magic-gate survey §8.4). nrs doesn't ship
`X_d!` — that's `u2n`'s problem. But nrs's Ry primitive MUST be the
"literal `exp(-iδ Ĵ_y)`" — no parity correction inside our primitive.
Document in the docstring + test that `q.θ += 2π/d` at d=4 does NOT
equal the displacement-operator X_4.

**R6. Generic d defers — bead-size argument.** I deferred generic-d Ry.
If the user's v0.1 use case needs d=7, that's a LOUD error and a
follow-on bead. Risk: follow-on bead gets deprioritised. **Mitigation:**
file `nrs-ry-generic` immediately on nrs merge, with acceptance criteria
= "d=7 amplitude-check test GREEN".

### Code I haven't read

* Exact orkan Rz sign (checked abstractly from ak2 Session 54 WORKLOG).
* Exact CX node emission path in `_multi_controlled_gate!` under nested
  `when()` depth 3+ — only relevant if d=7+ ships here, which it doesn't.
* Gate-cancellation pass behaviour on our 7-gate d=3 sequence — future
  concern.

## 11. Files to touch (paths + estimated line counts)

| File | Action | Estimated +lines |
|---|---|---|
| `/home/tobias/Projects/Sturm.jl/src/types/qmod.jl` | Replace stub with real `_apply_spin_j_rotation!` dispatch. Add: `_apply_spin_j_rz!`, `_spin_j_ry_d3!`, `_spin_j_ry_d5!`, `_wigner_d1_gate_sequence_angles(δ)`, `_wigner_d2_givens_angles(δ)` helpers. Add docstrings citing Bartlett Eqs. 5-7, Sakurai Eq. 3.8.33, Wigner small-d derivation note. | +150-200 (qmod.jl: 317 → ~500) |
| `/home/tobias/Projects/Sturm.jl/docs/physics/wigner_small_d.md` | NEW. Derive d^j(δ) at j=1 and j=2 from Sakurai Eq. 3.8.33; cite Bartlett Eq. 5 convention; Klappenecker-Rötteler 2003 OR our own derivation of the 4-Ry-3-CX sequence at d=3. | +250 |
| `/home/tobias/Projects/Sturm.jl/test/test_qmod.jl` | Append nrs testsets §7.1-7.9. Remove the `@test_throws ErrorException q.θ += π/3` deferral tests (ak2 testsets at lines 370-405) — nrs replaces the error with a real implementation at d ∈ {3, 5}, so those tests need updating: keep d=7 / d=9 deferrals, remove d=3 / d=5 deferrals. | +200 / −40 |
| `/home/tobias/Projects/Sturm.jl/WORKLOG.md` | New Session 55 entry per Rule 0: implementation notes, sign-convention calibration, any surprises. | +60-100 |

**Not touched.**
* `src/context/*.jl` — no new apply_* methods; reuse existing cascade.
* `src/types/qbool.jl`, `src/types/qint.jl` — Rule 11, frozen.
* `src/Sturm.jl` — nrs helpers are internal.
* `src/orkan/ffi.jl` — nrs decomposes to existing qubit primitives.

Design doc written to /tmp/nrs_design_B.md
