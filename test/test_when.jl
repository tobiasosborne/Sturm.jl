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
end
