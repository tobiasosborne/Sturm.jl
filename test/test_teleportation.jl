using Test
using Sturm

@testset "Teleportation" begin

    function teleport!(q::QBool)::QBool
        ctx = q.ctx
        # Create Bell pair
        a = QBool(ctx, 1//2)
        b = QBool(ctx, 0)
        b ⊻= a

        # Bell measurement
        a ⊻= q

        rq::Bool = q
        ra::Bool = a

        # Classical corrections
        if ra; b.θ += π; end
        if rq; b.φ += π; end
        return b
    end

    @testset "Teleport |0>" begin
        @context EagerContext() begin
            N = 500
            for _ in 1:N
                q = QBool(0)
                out = teleport!(q)
                @test Bool(out) == false
            end
        end
    end

    @testset "Teleport |1>" begin
        @context EagerContext() begin
            N = 500
            for _ in 1:N
                q = QBool(1)
                out = teleport!(q)
                @test Bool(out) == true
            end
        end
    end

    @testset "Teleport |+> statistics" begin
        @context EagerContext() begin
            count_true = 0
            N = 2000
            for _ in 1:N
                q = QBool(0.5)
                out = teleport!(q)
                count_true += Bool(out)
            end
            # Should be ~50/50
            @test 0.45 * N < count_true < 0.55 * N
        end
    end

    @testset "Teleport arbitrary state" begin
        @context EagerContext() begin
            # Prepare |ψ> with P(|1>) = 0.3, teleport, verify statistics
            p = 0.3
            count_true = 0
            N = 3000
            for _ in 1:N
                q = QBool(p)
                out = teleport!(q)
                count_true += Bool(out)
            end
            observed = count_true / N
            @test abs(observed - p) < 0.04  # tolerance ±4%
        end
    end
end
