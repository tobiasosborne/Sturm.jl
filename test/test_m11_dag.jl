# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# Sturm.jl M11 (bead Sturm.jl-qmpo), design docs/design/m11-82su-synthesis.md
# ruling S28: channel-level ∘/⊗ on `ChannelDAG` + `channel_dag`. The relabel
# discipline is the whole game (risk R-c, wm28-class): both operands enter one
# fresh PortID/lineage namespace and the ∘ seam is ONE port. The NEGATIVE
# CONTROL — naive node concatenation with colliding PortIDs silently fuses
# unrelated wires — is demonstrated to produce the WRONG state, which is what
# makes the relabel test a real guard rather than a tautology.
# Requires test/choi.jl included first.

using Test
using LinearAlgebra
using Sturm
using Sturm: trace, _replay_dm!, _adopt_qbool, density, density_matrix,
    channel_dag, choi_matrix, bit_flip, same_channel, KrausFamily,
    ChannelDAG, ApplyN, AllocN, TraceN, MeasureN, CasesN, NoiseN,
    DAGBuilder, input!, alloc!, apply_node!, measure!, freeze, certify,
    UnitaryBlock, denoted_matrix, H, X, ctrl, ⊗, apply!

_replay_ch(dag) = function (qin)
    outs = _replay_dm!(qin.ctx, dag, [qin.wire])
    return _adopt_qbool(qin.ctx, outs[1])
end

const _Hm11 = ComplexF64[1 1; 1 -1] ./ sqrt(2)
const _Xm11 = ComplexF64[0 1; 1 0]

# Choi of a Kraus list, out = MSB (the harness convention).
function _choiK(ops)
    d = size(ops[1], 1)
    J = zeros(ComplexF64, d * d, d * d)
    for K in ops
        v = zeros(ComplexF64, d * d)
        for a in 1:d, b in 1:d
            v[(a - 1) * d + b] = K[a, b]
        end
        J .+= v * v'
    end
    return J ./ d
end

@testset "M11.DAG.COMPOSE-RELABEL" begin
    # Two INDEPENDENTLY traced DAGs — every trace() numbers its ports from 1,
    # so their PortIDs collide by construction. ∘ must relabel + seam.
    b = trace(q -> (apply!(Sturm.current_context(), H, (q.wire,)); q), 1)
    a = trace(q -> (apply!(Sturm.current_context(), X, (q.wire,)); q), 1)
    @test b.qin[1].id == a.qin[1].id                 # the collision is REAL
    comp = a ∘ b                                     # b first: X∘H... i.e. X·H
    @test length(comp.qin) == 1 && length(comp.qout) == 1
    J = choi(_replay_ch(comp), 1)
    @test J ≈ _choiK([_Xm11 * _Hm11]) atol = 1e-10
    # Arity mismatch is loud.
    t2 = channel_dag(bit_flip(0.1) ⊗ bit_flip(0.1), 2)
    @test_throws ArgumentError b ∘ t2
end

@testset "M11.DAG.SEAM-LINEAGE-CERTIFIES" begin
    # The seam identifies LINEAGE, so a composite of endomorphic unitary DAGs
    # still certifies (boundary lineage in order) — S28's load-bearing detail.
    b = trace(q -> (apply!(Sturm.current_context(), H, (q.wire,)); q), 1)
    a = trace(q -> (apply!(Sturm.current_context(), X, (q.wire,)); q), 1)
    blk = certify(a ∘ b)
    @test blk isa UnitaryBlock
    @test denoted_matrix(blk) ≈ _Xm11 * _Hm11 atol = 1e-10
end

