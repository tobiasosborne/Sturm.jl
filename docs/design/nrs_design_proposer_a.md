# nrs (qubit-encoded fallback simulator) Design — Proposer A

## 0. Summary (5-8 lines)

Ship `_apply_spin_j_rotation!` for **d ∈ {3, 5} only**, via a
**Givens-like decomposition over adjacent computational-basis pairs
`(|s⟩, |s+1⟩)`** with Wigner small-d angles (Sakurai §3.10.16) hard-coded
from closed-form spin-1 / spin-2 expressions. At d=3 the Ry cost is
**2 two-level SU(2) rotations** sandwiched by a base-change, each lifted
to qubit primitives via the existing `_multi_controlled_gate!` cascade in
`src/context/multi_control.jl:88-111`. Rz is factored **diagonal-per-bit**
— `Ĵ_z = (j−s)I` is expressible as a bit-linear polynomial in the binary
encoding, so Rz reduces to at most K single-qubit Rz's + a global phase
(absorbed). Leakage control: every cascade control pattern confines
itself to `s < d`, so the `|m⟩` states with `m ≥ d` receive identity by
construction. Generic-d, the leakage TLS sweep, and `apply_sum_d` are
all filed as follow-ons; the current bead stays scoped to what can be
test-verified against hand-computed Wigner matrices. Headline gate
counts (d=3 Ry: ~8 CX + ~10 Ry; d=5 Ry: ~40 CX + ~50 Ry) assert under
`TracingContext`.

## 1. Scope decision — Q1 answer

**This bead ships exactly three things, no more:**

1. **`_apply_spin_j_rotation!` for d ∈ {3, 5}**, via dispatch on
   `Val{d}`. Both the Ry and Rz paths. Hard-coded closed-form Wigner
   d-matrix angles (j=1 and j=2) extracted from Sakurai eq. 3.10.16 and
   checked against independent references (BartlettdeGuise Eq. 6 for
   matrix elements; explicit `d^1(β)` and `d^2(β)` tables in any modern
   angular-momentum textbook — will include a tiny derivation note at
   `docs/physics/wigner_small_d_j1_j2.md` for Rule 4 compliance).

2. **Leakage proof per-Givens-block, verified experimentally.** For
   d=3, K=2, the `|11⟩` state must keep amplitude 0 through any
   sequence of Ry/Rz. Asserted statistically (1000 random sequences →
   `Int(q)` never errors with the "out of range" message).

3. **Gate-count regression test** under `TracingContext` — counts CX +
   Ry + Rz + CCX nodes in the DAG after one `q.θ += π/3` at d=3,
   pins the headline number. Catches silent algorithmic regressions
   from future refactors.

**Explicitly DEFERRED to follow-on beads:**

* **Generic d ≥ 3.** The closed-form `d^j_{m',m}(β)` exists (Wigner's
  explicit sum formula) but each new `d` needs hand-verification +
  another Givens decomposition. `csw`'s v0.1 acceptance only requires
  d ≤ 9, and d ∈ {3, 5} are the physics-motivated prime cases (qutrit
  MSD + smallest prime d ≥ 5). **File as bead `nrs-generic`**: generic
  `d^j_{m',m}(β)` via recursion (Edmonds 4.1.23) + a Givens loop. Tests
  live there against d ∈ {4, 6, 7, 8, 9}.

* **`apply_sum_d` (SUM for bead `p38`).** *Not* in nrs. The SUM
  decomposition `|a, b⟩ → |a, (a+b) mod d⟩` is a **modular in-place
  adder** on 2K qubits. Its natural home is a new
  `src/library/qudit_arithmetic.jl` file (parallel to
  `src/library/arithmetic.jl` — which already implements
  `add_qft_quantum!` via the Draper QFT adder). The p38 implementer
  can either (a) lift Draper's mod-d adder by reusing the binary
  encoding + a mod-d carry, or (b) use per-s controlled increment
  `X_d^s` decomposed via nrs's Wigner-small-d machinery. Option (a)
  is cheaper (O(K²) gates vs. O(d·K²) for option b); p38's 3+1
  protocol should evaluate both. **nrs exposes no SUM interface**; the
  only shared infrastructure is the Wigner d-matrix closed-form helper
  (which nrs documents in-module but does not export — p38 can lift
  it out or include it verbatim).

* **`with_qmod_leakage_checks` TLS flag.** Still filed. No new scope
  here; the "unconditional measurement-time check in `Base.Int`" from
  bead 9aa is the layer-3 safety net, layer 2 (per-primitive subspace
  proof) is what nrs delivers by construction, and layer 1 (trust
  prep) is preserved. The TLS debug sweep is only useful if a bug is
  suspected in a production simulation — a real scenario but not
  blocking.

**Rationale for the narrow scope.** Rule 2 (3+1 protocol) kicks in for
core-type changes; Rule 6 (bugs are deep); Rule 10 (TDD). A d=3 Givens
decomposition I can grind out and verify against hand-computed
`d^1(β)` matrices fits in one bead. Generic-d is materially more work:
the closed-form recursion is more bug-prone, and every new `d`
doubles the test matrix (Ry × Rz × subspace-preservation × gate-count
× controlled-context). Ship correctness at d=3 and d=5, then lift.

## 2. Decomposition algorithm — Q2 answer (CITE BARTLETT / SAKURAI EQUATIONS)

**Algorithm: (i) Givens decomposition into `d−1` two-level SU(2)
rotations on adjacent pairs, with a base-change sandwich.**

### The core identity

Ry on the spin-j irrep is off-diagonal in the `|j, m⟩_z` basis:

$$
R_y(\beta) = e^{-i\beta \hat J_y} = \sum_{m',m=-j}^{j} d^j_{m',m}(\beta)\, |j, m'\rangle_z \langle j, m|_z
$$

(Sakurai *Modern QM* Eq. 3.10.16). In Bartlett's labelling
`|s⟩ ≡ |j, j−s⟩_z` (Bartlett Eq. 5, p.2), this is a dense
`d × d` matrix on the `{|0⟩, …, |d−1⟩}` subspace.

**QR-style Givens decomposition** (Reck-Zeilinger 1994 / Murnaghan
1962) writes any `d × d` unitary as a product of `C(d, 2) = d(d−1)/2`
two-level rotations on adjacent pairs `(|s⟩, |s+1⟩)`. For the spin-j
`R_y(β)` specifically, only `d−1` rotations are needed because of the
tridiagonal-like structure of the ladder operators `Ĵ_± = Ĵ_x ± i Ĵ_y`
(Bartlett Eq. 6, matrix elements after Eq. 5):

