# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# Sturm.jl M3 (bead Sturm.jl-77m2): the Choi harness — the measuring instrument
# for the boundary algebra and (from M4 on) every channel. TEST-SIDE tooling: it
# is licensed to use kernel values directly (`H`, `ctrl(X)`) and to reach
# `Sturm.` internals, because it is kernel-level test tooling, not surface code
# (only SURFACE code is gate-free). It never ships in `src/` — a Choi builder in
# `src/` would invite surface code to call it.
#
# NORMALIZATION (pinned): the Choi STATE (Jamiołkowski),
#     J(Φ) = (Φ ⊗ id)(|Ω⟩⟨Ω|),   |Ω⟩ = 2^{−nin/2} Σ_i |i⟩_sys |i⟩_ref  (NORMALIZED)
# so J is a trace-1 density matrix for a CPTP Φ, comparable with `≈`. J(id) is
# the maximally-entangled projector |Ω⟩⟨Ω| (rank 1, off-diagonals present);
# J(pinching) is its complete dephasing (DIAGONAL). Comparing these two on the
# COHERENT Bell probe catches the wm28 class (a Z-error/pinch is invisible to
# Z-basis marginals but visible in the off-diagonal of J).
#
# Basis ordering (pinned by `_ptrace_keep`): the kept-slot tuple `keep` is placed
# with `keep[1]` as the MSB of the reduced index. The harness passes
# `keep = (output_slot, ref_slot)`, so J is written in the |out⟩⊗|ref⟩ basis with
# `out` the MSB — the endianness pin lives in exactly one function.

using Test
using LinearAlgebra
using Sturm
using Sturm: H, X, ctrl, apply!, allocate!, density, density_matrix, q

"""
    _ptrace_keep(ρ, keep::NTuple{K,Int}, cap::Int) -> Matrix{ComplexF64}

Partial trace of the `2^cap × 2^cap` density matrix `ρ`, KEEPING the Orkan slots
in `keep` (traced over every other slot). Keyed on SLOTS (not WireIDs), so it is
robust to slot recycling by the channel. `keep[1]` becomes the MSB of the reduced
index. Pure Julia, no ccall; O(2^{2cap}) — fine at the ≤15-wire law-test scale.
"""
function _ptrace_keep(ρ::AbstractMatrix, keep::NTuple{K,Int}, cap::Int) where {K}
    N = 1 << cap
    M = 1 << K
    keepmask = 0
    for s in keep
        keepmask |= (1 << s)
    end
    tracemask = (N - 1) & ~keepmask
    kb = idx -> begin
        v = 0
        for (p, s) in enumerate(keep)
            v |= ((idx >> s) & 1) << (K - p)   # keep[1] → MSB
        end
        return v
    end
    J = zeros(ComplexF64, M, M)
    for j in 0:(N - 1), i in 0:(N - 1)
        (i & tracemask) == (j & tracemask) || continue
        J[kb(i) + 1, kb(j) + 1] += ρ[i + 1, j + 1]
    end
    return J
end

"""
    choi(f, nin::Int = 1; cap = 2*nin) -> Matrix{ComplexF64}

The (normalized) Choi matrix of the 1-in/1-out channel `f`, computed EXACTLY in
one density-matrix run (DM executes channels, §3.8). Prepares `nin` Bell pairs
(system ⊗ reference), applies `f` to the system half wrapped as a `QBool`, and
reads the reduced density matrix over `(f's output wire, reference)`. `f`'s output
handle may live on a DIFFERENT wire than its input (e.g. a fresh-prepare channel),
so the harness reads J over the RETURNED handle's wire, not the input wire. M3
supports `nin = 1` (all boundary-law channels are 1-in/1-out). `cap` gives
`2·nin` Bell wires plus headroom for `f`'s scratch/fresh-output wires (a channel
that allocates its output without consuming its input needs > 2·nin live slots).
"""
function choi(f, nin::Int = 1; cap::Int = 2 * nin + 2)
    nin == 1 || error("choi: M3 harness supports nin=1 (got $nin); multi-input arrives with M4")
    density(cap) do ctx
        sys = allocate!(ctx)
        ref = allocate!(ctx)
        apply!(ctx, H, (sys,))
        apply!(ctx, ctrl(X), (sys, ref))            # normalized Bell pair (|00⟩+|11⟩)/√2
        qin = Sturm._adopt_qbool(ctx, sys)          # wrap the system half (no re-prep)
        qout = f(qin)                               # f may consume qin / return a new wire
        ρ = density_matrix(ctx)
        keep = (q(ctx, qout.wire), q(ctx, ref))     # (output MSB, ref LSB) — slots, recycle-robust
        return _ptrace_keep(ρ, keep, cap)
    end
end

# --- Channels under test (the boundary-algebra denotations) --------------

"The identity channel: return the handle unchanged. Its Choi is |Ω⟩⟨Ω|."
identity_channel(q) = q

"""The pinching (complete-dephasing) channel — the CHANNEL denotation of qc on DM
(§3.8), realized in one pass via `_instrument!`. Output wire == input wire."""
function pinch_channel(q)
    Sturm._instrument!(q.ctx, q.wire)
    return q
end

"A constant-prepare channel: ignore the input (traced at region exit), output a
fresh |0⟩. Exercises the harness's output-wire tracking (out wire ≠ input wire)."
prepare_false_channel(_q) = QBool(false)

# --- The boundary-algebra Choi laws (§3.2, §3.8) -------------------------

@testset "Choi harness — boundary algebra (§3.2/§3.8)" begin
    # Analytic references in the (out, ref) basis, out = MSB.
    bell    = ComplexF64[1 0 0 1; 0 0 0 0; 0 0 0 0; 1 0 0 1] ./ 2   # |Ω⟩⟨Ω| = J(id)
    pinched = ComplexF64[1 0 0 0; 0 0 0 0; 0 0 0 0; 0 0 0 1] ./ 2   # ½(|00⟩⟨00|+|11⟩⟨11|)
    constJ  = ComplexF64[1 0 0 0; 0 1 0 0; 0 0 0 0; 0 0 0 0] ./ 2   # |0⟩⟨0|_out ⊗ (I/2)_ref

    @testset "qc∘cq = id at the channel level (identity Choi = |Ω⟩⟨Ω|)" begin
        Jid = choi(identity_channel, 1)
        @test Jid ≈ bell
        @test tr(Jid) ≈ 1                       # normalized (trace-1, CPTP)
        @test !(Jid ≈ Diagonal(diag(Jid)))      # genuinely coherent (off-diagonals present)
    end

    @testset "cq∘qc = pinching, probed on the COHERENT Bell state (wm28 gate)" begin
        Jp = choi(pinch_channel, 1)
        @test Jp ≈ pinched
        @test Jp ≈ Diagonal(diag(Jp))           # DIAGONAL ⇔ complete dephasing
        @test tr(Jp) ≈ 1
        # The headline: on the COHERENT probe, pinching ≠ identity. A diagonal
        # probe (or a Z-basis marginal) cannot see this — the wm28 lesson.
        @test !(Jp ≈ choi(identity_channel, 1))
    end

    @testset "output-wire tracking: constant-prepare channel Choi" begin
        Jc = choi(prepare_false_channel, 1)     # out wire ≠ input wire
        @test Jc ≈ constJ
        @test tr(Jc) ≈ 1
    end
end
