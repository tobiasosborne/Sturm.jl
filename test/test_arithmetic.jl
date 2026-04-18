# Tests for src/library/arithmetic.jl — Draper 2000 QFT-adder and friends.
#
# TDD for Sturm.jl-ar7. Verifies:
#   superpose!(y) → add_qft!(y, a) → interfere!(y)  ==  y := (y + a) mod 2^L
# in the computational basis, for all (L, y, a) small enough to enumerate.

using Test
using Sturm

@testset "add_qft!: classical integer addition via QFT sandwich" begin

    # Exhaustive sweep at L = 2, 3, 4 — 576 cases total.
    @testset "exhaustive L=$L" for L in 2:4
        mask = (1 << L) - 1
        for y in 0:mask, a in 0:mask
            @context EagerContext() begin
                q = QInt{L}(y)
                superpose!(q)
                add_qft!(q, a)
                interfere!(q)
                @test Int(q) == (y + a) & mask
            end
        end
    end

    # Spot-check at wider L, with random draws — too many cases to enumerate.
    @testset "random L=$L" for L in (5, 6, 8)
        mask = (1 << L) - 1
        # 50 random (y, a) pairs at each L
        for _ in 1:50
            y = rand(0:mask); a = rand(0:mask)
            @context EagerContext() begin
                q = QInt{L}(y)
                superpose!(q)
                add_qft!(q, a)
                interfere!(q)
                @test Int(q) == (y + a) & mask
            end
        end
    end

    # Sanity-check that a=0 leaves y unchanged exactly.
    @testset "a=0 is identity (no net rotation)" begin
        for L in 2:6, y in (0, 1, (1 << L) - 1, rand(0:(1 << L) - 1))
            @context EagerContext() begin
                q = QInt{L}(y)
                superpose!(q)
                add_qft!(q, 0)
                interfere!(q)
                @test Int(q) == y
            end
        end
    end

    # Negative a: sub_qft! is add_qft!(-a).
    @testset "sub_qft! and negative add_qft!" begin
        L = 4; mask = (1 << L) - 1
        for y in 0:mask, a in 0:mask
            @context EagerContext() begin
                q = QInt{L}(y)
                superpose!(q)
                sub_qft!(q, a)
                interfere!(q)
                @test Int(q) == (y - a) & mask
            end
        end
    end

    # Wraparound: add_qft!(y, 2^L) should be identity (full revolution).
    @testset "wraparound a = 2^L" begin
        for L in 2:6
            @context EagerContext() begin
                q = QInt{L}(5 & ((1 << L) - 1))
                superpose!(q)
                add_qft!(q, 1 << L)
                interfere!(q)
                @test Int(q) == (5 & ((1 << L) - 1))
            end
        end
    end

    # Associativity: add(a) then add(b) == add(a+b).
    @testset "addition associativity" begin
        L = 5; mask = (1 << L) - 1
        for _ in 1:30
            y = rand(0:mask); a = rand(0:mask); b = rand(0:mask)
            @context EagerContext() begin
                q1 = QInt{L}(y)
                superpose!(q1); add_qft!(q1, a); add_qft!(q1, b); interfere!(q1)
                r1 = Int(q1)

                q2 = QInt{L}(y)
                superpose!(q2); add_qft!(q2, (a + b) & mask); interfere!(q2)
                r2 = Int(q2)

                @test r1 == r2 == (y + a + b) & mask
            end
        end
    end

    # Quantum-controlled add (Beauregard uses this inside mulmod).
    # Control = |+⟩ in superposition; output should be a uniform mixture of
    # (y, y+a mod 2^L) — measurement yields either with equal probability.
    @testset "controlled add_qft! under when(ctrl::|+⟩)" begin
        L = 3; mask = (1 << L) - 1
        for (y, a) in [(0, 3), (1, 5), (4, 7), (2, 2)]
            n_unchanged = 0; n_added = 0
            for _ in 1:400
                @context EagerContext() begin
                    q    = QInt{L}(y)
                    ctrl = QBool(1/2)            # |+⟩ control
                    superpose!(q)
                    when(ctrl) do
                        add_qft!(q, a)
                    end
                    interfere!(q)
                    result = Int(q)
                    _ = Bool(ctrl)                # collapse ctrl
                    if result == y
                        n_unchanged += 1
                    elseif result == (y + a) & mask
                        n_added += 1
                    end
                end
            end
            # ~50/50 split up to binomial noise; allow ±15% window on 400 trials.
            @test 140 <= n_unchanged <= 260
            @test 140 <= n_added     <= 260
            @test n_unchanged + n_added == 400   # nothing else appears
        end
    end
end

# ── Sturm.jl-dgy: modadd! (Beauregard 2003 Fig. 5) ─────────────────────────
#
# modadd!(y::QInt{L+1}, anc::QBool, a::Int, N::Int) computes
#   y := Φ((a + b) mod N) on the (L+1)-qubit Fourier register carrying b,
# leaving the ancilla anc in |0⟩.
#
# Preconditions: y is in Fourier basis; b < N; anc = |0⟩; a < N; N < 2^L.
# Postconditions: y in Fourier basis carrying (a+b) mod N; anc = |0⟩.