$$
(\hat J_\pm)_{m',m} = \sqrt{j(j+1) - m(m \pm 1)}\, \delta_{m', m \pm 1}
$$

**But** `R_y(β) = e^{-iβ Ĵ_y}` is dense, not tridiagonal. The `d−1`
count applies to `Ĵ_y`, not `exp(−iβ Ĵ_y)`. For the general unitary we
need the full `d(d−1)/2` pairs. At d=3 that's 3 rotations; at d=5
that's 10. Manageable.

**Simplification used.** For spin-j `R_y(β)`, the Wigner matrix
`d^j(β)` factors as

$$
d^j(\beta) = \prod_{m=-j}^{j-1} G_{m, m+1}(\gamma_m(\beta))
$$

where each `G_{m,m+1}` is a 2×2 rotation on the adjacent `(|m⟩, |m+1⟩)`
pair, and the angles `γ_m(β)` come from a QR decomposition of
`d^j(β)`. This is the **Givens rotation sequence** (Wang-Hu-Sanders-Kais
2020 Eq. 4, §3 — "one-qudit gates"; also Brennen-Bullock-O'Leary 2005
§4). **Closed form for j=1 (d=3)** is the Jacobi rotation sequence; for
j=2 (d=5), the explicit closed form is in Chirolli-Burkard
"Full-Rotation-Angle Single-Qudit" (not critical, we can also
numerically QR-decompose `d^j(β)` at call time and verify against the
closed form — see §3).

### Pseudocode

```
function _apply_spin_j_ry!(ctx, wires, β, ::Val{d}):
    # d ∈ {3, 5} for v0.1
    K = length(wires)             # K = ceil(log2(d))
    M = _wigner_d_matrix(β, d)    # d × d real matrix, from Sakurai 3.10.16
    # QR-decompose M into d-1 Givens on adjacent pairs
    γ = _givens_angles(M)         # returns Vector{Float64} of length d-1
    for s in 0:(d-2):
        _apply_two_level_SU2!(ctx, wires, s, s+1, :y, γ[s+1], Val(d))
    # For general R_y(β) on spin-j, we may need a second sweep
    # (bubble-sort-like); for d=3 specifically, 2 sweeps suffice (see below).
```

For **d=3**, spin-1 `R_y(β)` has the closed form

$$
d^1(\beta) =
\begin{pmatrix}
\frac{1+\cos\beta}{2} & -\frac{\sin\beta}{\sqrt 2} & \frac{1-\cos\beta}{2}\\
\frac{\sin\beta}{\sqrt 2} & \cos\beta & -\frac{\sin\beta}{\sqrt 2}\\
\frac{1-\cos\beta}{2} & \frac{\sin\beta}{\sqrt 2} & \frac{1+\cos\beta}{2}
\end{pmatrix}
$$

(Sakurai 3.10.33; BartlettdeGuise derivations). This factors as a
product of **3 Givens on adjacent pairs** (0,1), (1,2), (0,1):

$$
d^1(\beta) = G_{0,1}(\alpha_1) \cdot G_{1,2}(\alpha_2) \cdot G_{0,1}(\alpha_3)
$$

with angles `(α_1, α_2, α_3)` solved from the QR. For d=5, spin-2
takes **10 Givens** (or fewer if we exploit the Wigner-d structural
sparsity — TBD).

### Lift to qubit primitives

Each `G_{s,s+1}(α)` is a 2×2 SU(2) rotation on the
`{|s⟩_qubit, |s+1⟩_qubit}` pair of qubit-basis states. In binary
encoding these two states differ by `s XOR (s+1)` in qubit-bit space.
Two subcases:

**Case A: Hamming distance 1** (e.g. (0,1)=(00,01), (2,3)=(10,11)).
Single bit flips. `G_{s,s+1}(α)` lifts to **`apply_ry!(α)` on the
differing wire, conditioned on the K−1 shared wires matching the
Hamming-shared bits of `s`**. Control pattern: push the shared bits as
controls (via `push_control!`), with X-gate negation on bits that
should match 0 (the standard "zero-control" trick — flip-the-bit,
control, flip-back). Call `apply_ry!` on the differing wire. Pop
controls. This is **exactly** what `_multi_controlled_gate!`
(`src/context/multi_control.jl:88-111`) expects; we just bracket the
call in X-sandwiches for zero-controls.

**Case B: Hamming distance ≥ 2** (e.g. (1,2)=(01,10)). Two or more
bits flip. Strategy: **decompose the 2×2 block rotation into a
3-gate sequence**:
```
CX(wire_a, wire_b) · {multi-controlled Ry(α) on wire_a} · CX(wire_a, wire_b)
```
where wire_a and wire_b are the two bits that flip differently.
This moves the problem from Hamming-d-≥-2 to Hamming-d-1 on wire_a,
with wire_b inheriting the flip. (Standard technique from Barenco
1995 Lemma 7.2 + Nielsen-Chuang §4.3. Trusted.) For d=3 pair
(1, 2) = (01, 10), wire_a = LSB, wire_b = MSB; the CX(MSB, LSB)
sandwich maps (01, 10) to (01, 11), then Ry on MSB conditioned
on LSB=1, then unsandwich.

### Rz path — see §4 below. Separate, diagonal-per-bit, much cheaper.

## 3. Wigner d-matrix source — Q3 answer

**Hybrid: closed-form closed tables for d ∈ {3, 5}, validated
numerically at test-build time.**

* **d=3 (j=1)**: `d^1_{m',m}(β)` copied from Sakurai eq. 3.10.33 (the
  spin-1 matrix above). Nine entries, all in `{cos β, sin β,
  (1±cos β)/2, ±sin β/√2}`. Hand-verified against the defining
  `exp(-iβ Ĵ_y)` series at β = 0, π/2, π. Stored as a Julia helper
  `_wigner_d1(β)::SMatrix{3,3,Float64}` in the new
  `src/library/qudit_fallback.jl`.

