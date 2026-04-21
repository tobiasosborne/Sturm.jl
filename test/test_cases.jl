using Test
using Sturm
using Sturm: cases, @cases

@testset "cases() — classical-conditioned operations" begin

    # ── EagerContext: dispatches to correct branch based on actual measurement ──

    @testset "EagerContext: cases dispatches to then on outcome=1" begin
        @context EagerContext() begin
            ran_then = Ref(false); ran_else = Ref(false)
            q = QBool(1.0)   # |1⟩ — deterministic measurement = true
            cases(q, () -> (ran_then[] = true), () -> (ran_else[] = true))
            @test ran_then[] === true
            @test ran_else[] === false
        end
    end

    @testset "EagerContext: cases dispatches to else on outcome=0" begin
        @context EagerContext() begin
            ran_then = Ref(false); ran_else = Ref(false)
            q = QBool(0.0)   # |0⟩ — deterministic measurement = false
            cases(q, () -> (ran_then[] = true), () -> (ran_else[] = true))
            @test ran_then[] === false
            @test ran_else[] === true
        end
    end

    @testset "EagerContext: default else is no-op" begin
        @context EagerContext() begin
            ran = Ref(false)
            q0 = QBool(0.0)
            cases(q0, () -> (ran[] = true))   # else defaults to nothing
            @test ran[] === false             # outcome 0, no-op else didn't error

            ran[] = false
            q1 = QBool(1.0)
            cases(q1, () -> (ran[] = true))
            @test ran[] === true
        end
    end

    @testset "EagerContext: cases applies controlled correction" begin
        # Pattern: measure ancilla; if 1, X the target. Like a syndrome correction.
        @context EagerContext() begin
            target = QBool(0.0)
            ancilla = QBool(1.0)
            cases(ancilla, () -> X!(target))
            @test Bool(target) === true
        end
        @context EagerContext() begin
            target = QBool(0.0)
            ancilla = QBool(0.0)
            cases(ancilla, () -> X!(target))
            @test Bool(target) === false
        end
    end

    # ── HardwareContext: cases works through the round-trip path ────────────────

    @testset "HardwareContext: cases dispatches correctly" begin
        sim = Sturm.IdealisedSimulator(; capacity=4)
        ctx = Sturm.HardwareContext(Sturm.InProcessTransport(sim); capacity=4)
        @context ctx begin
            target = QBool(0.0)
            ancilla = QBool(1.0)
            cases(ancilla, () -> X!(target))
            @test Bool(target) === true
        end
        close(ctx)
    end

    # ── @cases macro: parses and dispatches identically ─────────────────────────

    @testset "@cases macro with single begin block (then-only)" begin
        @context EagerContext() begin
            ran = Ref(false)
            q = QBool(1.0)
            @cases q begin
                ran[] = true
            end
            @test ran[] === true
        end
    end

    @testset "@cases macro with two begin blocks (then + else)" begin
        @context EagerContext() begin
            r1 = Ref(false); r2 = Ref(false)
            q = QBool(0.0)   # outcome = false → else fires
            @cases q begin
                r1[] = true
            end begin
                r2[] = true
            end
            @test r1[] === false
            @test r2[] === true
        end
    end

    # ── TracingContext: emits ObserveNode + CasesNode with both branches ────────

    @testset "TracingContext: cases emits ObserveNode + CasesNode" begin
        ctx = Sturm.TracingContext()
        @context ctx begin
            q = QBool(0)
            target = QBool(0)
            cases(q, () -> X!(target), () -> Z!(target))
            discard!(target)
        end
        # Find the observe + cases pair
        obs_idx = findfirst(n -> n isa Sturm.ObserveNode, ctx.dag)
        @test obs_idx !== nothing
        cases_idx = findfirst(n -> n isa Sturm.CasesNode, ctx.dag)
        @test cases_idx !== nothing
        @test cases_idx == obs_idx + 1   # adjacent
        cn = ctx.dag[cases_idx]
        @test cn.condition_id == ctx.dag[obs_idx].result_id
        @test !isempty(cn.true_branch)   # X! emitted into true branch
        @test !isempty(cn.false_branch)  # Z! emitted into false branch
    end

    @testset "TracingContext: branch ops land in correct sub-DAG" begin
        ctx = Sturm.TracingContext()
        a_wire = b_wire = c_wire = nothing
        @context ctx begin
            q = QBool(0)
            a = QBool(0); b = QBool(0); c = QBool(0)
            a_wire = a.wire; b_wire = b.wire; c_wire = c.wire
            cases(q, () -> (X!(a); X!(b)), () -> Z!(c))
            discard!(a); discard!(b); discard!(c)
        end
        cn = ctx.dag[findfirst(n -> n isa Sturm.CasesNode, ctx.dag)]
        true_wires = Set{Sturm.WireID}()
        Sturm._collect_wires!(true_wires, cn.true_branch)
        @test a_wire in true_wires
        @test b_wire in true_wires
        @test !(c_wire in true_wires)
        false_wires = Set{Sturm.WireID}()
        Sturm._collect_wires!(false_wires, cn.false_branch)
        @test c_wire in false_wires
        @test !(a_wire in false_wires)
    end

    # ── trace() auto-lowers CasesNodes via defer_measurements ──────────────────

    @testset "trace(): auto-lowers cases to controlled gates" begin
        ch = trace(1) do q
            target = QBool(0)
            cases(q, () -> X!(target))
            target
        end
        # Channel has no ObserveNode or CasesNode after auto-lower
        @test !any(n -> n isa Sturm.CasesNode, ch.dag)
        @test !any(n -> n isa Sturm.ObserveNode, ch.dag)
        # The X! becomes controlled-X (controlled on q's wire)
        @test any(n -> n isa Sturm.RyNode && n.ncontrols >= 1, ch.dag)
    end

    @testset "trace(): nested measurement inside cases body errors loudly" begin
        # Bool(q2) inside cases body → measurement that defer_measurements can't lower
        @test_throws ErrorException trace(1) do q
            target = QBool(0)
            cases(q, () -> begin
                ancilla = QBool(0)
                _ = Bool(ancilla)  # nested measurement
            end)
            target
        end
    end

    # ── Failure modes for raw Bool(q) / Int(q) inside TracingContext ────────────

    @testset "Bool(q) inside TracingContext errors with migration message" begin
        ctx = Sturm.TracingContext()
        try
            @context ctx begin
                q = QBool(0)
                _ = Bool(q)
            end
            @test false  # should have errored
        catch e
            @test e isa ErrorException
            msg = sprint(showerror, e)
            @test occursin("cases", msg) || occursin("discard!", msg)
        end
    end

    @testset "Int(q::QInt) inside TracingContext errors" begin
        ctx = Sturm.TracingContext()
        @test_throws ErrorException @context ctx begin
            qi = QInt{4}(0)
            _ = Int(qi)
        end
    end

    # ── Empty-cases idiom: measure-and-discard-result with IR record ────────────
    # The empty-then/empty-else CasesNode records the measurement in the IR
    # (via the preceding ObserveNode) without any classical branching. Used
    # when the user wants the trace/QASM output to contain a measurement
    # instruction but does not need the result for further classical control.

    @testset "Empty cases() records ObserveNode without classical branching" begin
        ctx = Sturm.TracingContext()
        @context ctx begin
            q = QBool(0)
            cases(q, () -> nothing)   # empty then; default empty else
        end
        # ObserveNode appended; CasesNode appended (both branches empty)
        @test any(n -> n isa Sturm.ObserveNode, ctx.dag)
        cn_idx = findfirst(n -> n isa Sturm.CasesNode, ctx.dag)
        @test cn_idx !== nothing
        @test isempty(ctx.dag[cn_idx].true_branch)
        @test isempty(ctx.dag[cn_idx].false_branch)
    end

    @testset "trace() with empty cases() preserves ObserveNode (lowering drops empty CasesNode)" begin
        # defer_measurements should drop the empty CasesNode and leave just
        # the ObserveNode in the lowered Channel — so QASM emission has the
        # measurement record.
        ch = trace(1) do q
            H!(q)
            cases(q, () -> nothing)
            nothing
        end
        @test any(n -> n isa Sturm.ObserveNode, ch.dag)
        @test !any(n -> n isa Sturm.CasesNode, ch.dag)
    end
end
