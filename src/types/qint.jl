# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M6 (bead Sturm.jl-80g6): `QInt{W}`,
# the width-`W` integer register handle (the ℤ_{2^W} generalisation of `QBool`),
# its preparation/measurement casts, and `x[i]` — the borrowed single-wire slice
# `WireRef` (D2). Arithmetic (the two D12 worlds) lives in surface/arithmetic.jl;
# the Fourier dual value in kernel/qft.jl.
#
# THE ENDIANNESS PIN (one convention, kernel-wide): WIRE 1 = MSB. `x.wires[1]`
# carries bit weight `2^{W−1}`, `x.wires[W]` the units bit, so
# `Int(x) = Σ_{j=1}^W x_j · 2^{W−j}` and the tuple hands straight to `apply!`
# (whose position 1 is a value's MSB wire) and to `Perm`/`Ctrl`/`QFT` — all
# MSB-leading. No LSB helper layer: a bit-order slip would show up in exactly one
# convention (this file's cast loops), not in a scattered reversal.
#
# BORROW vs OWN (§8.5, the SubArray-vs-Array split): `x[i]` returns a `WireRef`,
# a distinct `AbstractQubit` that BORROWS `x`'s wire `i` (no `allocate!`, no
# owned-set entry — its death traces nothing). Measuring it (`Bool(x[i])`)
# consumes THE SHARED WIRE on the single-sourced consumed set (§4.5), a PARTIAL
# consumption of `x`; there is no per-object consumed flag to drift. A later
# `Int(x)` then fails loud on the holed register (the §8.5 regression, closed by
# construction). The distinct type (not a bare `QBool`) is the dispatchable
# aliasing hook and keeps a borrow from masquerading as an owned register.
#
# Physics/spec grounding: PRD-v2 §3.1 (register types; W the only type
# parameter), §3.2 (casts), §3.9 (allocation-is-initialisation, regions), §4.5
# (single-sourced consumption), §8.5 (partial consumption), D2 (wire handles),
# D12 (two arithmetic worlds — the arithmetic itself is surface/arithmetic.jl).
# Fourier dual: docs/physics/chen_stoudenmire_white_qft_entanglement.md.

"""
    QInt{W,C}(ctx::C, wires::NTuple{W,WireID})  [field constructor — internal]
    QInt{W}(n::Integer)                         [preparation cast, cq]
    QInt{W}(ctx::C, n::Integer)                 [typed worker; `public`]

A width-`W` integer register handle: `W` wires (wire 1 = MSB) into a context that
owns the state (§4.3), the ℤ_{2^W} analogue of `QBool`. `W` is the only
USER-semantic type parameter (§3.1); the CONCRETE owning-context type `C` is a
TRAILING internal execution parameter (F16), so `QInt{W}` remains a valid partial
`UnionAll` — every `x::QInt{W} where {W}` signature keeps matching — while the
`ctx::C` field is concrete, making handle ops inference-clean (Ruling D: the
`Int(x)` return varies by context, so dispatch must reach `C`).

`QInt{W}(n)` is the preparation cast (a dynamic barrier over `current_context()`,
so it infers as `QInt{W}`): allocate `W` fresh |0⟩ wires (region-owned, §3.9) and
set the bits of `n` with the EXACT kernel `X` (never `Ry(π)` — the §3.4
latent-phase discipline). `n ∉ 0:2^W−1` is a `DomainError` (a literal names a
point in the ring; the chart is `[0, 2^W)`), whereas `add!` OVERFLOW WRAPS
(ℤ_{2^W} is the group — documented, tested, never an error): the asymmetry is
deliberate. `QInt{W}(ctx::C, n)` is the inference-clean typed worker (`QInt{W,C}`).
"""
struct QInt{W,C<:AbstractContext} <: AbstractQRegister{C}
    ctx::C
    wires::NTuple{W,WireID}

    function QInt{W,C}(ctx::C, wires::NTuple{W,WireID}) where {W,C<:AbstractContext}
        _require_concrete_context(C)
        return new{W,C}(ctx, wires)
    end
end

# Chart guard, shared by barrier and typed worker; runs BEFORE any context lookup.
@inline function _check_qint_lit(::Val{W}, n::Integer) where {W}
    _shift_width_guard(W, "QInt{$W}(n) literal range check")   # ctw2/F23: no silent `1<<W` wrap
    (0 ≤ n < (1 << W)) || throw(DomainError(n,
        "QInt{$W}(n): a preparation literal must name a point in 0:$( (1 << W) - 1 ) " *
        "(the ring ℤ_{2^$W}); got $n. Arithmetic wraps (`add!`), but a literal " *
        "outside the ring is a bug (D2/§3.2)."))
    return nothing
