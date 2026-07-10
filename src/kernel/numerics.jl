# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M1 (beads Sturm.jl-c52g +
# Sturm.jl-puig): kernel process values — the numeric substrate.
#
# Cross-cutting numeric policy for the kernel: tolerance constants, the
# circular (phase) distance, the ℤ₂ sign-fix on raw quaternion floats,
# the cheap in-range phase fold, and the tiny dependency-free matrix
# helpers used only by the OFF-hot-path `denoted_matrix` cross-checks.
#
# Physics grounding:
#   docs/physics/wharton_koch_quaternion_bloch.md — the unit-quaternion +
#     U(1)-phase representation of U(2), the 2-to-1 double cover
#     (q, φ) ~ (−q, φ+π), and the "one scalar rescale" numerics policy.
#   docs/physics/stuelpnagel_1964_rotation_parametrization.md — Thm 1:
#     γ(u)=γ(v) ⇔ u=−v; the double cover is a topological fact, not a
#     representational artifact, so the equality quotient is exactly ℤ₂.

# --- Tolerance / policy constants (documented against PRD-v2 §4.1) -----

"""
    U2_ATOL

Absolute tolerance for the normative U(2)-quotient equality `≈` on process
values (quaternion-component and circular-phase compare). Chosen above the
worst accumulated Hamilton-product drift (renorm holds it `< 2^-40`) and
above the irrational-π residue (`sin(Float64(π)) ≈ 1.2e-16`), yet below any
physically meaningful gate difference. See
`docs/physics/wharton_koch_quaternion_bloch.md` ("float laws compare with ≈").
"""
const U2_ATOL = 1e-10

"""
    RENORM_TOL

Renormalization cadence threshold on `|‖q‖² − 1|` inside `∘`. A single
product of two exactly-unit quaternions perturbs `‖q‖²` by `O(few·ε) ≈
1e-15 ≪ 2^-40`, so the common path never rescales (one compare, no sqrt);
drift reaches `2^-40 ≈ 9.09e-13` only after thousands of composes, and the
residual denoted-matrix error there is `≈ 2^-41 ≪ U2_ATOL`. The sweet spot:
never on the hot path, always below test tolerance
(`docs/physics/wharton_koch_quaternion_bloch.md`, "Numerics").
"""
const RENORM_TOL = 2.0^-40

"""
    U2_NORM_GROSS

Gross unit-norm bound the *checked public* `U2` constructor asserts. It sits
far above legitimate drift (`< 2^-40`) yet catches the real bug class — a
caller passing an un-normalized axis (e.g. `(0,1,1,0)`, norm 2) where a unit
quaternion was required. The constructor CHECKS, never silently fixes
(CLAUDE.md #1 FAIL LOUD); repair is the distinct, deliberate `renorm_if_needed`
step. See `docs/physics/wharton_koch_quaternion_bloch.md`.
"""
const U2_NORM_GROSS = 2.0^-20

"""
    CHART_EPS

Threshold (on the `hypot`-scale magnitudes `|sin(β/2)|` / `|cos(β/2)|`) for the
ZYZ Euler-chart singularity at β≈0 / β≈π, handled ONLY at the Orkan boundary
(PRD-v2 §4.1/§4.3, D7). The gimbal degeneracy — only `α+γ` (β≈0) or `α−γ`
(β≈π) is determined — is a topological fact about `SO(3)`/`SU(2)`, not a
convention (`docs/physics/stuelpnagel_1964_rotation_parametrization.md`). At
`1e-8`, snapping to the pole discards a rotation of magnitude `< CHART_EPS`, so
the reconstructed matrix error is `O(CHART_EPS) ≪` any physically meaningful
gate difference; random quaternions essentially never land this close to a
pole, so the general (exact) branch handles the fuzz suite at tight tolerance.
Also the degeneracy floor for the U(2) square root (`sqrt_u2`, ad.jl): only
`u ≈ −I` (`w≈−1`, vanishing vector part) needs the free-axis branch.
"""
const CHART_EPS = 1e-8

"""
    PERM_EQ_MAXW

Wire ceiling for semantic `Perm` equality by materialized permutation
(`denoted_permutation`). At `20` this is ≤ 2^20 ≈ 10^6 basis indices — ample
for M1 tests. Above it, `denoted_permutation` errors LOUDLY rather than
silently returning a wrong structural answer (CLAUDE.md #1). The kernel never
needs large-`Perm` equality: it composes and controls them; equality is a
test-time predicate.
"""
const PERM_EQ_MAXW = 20

