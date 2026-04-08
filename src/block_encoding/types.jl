# Block encoding types for query-model quantum algorithms.
#
# A (α, a)-block encoding of an operator A is a unitary U acting on
# (system + ancilla) qubits such that:
#
#   A = α ⟨0|^⊗a  U  |0⟩^⊗a
#
# where the ancilla register starts and ends in |0⟩^⊗a, and α ≥ ||A||
# is a subnormalization factor.
#
# Ref: Gilyen, Su, Low, Wiebe (2019), "Quantum singular value
#      transformations and beyond", STOC'19, Definition 25.
#      arXiv:1806.01838
#      Local PDF: docs/literature/quantum_simulation/query_model/1806.01838.pdf

"""
    BlockEncoding{N, A}

Block encoding of an N-qubit operator using A ancilla qubits.

The oracle U acts on (ancilla, system) registers. The encoded operator is
retrieved by projecting the ancilla onto |0⟩^⊗A:

    encoded_op = α ⟨0|^⊗A  U  |0⟩^⊗A

Fields:
- `oracle!`: Function(ancillas::Vector{QBool}, system::Vector{QBool}) -> nothing
- `oracle_adj!`: Adjoint of the oracle
- `alpha`: Subnormalization factor (||encoded_op|| ≤ α)
- `n_system`: Number of system qubits (N)
- `n_ancilla`: Number of ancilla qubits (A)

Ref: GSLW19, Definition 25.
"""
struct BlockEncoding{N, A}
    oracle!::Function
    oracle_adj!::Function
    alpha::Float64
    n_system::Int
    n_ancilla::Int

    function BlockEncoding{N, A}(oracle!::Function, oracle_adj!::Function,
                                  alpha::Float64) where {N, A}
        N >= 1 || error("BlockEncoding: n_system must be >= 1, got $N")
        A >= 1 || error("BlockEncoding: n_ancilla must be >= 1, got $A")
        alpha > 0 || error("BlockEncoding: alpha must be > 0, got $alpha")
        new{N, A}(oracle!, oracle_adj!, alpha, N, A)
    end
end
