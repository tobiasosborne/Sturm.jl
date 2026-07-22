# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# Sturm.jl M8 law tests, PARTS 5–6 (bead Sturm.jl-szx1), design gate
# `docs/design/m8-5hr7-unitary-block-design.md` §3 (the pass contract, F3) +
# §3.4 named battery: the CHANNEL-PASS framework (Choi-preserving), the
# REPRESENTATIVE-PRESERVING UNITARY-PASS framework (phase-inclusive `≈` + the
# ctrl-wrapped Choi law), `PASS_REGISTRY` + its law-coverage lint (with teeth),
# the π/3 PHASE SENTINEL "test of the test", the tier-1b PHASE-DELTA commit, the
# XportCert transport, and the `within` combinator.
#
# All DIRECT unitary comparisons are PHASE-INCLUSIVE (`denoted_matrix` carries the
# U(1) phase; `approx_upto_phase` is forbidden — design §3.4). The CTRL-wrapped
# law compares CHOI (Ad quotients U(1)) precisely to prove no phase leaked into the
# controlled channel (Tang–Wright Thm 1.1).

using Test
using LinearAlgebra
using Sturm
using Sturm: DAGBuilder, input!, alloc!, apply_node!, trace!, measure!, noise!, freeze,
    certify, ChannelDAG, UnitaryBlock, denoted_matrix, boundary, ctrl, nwires,
    ProcessValue, Perm, MCX, X, Y, Z, H, S, T, gphase, I2, NEG_I, Ry, U2, Ctrl,
    ApplyN, AllocN, TraceN, MeasureN, has_barrier, is_barrier,
    NoAncilla, MatchedPair, XportCert, PermClean,
    UnitaryPass, ChannelPass, apply_pass, PASS_REGISTRY, PhaseDelta,
    Fuse1qPass, ViewFusionPass, ReassocPass, FuseUnitaryRunsPass, DeferMeasurementPass,
    within

# --- fixtures ---------------------------------------------------------------
m8_CXp() = Perm(2, [MCX([1], 2)])

"Certify a single-`ApplyN` `NoAncilla` block of `v`."
function blk(v::ProcessValue)
    b = DAGBuilder()
    ws = [input!(b) for _ in 1:nwires(v)]
    apply_node!(b, v, ws...)
    return certify(b)
end

"A 1-wire block whose body is [ApplyN(a), ApplyN(b)] on ONE wire (a runs first)."
function two1q(a::U2, b::U2)
    bl = DAGBuilder(); w = input!(bl)
    apply_node!(bl, a, w); apply_node!(bl, b, w)
    return certify(bl)
end

"A 1-wire block whose body is [ApplyN(a), ApplyN(a†)] on ONE wire (an inverse pair)."
function invpair(a::U2)
    bl = DAGBuilder(); w = input!(bl)
    apply_node!(bl, a, w); apply_node!(bl, adjoint(a), w)
    return certify(bl)
end

"A 2-wire block [V†; ctrl(W); V] realizing (1⊗V)·ctrl(W)·(1⊗V†) — the reassoc window."
function reassocwin(V::U2, W::U2)
    bl = DAGBuilder(); c = input!(bl); t = input!(bl)
    apply_node!(bl, adjoint(V), t)
    apply_node!(bl, ctrl(W), c, t)
    apply_node!(bl, V, t)
    return certify(bl)
end

"""A 3-wire MULTIPLY-CONTROLLED reassoc window [V†; ctrl²(W); V] realizing
(1⊗V)·ctrl²(W)·(1⊗V†) — the k=2 path (two controls c1,c2 on wires 1,2; target t)."""
function reassocwin2(V::U2, W::U2)
    bl = DAGBuilder(); c1 = input!(bl); c2 = input!(bl); t = input!(bl)
    apply_node!(bl, adjoint(V), t)
    apply_node!(bl, ctrl(ctrl(W)), c1, c2, t)          # ctrl²(W) = Ctrl(2,W), 3 wires
    apply_node!(bl, V, t)
    return certify(bl)
