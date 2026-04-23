# Sturm.jl-ixd (d=5 scope) — QMod{5} Ry primitive via Euler sandwich
#
# Implements `q.θ += δ` at d=5, j=2 via the SU(2) Euler identity
#
#     exp(-i δ Ĵ_y) = Rz_j(π/2) · Ry_j(π/2) · Rz_j(δ) · Ry_j(-π/2) · Rz_j(-π/2)
#
# where each factor is the spin-j SU(2) rotation obtained from the
# functor SU(2) → U(2j+1). The advantage:
#   * `Rz_j(α)` is the δ-dependent middle — shipped by `Sturm.jl-nrs` as
#     per-wire single-qubit `apply_rz!` (K gates). Reused verbatim.
#   * `Ry_j(±π/2)` are δ-INDEPENDENT fixed unitaries. Precomputed once via
#     a QR-into-Givens factorisation of `V₅ = d²(π/2)` (the 5×5 real
#     orthogonal Wigner matrix at β = π/2). The 10 Givens angles are
#     stored as a const tuple and emitted as a fixed qubit circuit.
#
# ## Per-Givens qubit lowering (orchestrator-verified to 3e-16 for V₅ ⊕ I₃)
#
# Each Givens G_{s, s+1}(θ) acting on levels s, s+1 of the 5-dim subspace
# (identity on labels ≥ 5) is lowered to Sturm primitives by:
#
#   1. Compute bit patterns b_lo = binary(s), b_hi = binary(s+1) and their
#      Hamming distance H.
#
#   2. If H = 1: the pair differs in exactly one bit `target`. Emit a
#      multi-controlled Ry on that bit, controlled on the other K-1 bits
#      matching their common value in the pair. (Negated controls realised
#      by Ry(π) sandwich brackets.)
#
#   3. If H ≥ 2: pick pivot = highest-index differing bit. Apply forward
#      CX chain CX(pivot, k) for each other differing bit k — this flips
#      bit k in whichever pair member has pivot = 1, reducing the pair to
#      Hamming 1 in the pivot dimension. Then multi-controlled Ry on
#      pivot, controlled on all non-pivot bits matching their post-CX
#      common value. Then uncompute CX chain.
#
#      SIGN FIX: if the POST-CX lower label has pivot-bit = 1, the Ry
#      convention places the lower label on the "|1⟩" side of the
#      rotation, flipping the sine sign. Negate θ in that case. (This is
#      the k8u-style sign bug; verified numerically to machine epsilon.)
#
# Orchestrator-verified numerics (before this code was written):
#   * Each Givens block's 8×8 qubit circuit matches G_{s,s+1}(θ) ⊕ I_6
#     to err = 0.0.
#   * Full V₅ (10 Givens) circuit matches V₅ ⊕ I_3 to 3e-16.
#   * Leakage subspace (labels 5, 6, 7) transits through CX chains but
#     returns to zero amplitude on exit (amplitude-preserving permutation
#     of leakage states).
#
# ## Global phase under `when()`
#
# On the d=5 subspace, the sandwich equals `exp(-iδĴ_y)` up to a global
# phase `ξ(δ) = exp(iδ[j − (2^K−1)/2]) = exp(-1.5iδ)` (for d=5: j=2, K=3).
# This phase comes from the nrs Rz factorisation — the fixed outer
# Rz(±π/2) contributions cancel. Under `when(ctrl)`, ξ(δ) becomes a
# controlled relative phase (same as the nrs Rz path per §8.4 policy).
# Documented and accepted; identical precedent to `q.φ += δ` at d ≥ 3.
#
# ## References
#   * `docs/physics/bartlett_deGuise_sanders_2002_qudit_simulation.pdf` Eq. 5.
#   * `docs/design/ixd_design_{A,B}.md` (3+1 review round).
#   * `docs/design/k8u_design_{A,B}.md` (prior Ry at d=3 bead).
#   * `docs/physics/brennen_bullock_oleary_2005_efficient_qudit_circuits.pdf`
#     §3 — QR-into-Givens construction for qudit circuits.
#   * `docs/physics/qudit_magic_gate_survey.md` §8.4 — global-phase policy.
#   * WORKLOG Session 57 (2026-04-23) — orchestrator synthesis.
#
# See bead `Sturm.jl-ixd` (d=5 portion).

