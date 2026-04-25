# test_do_block_alloc.jl — bead Sturm.jl-cbl
#
# Do-block constructors for QBool/QInt, mirroring Julia's `open(f, path) do
# stream … end`. Form: `QBool(p) do q … end` and `QInt{W}(value) do reg … end`
# allocate the resource, run the body, and partial-trace the resource at
# block exit (regardless of normal return / exception / explicit consume).
#
# Acceptance criteria (from the bead):
#   1. `QBool(0.5) do q; H!(q); Bool(q); end` works.
#   2. q is unusable after the block.
#   3. Nested allocation works.
#   4. Body's return value is propagated.
#   5. Cleanup runs on exception.
#   6. If the body explicitly consumes q (ptrace! or Bool/Int cast), no
#      double-ptrace.

using Test
using Sturm
using Sturm: EagerContext, QBool, QInt, ptrace!, current_context

@testset "do-block allocation (Sturm.jl-cbl)" begin

    @testset "QBool" begin

        @testset "basic: body runs with q in scope, q ptraced at exit" begin
            @context EagerContext() begin
                ctx = current_context()
                consumed_inside = QBool(0.5) do q
                    @test q isa QBool
                    @test !q.consumed
                    @test haskey(ctx.wire_to_qubit, q.wire)
                    return q.consumed   # false at this point
                end
                @test consumed_inside == false
                # After block: no live wires.
                @test isempty(ctx.wire_to_qubit)
            end
        end

        @testset "body's return value is propagated" begin
            @context EagerContext() begin
                # Bool(q) consumes q AND returns the measurement result.
                # The do-block's return value is whatever the body returned.
                outcome = QBool(1.0) do q
                    Bool(q)
                end
                @test outcome === true
                # |0⟩-prepared qubit always measures false.
                outcome2 = QBool(0.0) do q
                    Bool(q)
                end
                @test outcome2 === false
            end
        end

        @testset "ptrace runs on exception" begin
            @context EagerContext() begin
                ctx = current_context()
                threw = false
                try
                    QBool(0.5) do q
                        @test haskey(ctx.wire_to_qubit, q.wire)
                        error("boom")
                    end
                catch e
                    threw = true
                    @test e isa ErrorException
                    @test occursin("boom", e.msg)
                end
                @test threw == true
                # q was ptraced in finally.
                @test isempty(ctx.wire_to_qubit)
            end
        end

        @testset "no double-ptrace if body explicitly consumes q" begin
            @context EagerContext() begin
                ctx = current_context()
                # Body consumes via Bool() — q.consumed = true on exit.
                # The do-block's finally must NOT re-ptrace (which would error
                # on `consume!` because already consumed).
                QBool(0.5) do q
                    Bool(q)
                end
                @test isempty(ctx.wire_to_qubit)
                # Body explicitly ptraces.
                QBool(0.5) do q
                    ptrace!(q)
                end
                @test isempty(ctx.wire_to_qubit)
            end
        end

        @testset "nested do-blocks compose" begin
            @context EagerContext() begin
                ctx = current_context()
                outer_outcome = QBool(0.5) do a
                    @test haskey(ctx.wire_to_qubit, a.wire)
                    inner_outcome = QBool(0.0) do b
                        @test haskey(ctx.wire_to_qubit, a.wire)
                        @test haskey(ctx.wire_to_qubit, b.wire)
                        Bool(b)
                    end
                    # inner b has been ptraced via Bool().
                    @test inner_outcome === false
                    @test haskey(ctx.wire_to_qubit, a.wire)
                    Bool(a)
                end
                @test outer_outcome isa Bool
                @test isempty(ctx.wire_to_qubit)
            end
        end

        @testset "explicit context form: QBool(f, ctx, p)" begin
            ctx = EagerContext()
            QBool(ctx, 0.5) do q
                @test q.ctx === ctx
                Bool(q)
            end
            @test isempty(ctx.wire_to_qubit)
        end
    end

    @testset "QInt" begin

        @testset "basic: register live in body, ptraced at exit" begin
            @context EagerContext() begin
                ctx = current_context()
                width = QInt{4}(7) do reg
                    @test reg isa QInt{4}
                    @test !reg.consumed
                    @test length(reg) == 4
                    return length(reg)
                end
                @test width == 4
                @test isempty(ctx.wire_to_qubit)
            end
        end

        @testset "body's measurement result is propagated" begin
            @context EagerContext() begin
                ctx = current_context()
                value = QInt{4}(11) do reg
                    Int(reg)
                end
                @test value == 11
                @test isempty(ctx.wire_to_qubit)
            end
        end

        @testset "ptrace runs on exception" begin
            @context EagerContext() begin
                ctx = current_context()
                threw = false
                try
                    QInt{4}(5) do reg
                        @test all(haskey(ctx.wire_to_qubit, w) for w in reg.wires)
                        error("kaboom")
                    end
                catch e
                    threw = true
                    @test occursin("kaboom", e.msg)
                end
                @test threw == true
                @test isempty(ctx.wire_to_qubit)
            end
        end

        @testset "no double-ptrace if body consumes via Int()" begin
            @context EagerContext() begin
                ctx = current_context()
                QInt{3}(5) do reg
                    Int(reg)
                end
                @test isempty(ctx.wire_to_qubit)
                QInt{3}(2) do reg
                    ptrace!(reg)
                end
                @test isempty(ctx.wire_to_qubit)
            end
        end

        @testset "explicit context form: QInt{W}(f, ctx, value)" begin
            ctx = EagerContext()
            QInt{4}(ctx, 13) do reg
                @test reg.ctx === ctx
                @test Int(reg) == 13
            end
            @test isempty(ctx.wire_to_qubit)
        end
    end

    @testset "interop: QBool inside @context, mid-scope" begin
        # Use case the bead motivates: a one-shot ancilla that should die
        # mid-scope without polluting the surrounding @context block's
        # auto-cleanup. Tests the LIVE-count invariant (persistent stays
        # live, scratch's slot is recycled), not n_qubits — which is
        # sticky upward by design (only compaction reduces it).
        @context EagerContext() begin
            ctx = current_context()
            persistent = QBool(1.0)
            @test length(ctx.wire_to_qubit) == 1   # only persistent live
            # one-shot ancilla
            outcome = QBool(0.0) do scratch
                # entangle and measure
                scratch ⊻= persistent
                Bool(scratch)
            end
            # scratch's slot is freed; persistent remains live.
            @test outcome === true
            @test length(ctx.wire_to_qubit) == 1
            @test haskey(ctx.wire_to_qubit, persistent.wire)
            @test Bool(persistent) === true
        end
    end
end
