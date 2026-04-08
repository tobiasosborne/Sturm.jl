# PREPARE oracle for LCU block encoding.
#
# Given H = sum_j h_j P_j with L terms, PREPARE loads:
#
#   PREPARE |0>^{otimes a} = sum_j sqrt(|h_j| / lambda) |j>
#
# where a = ceil(log2(L)) ancilla qubits, lambda = sum |h_j|, and
# |j> is the binary encoding of term index j.
#
# Implementation: binary rotation tree (amplitude encoding).
# At each level of the tree, a controlled Ry rotation splits the
# probability mass between the left and right subtrees.
#
# Tree structure (example for L=4 terms with weights w_0..w_3):
#   Root qubit (MSB): Ry(2 arcsin sqrt((w_2+w_3)/(w_0+w_1+w_2+w_3)))
#     Left child (qubit 1, ctrl=|0>): Ry(2 arcsin sqrt(w_1/(w_0+w_1)))
#     Right child (qubit 1, ctrl=|1>): Ry(2 arcsin sqrt(w_3/(w_2+w_3)))
#
# The key identity: after Ry(2 arcsin sqrt(p)) on |0>:
#   |0> -> sqrt(1-p)|0> + sqrt(p)|1>
# which matches the QBool(p) preparation primitive (Primitive #1).
#
# Ref: Shende, Bullock, Markov (2006), "Synthesis of Quantum Logic Circuits",
#      IEEE Trans. CAD 25(6):1000-1010, Section IV (state preparation).
#      arXiv:quant-ph/0406176
#
# Ref: Grover, Rudolph (2002), "Creating superpositions that correspond to
#      efficiently integrable probability distributions",
#      arXiv:quant-ph/0208112, Theorem 1.
#
# Local PDFs: docs/literature/quantum_simulation/query_model/0406176.pdf
#             docs/literature/quantum_simulation/query_model/0208112.pdf

"""
    _prepare!(ancillas::Vector{QBool}, H::PauliHamiltonian{N})

Apply the PREPARE oracle to ancilla qubits (assumed to start in |0>^a).

After execution:
    |0>^a -> sum_j sqrt(|h_j| / lambda) |j>

where j ranges over term indices (binary encoded on `a` ancilla qubits),
and padded terms (j >= L) have zero coefficient.

The rotation tree recurses on bit slices of the ancilla register,
from MSB (ancillas[a]) down to LSB (ancillas[1]).

Ref: Shende, Bullock, Markov (2006), Section IV; Grover, Rudolph (2002).
"""
function _prepare!(ancillas::Vector{QBool}, H::PauliHamiltonian{N}) where {N}
    a = length(ancillas)
    a >= 1 || error("_prepare!: need at least 1 ancilla qubit")
    L = nterms(H)
    lam = lambda(H)
    lam > 0 || error("_prepare!: Hamiltonian 1-norm is zero")

    # Build weight array: |h_j| for j=0..2^a-1 (zero-padded)
    n_slots = 1 << a
    weights = zeros(Float64, n_slots)
    for j in 1:L
        weights[j] = abs(H.terms[j].coeff)
    end

    # Apply the binary rotation tree.
    # We process the ancilla register from MSB (ancillas[a]) to LSB (ancillas[1]).
    # At each level, the qubit splits the index space into halves.
    #
    # Convention: ancillas[1] is LSB (bit 0), ancillas[a] is MSB (bit a-1).
    # The tree processes from MSB to LSB because each level's rotation
    # must be controlled on all higher-level qubits (the path from root).
    _rotation_tree!(ancillas, weights, a, 0, n_slots)
    return nothing
end

