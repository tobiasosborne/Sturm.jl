using Test
using Sturm

# Aggressive qubit-recycling test: 500 shots through a 2-qubit device. Every
# Bool(q) measurement recycles a slot on both client and server, so the
# server's EagerContext never grows beyond 2 qubits.

@testset "HardwareContext qubit recycling (HW6)" begin

    @testset "500 Bell pairs through a 2-qubit device" begin
        sim = Sturm.IdealisedSimulator(; capacity=2)
        ctx = Sturm.HardwareContext(Sturm.InProcessTransport(sim); capacity=2)
        @context ctx begin
            agreed = 0
            for _ in 1:500
                a = QBool(0.5); b = QBool(0)
                b ⊻= a
                ra = Bool(a); rb = Bool(b)
                ra == rb && (agreed += 1)
            end
            @test agreed == 500       # Bell correlation never breaks
        end
        # Server-side capacity stayed at 2: never grew.
        @test sim.sessions[ctx.session_id].eager.capacity == 2
        close(ctx)
    end

    @testset "1000 sequential single-qubit prep+measure on 1-qubit device" begin
        sim = Sturm.IdealisedSimulator(; capacity=1)
        ctx = Sturm.HardwareContext(Sturm.InProcessTransport(sim); capacity=1)
        @context ctx begin
            count_true = 0
            for _ in 1:1000
                q = QBool(1.0)        # |1⟩
                Bool(q) && (count_true += 1)
            end
            @test count_true == 1000  # deterministic
        end
        @test sim.sessions[ctx.session_id].eager.capacity == 1
        close(ctx)
    end

    @testset "Free-list grows monotonically across measure recycles" begin
        sim = Sturm.IdealisedSimulator(; capacity=4)
        ctx = Sturm.HardwareContext(Sturm.InProcessTransport(sim); capacity=4)
        @context ctx begin
            # Allocate 4, measure 4 → free_slots should be 4 long after the flush
            qs = [QBool(0) for _ in 1:4]
            @test length(ctx.free_slots) == 0
            for q in qs
                Bool(q)
            end
            @test length(ctx.free_slots) == 4
            # Allocate 4 more — they should ALL reuse slots, next_slot stays
            qs2 = [QBool(0) for _ in 1:4]
            @test ctx.next_slot == 4   # never grew
            @test length(ctx.free_slots) == 0
            for q in qs2
                Bool(q)
            end
        end
        close(ctx)
    end
end
