# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# Sturm.jl M5 (bead Sturm.jl-o5yh): the law tests for `when` — streaming coherent
# control, its three §3.5 guardrails, the §3.9 clean-ancilla exit witness, and the
# deferred-teleport §7.1b acceptance gate. Each @testset is named after its PRD-v2
# section (a grep-able coverage map). Channel laws are EXACT one-run DM Choi (via
# test/choi.jl, INCLUDED before this file in runtests.jl); Toffoli-grade and
# streaming-vs-fusion facts are dense-statevector compares (the Choi harness caps
# nin ≤ 2). No marginals — the §7.1/wm28 discipline. Test-side code is licensed to
# reach kernel values (`H`, `X`, `ctrl`, `apply!`), exactly as test/choi.jl is.

using Test
using LinearAlgebra
using Sturm
using Sturm: eager, density, dual, when, not!, ctrl, X, H, apply!, statevector,
    density_matrix, current_context, _core, _under_control

# Dense reference matrices (harness basis: |o₁o₂⟩, o₁ = MSB = first-returned).
const _id2 = ComplexF64[1 0; 0 1]
const _Xm  = ComplexF64[0 1; 1 0]
const _Hm  = ComplexF64[1 1; 1 -1] ./ sqrt(2)
const _CXm = ComplexF64[1 0 0 0; 0 1 0 0; 0 0 0 1; 0 0 1 0]   # control MSB, target LSB
const _CZm = ComplexF64[1 0 0 0; 0 1 0 0; 0 0 1 0; 0 0 0 -1]

# §7.1b deferred teleport — transcribed VERBATIM (every op is M3/M4 surface +
# M5 `when`; no casts, so it runs one DM pass ⇒ deterministic Choi).
function teleport_deferred(ψ::QBool)
    b = QBool(0.5)
    c = false ⊻ b                # Bell pair on (b, c)
    b ⊻= ψ

    when(b) do                   # deferred X-correction
        not!(c)
    end
    when(dual(ψ)) do             # deferred Z-correction: control read in the
        not!(dual(c))            # conjugate basis — |−⟩⟨−| ⊗ Z, exactly
    end
    return c                     # ψ, b: owned, unreturned — traced, silently
end

@testset "M5 — guardrail 1: cast/ptrace under control is a loud error (§8.1 regression)" begin
    # THE headline v0.1 §8.1 fix: a non-unitary effect under a live control frame
    # errors BEFORE any backaction. The statevector is bit-unchanged across the throw.
    eager(2) do ctx
        q = QBool(0.5); r = QBool(false)
        sv = copy(statevector(ctx))
        # measurement of the control itself → guardrail 1 (NOT guardrail 2)
        @test_throws ErrorException when(q) do; Bool(q) end
        @test statevector(ctx) == sv
        @test isempty(_core(ctx).control_stack)          # stack restored on throw
        # measurement of another register, conjugate-basis measurement, explicit trace
        @test_throws ErrorException when(q) do; Bool(r) end
        @test_throws ErrorException when(q) do; Bool(dual(r)) end
        @test_throws ErrorException when(q) do; ptrace!(r.wire) end
        @test statevector(ctx) == sv                     # no backaction from any of them
        @test isempty(_core(ctx).control_stack)
    end
    # DM noise under control: forward-hooked at M8/M11 (row 9). Documented, not
    # yet a live guardrail on apply_channel! — flagged in when.jl. No test here.
end

@testset "M5 — guardrail 2: the body may not access its control (external + through views)" begin
    # Bădescu–Panangaden Condition I. Both target-side and control-side views resolve
    # to the parent wire, so aliasing is caught with a guard-externality message.
    eager(3) do _
        q = QBool(0.5); r = QBool(false); a = QBool(false)
        @test_throws ErrorException when(q) do; not!(q) end            # control as target
        @test_throws ErrorException when(q) do; q ⊻= true end          # control as target (mixed)
        @test_throws ErrorException when(q) do; a ⊻= q end             # control as op-control
        @test_throws ErrorException when(q) do; not!(dual(q)) end      # control through a view (kickback onto self)
        @test_throws ErrorException when(dual(q)) do; not!(q) end      # control-side view aliases target
        # message names the guard-externality
        err = try; when(q) do; not!(q) end; catch e; e; end
        @test occursin("control register", sprint(showerror, err))
        # a LEGAL body (distinct target) does NOT throw
        @test (when(q) do; not!(r) end) === nothing
        Bool(q)
    end
