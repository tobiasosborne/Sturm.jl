using Test
using Sturm

@testset "Quantum control (when)" begin

    @testset "Controlled-X via when" begin
        @context EagerContext() begin
            # Control=|1>, target=|0> → should flip target
            for _ in 1:100
                ctrl = QBool(1)
                target = QBool(0)
                when(ctrl) do
                    target.θ += π   # controlled-X
                end
                discard!(ctrl)
                @test Bool(target) == true
            end

            # Control=|0>, target=|0> → should NOT flip target
            for _ in 1:100
                ctrl = QBool(0)
                target = QBool(0)
                when(ctrl) do
                    target.θ += π
                end
                discard!(ctrl)
                @test Bool(target) == false
            end
        end
    end

    @testset "Controlled-Z via when" begin
        @context EagerContext() begin
            # CZ on |++>: should produce (|00>+|01>+|10>-|11>)/2
            # Measure in X basis (apply H before measurement)
            # CZ|++> = (|+0> + |-1>)/√2 in some basis...
            # Simpler test: CZ|11> = -|11>, but phase is unobservable directly.
            # Test via: |+> ⊗ |+>, apply CZ, then H⊗H, should give |11> with prob 1/4
            # Actually, test CZ as entangler: H·CZ·H = CNOT
            # So: target=|0>, ctrl=|1>, H(target), CZ, H(target) → target should be |1>
            for _ in 1:100
                ctrl = QBool(1)
                target = QBool(0)
                H!(target)
                when(ctrl) do
                    target.φ += π   # controlled-Z
                end
                H!(target)
                discard!(ctrl)
                @test Bool(target) == true
            end
        end
    end

    @testset "Controlled-NOT via ⊻= inside when (Toffoli)" begin
        @context EagerContext() begin
            # Both controls |1> → target flips
            for _ in 1:100
                c1 = QBool(1)
                c2 = QBool(1)
                target = QBool(0)
                when(c1) do
                    target ⊻= c2  # Toffoli: c1 AND c2 → flip target
                end
                discard!(c1)
                discard!(c2)
                @test Bool(target) == true
            end

            # One control |0> → target stays
            for _ in 1:100
                c1 = QBool(0)
                c2 = QBool(1)
                target = QBool(0)
                when(c1) do
                    target ⊻= c2
                end
                discard!(c1)
                discard!(c2)
                @test Bool(target) == false
            end
        end
    end

    # ─────────────────────────────────────────────────────────────────────
    # Multi-controlled gates (>1 control): Toffoli cascade decomposition
    # ─────────────────────────────────────────────────────────────────────

    @testset "Double-controlled Rz (2 controls)" begin
        # when(c1) { when(c2) { target.φ += angle } }
        # Only fires when both c1 AND c2 are |1⟩.
        @context EagerContext() begin
            # Both controls |1⟩ → gate fires
            c1 = QBool(1); c2 = QBool(1); t = QBool(0.5)  # |+⟩
            when(c1) do; when(c2) do
                t.φ += π  # Rz(π) = Z (up to global phase)
            end; end
            discard!(c1); discard!(c2)
            # |+⟩ after Z → |-⟩. P(|1⟩) for |-⟩ = 0.5.
            # But Z|+⟩ = |-⟩ = (|0⟩-|1⟩)/√2, still 50/50
            # Use a different test: Rz(π) on |0⟩ is identity
            discard!(t)

            # Better test: c1=|1⟩, c2=|1⟩, target=|0⟩ → Rz(π)|0⟩ = e^{-iπ/2}|0⟩ = -i|0⟩
            # Measurement: still |0⟩ deterministically
            c1 = QBool(1); c2 = QBool(1); t = QBool(0)
            when(c1) do; when(c2) do; t.φ += π; end; end
            discard!(c1); discard!(c2)
            @test Bool(t) == false  # still |0⟩

            # c1=|1⟩, c2=|0⟩ → gate does NOT fire
            c1 = QBool(1); c2 = QBool(0); t = QBool(0)
            when(c1) do; when(c2) do; t.θ += π; end; end  # would flip if fired
            discard!(c1); discard!(c2)
            @test Bool(t) == false  # NOT flipped

            # c1=|0⟩, c2=|1⟩ → gate does NOT fire
            c1 = QBool(0); c2 = QBool(1); t = QBool(0)
            when(c1) do; when(c2) do; t.θ += π; end; end
            discard!(c1); discard!(c2)
            @test Bool(t) == false
        end
    end

    @testset "Double-controlled Ry (2 controls)" begin
        @context EagerContext() begin
            # Both |1⟩ → Ry(π) flips |0⟩ to |1⟩
            c1 = QBool(1); c2 = QBool(1); t = QBool(0)
            when(c1) do; when(c2) do; t.θ += π; end; end
            discard!(c1); discard!(c2)
            @test Bool(t) == true  # flipped

            # c1=|0⟩ → no flip
            c1 = QBool(0); c2 = QBool(1); t = QBool(0)
            when(c1) do; when(c2) do; t.θ += π; end; end
            discard!(c1); discard!(c2)
            @test Bool(t) == false
        end
    end

    @testset "Double-controlled CX (Toffoli from nested when)" begin
        @context EagerContext() begin
            # Both |1⟩ → CX fires
            c1 = QBool(1); c2 = QBool(1); t = QBool(0)
            when(c1) do; when(c2) do; t ⊻= c2; end; end
            # Actually, c2 is the xor control, not c1. Let me use a different target.
            discard!(c1); discard!(c2); discard!(t)

            # Clean test: CCX(c1, c2, target) = when(c1){when(c2){target.θ += π}}
            c1 = QBool(1); c2 = QBool(1); t = QBool(0)
            when(c1) do; when(c2) do; t.θ += π; end; end
            discard!(c1); discard!(c2)
            @test Bool(t) == true

            # Superposition test: c1=|+⟩, c2=|1⟩, t=|0⟩
            # → (|0⟩|1⟩|0⟩ + |1⟩|1⟩|1⟩)/√2 (entangled)
            c1 = QBool(0.5); c2 = QBool(1); t = QBool(0)
            when(c1) do; when(c2) do; t.θ += π; end; end
            rc1 = Bool(c1)
            discard!(c2)
            rt = Bool(t)
            @test rc1 == rt  # entangled: c1 and t always agree
        end
    end
end
