# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M11 (bead Sturm.jl-qmpo), design
# `docs/design/m11-82su-synthesis.md` §3.1 (rulings S1–S8): CHANNEL VALUES —
# stratum 2 of PRD-v2 §4.4's three-level stratification (process values /
# channel REPRESENTATIONS / denotations).
#
# A `ChannelValue` is a definite REPRESENTATION of a CPTP map — an operator-sum
# (Kraus) family or a lazy composite of them. It is deliberately NOT a
# `ProcessValue` (S1): a channel's representation is non-unique exactly in the
# ways `ctrl` can see (Kraus unitary freedom, Watrous Cor. 2.24 —
# docs/physics/watrous_2018_channel_representations.md; Tang–Wright Thm 1.1 —
# docs/physics/tang_wright_2025_controlled_unitaries.md), so controlling one
# would make the observable result depend on an arbitrary representative.
# Therefore, BY CONSTRUCTION (zero lines added to the choke point):
#   `ctrl(::ChannelValue)`     is a MethodError,
#   `adjoint(::ChannelValue)`  is a MethodError,
#   `∘`/`⊗` mixing a ProcessValue with a ChannelValue is a MethodError (S7 —
#   the quotient `channel(v)` must be crossed EXPLICITLY, in the source).
#
# STRUCTS-EARLY / METHODS-LATE (the shipped Tensor/Seq pattern): this file is
# included after `kernel/perm.jl` and BEFORE `channel/dag.jl` (whose `NoiseN`
# carries a `ChannelValue`), so it holds the structs, validated constructors,
# constants, and every method needing only call-time-resolved generics
# (`nwires`, `denoted_matrix`, `Base.:∘`). The `⊗` methods live in
# `channel/channel_algebra.jl` (after `kernel/algebra.jl`, where `⊗` is born).
#
# Physics grounding: docs/physics/watrous_2018_channel_representations.md
# (Thm 2.22: Kraus ⟺ Stinespring ⟺ Choi; Cor. 2.21/2.27: minimal rank;
# Cor. 2.23/2.24: non-uniqueness / unitary freedom — TP is the ONLY
# construction obligation, CP is free from the operator-sum form).

"""
    ChannelValue

Abstract supertype of every channel-level value (PRD-v2 §4.4 stratum 2): a
definite *representation* of a CPTP map. Concrete kinds: [`KrausFamily`](@ref)
(operator-sum), [`MixedUnitary`](@ref) (convex mixture of process values),
[`ChannelTensor`](@ref) (lazy parallel), [`ChannelSeq`](@ref) (lazy series).

NOT a `ProcessValue`: `ctrl`, `adjoint`, and mixed `∘`/`⊗` with process values
are `MethodError`s by construction — control on a channel is unrepresentable
(P4, §4.4), and the denotation quotient `channel(v)` is never inverted.

Semantic comparison is [`same_channel`](@ref) (Choi-level, tolerance);
`==` stays exact structural equality (F26 — hashable, transitive, never
toleranced). `Base.isapprox` on channel values is deliberately UNDEFINED (S6):
an O(4^W) Choi construction must not hide behind an operator that looks cheap.
"""
abstract type ChannelValue end

"""
    KRAUS_TP_ATOL

Trace-preservation tolerance for [`KrausFamily`](@ref) construction (S4,
derived): `‖Σᵢ Kᵢ†Kᵢ − I‖_∞ ≤ 1e-12`. Construction residual for exact-arithmetic
families is ≲1e-15 at the shipped size range; a real user error (a dropped
normalization, a wrong √) is O(1e-2). 1e-12 sits three decades above the noise
floor and ten below any physical non-TP-ness. A violating family is REJECTED —
never silently renormalised (principle 1; renormalising would silently change
which channel the user gets).
"""
const KRAUS_TP_ATOL = 1e-12

"""
    KRAUS_MAXDATA

Frozen-storage ceiling for [`KrausFamily`](@ref): `R · 4^W ≤ 1024` complex
entries (S5). Beyond this an `NTuple` destroys inference (and a dense family
that size should be a lazy [`ChannelTensor`](@ref) of local factors instead —
i.i.d. noise NEVER needs a dense multi-wire family, ruling S1/V3).
"""
const KRAUS_MAXDATA = 1024

