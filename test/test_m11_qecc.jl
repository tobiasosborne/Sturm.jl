# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# Sturm.jl M11 (bead Sturm.jl-qmpo), design docs/design/m11-82su-synthesis.md
# §6 "QECC" (slice-5 half): code-value validation (S17), the self-validating
# table (S20), the honest distance (the session-105 Eastin–Knill finding —
# this code has d = 1 and the suite REFUSES to imply 3), codespace invariance,
# the encode∘decode identity at the Choi level (coherently probed — the wm28
# gate), the T4 ownership transfer, and the six T3 refusals. The superchannel
# tests (effective_logical_noise, break-even, phase-amplification) land with
# slice 6 in this same file. Requires test/choi.jl first.

using Test
using LinearAlgebra
using Sturm
using Sturm: StabilizerCode, CodeEncoding, CodeBlock, bit_flip_code, decoder,
    syndrome, nphysical, nlogical, stabilizers, distance, verify_distance,
    PauliWord, commutes, certify, trace, UnitaryBlock, denoted_matrix,
    density, density_matrix, eager, apply!, X, Z, H, dual, when, not!, oracle,
    encoding

const _P3 = PauliWord{3}

# Apply a PauliWord to context wires (test-side: X/Z/Y per letter).
function _apply_word!(ctx, w::PauliWord{3}, wires)
    for j in 1:3
        c = Sturm.letter_at(w, j)
        c == 'I' && continue
        v = c == 'X' ? Sturm.X : (c == 'Z' ? Sturm.Z : Sturm.Y)
        apply!(ctx, v, (wires[j],))
    end
    nothing
end

@testset "M11.CODE.VALIDATION" begin
    stabs = (_P3("ZZI"), _P3("IZZ"))
    lx = (_P3("XXX"),); lz = (_P3("ZII"),)
    ok = StabilizerCode(:ok, stabs, (1, 1), lx, lz, 1)
    @test nphysical(ok) == 3 && nlogical(ok) == 1
    # (1) wrong generator count for [[3,1]]:
    @test_throws ArgumentError StabilizerCode(:bad, (_P3("ZZI"),), (1,), lx, lz, 1)
    # (1b) identity generator:
    @test_throws ArgumentError StabilizerCode(:bad, (_P3("III"), _P3("IZZ")), (1, 1), lx, lz, 1)
    # (2) anticommuting generators:
    @test_throws ArgumentError StabilizerCode(:bad, (_P3("XII"), _P3("ZII")), (1, 1), lx, lz, 1)
    # (3) GF(2)-dependent generators (g₂ = g₁):
    @test_throws ArgumentError StabilizerCode(:bad, (_P3("ZZI"), _P3("ZZI")), (1, 1), lx, lz, 1)
    # (4) logical outside the normaliser:
    @test_throws ArgumentError StabilizerCode(:bad, stabs, (1, 1), (_P3("XII"),), lz, 1)
    # (5) logical pair that COMMUTES (XXX/ZZZ would be VALID — three X·Z
    # anticommutations compose to an odd overlap; the clean violation needs a
    # pair sharing no anticommuting wire — built on an S = 0 code):
    P2 = PauliWord{2}
    @test_throws ArgumentError StabilizerCode(:bad, (), (),
        (P2("XI"), P2("IX")), (P2("XI"), P2("IZ")), 1)
    # and the same S = 0 shape with honest pairs constructs:
    @test StabilizerCode(:ok0, (), (), (P2("XI"), P2("IX")),
                         (P2("ZI"), P2("IZ")), 1) isa StabilizerCode
    # (6) "logical" inside the stabilizer group:
    @test_throws ArgumentError StabilizerCode(:bad, stabs, (1, 1), lx, (_P3("ZZI"),), 1)
    # bad sign:
    @test_throws ArgumentError StabilizerCode(:bad, stabs, (1, 2), lx, lz, 1)
    # (S20) mis-entered table rejected, naming the entry:
    enc = bit_flip_code()
    badtable = [_P3("III"), _P3("IXI"), _P3("IIX"), _P3("XII")]   # 1↔3 swapped
    err = try
        CodeEncoding(enc.code, enc.encoder, badtable); nothing
    catch e; e end
    @test err isa ArgumentError
    @test occursin("mis-entered", sprint(showerror, err))
