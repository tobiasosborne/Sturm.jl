using Test
using Sturm

@testset "Primitives" begin

    @testset "QBool preparation" begin
        @context EagerContext() begin
            # QBool(0) always measures false
            for _ in 1:100
                q = QBool(0)
                @test Bool(q) == false
            end

            # QBool(1) always measures true
            for _ in 1:100
                q = QBool(1)
                @test Bool(q) == true
            end

            # QBool(0.5) is ~50/50
            count_true = 0
            N = 10000
            for _ in 1:N
                q = QBool(0.5)
                count_true += Bool(q)
            end
            @test 0.47 * N < count_true < 0.53 * N
        end
    end

    @testset "Theta rotation (Ry)" begin
        @context EagerContext() begin
            # q.θ += π on |0> → |1>
            for _ in 1:100
                q = QBool(0)
                q.θ += π
                @test Bool(q) == true
            end

            # q.θ += π on |1> → |0>
            for _ in 1:100
                q = QBool(1)
                q.θ += π
                @test Bool(q) == false
            end
        end
    end

    @testset "Phi rotation (Rz)" begin
        @context EagerContext() begin
            # q.φ += anything on |0> has no observable effect
            for _ in 1:100
                q = QBool(0)
                q.φ += π
                @test Bool(q) == false
            end

            # H · Z · H = X: QBool(0) → H → Z → H → should be |1>
            # H = Rz(π)·Ry(π/2), Z = Rz(π)
            for _ in 1:100
                q = QBool(0)
                H!(q)
                Z!(q)
                H!(q)
                @test Bool(q) == true
            end
        end
    end

    @testset "XOR entanglement (⊻=)" begin
        @context EagerContext() begin
            # |0> ⊻= |1> → CNOT with |1> as control → flips target → |1>
            q_target = QBool(0)
            q_ctrl = QBool(1)
            q_target ⊻= q_ctrl
            @test Bool(q_target) == true
            @test Bool(q_ctrl) == true
        end
    end

    @testset "Linear resource tracking" begin
        @context EagerContext() begin
            q = QBool(0)
            _ = Bool(q)  # consumes q

            # Using consumed qubit should error
            @test_throws ErrorException Bool(q)
            @test_throws ErrorException (q.θ += π)

            # Double discard should error
            q2 = QBool(0)
            discard!(q2)
            @test_throws ErrorException discard!(q2)
        end
    end

    @testset "Context propagation" begin
        # QBool(p) without context should error
        @test_throws ErrorException QBool(0.5)

        # Nested contexts
        @context EagerContext() begin
            outer_ctx = current_context()
            q1 = QBool(0)
            @context EagerContext() begin
                inner_ctx = current_context()
                @test outer_ctx !== inner_ctx
                q2 = QBool(0)
            end
            # Outer context restored
            @test current_context() === outer_ctx
        end
    end
end