"""
    CHOI_ATOL

Default tolerance for [`same_channel`](@ref)'s Choi comparison: the §4.1
float-law scale (`U2_ATOL = 1e-10`), NOT the TP-construction scale.
"""
const CHOI_ATOL = 1e-10

"""
    CHANNEL_CHOI_MAXWIRES

Cap on [`choi_matrix`](@ref)/[`same_channel`](@ref) width: a W-wire Choi matrix
is `4^W × 4^W` dense complex (F25 — the memory budget sets the cap, never the
qubit ceiling). W = 5 is 16 MiB; W = 6 would be 4 GiB. Loud error above.
"""
const CHANNEL_CHOI_MAXWIRES = 5

"""
    KrausFamily{W,R,L}(data, label)

An operator-sum (Kraus) representation of a W-wire CPTP map: `R` operators of
size `2^W × 2^W`, frozen row-major concatenated in `data::NTuple{L,ComplexF64}`
with `L = R·4^W` (S5 — this IS Orkan's `kraus_t` buffer layout, so the DM path
copies once). `label` names the constructing family (`:bit_flip`, `:custom`, …)
for error messages and display; it participates in structural `==` honestly
(two same-data families constructed under different names are different
VALUES of the same channel — `same_channel` is the semantic comparison).

Construct via `KrausFamily(ops::Vector{<:AbstractMatrix}; label=:custom)`,
which validates: R ≥ 1; square operators of one power-of-2 size; the storage
ceiling [`KRAUS_MAXDATA`](@ref); and trace preservation
`‖Σᵢ Kᵢ†Kᵢ − I‖_∞ ≤ KRAUS_TP_ATOL` (the ONLY obligation — CP is free from the
operator-sum form, Watrous Thm 2.22). FAILS LOUD naming the deviation; never
renormalises (S4).
"""
struct KrausFamily{W,R,L} <: ChannelValue
    data::NTuple{L,ComplexF64}
    label::Symbol
    function KrausFamily{W,R,L}(data::NTuple{L,ComplexF64}, label::Symbol) where {W,R,L}
        (W isa Int && R isa Int && L isa Int) || throw(ArgumentError("KrausFamily: type parameters must be Ints"))
        W >= 1 || throw(ArgumentError("KrausFamily: need W ≥ 1 wires (got W=$W)"))
        R >= 1 || throw(ArgumentError("KrausFamily: need R ≥ 1 Kraus operators (got R=$R)"))
        L == R * 4^W || throw(ArgumentError("KrausFamily: L=$L ≠ R·4^W = $(R * 4^W)"))
        return new{W,R,L}(data, label)
    end
end

function KrausFamily(ops::AbstractVector{<:AbstractMatrix}; label::Symbol = :custom)
    R = length(ops)
    R >= 1 || throw(ArgumentError("KrausFamily: need ≥ 1 Kraus operator"))
    d = size(first(ops), 1)
    for (t, K) in enumerate(ops)
        size(K) == (d, d) || throw(ArgumentError(
            "KrausFamily: operator $t is $(size(K)); all must be square $(d)×$(d)"))
    end
    (d >= 2 && ispow2(d)) || throw(ArgumentError(
        "KrausFamily: operator dimension $d is not a power of 2 ≥ 2"))
    W = trailing_zeros(d)
    L = R * d * d
    L <= KRAUS_MAXDATA || throw(ArgumentError(
        "KrausFamily: R·4^W = $L exceeds KRAUS_MAXDATA = $KRAUS_MAXDATA; " *
        "represent i.i.d./local noise as a lazy ChannelTensor of local factors instead"))
    # TP check: ‖Σ K†K − I‖_∞ ≤ KRAUS_TP_ATOL. Plain loops — core takes no
    # LinearAlgebra dependency (V4).
    acc = zeros(ComplexF64, d, d)
    for K in ops
        for j in 1:d, i in 1:d
            s = zero(ComplexF64)
            for k in 1:d
                s += conj(K[k, i]) * K[k, j]
            end
            acc[i, j] += s
        end
    end
    dev = 0.0
    for j in 1:d, i in 1:d
        dev = max(dev, abs(acc[i, j] - (i == j ? 1.0 : 0.0)))
    end
    dev <= KRAUS_TP_ATOL || throw(ArgumentError(
        "KrausFamily($label): not trace-preserving — ‖Σᵢ Kᵢ†Kᵢ − I‖_∞ = $dev " *
        "(> KRAUS_TP_ATOL = $KRAUS_TP_ATOL). Fix the family; Sturm never renormalises."))
    data = Vector{ComplexF64}(undef, L)
    for (t, K) in enumerate(ops)
        o = (t - 1) * d * d
        for i in 1:d, j in 1:d                     # row-major within an operator
            data[o + (i - 1) * d + j] = K[i, j]
        end
    end
    return KrausFamily{W,R,L}(NTuple{L,ComplexF64}(data), label)
