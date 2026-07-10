# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M4 (bead Sturm.jl-3nld): the VIEW
# mechanism — `dual` (the conjugate/character-group view, surface construct 4)
# and the general parametric `view` (kernel/library-only). Both follow Base's
# `adjtrans.jl` pattern EXACTLY: two DISTINCT nominal wrapper types, each a lazy
# reinterpretation of a borrowed register handle, never an operation on the data
# (PRD-v2 §3.3, the `transpose`/`adjoint` idiom).
#
# The one normative discipline this file exists to enforce: `dual` UNWRAPS by
# dispatch on the wrapper's nominal type (`dual(v::DualView) = v.parent`), it
# NEVER lowers by *applying* the Fourier transform F. As a *process* the Fourier
# value satisfies F² = parity (x ↦ −x); an implementation that lowered `dual` by
# applying F would negate every integer under a double dual (`dual(dual(x))`) —
# the exact bug §3.3 names, and the same category of mistake Julia repaired at
# cost in JuliaLang/julia#20978 (pre-0.7 `ctranspose = conj∘transpose` by fiat).
# Structurally `dual(dual(q)) === q` (Pontryagin's canonical double-dual
# identification ev : G → Ĝ̂, no antipode) is a *dispatch-time* unwrap, matching
# `transpose(transpose(A)) === A`. "Views unwrap; processes compose" (§3.3):
# generic stacked `view`s compose their transforms; `dual` specifically unwraps.
#
# The dual's basis change F_G is a REGISTER-TYPE TRAIT, never stored as data:
# `_dual_transform(::QBool) = H` (ℤ₂ is self-dual, F = H = F†). This is P7 by the
# surface — one theorem (Pontryagin duality) covers every abelian register — and
# it is exactly what buys the *passive* view: `dual` is the unique view
# constructor that takes no process-value argument (its P5 surface privilege,
# §3.3), because the register type already fixes F_G. Library authors reach for
# the general `view(V, q)` with an explicit `V` (QSVT's SELECT conjugates by a
# Y-axis value this way); users never see a `V`.
#
# WHY THIS IS INCLUDED AT M4 POSITION (after surface/casts.jl), despite living
# under src/kernel/: `_dual_transform(::QBool)` and `dual(::QBool)` need `QBool`
# (M3, types/qbool.jl) and the kernel `H`/`∘`/`adjoint`/`ProcessValue` (M1). The
# directory is a LAYERING marker (view machinery is `public`, not surface); the
# include position is dependency order. No kernel/context/FFI logic is touched —
# a view is NEVER an `apply!` argument (that invariant is what buys "zero M1/M2/M3
# edits"): each surface view-op computes a concrete ProcessValue + parent WireIDs
# and calls the EXISTING `apply!` (see src/surface/actions.jl).
#
# Prior art (docstring citations): docs/physics/adams_qwerty_basis_oriented.md
# and docs/physics/adams_asdf_basis_translation_synthesis.md — the
# view-vs-synthesis differentiator (Qwerty's `>>` is a *synthesized circuit*;
# `dual`'s narrowing to the one canonical character-group dual is what makes a
# pure reinterpretation possible). docs/physics/wharton_koch_quaternion_bloch.md
# — HXH = Z, the self-dual H.

"""
    AbstractView

Marker supertype of every lazy register view (`DualView`, `View`). Views BORROW a
parent handle (they never `allocate!`, so their death traces nothing — §3.9), and
every one carries a `parent` field. The aliasing/consumed-set resolver
(`_parent_wire`) and M5's `when`-guardrail dispatch on this supertype. Not a
number: views do NOT ride P9 (no ring ops), so generic numeric code handed one
`MethodError`s honestly — the same wall as `g(x::Int)` (§3.3).
"""
abstract type AbstractView end

