using Test
using LinearAlgebra: norm

# Import the polynomial approximation function
using Sturm: jacobi_anger_coeffs, chebyshev_eval

# ═══════════════════════════════════════════════════════════════════════════
# Test Jacobi-Anger polynomial approximation to e^{-ixt}.
#
# The Jacobi-Anger expansion:
#   e^{-ixt} = J₀(t) T₀(x) + 2 Σ_{k=1}^d (-i)^k Jₖ(t) Tₖ(x)
#
# gives a degree-d Chebyshev approximation on x ∈ [-1, 1].
#
# Ref: Martyn et al. (2021), arXiv:2105.02859, Section III.B, Eq. (29)-(30).
#      Local PDF: docs/literature/quantum_simulation/qsp_qsvt/2105.02859.pdf
# ═══════════════════════════════════════════════════════════════════════════

@testset "QSVT Polynomials" begin

    # ─────────────────────────────────────────────────────────────────────
    # 1. Jacobi-Anger coefficients have correct structure
    # ─────────────────────────────────────────────────────────────────────

    @testset "jacobi_anger_coeffs structure" begin
        t = 1.0
        d = 10
        coeffs = jacobi_anger_coeffs(t, d)
        @test length(coeffs) == d + 1  # c₀, c₁, ..., c_d
        @test coeffs isa Vector{ComplexF64}
    end

    # ─────────────────────────────────────────────────────────────────────
    # 2. Approximation matches e^{-ixt} on [-1, 1]
    # ─────────────────────────────────────────────────────────────────────

    @testset "Jacobi-Anger approximates e^{-ixt}" begin
        for t in [0.5, 1.0, 2.0, 5.0]
            # Choose degree large enough for convergence
            d = Int(ceil(abs(t) + 10 * log(10)))  # heuristic
            coeffs = jacobi_anger_coeffs(t, d)

            # Sample x on [-1, 1]
            xs = range(-1.0, 1.0, length=51)
            max_err = 0.0
            for x in xs
                approx = chebyshev_eval(coeffs, x)
                exact = exp(-im * x * t)
                max_err = max(max_err, abs(approx - exact))
            end
            @test max_err < 1e-10
        end
    end

    # ─────────────────────────────────────────────────────────────────────
    # 3. Degree-0: constant approximation (t ≈ 0)
    # ─────────────────────────────────────────────────────────────────────

    @testset "t=0 gives identity (all coeffs ≈ 0 except c₀=1)" begin
        coeffs = jacobi_anger_coeffs(0.0, 5)
        @test abs(coeffs[1] - 1.0) < 1e-14  # J₀(0) = 1
        for k in 2:6
            @test abs(coeffs[k]) < 1e-14      # Jₖ(0) = 0 for k ≥ 1
        end
    end

    # ─────────────────────────────────────────────────────────────────────
    # 4. chebyshev_eval at x=1 and x=-1 (boundary)
    # ─────────────────────────────────────────────────────────────────────

    @testset "boundary evaluation x=±1" begin
        t = 2.0
        d = 30
        coeffs = jacobi_anger_coeffs(t, d)

        # e^{-i·1·t} = e^{-2i}
        @test abs(chebyshev_eval(coeffs, 1.0) - exp(-im * t)) < 1e-10
        # e^{-i·(-1)·t} = e^{2i}
        @test abs(chebyshev_eval(coeffs, -1.0) - exp(im * t)) < 1e-10
    end

    # ─────────────────────────────────────────────────────────────────────
    # 5. |P(x)| ≤ 1 for all x ∈ [-1, 1] (unitarity constraint for QSP)
    # ─────────────────────────────────────────────────────────────────────

    @testset "|P(x)| ≤ 1 on [-1,1]" begin
        t = 3.0
        d = 40
        coeffs = jacobi_anger_coeffs(t, d)

        xs = range(-1.0, 1.0, length=201)
        for x in xs
            @test abs(chebyshev_eval(coeffs, x)) ≤ 1.0 + 1e-12
        end
    end

end
