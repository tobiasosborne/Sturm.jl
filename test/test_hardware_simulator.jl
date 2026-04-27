using Test
using Sturm: IdealisedSimulator, dispatch!, PROTOCOL_VERSION,
             ProtocolOp, op_alloc, op_discard, op_ry, op_rz, op_cx, op_ccx,
             op_measure, op_barrier,
             open_session_request, close_session_request, submit_request

# These tests exercise the IdealisedSimulator directly (no transport layer).
# Each test constructs a simulator, dispatches messages as Dicts, and asserts
# on the response. The simulator owns an internal EagerContext (Orkan-backed).

@testset "IdealisedSimulator (HW4)" begin

    @testset "open_session returns ok + session_id" begin
        sim = IdealisedSimulator(; capacity=4)
        resp = dispatch!(sim, open_session_request(; capacity=4))
        @test resp["ok"] === true
        @test resp["v"] == PROTOCOL_VERSION
        @test haskey(resp, "session_id")
        @test resp["session_id"] isa AbstractString
    end

    @testset "open_session rejects capacity > sim max" begin
        sim = IdealisedSimulator(; capacity=4)
        resp = dispatch!(sim, open_session_request(; capacity=8))
        @test resp["ok"] === false
        @test resp["err"] == "capacity_exceeded"
    end

    @testset "close_session removes the session" begin
        sim = IdealisedSimulator(; capacity=4)
        sid = dispatch!(sim, open_session_request(; capacity=4))["session_id"]
        resp = dispatch!(sim, close_session_request(sid))
        @test resp["ok"] === true
        # Subsequent submit should fail
        bad = dispatch!(sim, submit_request(sid, ProtocolOp[op_alloc(0)]))
        @test bad["ok"] === false
        @test bad["err"] == "unknown_session"
    end

    @testset "submit alloc + discard" begin
        sim = IdealisedSimulator(; capacity=4)
        sid = dispatch!(sim, open_session_request(; capacity=4))["session_id"]
        resp = dispatch!(sim, submit_request(sid, ProtocolOp[op_alloc(0), op_discard(0)]))
        @test resp["ok"] === true
        @test isempty(resp["results"])
    end

    @testset "submit Ry(π) on |0⟩ measures to true" begin
        sim = IdealisedSimulator(; capacity=2)
        sid = dispatch!(sim, open_session_request(; capacity=2))["session_id"]
        ops = ProtocolOp[
            op_alloc(0),
            op_ry(0, π),                # |0⟩ → |1⟩ (up to global phase)
            op_measure(0, "m"),         # measure recycles the slot
        ]
        resp = dispatch!(sim, submit_request(sid, ops))
        @test resp["ok"] === true
        @test resp["results"]["m"] === true
    end

    @testset "submit Ry(0) on |0⟩ measures to false" begin
        sim = IdealisedSimulator(; capacity=2)
        sid = dispatch!(sim, open_session_request(; capacity=2))["session_id"]
        ops = ProtocolOp[
            op_alloc(0),
            op_ry(0, 0.0),
            op_measure(0, "m"),
        ]
        resp = dispatch!(sim, submit_request(sid, ops))
        @test resp["ok"] === true
        @test resp["results"]["m"] === false
    end

    @testset "Bell pair statistics over 200 shots" begin
        sim = IdealisedSimulator(; capacity=2)
        sid = dispatch!(sim, open_session_request(; capacity=2))["session_id"]
        n00 = 0; n11 = 0; n01 = 0; n10 = 0
        for _ in 1:200
            ops = ProtocolOp[
                op_alloc(0), op_alloc(1),
                op_ry(0, π / 2),     # |+⟩ on qubit 0
                op_cx(0, 1),
                op_measure(0, "a"),
                op_measure(1, "b"),
            ]
            r = dispatch!(sim, submit_request(sid, ops))
            @test r["ok"] === true
            a = r["results"]["a"]
            b = r["results"]["b"]
            if !a && !b
                n00 += 1
            elseif a && b
                n11 += 1
            elseif !a && b
                n01 += 1
            else
                n10 += 1
            end
        end
        # Bell: only 00 and 11 are possible (perfect correlation).
        @test n01 == 0
        @test n10 == 0
        @test n00 + n11 == 200
        # Roughly 50/50 split. Allow generous tolerance for 200 shots.
        @test 60 < n00 < 140
        @test 60 < n11 < 140
    end

    @testset "alloc on already-allocated qubit is an error" begin
        sim = IdealisedSimulator(; capacity=2)
        sid = dispatch!(sim, open_session_request(; capacity=2))["session_id"]
        resp = dispatch!(sim, submit_request(sid, ProtocolOp[op_alloc(0), op_alloc(0)]))
        @test resp["ok"] === false
        @test resp["err"] == "alloc_conflict"
    end

    @testset "alloc on out-of-range qubit is an error" begin
        sim = IdealisedSimulator(; capacity=2)
        sid = dispatch!(sim, open_session_request(; capacity=2))["session_id"]
        resp = dispatch!(sim, submit_request(sid, ProtocolOp[op_alloc(2)]))
        @test resp["ok"] === false
        @test resp["err"] == "qubit_out_of_range"
    end

    @testset "op on un-allocated qubit is an error" begin
        sim = IdealisedSimulator(; capacity=2)
        sid = dispatch!(sim, open_session_request(; capacity=2))["session_id"]
        resp = dispatch!(sim, submit_request(sid, ProtocolOp[op_ry(0, π)]))
        @test resp["ok"] === false
        @test resp["err"] == "qubit_not_allocated"
    end

    @testset "qubit recycling across submits within one session" begin
        sim = IdealisedSimulator(; capacity=2)
        sid = dispatch!(sim, open_session_request(; capacity=2))["session_id"]
        # First submit: alloc both, measure both
        r1 = dispatch!(sim, submit_request(sid, ProtocolOp[
            op_alloc(0), op_alloc(1),
            op_ry(0, π),
            op_measure(0, "m0"), op_measure(1, "m1"),
        ]))
        @test r1["ok"] === true
        @test r1["results"]["m0"] === true
        @test r1["results"]["m1"] === false
        # Second submit: re-allocate same indices, work on them
        r2 = dispatch!(sim, submit_request(sid, ProtocolOp[
            op_alloc(0), op_alloc(1),
            op_ry(1, π),
            op_measure(0, "m0"), op_measure(1, "m1"),
        ]))
        @test r2["ok"] === true
        @test r2["results"]["m0"] === false
        @test r2["results"]["m1"] === true
    end

    @testset "duration_ms scales with gate count" begin
        sim = IdealisedSimulator(; capacity=2, gate_time_ms=2.5)
        sid = dispatch!(sim, open_session_request(; capacity=2, gate_time_ms=2.5))["session_id"]
        # 1 ry gate (alloc/discard/measure don't count as gates)
        r = dispatch!(sim, submit_request(sid, ProtocolOp[
            op_alloc(0), op_ry(0, π / 4), op_measure(0, "m"),
        ]))
        @test r["duration_ms"] ≈ 2.5
        # 3 gates (ry, ry, cx)
        r = dispatch!(sim, submit_request(sid, ProtocolOp[
            op_alloc(0), op_alloc(1),
            op_ry(0, π / 4), op_ry(1, π / 4), op_cx(0, 1),
            op_measure(0, "a"), op_measure(1, "b"),
        ]))
        @test r["duration_ms"] ≈ 7.5
    end

    @testset "realtime=true sleeps approximately gate_time_ms" begin
        sim = IdealisedSimulator(; capacity=1, gate_time_ms=20.0, realtime=true)
        sid = dispatch!(sim, open_session_request(; capacity=1, gate_time_ms=20.0))["session_id"]
        t0 = time_ns()
        dispatch!(sim, submit_request(sid, ProtocolOp[
            op_alloc(0), op_ry(0, π / 2), op_measure(0, "m"),
        ]))
        elapsed_ms = (time_ns() - t0) / 1e6
        # Should be at least 20 ms (one gate × 20ms). Generous upper bound.
        @test elapsed_ms >= 18.0
        @test elapsed_ms < 200.0
    end

    @testset "realtime=false (default) is fast" begin
        sim = IdealisedSimulator(; capacity=1, gate_time_ms=1000.0)
        sid = dispatch!(sim, open_session_request(; capacity=1))["session_id"]
        t0 = time_ns()
        dispatch!(sim, submit_request(sid, ProtocolOp[
            op_alloc(0), op_ry(0, π / 2), op_measure(0, "m"),
        ]))
        elapsed_ms = (time_ns() - t0) / 1e6
        @test elapsed_ms < 100.0  # Way under 1000ms — no actual sleep
    end

    @testset "two sessions run independently" begin
        sim = IdealisedSimulator(; capacity=4)
        s1 = dispatch!(sim, open_session_request(; capacity=2))["session_id"]
        s2 = dispatch!(sim, open_session_request(; capacity=2))["session_id"]
        @test s1 != s2
        # Session 1: prepare |1⟩
        r1 = dispatch!(sim, submit_request(s1, ProtocolOp[
            op_alloc(0), op_ry(0, π), op_measure(0, "m"),
        ]))
        # Session 2: prepare |0⟩
        r2 = dispatch!(sim, submit_request(s2, ProtocolOp[
            op_alloc(0), op_measure(0, "m"),
        ]))
        @test r1["results"]["m"] === true
        @test r2["results"]["m"] === false
        # Both close cleanly
        @test dispatch!(sim, close_session_request(s1))["ok"] === true
        @test dispatch!(sim, close_session_request(s2))["ok"] === true
    end

    @testset "unknown message op is an error" begin
        sim = IdealisedSimulator(; capacity=2)
        resp = dispatch!(sim, Dict{String,Any}(
            "v" => PROTOCOL_VERSION, "op" => "frobnicate",
        ))
        @test resp["ok"] === false
    end

    @testset "version mismatch is an error" begin
        sim = IdealisedSimulator(; capacity=2)
        resp = dispatch!(sim, Dict{String,Any}(
            "v" => 999, "op" => "open_session", "capacity" => 2, "gate_time_ms" => 1.0,
        ))
        @test resp["ok"] === false
    end

    @testset "Toffoli (CCX) flips target only when both controls are |1⟩" begin
        sim = IdealisedSimulator(; capacity=3)
        sid = dispatch!(sim, open_session_request(; capacity=3))["session_id"]
        # Case 1: c1=1, c2=1, target=0 → target should become 1
        r = dispatch!(sim, submit_request(sid, ProtocolOp[
            op_alloc(0), op_alloc(1), op_alloc(2),
            op_ry(0, π), op_ry(1, π),                # c1=|1⟩, c2=|1⟩
            op_ccx(0, 1, 2),
            op_measure(0, "c1"), op_measure(1, "c2"), op_measure(2, "t"),
        ]))
        @test r["results"]["t"] === true
        # Case 2: c1=0, c2=1, target=0 → target should stay 0
        r = dispatch!(sim, submit_request(sid, ProtocolOp[
            op_alloc(0), op_alloc(1), op_alloc(2),
            op_ry(1, π),                              # c1=|0⟩, c2=|1⟩
            op_ccx(0, 1, 2),
            op_measure(0, "c1"), op_measure(1, "c2"), op_measure(2, "t"),
        ]))
        @test r["results"]["t"] === false
    end

    @testset "concurrent open_session yields distinct ids — bead Sturm.jl-x3xn" begin
        # Pre-fix: `sim.next_session_id += 1` was a non-atomic read-
        # modify-write AND `sim.sessions[sid] = …` was a Dict mutation
        # without a lock. Two @async tasks calling open_session in
        # parallel could (a) observe the same counter value, emitting
        # duplicate session ids, AND (b) trip Julia's Dict
        # rehash-during-insert UB. Now Threads.atomic_add! handles the
        # counter and a ReentrantLock guards every sessions-Dict access.
        sim = IdealisedSimulator(; capacity=2)
        N = 64
        ids = String["unset" for _ in 1:N]
        errs = String["" for _ in 1:N]
        @sync for i in 1:N
            Threads.@spawn try
                resp = dispatch!(sim, open_session_request(; capacity=1))
                ids[i] = String(resp["session_id"])
            catch e
                errs[i] = sprint(showerror, e)
            end
        end
        @test all(isempty, errs)
        @test length(unique(ids)) == N
        @test all(startswith.(ids, "s_"))
    end
end
