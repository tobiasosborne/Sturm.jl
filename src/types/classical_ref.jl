"""
    ClassicalRef

A symbolic reference to a measurement outcome in a TracingContext.
Produced by measuring a QBool in tracing mode. Converting to Bool
records a classical branch in the DAG.
"""
struct ClassicalRef
    result_id::UInt32
    wire::WireID
    ctx::TracingContext
end

Base.convert(::Type{Bool}, c::ClassicalRef) = false  # default branch in tracing
Base.Bool(c::ClassicalRef) = convert(Bool, c)