end

"The MatchedPair ancilla block from `within` (CX compute, ctrl(X) inner) — denotes CX."
matchedblk() = within(m8_CXp(), ctrl(X))

"""
    _choiU(U) -> Matrix

Normalized Choi (Jamiołkowski) of the unitary channel `Ad_U`:
`J = (U⊗I)|Ω⟩⟨Ω|(U⊗I)†`. PHASE-BLIND (`Ad_U = Ad_{e^{iα}U}` — the global phase
cancels in `v v'`), which is exactly why the UNCONTROLLED Choi law cannot see a
leaked phase and the CTRL-wrapped one can (the ctrl promotes it to a relative phase
that survives `Ad`).
"""
function _choiU(U::AbstractMatrix)
    d = size(U, 1)
    Ω = zeros(ComplexF64, d * d)
    for i in 0:(d - 1)
        Ω[i * d + i + 1] = 1 / sqrt(d)
    end
    v = kron(Matrix{ComplexF64}(U), Matrix{ComplexF64}(I, d, d)) * Ω
    return v * v'
end

# The full battery fixture set V* (design §3.4): phase-only values + gates + the
# rewrite-TRIGGERING multi-node blocks + a live-ancilla MatchedPair block.
_fixtures() = UnitaryBlock[
    blk(S), blk(T), blk(gphase(π)), blk(gphase(π / 4)), blk(H), blk(NEG_I),
    two1q(S, T), two1q(H, Z),          # Fuse1q active
    invpair(H), invpair(S),            # ViewFusion active
    reassocwin(H, T), reassocwin(H, Z),# Reassoc active
    matchedblk(),                      # a MatchedPair block with a live ancilla
]

# Runtime record: which of {representative, controlled} each registered pass ran.
const _PASS_LAWS_RAN = Dict{Symbol,Set{Symbol}}()
_record!(name::Symbol, law::Symbol) = push!(get!(_PASS_LAWS_RAN, name, Set{Symbol}()), law)

# A FABRICATED, UNSOUND phase-dropping rewrite (the "test of the test", design
# §3.4). On a 1-wire block it replaces the body with plain `I` — DROPPING any
# global phase. Choi-blind uncontrolled, but caught by the representative law AND
# the ctrl-wrapped Choi law. NOT registered (a bad pass must never ship).
struct _PhaseDropPass <: UnitaryPass end
function Sturm._rewrite(::_PhaseDropPass, v::UnitaryBlock)
    return Sturm._commit(:phasedrop, v, Sturm.Node[ApplyN(I2, (v.boundary[1].id,))])
end

