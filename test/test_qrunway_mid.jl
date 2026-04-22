using Test
using Sturm
using Random

# Sturm.jl-jrl — QRunwayMid{Wlow, Cpad, Whigh}: runway-in-middle layout.
#
# Physics ground truth: Gidney 2019 arXiv:1905.08488 §4 Definition 4.1,
# Theorem 4.2, Figure 2, Figure 3.
#   docs/physics/gidney_2019_approximate_encoded_permutations.pdf
#
# Encoding (Def 4.1):
#   Register size n+m split as (low_part = p bits) + (runway = m bits)
#     + (high_part = n-p bits). Value g ∈ [0, 2^n) encoded into pair
#     (e_0, e_1) ∈ (Z/2^{p+m}) × (Z/2^{n-p}) via
#     e_0 = (g mod 2^p) + 2^p · c,
#     e_1 = (⌊g/2^p⌋ − c) mod 2^{n-p},
#   where c ∈ [0, 2^m) is the coset index (runway superposition value).
#
# Addition (Fig 3 / Def 4.1): adding classical constant k = (a) decomposes as
#   e_0 += (k mod 2^p) on the (p+m)-bit low+runway piece
#   e_1 += ⌊k / 2^p⌋ on the (n-p)-bit high piece
#   (independent — no cross-piece carry).
#
# Theorem 4.2: each approximate encoded addition has deviation ≤ 2^{-m}.
# Only the coset branch c = 2^m - 1 can deviate (via runway overflow).
#
# Decoding: measure both pieces; recover
#   g_decoded = (e_0 + 2^p · e_1) mod 2^n   (Def 4.1 f^{-1})
# This formula absorbs the runway value c correctly because
#   e_0 + 2^p · e_1 = (g mod 2^p) + 2^p · c + 2^p · (⌊g/2^p⌋ - c) = g.
#
# Sturm type parameters: Wlow ↔ p, Cpad ↔ m, Whigh ↔ n-p, Wtot = Wlow+Cpad+Whigh.

Random.seed!(2026)

# Construct + decode (no additions).
function _runway_mid_round_trip(Wlow, Cpad, Whigh, value)
    @context EagerContext() begin
        r = QRunwayMid{Wlow, Cpad, Whigh}(value)
        return runway_mid_decode!(r)
    end
end

# Construct + add a + decode.
function _runway_mid_add_decode(Wlow, Cpad, Whigh, value, a)
    @context EagerContext() begin
        r = QRunwayMid{Wlow, Cpad, Whigh}(value)
        runway_mid_add!(r, a)
        return runway_mid_decode!(r)
    end
end

# Sequential additions.
function _runway_mid_add_seq(Wlow, Cpad, Whigh, value, addends::Vector{<:Integer})
    @context EagerContext() begin
        r = QRunwayMid{Wlow, Cpad, Whigh}(value)
        for a in addends; runway_mid_add!(r, a); end
        return runway_mid_decode!(r)
    end
end

# Deviation fraction over N trials.
function _deviation_rate(Wlow, Cpad, Whigh, value, a; N=500)
    n = Wlow + Whigh
    expected = mod(value + a, 1 << n)
    dev = 0
    for _ in 1:N
        if _runway_mid_add_decode(Wlow, Cpad, Whigh, value, a) != expected
            dev += 1
        end
    end
    dev / N
end

