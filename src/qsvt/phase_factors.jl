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

# ═══════════════════════════════════════════════════════════════════════════
# Step 2: Weiss algorithm (b → ĉ = Fourier coefficients of b/a)
# ═══════════════════════════════════════════════════════════════════════════

"""
    weiss(b::Vector{ComplexF64}, eta::Float64, epsilon::Float64) -> Vector{ComplexF64}

Weiss' algorithm: compute Fourier coefficients of b/a from polynomial b.

Given b(z) = Σ_{k=0}^n b_k z^k with ||b||_∞ ≤ 1-η on the unit circle 𝕋,
computes the Fourier coefficients ĉ_0, ..., ĉ_n of b/a, where a(z) = e^{G*(z)}
is the outer function satisfying |a|² + |b|² = 1 on 𝕋.

The function f(z) = √(1-|b(z)|²) satisfies |f|² + |b|² = 1, and we define
R(z) = log f(z) = (1/2)log(1-|b(z)|²). The Schwarz integral formula gives
G(z) analytic in 𝔻 with Re(G) = R on 𝕋. Then a := e^{G*} where G*(z) = conj(G(z))
on 𝕋. The output ĉ = Fourier coefficients of b·e^{-G*}.

# Arguments
- `b`: Monomial coefficients [b_0, ..., b_n] of polynomial b(z)
- `eta`: Gap parameter, must satisfy ||b||_∞ ≤ 1-η on 𝕋 (η > 0)
- `epsilon`: Target precision for output coefficients (ε > 0)

# Returns
Vector{ComplexF64} of length n+1: Fourier coefficients [ĉ_0, ..., ĉ_n] of b/a.

# Ref
Laneve (2025), arXiv:2503.03026, Algorithm 1, Section 5.1 p.11-12.
Alexis et al. (2024), arXiv:2407.05634, [30] (original Weiss algorithm).
"""
# _weiss_schwarz(b, eta, epsilon) -> (R_vals, G_vals, b_vals, N)
#
# Internal: compute the Schwarz outer function G from polynomial b.
# Returns R(z) = (1/2)log(1-|b(z)|²) and G(z) (analytic in 𝔻) at N-th roots
# of unity, plus b values and FFT size. Used by `weiss` and exposed for testing.
#
# On 𝕋: Re(G(z)) = R(z), and a(z) = e^{conj(G(z))} satisfies |a|² + |b|² = 1.
#
# Ref: Laneve (2025), arXiv:2503.03026, Section 5.1 p.11-12.
function _weiss_schwarz(b::Vector{ComplexF64}, eta::Float64, epsilon::Float64)
    n = length(b) - 1
    n >= 0 || error("_weiss_schwarz: b must have at least 1 coefficient")
    eta > 0 || error("_weiss_schwarz: eta must be positive, got $eta")
    epsilon > 0 || error("_weiss_schwarz: epsilon must be positive, got $epsilon")

    # ── Choose FFT size N (Algorithm 1, line 1) ──
    # N ≥ (8n/η) · log(576n² / (η⁴ε))
    # Minimum 2(n+1) for Nyquist. Cap at 2^22 to avoid OOM.
    if n == 0
        N = 2
    else
        N_theory = ceil(Int, (8 * n / eta) * log(576 * n^2 / (eta^4 * epsilon)))
        N = nextpow(2, max(N_theory, 2 * (n + 1)))
        N = min(N, 1 << 22)
    end
    @debug "weiss: N=$N (2^$(round(log2(N), digits=1)))"

    # ── Evaluate b at N-th roots of unity ──
    # b(ω^j) where ω = e^{2πi/N}, via IFFT: b_vals = IFFT(b_padded) · N
    b_padded = zeros(ComplexF64, N)
    b_padded[1:n+1] .= b
    b_vals = ifft(b_padded) .* N

    # ── Compute R(z) = (1/2)log(1 - |b(z)|²) at roots of unity ──
    R_vals = Vector{Float64}(undef, N)
    for j in 1:N
        arg = 1.0 - abs2(b_vals[j])
        if arg <= 0
            @warn "weiss: |b(ω^$(j-1))|² = $(abs2(b_vals[j])) ≥ 1 (arg=$arg), clamping"
            arg = 1e-30
        end
        R_vals[j] = 0.5 * log(arg)
    end

    # ── Schwarz transform → G(z) coefficients ──
    # G is analytic in 𝔻 with Re(G) = R on 𝕋. Fourier multiplier:
    #   g_0 = r̂_0        (DC: keep, ×1)
    #   g_k = 2·r̂_k      (positive freqs k=1..N/2-1: double, ×2)
    #   g_{N/2} = r̂_{N/2} (Nyquist: keep, ×1 — split between G and G*)
    #   g_k = 0           (negative freqs: zero)
    #
    # NOTE: _bs_algorithm1 halves DC because it starts from S=2R.
    # We start from R directly, so DC is ×1 not ×1/2.
    r_hat = fft(complex.(R_vals)) ./ N
    G_hat = zeros(ComplexF64, N)
    half = N ÷ 2
    G_hat[1] = r_hat[1]                        # DC: keep (×1)
    for k in 2:half
        G_hat[k] = 2 * r_hat[k]                # positive frequencies: double (×2)
    end
    G_hat[half + 1] = r_hat[half + 1]          # Nyquist: keep (×1)
    # indices half+2 .. N remain zero (negative frequencies)

    # ── G values at roots of unity ──
    G_vals = ifft(G_hat) .* N

    return (R_vals, G_vals, b_vals, N)
