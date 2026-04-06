# Trotter-Suzuki product formula implementations.
#
# Ref: Suzuki, M. (1991), "General theory of fractal path integrals",
#      J. Math. Phys. 32(2):400-407, Eqs. (1.3), (3.2), (3.14), (3.16).
#      Local PDF: docs/literature/quantum_simulation/product_formulas/Suzuki_JMP_32_400_1991.pdf
#
# Error bounds:
#   Order 1: ‖exp(-iHt) - S₁(t/r)^r‖ = O(λ²t²/r)
#   Order 2: ‖exp(-iHt) - S₂(t/r)^r‖ = O(λ³t³/r²)
#   Order 2k: ‖exp(-iHt) - S₂ₖ(t/r)^r‖ = O((λt)^{2k+1}/r^{2k})
#
# Ref: Childs, Su, Tran, Wiebe, Zhu (2021), Phys. Rev. X 11:011020, Thm 1.
#      Local PDF: docs/literature/quantum_simulation/product_formulas/1912.08854.pdf

# ── Abstract type hierarchy ──────────────────────────────────────────────────

"""Base type for Hamiltonian simulation algorithms."""
abstract type AbstractSimAlgorithm end

"""Product formula (Trotter-Suzuki) algorithms."""
abstract type AbstractProductFormula <: AbstractSimAlgorithm end

"""Stochastic/randomised algorithms (qDRIFT, randomised MPF)."""
abstract type AbstractStochasticAlgorithm <: AbstractSimAlgorithm end

"""Query-based algorithms requiring block encodings (LCU, QSVT)."""
abstract type AbstractQueryAlgorithm <: AbstractSimAlgorithm end

# ── Concrete algorithm types ─────────────────────────────────────────────────

"""
    Trotter1(; steps=1)

First-order Lie-Trotter product formula [Suzuki 1991, Eq. (1.3)]:
    S₁(t) = Πⱼ exp(-i t hⱼ Pⱼ)
Error: O((λt)²/r) for r steps.
"""
struct Trotter1 <: AbstractProductFormula
    steps::Int
    function Trotter1(; steps::Int=1)
        steps >= 1 || error("Trotter1: steps must be >= 1, got $steps")
        new(steps)
    end
end

"""
    Trotter2(; steps=1)

Second-order symmetric Trotter (Strang splitting) [Suzuki 1991, Eq. (3.2)]:
    S₂(t) = Πⱼ exp(-i t hⱼ Pⱼ / 2) · Π_{j←L} exp(-i t hⱼ Pⱼ / 2)
Error: O((λt)³/r²) for r steps.
"""
struct Trotter2 <: AbstractProductFormula
    steps::Int
    function Trotter2(; steps::Int=1)
        steps >= 1 || error("Trotter2: steps must be >= 1, got $steps")
        new(steps)
    end
end

"""
    Suzuki(; order=4, steps=1)

Higher-order Suzuki product formula [Suzuki 1991, Eqs. (3.14)-(3.16)]:
    S₂ₖ(t) = [S₂ₖ₋₂(pₖt)]² · S₂ₖ₋₂((1-4pₖ)t) · [S₂ₖ₋₂(pₖt)]²
    pₖ = 1/(4 - 4^{1/(2k-1)})
Order must be even and >= 4.
Error: O((λt)^{2k+1}/r^{2k}) for r steps.
"""
struct Suzuki <: AbstractProductFormula
    order::Int
    steps::Int
    function Suzuki(; order::Int=4, steps::Int=1)
        order >= 4 || error("Suzuki: order must be >= 4 (use Trotter2 for order 2), got $order")
        iseven(order) || error("Suzuki: order must be even, got $order")
        steps >= 1 || error("Suzuki: steps must be >= 1, got $steps")
        new(order, steps)
    end
end

# ── Suzuki recursion coefficient ─────────────────────────────────────────────

"""
    _suzuki_p(k::Int) -> Float64

Recursion coefficient pₖ = 1/(4 - 4^{1/(2k-1)}) [Suzuki 1991, Eq. (3.16)].
Satisfies: 4pₖ + (1-4pₖ) = 1 (time conservation).
"""
function _suzuki_p(k::Int)
    k >= 2 || error("_suzuki_p: k must be >= 2, got $k")
    1.0 / (4.0 - 4.0^(1.0 / (2k - 1)))
end

# ── Core Trotter steps ───────────────────────────────────────────────────────

"""One step of first-order Trotter: S₁(dt) = Πⱼ exp(-i dt hⱼ Pⱼ)."""
function _trotter1_step!(qubits::Vector{QBool}, H::PauliHamiltonian{N}, dt::Real) where {N}
    for term in H.terms
        pauli_exp!(qubits, term, dt)
    end
end

"""One step of second-order Trotter: forward sweep at dt/2, reverse sweep at dt/2."""
function _trotter2_step!(qubits::Vector{QBool}, H::PauliHamiltonian{N}, dt::Real) where {N}
    half_dt = dt / 2
    for term in H.terms
        pauli_exp!(qubits, term, half_dt)
    end
    for term in Iterators.reverse(H.terms)
        pauli_exp!(qubits, term, half_dt)
    end
end

"""Recursive Suzuki step. Base case Val(2) → _trotter2_step!.
Uses Val{K} dispatch so the compiler inlines the full recursion tree."""
function _suzuki_step!(qubits::Vector{QBool}, H::PauliHamiltonian{N},
                       dt::Real, ::Val{2}) where {N}
    _trotter2_step!(qubits, H, dt)
end

function _suzuki_step!(qubits::Vector{QBool}, H::PauliHamiltonian{N},
                       dt::Real, ::Val{K}) where {N, K}
    # k = K ÷ 2 aligns with Suzuki 1991 indexing: order 2k uses p_k
    p = _suzuki_p(K ÷ 2)
    inner_order = Val(K - 2)
    # S₂ₖ(dt) = S₂ₖ₋₂(p·dt)² · S₂ₖ₋₂((1-4p)·dt) · S₂ₖ₋₂(p·dt)²
    _suzuki_step!(qubits, H, p * dt, inner_order)
    _suzuki_step!(qubits, H, p * dt, inner_order)
    _suzuki_step!(qubits, H, (1 - 4p) * dt, inner_order)
    _suzuki_step!(qubits, H, p * dt, inner_order)
    _suzuki_step!(qubits, H, p * dt, inner_order)
end

# ── Dispatch ─────────────────────────────────────────────────────────────────

function _apply_formula!(qubits::Vector{QBool}, H::PauliHamiltonian{N},
                         t::Real, alg::Trotter1) where {N}
    dt = t / alg.steps
    for _ in 1:alg.steps
        _trotter1_step!(qubits, H, dt)
    end
end

function _apply_formula!(qubits::Vector{QBool}, H::PauliHamiltonian{N},
                         t::Real, alg::Trotter2) where {N}
    dt = t / alg.steps
    for _ in 1:alg.steps
        _trotter2_step!(qubits, H, dt)
    end
end

function _apply_formula!(qubits::Vector{QBool}, H::PauliHamiltonian{N},
                         t::Real, alg::Suzuki) where {N}
    dt = t / alg.steps
    for _ in 1:alg.steps
        _suzuki_step!(qubits, H, dt, Val(alg.order))
    end
end