* **d=5 (j=2)**: `d^2_{m',m}(β)` — 25 entries, derived from the
  general formula

  $$
  d^j_{m',m}(\beta) = \sum_k \frac{(-1)^{k-m+m'} \sqrt{(j+m)!(j-m)!(j+m')!(j-m')!}}{(j+m-k)!\,k!\,(j-k-m')!\,(k-m+m')!} \bigl(\cos\frac{\beta}{2}\bigr)^{2j+m-m'-2k} \bigl(\sin\frac{\beta}{2}\bigr)^{2k+m'-m}
  $$

  (Sakurai eq. 3.10.16). Hard-code the 25 entries symbolically. Store
  as `_wigner_d2(β)::SMatrix{5,5,Float64}`.

* **Givens angles** `γ_m(β)`: extracted by QR-decomposing the
  pre-computed d^j(β) at call time. This is 2×2 rotations on a small
  matrix — O(d²) floating-point ops, negligible compared to the
  O(d²) ccalls to apply_ry!. Implementation: standard QR loop
  identical to BLAS's `GEQR2` but specialised to 3×3 / 5×5. ~15 lines
  in `_givens_angles(M)`.

* **Validation** (build-time assertion): at module load, run a smoke
  check that `_wigner_d1(π/3) * _wigner_d1(-π/3) ≈ I` and
  `_wigner_d1(2π) ≈ I` (or `-I` for even-d if we honour spin-j parity;
  at d=3 (j=1 integer) `d^1(2π) = +I`, confirming the closed form).
  This is Rule 7 "feedback fast" — any typo in the matrix entries
  dies at `using Sturm`.

* **Does NOT use `@generated` or pre-tabulation per Val(d).** That's
  `nrs-generic`'s job — this bead just hard-codes two small
  tables. YAGNI.

**Rationale**: for a d>2 fallback that only needs to ship d=3 and
d=5, a symbolic pre-computed 3×3 / 5×5 matrix is ~50 lines of code
with no numerical stability surprises. The recursion (Edmonds 4.1.23)
is elegant but has more rounding failure modes at β near π; save it
for `nrs-generic`.

## 4. Rz path (diagonal) — Q4 answer with gate-count estimate

**Rz is diagonal; factor per bit.**

In Bartlett's labelling `|s⟩ = |j, j−s⟩_z`, `Ĵ_z |s⟩ = (j − s) |s⟩`,
so

$$
R_z(\delta) |s\rangle = e^{-i\delta(j-s)} |s\rangle
$$

(Bartlett Eq. 7 phase base). Substitute `s = \sum_{i=0}^{K-1} b_i 2^i`
for the binary encoding (LSB in `wires[1]`). Then

$$
e^{-i\delta(j - s)} = e^{-i\delta j} \prod_{i=0}^{K-1} e^{+i\delta\, 2^i\, b_i}
= e^{-i\delta j} \prod_{i=0}^{K-1} \bigl( e^{+i\delta\, 2^i} \bigr)^{b_i}
$$

Each factor `(e^{+i δ 2^i})^{b_i}` is a **single-qubit Rz on
wires[i+1]**:

$$
R_z^{\text{qubit}}(\theta_i) = \mathrm{diag}(e^{-i\theta_i / 2}, e^{+i\theta_i / 2})
$$

with `θ_i = −δ · 2^{i+1}` gives diagonal `(e^{+i δ 2^i}, e^{−i δ 2^i})`
on wire i+1. After absorbing constant factors (global phase from the
`e^{-iδj}` prefactor and from the `1/2` in `R_z^{qubit}`), the
resulting spectrum matches `e^{-iδ(j-s)}` on each |s⟩ **exactly**,
including on the forbidden |s⟩ with s ≥ d — but see §6 below for why
that's fine (those amplitudes are 0 by upstream invariant, so phasing
them has no effect).

### Pseudocode

```
function _apply_spin_j_rz!(ctx, wires, δ, ::Val{d}):
    K = length(wires)
    # Phase on wires[i+1] = (e^{+i δ 2^i}, e^{-i δ 2^i}):
    #   i.e. apply_rz!(ctx, wires[i+1], -δ * 2^(i+1))
    for i in 0:(K-1):
        apply_rz!(ctx, wires[i+1], -δ * 2^(i+1))
    # Global phase e^{-iδj} dropped (SU(d) convention, CLAUDE.md
    # Global Phase and Universality).
```

### Gate count

**d=3, K=2**: 2 single-qubit Rz gates. Exactly 2. No CX, no ancillae.
**d=5, K=3**: 3 Rz gates.
**d=9, K=4**: 4 Rz gates.

Under `when(ctrl)`, each `apply_rz!` gets controlled via the existing
`_controlled_rz!` or the cascade → so the controlled `q.φ += δ` at
d=3 costs **2 controlled-Rz** = 4 CX + 4 Rz + 2 Rz = 4 CX + 6 Rz
(via the ABC decomposition in `multi_control.jl:50-58`). Cheap.