"""
    DualView{H}(parent)   [construct via `dual`]

The conjugate-basis view — surface construct 4 (`dual`). A distinct nominal type
storing ONLY the borrowed `parent` handle (Base's `Transpose`/`Adjoint` pattern,
`adjtrans.jl`): its basis change F_G is supplied by the parent register's TYPE
(`_dual_transform`), never stored as a field. Parametric on the parent handle
type `H`.

MUTABLE deliberately, for identity semantics (NOT for mutation — the field is
never reassigned). §3.3 is normative that `dual(q) === dual(q)` is `false` (each
call is a fresh wrapper; consumed-set/aliasing bookkeeping must therefore key on
the parent wire via `_parent_wire`, never on wrapper identity). `===` on an
IMMUTABLE struct is structural (two `DualView(q)` would compare EQUAL), so only a
`mutable struct` — whose `===` is object identity — yields the required
`dual(q) !== dual(q)` while keeping `dual(dual(q)) === q` (the unwrap returns the
very same parent object). Not `isbits` regardless (its parent `QBool` holds an
abstract `ctx`) — fine, views are never in the hot loop; they PRODUCE `apply!`
calls, they are not `apply!` arguments.
"""
mutable struct DualView{H} <: AbstractView
    parent::H
end

"""
    View{V,H}(transform, parent)   [construct via `view`]

The general parametric view: a lazy wrapper carrying an explicit process value
`transform` and a borrowed `parent`. Library-only (kernel `public`) — the surface
never mentions a process value (P5). Unlike `DualView`, stacked `view`s COMPOSE
their transforms (`view(W, view(V, q)) = view(W ∘ V, q)`); there is no unwrap.
QSVT's SELECT conjugates by a Y-axis value this way (§3.3/§5).
"""
struct View{V<:ProcessValue,H} <: AbstractView
    transform::V
    parent::H
end

"""
    _dual_transform(reg) -> ProcessValue

The character-group basis change F_G for a register type (P7 trait). For `QBool`
(G = ℤ₂, self-dual) it is the exact kernel `H` (F = H = F†;
docs/physics/wharton_koch_quaternion_bloch.md). M6 adds
`_dual_transform(::QInt{W}) = QFT_W` (F ≠ F†; the direction pinned by the
Pontryagin unit test, §3.3). INTERNAL — never a surface name.
"""
_dual_transform(::AbstractQubit) = H

"""
    dual(q::QBool) -> DualView
    dual(v::DualView) -> parent            # UNWRAP (involution)

The conjugate-basis view (§3.3). `dual(q)` is a fresh, zero-cost, lazy wrapper —
a different way of ADDRESSING the register, not an operation on it. Operations on
the view lower by kernel conjugation through F_G (`Bool(dual(q))` is
conjugate-basis measurement; `not!(dual(q))` is the phase flip Z; `q̂ ⊻= r` is
CZ — src/surface/actions.jl).

Involution is by DISPATCH, never by applying F: `dual(dual(q)) === q` structurally
(the `adjtrans.jl` unwrap `dual(v::DualView) = v.parent`), matching
`transpose(transpose(A)) === A`. Lowering `dual` by *applying* F would negate
integers under a double dual (F² = parity) — the normative bug of §3.3 /
JuliaLang#20978. Each `dual(q)` call builds a FRESH wrapper, so
`dual(q) === dual(q)` is `false`; consumed-set/aliasing bookkeeping keys on the
parent wire (`_parent_wire`), never on wrapper identity.

# Spelling traps (D11 — `dual`'s docstring must name both)

- `dual(q) ⊻= r` and `dual(x) += a` are **not writable Julia**: op-assignment
  demands an assignable location, so these lower to `Expr(:error, "invalid
  assignment location \"dual(q)\"")` (a fifteen-year invariant, julialang
  #227/#249/#3217) — caught by the M0 PRD lower-lint, never reaching runtime.
  Bind the view first: `q̂ = dual(q); q̂ ⊻= r`. A bound view op-assign mutates the
  viewed register in place and rebinds `q̂` to the same view (§3.4 registration).
- `dual(x) = y` inside a function body **silently defines a local method**
  shadowing `dual` for the whole body — a Julia footgun (the cousin of
  JuliaLang#20978: defining an operation as the *evaluation* of a composition
  rather than structurally is the same category of error as applying F above).

# Prior art

The nearest neighbour is Qwerty (Adams et al., arXiv:2404.12603): first-class
basis values and Fourier-basis measurement. But its basis translation `>>` is a
*synthesized circuit* (its compiler paper, ASDF arXiv:2501.13262, names
"synthesizing circuits from basis translations" as the core problem), never a
passive view — structurally it cannot be, because `>>` maps between *arbitrary*
user-named bases. Only `dual`'s narrowing to the one canonical character-group
dual makes a pure reinterpretation possible (the canonicity-buys-the-view point;
docs/physics/adams_qwerty_basis_oriented.md,
docs/physics/adams_asdf_basis_translation_synthesis.md). Cite Qwerty §IV's own
representation-vs-value disclaimer, never "they rejected the view". Qwerty's `∼e`
(function adjoint) is `Sturm.adjoint` on a process value, NOT `dual`.
"""
dual(q::AbstractQubit) = DualView(q)
dual(v::DualView) = v.parent