end

@testset "M5 — streaming ctrl(X): when(q) do not!(r) end = CX (§3.5)" begin
    J = choi((q, r) -> (when(q) do; not!(r) end; (q, r)), 2)
    @test J ≈ analytic_choi2(_CXm)
    @test tr(J) ≈ 1
end

@testset "M5 — fusion: a U2 action under control never fuses uncontrolled (§8.1-class)" begin
    # A bare U2 (`not!`) under a live control must emit as a controlled 2-wire op,
    # never linger in the 1q fusion buffer to flush uncontrolled. Closed by
    # construction (`_act!` wraps before `apply!`); asserted against dense CX.
    got = eager(2) do ctx
        q = QBool(0.5); r = QBool(false)        # q superposed ⇒ the control branch matters
        when(q) do; not!(r) end
        statevector(ctx)
    end
    ref = eager(2) do ctx
        q = QBool(0.5); r = QBool(false)
        apply!(ctx, ctrl(X), (q.wire, r.wire))  # the dense ctrl(X) reference
        statevector(ctx)
    end
    @test got ≈ ref
end

@testset "M5 — kickback / CZ: when(q) do not!(dual(r)) end = CZ, control is input+output (§7.3)" begin
    # The body names r (as Z) — never the control q — yet q picks up a relative
    # phase through the `ctrl` mechanism. One CZ. Symmetric in the two spellings.
    J1 = choi((q, r) -> (when(q) do; not!(dual(r)) end; (q, r)), 2)
    J2 = choi((q, r) -> (when(r) do; not!(dual(q)) end; (q, r)), 2)
    @test J1 ≈ analytic_choi2(_CZm)
    @test J2 ≈ analytic_choi2(_CZm)
    @test J1 ≈ J2                       # CZ symmetry theorem
    @test tr(J1) ≈ 1
end

@testset "M5 — nested when = Toffoli-grade: when(a){when(b){not!(c)}} = CCX (§3.5, Delorme Eq 14)" begin
    # Depth-2 stack ⇒ flat Ctrl(2,X) ⇒ the existing ad.jl k=2 Toffoli path.
    # Dense-statevector compare (Choi harness caps nin ≤ 2); a superposed outer
    # control makes it non-trivial (entangled output).
    got = eager(3) do ctx
        a = QBool(0.5); b = QBool(true); c = QBool(false)
        when(a) do; when(b) do; not!(c) end; end
        statevector(ctx)
    end
    ref = eager(3) do ctx
        a = QBool(0.5); b = QBool(true); c = QBool(false)
        apply!(ctx, ctrl(ctrl(X)), (a.wire, b.wire, c.wire))
        statevector(ctx)
    end
    @test got ≈ ref
end

@testset "M5 — anti-control sandwich: not!(q); when(q){…}; not!(q) fires on q=0 (§3.5 blessed idiom)" begin
    antiCX = kron(_Xm, _id2) * _CXm * kron(_Xm, _id2)     # fires when the control is 0
    J = choi((q, r) -> (not!(q); when(q) do; not!(r) end; not!(q); (q, r)), 2)
    @test J ≈ analytic_choi2(antiCX)
    @test tr(J) ≈ 1
end

@testset "M5 — when(dual(q)): control in the conjugate basis (§7.1b)" begin
    # H·CX·H on the control: fires on |−⟩, not |1⟩.
    ref = kron(_Hm, _id2) * _CXm * kron(_Hm, _id2)
    J = choi((q, r) -> (when(dual(q)) do; not!(r) end; (q, r)), 2)
    @test J ≈ analytic_choi2(ref)
    @test tr(J) ≈ 1
end

