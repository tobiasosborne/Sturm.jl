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

# ─── Slice 6: the superchannel (S21-S27, T1) ───────────────────────────────────

using Sturm: PhysicalChannel, LogicalChannel, Protect, TableDecoder, NoRecovery,
    effective_logical_noise, physical_iid, TRANSFORM_REGISTRY,
    fault_tolerant_lift, channel_dag, channel, bit_flip, phase_flip,
    depolarizing, choi_matrix, same_channel, ctrl, _replay_dm!, _adopt_qbool,
    apply_noise!, mulword, letter_at, I2, ⊗

_replay_lch(Φ) = function (qin)
    outs = _replay_dm!(qin.ctx, Φ.dag, [qin.wire])
    return _adopt_qbool(qin.ctx, outs[1])
end

function _choiK_qecc(ops)
    d = size(ops[1], 1)
    J = zeros(ComplexF64, d * d, d * d)
    for K in ops
        v = zeros(ComplexF64, d * d)
        for a in 1:d, b in 1:d
            v[(a - 1) * d + b] = K[a, b]
        end
        J .+= v * v'
    end
    return J ./ d
end
const _mI = ComplexF64[1 0; 0 1]; const _mX = ComplexF64[0 1; 1 0]
const _mY = ComplexF64[0 -im; im 0]; const _mZ = ComplexF64[1 0; 0 -1]

@testset "M11.QECC.EFFECTIVE-NOISE-EXACT" begin
    # Θ(bit_flip(p)^⊗3) ≈ bit_flip(3p² − 2p³) at the Choi level — the
    # repetition_code_effective_noise.md derivation, executed.
    enc = bit_flip_code()
    θ = Protect(enc)
    for p in (0.01, 0.05, 0.1, 0.3, 0.5, 0.7)
        Φ = θ(physical_iid(enc, bit_flip(p)))
        @test Φ isa LogicalChannel
        J = choi(_replay_lch(Φ), 1; cap = 6)
        pL = 3p^2 - 2p^3
        @test J ≈ choi_matrix(bit_flip(pL)) atol = 1e-10
    end
end

@testset "M11.QECC.BREAK-EVEN" begin
    # TWO-SIDED (risk R-d): correction HELPS below p = ½ and HURTS above —
    # a sign-flipped recovery table would pass a one-sided "protection helps".
    pL = p -> 3p^2 - 2p^3
    @test pL(0.1) ≈ 0.028 atol = 1e-12
    @test pL(0.1) < 0.1
    @test pL(0.6) ≈ 0.648 atol = 1e-12
    @test pL(0.6) > 0.6
    @test pL(0.5) ≈ 0.5 atol = 1e-12                 # exact break-even (2p−1)(p−1)=0
    enc = bit_flip_code()
    for p in (0.1, 0.6)
        Φ = Protect(enc)(physical_iid(enc, bit_flip(p)))
        J = choi(_replay_lch(Φ), 1; cap = 6)
        @test J ≈ choi_matrix(bit_flip(pL(p))) atol = 1e-10
    end
end

@testset "M11.QECC.PHASE-NOISE-IS-WORSE" begin
    # The wm28-shaped anti-test: the bit-flip code AMPLIFIES phase noise —
    # every Zᵢ is a logical Z̄ with trivial syndrome, so no correction ever
    # fires and the residual is Z̄ iff an odd number of Zs landed:
    # Θ(phase_flip(p)^⊗3) = phase_flip((1 − (1−2p)³)/2) ≈ 3p. A
    # population-only probe is BLIND to this; the Choi is not.
    enc = bit_flip_code()
    for p in (0.05, 0.1, 0.3)
        Φ = Protect(enc)(physical_iid(enc, phase_flip(p)))
        J = choi(_replay_lch(Φ), 1; cap = 6)
        pZ = (1 - (1 - 2p)^3) / 2
        @test J ≈ choi_matrix(phase_flip(pZ)) atol = 1e-10
        @test pZ > p                                  # amplification, pinned
    end
end

