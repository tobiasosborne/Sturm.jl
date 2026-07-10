# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# Sturm.jl M7 (bead Sturm.jl-7a0v): the Bennett bridge law tests. Verification is
# at the PERMUTATION / channel level (`denoted_permutation`, exhaustive basis
# replay, exact statevector marginals), NEVER an output marginal as the sole
# witness — a silent bit-reversal (wm28 class) survives every marginal test and is
# caught only on an ASYMMETRIC `f` at the permutation level (the increment tripwire
# below).
#
# CAPACITY NOTE: a Bennett oracle spends many ancilla wires (a 3-bit `f` compiles
# to 10–25 wires), so oracle state tests run on EAGER (2^n statevector), never a
# density matrix (2^{2n}, infeasible past ~12 wires). "Exact on DM" claims are met
# by reading the EAGER statevector's exact amplitudes/marginals (no sampling), the
# same exactness a DM diagonal would give.
#
# GOTCHA (probe §2e-ii): a data-dependent loop guard is only observable with
# `optimize=false`; the default optimizer folds a simple countdown to a closed form
# (empty loop_check_wires) and silently tests the WRONG path. The loop-reject test
# passes `optimize=false`.
#
# DJ §7.4 / BV §7.5 run VERBATIM: their source is extracted from Sturm-PRD-v2.md
# and eval'd (the PRD examples ARE the acceptance test — they must EXECUTE). This
# is Bennett-gated (the extension must be loaded).

using Test
using Sturm
using Bennett
using Sturm: Perm, MCX, CompiledOracle, OracleQuery, denoted_permutation,
             apply!, ctrl, X, H, QFT, eager, allocate!, q,
             statevector, when, superpose!, _core

# `extract_julia_blocks` (test_prd_examples.jl) and `_ptrace_keep` (choi.jl) are in
# scope — both included earlier in runtests.jl at this same (Main) scope.

# --- Test oracles (surface-visible ordinary Julia functions) --------------

dj_const(x)   = false                                   # constant  → DJ true
dj_bal(x)     = (x & 0x01) == 0x01                      # balanced (LSB) → DJ false
bv_s0(x)      = false                                   # s = 0 (0b000)
bv_s2(x)      = ((x >> 0x01) & 0x01) == 0x01            # s = 2 (0b010): bit 1
bv_s5(x)      = xor((x >> 0x00) & 0x01, (x >> 0x02) & 0x01) == 0x01   # s = 5: bit0 ⊕ bit2
inc3(x)       = x + 0x01                                # asymmetric — the carry tripwire

# A data-dependent loop (probe §2e): its convergence flag is a dirty ancilla.
function countdown3(x)
    acc = x
    c = zero(x)
    while acc != zero(x)
        acc -= one(x)
        c += one(x)
    end
    return c
end

# --- Helpers --------------------------------------------------------------

"The classical truth table of `f` at width `W` (output masked to `Wout` bits)."
function classical_table(f, W::Int, Wout::Int)
    mask = (1 << Wout) - 1
    return Dict(x => (Int(f(UInt64(x))) & mask) for x in 0:(2^W - 1))
end

"""
    realized_map(c::CompiledOracle) -> Dict{Int,Int}

The map `x ↦ f_realized(x)` the compiled `Perm` induces, read at the PERMUTATION
level via `denoted_permutation` on the role tables (input=x, output=0, anc=0), and
asserting input-preservation + ancilla-cleanliness for every input on the way.
The (★) ground truth — never a marginal. Gated at `PERM_EQ_MAXW` (n ≤ 20).
"""
function realized_map(c::CompiledOracle)
    n = c.n_wires
    dp = denoted_permutation(c.perm)                       # dp[b+1] = image of basis b
    inpos = c.in_positions[1]
    Wx = length(inpos)
    getbit(b, wire) = (b >> (n - wire)) & 1                # Perm wire = MSB (n - wire)
    out = Dict{Int,Int}()
    for x in 0:(2^Wx - 1)
        b = 0
        for j in 1:Wx
            ((x >> (Wx - j)) & 1) == 1 && (b |= (1 << (n - inpos[j])))   # MSB-first bit j
        end
        img = dp[b + 1]
        val = 0
        for β in 0:(c.W - 1)
            val |= Int(getbit(img, c.out_positions[β + 1])) << β         # output LSB-first
        end
        xin = 0
        for j in 1:Wx
            xin |= Int(getbit(img, inpos[j])) << (Wx - j)                # input preserved
        end
        @assert xin == x "oracle did not preserve input x=$x (got $xin)"
        @assert all(getbit(img, a) == 0 for a in c.anc_positions) "ancilla not clean for x=$x"
        out[x] = val
    end
    return out
