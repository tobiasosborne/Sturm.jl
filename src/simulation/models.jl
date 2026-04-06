# Standard model Hamiltonians for benchmarking and testing.
#
# Ref: Childs, Su, Tran, Wiebe, Zhu (2021), "A Theory of Trotter Error",
#      arXiv:1912.08854, Eq. (99) for the transverse-field Ising model.
#      Local PDF: docs/literature/quantum_simulation/product_formulas/1912.08854.pdf
#
# Their convention: H = -A - B with A = Σ j_{u,v} Z_u Z_v, B = Σ h_u X_u
# (negative signs, non-negative coefficients).
#
# Our convention: H = J Σ Z_i Z_{i+1} + h Σ X_i. The user controls the
# sign via J and h. Positive J → ferromagnetic (aligned ground state).

"""
    ising(::Val{N}; J=1.0, h=0.0) -> PauliHamiltonian{N}

Transverse-field Ising model on N qubits with open boundary conditions:
    H = J Σᵢ ZᵢZᵢ₊₁ + h Σᵢ Xᵢ

The quantum critical point is at |h/J| = 1 for the 1D chain.

Ref: Childs et al. (2021), arXiv:1912.08854, Eq. (99).
     Local PDF: docs/literature/quantum_simulation/product_formulas/1912.08854.pdf
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

"""Convenience: `ising(4, J=1.0)` delegates to `ising(Val(4), J=1.0)`."""
ising(N::Int; kwargs...) = ising(Val(N); kwargs...)

"""
    heisenberg(::Val{N}; Jx=1.0, Jy=1.0, Jz=1.0) -> PauliHamiltonian{N}

Heisenberg XXZ model on N qubits with open boundary conditions:
    H = Σᵢ (Jx XᵢXᵢ₊₁ + Jy YᵢYᵢ₊₁ + Jz ZᵢZᵢ₊₁)

The isotropic XXX model has Jx = Jy = Jz.

Ref: Childs et al. (2021), arXiv:1912.08854, Eq. (288) defines a general
     ferromagnetic spin system with XX+YY couplings. Our convention exposes
     independent Jx, Jy, Jz for the full XXZ model.
     Local PDF: docs/literature/quantum_simulation/product_formulas/1912.08854.pdf
"""
function heisenberg(::Val{N}; Jx::Real=1.0, Jy::Real=1.0, Jz::Real=1.0) where {N}
    N >= 2 || error("heisenberg: need at least 2 qubits, got $N")
    terms = PauliTerm{N}[]
    for i in 1:(N-1)
        for (J, P) in ((Float64(Jx), pauli_X), (Float64(Jy), pauli_Y), (Float64(Jz), pauli_Z))
            J == 0 && continue
            ops = ntuple(k -> (k == i || k == i+1) ? P : pauli_I, N)
            push!(terms, PauliTerm{N}(J, ops))
        end
    end
    PauliHamiltonian{N}(terms)
end

"""Convenience: `heisenberg(4, Jx=1.0)` delegates to `heisenberg(Val(4), Jx=1.0)`."""
heisenberg(N::Int; kwargs...) = heisenberg(Val(N); kwargs...)