end

"""
    MixedUnitary{W,R}(weights, unitaries)

A convex mixture of process values: `ρ ↦ Σᵢ wᵢ Uᵢ ρ Uᵢ†` on W wires. Kept as a
DISTINCT type, not a `KrausFamily` flag (S2): it is exactly the class whose
Stinespring dilation is *executable* (class P of the S14 catalogue), and making
that a dispatch fact turns "your dilation cannot run" from a runtime surprise
into a method-table fact. Closed under `∘` and `⊗` — the channel-level analogue
of `ctrl(Perm) = Perm`.

Validates: R ≥ 1; weights ≥ 0 with `|Σwᵢ − 1| ≤ KRAUS_TP_ATOL` (TP for a
mixture IS unit total weight); every unitary on the same W wires. Never
renormalises.
"""
struct MixedUnitary{W,R} <: ChannelValue
    weights::NTuple{R,Float64}
    unitaries::NTuple{R,ProcessValue}
    function MixedUnitary{W,R}(weights::NTuple{R,Float64},
                               unitaries::NTuple{R,ProcessValue}) where {W,R}
        R >= 1 || throw(ArgumentError("MixedUnitary: need R ≥ 1 branches"))
        for (i, w) in enumerate(weights)
            (isfinite(w) && w >= 0) || throw(ArgumentError(
                "MixedUnitary: weight $i is $w; weights must be finite and ≥ 0"))
        end
        s = sum(weights)
        abs(s - 1) <= KRAUS_TP_ATOL || throw(ArgumentError(
            "MixedUnitary: weights sum to $s ≠ 1 (|Δ| > $KRAUS_TP_ATOL — not " *
            "trace-preserving). Fix the weights; Sturm never renormalises."))
        for (i, u) in enumerate(unitaries)
            nwires(u) == W || throw(ArgumentError(
                "MixedUnitary{$W}: unitary $i acts on $(nwires(u)) wires, not $W"))
        end
        return new{W,R}(weights, unitaries)
    end
end

function MixedUnitary(weights::AbstractVector{<:Real}, unitaries::AbstractVector{<:ProcessValue})
    length(weights) == length(unitaries) || throw(ArgumentError(
        "MixedUnitary: $(length(weights)) weights vs $(length(unitaries)) unitaries"))
    isempty(unitaries) && throw(ArgumentError("MixedUnitary: need R ≥ 1 branches"))
    W = nwires(first(unitaries))
    R = length(unitaries)
    return MixedUnitary{W,R}(NTuple{R,Float64}(Float64.(weights)),
                             NTuple{R,ProcessValue}(unitaries))
end

"""
    ChannelTensor(a, b)

Lazy parallel composite `a ⊗ b` of channel values — `a` on the leading (MSB)
wire block (the kernel `Tensor` convention). Lazy is LOAD-BEARING, not a
convenience (S1/V3): Orkan's only channel entry is 1-local (`channel_1q`), so
i.i.d. noise on W wires must reach the backend as W separate 1-local factors —
an eagerly-flattened `4^W` family could not be applied at all. Built by `⊗`
(`channel/channel_algebra.jl`).
"""
struct ChannelTensor{A<:ChannelValue,B<:ChannelValue} <: ChannelValue
    a::A
    b::B
