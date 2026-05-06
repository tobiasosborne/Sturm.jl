# Bead Sturm.jl-5lu4 / 4ceh-Φ0: deterministic amplitude-level operator
# equivalence test for qsvt_reflect!.
#
# Reads the |anc = 0…0⟩-block operator M directly from the Orkan amplitude
# buffer (no measurement, no shot noise) and compares against the diagonalised
# reference S(H/α). This pins the bug at amplitude precision rather than
# behind a "> N/4 success rate" threshold, which is the failure mode that has
# masked bead 4ceh in the existing statistical tests.
#
# Expected outcome on the BUGGY code:
#   * T1 (H = Z, n_ancilla = 1)             — PASSES (probe |c|=1)
#   * T2 (n_ancilla = 1, two Pauli terms)   — PASSES (probe |c|=1)
#   * T3 (n_ancilla = 2, three Pauli terms) — FAILS  (probe |c| ≈ (1-ε/4)/√2)
#
# Once 4ceh is fixed, all four assertions for T3 should pass too.

using Test, Sturm
using Sturm: sign_polynomial, qsvt_phases, chebyshev_eval,
             PauliHamiltonian, PauliTerm, pauli_X, pauli_Y, pauli_Z,
             block_encode_lcu, EagerContext, QBool, nqubits,
             _qsvt_reflect_naked!
using LinearAlgebra: eigen, Diagonal, Hermitian, norm
using Random: MersenneTwister

# ────────────────────────────────────────────────────────────────────
# Helper: build the |anc = 0…0⟩-block operator M for the qsvt_reflect!
# circuit body (oracle/Rz alternation), without the final post-select.
# Reads amplitudes directly from ctx.orkan.raw.data — pattern from
# test_compact_state.jl:30 and test_qmod.jl:269.
#
# Bit layout assumption (verified by the H=Z probe: states |…000⟩ and |…001⟩
# carry all the |0⟩-input and |1⟩-input mass): system qubits are allocated
# first, taking bits 0..N-1; ancillas take bits N..N+a-1. The |anc=0…0⟩
# slice is the first 2^N entries of the amplitude buffer.
# ────────────────────────────────────────────────────────────────────
function reflect_block_operator(H::PauliHamiltonian{N},
                                 phi::Vector{Float64}) where {N}
    be = block_encode_lcu(H)
    dim_sys = 1 << N
    M = zeros(ComplexF64, dim_sys, dim_sys)
    for j in 0:dim_sys-1
        ctx = EagerContext()
        col = zeros(ComplexF64, dim_sys)
        @context ctx begin
            sys = [QBool(ctx, Float64((j >> k) & 1)) for k in 0:N-1]
            ancillas = [QBool(ctx, 0.0) for _ in 1:be.n_ancilla]
            _qsvt_reflect_naked!(sys, be, phi, ancillas)
            dim = 1 << Int(ctx.orkan.raw.qubits)
            amps = unsafe_wrap(Array{ComplexF64,1}, ctx.orkan.raw.data, dim)
            for i in 0:dim_sys-1
                col[i+1] = amps[i+1]
            end
        end
        M[:, j+1] .= col
    end
    return M
end

# Reference: S(H/α) via spectral decomposition.
function sign_op_reference(H_mat::Matrix{ComplexF64}, alpha::Float64,
                            cheb::Vector{Float64})
    evals, evecs = eigen(Hermitian(H_mat ./ alpha))
    cheb_cx = ComplexF64.(cheb)
    S_diag = ComplexF64[real(chebyshev_eval(cheb_cx, x)) for x in evals]
    return evecs * Diagonal(S_diag) * evecs'
end

# Closest scalar c such that M ≈ c · S_truth (least-squares over the operator
# entries). On the BUGGY code, |c| ≈ (1-ε/4)/√2 instead of ≈ 1. The closest-
# scalar fit is the right comparison here because the QSVT channel is defined
# only up to a global phase — but |c| < 1 is a real amplitude loss, not a
# phase ambiguity, and is what 4ceh is about.
function closest_scalar_fit(M::Matrix{ComplexF64}, S::Matrix{ComplexF64})
    return sum(conj.(S) .* M) / sum(abs2.(S))
end

