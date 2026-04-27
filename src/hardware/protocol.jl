# Hardware backend protocol — wire format between Sturm and the device.
#
# v0.1: NDJSON over TCP (or in-process). Every message is a one-line JSON
# object terminated by '\n'. See bead Sturm.jl-hlv for the full spec.
#
# Design choices:
#   - Hand-rolled minimal JSON encoder/decoder (no external dep). Handles only
#     what the protocol uses: nothing/Bool/Integer/Float64/String/Vector/Dict.
#   - ProtocolOp is the unit of submission: a verb (Symbol) + a flat Dict of
#     fields. Eight verbs cover the Sturm primitive set + lifecycle:
#       :alloc, :discard, :ry, :rz, :cx, :ccx, :measure, :barrier
#   - Every message envelope carries `"v": PROTOCOL_VERSION` for forward
#     compatibility.

const PROTOCOL_VERSION = 1

const _VALID_VERBS = (:alloc, :discard, :ry, :rz, :cx, :ccx, :measure, :barrier)

struct ProtocolError <: Exception
    msg::String
end
Base.showerror(io::IO, e::ProtocolError) = print(io, "ProtocolError: ", e.msg)

# ── ProtocolOp ────────────────────────────────────────────────────────────────

struct ProtocolOp
    verb::Symbol
    fields::Dict{String,Any}
end

Base.:(==)(a::ProtocolOp, b::ProtocolOp) = a.verb === b.verb && a.fields == b.fields
Base.hash(op::ProtocolOp, h::UInt) = hash(op.verb, hash(op.fields, h))

op_alloc(qubit::Integer) =
    ProtocolOp(:alloc, Dict{String,Any}("qubit" => Int(qubit)))
op_discard(qubit::Integer) =
    ProtocolOp(:discard, Dict{String,Any}("qubit" => Int(qubit)))
op_ry(qubit::Integer, theta::Real) =
    ProtocolOp(:ry, Dict{String,Any}("qubit" => Int(qubit), "theta" => Float64(theta)))
op_rz(qubit::Integer, theta::Real) =
    ProtocolOp(:rz, Dict{String,Any}("qubit" => Int(qubit), "theta" => Float64(theta)))
op_cx(control::Integer, target::Integer) =
    ProtocolOp(:cx, Dict{String,Any}("control" => Int(control), "target" => Int(target)))
op_ccx(c1::Integer, c2::Integer, target::Integer) = ProtocolOp(
    :ccx,
    Dict{String,Any}("c1" => Int(c1), "c2" => Int(c2), "target" => Int(target)),
)
op_measure(qubit::Integer, id::AbstractString) =
    ProtocolOp(:measure, Dict{String,Any}("qubit" => Int(qubit), "id" => String(id)))
op_barrier() = ProtocolOp(:barrier, Dict{String,Any}())

"""Convert a ProtocolOp to a JSON-ready Dict (verb stored under key "g")."""
function to_json_dict(op::ProtocolOp)::Dict{String,Any}
    d = copy(op.fields)
    d["g"] = String(op.verb)
    return d
end

"""Reconstruct a ProtocolOp from a decoded JSON dict. Validates the verb."""
function from_json_dict(d::AbstractDict)::ProtocolOp
    haskey(d, "g") || throw(ProtocolError("op missing 'g' verb field"))
    verb_str = d["g"]
    verb_str isa AbstractString ||
        throw(ProtocolError("op 'g' field must be a string, got $(typeof(verb_str))"))
    verb = Symbol(verb_str)
    verb in _VALID_VERBS ||
        throw(ProtocolError("unknown op verb: $verb_str (valid: $(_VALID_VERBS))"))
    fields = Dict{String,Any}(String(k) => v for (k, v) in d if String(k) != "g")
    return ProtocolOp(verb, fields)
end

# ── Message envelopes ─────────────────────────────────────────────────────────

function open_session_request(; capacity::Integer=16, gate_time_ms::Real=1.0)
    Dict{String,Any}(
        "v" => PROTOCOL_VERSION,
        "op" => "open_session",
        "capacity" => Int(capacity),
        "gate_time_ms" => Float64(gate_time_ms),
    )
end

function close_session_request(session_id::AbstractString)
    Dict{String,Any}(
        "v" => PROTOCOL_VERSION,
        "op" => "close_session",
        "session_id" => String(session_id),
    )
end

function submit_request(session_id::AbstractString, ops::AbstractVector{ProtocolOp})
    Dict{String,Any}(
        "v" => PROTOCOL_VERSION,
        "op" => "submit",
        "session_id" => String(session_id),
        "ops" => Any[to_json_dict(o) for o in ops],
    )
end

function ok_response(;
    results::AbstractDict=Dict{String,Bool}(),
    duration_ms::Real=0.0,
    extras::AbstractDict=Dict{String,Any}(),
)
    d = Dict{String,Any}(
        "v" => PROTOCOL_VERSION,
        "ok" => true,
        "results" => Dict{String,Any}(String(k) => v for (k, v) in results),
        "duration_ms" => Float64(duration_ms),
    )
    for (k, v) in extras
        d[String(k)] = v
    end
    return d