"""
    _rotation_tree!(ancillas, weights, level, offset, span)

Recursive binary rotation tree for amplitude encoding.

- `level`: current bit being processed (a = MSB, 1 = LSB)
- `offset`: start index in the weights array (0-based)
- `span`: number of slots in the current subtree

At each node: split the span in half. The rotation angle is determined
by the fraction of weight in the right (|1>) half:

    p_right = sum(weights[right_half]) / sum(weights[full_span])
    angle = 2 * arcsin(sqrt(p_right))

The rotation is applied to ancillas[level], which corresponds to the
bit that distinguishes left from right at this level.

Ref: Grover, Rudolph (2002), arXiv:quant-ph/0208112.
"""
function _rotation_tree!(ancillas::Vector{QBool}, weights::Vector{Float64},
                          level::Int, offset::Int, span::Int)
    level >= 1 || return  # base case: no more qubits

    half = span >> 1
    half >= 1 || return  # span too small to split

    # Compute weight sums for left and right halves
    # Left half: indices offset..(offset+half-1)
    # Right half: indices (offset+half)..(offset+span-1)
    w_total = sum(@view weights[offset+1:offset+span])

    if w_total < 1e-30
        # Zero total weight: no rotation needed (qubit stays |0>)
        return
    end

    w_right = sum(@view weights[offset+half+1:offset+span])
    p_right = w_right / w_total

    # Clamp for numerical safety
    p_right = clamp(p_right, 0.0, 1.0)

    if p_right > 1e-15
        # Ry(2 arcsin sqrt(p_right)) on this ancilla qubit
        # This transforms |0> -> sqrt(1-p_right)|0> + sqrt(p_right)|1>
        angle = 2.0 * asin(sqrt(p_right))
        ancillas[level].θ += angle
    end

    # Recurse: left subtree (this qubit = |0>)
    if level > 1
        # To apply rotations conditioned on this qubit being |0>,
        # we flip it (X), condition on |1> via when(), then flip back.
        X!(ancillas[level])
        when(ancillas[level]) do
            _rotation_tree!(ancillas, weights, level - 1, offset, half)
        end
        X!(ancillas[level])

        # Right subtree (this qubit = |1>)
        when(ancillas[level]) do
            _rotation_tree!(ancillas, weights, level - 1, offset + half, half)
        end
    end

    return nothing
end

"""
    _prepare_adj!(ancillas::Vector{QBool}, H::PauliHamiltonian{N})

Adjoint of the PREPARE oracle. Reverses all rotations to map the
prepared state back to |0>^a.

The adjoint of a rotation tree is obtained by traversing in reverse
order (LSB to MSB) and negating all rotation angles.

Ref: Shende, Bullock, Markov (2006), Section IV.
"""
function _prepare_adj!(ancillas::Vector{QBool}, H::PauliHamiltonian{N}) where {N}
    a = length(ancillas)
    a >= 1 || error("_prepare_adj!: need at least 1 ancilla qubit")
    L = nterms(H)
    lam = lambda(H)
    lam > 0 || error("_prepare_adj!: Hamiltonian 1-norm is zero")

    n_slots = 1 << a
    weights = zeros(Float64, n_slots)
    for j in 1:L
        weights[j] = abs(H.terms[j].coeff)
    end

    _rotation_tree_adj!(ancillas, weights, a, 0, n_slots)
    return nothing
end

"""
    _rotation_tree_adj!(ancillas, weights, level, offset, span)

Adjoint of the binary rotation tree. Applies the same structure
but in reverse order with negated angles.

For a unitary U = U_n ... U_2 U_1, the adjoint is U† = U_1† U_2† ... U_n†.
Each Ry(theta)† = Ry(-theta).
"""
function _rotation_tree_adj!(ancillas::Vector{QBool}, weights::Vector{Float64},
                              level::Int, offset::Int, span::Int)
    level >= 1 || return
    half = span >> 1
    half >= 1 || return

    w_total = sum(@view weights[offset+1:offset+span])
    if w_total < 1e-30
        return
    end

    w_right = sum(@view weights[offset+half+1:offset+span])
    p_right = clamp(w_right / w_total, 0.0, 1.0)

    # Adjoint: recurse children FIRST (reverse order), then undo this rotation.
    # Original order: rotate this qubit, then left subtree, then right subtree.
    # Adjoint order: right subtree adj, left subtree adj, then undo rotation.

    if level > 1
        # Right subtree adjoint first
        when(ancillas[level]) do
            _rotation_tree_adj!(ancillas, weights, level - 1, offset + half, half)
        end

        # Left subtree adjoint
        X!(ancillas[level])
        when(ancillas[level]) do
            _rotation_tree_adj!(ancillas, weights, level - 1, offset, half)
        end
        X!(ancillas[level])
    end

    # Undo the rotation on this qubit (negate angle)
    if p_right > 1e-15
        angle = 2.0 * asin(sqrt(p_right))
        ancillas[level].θ -= angle
    end

    return nothing
end
