# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# Sturm.jl M4 (bead Sturm.jl-3nld): the law tests for views, `dual`, the action
# family, and teleportation. Each `@testset` is named after its PRD-v2 section
# (a grep-able coverage map). Channel laws are exact one-run DM Choi (via
# test/choi.jl, INCLUDED before this file in runtests.jl); teleportation is the
# exception — its §7.1 `&&`-corrections use scalar `Bool`, which throws on DM, so
# M4's teleport gate is the Eager statistical full-channel probe (the exact
# Choi(teleport_deferred) is M5's gate, §7.1b). Test-side code is licensed to
# reach kernel values (`H`, `S`, `apply!`), exactly as test/choi.jl is.

using Test
using Random
using LinearAlgebra
using Sturm
using Sturm: eager, density, dual, view, DualView, View, _parent_wire, _conj,
    _dual_transform, H, X, Y, Z, S, ctrl, apply!, statevector, density_matrix,
    current_context, _core

# The §7.1 teleport program, transcribed VERBATIM (every op is M4 surface + M3
# casts; corrections are Julia-Bool-conditioned — no `when`). Used by the Eager
# statistical gate and the DM-throw negative test.
function teleport(ψ::QBool)
    b = QBool(0.5)                # a fair quantum coin
    c = false ⊻ b                 # xor into a fresh false: Bell pair
    b ⊻= ψ                        # correlate payload with Alice's half
    m_phase = Bool(dual(ψ))       # conjugate-basis readout (consumes ψ)
    m_value = Bool(b)
    m_value && not!(c)            # ordinary conditionals, ordinary flips —
    m_phase && not!(dual(c))      # one of them in the dual view
    return c
end

@testset "M4 — dual unwrap / wrapper identity (§3.3)" begin
    eager(2) do _
        q = QBool(0.5)
        # Involution is STRUCTURAL (dispatch-time unwrap), not F² evaluation.
        @test dual(dual(q)) === q
        # Each dual(·) call is a FRESH wrapper — bookkeeping must key on the wire.
        @test !(dual(q) === dual(q))
        @test dual(q) isa DualView
        @test _parent_wire(dual(dual(q))) == q.wire
        @test _parent_wire(dual(q)) == q.wire
        Bool(q)
    end

    # dual(dual(q)) applies NO process: the statevector is bit-identical and the
    # wire's fusion buffer stays empty (the unwrap emits nothing — no H).
    eager(1) do ctx
        q = QBool(0.5)
        sv_before = copy(statevector(ctx))
        r = dual(dual(q))
        @test r === q
        @test statevector(ctx) == sv_before      # not ≈: BIT-identical, no op emitted
        @test isempty(_core(ctx).fusion)          # nothing fused onto any wire
        Bool(q)
    end
end

@testset "M4 — views unwrap vs processes compose (§3.3, QBool arm)" begin
    # `dual` unwraps by nominal type; the general `view` COMPOSES its transforms.
    # For QBool the F² = parity trap is MASKED (H² ≈ +I), so the sharp
    # integer-negation signature test is deferred to M6/QInt (per plan). Here we
    # pin the TYPE-LEVEL distinction: dual(dual(q)) is the bare handle, while
    # view(H, view(H, q)) is a composed View (never an unwrap).
    eager(1) do _
        q = QBool(0.5)
        @test dual(dual(q)) isa QBool          # unwrapped to the handle
        vv = view(H, view(H, q))
        @test vv isa View                       # composed, NOT unwrapped
        @test vv.transform ≈ (H ∘ H)            # transforms composed
        # M6 IOU: with QInt, dual(dual(x)) === x while F² negates every integer —
        # the integer-negation signature test that this QBool arm cannot show.
        Bool(q)
    end
    # Kernel conjugation direction sanity (§3.3, the ℤ₂ swap): _conj(H,X) ≈ Z,
    # _conj(H,Z) ≈ X. Self-adjoint H ⇒ direction unobservable at M4.
    @test _conj(H, X) ≈ Z
    @test _conj(H, Z) ≈ X
end

@testset "M4 — X ↔ Z view swap (§3.3/§3.4, exact DM Choi)" begin
    # not! ↦ X (ℤ₂ translation); not!(dual(·)) ↦ Z (ℤ₂ modulation). The two
    # channels are the X and Z channels respectively, and they DIFFER.
    Jx = choi(q -> (not!(q); q), 1)
    Jz = choi(q -> (not!(dual(q)); q), 1)
    @test Jx ≈ analytic_choi1(ComplexF64[0 1; 1 0])     # J(Ad_X)
    @test Jz ≈ analytic_choi1(ComplexF64[1 0; 0 -1])    # J(Ad_Z)
    @test !(Jx ≈ Jz)
    @test tr(Jx) ≈ 1 && tr(Jz) ≈ 1
