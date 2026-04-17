using Test
using Sturm

# P9 auto-dispatch (bead Sturm.jl-k3m) — PARTIAL.
#
# The literal P9 axiom `(f::Function)(q::Quantum) → oracle(f, q)` is BLOCKED
# by Julia: `cannot add methods to builtin function Function` (confirmed
# Julia 1.12.5). This test file covers what has landed under k3m so far:
#
#   (1) `abstract type Quantum end` with QBool, QInt{W} as subtypes.
#   (2) `classical_type(::Type{<:Quantum})` and `classical_compile_kwargs`
#       traits that Bennett lifts use to find the classical shadow type.
#   (3) P8 direct overloads and user-typed quantum methods still win — the
#       missing catch-all does not disturb them.
#
# The remaining P9 acceptance criteria (bare `f(q)` auto-dispatch) depend on
# an axiom re-definition — see WORKLOG and bead k3m.

@testset verbose=true "P9 auto-dispatch (k3m) — partial" begin

    @testset "Quantum abstract type" begin
        @test isdefined(Sturm, :Quantum)
        @test QBool <: Sturm.Quantum
        @test QInt{2} <: Sturm.Quantum
        @test QInt{8} <: Sturm.Quantum
    end

    @testset "classical_type trait" begin
        @test Sturm.classical_type(QBool)    === Int8
        @test Sturm.classical_type(QInt{4})  === Int8
        @test Sturm.classical_type(QInt{8})  === Int8
    end

    @testset "classical_compile_kwargs trait" begin
        @test Sturm.classical_compile_kwargs(QBool)   == (bit_width = 1,)
        @test Sturm.classical_compile_kwargs(QInt{4}) == (bit_width = 4,)
        @test Sturm.classical_compile_kwargs(QInt{8}) == (bit_width = 8,)
    end

    @testset "existing dispatch paths still work" begin
        # P8 mixed-op: Base.:+(::QInt, ::Integer) wins regardless.
        @context EagerContext() begin
            q = QInt{4}(5)
            @test Int(q + 3) == 8
        end
        # Explicit oracle(f, q) path still fires.
        @context EagerContext() begin
            x = QInt{2}(1)
            y = oracle(x -> x + Int8(1), x)
            @test Int(y) == 2
        end
        # User-typed quantum method wins by specificity.
        let_marker(x::Int8) = x + Int8(1)
        let_marker(q::QInt{W}) where {W} = (discard!(q); QInt{W}(current_context(), 7 % (1 << W)))
        @context EagerContext() begin
            x = QInt{4}(0)
            y = let_marker(x)
            @test Int(y) == 7
        end
    end

end