end

function weiss(b::Vector{ComplexF64}, eta::Float64, epsilon::Float64)
    # ── Validate inputs (Rule 1: fail fast, fail loud) ──
    n = length(b) - 1
    n >= 0 || error("weiss: b must have at least 1 coefficient, got $(length(b))")
    eta > 0 || error("weiss: eta must be positive, got $eta")
    epsilon > 0 || error("weiss: epsilon must be positive, got $epsilon")

    @debug "weiss: n=$n, η=$eta, ε=$epsilon"

    # ── Steps 1-6: Schwarz computation ──
    R_vals, G_vals, b_vals, N = _weiss_schwarz(b, eta, epsilon)

    # ── Step 7: G*(z) = conj(G(z)) on 𝕋 ──
    # On the unit circle, G*(z) = G̅(1/z̅) = conj(G(z)) since |z| = 1.
    G_star_vals = conj.(G_vals)

    # ── Step 8: Compute b(z)·e^{-G*(z)} at roots of unity ──
    # This is b/a since a = e^{G*}.
    c_vals = b_vals .* exp.(-G_star_vals)

    # ── Step 9: FFT to get Fourier coefficients, extract [0, n] ──
    c_hat_full = fft(c_vals) ./ N
    c_hat = c_hat_full[1:n+1]

    tail_max = n + 2 <= N ? maximum(abs.(c_hat_full[n+2:end])) : 0.0
    @debug "weiss: max|ĉ_{>n}| = $tail_max (should be ≈ 0)"

    return c_hat
end

# ═══════════════════════════════════════════════════════════════════════════
# Step 3: RHW factorization (ĉ → F_k, the NLFT sequence)
# ═══════════════════════════════════════════════════════════════════════════