@testset "M11.DAG.TENSOR-AND-NEGATIVE-CONTROL" begin
    # Proper ⊗ of two independently traced H-DAGs: both wires end in |+⟩.
    ha = trace(q -> (apply!(Sturm.current_context(), H, (q.wire,)); q), 1)
    hb = trace(q -> (apply!(Sturm.current_context(), H, (q.wire,)); q), 1)
    tp = ha ⊗ hb
    @test length(tp.qin) == 2
    allids = [p.id.id for p in (tp.qin..., tp.qout...)]
    @test length(unique(allids)) == length(unique([p.id.id for p in tp.qin]))
    density(2) do ctx
        u = QBool(false); v = QBool(false)
        _replay_dm!(ctx, tp, [u.wire, v.wire])
        ρ = density_matrix(ctx)
        for i in 1:4, j in 1:4
            @test real(ρ[i, j]) ≈ 0.25 atol = 1e-10   # |++⟩⟨++| — all entries ¼
        end
        nothing
    end
    # NEGATIVE CONTROL (the wm28-class guard): naive concatenation KEEPS the
    # colliding PortIDs — both H nodes land on ONE physical wire (H·H = I) and
    # the other wire is never touched: the state stays |00⟩, visibly wrong.
    naive = ChannelDAG(Tuple(vcat(collect(ha.nodes), collect(hb.nodes))),
                       (ha.qin..., hb.qin...), (ha.qout..., hb.qout...), ())
    density(2) do ctx
        u = QBool(false); v = QBool(false)
        _replay_dm!(ctx, naive, [u.wire, v.wire])
        ρ = density_matrix(ctx)
        @test real(ρ[1, 1]) ≈ 1.0 atol = 1e-10        # |00⟩ — the silent fusion
        nothing
    end
end

@testset "M11.DAG.CASES-BRANCH-REMAP" begin
    # A DAG whose CasesN carries nested branch DAGs (measure → correct is the
    # cq∘qc pinching channel: r = |m⟩) composed AFTER an H-DAG. The composite
    # channel is pinch ∘ Ad_H — Kraus {P₀H, P₁H} — Choi-checked. This is the
    # recursive-branch remap path (S28's hardest detail) executing end-to-end.
    pinchdag = trace(1) do q
        m = Bool(q)                       # MeasureN + token (consumes q)
        r = QBool(false)                  # fresh output wire
        @cases m begin
            not!(r)                       # CasesN with a nested branch DAG
        end
        r
    end
    @test any(n -> n isa CasesN, pinchdag.nodes)
    hdag = trace(q -> (apply!(Sturm.current_context(), H, (q.wire,)); q), 1)
    comp = pinchdag ∘ hdag
    J = choi(_replay_ch(comp), 1; cap = 5)
    P0 = ComplexF64[1 0; 0 0]; P1 = ComplexF64[0 0; 0 1]
    @test J ≈ _choiK([P0 * _Hm11, P1 * _Hm11]) atol = 1e-10
end

@testset "M11.DAG.COUT-UNION" begin
    # b measures its only input (record escapes as cout); a allocates a fresh
    # output from nothing. a∘b: 1 quantum in, 1 quantum out, 1 record out.
    bb = DAGBuilder(); w = input!(bb); measure!(bb, w)
    b = freeze(bb)
    @test length(b.cout) == 1 && isempty(b.qout)
    ab = DAGBuilder(); alloc!(ab)
    a = freeze(ab)
    @test isempty(a.qin) && length(a.qout) == 1
    comp = a ∘ b
    @test length(comp.qin) == 1
    @test length(comp.qout) == 1
    @test length(comp.cout) == 1
    density(2) do ctx
        u = QBool(0.5)
        outs = _replay_dm!(ctx, comp, [u.wire])
        @test length(outs) == 1                       # the fresh |0⟩ output
        nothing
    end
end

@testset "M11.DAG.CHANNEL-DAG-LIFT" begin
    # channel_dag lifts a value into a one-NoiseN DAG whose replay is the
    # native channel; arity is taken from the value, never assumed.
    fam = bit_flip(0.3)
    g = channel_dag(fam, 1)
    @test length(g.nodes) == 1 && g.nodes[1] isa NoiseN
    @test_throws ArgumentError channel_dag(fam, 2)
    J = choi(_replay_ch(g), 1)
    @test J ≈ choi_matrix(fam) atol = 1e-10
    # And it composes: bit_flip(p) ∘ bit_flip(q) at the DAG level.
    g2 = channel_dag(bit_flip(0.2), 1) ∘ g
    J2 = choi(_replay_ch(g2), 1)
    @test J2 ≈ choi_matrix(bit_flip(0.3 + 0.2 - 2 * 0.3 * 0.2)) atol = 1e-10
end
