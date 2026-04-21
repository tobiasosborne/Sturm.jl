# Standalone TCP server for IdealisedSimulator.
#
# Wire format: NDJSON (one JSON object per line, newline-terminated, both
# directions). Per connection: a Task that reads a line, parses, dispatches
# via dispatch!(sim, msg), writes the response + '\n', loops until EOF.
#
# Multiple clients can connect concurrently — each gets its own per-connection
# Task. Sessions are server-wide (the simulator's `sessions` Dict), so two
# clients can hold distinct sessions over the same simulator.

using Sockets: TCPServer, listen, accept, getsockname, IPv4

"""
    start_server(sim::IdealisedSimulator; port=0, host="127.0.0.1")
        -> (TCPServer, Int, Task)

Bind a TCP listener and start accepting connections in a background Task.
Returns the server socket, the bound port (resolved if `port=0`), and the
accept Task. Use [`stop_server!`](@ref) to shut down. Non-blocking — the
accept loop runs as a Julia task in the same process.
"""
function start_server(sim::IdealisedSimulator; port::Integer=0,
                      host::AbstractString="127.0.0.1")
    server = listen(IPv4(String(host)), Int(port))
    actual_port = Int(getsockname(server)[2])
    accept_task = @async _accept_loop(server, sim)
    return (server, actual_port, accept_task)
end

"""
    stop_server!(server::TCPServer)

Close the listener. Existing connections complete naturally. The accept Task
exits at the next `accept` failure.
"""
function stop_server!(server::TCPServer)
    close(server)
end

function _accept_loop(server::TCPServer, sim::IdealisedSimulator)
    while true
        conn = try
            accept(server)
        catch
            return  # listener closed
        end
        @async _handle_connection(conn, sim)
    end
end

function _handle_connection(conn, sim::IdealisedSimulator)
    try
        while !eof(conn)
            line = readline(conn)
            isempty(line) && continue
            local resp::Dict{String,Any}
            try
                msg = json_decode(line)
                msg isa AbstractDict ||
                    (resp = err_response("malformed_message"; detail="not an object"); @goto write)
                resp = dispatch!(sim, msg)
            catch e
                e isa ProtocolError || rethrow()
                resp = err_response("malformed_message"; detail=e.msg)
            end
            @label write
            println(conn, json_encode(resp))
            flush(conn)
        end
    catch
        # Connection-level errors (broken pipe, etc.) → just close the
        # connection. Per-message protocol errors are reported as err
        # responses inside the loop above.
    finally
        try
            close(conn)
        catch
        end
    end
end
