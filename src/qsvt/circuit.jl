# QSVT algorithm type and circuit implementations.
#
# The GQSP protocol (Laneve 2025, Theorem 9) on a single signal qubit:
#
#   e^{iλZ} · A₀ · W̃ · A₁ · W̃ · ··· · W̃ · Aₙ  |0⟩ = P(z)|0⟩ + Q(z)|1⟩
#
# where W̃ = diag(z, 1) is the signal operator with z = e^{iθ},
# and A_k = e^{iφ_k X}·e^{iθ_k Z} are the processing operators.
#
# On a single qubit, W̃ ≡ Rz(-θ) (up to global phase):
#   diag(e^{iθ}, 1) = e^{iθ/2} · diag(e^{iθ/2}, e^{-iθ/2}) = e^{iθ/2} · Rz(-θ)
#
# The global phase factors out and doesn't affect measurements.
#
# Ref: Laneve (2025), arXiv:2503.03026, Theorem 9.
#      Local PDF: docs/literature/quantum_simulation/qsp_qsvt/2503.03026.pdf

"""
    qsvt_protocol!(theta_signal::Float64, phases::QSVTPhases) -> QBool

Execute the GQSP protocol on a single signal qubit.

Allocates a signal qubit in |0⟩, applies the GQSP circuit with signal
operator W̃ = diag(z, 1) where z = e^{iθ_signal}, and returns the signal
qubit for measurement.

The protocol produces: P(z)|0⟩ + Q(z)|1⟩ where (P, Q) are the polynomials
encoded by the phase factors.

This is the core building block for QSVT. For use with a block encoding,
the signal operator W̃ is replaced by the block encoding oracle controlled
on the signal qubit.

# Arguments
- `theta_signal`: Signal angle θ such that z = e^{iθ} (the eigenvalue parameter)
- `phases`: GQSP phase factors (λ, φ_k, θ_k) from `extract_phases`

# Returns
The signal `QBool` after the protocol. Measuring it gives:
- |0⟩ with probability |P(z)|²
- |1⟩ with probability |Q(z)|²

# Ref
Laneve (2025), arXiv:2503.03026, Theorem 9.
"""
function qsvt_protocol!(theta_signal::Float64, phases::QSVTPhases)
    ctx = current_context()
    signal = QBool(ctx, 0.0)  # |0⟩

    # Initial e^{iλZ} = Rz(-2λ)
    signal.φ += -2 * phases.lambda

    # GQSP loop: A₀ · W̃ · A₁ · W̃ · ··· · W̃ · Aₙ
    for k in 0:phases.degree
        # Processing operator A_k = e^{iφ_k X}·e^{iθ_k Z}
        apply_processing_op!(signal, phases.phi[k + 1], phases.theta[k + 1])

        # Signal operator W̃ = diag(z, 1) ≡ Rz(-θ) (between processing ops)
        if k < phases.degree
            signal.φ += -theta_signal
        end
    end

    return signal
end

# ═══════════════════════════════════════════════════════════════════════════
# QSVT algorithm type + classical preprocessing pipeline
# ═══════════════════════════════════════════════════════════════════════════

"""
    QSVT <: AbstractQueryAlgorithm

QSVT Hamiltonian simulation algorithm.

Uses the GQSP protocol (Laneve 2025) with Jacobi-Anger polynomial
approximation and Berntson-Sünderhauf + RHW phase factor computation.

# Fields
- `epsilon::Float64`: target approximation error for the polynomial
- `degree::Union{Int, Nothing}`: polynomial degree (auto-computed if nothing)

# Example
```julia
alg = QSVT(epsilon=1e-6)
# Full evolve! integration pending (requires reflection QSVT for LCU BE)
phases = qsvt_hamiltonian_sim_phases(1.0, alg)  # classical preprocessing
```
"""
struct QSVT <: AbstractQueryAlgorithm
    epsilon::Float64
    degree::Union{Int, Nothing}

    function QSVT(; epsilon::Float64=1e-6, degree::Union{Int, Nothing}=nothing)
        epsilon > 0 || error("QSVT: epsilon must be positive, got $epsilon")
        degree === nothing || degree >= 1 || error("QSVT: degree must be >= 1, got $degree")
        new(epsilon, degree)
    end
end

"""
    qsvt_hamiltonian_sim_phases(t::Real, alg::QSVT) -> QSVTPhases

Compute GQSP phase factors for Hamiltonian simulation e^{-iHt}.

Runs the full classical preprocessing pipeline:
1. Jacobi-Anger polynomial: e^{-ixt} ≈ P(x) of degree d
2. Chebyshev → analytic conversion (degree doubles: d → 2d)
3. Convention mapping: b = -i·P·scale (create gap for Weiss)
4. Weiss algorithm: b → ĉ (Fourier coefficients of b/a)
5. RHW factorization: ĉ → F_k (NLFT sequence)
6. Phase extraction: F_k → QSVTPhases (λ, φ_k, θ_k)

The degree d is auto-computed as ⌈|t| + C·log(1/ε)⌉ if not specified,
where C ≈ 1.5/ln(10) gives the Bessel tail decay rate.

# Arguments
- `t`: simulation time
- `alg`: QSVT algorithm with epsilon (and optional degree override)

# Returns
QSVTPhases for the analytic GQSP protocol (degree 2d in the analytic picture).

# Ref
Martyn et al. (2021), PRX Quantum 2:040203, Eq. (29)-(30).
Laneve (2025), arXiv:2503.03026, Algorithm 1-2, Theorem 9.
"""
function qsvt_hamiltonian_sim_phases(t::Real, alg::QSVT)
    t = Float64(t)
    ε = alg.epsilon

    # ── Step 1: Polynomial degree ──
    if alg.degree !== nothing
        d = alg.degree
    else
        # Heuristic: d ≈ |t| + C·log(1/ε) where Bessel tails decay as J_k(t) ~ (et/2k)^k
        # Conservative: C = 1.5/ln(10) ≈ 0.65 per digit of precision
        d = max(1, ceil(Int, abs(t) + 1.5 / log(10) * log(1 / ε)))
    end
    @debug "qsvt_hamiltonian_sim_phases: t=$t, ε=$ε, d=$d"

    # ── Step 2: Jacobi-Anger polynomial (Chebyshev basis) ──
    P_cheb = jacobi_anger_coeffs(t, d)

    # ── Step 3: Chebyshev → analytic (degree doubles: d → 2d) ──
    P_analytic = chebyshev_to_analytic(P_cheb)
    n_a = length(P_analytic) - 1  # = 2d

    # ── Step 4: Convention mapping b = -i·P (Laneve Section 4.3) ──
    b_raw = -im .* P_analytic

    # ── Step 5: Downscale to create gap ──
    # Evaluate ||b||_∞ on 𝕋 (analytic preserves Chebyshev norm, but verify)
    N_est = nextpow(2, max(1024, 4 * length(b_raw)))
    b_pad = zeros(ComplexF64, N_est)
    b_pad[1:length(b_raw)] .= b_raw
    b_est = ifft(b_pad) .* N_est
    max_b = sqrt(maximum(abs2.(b_est)))

    # Scale so ||b||_∞ ≤ 1 - η with η = ε/4
    η = ε / 4
    scale = (1.0 - η) / max(max_b, 1.0 - η)
    b_scaled = b_raw .* scale

    @debug "qsvt_hamiltonian_sim_phases: ||b_raw||_∞=$max_b, scale=$scale, η=$η"

    # ── Step 6: Weiss → RHW → extract_phases ──
    F = rhw_factorize(b_scaled, η, ε / 4)
    phases = extract_phases(F)

    return phases
end
