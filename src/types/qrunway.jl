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

# Partial-trace discipline
A `QRunway` MUST NOT be partial-traced directly — the runway bits are entangled
with the rest of the computation, and measurement-based uncomputation (classical
carry correction) must be applied first. Call `runway_fold!` (downstream bead)
then `_runway_force_ptrace!`. Direct `ptrace!` (or the backcompat alias
`discard!`) is an unconditional error (CLAUDE.md fail-loud rule).

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
    ptrace!(q::QRunway)

ERROR: direct partial-trace of a QRunway is forbidden.

The runway qubits are entangled with the computation and must be
classically uncomputed (carry correction) before they can be safely
released. Call `runway_fold!` first to perform measurement-based
uncomputation, then call `_runway_force_ptrace!` to release the wires.

This error is intentional per CLAUDE.md fail-loud rule: crashes, not
corrupted state.

`discard!` remains as a backcompat alias. Prefer `ptrace!` (bead diy).
"""
function ptrace!(q::QRunway{W, Cpad, Wtot}) where {W, Cpad, Wtot}
    error(
        "QRunway: runway must be measured and classical carry correction " *
        "applied before partial trace. Call runway_fold! first."
    )
end

"""
    _runway_force_ptrace!(r::QRunway{W, Cpad, Wtot})

Internal: release all wires after `runway_fold!` has applied classical carry
correction and the runway bits are back to a known state. NOT safe to call
without prior `runway_fold!` (or equivalent uncomputation) — hence the
leading underscore and the absence from public exports.

Callers outside this module that need to clean up after a runway: use
`runway_fold!` (downstream bead b3l), then call this function.
"""
function _runway_force_ptrace!(r::QRunway{W, Cpad, Wtot}) where {W, Cpad, Wtot}
    check_live!(r)
    ptrace!(r.reg)
    r.consumed = true
end
const _runway_force_discard! = _runway_force_ptrace!

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

# ── QRunwayMid: runway-in-middle layout (bead jrl) ──────────────────────────
#
# Gidney 2019 §4 Definition 4.1: RUN_{k,p,m,n} — oblivious carry runway of
# length m at bit position p in a register of size n. The classical value
# g ∈ [0, 2^n) is encoded as a pair (e_0, e_1) ∈ (Z/2^{p+m}) × (Z/2^{n-p}):
#   e_0 = (g mod 2^p) + 2^p · c,
#   e_1 = (⌊g/2^p⌋ − c) mod 2^{n-p},
# where c ∈ [0, 2^m) is the runway (coset) index in uniform superposition.
# Theorem 4.2 bounds the per-addition deviation by 2^{-m}: only the single
# branch c = 2^m − 1 overflows when a carry enters the full runway.
#
# This layout is a strict generalisation of QRunway (which has no high part,
# p = n, trivially 0-deviation): QRunwayMid actually delivers the depth
# reduction from GE21 §2.6 by letting the (p+m)-bit low+runway piece and
# the (n-p)-bit high piece be added **in parallel** (no inter-piece carry).
#
# Sturm parameters: Wlow ↔ p, Cpad ↔ m, Whigh ↔ n−p, Wtot = Wlow+Cpad+Whigh.
# Wire layout is contiguous [low | runway | high].

"""
    QRunwayMid{Wlow, Cpad, Whigh, Wtot}

Runway-in-middle oblivious carry runway (Gidney 1905.08488 §4 Def 4.1,
Fig 2–3). Splits a value register of size `Wlow + Whigh` into a low part
below a `Cpad`-wire runway and a high part above it, allowing the two
pieces to be added independently in parallel.

# Type parameters
  * `Wlow`  — low part width (bits 0..Wlow−1 of the encoded value).
  * `Cpad`  — runway length. Per-addition deviation is ≤ 2^{−Cpad}
              (Theorem 4.2); r additions give ≤ (r+1)/2^{Cpad}
              (Theorem 4.3).
  * `Whigh` — high part width (bits Wlow..Wlow+Whigh−1 of the value).
  * `Wtot`  — total wire count: must equal `Wlow + Cpad + Whigh`.

# Layout
`reg.wires[1..Wlow]`                               = low part (LSB=1).
`reg.wires[Wlow+1..Wlow+Cpad]`                     = runway.
`reg.wires[Wlow+Cpad+1..Wlow+Cpad+Whigh]`          = high part.

# Partial-trace discipline
Same as QRunway: direct `ptrace!` is an error (fail-loud per CLAUDE.md).
The blessed cleanup is `runway_mid_decode!` — measure and classical
reconstruct — or `_runway_mid_force_ptrace!` after explicit
uncomputation.

# References
  Gidney (2019) arXiv:1905.08488 §4 Def 4.1, Thm 4.2, Fig 2–3.
  Gidney-Ekerå (2021) arXiv:1905.09749 §2.6 (depth reduction use case).
"""
mutable struct QRunwayMid{Wlow, Cpad, Whigh, Wtot} <: Quantum
    reg::QInt{Wtot}
    consumed::Bool
end

classical_type(::Type{<:QRunwayMid}) = Int8
classical_compile_kwargs(::Type{<:QRunwayMid{Wlow, Cpad, Whigh}}) where {Wlow, Cpad, Whigh} =
    (bit_width = Wlow + Whigh,)

function check_live!(q::QRunwayMid{Wlow, Cpad, Whigh, Wtot}) where {Wlow, Cpad, Whigh, Wtot}
    q.consumed && error(
        "Linear resource violation: QRunwayMid{$Wlow,$Cpad,$Whigh,$Wtot} already consumed"
    )
end

function consume!(q::QRunwayMid{Wlow, Cpad, Whigh, Wtot}) where {Wlow, Cpad, Whigh, Wtot}
    check_live!(q)
    q.consumed = true
end

"""
    ptrace!(q::QRunwayMid)