end

function err_response(err::AbstractString; detail::AbstractString="")
    Dict{String,Any}(
        "v" => PROTOCOL_VERSION,
        "ok" => false,
        "err" => String(err),
        "detail" => String(detail),
    )
end

# ── Hand-rolled JSON encoder ──────────────────────────────────────────────────

"""
    json_encode(v) -> String

Encode a Julia value to a JSON string. Supports nothing, Bool, Integer,
AbstractFloat (must be finite), AbstractString, AbstractVector, AbstractDict.
Throws ProtocolError on non-finite floats or unsupported types.
"""
function json_encode(v)::String
    io = IOBuffer()
    _json_encode(io, v)
    return String(take!(io))
end

_json_encode(io::IO, ::Nothing) = print(io, "null")
_json_encode(io::IO, b::Bool) = print(io, b ? "true" : "false")
_json_encode(io::IO, n::Integer) = print(io, n)

function _json_encode(io::IO, x::AbstractFloat)
    isfinite(x) || throw(ProtocolError("non-finite float not representable in JSON: $x"))
    print(io, x)
end

function _json_encode(io::IO, s::AbstractString)
    print(io, '"')
    for c in s
        if c == '"'
            print(io, "\\\"")
        elseif c == '\\'
            print(io, "\\\\")
        elseif c == '\n'
            print(io, "\\n")
        elseif c == '\r'
            print(io, "\\r")
        elseif c == '\t'
            print(io, "\\t")
        elseif c < ' '
            print(io, "\\u", lpad(string(UInt(c); base=16), 4, '0'))
        else
            print(io, c)
        end
    end
    print(io, '"')
end

function _json_encode(io::IO, v::AbstractVector)
    print(io, '[')
    for (i, x) in enumerate(v)
        i > 1 && print(io, ',')
        _json_encode(io, x)
    end
    print(io, ']')
end

function _json_encode(io::IO, d::AbstractDict)
    print(io, '{')
    first = true
    for (k, v) in d
        first || print(io, ',')
        first = false
        _json_encode(io, String(k))
        print(io, ':')
        _json_encode(io, v)
    end
    print(io, '}')
end

_json_encode(::IO, x) = throw(ProtocolError("cannot JSON-encode value of type $(typeof(x))"))

# ── Hand-rolled JSON decoder (recursive descent) ──────────────────────────────

mutable struct _Parser
    s::String
    pos::Int  # 1-based byte index into s
end

@inline _peek(p::_Parser) = p.pos <= ncodeunits(p.s) ? @inbounds(codeunit(p.s, p.pos)) : 0x00
@inline function _advance!(p::_Parser)
    b = _peek(p)
    p.pos += 1
    return b
end

function _skip_ws!(p::_Parser)
    while p.pos <= ncodeunits(p.s)
        b = @inbounds codeunit(p.s, p.pos)
        if b == UInt8(' ') || b == UInt8('\t') || b == UInt8('\n') || b == UInt8('\r')
            p.pos += 1
        else
            break
        end
    end
end

function _expect!(p::_Parser, lit::String)
    n = ncodeunits(lit)
    p.pos + n - 1 <= ncodeunits(p.s) || throw(ProtocolError("expected '$lit' at pos $(p.pos), past end"))
    for i in 1:n
        @inbounds if codeunit(p.s, p.pos + i - 1) != codeunit(lit, i)
            throw(ProtocolError("expected '$lit' at pos $(p.pos)"))
        end
    end
    p.pos += n
end

"""
    json_decode(s::AbstractString) -> Any

Parse a JSON document. Returns nothing | Bool | Int | Float64 | String |
Vector{Any} | Dict{String,Any}. Throws ProtocolError on malformed input or
trailing data.
"""
function json_decode(s::AbstractString)
    p = _Parser(String(s), 1)
    _skip_ws!(p)
    p.pos > ncodeunits(p.s) && throw(ProtocolError("empty input"))
    v = _parse_value!(p)
    _skip_ws!(p)
    p.pos <= ncodeunits(p.s) &&
        throw(ProtocolError("trailing data at pos $(p.pos): $(p.s[p.pos:min(end, p.pos+10)])"))
    return v
end

function _parse_value!(p::_Parser)
    _skip_ws!(p)
    b = _peek(p)
    b == 0x00 && throw(ProtocolError("unexpected end of input at pos $(p.pos)"))
    if b == UInt8('{')
        return _parse_object!(p)
    elseif b == UInt8('[')
        return _parse_array!(p)
    elseif b == UInt8('"')
        return _parse_string!(p)
    elseif b == UInt8('t')
        _expect!(p, "true")
        return true
    elseif b == UInt8('f')
        _expect!(p, "false")
        return false
    elseif b == UInt8('n')
        _expect!(p, "null")
        return nothing
    elseif b == UInt8('-') || (b >= UInt8('0') && b <= UInt8('9'))
        return _parse_number!(p)
    else
        throw(ProtocolError("unexpected character '$(Char(b))' at pos $(p.pos)"))
    end
