using Test
using Sturm
using Sturm: nqubits, nterms, lambda, _QDriftDist, _sample
using LinearAlgebra: eigen, Diagonal, kron

# _amp and _probs helpers defined in test_simulation.jl (included first)

# ── Helpers for state vector comparison ─────────────────────────────────────

"""State vector infidelity: 1 - |⟨ψ|φ⟩|² between two Orkan contexts."""
function _infidelity(ctx1, ctx2)
    dim = 1 << ctx1.n_qubits
    overlap = ComplexF64(0)
    for i in 0:dim-1
        overlap += conj(_amp(ctx1, i)) * _amp(ctx2, i)
    end
    1.0 - abs2(overlap)
end

"""State vector ℓ₂ error ‖ψ_approx - ψ_exact‖² from Orkan ctx vs complex vector."""
function _state_error(ctx, ψ_exact::Vector{ComplexF64})
    dim = length(ψ_exact)
    err = 0.0
    for i in 0:dim-1
        err += abs2(_amp(ctx, i) - ψ_exact[i+1])
    end
    err
end

"""Build full 2^N × 2^N matrix for PauliHamiltonian via Kronecker products.
Only feasible for N ≤ 14."""
function _pauli_matrix(H_sturm)
    N = nqubits(H_sturm)
    dim = 1 << N
    I2 = ComplexF64[1 0; 0 1]
    σx = ComplexF64[0 1; 1 0]
    σy = ComplexF64[0 -im; im 0]
    σz = ComplexF64[1 0; 0 -1]
    pauli_mats = Dict(Sturm.pauli_I => I2, Sturm.pauli_X => σx,
                      Sturm.pauli_Y => σy, Sturm.pauli_Z => σz)
    H_mat = zeros(ComplexF64, dim, dim)
    for term in H_sturm.terms
        # Orkan LSB: position 1 → qubit 0 (rightmost in kron)
        # kron order: position N, N-1, ..., 1
        M = pauli_mats[term.ops[N]]
        for k in (N-1):-1:1
            M = kron(M, pauli_mats[term.ops[k]])
        end
        H_mat .+= term.coeff .* M
    end
    H_mat
end

"""Exact exp(-iHt)|0⟩ via eigendecomposition. Only for N ≤ 14."""
function _exact_evolve(H_sturm, t::Real)
    H_mat = _pauli_matrix(H_sturm)
    dim = size(H_mat, 1)
    evals, evecs = eigen(H_mat)
    U = evecs * Diagonal(exp.(-im * t .* evals)) * evecs'
    ψ0 = zeros(ComplexF64, dim); ψ0[1] = 1.0
    U * ψ0
end