end

# Public zero-context barrier: reads `current_context()` once, hands to the worker.
function QInt{W}(n::Integer) where {W}
    _check_qint_lit(Val(W), n)
    return QInt{W}(current_context(), n)
end

"""
    QInt{W}(ctx::C, n::Integer) -> QInt{W,C}

The context-explicit preparation cast (`public`, not exported): allocate `W`
fresh |0⟩ wires in `ctx` and set the bits of `n`, returning an inference-clean
`QInt{W,C}`. The hot-loop / internal-seam entry (avoids re-reading the
ScopedValue); the ℤ_{2^W} analogue of `QBool(ctx, b)`.
"""
function QInt{W}(ctx::C, n::Integer) where {W,C<:AbstractContext}
    _check_qint_lit(Val(W), n)
    ws = ntuple(_ -> allocate!(ctx), Val(W))            # W fresh |0⟩ (Val(W) ⇒ inference-clean length; §3.9)
    x = QInt{W,C}(ctx, ws)
    @inbounds for j in 1:W
        ((n >> (W - j)) & 1) == 1 && apply!(ctx, X, (ws[j],))   # wire j = bit 2^{W-j}; exact X
    end
    return x
end

"""
    _adopt_qint(ctx::C, ws::NTuple{W,WireID}) -> QInt{W,C}

INTERNAL seam: wrap ALREADY-live wires as a `QInt{W,C}` handle WITHOUT preparing
anything (the analogue of `_adopt_qbool`). Used by the fresh-output value-world
adders (surface/arithmetic.jl) and the Choi harness.
"""
_adopt_qint(ctx::C, ws::NTuple{W,WireID}) where {W,C<:AbstractContext} = QInt{W,C}(ctx, ws)

"""
    _here(x::QInt{W,C}) -> C

Assert `x`'s owning context is the active one and OPEN, and return it as the
concrete `C` (fail-loud; the `QInt` sibling of the `AbstractQubit` `_here`).
ArgumentError on an escaped handle (WireIDs are per-context — a cross-context id
collision would silently target the wrong physical qubits); ErrorException on a
torn-down (closed) context, before any FFI touch (F16 §5.1).
"""
@inline function _here(x::QInt{W,C}) where {W,C}
    ctx = contextof(x)
    ctx === current_context() || throw(ArgumentError(
        "action on QInt register $(x.wires): the handle belongs to a different " *
        "context than the active one — a handle escaped its context/region."))
    _require_open(ctx, "action on QInt register $(x.wires)")
    return ctx
end

"""
    _int_host_width_guard(ctx, W)

F23 host-scalar width guard: `Int(x)` is an *honest machine-`Int`* cast, so on a
context whose `Int(x)` returns a host `Int` (Eager) it admits exactly
`1 ≤ W ≤ Sys.WORD_SIZE-1` (every unsigned `W`-bit outcome fits a signed host
`Int`) and throws BEFORE any backaction for `W ≥ Sys.WORD_SIZE` — never silently
widening to `BigInt` (`BigInt(x)` is the explicit wide cast). On contexts whose
`Int(x)` returns a fixed-width record TOKEN (DM/Tracing → `ClassicalWord{W}`) the
limit does not apply — the token carries the width, no host scalar is formed
(PRD-v2 §3.2, F23). `W ≤ 0` is rejected everywhere.
"""
@inline function _int_host_width_guard(::EagerContext, W::Int)
    (1 ≤ W ≤ Sys.WORD_SIZE - 1) || throw(ErrorException(
        "Int(QInt{$W}) cannot represent every $W-bit outcome on this " *
        "$(Sys.WORD_SIZE)-bit host (need 1 ≤ W ≤ $(Sys.WORD_SIZE - 1)); use " *
        "`BigInt(x)`. Rejected before measurement (F23)."))
    return nothing
end
@inline _int_host_width_guard(::AbstractContext, W::Int) =
    (W ≥ 1 || throw(ErrorException("Int(QInt{$W}): width must be ≥ 1 (F23).")); nothing)

