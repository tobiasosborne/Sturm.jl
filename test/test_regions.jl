# SPDX-License-Identifier: AGPL-3.0-only
#
# M2 tests (bead Sturm.jl-dc6i): regions (PRD-v2 §3.9) — @context binding,
# ScopedValue propagation into spawned tasks, owned-only exit traces, the
# no-backaction corollary (trace-timing invariance; seeded tests never assert
# trace placement), ptrace! as a consumption site, and the strict-mode scaffold.

# (helpers from test_m2_common.jl are already in scope)

using Sturm: _core, _marginal_p1

@testset "Regions & scope (M2, §3.9)" begin

    @testset "@context binds current_context()" begin
        eager(2) do ctx
            @context ctx begin
                @test current_context() === ctx
                w = allocate!(current_context())
                apply!(current_context(), X, (w,))
            end
        end
        # outside any binding, current_context() fails loud
        @test_throws ErrorException current_context()
    end

    @testset "ScopedValue propagates into Threads.@spawn (TLS would NOT — conv 6)" begin
        eager(1) do ctx
            @context ctx begin
                t = Threads.@spawn current_context()
                @test fetch(t) === ctx
            end
        end
    end

    @testset "region exit traces OWNED-and-unconsumed wires only" begin
        eager(4) do ctx
            outer = allocate!(ctx)                    # owned by the outer (eager) region
            traced_inner = Ref{Any}(nothing)
            region() do
                a = allocate!(current_context())      # owned by this region
                b = allocate!(current_context())
                ptrace!(current_context(), b)         # consumed early ⇒ not re-traced
                traced_inner[] = a
                # `outer` is owned by the ENCLOSING region, not this one:
                @test haskey(_core(ctx).wire_to_slot, outer)
            end
            # after the region: a was traced (dead), b was consumed (dead), outer lives
            @test !haskey(_core(ctx).wire_to_slot, traced_inner[])
            @test haskey(_core(ctx).wire_to_slot, outer)
        end
    end

    @testset "ptrace! is a consumption site (single-sourced consumed set §4.5)" begin
        eager(2) do ctx
            w = allocate!(ctx)
            @test !is_consumed(ctx, w)
            ptrace!(ctx, w)
            @test is_consumed(ctx, w)
            @test !haskey(_core(ctx).wire_to_slot, w)   # and no longer live
        end
    end

    @testset "trace-timing invariance — statistics equal, streams need not be (N≥1000)" begin
        # Bell(a,b); trace a. b's outcome mirrors a (50/50) regardless of WHERE the
        # trace falls: explicit-early vs region-exit-auto. Compare STATISTICS only.
        N = 2000
        function freq_b1(auto::Bool; seed::Int=20260710)
            rng = MersenneTwister(seed)
            count1 = 0
            for _ in 1:N
                v = eager(2; rng=rng) do ctx
                    if auto
                        # `a` is owned by an INNER region and auto-traced at its exit
                        # (region-exit timing); then b is definite.
                        b = allocate!(ctx)
                        region() do
                            a = allocate!(current_context())
                            apply!(ctx, H, (a,))
                            apply!(ctx, ctrl(X), (a, b))
                        end
                        round(Int, _marginal_p1(_core(ctx).state, q(ctx, b)))
                    else
                        # explicit early trace (different timing, same statistics)
                        a = allocate!(ctx); b = allocate!(ctx)
                        apply!(ctx, H, (a,))
                        apply!(ctx, ctrl(X), (a, b))
                        ptrace!(ctx, a)
                        round(Int, _marginal_p1(_core(ctx).state, q(ctx, b)))
                    end
                end
                count1 += v
            end
            return count1 / N
        end
        f_auto = freq_b1(true)
        f_expl = freq_b1(false)
        σ = sqrt(0.25 / N)
        @test abs(f_auto - 0.5) < 3σ            # each within 3σ of 0.5
        @test abs(f_expl - 0.5) < 3σ
        @test abs(f_auto - f_expl) < 6σ         # statistically equal to each other
    end

    @testset "seeded tests never assert trace placement (D10 policy, executable)" begin
        # Same seed, two region STRUCTURES; assert MARGINAL statistics match a
        # reference (≈0.5). We deliberately do NOT compare RNG streams / draw order
        # (that would pin trace placement, which §3.9 forbids as a test contract).
        N = 2000
        function marg(seed)
            rng = MersenneTwister(seed)
            c = 0
            for _ in 1:N
                c += eager(2; rng=rng) do ctx
                    a = allocate!(ctx); b = allocate!(ctx)
                    apply!(ctx, H, (a,))
                    apply!(ctx, ctrl(X), (a, b))
                    ptrace!(ctx, a)
                    round(Int, _marginal_p1(_core(ctx).state, q(ctx, b)))
                end
            end
            c / N
        end
        @test abs(marg(1234) - 0.5) < 0.05
        @test abs(marg(9999) - 0.5) < 0.05
    end

    @testset "resource form frees the state_t even on a thrown exception" begin
        # `eager`'s finally must teardown! even if the body throws.
        thrown = false
        try
            eager(1) do ctx
                allocate!(ctx)
                error("boom inside region")
            end
        catch e
            thrown = true
            @test e isa ErrorException
        end
        @test thrown
        # (leak is only observable via a debug detector; here we assert the path
        #  ran without a double-free crash — reaching this line proves teardown
        #  did not fault.)
        @test true
    end

    @testset "strict-mode scaffold is inert while the parent map is empty (M6 hook)" begin
        eager(2; strict=true) do ctx
            @test _core(ctx).strict
            @test isempty(_core(ctx).parent)
            # region exit with the detector hook runs and does nothing (no fresh-
            # output ops exist before M6): allocate a local, let the region trace it.
            region() do
                allocate!(current_context())
            end
            @test true          # no error from the inert detector
        end
    end
end
