# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# Sturm.jl M6 (bead Sturm.jl-80g6): QInt{W}, x[i] slices (D2), the two arithmetic
# worlds (D12), the Pontryagin sign pins, the QFT dual, and the strict-mode
# lost-binding detector. Named law tests per PRD-v2 §3.3/§3.4. Outcomes are
# DETERMINISTIC (every statement ends on an exact basis state), so a single shot
# reads the exact integer — no tolerance on the value (float laws use ≈).

using Test
using LinearAlgebra
using Sturm
using Sturm: QInt, add!, sub!, superpose!, dual, when, not!
using Sturm: QFT, P, WireRef, AbstractQubit
using Sturm: eager, apply!, allocate!, statevector, denoted_matrix, q, is_consumed,
    _emit_x!, adjoint

# --- Test tooling: the emitted unitary of a W-wire value, PHASE-HONEST ------
# Prep basis states with the NATIVE `_emit_x!` (an honest σx — NOT the fused
# ZYZ `apply!(X)`, which realises −iσx and pollutes raw amplitudes with a global
# phase, Ad's kernel). This makes the emitted matrix comparable to the denoted
# matrix on the nose (test tooling is licensed to reach `Sturm.` internals).
function emitted_matrix(f, W::Int)
    N = 1 << W
    M = Matrix{ComplexF64}(undef, N, N)
    for jin in 0:(N - 1)
        col = eager(W) do ctx
            ws = ntuple(_ -> allocate!(ctx), W)
            slots = [q(ctx, w) for w in ws]
            for j in 1:W
                ((jin >> (W - j)) & 1) == 1 && _emit_x!(ctx, slots[j])
            end
            apply!(ctx, f, ws)
            sv = statevector(ctx)
            amp = zeros(ComplexF64, N)
            mask = 0
            for s in slots; mask |= (1 << s); end
            for idx in 0:(N - 1)
                (idx & ~mask) == 0 || continue
                used = 0
                for (p, s) in enumerate(slots); used |= ((idx >> s) & 1) << (W - p); end
                amp[used + 1] = sv[idx + 1]
            end
            amp
        end
        M[:, jin + 1] = col
    end
    return M
end

