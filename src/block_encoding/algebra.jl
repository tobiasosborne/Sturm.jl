# Block encoding algebra: product of block encodings.
#
# GSLW19 Lemma 30: If U_A is an (α_A, a_A)-block encoding of A, and
# U_B is an (α_B, a_B)-block encoding of B, then
#   U_AB := (U_A ⊗ I_{a_B}) · (I_{a_A} ⊗ U_B)
# is an (α_A·α_B, a_A+a_B)-block encoding of AB.
#
# The product oracle acts on (ancA ++ ancB, system):
#   oracle_AB!(anc, sys) = oracle_A!(anc[1:a_A], sys) then oracle_B!(anc[a_A+1:end], sys)
#
# Ref: Gilyén, Su, Low, Wiebe (2019), STOC'19, Lemma 30.
#      arXiv:1806.01838
#      Local PDF: docs/literature/quantum_simulation/query_model/1806.01838.pdf

"""
    Base.:*(be_a::BlockEncoding{N}, be_b::BlockEncoding{N}) -> BlockEncoding{N}

Product of two block encodings of N-qubit operators.

If `be_a` encodes A/α_A and `be_b` encodes B/α_B, then `be_a * be_b`
encodes AB/(α_A·α_B) with ancilla count a_A + a_B.

The product oracle applies U_B first (rightmost), then U_A:
  ⟨0|^{a_A+a_B} (U_A ⊗ I_{a_B}) · (I_{a_A} ⊗ U_B) |0⟩^{a_A+a_B}
  = ⟨0|^{a_A} U_A |0⟩^{a_A} · ⟨0|^{a_B} U_B |0⟩^{a_B}
  = (A/α_A)(B/α_B) = AB/(α_A·α_B)

# Ref
GSLW (2019), arXiv:1806.01838, Lemma 30.
"""
function Base.:*(be_a::BlockEncoding{N, A_A}, be_b::BlockEncoding{N, A_B}) where {N, A_A, A_B}
    a_total = A_A + A_B
    alpha_total = be_a.alpha * be_b.alpha

    function oracle_prod!(ancillas::Vector{QBool}, system::Vector{QBool})
        length(ancillas) == a_total || error(
            "product oracle: expected $a_total ancillas, got $(length(ancillas))")
        anc_a = ancillas[1:A_A]
        anc_b = ancillas[A_A+1:end]
        # Apply U_B first (right operand), then U_A (left operand)
        be_b.oracle!(anc_b, system)
        be_a.oracle!(anc_a, system)
        return nothing
    end

    function oracle_adj_prod!(ancillas::Vector{QBool}, system::Vector{QBool})
        length(ancillas) == a_total || error(
            "product oracle adj: expected $a_total ancillas, got $(length(ancillas))")
        anc_a = ancillas[1:A_A]
        anc_b = ancillas[A_A+1:end]
        # (U_A · U_B)† = U_B† · U_A† — reverse order
        be_a.oracle_adj!(anc_a, system)
        be_b.oracle_adj!(anc_b, system)
        return nothing
    end

    return BlockEncoding{N, a_total}(oracle_prod!, oracle_adj_prod!, alpha_total)
end