"""
    TWO_PI

`2π` as a `Float64` (`6.283185307179586`), used by the cheap in-range phase
fold. Named so the fold reads as a single conditional subtract/add.
"""
const TWO_PI = 2π

"""
    INV_SQRT2

`1/√2` as its nearest `Float64` (`0.7071067811865476`). Used by the `H`/`S`
gate constants (`docs/physics/wharton_koch_quaternion_bloch.md`, gate table).
"""
const INV_SQRT2 = 0.7071067811865476

# --- Phase helpers -----------------------------------------------------

"""
    circdist(a, b) -> Float64

Distance between two angles ON THE CIRCLE: `|rem2pi(a − b, RoundNearest)|`.

WHY: the phase `φ` of a `U2` enters denotation only through `e^{iφ}`, which
is 2π-periodic, so `φ ≈ 0` and `φ ≈ 2π − ε` denote the same element yet are
far apart on the line. Comparing on the circle via `rem2pi(·, RoundNearest)`
(Payne–Hanek accurate, no catastrophic cancellation near multiples of 2π) is
the fold-boundary-safe compare the double-cover equality needs
(`docs/physics/wharton_koch_quaternion_bloch.md`, double cover). This is the
ONLY place `rem2pi` is called in the equality path — never in the hot loop.
"""
circdist(a::Real, b::Real) = abs(rem2pi(float(a) - float(b), RoundNearest))

"""
    _foldphase(s) -> Float64

Fold a summed phase `s ∈ [−4π, 4π]` back into `[−2π, 2π]` with ONE cheap
conditional subtract/add of `2π` — no `rem2pi` (that is Payne–Hanek and far
too expensive for the `∘` hot path).

WHY: the kernel maintains the representation invariant `|φ| ≤ 2π` on every
stored `U2` (see `u2.jl`). Because both operands of `∘` already satisfy it,
their phase sum lies in `[−4π, 4π]`, and a single conditional restores the
invariant. Denotation is unaffected: `e^{iφ}` is 2π-periodic.
"""
@inline function _foldphase(s::Float64)
    return s > TWO_PI ? s - TWO_PI : (s < -TWO_PI ? s + TWO_PI : s)
end

"""
    _signfix(w, x, y, z, φ) -> NTuple{5,Float64}

Map a `(quaternion, phase)` 5-tuple to the canonical ℤ₂ representative in
which the LARGEST-magnitude quaternion component is non-negative, applying
the double-cover transform `(q, φ) ~ (−q, φ+π)` when it is negative.

WHY largest-magnitude pivot (Proposal A, R1): a unit quaternion always has a
component with `|·| ≥ 1/2`, so the pivot is never near a sign crossing — this
makes `signfix(q) = signfix(−q)` provably exact (both reps pick the same
pivot index by magnitude and the same lowest-index tie-break, and land on the
same signed quaternion), eliminating the "first non-zero + threshold" tuning
a naive pivot invites. Grounds: the ℤ₂ is exactly `γ(u)=γ(v) ⇔ u=−v`
(`docs/physics/stuelpnagel_1964_rotation_parametrization.md`, Thm 1) and
`U(−q) = −U(q)` (`docs/physics/wharton_koch_quaternion_bloch.md`).

Tie-break: strict `>` keeps the earliest (lowest-index) component on ties,
so the choice is deterministic and stable across float drift.
"""
@inline function _signfix(w::Float64, x::Float64, y::Float64, z::Float64, φ::Float64)
    m = abs(w); c = w
    aw = abs(x); if aw > m; m = aw; c = x; end
    aw = abs(y); if aw > m; m = aw; c = y; end
    aw = abs(z); if aw > m; m = aw; c = z; end
    if c < 0
        return (-w, -x, -y, -z, φ + π)
    else
        return (w, x, y, z, φ)
    end
end

# --- Dependency-free matrix helper (OFF hot path, cross-checks only) ----

"""
    _eye(n) -> Matrix{ComplexF64}

The `n×n` complex identity, built by comprehension so that core Sturm takes
NO `LinearAlgebra` dependency (`Matrix{ComplexF64}(I, n, n)` would need it;
CLAUDE.md Julia-convention #4 — core depends only on Orkan). Used only by
`denoted_matrix(::Ctrl)`, itself a test/Ad cross-check, never the 1q hot path.
"""
function _eye(n::Int)
    return ComplexF64[i == j ? one(ComplexF64) : zero(ComplexF64) for i in 1:n, j in 1:n]
end