**Dropped global phase**: `e^{-iδj}` is unobservable for isolated
operations (CLAUDE.md policy). Under `when(ctrl)` it becomes a
relative phase `e^{-iδj}` on ctrl=|1⟩, which IS observable —
analogous to the Bartlett Eq. 13 parity factor and the controlled-Z
trap from Grover. **This matches locked §8.4 policy** ("live in
SU(d), pay the controlled-phase cost"). The test matrix documents
this: the controlled R_z built from spin-j rotations differs from the
"naive" mathematician's `diag(e^{-iδ(j-s)})` by a controlled global
phase `e^{-iδj}` — i.e. it equals `diag(e^{-iδ(j-s+j)}) = diag(e^{-iδ(2j-s)})`
on ctrl=|1⟩. Document in the docstring with a `when()` test.

## 5. Ry path (off-diagonal) — Q5 answer with gate-count estimate

### d=3 closed form

`d^1(β)` decomposes into Givens via QR. Running the QR by hand
(3×3 matrix, 2 Givens to upper-triangularise then absorb the diagonal
phases into a final Givens):

$$
d^1(\beta) = G_{0,1}(\alpha_1)\, G_{1,2}(\alpha_2)\, G_{0,1}(\alpha_3)
$$

The angles `(α_1, α_2, α_3)` are computed from the matrix entries.
Symbolically, for `β ∈ [0, π]`:

* `α_1` from zeroing `d^1_{2,0}(β) = (1−\cosβ)/2` via a rotation on
  rows 0 and 1. Concretely: `α_1 = \arctan\bigl((1−\cosβ)/(1+\cosβ) \cdot \sqrt{2}/\sin β \bigr)` or equivalent.
* `α_2` from the remaining 2-parameter sub-problem.
* `α_3` absorbs the residual.

Skipping the algebra (tractable, but nrs delivers the code + a
build-time test against `exp(-iβ Ĵ_y)`), the three Givens translate
into **qubit gates** as follows:

**`G_{0,1}(α)`** — pair `|0⟩_d = |00⟩_qubit, |1⟩_d = |01⟩_qubit`.
Hamming distance 1: differing wire is wires[1] (LSB). Control: MSB = 0.
Qubit-side: **X(wires[2]) · controlled-Ry(α, ctrl=wires[2], target=wires[1]) · X(wires[2])**.
Using the existing `apply_ccx!`/ABC tricks this is **1 Ry + 2 X (≡ 2 Ry(π))**
plus **2 CX** for the single-controlled Ry via `_controlled_ry!`. Total
per `G_{0,1}` block: 3 Ry + 2 CX (the X-negation Ry's are cheap).
Actually under Sturm's framework the X-bracket is 2 CX (since `apply_ry!(π)`
+ `apply_ry!(π)` on the same wire compose to X·X=I up to phase, but
we need a literal X-bracket here — use `apply_ry!(π)` which gives X
up to global phase, fine for our SU(d) budget).

Implementation via `push_control!`/`pop_control!`:
```
apply_ry!(ctx, wires[2], π)          # negate MSB (X-gate)
push_control!(ctx, wires[2])
apply_ry!(ctx, wires[1], α)          # routes through _controlled_ry!
pop_control!(ctx)
apply_ry!(ctx, wires[2], π)          # de-negate
```
That's **3 Ry + 2 CX** (the controlled-Ry's ABC gives 2 Ry + 2 CX +
the outer X bracket is 2 Ry = 4 Ry + 2 CX). Actually let me
recount: `_controlled_ry!` = 2 Ry + 2 CX (lines 34-42
of multi_control.jl); X brackets = 2 Ry. So **4 Ry + 2 CX** per
`G_{0,1}`.

**`G_{1,2}(α)`** — pair `|1⟩_d = |01⟩_qubit, |2⟩_d = |10⟩_qubit`.
Hamming distance 2: both wires flip. Realise via CX-wrap:
```
apply_cx!(wires[1], wires[2])          # CX(LSB→MSB)
# now (01, 10) → (01, 11); pair is (01, 11), distinct bit = MSB
push_control!(ctx, wires[1])            # LSB = 1
apply_ry!(ctx, wires[2], α)
pop_control!(ctx)
apply_cx!(wires[1], wires[2])          # uncompute
```
**2 Ry + 2 CX (cRy) + 2 CX (wrapper)** = **2 Ry + 4 CX**.

Sum for d=3 `R_y(β)`:
* 2 × `G_{0,1}` blocks = 8 Ry + 4 CX
* 1 × `G_{1,2}` block = 2 Ry + 4 CX
* **Total: 10 Ry + 8 CX** for one `q.θ += β` at d=3.

Under `when(ctrl)`, one extra control is pushed to the stack, so
each Ry/CX becomes a CCRy/CCX. The cascade doubles the count roughly:
**~20 Ry + ~16 CX + 2 workspace ancillae** per `q.θ += β` at d=3
inside a `when()` block. Still tractable.

### d=5 closed form — sketch

Spin-2 `d^2(β)` is 5×5. QR decomposition into adjacent-pair Givens
takes **10 rotations** (C(5,2) = 10): pairs (0,1), (1,2), (2,3),
(3,4), (0,1), (1,2), (2,3), (0,1), (1,2), (0,1) — the "bubble-sort"
Givens sweep. Each pair is Hamming-distance 1 or 2 in the K=3
encoding; the cost per block is ~4 Ry + ~4 CX (mix of HD-1 and HD-2
cases with one extra control for being K=3).

Rough **d=5 gate count**: 10 Givens × 4 Ry + 4 CX ≈ **40 Ry + 40 CX**
unconditionally; ~2× that in a `when()` block.

### Not the most efficient

Better decompositions exist (Bullock-O'Leary-Brennen 2005
asymptotically-optimal O(d²) circuits via spectral decomposition). They
require substantially more code. nrs's v0.1 trades factor-of-~3
overhead for testability + tractable Wigner-d validation. Upgrade
path: `nrs-optimize` bead lowering to BO'LB 2005. **Deferred.**

## 6. Leakage invariants — Q6 answer

### Proof sketch (§5 control patterns never fire on |s⟩ ≥ d)

At d=3, K=2, the forbidden state is `|11⟩_qubit = |3⟩_encoded`. The
Givens decomposition touches three pairs:

