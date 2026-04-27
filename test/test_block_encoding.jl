using Test
using Sturm
using LinearAlgebra: I, norm
using Sturm: nqubits, nterms, lambda, BlockEncoding,
             _prepare!, _prepare_adj!, _select!,
             block_encode_lcu

# Helper: read Orkan amplitude at basis state index (0-based)
_amp(ctx, idx) = Sturm.orkan_state_get(ctx.orkan.raw, idx, 0)

# Helper: build the explicit matrix for a PauliHamiltonian on N qubits
# by summing h_j * kron(P_1, ..., P_N) for each term.
function _pauli_matrix(H::PauliHamiltonian{N}) where {N}
    dim = 1 << N
    mat = zeros(ComplexF64, dim, dim)
    I2 = ComplexF64[1 0; 0 1]
    X2 = ComplexF64[0 1; 1 0]
    Y2 = ComplexF64[0 -im; im 0]
    Z2 = ComplexF64[1 0; 0 -1]
    for term in H.terms
        kron_mat = ones(ComplexF64, 1, 1)
        # Build tensor product in Orkan's little-endian convention:
        # wire 1 (ops[1]) = bit 0 (LSB), wire N (ops[N]) = bit N-1 (MSB).
        # Julia's kron(A, B) places A on MSB and B on LSB, so we need
        # kron(P_N, ..., P_2, P_1) = build up as kron(p, kron_mat).
        for k in 1:N
            op = term.ops[k]
            p = op == pauli_I ? I2 :
                op == pauli_X ? X2 :
                op == pauli_Y ? Y2 : Z2
            kron_mat = kron(p, kron_mat)
        end
        mat .+= term.coeff .* kron_mat
    end
    mat
end

# Helper: get full state vector from context
function _statevec(ctx, n)
    dim = 1 << n
    [_amp(ctx, i) for i in 0:dim-1]
end

"""
    _proportional(actual, expected; tol=1e-10) -> Bool

Check that two complex vectors are proportional (equal up to global phase).
Returns true if actual = e^{iφ} * expected for some φ, within tolerance.

This is the correct comparison for block encodings in Sturm's channel model:
the DSL lives in SU(2), so all derived gates carry global phases that are
physically unobservable (CLAUDE.md: "H! = -i·H, Z! = -i·Z").
"""
function _proportional(actual::Vector{ComplexF64}, expected::Vector{ComplexF64};
                        tol::Float64=1e-10)
    length(actual) == length(expected) || return false
    # Find a non-zero entry to extract the phase
    idx = findfirst(i -> abs(expected[i]) > tol, 1:length(expected))
    idx === nothing && return all(abs.(actual) .< tol)  # both zero
    phase = actual[idx] / expected[idx]
    abs(abs(phase) - 1.0) < tol || return false  # phase must have unit magnitude
    return norm(actual .- phase .* expected) < tol * length(actual)
end

