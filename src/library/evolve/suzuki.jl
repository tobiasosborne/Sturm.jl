# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M12 phase 1 (bead Sturm.jl-elsf):
# the Suzuki order-2p stage scales — the runtime γ-recursion (synthesis
# convergent core #4; proposal B §3), the loud order cap (S11), and the
# one-step sweep builder consumed by TrotterPlan (plans.jl).
#
# ── THE FRACTAL RECURSION (docs/physics/suzuki_1991_fractal_decomposition.md,
#    eqs 3.14–3.16) ─────────────────────────────────────────────────────────
#   S_{2p}(τ) = S_{2p−2}(u_p τ)² · S_{2p−2}((1−4u_p)τ) · S_{2p−2}(u_p τ)²,
#   u_p = 1/(4 − 4^{1/(2p−1)})    (eq 3.16; Suzuki's p_m — REAL, irrational),
# flattened to a vector of 5^{p−1} STRANG scale factors γ:
# S_{2p}(τ) = Πᵢ S₂(γᵢ τ). Coefficients are Float64 evaluations of the
# DEFINING recursion — never literals, never fitted. Suzuki's Theorem 3
# (nonexistence of positive decompositions, §V) proves some γᵢ MUST be
# negative for p ≥ 2: signed sub-steps are physics, do not "fix" them.

"""
    SUZUKI_MAX_P

The loud Suzuki order cap: p ≤ 6 (order 12, Υ = 2·5⁵ = 6250). Beyond it the
fractal coefficients are numerically and practically useless (the stage count
grows 5× per level while every |γᵢ| → 0, eq 3.19) — requests past the cap
`throw`, never clamp (S11).
"""
const SUZUKI_MAX_P = 6

# The generic-precision recursion (T = Float64 for planning, BigFloat for the
# transcription-typo twin test).
function _stage_scales(::Type{T}, p::Integer) where {T<:AbstractFloat}
    1 ≤ p ≤ SUZUKI_MAX_P || error(
        "suzuki_stage_scales: p = $p is outside 1 ≤ p ≤ $SUZUKI_MAX_P (order " *
        "$(2p) > $(2 * SUZUKI_MAX_P)) — the loud order cap (Υ = 2·5^{p−1} " *
        "stages; beyond order 12 the Suzuki coefficients are numerically " *
        "useless; docs/physics/suzuki_1991_fractal_decomposition.md).")
    γ = T[one(T)]
    for m in 2:p
        u = one(T) / (4 - T(4)^(one(T) / (2m - 1)))     # eq 3.16, evaluated
        γ = vcat(u .* γ, u .* γ, (1 - 4u) .* γ, u .* γ, u .* γ)   # eq 3.14
    end
    return γ
end

"""
    suzuki_stage_scales(p::Integer) -> Vector{Float64}
    suzuki_stage_scales(::Type{BigFloat}, p) -> Vector{BigFloat}

The `5^{p−1}` Strang scale factors of the order-`2p` Suzuki formula:
`S_{2p}(τ) = Πᵢ S₂(γᵢ τ)` (docs/physics/suzuki_1991_fractal_decomposition.md,
eqs 3.14–3.16; the same recursion Hagan–Wiebe restate as their
`def:higher_order_loop`, docs/physics/hagan_wiebe_2023_composite.md). `p = 1`
⇒ `[1.0]` (plain Strang). The sweep count is `Υ = 2·5^{p−1}` (two term-sweeps
per Strang factor).

Two loud invariants are asserted at every generation (they cost microseconds):
`|Σγ − 1| ≤ 64·eps·length` (first-order consistency) and EXACT palindromicity
(the recursion is structurally palindromic; the float evaluation preserves it
bit-for-bit because mirrored entries are identical subexpressions). The ORDER
itself is pinned by the 2^{2p} scaling-signature test (M12.SUZUKI.COEFFS),
immune to coefficient-magnitude conventions. The `BigFloat` method is the
arbitrary-precision twin the tests compare against (≤ 4 eps relative).
"""
function suzuki_stage_scales(p::Integer)
    γ = _stage_scales(Float64, p)
    abs(sum(γ) - 1) ≤ 64 * eps() * length(γ) || error(
        "suzuki_stage_scales(p = $p): Σγ = $(sum(γ)) drifted from 1 beyond " *
        "64·eps·length — a broken recursion (first-order consistency violated).")
    γ == reverse(γ) || error(
        "suzuki_stage_scales(p = $p): the scale vector is not exactly " *
        "palindromic — the recursion implementation broke its structural " *
        "symmetry (mirrored entries must be identical subexpressions).")
    return γ
end
suzuki_stage_scales(::Type{BigFloat}, p::Integer) = _stage_scales(BigFloat, p)

"""
    _check_order(order) -> Int

Validate an `evolve!` Trotter order: `1` (Lie–Trotter) or an even
`2 ≤ order ≤ 2·SUZUKI_MAX_P` (Suzuki 2p). Anything else — odd ≥ 3, 0,
past-the-cap — throws `DomainError` LOUDLY (fail fast; no clamp, no fallback).
"""
function _check_order(order::Integer)
    (order == 1 || (iseven(order) && 2 ≤ order ≤ 2 * SUZUKI_MAX_P)) ||
        throw(DomainError(order,
            "evolve!: Trotter order must be 1 or an even 2 ≤ order ≤ " *
            "$(2 * SUZUKI_MAX_P) (order $(2 * SUZUKI_MAX_P) = Suzuki p = " *
            "$SUZUKI_MAX_P, Υ = 6250, is the loud cap — " *
            "docs/physics/suzuki_1991_fractal_decomposition.md)."))
    return Int(order)
end

