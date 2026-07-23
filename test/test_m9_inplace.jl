# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# Sturm.jl M9 (bead Sturm.jl-8oo9): the IN-PLACE-`Perm` COMPILER CONTRACT law
# tests (design `docs/design/m9-addq-inplace-perm-design.md` §9.2/§9.3). Inverse
# agreement, tiered verification, shared ancilla pool, the bit-order tripwire, the
# clean composite, and the PermClean certificate — all at the PERMUTATION level via
# single-basis replay (a `Perm` is a canonical 0/1 matrix; exhaustive basis
# agreement IS the channel-level check), never a marginal.

using Test
using Sturm
using Bennett
using Sturm: verify_inverse_pair, compile_inplace_perm, CompiledInplacePerm,
             VerifiedInversePair, FullSpaceMulProof, InverseContractError,
             AbstractInplaceProof, permclean_cert, PermClean, PortID,
             nwires, _replay_perm_basis, _modwidth, PERM_EQ_MAXW

# --- Test callables (ordinary Julia, full-space bijections / not) ----------

incW(W) = let M = 1 << W; v -> (v + oftype(v, 1)) % oftype(v, M); end   # +1 mod 2^W
decW(W) = let M = 1 << W; v -> (v + oftype(v, M - 1)) % oftype(v, M); end # −1 mod 2^W
clrlsb  = v -> v & ~oftype(v, 1)                                         # 2-to-1 (not bijective)
idfn    = v -> v

"""
    inplace_data_perm(compiled, W) -> Vector{Int}

The data-block permutation the composite `Perm` realizes on clean inputs
`|v⟩_D|0⟩_B|0⟩_A`, read by single-basis replay; asserts the scratch (`B ∪ A`)
returns to |0⟩ for every `v` (the clean-ancilla witness — never a marginal).
"""
function inplace_data_perm(compiled::CompiledInplacePerm{W}, Wv::Int) where {W}
    n = nwires(compiled.perm)
    out = Vector{Int}(undef, 1 << Wv)
    for v in 0:((1 << Wv) - 1)
        b = 0
        for j in 1:Wv
            ((v >> (Wv - j)) & 1) == 1 && (b |= (1 << (n - j)))
        end
        img = _replay_perm_basis(compiled.perm, b)
        for s in (Wv + 1):n
            @assert ((img >> (n - s)) & 1) == 0 "dirty scratch slot $s at v=$v"
        end
        d = 0
        for j in 1:Wv
            d |= Int((img >> (n - j)) & 1) << (Wv - j)
        end
        out[v + 1] = d
    end
    return out
end

@testset "M9 — in-place-Perm compiler contract (§3, §9.2/§9.3)" begin

    @testset "BOTH-COMPILE + EXHAUSTIVE-INVERSE + IN-PLACE realization" begin
        for W in (2, 3)
            pair = verify_inverse_pair(incW(W), decW(W), Val(W))
            @test pair isa VerifiedInversePair{W}
            @test pair.tier == :exhaustive
            compiled = compile_inplace_perm(pair)
            @test compiled isa CompiledInplacePerm{W}
            dp = inplace_data_perm(compiled, W)
            @test dp == [(v + 1) % (1 << W) for v in 0:((1 << W) - 1)]   # realizes +1
        end
    end

    @testset "SHARED-ANCILLA-POOL — nwires == 2W + max(A_f,A_g), not the sum" begin
        W = 3
        backend = Sturm._BENNETT_BACKEND[]
        cf = backend(incW(W), W, (;)); cg = backend(decW(W), W, (;))
        Af = length(cf.anc_positions); Ag = length(cg.anc_positions)
        compiled = compile_inplace_perm(verify_inverse_pair(incW(W), decW(W), Val(W)))
        @test nwires(compiled) == 2W + max(Af, Ag)
        @test nwires(compiled) < 2W + Af + Ag        # pool shared, NOT summed
        @test compiled.scratch_width == W + max(Af, Ag)
    end

    @testset "WRONG-INVERSE-REJECTED — first counterexample before apply" begin
        # (f, f): +1 is not an involution ⇒ g∘f = +2 ≠ id
        @test_throws InverseContractError verify_inverse_pair(incW(3), incW(3), Val(3))
    end

    @testset "NONBIJECTION-REJECTED — many-to-one f fails even if it compiles" begin
        # clrlsb is 2-to-1; no inverse can satisfy 3-inv on S_W.
        @test_throws InverseContractError verify_inverse_pair(clrlsb, idfn, Val(3))
        @test_throws InverseContractError verify_inverse_pair(idfn, clrlsb, Val(3))
    end

    @testset "BIT-ORDER-TRIPWIRE — asymmetric carry perm (increment)" begin
        # +1 is asymmetric: a bit-reversal in either embedding gives a DIFFERENT map;
        # the composite self-check (inside compile_inplace_perm) would catch it, and
        # the realized data-perm here confirms the exact carry structure.
        compiled = compile_inplace_perm(verify_inverse_pair(incW(3), decW(3), Val(3)))
        @test inplace_data_perm(compiled, 3) == [1, 2, 3, 4, 5, 6, 7, 0]
    end

    @testset "GENERIC-WIDE-NEEDS-PROOF — W>PERM_EQ_MAXW generic pair rejected" begin
        # No compile, no sampling — rejected on the tier decision alone.
        @test_throws ErrorException verify_inverse_pair(incW(3), decW(3), Val(PERM_EQ_MAXW + 1))
    end

    @testset "REGISTERED-PROOF-ACCEPTED — modular proof accepted above the ceiling" begin
        Nbig = (1 << 20) + 1                 # ndigits(N-1;base2) = 21 > PERM_EQ_MAXW
        @test _modwidth(Nbig) == 21
        d = invmod(2, Nbig)
        proof = FullSpaceMulProof{Nbig,21}(2, d)
        @test proof isa AbstractInplaceProof
        pair = verify_inverse_pair(idfn, idfn, Val(21); proof = proof)   # callables deferred
        @test pair.tier == :proof
        @test pair.proof === proof
        # a bad proof is rejected at construction
        @test_throws ArgumentError FullSpaceMulProof{Nbig,21}(2, 3)
    end

    @testset "PermClean certificate carried (declared clean ports = B ∪ A)" begin
        compiled = compile_inplace_perm(verify_inverse_pair(incW(3), decW(3), Val(3)))
        @test compiled.clean_ports == collect(4:nwires(compiled))   # {W+1 : 2W+A}
        cert = permclean_cert(compiled)
        @test cert isa PermClean
        @test length(cert.anc) == length(compiled.clean_ports)
        @test all(p isa PortID for p in cert.anc)
    end

    @testset "InverseContractError carries the counterexample (fail-loud message)" begin
        e = try
            verify_inverse_pair(incW(3), incW(3), Val(3)); nothing
        catch err; err; end
        @test e isa InverseContractError
        @test e.W == 3
        @test occursin("two-sided inverse", sprint(showerror, e))
    end
end
