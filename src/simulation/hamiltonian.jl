# Hamiltonian representation as weighted sums of Pauli strings.
#
# Every Hermitian operator on N qubits decomposes as H = Σⱼ hⱼ Pⱼ where
# Pⱼ ∈ {I, X, Y, Z}^⊗N and hⱼ ∈ ℝ (real, since Paulis are Hermitian and
# form an orthogonal basis under the Hilbert-Schmidt inner product).
#
# Ref: Whitfield, Biamonte, Aspuru-Guzik (2011), "Simulation of electronic
#      structure Hamiltonians using quantum computers", Mol. Phys. 109:735-750,
#      arXiv:1001.3855, Section 3.1.
#      Local PDF: docs/literature/quantum_simulation/applications_chemistry/1001.3855.pdf

"""
    PauliOp

Single-qubit Pauli operator: `pauli_I`, `pauli_X`, `pauli_Y`, `pauli_Z`.
"""
@enum PauliOp::UInt8 pauli_I=0 pauli_X=1 pauli_Y=2 pauli_Z=3

"""
    PauliTerm{N}

A single weighted Pauli string: `coeff × (P₁ ⊗ P₂ ⊗ … ⊗ Pₙ)`.

The coefficient is real (Hermitian Hamiltonians). The operators are stored
as an NTuple{N, PauliOp} for stack allocation and Julia specialisation on N.
"""
struct PauliTerm{N}
    coeff::Float64
    ops::NTuple{N, PauliOp}
end

"""
    PauliHamiltonian{N}

Hamiltonian H = Σⱼ hⱼ Pⱼ on N qubits. The 1-norm λ = Σⱼ |hⱼ| controls
Trotter error bounds (Childs et al. 2021, Eq. 1) and LCU query complexity
(Berry et al. 2015).

Ref: Childs, Su, Tran, Wiebe, Zhu (2021), "Theory of Trotter Error with
     Commutator Scaling", Phys. Rev. X 11:011020.
     Local PDF: docs/literature/quantum_simulation/product_formulas/1912.08854.pdf
"""
struct PauliHamiltonian{N}
    terms::Vector{PauliTerm{N}}

    function PauliHamiltonian{N}(terms::Vector{PauliTerm{N}}) where {N}
        N >= 1 || error("PauliHamiltonian: N must be >= 1, got $N")
        isempty(terms) && error("PauliHamiltonian: must have at least one term")
        new{N}(terms)
    end
end

nqubits(::PauliHamiltonian{N}) where {N} = N
nterms(H::PauliHamiltonian) = length(H.terms)

"""
    lambda(H::PauliHamiltonian) -> Float64

1-norm of the coefficients: λ = Σⱼ |hⱼ|.
"""
lambda(H::PauliHamiltonian) = mapreduce(t -> abs(t.coeff), +, H.terms; init=0.0)

"""
    _support_count(t::PauliTerm{N}) -> Int

Number of non-identity Paulis (weight). Zero allocation.
"""
@inline function _support_count(t::PauliTerm{N}) where {N}
    c = 0
    @inbounds for i in 1:N
        t.ops[i] != pauli_I && (c += 1)
    end
    c
end

function Base.show(io::IO, H::PauliHamiltonian{N}) where {N}
    print(io, "PauliHamiltonian{$N}($(nterms(H)) terms, λ=$(round(lambda(H), digits=4)))")
end

# ── Arithmetic ───────────────────────────────────────────────────────────────

Base.:+(H1::PauliHamiltonian{N}, H2::PauliHamiltonian{N}) where {N} =
    PauliHamiltonian{N}(vcat(H1.terms, H2.terms))

function Base.:*(c::Real, H::PauliHamiltonian{N}) where {N}
    PauliHamiltonian{N}([PauliTerm{N}(c * t.coeff, t.ops) for t in H.terms])
end
Base.:*(H::PauliHamiltonian, c::Real) = c * H

# ── Convenience constructors ─────────────────────────────────────────────────

@inline function _sym_to_pauli(s::Symbol)
    s === :I && return pauli_I
    s === :X && return pauli_X
    s === :Y && return pauli_Y
    s === :Z && return pauli_Z
    error("pauli_term: unknown Pauli '$s'. Expected :I, :X, :Y, :Z.")
end

"""
    pauli_term(coeff, ops::Symbol...) -> PauliTerm{N}

Convenience: `pauli_term(0.5, :X, :Z)` creates 0.5 × X⊗Z.
"""
function pauli_term(coeff::Real, ops::Symbol...)
    N = length(ops)
    N >= 1 || error("pauli_term: need at least 1 operator")
    pops = ntuple(i -> _sym_to_pauli(ops[i]), N)
    PauliTerm{N}(Float64(coeff), pops)
end

"""
    hamiltonian(terms::PauliTerm{N}...) -> PauliHamiltonian{N}

Construct a PauliHamiltonian from individual terms.

# Example
```julia
H = hamiltonian(
    pauli_term(-1.0, :Z, :Z),
    pauli_term(-0.5, :X, :I),
    pauli_term(-0.5, :I, :X),
)
```
"""
hamiltonian(terms::PauliTerm{N}...) where {N} = PauliHamiltonian{N}(collect(terms))
