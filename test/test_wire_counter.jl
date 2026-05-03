# test_wire_counter.jl — bead Sturm.jl-6s5t
#
# `_wire_counter` was a plain `Ref{UInt32}` with non-atomic `[] += 1` (load,
# add, store). Two threads racing `fresh_wire!()` could read the same value
# and produce identical WireIDs — silent state corruption, no assertion
# fires. Fix: `Threads.Atomic{UInt32}` + `Threads.atomic_add!` (returns the
# pre-increment value, so we add 1 to get the new ID).
#
# The interesting test only exercises the atomicity guarantee under
# `nthreads() > 1`. With a single thread `Threads.@spawn` runs each task
# sequentially and the race never materialises — the assertion still holds
# but it would have held under the old non-atomic code too. We additionally
# spawn a sibling julia subprocess with `--threads=4` so CI-on-1-thread
# still gets a real race-test.

using Test
using Sturm: fresh_wire!, _wire_counter

@testset "wire counter atomicity (Sturm.jl-6s5t)" begin

    @testset "fresh_wire! returns globally unique IDs (sequential)" begin
        # Sanity baseline. Always passes regardless of nthreads.
        N = 1000
        before = _wire_counter[]
        ids = [fresh_wire!() for _ in 1:N]
        @test length(unique(ids)) == N
        @test _wire_counter[] == before + UInt32(N)
    end

    @testset "_wire_counter is a Threads.Atomic" begin
        # Type-level guarantee — without this, a future refactor could
        # silently revert to a plain Ref and the duplicate-ID race returns.
        @test _wire_counter isa Threads.Atomic{UInt32}
    end

    @testset "in-process Threads.@spawn race (degenerates if nthreads==1)" begin
        # Real coverage requires nthreads ≥ 2. Under nthreads==1 this
        # collapses to sequential @spawn, which still passes — useful as a
        # smoke test that Atomic semantics work via the existing API.
        N = 4000
        ids = Vector{UInt32}(undef, N)
        tasks = Vector{Task}(undef, N)
        for i in 1:N
            tasks[i] = Threads.@spawn (ids[i] = fresh_wire!().id)
        end
        for t in tasks; wait(t); end
        @test length(unique(ids)) == N
        if Threads.nthreads() == 1
            @info "test_wire_counter: in-process race only validates atomicity under JULIA_NUM_THREADS≥2 (current: 1). Subprocess test below covers the actual race."
        end
    end

    @testset "subprocess race with --threads=4 → no duplicate IDs" begin
        # Spawn a child julia with 4 threads, hammer fresh_wire! from all of
        # them, count distinct IDs. Parent waits — strict-serial-julia rule
        # satisfied (no concurrent julia processes on this device, just
        # parent → child sequentially).
        proj = dirname(@__DIR__)
        script = """
            using Sturm: fresh_wire!
            N_PER = 5000
            T = Threads.nthreads()
            ids = Vector{UInt32}(undef, N_PER * T)
            Threads.@threads for tid in 1:T
                base = (tid - 1) * N_PER
                for i in 1:N_PER
                    ids[base + i] = fresh_wire!().id
                end
            end
            println("nthreads=", T)
            println("total=", length(ids))
            println("unique=", length(unique(ids)))
        """
        cmd = `$(Base.julia_cmd()) --project=$proj --threads=4 -e $script`
        out = read(cmd, String)
        m_unique = match(r"unique=(\d+)"s, out)
        m_total  = match(r"total=(\d+)"s,  out)
        m_nt     = match(r"nthreads=(\d+)"s, out)
        @test m_unique !== nothing && m_total !== nothing && m_nt !== nothing
        if m_unique !== nothing && m_total !== nothing
            unique_count = parse(Int, m_unique.captures[1])
            total_count  = parse(Int, m_total.captures[1])
            nt_count     = parse(Int, m_nt.captures[1])
            @test nt_count == 4
            @test unique_count == total_count   # zero collisions under 4-way race
        end
    end
end
