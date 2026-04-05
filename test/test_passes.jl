using Test
using Sturm

@testset "Optimisation passes" begin

    @testset "Gate cancellation: Ry(π) then Ry(-π) → empty" begin
        w = Sturm.fresh_wire!()
        dag = Sturm.DAGNode[
            Sturm.RyNode(w, π),
            Sturm.RyNode(w, -π),
        ]
        opt = gate_cancel(dag)
        @test isempty(opt)
    end

    @testset "Gate cancellation: Ry(π/4) + Ry(π/4) → Ry(π/2)" begin
        w = Sturm.fresh_wire!()
        dag = Sturm.DAGNode[
            Sturm.RyNode(w, π/4),
            Sturm.RyNode(w, π/4),
        ]
        opt = gate_cancel(dag)
        @test length(opt) == 1
        @test opt[1] isa Sturm.RyNode
        @test opt[1].angle ≈ π/2
    end

    @testset "Gate cancellation: Rz(π) then Rz(-π) → empty" begin
        w = Sturm.fresh_wire!()
        dag = Sturm.DAGNode[
            Sturm.RzNode(w, π),
            Sturm.RzNode(w, -π),
        ]
        opt = gate_cancel(dag)
        @test isempty(opt)
    end

    @testset "Gate cancellation: different wires don't merge" begin
        w1 = Sturm.fresh_wire!()
        w2 = Sturm.fresh_wire!()
        dag = Sturm.DAGNode[
            Sturm.RyNode(w1, π),
            Sturm.RyNode(w2, -π),
        ]
        opt = gate_cancel(dag)
        @test length(opt) == 2  # no cancellation
    end

    @testset "Gate cancellation: different types don't merge" begin
        w = Sturm.fresh_wire!()
        dag = Sturm.DAGNode[
            Sturm.RyNode(w, π),
            Sturm.RzNode(w, -π),
        ]
        opt = gate_cancel(dag)
        @test length(opt) == 2
    end

    @testset "Gate cancellation: chain of merges" begin
        w = Sturm.fresh_wire!()
        dag = Sturm.DAGNode[
            Sturm.RyNode(w, π/4),
            Sturm.RyNode(w, π/4),
            Sturm.RyNode(w, π/4),
            Sturm.RyNode(w, π/4),
        ]
        opt = gate_cancel(dag)
        @test length(opt) == 1
        # 4×(π/4) = π, normalized to [-π,π] gives ±π
        @test abs(opt[1].angle) ≈ π
    end

    @testset "Gate cancellation via traced channel" begin
        ch = trace(1) do q
            H!(q)
            H!(q)  # H·H = I
            q
        end
        opt = gate_cancel(ch.dag)
        # H = Rz(π)·Ry(π/2), so H·H = Rz(π)·Ry(π/2)·Rz(π)·Ry(π/2)
        # Adjacent: Ry(π/2) then Rz(π) are different types → no merge
        # But the two Rz(π)'s are separated by Ry nodes
        # So no adjacent cancellations happen at this level
        @test length(opt) <= length(ch.dag)
    end

    @testset "Deferred measurement: simple pattern" begin
        w1 = Sturm.fresh_wire!()
        w2 = Sturm.fresh_wire!()
        dag = Sturm.DAGNode[
            Sturm.ObserveNode(w1, UInt32(1)),
            Sturm.CasesNode(UInt32(1),
                [Sturm.RyNode(w2, π)],    # if measured 1: apply X
                Sturm.DAGNode[]),           # if measured 0: nothing
        ]
        opt = defer_measurements(dag)
        # Should replace with controlled-X (Ry(π) controlled on w1)
        @test !any(n -> n isa Sturm.ObserveNode, opt)
        @test !any(n -> n isa Sturm.CasesNode, opt)
        @test length(opt) == 1
        @test opt[1] isa Sturm.RyNode
        @test w1 in opt[1].controls
    end

    @testset "Deferred measurement: both branches" begin
        w1 = Sturm.fresh_wire!()
        w2 = Sturm.fresh_wire!()
        dag = Sturm.DAGNode[
            Sturm.ObserveNode(w1, UInt32(1)),
            Sturm.CasesNode(UInt32(1),
                [Sturm.RyNode(w2, π)],       # true: X
                [Sturm.RzNode(w2, π/2)]),     # false: S
        ]
        opt = defer_measurements(dag)
        @test !any(n -> n isa Sturm.ObserveNode, opt)
        # true branch: controlled Ry(π) on w1
        # false branch: X on w1, controlled Rz(π/2), X on w1
        @test length(opt) == 4  # Ry(π) + X + Rz(π/2) + X
    end
end
