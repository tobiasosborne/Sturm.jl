# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M11 (bead Sturm.jl-qmpo), design
# `docs/design/m11-82su-synthesis.md` ruling S31 + Tobias ruling T2 (session
# 103): TWO NAMES, TWO OPERATIONS —
#
#   `classicalise`        — the v0.1 carried contract (plan §7 row 7), RE-
#                           DERIVED: the decohered channel Δ_out ∘ 𝓔 ∘ Δ_in as
#                           a column-stochastic matrix, arity FROM THE PORTS
#                           (the v0.1 spec's own "returns 2×2" single-qubit
#                           defect, Sturm-PRD.md:457, cannot recur), exact by
#                           replay.
#   `record_distribution` — token-record introspection on DM: the outcome
#                           distribution a classical record carries, read with
#                           NO backaction and WITHOUT consuming the token.
#
# Merging them would be exactly the sample/record/assert conflation §3.6
# exists to prevent (the T2 reason of record). No `-ize` alias.

"""
    CLASSICALISE_MAXWIRES

Width cap for [`classicalise`](@ref): the result is a dense `2^n × 2^n` matrix
and DAG replay runs `2^n` DM columns — loud above 3 wires (an 8×8 stochastic
matrix; wider maps are not a "matrix you look at" any more).
"""
const CLASSICALISE_MAXWIRES = 3

"""
    classicalise(g) -> Matrix{Float64}

The CLASSICAL SHADOW of a channel (v0.1 carried contract, re-derived — S31/T2):
the column-stochastic matrix of `Δ_out ∘ 𝓔 ∘ Δ_in` on the computational basis,
`M[i+1, j+1] = ⟨i| 𝓔(|j⟩⟨j|) |i⟩`, with the arity taken FROM THE PORTS —
`nwires(𝓔)` for a value, `length(qin)` for a `ChannelDAG` (the v0.1 "always
2×2" defect is unrepresentable). Exact: values via their Kraus operators, DAGs
by one DM replay per basis column (instrument sums and all). Accepts a
`ChannelValue`, a `ChannelDAG`, or a `LogicalChannel`.

⚠ PHASE-BLIND — NEVER a channel-equivalence test. `classicalise` deliberately
satisfies `classicalise(channel(I2)) == classicalise(channel(Z))` (the pinch
kills exactly what a coherent probe sees), which is the F3-barred criterion
class: comparing classical shadows says NOTHING about the channels agreeing.
The named test `M11.CLASSICALISE.IS-PHASE-BLIND` asserts this ON PURPOSE.
Basis order: index bit `n−k` is wire `k` (wire 1 = MSB, the M6 pin).
"""
function classicalise(ch::ChannelValue)
    n = nwires(ch)
    n <= CLASSICALISE_MAXWIRES || throw(ArgumentError(
        "classicalise: $n wires exceeds CLASSICALISE_MAXWIRES = $CLASSICALISE_MAXWIRES"))
    d = 2^n
    ops = kraus_matrices(ch)
    M = zeros(Float64, d, d)
    for K in ops, j in 1:d, i in 1:d
        M[i, j] += abs2(K[i, j])
    end
    return M
end

