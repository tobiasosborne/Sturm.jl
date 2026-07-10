# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M3 (bead Sturm.jl-77m2): `QBool`,
# the first typed register handle, and the preparation cast (cq, PRD-v2 §3.2).
# A QBool is `(ctx, wire)` — "a register IS a handle into a context that owns
# the state" (§4.3). Storing the OWNING context (not just a bare `WireID`) is
# load-bearing: `WireID`s are minted per-context (abstract.jl `allocate!`), so
# `WireID(1)` exists in EVERY context; a bare-id handle from context A, used
# while context B is bound, would pass B's liveness check and silently target a
# DIFFERENT physical qubit. The stored `ctx` lets every surface op assert
# `q.ctx === current_context()` and fail loud on a cross-context handle. This is
# the leaf-handle pattern M4 views (borrow a parent handle) and M6 `QInt{W}`
# (`(ctx, NTuple{W,WireID})`) inherit.
#
# TYPE-STABILITY (the QBool{C} call, recorded once): `ctx::AbstractContext` is
# an ABSTRACT field, so QBool is not a concrete-leaf type and handle ops take a
# dynamic dispatch on `ctx`. This is DELIBERATE and acceptable — handles are not
# in the hot loop (the hot loop is `apply!` over raw wires + the per-wire fusion
# buffer, M2). We do NOT parameterize `QBool{C<:AbstractContext}`: the PRD's
# surface names are `QBool` and `QInt{W}` (W the ONLY type parameter, §3.1), and
# a context parameter would metastasize into `QInt{W,C}` and infect every
# signature. The `@code_warntype` gate stays on the wire-level `apply!`/emit
# path, never on handle construction.
#
# Physics/spec grounding: PRD-v2 §3.1–3.2 (casts, boundary algebra), §3.9
# (allocation-is-initialization, regions), §4.3 (register = handle; Ad drops
# global phase), D1 (§9: the (p,φ) literal, DomainError, never widen to Complex).
# Preparation value derivation: docs/physics/wharton_koch_quaternion_bloch.md
# (the PINNED U(2) convention; Ry/Rz gate table, Eq 8).

"""
    AbstractQubit

Supertype of every SINGLE-WIRE quantum handle: `QBool` (an owned register) and
`WireRef` (a BORROWED slice `x[i]` of a `QInt`, M6 types/qint.jl). Both carry a
`.ctx` and a `.wire`, so the single-wire surface family — the action family
(`not!`, `⊻=`), the `dual` view, `when`, and the `Bool`/`convert` measurement
casts — dispatches on `AbstractQubit` and is written ONCE (the `AbstractArray`
reuse move; CLAUDE.md #13). The OWN-vs-BORROW distinction is NOT in these shared
ops — it lives in construction (a `WireRef` never `allocate!`s) and in
consumption (measuring a `WireRef` consumes the shared wire on the single-sourced
set, a partial consumption of its parent register — PRD-v2 §4.5/§8.5).
"""
abstract type AbstractQubit end

"""
    QBool(p::Real, φ::Real = 0.0) -> QBool
    QBool(b::Bool)                -> QBool

A single-qubit register handle: the quantum analogue of `Bool`. Its two forms
are the PREPARATION cast (cq, §3.2):

- `QBool(p, φ)` allocates a fresh wire in |0⟩ and prepares
  `√(1−p)|0⟩ + √p·e^{iφ}|1⟩` — Born probability `p` of measuring `true`,
  relative phase `φ`. `p ∉ [0,1]` throws `DomainError` (the (p,φ) chart never
  widens to Complex — D1). `φ` is unrestricted.
- `QBool(b::Bool)` is the definite-bit cast: |0⟩ for `false`, |1⟩ for `true`.

A `QBool` stores its owning `ctx` and `wire::WireID`; it is a LIVE handle —
consumed by `Bool(q)` (the qc cast, surface/casts.jl) and traced at region exit
if neither consumed nor returned (§3.9). Two `QBool`s are never structurally
equal (distinct wires); the boundary laws are state/channel-level, not `==` on
handles (see D1 pole degeneracy, tested at the state level).
"""
struct QBool <: AbstractQubit
    ctx::AbstractContext   # the OWNING context (§4.3: a register is a handle into a context)
    wire::WireID           # the M2 identity core (types/wire.jl)
end

