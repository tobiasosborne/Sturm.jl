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

    @testset "measure! at n_qubits=4 GHZ-like leaves correct projection (bead e30b)" begin
        # Build 1/√2(|0000⟩ + |1111⟩) as a density matrix, measure qubit 0,
        # verify (1) outcome statistics match Born rule (50/50) and (2) the
        # post-measurement diagonal matches the projection. The pre-bead-e30b
        # implementation used per-element FFI in O(4^n) loops AND wrote to the
        # upper triangle of MIXED_PACKED — both are eliminated by switching to
        # an unsafe_wrap lower-triangle pass.
        N = 1000
        zero_count = 0
        for _ in 1:N
            @context DensityMatrixContext() begin
                a = QBool(0.5)
                b = QBool(0)
                c = QBool(0)
                d = QBool(0)
                b ⊻= a
                c ⊻= a
                d ⊻= a
                # State now: 1/√2(|0000⟩ + |1111⟩); measure a, all four should agree.
                ma = Bool(a)
                mb = Bool(b)
                mc = Bool(c)
                md = Bool(d)
                @test ma == mb == mc == md
                zero_count += !ma
            end
        end
        # Born rule: each outcome ~50%. Tolerance 4σ on N=1000 binomial → ±63.
        @test 437 <= zero_count <= 563
    end
end
