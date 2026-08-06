# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M11 (bead Sturm.jl-qmpo), design
# `docs/design/m11-82su-synthesis.md` §3.2 (rulings S9–S16): the STINESPRING
# DILATION — the F33 contract made concrete.
#
# THE CHOKE POINT. `_emit_dilation!` is the ONLY consumer of a
# `StinespringDilation`, and this file is the only site allowed to construct
# one (source-linted — `test_m11_stinespring.jl`, mirroring the `_ctrl` lint).
# A dilation is a `ChannelArtifact`: it subtypes NEITHER `ProcessValue` NOR
# `ChannelValue` NOR `Node` (S11) — the unitary completion is an ARBITRARY
# choice (Watrous Cor. 2.24: Kraus/Stinespring freedom), so controlling it,
# composing it, or recording it in the IR would make observable results depend
# on a representation artifact. `ctrl(dilation)` is a MethodError by
# construction; the IR records the CHANNEL, never a dilation (S12).
#
# THE ENV-ORDERING PIN (S10 — normative in PRD-v2 §4.3 since session 104; the
# qmpo bead note): environment wires LEAD (MSB).
#     Ṽ[i·d + s + 1, t + 1] = Kᵢ[s+1, t+1]
# This TRANSPOSES the cited source — Watrous (Cor. 2.27(5),
# docs/physics/watrous_2018_channel_representations.md) writes system-first
# `V|ψ⟩ = Σᵢ Kᵢ|ψ⟩|i⟩_E`. Same channel, DIFFERENT MATRIX. Do NOT "correct" the
# implementation back to the book: in the env-leading layout the env=|0…0⟩
# input columns are contiguously 1:d (`U[:,1:d] == Ṽ`, a block read), and the
# layout matches both `apply!`'s position-1-= -MSB and `Ctrl`'s leading-wires-
# are-controls — the executable tier's environment IS a multiplexing control,
# so the dense artifact and the structured emission agree with NO permutation
# between them. The pin is only TESTABLE on a non-unital asymmetric channel:
# amplitude damping is the sentinel (a Pauli channel is blind to the swap).
#
# COMPLETION ALGORITHM (S9): Householder QR of the isometry Ṽ, keep
# Q[:, d+1:M] as the orthogonal complement, then OVERWRITE U[:, 1:d] := Ṽ
# verbatim. Householder cannot fail on valid input (no rank-detection
# tolerance inside the algorithm — Gram–Schmidt's pivot tolerance was rejected
# for exactly that data-dependent loud-failure mode); the only tolerances are
# POST-conditions. First-d-column equality is thereby EXACT (a stronger test
# than ≈). Reference: Golub & Van Loan, Matrix Computations, §5.1–5.2
# (Householder QR; numerical linear algebra — no distillation owed).
#
# EXECUTABLE CATALOGUE (S14), 1-local dense families + any-width MixedUnitary:
#   class P (mixed-unitary): PREPARE |χ⟩_E = Σᵢ √pᵢ|i⟩ by the real-amplitude
#     binary Ry tree, then multiplexed ctrl^E(Uᵢ) with X-sandwich anti-controls.
#   class D (amplitude damping): ctrl(Ry(2θ)) sys→env with sinθ = √γ, then
#     ctrl(X) env→sys. Verified gate-by-gate in the synthesis; R1 (the kernel
#     Ry sign convention Ry(2θ)|0⟩ = cosθ|0⟩ + sinθ|1⟩) verified against
#     kernel/constants.jl:81 — q = (cos(γ/2), 0, sin(γ/2), 0), so the matrix is
#     [[cosθ, −sinθ],[sinθ, cosθ]] at γ = 2θ: positive sin on |0⟩, as assumed.
#   class X (everything else): a LOUD error naming the missing capability and
#     the escapes. General k-local emission is gated on Orkan `unitary_kq`
#     (ruling T6 — approved, scheduled after M11).
#
# ENVIRONMENT OWNERSHIP (S15): `_emit_dilation!` opens an internal region;
# env wires are allocated inside and traced at its exit (§3.9 made literal).
# Nothing escapes; `keep_environment` does not exist. On Eager the dilation +
# region-exit trace IS the quantum-jump unravelling: ONE RUN IS ONE
# TRAJECTORY, NOT THE CHANNEL (S16) — stated in the apply! error message and
# docstrings; `shots` is the sampling recovery, `density` the exact one.

