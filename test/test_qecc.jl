using Test
using Sturm

# Canonical [[7,1,3]] codewords per Steane 1996 eq. 6 (φ_j = 0).
# Reading q1..q7 as MSB..LSB of a 7-bit integer.
const _STEANE_C = Set{UInt8}([
    0b0000000, 0b1010101, 0b0110011, 0b1100110,
    0b0001111, 0b1011010, 0b0111100, 0b1101001,
])
const _STEANE_NOT_C = Set{UInt8}(x ⊻ 0b1111111 for x in _STEANE_C)

# Encode the 7 measured bits (q1..q7) as a 7-bit integer, q1 = MSB.
_pack_bits(bits::NTuple{7, Bool}) = UInt8(reduce(
    (acc, b) -> (acc << 1) | UInt8(b), bits; init=UInt8(0)))

@testset "QECC — Steane [[7,1,3]]" begin

    @testset "Encode-decode roundtrip: |0⟩" begin
        @context EagerContext() begin
            for _ in 1:50
                q = QBool(0)
                physical = encode!(Steane(), q)
                recovered = decode!(Steane(), physical)
                @test Bool(recovered) == false
            end
        end
    end

    @testset "Encode-decode roundtrip: |1⟩" begin
        @context EagerContext() begin
            for _ in 1:50
                q = QBool(1)
                physical = encode!(Steane(), q)
                recovered = decode!(Steane(), physical)
                @test Bool(recovered) == true
            end
        end
    end

    @testset "Encode-decode roundtrip: |+⟩ (superposition)" begin
        @context EagerContext() begin
            N = 2000
            count_true = 0
            for _ in 1:N
                q = QBool(0)
                H!(q)
                physical = encode!(Steane(), q)
                recovered = decode!(Steane(), physical)
                count_true += Bool(recovered)
            end
            # |+⟩ encoded then decoded should give ~50/50
            @test abs(count_true / N - 0.5) < 0.04
        end
    end

    # ── Canonical codeword verification (Steane 1996 eq. 6) ─────────────────

    @testset "encode(|0⟩_L) produces canonical |C⟩ codewords" begin
        # For each shot, measure all 7 physical qubits and verify the
        # observed bit string is in the 8-element codeword set |C⟩.
        @context EagerContext() begin
            N = 500
            observed = Set{UInt8}()
            for _ in 1:N
                q = QBool(0)
                physical = encode!(Steane(), q)
                bits = ntuple(i -> Bool(physical[i]), 7)
                word = _pack_bits(bits)
                @test word in _STEANE_C
                push!(observed, word)
            end
            # All 8 codewords should appear with high probability (N=500, p=1/8).
            @test length(observed) == 8
        end
    end

    @testset "encode(|1⟩_L) produces canonical |¬C⟩ codewords" begin
        @context EagerContext() begin
            N = 500
            observed = Set{UInt8}()
            for _ in 1:N
                q = QBool(1)
                physical = encode!(Steane(), q)
                bits = ntuple(i -> Bool(physical[i]), 7)
                word = _pack_bits(bits)
                @test word in _STEANE_NOT_C
                push!(observed, word)
            end
            @test length(observed) == 8
        end
    end

    @testset "X_L = X₁X₂X₃X₄X₅X₆X₇ flips the logical bit" begin
        # Transversal X is a valid logical X for Steane. Encode |0⟩_L,
        # apply X to each of the 7 physical qubits, decode: expect |1⟩_L.
        @context EagerContext() begin
            for _ in 1:50
                q = QBool(0)
                physical = encode!(Steane(), q)
                for p in physical
                    X!(p)
                end
                recovered = decode!(Steane(), physical)
                @test Bool(recovered) == true
            end
        end
    end

    @testset "Logical qubit is consumed after encoding" begin
        @context EagerContext() begin
            q = QBool(0)
            physical = encode!(Steane(), q)
            @test q.consumed == true
            for p in physical
                discard!(p)
            end
        end
    end

    # ── Higher-order QECC: encode(ch::Channel, code) (PRD P6, §8.5) ─────────

    @testset "encode(Channel, Steane) produces Channel{In,Out}" begin
        # Logical X circuit: trace(1) do q; X!(q); q end → Channel{1,1}
        ch = trace(1) do q
            X!(q)
            q
        end
        @test n_inputs(ch) == 1
        @test n_outputs(ch) == 1

        ch_enc = encode(ch, Steane())
        @test ch_enc isa Sturm.Channel{1, 1}
        @test n_inputs(ch_enc) == 1
        @test n_outputs(ch_enc) == 1
    end

    @testset "encoded channel DAG has transversal structure" begin
        # Logical X: X! = Rz(π)·Ry(π) → RzNode then RyNode (bead 3yz).
        ch = trace(1) do q
            X!(q)
            q
        end
        @test length(ch.dag) == 2
        @test ch.dag[1] isa Sturm.RzNode
        @test ch.dag[1].angle ≈ π
        @test ch.dag[2] isa Sturm.RyNode
        @test ch.dag[2].angle ≈ π

        # correct=false: bare transversal, no syndrome ancillas. The structure
        # asserted here is the transversalized-encoder-decoder shape. With
        # correct=true (the default, bead 870 P3), syndrome_correct! is
        # interleaved and the DAG is much bigger; that path is asserted in
        # test_steane_channel_correct.jl.
        ch_enc = encode(ch, Steane(); correct=false)

        # Original: 1 RzNode + 1 RyNode. Encoded: encoder + 7 transversal X! + decoder.
        # Steane encoder: 2 CNOTs + 3 H! (each 1 Rz + 1 Ry) + 9 CNOTs = 17 nodes.
        # Transversal X: 7 * (Rz + Ry) = 14 nodes.
        # Steane decoder: mirror of encoder = 17 nodes + 6 DiscardNodes (ancilla cleanup).
        # Total expected: 17 + 14 + 17 + 6 = 54 nodes.
        @test length(ch_enc.dag) == 54

        # No non-unitary nodes should leak from the original (the original was
        # pure unitary). DiscardNodes appear only from decode!'s ancilla cleanup.
        n_discard = count(n -> n isa Sturm.DiscardNode, ch_enc.dag)
        @test n_discard == 6  # 6 ancilla qubits discarded

        # No ObserveNode or CasesNode should appear in the encoded channel.
        @test !any(n -> n isa Sturm.ObserveNode, ch_enc.dag)
        # CasesNode is not in HotNode so won't appear in ch.dag anyway.
    end

    @testset "encode transversalizes Z on 7 physical qubits" begin
        # Logical Z circuit: Z!(q) = q.φ += π → one RzNode with angle π.
        ch = trace(1) do q
            Z!(q)
            q
        end
        @test ch.dag[1] isa Sturm.RzNode
        @test ch.dag[1].angle ≈ π

        # Bare transversal (see comment above in the X testset).
        ch_enc = encode(ch, Steane(); correct=false)

        # Transversal Z: 7 RzNodes with angle π (in addition to the 6 Rz's
        # from encoder's H's and 6 from decoder's H's). Count all RzNodes
        # with angle π and verify we see the expected transversal chunk.
        rz_pi_count = count(ch_enc.dag) do n
            n isa Sturm.RzNode && n.angle ≈ π
        end
        # Encoder has 3 H = 3 RzNode(π). Transversal Z adds 7 RzNode(π).
        # Decoder has 3 H = 3 RzNode(π). Total: 3 + 7 + 3 = 13.
        @test rz_pi_count == 13
    end

    @testset "encode transversalizes CNOT pairwise between blocks" begin
        # Two-qubit CNOT circuit: one CXNode.
        ch = trace(2) do a, b
            b ⊻= a   # CNOT: a controls, b target
            (a, b)
        end
        cx_nodes_orig = count(n -> n isa Sturm.CXNode, ch.dag)
        @test cx_nodes_orig == 1

        ch_enc = encode(ch, Steane(); correct=false)
        @test ch_enc isa Sturm.Channel{2, 2}

        # Encoder: 2 * 11 CXNodes = 22. Transversal CNOT: 7 pairwise CXNodes.
        # Decoder: 2 * 11 CXNodes = 22. Total: 22 + 7 + 22 = 51.
        cx_nodes_enc = count(n -> n isa Sturm.CXNode, ch_enc.dag)
        @test cx_nodes_enc == 51
    end

    @testset "encode rejects non-Clifford rotation" begin
        # T gate: q.φ += π/4 → RzNode with non-Clifford angle.
        ch = trace(1) do q
            q.φ += π/4
            q
        end
        @test_throws ErrorException encode(ch, Steane())
    end

    @testset "encode rejects nested when-controls" begin
        ch = trace(2) do a, b
            when(a) do
                b.θ += π   # controlled X = CNOT (but via when, so nested control)
            end
            (a, b)
        end
        @test_throws ErrorException encode(ch, Steane())
    end
end