@testset "M5 — clean-ancilla exit witness: sound under superposed & entangled control (§3.9)" begin
    # (a) SUPERPOSED control, matched uncompute ⇒ ancilla returns to |0⟩ ⇒ clean.
    @test (eager(3) do ctx
        q = QBool(0.5)                    # |+⟩ — the control branch is live
        when(q) do
            a = QBool(false)              # body-owned scratch |0⟩
            not!(a); not!(a)              # controlled X twice = identity ⇒ a back to |0⟩
        end                               # region exit: clean-ancilla assert PASSES
        Bool(q); nothing
    end) === nothing
    # (b) SUPERPOSED control, UNMATCHED uncompute ⇒ ancilla dirty ⇒ loud error.
    @test_throws ErrorException eager(3) do ctx
        q = QBool(0.5)
        when(q) do
            a = QBool(false)
            not!(a)                       # a entangled with q: |0⟩ if q=0, |1⟩ if q=1
        end                               # region exit: witness FIRES
        Bool(q)
    end
    # (c) ENTANGLED control (Bell-correlated with another register): clean passes,
    #     dirty fails — the reference-entanglement is orthogonal to the witness.
    @test (eager(3) do ctx
        q = QBool(0.5); s = false ⊻ q     # Bell pair on (q, s): q now entangled
        when(q) do
            a = QBool(false); not!(a); not!(a)
        end
        Bool(q); Bool(s); nothing
    end) === nothing
    @test_throws ErrorException eager(3) do ctx
        q = QBool(0.5); s = false ⊻ q
        when(q) do
            a = QBool(false); not!(a)
        end
        Bool(q); Bool(s)
    end
    # (d) DM branch of the witness (region-in-when trace on a density context).
    @test (density(3) do _
        q = QBool(0.5)
        when(q) do
            a = QBool(false); not!(a); not!(a)
        end
        nothing
    end) === nothing
    @test_throws ErrorException density(3) do _
        q = QBool(0.5)
        when(q) do
            a = QBool(false); not!(a)
        end
    end
end

@testset "M5 — control stack unwinds on a thrown error mid-body (§3.5 topology)" begin
    # A user error mid-body must leave the stack clean and (for when(dual)) restore
    # the control's basis — the nested try/finally guarantees it.
    eager(2) do ctx
        q = QBool(0.5); r = QBool(false)
        try; when(q) do; not!(r); error("boom") end; catch; end
        @test isempty(_core(ctx).control_stack)
        @test !_under_control(ctx)
        try; when(dual(q)) do; not!(r); error("boom") end; catch; end
        @test isempty(_core(ctx).control_stack)   # even the dual sandwich unwinds
        Bool(q); Bool(r)
    end
end

@testset "M5 — deferred teleport §7.1b: choi(teleport_deferred,1) ≈ J(id), one DM run (THE gate)" begin
    # cap = 4 is TIGHT: live wires ψ(sys), ref, b, c = 4; single-control `when`s
    # need no scratch (k=1). Set explicitly (any added ancilla or a k≥3 `when`
    # variant would need a bump).
    bell    = ComplexF64[1 0 0 1; 0 0 0 0; 0 0 0 0; 1 0 0 1] ./ 2   # |Ω⟩⟨Ω| = J(id)
    pinched = ComplexF64[1 0 0 0; 0 0 0 0; 0 0 0 0; 0 0 0 1] ./ 2   # complete dephasing
    J = choi(teleport_deferred, 1; cap = 4)
    @test J ≈ bell                              # the identity channel, coherently
    @test tr(J) ≈ 1
    @test !(J ≈ Diagonal(diag(J)))              # off-diagonals present ⇒ genuinely coherent
    @test !(J ≈ pinched)                        # NOT the wm28 diagonal-only teleport (Z-sensitive)
    # IOU → M8: the §3.5 REQUIRED law test (streaming ≡ materialized, Choi-compared)
    # needs UnitaryDAG/Tracing. M5 discharges the STREAMING half (this Choi ≈ id);
    # the two-strategy equality lands with M8's materialize path.
end
