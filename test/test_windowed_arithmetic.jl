using Test
using Sturm
using Sturm: qrom_lookup_xor!, plus_equal_product!, plus_equal_product_mod!, decode!
using Sturm: _shor_mulmod_E_controlled!

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

# ═════════════════════════════════════════════════════════════════════════════
# plus_equal_product_mod! — Gidney 2019 §3.3 (Sturm.jl-6oc Phase B step 1)
#
# Modular variant of plus_equal_product!. Target is a QCoset (GE21 §2.4
# coset representation); the inner add is non-modular, but the coset
# structure makes it ≈ modular add mod N with deviation ≤ 2^{-Cpad} per op.
# The position factor 2^i is folded into each window's lookup table, so
# there is no target-slice pattern — every iteration adds into the full
# Wtot-bit reg.
#
# For these tests, N < 2^W is the QCoset invariant and table entries are
# reduced mod N (≤ N-1). The resulting max branch value per iteration is
# (2^Cpad - 1)·N + (N - 1) = 2^Cpad · N - 1 < 2^(W+Cpad) = 2^Wtot, so
# NO coset branch wraps → deterministic per-shot, no statistical slack.
# ═════════════════════════════════════════════════════════════════════════════

@testset "plus_equal_product_mod! (QCoset, no-wrap regime)" begin
    _log("ENTER plus_equal_product_mod!")

    @testset "basis state, target_coset += k·y mod N" begin
        _log("  ENTER basis state  [peak ≤ 15 qubits, no-wrap regime]")
        # (N, W, Cpad, k, y0, window, Ly)
        # peak_live = (W+2·Cpad) + Ly + (W+Cpad) + window = 2W + 3·Cpad + Ly + window
        for (N, W, Cpad, k, y0, window, Ly) in [
            (5, 3, 1, 3, 2, 1, 2),   # peak 12; (3·2) mod 5 = 1
            (5, 3, 1, 2, 3, 1, 2),   # peak 12; (2·3) mod 5 = 1
            (5, 3, 1, 4, 1, 1, 2),   # peak 12; (4·1) mod 5 = 4
            (5, 3, 1, 1, 0, 1, 2),   # peak 12; (1·0) mod 5 = 0 (zero-y path)
            (5, 3, 1, 0, 3, 1, 2),   # peak 12; k=0 identity
            (7, 3, 2, 3, 2, 1, 2),   # peak 15; (3·2) mod 7 = 6
            (7, 3, 2, 3, 3, 1, 2),   # peak 15; (3·3) mod 7 = 2 — Cpad=2 (Cpad=1 hits the wrap bound 2^Cpad·(2^W-N)+N = 9 exactly at a_total=9)
            (5, 3, 1, 3, 3, 2, 2),   # peak 13; window=Ly single lookup; (3·3) mod 5 = 4
        ]
            _log("    case N=$N W=$W Cpad=$Cpad k=$k y0=$y0 window=$window Ly=$Ly")
            @context EagerContext() begin
                target = QCoset{W, Cpad}(0, N)   # encode residue 0 mod N
                y = QInt{Ly}(y0)
                plus_equal_product_mod!(target, k, y; window=window)
                expected = mod(k * y0, N)
                @test decode!(target) == expected
                @test Int(y) == y0
            end
        end
        _log("  EXIT basis state")
    end

    @testset "target_coset non-zero initial residue" begin
        _log("  ENTER non-zero initial  [peak ≤ 13 qubits]")
        # Starting from residue r0, add k·y: expect (r0 + k·y) mod N.
        for (N, W, Cpad, r0, k, y0, window, Ly) in [
            (5, 3, 1, 2, 3, 1, 1, 2),   # (2 + 3·1) mod 5 = 0
            (7, 3, 1, 3, 2, 2, 1, 2),   # (3 + 2·2) mod 7 = 0
        ]
            _log("    case N=$N Cpad=$Cpad r0=$r0 k=$k y0=$y0 window=$window")
            @context EagerContext() begin
                target = QCoset{W, Cpad}(r0, N)
                y = QInt{Ly}(y0)
                plus_equal_product_mod!(target, k, y; window=window)
                expected = mod(r0 + k * y0, N)
                @test decode!(target) == expected
                @test Int(y) == y0
            end
        end
        _log("  EXIT non-zero initial")
    end

    @testset "k = 0: identity on coset target" begin
        _log("  ENTER k=0 identity  [peak 7 qubits, early-return]")
        @context EagerContext() begin
            target = QCoset{3, 1}(3, 5)
            y = QInt{2}(2)
            plus_equal_product_mod!(target, 0, y; window=1)
            @test decode!(target) == 3
            @test Int(y) == 2
        end
        _log("  EXIT k=0 identity")
    end

    @testset "preconditions fire loudly" begin
        _log("  ENTER preconditions  [tiny]")
        @context EagerContext() begin
            target = QCoset{3, 1}(0, 5)
            y = QInt{3}(5)
            @test_throws ErrorException plus_equal_product_mod!(target, 3, y; window=2)  # 3 % 2 ≠ 0
            @test_throws ErrorException plus_equal_product_mod!(target, 3, y; window=0)
            @test_throws ErrorException plus_equal_product_mod!(target, 3, y; window=4)  # window > Ly
            ptrace!(target); ptrace!(y)
        end
        _log("  EXIT preconditions")
    end

    _log("EXIT plus_equal_product_mod!")
