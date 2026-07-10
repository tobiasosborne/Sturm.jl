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
    QInt{W}(ctx, wires::NTuple{W,WireID})     [field constructor — internal]
    QInt{W}(n::Integer)                       [preparation cast, cq]

A width-`W` integer register handle: `W` wires (wire 1 = MSB) into a context that
owns the state (§4.3), the ℤ_{2^W} analogue of `QBool`. `W` is the ONLY type
parameter (§3.1); the context is an abstract FIELD (never a second parameter —
the `QBool` "no `QInt{W,C}` metastasis" rule), acceptable because handles are not
the hot loop.

`QInt{W}(n)` is the preparation cast: allocate `W` fresh |0⟩ wires (region-owned,
§3.9) and set the bits of `n` with the EXACT kernel `X` (never `Ry(π)` — the
§3.4 latent-phase discipline). `n ∉ 0:2^W−1` is a `DomainError` (a literal names
a point in the ring; the chart is `[0, 2^W)`), whereas `add!` OVERFLOW WRAPS
(ℤ_{2^W} is the group — documented, tested, never an error): the asymmetry is
deliberate.
"""
struct QInt{W}
    ctx::AbstractContext
    wires::NTuple{W,WireID}
end

function QInt{W}(n::Integer) where {W}
    (0 ≤ n < (1 << W)) || throw(DomainError(n,
        "QInt{$W}(n): a preparation literal must name a point in 0:$( (1 << W) - 1 ) " *
        "(the ring ℤ_{2^$W}); got $n. Arithmetic wraps (`add!`), but a literal " *
        "outside the ring is a bug (D2/§3.2)."))
    ctx = current_context()
    ws = ntuple(_ -> allocate!(ctx), W)                 # W fresh |0⟩, region-owned (§3.9)
    x = QInt{W}(ctx, ws)
    @inbounds for j in 1:W
        ((n >> (W - j)) & 1) == 1 && apply!(ctx, X, (ws[j],))   # wire j = bit 2^{W-j}; exact X
    end
    return x
end

"""
    _adopt_qint(ctx, ws::NTuple{W,WireID}) -> QInt{W}

INTERNAL seam: wrap ALREADY-live wires as a `QInt{W}` handle WITHOUT preparing
anything (the analogue of `_adopt_qbool`). Used by the fresh-output value-world
adders (surface/arithmetic.jl) and the Choi harness.
"""
_adopt_qint(ctx::AbstractContext, ws::NTuple{W,WireID}) where {W} = QInt{W}(ctx, ws)

"""
    _here(x::QInt) -> AbstractContext

Assert `x`'s owning context is the active one and return it (fail-loud; the
`QBool` `_here` for a multi-wire register). ArgumentError on an escaped handle
(WireIDs are per-context — a cross-context id collision would silently target the
wrong physical qubits).
"""
@inline function _here(x::QInt)
    x.ctx === current_context() || throw(ArgumentError(
        "action on QInt register $(x.wires): the handle belongs to a different " *
        "context than the active one — a handle escaped its context/region."))
    return x.ctx
end

"""
    Int(x::QInt{W}) -> Int

The MEASUREMENT cast (qc, §3.2): measure all `W` wires in the computational basis
(MSB-first, `n = Σ x_j 2^{W−j}`), CONSUMING each on the single-sourced set. Fails
loud BEFORE any backaction on a PARTIALLY-consumed register — a wire already
measured via `Bool(x[i])` (§8.5) — and on a cross-context handle, and (guardrail
1) under a live `when` control. Eager-only: on a density context each wire
measurement throws (a scalar outcome is a trajectory, not a channel — §3.8).
"""
function Base.Int(x::QInt{W}) where {W}
    ctx = x.ctx
    ctx === current_context() || throw(ArgumentError(
        "Int(x): QInt register $(x.wires) belongs to a different context than the " *
        "active one — a handle escaped its context/region."))
    _assert_no_control(ctx, "measurement cast Int(x)")
    # Partial-consumption guard (D2/§8.5): a set check on the single-sourced
    # consumed set + liveness, BEFORE any measurement — never a silent reinterpret.
    dead = filter(w -> is_consumed(ctx, w) || !haskey(_core(ctx).wire_to_slot, w),
                  collect(x.wires))
    isempty(dead) || error(
        "Int(x): register $(x.wires) is partially consumed — wire(s) $(dead) are dead " *
        "(a slice `x[i]` was measured via `Bool(x[i])`, or the register was traced). " *
        "Measure the remaining wires explicitly; do not `Int(x)` a holed register (D2/§8.5).")
    n = 0
    @inbounds for j in 1:W
        _measure_wire!(ctx, x.wires[j]) && (n |= (1 << (W - j)))   # MSB-first reassembly
        mark_consumed!(ctx, x.wires[j])
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
struct WireRef <: AbstractQubit
    ctx::AbstractContext
    wire::WireID
    reg::WireID     # provenance: the parent's MSB wire (messages only)
    idx::Int        # 1-based slice index (messages only)
end

"""
    getindex(x::QInt{W}, i::Integer) -> WireRef

`x[i]` — a borrowed handle on wire `i` (wire 1 = MSB). No `allocate!`: the wire is
`x`'s, and only `x` (or a slice consuming it) traces it. `BoundsError` off
`1:W` (the Base idiom).
"""
function Base.getindex(x::QInt{W}, i::Integer) where {W}
    (1 ≤ i ≤ W) || throw(BoundsError(x, i))
    return WireRef(x.ctx, x.wires[i], x.wires[1], Int(i))
end

# A returned slice escapes carrying its one borrowed wire (regions.jl).
_escaped_wires(r::WireRef) = [r.wire]

# ---------------------------------------------------------------------------
# The register dual `dual(x::QInt)` — the Fourier view on ℤ_{2^W}
# ---------------------------------------------------------------------------

"""
    _dual_transform(::QInt{W}) -> QFT

The character-group basis change F_G of a `QInt{W}` register: the forward DFT `F`
on ℤ_{2^W} (`QFT(W, false)`, kernel/qft.jl). Unlike `QBool`'s self-dual `H`, this
is F ≠ F† — the direction is pinned by the Pontryagin modulation test
(surface/arithmetic.jl, §3.3). INTERNAL trait (P7), never a surface name.
"""
_dual_transform(::QInt{W}) where {W} = QFT(W, false)

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
    _assert_no_control(ctx, "Fourier-basis measurement cast Int(dual(x))")
    apply!(ctx, _dual_transform(x), x.wires)   # F, uncontrolled (fuses into no 1q buffer; QFT emits directly)
    return Int(x)
end
