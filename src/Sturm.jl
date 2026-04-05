module Sturm

# Orkan FFI bindings
include("orkan/ffi.jl")
include("orkan/state.jl")

# Core types
include("types/wire.jl")
include("context/abstract.jl")
include("context/eager.jl")
include("types/qbool.jl")
include("types/qint.jl")

# Quantum control
include("control/when.jl")

# Convenience gates (built from primitives)
include("gates.jl")

# Library patterns (higher-order quantum operations)
include("library/patterns.jl")

# ── Module init (runs at load time, not precompile time) ─────────────────────
function __init__()
    _set_omp_threads!()
end

# ── Exports ───────────────────────────────────────────────────────────────────

# Context
export AbstractContext, EagerContext, @context, current_context

# Types
export QBool, QInt, WireID, discard!

# Quantum control
export when

# Gates (standard library, not primitives)
export H!, X!, Y!, Z!, S!, T!, Sdg!, Tdg!, swap!

# Library patterns
export superpose!, interfere!, fourier_sample, phase_estimate

end # module Sturm
