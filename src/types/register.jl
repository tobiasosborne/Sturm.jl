# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. F16 (bead Sturm.jl-vanm): the context-indexed
# register hierarchy that makes handle-driven hot paths inference-clean, plus
# the F15 number-like-handle contract. Every owned or borrowed quantum register
# handle (`QBool{C}`, `QInt{W,C}`, `WireRef{C}`) carries the CONCRETE type `C` of
# its owning context, so `x.ctx` loads as a concrete type, `_here(x)` returns a
# concrete `C`, and `_act!`/`apply!`/casts dispatch statically — the M4/M6
# defect this file closes (before: `fieldtype(QBool,:ctx) === AbstractContext`,
# a dynamic dispatch on every action; after: `=== EagerContext`).
#
# TWO SOURCES OF SAFETY, KEPT DISTINCT (F16 §5). The type parameter `C` selects
# the COMPILED CODE; the context INSTANCE (stored in `ctx::C`) establishes
# OWNERSHIP by object identity. Two different `EagerContext` objects share
# `C = EagerContext` yet are distinct state owners — so `C` alone can never
# authorize an operation. Every surface op still runs the `ctx === current` and
# `ctx === other.ctx` identity checks (`_here`, actions.jl); the parameter buys
# inference, not the mixing guard. This is why `WireID` stays UNparameterized: a
# `WireID{C}` would distinguish context KINDS but still not two instances of one
# kind, and would metastasize through every kernel dict without carrying its
# weight (F16 §15, alternatives rejected).
#
# WHY `C` IS TRAILING (`QInt{W,C}`, not `QInt{C,W}`): so `QInt{W}` remains a
# valid partial `UnionAll` — every shipped `x::QInt{W} where {W}` signature and
# `dual(x)::DualView{<:QInt{W}}` method keeps matching, and `W` remains the ONLY
# user-semantic parameter (PRD-v2 §3.1). `C` is an internal execution parameter.
#
# Physics/spec grounding: PRD-v2 §3.4 (number-like handles, F15 — the two
# arithmetic worlds), §3.6 (Ruling D: cast return varies by context, so dispatch
# must reach the concrete context type), §3.8 (portability), §6 P7/P8/P9
# (dimension-agnostic by parametricity; generic code rides the overloads; NO
# catch-all on `Function`; no `Number`/`Integer` subtyping).

"""
    AbstractQRegister{C<:AbstractContext}

Supertype of every quantum register HANDLE — an owned register (`QBool{C}`,
`QInt{W,C}`) or a borrow (`WireRef{C}`) — owned by a context of concrete type
`C`. A register is "a handle into a context that owns the state" (§4.3); the
handle stores that context in a `ctx::C` field, reached by `contextof`.

# Number-like handles, NOT numbers (F15, PRD-v2 §3.4)

A register is a NUMBER-LIKE HANDLE: it names a quantum value and carries the
group action on it, but it is NOT a `Number` or `Integer` subtype and has NO
host value semantics. The shipped operator surface, per register type:

| Type | Value world (fresh output) | Action world (in-place, same handle) | Other |
|---|---|---|---|
| `QBool{C}` / `WireRef{C}` | `false ⊻ q`, `true ⊻ q` → fresh `QBool{C}` | `not!`, `q ⊻= r`, `q ⊻= b::Bool` | `Bool(q)`, `dual`, `when` |
| `QInt{W,C}` | `x + a`, `a + x`, `x - a`, `x + y` → fresh `QInt{W,C}` | `add!`, `sub!`, `add!(y,x)`, `x ⊻= y`, `x ⊻= n`, `superpose!` | `Int(x)`, `x[i]`, `dual`, `when`, `oracle` |
| `DualView{QInt{W,C}}` | — | `x̂ += a`, `x̂ -= a` (modulation) | `Int`, `when` |
| `DualView{<:AbstractQubit{C}}` | — | `not!`, `q̂ ⊻= r` (CZ) | `Bool`, `when` |

DELIBERATELY ABSENT (each a `MethodError` or a loud throw, never a silent value
interpretation): `<: Number`/`<: Integer`; `zero`/`one`/`typemin`/`typemax`/
promotion/scalar `convert`; `*`/`/`/`%`/`^`/shifts/broadcast/iteration;
host-valued `==`/`isequal`/`hash`/`isless`/`<`; use as a `Dict` key; generic
`f(::Integer)` dispatch. `===` remains the handle-identity test (it inspects no
quantum state). Branch-heavy ordinary code goes through `oracle(f, x)` (P9); a
coherent comparator, when added, returns `QBool{C}`, never host `Bool` (F16 §8).

The negative surface is enforced by loud `==`/`isequal`/`hash`/`isless` methods
below — Base's fallbacks would otherwise give a register a misleading
identity-shaped `==`/`hash`, and a value-treating bug must fail, not limp.
"""
abstract type AbstractQRegister{C<:AbstractContext} end

