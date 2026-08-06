# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# Sturm.jl M11 (bead Sturm.jl-qmpo), design docs/design/m11-82su-synthesis.md
# §6 "Analysis" + M11.PORTABLE.SYNDROME: the S31/T2 two-name split
# (classicalise vs record_distribution), the S30 host-scalar select mirror,
# and the acceptance example — ONE surface listing running under Eager
# (scalars), DM (exact instrument sums), and Tracing (materialised CasesN) with
# the DM replay reproducing the DM-streamed channel. Requires test/choi.jl.

using Test
using LinearAlgebra
using Sturm
using Sturm: classicalise, record_distribution, CLASSICALISE_MAXWIRES,
    channel, bit_flip, phase_flip, choi_matrix, channel_dag, trace,
    select, ClassicalTable, density, density_matrix, eager, apply!,
    _replay_dm!, _adopt_qbool, Protect, physical_iid, bit_flip_code,
    I2, Z, H, X, discard!, shots, ⊗

@testset "M11.CLASSICALISE.STOCHASTIC" begin
    # Columns sum to 1; the id / bit-flip / Hadamard shadows are the expected
    # stochastic matrices; a 2-wire value gives a 4×4 (arity from the ports —
    # the v0.1 always-2×2 defect cannot recur).
    Mid = classicalise(channel(I2))
    @test Mid ≈ [1.0 0.0; 0.0 1.0]
    Mbf = classicalise(bit_flip(0.3))
    @test Mbf ≈ [0.7 0.3; 0.3 0.7]
    MH = classicalise(channel(H))
    @test MH ≈ [0.5 0.5; 0.5 0.5]
    for M in (Mid, Mbf, MH), j in 1:2
        @test sum(M[:, j]) ≈ 1 atol = 1e-12
    end
    M2 = classicalise(bit_flip(0.2) ⊗ bit_flip(0.0))
    @test size(M2) == (4, 4)
    @test M2[1, 1] ≈ 0.8 && M2[3, 1] ≈ 0.2       # wire 1 = MSB flips |00⟩→|10⟩
    # The cap is loud.
    wide = bit_flip(0.1) ⊗ (bit_flip(0.1) ⊗ (bit_flip(0.1) ⊗ bit_flip(0.1)))
    @test_throws ArgumentError classicalise(wide)
    # DAG columns run by exact replay: a traced H-DAG has the uniform shadow.
    hdag = trace(q -> (apply!(Sturm.current_context(), H, (q.wire,)); q), 1)
    @test classicalise(hdag) ≈ [0.5 0.5; 0.5 0.5] atol = 1e-10
end

@testset "M11.CLASSICALISE.IS-PHASE-BLIND" begin
    # DELIBERATE: classicalise(id) == classicalise(Ad_Z). The shadow kills
    # exactly what a coherent probe sees — which is why classicalise is NEVER
    # a channel-equivalence test (the F3-barred criterion class). The channels
    # themselves are distinguishable (their Chois differ).
    @test classicalise(channel(I2)) == classicalise(channel(Z))
    @test !(choi_matrix(channel(I2)) ≈ choi_matrix(channel(Z)))
end

@testset "M11.CLASSICALISE.QECC" begin
    # The quantitative statement read off a value: the logical bit-flip
    # probability sits at [2,1] of the logical shadow.
    enc = bit_flip_code()
    p = 0.1
    Φ = Protect(enc)(physical_iid(enc, bit_flip(p)))
    M = classicalise(Φ)
    @test size(M) == (2, 2)
    @test M[2, 1] ≈ 3p^2 - 2p^3 atol = 1e-10
end

@testset "M11.RECORD.NO-BACKACTION-AND-DISTRIBUTION" begin
    density(2) do ctx
        u = QBool(0.3)
        m = Bool(u)                                # DM: a ClassicalBit token
        ρ0 = density_matrix(ctx)
        dist = record_distribution(m)
        @test density_matrix(ctx) == ρ0            # BITWISE unchanged
        @test dist ≈ [0.7, 0.3] atol = 1e-12
        # Non-consuming: read again.
        @test record_distribution(m) ≈ [0.7, 0.3] atol = 1e-12
        nothing
    end
end

@testset "M11.RECORD.DERIVED-CORRELATION" begin
    density(2) do ctx
        u = QBool(0.3)
        m = Bool(u)
        n = !m                                     # T1 derivation, same base wire
        @test record_distribution(n) ≈ [0.3, 0.7] atol = 1e-12   # exact complement
        nothing
    end
end

