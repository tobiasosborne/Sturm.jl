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

    # GQSP protocol (Theorem 9, Laneve 2025):
    #   Matrix product: e^{iλZ} · A₀ · W̃ · A₁ · W̃ · ··· · W̃ · Aₙ |0⟩
    #   Time order:     Aₙ first on |0⟩, then W̃, ..., then A₀, then e^{iλZ} last.
    for k in phases.degree:-1:0
        # Processing operator A_k = e^{iφ_k X}·e^{iθ_k Z}
        apply_processing_op!(signal, phases.phi[k + 1], phases.theta[k + 1])

        # Signal operator W̃ = diag(z, 1) ≡ Rz(-θ) (between A_k and A_{k-1})
        if k > 0
            signal.φ += -theta_signal
        end
    end

    # e^{iλZ} = Rz(-2λ), applied last (leftmost in matrix product)
    signal.φ += -2 * phases.lambda

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

# ═══════════════════════════════════════════════════════════════════════════
# Reflection QSVT circuit (GSLW Definition 15 + Theorem 17)
#
# The correct way to apply polynomial transformations to block encodings.
# Uses Z-rotations on the block encoding's ancilla qubit, interleaved
# with alternating U / U† applications. No separate signal qubit.
#
# Circuit structure for n phases (GSLW Definition 15, Eq 31):
#   Time order: U, Rz(φₙ), U†, Rz(φₙ₋₁), U, Rz(φₙ₋₂), ...
#   Pattern: start with U, alternate oracle (U↔U†) and Rz
#   Total: n oracle calls + n Z-rotations on ancilla
#
# Phase convention: Rz here means e^{iφ_k Z} = diag(e^{iφ}, e^{-iφ})
# on the ancilla qubit. In Sturm DSL: ancilla.φ += -2φ_k.
#
# Post-selection: project ancilla onto |0⟩ after the circuit.
#   Even n: P^{(SV)}(A) = Π U_Φ Π  (Theorem 17)
#   Odd n:  P^{(SV)}(A) = Π̃ U_Φ Π  (Theorem 17)
# For single-ancilla: Π = Π̃ = |0⟩⟨0|, so both cases project the same way.
#
# Ref: Gilyén, Su, Low, Wiebe (2019), arXiv:1806.01838,
#      Definition 15, Theorem 17, Lemma 19.
# ═══════════════════════════════════════════════════════════════════════════

"""
    qsvt_reflect!(system::Vector{QBool}, be::BlockEncoding,
                   phases::Vector{Float64}) -> Bool

Execute the GSLW reflection QSVT circuit on a block encoding.

Applies a polynomial P(x) to the singular values of the block-encoded
operator A/α, using Z-rotations on the ancilla interleaved with
alternating U / U† applications.

The circuit implements (GSLW Definition 15):
    U_Φ = e^{iφ₁Z}·U†·e^{iφ₂Z}·U·...    (even n)
    U_Φ = e^{iφ₁Z}·U·e^{iφ₂Z}·U†·...     (odd n)

Post-selecting ancilla on |0⟩ gives P^{(SV)}(A/α).

# Arguments
- `system`: system qubits (must match `be.n_system`)
- `be`: block encoding of the target operator
- `phases`: Z-constrained QSVT phases [φ₁, φ₂, ..., φₙ] (n phases, NOT n+1)

# Returns
`true` if post-selection succeeded (all ancilla measured |0⟩).

# Ref
GSLW (2019), arXiv:1806.01838, Definition 15, Theorem 17.
"""
function qsvt_reflect!(system::Vector{QBool}, be::BlockEncoding,
                        phases::Vector{Float64})
    length(system) == be.n_system || error(
        "qsvt_reflect!: expected $(be.n_system) system qubits, got $(length(system))")
    n = length(phases)
    n >= 1 || error("qsvt_reflect!: need at least 1 phase, got 0")
    ctx = system[1].ctx

    # ── Allocate ancilla qubits ──
    ancillas = [QBool(ctx, 0.0) for _ in 1:be.n_ancilla]

    # ── QSVT circuit (GSLW Definition 15) ──
    # Time order: U, Rz(φₙ), U†, Rz(φₙ₋₁), U, Rz(φₙ₋₂), ...
    # Oracle alternates: U first, then U†, then U, then U†, ...
    use_oracle = true  # true = U, false = U†
    for j in n:-1:1
        # Apply oracle (U or U†)
        if use_oracle
            be.oracle!(ancillas, system)
        else
            be.oracle_adj!(ancillas, system)
        end

        # Apply Z-rotation e^{iφ_j Z} on first ancilla qubit
        # e^{iφZ} = diag(e^{iφ}, e^{-iφ}) = Rz(-2φ)
        ancillas[1].φ += -2.0 * phases[j]

        use_oracle = !use_oracle  # alternate U ↔ U†
    end

    # ── Post-select ancilla on |0⟩ ──
    success = true
    for a in ancillas
        if Bool(a)
            success = false
        end
    end

    return success
