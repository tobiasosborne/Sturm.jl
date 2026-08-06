# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# Sturm.jl M11 (bead Sturm.jl-qmpo), design docs/design/m11-82su-synthesis.md
# §6 "Channel values": the stratum-2 value tree — construction discipline (TP
# checked, never renormalised), the denotation quotient `channel`, the semantic
# comparison `same_channel` vs structural `==`, the named convention-pinned
# families, and the §4.4 stratification enforced BY CONSTRUCTION (every cross-
# stratum operation a MethodError). Slice-1 scope: values only; application
# (`apply_noise!`), Stinespring, and QECC land in later slices with their own
# testsets in this file and its siblings.

using Test
using LinearAlgebra
using Sturm
using Sturm: KrausFamily, MixedUnitary, ChannelTensor, ChannelSeq, ChannelValue,
    kraus_matrices, choi_matrix, channel, same_channel, krausrank,
    bit_flip, phase_flip, pauli_channel, depolarizing, dephasing,
    phase_damping, amplitude_damping, reset_channel, pinch_channel,
    KRAUS_TP_ATOL, ProcessValue, ctrl, ⊗, I2, X, Y, Z, H, gphase, nwires

const _MI = ComplexF64[1 0; 0 1]
const _MX = ComplexF64[0 1; 1 0]

# The normalized Choi state of Ad_U (out = MSB factor), built independently of
# src (principle 3: an independent reference, not a pinned number).
function _choi_of_unitary(U::Matrix{ComplexF64})
    d = size(U, 1)
    Ω = zeros(ComplexF64, d * d)
    for i in 1:d
        Ω[(i - 1) * d + i] = 1 / sqrt(d)          # |i⟩_out |i⟩_ref, out = MSB
    end
    V = kron(U, Matrix{ComplexF64}(I, d, d)) * Ω
    return V * V'
end

@testset "M11.KRAUS.TP-CHECK" begin
    # A 1e-3 TP deviation throws, NAMING the deviation; 1e-16 constructs.
    p = 0.3
    bad = [sqrt(1 - p) .* _MI, sqrt(p + 1e-3) .* _MX]
    err = try
        KrausFamily(bad); nothing
    catch e; e end
    @test err isa ArgumentError
    @test occursin("Σᵢ Kᵢ†Kᵢ − I", sprint(showerror, err))
    @test occursin("not trace-preserving", sprint(showerror, err))
    # Numerically clean input constructs (residual ≲ 1e-16 ≪ 1e-12).
    good = KrausFamily([sqrt(1 - p) .* _MI, sqrt(p) .* _MX])
    @test krausrank(good) == 2
    @test nwires(good) == 1
    # Roundtrip: frozen row-major storage reconstructs the operators exactly.
    @test kraus_matrices(good) ≈ [sqrt(1 - p) .* _MI, sqrt(p) .* _MX] atol = 0
end

@testset "M11.KRAUS.NO-SILENT-RENORM" begin
    # The rejection message must state Sturm never renormalises — and must NOT
    # offer to rescale. (S4: a silent renormalisation would silently change
    # which channel the user gets.)
    err = try
        KrausFamily([0.9 .* _MI]); nothing
    catch e; e end
    @test err isa ArgumentError
    msg = sprint(showerror, err)
    @test occursin("never renormalises", msg)
    # And the constructed family really is bit-exact what was passed in — no
    # method rescaled on the way through.
    K = [sqrt(0.7) .* _MI, sqrt(0.3) .* _MX]
    @test kraus_matrices(KrausFamily(K)) == K
end

@testset "M11.CHANNEL.AD-KERNEL" begin
    # ker(Ad) = U(1) at the VALUE level: the two values differ structurally,
    # while their denotations are the same channel (§4.3 — application forgets
    # the phase; the value does not).
    a = channel(gphase(π / 3))
    b = channel(Sturm.I2)
    @test a != b
    @test same_channel(a, b)
    # And a value ctrl CAN see stays distinct semantically too: gphase under
    # control is a relative phase (Tang–Wright), but channel() has already
    # crossed the quotient — the CHANNEL is the identity. The value-level `!=`
    # above is what keeps the distinction recoverable upstream.
    @test krausrank(a) == 1
end

@testset "M11.CHANNEL.CHOI-1Q" begin
    # choi_matrix(bit_flip(p)) ≈ (1−p)·J(id) + p·J(Ad_X), several p — analytic,
    # with J built by an independent test-side construction.
    Jid = _choi_of_unitary(_MI)
    Jx = _choi_of_unitary(_MX)
    for p in (0.0, 0.1, 0.35, 0.5, 0.9, 1.0)
        @test choi_matrix(bit_flip(p)) ≈ (1 - p) .* Jid .+ p .* Jx atol = 1e-12
    end
    # depolarizing PIN (S8): ρ ↦ (1−p)ρ + p·I/2 ⇒ J = (1−p)·J(id) + p·I₄/4.
    for p in (0.0, 0.2, 1.0)
        @test choi_matrix(depolarizing(p)) ≈
              (1 - p) .* Jid .+ (p / 4) .* Matrix{ComplexF64}(I, 4, 4) atol = 1e-12
    end
    # Choi state sanity: trace 1, Hermitian.
    J = choi_matrix(amplitude_damping(0.3))
    @test tr(J) ≈ 1 atol = 1e-12
    @test J ≈ J' atol = 1e-14
end