"""
    Int(x::QInt{W}) -> Int | ClassicalWord{W}

The MEASUREMENT cast (qc, §3.2), THE measurement spelling in every context
(Ruling D, §3.6/§14): measure all `W` wires in the computational basis (MSB-first,
`n = Σ x_j 2^{W−j}`). Fails loud BEFORE any backaction on a PARTIALLY-consumed
register — a wire already measured via `Bool(x[i])` (§8.5) — on a cross-context
handle, and (guardrail 1) under a live `when` control, and — the F23 bound — when
`W ≥ Sys.WORD_SIZE` on a host-`Int` context (use `BigInt(x)`). The RETURN varies by
context: a real `Int` on EAGER (measure+consume, unchanged); a `ClassicalWord{W}`
record TOKEN on DM (`_cast_int(::DensityMatrixContext, …)`, surface/tokens.jl —
the pinched record, summed at region exit / `discard!`).
"""
function Base.Int(x::QInt{W,C}) where {W,C}
    ctx = _here(x)
    _int_host_width_guard(ctx, W)     # F23: fail BEFORE any backaction, host-Int contexts only
    _assert_no_control(ctx, "measurement cast Int(x)")
    # Partial-consumption guard (D2/§8.5): a set check on the single-sourced
    # consumed set + liveness, BEFORE any measurement — never a silent reinterpret.
    dead = filter(w -> is_consumed(ctx, w) || !haskey(_core(ctx).wire_to_slot, w),
                  collect(x.wires))
    isempty(dead) || error(
        "Int(x): register $(x.wires) is partially consumed — wire(s) $(dead) are dead " *
        "(a slice `x[i]` was measured via `Bool(x[i])`, or the register was traced). " *
        "Measure the remaining wires explicitly; do not `Int(x)` a holed register (D2/§8.5).")
    return _cast_int(ctx, Val(W), x.wires)   # Eager: Int; DM: ClassicalWord{W} token
end

"""
    _cast_int(ctx::EagerContext, Val(W), wires) -> Int

The Eager (trajectory) qc for a width-`W` register: measure each wire MSB-first,
reassemble the integer, mark each consumed (§4.5). The DM sibling
(`_cast_int(::DensityMatrixContext, …)` → `ClassicalWord{W}`) lives in
surface/tokens.jl (Ruling D).
"""
function _cast_int(ctx::EagerContext, ::Val{W}, wires::NTuple{W,WireID}) where {W}
    n = 0
    @inbounds for j in 1:W
        _measure_wire!(ctx, wires[j]) && (n |= (1 << (W - j)))   # MSB-first reassembly
        mark_consumed!(ctx, wires[j])
    end
    return n
end

# A returned QInt escapes carrying all W wires (regions.jl `_escaped_wires`).
_escaped_wires(x::QInt) = collect(x.wires)

# ---------------------------------------------------------------------------
# `x[i]` — the borrowed single-wire slice (D2)
# ---------------------------------------------------------------------------

"""
    WireRef   [construct via `x[i]`]

A BORROW of one wire of a parent `QInt` — a distinct `AbstractQubit` (NOT a bare
`QBool`), so the single-wire surface family (`not!`, `⊻=`, `dual`, `when`, `Bool`)
reaches it through the widened `::AbstractQubit` methods (M3/M4/M5), while its
BORROW nature stays a dispatch fact: it never `allocate!`s (its death traces
nothing), and `Bool(x[i])` consumes the shared wire (partial consumption of the
parent). `reg`/`idx` are provenance for messages only; aliasing safety is already
guaranteed because `x[i].wire === x.wires[i]` (a `WireID` collision `apply!`
catches — §8.4).
"""
struct WireRef{C<:AbstractContext} <: AbstractQubit{C}
    ctx::C
    wire::WireID
    reg::WireID     # provenance: the parent's MSB wire (messages only)
    idx::Int        # 1-based slice index (messages only)

    function WireRef{C}(ctx::C, wire::WireID, reg::WireID, idx::Int) where {C<:AbstractContext}
        _require_concrete_context(C)
        return new{C}(ctx, wire, reg, idx)
    end
end

"""
    getindex(x::QInt{W}, i::Integer) -> WireRef

`x[i]` — a borrowed handle on wire `i` (wire 1 = MSB). No `allocate!`: the wire is
`x`'s, and only `x` (or a slice consuming it) traces it. `BoundsError` off
`1:W` (the Base idiom).
"""
function Base.getindex(x::QInt{W,C}, i::Integer) where {W,C}
    (1 ≤ i ≤ W) || throw(BoundsError(x, i))
    return WireRef{C}(x.ctx, x.wires[i], x.wires[1], Int(i))