end

@testset "M11.CODE.DISTANCE-IS-ONE" begin
    enc = bit_flip_code()
    @test distance(enc.code) == 1
    @test verify_distance(enc.code) == 1        # witness Z₁ — computed, not declared
    # Syndrome pin (generator 1 = LSB, the codes.jl header): the design's arm map.
    @test syndrome(enc.code, _P3("XII")) == 1
    @test syndrome(enc.code, _P3("IXI")) == 3
    @test syndrome(enc.code, _P3("IIX")) == 2
    @test syndrome(enc.code, _P3("III")) == 0
    @test syndrome(enc.code, _P3("ZII")) == 0   # the d=1 witness is INVISIBLE
end

@testset "M11.QECC.CODESPACE" begin
    # The encoder maps into the joint +1 eigenspace: applying each stabilizer
    # to an encoded state leaves the DM invariant (α|000⟩+β|111⟩ probe).
    enc = bit_flip_code()
    density(3) do ctx
        q = QBool(0.3)                          # a non-trivial logical state
        blk = encode_state(enc, q)
        ρ0 = density_matrix(ctx)
        for g in stabilizers(enc.code)
            _apply_word!(ctx, g, blk.wires)
            @test density_matrix(ctx) ≈ ρ0 atol = 1e-12
        end
        nothing
    end
end

@testset "M11.QECC.ENCODE-DECODE-ID" begin
    # Choi(decode ∘ encode) ≈ Choi(id), COHERENTLY probed (the Bell half —
    # a Z-basis marginal would pass a dephasing bug; the Choi does not).
    enc = bit_flip_code()
    J = choi(q -> decode_state(encode_state(enc, q)), 1; cap = 6)
    bell = ComplexF64[1 0 0 1; 0 0 0 0; 0 0 0 0; 1 0 0 1] ./ 2
    @test J ≈ bell atol = 1e-10
end

@testset "M11.QECC.OWNERSHIP-TRANSFER" begin
    # T4: encode_state re-homes the logical wire — the OLD handle dies loudly;
    # decode_state returns a live handle and consumes the block.
    eager(3) do ctx                                  # Eager: Bool is a scalar
        q = QBool(false)
        blk = encode_state(bit_flip_code(), q)
        @test_throws Exception Bool(q)               # old handle is dead
        out = decode_state(blk)
        @test Bool(out) == false                     # information round-trips
        nothing
    end
    eager(3) do ctx
        q = QBool(true)
        out = decode_state(encode_state(bit_flip_code(), q))
        @test Bool(out) == true
        nothing
    end
    # Wrong arity is loud.
    density(3) do _
        q1 = QBool(false); q2 = QBool(false)
        @test_throws ArgumentError encode_state(bit_flip_code(), q1, q2)
        nothing
    end
end

@testset "M11.QECC.SURFACE-BOUNDARY" begin
    # All six T3 refusals throw with the ruling's reason of record.
    density(4) do _
        q = QBool(false)
        blk = encode_state(bit_flip_code(), q)
        for (f, name) in ((b -> not!(b), "not!"),
                          (b -> Bool(b), "Bool"),
                          (b -> b ⊻ b, "xor"),
                          (b -> dual(b), "dual"),
                          (b -> when(() -> nothing, b), "when"),
                          (b -> oracle(identity, b), "oracle"))
            err = try
                f(blk); nothing
            catch e; e end
            @test err isa ArgumentError
            @test occursin("T3", sprint(showerror, err))
        end
        nothing
    end
end
