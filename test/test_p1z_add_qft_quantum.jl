# Tests for add_qft_quantum! / sub_qft_quantum! — Sturm.jl-p1z.
#
# Draper 2000 §5 "Quantum Addition" (docs/physics/draper_2000_qft_adder.pdf).
# The full two-quantum-register construction. Sturm's existing add_qft!
# (classical constant addend) is the sum-collapsed specialisation.
#
# Red-green TDD per CLAUDE.md rule 10. Verbose-flush per session-31 correction
# — every testset prints per-case progress.

using Test, Sturm
using Sturm: add_qft_quantum!, sub_qft_quantum!

@testset "p1z: add_qft_quantum! exhaustive L=3" begin

    @testset "forward: y += b on all 8×8 pairs" begin
        println(stderr, "  [p1z fwd L=3] 64 cases exhaustive"); flush(stderr)
        for y0 in 0:7, b0 in 0:7
            @context EagerContext() begin
                y = QInt{3}(y0)
                b = QInt{3}(b0)
                superpose!(y)                # → Fourier
                add_qft_quantum!(y, b)       # Φ(y0) → Φ(y0 + b0)
                interfere!(y)                # → computational
                @test Int(y) == (y0 + b0) % 8
                @test Int(b) == b0           # b preserved
            end
        end
        println(stderr, "  [p1z fwd L=3] done"); flush(stderr)
    end

    @testset "inverse: sub_qft_quantum! undoes add_qft_quantum!" begin
        println(stderr, "  [p1z inv L=3] 64 cases"); flush(stderr)
        for y0 in 0:7, b0 in 0:7
            @context EagerContext() begin
                y = QInt{3}(y0); b = QInt{3}(b0)
                superpose!(y)
                add_qft_quantum!(y, b)
                sub_qft_quantum!(y, b)      # → Φ(y0) again
                interfere!(y)
                @test Int(y) == y0
            end
        end
        println(stderr, "  [p1z inv L=3] done"); flush(stderr)
    end

    @testset "double-add: 2·add = add(2b mod 2^L)" begin
        println(stderr, "  [p1z 2x  L=3] 64 cases"); flush(stderr)
        for y0 in 0:7, b0 in 0:7
            @context EagerContext() begin
                y = QInt{3}(y0); b = QInt{3}(b0)
                superpose!(y)
                add_qft_quantum!(y, b)
                add_qft_quantum!(y, b)
                interfere!(y)
                @test Int(y) == (y0 + 2*b0) % 8
            end
        end
        println(stderr, "  [p1z 2x  L=3] done"); flush(stderr)
    end
end

@testset "p1z: add_qft_quantum! under when(ctrl) L=3" begin

    @testset "ctrl=|1⟩ → addition fires" begin
        println(stderr, "  [p1z ctrl=1] 64 cases"); flush(stderr)
        for y0 in 0:7, b0 in 0:7
            @context EagerContext() begin
                y = QInt{3}(y0); b = QInt{3}(b0); ctrl = QBool(1)
                superpose!(y)
                when(ctrl) do
                    add_qft_quantum!(y, b)
                end
                interfere!(y)
                @test Int(y) == (y0 + b0) % 8
                @test Bool(ctrl) == true
            end
        end
        println(stderr, "  [p1z ctrl=1] done"); flush(stderr)
    end

    @testset "ctrl=|0⟩ → identity" begin
        println(stderr, "  [p1z ctrl=0] 64 cases"); flush(stderr)
        for y0 in 0:7, b0 in 0:7
            @context EagerContext() begin
                y = QInt{3}(y0); b = QInt{3}(b0); ctrl = QBool(0)
                superpose!(y)
                when(ctrl) do
                    add_qft_quantum!(y, b)
                end
                interfere!(y)
                @test Int(y) == y0
                @test Bool(ctrl) == false
            end
        end
        println(stderr, "  [p1z ctrl=0] done"); flush(stderr)
    end

    # di9 tripwire: forward + inverse under ctrl=|+⟩ must leave ctrl pure
    @testset "ctrl=|+⟩: add + sub is identity — X-basis coherence" begin
        println(stderr, "  [p1z ctrl=+,add+sub] 16 cases"); flush(stderr)
        for y0 in 0:3, b0 in 0:3
            @context EagerContext() begin
                y = QInt{2}(y0); b = QInt{2}(b0); ctrl = QBool(1/2)
                superpose!(y)
                when(ctrl) do
                    add_qft_quantum!(y, b)
                    sub_qft_quantum!(y, b)
                end
                interfere!(y)
                ctrl.θ -= π/2           # Ry(-π/2): |+⟩ → |0⟩ if pure
                m = Bool(ctrl)
                @test m == false        # any X-basis leak would flip ctrl
                @test Int(y) == y0      # y unchanged
            end
        end
        println(stderr, "  [p1z ctrl=+,add+sub] done"); flush(stderr)
    end
end

@testset "p1z: add_qft_quantum! at L=4 (spot check)" begin
    # L=4 exhaustive would be 256 cases — too many for time. Spot-check.
    println(stderr, "  [p1z L=4 spot] 32 cases"); flush(stderr)
    for (y0, b0) in [(0,0), (1,1), (7,8), (15,1), (15,15), (8,8), (3,12), (11,5),
                     (0,15), (15,0), (1,14), (14,2), (5,10), (10,6), (6,9), (9,7),
                     (2,13), (13,3), (4,11), (4,12), (2,2), (7,7), (12,12), (5,5),
                     (15,14), (14,15), (0,7), (7,0), (8,15), (15,8), (3,8), (8,3)]
        @context EagerContext() begin
            y = QInt{4}(y0); b = QInt{4}(b0)
            superpose!(y)
            add_qft_quantum!(y, b)
            interfere!(y)
            @test Int(y) == (y0 + b0) % 16
        end
    end
    println(stderr, "  [p1z L=4 spot] done"); flush(stderr)
end
