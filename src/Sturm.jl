module Sturm

# Orkan FFI bindings
include("orkan/ffi.jl")
include("orkan/state.jl")

# Core types
include("types/wire.jl")
include("context/abstract.jl")
include("context/eager.jl")
include("context/density.jl")
include("context/multi_control.jl")  # shared cascade, needs both context types
include("types/quantum.jl")
include("types/qbool.jl")
include("types/qint.jl")
include("types/qcoset.jl")
include("types/qrunway.jl")
include("types/qrom_table.jl")

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
include("control/cases.jl")

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
include("library/arithmetic.jl")
include("library/coset.jl")
include("library/shor.jl")

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

# Hardware backend (HardwareContext + IdealisedSimulator + protocol)
include("hardware/protocol.jl")
include("hardware/simulator.jl")
include("hardware/transport.jl")
include("hardware/hardware_context.jl")
include("hardware/server.jl")

# ── Module init (runs at load time, not precompile time) ─────────────────────
function __init__()
    _set_omp_threads!()
end

# ── Exports ───────────────────────────────────────────────────────────────────

# Context
export AbstractContext, EagerContext, DensityMatrixContext, TracingContext, @context, current_context

# Types
export QBool, QInt, WireID, ptrace!, discard!, Quantum
export with_silent_casts
export QCoset, QRunway, QROMTable, QROMTableLarge
export coset_add!, runway_add!, runway_decode!

# Quantum control
export when, cases, @cases
export current_controls, with_controls, with_empty_controls

# Gates (standard library, not primitives)
export H!, X!, Y!, Z!, S!, T!, Sdg!, Tdg!, swap!

# Library patterns
export superpose!, interfere!, fourier_sample, phase_estimate
export find, amplify, phase_flip!

# Arithmetic (QFT-based, Draper 2000 + Beauregard 2003 chain)
export add_qft!, sub_qft!, add_qft_quantum!, sub_qft_quantum!,
       modadd!, mulmod_beauregard!

# Bennett bridge: classical-tabulate + QROM for functions Bennett cannot lower
export oracle_table

# Shor's algorithm (docs/physics/nielsen_chuang_5.3.md)
export shor_order_A, shor_factor_A
export shor_order_B, shor_factor_B
export shor_order_C, shor_factor_C
export shor_order_D, shor_factor_D
export shor_order_D_semi, shor_factor_D_semi
export shor_factor_EH

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

# Hardware backend
export HardwareContext, IdealisedSimulator, with_hardware
export AbstractTransport, InProcessTransport, TCPTransport
export start_server, stop_server!

end # module Sturm
