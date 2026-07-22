# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# Sturm.jl F16 (bead Sturm.jl-vanm): the context-parameterized register handles
# (`QBool{C}`, `QInt{W,C}`, `WireRef{C}`, views), the F15 number-like-handle
# contract, and the F19 symmetric bicharacter trait. This is a REPRESENTATION-
# ONLY refactor: the M3–M7 law suites are the physics-regression gate and must
# pass UNCHANGED. This file adds the NEW obligations F16/F15/F19 introduce:
#   - type propagation: every handle/view carries a concrete context parameter;
#   - inference: the typed workers and hot paths are `@inferred`-clean, while the
#     public zero-context barrier is intentionally existential (dynamic scope);
#   - mixed-context / closed-context loud failures BEFORE any state mutation;
#   - F15: no `Number`/`Integer` subtyping, loud `==`/`hash`/`isless`;
#   - F19: the bicharacter laws (identity, bilinearity, nondegeneracy, symmetry)
#     and the additive-vs-bitwise action-group distinction; the CZ-symmetry law
#     consults the trait's DECLARED symmetry.
#
# Physics/spec grounding: PRD-v2 §3.3 (dual/pairing), §3.4 (number-like handles,
# two worlds), §3.6 (Ruling D), §3.8 (portability), §6 (P7/P8/P9), §7.3 (CZ).

using Test
using Sturm
using Sturm: eager, density, contextof, contexttype, register_style,
    NumberLikeHandleStyle, AddressingModeStyle, duality, symmetry, transform,
    bicharacter, pairing_exponent, action_group, AddFamily, XorFamily,
    Cyclic2PowGroup, BitVectorGroup, SymmetricPairing, Pow2Bicharacter,
    DualView, View, EagerContext, DensityMatrixContext, dual, not!, add!,
    statevector, AbstractQRegister, AbstractQubit, WireRef, _here