end

@testset "M4 — mixed xor is EXACT X, not Ry(π) (§3.4 / audit 8.3)" begin
    # `q ⊻= true` lowers to the kernel's exact X (the v0.1 latent-phase bug fix).
    @test choi(q -> (q ⊻= true; q), 1) ≈ analytic_choi1(ComplexF64[0 1; 1 0])
    # `q ⊻= false` is a no-op (identity channel).
    @test choi(q -> (q ⊻= false; q), 1) ≈ analytic_choi1(ComplexF64[1 0; 0 1])
end

@testset "M4 — Bell prep `false ⊻ b` (§7.1)" begin
    # false ⊻ b with b = |+⟩ gives Φ⁺ on (b, c); true ⊻ b gives Ψ-type.
    bellΦ = zeros(ComplexF64, 4, 4); bellΦ[1,1] = bellΦ[1,4] = bellΦ[4,1] = bellΦ[4,4] = 0.5
    dmΦ = density(2) do ctx; b = QBool(0.5); false ⊻ b; density_matrix(ctx) end
    @test dmΦ ≈ bellΦ
    # true ⊻ b: fresh starts |1⟩, CNOT(b→c) ⇒ (|01⟩+|10⟩)/√2 in (b,c).
    bellΨ = zeros(ComplexF64, 4, 4); bellΨ[2,2] = bellΨ[2,3] = bellΨ[3,2] = bellΨ[3,3] = 0.5
    dmΨ = density(2) do ctx; b = QBool(0.5); true ⊻ b; density_matrix(ctx) end
    @test dmΨ ≈ bellΨ
    # Fresh-output form: c is a NEW handle (value world), b stays live.
    eager(2) do _
        b = QBool(0.5); c = false ⊻ b
        @test c !== b
        Bool(b); Bool(c)
    end
end

@testset "M4 — CZ symmetry at Choi level (§7.3, nin=2)" begin
    # q̂ ⊻= r ≡ r̂ ⊻= q — symmetry of the pairing G × Ĝ → U(1), by theorem.
    CZ = ComplexF64[1 0 0 0; 0 1 0 0; 0 0 1 0; 0 0 0 -1]
    J1 = choi((q, r) -> (q̂ = dual(q); q̂ ⊻= r; (q, r)), 2)
    J2 = choi((q, r) -> (r̂ = dual(r); r̂ ⊻= q; (q, r)), 2)
    @test J1 ≈ analytic_choi2(CZ)
    @test J2 ≈ analytic_choi2(CZ)
    @test J1 ≈ J2                       # the symmetry theorem
    @test tr(J1) ≈ 1
    # Two CZs in sequence cancel to the identity channel.
    Jii = choi((q, r) -> (q̂ = dual(q); q̂ ⊻= r; q̂ ⊻= r; (q, r)), 2)
    @test Jii ≈ analytic_choi2(Matrix{ComplexF64}(I, 4, 4))
end

@testset "M4 — Bool(dual(q)) X-readout + |+⟩↦false labeling (§3.3/§7.1)" begin
    # |+⟩ ↦ false, |−⟩ ↦ true DETERMINISTICALLY (F†P_kF, the wm28 convention pin).
    N = 1024
    hits_plus = eager(1; rng = MersenneTwister(0xB0A)) do _
        sum(_ -> Bool(dual(QBool(0.5))) == false, 1:N)
    end
    hits_minus = eager(1; rng = MersenneTwister(0xB0B)) do _
        sum(_ -> Bool(dual(QBool(0.5, π))) == true, 1:N)
    end
    @test hits_plus == N                # deterministic |+⟩ ↦ false
    @test hits_minus == N               # deterministic |−⟩ ↦ true
    # A |0⟩ read through dual is uniform (complementarity, §3.9) — ±3σ.
    ones0 = eager(1; rng = MersenneTwister(0xB0C)) do _
        sum(_ -> Bool(dual(QBool(false))) ? 1 : 0, 1:N)
    end
    @test abs(ones0 / N - 0.5) < 3 * sqrt(0.25 / N)
    # DM Bool(dual(q)) throws (a scalar outcome is a trajectory, §3.8).
    @test_throws ArgumentError density(1) do _; Bool(dual(QBool(0.5))) end
