using Test
using Sturm

@testset "Channel / Tracing" begin

    @testset "DAG node construction" begin
        w1 = Sturm.fresh_wire!()
        w2 = Sturm.fresh_wire!()
        @test Sturm.PrepNode(w1, 0.5) isa Sturm.DAGNode
        @test Sturm.RyNode(w1, π) isa Sturm.DAGNode
        @test Sturm.RzNode(w1, π/2) isa Sturm.DAGNode
        @test Sturm.CXNode(w1, w2) isa Sturm.DAGNode
        @test Sturm.ObserveNode(w1, UInt32(1)) isa Sturm.DAGNode
        @test Sturm.DiscardNode(w1) isa Sturm.DAGNode
    end

    @testset "TracingContext records H gate" begin
        ctx = TracingContext()
        w = Sturm.allocate!(ctx)
        # H! = Rz(π) · Ry(π/2)
        Sturm.apply_rz!(ctx, w, π)
        Sturm.apply_ry!(ctx, w, π/2)
        @test length(ctx.dag) == 2
        @test ctx.dag[1] isa Sturm.RzNode
        @test ctx.dag[2] isa Sturm.RyNode
        @test ctx.dag[1].angle ≈ π
        @test ctx.dag[2].angle ≈ π/2
    end

    @testset "TracingContext records CX" begin
        ctx = TracingContext()
        w1 = Sturm.allocate!(ctx)
        w2 = Sturm.allocate!(ctx)
        Sturm.apply_cx!(ctx, w1, w2)
        @test length(ctx.dag) == 1
        @test ctx.dag[1] isa Sturm.CXNode
        @test ctx.dag[1].control == w1
        @test ctx.dag[1].target == w2
    end

    @testset "TracingContext records controlled rotation" begin
        ctx = TracingContext()
        w1 = Sturm.allocate!(ctx)
        w2 = Sturm.allocate!(ctx)
        Sturm.push_control!(ctx, w1)
        Sturm.apply_ry!(ctx, w2, π)
        Sturm.pop_control!(ctx)
        @test length(ctx.dag) == 1
        node = ctx.dag[1]
        @test node isa Sturm.RyNode
        @test node.ncontrols == 1
        @test node.ctrl1 == w1
    end

    @testset "TracingContext: measure! errors loudly (use cases() or discard!)" begin
        # Bool(q) / Int(q) inside TracingContext is a silent-mis-trace footgun
        # (Sturm.jl-322). The fix is to error on raw measure! and route users
        # to cases() for branching or discard!() for partial trace.
        ctx = TracingContext()
        w = Sturm.allocate!(ctx)
        @test_throws ErrorException Sturm.measure!(ctx, w)
    end

    @testset "TracingContext: _emit_observe! is the internal cases-only path" begin
        # cases() uses the internal _emit_observe! to record an ObserveNode
        # without triggering the loud-error guard on raw measure!.
        ctx = TracingContext()
        w = Sturm.allocate!(ctx)
        cond_id = Sturm._emit_observe!(ctx, w)
        @test cond_id isa UInt32
        @test length(ctx.dag) == 1
        @test ctx.dag[1] isa Sturm.ObserveNode
        @test w in ctx.consumed
    end

    @testset "trace: single-qubit H gate" begin
        ch = trace(1) do q
            H!(q)
            q
        end
        @test n_inputs(ch) == 1
        @test n_outputs(ch) == 1
        # H! = Rz(π) then Ry(π/2) → 2 nodes
        @test length(ch.dag) == 2
    end

    @testset "trace: Bell state circuit" begin
        ch = trace(2) do a, b
            H!(a)
            b ⊻= a
            (a, b)
        end
        @test n_inputs(ch) == 2
        @test n_outputs(ch) == 2
        # H! = 2 nodes, CX = 1 node → 3 total
        @test length(ch.dag) == 3
    end

    @testset "Channel sequential composition (≫)" begin
        ch_h = trace(1) do q; H!(q); q; end
        ch_hh = ch_h >> ch_h  # H·H = I
        @test n_inputs(ch_hh) == 1
        @test n_outputs(ch_hh) == 1
        @test length(ch_hh.dag) == 4  # 2 + 2 nodes
    end

    @testset "Channel parallel composition (⊗)" begin
        ch1 = trace(1) do q; H!(q); q; end
        ch2 = trace(1) do q; X!(q); q; end
        ch_par = ch1 ⊗ ch2
        @test n_inputs(ch_par) == 2
        @test n_outputs(ch_par) == 2
    end

    @testset "to_openqasm: H gate" begin
        ch = trace(1) do q; H!(q); q; end
        qasm = to_openqasm(ch)
        @test occursin("OPENQASM 3.0;", qasm)
        @test occursin("qubit[", qasm)
        @test occursin("rz(", qasm)
        @test occursin("ry(", qasm)
    end

    @testset "to_openqasm: Bell circuit" begin
        ch = trace(2) do a, b
            H!(a)
            b ⊻= a
            (a, b)
        end
        qasm = to_openqasm(ch)
        @test occursin("cx ", qasm)
        @test occursin("rz(", qasm)
        @test occursin("ry(", qasm)
    end

    @testset "to_openqasm: measurement" begin
        ch = trace(1) do q
            H!(q)
            cases(q, () -> nothing)   # record measurement in IR (for QASM output) without branching
            nothing
        end
        qasm = to_openqasm(ch)
        @test occursin("measure", qasm)
        @test occursin("bit[", qasm)
    end
end
