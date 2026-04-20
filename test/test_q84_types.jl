using Test
using Sturm
import Sturm: _runway_force_discard!

@testset "q84 — Type design smoke tests" begin

    @testset "QCoset construction" begin
        @context EagerContext() begin
            c = QCoset{4, 3}(7, 15)   # k=7, N=15, W=4, Cpad=3, Wtot=7
            @test c.modulus == 15
            @test length(c.reg) == 7   # Wtot = W + Cpad = 4 + 3
            @test length(c) == 7
            @test !c.consumed
            discard!(c)
            @test c.consumed
        end
    end

    @testset "QCoset validation errors" begin
        @context EagerContext() begin
            # k out of range (k >= N)
            @test_throws ErrorException QCoset{4, 3}(15, 15)
            # N too large for W
            @test_throws ErrorException QCoset{4, 3}(0, 16)
            # k negative
            @test_throws ErrorException QCoset{4, 3}(-1, 15)
            # Cpad = 0
            @test_throws ErrorException QCoset{4, 0}(current_context(), 7, 15)
        end
    end

    @testset "QCoset wire access" begin
        @context EagerContext() begin
            c = QCoset{4, 3}(7, 15)
            # Wire access via getindex: should return a QBool view
            w1 = c[1]
            @test w1 isa QBool
            @test !w1.consumed   # view, not owned
            # All 7 wires accessible
            for i in 1:7
                @test c[i] isa QBool
            end
            @test_throws ErrorException c[0]
            @test_throws ErrorException c[8]
            discard!(c)
        end
    end

    @testset "QRunway construction" begin
        @context EagerContext() begin
            r = QRunway{4, 3}(5)   # value=5, W=4, Cpad=3, Wtot=7
            @test length(r.reg) == 7
            @test length(r) == 7
            @test !r.consumed
            # discard! must error (CLAUDE.md fail-loud)
            @test_throws ErrorException discard!(r)
            @test !r.consumed   # still live after error
            # _runway_force_discard! is the safe cleanup path
            _runway_force_discard!(r)
            @test r.consumed
        end
    end

    @testset "QRunway validation errors" begin
        @context EagerContext() begin
            # value out of range
            @test_throws ErrorException QRunway{4, 3}(16)
            @test_throws ErrorException QRunway{4, 3}(-1)
            # Cpad = 0
            @test_throws ErrorException QRunway{4, 0}(current_context(), 5)
        end
    end

    @testset "QRunway wire access" begin
        @context EagerContext() begin
            r = QRunway{4, 3}(5)
            for i in 1:7
                @test r[i] isa QBool
            end
            _runway_force_discard!(r)
        end
    end

    @testset "QROMTable construction" begin
        # 2^2 = 4 entries, 4 bits wide
        tbl = QROMTable{2, 4}([0, 5, 10, 0])
        @test length(tbl.data) == 4
        @test length(tbl) == 4
        @test tbl.modulus === nothing
        @test tbl.data[1] == UInt64(0)
        @test tbl.data[2] == UInt64(5)
        @test tbl.data[3] == UInt64(10)

        # Modular canonicalisation: 15 mod 15 = 0
        tbl_mod = QROMTable{2, 4}([0, 5, 10, 15], 15)
        @test tbl_mod.modulus == 15
        @test tbl_mod.data[4] == UInt64(0)   # 15 mod 15 = 0

        # Ccmul > 20 should error and point to QROMTableLarge
        @test_throws ErrorException QROMTable{21, 4}(zeros(Int, 1 << 21))
    end

    @testset "QROMTableLarge construction" begin
        entries = collect(0:(1 << 4 - 1))   # 0..15
        tbl = QROMTableLarge{4, 8}(entries)
        @test length(tbl.data) == 16
        @test length(tbl) == 16
        @test tbl.modulus === nothing
        @test tbl.data[1] == UInt64(0)
        @test tbl.data[16] == UInt64(15)

        # Wrong length
        @test_throws ErrorException QROMTableLarge{4, 8}(collect(0:5))
    end

    @testset "QROMTable canonicalize entries" begin
        # mod-2^W reduction (no modulus)
        tbl = QROMTable{2, 4}([0, 16, 32, 48])   # all mod 16 = 0
        @test all(==(UInt64(0)), tbl.data)

        # modular canonicalisation with N=7
        tbl7 = QROMTable{3, 4}([0, 1, 2, 3, 4, 5, 6, 7], 7)
        @test tbl7.data[8] == UInt64(0)   # 7 mod 7 = 0
        @test tbl7.data[7] == UInt64(6)   # 6 mod 7 = 6
    end

    @testset "Type parameters" begin
        @context EagerContext() begin
            # QCoset type params
            c = QCoset{4, 3}(7, 15)
            @test c isa QCoset{4, 3, 7}
            @test c isa Quantum
            discard!(c)

            # QRunway type params
            r = QRunway{4, 3}(5)
            @test r isa QRunway{4, 3, 7}
            @test r isa Quantum
            _runway_force_discard!(r)
        end

        # QROMTable NOT a subtype of Quantum
        tbl = QROMTable{2, 4}([0, 1, 2, 3])
        @test !(tbl isa Quantum)
    end

    @testset "Double discard protection" begin
        @context EagerContext() begin
            c = QCoset{4, 3}(7, 15)
            discard!(c)
            @test_throws ErrorException discard!(c)
        end
    end

end
