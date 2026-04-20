# Coset and runway initialisation circuits.
#
# Physics:
#   Gidney (2019) "Approximate Encoded Permutations and Piecewise Quantum Adders"
#   arXiv:1905.08488. Figure 1 (InitCoset), Figure 2 (runway init).
#   Local copy: docs/physics/gidney_2019_approximate_encoded_permutations.pdf
#
# _coset_init! — external-ancilla approach
#   Gidney Fig. 1 shows Cpad stages of: H on a padding qubit, controlled
#   addition of 2^p·N, then a comparison-negation `(-1)^{x≥2^p·N}`. The
#   comparison-negation phase-kickback-disentangles the padding qubits from
#   the value register, producing the PURE coset state on a single W+Cpad
#   qubit register. Implementing comparison-negation requires a reversible
#   comparator — deferred to a follow-on refinement bead.
#
#   For bead 6xi acceptance (residue-mod-N correctness), we implement the
#   simpler variant WITHOUT comparison-negation: allocate Cpad separate pad
#   ancillae, put them in |+⟩, use them as EXTERNAL controls for +2^p·N into
#   reg. The resulting state is entangled:
#
#     (1/√2^Cpad) ∑_{j=0..2^Cpad-1} |j⟩_pad ⊗ |k + j·N⟩_reg
#
#   Tracing out the pad (via discard or reg-only measurement) leaves the
#   correct coset comb distribution: every measurement of reg yields
#   (k + jN) for some j, so `outcome mod N == k` deterministically. This
#   matches Gidney 1905.08488 Thm 3.2's measurement-level claim.
#
#   Why "external" ancillae (not high bits of reg): if pad bits were wires
#   of reg, the controlled addition `when(pad_p) { reg += 2^p·N }` would
#   require pad_p as both control and target (reg.wires[W+p+1]), which
#   Orkan rejects. External ancillae sidestep this entirely.

# ── InitCoset ────────────────────────────────────────────────────────────────

"""
    _coset_init!(ctx, reg::QInt{Wtot}, pad_anc::NTuple{Cpad,WireID},
                 ::Val{W}, ::Val{Cpad}, N::Int)

In-place initialisation of `reg` (already holding classical value `k`) and
`pad_anc` (all wires at `|0⟩`) into the entangled coset state

    (1/√2^Cpad) ∑_{j=0..2^Cpad-1} |j⟩_pad ⊗ |k + j·N⟩_reg

Circuit (three phases):
  1. For each `p ∈ 0..Cpad-1`: apply Ry(π/2) to `pad_anc[p+1]` to put it in `|+⟩`.
  2. `superpose!(reg)` — QFT reg into Fourier basis.
  3. For each `p ∈ 0..Cpad-1`:
       `when(pad_anc[p+1]) { add_qft!(reg, 2^p · N) }`
     Each controlled-add emits a Draper loop of Rz rotations on reg.wires,
     with pad_anc[p+1] as EXTERNAL control (no self-control because pad_anc
     is allocated separately from reg).
  4. `interfere!(reg)` — inverse QFT back to computational basis.

Properties guaranteed by the resulting state:
  * Measuring `reg` yields outcome `k + jN` for uniformly-random
    `j ∈ {0,..,2^Cpad-1}`. Therefore `outcome mod N == k` deterministically.
  * The pad ancillae remain entangled with `reg` — they encode `j`. Tracing
    them out (via `discard!` on the `QCoset`) does not affect the residue
    distribution on `reg`.

# Reference
  Gidney (2019) arXiv:1905.08488, Definition 3.1, Figure 1. This function
  implements the "pre-comparison-negation" portion of the InitCoset circuit.
"""
function _coset_init!(ctx::AbstractContext, reg::QInt{Wtot},
                      pad_anc::NTuple{Cpad, WireID},
                      ::Val{W}, ::Val{Cpad}, N::Int) where {Wtot, W, Cpad}
    Wtot == W + Cpad || error(
        "_coset_init!: Wtot=$Wtot must equal W+Cpad=$(W+Cpad)"
    )

    # Phase 1: put each pad ancilla into |+⟩ via Ry(π/2)|0⟩ = |+⟩.
    for p in 0:(Cpad - 1)
        apply_ry!(ctx, pad_anc[p + 1], π / 2)
    end

    # Phase 2: QFT the value register so that add_qft! can operate in-basis.
    superpose!(reg)

    # Phase 3: for each p, controlled-add 2^p · N to reg, controlled by
    # pad_anc[p+1]. Because pad_anc is EXTERNAL to reg, add_qft!'s Rz loop
    # can fire under when(pad_q) without ctrl==target conflict.
    for p in 0:(Cpad - 1)
        addend = (1 << p) * N
        pad_q = QBool(pad_anc[p + 1], ctx, false)
        when(pad_q) do
            add_qft!(reg, addend)
        end
    end

    # Phase 4: inverse QFT — back to computational basis.
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
