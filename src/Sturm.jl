module Sturm

# Orkan FFI bindings
include("orkan/ffi.jl")
include("orkan/state.jl")

# Core types
include("types/wire.jl")
include("context/abstract.jl")
include("context/eager.jl")
include("context/density.jl")
include("types/quantum.jl")
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
include("channel/draw.jl")
include("channel/pixels.jl")

# Quantum control (must come before gates, passes, and library)
include("control/when.jl")

# Bennett.jl reversible circuit integration
include("bennett/bridge.jl")

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
include("qecc/channel_encode.jl")

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

# Block encoding (LCU, query-model algorithms)
include("block_encoding/types.jl")
include("block_encoding/prepare.jl")
include("block_encoding/select.jl")
include("block_encoding/lcu.jl")
include("block_encoding/algebra.jl")

# QSVT (quantum singular value transformation)
include("qsvt/conventions.jl")
include("qsvt/polynomials.jl")
include("qsvt/phase_factors.jl")
include("qsvt/circuit.jl")

# ── Module init (runs at load time, not precompile time) ─────────────────────
function __init__()
    _set_omp_threads!()
end

# ── Exports ───────────────────────────────────────────────────────────────────

# Context
export AbstractContext, EagerContext, DensityMatrixContext, TracingContext, @context, current_context

# Types
export QBool, QInt, WireID, discard!, Quantum
export with_silent_casts

# Quantum control
export when

# Gates (standard library, not primitives)
export H!, X!, Y!, Z!, S!, T!, Sdg!, Tdg!, swap!

# Library patterns
export superpose!, interfere!, fourier_sample, phase_estimate
export find, amplify, phase_flip!

# Channel / tracing
export Channel, trace, to_openqasm, to_ascii, to_pixels, to_png, ⊗, n_inputs, n_outputs
export PixelScheme, birren_dark_scheme, birren_light_scheme
export ClassicalRef

# Optimisation passes
export gate_cancel, defer_measurements, optimise

# Noise
export depolarise!, dephase!, amplitude_damp!, classicalise

# QECC
export AbstractCode, Steane, encode!, decode!, encode

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

# Block encoding
export BlockEncoding, block_encode_lcu

# QSVT
export QSVTPhases, apply_processing_op!
export qsvt_combined_reflect!, oaa_amplify!

# Bennett integration
export apply_reversible!, apply_oracle!, build_wire_map, estimate_oracle_resources
export oracle, quantum, QuantumOracle

end # module Sturm