"""
    ChannelArtifact

Abstract supertype for execution/lowering ARTIFACTS (S11): objects derived
from a channel value for a specific lowering, carrying representation choices
that are NOT part of the channel's identity (a dilation's unitary completion,
a future synthesized block or pulse schedule). Deliberately outside both the
`ProcessValue` and `ChannelValue` trees: `ctrl`/`adjoint`/`∘`/`⊗`/`ApplyN` on
an artifact are MethodErrors by construction, and no artifact ever enters a
`ChannelDAG`.
"""
abstract type ChannelArtifact end

"""
    DilationProgram

The structured (executable) emission recipe attached to a dilation — class P
(`:mixedu`: weights + kernel process values) or class D (`:damping`: γ). An
internal payload of [`StinespringDilation`](@ref); never user-facing.
"""
struct DilationProgram
    kind::Symbol                        # :mixedu | :damping
    weights::Vector{Float64}            # :mixedu
    unitaries::Vector{ProcessValue}     # :mixedu — kernel values (ctrl-able)
    γ::Float64                          # :damping
end

const STINESPRING_ATOL = U2_ATOL        # 1e-10 — the §4.1 float-law scale
const DILATION_MAXWIRES = 8             # W + E cap (dense artifact ≤ 256×256)

"""
    StinespringDilation{W,E} <: ChannelArtifact

The Stinespring dilation of a W-wire channel value with an E-wire environment
(F33): `isometry` Ṽ (`2^{W+E} × 2^W`, ENV LEADING — S10) with
`Ṽ[i·d+s+1, t+1] = Kᵢ[s+1, t+1]`, and its `unitary` completion U
(`U[:, 1:d] == Ṽ` EXACTLY — S9; `‖U†U − I‖_∞ ≤ STINESPRING_ATOL` asserted at
construction). `rank` is the represented Kraus count (before padding to 2^E);
`program` is the structured emission recipe, or `nothing` for class X (the
dilation MATHEMATICS is total; executability is a catalogue).

An execution artifact, NEVER a representative of the channel (§4.4): the
completion columns `d+1:M` are an arbitrary orthonormal choice, so nothing may
control, compose, replay, or IR-record this object. Constructed by
[`dilate`](@ref) only; consumed by `_emit_dilation!` only (boot-linted).
"""
struct StinespringDilation{W,E} <: ChannelArtifact
    isometry::Matrix{ComplexF64}
    unitary::Matrix{ComplexF64}
    rank::Int
    program::Union{Nothing,DilationProgram}
end

# --- Matrix → U2 (the class-P detector's bridge into the kernel) --------------

"""
    _u2_from_matrix(M) -> U2

Recover the kernel `U2` value denoting the 2×2 unitary `M` (PINNED Wharton–Koch
convention, kernel/u2.jl): φ = arg(det M)/2, then Q = e^{−iφ}M ∈ SU(2) reads
off the quaternion. The caller must have verified `M` IS unitary (within
`STINESPRING_ATOL`); the checked `U2` constructor re-asserts the norm. The ℤ₂
representative choice (φ vs φ+π) is irrelevant — both denote `M` exactly.
"""
function _u2_from_matrix(M::AbstractMatrix)
    detM = M[1, 1] * M[2, 2] - M[1, 2] * M[2, 1]
    φ = angle(detM) / 2
    e = cis(-φ)
    q11 = e * M[1, 1]; q12 = e * M[1, 2]
    q21 = e * M[2, 1]; q22 = e * M[2, 2]
    w = (real(q11) + real(q22)) / 2
    z = (imag(q22) - imag(q11)) / 2
    x = -(imag(q12) + imag(q21)) / 2
    y = (real(q21) - real(q12)) / 2
    return U2(w, x, y, z, φ)
end

# --- Catalogue classification (S14) -------------------------------------------

