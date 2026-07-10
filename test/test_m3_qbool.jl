# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# Sturm.jl M3 (bead Sturm.jl-77m2): the boundary-algebra law tests for `QBool`
# and the consuming casts. The channel-level laws (cq∘qc = pinching on a coherent
# probe; the identity Choi) live in `test/choi.jl`; this file covers the
# state/value-level and error-taxonomy laws (PRD-v2 §3.2, D1, §3.9, S13).

using Test
using Random
using LinearAlgebra
using Sturm
using Sturm: eager, density, _prep_u2, denoted_matrix, statevector, density_matrix,
    allocate!, apply!, q, live_wires, is_consumed, current_context, _core

# Statevector equality up to a single unobservable GLOBAL phase.
function sv_upto_phase(a::AbstractVector, b::AbstractVector; atol::Real=1e-9)
    length(a) == length(b) || return false
    i = argmax(abs.(b))
    abs(b[i]) < 1e-12 && return isapprox(a, b; atol=atol)
    ph = a[i] / b[i]
    abs(abs(ph) - 1) < 1e-6 || return false
    return isapprox(a, ph .* b; atol=atol)
end

# Prepared statevector (Eager) / density matrix (DM, global-phase-free) of a
# 0-arg preparation thunk.
prep_sv(f) = eager(1) do _; f(); statevector(current_context()) end
prep_dm(f) = density(1) do _; f(); density_matrix(current_context()) end

@testset "M3 QBool — preparation cast (cq, §3.2 / D1)" begin

    @testset "prep value first column = analytic |0⟩-image (A's oracle for B's ∘)" begin
        for p in (0.0, 0.1, 0.5, 0.9, 1.0), φ in (0.0, 0.7, π, π / 4, -1.3)
            col = denoted_matrix(_prep_u2(Float64(p), Float64(φ)))[:, 1]
            # A's derivation: U|0⟩ = √(1−p) e^{−iφ/2}|0⟩ + √p e^{+iφ/2}|1⟩.
            analytic = ComplexF64[sqrt(1 - p) * cis(-φ / 2), sqrt(p) * cis(φ / 2)]
            @test sv_upto_phase(col, analytic)
            @test abs2(col[1]) ≈ 1 - p atol = 1e-9    # Born weight on |0⟩
            @test abs2(col[2]) ≈ p     atol = 1e-9    # Born weight on |1⟩
        end
    end

    @testset "named literals |+⟩ / |−⟩ / magic_T (|A⟩)" begin
        @test sv_upto_phase(prep_sv(plus),  ComplexF64[1, 1] ./ sqrt(2))
        @test sv_upto_phase(prep_sv(minus), ComplexF64[1, -1] ./ sqrt(2))
        # PRD D1/§7.6: magic_T = |A⟩ = (|0⟩ + e^{iπ/4}|1⟩)/√2. Verified against
        # the PRD's own definition (Sturm-PRD-v2.md:1335, :562).
        @test sv_upto_phase(prep_sv(magic_T), ComplexF64[1, cis(π / 4)] ./ sqrt(2))
    end

    @testset "QBool(::Bool) dispatch + exact X (D1)" begin
        @test sv_upto_phase(prep_sv(() -> QBool(false)), ComplexF64[1, 0])
        @test sv_upto_phase(prep_sv(() -> QBool(true)),  ComplexF64[0, 1])
        # QBool(true) hits the more-specific Bool method, NOT the (p,φ) method.
        @test which(QBool, Tuple{Bool}) !== which(QBool, Tuple{Int})
        # QBool(1) (Int isa Real) prepares the same |1⟩ via the (p,φ) path.
        @test sv_upto_phase(prep_sv(() -> QBool(1)), ComplexF64[0, 1])
    end

    @testset "Irrational-safe φ (Float64 before the emit, D1)" begin
        # π / π/4 are Irrational; must not error, and must match the Float64 form.
        @test sv_upto_phase(prep_sv(() -> QBool(0.3, π)),
                            prep_sv(() -> QBool(0.3, Float64(π))))
        @test prep_dm(minus) ≈ prep_dm(() -> QBool(0.5, Float64(π)))
    end

    @testset "pole degeneracy: QBool(1,φ) ≡ QBool(true), φ swept (D1)" begin
        # A STATE-level law (φ is unobservable at the pole — one amplitude
        # vanishes). Tested on DM (global-phase-free), NEVER via handle ==.
        one_dm = ComplexF64[0 0; 0 1]
        zero_dm = ComplexF64[1 0; 0 0]
        for φ in (0.0, π / 3, π, 7.1, -2.0)
            @test prep_dm(() -> QBool(1.0, φ)) ≈ one_dm
            @test prep_dm(() -> QBool(0.0, φ)) ≈ zero_dm
        end
        @test prep_dm(() -> QBool(true)) ≈ one_dm
        @test prep_dm(() -> QBool(false)) ≈ zero_dm
    end