end

# ═══════════════════════════════════════════════════════════════════════════
# Z-constrained phase computation for real Chebyshev polynomials
# ═══════════════════════════════════════════════════════════════════════════

"""
    qsvt_phases(cheb_real::Vector{Float64}; epsilon::Float64=1e-10) -> Vector{Float64}

Compute Z-constrained QSVT phases for a REAL Chebyshev polynomial.

Given a real polynomial P(x) = Σ cₖ Tₖ(x) with |P(x)| ≤ 1 on [-1,1],
computes the phase angles φ₁,...,φₙ for the GSLW reflection QSVT circuit
(Definition 15, Theorem 17).

Pipeline:
1. Chebyshev → analytic conversion (degree d → 2d), Laneve Lemma 1
2. b = -i·P_analytic·scale (Section 4.3 + downscaling)
3. Weiss + RHW → NLFT sequence F_k ∈ iℝ (purely imaginary for real P)
4. Phase extraction → X-constrained GQSP phases (θ_k = 0, λ = 0)
5. Section 4.3 correction: φₙ += π/2
6. Parity-matched trim: drop φ₀ for even parity, keep φ₀ for odd parity.

The X-constrained GQSP phases ARE the Z-constrained QSVT phases
(same numerical values) via the Hadamard conjugation identity
H·e^{iφX}·H = e^{iφZ} (Laneve Section 2.1).

# Arguments
- `cheb_real`: real Chebyshev coefficients [c₀, c₁, ..., c_d]
- `epsilon`: target precision for the phase computation

# Returns
`Vector{Float64}` of length matched to the Chebyshev polynomial's parity:
- **even parity** (cos-like, `c₁ = c₃ = ... = 0`): **2d** phases,
  implementing an even polynomial on the singular values.
- **odd parity** (sin-like, `c₀ = c₂ = ... = 0`): **2d+1** phases,
  implementing an odd polynomial on the singular values (sign preserved).

Parity matching is required by GSLW Theorem 17: n and the polynomial
parity must agree, or the SVT collapses eigenvalue signs (Hermitian A
maps through P(|λ|) under even n, losing sign).

# Ref
Berntson, Sünderhauf (2025), CMP 406:161 (completion step).
Laneve (2025), arXiv:2503.03026, Theorem 9, Section 4.3.
GSLW (2019), arXiv:1806.01838, Theorem 3, Definition 15.
"""
function qsvt_phases(cheb_real::Vector{Float64}; epsilon::Float64=1e-10)
    d = length(cheb_real) - 1
    d >= 0 || error("qsvt_phases: need at least 1 coefficient")

    # ── Step 1: Chebyshev → analytic (degree d → 2d) ──
    P_analytic = chebyshev_to_analytic(ComplexF64.(cheb_real))
    n_a = length(P_analytic) - 1  # = 2d

    # ── Step 2: b = -i·P (Laneve Section 4.3) ──
    b_raw = -im .* P_analytic

    # ── Step 3: Downscale to create gap ──
    η = epsilon / 4
    N_est = nextpow(2, max(1024, 4 * length(b_raw)))
    b_pad = zeros(ComplexF64, N_est)
    b_pad[1:length(b_raw)] .= b_raw
    b_est = ifft(b_pad) .* N_est
    max_b = sqrt(maximum(abs2.(b_est)))
    scale = (1.0 - η) / max(max_b, 1.0 - η)
    b_scaled = b_raw .* scale

    # ── Step 4: NLFT inverse → phase extraction ──
    F = rhw_factorize(b_scaled, η, epsilon / 4)
    phases = extract_phases(F)

    # ── Validate X-constrained (θ_k ≈ 0, λ ≈ 0) ──
    max_theta = maximum(abs.(phases.theta))
    if max_theta > 1e-3
        @warn "qsvt_phases: non-zero θ_k detected (max |θ| = $max_theta). " *
              "Input may not be a real Chebyshev polynomial."
    end
    if abs(phases.lambda) > 1e-3
        @warn "qsvt_phases: non-zero λ = $(phases.lambda). " *
              "Input may not be a real Chebyshev polynomial."
    end

    # ── Step 5: Section 4.3 correction: φₙ += π/2 ──
    # Puts the target polynomial in the P (|0⟩) position.
    phi = copy(phases.phi)
    phi[end] += π / 2

    # ── Step 6: Determine parity and return phases ──
    # The Chebyshev→analytic conversion doubles degree d→2d, giving 2d+1
    # GQSP phases (φ₀,...,φ_{2d}). The reflection QSVT parity (GSLW Theorem 17)
    # must match the Chebyshev polynomial parity:
    #   - Even Chebyshev (cos): drop φ₀ → 2d phases (even n) → even polynomial
    #   - Odd Chebyshev (sin):  keep φ₀ → 2d+1 phases (odd n) → odd polynomial
    #
    # With even n, the SVT maps eigenvalue λ through P(|λ|), losing sign.
    # With odd n, eigenvalue sign is preserved: P(λ) = sign(λ)·|P(|λ|)|.
    # For Hermitian operators, eigenvalue transformation P(A) requires matching
    # parity between n and the polynomial.
    #
    # Parity detection: check if even-indexed Chebyshev coefficients are ≈ 0
    # (odd polynomial has c₀ = c₂ = c₄ = ... ≈ 0).
    is_odd = all(abs(cheb_real[k]) < 1e-12 for k in 1:2:length(cheb_real))
    if is_odd
        return phi          # keep φ₀ → 2d+1 phases (odd n)
    else
        return phi[2:end]   # drop φ₀ → 2d phases (even n)
    end
