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

    # NOTE: Full controlled-LCU test (when(signal) { be.oracle! }) is blocked by
    # EagerContext's multi-controlled Rz limit. SELECT adds its own ancilla control
    # on top of the signal control → 2+ controls on the Rz pivot → crash.
    # The control-stack isolation in oracle! is mathematically correct (verified by
    # Opus review), but requires multi-controlled Rz support to test end-to-end.
    # The hand-crafted oracle test in test_qsvt_phase_factors.jl verifies the
    # when(signal) { oracle! } pattern works for simple oracles.

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

end
