using Sturm

# P8 bitwise ops on QInt (Sturm.jl-r9i).
# Semantics mirror QBool.xor: primitive-level operations mutate the left
# operand and preserve the right. ⊻ reduces to W parallel CNOTs
# (primitive 4); & and | use ancilla bits because AND/OR are not
# reversible in place.

@testset verbose=true "P8 bitwise ops on QInt" begin

@testset "QInt ⊻ QInt — bitwise XOR via parallel CNOT" begin
    # 0b1010 ⊻ 0b0110 = 0b1100 (10 ⊻ 6 = 12)
    @context EagerContext(capacity=20) begin
        a = QInt{4}(0b1010)
        b = QInt{4}(0b0110)
        c = a ⊻ b
        @test Int(c) == 0b1100    # consumes c (= mutated a)
        @test Int(b) == 0b0110    # b preserved — CNOT semantic
    end
end

@testset "QInt ⊻ Integer — X on set bits (P8 promotion)" begin
    # Classical operand is a known constant; bits set to 1 get an X gate.
    # No ancilla, no entanglement.
    @context EagerContext(capacity=10) begin
        a = QInt{4}(0b1010)
        c = a ⊻ 0b0110
        @test Int(c) == 0b1100
    end
end

@testset "Integer ⊻ QInt — fresh QInt via promotion+CNOT" begin
    # Mirrors QBool's (Bool, QBool) pattern: prepare a fresh QInt from the
    # classical, then CNOT the quantum operand into it. Quantum operand
    # is preserved (used only as control).
    @context EagerContext(capacity=20) begin
        b = QInt{4}(0b0110)
        c = 0b1010 ⊻ b
        @test Int(c) == 0b1100
        @test Int(b) == 0b0110    # b preserved
    end
end

@testset "QInt & QInt — bitwise AND via Toffoli into fresh register" begin
    # AND is not reversible in place. Standard construction: fresh W-wire
    # register c at |0⟩, then Toffoli(a_i, b_i, c_i) makes c_i = a_i ∧ b_i.
    # Both a and b are preserved (used as Toffoli controls only).
    @context EagerContext(capacity=20) begin
        a = QInt{4}(0b1010)
        b = QInt{4}(0b0110)
        c = a & b
        @test Int(c) == 0b0010    # 10 & 6 = 2
        @test Int(a) == 0b1010    # a preserved
        @test Int(b) == 0b0110    # b preserved
    end
end

@testset "QInt & Integer — CNOT from a to fresh, only where bit set" begin
    # Classical operand has known bits. For each bit i where the classical
    # value is 1, CNOT a_i into the fresh target — no Toffoli needed since
    # the classical control is a known constant, not a qubit.
    @context EagerContext(capacity=15) begin
        a = QInt{4}(0b1010)
        c = a & 0b0110
        @test Int(c) == 0b0010
        @test Int(a) == 0b1010    # a preserved
    end
end

@testset "Integer & QInt — commutes with QInt & Integer" begin
    @context EagerContext(capacity=15) begin
        b = QInt{4}(0b0110)
        c = 0b1010 & b
        @test Int(c) == 0b0010
        @test Int(b) == 0b0110    # b preserved
    end
end

@testset "QInt | QInt — bitwise OR via a⊕b⊕ab (2 CNOT + 1 Toffoli per bit)" begin
    # a ∨ b = a ⊕ b ⊕ (a ∧ b). Preserves both operands; no X gates, no
    # un-compute. Fresh target starts at |0⟩.
    @context EagerContext(capacity=20) begin
        a = QInt{4}(0b1010)
        b = QInt{4}(0b0110)
        c = a | b
        @test Int(c) == 0b1110    # 10 | 6 = 14
        @test Int(a) == 0b1010
        @test Int(b) == 0b0110
    end
end

@testset "QInt | Integer — X where classical is 1, CNOT where classical is 0" begin
    # Classical bit = 1 forces the result bit to 1 (X on fresh |0⟩);
    # classical bit = 0 lets the result bit equal a_i (CNOT from a).
    @context EagerContext(capacity=15) begin
        a = QInt{4}(0b1010)
        c = a | 0b0110
        @test Int(c) == 0b1110
        @test Int(a) == 0b1010
    end
end

@testset "Integer | QInt — commutes with QInt | Integer" begin
    @context EagerContext(capacity=15) begin
        b = QInt{4}(0b0110)
        c = 0b1010 | b
        @test Int(c) == 0b1110
        @test Int(b) == 0b0110
    end
end

end  # testset