@testset "qsvt_reflect! amplitude-level operator equivalence — bead 4ceh" begin
    sX = ComplexF64[0 1; 1 0]
    sY = ComplexF64[0 -im; im 0]
    sZ = ComplexF64[1 0; 0 -1]

    # Single (cheb, phi) pair shared across all single-qubit Hamiltonians.
    # δ = 0.4 lets r/α ≥ 0.5 random Hermitians stay on the plateau, and is
    # tight enough to keep the Lemma 3 polynomial degree small.
    δ, ε  = 0.4, 0.05
    cheb  = sign_polynomial(δ, ε)
    phi   = qsvt_phases(cheb; epsilon=1e-3)

    # Operator-norm tolerance: Lemma 3 guarantees |S(λ) − sign(λ)| ≤ ε on the
    # plateau; the induced operator error on a 2×2 Hermitian is at most ε in
    # spectral norm, so the Frobenius norm is at most √2·ε. Add 0.01 for
    # circuit FP slack accumulated over O(2d) gates.
    op_tol = sqrt(2) * ε + 0.01

    # ────────────────────────────────────────────────────────────────────
    # T1 — H = Z (n_ancilla = 1). Eigenstates are |0⟩, |1⟩ on the plateau.
    # Probe finding: M = c·S(H/α) with |c| = 1. Expected PASS.
    # ────────────────────────────────────────────────────────────────────
    @testset "T1 — H = Z (n_ancilla = 1)" begin
        H = PauliHamiltonian{1}([PauliTerm{1}(1.0, (pauli_Z,))])
        be = block_encode_lcu(H)
        @test be.n_ancilla == 1
        M = reflect_block_operator(H, phi)
        S_truth = sign_op_reference(sZ, 1.0, cheb)
        c = closest_scalar_fit(M, S_truth)
        @test abs(abs(c) - 1.0) < op_tol
        @test norm(M - c * S_truth) < op_tol
    end

    # ────────────────────────────────────────────────────────────────────
    # T2 — H = aX·X + aZ·Z (n_ancilla = 1). Eigenvectors are NOT comp-basis
    # but the BE has only 1 ancilla, so Bug B (multi-ancilla Π^φ) does NOT
    # fire. The bug that fires here is Bug A (l5s5): qsvt_phases ships
    # analytic-QSP angles without the §2.1 analytic→reflection conversion
    # shift. Probe finding (session 89): |c| ≈ 0.7256 instead of 1.
    # Expected RED on current code; passes when l5s5 is fixed.
    # ────────────────────────────────────────────────────────────────────
    @testset "T2 — H = a·X + b·Z (n_ancilla = 1)" begin
        a_X, a_Z = 0.3, 0.4
        alpha = abs(a_X) + abs(a_Z)
        H_mat = a_X * sX + a_Z * sZ
        H = PauliHamiltonian{1}([
            PauliTerm{1}(a_X, (pauli_X,)),
            PauliTerm{1}(a_Z, (pauli_Z,))])
        be = block_encode_lcu(H)
        @test be.n_ancilla == 1
        M = reflect_block_operator(H, phi)
        S_truth = sign_op_reference(H_mat, alpha, cheb)
        c = closest_scalar_fit(M, S_truth)
        @test abs(abs(c) - 1.0) < op_tol
        @test norm(M - c * S_truth) < op_tol
    end

    # ────────────────────────────────────────────────────────────────────
    # T3 — H = aX·X + aY·Y + aZ·Z (n_ancilla = 2). The bug appears here.
    # Probe finding (case 1 of the existing test): M = c·S(H/α) with
    # |c| ≈ (1-ε/4)/√2 ≈ 0.697 instead of ≈ 1, residual = 0.0 exact.
    # Expected FAIL on current code; will pass once 4ceh is fixed.
    # ────────────────────────────────────────────────────────────────────
    @testset "T3 — H = a·X + b·Y + c·Z (n_ancilla = 2) — RED on current code" begin
        # Three random cases mirroring test_qsvt_sign_polynomial.jl line 188.
        # Same MT seed and same r/α >= 0.5 filter for reproducibility.
        rng = MersenneTwister(0xc0ffee)
        cases = NamedTuple[]
        while length(cases) < 3
            a_X = (rand(rng) - 0.5)
            a_Y = (rand(rng) - 0.5)
            a_Z = (rand(rng) - 0.5)
            alpha = abs(a_X) + abs(a_Y) + abs(a_Z)
            r = sqrt(a_X^2 + a_Y^2 + a_Z^2)
            r/alpha >= 0.5 || continue
            push!(cases, (a_X=a_X, a_Y=a_Y, a_Z=a_Z, alpha=alpha))
        end

        for (i, c) in enumerate(cases)
            H_mat = c.a_X * sX + c.a_Y * sY + c.a_Z * sZ
            H = PauliHamiltonian{1}([
                PauliTerm{1}(c.a_X, (pauli_X,)),
                PauliTerm{1}(c.a_Y, (pauli_Y,)),
                PauliTerm{1}(c.a_Z, (pauli_Z,))])
            be = block_encode_lcu(H)
            @test be.n_ancilla == 2

            M = reflect_block_operator(H, phi)
            S_truth = sign_op_reference(H_mat, c.alpha, cheb)
            c_fit = closest_scalar_fit(M, S_truth)

            # Diagnostic — printed when test fails.
            @info "T3 case $i: H = $(round(c.a_X,digits=3))·X + $(round(c.a_Y,digits=3))·Y + $(round(c.a_Z,digits=3))·Z   |c|=$(round(abs(c_fit),digits=4))   residual=$(round(norm(M - c_fit*S_truth),digits=4))"

            @test abs(abs(c_fit) - 1.0) < op_tol
            @test norm(M - c_fit * S_truth) < op_tol
        end
    end
end
