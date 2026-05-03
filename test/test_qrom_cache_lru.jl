# test_qrom_cache_lru.jl — bead Sturm.jl-rqus
#
# `_QROM_LOOKUP_XOR_CACHE` previously grew without bound: long Shor
# parameter sweeps that hit `qrom_lookup_xor!` with distinct
# (hash(table_data), Ccmul, W) triples accumulated one ReversibleCircuit
# per unique key forever, OOMing Julia.
#
# Mirrors the LRU treatment from bead Sturm.jl-t1v (see
# test_oracle_cache_lru.jl). Public API:
#   - qrom_lookup_xor_cache_size() :: Int
#   - qrom_lookup_xor_cache_max_size() :: Int
#   - set_qrom_lookup_xor_cache_size!(n)
#   - clear_qrom_lookup_xor_cache!()
#
# These tests exercise the LRU machinery directly (insertion via the
# internal `_qrom_lookup_xor_cache_get!`, eviction logic, MRU promotion
# on hit, cap shrink). They use stub `ReversibleCircuit` values rather
# than going through the live `qrom_lookup_xor!` path — that path
# composes Bennett's `emit_qrom!` + `LoweringResult(...)`, which is
# orthogonal to the cache logic and currently unrelated-broken in the
# t1v sibling test (Bennett LoweringResult signature drift, separate
# bead). Decoupling here means the cache-correctness test exercises
# exactly the code added for rqus — nothing more, nothing less.

using Test
using Sturm
using Bennett: ReversibleCircuit, ReversibleGate, WireIndex

# Minimal stub: empty circuit, all wire vectors empty, n_wires=0. The
# Bennett constructor's wire-partition validation accepts this (every
# set is empty; union covers 1:0 vacuously).
_stub_circuit() =
    ReversibleCircuit(0, ReversibleGate[], WireIndex[], WireIndex[],
                      WireIndex[], Int[], Int[])

# Direct access to the cache machinery (private, but stable for tests).
_get_or_compute(key) =
    Sturm._qrom_lookup_xor_cache_get!(_stub_circuit, key)

@testset "qrom_lookup_xor cache LRU (Sturm.jl-rqus)" begin

    @testset "public API exists" begin
        @test isdefined(Sturm, :qrom_lookup_xor_cache_size)
        @test isdefined(Sturm, :qrom_lookup_xor_cache_max_size)
        @test isdefined(Sturm, :set_qrom_lookup_xor_cache_size!)
        @test isdefined(Sturm, :clear_qrom_lookup_xor_cache!)
        @test Sturm.qrom_lookup_xor_cache_max_size() >= 1
    end

    @testset "clear_qrom_lookup_xor_cache! empties the cache" begin
        Sturm.clear_qrom_lookup_xor_cache!()
        _get_or_compute((UInt64(1), 2, 3))
        @test Sturm.qrom_lookup_xor_cache_size() == 1
        Sturm.clear_qrom_lookup_xor_cache!()
        @test Sturm.qrom_lookup_xor_cache_size() == 0
    end

    @testset "cache hit: same key reused, no growth" begin
        Sturm.clear_qrom_lookup_xor_cache!()
        for _ in 1:5
            _get_or_compute((UInt64(0xCAFE), 2, 3))
        end
        @test Sturm.qrom_lookup_xor_cache_size() == 1
        Sturm.clear_qrom_lookup_xor_cache!()
    end

    @testset "LRU eviction: oldest entries drop when cap exceeded" begin
        saved_max = Sturm.qrom_lookup_xor_cache_max_size()
        try
            Sturm.set_qrom_lookup_xor_cache_size!(3)
            Sturm.clear_qrom_lookup_xor_cache!()
            for h in 1:5
                _get_or_compute((UInt64(h), 2, 3))
            end
            # 5 distinct keys inserted; cap=3 → only the 3 most recent kept.
            @test Sturm.qrom_lookup_xor_cache_size() == 3
        finally
            Sturm.set_qrom_lookup_xor_cache_size!(saved_max)
            Sturm.clear_qrom_lookup_xor_cache!()
        end
    end

    @testset "set_qrom_lookup_xor_cache_size! shrinks immediately when over" begin
        saved_max = Sturm.qrom_lookup_xor_cache_max_size()
        try
            Sturm.set_qrom_lookup_xor_cache_size!(10)
            Sturm.clear_qrom_lookup_xor_cache!()
            for h in 1:6
                _get_or_compute((UInt64(h), 2, 3))
            end
            @test Sturm.qrom_lookup_xor_cache_size() == 6
            Sturm.set_qrom_lookup_xor_cache_size!(2)
            @test Sturm.qrom_lookup_xor_cache_size() == 2
        finally
            Sturm.set_qrom_lookup_xor_cache_size!(saved_max)
            Sturm.clear_qrom_lookup_xor_cache!()
        end
    end

    @testset "LRU semantics: re-accessing oldest entry prevents eviction" begin
        saved_max = Sturm.qrom_lookup_xor_cache_max_size()
        try
            Sturm.set_qrom_lookup_xor_cache_size!(3)
            Sturm.clear_qrom_lookup_xor_cache!()
            ka = (UInt64(101), 2, 3)
            kb = (UInt64(102), 2, 3)
            kc = (UInt64(103), 2, 3)
            kd = (UInt64(104), 2, 3)
            # Insert A, B, C in order — A is oldest.
            _get_or_compute(ka); _get_or_compute(kb); _get_or_compute(kc)
            @test Sturm.qrom_lookup_xor_cache_size() == 3
            # Re-touch A → A is now MRU, B is the new oldest.
            _get_or_compute(ka)
            @test Sturm.qrom_lookup_xor_cache_size() == 3
            # Insert D → evicts B, not A.
            _get_or_compute(kd)
            @test Sturm.qrom_lookup_xor_cache_size() == 3
            @test haskey(Sturm._QROM_LOOKUP_XOR_CACHE, ka)
            @test !haskey(Sturm._QROM_LOOKUP_XOR_CACHE, kb)
            @test haskey(Sturm._QROM_LOOKUP_XOR_CACHE, kc)
            @test haskey(Sturm._QROM_LOOKUP_XOR_CACHE, kd)
        finally
            Sturm.set_qrom_lookup_xor_cache_size!(saved_max)
            Sturm.clear_qrom_lookup_xor_cache!()
        end
    end

    @testset "set_qrom_lookup_xor_cache_size! validates input" begin
        saved_max = Sturm.qrom_lookup_xor_cache_max_size()
        try
            @test_throws ErrorException Sturm.set_qrom_lookup_xor_cache_size!(-1)
            Sturm.set_qrom_lookup_xor_cache_size!(0)
            @test Sturm.qrom_lookup_xor_cache_max_size() == 0
            Sturm.clear_qrom_lookup_xor_cache!()
            _get_or_compute((UInt64(7), 2, 3))
            # cap=0 → just-inserted entry evicted before we return.
            @test Sturm.qrom_lookup_xor_cache_size() == 0
        finally
            Sturm.set_qrom_lookup_xor_cache_size!(saved_max)
            Sturm.clear_qrom_lookup_xor_cache!()
        end
    end
end
