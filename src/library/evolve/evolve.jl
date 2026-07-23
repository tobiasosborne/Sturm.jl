# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M12 phase 1 (bead Sturm.jl-elsf):
# the quantum EXECUTOR (a dumb fold of `_pauli_exp!` over a plan's
# trajectory) and the `evolve!` surface entry with the B §1.3 resolution
# rules under S3 AS RULED (the bare call errors; ε is an `evolve!` kwarg;
# the M10 `steps`/`order` sugar is preserved bit-for-bit for the calls M10
# accepted). Supersedes the M10 `src/library/evolve.jl`.
#
# LIBRARY code (PRD-v2 §5): `evolve!` is where generators live. It touches
# kernel process values (Rz, H, S, ctrl(X), gphase) — sanctioned for a
# library HOF — but there is NO surface spelling for angles; a user writes
# `evolve!(x, H, t; …)`, never a rotation.
#
# ── S9 AS RULED (guarded by R3, audited this session) ───────────────────────
# `_pauli_exp!` emits through `_act!` (surface/when.jl), the control-aware
# `apply!` sibling, so DETERMINISTIC `evolve!` is legal inside `when` — the
# streamed per-op `ctrl^k` lowering equals `ctrl^k` of the whole word
# exponential by the §4.2 homomorphism `ctrl(g∘h) = ctrl(g)∘ctrl(h)`. The R3
# audit: (a) `_pauli_exp!` allocates NO scratch (the CNOT-ladder parity
# target is a REGISTER wire), so the §3.9 clean-ancilla seal never sees
# evolve!-owned ancillas; (b) guardrail 2 fires on every emission if the
# evolved register overlaps the control; (c) the identity-word `gphase`
# becomes a genuine RELATIVE phase under a live frame (`ctrl(gphase)` is a
# real kernel op, kernel/constants.jl) — named test M12.CTRL.EVOLVE.

"""
    _pauli_exp!(ctx, x::QInt{W}, w::PauliWord{W}, θ::Real)

Apply `exp(−iθ·P)` (P = the Pauli word `w`) in place on `x`'s wires — the
standard N&C §4.7.3 lowering (docs/physics/childs_2019_trotter_error.md,
single-word exponential): rotate each non-`I` letter into the Z basis (`X`:
`H`; `Y`: `S†` then `H`), CNOT-ladder the active wires' parity onto the LAST
active wire, `Rz(2θ) = exp(−iθZ)` there (EXACT in Sturm's U(2) convention —
no phase-quotient slip), uncompute. A pure-identity word is the exact global
phase `gphase(−θ)`. All emissions go through `_act!` (S9): with an empty
control stack this IS `apply!`; under a live `when` frame every factor lowers
as `ctrl^k(·)` through the kernel choke point, and the `gphase` becomes the
correct relative phase.
"""
function _pauli_exp!(ctx::AbstractContext, x::QInt{W}, w::PauliWord{W}, θ::Real) where {W}
    if is_identity(w)
        _act!(ctx, gphase(-θ), (x.wires[1],))           # exp(−iθI) = e^{−iθ}, ctrl-visible
        return nothing
    end
    active = [j for j in 1:W if letter_at(w, j) != 'I']
    # 1. basis-change each active letter into Z (pre): X→H, Y→(S† then H)
    for j in active
        c = letter_at(w, j)
        if c == 'X'
            _act!(ctx, H, (x.wires[j],))
        elseif c == 'Y'
            _act!(ctx, adjoint(S), (x.wires[j],))
            _act!(ctx, H, (x.wires[j],))
        end                                             # 'Z': no basis change
    end
    # 2. CNOT ladder: fold the active wires' parity onto the last active wire
    tgt = last(active)
    for i in 1:(length(active) - 1)
        _act!(ctx, ctrl(X), (x.wires[active[i]], x.wires[active[i + 1]]))
    end
    # 3. the single Z-rotation on the parity wire — exp(−iθZ) = Rz(2θ), exact
    _act!(ctx, Rz(2θ), (x.wires[tgt],))
    # 4. uncompute the ladder (reverse order)
    for i in (length(active) - 1):-1:1
        _act!(ctx, ctrl(X), (x.wires[active[i]], x.wires[active[i + 1]]))
    end
    # 5. uncompute the basis changes (post = B†): X→H, Y→(H then S)
    for j in active
        c = letter_at(w, j)
        if c == 'X'
            _act!(ctx, H, (x.wires[j],))
        elseif c == 'Y'
            _act!(ctx, H, (x.wires[j],))
            _act!(ctx, S, (x.wires[j],))
        end
    end
    return nothing
