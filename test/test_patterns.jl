using Test
using Sturm

@testset "Library patterns" begin

    @testset "superpose! on QInt{1}(0) gives uniform superposition" begin
        @context EagerContext() begin
            N = 5000
            count_1 = 0
            for _ in 1:N
                x = QInt{1}(0)
                superpose!(x)
                count_1 += Int(x)
            end
            @test abs(count_1 / N - 0.5) < 0.03
        end
    end

    @testset "interfere!(superpose!(|0⟩)) = |0⟩ roundtrip" begin
        # QFT then iQFT on |0⟩ should return |0⟩ deterministically
        @context EagerContext() begin
            for _ in 1:50
                x = QInt{3}(0)
                superpose!(x)
                interfere!(x)
                @test Int(x) == 0
            end
        end
    end

    @testset "interfere!(superpose!(|k⟩)) = |k⟩ for all 3-bit states" begin
        @context EagerContext() begin
            for k in 0:7
                x = QInt{3}(k)
                superpose!(x)
                interfere!(x)
                @test Int(x) == k
            end
        end
    end

    @testset "superpose!(|0⟩) gives uniform distribution (3 qubits)" begin
        @context EagerContext() begin
            counts = zeros(Int, 8)
            N = 8000
            for _ in 1:N
                x = QInt{3}(0)
                superpose!(x)
                counts[Int(x) + 1] += 1
            end
            # Each outcome should appear ~N/8 = 1000 times
            for c in counts
                @test abs(c / N - 1/8) < 0.04
            end
        end
    end

    @testset "fourier_sample: constant oracle → 0 (Deutsch-Jozsa)" begin
        # Constant oracle: identity (does nothing)
        # After superpose → identity → interfere, we get |0⟩
        @context EagerContext() begin
            for _ in 1:20
                result = fourier_sample(x -> nothing, Val(3))
                @test result == 0
            end
        end
    end

    @testset "fourier_sample: balanced oracle → nonzero (Deutsch-Jozsa)" begin
        # Balanced oracle: flip phase of all basis states with MSB=1
        # This is Z on the MSB, which in our little-endian convention is wire W
        @context EagerContext() begin
            N = 100
            nonzero_count = 0
            for _ in 1:N
                result = fourier_sample(Val(3)) do x
                    # Z on MSB (wire 3): flip phase when bit 3 is 1
                    b = QBool(x.wires[3], x.ctx, false)
                    Z!(b)
                end
                if result != 0
                    nonzero_count += 1
                end
            end
            # Balanced oracle should ALWAYS give nonzero (Deutsch-Jozsa guarantee)
            @test nonzero_count == N
        end
    end

    @testset "phase_estimate: Z! (Rz(π)) on |1⟩" begin
        # Z! = Rz(π). Rz(π)|1⟩ = e^{iπ/2}|1⟩.
        # Phase φ = (π/2)/(2π) = 0.25. Result = 0.25 × 2^3 = 2.
        # Note: Z! is Rz(π), NOT diag(1,-1). Eigenvalue differs by global phase.
        @context EagerContext() begin
            eigenstate = QBool(1)
            result = phase_estimate(Z!, eigenstate, Val(3))
            @test result == 2
        end
    end

    @testset "phase_estimate: S! (Rz(π/2)) on |1⟩" begin
        # S! = Rz(π/2). Rz(π/2)|1⟩ = e^{iπ/4}|1⟩.
        # Phase φ = (π/4)/(2π) = 0.125. Result = 0.125 × 2^3 = 1.
        @context EagerContext() begin
            eigenstate = QBool(1)
            result = phase_estimate(S!, eigenstate, Val(3))
            @test result == 1
        end
    end

    @testset "phase_estimate: Rz(π/2) on |1⟩ with 4 bits precision" begin
        # Rz(π/2)|1⟩ = e^{iπ/4}|1⟩. Phase = 0.125.
        # With 4 precision qubits: result = 0.125 × 16 = 2.
        @context EagerContext() begin
            eigenstate = QBool(1)
            result = phase_estimate(S!, eigenstate, Val(4))
            @test result == 2
        end
    end

    @testset "phase_estimate: custom Rz(2π/4) = Rz(π/2) on |1⟩" begin
        # Apply Rz(π/2) = q.φ += π/2. Same as S!.
        # Eigenvalue on |1⟩ = e^{iπ/4}. Phase = 1/8.
        # With 3 bits: result = 1.
        @context EagerContext() begin
            eigenstate = QBool(1)
            my_gate!(q) = (q.φ += π/2; q)
            result = phase_estimate(my_gate!, eigenstate, Val(3))
            @test result == 1
        end
    end
end
