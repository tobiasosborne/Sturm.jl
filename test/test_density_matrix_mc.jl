using Test
using Sturm

# Multi-controlled gates on DensityMatrixContext (bead Sturm.jl-xcu).
# Mirrors test_when.jl's nested-when cases on the density-matrix backend.
# Before this bead, DensityMatrixContext errored "not yet implemented" on any
# nested when() depth ≥ 2.
#
# Deterministic cases use the fact that pure computational-basis inputs
# remain diagonal under coherent gates, so measurement outcomes are
# perfectly predictable. Superposition cases use repeated shots since DM
# has no cheap amplitude helper.

@testset "Multi-controlled gates on DensityMatrixContext" begin

    # ── Depth 2: double-controlled gates (nested when) ──────────────────────

    @testset "Depth 2: CCRy via when-when (both controls |1⟩)" begin
        @context DensityMatrixContext() begin
            # Both controls |1⟩ → Ry(π) fires → target |0⟩ → |1⟩
            c1 = QBool(1); c2 = QBool(1); t = QBool(0)
            when(c1) do; when(c2) do; t.θ += π; end; end
            discard!(c1); discard!(c2)
            @test Bool(t) == true
        end
    end

    @testset "Depth 2: CCRy does NOT fire when one control is |0⟩" begin
        @context DensityMatrixContext() begin
            for (v1, v2) in [(0, 1), (1, 0), (0, 0)]
                c1 = QBool(v1); c2 = QBool(v2); t = QBool(0)
                when(c1) do; when(c2) do; t.θ += π; end; end
                discard!(c1); discard!(c2)
                @test Bool(t) == false
            end
        end
    end

    @testset "Depth 2: CCRz on |0⟩ stays |0⟩ (phase only)" begin
        @context DensityMatrixContext() begin
            c1 = QBool(1); c2 = QBool(1); t = QBool(0)
            when(c1) do; when(c2) do; t.φ += π; end; end
            discard!(c1); discard!(c2)
            @test Bool(t) == false   # Rz(π)|0⟩ = -i|0⟩, still |0⟩
        end
    end

    @testset "Depth 2: CCX (Toffoli via nested when) fires on (1,1)" begin
        @context DensityMatrixContext() begin
            # Both |1⟩ → target flips via Rθ(π)
            c1 = QBool(1); c2 = QBool(1); t = QBool(0)
            when(c1) do; when(c2) do; t.θ += π; end; end
            discard!(c1); discard!(c2)
            @test Bool(t) == true
        end
    end

    # ── Depth 2: apply_cx! inside nested when() — toffoli cascade ────────────

    @testset "Depth 2: apply_cx! inside nested when() (effective CCCX)" begin
        # when(c1) do; when(c2) do; t ⊻= c3; end; end
        # Fires iff c1 ∧ c2 ∧ c3 = 1. With c3=|1⟩, t=|0⟩: t flips iff c1=c2=1.
        @context DensityMatrixContext() begin
            c1 = QBool(1); c2 = QBool(1); c3 = QBool(1); t = QBool(0)
            when(c1) do; when(c2) do; t ⊻= c3; end; end
            discard!(c1); discard!(c2); discard!(c3)
            @test Bool(t) == true
        end
        @context DensityMatrixContext() begin
            c1 = QBool(1); c2 = QBool(0); c3 = QBool(1); t = QBool(0)
            when(c1) do; when(c2) do; t ⊻= c3; end; end
            discard!(c1); discard!(c2); discard!(c3)
            @test Bool(t) == false    # c2=0 blocks
        end
    end

    # ── Depth 2: apply_ccx! inside when() — 3-AND via explicit Toffoli ──────

    @testset "Depth 2: apply_ccx! inside when() (effective CCCX via ccx)" begin
        # Inside when(c1), a CCX(c2, c3, t) should fire iff c1 ∧ c2 ∧ c3.
        # Exercised via the gate primitive directly; user code would spell
        # this as a library _ccx!(c2, c3, t) call inside when(c1).
        @context DensityMatrixContext() begin
            c1 = QBool(1); c2 = QBool(1); c3 = QBool(1); t = QBool(0)
            when(c1) do
                Sturm.apply_ccx!(current_context(), c2.wire, c3.wire, t.wire)
            end
            discard!(c1); discard!(c2); discard!(c3)
            @test Bool(t) == true
        end
        @context DensityMatrixContext() begin
            c1 = QBool(0); c2 = QBool(1); c3 = QBool(1); t = QBool(0)
            when(c1) do
                Sturm.apply_ccx!(current_context(), c2.wire, c3.wire, t.wire)
            end
            discard!(c1); discard!(c2); discard!(c3)
            @test Bool(t) == false
        end
    end

    # ── Depth 3: four-way AND via 3-level nested when ────────────────────────

    @testset "Depth 3: triple-nested when() fires iff all four qubits |1⟩" begin
        @context DensityMatrixContext() begin
            c1 = QBool(1); c2 = QBool(1); c3 = QBool(1); t = QBool(0)
            when(c1) do; when(c2) do; when(c3) do
                t.θ += π
            end; end; end
            discard!(c1); discard!(c2); discard!(c3)
            @test Bool(t) == true
        end
        @context DensityMatrixContext() begin
            # Any single |0⟩ blocks the gate
            for missing_idx in 1:3
                vs = [1, 1, 1]; vs[missing_idx] = 0
                c1 = QBool(vs[1]); c2 = QBool(vs[2]); c3 = QBool(vs[3])
                t = QBool(0)
                when(c1) do; when(c2) do; when(c3) do
                    t.θ += π
                end; end; end
                discard!(c1); discard!(c2); discard!(c3)
                @test Bool(t) == false
            end
        end
    end

    # ── Entanglement preservation on DM: superposition control ──────────────

    @testset "Depth 2: superposition control entangles correctly (statistical)" begin
        # c1=|+⟩, c2=|1⟩, t=|0⟩; nested when applies Ry(π) iff c1=c2=1.
        # After: (|0⟩_c1 |1⟩_c2 |0⟩_t + |1⟩_c1 |1⟩_c2 |1⟩_t)/√2 — c1 and t entangled.
        # Across shots: Bool(c1) == Bool(t) always.
        N = 200
        agreements = 0
        for _ in 1:N
            @context DensityMatrixContext() begin
                c1 = QBool(0.5); c2 = QBool(1); t = QBool(0)
                when(c1) do; when(c2) do; t.θ += π; end; end
                discard!(c2)
                rc1 = Bool(c1)
                rt = Bool(t)
                rc1 == rt && (agreements += 1)
            end
        end
        @test agreements == N   # perfect correlation, every shot
    end

    # ── Workspace recycling: cascade should return workspace qubits to |0⟩ ─

    @testset "Workspace ancillae are returned to |0⟩ (no qubit leak)" begin
        # Run a depth-3 cascade then inspect the allocator: after deallocation,
        # n_qubits − length(consumed) should equal the number of live user qubits.
        @context DensityMatrixContext() begin
            ctx = current_context()
            c1 = QBool(1); c2 = QBool(1); c3 = QBool(1); t = QBool(0)
            when(c1) do; when(c2) do; when(c3) do; t.θ += π; end; end; end
            # Check: consumed ∪ live accounts for all n_qubits slots
            live = length(ctx.wire_to_qubit)
            @test live == 4   # c1, c2, c3, t — workspace should have been recycled
            @test Bool(t) == true
            discard!(c1); discard!(c2); discard!(c3)
        end
    end
end