@testset "Block Encoding" begin

    # ═════════════════════════════════════════════════════════════════════
    # Test Hamiltonian: 2-qubit Ising model
    # H = -J ZZ - h XI - h IX  (with J=1.0, h=0.5)
    # ═════════════════════════════════════════════════════════════════════

    H_ising = hamiltonian(
        pauli_term(-1.0, :Z, :Z),
        pauli_term(-0.5, :X, :I),
        pauli_term(-0.5, :I, :X),
    )

    # ─────────────────────────────────────────────────────────────────────
    # 1. PREPARE fidelity: ancilla distribution matches |h_j|/lambda
    # ─────────────────────────────────────────────────────────────────────

    @testset "PREPARE: ancilla distribution matches |h_j|/lambda" begin
        L = nterms(H_ising)
        lam = lambda(H_ising)
        a = Int(ceil(log2(L)))

        # Expected probability distribution: |h_j| / lambda for each term j
        expected_probs = [abs(t.coeff) / lam for t in H_ising.terms]
        while length(expected_probs) < (1 << a)
            push!(expected_probs, 0.0)
        end

        # Run PREPARE and read amplitudes directly (deterministic check)
        ctx = EagerContext()
        ancillas = [QBool(ctx, 0) for _ in 1:a]
        _prepare!(ancillas, H_ising)

        # Check that |amplitude|^2 matches expected probability
        for j in 0:(1 << a)-1
            amp = _amp(ctx, j)
            @test abs(abs2(amp) - expected_probs[j + 1]) < 1e-10
        end

        for anc in ancillas; discard!(anc); end
    end

    # ─────────────────────────────────────────────────────────────────────
    # 1b. PREPARE statistical test (measurement sampling)
    # ─────────────────────────────────────────────────────────────────────

    @testset "PREPARE: measurement histogram matches distribution" begin
        L = nterms(H_ising)
        lam = lambda(H_ising)
        a = Int(ceil(log2(L)))

        expected_probs = [abs(t.coeff) / lam for t in H_ising.terms]
        while length(expected_probs) < (1 << a)
            push!(expected_probs, 0.0)
        end

        N_samples = 10000
        counts = zeros(Int, 1 << a)

        for _ in 1:N_samples
            ctx = EagerContext()
            ancillas = [QBool(ctx, 0) for _ in 1:a]
            _prepare!(ancillas, H_ising)
            idx = 0
            for k in 1:a
                bit = Bool(ancillas[k])
                if bit
                    idx |= (1 << (k - 1))
                end
            end
            counts[idx + 1] += 1
        end

        measured_probs = counts ./ N_samples
        for j in 1:(1 << a)
            if expected_probs[j] > 0
                sigma = sqrt(expected_probs[j] * (1 - expected_probs[j]) / N_samples)
                @test abs(measured_probs[j] - expected_probs[j]) < 3 * sigma + 1e-6
            else
                @test counts[j] == 0
            end
        end
    end

    # ─────────────────────────────────────────────────────────────────────
    # 1c. PREPARE adjoint roundtrip: PREPARE_adj . PREPARE |0> = |0>
    # ─────────────────────────────────────────────────────────────────────

    @testset "PREPARE: adjoint roundtrip restores |0>" begin
        L = nterms(H_ising)
        a = Int(ceil(log2(L)))

        ctx = EagerContext()
        ancillas = [QBool(ctx, 0) for _ in 1:a]
        _prepare!(ancillas, H_ising)
        _prepare_adj!(ancillas, H_ising)

        # Should be back to |00> (up to global phase)
        @test abs2(_amp(ctx, 0)) > 1.0 - 1e-10
        for j in 1:(1 << a)-1
            @test abs2(_amp(ctx, j)) < 1e-10
        end

        for anc in ancillas; discard!(anc); end
    end

    # ─────────────────────────────────────────────────────────────────────
    # 2. SELECT correctness: for each term j, |j>|psi> -> |j>(P_j|psi>)
    #    Comparison is up to global phase (channel equivalence).
    # ─────────────────────────────────────────────────────────────────────

    @testset "SELECT: applies correct Pauli for each term index" begin
        N = nqubits(H_ising)
        L = nterms(H_ising)
        a = Int(ceil(log2(L)))

        for j in 0:(1 << a)-1
            ctx = EagerContext()

            # Prepare ancilla in computational basis state |j>
            anc = [QBool(ctx, 0) for _ in 1:a]
            for k in 1:a
                if (j >> (k - 1)) & 1 == 1
                    X!(anc[k])
                end
            end

            # Prepare system in |01>
            sys = [QBool(ctx, 0) for _ in 1:N]
            X!(sys[2])

            # Apply SELECT
            _select!(anc, sys, H_ising)

            # Extract system amplitudes conditioned on ancilla = |j>
            sys_dim = 1 << N
            sys_amps = zeros(ComplexF64, sys_dim)
            for s in 0:sys_dim-1
                full_idx = j + (s << a)
                sys_amps[s + 1] = _amp(ctx, full_idx)
            end

            # Build expected: sign(h_j) * P_j applied to |01>
            input_vec = zeros(ComplexF64, sys_dim)
            input_vec[3] = 1.0  # |01> = index 2 (0-based), position 3 (1-based)

            if j < L
                term = H_ising.terms[j + 1]
                sgn = sign(term.coeff)
                H_single = hamiltonian(PauliTerm{N}(sgn, term.ops))
                P_mat = _pauli_matrix(H_single)
            else
                P_mat = Matrix{ComplexF64}(I, sys_dim, sys_dim)
            end
            expected = P_mat * input_vec

            # Compare up to global phase (channel equivalence)
            @test _proportional(sys_amps, expected, tol=1e-8)

            for q in anc; discard!(q); end
            for q in sys; discard!(q); end
        end
    end

    # ─────────────────────────────────────────────────────────────────────
    # 2b. SELECT is self-adjoint: SELECT . SELECT = I (up to global phase)
    # ─────────────────────────────────────────────────────────────────────

    @testset "SELECT: self-adjoint (SELECT^2 = identity)" begin
        N = nqubits(H_ising)
        L = nterms(H_ising)
        a = Int(ceil(log2(L)))

        ctx = EagerContext()
        anc = [QBool(ctx, 0) for _ in 1:a]
        X!(anc[1])  # ancilla = |01> = term 1

        sys = [QBool(ctx, 0) for _ in 1:N]
        X!(sys[2])  # system = |01>

        # Apply SELECT twice
        _select!(anc, sys, H_ising)
        _select!(anc, sys, H_ising)

        # System should be back to |01> (up to global phase)
        total = a + N
        anc_idx = 1  # |01> ancilla
        sys_dim = 1 << N
        sys_amps = zeros(ComplexF64, sys_dim)
        for s in 0:sys_dim-1
            sys_amps[s + 1] = _amp(ctx, anc_idx + (s << a))
        end

        expected = zeros(ComplexF64, sys_dim)
        expected[3] = 1.0  # |01>

        @test _proportional(sys_amps, expected, tol=1e-8)

        for q in anc; discard!(q); end
        for q in sys; discard!(q); end
    end

    # ─────────────────────────────────────────────────────────────────────
    # 3. LCU roundtrip: <0^a| U |0^a> |psi> = (H/lambda)|psi>
    #    Comparison up to global phase.
    # ─────────────────────────────────────────────────────────────────────

    @testset "LCU: ancilla=|0> subspace encodes H/lambda" begin
        N = nqubits(H_ising)
        lam = lambda(H_ising)
        L = nterms(H_ising)
        a = Int(ceil(log2(L)))

        be = block_encode_lcu(H_ising)
        @test be.n_system == N
        @test be.n_ancilla == a
        @test abs(be.alpha - lam) < 1e-12

        # Test on |01> input
        ctx = EagerContext()
        @context ctx begin
            ancillas = [QBool(0) for _ in 1:a]
            system = [QBool(0) for _ in 1:N]
            X!(system[2])

            be.oracle!(ancillas, system)

            sys_dim = 1 << N
            projected_amps = zeros(ComplexF64, sys_dim)
            for s in 0:sys_dim-1
                full_idx = 0 + (s << a)
                projected_amps[s + 1] = _amp(ctx, full_idx)
            end

            H_mat = _pauli_matrix(H_ising)
            input_vec = zeros(ComplexF64, sys_dim)
            input_vec[3] = 1.0
            expected = (H_mat / lam) * input_vec

            @test _proportional(projected_amps, expected, tol=1e-8)

            for q in ancillas; discard!(q); end
            for q in system; discard!(q); end
        end
    end

    # ─────────────────────────────────────────────────────────────────────
    # 3b. LCU on |00> input
    # ─────────────────────────────────────────────────────────────────────

    @testset "LCU: ancilla=|0> subspace on |00> input" begin
        N = nqubits(H_ising)
        lam = lambda(H_ising)
        L = nterms(H_ising)
        a = Int(ceil(log2(L)))

        be = block_encode_lcu(H_ising)

        ctx = EagerContext()
        @context ctx begin
            ancillas = [QBool(0) for _ in 1:a]
            system = [QBool(0) for _ in 1:N]

            be.oracle!(ancillas, system)

            sys_dim = 1 << N
            projected_amps = zeros(ComplexF64, sys_dim)
            for s in 0:sys_dim-1
                full_idx = 0 + (s << a)
                projected_amps[s + 1] = _amp(ctx, full_idx)
            end

            H_mat = _pauli_matrix(H_ising)
            input_vec = zeros(ComplexF64, sys_dim)
            input_vec[1] = 1.0
            expected = (H_mat / lam) * input_vec

            @test _proportional(projected_amps, expected, tol=1e-8)

            for q in ancillas; discard!(q); end
            for q in system; discard!(q); end
        end
    end

    # ─────────────────────────────────────────────────────────────────────
    # 4. Sign handling: negative coefficients
    # ─────────────────────────────────────────────────────────────────────

    @testset "LCU: sign handling with mixed positive/negative coefficients" begin
        H_mixed = hamiltonian(
            pauli_term(1.0, :Z, :I),
            pauli_term(-0.5, :I, :Z),
        )

        N = nqubits(H_mixed)
        lam = lambda(H_mixed)
        L = nterms(H_mixed)
        a = max(1, Int(ceil(log2(L))))

        be = block_encode_lcu(H_mixed)

        # Test on |10> input
        ctx = EagerContext()
        @context ctx begin
            ancillas = [QBool(0) for _ in 1:a]
            system = [QBool(0) for _ in 1:N]
            X!(system[1])

            be.oracle!(ancillas, system)

            sys_dim = 1 << N
            projected_amps = zeros(ComplexF64, sys_dim)
            for s in 0:sys_dim-1
                full_idx = 0 + (s << a)
                projected_amps[s + 1] = _amp(ctx, full_idx)
            end

            H_mat = _pauli_matrix(H_mixed)
            input_vec = zeros(ComplexF64, sys_dim)
            input_vec[2] = 1.0  # |10>
            expected = (H_mat / lam) * input_vec

            @test _proportional(projected_amps, expected, tol=1e-8)

            for q in ancillas; discard!(q); end
            for q in system; discard!(q); end
        end
    end

    # ─────────────────────────────────────────────────────────────────────
    # 5. Single-qubit Hamiltonian (edge case: 1 system qubit)
    # ─────────────────────────────────────────────────────────────────────

    @testset "LCU: single-qubit Hamiltonian" begin
        H1 = hamiltonian(
            pauli_term(0.7, :X),
            pauli_term(0.3, :Z),
        )

        N = nqubits(H1)
        lam = lambda(H1)
        a = max(1, Int(ceil(log2(nterms(H1)))))

        be = block_encode_lcu(H1)
        @test be.n_system == 1
        @test be.n_ancilla == a

        ctx = EagerContext()
        @context ctx begin
            ancillas = [QBool(0) for _ in 1:a]
            system = [QBool(0) for _ in 1:N]

            be.oracle!(ancillas, system)

            sys_dim = 1 << N
            projected_amps = zeros(ComplexF64, sys_dim)
            for s in 0:sys_dim-1
                full_idx = 0 + (s << a)
                projected_amps[s + 1] = _amp(ctx, full_idx)
            end

            H_mat = _pauli_matrix(H1)
            input_vec = zeros(ComplexF64, sys_dim)
            input_vec[1] = 1.0
            expected = (H_mat / lam) * input_vec

            @test _proportional(projected_amps, expected, tol=1e-8)

            for q in ancillas; discard!(q); end
            for q in system; discard!(q); end
        end
    end

    # ─────────────────────────────────────────────────────────────────────
    # 5b. Identity term with negative coefficient (C2 bug from review)
    # ─────────────────────────────────────────────────────────────────────

    @testset "_rotation_tree! rejects negative coefficients — bead Sturm.jl-pwuy" begin
        # Pre-fix the clamp(p_right, 0, 1) silently absorbed a negative
        # weight into p_right=0, producing wrong rotation angles with no
        # diagnostic. Direct invocation of the internal helper with a
        # mixed-sign weight vector must error loudly.
        @context EagerContext() begin
            anc = [QBool(0), QBool(0)]
            bad_weights = Float64[1.0, -2.0, 3.0, 0.5]   # negative entry
            @test_throws ErrorException Sturm._rotation_tree!(anc, bad_weights, 2, 0, 4)
            @test_throws ErrorException Sturm._rotation_tree_adj!(anc, bad_weights, 2, 0, 4)
            # Sanity: non-negative weights still work.
            ok_weights = Float64[1.0, 2.0, 3.0, 0.5]
            Sturm._rotation_tree!(anc, ok_weights, 2, 0, 4)
            for q in anc; discard!(q); end
        end
    end

    @testset "LCU: Hamiltonian with identity term errors loudly" begin
        # Identity terms are classical energy offsets — must be removed before
        # block encoding. SELECT cannot apply a uniform -i phase to identity.
        H_id = hamiltonian(
            pauli_term(-2.0, :I, :I),
            pauli_term(1.0, :Z, :Z),
        )
        be = block_encode_lcu(H_id)
        ctx = EagerContext()
        @context ctx begin
            anc = [QBool(0)]
            sys = [QBool(0), QBool(0)]
            @test_throws ErrorException be.oracle!(anc, sys)
            for q in anc; discard!(q); end
            for q in sys; discard!(q); end
        end
    end

    # ─────────────────────────────────────────────────────────────────────
    # 6. BlockEncoding struct fields
    # ─────────────────────────────────────────────────────────────────────

    @testset "BlockEncoding struct" begin
        be = block_encode_lcu(H_ising)
        @test be.alpha == lambda(H_ising)
        @test be.n_system == 2
        @test be.n_ancilla == Int(ceil(log2(nterms(H_ising))))
        @test be.oracle! isa Function
        @test be.oracle_adj! isa Function
    end

    # ─────────────────────────────────────────────────────────────────────
    # 7. LCU adjoint oracle
    # ─────────────────────────────────────────────────────────────────────

    # ─────────────────────────────────────────────────────────────────────
    # 7b. Controlled oracle: when(signal) { oracle! } (QSVT use case)
    # ─────────────────────────────────────────────────────────────────────

    @testset "LCU: oracle unconditional still works after control-stack isolation" begin
        # Verify that the control-stack isolation in oracle! doesn't break
        # the unconditional case (no outer when()). This is a regression test.
        H1 = hamiltonian(
            pauli_term(0.7, :X),
            pauli_term(0.3, :Z),
        )
        be = block_encode_lcu(H1)
        N = nqubits(H1)
        a = be.n_ancilla

        # Run oracle without any when() — should work as before
        ctx = EagerContext()
        @context ctx begin
            ancillas = [QBool(0) for _ in 1:a]
            system = [QBool(0) for _ in 1:N]
            be.oracle!(ancillas, system)
            # Just verify it completes without error and state is finite
            dim = 1 << (a + N)
            total_prob = sum(abs2(_amp(ctx, i)) for i in 0:dim-1)
            @test abs(total_prob - 1.0) < 1e-8

            # Run oracle_adj! to verify roundtrip still works
            be.oracle_adj!(ancillas, system)
            # Should be back to |0⟩^(a+N)
            @test abs2(_amp(ctx, 0)) > 1.0 - 1e-8

            for q in ancillas; discard!(q); end
            for q in system; discard!(q); end
        end
    end

    @testset "LCU: controlled oracle when(signal) in superposition" begin
        # Full controlled-LCU: signal=|+⟩, verify controlled-U behavior.
        # |+⟩|0⟩^a|ψ⟩ → (1/√2)(|0⟩|0⟩^a|ψ⟩ + |1⟩ U|0⟩^a|ψ⟩)
        # Requires multi-controlled Rz (Toffoli cascade) to work.
        H1 = hamiltonian(
            pauli_term(0.7, :X),
            pauli_term(0.3, :Z),
        )
        be = block_encode_lcu(H1)
        N = nqubits(H1)
        a = be.n_ancilla

        ctx = EagerContext()
        @context ctx begin
            signal = QBool(0.5)  # |+⟩
            ancillas = [QBool(0) for _ in 1:a]
            system = [QBool(0) for _ in 1:N]

            when(signal) do
                be.oracle!(ancillas, system)
            end

            # Reference: oracle without control
            ctx_ref = EagerContext()
            ref_amps = @context ctx_ref begin
                anc_ref = [QBool(0) for _ in 1:a]
                sys_ref = [QBool(0) for _ in 1:N]
                be.oracle!(anc_ref, sys_ref)
                dim_ref = 1 << (a + N)
                amps = [_amp(ctx_ref, i) for i in 0:dim_ref-1]
                for q in anc_ref; discard!(q); end
                for q in sys_ref; discard!(q); end
                amps
            end

            # signal=|1⟩ subspace should match reference × 1/√2
            for idx in 0:(1 << (a + N))-1
                full_idx = 1 + (idx << 1)  # signal=|1⟩ is bit 0
                amp = _amp(ctx, full_idx)
                expected = ref_amps[idx + 1] / sqrt(2)
                @test abs(amp - expected) < 1e-6
            end

            # signal=|0⟩ subspace should be identity × 1/√2
            # Only |0⟩^(a+N) should have amplitude
            amp_000 = _amp(ctx, 0)  # signal=|0⟩, all else |0⟩
            @test abs(amp_000 - 1/sqrt(2)) < 1e-6
            for idx in 1:(1 << (a + N))-1
                full_idx = 0 + (idx << 1)  # signal=|0⟩
                @test abs(_amp(ctx, full_idx)) < 1e-6
            end

            discard!(signal)
            for q in ancillas; discard!(q); end
            for q in system; discard!(q); end
        end
    end

    @testset "LCU: oracle then oracle_adj restores initial state" begin
        N = nqubits(H_ising)
        lam = lambda(H_ising)
        a = Int(ceil(log2(nterms(H_ising))))

        be = block_encode_lcu(H_ising)

        ctx = EagerContext()
        @context ctx begin
            ancillas = [QBool(0) for _ in 1:a]
            system = [QBool(0) for _ in 1:N]
            X!(system[1])  # |10>

            be.oracle!(ancillas, system)
            be.oracle_adj!(ancillas, system)

            # Should be back to ancilla=|00>, system=|10>
            total = a + N
            dim = 1 << total
            target_idx = 0 + (1 << a)  # anc=00, sys=10 (bit 0 of system = 1)
            @test abs2(_amp(ctx, target_idx)) > 1.0 - 1e-8

            # All other amplitudes should be ~0
            for idx in 0:dim-1
                if idx != target_idx
                    @test abs2(_amp(ctx, idx)) < 1e-8
                end
            end

            for q in ancillas; discard!(q); end
            for q in system; discard!(q); end
        end
    end

    # ─────────────────────────────────────────────────────────────────────
    # 8. Block encoding product (GSLW19 Lemma 30)
    # ─────────────────────────────────────────────────────────────────────

    @testset "BE product: alpha and ancilla count" begin
        H_a = hamiltonian(pauli_term(0.7, :X), pauli_term(0.3, :Z))
        H_b = hamiltonian(pauli_term(0.5, :Y), pauli_term(0.5, :Z))
        be_a = block_encode_lcu(H_a)
        be_b = block_encode_lcu(H_b)
        be_ab = be_a * be_b

        @test be_ab.alpha ≈ be_a.alpha * be_b.alpha
        @test be_ab.n_ancilla == be_a.n_ancilla + be_b.n_ancilla
        @test be_ab.n_system == 1
    end

    @testset "BE product: encodes AB in ancilla=|0⟩ subspace" begin
        H_a = hamiltonian(pauli_term(0.7, :X), pauli_term(0.3, :Z))
        H_b = hamiltonian(pauli_term(0.5, :Y), pauli_term(0.5, :Z))
        be_a = block_encode_lcu(H_a)
        be_b = block_encode_lcu(H_b)
        be_ab = be_a * be_b

        A_mat = _pauli_matrix(H_a) / lambda(H_a)
        B_mat = _pauli_matrix(H_b) / lambda(H_b)
        AB_expected = A_mat * B_mat

        N = 1
        a_total = be_ab.n_ancilla

        ctx = EagerContext()
        @context ctx begin
            ancillas = [QBool(0) for _ in 1:a_total]
            system = [QBool(0) for _ in 1:N]

            be_ab.oracle!(ancillas, system)

            sys_dim = 1 << N
            projected = zeros(ComplexF64, sys_dim)
            for s in 0:sys_dim-1
                full_idx = 0 + (s << a_total)  # ancilla = |0...0⟩
                projected[s + 1] = _amp(ctx, full_idx)
            end

            input_vec = zeros(ComplexF64, sys_dim)
            input_vec[1] = 1.0  # |0⟩
            expected = AB_expected * input_vec

            @test _proportional(projected, expected, tol=1e-6)

            for q in ancillas; discard!(q); end
            for q in system; discard!(q); end
        end
    end

    @testset "BE product: adjoint roundtrip" begin
        H_a = hamiltonian(pauli_term(0.7, :X), pauli_term(0.3, :Z))
        H_b = hamiltonian(pauli_term(0.5, :Y), pauli_term(0.5, :Z))
        be_ab = block_encode_lcu(H_a) * block_encode_lcu(H_b)

        a_total = be_ab.n_ancilla
        ctx = EagerContext()
        @context ctx begin
            ancillas = [QBool(0) for _ in 1:a_total]
            system = [QBool(0)]

            be_ab.oracle!(ancillas, system)
            be_ab.oracle_adj!(ancillas, system)

            # Should restore to initial state
            total = a_total + 1
            @test abs2(_amp(ctx, 0)) > 1.0 - 1e-6

            for q in ancillas; discard!(q); end
            for q in system; discard!(q); end
        end
    end

    # ═════════════════════════════════════════════════════════════════════
    # 9g5: X↔Y convention-drift discriminators for _flip_for_index! and its
    #      X-sandwich around _multi_controlled_z! (the control-polarity
    #      construction used throughout src/block_encoding/select.jl and
    #      src/block_encoding/prepare.jl).
    #
    # WORKLOG Session 42 (bead 3yz) proved:
    #   Y|0⟩⟨0|Y = |1⟩⟨1| = X|0⟩⟨0|X
    # so the X-sandwich is X↔Y INVARIANT under a symmetric swap. The real
    # drift risk is ASYMMETRIC X↔Y, or a broken sandwich that omits / adds
    # / reorders one of the flips, or changes the bit-mask condition. These
    # tests pin the two guarantees the block-encoding code depends on:
    #
    #   (a) `_flip_for_index!(ancillas, j)` on |j⟩ produces |1…1⟩ up to
    #       global phase — the all-controls-high state MCZ / MC-PauliExp
    #       fires on. Double-application restores |j⟩ (self-inverse).
    #   (b) The full sandwich
    #           _flip_for_index!(j); _multi_controlled_z!; _flip_for_index!(j)
    #       phase-flips EXACTLY |j⟩ and leaves every other |k⟩ unchanged —
    #       this is the core SELECT-loop step (select.jl:137-143).
    #
    # Tests are phase-invariant (CLAUDE.md §Global Phase and Universality):
    # (b) compares ratios post[k]/pre[k] against a non-flipped reference.
    # ═════════════════════════════════════════════════════════════════════

    @testset "9g5: _flip_for_index! maps |j⟩ → |1..1⟩ on W=2 ancillas" begin
        for j in 0:3
            @context EagerContext() begin
                ancillas = [QBool(0) for _ in 1:2]
                # Prepare |j⟩ on the ancilla register using raw primitives
                # (not `X!` from gates.jl — keeps the prep independent of
                # the function under test so a drift inside _flip_for_index!
                # cannot mask itself via a matching drift in the prep).
                (j >> 0) & 1 == 1 && (ancillas[1].θ += π; ancillas[1].φ += π)
                (j >> 1) & 1 == 1 && (ancillas[2].θ += π; ancillas[2].φ += π)

                # After `_flip_for_index!(j)`, ancilla register should be in
                # |1..1⟩ (idx = 3 at W=2) up to global phase.
                Sturm._flip_for_index!(ancillas, j)
                @test abs(abs(_amp(ancillas[1].ctx, 3)) - 1.0) < 1e-12
                for k in 0:2
                    @test abs(_amp(ancillas[1].ctx, k)) < 1e-12
                end

                # Self-inverse: second application restores |j⟩.
                Sturm._flip_for_index!(ancillas, j)
                @test abs(abs(_amp(ancillas[1].ctx, j)) - 1.0) < 1e-12
                for k in 0:3
                    k == j && continue
                    @test abs(_amp(ancillas[1].ctx, k)) < 1e-12
                end

                for q in ancillas; discard!(q); end
            end
        end
    end

    @testset "9g5: flip·MCZ·flip sandwich phase-flips exactly |j⟩" begin
        # Exact call structure at src/block_encoding/select.jl:137-143.
        # On a generic non-|0…0⟩ superposition, ratios post[k]/pre[k] must
        # be equal across all k ≠ j (global phase) and opposite at k == j
        # (the single target flipped).
        for j in 0:3
            @context EagerContext() begin
                ancillas = [QBool(0) for _ in 1:2]
                a, b = π/7, π/11
                ancillas[1].θ += 2a
                ancillas[2].θ += 2b

                pre  = [_amp(ancillas[1].ctx, k) for k in 0:3]

                Sturm._flip_for_index!(ancillas, j)
                Sturm._multi_controlled_z!(ancillas)
                Sturm._flip_for_index!(ancillas, j)

                post = [_amp(ancillas[1].ctx, k) for k in 0:3]

                # Unitary — magnitudes preserved on every amplitude.
                for k in 0:3
                    @test abs(abs(post[k+1]) - abs(pre[k+1])) < 1e-12
                end

                # Pick a non-flipped index as the phase reference.
                ref = j == 0 ? 1 : 0
                r_ref = post[ref+1] / pre[ref+1]
                for k in 0:3
                    ratio_k = post[k+1] / pre[k+1]
                    expected = k == j ? -r_ref : r_ref
                    @test abs(ratio_k - expected) < 1e-12
                end

                for q in ancillas; discard!(q); end
            end
        end
    end

end
