# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# Sturm.jl M8 (bead Sturm.jl-szx1) — the i4ri classical-control gate, DM/Eager
# slice. The L-battery (design `docs/design/m8-i4ri-classical-control-design.md`
# §8) that belongs to the DM/Eager side: Ruling-D token casts, the exact
# instrument-sum `cases` executor, repeated-token correlation (the MANDATORY
# PHASE form — pinched records are diagonal-blind, the wm28 lesson), join-typing,
# copyable/derived tokens, the loud-rejection boundary, `select`/`ClassicalTable`,
# `shots`, and `discard!`. Channel-level verification is at the Choi level
# (`choi`/`_choi2`, INCLUDED earlier in runtests.jl — reused here, test_m4_views
# style); teleport-class fixtures probe Z-SENSITIVE states, never Z-basis-only.
#
# Reserved for the NEXT slice (NOT tested here): TracingContext token variant,
# MeasureNode/CasesNode emission, DeferMeasurementPass, the tracer pre-flight lint.

using Test
using LinearAlgebra
using Random
using Sturm
using Sturm: eager, density, density_matrix, apply!, allocate!, q, superpose!,
    H, X, Z, ctrl, _adopt_qbool,
    ClassicalBit, ClassicalWord, ClassicalToken, ClassicalTable,
    select, shots, discard!, width, zext, truncate_word

# --- Fixtures ---------------------------------------------------------------

# The §7.1b deferred teleport, token+`cases` form (Ruling D): measure both halves
# to RECORD tokens, condition the X/Z corrections off the records. One-run exact.
function teleport_tok(ψ::AbstractQubit)
    ctx = ψ.ctx
    a = QBool(false); c = QBool(false)
    apply!(ctx, H, (a.wire,)); apply!(ctx, ctrl(X), (a.wire, c.wire))   # Bell(a,c)
    apply!(ctx, ctrl(X), (ψ.wire, a.wire)); apply!(ctx, H, (ψ.wire,))    # entangle ψ with a
    m2 = Bool(_adopt_qbool(ctx, a.wire))    # measure a → record
    m1 = Bool(ψ)                            # measure ψ (Z-basis) → record
    cases(m2) do; not!(c) end               # X correction, off the a-record
    cases(m1) do; not!(dual(c)) end          # Z correction, off the ψ-record
    return c
end

# A 2-in/2-out channel driven by ONE shared fair record: X^m on qa, Z^m on qb.
function fXZ(qa::AbstractQubit, qb::AbstractQubit)
    m = Bool(QBool(0.5))
    cases(m) do; not!(qa) end
    cases(m) do; not!(dual(qb)) end
    discard!(m)
    return (qa, qb)
end

@testset "L1 — Consuming Observation (DM record token)" begin
    # Ruling D: DM `Bool(q)` / `Int(x)` return a token, NOT a scalar throw.
    density(2) do _
        m = Bool(QBool(0.5))
        @test m isa ClassicalBit
        @test width(m) == 1
    end
    density(3) do _
        w = Int(QInt{3}(5))
        @test w isa ClassicalWord{3}
        @test width(w) == 3
    end
    # ...but the QUANTUM handle is still affine-consumed (§4.5): every later
    # quantum use fails before state mutation (the measured wire is a record,
    # not an ordinary quantum handle — design §6).
    @test_throws Exception density(1) do _; qq = QBool(0.5); Bool(qq); Bool(qq) end
    @test_throws Exception density(1) do _; qq = QBool(0.5); Bool(qq); not!(qq) end
    @test_throws Exception density(2) do _; x = QInt{2}(1); Int(x); Int(x) end
    # Eager is unchanged: casts still return scalars (the trajectory contract).
    @test eager(1) do _; Bool(QBool(true)) end === true
    @test eager(2) do _; Int(QInt{2}(3)) end == 3
end

