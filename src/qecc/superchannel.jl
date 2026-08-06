# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M11 (bead Sturm.jl-qmpo), design
# `docs/design/m11-82su-synthesis.md` §3.3 (rulings S21–S24, S27) + Tobias
# ruling T1 (session 103): the QECC SUPERCHANNEL — the F8 typed replacement
# for v0.1's conflated `encode(ch, code)`.
#
#     Θ(𝓝) = D ∘ R ∘ 𝓝 ∘ E : Chan(P, P) → Chan(L, L)
#
# THE CODE-CAPACITY MODEL, NAMED (S27): the encoder, recovery, and decoder are
# NOISELESS and syndrome extraction is PERFECT. M11 makes NO fault-tolerance
# claim and NO threshold claim — `p_L < p` below break-even is a code-capacity
# statement, nothing more. `fault_tolerant_lift` (qecc/ft.jl) names what a
# fault-tolerance claim would need.
#
# A superchannel is a COMPILER TRANSFORMATION on `ChannelDAG`s and explicitly
# NOT a `ChannelPass` (§2 convergent core): the pass law is Choi-preserving
# with an unchanged boundary; a superchannel changes both BY DESIGN. Its
# license is the comb factorisation — a 1-slot superchannel IS
# `Θ(𝓝) = Tr_M[D∘(𝓝⊗id_M)∘E]` (Chiribella–D'Ariano–Perinotti, EPL Thm 1
# eq (23), docs/physics/chiribella_2009_quantum_combs.md), and QECC is its
# memoryless (1-dimensional-memory) case — EPL Application 1, verbatim.
# `ctrl(Θ)` and `ctrl(Φ::LogicalChannel)` are MethodErrors by construction.
#
# Physics grounding:
#   docs/physics/knill_laflamme_1997_qec_conditions.md — Thm 3.3: Θ(𝓝) = id_L
#     IS the correctability statement (not a precondition); Thm 3.4 licenses
#     Choi-level QECC tests.
#   docs/physics/repetition_code_effective_noise.md — the [[3,1,1]] numbers.

"""
    PhysicalChannel{C<:StabilizerCode}

A noise process on the PHYSICAL wires of a code: a validated `ChannelDAG` on
`nphysical(code)` quantum wires (S22): endomorphic boundary (in == out
lineage, in order), and NO classical outputs — a "physical noise model" with a
classical output is an *instrument*, and admitting one would smuggle a second
measurement record into the syndrome path. Build i.i.d. models with
[`physical_iid`](@ref).
"""
struct PhysicalChannel{C<:StabilizerCode}
    code::C
    dag::ChannelDAG
    function PhysicalChannel(code::StabilizerCode{N}, dag::ChannelDAG) where {N}
        _assert_channel_boundary(dag, N, "PhysicalChannel")
        return new{typeof(code)}(code, dag)
    end
end

"""
    LogicalChannel{C<:StabilizerCode}

The effective LOGICAL channel a superchannel produces: a validated
`ChannelDAG` on `nlogical(code)` wires, no classical outputs (the syndrome
record is discarded inside — the code-capacity block accumulation).
"""
struct LogicalChannel{C<:StabilizerCode}
    code::C
    dag::ChannelDAG
    function LogicalChannel(code::StabilizerCode{N,K}, dag::ChannelDAG) where {N,K}
        _assert_channel_boundary(dag, K, "LogicalChannel")
        return new{typeof(code)}(code, dag)
    end
end

function _assert_channel_boundary(dag::ChannelDAG, n::Int, what::AbstractString)
    length(dag.qin) == n || throw(ArgumentError(
        "$what: DAG has $(length(dag.qin)) quantum inputs; the code needs $n"))
    length(dag.qout) == n || throw(ArgumentError(
        "$what: DAG has $(length(dag.qout)) quantum outputs; the code needs $n"))
    for i in 1:n
        dag.qin[i].lineage == dag.qout[i].lineage || throw(ArgumentError(
            "$what: boundary is not endomorphic — output $i lineage " *
            "$(dag.qout[i].lineage) ≠ input lineage $(dag.qin[i].lineage) (§1.2)"))
    end
    isempty(dag.cout) || throw(ArgumentError(
        "$what: DAG has classical outputs — an instrument is not a $what " *
        "(a record would smuggle a second measurement into the syndrome path)"))
    nothing
end

# --- Transforms (S21/S23) -----------------------------------------------------

