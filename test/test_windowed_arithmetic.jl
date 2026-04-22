using Test
using Sturm
using Sturm: qrom_lookup_xor!, plus_equal_product!

# Eager-flushed staged output (feedback_verbose_eager_flush).
_t0 = time_ns()
_ms() = round((time_ns() - _t0) / 1e6, digits=1)
_log(msg) = (println("[$(rpad(_ms(), 7)) ms] $msg"); flush(stdout))
_log("ENTER test_windowed_arithmetic.jl")

# Sturm.jl-6oc Phase A — windowed arithmetic atoms.
#
# Physics ground truth:
#   Gidney 2019 "Windowed quantum arithmetic", arXiv:1905.07682 §3.1
#     docs/physics/gidney_2019_windowed_arithmetic.pdf
#   Gidney-Ekerå 2021 "How to factor 2048 bit RSA integers …" arXiv:1905.09749  §2.5, Fig 2
#     docs/physics/gidney_ekera_2021_rsa2048.pdf
#   Babbush et al. 2018 "Encoding Electronic Spectra …" arXiv:1805.03662  §III.C Fig 10, App C
#     docs/physics/babbush_2018_qrom_linear_T.pdf
#
# Test sizing is deliberately small. Orkan per-gate cost grows exponentially
# with live-qubit count; the peak-live budget per case is kept under ~14
# qubits. Correctness of larger cases was confirmed offline via
# probe_pep_timing.jl (Lt=6 Ly=4 window=1 returned 15=expected, in ~2 min).

@testset "qrom_lookup_xor!" begin
    _log("ENTER qrom_lookup_xor!")

    @testset "identity table T[i]=i, basis-state address" begin
        _log("  ENTER identity table  [peak ≈ 7 qubits]")
        for addr_val in 0:3
            @context EagerContext() begin
                addr = QInt{2}(addr_val)
                target = QInt{3}(0)
                tbl = QROMTable{2,3}([0, 1, 2, 3])
                qrom_lookup_xor!(target, addr, tbl)
                @test Int(target) == addr_val
                @test Int(addr)   == addr_val
            end
        end
        _log("  EXIT identity table")
    end

    @testset "arbitrary table, XOR into pre-loaded target" begin
        _log("  ENTER arbitrary table  [peak ≈ 7 qubits]")
        tbl_entries = [5, 2, 7, 1]
        for addr_val in 0:3
            @context EagerContext() begin
                addr = QInt{2}(addr_val)
                target = QInt{3}(3)
                tbl = QROMTable{2,3}(tbl_entries)
                qrom_lookup_xor!(target, addr, tbl)
                @test Int(target) == 3 ⊻ tbl_entries[addr_val + 1]
                @test Int(addr)   == addr_val
            end
        end
        _log("  EXIT arbitrary table")
    end

    @testset "calling twice with the same address is identity" begin
        _log("  ENTER twice-call  [peak ≈ 10 qubits]")
        @context EagerContext() begin
            addr = QInt{3}(5)
            target = QInt{4}(9)
            tbl = QROMTable{3,4}([3, 15, 8, 1, 6, 12, 0, 11])
            qrom_lookup_xor!(target, addr, tbl)
            qrom_lookup_xor!(target, addr, tbl)   # uncompute
            @test Int(target) == 9
            @test Int(addr)   == 5
        end
        _log("  EXIT twice-call")
    end

    @testset "superposed address: even superposition → correct entanglement" begin
        _log("  ENTER superposed addr  [peak ≈ 7 qubits]")
        tbl_entries = [4, 2, 7, 1]
        @context EagerContext() begin
            addr = QInt{2}(0)
            for i in 1:2
                H!(QBool(addr.wires[i], addr.ctx, false))
            end
            target = QInt{3}(0)
            tbl = QROMTable{2,3}(tbl_entries)
            qrom_lookup_xor!(target, addr, tbl)
            a_m = Int(addr)
            t_m = Int(target)
            @test t_m == tbl_entries[a_m + 1]
        end
        _log("  EXIT superposed addr")
    end

    _log("EXIT qrom_lookup_xor!")
end