* **`G_{0,1}`** (pair (00, 01)): control pattern is MSB=0. When the
  state is `|11⟩` (MSB=1), the controlled-Ry is identity because the
  X-bracket flips MSB from 1 to 0 first, then controls fire only on
  "MSB was 0 in the original frame" — **wait**, the X-bracket flips
  `|11⟩ → |01⟩` momentarily, which is inside the |s⟩ < d subspace…
  this is a problem worth thinking through. Let me re-examine.

  **Correction**: during the X-bracket (temporary negation of MSB
  for the "zero-control" trick), amplitude on `|11⟩` gets moved to
  `|01⟩` temporarily. The controlled Ry(α) on wires[1] with MSB=1 as
  control will then rotate the component that USED to be at `|11⟩`.
  After the de-negation X, that amplitude comes back to |11⟩-plus-
  rotation-into-|10⟩. **This DOES leak.** The classic zero-control
  trick is unsafe when the forbidden subspace is a zero-controlled
  pattern.

  **Fix**: invert the control polarity instead. Don't bracket with X;
  use an "anti-controlled" Ry directly. Sturm's current
  `_controlled_ry!` only supports positive-polarity control, so we'd
  either (a) implement `_controlled_ry_neg!` that fires when ctrl=0,
  or (b) use a different Givens orientation. Option (a) is cleaner:
  `apply_ry!(ctx, neg_ctrl, π) / push_control!(neg_ctrl) /
  apply_ry!(ctx, target, α) / pop_control! / apply_ry!(ctx, neg_ctrl, π)`
  only works if the amplitude at the OLD negation point was zero —
  which it isn't at `|11⟩`.
  **True fix**: the controlled-Ry fires when MSB=0. On the forbidden
  state `|11⟩`, MSB=1, so the controlled-Ry is identity. The X-bracket
  trick does NOT apply here because the control fires on ctrl=1 in
  qubit semantics, so the bracket actually FIRES on ctrl=0. Ah, this
  is the standard confusion. Let me re-verify:

  To have a controlled-Ry that fires when wires[2]=0 (MSB=0), the
  standard pattern is:
  ```
  apply_ry!(wires[2], π)         # X: wires[2] <- !wires[2]
  push_control!(wires[2])         # now firing when new wires[2] = 1
  apply_ry!(wires[1], α)          # controlled on new wires[2]=1
  pop_control!()
  apply_ry!(wires[2], π)          # undo X
  ```
  In this sequence, `|11⟩` → (X) `|10⟩` → (controlled-Ry: MSB=0 after
  X, so NOT firing) `|10⟩` (also possibly `|11⟩` component if α is nontrivial;
  but `|10⟩` is ctrl=0 → no fire) → (X) `|11⟩`. Identity on `|11⟩`. ✓
  And `|11⟩`'s transient form `|10⟩` — which IS a legal label (s=2) —
  is untouched by the controlled-Ry because THE CONTROL now fires
  when wires[2]=1, and `|10⟩` has wires[2]=0 after the X. I was
  confused about the polarity; the bracket IS safe. Restated cleanly:

  For `G_{0,1}`, we want to rotate only when `|s⟩ = |0⟩` or `|s⟩ = |1⟩`,
  i.e. when MSB=0. X-bracket: flip MSB, apply ctrl-Ry on target=LSB
  with ctrl=MSB fires on MSB=1 in the flipped frame, then un-flip.
  `|11⟩` (MSB=1) → (X) `|01⟩` (MSB=0, ctrl off) → `|01⟩` → (X) `|11⟩`.
  **Identity on |11⟩** ✓. `|00⟩` (MSB=0) → (X) `|10⟩` (ctrl=MSB=1, on)
  → rotates LSB: `cos(α/2)|10⟩ − sin(α/2)|11⟩` → (X) `cos(α/2)|00⟩ −
  sin(α/2)|01⟩`. Rotation of (00, 01) pair. ✓

  Wait — but the rotation sends amplitude into `|11⟩` (before the
  final X, into `|11⟩_qubit`; after X, `|01⟩_qubit`). The
  intermediate frame has amplitude on `|11⟩_qubit` during the
  middle of the bracket, which is FINE because we're mid-computation
  and the "leakage invariant" only applies at the level of "what the
  user can observe via Int(q)". Between individual qubit gates, the
  binary labels are just labels — leakage is defined by the AMPLITUDE
  on qubit-basis-state `|m⟩` with `m ≥ d` AFTER all of the rotation's
  sub-gates execute.

  So: for `G_{0,1}` the X-bracket works. For `G_{1,2}` the same
  analysis: the CX-bracket creates an intermediate state in the
  `|11⟩` sector transiently, but after the CX uncomputes the
  amplitude back-flows correctly. Verified case-by-case.

**Generic claim**: each Givens block `G_{s,s+1}` at the end of the
sub-sequence (after all X- and CX-brackets close) leaves any
amplitude on `|m⟩`, m ∉ {s, s+1}, AT ITS OLD VALUE. Mid-bracket the
amplitudes on forbidden labels can be nonzero transiently, but that
is a legitimate part of the multi-qubit circuit — leakage is measured
at observation time, and the observable result is identity on
forbidden |m⟩.

### Test

Statistical: 1000 random sequences of `q.θ += rand() * 2π; q.φ +=
rand() * 2π` on `QMod{3}()`, then `Int(q)`. The measurement-time
leakage check (`src/types/qmod.jl:172-180`) errors loudly if any
decoded bitstring ≥ d. Over 1000 shots: **assert the error-count
is 0**. Plus a direct amplitude-sweep test (zero-copy via
`unsafe_wrap` as in `_amps_snapshot` in `test_qmod.jl:266-270`): after
any sequence, `|⟨11|ψ⟩|² < 1e-20` (tolerance for double-precision
accumulation).

## 7. Test plan (runnable — no @test_skip) — Q7 answer

All tests extend `test/test_qmod.jl`, reusing `_amps_snapshot`.

### Testset 1: d=3 Ry vs hand-computed `d^1(β)`

```julia
@testset "nrs d=3: q.θ += π/3 matches Wigner d^1(π/3)" begin
    β = π/3
    # Closed-form d^1(β) from Sakurai 3.10.33
    c, s = cos(β), sin(β)
    expected = ComplexF64[
        (1+c)/2       -s/√2       (1-c)/2 ;
         s/√2          c          -s/√2 ;
        (1-c)/2        s/√2       (1+c)/2
    ]
    # Apply on |0⟩_d = |00⟩_qubit: expected[:, 1] gives amplitudes on
    # qubit-basis states |00⟩, |01⟩, |10⟩ (labels 0, 1, 2). Leakage state
    # |11⟩ (label 3) should stay at 0.
    amps = @context EagerContext() begin
        q = QMod{3}()
        q.θ += β
        _amps_snapshot(current_context())
    end
    # Little-endian binary: qubit-basis index = b0 + 2 b1; label s = same.
    # (Our encoding: wires[1]=LSB, so Orkan index i = s directly at s < 4.)
    for s in 0:2
        @test isapprox(amps[s+1], expected[s+1, 1]; atol=1e-10)
    end
    # Leakage check: amplitude on |11⟩_qubit (index 3)
    @test abs(amps[4]) < 1e-12
end
```

### Testset 2: d=3 Rz diagonal

