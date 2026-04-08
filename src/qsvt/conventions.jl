# GQSP convention adapter: phase factors → Sturm.jl primitive sequences.
#
# The GQSP protocol (Laneve 2025, Theorem 9) for a degree-n polynomial is:
#
#   e^{iλZ} · A₀ · W · A₁ · W · ··· · W · Aₙ
#
# where W = diag(z, 1) is the signal operator (block encoding oracle),
# and the processing operators are:
#
#   A_k = e^{iφ_k X} · e^{iθ_k Z}
#
# In Sturm.jl primitives on the signal qubit (q):
#
#   e^{iθZ} = Rz(-2θ)              →  q.φ += -2θ
#
#   e^{iφX} = Rz(-π/2)·Ry(-2φ)·Rz(π/2)
#           →  q.φ += π/2; q.θ += -2φ; q.φ += -π/2
#
# Proof of the X decomposition:
#   e^{iπZ/4} · Y · e^{-iπZ/4} = cos(π/2)Y + sin(π/2)X = X
#   (rotation formula: e^{iαZ} Y e^{-iαZ} = cos(2α)Y + sin(2α)X)
#   Therefore e^{iπZ/4} · e^{iφY} · e^{-iπZ/4} = e^{iφX}.
#   In Rz/Ry notation: Rz(-π/2) · Ry(-2φ) · Rz(π/2) = e^{iφX}.
#
# The initial factor e^{iλZ} = Rz(-2λ) is applied before A₀.
#
# Ref: Laneve (2025), "GQSP and NLFT are equivalent",
#      arXiv:2503.03026, Theorem 9, Eq. (4).
#      Local PDF: docs/literature/quantum_simulation/qsp_qsvt/2503.03026.pdf

"""
    QSVTPhases

Phase factors for a GQSP protocol of degree n (n oracle calls, n+1 processing operators).

Fields:
- `lambda::Float64`: initial Z-rotation parameter (e^{iλZ})
- `phi::Vector{Float64}`: X-rotation angles φ₀, φ₁, ..., φₙ (length n+1)
- `theta::Vector{Float64}`: Z-rotation angles θ₀, θ₁, ..., θₙ (length n+1)
- `degree::Int`: polynomial degree n = length(phi) - 1

The GQSP circuit is: Rz(-2λ) · [A₀ · W · A₁ · W · ··· · W · Aₙ]
where A_k = e^{iφ_k X} · e^{iθ_k Z} and W is the block encoding oracle.

Ref: Laneve (2025), arXiv:2503.03026, Theorem 9.
"""
struct QSVTPhases
    lambda::Float64
    phi::Vector{Float64}
    theta::Vector{Float64}
    degree::Int

    function QSVTPhases(lambda::Float64, phi::Vector{Float64}, theta::Vector{Float64})
        length(phi) == length(theta) || error(
            "QSVTPhases: phi and theta must have the same length, got $(length(phi)) and $(length(theta))")
        length(phi) >= 1 || error(
            "QSVTPhases: need at least 1 processing operator (degree 0)")
        new(lambda, phi, theta, length(phi) - 1)
    end
end

"""
    apply_processing_op!(signal::QBool, φ::Float64, θ::Float64)

Apply one GQSP processing operator A_k = e^{iφX} · e^{iθZ} to the signal qubit.

Decomposes into 3 primitive rotations (merging adjacent Rz):
  q.φ += (-2θ + π/2)    # Rz for e^{iθZ} merged with start of e^{iφX}
  q.θ += -2φ            # Ry core of e^{iφX}
  q.φ += -π/2           # end of e^{iφX}

Ref: Laneve (2025), arXiv:2503.03026, Theorem 9.
"""
@inline function apply_processing_op!(signal::QBool, φ::Float64, θ::Float64)
    signal.φ += -2θ + π/2   # e^{iθZ} then start of e^{iφX} (merged)
    signal.θ += -2φ          # Ry core
    signal.φ += -π/2         # end of e^{iφX}
    return nothing
end

"""
    processing_op_matrix(φ::Float64, θ::Float64) -> Matrix{ComplexF64}

Compute the 2×2 matrix for A_k = e^{iφX} · e^{iθZ} directly.

Used for testing — verifies the Ry/Rz decomposition matches the matrix definition.
Not used in quantum circuits (the circuit uses apply_processing_op! instead).
"""
function processing_op_matrix(φ::Float64, θ::Float64)
    # Rz(δ) = [e^{-iδ/2}  0; 0  e^{iδ/2}]
    # Ry(δ) = [cos(δ/2)  -sin(δ/2); sin(δ/2)  cos(δ/2)]
    δ1 = -2θ + π/2   # first Rz angle
    δ2 = -2φ          # Ry angle
    δ3 = -π/2         # last Rz angle

    Rz1 = ComplexF64[exp(-im*δ1/2) 0; 0 exp(im*δ1/2)]
    Ry  = ComplexF64[cos(δ2/2) -sin(δ2/2); sin(δ2/2) cos(δ2/2)]
    Rz3 = ComplexF64[exp(-im*δ3/2) 0; 0 exp(im*δ3/2)]

    return Rz3 * Ry * Rz1
end