end

# A returned slice escapes carrying its one borrowed wire (regions.jl).
_escaped_wires(r::WireRef) = [r.wire]

# ---------------------------------------------------------------------------
# The register dual `dual(x::QInt)` — the Fourier view on ℤ_{2^W}
# ---------------------------------------------------------------------------

"""
    duality(::Type{<:QInt{W}}) -> DualitySpec

The F19 duality/bicharacter trait of a `QInt{W}` register (§3.3), CONTEXT-FREE:
`QInt{W,EagerContext}` and `QInt{W,DensityMatrixContext}` describe the same
Hilbert space, group ℤ_{2^W}, Fourier transform, and pairing. Its
`transform = QFT(W, false)` is the forward DFT `F` on ℤ_{2^W} (kernel/qft.jl);
unlike `QBool`'s self-dual `H`, F ≠ F† (the direction pinned by the Pontryagin
modulation test, surface/arithmetic.jl). Its bicharacter is `ω^{xy}`,
ω = e^{2πi/2^W}, declared `SymmetricPairing`. `_dual_transform` (views.jl) reads
`.transform`. See kernel/views.jl for the trait machinery. INTERNAL trait (P7).
"""
duality(::Type{<:QInt{W}}) where {W} =
    DualitySpec(Cyclic2PowGroup{W}(), QFT(W, false), Pow2Bicharacter{W}(), SymmetricPairing())

"""
    action_group(::Type{<:QInt{W}}, ::ActionFamily) -> AbstractActionGroup

The label group of a `QInt{W}` action FAMILY (F19), keeping the two DISTINCT
group structures from being conflated (§3.4/D12): the additive `add!`/`dual(x)`
world is cyclic ℤ_{2^W} (`Cyclic2PowGroup{W}`), while the transversal bitwise
`x ⊻= y` world is (ℤ₂)^W (`BitVectorGroup{W}`). Same register, two group actions —
`dual(x)` (the QFT) is the character group of the CYCLIC one, never the bitwise.
"""
action_group(::Type{<:QInt{W}}, ::AddFamily) where {W} = Cyclic2PowGroup{W}()
action_group(::Type{<:QInt{W}}, ::XorFamily) where {W} = BitVectorGroup{W}()

"""
    dual(x::QInt{W}) -> DualView

The Fourier (conjugate-character) view of an integer register (§3.3): a fresh,
zero-cost, lazy wrapper — a different way to ADDRESS `x`, not an operation on it.
`F` is applied only when a cast/op-assign forces it (`Int(dual(x))` measures in
the Fourier basis; `x̂ += a` modulates — surface/arithmetic.jl). `dual(dual(x))
=== x` is the structural unwrap (`dual(v::DualView)=v.parent`, views.jl), NEVER
an application of `F` — applying `F` twice would negate integers (F² = parity),
the normative bug of §3.3. Per-wire indexing `dual(x)[i]` is UNDEFINED (throws):
the register dual is not a tensor product across any cut.
"""
dual(x::QInt) = DualView(x)

"""
    getindex(v::DualView{<:QInt}, i::Integer)

`dual(x)[i]` is a DEFINED method that THROWS `ArgumentError` (the
`Symmetric`/`UpperTriangular` forbidden-entry idiom — `hasmethod` stays `true`,
the message states the reason): the register dual of a `QInt{W}` is the QFT `F`
on ℤ_{2^W}, which is NOT a tensor product across ANY register cut
(Chen–Stoudenmire–White, arXiv:2210.08468 — no local `wire i` of it exists).
Did you mean `dual(x[i])` (the ℤ₂ dual of one wire)?
"""
Base.getindex(v::DualView{<:QInt}, i::Integer) = throw(ArgumentError(
    "dual(x)[$i] is undefined: for a QInt{W} the register dual is the Fourier view " *
    "on ℤ_{2^W} (the QFT), which is NOT a tensor product across any register cut " *
    "(Chen–Stoudenmire–White, arXiv:2210.08468) — there is no local `wire $i` of it. " *
    "Did you mean `dual(x[$i])` (the ℤ₂ dual of one wire)?"))