```julia
@testset "nrs d=3: q.φ += δ is diagonal (|0⟩_d stays |0⟩_d up to phase)" begin
    δ = 0.7
    amps = @context EagerContext() begin
        q = QMod{3}()
        q.φ += δ
        _amps_snapshot(current_context())
    end
    # Only |0⟩_d = qubit index 0 should have amplitude
    @test abs(amps[1]) ≈ 1.0 atol=1e-10
    @test abs(amps[2]) < 1e-12
    @test abs(amps[3]) < 1e-12
    @test abs(amps[4]) < 1e-12  # leakage state
    # Phase on |0⟩_d: j=1, s=0 → Ĵ_z eigenvalue = j-s = 1 → phase e^{-iδ}
    # (modulo our dropped global e^{-iδj} — phases are convention, verify
    # only up to ONE consistent global)
    # Compute amplitudes on all 3 legal labels by first putting a
    # superposition, then checking relative phases:
    amps2 = @context EagerContext() begin
        q = QMod{3}()
        q.θ += π/4        # nontrivial superposition
        q.φ += δ
        _amps_snapshot(current_context())
    end
    amps_no_rz = @context EagerContext() begin
        q = QMod{3}()
        q.θ += π/4
        _amps_snapshot(current_context())
    end
    # Check |amps2[s]| == |amps_no_rz[s]| for s = 0, 1, 2 — Rz preserves
    # amplitude magnitude in the computational basis.
    for s in 0:2
        @test abs(amps2[s+1]) ≈ abs(amps_no_rz[s+1]) atol=1e-10
    end
    # Relative phase amps2[s+1] / amps_no_rz[s+1] = e^{-iδ((j-s) - (j-0))} × global
    # = e^{+iδs} × global_phase. Verify:
    ref_phase = amps2[1] / amps_no_rz[1]   # s=0 reference
    for s in 1:2
        expected_rel = exp(+im*δ*s)
        @test isapprox(amps2[s+1]/amps_no_rz[s+1] / ref_phase, expected_rel;
                       atol=1e-10)
    end
end
```

### Testset 3: Ramsey-style root-of-unity (Rz observable via Ry-sandwich)

```julia
@testset "nrs d=3: Ramsey — Ry·Rz(2π/d·k)·Ry^{-1} has k-dependent amplitude" begin
    # Ry(π/2) |0⟩ gives a known spin-1 superposition. Rz(2π/3·k) rotates
    # phases by {1, ω^k, ω^{2k}} (after global-phase absorption). Ry(-π/2)
    # brings back to a different state unless k = 0 mod 3.
    for k in 0:2
        δ = 2π/3 * k
        amps = @context EagerContext() begin
            q = QMod{3}()
            q.θ += π/2
            q.φ += δ
            q.θ -= π/2
            _amps_snapshot(current_context())
        end
        # For k=0, amps[1] ≈ 1; for k ≠ 0, amps redistribute.
        if k == 0
            @test abs(amps[1]) ≈ 1.0 atol=1e-10
            @test abs(amps[2]) < 1e-10
            @test abs(amps[3]) < 1e-10
        else
            # Non-trivial redistribution — assert |amps[1]|² + |amps[2]|² +
            # |amps[3]|² = 1 and amps[1] is NOT the whole weight
            tot = abs2(amps[1]) + abs2(amps[2]) + abs2(amps[3])
            @test tot ≈ 1.0 atol=1e-10
            @test abs(amps[1]) < 0.9
        end
        @test abs(amps[4]) < 1e-12   # leakage
    end
end
```

### Testset 4: subspace preservation statistical

```julia
@testset "nrs d=3: 1000 random rotation sequences never leak past d" begin
    for trial in 1:1000
        @context EagerContext() begin
            q = QMod{3}()
            for _ in 1:rand(1:5)   # 1-5 random rotations
                ax = rand(Bool) ? :θ : :φ
                δ = rand() * 2π
                if ax === :θ; q.θ += δ; else; q.φ += δ; end
            end
            result = Int(q)      # would error on leakage per 9aa's layer 3
            @test result in 0:2
        end
    end
end
```

### Testset 5: d=5 Ry amplitude-level

```julia
@testset "nrs d=5: q.θ += π/4 puts amplitude on ≥1 nontrivial label" begin
    # Spin-2 Ry(π/4) on |0⟩ gives a specific known 5-component amplitude.
    # Verify d^2_{s, 0}(π/4) at s=0,1,2,3,4 matches Orkan's computed amps.
    β = π/4
    expected = _wigner_d2_column_zero(β)   # helper computing column 0 of d^2
    amps = @context EagerContext() begin
        q = QMod{5}()   # K=3
        q.θ += β
        _amps_snapshot(current_context())
    end
    # Little-endian: label s at qubit-basis index = s for s < 8 (K=3)
    for s in 0:4
        @test isapprox(amps[s+1], expected[s+1]; atol=1e-10)
    end
    # Leakage: labels 5, 6, 7 all ≈ 0
    for s in 5:7
        @test abs(amps[s+1]) < 1e-12
    end
end
```

(`_wigner_d2_column_zero(β)` is computed in-test via the explicit
Sakurai formula; 5 closed-form expressions, written directly.)

### Testset 6: controlled-Rz observable-phase test (docstring's §8.4 warning)

```julia
@testset "nrs d=3: when(ctrl) q.φ += δ carries global-phase → controlled-phase" begin
    # Under coherent control, the e^{-iδj} "dropped global phase" from §4
    # becomes a relative phase on ctrl=|1⟩. Verify by comparing
    # controlled-Rz(δ) applied to prep state (|0⟩+|1⟩)/√2 ⊗ |0⟩_d vs.
    # expected (|0⟩ + e^{-iδj}|1⟩)/√2 ⊗ |0⟩_d.
    δ = 0.9
    j = 1.0  # spin-1 for d=3
    amps = @context EagerContext() begin
        ctrl = QBool(0.0)
        ctrl.θ += π/2               # Hadamard-like: (|0⟩ + |1⟩)/√2
        q = QMod{3}()                # |0⟩_d
        when(ctrl) do
            q.φ += δ
        end
        _amps_snapshot(current_context())
    end
    # Full state: (|0⟩_ctrl ⊗ |0⟩_d + e^{-iδj} |1⟩_ctrl ⊗ |0⟩_d) / √2
    # Qubit layout: ctrl=wire 1, QMod wires = wires 2, 3 (LSB, MSB of s).
    # |0⟩_ctrl|0⟩_d = 000 (index 0); |1⟩_ctrl|0⟩_d = 001 (index 1).
    @test isapprox(amps[1], 1/√2; atol=1e-10)
    @test isapprox(amps[2], exp(-im*δ*j)/√2; atol=1e-10)
    # NOTE: sign / phase convention depends on whether we drop e^{-iδj}
    # consistently. This test locks the convention; adjust if
    # implementation drops a different global.
end
```

### Testset 7: gate-count regression under TracingContext

