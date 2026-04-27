using Bennett: ReversibleCircuit, ReversibleGate, NOTGate, CNOTGate, ToffoliGate,
               WireIndex, reversible_compile, simulate, gate_count

# ── Pre-compile circuits ONCE (expensive) ───────────────────────────────────
t0 = time()
const _CIRCUIT_ID   = reversible_compile(identity, Int8)
println("  compiled identity: $(time()-t0)s, $(_CIRCUIT_ID.n_wires) wires, $(gate_count(_CIRCUIT_ID).total) gates")
flush(stdout)

t1 = time()
const _CIRCUIT_INC  = reversible_compile(x -> x + Int8(1), Int8)
println("  compiled x+1:      $(time()-t1)s, $(_CIRCUIT_INC.n_wires) wires, $(gate_count(_CIRCUIT_INC).total) gates")
flush(stdout)

t2 = time()
const _CIRCUIT_ADD3 = reversible_compile(x -> x + Int8(3), Int8)
println("  compiled x+3:      $(time()-t2)s, $(_CIRCUIT_ADD3.n_wires) wires, $(gate_count(_CIRCUIT_ADD3).total) gates")
flush(stdout)

# ── Helper: encode Int8 → qubits, run circuit, measure result ───────────────
function _run_bennett_e2e(circuit::ReversibleCircuit, test_val::Int8)
    @context EagerContext(capacity=circuit.n_wires + 2) begin
        ctx = current_context()
        input_wires = WireID[]
        for i in 1:8
            bit = (reinterpret(UInt8, test_val) >> (i - 1)) & 1
            push!(input_wires, QBool(Float64(bit)).wire)
        end
        output_wires = WireID[]
        for _ in 1:8
            push!(output_wires, QBool(0.0).wire)
        end
        wm = Sturm.build_wire_map(circuit, input_wires, output_wires)
        Sturm.apply_reversible!(ctx, circuit, wm)
        result_bits = UInt8(0)
        for (i, w) in enumerate(output_wires)
            bit = Sturm.measure!(ctx, w)
            result_bits |= UInt8(bit) << (i - 1)
        end
        return reinterpret(Int8, result_bits)
    end
end

@testset verbose=true "Bennett Integration" begin

# ── apply_ccx! ──────────────────────────────────────────────────────────────

@testset verbose=true "apply_ccx!" begin
    @testset "EagerContext" begin
        @testset "flips target when both controls |1⟩" begin
            @context EagerContext() begin
                ctx = current_context()
                c1 = QBool(1.0); c2 = QBool(1.0); t = QBool(0.0)
                Sturm.apply_ccx!(ctx, c1.wire, c2.wire, t.wire)
                @test Bool(t) == true
            end
        end

        @testset "no flip when one control |0⟩" begin
            @context EagerContext() begin
                ctx = current_context()
                c1 = QBool(1.0); c2 = QBool(0.0); t = QBool(0.0)
                Sturm.apply_ccx!(ctx, c1.wire, c2.wire, t.wire)
                @test Bool(t) == false
            end
        end

        @testset "no flip when both controls |0⟩" begin
            @context EagerContext() begin
                ctx = current_context()
                c1 = QBool(0.0); c2 = QBool(0.0); t = QBool(0.0)
                Sturm.apply_ccx!(ctx, c1.wire, c2.wire, t.wire)
                @test Bool(t) == false
            end
        end

        @testset "self-inverse" begin
            @context EagerContext() begin
                ctx = current_context()
                c1 = QBool(1.0); c2 = QBool(1.0); t = QBool(0.0)
                Sturm.apply_ccx!(ctx, c1.wire, c2.wire, t.wire)
                Sturm.apply_ccx!(ctx, c1.wire, c2.wire, t.wire)
                @test Bool(t) == false
            end
        end

        @testset "inside when() — control ON" begin
            @context EagerContext() begin
                ctx = current_context()
                ctrl = QBool(1.0); c1 = QBool(1.0); c2 = QBool(1.0); t = QBool(0.0)
                when(ctrl) do
                    Sturm.apply_ccx!(ctx, c1.wire, c2.wire, t.wire)
                end
                @test Bool(t) == true
            end
        end

        @testset "inside when() — control OFF" begin
            @context EagerContext() begin
                ctx = current_context()
                ctrl = QBool(0.0); c1 = QBool(1.0); c2 = QBool(1.0); t = QBool(0.0)
                when(ctrl) do
                    Sturm.apply_ccx!(ctx, c1.wire, c2.wire, t.wire)
                end
                @test Bool(t) == false
            end
        end
    end

    @testset "TracingContext records CXNode with 1 control" begin
        ctx = TracingContext()
        w1 = Sturm.allocate!(ctx); w2 = Sturm.allocate!(ctx); w3 = Sturm.allocate!(ctx)
        Sturm.apply_ccx!(ctx, w1, w2, w3)
        node = ctx.dag[end]
        @test node isa Sturm.CXNode
        @test node.control == w2
        @test node.target == w3
        @test node.ncontrols == 1
        @test node.ctrl1 == w1
    end

    @testset "DensityMatrixContext" begin
        @context DensityMatrixContext() begin
            ctx = current_context()
            c1 = QBool(1.0); c2 = QBool(1.0); t = QBool(0.0)
            Sturm.apply_ccx!(ctx, c1.wire, c2.wire, t.wire)
            @test Bool(t) == true
        end
    end
