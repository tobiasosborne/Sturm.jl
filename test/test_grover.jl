using Test
using Sturm

@testset "Grover search & amplitude amplification" begin

    @testset "find: single item in 3-bit space (target=5)" begin
        @context EagerContext() begin
            N = 1000
            count = sum(1:N) do _
                find(Val(3)) do x; phase_flip!(x, 5); end == 5
            end
            @test count / N > 0.90
        end
    end

    @testset "find: each item in 3-bit space" begin
        @context EagerContext() begin
            for target in 0:7
                count = sum(1:200) do _
                    find(Val(3)) do x; phase_flip!(x, target); end == target
                end
                @test count / 200 > 0.85
            end
        end
    end

    @testset "find: 2-bit space (near-perfect for 1 in 4)" begin
        @context EagerContext() begin
            N = 500
            count = sum(1:N) do _
                find(Val(2)) do x; phase_flip!(x, 3); end == 3
            end
            # 1 in 4: sin²(3·arcsin(1/2)) = sin²(π/2) = 1.0
            @test count / N > 0.98
        end
    end

    @testset "find: two marked items {2, 5}" begin
        @context EagerContext() begin
            N = 1000
            count = sum(1:N) do _
                find(Val(3), n_marked=2) do x; phase_flip!(x, [2, 5]); end in (2, 5)
            end
            @test count / N > 0.95
        end
    end

    @testset "find: half the space (4 of 8, ~50%)" begin
        @context EagerContext() begin
            N = 2000
            odd_count = 0
            for _ in 1:N
                r = find(Val(3), n_marked=4) do x
                    phase_flip!(x, [1, 3, 5, 7])
                end
                if isodd(r); odd_count += 1; end
            end
            @test 0.40 < odd_count / N < 0.60
        end
    end

    @testset "amplify: with H^W = equivalent to find" begin
        @context EagerContext() begin
            N = 1000
            h_all! = Sturm._hadamard_all!
            count = sum(1:N) do _
                amplify(x -> phase_flip!(x, 7), h_all!, h_all!, Val(3)) == 7
            end
            @test count / N > 0.90
        end
    end

    @testset "amplify: explicit iteration count = 0 (uniform)" begin
        @context EagerContext() begin
            N = 2000
            h_all! = Sturm._hadamard_all!
            count = sum(1:N) do _
                amplify(x -> phase_flip!(x, 3), h_all!, h_all!, Val(3); iterations=0) == 3
            end
            @test 0.08 < count / N < 0.18
        end
    end

    @testset "amplify: explicit iteration count = 2 (optimal for 1/8)" begin
        @context EagerContext() begin
            N = 1000
            h_all! = Sturm._hadamard_all!
            count = sum(1:N) do _
                amplify(x -> phase_flip!(x, 3), h_all!, h_all!, Val(3); iterations=2) == 3
            end
            @test count / N > 0.90
        end
    end

    @testset "phase_flip! marks exactly the target" begin
        @context EagerContext() begin
            # |+⟩ → phase_flip!(1) → |−⟩ → H → |1⟩
            for _ in 1:100
                x = QInt{1}(0)
                superpose!(x)
                phase_flip!(x, 1)
                interfere!(x)
                @test Int(x) == 1
            end
        end
    end

    @testset "_optimal_iterations: known values" begin
        @test Sturm._optimal_iterations(4, 1) == 1
        @test Sturm._optimal_iterations(8, 1) == 2
        @test Sturm._optimal_iterations(16, 1) == 3
        @test Sturm._optimal_iterations(8, 2) == 1
        @test Sturm._optimal_iterations(8, 4) == 0
        @test Sturm._optimal_iterations(8, 0) == 0
        @test Sturm._optimal_iterations(8, 8) == 0
    end

    @testset "success probability matches theory (N=8, M=1)" begin
        @context EagerContext() begin
            N = 2000
            target = 6
            count = sum(1:N) do _
                find(Val(3)) do x; phase_flip!(x, target); end == target
            end
            observed = count / N
            # Theory: sin²((2k+1)θ) where θ=arcsin(1/√8), k=2
            theoretical = sin((2 * 2 + 1) * asin(1 / sqrt(8)))^2
            @test abs(observed - theoretical) < 0.05
        end
    end

    @testset "distribution concentrates on target" begin
        @context EagerContext() begin
            N = 2000
            target = 6
            counts = zeros(Int, 8)
            for _ in 1:N
                r = find(Val(3)) do x; phase_flip!(x, target); end
                counts[r + 1] += 1
            end
            @test counts[target + 1] / N > 0.90
            for i in 0:7
                i == target && continue
                @test counts[i + 1] / N < 0.05
            end
        end
    end

    @testset "_multi_controlled_z! correctness" begin
        @context EagerContext() begin
            # 1-qubit: Z on |+⟩ → |−⟩ → H → |1⟩
            for _ in 1:50
                q = QBool(0); H!(q)
                Sturm._multi_controlled_z!([q])
                H!(q)
                @test Bool(q) == true
            end
            # 2-qubit CZ: only flips when both |1⟩
            for _ in 1:50
                a = QBool(1); b = QBool(0); H!(b)
                Sturm._multi_controlled_z!([a, b])
                H!(b)
                @test Bool(b) == true  # CZ|1,+⟩ = |1,−⟩ → H → |1,1⟩
                discard!(a)
            end
            # 2-qubit CZ: control=|0⟩ → no flip
            for _ in 1:50
                a = QBool(0); b = QBool(0); H!(b)
                Sturm._multi_controlled_z!([a, b])
                H!(b)
                @test Bool(b) == false  # CZ|0,+⟩ = |0,+⟩ → H → |0,0⟩
                discard!(a)
            end
        end
    end
end
