using Test
using Sturm
using Sturm: to_openqasm, ObserveNode, CasesNode, RyNode, RzNode, CXNode,
             DAGNode, fresh_wire!, WireID

# OpenQASM 3.0 dynamic-circuit emission for CasesNode.
# Closes Sturm.jl-tak: the previous emitter silently dropped CasesNode.

@testset "OpenQASM 3 dynamic-circuit emission (HW tak)" begin

    @testset "Then-only branch emits if (c[0] == 1) { ... }" begin
        w1 = fresh_wire!()
        w2 = fresh_wire!()
        dag = DAGNode[
            ObserveNode(w1, UInt32(1)),
            CasesNode(UInt32(1), DAGNode[RyNode(w2, π)], DAGNode[]),
        ]
        qasm = to_openqasm(dag, [w1, w2], WireID[])
        @test occursin("OPENQASM 3", qasm)
        @test occursin("c[0] = measure", qasm)
        @test occursin("if (c[0] == 1)", qasm)
        @test occursin("ry(", qasm)
        # No else branch
        @test !occursin("else", qasm)
    end

    @testset "Both branches emit if/else" begin
        w1 = fresh_wire!()
        w2 = fresh_wire!()
        dag = DAGNode[
            ObserveNode(w1, UInt32(1)),
            CasesNode(UInt32(1),
                DAGNode[RyNode(w2, π)],
                DAGNode[RzNode(w2, π / 2)]),
        ]
        qasm = to_openqasm(dag, [w1, w2], WireID[])
        @test occursin("if (c[0] == 1)", qasm)
        @test occursin("else", qasm)
        @test occursin("ry(", qasm)
        @test occursin("rz(", qasm)
    end

    @testset "Multiple measurements: bit indices match condition_id ordering" begin
        # Two measurements; the SECOND one's CasesNode should reference c[1]
        w1 = fresh_wire!()
        w2 = fresh_wire!()
        w3 = fresh_wire!()
        dag = DAGNode[
            ObserveNode(w1, UInt32(11)),
            ObserveNode(w2, UInt32(22)),
            CasesNode(UInt32(22), DAGNode[RyNode(w3, π)], DAGNode[]),
        ]
        qasm = to_openqasm(dag, [w1, w2, w3], WireID[])
        @test occursin("c[0] = measure", qasm)
        @test occursin("c[1] = measure", qasm)
        @test occursin("if (c[1] == 1)", qasm)   # references second measurement
        @test !occursin("if (c[0] == 1)", qasm)
    end

    @testset "Channel-level to_openqasm still works (no CasesNode)" begin
        # Ensure existing Channel API unchanged for non-cases circuits
        ch = trace(1) do q
            H!(q)
            q
        end
        qasm = to_openqasm(ch)
        @test occursin("OPENQASM 3", qasm)
        @test occursin("ry", qasm)
    end

    @testset "Empty CasesNode bodies don't emit if-block (no-op suppressed)" begin
        # Both branches empty → entire if-block redundant, suppress
        w1 = fresh_wire!()
        dag = DAGNode[
            ObserveNode(w1, UInt32(1)),
            CasesNode(UInt32(1), DAGNode[], DAGNode[]),
        ]
        qasm = to_openqasm(dag, [w1], WireID[])
        @test occursin("c[0] = measure", qasm)
        @test !occursin("if (", qasm)   # empty cases suppressed
    end
end
