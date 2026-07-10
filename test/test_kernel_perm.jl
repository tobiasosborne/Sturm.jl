# SPDX-License-Identifier: AGPL-3.0-only
#
# Milestone M1 law tests for the `Perm` process value — the phase-free
# classical-reversible corner and, crucially, its CLOSURE under `ctrl`
# (PRD-v2 §4.1). Semantic equality goes through `≈` (denoted_permutation).

using Test
using Sturm
using Sturm: Perm, ctrl, ⊗, denoted_matrix, nwires
using Sturm: MCX, denoted_permutation

# small fixtures
Xp() = Perm(1, [MCX(Int[], 1)])          # bare X on 1 wire
CXp() = Perm(2, [MCX([1], 2)])           # control wire 1 (MSB), target wire 2
idp(n) = Perm(n, MCX[])                   # identity permutation

@testset "Perm — §4.1 classical corner" begin

    @testset "T9 — ctrl(Perm) is a Perm, denotes Toffoli (§4.1 closure)" begin
        cx = CXp()
        tof = ctrl(cx)
        @test tof isa Perm
        @test nwires(tof) == 3
        # Toffoli: swap the two all-controls-set basis states (6 ↔ 7).
        @test denoted_permutation(tof) == [0, 1, 2, 3, 4, 5, 7, 6]
        # ctrl(ctrl(X)) is Toffoli-grade too (no special case).
        @test ctrl(ctrl(Xp())) isa Perm
        @test denoted_permutation(ctrl(ctrl(Xp()))) == [0, 1, 2, 3, 4, 5, 7, 6]
        # denoted_matrix cross-check: 8×8 permutation matrix of the Toffoli.
        M = denoted_matrix(tof)
        expected = zeros(ComplexF64, 8, 8)
        perm = [0, 1, 2, 3, 4, 5, 7, 6]
        for b in 0:7
            expected[perm[b+1]+1, b+1] = 1
        end
        @test M ≈ expected
    end

    @testset "T-perm-adj — adjoint / involution (§4.1)" begin
        for p in (Xp(), CXp(), ctrl(CXp()))
            @test adjoint(p) ∘ p ≈ idp(p.n)
            @test p ∘ adjoint(p) ≈ idp(p.n)
        end
        # each MCX is a self-inverse: X∘X = id
        @test Xp() ∘ Xp() ≈ idp(1)
    end

    @testset "T-perm-tensor — ⊗ closure (§4.1)" begin
        # X ⊗ X flips both wires independently: b ↦ b ⊻ 0b11.
        xx = Xp() ⊗ Xp()
        @test xx isa Perm
        @test nwires(xx) == 2
        @test denoted_permutation(xx) == [3, 2, 1, 0]
        # ⊗ places the first factor on the leading (MSB) block.
        cx_x = CXp() ⊗ Xp()             # 3 wires: CX on wires 1,2; X on wire 3
        @test cx_x isa Perm
        @test nwires(cx_x) == 3
    end

    @testset "T-perm-homo — ctrl homomorphism over ∘ (§4.2)" begin
        # ctrl(p ∘ q) == ctrl(p) ∘ ctrl(q) at the permutation level.
        p = CXp()
        q = Perm(2, [MCX(Int[], 1)])    # X on wire 1
        @test ctrl(p ∘ q) ≈ ctrl(p) ∘ ctrl(q)
    end

    @testset "T-perm-eq — semantic equality (§4.1)" begin
        # two different generator lists, one permutation (X∘X∘X == X).
        a = Perm(1, [MCX(Int[], 1), MCX(Int[], 1), MCX(Int[], 1)])
        @test a ≈ Xp()
        @test !(Xp() ≈ idp(1))
        # differing widths are never ≈.
        @test !(Xp() ≈ idp(2))
    end
end
