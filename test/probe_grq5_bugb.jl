# Probe for bead Sturm.jl-grq5 (Bug B fix in qsvt_reflect!).
#
# Bug B isolator: with reflection-QSP phases for the IDENTITY polynomial
# P(x) = x (single phase φ = 0), the qsvt_reflect circuit body is just
# the BE oracle U applied once. The |anc=0…0⟩-block of U is H/α by the
# block-encoding identity. So M must equal H/α exactly, with |c|=1.
#
# This holds independently of `_reflect_ancilla_phase!` vs single-qubit Rz,
# because Rz(0) = I and Π^0 = I — both are the identity at φ=0. So this
# probe verifies the BE-oracle path, not Bug B itself.
#
# Bug B isolator with non-trivial phase: degree-3 phases derived from
# directly composing -T_3(λ) = 3λ - 4λ³ as a 3-step reflection-QSP body
# in the EIGENBASIS — but those phases are exactly _oaa_phases_half_deg3
# only for a specific OAA-lifted BE convention. The generic deg-3 phases
# for -T_3 on an arbitrary BE are derivable by symmetric-QSP optimization
# (Wang-Dong, GSLW Theorem 27); deferred — bead Sturm.jl-50k1 / l5s5.
#
# Therefore Bug B will be verified end-to-end via test_qsvt_amplitude_level.jl
# T3 cases AFTER Bug A (l5s5) is also fixed. Session 89's empirical claim
# that T3 with hand-validated phases gives |c|=0.637 was on a different
# probe setup (likely the OAA-lifted BE) and does not reproduce here.
#
# The test below exercises the BE oracle path on a 2-ancilla LCU to confirm
# the refactored circuit produces the correct identity operator M = H/α.

using Test, Sturm
using Sturm: PauliHamiltonian, PauliTerm, pauli_X, pauli_Y, pauli_Z,
             block_encode_lcu, EagerContext, QBool, _qsvt_reflect_naked!
using LinearAlgebra: norm
using Random: MersenneTwister

function reflect_block_operator(H::PauliHamiltonian{N},
                                 phi::Vector{Float64}) where {N}
    be = block_encode_lcu(H)
    dim_sys = 1 << N
    M = zeros(ComplexF64, dim_sys, dim_sys)
    for j in 0:dim_sys-1
        ctx = EagerContext()
        col = zeros(ComplexF64, dim_sys)
        @context ctx begin
            sys = [QBool(ctx, Float64((j >> k) & 1)) for k in 0:N-1]
            ancillas = [QBool(ctx, 0.0) for _ in 1:be.n_ancilla]
            _qsvt_reflect_naked!(sys, be, phi, ancillas)
            dim = 1 << Int(ctx.orkan.raw.qubits)
            amps = unsafe_wrap(Array{ComplexF64,1}, ctx.orkan.raw.data, dim)
            for i in 0:dim_sys-1
                col[i+1] = amps[i+1]
            end
        end
        M[:, j+1] .= col
    end
    return M
end

closest_scalar_fit(M, S) = sum(conj.(S) .* M) / sum(abs2.(S))

@testset "Bug B (grq5) sanity — _qsvt_reflect_naked! with φ=[0] on multi-anc BE" begin
    sX = ComplexF64[0 1; 1 0]
    sY = ComplexF64[0 -im; im 0]
    sZ = ComplexF64[1 0; 0 -1]
    op_tol = 1e-6

    # ── 2-ancilla BE (3-term LCU) — Bug B fires here when φ ≠ 0 ──
    @testset "n_anc=2: M(φ=[0]) ≈ H/α" begin
        H_mat = 0.3 * sX + 0.2 * sY + 0.4 * sZ
        α = 0.3 + 0.2 + 0.4
        H = PauliHamiltonian{1}([
            PauliTerm{1}(0.3, (pauli_X,)),
            PauliTerm{1}(0.2, (pauli_Y,)),
            PauliTerm{1}(0.4, (pauli_Z,))])
        be = block_encode_lcu(H)
        @test be.n_ancilla == 2

        M = reflect_block_operator(H, [0.0])
        c = closest_scalar_fit(M, ComplexF64.(H_mat ./ α))
        @info "φ=[0] · 2-anc BE: |c|=$(round(abs(c), digits=6)) residual=$(round(norm(M - c*(H_mat./α)), digits=6))"
        @test abs(abs(c) - 1.0) < op_tol
        @test norm(M - c * (H_mat ./ α)) < op_tol
    end

    # ── 1-ancilla BE (2-term LCU) — Bug B does NOT fire ──
    @testset "n_anc=1: M(φ=[0]) ≈ H/α" begin
        H_mat = 0.3 * sX + 0.4 * sZ
        α = 0.7
        H = PauliHamiltonian{1}([
            PauliTerm{1}(0.3, (pauli_X,)), PauliTerm{1}(0.4, (pauli_Z,))])
        be = block_encode_lcu(H)
        @test be.n_ancilla == 1

        M = reflect_block_operator(H, [0.0])
        c = closest_scalar_fit(M, ComplexF64.(H_mat ./ α))
        @info "φ=[0] · 1-anc BE: |c|=$(round(abs(c), digits=6)) residual=$(round(norm(M - c*(H_mat./α)), digits=6))"
        @test abs(abs(c) - 1.0) < op_tol
        @test norm(M - c * (H_mat ./ α)) < op_tol
    end
end
