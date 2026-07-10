# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M1: the `U2` process value
# (element of U(2) as unit quaternion + U(1) phase) and the `ProcessValue`
# supertype on which the kernel algebra is declared. Also seeds the two
# structural combinator node types `Tensor`/`Seq` (their rich methods live
# in `algebra.jl`; the struct definitions live here so that `ctrl.jl` — the
# single choke point, included before `algebra.jl` per the fixed include
# order — can define `ctrl(::Tensor)`/`ctrl(::Seq)` and `∘(::Ctrl,::Ctrl)`'s
# `Seq` fallback without a forward reference).
#
# Physics grounding (the PINNED convention, adopt verbatim):
#   docs/physics/wharton_koch_quaternion_bloch.md
#     U(q) = w·I − i(x σx + y σy + z σz) = [[w−iz, −y−ix],[y−ix, w+iz]]
#     U(2) element = e^{iφ} U(q); composition = Hamilton product, phases add;
#     adjoint = quaternion conjugate + phase negate; double cover
#     (q,φ) ~ (−q, φ+π); exact H² = (−1_quat, π) ≡ +I.
#   docs/physics/stuelpnagel_1964_rotation_parametrization.md — Thm 1: the
#     equality quotient is exactly ℤ₂ (γ(u)=γ(v) ⇔ u=−v).

"""
    ProcessValue

Abstract supertype of every kernel process value (PRD-v2 §4.1): `U2`, `Perm`,
`Ctrl`, and the structural combinators `Tensor`/`Seq` (M8's `UnitaryDAG` will
join here). A process value is a definite representative of a symmetry-group
element — DATA, not denotation.

The algebra (`∘`, `⊗`, `adjoint`, `ctrl`, `denoted_matrix`, `≈`) is declared
against `ProcessValue` where it is generic, with concrete methods specializing
the fast cases. This is what keeps M8 out of a corner: when
`UnitaryDAG <: ProcessValue` lands, it inherits the generic laws for free.
"""
abstract type ProcessValue end

"""
    nwires(v::ProcessValue) -> Int

Wire count of a process value (P7 dimension-agnostic naming; the Hilbert
dimension is `2^nwires` for the qubit types of M1). Concrete methods live with
each type. The abstract fallback fails loud (CLAUDE.md #1).
"""
nwires(v::ProcessValue) = error("nwires undefined for $(typeof(v))")

"""
    U2(w, x, y, z, φ)

An element of U(2) as a unit quaternion `q = (w, x, y, z)` plus a U(1) phase
`φ`, denoting the matrix `e^{iφ} U(q)` with
`U(q) = w·I − i(x σx + y σy + z σz)`
(PINNED convention, `docs/physics/wharton_koch_quaternion_bloch.md`).

WHY quaternion+phase and not a 2×2: composition is the 16-multiply Hamilton
product (exact, matrix-free, `docs/physics/stuelpnagel_1964_rotation_parametrization.md`
§5 "far superior"), and X, Z, H are EXACT elements — the v0.1 "H!² = −I is a
feature" SU(2)-section doctrine dissolves.

This CHECKED public constructor asserts finiteness and gross unit norm
(`U2_NORM_GROSS`) and FAILS LOUD on violation — it never silently renormalizes
(that is the distinct, deliberate `renorm_if_needed`). It DOES fold `φ` into
`(−π, π]` via `rem2pi` to establish the representation invariant `|φ| ≤ 2π`;
that fold is denotation-preserving (`e^{iφ}` is 2π-periodic) and is a
representation normalization, not a bug fix.

REPRESENTATION INVARIANT (maintained system-wide): every stored `U2` has
`|φ| ≤ 2π`. The public constructor establishes `|φ| ≤ π`; `∘` folds the phase
sum cheaply (`_foldphase`); `adjoint` negates (range-preserving); `_ctrl`,
`renorm_if_needed` leave `φ` untouched. This is what lets the hot path avoid
`rem2pi`.

The unchecked internal constructor `_u2(w,x,y,z,φ)` (all `Float64`) is the hot
path used by `∘`/`adjoint`/`renorm_if_needed`; it trusts the caller to have
maintained the norm and `|φ| ≤ 2π` invariants.
"""
struct U2 <: ProcessValue
    w::Float64
    x::Float64
    y::Float64
    z::Float64
    φ::Float64
    # Unchecked internal constructor — the Hamilton hot path.
    global _u2(w::Float64, x::Float64, y::Float64, z::Float64, φ::Float64) =
        new(w, x, y, z, φ)
    # Checked public constructor — FAIL LOUD on garbage, fold φ into range.
    function U2(w::Real, x::Real, y::Real, z::Real, φ::Real)
        w64 = Float64(w); x64 = Float64(x); y64 = Float64(y)
        z64 = Float64(z); φ64 = Float64(φ)
        @assert isfinite(w64) & isfinite(x64) & isfinite(y64) & isfinite(z64) & isfinite(φ64) "U2: non-finite component (w=$w64, x=$x64, y=$y64, z=$z64, φ=$φ64)"
        n2 = w64 * w64 + x64 * x64 + y64 * y64 + z64 * z64
        @assert abs(n2 - 1) < U2_NORM_GROSS "U2: quaternion norm²=$n2 far from unit (|Δ| ≥ $(U2_NORM_GROSS)); build via Ry/Rz/Rx or the gate constants, or normalize the axis first"
        return new(w64, x64, y64, z64, rem2pi(φ64, RoundNearest))
    end