@testset "qDRIFT simulation" begin

    # ═════════════════════════════════════════════════════════════════════
    # A. Type construction and validation
    # ═════════════════════════════════════════════════════════════════════

    @testset "QDrift construction" begin
        alg = QDrift(samples=50)
        @test alg.samples == 50
        @test_throws ErrorException QDrift(samples=0)
        @test_throws ErrorException QDrift(samples=-1)
    end

    @testset "qdrift_samples computes N from error bound" begin
        H = hamiltonian(pauli_term(1.0, :Z, :Z), pauli_term(0.5, :X, :I))
        λ = lambda(H)   # 1.5
        t = 1.0
        ε = 0.01
        N = qdrift_samples(H, t, ε)
        @test N == ceil(Int, 2 * λ^2 * t^2 / ε)
        @test N == 450
        @test_throws ErrorException qdrift_samples(H, t, 0.0)
        @test_throws ErrorException qdrift_samples(H, t, -0.1)
    end

    @testset "Sampling distribution" begin
        H = hamiltonian(pauli_term(3.0, :Z, :Z), pauli_term(1.0, :X, :I))
        dist = _QDriftDist(H)
        @test dist.λ ≈ 4.0
        @test dist.cumprobs[1] ≈ 0.75
        @test dist.cumprobs[2] ≈ 1.0
        counts = zeros(Int, 2)
        for _ in 1:10000
            counts[_sample(dist)] += 1
        end
        @test abs(counts[1] / 10000 - 0.75) < 0.03
        @test abs(counts[2] / 10000 - 0.25) < 0.03
    end

    # ═════════════════════════════════════════════════════════════════════
    # B. Single-term: qDRIFT is deterministically exact
    # ═════════════════════════════════════════════════════════════════════

    @testset "Single Z term: qDRIFT exact" begin
        θ = 0.7
        ctx = EagerContext()
        q = QBool(ctx, 0)
        evolve!([q], hamiltonian(pauli_term(1.0, :Z)), θ, QDrift(samples=10))
        @test abs(_amp(ctx, 0) - exp(-im * θ)) < 1e-12
        @test abs(_amp(ctx, 1)) < 1e-12
        discard!(q)
    end

    @testset "Single X term: qDRIFT exact" begin
        θ = π/6
        ctx = EagerContext()
        q = QBool(ctx, 0)
        evolve!([q], hamiltonian(pauli_term(1.0, :X)), θ, QDrift(samples=10))
        @test abs(_amp(ctx, 0) - cos(θ)) < 1e-12
        @test abs(_amp(ctx, 1) - (-im * sin(θ))) < 1e-12
        discard!(q)
    end

    @testset "Single Y term: qDRIFT exact" begin
        θ = π/5
        ctx = EagerContext()
        q = QBool(ctx, 0)
        evolve!([q], hamiltonian(pauli_term(1.0, :Y)), θ, QDrift(samples=10))
        @test abs(_amp(ctx, 0) - cos(θ)) < 1e-12
        @test abs(_amp(ctx, 1) - sin(θ)) < 1e-12
        discard!(q)
    end

    @testset "Single negative-coeff term: qDRIFT exact" begin
        θ = 0.3
        ctx = EagerContext()
        q = QBool(ctx, 0)
        evolve!([q], hamiltonian(pauli_term(-1.0, :Z)), θ, QDrift(samples=10))
        @test abs(_amp(ctx, 0) - exp(+im * θ)) < 1e-12
        discard!(q)
    end

    # ═════════════════════════════════════════════════════════════════════
    # C. Matrix ground truth: Ising model, N=2 to N=10
    # ═════════════════════════════════════════════════════════════════════
    # Exact exp(-iHt) via eigendecomposition vs qDRIFT (averaged).
    # Campbell's bound: average channel error ≤ 2λ²t²/N.

    @testset "Ising ground truth N=$N" for N in [2, 3, 4, 6, 8, 10]
        H_sturm = ising(Val(N), J=1.0, h=0.5)
        λ_val = lambda(H_sturm)
        t = 0.2   # short time keeps error manageable

        ψ_exact = _exact_evolve(H_sturm, t)

        # Use enough samples for < 1% average error
        N_samples = max(200, ceil(Int, 4 * λ_val^2 * t^2 / 0.01))
        N_trials = 20

        total_err = 0.0
        for _ in 1:N_trials
            ctx = EagerContext()
            qs = [QBool(ctx, 0) for _ in 1:N]
            evolve!(qs, H_sturm, t, QDrift(samples=N_samples))
            total_err += _state_error(ctx, ψ_exact)
            for q in qs; discard!(q); end
        end
        avg_err = total_err / N_trials

        # Campbell bound: ‖Δ‖ ≤ 2λ²t²/N. State error ≤ ‖Δ‖² loosely.
        # With our sample count, average error should be well below 0.05.
        @test avg_err < 0.05
    end

    # ═════════════════════════════════════════════════════════════════════
    # D. O(λ²t²/N) scaling exponent verification
    # ═════════════════════════════════════════════════════════════════════
    # Double N → error should drop by ~4× (quadratic in 1/N for
    # the diamond norm, which upper-bounds state error).
    # We measure average state error and check the ratio.

    @testset "Error scaling O(1/N)" begin
        H_sturm = ising(Val(4), J=1.0, h=0.5)
        t = 0.3
        N_trials = 60

        ψ_exact = _exact_evolve(H_sturm, t)

        avg_errors = Float64[]
        for N_samples in [100, 400, 1600]
            total_err = 0.0
            for _ in 1:N_trials
                ctx = EagerContext()
                qs = [QBool(ctx, 0) for _ in 1:4]
                evolve!(qs, H_sturm, t, QDrift(samples=N_samples))
                total_err += _state_error(ctx, ψ_exact)
                for q in qs; discard!(q); end
            end
            push!(avg_errors, total_err / N_trials)
        end

        # Doubling N (100→400, 400→1600) each ×4 in samples.
        # Diamond-norm error scales as 1/N, state error ≲ (1/N)² loosely,
        # but single-realization variance adds noise. Check monotonic decrease
        # and that ×4 samples gives at least ×2 reduction (conservative).
        @test avg_errors[2] < avg_errors[1]
        @test avg_errors[3] < avg_errors[2]
        ratio_1 = avg_errors[1] / avg_errors[2]
        ratio_2 = avg_errors[2] / avg_errors[3]
        @test ratio_1 > 2.0   # ×4 samples → at least ×2 error reduction
        @test ratio_2 > 2.0
    end

    # ═════════════════════════════════════════════════════════════════════
    # E. Commuting Hamiltonian: exact (phase-correct)
    # ═════════════════════════════════════════════════════════════════════

    @testset "Commuting ZI+IZ: phase-correct" begin
        # H = Z₁ + Z₂. exp(-it(Z₁+Z₂))|00⟩ = e^{-2it}|00⟩
        t = 0.4
        ctx = EagerContext()
        q1 = QBool(ctx, 0); q2 = QBool(ctx, 0)
        evolve!([q1, q2], hamiltonian(pauli_term(1.0, :Z, :I), pauli_term(1.0, :I, :Z)),
                t, QDrift(samples=1000))
        # Check both amplitude AND phase, not just probability
        @test abs(_amp(ctx, 0) - exp(-2im * t)) < 0.02
        for i in 1:3
            @test abs(_amp(ctx, i)) < 0.02
        end
        discard!(q1); discard!(q2)
    end

    # ═════════════════════════════════════════════════════════════════════
    # F. qDRIFT vs Trotter2 cross-validation (N=2 to N=14)
    # ═════════════════════════════════════════════════════════════════════
    # Both should converge to the same answer. For small N, also check
    # against matrix ground truth.

    @testset "qDRIFT vs Trotter2: Ising N=$N" for N in [2, 4, 6, 8, 10, 14]
        H_sturm = ising(Val(N), J=1.0, h=0.5)
        λ_val = lambda(H_sturm)
        t = 0.1

        # High-accuracy Trotter2 as reference
        ctx_ref = EagerContext()
        qs_ref = [QBool(ctx_ref, 0) for _ in 1:N]
        evolve!(qs_ref, H_sturm, t, Trotter2(steps=200))

        # qDRIFT: average over trials
        N_samples = max(500, ceil(Int, 4 * λ_val^2 * t^2 / 0.001))
        N_trials = 10
        total_infid = 0.0
        for _ in 1:N_trials
            ctx_qd = EagerContext()
            qs_qd = [QBool(ctx_qd, 0) for _ in 1:N]
            evolve!(qs_qd, H_sturm, t, QDrift(samples=N_samples))
            total_infid += _infidelity(ctx_ref, ctx_qd)
            for q in qs_qd; discard!(q); end
        end
        avg_infid = total_infid / N_trials

        # Both should agree closely
        @test avg_infid < 0.01

        for q in qs_ref; discard!(q); end
    end

    # ═════════════════════════════════════════════════════════════════════
    # G. Large-N cross-validation (N=16, 20, 24)
    # ═════════════════════════════════════════════════════════════════════
    # No eigendecomposition possible. Use Trotter2(steps=50) as reference,
    # qDRIFT with proportional samples. Single realization (no averaging
    # to keep runtime manageable). Just check infidelity < threshold.

    @testset "qDRIFT vs Trotter2: Ising N=$N (large)" for N in [16, 20, 24]
        H_sturm = ising(Val(N), J=1.0, h=0.3)
        λ_val = lambda(H_sturm)
        t = 0.05  # short time for large N

        # Trotter2 reference
        ctx_ref = EagerContext()
        qs_ref = [QBool(ctx_ref, 0) for _ in 1:N]
        evolve!(qs_ref, H_sturm, t, Trotter2(steps=50))

        # qDRIFT: single realization with many samples
        N_samples = ceil(Int, 4 * λ_val^2 * t^2 / 0.001)
        ctx_qd = EagerContext()
        qs_qd = [QBool(ctx_qd, 0) for _ in 1:N]
        evolve!(qs_qd, H_sturm, t, QDrift(samples=N_samples))

        infid = _infidelity(ctx_ref, ctx_qd)
        # Single realization may have more variance, so wider tolerance
        @test infid < 0.05

        for q in qs_ref; discard!(q); end
        for q in qs_qd; discard!(q); end
    end

    # ═════════════════════════════════════════════════════════════════════
    # H. Heisenberg model tests
    # ═════════════════════════════════════════════════════════════════════

    @testset "qDRIFT Heisenberg N=$N" for N in [2, 4, 6]
        H_sturm = heisenberg(Val(N), Jx=1.0, Jy=1.0, Jz=1.0)
        t = 0.15

        ψ_exact = _exact_evolve(H_sturm, t)

        λ_val = lambda(H_sturm)
        N_samples = max(300, ceil(Int, 4 * λ_val^2 * t^2 / 0.005))
        N_trials = 15

        total_err = 0.0
        for _ in 1:N_trials
            ctx = EagerContext()
            qs = [QBool(ctx, 0) for _ in 1:N]
            evolve!(qs, H_sturm, t, QDrift(samples=N_samples))
            total_err += _state_error(ctx, ψ_exact)
            for q in qs; discard!(q); end
        end
        avg_err = total_err / N_trials
        @test avg_err < 0.05
    end

    @testset "qDRIFT vs Trotter2: Heisenberg N=$N" for N in [8, 10, 14]
        H_sturm = heisenberg(Val(N), Jx=1.0, Jy=1.0, Jz=1.0)
        λ_val = lambda(H_sturm)
        t = 0.1

        ctx_ref = EagerContext()
        qs_ref = [QBool(ctx_ref, 0) for _ in 1:N]
        evolve!(qs_ref, H_sturm, t, Trotter2(steps=200))

        N_samples = max(500, ceil(Int, 4 * λ_val^2 * t^2 / 0.001))
        N_trials = 10
        total_infid = 0.0
        for _ in 1:N_trials
            ctx_qd = EagerContext()
            qs_qd = [QBool(ctx_qd, 0) for _ in 1:N]
            evolve!(qs_qd, H_sturm, t, QDrift(samples=N_samples))
            total_infid += _infidelity(ctx_ref, ctx_qd)
            for q in qs_qd; discard!(q); end
        end
        avg_infid = total_infid / N_trials
        @test avg_infid < 0.01

        for q in qs_ref; discard!(q); end
    end

    # ═════════════════════════════════════════════════════════════════════
    # I. Edge cases
    # ═════════════════════════════════════════════════════════════════════

    @testset "Zero time is identity" begin
        ctx = EagerContext()
        q = QBool(ctx, 0)
        evolve!([q], hamiltonian(pauli_term(1.0, :X)), 0.0, QDrift(samples=10))
        @test abs(_amp(ctx, 0) - 1.0) < 1e-12
        discard!(q)
    end

    @testset "evolve! on QInt with QDrift" begin
        @context EagerContext() begin
            H = hamiltonian(pauli_term(1.0, :X))
            q = QInt{1}(0)
            result = evolve!(q, H, 0.1, QDrift(samples=10))
            @test result === q
            discard!(q)
        end
    end

    @testset "Qubit count mismatch errors" begin
        @context EagerContext() begin
            q = QBool(0)
            @test_throws ErrorException evolve!([q], hamiltonian(pauli_term(1.0, :X, :Z)), 0.1, QDrift(samples=5))
            discard!(q)
        end
    end

    @testset "evolve! rejects negative time for QDrift" begin
        @context EagerContext() begin
            q = QBool(0)
            @test_throws ErrorException evolve!([q], hamiltonian(pauli_term(1.0, :X)), -0.1, QDrift(samples=5))
            discard!(q)
        end
    end

    # ═════════════════════════════════════════════════════════════════════
    # J. DAG emit: TracingContext
    # ═════════════════════════════════════════════════════════════════════

    @testset "qDRIFT traces into Channel" begin
        H = hamiltonian(pauli_term(1.0, :Z, :Z), pauli_term(0.5, :X, :I))
        ch = trace(2) do q1, q2
            evolve!([q1, q2], H, 0.1, QDrift(samples=5))
            (q1, q2)
        end
        @test n_inputs(ch) == 2
        @test n_outputs(ch) == 2
        @test length(ch.dag) > 0
    end

    @testset "OpenQASM export from qDRIFT channel" begin
        H = hamiltonian(pauli_term(1.0, :Z))
        ch = trace(1) do q
            evolve!([q], H, 0.5, QDrift(samples=3))
            (q,)
        end
        qasm = to_openqasm(ch)
        @test occursin("OPENQASM 3.0", qasm)
        @test occursin("rz(", qasm)
    end

    # ═════════════════════════════════════════════════════════════════════
    # K. Controlled qDRIFT
    # ═════════════════════════════════════════════════════════════════════

    @testset "Controlled qDRIFT: ctrl=|0⟩ is identity" begin
        ctx = EagerContext()
        ctrl = QBool(ctx, 0)
        target = QBool(ctx, 0)
        when(ctrl) do
            evolve!([target], hamiltonian(pauli_term(1.0, :X)), 0.5, QDrift(samples=20))
        end
        @test abs(_amp(ctx, 0) - 1.0) < 1e-12
        for i in 1:3
            @test abs(_amp(ctx, i)) < 1e-12
        end
        discard!(ctrl); discard!(target)
    end

    @testset "Controlled qDRIFT: ctrl=|1⟩ applies evolution (single term)" begin
        θ = π/6
        ctx = EagerContext()
        ctrl = QBool(ctx, 1)
        target = QBool(ctx, 0)
        when(ctrl) do
            evolve!([target], hamiltonian(pauli_term(1.0, :X)), θ, QDrift(samples=10))
        end
        @test abs(_amp(ctx, 0)) < 1e-12
        @test abs(_amp(ctx, 1) - cos(θ)) < 1e-12
        @test abs(_amp(ctx, 2)) < 1e-12
        @test abs(_amp(ctx, 3) - (-im * sin(θ))) < 1e-12
        discard!(ctrl); discard!(target)
    end

end
