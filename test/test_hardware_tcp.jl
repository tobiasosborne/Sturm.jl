using Test
using Sturm
using Sockets: listen, accept, IPv4, getsockname

# TCPTransport + standalone server — exercises the full NDJSON-over-TCP wire
# protocol. Server runs in-process on a port chosen by the OS (port=0).

@testset "Hardware TCP transport + server (HW5)" begin

    @testset "Bell pair via TCPTransport on in-process server" begin
        sim = Sturm.IdealisedSimulator(; capacity=2)
        sock, port, accept_task = Sturm.start_server(sim; port=0)
        try
            t = Sturm.TCPTransport("127.0.0.1", port)
            try
                ctx = Sturm.HardwareContext(t; capacity=2)
                @context ctx begin
                    agreed = 0
                    for _ in 1:50
                        a = QBool(0.5); b = QBool(0)
                        b ⊻= a
                        ra = Bool(a); rb = Bool(b)
                        ra == rb && (agreed += 1)
                    end
                    @test agreed == 50
                end
                close(ctx)
            finally
                close(t)
            end
        finally
            Sturm.stop_server!(sock)
        end
    end

    @testset "TCPTransport reports session_id back to the client" begin
        sim = Sturm.IdealisedSimulator(; capacity=2)
        sock, port, _ = Sturm.start_server(sim; port=0)
        try
            t = Sturm.TCPTransport("127.0.0.1", port)
            try
                resp = Sturm.request(t, Sturm.open_session_request(; capacity=2))
                @test resp["ok"] === true
                @test haskey(resp, "session_id")
                Sturm.request(t, Sturm.close_session_request(resp["session_id"]))
            finally
                close(t)
            end
        finally
            Sturm.stop_server!(sock)
        end
    end

    @testset "Server returns err response for malformed request without dropping connection" begin
        sim = Sturm.IdealisedSimulator(; capacity=2)
        sock, port, _ = Sturm.start_server(sim; port=0)
        try
            t = Sturm.TCPTransport("127.0.0.1", port)
            try
                # Bogus message: missing "v"
                resp = Sturm.request(t, Dict{String,Any}("op" => "open_session"))
                @test resp["ok"] === false
                @test resp["err"] == "missing_version"
                # Subsequent valid request still works on the SAME connection
                ok = Sturm.request(t, Sturm.open_session_request(; capacity=2))
                @test ok["ok"] === true
            finally
                close(t)
            end
        finally
            Sturm.stop_server!(sock)
        end
    end

    @testset "Two clients on one server run independent sessions" begin
        sim = Sturm.IdealisedSimulator(; capacity=4)
        sock, port, _ = Sturm.start_server(sim; port=0)
        try
            t1 = Sturm.TCPTransport("127.0.0.1", port)
            t2 = Sturm.TCPTransport("127.0.0.1", port)
            try
                ctx1 = Sturm.HardwareContext(t1; capacity=2)
                ctx2 = Sturm.HardwareContext(t2; capacity=2)
                @test ctx1.session_id != ctx2.session_id
                @context ctx1 begin
                    @test Bool(QBool(1.0)) === true
                end
                @context ctx2 begin
                    @test Bool(QBool(0.0)) === false
                end
                close(ctx1); close(ctx2)
            finally
                close(t1); close(t2)
            end
        finally
            Sturm.stop_server!(sock)
        end
    end

    @testset "TCPTransport connect timeout fires on unreachable host — bead Sturm.jl-mx3g" begin
        # Pre-fix: connect() blocked indefinitely. Now bounded by the
        # `timeout` kwarg (default 30s; tested at 0.5s for speed).
        # 198.51.100.X is RFC5737 TEST-NET-2 — guaranteed not routable.
        t0 = time()
        @test_throws ErrorException Sturm.TCPTransport("198.51.100.1", 1; timeout=0.5)
        elapsed = time() - t0
        @test elapsed < 5.0   # must NOT block beyond a small overhead of 0.5s
    end

    @testset "TCPTransport request timeout fires on stalled server — bead Sturm.jl-mx3g" begin
        # Spawn a TCP listener that accepts but never responds. The
        # connect() succeeds (server accepts), but readline blocks forever
        # without the timeout. With the timeout: an ErrorException after
        # ~0.5s and the socket is closed.
        srv = listen(IPv4("127.0.0.1"), 0)
        port = Int(getsockname(srv)[2])
        accept_task = @async try; accept(srv); catch; end
        try
            t = Sturm.TCPTransport("127.0.0.1", port; timeout=0.5)
            t0 = time()
            @test_throws ErrorException Sturm.request(t,
                Dict("v" => 1, "op" => "open_session", "capacity" => 1))
            elapsed = time() - t0
            @test elapsed < 5.0
            @test !isopen(t.sock)   # timer closed the socket
        finally
            close(srv)
        end
    end
end