@testset "M6 — QInt{W}, slices, two worlds, Pontryagin pins" begin

    # =====================================================================
    # §3.3 The QFT dual value: emission ≡ analytic DFT (the convention anchor)
    # =====================================================================
    @testset "QFT emission ≡ analytic DFT (basis sweep + denoted matrix, W≤3)" begin
        for W in 1:3
            F = QFT(W, false)
            @test emitted_matrix(F, W) ≈ denoted_matrix(F)
            @test emitted_matrix(adjoint(F), W) ≈ denoted_matrix(QFT(W, true))
            # F† F = I and F is unitary
            @test denoted_matrix(QFT(W, true)) * denoted_matrix(F) ≈ Matrix{ComplexF64}(I, 1 << W, 1 << W)
        end
        # P(θ) = diag(1, e^{iθ}); P(π) = Z exactly
        @test denoted_matrix(P(0.7)) ≈ ComplexF64[1 0; 0 cis(0.7)]
        @test P(π) ≈ Sturm.Z
    end

    # =====================================================================
    # §3.4 Sign pin #1 — translation: add!(x,1)|0⟩ ⇒ Int(x)==1 (fixes T_a=F†D_{+a}F)
    # =====================================================================
    @testset "Sign pin #1 — add! is +a translation (not 2^W−a), with wrap" begin
        for W in 2:4
            @test eager(W) do ctx; x = QInt{W}(0); add!(x, 1); Int(x) end == 1
            for n in 0:(1 << W)-1, a in 0:(1 << W)-1
                r = eager(W) do ctx; x = QInt{W}(n); add!(x, a); Int(x) end
                @test r == mod(n + a, 1 << W)          # overflow WRAPS (ℤ_{2^W})
            end
        end
        # sub! is the in-place inverse
        @test eager(3) do ctx; x = QInt{3}(2); sub!(x, 5); Int(x) end == mod(2 - 5, 8)
    end

    # =====================================================================
    # §3.3 Sign pin #2 — modulation: superpose!; x̂ += a; Int(dual(x)) == a
    #   (fixes the r6/B2 view sign as D_{-a}; the WRONG D_{+a} reads −a mod 2^W)
    # =====================================================================
    @testset "Sign pin #2 — dual-view modulation is D_{-a} (Int(dual)==a)" begin
        for W in 2:3, a in 0:(1 << W)-1
            r = eager(W) do ctx
                x = QInt{W}(0); superpose!(x)
                x̂ = dual(x); x̂ += a
                Int(dual(x))
            end
            @test r == a
        end
        # modulation leaves the PRIMAL value unchanged (a global phase on |n⟩)
        for W in 2:3, n in 0:(1 << W)-1, a in 0:(1 << W)-1
            r = eager(W) do ctx; x = QInt{W}(n); x̂ = dual(x); x̂ += a; Int(x) end
            @test r == n
        end
    end

    # =====================================================================
    # §3.3 F²-vs-unwrap signature — the view UNWRAPS (no op) vs the PROCESS negates
    # =====================================================================
    @testset "F²-vs-unwrap — dual(dual(x))===x (zero ops) vs QFT² = integer negation" begin
        # (a) the VIEW: structural unwrap, NO op emitted, state bit-identical
        zero_ops = eager(3) do ctx
            x = QInt{3}(3); superpose!(x)            # a nontrivial coherent state
            sv1 = statevector(ctx)
            y = dual(dual(x))
            sv2 = statevector(ctx)
            (y === x) && (sv1 == sv2)                # === and NO emission
        end
        @test zero_ops
        # (b) the PROCESS: applying the QFT value twice negates the integer
        for W in 2:3, n in 0:(1 << W)-1
            r = eager(W) do ctx
                x = QInt{W}(n)
                apply!(ctx, QFT(W, false), x.wires)
                apply!(ctx, QFT(W, false), x.wires)
                Int(x)
            end
            @test r == mod(-n, 1 << W)               # F² = parity (x ↦ −x)
        end
    end

    # =====================================================================
    # §3.4/D12 The two worlds
    # =====================================================================
    @testset "Value world — fresh output, inputs stay live (P9)" begin
        for W in 2:3, n in 0:(1 << W)-1, a in 0:(1 << W)-1
            (s, x) = eager(2W + 1) do ctx; xr = QInt{W}(n); sr = xr + a; (Int(sr), Int(xr)) end
            @test s == mod(n + a, 1 << W)
            @test x == n                              # input stayed live and correct
        end
        # a + x (P8 promotion) and x + y
        @test eager(4) do ctx; x = QInt{2}(1); s = 2 + x; Int(s) end == 3
        for m in 0:3, n in 0:3
            (s, x, y) = eager(6) do ctx; xr = QInt{2}(m); yr = QInt{2}(n); sr = xr + yr; (Int(sr), Int(xr), Int(yr)) end
            @test (s, x, y) == (mod(m + n, 4), m, n)
        end
    end

    @testset "Action world — in-place, returns the SAME handle (registered exception)" begin
        eager(2) do ctx
            x = QInt{2}(1)
            @test add!(x, 1) === x                    # same handle, no rebind
            @test superpose!(x) === x
            Int(x)
        end
        # quantum addend add!(y, x): |m⟩|n⟩ → |m⟩|n+m⟩, x stays live
        for W in 2:3, m in 0:(1 << W)-1, n in 0:(1 << W)-1
            (y, x) = eager(2W) do ctx; xr = QInt{W}(m); yr = QInt{W}(n); add!(yr, xr); (Int(yr), Int(xr)) end
            @test (y, x) == (mod(n + m, 1 << W), m)
        end
        # transversal ⊻ is (ℤ₂)^W, NOT ℤ_{2^W} addition
        for W in 2:3, m in 0:(1 << W)-1, n in 0:(1 << W)-1
            r = eager(2W) do ctx; xr = QInt{W}(m); yr = QInt{W}(n); xr ⊻= yr; v = Int(xr); Int(yr); v end
            @test r == (m ⊻ n)
        end
        # classical mixed ⊻
        @test eager(3) do ctx; x = QInt{3}(0b101); x ⊻= 0b011; Int(x) end == (0b101 ⊻ 0b011)
    end

    @testset "Reassociation — when(c) do add!(x,a) end is CONTROLLED addition (§4.2)" begin
        for cbit in (false, true), n in 0:3, a in 0:3
            r = eager(4) do ctx
                c = QBool(cbit); x = QInt{2}(n)
                when(c) do; add!(x, a); end
                v = Int(x); Bool(c); v
            end
            @test r == (cbit ? mod(n + a, 4) : n)
        end
    end

    # =====================================================================
    # D10 Strict-mode lost-binding detector (classical error; default silent)
    # =====================================================================
    @testset "Strict mode — x += a rebind flags; the negatives do not" begin
        # POSITIVE: `x = x + a` rebinds x to the fresh sum, drops the original
        @test_throws ErrorException eager(6; strict=true) do ctx
            x = QInt{2}(1); x = x + 1; return x
        end
        # NEGATIVE default (silent — the §3.9 doctrine intact)
        @test eager(6) do ctx; x = QInt{2}(1); x = x + 1; Int(x) end isa Int
        # NEGATIVE parent CONSUMED — measuring the input is a legitimate close
        @test eager(6; strict=true) do ctx; x = QInt{2}(1); s = x + 1; Int(x); Int(s) end isa Int
        # NEGATIVE both handles kept LIVE (returned/escaped) — parent never traced
        @test eager(6; strict=true) do ctx; x = QInt{2}(1); s = x + 1; return (x, s) end isa Tuple
        # the message names the fix
        try
            eager(6; strict=true) do ctx; x = QInt{2}(1); x = x + 1; return x end
        catch e
            @test occursin("lost binding", sprint(showerror, e))
            @test occursin("add!(x, a)", sprint(showerror, e))
        end
    end

    # =====================================================================
    # D2 x[i] slices, partial consumption, the misuse topology (§8.4/§8.5, S13)
    # =====================================================================
    @testset "x[i] slices — borrow, partial consumption, conjugate read" begin
        # x[i] is a WireRef borrowing the SHARED wire (no clone)
        eager(3) do ctx
            x = QInt{3}(0)
            r = x[2]
            @test r isa WireRef
            @test r isa AbstractQubit
            @test r.wire === x.wires[2]              # SAME wire
            Int(x)
        end
        # Bool(x[i]) reads the i-th bit MSB-first and consumes THE WIRE
        eager(3) do ctx
            x = QInt{3}(0b101)
            @test Bool(x[1]) == true                 # MSB
            @test Bool(x[2]) == false
            @test Bool(x[3]) == true
        end
        # Bool(x[i]) then Int(x) is a PARTIALLY-consumed error (§8.5)
        @test_throws ErrorException eager(3) do ctx
            x = QInt{3}(0b101); Bool(x[1]); Int(x)
        end
        # dual(x[i]) is the legal ℤ₂ dual of one wire (F = H); not!(dual) is a Z (Int unchanged)
        @test eager(2) do ctx; x = QInt{2}(0b10); not!(dual(x[1])); Int(x) end == 0b10
        # Bool(dual(x[i])) — the conjugate-basis wire read (BV §7.5 vocabulary)
        eager(2) do ctx
            x = QInt{2}(0)
            b = Bool(dual(x[1]))
            @test b isa Bool
            @test is_consumed(ctx, x.wires[1])
            Bool(x[2])
        end
        # BoundsError off 1:W
        @test_throws BoundsError eager(2) do ctx; x = QInt{2}(0); x[3] end
    end

    @testset "Misuse topology — every wrong program to a loud, named error" begin
        # dual(x)[i] — define-to-throw (register dual is not a tensor product)
        eager(2) do ctx
            x = QInt{2}(0)
            @test hasmethod(getindex, Tuple{typeof(dual(x)), Int})   # DEFINED (not MethodError)
            try; dual(x)[1]; @test false catch e
                @test e isa ArgumentError
                @test occursin("NOT a tensor product", sprint(showerror, e))
                @test occursin("dual(x[1])", sprint(showerror, e))
            end
            Int(x)
        end
        # QInt{W}(n) range → DomainError; add! overflow is NOT an error (wraps)
        @test_throws DomainError eager(2) do ctx; QInt{2}(4) end
        @test_throws DomainError eager(2) do ctx; QInt{2}(-1) end
        # x ⊻= x aliasing (through the shared WireID)
        @test_throws ErrorException eager(2) do ctx; x = QInt{2}(1); x ⊻= x end
        # x ⊻= x[i] — whole register with its own slice
        @test_throws ArgumentError eager(2) do ctx; x = QInt{2}(1); x ⊻= x[1] end
        # width mismatch
        @test_throws ArgumentError eager(5) do ctx; x = QInt{2}(1); y = QInt{3}(1); x ⊻= y end
        # measurement under `when` (guardrail 1)
        @test eager(3) do ctx
            c = QBool(true); x = QInt{2}(1); flagged = false
            when(c) do
                try; Int(x); catch e; flagged = occursin("forbidden inside a `when`", sprint(showerror, e)); end
            end
            Bool(c); flagged
        end
    end

    # =====================================================================
    # Namespace (CLAUDE.md conv 8): surface exported, kernel `public`
    # =====================================================================
    @testset "Namespace — surface exported, kernel public (not dumped)" begin
        for name in (:QInt, :add!, :sub!, :superpose!)
            @test Base.isexported(Sturm, name)           # surface: `using Sturm` gets them
        end
        for name in (:QFT, :P, :WireRef, :AbstractQubit)
            @test Base.ispublic(Sturm, name)             # documented, reachable as Sturm.<name>
            @test !Base.isexported(Sturm, name)          # but NOT dumped into `using Sturm`
            @test isdefined(Sturm, name)
        end
    end
end
