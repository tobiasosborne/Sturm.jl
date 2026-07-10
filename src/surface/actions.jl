# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M4 (bead Sturm.jl-3nld): the ACTION
# FAMILY (surface construct 3) and measurement THROUGH a view. One P7-parametric
# family — the register's group acting on itself and its dual (PRD-v2 §3.4/D12):
# `not!` (ℤ₂ translation by 1), `a ⊻= b` (translation in (ℤ₂)^W by a register),
# the bound-view forms (`not!(dual(q))` ↦ Z modulation; `q̂ ⊻= r` ↦ CZ), and the
# P8 mixed forms (`q ⊻= true`, `false ⊻ b`). All are BIJECTIONS of the register —
# that is *why* they may mutate in place (Julia conv 2, the registered exception,
# adopted knowing julialang #249/#3217: no-cloning means there is no caller value
# to clobber, and the exception is scoped to the bijective action family, never
# ring ops).
#
# THE RETURN-VALUE DISCIPLINE IS THE WHOLE GAME. `a ⊻= b` lowers to
# `a = xor(a, b)`; for the rebind to be a physical in-place op (not a rebind-of-a-
# copy) every action-family `xor` method RETURNS ITS MUTATED FIRST HANDLE, so the
# assignment `a = a` is a true no-op. Fresh-output forms (`c = false ⊻ b`) are a
# plain `=`, so they may — and must — return a FRESH handle (value world, §3.4).
#
# ZERO M1/M2/M3 KERNEL EDITS: a view is never an `apply!` argument. Each method
# resolves to a concrete ProcessValue (the exact kernel `X`; a conjugated `Z`; a
# `ctrl(X)`/`ctrl(Z)`) on parent `WireID`s and calls the ALREADY-landed `apply!`,
# inheriting its aliasing check (§8.4), liveness guard, and fusion/flush
# discipline (M2). The dual forms lower by `_conj` (views.jl): `not!(dual(q))`
# emits one fused `U2 ≈ Z`; `q̂ ⊻= r` emits `ctrl(_conj(H,X)) = ctrl(Z)`, which
# hits `ad.jl`'s native `u ≈ Z → cz` fast path — one `orkan_cz`.
#
# Physics/spec grounding: PRD-v2 §3.3 (dual, conjugation), §3.4/D12 (action
# family, two-world registry, mixed forms), §7.1 (teleportation usage — the
# xor direction pins), §7.3 (CZ symmetry theorem). Normative fix carried in
# (§3.4 / audit 8.3): the mixed `xor(::QBool, ::Bool)` lowers to the kernel's
# EXACT X, never `Ry(π)` (the v0.1 latent-phase bug). Distillation:
# docs/physics/wharton_koch_quaternion_bloch.md (X, Z exact; HXH = Z).

"""
    _here(q::QBool) -> AbstractContext

Assert `q`'s owning context IS the active one and return it (fail-loud). WireIDs
are per-context (`WireID(1)` exists in every context), so an escaped handle used
under a different bound context would otherwise silently target the WRONG physical
qubit — the exact bug `QBool` stores its `ctx` to catch (qbool.jl header; the same
guard `Bool(q)` runs). ArgumentError (well-formed-but-forbidden, S13).
"""
@inline function _here(q::AbstractQubit)
    q.ctx === current_context() || throw(ArgumentError(
        "action on register $(q.wire): the handle belongs to a different context " *
        "than the active one — a handle escaped its context/region. WireIDs are " *
        "per-context, so an id collision across contexts would otherwise silently " *
        "target the wrong physical qubit."))
    return q.ctx
end

# --- Flips: ℤ₂ translation (X) and its Ĝ-dual modulation (Z) -------------

"""
    not!(q::QBool) -> q

The ℤ₂ translation by 1 (surface construct 3): flip `q` in place via the kernel's
EXACT `X` (U(2), not `Ry(π)`; §4.1), returning the same handle. `not!` is now
*derivable* (X is exact) but kept as the idiomatic flip; its v0.1 constitutional
specialness dissolves into the action family (§3.4). No-cloning forbids `q = !q`,
which is why in-place mutation with a `!` name is the registered idiom.
"""
not!(q::AbstractQubit) = (_act!(_here(q), X, (q.wire,)); q)

"""
    not!(v::DualView) -> v

The ℤ₂ **modulation** — a phase flip Z, the Pontryagin dual of `not!` (§3.3): X
routed through the conjugate view lowers by `_conj(H, X) ≈ Z` (one fused `U2`).
Returns the same view. `not!(q)` ↦ X, `not!(dual(q))` ↦ Z is the self-dual ℤ₂
translation↔modulation pair.
"""
function not!(v::DualView)
    p = v.parent
    _act!(_here(p), _conj(_dual_transform(p), X), (p.wire,))
    return v
end

