using Test
using LinearAlgebra: norm
using FFTW: ifft, fft
using Sturm: jacobi_anger_coeffs, chebyshev_eval,
             complementary_polynomial,
             chebyshev_to_analytic,
             weiss, _weiss_schwarz,
             rhw_factorize,
             extract_phases, QSVTPhases

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

    # ─────────────────────────────────────────────────────────────────────
    # Step 2: Weiss algorithm (b → ĉ = Fourier coeffs of b/a)
    # Ref: Laneve 2025, arXiv:2503.03026, Algorithm 1, Section 5.1.
    # ─────────────────────────────────────────────────────────────────────

    @testset "weiss: N size formula" begin
        # Algorithm 1 line 1: N = nextpow2(max(⌈(8n/η)·log(576n²/(η⁴ε))⌉, 2(n+1)))
        # We test indirectly: weiss must accept valid inputs and return
        # correct-length output of correct type.
        b = ComplexF64[0.0, 0.05im, 0.0]  # b(z) = 0.05i·z, n=2, tiny
        c_hat = weiss(b, 0.9, 1e-6)
        @test length(c_hat) == length(b)
        @test c_hat isa Vector{ComplexF64}
    end

    @testset "weiss: trivial b=0 gives c_hat=0" begin
        b = zeros(ComplexF64, 5)  # b(z) = 0
        c_hat = weiss(b, 0.99, 1e-10)
        @test length(c_hat) == 5
        @test all(abs.(c_hat) .< 1e-10)
    end

    @testset "weiss: small b gives c_hat ≈ b (first order)" begin
        # For small ||b||, a ≈ 1, so b/a ≈ b.
        eps_val = 1e-4
        b = ComplexF64[0.0, eps_val * im, 0.0, 0.0]  # b = ε·i·z
        c_hat = weiss(b, 1.0 - eps_val, 1e-12)
        @test length(c_hat) == 4
        # c_hat should approximate b to O(ε³)
        @test abs(c_hat[1]) < 1e-6   # c_hat_0 ≈ 0
        @test abs(c_hat[2] - eps_val * im) < eps_val^2  # c_hat_1 ≈ ε·i
        @test abs(c_hat[3]) < 1e-6   # c_hat_2 ≈ 0
        @test abs(c_hat[4]) < 1e-6   # c_hat_3 ≈ 0
    end

    @testset "weiss: Schwarz identity Re(G*) = R on 𝕋" begin
        # The fundamental Schwarz identity: the outer function G satisfies
        # Re(G(z)) = R(z) on 𝕋, so Re(G*(z)) = Re(conj(G(z))) = Re(G(z)) = R.
        # _weiss_schwarz exposes G_vals and R_vals for testing.
        b = ComplexF64[0.0, 0.3im, 0.1, 0.0, 0.0]  # moderate b
        R_vals, G_vals, _, _ = _weiss_schwarz(b, 0.5, 1e-10)
        G_star_vals = conj.(G_vals)

        # Re(G*) should equal R at every root of unity
        max_err = maximum(abs.(real.(G_star_vals) .- R_vals))
        @test max_err < 1e-10
    end

    @testset "weiss: |a|² + |b|² = 1 identity" begin
        # a = e^{G*}, so |a|² = e^{2·Re(G*)} = e^{2R} = 1-|b|².
        # This is the fundamental identity that Weiss relies on.
        b = ComplexF64[0.0, 0.2 + 0.1im, 0.05im, 0.0]  # complex b
        R_vals, G_vals, b_vals, _ = _weiss_schwarz(b, 0.6, 1e-10)

        # a = exp(G*), |a|² + |b|² should be 1
        a_vals = exp.(conj.(G_vals))
        identity_err = maximum(abs.(abs2.(a_vals) .+ abs2.(b_vals) .- 1.0))
        @test identity_err < 1e-10
    end

    @testset "weiss: c_hat reconstructs b from a (ĉ·a ≈ b)" begin
        # ĉ = Fourier(b/a) truncated to degree n. Multiplying the truncated
        # ĉ polynomial by a recovers b approximately — the approximation
        # quality depends on how much of b/a falls outside [0, n].
        # For moderate-norm b, error ≈ O(||b||²) from higher-order terms.
        b = ComplexF64[0.0, 0.2im, 0.1 + 0.05im, 0.0, 0.0]  # degree 4
        eta = 0.5
        eps_prec = 1e-10
        c_hat = weiss(b, eta, eps_prec)

        # Recover a from Schwarz to verify reconstruction
        R_vals, G_vals, b_vals, N = _weiss_schwarz(b, eta, eps_prec)
        a_vals = exp.(conj.(G_vals))

        # Evaluate c_hat at roots of unity
        n = length(c_hat) - 1
        c_padded = zeros(ComplexF64, N)
        c_padded[1:n+1] .= c_hat
        c_vals = ifft(c_padded) .* N

        # Pointwise: c_hat(z) · a(z) ≈ b(z) (truncation error ≈ 1e-3)
        recon_err = maximum(abs.(c_vals .* a_vals .- b_vals))
        @test recon_err < 1e-2
    end

    @testset "weiss: output is finite and correct length" begin
        b = ComplexF64[0.0, 0.15im, 0.08, 0.02im, 0.0, 0.0]  # degree 5
        c_hat = weiss(b, 0.7, 1e-10)
        @test length(c_hat) == 6
        @test all(isfinite.(c_hat))
    end

    @testset "weiss: small b gives near-zero c_hat for zero coefficients" begin
        # For very small ||b||, a ≈ 1, so ĉ ≈ b. Zero entries in b
        # should map to near-zero entries in ĉ.
        b = ComplexF64[0.0, 1e-6im, 0.0, 0.0]
        c_hat = weiss(b, 1.0 - 1e-6, 1e-12)
        @test abs(c_hat[1]) < 1e-10   # ĉ_0 ≈ b_0 = 0
        @test abs(c_hat[3]) < 1e-10   # ĉ_2 ≈ b_2 = 0
        @test abs(c_hat[4]) < 1e-10   # ĉ_3 ≈ b_3 = 0
    end

    @testset "weiss: Jacobi-Anger pipeline integration" begin
        # Full pipeline: jacobi_anger_coeffs → chebyshev_to_analytic → b=-iP → weiss
        # For real target P(x) ≈ e^{-ixt}, set b = -iP (Section 4.3 convention).
        # Verify: |a|² + |b|² = 1 and ĉ is finite with correct length.
        for (t, d) in [(0.5, 10), (1.0, 20), (2.0, 30)]
            P_cheb = jacobi_anger_coeffs(t, d)
            P_analytic = chebyshev_to_analytic(P_cheb)
            b_raw = -im .* P_analytic  # b = -iP (Laneve Section 4.3)

            # Estimate ||b||_∞ on 𝕋 via FFT, then downscale to create gap.
            # chebyshev_to_analytic can push ||P_a|| above 1 on 𝕋 even
            # when |P| ≤ 1 on [-1,1], so must check on the circle directly.
            N_est = nextpow(2, max(1024, 4 * length(b_raw)))
            b_pad = zeros(ComplexF64, N_est)
            b_pad[1:length(b_raw)] .= b_raw
            b_est = ifft(b_pad) .* N_est
            max_b = sqrt(maximum(abs2.(b_est)))
            scale = 0.9 / max(max_b, 1.0)  # ensure ||b_scaled||_∞ ≤ 0.9
            b_scaled = b_raw .* scale
            eta = 0.1  # guaranteed gap

            c_hat = weiss(b_scaled, eta, 1e-8)

            n_analytic = length(b_scaled) - 1
            @test length(c_hat) == n_analytic + 1
            @test all(isfinite.(c_hat))

            # Verify fundamental identity |a|² + |b|² = 1 via Schwarz
            R_vals, G_vals, b_vals, N = _weiss_schwarz(b_scaled, eta, 1e-8)
            a_vals = exp.(conj.(G_vals))
            identity_err = maximum(abs.(abs2.(a_vals) .+ abs2.(b_vals) .- 1.0))
            @test identity_err < 1e-8
        end
    end

    @testset "weiss: purely imaginary b from real Chebyshev P" begin
        # For a REAL polynomial P (e.g., cos approximation: even-k Chebyshev
        # terms), b = -iP is purely imaginary. Jacobi-Anger gives complex P
        # (mixed cos+sin), so extract only the real-coefficient part.
        #
        # Real Chebyshev P: c_k real for all k.
        # Then P_analytic is real, and b = -i·P_analytic is purely imaginary.
        # P(x) = 0.5 - 0.2·T₂(x) + 0.05·T₄(x) → max|P|=0.75 at x=0.
        P_cheb = ComplexF64[0.5, 0.0, -0.2, 0.0, 0.05]  # real, ||P||_∞ < 1
        P_analytic = chebyshev_to_analytic(P_cheb)
        @test all(abs.(imag.(P_analytic)) .< 1e-15)  # P_analytic is real

        b = -im .* P_analytic .* 0.9  # downscaled, purely imaginary
        @test all(abs.(real.(b)) .< 1e-15)  # b is purely imaginary

        eta = 0.1
        c_hat = weiss(b, eta, 1e-10)
        @test length(c_hat) == length(b)
        @test all(isfinite.(c_hat))
    end

    @testset "weiss: complex Jacobi-Anger b (full e^{-ixt})" begin
        # Jacobi-Anger gives complex P (c_k = 2(-i)^k J_k(t)).
        # b = -iP is also complex. Weiss should handle this correctly.
        # Use scale=0.75 to create generous gap (analytic conversion can
        # amplify norm on 𝕋 relative to [-1,1]).
        P_cheb = jacobi_anger_coeffs(1.0, 15)
        P_analytic = chebyshev_to_analytic(P_cheb)
        b = -im .* P_analytic .* 0.75  # generous downscaling
        eta = 0.25

        c_hat = weiss(b, eta, 1e-10)
        @test length(c_hat) == length(b)
        @test all(isfinite.(c_hat))
    end

    @testset "weiss: multiple complex b polynomials" begin
        # Test with various complex b polynomials (not just imaginary)
        for (b, eta) in [
            (ComplexF64[0.1 + 0.2im, 0.05 - 0.1im, 0.0], 0.6),
            (ComplexF64[0.0, 0.0, 0.3im, 0.0, 0.0, 0.0], 0.5),
            (ComplexF64[0.1, 0.1, 0.1, 0.1, 0.1], 0.3),
        ]
            c_hat = weiss(b, eta, 1e-10)
            @test length(c_hat) == length(b)
            @test all(isfinite.(c_hat))

            # Verify |a|² + |b|² = 1
            R_vals, G_vals, b_vals, _ = _weiss_schwarz(b, eta, 1e-10)
            a_vals = exp.(conj.(G_vals))
            identity_err = maximum(abs.(abs2.(a_vals) .+ abs2.(b_vals) .- 1.0))
            @test identity_err < 1e-8
        end
    end

    @testset "weiss: input validation (fail fast)" begin
        # Empty b
        @test_throws ErrorException weiss(ComplexF64[], 0.5, 1e-10)
        # eta <= 0
        @test_throws ErrorException weiss(ComplexF64[0.1], 0.0, 1e-10)
        @test_throws ErrorException weiss(ComplexF64[0.1], -0.1, 1e-10)
        # epsilon <= 0
        @test_throws ErrorException weiss(ComplexF64[0.1], 0.5, 0.0)
        @test_throws ErrorException weiss(ComplexF64[0.1], 0.5, -1e-10)
    end

    # ─────────────────────────────────────────────────────────────────────
    # Step 3: RHW factorization (ĉ → F_k, the NLFT sequence)
    # Ref: Laneve 2025, arXiv:2503.03026, Algorithm 2, Section 5.2.
    # ─────────────────────────────────────────────────────────────────────

    @testset "rhw: trivial b=0 gives F_k=0" begin
        b = zeros(ComplexF64, 4)
        F = rhw_factorize(b, 0.99, 1e-10)
        @test length(F) == 4
        @test all(abs.(F) .< 1e-10)
    end

    @testset "rhw: b=αz gives F_0=0, F_1=α/√(1-|α|²)" begin
        # Exact closed form: for b(z) = αz (degree 1 monomial),
        # F_0 = 0, F_1 = α/√(1-|α|²).
        # Ref: NLFT Definition 3 + manual computation.
        α = 0.3im
        b = ComplexF64[0.0, α]
        eta = 1.0 - abs(α) - 0.01  # gap
        F = rhw_factorize(b, eta, 1e-10)

        @test length(F) == 2
        expected_F1 = α / sqrt(1 - abs2(α))
        @test abs(F[1]) < 1e-6          # F_0 ≈ 0
        @test abs(F[2] - expected_F1) < 1e-6  # F_1 ≈ α/√(1-|α|²)
    end

    @testset "rhw: NLFT roundtrip (F_k → b(z))" begin
        # Compute forward NLFT of F, verify (1,2) entry ≈ b(z) at test points.
        # Forward NLFT: G_F(z) = Π_k 1/√(1+|F_k|²) [1, F_k z^k; -F̄_k z^{-k}, 1]
        # The (1,2) entry of G_F(z) should equal b(z).
        b = ComplexF64[0.0, 0.2im, 0.1, 0.0]  # degree 3
        F = rhw_factorize(b, 0.5, 1e-10)
        @test length(F) == 4

        # Forward NLFT at test points on 𝕋
        for θ in [0.0, π/4, π/2, π, 3π/2]
            z = exp(im * θ)
            # Accumulate product G_F(z)
            G = ComplexF64[1 0; 0 1]
            for k in 0:length(F)-1
                Fk = F[k+1]
                zk = z^k
                s = 1.0 / sqrt(1.0 + abs2(Fk))
                Ak = s .* ComplexF64[1 Fk*zk; -conj(Fk)/zk 1]
                G = G * Ak
            end
            # (1,2) entry should ≈ b(z)
            bz = sum(b[j+1] * z^j for j in 0:length(b)-1)
            @test abs(G[1,2] - bz) < 1e-4
        end
    end

    @testset "rhw: Jacobi-Anger pipeline → F_k → NLFT roundtrip" begin
        # Full pipeline: Jacobi-Anger → analytic → b=-iP → RHW → F_k → NLFT → b'
        for (t, d) in [(0.5, 8), (1.0, 12)]
            P_cheb = jacobi_anger_coeffs(t, d)
            P_analytic = chebyshev_to_analytic(P_cheb)
            b_raw = -im .* P_analytic

            # Downscale: estimate ||b||_∞ on 𝕋, then create gap
            N_est = nextpow(2, max(1024, 4 * length(b_raw)))
            bp = zeros(ComplexF64, N_est)
            bp[1:length(b_raw)] .= b_raw
            bv = ifft(bp) .* N_est
            max_b = sqrt(maximum(abs2.(bv)))
            scale = 0.85 / max(max_b, 1.0)
            b_scaled = b_raw .* scale
            eta = 0.15

            F = rhw_factorize(b_scaled, eta, 1e-8)
            @test length(F) == length(b_scaled)
            @test all(isfinite.(F))

            # NLFT roundtrip at 5 points on 𝕋
            n_b = length(b_scaled) - 1
            for θ in [0.0, π/3, π/2, π, 5π/3]
                z = exp(im * θ)
                G = ComplexF64[1 0; 0 1]
                for k in 0:n_b
                    Fk = F[k+1]
                    zk = z^k
                    s = 1.0 / sqrt(1.0 + abs2(Fk))
                    Ak = s .* ComplexF64[1 Fk*zk; -conj(Fk)/zk 1]
                    G = G * Ak
                end
                bz = sum(b_scaled[j+1] * z^j for j in 0:n_b)
                @test abs(G[1,2] - bz) < 1e-3
            end
        end
    end

    @testset "rhw: multiple small polynomials" begin
        for (b, eta) in [
            (ComplexF64[0.1im, 0.05, 0.0], 0.8),
            (ComplexF64[0.0, 0.0, 0.2im], 0.7),
            (ComplexF64[0.05, 0.05, 0.05, 0.05], 0.5),
        ]
            F = rhw_factorize(b, eta, 1e-10)
            @test length(F) == length(b)
            @test all(isfinite.(F))
        end
    end

    @testset "rhw: input validation" begin
        @test_throws ErrorException rhw_factorize(ComplexF64[], 0.5, 1e-10)
        @test_throws ErrorException rhw_factorize(ComplexF64[0.1], 0.0, 1e-10)
        @test_throws ErrorException rhw_factorize(ComplexF64[0.1], 0.5, 0.0)
    end

    # ─────────────────────────────────────────────────────────────────────
    # Step 4: Phase extraction (F_k → GQSP angles λ, φ_k, θ_k)
    # Ref: Laneve 2025, arXiv:2503.03026, Theorem 9 Eq (4), Section 4.1.
    # ─────────────────────────────────────────────────────────────────────

    @testset "extract_phases: F_k=0 gives trivial phases" begin
        F = zeros(ComplexF64, 5)
        phases = extract_phases(F)
        @test phases isa QSVTPhases
        @test phases.degree == 4
        @test abs(phases.lambda) < 1e-15
        @test all(abs.(phases.phi) .< 1e-15)
        @test all(abs.(phases.theta) .< 1e-15)
    end

    @testset "extract_phases: purely imaginary F (Hamiltonian sim case)" begin
        # F_k ∈ iℝ → ψ_k = 0 → λ=0, θ_k=0, φ_k=arctan(Im(F_k))
        F = ComplexF64[0.0, 0.5im, -0.3im, 0.1im]
        phases = extract_phases(F)
        @test abs(phases.lambda) < 1e-12
        @test all(abs.(phases.theta) .< 1e-12)
        # φ_k = arctan(-i·F_k) = arctan(Im(F_k)) since ψ_k=0
        @test abs(phases.phi[1] - atan(0.0)) < 1e-12
        @test abs(phases.phi[2] - atan(0.5)) < 1e-12
        @test abs(phases.phi[3] - atan(-0.3)) < 1e-12
        @test abs(phases.phi[4] - atan(0.1)) < 1e-12
    end

    @testset "extract_phases: canonical condition λ + Σθ_k = 0" begin
        # Eq (5): canonical GQSP requires λ + Σ_{k=0}^n θ_k = 0.
        for F in [
            ComplexF64[0.3im, -0.2im, 0.1im],
            ComplexF64[0.1 + 0.2im, 0.05 - 0.1im],
            ComplexF64[0.4, -0.3im, 0.0, 0.1 + 0.05im],
        ]
            phases = extract_phases(F)
            canonical_sum = phases.lambda + sum(phases.theta)
            @test abs(canonical_sum) < 1e-12
        end
    end

    @testset "extract_phases: GQSP protocol reconstructs (P,Q)" begin
        # Build the full GQSP protocol matrix from phases and verify
        # it matches the NLFT of F at test points on 𝕋.
        # Protocol: e^{iλZ} · A₀ · W · A₁ · W · ··· · W · Aₙ |0⟩ = (P, Q)
        # where A_k = e^{iφ_k X}·e^{iθ_k Z}, W = diag(z, 1)
        F = ComplexF64[0.0, 0.3im, -0.15im]  # degree 2
        phases = extract_phases(F)

        for θ in [0.0, π/3, π, 5π/3]
            z = exp(im * θ)
            W = ComplexF64[z 0; 0 1]

            # Build GQSP protocol matrix
            eZ(α) = ComplexF64[exp(im*α) 0; 0 exp(-im*α)]
            eX(α) = let c=cos(α), s=sin(α)
                ComplexF64[c im*s; im*s c]
            end

            M = eZ(phases.lambda)  # initial e^{iλZ}
            for k in 0:phases.degree
                Ak = eX(phases.phi[k+1]) * eZ(phases.theta[k+1])
                M = M * Ak
                if k < phases.degree
                    M = M * W  # interleave oracle
                end
            end

            # Forward NLFT for comparison
            G = ComplexF64[1 0; 0 1]
            for k in 0:length(F)-1
                Fk = F[k+1]
                s = 1.0 / sqrt(1.0 + abs2(Fk))
                Ak_nlft = s .* ComplexF64[1 Fk*z^k; -conj(Fk)/z^k 1]
                G = G * Ak_nlft
            end

            # The GQSP protocol on |0⟩ gives (P, Q) as first column of M.
            # The NLFT gives [z^n·a, b; ...] as G.
            # Compare (1,2) entries: both should give b(z).
            @test abs(M[1,2] - G[1,2]) < 1e-4
        end
    end

    @testset "extract_phases: full pipeline b → F → phases" begin
        # b → RHW → F → extract_phases → QSVTPhases
        α = 0.25im
        b = ComplexF64[0.0, α]
        F = rhw_factorize(b, 0.7, 1e-10)
        phases = extract_phases(F)

        @test phases isa QSVTPhases
        @test phases.degree == 1
        @test all(isfinite.(phases.phi))
        @test all(isfinite.(phases.theta))
        @test isfinite(phases.lambda)
        # Canonical condition
        @test abs(phases.lambda + sum(phases.theta)) < 1e-10
    end

end
