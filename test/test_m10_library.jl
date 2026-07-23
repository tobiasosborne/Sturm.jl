# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# Sturm.jl M10 (bead Sturm.jl-8fo5): the library HOFs — Grover `amplify`/`find`,
# `phase_estimate`, Trotter `evolve!`, and `interfere!`. Full-pipeline tests with
# verification (CLAUDE.md #12): every algorithm is compared against the
# mathematically expected result — Grover's exact closed form sin²((2k+1)θ)
# (docs/physics/grover_1996_search.md, eq (rot)); QPE's exact dyadic readout; the
# Trotter commutator bound and order scaling (docs/physics/childs_2019_trotter_error.md,
# eq E1/E2). Statistical tests use ≥1000 seeded trials with a stated tolerance.

using Test
using Sturm
using Bennett
using LinearAlgebra
using Random
using Sturm: eager, statevector, _core, orkan_state_set!, P,
             _mcz_all_ones!, _grover_diffuse!, grover_iterations, PauliTerm
# `approx_upto_phase` is defined in test_m2_common.jl (Main scope, included earlier).

# --- helpers ---------------------------------------------------------------

# Born probability that register `x` (QInt{W}) reads a value in `marked`, from the
# live statevector (decoded through the wire→slot map — robust to slot layout and to
# any leftover clean ancilla, which it marginalizes over).
function reg_prob(ctx, x, W, marked)
    sv = statevector(ctx); core = _core(ctx)
    slots = [core.wire_to_slot[w] for w in x.wires]
    p = 0.0
    for idx in 0:(length(sv) - 1)
        val = 0
        for j in 1:W
            ((idx >> slots[j]) & 1) == 1 && (val |= (1 << (W - j)))
        end
        (val in marked) && (p += abs2(sv[idx + 1]))
    end
    return p
end

# A caller-supplied phase-marking body: flip the sign of |m⟩ exactly, using only
# surface verbs (bit-flips to map m↔all-ones, then the nested-`when` multi-ctrl Z).
function flip_state!(x, m, W)
    allones = (1 << W) - 1
    xor(x, allones ⊻ m)                     # X on the 0-bits of m: |m⟩ → |1…1⟩
    _mcz_all_ones!([x[i] for i in 1:W])     # phase-flip |1…1⟩
    xor(x, allones ⊻ m)                     # undo
    return x
end

# Realize the unitary that `op!(x)` implements on a W-wire register, by driving each
# computational-basis input (poked directly to avoid gate-prep phase pollution) and
# reading the output column — the same tooling as test_m2_common's realized_matrix.
function op_matrix(op!, W; cap = W + 4)
    N = 1 << W
    U = Matrix{ComplexF64}(undef, N, N)
    for jin in 0:(N - 1)
        eager(cap) do ctx
            x = QInt{W}(ctx, 0)
            core = _core(ctx); slots = [core.wire_to_slot[w] for w in x.wires]
            enc(v) = (i = 0; for j in 1:W; ((v >> (W - j)) & 1) == 1 && (i |= (1 << slots[j])); end; i)
            st = core.state
            orkan_state_set!(st, 0, 0, zero(ComplexF64))
            orkan_state_set!(st, enc(jin), 0, one(ComplexF64))
            op!(x)
            sv = statevector(ctx)
            for jout in 0:(N - 1)
                U[jout + 1, jin + 1] = sv[enc(jout) + 1]
            end
            nothing
        end
    end
    return U
end

# Dense Pauli-word / Hamiltonian matrices (test ground truth).
const _P1 = Dict('I' => ComplexF64[1 0; 0 1], 'X' => ComplexF64[0 1; 1 0],
                 'Y' => ComplexF64[0 -im; im 0], 'Z' => ComplexF64[1 0; 0 -1])
word_mat(w) = foldl(kron, (_P1[c] for c in w))
ham_mat(H) = sum(c .* word_mat(w) for (c, w) in H)
function dist_upto_phase(A, B)
    i = argmax(abs.(vec(B))); ph = (A[i] / B[i]); ph /= abs(ph)
    return opnorm(A .- ph .* B)
end

