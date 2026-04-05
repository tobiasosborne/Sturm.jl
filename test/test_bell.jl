using Test
using Sturm

@testset "Bell state" begin

    @testset "Bell pair correlation" begin
        @context EagerContext() begin
            N = 1000
            for _ in 1:N
                a = QBool(0.5)   # |+>
                b = QBool(0)     # |0>
                b ⊻= a          # Bell pair: (|00> + |11>)/√2
                ra::Bool = a
                rb::Bool = b
                @test ra == rb   # always perfectly correlated
            end
        end
    end

    @testset "GHZ state" begin
        @context EagerContext() begin
            N = 1000
            for _ in 1:N
                a = QBool(0.5)
                b = QBool(0)
                c = QBool(0)
                b ⊻= a
                c ⊻= a
                ra::Bool = a
                rb::Bool = b
                rc::Bool = c
                @test ra == rb == rc  # all three must agree
            end
        end
    end

    @testset "Bell state measurement statistics" begin
        @context EagerContext() begin
            count_00 = 0
            count_11 = 0
            N = 10000
            for _ in 1:N
                a = QBool(0.5)
                b = QBool(0)
                b ⊻= a
                ra::Bool = a
                rb::Bool = b
                if !ra && !rb
                    count_00 += 1
                elseif ra && rb
                    count_11 += 1
                else
                    @test false  # should never happen
                end
            end
            # Should be ~50/50 between |00> and |11>
            @test 0.47 * N < count_00 < 0.53 * N
            @test 0.47 * N < count_11 < 0.53 * N
        end
    end
end
