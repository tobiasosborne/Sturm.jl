# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# Sturm.jl M9 (bead Sturm.jl-8oo9): `mulmod!` — the FULL-SPACE modular
# multiplication permutation (design §2, closes F7). Bijectivity is checked at the
# PERMUTATION level (a `Perm` is a canonical 0/1 matrix — exhaustive basis
# agreement IS the Choi-level check for a phase-free permutation), plus quantum
# execution on the EagerContext (in-place replace, clean scratch, controlled).
# Design §9.1/§9.3/§9.4. `inplace_data_perm` comes from test_m9_inplace.jl (same
# Main scope, included earlier in runtests.jl).

using Test
using Sturm
using Bennett
using Sturm: mulmod!, QMod, eager, _get_mulmod_perm, _ideal_mulmod_perm, when, QBool

@testset "M9 — mulmod! full-space permutation (§2, §9.1/§9.4)" begin

    # The design's (c, N) matrix, restricted to Bennett-compilable widths W ≤ 4
    # (Bennett v0.5 cannot narrow `*`/`%` at W ≥ 5 — see the deviation note): power-
    # of-two tail-empty cases (3,16) and non-trivial tails (2,15),(4,15),(7,15),
    # (14,15),(2,5),(8,5),(2,3),(8,3).
    CN = [(2, 3), (2, 5), (2, 15), (4, 15), (7, 15), (14, 15), (3, 16), (8, 3), (8, 5)]

    @testset "MULMOD.FULL-SPACE-BIJECTION — π is a permutation matching eq (1)" begin
        for (c, N) in CN
            W = ndigits(N - 1; base = 2)
            c̄ = mod(c, N)
            cp = _get_mulmod_perm(Val(N), Val(W), c̄)
            dp = inplace_data_perm(cp, W)               # data-block map, clean scratch asserted
            ideal = _ideal_mulmod_perm(N, W, c̄)
            @test dp == ideal
            @test sort(dp) == collect(0:((1 << W) - 1))  # a genuine permutation (P†P = I)
            @test all(dp[v + 1] == v for v in N:((1 << W) - 1))            # tail fixed
            @test all(dp[v + 1] == Int(mod(big(c̄) * v, N)) for v in 0:(N - 1))  # logical block
            # inverse pair π_d ∘ π_c = id
            d = invmod(c̄, N)
            dpd = inplace_data_perm(_get_mulmod_perm(Val(N), Val(W), d), W)
            @test all(dpd[dp[v + 1] + 1] == v for v in 0:((1 << W) - 1))
            @test all(dp[dpd[v + 1] + 1] == v for v in 0:((1 << W) - 1))
        end
    end

    @testset "N=15 explicit regression — π(0)=0, π(15)=15 (collision removed)" begin
        cp = _get_mulmod_perm(Val(15), Val(4), 2)
        dp = inplace_data_perm(cp, 4)
        @test dp[0 + 1] == 0
        @test dp[15 + 1] == 15
        @test dp == [0, 2, 4, 6, 8, 10, 12, 14, 1, 3, 5, 7, 9, 11, 13, 15]
    end

    @testset "MULMOD.OVERFLOW-FREE-REFERENCE — cross-check vs BigInt reference" begin
        for (c, N) in CN
            W = ndigits(N - 1; base = 2)
            dp = inplace_data_perm(_get_mulmod_perm(Val(N), Val(W), mod(c, N)), W)
            ref = [v < N ? Int(mod(big(mod(c, N)) * v, N)) : v for v in 0:((1 << W) - 1)]
            @test dp == ref
        end
    end

    @testset "MULMOD.NONUNIT-FAILS-BEFORE-ACTION — loud DomainError naming gcd" begin
        for (c, N) in ((3, 15), (5, 15), (2, 10))
            eager(8) do ctx
                y = QMod{N}(1)
                err = try; mulmod!(y, c); nothing; catch e; e; end
                @test err isa DomainError
                msg = sprint(showerror, err)
                @test occursin("gcd", msg)
                @test occursin("$N", msg)
                # the register is untouched — still measures its prepared value
                @test Int(y) == 1
            end
        end
        # N < 2 rejected
        eager(4) do ctx
            @test_throws DomainError mulmod!(QMod{2}(1), 0)   # gcd(0,2)=2
        end
    end

    @testset "IN-PLACE-REPLACE + CLEAN-SCRATCH — quantum execution, all basis inputs" begin
        # Small feasible widths (N=15's 2^21+ statevector is verified at the Perm
        # level above; here we exercise the apply choreography + scratch release).
        for (c, N) in ((2, 5), (8, 5), (2, 3), (8, 3))
            W = ndigits(N - 1; base = 2)
            c̄ = mod(c, N)
            cp = _get_mulmod_perm(Val(N), Val(W), c̄)
            cap = W + cp.scratch_width + 2        # y + scratch (+ headroom)
            # Only LOGICAL inputs 0:N-1 are preparable via the QMod{N} literal cast;
            # the padded-tail identity (v ≥ N) is verified at the Perm level above.
            for v in 0:(N - 1)
                got = eager(cap) do ctx
                    y = QMod{N}(v)
                    y2 = mulmod!(y, c)
                    @test y2 === y                # in-place: same handle
                    Int(y)                        # scratch already freed at region exit
                end
                @test got == Int(mod(big(c̄) * v, N))
            end
        end
    end

    @testset "CONTROLLED — when(ctrl) do mulmod!(y,c) end fires only on |1⟩" begin
        c, N, W = 2, 5, 3
        cp = _get_mulmod_perm(Val(N), Val(W), c)
        cap = 1 + W + cp.scratch_width + 4        # control + y + scratch + ctrl borrow
        for cv in (false, true), v in (1, 3)
            got = eager(cap) do ctx
                ctrl = QBool(cv)
                y = QMod{N}(v)
                when(ctrl) do
                    mulmod!(y, c)
                end
                @test Bool(ctrl) == cv            # control preserved
                Int(y)
            end
            @test got == (cv ? Int(mod(big(c) * v, N)) : v)
        end
    end

    @testset "MBU-EXCLUDED (§3.4) — the artifact is a phase-free Perm" begin
        cp = _get_mulmod_perm(Val(15), Val(4), 2)
        @test cp.perm isa Sturm.Perm
        @test all(g -> g isa Sturm.MCX, cp.perm.gates)   # no measurement node can cross
    end
end
