# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M2 (bead Sturm.jl-dc6i): state
# lifecycle and bulk amplitude access on top of the raw FFI. INTERNAL layer.
#
# WHY bulk `unsafe_wrap` over per-element `state_get`: sampling/probabilities
# are Julia-side (Orkan has no RNG — audit §6) and cost O(2^n). PURE storage is
# a flat `2^n` ComplexF64 vector; wrapping the pointer once (under
# `GC.@preserve`) beats one ccall per amplitude (v0.1 flagged 16 MB/call at
# n=20, bead Sturm.jl-5z3r). MIXED storage is triangular/tiled — read it via the
# Hermitian-aware `state_get`.
#
# GOTCHA (verified 2026-07-10): `state_init` zero-allocates; a fresh PURE state
# is the all-ZERO vector, and a fresh MIXED state is the all-zero matrix. The
# canonical basis state |0…0⟩ / |0…0⟩⟨0…0| must be set explicitly here — see
# `_state_new`.

"""
    _state_new(type::Cint, ncap::Int) -> OrkanStateRaw

Allocate a fresh `ncap`-qubit Orkan state of the given storage `type` and set
it to the canonical basis state: |0…0⟩ (PURE) or |0…0⟩⟨0…0| (MIXED). Undoes the
zero-allocation gotcha at exactly one place.
"""
function _state_new(type::Cint, ncap::Int)
    st = OrkanStateRaw(type)
    orkan_state_init!(st, ncap)
    # state_init zero-allocates — set the |0…0⟩ amplitude / population.
    orkan_state_set!(st, 0, 0, one(ComplexF64))
    return st
end

"""
    _with_amps(f, state) -> f(amps)

Run `f` on a bulk `unsafe_wrap` view of a PURE state's flat amplitude vector,
under `GC.@preserve` (the view aliases Orkan-owned memory; the state must
outlive it). Mutations through the view mutate the live statevector — used by
the in-place collapse. Do NOT let the view escape `f`.
"""
function _with_amps(f, state::OrkanStateRaw)
    state.type == ORKAN_PURE || error("_with_amps: bulk amplitude view is PURE-only (got type $(state.type))")
    n = Int(orkan_state_len(state))
    GC.@preserve state begin
        amps = unsafe_wrap(Array, state.data, n)
        return f(amps)
    end
end

"""
    _statevector(state) -> Vector{ComplexF64}

A COPY of a PURE state's amplitude vector (safe to keep past the state's life).
Test/readout use.
"""
_statevector(state::OrkanStateRaw) = _with_amps(copy, state)

"""
    _density(state, ncap) -> Matrix{ComplexF64}

The `2^ncap × 2^ncap` density matrix of a MIXED state, read entrywise through
the Hermitian-aware `state_get`. Test/readout use.
"""
function _density(state::OrkanStateRaw, ncap::Int)
    N = 1 << ncap
    ρ = Matrix{ComplexF64}(undef, N, N)
    for j in 0:(N-1), i in 0:(N-1)
        ρ[i+1, j+1] = orkan_state_get(state, i, j)
    end
    return ρ
end

"""
    _marginal_p1(state, qubit) -> Float64

`P(qubit = 1)` on a PURE state: sum of `|amp|²` over basis indices whose bit
`qubit` is set. Bulk scan, no per-element ccall.
"""
function _marginal_p1(state::OrkanStateRaw, qubit::Int)
    mask = 1 << qubit
    _with_amps(state) do amps
        p = 0.0
        @inbounds for i in eachindex(amps)
            # eachindex is 1-based; basis index = i-1.
            if ((i - 1) & mask) != 0
                p += abs2(amps[i])
            end
        end
        return p
    end
end

"""
    _collapse!(state, qubit, outcome)

In-place projective collapse of a PURE state onto `qubit == outcome`, then
renormalize. Zeros every amplitude inconsistent with `outcome` and rescales the
survivors to unit norm. This is the pure-context measure-and-discard
UNRAVELING (§3.9): exact for all downstream statistics by no-signaling. The
caller draws `outcome` from its own RNG (Orkan has none).
"""
function _collapse!(state::OrkanStateRaw, qubit::Int, outcome::Int)
    mask = 1 << qubit
    _with_amps(state) do amps
        nrm2 = 0.0
        @inbounds for i in eachindex(amps)
            bit = ((i - 1) & mask) != 0 ? 1 : 0
            if bit != outcome
                amps[i] = zero(ComplexF64)
            else
                nrm2 += abs2(amps[i])
            end
        end
        nrm2 > 0 || error("_collapse!: zero-probability branch (outcome=$outcome, qubit=$qubit) — RNG/marginal desync")
        s = inv(sqrt(nrm2))
        @inbounds for i in eachindex(amps)
            amps[i] *= s
        end
        return nothing
    end
    nothing
end
