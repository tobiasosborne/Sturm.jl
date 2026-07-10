# SPDX-License-Identifier: AGPL-3.0-only
#
# Milestone M1 law tests for `ctrl` / `Ctrl` — the single choke point
# (PRD-v2 §4.2). Homomorphism, adjoint compatibility, phase-physicality
# (control distinguishes g from e^{iα}g), and control-scope reassociation.

using Test
using Random
using Sturm
using Sturm: U2, Ctrl, Tensor, ctrl, ⊗, denoted_matrix, nwires,
    X, Y, Z, H, S, T, Ry, Rz, Rx, I2, NEG_I, gphase

if !@isdefined(rand_u2)
    function rand_u2(rng)
        v = randn(rng, 4)
        v ./= sqrt(sum(abs2, v))
        return U2(v[1], v[2], v[3], v[4], 2π * rand(rng) - π)
    end
end

@testset "ctrl — §4.2 the single choke point" begin

    @testset "T5 — ctrl homomorphism over ∘, incl. eager fusion (§4.2)" begin
        rng = MersenneTwister(101)
        for _ in 1:500
            g = rand_u2(rng); h = rand_u2(rng)
            @test denoted_matrix(ctrl(g ∘ h)) ≈ denoted_matrix(ctrl(g) ∘ ctrl(h))
            # eager fusion: same control count ⇒ Ctrl(k, g∘h), not a Seq.
            fused = ctrl(g) ∘ ctrl(h)
            @test fused isa Ctrl
            @test fused.k == 1
            @test denoted_matrix(fused) ≈ denoted_matrix(ctrl(g)) * denoted_matrix(ctrl(h))
        end
    end

    @testset "T6 — adjoint(ctrl(g)) == ctrl(adjoint(g)) (§4.2)" begin
        rng = MersenneTwister(202)
        for _ in 1:500
            g = rand_u2(rng)
            @test denoted_matrix(adjoint(ctrl(g))) ≈ denoted_matrix(ctrl(adjoint(g)))
            # structurally too (same k, inner daggered).
            @test adjoint(ctrl(g)).k == ctrl(g).k
            @test adjoint(ctrl(g)).inner ≈ adjoint(g)
        end
    end

    @testset "T7 — ctrl exposes global phase (§4.2; Tang–Wright Thm 1.1)" begin
        # ctrl(−I) = diag(1,1,−1,−1) ≠ ctrl(I) = I.
        @test denoted_matrix(ctrl(NEG_I)) ≈ ComplexF64[
            1 0 0 0
            0 1 0 0
            0 0 -1 0
            0 0 0 -1
        ]
        @test !(denoted_matrix(ctrl(NEG_I)) ≈ denoted_matrix(ctrl(I2)))
        # ctrl(gphase(α)) = diag(1,1,e^{iα},e^{iα}) — a Z-rotation on the control.
        α = 0.7
        @test denoted_matrix(ctrl(gphase(α))) ≈ ComplexF64[
            1 0 0 0
            0 1 0 0
            0 0 cis(α) 0
            0 0 0 cis(α)
        ]
        # control distinguishes g from e^{iα}g for α ∉ 2πℤ.
        rng = MersenneTwister(303)
        for _ in 1:200
            g = rand_u2(rng)
            β = 0.3 + 2.0 * rand(rng)      # away from 0 and 2π
            @test !(denoted_matrix(ctrl(gphase(β) ∘ g)) ≈ denoted_matrix(ctrl(g)))
        end
    end

    @testset "T8 — control-scope reassociation (§4.2; Delorme Eq 16)" begin
        rng = MersenneTwister(404)
        for _ in 1:500
            V = rand_u2(rng); W = rand_u2(rng)
            # wire 1 = control, wire 2 = body; V acts only on the body wire.
            lhs = ((I2 ⊗ V) ∘ ctrl(W)) ∘ (I2 ⊗ adjoint(V))
            rhs = ctrl((V ∘ W) ∘ adjoint(V))
            @test denoted_matrix(lhs) ≈ denoted_matrix(rhs)
        end
    end

    @testset "T-ccx — ctrl(ctrl(X)) Toffoli-grade & type-stable (§4.2)" begin
        ccX = ctrl(ctrl(X))
        @test ccX isa Ctrl{U2}
        @test ccX.k == 2
        @test nwires(ccX) == 3
        # 8×8 Toffoli acting as σx on the |11·⟩ block.
        M = denoted_matrix(ccX)
        expected = ComplexF64[i == j ? 1 : 0 for i in 1:8, j in 1:8]
        expected[7, 7] = 0; expected[8, 8] = 0
        expected[7, 8] = 1; expected[8, 7] = 1
        @test M ≈ expected
    end

    @testset "T-caac — ctrl NOT pushed through ⊗ (§4.2 CaaC caveat)" begin
        # ctrl(a⊗b) is a Ctrl{Tensor} (one shared control), never Tensor(ctrl,ctrl).
        cab = ctrl(X ⊗ Z)
        @test cab isa Ctrl{<:Tensor}
        @test cab.k == 1
        @test nwires(cab) == 3
    end

    @testset "T-ctrl-stability — @inferred controlled paths (§4.2)" begin
        cX = ctrl(X)
        @test (@inferred ctrl(X)) isa Ctrl{U2}
        @test (@inferred ctrl(cX)) isa Ctrl{U2}
        @test (@inferred adjoint(cX)) isa Ctrl{U2}
    end
end
