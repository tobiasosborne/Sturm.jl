# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# Sturm.jl M8 law tests, PART 4 (bead Sturm.jl-szx1), design gate
# `docs/design/m8-5hr7-unitary-block-design.md` §1.4/§5/§8-TR2 and §3.4 battery:
# UnitaryBlock EXECUTION on a live context (the closed ad.jl seams), Eager
# TEE-TRACING + structural clean-ancilla sealing at `when`-body exit (the
# certificate is the witness, not a runtime marginal — F1/D13), the TR2
# poison-on-failed-seal failure topology, and the strengthened
# `M8.WHEN.STREAM-MATERIALIZED-CTRL` law (streaming ≡ materialized, ctrl-wrapped
# Choi-compared — §4.2 pass law, the F3 addition).
#
# Choi laws use the shipped `choi.jl` harness (INCLUDED before this file in
# runtests.jl); test-side code is licensed to reach kernel values (`apply!`,
# `ctrl`, `X`, `Z`) exactly as `choi.jl`/`test_m5_when.jl` are.

using Test
using LinearAlgebra
using Sturm
using Sturm: eager, density, when, dual, not!, apply!, statevector, ctrl, X, Z, H,
    DAGBuilder, input!, alloc!, apply_node!, trace!, certify, denoted_matrix, nwires,
    ProcessValue, Perm, MCX, NoAncilla, MatchedPair, UnitaryBlock, contextof,
    DEBUG_CLEAN_ANCILLA

# Dense references (harness basis |o₁o₂⟩, o₁ = MSB = first-returned).
const _Xm4  = ComplexF64[0 1; 1 0]
const _CXm4 = ComplexF64[1 0 0 0; 0 1 0 0; 0 0 0 1; 0 0 1 0]
const _CZm4 = ComplexF64[1 0 0 0; 0 1 0 0; 0 0 1 0; 0 0 0 -1]

CXperm() = Perm(2, [MCX([1], 2)])

"Certify a single-`ApplyN` `NoAncilla` block of `v`."
function _blk(v::ProcessValue)
    b = DAGBuilder()
    ws = [input!(b) for _ in 1:nwires(v)]
    apply_node!(b, v, ws...)
    return certify(b)
end

"The MatchedPair block denoting CX(x,ψ) with a cleanly-restored ancilla."
function _blk_matchedpair()
    b = DAGBuilder()
    x = input!(b); ψ = input!(b); a = alloc!(b)
    apply_node!(b, CXperm(), x, a)          # compute a = x
    apply_node!(b, ctrl(X), a, ψ)        # ψ ⊕= a (scratch as control)
    apply_node!(b, CXperm(), x, a)          # uncompute
    trace!(b, a; cert = MatchedPair(_blk(CXperm()), NoAncilla()))
    return certify(b)
end