# Class D: the amplitude-damping shape {diag(1, √(1−γ)), √γ|0⟩⟨1|} (either
# operator order). Returns γ, or `nothing`. Strict shape check at 1e-12: the
# catalogue matches what the named constructor (or a bit-identical user family)
# builds — near-misses fall through to class P/X honestly.
function _damping_gamma(ops::Vector{Matrix{ComplexF64}})
    length(ops) == 2 || return nothing
    size(ops[1]) == (2, 2) || return nothing
    for (a, b) in ((ops[1], ops[2]), (ops[2], ops[1]))
        # a = diag(1, √(1−γ)); b = √γ|0⟩⟨1|
        abs(a[1, 1] - 1) <= 1e-12 || continue
        abs(a[1, 2]) <= 1e-12 && abs(a[2, 1]) <= 1e-12 || continue
        abs(b[1, 1]) <= 1e-12 && abs(b[2, 1]) <= 1e-12 && abs(b[2, 2]) <= 1e-12 || continue
        g = b[1, 2]
        (abs(imag(g)) <= 1e-12 && real(g) >= 0) || continue
        γ = real(g)^2
        c = a[2, 2]
        (abs(imag(c)) <= 1e-12 && abs(real(c) - sqrt(max(1 - γ, 0.0))) <= 1e-12) || continue
        return γ
    end
    return nothing
end

# Class P from a dense 1-local family: every Kᵢ = √pᵢ·Uᵢ with Uᵢ unitary.
# Zero-weight operators (dead branches) pass with Uᵢ = I. Returns a
# `DilationProgram` or `nothing`.
function _mixedu_program(ops::Vector{Matrix{ComplexF64}})
    weights = Float64[]
    values = ProcessValue[]
    for K in ops
        size(K) == (2, 2) || return nothing
        p = real(sum(abs2, K)) / 2                     # tr(K†K)/d, d = 2
        if p <= 1e-24
            push!(weights, 0.0); push!(values, I2)     # dead branch
            continue
        end
        Uc = K ./ sqrt(p)
        # unitarity: ‖U†U − I‖_∞ ≤ STINESPRING_ATOL
        dev = 0.0
        for i in 1:2, j in 1:2
            s = conj(Uc[1, i]) * Uc[1, j] + conj(Uc[2, i]) * Uc[2, j]
            dev = max(dev, abs(s - (i == j ? 1.0 : 0.0)))
        end
        dev <= STINESPRING_ATOL || return nothing
        push!(weights, p); push!(values, _u2_from_matrix(Uc))
    end
    return DilationProgram(:mixedu, weights, values, 0.0)
end

_classify(ch::MixedUnitary) =
    DilationProgram(:mixedu, collect(ch.weights), collect(ch.unitaries), 0.0)
function _classify(ch::ChannelValue)
    nwires(ch) == 1 || return nothing        # dense multi-wire: MixedUnitary or bust (M11)
    ops = kraus_matrices(ch)
    γ = _damping_gamma(ops)
    γ === nothing || return DilationProgram(:damping, Float64[], ProcessValue[], γ)
    return _mixedu_program(ops)
end

# --- The unitary completion (S9) ----------------------------------------------

# Householder QR of the M×d isometry: returns the full M×M Q = H₁⋯H_d applied
# to I. Columns d+1:M span span(V)^⊥ exactly by construction; no tolerance
# inside the algorithm. Plain loops — core takes no LinearAlgebra (V4).
function _householder_q(V::Matrix{ComplexF64})
    M, d = size(V)
    A = copy(V)
    vs = Vector{Vector{ComplexF64}}(undef, d)
    for k in 1:d
        n = M - k + 1
        x = Vector{ComplexF64}(undef, n)
        for i in 1:n
            x[i] = A[k + i - 1, k]
        end
        nx = sqrt(sum(abs2, x))
        ph = x[1] == 0 ? one(ComplexF64) : x[1] / abs(x[1])
        α = -ph * nx
        v = x; v[1] -= α
        nv2 = sum(abs2, v)
        if nv2 > 0
            s = inv(sqrt(nv2))
            for i in 1:n
                v[i] *= s
            end
            for j in k:d                       # apply H = I − 2vv† to A[k:M, k:d]
                acc = zero(ComplexF64)
                for i in 1:n
                    acc += conj(v[i]) * A[k + i - 1, j]
                end
                for i in 1:n
                    A[k + i - 1, j] -= 2 * acc * v[i]
                end
            end
        end
        vs[k] = v
    end
    Q = zeros(ComplexF64, M, M)
    for i in 1:M
        Q[i, i] = 1
    end
    for k in d:-1:1                            # Q := H_k Q, k = d..1 ⇒ Q = H₁⋯H_d
        v = vs[k]
        sum(abs2, v) == 0 && continue
        n = M - k + 1
        for j in 1:M
            acc = zero(ComplexF64)
            for i in 1:n
                acc += conj(v[i]) * Q[k + i - 1, j]
            end
            for i in 1:n
                Q[k + i - 1, j] -= 2 * acc * v[i]
            end
        end
    end
    return Q