@testset "F16 — context-parameterized register handles" begin

    @testset "type propagation (owned/borrowed handles + views carry C)" begin
        eager(6) do ctx
            q = QBool(ctx, false)
            x = QInt{3}(ctx, 5)
            @test typeof(q) === QBool{EagerContext}
            @test typeof(x) === QInt{3,EagerContext}
            @test typeof(x[2]) === WireRef{EagerContext}
            @test fieldtype(typeof(q), :ctx) === EagerContext
            @test fieldtype(typeof(x), :ctx) === EagerContext
            @test fieldtype(typeof(x[2]), :ctx) === EagerContext
            # views carry C through the PARENT type (no redundant wrapper param)
            @test dual(q) isa DualView{QBool{EagerContext}}
            @test dual(x) isa DualView{QInt{3,EagerContext}}
            @test Sturm.view(Sturm.H, q) isa View{typeof(Sturm.H),QBool{EagerContext}}
            @test contextof(q) === ctx
            @test contextof(dual(q)) === ctx           # view delegates to parent
            @test contexttype(typeof(x)) === EagerContext
            @test contexttype(typeof(dual(x))) === EagerContext
            Int(x); Bool(q)                            # consume so the region exits clean
        end
        # subtype hierarchy (F16 §3)
        @test QBool{EagerContext} <: AbstractQubit{EagerContext}
        @test QBool{EagerContext} <: AbstractQRegister{EagerContext}
        @test QInt{3,EagerContext} <: AbstractQRegister{EagerContext}
        @test WireRef{EagerContext} <: AbstractQubit{EagerContext}
        @test !(QInt{3,EagerContext} <: AbstractQubit)   # QInt is multi-wire, not a qubit
    end

    @testset "partial `UnionAll` spellings still match (source compatibility)" begin
        eager(4) do ctx
            q = QBool(ctx, false)
            x = QInt{3}(ctx, 0)
            @test q isa QBool                 # bare partial spelling
            @test x isa QInt{3}               # width-only partial spelling
            @test x isa QInt                  # fully-bare
            @test QInt{3} <: QInt
            @test QInt{3,EagerContext} <: QInt{3}
            Int(x); Bool(q)
        end
    end

    @testset "different context KINDS parameterize distinctly (DM)" begin
        density(2) do ctx
            q = QBool(ctx, false)
            @test typeof(q) === QBool{DensityMatrixContext}
            @test fieldtype(typeof(q), :ctx) === DensityMatrixContext
        end
    end

    @testset "inference — typed workers & hot paths are @inferred (F16 §11)" begin
        eager(16) do ctx
            # typed workers infer the concrete handle type
            @test (@inferred QBool(ctx, false)) isa QBool{EagerContext}
            @test (@inferred QInt{4}(ctx, 0)) isa QInt{4,EagerContext}
            x = QInt{4}(ctx, 3)
            @test (@inferred getindex(x, 2)) isa WireRef{EagerContext}
            @test (@inferred dual(x)) isa DualView{QInt{4,EagerContext}}
            @test (@inferred add!(x, 1)) isa QInt{4,EagerContext}
            q = QBool(ctx, false)
            @test (@inferred dual(q)) isa DualView{QBool{EagerContext}}
            @test (@inferred not!(q)) isa QBool{EagerContext}
            # _here returns the CONCRETE C (the whole point of F16)
            @test Core.Compiler.return_type(_here, Tuple{QBool{EagerContext}}) === EagerContext
            @test Core.Compiler.return_type(_here, Tuple{QInt{4,EagerContext}}) === EagerContext
            # Ruling-D exact Eager cast returns
            @test (@inferred Int(x)) isa Int
            @test (@inferred Bool(q)) isa Bool
        end
        # the public zero-context barrier is INTENTIONALLY existential (dynamic
        # scope): it infers the UnionAll, never the concrete parameter (F16 §4).
        eager(2) do ctx
            @test Core.Compiler.return_type(() -> QBool(false), Tuple{}) === QBool
            q = QBool(false); Bool(q)
        end
    end

    @testset "mixed-context — loud reject BEFORE any mutation (F16 §5)" begin
        # two DISTINCT EagerContext instances share C but must not mix
        @test_throws ArgumentError eager(1) do _
            qo = QBool(false)                 # owned by the OUTER context
            eager(1) do _
                Bool(qo)                      # active = inner ≠ qo.ctx
            end
        end
        # a cross-context ACTION is rejected before it can touch state: the inner
        # statevector is unchanged after the (rejected) op.
        eager(1) do outer
            qo = QBool(false)
            eager(1) do inner
                before = statevector(inner)
                @test_throws ArgumentError not!(qo)   # foreign handle
                @test statevector(inner) == before    # no backaction preceded the throw
            end
            Bool(qo)
        end
    end

    @testset "closed-context — dangling handle rejects before FFI (F16 §5.1)" begin
        escaped = eager(1) do ctx
            QBool(false)                       # handle escapes the block; ctx torn down after
        end
        # rebinding the torn-down context must fail loud, not reach freed storage
        @test_throws ErrorException @context escaped.ctx begin
            Bool(escaped)
        end
        # an escaped QInt likewise
        escq = eager(2) do ctx
            QInt{2}(1)
        end
        @test_throws ErrorException @context escq.ctx begin
            add!(escq, 1)
        end
    end
end

@testset "F15 — number-like-handle contract (no host value semantics)" begin
    @test !(QBool{EagerContext} <: Number)
    @test !(QBool{EagerContext} <: Integer)
    @test !(QInt{3,EagerContext} <: Number)
    @test !(QInt{3,EagerContext} <: Integer)
    @test !(WireRef{EagerContext} <: Number)

    @test register_style(QBool{EagerContext}) isa NumberLikeHandleStyle
    @test register_style(QInt{3,EagerContext}) isa NumberLikeHandleStyle
    @test register_style(DualView{QBool{EagerContext}}) isa AddressingModeStyle

    # loud failure surface — never Base's silent identity-shaped fallback
    eager(4) do ctx
        q = QBool(ctx, false)
        r = QBool(ctx, false)
        x = QInt{2}(ctx, 1)
        @test_throws ArgumentError (q == r)
        @test_throws ArgumentError (q == 0)
        @test_throws ArgumentError (0 == q)
        @test_throws ArgumentError isequal(q, r)
        @test_throws ArgumentError hash(q)
        @test_throws ArgumentError (x < x)
        # a register is a HANDLE, not data — `missing` gets NO three-valued pass
        # (the disambiguator methods stay LOUD; F15 has no exemption for Missing)
        @test_throws ArgumentError (q == missing)
        @test_throws ArgumentError (missing == q)
        @test_throws ArgumentError isequal(q, missing)
        @test_throws ArgumentError isequal(missing, q)
        @test_throws ArgumentError isless(q, missing)
        @test_throws ArgumentError isless(missing, q)
        # `===` remains the handle-identity primitive (inspects no state)
        @test q === q
        @test q !== r
        @test dual(q) !== dual(q)              # fresh wrapper each call
        Bool(q); Bool(r); Int(x)
    end