@testset "M11.CHANNEL.COMPOSE" begin
    # bit_flip(p) ∘ bit_flip(q) is bit_flip(p+q−2pq) — exact, analytic.
    for (p, q) in ((0.1, 0.25), (0.5, 0.5), (0.0, 0.7))
        @test same_channel(bit_flip(p) ∘ bit_flip(q), bit_flip(p + q - 2p * q))
    end
    # Width mismatch is loud.
    @test_throws ArgumentError bit_flip(0.1) ∘ (bit_flip(0.1) ⊗ bit_flip(0.2))
    # ⊗ widths add; ∘ of a Seq keeps width.
    t = bit_flip(0.1) ⊗ phase_flip(0.2)
    @test nwires(t) == 2
    @test t isa ChannelTensor
    @test nwires(bit_flip(0.1) ∘ bit_flip(0.2)) == 1
    # ChannelSeq rank multiplies with b-first order; kraus of Seq = pairwise
    # products Ka*Kb.
    s = amplitude_damping(0.3) ∘ bit_flip(0.2)
    @test length(kraus_matrices(s)) == 4
end

@testset "M11.CHANNEL.KRAUS-FREEDOM" begin
    # A unitary mixing u of the operators is a DIFFERENT value of the SAME
    # channel (Watrous Cor. 2.24) — the F26 split, with teeth.
    γ = 0.4
    ad = amplitude_damping(γ)
    K = kraus_matrices(ad)
    mixed = KrausFamily([(K[1] .+ K[2]) ./ sqrt(2), (K[1] .- K[2]) ./ sqrt(2)];
                        label = :mixed_ad)
    @test mixed != ad
    @test same_channel(mixed, ad)
end

@testset "M11.CHANNEL.MIXED-UNITARY" begin
    # The distinct dispatchable class (S2): construction validation, exact
    # agreement with the equivalent KrausFamily, and ∘/⊗ CLOSURE.
    p = 0.15
    mu = MixedUnitary([1 - p, p], ProcessValue[I2, X])
    @test same_channel(mu, bit_flip(p))
    # TP-of-mixture = unit weight sum; never renormalised.
    err = try
        MixedUnitary([0.5, 0.4], ProcessValue[I2, X]); nothing
    catch e; e end
    @test err isa ArgumentError
    @test occursin("never renormalises", sprint(showerror, err))
    @test_throws ArgumentError MixedUnitary([0.5, 0.5], ProcessValue[I2, X ⊗ X])
    # Closure: MixedUnitary ∘ MixedUnitary and ⊗ stay MixedUnitary (the
    # channel-level ctrl(Perm)=Perm analogue), with exact kernel products.
    mu2 = MixedUnitary([0.5, 0.5], ProcessValue[I2, Z])
    c = mu ∘ mu2
    @test c isa MixedUnitary
    @test same_channel(c, bit_flip(p) ∘ phase_flip(0.5))
    t = mu ⊗ mu2
    @test t isa MixedUnitary
    @test nwires(t) == 2
end

@testset "M11.CHANNEL.FAMILY-PINS" begin
    # dephasing / phase_damping are one family under λ_deph = 1 − √(1−λ_damp).
    λd = 0.3
    @test same_channel(dephasing(1 - sqrt(1 - λd)), phase_damping(λd))
    # dephasing(1) IS the pinch.
    @test same_channel(dephasing(1.0), pinch_channel())
    # phase_flip(p) = dephasing(2p) for p ≤ 1/2 (off-diagonal factor 1−2p).
    @test same_channel(phase_flip(0.2), dephasing(0.4))
    # reset: ρ ↦ |0⟩⟨0| — Choi is |0⟩⟨0| ⊗ I/2 (out = MSB).
    Jr = choi_matrix(reset_channel())
    @test Jr ≈ kron(ComplexF64[1 0; 0 0], Matrix{ComplexF64}(I, 2, 2) ./ 2) atol = 1e-14
    # Domain checks are DomainErrors (Base convention).
    @test_throws DomainError bit_flip(1.5)
    @test_throws DomainError depolarizing(-0.1)
    @test_throws DomainError pauli_channel(0.5, 0.4, 0.3)
end

@testset "M11.CHANNEL.STRATIFICATION" begin
    # Every cross-stratum operation is a MethodError BY CONSTRUCTION — zero
    # lines were added to the choke point to achieve this.
    𝓝 = bit_flip(0.1)
    @test_throws MethodError ctrl(𝓝)
    @test_throws MethodError adjoint(𝓝)
    # `Base.:∘` has a generic ComposedFunction fallback for ANY pair, so the
    # mixed compositions are EXPLICIT loud refusals (they cannot be left to
    # MethodError — that fallback would silently build garbage).
    err = try
        X ∘ 𝓝; nothing
    catch e; e end
    @test err isa ArgumentError
    @test occursin("quotient", sprint(showerror, err))
    @test_throws ArgumentError 𝓝 ∘ X
    # `⊗` is Sturm-owned with no catch-all: no-method IS the refusal.
    @test_throws MethodError 𝓝 ⊗ X
    @test_throws MethodError X ⊗ 𝓝
    @test !(KrausFamily <: ProcessValue)
    @test !(MixedUnitary <: ProcessValue)
    # ApplyN carries process values only; a channel value cannot ride it.
    @test_throws MethodError Sturm.ApplyN(𝓝, (Sturm.PortID(1),))
    # certify refuses a NoiseN-bearing DAG (barrier — M8 discipline, re-pinned
    # here against the REAL family).
    b = Sturm.DAGBuilder()
    w = Sturm.input!(b)
    Sturm.noise!(b, 𝓝, w)
    @test Sturm.has_barrier(Sturm.freeze(b))
    @test_throws ArgumentError Sturm.certify(b)
    # NoiseN width-checks against the real channel.
    @test_throws ErrorException Sturm.NoiseN(𝓝, (Sturm.PortID(1), Sturm.PortID(2)))
    # No Base.isapprox on channel values (S6): the O(4^W) comparison must be
    # asked for by name.
    @test_throws MethodError 𝓝 ≈ bit_flip(0.1)
end