@testset "L2 — Instrument Sum (F5): exact DM cases = Σᵢ 𝓔ᵢ(𝓜ᵢ(ρ))" begin
    # m fair; X^m on a fresh |0⟩. The channel on b is Σ_m ½ X^m = ½(|0⟩⟨0|+|1⟩⟨1|),
    # deterministically (one DM run, not a sampled trajectory).
    ρb = density(3) do ctx
        m = Bool(QBool(0.5)); b = QBool(false)
        cases(m) do; not!(b) end
        discard!(m)
        _ptrace_keep(density_matrix(ctx), (q(ctx, b.wire),), 3)
    end
    @test ρb ≈ ComplexF64[0.5 0; 0 0.5]
    @test tr(ρb) ≈ 1                     # a channel (trace-preserving), not a subnormalized branch
    # And it is DETERMINISTIC — two runs of the exact channel agree exactly
    # (a trajectory would differ shot to shot).
    ρb2 = density(3) do ctx
        m = Bool(QBool(0.5)); b = QBool(false)
        cases(m) do; not!(b) end; discard!(m)
        _ptrace_keep(density_matrix(ctx), (q(ctx, b.wire),), 3)
    end
    @test ρb ≈ ρb2
end

@testset "L4 — cases-exact Choi (F5): Choi(teleport) ≈ Choi(id), one run, Z-sensitive" begin
    # Deterministic ONE-RUN DM Choi on the COHERENT Bell probe (Z-sensitive via the
    # off-diagonals): both cases arms provably evolve, Born-weighted, and the
    # corrections recover the identity channel exactly.
    Jid = choi(identity_channel, 1)
    Jtel = choi(teleport_tok, 1)
    @test Jtel ≈ Jid
    @test !(Jtel ≈ Diagonal(diag(Jtel)))    # genuinely coherent (off-diagonals present) — not a wm28-blind diagonal
    @test tr(Jtel) ≈ 1
end

@testset "L5 — Repeated-token correlation (F6), the MANDATORY PHASE FORM" begin
    # PHASE FORM (design §8 orchestrator correction): a shared fair record drives
    # X^m on wire a and Z^m on wire b (b half of the harness's entangled probe).
    # The composite Choi must show the CORRELATED X⊗Z record — ½(J(I)+J(X⊗Z)) —
    # NOT the product of the marginal channels. The Z-branch is visible only
    # coherently: a POPULATION-only probe (or applying X^m to both wires) is blind
    # to it, exactly the wm28 class this test exists to catch.
    J = _choi2(fXZ; cap = 6)
    Xm = ComplexF64[0 1; 1 0]; Zm = ComplexF64[1 0; 0 -1]; I2m = ComplexF64[1 0; 0 1]
    Jcorr = 0.5 * (analytic_choi2(kron(I2m, I2m)) + analytic_choi2(kron(Xm, Zm)))
    @test J ≈ Jcorr                                     # the correlated X⊗Z record
    # NOT the product of marginals (independent X-dephasing ⊗ Z-dephasing):
    Jprod = 0.25 * (analytic_choi2(kron(I2m, I2m)) + analytic_choi2(kron(Xm, I2m)) +
                    analytic_choi2(kron(I2m, Zm)) + analytic_choi2(kron(Xm, Zm)))
    @test !(J ≈ Jprod)
    # The phase-form Choi carries off-diagonal coherence a population probe cannot
    # read — the reason the population form (X^m on both) would be blind here.
    @test !(J ≈ Diagonal(diag(J)))
end

@testset "L5-population-consistency — X^m on both wires is CORRELATED but Z-blind" begin
    # The population (X⊗X) fixture IS correlated too — but it is the readout basis
    # that discriminates: this is the fixture the design warns is INSUFFICIENT as
    # the L5 witness (a Z-error/pinch hides on Z-populations). We pin its Choi to
    # ½(J(I)+J(X⊗X)) so the phase-form test above is the load-bearing one.
    function fXX(qa, qb)
        m = Bool(QBool(0.5)); cases(m) do; not!(qa) end; cases(m) do; not!(qb) end
        discard!(m); return (qa, qb)
    end
    J = _choi2(fXX; cap = 6)
    Xm = ComplexF64[0 1; 1 0]; I2m = ComplexF64[1 0; 0 1]
    @test J ≈ 0.5 * (analytic_choi2(kron(I2m, I2m)) + analytic_choi2(kron(Xm, Xm)))
