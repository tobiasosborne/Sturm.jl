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

    @testset "Gate cancellation via traced channel (H·H)" begin
        ch = trace(1) do q
            H!(q)
            H!(q)  # H·H = -I (global phase)
            q
        end
        opt = gate_cancel(ch.dag)
        # H = Rz(π)·Ry(π/2), so H·H = Rz(π)·Ry(π/2)·Rz(π)·Ry(π/2)
        # Ry(π/2) and Rz(π) are on the SAME wire → don't commute → can't merge
        # across types. But adjacent same-type: none adjacent. No improvement here.
        @test length(opt) <= length(ch.dag)
    end

    # ── Commutation-aware merging ──

    @testset "Non-adjacent merge: Ry through disjoint-wire gate" begin
        w1 = Sturm.fresh_wire!()
        w2 = Sturm.fresh_wire!()
        dag = Sturm.DAGNode[
            Sturm.RyNode(w1, π/4),
            Sturm.RyNode(w2, π/3),   # different wire — commutes
            Sturm.RyNode(w1, π/4),
        ]
        opt = gate_cancel(dag)
        # Ry(π/4, w1) merges with Ry(π/4, w1) through disjoint Ry(w2)
        @test length(opt) == 2
        ry_w1 = filter(n -> n isa Sturm.RyNode && n.wire == w1, opt)
        @test length(ry_w1) == 1
        @test ry_w1[1].angle ≈ π/2
    end

    @testset "Non-adjacent cancel: Ry(θ)…Ry(-θ) through disjoint gates" begin
        w1 = Sturm.fresh_wire!()
        w2 = Sturm.fresh_wire!()
        w3 = Sturm.fresh_wire!()
        dag = Sturm.DAGNode[
            Sturm.RyNode(w1, π/3),
            Sturm.RzNode(w2, π/4),       # disjoint
            Sturm.CXNode(w2, w3),         # disjoint from w1
            Sturm.RyNode(w1, -π/3),
        ]
        opt = gate_cancel(dag)
        # Ry(π/3) and Ry(-π/3) cancel; only Rz and CX remain
        @test length(opt) == 2
        @test !any(n -> n isa Sturm.RyNode, opt)
    end

    @testset "Rz commutes through CX control" begin
        w1 = Sturm.fresh_wire!()
        w2 = Sturm.fresh_wire!()
        dag = Sturm.DAGNode[
            Sturm.RzNode(w1, π/4),
            Sturm.CXNode(w1, w2),         # w1 is control — Rz commutes
            Sturm.RzNode(w1, π/4),
        ]
        opt = gate_cancel(dag)
        # Rz(π/4) merges with Rz(π/4) through CX
        @test length(opt) == 2  # merged Rz + CX
        rz = filter(n -> n isa Sturm.RzNode, opt)
        @test length(rz) == 1
        @test rz[1].angle ≈ π/2
    end

    @testset "Ry does NOT commute through CX control" begin
        w1 = Sturm.fresh_wire!()
        w2 = Sturm.fresh_wire!()
        dag = Sturm.DAGNode[
            Sturm.RyNode(w1, π/4),
            Sturm.CXNode(w1, w2),         # w1 is control — Ry does NOT commute
            Sturm.RyNode(w1, π/4),
        ]
        opt = gate_cancel(dag)
        # Should NOT merge — Ry doesn't commute with CX on shared wire
        @test length(opt) == 3
    end

    @testset "Rz does NOT commute through CX target" begin
        w1 = Sturm.fresh_wire!()
        w2 = Sturm.fresh_wire!()
        dag = Sturm.DAGNode[
            Sturm.RzNode(w2, π/4),
            Sturm.CXNode(w1, w2),         # w2 is target — Rz does NOT commute
            Sturm.RzNode(w2, π/4),
        ]
        opt = gate_cancel(dag)
        @test length(opt) == 3
    end

    @testset "CX-CX cancellation (adjacent)" begin
        w1 = Sturm.fresh_wire!()
        w2 = Sturm.fresh_wire!()
        dag = Sturm.DAGNode[
            Sturm.CXNode(w1, w2),
            Sturm.CXNode(w1, w2),
        ]
        opt = gate_cancel(dag)
        @test isempty(opt)
    end

    @testset "CX-CX cancellation (non-adjacent, disjoint intervening)" begin
        w1 = Sturm.fresh_wire!()
        w2 = Sturm.fresh_wire!()
        w3 = Sturm.fresh_wire!()
        dag = Sturm.DAGNode[
            Sturm.CXNode(w1, w2),
            Sturm.RyNode(w3, π/4),        # disjoint — commutes
            Sturm.CXNode(w1, w2),
        ]
        opt = gate_cancel(dag)
        # CXs cancel through disjoint Ry
        @test length(opt) == 1
        @test opt[1] isa Sturm.RyNode
    end

    @testset "CX-CX no cancel (different wires)" begin
        w1 = Sturm.fresh_wire!()
        w2 = Sturm.fresh_wire!()
        w3 = Sturm.fresh_wire!()
        dag = Sturm.DAGNode[
            Sturm.CXNode(w1, w2),
            Sturm.CXNode(w1, w3),         # different target
        ]
        opt = gate_cancel(dag)
        @test length(opt) == 2
    end

    @testset "Blocked by non-unitary node (ObserveNode)" begin
        w1 = Sturm.fresh_wire!()
        dag = Sturm.DAGNode[
            Sturm.RyNode(w1, π/4),
            Sturm.ObserveNode(w1, UInt32(1)),
            Sturm.RyNode(w1, π/4),
        ]
        opt = gate_cancel(dag)
        # ObserveNode on same wire blocks commutation
        @test length(opt) == 3
    end

    @testset "Controlled rotations: same controls merge" begin
        w = Sturm.fresh_wire!()
        c = Sturm.fresh_wire!()
        dag = Sturm.DAGNode[
            Sturm.RzNode(w, π/4, [c]),
            Sturm.RzNode(w, π/4, [c]),
        ]
        opt = gate_cancel(dag)
        @test length(opt) == 1
        @test opt[1].angle ≈ π/2
        @test c in Sturm.get_controls(opt[1])
    end

    @testset "Controlled rotations: different controls don't merge" begin
        w = Sturm.fresh_wire!()
        c1 = Sturm.fresh_wire!()
        c2 = Sturm.fresh_wire!()
        dag = Sturm.DAGNode[
            Sturm.RzNode(w, π/4, [c1]),
            Sturm.RzNode(w, π/4, [c2]),
        ]
        opt = gate_cancel(dag)
        @test length(opt) == 2
    end

    @testset "Multi-pass convergence: cascading cancellations" begin
        w1 = Sturm.fresh_wire!()
        w2 = Sturm.fresh_wire!()
        # After CX-CX cancel on w1,w2, the Rz's become adjacent and should merge
        dag = Sturm.DAGNode[
            Sturm.RzNode(w1, π/4),
            Sturm.CXNode(w1, w2),
            Sturm.CXNode(w1, w2),         # CX pair cancels
            Sturm.RzNode(w1, π/4),
        ]
        opt = gate_cancel(dag)
        # CX pair cancelled → Rz(π/4) + Rz(π/4) merge → Rz(π/2)
        @test length(opt) == 1
        @test opt[1] isa Sturm.RzNode
        @test opt[1].angle ≈ π/2
    end

    # ── optimise(ch, :pass) API ──

    @testset "optimise(ch, :cancel) returns optimised Channel" begin
        ch = trace(1) do q
            q.θ += π/4
            q.θ += π/4
            q
        end
        ch2 = optimise(ch, :cancel)
        @test ch2 isa Sturm.Channel
        @test n_inputs(ch2) == 1
        @test n_outputs(ch2) == 1
        @test length(ch2.dag) < length(ch.dag)
        @test length(ch2.dag) == 1
        @test ch2.dag[1] isa Sturm.RyNode
        @test ch2.dag[1].angle ≈ π/2
    end

    @testset "optimise(ch, :deferred) wraps defer_measurements" begin
        w1 = Sturm.fresh_wire!()
        w2 = Sturm.fresh_wire!()
        dag = Sturm.DAGNode[
            Sturm.ObserveNode(w1, UInt32(99)),
            Sturm.CasesNode(UInt32(99),
                [Sturm.RyNode(w2, π)],
                Sturm.DAGNode[]),
        ]
        ch = Sturm.Channel{0, 0}(dag, (), ())
        ch2 = optimise(ch, :deferred)
        @test !any(n -> n isa Sturm.ObserveNode, ch2.dag)
    end

    @testset "optimise(ch, :all) chains passes" begin
        ch = trace(1) do q
            q.θ += π/4
            q.θ += π/4
            q
        end
        ch2 = optimise(ch, :all)
        @test length(ch2.dag) == 1
    end

    @testset "optimise unknown pass errors" begin
        ch = trace(1) do q; q; end
        @test_throws ErrorException optimise(ch, :nonexistent)
    end

    # ── Deferred measurement ──

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
        @test w1 in Sturm.get_controls(opt[1])
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
