using Test
using LinearAlgebra: norm
using Sturm: jacobi_anger_coeffs, chebyshev_eval,
             complementary_polynomial

# ═══════════════════════════════════════════════════════════════════════════
# Test the QSP phase factor pipeline:
#   Step 1: Berntson-Sunderhauf completion (P -> Q)
#   Step 2: Weiss algorithm (b -> c_hat)
#   Step 3: RHW factorization (c_hat -> F_k)
#   Step 4: Phase extraction (F_k -> GQSP angles)
#
# Ref: Berntson, Sunderhauf (2025), CMP 406:161, Algorithm 1.
#      Laneve (2025), arXiv:2503.03026, Theorem 9.
# ═══════════════════════════════════════════════════════════════════════════

@testset "QSP Phase Factors" begin

    # ─────────────────────────────────────────────────────────────────────
    # Step 1: Berntson-Sunderhauf completion (P -> Q)
    # ─────────────────────────────────────────────────────────────────────

    @testset "complementary_polynomial: |P|² + |Q|² ≈ 1 on [-1,1]" begin
        # Use Jacobi-Anger polynomial for t=1.0, degree 20.
        # P and Q are in Chebyshev basis: P(x) = Σ cₖ Tₖ(x).
        # Internally converts to analytic convention for BS algorithm.
        t = 1.0
        d = 20
        P_coeffs = jacobi_anger_coeffs(t, d)

        Q_coeffs = complementary_polynomial(P_coeffs)
        @test length(Q_coeffs) == d + 1

        # Verify complementarity on x ∈ [-1, 1] via Chebyshev evaluation
        max_err = 0.0
        for x in range(-1.0, 1.0, length=201)
            Px = chebyshev_eval(P_coeffs, x)
            Qx = chebyshev_eval(Q_coeffs, x)
            err = abs(abs2(Px) + abs2(Qx) - 1.0)
            if err > max_err; max_err = err; end
        end
        @test max_err < 1e-6
    end

    @testset "complementary_polynomial: degree matches P" begin
        for (t, d) in [(0.5, 10), (2.0, 30), (0.1, 5)]
            P = jacobi_anger_coeffs(t, d)
            Q = complementary_polynomial(P)
            @test length(Q) == length(P)
        end
    end

    @testset "complementary_polynomial: Q for trivial P (small t)" begin
        # For t ≈ 0, P ≈ [1, 0, 0, ...], so |P(z)| ≈ 1 everywhere,
        # and Q ≈ 0 (since |P|² + |Q|² = 1 and |P| ≈ 1).
        # But wait: P_0 = J_0(0) = 1, so P(z) = 1 for all z.
        # Then |P|² = 1 and Q must be 0. But 1-|P|² = 0, log(0) = -∞.
        # This is the delta=0 case. Skip t=0, test t=0.01 (small delta).
        P = jacobi_anger_coeffs(0.01, 10)
        Q = complementary_polynomial(P)
        # Q should be small (since P is close to constant 1)
        @test all(abs.(Q) .< 0.1)
    end

    @testset "complementary_polynomial: multiple t values" begin
        for t in [0.5, 1.0, 2.0, 3.0, 5.0]
            d = Int(ceil(abs(t) + 15 * log(10)))
            P = jacobi_anger_coeffs(t, d)
            Q = complementary_polynomial(P)

            # Spot-check at 5 points on x ∈ [-1, 1] via Chebyshev evaluation
            for x in [-1.0, -0.5, 0.0, 0.5, 1.0]
                Px = chebyshev_eval(P, x)
                Qx = chebyshev_eval(Q, x)
                @test abs(abs2(Px) + abs2(Qx) - 1.0) < 1e-4
            end
        end
    end

end
