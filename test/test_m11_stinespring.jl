# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# Sturm.jl M11 (bead Sturm.jl-qmpo), design docs/design/m11-82su-synthesis.md
# §6 "Stinespring": the F33 dilation contract — env-leading pin (S10, the
# amplitude-damping sentinel), Householder completion with EXACT first-d
# columns (S9), determinism, artifact unreachability (S11), the executable
# catalogue P/D vs the loud class-X boundary (S14), environment ownership
# (S15), and Eager trajectory honesty (S16). Requires test/choi.jl (the DM
# Choi harness) to be included first for the three-way agreement test.

using Test
using LinearAlgebra
using Sturm
using Sturm: KrausFamily, MixedUnitary, ChannelValue, ProcessValue,
    kraus_matrices, choi_matrix, bit_flip, phase_flip, depolarizing,
    amplitude_damping, phase_damping, dilate, StinespringDilation,
    ChannelArtifact, apply_noise!, density, eager, ctrl, ⊗, I2, X, Z,
    STINESPRING_ATOL, nwires, live_wires

# Test-side random valid Kraus family: G_i · S^{−1/2} with S = Σ G†G (always
# TP by construction). Deterministic seed data — no RNG in the loop.
function _random_family(R::Int, seed::Int)
    ops = Matrix{ComplexF64}[]
    v = seed
    for _ in 1:R
        G = Matrix{ComplexF64}(undef, 2, 2)
        for i in 1:2, j in 1:2
            v = (1103515245 * v + 12345) % 2147483648
            re = (v / 2147483648) - 0.5
            v = (1103515245 * v + 12345) % 2147483648
            im_ = (v / 2147483648) - 0.5
            G[i, j] = complex(re, im_)
        end
        push!(ops, G)
    end
    S = sum(K' * K for K in ops)
    Sinvsqrt = inv(sqrt(Hermitian(S)))
    return KrausFamily([K * Sinvsqrt for K in ops]; label = :random)
end

# Tr_E of an (env ⊗ sys) matrix, env = the LEADING (MSB) block index.
function _trace_env(M::Matrix{ComplexF64}, dE::Int, d::Int)
    out = zeros(ComplexF64, d, d)
    for e in 0:(dE - 1)
        r0 = e * d
        for i in 1:d, j in 1:d
            out[i, j] += M[r0 + i, r0 + j]
        end
    end
    return out
end

@testset "M11.DILATE.KRAUS-RECONSTRUCT" begin
    # U[i·d+1 : i·d+d, 1:d] ≈ Kᵢ for i < R, ≈ 0 for padded rows — this
    # assertion IS the contract; everything else follows algebraically.
    for fam in (bit_flip(0.3), depolarizing(0.5), amplitude_damping(0.4),
                phase_damping(0.2), _random_family(3, 42))
        dl = dilate(fam)
        ops = kraus_matrices(fam)
        R = length(ops)
        d = 2
        dE = size(dl.unitary, 1) ÷ d
        @test dl.rank == R
        for i in 0:(dE - 1)
            blk = dl.unitary[(i * d + 1):(i * d + d), 1:d]
            if i < R
                @test blk ≈ ops[i + 1] atol = 1e-14
            else
                @test maximum(abs.(blk)) ≤ 1e-14          # padded rows are 0
            end
        end
    end
end

@testset "M11.DILATE.ISOMETRY-UNITARY-EXACT-DETERMINISM" begin
    for fam in (bit_flip(0.25), amplitude_damping(0.6), _random_family(3, 7),
                _random_family(5, 99))
        dl = dilate(fam)
        V = dl.isometry
        # ISOMETRY: V†V ≈ I (TP ⟺ isometry).
        @test V' * V ≈ Matrix{ComplexF64}(I, 2, 2) atol = 1e-12
        # EXACT-COLUMNS: bitwise, not toleranced (S9).
        d = size(V, 2)
        @test dl.unitary[:, 1:d] == V
        # UNITARY: ‖U†U − I‖_∞ ≤ STINESPRING_ATOL.
        M = size(dl.unitary, 1)
        @test maximum(abs.(dl.unitary' * dl.unitary - Matrix{ComplexF64}(I, M, M))) ≤
              STINESPRING_ATOL
        # DETERMINISM: bitwise identical on a second call — no RNG, no drift.
        @test dilate(fam).unitary == dl.unitary
    end
end

@testset "M11.DILATE.ENV-LEADING" begin
    # The S10 pin on the NON-UNITAL ASYMMETRIC sentinel: amplitude damping.
    # Ṽ[i·d + s + 1, t + 1] = Kᵢ[s+1, t+1]: K₁'s single entry √γ|0⟩⟨1| must
    # sit at ROW 3 (env block i=1 leading), COLUMN 2. A system-first layout
    # would interleave it at row 2/4 — visibly different on this family.
    γ = 0.3
    dl = dilate(amplitude_damping(γ))
    V = dl.isometry
    @test size(V) == (4, 2)
    @test V[1, 1] ≈ 1 atol = 1e-14                       # K₀[1,1]
    @test V[2, 2] ≈ sqrt(1 - γ) atol = 1e-14             # K₀[2,2]
    @test V[3, 2] ≈ sqrt(γ) atol = 1e-14                 # K₁[1,2] at env-block row 3
    @test abs(V[4, 2]) ≤ 1e-14                           # NOT row 4 (system-first trap)
    @test abs(V[2, 1]) ≤ 1e-14 && abs(V[3, 1]) ≤ 1e-14
end

@testset "M11.DILATE.DENOTES-THE-CHANNEL" begin
    # Matrix level, INCLUDING class-X families (the mathematics is total):
    # Tr_E[U(|0⟩⟨0|_E ⊗ ρ)U†] ≈ Σ K ρ K† for deterministic pseudo-random ρ.
    for fam in (bit_flip(0.2), amplitude_damping(0.5), phase_damping(0.35),
                _random_family(3, 13))
        dl = dilate(fam)
        ops = kraus_matrices(fam)
        d = 2
        dE = size(dl.unitary, 1) ÷ d
        for seed in (1, 2)
            G = ComplexF64[complex(sin(3.7seed + i + 2j), cos(1.3seed + 2i - j))
                           for i in 1:2, j in 1:2]
            ρ = G * G'; ρ ./= tr(ρ)
            full = zeros(ComplexF64, dE * d, dE * d)
            full[1:d, 1:d] = ρ                            # |0⟩⟨0|_E ⊗ ρ, env MSB
            lhs = _trace_env(dl.unitary * full * dl.unitary', dE, d)
            rhs = sum(K * ρ * K' for K in ops)
            @test lhs ≈ rhs atol = 1e-12
        end
    end
end

@testset "M11.DILATE.CHOI-EQUALS-KRAUS" begin
    # THREE-WAY agreement as channels: analytic value-level Choi ≡ native DM
    # (channel_1q) ≡ structured emission (dilate + region-exit trace on DM,
    # where the trace is EXACT). Class P with E=1 (bit_flip), E=2
    # (depolarizing, R=4 — prep tree + 4-way multiplex), and class D
    # (amplitude_damping — S14's gate-by-gate circuit).
    for fam in (bit_flip(0.3), depolarizing(0.5), amplitude_damping(0.3))
        Jval = choi_matrix(fam)
        Jnative = choi(q -> (apply_noise!(q, fam); q), 1)
        Jemit = choi(q -> (Sturm._emit_dilation!(q.ctx, fam, (q.wire,)); q), 1;
                     cap = 6)
        @test Jnative ≈ Jval atol = 1e-10
        @test Jemit ≈ Jval atol = 1e-10
    end
    # A W=2 MixedUnitary through the DM stinespring route (the class-P path
    # the native lowering cannot take): 0.7·I⊗I + 0.3·X⊗X on |00⟩.
    mu = MixedUnitary([0.7, 0.3], ProcessValue[I2 ⊗ I2, X ⊗ X])
    density(4) do ctx
        x = QInt{2}(0)
        Sturm.apply!(Sturm.contextof(x), mu, x.wires; stinespring = true)
        ρ = Sturm.density_matrix(Sturm.contextof(x))
        @test real(ρ[1, 1]) ≈ 0.7 atol = 1e-10            # |00⟩
        @test real(ρ[4, 4]) ≈ 0.3 atol = 1e-10            # |11⟩
        @test abs(ρ[1, 4]) ≤ 1e-10                        # a MIXTURE, not a cat state
        nothing
    end
end

@testset "M11.DILATE.CTRL-UNREACHABLE" begin
    dl = dilate(bit_flip(0.2))
    @test dl isa ChannelArtifact
    @test !(StinespringDilation <: ProcessValue)
    @test !(StinespringDilation <: ChannelValue)
    @test !(StinespringDilation <: Sturm.Node)
    @test_throws MethodError ctrl(dl)
    @test_throws MethodError adjoint(dl)
    @test_throws MethodError Sturm.ApplyN(dl, (Sturm.PortID(1),))
    # SOURCE LINT (the S11 choke point, mirroring the _ctrl lint): the emitter
    # is called only from its definition site and the context/noise.jl routes;
    # the artifact is constructed only inside dilate.
    src = joinpath(dirname(@__DIR__), "src")
    offenders = String[]
    for (root, _, files) in walkdir(src), f in files
        endswith(f, ".jl") || continue
        path = joinpath(root, f)
        rel = relpath(path, src)
        txt = read(path, String)
        if occursin("_emit_dilation!(", txt) &&
           rel ∉ ("channel/stinespring.jl", "context/noise.jl")
            push!(offenders, "emit:" * rel)
        end
        if occursin("StinespringDilation{", txt) && rel != "channel/stinespring.jl"
            push!(offenders, "construct:" * rel)
        end
    end
    @test isempty(offenders)
end

@testset "M11.DILATE.ENV-OWNERSHIP" begin
    # live_wires returns to baseline, and 100 sequential dilated applications
    # neither leak wires nor exhaust the 3-slot capacity (slot recycling —
    # a leak would error long before 100 iterations).
    eager(3) do ctx
        u = QBool(0.5)
        base = length(live_wires(ctx))
        for _ in 1:100
            apply_noise!(u, bit_flip(0.1); stinespring = true)
        end
        @test length(live_wires(ctx)) == base
        Bool(u)                                           # consume before exit
        nothing
    end
end

@testset "M11.DILATE.CATALOGUE-BOUNDARY" begin
    # Class X throws, naming the missing kernel capability and the escapes.
    eager(3) do _
        u = QBool(0.5)
        err = try
            apply_noise!(u, phase_damping(0.3); stinespring = true); nothing
        catch e; e end
        @test err isa ErrorException
        msg = sprint(showerror, err)
        @test occursin("class X", msg)
        @test occursin("unitary_kq", msg)
        @test occursin("density", msg)
        nothing
    end
end

@testset "M11.DILATE.EAGER-TRAJECTORY" begin
    # Deterministic endpoints: γ=1 damping always decays |1⟩→|0⟩; p=1 bit flip
    # always flips. One run = one trajectory (S16) — at the deterministic
    # points every trajectory agrees.
    eager(2) do _
        u = QBool(true)
        apply_noise!(u, amplitude_damping(1.0); stinespring = true)
        @test Bool(u) == false
        nothing
    end
    eager(2) do _
        u = QBool(false)
        apply_noise!(u, bit_flip(1.0); stinespring = true)
        @test Bool(u) == true
        nothing
    end
    # Statistical: p=0.3 bit flip on |0⟩ reads true with frequency p ± 3σ.
    N = 1000
    cnt = 0
    for i in 1:N
        cnt += eager(2) do _
            u = QBool(false)
            apply_noise!(u, bit_flip(0.3); stinespring = true)
            Bool(u) ? 1 : 0
        end
    end
    σ = sqrt(0.3 * 0.7 / N)
    @test abs(cnt / N - 0.3) < 3σ
end

@testset "M11.DILATE.CLASS-D-SIGN-PIN" begin
    # R1: the emitted class-D circuit reproduces K₁ = +√γ|0⟩⟨1| at the MATRIX
    # level (a −√γ sign is the SAME channel and would pass every Choi test —
    # only a matrix-level pin can see it). Test-side composite: the emitter's
    # two ops on (sys ⊗ env), sys = MSB: ctrl(Ry(2θ)) sys→env, then ctrl(X)
    # env→sys; extract Kᵢ[s',s] = W[(s'−1)·2 + i + 1, (s−1)·2 + 1].
    γ = 0.4
    θ = asin(sqrt(γ))
    Rymat = [cos(θ) -sin(θ); sin(θ) cos(θ)]
    M1 = zeros(ComplexF64, 4, 4)                          # ctrl(Ry(2θ)), control = sys
    M1[1:2, 1:2] = Matrix(I, 2, 2)                        # sys=0: identity on env
    M1[3:4, 3:4] = Rymat                                  # sys=1: rotate env
    M2 = zeros(ComplexF64, 4, 4)                          # ctrl(X), control = env (LSB)
    for s in 0:1, e in 0:1
        s2 = e == 1 ? (1 - s) : s
        M2[s2 * 2 + e + 1, s * 2 + e + 1] = 1
    end
    W = M2 * M1
    K0 = ComplexF64[W[(s2 - 1) * 2 + 1, (s - 1) * 2 + 1] for s2 in 1:2, s in 1:2]
    K1 = ComplexF64[W[(s2 - 1) * 2 + 2, (s - 1) * 2 + 1] for s2 in 1:2, s in 1:2]
    ops = kraus_matrices(amplitude_damping(γ))
    @test K0 ≈ ops[1] atol = 1e-12
    @test K1 ≈ ops[2] atol = 1e-12                        # the + sign, exactly
end
