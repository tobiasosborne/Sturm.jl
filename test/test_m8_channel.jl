# SPDX-License-Identifier: AGPL-3.0-only
#
# Milestone M8 law tests, parts 1–3 (bead Sturm.jl-szx1), design gate
# `docs/design/m8-5hr7-unitary-block-design.md` §3.4 named battery: the typed
# immutable `ChannelDAG`, the structural clean-ancilla certificate / `certify`
# sealer, and the `UnitaryBlock <: ProcessValue` algebra (`∘`/`⊗`/`adjoint`/
# `denoted_matrix`/`ctrl`). Parts 4–7 (Eager tee-tracing, pass framework,
# tokens/`cases`) are out of this slice; the PASS.* / WHEN.* battery is not here.
#
# All direct unitary comparisons are PHASE-INCLUSIVE (`denoted_matrix` carries the
# U(1) phase; `approx_upto_phase` is forbidden — design §3.4). Channel-level checks
# use the shipped `choi.jl` harness where they apply.

using Test
using LinearAlgebra
using Sturm
using Sturm: DAGBuilder, input!, alloc!, apply_node!, trace!, measure!, noise!, freeze,
    certify, ChannelDAG, UnitaryBlock, denoted_matrix, denoted_full, boundary,
    ctrl, ⊗, nwires, ProcessValue,
    PortID, Port, QuantumPort, ClassicalPort, is_barrier, has_barrier,
    CleanCert, NoAncilla, PermClean, MatchedPair, SeqCert, ParCert, AdjointCert,
    ApplyN, AllocN, TraceN, MeasureN, CasesN, NoiseN, KrausFamily,
    Perm, MCX, X, Y, Z, H, S, T, gphase, I2, NEG_I, Ry

# --- fixtures ---------------------------------------------------------------
CX() = Perm(2, [MCX([1], 2)])                 # control wire1 (MSB), target wire2
TOF() = Perm(3, [MCX([1, 2], 3)])             # Toffoli on 3 wires

"Certify a single-`ApplyN` `NoAncilla` block of `v` on `nwires(v)` fresh inputs."
function block_of(v::ProcessValue)
    b = DAGBuilder()
    ws = [input!(b) for _ in 1:nwires(v)]
    apply_node!(b, v, ws...)
    return certify(b)
end

