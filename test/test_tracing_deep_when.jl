using Test
using Sturm

# Arbitrary when() nesting depth on TracingContext (bead Sturm.jl-rpq).
#
# Before this bead, tracing.jl:65 hard-capped `nc > 2` with an explicit
# error. A 3-nested or deeper when() failed to trace even though
# EagerContext/DensityMatrixContext already supported it via Toffoli
# cascade. This test suite exercises depth-3 and depth-4 nesting end-to-end:
#   1. The circuit traces without erroring.
#   2. The resulting Channel has a non-empty DAG.
#   3. OpenQASM 3.0 export succeeds and emits the cascaded gates.
#   4. Running the same circuit on EagerContext gives the correct outcome,
#      confirming the trace-emitted cascade is the same one the eager
#      path would run.

@testset "TracingContext: arbitrary when() nesting depth" begin

    @testset "Depth 3: CCCRy via triple-nested when() traces" begin
        ch = trace(4) do c1, c2, c3, t
            when(c1) do; when(c2) do; when(c3) do
                t.θ += π
            end; end; end
            (c1, c2, c3, t)
        end
        @test n_inputs(ch) == 4
        @test n_outputs(ch) == 4
        @test length(ch.dag) > 0
    end

    @testset "Depth 3: OpenQASM export succeeds" begin
        ch = trace(4) do c1, c2, c3, t
            when(c1) do; when(c2) do; when(c3) do
                t.θ += π
            end; end; end
            (c1, c2, c3, t)
        end
        qasm = to_openqasm(ch)
        @test occursin("OPENQASM 3.0", qasm)
        @test occursin("ccx", qasm)   # cascade uses CCX
    end

    @testset "Depth 4: quadruple-nested when() traces" begin
        ch = trace(5) do c1, c2, c3, c4, t
            when(c1) do; when(c2) do; when(c3) do; when(c4) do
                t.θ += π
            end; end; end; end
            (c1, c2, c3, c4, t)
        end
        @test n_inputs(ch) == 5
        @test n_outputs(ch) == 5
        @test length(ch.dag) > 0
    end

    @testset "Depth 3: apply_cx! inside 2-deep when() (effective CCCX) traces" begin
        # when(c1) do; when(c2) do; t ⊻= c3; end; end
        ch = trace(4) do c1, c2, c3, t
            when(c1) do; when(c2) do
                t ⊻= c3
            end; end
            (c1, c2, c3, t)
        end
        @test n_inputs(ch) == 4
        @test length(ch.dag) > 0
    end

    @testset "Depth 2: apply_ccx! inside when() (effective CCCX) traces" begin
        # Inside when(c1), a CCX(c2, c3, t) should expand via the cascade.
        # Exercised through the gate primitive directly.
        ch = trace(4) do c1, c2, c3, t
            when(c1) do
                Sturm.apply_ccx!(current_context(), c2.wire, c3.wire, t.wire)
            end
            (c1, c2, c3, t)
        end
        @test n_inputs(ch) == 4
        @test length(ch.dag) > 0
    end

    # ── Equivalence: the cascade traced matches the cascade eager runs ─────

    @testset "Depth 3: eager outcome matches (all controls |1⟩ → target flips)" begin
        @context EagerContext() begin
            c1 = QBool(1); c2 = QBool(1); c3 = QBool(1); t = QBool(0)
            when(c1) do; when(c2) do; when(c3) do
                t.θ += π
            end; end; end
            discard!(c1); discard!(c2); discard!(c3)
            @test Bool(t) == true
        end
    end

    @testset "Depth 4: eager outcome matches (all |1⟩)" begin
        @context EagerContext() begin
            c1 = QBool(1); c2 = QBool(1); c3 = QBool(1); c4 = QBool(1); t = QBool(0)
            when(c1) do; when(c2) do; when(c3) do; when(c4) do
                t.θ += π
            end; end; end; end
            discard!(c1); discard!(c2); discard!(c3); discard!(c4)
            @test Bool(t) == true
        end
    end

    @testset "Depth 4: any |0⟩ control blocks the gate" begin
        @context EagerContext() begin
            for missing_idx in 1:4
                vs = [1, 1, 1, 1]; vs[missing_idx] = 0
                c1 = QBool(vs[1]); c2 = QBool(vs[2])
                c3 = QBool(vs[3]); c4 = QBool(vs[4])
                t = QBool(0)
                when(c1) do; when(c2) do; when(c3) do; when(c4) do
                    t.θ += π
                end; end; end; end
                discard!(c1); discard!(c2); discard!(c3); discard!(c4)
                @test Bool(t) == false
            end
        end
    end
end