"""
    ChannelTransform

Abstract supertype of typed channel→channel transformations (superchannels and
their degenerate relatives). NOT a `ChannelPass`: a transform may change the
boundary and the denotation by design; each registered transform carries its
own two law obligations (S23 — see `TRANSFORM_REGISTRY`).
"""
abstract type ChannelTransform end

"Recovery policy for [`Protect`](@ref): how the syndrome drives corrections."
abstract type RecoveryPolicy end

"Table-lookup recovery: apply `corrections[σ+1]` on syndrome σ (S20-validated)."
struct TableDecoder <: RecoveryPolicy end

"No recovery: encode, let the noise act, decode. (Detection-only baseline.)"
struct NoRecovery <: RecoveryPolicy end

"""
    Protect(enc::CodeEncoding, recovery::RecoveryPolicy = TableDecoder())

The QECC superchannel value (S21): callable,
`Protect(enc)(𝓝::PhysicalChannel) -> LogicalChannel` via
[`effective_logical_noise`](@ref). The code mismatch between the transform and
its argument is a `MethodError` (both are typed by `C`).
"""
struct Protect{C<:StabilizerCode,R<:RecoveryPolicy} <: ChannelTransform
    enc::CodeEncoding{C}
    recovery::R
end
Protect(enc::CodeEncoding) = Protect(enc, TableDecoder())

(θ::Protect{C})(𝓝::PhysicalChannel{C}) where {C} = effective_logical_noise(𝓝, θ)

"""
    TRANSFORM_REGISTRY

Registered channel transforms (S23), mirroring `PASS_REGISTRY`. Every entry
owes TWO law tests, enforced by the registry-driven testset in
`test/test_m11_qecc.jl` (which iterates THIS dict, so an unregistered-but-
shipped or registered-but-untested transform fails the suite):
  (a) the SPEC law — `Choi(θ(g))` equals the Choi of the composite assembled
      independently in the test file;
  (b) the IDENTITY law — `Choi(θ(id_P)) ≈ Choi(id_L)`.
"""
const TRANSFORM_REGISTRY = Dict{Symbol,Any}()
TRANSFORM_REGISTRY[:protect] = Protect

# --- The DAG factories --------------------------------------------------------

# E: K logical inputs → alloc N−K → encoder unitary. qout = all N wires.
function _encode_dag(enc::CodeEncoding{C,N,K}) where {C,N,K}
    b = DAGBuilder()
    logical = PortID[input!(b) for _ in 1:K]
    fresh = PortID[alloc!(b) for _ in 1:(N - K)]
    apply_node!(b, enc.encoder, logical..., fresh...)
    return freeze(b)
end

# D: N inputs → adjoint encoder → trace the N−K scratch. qout = K logical.
function _decode_dag(enc::CodeEncoding{C,N,K}) where {C,N,K}
    b = DAGBuilder()
    data = PortID[input!(b) for _ in 1:N]
    apply_node!(b, decoder(enc), data...)
    for i in (K + 1):N
        trace!(b, data[i])
    end
    return freeze(b)
end

# The controlled-word value of a Pauli generator: (⊗ of its non-I letters,
# ascending wire order = MSB-first) + the support indices.
function _word_value(g::PauliWord{N}) where {N}
    letters = ProcessValue[]
    support = Int[]
    for j in 1:N
        c = letter_at(g, j)
        c == 'I' && continue
        push!(support, j)
        push!(letters, c == 'X' ? X : (c == 'Z' ? Z : Y))
    end
    isempty(letters) && error("_word_value: identity generator")
    v = letters[1]
    for i in 2:length(letters)
        v = v ⊗ letters[i]
    end
    return v, support
end

# The nested binary correction tree over the syndrome records (generator 1 =
# LSB — the codes.jl pin): level ℓ branches on record ℓ; leaves apply the
# validated table's correction word. Branch DAGs share the parent namespace
# (the tracing-materializer convention the replay expects).
function _correction_cases(enc::CodeEncoding{C,N,K}, recs::Vector{PortID},
                           data::Vector{PortID}, level::Int, σ::Int) where {C,N,K}
    S = length(recs)
    branch = bit -> begin
        σb = σ | (bit << (level - 1))
        if level == S
            nodes = Node[]
            w = enc.corrections[σb + 1]
            for j in 1:N
                c = letter_at(w, j)
                c == 'I' && continue
                push!(nodes, ApplyN(c == 'X' ? X : (c == 'Z' ? Z : Y), (data[j],)))
            end
            ChannelDAG(Tuple(nodes), (), (), ())
        else
            ChannelDAG((_correction_cases(enc, recs, data, level + 1, σb),), (), (), ())
        end
    end
    return CasesN(recs[level], (branch(0), branch(1)))