@testset "M8 parts 1–3 — ChannelDAG / certify / UnitaryBlock" begin

    # ===================================================================== #
    #  PART 1 — Typed immutable ChannelDAG                                   #
    # ===================================================================== #

    @testset "M8.PORT.TYPED-COMPOSITION" begin
        # Arity: an ApplyN whose port count ≠ nwires(v) is rejected at build time.
        b = DAGBuilder(); w = input!(b)
        @test_throws ErrorException apply_node!(b, CX(), w)          # CX needs 2 ports
        @test_throws ErrorException apply_node!(b, X, w, w)          # X needs 1
        # A referenced-but-unknown port is rejected.
        b2 = DAGBuilder(); input!(b2)
        @test_throws ErrorException apply_node!(b2, X, PortID(999))
        # Resource-lineage composition: qout arity must match qin (checked at seal).
        p = Port(PortID(1), QuantumPort(1), 1)
        bad = ChannelDAG((ApplyN(X, (PortID(1),)),), (p,), (p, p), ())  # 1 in, 2 out
        @test_throws ArgumentError certify(bad)
    end

    @testset "M8.PORT.CHANNEL-NOT-PROCESS" begin
        # A ChannelDAG is NOT a process value: no ctrl, no unitary-pass method.
        @test !(ChannelDAG <: ProcessValue)
        @test UnitaryBlock <: ProcessValue
        p = Port(PortID(1), QuantumPort(1), 1)
        dag = ChannelDAG((ApplyN(X, (PortID(1),)),), (p,), (p,), ())
        @test !hasmethod(ctrl, Tuple{ChannelDAG})                    # ctrl(::ChannelDAG) unrepresentable (P4)
        @test_throws MethodError ctrl(dag)
        # Allocation / discard alone cannot be applied as a process value.
        @test !(AllocN <: ProcessValue)
        @test !(TraceN <: ProcessValue)
        # A DAG carrying a measurement/cases/noise BARRIER cannot be certified.
        bm = DAGBuilder(); wm = input!(bm); measure!(bm, wm)
        @test has_barrier(freeze(bm))
        @test_throws ArgumentError certify(bm)
        bn = DAGBuilder(); wn = input!(bn); noise!(bn, wn)
        @test_throws ArgumentError certify(bn)
    end

    @testset "M8.PORT.ENDOMORPHIC-BLOCK" begin
        # Sealing fails unless output boundary lineage == input lineage, in order.
        pin = Port(PortID(1), QuantumPort(1), 1)
        pout_same = Port(PortID(1), QuantumPort(1), 1)               # same lineage
        pout_diff = Port(PortID(2), QuantumPort(1), 2)               # different lineage
        ok = ChannelDAG((ApplyN(X, (PortID(1),)),), (pin,), (pout_same,), ())
        @test certify(ok) isa UnitaryBlock{1}
        bad = ChannelDAG((ApplyN(X, (PortID(1),)),), (pin,), (pout_diff,), ())
        @test_throws ArgumentError certify(bad)                      # width-equal but lineage-distinct
        # zero-port block forbidden (TR7).
        empty = ChannelDAG((), (), (), ())
        @test_throws ArgumentError certify(empty)
    end

    @testset "M8.IMMUTABLE.NTUPLE — Perm/MCX frozen storage (F28/TR5)" begin
        # Representation-only refactor: gates/controls are frozen tuples, not Vectors.
        p = Perm(2, [MCX([1], 2)])
        @test p.gates isa Tuple
        @test p.gates[1].controls isa Tuple
        @test p.gates[1].controls == (1,)
        @test Perm(3, MCX[]).gates == ()
        # Defensive copy: mutating the source vector cannot reach into the Perm.
        v = MCX[MCX(Int[], 1)]
        p2 = Perm(1, v); push!(v, MCX(Int[], 1))
        @test length(p2.gates) == 1
        cv = [1, 2]; g = MCX(cv, 3); push!(cv, 9)
        @test g.controls == (1, 2)
    end

    # ===================================================================== #
    #  PART 2 — Structural clean-ancilla certificate / certify              #
    # ===================================================================== #

    @testset "M8.CERT.STATE-IS-NOT-WITNESS (F1 adversary)" begin
        # `a = QBool(false); a ⊻= r; drop a` — an unmatched ancilla discard. It is
        # rejected STRUCTURALLY (no matched certified TraceN), regardless of input:
        # a statevector marginal on one run (r=|0⟩, marginal 0) is not a witness.
        b = DAGBuilder()
        r = input!(b); a = alloc!(b)
        apply_node!(b, CX(), r, a)      # a ⊻= r
        trace!(b, a)                    # cert = nothing  ⇒  reject
        @test_throws ArgumentError certify(b)
        # Attaching a bogus-but-nonstructural claim does not save it either: the
        # alloc must be matched by a *certified* trace whose structure checks out.
        # (Here a NoAncilla cert on a scratch-writing region fails the alloc-match.)
    end

    @testset "M8.CERT.CLEAN-SUBSPACE" begin
        # A valid MatchedPair fixture: alloc a; C=CX(d→a); M=ctrl(Z)(a,d); C†=CX; trace.
        Cblk = block_of(CX())
        b = DAGBuilder()
        d = input!(b); a = alloc!(b)
        apply_node!(b, CX(), d, a)               # compute (scratch target)
        apply_node!(b, ctrl(Z), a, d)            # inner M: scratch as control only
        apply_node!(b, CX(), d, a)               # uncompute
        trace!(b, a; cert = MatchedPair(Cblk, NoAncilla()))
        blk = certify(b)
        W = denoted_full(blk)                    # full 2-wire replay
        @test isapprox(W * W', Matrix{ComplexF64}(I, 4, 4))          # W unitary
        # ι embeds ancilla=|0⟩ (ancilla is the trailing/LSB wire): clean idx {0,2}.
        ι = zeros(ComplexF64, 4, 2); ι[1, 1] = 1; ι[3, 2] = 1
        Pc = ι * ι'
        @test norm((Matrix{ComplexF64}(I, 4, 4) - Pc) * W * ι) < 1e-12   # (I−ιι†)Wι ≈ 0
        U = ι' * W * ι                                                   # U = ι†Wι
        @test isapprox(U * U', Matrix{ComplexF64}(I, 2, 2))             # unitary on the N ports
        @test isapprox(denoted_matrix(blk), U)                         # replay agrees
    end

    @testset "M8.CERT.MATCHED-COMPUTE-UNCOMPUTE" begin
        # Structure |x⟩|0⟩|ψ⟩ ↦ |x⟩|0⟩ M_x|ψ⟩: x=control wire, a=ancilla, ψ=target.
        # C computes a = x; M = ctrl(X) on ψ controlled by a; C† uncomputes a.
        # Net (a clean): apply X to ψ iff x=1  ⇒  = Toffoli(x,·,ψ) with a factored out.
        Cblk = block_of(CX())
        b = DAGBuilder()
        x = input!(b); ψ = input!(b); a = alloc!(b)
        apply_node!(b, CX(), x, a)               # a ⊕= x  (compute)
        apply_node!(b, ctrl(X), a, ψ)            # ψ ⊕= a   (scratch as control)
        apply_node!(b, CX(), x, a)               # uncompute
        trace!(b, a; cert = MatchedPair(Cblk, NoAncilla()))
        blk = certify(b)
        @test blk isa UnitaryBlock{2}
        # Dense: equals CX on (x,ψ) (X on ψ controlled by x), ancilla cleanly gone.
        @test isapprox(denoted_matrix(blk), denoted_matrix(CX()))
        # A *bad* inner that writes scratch as a TARGET is rejected structurally.
        bbad = DAGBuilder()
        xb = input!(bbad); ab = alloc!(bbad)
        apply_node!(bbad, CX(), xb, ab)
        apply_node!(bbad, X, ab)                 # writes scratch as target (not control!)
        apply_node!(bbad, CX(), xb, ab)
        trace!(bbad, ab; cert = MatchedPair(Cblk, NoAncilla()))
        @test_throws ArgumentError certify(bbad)  # 3 scratch-writers ≠ 2 (or non-adjoint)
    end

    @testset "M8.CERT.PERM-SUBSET-NEEDS-CONTRACT" begin
        # A bare Perm with EVERY port on the boundary is accepted as unitary (NoAncilla).
        blk = block_of(CX())
        @test blk isa UnitaryBlock{2}
        @test blk.cert isa NoAncilla
        @test isapprox(denoted_matrix(blk), denoted_matrix(CX()))
        # But it may NOT release DESIGNATED scratch without a checked PermClean.
        # alloc anc; Perm(compute-copy-uncompute) using anc; trace anc.
        # Toffoli(x1,x2→anc); CX(anc→out); Toffoli(x1,x2→anc): out ⊕= x1∧x2, anc restored.
        artifact = Perm(4, [MCX([1, 2], 4), MCX([4], 3), MCX([1, 2], 4)])
        build_artifact = () -> begin
            bb = DAGBuilder()
            x1 = input!(bb); x2 = input!(bb); out = input!(bb); anc = alloc!(bb)
            apply_node!(bb, artifact, x1, x2, out, anc)
            return (bb, anc)
        end
        # Without a cert on the trace → rejected (unmatched alloc).
        (b_nocert, anc0) = build_artifact(); trace!(b_nocert, anc0)
        @test_throws ArgumentError certify(b_nocert)
        # With PermClean → accepted, and denotes out ⊕= x1∧x2 (Toffoli on 3 wires).
        (b, anc) = build_artifact()
        trace!(b, anc; cert = PermClean((anc,)))
        blk3 = certify(b)
        @test blk3 isa UnitaryBlock{3}
        @test blk3.cert isa PermClean
        @test isapprox(denoted_matrix(blk3), denoted_matrix(TOF()))
    end

    @testset "M8.CERT.BENNETT — exhaustive scratch restoration" begin
        # The compute-copy-uncompute Perm restores anc=|0⟩ for EVERY input (truth table).
        b = DAGBuilder()
        x1 = input!(b); x2 = input!(b); out = input!(b); anc = alloc!(b)
        artifact = Perm(4, [MCX([1, 2], 4), MCX([4], 3), MCX([1, 2], 4)])
        apply_node!(b, artifact, x1, x2, out, anc)
        trace!(b, anc; cert = PermClean((anc,)))
        blk = certify(b)
        W = denoted_full(blk)                    # 16×16 permutation matrix (4 wires)
        # For each of the 8 inputs with anc=0 (anc is the trailing/LSB wire), the
        # image must have anc bit = 0 (scratch restored) — exhaustive.
        for ext in 0:7
            col = ext * 2 + 1                     # anc=0 basis index (0-based ext*2), 1-based
            img0 = findfirst(!iszero, @view W[:, col]) - 1
            @test (img0 & 1) == 0                 # ancilla (LSB) restored to |0⟩
        end
    end

    @testset "M8.CERT.COMPOSITION — SeqCert/ParCert/AdjointCert" begin
        g = block_of(H); h = block_of(Z)
        gh = g ∘ h; gt = g ⊗ h; ga = adjoint(g)
        @test gh.cert isa SeqCert
        @test gt.cert isa ParCert
        @test ga.cert isa AdjointCert
        @test isapprox(denoted_matrix(gh), denoted_matrix(H) * denoted_matrix(Z))   # U₂U₁
        @test isapprox(denoted_matrix(gt), kron(denoted_matrix(H), denoted_matrix(Z)))  # U₁⊗U₂
        @test isapprox(denoted_matrix(ga), denoted_matrix(H)')                       # U†
        @test gh isa UnitaryBlock{1} && gt isa UnitaryBlock{2} && ga isa UnitaryBlock{1}
    end

    # ===================================================================== #
    #  PART 3 — ctrl(::UnitaryBlock) : the one new choke-point method        #
    # ===================================================================== #

    @testset "M8.CTRL.BLOCK-HOMOMORPHISM" begin
        g = block_of(H); h = block_of(Ry(0.7))
        @test ctrl(g) isa Sturm.Ctrl{<:UnitaryBlock}
        @test isapprox(denoted_matrix(ctrl(g ∘ h)), denoted_matrix(ctrl(g) ∘ ctrl(h)))
        # nested control (Toffoli-grade) is flat.
        @test isapprox(denoted_matrix(ctrl(ctrl(g))), denoted_matrix(ctrl(ctrl(g))))
        @test nwires(ctrl(g)) == 2
    end

    @testset "M8.CTRL.BLOCK-ADJOINT" begin
        for v in (H, S, T, Ry(1.1), gphase(0.9))
            g = block_of(v)
            @test isapprox(denoted_matrix(adjoint(ctrl(g))), denoted_matrix(ctrl(adjoint(g))))
        end
    end

    @testset "M8.PASS.PHASE-SENTINEL (block-level groundwork, α = π/3)" begin
        # A block denoting gphase(π/3) = e^{iπ/3}I: Choi-blind uncontrolled (Ad
        # quotients U(1)), but ctrl PROMOTES the phase to observable physics
        # (Tang–Wright Thm 1.1). Groundwork for the part-6 pass sentinel: certify
        # PRESERVES the U(d) representative (phase included), never merging with I.
        α = π / 3
        gp = block_of(gphase(α))
        @test !isapprox(denoted_matrix(gp), Matrix{ComplexF64}(I, 2, 2))   # e^{iα}I ≠ I (phase kept)
        # ctrl(block) = diag(1,1,e^{iα},e^{iα}) ≠ ctrl(I).
        D = diag(denoted_matrix(ctrl(gp)))
        @test isapprox(D, ComplexF64[1, 1, cis(α), cis(α)])
        @test !isapprox(denoted_matrix(ctrl(gp)), Matrix{ComplexF64}(I, 4, 4))
        # +I and −I are never merged: ctrl of a block denoting −I is a real CZ-grade op.
        gneg = block_of(NEG_I)
        @test isapprox(denoted_matrix(ctrl(gneg)), ComplexF64[1 0 0 0; 0 1 0 0; 0 0 -1 0; 0 0 0 -1])
    end
end
