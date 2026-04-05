using Test
using Sturm

@testset "DensityMatrixContext" begin

    @testset "Create and verify MIXED type" begin
        @context DensityMatrixContext() begin
            ctx = current_context()
            @test Sturm.state_type(ctx.orkan) == Sturm.ORKAN_MIXED_PACKED
        end
    end

    @testset "QBool(0) always false" begin
        @context DensityMatrixContext() begin
            for _ in 1:100
                @test Bool(QBool(0)) == false
            end
        end
    end

    @testset "QBool(1) always true" begin
        @context DensityMatrixContext() begin
            for _ in 1:100
                @test Bool(QBool(1)) == true
            end
        end
    end

    @testset "QBool(0.5) is ~50/50" begin
        @context DensityMatrixContext() begin
            N = 5000
            count = sum(1:N) do _
                Bool(QBool(0.5))
            end
            @test abs(count / N - 0.5) < 0.04
        end
    end

    @testset "H! creates superposition (matches EagerContext)" begin
        N = 5000
        eager_count = 0
        density_count = 0
        @context EagerContext() begin
            for _ in 1:N
                q = QBool(0); H!(q)
                eager_count += Bool(q)
            end
        end
        @context DensityMatrixContext() begin
            for _ in 1:N
                q = QBool(0); H!(q)
                density_count += Bool(q)
            end
        end
        @test abs(eager_count/N - density_count/N) < 0.05
    end

    @testset "Bell state correlations match EagerContext" begin
        N = 1000
        @context DensityMatrixContext() begin
            for _ in 1:N
                a = QBool(0.5)
                b = QBool(0)
                b ⊻= a
                ra = Bool(a)
                rb = Bool(b)
                @test ra == rb  # Bell state: always correlated
            end
        end
    end

    @testset "X! flips" begin
        @context DensityMatrixContext() begin
            for _ in 1:50
                q = QBool(0); X!(q)
                @test Bool(q) == true
            end
        end
    end

    @testset "Teleportation via density matrix" begin
        @context DensityMatrixContext() begin
            N = 500
            # Teleport |0⟩: should always measure false
            for _ in 1:N
                q = QBool(0)
                a = QBool(0.5)
                b = QBool(0)
                b ⊻= a
                q ⊻= a
                H!(q)
                mq = Bool(q)
                ma = Bool(a)
                if ma; X!(b); end
                if mq; Z!(b); end
                @test Bool(b) == false
            end
        end
    end
end
