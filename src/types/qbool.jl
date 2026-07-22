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
# TYPE-STABILITY (F16, bead vanm): `QBool{C}` carries the CONCRETE owning-context
# type `C` as a trailing parameter, and its `ctx::C` field is therefore concrete.
# Handle ops (`not!`, `⊻=`, `Bool`, `dual`) load `q.ctx` as `C` and dispatch
# `_act!`/`apply!`/casts statically — closing the M4/M6 defect where an abstract
# `ctx::AbstractContext` forced a dynamic dispatch on every action (Ruling D also
# demands it: the cast return type varies by context, so dispatch must reach the
# concrete context type). The context INSTANCE stays a field: `C` selects code,
# object identity (`ctx === current_context()`) establishes ownership — two
# `EagerContext`s share `C` yet must not mix (register.jl header). Public
# construction crosses ONE dynamic function barrier over `current_context()`;
# the typed worker `QBool(ctx::C, ...)` is the hot-loop / internal-seam entry.
#
# Physics/spec grounding: PRD-v2 §3.1–3.2 (casts, boundary algebra), §3.9
# (allocation-is-initialization, regions), §4.3 (register = handle; Ad drops
# global phase), D1 (§9: the (p,φ) literal, DomainError, never widen to Complex).
# Preparation value derivation: docs/physics/wharton_koch_quaternion_bloch.md
# (the PINNED U(2) convention; Ry/Rz gate table, Eq 8).

# `AbstractQubit{C}` (the single-wire supertype) now lives in types/register.jl,
# parameterized by the owning-context type `C` — shared by `QBool{C}` and the M6
# borrow `WireRef{C}`. See there for the OWN-vs-BORROW discipline.

"""
    QBool(p::Real, φ::Real = 0.0) -> QBool
    QBool(b::Bool)                -> QBool
    QBool(ctx::C, b::Bool)        -> QBool{C}   [typed worker; `public`]
    QBool(ctx::C, p::Real, φ = 0) -> QBool{C}   [typed worker; `public`]

A single-qubit register handle: the quantum analogue of `Bool`. Its two forms
are the PREPARATION cast (cq, §3.2):

- `QBool(p, φ)` allocates a fresh wire in |0⟩ and prepares
  `√(1−p)|0⟩ + √p·e^{iφ}|1⟩` — Born probability `p` of measuring `true`,
  relative phase `φ`. `p ∉ [0,1]` throws `DomainError` (the (p,φ) chart never
  widens to Complex — D1). `φ` is unrestricted.
- `QBool(b::Bool)` is the definite-bit cast: |0⟩ for `false`, |1⟩ for `true`.

A `QBool{C}` stores its owning `ctx::C` and `wire::WireID`; it is a LIVE handle —
consumed by `Bool(q)` (the qc cast, surface/casts.jl) and traced at region exit
if neither consumed nor returned (§3.9). Two `QBool`s have NO value equality
(F15 — register.jl throws on `==`/`hash`); the boundary laws are state/channel-
level, and `===` is the handle-identity test (D1 pole degeneracy, tested at the
state level).

The zero-context public forms read `current_context()` (a ScopedValue: its
static type is `AbstractContext`, so `QBool(false)` INFERS as `QBool`, not
`QBool{C}` — intrinsic to dynamic scope, F16 §4). Cross the function barrier or
use the typed worker `QBool(ctx::C, b)` for an inference-clean hot loop.
"""
struct QBool{C<:AbstractContext} <: AbstractQubit{C}
    ctx::C                 # the OWNING context, CONCRETE (§4.3; F16 inference)
    wire::WireID           # the M2 identity core (types/wire.jl)

    function QBool{C}(ctx::C, wire::WireID) where {C<:AbstractContext}
        _require_concrete_context(C)
        return new{C}(ctx, wire)
    end
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

# Chart guard, shared by the barrier and the typed worker: names p (fail-loud),
# and NaN ≤ 1 is false so NaN throws too. Runs BEFORE any context lookup, so an
# invalid `p` is a DomainError even with no context bound (D1; never widened to
# Complex).
@inline function _check_qbool_prob(p::Real)
    (0.0 ≤ p ≤ 1.0) || throw(DomainError(p,
        "QBool(p, φ): p must be a probability in [0,1] (got $p). The (p,φ) " *
        "literal never widens to Complex (D1); it is the d=2 amplitude chart."))
    return nothing
end

# --- Public zero-context forms: the dynamic function barrier (F16 §4) -------
# Each reads `current_context()` ONCE and hands off to the typed `QBool(ctx, …)`
# worker. `QBool(false)` therefore INFERS as `QBool` (the ScopedValue is typed
# `AbstractContext`); the worker `QBool(ctx::C, false)` infers `QBool{C}`.

function QBool(p::Real, φ::Real = 0.0)
    _check_qbool_prob(p)
    return QBool(current_context(), Float64(p), Float64(φ))
end

# Definite bit: `Bool <: Real`, so `QBool(true)` dispatches HERE (more specific),
# not the (p,φ) method.
QBool(b::Bool) = QBool(current_context(), b)

# --- Typed workers (concrete `ctx::C`): the hot-loop / internal-seam entry --
# `public`, not exported — a context object is machinery, not an eighth surface
# construct, but library hot allocation loops and internal seams (`false ⊻ r`,
# `_fresh_copy`) call these directly to avoid re-reading the ScopedValue.

"""
    QBool(ctx::C, p::Real, φ::Real = 0.0) -> QBool{C}
    QBool(ctx::C, b::Bool)                -> QBool{C}

The context-explicit preparation cast: allocate a fresh |0⟩ in `ctx` and prepare
it, returning an inference-clean `QBool{C}`. The advanced/context-layer analogue
of `apply!(ctx, …)` — NO new surface construct. Use inside a `C`-typed function
barrier for allocation-heavy loops (F16 §4). `φ` defaults to 0.
"""
function QBool(ctx::C, p::Real, φ::Real = 0.0) where {C<:AbstractContext}
    _check_qbool_prob(p)
    w = allocate!(ctx)                                   # |0⟩, region-owned (§3.9)
    apply!(ctx, _prep_u2(Float64(p), Float64(φ)), (w,))  # Float64 before the emit (D1)
    return QBool{C}(ctx, w)
end

# Definite bit: |0⟩ needs no gate; |1⟩ is one EXACT kernel X (constants.jl), NOT
# Ry(π) — pre-empts the v0.1 latent-phase bug §3.4 names.
function QBool(ctx::C, b::Bool) where {C<:AbstractContext}
    w = allocate!(ctx)
    b && apply!(ctx, X, (w,))
    return QBool{C}(ctx, w)
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
_adopt_qbool(ctx::C, w::WireID) where {C<:AbstractContext} = QBool{C}(ctx, w)

# A returned single-wire handle escapes its region carrying its one wire
# (regions.jl `_escaped_wires`; the strict-mode survivor set + region re-homing).
_escaped_wires(q::AbstractQubit) = [q.wire]
