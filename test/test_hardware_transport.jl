using Test
using Sturm: AbstractTransport, InProcessTransport, request,
             IdealisedSimulator, ProtocolOp, op_alloc, op_ry, op_measure,
             open_session_request, close_session_request, submit_request

@testset "Hardware transport (HW2)" begin

    @testset "InProcessTransport forwards open_session" begin
        sim = IdealisedSimulator(; capacity=2)
        t = InProcessTransport(sim)
        @test t isa AbstractTransport
        resp = request(t, open_session_request(; capacity=2))
        @test resp["ok"] === true
        @test haskey(resp, "session_id")
    end

    @testset "InProcessTransport forwards a full submit cycle" begin
        sim = IdealisedSimulator(; capacity=2)
        t = InProcessTransport(sim)
        sid = request(t, open_session_request(; capacity=2))["session_id"]
        ops = ProtocolOp[op_alloc(0), op_ry(0, π), op_measure(0, "m")]
        resp = request(t, submit_request(sid, ops))
        @test resp["ok"] === true
        @test resp["results"]["m"] === true
        @test request(t, close_session_request(sid))["ok"] === true
    end

    @testset "InProcessTransport propagates errors as err responses" begin
        sim = IdealisedSimulator(; capacity=2)
        t = InProcessTransport(sim)
        # Submit on unknown session — server returns err, transport doesn't throw
        resp = request(t, submit_request("s_bogus", ProtocolOp[op_alloc(0)]))
        @test resp["ok"] === false
        @test resp["err"] == "unknown_session"
    end

    @testset "InProcessTransport: two independent transports on one simulator" begin
        sim = IdealisedSimulator(; capacity=4)
        t1 = InProcessTransport(sim)
        t2 = InProcessTransport(sim)
        s1 = request(t1, open_session_request(; capacity=2))["session_id"]
        s2 = request(t2, open_session_request(; capacity=2))["session_id"]
        @test s1 != s2
        # Each transport hits the same simulator state; sessions are independent
        @test request(t1, close_session_request(s1))["ok"] === true
        @test request(t2, close_session_request(s2))["ok"] === true
    end
end