"Υ(order): sweep count — 1 for order 1, `2·5^{p−1}` for order 2p (HW's stage count)."
function suzuki_sweep_count(order::Integer)
    _check_order(order)
    return order == 1 ? 1 : 2 * 5^(order ÷ 2 - 1)
end

"""
    _build_sweep(hs::PauliSum{W}, order, τ) -> Vector{Tuple{Int,Float64}}

ONE Trotter step of duration `τ` as a materialized `(term index, θ)` schedule,
`θ` the FULL angle of `exp(−iθ P_j)` (coefficient and stage scale pre-folded):

- order 1: a single forward sweep, `θ_j = a_j·τ` (childs eq S1);
- order 2p: for each Suzuki scale γᵢ one STRANG factor — forward half-sweep
  then reverse half-sweep at `θ_j = a_j·γᵢτ/2` (childs eq S2 under `γᵢτ`;
  suzuki eqs 3.14–3.15). Order 2 is the p = 1 degenerate case (γ = [1.0]) —
  exactly M10's Strang loop, one code path.

Terms run in CANONICAL order (|a|-descending — every cited bound is
ordering-independent; reproducibility improves, see hamiltonian.jl / S12).
The identity term is NOT here: `c_I` is an exact per-plan `gphase`
(evolve.jl). Length = `Υ·L`, the papers' per-step exponential count.
"""
function _build_sweep(hs::PauliSum{W}, order::Integer, τ::Float64) where {W}
    _check_order(order)
    L = nterms(hs)
    sweep = Tuple{Int,Float64}[]
    if order == 1
        for j in 1:L
            push!(sweep, (j, hs.coeffs[j] * τ))
        end
        return sweep
    end
    for γ in suzuki_stage_scales(order ÷ 2)
        half = γ * τ / 2
        for j in 1:L
            push!(sweep, (j, hs.coeffs[j] * half))
        end
        for j in L:-1:1
            push!(sweep, (j, hs.coeffs[j] * half))
        end
    end
    return sweep
end

"""
    composite_outer_slots(order) -> Vector{Tuple{Symbol,Float64}}

One outer STEP of the Hagan–Wiebe composite channel as a slot list — the SAME
Suzuki recursion (eqs 3.14–3.16) applied to the two-element list [A, B]
instead of scalar stage scales (HW Def 5.1, docs/physics/
hagan_wiebe_2023_composite.md def:higher_order_loop). The second-order base
is the Strang sandwich `𝒰_A(τ/2)∘𝒰_B(τ/2)∘𝒰_B(τ/2)∘𝒰_A(τ/2)` — read as
APPLICATION order (left to right) `[(:A,½),(:B,½),(:B,½),(:A,½)]` — and the
order-2p list is the flattening through the SHARED `_stage_scales` γ vector:
`[(kind, γᵢ·s) for γᵢ in γ, (kind, s) in base]` (scales multiply; one code
path with the pure-Trotter recursion, synthesis convergent core #5).

Slot semantics: an `:A` slot replays one FULL inner order-2p Suzuki sweep of
the head at duration `scale·τ` (Υ·L_A exponentials — matched inner/outer
order, HW main.tex line 490); a `:B` slot draws `N_B` FRESH qDrift samples of
the tail at duration `scale·τ` (R2 — per-invocation N_B and fresh draws,
verified against Lemma lem:diamond_dist_higher_order's per-channel error
accounting and the `Υ(ΥL_A + N_B)` cost line). Negative scales (outer p ≥ 2)
are R3-covered: HW bound every slot via |1−4u_k| ≤ 1 ⇒ |t_i| ≤ t, and both
per-slot bounds are even in t_i — |dt| in error accounting, sign in angles.

Loud invariants at every generation (no truncation ANYWHERE — v0.1 lesson 3):
`Σ_A scale = Σ_B scale = 1` (within 64·eps·len), slot count `= 2Υ` with Υ of
each kind, EXACT palindromicity (mirrored entries are identical
subexpressions of the palindromic γ).
"""
function composite_outer_slots(order::Integer)
    (iseven(order) && 2 ≤ order ≤ 2 * SUZUKI_MAX_P) || throw(DomainError(order,
        "composite_outer_slots: the outer order must be an even 2 ≤ order ≤ " *
        "$(2 * SUZUKI_MAX_P) (docs/physics/hagan_wiebe_2023_composite.md, Def 5.1)."))
    γ = suzuki_stage_scales(order ÷ 2)              # asserts Σ=1 + palindrome
    base = ((:A, 0.5), (:B, 0.5), (:B, 0.5), (:A, 0.5))
    slots = Tuple{Symbol,Float64}[(kind, g * s) for g in γ for (kind, s) in base]
    Υ = suzuki_sweep_count(order)
    length(slots) == 2Υ || error(
        "composite_outer_slots(order = $order): $(length(slots)) slots ≠ 2Υ = " *
        "$(2Υ) — a broken recursion.")
    sA = sum(s for (k, s) in slots if k === :A; init = 0.0)
    sB = sum(s for (k, s) in slots if k === :B; init = 0.0)
    (abs(sA - 1) ≤ 64 * eps() * length(slots) && abs(sB - 1) ≤ 64 * eps() * length(slots)) ||
        error("composite_outer_slots(order = $order): Σ_A = $sA, Σ_B = $sB " *
              "drifted from 1 — first-order consistency violated.")
    slots == reverse(slots) || error(
        "composite_outer_slots(order = $order): the slot list is not exactly " *
        "palindromic — the recursion implementation broke its structural symmetry.")
    count(t -> t[1] === :A, slots) == Υ || error(
        "composite_outer_slots(order = $order): A-slot count ≠ Υ = $Υ.")
    return slots
end