end

"""
    dilate(ch::ChannelValue) -> StinespringDilation

Construct the Stinespring dilation of `ch` (F33): the env-leading isometry Ṽ
(S10 pin — see the file header), its Householder unitary completion with EXACT
first-`d` columns (S9), the Kraus rank, and the structured emission program
when `ch` is in the executable catalogue (S14; `nothing` for class X — the
MATHEMATICS is total, executability is a catalogue). Deterministic: no RNG, no
tie-breaking — two calls are bitwise identical. Post-conditions asserted:
`U[:,1:d] == Ṽ` exactly and `‖U†U − I‖_∞ ≤ STINESPRING_ATOL`.

The result is an execution ARTIFACT (S11): it cannot be controlled, composed,
adjointed, applied via `ApplyN`, or recorded in a `ChannelDAG` — all
MethodErrors by construction. Its single consumer is the private
`_emit_dilation!` choke point.
"""
function dilate(ch::ChannelValue)
    W = nwires(ch)
    ops = kraus_matrices(ch)
    R = length(ops)
    E = R == 1 ? 0 : ceil(Int, log2(R))
    W + E <= DILATION_MAXWIRES || throw(ArgumentError(
        "dilate: W + E = $(W + E) exceeds DILATION_MAXWIRES = $DILATION_MAXWIRES " *
        "(the dense artifact is 2^(W+E) square)"))
    d = 2^W
    M = 2^E * d
    V = zeros(ComplexF64, M, d)
    for (i, K) in enumerate(ops)               # env index i−1 LEADS (MSB) — S10
        r0 = (i - 1) * d
        for s in 1:d, t in 1:d
            V[r0 + s, t] = K[s, t]
        end
    end
    U = _householder_q(V)
    for t in 1:d                               # S9: first d columns are Ṽ, EXACTLY
        for r in 1:M
            U[r, t] = V[r, t]
        end
    end
    dev = 0.0                                  # post-condition: ‖U†U − I‖_∞
    for i in 1:M, j in 1:M
        s = zero(ComplexF64)
        for k in 1:M
            s += conj(U[k, i]) * U[k, j]
        end
        dev = max(dev, abs(s - (i == j ? 1.0 : 0.0)))
    end
    dev <= STINESPRING_ATOL || error(
        "dilate: unitary completion off by ‖U†U − I‖_∞ = $dev (> $STINESPRING_ATOL) — " *
        "numerical failure on a valid isometry; this is a bug, report it")
    return StinespringDilation{W,E}(V, U, R, _classify(ch))
end

# --- The emission choke point (S14/S15) ---------------------------------------

function _require_env_capacity(ctx::AbstractContext, E::Int)
    free = _core(ctx).capacity - length(_core(ctx).wire_to_slot)
    free >= E || error(
        "apply!: the Stinespring dilation needs $E environment wire(s) but only $free " *
        "slot(s) remain — raise the context capacity (the environment is internal " *
        "scratch, allocated and traced per application)")
    nothing
end

# Multi-controlled application of `v` selected on the env configuration `bits`
# (MSB-first over `env`): X-sandwich the 0-bits, wrap ctrl^E, apply to
# (env..., targets...). Kernel `Ctrl` reads leading wires as controls — the
# same convention as the env-leading pin (S10), so no permutation exists here.
function _emit_selected!(ctx::AbstractContext, env::Vector{WireID}, bits::Vector{Int},
                         v::ProcessValue, targets)
    for (j, b) in enumerate(bits)
        b == 0 && apply!(ctx, X, (env[j],))
    end
    val = v
    for _ in 1:length(env)
        val = ctrl(val)
    end
    apply!(ctx, val, (env..., targets...))
    for (j, b) in enumerate(bits)
        b == 0 && apply!(ctx, X, (env[j],))
    end
    nothing
end