end

"""
    ChannelSeq(a, b)

Lazy series composite `a ∘ b` of channel values — `b` runs FIRST (the kernel
`∘` convention). Requires equal widths. Built by `∘`.
"""
struct ChannelSeq{A<:ChannelValue,B<:ChannelValue} <: ChannelValue
    a::A
    b::B
    function ChannelSeq(a::A, b::B) where {A<:ChannelValue,B<:ChannelValue}
        nwires(a) == nwires(b) || throw(ArgumentError(
            "∘: channel widths differ ($(nwires(a)) vs $(nwires(b)) wires)"))
        return new{A,B}(a, b)
    end
end

# --- Structure ----------------------------------------------------------------

nwires(::KrausFamily{W}) where {W} = W
nwires(::MixedUnitary{W}) where {W} = W
nwires(t::ChannelTensor) = nwires(t.a) + nwires(t.b)
nwires(s::ChannelSeq) = nwires(s.a)

"""
    krausrank(f::KrausFamily) -> Int

The number of Kraus operators in this REPRESENTATION (not the minimal/Choi rank
— representations are non-unique, Watrous Cor. 2.23).
"""
krausrank(::KrausFamily{W,R}) where {W,R} = R

"""
    kraus_matrices(v::ChannelValue) -> Vector{Matrix{ComplexF64}}

The Kraus operators of `v`, materialised as dense matrices (COLD PATH — tests,
`choi_matrix`, the DM 1-local lowering; never a hot loop). For composites the
rank multiplies (`ChannelSeq`: pairwise products, `b` first) or the operators
kron (`ChannelTensor`, `a` = MSB block).
"""
function kraus_matrices(f::KrausFamily{W,R}) where {W,R}
    d = 2^W
    out = Vector{Matrix{ComplexF64}}(undef, R)
    for t in 1:R
        K = Matrix{ComplexF64}(undef, d, d)
        o = (t - 1) * d * d
        for i in 1:d, j in 1:d
            K[i, j] = f.data[o + (i - 1) * d + j]
        end
        out[t] = K
    end
    return out
end

kraus_matrices(m::MixedUnitary{W,R}) where {W,R} =
    Matrix{ComplexF64}[sqrt(m.weights[i]) .* denoted_matrix(m.unitaries[i]) for i in 1:R]

kraus_matrices(t::ChannelTensor) =
    Matrix{ComplexF64}[kron(Ka, Kb) for Ka in kraus_matrices(t.a) for Kb in kraus_matrices(t.b)]

kraus_matrices(s::ChannelSeq) =
    Matrix{ComplexF64}[Ka * Kb for Ka in kraus_matrices(s.a) for Kb in kraus_matrices(s.b)]

# --- Denotation and semantic comparison ---------------------------------------

"""
    channel(v::ProcessValue) -> KrausFamily

The denotation quotient §4.4 promises: `Ad_v` as a rank-1 operator-sum value.
TOTAL on process values (any width the replay can denote) and NEVER inverted —
no `process(::ChannelValue)` exists anywhere (S7). `channel(g) == channel(e^{iα}g)`
is FALSE at the value level (different matrices) while
`same_channel(channel(g), channel(e^{iα}g))` is TRUE — `ker(Ad) = U(1)` made
visible at the value level (test `M11.CHANNEL.AD-KERNEL`).
"""
channel(v::ProcessValue) =
    KrausFamily([denoted_matrix(v)]; label = Symbol(:Ad_, nameof(typeof(v))))

