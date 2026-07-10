# SPDX-License-Identifier: AGPL-3.0-only
#
# Milestone M1 law tests for the `U2` process value. Each @testset is named
# after its PRD-v2 § for a grep-able coverage map. All U(2)-quotient
# equalities go through `≈` (never `==`, which is exact-structural). Fuzz
# seeds are fixed (Random.seed!) for reproducibility.

using Test
using Random
using Sturm
using Sturm: U2, denoted_matrix, X, Y, Z, H, S, T, Ry, Rz, Rx, I2, NEG_I, gphase,
    RENORM_TOL, renorm_if_needed, _u2

# A random U(2) element: uniform-ish unit quaternion + phase in (−π, π].
# Guarded so multiple kernel test files can each declare it when run from
# runtests.jl (identical body) without a method-overwrite warning.
if !@isdefined(rand_u2)
    function rand_u2(rng)
        v = randn(rng, 4)
        v ./= sqrt(sum(abs2, v))
        return U2(v[1], v[2], v[3], v[4], 2π * rand(rng) - π)
    end
end

const σx = ComplexF64[0 1; 1 0]
const σy = ComplexF64[0 -im; im 0]
const σz = ComplexF64[1 0; 0 -1]

@testset "U2 — §4.1 convention & §4.2 algebra" begin

    @testset "T0 — convention anchor (§4.1 quaternion↔U(2))" begin
        # Certifies the ENTIRE pinned convention at once: U(q) matrix form,
        # Hamilton signs, and ∘ order. If any is transcribed wrong, this
        # fails first (laws-first spine).
        rng = MersenneTwister(2718)
        @test denoted_matrix(I2) ≈ ComplexF64[1 0; 0 1]
        for _ in 1:1000
            a = rand_u2(rng); b = rand_u2(rng)
            @test denoted_matrix(a ∘ b) ≈ denoted_matrix(a) * denoted_matrix(b)
            @test denoted_matrix(adjoint(a)) ≈ denoted_matrix(a)'
        end
    end

    @testset "T-canon — equality predicate cross-check (§4.1 double cover)" begin
        rng = MersenneTwister(12345)
        for _ in 1:1000
            a = rand_u2(rng); b = rand_u2(rng)
            # `≈` on U2 must agree with the reference denoted-matrix equality.
            matched = isapprox(denoted_matrix(a), denoted_matrix(b); atol=1e-8)
            @test (a ≈ b) == matched
            # reflexive
            @test a ≈ a
            # the OTHER double-cover representative (−q, φ+π) is the SAME element
            partner = U2(-a.w, -a.x, -a.y, -a.z, a.φ + π)
            @test a ≈ partner
            @test denoted_matrix(a) ≈ denoted_matrix(partner)
        end
        # wrap-boundary: φ≈0 vs φ≈2π−ε denote the same element (circdist-safe)
        q = (0.5, 0.5, 0.5, 0.5)
        @test U2(q..., 1e-13) ≈ U2(q..., 2π - 1e-13)
    end

    @testset "T1 — Ry/Rz additivity + spinor periodicity (§4.2 (ℝ,+))" begin
        rng = MersenneTwister(999)
        for _ in 1:200
            α = 8π * rand(rng) - 4π
            β = 8π * rand(rng) - 4π
            @test Ry(α) ∘ Ry(β) ≈ Ry(α + β)
            @test Rz(α) ∘ Rz(β) ≈ Rz(α + β)
            @test Rx(α) ∘ Rx(β) ≈ Rx(α + β)
        end
        @test Ry(π) ∘ Ry(π) ≈ NEG_I
        # the double cover is physics: Ry(2π) = −I ≠ I; Ry(4π) = I
        @test Ry(2π) ≈ NEG_I
        @test !(Ry(2π) ≈ I2)
        @test Ry(4π) ≈ I2
    end

    @testset "T2 — H² lands on the other rep of +I (§4.1) + naive-eq meta" begin
        @test H ∘ H ≈ I2                       # passes under the ℤ₂ quotient
        @test denoted_matrix(H ∘ H) ≈ denoted_matrix(I2)
        # REGRESSION GUARD: naive field equality FAILS for H∘H vs I2 — the
        # predicate must be the ℤ₂ quotient, never a raw 5-field compare.
        @test !(H ∘ H == I2)                   # Base.== is exact-structural
        naive_approx(u, v) = isapprox(u.w, v.w; atol=1e-10) &&
                             isapprox(u.x, v.x; atol=1e-10) &&
                             isapprox(u.y, v.y; atol=1e-10) &&
                             isapprox(u.z, v.z; atol=1e-10) &&
                             isapprox(u.φ, v.φ; atol=1e-10)
        @test !naive_approx(H ∘ H, I2)
        @test H ∘ H ≈ I2                       # but the real predicate is true
    end

    @testset "T3 — +I ≠ −I survives the quotient (§4.1)" begin
        @test !(I2 ≈ NEG_I)
        @test !(NEG_I ≈ I2)
        # the other rep of −I is (−1_quat, 0)
        @test NEG_I ≈ U2(-1.0, 0.0, 0.0, 0.0, 0.0)
        @test denoted_matrix(NEG_I) ≈ ComplexF64[-1 0; 0 -1]
    end

    @testset "T4 — exact gate elements (§4.1 — where convention bugs die)" begin
        @test denoted_matrix(X) ≈ σx
        @test denoted_matrix(Y) ≈ σy
        @test denoted_matrix(Z) ≈ σz
        @test denoted_matrix(H) ≈ ComplexF64[1 1; 1 -1] ./ sqrt(2)
        @test denoted_matrix(S) ≈ ComplexF64[1 0; 0 im]
        @test denoted_matrix(T) ≈ ComplexF64[1 0; 0 cis(π / 4)]
        # involutions and phase-stress fusions
        @test X ∘ X ≈ I2
        @test Z ∘ Z ≈ I2
        @test H ∘ H ≈ I2
        @test S ∘ S ≈ Z
        @test T ∘ T ≈ S
        @test (H ∘ X) ∘ H ≈ Z
        @test (H ∘ Z) ∘ H ≈ X
    end

    @testset "T-adj — adjoint laws (§4.1)" begin
        rng = MersenneTwister(7)
        for _ in 1:200
            a = rand_u2(rng)
            @test a ∘ adjoint(a) ≈ I2
            @test adjoint(a) ∘ a ≈ I2
            @test denoted_matrix(adjoint(a)) ≈ denoted_matrix(a)'
            @test adjoint(adjoint(a)) ≈ a
        end
    end

    @testset "T-renorm — renormalization cadence (§4.1 numerics)" begin
        # (1) fires when it should: a deliberately denormalized U2 is repaired,
        #     φ untouched.
        bad = _u2(1.5, 0.0, 0.0, 0.0, 0.3)
        fixed = renorm_if_needed(bad)
        n2 = fixed.w^2 + fixed.x^2 + fixed.y^2 + fixed.z^2
        @test abs(n2 - 1) < RENORM_TOL
        @test fixed.φ == 0.3
        # (2) stays clean over a long non-commuting chain (10^6 composes):
        #     norm bounded AND denoted matrix stays unitary.
        A = Ry(0.1); B = Rz(0.1)
        r = I2
        for _ in 1:1_000_000
            r = (r ∘ A) ∘ B
        end
        nr = r.w^2 + r.x^2 + r.y^2 + r.z^2
        @test abs(nr - 1) < 1e-10
        M = denoted_matrix(r)
        @test M' * M ≈ ComplexF64[1 0; 0 1]
        # (3) doesn't fire needlessly: a single product of unit inputs stays
        #     sub-threshold, so a follow-up renorm is a no-op (=== preserving).
        rng = MersenneTwister(3)
        for _ in 1:1000
            a = rand_u2(rng); b = rand_u2(rng)
            prod = a ∘ b
            @test renorm_if_needed(prod) === prod
        end
    end

    @testset "T-canon-tie — near-tie pivot false-negative regression (§4.1)" begin
        # Reviewer-found edge (session 95): when the two largest quaternion
        # components are nearly tied with OPPOSITE signs, _signfix can pick
        # different pivots for two float representations of the same element,
        # sending them to different ℤ₂ representatives. The fast quaternion
        # compare then fails; ≈ must fall back to denotation and return true.
        c = Sturm.INV_SQRT2
        δ = 2e-13                        # ≫ eps, ≪ U2_ATOL
        a = U2(c + δ, -(c - δ), 0.0, 0.0, 0.2)          # pivot w > 0, no flip
        b = U2(-(c - δ), c + δ, 0.0, 0.0, 0.2 + π)      # ℤ₂ mirror; pivot x > 0, no flip
        # Same element by denotation:
        @test isapprox(denoted_matrix(a), denoted_matrix(b); atol=Sturm.U2_ATOL)
        # The predicate must agree (this failed before the denotation fallback):
        @test a ≈ b
        # And the mirror direction:
        @test b ≈ a
        # Sanity: genuinely different elements still reject through the fallback.
        @test !(a ≈ X)
    end

    @testset "T-stability — @inferred hot-path type stability (§4.1)" begin
        cX = Sturm.ctrl(X)
        @test (@inferred X ∘ X) isa U2
        @test (@inferred adjoint(X)) isa U2
        @test (@inferred denoted_matrix(X)) isa Matrix{ComplexF64}
        @test (@inferred Sturm.ctrl(X)) isa Sturm.Ctrl{U2}
        @test (@inferred isapprox(X, X)) isa Bool
        @test (@inferred Sturm.ctrl(cX)) isa Sturm.Ctrl{U2}
    end
end
