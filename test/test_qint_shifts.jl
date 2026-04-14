using Sturm

# P8 shifts on QInt (Sturm.jl-9x4).
# Classical shift amount: logical shift (zero-fill), matching Julia's
# UInt semantics. `a << n` allocates a fresh QInt{W} and CNOTs the
# upper (W-n) bits of `a` into the upper bits of the target; the lower
# `n` bits stay at |0⟩. `a >> n` is the mirror. Operand preserved.
# Shifts by `n >= W` produce the all-zero register.

@testset verbose=true "P8 shifts on QInt" begin

@testset "QInt << Integer — logical left shift" begin
    # 0b0011 << 1 = 0b0110 (3 << 1 = 6, no overflow because W=4)
    @context EagerContext(capacity=15) begin
        a = QInt{4}(0b0011)
        c = a << 1
        @test Int(c) == 0b0110
        @test Int(a) == 0b0011    # preserved
    end
end

@testset "QInt >> Integer — logical right shift" begin
    # 0b1010 >> 1 = 0b0101 (10 >> 1 = 5)
    @context EagerContext(capacity=15) begin
        a = QInt{4}(0b1010)
        c = a >> 1
        @test Int(c) == 0b0101
        @test Int(a) == 0b1010    # preserved
    end
end

@testset "shift edge cases — 0, ≥W, negative" begin
    # shift by 0 is a copy
    @context EagerContext(capacity=15) begin
        a = QInt{4}(0b1010)
        c = a << 0
        @test Int(c) == 0b1010
    end
    # shift ≥ W collapses to zero
    @context EagerContext(capacity=15) begin
        a = QInt{4}(0b1111)
        c = a << 4
        @test Int(c) == 0
    end
    @context EagerContext(capacity=15) begin
        a = QInt{4}(0b1111)
        c = a >> 4
        @test Int(c) == 0
    end
    # negative shift errors (reserved for the future two-sided shift)
    @context EagerContext(capacity=15) begin
        a = QInt{4}(0b1010)
        @test_throws ErrorException a << -1
    end
end

end  # testset