end

# ── Batch allocation ────────────────────────────────────────────────────────

@testset "Batch allocation" begin
    @testset "allocate_batch! returns n fresh qubits" begin
        @context EagerContext() begin
            ctx = current_context()
            wires = Sturm.allocate_batch!(ctx, 5)
            @test length(wires) == 5
            @test length(unique(wires)) == 5
        end
    end

    @testset "deallocate_batch!" begin
        # bead Sturm.jl-w9e: pin the user-visible invariant ("ancillae are
        # consumed and no longer live"), not the implementation detail
        # (`free_slots`), which compaction may zero. The slot-recycling
        # bookkeeping is checked separately, branching on whether the
        # auto-trigger fired (sub-threshold here at 3 < 2*GROW_STEP=8, so
        # compact does NOT fire — but the assertion is robust either way).
        @context EagerContext() begin
            ctx = current_context()
            wires = Sturm.allocate_batch!(ctx, 3)
            Sturm.deallocate_batch!(ctx, wires)
            for w in wires
                @test w in ctx.consumed
                @test !haskey(ctx.wire_to_qubit, w)
            end
            @test isempty(ctx.wire_to_qubit)
            if ctx._compact_count == 0
                @test length(ctx.free_slots) == 3
            else
                @test isempty(ctx.free_slots)
                @test ctx.n_qubits == 0
            end
        end
    end

    @testset "TracingContext batch" begin
        ctx = TracingContext()
        wires = Sturm.allocate_batch!(ctx, 4)
        @test length(wires) == 4
        @test length(unique(wires)) == 4
    end
end

# ── apply_reversible! ──────────────────────────────────────────────────────

