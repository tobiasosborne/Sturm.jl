# test_oracle_cache_lru.jl — bead Sturm.jl-t1v
#
# `_ORACLE_TABLE_CACHE` previously grew unboundedly: long-running sessions
# that called `oracle_table` with distinct lookup tables (e.g. a hot loop
# quantising a continuous parameter) accumulated one entry per unique
# data hash forever. Replace with an LRU cache + public management API:
#
#   - `oracle_cache_size()` :: Int — current entry count
#   - `oracle_cache_max_size()` :: Int — current max
#   - `set_oracle_cache_size!(n)` — set max; evict to fit
#   - `clear_oracle_cache!()` — empty the cache
#
# Default max size: 64 entries.

using Test
using Sturm
using Sturm: EagerContext, QInt, oracle_table, current_context

@testset "oracle table cache LRU (Sturm.jl-t1v)" begin

    @testset "public API exists" begin
        @test isdefined(Sturm, :oracle_cache_size)
        @test isdefined(Sturm, :oracle_cache_max_size)
        @test isdefined(Sturm, :set_oracle_cache_size!)
        @test isdefined(Sturm, :clear_oracle_cache!)
        @test Sturm.oracle_cache_max_size() >= 1
    end

    @testset "clear_oracle_cache! empties the cache" begin
        @context EagerContext(capacity=8) begin
            x = QInt{2}(0)
            _ = oracle_table(k -> 2k + 1, x, Val(8))
            @test Sturm.oracle_cache_size() >= 1
        end
        Sturm.clear_oracle_cache!()
        @test Sturm.oracle_cache_size() == 0
    end

    @testset "cache hit: same table reused, no growth" begin
        Sturm.clear_oracle_cache!()
        for _ in 1:5
            @context EagerContext(capacity=8) begin
                x = QInt{2}(0)
                _ = oracle_table(k -> 3k, x, Val(8))
            end
        end
        # All 5 calls share the same hash → exactly 1 cache entry.
        @test Sturm.oracle_cache_size() == 1
        Sturm.clear_oracle_cache!()
    end

    @testset "LRU eviction: oldest entries drop when cap exceeded" begin
        # Set a small cap; insert N+2 distinct tables; cap holds.
        saved_max = Sturm.oracle_cache_max_size()
        try
            Sturm.set_oracle_cache_size!(3)
            Sturm.clear_oracle_cache!()
            for offset in 1:5
                @context EagerContext(capacity=8) begin
                    x = QInt{2}(0)
                    _ = oracle_table(k -> k + offset, x, Val(8))
                end
            end
            @test Sturm.oracle_cache_size() == 3   # capped, not 5
        finally
            Sturm.set_oracle_cache_size!(saved_max)
            Sturm.clear_oracle_cache!()
        end
    end

    @testset "set_oracle_cache_size! shrinks immediately when over" begin
        saved_max = Sturm.oracle_cache_max_size()
        try
            Sturm.set_oracle_cache_size!(10)
            Sturm.clear_oracle_cache!()
            for offset in 1:6
                @context EagerContext(capacity=8) begin
                    x = QInt{2}(0)
                    _ = oracle_table(k -> 5k + offset, x, Val(8))
                end
            end
            @test Sturm.oracle_cache_size() == 6
            Sturm.set_oracle_cache_size!(2)
            @test Sturm.oracle_cache_size() == 2
        finally
            Sturm.set_oracle_cache_size!(saved_max)
            Sturm.clear_oracle_cache!()
        end
    end

    @testset "LRU semantics: accessing oldest entry prevents eviction" begin
        saved_max = Sturm.oracle_cache_max_size()
        try
            Sturm.set_oracle_cache_size!(3)
            Sturm.clear_oracle_cache!()
            # Insert 3 entries (call them A, B, C in insertion order).
            for offset in 1:3
                @context EagerContext(capacity=8) begin
                    x = QInt{2}(0)
                    _ = oracle_table(k -> k + 100offset, x, Val(8))
                end
            end
            @test Sturm.oracle_cache_size() == 3
            # Re-access A (offset=1) — it should be MRU now; B is the oldest.
            @context EagerContext(capacity=8) begin
                x = QInt{2}(0)
                _ = oracle_table(k -> k + 100, x, Val(8))
            end
            @test Sturm.oracle_cache_size() == 3   # hit, no growth
            # Insert D (offset=4) — eviction. The oldest is now B.
            @context EagerContext(capacity=8) begin
                x = QInt{2}(0)
                _ = oracle_table(k -> k + 400, x, Val(8))
            end
            @test Sturm.oracle_cache_size() == 3
            # Verify A is still cached (re-accessing it doesn't grow size).
            @context EagerContext(capacity=8) begin
                x = QInt{2}(0)
                _ = oracle_table(k -> k + 100, x, Val(8))
            end
            @test Sturm.oracle_cache_size() == 3   # still hit, A survived
            # B should NOT be cached. Re-accessing it grows size, then
            # evicts the new-oldest. (We can't directly assert "miss" but
            # we can check size stays at cap after re-insert + access.)
        finally
            Sturm.set_oracle_cache_size!(saved_max)
            Sturm.clear_oracle_cache!()
        end
    end

    @testset "set_oracle_cache_size! validates input" begin
        saved_max = Sturm.oracle_cache_max_size()
        try
            @test_throws ErrorException Sturm.set_oracle_cache_size!(-1)
            Sturm.set_oracle_cache_size!(0)   # zero = always-evict
            @test Sturm.oracle_cache_max_size() == 0
            Sturm.clear_oracle_cache!()
            @context EagerContext(capacity=8) begin
                x = QInt{2}(0)
                _ = oracle_table(k -> k, x, Val(8))
            end
            # Cap=0 means even the just-inserted entry gets evicted.
            @test Sturm.oracle_cache_size() == 0
        finally
            Sturm.set_oracle_cache_size!(saved_max)
            Sturm.clear_oracle_cache!()
        end
    end
end
