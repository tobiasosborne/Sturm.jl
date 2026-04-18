# Arithmetic: QFT-based reversible arithmetic, the foundation for
# polynomial-in-L Shor.
#
# Physics:
#   Draper 2000 (quant-ph/0008033) §3, §5 — classical-constant QFT-adder.
#   Local copy: docs/physics/draper_2000_qft_adder.pdf.
#
# Design principles:
#   * 4 primitives only — no raw matrices, no named gates outside `gates.jl`.
#   * Caller manages the QFT↔computational-basis sandwich. This file
#     implements the in-basis operations.
#   * `a` is a classical `Integer` — Draper's n²/2 controlled rotations
#     collapse to L unconditional Rz rotations. O(L) gates per call.

"""
    add_qft!(y::QInt{L}, a::Integer) -> y

Add the classical integer `a` to a quantum register `y` that is already
in Fourier basis (post-QFT). Returns with `y` still in Fourier basis —
the caller applies `interfere!(y)` to recover `(y + a) mod 2^L` in
the computational basis.

Gate count: exactly L Rz rotations. No ancillae.

# Conventions

  * `y.wires[k]` for k ∈ 1..L is the k-th qubit of a QInt{L} in
    little-endian storage (`wires[1]` holds bit 2^0, `wires[L]` holds
    bit 2^{L-1}). Sturm's `superpose!` ends with a bit-reversal SWAP,
    so after QFT:

        wires[1]  holds |φ_L(y)⟩ = (|0⟩ + e^(2πi·y/2^L)|1⟩)/√2      (full-precision phase)
        wires[2]  holds |φ_{L-1}(y)⟩
        ...
        wires[L]  holds |φ_1(y)⟩ = (|0⟩ + e^(πi·y)|1⟩)/√2           (just (-1)^y)

    i.e. `wires[k]` holds `|φ_{L-k+1}(y)⟩`. To add classical `a` to
    its phase, apply `Rz(2π·a / 2^{L-k+1})` at `wires[k]`.

  * Sturm's `q.φ += δ` is `Rz(δ) = diag(e^(-iδ/2), e^(iδ/2))`. The
    relative phase between |1⟩ and |0⟩ is `e^(iδ)`, so `δ = 2π·a/2^k`
    produces the desired relative phase `e^(2πi·a/2^k)` on qubit k.

  * A global phase of `e^(-iπ·a·(1 − 2^(-L)))` accumulates over all L
    rotations. Invisible for an isolated `add_qft!`; observable when
    the call is inside `when(ctrl) do … end` (it becomes a relative
    phase on `ctrl`). The Beauregard modular adder compensates by
    composing an add-followed-by-subtract pattern that cancels the
    global phase — see Sturm.jl-dgy.

# Reference

  Draper 2000 §5 "Quantum Addition", paragraph starting "The quantum
  addition is performed using a sequence of conditional rotations…",
  specialised to classical `b` so that the n² controlled rotations
  collapse to n unconditional ones.
  `docs/physics/draper_2000_qft_adder.pdf` p. 6.
"""
function add_qft!(y::QInt{L}, a::Integer) where {L}
    check_live!(y)
    ctx = y.ctx
    # Negative a and a ≥ 2^L both wrap cleanly via mod.
    a_mod = mod(Int(a), 1 << L)
    a_mod == 0 && return y
    for k in 1:L
        # wires[k] holds |φ_{L-k+1}(y)⟩; its phase denominator is 2^(L-k+1).
        jj = L - k + 1
        θ = 2π * a_mod / (1 << jj)
        θ = mod(θ + π, 2π) - π      # fold into (-π, π] to keep angles small
        if θ != 0
            qk = QBool(y.wires[k], ctx, false)
            qk.φ += θ
        end
    end
    return y
end

"""
    sub_qft!(y::QInt{L}, a::Integer) -> y

Subtract the classical integer `a` from a Fourier-basis quantum
register `y`, in-place. Adjoint of [`add_qft!`](@ref).

`y` is expected in Fourier basis; output is in Fourier basis; result
computes `(y − a) mod 2^L` in the computational basis after `interfere!`.
"""
sub_qft!(y::QInt{L}, a::Integer) where {L} = add_qft!(y, -Int(a))
