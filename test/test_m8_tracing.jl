# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# Sturm.jl M8 law tests, PART 7 — TRACING half (bead Sturm.jl-szx1), design gates
# `docs/design/m8-i4ri-classical-control-design.md` (§2.4 IR record shapes, §2.3
# join-typing, §13 trichotomy + canonical Tracing passes) and
# `docs/design/m8-5hr7-unitary-block-design.md` (§2.1 no-state certificate, §3.4
# pass battery). The `TracingContext` is the COMPILER: it executes nothing and
# materialises the program into a `ChannelDAG`. These laws:
#
#   • MATERIALIZE       — allocations/apply/scope-exit/measure/cases → the typed
#                         effect nodes (AllocN/ApplyN/TraceN/MeasureN/CasesN);
#                         a barrier-free traced program CERTIFIES and the §4.2
#                         unitary-pass laws hold on it.
#   • TOKENS            — Bool(q)/Int(x) return WIRE tokens (Ruling D, C=Tracing);
#                         T2/T3 build tokens (generic over the context).
#   • JOIN              — trace-time join-typing (leaked scratch / consumed port).
#   • PREFLIGHT-LINT    — Ruling D §14: a non-portable token use is RECORDED and
#                         throws, pointing at `cases` (the listing form).
#   • STREAM-MATERIALIZED — streaming (DM) ≡ materialised (trace→replay) at the
#                         Choi level, on a Z-SENSITIVE measured+corrected teleport.
#   • DEFER / DEAD-RECORD — the canonical Tracing channel passes, Choi-preserving.
#
# Channel-level verification is Choi (`choi`/`_ptrace_keep`, INCLUDED earlier in
# runtests.jl); the materialise half executes a traced DAG via the DM `_replay_dm!`
# interpreter. Teleport probes the COHERENT Bell state (Z-sensitive) — never a
# Z-basis-only marginal (the wm28 lesson).

using Test
using LinearAlgebra
using Sturm
using Sturm: trace, TracingContext, trace_nonportable, density, density_matrix,
    apply!, allocate!, q, X, Z, H, ctrl, not!, dual, _adopt_qbool, _replay_dm!,
    ClassicalBit, ClassicalWord, select, width, zext,
    ChannelDAG, ApplyN, AllocN, TraceN, MeasureN, CasesN, has_barrier, is_barrier,
    certify, UnitaryBlock, denoted_matrix, apply_pass,
    Fuse1qPass, ViewFusionPass, ReassocPass, FuseUnitaryRunsPass,
    DeferMeasurementPass, DeadRecordEliminationPass

# Phase-blind Choi of a 1q unitary (the §3.4 harness helper; ctrl promotes phase).
function _choiU1(U::AbstractMatrix)
    d = size(U, 1)
    Ω = zeros(ComplexF64, d * d)
    for i in 0:(d - 1); Ω[i * d + i + 1] = 1 / sqrt(d); end
    v = kron(Matrix{ComplexF64}(U), Matrix{ComplexF64}(I, d, d)) * Ω
    return v * v'
end

# --- The Z-sensitive teleport-class fixture (context-generic: DM or Tracing) --
function teleport_tok(ψ)
    ctx = ψ.ctx
    a = QBool(false); c = QBool(false)
    apply!(ctx, H, (a.wire,)); apply!(ctx, ctrl(X), (a.wire, c.wire))   # Bell(a,c)
    apply!(ctx, ctrl(X), (ψ.wire, a.wire)); apply!(ctx, H, (ψ.wire,))    # entangle ψ,a
    m2 = Bool(_adopt_qbool(ctx, a.wire))
    m1 = Bool(ψ)
    cases(m2) do; not!(c) end               # X correction off the a-record
    cases(m1) do; not!(dual(c)) end          # Z correction off the ψ-record
    return c
end

# Replay a traced DAG as a 1-in/1-out channel, for the Choi harness.
_replay_channel(dag) = function (qin)
    outs = _replay_dm!(qin.ctx, dag, [qin.wire])
    return _adopt_qbool(qin.ctx, outs[1])
end

