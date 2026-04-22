# Convenience gates built entirely from the four primitives.
# These are NOT part of the language spec — they are standard library.

"""
X gate (bit flip). X = Rz(π) · Ry(π) up to global phase.

Ry(π)·Rz(π) = (-iY)·(-iZ) = -YZ = -iX, so the channel is ρ ↦ XρX.
A single Ry(π) alone has channel Y, NOT X — the Rz(π) factor is essential.
Bug history: bead Sturm.jl-3yz (session 42). Previously this was one
primitive `q.θ += π`, which silently implemented the Y channel.
"""
X!(q::QBool) = (q.φ += π; q.θ += π; q)

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
