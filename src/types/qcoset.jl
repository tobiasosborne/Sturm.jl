"""
    QCoset{W, Cpad, Wtot}

A coset-encoded modular quantum register. Decoding to the residue `k mod N` is
achieved by measuring the full (W+Cpad)-bit `reg` register and taking the
result mod N. All measurement outcomes satisfy `outcome mod N == k` (up to
approximation error 2^-Cpad per downstream arithmetic op, Gidney Thm 3.2).

Physically, this implementation uses Cpad ADDITIONAL pad-ancilla wires that
are entangled with `reg` after `_coset_init!`. The total internal qubit count
is therefore `W + 2·Cpad`. The pad ancillae encode the coset index j; tracing
them out (via discard or measurement of reg) leaves the correct mixed-state
comb over `{k, k+N, ..., k+(2^Cpad-1)N}`.

This is NOT the pure coset state of Gidney 1905.08488 Figure 1 — which would
require implementing the comparison-negation operations `(-1)^{x≥2^p·N}` to
phase-kickback-uncompute the pad ancillae. For residue-mod-N correctness
(bead 6xi acceptance) the entangled construction suffices. Full pure-coset
preparation with comparison-negation is a follow-on refinement.

# Type parameters
  * `W`    — value register width in qubits (N must satisfy N < 2^W).
  * `Cpad` — number of coset-padding qubits (error per addition ≤ 2^{-Cpad}).
  * `Wtot` — value register wire count: must equal `W + Cpad`. Present as a
             third type parameter to avoid `W + Cpad` arithmetic in struct field
             annotations, which Julia does not permit directly.

# Layout
`reg.wires[1..W]` = value register (little-endian, weight 2^(i−1) at wire i).
`reg.wires[W+1..W+Cpad]` = coset padding (continuing little-endian from weight 2^W).
Contiguous, NOT interleaved (matches Gidney 1905.08488 Fig. 1 value wire order).

`pad_anc[1..Cpad]` = separate ancilla wires used as external controls during
`_coset_init!`. Remain entangled with `reg` after initialisation.

# Linear resource semantics
A `QCoset` is consumed when explicitly discarded via `discard!`, which frees
both `reg` and `pad_anc` wires.

# References
  * Gidney (2019) "Approximate Encoded Permutations and Piecewise Quantum Adders",
    arXiv:1905.08488. Definition 3.1, Theorem 3.2, Figure 1.
    `docs/physics/gidney_2019_approximate_encoded_permutations.pdf`
"""
mutable struct QCoset{W, Cpad, Wtot} <: Quantum
    reg::QInt{Wtot}                   # Wtot = W + Cpad value wires
    pad_anc::NTuple{Cpad, WireID}     # Cpad external pad ancillae, entangled with reg
    modulus::Int                      # classical N — NOT in the type
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

Discard all wires in the coset register AND its pad ancillae (measure and
throw away results). Frees both `q.reg` (W+Cpad wires) and `q.pad_anc` (Cpad wires).
"""
function discard!(q::QCoset{W, Cpad, Wtot}) where {W, Cpad, Wtot}
    check_live!(q)
    ctx = q.reg.ctx
    discard!(q.reg)
    for w in q.pad_anc
        discard!(QBool(w, ctx, false))   # idiomatic partial trace per ancilla
    end
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

    # Allocate the value register initialised to the classical value k.
    # Padding bits of reg start at |0⟩; the coset superposition is built via
    # controlled additions from the separately-allocated pad ancillae.
    reg = QInt{Wtot}(ctx, k)

    # Allocate Cpad SEPARATE pad ancilla wires. These sit outside `reg` and
    # act as external controls for the conditional +2^p·N additions, avoiding
    # the self-control issue that would arise if pad qubits were wires of `reg`.
    pad_anc = ntuple(_ -> allocate!(ctx), Val(Cpad))

    _coset_init!(ctx, reg, pad_anc, Val(W), Val(Cpad), N)

    return QCoset{W, Cpad, Wtot}(reg, pad_anc, Int(N), false)
end

"""
    QCoset{W, Cpad}(k::Integer, N::Integer) -> QCoset{W, Cpad, W+Cpad}

Convenience constructor: uses `current_context()`.
"""
QCoset{W, Cpad}(k::Integer, N::Integer) where {W, Cpad} =
    QCoset{W, Cpad}(current_context(), k, N)
