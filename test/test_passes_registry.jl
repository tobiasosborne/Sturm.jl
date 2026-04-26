using Test
using Sturm

# Tests for Sturm.jl-7ab — AbstractPass + registry + handles_non_unitary gate.
# Backward-compat tests for the Symbol API live in test_passes.jl and must
# continue to pass; this file exercises the new abstraction layer directly.

# Test-fixture pass types — defined at module-top so methods dispatch under
# the same world age as the testsets that exercise them. (Defining a struct
# inside @testset triggers Julia world-age issues when methods on it are
# called from the same expansion.)

struct MyNaivePass <: Sturm.AbstractPass end
Sturm.pass_name(::Type{MyNaivePass}) = :my_naive
Sturm.run_pass(::MyNaivePass, dag::Vector{Sturm.DAGNode}) = dag

struct MyChannelAwarePass <: Sturm.AbstractPass end
Sturm.pass_name(::Type{MyChannelAwarePass}) = :my_channel_aware
Sturm.handles_non_unitary(::Type{MyChannelAwarePass}) = true
Sturm.run_pass(::MyChannelAwarePass, dag::Vector{Sturm.DAGNode}) = dag

struct MyTrivialPass <: Sturm.AbstractPass end
Sturm.pass_name(::Type{MyTrivialPass}) = :my_trivial
Sturm.handles_non_unitary(::Type{MyTrivialPass}) = true
Sturm.run_pass(::MyTrivialPass, dag::Vector{Sturm.DAGNode}) = dag

@testset "Pass registry (Sturm.jl-7ab)" begin

    # ── Built-in passes registered ──────────────────────────────────────────

    @testset "Built-in passes registered with canonical names" begin
        @test get_pass(:cancel) isa GateCancelPass
        @test get_pass(:cancel_adjacent) isa GateCancelPass
        @test get_pass(:deferred) isa DeferMeasurementsPass
        @test get_pass(:defer_measurements) isa DeferMeasurementsPass

        names = Set(pass_name(typeof(p)) for p in registered_passes())
        @test :cancel in names
        @test :deferred in names
    end

    @testset "get_pass(:bogus) errors with registered list" begin
        err = try; get_pass(:nonexistent_pass); catch e; e; end
        @test err isa ErrorException
        @test occursin("Unknown optimisation pass", err.msg)
        @test occursin(":cancel", err.msg)
        @test occursin(":deferred", err.msg)
    end

    # ── Trait declarations on built-ins ─────────────────────────────────────

    @testset "Built-in trait declarations" begin
        @test pass_name(GateCancelPass) === :cancel
        @test pass_name(DeferMeasurementsPass) === :deferred
        @test handles_non_unitary(GateCancelPass) === true
        @test handles_non_unitary(DeferMeasurementsPass) === true
        @test handles_non_unitary(GateCancelPass()) === true
    end

    # ── Vector-of-passes API ────────────────────────────────────────────────

    @testset "optimise(ch, [GateCancelPass()]) cancels rotations" begin
        ch = trace(1) do q
            q.θ += π/4
            q.θ += π/4
            q
        end
        ch2 = optimise(ch, [GateCancelPass()])
        @test ch2 isa Sturm.Channel
        @test length(ch2.dag) == 1
        @test ch2.dag[1] isa Sturm.RyNode
        @test ch2.dag[1].angle ≈ π/2
    end

    @testset "optimise(ch, GateCancelPass()) single-pass convenience" begin
        ch = trace(1) do q
            q.θ += π/4
            q.θ += π/4
            q
        end
        ch2 = optimise(ch, GateCancelPass())
        @test length(ch2.dag) == 1
        @test ch2.dag[1].angle ≈ π/2
    end

    @testset "Pipeline: [DeferMeasurementsPass(), GateCancelPass()]" begin
        ch = trace(1) do q
            q.θ += π/4
            q.θ += π/4
            q
        end
        ch2 = optimise(ch, [DeferMeasurementsPass(), GateCancelPass()])
        @test length(ch2.dag) == 1
    end

    # ── handles_non_unitary runtime gate ────────────────────────────────────

    # A third-party pass author writes a "ZX-like" rewrite that is NOT
    # barrier-aware. The default trait value (false) gates it from any
    # channel containing a non-unitary node. We trip it with a DiscardNode
    # (partial trace) — Bool(q) inside trace() is a P4 violation
    # (silent mis-tracing), so we use the public ptrace! API instead.
    @testset "handles_non_unitary = false refuses non-unitary node" begin
        @test handles_non_unitary(MyNaivePass) === false

        ch_unitary = trace(1) do q
            q.θ += π/4
            q
        end
        @test optimise(ch_unitary, MyNaivePass()) isa Sturm.Channel

        ch_disc = trace(1) do q
            q.θ += π/4
            ptrace!(q)
            nothing
        end
        @test any(n -> n isa Sturm.DiscardNode, ch_disc.dag)

        err = try
            optimise(ch_disc, MyNaivePass())
            nothing
        catch e
            e
        end
        @test err isa ErrorException
        @test occursin("handles_non_unitary = false", err.msg)
        @test occursin("DiscardNode", err.msg)
        @test occursin("DeferMeasurementsPass", err.msg)
    end

    @testset "Override handles_non_unitary = true bypasses the gate" begin
        ch_disc = trace(1) do q
            q.θ += π/4
            ptrace!(q)
            nothing
        end
        @test optimise(ch_disc, MyChannelAwarePass()) isa Sturm.Channel
    end

    # ── User registration ──────────────────────────────────────────────────

    @testset "register_pass! enables Symbol dispatch for user passes" begin
        register_pass!(:my_trivial, MyTrivialPass())
        @test get_pass(:my_trivial) isa MyTrivialPass

        ch = trace(1) do q
            q.θ += π/4
            q
        end
        @test optimise(ch, :my_trivial) isa Sturm.Channel
    end

    # ── DeferMeasurementsPass kwargs ───────────────────────────────────────

    @testset "DeferMeasurementsPass(strict=true) propagates strict" begin
        p = DeferMeasurementsPass(strict=true)
        @test p.strict === true
        p2 = DeferMeasurementsPass()
        @test p2.strict === false
    end
end