"""
    AbstractQubit{C<:AbstractContext} <: AbstractQRegister{C}

Supertype of every SINGLE-WIRE quantum handle: `QBool{C}` (an owned register)
and `WireRef{C}` (a borrowed slice `x[i]` of a `QInt`). Both carry a `.ctx::C`
and a `.wire::WireID`, so the single-wire surface family — the action family
(`not!`, `⊻=`), `dual`, `when`, and the `Bool`/`convert` casts — dispatches on
`AbstractQubit{C}` and is written ONCE (the `AbstractArray` reuse move,
CLAUDE.md #13). OWN-vs-BORROW is NOT in these shared ops: it lives in
construction (a `WireRef` never `allocate!`s) and in consumption (measuring a
`WireRef` consumes the shared wire on the single-sourced set — a partial
consumption of its parent register, PRD-v2 §4.5/§8.5).
"""
abstract type AbstractQubit{C<:AbstractContext} <: AbstractQRegister{C} end

# --- Register-style trait (F15): number-like handle vs addressing mode -----

"""
    RegisterStyle

Trait supertype separating the two families of quantum reference (`register_style`):
a `NumberLikeHandleStyle` (an `AbstractQRegister`: names a value, rides the P8/P9
overload surface) from an `AddressingModeStyle` (an `AbstractView`: a lazy
re-addressing of a handle, NOT a number — it does not ride P9; §3.3). Library
generic code dispatches on the style rather than re-testing concrete types. `public`.
"""
abstract type RegisterStyle end
struct NumberLikeHandleStyle <: RegisterStyle end
struct AddressingModeStyle <: RegisterStyle end

register_style(::Type{<:AbstractQRegister}) = NumberLikeHandleStyle()
register_style(x) = register_style(typeof(x))

"""
    contextof(x::AbstractQRegister{C}) -> C

The concrete owning context of a register handle (its `ctx` field, typed `C`).
The single accessor every hot path reads to reach the context WITHOUT a
`current_context()` ScopedValue read; `_here` (actions.jl/qint.jl) wraps it with
the active-context identity + open-context guard. For a view, `contextof`
delegates to the parent handle (kernel/views.jl). `public`.
"""
@inline contextof(x::AbstractQRegister{C}) where {C} = getfield(x, :ctx)::C

"""
    contexttype(::Type{<:AbstractQRegister{C}}) -> Type{C}
    contexttype(x) -> Type

The concrete context TYPE `C` a handle (or its type) is parameterized by — a
type-level companion to `contextof` (the instance). Recurses through views to
the parent. `public`.
"""
contexttype(::Type{<:AbstractQRegister{C}}) where {C} = C
contexttype(x::AbstractQRegister) = contexttype(typeof(x))

