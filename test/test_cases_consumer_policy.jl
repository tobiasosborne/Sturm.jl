using Test
using Logging
using Sturm

# Bead Sturm.jl-eiq — CasesNode consumer policy.
#
# CasesNode is an intermediate-only IR form: produced by `cases()` /
# TracingContext, consumed (lowered or errored) by `defer_measurements`,
# and emitted directly by `to_openqasm` for OpenQASM 3 dynamic-circuit
# export. Every *other* consumer in the DAG stack is a sink for HotNode-
# only data (Channel storage, gate_cancel, draw, pixels). The previous
# mixed behaviour (silent strip vs silent placeholder) was the kind of
# footgun Rule 1 forbids — this testset pins the fail-loud / warn-once
# policy in place so future drift is caught immediately.

@testset "CasesNode consumer policy (Sturm.jl-eiq)" begin

    # Helper: build a minimal DAG with a CasesNode for the assertion targets.
    # Fresh wires per call so wire-collation passes don't conflate with
    # sibling tests in the same Julia session.
    function _dag_with_cases()
        w = Sturm.fresh_wire!()
        rid = UInt32(rand(1:typemax(UInt32) - 1))
        return Sturm.DAGNode[
            Sturm.ObserveNode(w, rid),
            Sturm.CasesNode(rid, [Sturm.RyNode(w, π)], Sturm.DAGNode[]),
        ]
    end

    # ── (d) Channel{In,Out}(::Vector{DAGNode}, ...) — was silent strip ──────────

    @testset "Channel compat constructor errors loud on CasesNode" begin
        dag = _dag_with_cases()
        w = dag[1].wire
        try
            Sturm.Channel{1, 1}(dag, (w,), (w,))
            @test false  # should have thrown
        catch e
            @test e isa ErrorException
            msg = sprint(showerror, e)
            @test occursin("CasesNode", msg)
            @test occursin("optimise", msg)  # migration hint to :deferred
        end
    end

    @testset "Channel compat constructor accepts HotNode-only Vector{DAGNode}" begin
        # Same compat path must still work for the legitimate use:
        # raw HotNode dag wrapped in DAGNode element-type. This is what
        # test_pixels / test_draw / test_qsvt_phase_factors / bench_shor_i0j
        # rely on.
        w = Sturm.fresh_wire!()
        dag = Sturm.DAGNode[Sturm.RyNode(w, π/4)]
        ch = Sturm.Channel{1, 1}(dag, (w,), (w,))
        @test length(ch.dag) == 1
        @test ch.dag[1] isa Sturm.RyNode
    end

    # ── (b) gate_cancel(::Vector{DAGNode}) — was silent strip ──────────────────

    @testset "gate_cancel compat overload errors loud on CasesNode" begin
        dag = _dag_with_cases()
        try
            gate_cancel(dag)
            @test false
        catch e
            @test e isa ErrorException
            msg = sprint(showerror, e)
            @test occursin("CasesNode", msg)
            @test occursin("defer_measurements", msg) || occursin("optimise", msg)
        end
    end

    @testset "gate_cancel compat overload preserves HotNode-only inputs" begin
        # Existing test_passes.jl pattern: Vector{DAGNode} with only HotNodes.
        # Must not regress — this is the standard idiom.
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

    # ── (c) renderers: keep placeholder, but @warn once per source location ────
    #
    # CasesNode reaches the renderer only via raw-DAG entries that don't
    # exist on `to_ascii(::Channel)` today (Channel.dag is Vector{HotNode}
    # so trace-emitted Channels never carry CasesNode). The warning lives
    # on the dispatched method so any future raw-DAG entry inherits it;
    # tests call `_draw_node!` / `_paint_node_px!` directly.

    @testset "_draw_node!(::CasesNode, ...) emits a warning" begin
        cn = Sturm.CasesNode(UInt32(7), Sturm.DAGNode[], Sturm.DAGNode[])
        grid = fill(' ', 3, 16)
        styles = fill(0x00, 3, 16)
        offs = [0, 8, 16]
        widths = [8, 8]
        row_of = Dict{Sturm.WireID, Int}()
        bit_rows = Dict{UInt32, Int}()
        @test_logs (:warn, r"CasesNode") begin
            Sturm._draw_node!(grid, styles, cn, 0, offs, widths,
                              row_of, bit_rows, 1, true)
        end
    end

    @testset "_paint_node_px!(::CasesNode, ...) emits a warning" begin
        cn = Sturm.CasesNode(UInt32(11), Sturm.DAGNode[], Sturm.DAGNode[])
        sch = Sturm._resolve_scheme(:birren_dark)
        img = fill(sch.bg, 8, 32)
        col_w = 4
        row_of = Dict{Sturm.WireID, Int}()
        bit_row_abs = Dict{UInt32, Int}()
        @test_logs (:warn, r"CasesNode") begin
            Sturm._paint_node_px!(img, cn, 0, col_w, row_of, bit_row_abs, sch, 1, 1)
        end
    end

    # ── (a) openqasm.jl — already supports CasesNode via dynamic-circuit ──────
    # Sanity pin: the bead-original "(a) errors" criterion is OBSOLETE.
    # `to_openqasm` on a raw DAG containing CasesNode emits OpenQASM 3
    # `if (c[i] == 1) { ... }` — preserving classical branching for
    # IBM/Quantinuum dynamic-circuit hardware. Documented on the
    # docstring at src/channel/openqasm.jl. Closing this assertion here
    # so a future "fail-loud" sweep doesn't accidentally regress it.

    @testset "to_openqasm raw-DAG form emits dynamic-circuit if for CasesNode" begin
        dag = _dag_with_cases()
        w = dag[1].wire
        qasm = Sturm.to_openqasm(dag, [w], [w])
        @test occursin("if (c[", qasm)
        @test occursin("ry", qasm)
    end
end
