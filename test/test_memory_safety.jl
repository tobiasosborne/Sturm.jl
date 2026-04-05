@testset "Memory safety" begin
    @testset "MAX_QUBITS cap prevents runaway allocation" begin
        # Attempt to create a context with capacity > MAX_QUBITS
        @test_throws ErrorException EagerContext(capacity=Sturm.MAX_QUBITS + 1)
    end

    @testset "Additive growth stays within bounds" begin
        # Start with small capacity, allocate enough qubits to trigger one grow
        @context EagerContext(capacity=2) begin
            ctx = current_context()
            # Allocate 3 qubits: first 2 fit, 3rd triggers grow by GROW_STEP (2→6)
            qs = [QBool(0.0) for _ in 1:3]
            @test ctx.capacity == 2 + Sturm.GROW_STEP
            # Clean up
            for q in qs
                discard!(q)
            end
        end
    end

    @testset "Qubit recycling avoids growth" begin
        @context EagerContext(capacity=4) begin
            ctx = current_context()
            # Allocate and recycle in a loop — capacity should never grow
            for _ in 1:100
                q = QBool(0.5)
                _ = Bool(q)  # measure and recycle
            end
            @test ctx.capacity == 4  # no growth
        end
    end

    @testset "OMP_NUM_THREADS is set" begin
        @test haskey(ENV, "OMP_NUM_THREADS")
        n = parse(Int, ENV["OMP_NUM_THREADS"])
        @test n >= 1
    end

    @testset "_estimated_bytes is correct" begin
        @test Sturm._estimated_bytes(10) == 1024 * 16       # 16 KB
        @test Sturm._estimated_bytes(20) == 1048576 * 16    # 16 MB
        @test Sturm._estimated_bytes(30) == 1073741824 * 16 # 16 GB
    end
end