ERROR: direct partial-trace of a QRunwayMid is forbidden. The runway bits
are entangled with the high part by construction (Fig 2 subtract step).
Blessed cleanup paths: `runway_mid_decode!` (measure and reconstruct) or
`_runway_mid_force_ptrace!` after explicit uncomputation.
"""
function ptrace!(q::QRunwayMid{Wlow, Cpad, Whigh, Wtot}) where {Wlow, Cpad, Whigh, Wtot}
    error(
        "QRunwayMid: runway is entangled with the high part. Call " *
        "runway_mid_decode! to measure-and-reconstruct, or uncompute " *
        "the runway first and then _runway_mid_force_ptrace!."
    )
end

"""
    _runway_mid_force_ptrace!(r::QRunwayMid)

Internal: release all wires after explicit uncomputation (reverse of the
Fig-2 init subtraction). NOT safe without prior uncomputation.
"""
function _runway_mid_force_ptrace!(r::QRunwayMid{Wlow, Cpad, Whigh, Wtot}) where {Wlow, Cpad, Whigh, Wtot}
    check_live!(r)
    ptrace!(r.reg)
    r.consumed = true
end

# ── Wire access ─────────────────────────────────────────────────────────────

function Base.getindex(q::QRunwayMid{Wlow, Cpad, Whigh, Wtot}, i::Int) where {Wlow, Cpad, Whigh, Wtot}
    check_live!(q)
    return q.reg[i]
end

Base.length(::QRunwayMid{Wlow, Cpad, Whigh, Wtot}) where {Wlow, Cpad, Whigh, Wtot} = Wtot

# ── Constructor ─────────────────────────────────────────────────────────────

"""
    QRunwayMid{Wlow, Cpad, Whigh}(ctx, value::Integer) -> QRunwayMid{Wlow, Cpad, Whigh, Wtot}

Allocate a runway-in-middle register holding `value` ∈ [0, 2^(Wlow+Whigh))
with `Cpad` runway qubits inserted between the low and high parts.

# Circuit (Gidney 2019 Fig 2 Init)
  1. Allocate Wtot = Wlow+Cpad+Whigh wires as `QInt{Wtot}` with `value`'s
     low Wlow bits in the low slot, `value`'s high Whigh bits in the high
     slot, and zeros in the runway slot.
  2. Apply Ry(π/2) to each runway wire → |+⟩^Cpad. Runway is now in uniform
     superposition over c ∈ [0, 2^Cpad).
  3. Subtract the runway value c from the high part: `high -= c`. This is
     the "obliviousness" step — after subtraction the high part is
     (⌊value/2^Wlow⌋ - c) mod 2^Whigh, correlated with the runway so that
     e_0 + 2^Wlow · e_1 still decodes to `value`.

# Preconditions
  * `Wlow ≥ 0`, `Cpad ≥ 1`, `Whigh ≥ 1`.
  * `0 ≤ value < 2^(Wlow+Whigh)`.
"""
function QRunwayMid{Wlow, Cpad, Whigh}(ctx::AbstractContext, value::Integer) where {Wlow, Cpad, Whigh}
    Wlow  >= 0 || error("QRunwayMid: Wlow must be ≥ 0, got $Wlow")
    Cpad  >= 1 || error("QRunwayMid: Cpad must be ≥ 1, got $Cpad")
    Whigh >= 1 || error("QRunwayMid: Whigh must be ≥ 1, got $Whigh")
    n = Wlow + Whigh
    0 <= value < (1 << n) || error(
        "QRunwayMid: value=$value out of range [0, $(1<<n - 1)] for Wlow+Whigh=$n"
    )

    Wtot = Wlow + Cpad + Whigh

    # Stuff value with a zero-filled runway gap: low bits at [0..Wlow),
    # zeros at [Wlow..Wlow+Cpad), high bits at [Wlow+Cpad..Wtot).
    low_val  = value & ((1 << Wlow) - 1)
    high_val = value >> Wlow
    stuffed  = low_val | (high_val << (Wlow + Cpad))
    reg = QInt{Wtot}(ctx, stuffed)

    # Step 2: runway → |+⟩^Cpad.
    for p in 0:(Cpad - 1)
        apply_ry!(ctx, reg.wires[Wlow + p + 1], π / 2)
    end

    # Step 3: subtract runway from high part (Fig 2). Runway is the Cpad-bit
    # integer c = Σ 2^j · runway[j+1]. For each j, if runway[j+1] = 1, the
    # classical subtraction "high -= 2^j" fires — coherently controlled by
    # the runway bit. QFT-sandwich on the high piece turns each controlled
    # subtract into a chain of controlled Rz rotations.
    high = QInt{Whigh}(ntuple(k -> reg.wires[Wlow + Cpad + k], Val(Whigh)), ctx, false)
    superpose!(high)
    for j in 0:(Cpad - 1)
        runway_bit = QBool(reg.wires[Wlow + j + 1], ctx, false)
        when(runway_bit) do
            sub_qft!(high, 1 << j)
        end
    end
    interfere!(high)

    return QRunwayMid{Wlow, Cpad, Whigh, Wtot}(reg, false)
end

"""
    QRunwayMid{Wlow, Cpad, Whigh}(value::Integer) -> QRunwayMid{...}

Convenience constructor: uses `current_context()`.
"""
QRunwayMid{Wlow, Cpad, Whigh}(value::Integer) where {Wlow, Cpad, Whigh} =
    QRunwayMid{Wlow, Cpad, Whigh}(current_context(), value)
