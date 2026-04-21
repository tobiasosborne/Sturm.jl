#!/usr/bin/env julia
# Standalone TCP server for the Sturm idealised quantum device.
#
# Usage:
#     julia --project bin/sturm-sim.jl [--port=8765] [--qubits=16]
#                                      [--gate-time-ms=1.0] [--realtime]
#                                      [--host=127.0.0.1]
#
# Stays foreground; ^C to stop.

using Sturm

function _parse_flags(args::Vector{String})
    opts = Dict{String,Any}(
        "port" => 8765,
        "qubits" => 16,
        "gate-time-ms" => 1.0,
        "realtime" => false,
        "host" => "127.0.0.1",
    )
    for arg in args
        if startswith(arg, "--port=")
            opts["port"] = parse(Int, arg[8:end])
        elseif startswith(arg, "--qubits=")
            opts["qubits"] = parse(Int, arg[10:end])
        elseif startswith(arg, "--gate-time-ms=")
            opts["gate-time-ms"] = parse(Float64, arg[16:end])
        elseif startswith(arg, "--host=")
            opts["host"] = arg[8:end]
        elseif arg == "--realtime"
            opts["realtime"] = true
        elseif arg in ("-h", "--help")
            _print_help()
            exit(0)
        else
            println(stderr, "Unknown flag: $arg")
            _print_help()
            exit(2)
        end
    end
    return opts
end

function _print_help()
    println("""
        sturm-sim — idealised quantum device server

        Flags:
          --port=N            TCP port to listen on (default: 8765)
          --qubits=N          Device capacity (default: 16)
          --gate-time-ms=F    Nominal time per unitary gate (default: 1.0)
          --realtime          Sleep duration_ms on each submit to mimic latency
          --host=ADDR         Bind address (default: 127.0.0.1)
          -h, --help          Show this help
        """)
end

function main()
    opts = _parse_flags(ARGS)

    sim = Sturm.IdealisedSimulator(;
        capacity     = opts["qubits"],
        gate_time_ms = opts["gate-time-ms"],
        realtime     = opts["realtime"],
    )

    server, port, accept_task = Sturm.start_server(sim;
        port = opts["port"],
        host = opts["host"],
    )

    println("sturm-sim listening on $(opts["host"]):$port " *
            "(qubits=$(opts["qubits"]), gate_time_ms=$(opts["gate-time-ms"])" *
            (opts["realtime"] ? ", realtime" : "") * ")")
    println("^C to stop.")

    # Block until accept task exits (which it does when the listener is closed).
    # Ctrl-C raises InterruptException out of wait(); catch it and shut down.
    try
        wait(accept_task)
    catch e
        e isa InterruptException || rethrow()
        println("\nstopping…")
    finally
        Sturm.stop_server!(server)
    end
end

main()
