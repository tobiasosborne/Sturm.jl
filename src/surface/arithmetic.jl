# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M6 (bead Sturm.jl-80g6): the TWO
# ARITHMETIC WORLDS of D12 and the Pontryagin sign pins (PRD-v2 §3.3/§3.4).
#
# THE WHOLE MILESTONE IS ONE DISPATCH FACT. The same `Base.:+` generic means
# "fresh output" on a bare register and "in-place physical op" on a bound dual
# view:
#   • VALUE world (P9 ring op): `x + a`, `x + y` allocate a FRESH register and
#     leave the inputs LIVE (reversible dataflow). `x += a` on a BARE register
#     therefore rebinds `x` to the fresh sum and DROPS the original — the
#     lost-binding trap the strict detector flags.
#   • ACTION world (the registered in-place exception): `add!`, `sub!`, `⊻=`
#     mutate in place and RETURN THE SAME HANDLE (the op-assign no-op that makes
#     `a ⊻= b` physical rather than a rebind).
#   • MODULATION world (bound dual view): `x̂ += a` (`x̂ = dual(x)`) is a Ĝ-phase
#     kick, in place, returning the view.
#
# THE SIGN ALGEBRA (all signs derive from two intertwiners on ℤ_N, N = 2^W,
# ω = e^{2πi/N}; F the forward QFT of kernel/qft.jl):
#   translation  T_a|x⟩ = |x+a⟩        modulation  D_b|x⟩ = ω^{bx}|x⟩
#   (I)   F† D_a F = T_a     ⟹  add!(x, a) = F† ∘ D_{+a} ∘ F   (Draper)
#   (II)  F† T_a F = D_{-a}  ⟹  x̂ += a  emits  D_{-a}  DIRECTLY (bare phases)
# The minus sign in (II) is the r6/B2 theorem, not a convention: `x̂ += a` lowers
# to the modulation `D_{-a}`, NEVER a Fourier sandwich. `D_b` is separable
# (`ω^{bx} = Π_j e^{2πi b x_j / 2^j}`, wire j = MSB), so both worlds reduce to
# per-wire phase kicks `P(θ)` — `add!` wraps them in F/F†, the view does not.
#
# REASSOCIATION FOR FREE. In `add!`, F and F† go through `apply!` (UNCONTROLLED —
# a basis change, like the M5 `when(dual(q))` H-sandwich); only `D_a` routes
# through `_act!`. So under a `when` stack of depth k the emission is
# `F† ctrl^k(D_a) F = ctrl^k(T_a)` (the §4.2 law `(1⊗F)∘ctrl(W)∘(1⊗F†) =
# ctrl(FWF†)`, with `F` off the control) — `when(c) do add!(x,a) end` is
# ctrl-wrapped addition, correct by construction, no M8 pass and no ctrl(QFT).
#
# Physics/spec grounding: PRD-v2 §3.3 (dual, Pontryagin sign), §3.4/D12 (two
# worlds), §4.2 (reassociation), §8.4 (aliasing). Draper 2000 (the F†-D_a-F
# adder); docs/physics/chen_stoudenmire_white_qft_entanglement.md (the QFT view).

# ---------------------------------------------------------------------------
# superpose! — the (ℤ₂)^W Hadamard materialisation (a real op, not a view)
# ---------------------------------------------------------------------------

"""
    superpose!(x::QInt{W}) -> x

Apply `H^{⊗W}` in place (each wire through `_act!`, so it composes with `when`),
returning the same handle. On |0…0⟩ this is the uniform superposition
`2^{−W/2} Σ_k |k⟩` (which for the |0⟩ input coincides with `F|0⟩`). This is the
leading materialisation of DJ/BV and the state the Pontryagin modulation pin
starts from; it is the `(ℤ₂)^W` Fourier (per-wire), kept DISTINCT from the
register dual `dual(x)` (the ℤ_{2^W} QFT).
"""
function superpose!(x::QInt{W}) where {W}
    ctx = _here(x)
    @inbounds for w in x.wires
        _act!(ctx, H, (w,))
    end
    return x
end

# ---------------------------------------------------------------------------
# ACTION world — in-place, returns the same handle (the registered exception)
# ---------------------------------------------------------------------------

