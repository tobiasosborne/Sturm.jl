# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M12 phase 1 (bead Sturm.jl-elsf):
# the `evolve!` strategy descriptors (proposal B §1.1; synthesis S2/S11).
# A strategy object is a REQUEST; the plan (plans.jl) is the CONTRACT.
# Constructors validate EAGERLY — every violation is a `DomainError` at
# construction time, not an `evolve!`-time surprise. `ε` is NOT a strategy
# field (S2): the tolerance is a property of the CALL (`evolve!` kwarg), the
# strategy a property of the METHOD — `Trotter(order = 4)` is reusable across
# accuracies.
#
# QDrift/Composite carry randomized-execution parameters; their PLANNING is
# M12 phase 2 (bead Sturm.jl-8yzf) — the structs, validation and vocabulary
# ship now so the surface is stable, and planning fails LOUD (plans.jl).

"""
    EvolveAlg

Supertype of `evolve!` strategy descriptors (PRD-v2 §5 library values).
Concrete: [`Trotter`](@ref), [`QDrift`](@ref), [`Composite`](@ref),
[`Auto`](@ref) — all exported; the machinery behind them is `public`.
"""
abstract type EvolveAlg end

_check_steps_field(v::Nothing, name::String) = nothing
function _check_steps_field(v::Integer, name::String)
    v ≥ 1 || throw(DomainError(v, "evolve!: $name must be ≥ 1 (got $v)."))
    return Int(v)
end

"""
    Trotter(; order = 2, steps = nothing)

The deterministic Suzuki product formula: `order ∈ {1} ∪ {2, 4, …, 12}` (1 =
Lie–Trotter, 2p = Suzuki; order 12 is the loud cap, S11 —
docs/physics/suzuki_1991_fractal_decomposition.md eqs 3.14–3.16;
docs/physics/childs_2019_trotter_error.md). `steps` is the explicit repetition
count `r`; `steps = nothing` derives `r` from the `evolve!` tolerance
`ε` (full diamond norm) via `trotter_steps` — with NO default accuracy: a
free-`steps` `Trotter` without `ε=` is a loud `ArgumentError` (S3 as ruled).
"""
struct Trotter <: EvolveAlg
    order::Int
    steps::Union{Int,Nothing}
    function Trotter(; order::Integer = 2, steps::Union{Integer,Nothing} = nothing)
        return new(_check_order(order), _check_steps_field(steps, "steps"))
    end
end

"""
    QDrift(; N = nothing, rng = nothing)

Campbell's qDRIFT randomized compiler (docs/physics/campbell_2019_qdrift.md,
Thm 1): `N` i.i.d. samples `j ∼ |a_j|/λ`, each applying
`exp(−i·sign(a_j)·(λt/N)·P_j)`. `N = nothing` derives the sample count from
`ε` (the exact transcendental criterion, S4). `rng = nothing` draws from the
context RNG (`shots`-friendly); an explicit RNG pins the sampled trajectory.

M12 phase 1 ships the descriptor only — PLANNING/EXECUTION is phase 2 (bead
Sturm.jl-8yzf) and currently fails loud.
"""
struct QDrift <: EvolveAlg
    N::Union{Int,Nothing}
    rng::Any                       # untyped: Random stays out of src/ deps (context-core precedent)
    function QDrift(; N::Union{Integer,Nothing} = nothing, rng = nothing)
        return new(_check_steps_field(N, "N"), rng)
    end
end

"""
    Composite(; order = 2, K = nothing, N_B = nothing, steps = nothing, rng = nothing)

The Hagan–Wiebe composite channel (docs/physics/hagan_wiebe_2023_composite.md,
Def 5.1 / Thm 2.1): an order-`2p` Suzuki HEAD over the `K` largest-|a| terms
interleaved with fresh-sampled qDrift batches (`N_B` samples per B-slot) over
the tail, `steps` outer iterations. Every `nothing` is derived from `ε` and
the prefix tables (optimal-K, docs/physics/zlokapa_2026_hamsim_lower_bounds.md
Lemma 7). `K = 0`/`K = L` normalize to pure QDrift/Trotter plans.

M12 phase 1 ships the descriptor only — PLANNING/EXECUTION is phase 2 (bead
Sturm.jl-8yzf) and currently fails loud.
"""
struct Composite <: EvolveAlg
    order::Int
    K::Union{Int,Nothing}
    N_B::Union{Int,Nothing}
    steps::Union{Int,Nothing}
    rng::Any
    function Composite(; order::Integer = 2, K::Union{Integer,Nothing} = nothing,
                       N_B::Union{Integer,Nothing} = nothing,
                       steps::Union{Integer,Nothing} = nothing, rng = nothing)
        (iseven(order) && 2 ≤ order ≤ 2 * SUZUKI_MAX_P) || throw(DomainError(order,
            "Composite: the outer Suzuki order must be an even 2 ≤ order ≤ " *
            "$(2 * SUZUKI_MAX_P) (docs/physics/hagan_wiebe_2023_composite.md, " *
            "Def 5.1)."))
        (K === nothing || K ≥ 0) || throw(DomainError(K,
            "Composite: the head size K must be ≥ 0 (K = 0 is pure qDrift, " *
            "K = L pure Trotter)."))
        return new(Int(order), K === nothing ? nothing : Int(K),
                   _check_steps_field(N_B, "N_B"),
                   _check_steps_field(steps, "steps"), rng)
    end
end

"""
    Auto()

Strategy auto-dispatch: pick the proven-cost argmin among the candidate
strategies at the call's `ε` (which is REQUIRED — a bare `evolve!` with
neither `ε=` nor explicit resources is a loud `ArgumentError`, S3 as ruled).
Zero fields by design (S8/B §6): anything tunable belongs on the concrete
strategies; kwargs can be added later without breaking `Auto()`.

M12 phase 1 ships the descriptor only — the dispatch rule is phase 2 (bead
Sturm.jl-8yzf) and currently fails loud.
"""
struct Auto <: EvolveAlg end
