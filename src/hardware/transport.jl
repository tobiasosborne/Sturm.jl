# Transport layer — abstracts the wire between HardwareContext and the device.
#
# v0.1: InProcessTransport (direct dispatch, no serialisation).
# v0.1: TCPTransport ships in HW5 with the standalone server (bin/sturm-sim.jl)
# so that client and server can be developed and tested in lock-step.
#
# AbstractTransport contract: a single method
#   request(::AbstractTransport, msg::Dict) -> Dict
#
# `request` is synchronous: blocks until a response is available. Errors at the
# protocol level (capacity exceeded, unknown verb, etc.) come back as
# {ok: false, err: ...} responses, NOT thrown exceptions. Errors at the
# transport level (connection drop, malformed JSON on the wire) ARE thrown.

abstract type AbstractTransport end

"""
    request(t::AbstractTransport, msg::AbstractDict) -> Dict{String,Any}

Send a single protocol message and block until the response is returned.
Implementations must guarantee one response per request.
"""
function request(t::AbstractTransport, ::AbstractDict)::Dict{String,Any}
    error("request not implemented for $(typeof(t))")
end

# ── In-process transport ──────────────────────────────────────────────────────
#
# Carries messages by direct function call to dispatch! on the wrapped
# IdealisedSimulator. No JSON ser/de, no socket. Used for unit tests and for
# users who want a hardware-shaped backend without standing up a server.

struct InProcessTransport <: AbstractTransport
    server::IdealisedSimulator
end

function request(t::InProcessTransport, msg::AbstractDict)::Dict{String,Any}
    return dispatch!(t.server, msg)
end

Base.show(io::IO, t::InProcessTransport) =
    print(io, "InProcessTransport(", t.server.capacity, "q sim)")

# ── TCP transport ─────────────────────────────────────────────────────────────
#
# NDJSON over a single TCP connection. One request → one response, in order.
# Connection drops surface as errors on the next request. No reconnect logic
# in v0.1.

using Sockets: TCPSocket, connect, IPv4

# Default per-operation timeout. A stalled server should NOT hang the
# Sturm session forever — bead Sturm.jl-mx3g.
const TCP_DEFAULT_TIMEOUT_S = 30.0

mutable struct TCPTransport <: AbstractTransport
    sock::TCPSocket
    host::String
    port::Int
    timeout::Float64           # seconds; applies to connect AND each request

    function TCPTransport(host::AbstractString, port::Integer;
                          timeout::Real=TCP_DEFAULT_TIMEOUT_S)
        timeout > 0 ||
            error("TCPTransport: timeout must be > 0, got $timeout")
        sock = _connect_with_timeout(String(host), Int(port), Float64(timeout))
        return new(sock, String(host), Int(port), Float64(timeout))
    end
end

# Connect with a hard wall-clock budget. Pre-fix `connect()` blocked
# indefinitely if the server was unreachable — bead mx3g(b).
function _connect_with_timeout(host::String, port::Int, timeout_s::Float64)
    sock_ref = Ref{Union{TCPSocket,Nothing}}(nothing)
    err_ref = Ref{Any}(nothing)
    task = @async try
        sock_ref[] = connect(IPv4(host), port)
    catch e
        err_ref[] = e
    end
    status = timedwait(() -> istaskdone(task), timeout_s)
    if status === :timed_out
        # Best-effort cancel; the worker task may finish later and its
        # socket (if any) will get GC'd.
        try; schedule(task, InterruptException(); error=true); catch; end
        error("TCPTransport: connect to $host:$port timed out after $(timeout_s)s")
    end
    err_ref[] === nothing ||
        error("TCPTransport: connect to $host:$port failed: $(err_ref[])")
    sock_ref[] === nothing &&
        error("TCPTransport: connect to $host:$port returned nil")
    return sock_ref[]::TCPSocket
end

function request(t::TCPTransport, msg::AbstractDict)::Dict{String,Any}
    isopen(t.sock) ||
        error("TCPTransport: socket to $(t.host):$(t.port) is closed")
    println(t.sock, json_encode(msg))
    flush(t.sock)
    # Bound the read by closing the socket on expiry — readline then
    # returns empty (EOF) and we surface a timeout error. Connection is
    # unusable afterwards, which matches the wedged-server reality.
    timed_out = Ref(false)
    timer = Timer(t.timeout) do _
        timed_out[] = true
        try; close(t.sock); catch; end
    end
    line = try
        readline(t.sock)
    finally
        close(timer)
    end
    if timed_out[]
        error("TCPTransport: recv from $(t.host):$(t.port) timed out after $(t.timeout)s")
    end
    isempty(line) && error("TCPTransport: empty response (server hung up?)")
    decoded = json_decode(line)
    decoded isa AbstractDict ||
        error("TCPTransport: malformed response (not a JSON object): $line")
    return Dict{String,Any}(String(k) => v for (k, v) in decoded)
end

function Base.close(t::TCPTransport)
    isopen(t.sock) && close(t.sock)
end

Base.show(io::IO, t::TCPTransport) = print(io,
    "TCPTransport(", t.host, ":", t.port,
    isopen(t.sock) ? "" : ", CLOSED", ")")