# The real-amplitude binary preparation tree (S14 class P): |0⟩^E ↦ Σᵢ √pᵢ|i⟩,
# pᵢ ≥ 0, Σpᵢ = 1, i MSB-first over `env`. Level ℓ rotates env[ℓ] by
# Ry(2θ), cosθ = √(left/mass), controlled on the level-(ℓ−1) prefix. Dead
# branches (mass 0) emit nothing (deterministic; amplitude there is 0).
function _emit_prep_tree!(ctx::AbstractContext, env::Vector{WireID}, probs::Vector{Float64})
    _prep_node!(ctx, env, probs, 1, 1, length(probs), Int[])
    nothing
end

function _prep_node!(ctx::AbstractContext, env::Vector{WireID}, probs::Vector{Float64},
                     level::Int, lo::Int, hi::Int, prefix::Vector{Int})
    level > length(env) && return nothing
    mid = lo + (hi - lo + 1) ÷ 2 - 1
    left = 0.0
    for i in lo:mid
        left += probs[i]
    end
    right = 0.0
    for i in (mid + 1):hi
        right += probs[i]
    end
    mass = left + right
    mass <= 0 && return nothing                          # dead branch
    if right > 0
        θ = atan(sqrt(right), sqrt(left))                # cosθ = √(left/mass)
        _emit_selected!(ctx, env[1:(level - 1)], prefix, Ry(2θ), (env[level],))
    end
    _prep_node!(ctx, env, probs, level + 1, lo, mid, vcat(prefix, 0))
    _prep_node!(ctx, env, probs, level + 1, mid + 1, hi, vcat(prefix, 1))
    nothing
end

"""
    _emit_dilation!(ctx, ch::ChannelValue, wires) -> nothing

THE dilation consumer (S11 choke point; private, boot-linted): emit the
structured Stinespring program of `ch` onto `wires`, with the environment
allocated inside an internal region and TRACED at its exit (S15 — §3.9 made
literal; nothing escapes, `keep_environment` does not exist). Class X errors
loudly naming the missing capability and the escapes. On Eager the composite
(dilate + trace = measure-and-discard) is ONE quantum-jump unravelling per run,
NOT the channel (S16) — `density` is the exact route, `shots` the sampling one.
"""
function _emit_dilation!(ctx::AbstractContext, ch::ChannelValue,
                         wires::NTuple{K,WireID}) where {K}
    _assert_no_control(ctx, "Stinespring dilation emission")   # defence in depth (S11)
    prog = _classify(ch)
    if prog === nothing
        error("apply!: no executable Stinespring lowering for channel $(_chlabel(ch)) " *
              "(class X). The M11 catalogue emits mixed-unitary families (class P) and " *
              "amplitude damping (class D); a general emission needs the Orkan " *
              "`unitary_kq` entry (approved, scheduled after M11 — ruling T6). " *
              "Escapes: density(cap) executes 1-local families natively and exactly; " *
              "or rewrite the value as a MixedUnitary / ⊗ of catalogue factors.")
    end
    E = prog.kind === :damping ? 1 :
        (length(prog.weights) <= 1 ? 0 : ceil(Int, log2(length(prog.weights))))
    _require_env_capacity(ctx, E)
    _enter_region!(ctx)
    try
        env = WireID[allocate!(ctx) for _ in 1:E]
        if prog.kind === :damping
            θ = asin(sqrt(prog.γ))
            apply!(ctx, ctrl(Ry(2θ)), (wires[1], env[1]))   # sys controls env
            apply!(ctx, ctrl(X), (env[1], wires[1]))        # env controls sys
        else
            R = length(prog.weights)
            if E == 0
                R == 1 && apply!(ctx, prog.unitaries[1], wires)
            else
                probs = zeros(Float64, 2^E)
                for i in 1:R
                    probs[i] = prog.weights[i]
                end
                _emit_prep_tree!(ctx, env, probs)
                for i in 0:(R - 1)
                    prog.weights[i + 1] == 0 && continue     # dead branch
                    bits = Int[(i >> (E - j)) & 1 for j in 1:E]
                    _emit_selected!(ctx, env, bits, prog.unitaries[i + 1], wires)
                end
            end
        end
    finally
        _exit_region!(ctx, nothing)                          # env traced — S15
    end
    nothing
end