end

# ═══════════════════════════════════════════════════════════════════════════
# Naked (no-alloc) combined QSVT circuit body + adjoint
# ═══════════════════════════════════════════════════════════════════════════

"""
    _qsvt_combined_naked!(system, be, phi_even, phi_odd, ancillas, q_re, q_lcu)

The body of the Theorem 56 combined QSVT circuit WITHOUT allocation or
measurement. Operates on pre-allocated ancillas, q_re, and q_lcu.

Ref: GSLW (2019), arXiv:1806.01838, Theorem 56, Figure 1(c).
"""
function _qsvt_combined_naked!(system::Vector{QBool}, be::BlockEncoding,
                                phi_even::Vector{Float64},
                                phi_odd::Vector{Float64},
                                ancillas::Vector{QBool},
                                q_re::QBool, q_lcu::QBool)
    n_even = length(phi_even)
    n_odd = length(phi_odd)
    anc = ancillas[1]

    use_oracle = true
    for k in 1:n_even
        if use_oracle
            be.oracle!(ancillas, system)
        else
            be.oracle_adj!(ancillas, system)
        end

        phi_e = phi_even[n_even - k + 1]
        phi_o = phi_odd[n_odd - k + 1]
        delta = phi_o - phi_e

        anc ⊻= q_re
        anc.φ += -2.0 * phi_e
        anc ⊻= q_re

        anc ⊻= q_re
        anc.φ += -delta
        anc ⊻= q_lcu
        anc.φ += +delta
        anc ⊻= q_lcu
        anc ⊻= q_re

        use_oracle = !use_oracle
    end

    when(q_lcu) do
        if use_oracle
            be.oracle!(ancillas, system)
        else
            be.oracle_adj!(ancillas, system)
        end
    end

    phi_o_last = phi_odd[1]
    anc ⊻= q_re
    anc.φ += -phi_o_last
    anc ⊻= q_lcu
    anc.φ += +phi_o_last
    anc ⊻= q_lcu
    anc ⊻= q_re

    return nothing
end