end

nwires(::U2) = 1

"""
    ∘(a::U2, b::U2) -> U2

Composition (right-to-left: `a ∘ b` applies `b` first). By the group
isomorphism `U(pq) = U(p)U(q)`, this is the Hamilton product of the
quaternions with phases ADDED — transcribed verbatim from
`docs/physics/wharton_koch_quaternion_bloch.md` (16 real multiplies, 12 adds).

The 16 signs are NOT hand-verified here: the convention-anchor fuzz test
(`test_kernel_u2.jl`, T0) certifies `denoted(a∘b) ≈ denoted(a)*denoted(b)` on
random pairs — one failing test localizes any convention slip. Phase sum is
folded cheaply (`_foldphase`); the result is renormalized only if drift
exceeds `RENORM_TOL`.
"""
@inline function Base.:∘(a::U2, b::U2)
    aw = a.w; ax = a.x; ay = a.y; az = a.z
    bw = b.w; bx = b.x; by = b.y; bz = b.z
    rw = aw * bw - ax * bx - ay * by - az * bz
    rx = aw * bx + ax * bw + ay * bz - az * by
    ry = aw * by - ax * bz + ay * bw + az * bx
    rz = aw * bz + ax * by - ay * bx + az * bw
    φ = _foldphase(a.φ + b.φ)
    return renorm_if_needed(_u2(rw, rx, ry, rz, φ))
end

"""
    adjoint(a::U2) -> U2

The inverse `(e^{iφ} U(q))† = e^{−iφ} U(q̄)`, with `q̄ = (w, −x, −y, −z)` and
`U(q̄) = U(q)†` (`docs/physics/wharton_koch_quaternion_bloch.md`, "Adjoint").
Sign flips only — norm-preserving, and `|−φ| ≤ 2π` when `|φ| ≤ 2π`, so no
renorm and no fold are needed.
"""
@inline Base.adjoint(a::U2) = _u2(a.w, -a.x, -a.y, -a.z, -a.φ)

"""
    renorm_if_needed(u::U2) -> U2

Repair unit-norm drift by ONE scalar rescale of the quaternion (φ untouched),
but only when `|‖q‖² − 1| > RENORM_TOL` — the common path returns `u`
unchanged after a single compare (no sqrt). A scalar rescale is cheaper and
better-conditioned than re-orthogonalizing a drifting 2×2
(`docs/physics/wharton_koch_quaternion_bloch.md`, "Numerics").
"""
@inline function renorm_if_needed(u::U2)
    n2 = u.w * u.w + u.x * u.x + u.y * u.y + u.z * u.z
    if abs(n2 - 1) > RENORM_TOL
        s = inv(sqrt(n2))
        return _u2(u.w * s, u.x * s, u.y * s, u.z * s, u.φ)
    end
    return u
