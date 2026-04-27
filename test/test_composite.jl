using Test
using Random: MersenneTwister
using Sturm
using Sturm: nqubits, nterms, lambda, _partition, _qdrift_schedule
using LinearAlgebra: eigen, Diagonal, kron

# _amp, _probs, _infidelity, _state_error, _exact_evolve defined in earlier test files

@testset "Composite Trotter+qDRIFT simulation" begin

    # ═════════════════════════════════════════════════════════════════════
    # A. Construction and validation
    # ═════════════════════════════════════════════════════════════════════

    @testset "Composite construction" begin
        alg = Composite(steps=10, qdrift_samples=200, cutoff=0.3)
        @test alg.steps == 10
        @test alg.qdrift_samples == 200
        @test alg.cutoff == 0.3
        @test alg.trotter_order == 2  # default
        @test_throws ErrorException Composite(steps=0)
        @test_throws ErrorException Composite(cutoff=0.0)
        @test_throws ErrorException Composite(cutoff=-1.0)
    end

    @testset "_qdrift_schedule preserves user total — bead Sturm.jl-m0p9" begin
        # Pre-fix: samples_per_step = max(1, total ÷ steps) silently lost
        # the remainder. qdrift_samples=10, steps=3 produced 3·3 = 9 samples
        # instead of 10. The fix distributes the remainder across the first
        # `total % steps` steps via cld, the rest via div.
        @test sum(_qdrift_schedule(10, 3)) == 10
        @test _qdrift_schedule(10, 3) == [4, 3, 3]
        # Even division: no remainder.
        @test sum(_qdrift_schedule(10, 5)) == 10
        @test _qdrift_schedule(10, 5) == [2, 2, 2, 2, 2]
        # total < steps: drop the silent floor that inflated total to steps.
        @test sum(_qdrift_schedule(2, 10)) == 2
        @test _qdrift_schedule(2, 10) == [1, 1, 0, 0, 0, 0, 0, 0, 0, 0]
        # zero samples is fine.
        @test sum(_qdrift_schedule(0, 5)) == 0
        @test _qdrift_schedule(0, 5) == [0, 0, 0, 0, 0]
        # Single step gets all.
        @test _qdrift_schedule(7, 1) == [7]
        # Bad inputs error loudly.
        @test_throws ErrorException _qdrift_schedule(10, 0)
        @test_throws ErrorException _qdrift_schedule(-1, 5)
    end

    @testset "Hamiltonian partitioning" begin
        H = hamiltonian(
            pauli_term(2.0, :Z, :Z),    # large: |2.0| ≥ 0.5
            pauli_term(0.3, :X, :I),     # small: |0.3| < 0.5
            pauli_term(0.8, :I, :X),     # large: |0.8| ≥ 0.5
            pauli_term(0.1, :Y, :Y),     # small: |0.1| < 0.5
        )
        A, B = _partition(H, 0.5)
        @test nterms(A) == 2    # ZZ (2.0) and IX (0.8)
        @test nterms(B) == 2    # XI (0.3) and YY (0.1)
        @test lambda(A) ≈ 2.8
        @test lambda(B) ≈ 0.4
    end

    @testset "Partition edge cases" begin
        H = hamiltonian(pauli_term(1.0, :Z), pauli_term(0.5, :X))
        # All above cutoff
        A, B = _partition(H, 0.1)
        @test nterms(A) == 2
        @test B === nothing
        # All below cutoff
        A2, B2 = _partition(H, 2.0)
        @test A2 === nothing
        @test nterms(B2) == 2
    end

    # ═════════════════════════════════════════════════════════════════════
    # B. Degenerate cases: pure Trotter, pure qDRIFT
    # ═════════════════════════════════════════════════════════════════════

    @testset "All terms in Trotter partition (cutoff=0.01)" begin
        # Small cutoff → everything in Trotter → should match pure Trotter2
        θ = 0.3
        H = hamiltonian(pauli_term(1.0, :Z, :Z), pauli_term(0.5, :X, :I))
        ψ_exact = _exact_evolve(H, θ)

        ctx = EagerContext()
        q1 = QBool(ctx, 0); q2 = QBool(ctx, 0)
        evolve!([q1, q2], H, θ, Composite(steps=50, cutoff=0.01, qdrift_samples=0))
        @test _state_error(ctx, ψ_exact) < 1e-5
        discard!(q1); discard!(q2)
    end

    @testset "All terms in qDRIFT partition (cutoff=10.0)" begin
        # High cutoff → everything in qDRIFT → should converge like pure qDRIFT
        θ = 0.2
        H = hamiltonian(pauli_term(1.0, :Z, :Z), pauli_term(0.5, :X, :I))
        ψ_exact = _exact_evolve(H, θ)

        N_trials = 20
        total_err = 0.0
        for _ in 1:N_trials
            ctx = EagerContext()
            q1 = QBool(ctx, 0); q2 = QBool(ctx, 0)
            evolve!([q1, q2], H, θ, Composite(steps=10, cutoff=10.0, qdrift_samples=2000))
            total_err += _state_error(ctx, ψ_exact)
            discard!(q1); discard!(q2)
        end
        @test total_err / N_trials < 0.01
    end

    # ═════════════════════════════════════════════════════════════════════
    # C. Matrix ground truth: bimodal Hamiltonian, N=2 to N=10
    # ═════════════════════════════════════════════════════════════════════
    # The composite method shines on Hamiltonians with few large + many small terms.

    @testset "Bimodal H, N=2: composite vs exact" begin
        # 1 large ZZ + 2 small transverse field terms
        H = hamiltonian(
            pauli_term(2.0, :Z, :Z),
            pauli_term(0.1, :X, :I),
            pauli_term(0.1, :I, :X))
        t = 0.3
        ψ_exact = _exact_evolve(H, t)

        # Cutoff=0.5: ZZ → Trotter, X terms → qDRIFT
        N_trials = 20
        total_err = 0.0
        for _ in 1:N_trials
            ctx = EagerContext()
            q1 = QBool(ctx, 0); q2 = QBool(ctx, 0)
            evolve!([q1, q2], H, t,
                    Composite(steps=20, cutoff=0.5, qdrift_samples=500))
            total_err += _state_error(ctx, ψ_exact)
            discard!(q1); discard!(q2)
        end
        @test total_err / N_trials < 0.01
    end

    @testset "Ising ground truth N=$N" for N in [4, 6, 8, 10]
        H = ising(Val(N), J=1.0, h=0.2)  # J=1.0 large, h=0.2 small
        t = 0.15
        ψ_exact = _exact_evolve(H, t)

        # Cutoff=0.5: ZZ terms (coeff 1.0) → Trotter, X terms (coeff 0.2) → qDRIFT
        λ_val = lambda(H)
        N_trials = 15
        total_err = 0.0
        for _ in 1:N_trials
            ctx = EagerContext()
            qs = [QBool(ctx, 0) for _ in 1:N]
            evolve!(qs, H, t,
                    Composite(steps=30, cutoff=0.5, qdrift_samples=1000))
            total_err += _state_error(ctx, ψ_exact)
            for q in qs; discard!(q); end
        end
        @test total_err / N_trials < 0.05
    end

    # ═════════════════════════════════════════════════════════════════════
    # D. Cross-validation: Composite vs Trotter2 vs qDRIFT
    # ═════════════════════════════════════════════════════════════════════

    @testset "Composite vs Trotter2: Ising N=$N" for N in [4, 8, 14]
        H = ising(Val(N), J=1.0, h=0.3)
        t = 0.1

        # High-accuracy Trotter2 reference
        ctx_ref = EagerContext()
        qs_ref = [QBool(ctx_ref, 0) for _ in 1:N]
        evolve!(qs_ref, H, t, Trotter2(steps=200))

        # Composite
        N_trials = 10
        total_infid = 0.0
        for _ in 1:N_trials
            ctx = EagerContext()
            qs = [QBool(ctx, 0) for _ in 1:N]
            evolve!(qs, H, t,
                    Composite(steps=30, cutoff=0.5, qdrift_samples=500))
            total_infid += _infidelity(ctx_ref, ctx)
            for q in qs; discard!(q); end
        end
        @test total_infid / N_trials < 0.01

        for q in qs_ref; discard!(q); end
    end

    # ═════════════════════════════════════════════════════════════════════
    # E. Large-N cross-validation (N=16, 20, 24)
    # ═════════════════════════════════════════════════════════════════════

    @testset "Composite vs Trotter2: Ising N=$N (large)" for N in [16, 20, 24]
        H = ising(Val(N), J=1.0, h=0.2)
        t = 0.05

        ctx_ref = EagerContext()
        qs_ref = [QBool(ctx_ref, 0) for _ in 1:N]
        evolve!(qs_ref, H, t, Trotter2(steps=50))

        ctx = EagerContext()
        qs = [QBool(ctx, 0) for _ in 1:N]
        evolve!(qs, H, t,
                Composite(steps=20, cutoff=0.5, qdrift_samples=500))

        @test _infidelity(ctx_ref, ctx) < 0.05

        for q in qs_ref; discard!(q); end
        for q in qs; discard!(q); end
    end

    # ═════════════════════════════════════════════════════════════════════
    # F. Trotter order selection
    # ═════════════════════════════════════════════════════════════════════

    @testset "Higher Trotter order in composite" begin
        # Use few composite steps so Trotter error dominates over qDRIFT noise,
        # and high qdrift_samples to suppress qDRIFT variance.
        H = ising(Val(4), J=1.0, h=0.1)  # small h → most weight in Trotter partition
        t = 0.5  # longer time amplifies Trotter order difference
        ψ_exact = _exact_evolve(H, t)

        N_trials = 20
        err_o1 = 0.0
        err_o2 = 0.0
        for _ in 1:N_trials
            ctx1 = EagerContext()
            qs1 = [QBool(ctx1, 0) for _ in 1:4]
            evolve!(qs1, H, t,
                    Composite(steps=5, cutoff=0.05, qdrift_samples=2000, trotter_order=1))
            err_o1 += _state_error(ctx1, ψ_exact)
            for q in qs1; discard!(q); end

            ctx2 = EagerContext()
            qs2 = [QBool(ctx2, 0) for _ in 1:4]
            evolve!(qs2, H, t,
                    Composite(steps=5, cutoff=0.05, qdrift_samples=2000, trotter_order=2))
            err_o2 += _state_error(ctx2, ψ_exact)
            for q in qs2; discard!(q); end
        end
        @test err_o2 / N_trials < err_o1 / N_trials
    end

    # ═════════════════════════════════════════════════════════════════════
    # G. Edge cases
    # ═════════════════════════════════════════════════════════════════════

    @testset "Zero time is identity" begin
        ctx = EagerContext()
        q = QBool(ctx, 0)
        evolve!([q], hamiltonian(pauli_term(1.0, :X)), 0.0,
                Composite(steps=5, cutoff=0.5, qdrift_samples=50))
        @test abs(_amp(ctx, 0) - 1.0) < 1e-12
        discard!(q)
    end

    @testset "Single-term H: composite is exact" begin
        θ = 0.5
        ctx = EagerContext()
        q = QBool(ctx, 0)
        evolve!([q], hamiltonian(pauli_term(1.0, :X)), θ,
                Composite(steps=10, cutoff=0.5, qdrift_samples=50))
        @test abs(_amp(ctx, 0) - cos(θ)) < 1e-6
        @test abs(_amp(ctx, 1) - (-im * sin(θ))) < 1e-6
        discard!(q)
    end

    @testset "evolve! on QInt with Composite" begin
        @context EagerContext() begin
            H = hamiltonian(pauli_term(1.0, :X))
            q = QInt{1}(0)
            result = evolve!(q, H, 0.1,
                            Composite(steps=5, cutoff=0.5, qdrift_samples=20))
            @test result === q
            discard!(q)
        end
    end

    # ═════════════════════════════════════════════════════════════════════
    # H. DAG emit
    # ═════════════════════════════════════════════════════════════════════

    @testset "Composite traces into Channel" begin
        H = hamiltonian(pauli_term(1.0, :Z, :Z), pauli_term(0.1, :X, :I))
        ch = trace(2) do q1, q2
            evolve!([q1, q2], H, 0.1,
                    Composite(steps=3, cutoff=0.5, qdrift_samples=10))
            (q1, q2)
        end
        @test n_inputs(ch) == 2
        @test n_outputs(ch) == 2
        @test length(ch.dag) > 0
    end

    # ═════════════════════════════════════════════════════════════════════
    # I. Controlled composite
    # ═════════════════════════════════════════════════════════════════════

    @testset "Controlled composite: ctrl=|0⟩ is identity" begin
        ctx = EagerContext()
        ctrl = QBool(ctx, 0)
        target = QBool(ctx, 0)
        when(ctrl) do
            evolve!([target], hamiltonian(pauli_term(1.0, :X)), 0.5,
                    Composite(steps=5, cutoff=0.5, qdrift_samples=20))
        end
        @test abs(_amp(ctx, 0) - 1.0) < 1e-12
        for i in 1:3
            @test abs(_amp(ctx, i)) < 1e-12
        end
        discard!(ctrl); discard!(target)
    end

    @testset "Controlled composite: ctrl=|1⟩ applies (single term)" begin
        θ = π/6
        ctx = EagerContext()
        ctrl = QBool(ctx, 1)
        target = QBool(ctx, 0)
        when(ctrl) do
            evolve!([target], hamiltonian(pauli_term(1.0, :X)), θ,
                    Composite(steps=10, cutoff=0.5, qdrift_samples=20))
        end
        @test abs(_amp(ctx, 0)) < 1e-12
        @test abs(_amp(ctx, 1) - cos(θ)) < 1e-6
        @test abs(_amp(ctx, 2)) < 1e-12
        @test abs(_amp(ctx, 3) - (-im * sin(θ))) < 1e-6
        discard!(ctrl); discard!(target)
    end

    # ─────────────────────────────────────────────────────────────────────
    # RNG injection: reproducible circuits (Sturm.jl-1f3)
    # ─────────────────────────────────────────────────────────────────────

    @testset "Composite rng kwarg is stored and threaded to qDRIFT partition" begin
        # cutoff=0.75 splits ising(J=1.0, h=0.5): ZZ → Trotter, X → qDRIFT.
        # cutoff=0.5 would put all terms in Trotter (|hⱼ| ≥ cutoff), making RNG
        # threading unobservable (test would pass vacuously).
        H = ising(Val(3), J=1.0, h=0.5)
        alg = Composite(steps=2, qdrift_samples=10, cutoff=0.75,
                        trotter_order=2, rng=MersenneTwister(42))
        @test alg.rng isa MersenneTwister
        # End-to-end: identically-seeded runs yield identical amplitudes.
        run_once(seed) = @context EagerContext() begin
            qs = [QBool(0.0) for _ in 1:3]
            evolve!(qs, H, 0.5,
                    Composite(steps=2, qdrift_samples=10, cutoff=0.75,
                              trotter_order=2, rng=MersenneTwister(seed)))
            a = [_amp(qs[1].ctx, i) for i in 0:7]
            for q in qs; discard!(q); end
            a
        end
        amps_a = run_once(42)
        amps_b = run_once(42)
        amps_c = run_once(99)
        @test amps_a == amps_b           # same seed → identical circuit
        @test amps_a != amps_c           # different seed → different circuit (RNG is actually threaded)
    end

end