"""
    choi_matrix(v::ChannelValue) -> Matrix{ComplexF64}

The normalized Choi (Jamiołkowski) state `J(𝓔) = (𝓔 ⊗ id)(|Ω⟩⟨Ω|)` with
`|Ω⟩ = 2^{−W/2} Σᵢ |i⟩|i⟩` — the CANONICAL representative every semantic
comparison runs through ([`same_channel`](@ref)). Basis `|out⟩ ⊗ |ref⟩` with
`out` the MSB factor — pinned to match `test/choi.jl`'s `_ptrace_keep`
convention exactly. Trace-1 PSD for a CPTP value. Loud above
[`CHANNEL_CHOI_MAXWIRES`](@ref) (F25: the memory budget is the cap).
"""
function choi_matrix(v::ChannelValue)
    W = nwires(v)
    W <= CHANNEL_CHOI_MAXWIRES || throw(ArgumentError(
        "choi_matrix: $W wires exceeds CHANNEL_CHOI_MAXWIRES = $CHANNEL_CHOI_MAXWIRES " *
        "(a W-wire Choi is 4^W × 4^W dense — F25); compare sub-blocks or use " *
        "randomized probes instead"))
    d = 2^W
    ops = kraus_matrices(v)
    J = zeros(ComplexF64, d * d, d * d)
    # J = (1/d) Σ_k (K ⊗ I) |Ω̃⟩⟨Ω̃| (K ⊗ I)†, |Ω̃⟩ = Σᵢ |i⟩|i⟩; row of (K⊗I)|Ω̃⟩
    # at |a⟩|b⟩ is K[a, b] — so J[(a,b),(c,e)] = (1/d) Σ_k K[a,b] conj(K[c,e]).
    for K in ops
        v̄ = Vector{ComplexF64}(undef, d * d)      # vec of (K ⊗ I)|Ω̃⟩ in (out,ref) basis
        for a in 1:d, b in 1:d
            v̄[(a - 1) * d + b] = K[a, b]
        end
        for c in eachindex(v̄), r in eachindex(v̄)
            J[r, c] += v̄[r] * conj(v̄[c])
        end
    end
    J ./= d
    return J
end

"""
    same_channel(a::ChannelValue, b::ChannelValue; atol=CHOI_ATOL) -> Bool

Semantic (denotation-level) equality: `‖J(a) − J(b)‖_∞ ≤ atol` on the canonical
Choi representatives. This is the CHANNEL-level comparison — deliberately blind
to Kraus unitary freedom (Watrous Cor. 2.24) and to global phase, which is
exactly why it must NEVER be used as a pass-correctness criterion for values
that may later be controlled (F3 — barred; compare ctrl-wrapped values there).

Named function, not `Base.isapprox` (S6): an O(4^W) Choi construction must not
hide behind `≈`, and F26 forbids tolerance comparison from ever implementing
`==`/`hash`. `==` on channel values stays exact structural equality.
"""
function same_channel(a::ChannelValue, b::ChannelValue; atol::Real = CHOI_ATOL)
    nwires(a) == nwires(b) || return false
    Ja = choi_matrix(a)
    Jb = choi_matrix(b)
    dev = 0.0
    for i in eachindex(Ja)
        dev = max(dev, abs(Ja[i] - Jb[i]))
        dev > atol && return false
    end
    return true
end

# --- Series composition (⊗ lives in channel/channel_algebra.jl) ---------------

"""
    ∘(a::ChannelValue, b::ChannelValue) -> ChannelValue

Series composition, `b` runs first (the kernel convention). Lazy `ChannelSeq`
in general; two `MixedUnitary`s fuse EXACTLY (S2 closure):
`(Σᵢ wᵢ Ad_{Uᵢ}) ∘ (Σⱼ vⱼ Ad_{Vⱼ}) = Σᵢⱼ wᵢvⱼ Ad_{Uᵢ∘Vⱼ}` — the kernel `∘`
on the branch values is the exact Hamilton/permutation product. No method mixes
a `ProcessValue` with a `ChannelValue` (S7): write `channel(v) ∘ 𝓝`.
"""
Base.:∘(a::ChannelValue, b::ChannelValue) = ChannelSeq(a, b)

# Base.:∘ carries a generic `ComposedFunction` fallback for ANY two arguments,
# so — unlike `⊗`/`ctrl`/`adjoint`, where no-method IS the refusal — a mixed
# ProcessValue×ChannelValue composition cannot be left to `MethodError`: it
# would silently build a meaningless `ComposedFunction`. The stratification
# (S7/§4.4) is therefore enforced by EXPLICIT refusal methods here.
Base.:∘(::ProcessValue, ::ChannelValue) = throw(ArgumentError(
    "cannot compose a ProcessValue with a ChannelValue: the denotation is a " *
    "quotient (§4.4) — cross it explicitly with channel(v) ∘ 𝓝; it is never " *
    "inverted, so a channel can never re-enter the process stratum"))
