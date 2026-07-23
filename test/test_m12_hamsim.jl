# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# Sturm.jl M12 phase 1 (bead Sturm.jl-elsf): the deterministic core of the
# Hamiltonian-simulation strategy layer — symplectic Pauli algebra, canonical
# `PauliSum`, Suzuki order-2p stage scales, the EXACT α_comm engine, Trotter
# step/error bounds (BoundReport), strategy structs, TrotterPlan/trajectory/
# exp_count, and the `_act!`-emitting executor (deterministic ctrl-`evolve!`).
# Design: docs/design/m12-synthesis.md (rulings S1–S14; S3/S9 as ruled).
#
# Every bound asserted here is UNTUNED — computed from the cited inequality
# (docs/physics/childs_2019_trotter_error.md eq E1;
# docs/physics/hagan_wiebe_2023_composite.md eqs diamond_to_spectral_start–
# TS_intermediate_3; docs/physics/suzuki_1991_fractal_decomposition.md
# eqs 3.14–3.16) with the actual λ, α_comm, t, ε. Scaling-signature bands are
# the order pins (immune to prefactor conventions), the M10 pattern.
#
# Reuses the Main-scope M10 harness (test_m10_library.jl, included earlier by
# runtests.jl): `op_matrix`, `word_mat`, `ham_mat`, `dist_upto_phase`.

using Test
using Sturm
using LinearAlgebra
using Random
using Sturm: eager, statevector, _core, orkan_state_set!,
             PauliTerm, PauliWord, PauliSum, letter_at, mulword, commutes,
             iscommuting, suzuki_stage_scales, alpha_comm, alpha_comm_pairs,
             alpha_comm_cross, AlphaCommBlowup, trotter_steps,
             trotter_error_bound, BoundReport, plan_evolution, trajectory,
             exp_count, ising_chain, heisenberg_chain, powerlaw_chain