end

@testset "L6 — Derived-token correlation (F6): n = !m ⇒ m,n anticorrelated" begin
    # A classical SSA op creates NO new stochastic record: `m` and `!m` share the
    # one base record wire, so branches on them are PERFECTLY anticorrelated.
    ρ = density(3) do ctx
        m = Bool(QBool(0.5)); n = !m
        a = QBool(false); b = QBool(false)
        cases(m) do; not!(a) end
        cases(n) do; not!(b) end
        discard!(m)
        _ptrace_keep(density_matrix(ctx), (q(ctx, a.wire), q(ctx, b.wire)), 3)
    end
    # anticorrelated: ½(|01⟩⟨01| + |10⟩⟨10|)
    @test real.(diag(ρ)) ≈ [0.0, 0.5, 0.5, 0.0] atol = 1e-9
end

@testset "Copyable tokens (F6): reuse of a token is the SAME record, not a new measurement" begin
    # `s = m` copies the handle; both `cases` see the same outcome ⇒ CORRELATED
    # (½(|00⟩⟨00|+|11⟩⟨11|)), NOT the ¼-over-4 independent mixture two separate
    # measurements would give.
    ρ = density(3) do ctx
        m = Bool(QBool(0.5)); s = m
        a = QBool(false); b = QBool(false)
        cases(m) do; not!(a) end
        cases(s) do; not!(b) end
        discard!(m)
        _ptrace_keep(density_matrix(ctx), (q(ctx, a.wire), q(ctx, b.wire)), 3)
    end
    @test real.(diag(ρ)) ≈ [0.5, 0.0, 0.0, 0.5] atol = 1e-9
    # tokens are NOT affine — copying and reusing throws nothing, mints no measurement.
    density(1) do _
        m = Bool(QBool(0.5)); s = m
        @test s isa ClassicalBit
        @test s.wires == m.wires        # same record
    end
end

@testset "L7 — immediate summation of the record while a token is LIVE is forbidden" begin
    # The correlation-destroying bug (design §2.2/§9.2): summing (tracing) the
    # record BEFORE the token is dead turns correlated feed-forward into
    # independent feed-forward. Our executor never sums between `cases` (only at
    # region exit / `discard!`), so the copyable test above is correlated. Here we
    # show the guard: summing early (an explicit `discard!` mid-stream) and then
    # reusing the token is a LOUD error — the record is gone (its wire retired).
    @test_throws Exception density(3) do ctx
        m = Bool(QBool(0.5)); a = QBool(false); b = QBool(false)
        cases(m) do; not!(a) end
        discard!(m)                     # sum the record too early — while `m` is still used below
        cases(m) do; not!(b) end        # ← reuse after summation: loud (record wire not live)
    end
end

@testset "L8/L10 — Branch-join port-signature (F6): leaked scratch / consumed port" begin
    # Every arm must end with the identical live-quantum port signature. A
    # branch-local register that escapes the join (leaked scratch) is a loud join
    # error under the DM executor.
    @test_throws Exception density(3) do ctx
        m = Bool(QBool(0.5))
        cases(m) do; QBool(true) end    # allocates a fresh live wire, never traced in-arm
        discard!(m)
    end
    # An arm consuming a pre-existing port (here via a nested measurement) is
    # caught — under DM by guardrail 1 (measurement under the control stack is
    # forbidden), the DM manifestation of a partial-consumption join (L9).
    @test_throws Exception density(3) do ctx
        m = Bool(QBool(0.5)); r = QBool(0.5)
        cases(m) do; Bool(r) end        # measurement under the cases control stack → guardrail 1
        discard!(m)
    end
