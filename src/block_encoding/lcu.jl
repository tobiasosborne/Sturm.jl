# LCU (Linear Combination of Unitaries) block encoding assembly.
#
# Given H = Σ_j h_j P_j, construct a block encoding U such that:
#
#   ⟨0|^a U |0⟩^a = H / λ
#
# where λ = Σ|h_j| is the 1-norm and a = ⌈log₂ L⌉ ancilla qubits.
#
# The oracle is:
#   U = (PREPARE† ⊗ I) · SELECT · (PREPARE ⊗ I)
#
# Since SELECT is self-adjoint for Pauli strings:
#   U† = (PREPARE ⊗ I) · SELECT · (PREPARE† ⊗ I)
#
# Ref: Berry, Childs, Cleve, Kothari, Somma (2015),
#      PRL 114:090502, Eq. (4)–(8).
#      arXiv:1412.4687
#      Local PDF: docs/literature/quantum_simulation/lcu_taylor_series/1412.4687.pdf
#
# Ref: Gilyén, Su, Low, Wiebe (2019), STOC'19, Lemma 47–48
#      (block encoding from LCU decomposition).
#      arXiv:1806.01838
#      Local PDF: docs/literature/quantum_simulation/qsp_qsvt/1806.01838.pdf

"""
    block_encode_lcu(H::PauliHamiltonian{N}) -> BlockEncoding{N, A}

Construct an LCU block encoding of Hamiltonian H.

The returned `BlockEncoding{N, A}` has:
- `oracle!(ancillas, system)`: applies U = PREPARE†·SELECT·PREPARE
- `oracle_adj!(ancillas, system)`: applies U† = PREPARE·SELECT·PREPARE†
- `alpha = λ = Σ|h_j|` (the 1-norm)
- `n_ancilla = ⌈log₂(nterms(H))⌉`

The ancilla and system registers must be provided by the caller.
Ancillas should start in |0⟩^a for the block encoding identity to hold.

# Example
```julia
H = ising(Val(2), J=1.0, h=0.5)
be = block_encode_lcu(H)
# be.oracle!(ancilla_qubits, system_qubits)
# Post-select ancilla = |0⟩ to get H/λ acting on system
```

Ref: BCKS-PRL15 Eq. (4)–(8); GSLW19 Lemma 47.
"""
function block_encode_lcu(H::PauliHamiltonian{N}) where {N}
    L = nterms(H)
    L >= 1 || error("block_encode_lcu: Hamiltonian must have at least 1 term")
    lam = lambda(H)
    lam > 0 || error("block_encode_lcu: Hamiltonian 1-norm must be > 0")

    a = max(1, Int(ceil(log2(L))))  # at least 1 ancilla qubit

    # U = PREPARE† · SELECT · PREPARE
    #
    # When called inside when(ctrl), PREPARE must run unconditionally so that
    # the controlled-U decomposition works:
    #   PREPARE_uncond · controlled(SELECT) · PREPARE†_uncond = controlled(U)
    #
    # Proof: V·controlled(W)·V† = controlled(V·W·V†) when V (PREPARE) acts
    # on ancilla qubits disjoint from the control qubit.
    #
    # The control stack is saved/cleared for PREPARE, restored for SELECT
    # (which handles multi-control via Toffoli cascade), then cleared again
    # for PREPARE†, and finally restored.
    #
    # Ref: Laneve (2025), arXiv:2503.03026, Algorithm 2 + QSVT circuit.
    function oracle!(ancillas::Vector{QBool}, system::Vector{QBool})
        controls = ancillas[1].ctx.control_stack
        has_controls = !isempty(controls)
        local saved
        if has_controls
            saved = copy(controls)
            empty!(controls)
        end
        try
            _prepare!(ancillas, H)            # unconditional
            if has_controls
                append!(controls, saved)
            end
            _select!(ancillas, system, H)     # controlled (if inside when)
            if has_controls
                empty!(controls)
            end
            _prepare_adj!(ancillas, H)        # unconditional
        finally
            # Always restore the control stack, even on exception
            if has_controls
                empty!(controls)
                append!(controls, saved)
            end
        end
        return nothing
    end

    # U† = PREPARE · SELECT† · PREPARE† (temporal order)
    # Same control-stack isolation as oracle!.
    function oracle_adj!(ancillas::Vector{QBool}, system::Vector{QBool})
        controls = ancillas[1].ctx.control_stack
        has_controls = !isempty(controls)
        local saved
        if has_controls
            saved = copy(controls)
            empty!(controls)
        end
        try
            _prepare!(ancillas, H)            # unconditional
            if has_controls
                append!(controls, saved)
            end
            _select_adj!(ancillas, system, H) # controlled (if inside when)
            if has_controls
                empty!(controls)
            end
            _prepare_adj!(ancillas, H)        # unconditional
        finally
            if has_controls
                empty!(controls)
                append!(controls, saved)
            end
        end
        return nothing
    end

    return BlockEncoding{N, a}(oracle!, oracle_adj!, Float64(lam))
end