Base.:∘(::ChannelValue, ::ProcessValue) = throw(ArgumentError(
    "cannot compose a ChannelValue with a ProcessValue: the denotation is a " *
    "quotient (§4.4) — cross it explicitly with 𝓝 ∘ channel(v); it is never " *
    "inverted, so a channel can never re-enter the process stratum"))

function Base.:∘(a::MixedUnitary{W,Ra}, b::MixedUnitary{W,Rb}) where {W,Ra,Rb}
    weights = Float64[a.weights[i] * b.weights[j] for i in 1:Ra for j in 1:Rb]
    unitaries = ProcessValue[a.unitaries[i] ∘ b.unitaries[j] for i in 1:Ra for j in 1:Rb]
    return MixedUnitary(weights, unitaries)
end

# --- Named channel constructors (S8): the convention is pinned HERE -----------

# Shared 2×2 building blocks (plain literals; no LinearAlgebra).
const _K_I2 = ComplexF64[1 0; 0 1]
const _K_X = ComplexF64[0 1; 1 0]
const _K_Y = ComplexF64[0 -im; im 0]
const _K_Z = ComplexF64[1 0; 0 -1]
const _K_P0 = ComplexF64[1 0; 0 0]
const _K_P1 = ComplexF64[0 0; 0 1]

function _check_prob(name::Symbol, sym::Symbol, p::Real)
    (isfinite(p) && 0 <= p <= 1) || throw(DomainError(p,
        "$name: $sym must lie in [0, 1]"))
    return Float64(p)
end

"""
    bit_flip(p) -> KrausFamily

`ρ ↦ (1−p)ρ + p XρX` — flip the computational bit with probability `p`.
Kraus {√(1−p)·I, √p·X}.
"""
function bit_flip(p::Real)
    p64 = _check_prob(:bit_flip, :p, p)
    return KrausFamily([sqrt(1 - p64) .* _K_I2, sqrt(p64) .* _K_X]; label = :bit_flip)
end

"""
    phase_flip(p) -> KrausFamily

`ρ ↦ (1−p)ρ + p ZρZ` — flip the phase with probability `p`.
Kraus {√(1−p)·I, √p·Z}.
"""
function phase_flip(p::Real)
    p64 = _check_prob(:phase_flip, :p, p)
    return KrausFamily([sqrt(1 - p64) .* _K_I2, sqrt(p64) .* _K_Z]; label = :phase_flip)
end

"""
    pauli_channel(px, py, pz) -> KrausFamily

`ρ ↦ (1−px−py−pz)ρ + px XρX + py YρY + pz ZρZ`. Requires each `pᵢ ∈ [0,1]`
and `px+py+pz ≤ 1`.
"""
function pauli_channel(px::Real, py::Real, pz::Real)
    x = _check_prob(:pauli_channel, :px, px)
    y = _check_prob(:pauli_channel, :py, py)
    z = _check_prob(:pauli_channel, :pz, pz)
    s = x + y + z
    s <= 1 + KRAUS_TP_ATOL || throw(DomainError(s,
        "pauli_channel: px + py + pz must be ≤ 1"))
    return KrausFamily([sqrt(max(1 - s, 0.0)) .* _K_I2, sqrt(x) .* _K_X,
                        sqrt(y) .* _K_Y, sqrt(z) .* _K_Z]; label = :pauli_channel)
end