end

@testset "M3 QBool — measurement cast (qc, §3.2)" begin

    @testset "qc∘cq = id on classical data: Bool(QBool(b)) == b (deterministic)" begin
        for b in (false, true)
            @test eager(1) do _; Bool(QBool(b)) end == b
        end
    end

    @testset "consumption retires the wire + recycles the slot" begin
        eager(2) do ctx
            q0 = QBool(0.5)
            w = q0.wire
            @test w in keys(_core(ctx).wire_to_slot)
            Bool(q0)
            @test is_consumed(ctx, w)
            @test !(w in keys(_core(ctx).wire_to_slot))   # retired
        end
    end

    @testset "P2 — implicit convert warns, explicit Bool is silent" begin
        eager(1) do _
            @test_logs Bool(QBool(true))               # explicit: NO log
        end
        eager(1) do _
            q0 = QBool(true)
            @test_logs (:warn,) convert(Bool, q0)      # implicit: warns (P2)
        end
    end

    @testset "statistical prep frequencies (N≥1000, ±3σ, seeded)" begin
        for p in (0.3, 0.7)
            N = 2000
            rng = MersenneTwister(0xC0FFEE)
            cnt = eager(1; rng=rng) do _
                c = 0
                for _ in 1:N
                    c += Bool(QBool(p)) ? 1 : 0
                end
                c
            end
            freq = cnt / N
            σ = sqrt(p * (1 - p) / N)
            @test abs(freq - p) < 3σ
        end
    end
end

@testset "M3 QBool — S13 error taxonomy (one policy test)" begin
    # DomainError — chart violation (p ∉ [0,1]); never widened to Complex.
    @test_throws DomainError eager(1) do _; QBool(1.5)  end
    @test_throws DomainError eager(1) do _; QBool(-0.1) end
    @test_throws DomainError eager(1) do _; QBool(NaN)  end

    # ArgumentError — well-formed-but-forbidden.
    #  (a) DM scalar Bool (a trajectory, not a channel — D3/§3.8, deferred to M8).
    @test_throws ArgumentError density(1) do _; Bool(QBool(0.5)) end
    #  (b) cross-context handle (a handle escaped its context; closed by storing ctx).
    @test_throws ArgumentError eager(1) do _
        qo = QBool(0.5)                 # qo.ctx = outer
        eager(1) do _
            Bool(qo)                    # current = inner ≠ qo.ctx → ArgumentError
        end
    end

    # error() with WireID — linearity/liveness guardrails.
    #  (a) double consume.
    @test_throws ErrorException eager(1) do _
        q0 = QBool(0.5); Bool(q0); Bool(q0)
    end
    #  (b) trace-after-consume (dead handle on the single-sourced set).
    @test_throws ErrorException eager(1) do _
        q0 = QBool(0.5); Bool(q0); ptrace!(q0.wire)
    end

    # S13: no custom exception hierarchy introduced by M3.
    for rel in ("src/types/qbool.jl", "src/surface/casts.jl")
        txt = read(joinpath(REPO_ROOT, rel), String)
        @test !occursin(r"struct\s+\w+\s*<:\s*Exception", txt)
    end
end

@testset "M3 QBool — region interaction (§3.9)" begin
    # Unconsumed local QBool is traced at region exit (no leak, slot recycled).
    eager(2) do ctx
        before = length(live_wires(ctx))
        w = region() do
            QBool(0.5).wire
        end
        @test !(w in keys(_core(ctx).wire_to_slot))     # traced at exit
        @test length(live_wires(ctx)) == before
    end

    # A QBool CONSUMED inside the region is skipped at exit — NO double-trace.
    # (It is both retired from wire_to_slot AND in the consumed set, so
    # `_exit_region!` fails both predicates and does nothing further.)
    eager(2) do ctx
        before = length(live_wires(ctx))
        region() do
            q0 = QBool(0.5)
            Bool(q0)
            @test is_consumed(ctx, q0.wire)
            @test !(q0.wire in keys(_core(ctx).wire_to_slot))
        end
        @test length(live_wires(ctx)) == before          # exit was a no-op for it
    end
end