end

"""
    _pauli_exp!(ctx, x::QInt{W}, term::PauliTerm, τ::Real)

The M10-compatible spelling: `exp(−i·term.coeff·P·τ)` — parses the word once
and delegates to the angle-resolved method with `θ = coeff·τ`.
"""
_pauli_exp!(ctx::AbstractContext, x::QInt{W}, term::PauliTerm, τ::Real) where {W} =
    _pauli_exp!(ctx, x, PauliWord{W}(term.word), term.coeff * τ)

"""
    _execute_plan!(ctx, x::QInt{W}, plan::TrotterPlan{W})

The dumb executor (synthesis convergent core #1): the identity-word phase
`gphase(−c_I·t)` ONCE per plan (exact — phases add; conditional under a live
ctrl frame), then a fold of `_pauli_exp!` over `trajectory(plan)`. No
counting, no branching, no arithmetic — everything was decided at plan time.
"""
function _execute_plan!(ctx::AbstractContext, x::QInt{W}, plan::TrotterPlan{W}) where {W}
    hs = plan.ham
    hs.c_I == 0 || _act!(ctx, gphase(-hs.c_I * plan.t), (x.wires[1],))
    for (j, θ) in trajectory(plan)
        _pauli_exp!(ctx, x, hs.words[j], θ)
    end
    return nothing
end

# --- Randomized execution (M12 phase 2, bead Sturm.jl-8yzf) ------------------

"""
    _assert_randomized_legal(ctx, what)

The two now-reachable guards of S10 + B §1.4, fired BEFORE any emission:

- **DM context** ⇒ `error()` naming M11: one sampled trajectory is one
  UNRAVELLING of the qDrift/composite channel; executing it on a density
  matrix would silently present a single branch as the CPTP average — the
  exact bug class Principle 1 kills. The DM lowering of the ensemble is
  M11's mixture value (KrausFamily/NoiseN, channel/dag.jl). The same
  argument bans TRACING (a recorded trajectory would materialize the wrong
  channel DAG) — guarded here too, same physics, distinct message.
- **live `when` frame** ⇒ loud error (the `_assert_no_control` shape): the
  qDrift guarantee is a CHANNEL statement, and ctrl of a mixture ≠ the
  mixture of ctrls — conditioning turns each branch's harmless global phase
  into a RELATIVE phase the mixing lemma never averages
  (docs/physics/campbell_2017_mixing_unitaries.md, the a² + 2b premise is
  unconditioned; docs/physics/hastings_2016_incoherent_errors.md).
  Deterministic strategies remain legal inside `when` (S9 as ruled).
"""
function _assert_randomized_legal(ctx::AbstractContext, what::AbstractString)
    ctx isa DensityMatrixContext && error(
        "evolve!($what): a randomized strategy samples ONE trajectory — one " *
        "unravelling of the qDrift/composite CHANNEL — and running it on a " *
        "density-matrix context would silently misrepresent the CPTP average " *
        "(S10). The DM lowering of the ensemble is M11's mixture value " *
        "(KrausFamily/NoiseN); until it lands, run randomized strategies under " *
        "`eager`/`shots`, or use a deterministic strategy (legal on DM).")
    ctx isa TracingContext && error(
        "evolve!($what): a randomized strategy samples ONE trajectory; tracing " *
        "it would materialize a single unravelling as if it were the channel " *
        "(the S10 bug class at the DAG level). The traced form of the ensemble " *
        "is M11's mixture value; trace a deterministic strategy instead.")
    isempty(_core(ctx).control_stack) || error(
        "evolve!($what) is forbidden under a live `when` frame: the qDrift " *
        "guarantee is a CHANNEL statement (a mixture of unitaries), and ctrl " *
        "of a mixture ≠ the mixture of ctrls — conditioning turns per-branch " *
        "global phases into relative phases the mixing lemma premises never " *
        "average (docs/physics/campbell_2017_mixing_unitaries.md; " *
        "docs/physics/hastings_2016_incoherent_errors.md). Deterministic " *
        "strategies remain legal inside `when` (S9).")
    return nothing