end

@testset "M4 — views are NOT numbers: the P9 wall (§3.3)" begin
    # No ring ops on a view: generic numeric code MethodErrors honestly (the same
    # wall as g(x::Int)), so the mutate-in-place view convention can never leak.
    eager(1) do _
        q = QBool(0.5)
        @test_throws MethodError dual(q) * 2
        @test_throws MethodError dual(q) + 1
        @test_throws MethodError dual(q) & true
        @test_throws MethodError dual(q) ^ 2
        Bool(q)
    end
end

@testset "M4 — aliasing through views fires NOW (§8.4)" begin
    # q̂ ⊻= q (view whose parent IS the other operand) resolves to a doubled
    # WireID and the landed _check_wire_aliasing fires with register identity —
    # the M5 `when(q) do not!(dual(q)) end` shadow, caught in M4 already.
    err = try
        eager(2) do _; q = QBool(0.5); q̂ = dual(q); q̂ ⊻= q end
        nothing
    catch e
        e
    end
    @test err isa ErrorException
    @test occursin("aliasing", sprint(showerror, err))
end

@testset "M4 — D11 spelling traps (dual's docstring, parser-level)" begin
    # `dual(q) ⊻= r` is not writable Julia: op-assign demands an assignable
    # location, so it LOWERS to an :error (never reaches runtime — the M0 lint).
    lo = Meta.lower(@__MODULE__, :(dual(q) ⊻= r))
    @test lo isa Expr && lo.head === :error
    @test occursin("invalid assignment location", string(lo.args[1]))
    # The bound-view idiom is fine (q̂ is a plain local rebinding to the returned
    # self): it must PARSE and LOWER without error.
    lo2 = Meta.lower(@__MODULE__, :(begin q̂ = dual(q); q̂ ⊻= r end))
    @test !(lo2 isa Expr && lo2.head === :error)
end

@testset "M4 — teleportation: Eager statistical full-channel probe (§7.1, wm28)" begin
    # M4's teleport GATE (the RATIFIED split): §7.1's &&-form runs on Eager (scalar
    # Bool + && both work); the deterministic Choi(teleport_deferred) is M5's gate
    # (§7.1b — the &&-corrections make a one-run DM Choi impossible: scalar Bool
    # throws on DM, and the branchless form needs `when` ∉ M4). Recovery is EXACT
    # (corrections compensate the random Bell outcomes), so every shot recovers
    # |ψ⟩ and the matching-basis measurement is deterministic ⇒ hits == N.
    N = 1024
    # (prep, readout, expected) — Z on |0⟩/|1⟩, X on |+⟩/|−⟩ (via Bool(dual)),
    # Y on |i⟩ (test-side kernel S†+H readout, licensed like choi.jl).
    y_readout(ctx, out) = (apply!(ctx, adjoint(S), (out.wire,)); apply!(ctx, H, (out.wire,)); Bool(out))
    probes = [
        ("|0⟩", () -> QBool(false),   (ctx, o) -> Bool(o),          false),
        ("|1⟩", () -> QBool(true),    (ctx, o) -> Bool(o),          true),
        ("|+⟩", () -> QBool(0.5),     (ctx, o) -> Bool(dual(o)),    false),
        ("|−⟩", () -> QBool(0.5, π),  (ctx, o) -> Bool(dual(o)),    true),
        ("|i⟩", () -> QBool(0.5, π/2),(ctx, o) -> y_readout(ctx, o),false),  # wm28 discriminator
    ]
    for (name, prep, readout, expect) in probes
        hits = eager(4; rng = MersenneTwister(0x51EED ⊻ hash(name))) do ctx
            sum(_ -> readout(ctx, teleport(prep())) == expect, 1:N)
        end
        # Perfect recovery: a diagonal-only (wm28) teleport reads ≈ N/2 on the
        # |i⟩ (Y) and |+⟩/|−⟩ (X) probes — the whole point of the Z/Y-sensitive set.
        @test hits == N
    end
end

@testset "M4 — teleport under DM throws at the first Bool (M5 pointer)" begin
    # WHY there is no M4 DM Choi of the &&-form: DM Bool throws (§3.8), so
    # choi(teleport) throws at `Bool(dual(ψ))`. The deterministic
    # Choi(teleport_deferred) ≈ Choi(id) is M5's gate (§7.1b, corrections under
    # `when`, no scalar Bool). Documented here as a required negative test.
    @test_throws ArgumentError density(4) do _; teleport(QBool(0.5)) end
end
