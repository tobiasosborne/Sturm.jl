# End-to-end test: Oblivious Amplitude Amplification (OAA)
#
# OAA wraps the Theorem 56 combined QSVT circuit as a block encoding,
# then applies -T_3(x) via reflection QSVT to boost the 1/2 subnormalization
# to 1. Result: e^{-iHt/alpha} (full unitary, no subnormalization).
#
# Pipeline: Jacobi-Anger cos+sin -> qsvt_phases -> block_encode_lcu
#           -> _lift_combined_to_be -> _oaa_phases_half -> qsvt_reflect!
#
# Ref: GSLW (2019), arXiv:1806.01838, Corollary 28 (robust OAA),
#      Theorem 56 (combined QSVT), Theorem 58 (optimal Hamiltonian sim).

using Test, Sturm, FFTW
using Sturm: jacobi_anger_cos_coeffs, jacobi_anger_sin_coeffs,
             qsvt_phases, qsvt_reflect!, qsvt_combined_reflect!, QSVT,
             block_encode_lcu, ising, lambda, nqubits,
             _qsvt_combined_naked!, _qsvt_combined_naked_adj!,
             _lift_combined_to_be, _oaa_phases_half, oaa_amplify!
using LinearAlgebra: eigen, Diagonal, kron, norm

# ── Helpers ──

if !@isdefined(_pauli_matrix_oaa)
    function _pauli_matrix_oaa(H_sturm)
        N = nqubits(H_sturm)
        dim = 1 << N
        I2 = ComplexF64[1 0; 0 1]
        sx = ComplexF64[0 1; 1 0]
        sy = ComplexF64[0 -im; im 0]
        sz = ComplexF64[1 0; 0 -1]
        pauli_mats = Dict(Sturm.pauli_I => I2, Sturm.pauli_X => sx,
                          Sturm.pauli_Y => sy, Sturm.pauli_Z => sz)
        H_mat = zeros(ComplexF64, dim, dim)
        for term in H_sturm.terms
            M = pauli_mats[term.ops[N]]
            for k in (N-1):-1:1
                M = kron(M, pauli_mats[term.ops[k]])
            end
            H_mat .+= term.coeff .* M
        end
        H_mat
    end
end