"""
    view(V::ProcessValue, q) -> View
    view(V::ProcessValue, w::View) -> View     # COMPOSE

The general parametric view (kernel `public`, library-only). Stacking composes the
transforms — "processes compose" (§3.3): `view(W, view(V, q))` is
`view(W ∘ V, q)`, NOT an unwrap. A fresh Sturm generic (NOT a `Base.view` method,
so `using Sturm` never shadows array views — B's D-B3, ratified). Surface code
never calls this; `dual` is the surface's unique no-process-value view.
"""
view(V::ProcessValue, q) = View(V, q)
view(V::ProcessValue, w::View) = View(V ∘ w.transform, w.parent)

"""
    _parent_wire(handle) -> WireID

Resolve any handle or view to the borrowed parent `WireID` (a Sturm-owned hook,
SHAPED like Base's documented-but-not-public `dataids`/`mightalias` protocol — we
do NOT call Base internals). This is what makes aliasing SEE THROUGH views:
because every surface view-op resolves to parent `WireID`s before calling
`apply!`, the landed `_check_wire_aliasing` (ad.jl) fires on `q̂ ⊻= q` today. M5's
per-op `when`-guardrail consumes exactly this resolver
(`_parent_wire(control) == _parent_wire(target)`). INTERNAL.
"""
_parent_wire(q::AbstractQubit) = q.wire
_parent_wire(v::AbstractView) = _parent_wire(v.parent)

# A returned view escapes carrying its borrowed parent's wires (regions.jl).
_escaped_wires(v::AbstractView) = _escaped_wires(v.parent)

"""
    _conj(V::ProcessValue, g::ProcessValue) -> ProcessValue

The conjugation that lowers a unitary `g` through a view with basis change `V`:
`Ad_{V†} ∘ op ∘ Ad_V` (§3.3), i.e. the effective process value `V† · g · V`,
computed with M1's fuzz-certified Hamilton `∘` — matrix-free and EXACT, emitting
ONE fused value (not a literal H·g·H sandwich). Direction pinned `adjoint(V) ∘ g
∘ V` (applies V first, then g, then V†; matrix `V†·g·V`). For `QBool` V = H is
self-adjoint, so the direction is UNOBSERVABLE here (`H∘X∘H = H∘Z∘H` either way);
it is genuinely disambiguated only at M6 by the Pontryagin unit test, for F ≠ F†.
`_conj(H, X) ≈ Z` and `_conj(H, Z) ≈ X` — the ℤ₂ translation↔modulation swap
(docs/physics/wharton_koch_quaternion_bloch.md, HXH = Z). INTERNAL.
"""
_conj(V::ProcessValue, g::ProcessValue) = adjoint(V) ∘ g ∘ V
