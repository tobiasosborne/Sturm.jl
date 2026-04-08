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
# Step 0: Chebyshev ↔ analytic polynomial conversion
# ═══════════════════════════════════════════════════════════════════════════

"""
    chebyshev_to_analytic(cheb::Vector{ComplexF64}) -> Vector{ComplexF64}

Convert Chebyshev coefficients [c₀, c₁, ..., c_d] (where P(x) = Σ cₖ Tₖ(x))
to analytic (monomial) coefficients [p₀, ..., p_{2d}] for the analytic QSP
polynomial P_a(z) = z^d · P_L(z), where P_L(z) is the Laurent polynomial
form of the Chebyshev expansion.

The Laurent polynomial is: P_L(z) = c₀ + Σ_{k=1}^d cₖ(z^k + z^{-k})/2
Multiplying by z^d: P_a(z) = Σ_{j=0}^{2d} p_j z^j where
  p_d = c₀
  p_{d+k} = p_{d-k} = cₖ/2   for k = 1, ..., d

This satisfies |P_a(e^{iθ})| = |P_L(e^{iθ})| ≤ 1 on the unit circle
(since |e^{idθ}| = 1), which is the precondition for Berntson-Sünderhauf.

The degree doubles from d to 2d.

Ref: Laneve (2025), arXiv:2503.03026, Lemma 1 (analytic ↔ Laurent QSP).
"""
function chebyshev_to_analytic(cheb::Vector{ComplexF64})
    d = length(cheb) - 1
    # Analytic polynomial has degree 2d
    p = zeros(ComplexF64, 2d + 1)
    p[d + 1] = cheb[1]  # p_d = c_0
    for k in 1:d
        p[d + 1 + k] = cheb[k + 1] / 2  # p_{d+k} = c_k / 2
        p[d + 1 - k] = cheb[k + 1] / 2  # p_{d-k} = c_k / 2
    end
    return p
end

"""
    analytic_to_chebyshev(p::Vector{ComplexF64}) -> Vector{ComplexF64}

Inverse of chebyshev_to_analytic. Given analytic polynomial of degree 2d,
extract the Chebyshev coefficients of the underlying Laurent polynomial.

  c₀ = p_d
  cₖ = p_{d+k} + p_{d-k}   for k = 1, ..., d
"""
function analytic_to_chebyshev(p::Vector{ComplexF64})
    n = length(p) - 1  # degree 2d
    iseven(n) || error("analytic_to_chebyshev: degree must be even, got $n")
    d = n ÷ 2
    cheb = zeros(ComplexF64, d + 1)
    cheb[1] = p[d + 1]
    for k in 1:d
        cheb[k + 1] = p[d + 1 + k] + p[d + 1 - k]
    end
    return cheb
end

# ═══════════════════════════════════════════════════════════════════════════
# Step 1: Berntson-Sunderhauf completion (P → Q)
# ═══════════════════════════════════════════════════════════════════════════

"""
    complementary_polynomial(cheb_coeffs; epsilon=1e-10) -> Vector{ComplexF64}

Compute the complementary polynomial Q (in Chebyshev basis) such that
|P(x)|² + |Q(x)|² = 1 for x ∈ [-1, 1], given Chebyshev coefficients of P.

Internally converts to the analytic QSP convention (monomial basis on the
unit circle) via chebyshev_to_analytic, runs the Berntson-Sünderhauf FFT
algorithm, then converts Q back via analytic_to_chebyshev.

The degree doubles (Chebyshev d → analytic 2d) for the internal computation,
but the returned Q has the same degree d as the input.

Ref: Berntson, Sünderhauf (2025), CMP 406:161, Algorithms 1-2.
     Laneve (2025), arXiv:2503.03026, Lemma 1 (convention conversion).
"""
function complementary_polynomial(cheb_coeffs::Vector{ComplexF64};
                                   epsilon::Float64=1e-10)
    d_cheb = length(cheb_coeffs) - 1
    d_cheb >= 0 || error("complementary_polynomial: need at least 1 coefficient")

    # Convert Chebyshev → analytic (degree d → 2d)
    P_analytic = chebyshev_to_analytic(cheb_coeffs)
    d_a = length(P_analytic) - 1  # = 2 * d_cheb

    # Estimate delta on the unit circle for the analytic polynomial
    N_est = nextpow(2, max(1024, 4 * (d_a + 1)))
    P_padded = zeros(ComplexF64, N_est)
    P_padded[1:d_a+1] .= P_analytic
    P_vals = ifft(P_padded) .* N_est
    max_P = sqrt(maximum(abs2.(P_vals)))
    delta = max(1.0 - max_P, 0.0)

    # Always use Algorithm 2 (downscaling) for robustness when delta is tiny
    scale = 1.0 - epsilon / 4
    P_scaled = P_analytic .* scale
    delta_eff = epsilon / 4  # guaranteed gap after downscaling

    Q_analytic = _bs_algorithm1(P_scaled, delta_eff, epsilon / (5 * (d_a + 1)))

    # Convert analytic Q back to Chebyshev
    # Q_analytic has degree 2*d_cheb — convert back
    if length(Q_analytic) < d_a + 1
        # Pad if truncated
        Q_padded = zeros(ComplexF64, d_a + 1)
        Q_padded[1:length(Q_analytic)] .= Q_analytic
        Q_analytic = Q_padded
    elseif length(Q_analytic) > d_a + 1
        Q_analytic = Q_analytic[1:d_a+1]
    end

    return analytic_to_chebyshev(Q_analytic)
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
