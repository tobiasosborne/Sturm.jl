using Test
using Sturm

# HardwareContext exercised via the full public DSL: QBool, Bool(), when(), H!,
# CX (⊻=), discard!, @context. Every test runs through an InProcessTransport
# wrapped around an IdealisedSimulator (no network).

@testset "HardwareContext (HW3)" begin

    function _hw(; capacity=4, gate_time_ms=1.0)
        sim = Sturm.IdealisedSimulator(; capacity=capacity, gate_time_ms=gate_time_ms)
        t = Sturm.InProcessTransport(sim)
        return Sturm.HardwareContext(t; capacity=capacity, gate_time_ms=gate_time_ms)
    end

    @testset "Construction opens a session" begin
        ctx = _hw(; capacity=4)
        @test ctx isa AbstractContext
        @test !isempty(ctx.session_id)
        @test ctx.capacity == 4
        @test isempty(ctx.pending)
        close(ctx)
    end

    @testset "allocate! / deallocate! queue ops without flushing" begin
        ctx = _hw(; capacity=4)
        w1 = Sturm.allocate!(ctx)
        w2 = Sturm.allocate!(ctx)
        @test length(ctx.pending) == 2  # two alloc ops queued
        @test all(o.verb === :alloc for o in ctx.pending)
        Sturm.deallocate!(ctx, w1)
        @test length(ctx.pending) == 3  # alloc, alloc, discard
        @test ctx.pending[3].verb === :discard
        Sturm.deallocate!(ctx, w2)
        close(ctx)
    end

    @testset "QBool prep and Bool measurement (single qubit)" begin
        @context _hw(; capacity=2) begin
            q = QBool(0.0)
            @test Bool(q) === false
        end

        @context _hw(; capacity=2) begin
            q = QBool(1.0)  # Ry(π) → |1⟩
            @test Bool(q) === true
        end
    end

    @testset "Bell pair via HardwareContext (200 shots)" begin
        @context _hw(; capacity=2) begin
            for _ in 1:200
                a = QBool(0.5)   # |+⟩
                b = QBool(0)     # |0⟩
                b ⊻= a           # CX(a, b) → Bell pair
                ra = Bool(a)
                rb = Bool(b)
                @test ra == rb   # perfectly correlated
            end
        end
    end

    @testset "GHZ via HardwareContext (200 shots)" begin
        @context _hw(; capacity=3) begin
            for _ in 1:200
                a = QBool(0.5)
                b = QBool(0)
                c = QBool(0)
                b ⊻= a
                c ⊻= a
                @test Bool(a) == Bool(b) == Bool(c)
            end
        end
    end

    @testset "H! gate composed from primitives" begin
        @context _hw(; capacity=1) begin
            count_true = 0
            N = 200
            for _ in 1:N
                q = QBool(0)
                H!(q)            # H = Rz(π/2) Ry(π/2) Rz(π/2) (up to global phase)
                Bool(q) && (count_true += 1)
            end
            @test 70 < count_true < 130
        end
    end

    @testset "when() with single control via HardwareContext" begin
        @context _hw(; capacity=2) begin
            for _ in 1:50
                ctrl = QBool(1.0)   # |1⟩, so when() body always fires
                tgt = QBool(0.0)
                when(ctrl) do
                    X!(tgt)
                end
                @test Bool(ctrl) === true
                @test Bool(tgt) === true
            end

            for _ in 1:50
                ctrl = QBool(0.0)   # |0⟩, so when() body never fires
                tgt = QBool(0.0)
                when(ctrl) do
                    X!(tgt)
                end
                @test Bool(ctrl) === false
                @test Bool(tgt) === false
            end
        end
    end

    @testset "when() with TWO controls (Toffoli via cascade)" begin
        @context _hw(; capacity=4) begin
            # Both controls |1⟩ → target should flip
            c1 = QBool(1.0); c2 = QBool(1.0); t = QBool(0.0)
            when(c1) do
                when(c2) do
                    X!(t)
                end
            end
            @test Bool(c1) === true
            @test Bool(c2) === true
            @test Bool(t) === true

            # One control |0⟩ → target stays
            c1 = QBool(0.0); c2 = QBool(1.0); t = QBool(0.0)
            when(c1) do
                when(c2) do
                    X!(t)
                end
            end
            @test Bool(c1) === false
            @test Bool(c2) === true
            @test Bool(t) === false
        end
    end

    @testset "Slot recycling: many shots through 2-qubit device" begin
        @context _hw(; capacity=2) begin
            for _ in 1:100
                q = QBool(1.0)
                @test Bool(q) === true
            end
        end
    end

    @testset "Capacity exhaustion is loud" begin
        @context _hw(; capacity=2) begin
            _ = QBool(0)
            _ = QBool(0)
            @test_throws ErrorException QBool(0)  # device only has 2 qubits
        end
    end

    @testset "Operations after close throw" begin
        ctx = _hw(; capacity=2)
        close(ctx)
        @test_throws ErrorException Sturm.allocate!(ctx)
    end

    @testset "close is idempotent" begin
        ctx = _hw(; capacity=2)
        close(ctx)
        close(ctx)  # no error
        @test ctx.closed === true
    end

    @testset "Pending ops survive across non-measurement gates (no premature flush)" begin
        ctx = _hw(; capacity=4)
        @context ctx begin
            q1 = QBool(0)
            q2 = QBool(0)
            q1.θ += π/3
            q2.φ += π/4
            q2 ⊻= q1
            # 5 ops queued so far (alloc, alloc, ry, rz, cx) — none flushed
            @test length(ctx.pending) == 5
            @test ctx.total_duration_ms == 0.0
            # First measurement triggers flush
            r = Bool(q1)
            @test isempty(ctx.pending)
            @test ctx.total_duration_ms > 0.0
        end
    end

    @testset "total_duration_ms accumulates across flushes" begin
        ctx = _hw(; capacity=2, gate_time_ms=2.0)
        @context ctx begin
            q1 = QBool(1.0)   # 1 ry gate, then measure → 1st flush, ~2ms
            _ = Bool(q1)
            d1 = ctx.total_duration_ms
            q2 = QBool(1.0)   # another 1 ry gate, then measure → 2nd flush
            _ = Bool(q2)
            d2 = ctx.total_duration_ms
            @test d1 ≈ 2.0
            @test d2 ≈ 4.0
        end
    end
end
