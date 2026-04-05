using Test
using Sturm: OrkanStateRaw, OrkanKrausRaw, OrkanSuperopRaw,
             ORKAN_PURE, ORKAN_MIXED_PACKED, ORKAN_MIXED_TILED,
             orkan_state_init!, orkan_state_free!, orkan_state_len,
             orkan_state_get, orkan_state_set!, orkan_state_plus!,
             orkan_x!, orkan_y!, orkan_z!, orkan_h!,
             orkan_s!, orkan_sdg!, orkan_t!, orkan_tdg!,
             orkan_rx!, orkan_ry!, orkan_rz!, orkan_p!,
             orkan_cx!, orkan_cy!, orkan_cz!, orkan_swap!, orkan_ccx!,
             orkan_kraus_to_superop, orkan_superop_free!,
             OrkanState, n_qubits, state_length, probabilities, sample

@testset "Orkan FFI" begin

    @testset "Struct sizes" begin
        @test sizeof(OrkanStateRaw) == 24
        @test sizeof(OrkanSuperopRaw) == 16
        @test sizeof(OrkanKrausRaw) == 24
    end

    @testset "State init/free" begin
        s = OrkanStateRaw(ORKAN_PURE)
        orkan_state_init!(s, 1)
        @test s.data != C_NULL
        @test s.qubits == 1
        @test orkan_state_len(s) == 2
        orkan_state_free!(s)
        @test s.data == C_NULL
        @test s.qubits == 0
        # Double free is safe
        orkan_state_free!(s)
    end

    @testset "State get/set" begin
        s = OrkanStateRaw(ORKAN_PURE)
        orkan_state_init!(s, 1)
        # Starts zeroed
        @test orkan_state_get(s, 0, 0) == 0.0 + 0.0im
        # Set |0> amplitude
        orkan_state_set!(s, 0, 0, 1.0 + 0.0im)
        @test orkan_state_get(s, 0, 0) ≈ 1.0 + 0.0im
        @test orkan_state_get(s, 1, 0) ≈ 0.0 + 0.0im
        orkan_state_free!(s)
    end

    @testset "State plus" begin
        s = OrkanStateRaw(ORKAN_PURE)
        orkan_state_plus!(s, 2)
        @test s.qubits == 2
        @test orkan_state_len(s) == 4
        amp = 1.0 / sqrt(4.0)
        for i in 0:3
            @test abs(orkan_state_get(s, i, 0) - amp) < 1e-12
        end
        orkan_state_free!(s)
    end

    @testset "X gate" begin
        s = OrkanStateRaw(ORKAN_PURE)
        orkan_state_init!(s, 1)
        orkan_state_set!(s, 0, 0, 1.0 + 0.0im)  # |0>
        orkan_x!(s, 0)  # X|0> = |1>
        @test abs2(orkan_state_get(s, 0, 0)) < 1e-20
        @test abs2(orkan_state_get(s, 1, 0)) ≈ 1.0
        orkan_state_free!(s)
    end

    @testset "Hadamard gate" begin
        s = OrkanStateRaw(ORKAN_PURE)
        orkan_state_init!(s, 1)
        orkan_state_set!(s, 0, 0, 1.0 + 0.0im)  # |0>
        orkan_h!(s, 0)  # H|0> = |+>
        @test abs(orkan_state_get(s, 0, 0) - 1/√2) < 1e-12
        @test abs(orkan_state_get(s, 1, 0) - 1/√2) < 1e-12
        orkan_state_free!(s)
    end

    @testset "Ry gate" begin
        s = OrkanStateRaw(ORKAN_PURE)
        orkan_state_init!(s, 1)
        orkan_state_set!(s, 0, 0, 1.0 + 0.0im)  # |0>
        orkan_ry!(s, 0, π)  # Ry(π)|0> = |1>
        @test abs2(orkan_state_get(s, 0, 0)) < 1e-20
        @test abs2(orkan_state_get(s, 1, 0)) ≈ 1.0 atol=1e-12
        orkan_state_free!(s)
    end

    @testset "CX gate (Bell state)" begin
        s = OrkanStateRaw(ORKAN_PURE)
        orkan_state_init!(s, 2)
        orkan_state_set!(s, 0, 0, 1.0 + 0.0im)  # |00>
        orkan_h!(s, 0)    # H on qubit 0 → |+0>
        orkan_cx!(s, 0, 1)  # CX → Bell state (|00>+|11>)/√2
        @test abs2(orkan_state_get(s, 0, 0)) ≈ 0.5 atol=1e-12  # |00>
        @test abs2(orkan_state_get(s, 1, 0)) < 1e-20             # |01>
        @test abs2(orkan_state_get(s, 2, 0)) < 1e-20             # |10>
        @test abs2(orkan_state_get(s, 3, 0)) ≈ 0.5 atol=1e-12  # |11>
        orkan_state_free!(s)
    end

    @testset "Rz gate" begin
        s = OrkanStateRaw(ORKAN_PURE)
        orkan_state_init!(s, 1)
        orkan_state_set!(s, 0, 0, 1.0 + 0.0im)
        orkan_h!(s, 0)   # |+>
        orkan_rz!(s, 0, π)  # Rz(π)|+> = |->  (up to global phase)
        # |-> = (|0> - |1>)/√2, but Rz gives phase: e^{-iπ/2}|0> + e^{iπ/2}|1>)/√2
        # which is -i(|0> - |1>)/√2. The relative phase between |0> and |1> is π.
        a0 = orkan_state_get(s, 0, 0)
        a1 = orkan_state_get(s, 1, 0)
        @test abs2(a0) ≈ 0.5 atol=1e-12
        @test abs2(a1) ≈ 0.5 atol=1e-12
        # Relative phase should be π (a1/a0 ≈ -1 up to global phase)
        @test abs(a1/a0 + 1.0) < 1e-12 || abs(a1/a0 - (-1.0)) < 1e-12
        orkan_state_free!(s)
    end

    @testset "Toffoli (CCX) gate" begin
        # Orkan convention: qubit 0 = LSB of basis state index
        # ccx(c1=0, c2=1, target=2): flip qubit 2 when qubits 0 AND 1 are both |1>
        # |011> = index 3 (q0=1, q1=1, q2=0) → should flip q2 → |111> = index 7
        s = OrkanStateRaw(ORKAN_PURE)
        orkan_state_init!(s, 3)
        orkan_state_set!(s, 0b011, 0, 1.0 + 0.0im)  # |011>: q0=1, q1=1
        orkan_ccx!(s, 0, 1, 2)  # flip q2 → |111>
        @test abs2(orkan_state_get(s, 0b111, 0)) ≈ 1.0 atol=1e-12
        orkan_state_free!(s)
    end

    @testset "Swap gate" begin
        s = OrkanStateRaw(ORKAN_PURE)
        orkan_state_init!(s, 2)
        orkan_state_set!(s, 0b01, 0, 1.0 + 0.0im)  # |01>
        orkan_swap!(s, 0, 1)  # → |10>
        @test abs2(orkan_state_get(s, 0b10, 0)) ≈ 1.0 atol=1e-12
        orkan_state_free!(s)
    end

    @testset "Kraus → superop (identity channel)" begin
        # Single Kraus operator = 2x2 identity, row-major
        data = ComplexF64[1, 0, 0, 1]
        kraus = OrkanKrausRaw(
            UInt8(1),
            ntuple(_ -> UInt8(0), 7),
            UInt64(1),
            pointer(data)
        )
        sop = orkan_kraus_to_superop(kraus)
        @test sop.data != C_NULL
        @test sop.n_qubits == 1
        orkan_superop_free!(sop)
    end

    @testset "OrkanState managed handle" begin
        s = OrkanState(ORKAN_PURE, 2)
        @test n_qubits(s) == 2
        @test state_length(s) == 4
        # Set Bell state manually
        s[0] = 1/√2
        s[3] = 1/√2
        probs = probabilities(s)
        @test probs[1] ≈ 0.5 atol=1e-12  # |00>
        @test probs[2] ≈ 0.0 atol=1e-12  # |01>
        @test probs[3] ≈ 0.0 atol=1e-12  # |10>
        @test probs[4] ≈ 0.5 atol=1e-12  # |11>
    end

    @testset "OrkanState via gates" begin
        s = OrkanState(ORKAN_PURE, 2)
        s[0] = 1.0  # |00>
        orkan_h!(s.raw, 0)
        orkan_cx!(s.raw, 0, 1)
        probs = probabilities(s)
        @test probs[1] ≈ 0.5 atol=1e-12
        @test probs[4] ≈ 0.5 atol=1e-12
    end

    @testset "OrkanState sampling" begin
        s = OrkanState(ORKAN_PURE, 1)
        s[0] = 1/√2
        s[1] = 1/√2
        # Sample 1000 times, should be roughly 50/50
        counts = zeros(Int, 2)
        for _ in 1:1000
            counts[sample(s) + 1] += 1
        end
        @test 350 < counts[1] < 650
        @test 350 < counts[2] < 650
    end
end