"""
    _qsvt_combined_naked_adj!(system, be, phi_even, phi_odd, ancillas, q_re, q_lcu)

The ADJOINT of the Theorem 56 combined QSVT circuit body.

Ref: GSLW (2019), arXiv:1806.01838, Theorem 56.
"""
function _qsvt_combined_naked_adj!(system::Vector{QBool}, be::BlockEncoding,
                                    phi_even::Vector{Float64},
                                    phi_odd::Vector{Float64},
                                    ancillas::Vector{QBool},
                                    q_re::QBool, q_lcu::QBool)
    n_even = length(phi_even)
    n_odd = length(phi_odd)
    anc = ancillas[1]

    phi_o_last = phi_odd[1]
    anc ⊻= q_re
    anc.φ += -phi_o_last
    anc ⊻= q_lcu
    anc.φ += +phi_o_last
    anc ⊻= q_lcu
    anc ⊻= q_re

    use_oracle_at_extra = iseven(n_even)
    when(q_lcu) do
        if use_oracle_at_extra
            be.oracle_adj!(ancillas, system)
        else
            be.oracle!(ancillas, system)
        end
    end

    for k in n_even:-1:1
        phi_e = phi_even[n_even - k + 1]
        phi_o = phi_odd[n_odd - k + 1]
        delta = phi_o - phi_e

        anc ⊻= q_re
        anc.φ += +delta
        anc ⊻= q_lcu
        anc.φ += -delta
        anc ⊻= q_lcu
        anc ⊻= q_re

        anc ⊻= q_re
        anc.φ += +2.0 * phi_e
        anc ⊻= q_re

        forward_used_oracle = isodd(k)
        if forward_used_oracle
            be.oracle_adj!(ancillas, system)
        else
            be.oracle!(ancillas, system)
        end
    end

    return nothing
end

"""
    _lift_combined_to_be(be, phi_even, phi_odd) -> BlockEncoding{N, A+2}

Wrap the Theorem 56 combined QSVT circuit as a BlockEncoding.

Ref: GSLW (2019), arXiv:1806.01838, Theorem 56, Theorem 58.
"""
function _lift_combined_to_be(be::BlockEncoding{N, A},
                               phi_even::Vector{Float64},
                               phi_odd::Vector{Float64}) where {N, A}
    n_even = length(phi_even)
    n_odd = length(phi_odd)
    n_odd == n_even + 1 || error(
        "_lift_combined_to_be: need n_odd = n_even + 1, got n_even=$n_even, n_odd=$n_odd")

    new_a = A + 2

    function lifted_oracle!(ancillas::Vector{QBool}, system::Vector{QBool})
        be_ancs = ancillas[1:A]
        q_re = ancillas[A + 1]
        q_lcu = ancillas[A + 2]
        q_re.θ += π / 2
        q_lcu.θ += π / 2
        _qsvt_combined_naked!(system, be, phi_even, phi_odd, be_ancs, q_re, q_lcu)
        q_lcu.φ += π / 2
        q_lcu.θ += -π / 2
        q_re.θ += -π / 2
        return nothing
    end

    function lifted_oracle_adj!(ancillas::Vector{QBool}, system::Vector{QBool})
        be_ancs = ancillas[1:A]
        q_re = ancillas[A + 1]
        q_lcu = ancillas[A + 2]
        q_re.θ += π / 2
        q_lcu.θ += π / 2
        q_lcu.φ += -π / 2
        _qsvt_combined_naked_adj!(system, be, phi_even, phi_odd, be_ancs, q_re, q_lcu)
        q_lcu.θ += -π / 2
        q_re.θ += -π / 2
        return nothing
    end

    return BlockEncoding{N, new_a}(lifted_oracle!, lifted_oracle_adj!, 2.0)
end

const _OAA_PHASES_CACHE = Ref{Union{Nothing, Vector{Float64}}}(nothing)

