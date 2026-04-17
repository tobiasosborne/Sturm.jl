@testset "Quantum promotion (P8)" begin

    # ── QInt mixed-type addition ────────────────────────────────────────────
    @testset "QInt{8} + Integer" begin
        @context EagerContext() begin
            @test Int(QInt{8}(42) + 17) == 59
        end
    end

    @testset "Integer + QInt{8}" begin
        @context EagerContext() begin
            @test Int(17 + QInt{8}(42)) == 59
        end
    end

    @testset "QInt{8} + Integer overflow (mod 256)" begin
        @context EagerContext() begin
            # 300 mod 256 = 44, so 42 + 44 = 86
            @test Int(QInt{8}(42) + 300) == 86
        end
    end

    @testset "QInt{4} + Integer exhaustive" begin
        @context EagerContext() begin
            for x in 0:15, y in 0:31
                @test Int(QInt{4}(x) + y) == (x + mod(y, 16)) % 16
            end
        end
    end

    @testset "Integer + QInt{4} exhaustive" begin
        @context EagerContext() begin
            for x in 0:31, y in 0:15
                @test Int(x + QInt{4}(y)) == (mod(x, 16) + y) % 16
            end
        end
    end

    # ── QInt mixed-type subtraction ─────────────────────────────────────────
    @testset "QInt{8} - Integer" begin
        @context EagerContext() begin
            @test Int(QInt{8}(42) - 17) == 25
        end
    end

    @testset "Integer - QInt{8}" begin
        @context EagerContext() begin
            @test Int(100 - QInt{8}(42)) == 58
        end
    end

    @testset "QInt{8} - Integer underflow (mod 256)" begin
        @context EagerContext() begin
            @test Int(QInt{8}(0) - 1) == 255
        end
    end

    # ── QInt mixed-type comparison: REMOVED in Sturm.jl-w4g ────────────────
    # The v0.1 classical-collapse `<` and `==` violated P1/P9 and were deleted.
    # Quantum comparators must go through oracle(f, q) with a classical predicate.

    # ── QBool mixed-type XOR ────────────────────────────────────────────────
    @testset "QBool ⊻ true = X gate" begin
        @context EagerContext() begin
            q = QBool(0.0); q ⊻= true
            @test Bool(q) == true

            q2 = QBool(1.0); q2 ⊻= true
            @test Bool(q2) == false
        end
    end

    @testset "QBool ⊻ false = no-op" begin
        @context EagerContext() begin
            q = QBool(0.0); q ⊻= false
            @test Bool(q) == false

            q2 = QBool(1.0); q2 ⊻= false
            @test Bool(q2) == true
        end
    end

    @testset "true ⊻ QBool → new QBool" begin
        @context EagerContext() begin
            # true ⊻ |0⟩: prepare |1⟩, CNOT from |0⟩ → 1 XOR 0 = 1
            q = QBool(0.0)
            r = xor(true, q)
            discard!(q)
            @test Bool(r) == true

            # true ⊻ |1⟩: prepare |1⟩, CNOT from |1⟩ → 1 XOR 1 = 0
            q2 = QBool(1.0)
            r2 = xor(true, q2)
            discard!(q2)
            @test Bool(r2) == false
        end
    end

    @testset "false ⊻ QBool → CNOT copy" begin
        @context EagerContext() begin
            # false ⊻ |0⟩ = |0⟩
            q = QBool(0.0)
            r = xor(false, q)
            discard!(q)
            @test Bool(r) == false

            # false ⊻ |1⟩ = |1⟩
            q2 = QBool(1.0)
            r2 = xor(false, q2)
            discard!(q2)
            @test Bool(r2) == true
        end
    end

    @testset "Bool ⊻ QBool(0.5) — entanglement" begin
        @context EagerContext() begin
            # false ⊻ |+⟩: prepare |0⟩, CNOT from |+⟩ → Bell pair
            # Measuring both should always agree
            N = 1000
            for _ in 1:N
                q = QBool(0.5)
                r = xor(false, q)
                rq = Bool(q)
                rr = Bool(r)
                @test rq == rr  # Bell-pair correlation
            end
        end
    end

    # ── Classical operand is not consumed ────────────────────────────────────
    @testset "Classical operand reusable" begin
        @context EagerContext() begin
            x = 42  # classical, freely copyable
            a = QInt{8}(10)
            r1 = Int(a + x)
            b = QInt{8}(20)
            r2 = Int(b + x)
            @test r1 == 52
            @test r2 == 62
            @test x == 42  # unchanged
        end
    end

    # ── Negative tests: no promotion for gates or when() ────────────────────
    @testset "H!(::Bool) → MethodError" begin
        @test_throws MethodError H!(true)
    end

    @testset "when(::Bool) → MethodError" begin
        @context EagerContext() begin
            target = QBool(0.0)
            @test_throws MethodError when(true) do
                target.θ += π
            end
            discard!(target)
        end
    end
end
