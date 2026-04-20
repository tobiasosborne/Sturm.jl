using Test
using Sturm
using Random

# Sturm.jl-6xi — Coset representation of modular integers (Zalka 1998 / GE21 §2.4).
#
# Tests verify the entangled-pad coset construction (see src/library/coset.jl
# and bead 8fy for the design rationale). The state is
#
#     (1/√2^Cpad) Σ_{j=0..2^Cpad-1} |j⟩_pad ⊗ |k + j·N⟩_reg
#
# Tracing out the pad leaves a uniform mixture over the 2^Cpad "comb" basis
# states `{k, k+N, ..., k+(2^Cpad-1)N}`. Therefore every measurement of the
# value register satisfies `outcome mod N == k` deterministically.
#
# Reference: Gidney 1905.08488 §3, Definition 3.1, Theorem 3.2.

Random.seed!(2026)

# Statistical helper: 3-sigma binomial tolerance.
threesigma(p::Real, n::Integer) = 3 * sqrt(p * (1 - p) / n)

# Build a fresh coset, decode, return residue.
function _coset_residue(W, Cpad, k, N)
    @context EagerContext() begin
        c = QCoset{W, Cpad}(k, N)
        return decode!(c)
    end
end

# Build a fresh coset, measure full register (don't decode), return raw integer.
function _coset_raw_value(W, Cpad, k, N)
    @context EagerContext() begin
        c = QCoset{W, Cpad}(k, N)
        ctx = c.reg.ctx
        x = Int(c.reg)                             # P2 cast — measures reg
        for w in c.pad_anc
            discard!(QBool(w, ctx, false))         # P2-clean partial trace
        end
        c.consumed = true
        return x
    end
end

# Build a coset, apply add, decode.
function _coset_add_residue(W, Cpad, k, N, a)
    @context EagerContext() begin
        c = QCoset{W, Cpad}(k, N)
        coset_add!(c, a)
        return decode!(c)
    end
end

@testset "6xi — Coset representation (Gidney 1905.08488)" begin

    @testset "Decoding preserves residue exactly (smoke)" begin
        # All single-shot decodes should yield exactly k.
        for (W, Cpad, k, N) in [(4, 3, 7, 15), (4, 3, 0, 15), (4, 3, 14, 15),
                                  (4, 2, 5, 11), (5, 3, 17, 23)]
            for _ in 1:50
                @test _coset_residue(W, Cpad, k, N) == k
            end
        end
    end

    @testset "Residue distribution is 100% k (Theorem 3.2 unmodified state)" begin
        # 2000 shots; ALL must land on residue == k.
        # The unmodified coset state never deviates — Theorem 3.2's deviation
        # bound applies to the +k operation, not to a fresh state.
        N_shots = 2000
        for (W, Cpad, k, N) in [(4, 3, 7, 15), (5, 3, 13, 23), (4, 4, 0, 13)]
            misses = 0
            for _ in 1:N_shots
                if _coset_residue(W, Cpad, k, N) != k
                    misses += 1
                end
            end
            @test misses == 0
        end
    end

    @testset "Basis states uniform within 3σ (W=4, Cpad=3, k=7, N=15)" begin
        # Expected basis states: {7, 22, 37, 52, 67, 82, 97, 112}
        # Each with probability 1/8 = 0.125.
        N_shots = 4000
        expected = Set([7, 22, 37, 52, 67, 82, 97, 112])
        hits = Dict{Int, Int}()
        for _ in 1:N_shots
            v = _coset_raw_value(4, 3, 7, 15)
            hits[v] = get(hits, v, 0) + 1
        end
        # Every observed value must be in the expected set.
        @test issubset(keys(hits), expected)
        # Each expected value within 3σ of N/8.
        p = 1/8
        tol = threesigma(p, N_shots)
        for v in expected
            count = get(hits, v, 0)
            @test abs(count/N_shots - p) <= tol
        end
    end

    @testset "coset_add! — single classical addition" begin
        # After coset_add!(c, a), decoding should yield (k + a) mod N.
        # Theorem 3.2: deviation per addition ≤ 2^{-Cpad}.
        # For N=15, Cpad=3: deviation ≤ 1/8. Use ≥1000 shots and require
        # success rate ≥ 1 - 1/8 - 3σ for the binomial.
        N_shots = 1000
        for (W, Cpad, k, N, a) in [(4, 3, 7, 15, 5),    # (7+5) mod 15 = 12
                                    (4, 3, 0, 15, 1),    # 1
                                    (4, 3, 14, 15, 2),   # (14+2) mod 15 = 1
                                    (4, 3, 5, 13, 7)]    # (5+7) mod 13 = 12
            expected = (k + a) % N
            hits = 0
            for _ in 1:N_shots
                if _coset_add_residue(W, Cpad, k, N, a) == expected
                    hits += 1
                end
            end
            success_rate = hits / N_shots
            # Generous lower bound: ≥ 1 - 2^{-Cpad} - 3σ
            min_rate = 1 - 1/(1 << Cpad) - threesigma(1 - 1/(1 << Cpad), N_shots)
            @test success_rate >= min_rate
        end
    end

    @testset "Theorem 3.2 — deviation bound scales as 2^{-Cpad}" begin
        # Sweep Cpad ∈ {2, 3, 4, 5} at fixed N=15, W=4, k=7, a=5.
        # Measured deviation should be ≤ 2^{-Cpad} (with statistical slack).
        # Note: at small Cpad the deviation is high; at larger Cpad it should drop.
        N_shots = 2000
        N = 15
        W = 4
        k = 7
        a = 5
        expected = (k + a) % N
        for Cpad in 2:5
            misses = 0
            for _ in 1:N_shots
                @context EagerContext() begin
                    c = QCoset{W, Cpad}(k, N)
                    coset_add!(c, a)
                    r = decode!(c)
                    if r != expected
                        misses += 1
                    end
                end
            end
            deviation = misses / N_shots
            bound = 1 / (1 << Cpad)   # 2^{-Cpad}
            # Allow 3σ slack: deviation ≤ bound + 3σ_p where p = bound
            slack = threesigma(bound, N_shots)
            @test deviation <= bound + slack
        end
    end

    @testset "Pad ancillae count: W + 2·Cpad internal qubits" begin
        # Verify the implementation uses W + 2*Cpad qubits internally.
        # Use tracing context to count high-water-mark wire allocations.
        @context TracingContext() begin
            c = QCoset{4, 3}(7, 15)
            ctx = c.reg.ctx
            # reg holds W+Cpad = 7 wires; pad_anc holds Cpad = 3 ancillae.
            # Total = 10 wires allocated.
            @test length(c.pad_anc) == 3
            @test length(c.reg) == 7
            discard!(c)
        end
    end

    @testset "Round-trip: encode → decode preserves k" begin
        # Exhaustive over (k, N) pairs at W=4, Cpad=2.
        for N in [11, 13, 15]
            for k in 0:(N-1)
                @test _coset_residue(4, 2, k, N) == k
            end
        end
    end
end
