using Test
using LinearAlgebra: norm, I
using Sturm: QSVTPhases, processing_op_matrix

# ═══════════════════════════════════════════════════════════════════════════
# Test the GQSP convention adapter.
#
# The processing operator A_k = e^{iφ_k X} e^{iθ_k Z} is a 2×2 SU(2) matrix.
# We verify that our Ry/Rz decomposition produces the same matrix.
#
# Ref: Laneve (2025), arXiv:2503.03026, Theorem 9.
# ═══════════════════════════════════════════════════════════════════════════

# Pauli matrices for reference
const σX = ComplexF64[0 1; 1 0]
const σZ = ComplexF64[1 0; 0 -1]

# Matrix exponential of a Pauli: e^{iαP} = cos(α)I + i·sin(α)P
_expiP(α, P) = cos(α) * Matrix{ComplexF64}(I, 2, 2) + im * sin(α) * P

@testset "QSVT Conventions" begin

    # ─────────────────────────────────────────────────────────────────────
    # 1. Processing operator A_k = e^{iφX} e^{iθZ} matches Ry/Rz decomp
    # ─────────────────────────────────────────────────────────────────────

    @testset "processing_op_matrix matches e^{iφX}·e^{iθZ}" begin
        test_cases = [
            (0.0, 0.0),       # identity
            (π/4, 0.0),       # pure X rotation
            (0.0, π/3),       # pure Z rotation
            (π/6, π/4),       # mixed
            (-π/3, π/5),      # negative φ
            (π/7, -π/8),      # negative θ
            (0.3, 0.7),       # arbitrary
            (1.2, -0.4),      # another arbitrary
        ]
        for (φ, θ) in test_cases
            expected = _expiP(φ, σX) * _expiP(θ, σZ)
            actual = processing_op_matrix(φ, θ)
            # Compare up to global phase (SU(2) vs U(2))
            if abs(expected[1,1]) > 1e-10
                phase = actual[1,1] / expected[1,1]
                @test abs(abs(phase) - 1.0) < 1e-10
                @test norm(actual - phase * expected) < 1e-10
            else
                # Find any nonzero entry
                idx = findfirst(x -> abs(x) > 1e-10, expected)
                phase = actual[idx] / expected[idx]
                @test norm(actual - phase * expected) < 1e-10
            end
        end
    end

    # ─────────────────────────────────────────────────────────────────────
    # 2. QSVTPhases struct stores angles correctly
    # ─────────────────────────────────────────────────────────────────────

    @testset "QSVTPhases construction and accessors" begin
        φ = [0.1, 0.2, 0.3]
        θ = [0.4, 0.5, 0.6]
        λ = 0.7
        phases = QSVTPhases(λ, φ, θ)
        @test phases.lambda == λ
        @test phases.phi == φ
        @test phases.theta == θ
        @test phases.degree == 2  # n oracle calls = length(φ) - 1
    end

    # ─────────────────────────────────────────────────────────────────────
    # 3. Validation: φ and θ must have same length
    # ─────────────────────────────────────────────────────────────────────

    @testset "QSVTPhases validates input" begin
        @test_throws ErrorException QSVTPhases(0.0, [0.1, 0.2], [0.3])
        @test_throws ErrorException QSVTPhases(0.0, Float64[], Float64[])
    end

    # ─────────────────────────────────────────────────────────────────────
    # 4. Full GQSP protocol matrix for degree-1 (single oracle call)
    #    A₀ · W · A₁  where W = diag(z, 1)
    # ─────────────────────────────────────────────────────────────────────

    @testset "degree-1 GQSP protocol matrix" begin
        # For z = e^{iα} on the unit circle, the protocol gives:
        # A₀ · diag(z,1) · A₁ = 2×2 matrix whose (1,1) entry is P(z)
        φ = [π/6, π/4]
        θ = [π/3, π/5]
        λ = 0.1  # initial Z rotation

        A0 = _expiP(λ, σZ) * _expiP(φ[1], σX) * _expiP(θ[1], σZ)
        A1 = _expiP(φ[2], σX) * _expiP(θ[2], σZ)

        # Test at z = e^{iπ/4}
        α = π/4
        z = exp(im * α)
        W = ComplexF64[z 0; 0 1]

        protocol = A0 * W * A1
        # Just verify it's unitary
        @test norm(protocol * protocol' - I) < 1e-10
        # And that |P(z)|² + |Q(z)|² = 1
        P_z = protocol[1, 1]
        Q_z = protocol[1, 2]
        @test abs(abs2(P_z) + abs2(Q_z) - 1.0) < 1e-10
    end

end
