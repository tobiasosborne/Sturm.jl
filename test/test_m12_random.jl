# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# Sturm.jl M12 phases 2+3 (beads Sturm.jl-8yzf / Sturm.jl-ze22): the
# RANDOMIZED strategies (QDrift, Composite, Auto) and their channel-level
# verification harness. Design: docs/design/m12-synthesis.md (S4/S7/S8/S10 as
# ruled; R2/R3 closed against docs/literature/2206.06409_src/main.tex —
# per-invocation N_B + fresh draws per B-slot; |dt| accounting covers the
# negative outer-p ≥ 2 scales).
#
# VERIFICATION DOCTRINE (v0.1 lessons; synthesis convergent core #7): the
# ensemble averages are EXACT ENUMERATED SUPEROPERATORS (dense Φ_step = Σ_j
# p_j·Ad(U_j), powered/composed — no sampling noise), compared at the Choi
# level (‖J(Φ) − J(Ψ)‖₁ ≤ ‖Φ − Ψ‖_⋄, a sound necessary condition of the
# cited FULL-diamond bounds, all untuned); individual trajectories are pinned
# by seeded replay against dense products of the SAME sampled sequence.
# Statistics (χ², shots-level means) are supplements; H1 is HEAVY-gated
# (ENV["STURM_TEST_HEAVY"] == "1").
#
# All dense/superoperator helpers are TEST-SIDE only (nothing ships in src/).
# Reuses the Main-scope M10/M12 harness (op_matrix, word_mat, ham_mat,
# dist_upto_phase) from test_m10_library.jl, included earlier by runtests.jl.

using Test
using Sturm
using LinearAlgebra
using Random
using Sturm: eager, density, statevector, _core, orkan_state_set!,
             PauliSum, PauliWord, nterms, iscommuting,
             plan_evolution, trajectory, exp_count,
             TrotterPlan, QDriftPlan, CompositePlan,
             qdrift_samples, qdrift_error_bound,
             composite_steps, composite_error_bound, composite_nb, composite_k,
             composite_outer_slots, suzuki_sweep_count,
             evolve_plan, EvolveChoice, PlanRow, BoundReport,
             ising_chain, heisenberg_chain, powerlaw_chain, trace,
             alpha_comm, alpha_comm_pairs, alpha_comm_cross, trotter_steps,
             alpha_comm_layered, alpha_comm_cross_layered, AlphaLayered,
             ALPHA_WORK_DEFAULT

# Tiny stats helpers (Statistics is not a test dep — Test-only extras policy).
_mean(v) = sum(v) / length(v)
_stderr(v) = sqrt(sum(abs2, v .- _mean(v)) / (length(v) - 1)) / sqrt(length(v))
_quantile(v, q) = sort(v)[clamp(ceil(Int, q * length(v)), 1, length(v))]

# --- Test-side dense superoperator tooling (column-major vec convention) -----

"Superoperator of the unitary channel Ad_U: vec(UρU†) = (conj(U) ⊗ U)·vec(ρ)."
ad_super(U::AbstractMatrix) = kron(conj.(U), U)

"Normalized Choi state J(Φ) = (Φ ⊗ id)(|Ω⟩⟨Ω|) of the superoperator S on ℂ^d."
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
choi_dist(S1, S2, d) = trnorm(super_to_choi(S1, d) - super_to_choi(S2, d))

"One qDrift STEP superoperator Φ = Σ_j p_j·Ad(exp(−i·sign(a_j)·τ·P_j))."
function qdrift_step_super(hs::PauliSum{W}, τ::Float64) where {W}
    d = 1 << W
    S = zeros(ComplexF64, d^2, d^2)
    for j in 1:nterms(hs)
        U = exp(-im .* flipsign(τ, hs.coeffs[j]) .* word_mat(String(hs.words[j])))
        S .+= (abs(hs.coeffs[j]) / hs.λ) .* ad_super(U)
    end
    return S
end

"Dense unitary of a materialized (term, θ) sweep, in APPLICATION order."
function sweep_unitary(hs::PauliSum{W}, sweep) where {W}
    d = 1 << W
    U = Matrix{ComplexF64}(I, d, d)
    for (j, θ) in sweep
        U = exp(-im .* θ .* word_mat(String(hs.words[j]))) * U
    end
    return U
end

