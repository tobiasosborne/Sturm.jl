# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M6 (bead Sturm.jl-80g6): the `QFT`
# process value — the character-group basis change F_G for a `QInt{W}` register
# (G = ℤ_{2^W}), and the phase-gate constant `P(θ)` its lowering ladder is built
# from. `QFT` is the F ≠ F† dual transform that `_dual_transform(::QInt{W})`
# returns (kernel/views.jl); it is the value that makes `dual(x)` for an integer
# register the discrete Fourier view (PRD-v2 §3.3), the analogue of `H` for the
# self-dual ℤ₂ `QBool`.
#
# TWO OBLIGATIONS, ONE VALUE. The DENOTATION is the analytic DFT matrix
# (`denoted_matrix`, the reference semantics); the EMISSION is the exact
# H / ctrl-phase ladder + bit-reversal swaps (`_emit!`), whose obligation is to
# AGREE with the denotation. One cross-check test (basis sweep W ≤ 3 vs the
# denoted matrix) localises any convention slip — the U2-T0 discipline applied to
# a multi-wire value.
#
# THE CHOKE POINT STAYS HONEST. Every phase in the ladder is a `ctrl(P(θ))`
# routed through the EXISTING `_apply_controlled_u2!` (orkan/ad.jl): this file
# adds NO new controlled-lowering code path — it reuses the one M1/M2 built. For
# θ = π the inner `P(π) = Z`, so the ladder's coarsest phase is a native `cz`;
# finer phases take the ABC + phase-line path (Barenco Lemma 5.2), phase-exact.
#
# NO ctrl(::QFT) at M6. A controlled QFT appears only in phase estimation (M8);
# an attempt is an honest `MethodError` (the no-catch-all discipline of
# kernel/ctrl.jl), not a silent wrong wrap.
#
# Physics grounding:
#   docs/physics/chen_stoudenmire_white_qft_entanglement.md — the QFT F_n =
#     R_n Q_n factorisation (the H/phase core Q_n plus the bit-reversal R_n);
#     the core is NOT a tensor product across any register cut, which is why
#     `dual(x)[i]` (a per-wire local of the register dual) does not exist.
#   docs/physics/wharton_koch_quaternion_bloch.md — the pinned U(2) convention
#     that `P(θ) = gphase(θ/2) ∘ Rz(θ) = diag(1, e^{iθ})` is written under.
#   docs/physics/delorme_control_as_constructor.md — control-as-constructor: the
#     ladder's ctrl-phases are `ctrl(P(θ))` values, never hand-built diagonals.

"""
    P(θ) -> U2

The single-qubit phase gate `diag(1, e^{iθ})` as a `U2` value
`gphase(θ/2) ∘ Rz(θ)` (`Rz(θ) = diag(e^{−iθ/2}, e^{iθ/2})`, lifted by the
`e^{iθ/2}` global phase onto the |0⟩ = 1 gauge). Kernel `public`, the phase
primitive the `QFT` ladder and the Draper modulation `D_a` are composed from
(PRD-v2 §3.3/§4.1; `docs/physics/wharton_koch_quaternion_bloch.md`). `P(π) = Z`
exactly (`ctrl(P(π))` → native `cz`); `P(2π k) = I`.
"""
P(θ::Real) = gphase(θ / 2) ∘ Rz(θ)

"""
    QFT(n, inv)   [kernel public; construct via `_dual_transform(::QInt)`]

The discrete Fourier transform `F` on `ℤ_{2^n}` as a process value: the
character-group basis change of an `n`-wire integer register (`n` in a FIELD,
mirroring `Perm`, because register width is runtime-dynamic under the single
type parameter `QInt{W}`). `inv = false` is the forward `F` (`ω = e^{+2πi/2^n}`);
`inv = true` is `F† = conj(F)` (`F` is symmetric, so its adjoint is its
elementwise conjugate). `adjoint` flips the flag — it never *applies* `F` (views
unwrap; processes compose — PRD-v2 §3.3).

Denotation: `F[k, j] = 2^{−n/2} · ω^{± j k}` (`+` forward, `−` inverse). Emission
(`_emit!`, orkan/ad.jl-grade lowering): the standard H / ctrl-phase ladder with a
trailing bit-reversal so the emitted unitary EQUALS the denoted DFT
(`docs/physics/chen_stoudenmire_white_qft_entanglement.md`, `F_n = R_n Q_n`).
"""
struct QFT <: ProcessValue
    n::Int
    inv::Bool
end

nwires(f::QFT) = f.n
Base.adjoint(f::QFT) = QFT(f.n, !f.inv)

"""
    denoted_matrix(f::QFT) -> Matrix{ComplexF64}

The `2^n × 2^n` analytic DFT matrix `F[k, j] = 2^{−n/2} ω^{± j k}`
(`ω = e^{2πi/2^n}`; sign `+` forward, `−` inverse), row `k` = image basis index,
column `j` = input basis index. THIS is the semantics; `_emit!`'s circuit must
agree with it (the QFT convention anchor). Off the hot path (test/Ad
cross-checks only); dependency-free `ComplexF64` build (CLAUDE.md Julia-conv 4).
"""
function denoted_matrix(f::QFT)
    N = 1 << f.n
    s = f.inv ? -1.0 : 1.0
    invsqrtN = 1.0 / sqrt(N)
    M = Matrix{ComplexF64}(undef, N, N)
    for j in 0:(N - 1), k in 0:(N - 1)
        M[k + 1, j + 1] = invsqrtN * cis(s * 2π * j * k / N)
    end
    return M
end

"""
    _emit!(ctx, f::QFT, qs)

Lower `F` (or `F†`) onto Orkan slots `qs` (`qs[1]` = the register's MSB wire,
per the `apply!` position convention). The textbook ladder: for each wire `j`
(MSB→LSB) an `H`, then ctrl-phases `ctrl(P(±2π / 2^{k−j+1}))` from every less-
significant wire `k`, then a bit-reversal of `⌊n/2⌋` swaps so the emitted
unitary equals the *denoted* forward/inverse DFT (not its bit-reversed cousin).
`f.inv` negates every phase angle — since `H` and `SWAP` are real and `F` is
symmetric, negating the phases yields `conj(F) = F†` in the SAME gate order.

Every ctrl-phase is a `ctrl(P(θ))` value handed to the EXISTING
`_apply_controlled_u2!` (Barenco Lemma 5.1/5.2) — no new controlled-lowering
code. Lives under `src/orkan/`-grade emission but in `src/kernel/` (an allowed
region for the choke-point lint); called only by `apply!`/`_emit!` dispatch.
"""
function _emit!(ctx::AbstractContext, f::QFT, qs::Vector{Int})
    n = f.n
    sgn = f.inv ? -1.0 : 1.0
    @inbounds for j in 1:n
        _emit_h!(ctx, qs[j])
        for k in (j + 1):n
            θ = sgn * 2π / (1 << (k - j + 1))     # R_{k-j+1}: fires when both wires are |1⟩
            _apply_controlled_u2!(ctx, qs[k], P(θ), qs[j])
        end
    end
    @inbounds for j in 1:(n ÷ 2)
        _emit_swap!(ctx, qs[j], qs[n + 1 - j])   # bit-reversal R_n (CSW: a free reindex)
    end
    nothing
end