end

@testset "L11 — Host-Boolean rejection (F4): `if token` / `&&` are Julia's native TypeError" begin
    # We do NOT and cannot intercept these — only the descriptive token type name
    # surfaces (design §4.1/§9.0). No Sturm-dispatched exception is expected.
    @test_throws TypeError density(1) do _; m = Bool(QBool(0.5)); m && true end
    @test_throws TypeError density(1) do _; m = Bool(QBool(0.5)); m || true end
    @test_throws TypeError density(1) do _; m = Bool(QBool(0.5)); if m; 1 else 2 end end
end

@testset "L12 — Reject branch/index positions (F4): descriptive Sturm errors where we own the method" begin
    @test_throws ArgumentError density(1) do _; m = Bool(QBool(0.5)); [1, 2][m] end
    @test_throws ArgumentError density(1) do _; m = Bool(QBool(0.5)); for _ in m; end end
    @test_throws ArgumentError density(1) do _; m = Bool(QBool(0.5)); convert(Bool, m) end
    @test_throws ArgumentError density(2) do _; w = Int(QInt{2}(1)); convert(Int, w) end
    # a word indexed by a TOKEN (dynamic index) is forbidden; the static build-time
    # slice `w[i::Integer]` is the T2 bit-extract (tested in the SSA testset).
    @test_throws ArgumentError density(3) do _; w = Int(QInt{2}(1)); m = Bool(QBool(0.5)); w[m] end
    # two RUNTIME words through a non-whitelisted op → descriptive error.
    @test_throws ArgumentError density(4) do _
        u = Int(QInt{2}(1)); v = Int(QInt{2}(1)); u * v
    end
end

@testset "L13 — cases IR follows the WRITTEN fan-in, not the word domain" begin
    # Wide feed-forward is a per-bit static loop (K=1 each), never a 2^W branch.
    # A per-bit conditioned circuit builds and its DM channel matches the reference.
    ρ = density(6) do ctx
        x = QInt{3}(0); superpose!(x); w = Int(x)
        outs = ntuple(_ -> QBool(false), 3)
        for j in 1:3
            @cases w[j] begin                  # static build-time slice → K=1 selector
                not!(outs[j])
            end
        end
        discard!(w)
        _ptrace_keep(density_matrix(ctx),
                     (q(ctx, outs[1].wire), q(ctx, outs[2].wire), q(ctx, outs[3].wire)), 6)
    end
    # each out mirrors one uniform bit ⇒ the reduced state is I/8 (uniform over 8).
    @test real.(diag(ρ)) ≈ fill(1 / 8, 8) atol = 1e-9
    # A selector past the fan-in cap is a LOUD error (never a silent 2^K blowup).
    @test_throws Exception density(20) do ctx
        x = QInt{17}(0); w = Int(x); cases(w == 0) do; nothing end
    end
end

@testset "T2 — the whitelisted finite classical SSA (bit + word), realised through cases" begin
    # Bit algebra: m ⊻ n branch. Build a small truth check via the derived record.
    ρ = density(3) do ctx
        m = Bool(QBool(0.5)); a = QBool(false)
        cases(m ⊻ true) do; not!(a) end        # ¬m
        discard!(m)
        _ptrace_keep(density_matrix(ctx), (q(ctx, a.wire),), 3)
    end
    @test real.(diag(ρ)) ≈ [0.5, 0.5] atol = 1e-9
    # Word: modular +const, compare-against-constant, static slice.
    density(2) do _
        w = Int(QInt{2}(1))
        @test (w + 1) isa ClassicalWord{2}
        @test (w == 1) isa ClassicalBit
        @test (w < 2) isa ClassicalBit
        @test w[1] isa ClassicalBit               # static build-time slice (MSB)
        @test (w * 3) isa ClassicalWord{2}        # constant multiply
        @test (w >> 1) isa ClassicalWord{2}       # constant shift
    end
    # Explicit width changes only (never implicit).
    density(2) do _
        w = Int(QInt{2}(1))
        @test zext(w, Val(4)) isa ClassicalWord{4}
        @test truncate_word(w, Val(1)) isa ClassicalWord{1}
    end
    # +const wraps mod 2^W in the DM branch: word (uniform 0..3) +1 == 0 fires w.p. 1/4 (word was 3).
    ρw = density(5) do ctx
        x = QInt{2}(0); superpose!(x); w = Int(x); a = QBool(false)
        cases((w + 1) == 0) do; not!(a) end       # (w+1) mod 4 == 0 ⇔ w == 3
        discard!(w)
        _ptrace_keep(density_matrix(ctx), (q(ctx, a.wire),), 5)
    end
    @test real(ρw[2, 2]) ≈ 0.25 atol = 1e-9