@testset "M11.QECC.INDEPENDENT-REFERENCE" begin
    # For depolarizing(p): the expected logical channel from a TEST-SIDE
    # brute-force enumerator over all 4³ Pauli patterns (pattern prob →
    # syndrome → validated-table correction → residual's logical class by
    # commutation with X̄/Z̄ — an independent implementation, not a pinned
    # number), compared against the executed Choi.
    enc = bit_flip_code()
    p = 0.3
    probs = Dict('I' => 1 - 3p / 4, 'X' => p / 4, 'Y' => p / 4, 'Z' => p / 4)
    logi = zeros(Float64, 4)                          # I, X, Y, Z logical weights
    for l1 in "IXYZ", l2 in "IXYZ", l3 in "IXYZ"
        w = PauliWord{3}(String([l1, l2, l3]))
        pr = probs[l1] * probs[l2] * probs[l3]
        σ = syndrome(enc.code, w)
        r = mulword(w, enc.corrections[σ + 1])[2]     # residual (phase-free class)
        a = !commutes(r, enc.code.logical_z[1])       # X̄ component
        b = !commutes(r, enc.code.logical_x[1])       # Z̄ component
        cls = a ? (b ? 4 : 2) : (b ? 3 : 1)           # I/X/Z/Y → 1/2/3/4 (a,b) map
        logi[cls] += pr
    end
    expected = logi[1] .* _choiK_qecc([_mI]) .+ logi[2] .* _choiK_qecc([_mX]) .+
               logi[3] .* _choiK_qecc([_mZ]) .+ logi[4] .* _choiK_qecc([_mY])
    Φ = Protect(enc)(physical_iid(enc, depolarizing(p)))
    J = choi(_replay_lch(Φ), 1; cap = 6)
    @test J ≈ expected atol = 1e-10
end

@testset "M11.QECC.SUPERCHANNEL-TYPING" begin
    enc = bit_flip_code()
    # A bare family is refused, pointing at physical_iid (S24).
    err = try
        effective_logical_noise(bit_flip(0.1), Protect(enc)); nothing
    catch e; e end
    @test err isa ArgumentError
    @test occursin("physical_iid", sprint(showerror, err))
    # Arity/instrument validation (S22).
    @test_throws ArgumentError PhysicalChannel(enc.code, channel_dag(bit_flip(0.1), 1))
    bb = Sturm.DAGBuilder()
    ws = [Sturm.input!(bb) for _ in 1:3]
    Sturm.measure!(bb, ws[3])
    @test_throws ArgumentError PhysicalChannel(enc.code, Sturm.freeze(bb))
    # The result is typed; nothing here is controllable.
    Φ = Protect(enc)(physical_iid(enc, bit_flip(0.1)))
    @test Φ isa LogicalChannel{typeof(enc.code)}
    @test length(Φ.dag.qin) == 1 && isempty(Φ.dag.cout)
    @test_throws MethodError ctrl(Φ)
    @test_throws MethodError ctrl(Protect(enc))
    # physical_iid refuses a multi-wire factor.
    @test_throws ArgumentError physical_iid(enc, bit_flip(0.1) ⊗ bit_flip(0.1))
end

@testset "M11.QECC.FT-LIFT-HONEST" begin
    enc = bit_flip_code()
    Φ = Protect(enc)(physical_iid(enc, bit_flip(0.1)))
    err = try
        fault_tolerant_lift(Φ, nothing); nothing
    catch e; e end
    @test err isa ArgumentError
    msg = sprint(showerror, err)
    for needle in ("fault model", "gadget", "magic-state", "syndrome", "threshold",
                   "Eastin–Knill")
        @test occursin(needle, msg)
    end
end

@testset "M11.TRANSFORM.LAW-AND-IDENTITY" begin
    # Registry-driven (S23): EVERY registered transform runs both laws here —
    # a shipped-but-unregistered or registered-but-untested transform fails.
    @test !isempty(TRANSFORM_REGISTRY)
    for (name, T) in TRANSFORM_REGISTRY
        if name === :protect
            enc = bit_flip_code()
            # (b) IDENTITY law: Θ(id_P) ≈ id_L.
            Φid = Protect(enc)(physical_iid(enc, channel(I2)))
            Jid = choi(_replay_lch(Φid), 1; cap = 6)
            bell = ComplexF64[1 0 0 1; 0 0 0 0; 0 0 0 0; 1 0 0 1] ./ 2
            @test Jid ≈ bell atol = 1e-10
            # (a) SPEC law: the composite assembled INDEPENDENTLY — separate
            # replays of E, the native noise value, R, D in one DM run (no
            # slice-4 ∘ anywhere), vs the spliced superchannel.
            fam = bit_flip(0.2)
            Jspec = choi(1; cap = 6) do q
                ctx = q.ctx
                eouts = _replay_dm!(ctx, Sturm._encode_dag(enc), [q.wire])
                for w in eouts
                    Sturm.apply!(ctx, fam, (w,))
                end
                routs = _replay_dm!(ctx, Sturm._recovery_dag(enc), eouts)
                douts = _replay_dm!(ctx, Sturm._decode_dag(enc), routs)
                _adopt_qbool(ctx, douts[1])
            end
            Jexe = choi(_replay_lch(Protect(enc)(physical_iid(enc, fam))), 1; cap = 6)
            @test Jexe ≈ Jspec atol = 1e-10
        else
            @test false || error("TRANSFORM_REGISTRY entry :$name has no law arm " *
                                 "in M11.TRANSFORM.LAW-AND-IDENTITY — add one (S23)")
        end
    end
end