"""
    depolarizing(p) -> KrausFamily

PINNED convention (S8): `ρ ↦ (1−p)ρ + p·I/2` — with probability `p` the state
is REPLACED by the maximally mixed state. Operator-sum:
`(1−3p/4)ρ + (p/4)(XρX + YρY + ZρZ)`, so the physical domain is `p ∈ [0, 4/3]`
(CPTP up to 4/3; `p = 1` is the fully-depolarizing point, `p > 1` inverts the
Bloch ball). The `(p/3)Σ PρP` convention is deliberately NOT offered under this
name — convention pinning in the constructor is where that bug class dies.
"""
function depolarizing(p::Real)
    (isfinite(p) && 0 <= p <= 4 / 3) || throw(DomainError(p,
        "depolarizing: p must lie in [0, 4/3] (ρ ↦ (1−p)ρ + p·I/2 is CPTP there)"))
    p64 = Float64(p)
    return KrausFamily([sqrt(1 - 3p64 / 4) .* _K_I2, sqrt(p64 / 4) .* _K_X,
                        sqrt(p64 / 4) .* _K_Y, sqrt(p64 / 4) .* _K_Z];
                       label = :depolarizing)
end

"""
    dephasing(λ) -> KrausFamily

PINNED convention: the λ-interpolation to the pinch — `ρ ↦ (1−λ)ρ + λ·Δ(ρ)`
with `Δ` the complete-dephasing (pinching) channel. Off-diagonals scale by
`(1−λ)`; `dephasing(1)` IS `pinch_channel()`'s channel. Kraus
{√(1−λ)·I, √λ·|0⟩⟨0|, √λ·|1⟩⟨1|}. Same one-parameter family as
[`phase_damping`](@ref) under `λ_deph = 1 − √(1−λ_damp)`; both spellings exist
because the literatures pin different parameters — the FORMULA is what this
docstring pins.
"""
function dephasing(λ::Real)
    l = _check_prob(:dephasing, :λ, λ)
    return KrausFamily([sqrt(1 - l) .* _K_I2, sqrt(l) .* _K_P0, sqrt(l) .* _K_P1];
                       label = :dephasing)
end

"""
    phase_damping(λ) -> KrausFamily

PINNED convention (Nielsen–Chuang §8.3.6): K₀ = diag(1, √(1−λ)),
K₁ = diag(0, √λ). Off-diagonals scale by `√(1−λ)`. See [`dephasing`](@ref) for
the reparameterization between the two spellings.
"""
function phase_damping(λ::Real)
    l = _check_prob(:phase_damping, :λ, λ)
    return KrausFamily([ComplexF64[1 0; 0 sqrt(1 - l)], ComplexF64[0 0; 0 sqrt(l)]];
                       label = :phase_damping)
end

"""
    amplitude_damping(γ) -> KrausFamily

PINNED convention (Nielsen–Chuang §8.3.5): K₀ = diag(1, √(1−γ)),
K₁ = √γ·|0⟩⟨1| — decay |1⟩ → |0⟩ with probability `γ`. Non-unital and
asymmetric, which is exactly why it is the SENTINEL for the env-ordering pin
(S10/F3 — a Pauli channel is blind to an env/system swap; this one is not).
"""
function amplitude_damping(γ::Real)
    g = _check_prob(:amplitude_damping, :γ, γ)
    return KrausFamily([ComplexF64[1 0; 0 sqrt(1 - g)], ComplexF64[0 sqrt(g); 0 0]];
                       label = :amplitude_damping)
end

"""
    reset_channel() -> KrausFamily

The trace-and-reset channel {|0⟩⟨0|, |0⟩⟨1|}: `ρ ↦ Tr(ρ)|0⟩⟨0|` on the wire —
the M2 exact-ptrace lowering's channel, RE-HOMED here as the single canonical
definition (S8/principle 13; `density.jl`'s `_RESET_KRAUS` is derived from it).
"""
reset_channel() = KrausFamily([copy(_K_P0), ComplexF64[0 1; 0 0]]; label = :reset)

"""
    pinch_channel() -> KrausFamily

The complete-dephasing (pinching) channel {|0⟩⟨0|, |1⟩⟨1|}: kills coherences,
keeps the diagonal — the qc-cast denotation `cq ∘ qc` (§3.2). RE-HOMED single
canonical definition (S8; `density.jl`'s `_PINCH_KRAUS` is derived from it).
"""
pinch_channel() = KrausFamily([copy(_K_P0), copy(_K_P1)]; label = :pinch)
