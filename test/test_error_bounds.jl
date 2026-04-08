using Test
using Sturm
using Sturm: nqubits, nterms, lambda,
             _pauli_anticommutes, _pauli_product,
             _alpha_comm_naive
using LinearAlgebra: eigen, Diagonal, kron

# Helpers needed for standalone execution (also defined in test_simulation/test_qdrift)
if !@isdefined(_amp)
    _amp(ctx, idx) = Sturm.orkan_state_get(ctx.orkan.raw, idx, 0)
end
if !@isdefined(_state_error)
    function _state_error(ctx, ψ_exact::Vector{ComplexF64})
        dim = length(ψ_exact)
        err = 0.0
        for i in 0:dim-1
            err += abs2(_amp(ctx, i) - ψ_exact[i+1])
        end
        err
    end
end
if !@isdefined(_pauli_matrix)
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
            M = pauli_mats[term.ops[N]]
            for k in (N-1):-1:1
                M = kron(M, pauli_mats[term.ops[k]])
            end
            H_mat .+= term.coeff .* M
        end
        H_mat
    end
end
if !@isdefined(_exact_evolve)
    function _exact_evolve(H_sturm, t::Real)
        H_mat = _pauli_matrix(H_sturm)
        dim = size(H_mat, 1)
        evals, evecs = eigen(H_mat)
        U = evecs * Diagonal(exp.(-im * t .* evals)) * evecs'
        ψ0 = zeros(ComplexF64, dim); ψ0[1] = 1.0
        U * ψ0
    end
end