end

@testset "F19 — symmetric bicharacter trait (§3.3/§7.3)" begin
    @testset "duality trait shape + context-freeness" begin
        @test transform(duality(QBool)) === Sturm.H
        @test duality(QInt{3}).transform == Sturm.QFT(3, false)
        # the trait does NOT depend on C: same spec for Eager and DM parameters
        @test duality(QInt{3,EagerContext}) === duality(QInt{3,DensityMatrixContext})
        @test symmetry(duality(QBool)) isa SymmetricPairing
        @test symmetry(duality(QInt{4})) isa SymmetricPairing
    end

    @testset "action-group distinction: add! (cyclic) vs ⊻ (bitvector)" begin
        for W in (1, 2, 3, 4)
            @test action_group(QInt{W}, AddFamily()) isa Cyclic2PowGroup{W}
            @test action_group(QInt{W}, XorFamily()) isa BitVectorGroup{W}
        end
    end

    @testset "bicharacter laws — exact, exhaustive for small W" begin
        for W in 1:4
            b = Pow2Bicharacter{W}()
            N = 1 << W
            # (1) identity: B(0,y) = B(x,0) = 1
            for k in 0:(N - 1)
                @test pairing_exponent(b, 0, k) == 0
                @test pairing_exponent(b, k, 0) == 0
                @test bicharacter(b, 0, k) ≈ 1
                @test bicharacter(b, k, 0) ≈ 1
            end
            # (2) bilinearity: B(x+x', y) = B(x,y)·B(x',y) (and symmetric arg)
            for x in 0:(N - 1), xp in 0:(N - 1), y in 0:(N - 1)
                @test bicharacter(b, mod(x + xp, N), y) ≈ bicharacter(b, x, y) * bicharacter(b, xp, y)
                @test bicharacter(b, x, mod(y + xp, N)) ≈ bicharacter(b, x, y) * bicharacter(b, x, xp)
            end
            # (3) nondegeneracy: every nonzero x has some y with B(x,y) ≠ 1
            for x in 1:(N - 1)
                @test any(y -> !(bicharacter(b, x, y) ≈ 1), 0:(N - 1))
            end
            # (4) declared symmetry: B(x,y) = B(y,x)
            for x in 0:(N - 1), y in 0:(N - 1)
                @test bicharacter(b, x, y) ≈ bicharacter(b, y, x)
                @test pairing_exponent(b, x, y) == pairing_exponent(b, y, x)
            end
        end
    end

    @testset "CZ symmetry consults the DECLARED trait symmetry (§7.3)" begin
        # the law is licensed ONLY because the shipped ℤ₂ trait CLAIMS symmetry
        @test symmetry(duality(QBool)) isa SymmetricPairing
        # ...and the two operand orders denote the same channel (statevector-level
        # on a generic product input; CZ is diagonal so the states coincide)
        sv_qr = eager(2) do ctx
            q = QBool(ctx, 0.5, 0.3); r = QBool(ctx, 0.5, 1.1)
            q̂ = dual(q); q̂ ⊻= r
            statevector(ctx)
        end
        sv_rq = eager(2) do ctx
            q = QBool(ctx, 0.5, 0.3); r = QBool(ctx, 0.5, 1.1)
            r̂ = dual(r); r̂ ⊻= q
            statevector(ctx)
        end
        @test sv_qr ≈ sv_rq
    end
end