end

"""
    denoted_matrix(u::U2) -> Matrix{ComplexF64}

The 2×2 U(2) matrix `e^{iφ} U(q)` this value denotes (PINNED convention). This
IS the semantics; the Hamilton product in `∘` is the optimization whose
obligation is to agree with it. Off the 1q hot path (test/Ad cross-checks
only); returns a plain `Matrix{ComplexF64}` to keep core dependency-free.
"""
function denoted_matrix(u::U2)
    e = cis(u.φ)
    return ComplexF64[
        e*complex(u.w, -u.z)  e*complex(-u.y, -u.x)
        e*complex(u.y, -u.x)  e*complex(u.w, u.z)
    ]
end

"""
    isapprox(a::U2, b::U2; atol=U2_ATOL, rtol=0) -> Bool

The NORMATIVE U(2)-quotient equality `≈` (used by every M1 law test). Both
operands are sign-fixed into the same ℤ₂ representative (`_signfix`, largest-
magnitude pivot), then quaternion components are compared with `atol` and the
phase with `circdist` (fold-boundary safe).

Two guardrails follow structurally (`docs/physics/wharton_koch_quaternion_bloch.md`):
`H∘H ≈ I` (both denote `I`; H² lands on the OTHER representative of `+I`), and
`+I ≠ −I` (`circdist(0, π) = π > atol` — the π that `ctrl` promotes to an
observable Z; `docs/physics/tang_wright_2025_controlled_unitaries.md` Thm 1.1).
`Base.==` is deliberately left as exact structural equality (honest, hashable,
transitive) — it is NOT this quotient, and no `Base.hash` is overloaded.

A fast quaternion-level pass is SOUND but not complete: when the two largest
quaternion components are nearly TIED with opposite signs, `_signfix` can pick
different pivots for two float representations of the same element and send
them to different ℤ₂ representatives (a false negative the random fuzz never
hits). Completeness is restored by falling back to the reference semantics —
the denoted matrices — whenever the fast path says "no". The common case never
allocates; the fallback only runs on (rare) rejections, where correctness, not
speed, is at stake.
"""
function Base.isapprox(a::U2, b::U2; atol::Real=U2_ATOL, rtol::Real=0)
    wa, xa, ya, za, φa = _signfix(a.w, a.x, a.y, a.z, a.φ)
    wb, xb, yb, zb, φb = _signfix(b.w, b.x, b.y, b.z, b.φ)
    if abs(wa - wb) <= atol && abs(xa - xb) <= atol &&
       abs(ya - yb) <= atol && abs(za - zb) <= atol &&
       circdist(φa, φb) <= atol
        return true
    end
    # Near-tie pivot hazard: decide by denotation (the reference semantics).
    return isapprox(denoted_matrix(a), denoted_matrix(b); atol=atol, rtol=rtol)
end

# --- Structural combinator node types (methods in algebra.jl) ----------

"""
    Tensor{A,B}(a, b)

The `⊗` (parallel) combinator node: `a` on the most-significant (leftmost)
wire block, `b` on the trailing block; denotes `kron(matrix(a), matrix(b))`.
A thin, wire-positional, lazy node — the two-leaf degenerate case of M8's
`UnitaryDAG`. Binary form (M8 may flatten later). Built by `⊗` (algebra.jl).
"""
struct Tensor{A<:ProcessValue,B<:ProcessValue} <: ProcessValue
    a::A
    b::B
end
nwires(t::Tensor) = nwires(t.a) + nwires(t.b)

"""
    Seq{A,B}(a, b)

The `∘` (series) fallback node for operands that do not fuse to an exact group
element: `a ∘ b`, apply `b` first, same wires; denotes `matrix(a)*matrix(b)`.
The two-leaf seed of M8's DAG. Built by the generic `∘` fallback (algebra.jl)
and by `∘(::Ctrl,::Ctrl)` on differing control counts.
"""
struct Seq{A<:ProcessValue,B<:ProcessValue} <: ProcessValue
    a::A
    b::B
end
nwires(s::Seq) = nwires(s.a)
