# SPDX-License-Identifier: AGPL-3.0-only
#
# Shared helpers for the M2 test suite (bead Sturm.jl-dc6i). Test-only stdlib
# use (LinearAlgebra, Random) is fine here (M2 directive). All quantum
# comparisons go through the M1 `denoted_matrix` reference semantics; uncontrolled
# `Ad` drops the global phase (ker Ad = U(1)), so uncontrolled comparisons are
# "up to global phase" (`≈ₚ`), while the phase-EXACT controlled decompositions
# compare exactly.

using Test
using Random
using LinearAlgebra
using Sturm
using Sturm: U2, Perm, MCX, Ctrl, ctrl, denoted_matrix, nwires,
    X, Y, Z, H, S, T, Ry, Rz, Rx, I2, NEG_I, gphase, ⊗,
    EagerContext, DensityMatrixContext, eager, density,
    allocate!, apply!, q, deallocate!, ptrace!, current_context,
    statevector, density_matrix, apply_channel!, sqrt_u2, live_wires,
    consumed, is_consumed, mark_consumed!, CHART_EPS,
    _core, orkan_state_set!, _emit_u2!, _zyz_angles

# A random U(2) element (guarded — several M2 test files declare it).
if !@isdefined(rand_u2)
    function rand_u2(rng)
        v = randn(rng, 4)
        v ./= sqrt(sum(abs2, v))
        return U2(v[1], v[2], v[3], v[4], 2π * rand(rng) - π)
    end
end

# A random SU(2) element (phase 0) — for cases where phase would obscure.
if !@isdefined(rand_su2)
    function rand_su2(rng)
        v = randn(rng, 4)
        v ./= sqrt(sum(abs2, v))
        return U2(v[1], v[2], v[3], v[4], 0.0)
    end
end

# Matrix equality up to a single GLOBAL phase (uncontrolled Ad quotients U(1)).
if !@isdefined(approx_upto_phase)
    function approx_upto_phase(A::AbstractMatrix, B::AbstractMatrix; atol::Real=1e-7)
        size(A) == size(B) || return false
        i = argmax(abs.(B))
        if abs(B[i]) < 1e-12
            return isapprox(A, B; atol=atol)
        end
        ph = A[i] / B[i]
        abs(abs(ph) - 1) < 1e-5 || return false
        return isapprox(A, ph .* B; atol=atol)
    end
end

# Realize the 2^m × 2^m operator that `apply!(ctx, v, ·)` implements, by driving
# each computational-basis input and reading the output statevector as a column.
# Wires are passed MSB-first (position 1 = highest Orkan slot = high statevector
# bit), so the realized matrix is directly comparable to `denoted_matrix(v)`
# (§3.3 endianness pin). Basis inputs are set DIRECTLY on the Orkan state to
# avoid Ad-phase pollution from a gate-based |j⟩ preparation.
# `capacity` may exceed `nwires(v)` to leave room for kernel-internal scratch
# ancillas (k≥3 controls, ≥3-control MCX). The value's wires take slots 0…m-1
# and ancillas the higher slots; ancillas MUST return to |0⟩, so the output lies
# entirely in the first 2^m amplitudes — we read that block and ASSERT no
# amplitude leaked into the ancilla-nonzero subspace (a bad uncompute is caught
# loudly here, not silently truncated).
if !@isdefined(realized_matrix)
    function realized_matrix(v; capacity::Int=nwires(v), rng=nothing)
        m = nwires(v)
        N = 1 << m
        M = Matrix{ComplexF64}(undef, N, N)
        for j in 0:(N-1)
            eager(capacity; rng=rng) do ctx
                wires = ntuple(_ -> allocate!(ctx), m)     # slots 0 … m-1
                st = _core(ctx).state
                orkan_state_set!(st, 0, 0, zero(ComplexF64)) # clear the init |0…0⟩
                orkan_state_set!(st, j, 0, one(ComplexF64))  # set |j⟩
                apply!(ctx, v, reverse(wires))               # MSB → highest slot
                col = statevector(ctx)
                leak = 0.0
                @inbounds for r in (N+1):length(col)
                    leak += abs2(col[r])
                end
                @assert leak < 1e-10 "ancilla leakage $(leak) — a compute/uncompute did not clear scratch to |0⟩"
                @inbounds for r in 1:N
                    M[r, j+1] = col[r]
                end
                nothing
            end
        end
        return M
    end
end