@testset verbose=true "apply_reversible!" begin
    @testset "single NOTGate" begin
        @context EagerContext() begin
            ctx = current_context()
            q = QBool(0.0)
            circuit = ReversibleCircuit(
                1, ReversibleGate[NOTGate(1)],
                WireIndex[1], WireIndex[1], WireIndex[], [1], [1])
            Sturm.apply_reversible!(ctx, circuit, Dict{WireIndex,WireID}(1 => q.wire))
            @test Bool(q) == true
        end
    end

    @testset "CNOTGate maps to CX" begin
        @context EagerContext() begin
            ctx = current_context()
            a = QBool(0.0); b = QBool(1.0)
            circuit = ReversibleCircuit(
                2, ReversibleGate[CNOTGate(2, 1)],
                WireIndex[1, 2], WireIndex[1, 2], WireIndex[], [1, 1], [1, 1])
            Sturm.apply_reversible!(ctx, circuit, Dict{WireIndex,WireID}(1 => a.wire, 2 => b.wire))
            @test Bool(a) == true
        end
    end

    @testset "inside when() — control ON" begin
        @context EagerContext() begin
            ctx = current_context()
            ctrl = QBool(1.0); target = QBool(0.0)
            circuit = ReversibleCircuit(
                1, ReversibleGate[NOTGate(1)],
                WireIndex[1], WireIndex[1], WireIndex[], [1], [1])
            when(ctrl) do
                Sturm.apply_reversible!(ctx, circuit, Dict{WireIndex,WireID}(1 => target.wire))
            end
            @test Bool(target) == true
        end
    end

    @testset "inside when() — control OFF" begin
        @context EagerContext() begin
            ctx = current_context()
            ctrl = QBool(0.0); target = QBool(0.0)
            circuit = ReversibleCircuit(
                1, ReversibleGate[NOTGate(1)],
                WireIndex[1], WireIndex[1], WireIndex[], [1], [1])
            when(ctrl) do
                Sturm.apply_reversible!(ctx, circuit, Dict{WireIndex,WireID}(1 => target.wire))
            end
            @test Bool(target) == false
        end
    end

    @testset "NOTGate channel matches Sturm not! — bead Sturm.jl-ls8" begin
        # Bennett-NOT must produce the same channel as `not!` (= Rz(π)·Ry(π) = iX,
        # det=-1). A single Ry(π) is -iY (det=+1, channel ρ↦YρY) — wrong gate.
        #
        # X|+⟩ = |+⟩ (eigenstate, +1 eigenvalue) so iX|+⟩ = i|+⟩, and H|+⟩=|0⟩.
        # Y|+⟩ = -i|-⟩ so (-iY)|+⟩ = -|-⟩, and H|-⟩=|1⟩.
        # Single-shot deterministic distinguisher: prep |+⟩, apply NOT, H, measure.
        # Correct X → 0; -iY bug → 1.
        @context EagerContext() begin
            ctx = current_context()
            q = QBool(0.5)              # |+⟩
            circuit = ReversibleCircuit(
                1, ReversibleGate[NOTGate(1)],
                WireIndex[1], WireIndex[1], WireIndex[], [1], [1])
            Sturm.apply_reversible!(ctx, circuit, Dict{WireIndex,WireID}(1 => q.wire))
            H!(q)
            @test Bool(q) == false
        end
    end

    @testset "NOTGate equivalence with Sturm not! at |+⟩, |-⟩, |+i⟩" begin
        # Same physical state preparations subjected to (a) Bennett-NOT and (b)
        # Sturm `not!` should produce the same X-basis / Y-basis measurement
        # outcome. Tests three non-computational basis states; the Y-basis case
        # (|+i⟩) cleanly separates iX (correct) from -iY (bug).
        circuit = ReversibleCircuit(
            1, ReversibleGate[NOTGate(1)],
            WireIndex[1], WireIndex[1], WireIndex[], [1], [1])

        # |+⟩ → not! → i|+⟩;  H → i|0⟩;   measure → 0.
        @context EagerContext() begin
            q = QBool(0.5)
            Sturm.apply_reversible!(current_context(), circuit,
                Dict{WireIndex,WireID}(1 => q.wire))
            H!(q)
            @test Bool(q) == false
        end

        # |-⟩ → not! → -i|-⟩; H → -i|1⟩;  measure → 1.
        @context EagerContext() begin
            q = QBool(0.5); q.φ += π     # |-⟩
            Sturm.apply_reversible!(current_context(), circuit,
                Dict{WireIndex,WireID}(1 => q.wire))
            H!(q)
            @test Bool(q) == true
        end
    end

    @testset "circuit with ancillae" begin
        @context EagerContext() begin
            ctx = current_context()
            circuit = ReversibleCircuit(
                3,
                ReversibleGate[CNOTGate(1, 2), CNOTGate(2, 3), CNOTGate(1, 2)],
                WireIndex[1], WireIndex[3], WireIndex[2], [1], [1])
            q_in = QBool(1.0); q_out = QBool(0.0)
            Sturm.apply_reversible!(ctx, circuit,
                Dict{WireIndex,WireID}(1 => q_in.wire, 3 => q_out.wire))
            @test Bool(q_out) == true
        end
    end

    @testset "TracingContext expands gates into DAG" begin
        ctx = TracingContext()
        w1 = Sturm.allocate!(ctx); w2 = Sturm.allocate!(ctx)
        circuit = ReversibleCircuit(
            2, ReversibleGate[CNOTGate(1, 2), NOTGate(2)],
            WireIndex[1, 2], WireIndex[1, 2], WireIndex[], [1, 1], [1, 1])
        Sturm.apply_reversible!(ctx, circuit, Dict{WireIndex,WireID}(1 => w1, 2 => w2))
        types = [typeof(n) for n in ctx.dag]
        @test Sturm.CXNode in types
        @test Sturm.RyNode in types
    end