"""
    _oaa_phases_half() -> Vector{Float64}

Compute Z-constrained QSVT phases for -T_3(x). Cached.

Ref: GSLW (2019), arXiv:1806.01838, Corollary 28.
"""
function _oaa_phases_half()
    if _OAA_PHASES_CACHE[] !== nothing
        return _OAA_PHASES_CACHE[]
    end
    # Direct Chebyshev-convention QSVT phases for -T₃(x) = 3x - 4x³.
    # 3 phases for 3 oracle calls (degree-3 polynomial).
    #
    # Computed by numerical optimization over the 2×2 SU(2) matrix product
    # of the reflection QSVT circuit (Definition 15). Verified to machine
    # precision at 11 points in [0,1]. The BS+NLFT pipeline cannot produce
    # these because its Chebyshev→analytic degree doubling collapses for
    # Chebyshev basis vectors.
    #
    # Ref: GSLW (2019), arXiv:1806.01838, Corollary 8, Corollary 28.
    phases = [-π, -π/2, π/2]
    _OAA_PHASES_CACHE[] = phases
    return phases
end

"""
    _reflect_ancilla_phase!(ancillas, phi)

Apply e^{iφ(2Π-I)} where Π = |0⟩⟨0|^⊗m on the ancilla register.

This is the multi-ancilla generalization of the single-qubit Rz(−2φ) used
in qsvt_reflect!. For m=1 it reduces to Rz(−2φ) on the ancilla.
For m>1 it applies a phase e^{2iφ} to the |0...0⟩ component.

Circuit: X-all, multi-controlled-phase(2φ) on |1...1⟩, X-all.
The multi-controlled phase uses the Toffoli cascade from _multi_controlled_z!
with the angle generalized from π to 2φ.

Up to global phase e^{-iφ} (unobservable in the channel model).

Ref: GSLW (2019), arXiv:1806.01838, Definition 15, Lemma 19.
"""
function _reflect_ancilla_phase!(ancillas::Vector{QBool}, phi::Float64)
    m = length(ancillas)
    if m == 1
        # Single ancilla: e^{iφ(2|0⟩⟨0|-I)} = diag(e^{iφ}, e^{-iφ}) = Rz(-2φ)
        ancillas[1].φ += -2.0 * phi
        return nothing
    end

    # Multi-ancilla: apply phase e^{2iφ} to |0...0⟩ component.
    # Circuit: X all → phase on |1...1⟩ → X all.
    # Phase on |1...1⟩ = multi-controlled Rz(2φ) on last qubit, controlled by rest.
    for q in ancillas; q.θ += π; end  # X all (|0⟩ → |1⟩)

    # Multi-controlled phase(2φ) on |1...1⟩:
    # For 2 qubits: controlled-phase = _cz! generalized.
    # For m qubits: Toffoli cascade to compute AND, then phase, then uncompute.
    if m == 2
        # Controlled-Rz(2φ): apply Rz(2φ) on target controlled by control
        # CRz decomposition: Rz(φ) on target, CNOT, Rz(-φ), CNOT, Rz(φ) on control
        # But we need controlled-PHASE, not controlled-Rz.
        # Phase on |11⟩: use CZ-like decomposition with angle 2φ instead of π.
        # CP(2φ) = Rz(φ) on each + CX + Rz(-φ) on target + CX
        ancillas[2].φ += phi
        ancillas[2] ⊻= ancillas[1]
        ancillas[2].φ += -phi
        ancillas[2] ⊻= ancillas[1]
        ancillas[1].φ += phi
    else
        # General m: Toffoli cascade to compute AND chain into workspace,
        # apply phase, uncompute. Uses m-2 workspace ancilla.
        ctx = ancillas[1].ctx
        work = [QBool(ctx, 0.0) for _ in 1:(m - 2)]

        # Forward cascade: compute AND chain
        when(ancillas[1]) do; work[1] ⊻= ancillas[2]; end
        for k in 2:(m - 2)
            when(work[k - 1]) do; work[k] ⊻= ancillas[k + 1]; end
        end

        # Apply phase: controlled-phase(2φ) between last work qubit and last ancilla
        # CP(2φ) decomposition:
        work[m - 2].φ += phi
        ancillas[m].φ += phi
        ancillas[m] ⊻= work[m - 2]
        ancillas[m].φ += -phi
        ancillas[m] ⊻= work[m - 2]

        # Backward cascade: uncompute
        for k in (m - 2):-1:2
            when(work[k - 1]) do; work[k] ⊻= ancillas[k + 1]; end
        end
        when(ancillas[1]) do; work[1] ⊻= ancillas[2]; end

        for w in work; ptrace!(w); end
    end

    for q in ancillas; q.θ += π; end  # X all (undo)
    return nothing