"""
    Int(v::DualView{<:QInt{W}}) -> Int

The Fourier-basis MEASUREMENT cast (§3.3): apply the register's F_G = `F`
(uncontrolled — the M4 `Bool(dual(q))` basis-change pattern; guardrail 1 asserted
first), then the consuming computational-basis `Int(parent)`. `F` is APPLIED here
(the process), distinct from the structural `dual(dual(x))===x` unwrap (the view)
— the two are genuinely different code paths (the F²-vs-unwrap signature test).
"""
function Base.Int(v::DualView{<:QInt{W}}) where {W}
    x = v.parent
    ctx = _here(x)
    _int_host_width_guard(ctx, W)     # F23: fire BEFORE the Fourier transform (backaction)
    _assert_no_control(ctx, "Fourier-basis measurement cast Int(dual(x))")
    apply!(ctx, _dual_transform(x), x.wires)   # F, uncontrolled (fuses into no 1q buffer; QFT emits directly)
    return Int(x)
end

"""
    BigInt(x::QInt{W,C}) -> BigInt

The WIDE consuming (qc) measurement cast (F23, PRD-v2 §3.2, Δ3): measure all `W`
wires in the computational basis (MSB-first, `n = Σ x_j 2^{W-j}`) and return a
`BigInt`, valid for EVERY width `W ≥ 1` — where `Int(x)` would throw for
`W ≥ Sys.WORD_SIZE`. `BigInt` is a Base constructor, so returning a `BigInt` from
`BigInt(x)` is honest (unlike making `Int(x)` widen); it is the same measurement
cast spelled with a constructor, NOT a new `measure` verb (Ruling D). The natural
spelling for Shor's Fourier sample `BigInt(dual(k))` (§7.7). Same fail-loud order
as `Int(x)` (partial-consumption / cross-context guards), minus the host-scalar
width bound. On DM/Tracing the return is the fixed-width record token (Ruling D).
"""
function Base.BigInt(x::QInt{W,C}) where {W,C}
    ctx = _here(x)
    W ≥ 1 || throw(ErrorException("BigInt(QInt{$W}): width must be ≥ 1."))
    _assert_no_control(ctx, "measurement cast BigInt(x)")
    dead = filter(w -> is_consumed(ctx, w) || !haskey(_core(ctx).wire_to_slot, w),
                  collect(x.wires))
    isempty(dead) || error(
        "BigInt(x): register $(x.wires) is partially consumed — wire(s) $(dead) are dead " *
        "(a slice `x[i]` was measured via `Bool(x[i])`, or the register was traced). " *
        "Measure the remaining wires explicitly; do not `BigInt(x)` a holed register (D2/§8.5).")
    return _cast_bigint(ctx, Val(W), x.wires)
end

"""
    _cast_bigint(ctx::EagerContext, Val(W), wires) -> BigInt

The Eager (trajectory) wide qc: measure each wire MSB-first, reassemble the
integer as a `BigInt` (`big(1) << (W-j)`), mark each consumed (§4.5). Other
contexts return their fixed-width record token via `_cast_int` (Ruling D).
"""
function _cast_bigint(ctx::EagerContext, ::Val{W}, wires::NTuple{W,WireID}) where {W}
    n = big(0)
    @inbounds for j in 1:W
        _measure_wire!(ctx, wires[j]) && (n |= (big(1) << (W - j)))   # MSB-first reassembly
        mark_consumed!(ctx, wires[j])
    end
    return n
end
# Off Eager, a wide cast reduces to the context's own record token (Ruling D).
_cast_bigint(ctx::AbstractContext, ::Val{W}, wires::NTuple{W,WireID}) where {W} =
    _cast_int(ctx, Val(W), wires)

"""
    BigInt(v::DualView{<:QInt{W}}) -> BigInt

The wide Fourier-basis measurement cast (F23): apply the register's `F` (uncontrolled,
the `Int(dual(x))` pattern), then the wide computational-basis `BigInt(parent)`.
The natural spelling for the Shor phase sample `BigInt(dual(k))` (§7.7).
"""
function Base.BigInt(v::DualView{<:QInt{W}}) where {W}
    x = v.parent
    ctx = _here(x)
    W ≥ 1 || throw(ErrorException("BigInt(dual(x)): width must be ≥ 1."))
    _assert_no_control(ctx, "Fourier-basis measurement cast BigInt(dual(x))")
    apply!(ctx, _dual_transform(x), x.wires)   # F, uncontrolled
    return BigInt(x)
end
