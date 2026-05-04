# Polynomial approximations for QSVT target functions.
#
# For Hamiltonian simulation, the target function is e^{-ixt} on x ∈ [-1, 1].
# The Jacobi-Anger expansion gives:
#
#   e^{-ixt} = J₀(t) T₀(x) + 2 Σ_{k=1}^∞ (-i)^k Jₖ(t) Tₖ(x)
#
# where Jₖ are Bessel functions of the first kind and Tₖ are Chebyshev
# polynomials of the first kind.
#
# Truncating at degree d gives a polynomial P_d(x) with error bounded by
# the Bessel function tail: |e^{-ixt} - P_d(x)| ≤ 2 Σ_{k>d} |Jₖ(t)|.
# For d ≥ |t|, the Bessel functions decay super-exponentially, giving
# convergence rate O((e|t|/2d)^d) (Stirling bound on Bessel tail).
#
# Ref: Martyn, Rossi, Tan, Chuang (2021), "Grand Unification of Quantum
#      Algorithms", arXiv:2105.02859, Section III.B, Eq. (29)-(30).
#      Local PDF: docs/literature/quantum_simulation/qsp_qsvt/2105.02859.pdf
#
# Ref: Gilyen, Su, Low, Wiebe (2019), arXiv:1806.01838, Corollary 62
#      (degree bounds for Hamiltonian simulation polynomial).

using SpecialFunctions: besselj, erf

"""
    jacobi_anger_coeffs(t::Real, d::Int) -> Vector{ComplexF64}

Compute Chebyshev coefficients c₀, c₁, ..., c_d for the degree-d Jacobi-Anger
approximation to e^{-ixt} on x ∈ [-1, 1].

The polynomial is P(x) = Σ_{k=0}^d cₖ Tₖ(x) where:
  c₀ = J₀(t)
  cₖ = 2(-i)^k Jₖ(t)   for k ≥ 1

The result satisfies |P(x)| ≤ 1 for x ∈ [-1, 1] (since |e^{-ixt}| = 1).

# Arguments
- `t::Real`: simulation time (may be negative)
- `d::Int`: polynomial degree (must be ≥ 0)

Ref: Martyn et al. (2021), arXiv:2105.02859, Eq. (29)-(30).
"""
function jacobi_anger_coeffs(t::Real, d::Int)
    d >= 0 || error("jacobi_anger_coeffs: degree must be ≥ 0, got $d")
    tf = Float64(t)

    coeffs = Vector{ComplexF64}(undef, d + 1)
    coeffs[1] = besselj(0, tf)
    for k in 1:d
        coeffs[k + 1] = 2 * (-im)^k * besselj(k, tf)
    end
    return coeffs
end

"""
    jacobi_anger_cos_coeffs(t::Real, d::Int) -> Vector{Float64}

Compute REAL Chebyshev coefficients for the degree-d approximation to cos(xt).

The even part of the Jacobi-Anger expansion:
  cos(xt) = J₀(t) + 2Σ_{k=1}^{⌊d/2⌋} (-1)^k J_{2k}(t) T_{2k}(x)

Returns a vector of length d+1 where odd-indexed coefficients are zero.
The result satisfies |P(x)| ≤ 1 for x ∈ [-1, 1] and P has even parity.

Ref: Martyn et al. (2021), arXiv:2105.02859, Eq. (29)-(30).
     GSLW (2019), arXiv:1806.01838, Corollary 62.
"""
function jacobi_anger_cos_coeffs(t::Real, d::Int)
    d >= 0 || error("jacobi_anger_cos_coeffs: degree must be ≥ 0, got $d")
    tf = Float64(t)
    coeffs = zeros(Float64, d + 1)
    coeffs[1] = besselj(0, tf)  # c₀ = J₀(t)
    for k in 1:d÷2
        # (-i)^{2k} = (-1)^k, so Re[2(-i)^{2k} J_{2k}(t)] = 2(-1)^k J_{2k}(t)
        idx = 2k + 1  # Julia 1-indexed
        if idx <= d + 1
            coeffs[idx] = 2.0 * (-1)^k * besselj(2k, tf)
        end
    end
    return coeffs