@testset "jrl — QRunwayMid runway-in-middle (Gidney 2019 §4)" begin

    # ── Round-trip: construction is DETERMINISTIC (no deviation) ─────────────

    @testset "Round-trip: decode preserves value" begin
        # Every (Wlow, Cpad, Whigh, value) pair: decode should yield value on
        # every sample. Construction is an exact encoding (Def 4.1);
        # deviation is introduced only by ADDITIONS (Theorem 4.2).
        for (Wlow, Cpad, Whigh) in [(2, 3, 2), (3, 3, 2), (2, 4, 3), (4, 2, 4)]
            n = Wlow + Whigh
            for v in 0:(1 << n - 1)
                for _ in 1:20
                    @test _runway_mid_round_trip(Wlow, Cpad, Whigh, v) == v
                end
            end
        end
    end

    # ── Large Cpad: deviation ≤ 2^-Cpad is negligible per-trial ──────────────

    @testset "Large Cpad: single addition deterministic (deviation 2^-Cpad negligible)" begin
        # With Cpad=10, per-trial deviation ≤ 2^-10 ≈ 0.001. Over 500 trials,
        # expected deviations ≤ 0.5 → empirically near-zero (we allow 0 or 1
        # failure, very unlikely to see more).
        Wlow, Cpad, Whigh = 3, 10, 3
        n = Wlow + Whigh
        for v in [0, 5, 31, 63]
            for a in [1, 7, 17, 63]
                rate = _deviation_rate(Wlow, Cpad, Whigh, v, a; N=500)
                @test rate <= 0.01    # ≤ 1% empirical deviation rate
            end
        end
    end

    # ── Small Cpad: deviation rate ≤ 2^-Cpad within statistical tolerance ────

    @testset "Theorem 4.2 deviation bound: rate ≤ 2^-Cpad (small Cpad)" begin
        # Cpad=3 → 2^-3 = 1/8 = 12.5% upper bound on deviation.
        # Over N=1000 samples, deviations ≤ 125 expected; allow 2× slack
        # (200) for sampling variance of a Bernoulli(p ≤ 0.125) sum.
        Wlow, Cpad, Whigh = 3, 3, 3
        for v in [0, 3, 7]
            for a in [1, 5, 11]
                rate = _deviation_rate(Wlow, Cpad, Whigh, v, a; N=1000)
                @test rate <= 2.0 / (1 << Cpad)   # ≤ 2 · 2^-Cpad slack
            end
        end
    end

    # ── Wrap-around: addition spanning 2^Wlow boundary still correct ─────────

    @testset "Wrap-around across 2^Wlow boundary: parallel pieces compose" begin
        # Classically, adding a=5 to v=6 in a 6-bit register gives 11 (0b001011).
        # Here Wlow=2 (low bits = 2), Cpad=8, Whigh=4 — split add: low piece
        # gets (5 mod 4)=1 → low bits overflow from 10 to 11, carry into runway.
        # High piece gets ⌊5/4⌋=1 → high bits 01→10. Combined: 1011 = 11. ✓
        Wlow, Cpad, Whigh = 2, 8, 4
        for (v, a) in [(6, 5), (3, 14), (0, 63), (15, 48), (60, 3)]
            rate = _deviation_rate(Wlow, Cpad, Whigh, v, a; N=300)
            @test rate <= 0.05     # ≤ 5% (well below 2^-8 ≈ 0.004)
        end
    end

    # ── Theorem 4.3 (r additions): cumulative deviation ≤ (r+1)/2^m ──────────

    @testset "Theorem 4.3 cumulative deviation: r additions bounded by (r+1)/2^Cpad" begin
        # Multiple additions into the same runway. Cumulative deviation bound is
        # (r+1)/2^m per Theorem 4.3 (for a single runway). For r=5, m=8:
        # bound = 6/256 ≈ 0.023. Allow 2× slack → 0.05.
        Wlow, Cpad, Whigh = 3, 8, 3
        n = Wlow + Whigh
        for trial in 1:10
            v = rand(0:(1 << n - 1))
            addends = rand(0:(1 << n - 1), 5)
            expected = mod(v + sum(addends), 1 << n)
            dev = 0
            N = 200
            for _ in 1:N
                if _runway_mid_add_seq(Wlow, Cpad, Whigh, v, addends) != expected
                    dev += 1
                end
            end
            @test dev / N <= 0.06   # bound 6/256 + slack
        end
    end

    # ── ptrace! is blocked, decode consumes ─────────────────────────────────

    @testset "Direct ptrace! blocked; runway_mid_decode! is the blessed path" begin
        @context EagerContext() begin
            r = QRunwayMid{2, 3, 2}(5)
            @test_throws ErrorException ptrace!(r)
            @test !r.consumed
            v = runway_mid_decode!(r)
            @test v == 5
            @test r.consumed
        end
    end

    # ── Wire accounting ─────────────────────────────────────────────────────

    @testset "Length: Wlow + Cpad + Whigh wires total" begin
        @context EagerContext() begin
            r = QRunwayMid{3, 4, 2}(0)
            @test length(r) == 9   # 3 + 4 + 2
            _ = runway_mid_decode!(r)
        end
    end

end
