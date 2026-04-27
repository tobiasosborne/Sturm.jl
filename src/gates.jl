# Convenience gates built entirely from the four primitives.
# These are NOT part of the language spec — they are standard library.

"""
    not!(q::QBool) -> QBool

Flip a quantum bit. The boolean-vocabulary name for the X channel:
`q::QBool` is a quantum bit, and the natural mutating operation on a
boolean is `not!`. Equivalent to `q.φ += π; q.θ += π` (= `Rz(π)·Ry(π)`),
which is the X channel `ρ ↦ XρX`.

`X!` is provided as an alias for textbook quantum-vocabulary readers but
the idiomatic Sturm spelling is `not!`. Inside `when(c) do not!(q) end`
the channel is the controlled bit-flip — the channel everyone else
calls CNOT.

Bug history: bead Sturm.jl-3yz (session 42). The fix was to use BOTH
primitives — a single `q.θ += π` is `Ry(π) = -iY`, channel `ρ ↦ YρY`,
NOT X. The `Rz(π)` factor is essential; under `when(c)` its global
phase becomes a relative phase between the c=|0⟩ and c=|1⟩ branches.
"""
not!(q::QBool) = (q.φ += π; q.θ += π; q)

"""X gate alias for `not!`. Provided for textbook quantum-vocabulary
users; idiomatic Sturm uses `not!`."""
const X! = not!

"""Z gate (phase flip). Equivalent to q.φ += π."""
Z!(q::QBool) = (q.φ += π; q)

"""S gate (√Z). Equivalent to q.φ += π/2."""
S!(q::QBool) = (q.φ += π/2; q)

"""T gate (√S). Equivalent to q.φ += π/4."""
T!(q::QBool) = (q.φ += π/4; q)

"""Hadamard gate. H = Rz(π) · Ry(π/2) up to global phase."""
H!(q::QBool) = (q.φ += π; q.θ += π/2; q)

"""
Y gate. Y = Ry(π) up to global phase: Ry(π) = -iY, so channel is ρ ↦ YρY.
Single primitive. (Previously Y! was two primitives implementing X — see
bead Sturm.jl-3yz.)
"""
Y!(q::QBool) = (q.θ += π; q)

"""S-dagger gate. Equivalent to q.φ -= π/2."""
Sdg!(q::QBool) = (q.φ -= π/2; q)

"""T-dagger gate. Equivalent to q.φ -= π/4."""
Tdg!(q::QBool) = (q.φ -= π/4; q)

"""SWAP gate via three CNOTs."""
function swap!(a::QBool, b::QBool)
    a ⊻= b
    b ⊻= a
    a ⊻= b
    return (a, b)
end