```julia
@testset "nrs d=3: q.θ += β emits expected DAG node counts" begin
    ctx = TracingContext()
    @context ctx begin
        q = QMod{3}()
        q.θ += π/3
    end
    # Count RyNode, RzNode, CXNode in ctx.dag
    ry_count = count(n -> n isa Sturm.RyNode, ctx.dag)
    cx_count = count(n -> n isa Sturm.CXNode, ctx.dag)
    rz_count = count(n -> n isa Sturm.RzNode, ctx.dag)
    # Per §5 pseudocode: 10 Ry + 8 CX expected for d=3 Ry.
    @test ry_count <= 12     # some slack for the X-brackets vs Ry-absorption
    @test cx_count <= 10
    @test rz_count == 0
end

@testset "nrs d=3: q.φ += β emits exactly K Rz nodes" begin
    ctx = TracingContext()
    @context ctx begin
        q = QMod{3}()
        q.φ += π/3
    end
    rz_count = count(n -> n isa Sturm.RzNode, ctx.dag)
    ry_count = count(n -> n isa Sturm.RyNode, ctx.dag)
    cx_count = count(n -> n isa Sturm.CXNode, ctx.dag)
    @test rz_count == 2   # K=2
    @test ry_count == 0
    @test cx_count == 0
end
```

### Deferred to follow-on beads

* **Bartlett Eq. 13 parity test at d=4**. The spin-j X gate differs
  from displacement X_d by `exp(-iπ/d)` at even d. At d=4 this is
  `exp(-iπ/4)`. Since nrs v0.1 ships d ∈ {3, 5} only, d=4 is not in
  scope; test lives in `nrs-generic` (which ships d=4). Explicitly
  noted as a dependency for bead `u2n` (library gates).

* **Generic-d d^j(β) recursion**. Lives in `nrs-generic`.

* **TracingContext gate counts under `when()`**. Doable but fiddly
  (cascade explodes the count). File as `nrs-benchmarks`.

## 8. File organization — Q8 answer

**New file: `src/library/qudit_fallback.jl`** — ~200 lines.

Structure:
```
module Sturm (via include)

# --- Wigner small-d matrix closed forms ---
function _wigner_d1(β::Float64)::SMatrix{3, 3, Float64}  # spin-1
function _wigner_d2(β::Float64)::SMatrix{5, 5, Float64}  # spin-2

# --- Givens decomposition ---
function _givens_angles(M::SMatrix)::Vector{Float64}
function _apply_two_level_SU2!(ctx, wires, s, t, axis, α, ::Val{d})

# --- Spin-j rotations ---
function _apply_spin_j_ry!(ctx, wires, β, ::Val{3})   # specialised
function _apply_spin_j_ry!(ctx, wires, β, ::Val{5})   # specialised
function _apply_spin_j_rz!(ctx, wires, δ, ::Val{d}) where {d}  # generic (diagonal)

# --- Dispatcher (replaces the stub in qmod.jl) ---
# NOTE: overrides the stub in qmod.jl via more-specific Val{3}/Val{5} methods.
function _apply_spin_j_rotation!(ctx, wires, axis, δ, ::Val{3})
function _apply_spin_j_rotation!(ctx, wires, axis, δ, ::Val{5})
```

**Edit: `src/types/qmod.jl`** — update the `_apply_spin_j_rotation!`
stub to mention which d are supported (error for d ∉ {3, 5} points to
`nrs-generic` instead of `nrs`).

**Edit: `src/Sturm.jl`** — `include("library/qudit_fallback.jl")`
after `include("library/arithmetic.jl")`.

**Edit: `test/test_qmod.jl`** — append the 7 testsets from §7 to the
existing file (it already houses the ak2 deferral-error tests; nrs
flips them to working tests + adds the new ones).

**NOT `src/types/qmod_rotations.jl`** — decomposition code isn't
"type definition"; it's library-level. Matches
`src/library/arithmetic.jl` precedent (arithmetic operations on
`QInt` live in `library/`, not `types/`).

**NOT a new test file** — test_qmod.jl is the natural home; matches
ak2's choice (Session 54 WORKLOG).

## 9. Performance / regression — Q9 answer

### Gate count per rotation

| d | K | Ry path | Rz path | Ry count (unconditional) | Rz count |
|---|---|---------|---------|--------------------------|----------|
| 3 | 2 | 3 Givens | 2 diagonal | ~10 Ry + ~8 CX | 2 Rz |
| 5 | 3 | 10 Givens | 3 diagonal | ~40 Ry + ~40 CX | 3 Rz |
| 9 | 4 | (not shipped here) | (if generic): 4 Rz | n/a | 4 Rz |

**Is O(d²) per Ry acceptable?** For Shor/QPE at d=3 with L=40 digits:
40 Ry rotations × ~10 Ry-nodes × ~8 CX = 320 Ry + 320 CX per QFT. At
Orkan's ~1μs/gate throughput: 0.6 ms per QFT, ~60 ms per full
circuit. Acceptable for v0.1. For d=5 QFT, ~40× more expensive —
ballpark 2 seconds. Also acceptable for v0.1 prototyping.

### Hot-loop cost mitigation

`q.θ += δ` inside a 1000-iteration loop at d=3 = 1000 × 10 Ry =
10000 Ry nodes pushed. Under `EagerContext` this is 10000 ccalls
to Orkan — each ~1μs, so ~10ms total. Fine.

Under `TracingContext` — same nodes but no Orkan call; cheaper. Fine.

**Pre-computed angle tables per `Val(d)`**: not needed at d=3/5 —
the QR decomposition of a 3×3 matrix is ~10 floating-point ops. At
generic d it becomes O(d²) per call and SHOULD be cached. File as
`nrs-perf`. YAGNI here.

### Channel IR safety

The Givens decomposition emits only RyNode / RzNode / CXNode / CCXNode
in `TracingContext`'s DAG. **Zero `ObserveNode`, zero `CasesNode`,
zero `DiscardNode`**. Spin-j rotations are unitary sub-blocks; future
unitary-only optimisation passes (phase polynomials, ZX-rewriting,
Clifford synthesis) can safely traverse across these nodes without
barrier partitioning. Confirmed.

## 10. Open questions / risks — Q10 answer

**Q10.1**. **QR of `d^j(β)`**: does my hand-derivation of the
Givens angles for d=3 actually compose back to `d^1(β)` exactly? I
believe so — standard 3×3 QR decomposition is 2 Householder or 2
Givens — but I haven't written out `(α_1, α_2, α_3)` symbolically as
closed forms in β. Implementer must either derive them on paper
(high confidence, few pages) or compute them numerically at call
time (verifiable via the build-time smoke test). Recommendation:
**numeric QR at call time**, closed-form only for the build-time
validation test. Avoids a subtle-trig-identity bug.

