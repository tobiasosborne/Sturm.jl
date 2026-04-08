# End-to-end test: reflection QSVT applies cos(Ht/alpha) to block-encoded H.
#
# Pipeline: jacobi_anger_cos_coeffs -> qsvt_phases -> qsvt_reflect! -> verify
#
# Ref: GSLW (2019), arXiv:1806.01838, Definition 15, Theorem 17, Corollary 18.
#      Laneve (2025), arXiv:2503.03026, Section 2.1, Section 4.3.
#      Berntson, Sunderhauf (2025), CMP 406:161 (completion step).

using Test, Sturm, FFTW
using Sturm: jacobi_anger_cos_coeffs, jacobi_anger_sin_coeffs,
             qsvt_phases, qsvt_reflect!,
             block_encode_lcu, ising, lambda, nqubits
using LinearAlgebra: eigen, Diagonal, kron

# ── Helpers ──

if !@isdefined(_pauli_matrix)
    function _pauli_matrix(H_sturm)
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

@testset "Reflection QSVT" begin

    # ─────────────────────────────────────────────────────────────────────
    # A. qsvt_phases smoke tests
    # ─────────────────────────────────────────────────────────────────────

    @testset "qsvt_phases: cos polynomial returns correct count" begin
        for d in [4, 8, 12]
            c = jacobi_anger_cos_coeffs(1.0, d)
            phi = qsvt_phases(c; epsilon=1e-6)
            @test length(phi) == 2d  # analytic degree = 2d, minus phi_0
        end
    end

    @testset "qsvt_phases: sin polynomial returns correct count" begin
        for d in [5, 9, 13]
            c = jacobi_anger_sin_coeffs(1.0, d)
            phi = qsvt_phases(c; epsilon=1e-6)
            @test length(phi) == 2d
        end
    end

    @testset "jacobi_anger_cos_coeffs: real, even parity" begin
        c = jacobi_anger_cos_coeffs(1.0, 10)
        @test all(isfinite.(c))
        # Even parity: odd-indexed coefficients should be zero
        for k in 1:2:10
            @test abs(c[k+1]) < 1e-15  # c_k = 0 for odd k
        end
    end

    @testset "jacobi_anger_sin_coeffs: real, odd parity" begin
        c = jacobi_anger_sin_coeffs(1.0, 11)
        @test all(isfinite.(c))
        # Odd parity: even-indexed coefficients should be zero
        @test abs(c[1]) < 1e-15  # c_0 = 0
        for k in 2:2:10
            @test abs(c[k+1]) < 1e-15  # c_k = 0 for even k
        end
    end

    @testset "jacobi_anger_cos_coeffs: approximates cos(xt)" begin
        t = 1.5
        d = 20
        c = jacobi_anger_cos_coeffs(t, d)
        c_cx = ComplexF64.(c)
        for x in [-1.0, -0.5, 0.0, 0.5, 1.0]
            approx = real(Sturm.chebyshev_eval(c_cx, x))
            exact = cos(x * t)
            @test abs(approx - exact) < 1e-10
        end
    end

    @testset "jacobi_anger_sin_coeffs: approximates -sin(xt)" begin
        t = 1.5
        d = 21  # odd degree for odd polynomial
        c = jacobi_anger_sin_coeffs(t, d)
        c_cx = ComplexF64.(c)
        for x in [-1.0, -0.5, 0.3, 0.5, 1.0]
            approx = real(Sturm.chebyshev_eval(c_cx, x))
            exact = -sin(x * t)
            @test abs(approx - exact) < 1e-10
        end
    end

    # ─────────────────────────────────────────────────────────────────────
    # B. Reflection QSVT end-to-end: cos(Ht/alpha)|psi>
    # ─────────────────────────────────────────────────────────────────────

    @testset "qsvt_reflect!: cos(Ht/alpha) on 2-qubit Ising" begin
        t = 0.5
        N_sys = 2
        H = ising(Val(N_sys), J=1.0, h=0.5)
        al = lambda(H)
        d = 12  # Chebyshev degree

        # Ground truth: cos(H*t/alpha)|0>
        H_mat = _pauli_matrix(H)
        evals, evecs = eigen(H_mat)
        cos_Ht = evecs * Diagonal(cos.(evals .* t / al)) * evecs'
        psi0 = zeros(ComplexF64, 4); psi0[1] = 1.0
        psi_exact = cos_Ht * psi0
        probs_exact = abs2.(psi_exact)
        norm_exact = sum(probs_exact)  # ||cos(Ht/alpha)|0>||^2

        # Compute QSVT phases
        cos_c = jacobi_anger_cos_coeffs(t, d)
        phi = qsvt_phases(cos_c; epsilon=1e-6)

        # Block encode
        be = block_encode_lcu(H)

        # Run circuit, collect post-selected statistics
        N_shots = 3000
        n_success = 0
        counts = zeros(Int, 4)

        for _ in 1:N_shots
            ctx = EagerContext()
            @context ctx begin
                sys = [QBool(ctx, 0.0) for _ in 1:N_sys]
                success = qsvt_reflect!(sys, be, phi)
                if success
                    n_success += 1
                    b1 = Bool(sys[1])
                    b2 = Bool(sys[2])
                    idx = Int(b1) + 2*Int(b2) + 1
                    counts[idx] += 1
                else
                    for s in sys; discard!(s); end
                end
            end
        end

        # Post-selection normalizes the state
        @test n_success > 30  # should succeed with reasonable probability

        if n_success > 30
            probs_measured = counts ./ n_success
            probs_expected = probs_exact ./ norm_exact  # normalized

            # Statistical comparison with tolerance
            for i in 1:4
                sigma = sqrt(probs_expected[i] * (1 - probs_expected[i]) / n_success)
                @test abs(probs_measured[i] - probs_expected[i]) < max(5 * sigma, 0.08)
            end
        end
    end

end