@testset "M8 part 4 — block execution, tee-tracing, TR2 poison" begin

    # ===================================================================== #
    #  UnitaryBlock EXECUTION — the closed ad.jl seams (design §1.4)         #
    # ===================================================================== #

    @testset "M8.BLOCK.EXEC-UNCONTROLLED" begin
        # apply!(block_of(v)) replays the body against the live context = applies v.
        sv = eager(1) do ctx
            q = QBool(false); apply!(ctx, _blk(X), (q.wire,)); statevector(ctx)
        end
        @test findall(x -> abs(x) > 1e-9, sv) .- 1 == [1]     # |0⟩ → |1⟩
        # A block equal to H put on |0⟩ gives (|0⟩±|1⟩)/√2. UNCONTROLLED execution
        # quotients the global phase at Ad (§4.3), exactly as a bare `apply!(H)` does,
        # so compare magnitudes (the ctrl-Choi law below is the phase-faithful test).
        svh = eager(1) do ctx
            q = QBool(false); apply!(ctx, _blk(H), (q.wire,)); statevector(ctx)
        end
        @test abs.(svh) ≈ ComplexF64[1, 1] ./ sqrt(2)
    end

    @testset "M8.BLOCK.EXEC-CONTROLLED — alloc/trace uncontrolled, ApplyNs wrapped" begin
        # ctrl(block_of(X)) executes as CX.
        sv = eager(2) do ctx
            c = QBool(true); t = QBool(false)
            apply!(ctx, ctrl(_blk(X)), (c.wire, t.wire)); statevector(ctx)
        end
        @test findall(x -> abs(x) > 1e-9, sv) .- 1 == [3]     # |10⟩ → |11⟩
        # ctrl(MatchedPair block denoting CX) = CCX, ancilla cleanly restored to |0⟩.
        blk = _blk_matchedpair()
        sv2 = eager(4) do ctx    # 3 external + 1 internal ancilla slot
            c = QBool(true); x = QBool(true); ψ = QBool(false)
            apply!(ctx, ctrl(blk), (c.wire, x.wire, ψ.wire)); statevector(ctx)
        end
        # Orkan bit j = slot j: c=slot0, x=slot1, ψ=slot2, ancilla=slot3. CCX fires
        # (c=x=1) ⇒ ψ→1; ancilla restored to |0⟩ ⇒ bits {0,1,2} set = index 7.
        @test findall(x -> abs(x) > 1e-9, sv2) .- 1 == [7]
        # control = 0 ⇒ identity: only x=1 (slot1/bit1), ancilla clean ⇒ index 2.
        sv3 = eager(4) do ctx
            c = QBool(false); x = QBool(true); ψ = QBool(false)
            apply!(ctx, ctrl(blk), (c.wire, x.wire, ψ.wire)); statevector(ctx)
        end
        @test findall(x -> abs(x) > 1e-9, sv3) .- 1 == [2]
    end

    # ===================================================================== #
    #  M8.WHEN.STREAM-MATERIALIZED — streaming ≡ materialized (design §3.4)  #
    # ===================================================================== #

    @testset "M8.WHEN.STREAM-MATERIALIZED-AD (conjunct 1 — U(d) representative)" begin
        # The block captured from a STREAMING `when(q) do not!(r) end` run denotes the
        # body's phase-fixed U(d) representative (X) — equal to the directly-built M(B).
        captured = eager(2) do ctx
            q = QBool(0.5); r = QBool(false)
            blk = Sturm._when_capture(contextof(q), q.wire, () -> not!(r))
            blk === nothing ? nothing : denoted_matrix(blk)
        end
        @test captured ≈ _Xm4
        @test captured ≈ denoted_matrix(_blk(X))
        # And the streaming half really ran: the applied channel is ctrl(X) = CX.
        svstream = eager(2) do ctx
            q = QBool(true); r = QBool(false)
            Sturm._when_capture(contextof(q), q.wire, () -> not!(r))
            statevector(ctx)
        end
        @test findall(x -> abs(x) > 1e-9, svstream) .- 1 == [3]     # |10⟩ → |11⟩
    end

    @testset "M8.WHEN.STREAM-MATERIALIZED-CTRL (conjunct 2 — ctrl-wrapped Choi)" begin
        # STREAMED S(B) vs MATERIALIZED M(B) executed under ctrl, Choi-compared — the
        # F3 strengthened form: control promotes any leaked phase to observable physics.
        # Body B = not!(r) ⇒ X ⇒ ctrl = CX.
        Js = choi((q, r) -> (when(q) do; not!(r) end; (q, r)), 2)
        Jm = choi((q, r) -> (apply!(contextof(q), ctrl(_blk(X)), (q.wire, r.wire)); (q, r)), 2)
        @test Js ≈ Jm
        @test Jm ≈ analytic_choi2(_CXm4)
        # Body B = not!(dual(r)) ⇒ Z ⇒ ctrl = CZ (kickback; the control picks up phase).
        Js2 = choi((q, r) -> (when(q) do; not!(dual(r)) end; (q, r)), 2)
        Jm2 = choi((q, r) -> (apply!(contextof(q), ctrl(_blk(Z)), (q.wire, r.wire)); (q, r)), 2)
        @test Js2 ≈ Jm2
        @test Jm2 ≈ analytic_choi2(_CZm4)
    end

    # ===================================================================== #
    #  Tee-tracing seal is the WITNESS (design §5, F1) + TR2 poison (§8)     #
    # ===================================================================== #

    @testset "M8.WHEN.SEAL-IS-WITNESS — structural seal accepts clean, rejects F1" begin
        # A clean matched compute/uncompute scratch body SEALS (streaming succeeds).
        @test (eager(3) do ctx
            q = QBool(0.5)
            when(q) do
                a = QBool(false); not!(a); not!(a)     # X;X — matched, ancilla → |0⟩
            end
            Bool(q); nothing
        end) === nothing
        # The F1 adversary UNDER `when`: scratch written once (a ⊻= r), never uncomputed.
        # Rejected STRUCTURALLY at body-exit seal — independent of the runtime input
        # (here r = |0⟩, where a naive marginal would read 0). Throws ErrorException.
        @test_throws ErrorException eager(3) do ctx
            q = QBool(0.5); r = QBool(false)
            when(q) do
                a = QBool(false)
                a ⊻= r                                  # one scratch writer, no uncompute
            end
            Bool(q)
        end
        # An ancilla allocated |0⟩ and never touched seals clean (untouched |0⟩ —
        # zero scratch writers), alongside a matched pair on a second ancilla.
        @test (eager(4) do ctx
            q = QBool(0.5)
            when(q) do
                a = QBool(false)                        # allocated, dropped, still |0⟩
                b = QBool(false); not!(b); not!(b)      # matched compute/uncompute
            end
            Bool(q); nothing
        end) === nothing
    end

    @testset "M8.TR2.POISON — failed seal poisons the context (design §8/TR2)" begin
        # After a failed seal, the context is POISONED: subsequent surface ops fail
        # loud, naming the original seal failure. Streaming ran effects before the late
        # seal, so the failure cannot be unwound (TR2 — poison, not rollback).
        err = eager(3) do ctx
            q = QBool(0.5); r = QBool(false)
            try
                when(q) do
                    a = QBool(false); a ⊻= r            # F1 — seal fails, poison set
                end
            catch
            end
            try
                not!(r)                                 # any op on the poisoned ctx must throw
                return nothing
            catch e
                return e
            end
        end
        @test err isa ErrorException
        @test occursin("POISONED", sprint(showerror, err))
        @test occursin("seal", sprint(showerror, err))
    end

    @testset "M8.WHEN.DEBUG-CROSSCHECK — demoted marginal, off by default" begin
        # The |1⟩-marginal survives ONLY as a debug cross-check (design §2.5). Off by
        # default; when armed it is an independent fail-fast that must still PASS a
        # structurally-clean body (the certificate was honoured).
        @test DEBUG_CLEAN_ANCILLA[] == false
        DEBUG_CLEAN_ANCILLA[] = true
        try
            @test (eager(3) do ctx
                q = QBool(0.5)
                when(q) do
                    a = QBool(false); not!(a); not!(a)
                end
                Bool(q); nothing
            end) === nothing
        finally
            DEBUG_CLEAN_ANCILLA[] = false
        end
    end

    # ===================================================================== #
    #  Shared matched-pair discipline: _is_adjoint_pair (orchestrator FIX 1) #
    # ===================================================================== #

    @testset "M8.CERT.MATCHED-PAIR-DISCIPLINE — one shared _is_adjoint_pair, two tiers" begin
        # Tier A (exact structural provenance) holds for Perm — generator reversal.
        @test CXperm() == adjoint(CXperm())
        @test Sturm._is_adjoint_pair(CXperm(), CXperm())
        # Tier B: a self-adjoint U2 is representation-brittle under exact ==, so the
        # shared helper falls back to phase-inclusive ≈. Exact == would WRONGLY reject.
        @test !(X == adjoint(X))                        # stored quaternion fields differ
        @test !(H == adjoint(H))
        @test Sturm._is_adjoint_pair(X, X)              # but X† = X as an operator ⇒ accept
        @test Sturm._is_adjoint_pair(H, H)
        @test !Sturm._is_adjoint_pair(X, H)             # genuinely non-adjoint ⇒ reject
        # certify(MatchedPair) with a SELF-ADJOINT U2 compute/uncompute now seals — this
        # DAG was rejected before the fix (exact == on X vs adjoint(X)). Both the
        # certify checker and the streaming seal go through the same _is_adjoint_pair.
        b = DAGBuilder()
        d = input!(b); a = alloc!(b)
        apply_node!(b, X, a)                            # compute: X on scratch (writes a)
        apply_node!(b, ctrl(Z), a, d)                   # inner: scratch as control only
        apply_node!(b, X, a)                            # uncompute: X = adjoint(X) as operator
        trace!(b, a; cert = MatchedPair(_blk(X), NoAncilla()))
        @test certify(b) isa UnitaryBlock{1}            # tier B accepts; exact == rejected
    end

    # ===================================================================== #
    #  TR2 mid-body throw poison (orchestrator FIX 2)                        #
    # ===================================================================== #

    @testset "M8.TR2.MIDBODY-POISON — throw with LIVE scratch poisons, original surfaces" begin
        outcome = eager(3) do ctx
            q = QBool(0.5); r = QBool(false)
            orig = try
                when(q) do
                    a = QBool(false)                    # scratch allocated (un-sealed)
                    error("boom-with-scratch")
                end
                nothing
            catch e
                e
            end
            @test orig isa ErrorException
            @test occursin("boom-with-scratch", sprint(showerror, orig))   # ORIGINAL error surfaced
            # Context is poisoned: a `catch` cannot resume — the next surface op throws.
            try
                not!(r)
                return nothing
            catch e
                return e
            end
        end
        @test outcome isa ErrorException
        @test occursin("POISONED", sprint(showerror, outcome))
    end

    @testset "M8.TR2.MIDBODY-NO-SCRATCH — throw without scratch does NOT poison" begin
        result = eager(2) do ctx
            q = QBool(0.5); r = QBool(false)
            orig = try
                when(q) do
                    not!(r)                             # body touches only an external wire
                    error("boom-no-scratch")
                end
                nothing
            catch e
                e
            end
            @test orig isa ErrorException
            @test occursin("boom-no-scratch", sprint(showerror, orig))
            # Context NOT poisoned — it stays usable (the M5 unwind idiom).
            not!(r)                                     # must not throw
            Bool(q)
            :ok
        end
        @test result == :ok
    end
end