@testset "Oblivious Amplitude Amplification" begin

    # ─────────────────────────────────────────────────────────────────────
    # Test 1: OAA phases are well-formed
    # ─────────────────────────────────────────────────────────────────────

    @testset "OAA phases: _oaa_phases_half returns well-formed phases" begin
        phi = _oaa_phases_half()

        # -T_3(x) is an odd degree-3 Chebyshev polynomial.
        # After chebyshev_to_analytic (degree 3 -> 6), the analytic polynomial
        # has degree 6. For odd polynomial, qsvt_phases keeps phi_0 -> 7 phases.
        @test length(phi) == 7

        # Phases should be finite
        @test all(isfinite.(phi))

        # Calling again should return the same (cached)
        phi2 = _oaa_phases_half()
        @test phi === phi2
    end

    # ─────────────────────────────────────────────────────────────────────
    # Test 2: V * V^dag roundtrip = identity (naked forward then adjoint)
    # ─────────────────────────────────────────────────────────────────────

    @testset "naked roundtrip: V*V^dag = I" begin
        t = 2.0
        N_sys = 2
        d = 7
        H = ising(Val(N_sys), J=1.0, h=0.5)

        phi_even = qsvt_phases(jacobi_anger_cos_coeffs(t, d); epsilon=1e-4)
        phi_odd = qsvt_phases(jacobi_anger_sin_coeffs(t, d); epsilon=1e-4)
        be = block_encode_lcu(H)

        # Run forward then adjoint, verify everything returns to |0>
        N_shots = 100
        n_roundtrip_success = 0
        n_sys_correct = 0

        for _ in 1:N_shots
            ctx = EagerContext()
            @context ctx begin
                sys = [QBool(ctx, 0.0) for _ in 1:N_sys]
                ancillas = [QBool(ctx, 0.0) for _ in 1:be.n_ancilla]
                q_re = QBool(ctx, 0.0)
                q_lcu = QBool(ctx, 0.0)

                q_re.θ += π/2
                q_lcu.θ += π/2

                _qsvt_combined_naked!(sys, be, phi_even, phi_odd,
                                      ancillas, q_re, q_lcu)

                _qsvt_combined_naked_adj!(sys, be, phi_even, phi_odd,
                                          ancillas, q_re, q_lcu)

                q_lcu.θ += -π/2
                q_re.θ += -π/2

                success = true
                for a in ancillas
                    if Bool(a); success = false; end
                end
                if Bool(q_re); success = false; end
                if Bool(q_lcu); success = false; end
                if success
                    n_roundtrip_success += 1
                    all_zero = true
                    for s in sys
                        if Bool(s); all_zero = false; end
                    end
                    if all_zero; n_sys_correct += 1; end
                else
                    for s in sys; discard!(s); end
                end
            end
        end

        println("  roundtrip: $n_roundtrip_success/$N_shots ancilla, $n_sys_correct system")
        @test n_roundtrip_success == N_shots
        @test n_sys_correct == N_shots
    end

    # ─────────────────────────────────────────────────────────────────────
    # Test 3: Lifted BE structural properties + single oracle statistics
    # ─────────────────────────────────────────────────────────────────────

    @testset "lifted BE oracle produces e^{-iHt/alpha}/2" begin
        t = 2.0
        N_sys = 2
        d = 7
        H = ising(Val(N_sys), J=1.0, h=0.5)
        al = lambda(H)

        phi_even = qsvt_phases(jacobi_anger_cos_coeffs(t, d); epsilon=1e-4)
        phi_odd = qsvt_phases(jacobi_anger_sin_coeffs(t, d); epsilon=1e-4)
        be = block_encode_lcu(H)

        lifted = _lift_combined_to_be(be, phi_even, phi_odd)

        # Check structural properties
        @test lifted.n_system == N_sys
        @test lifted.n_ancilla == be.n_ancilla + 2
        @test lifted.alpha == 2.0

        # Ground truth: e^{-iHt/alpha}/2 |0>
        H_mat = _pauli_matrix_oaa(H)
        evals, evecs = eigen(H_mat)
        eiHt_half = evecs * Diagonal(exp.(-im .* evals .* t / al) ./ 2) * evecs'
        psi0 = zeros(ComplexF64, 4); psi0[1] = 1.0
        psi_exact = eiHt_half * psi0
        probs_exact = abs2.(psi_exact)
        norm_exact = sum(probs_exact)

        N_shots = 1500
        n_success = 0
        counts = zeros(Int, 4)

        for _ in 1:N_shots
            ctx = EagerContext()
            @context ctx begin
                sys = [QBool(ctx, 0.0) for _ in 1:N_sys]
                ancs = [QBool(ctx, 0.0) for _ in 1:lifted.n_ancilla]
                lifted.oracle!(ancs, sys)
                ok = true
                for a in ancs
                    if Bool(a); ok = false; end
                end
                if ok
                    n_success += 1
                    b1 = Bool(sys[1])
                    b2 = Bool(sys[2])
                    counts[Int(b1) + 2*Int(b2) + 1] += 1
                else
                    for s in sys; discard!(s); end
                end
            end
        end

        println("  lifted BE: $n_success/$N_shots success")
        @test n_success > 30

        if n_success > 30
            probs_lifted = counts ./ n_success
            probs_expected = probs_exact ./ norm_exact
            for i in 1:4
                sigma = sqrt(probs_expected[i] * (1 - probs_expected[i]) / n_success)
                @test abs(probs_lifted[i] - probs_expected[i]) < max(5 * sigma, 0.15)
            end
        end
    end

    # ─────────────────────────────────────────────────────────────────────
    # Test 4: OAA end-to-end: oaa_amplify! produces e^{-iHt/alpha}
    # ─────────────────────────────────────────────────────────────────────

    @testset "oaa_amplify!: e^{-iHt/alpha} on 2-qubit Ising" begin
        t = 2.0
        N_sys = 2
        d = 7
        H = ising(Val(N_sys), J=1.0, h=0.5)
        al = lambda(H)

        phi_even = qsvt_phases(jacobi_anger_cos_coeffs(t, d); epsilon=1e-4)
        phi_odd = qsvt_phases(jacobi_anger_sin_coeffs(t, d); epsilon=1e-4)
        be = block_encode_lcu(H)

        # Ground truth: e^{-iHt/alpha}|0>  (FULL unitary)
        H_mat = _pauli_matrix_oaa(H)
        evals, evecs = eigen(H_mat)
        eiHt = evecs * Diagonal(exp.(-im .* evals .* t / al)) * evecs'
        psi0 = zeros(ComplexF64, 4); psi0[1] = 1.0
        psi_exact = eiHt * psi0
        probs_exact = abs2.(psi_exact)

        N_shots = 1000
        n_success = 0
        counts = zeros(Int, 4)

        for _ in 1:N_shots
            ctx = EagerContext()
            @context ctx begin
                sys = [QBool(ctx, 0.0) for _ in 1:N_sys]
                success = oaa_amplify!(sys, be, phi_even, phi_odd)
                if success
                    n_success += 1
                    b1 = Bool(sys[1])
                    b2 = Bool(sys[2])
                    counts[Int(b1) + 2*Int(b2) + 1] += 1
                else
                    for s in sys; discard!(s); end
                end
            end
        end

        println("  OAA: $n_success/$N_shots success")
        @test n_success > 20

        if n_success > 20
            probs_measured = counts ./ n_success
            for i in 1:4
                sigma = sqrt(probs_exact[i] * (1 - probs_exact[i]) / n_success)
                @test abs(probs_measured[i] - probs_exact[i]) < max(5 * sigma, 0.15)
            end
        end
    end

    # ─────────────────────────────────────────────────────────────────────
    # Test 5: evolve!(QSVT) full pipeline with OAA
    # ─────────────────────────────────────────────────────────────────────

    @testset "evolve!(QSVT): e^{-iHt/alpha} via OAA on 2-qubit Ising" begin
        t = 2.0
        N_sys = 2
        H = ising(Val(N_sys), J=1.0, h=0.5)
        al = lambda(H)
        alg = QSVT(epsilon=1e-3, degree=7)

        # Ground truth: e^{-iHt/alpha}|0>
        H_mat = _pauli_matrix_oaa(H)
        evals, evecs = eigen(H_mat)
        eiHt = evecs * Diagonal(exp.(-im .* evals .* t / al)) * evecs'
        psi0 = zeros(ComplexF64, 4); psi0[1] = 1.0
        psi_exact = eiHt * psi0
        probs_exact = abs2.(psi_exact)

        N_shots = 1000
        n_success = 0
        counts = zeros(Int, 4)

        for _ in 1:N_shots
            ctx = EagerContext()
            @context ctx begin
                sys = [QBool(ctx, 0.0) for _ in 1:N_sys]
                success = evolve!(sys, H, t, alg)
                if success
                    n_success += 1
                    b1 = Bool(sys[1])
                    b2 = Bool(sys[2])
                    counts[Int(b1) + 2*Int(b2) + 1] += 1
                else
                    for s in sys; discard!(s); end
                end
            end
        end

        println("  evolve! OAA: $n_success/$N_shots success")
        @test n_success > 20

        if n_success > 20
            probs_measured = counts ./ n_success
            for i in 1:4
                sigma = sqrt(probs_exact[i] * (1 - probs_exact[i]) / n_success)
                @test abs(probs_measured[i] - probs_exact[i]) < max(5 * sigma, 0.15)
            end
        end
    end

end
