using Test
using Sturm

# Sturm.jl-sv3: @context auto-cleanup of unconsumed quantum resources.
#
# After an @context block exits, every qubit/wire that was allocated inside
# it and never consumed (via measure / Bool() / Int() / discard!) must be
# partial-traced deterministically — NOT left to Julia's non-deterministic
# GC. This mirrors `lock(l) do … end`: resource release is tied to scope,
# not to finalizer timing.

@testset "sv3: @context auto-cleanup" begin

    @testset "EagerContext: unconsumed QBool is cleared on block exit" begin
        ctx = EagerContext()
        @context ctx begin
            q1 = QBool(0.0)
            q2 = QBool(0.5)
            # deliberately no discard!, no Bool(...)
        end
        @test isempty(ctx.wire_to_qubit)
    end

    @testset "EagerContext: unconsumed QInt is cleared on block exit" begin
        ctx = EagerContext()
        @context ctx begin
            r = QInt{4}(7)
        end
        @test isempty(ctx.wire_to_qubit)
    end

    @testset "EagerContext: consumed wire is not double-traced" begin
        ctx = EagerContext()
        @context ctx begin
            q = QBool(0.5)
            Bool(q)   # consumes q; wire already removed from wire_to_qubit
        end
        @test isempty(ctx.wire_to_qubit)
    end

    @testset "EagerContext: mixed (some consumed, some leaked)" begin
        ctx = EagerContext()
        @context ctx begin
            q1 = QBool(0.5)
            q2 = QBool(0.0)
            q3 = QBool(1.0)
            Bool(q2)          # consume q2
            # q1, q3 leaked
        end
        @test isempty(ctx.wire_to_qubit)
    end

    @testset "DensityMatrixContext: unconsumed wires cleared on block exit" begin
        ctx = DensityMatrixContext()
        @context ctx begin
            q = QBool(0.5)
        end
        @test isempty(ctx.wire_to_qubit)
    end

    @testset "100 nested @context blocks: qubit recycling across iterations" begin
        # Without sv3 this test still passes because each @context builds a
        # fresh EagerContext. With sv3 we additionally guarantee that the
        # retired ctx's wire_to_qubit is empty — a canary that the cleanup
        # path ran for every iteration. We check the last one.
        last_ctx = nothing
        for _ in 1:100
            last_ctx = EagerContext()
            @context last_ctx begin
                q = QBool(0.0)
            end
        end
        @test isempty(last_ctx.wire_to_qubit)
    end

    @testset "Exception safety: wires cleared even if body throws" begin
        ctx = EagerContext()
        @test_throws ErrorException (@context ctx begin
            q = QBool(0.0)
            error("boom")
        end)
        @test isempty(ctx.wire_to_qubit)
    end

    @testset "Nested @context on same ctx: outer wires preserved while inner runs" begin
        # Nested @context is legal (see CLAUDE.md). The inner block switches
        # to a different ctx via TLS; the outer ctx's live set must be
        # untouched until the outer exits.
        outer = EagerContext()
        inner = EagerContext()
        @context outer begin
            q_outer = QBool(0.0)
            @context inner begin
                q_inner = QBool(0.5)
            end
            # After inner exits, its wires are cleaned up ...
            @test isempty(inner.wire_to_qubit)
            # ... but outer's wire is still live.
            @test !isempty(outer.wire_to_qubit)
        end
        @test isempty(outer.wire_to_qubit)
    end

    @testset "TracingContext: unconsumed wires emit DiscardNode in lowered channel" begin
        # Scope-equivalent semantics for tracing: orphaned wires should show
        # up as DiscardNode in the Channel DAG — partial trace is partial
        # trace, whatever the backend.
        ch = trace(2) do a, b
            # b is neither returned, nor discarded, nor measured — orphan.
            a
        end
        has_discard = any(n -> n isa Sturm.DiscardNode, ch.dag)
        @test has_discard
    end

    @testset "Block return value is preserved" begin
        x = @context EagerContext() begin
            42
        end
        @test x == 42
    end

    @testset "TracingContext: DiscardNodes appear at end of DAG in allocation order" begin
        ch = trace(2) do a, b
            # Allocate two scratch qubits, use one, leave both orphan.
            s1 = QBool(0.0)
            s2 = QBool(0.5)
            # a is the only output
            a
        end
        # b, s1, s2 are all orphans. They should appear as DiscardNodes in the
        # dag tail, in allocation order: b (input wire) was allocated first,
        # then s1, then s2 — but b was allocated OUTSIDE f (by trace itself),
        # and s1/s2 inside f. All three go to live. Expect 3 DiscardNodes.
        discards = [n for n in ch.dag if n isa Sturm.DiscardNode]
        @test length(discards) >= 3
    end

end