end

"""
    _plan_rng(plan, ctx)

RNG precedence (pinned by a named test): the strategy's explicit `rng` if
set, else the context core's rng (the SAME stream `shots`/`_draw` thread —
`nothing` means Julia's task-global stream, matching `_draw`'s convention in
context/abstract.jl).
"""
_plan_rng(plan, ctx::AbstractContext) = plan.rng !== nothing ? plan.rng : rng(ctx)

function _execute_plan!(ctx::AbstractContext, x::QInt{W}, plan::QDriftPlan{W}) where {W}
    _assert_randomized_legal(ctx, "QDrift")
    hs = plan.ham
    hs.c_I == 0 || _act!(ctx, gphase(-hs.c_I * plan.t), (x.wires[1],))
    for (j, θ) in trajectory(plan, _plan_rng(plan, ctx))
        _pauli_exp!(ctx, x, hs.words[j], θ)
    end
    return nothing
end

function _execute_plan!(ctx::AbstractContext, x::QInt{W}, plan::CompositePlan{W}) where {W}
    _assert_randomized_legal(ctx, "Composite")
    hs = plan.ham
    hs.c_I == 0 || _act!(ctx, gphase(-hs.c_I * plan.t), (x.wires[1],))
    for (j, θ) in trajectory(plan, _plan_rng(plan, ctx))
        _pauli_exp!(ctx, x, hs.words[j], θ)
    end
    return nothing
end