end

# ── build_wire_map ──────────────────────────────────────────────────────────

@testset "build_wire_map" begin
    @testset "maps input and output wires" begin
        @context EagerContext(capacity=_CIRCUIT_ID.n_wires + 2) begin
            input_qubits = [QBool(0.0) for _ in 1:8]
            output_qubits = [QBool(0.0) for _ in 1:8]
            wm = Sturm.build_wire_map(_CIRCUIT_ID,
                [q.wire for q in input_qubits], [q.wire for q in output_qubits])
            for bw in _CIRCUIT_ID.input_wires; @test haskey(wm, bw); end
            for bw in _CIRCUIT_ID.output_wires; @test haskey(wm, bw); end
        end
    end

    @testset "errors on wire count mismatch" begin
        @test_throws ErrorException Sturm.build_wire_map(_CIRCUIT_ID, WireID[], WireID[])
    end
end

# ── End-to-end ──────────────────────────────────────────────────────────────

@testset verbose=true "End-to-end" begin
    @testset "identity Int8 (17 wires)" begin
        @test _CIRCUIT_ID.n_wires <= 30
        println("    e2e identity: first shot..."); flush(stdout)
        for test_val in Int8[0, 1, 42, 127, -1, -128]
            @test _run_bennett_e2e(_CIRCUIT_ID, test_val) == test_val
        end
        println("    e2e identity: 6 values OK"); flush(stdout)
    end

    @testset "x+1 Int8 (26 wires)" begin
        @test _CIRCUIT_INC.n_wires <= 30
        println("    e2e x+1: first shot..."); flush(stdout)
        for test_val in Int8[0, 1, 42, 127, -1, -128]
            expected = test_val + Int8(1)
            @test simulate(_CIRCUIT_INC, test_val) == expected
            @test _run_bennett_e2e(_CIRCUIT_INC, test_val) == expected
        end
        println("    e2e x+1: 6 values OK"); flush(stdout)
    end

    @testset "x+3 Int8 (26 wires)" begin
        @test _CIRCUIT_ADD3.n_wires <= 30
        println("    e2e x+3: first shot..."); flush(stdout)
        for test_val in Int8[0, 5, -1, -128, 100]
            expected = test_val + Int8(3)
            @test _run_bennett_e2e(_CIRCUIT_ADD3, test_val) == expected
        end
        println("    e2e x+3: 5 values OK"); flush(stdout)
    end
end

# ── apply_oracle! ───────────────────────────────────────────────────────────

@testset "apply_oracle!" begin
    @testset "identity Int8" begin
        test_val = Int8(42)
        @context EagerContext(capacity=_CIRCUIT_ID.n_wires + 2) begin
            ctx = current_context()
            input_wires = WireID[]
            for i in 1:8
                bit = (reinterpret(UInt8, test_val) >> (i - 1)) & 1
                push!(input_wires, QBool(Float64(bit)).wire)
            end
            output_wires = [QBool(0.0).wire for _ in 1:8]
            Sturm.apply_oracle!(ctx, identity, Int8, input_wires, output_wires)
            result_bits = UInt8(0)
            for (i, w) in enumerate(output_wires)
                bit = Sturm.measure!(ctx, w)
                result_bits |= UInt8(bit) << (i - 1)
            end
            @test reinterpret(Int8, result_bits) == test_val
        end
    end
