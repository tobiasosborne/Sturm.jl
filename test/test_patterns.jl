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

    # ── 35s: X↔Y convention-drift discriminators ───────────────────────────
    #
    # WORKLOG Session 42 (bead 3yz) proved algebraically that for any
    # diagonal D, Y^⊗W · D · Y^⊗W = X^⊗W · D · X^⊗W  (Y = iXZ; the Z factors
    # commute through D and cancel). So `X-MCZ-X` in `_diffusion!` and
    # `phase_flip!` is INVARIANT under a symmetric X↔Y swap.
    #
    # The real convention-drift risk is ASYMMETRIC drift — swapping only
    # one side of the sandwich, giving `X-MCZ-Y` or `Y-MCZ-X`. On W=2 such
    # a broken sandwich reduces (up to global phase) to CZ and a pure-
    # imaginary single-qubit phase flip respectively — radically different
    # from the intended S₀ = 2|0⟩⟨0|−I and the target-indexed phase flip.
    #
    # Global phase is unobservable (CLAUDE.md "Global Phase and Universality":
    # Sturm lives in SU(2), H!² = −I is correct). The tests below therefore
    # assert the channel action UP TO GLOBAL PHASE via amplitude ratios
    # r[k] = post[k] / pre[k], comparing RELATIVE signs between indices.

    _amp(ctx, idx) = Sturm.orkan_state_get(ctx.orkan.raw, idx, 0)

    @testset "_diffusion! acts as S₀ = 2|0⟩⟨0|−I on a generic W=2 state" begin
        # |ψ⟩ = Ry(2a)|0⟩ ⊗ Ry(2b)|0⟩, a=π/7, b=π/11:
        #    α = cos(a)cos(b)   at idx 0  (|00⟩ in little-endian)
        #    β = sin(a)cos(b)   at idx 1
        #    γ = cos(a)sin(b)   at idx 2
        #    δ = sin(a)sin(b)   at idx 3
        # all real, distinct, non-zero.
        #
        # S₀ channel on W=2: ratio[0] = +c; ratio[k] = −c for k∈{1,2,3}
        # (c is the shared global phase e^{i3π/4} from the X!·_cz!·X!
        # construction — unobservable, cancels in ratio comparisons).
        #
        # Asymmetric Y⊗Y·_cz!·X⊗X (broken sandwich): ratio[k] = +c for
        # k∈{0,1,2}, ratio[3] = −c. Three of the four ratio checks below
        # flip sign under that drift.
        a, b = π/7, π/11
        @context EagerContext() begin
            x = QInt{2}(0)
            q0 = QBool(x.wires[1], x.ctx, false); q0.θ += 2a
            q1 = QBool(x.wires[2], x.ctx, false); q1.θ += 2b

            α = cos(a) * cos(b)
            β = sin(a) * cos(b)
            γ = cos(a) * sin(b)
            δ = sin(a) * sin(b)

            # Sanity: pre-diffusion amplitudes match preparation.
            @test abs(_amp(x.ctx, 0) - α) < 1e-12
            @test abs(_amp(x.ctx, 1) - β) < 1e-12
            @test abs(_amp(x.ctx, 2) - γ) < 1e-12
            @test abs(_amp(x.ctx, 3) - δ) < 1e-12

            Sturm._diffusion!(x)

            # Unitary — magnitudes preserved.
            @test abs(abs(_amp(x.ctx, 0)) - α) < 1e-12
            @test abs(abs(_amp(x.ctx, 1)) - β) < 1e-12
            @test abs(abs(_amp(x.ctx, 2)) - γ) < 1e-12
            @test abs(abs(_amp(x.ctx, 3)) - δ) < 1e-12

            # Phase-invariant channel-action assertion.
            r = _amp(x.ctx, 0) / α
            @test abs(_amp(x.ctx, 1) / β - (-r)) < 1e-12
            @test abs(_amp(x.ctx, 2) / γ - (-r)) < 1e-12
            @test abs(_amp(x.ctx, 3) / δ - (-r)) < 1e-12
        end
    end

    @testset "phase_flip!(x, 2) flips only idx 2 relative to idx 0" begin
        # target=2 = 0b10 on W=2: bit 0 of target is 0 → X!(qs[1]);
        # bit 1 is 1 → no X. Correct channel flips ONLY idx 2.
        #
        # Asymmetric X·MCZ·Y on wire 1 would flip idx 0 instead (with an
        # extra i on the global phase). The ratio[k]/r checks below pin the
        # flip location to idx 2 up to global phase.
        a, b = π/7, π/11
        @context EagerContext() begin
            x = QInt{2}(0)
            q0 = QBool(x.wires[1], x.ctx, false); q0.θ += 2a
            q1 = QBool(x.wires[2], x.ctx, false); q1.θ += 2b

            α = cos(a) * cos(b); β = sin(a) * cos(b)
            γ = cos(a) * sin(b); δ = sin(a) * sin(b)

            phase_flip!(x, 2)

            @test abs(abs(_amp(x.ctx, 0)) - α) < 1e-12
            @test abs(abs(_amp(x.ctx, 1)) - β) < 1e-12
            @test abs(abs(_amp(x.ctx, 2)) - γ) < 1e-12
            @test abs(abs(_amp(x.ctx, 3)) - δ) < 1e-12

            r = _amp(x.ctx, 0) / α
            @test abs(_amp(x.ctx, 1) / β - ( r)) < 1e-12  # unchanged
            @test abs(_amp(x.ctx, 2) / γ - (-r)) < 1e-12  # flipped (target)
            @test abs(_amp(x.ctx, 3) / δ - ( r)) < 1e-12  # unchanged
        end
    end

    @testset "phase_flip!(x, 1) flips only idx 1 relative to idx 0" begin
        # target=1 = 0b01 on W=2: X on wire 2 only. Correct flips ONLY idx 1.
        a, b = π/7, π/11
        @context EagerContext() begin
            x = QInt{2}(0)
            q0 = QBool(x.wires[1], x.ctx, false); q0.θ += 2a
            q1 = QBool(x.wires[2], x.ctx, false); q1.θ += 2b

            α = cos(a) * cos(b); β = sin(a) * cos(b)
            γ = cos(a) * sin(b); δ = sin(a) * sin(b)

            phase_flip!(x, 1)

            @test abs(abs(_amp(x.ctx, 0)) - α) < 1e-12
            @test abs(abs(_amp(x.ctx, 1)) - β) < 1e-12
            @test abs(abs(_amp(x.ctx, 2)) - γ) < 1e-12
            @test abs(abs(_amp(x.ctx, 3)) - δ) < 1e-12

            r = _amp(x.ctx, 0) / α
            @test abs(_amp(x.ctx, 1) / β - (-r)) < 1e-12  # flipped (target)
            @test abs(_amp(x.ctx, 2) / γ - ( r)) < 1e-12  # unchanged
            @test abs(_amp(x.ctx, 3) / δ - ( r)) < 1e-12  # unchanged
        end
    end
end