end

"""
    x_marginal(ctx, xwires, W) -> Vector{Float64}

Exact `P(x = k)` for `k in 0:2^W−1`, read from the Eager statevector by summing
`|amp|²` grouped on `x`'s slots (MSB-first). Everything else (b, freed scratch) is
summed out — an EXACT marginal, no sampling.
"""
function x_marginal(ctx, xwires, W::Int)
    sv = statevector(ctx)
    slots = [q(ctx, w) for w in xwires]                    # MSB-first
    P = zeros(Float64, 1 << W)
    for i in 0:(length(sv) - 1)
        k = 0
        for (p, s) in enumerate(slots)
            k |= ((i >> s) & 1) << (W - p)                 # slots[1] = MSB
        end
        P[k + 1] += abs2(sv[i + 1])
    end
    return P
end

@testset "M7 — Bennett bridge: oracle, accumulate, DJ/BV, control (§3.4/§7.4/§7.5/D9/D14)" begin

    @testset "extension is loaded (weakdep glue active)" begin
        @test Base.get_extension(Sturm, :SturmBennettExt) !== nothing
    end

    # ---------------------------------------------------------------------
    # Gate map + permutation-level correctness (NEVER marginals — wm28)
    # ---------------------------------------------------------------------
    @testset "gate map NOT/CNOT/Toffoli → MCX; perm isa Perm" begin
        eager(8) do ctx
            x = QInt{3}(0)
            q = oracle(inc3, x)
            @test q.compiled.perm isa Perm
            @test all(g -> g isa MCX, q.compiled.perm.gates)
            @test q.compiled.n_wires == q.compiled.perm.n
        end
    end

    @testset "denoted_permutation ≡ classical f, exhaustive (n ≤ PERM_EQ_MAXW)" begin
        for (f, W) in ((dj_const, 3), (dj_bal, 3), (bv_s2, 3), (bv_s5, 3), (inc3, 3))
            eager(8) do ctx
                x = QInt{W}(0)
                q = oracle(f, x)
                c = q.compiled
                @test c.n_wires ≤ 20                       # all fit the exhaustive check
                @test realized_map(c) == classical_table(f, W, c.W)
            end
        end
    end

    @testset "MSB/LSB remap tripwire — increment (carry direction, asymmetric)" begin
        eager(8) do ctx
            x = QInt{3}(0)
            q = oracle(inc3, x)
            # (x + 1) mod 8 — a bit-reversal gives a DIFFERENT permutation, caught here.
            @test realized_map(q.compiled) == Dict(x => (x + 1) % 8 for x in 0:7)
        end
    end

    @testset "three-way agreement: Sturm ≡ Bennett.simulate ≡ classical f" begin
        for (f, W) in ((inc3, 3), (dj_bal, 3), (bv_s5, 3))
            circuit = Bennett.reversible_compile(f, UInt8; bit_width=W,
                                                 auto_self_reversing=false)
            Wout = circuit.output_elem_widths[1]
            for xv in 0:(2^W - 1)
                sturm_val = eager(20) do ctx
                    x = QInt{W}(xv)
                    b = QInt{Wout}(0)
                    b ⊻= oracle(f, x)
                    bval = Int(b)
                    @test Int(x) == xv                 # input preserved (x stays live)
                    bval
                end
                @test sturm_val == Int(Bennett.simulate(circuit, xv))
                @test sturm_val == (Int(f(UInt64(xv))) & ((1 << Wout) - 1))
            end
        end
    end

    # ---------------------------------------------------------------------
    # The accumulate law  Int(b) == v ⊻ f(x)   (D9)
    # ---------------------------------------------------------------------
    @testset "accumulate law: Int(b) == v ⊻ f(x) for nonzero b" begin
        for xv in 0:7, v in (0, 3, 5, 7)
            got = eager(20) do ctx
                x = QInt{3}(xv)
                b = QInt{3}(v)
                b ⊻= oracle(inc3, x)
                Int(b)
            end
            @test got == xor(v, (xv + 1) % 8)
        end
    end

    # ---------------------------------------------------------------------
    # DJ §7.4 and BV §7.5 — VERBATIM from the PRD, EXECUTED
    # ---------------------------------------------------------------------
    @testset "PRD §7.4 Deutsch–Jozsa / §7.5 Bernstein–Vazirani execute verbatim" begin
        prd_blocks = extract_julia_blocks(joinpath(@__DIR__, "..", "Sturm-PRD-v2.md"))
        dj_src = only(filter(b -> occursin("function deutsch_jozsa", b.code), prd_blocks))
        bv_src = only(filter(b -> occursin("function bernstein_vazirani", b.code), prd_blocks))

        # Eval the PRD's own source into a fresh module (guarantees verbatim).
        mod = Module(:PRDExecM7)
        Core.eval(mod, :(using Sturm))
        Core.eval(mod, :(using Bennett))
        Base.include_string(mod, dj_src.code)
        Base.include_string(mod, bv_src.code)

        @testset "DJ — constant ⇒ true, balanced ⇒ false (one query)" begin
            for N in (2, 3)
                @test eager(18) do ctx
                    mod.deutsch_jozsa(dj_const, Val(N))
                end == true
                @test eager(18) do ctx
                    mod.deutsch_jozsa(dj_bal, Val(N))
                end == false
            end
        end

        @testset "BV — one query recovers the (palindromic) secret s exactly" begin
            for (fs, s) in ((bv_s0, 0), (bv_s2, 2), (bv_s5, 5))
                @test eager(20) do ctx
                    mod.bernstein_vazirani(fs, Val(3))
                end == s
            end
        end
    end

    # ---------------------------------------------------------------------
    # D2 negative control — the register dual does NOT recover s (§7.4 vs §7.5)
    # ---------------------------------------------------------------------
    @testset "D2 negative control: register-dual readout is spread/tied (N=3, s=5)" begin
        # The §7.4 pattern Int(dual(x)) on the BV(s=5) kicked state: EXACT via the
        # register dual F applied then the statevector marginal read (no sampling).
        dist = eager(20) do ctx
            x = QInt{3}(0)
            superpose!(x)
            b = minus()
            b ⊻= oracle(bv_s5, x)
            apply!(ctx, QFT(3, false), x.wires)              # register dual F (test tooling)
            x_marginal(ctx, x.wires, 3)
        end
        # {1: .073, 3: .427, 5: .427, 7: .073}; even outcomes ≈ 0.
        @test isapprox(dist[1 + 1], 0.073; atol=0.01)
        @test isapprox(dist[3 + 1], 0.427; atol=0.01)
        @test isapprox(dist[5 + 1], 0.427; atol=0.01)
        @test isapprox(dist[7 + 1], 0.073; atol=0.01)
        @test all(isapprox(dist[2k + 1], 0.0; atol=1e-9) for k in 0:3)  # even outcomes vanish
        @test isapprox(sum(dist), 1.0; atol=1e-9)
    end

    # ---------------------------------------------------------------------
    # Oracle under `when` — the M5 IOU (ctrl(Perm) = Perm)
    # ---------------------------------------------------------------------
    @testset "oracle under when — controlled permutation, exhaustive basis (Eager)" begin
        # Definite (c, x) inputs, b = |0⟩ target: when(c){ b ⊻= oracle } realizes the
        # controlled classical map. Exhaustive over computational basis ⇒ the FULL
        # controlled permutation (Perm is phase-free, so basis-exhaustive = channel).
        for cv in (false, true), xv in 0:7
            got = eager(20) do ctx
                c = QBool(cv)
                x = QInt{3}(xv)
                b = QInt{3}(0)
                when(c) do
                    b ⊻= oracle(inc3, x)
                end
                @test Int(x) == xv            # input preserved
                @test Bool(c) == cv           # control preserved (participates as input+output)
                Int(b)
            end
            @test got == (cv ? (xv + 1) % 8 : 0)   # fires only on c = 1
        end
    end

    @testset "oracle under when — coherence witness (no spurious controlled phase)" begin
        # c = |+⟩, x = |1⟩ definite (dj_bal = lsb ⇒ f(1) = 1), b = |0⟩:
        # after when, EXACTLY two basis states are nonzero — (c=0,b=0) and (c=1,b=1)
        # — and they must carry EQUAL amplitudes (1/√2, in phase). A spurious
        # controlled Z-phase would make them unequal (invisible to any Z-marginal).
        amps = eager(18) do ctx
            c = QBool(0.5)                     # |+⟩
            x = QInt{3}(1)
            b = QBool(false)
            when(c) do
                b ⊻= oracle(dj_bal, x)         # dj_bal = lsb; f(1) = 1
            end
            sv = statevector(ctx)
            [sv[i + 1] for i in 0:(length(sv) - 1) if abs(sv[i + 1]) > 1e-9]
        end
        @test length(amps) == 2
        @test isapprox(abs(amps[1]), 1 / sqrt(2); atol=1e-6)
        @test isapprox(abs(amps[2]), 1 / sqrt(2); atol=1e-6)
        @test isapprox(amps[1], amps[2]; atol=1e-6)   # equal ⇒ in phase (no spurious phase)
    end

    # ---------------------------------------------------------------------
    # MBU-exclusion (§3.4) — structural: the boundary admits only phase-free perms
    # ---------------------------------------------------------------------
    @testset "MBU-exclusion is structural (§3.4 named test)" begin
        eager(8) do ctx
            x = QInt{3}(0)
            for f in (dj_const, dj_bal, inc3, bv_s5)
                q = oracle(f, x)
                # The unitarity witness IS the Perm: no measurement can cross the boundary.
                @test q.compiled.perm isa Perm
                @test all(g -> g isa MCX, q.compiled.perm.gates)
            end
        end
        # A VM-target request is rejected loud at the boundary (D14) — MBU/VM lowerings
        # are not fixed permutations and never cross.
        eager(8) do ctx
            x = QInt{3}(0)
            @test_throws Exception oracle(inc3, x; target = :reversible_vm)
        end
    end

    # ---------------------------------------------------------------------
    # Zero-tail witness + ancilla cleanliness (wm28 guards)
    # ---------------------------------------------------------------------
    @testset "zero-tail witness fires loud for an under-sized b" begin
        # inc3 produces values up to 7 (3 bits); a QBool (Wb = 1) target for x = 3
        # (f = 4 = 0b100) leaves a nonzero tail wire ⇒ LOUD (not a silent decohere).
        @test_throws Exception eager(18) do ctx
            x = QInt{3}(3)
            b = QBool(false)
            b ⊻= oracle(inc3, x)        # tail bits 1,2 nonzero ⇒ clean-witness fails
        end
        # Sanity: a value that DOES fit a 1-bit target passes (no false positive).
        @test eager(18) do ctx
            x = QInt{3}(0)              # inc3(0) = 1 fits bit 0
            b = QBool(false)
            b ⊻= oracle(inc3, x)
            Bool(b)
        end == true
    end

    @testset "ancilla full-marginal cleanliness (no leaked scratch)" begin
        for xv in 0:7
            ok = eager(20) do ctx
                x = QInt{3}(xv)
                b = QInt{3}(0)
                b ⊻= oracle(inc3, x)        # completes iff every scratch wire is clean |0⟩
                (Int(b), Int(x))
            end
            @test ok == (xor(0, (xv + 1) % 8), xv)   # b = f(x), x preserved
        end
    end

    # ---------------------------------------------------------------------
    # Loop-reject (probe gotcha: optimize=false) + error-path sweep
    # ---------------------------------------------------------------------
    @testset "loop-reject: data-dependent loop rejected LOUD at compile (optimize=false)" begin
        # optimize=false forces genuine per-iteration unrolling; the default optimizer
        # folds the countdown to a closed form and would test the WRONG path.
        eager(8) do ctx
            x = QInt{3}(0)
            @test_throws Exception oracle(countdown3, x; optimize=false, max_loop_iterations=6)
        end
        # Named test: also rejected when the oracle() compile happens inside a `when`.
        eager(8) do ctx
            c = QBool(true)
            x = QInt{3}(0)
            @test_throws Exception when(c) do
                oracle(countdown3, x; optimize=false, max_loop_iterations=6)
            end
        end
    end

    @testset "error-path sweep (all fail-loud)" begin
        eager(12) do ctx
            x = QInt{3}(0)
            q = oracle(inc3, x)
            # target aliases input register (a slice of x as the target)
            @test_throws Exception (x[1] ⊻= q)
            # width mismatch: target wider than the oracle output block
            y = QInt{5}(0)
            @test_throws Exception (y ⊻= q)
        end
        # cross-context handle: a query bound in one context applied under another.
        @test_throws Exception begin
            stray = eager(8) do ctx
                QInt{3}(0)          # escapes its context (dead handle)
            end
            eager(8) do ctx
                oracle(inc3, stray)
            end
        end
    end

    # ---------------------------------------------------------------------
    # Core (Bennett-independent) — the accumulate law from a HAND-BUILT Perm
    # ---------------------------------------------------------------------
    @testset "core accumulate law from a hand-built OracleQuery (no compile path)" begin
        # f = identity, W = 1: n_wires = 2, gate CNOT(input→output). Tests the core
        # `Base.xor`/`_apply_oracle!` physics WITHOUT the extension's compile.
        perm = Perm(2, [MCX([1], 2)])                 # CNOT: control = wire 1, target = 2
        comp = CompiledOracle(perm, 2, [[1]], [2], 1, Int[])
        for xv in (false, true), bv in (false, true)
            got = eager(8) do ctx
                x = QInt{1}(xv ? 1 : 0)
                q = OracleQuery(comp, (x,))
                b = QBool(bv)
                b ⊻= q                                 # b ← b ⊻ id(x) = b ⊻ x
                (Bool(b), Int(x))
            end
            @test got == (xor(bv, xv), xv ? 1 : 0)     # accumulate + input preserved
        end
    end
end