function classicalise(g::ChannelDAG)
    n = length(g.qin)
    n == length(g.qout) || throw(ArgumentError(
        "classicalise: DAG has $n quantum inputs but $(length(g.qout)) outputs — " *
        "the classical shadow needs a same-arity channel"))
    n >= 1 || throw(ArgumentError("classicalise: DAG has no quantum ports"))
    n <= CLASSICALISE_MAXWIRES || throw(ArgumentError(
        "classicalise: $n wires exceeds CLASSICALISE_MAXWIRES = $CLASSICALISE_MAXWIRES"))
    d = 2^n
    M = zeros(Float64, d, d)
    for j in 0:(d - 1)
        density(n + 5) do ctx                     # headroom for internal allocs
            wires = WireID[allocate!(ctx) for _ in 1:n]
            for k in 1:n                          # prepare |j⟩, wire 1 = MSB
                ((j >> (n - k)) & 1) == 1 && apply!(ctx, X, (wires[k],))
            end
            outs = _replay_dm!(ctx, g, wires)
            ρ = density_matrix(ctx)
            cap = _core(ctx).capacity
            slots = Int[q(ctx, w) for w in outs]
            for idx in 0:(2^cap - 1)
                p = real(ρ[idx + 1, idx + 1])
                p == 0 && continue
                i = 0
                for k in 1:n                      # out wire 1 = MSB of the row index
                    (((idx >> slots[k]) & 1) == 1) && (i |= 1 << (n - k))
                end
                M[i + 1, j + 1] += p
            end
            nothing
        end
    end
    return M
end

classicalise(Φ::LogicalChannel) = classicalise(Φ.dag)

"""
    record_distribution(t::ClassicalToken) -> Vector{Float64}

Token-record introspection (S31, the OTHER half of the T2 split): the outcome
distribution the classical record carries, `dist[v+1] = P(token = v)`, read
from the DM diagonal with NO BACKACTION (the record wires are already pinched
— a named test asserts `density_matrix` is bitwise unchanged) and WITHOUT
consuming the token (records are copyable; the last-use rule is `discard!`).

DM-only BY CONSTRUCTION: an Eager measurement returns a host `Bool`/`Int`
(there is no Eager token to introspect — `record_distribution(true)` is a
`MethodError`); under Tracing it is a descriptive error (a trace-time token
has no distribution — the record is symbolic). Returns a DISTRIBUTION, never a
value: there is no scalar here to branch on (`cases` is the branching
construct). Derived tokens evaluate their T1–T4 SSA over the base-wire
configurations; the fan-in is capped like `cases` (`CASES_MAX_FANIN`).

R4 note (cross-checked, not assumed): the diagonal read uses the
`(idx >> slot) & 1` bit convention — the same convention `test/choi.jl`'s
`_ptrace_keep` pins (`keep[1]` → MSB there; here the token's own evaluator
maps base bits to values, so no reduced-index ordering exists to get wrong).
"""
function record_distribution(t::ClassicalToken)
    ctx = contextof(t)
    ctx isa TracingContext && throw(ArgumentError(
        "record_distribution: a Tracing token is SYMBOLIC — a trace-time record has " *
        "no distribution (the compiler context executes nothing). Introspect on the " *
        "DM context, or `shots` on Eager."))
    ctx isa DensityMatrixContext || throw(ArgumentError(
        "record_distribution: tokens carry records only under DM (Eager measurement " *
        "returns a host scalar; there is nothing to introspect)"))
    K = length(t.wires)
    K <= CASES_MAX_FANIN || error(
        "record_distribution: the token derives from $K record wires, which " *
        "exceeds the fan-in cap ($CASES_MAX_FANIN). Wide feed-forward is a finite " *
        "classical computation — restructure through `select`/T2 first.")
    core = _core(ctx)
    for w in t.wires
        haskey(core.wire_to_slot, w) || error(
            "record_distribution: record wire $w is no longer live — the record was " *
            "`discard!`ed or its region exited (last-use rule, §2.2)")
    end
    ρ = density_matrix(ctx)                        # flushes; read-only afterwards
    cap = core.capacity
    slots = Int[core.wire_to_slot[w] for w in t.wires]
    dist = zeros(Float64, 1 << width(t))
    d = Dict{WireID,Bool}()
    for idx in 0:(2^cap - 1)
        p = real(ρ[idx + 1, idx + 1])
        p == 0 && continue
        for (k, w) in enumerate(t.wires)
            d[w] = ((idx >> slots[k]) & 1) == 1
        end
        v = t.f(d)
        dist[(v isa Bool ? Int(v) : v) + 1] += p
    end
    return dist
end
