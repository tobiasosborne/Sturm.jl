using Test
using Sturm

# Sturm.jl-diy: rename discard! → ptrace! (partial trace, channel-theoretic name).
# discard! remains as a const alias for backcompat.

@testset "diy: ptrace! is canonical, discard! aliases to it" begin

    @testset "ptrace! on QBool" begin
        @context EagerContext() begin
            q = QBool(0.5)
            ptrace!(q)
            @test q.consumed === true
        end
    end

    @testset "ptrace! on QInt" begin
        @context EagerContext() begin
            r = QInt{4}(7)
            ptrace!(r)
            @test r.consumed === true
        end
    end

    @testset "ptrace! has methods for every quantum register type" begin
        # Rename covered QBool, QInt, QCoset, QRunway — verify all four via
        # the method table without invoking non-trivial constructors.
        ms = methods(ptrace!)
        sigs = [Base.unwrap_unionall(m.sig).parameters[2] for m in ms]
        @test any(s -> s <: QBool, sigs)
        @test any(s -> s <: QInt, sigs)
        @test any(s -> s <: QCoset, sigs)
        @test any(s -> s <: QRunway, sigs)
    end

    @testset "discard! is the same function as ptrace! (backcompat alias)" begin
        @test discard! === ptrace!
    end

    @testset "discard! still works on QBool (backcompat)" begin
        @context EagerContext() begin
            q = QBool(0.0)
            discard!(q)   # alias to ptrace!
            @test q.consumed === true
        end
    end

    @testset "ptrace! inside @context: explicit + auto-cleanup coexist" begin
        # ptrace! eagerly partial-traces one wire; @context auto-cleanup
        # handles the rest. Both paths must end in an empty wire_to_qubit.
        ctx = EagerContext()
        @context ctx begin
            q1 = QBool(0.5)
            q2 = QBool(0.0)
            ptrace!(q1)        # explicit partial trace of q1
            # q2 orphaned → cleanup handles it
        end
        @test isempty(ctx.wire_to_qubit)
    end

end
