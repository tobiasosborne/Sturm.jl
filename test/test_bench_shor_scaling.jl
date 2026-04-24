# Regression tests for Sturm.jl-guj: estimate_bytes must not throw
# InexactError at L ≥ 18 impl B, where the Int-first multiplication
# `estimate_gates * NODE_BYTES` overflowed Int64 and the subsequent
# round(Int, …) threw, crashing preflight instead of returning a clean
# "over budget" verdict.
using Test

include("bench_shor_scaling.jl")

@testset verbose=true "bench_shor_scaling.estimate_bytes" begin

    @testset "returns Float64 across impls" begin
        for impl in (:A, :B, :C, :D)
            @test estimate_bytes(impl, 4, 8) isa Float64
        end
    end

    @testset "small case agrees with hand computation" begin
        # Impl B, L=4, t=8: (4+14)·2^(8+4+1) = 18·8192 gates;
        # bytes = gates · 25 · 3.0 = 11_059_200.
        @test estimate_bytes(:B, 4, 8) ≈ 18 * 8192 * 25 * 3.0
    end

    @testset "regression: L=18 impl B does not throw (guj)" begin
        # Int-first path: (18+14)·2^55 · 25 wraps Int64 to −8.07e18, then
        # round(Int, −2.42e19) throws InexactError.
        local b
        @test (b = estimate_bytes(:B, 18, 36); true)
        @test isfinite(b)
        @test b > 8e19  # (18+14)·2^55 · 75 ≈ 8.65e19
    end

    @testset "preflight: L=18 impl B returns ok=false cleanly" begin
        budget = 64 * 1024^3  # 64 GiB
        local pf
        @test (pf = preflight(:B, 18, 36; budget_bytes=budget); true)
        @test pf.ok == false
        @test pf.mem > pf.budget
    end

    @testset "preflight: small case still reports ok=true" begin
        budget = 64 * 1024^3
        pf = preflight(:B, 4, 8; budget_bytes=budget)
        @test pf.ok == true
        @test pf.mem <= pf.budget
    end
end