end

# ═════════════════════════════════════════════════════════════════════════════
# _shor_mulmod_E_controlled! — Gidney 2019 §3.4 Fig 6 cmult-swap pattern
# (Sturm.jl-6oc Phase B step 2)
#
# Controlled modular multiplication on a QCoset target:
#     if ctrl = |1⟩:  target ← (a · target) mod N
#     if ctrl = |0⟩:  target unchanged
#
# Three phases per Fig 6:
#   1. b += a · x  (windowed, via plus_equal_product_mod!, under when(ctrl))
#   2. controlled-SWAP(x, b) on all wires (reg AND pad_anc)
#   3. b -= a⁻¹ · x  ≡  b += (-a⁻¹ mod N) · x  (windowed, under when(ctrl))
# Then free b — clean |0⟩ coset on both ctrl branches.
#
# Tests use tiny N (= 3) with W=2 Cpad=2 to keep the deterministic no-wrap
# regime while fitting under 18 live qubits. Slow on Orkan (~one minute per
# case) but correct.
# ═════════════════════════════════════════════════════════════════════════════

@testset "_shor_mulmod_E_controlled! (N=3 W=2 Cpad=1, ctrl=|1⟩, x=1)" begin
    _log("ENTER _shor_mulmod_E_controlled!")

    # Analytical no-wrap sanity check for (N=3 W=2 Cpad=1 a=2 x=1 c_mul=1):
    # step 1 scratches = {2, 0, 0}, b branches max = 5 < 2^Wtot = 8. ✓
    # step 3 (after swap) scratches = {1, 2, 1}, b branches max = 6 < 8. ✓
    # ∴ deterministic single-shot assertion is safe at Cpad=1.
    @testset "ctrl=|1⟩, x=1: target ← (2·1) mod 3 = 2" begin
        _log("  ENTER ctrl=1 x=1  [peak ≈ 15 qubits, slow]")
        @context EagerContext() begin
            target = QCoset{2, 1}(1, 3)
            ctrl = QBool(1)
            _shor_mulmod_E_controlled!(target, 2, ctrl; c_mul=1)
            @test decode!(target) == 2
            @test Bool(ctrl) == true
        end
        _log("  EXIT ctrl=1 x=1")
    end

    _log("EXIT _shor_mulmod_E_controlled!")
end

# ═════════════════════════════════════════════════════════════════════════════
# shor_order_E — end-to-end driver (Sturm.jl-6oc Phase B step 3)
#
# Same Parker-Plenio semi-classical cascade as shor_order_D_semi, with the
# coset-encoded target + windowed mulmod. Single-shot callability test:
# confirm the function runs and returns a classically-valid period candidate
# (integer divisor from continued fractions). Full 50-shot statistical
# acceptance (bead criterion a: ≥30% hit rate on (7,15;t=3)) deferred to a
# bench run — runtime on this device is ~10-20 min for 50 shots at N=15.
# ═════════════════════════════════════════════════════════════════════════════

@testset "shor_order_E — callable, returns valid period" begin
    _log("ENTER shor_order_E")

    @testset "shor_order_E(2, 3; t=3) single shot" begin
        _log("  ENTER (2, 3; t=3)  [peak ≈ 13 qubits; cpad=1 c_mul=1]")
        @context EagerContext() begin
            # Order of 2 mod 3 is 2. Ideal distribution: ỹ ∈ {0, 4} with
            # prob 1/2 each → r ∈ {1, 2}. Coset deviation perturbs slightly
            # but still stays in divisors of |Z_N*|.
            r = shor_order_E(2, 3, Val(3); cpad=1, c_mul=1)
            @test r in [1, 2]
        end
        _log("  EXIT (2, 3; t=3)")
    end

    _log("EXIT shor_order_E")
end

_log("EXIT test_windowed_arithmetic.jl")
