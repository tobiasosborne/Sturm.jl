"""
    WireID

Opaque symbolic reference into the compilation context's wire graph.
Not a qubit index — the mapping from WireID to physical qubit is managed by the context.
"""
struct WireID
    id::UInt32
end

Base.show(io::IO, w::WireID) = print(io, "Wire(", w.id, ")")
Base.hash(w::WireID, h::UInt) = hash(w.id, h)
Base.:(==)(a::WireID, b::WireID) = a.id == b.id

const _wire_counter = Ref(UInt32(0))

"""Allocate a globally unique WireID."""
function fresh_wire!()
    _wire_counter[] += 1
    WireID(_wire_counter[])
end

"""Reset the wire counter (for testing only)."""
function reset_wire_counter!()
    _wire_counter[] = UInt32(0)
end