end

"""
    oaa_amplify!(system, be, phi_even, phi_odd) -> Bool

Oblivious Amplitude Amplification (GSLW Corollary 28, Theorem 58).

Implements the OAA circuit directly with multi-ancilla reflections
e^{iφ(2Π-I)} between oracle calls, where Π = |0⟩⟨0|^⊗(a+2).

Circuit for 3 OAA phases [φ₁, φ₂, φ₃] (time order):
  V · e^{iφ₃(2Π-I)} · V† · e^{iφ₂(2Π-I)} · V · e^{iφ₁(2Π-I)}

Post-selects all ancilla on |0⟩. Returns true if successful.

Ref: GSLW (2019), arXiv:1806.01838, Corollary 28, Theorem 58.
"""
function oaa_amplify!(system::Vector{QBool}, be::BlockEncoding,
                       phi_even::Vector{Float64},
                       phi_odd::Vector{Float64})
    lifted = _lift_combined_to_be(be, phi_even, phi_odd)
    oaa_phases = _oaa_phases_half()
    n = length(oaa_phases)
    ctx = system[1].ctx

    # Allocate ancilla for the lifted BE
    ancillas = [QBool(ctx, 0.0) for _ in 1:lifted.n_ancilla]

    # OAA circuit: alternating V/V† with multi-ancilla reflections
    use_fwd = true
    for j in n:-1:1
        if use_fwd
            lifted.oracle!(ancillas, system)
        else
            lifted.oracle_adj!(ancillas, system)
        end
        _reflect_ancilla_phase!(ancillas, oaa_phases[j])
        use_fwd = !use_fwd
    end

    # Post-select all ancilla on |0⟩
    success = true
    for a in ancillas
        if Bool(a); success = false; end
    end
    return success
end

# ═══════════════════════════════════════════════════════════════════════════
# Combined QSVT circuit (GSLW Theorem 56)
#
# Combines even (cos) and odd (sin) polynomial transformations into a single
# circuit implementing (P_even + i·P_odd)/2 = e^{iHt/α}/2.
#
# Two extra ancilla qubits beyond the block encoding's own:
#   q_re:  selects between +Φ and -Φ (real part extraction, Corollary 18)
#   q_lcu: selects between even and odd phase sets (LCU, Theorem 56)
#
# The oracle U and U† are called UNCONDITIONALLY. Only the Rz rotations on
# the BE ancilla are multiplexed, decomposed as ZZ + ZZZ interactions:
#
#   e^{i·(-1)^{q_re}·φ_{q_lcu,j}·Z_anc}
#   = e^{i·s_j·Z_re·Z_anc} · e^{i·δ_j·Z_re·Z_lcu·Z_anc}
#
# where s_j = (φ_even_j + φ_odd_j)/2, δ_j = (φ_even_j - φ_odd_j)/2.
#
# ZZ(q_re, anc):  anc⊻=q_re; anc.φ+=-2s; anc⊻=q_re
# ZZZ(q_re, q_lcu, anc): anc⊻=q_re; anc⊻=q_lcu; anc.φ+=-2δ; anc⊻=q_lcu; anc⊻=q_re
#
# Cost per rotation position: 6 CNOTs + 2 Rz. Oracle calls: unconditional.
#
# The i factor for combining cos + i·sin is absorbed by preparing q_lcu in
# (|0⟩ + i|1⟩)/√2 = S·H|0⟩ instead of H|0⟩.
#
# Post-select q_re and q_lcu on |0⟩ to extract (P_even + i·P_odd)/2.
#
# Ref: GSLW (2019), arXiv:1806.01838, Theorem 56, Corollary 18.
# ═══════════════════════════════════════════════════════════════════════════

