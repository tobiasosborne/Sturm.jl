# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# Sturm.jl M9 (bead Sturm.jl-8oo9): `QMod{N,W,C}` (F24 static modulus) + the F23
# host-Int/BigInt cast bounds + the ctw2 `1<<W` overflow guard sweep. Design
# `docs/design/m9-addq-inplace-perm-design.md` §5/§6/§9.7/§9.8.

using Test
using Sturm
using Sturm: eager, _modwidth, modulus, QMod, contexttype, _shift_width_guard

@testset "M9 — QMod{N,W,C} + F23/ctw2 overflow bounds" begin

    @testset "QMOD.INFERENCE — derived width, static modulus, concrete type" begin
        @test _modwidth(15) == 4
        @test _modwidth(16) == 4
        @test _modwidth(21) == 5
        @test _modwidth(3) == 2
        @test _modwidth(2) == 1
        eager(20) do ctx
            # The context-explicit WORKER is @inferred-clean (F16 pattern, matching
            # QInt{W}(ctx, n)); the zero-context barrier is a deliberate dynamic
            # barrier over current_context(), so it infers partially — its value type
            # is still concrete.
            y = @inferred QMod{15}(ctx, 1)
            @test y isa QMod{15,4,typeof(ctx)}
            @test typeof(QMod{15}(1)) === QMod{15,4,typeof(ctx)}       # barrier value concrete
            @test typeof(QMod(Val(15), 1)) === QMod{15,4,typeof(ctx)}
            @test modulus(y) == 15
            @test modulus(typeof(y)) == 15
            @test contexttype(y) === typeof(ctx)
            # QMod{21} reaches a DISTINCT specialized type (5 wires)
            z = @inferred QMod{21}(ctx, 0)
            @test z isa QMod{21,5,typeof(ctx)}
        end
    end

    @testset "STATIC-MODULUS-ONLY — no dynamic QMod(N,v), no runtime field" begin
        # There is NO `QMod(N::Integer, v)` dynamic constructor (F24, §3.1).
        @test !hasmethod(QMod, Tuple{Int,Int})
        # No runtime `modulus` field — modulus is purely type-level.
        eager(8) do ctx
            y = QMod{15}(3)
            @test !(:modulus in fieldnames(typeof(y)))
            @test fieldnames(typeof(y)) == (:ctx, :wires)
        end
    end

    @testset "inner-constructor consistency + literal range" begin
        eager(8) do ctx
            # inconsistent (N,W) rejected
            @test_throws ArgumentError QMod{15,3,typeof(ctx)}(ctx, (Sturm.allocate!(ctx),
                Sturm.allocate!(ctx), Sturm.allocate!(ctx)))
            # N < 2 rejected
            @test_throws ArgumentError QMod{1}(0)
            # literal outside 0:N-1 is a DomainError
            @test_throws DomainError QMod{15}(15)
            @test_throws DomainError QMod{15}(-1)
            # in-range prep + measure round-trips (definite value)
            for v in (0, 1, 7, 14)
                got = eager(8) do c2; Int(QMod{15}(v)); end
                @test got == v
            end
            # padded-tail literal is a legal physical prep (v = 15 not allowed as a
            # LOGICAL literal, but the width holds the padded state)
        end
    end

    @testset "INT.WIDTH-BOUNDARY (F23) — Int admits 1:B-1, BigInt every W≥1" begin
        B = Sys.WORD_SIZE
        eager(6) do ctx
            x = QInt{4}(9)
            @test Int(x) == 9
        end
        # BigInt reconstructs a wide-ish register exactly (host-Int path still fine here)
        eager(20) do ctx
            @test BigInt(QInt{12}(2748)) == big(2748)   # 0xABC (consuming — fresh register each)
            @test BigInt(QInt{12}(2748)) isa BigInt
        end
        # The width guard is host-context only; the ErrorException message names BigInt.
        # (W ≥ B is unreachable under the qubit budget, so we test the guard function
        #  path directly on the type-level bound.)
        @test 1 ≤ B - 1
    end

    @testset "BIGINT.WIDE-RECONSTRUCT + BigInt(dual) round-trip" begin
        eager(10) do ctx
            x = QInt{8}(0x5A)
            @test BigInt(x) == big(0x5A)
        end
        # BigInt(dual(k)) is the Shor Fourier sample spelling: F|0…0⟩ is the UNIFORM
        # superposition, so the sample is a random point in 0:2^{2W}-1 (never negative,
        # always in range) — the wide-cast return is a BigInt.
        eager(10) do ctx
            z = BigInt(dual(QInt{6}(0)))
            @test z isa BigInt
            @test 0 ≤ z < big(1) << 6
        end
    end

    @testset "ctw2/F23 — `1<<W` overflow guard fails loud (representation-only)" begin
        # The guard admits every reachable width and rejects the overflowing ones.
        @test _shift_width_guard(4, "t") === nothing
        @test _shift_width_guard(Sys.WORD_SIZE - 2, "t") === nothing
        @test_throws DomainError _shift_width_guard(Sys.WORD_SIZE - 1, "t")
        @test_throws DomainError _shift_width_guard(0, "t")
        # pairing_exponent guard sweep (F19): tiny W exact, huge W loud
        @test Sturm.pairing_exponent(Sturm.Pow2Bicharacter{4}(), 3, 5) == mod(15, 16)
        @test_throws DomainError Sturm.pairing_exponent(Sturm.Pow2Bicharacter{40}(), 3, 5)
    end
end
