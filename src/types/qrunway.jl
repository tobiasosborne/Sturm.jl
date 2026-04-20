"""
    QRunway{W, Cpad, Wtot}

An oblivious carry runway register. Attaches `Cpad` runway qubits to a
`W`-qubit value register to allow piecewise addition without per-addition
carry propagation.

The runway qubits are initialised into `|+⟩` (Hadamard) and then subtracted
from the high part of the target register at attachment time (see `_runway_init!`
and Gidney 1905.08488 Figure 2). This places the runway in the "oblivious"
eigenstate so that carries passing through it do not leave distinguishable
information about which additions were performed.

# Type parameters
  * `W`    — value register width in qubits.
  * `Cpad` — runway length (number of carry-runway qubits). Error per addition
             is at most 2^{-Cpad} (Gidney Theorem 4.2).
  * `Wtot` — total wire count: must equal `W + Cpad`. Third type parameter to
             avoid `W + Cpad` in struct field annotations.

# NO modulus field
The runway is modulus-agnostic (Gidney §4). The modulus enters only when
composing `QRunway` with `QCoset` at the function-call level (GE21 §2.6).

# Layout
`reg.wires[1..W]` = value register (little-endian, weight 2^(i−1) at wire i).
`reg.wires[W+1..W+Cpad]` = runway (continuing little-endian from weight 2^W).
Contiguous, NOT interleaved (Gidney 1905.08488 Figure 2 wire order).

# Discard discipline
A `QRunway` MUST NOT be discarded directly — the runway bits are entangled with
the rest of the computation, and measurement-based uncomputation (classical carry
correction) must be applied first. Call `runway_fold!` (downstream bead) then
`_runway_force_discard!`. Direct `discard!` is an unconditional error (CLAUDE.md
fail-loud rule).

# References
  * Gidney (2019) "Approximate Encoded Permutations and Piecewise Quantum Adders",
    arXiv:1905.08488. Definition 4.1, Theorem 4.2, Figure 2.
    `docs/physics/gidney_2019_approximate_encoded_permutations.pdf`
"""
mutable struct QRunway{W, Cpad, Wtot} <: Quantum
    reg::QInt{Wtot}
    consumed::Bool
end

classical_type(::Type{<:QRunway}) = Int8
classical_compile_kwargs(::Type{<:QRunway{W}}) where {W} = (bit_width = W,)

# ── Linearity checks ─────────────────────────────────────────────────────────

function check_live!(q::QRunway{W, Cpad, Wtot}) where {W, Cpad, Wtot}
    q.consumed && error(
        "Linear resource violation: QRunway{$W,$Cpad,$Wtot} already consumed"
    )
end

function consume!(q::QRunway{W, Cpad, Wtot}) where {W, Cpad, Wtot}
    check_live!(q)
    q.consumed = true
end

"""
    discard!(q::QRunway)

ERROR: direct discard of a QRunway is forbidden.

The runway qubits are entangled with the computation and must be
classically uncomputed (carry correction) before they can be safely
released. Call `runway_fold!` first to perform measurement-based
uncomputation, then call `_runway_force_discard!` to release the wires.

This error is intentional per CLAUDE.md fail-loud rule: crashes, not
corrupted state.
"""
function discard!(q::QRunway{W, Cpad, Wtot}) where {W, Cpad, Wtot}
    error(
        "QRunway: runway must be measured and classical carry correction " *
        "applied before discard. Call runway_fold! first."
    )
end

"""
    _runway_force_discard!(r::QRunway{W, Cpad, Wtot})

Internal: release all wires after `runway_fold!` has applied classical carry
correction and the runway bits are back to a known state. NOT safe to call
without prior `runway_fold!` (or equivalent uncomputation) — hence the
leading underscore and the absence from public exports.

Callers outside this module that need to clean up after a runway: use
`runway_fold!` (downstream bead b3l), then call this function.
"""
function _runway_force_discard!(r::QRunway{W, Cpad, Wtot}) where {W, Cpad, Wtot}
    check_live!(r)
    discard!(r.reg)
    r.consumed = true
end

# ── Wire access ──────────────────────────────────────────────────────────────

"""
    Base.getindex(q::QRunway{W, Cpad, Wtot}, i::Int) -> QBool

Return a non-owning QBool view of wire `i` (1-indexed). Wire layout:
  * i ∈ 1..W      → value register (little-endian)
  * i ∈ W+1..Wtot → runway (continuing little-endian)
"""
function Base.getindex(q::QRunway{W, Cpad, Wtot}, i::Int) where {W, Cpad, Wtot}
    check_live!(q)
    return q.reg[i]
end

"""Width of the full runway register (W + Cpad wires)."""
Base.length(::QRunway{W, Cpad, Wtot}) where {W, Cpad, Wtot} = Wtot

# ── Constructors ─────────────────────────────────────────────────────────────

"""
    QRunway{W, Cpad}(ctx::AbstractContext, value::Integer) -> QRunway{W, Cpad, W+Cpad}

Allocate an oblivious carry runway register holding `value` in the low W bits
with Cpad runway qubits attached at positions W+1..W+Cpad.

# Preconditions
  * `0 ≤ value < 2^W` — value must fit in the W-bit value register.
  * `Cpad ≥ 1`        — at least one runway qubit.

# Circuit
Allocates a `QInt{W+Cpad}` with the classical `value` in the low W bits and
`|0⟩` in the padding bits, then calls `_runway_init!` to put the runway
qubits into `|+⟩` (Gidney 1905.08488 Figure 2, initialisation step).
The subtraction-from-high-part step in Fig. 2 is performed by downstream
usage of the runway register when composing with an existing register —
it is NOT performed in the constructor because the runway is a free-standing
register until it is attached.

# References
  Gidney (2019) arXiv:1905.08488, Definition 4.1, Figure 2.
"""
function QRunway{W, Cpad}(ctx::AbstractContext, value::Integer) where {W, Cpad}
    W >= 1    || error("QRunway: W must be ≥ 1, got $W")
    Cpad >= 1 || error("QRunway: Cpad must be ≥ 1, got $Cpad")
    0 <= value < (1 << W) || error(
        "QRunway: value=$value out of range [0, $(1<<W - 1)] for W=$W"
    )

    Wtot = W + Cpad

    # Allocate the full register. Low W bits hold `value`; high Cpad bits
    # start at |0⟩ and are rotated into |+⟩ by _runway_init!.
    reg = QInt{Wtot}(ctx, value)

    _runway_init!(ctx, reg, Val(W), Val(Cpad))

    return QRunway{W, Cpad, Wtot}(reg, false)
end

"""
    QRunway{W, Cpad}(value::Integer) -> QRunway{W, Cpad, W+Cpad}

Convenience constructor: uses `current_context()`.
"""
QRunway{W, Cpad}(value::Integer) where {W, Cpad} =
    QRunway{W, Cpad}(current_context(), value)