end

# R: syndrome extraction (|0⟩ ancilla, H, ctrl(generator word), H, measure —
# phase kickback reads the ±1 eigenvalue for ANY Pauli generator) + the
# table-driven correction tree + record discard (code-capacity accumulation).
function _recovery_dag(enc::CodeEncoding{C,N,K}) where {C,N,K}
    any(==(Int8(-1)), enc.code.signs) && error(
        "_recovery_dag: M11 supports +1-sign generators only (a −1 sign flips " *
        "the syndrome-bit convention; the sign-aware extraction is deferred " *
        "with the Steane epic)")
    b = DAGBuilder()
    data = PortID[input!(b) for _ in 1:N]
    recs = PortID[]
    for g in enc.code.stabilizers
        a = alloc!(b)
        v, support = _word_value(g)
        apply_node!(b, H, a)
        apply_node!(b, ctrl(v), a, PortID[data[j] for j in support]...)
        apply_node!(b, H, a)
        push!(recs, measure!(b, a))
    end
    push!(b.nodes, _correction_cases(enc, recs, data, 1, 0))
    for r in recs
        trace_record!(b, r)
    end
    return freeze(b)
end

# --- The superchannel (S21) ---------------------------------------------------

"""
    effective_logical_noise(𝓝::PhysicalChannel{C}, θ::Protect{C}) -> LogicalChannel{C}

The QECC superchannel under the CODE-CAPACITY model (S27 — noiseless
encoder/recovery/decoder, perfect syndrome extraction; NO fault-tolerance or
threshold claim): splices `Θ(𝓝) = D ∘ R ∘ 𝓝.dag ∘ E` at the `ChannelDAG`
level (slice-4 `∘`; `NoRecovery` omits R) and validates the result onto the
logical boundary. `Θ(𝓝) = id_L` is the CORRECTABILITY STATEMENT (KL Thm 3.3),
computed — not assumed.
"""
function effective_logical_noise(𝓝::PhysicalChannel{C}, θ::Protect{C}) where {C}
    𝓝.code == θ.enc.code || throw(ArgumentError(
        "effective_logical_noise: the physical channel and the transform carry " *
        "different codes ($(𝓝.code.name) vs $(θ.enc.code.name))"))
    E = _encode_dag(θ.enc)
    D = _decode_dag(θ.enc)
    inner = θ.recovery isa NoRecovery ? (𝓝.dag ∘ E) : (_recovery_dag(θ.enc) ∘ (𝓝.dag ∘ E))
    return LogicalChannel(𝓝.code, D ∘ inner)
end

"""
    effective_logical_noise(::ChannelValue, ...)

LOUD refusal (S24): a channel value says WHAT the noise is, not WHERE it acts.
Lift it first: `physical_iid(enc, fam)` for i.i.d. noise, or
`PhysicalChannel(code, channel_dag(...))` for anything structured.
"""
effective_logical_noise(::ChannelValue, ::Any) = throw(ArgumentError(
    "effective_logical_noise: a channel VALUE says WHAT the noise is, not WHERE " *
    "it acts (S24). Lift it first: physical_iid(enc, fam) for i.i.d. noise, or " *
    "PhysicalChannel(code, channel_dag(ch, n)) for a structured model."))

"""
    physical_iid(e::CodeEncoding, 𝓝::ChannelValue) -> PhysicalChannel

The i.i.d. physical noise model: the 1-wire factor `𝓝` on every physical wire
(`𝓝^{⊗N}` as a lazy `ChannelTensor` — never a dense `4^N` family, V3).
"""
function physical_iid(e::CodeEncoding, 𝓝::ChannelValue)
    nwires(𝓝) == 1 || throw(ArgumentError(
        "physical_iid: the factor must be a 1-wire channel (got $(nwires(𝓝)) wires); " *
        "i.i.d. means the SAME local factor on every wire"))
    N = nphysical(e)
    t = 𝓝
    for _ in 2:N
        t = t ⊗ 𝓝
    end
    return PhysicalChannel(e.code, channel_dag(t, N))
end