"""
Fixed Givens decomposition of V₅ = d²(π/2) into 10 adjacent-pair rotations.
Each tuple `(pair_lo, θ)` denotes G_{pair_lo, pair_lo+1}(θ). Applied
left-to-right — the FIRST entry is the FIRST gate emitted (= rightmost in
the matrix product acting on |ψ⟩).

Angles derived by QR-zeroing below-diagonal entries of V₅ (= d²(π/2)):

    for col = 1 .. d-1:
        for i = d .. col+1 (decreasing):
            a = M[i-1, col];  b = M[i, col]
            r = √(a² + b²);   c = a/r;  s = b/r
            # left-multiply by G_{i-1,i}(-θ) to zero M[i, col]:
            M[i-1, :], M[i, :] = c·M[i-1, :] + s·M[i, :], -s·M[i-1, :] + c·M[i, :]
            append (i-1, 2·atan2(b, a))
        end
    end
    (returned ops are inverse Givens; reverse+take-as-stated = forward)

The 10 tuples below are FLOAT64-LITERAL-PRECISE (written via `repr(θ)`) —
NOT truncated. Each is exactly the Float64 returned by the QR. A
regression test in `test/test_qmod.jl` recomputes the angles from a
fresh V₅ and asserts bit-identical agreement — do NOT edit by hand with
fewer digits (Session 57 learning: 16-digit decimal transcription
introduced 1e-8 errors in Orkan's statevector output; debugged via
per-Givens circuit-vs-target comparison).
"""
const _RY_J_HALFPI_D5_OPS = (
    (3, 0.9272952180016119),
    (2, 1.479761548757481),
    (3, 0.8479278926781093),
    (1, 2.0563144490904874),
    (2, 1.3753393038222432),
    (3, 0.8479278926781089),
    (0, 2.6362321433056364),
    (1, 2.0563144490904874),
    (2, 1.4797615487574811),
    (3, 0.9272952180016122),
)

"""
    _givens_block_d5!(ctx, wires, pair_lo, θ)

Emit the qubit-level circuit for a single Givens `G_{pair_lo, pair_lo+1}(θ)`
at d=5, K=3. Dispatches on `pair_lo ∈ {0, 1, 2, 3}` (the four possible
adjacent pairs at d=5). Each branch is hand-derived from the Hamming-
distance analysis and verified numerically before inclusion.

Wire layout (little-endian): `wires[1]` = bit 0 (LSB), `wires[2]` = bit 1,
`wires[3]` = bit 2 (MSB). Labels:

    0 = (0,0,0)   1 = (1,0,0)   2 = (0,1,0)   3 = (1,1,0)   4 = (0,0,1)
    leakage: 5 = (1,0,1), 6 = (0,1,1), 7 = (1,1,1)

  * pair (0, 1) — H=1, target = bit 0; controls (bit 1 = 0, bit 2 = 0).
  * pair (1, 2) — H=2, pivot = bit 1, reduce via CX(bit 1, bit 0); post-CX
    controls (bit 0 = 1, bit 2 = 0). Sign: lower label post-CX is (1,0,0),
    pivot-bit = 0 → no sign flip.
  * pair (2, 3) — H=1, target = bit 0; controls (bit 1 = 1, bit 2 = 0).
  * pair (3, 4) — H=3, pivot = bit 2, reduce via CX(bit 2, bit 0) then
    CX(bit 2, bit 1); post-CX controls (bit 0 = 1, bit 1 = 1). Sign: lower
    label post-CX is (1,1,0), pivot-bit = 0 → no sign flip.
"""
function _givens_block_d5!(
    ctx::AbstractContext, wires::NTuple{3, WireID}, pair_lo::Int, θ::Real,
)
    w0, w1, w2 = wires[1], wires[2], wires[3]
    if pair_lo == 0
        # H=1, target = w0, controls (w1=0, w2=0) — both negated.
        apply_ry!(ctx, w1, π)
        apply_ry!(ctx, w2, π)
        push_control!(ctx, w1)
        push_control!(ctx, w2)
        apply_ry!(ctx, w0, θ)
        pop_control!(ctx)
        pop_control!(ctx)
        apply_ry!(ctx, w2, -π)
        apply_ry!(ctx, w1, -π)
    elseif pair_lo == 1
        # H=2, pivot = w1. Forward CX(w1, w0); post-CX pair is (w0=1, w1=*, w2=0).
        # Controls: w0=1 (positive), w2=0 (negated). Target: w1. Sign: +θ.
        apply_cx!(ctx, w1, w0)
        apply_ry!(ctx, w2, π)          # negate w2 control
        push_control!(ctx, w0)
        push_control!(ctx, w2)
        apply_ry!(ctx, w1, θ)
        pop_control!(ctx)
        pop_control!(ctx)
        apply_ry!(ctx, w2, -π)
        apply_cx!(ctx, w1, w0)
    elseif pair_lo == 2
        # H=1, target = w0, controls (w1=1 positive, w2=0 negated).
        apply_ry!(ctx, w2, π)
        push_control!(ctx, w1)
        push_control!(ctx, w2)
        apply_ry!(ctx, w0, θ)
        pop_control!(ctx)
        pop_control!(ctx)
        apply_ry!(ctx, w2, -π)
    elseif pair_lo == 3
        # H=3, pivot = w2. Forward CX(w2, w0), CX(w2, w1); post-CX pair is
        # (w0=1, w1=1, w2=*). Controls: w0=1, w1=1 (both positive). Sign: +θ.
        apply_cx!(ctx, w2, w0)
        apply_cx!(ctx, w2, w1)
        push_control!(ctx, w0)
        push_control!(ctx, w1)
        apply_ry!(ctx, w2, θ)
        pop_control!(ctx)
        pop_control!(ctx)
        apply_cx!(ctx, w2, w1)
        apply_cx!(ctx, w2, w0)
    else
        error("_givens_block_d5!: pair_lo must be 0..3, got $pair_lo")
    end
    return nothing
