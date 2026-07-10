# SPDX-License-Identifier: AGPL-3.0-only
#
# M2 tests (bead Sturm.jl-dc6i): the Orkan FFI shim — guards, ABI, loader, OMP.
# Orkan `exit()`s on bad input (audit §5), which we CANNOT observe from Julia;
# so each test asserts the Julia-side GUARD fires (raises before the ccall) —
# proving no path reaches `exit()`.

using Test
using Sturm
using Sturm: OrkanStateRaw, OrkanKrausRaw, OrkanSuperopRaw, ORKAN_PURE,
    ORKAN_MIXED_TILED, LIBORKAN, _state_new, orkan_state_free!,
    orkan_x!, orkan_cx!, orkan_ccx!, orkan_channel_1q!, orkan_state_init!

@testset "Orkan FFI shim (M2)" begin

    @testset "loader resolved to a real library" begin
        @test isassigned(LIBORKAN)
        @test !isempty(LIBORKAN[])
        # Under the test harness LIBORKAN_PATH is a real file.
        @test LIBORKAN[] == "liborkan" || isfile(LIBORKAN[])
    end

    @testset "raw struct ABI (byte-exact, audit §1/§4)" begin
        @test sizeof(OrkanStateRaw) == 24
        @test sizeof(OrkanKrausRaw) == 24
        @test sizeof(OrkanSuperopRaw) == 16
    end

    @testset "FFI guards raise Julia errors (never reach exit())" begin
        st = _state_new(ORKAN_PURE, 2)
        try
            # in-range works (2 qubits ⇒ indices 0,1)
            @test (orkan_x!(st, 0); true)
            # out-of-range qubit
            @test_throws ErrorException orkan_x!(st, 5)
            @test_throws ErrorException orkan_x!(st, 2)
            # non-distinct 2q / 3q
            @test_throws ErrorException orkan_cx!(st, 1, 1)
            @test_throws ErrorException orkan_ccx!(st, 0, 1, 1)
            # channel_1q on a PURE state (Orkan exit()s on PURE) — guard fires
            fake_sop = OrkanSuperopRaw(UInt8(1), ntuple(_ -> UInt8(0), 7), C_NULL)
            @test_throws ErrorException orkan_channel_1q!(st, fake_sop, 0)
        finally
            orkan_state_free!(st)
        end
    end

    @testset "channel_1q rejects non-1-local superop (bead Sturm.jl-1oy guard)" begin
        dm = _state_new(ORKAN_MIXED_TILED, 1)
        try
            bad_sop = OrkanSuperopRaw(UInt8(2), ntuple(_ -> UInt8(0), 7), C_NULL)
            @test_throws ErrorException orkan_channel_1q!(dm, bad_sop, 0)
        finally
            orkan_state_free!(dm)
        end
    end

    @testset "NULL-data state guard" begin
        # A fresh, uninitialized struct has data == NULL, qubits == 0.
        raw = OrkanStateRaw(ORKAN_PURE)
        @test raw.data == C_NULL
        @test_throws ErrorException orkan_x!(raw, 0)
    end

    @testset "OpenMP ceiling (audit §7)" begin
        # __init__ sets it if unset; the device ceiling is 16.
        @test haskey(ENV, "OMP_NUM_THREADS")
        @test parse(Int, ENV["OMP_NUM_THREADS"]) <= 16
        # the clamp formula never exceeds the ceiling
        @test clamp(Sys.CPU_THREADS ÷ 4, 1, 16) <= 16
        @test clamp(Sys.CPU_THREADS ÷ 4, 1, 16) >= 1
    end
end
