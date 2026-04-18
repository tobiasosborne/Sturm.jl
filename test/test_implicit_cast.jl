using Test
using Logging
using Sturm

# P2 implicit quantum→classical cast warning (bead Sturm.jl-f23).
#
# Contract:
#   - Explicit  Bool(q)  /  Int(q)      → silent (blessed path).
#   - Implicit  x::Bool = q  /  y::Int = qi  → one `@warn` per source site.
#   - Two distinct user sites → two distinct warnings (deduped by file:line).
#   - Loop iterations at a single site → one warning (`maxlog=1` + stable _id).
#   - `with_silent_casts(f)` suppresses warnings in the current task; nests.
#
# Note: Julia's global logger dedupes `_id` across the process. Test using
# `@test_logs` which captures records before the global dedup filter.

@testset "P2 implicit-cast warning" begin

    @testset "explicit Bool(q) is silent" begin
        @test_logs min_level=Warn begin
            @context EagerContext() begin
                q = QBool(1.0)
                x = Bool(q)
                @test x == true
            end
        end
    end

    @testset "explicit Int(q) is silent" begin
        @test_logs min_level=Warn begin
            @context EagerContext() begin
                qi = QInt{3}(5)
                y = Int(qi)
                @test y == 5
            end
        end
    end

    @testset "implicit x::Bool = q warns once" begin
        @test_logs (:warn, r"Implicit quantum→classical cast QBool → Bool") begin
            @context EagerContext() begin
                q = QBool(1.0)
                local x::Bool = q
                @test x == true
            end
        end
    end

    @testset "implicit y::Int = qi warns once" begin
        @test_logs (:warn, r"Implicit quantum→classical cast QInt\{3\} → Int") begin
            @context EagerContext() begin
                qi = QInt{3}(5)
                local y::Int = qi
                @test y == 5
            end
        end
    end

    @testset "warning message names explicit cast as fix" begin
        @test_logs (:warn, r"Wrap the RHS in an explicit cast: `Bool\(q\)`") begin
            @context EagerContext() begin
                q = QBool(1.0)
                local x::Bool = q
            end
        end
        @test_logs (:warn, r"Wrap the RHS in an explicit cast: `Int\(q\)`") begin
            @context EagerContext() begin
                qi = QInt{2}(1)
                local y::Int = qi
            end
        end
    end

    @testset "with_silent_casts suppresses" begin
        @test_logs min_level=Warn begin
            with_silent_casts() do
                @context EagerContext() begin
                    q = QBool(1.0)
                    local x::Bool = q
                    @test x == true
                end
            end
        end
    end

    @testset "with_silent_casts nests (inner restores outer state)" begin
        # Outer default (warnings on). Inner silent block runs silently,
        # then returns to outer default.
        @test_logs (:warn, r"Implicit quantum→classical cast") begin
            with_silent_casts() do
                @context EagerContext() begin
                    q = QBool(1.0); local dummy::Bool = q
                end
            end
            @context EagerContext() begin
                q = QBool(1.0); local dummy::Bool = q
            end
        end
    end

    @testset "with_silent_casts returns its block's value" begin
        v = with_silent_casts() do
            @context EagerContext() begin
                q = QBool(1.0)
                local x::Bool = q
                x ? 42 : 0
            end
        end
        @test v == 42
    end
end
