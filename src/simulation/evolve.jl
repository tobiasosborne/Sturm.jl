# User-facing Hamiltonian simulation API.
# Follows DiffEq.jl's solve(prob, alg) pattern.

"""
    evolve!(qubits::Vector{QBool}, H::PauliHamiltonian{N}, t::Real, alg::AbstractProductFormula)

Apply exp(-iHt) to qubits using a product formula algorithm.
The state is mutated in-place via the context. Returns nothing.
"""
function evolve!(qubits::Vector{QBool}, H::PauliHamiltonian{N}, t::Real,
                 alg::AbstractProductFormula) where {N}
    length(qubits) == N || error(
        "evolve!: expected $N qubits for PauliHamiltonian{$N}, got $(length(qubits))")
    for q in qubits; check_live!(q); end
    t >= 0 || error("evolve!: time must be non-negative, got $t")
    t == 0 && return nothing
    _apply_formula!(qubits, H, t, alg)
    return nothing
end

"""
    evolve!(reg::QInt{W}, H::PauliHamiltonian{W}, t::Real, alg::AbstractSimAlgorithm)

Apply exp(-iHt) to a QInt register. Returns the register for chaining.

# Example
```julia
@context EagerContext() begin
    H = ising(Val(3), J=1.0, h=0.5)
    q = QInt{3}(0)
    evolve!(q, H, 0.1, Trotter2(steps=10))
    result = Int(q)
end
```
"""
function evolve!(reg::QInt{W}, H::PauliHamiltonian{W}, t::Real,
                 alg::AbstractSimAlgorithm) where {W}
    check_live!(reg)
    ctx = reg.ctx
    qubits = [QBool(reg.wires[i], ctx, false) for i in 1:W]
    evolve!(qubits, H, t, alg)
    return reg
end
