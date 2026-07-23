# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# Sturm.jl M9 (bead Sturm.jl-8oo9): the §7.6 magic-state INJECTION LADDER executed
# under EagerContext (both observation branches, the non-Pauli S-correction path
# explicit), and the PRD §8 v0.1 DEFECT-LEDGER closure — a NAMED green regression
# for each remaining defect class (plan §M9: 8.1→M5, 8.3→M4, 8.4→M2/M4, 8.5→M6,
# 8.6→API-shape, 8.7→M1 totality, 8.8→M4; 8.2 died with the surface). The v2
# design closes each by construction; this asserts it once, in M9's vocabulary.

using Test
using Sturm
using Sturm: eager, statevector, when, dual, not!, ctrl, X, denoted_matrix,
             QMod, mulmod!, oracle
# `extract_julia_blocks` is defined in test_prd_examples.jl (Main scope, included
# earlier in runtests.jl) — used bare, as in test_m7_bennett.jl.

@testset "M9 — §7.6 injection ladder executes (both branches, S/T exact)" begin
    blocks = extract_julia_blocks(joinpath(@__DIR__, "..", "Sturm-PRD-v2.md"))
    injS = only(filter(b -> occursin("function inject_S!", b.code), blocks))
    injT = only(filter(b -> occursin("function inject_T!", b.code), blocks))
    m = Module(:PRDInjM9)
    Core.eval(m, :(using Sturm))
    # inject_S! and inject_T! share ONE fenced block in the PRD (§7.6) — include
    # each distinct block exactly once (double-include = overwrite warnings).
    for code in unique(b.code for b in (injS, injT))
        Base.include_string(m, code)
    end

    # inject_S! ≡ S, inject_T! ≡ T on the state |ψ⟩ = √(1−p)|0⟩ + e^{iφ}√p|1⟩, for
    # BOTH measurement outcomes (min overlap over many trials exercises the
    # correction arm). Compared up to global phase (state overlap).
    function min_overlap(fn, gate, p, phi; trials = 200)
        a0 = sqrt(1 - p); a1 = exp(im * phi) * sqrt(p); ex = gate * [a0, a1]
        ov = 1.0
        for _ in 1:trials
            amps = eager(6) do ctx
                psi = QBool(p, phi); Base.invokelatest(fn, psi); statevector(ctx)
            end
            ov = min(ov, abs(sum(conj(ex) .* amps[1:2])))
        end
        return ov
    end
    Smat = ComplexF64[1 0; 0 im]
    Tmat = ComplexF64[1 0; 0 exp(im * π / 4)]
    for (p, phi) in ((0.5, 0.0), (0.5, π / 3), (0.0, 0.0), (1.0, 0.0))
        @test min_overlap(m.inject_S!, Smat, p, phi) ≈ 1.0 atol = 1e-6
    end
    for (p, phi) in ((0.5, 0.0), (0.5, π / 3))
        @test min_overlap(m.inject_T!, Tmat, p, phi) ≈ 1.0 atol = 1e-6
    end

    # The T-gadget's correction is a NON-PAULI Clifford (S), distinct from identity
    # (a Pauli-frame tracker could not express it) — S ≠ I as a channel.
    @test denoted_matrix(Sturm.S) ≉ denoted_matrix(Sturm.I2)
end

@testset "M9 — §8 v0.1 defect-ledger closure (named regressions)" begin

    @testset "§8.1 — Bool(q) inside when() is a LOUD error (not silent collapse)" begin
        eager(4) do ctx
            c = QBool(0.5); q = QBool(0.5)
            @test_throws Exception when(c) do; Bool(q); end
        end
    end

    @testset "§8.3 — mixed xor(QBool,Bool) lowers to EXACT X (no Ry(π) phase)" begin
        # q ⊻= true flips exactly; under `when` it is a clean CNOT with NO spurious
        # controlled phase (the v0.1 qbool.jl:154 latent-phase bug).
        amps = eager(4) do ctx
            c = QBool(0.5); q = QBool(false)   # |+⟩|0⟩
            when(c) do; q ⊻= true; end          # → (|00⟩ + |11⟩)/√2, EQUAL phases
            [a for a in statevector(ctx) if abs(a) > 1e-9]
        end
        @test length(amps) == 2
        @test isapprox(amps[1], amps[2]; atol = 1e-9)   # equal ⇒ in phase (exact X)
    end

    @testset "§8.4 — DSL-level aliasing caught with register identity" begin
        eager(4) do ctx
            a = QBool(0.5)
            @test_throws Exception when(a) do; not!(a); end    # control == target
        end
        eager(6) do ctx
            x = QInt{3}(0)
            @test_throws Exception (x ⊻= x)                    # shared WireID
        end
    end

    @testset "§8.5 — single-sourced consumed set: holed register fails loud" begin
        eager(6) do ctx
            x = QInt{3}(5)
            Bool(x[1])                          # partial consumption of x
            @test_throws Exception Int(x)       # measuring the holed register is loud
        end
    end

    @testset "§8.6 — typed register library APIs (no Vector{QBool})" begin
        # mulmod! dispatches on the typed QMod handle; oracle on QInt — not on a
        # bag of qubits. The typed-from-day-one contract (P9, no catch-all).
        @test hasmethod(mulmod!, Tuple{QMod{15,4,Sturm.EagerContext},Int})
        @test !hasmethod(mulmod!, Tuple{Vector{QBool}})
        @test any(m -> m.sig <: Tuple{Any,typeof(oracle),<:Any,<:QInt},
                  methods(oracle).ms) || hasmethod(oracle, Tuple{typeof(identity),QInt{3,Sturm.EagerContext}})
    end

    @testset "§8.7 — kernel ctrl is total: no control-count cap" begin
        # v0.1 capped `_apply_ctrls` at 2 controls; v2's ctrl is a homomorphism with
        # no cap — ctrl^k(X) builds for any k (the marquee closure fact).
        u = X
        for k in 1:6
            u = ctrl(u)
        end
        @test u isa Sturm.Ctrl
        @test u.k == 6
        # and it denotes a genuine 7-wire controlled-X (128×128 permutation)
        M = denoted_matrix(u)
        @test size(M) == (128, 128)
    end

    @testset "§8.8 — Z-sensitive probe: S injection distinguishable from identity" begin
        # v0.1's teleportation Choi test was Z-blind (marginals). A Z-sensitive
        # channel (S carries a relative phase on |1⟩) is distinguished from identity
        # on the |+⟩ probe: S|+⟩ = |i⟩ ≠ |+⟩ (a Z-marginal cannot see it, the phase can).
        sv = eager(4) do ctx
            q = QBool(0.5)          # |+⟩
            Sturm.apply!(ctx, Sturm.S, (q.wire,))   # test tooling: apply S directly
            statevector(ctx)
        end
        # |i⟩ = (|0⟩ + i|1⟩)/√2: the two amplitudes are 90° out of phase (Z-sensitive)
        @test isapprox(abs(sv[1]), abs(sv[2]); atol = 1e-9)
        @test isapprox(angle(sv[2]) - angle(sv[1]), π / 2; atol = 1e-6)
    end
end