"""
    qsvt_combined_reflect!(system::Vector{QBool}, be::BlockEncoding,
                            phi_even::Vector{Float64},
                            phi_odd::Vector{Float64}) -> Bool

Combined even+odd QSVT circuit (GSLW Theorem 56).

Applies (P_even(A/α) + i·P_odd(A/α))/2 to the system state, where
P_even and P_odd are the polynomials encoded by `phi_even` and `phi_odd`.

For Hamiltonian simulation: P_even = cos(xt), P_odd = -sin(xt), giving
(cos(Ht/α) - i·sin(Ht/α))/2 = e^{-iHt/α}/2, or with the Jacobi-Anger
sign convention: (cos + i·(-sin))/2 = e^{iHt/α}/2.

Uses 2 extra ancilla qubits (q_re, q_lcu) beyond the block encoding's own.
Oracle calls are unconditional — only the Rz rotations are multiplexed.

Returns `true` if post-selection succeeded (all ancilla + q_re + q_lcu = |0⟩).

# Arguments
- `system`: system qubits
- `be`: block encoding
- `phi_even`: QSVT phases for the even polynomial (from `qsvt_phases`)
- `phi_odd`: QSVT phases for the odd polynomial (from `qsvt_phases`)

# Ref
GSLW (2019), arXiv:1806.01838, Theorem 56, Corollary 18, Eq. (33).
Laneve (2025), arXiv:2503.03026, §2.1, §4.3.
"""
function qsvt_combined_reflect!(system::Vector{QBool}, be::BlockEncoding,
                                 phi_even::Vector{Float64},
                                 phi_odd::Vector{Float64})
    length(system) == be.n_system || error(
        "qsvt_combined_reflect!: expected $(be.n_system) system qubits, got $(length(system))")
    n_even = length(phi_even)
    n_odd = length(phi_odd)
    n_even >= 1 || error("qsvt_combined_reflect!: need at least 1 even phase")
    n_odd >= 1 || error("qsvt_combined_reflect!: need at least 1 odd phase")
    n_odd == n_even + 1 || error(
        "qsvt_combined_reflect!: need n_odd = n_even + 1, " *
        "got n_even=$n_even, n_odd=$n_odd. Use the same Chebyshev degree d.")
    ctx = system[1].ctx

    # ── Allocate qubits ──
    ancillas = [QBool(ctx, 0.0) for _ in 1:be.n_ancilla]
    anc = ancillas[1]
    q_re = QBool(ctx, 0.5)     # |+⟩ for Corollary 18 (real-part extraction)
    q_lcu = QBool(ctx, 0.5)    # |+⟩ for Theorem 56 (even/odd LCU)

    # ══════════════════════════════════════════════════════════════════
    # Multiplexed rotation decomposition at each shared position:
    #
    # Target: e^{i·(-1)^{q_re}·φ_sel·Z_anc} where φ_sel = φ_e (lcu=0) or φ_o (lcu=1)
    #
    # Decompose as:
    #   Part 1: ZZ(q_re, anc, φ_e)  — sign flip on base angle
    #     anc⊻=q_re; anc.φ+=-2φ_e; anc⊻=q_re
    #
    #   Part 2: Controlled-ZZ(q_re, anc, Δ) controlled by q_lcu
    #     where Δ = φ_o - φ_e. Implemented as:
    #     anc⊻=q_re; Rz(-Δ); anc⊻=q_lcu; Rz(+Δ); anc⊻=q_lcu; anc⊻=q_re
    #
    # Cost: 6 CNOTs + 3 Rz per position. Oracles unconditional.
    #
    # Ref: GSLW (2019), arXiv:1806.01838, Theorem 56, Figure 1(c).
    # ══════════════════════════════════════════════════════════════════

    # ── Shared positions k=1..n_even: unconditional oracle calls ──
    use_oracle = true  # U first
    for k in 1:n_even
        if use_oracle
            be.oracle!(ancillas, system)
        else
            be.oracle_adj!(ancillas, system)
        end

        φ_e = phi_even[n_even - k + 1]
        φ_o = phi_odd[n_odd - k + 1]
        Δ = φ_o - φ_e

        # Part 1: ZZ(q_re, anc, φ_e)
        anc ⊻= q_re
        anc.φ += -2.0 * φ_e
        anc ⊻= q_re

        # Part 2: Controlled-ZZ(q_re, anc, Δ) controlled by q_lcu
        anc ⊻= q_re        # enter ZZ frame
        anc.φ += -Δ         # CRz first half
        anc ⊻= q_lcu        # CRz CNOT
        anc.φ += +Δ         # CRz second half
        anc ⊻= q_lcu        # CRz CNOT
        anc ⊻= q_re         # exit ZZ frame

        use_oracle = !use_oracle
    end

    # ── Extra position: odd branch only (Theorem 56 controlled-U) ──
    when(q_lcu) do
        if use_oracle
            be.oracle!(ancillas, system)
        else
            be.oracle_adj!(ancillas, system)
        end
    end

    # Phase for odd branch only: φ_e = 0, φ_o = phi_odd[1], Δ = phi_odd[1]
    φ_o_last = phi_odd[1]
    # Part 1: ZZ(q_re, anc, 0) = identity (skip)
    # Part 2: Controlled-ZZ(q_re, anc, φ_o_last) controlled by q_lcu
    anc ⊻= q_re
    anc.φ += -φ_o_last
    anc ⊻= q_lcu
    anc.φ += +φ_o_last
    anc ⊻= q_lcu
    anc ⊻= q_re

    # ── Post-select ──
    success = true
    for a in ancillas
        if Bool(a); success = false; end
    end

    # q_lcu: S gate (e^{iπ/2} from Theorem 58) + undo |+⟩
    # Extracts (P_even + i·P_odd)/2.
    q_lcu.φ += π / 2    # S gate
    q_lcu.θ += -π / 2   # Ry(-π/2)
    if Bool(q_lcu); success = false; end

    # q_re: undo |+⟩
    q_re.θ += -π / 2
    if Bool(q_re); success = false; end

    return success