@testset "M8 part 7 — Tracing: materialize, tokens, join, defer, dead-record" begin

    # ===================================================================== #
    #  MATERIALIZE — the program becomes typed effect nodes                  #
    # ===================================================================== #

    @testset "M8.TRACE.MATERIALIZE-NODES (alloc/apply/measure/cases → effect nodes)" begin
        # A barrier-free unitary program → only ApplyN (no state, no Orkan).
        g = trace(1) do q; not!(q); not!(dual(q)); q end       # X then Z on one wire
        @test all(n -> n isa ApplyN, g.nodes)
        @test !has_barrier(g)
        @test length(g.qin) == 1 && length(g.qout) == 1 && isempty(g.cout)

        # Allocation + scope-exit trace → AllocN + TraceN (a dropped local).
        g2 = trace(1) do q; a = QBool(false); not!(a); not!(a); q end   # a allocated, dropped
        @test count(n -> n isa AllocN, g2.nodes) == 1
        @test count(n -> n isa TraceN, g2.nodes) == 1                    # scope-exit trace of `a`

        # Measurement → MeasureN (barrier); cases → CasesN (barrier).
        g3 = trace(1) do q; m = Bool(q); cases(m) do; nothing end; q end
        @test count(n -> n isa MeasureN, g3.nodes) == 1
        @test count(n -> n isa CasesN, g3.nodes) == 1
        @test has_barrier(g3)
    end

    @testset "M8.TRACE.NO-ORKAN (the compiler allocates no state / makes no FFI)" begin
        # A TracingContext with capacity 0 traces an arbitrarily wide program: no
        # Orkan slot allocator is ever reached (allocate! records an AllocN).
        g = trace(1) do q
            xs = ntuple(_ -> QBool(false), 8)           # 8 ancillas — no capacity limit
            for x in xs; not!(x); not!(x); end
            q
        end
        @test count(n -> n isa AllocN, g.nodes) == 8
        # teardown frees nothing — trace returns cleanly with no state_t.
        @test g isa ChannelDAG
    end

    @testset "M8.TRACE.CERTIFY-AND-PASS-LAWS (barrier-free segment certifies; §4.2 laws hold)" begin
        # Trace a barrier-free program, certify it to a UnitaryBlock, and assert the
        # §4.2 representative + ctrl-wrapped Choi laws hold under the shipped passes.
        g = trace(1) do q; not!(q); not!(dual(q)); q end   # X; Z
        v = certify(g)
        @test v isa UnitaryBlock{1}
        for P in (Fuse1qPass(), ViewFusionPass(), ReassocPass())
            w = apply_pass(P, v)
            @test w isa UnitaryBlock
            @test denoted_matrix(w) ≈ denoted_matrix(v)                       # representative (phase-inclusive)
            @test _choiU1(denoted_matrix(ctrl(w))) ≈ _choiU1(denoted_matrix(ctrl(v)))  # ctrl-wrapped Choi
        end
        # Fuse1q really fires: X;Z → one node.
        @test length(apply_pass(Fuse1qPass(), v).body.nodes) == 1

        # FuseUnitaryRuns (channel pass) partitions a traced DAG at its barrier.
        gb = trace(1) do q; not!(q); not!(dual(q)); m = Bool(q); nothing end   # X;Z | MEASURE
        gb2 = apply_pass(FuseUnitaryRunsPass(), gb)
        @test count(is_barrier, gb2.nodes) == 1
        @test count(n -> n isa ApplyN, gb2.nodes) == 1                        # the run fused before the barrier
        @test gb2.nodes[end] isa MeasureN                                      # barrier stays put
    end

    # ===================================================================== #
    #  TOKENS under Tracing (Ruling D, C = TracingContext)                   #
    # ===================================================================== #

    @testset "M8.TRACE.TOKENS (Bool/Int return wire tokens; T2/T3 build tokens)" begin
        # The cast returns a token, and the quantum handle is affine-consumed.
        trace(1) do q
            m = Bool(q)
            @test m isa ClassicalBit{TracingContext}
            @test width(m) == 1
            n = !m                                        # T2 derivation (generic evaluator)
            @test n isa ClassicalBit{TracingContext}
            @test n.wires == m.wires                      # shares the one record wire
            s = select(m, 2, 1)                           # T3 select
            @test s isa ClassicalWord{2,TracingContext}
            nothing
        end
        # A word measurement → ClassicalWord{W} record token; T2 word ops build tokens.
        trace(0) do
            w = Int(QInt{3}(0))
            @test w isa ClassicalWord{3,TracingContext}
            @test (w + 1) isa ClassicalWord{3}
            @test (w == 0) isa ClassicalBit
            @test w[1] isa ClassicalBit
            @test zext(w, Val(5)) isa ClassicalWord{5}
            nothing
        end
        # The quantum handle dies at the cast — a second measurement is loud.
        @test_throws Exception trace(1) do q; Bool(q); Bool(q) end
    end

    # ===================================================================== #
    #  JOIN-typing (design §2.3): leaked scratch / consumed port            #
    # ===================================================================== #

    @testset "M8.TRACE.JOIN (leaked scratch / branch-consumed port are loud)" begin
        # L10 — a branch-local register that escapes the join (leaked scratch).
        @test_throws ErrorException trace(1) do q
            m = Bool(q)
            cases(m) do; QBool(true) end       # allocates a fresh live wire, never traced in-arm
            q
        end
        # L9 — a pre-existing port consumed in only one arm (a nested measurement).
        @test_throws ErrorException trace(2) do q, r
            m = Bool(q)
            cases(m) do; Bool(r) end           # consumes r inside the arm
            q
        end
        # A clean arm (a unitary correction that preserves the signature) is fine.
        g = trace(2) do q, r
            m = Bool(q)
            cases(m) do; not!(r) end
            r
        end
        @test count(n -> n isa CasesN, g.nodes) == 1
    end

    # ===================================================================== #
    #  PREFLIGHT-LINT (Ruling D §14 / PRD §3.8 traceable-subset)            #
    # ===================================================================== #

    @testset "M8.TRACE.PREFLIGHT-LINT (non-portable token use recorded + thrown)" begin
        # A token in a Sturm-owned forbidden position is RECORDED into the lint
        # accumulator and then throws a descriptive error pointing at `cases`.
        ctx = TracingContext()
        m = Sturm.with(Sturm.CURRENT_CONTEXT => ctx) do
            Sturm._enter_region!(ctx)
            Bool(_adopt_qbool(ctx, Sturm._trace_input!(ctx)))
        end
        @test isempty(trace_nonportable(ctx))
        @test_throws ArgumentError [1, 2][m]                     # array-index-by-token
        @test trace_nonportable(ctx) == ["an array index (`arr[token]`)"]
        @test_throws ArgumentError convert(Bool, m)              # host coercion
        @test length(trace_nonportable(ctx)) == 2
        @test occursin("convert", last(trace_nonportable(ctx)))
        # host `if`/`&&` are Julia-native TypeErrors (uncatchable) — still loud, but
        # NOT recorded by the lint (only the descriptive type name surfaces, §9.0).
        @test_throws TypeError (m && true)
    end

    # ===================================================================== #
    #  STREAM ≡ MATERIALIZED (the round-trip; Z-sensitive teleport)         #
    # ===================================================================== #

    @testset "M8.TRACE.STREAM-MATERIALIZED (streaming DM ≡ materialised Tracing, Choi)" begin
        Jid = choi(identity_channel, 1)
        Jstream = choi(teleport_tok, 1)                          # streamed DM channel
        tdag = trace(teleport_tok, 1)                            # materialised IR
        @test count(n -> n isa MeasureN, tdag.nodes) == 2
        @test count(n -> n isa CasesN, tdag.nodes) == 2
        Jmat = choi(_replay_channel(tdag), 1)                    # replayed IR channel
        @test Jstream ≈ Jid                                      # teleport is the identity channel
        @test Jmat ≈ Jstream                                     # streaming ≡ materialised (the law)
        @test Jmat ≈ Jid
        @test !(Jmat ≈ Diagonal(diag(Jmat)))                    # genuinely coherent (Z-sensitive), not wm28-blind
        @test tr(Jmat) ≈ 1
    end

    # ===================================================================== #
    #  DEFERRED MEASUREMENT (the canonical no-MCM Tracing pass)             #
    # ===================================================================== #

    @testset "M8.TRACE.DEFER (measure+cases → coherent ctrl + terminal measure, Choi)" begin
        Jid = choi(identity_channel, 1)
        tdag = trace(teleport_tok, 1)
        ddag = apply_pass(DeferMeasurementPass(), tdag)
        # The rewrite removed the CasesN and moved both MeasureNs to the END; the
        # corrections became coherent ctrl (off the still-unmeasured records).
        @test count(n -> n isa CasesN, ddag.nodes) == 0
        @test count(n -> n isa MeasureN, ddag.nodes) == 2
        @test ddag.nodes[end] isa MeasureN && ddag.nodes[end-1] isa MeasureN   # terminal readout
        @test all(n -> n isa MeasureN, ddag.nodes[end-1:end])
        # Licence = Choi equality (defined in DM, tested by DM replay): defer ≡ id.
        Jdef = choi(_replay_channel(ddag), 1)
        @test Jdef ≈ Jid
        @test Jdef ≈ choi(_replay_channel(tdag), 1)                              # pre ≡ post

        # Identity on a DAG with no measure+cases pattern (a bare X; measure).
        g = trace(1) do q; not!(q); m = Bool(q); nothing end
        g2 = apply_pass(DeferMeasurementPass(), g)
        @test length(g2.nodes) == length(g.nodes)                               # unchanged
    end

    # ===================================================================== #
    #  DEAD-RECORD ELIMINATION (record never consumed ⇒ collapse to trace)  #
    # ===================================================================== #

    @testset "M8.TRACE.DEAD-RECORD (unused record MeasureN → TraceN, Choi)" begin
        # `a` measured but its record never consumed nor returned ⇒ pinch-then-drop
        # = trace: the MeasureN collapses to a TraceN.
        g = trace(1) do q; a = QBool(false); Bool(a); q end
        @test count(n -> n isa MeasureN, g.nodes) == 1
        @test isempty(g.cout)                                                    # the record does not escape
        g2 = apply_pass(DeadRecordEliminationPass(), g)
        @test count(n -> n isa MeasureN, g2.nodes) == 0
        @test count(n -> n isa TraceN, g2.nodes) == 1                            # collapsed to trace
        # Choi-preserving (Tr∘pinch = Tr): replay pre ≡ post.
        @test choi(_replay_channel(g), 1) ≈ choi(_replay_channel(g2), 1)
        # A record CONSUMED by a cases is NOT eliminated (it is live).
        g3 = trace(1) do q; m = Bool(q); cases(m) do; nothing end; q end
        g3e = apply_pass(DeadRecordEliminationPass(), g3)
        @test count(n -> n isa MeasureN, g3e.nodes) == 1                          # kept
    end
end
