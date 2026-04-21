using Test
using Sturm

# HEADLINE TEST: 3-qubit bit-flip QECC with mid-circuit syndrome extraction +
# CLASSICAL correction logic, all running through the HardwareContext
# round-trip path.
#
# Algorithm (Nielsen & Chuang §10.1.1):
#   Encode |ψ⟩ = α|0⟩ + β|1⟩  →  α|000⟩ + β|111⟩  (two CNOTs)
#   Inject one X error on qubit e ∈ {0, 1, 2, none}
#   Syndrome extraction:
#     a1 ⊻= q0; a1 ⊻= q1     → s1 = (q0 ⊕ q1) parity
#     a2 ⊻= q1; a2 ⊻= q2     → s2 = (q1 ⊕ q2) parity
#   Mid-circuit measurement: s1, s2 ∈ Bool
#   Classical correction lookup:
#     (1, 0) → flip q0
#     (1, 1) → flip q1
#     (0, 1) → flip q2
#     (0, 0) → no flip
#   Decode (reverse encode), measure logical bit, verify recovery.
#
# This proves the round-trip + classical-feedback architecture works end-to-
# end. It exercises mid-circuit measurement (s1, s2 in the middle of a longer
# circuit), classical Julia control flow on quantum results, and continued
# coherent operations on the data qubits after measurement.

# Encode |q⟩ as a 3-qubit repetition codeword across (q, b1, b2) which start in |0⟩.
function _encode_repetition!(q::QBool, b1::QBool, b2::QBool)
    b1 ⊻= q
    b2 ⊻= q
end

# Reverse the encoder. After this q is the logical bit; b1, b2 should be |0⟩.
function _decode_repetition!(q::QBool, b1::QBool, b2::QBool)
    b2 ⊻= q
    b1 ⊻= q
end

# Run a full encode-error-syndrome-correct-decode cycle. Returns the
# recovered logical bit. `inject_err` ∈ {0, 1, 2, -1 = no error}.
function _bit_flip_cycle(p::Real, inject_err::Int)
    qs_data = [QBool(p), QBool(0), QBool(0)]   # logical, then 2 zeros
    _encode_repetition!(qs_data[1], qs_data[2], qs_data[3])

    # Inject error
    inject_err in (0, 1, 2) && X!(qs_data[inject_err + 1])

    # Syndrome extraction
    a1 = QBool(0)
    a2 = QBool(0)
    a1 ⊻= qs_data[1]; a1 ⊻= qs_data[2]
    a2 ⊻= qs_data[2]; a2 ⊻= qs_data[3]
    s1 = Bool(a1)   # round-trip
    s2 = Bool(a2)   # round-trip

    # Classical correction
    if s1 && !s2
        X!(qs_data[1])
    elseif s1 && s2
        X!(qs_data[2])
    elseif !s1 && s2
        X!(qs_data[3])
    end

    # Decode
    _decode_repetition!(qs_data[1], qs_data[2], qs_data[3])

    # Measure logical
    logical = Bool(qs_data[1])
    discard!(qs_data[2])
    discard!(qs_data[3])
    return logical
end

@testset "3-qubit bit-flip QECC via HardwareContext (HW6 HEADLINE)" begin

    function _hw(; capacity=8)
        sim = Sturm.IdealisedSimulator(; capacity=capacity)
        return Sturm.HardwareContext(Sturm.InProcessTransport(sim); capacity=capacity)
    end

    @testset "Logical |0⟩ recovers under any single-bit-flip error" begin
        ctx = _hw(; capacity=8)
        @context ctx begin
            for err in (-1, 0, 1, 2)
                # Multiple shots (logical |0⟩ is deterministic, but exercise
                # repeated flushes / round-trips).
                for _ in 1:20
                    @test _bit_flip_cycle(0.0, err) === false
                end
            end
        end
        close(ctx)
    end

    @testset "Logical |1⟩ recovers under any single-bit-flip error" begin
        ctx = _hw(; capacity=8)
        @context ctx begin
            for err in (-1, 0, 1, 2)
                for _ in 1:20
                    @test _bit_flip_cycle(1.0, err) === true
                end
            end
        end
        close(ctx)
    end

    @testset "Round-trip count: 2 measurements per cycle (2 flushes)" begin
        sim = Sturm.IdealisedSimulator(; capacity=8, gate_time_ms=1.0)
        ctx = Sturm.HardwareContext(Sturm.InProcessTransport(sim); capacity=8)
        @context ctx begin
            d0 = ctx.total_duration_ms
            _bit_flip_cycle(0.0, 1)         # inject error on qubit 1
            d1 = ctx.total_duration_ms
            # 2 syndrome measurements + 1 final logical measurement = 3 flushes
            # total. Total gates: encode (2 cx) + error (1 ry) + syndrome
            # (4 cx) + correction (1 ry, since err=1 produces s1=1,s2=1 → flip q1)
            # + decode (2 cx) = 10 gates → 10ms.
            @test d1 - d0 ≈ 10.0
        end
        close(ctx)
    end

    @testset "Capacity 16: full GE21-spec device handles the algorithm" begin
        ctx = _hw(; capacity=16)
        @context ctx begin
            for err in (-1, 0, 1, 2), p in (0.0, 1.0)
                expected = (p == 1.0)
                for _ in 1:5
                    @test _bit_flip_cycle(p, err) === expected
                end
            end
        end
        close(ctx)
    end
end