"""
    add!(x::QInt{W}, a::Integer) -> x

In-place translation `x ↦ x + a (mod 2^W)` — the Draper adder `F† ∘ D_{+a} ∘ F`
(intertwiner (I)). `F`/`F†` are UNCONTROLLED basis changes (`apply!`); the
per-wire modulation `D_{+a}` (wire j gets `P(2π a / 2^j)`) routes through `_act!`,
so `when(c) do add!(x,a) end` streams as `ctrl(T_a)` (reassociation, file header).
Overflow WRAPS (ℤ_{2^W} is the group). Returns the same handle (D12 in-place).
"""
function add!(x::QInt{W}, a::Integer) where {W}
    ctx = _here(x)
    _shift_width_guard(W, "add!")                             # ctw2/F23: no silent `1<<W` wrap
    a = mod(a, 1 << W)
    F = QFT(W, false)
    apply!(ctx, F, x.wires)                                   # F — uncontrolled
    @inbounds for j in 1:W
        _act!(ctx, P(2π * a / (1 << j)), (x.wires[j],))       # D_{+a} — the ctrl-carrying part
    end
    apply!(ctx, adjoint(F), x.wires)                          # F† — uncontrolled
    return x
end

"""
    sub!(x::QInt{W}, a::Integer) -> x

In-place `x ↦ x − a (mod 2^W)` = `add!(x, −a)` (the action-world inverse).
"""
sub!(x::QInt{W}, a::Integer) where {W} = add!(x, -a)

"""
    add!(y::QInt{W}, x::QInt{W}) -> y

In-place QUANTUM-addend translation `|x⟩|y⟩ ↦ |x⟩|y + x (mod 2^W)⟩` — Draper with
a quantum increment: `F` on `y`, then the triangular cross-register phase network
`ctrl(P(2π·2^{W−k−j}))` (control = `x`'s wire k, target = `y`'s Fourier wire j),
then `F†` on `y`. The phase is trivial (a multiple of 2π) unless `k + j > W`. `x`
is read control-like (stays live); `y` is mutated. Returns `y`. Distinct
registers required (§8.4).
"""
function add!(y::QInt{W}, x::QInt{W}) where {W}
    ctx = _here(y); _here(x)
    F = QFT(W, false)
    apply!(ctx, F, y.wires)
    @inbounds for k in 1:W, j in 1:W
        e = W - k - j
        e ≥ 0 && continue                                    # phase ≡ 1 (multiple of 2π)
        _act!(ctx, ctrl(P(2π * 2.0^e)), (x.wires[k], y.wires[j]))
    end
    apply!(ctx, adjoint(F), y.wires)
    return y
end

"""
    xor(x::QInt{W}, y::QInt{W}) -> x       # `x ⊻= y`

Transversal `(ℤ₂)^W` translation: W parallel `ctrl(X)` (control = `y`'s wire,
target = `x`'s wire), `x ↦ x ⊻ y` bitwise. This is the per-wire group `(ℤ₂)^W`,
NOT ring addition on ℤ_{2^W} (`add!`) — deliberately the world of the per-wire
duals. Returns `x`. `x ⊻= x` fires the §8.4 aliasing check (shared `WireID`).
"""
function Base.xor(x::QInt{W}, y::QInt{W}) where {W}
    ctx = _here(x); _here(y)
    @inbounds for j in 1:W
        _act!(ctx, ctrl(X), (y.wires[j], x.wires[j]))        # (control, target) = (y_j, x_j)
    end
    return x
end

"""
    xor(x::QInt{W}, n::Integer) -> x       # `x ⊻= n`

Mixed form (P8/D12): flip the set bits of the classical `n` with the EXACT kernel
`X` (never `Ry(π)`). Returns `x`.
"""
function Base.xor(x::QInt{W}, n::Integer) where {W}
    ctx = _here(x)
    @inbounds for j in 1:W
        ((n >> (W - j)) & 1) == 1 && _act!(ctx, X, (x.wires[j],))
    end
    return x
end

# ---------------------------------------------------------------------------
# MODULATION world — bound dual view, in-place, returns the view (Ĝ-kick)
# ---------------------------------------------------------------------------

"""
    +(v::DualView{<:QInt{W}}, a::Integer) -> v      # `x̂ += a`

The Pontryagin modulation: `x̂ += a` (`x̂ = dual(x)`) kicks the DUAL label by `a`,
which on `x` is the modulation `D_{-a}` (intertwiner (II)) — emitted DIRECTLY as
bare per-wire phases `P(-2π a / 2^j)` (NO Fourier sandwich; that is the r6/B2
distinction from `add!`). Mutates in place and RETURNS THE VIEW (Julia rewrites
`x̂ += a` to `x̂ = x̂ + a`, so returning `v` makes the rebind a no-op — the
registered D11 exception). Leaves `Int(x)` unchanged (a global phase on a basis
state); shifts `Int(dual(x))` by `+a` (the sign pin).
"""
function Base.:+(v::DualView{<:QInt{W}}, a::Integer) where {W}
    x = v.parent
    ctx = _here(x)
    _shift_width_guard(W, "x̂ += a (dual-view modulation)")    # ctw2/F23: no silent `1<<W` wrap
    a = mod(a, 1 << W)
    @inbounds for j in 1:W
        _act!(ctx, P(-2π * a / (1 << j)), (x.wires[j],))      # D_{-a}: NEGATIVE angle (intertwiner II)
    end
    return v
