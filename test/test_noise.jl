using Test
using Sturm

@testset "Noise channels" begin

    @testset "depolarise!(q, 0) leaves state unchanged" begin
        @context DensityMatrixContext() begin
            N = 1000
            count = 0
            for _ in 1:N
                q = QBool(0)
                depolarise!(q, 0.0)
                count += Bool(q)
            end
            @test count == 0  # |0⟩ unchanged
        end
    end

    @testset "depolarise!(q, 1) → maximally mixed (50/50)" begin
        @context DensityMatrixContext() begin
            N = 5000
            count = 0
            for _ in 1:N
                q = QBool(0)
                depolarise!(q, 1.0)
                count += Bool(q)
            end
            @test abs(count / N - 0.5) < 0.04
        end
    end

    @testset "dephase!(q, 0) leaves state unchanged" begin
        @context DensityMatrixContext() begin
            for _ in 1:100
                q = QBool(0)
                dephase!(q, 0.0)
                @test Bool(q) == false
            end
        end
    end

    @testset "dephase!(q, 1) on |+⟩ → mixed (50/50)" begin
        # |+⟩ = H|0⟩. Full dephasing kills off-diagonal → ρ = I/2 → 50/50
        @context DensityMatrixContext() begin
            N = 5000
            count = 0
            for _ in 1:N
                q = QBool(0)
                H!(q)
                dephase!(q, 1.0)
                count += Bool(q)
            end
            @test abs(count / N - 0.5) < 0.04
        end
    end

    @testset "dephase! on |0⟩ or |1⟩ has no effect" begin
        # Dephasing only affects off-diagonal elements.
        # Computational basis states have no off-diagonal → unaffected.
        @context DensityMatrixContext() begin
            for _ in 1:100
                q = QBool(0)
                dephase!(q, 1.0)
                @test Bool(q) == false
            end
            for _ in 1:100
                q = QBool(1)
                dephase!(q, 1.0)
                @test Bool(q) == true
            end
        end
    end

    @testset "amplitude_damp!(q, 0) leaves state unchanged" begin
        @context DensityMatrixContext() begin
            for _ in 1:100
                q = QBool(1)
                amplitude_damp!(q, 0.0)
                @test Bool(q) == true
            end
        end
    end

    @testset "amplitude_damp!(q, 1) → fully damped to |0⟩" begin
        @context DensityMatrixContext() begin
            for _ in 1:100
                q = QBool(1)
                amplitude_damp!(q, 1.0)
                @test Bool(q) == false
            end
        end
    end

    @testset "Noise requires DensityMatrixContext" begin
        @context EagerContext() begin
            q = QBool(0)
            @test_throws ErrorException depolarise!(q, 0.5)
            @test_throws ErrorException dephase!(q, 0.5)
            @test_throws ErrorException amplitude_damp!(q, 0.5)
            discard!(q)
        end
    end
end

@testset "Classicalise" begin
    @testset "classicalise(identity) → identity map" begin
        M = classicalise(q -> q)
        @test M[1, 1] ≈ 1.0 atol=1e-6  # P(0|0) = 1
        @test M[2, 1] ≈ 0.0 atol=1e-6  # P(1|0) = 0
        @test M[1, 2] ≈ 0.0 atol=1e-6  # P(0|1) = 0
        @test M[2, 2] ≈ 1.0 atol=1e-6  # P(1|1) = 1
    end

    @testset "classicalise(X!) → bit-flip" begin
        M = classicalise(X!)
        @test M[1, 1] ≈ 0.0 atol=1e-6
        @test M[2, 1] ≈ 1.0 atol=1e-6
        @test M[1, 2] ≈ 1.0 atol=1e-6
        @test M[2, 2] ≈ 0.0 atol=1e-6
    end

    @testset "classicalise(H!) → uniform" begin
        M = classicalise(H!)
        @test M[1, 1] ≈ 0.5 atol=1e-6
        @test M[2, 1] ≈ 0.5 atol=1e-6
        @test M[1, 2] ≈ 0.5 atol=1e-6
        @test M[2, 2] ≈ 0.5 atol=1e-6
    end
end
