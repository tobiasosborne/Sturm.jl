using Test
using Sturm
using Sturm: nqubits, nterms, lambda
using LinearAlgebra: eigen, Diagonal, kron

# Helper: read Orkan amplitude at basis state index (0-based)
_amp(ctx, idx) = Sturm.orkan_state_get(ctx.orkan.raw, idx, 0)

# Helper: read all probabilities from Orkan state
_probs(ctx) = Sturm.probabilities(ctx.orkan)

@testset "Hamiltonian simulation" begin

    # ═════════════════════════════════════════════════════════════════════
    # A. Type construction and algebra
    # ═════════════════════════════════════════════════════════════════════

    @testset "PauliTerm construction" begin
        t = pauli_term(0.5, :X, :Z)
        @test t.coeff == 0.5
        @test t.ops == (pauli_X, pauli_Z)
        @test_throws ErrorException pauli_term(1.0, :X, :Q)
    end

    @testset "PauliHamiltonian properties" begin
        H = hamiltonian(pauli_term(1.0, :Z, :Z), pauli_term(0.5, :X, :I), pauli_term(0.5, :I, :X))
        @test nqubits(H) == 2
        @test nterms(H) == 3
        @test lambda(H) == 2.0
    end

    @testset "Ising model" begin
        H = ising(Val(3), J=1.0, h=0.5)
        @test nqubits(H) == 3
        @test nterms(H) == 5   # 2 ZZ + 3 X
        @test lambda(H) == 3.5  # 2×1.0 + 3×0.5
    end

    @testset "Heisenberg model" begin
        H = heisenberg(Val(2), Jx=1.0, Jy=1.0, Jz=1.0)
        @test nqubits(H) == 2
        @test nterms(H) == 3  # XX + YY + ZZ for 1 bond
        @test lambda(H) == 3.0
    end

    @testset "Validation" begin
        @test_throws ErrorException PauliHamiltonian{2}(PauliTerm{2}[])
        @test_throws ErrorException Trotter1(steps=0)
        @test_throws ErrorException Suzuki(order=2)
        @test_throws ErrorException Suzuki(order=3)
    end

    # ═════════════════════════════════════════════════════════════════════
    # B. pauli_exp! — Orkan amplitude verification (exact state vectors)
    # ═════════════════════════════════════════════════════════════════════
    # These tests read Orkan amplitudes directly and compare against
    # analytically computed state vectors. No sampling noise.

    @testset "exp(-iθZ)|0⟩ = e^{-iθ}|0⟩ (exact amplitudes)" begin
        # exp(-iθZ) = Rz(2θ) = diag(e^{-iθ}, e^{iθ})
        # Applied to |0⟩: amplitude[0] = e^{-iθ}, amplitude[1] = 0
        θ = 0.3
        ctx = EagerContext()
        q = QBool(ctx, 0)
        pauli_exp!([q], pauli_term(1.0, :Z), θ)
        @test abs(_amp(ctx, 0) - exp(-im * θ)) < 1e-12
        @test abs(_amp(ctx, 1)) < 1e-12
        discard!(q)
    end

    @testset "exp(-iθX)|0⟩ = cos(θ)|0⟩ - i·sin(θ)|1⟩ (exact)" begin
        # exp(-iθX) = cos(θ)I - i·sin(θ)X = Rx(2θ)
        θ = π/6
        ctx = EagerContext()
        q = QBool(ctx, 0)
        pauli_exp!([q], pauli_term(1.0, :X), θ)
        @test abs(_amp(ctx, 0) - cos(θ)) < 1e-12
        @test abs(_amp(ctx, 1) - (-im * sin(θ))) < 1e-12
        discard!(q)
    end

    @testset "exp(-iθY)|0⟩ = cos(θ)|0⟩ + sin(θ)|1⟩ (exact)" begin
        # exp(-iθY) = cos(θ)I - i·sin(θ)Y = Ry(2θ)
        # Ry(2θ)|0⟩ = cos(θ)|0⟩ + sin(θ)|1⟩  (real amplitudes!)
        θ = π/5
        ctx = EagerContext()
        q = QBool(ctx, 0)
        pauli_exp!([q], pauli_term(1.0, :Y), θ)
        @test abs(_amp(ctx, 0) - cos(θ)) < 1e-12
        @test abs(_amp(ctx, 1) - sin(θ)) < 1e-12
        discard!(q)
    end

    @testset "exp(-iπ/2 X)|0⟩ = -i|1⟩ (bit flip)" begin
        ctx = EagerContext()
        q = QBool(ctx, 0)
        pauli_exp!([q], pauli_term(1.0, :X), π/2)
        @test abs(_amp(ctx, 0)) < 1e-12
        @test abs(_amp(ctx, 1) - (-im)) < 1e-12
        discard!(q)
    end

    @testset "exp(-iπ/2 Y)|0⟩ = |1⟩" begin
        # exp(-iπ/2 Y) = -iY. (-iY)|0⟩ = -i(i|1⟩) = |1⟩
        ctx = EagerContext()
        q = QBool(ctx, 0)
        pauli_exp!([q], pauli_term(1.0, :Y), π/2)
        @test abs(_amp(ctx, 0)) < 1e-12
        @test abs(abs(_amp(ctx, 1)) - 1.0) < 1e-12
        discard!(q)
    end

    @testset "Identity Pauli exp is no-op" begin
        ctx = EagerContext()
        q = QBool(ctx, 0)
        pauli_exp!([q], pauli_term(1.0, :I), 1.7)
        @test abs(_amp(ctx, 0) - 1.0) < 1e-12  # still |0⟩
        discard!(q)
    end

    @testset "exp(-iθ ZZ)|00⟩ = e^{-iθ}|00⟩ (exact)" begin
        # ZZ|00⟩ = (+1)(+1)|00⟩ = |00⟩, eigenvalue +1
        # exp(-iθ ZZ)|00⟩ = e^{-iθ}|00⟩
        θ = 0.4
        ctx = EagerContext()
        q1 = QBool(ctx, 0)
        q2 = QBool(ctx, 0)
        pauli_exp!([q1, q2], pauli_term(1.0, :Z, :Z), θ)
        probs = _probs(ctx)
        @test abs(probs[1] - 1.0) < 1e-12  # |00⟩ has all probability
        @test abs(_amp(ctx, 0) - exp(-im * θ)) < 1e-12
        discard!(q1); discard!(q2)
    end

    @testset "exp(-iθ XX)|00⟩ = cos(θ)|00⟩ - i·sin(θ)|11⟩ (exact)" begin
        # XX|00⟩ = X|0⟩⊗X|0⟩ = |1⟩⊗|1⟩ = |11⟩.
        # XX² = I, eigenvalue on {|00⟩,|11⟩} subspace is ±1.
        # exp(-iθ XX) in {|00⟩,|11⟩}: cos(θ)I - i·sin(θ)·σ_x(sub)
        # Applied to |00⟩: cos(θ)|00⟩ - i·sin(θ)|11⟩
        θ = π/7
        ctx = EagerContext()
        q1 = QBool(ctx, 0)
        q2 = QBool(ctx, 0)
        pauli_exp!([q1, q2], pauli_term(1.0, :X, :X), θ)
        # Orkan basis: index 0=|00⟩, 1=|01⟩, 2=|10⟩, 3=|11⟩ (LSB=q0)
        @test abs(_amp(ctx, 0) - cos(θ)) < 1e-12        # |00⟩
        @test abs(_amp(ctx, 1)) < 1e-12                   # |01⟩ = 0
        @test abs(_amp(ctx, 2)) < 1e-12                   # |10⟩ = 0
        @test abs(_amp(ctx, 3) - (-im * sin(θ))) < 1e-12  # |11⟩
        discard!(q1); discard!(q2)
    end

    @testset "exp(-iθ YY)|00⟩ = cos(θ)|00⟩ + i·sin(θ)|11⟩ (exact)" begin
        # YY|00⟩ = Y|0⟩⊗Y|0⟩ = (i|1⟩)(i|1⟩) = -|11⟩
        # In {|00⟩,|11⟩} subspace: YY acts as [[0,-1],[-1,0]] = -σ_x(sub)
        # exp(-iθ(-σ_x)) = cos(θ)I + i·sin(θ)·σ_x(sub)
        # Applied to |00⟩: cos(θ)|00⟩ + i·sin(θ)·(-|11⟩) ... wait.
        #
        # Let me be precise. YY as 4×4:
        #   ⟨00|YY|00⟩ = ⟨0|Y|0⟩² = 0 (Y is off-diagonal)
        #   ⟨11|YY|00⟩ = ⟨1|Y|0⟩² = (i)² = -1
        #   ⟨00|YY|11⟩ = ⟨0|Y|1⟩² = (-i)² = -1
        #   ⟨11|YY|11⟩ = ⟨1|Y|1⟩² = 0
        # So YY restricted to {|00⟩,|11⟩} = [[0,-1],[-1,0]] = -σ_x(sub)
        #
        # exp(-iθ YY) on |00⟩ = exp(iθ σ_x(sub))|00⟩
        #   = cos(θ)|00⟩ + i·sin(θ)|11⟩
        θ = π/7
        ctx = EagerContext()
        q1 = QBool(ctx, 0)
        q2 = QBool(ctx, 0)
        pauli_exp!([q1, q2], pauli_term(1.0, :Y, :Y), θ)
        @test abs(_amp(ctx, 0) - cos(θ)) < 1e-11        # |00⟩
        @test abs(_amp(ctx, 1)) < 1e-11                   # |01⟩
        @test abs(_amp(ctx, 2)) < 1e-11                   # |10⟩
        @test abs(_amp(ctx, 3) - (im * sin(θ))) < 1e-11   # |11⟩
        discard!(q1); discard!(q2)
    end

    @testset "exp(-iθ XZ)|00⟩ = cos(θ)|00⟩ - i·sin(θ)|10⟩ (exact)" begin
        # XZ|00⟩ = X|0⟩⊗Z|0⟩ = |1⟩⊗|0⟩ = |10⟩
        # In {|00⟩,|10⟩}: XZ acts as σ_x(sub)
        # exp(-iθ σ_x)|00⟩ = cos(θ)|00⟩ - i·sin(θ)|10⟩
        θ = π/8
        ctx = EagerContext()
        q1 = QBool(ctx, 0)   # Orkan qubit 0 (LSB)
        q2 = QBool(ctx, 0)   # Orkan qubit 1
        pauli_exp!([q1, q2], pauli_term(1.0, :X, :Z), θ)
        # |10⟩ in term notation: q1=1,q2=0 → Orkan: qubit0=1,qubit1=0 → index 1
        @test abs(_amp(ctx, 0) - cos(θ)) < 1e-12        # |00⟩
        @test abs(_amp(ctx, 1) - (-im * sin(θ))) < 1e-12  # |10⟩ = index 1
        @test abs(_amp(ctx, 2)) < 1e-12                   # |01⟩
        @test abs(_amp(ctx, 3)) < 1e-12                   # |11⟩
        discard!(q1); discard!(q2)
    end

    @testset "3-qubit exp(-iθ XYZ)|000⟩ (exact)" begin
        # XYZ|000⟩ = X|0⟩⊗Y|0⟩⊗Z|0⟩ = |1⟩⊗(i|1⟩)⊗|0⟩ = i|110⟩
        # exp(-iθ XYZ)|000⟩ = cos(θ)|000⟩ - i·sin(θ)·(i|110⟩)
        #                    = cos(θ)|000⟩ + sin(θ)|110⟩
        #
        # Orkan LSB: term positions [1,2,3] → Orkan qubits [0,1,2]
        # |110⟩ in term notation: q1=1,q2=1,q3=0 → qubit0=1,qubit1=1,qubit2=0
        # Orkan index = 1 + 2 + 0 = 3
        θ = π/9
        ctx = EagerContext()
        q1 = QBool(ctx, 0)
        q2 = QBool(ctx, 0)
        q3 = QBool(ctx, 0)
        pauli_exp!([q1, q2, q3], pauli_term(1.0, :X, :Y, :Z), θ)
        @test abs(_amp(ctx, 0) - cos(θ)) < 1e-11       # |000⟩
        @test abs(_amp(ctx, 3) - sin(θ)) < 1e-11        # |110⟩ = index 3
        # All other amplitudes zero
        for i in [1,2,4,5,6,7]
            @test abs(_amp(ctx, i)) < 1e-11
        end
        discard!(q1); discard!(q2); discard!(q3)
    end

    # ═════════════════════════════════════════════════════════════════════
    # C. Linear algebra ground truth: matrix exp vs Orkan
    # ═════════════════════════════════════════════════════════════════════
    # Compute exp(-iHt) as a 4×4 matrix using Taylor series, apply to |00⟩,
    # then compare against Orkan's state vector after Trotter evolution.

    @testset "Exact vs Trotter: 2-qubit Ising (matrix ground truth)" begin
        # H = Z₁Z₂ + 0.3 X₁  (2-qubit, non-commuting)
        # Build H as a 4×4 matrix and compute exp(-iHt) exactly.
        #
        # Pauli matrices:
        I2 = ComplexF64[1 0; 0 1]
        σx = ComplexF64[0 1; 1 0]
        σz = ComplexF64[1 0; 0 -1]

        # Orkan LSB convention: kron(qubit1_op, qubit0_op)
        # PauliTerm position 1 → Orkan qubit 0 (LSB) → second arg of kron
        # PauliTerm position 2 → Orkan qubit 1 (MSB) → first arg of kron
        H_zz = kron(σz, σz)           # symmetric, order doesn't matter
        H_xi = kron(I2, σx)           # X on qubit 0 (LSB), I on qubit 1
        H_mat = H_zz + 0.3 * H_xi

        t = 0.3

        # Exact exp(-iHt) via eigendecomposition
        evals, evecs = eigen(H_mat)
        U_exact = evecs * Diagonal(exp.(-im * t .* evals)) * evecs'
        ψ_exact = U_exact * ComplexF64[1, 0, 0, 0]  # apply to |00⟩

        # Sturm Trotter2 with many steps (should converge to exact)
        H_sturm = hamiltonian(pauli_term(1.0, :Z, :Z), pauli_term(0.3, :X, :I))
        ctx = EagerContext()
        q1 = QBool(ctx, 0)
        q2 = QBool(ctx, 0)
        evolve!([q1, q2], H_sturm, t, Trotter2(steps=100))

        # Compare amplitudes (should be close to exact)
        for i in 0:3
            @test abs(_amp(ctx, i) - ψ_exact[i+1]) < 1e-6
        end
        discard!(q1); discard!(q2)

        # Also verify Trotter1 converges (less precise)
        ctx2 = EagerContext()
        q1b = QBool(ctx2, 0)
        q2b = QBool(ctx2, 0)
        evolve!([q1b, q2b], H_sturm, t, Trotter1(steps=100))
        # Trotter1 error is O(λ²t²/r) ≈ O(1.3²·0.09/100) ≈ 1.5e-3
        for i in 0:3
            @test abs(_amp(ctx2, i) - ψ_exact[i+1]) < 1e-3
        end
        discard!(q1b); discard!(q2b)
    end

    @testset "Trotter order convergence: error(T2) < error(T1)" begin
        # Same Hamiltonian, fixed step count.
        # Second-order should be more accurate than first-order.
        I2 = ComplexF64[1 0; 0 1]
        σx = ComplexF64[0 1; 1 0]
        σz = ComplexF64[1 0; 0 -1]
        # Orkan LSB: kron(qubit1_op, qubit0_op)
        H_mat = kron(σz, σz) + 0.5 * kron(I2, σx) + 0.5 * kron(σx, I2)
        t = 0.5
        evals, evecs = eigen(H_mat)
        U_exact = evecs * Diagonal(exp.(-im * t .* evals)) * evecs'
        ψ_exact = U_exact * ComplexF64[1, 0, 0, 0]

        H_sturm = hamiltonian(pauli_term(1.0, :Z, :Z), pauli_term(0.5, :X, :I), pauli_term(0.5, :I, :X))
        steps = 5  # modest step count to see the difference

        # Trotter1
        ctx1 = EagerContext()
        q1a = QBool(ctx1, 0); q2a = QBool(ctx1, 0)
        evolve!([q1a, q2a], H_sturm, t, Trotter1(steps=steps))
        err_t1 = sum(abs2(_amp(ctx1, i) - ψ_exact[i+1]) for i in 0:3)
        discard!(q1a); discard!(q2a)

        # Trotter2
        ctx2 = EagerContext()
        q1b = QBool(ctx2, 0); q2b = QBool(ctx2, 0)
        evolve!([q1b, q2b], H_sturm, t, Trotter2(steps=steps))
        err_t2 = sum(abs2(_amp(ctx2, i) - ψ_exact[i+1]) for i in 0:3)
        discard!(q1b); discard!(q2b)

        @test err_t2 < err_t1  # order 2 should be strictly better
    end

    @testset "Suzuki order-4 convergence" begin
        # Same test but Suzuki-4 should beat Trotter2 at same step count
        I2 = ComplexF64[1 0; 0 1]
        σx = ComplexF64[0 1; 1 0]
        σz = ComplexF64[1 0; 0 -1]
        H_mat = kron(σz, σz) + 0.5 * kron(I2, σx) + 0.5 * kron(σx, I2)
        t = 0.5
        evals, evecs = eigen(H_mat)
        U_exact = evecs * Diagonal(exp.(-im * t .* evals)) * evecs'
        ψ_exact = U_exact * ComplexF64[1, 0, 0, 0]

        H_sturm = hamiltonian(pauli_term(1.0, :Z, :Z), pauli_term(0.5, :X, :I), pauli_term(0.5, :I, :X))

        # Trotter2 with 3 steps
        ctx2 = EagerContext()
        q1a = QBool(ctx2, 0); q2a = QBool(ctx2, 0)
        evolve!([q1a, q2a], H_sturm, t, Trotter2(steps=3))
        err_t2 = sum(abs2(_amp(ctx2, i) - ψ_exact[i+1]) for i in 0:3)
        discard!(q1a); discard!(q2a)

        # Suzuki-4 with 3 steps
        ctx4 = EagerContext()
        q1b = QBool(ctx4, 0); q2b = QBool(ctx4, 0)
        evolve!([q1b, q2b], H_sturm, t, Suzuki(order=4, steps=3))
        err_s4 = sum(abs2(_amp(ctx4, i) - ψ_exact[i+1]) for i in 0:3)
        discard!(q1b); discard!(q2b)

        @test err_s4 < err_t2  # order 4 beats order 2
    end

    # ═════════════════════════════════════════════════════════════════════
    # D. DAG emit: TracingContext captures the circuit
    # ═════════════════════════════════════════════════════════════════════

    @testset "pauli_exp! traces into DAG correctly" begin
        ch = trace(1) do q
            pauli_exp!([q], pauli_term(1.0, :X), 0.3)
            (q,)
        end
        @test n_inputs(ch) == 1
        @test n_outputs(ch) == 1
        # The DAG should contain Ry and Rz nodes for basis change + rotation
        # X basis change = Ry(-π/2), then Rz(0.6), then Ry(π/2)
        @test length(ch.dag) >= 3
    end

    @testset "Trotter evolution traces into Channel" begin
        H = hamiltonian(pauli_term(1.0, :Z, :Z), pauli_term(0.5, :X, :I))
        ch = trace(2) do q1, q2
            evolve!([q1, q2], H, 0.1, Trotter2(steps=2))
            (q1, q2)
        end
        @test n_inputs(ch) == 2
        @test n_outputs(ch) == 2
        # The channel should have many nodes (multiple Trotter steps)
        @test length(ch.dag) > 10
    end

    @testset "OpenQASM export from simulation channel" begin
        H = hamiltonian(pauli_term(1.0, :Z))
        ch = trace(1) do q
            evolve!([q], H, 0.5, Trotter1(steps=1))
            (q,)
        end
        qasm = to_openqasm(ch)
        @test occursin("OPENQASM 3.0", qasm)
        @test occursin("rz(", qasm)
    end

    # ═════════════════════════════════════════════════════════════════════
    # E. Suzuki recursion coefficients
    # ═════════════════════════════════════════════════════════════════════

    @testset "Suzuki p_k values" begin
        p2 = Sturm._suzuki_p(2)
        @test abs(p2 - 1.0 / (4.0 - 4.0^(1/3))) < 1e-14
        # Time conservation: 4p + (1-4p) = 1
        for k in 2:5
            pk = Sturm._suzuki_p(k)
            @test abs(4pk + (1 - 4pk) - 1.0) < 1e-14
        end
    end

    # ═════════════════════════════════════════════════════════════════════
    # F. Edge cases
    # ═════════════════════════════════════════════════════════════════════

    @testset "Zero time is identity" begin
        ctx = EagerContext()
        q = QBool(ctx, 0)
        evolve!([q], hamiltonian(pauli_term(1.0, :X)), 0.0, Trotter1(steps=1))
        @test abs(_amp(ctx, 0) - 1.0) < 1e-12
        discard!(q)
    end

    @testset "Single-term Hamiltonian: Trotter is exact (1 step)" begin
        # For a single term, there is no splitting error.
        θ = 0.7
        ctx = EagerContext()
        q = QBool(ctx, 0)
        evolve!([q], hamiltonian(pauli_term(1.0, :X)), θ, Trotter1(steps=1))
        @test abs(_amp(ctx, 0) - cos(θ)) < 1e-12
        @test abs(_amp(ctx, 1) - (-im * sin(θ))) < 1e-12
        discard!(q)
    end

    @testset "Commuting Hamiltonian: Trotter is exact" begin
        # H = Z₁ + Z₂ (commuting). Trotter is exact with 1 step.
        # exp(-it(Z₁+Z₂))|00⟩ = exp(-itZ₁)|0⟩ ⊗ exp(-itZ₂)|0⟩ = e^{-2it}|00⟩
        t = 0.4
        ctx = EagerContext()
        q1 = QBool(ctx, 0)
        q2 = QBool(ctx, 0)
        H = hamiltonian(pauli_term(1.0, :Z, :I), pauli_term(1.0, :I, :Z))
        evolve!([q1, q2], H, t, Trotter1(steps=1))
        @test abs(_amp(ctx, 0) - exp(-2im * t)) < 1e-12
        discard!(q1); discard!(q2)
    end

    @testset "evolve! on QInt register returns register" begin
        @context EagerContext() begin
            H = hamiltonian(pauli_term(1.0, :Z))
            q = QInt{1}(0)
            result = evolve!(q, H, 0.1, Trotter1(steps=1))
            @test result === q
            discard!(q)
        end
    end

    @testset "qubit count mismatch errors" begin
        @context EagerContext() begin
            q = QBool(0)
            @test_throws ErrorException pauli_exp!([q], pauli_term(1.0, :X, :Z), 0.1)
            discard!(q)
        end
    end

    # ═════════════════════════════════════════════════════════════════════
    # G. Review-driven tests (from code review C findings)
    # ═════════════════════════════════════════════════════════════════════

    @testset "Negative coefficient: exp(-iθ(-Z))|0⟩ = e^{+iθ}|0⟩" begin
        # h = -1.0, so angle = 2θ·(-1) = -2θ. Rz(-2θ)|0⟩ = e^{+iθ}|0⟩
        θ = 0.3
        ctx = EagerContext()
        q = QBool(ctx, 0)
        pauli_exp!([q], pauli_term(-1.0, :Z), θ)
        @test abs(_amp(ctx, 0) - exp(+im * θ)) < 1e-12
        @test abs(_amp(ctx, 1)) < 1e-12
        discard!(q)
    end

    @testset "Negative coefficient: exp(-iθ(-X))|0⟩ = cos(θ)|0⟩ + i·sin(θ)|1⟩" begin
        # exp(-iθ(-X)) = exp(+iθX) = cos(θ)I + i·sin(θ)X
        # Applied to |0⟩: cos(θ)|0⟩ + i·sin(θ)|1⟩
        θ = π/7
        ctx = EagerContext()
        q = QBool(ctx, 0)
        pauli_exp!([q], pauli_term(-1.0, :X), θ)
        @test abs(_amp(ctx, 0) - cos(θ)) < 1e-12
        @test abs(_amp(ctx, 1) - (im * sin(θ))) < 1e-12
        discard!(q)
    end

    @testset "Suzuki order-6 convergence beats order-4" begin
        I2 = ComplexF64[1 0; 0 1]
        σx = ComplexF64[0 1; 1 0]
        σz = ComplexF64[1 0; 0 -1]
        H_mat = kron(σz, σz) + 0.5 * kron(I2, σx) + 0.5 * kron(σx, I2)
        t = 0.5
        evals, evecs = eigen(H_mat)
        U_exact = evecs * Diagonal(exp.(-im * t .* evals)) * evecs'
        ψ_exact = U_exact * ComplexF64[1, 0, 0, 0]
        H_sturm = hamiltonian(pauli_term(1.0, :Z, :Z), pauli_term(0.5, :X, :I), pauli_term(0.5, :I, :X))
        steps = 3

        ctx4 = EagerContext()
        q1a = QBool(ctx4, 0); q2a = QBool(ctx4, 0)
        evolve!([q1a, q2a], H_sturm, t, Suzuki(order=4, steps=steps))
        err_s4 = sum(abs2(_amp(ctx4, i) - ψ_exact[i+1]) for i in 0:3)
        discard!(q1a); discard!(q2a)

        ctx6 = EagerContext()
        q1b = QBool(ctx6, 0); q2b = QBool(ctx6, 0)
        evolve!([q1b, q2b], H_sturm, t, Suzuki(order=6, steps=steps))
        err_s6 = sum(abs2(_amp(ctx6, i) - ψ_exact[i+1]) for i in 0:3)
        discard!(q1b); discard!(q2b)

        @test err_s6 < err_s4  # order 6 beats order 4
    end

    @testset "Trotter1 == Trotter2 on single-term Hamiltonian" begin
        # Single term: no splitting error for either order
        θ = 0.7
        H = hamiltonian(pauli_term(1.0, :X))

        ctx1 = EagerContext()
        q1 = QBool(ctx1, 0)
        evolve!([q1], H, θ, Trotter1(steps=1))
        amp1 = [_amp(ctx1, i) for i in 0:1]
        discard!(q1)

        ctx2 = EagerContext()
        q2 = QBool(ctx2, 0)
        evolve!([q2], H, θ, Trotter2(steps=1))
        amp2 = [_amp(ctx2, i) for i in 0:1]
        discard!(q2)

        @test abs(amp1[1] - amp2[1]) < 1e-12
        @test abs(amp1[2] - amp2[2]) < 1e-12
    end

    @testset "evolve! on QInt verifies state correctness" begin
        # exp(-i 0.3 X)|0⟩ = cos(0.3)|0⟩ - i·sin(0.3)|1⟩
        θ = 0.3
        ctx = EagerContext()
        Sturm.task_local_storage(:sturm_context, ctx) do
            H = hamiltonian(pauli_term(1.0, :X))
            q = QInt{1}(0)
            evolve!(q, H, θ, Trotter1(steps=1))
            @test abs(_amp(ctx, 0) - cos(θ)) < 1e-12
            @test abs(_amp(ctx, 1) - (-im * sin(θ))) < 1e-12
            discard!(q)
        end
    end

    @testset "evolve! rejects negative time" begin
        @context EagerContext() begin
            q = QBool(0)
            @test_throws ErrorException evolve!([q], hamiltonian(pauli_term(1.0, :X)), -0.1, Trotter1(steps=1))
            discard!(q)
        end
    end

    @testset "DensityMatrixContext + pauli_exp! works" begin
        # Same physics as EagerContext: exp(-iθX)|0⟩ = cos(θ)|0⟩ - i·sin(θ)|1⟩
        # But exercising the density matrix code path (different apply_ry!/rz!/cx!)
        θ = π/6
        @context DensityMatrixContext() begin
            q = QBool(0)
            pauli_exp!([q], pauli_term(1.0, :X), θ)
            # Measure statistically (DensityMatrixContext measure! differs from Eager)
            # P(|1⟩) = sin²(π/6) = 0.25
            count = 0
            N_trials = 2000
        end
        # DensityMatrixContext doesn't support reading amplitudes directly,
        # so test via sampling in a separate context
        count = 0
        for _ in 1:2000
            @context DensityMatrixContext() begin
                q = QBool(0)
                pauli_exp!([q], pauli_term(1.0, :X), θ)
                count += Bool(q)
            end
        end
        @test abs(count / 2000 - sin(θ)^2) < 0.04
    end

    @testset "evolve! rejects NaN time" begin
        @context EagerContext() begin
            q = QBool(0)
            @test_throws ErrorException evolve!([q], hamiltonian(pauli_term(1.0, :X)), NaN, Trotter1(steps=1))
            discard!(q)
        end
    end

    # ═════════════════════════════════════════════════════════════════════
    # H. Controlled-pauli_exp! optimisation tests
    # ═════════════════════════════════════════════════════════════════════
    # when(ctrl) { pauli_exp!(...) } should only control the Rz pivot.
    # Correctness: ctrl=|0⟩ → identity, ctrl=|1⟩ → exp(-iθP).
    # The optimisation changes gate count but not the quantum channel.

    @testset "controlled exp(-iθZ): ctrl=|0⟩ is identity" begin
        # ctrl=|0⟩, target=|0⟩ → should remain |00⟩
        θ = 0.5
        ctx = EagerContext()
        ctrl = QBool(ctx, 0)      # |0⟩ control
        target = QBool(ctx, 0)    # |0⟩ target
        when(ctrl) do
            pauli_exp!([target], pauli_term(1.0, :Z), θ)
        end
        # ctrl=|0⟩ → identity on target. State = |00⟩.
        @test abs(_amp(ctx, 0) - 1.0) < 1e-12
        @test abs(_amp(ctx, 1)) < 1e-12
        @test abs(_amp(ctx, 2)) < 1e-12
        @test abs(_amp(ctx, 3)) < 1e-12
        discard!(ctrl); discard!(target)
    end

    @testset "controlled exp(-iθZ): ctrl=|1⟩ applies rotation" begin
        # ctrl=|1⟩, target=|0⟩ → target gets exp(-iθZ)|0⟩ = e^{-iθ}|0⟩
        θ = 0.5
        ctx = EagerContext()
        ctrl = QBool(ctx, 1)      # |1⟩ control
        target = QBool(ctx, 0)    # |0⟩ target
        when(ctrl) do
            pauli_exp!([target], pauli_term(1.0, :Z), θ)
        end
        # State = |10⟩ (ctrl=1) with phase e^{-iθ} on target
        # Orkan LSB: ctrl=qubit0=1, target=qubit1=0 → index 1
        @test abs(_amp(ctx, 0)) < 1e-12          # |00⟩
        @test abs(_amp(ctx, 1) - exp(-im*θ)) < 1e-12  # |10⟩
        @test abs(_amp(ctx, 2)) < 1e-12          # |01⟩
        @test abs(_amp(ctx, 3)) < 1e-12          # |11⟩
        discard!(ctrl); discard!(target)
    end

    @testset "controlled exp(-iθX): ctrl=|0⟩ is identity" begin
        θ = π/6
        ctx = EagerContext()
        ctrl = QBool(ctx, 0)
        target = QBool(ctx, 0)
        when(ctrl) do
            pauli_exp!([target], pauli_term(1.0, :X), θ)
        end
        @test abs(_amp(ctx, 0) - 1.0) < 1e-12
        for i in 1:3
            @test abs(_amp(ctx, i)) < 1e-12
        end
        discard!(ctrl); discard!(target)
    end

    @testset "controlled exp(-iθX): ctrl=|1⟩ applies rotation" begin
        # ctrl=|1⟩: exp(-iθX)|0⟩ = cos(θ)|0⟩ - i·sin(θ)|1⟩
        θ = π/6
        ctx = EagerContext()
        ctrl = QBool(ctx, 1)
        target = QBool(ctx, 0)
        when(ctrl) do
            pauli_exp!([target], pauli_term(1.0, :X), θ)
        end
        # Orkan LSB: ctrl=qubit0, target=qubit1
        # |ctrl=1, target=0⟩ = index 1, |ctrl=1, target=1⟩ = index 3
        @test abs(_amp(ctx, 0)) < 1e-12                       # |00⟩
        @test abs(_amp(ctx, 1) - cos(θ)) < 1e-12              # |10⟩ = ctrl=1, tgt=0
        @test abs(_amp(ctx, 2)) < 1e-12                       # |01⟩
        @test abs(_amp(ctx, 3) - (-im * sin(θ))) < 1e-12      # |11⟩ = ctrl=1, tgt=1
        discard!(ctrl); discard!(target)
    end

    @testset "controlled exp(-iθ ZZ): ctrl in superposition" begin
        # ctrl=|+⟩: creates entanglement between ctrl and target register.
        # |+⟩|00⟩ → (|0⟩|00⟩ + |1⟩exp(-iθZZ)|00⟩)/√2
        #         = (|0⟩|00⟩ + e^{-iθ}|1⟩|00⟩)/√2
        θ = 0.4
        ctx = EagerContext()
        ctrl = QBool(ctx, 0.5)    # |+⟩
        q1 = QBool(ctx, 0)
        q2 = QBool(ctx, 0)
        when(ctrl) do
            pauli_exp!([q1, q2], pauli_term(1.0, :Z, :Z), θ)
        end
        # 3 qubits: ctrl=qubit0, q1=qubit1, q2=qubit2
        # |000⟩ = index 0: amplitude 1/√2
        # |001⟩ = index 1 (ctrl=1,q1=0,q2=0): amplitude e^{-iθ}/√2
        @test abs(_amp(ctx, 0) - 1/√2) < 1e-12
        @test abs(_amp(ctx, 1) - exp(-im*θ)/√2) < 1e-12
        for i in 2:7
            @test abs(_amp(ctx, i)) < 1e-12
        end
        discard!(ctrl); discard!(q1); discard!(q2)
    end

    @testset "controlled evolve! on QInt" begin
        # ctrl=|1⟩, QInt evolve should work via NTuple path
        θ = 0.3
        ctx = EagerContext()
        Sturm.task_local_storage(:sturm_context, ctx) do
            ctrl = QBool(ctx, 1)
            q = QInt{1}(0)
            when(ctrl) do
                evolve!(q, hamiltonian(pauli_term(1.0, :X)), θ, Trotter1(steps=1))
            end
            # ctrl=1 → exp(-iθX)|0⟩ = cos(θ)|0⟩ - i·sin(θ)|1⟩
            # ctrl=qubit0=1, q=qubit1. |10⟩=idx1, |11⟩=idx3
            @test abs(_amp(ctx, 0)) < 1e-12
            @test abs(_amp(ctx, 1) - cos(θ)) < 1e-12
            @test abs(_amp(ctx, 2)) < 1e-12
            @test abs(_amp(ctx, 3) - (-im * sin(θ))) < 1e-12
            discard!(ctrl); discard!(q)
        end
    end

    @testset "controlled pauli_exp! with Y operator" begin
        # ctrl=|1⟩: exp(-iθY)|0⟩ = cos(θ)|0⟩ + sin(θ)|1⟩
        θ = π/5
        ctx = EagerContext()
        ctrl = QBool(ctx, 1)
        target = QBool(ctx, 0)
        when(ctrl) do
            pauli_exp!([target], pauli_term(1.0, :Y), θ)
        end
        @test abs(_amp(ctx, 0)) < 1e-12
        @test abs(_amp(ctx, 1) - cos(θ)) < 1e-11
        @test abs(_amp(ctx, 2)) < 1e-12
        @test abs(_amp(ctx, 3) - sin(θ)) < 1e-11
        discard!(ctrl); discard!(target)
    end

end