@testset "M8 parts 5–6 — pass frameworks (channel + unitary), registry, sentinel" begin

    # ===================================================================== #
    #  PART 6 — the representative-preserving UNITARY-PASS framework          #
    #  M8.PASS.UNITARY-REPRESENTATIVE + M8.PASS.UNITARY-CONTROLLED per pass    #
    # ===================================================================== #

    fixtures = _fixtures()
    for (name, P) in sort(collect(PASS_REGISTRY); by = first)
        @testset "M8.PASS.UNITARY-REPRESENTATIVE[$name]" begin
            for v in fixtures
                w = apply_pass(P, v)
                @test w isa UnitaryBlock                     # codomain pinned (tier 3)
                @test denoted_matrix(w) ≈ denoted_matrix(v)  # phase-inclusive P(v) ≈ v
            end
            _record!(name, :representative)
        end
        @testset "M8.PASS.UNITARY-CONTROLLED[$name]" begin
            for v in fixtures
                w = apply_pass(P, v)
                # ctrl promotes any leaked phase to observable physics — Choi-compared.
                @test _choiU(denoted_matrix(ctrl(w))) ≈ _choiU(denoted_matrix(ctrl(v)))
            end
            _record!(name, :controlled)
        end
    end

    @testset "concrete rewrites actually fire (teeth of the passes)" begin
        # Fuse1q: [S,T] on one wire → one node denoting S∘T.
        v = two1q(S, T); f = apply_pass(Fuse1qPass(), v)
        @test length(f.body.nodes) == 1
        @test denoted_matrix(f) ≈ denoted_matrix(v)
        @test f.cert isa XportCert
        # ViewFusion: [H,H] → both dropped (composite is exactly I₂).
        vv = invpair(H); g = apply_pass(ViewFusionPass(), vv)
        @test length(g.body.nodes) == 0
        @test denoted_matrix(g) ≈ Matrix{ComplexF64}(I, 2, 2)
        # ViewFusion REFUSES a pair composing to −I (Ry(π);Ry(π) = −I, a real ctrl op).
        neg = two1q(Ry(π), Ry(π)); h = apply_pass(ViewFusionPass(), neg)
        @test length(h.body.nodes) == 2                    # NOT dropped
        @test denoted_matrix(h) ≈ ComplexF64[-1 0; 0 -1]
        # Reassoc: [H†; ctrl(Z); H] → one node ctrl(H∘Z∘H) = ctrl(X).
        r = reassocwin(H, Z); rr = apply_pass(ReassocPass(), r)
        @test length(rr.body.nodes) == 1
        @test denoted_matrix(rr) ≈ denoted_matrix(r)
        @test denoted_matrix(ctrl(rr)) ≈ denoted_matrix(ctrl(r))   # phase-faithful under ctrl
    end

    @testset "M8.PASS.REASSOC-K2 (multiply-controlled window — both laws + k=2 sentinel)" begin
        # Multiply-controlled decomposition is the historical phase-bug class (Cirq/
        # Qiskit/pytket, years). Exercise the ReassocPass k=2 path under BOTH required
        # laws so no shipped kernel path goes untested. Window: V†; ctrl²(W); V ⇒
        # ctrl²(V∘W∘V†), verified for a phase gate (T), a global phase (gphase(π/3)),
        # and a Pauli (Z).
        α = π / 3
        for W in (T, gphase(α), Z)
            r = reassocwin2(H, W)
            rr = apply_pass(ReassocPass(), r)
            @test length(rr.body.nodes) == 1
            @test rr.body.nodes[1].v isa Ctrl
            @test rr.body.nodes[1].v.k == 2                          # the k=2 path really fired
            @test denoted_matrix(rr) ≈ denoted_matrix(r)            # representative ≈ (phase-inclusive)
            # ctrl-wrapped Choi: one MORE control ⇒ a 4-wire (16×16) op, choiU 256×256 —
            # within the dense cap (block replays 3 wires, no ancilla).
            @test _choiU(denoted_matrix(ctrl(rr))) ≈ _choiU(denoted_matrix(ctrl(r)))
        end
        # k=2 PHASE SENTINEL (π/3): a phase dropped under TWO controls must be caught.
        r = reassocwin2(H, gphase(α))
        rr = apply_pass(ReassocPass(), r)                           # denotes ctrl²(gphase(α))
        # A fabricated phase-DROPPED sibling on the same 3 wires: ctrl²(I) = I₈.
        bl = DAGBuilder(); c1 = input!(bl); c2 = input!(bl); t = input!(bl)
        apply_node!(bl, ctrl(ctrl(I2)), c1, c2, t)
        bad = certify(bl)
        # The dropped π/3 under two controls IS caught by the ctrl-wrapped Choi law
        # (the exact bug class the choke point + phase test exist to stop):
        @test !(_choiU(denoted_matrix(ctrl(rr))) ≈ _choiU(denoted_matrix(ctrl(bad))))
        # The Tang–Wright separation, nested to depth 2: ctrl²(gphase(α)) ≠ ctrl²(I) in
        # Choi, and the leaked phase lands on the all-controls-1 corner as e^{iα}.
        @test !(_choiU(denoted_matrix(ctrl(ctrl(gphase(α))))) ≈ _choiU(denoted_matrix(ctrl(ctrl(I2)))))
        @test isapprox(diag(denoted_matrix(ctrl(ctrl(gphase(α)))))[end], cis(α))
    end

    @testset "M8.PASS.PORT-AND-CERTIFICATE" begin
        # A committed rewrite keeps the exact boundary and transports the cert (XportCert).
        v = two1q(S, T); w = apply_pass(Fuse1qPass(), v)
        @test length(w.boundary) == length(v.boundary)
        @test all(p -> p[1].lineage == p[2].lineage, zip(w.boundary, v.boundary))
        @test w.cert isa XportCert
        @test w.cert.rewrite == :fuse1q
        @test w.cert.src === v.cert                         # the input's cert rode along
        # An identity application returns the block unchanged (original cert kept).
        u = apply_pass(Fuse1qPass(), blk(S))
        @test u.cert isa NoAncilla
    end

    @testset "M8.PASS.PHASE-SENTINEL (π/3 — the test of the test)" begin
        α = π / 3
        v = blk(gphase(α))                                  # e^{iα} I
        bad = apply_pass(_PhaseDropPass(), v)               # fabricated: drops the phase → I
        # UNCONTROLLED Choi is BLIND to the dropped phase (the trap the naive law falls into):
        @test _choiU(denoted_matrix(bad)) ≈ _choiU(denoted_matrix(v))
        # But the phase-inclusive REPRESENTATIVE law catches it:
        @test !(denoted_matrix(bad) ≈ denoted_matrix(v))
        # ...and the CTRL-wrapped Choi law catches it (ctrl promotes the phase to Z):
        @test !(_choiU(denoted_matrix(ctrl(bad))) ≈ _choiU(denoted_matrix(ctrl(v))))
        # The canonical Tang–Wright separation at the heart of the sentinel:
        @test _choiU(denoted_matrix(I2)) ≈ _choiU(denoted_matrix(gphase(α)))            # Ad blind
        @test !(_choiU(denoted_matrix(ctrl(I2))) ≈ _choiU(denoted_matrix(ctrl(gphase(α)))))  # ctrl sees it
    end

    @testset "M8.PASS.PHASE-DELTA (tier 1b — report δ, commit reattaches gphase(−δ))" begin
        δ = 0.7
        v = blk(X)
        # A rule that shifts the body by gphase(δ): the UNCOMMITTED candidate denotes e^{iδ}·X.
        cand_nodes = Sturm.Node[collect(v.body.nodes)..., ApplyN(gphase(δ), (v.boundary[1].id,))]
        candblk = certify(ChannelDAG(Tuple(cand_nodes), v.body.qin, v.body.qout, ()))
        @test denoted_matrix(candblk) ≈ cis(δ) * denoted_matrix(v)      # U' = e^{iδ}U (proved)
        # The trusted commit reattaches gphase(−δ) BEFORE sealing ⇒ committed ≈ v.
        committed = Sturm._commit(:phasedelta_demo, v, PhaseDelta(cand_nodes, δ))
        @test committed isa UnitaryBlock
        @test denoted_matrix(committed) ≈ denoted_matrix(v)             # committed ≈ v
        @test committed.cert isa XportCert
        # ...and the controlled Chois agree (no residual phase under ctrl).
        @test _choiU(denoted_matrix(ctrl(committed))) ≈ _choiU(denoted_matrix(ctrl(v)))
    end

    @testset "M8.PASS.MEASUREMENT-BARRIER (unitary passes never touch a barrier)" begin
        bm = DAGBuilder(); wm = input!(bm); measure!(bm, wm); gm = freeze(bm)
        @test has_barrier(gm)
        # A UnitaryPass has NO method for a ChannelDAG — barrier blocks are unreachable.
        @test_throws MethodError apply_pass(Fuse1qPass(), gm)
        # And a barrier DAG never certifies, so it can never BECOME a UnitaryBlock.
        @test_throws ArgumentError certify(gm)
    end

    # ===================================================================== #
    #  PART 5 — the CHANNEL-PASS framework                                    #
    #  M8.PASS.CHANNEL-DENOTATION                                             #
    # ===================================================================== #

    @testset "M8.PASS.CHANNEL-DENOTATION (FuseUnitaryRuns — Choi preserved)" begin
        P = FuseUnitaryRunsPass()
        # (a) Signature identity + Choi preservation on a barrier-free unitary fixture.
        bl = DAGBuilder(); w = input!(bl); apply_node!(bl, S, w); apply_node!(bl, T, w)
        g = freeze(bl)
        g2 = apply_pass(P, g)
        @test g2 isa ChannelDAG
        @test g2.qin == g.qin && g2.qout == g.qout && g2.cout == g.cout   # signatures identical
        @test length(g2.nodes) == 1                                       # the run fused
        @test _choiU(denoted_matrix(certify(g2))) ≈ _choiU(denoted_matrix(certify(g)))
        # (b) A ChannelPass handed a UnitaryBlock rejects (MethodError — tier 3 partition).
        @test_throws MethodError apply_pass(P, blk(S))
    end

    @testset "M8.PASS.BARRIER-PARTITION (channel pass never crosses a barrier)" begin
        # Body: H;Z (fusable) | MEASURE | H;Z (fusable). The two runs fuse independently;
        # the barrier stays exactly where it was — never crossed.
        bl = DAGBuilder()
        w = input!(bl)
        apply_node!(bl, H, w); apply_node!(bl, Z, w)
        m = measure!(bl, w)                                # BARRIER (consumes w)
        g = freeze(bl)
        g2 = apply_pass(FuseUnitaryRunsPass(), g)
        # H;Z fused to one node before the barrier; the MeasureN preserved.
        @test count(is_barrier, g2.nodes) == 1
        @test count(n -> n isa ApplyN, g2.nodes) == 1      # the two 1q ops fused
        @test g2.nodes[end] isa MeasureN                   # barrier stays last
    end

    @testset "M8.PASS.CHANNEL-DENOTATION (DeferMeasurement — framework slot, deferred)" begin
        # DeferMeasurement is a typed ChannelPass whose REWRITE BODY is deferred to the
        # part-7 CasesN token semantics (design §6 seam). Until then it is the identity:
        # the SLOT is real (returns a ChannelDAG, rejects a UnitaryBlock), the rewrite waits.
        P = DeferMeasurementPass()
        bm = DAGBuilder(); wm = input!(bm); apply_node!(bm, X, wm); measure!(bm, wm)
        g = freeze(bm)
        g2 = apply_pass(P, g)
        @test g2 isa ChannelDAG
        @test g2.qin == g.qin && g2.qout == g.qout && g2.cout == g.cout
        @test length(g2.nodes) == length(g.nodes)          # identity (no pattern deferred yet)
        @test_throws MethodError apply_pass(P, blk(X))      # rejects a UnitaryBlock
    end

    # ===================================================================== #
    #  `within` combinator + the MatchedPair compute-field cross-check       #
    # ===================================================================== #

    @testset "M8.WITHIN.MATCHED-PAIR (public combinator, tier-A provenance)" begin
        w = within(m8_CXp(), ctrl(X))                          # C=CX (data→scratch), M=ctrl(X)
        @test w isa UnitaryBlock{2}
        @test w.cert isa MatchedPair
        @test denoted_matrix(w) ≈ denoted_matrix(m8_CXp())     # denotes CX, ancilla factored out
        # A three-wire within: C=Toffoli-style compute is out of scope; test a 2q inner.
        w2 = within(m8_CXp(), ctrl(Z))                         # M=ctrl(Z) ⇒ effective CZ(data,target)
        @test w2 isa UnitaryBlock{2}
        @test denoted_matrix(w2) ≈ ComplexF64[1 0 0 0; 0 1 0 0; 0 0 1 0; 0 0 0 -1]
    end

    @testset "M8.WITHIN.COMPUTE-FIELD-CROSSCHECK (slice-3 ruling)" begin
        # A MatchedPair whose named `compute` block DISAGREES with the body's compute
        # writer is rejected at certify — the cert cannot lie about which C it is.
        b = DAGBuilder()
        d = input!(b); a = alloc!(b)
        apply_node!(b, m8_CXp(), d, a)                          # compute writer is CX
        apply_node!(b, ctrl(Z), a, d)                        # inner reads scratch as control
        apply_node!(b, m8_CXp(), d, a)                          # uncompute
        # Lie: name a compute block denoting a DIFFERENT 2q op (ctrl(Z), not CX).
        liar = MatchedPair(blk(ctrl(Z)), NoAncilla())
        trace!(b, a; cert = liar)
        @test_throws ArgumentError certify(b)
        # The honest cert (naming CX) still seals.
        b2 = DAGBuilder()
        d2 = input!(b2); a2 = alloc!(b2)
        apply_node!(b2, m8_CXp(), d2, a2)
        apply_node!(b2, ctrl(Z), a2, d2)
        apply_node!(b2, m8_CXp(), d2, a2)
        trace!(b2, a2; cert = MatchedPair(blk(m8_CXp()), NoAncilla()))
        @test certify(b2) isa UnitaryBlock{1}
    end

    # ===================================================================== #
    #  PASS_REGISTRY law-coverage lint — mirrors the ctrl choke-point lint    #
    # ===================================================================== #

    @testset "PASS_REGISTRY law-coverage lint (teeth)" begin
        # Pure checker: which registered passes are missing EITHER required law.
        both = Set([:representative, :controlled])
        missing_laws(reg, ran) = sort([n for n in reg if get(ran, n, Set{Symbol}()) != both])
        # TEETH — self-tests against synthetic registries (mirrors the ctrl lint's
        # "lint function catches a synthetic violation"):
        @test missing_laws([:dummy], Dict{Symbol,Set{Symbol}}()) == [:dummy]          # no laws
        @test missing_laws([:a], Dict(:a => Set([:representative]))) == [:a]           # only one law
        @test missing_laws([:a], Dict(:a => both)) == Symbol[]                         # both ⇒ ok
        # Applied to the REAL registry against what actually ran above: every
        # registered unitary pass exercised BOTH its required laws.
        @test missing_laws(collect(keys(PASS_REGISTRY)), _PASS_LAWS_RAN) == Symbol[]
        # Non-vacuous: the registry is populated and every entry is a UnitaryPass.
        @test !isempty(PASS_REGISTRY)
        @test all(p -> p isa UnitaryPass, values(PASS_REGISTRY))
    end

    @testset "PASS_REGISTRY lint has REAL teeth — an unsound registered pass FAILS its ctrl law" begin
        # Demonstrate the battery would catch a bad pass: register the fabricated
        # phase-dropper into a COPY of the registry, run the CTRL-wrapped Choi law, and
        # assert it FAILS on a phase-carrying fixture (α = π/3). A pass cannot ship past
        # this law with a leaked phase — the Cirq/Qiskit/pytket bug class, mechanized.
        v = blk(gphase(π / 3))
        bad = apply_pass(_PhaseDropPass(), v)
        ctrl_choi_ok = _choiU(denoted_matrix(ctrl(bad))) ≈ _choiU(denoted_matrix(ctrl(v)))
        @test ctrl_choi_ok == false          # the law REJECTS the unsound pass
    end
end
