# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# bench/hamsim/groundtruth.jl — dense ground truth for the measured tier
# (bead Sturm.jl-gmx0). Adapted from the test-side harness
# (test/test_m12_random.jl §"dense superoperator tooling" and
# test/test_m10_library.jl helpers) — reimplemented here because the test
# files live inside runtests' Main-scope preamble; NOTHING here ships in src/.
#
# Doctrine (synthesis convergent core #7): deterministic plans are compared as
# dense unitaries of their OWN sweep schedules; randomized plans as EXACT
# enumerated ensemble superoperators (Φ_step = Σ_j p_j·Ad(U_j), powered /
# composed — zero sampling noise); the distance is the Choi trace-norm
# ‖J(Φ) − J(Ψ)‖₁ ≤ ‖Φ − Ψ‖_⋄ (a SOUND lower bound of the certified
# full-diamond ε — so a measured cost is if anything optimistic, and the
# certified/measured slack column is an upper bound on the true constant
# looseness). Pauli exponentials use P² = I: exp(−iθP) = cos θ·I − i sin θ·P —
# exact, no matrix exp.

using LinearAlgebra
using Random
using Sturm
using Sturm: PauliSum, PauliWord, nterms, letter_at, plan_evolution, trajectory,
             exp_count, TrotterPlan, QDriftPlan, CompositePlan,
             eager, statevector, _core, orkan_state_set!

const _PAULI1 = Dict(
    'I' => ComplexF64[1 0; 0 1], 'X' => ComplexF64[0 1; 1 0],
    'Y' => ComplexF64[0 -im; im 0], 'Z' => ComplexF64[1 0; 0 -1])

word_matrix(w::PauliWord{W}) where {W} =
    foldl(kron, (_PAULI1[letter_at(w, j)] for j in 1:W))

"Per-family cache: dense matrices of the canonical words, in canonical order."
family_wordmats(hs::PauliSum) = [word_matrix(w) for w in hs.words]

"exp(−iθP) for a Pauli word matrix P (P² = I): cos θ·I − i sin θ·P, exact."
pauli_exp_mat(P::AbstractMatrix, θ::Real) = cos(θ) * I - (im * sin(θ)) * P

"Dense H = Σ_j a_j·P_j from the canonical sum and its word-matrix cache."
ham_matrix(hs::PauliSum, wm) =
    sum(hs.coeffs[j] .* wm[j] for j in 1:nterms(hs))

"Eigen-factorization of H (Hermitian) — e^{−iHt} for every t on the grid."
exact_factor(Hm) = eigen(Hermitian(Matrix(Hm)))
u_exact(F, t::Real) = F.vectors * Diagonal(cis.(-t .* F.values)) * F.vectors'

# --- superoperator machinery (column-major vec convention; test-suite twin) --

"Superoperator of Ad_U: vec(UρU†) = (conj(U) ⊗ U)·vec(ρ)."
ad_super(U::AbstractMatrix) = kron(conj.(U), U)

"Normalized Choi state J(Φ) of the superoperator S on ℂ^d."
function super_to_choi(S::AbstractMatrix, d::Int)
    J = zeros(ComplexF64, d^2, d^2)
    E = zeros(ComplexF64, d, d)
    for i in 1:d, j in 1:d
        E .= 0; E[i, j] = 1
        J .+= kron(reshape(S * vec(E), d, d), E)
    end
    return J ./ d
end

trnorm(A::AbstractMatrix) = sum(svdvals(Matrix(A)))

"Choi-trace-norm distance of two superoperators — lower-bounds ‖·‖_⋄ (sound)."
choi_dist(S1, S2, d::Int) = trnorm(super_to_choi(S1, d) - super_to_choi(S2, d))

"Dense unitary of a materialized (term, θ) sweep, in APPLICATION order."
function sweep_unitary(sweep, wm)
    d = size(wm[1], 1)
    U = Matrix{ComplexF64}(I, d, d)
    for (j, θ) in sweep
        U = pauli_exp_mat(wm[j], θ) * U
    end
    return U
end

"One qDrift STEP superoperator Φ = Σ_j p_j·Ad(exp(−i·sign(a_j)·τ·P_j))."
function qdrift_step_super(hs::PauliSum, τ::Float64, wm)
    d = size(wm[1], 1)
    S = zeros(ComplexF64, d^2, d^2)
    for j in 1:nterms(hs)
        U = pauli_exp_mat(wm[j], flipsign(τ, hs.coeffs[j]))
        S .+= (abs(hs.coeffs[j]) / hs.λ) .* ad_super(U)
    end
    return S
end

