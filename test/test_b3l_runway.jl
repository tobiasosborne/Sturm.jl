using Test
using Sturm
using Random

# Sturm.jl-b3l — Oblivious carry runways (Gidney 1905.08488 §4 / GE21 §2.6).
#
# Tests verify the runway-at-end QRunway construction (q84) plus runway_add!.
# In this configuration (no high part above runway), the |+⟩^Cpad runway is
# invariant under classical additions — so decoded low W bits equal
# `(value + a) mod 2^W` deterministically (zero deviation for any a < 2^Wtot).
#
# Theorem 4.2's `2^{-Cpad}` deviation bound applies to the runway-in-middle
# layout (with a high part above the runway). That's a different type
# signature reserved for follow-on work; b3l ships the basic primitives.
#
# Reference: Gidney 1905.08488 §4, Definition 4.1, Theorem 4.2, Figure 2.

Random.seed!(2026)

# Build runway, decode, return low W bits.
function _runway_round_trip(W, Cpad, value)
    @context EagerContext() begin
        r = QRunway{W, Cpad}(value)
        return runway_decode!(r)
    end
end

# Build runway, add a, decode.
function _runway_add_decode(W, Cpad, value, a)
    @context EagerContext() begin
        r = QRunway{W, Cpad}(value)
        runway_add!(r, a)
        return runway_decode!(r)
    end
end

# Build runway, sequentially add many constants, decode.
function _runway_add_seq(W, Cpad, value, addends::Vector{<:Integer})
    @context EagerContext() begin
        r = QRunway{W, Cpad}(value)
        for a in addends
            runway_add!(r, a)
        end
        return runway_decode!(r)
    end
end

@testset "b3l — Oblivious carry runways (Gidney 1905.08488)" begin

    @testset "Round-trip (no addition): decode preserves value" begin
        # All single-shot decodes should yield exactly `value`.
        for (W, Cpad) in [(4, 3), (4, 2), (3, 3), (5, 2)]
            for v in 0:(1 << W - 1)
                @test _runway_round_trip(W, Cpad, v) == v
            end
        end
    end

    @testset "runway_add!: low W bits = (value + a) mod 2^W" begin
        # For runway-at-end configuration, the addition is exact mod 2^W.
        # No statistical tolerance needed (deviation = 0).
        W, Cpad = 4, 3
        for v in 0:(1 << W - 1)
            for a in 0:(1 << W - 1)
                expected = (v + a) % (1 << W)
                @test _runway_add_decode(W, Cpad, v, a) == expected
            end
        end
    end

    @testset "Adding constants > 2^W still decodes correctly" begin
        # The runway absorbs higher-order bits cleanly.
        W, Cpad = 4, 3
        Wtot = W + Cpad   # = 7 → max value = 127
        # Test a values up to 2^Wtot - 1 = 127, classical mod 2^W.
        for v in [0, 7, 15]
            for a in [16, 31, 63, 127]
                expected = (v + a) % (1 << W)
                @test _runway_add_decode(W, Cpad, v, a) == expected
            end
        end
    end

    @testset "Negative addends (subtraction via 2's complement)" begin
        W, Cpad = 4, 3
        for v in 5:10
            for a in [-1, -3, -7, -15]
                expected = mod(v + a, 1 << W)   # Julia mod gives non-negative
                @test _runway_add_decode(W, Cpad, v, a) == expected
            end
        end
    end

    @testset "Sequence of additions: net effect is sum mod 2^W" begin
        W, Cpad = 4, 3
        for trial in 1:20
            v = rand(0:(1 << W - 1))
            n_adds = rand(2:6)
            addends = rand(0:(1 << W - 1), n_adds)
            expected = mod(v + sum(addends), 1 << W)
            @test _runway_add_seq(W, Cpad, v, addends) == expected
        end
    end

    @testset "Cpad sweep: addition correctness independent of Cpad" begin
        # Theorem 4.2 says deviation ≤ 2^{-Cpad}, but in runway-at-end
        # configuration deviation is 0 regardless of Cpad. Verify across Cpad.
        W = 4
        for Cpad in 1:5
            v = 7
            a = 11
            expected = (v + a) % (1 << W)   # = 2
            for _ in 1:20
                @test _runway_add_decode(W, Cpad, v, a) == expected
            end
        end
    end

    @testset "QRunway discard! still errors (CLAUDE.md fail-loud)" begin
        @context EagerContext() begin
            r = QRunway{4, 3}(7)
            # Direct discard! errors per qrunway.jl docstring
            @test_throws ErrorException discard!(r)
            @test !r.consumed
            # The blessed cleanup path is runway_decode! (which consumes).
            v = runway_decode!(r)
            @test v == 7
            @test r.consumed
        end
    end

    @testset "Wire counts: W + Cpad total" begin
        @context EagerContext() begin
            r = QRunway{4, 3}(5)
            @test length(r) == 7         # W + Cpad
            @test length(r.reg) == 7
            v = runway_decode!(r)
            @test v == 5
        end
    end

end
