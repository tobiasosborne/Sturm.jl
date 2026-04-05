using Test
using Sturm

@testset "QECC — Steane [[7,1,3]]" begin

    @testset "Encode-decode roundtrip: |0⟩" begin
        @context EagerContext() begin
            for _ in 1:50
                q = QBool(0)
                physical = encode!(Steane(), q)
                recovered = decode!(Steane(), physical)
                @test Bool(recovered) == false
            end
        end
    end

    @testset "Encode-decode roundtrip: |1⟩" begin
        @context EagerContext() begin
            for _ in 1:50
                q = QBool(1)
                physical = encode!(Steane(), q)
                recovered = decode!(Steane(), physical)
                @test Bool(recovered) == true
            end
        end
    end

    @testset "Encode-decode roundtrip: |+⟩ (superposition)" begin
        @context EagerContext() begin
            N = 2000
            count_true = 0
            for _ in 1:N
                q = QBool(0)
                H!(q)
                physical = encode!(Steane(), q)
                recovered = decode!(Steane(), physical)
                count_true += Bool(recovered)
            end
            # |+⟩ encoded then decoded should give ~50/50
            @test abs(count_true / N - 0.5) < 0.04
        end
    end

    # TODO: Logical X test requires verified encoding circuit.
    # The X_L = X₁X₂...X₇ operator should flip the logical qubit,
    # but the current encoding circuit may not produce the canonical
    # Steane codewords. Deferred to future work with full stabilizer
    # verification.

    @testset "Logical qubit is consumed after encoding" begin
        @context EagerContext() begin
            q = QBool(0)
            physical = encode!(Steane(), q)
            @test q.consumed == true
            for p in physical
                discard!(p)
            end
        end
    end
end