"""
    _prep_u2(p::Float64, φ::Float64) -> U2

The preparation process value `Rz(φ) ∘ Ry(2·asin(√p))`, denoting a U(2) element
that sends |0⟩ ↦ √(1−p)·e^{−iφ/2}|0⟩ + √p·e^{+iφ/2}|1⟩ (Born weight `p` on |1⟩,
relative phase `e^{iφ}`; the residual `e^{−iφ/2}` is an unobservable GLOBAL phase
of a prepared state, dropped by Ad — §4.3). Built with M1's fuzz-certified
Hamilton `∘` — never a hand-transcribed quaternion (the convention-slip surface
that `∘`'s T0 test exists to kill). `p`/`φ` are `Float64` already: the surface
constructor crosses any `Irrational` (π) to `Float64` BEFORE this call, so no `π`
leaks to Orkan (D1). `asin`/`sqrt` stay REAL — the `[0,1]` guard runs first, so
they are never handed an out-of-domain argument.

With `θ = 2·asin(√p)`: `cos(θ/2)=√(1−p)`, `sin(θ/2)=√p`. Verified against A's
analytic first column in the M3 tests (`denoted_matrix(_prep_u2(p,φ))[:,1]`).
docs/physics/wharton_koch_quaternion_bloch.md (Ry/Rz, Eq 8).
"""
_prep_u2(p::Float64, φ::Float64) = Rz(φ) ∘ Ry(2 * asin(sqrt(p)))

function QBool(p::Real, φ::Real = 0.0)
    # Chart guard BEFORE any sqrt/asin: names p in the message (fail-loud), and
    # NaN ≤ 1 is false so NaN throws here too. Never widened to Complex (D1).
    (0.0 ≤ p ≤ 1.0) || throw(DomainError(p,
        "QBool(p, φ): p must be a probability in [0,1] (got $p). The (p,φ) " *
        "literal never widens to Complex (D1); it is the d=2 amplitude chart."))
    ctx = current_context()
    w = allocate!(ctx)                                # |0⟩, region-owned (§3.9)
    apply!(ctx, _prep_u2(Float64(p), Float64(φ)), (w,))  # Float64 before the emit (D1)
    return QBool(ctx, w)
end

function QBool(b::Bool)
    # Definite bit: |0⟩ needs no gate; |1⟩ is one EXACT kernel X (constants.jl),
    # NOT Ry(π) — pre-empts the v0.1 latent-phase bug §3.4 names. `Bool <: Real`,
    # so `QBool(true)` dispatches HERE (more specific), not the (p,φ) method.
    ctx = current_context()
    w = allocate!(ctx)
    b && apply!(ctx, X, (w,))
    return QBool(ctx, w)
end

"""
    plus()    -> QBool   #  |+⟩ = (|0⟩ + |1⟩)/√2          = QBool(0.5)
    minus()   -> QBool   #  |−⟩ = (|0⟩ − |1⟩)/√2          = QBool(0.5, π)
    magic_T() -> QBool   #  |A⟩ = (|0⟩ + e^{iπ/4}|1⟩)/√2  = QBool(0.5, π/4)

Named library constants — thin sugar on the `QBool(p, φ)` constructor (D1,
Base's `im = Complex(false, true)` pattern). `magic_T` is the §3.7-entailed
phase-bearing literal (real stabilizer ops cannot manufacture `e^{iπ/4}`) — the
`T`-injection resource (`inject_T!`, PRD-v2 §7.6), which is why the `φ` argument
exists at all. `π`/`π/4` are `Irrational`; the constructor's `Float64(φ)` makes
these calls Irrational-safe.
"""
plus()    = QBool(0.5)
minus()   = QBool(0.5, π)
magic_T() = QBool(0.5, π / 4)

"""
    _adopt_qbool(ctx, w::WireID) -> QBool

INTERNAL seam: wrap an ALREADY-live wire as a `QBool` handle WITHOUT preparing
anything (the 2-arg field constructor, named for intent). Used by the Choi
harness (test/choi.jl) to hand a Bell-prepared system half to a channel `f`, and
by M4 views / M6 slices later. NOT the surface literal — a stray `WireID` can
never be mistaken for a preparation.
"""
_adopt_qbool(ctx::AbstractContext, w::WireID) = QBool(ctx, w)

# A returned single-wire handle escapes its region carrying its one wire
# (regions.jl `_escaped_wires`; the strict-mode survivor set + region re-homing).
_escaped_wires(q::AbstractQubit) = [q.wire]
