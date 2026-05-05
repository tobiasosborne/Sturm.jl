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
using Sturm: sign_polynomial, chebyshev_eval,
             PauliHamiltonian, PauliTerm, pauli_I, pauli_Z,
             block_encode_lcu, qsvt_reflect!, qsvt_phases

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

    # ─────────────────────────────────────────────────────────────────────
    # End-to-end: QSVT applies S(H/α) ≈ sign(H) to a block-encoded H = Z.
    # Eigenvalues ±1 lie inside the plateau [δ, 1] for δ = 0.5, so
    #   sign(Z)|+⟩ = (|0⟩ - |1⟩)/√2 = |-⟩
    # which we detect by rotating to the Z-basis (Hadamard via primitives)
    # and measuring outcome 1.
    # ─────────────────────────────────────────────────────────────────────

    @testset "qsvt_reflect! · sign_polynomial: phase flip on |1⟩ branch (H=Z)" begin
        # Build H = Z as a 1-qubit PauliHamiltonian directly. ising/heisenberg
        # both demand N ≥ 2 — for the simplest verifiable demo we go to the
        # primitives.
        H = PauliHamiltonian{1}([PauliTerm{1}(1.0, (pauli_Z,))])
        be = block_encode_lcu(H)
        @test be.alpha ≈ 1.0                # α = |coeff| = 1, so H/α = Z
        @test be.n_system == 1

        # Sign polynomial on the plateau [0.5, 1]: eigenvalues ±1 are well
        # inside, ε=0.05 leaves room for stochastic verification.
        cheb = sign_polynomial(0.5, 0.05)
        phi  = qsvt_phases(cheb; epsilon=1e-3)
        d    = length(cheb) - 1
        @test length(phi) == 2d + 1            # odd parity → 2d+1

        # Statistical end-to-end. Initial state |+⟩ on the system qubit.
        # After QSVT (post-selected): state is approximately |-⟩.
        # Rotate to Z-basis with the primitive form of Hadamard
        # (q.φ += π; q.θ += π/2) and measure — expect outcome 1.
        N_shots   = 400
        n_success = 0
        n_one     = 0

        for _ in 1:N_shots
            ctx = EagerContext()
            @context ctx begin
                # |+⟩ via the P2 preparation cast (equal superposition)
                sys = [QBool(ctx, 0.5)]
                success = qsvt_reflect!(sys, be, phi)
                if success
                    n_success += 1
                    # Hadamard via the rotation primitives — no named gate.
                    sys[1].φ += π
                    sys[1].θ += π / 2
                    if Bool(sys[1])
                        n_one += 1
                    end
                else
                    for s in sys; discard!(s); end
                end
            end
        end

        # Post-selection: |P(eigval)|² ≈ 1 for both ±1 eigenvalues, so we
        # expect a high success rate. Tolerate noise: ≥ 50% suffices to make
        # the next test statistically meaningful.
        @test n_success > N_shots ÷ 2

        if n_success > N_shots ÷ 2
            # Among successful shots, |-⟩ → |1⟩ under Hadamard, so outcome
            # should be 1 with probability ≈ 1 - O(ε). Allow generous slack
            # for shot noise + polynomial approximation error (ε=0.05).
            p_one = n_one / n_success
            @test p_one > 0.85
        end
    end
end
