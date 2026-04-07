module Sturm

# Orkan FFI bindings
include("orkan/ffi.jl")
include("orkan/state.jl")

# Core types
include("types/wire.jl")
include("context/abstract.jl")
include("context/eager.jl")
include("context/density.jl")
include("types/qbool.jl")
include("types/qint.jl")

# Channel / tracing layer
include("channel/dag.jl")
include("context/tracing.jl")
include("types/classical_ref.jl")
include("channel/channel.jl")
include("channel/trace.jl")
include("channel/compose.jl")
include("channel/openqasm.jl")

# Quantum control (must come before gates, passes, and library)
include("control/when.jl")

# Convenience gates (built from primitives)
include("gates.jl")

# Optimisation passes
include("passes/gate_cancel.jl")
include("passes/deferred_measurement.jl")
include("passes/optimise.jl")

# Noise channels
include("noise/channels.jl")
include("noise/classicalise.jl")

# QECC
include("qecc/abstract.jl")
include("qecc/steane.jl")

# Library patterns (higher-order quantum operations)
include("library/patterns.jl")

# Hamiltonian simulation
include("simulation/hamiltonian.jl")
include("simulation/pauli_exp.jl")
include("simulation/trotter.jl")
include("simulation/qdrift.jl")
include("simulation/composite.jl")
include("simulation/error_bounds.jl")
include("simulation/models.jl")
include("simulation/evolve.jl")

# ── Module init (runs at load time, not precompile time) ─────────────────────
function __init__()
    _set_omp_threads!()
end

# ── Exports ───────────────────────────────────────────────────────────────────

# Context
export AbstractContext, EagerContext, DensityMatrixContext, TracingContext, @context, current_context

# Types
export QBool, QInt, WireID, discard!

# Quantum control
export when

# Gates (standard library, not primitives)
export H!, X!, Y!, Z!, S!, T!, Sdg!, Tdg!, swap!

# Library patterns
export superpose!, interfere!, fourier_sample, phase_estimate
export find, amplify, phase_flip!

# Channel / tracing
export Channel, trace, to_openqasm, ⊗, n_inputs, n_outputs
export ClassicalRef

# Optimisation passes
export gate_cancel, defer_measurements, optimise

# Noise
export depolarise!, dephase!, amplitude_damp!, classicalise

# QECC
export AbstractCode, Steane, encode!, decode!

# Simulation
export PauliOp, pauli_I, pauli_X, pauli_Y, pauli_Z
export PauliTerm, PauliHamiltonian, pauli_term, hamiltonian
# nqubits, nterms, lambda intentionally NOT exported — too generic.
# Access via Sturm.nqubits(H), Sturm.lambda(H), or nterms(H) after `using Sturm`
# if users import them explicitly.
export pauli_exp!
export AbstractSimAlgorithm, AbstractProductFormula, AbstractStochasticAlgorithm, AbstractQueryAlgorithm
export Trotter1, Trotter2, Suzuki
export QDrift, qdrift_samples
export Composite
export alpha_comm, trotter_error, trotter_steps
export evolve!
export ising, heisenberg

end # module Sturm