@testset "M10 — library HOFs (Grover / QPE / Trotter / interfere)" begin

    # =====================================================================
    #  amplify (Grover) — exact closed form sin²((2k+1)θ)
    # =====================================================================
    @testset "M10.GROVER.AMPLIFY-EXACT — sin²((2k+1)θ), caller-marked body" begin
        # grover_iterations = round(π/(4θ) − 1/2), θ = arcsin(√(M/2^W)) (BBHT).
        @test grover_iterations(1, 2) == 1
        @test grover_iterations(1, 3) == 2
        @test grover_iterations(1, 4) == 3
        @test grover_iterations(2, 3) == 1
        @test_throws DomainError grover_iterations(0, 3)
        @test_throws DomainError grover_iterations(9, 3)

        # W=2, M=1 (m=3): θ=π/6, k=1, P = sin²(π/2) = 1 EXACTLY (deterministic N=4).
        p2 = eager(6) do ctx
            x = QInt{2}(0); superpose!(x)
            amplify(x; iterations = 1) do reg; flip_state!(reg, 3, 2) end
            reg_prob(ctx, x, 2, Set(3))
        end
        @test p2 ≈ 1.0 atol = 1e-9

        # A NON-all-ones marked state (m=2) exercises the X-conjugation marker path.
        p2b = eager(6) do ctx
            x = QInt{2}(0); superpose!(x)
            amplify(x; iterations = 1) do reg; flip_state!(reg, 2, 2) end
            reg_prob(ctx, x, 2, Set(2))
        end
        @test p2b ≈ 1.0 atol = 1e-9

        # W=3, M=1 (m=7): θ=asin(1/√8), k=2, P = sin²(5θ) ≈ 0.9453125.
        θ3 = asin(sqrt(1 / 8)); exp3 = sin(5θ3)^2
        @test exp3 ≈ 0.9453125 atol = 1e-6
        p3 = eager(14) do ctx
            x = QInt{3}(0); superpose!(x)
            amplify(x; iterations = 2) do reg; flip_state!(reg, 7, 3) end
            reg_prob(ctx, x, 3, Set(7))
        end
        @test p3 ≈ exp3 atol = 1e-8

        # W=4, M=1 (m=10): θ=asin(1/4), k=3, P = sin²(7θ) ≈ 0.9613.
        θ4 = asin(sqrt(1 / 16)); exp4 = sin(7θ4)^2
        @test exp4 ≈ 0.9613189093 atol = 1e-6
        p4 = eager(18) do ctx
            x = QInt{4}(0); superpose!(x)
            amplify(x; iterations = 3) do reg; flip_state!(reg, 10, 4) end
            reg_prob(ctx, x, 4, Set(10))
        end
        @test p4 ≈ exp4 atol = 1e-7

        # W=3, M=2 (mark {3,5}): θ=π/6, k=1, P = sin²(π/2) = 1 EXACTLY.
        p32 = eager(14) do ctx
            x = QInt{3}(0); superpose!(x)
            amplify(x; iterations = 1) do reg
                flip_state!(reg, 3, 3); flip_state!(reg, 5, 3)
            end
            reg_prob(ctx, x, 3, Set([3, 5]))
        end
        @test p32 ≈ 1.0 atol = 1e-9
    end

    # =====================================================================
    #  amplify — CHANNEL-LEVEL: the realized iterate equals the analytic G
    # =====================================================================
    @testset "M10.GROVER.CHANNEL — realized G(k=1) ≈ analytic D·O (up to phase)" begin
        # W=2, marked m=2. Analytic Grover iterate G = D·O in the register-value basis.
        W, m, N = 2, 2, 4
        Omat = Matrix{ComplexF64}(I, N, N); Omat[m + 1, m + 1] = -1        # flip |m⟩
        s = fill(ComplexF64(1 / 2), N); Dmat = 2 * (s * s') - I            # 2|s⟩⟨s|−I (non-broadcast: UniformScaling has no length)
        G = Dmat * Omat
        # Realized: one amplify iteration (mark m via the caller body). Sturm's
        # materialized diffusion is −D (global −1 per iteration, Born-invariant), so
        # the realized matrix = −G — matched by approx_upto_phase.
        Ureal = op_matrix(W; cap = 6) do x
            amplify(x; iterations = 1) do reg; flip_state!(reg, m, W) end
        end
        @test approx_upto_phase(Ureal, G; atol = 1e-7)
        # The diffusion operator alone equals 2|s⟩⟨s|−I (up to the global −1).
        Udiff = op_matrix(W; cap = 6) do x; _grover_diffuse!(x) end
        @test approx_upto_phase(Udiff, Dmat; atol = 1e-7)
    end

    # =====================================================================
    #  find (Grover via the Bennett oracle bridge) — end-to-end
    # =====================================================================
    @testset "M10.GROVER.FIND — Bennett-oracle marker, end-to-end" begin
        # DETERMINISTIC (N=4, M=1): the only 2-bit v with v==2 → k=1, P=1, always found.
        # cap=16 covers the Bennett comparison oracle's ancilla (probe: min 14).
        for seed in (0x11, 0x22, 0x33, 0x44)
            r = eager(16; rng = MersenneTwister(seed)) do ctx
                find(v -> v == 2, Val(2))
            end
            @test r == 2
        end
        # PROBABILISTIC (N=8, M=1): θ=asin(1/√8), k=2, P=sin²(5θ)≈0.945. A handful of
        # seeds; every return is IN RANGE and the (near-certain) successes hit the
        # solution. cap=22 covers the 3-bit comparison oracle (probe: min 20).
        hits = 0
        for seed in (0xA1, 0xA2, 0xA3, 0xA4, 0xA5)
            r = eager(22; rng = MersenneTwister(seed)) do ctx
                find(v -> v == 6, Val(3); nsolutions = 1)
            end
            @test 0 ≤ r ≤ 7
            r == 6 && (hits += 1)
        end
        @info "find N=8 M=1 (5 seeds)" hits
        @test hits ≥ 3                          # P≈0.945 ⇒ P(≥3 of 5) ≈ 0.999
    end

    # =====================================================================
    #  Grover pipeline STATISTICAL — measured success rate vs sin²((2k+1)θ)
    # =====================================================================
    @testset "M10.GROVER.STATISTICAL — amplify+measure rate ≈ sin²((2k+1)θ), ≥1000 seeded" begin
        # W=3, M=1 (mark m=6), k=2 via a CALLER phase-marking body (no Bennett) — the
        # cheap path (cap=14) that lets ≥1000 measured trials run fast. The empirical
        # success frequency must track the closed form sin²((2k+1)θ), θ=asin(√(1/8)).
        W, m, k = 3, 6, 2
        θ = asin(sqrt(1 / 8)); psucc = sin((2k + 1) * θ)^2
        @test psucc ≈ 0.9453125 atol = 1e-6
        trials = 1000; ok = 0
        for t in 1:trials
            r = eager(14; rng = MersenneTwister(hash((0x6ADE, t)))) do ctx
                x = QInt{W}(0); superpose!(x)
                amplify(x; iterations = k) do reg; flip_state!(reg, m, W) end
                Int(x)
            end
            r == m && (ok += 1)
        end
        @info "Grover amplify+measure N=8 M=1 statistical" trials ok psucc
        p̂ = ok / trials
        lb = p̂ - 2.33 * sqrt(max(p̂ * (1 - p̂), 1e-9) / trials)
        @test lb ≥ psucc - 0.05                 # empirical rate tracks sin²((2k+1)θ)
        @test p̂ ≤ psucc + 0.05
    end

    # =====================================================================
    #  interfere! — the closing Walsh–Hadamard (DJ/BV twin of superpose!)
    # =====================================================================
    @testset "M10.INTERFERE — H^⊗W involution + Deutsch–Jozsa pipeline" begin
        # superpose! then interfere! is H²=I: |0…0⟩ ↦ |0…0⟩ exactly.
        r0 = eager(4) do ctx
            x = QInt{3}(0); superpose!(x); interfere!(x); Int(x)
        end
        @test r0 == 0

        # Deutsch–Jozsa: |0⟩ⁿ, superpose!, phase-kick oracle, interfere!, measure.
        # CONSTANT f ⇒ x returns to |0⟩ (0); BALANCED f ⇒ x ≠ 0 with certainty.
        function dj(f, W)
            eager(20) do ctx
                x = QInt{W}(0); superpose!(x)
                Sturm._phase_mark_oracle!(x, v -> f(v))
                interfere!(x)
                Int(x)
            end
        end
        @test dj(v -> 0, 2) == 0                     # constant 0
        @test dj(v -> 1, 2) == 0                     # constant 1 (global phase only)
        @test dj(v -> v & 1, 2) != 0                 # balanced (LSB) ⇒ nonzero (BV s=1)
    end

    # =====================================================================
    #  phase_estimate — exact dyadic + statistical non-dyadic
    # =====================================================================
    @testset "M10.QPE.DYADIC-EXACT — φ = a/2^m ⇒ n = a exactly" begin
        # A phase gate P(2πa/2^m) has eigenstate |1⟩ with eigenphase a/2^m (dyadic).
        for (a, m) in [(3, 3), (5, 4), (1, 2), (7, 3), (11, 4), (0, 3)]
            n = eager(m + 3) do ctx
                ψ = QBool(true)
                phase_estimate(P(2π * a / (1 << m)), ψ; nbits = m)
            end
            @test n == a
        end
        @test_throws DomainError eager(4) do ctx
            phase_estimate(P(0.0), QBool(true); nbits = 0)
        end
    end

    @testset "M10.QPE.NONDYADIC-STATISTICAL — φ = 1/3, ≥1000 seeded, ±1 LSB" begin
        # φ = 1/3, nbits = 5: N·φ = 32/3 ≈ 10.667; the nearest dyadic numerator is 11
        # (11/32 ≈ 0.34375). Single-shot QPE returns the closest integer with prob
        # ≥ 4/π² ≈ 0.405 and lands within ±1 LSB with high probability (N&C §5.2.1).
        m = 5; N = 1 << m; φ = 1 / 3
        best = round(Int, N * φ)                      # = 11
        trials = 1000; within1 = 0; hitbest = 0
        for t in 1:trials
            n = eager(m + 3; rng = MersenneTwister(hash((0x3333, t)))) do ctx
                ψ = QBool(true)
                phase_estimate(P(2π * φ), ψ; nbits = m)
            end
            (mod(n - best + N ÷ 2, N) - N ÷ 2 |> abs) ≤ 1 && (within1 += 1)
            n == best && (hitbest += 1)
        end
        @info "QPE φ=1/3 statistical" trials best hitbest within1
        @test hitbest / trials ≥ 0.40                 # ≥ 4/π² (the N&C single-shot bound)
        @test within1 / trials ≥ 0.80                 # ±1 LSB captures the bulk
    end

    # =====================================================================
    #  evolve! — first/second-order Trotter of e^{−iHt}
    # =====================================================================
    @testset "M10.EVOLVE.TROTTER — commutator bound + order scaling vs expm" begin
        # H = Z⊗Z + ½ X⊗I (non-commuting: [ZZ, XI] = ab·2i·Y⊗Z, ‖·‖ = 2ab = 1).
        H = [(1.0, "ZZ"), (0.5, "XI")]; t = 1.0; W = 2
        Uex = exp(-im .* ham_mat(H) .* t)
        C = word_mat("ZZ") * (0.5 .* word_mat("XI")) - (0.5 .* word_mat("XI")) * word_mat("ZZ")
        commnorm = opnorm(C)
        @test commnorm ≈ 1.0 atol = 1e-9

        Umat(ord, r) = op_matrix(W; cap = W + 4) do x
            evolve!(x, H, t; steps = r, order = ord)
        end

        # (a) First order under the eq-(E1) commutator bound (t²/2r)·Σ‖[Hi,Hj]‖.
        r1 = 100; d1 = dist_upto_phase(Umat(1, r1), Uex)
        bound1 = t^2 / (2 * r1) * commnorm
        @test d1 ≤ bound1                             # 0.00403 ≤ 0.005 (not tuned)

        # (b) First-order SCALING O(t²/r): halving the step halves the error (≈2×).
        d1a = dist_upto_phase(Umat(1, 50), Uex)
        d1b = dist_upto_phase(Umat(1, 100), Uex)
        @test 1.8 ≤ d1a / d1b ≤ 2.2                   # the order-1 signature

        # (c) Second-order SCALING O(t³/r²): halving the step quarters the error (≈4×).
        d2a = dist_upto_phase(Umat(2, 20), Uex)
        d2b = dist_upto_phase(Umat(2, 40), Uex)
        @test 3.5 ≤ d2a / d2b ≤ 4.5                   # the order-2 signature
        @test d2b ≤ d1b                               # second order is tighter at equal r

        @test_throws DomainError op_matrix(W) do x; evolve!(x, H, t; steps = 0) end
        @test_throws DomainError op_matrix(W) do x; evolve!(x, H, t; order = 3) end
    end

    @testset "M10.EVOLVE.3Q — 3-qubit mixed word Hamiltonian vs expm" begin
        # A 3-qubit Hamiltonian with X, Y, Z words and an identity term (global phase).
        H = [(0.7, "ZZI"), (0.4, "IXX"), (0.3, "YIY"), (0.2, "III")]
        t = 0.5; W = 3
        Uex = exp(-im .* ham_mat(H) .* t)
        U = op_matrix(W; cap = W + 4) do x
            evolve!(x, H, t; steps = 80, order = 2)
        end
        @test dist_upto_phase(U, Uex) ≤ 1e-4          # second order, r=80: ~1e-5
    end

    # =====================================================================
    #  Guardrail: no measurement inside an amplify/when body (§3.5 guardrail 1)
    # =====================================================================
    @testset "M10.GUARDRAIL — a cast inside the marking body is a loud error" begin
        @test_throws Exception eager(6) do ctx
            x = QInt{2}(0); superpose!(x)
            amplify(x; iterations = 1) do reg
                when(reg[1]) do
                    Bool(reg[2])          # measurement under control — guardrail 1
                end
            end
        end
    end
end