@testset "M12 — Hamiltonian simulation, phase 1 (deterministic core)" begin

    # =====================================================================
    #  T1 — M12.PAULI.ALGEBRA
    # =====================================================================
    @testset "M12.PAULI.ALGEBRA — symplectic vs dense kron; endianness pin; canonicalization" begin
        # THE ENDIANNESS PIN (one test, v0.1 lesson 6): char 1 = wire 1 = MSB,
        # i.e. char j occupies mask bit (W − j). Pinned in pauli.jl ONLY.
        w = PauliWord{2}("XI")
        @test w.x == 0b10 && w.z == 0b00
        w2 = PauliWord{2}("IZ")
        @test w2.x == 0b00 && w2.z == 0b01
        @test PauliWord{2}("YI").x == 0b10 && PauliWord{2}("YI").z == 0b10
        @test String(PauliWord{3}("XYZ")) == "XYZ"
        @test letter_at(PauliWord{3}("XYZ"), 1) == 'X'
        @test letter_at(PauliWord{3}("XYZ"), 3) == 'Z'

        # string ↔ mask round trip on random words
        rng = MersenneTwister(0x12)
        for W in (1, 2, 6, 64), _ in 1:25
            s = String(rand(rng, ['I', 'X', 'Y', 'Z'], W))
            @test String(PauliWord{W}(s)) == s
        end

        # product + i^k phase + commutation vs dense kron — EXHAUSTIVE W ≤ 2
        for W in (1, 2)
            letters = W == 1 ? ["I", "X", "Y", "Z"] :
                               [String([a, b]) for a in "IXYZ" for b in "IXYZ"]
            for sp in letters, sq in letters
                p, q = PauliWord{W}(sp), PauliWord{W}(sq)
                k, r = mulword(p, q)
                @test word_mat(sp) * word_mat(sq) ≈ (im^k) .* word_mat(String(r)) atol = 1e-12
                C = word_mat(sp) * word_mat(sq) - word_mat(sq) * word_mat(sp)
                @test commutes(p, q) == (opnorm(C) < 1e-12)
                # anticommuting unit words: ‖[P,Q]‖ = 2 EXACTLY (the α_comm enabling fact)
                commutes(p, q) || @test opnorm(C) ≈ 2.0 atol = 1e-12
            end
        end

        # canonicalization: merge (S12), zero-drop, identity split, |a|-desc sort, λ, tails
        hs = PauliSum{2}([(0.5, "ZZ"), (1.5, "XI"), (0.25, "ZZ"), (0.0, "YY"), (0.3, "II")])
        @test length(hs.coeffs) == 2
        @test hs.coeffs[1] == 1.5 && String(hs.words[1]) == "XI"
        @test hs.coeffs[2] == 0.75 && String(hs.words[2]) == "ZZ"   # 0.5 + 0.25 merged
        @test hs.c_I == 0.3                                          # identity split out
        @test hs.λ ≈ 2.25                                            # identity EXCLUDED
        @test hs.tail_λ[1] ≈ 2.25 && hs.tail_λ[2] ≈ 0.75 && hs.tail_λ[3] == 0.0
        @test hs.tail_m2[1] ≈ 1.5^2 + 0.75^2 && hs.tail_m2[3] == 0.0
        @test PauliSum{2}(hs) === hs                                 # idempotent pass-through
        @test PauliSum{2}([PauliTerm(1.0, "XY")]).coeffs == [1.0]    # Vector{PauliTerm} input

        # negative coefficients: signs kept, sort by |a|
        hn = PauliSum{1}([(-2.0, "X"), (1.0, "Z")])
        @test hn.coeffs[1] == -2.0 && hn.λ ≈ 3.0

        # errors: wrong length, bad letter, W > 64 (UInt64 masks) — all loud
        @test_throws DimensionMismatch PauliSum{2}([(1.0, "ZZZ")])
        @test_throws ArgumentError PauliSum{2}([(1.0, "ZA")])
        @test_throws Exception PauliSum{65}([(1.0, "I"^65)])
    end

    # =====================================================================
    #  T2 — M12.SUZUKI.COEFFS
    # =====================================================================
    @testset "M12.SUZUKI.COEFFS — γ-recursion invariants + order-4 scaling signature" begin
        @test suzuki_stage_scales(1) == [1.0]
        u2 = 1 / (4 - 4^(1 / 3))
        γ2 = suzuki_stage_scales(2)
        @test length(γ2) == 5
        @test γ2 ≈ [u2, u2, 1 - 4u2, u2, u2]
        # Suzuki 1991 Fig. 1 caption: p_2 = 0.4144907717943757…
        @test u2 ≈ 0.4144907717943757 atol = 1e-15

        for p in 1:6
            γ = suzuki_stage_scales(p)
            @test length(γ) == 5^(p - 1)
            @test abs(sum(γ) - 1) ≤ 64 * eps() * length(γ)       # first-order consistency
            @test γ == reverse(γ)                                 # palindrome, EXACT
            # Suzuki Thm 3 (nonexistence of positive decomposition): p ≥ 2 MUST
            # have negative substeps — asserting all-positive would assert the impossible.
            p ≥ 2 && @test any(<(0), γ)
        end
        @test_throws Exception suzuki_stage_scales(7)             # order cap 12 (S11), loud
        @test_throws Exception suzuki_stage_scales(0)

        # BigFloat twin (transcription-typo guard): ≤ 4 eps relative
        for p in 2:4
            γ = suzuki_stage_scales(p)
            Γ = Float64.(suzuki_stage_scales(BigFloat, p))
            @test maximum(abs.((γ .- Γ) ./ Γ)) ≤ 4 * eps()
        end

        # ORDER-4 SCALING SIGNATURE: doubling r divides the error by ≈ 2^{2p} = 16
        # (the order pin, immune to coefficient-magnitude conventions).
        H = [(1.0, "ZZ"), (0.5, "XI")]; t = 1.0; W = 2
        Uex = exp(-im .* ham_mat(H) .* t)
        U4(r) = op_matrix(W) do x
            evolve!(x, H, t; alg = Trotter(order = 4, steps = r))
        end
        da = dist_upto_phase(U4(2), Uex)
        db = dist_upto_phase(U4(4), Uex)
        @test db > 1e-10                       # well above fp noise: the ratio means something
        @test 11 ≤ da / db ≤ 22                # ≈ 16 (±40% band around the asymptote)
    end

    # =====================================================================
    #  T4 — M12.ALPHA.EXACT
    # =====================================================================
    @testset "M12.ALPHA.EXACT — DP vs brute-force tuple enumeration; guards" begin
        # Ground truth: the defining sum (hagan_wiebe_2023_composite.md, eq
        # def:alpha_comm) by brute-force enumeration with dense matrices.
        # M_j = |h_j|·P_j makes the per-tuple norm Π|h|·‖nested(units)‖ by
        # multilinearity of the nested commutator.
        function alpha_brute(H, order2k)
            Ms = [abs(c) .* word_mat(w) for (c, w) in H]
            L = length(Ms)
            tot = 0.0
            for idx in Iterators.product(ntuple(_ -> 1:L, order2k + 1)...)
                C = Ms[idx[1]]
                for d in 2:(order2k + 1)
                    C = Ms[idx[d]] * C - C * Ms[idx[d]]
                end
                tot += opnorm(C)
            end
            return tot
        end

        H3 = [(0.9, "ZZ"), (0.4, "XI"), (0.2, "IY")]
        hs3 = PauliSum{2}(H3)
        @test alpha_comm(hs3, 2) ≈ alpha_brute(H3, 2) rtol = 1e-9

        # hand-computed 2-term value: H = aX + bZ (W = 1), 2k = 2:
        # μ₂ = {Y: 2ab}, μ₃ = {Z: 2a²b, X: 2ab²} ⇒ α = 2²·2ab(a+b)
        a, b = 0.8, 0.5
        hs2 = PauliSum{1}([(a, "X"), (b, "Z")])
        @test alpha_comm(hs2, 2) ≈ 4 * 2 * a * b * (a + b) rtol = 1e-12
        @test alpha_comm(hs2, 2) ≈ alpha_brute([(a, "X"), (b, "Z")], 2) rtol = 1e-9
        # order 4 (3^5 = 243 tuples): the DP nests correctly beyond one level
        @test alpha_comm(hs2, 4) ≈ alpha_brute([(a, "X"), (b, "Z")], 4) rtol = 1e-9

        # commuting family ⇒ exactly 0 (and the empty sum stays 0.0)
        @test alpha_comm(PauliSum{2}([(1.0, "ZI"), (2.0, "IZ"), (0.5, "ZZ")]), 2) == 0.0
        @test iscommuting(PauliSum{2}([(1.0, "ZI"), (2.0, "IZ"), (0.5, "ZZ")]))
        @test !iscommuting(hs3)

        # sign-insensitivity: commutator norms see |a| only
        @test alpha_comm(PauliSum{1}([(-a, "X"), (b, "Z")]), 2) ≈ alpha_comm(hs2, 2) rtol = 1e-12

        # partition identity by inclusion–exclusion (exact; canonical order of
        # hs3 is ZZ(0.9) | XI(0.4), IY(0.2), so K = 1 cuts exactly there)
        A = [(0.9, "ZZ")]; B = [(0.4, "XI"), (0.2, "IY")]
        αA, αAB = alpha_comm_cross(hs3, 1, 2)
        @test αA ≈ alpha_brute(A, 2) rtol = 1e-9
        @test αA + αAB + alpha_comm(PauliSum{2}(B), 2) ≈ alpha_comm(hs3, 2) rtol = 1e-12
        @test αAB ≈ alpha_brute(H3, 2) - alpha_brute(A, 2) - alpha_brute(B, 2) rtol = 1e-8

        # the blowup guard fires LOUD (no silent substitution path exists)
        @test_throws AlphaCommBlowup alpha_comm(hs3, 2; maxwords = 1)
        # :norm1 is an explicit-opt-in BOUND (HW Lemma bounds_on_alpha_and_p), never a fallback
        @test alpha_comm(hs3, 2; mode = :norm1) ≥ alpha_comm(hs3, 2)
        @test alpha_comm(hs3, 2; mode = :norm1) ≈ 4 * hs3.λ^3 rtol = 1e-12
        @test_throws ArgumentError alpha_comm(hs3, 2; mode = :estimate)
        @test_throws DomainError alpha_comm(hs3, 3)              # α_comm is a 2k object

        # first-order tight pair sum (childs E1) vs dense commutators
        Ms3 = [c .* word_mat(w) for (c, w) in H3]
        e1 = sum(opnorm(Ms3[i] * Ms3[j] - Ms3[j] * Ms3[i])
                 for i in 1:2 for j in (i + 1):3)
        @test alpha_comm_pairs(hs3) ≈ e1 rtol = 1e-9
    end

    # =====================================================================
    #  T3 — M12.TROTTER.BOUND
    # =====================================================================
    @testset "M12.TROTTER.BOUND — realized ≤ cited bound (exact α, untuned); BoundReport" begin
        H = [(1.0, "ZZ"), (0.5, "XI")]; W = 2; t = 1.0
        hs = PauliSum{W}(H)
        Uex = exp(-im .* ham_mat(H) .* t)

        # order 4 at explicit r: realized spectral distance ≤ the spectral half of
        # the HW bound with EXACT α_comm (hagan_wiebe eq TS_intermediate_2 × r)
        r = 20
        rep4 = trotter_error_bound(hs, t, r; order = 4)
        @test rep4.formula === :hw_trotter_2k
        @test rep4.value ≈ 2 * rep4.inputs.spectral        # THE ×2 pin: diamond = 2·spectral
        U4 = op_matrix(W) do x
            evolve!(x, H, t; alg = Trotter(order = 4, steps = r))
        end
        @test dist_upto_phase(U4, Uex) ≤ rep4.inputs.spectral

        # the citation resolves (S6: bounds are auditable data)
        for rep in (rep4, trotter_error_bound(hs, t, 10; order = 1))
            path = first(split(rep.citation, " — "))
            @test isfile(joinpath(@__DIR__, "..", path))
        end

        # steps-from-ε consistency: the derived r satisfies the bound; r − 1 does not
        # (the ceiling is tight), for orders 1, 2, 4 — ε is the FULL diamond norm (S5)
        for (order, ε) in ((1, 1e-2), (2, 1e-3), (4, 1e-3))
            rp = trotter_steps(hs, t, ε; order)
            rr = Int(rp.value)
            @test trotter_error_bound(hs, t, rr; order).value ≤ ε
            rr > 1 && @test trotter_error_bound(hs, t, rr - 1; order).value > ε
        end

        # order 2 through the ε path end-to-end: realized ≤ spectral report
        rp2 = trotter_steps(hs, t, 1e-3; order = 2)
        U2m = op_matrix(W) do x
            evolve!(x, H, t; alg = Trotter(order = 2), ε = 1e-3)
        end
        @test dist_upto_phase(U2m, Uex) ≤
              trotter_error_bound(hs, t, Int(rp2.value); order = 2).inputs.spectral

        # 3-qubit, X/Y/Z + identity words, order 4 vs expm under its own bound
        H3q = [(0.7, "ZZI"), (0.4, "IXX"), (0.3, "YIY"), (0.2, "III")]
        hs3q = PauliSum{3}(H3q)
        U3 = op_matrix(3) do x
            evolve!(x, H3q, 0.5; alg = Trotter(order = 4, steps = 6))
        end
        @test dist_upto_phase(U3, exp(-im .* ham_mat(H3q) .* 0.5)) ≤
              trotter_error_bound(hs3q, 0.5, 6; order = 4).inputs.spectral

        # commuting H ⇒ α ≡ 0 ⇒ r = 1 exactly, no division blowup (named degeneracy)
        hc = PauliSum{2}([(1.0, "ZI"), (0.5, "IZ")])
        @test Int(trotter_steps(hc, 3.0, 1e-8; order = 2).value) == 1
        @test Int(trotter_steps(hc, 3.0, 1e-8; order = 1).value) == 1

        # |t| symmetry: bounds use |t| (t < 0 legal, angles carry the sign)
        @test trotter_error_bound(hs, -t, r; order = 4).value ≈ rep4.value
    end

    # =====================================================================
    #  Plans — plan_evolution / trajectory / exp_count (S1, S6)
    # =====================================================================
    @testset "M12.PLAN — immutable plans, lazy trajectory, exact exponential counts" begin
        hs = PauliSum{2}([(1.0, "ZZ"), (0.5, "XI")])
        L = 2

        plan = plan_evolution(Trotter(order = 2, steps = 3), hs, 1.0)
        @test exp_count(plan) == 3 * 2 * L                 # r·Υ·L′, Υ(order 2) = 2
        @test length(collect(trajectory(plan))) == exp_count(plan)
        @test collect(trajectory(plan))[1:(2L)] == plan.sweep   # one shared sweep per step

        p1 = plan_evolution(Trotter(order = 1, steps = 5), hs, 1.0)
        @test exp_count(p1) == 5 * L                       # order 1: single forward sweep
        @test p1.sweep == [(1, 1.0 / 5), (2, 0.5 / 5)]     # canonical order, θ = a_j·τ

        p4 = plan_evolution(Trotter(order = 4, steps = 2), hs, 1.0)
        @test exp_count(p4) == 2 * 10 * L                  # Υ(order 4) = 10

        # angle bookkeeping: Σ_sweep θ per term × steps = a_j·t exactly (to fp)
        for p in (plan, p4), j in 1:L
            s = sum(θ for (i, θ) in p.sweep if i == j) * p.steps
            @test s ≈ hs.coeffs[j] * 1.0 rtol = 1e-12
        end

        # ε-derived plans carry their BoundReport (S6); explicit-steps plans carry nothing
        pε = plan_evolution(Trotter(order = 2), hs, 1.0; ε = 1e-3)
        @test pε.report isa BoundReport
        @test pε.steps == Int(pε.report.value)
        @test plan.report === nothing
    end

    # =====================================================================
    #  T9 — M12.CTRL.EVOLVE (S9 as ruled, guarded by R3)
    # =====================================================================
    @testset "M12.CTRL.EVOLVE — deterministic evolve! under when ≡ dense ctrl-expm" begin
        # H includes an identity word: under ctrl its gphase must surface as a
        # RELATIVE phase on the |1⟩ block (kernel ctrl(gphase) is a real op) —
        # compared phase-SENSITIVELY (no up-to-phase normalization).
        H = [(0.7, "ZZ"), (0.4, "XI"), (0.2, "II")]; t = 0.8; W = 2; r = 24
        hs = PauliSum{W}(H)
        N = 1 << (W + 1)
        Ureal = Matrix{ComplexF64}(undef, N, N)
        for jin in 0:(N - 1)
            eager(W + 2) do ctx
                c = QBool(false)
                x = QInt{W}(0)
                core = _core(ctx)
                slots = [core.wire_to_slot[c.wire];
                         [core.wire_to_slot[w] for w in x.wires]]
                enc(v) = begin
                    i = 0
                    for (bpos, s) in enumerate(slots)
                        ((v >> (W + 1 - bpos)) & 1) == 1 && (i |= 1 << s)
                    end
                    i
                end
                st = core.state
                orkan_state_set!(st, 0, 0, zero(ComplexF64))
                orkan_state_set!(st, enc(jin), 0, one(ComplexF64))
                when(c) do
                    evolve!(x, H, t; alg = Trotter(order = 2, steps = r))
                end
                sv = statevector(ctx)
                for jout in 0:(N - 1)
                    Ureal[jout + 1, jin + 1] = sv[enc(jout) + 1]
                end
                nothing
            end
        end
        Uex = exp(-im .* ham_mat(H) .* t)
        Cex = [Matrix{ComplexF64}(I, 4, 4) zeros(4, 4); zeros(4, 4) Uex]
        bound = trotter_error_bound(hs, t, r; order = 2).inputs.spectral
        @test opnorm(Ureal .- Cex) ≤ bound + 1e-9   # phase-faithful, untuned
        @test opnorm(Ureal[1:4, 1:4] - I) ≤ 1e-9    # the |0⟩ branch is EXACT identity

        # guardrail 2 still fires through evolve!: the body may not touch its control
        @test_throws Exception eager(4) do ctx
            x = QInt{2}(0)
            when(x[1]) do
                evolve!(x, [(1.0, "ZZ")], 0.3; steps = 1)
            end
        end
    end

    # =====================================================================
    #  T12 — M12.EVOLVE.SUGAR (M10 regression)
    # =====================================================================
    @testset "M12.EVOLVE.SUGAR — kwargs ≡ Trotter strategy; t = 0 no-op; t < 0 legal" begin
        H = [(1.0, "ZZ"), (0.5, "XI")]; t = 0.7; W = 2
        for (r, ord) in ((3, 1), (4, 2))
            A = op_matrix(W) do x; evolve!(x, H, t; steps = r, order = ord) end
            B = op_matrix(W) do x; evolve!(x, H, t; alg = Trotter(order = ord, steps = r)) end
            @test A ≈ B atol = 1e-13                     # same plan ⇒ same circuit
        end
        # M10 defaults reproduced by the sugar: order alone ⇒ steps = 1
        A1 = op_matrix(W) do x; evolve!(x, H, t; order = 1) end
        B1 = op_matrix(W) do x; evolve!(x, H, t; alg = Trotter(order = 1, steps = 1)) end
        @test A1 ≈ B1 atol = 1e-13
        # steps alone ⇒ order = 2
        A2 = op_matrix(W) do x; evolve!(x, H, t; steps = 2) end
        B2 = op_matrix(W) do x; evolve!(x, H, t; alg = Trotter(order = 2, steps = 2)) end
        @test A2 ≈ B2 atol = 1e-13
        # order kwarg + ε (no steps): the sugar leaves steps free, ε sizes them
        Aε = op_matrix(W) do x; evolve!(x, H, t; order = 2, ε = 1e-3) end
        Bε = op_matrix(W) do x; evolve!(x, H, t; alg = Trotter(order = 2), ε = 1e-3) end
        @test Aε ≈ Bε atol = 1e-13

        # t == 0: exact no-op
        U0 = op_matrix(W) do x; evolve!(x, H, 0.0; steps = 5) end
        @test U0 ≈ Matrix{ComplexF64}(I, 4, 4) atol = 1e-12
        # t < 0: legal backwards evolution (bounds use |t|; angles carry the sign)
        Um = op_matrix(W) do x; evolve!(x, H, -t; steps = 40) end
        @test dist_upto_phase(Um, exp(im .* ham_mat(H) .* t)) ≤ 1e-3
    end

    # =====================================================================
    #  T10 — M12.GUARDRAIL (phase-1 parts)
    # =====================================================================
    @testset "M12.GUARDRAIL — bare call, double-spec, caps, phase-2 stubs (all loud)" begin
        H = [(1.0, "ZZ"), (0.5, "XI")]
        runq(f) = eager(4) do ctx
            x = QInt{2}(0)
            f(x)
        end

        # S3 AS RULED: the bare call throws, demanding ε= or explicit resources
        @test_throws ArgumentError runq(x -> evolve!(x, H, 1.0))
        @test_throws ArgumentError runq(x -> evolve!(x, H, 1.0; alg = Trotter(order = 4)))
        # ε with nothing to influence is a caller bug (rule 5)
        @test_throws ArgumentError runq(x -> evolve!(x, H, 1.0;
                                                     alg = Trotter(order = 2, steps = 5), ε = 1e-3))
        @test_throws ArgumentError runq(x -> evolve!(x, H, 1.0; steps = 5, ε = 1e-3))
        # kwargs alongside alg is over-specified (rule 2: one spelling per meaning)
        @test_throws ArgumentError runq(x -> evolve!(x, H, 1.0; alg = Trotter(order = 2), steps = 3))
        @test_throws ArgumentError runq(x -> evolve!(x, H, 1.0; alg = Auto(), order = 2))
        # ε domain: finite, > 0
        @test_throws DomainError runq(x -> evolve!(x, H, 1.0; alg = Trotter(order = 2), ε = -1e-3))
        @test_throws DomainError runq(x -> evolve!(x, H, 1.0; alg = Trotter(order = 2), ε = 0.0))

        # eager constructor validation (B §1.1); order cap 12 loud (S11)
        @test_throws DomainError Trotter(order = 3)
        @test_throws DomainError Trotter(order = 14)
        @test_throws DomainError Trotter(order = 0)
        @test_throws DomainError Trotter(order = 2, steps = 0)
        @test_throws DomainError QDrift(N = 0)
        @test_throws DomainError Composite(order = 1)
        @test_throws DomainError Composite(order = 2, K = -1)
        @test_throws DomainError Composite(order = 2, N_B = 0)
        # M10-compat sugar errors
        @test_throws DomainError runq(x -> evolve!(x, H, 1.0; steps = 0))
        @test_throws DomainError runq(x -> evolve!(x, H, 1.0; order = 3))

        # phase-2 stubs (bead Sturm.jl-8yzf): randomized/Auto planning throws LOUD
        hs = PauliSum{2}(H)
        for alg in (QDrift(), Composite(order = 2), Auto())
            err = try
                plan_evolution(alg, hs, 1.0; ε = 1e-3)
                nothing
            catch e
                e
            end
            @test err isa ErrorException
            @test occursin("phase 2", err.msg) && occursin("8yzf", err.msg)
        end
        @test_throws ErrorException runq(x -> evolve!(x, H, 1.0; alg = QDrift(), ε = 1e-2))
        # the bare-with-ε call resolves to Auto ⇒ must hit the stub, never silently Trotter
        err = try
            runq(x -> evolve!(x, H, 1.0; ε = 1e-3))
            nothing
        catch e
            e
        end
        @test err isa ErrorException && occursin("phase 2", err.msg)
    end

    # =====================================================================
    #  Model library — ising / heisenberg / power-law constructors
    # =====================================================================
    @testset "M12.MODELS — coefficient-tail model families" begin
        hi = PauliSum{4}(ising_chain(4; J = 1.0, h = 0.5))
        @test length(hi.coeffs) == 3 + 4                  # 3 ZZ bonds + 4 X fields
        @test hi.λ ≈ 3 * 1.0 + 4 * 0.5

        hh = PauliSum{3}(heisenberg_chain(3; J = 0.7))
        @test length(hh.coeffs) == 3 * 2                  # XX, YY, ZZ per bond
        Hh2 = heisenberg_chain(2; J = 1.0)
        @test ham_mat([(p.coeff, p.word) for p in Hh2]) ≈
              word_mat("XX") + word_mat("YY") + word_mat("ZZ")

        hp = PauliSum{4}(powerlaw_chain(4; γ = 2.0, J = 1.0))
        @test length(hp.coeffs) == 6 + 4                  # all pairs ZZ + X fields
        # the 1/|i−j|^γ tail: nearest-neighbour weight 1, distance-2 weight 1/4
        @test any(c -> c ≈ 0.25, hp.coeffs)
        @test_throws DomainError ising_chain(1)
    end
end