end

# ── Resource estimation ─────────────────────────────────────────────────────

@testset "estimate_oracle_resources" begin
    r = Sturm.estimate_oracle_resources(x -> x + Int8(1), Int8)
    @test r.gates > 0
    @test r.toffoli >= 0
    @test r.t_count == r.toffoli * 7
    @test r.qubits > 0
    @test r.qubits == 26
end

# ── oracle(f, x::QInt{W}) ───────────────────────────────────────────────────

@testset verbose=true "oracle(f, x)" begin
    println("    oracle: compiling bit_width=2 circuits..."); flush(stdout)
    t_oracle = time()
    println("    oracle circuits compiled: $(round(time()-t_oracle, digits=2))s"); flush(stdout)

    @testset "identity bit_width=2 — all inputs" begin
        for v in 0:3
            @context EagerContext() begin
                x = QInt{2}(v)
                y = oracle(identity, x)
                @test Int(y) == v
                @test Int(x) == v   # input preserved
            end
        end
    end

    @testset "x+1 bit_width=2 — all inputs" begin
        println("    oracle x+1: testing..."); flush(stdout)
        for v in 0:3
            @context EagerContext() begin
                x = QInt{2}(v)
                y = oracle(x -> x + Int8(1), x)
                @test Int(y) == (v + 1) % 4
            end
        end
    end

    @testset "x*x bit_width=2 — all inputs (19 wires)" begin
        println("    oracle x*x: testing..."); flush(stdout)
        for v in 0:3
            expected = (v * v) % 4
            @context EagerContext() begin
                x = QInt{2}(v)
                y = oracle(x -> x * x, x)
                @test Int(y) == expected
            end
        end
    end

    @testset "x^2+3x+1 bit_width=2 (25 wires)" begin
        println("    oracle polynomial: testing..."); flush(stdout)
        # 25 wires = 512 MB per context; test one value to avoid OOM
        v = 2; expected = (v*v + 3*v + 1) % 4  # (4+6+1)%4 = 3
        @context EagerContext() begin
            x = QInt{2}(v)
            y = oracle(x -> x*x + Int8(3)*x + Int8(1), x)
            @test Int(y) == expected
        end
        GC.gc()
    end

    @testset "inside when() — controlled x+1" begin
        println("    oracle controlled: testing..."); flush(stdout)
        # Use x+1 (8 wires at bit_width=2) to avoid OOM from polynomial
        for v in 0:3
            # Control ON: oracle executes
            @context EagerContext() begin
                q = QBool(1.0)
                x = QInt{2}(v)
                local y
                when(q) do
                    y = oracle(x -> x + Int8(1), x)
                end
                @test Int(y) == (v + 1) % 4
            end
            # Control OFF: output stays |0⟩
            @context EagerContext() begin
                q = QBool(0.0)
                x = QInt{2}(v)
                local y
                when(q) do
                    y = oracle(x -> x + Int8(1), x)
                end
                @test Int(y) == 0
            end
        end
        println("    oracle controlled: 8 cases OK"); flush(stdout)
    end
end

# ── quantum(f) — caching wrapper ───────────────────────────────────────────

@testset verbose=true "quantum(f)" begin
    @testset "basic usage" begin
        qf = quantum(x -> x + Int8(1))
        @context EagerContext() begin
            x = QInt{2}(2)
            y = qf(x)
            @test Int(y) == 3
        end
    end

    @testset "caches circuit across calls" begin
        qf = quantum(x -> x + Int8(1))
        @context EagerContext() begin
            x1 = QInt{2}(0)
            y1 = qf(x1)
            @test Int(y1) == 1
        end
        @test haskey(qf.cache, (2, true, ()))    # key: (W=2, signed=true, no kwargs)
        @context EagerContext() begin
            x2 = QInt{2}(3)
            y2 = qf(x2)
            @test Int(y2) == 0       # (3+1) % 4 = 0
        end
    end

    @testset "different widths use different cache entries" begin
        qf = quantum(identity)
        @context EagerContext() begin
            x2 = QInt{2}(3)
            y2 = qf(x2)
            @test Int(y2) == 3
        end
        @context EagerContext() begin
            x3 = QInt{3}(7)
            y3 = qf(x3)
            @test Int(y3) == 7
        end
        @test haskey(qf.cache, (2, true, ()))
        @test haskey(qf.cache, (3, true, ()))
    end

    @testset "inside when()" begin
        qf = quantum(x -> x * x)
        @context EagerContext() begin
            q = QBool(1.0)
            x = QInt{2}(3)
            local y
            when(q) do
                y = qf(x)
            end
            @test Int(y) == (9 % 4)   # 1
        end
    end
