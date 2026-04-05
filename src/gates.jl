# Convenience gates built entirely from the four primitives.
# These are NOT part of the language spec — they are standard library.

"""X gate (bit flip). Equivalent to q.θ += π."""
X!(q::QBool) = (q.θ += π; q)

"""Z gate (phase flip). Equivalent to q.φ += π."""
Z!(q::QBool) = (q.φ += π; q)

"""S gate (√Z). Equivalent to q.φ += π/2."""
S!(q::QBool) = (q.φ += π/2; q)

"""T gate (√S). Equivalent to q.φ += π/4."""
T!(q::QBool) = (q.φ += π/4; q)

"""Hadamard gate. H = Rz(π) · Ry(π/2) up to global phase."""
H!(q::QBool) = (q.φ += π; q.θ += π/2; q)

"""Y gate. Y = Rz(π) · Ry(π) up to global phase."""
Y!(q::QBool) = (q.φ += π; q.θ += π; q)

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
