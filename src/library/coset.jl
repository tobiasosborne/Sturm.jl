# Coset and runway initialisation circuits.
#
# Physics:
#   Gidney (2019) "Approximate Encoded Permutations and Piecewise Quantum Adders"
#   arXiv:1905.08488. Figure 1 (InitCoset), Figure 2 (runway init).
#   Local copy: docs/physics/gidney_2019_approximate_encoded_permutations.pdf
#
# Design notes (read before modifying):
#
# _coset_init! — QFT-sandwich approach
#   Gidney Figure 1 shows m stages of: H on a padding qubit, controlled
#   addition of 2^p·N, then a comparison-negation ((-1)^{x≥N}) step.
#   The comparison-negation operations require a reversible comparator circuit
#   (Cuccaro-style) that is not available in this bead's scope (it belongs to
#   downstream bead 6xi). We therefore implement the QFT-sandwich variant,
#   which achieves the SAME coset superposition state by exploiting the
#   QFT-basis addition structure:
#
#     |Coset_m(r)⟩ = (1/√2^m) ∑_{j=0}^{2^m−1} |r + j·N⟩
#                  = (1/√2^m) ∑_{c_0,...,c_{m−1}∈{0,1}} |r + c_0·N + c_1·2N + … + c_{m−1}·2^{m−1}N⟩
#
#   Each padding bit c_p in |+⟩ = (|0⟩+|1⟩)/√2 independently controls an
#   addition of 2^p·N into the full Wtot-qubit register in QFT basis.
#   The QFT basis is needed because add_qft! (Draper 2000) works in-basis.
#
#   Circuit for _coset_init!:
#     1. superpose!(reg)                          — QFT on full Wtot-qubit register
#     2. For p = 0..Cpad-1:
#        a. H! on reg.wires[W+p+1]               — put padding bit p in |+⟩ ***
#        b. when(pad_bit) { add_qft!(reg, 2^p·N) } — controlled Draper add
#     3. interfere!(reg)                          — inverse QFT
#
#   *** Note: after superpose!(reg), the padding bits are already in a QFT-basis
#   state, not in |0⟩. The H! in step 2a is structurally part of the QFT already
#   applied to those bits. Instead of applying H! again (which would undo the QFT
#   action on that bit), we exploit the fact that in the QFT basis the padding
#   bits start in the |φ_k(0)⟩ = |+⟩ state anyway (since they hold value 0).
#   The superpose! transforms |0⟩^Cpad → |+⟩^{Cpad} (all phases zero ⟹ |+⟩).
#   So after superpose!(reg), the padding bits are ALREADY in |+⟩ in the QFT
#   basis — we do NOT apply H! again. We directly use each padding bit as a
#   control for its conditional addition.
#
#   This is correct because:
#     QFT|0…0⟩ = |+⟩^W (every qubit in |+⟩, zero relative phases)
#     The padding bits start at value 0, so after QFT they are in |+⟩.
#     when(pad) { add_qft!(reg, 2^p·N) } adds 2^p·N to the QFT-basis register
#     conditioned on pad, creating the controlled superposition.
#     interfere!(reg) = QFT† maps back to the computational basis.
#
# _runway_init! — trivial |+⟩ initialisation
#   Figure 2 shows the runway qubits initialised as |+⟩, then subtracted from
#   the high part of a target register at ATTACHMENT time. The subtraction from
#   the target is performed by the downstream runway_fold!/coset_add! functions
#   (beads b3l/6xi/6oc), not here. The constructor's job is only to put the
#   Cpad runway qubits into |+⟩. Since the QInt{Wtot} constructor initialises
#   those bits to |0⟩, a single Ry(π/2) per runway qubit suffices (Ry(π/2)|0⟩ = |+⟩).

# ── InitCoset ────────────────────────────────────────────────────────────────