@testset "M11.RECORD.LOUD-AND-NOT-A-VALUE" begin
    # Eager: measurement returns a host Bool — nothing to introspect.
    @test_throws MethodError record_distribution(true)
    # Tracing: symbolic record, descriptive error.
    err = try
        trace(1) do q
            record_distribution(Bool(q))
            QBool(false)
        end
        nothing
    catch e; e end
    @test err isa ArgumentError
    @test occursin("SYMBOLIC", sprint(showerror, err))
    # After discard!: loud, naming the last-use rule.
    density(2) do ctx
        u = QBool(0.5)
        m = Bool(u)
        discard!(m)
        err2 = try
            record_distribution(m); nothing
        catch e; e end
        @test err2 isa ErrorException
        @test occursin("last-use", sprint(showerror, err2))
        nothing
    end
    # The return is a distribution, not a value — no truth value to branch on.
    density(2) do ctx
        u = QBool(0.5)
        d = record_distribution(Bool(u))
        @test d isa Vector{Float64}
        @test_throws TypeError (d ? 1 : 0)
        nothing
    end
end

@testset "M11.SELECT.HOST-SCALAR" begin
    # S30: the Eager twins, same totality checks, same messages.
    @test select(true, 3, 5) == 3
    @test select(false, 3, 5) == 5
    @test select(2, [10, 20, 30]) == 30
    err = try
        select(3, [10, 20, 30]); nothing
    catch e; e end
    @test err isa ArgumentError
    @test occursin("TOTAL", sprint(showerror, err))
    tbl = ClassicalTable([7, 8]; default = 0)
    @test select(1, tbl) == 8
    @test select(5, tbl) == 0                      # default fires
    @test_throws ArgumentError select(5, ClassicalTable([7, 8]))
end

# ─── The acceptance example: ONE listing, three contexts (S30/§3.8) ───────────

"Bit-flip syndrome recovery in pure surface vocabulary (the S28/S30 program)."
function _bitflip_recover!(q1, q2, q3)
    a1 = QBool(false); a2 = QBool(false)           # construct 1
    a1 ⊻= q1; a1 ⊻= q2                             # construct 3 — parity(q1,q2)
    a2 ⊻= q2; a2 ⊻= q3                             # construct 3 — parity(q2,q3)
    b1 = Bool(a1); b2 = Bool(a2)                   # construct 2 (scalar or token)
    s = Sturm.zext(select(b1, 1, 0), Val(2)) +     # σ = b1 + 2·b2 — the T2 SSA
        2 * Sturm.zext(select(b2, 1, 0), Val(2))   # (host twins on Eager, S30)
    @cases s begin                                 # construct 6
        0 => nothing
        1 => not!(q1)
        3 => not!(q2)
        2 => not!(q3)
    end
    return (q1, q2, q3)
end

@testset "M11.PORTABLE.SYNDROME" begin
    # The listing operates on HANDLES; drive it end-to-end on all contexts.
    # Eager (host scalars): N ≥ 500 shots of p=0.3 single-X-per-wire noise on
    # |000⟩ always recover to |000⟩ (any ONE X is corrected exactly).
    for wire in 1:3
        eager(6) do _
            q1 = QBool(false); q2 = QBool(false); q3 = QBool(false)
            qs = (q1, q2, q3)
            not!(qs[wire])                         # a definite single-X error
            _bitflip_recover!(q1, q2, q3)
            @test Bool(q1) == false && Bool(q2) == false && Bool(q3) == false
            nothing
        end
    end
    # DM (exact instrument sums): same, deterministically, incl. a superposed
    # logical state — encode |ψ⟩, inject X₂, recover, decode: identity.
    J = choi(1; cap = 7) do q
        blk = encode_state(bit_flip_code(), q)
        Sturm.apply!(Sturm.contextof(blk), X, (blk.wires[2],))
        h1 = Sturm._adopt_qbool(Sturm.contextof(blk), blk.wires[1])
        h2 = Sturm._adopt_qbool(Sturm.contextof(blk), blk.wires[2])
        h3 = Sturm._adopt_qbool(Sturm.contextof(blk), blk.wires[3])
        _bitflip_recover!(h1, h2, h3)
        decode_state(blk)
    end
    bell = ComplexF64[1 0 0 1; 0 0 0 0; 0 0 0 0; 1 0 0 1] ./ 2
    @test J ≈ bell atol = 1e-10
    # Tracing: the listing materialises (MeasureN + CasesN tree), and the DM
    # replay of the traced DAG reproduces the DM-streamed behaviour.
    dag = trace(3) do q1, q2, q3
        _bitflip_recover!(q1, q2, q3)
    end
    @test any(n -> n isa Sturm.MeasureN, dag.nodes)
    @test any(n -> n isa Sturm.CasesN, dag.nodes)
    density(6) do ctx
        u1 = QBool(false); u2 = QBool(true); u3 = QBool(false)   # X₂-errored |000⟩
        _replay_dm!(ctx, dag, [u1.wire, u2.wire, u3.wire])
        ρ = density_matrix(ctx)
        # data wires recovered to |000⟩: marginal on the three data slots.
        p000 = real(sum(ρ[i + 1, i + 1] for i in 0:(2^6 - 1)
                        if (i >> Sturm.q(ctx, u1.wire)) & 1 == 0 &&
                           (i >> Sturm.q(ctx, u2.wire)) & 1 == 0 &&
                           (i >> Sturm.q(ctx, u3.wire)) & 1 == 0))
        @test p000 ≈ 1 atol = 1e-10
        nothing
    end
end
