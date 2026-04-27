using Test
using Sturm: ProtocolOp, ProtocolError, PROTOCOL_VERSION,
             op_alloc, op_discard, op_ry, op_rz, op_cx, op_ccx, op_measure, op_barrier,
             open_session_request, close_session_request, submit_request,
             ok_response, err_response,
             json_encode, json_decode,
             to_json_dict, from_json_dict

@testset "Hardware protocol (HW1)" begin

    @testset "PROTOCOL_VERSION = 1" begin
        @test PROTOCOL_VERSION == 1
    end

    @testset "Op constructors set verb and fields" begin
        @test op_alloc(3).verb === :alloc
        @test op_alloc(3).fields["qubit"] == 3

        @test op_discard(7).verb === :discard
        @test op_discard(7).fields["qubit"] == 7

        @test op_ry(2, 1.5).verb === :ry
        @test op_ry(2, 1.5).fields["qubit"] == 2
        @test op_ry(2, 1.5).fields["theta"] == 1.5

        @test op_rz(4, π / 2).verb === :rz
        @test op_rz(4, π / 2).fields["qubit"] == 4
        @test op_rz(4, π / 2).fields["theta"] ≈ π / 2

        @test op_cx(0, 1).verb === :cx
        @test op_cx(0, 1).fields["control"] == 0
        @test op_cx(0, 1).fields["target"] == 1

        @test op_ccx(0, 1, 2).verb === :ccx
        @test op_ccx(0, 1, 2).fields["c1"] == 0
        @test op_ccx(0, 1, 2).fields["c2"] == 1
        @test op_ccx(0, 1, 2).fields["target"] == 2

        @test op_measure(5, "m0").verb === :measure
        @test op_measure(5, "m0").fields["qubit"] == 5
        @test op_measure(5, "m0").fields["id"] == "m0"

        @test op_barrier().verb === :barrier
        @test isempty(op_barrier().fields)
    end

    @testset "Op equality" begin
        @test op_alloc(3) == op_alloc(3)
        @test op_alloc(3) != op_alloc(4)
        @test op_alloc(3) != op_discard(3)
        @test op_ccx(0, 1, 2) == op_ccx(0, 1, 2)
        @test op_ccx(0, 1, 2) != op_ccx(0, 2, 1)
    end

    @testset "Op JSON dict round-trip" begin
        for op in (op_alloc(3), op_discard(7), op_ry(2, 1.5), op_rz(4, π / 2),
                   op_cx(0, 1), op_ccx(0, 1, 2), op_measure(5, "m0"), op_barrier())
            d = to_json_dict(op)
            @test d["g"] == String(op.verb)
            recovered = from_json_dict(d)
            @test recovered == op
        end
    end

    @testset "JSON encode primitives" begin
        @test json_encode(nothing) == "null"
        @test json_encode(true) == "true"
        @test json_encode(false) == "false"
        @test json_encode(42) == "42"
        @test json_encode(-7) == "-7"
        @test json_encode(1.5) == "1.5"
        @test json_encode("hello") == "\"hello\""
        @test json_encode("") == "\"\""
        @test json_encode([1, 2, 3]) == "[1,2,3]"
        @test json_encode(Any[]) == "[]"
        @test json_encode(Dict{String,Any}("a" => 1)) == "{\"a\":1}"
    end

    @testset "JSON encode rejects non-finite floats" begin
        @test_throws ProtocolError json_encode(Inf)
        @test_throws ProtocolError json_encode(-Inf)
        @test_throws ProtocolError json_encode(NaN)
    end

    @testset "JSON string escaping" begin
        @test json_encode("a\"b") == "\"a\\\"b\""
        @test json_encode("a\\b") == "\"a\\\\b\""
        @test json_encode("a\nb") == "\"a\\nb\""
        @test json_encode("a\tb") == "\"a\\tb\""
        @test json_decode("\"a\\\"b\"") == "a\"b"
        @test json_decode("\"a\\\\b\"") == "a\\b"
        @test json_decode("\"a\\nb\"") == "a\nb"
        @test json_decode("\"a\\tb\"") == "a\tb"
    end

    @testset "JSON decode primitives" begin
        @test json_decode("null") === nothing
        @test json_decode("true") === true
        @test json_decode("false") === false
        @test json_decode("42") == 42
        @test json_decode("-7") == -7
        @test json_decode("1.5") == 1.5
        @test json_decode("\"hello\"") == "hello"
        @test json_decode("[1,2,3]") == [1, 2, 3]
        @test json_decode("[]") == []
        @test json_decode("{\"a\":1}") == Dict{String,Any}("a" => 1)
    end

    @testset "JSON round-trip nested" begin
        v = Dict{String,Any}(
            "v" => 1,
            "ops" => Any[
                Dict{String,Any}("g" => "ry", "qubit" => 3, "theta" => 1.5),
                Dict{String,Any}("g" => "cx", "control" => 0, "target" => 1),
            ],
            "ok" => true,
        )
        @test json_decode(json_encode(v)) == v
    end

    @testset "JSON decode rejects malformed input" begin
        @test_throws ProtocolError json_decode("{")
        @test_throws ProtocolError json_decode("[1,2,")
        @test_throws ProtocolError json_decode("nul")
        @test_throws ProtocolError json_decode("1 2")  # trailing data
    end

    @testset "Parser raises ProtocolError, not AssertionError, on untrusted bytes — bead Sturm.jl-mx3g" begin
        # Pre-fix _parse_object! / _parse_array! / _parse_string! used
        # `@assert _peek(p) == UInt8('X')` on raw network bytes. An
        # AssertionError propagates past `catch e isa ProtocolError` in
        # _handle_connection and kills the connection task. Each parser
        # entry point must surface ProtocolError instead.
        # All three error types are reachable through the public
        # json_decode entry point with malformed input that confuses
        # _parse_value!'s dispatch — but the internal parsers must also
        # be defensive. Fuzz a battery of malformed payloads and assert
        # NO AssertionError ever escapes; only ProtocolError.
        for payload in (
            "",                        # empty
            "{",                       # unterminated object
            "[",                       # unterminated array
            "\"",                      # unterminated string
            "{\"k\"",                  # missing colon
            "{\"k\":}",                # missing value
            "[1,2",                    # missing close
            "{\"k\":1,",               # trailing comma + EOF
            "abc",                     # bare garbage
            "\\xff",                   # high-byte garbage
            "\x00\x01\x02",            # raw bytes
            ":",                       # leading punct
            "}",                       # bare close
            "]",
            "\"\\u",                   # broken unicode escape
        )
            err = try; json_decode(payload); catch e; e; end
            @test err isa ProtocolError
            @test !(err isa AssertionError)
        end
    end

    @testset "Message envelopes carry version + op" begin
        req = open_session_request()
        @test req["v"] == PROTOCOL_VERSION
        @test req["op"] == "open_session"
        @test req["capacity"] == 16
        @test req["gate_time_ms"] == 1.0
        @test open_session_request(; capacity=8, gate_time_ms=2.0)["capacity"] == 8

        @test close_session_request("s_1")["v"] == PROTOCOL_VERSION
        @test close_session_request("s_1")["op"] == "close_session"
        @test close_session_request("s_1")["session_id"] == "s_1"

        sub = submit_request("s_1", ProtocolOp[op_alloc(0), op_ry(0, 1.0)])
        @test sub["op"] == "submit"
        @test sub["session_id"] == "s_1"
        @test length(sub["ops"]) == 2

        @test ok_response()["ok"] === true
        @test ok_response(; duration_ms=4.0)["duration_ms"] == 4.0
        @test ok_response(; results=Dict{String,Bool}("m0" => true))["results"]["m0"] === true

        e = err_response("capacity_exceeded"; detail="need 17, have 16")
        @test e["ok"] === false
        @test e["err"] == "capacity_exceeded"
        @test e["detail"] == "need 17, have 16"
    end

    @testset "Submit message end-to-end ser/de" begin
        ops = ProtocolOp[
            op_alloc(0), op_alloc(1),
            op_ry(0, π / 2),
            op_cx(0, 1),
            op_measure(0, "m0"),
            op_discard(0),
        ]
        msg = submit_request("s_a3f9", ops)
        encoded = json_encode(msg)
        decoded = json_decode(encoded)
        @test decoded["v"] == PROTOCOL_VERSION
        @test decoded["op"] == "submit"
        @test decoded["session_id"] == "s_a3f9"
        @test length(decoded["ops"]) == 6
        @test from_json_dict(decoded["ops"][1]) == op_alloc(0)
        ry_back = from_json_dict(decoded["ops"][3])
        @test ry_back.verb === :ry
        @test ry_back.fields["theta"] ≈ π / 2
        @test from_json_dict(decoded["ops"][5]) == op_measure(0, "m0")
    end

    @testset "from_json_dict rejects unknown / missing verb" begin
        @test_throws ProtocolError from_json_dict(Dict{String,Any}("g" => "swap"))
        @test_throws ProtocolError from_json_dict(Dict{String,Any}("qubit" => 3))
    end
end