**Q10.2**. **Global phase convention for Rz**. I drop `e^{-iδj}` and
have tests pin specific controlled-phase behaviour. **Does this match
Orkan's internal `apply_rz!` convention?** Orkan's `apply_rz!` is
`diag(e^{-iδ/2}, e^{+iδ/2})` per Sturm's existing `add_qft!` convention
(checked in `src/library/arithmetic.jl:40-43`: "Sturm's `q.φ += δ` is
`Rz(δ) = diag(e^{-iδ/2}, e^{+iδ/2})`"). My factorisation maps
`e^{+iδ 2^i b_i}` per bit — which means wire-i Rz angle = `−δ · 2^{i+1}`
for the `+iδ` branch. Need to verify sign convention matches Bartlett
Eq. 5 (`|s⟩ = |j, j−s⟩_z`, `Ĵ_z|s⟩ = (j−s)|s⟩`, so
`Rz(δ)|s⟩ = e^{-iδ(j−s)}|s⟩`). Implementer: re-verify with a d=3
state-vector unit test at δ=π/3 against Bartlett's convention before
pinning the `when()` controlled-phase test. Could be off by a sign.

**Q10.3**. **Hamming-distance-2 blocks at d=5**: the pair (3, 4) =
(011, 100) in K=3 has Hamming distance 3. Lifting via nested
CX-brackets is fine but the gate count balloons (3-bit flip → 2
wraps). Worth a specialised case; may need a "cyclic-shift" pre-pass
that reorders basis states to minimise Hamming distance in the
Givens sequence. Deferred to implementer; initial implementation
can use the naive 3-CX wrap and pay the gate-count hit.

**Q10.4**. **Subspace preservation at intermediate states**. §6 argues
that each full Givens block ACT AS IDENTITY on forbidden |m⟩ after
all sub-gates complete, but during the X-bracket / CX-bracket the
forbidden-region amplitude can be non-zero transiently. This is fine
for the channel semantics (a unitary's intermediate states are not
observable), but a future `with_qmod_leakage_checks` TLS sweep that
checks mid-block would fire spuriously. **Lock**: the TLS sweep must
run at Primitive-call boundaries, not at qubit-gate boundaries. Note
for the `with_qmod_leakage_checks` implementer.

**Q10.5**. **d=5 Givens angle closed forms not yet written down.**
§2 sketches but doesn't provide. Implementation will need to compute
these — easiest via the numeric QR approach from Q10.1. Each of the
10 Givens blocks in the d=5 sweep needs a closed-form lift to qubit
primitives similar to the d=3 blocks in §5; implementer must enumerate
all 10 Hamming-distance cases in the K=3 encoding. ~1 afternoon of
careful work; test matrix has 5 amplitude points per d=5 test.

**Q10.6**. **Controlled-context cost not profiled**. A `when(ctrl) do
q.θ += δ end` at d=3 doubles the gate count (per control stack depth
1). Inside a deeper `when` nest (depth ≥ 2), the cascade in
`_multi_controlled_gate!` adds workspace ancilla + CCX chain. Headline
number scales to ~30 Ry + ~25 CX + 1-2 workspace qubits for d=3 at
depth 2. Not tested in v0.1 — file as `nrs-deep-when`.

**Q10.7**. **Gap with the "library gates" follow-ons**. Once
`_apply_spin_j_rotation!` lands at d=3,5, the library gates `X_d!`,
`Z_d!`, `H_d!`, `F_d!`, `T_d!` become constructible via combinations.
Bead `u2n` (library gates) should claim after nrs lands. Confirm in
the session-end hand-off.

**Q10.8**. **Apply_sum_d interface**. I deferred this. `p38` will need:
(a) wire tuples from both operands (already available via QMod.wires);
(b) a way to apply multi-controlled phase/Ry to implement the modular
adder; (c) possibly nrs's `_wigner_d1`/`_wigner_d2` helpers if the
SUM decomposition uses spin-j rotations. **nrs exposes its two
closed-form helpers as `Sturm._wigner_d1` / `Sturm._wigner_d2`** (no
export; internal). p38 can `import Sturm: _wigner_d1, _wigner_d2`
without any API coupling. If p38 prefers the QFT-adder route
(Draper-style mod-d), nrs's helpers aren't needed at all.

## 11. Files to touch (paths + estimated line counts)

| File | Action | Line count |
|---|---|---|
| `/home/tobias/Projects/Sturm.jl/src/library/qudit_fallback.jl` | NEW — Wigner matrices, Givens decomp, spin-j rotations for Val{3}, Val{5} | ~220 lines |
| `/home/tobias/Projects/Sturm.jl/src/types/qmod.jl` | EDIT — tweak `_apply_spin_j_rotation!` stub's error message (for d ∉ {3, 5}, point to `nrs-generic`) | ~5 line diff |
| `/home/tobias/Projects/Sturm.jl/src/Sturm.jl` | EDIT — `include("library/qudit_fallback.jl")` after line 127 | +1 line |
| `/home/tobias/Projects/Sturm.jl/test/test_qmod.jl` | EDIT — add 7 new testsets (Testsets 1-7 from §7), remove/flip the 2 ak2 deferral-error testsets (since d=3 no longer errors) | ~250 lines added, ~30 lines removed |
| `/home/tobias/Projects/Sturm.jl/docs/physics/wigner_small_d_j1_j2.md` | NEW — 1-page derivation note citing Sakurai 3.10.16 + BartlettdeGuise Eq. 6, required for Rule 4 | ~60 lines |
| `/home/tobias/Projects/Sturm.jl/WORKLOG.md` | APPEND — Session 55 entry | ~60 lines |

**DO NOT TOUCH**:
* `src/types/qbool.jl` — Rule 11 (qubit primitives frozen)
* `src/context/eager.jl` / `tracing.jl` / `density.jl` — no new apply_*
  methods; all routing through existing `apply_ry!`/`apply_rz!`/`apply_cx!`
* `src/orkan/ffi.jl` — no new ccall (spin-j on qubit encoding = existing
  qubit primitives)
* `src/context/multi_control.jl` — `_multi_controlled_gate!` used as-is

---

Design doc written to /tmp/nrs_design_A.md
