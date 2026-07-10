# SPDX-License-Identifier: AGPL-3.0-only
#
# M2 tests (bead Sturm.jl-dc6i): the Eager and DensityMatrix contexts —
# apply/measure round-trips, the endianness pin, the §8.4 aliasing check, DM
# conjugation + 1-local channels + exact partial trace, and reset-on-recycle.

# (helpers from test_m2_common.jl are already in scope)

using Sturm: _core, _marginal_p1, orkan_state_get

# Partial trace of a 2-qubit density matrix over Orkan slot `t` (0-based),
# returning the 2×2 reduced state on the other qubit. Little-endian: qubit j is
# bit j of the basis index.
function _ptrace2(ρ::Matrix{ComplexF64}, t::Int)
    k = 1 - t
    red = zeros(ComplexF64, 2, 2)
    for i in 0:1, j in 0:1
        s = zero(ComplexF64)
        for b in 0:1
            gi = (i << k) | (b << t)
            gj = (j << k) | (b << t)
            s += ρ[gi+1, gj+1]
        end
        red[i+1, j+1] = s
    end
    return red
end

@testset "Contexts: Eager & DensityMatrix (M2)" begin

    @testset "single-wire round-trips vs denoted_matrix (up to global phase)" begin
        for g in (X, Y, Z, H, S, T, Ry(0.7), Rz(-1.3), Rx(2.1))
            @test approx_upto_phase(realized_matrix(g), denoted_matrix(g); atol=1e-7)
        end
    end

    @testset "endianness pin — X on the MSB wire flips the HIGH bit" begin
        eager(3) do ctx
            ws = (allocate!(ctx), allocate!(ctx), allocate!(ctx))   # slots 0,1,2
            # MSB of a 3-wire register = highest slot = ws[3] (slot 2, bit 2).
            apply!(ctx, X, (ws[3],))
            v = statevector(ctx)
            idx = findall(a -> abs(a) > 1e-9, v) .- 1
            @test idx == [4]                                        # bit 2 ⇒ index 4, not 1
        end
        # X on the LSB wire flips the low bit.
        eager(3) do ctx
            ws = (allocate!(ctx), allocate!(ctx), allocate!(ctx))
            apply!(ctx, X, (ws[1],))                                # slot 0, bit 0
            v = statevector(ctx)
            @test (findall(a -> abs(a) > 1e-9, v) .- 1) == [1]
        end
    end

    @testset "§8.4 aliasing — register identity, BEFORE the FFI shim" begin
        eager(2) do ctx
            w = allocate!(ctx)
            allocate!(ctx)
            # A controlled op with the SAME WireID as control and target.
            err = try
                apply!(ctx, ctrl(X), (w, w))
                nothing
            catch e
                e
            end
            @test err isa ErrorException
            @test occursin("aliasing", err.msg)
            @test occursin(string(w), err.msg)      # names the register identity
        end
    end

    @testset "1q fusion buffer — a chain of 1q gates fuses correctly" begin
        # H;S;H;T on |0⟩ should equal the composed U2's action (up to phase).
        u = T ∘ (H ∘ (S ∘ H))
        r = eager(1) do ctx
            w = allocate!(ctx)
            apply!(ctx, H, (w,)); apply!(ctx, S, (w,)); apply!(ctx, H, (w,)); apply!(ctx, T, (w,))
            statevector(ctx)
        end
        ref = denoted_matrix(u) * ComplexF64[1, 0]
        @test approx_upto_phase(reshape(r, :, 1), reshape(ref, :, 1); atol=1e-7)
        # fusion must flush before an entangling op: H(a);ctrl(X)(a,b) = Bell.
        rb = eager(2) do ctx
            a = allocate!(ctx); b = allocate!(ctx)
            apply!(ctx, H, (a,))
            apply!(ctx, ctrl(X), (a, b))
            statevector(ctx)
        end
        @test isapprox(abs.(rb), abs.(ComplexF64[1, 0, 0, 1] ./ sqrt(2)); atol=1e-7)
    end

    @testset "allocate!/q/live_wires bookkeeping" begin
        eager(4) do ctx
            a = allocate!(ctx); b = allocate!(ctx)
            @test q(ctx, a) == 0 && q(ctx, b) == 1
            @test Set(live_wires(ctx)) == Set([a, b])
            @test_throws ErrorException q(ctx, Sturm.WireID(999999))   # dead/unknown wire
        end
    end

    @testset "DensityMatrix: conjugation, channels, exact ptrace" begin
        # X: |0⟩⟨0| ↦ |1⟩⟨1|.
        ρ = density(1) do ctx
            w = allocate!(ctx)
            apply!(ctx, X, (w,))
            density_matrix(ctx)
        end
        @test isapprox(ρ, ComplexF64[0 0; 0 1]; atol=1e-9)

        # 1-local reset channel: |1⟩⟨1| ↦ |0⟩⟨0|.
        ρr = density(1) do ctx
            w = allocate!(ctx)
            apply!(ctx, X, (w,))
            apply_channel!(ctx, Matrix{ComplexF64}[ComplexF64[1 0; 0 0], ComplexF64[0 1; 0 0]], w)
            density_matrix(ctx)
        end
        @test isapprox(ρr, ComplexF64[1 0; 0 0]; atol=1e-9)

        # EXACT partial trace of a Bell state ⇒ maximally mixed marginal.
        ρafter = density(2) do ctx
            a = allocate!(ctx); b = allocate!(ctx)
            apply!(ctx, H, (a,))
            apply!(ctx, ctrl(X), (a, b))
            ptrace!(ctx, a)          # exact trace of wire a (reset channel)
            density_matrix(ctx)
        end
        # a is slot 0; reducing over the OTHER slot leaves a's post-trace = |0⟩⟨0|,
        # and b (slot 1) is maximally mixed. Check b's reduced state = I/2.
        red_b = _ptrace2(ρafter, 0)
        @test isapprox(red_b, ComplexF64[0.5 0; 0 0.5]; atol=1e-9)
    end

    @testset "reset-on-recycle — a recycled slot re-enters as |0⟩" begin
        eager(2) do ctx
            a = allocate!(ctx)
            apply!(ctx, X, (a,))          # a → |1⟩ (up to phase)
            ptrace!(ctx, a)               # trace collapses toward |1⟩, then resets slot to |0⟩
            # slot 0 recycled; a fresh wire must read |0⟩.
            c = allocate!(ctx)
            @test q(ctx, c) == 0          # recycled the same slot
            p1 = _marginal_p1(_core(ctx).state, q(ctx, c))
            @test p1 < 1e-9               # fresh = |0⟩
        end
    end
end
