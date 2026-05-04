# Sign-function polynomial approximation for QSVT eigenvalue filter.
#
# Lin-Tong 2020 Lemma 3 (Polynomial approximation of the sign function):
#   For all 0 < δ < 1, 0 < ε < 1, there exists an efficiently computable
#   ODD polynomial S(·; δ, ε) ∈ ℝ[x] of degree ℓ = O((1/δ)·log(1/ε)) s.t.
#     (1) |S(x)| ≤ 1                   for all x ∈ [-1, 1]
#     (2) |S(x) - sign(x)| ≤ ε         for x ∈ [-1, -δ] ∪ [δ, 1]
#
# Bead Sturm.jl-u1er. Ground truth: docs/physics/lin_tong_2020_ground_state_prep.md
# (lands as part of this bead). Local PDF:
#   docs/literature/quantum_simulation/qsp_qsvt/2002.12508.pdf

using Test, Sturm
using Sturm: sign_polynomial, chebyshev_eval

@testset "sign_polynomial — Lin-Tong 2020 Lemma 3" begin

    # ─────────────────────────────────────────────────────────────────────
    # Shape: odd-parity Chebyshev coefficients
    # ─────────────────────────────────────────────────────────────────────

    @testset "odd parity (even coefficients vanish)" begin
        for (δ, ε) in [(0.5, 0.1), (0.2, 0.05), (0.3, 0.01)]
            c = sign_polynomial(δ, ε)
            @test eltype(c) == Float64
            @test length(c) >= 2          # at least one odd coefficient
            # Even-indexed Chebyshev coefficients must be zero (sign is odd).
            for k in 1:2:length(c)
                @test abs(c[k]) < 1e-12   # c[1] = c_0, c[3] = c_2, …
            end
        end
    end

    # ─────────────────────────────────────────────────────────────────────
    # Lemma 3 (1): |S(x)| ≤ 1 on [-1, 1]
    # ─────────────────────────────────────────────────────────────────────

    @testset "bounded by 1 on [-1, 1]" begin
        c = sign_polynomial(0.2, 0.05)
        c_cx = ComplexF64.(c)
        # Sample densely; QSP requires the bound everywhere, not just at nodes.
        for x in range(-1.0, 1.0; length=401)
            S = real(chebyshev_eval(c_cx, x))
            @test abs(S) <= 1.0 + 1e-10
        end
    end

    # ─────────────────────────────────────────────────────────────────────
    # Lemma 3 (2): |S(x) - sign(x)| ≤ ε on the plateau [-1,-δ] ∪ [δ,1]
    # ─────────────────────────────────────────────────────────────────────

    @testset "approximates sign(x) on the plateau within ε" begin
        for (δ, ε) in [(0.5, 0.1), (0.3, 0.05), (0.2, 0.02)]
            c = sign_polynomial(δ, ε)
            c_cx = ComplexF64.(c)
            # Sample inside [δ, 1] and [-1, -δ]
            for x in vcat(range(δ, 1.0; length=20), range(-1.0, -δ; length=20))
                S = real(chebyshev_eval(c_cx, x))
                @test abs(S - sign(x)) <= ε
            end
        end
    end

    # ─────────────────────────────────────────────────────────────────────
    # Lemma 3: degree scales as O((1/δ)·log(1/ε))
    # ─────────────────────────────────────────────────────────────────────

    @testset "degree scales like (1/δ)·log(1/ε)" begin
        # Halve δ → degree should at most ~double (log factor). Halve ε → degree
        # grows by a constant. Loose upper-bound check, not a tight asymptotic.
        d_loose  = length(sign_polynomial(0.4, 0.1)) - 1
        d_tight  = length(sign_polynomial(0.2, 0.1)) - 1
        d_strict = length(sign_polynomial(0.2, 0.001)) - 1

        @test d_loose < d_tight                          # smaller δ → higher degree
        @test d_tight < d_strict                         # tighter ε → higher degree
        # Sanity: should not blow up; for δ=0.2, ε=0.001 we expect ~50–200.
        @test d_strict < 1000
    end

    # ─────────────────────────────────────────────────────────────────────
    # Wire-up: feeding the polynomial through the BS-25 → Laneve-25 phase
    # pipeline. This is the "does it compose with what's already shipped"
    # check — no quantum simulation, just classical pipeline.
    # ─────────────────────────────────────────────────────────────────────

    @testset "qsvt_phases accepts sign_polynomial output (odd parity)" begin
        c = sign_polynomial(0.4, 0.1)         # small for fast test
        d = length(c) - 1
        # Sturm phase pipeline returns 2d+1 phases for odd Chebyshev parity.
        phi = qsvt_phases(c; epsilon=1e-3)
        @test length(phi) == 2d + 1
        @test all(isfinite, phi)
    end
end