@testset "Trotter error bounds (Childs et al. 2021)" begin

    # ═════════════════════════════════════════════════════════════════════
    # A. Pauli commutation algebra
    # ═════════════════════════════════════════════════════════════════════

    @testset "Single-qubit anticommutation" begin
        # X,Y anticommute; X,Z anticommute; Y,Z anticommute
        @test _pauli_anticommutes((pauli_X,), (pauli_Y,)) == true
        @test _pauli_anticommutes((pauli_X,), (pauli_Z,)) == true
        @test _pauli_anticommutes((pauli_Y,), (pauli_Z,)) == true
        # Same op commutes; identity commutes with everything
        @test _pauli_anticommutes((pauli_X,), (pauli_X,)) == false
        @test _pauli_anticommutes((pauli_I,), (pauli_X,)) == false
        @test _pauli_anticommutes((pauli_I,), (pauli_I,)) == false
    end

    @testset "Multi-qubit anticommutation" begin
        # XX and YY: anticommute on both positions → even → commute
        @test _pauli_anticommutes((pauli_X, pauli_X), (pauli_Y, pauli_Y)) == false
        # XX and YX: anticommute on pos 1 only → odd → anticommute
        @test _pauli_anticommutes((pauli_X, pauli_X), (pauli_Y, pauli_X)) == true
        # ZZ and XI: anticommute on pos 1, commute on pos 2 → odd → anticommute
        @test _pauli_anticommutes((pauli_Z, pauli_Z), (pauli_X, pauli_I)) == true
        # ZZ and IX: commute on pos 1, anticommute on pos 2 → odd → anticommute
        @test _pauli_anticommutes((pauli_Z, pauli_Z), (pauli_I, pauli_X)) == true
        # ZI and IZ: commute (disjoint support)
        @test _pauli_anticommutes((pauli_Z, pauli_I), (pauli_I, pauli_Z)) == false
    end

    @testset "Pauli product (ignoring phase)" begin
        # X·Y = iZ → product Pauli = Z
        @test _pauli_product((pauli_X,), (pauli_Y,)) == (pauli_Z,)
        # Y·Z = iX
        @test _pauli_product((pauli_Y,), (pauli_Z,)) == (pauli_X,)
        # X·X = I
        @test _pauli_product((pauli_X,), (pauli_X,)) == (pauli_I,)
        # I·X = X
        @test _pauli_product((pauli_I,), (pauli_X,)) == (pauli_X,)
        # Multi-qubit: (X⊗Z)·(Y⊗X) = (X·Y)⊗(Z·X) = (Z)⊗(Y)
        @test _pauli_product((pauli_X, pauli_Z), (pauli_Y, pauli_X)) == (pauli_Z, pauli_Y)
    end

    # ═════════════════════════════════════════════════════════════════════
    # B. Commutator norm: exact values for known Hamiltonians
    # ═════════════════════════════════════════════════════════════════════

    @testset "Commuting Hamiltonian: α̃_comm = 0" begin
        # H = Z₁ + Z₂: all terms commute
        H = hamiltonian(pauli_term(1.0, :Z, :I), pauli_term(1.0, :I, :Z))
        @test alpha_comm(H, 1) == 0.0
        @test alpha_comm(H, 2) == 0.0
    end

    @testset "Two-term H: α̃_comm by hand" begin
        # H = Z + X (single qubit). Z and X anticommute.
        # p=1: α̃ = Σ_{γ1,γ2} 2|h1||h2|·[anticommute?]
        #     = 2·(1·1 + 1·1) = 4  (pairs (Z,X) and (X,Z) both anticommute)
        # Same op pairs (Z,Z) and (X,X) commute → contribute 0.
        H = hamiltonian(pauli_term(1.0, :Z), pauli_term(1.0, :X))
        @test alpha_comm(H, 1) ≈ 4.0

        # p=2: 3-fold nested. For each (γ1,γ2) that anticommutes:
        # product P_C, then check (γ3, P_C).
        # Pairs that anticommute: (Z,X) and (X,Z), each gives P_C = Y.
        # Then for γ3: Z anticommutes with Y ✓, X anticommutes with Y ✓
        # Inner coeff = 4·|h1||h2||h3|. Count valid triples:
        # (Z,X,Z), (Z,X,X), (X,Z,Z), (X,Z,X) → 4 triples, each contributes 4·1·1·1=4
        # Total: 4·4 = 16
        @test alpha_comm(H, 2) ≈ 16.0
    end

    @testset "α̃_comm ≤ naive bound" begin
        # The exact commutator norm should always be ≤ the naive bound
        for H in [
            ising(Val(4), J=1.0, h=0.5),
            heisenberg(Val(3), Jx=1.0, Jy=1.0, Jz=1.0),
            hamiltonian(pauli_term(2.0, :Z, :Z), pauli_term(0.3, :X, :I), pauli_term(0.1, :Y, :Y)),
        ]
            for p in [1, 2]
                @test alpha_comm(H, p) ≤ _alpha_comm_naive(H, p) + 1e-10
            end
        end
    end

    @testset "Ising α̃_comm < λ^{p+1} (commutator advantage)" begin
        # Ising model: ZZ terms commute with each other, only anticommute
        # with X terms on shared qubits. So α̃_comm << λ^{p+1}.
        for N in [4, 6, 8]
            H = ising(Val(N), J=1.0, h=0.5)
            λ = lambda(H)
            α1 = alpha_comm(H, 1)
            @test α1 < λ^2   # strict improvement
        end
    end

    # ═════════════════════════════════════════════════════════════════════
    # C. Error bound functions
    # ═════════════════════════════════════════════════════════════════════

    @testset "trotter_error: comm ≤ naive" begin
        H = ising(Val(4), J=1.0, h=0.5)
        t = 0.5
        for p in [1, 2]
            e_naive = trotter_error(H, t, p, method=:naive)
            e_comm = trotter_error(H, t, p, method=:comm)
            @test e_comm ≤ e_naive + 1e-10
        end
    end

    @testset "trotter_steps: comm ≤ naive" begin
        H = ising(Val(4), J=1.0, h=0.5)
        for (t, ε) in [(1.0, 0.01), (0.5, 0.001), (2.0, 0.1)]
            for p in [1, 2]
                r_naive = trotter_steps(H, t, ε, p, method=:naive)
                r_comm = trotter_steps(H, t, ε, p, method=:comm)
                @test r_comm ≤ r_naive
            end
        end
    end

    @testset "trotter_steps increases with t, decreases with ε" begin
        H = ising(Val(4), J=1.0, h=0.5)
        # More time → more steps
        @test trotter_steps(H, 2.0, 0.01, 2) > trotter_steps(H, 1.0, 0.01, 2)
        # Tighter error → more steps
        @test trotter_steps(H, 1.0, 0.001, 2) > trotter_steps(H, 1.0, 0.01, 2)
    end

    @testset "Edge cases" begin
        H = hamiltonian(pauli_term(1.0, :X))
        @test trotter_error(H, 0.0, 1) == 0.0
        @test trotter_steps(H, 0.0, 0.01, 1) == 1
        @test_throws ErrorException trotter_steps(H, 1.0, 0.0, 1)
        @test_throws ErrorException trotter_steps(H, 1.0, -0.1, 1)
        @test_throws ErrorException trotter_error(H, 1.0, 0)
    end

    # ═════════════════════════════════════════════════════════════════════
    # D. Numerical validation: predicted steps actually achieve ε
    # ═════════════════════════════════════════════════════════════════════
    # Use matrix ground truth to verify that the predicted number of
    # Trotter steps actually achieves the target error.

    @testset "Predicted steps achieve target error: N=$N" for N in [2, 4, 6]
        H = ising(Val(N), J=1.0, h=0.5)
        t = 0.5
        ε = 0.01

        ψ_exact = _exact_evolve(H, t)

        for (p, Alg) in [(1, Trotter1), (2, Trotter2)]
            # Get predicted steps (naive — conservative, should always work)
            r = trotter_steps(H, t, ε, p, method=:naive)
            # Ensure at least some steps
            r = max(r, 1)

            ctx = EagerContext()
            qs = [QBool(ctx, 0) for _ in 1:N]
            evolve!(qs, H, t, Alg(steps=r))
            err = sqrt(_state_error(ctx, ψ_exact))  # ℓ₂ error, not squared
            for q in qs; discard!(q); end

            # The naive bound is conservative (O() constant ≥ 1 in practice),
            # so actual error should be well below ε
            @test err < ε
        end
    end

    @testset "Commutator steps also achieve target: N=$N" for N in [2, 4, 6]
        H = ising(Val(N), J=1.0, h=0.5)
        t = 0.5
        ε = 0.01

        ψ_exact = _exact_evolve(H, t)

        for (p, Alg) in [(1, Trotter1), (2, Trotter2)]
            r = trotter_steps(H, t, ε, p, method=:comm)
            r = max(r, 1)

            ctx = EagerContext()
            qs = [QBool(ctx, 0) for _ in 1:N]
            evolve!(qs, H, t, Alg(steps=r))
            err = sqrt(_state_error(ctx, ψ_exact))
            for q in qs; discard!(q); end

            # Commutator bound is tighter but still conservative
            @test err < ε
        end
    end

    # ═════════════════════════════════════════════════════════════════════
    # E. Scaling: commutator advantage grows with system size
    # ═════════════════════════════════════════════════════════════════════
    # For Ising chain, α̃_comm grows as O(N) while λ^2 grows as O(N^2).
    # So the ratio α̃_comm/λ^2 → 0 as N → ∞.

    @testset "Commutator advantage scales with N" begin
        ratios = Float64[]
        for N in [4, 8, 16, 32]
            H = ising(Val(N), J=1.0, h=0.5)
            λ = lambda(H)
            α = alpha_comm(H, 1)
            push!(ratios, α / λ^2)
        end
        # Ratio should decrease with N
        @test ratios[2] < ratios[1]
        @test ratios[3] < ratios[2]
        @test ratios[4] < ratios[3]
    end

    # ═════════════════════════════════════════════════════════════════════
    # F. Heisenberg model
    # ═════════════════════════════════════════════════════════════════════

    @testset "Heisenberg commutator norm" begin
        H = heisenberg(Val(4), Jx=1.0, Jy=1.0, Jz=1.0)
        λ = lambda(H)
        α1 = alpha_comm(H, 1)
        # Heisenberg has more anticommuting pairs than Ising
        # but still α̃ < λ²
        @test α1 > 0
        @test α1 < λ^2
        # Steps: comm should be ≤ naive
        r_n = trotter_steps(H, 1.0, 0.01, 2, method=:naive)
        r_c = trotter_steps(H, 1.0, 0.01, 2, method=:comm)
        @test r_c ≤ r_n
    end

end
