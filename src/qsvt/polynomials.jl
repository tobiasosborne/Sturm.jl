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

using SpecialFunctions: besselj

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