# --- Entanglement + mixed forms: the `Base.xor` (⊻) method table ---------
#
# | Surface            | Lowering                                   | Returns |
# |--------------------|--------------------------------------------|---------|
# | `a ⊻= b` (Q,Q)     | ctrl(X) — control = b (RHS), target = a     | a       |
# | `q ⊻= b` (Q,Bool)  | b ? exact X : no-op                          | q       |
# | `c = false ⊻ b`    | fresh |0⟩; (b?X); ctrl(X) control=b target=f | fresh   |
# | `q̂ ⊻= r` (Dual,Q)  | ctrl(_conj(H,X)) = ctrl(Z) — CZ             | q̂       |

"""
    xor(a::QBool, b::QBool) -> a       # `a ⊻= b`

CNOT with **target = LHS `a`, control = RHS `b`** (pinned from §7.1: `b ⊻= ψ`
correlates the payload `ψ` (control) with Alice's half `b` (target)). Entanglement
is COMPOSED, not a gate — there is no CNOT in the surface vocabulary. Returns `a`
(the in-place rebind no-op). Aliasing `a ⊻= a` fires `_check_wire_aliasing` on the
doubled `WireID` (§8.4).
"""
function Base.xor(a::AbstractQubit, b::AbstractQubit)
    ctx = _here(a); _here(b)
    _act!(ctx, ctrl(X), (b.wire, a.wire))   # (control, target) = (b, a)
    return a
end

"""
    xor(q::QBool, b::Bool) -> q        # `q ⊻= true` / `false`

Mixed form (P8/D12): a classical RHS flips `q` in place via the kernel's EXACT `X`
(never `Ry(π)` — the §3.4/audit-8.3 fix), or is a no-op for `false`. Returns `q`.
"""
Base.xor(q::AbstractQubit, b::Bool) = (b && _act!(_here(q), X, (q.wire,)); q)

"""
    xor(b::Bool, r::QBool) -> fresh QBool     # `c = false ⊻ b`

Classical-to-fresh promotion (the Bell-pair idiom, §7.1): allocate a FRESH |0⟩
(region-owned, §3.9), optionally flip it for `b == true`, then CNOT with
control = `r`, target = the fresh wire. This is a FRESH-OUTPUT (value-world) form
— a plain `=`, returning a NEW handle (`c !== r`); `r` stays live. With `r = |+⟩`
the result is the Bell pair Φ⁺ on `(r, c)`.
"""
function Base.xor(b::Bool, r::AbstractQubit)
    ctx = _here(r)
    f = QBool(false)                       # fresh |0⟩ in the active context
    b && apply!(ctx, X, (f.wire,))          # fresh-PREP: uncontrolled (§3.9 alloc)
    _act!(ctx, ctrl(X), (r.wire, f.wire))   # ENTANGLE: control-wrapped under a `when`
    return f
end

"""
    xor(v::DualView, r::QBool) -> v    # `q̂ ⊻= r`

CZ, the phase-entangler (§3.3/§7.3): an `X` routed through the target's conjugate
view lowers to `ctrl(_conj(H, X)) = ctrl(Z)` — the §4.2 reassociation
`(1⊗V)·ctrl(W)·(1⊗V†) = ctrl(V·W·V†)` with V = H on the target. Hits `ad.jl`'s
native `cz` fast path (one `orkan_cz`). CZ is symmetric by theorem, so
`q̂ ⊻= r ≡ r̂ ⊻= q` (a required Choi test, §7.3). Returns the same view. The
one-line `dual(q) ⊻= r` is NOT writable Julia (D11); bind first (`q̂ = dual(q)`).
"""
function Base.xor(v::DualView, r::QBool)
    p = v.parent
    ctx = _here(p); _here(r)
    _act!(ctx, ctrl(_conj(_dual_transform(p), X)), (r.wire, p.wire))  # ctrl(Z) = CZ
    return v
end

# --- Measurement through the dual view (conjugate-basis cast) ------------

"""
    Bool(v::DualView) -> Bool

The conjugate-basis MEASUREMENT cast (§3.3): rotate the dual basis into the
computational one (apply F_G = H to the parent, fusing as a `U2` — M2), then the
existing CONSUMING `Bool(parent)` (M3). The full conjugated instrument is
`V† ∘ M_Z ∘ V`; the trailing `V†` acts on an already-collapsed, retired wire, so
a consuming measurement legitimately omits it. The **|+⟩ ↦ false** labeling falls
out for free (H|+⟩ = |0⟩ → outcome 0 → false; F†P_kF, §7.1) — reversing it would
reproduce wm28 from the convention side (a Z-error channel invisible to
Z-marginals). Consumption / liveness / cross-context checks inherit via
`Bool(parent)`. On a DM context `Bool(parent)` throws (a scalar outcome is a
trajectory, §3.8) — the channel statement uses the Choi harness.
"""
function Base.Bool(v::DualView)
    p = v.parent
    ctx = _here(p)
    # Guardrail 1 (§3.5): conjugate-basis measurement under a live `when` control
    # is a loud error — checked at the TOP, before the H basis-change is emitted,
    # so no backaction precedes the throw.
    _assert_no_control(ctx, "conjugate-basis measurement cast Bool(dual(q))")
    apply!(ctx, _dual_transform(p), (p.wire,))   # basis change; fuses (M2)
    return Bool(p)                               # M3 consuming qc; consumes p
end