@testset "plus_equal_product! (non-modular)" begin
    _log("ENTER plus_equal_product!")

    @testset "basis state, target += k·y mod 2^Lt" begin
        _log("  ENTER basis state  [peaks ≤ 14 qubits]")
        # peak_live = 2·Lt + Ly + window. Budget: ≤ 14 for session runtime.
        for (k, y0, window, Lt, Ly) in [
            (3, 2, 1, 4, 2),   # peak 11
            (3, 3, 1, 4, 2),   # peak 11
            (5, 1, 1, 4, 2),   # peak 11
            (0, 3, 1, 4, 2),   # peak 11 — k=0 early-return path
            (1, 0, 1, 4, 2),   # peak 11
            (3, 5, 2, 4, 4),   # peak 14 — two iterations, window=2
            (7, 3, 1, 5, 2),   # peak 13
            (1, 3, 2, 4, 2),   # peak 12 — window = Ly single-lookup, y0 fits in Ly=2 bits
        ]
            _log("    case k=$k y0=$y0 window=$window Lt=$Lt Ly=$Ly")
            @context EagerContext() begin
                target = QInt{Lt}(0)
                y = QInt{Ly}(y0)
                plus_equal_product!(target, k, y; window=window)
                expected = (k * y0) % (1 << Lt)
                @test Int(target) == expected
                @test Int(y)      == y0
            end
        end
        _log("  EXIT basis state")
    end

    @testset "target non-zero: accumulation" begin
        _log("  ENTER accumulation  [peak ≤ 13 qubits]")
        for (t0, k, y0, window, Lt, Ly) in [
            (7,  3, 2, 1, 4, 2),   # peak 11
            (5,  3, 3, 1, 5, 2),   # peak 13
            (2,  3, 3, 2, 4, 2),   # peak 12
        ]
            _log("    case t0=$t0 k=$k y0=$y0 window=$window Lt=$Lt Ly=$Ly")
            @context EagerContext() begin
                target = QInt{Lt}(t0 & ((1 << Lt) - 1))
                y = QInt{Ly}(y0 & ((1 << Ly) - 1))
                plus_equal_product!(target, k, y; window=window)
                expected = ((t0 & ((1 << Lt) - 1)) + k * (y0 & ((1 << Ly) - 1))) % (1 << Lt)
                @test Int(target) == expected
                @test Int(y)      == (y0 & ((1 << Ly) - 1))
            end
        end
        _log("  EXIT accumulation")
    end

    @testset "k = 0: identity on target" begin
        _log("  ENTER k=0 identity  [peak 6 qubits, early-return]")
        @context EagerContext() begin
            Lt, Ly = 4, 2
            target = QInt{Lt}(9)
            y = QInt{Ly}(3)
            plus_equal_product!(target, 0, y; window=1)
            @test Int(target) == 9
            @test Int(y)      == 3
        end
        _log("  EXIT k=0 identity")
    end

    @testset "superposed y: entanglement correctness" begin
        _log("  ENTER superposed y  [peak 13 qubits]")
        @context EagerContext() begin
            Lt, Ly = 5, 2
            target = QInt{Lt}(0)
            y = QInt{Ly}(0)
            for i in 1:Ly
                H!(QBool(y.wires[i], y.ctx, false))
            end
            k = 3
            plus_equal_product!(target, k, y; window=1)
            y_m = Int(y)
            t_m = Int(target)
            @test t_m == (k * y_m) % (1 << Lt)
        end
        _log("  EXIT superposed y")
    end

    @testset "preconditions fire loudly" begin
        _log("  ENTER preconditions  [tiny]")
        @context EagerContext() begin
            target = QInt{4}(0)
            y = QInt{3}(5)
            @test_throws ErrorException plus_equal_product!(target, 3, y; window=2)  # 3 % 2 ≠ 0
            @test_throws ErrorException plus_equal_product!(target, 3, y; window=0)
            @test_throws ErrorException plus_equal_product!(target, 3, y; window=4)  # window > Ly
            ptrace!(target); ptrace!(y)
        end
        _log("  EXIT preconditions")
    end

    _log("EXIT plus_equal_product!")
end

_log("EXIT test_windowed_arithmetic.jl")