end

# ═══════════════════════════════════════════════════════════════════════════
# evolve! integration: Hamiltonian simulation via QSVT
# ═══════════════════════════════════════════════════════════════════════════

"""
    evolve!(qubits::Vector{QBool}, H::PauliHamiltonian, t::Real, alg::QSVT)

Hamiltonian simulation via QSVT: apply e^{-iHt/alpha} to the system state,
where alpha = lambda(H) is the block encoding normalization factor.

Uses the full GSLW Theorem 58 pipeline:
1. Jacobi-Anger cos+sin polynomials of ODD degree d (GSLW Lemma 57)
2. BS completion + NLFT inverse -> Z-constrained QSVT phases (Laneve S4.3)
3. LCU block encoding of H (Berry et al. 2015)
4. Combined QSVT circuit (GSLW Theorem 56) -> e^{-iHt/alpha}/2
5. Oblivious amplitude amplification (GSLW Corollary 28) -> e^{-iHt/alpha}
6. Post-select all ancilla on |0>

Returns `true` if post-selection succeeded. The degree d must be ODD so
that the sin polynomial has full degree d, giving n_odd = n_even + 1.

# Ref
GSLW (2019), arXiv:1806.01838, Theorem 56-58, Lemma 57, Corollary 28.
Laneve (2025), arXiv:2503.03026, S2.1, S4.3.
Berntson, Sunderhauf (2025), CMP 406:161.
"""
function evolve!(qubits::Vector{QBool}, H::PauliHamiltonian,
                  t::Real, alg::QSVT)
    N = length(qubits)
    N == nqubits(H) || error(
        "evolve!(QSVT): Hamiltonian has $(nqubits(H)) qubits, got $N")
    t_f = Float64(t)
    eps = alg.epsilon

    # ── Step 1: Polynomial degree (must be ODD for combined circuit) ──
    if alg.degree !== nothing
        d = alg.degree
        isodd(d) || error(
            "evolve!(QSVT): degree must be odd for full e^{-iHt} simulation, got $d")
    else
        d = max(3, ceil(Int, abs(t_f) + 1.5 / log(10) * log(1 / eps)))
        iseven(d) && (d += 1)  # ensure odd degree
    end

    # ── Step 2: Jacobi-Anger cos+sin polynomials (same degree d) ──
    cos_coeffs = jacobi_anger_cos_coeffs(t_f, d)
    sin_coeffs = jacobi_anger_sin_coeffs(t_f, d)

    # ── Step 3: QSVT phases via BS + NLFT pipeline ──
    phi_even = qsvt_phases(cos_coeffs; epsilon=eps)
    phi_odd = qsvt_phases(sin_coeffs; epsilon=eps)

    # ── Step 4: LCU block encoding of H ──
    be = block_encode_lcu(H)

    # ── Step 5: OAA (Theorem 56 + Corollary 28) ──
    return oaa_amplify!(qubits, be, phi_even, phi_odd)
end