@testset "M12 — Hamiltonian simulation, phases 2+3 (randomized strategies)" begin

    # =====================================================================
    #  qdrift_samples — the S4 exact transcendental criterion
    # =====================================================================
    @testset "M12.QDRIFT.SAMPLES — exact criterion: minimality, sandwich, ratio → 1" begin
        f(N, λ, T) = 2N * (expm1(2λ * T / N) - 2λ * T / N)   # the S4 value
        for (λ, T, ε) in ((1.75, 1.0, 1e-2), (0.8, 3.0, 1e-3), (2.5, 0.4, 1e-4))
            rep = qdrift_samples(λ, T, ε)
            N = Int(rep.value)
            @test rep.formula === :campbell_exact_N
            # minimality: N meets the criterion, N − 1 does not (least such N)
            @test f(N, λ, T) ≤ ε
            N > 1 && @test f(N - 1, λ, T) > ε
            @test rep.inputs.bound ≈ f(N, λ, T)
            # THE SANDWICH (deviation from proposal A's flipped inequality —
            # e^x − 1 − x > x²/2 STRICTLY, so the exact criterion demands MORE
            # than the naive asymptote, by ≈ 2λT/3; verified analytically and
            # numerically, see bounds.jl section header):
            @test ceil(Int, 4λ^2 * T^2 / ε) ≤ N
            @test N ≤ ceil(Int, 4λ^2 * T^2 / ε) + ceil(Int, 2λ * T / 3) + 2
            # ratio → 1 against the asymptote
            @test N / (4λ^2 * T^2 / ε) ≈ 1 atol = 0.01
        end
        # strict monotone decrease of the criterion in N (the bisection license)
        @test all(f(N, 1.3, 2.0) > f(N + 1, 1.3, 2.0) for N in 1:50)
        # |t| symmetry and degenerate λ = 0
        @test qdrift_samples(1.0, -2.0, 1e-2).value == qdrift_samples(1.0, 2.0, 1e-2).value
        @test qdrift_samples(0.0, 5.0, 1e-6).value == 1.0
        @test_throws DomainError qdrift_samples(1.0, 1.0, 0.0)
        @test_throws DomainError qdrift_samples(1.0, 1.0, -1e-3)
        # inverse direction agrees with the criterion value
        @test qdrift_error_bound(1.75, 1.0, 100).value ≈ f(100, 1.75, 1.0)
    end

    # =====================================================================
    #  T5 — M12.QDRIFT.CHANNEL (exact ensemble superoperator, no sampling)
    # =====================================================================
    @testset "M12.QDRIFT.CHANNEL — Choi distance ≤ the exact S4 bound; 1/N scaling" begin
        H = [(0.8, "ZZ"), (0.5, "XI"), (0.3, "IY")]; W = 2; t = 0.6; d = 1 << W
        hs = PauliSum{W}(H)
        Sex = ad_super(exp(-im .* ham_mat(H) .* t))

        err(N) = choi_dist(qdrift_step_super(hs, hs.λ * t / N)^N, Sex, d)

        # ε-derived plan: the realized ensemble distance obeys the plan's OWN
        # report (the untuned S4 criterion value f(N) ≤ ε) — T5's headline.
        plan = plan_evolution(QDrift(), hs, t; ε = 0.05)
        @test plan isa QDriftPlan{W}
        @test plan.report isa BoundReport
        @test err(plan.N) ≤ plan.report.inputs.bound
        @test plan.report.inputs.bound ≤ 0.05
        # explicit-N plans: the inverse-direction report is the same bound
        for N in (16, 64)
            @test err(N) ≤ qdrift_error_bound(hs.λ, t, N).value
        end
        # 1/N scaling signature (channel error ∝ 1/N; no norm gap can fake it)
        ea, eb = err(24), err(48)
        @test eb > 1e-8                       # far above fp noise: the ratio means something
        @test 1.6 ≤ ea / eb ≤ 2.4             # ≈ 2 (±20% band around the asymptote)
        # negative t: same ensemble distance by symmetry of the construction
        Sexm = ad_super(exp(im .* ham_mat(H) .* t))
        @test choi_dist(qdrift_step_super(hs, -hs.λ * t / 32)^32, Sexm, d) ≈ err(32) atol = 1e-10
    end

    # =====================================================================
    #  T6 — M12.QDRIFT.TRAJECTORY (seeded replay, ordering pinned; χ²)
    # =====================================================================
    @testset "M12.QDRIFT.TRAJECTORY — seeded replay ≡ dense product; RNG precedence; χ²" begin
        # H INCLUDES an identity word: the executor's per-plan gphase must be
        # replayed phase-SENSITIVELY (opnorm, no up-to-phase normalization).
        H = [(0.9, "ZZ"), (0.6, "XI"), (0.4, "IY"), (0.2, "II")]; W = 2; t = 0.7
        hs = PauliSum{W}(H)
        N = 40; seed = 0x5eed

        plan = plan_evolution(QDrift(N = N), hs, t)
        @test plan.report === nothing                       # explicit N ⇒ no report
        seq = collect(trajectory(plan, MersenneTwister(seed)))
        @test length(seq) == N == exp_count(plan)
        @test all(θ == flipsign(hs.λ * t / N, hs.coeffs[j]) for (j, θ) in seq)

        # the SAME seed replayed through the executor: realized unitary ==
        # dense product of the SAME sampled sequence, in the SAME order
        # (application order = iteration order = draw order — the v0.1 GQSP
        # ordering-bug class is pinned here). Up-to-phase: the UNCONTROLLED Ad
        # path crosses the phase quotient at application (§4.3 — `_emit_u2!`
        # drops φ; the c_I gphase and the H/S† basis-change phases are global
        # and unphysical at top level; their ctrl-visibility is pinned
        # phase-SENSITIVELY by the phase-1 T9 ctrl-evolve! test). Ordering
        # bugs produce genuinely different operators, which up-to-phase
        # distance still catches.
        Udense = sweep_unitary(hs, seq)
        Ureal = op_matrix(W) do x
            evolve!(x, H, t; alg = QDrift(N = N, rng = MersenneTwister(seed)))
        end
        @test dist_upto_phase(Ureal, Udense) ≤ 1e-9

        # RNG precedence (pinned): strategy rng WINS over the context rng …
        run_sv(; ctxseed, alg) = eager(W; rng = MersenneTwister(ctxseed)) do ctx
            x = QInt{W}(0)
            evolve!(x, H, t; alg)
            statevector(ctx)
        end
        sv_a = run_sv(ctxseed = 1, alg = QDrift(N = N, rng = MersenneTwister(seed)))
        sv_b = run_sv(ctxseed = 2, alg = QDrift(N = N, rng = MersenneTwister(seed)))
        @test sv_a ≈ sv_b atol = 1e-12                      # context seed irrelevant
        # … and with no strategy rng, the CONTEXT rng drives the draws
        sv_c = run_sv(ctxseed = 7, alg = QDrift(N = N))
        sv_d = run_sv(ctxseed = 7, alg = QDrift(N = N))
        sv_e = run_sv(ctxseed = 8, alg = QDrift(N = N))
        @test sv_c ≈ sv_d atol = 1e-12                      # same context seed ⇒ same trajectory
        @test !(sv_c ≈ sv_e)                                # different seed ⇒ different (a.s.)

        # χ² histogram supplement: draw frequencies match p_j = |a_j|/λ
        # (seeded ⇒ deterministic; df = L − 1 = 3, the 99.9% quantile ≈ 16.3)
        Nχ = 6000
        pχ = plan_evolution(QDrift(N = Nχ), hs, t)
        counts = zeros(Int, nterms(hs))
        for (j, _) in trajectory(pχ, MersenneTwister(0xabc))
            counts[j] += 1
        end
        χ² = sum((counts[j] - Nχ * abs(hs.coeffs[j]) / hs.λ)^2 /
                 (Nχ * abs(hs.coeffs[j]) / hs.λ) for j in 1:nterms(hs))
        @test χ² < 16.3
    end

    # =====================================================================
    #  T8 — M12.COMPOSITE.SCHEDULE (pure classical; exact slot algebra)
    # =====================================================================
    @testset "M12.COMPOSITE.SCHEDULE — HW Def 5.1 slots; exact counts; no truncation" begin
        # order 2: the hand-derived Strang sandwich (HW line 499, application order)
        @test composite_outer_slots(2) == [(:A, 0.5), (:B, 0.5), (:B, 0.5), (:A, 0.5)]
        # order 4: hand-derived from the recursion — five scaled copies of the base
        u2 = 1 / (4 - 4^(1 / 3))
        base = [(:A, 0.5), (:B, 0.5), (:B, 0.5), (:A, 0.5)]
        expected4 = vcat([[(k, g * s) for (k, s) in base]
                          for g in (u2, u2, 1 - 4u2, u2, u2)]...)
        got4 = composite_outer_slots(4)
        @test length(got4) == 20 == 2 * suzuki_sweep_count(4)
        @test got4 == expected4
        # invariants for every order: Σ_A = Σ_B = 1, palindrome, Υ of each kind
        for order in (2, 4, 6)
            slots = composite_outer_slots(order)
            Υ = suzuki_sweep_count(order)
            @test length(slots) == 2Υ
            @test count(s -> s[1] === :A, slots) == Υ
            @test sum(s[2] for s in slots if s[1] === :A) ≈ 1 atol = 1e-12
            @test sum(s[2] for s in slots if s[1] === :B) ≈ 1 atol = 1e-12
            @test slots == reverse(slots)
            # outer p ≥ 2 MUST carry negative scales (Suzuki Thm 3) — R3: |dt|
            # in the accounting, sign in the angles; asserting all-positive
            # would assert the impossible.
            @test any(s -> s[2] < 0, slots) == (order ≥ 4)
        end
        @test_throws DomainError composite_outer_slots(1)
        @test_throws DomainError composite_outer_slots(3)
        @test_throws DomainError composite_outer_slots(14)

        # exp_count == trajectory length for ALL strategies (the S1/no-hot-path
        # counting law), incl. an adversarial no-truncation grid: exact
        # r·Υ·(Υ·K + N_B) with NO ÷/remainder class anywhere (v0.1 lesson 3).
        H5 = [(1.0, "ZZIII"), (0.7, "IXXII"), (0.45, "IIYYI"), (0.3, "IIIZX"),
              (0.2, "XIIIZ"), (0.1, "ZZZZZ"), (0.05, "IYIYI")]
        hs5 = PauliSum{5}(H5)
        L = nterms(hs5)
        rng = MersenneTwister(42)
        for (order, K, N_B, r) in ((2, 1, 1, 1), (2, 3, 2, 3), (2, 6, 5, 2),
                                   (4, 2, 3, 2), (4, 5, 1, 3), (6, 1, 2, 1))
            plan = plan_evolution(Composite(; order, K, N_B, steps = r), hs5, 0.9)
            Υ = suzuki_sweep_count(order)
            @test exp_count(plan) == r * Υ * (Υ * K + N_B)
            @test length(collect(trajectory(plan, rng))) == exp_count(plan)
            # B-draw count is exactly r·Υ·N_B (every tail index > K)
            nB = count(j > K for (j, _) in trajectory(plan, rng))
            @test nB == r * Υ * N_B
            # head angle bookkeeping: Σθ over A-entries per head term = a_j·t
            for j in 1:K
                s = sum(θ for (i, θ) in collect(trajectory(plan, rng))[1:end]
                        if i == j; init = 0.0)
                @test s ≈ hs5.coeffs[j] * 0.9 rtol = 1e-10
            end
        end
        for (alg, ε) in ((Trotter(order = 4), 1e-3), (QDrift(), 5e-2))
            plan = plan_evolution(alg, hs5, 0.4; ε)
            @test length(collect(trajectory(plan, rng))) == exp_count(plan)
        end
        # deterministic plans accept-and-ignore an rng (uniform harness shape)
        pt = plan_evolution(Trotter(order = 2, steps = 2), hs5, 0.4)
        @test collect(trajectory(pt, rng)) == collect(trajectory(pt))
    end

    # =====================================================================
    #  Composite planning — defaults (S7 N_B, composite_k), degenerations
    # =====================================================================
    @testset "M12.COMPOSITE.PLAN — S7/N_B + K defaults; K = 0/L normalize; reports" begin
        H = [(1.0, "ZZ"), (0.55, "XI"), (0.3, "IY"), (0.12, "YX")]; W = 2; t = 0.8
        hs = PauliSum{W}(H)
        L = nterms(hs)

        # K = 0 / K = L normalize BEFORE scheduling — one code path, tested
        @test plan_evolution(Composite(order = 2, K = 0), hs, t; ε = 1e-2) isa QDriftPlan{W}
        @test plan_evolution(Composite(order = 2, K = L), hs, t; ε = 1e-2) isa TrotterPlan{W}
        # the K = L normalization equals the directly-planned Trotter, field for field
        pT = plan_evolution(Composite(order = 4, K = L), hs, t; ε = 1e-3)
        pT2 = plan_evolution(Trotter(order = 4), hs, t; ε = 1e-3)
        @test pT.steps == pT2.steps && pT.sweep == pT2.sweep
        # the K = 0 normalization equals the directly-planned QDrift
        pQ = plan_evolution(Composite(order = 2, K = 0), hs, t; ε = 1e-2)
        pQ2 = plan_evolution(QDrift(), hs, t; ε = 1e-2)
        @test pQ.N == pQ2.N && pQ.τ == pQ2.τ
        # fully-pinned K = 0: the exp_count-preserving map N = steps·Υ·N_B
        pQ3 = plan_evolution(Composite(order = 2, K = 0, N_B = 3, steps = 5), hs, t)
        @test pQ3 isa QDriftPlan{W} && pQ3.N == 5 * 2 * 3
        # partial pins across a degeneration are un-honorable ⇒ loud
        @test_throws ArgumentError plan_evolution(Composite(order = 2, K = 0, N_B = 3), hs, t; ε = 1e-2)
        @test_throws ArgumentError plan_evolution(Composite(order = 2, K = L, N_B = 3), hs, t; ε = 1e-2)
        @test_throws DomainError plan_evolution(Composite(order = 2, K = L + 1), hs, t; ε = 1e-2)

        # rules 4/5 for the randomized shapes (B §1.3 completed)
        @test_throws ArgumentError plan_evolution(QDrift(), hs, t)                    # free N, no ε
        @test_throws ArgumentError plan_evolution(QDrift(N = 10), hs, t; ε = 1e-2)    # pinned + ε
        @test_throws ArgumentError plan_evolution(Composite(order = 2), hs, t)        # free, no ε
        @test_throws ArgumentError plan_evolution(
            Composite(order = 2, K = 2, N_B = 2, steps = 3), hs, t; ε = 1e-2)         # pinned + ε

        # interior-K plan: derived steps satisfy Fact HW; the report is auditable
        plan = plan_evolution(Composite(order = 2, K = 2, N_B = 2), hs, t; ε = 1e-2)
        @test plan isa CompositePlan{W}
        @test plan.report isa BoundReport && plan.report.formula === :hw_fact_thm21
        @test plan.steps == Int(plan.report.value)
        @test plan.report.inputs.K == 2 && plan.report.inputs.N_B == 2
        # r is the exact ceiling of R_P + R_Q/N_B — and r − 1 fails the bound
        rr = plan.steps
        @test rr ≥ plan.report.inputs.R_P + plan.report.inputs.R_Q / 2
        rr > 1 && @test rr - 1 < plan.report.inputs.R_P + plan.report.inputs.R_Q / 2
        # the citation resolves (S6)
        @test isfile(joinpath(@__DIR__, "..", first(split(plan.report.citation, " — "))))

        # S7 N_B default: the integer scan beats (or ties) its neighbors on the
        # TRUE ceiled cost — local optimality of the stationary-point choice
        pq = Sturm._composite_RP_RQ(hs, 2, t, 1e-2; order = 2)
        nb = composite_nb(2, pq.Υ, pq.R_P, pq.R_Q)
        cost(n) = pq.Υ * (pq.Υ * 2 + n) * max(1, ceil(pq.R_P + pq.R_Q / n))
        @test cost(nb) ≤ cost(max(1, nb - 1)) && cost(nb) ≤ cost(nb + 1)
        # a plan with free N_B uses exactly that default
        pfree = plan_evolution(Composite(order = 2, K = 2), hs, t; ε = 1e-2)
        @test pfree.N_B == nb

        # composite_k: the second-moment seed is the LEAST K with
        # tail_m2[K+1]·t² ≤ ε (zlokapa Lemma, upper half), and the refined K
        # stays in [0, L]
        for ε in (1e-1, 1e-2, 1e-3)
            K = composite_k(hs, t, ε; order = 2)
            @test 0 ≤ K ≤ L
        end
        # tiny ε ⇒ everything deterministic (K = L); huge ε ⇒ pure qDrift (K = 0)
        @test composite_k(hs, t, 1e-9; order = 2) == L
        @test composite_k(hs, 0.05, 10.0; order = 2) == 0
    end

    # =====================================================================
    #  T11 — M12.COMPOSITE.CHANNEL (toy exact ensemble average)
    # =====================================================================
    @testset "M12.COMPOSITE.CHANNEL — exact ensemble ≤ composed Fact-HW bound; r-scaling" begin
        H = [(0.9, "ZZ"), (0.4, "XI"), (0.25, "IY")]; W = 2; d = 1 << W; t = 0.5
        hs = PauliSum{W}(H)
        Sex = ad_super(exp(-im .* ham_mat(H) .* t))

        # exact ensemble superoperator of the composite channel: compose A-slot
        # dense unitaries with B-slot Φ^{N_B} powers per the outer schedule
        # (fresh draws per B-slot ⇒ the slot channel is the N_B-th power of the
        # per-draw average — R2), then power the step r times.
        function composite_super(plan::CompositePlan{2})
            τstep = plan.t / plan.steps
            tail = Sturm._subsum(plan.ham, (plan.K + 1):nterms(plan.ham))
            S = Matrix{ComplexF64}(I, d^2, d^2)
            for (kind, scale) in plan.outer
                τ = scale * τstep
                if kind === :A
                    UA = sweep_unitary(plan.ham, [(j, θu * τ) for (j, θu) in plan.head_sweep])
                    S = ad_super(UA) * S
                else
                    ΦB = qdrift_step_super(tail, plan.λ_B * τ / plan.N_B)
                    S = ΦB^plan.N_B * S
                end
            end
            return S^plan.steps
        end

        for (K, N_B, r) in ((1, 1, 2), (1, 2, 3), (2, 1, 2))
            plan = plan_evolution(Composite(; order = 2, K, N_B, steps = r), hs, t)
            bound = composite_error_bound(hs, K, t, r; order = 2, N_B)
            @test choi_dist(composite_super(plan), Sex, d) ≤ bound.value   # untuned
        end
        # tail-index sanity: the tail subsum keeps canonical order (global j = K + off)
        tail = Sturm._subsum(hs, 2:3)
        @test tail.words == hs.words[2:3]

        # r-scaling: the exact ensemble error strictly improves with r and
        # keeps obeying its own bound (mixed P/r² + Q/r scaling at order 2)
        errs = [choi_dist(composite_super(
                    plan_evolution(Composite(order = 2, K = 1, N_B = 1, steps = r), hs, t)),
                    Sex, d) for r in (1, 2, 4)]
        @test errs[3] > 1e-10                    # above fp noise
        @test errs[1] > errs[2] > errs[3]
        # ε-derived plan honors ε at the exact-ensemble level (full budget)
        planε = plan_evolution(Composite(order = 2, K = 1), hs, t; ε = 5e-2)
        @test choi_dist(composite_super(planε), Sex, d) ≤ 5e-2
    end

    # =====================================================================
    #  T7 — M12.AUTO.DISPATCH (pure classical)
    # =====================================================================
    @testset "M12.AUTO.DISPATCH — fast paths; regimes; table visibility; tie-breaks" begin
        # exactness fast paths: single term / commuting family ⇒ order-1,
        # steps-1, EXACT (α ≡ 0 path never divides — the plan carries no ε)
        hs1 = PauliSum{2}([(0.7, "XY")])
        ec1 = evolve_plan(hs1, 2.0, 1e-12)
        @test ec1.choice == Trotter(order = 1, steps = 1)
        @test length(ec1.table) == 1 && ec1.table[1].skipped === nothing
        @test isempty(ec1.table[1].alpha)        # α ≡ 0 by physics: none evaluated
        hsc = PauliSum{2}([(1.0, "ZI"), (0.5, "IZ"), (0.25, "ZZ")])
        @test iscommuting(hsc)
        ecc = evolve_plan(hsc, 5.0, 1e-12)
        @test ecc.choice == Trotter(order = 1, steps = 1)
        @test length(ecc.table) == 1 && isempty(ecc.table[1].alpha)
        # …and the fast-path plan EXECUTES exactly (even at absurd ε)
        Uc = op_matrix(2) do x
            evolve!(x, [(1.0, "ZI"), (0.5, "IZ"), (0.25, "ZZ")], 5.0; ε = 1e-12)
        end
        @test dist_upto_phase(Uc, exp(-im .* ham_mat([(1.0, "ZI"), (0.5, "IZ"), (0.25, "ZZ")]) .* 5.0)) ≤ 1e-9

        # uniform coefficients (ising): deterministic Trotter wins at tight ε
        hsu = PauliSum{4}(ising_chain(4))
        ecu = evolve_plan(hsu, 1.0, 1e-4)
        @test ecu.choice isa Trotter
        # the choice IS the argmin over live rows (self-consistency)
        @test ecu.cost == minimum(r.cost for r in ecu.table if r.skipped === nothing)
        # candidate table always visible: one QDrift row + 3 Trotter + 2 Composite
        @test count(r -> r.alg isa QDrift, ecu.table) == 1
        @test count(r -> r.alg isa Trotter, ecu.table) == 3
        @test count(r -> r.alg isa Composite, ecu.table) == 2
        # skipped rows carry a REASON, never a silent drop
        @test all(r -> r.skipped === nothing || !isempty(r.skipped), ecu.table)

        # loose ε + many small uniform terms: the qDrift regime — λ² ≪ Υ·L·(bound
        # factors), and the second-moment K* collapses to 0 so the composite
        # rows degenerate (campbell_2019_qdrift.md "Asymptotics comparison")
        hsq = PauliSum{5}(heisenberg_chain(5; J = 0.05))
        ecq = evolve_plan(hsq, 1.0, 0.3)
        @test ecq.choice isa QDrift
        @test all(r -> r.skipped !== nothing, [r for r in ecq.table if r.alg isa Composite])

        # power-law tail at an intermediate (t, ε): the interior-K window —
        # the composite row is LIVE with 0 < K* < L (zlokapa second-moment
        # rule on tail_m2), whatever the final argmin
        hsp = PauliSum{6}(powerlaw_chain(6; γ = 2.0))
        t, ε = 2.0, 2e-2
        Lp = nterms(hsp)
        K0 = findfirst(K -> hsp.tail_m2[K + 1] * t^2 ≤ ε, 0:Lp) - 1
        @test 0 < K0 < Lp
        ecp = evolve_plan(hsp, t, ε)
        comprows = [r for r in ecp.table if r.alg isa Composite]
        @test any(r -> r.skipped === nothing, comprows)

        # the zlokapa optimal-split Lemma, both halves, on the power-law family
        # (K* = argmin(K + λ_K²t²/ε) ⇒ tail second moment ≤ ε̂; and the seed
        # K0 = least-K-with-small-tail-m2 never exceeds K*)
        obj(K) = K + hsp.tail_λ[K + 1]^2 * t^2 / ε
        Kstar = argmin(map(obj, 0:Lp)) - 1
        @test hsp.tail_m2[Kstar + 1] * t^2 ≤ ε
        @test K0 ≤ Kstar

        # tie-break chain: deterministic beats randomized at equal cost
        nop = AlphaLayered[]
        rows = [Sturm.PlanRow(QDrift(), 100.0, nothing, nothing, nop),
                Sturm.PlanRow(Trotter(order = 2), 100.0, nothing, nothing, nop),
                Sturm.PlanRow(Composite(order = 2), 100.0, nothing, nothing, nop),
                Sturm.PlanRow(Trotter(order = 4), 100.0, nothing, nothing, nop)]
        best = rows[argmin([Sturm._dispatch_key(r) for r in rows])]
        @test best.alg == Trotter(order = 2)     # det > rand, lower order

        # ε is REQUIRED (S3); the guard domain-checks it
        @test_throws ArgumentError plan_evolution(Auto(), hsu, 1.0)
        @test_throws DomainError evolve_plan(hsu, 1.0, -1.0)

        # Auto's CHOSEN strategy is planned with exact α (phase-1 conventions):
        # the delivered plan's report is the exact-α trotter_steps report
        pauto = plan_evolution(Auto(), hsu, 1.0; ε = 1e-4)
        @test pauto isa TrotterPlan{4}
        @test pauto.report.inputs.alpha_mode === :exact
        pdirect = plan_evolution(ecu.choice, hsu, 1.0; ε = 1e-4)
        @test pauto.steps == pdirect.steps
    end

    # =====================================================================
    #  M12.AUTO.ALPHA — the BUDGETED layered α surrogate (bead Sturm.jl-jpky)
    # =====================================================================
    # Phase 4's bench (gmx0) found `Auto` over-picking QDrift on structured
    # and head-heavy Hamiltonians because the ranking α came from the HW
    # 1-norm Lemma alone (regret 43.5 at ising-W64, t = 16, ε = 1e-4). The
    # fix keeps the ranking PROVEN and makes the proof deeper — bounds.jl's
    # inequality (‡): α_comm(H, 2k) ≤ 2^{2k}·λ^{2k+1−d}·M_d at the deepest
    # COMPLETED DP layer d. This testset pins the inequality's endpoints and
    # monotonicity, the two bench regressions (each with its RED half — the
    # old :norm1-only ranking, reconstructed, still choosing wrong), the row
    # visibility, and the invariance of every SHIPPED bound.
    @testset "M12.AUTO.ALPHA — layered α: (‡) endpoints, monotone, visible; regret" begin
        # ---- (a) the (‡) chain: endpoints, monotonicity, upper-boundness ---
        hs = PauliSum{4}(ising_chain(4))
        L = nterms(hs); λ = hs.λ
        for order in (2, 4, 6)
            αex = alpha_comm(hs, order)
            # d = 1 (zero budget) IS the explicit-opt-in HW 1-norm Lemma bound
            a1 = alpha_comm_layered(hs, order; work = 0)
            @test a1.layers == 1 && !a1.exact
            @test a1.value ≈ alpha_comm(hs, order; mode = :norm1) rtol = 1e-14
            @test a1.value ≈ 2.0^order * λ^(order + 1) rtol = 1e-14
            @test occursin("1-norm step", a1.reason)   # loud, never silent
            # d = 2 IS the tight Childs-E1 pair-sum anchor (M₂ = α_pairs
            # exactly — the bead's proposal (a), recovered as one link of (‡))
            a2 = alpha_comm_layered(hs, order; work = L * L)
            @test a2.layers == 2 && !a2.exact
            @test a2.value ≈ 2.0^order * λ^(order - 1) * alpha_comm_pairs(hs) rtol = 1e-12
            # d = 2k+1 IS the exact α, and says so
            af = alpha_comm_layered(hs, order)
            @test af.exact && af.layers == order + 1 && isempty(af.reason)
            @test af.value ≈ αex rtol = 1e-12
            @test af.what === :H
            # every stopping point is an UPPER bound, non-increasing in depth
            vals = [alpha_comm_layered(hs, order; work = b).value
                    for b in (0, L * L, 4 * L * L, 64 * L * L, typemax(Int))]
            @test all(≥(αex * (1 - 1e-12)), vals)
            @test all(i -> vals[i + 1] ≤ vals[i] * (1 + 1e-12),
                      1:(length(vals) - 1))            # B_{d+1} ≤ B_d
            @test vals[end] ≈ αex rtol = 1e-12
        end
        # a commuting sum has α ≡ 0 at EVERY budget (the DP empties out; the
        # (‡) closure of an exhausted measure is 0, not a positive bound)
        hscom = PauliSum{4}([(1.0, "ZIII"), (0.5, "IZII"), (0.25, "ZZII")])
        @test alpha_comm_layered(hscom, 4; work = typemax(Int)).value == 0.0
        @test alpha_comm_layered(hscom, 4; work = typemax(Int)).exact
        # the layered CROSS device: exact ⇒ the same inclusion–exclusion pair
        # as `alpha_comm_cross`; budgeted ⇒ proven bounds, never a subtraction
        # of bounds (which is neither an upper nor a lower bound)
        (αA, αAB) = alpha_comm_cross(hs, 3, 2)
        cl = alpha_comm_cross_layered(hs, 3, 2)
        @test cl.exact
        @test cl.αA ≈ αA rtol = 1e-12
        @test cl.αAB ≈ αAB rtol = 1e-12
        cl0 = alpha_comm_cross_layered(hs, 3, 2; work = 0)
        @test !cl0.exact && cl0.αA ≥ αA && cl0.αAB ≥ αAB
        @test cl0.provA.what === :A && cl0.provAB.what === :cross
        @test !isempty(cl0.provAB.reason)
        # a supplied αH must match the order it is used at (a caching bug is
        # a bug, not a bound question)
        @test_throws ErrorException alpha_comm_cross_layered(
            hs, 3, 2; αH = alpha_comm_layered(hs, 4))

        # ---- (b) REGRESSION 1: the bench's worst analytic cell --------------
        # ising-W64 normalized to λ = 1 (the gmx0 convention), t = 16, ε = 1e-4:
        # bench regret 43.5 — Auto chose QDrift over Trotter order 2.
        is64 = PauliSum{64}(ising_chain(64; J = 1 / 127, h = 1 / 127))
        @test nterms(is64) == 127
        @test is64.λ ≈ 1.0 rtol = 1e-12
        t64, ε64 = 16.0, 1e-4
        cert64 = Dict(lab => Float64(exp_count(plan_evolution(alg, is64, t64; ε = ε64)))
                      for (lab, alg) in (("T2", Trotter(order = 2)),
                                         ("T4", Trotter(order = 4)),
                                         ("T6", Trotter(order = 6)),
                                         ("QD", QDrift())))
        best64 = minimum(values(cert64))
        @test best64 == cert64["T2"]                   # the bench's certified argmin
        # RED half: the OLD ranking (α from :norm1 only, everything else
        # identical) still ranks QDrift first — the failure this bead fixes.
        old64 = Dict("QD" => qdrift_samples(is64.λ, t64, ε64).value)
        for o in (2, 4, 6)
            old64["T$o"] = trotter_steps(is64, t64, ε64; order = o,
                                         alpha_mode = :norm1).value *
                           suzuki_sweep_count(o) * nterms(is64)
        end
        @test argmin(old64) == "QD"
        @test cert64["QD"] / best64 > 40               # the 43.5 the bench measured
        # GREEN half: the layered surrogate ranks the deterministic row first
        ec64 = evolve_plan(is64, t64, ε64)
        @test ec64.choice isa Trotter && ec64.choice.order == 2
        auto64 = Float64(exp_count(plan_evolution(Auto(), is64, t64; ε = ε64)))
        @test auto64 == best64                          # regret EXACTLY 1
        @test auto64 == 235204                          # …and the pinned value
        # every deterministic row was priced at EXACT α here (the DP fits the
        # budget on a structured chain), and says so on the row
        for r in ec64.table
            r.alg isa Trotter || continue
            @test length(r.alpha) == 1 && r.alpha[1].exact
            @test r.report.inputs.alpha_mode === :exact
        end
        # the composite rows degenerate (K* = L) and carry the reason
        @test all(r -> occursin("degenerates to pure Trotter", something(r.skipped, "")),
                  [r for r in ec64.table if r.alg isa Composite])

        # ---- (c) REGRESSION 2: the head-heavy exp-coefficient class ---------
        # The bench's exp-L256 cells (regret up to 15: Auto missed Composite).
        # CI-cheap analogue: exponential coefficients 2^{-j} on a 2-local
        # chain, λ-normalized — the same head-heavy tail that makes the
        # HW composite optimal.
        function exp_chain(W::Int)
            terms = Tuple{Float64,String}[]
            n = 0
            for j in 1:(W - 1)
                n += 1
                s = fill('I', W); s[j] = 'X'; s[j + 1] = 'X'
                push!(terms, (2.0^(-n), String(s)))
            end
            for j in 1:W
                n += 1
                s = fill('I', W); s[j] = 'Z'
                push!(terms, (2.0^(-n), String(s)))
            end
            λ = sum(abs(c) for (c, _) in terms)
            return PauliSum{W}([(c / λ, w) for (c, w) in terms])
        end
        hx = exp_chain(12)
        tx, εx = 4.0, 1e-3
        certx = Dict(lab => Float64(exp_count(plan_evolution(alg, hx, tx; ε = εx)))
                     for (lab, alg) in (("T2", Trotter(order = 2)),
                                        ("T4", Trotter(order = 4)),
                                        ("T6", Trotter(order = 6)),
                                        ("QD", QDrift()),
                                        ("C2", Composite(order = 2)),
                                        ("C4", Composite(order = 4))))
        @test argmin(certx) == "C2"                     # Composite IS best here
        # RED half: the OLD :norm1 ranking put QDrift first ⇒ regret 62.5
        oldx = Dict("QD" => qdrift_samples(hx.λ, tx, εx).value)
        for o in (2, 4, 6)
            oldx["T$o"] = trotter_steps(hx, tx, εx; order = o,
                                        alpha_mode = :norm1).value *
                          suzuki_sweep_count(o) * nterms(hx)
        end
        Kx = findfirst(K -> hx.tail_m2[K + 1] * tx^2 ≤ εx, 0:nterms(hx)) - 1
        @test 0 < Kx < nterms(hx)
        for o in (2, 4)
            pq = Sturm._composite_RP_RQ(hx, Kx, tx, εx; order = o, alpha_mode = :norm1)
            n = composite_nb(Kx, pq.Υ, pq.R_P, pq.R_Q)
            rep = composite_steps(hx, Kx, tx, εx; order = o, N_B = n,
                                  alpha_mode = :norm1)
            oldx["C$o"] = pq.Υ * (pq.Υ * Kx + n) * rep.value
        end
        @test argmin(oldx) == "QD"
        @test certx["QD"] / certx["C2"] > 60            # the regret it would pay
        # GREEN half: the layered surrogate finds Composite, at regret 1
        ecx = evolve_plan(hx, tx, εx)
        @test ecx.choice isa Composite && ecx.choice.order == 2
        autox = Float64(exp_count(plan_evolution(Auto(), hx, tx; ε = εx)))
        @test autox == certx["C2"] == 1024

        # ---- (d) row visibility, including a budget-exhausted row -----------
        for r in ecx.table
            if r.alg isa QDrift
                @test isempty(r.alpha)                  # S4 is λ-only: no α exists
            elseif r.skipped === nothing && r.alg isa Trotter
                @test [a.what for a in r.alpha] == [:H]
                @test r.alpha[1].order == r.alg.order
            elseif r.skipped === nothing
                @test [a.what for a in r.alpha] == [:A, :cross]
            end
        end
        # a starved dispatch degrades VISIBLY: every α-consuming row reports
        # the depth it reached and why it stopped — never an invisible downgrade
        ec0 = evolve_plan(hx, tx, εx; alpha_work = 0)
        αrows = [r for r in ec0.table if r.skipped === nothing && !isempty(r.alpha)]
        @test !isempty(αrows)
        for r in αrows
            @test all(a -> !a.exact && a.layers == 1, r.alpha)
            @test all(a -> occursin("work budget", a.reason) ||
                           occursin("1-norm cross sum", a.reason), r.alpha)
            @test r.report.inputs.alpha_mode === :layered
        end
        # …and the starved ranking is still a ranking of PROVEN bounds: each
        # row's cost is ≥ the same row's cost at the full budget (one-sided)
        full = Dict(string(r.alg) => r.cost for r in ecx.table)
        for r in ec0.table
            haskey(full, string(r.alg)) || continue
            isfinite(r.cost) && isfinite(full[string(r.alg)]) || continue
            @test r.cost ≥ full[string(r.alg)] * (1 - 1e-12)
        end

        # ---- (e) INVARIANCE: no shipped bound moved -------------------------
        # Literal pins on the explicit-strategy plans (what a user is handed).
        # These numbers are the phase-1/2 bounds and must NOT change because
        # the RANKING got tighter.
        px2 = plan_evolution(Trotter(order = 2), hx, tx; ε = εx)
        @test (px2.steps, exp_count(px2)) == (28, 1288)
        @test px2.report.inputs.alpha_mode === :exact
        @test exp_count(plan_evolution(Trotter(order = 4), hx, tx; ε = εx)) == 25300
        @test plan_evolution(QDrift(), hx, tx; ε = εx).N == 64003
        pxc = plan_evolution(Composite(order = 2), hx, tx; ε = εx)
        @test (pxc.K, pxc.N_B, pxc.steps, exp_count(pxc)) == (7, 2, 32, 1024)
        @test [plan_evolution(Trotter(; order), is64, t64; ε = ε64).steps
               for order in (2, 4, 6)] == [926, 264, 533]
        @test plan_evolution(QDrift(), is64, t64; ε = ε64).N == 10240011
        # the dispatch budget CANNOT reach a shipped bound: whatever shape a
        # starved dispatch picks, the plan it returns is bit-for-bit the plan
        # that shape gets on its own (exact α, phase-1 conventions)
        for aw in (0, 4096, ALPHA_WORK_DEFAULT)
            ch = evolve_plan(hx, tx, εx; alpha_work = aw).choice
            pa = plan_evolution(Auto(), hx, tx; ε = εx, alpha_work = aw)
            pd = plan_evolution(ch, hx, tx; ε = εx)
            @test typeof(pa) === typeof(pd) && exp_count(pa) == exp_count(pd)
            # …and the delivered bound is the EXACT-α one (QDrift's S4
            # criterion has no α at all — it is exact by construction)
            pa isa QDriftPlan || @test pa.report.inputs.alpha_mode === :exact
        end
    end

    # =====================================================================
    #  T10 additions — the now-reachable guards (S10 + B §1.4)
    # =====================================================================
    @testset "M12.GUARDRAIL.RANDOM — DM/Tracing + randomized; under-when; rng-less trajectory" begin
        H = [(1.0, "ZZ"), (0.5, "XI")]; W = 2
        hs = PauliSum{W}(H)

        # DM + randomized ⇒ loud error naming M11 (S10); deterministic stays legal
        err = try
            density(W) do _
                x = QInt{W}(0)
                evolve!(x, H, 0.5; alg = QDrift(N = 5))
            end
            nothing
        catch e
            e
        end
        @test err isa ErrorException && occursin("M11", err.msg)
        @test occursin("density", err.msg) || occursin("DM", err.msg)
        errc = try
            density(W) do _
                x = QInt{W}(0)
                evolve!(x, H, 0.5; alg = Composite(order = 2, K = 1, N_B = 1, steps = 1))
            end
            nothing
        catch e
            e
        end
        @test errc isa ErrorException && occursin("M11", errc.msg)
        # deterministic on DM: legal, unchanged (S10 bans only randomized)
        @test density(W) do _
            x = QInt{W}(0)
            evolve!(x, H, 0.5; steps = 2)
            true
        end

        # randomized under a live `when` frame ⇒ loud error; deterministic legal (S9)
        errw = try
            eager(W + 1) do _
                c = QBool(false)
                x = QInt{W}(0)
                when(c) do
                    evolve!(x, H, 0.3; alg = QDrift(N = 3, rng = MersenneTwister(1)))
                end
            end
            nothing
        catch e
            e
        end
        @test errw isa ErrorException && occursin("when", errw.msg)
        @test occursin("mixture", errw.msg)

        # Tracing + randomized ⇒ loud (a traced trajectory would materialize
        # ONE unravelling as the channel DAG — the S10 class at the DAG level)
        errt = try
            trace(0) do
                x = QInt{W}(0)
                evolve!(x, H, 0.3; alg = QDrift(N = 2, rng = MersenneTwister(1)))
                nothing
            end
            nothing
        catch e
            e
        end
        @test errt isa ErrorException && occursin("M11", errt.msg)

        # trajectory without an rng THROWS for randomized plans
        pq = plan_evolution(QDrift(N = 4), hs, 0.5)
        pc = plan_evolution(Composite(order = 2, K = 1, N_B = 1, steps = 1), hs, 0.5)
        @test_throws ErrorException trajectory(pq)
        @test_throws ErrorException trajectory(pc)

        # the evolve! surface completes rules 4/5 through the entry point
        runq(f) = eager(4) do _
            x = QInt{W}(0)
            f(x)
        end
        @test_throws ArgumentError runq(x -> evolve!(x, H, 1.0; alg = QDrift()))
        @test_throws ArgumentError runq(x -> evolve!(x, H, 1.0; alg = QDrift(N = 10), ε = 1e-2))
        @test_throws ArgumentError runq(x -> evolve!(x, H, 1.0; alg = Composite(order = 2)))
        # …and the bare-ε call now RUNS Auto end-to-end (the phase-1 stub is gone)
        @test runq(x -> evolve!(x, H, 1.0; ε = 1e-2)) isa QInt{W}
    end

    # =====================================================================
    #  H1 — M12.HEAVY.SHOTS (statistical tier; ENV-gated)
    # =====================================================================
    if get(ENV, "STURM_TEST_HEAVY", "0") == "1"
        @testset "M12.HEAVY.SHOTS — trajectory-mean within diamond ε; √ε typicality" begin
            H = [(0.9, "ZZ"), (0.6, "XI"), (0.4, "IY")]; W = 2; t = 0.8; ε = 4e-2
            hs = PauliSum{W}(H)
            plan = plan_evolution(QDrift(), hs, t; ε)
            N = plan.N
            ψex = exp(-im .* ham_mat(H) .* t)[:, 1]        # e^{−iHt}|00⟩
            M = 1200
            fids = Vector{Float64}(undef, M)
            for s in 1:M
                ψ = eager(W) do ctx
                    x = QInt{W}(0)
                    evolve!(x, H, t; alg = QDrift(N = N, rng = MersenneTwister(s)))
                    core = _core(ctx)
                    slots = [core.wire_to_slot[w] for w in x.wires]
                    sv = statevector(ctx)
                    out = Vector{ComplexF64}(undef, 1 << W)
                    for v in 0:(1 << W - 1)
                        i = 0
                        for (b, sl) in enumerate(slots)
                            ((v >> (W - b)) & 1) == 1 && (i |= 1 << sl)
                        end
                        out[v + 1] = sv[i + 1]
                    end
                    out
                end
                fids[s] = abs2(dot(ψex, ψ))
            end
            # observable O = |ψex⟩⟨ψex| (‖O‖ = 1): the SHOT-AVERAGED mean obeys
            # the diamond bound |E⟨O⟩ − 1| ≤ ‖E − U‖_⋄ ≤ ε, plus 3σ̂ statistics
            # (campbell_2019_qdrift.md — the ensemble regime; the CORRECT
            # tolerance for AVERAGED tests per chen_2021 "What this licenses").
            σ̂ = _stderr(fids)
            @test abs(_mean(fids) - 1) ≤ ε + 3σ̂
            # typicality (chen_2021_concentration_random_products.md, Thm
            # summary_of_errors): a SINGLE trajectory concentrates at ~√ε, not
            # ε — the per-trajectory pure-state trace distance √(1 − F) spreads
            # on the √ε scale (loose factor-3 band; a supplement, not a bound).
            devs = sqrt.(max.(0.0, 1 .- fids))
            @test _quantile(devs, 0.9) ≤ 3 * sqrt(ε)
            # …and the single-trajectory spread genuinely EXCEEDS the ensemble
            # scale (the regimes are distinct — the S10 rationale made visible)
            @test _quantile(devs, 0.9) > ε / 4
        end
    else
        @info "M12.HEAVY.SHOTS skipped (set ENV[\"STURM_TEST_HEAVY\"] = \"1\" to run)"
    end
end