"""
    evolve!(x::QInt{W}, H, t::Real;
            alg = nothing, ε = nothing, steps = nothing, order = nothing) -> x

Simulate `e^{−iHt}` in place on the register `x`, returning the same handle
(in-place, D12). `H` is a sum of weighted Pauli words: any iterable of
`(coefficient::Real, word::AbstractString)` pairs (or `PauliTerm`s / a
`PauliSum{W}`), each word a length-`W` string over `"IXYZ"` (char 1 = wire 1
= MSB). Terms execute in CANONICAL |coeff|-descending order (duplicates
merged — exactly equal, `e^{−iaP}e^{−ibP} = e^{−i(a+b)P}`; S12 changelog).

Strategy selection (`alg`, exported vocabulary): `Trotter(order=…, steps=…)`
(deterministic Suzuki — docs/physics/suzuki_1991_fractal_decomposition.md,
docs/physics/childs_2019_trotter_error.md,
docs/physics/hagan_wiebe_2023_composite.md), `QDrift(N=…, rng=…)` (Campbell's
randomized compiler — docs/physics/campbell_2019_qdrift.md), `Composite(…)`
(the Hagan–Wiebe head/tail interleave — docs/physics/hagan_wiebe_2023_composite.md),
`Auto()` (the proven-cost argmin over the candidate set — auto.jl,
docs/physics/zlokapa_2026_hamsim_lower_bounds.md). `ε` is the target accuracy
in the FULL diamond norm (S5), used to derive whatever resources the strategy
left free. Resolution rules (every violation throws):

1. `steps`/`order` kwargs with no `alg` are the M10 sugar for
   `Trotter(order = something(order, 2), steps = …)` — same circuit as M10,
   bit for bit, for every call M10 accepted (`steps` defaults to 1 only when
   no `ε` is given; with `ε`, free `steps` are derived from it).
2. Kwargs alongside `alg` are over-specified ⇒ `ArgumentError` (one spelling
   per meaning: put the parameters inside the strategy).
3. Neither ⇒ `alg = Auto()`, and
4. any free plan parameter REQUIRES `ε` — **the bare call
   `evolve!(x, H, t)` errors** (S3 as ruled: no default accuracy anywhere).
5. `ε` alongside fully-explicit resources ⇒ `ArgumentError` (a tolerance
   that cannot influence anything is a caller bug).
6. `t == 0` is an exact no-op; `t < 0` is legal everywhere (bounds use
   `|t|`; angles carry the sign).

Deterministic strategies are legal inside `when` (S9): the whole evolution
lowers `ctrl^k` through the kernel choke point — QPE on `e^{−iHt}` composes.

Randomized strategies (`QDrift`/`Composite`, and `Auto` when it picks one)
execute ONE sampled trajectory per call — the `shots` HOF owns the shot loop;
the ε guarantee is a property of the shot-averaged CHANNEL, a single
trajectory is only ~√ε-close (campbell_2019_qdrift.md "Diamond norm
distance"; docs/physics/chen_2021_concentration_random_products.md). They are
loud errors on a DM/Tracing context (S10 — the ensemble's lowering is M11's
mixture value) and under a live `when` frame (ctrl of a mixture ≠ mixture of
ctrls). RNG: the strategy's `rng` if set, else the context core's rng (the
`shots` stream), else Julia's global stream — precedence pinned by a test.

```julia
# evolve a 2-qubit register under H = Z⊗Z + ½ X⊗I for time t, second order
x = QInt{2}(0)
evolve!(x, [(1.0, "ZZ"), (0.5, "XI")], 1.0; steps = 40)
# derive the step count from a target accuracy instead (full diamond norm)
evolve!(x, [(1.0, "ZZ"), (0.5, "XI")], 1.0; alg = Trotter(order = 4), ε = 1e-6)
```
"""
function evolve!(x::QInt{W}, H, t::Real;
                 alg::Union{EvolveAlg,Nothing} = nothing,
                 ε::Union{Real,Nothing} = nothing,
                 steps::Union{Integer,Nothing} = nothing,
                 order::Union{Integer,Nothing} = nothing) where {W}
    # -- rule 1/2: the M10 sugar vs an explicit strategy -----------------
    if steps !== nothing || order !== nothing
        alg === nothing || throw(ArgumentError(
            "evolve!: pass the parameters inside the strategy — " *
            "`Trotter(order = …, steps = …)` — not alongside `alg = …` " *
            "(one spelling per meaning)."))
        alg = Trotter(order = something(order, 2),
                      steps = (steps === nothing && ε !== nothing) ?
                              nothing : something(steps, 1))
    elseif alg === nothing
        alg = Auto()                                    # rule 3
    end
    # -- ε domain (rule 6 of B §1.3) -------------------------------------
    ε === nothing || (isfinite(ε) && ε > 0) || throw(DomainError(ε,
        "evolve!: ε must be a finite positive accuracy (FULL diamond norm, S5)."))
    # -- rules 4/5 for the shapes phase 1 executes (defense in depth: the
    #    planner re-checks; Auto must fail on the MISSING ε before its
    #    phase-2 stub so the bare call reads as the S3 ruling) ------------
    if alg isa Auto && ε === nothing
        throw(ArgumentError(
            "evolve!: give a target accuracy ε=… or explicit resources " *
            "(steps=…/N=…) — there is no default accuracy (S3)."))
    end
    hs = PauliSum{W}(H)                                 # loud on malformed H
    t == 0 && return x                                  # exact no-op (rule 7)
    ctx = _here(x)
    plan = plan_evolution(alg, hs, Float64(t); ε = ε)   # pure; fills every free resource
    _execute_plan!(ctx, x, plan)
    return x
end