end

"""
    jacobi_anger_sin_coeffs(t::Real, d::Int) -> Vector{Float64}

Compute REAL Chebyshev coefficients for the degree-d approximation to -sin(xt).

The odd part of the Jacobi-Anger expansion:
  -sin(xt) = 2Σ_{k=0}^{⌊(d-1)/2⌋} (-1)^{k+1} J_{2k+1}(t) T_{2k+1}(x)

Returns a vector of length d+1 where even-indexed coefficients are zero.
The result satisfies |P(x)| ≤ 1 for x ∈ [-1, 1] and P has odd parity.

Ref: Martyn et al. (2021), arXiv:2105.02859, Eq. (29)-(30).
"""
function jacobi_anger_sin_coeffs(t::Real, d::Int)
    d >= 1 || error("jacobi_anger_sin_coeffs: degree must be ≥ 1, got $d")
    tf = Float64(t)
    coeffs = zeros(Float64, d + 1)
    for k in 0:(d-1)÷2
        # (-i)^{2k+1} = (-1)^k · (-i), so Im[2(-i)^{2k+1} J_{2k+1}(t)] = -2(-1)^k J_{2k+1}(t)
        # We want -sin(xt), so coefficient is -2(-1)^k J_{2k+1}(t) ... wait:
        # e^{-ixt} = cos(xt) - i·sin(xt)
        # The full Jacobi-Anger: c_k = 2(-i)^k J_k(t) for k ≥ 1
        # For odd k=2m+1: c_{2m+1} = 2(-i)^{2m+1} J_{2m+1}(t) = 2(-1)^m·(-i)·J_{2m+1}(t)
        # This is purely imaginary. The imaginary part is Im(c_{2m+1}) = -2(-1)^m J_{2m+1}(t)
        # Since e^{-ixt} = Re(e^{-ixt}) + i·Im(e^{-ixt}) = cos(xt) - i·sin(xt),
        # and the odd Chebyshev terms contribute to -i·sin(xt),
        # we have: -sin(xt) = Σ Im(c_{2m+1}) T_{2m+1}(x) = -2Σ(-1)^m J_{2m+1}(t) T_{2m+1}(x)
        idx = 2k + 2  # Julia 1-indexed for T_{2k+1}
        if idx <= d + 1
            coeffs[idx] = -2.0 * (-1)^k * besselj(2k + 1, tf)
        end
    end
    return coeffs
end

"""
    chebyshev_eval(coeffs::Vector{ComplexF64}, x::Real) -> ComplexF64

Evaluate a Chebyshev expansion P(x) = Σ_{k=0}^d cₖ Tₖ(x) using
the Clenshaw recurrence (numerically stable, O(d) operations).

# Arguments
- `coeffs`: Chebyshev coefficients [c₀, c₁, ..., c_d]
- `x`: evaluation point (should be in [-1, 1] for convergence)

Ref: Clenshaw (1955), "A note on the summation of Chebyshev series",
     Mathematics of Computation 9(51):118-120.
"""
# ═══════════════════════════════════════════════════════════════════════════
# Sign-function polynomial — Lin-Tong 2020 Lemma 3 (eigenvalue filter / GSP).
# ═══════════════════════════════════════════════════════════════════════════
#
# Lemma 3 (Lin-Tong 2020, restated from GSLW19 Lemma 14).
# For all 0 < δ < 1, 0 < ε < 1, there exists an *odd* polynomial S(·;δ,ε) ∈ ℝ[x]
# of degree ℓ = O((1/δ)·log(1/ε)) such that
#   (1) |S(x)| ≤ 1                  for all x ∈ [-1, 1]
#   (2) |S(x; δ, ε) - sign(x)| ≤ ε  for x ∈ [-1, -δ] ∪ [δ, 1].
#
# Construction: truncated Chebyshev expansion of erf(K·x) with K chosen so the
# plateau-error 1 - erf(K·δ) is below ε/2. Truncation degree d picked so the
# tail mass sum_{n>d} |c_n| ≤ ε/8. Final rescale by (1 - ε/4) ensures
# |S(x)| ≤ 1 - ε/4 < 1 strictly, leaving the QSP downscaling step inside
# `qsvt_phases` (BS-25 → Laneve-25 RHW) some headroom.
#
# Chebyshev coefficients are computed via DCT-I of erf(K·x) sampled at the
# Chebyshev–Lobatto nodes x_j = cos(jπ/N), j = 0..N. Direct O(N²) evaluation
# (N ≲ 1024 for typical (δ, ε)) — FFTW would buy a constant factor on big N
# but is unnecessary at the QSVT regime.
#
# Ref: Lin, Tong (2020), "Near-optimal ground state preparation",
#      arXiv:2002.12508, Lemma 3.
#      Distillation: docs/physics/lin_tong_2020_ground_state_prep.md
#      Local PDF:    docs/literature/quantum_simulation/qsp_qsvt/2002.12508.pdf
# Ref: Gilyén, Su, Low, Wiebe (2019), arXiv:1806.01838, Lemma 14
#      (the original GSLW formulation; Lin-Tong rescales the interval).

