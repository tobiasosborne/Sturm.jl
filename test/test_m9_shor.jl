# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# Sturm.jl M9 (bead Sturm.jl-8oo9): `shor_order` — the order-finding capstone
# (design §4/§9.5/§9.6, closes F21/F22). Deterministic post-processing (exact CF /
# LCM / minimize / exception laws), the exact small orders (quantum, feasible
# widths), the ≥1000-trial seeded statistical suite, and the PRD-§7.7 verbatim
# execution proof.
#
# QUBIT-BUDGET FINDING (reported in the session worklog). Peak wires for one Shor
# sample are `2W (phase) + W (work) + scratch_width (mulmod! B∪A) + ctrl-borrow`:
#   N=3 (W=2): 4+2+9+1 = 16   → 2^16 (~1 MB), ~31 ms/sample — the ≥1000 suite.
#   N=5 (W=3): 6+3+13+1 = 23  → 2^23 (~128 MB), ~3-4 s/sample — a few exact calls.
#   N=15 (W=4): 8+4+17+1 = 30 → 2^30 (~16 GB), seconds-to-minutes/sample and
#     MULTIPLE samples per order — OVER the practical Orkan statevector budget for a
#     repeated driver. So N=15's capstone is verified at the PERMUTATION level
#     (mulmod! bijectivity, test_m9_modular.jl); its end-to-end quantum order is not
#     run in the suite. N=21 (W=5) does not even COMPILE (Bennett v0.5 cannot narrow
#     `*`/`%` at bit_width 5 — see the modular.jl deviation note).

using Test
using Sturm
using Bennett
using Random
using Sturm: shor_order, _shor_phase_sample, _cf_denominator, _minimize_order,
             NonCoprimeBaseError, OrderFindingFailure, eager
# `extract_julia_blocks` is defined in test_prd_examples.jl (Main scope, included
# earlier in runtests.jl) — used bare, as in test_m7_bennett.jl.

# Exact classical multiplicative order (the ground truth for the quantum result).
function classical_order(a, N)
    a = mod(a, N); gcd(a, N) == 1 || return 0
    r = 1; x = a
    while x != 1; x = mod(x * a, N); r += 1; end
    return r
end