"""
    rhw_factorize(b::Vector{ComplexF64}, eta::Float64, epsilon::Float64) -> Vector{ComplexF64}

Generalized Riemann-Hilbert-Weiss algorithm: compute the NLFT sequence F_k
from polynomial b(z), such that the NLFT of F maps to (·, b).

Internally calls the Weiss algorithm (Step 2) to get Fourier coefficients ĉ
of b/a, then solves n+1 structured Toeplitz systems to extract F_0,...,F_n.

At each step k, forms the (n-k+1)×(n-k+1) Toeplitz matrix T_k from ĉ, then
solves the 2(n-k+1)×2(n-k+1) block system:

    [𝟙   -T_kᵀ ] [b_k    ]   [ 0      ]
    [T_k*   𝟙  ] [rev(a_k)] = [rev(e_0)]

and extracts F_k = b_{k,0} / a_{k,0}.

Current implementation: dense O(n³) solve. Half-Cholesky O(n²) deferred.

# Arguments
- `b`: Monomial coefficients [b_0, ..., b_n] of polynomial b(z)
- `eta`: Gap parameter, ||b||_∞ ≤ 1-η on 𝕋 (η > 0)
- `epsilon`: Target precision (ε > 0)

# Returns
Vector{ComplexF64} of length n+1: NLFT sequence [F_0, ..., F_n].

# Ref
Laneve (2025), arXiv:2503.03026, Algorithm 2, Section 5.2 p.12-13.
Alexis et al. (2024), arXiv:2407.05634, [30] (original RHW algorithm).
Ni, Ying (2024), arXiv:2410.06409, [31] (Half-Cholesky acceleration).
"""
function rhw_factorize(b::Vector{ComplexF64}, eta::Float64, epsilon::Float64)
    n = length(b) - 1
    n >= 0 || error("rhw_factorize: b must have at least 1 coefficient, got $(length(b))")
    eta > 0 || error("rhw_factorize: eta must be positive, got $eta")
    epsilon > 0 || error("rhw_factorize: epsilon must be positive, got $epsilon")

    @debug "rhw_factorize: n=$n, η=$eta, ε=$epsilon"

    # ── Step 1: Weiss algorithm → full ĉ sequence ──
    # Need ĉ_0 through ĉ_{2n} for the Toeplitz matrices.
    # Use _weiss_schwarz + FFT to get the full coefficient array.
    R_vals, G_vals, b_vals, N = _weiss_schwarz(b, eta, epsilon)
    G_star_vals = conj.(G_vals)
    c_vals = b_vals .* exp.(-G_star_vals)
    c_hat_full = fft(c_vals) ./ N

    # Extract ĉ[0..2n] (Julia indices 1..2n+1), zero-pad if needed
    n_need = 2 * n + 1
    if N >= n_need
        c_hat = c_hat_full[1:n_need]
    else
        c_hat = [c_hat_full[1:N]; zeros(ComplexF64, n_need - N)]
    end

    @debug "rhw_factorize: N=$N, extracted $(length(c_hat)) ĉ coefficients"

    # ── Step 2: Solve Toeplitz systems for each k ──
    F = Vector{ComplexF64}(undef, n + 1)

    for k in 0:n
        m = n - k + 1  # system block size

        # Build Toeplitz T_k (m × m): T_k[i,j] = c_{n-(i-j)}
        # 0-indexed i,j ∈ {0,...,m-1}. In Julia 1-indexed:
        # T_k[i,j] = c_hat[n + 1 - (i - j)]  (1-indexed into c_hat)
        T_k = zeros(ComplexF64, m, m)
        for i in 1:m, j in 1:m
            idx = n + 1 - (i - j)  # 1-indexed into c_hat
            if 1 <= idx <= length(c_hat)
                T_k[i, j] = c_hat[idx]
            end
        end

        # Build 2m × 2m block system:
        # [I, -T_kᵀ; T_k*, I] x = [0; rev(e_0)]
        A = zeros(ComplexF64, 2m, 2m)
        for i in 1:m; A[i, i] = 1.0; end          # upper-left: I
        A[1:m, m+1:2m] .= -transpose(T_k)          # upper-right: -T_kᵀ
        A[m+1:2m, 1:m] .= conj.(T_k)               # lower-left: T_k*
        for i in 1:m; A[m+i, m+i] = 1.0; end       # lower-right: I

        # RHS: [0; rev(e_0)] where rev(e_0) = [0,...,0,1]
        rhs = zeros(ComplexF64, 2m)
        rhs[2m] = 1.0

        # Solve
        x = A \ rhs

        # Extract F_k = b_{k,0} / a_{k,0}
        # x[1:m] = b_k, x[m+1:2m] = rev(a_k)
        # b_{k,0} = x[1], a_{k,0} = rev(a_k)[end] = x[2m]
        b_k0 = x[1]
        a_k0 = x[2m]

        if abs(a_k0) < 1e-15
            error("rhw_factorize: a_{k,0} ≈ 0 at k=$k (system degenerate)")
        end

        F[k+1] = b_k0 / a_k0

        @debug "rhw_factorize: k=$k, F_k=$(F[k+1]), |F_k|=$(abs(F[k+1]))"
    end

    return F
end