end

@testset "T3 — select / total ClassicalTable lookup (bounded multiplexer)" begin
    # select(bit, 2, 1) → a word; a multiway cases picks the arm.
    ρ = density(4) do ctx
        m = Bool(QBool(0.5)); sel = select(m, 2, 1)
        a = QBool(false); b = QBool(false)
        @cases sel begin
            1 => not!(a)
            2 => not!(b)
            _ => nothing
        end
        discard!(m)
        _ptrace_keep(density_matrix(ctx), (q(ctx, a.wire), q(ctx, b.wire)), 4)
    end
    @test real(ρ[3, 3]) ≈ 0.5 atol = 1e-9        # a fires on false→1
    @test real(ρ[2, 2]) ≈ 0.5 atol = 1e-9        # b fires on true→2
    # L15 — table totality: an incomplete raw-vector table (no default) is rejected.
    @test_throws ArgumentError density(2) do _
        w = Int(QInt{2}(0)); select(w, [5, 6])   # length 2 < domain 4, no default
    end
    density(2) do _
        w = Int(QInt{2}(0))
        @test select(w, [5, 6, 7, 8]) isa ClassicalWord           # total raw table OK
        @test select(w, ClassicalTable([9]; default = 0)) isa ClassicalWord  # partial + default OK
    end
end

@testset "F30 / L20 — cases takes a token, never a raw register; banned under `when`" begin
    # A bare quantum register selector is rejected (measurement must be spelled).
    @test_throws ArgumentError eager(1) do _; cases(QBool(0.5)) do; nothing end end
    @test_throws ArgumentError density(1) do _; cases(QBool(0.5)) do; nothing end end
    # `@cases Bool(q)` works (Ruling D idiom).
    @test eager(1) do _
        hit = Ref(false); @cases Bool(QBool(true)) begin (hit[] = true) end; hit[]
    end
    # measurement / cases under `when` → guardrail 1 (measurement under coherent
    # control is unrepresentable, §3.5).
    @test_throws Exception density(2) do ctx
        a = QBool(0.5); b = QBool(false)
        when(a) do; cases(Bool(b)) do; not!(a) end end
    end
end

@testset "shots — the trajectory / shot HOF over Eager (design §3.3)" begin
    # N scalar-outcome trajectories; a fair bit averages ≈ 0.5.
    outs = shots(1; N = 2000, rng = MersenneTwister(0x5107)) do ctx
        Bool(QBool(0.5))
    end
    @test length(outs) == 2000
    @test all(x -> x isa Bool, outs)
    @test abs(sum(outs) / length(outs) - 0.5) < 3 * sqrt(0.25 / 2000)
    # inside a shot, ordinary host `if` on the scalar outcome works (Eager contract).
    ones = shots(2; N = 500, rng = MersenneTwister(7)) do ctx
        m = Bool(QBool(0.5))
        b = QBool(false)
        m && not!(b)                    # host `if`/`&&` — legal on an Eager scalar
        Bool(b)
    end
    @test abs(sum(ones) / length(ones) - 0.5) < 3 * sqrt(0.25 / 500)
    @test_throws ArgumentError shots(1; N = 0) do _; Bool(QBool(0.5)) end
end
