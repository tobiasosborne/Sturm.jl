using Test
using Sturm
using Sturm: syndrome_extract!, correct!, decode_with_correction!

# Sturm.jl-870 P1+P2: Steane [[7,1,3]] syndrome extraction + correction.
#
# Physics ground truth: Steane 1996 quant-ph/9601029 §3.3 eq. 16-17 (parity
# check matrices H_C, H_{C+}); §3.5 Theorem 6 (correction in two bases is
# sufficient); p. 21 (ancilla + CNOT extraction protocol).
#
# Stabiliser generators (both X-type and Z-type, same supports — CSS self-dual):
#   g₁ = {1, 3, 5, 7}     — binary 001, so bit 1 (LSB) of syndrome
#   g₂ = {2, 3, 6, 7}     — binary 010, so bit 2
#   g₃ = {4, 5, 6, 7}     — binary 100, so bit 3
# By construction, syndrome value (in decimal) = qubit index of the error.
#
# P1 scope:   syndrome_extract!(7 QBools) → (sx::UInt8, sz::UInt8)
#             correct!(7 QBools, sx, sz)  — applies X on q[sx] and/or Z on q[sz]
# P2 scope:   decode_with_correction!(Steane, 7 QBools) → QBool
#             21 weight-1 errors recovered exactly; N=500 statistical test.

# Helper: encode a classical logical bit and return the 7-tuple.
_encode_bit(v::Bool) = encode!(Steane(), QBool(Float64(v)))

@testset "Steane [[7,1,3]] syndrome extraction + correction (bead 870)" begin

    # ── P1: syndrome_extract! correctness on all 21 weight-1 errors ───────────

    @testset "P1: no error → syndrome (0, 0) on encoded |0⟩_L" begin
        @context EagerContext() begin
            phys = _encode_bit(false)
            sx, sz = syndrome_extract!(phys)
            @test sx == 0
            @test sz == 0
            # residual state should still decode to |0⟩_L
            @test Bool(decode!(Steane(), phys)) === false
        end
    end

    @testset "P1: no error → syndrome (0, 0) on encoded |1⟩_L" begin
        @context EagerContext() begin
            phys = _encode_bit(true)
            sx, sz = syndrome_extract!(phys)
            @test sx == 0
            @test sz == 0
            @test Bool(decode!(Steane(), phys)) === true
        end
    end

    @testset "P1: single X error on each qubit → sx == qubit index, sz == 0" begin
        for err_qubit in 1:7
            @context EagerContext() begin
                phys = _encode_bit(false)
                X!(phys[err_qubit])
                sx, sz = syndrome_extract!(phys)
                @test sx == err_qubit
                @test sz == 0
                ptrace!.(phys)   # cleanup for this iteration's ctx
            end
        end
    end

    @testset "P1: single Z error on each qubit → sx == 0, sz == qubit index" begin
        for err_qubit in 1:7
            @context EagerContext() begin
                phys = _encode_bit(false)
                Z!(phys[err_qubit])
                sx, sz = syndrome_extract!(phys)
                @test sx == 0
                @test sz == err_qubit
                ptrace!.(phys)
            end
        end
    end

    @testset "P1: single Y error on each qubit → both syndromes == qubit index" begin
        # Y = iXZ (up to phase, which is unobservable for channels)
        for err_qubit in 1:7
            @context EagerContext() begin
                phys = _encode_bit(false)
                Y!(phys[err_qubit])
                sx, sz = syndrome_extract!(phys)
                @test sx == err_qubit
                @test sz == err_qubit
                ptrace!.(phys)
            end
        end
    end

    # ── P2: full round-trip recovery via decode_with_correction! ──────────────

    @testset "P2: X error recovery on |0⟩_L for every qubit" begin
        for err_qubit in 1:7
            @context EagerContext() begin
                phys = _encode_bit(false)
                X!(phys[err_qubit])
                logical = decode_with_correction!(Steane(), phys)
                @test Bool(logical) === false
            end
        end
    end

    @testset "P2: Z error recovery on |0⟩_L for every qubit" begin
        for err_qubit in 1:7
            @context EagerContext() begin
                phys = _encode_bit(false)
                Z!(phys[err_qubit])
                logical = decode_with_correction!(Steane(), phys)
                # Z on |0⟩_L is still |0⟩_L (Z|0⟩ = |0⟩), so recovery is trivial —
                # BUT the syndrome machinery must still emit no junk.
                @test Bool(logical) === false
            end
        end
    end

    @testset "P2: Y error recovery on |0⟩_L for every qubit" begin
        for err_qubit in 1:7
            @context EagerContext() begin
                phys = _encode_bit(false)
                Y!(phys[err_qubit])
                logical = decode_with_correction!(Steane(), phys)
                @test Bool(logical) === false
            end
        end
    end

    @testset "P2: X error recovery on |1⟩_L for every qubit" begin
        for err_qubit in 1:7
            @context EagerContext() begin
                phys = _encode_bit(true)
                X!(phys[err_qubit])
                logical = decode_with_correction!(Steane(), phys)
                @test Bool(logical) === true
            end
        end
    end

    @testset "P2: no-error roundtrip on both logical states" begin
        for v in (false, true)
            @context EagerContext() begin
                phys = _encode_bit(v)
                # no error injected
                logical = decode_with_correction!(Steane(), phys)
                @test Bool(logical) === v
            end
        end
    end

    # ── P2 statistical: N=500 random weight-1 errors → exact recovery ────────
    #
    # Distance-3 code: deterministic recovery for every weight-1 error. No
    # tolerance needed — 500/500 exact is the contract.
    @testset "P2 N=500 random weight-1 errors on |0⟩_L: exact recovery" begin
        pauli_ops = (X!, Y!, Z!)
        N = 500
        successes = 0
        for _ in 1:N
            @context EagerContext() begin
                phys = _encode_bit(false)
                err_qubit = rand(1:7)
                err_op    = rand(pauli_ops)
                err_op(phys[err_qubit])
                logical = decode_with_correction!(Steane(), phys)
                if Bool(logical) === false
                    successes += 1
                end
            end
        end
        @test successes == N
    end

    @testset "P2 N=500 random weight-1 errors on |1⟩_L: exact recovery" begin
        pauli_ops = (X!, Y!, Z!)
        N = 500
        successes = 0
        for _ in 1:N
            @context EagerContext() begin
                phys = _encode_bit(true)
                err_qubit = rand(1:7)
                err_op    = rand(pauli_ops)
                err_op(phys[err_qubit])
                logical = decode_with_correction!(Steane(), phys)
                if Bool(logical) === true
                    successes += 1
                end
            end
        end
        @test successes == N
    end

end