"""
    composite_super(plan::CompositePlan, wm, d) -> Matrix

The EXACT ensemble superoperator of the composite channel: A-slots as dense
unitary Ad's of the scaled head sweep, B-slots as the N_B-th power of the
per-draw tail average (fresh draws per B-leaf ⇒ the slot channel IS Φ^{N_B} —
R2, hagan_wiebe Def 5.1), composed in the plan's own slot order, powered by
`steps`. The angle bookkeeping mirrors plans.jl `_composite_slot` exactly.
"""
function composite_super(plan::CompositePlan, wm, d::Int)
    hs = plan.ham
    τstep = plan.t / plan.steps
    S = Matrix{ComplexF64}(I, d^2, d^2)
    for (kind, scale) in plan.outer
        τ = scale * τstep
        if kind === :A
            U = Matrix{ComplexF64}(I, d, d)
            for (j, θu) in plan.head_sweep
                U = pauli_exp_mat(wm[j], θu * τ) * U
            end
            S = ad_super(U) * S
        else
            θmag = plan.λ_B * τ / plan.N_B
            Φ = zeros(ComplexF64, d^2, d^2)
            for j in (plan.K + 1):nterms(hs)
                Φ .+= (abs(hs.coeffs[j]) / plan.λ_B) .*
                      ad_super(pauli_exp_mat(wm[j], flipsign(θmag, hs.coeffs[j])))
            end
            S = Φ^plan.N_B * S
        end
    end
    return S^plan.steps
end

# --- the bench self-check (the one invariant keeping the report honest) ------

"Trajectory length WITHOUT materializing (QDrift N can be ~1e7+)."
traj_len(plan::TrotterPlan) = count(Returns(true), trajectory(plan))
traj_len(plan, rng) = count(Returns(true), trajectory(plan, rng))

"""
    selfcheck_plan(plan; seed = 0xbead) -> Bool

`exp_count(plan) == length(trajectory(plan[, rng]))` — the S1 no-hot-path
counting law, re-asserted bench-side on every executed configuration
(proposal B §8). Randomized plans iterate under a seeded RNG (any RNG gives
the same LENGTH; the seed is for reproducibility of the run log).
"""
function selfcheck_plan(plan; seed::Integer = 0xbead)
    n = plan isa TrotterPlan ? traj_len(plan) :
        traj_len(plan, MersenneTwister(seed))
    return n == exp_count(plan)
end

# --- the one Orkan integration cross-check per executed family ---------------

"Realize the unitary `op!(x)` implements on a W-wire register (test_m10 twin)."
function op_matrix(op!, W::Int; cap::Int = W + 1)
    N = 1 << W
    U = Matrix{ComplexF64}(undef, N, N)
    for jin in 0:(N - 1)
        eager(cap) do ctx
            x = QInt{W}(ctx, 0)
            core = _core(ctx)
            slots = [core.wire_to_slot[w] for w in x.wires]
            enc(v) = begin
                i = 0
                for j in 1:W
                    ((v >> (W - j)) & 1) == 1 && (i |= (1 << slots[j]))
                end
                i
            end
            st = core.state
            orkan_state_set!(st, 0, 0, zero(ComplexF64))
            orkan_state_set!(st, enc(jin), 0, one(ComplexF64))
            op!(x)
            sv = statevector(ctx)
            for jout in 0:(N - 1)
                U[jout + 1, jin + 1] = sv[enc(jout) + 1]
            end
            nothing
        end
    end
    return U
end

function dist_upto_phase(A, B)
    i = argmax(abs.(vec(B)))
    ph = A[i] / B[i]; ph /= abs(ph)
    return opnorm(A .- ph .* B)
end

"""
    orkan_replay_check(hs, W, wm; N = 24, seed = 0xbe57) -> Float64

ONE end-to-end pipe check per executed family (proposal A §9's "cross-check
executed ONCE"): a seeded qDrift trajectory replayed through the REAL
executor (eager/Orkan) against the dense product of the SAME sampled
sequence, up-to-phase (the top-level Ad path crosses the phase quotient at
application — §4.3; ordering bugs still shift the operator). Must be ≤ 1e-9.
"""
function orkan_replay_check(hs::PauliSum, W::Int, wm; N::Int = 24, seed::Integer = 0xbe57)
    plan = plan_evolution(QDrift(N = N), hs, 1.0)
    seq = collect(trajectory(plan, MersenneTwister(seed)))
    Ud = sweep_unitary(seq, wm)
    Ureal = op_matrix(W) do x
        evolve!(x, hs, 1.0; alg = QDrift(N = N, rng = MersenneTwister(seed)))
    end
    return dist_upto_phase(Ureal, Ud)
end