end

"""
    _apply_ry_j_halfpi_d5!(ctx, wires, sign::Int)

Emit the qubit-level circuit for `Ry_j(sign · π/2)` at d=5 via the 10-
Givens factorisation. `sign = +1` for `Ry_j(+π/2)` (forward Givens order
with the tabled angles); `sign = -1` for `Ry_j(-π/2)` (reversed Givens
order, every angle negated — since `V₅⁻¹ = V₅ᵀ` and reversing the
product order with negated Ry angles gives the transpose).

Invariant: leaves leakage labels (5, 6, 7) invariant up to a transient
permutation within the leakage block; amplitudes on those labels stay at
zero if they start at zero.
"""
@inline function _apply_ry_j_halfpi_d5!(
    ctx::AbstractContext, wires::NTuple{3, WireID}, sign::Int,
)
    sign == 1 || sign == -1 ||
        error("_apply_ry_j_halfpi_d5!: sign must be ±1, got $sign")
    if sign == 1
        @inbounds for (pair_lo, θ) in _RY_J_HALFPI_D5_OPS
            _givens_block_d5!(ctx, wires, pair_lo, θ)
        end
    else
        @inbounds for (pair_lo, θ) in reverse(_RY_J_HALFPI_D5_OPS)
            _givens_block_d5!(ctx, wires, pair_lo, -θ)
        end
    end
    return nothing
end

"""
    _apply_spin_j_ry_d5!(ctx, wires::NTuple{3, WireID}, δ::Real)

Apply `exp(-i δ Ĵ_y)` on the spin-j = 2 (d = 5) irrep stored in three
qubit wires via the Euler sandwich. Gate count per call:

  * 3 × nrs Rz (each K = 3 apply_rz!): 9 apply_rz!.
  * 2 × fixed Ry_j(π/2) / Ry_j(-π/2) dressings (each 14 apply_ry! + 20
    apply_cx! + 10 multi-controlled-Ry via push_control!): approximately
    44 primitive slots per dressing.

Total roughly ~100 apply_* calls per `q.θ += δ` at d=5. The two fixed
dressings dominate; a follow-on bead may precompile them into flattened
lists for lower overhead. For v0.1 correctness this is fine.

Global phase on subspace: `ξ(δ) = exp(-1.5iδ)` (see file-level note).
Leakage states receive fixed-per-label phase that is unobservable when
leakage starts at zero amplitude.
"""
@inline function _apply_spin_j_ry_d5!(
    ctx::AbstractContext, wires::NTuple{3, WireID}, δ::Real,
)
    # exp(-iδĴ_y) = Rz(π/2) · Ry(π/2) · Rz(δ) · Ry(-π/2) · Rz(-π/2)
    # Applied to |ψ⟩: Rz(-π/2) first, then Ry(-π/2), etc.
    K = 3
    # Rz_j(-π/2) — nrs factorisation
    @inbounds for i in 1:K
        apply_rz!(ctx, wires[i], -π/2 * (1 << (i - 1)))
    end
    # Ry_j(-π/2) — fixed dressing inverse
    _apply_ry_j_halfpi_d5!(ctx, wires, -1)
    # Rz_j(δ) — nrs factorisation (δ-dependent middle)
    @inbounds for i in 1:K
        apply_rz!(ctx, wires[i], δ * (1 << (i - 1)))
    end
    # Ry_j(+π/2) — fixed dressing forward
    _apply_ry_j_halfpi_d5!(ctx, wires, +1)
    # Rz_j(+π/2) — nrs factorisation
    @inbounds for i in 1:K
        apply_rz!(ctx, wires[i], π/2 * (1 << (i - 1)))
    end
    return nothing
end
