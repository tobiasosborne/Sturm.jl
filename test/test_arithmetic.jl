# Tests for src/library/arithmetic.jl — Draper 2000 QFT-adder and friends.
#
# TDD for Sturm.jl-ar7. Verifies:
#   superpose!(y) → add_qft!(y, a) → interfere!(y)  ==  y := (y + a) mod 2^L
# in the computational basis, for all (L, y, a) small enough to enumerate.

using Test
using Sturm

@testset "add_qft!: classical integer addition via QFT sandwich" begin

    # Exhaustive sweep at L = 2, 3, 4 — 576 cases total.
    @testset "exhaustive L=$L" for L in 2:4
        mask = (1 << L) - 1
        for y in 0:mask, a in 0:mask
            @context EagerContext() begin
                q = QInt{L}(y)
                superpose!(q)
                add_qft!(q, a)
                interfere!(q)
                @test Int(q) == (y + a) & mask
            end
        end
    end

    # Spot-check at wider L, with random draws — too many cases to enumerate.
    @testset "random L=$L" for L in (5, 6, 8)
        mask = (1 << L) - 1
        # 50 random (y, a) pairs at each L
        for _ in 1:50
            y = rand(0:mask); a = rand(0:mask)
            @context EagerContext() begin
                q = QInt{L}(y)
                superpose!(q)
                add_qft!(q, a)
                interfere!(q)
                @test Int(q) == (y + a) & mask
            end
        end
    end

    # Sanity-check that a=0 leaves y unchanged exactly.
    @testset "a=0 is identity (no net rotation)" begin
        for L in 2:6, y in (0, 1, (1 << L) - 1, rand(0:(1 << L) - 1))
            @context EagerContext() begin
                q = QInt{L}(y)
                superpose!(q)
                add_qft!(q, 0)
                interfere!(q)
                @test Int(q) == y
            end
        end
    end

    # Negative a: sub_qft! is add_qft!(-a).
    @testset "sub_qft! and negative add_qft!" begin
        L = 4; mask = (1 << L) - 1
        for y in 0:mask, a in 0:mask
            @context EagerContext() begin
                q = QInt{L}(y)
                superpose!(q)
                sub_qft!(q, a)
                interfere!(q)
                @test Int(q) == (y - a) & mask
            end
        end
    end

    # Wraparound: add_qft!(y, 2^L) should be identity (full revolution).
    @testset "wraparound a = 2^L" begin
        for L in 2:6
            @context EagerContext() begin
                q = QInt{L}(5 & ((1 << L) - 1))
                superpose!(q)
                add_qft!(q, 1 << L)
                interfere!(q)
                @test Int(q) == (5 & ((1 << L) - 1))
            end
        end
    end

    # Associativity: add(a) then add(b) == add(a+b).
    @testset "addition associativity" begin
        L = 5; mask = (1 << L) - 1
        for _ in 1:30
            y = rand(0:mask); a = rand(0:mask); b = rand(0:mask)
            @context EagerContext() begin
                q1 = QInt{L}(y)
                superpose!(q1); add_qft!(q1, a); add_qft!(q1, b); interfere!(q1)
                r1 = Int(q1)

                q2 = QInt{L}(y)
                superpose!(q2); add_qft!(q2, (a + b) & mask); interfere!(q2)
                r2 = Int(q2)

                @test r1 == r2 == (y + a + b) & mask
            end
        end
    end

    # Quantum-controlled add (Beauregard uses this inside mulmod).
    # Control = |+⟩ in superposition; output should be a uniform mixture of
    # (y, y+a mod 2^L) — measurement yields either with equal probability.
    @testset "controlled add_qft! under when(ctrl::|+⟩)" begin
        L = 3; mask = (1 << L) - 1
        for (y, a) in [(0, 3), (1, 5), (4, 7), (2, 2)]
            n_unchanged = 0; n_added = 0
            for _ in 1:400
                @context EagerContext() begin
                    q    = QInt{L}(y)
                    ctrl = QBool(1/2)            # |+⟩ control
                    superpose!(q)
                    when(ctrl) do
                        add_qft!(q, a)
                    end
                    interfere!(q)
                    result = Int(q)
                    _ = Bool(ctrl)                # collapse ctrl
                    if result == y
                        n_unchanged += 1
                    elseif result == (y + a) & mask
                        n_added += 1
                    end
                end
            end
            # ~50/50 split up to binomial noise; allow ±15% window on 400 trials.
            @test 140 <= n_unchanged <= 260
            @test 140 <= n_added     <= 260
            @test n_unchanged + n_added == 400   # nothing else appears
        end
    end
end
