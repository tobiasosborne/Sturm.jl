module Sturm

# Orkan FFI bindings
include("orkan/ffi.jl")
include("orkan/state.jl")

# Core types
include("types/wire.jl")
include("context/abstract.jl")
include("context/eager.jl")
include("types/qbool.jl")

# Quantum control
include("control/when.jl")

# Convenience gates (built from primitives)
include("gates.jl")

# ── Exports ───────────────────────────────────────────────────────────────────

# Context
export AbstractContext, EagerContext, @context, current_context

# Types
export QBool, WireID, discard!

# Quantum control
export when

# Gates (standard library, not primitives)
export H!, X!, Y!, Z!, S!, T!, Sdg!, Tdg!, swap!

end # module Sturm
