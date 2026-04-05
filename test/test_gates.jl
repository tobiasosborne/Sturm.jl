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

    @testset "T! applies π/4 phase" begin
        # H · T · H on |0>: if T adds π/4 phase to |1>, then
        # H|0> = |+>, T|+> = (|0> + e^{iπ/4}|1>)/√2, then H on that
        # gives P(|1>) = sin²(π/8) ≈ 0.1464
        @context EagerContext() begin
            count_true = 0
            N = 10000
            for _ in 1:N
                q = QBool(0)
                H!(q)
                T!(q)
                H!(q)
                count_true += Bool(q)
            end
            expected = sin(π/8)^2
            @test abs(count_true / N - expected) < 0.03
        end
    end

    @testset "T! and Tdg! cancel" begin
        @context EagerContext() begin
            for _ in 1:100
                q = QBool(0)
                H!(q)
                T!(q)
                Tdg!(q)
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