"""
    _require_concrete_context(::Type{C})

Fail loud if a register's context parameter `C` is not a concrete type. Called
by every inner (field) constructor: an abstract `C` (e.g. `QBool{AbstractContext}`)
would defeat the whole F16 refactor by reintroducing a dynamic `ctx` field, so it
is a hard error, not a silent widening (CLAUDE.md #1). ArgumentError (well-formed
but forbidden, S13).
"""
@inline function _require_concrete_context(::Type{C}) where {C<:AbstractContext}
    isconcretetype(C) || throw(ArgumentError(
        "register context parameter must be concrete; got $C — an abstract " *
        "context parameter would reintroduce the dynamic-dispatch defect F16 closes."))
    return nothing
end

# --- F15: no host value semantics (fail loud, never Base's fallback) -------
#
# A register is a handle, not a value: `==`/`isequal`/`hash` on the QUANTUM
# CONTENT is meaningless (no-cloning forbids reading it without measuring), and
# ordering is not defined at all. Base's structural fallbacks would make a
# register look like a comparable/hashable value (they would compare the stored
# `ctx`/`WireID` fields), silently succeeding where a value-treating bug should
# crash. So each is a LOUD throw; `===` remains the handle-identity primitive.
# The three-arg `(reg, reg)` methods break the ambiguity between the `(reg, Any)`
# and `(Any, reg)` methods when BOTH operands are registers.

@noinline _no_value_eq() = throw(ArgumentError(
    "quantum registers have no value equality — measuring is the only way to " *
    "read quantum content, and it consumes the handle (§3.2). Use `===` for " *
    "handle identity, or measure explicitly (`Bool(q)` / `Int(x)`)."))
@noinline _no_value_hash() = throw(ArgumentError(
    "quantum registers are not hashable values — their content is unreadable " *
    "without a consuming measurement (§3.4). Key internal collections on the " *
    "handle's `WireID`s, not the handle."))
@noinline _no_value_order() = throw(ArgumentError(
    "quantum registers have no host ordering — a coherent comparator returns a " *
    "`QBool` (a quantum bit), never a host `Bool`, and is not part of F16 (§3.4)."))

Base.:(==)(::AbstractQRegister, ::AbstractQRegister) = _no_value_eq()
Base.:(==)(::AbstractQRegister, ::Any) = _no_value_eq()
Base.:(==)(::Any, ::AbstractQRegister) = _no_value_eq()
Base.isequal(::AbstractQRegister, ::AbstractQRegister) = _no_value_eq()
Base.isequal(::AbstractQRegister, ::Any) = _no_value_eq()
Base.isequal(::Any, ::AbstractQRegister) = _no_value_eq()
Base.hash(::AbstractQRegister, ::UInt) = _no_value_hash()
Base.isless(::AbstractQRegister, ::AbstractQRegister) = _no_value_order()
Base.isless(::AbstractQRegister, ::Any) = _no_value_order()
Base.isless(::Any, ::AbstractQRegister) = _no_value_order()

# These methods exist ONLY to disambiguate against Base's `::Any`-methods for
# `Missing`/`WeakRef` (the sole types that clash with the broad register methods
# above — `detect_ambiguities` confirms, and runtests.jl gates it at 0). They are
# NOT an exemption: a register is a HANDLE, not data, so it gets NO value
# comparison — `Missing` gets no three-valued-logic pass (that would be the exact
# silent value-interpretation F15 kills, and would contradict the loud `isless`
# above). Every one stays LOUD.
Base.:(==)(::AbstractQRegister, ::Missing) = _no_value_eq()
Base.:(==)(::Missing, ::AbstractQRegister) = _no_value_eq()
Base.isequal(::AbstractQRegister, ::Missing) = _no_value_eq()
Base.isequal(::Missing, ::AbstractQRegister) = _no_value_eq()
Base.isless(::AbstractQRegister, ::Missing) = _no_value_order()
Base.isless(::Missing, ::AbstractQRegister) = _no_value_order()
Base.:(==)(::AbstractQRegister, ::WeakRef) = _no_value_eq()
Base.:(==)(::WeakRef, ::AbstractQRegister) = _no_value_eq()
