# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M9 (bead Sturm.jl-8oo9, design
# `docs/design/m9-addq-inplace-perm-design.md` §6, closes F24): `QMod{N,W,C}`,
# the modular integer register handle over ℤ_N, embedded in `W = ndigits(N-1;
# base=2)` binary-padded wires.
#
# STATIC MODULUS IN THE TYPE (F24, PRD-v2 §3.1). `N` is a type parameter, not a
# runtime field: it declares the logical Hilbert dimension ℂ^N, the group ℤ_N,
# which multipliers are units, and the conjugate transform F_N (P7 — the register
# type declares its symmetry structure). Two width-4 registers with moduli 13 and
# 15 do NOT carry the same symmetry structure, so a runtime `modulus` field would
# collapse them to one concrete type and defer algebra/dispatch to runtime
# branches. The width `W = ndigits(N-1; base=2) = ⌈log₂N⌉` is DERIVED; the inner
# constructor rejects any inconsistent `(N,W)`. This mirrors the shipped
# `QInt{W,C}` (F16/`vanm`): `C` is the trailing internal context parameter, so
# `QMod{N}` and `QMod{N,W}` remain valid partial `UnionAll`s.
#
# Physics/spec grounding: PRD-v2 §3.1 (register types; static modulus F24), §3.4
# (the in-place `Perm` action `mulmod!`), §6 P7 (dimension-agnostic by
# parametricity). The full-space modular permutation and its bijectivity proof:
# `docs/design/m9-addq-inplace-perm-design.md` §2.

"""
    _modwidth(N) -> Int

The derived embedding width `W = ndigits(N-1; base=2) = ⌈log₂N⌉` (for `N ≥ 2`)
of a `QMod{N}` register: the fewest binary wires holding every logical value
`0:N-1`. Marked foldable so the width is a compile-time constant when `N` is a
static type parameter (keeping `QMod{N}(v)` inference-clean — the F24/`@inferred`
contract). `docs/design/m9-addq-inplace-perm-design.md` §2.
"""
Base.@assume_effects :foldable _modwidth(N::Integer) = ndigits(N - 1; base = 2)

"""
    _check_qmod_params(N, W)

Inner-constructor consistency guard (fail-loud, CLAUDE.md #1): `N` must be a
concrete `Int ≥ 2`, and `W` must equal the DERIVED width `ndigits(N-1; base=2)`.
An inconsistent `(N,W)` — e.g. `QMod{15,3,C}` — is a hard `ArgumentError`, never a
silent reinterpret (a wrong width would misplace every bit of the padded
permutation). `docs/design/m9-addq-inplace-perm-design.md` §6.
"""
@inline function _check_qmod_params(N, W::Integer)
    (N isa Integer && N ≥ 2) || throw(ArgumentError(
        "QMod{N,W,C}: modulus N must be an Integer ≥ 2; got N=$N (::$(typeof(N)))."))
    Wd = _modwidth(N)
    W == Wd || throw(ArgumentError(
        "QMod{$N,$W,C}: width $W is inconsistent with the modulus — the derived " *
        "embedding width is ndigits($N-1; base=2) = $Wd. `W` is DERIVED from `N`, " *
        "never chosen (F24, §3.1)."))
    return nothing
end

"""
    QMod{N,W,C}(ctx::C, wires::NTuple{W,WireID})   [field constructor — internal]
    QMod{N}(v::Integer = 0)                         [preparation cast, cq]
    QMod(::Val{N}, v::Integer = 0)                  [preparation cast, cq]
    QMod{N}(ctx::C, v::Integer = 0)                 [typed worker; `public`]

A modular integer register handle over ℤ_N: `W = ndigits(N-1; base=2)` wires
(wire 1 = MSB, shared with `QInt`) into a context that owns the state (§4.3). `N`
is the ONLY user-semantic value in the type (it declares ℂ^N, ℤ_N, its units,
F_N — P7); `W` is derived and the CONCRETE owning-context type `C` is a trailing
internal execution parameter (F16), so `QMod{N}` stays a valid partial `UnionAll`.

`QMod{N}(v)` is the preparation cast (a dynamic barrier over `current_context()`,
so it infers as `QMod{N,W}`): allocate `W` fresh |0⟩ wires (region-owned, §3.9)
and set the bits of `v` with the EXACT kernel `X` (never `Ry(π)` — §3.4 latent
phase). `v ∉ 0:N-1` is a `DomainError` (a literal names a point in ℤ_N). There is
NO dynamic `QMod(N::Integer, v)` constructor (a `Val(N)` at a high-cardinality
call site would force unbounded specialization while hiding the static-program
contract, §3.1/F24). The full-space modular permutation `mulmod!(y, c)` lives in
`src/library/modular.jl`.

`docs/design/m9-addq-inplace-perm-design.md` §2/§6; PRD-v2 §3.1.
"""
struct QMod{N,W,C<:AbstractContext} <: AbstractQRegister{C}
    ctx::C
    wires::NTuple{W,WireID}

    function QMod{N,W,C}(ctx::C, wires::NTuple{W,WireID}) where {N,W,C<:AbstractContext}
        _require_concrete_context(C)
        _check_qmod_params(N, W)
        return new{N,W,C}(ctx, wires)
    end
