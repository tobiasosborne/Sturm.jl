using Test
using Sturm

@testset "Convenience gates" begin

    @testset "H! creates superposition" begin
        @context EagerContext() begin
            count_true = 0
            N = 2000
            for _ in 1:N
                q = QBool(0)
                H!(q)
                count_true += Bool(q)
            end
            @test 0.45 * N < count_true < 0.55 * N
        end
    end

    @testset "H! twice returns to original" begin
        @context EagerContext() begin
            for _ in 1:100
                q = QBool(0)
                H!(q)
                H!(q)
                @test Bool(q) == false
            end
            for _ in 1:100
                q = QBool(1)
                H!(q)
                H!(q)
                @test Bool(q) == true
            end
        end
    end

    @testset "X! flips" begin
        @context EagerContext() begin
            for _ in 1:100
                q = QBool(0)
                X!(q)
                @test Bool(q) == true
            end
        end
    end

    @testset "Z! has no effect on |0>" begin
        @context EagerContext() begin
            for _ in 1:100
                q = QBool(0)
                Z!(q)
                @test Bool(q) == false
            end
        end
    end

    @testset "S! and Sdg! cancel" begin
        @context EagerContext() begin
            for _ in 1:100
                q = QBool(0)
                H!(q)
                S!(q)
                Sdg!(q)
                H!(q)
                @test Bool(q) == false
            end
        end
    end

    @testset "swap!" begin
        @context EagerContext() begin
            a = QBool(0)
            b = QBool(1)
            swap!(a, b)
            @test Bool(a) == true
            @test Bool(b) == false
        end
    end
end
