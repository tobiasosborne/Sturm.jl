# qDRIFT: randomized Hamiltonian simulation via importance sampling.
#
# Algorithm (Campbell 2019):
#   Given H = Σⱼ hⱼ Pⱼ with λ = Σ|hⱼ|, to approximate exp(-iHt):
#   For n = 1, …, N:
#     1. Sample j with probability pⱼ = |hⱼ|/λ
#     2. Apply exp(-iλτ·sign(hⱼ)·Pⱼ) where τ = t/N
#   The average channel ε-approximates exp(-iHt) in diamond norm
#   with N = ⌈2λ²t²/ε⌉ gates, INDEPENDENT of the number of terms L.
#
# Ref: Campbell, E. T. (2019), "A Random Compiler for Fast Hamiltonian
#      Simulation", Phys. Rev. Lett. 123, 070503.
#      arXiv:1811.08017
#
# Concentration: individual circuit realizations also approximate the
# target with high probability (Chen, Huang, Kueng, Tropp, 2021,
# PRX Quantum 2, 040305, arXiv:2008.11751).

"""
    QDrift(; samples=100)

qDRIFT randomized Hamiltonian simulation [Campbell 2019, arXiv:1811.08017].

Samples `N` random Pauli exponentials from the Hamiltonian, each with
probability proportional to the absolute coefficient. Gate count is
O(λ²t²/ε), independent of the number of Hamiltonian terms L.

Each call produces a DIFFERENT random circuit realization.
The average channel over many realizations approximates exp(-iHt).

# Error bound
For target diamond-norm error ε: N ≥ 2λ²t²/ε suffices, where
λ = Σⱼ|hⱼ| is the 1-norm of the Hamiltonian coefficients.

Use `qdrift_samples(H, t, epsilon)` to compute the required N.
"""
struct QDrift <: AbstractStochasticAlgorithm
    samples::Int
    function QDrift(; samples::Int=100)
        samples >= 1 || error("QDrift: samples must be >= 1, got $samples")
        new(samples)
    end
end

"""
    qdrift_samples(H::PauliHamiltonian, t::Real, epsilon::Real) -> Int

Compute the number of qDRIFT samples needed for diamond-norm error ≤ ε.
Formula: N = ⌈2λ²t²/ε⌉ [Campbell 2019, Theorem 1].
"""
function qdrift_samples(H::PauliHamiltonian, t::Real, epsilon::Real)
    epsilon > 0 || error("qdrift_samples: epsilon must be > 0, got $epsilon")
    t >= 0 || error("qdrift_samples: time must be non-negative, got $t")
    λ = lambda(H)
    ceil(Int, 2 * λ^2 * t^2 / epsilon)
end

# ── Internal: precomputed sampling distribution ─────────────────────────────

"""
    _QDriftDist{N}

Precomputed cumulative distribution for importance sampling.
Stack-allocated for small Hamiltonians.
"""
struct _QDriftDist{L}
    cumprobs::Vector{Float64}   # cumulative probabilities, length L
    λ::Float64                  # 1-norm Σ|hⱼ|
end

function _QDriftDist(H::PauliHamiltonian{N}) where {N}
    L = length(H.terms)
    weights = Vector{Float64}(undef, L)
    @inbounds for i in 1:L
        weights[i] = abs(H.terms[i].coeff)
    end
    λ = sum(weights)
    λ > 0 || error("QDrift: Hamiltonian has zero 1-norm (all coefficients zero)")
    # Normalise to probabilities and compute cumulative sum
    @inbounds for i in 1:L
        weights[i] /= λ
    end
    cumprobs = cumsum(weights)
    # Fix floating-point: ensure last entry is exactly 1.0
    cumprobs[end] = 1.0
    _QDriftDist{L}(cumprobs, λ)
end

"""Sample a term index from the precomputed distribution."""
@inline function _sample(dist::_QDriftDist)
    r = rand()
    # Binary search for the first cumprob ≥ r
    searchsortedfirst(dist.cumprobs, r)
end

# ── Core qDRIFT step ────────────────────────────────────────────────────────

"""
    _apply_qdrift!(qubits, H::PauliHamiltonian{N}, t::Real, alg::QDrift)

Apply N random Pauli exponentials sampled from H.
Each gate: exp(-i·λ·τ·sign(hⱼ)·Pⱼ) where τ = t/N.

Implementation detail: `_pauli_exp!(qubits, term_j, λτ/|hⱼ|)` produces
the correct rotation because `_pauli_exp!` computes angle = 2·θ·hⱼ,
giving 2·(λτ/|hⱼ|)·hⱼ = 2·λτ·sign(hⱼ). ✓
"""
function _apply_qdrift!(qubits, H::PauliHamiltonian{N}, t::Real, alg::QDrift) where {N}
    dist = _QDriftDist(H)
    τ = t / alg.samples
    λτ = dist.λ * τ

    for _ in 1:alg.samples
        j = _sample(dist)
        term = @inbounds H.terms[j]
        # _pauli_exp!(qubits, term, θ) applies exp(-i·θ·h·P)
        # We want exp(-i·λτ·sign(h)·P), so θ = λτ/|h|
        _pauli_exp!(qubits, term, λτ / abs(term.coeff))
    end
end

# ── Dispatch into evolve! ───────────────────────────────────────────────────

function _apply_formula!(qubits, H::PauliHamiltonian{N},
                         t::Real, alg::QDrift) where {N}
    _apply_qdrift!(qubits, H, t, alg)
end

# Extend evolve! to accept AbstractStochasticAlgorithm
function evolve!(qubits::Vector{QBool}, H::PauliHamiltonian{N}, t::Real,
                 alg::AbstractStochasticAlgorithm) where {N}
    length(qubits) == N || error(
        "evolve!: expected $N qubits for PauliHamiltonian{$N}, got $(length(qubits))")
    for q in qubits; check_live!(q); end
    isfinite(t) || error("evolve!: time must be finite, got $t")
    t >= 0 || error("evolve!: time must be non-negative, got $t")
    t == 0 && return nothing
    _apply_formula!(qubits, H, t, alg)
    return nothing
end

function evolve!(reg::QInt{W}, H::PauliHamiltonian{W}, t::Real,
                 alg::AbstractStochasticAlgorithm) where {W}
    check_live!(reg)
    isfinite(t) || error("evolve!: time must be finite, got $t")
    t >= 0 || error("evolve!: time must be non-negative, got $t")
    t == 0 && return reg
    _apply_formula!(_qbool_views(reg), H, t, alg)
    return reg
end