end

# Chart guard, shared by barrier and typed worker; runs BEFORE any context lookup.
@inline function _check_qmod_lit(::Val{N}, v::Integer) where {N}
    (0 ≤ v < N) || throw(DomainError(v,
        "QMod{$N}(v): a preparation literal must name a point in 0:$(N - 1) (the " *
        "ring ℤ_$N); got $v. Modular arithmetic wraps (`mulmod!`), but a literal " *
        "outside the ring is a bug (§3.2)."))
    return nothing
end

# Public zero-context barrier: reads `current_context()` once, hands to the worker.
function QMod{N}(v::Integer = 0) where {N}
    _check_qmod_lit(Val(N), v)
    return QMod{N}(current_context(), v)
end

# `Val`-spelled sibling (PRD-v2 §3.1 public constructor set): same barrier.
QMod(::Val{N}, v::Integer = 0) where {N} = QMod{N}(v)

"""
    QMod{N}(ctx::C, v::Integer = 0) -> QMod{N,W,C}

The context-explicit preparation cast (`public`, not exported): allocate `W`
fresh |0⟩ wires in `ctx` and set the bits of `v`, returning an inference-clean
`QMod{N,W,C}`. The hot-loop / internal-seam entry (avoids re-reading the
ScopedValue); the ℤ_N analogue of `QInt{W}(ctx, n)`.
"""
function QMod{N}(ctx::C, v::Integer = 0) where {N,C<:AbstractContext}
    _check_qmod_lit(Val(N), v)
    W = _modwidth(N)
    ws = ntuple(_ -> allocate!(ctx), Val(_modwidth(N)))   # Val ⇒ inference-clean tuple length
    x = QMod{N,W,C}(ctx, ws)
    @inbounds for j in 1:W
        ((v >> (W - j)) & 1) == 1 && apply!(ctx, X, (ws[j],))   # wire j = bit 2^{W-j}; exact X
    end
    return x
end

"""
    _here(y::QMod{N,W,C}) -> C

Assert `y`'s owning context is the active one and OPEN, return it as concrete `C`
(the `QMod` sibling of the `QInt`/`AbstractQubit` `_here`, fail-loud). ArgumentError
on an escaped handle; ErrorException on a torn-down context, before any FFI touch.
"""
@inline function _here(y::QMod{N,W,C}) where {N,W,C}
    ctx = contextof(y)
    ctx === current_context() || throw(ArgumentError(
        "action on QMod register $(y.wires): the handle belongs to a different " *
        "context than the active one — a handle escaped its context/region."))
    _require_open(ctx, "action on QMod register $(y.wires)")
    return ctx
end

# A returned QMod escapes carrying all W wires (regions.jl `_escaped_wires`); a
# QMod that stays local (Shor's `y`) is traced at region exit — that trace is the
# Stinespring boundary that makes order finding work (§3.9/§7.7).
_escaped_wires(y::QMod) = collect(y.wires)

"""
    Int(y::QMod{N,W,C}) -> Int

The MEASUREMENT cast (qc, §3.2) for a modular register: measure all `W` wires in
the computational basis (MSB-first, `n = Σ y_j 2^{W-j}`) and return the host `Int`
in `0:2^W-1` (a padded-tail state `N ≤ n < 2^W` is a legal physical outcome). The
ℤ_N analogue of `Int(::QInt)`; fails loud (guardrail 1) under a live `when`
control, on a cross-context handle, and reuses the Eager `_cast_int` measure loop.
`W ≤ Sys.WORD_SIZE-1` always holds for a `QMod` under the backend qubit budget.
"""
function Base.Int(y::QMod{N,W,C}) where {N,W,C}
    ctx = _here(y)
    _assert_no_control(ctx, "measurement cast Int(y::QMod)")
    return _cast_int(ctx, Val(W), y.wires)
end

"""
    modulus(::Type{<:QMod{N}}) -> N
    modulus(y::QMod{N}) -> N

The static modulus `N` of a `QMod` register (its declared logical dimension ℂ^N /
group ℤ_N; P7). A type-level accessor — there is no runtime `modulus` field (F24).
`public`.
"""
modulus(::Type{<:QMod{N}}) where {N} = N
modulus(y::QMod{N}) where {N} = N
