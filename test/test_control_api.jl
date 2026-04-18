using Test
using Sturm
using Sturm: current_controls, with_controls, with_empty_controls,
             push_control!, pop_control!, allocate!, current_context

# Control-stack public API (bead Sturm.jl-1wv).
#
# Contract:
#   - current_controls(ctx)             returns a *copy* of the stack.
#   - with_empty_controls(f, ctx)       runs f() with an empty stack,
#                                       restores on exit (including exception).
#   - with_controls(f, ctx, ctrls)      runs f() with `ctrls` as the stack,
#                                       restores on exit.
#   - Both nest correctly and return the value of f().
#   - No direct access to `ctx.control_stack` required by callers.

@testset "Control-stack public API" begin

    # ── current_controls (regression, API already existed) ──────────────────

    @testset "current_controls returns a copy (mutating result does not alter stack)" begin
        @context EagerContext() begin
            ctx = current_context()
            w1 = allocate!(ctx); w2 = allocate!(ctx)
            push_control!(ctx, w1); push_control!(ctx, w2)

            snapshot = current_controls(ctx)
            @test snapshot == [w1, w2]
            empty!(snapshot)                        # mutate the returned copy
            @test current_controls(ctx) == [w1, w2] # stack unaffected

            pop_control!(ctx); pop_control!(ctx)
            discard!(QBool(ctx, 0))  # keep stateful; discard a dummy to advance
        end
    end

    # ── with_empty_controls: clears, runs, restores ─────────────────────────

    @testset "with_empty_controls clears stack inside block" begin
        @context EagerContext() begin
            ctx = current_context()
            w1 = allocate!(ctx)
            push_control!(ctx, w1)
            @test current_controls(ctx) == [w1]

            with_empty_controls(ctx) do
                @test current_controls(ctx) == WireID[]
            end

            @test current_controls(ctx) == [w1]
            pop_control!(ctx)
        end
    end

    @testset "with_empty_controls restores on exception" begin
        @context EagerContext() begin
            ctx = current_context()
            w1 = allocate!(ctx)
            push_control!(ctx, w1)

            @test_throws ErrorException with_empty_controls(ctx) do
                @test current_controls(ctx) == WireID[]
                error("boom")
            end

            # Stack restored despite exception
            @test current_controls(ctx) == [w1]
            pop_control!(ctx)
        end
    end

    @testset "with_empty_controls returns the value of its block" begin
        @context EagerContext() begin
            v = with_empty_controls(current_context()) do
                42
            end
            @test v == 42
        end
    end

    # ── with_controls: swaps to supplied stack, restores on exit ────────────

    @testset "with_controls swaps to supplied stack" begin
        @context EagerContext() begin
            ctx = current_context()
            w1 = allocate!(ctx); w2 = allocate!(ctx); w3 = allocate!(ctx)
            push_control!(ctx, w1)
            @test current_controls(ctx) == [w1]

            with_controls(ctx, WireID[w2, w3]) do
                @test current_controls(ctx) == [w2, w3]
            end

            @test current_controls(ctx) == [w1]
            pop_control!(ctx)
        end
    end

    @testset "with_controls restores on exception" begin
        @context EagerContext() begin
            ctx = current_context()
            w1 = allocate!(ctx); w2 = allocate!(ctx)
            push_control!(ctx, w1)

            @test_throws ErrorException with_controls(ctx, WireID[w2]) do
                @test current_controls(ctx) == [w2]
                error("boom")
            end

            @test current_controls(ctx) == [w1]
            pop_control!(ctx)
        end
    end

    # ── Nesting: the pauli_exp.jl / lcu.jl idiom ────────────────────────────

    @testset "Nested with_empty_controls + with_controls (pauli_exp / lcu idiom)" begin
        # Outer: stack = [w1, w2]. Inner pattern: clear for unconditional ops,
        # temporarily restore for the one controlled op, clear again.
        @context EagerContext() begin
            ctx = current_context()
            w1 = allocate!(ctx); w2 = allocate!(ctx)
            push_control!(ctx, w1); push_control!(ctx, w2)
            saved = current_controls(ctx)

            with_empty_controls(ctx) do
                @test current_controls(ctx) == WireID[]

                with_controls(ctx, saved) do
                    @test current_controls(ctx) == [w1, w2]
                end

                @test current_controls(ctx) == WireID[]
            end

            @test current_controls(ctx) == [w1, w2]
            pop_control!(ctx); pop_control!(ctx)
        end
    end

    # ── Works identically on DensityMatrixContext and TracingContext ────────

    @testset "Works on DensityMatrixContext" begin
        @context DensityMatrixContext() begin
            ctx = current_context()
            w1 = allocate!(ctx)
            push_control!(ctx, w1)
            with_empty_controls(ctx) do
                @test current_controls(ctx) == WireID[]
            end
            @test current_controls(ctx) == [w1]
            pop_control!(ctx)
        end
    end

    @testset "Works on TracingContext" begin
        @context TracingContext() begin
            ctx = current_context()
            w1 = allocate!(ctx)
            push_control!(ctx, w1)
            with_empty_controls(ctx) do
                @test current_controls(ctx) == WireID[]
            end
            @test current_controls(ctx) == [w1]
            pop_control!(ctx)
        end
    end
end