"""
    sign_polynomial(delta::Real, epsilon::Real) -> Vector{Float64}

Chebyshev coefficients of an odd polynomial `S(x; δ, ε)` approximating
`sign(x)` per Lin-Tong 2020 Lemma 3:

    (1)  |S(x)| ≤ 1                   for x ∈ [-1, 1]
    (2)  |S(x) - sign(x)| ≤ ε         for x ∈ [-1, -δ] ∪ [δ, 1]

Polynomial degree is `O((1/δ) log(1/ε))` and is chosen automatically so that
the truncation-tail mass is below `ε/8`; the result is then scaled by
`1 - ε/4` to leave the QSVT phase pipeline (`qsvt_phases`, BS-25 + Laneve-25
RHW) some headroom for its own downscaling step.

Output is real, has *odd* parity (even-indexed coefficients are exactly zero),
and feeds directly into [`qsvt_phases`](@ref) → [`qsvt_reflect!`](@ref).

# Arguments
- `delta::Real`  — gap parameter `δ ∈ (0, 1)`. The polynomial may deviate
                    from `sign(x)` inside `(-δ, δ)` but must approximate
                    within `ε` outside.
- `epsilon::Real` — uniform plateau error `ε ∈ (0, 1)`.

# Returns
`Vector{Float64}` of length `d+1` carrying Chebyshev coefficients
`[c₀, c₁, ..., c_d]`, with `c_{2k} = 0`.

# Use case

The QSVT eigenvalue filter (Lin-Tong 2020 §2) needs `sign((H-µI)/α)` applied
to a state; this function provides the polynomial part. The downstream
pipeline is then:

```julia
cheb = sign_polynomial(δ, ε)
phi  = qsvt_phases(cheb; epsilon = ε/4)
@context EagerContext() begin
    sys = [QBool(0.0) for _ in 1:N]
    success = qsvt_reflect!(sys, be_of_H_minus_µ, phi)
    # On success, sys carries S((H-µ)/α)·|0⟩^N — eigenstates with
    # eigenvalue < µ get +1, > µ get -1 (sign flip).
end
```

# Refs
- Lin, Tong (2020), arXiv:2002.12508, Lemma 3.
  Distillation: `docs/physics/lin_tong_2020_ground_state_prep.md`.
- Gilyén, Su, Low, Wiebe (2019), arXiv:1806.01838, Lemma 14 (rescaled to [-1,1]).
"""
function sign_polynomial(delta::Real, epsilon::Real)
    0 < delta < 1   || error("sign_polynomial: need 0 < delta < 1, got delta=$delta")
    0 < epsilon < 1 || error("sign_polynomial: need 0 < epsilon < 1, got epsilon=$epsilon")

    δ = Float64(delta)
    ε = Float64(epsilon)

    # ── Step 1: choose K so the plateau error is ≤ ε/2 ──────────────────────
    # erfc bound: 1 - erf(z) ≤ exp(-z²) for z ≥ 1.  Require K·δ ≥ 1 AND
    #   exp(-(K·δ)²) ≤ ε/2  ⇒  K ≥ √(log(2/ε))/δ.
    K = max(sqrt(log(2.0 / ε)) / δ, 1.0 / δ)

    # ── Step 2: oversample at Chebyshev–Lobatto nodes ───────────────────────
    # Chebyshev coefficients of erf(K·x) decay super-exponentially past degree
    # ~K, so 4K samples is plenty for the tail-mass bound below to be tight.
    N = max(64, nextpow(2, ceil(Int, 4 * K)))
    samples = Vector{Float64}(undef, N + 1)
    @inbounds for j in 0:N
        samples[j + 1] = erf(K * cos(j * π / N))
    end

    # ── Step 3: DCT-I → Chebyshev coefficients [c₀, …, c_N] ─────────────────
    # Convention: chebyshev_eval treats coeffs[1] as the full c₀ weight, so
    # the DCT-I result for n = 0 is halved post-hoc.
    c = zeros(Float64, N + 1)
    @inbounds for n in 0:N
        s = 0.5 * samples[1]
        for j in 1:(N - 1)
            s += samples[j + 1] * cos(n * π * j / N)
        end
        s += 0.5 * (-1)^n * samples[N + 1]
        c[n + 1] = (2.0 / N) * s
    end
    c[1] /= 2.0

    # ── Step 4: force odd parity (zero out even-degree coefficients) ────────
    # erf is odd so even-degree coefs are already O(eps) numerical noise.
    @inbounds for k in 1:2:length(c)   # k = 1, 3, 5, … → degrees 0, 2, 4, …
        c[k] = 0.0
    end

    # ── Step 5: truncate at smallest d with tail mass ≤ ε/8 ─────────────────
    tail_budget = ε / 8.0
    tail = 0.0
    d = N
    @inbounds for n in N:-1:1
        tail += abs(c[n + 1])
        if tail > tail_budget
            d = n                                  # keep c_0..c_n
            break
        end
        d = n - 1
    end
    d = max(d, 1)
    isodd(d) || (d += 1)                            # promote to odd → odd parity
    d = min(d, N)

    # ── Step 6: rescale by (1 - ε/4) so |S(x)| ≤ 1 - ε/4 strictly ───────────
    return c[1:(d + 1)] .* (1.0 - ε / 4.0)
