# QSVT circuit implementations.
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