@testset "modadd!: Beauregard classical-constant modular addition" begin

    # Exhaustive L=3 sweep — N ∈ {2..7}, all (a, b) with 0 ≤ a,b < N.
    # 139 (N, a, b) triples total.
    @testset "exhaustive L=3 (N=$N)" for N in 2:7
        L = 3                    # y has L+1 = 4 qubits, plus 1 ancilla = 5
        for a in 0:(N-1), b in 0:(N-1)
            @context EagerContext() begin
                y   = QInt{L + 1}(b)
                anc = QBool(0)
                superpose!(y)
                modadd!(y, anc, a, N)
                interfere!(y)
                @test Int(y)    == (a + b) % N
                @test Bool(anc) == false    # ancilla cleanly restored
            end
        end
    end

    # Spot-check at L=4 with representative N values.
    @testset "spot-check L=4 (N=$N)" for N in (5, 11, 13, 15)
        L = 4
        # 30 random (a, b) per N
        for _ in 1:30
            a = rand(0:(N-1)); b = rand(0:(N-1))
            @context EagerContext() begin
                y   = QInt{L + 1}(b)
                anc = QBool(0)
                superpose!(y)
                modadd!(y, anc, a, N)
                interfere!(y)
                @test Int(y)    == (a + b) % N
                @test Bool(anc) == false
            end
        end
    end

    # Controlled modadd! under when(ctrl). When ctrl=|0⟩, operation must be
    # identity on y and anc (Beauregard's §2.2 correctness argument for
    # the doubly-controlled form — here with a single control for simplicity).
    @testset "controlled modadd! under when(ctrl)" begin
        L = 3; N = 5
        # Test cases must have (a+b) mod N ≠ b, else bucketing can't distinguish
        # the ctrl=|0⟩ (identity → b) and ctrl=|1⟩ ((a+b) mod N) branches.
        for (a, b) in [(2, 3), (4, 1), (1, 4), (3, 3)]
            # Control in |+⟩: expect 50/50 mixture (b unchanged, (a+b) mod N).
            n_unchanged = 0; n_added = 0; n_other = 0
            for _ in 1:400
                @context EagerContext() begin
                    y    = QInt{L + 1}(b)
                    anc  = QBool(0)
                    ctrl = QBool(1/2)
                    superpose!(y)
                    when(ctrl) do
                        modadd!(y, anc, a, N)
                    end
                    interfere!(y)
                    result = Int(y)
                    anc_out = Bool(anc)
                    _ = Bool(ctrl)
                    @test anc_out == false       # ancilla MUST be clean both branches
                    if result == b
                        n_unchanged += 1
                    elseif result == (a + b) % N
                        n_added += 1
                    else
                        n_other += 1
                    end
                end
            end
            @test n_other == 0
            @test 140 <= n_unchanged <= 260
            @test 140 <= n_added     <= 260
        end
    end
end

# ── Sturm.jl-uf4: mulmod_beauregard! (Beauregard 2003 Fig. 7) ──────────────
#
# mulmod_beauregard!(x::QInt{L}, a::Integer, N::Integer, ctrl::QBool)
# maps |ctrl⟩|x⟩ to |ctrl⟩|(a·x) mod N⟩ when ctrl=1, identity when ctrl=0.
# Requires gcd(a, N) = 1 (classical a must be invertible mod N).
#
# Internally: CMULT(a)MOD(N) + ctrl-SWAP + CMULT(a^{-1})MOD(N)^{-1},
# using an L+1-qubit accumulator and a 1-qubit ancilla, both restored.

@testset "mulmod_beauregard!: Beauregard controlled modular multiplication" begin

    # Exhaustive L=3, pick (N, a) pairs with gcd(a, N) = 1.
    # Note: b < N is enforced by construction; modadd uses b < N precondition.
    # For mulmod, we need x < N (the quantum input to multiply). For x ≥ N
    # the Beauregard circuit is undefined; we don't test that regime.
    @testset "exhaustive L=3 ctrl=|1⟩ (N=$N)" for N in (3, 5, 7)
        L = 3
        for a in 1:(N-1)
            gcd(a, N) == 1 || continue
            for x0 in 0:(N-1)
                @context EagerContext() begin
                    x    = QInt{L}(x0)
                    ctrl = QBool(1)            # always-on
                    mulmod_beauregard!(x, a, N, ctrl)
                    @test Int(x)    == (a * x0) % N
                    @test Bool(ctrl) == true   # ctrl passes through untouched
                end
            end
        end
    end

    @testset "exhaustive L=3 ctrl=|0⟩ identity (N=$N)" for N in (5, 7)
        L = 3
        for a in 1:(N-1)
            gcd(a, N) == 1 || continue
            for x0 in 0:(N-1)
                @context EagerContext() begin
                    x    = QInt{L}(x0)
                    ctrl = QBool(0)            # off
                    mulmod_beauregard!(x, a, N, ctrl)
                    @test Int(x) == x0          # unchanged
                    @test Bool(ctrl) == false
                end
            end
        end
    end

    # Coherent test: ctrl = |+⟩ gives 50/50 mixture of (x0, a·x0 mod N).
    @testset "coherent ctrl=|+⟩" begin
        L = 3
        cases = [(N=5, a=2, x0=3), (N=7, a=3, x0=4), (N=5, a=4, x0=2)]
        for c in cases
            n_id = 0; n_mul = 0; n_other = 0
            for _ in 1:400
                @context EagerContext() begin
                    x    = QInt{L}(c.x0)
                    ctrl = QBool(1/2)             # |+⟩
                    mulmod_beauregard!(x, c.a, c.N, ctrl)
                    r = Int(x)
                    _ = Bool(ctrl)
                    expected = (c.a * c.x0) % c.N
                    if r == c.x0
                        n_id += 1
                    elseif r == expected
                        n_mul += 1
                    else
                        n_other += 1
                    end
                end
            end
            @test n_other == 0
            @test 140 <= n_id  <= 260
            @test 140 <= n_mul <= 260
        end
    end
end


