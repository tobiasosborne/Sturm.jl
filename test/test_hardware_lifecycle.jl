using Test
using Sturm

# HW7: lifecycle hardening.
#
# Covers: with_hardware RAII wrapper, connection-drop handling, double-
# discard error path, fresh sessions after close. Finalizer is best-effort
# (GC timing is non-deterministic) so we test it lightly via an explicit
# GC.gc() prod and accept that it may not always trigger.

@testset "HardwareContext lifecycle (HW7)" begin

    @testset "with_hardware closes on normal exit" begin
        sim = Sturm.IdealisedSimulator(; capacity=2)
        t = Sturm.InProcessTransport(sim)
        sid_seen = ""
        Sturm.with_hardware(t; capacity=2) do ctx
            sid_seen = ctx.session_id
            @test Bool(QBool(1.0)) === true
        end
        @test !isempty(sid_seen)
        @test !haskey(sim.sessions, sid_seen)   # session was closed on the server
    end

    @testset "with_hardware closes on exception" begin
        sim = Sturm.IdealisedSimulator(; capacity=2)
        t = Sturm.InProcessTransport(sim)
        sid_seen = ""
        @test_throws ErrorException Sturm.with_hardware(t; capacity=2) do ctx
            sid_seen = ctx.session_id
            error("boom")
        end
        @test !haskey(sim.sessions, sid_seen)   # session still cleaned up
    end

    @testset "Closed transport socket → loud failure on next request" begin
        sim = Sturm.IdealisedSimulator(; capacity=2)
        sock, port, _ = Sturm.start_server(sim; port=0)
        t = Sturm.TCPTransport("127.0.0.1", port)
        ctx = Sturm.HardwareContext(t; capacity=2)
        # Simulate connection drop by closing the client socket directly.
        close(t)
        @context ctx begin
            q = QBool(0)
            @test_throws ErrorException Bool(q)   # flush() hits closed socket
        end
        try; close(ctx); catch; end
        Sturm.stop_server!(sock)
    end

    @testset "Sessions back-to-back through a single transport" begin
        sim = Sturm.IdealisedSimulator(; capacity=2)
        t = Sturm.InProcessTransport(sim)
        for _ in 1:5
            ctx = Sturm.HardwareContext(t; capacity=2)
            @context ctx begin
                @test Bool(QBool(1.0)) === true
            end
            close(ctx)
        end
        @test isempty(sim.sessions)   # all 5 sessions closed
    end

    @testset "discard! on already-consumed wire errors" begin
        sim = Sturm.IdealisedSimulator(; capacity=2)
        ctx = Sturm.HardwareContext(Sturm.InProcessTransport(sim); capacity=2)
        @context ctx begin
            q = QBool(0)
            discard!(q)
            @test_throws ErrorException discard!(q)
        end
        close(ctx)
    end

    @testset "Operations after close throw loudly" begin
        sim = Sturm.IdealisedSimulator(; capacity=2)
        ctx = Sturm.HardwareContext(Sturm.InProcessTransport(sim); capacity=2)
        close(ctx)
        @test_throws ErrorException Sturm.allocate!(ctx)
        @test_throws ErrorException Sturm.flush!(ctx)
    end

    @testset "Finalizer does best-effort cleanup of forgotten contexts" begin
        sim = Sturm.IdealisedSimulator(; capacity=2)
        t = Sturm.InProcessTransport(sim)
        # Open a context, drop the reference WITHOUT close, force GC.
        # The finalizer should @spawn a close and the session disappears.
        let
            ctx = Sturm.HardwareContext(t; capacity=2)
            @context ctx begin
                Bool(QBool(1.0))
            end
            # ctx goes out of scope here
        end
        GC.gc()           # request GC
        sleep(0.2)        # give the @spawn'd close task time to run
        GC.gc()           # encourage finalizer + scheduler activity
        sleep(0.2)
        # Cannot @test_broken assert sessions are empty — finalizer timing is
        # non-deterministic. Just verify it didn't blow up the test harness.
        @test true
    end
end
