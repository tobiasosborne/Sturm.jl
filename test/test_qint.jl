using Test
using Sturm

@testset "QInt{W}" begin

    @testset "QInt{8} classical roundtrip" begin
        for val in [0, 1, 42, 127, 255]
            @context EagerContext() begin
                q = QInt{8}(val)
                @test Int(q) == val
            end
        end
    end

    @testset "QInt{4} classical roundtrip" begin
        # Exhaustive for 4-bit
        @context EagerContext() begin
            for val in 0:15
                q = QInt{4}(val)
                @test Int(q) == val
            end
        end
    end

    @testset "QInt{1} single bit" begin
        @context EagerContext() begin
            q0 = QInt{1}(0)
            @test Int(q0) == 0
            q1 = QInt{1}(1)
            @test Int(q1) == 1
        end
    end

    @testset "QInt value out of range" begin
        @context EagerContext() begin
            @test_throws ErrorException QInt{4}(16)   # too large
            @test_throws ErrorException QInt{4}(-1)   # negative
            @test_throws ErrorException QInt{1}(2)    # 1-bit, value 2
        end
    end

    @testset "Linear resource tracking" begin
        @context EagerContext() begin
            q = QInt{4}(5)
            _ = Int(q)  # consumes q
            @test_throws ErrorException Int(q)  # double consume
        end
    end

    @testset "getindex returns QBool view" begin
        @context EagerContext() begin
            q = QInt{4}(0b1010)  # value 10 = bits: 0,1,0,1 (LSB first)
            # bit 1 (LSB) = 0
            b1 = q[1]
            @test Bool(b1) == false
            # bit 2 = 1
            b2 = q[2]
            @test Bool(b2) == true
            # bit 3 = 0
            b3 = q[3]
            @test Bool(b3) == false
            # bit 4 (MSB) = 1
            b4 = q[4]
            @test Bool(b4) == true
        end
    end

    @testset "getindex bounds check" begin
        @context EagerContext() begin
            q = QInt{4}(0)
            @test_throws ErrorException q[0]
            @test_throws ErrorException q[5]
            discard!(q)
        end
    end

    @testset "discard!" begin
        @context EagerContext() begin
            q = QInt{8}(42)
            discard!(q)
            @test_throws ErrorException Int(q)  # consumed
        end
    end

    @testset "length" begin
        @context EagerContext() begin
            q = QInt{8}(0)
            @test length(q) == 8
            discard!(q)
            q4 = QInt{4}(0)
            @test length(q4) == 4
            discard!(q4)
        end
    end

    @testset "Addition: QInt{8}(42) + QInt{8}(17) = 59" begin
        @context EagerContext() begin
            @test Int(QInt{8}(42) + QInt{8}(17)) == 59
        end
    end

    @testset "Addition: QInt{8}(200) + QInt{8}(100) = 44 (mod 256)" begin
        @context EagerContext() begin
            @test Int(QInt{8}(200) + QInt{8}(100)) == 44
        end
    end

    @testset "Addition: identity and zero" begin
        @context EagerContext() begin
            @test Int(QInt{4}(0) + QInt{4}(0)) == 0
            for x in [1, 7, 15]
                @test Int(QInt{4}(0) + QInt{4}(x)) == x
            end
        end
    end

    @testset "Addition: QInt{1} single bit" begin
        @context EagerContext() begin
            @test Int(QInt{1}(0) + QInt{1}(0)) == 0
            @test Int(QInt{1}(0) + QInt{1}(1)) == 1
            @test Int(QInt{1}(1) + QInt{1}(0)) == 1
            @test Int(QInt{1}(1) + QInt{1}(1)) == 0  # 2 mod 2
        end
    end

    @testset "Addition: exhaustive QInt{4}" begin
        @context EagerContext() begin
            for x in 0:15, y in 0:15
                @test Int(QInt{4}(x) + QInt{4}(y)) == (x + y) % 16
            end
        end
    end

    @testset "Addition consumes inputs" begin
        @context EagerContext() begin
            a = QInt{4}(5)
            b = QInt{4}(3)
            s = a + b
            @test_throws ErrorException Int(a)
            @test_throws ErrorException Int(b)
            discard!(s)
        end
    end

    @testset "Subtraction: QInt{8}(10) - QInt{8}(3) = 7" begin
        @context EagerContext() begin
            @test Int(QInt{8}(10) - QInt{8}(3)) == 7
        end
    end

    @testset "Subtraction: QInt{8}(0) - QInt{8}(1) = 255 (mod 256)" begin
        @context EagerContext() begin
            @test Int(QInt{8}(0) - QInt{8}(1)) == 255
        end
    end

    @testset "Subtraction: exhaustive QInt{4}" begin
        @context EagerContext() begin
            for x in 0:15, y in 0:15
                @test Int(QInt{4}(x) - QInt{4}(y)) == (x - y + 16) % 16
            end
        end
    end

    # `<` and `==` on QInt are intentionally NOT defined; removed in Sturm.jl-w4g.
    # Quantum comparators go through oracle(f, q) with a classical predicate.
end