@testset "M9 — shor_order (§4, §9.5/§9.6)" begin

    @testset "post-processing: exact continued-fraction denominators (§4.3, eq 5)" begin
        # r=4, Q=64: s/4 phases. ZERO-SAMPLE-IGNORED and q=1 skipped.
        @test _cf_denominator(0, 64, 5) === nothing        # z = 0 uninformative
        @test _cf_denominator(16, 64, 5) == 4              # 1/4 → q = 4
        @test _cf_denominator(48, 64, 5) == 4              # 3/4 → q = 4
        @test _cf_denominator(32, 64, 5) == 2              # 1/2 → q = 2 (divisor, s=2)
        # LCM-PROPER-DIVISORS: N=21, order 6, Q=1024 — divisor denominators 2 and 3.
        @test _cf_denominator(512, 1024, 21) == 2          # 1/2
        @test _cf_denominator(round(Int, 1024 / 3), 1024, 21) == 3   # 1/3
        @test lcm(2, 3) == 6 && powermod(2, 6, 21) == 1    # LCM of divisors → order
    end

    @testset "post-processing: prime-strip minimization (§1.Δ7)" begin
        # MINIMIZE-VERIFIED-MULTIPLE: 12 is a verified multiple of order(2,21)=6.
        @test classical_order(2, 21) == 6
        @test powermod(2, 12, 21) == 1
        @test _minimize_order(2, 21, 12) == 6
        @test _minimize_order(2, 5, 8) == 4                # order(2,5)=4; 8=2·4
        @test _minimize_order(2, 3, 6) == 2                # order(2,3)=2
    end

    @testset "driver guards (no quantum): order-1, non-coprime, exhaustion type" begin
        # ORDER-ONE — a₀ ≡ 1 returns 1 without sampling (the A-catch regression).
        @test shor_order(1, Val(15)) == 1
        @test shor_order(16, Val(15)) == 1                 # 16 ≡ 1 (mod 15)
        # NONCOPRIME-REPORTS-FACTOR — gcd(3,15)=3 found before any allocation.
        e = try; shor_order(3, Val(15)); nothing; catch err; err; end
        @test e isa NonCoprimeBaseError
        @test e.factor == 3
        @test occursin("nontrivial factor", sprint(showerror, e))
        @test_throws NonCoprimeBaseError shor_order(6, Val(15))   # gcd 3
        # EXHAUSTION-LOUD — the failure type is loud and carries context.
        @test occursin("verified order", sprint(showerror, OrderFindingFailure(2, 15, 3)))
        @test_throws DomainError shor_order(2, Val(1))     # N < 2
        @test_throws DomainError shor_order(2, Val(15); max_samples = 0)
    end

    @testset "exact small orders (quantum, feasible widths)" begin
        # A handful of full end-to-end runs at feasible widths; every return is the
        # exact classical order (verified + minimized inside the driver).
        r5 = eager(23; rng = MersenneTwister(0xA1)) do ctx; shor_order(2, Val(5)); end
        @test r5 == classical_order(2, 5) == 4
        r5b = eager(23; rng = MersenneTwister(0xA2)) do ctx; shor_order(4, Val(5)); end
        @test r5b == classical_order(4, 5) == 2
        r7 = eager(23; rng = MersenneTwister(0xA3)) do ctx; shor_order(2, Val(7)); end
        @test r7 == classical_order(2, 7) == 3
        r3 = eager(16; rng = MersenneTwister(0xA4)) do ctx; shor_order(2, Val(3)); end
        @test r3 == classical_order(2, 3) == 2
    end

    @testset "M9.SHOR.END-TO-END-STATISTICAL — N=3, ≥1000 seeded trials" begin
        # N=3 (order 2) is the only width where 1000 quantum trials are feasible
        # (~31 ms/sample). Assert: every successful return is the exact order; NO
        # wrong order EVER; a one-sided lower bound on success ≥ 0.95 (§9.6). The
        # threshold is justified in docs/physics/shor_order_finding.md (per-sample
        # ≥ φ(r)/3r; φ(2)/2·max_samples compound geometrically toward 1).
        N, a, rexact = 3, 2, 2
        trials = 1000
        successes = 0; wrong = 0; failures = 0
        for t in 1:trials
            r = eager(16; rng = MersenneTwister(hash((0xC0FFEE, t)))) do ctx
                try
                    shor_order(a, Val(N))
                catch e
                    e isa OrderFindingFailure ? -1 : rethrow()
                end
            end
            if r == -1
                failures += 1
            elseif r == rexact
                successes += 1
            else
                wrong += 1
            end
        end
        @info "shor_order N=3 statistical" trials successes wrong failures
        @test wrong == 0                                   # NEVER a wrong order
        # one-sided 99% binomial lower bound on the success rate ≥ 0.95:
        p̂ = successes / trials
        lb = p̂ - 2.33 * sqrt(max(p̂ * (1 - p̂), 1e-9) / trials)
        @test lb ≥ 0.95
    end

    @testset "PRD §7.7 executes VERBATIM (normative blocks)" begin
        # The PRD's own _shor_phase_sample + shor_order source is extracted and eval'd
        # into a fresh module (guarantees the normative text RUNS — the DJ/BV pattern).
        blocks = extract_julia_blocks(joinpath(@__DIR__, "..", "Sturm-PRD-v2.md"))
        ps = only(filter(b -> occursin("function _shor_phase_sample", b.code), blocks))
        drv = only(filter(b -> occursin("function shor_order", b.code), blocks))
        m = Module(:PRDExecM9)
        Core.eval(m, :(using Sturm))
        Core.eval(m, :(using Bennett))
        Core.eval(m, :(using Sturm: _cf_denominator, _minimize_order,
                                    NonCoprimeBaseError, OrderFindingFailure))
        Base.include_string(m, ps.code)
        Base.include_string(m, drv.code)
        r = eager(23; rng = MersenneTwister(0xBEEF)) do ctx
            Base.invokelatest(m.shor_order, 2, Val(5))
        end
        @test r == 4
        @test Base.invokelatest(m.shor_order, 1, Val(15)) == 1
    end
end