"""
    _coset_init!(ctx::AbstractContext, reg::QInt{Wtot}, ::Val{W}, ::Val{Cpad}, N::Int)

In-place initialisation of a `QInt{Wtot}` (which was prepared in the classical
value `k`) into the coset superposition state

    |Coset_Cpad(k)⟩ = (1/√2^Cpad) ∑_{j=0}^{2^Cpad−1} |k + j·N⟩

using a QFT-sandwich approach:
  1. `superpose!(reg)` — QFT transforms the register to the Fourier basis.
     After QFT, the Cpad padding bits (which hold value 0) are in |+⟩.
  2. For each padding bit position `p ∈ 0..Cpad-1`:
     `when(pad_bit_p) { add_qft!(reg, 2^p · N) }` — in QFT basis, this
     controlled Draper addition implements the controlled increment by 2^p·N.
  3. `interfere!(reg)` — inverse QFT maps back to the computational basis,
     producing the uniform superposition over all j·N offsets.

# Reference
  Gidney (2019) arXiv:1905.08488, Definition 3.1, Figure 1.
  QFT-sandwich approach chosen because the comparison-negation operations in
  the original Figure 1 circuit ((-1)^{x≥N} gates) require a reversible
  comparator not available in this bead. The QFT approach produces the same
  coset state since:
    f(g, c) = g + c·N (Def. 3.1) with c uniform over {0..2^m−1} gives
    exactly the uniform superposition ∑_j |k + j·N⟩.
  Each padding bit controls addition of 2^p·N, so the combined controlled
  additions iterate over all c = Σ_p c_p · 2^p ∈ {0..2^m−1}.
"""
function _coset_init!(ctx::AbstractContext, reg::QInt{Wtot},
                      ::Val{W}, ::Val{Cpad}, N::Int) where {Wtot, W, Cpad}
    Wtot == W + Cpad || error(
        "_coset_init!: Wtot=$Wtot must equal W+Cpad=$(W+Cpad)"
    )

    # Step 1: QFT — transforms reg to Fourier basis.
    # After QFT, the padding bits (which held value 0) are in |+⟩.
    superpose!(reg)

    # Step 2: For each padding bit p, controlled-add 2^p · N in Fourier basis.
    # The padding bit at position p occupies wire index W+p+1 (1-indexed).
    #
    # IMPORTANT: `add_qft!(reg, addend)` inside `when(pad)` would cause Orkan
    # to attempt `controlled-Rz(θ, ctrl=pad_wire, target=pad_wire)` when
    # k = W+p+1. Hardware rejects ctrl==target. The resolution:
    #   * For all wires k ≠ W+p+1: `when(pad) { Rz(θ_k) }` — controlled rotation.
    #   * For wire k = W+p+1 (the control wire itself):
    #     `controlled-Rz(θ, ctrl=q, target=q)` acts as `Rz(θ)` unconditionally,
    #     because on |0⟩ the ctrl is off (no rotation) and on |1⟩ the ctrl is on
    #     (rotation applied), which matches the unconditional Rz(θ) action on |1⟩.
    #     So we apply Rz(θ_self) unconditionally outside `when`.
    #
    # This split-loop mirrors Draper 2000 §5 arithmetic.jl:61 but with the
    # self-wire handled separately.
    for p in 0:(Cpad - 1)
        pad_wire = reg.wires[W + p + 1]
        pad = QBool(pad_wire, ctx, false)  # non-owning view, used as when() ctrl
        addend = (1 << p) * N              # 2^p · N

        # Apply the Draper rotations wire-by-wire (cf. add_qft! body).
        # We reproduce the loop from add_qft! (arithmetic.jl:61) rather than
        # calling add_qft! inside when(), to separate the self-wire case.
        L = Wtot
        a_int = addend
        for k in 1:L
            jj = L - k + 1
            θ = 2π * a_int / (1 << jj)
            target_wire = reg.wires[k]
            if target_wire == pad_wire
                # Self-rotation: ctrl==target ⟹ apply Rz(θ) unconditionally.
                qk = QBool(target_wire, ctx, false)
                qk.φ += θ
            else
                # Normal controlled rotation.
                qk = QBool(target_wire, ctx, false)
                when(pad) do
                    qk.φ += θ
                end
            end
        end
    end

    # Step 3: inverse QFT — maps back to computational basis.
    interfere!(reg)

    return reg
end

# ── Runway init ───────────────────────────────────────────────────────────────

"""
    _runway_init!(ctx::AbstractContext, reg::QInt{Wtot}, ::Val{W}, ::Val{Cpad})

In-place initialisation of the Cpad runway qubits in a `QInt{Wtot}`.

The runway qubits occupy `reg.wires[W+1..W+Cpad]`. The constructor already
initialised them to `|0⟩`. This function applies `Ry(π/2)` to each, mapping
`|0⟩ → |+⟩ = (|0⟩ + |1⟩)/√2`.

This implements the first step of Gidney 1905.08488 Figure 2 ("initialise
carry runway with |+⟩ qubits"). The second step of Figure 2 (subtract the
runway from the high part of the target register) is performed by the
downstream `runway_fold!` function (bead b3l) when the runway is attached
to an existing register.

# Reference
  Gidney (2019) arXiv:1905.08488, Definition 4.1, Figure 2.
"""
function _runway_init!(ctx::AbstractContext, reg::QInt{Wtot},
                       ::Val{W}, ::Val{Cpad}) where {Wtot, W, Cpad}
    Wtot == W + Cpad || error(
        "_runway_init!: Wtot=$Wtot must equal W+Cpad=$(W+Cpad)"
    )

    # Ry(π/2)|0⟩ = cos(π/4)|0⟩ + sin(π/4)|1⟩ = |+⟩
    for p in 0:(Cpad - 1)
        apply_ry!(ctx, reg.wires[W + p + 1], π / 2)
    end

    return reg
end
