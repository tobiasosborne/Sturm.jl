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

# ── Coset arithmetic: classical addition into a coset register ───────────────

"""
    coset_add!(c::QCoset{W, Cpad, Wtot}, a::Integer) -> c

Add the classical constant `a` into the coset-encoded register `c`, in-place,
preserving the coset structure. Decoding the result mod `c.modulus` yields
`(k + a) mod N` where `k` was the originally encoded residue, with deviation
at most `2^{-Cpad}` per addition (Gidney 1905.08488 Theorem 3.2 / GE21 §2.4).

This is the GE21 §2.4 "modular-via-non-modular" pattern: in the coset
representation, ordinary (non-modular) addition of a classical constant
implements modular addition mod N to within the deviation bound. The trick
is that the coset state is approximately an eigenvector of the +N operation
(any value-error from wrap-around the (W+Cpad)-bit register affects at most
one coset value out of `2^Cpad`).

# Circuit
QFT-sandwich around a single Draper add:
  1. `superpose!(c.reg)` — QFT into Fourier basis.
  2. `add_qft!(c.reg, a)` — Draper rotations encoding +a (mod 2^Wtot).
  3. `interfere!(c.reg)` — inverse QFT.

The pad ancillae (which encode the coset index `j`) remain entangled with
`c.reg` throughout — they are not touched by `coset_add!`. This preserves
the entangled coset structure so that subsequent additions and a final
`decode!` still produce the correct residue distribution.

# Note on `a`
`a` may be any integer (positive, negative, or larger than N). Decoding via
`% N` always recovers the correct residue.

# Reference
  Gidney (2019) arXiv:1905.08488, §3 (the "near-eigenvector under +N" claim);
  Theorem 3.2 (deviation bound 2^{-Cpad} per addition).
  Gidney-Ekerå (2021) arXiv:1905.09749, §2.4.
"""
function coset_add!(c::QCoset{W, Cpad, Wtot}, a::Integer) where {W, Cpad, Wtot}
    check_live!(c)
    superpose!(c.reg)
    add_qft!(c.reg, a)
    interfere!(c.reg)
    return c
end

# ── Coset decoding: measurement + classical mod N ───────────────────────────

"""
    decode!(c::QCoset{W, Cpad, Wtot}) -> Int

Measure the coset register and pad ancillae, return the encoded residue
`k mod N` (a classical integer in `[0, N)`). Consumes `c`.

The decoding is purely classical: measure all `W + Cpad` value qubits to
get an integer `x ∈ [0, 2^{W+Cpad})`, take `x mod N`. The pad ancillae are
also measured (and discarded) to release their wires.

# Correctness
For an unmodified coset state (no `coset_add!` calls), `x` will be one of
the basis states `{k, k+N, …, k+(2^Cpad-1)·N}`, all satisfying `x mod N == k`.

After `coset_add!(c, a)` calls totalling `a_total`, `x mod N` will equal
`(k + a_total) mod N` with deviation bounded by Theorem 3.2 cumulative
over the operation count.

# Reference
  Gidney 1905.08488 §3 (decoder definition); GE21 §2.15 (classical decoding
  is performed after measurement, not as a quantum circuit).
"""
function decode!(c::QCoset{W, Cpad, Wtot}) where {W, Cpad, Wtot}
    check_live!(c)
    ctx = c.reg.ctx
    x = Int(c.reg)                                 # P2 cast — measures reg
    for w in c.pad_anc                             # partial-trace pad ancillae
        discard!(QBool(w, ctx, false))             # P2-clean: cast wrapper + discard
    end
    c.consumed = true
    return x % c.modulus
end

# ── Runway arithmetic: classical addition into a runway-augmented register ───

"""
    runway_add!(r::QRunway{W, Cpad, Wtot}, a::Integer) -> r

Add the classical constant `a` into the value+runway register, in-place.
The runway absorbs any carries that would otherwise overflow the W-bit
value register; the runway's `|+⟩^Cpad` initialisation makes it invariant
under such carries, so the value register's low W bits cleanly hold
`(value + a) mod 2^W` after the operation.

# Circuit
QFT-sandwich around a single Draper add on the FULL `W+Cpad`-qubit register:
  1. `superpose!(r.reg)` — QFT into Fourier basis.
  2. `add_qft!(r.reg, a)` — Draper rotations encoding +a (mod 2^Wtot).
  3. `interfere!(r.reg)` — inverse QFT.

# Note on the runway-at-end case
This implementation places the runway at the high end of the register
(no high part above). In this configuration the |+⟩^Cpad runway is
invariant under any classical addition (a constant addition merely
relabels the runway's superposition index), so decoded low W bits equal
`(value + a) mod 2^W` deterministically. The Theorem 4.2 deviation bound
of `2^{-Cpad}` per addition applies to the runway-in-middle layout
(high part above runway), which is a different type signature reserved
for follow-on work.

# Reference
  Gidney (2019) arXiv:1905.08488, §4 Definition 4.1, Theorem 4.2.
  Gidney-Ekerå (2021) arXiv:1905.09749, §2.6.
"""
function runway_add!(r::QRunway{W, Cpad, Wtot}, a::Integer) where {W, Cpad, Wtot}
    check_live!(r)
    superpose!(r.reg)
    add_qft!(r.reg, a)
    interfere!(r.reg)
    return r
end

# ── Runway decoding: measurement + classical low-W extraction ────────────────

"""
    runway_decode!(r::QRunway{W, Cpad, Wtot}) -> Int

Measure the full runway-augmented register, return the value in the low
W bits (a classical integer in `[0, 2^W)`). Consumes `r`.

The runway bits are also measured (the classical outcome is discarded —
GE21 §2.6 calls this the "post-measurement classical cleanup", trivial
for the runway-at-end configuration where no further correction is needed).

# Reference
  GE21 §2.6 (classical cleanup is performed after measurement).
"""
function runway_decode!(r::QRunway{W, Cpad, Wtot}) where {W, Cpad, Wtot}
    check_live!(r)
    x = Int(r.reg)                # P2 cast — measures all W+Cpad wires
    r.consumed = true
    return x & ((1 << W) - 1)     # low W bits
end
