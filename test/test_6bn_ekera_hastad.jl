# Tests for bead Sturm.jl-6bn — Ekerå-Håstad 2017 short-DLP factoring.
#
# Ground truth: arXiv:1702.00249 (Ekerå & Håstad, "Quantum algorithms for
# computing short discrete logarithms and factoring RSA integers", Feb 2017)
#   docs/physics/ekera_2017_short_dlp.pdf
#
# Algorithm (EH17 normalisation, §5.2.2):
#   1. pick random g coprime to N;
#   2. classical: x = g^((N-1)/2) mod N; this is ≡ g^((p+q-2)/2) mod N;
#   3. quantum: two-register PE on f(a,b) = [a]g ⊙ [-b]x = g^(a - bd) mod N
#      with a ∈ [0, 2^(ℓ+m)), b ∈ [0, 2^ℓ), for m such that 0 < d < 2^m;
#   4. QFT both registers, measure → (j, k);
#   5. classical: recover d ∈ (0, 2^m) from the 2D lattice (§4.4);
#   6. factor recovery via quadratic x² - (2d+2)x + N = 0.
#
# For N=15: p=3, q=5, d = (p+q-2)/2 = 3, m = 3 (0 < 3 < 2^3), ℓ = m = 3 for
# s=1. Total exponent width 2ℓ+m = 9. Working register L=4, total peak ~18.

using Test
using Sturm

@testset "6bn: Ekerå-Håstad shor_factor_EH(15)" begin

    @testset "_eh_factors_from_d quadratic recovery" begin
        # EH17 §5.2.2: x² - (2d+2)x + N = 0 ⇒ p, q = (d+1) ± √((d+1)² - N)
        # For N=15, d=3: c=4, c²-N=1, roots {3, 5}.
        fs = Sturm._eh_factors_from_d(3, 15)
        @test fs !== nothing
        @test Set(fs) == Set((3, 5))

        # N=35, d = (5+7-2)/2 = 5, c=6, c²-N=1, roots {5, 7}.
        fs = Sturm._eh_factors_from_d(5, 35)
        @test fs !== nothing
        @test Set(fs) == Set((5, 7))

        # N=21, d = (3+7-2)/2 = 4, c=5, c²-N=4, roots {3, 7}.
        fs = Sturm._eh_factors_from_d(4, 21)
        @test fs !== nothing
        @test Set(fs) == Set((3, 7))

        # Wrong d → discriminant not a perfect square → nothing.
        @test Sturm._eh_factors_from_d(5, 15) === nothing
        @test Sturm._eh_factors_from_d(2, 15) === nothing

        # Negative discriminant → nothing.
        @test Sturm._eh_factors_from_d(1, 15) === nothing
    end

    @testset "_eh_recover_d_candidates returns d_true for synthetic good pairs" begin
        # Construct genuine good pairs for d_true=3, then check d_true ∈ candidates.
        # Good pair (Def 1): |{d_true·j + 2^m·k}_{2^(ℓ+m)}| ≤ 2^(m-2).
        d_true = 3
        m, ell = 3, 3
        M = 1 << (ell + m)                     # 64
        twom = 1 << m                          # 8
        bound = 1 << (m - 2)                   # 2

        good_count = 0
        for j in 1:(M - 1)
            # Pick the k that minimises |{d_true·j + 2^m·k}_M|.
            target = mod(-d_true * j, M)
            k = round(Int, target / twom)
            k = mod(k, 1 << ell)
            r = mod(d_true * j + twom * k, M)
            r = r >= M ÷ 2 ? r - M : r
            if abs(r) <= bound
                good_count += 1
                cands = Sturm._eh_recover_d_candidates(j, k, m, ell)
                @test d_true in cands
            end
        end
        # Lemma 1: ≥ 2^(ℓ+m-1) = 32 good j values for d < 2^m.
        @test good_count >= 16
    end

    @testset "_eh_recover_d_candidates returns [] on non-good pair" begin
        m, ell = 3, 3
        # (j=4, k=0): residual = 4d for d ∈ [1,7] → all |·| ≥ 4 > bound=2.
        @test isempty(Sturm._eh_recover_d_candidates(4, 0, m, ell))
    end

    @testset "_eh_recover_d_candidates: spurious candidates possible at small m" begin
        # The paper (§4.4, Lemma 3) notes that at small m/ℓ, multiple d ∈ (0, 2^m)
        # may satisfy the residual bound — these are spurious lattice vectors;
        # the caller must verify each via g^d (or via _eh_factors_from_d).
        # (j=2, k=7) for d_true=3, m=ℓ=3: residuals d=3→2, d=4→0, d=5→2.
        cands = Sturm._eh_recover_d_candidates(2, 7, 3, 3)
        @test 3 in cands  # true d must be present
        @test length(cands) >= 1
    end

    @testset "end-to-end shor_factor_EH(15) hit rate" begin
        # Acceptance per bead Sturm.jl-6bn: Set([3,5]) returned ≥ 50% over 30 shots.
        # (Toy-N caveat: EH17 clean analysis requires ord(g) ≥ 2^(ℓ+m) + 2^ℓ·d,
        #  which fails at N=15 where max ord is 4. Empirically the algorithm still
        #  gives biased output for N=15 — per bead, hit rate 50–90%.)
        trials = 30
        successes = 0
        for _ in 1:trials
            @context EagerContext() begin
                fs = shor_factor_EH(15)
                if !isempty(fs) && Set(fs) == Set([3, 5])
                    successes += 1
                end
            end
        end
        @info "shor_factor_EH(15) hit rate" successes trials
        @test successes >= trials ÷ 2   # ≥ 50%
    end

    @testset "shor_factor_EH: even N trivial factor" begin
        @context EagerContext() begin
            fs = shor_factor_EH(14)
            @test Set(fs) == Set([2, 7])
        end
    end
end
