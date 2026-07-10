# SPDX-License-Identifier: AGPL-3.0-only
#
# M2 tests (bead Sturm.jl-dc6i): the Ad application kernel — ZYZ extraction, the
# ABC controlled decomposition, sqrt_u2, multi-control ladders, Perm replay.
# Every check is against the M1 `denoted_matrix` reference. Uncontrolled Ad
# drops the global phase (ker Ad = U(1)) ⇒ `approx_upto_phase`; the phase-EXACT
# controlled decompositions compare exactly.
#
# Physics: docs/physics/barenco_1995_elementary_gates.md (Lemmas 4.1/4.3/5.1/5.2,
# Cor 5.3, Lemma 6.1, Cor 7.12); tang_wright (Thm 1.1, the ctrl(−I)≠ctrl(I) gate);
# stuelpnagel (chart singularity).

# (helpers from test_m2_common.jl are already in scope via runtests.jl)

@testset "Ad application kernel (M2)" begin

    @testset "ZYZ round-trip fuzz (uncontrolled U2, up to global phase)" begin
        rng = MersenneTwister(4242)
        n = 3000   # trimmed from 10^4 for suite wall-time; poles tested explicitly below
        ok = 0
        for _ in 1:n
            u = rand_u2(rng)
            approx_upto_phase(realized_matrix(u), denoted_matrix(u); atol=1e-7) && (ok += 1)
        end
        @test ok == n
    end

    @testset "ZYZ explicit poles + axis-degenerate cases (D7 chart singularity)" begin
        # β≈0 (diagonal) and β≈π (antidiagonal) folds, θ ∈ {0, π, ±1e-9, ±1e-13}.
        for θ in (0.0, Float64(π), 1e-9, -1e-9, 1e-13, -1e-13, 2π)
            for g in (Ry(θ), Rz(θ), Rx(θ))
                @test approx_upto_phase(realized_matrix(g), denoted_matrix(g); atol=1e-6)
            end
        end
        # exact diagonal / antidiagonal
        @test approx_upto_phase(realized_matrix(Z), denoted_matrix(Z); atol=1e-9)   # β=0
        @test approx_upto_phase(realized_matrix(X), denoted_matrix(X); atol=1e-9)   # β=π
        @test approx_upto_phase(realized_matrix(Y), denoted_matrix(Y); atol=1e-9)   # β=π
        # no NaN escapes the fold (a NaN would fail the matrix compare, but assert finiteness)
        @test all(isfinite, realized_matrix(Ry(1e-12)))
        @test all(isfinite, realized_matrix(Ry(Float64(π) - 1e-12)))
    end

    @testset "sqrt_u2 — V∘V ≈ u fuzz + w≈−1 branch" begin
        rng = MersenneTwister(0xBEEF)
        n = 3000
        ok = 0
        for _ in 1:n
            u = rand_u2(rng)
            (sqrt_u2(u) ∘ sqrt_u2(u) ≈ u) && (ok += 1)
        end
        @test ok == n
        # the free-axis branch: u = −I exactly
        @test sqrt_u2(NEG_I) ∘ sqrt_u2(NEG_I) ≈ NEG_I
        @test sqrt_u2(I2) ∘ sqrt_u2(I2) ≈ I2
        # near-pole (w near −1 but with a real axis) uses the general formula
        @test sqrt_u2(Ry(2π - 1e-6)) ∘ sqrt_u2(Ry(2π - 1e-6)) ≈ Ry(2π - 1e-6)
    end

    @testset "controlled decomposition k∈{1,2,3} (phase-EXACT vs denoted_matrix)" begin
        rng = MersenneTwister(555)
        for _ in 1:200
            u = rand_u2(rng)                       # nonzero φ in general
            for (k, c) in ((1, ctrl(u)), (2, ctrl(ctrl(u))), (3, ctrl(ctrl(ctrl(u)))))
                cap = nwires(c) + max(0, k - 1)    # room for k−1 scratch ancillas
                @test isapprox(realized_matrix(c; capacity=cap), denoted_matrix(c); atol=1e-8)
            end
        end
    end

    @testset "native controlled Paulis (cx/cy/cz/ccx exact)" begin
        @test isapprox(realized_matrix(ctrl(X)), denoted_matrix(ctrl(X)); atol=1e-9)
        @test isapprox(realized_matrix(ctrl(Y)), denoted_matrix(ctrl(Y)); atol=1e-9)
        @test isapprox(realized_matrix(ctrl(Z)), denoted_matrix(ctrl(Z)); atol=1e-9)
        @test isapprox(realized_matrix(ctrl(ctrl(X))), denoted_matrix(ctrl(ctrl(X))); atol=1e-9)
    end

    @testset "PHASE-EXACTNESS gates (the whole point — Tang–Wright Thm 1.1)" begin
        # ctrl(gphase(α)) lowers to a bare p(control, α) = diag(1,1,e^{iα},e^{iα}).
        for α in (0.3, 1.0, 2.5, -0.7)
            cg = ctrl(gphase(α))
            @test isapprox(realized_matrix(cg), denoted_matrix(cg); atol=1e-9)
            @test isapprox(realized_matrix(cg), ComplexF64[1 0 0 0; 0 1 0 0; 0 0 cis(α) 0; 0 0 0 cis(α)]; atol=1e-9)
        end
        # ctrl(−I) = diag(1,1,−1,−1) ≠ ctrl(I) = I₄ — the separating example.
        cn = realized_matrix(ctrl(NEG_I))
        ci = realized_matrix(ctrl(I2))
        @test isapprox(cn, denoted_matrix(ctrl(NEG_I)); atol=1e-9)
        @test isapprox(ci, denoted_matrix(ctrl(I2)); atol=1e-9)
        @test !approx_upto_phase(cn, ci)          # visibly different operators
        # nonzero-φ inner under a further control (k=2): dropping p(φ) would show
        u = gphase(0.9) ∘ Ry(0.5)                 # a genuine e^{iφ}·SU(2)
        c2 = ctrl(ctrl(u))
        @test isapprox(realized_matrix(c2), denoted_matrix(c2); atol=1e-8)
    end

    @testset "Perm replay (MCX → x/cx/ccx/ladder), incl. k≥3 ladder" begin
        # bare X, CNOT, Toffoli, and a 3- and 4-control MCX.
        @test isapprox(realized_matrix(Perm(1, [MCX(Int[], 1)])), denoted_matrix(Perm(1, [MCX(Int[], 1)])); atol=1e-9)
        @test isapprox(realized_matrix(Perm(2, [MCX([1], 2)])), denoted_matrix(Perm(2, [MCX([1], 2)])); atol=1e-9)
        @test isapprox(realized_matrix(Perm(3, [MCX([1, 2], 3)])), denoted_matrix(Perm(3, [MCX([1, 2], 3)])); atol=1e-9)
        p3 = Perm(4, [MCX([1, 2, 3], 4)])
        @test isapprox(realized_matrix(p3; capacity=4 + 2), denoted_matrix(p3); atol=1e-9)
        p4 = Perm(5, [MCX([1, 2, 3, 4], 5)])
        @test isapprox(realized_matrix(p4; capacity=5 + 3), denoted_matrix(p4); atol=1e-9)
        # a multi-generator Perm (compose two MCX)
        pc = Perm(3, [MCX([1], 3), MCX([2], 3)])
        @test isapprox(realized_matrix(pc), denoted_matrix(pc); atol=1e-9)
        # controlled Perm leaf via a Tensor under ctrl
        cpt = ctrl(Perm(2, [MCX([1], 2)]) ⊗ I2)
        @test isapprox(realized_matrix(cpt; capacity=nwires(cpt)), denoted_matrix(cpt); atol=1e-9)
    end

    @testset "structural recursion: Tensor (uncontrolled) & Seq & Ctrl{Seq}" begin
        rng = MersenneTwister(31337)
        for _ in 1:50
            a = rand_u2(rng); b = rand_u2(rng)
            @test approx_upto_phase(realized_matrix(a ⊗ b), denoted_matrix(a ⊗ b); atol=1e-7)
        end
        # Ctrl{Tensor}: one shared control gating both factors (Delorme).
        ct = ctrl(X ⊗ Z)
        @test isapprox(realized_matrix(ct), denoted_matrix(ct); atol=1e-9)
        # Ctrl{Seq}: control homomorphism over ∘.
        s = Ry(0.7) ∘ Rx(0.3)             # a genuine Seq? no — U2∘U2 fuses. Force a Seq:
        seq = (X ⊗ I2) ∘ (H ⊗ Z)          # Tensor∘Tensor → Seq (generic fallback)
        @test approx_upto_phase(realized_matrix(seq), denoted_matrix(seq); atol=1e-7)
        cseq = ctrl(seq)
        @test isapprox(realized_matrix(cseq; capacity=nwires(cseq)), denoted_matrix(cseq); atol=1e-8)
    end

    @testset "no apply! catch-all (P4): unhandled kinds are MethodError-adjacent" begin
        # A U2 to the wrong wire count fails loud (not a silent wrong emission).
        eager(1) do ctx
            w = allocate!(ctx)
            @test_throws ErrorException apply!(ctx, X ⊗ Z, (w,))   # 2-wire value, 1 wire
        end
    end
end
