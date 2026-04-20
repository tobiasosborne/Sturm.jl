"""
    QCoset{W, Cpad, Wtot}

A coset-encoded modular quantum register. Stores a value `r ∈ ℤ/Nℤ` in the
coset representation: a uniform superposition over all encodings

    |Coset_m(r)⟩ = (1/√(2^Cpad)) ∑_{j=0}^{2^Cpad − 1} |r + j·N⟩

where `m = Cpad` is the number of padding qubits and `N` is the classical modulus.

# Type parameters
  * `W`    — value register width in qubits (N must satisfy N < 2^W).
  * `Cpad` — number of coset-padding qubits (error per addition ≤ 2^{-Cpad}).
  * `Wtot` — total wire count: must equal `W + Cpad`. Present as a third type
             parameter to avoid `W + Cpad` arithmetic in struct field annotations,
             which Julia does not permit directly.

# Layout
`reg.wires[1..W]` = value register (little-endian, weight 2^(i−1) at wire i).
`reg.wires[W+1..W+Cpad]` = coset padding (continuing little-endian from weight 2^W).
Contiguous, NOT interleaved (Gidney 1905.08488 Fig. 1 wire order).

# Linear resource semantics
A `QCoset` is consumed when explicitly discarded via `discard!`. Downstream
operations (`coset_add!`, etc.) consume the register on use.

# References
  * Gidney (2019) "Approximate Encoded Permutations and Piecewise Quantum Adders",
    arXiv:1905.08488. Definition 3.1, Theorem 3.2, Figure 1.
    `docs/physics/gidney_2019_approximate_encoded_permutations.pdf`
"""
mutable struct QCoset{W, Cpad, Wtot} <: Quantum
    reg::QInt{Wtot}     # owns all Wtot wires
    modulus::Int        # classical N — NOT in the type (modulus-agnostic dispatch)
    consumed::Bool
end

classical_type(::Type{<:QCoset}) = Int8
classical_compile_kwargs(::Type{<:QCoset{W}}) where {W} = (bit_width = W,)

# ── Linearity checks ─────────────────────────────────────────────────────────

function check_live!(q::QCoset{W, Cpad, Wtot}) where {W, Cpad, Wtot}
    q.consumed && error(
        "Linear resource violation: QCoset{$W,$Cpad,$Wtot} already consumed"
    )
end

function consume!(q::QCoset{W, Cpad, Wtot}) where {W, Cpad, Wtot}
    check_live!(q)
    q.consumed = true
end

"""
    discard!(q::QCoset{W, Cpad, Wtot})

Discard all wires in the coset register (measure and throw away results).
Delegates to `discard!(q.reg)`.
"""
function discard!(q::QCoset{W, Cpad, Wtot}) where {W, Cpad, Wtot}
    check_live!(q)
    discard!(q.reg)
    q.consumed = true
end

# ── Wire access ──────────────────────────────────────────────────────────────

"""
    Base.getindex(q::QCoset{W, Cpad, Wtot}, i::Int) -> QBool

Return a non-owning QBool view of wire `i` (1-indexed). Delegates to the
underlying `reg::QInt{Wtot}`. The wire order follows Gidney 1905.08488 Fig. 1:
  * i ∈ 1..W      → value register (little-endian)
  * i ∈ W+1..Wtot → coset padding (continuing little-endian)
"""
function Base.getindex(q::QCoset{W, Cpad, Wtot}, i::Int) where {W, Cpad, Wtot}
    check_live!(q)
    return q.reg[i]
end

"""Width of the full coset register (W + Cpad wires)."""
Base.length(::QCoset{W, Cpad, Wtot}) where {W, Cpad, Wtot} = Wtot

# ── Constructors ─────────────────────────────────────────────────────────────

"""
    QCoset{W, Cpad}(ctx::AbstractContext, k::Integer, N::Integer) -> QCoset{W, Cpad, W+Cpad}

Allocate a coset-encoded modular register for the value `k` with modulus `N`,
using `Cpad` padding qubits to produce the approximate coset state

    |Coset_Cpad(k)⟩ = (1/√(2^Cpad)) ∑_{j=0}^{2^Cpad − 1} |k + j·N⟩

# Preconditions
  * `0 ≤ k < N` — value must be a valid residue.
  * `N < 2^W`   — modulus must fit in the value register.
  * `Cpad ≥ 1`  — at least one padding qubit.

# Circuit
Allocates a `QInt{W+Cpad}` holding the initial value `k`, then calls
`_coset_init!` to entangle the padding qubits into the coset superposition
(Gidney 1905.08488 Figure 1, initialisation step).

# References
  Gidney (2019) arXiv:1905.08488, Definition 3.1, Figure 1.
"""
function QCoset{W, Cpad}(ctx::AbstractContext, k::Integer, N::Integer) where {W, Cpad}
    W >= 1    || error("QCoset: W must be ≥ 1, got $W")
    Cpad >= 1 || error("QCoset: Cpad must be ≥ 1, got $Cpad")
    0 <= k    || error("QCoset: k must be ≥ 0, got $k")
    k < N     || error("QCoset: k=$k must be < N=$N")
    N < (1 << W) || error(
        "QCoset: N=$N must be < 2^W = $(1 << W) (does not fit in W=$W value bits)"
    )

    Wtot = W + Cpad

    # Allocate the full register initialised to the classical value k.
    # The padding bits start at |0⟩ — _coset_init! will put them into |+⟩
    # and entangle them with the value register.
    reg = QInt{Wtot}(ctx, k)

    _coset_init!(ctx, reg, Val(W), Val(Cpad), N)

    return QCoset{W, Cpad, Wtot}(reg, Int(N), false)
end

"""
    QCoset{W, Cpad}(k::Integer, N::Integer) -> QCoset{W, Cpad, W+Cpad}

Convenience constructor: uses `current_context()`.
"""
QCoset{W, Cpad}(k::Integer, N::Integer) where {W, Cpad} =
    QCoset{W, Cpad}(current_context(), k, N)
