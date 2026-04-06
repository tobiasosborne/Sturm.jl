# Standard model Hamiltonians for benchmarking and testing.

"""
    ising(::Val{N}; J=1.0, h=0.0) -> PauliHamiltonian{N}

Transverse-field Ising model on N qubits with open boundary conditions:
    H = J Σᵢ ZᵢZᵢ₊₁ + h Σᵢ Xᵢ

The quantum critical point is at |h/J| = 1 for the 1D chain.
"""
function ising(::Val{N}; J::Real=1.0, h::Real=0.0) where {N}
    N >= 2 || error("ising: need at least 2 qubits, got $N")
    terms = PauliTerm{N}[]
    for i in 1:(N-1)
        ops = ntuple(k -> (k == i || k == i+1) ? pauli_Z : pauli_I, N)
        push!(terms, PauliTerm{N}(Float64(J), ops))
    end
    if h != 0
        for i in 1:N
            ops = ntuple(k -> k == i ? pauli_X : pauli_I, N)
            push!(terms, PauliTerm{N}(Float64(h), ops))
        end
    end
    PauliHamiltonian{N}(terms)
end

"""
    heisenberg(::Val{N}; Jx=1.0, Jy=1.0, Jz=1.0) -> PauliHamiltonian{N}

Heisenberg model on N qubits with open boundary conditions:
    H = Σᵢ (Jx XᵢXᵢ₊₁ + Jy YᵢYᵢ₊₁ + Jz ZᵢZᵢ₊₁)
"""
function heisenberg(::Val{N}; Jx::Real=1.0, Jy::Real=1.0, Jz::Real=1.0) where {N}
    N >= 2 || error("heisenberg: need at least 2 qubits, got $N")
    terms = PauliTerm{N}[]
    for i in 1:(N-1)
        for (J, P) in ((Jx, pauli_X), (Jy, pauli_Y), (Jz, pauli_Z))
            J == 0 && continue
            ops = ntuple(k -> (k == i || k == i+1) ? P : pauli_I, N)
            push!(terms, PauliTerm{N}(Float64(J), ops))
        end
    end
    PauliHamiltonian{N}(terms)
end
