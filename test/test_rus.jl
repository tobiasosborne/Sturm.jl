using Test
using Sturm

# ── PRD §8.3 rus_T! (verbatim) ──────────────────────────────────────────────
# NOTE: The PRD's algorithm applies CX·CX = I (two identical CNOTs cancel),
# so the ancilla is never entangled with the target. The measured ancilla
# outcome is independent of the target state, and the failure branch applies
# a random number of Rz(-π/4) corrections. This does NOT implement a T gate.
# We include it to verify the DSL handles repeat-until-success control flow.

function rus_T_prd!(target::QBool)
    iters = 0
    while true
        iters += 1
        iters > 1000 && error("RUS exceeded 1000 iterations")
        anc = QBool(1//8)
        anc ⊻= target
        anc ⊻= target     # CX · CX = I — undoes the first CNOT
        ok = Bool(anc)
        if ok; return iters; end
        target.φ -= π/4
    end
    return iters
end

# ── Correct T gate via magic state injection ─────────────────────────────────
# Gate teleportation: prepare |T⟩ = (|0⟩ + e^{iπ/4}|1⟩)/√2, entangle with
# target via CX, measure ancilla. If anc=0: T applied. If anc=1: T† applied,
# correct with S = T² (Rz(π/2)). Deterministic — always succeeds in 1 shot.
#
# Physics: CX(target→anc) on |ψ⟩|T⟩ gives:
#   anc=0 → α|0⟩ + βe^{iπ/4}|1⟩ = T|ψ⟩
#   anc=1 → e^{iπ/4}(α|0⟩ + βe^{-iπ/4}|1⟩) = e^{iπ/4}T†|ψ⟩
# Correction: T²·T† = T, and global phase is unobservable.

function t_inject!(target::QBool)
    anc = QBool(0.5)       # |+⟩
    anc.φ += π/4            # |T⟩ magic state
    anc ⊻= target           # CX(target→anc)
    if Bool(anc)            # measure anc
        target.φ += π/2     # S correction
    end
end

@testset "RUS / T-gate injection" begin

    @testset "PRD rus_T! terminates and handles loop mechanics" begin
        @context EagerContext() begin
            # Verify the loop terminates (geometric p=1/8, so ~8 iterations avg)
            total_iters = 0
            N = 100
            for _ in 1:N
                q = QBool(0)
                total_iters += rus_T_prd!(q)
                discard!(q)
            end
            avg_iters = total_iters / N
            # Expected ~8 iterations (geometric with p=1/8), allow wide margin
            @test 3 < avg_iters < 20
        end
    end

    @testset "PRD rus_T! does NOT match T gate (CX·CX=I physics error)" begin
        # Document that the PRD algorithm does not implement T
        N = 5000
        count_direct = Ref(0)
        count_prd = Ref(0)
        @context EagerContext() begin
            for _ in 1:N
                q = QBool(0); H!(q); T!(q); H!(q)
                count_direct[] += Bool(q)
            end
        end
        @context EagerContext() begin
            for _ in 1:N
                q = QBool(0); H!(q); rus_T_prd!(q); H!(q)
                count_prd[] += Bool(q)
            end
        end
        p_direct = count_direct[] / N
        p_prd = count_prd[] / N
        # Direct T gives P(1) ≈ sin²(π/8) ≈ 0.1464
        @test abs(p_direct - sin(π/8)^2) < 0.03
        # PRD version should NOT match (it gives ~0.46 due to random phase walk)
        @test abs(p_prd - sin(π/8)^2) > 0.1
    end

    @testset "t_inject! matches direct T gate" begin
        N = 10000
        count_direct = Ref(0)
        count_inject = Ref(0)
        @context EagerContext() begin
            for _ in 1:N
                q = QBool(0); H!(q); T!(q); H!(q)
                count_direct[] += Bool(q)
            end
        end
        @context EagerContext() begin
            for _ in 1:N
                q = QBool(0); H!(q); t_inject!(q); H!(q)
                count_inject[] += Bool(q)
            end
        end
        p_direct = count_direct[] / N
        p_inject = count_inject[] / N
        expected = sin(π/8)^2  # ≈ 0.1464
        @test abs(p_direct - expected) < 0.02
        @test abs(p_inject - expected) < 0.02
    end

    @testset "t_inject! on |1⟩ matches T!|1⟩" begin
        # T|1⟩ = e^{iπ/4}|1⟩, so measurement always gives true
        @context EagerContext() begin
            for _ in 1:100
                q = QBool(1)
                t_inject!(q)
                @test Bool(q) == true
            end
        end
    end

    @testset "t_inject! on |0⟩ matches T!|0⟩" begin
        # T|0⟩ = |0⟩, so measurement always gives false
        @context EagerContext() begin
            for _ in 1:100
                q = QBool(0)
                t_inject!(q)
                @test Bool(q) == false
            end
        end
    end
end