end

function _parse_object!(p::_Parser)::Dict{String,Any}
    # Bead Sturm.jl-mx3g: never @assert on untrusted network input —
    # AssertionError propagates past `catch e isa ProtocolError` in
    # _handle_connection and kills the connection task. _parse_value!
    # routes here only on '{', so this is defence-in-depth, but a
    # mis-route from any future caller must surface as ProtocolError.
    _peek(p) == UInt8('{') ||
        throw(ProtocolError("expected '{' at pos $(p.pos), got '$(Char(_peek(p)))'"))
    p.pos += 1
    d = Dict{String,Any}()
    _skip_ws!(p)
    if _peek(p) == UInt8('}')
        p.pos += 1
        return d
    end
    while true
        _skip_ws!(p)
        _peek(p) == UInt8('"') ||
            throw(ProtocolError("object key must be a string at pos $(p.pos)"))
        key = _parse_string!(p)
        _skip_ws!(p)
        _peek(p) == UInt8(':') ||
            throw(ProtocolError("expected ':' after key at pos $(p.pos)"))
        p.pos += 1
        val = _parse_value!(p)
        d[key] = val
        _skip_ws!(p)
        b = _peek(p)
        if b == UInt8(',')
            p.pos += 1
            continue
        elseif b == UInt8('}')
            p.pos += 1
            return d
        else
            throw(ProtocolError("expected ',' or '}' in object at pos $(p.pos)"))
        end
    end
end

function _parse_array!(p::_Parser)::Vector{Any}
    _peek(p) == UInt8('[') ||
        throw(ProtocolError("expected '[' at pos $(p.pos), got '$(Char(_peek(p)))'"))
    p.pos += 1
    v = Any[]
    _skip_ws!(p)
    if _peek(p) == UInt8(']')
        p.pos += 1
        return v
    end
    while true
        push!(v, _parse_value!(p))
        _skip_ws!(p)
        b = _peek(p)
        if b == UInt8(',')
            p.pos += 1
            continue
        elseif b == UInt8(']')
            p.pos += 1
            return v
        else
            throw(ProtocolError("expected ',' or ']' in array at pos $(p.pos)"))
        end
    end
end

function _parse_string!(p::_Parser)::String
    _peek(p) == UInt8('"') ||
        throw(ProtocolError("expected '\"' at pos $(p.pos), got '$(Char(_peek(p)))'"))
    p.pos += 1
    io = IOBuffer()
    while true
        p.pos > ncodeunits(p.s) && throw(ProtocolError("unterminated string"))
        b = @inbounds codeunit(p.s, p.pos)
        p.pos += 1
        if b == UInt8('"')
            return String(take!(io))
        elseif b == UInt8('\\')
            p.pos > ncodeunits(p.s) && throw(ProtocolError("trailing backslash in string"))
            esc = @inbounds codeunit(p.s, p.pos)
            p.pos += 1
            if esc == UInt8('"');       write(io, '"')
            elseif esc == UInt8('\\');  write(io, '\\')
            elseif esc == UInt8('/');   write(io, '/')
            elseif esc == UInt8('n');   write(io, '\n')
            elseif esc == UInt8('r');   write(io, '\r')
            elseif esc == UInt8('t');   write(io, '\t')
            elseif esc == UInt8('b');   write(io, '\b')
            elseif esc == UInt8('f');   write(io, '\f')
            elseif esc == UInt8('u')
                p.pos + 3 > ncodeunits(p.s) && throw(ProtocolError("truncated \\u escape"))
                hex = String(view(codeunits(p.s), p.pos:p.pos+3))
                cp = parse(UInt16, hex; base=16)
                p.pos += 4
                write(io, Char(cp))
            else
                throw(ProtocolError("invalid escape \\$(Char(esc)) at pos $(p.pos)"))
            end
        else
            write(io, b)
        end
    end
end

function _parse_number!(p::_Parser)
    start = p.pos
    is_float = false
    if _peek(p) == UInt8('-')
        p.pos += 1
    end
    while p.pos <= ncodeunits(p.s)
        b = @inbounds codeunit(p.s, p.pos)
        if b >= UInt8('0') && b <= UInt8('9')
            p.pos += 1
        elseif b == UInt8('.') || b == UInt8('e') || b == UInt8('E') ||
               b == UInt8('+') || b == UInt8('-')
            is_float = true
            p.pos += 1
        else
            break
        end
    end
    s = SubString(p.s, start, prevind(p.s, p.pos))
    isempty(s) && throw(ProtocolError("expected number at pos $start"))
    if is_float
        return parse(Float64, s)
    else
        n = tryparse(Int, s)
        n === nothing && throw(ProtocolError("invalid number: $s"))
        return n
    end
end