end

# ── Width-fitting arg type (Sturm.jl-q93) ───────────────────────────────────

@testset verbose=true "arg-type selection by W" begin
    using Sturm: _bennett_arg_type

    @testset "_bennett_arg_type: signed=true (default)" begin
        # W≤8 → Int8, W≤16 → Int16, W≤32 → Int32, W≤64 → Int64
        for W in 1:8;    @test _bennett_arg_type(W) === Int8;  end
        for W in 9:16;   @test _bennett_arg_type(W) === Int16; end
        for W in [17, 24, 32]; @test _bennett_arg_type(W) === Int32; end
        for W in [33, 48, 64]; @test _bennett_arg_type(W) === Int64; end
    end

    @testset "_bennett_arg_type: signed=false" begin
        for W in 1:8;    @test _bennett_arg_type(W; signed=false) === UInt8;  end
        for W in 9:16;   @test _bennett_arg_type(W; signed=false) === UInt16; end
        for W in [17, 24, 32]; @test _bennett_arg_type(W; signed=false) === UInt32; end
        for W in [33, 48, 64]; @test _bennett_arg_type(W; signed=false) === UInt64; end
    end

    @testset "_bennett_arg_type: out of range errors" begin
        @test_throws ErrorException _bennett_arg_type(0)
        @test_throws ErrorException _bennett_arg_type(-1)
        @test_throws ErrorException _bennett_arg_type(65)
        @test_throws ErrorException _bennett_arg_type(128)
    end

    @testset "oracle forwards signed kwarg without breaking W=2 regression" begin
        # Regression: W=2 defaults to Int8 as before; signed=false runs too.
        # Bennett lowers the function's LLVM IR — using two top-level
        # functions (not a closure over `signed`) keeps the IR free of
        # captured-variable struct types that Bennett cannot compile.
        f_signed(x)   = x + Int8(1)
        f_unsigned(x) = x + UInt8(1)

        @context EagerContext() begin
            x = QInt{2}(2)
            y = oracle(f_signed, x; signed=true)
            @test Int(y) == 3
        end
        @context EagerContext() begin
            x = QInt{2}(2)
            y = oracle(f_unsigned, x; signed=false)
            @test Int(y) == 3
        end
    end

    @testset "quantum(f) cache distinguishes signed=true vs signed=false" begin
        qf = quantum(identity)
        @context EagerContext() begin
            x = QInt{2}(1)
            y = qf(x; signed=true)
            @test Int(y) == 1
        end
        @context EagerContext() begin
            x = QInt{2}(1)
            y = qf(x; signed=false)
            @test Int(y) == 1
        end
        @test haskey(qf.cache, (2, true,  ()))
        @test haskey(qf.cache, (2, false, ()))
        @test length(qf.cache) == 2   # two distinct compilations, not one silently reused
    end
end

# ── OpenQASM export ─────────────────────────────────────────────────────────

@testset "OpenQASM export of Bennett circuit" begin
    ch = trace(2) do a, b
        circuit = ReversibleCircuit(
            2, ReversibleGate[CNOTGate(1, 2)],
            WireIndex[1, 2], WireIndex[1, 2], WireIndex[], [1, 1], [1, 1])
        Sturm.apply_reversible!(current_context(), circuit,
            Dict{WireIndex,WireID}(1 => a.wire, 2 => b.wire))
        (a, b)
    end
    qasm = to_openqasm(ch)
    @test contains(qasm, "cx")
end

end # top-level "Bennett Integration"