end

# ═══════════════════════════════════════════════════════════════════════════
# Chebyshev evaluation (Clenshaw recurrence) — used by callers and by tests.
# ═══════════════════════════════════════════════════════════════════════════

function chebyshev_eval(coeffs::Vector{ComplexF64}, x::Real)
    d = length(coeffs) - 1
    d >= 0 || error("chebyshev_eval: need at least 1 coefficient")

    xf = Float64(x)

    # Clenshaw recurrence: T_{k+1}(x) = 2x·T_k(x) - T_{k-1}(x)
    # b_{d+2} = b_{d+1} = 0
    # b_k = 2x·b_{k+1} - b_{k+2} + c_k   for k = d, d-1, ..., 1
    # P(x) = b_1·x - b_2 + c_0  ... no, standard Clenshaw for Chebyshev:
    # P(x) = c_0 + x·b_1 - b_2  (for modified first term since T_0 = 1)
    #
    # Actually the standard Clenshaw for Σ c_k T_k(x):
    # b_{n+1} = b_{n+2} = 0
    # b_k = 2x·b_{k+1} - b_{k+2} + c_k
    # P(x) = b_0 - x·b_1  ... let me use the textbook form.
    #
    # Better: use the fact that T_k(x) = cos(k·arccos(x)) for |x| ≤ 1.
    # Direct evaluation is stable and simple for moderate d.

    if d == 0
        return coeffs[1]
    end

    # Clenshaw algorithm for Chebyshev sum Σ_{k=0}^d c_k T_k(x)
    b_next = zero(ComplexF64)  # b_{d+2}
    b_curr = zero(ComplexF64)  # b_{d+1}

    for k in d:-1:1
        b_prev = 2xf * b_curr - b_next + coeffs[k + 1]
        b_next = b_curr
        b_curr = b_prev
    end

    # Final step: P(x) = c_0 + x·b_1 - b_2
    # Here b_curr = b_1, b_next = b_2
    return coeffs[1] + xf * b_curr - b_next
end
