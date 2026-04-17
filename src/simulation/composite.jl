# Composite Trotter+qDRIFT simulation.
#
# Partitions H = A + B by coefficient magnitude: |hⱼ| ≥ cutoff → Trotter
# partition A, |hⱼ| < cutoff → qDRIFT partition B. Each composite step
# applies one Trotter step to A followed by qDRIFT samples from B.
#
# This "horizontal" composition interpolates between pure Trotter (cutoff=0)
# and pure qDRIFT (cutoff=∞), combining the deterministic precision of
# high-order Trotter on large terms with the L-independence of qDRIFT on
# the many small terms.
#
# Ref: Hagan, M. & Wiebe, N. (2023), "Composite Quantum Simulations",
#      Quantum 7, 1181. arXiv:2206.06409.
#      Local PDF: docs/literature/quantum_simulation/randomized_methods/2206.06409.pdf
#      Theorem 2.1 (Eq. 1): gate cost upper bound for composite channel.
#      Lemma 2.1 (Eq. 3): probabilistic partitioning scheme.
#      Section 5, p.5: deterministic cutoff partitioning.

"""
    Composite(; steps=10, qdrift_samples=100, cutoff=0.1,
                trotter_order=2, rng=Random.default_rng())

Composite Trotter+qDRIFT simulation [Hagan & Wiebe 2023, arXiv:2206.06409].

Partitions Hamiltonian terms by coefficient magnitude:
- |hⱼ| ≥ `cutoff` → high-order Trotter (deterministic, precise)
- |hⱼ| < `cutoff` → qDRIFT (randomized, L-independent)

Each of `steps` composite repetitions applies one Trotter step to the large
partition followed by `qdrift_samples ÷ steps` random samples from the small
partition.

Edge cases: if all terms exceed cutoff → pure Trotter; if none do → pure qDRIFT.

# Arguments
- `steps::Int`: number of composite repetitions (r in the paper)
- `qdrift_samples::Int`: total qDRIFT samples across all steps (Nв)
- `cutoff::Float64`: partition threshold on |hⱼ|
- `trotter_order::Int`: 1 (Lie-Trotter), 2 (Strang), or 4,6,... (Suzuki)
- `rng::AbstractRNG`: random source for the qDRIFT partition. Seed for reproducibility.
"""
struct Composite <: AbstractSimAlgorithm
    steps::Int
    qdrift_samples::Int
    cutoff::Float64
    trotter_order::Int
    rng::AbstractRNG
    function Composite(; steps::Int=10, qdrift_samples::Int=100,
                        cutoff::Float64=0.1, trotter_order::Int=2,
                        rng::AbstractRNG=default_rng())
        steps >= 1 || error("Composite: steps must be >= 1, got $steps")
        qdrift_samples >= 0 || error("Composite: qdrift_samples must be >= 0, got $qdrift_samples")
        cutoff > 0 || error("Composite: cutoff must be > 0, got $cutoff")
        trotter_order >= 1 || error("Composite: trotter_order must be >= 1, got $trotter_order")
        new(steps, qdrift_samples, cutoff, trotter_order, rng)
    end
end

# ── Hamiltonian partitioning ────────────────────────────────────────────────

"""
    _partition(H::PauliHamiltonian{N}, cutoff::Float64)
        -> (A::Union{PauliHamiltonian{N},Nothing}, B::Union{PauliHamiltonian{N},Nothing})

Split H into Trotter partition A (|hⱼ| ≥ cutoff) and qDRIFT partition B (|hⱼ| < cutoff).
Returns `nothing` for empty partitions.
"""
function _partition(H::PauliHamiltonian{N}, cutoff::Float64) where {N}
    terms_a = PauliTerm{N}[]
    terms_b = PauliTerm{N}[]
    for term in H.terms
        if abs(term.coeff) >= cutoff
            push!(terms_a, term)
        else
            push!(terms_b, term)
        end
    end
    A = isempty(terms_a) ? nothing : PauliHamiltonian{N}(terms_a)
    B = isempty(terms_b) ? nothing : PauliHamiltonian{N}(terms_b)
    (A, B)
end

# ── Core composite step ─────────────────────────────────────────────────────

"""
    _apply_composite!(qubits, H, t, alg::Composite)

For each of r steps:
  1. One Trotter step on partition A (large terms)
  2. Nв/r qDRIFT samples on partition B (small terms)
"""
function _apply_composite!(qubits, H::PauliHamiltonian{N}, t::Real,
                           alg::Composite) where {N}
    A, B = _partition(H, alg.cutoff)

    dt = t / alg.steps

    # Degenerate cases: pure Trotter or pure qDRIFT
    if B === nothing
        # All terms in Trotter partition
        _apply_trotter_partition!(qubits, A, dt, alg.trotter_order, alg.steps)
        return nothing
    end
    if A === nothing
        # All terms in qDRIFT partition
        _apply_qdrift!(qubits, B, t, QDrift(samples=max(1, alg.qdrift_samples), rng=alg.rng))
        return nothing
    end

    # Composite: interleave Trotter steps on A with qDRIFT samples on B
    samples_per_step = max(1, alg.qdrift_samples ÷ alg.steps)
    dist = _QDriftDist(B)
    λB = dist.λ

    for _ in 1:alg.steps
        # 1. One Trotter step on partition A
        _trotter_step_dispatch!(qubits, A, dt, alg.trotter_order)

        # 2. qDRIFT samples on partition B
        τ = dt / samples_per_step
        λτ = λB * τ
        for _ in 1:samples_per_step
            j = _sample(dist, alg.rng)
            term = @inbounds B.terms[j]
            _pauli_exp!(qubits, term, λτ / abs(term.coeff))
        end
    end

    return nothing
end

"""Dispatch a single Trotter step by order."""
function _trotter_step_dispatch!(qubits, H::PauliHamiltonian{N}, dt::Real,
                                 order::Int) where {N}
    if order == 1
        _trotter1_step!(qubits, H, dt)
    elseif order == 2
        _trotter2_step!(qubits, H, dt)
    else
        _suzuki_step!(qubits, H, dt, Val(order))
    end
end

"""Apply Trotter partition only (no qDRIFT), for degenerate case."""
function _apply_trotter_partition!(qubits, H::PauliHamiltonian{N}, dt::Real,
                                   order::Int, steps::Int) where {N}
    for _ in 1:steps
        _trotter_step_dispatch!(qubits, H, dt, order)
    end
end

# ── Dispatch into evolve! ───────────────────────────────────────────────────

function _apply_formula!(qubits, H::PauliHamiltonian{N},
                         t::Real, alg::Composite) where {N}
    _apply_composite!(qubits, H, t, alg)
end

function evolve!(qubits::Vector{QBool}, H::PauliHamiltonian{N}, t::Real,
                 alg::Composite) where {N}
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
                 alg::Composite) where {W}
    check_live!(reg)
    isfinite(t) || error("evolve!: time must be finite, got $t")
    t >= 0 || error("evolve!: time must be non-negative, got $t")
    t == 0 && return reg
    _apply_formula!(_qbool_views(reg), H, t, alg)
    return reg
end
