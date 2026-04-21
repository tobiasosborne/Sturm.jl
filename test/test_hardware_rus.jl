using Test
using Sturm

# Repeat-until-success T-gate template (from test_rus.jl) but executed via the
# round-trip path. Each loop iteration measures the ancilla (round-trip!) and
# branches in classical Julia. Validates that mid-circuit measurement +
# classical-conditioned corrections work end-to-end via HardwareContext.
#
# This is functionally identical to the EagerContext RUS test in test_rus.jl
# — same physics, same DSL — proving the AbstractContext substitution holds
# on the round-trip path.

function _rus_T_via_hardware!(target::QBool)
    iters = 0
    while true
        iters += 1
        iters > 1000 && error("RUS exceeded 1000 iterations")
        anc = QBool(1//8)
        anc ⊻= target
        anc ⊻= target           # CX·CX = I (mirrors test_rus.jl)
        ok = Bool(anc)          # → flush, round-trip, classical Bool back
        if ok
            return iters
        end
        target.φ -= π/4
    end
    return iters
end

@testset "RUS via HardwareContext (HW6)" begin

    @testset "RUS terminates with geometric distribution (p=1/8)" begin
        sim = Sturm.IdealisedSimulator(; capacity=2)
        ctx = Sturm.HardwareContext(Sturm.InProcessTransport(sim); capacity=2)
        @context ctx begin
            total_iters = 0
            N = 50
            for _ in 1:N
                q = QBool(0)
                total_iters += _rus_T_via_hardware!(q)
                discard!(q)
            end
            avg = total_iters / N
            @test 3 < avg < 20    # E[geometric(1/8)] = 8
        end
        close(ctx)
    end

    @testset "Each iteration produces one round-trip (one flush per Bool)" begin
        sim = Sturm.IdealisedSimulator(; capacity=2, gate_time_ms=10.0)
        ctx = Sturm.HardwareContext(Sturm.InProcessTransport(sim); capacity=2)
        @context ctx begin
            q = QBool(0)
            iters = _rus_T_via_hardware!(q)
            discard!(q)
            # total_duration_ms accumulates per-flush. Each iteration:
            #   alloc(anc) + ry(π/8 prep) + cx + cx + measure  → 3 unitary gates
            # Plus a final discard (no gate). Plus possibly one rz(-π/4) per
            # failed iter (which gets buffered into the NEXT iter's flush).
            # Floor: 3 * iters * 10ms; ceiling much higher because iters itself
            # is random and rz adds.
            @test ctx.total_duration_ms >= 3 * iters * 10.0
        end
        close(ctx)
    end
end