end

Base.:-(v::DualView{<:QInt{W}}, a::Integer) where {W} = v + (-a)

# ---------------------------------------------------------------------------
# VALUE world — fresh output, inputs stay live (P9 ring ops)
# ---------------------------------------------------------------------------

"""
    _fresh_copy(x::QInt{W}) -> QInt{W}

A fresh `|0⟩^W` register reversibly loaded with `x`'s value via the transversal
CNOT (`s ⊻= x`: `|x⟩|0⟩ ↦ |x⟩|x⟩`, entangled — NOT a clone; no-cloning forbids
copying a superposed `x`). `x` stays live and recoverable. The value-world adders
build on this so the input remains a valid register (reversible dataflow, P9).
"""
function _fresh_copy(x::QInt{W,C}) where {W,C}
    ctx = contextof(x)            # the caller already validated x via `_here`; reuse its typed ctx
    s = QInt{W}(ctx, 0)           # fresh |0⟩^W via the KNOWN ctx (no ScopedValue reread; F16)
    xor(s, x)                     # s ⊻= x: transversal load (s starts |0⟩)
    return s
end

_maybe_record!(ctx, s::QInt{W}, sources::QInt{W}...) where {W} = begin
    _core(ctx).strict || return nothing
    @inbounds for j in 1:W, src in sources
        _record_parent!(ctx, s.wires[j], src.wires[j])
    end
    nothing
end

"""
    +(x::QInt{W}, a::Integer) -> QInt{W}      # value world: fresh sum, `x` stays live

`s = x + a` allocates a FRESH register holding `x + a` and leaves `x` LIVE (both
independently measurable — reversible dataflow, P9). Because `x` stays live, a
bare `x += a` (which lowers to `x = x + a`) rebinds `x` to `s` and DROPS the
original — the lost-binding trap (strict detector). Use `add!(x, a)` for in-place.
"""
function Base.:+(x::QInt{W}, a::Integer) where {W}
    ctx = _here(x)
    s = _fresh_copy(x)
    add!(s, a)
    _maybe_record!(ctx, s, x)
    return s
end

Base.:+(a::Integer, x::QInt{W}) where {W} = x + a
Base.:-(x::QInt{W}, a::Integer) where {W} = x + (-a)

"""
    +(x::QInt{W}, y::QInt{W}) -> QInt{W}      # value world: fresh sum, inputs live

`s = x + y` = a fresh register loaded with `x` then quantum-incremented by `y`
(`s ⊻= x; add!(s, y)`), `|x⟩|y⟩` staying live. Fresh output (P9); the strict
detector records both `x` and `y` as `s`'s entangling parents.
"""
function Base.:+(x::QInt{W}, y::QInt{W}) where {W}
    ctx = _here(x); _here(y)
    s = _fresh_copy(x)
    add!(s, y)
    _maybe_record!(ctx, s, x, y)
    return s
end

# ---------------------------------------------------------------------------
# Misuse topology — every wrong program to a loud, identity-bearing error (S13)
# ---------------------------------------------------------------------------

"`x ⊻= x[i]` — a whole register with one of its own slices (width + aliasing)."
Base.xor(x::QInt{W}, r::WireRef) where {W} = throw(ArgumentError(
    "x ⊻= x[$(r.idx)] is undefined: cannot ⊻ a whole QInt{$W} with a single-wire " *
    "slice of it (width mismatch, and it would alias). Did you mean `x[i] ⊻= r` " *
    "(a slice action) or `x ⊻= y` (a same-width register)?"))

"`x::QInt{W} ⊻= y::QInt{V}` with V ≠ W — the transversal ⊻ needs equal width."
Base.xor(x::QInt{W}, y::QInt{V}) where {W,V} = throw(ArgumentError(
    "width mismatch: QInt{$W} ⊻ QInt{$V}; the transversal `⊻` is per-wire and needs " *
    "equal width. Widen/narrow one register first."))
