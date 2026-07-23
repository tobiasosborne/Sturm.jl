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

# ===========================================================================
# F19 — the explicit symmetric bicharacter / duality trait (§3.3)
# ===========================================================================
#
# The dual view's basis change is only HALF the story: the physics that makes
# `q̂ ⊻= r ≡ r̂ ⊻= q` (CZ symmetry, §7.3) a theorem is the register's PAIRING
# B : G × Ĝ → U(1), and its symmetry is a PROPERTY THAT MUST BE DECLARED, never
# inferred from the Fourier matrix (evaluation G × Ĝ → U(1) is not intrinsically
# symmetric — F16 §8, alternatives rejected). So the trait carries four data as
# TYPES: the label group `G`, the character transform `F` (the process value the
# view applies), the selected bicharacter `B`, and the symmetry marker `S`. It is
# CONTEXT-FREE by design: the Hilbert space, group, transform, and pairing do not
# depend on how the register is executed. The CZ-symmetry law test consults the
# declared `symmetry(...)`; a future non-symmetric self-dual register may keep
# `dual` yet must NOT assert the alternative operand order equivalent.
#
# Physics/spec grounding: PRD-v2 §3.3 (dual, Pontryagin pairing), §7.3 (CZ
# symmetry theorem). docs/physics/wharton_koch_quaternion_bloch.md (HXH = Z, the
# self-dual H); docs/physics/chen_stoudenmire_white_qft_entanglement.md (the QFT
# view on ℤ_{2^W}).

"Label-group of a register's self-action (F19): ℤ₂, cyclic ℤ_{2^W}, or (ℤ₂)^W."
abstract type AbstractActionGroup end
struct Z2Group <: AbstractActionGroup end
struct Cyclic2PowGroup{W} <: AbstractActionGroup end   # ℤ_{2^W} (the `add!`/`dual` world)
struct BitVectorGroup{W} <: AbstractActionGroup end    # (ℤ₂)^W  (the transversal `⊻` world)

"Action-family tag (F19): which group a `QInt` op acts through (add! vs ⊻)."
abstract type ActionFamily end
struct AddFamily <: ActionFamily end
struct XorFamily <: ActionFamily end

"""
    Pow2Bicharacter{W}

The selected nondegenerate pairing on ℤ_N × ℤ_N, N = 2^W:
B_W(x,y) = ω^{xy}, ω = e^{2πi/N}. For W = 1 this is the ℤ₂ pairing (−1)^{xy}
(so `QBool` and one `QInt` wire share one trait shape). Symmetric and
nondegenerate; the exact integer exponent is exposed separately
(`pairing_exponent`) so the law tests avoid floating-point round-off.
"""
abstract type AbstractBicharacter end
struct Pow2Bicharacter{W} <: AbstractBicharacter end

"Declared symmetry of the pairing (F19): a PROPERTY, never inferred (§3.3)."
abstract type PairingSymmetry end
struct SymmetricPairing <: PairingSymmetry end
struct NonSymmetricPairing <: PairingSymmetry end

"""
    DualitySpec{G,F,B,S}(group, transform, bicharacter, symmetry)

The complete duality specification of a register type (F19): the label group,
the character-group transform `F_G` (a process value — `H` for ℤ₂, `QFT` for
ℤ_{2^W}), the selected bicharacter, and the declared symmetry. Reached by the
`duality(::Type)` trait; `transform`/`symmetry` accessors extract fields.
"""
struct DualitySpec{G<:AbstractActionGroup,F<:ProcessValue,B<:AbstractBicharacter,S<:PairingSymmetry}
    group::G
    transform::F
    bicharacter::B
    symmetry::S
end

transform(d::DualitySpec) = d.transform
symmetry(d::DualitySpec) = d.symmetry

"""
    pairing_exponent(::Pow2Bicharacter{W}, x, y) -> Integer

The EXACT integer exponent `k` with B_W(x,y) = ω^k, ω = e^{2πi/2^W}:
`k = (x·y) mod 2^W`. Computed in exact integer arithmetic (no float error) so
the bicharacter law tests (identity, bilinearity, nondegeneracy, symmetry) are
exact for small `W`. `bicharacter` maps it to the phase.
"""
function pairing_exponent(::Pow2Bicharacter{W}, x::Integer, y::Integer) where {W}
    # ctw2/F19 guard sweep: `Int(x)*Int(y)` overflows a signed host Int once
    # `2W > Sys.WORD_SIZE-2` (values `< 2^W`), and `1<<W` once `W ≥ Sys.WORD_SIZE-1`.
    # Harmless at law-test widths (tier cutoff W≤20); fail loud above rather than
    # silently wrapping the exponent (CLAUDE.md #1).
    (1 ≤ 2W ≤ Sys.WORD_SIZE - 2) || throw(DomainError(W,
        "pairing_exponent: width W=$W would overflow the host-Int product Int(x)*Int(y) " *
        "(need 2W ≤ $(Sys.WORD_SIZE - 2)); this path is a small-W law-test helper."))
    return mod(Int(x) * Int(y), 1 << W)
end

"""
    bicharacter(::Pow2Bicharacter{W}, x, y) -> ComplexF64

The pairing phase B_W(x,y) = ω^{xy}, ω = e^{2πi/2^W}, via the exact exponent.
"""
function bicharacter(b::Pow2Bicharacter{W}, x::Integer, y::Integer) where {W}
    N = 1 << W
    return cispi(2 * pairing_exponent(b, x, y) / N)
end

"""
    duality(::Type{<:AbstractQubit}) -> DualitySpec

The F19 trait for a single-wire register (`QBool`, `WireRef`): G = ℤ₂
(self-dual), transform = the exact kernel `H` (F = H = F†), pairing (−1)^{xy},
declared symmetric. `QInt{W}` supplies its own cyclic specialization
(types/qint.jl). CONTEXT-FREE (P7 trait).
"""
duality(::Type{<:AbstractQubit}) =
    DualitySpec(Z2Group(), H, Pow2Bicharacter{1}(), SymmetricPairing())

"""
    _dual_transform(reg) -> ProcessValue

The character-group basis change F_G for a register (P7 trait) — the `transform`
component of its `duality` spec. For `QBool` it is the exact kernel `H` (ℤ₂
self-dual; docs/physics/wharton_koch_quaternion_bloch.md); for `QInt{W}` it is
`QFT(W, false)` (F ≠ F†; the direction pinned by the Pontryagin unit test, §3.3).
INTERNAL — never a surface name; the view applies it, never stores it.
"""
_dual_transform(x) = transform(duality(typeof(x)))

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

# A view is an ADDRESSING MODE, not a number-like handle (F15): it re-addresses a
# borrowed handle and does NOT ride P9. Its owning context and context type come
# from the parent — the single source of truth (F16: no redundant `C` on the
# wrapper; `DualView{QInt{W,C}}` already carries `C`).
register_style(::Type{<:AbstractView}) = AddressingModeStyle()
contextof(v::AbstractView) = contextof(v.parent)
contexttype(::Type{<:DualView{H}}) where {H} = contexttype(H)
contexttype(::Type{<:View{V,H}}) where {V,H} = contexttype(H)

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
