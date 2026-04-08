# QSP phase factor computation pipeline.
#
# Pipeline: P(z) → Q(z) → (a,b) → F_k → (λ, φ_k, θ_k)
#
# Step 1: Berntson-Sunderhauf completion (P → Q)
# Step 2: Weiss algorithm (b → c_hat)
# Step 3: RHW factorization (c_hat → F_k)
# Step 4: Phase extraction (F_k → GQSP angles)
#
# Ref: Berntson, Sunderhauf (2025), CMP 406:161.
#      Local PDF: docs/literature/quantum_simulation/qsp_qsvt/s00220-025-05302-9.pdf
# Ref: Laneve (2025), arXiv:2503.03026.
#      Local PDF: docs/literature/quantum_simulation/qsp_qsvt/2503.03026.pdf

using FFTW

# ═══════════════════════════════════════════════════════════════════════════
# Step 1: Berntson-Sunderhauf completion (P → Q)
# ═══════════════════════════════════════════════════════════════════════════

"""
    complementary_polynomial(P::Vector{ComplexF64}; delta=nothing, epsilon=1e-12) -> Vector{ComplexF64}

Compute the complementary polynomial Q such that |P(z)|² + |Q(z)|² = 1 on
the unit circle 𝕋, using the Berntson-Sünderhauf FFT algorithm.

P is given as monomial coefficients [p₀, p₁, ..., p_d] where P(z) = Σ pₖ zᵏ.
Returns Q as monomial coefficients of the same length.

If `delta` is provided (||P||_{∞,𝕋} ≤ 1 - delta), uses Algorithm 1 directly.
If `delta` is nothing, estimates it from P or falls back to Algorithm 2
(downscaling by 1 - ε/4).

# Algorithm (Berntson-Sünderhauf, CMP 2025, Algorithm 1, p.11)

1. Evaluate P at N roots of unity via IFFT
2. Compute S = log(1 - |P|²) at each root (real-valued)
3. FFT to Fourier space, apply multiplier Π (positive freqs only + ½ DC)
4. IFFT back, exponentiate → Q at roots of unity
5. FFT to get Q monomial coefficients, truncate to degree d

The Fourier multiplier Π (Eq. 1.7) keeps positive frequencies, halves DC,
and zeros negative frequencies: Π[e^{inθ}] = e^{inθ} (n>0), ½ (n=0), 0 (n<0).

Ref: Berntson, Sünderhauf (2025), CMP 406:161, Algorithm 1, Theorem 3.
     Local PDF: docs/literature/quantum_simulation/qsp_qsvt/s00220-025-05302-9.pdf
"""
function complementary_polynomial(P::Vector{ComplexF64};
                                   delta::Union{Nothing, Float64}=nothing,
                                   epsilon::Float64=1e-12)
    d = length(P) - 1
    d >= 0 || error("complementary_polynomial: need at least 1 coefficient")

    # Estimate delta if not provided: evaluate |P|² on a fine grid
    if delta === nothing
        N_est = max(1024, 4 * (d + 1))
        N_est = nextpow(2, N_est)
        P_padded_est = zeros(ComplexF64, N_est)
        P_padded_est[1:d+1] .= P
        # FFTW convention: ifft gives (1/N) Σ x_n e^{2πi·n·k/N}
        # To evaluate P(ω^k) = Σ p_n ω^{nk}, we need ifft * N
        P_vals_est = ifft(P_padded_est) .* N_est
        max_P2 = maximum(abs2.(P_vals_est))
        delta = max(1.0 - sqrt(max_P2), 1e-15)
    end

    if delta < epsilon / 4
        # Algorithm 2: downscale P to enforce delta = epsilon/4
        scale = 1.0 - epsilon / 4
        P_scaled = P .* scale
        Q_scaled = _bs_algorithm1(P_scaled, epsilon / 4, epsilon / (5 * (d + 1)))
        # Q for the original P: Q_scaled corresponds to scaled P.
        # The complementarity |scale·P|² + |Q_scaled|² = 1 holds for scaled P.
        # For the original P: we return Q_scaled as-is (Theorem 4 guarantees
        # the complementarity error is bounded by epsilon).
        return Q_scaled[1:d+1]
    else
        return _bs_algorithm1(P, delta, epsilon)
    end
end

"""
    _bs_algorithm1(P, delta, epsilon) -> Vector{ComplexF64}

Core of Berntson-Sunderhauf Algorithm 1 for known delta > 0.
"""
function _bs_algorithm1(P::Vector{ComplexF64}, delta::Float64, epsilon::Float64)
    d = length(P) - 1

    # Choose N: must be a power of 2, at least 2*(d+1).
    #
    # Theorem 3 (Eq. 4.8) gives N = O(d/δ · log(d/(δε))), but this
    # overflows for very small δ. Remark 1 (p.12) notes empirically
    # Algorithm 1 works with N = O(d/√ε) even for δ → 0.
    #
    # Practical heuristic: N = max(8d, d/δ) capped at 2^20 (~1M).
    # For d ≤ 100 and δ ≥ 1e-4, this gives N ≤ 2^20 comfortably.
    N_heuristic = max(8 * (d + 1), ceil(Int, (d + 1) / max(delta, 1e-6)))
    N = nextpow(2, clamp(N_heuristic, 2 * (d + 1), 1 << 20))

    # Step 1: Evaluate P at N-th roots of unity
    # P(ω^k) = Σ_{n=0}^{d} p_n ω^{nk} where ω = e^{2πi/N}
    # = N · IFFT(p_padded)[k]  (FFTW ifft convention)
    P_padded = zeros(ComplexF64, N)
    P_padded[1:d+1] .= P
    P_vals = ifft(P_padded) .* N

    # Step 2: Compute S = log(1 - |P|²) at roots of unity
    S_vals = Vector{Float64}(undef, N)
    for k in 1:N
        val = 1.0 - abs2(P_vals[k])
        val = max(val, 1e-30)  # clamp to avoid log(0)
        S_vals[k] = log(val)
    end

    # Step 3: FFT to get Fourier coefficients, apply Π multiplier
    # a_tilde = FFT(S_vals) / N
    a_tilde = fft(complex.(S_vals)) ./ N

    # Apply Fourier multiplier Π:
    # slot 1 (index 0 in 0-based) = DC: halve
    # slots 2..N/2 (indices 1..N/2-1) = positive freqs: keep
    # slot N/2+1 (index N/2) = Nyquist: halve
    # slots N/2+2..N (indices N/2+1..N-1) = negative freqs: zero
    b = zeros(ComplexF64, N)
    b[1] = a_tilde[1] / 2                     # DC (Julia 1-indexed)
    half = N ÷ 2
    for k in 2:half
        b[k] = a_tilde[k]                      # positive frequencies
    end
    b[half + 1] = a_tilde[half + 1] / 2       # Nyquist
    # slots half+2 .. N remain zero (negative frequencies)

    # Step 4: IFFT back, exponentiate → Q at roots of unity
    exp_arg = ifft(b) .* N
    Q_vals = exp.(exp_arg)

    # Step 5: FFT to get Q monomial coefficients, truncate
    Q_full = fft(Q_vals) ./ N

    # Truncate to degree d
    Q_coeffs = Q_full[1:d+1]

    return Q_coeffs
end
