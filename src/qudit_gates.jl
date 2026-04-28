# Convenience qudit gates built from the locked 6-primitive QMod set.
# Parallel to src/gates.jl (qubit gates from the 4-primitive QBool set).
# Reference: docs/physics/qudit_primitives_survey.md (universality + spin-j),
# docs/physics/qudit_magic_gate_survey.md §8 (locked design),
# docs/physics/gottesman_1998_qudit_fault_tolerant.pdf §2 (Weyl-Heisenberg
# definitions),
# docs/physics/bartlett_deGuise_sanders_2002_qudit_simulation.pdf Eq. 13
# (X_d via spin-j Ĵ_x rotation).
#
# Bead Sturm.jl-u2n: ships Z_d! and X_d! at all d ≥ 2; F_d! at d=2 only
# (follow-up bead for d ≥ 3 closed-form QFT decomposition).

# ═══════════════════════════════════════════════════════════════════════════
# Z_d! — Clock / phase gate
# ═══════════════════════════════════════════════════════════════════════════

"""
    Z_d!(q::QMod{d, K}) -> q

Apply the qudit Z (clock) gate `Z_d|k⟩ = ω^k|k⟩` where `ω = e^{2πi/d}`.

Built from a single q.φ rotation. In Sturm's spin-j Rz convention,
`q.φ += δ` is `exp(-iδ·Ĵ_z)`. On Bartlett-labelled `|s⟩ = |j, j-s⟩_z`
(s ∈ {0, …, d-1}, the computational label k), `Ĵ_z|s⟩ = (j-s)|s⟩`, so

    exp(-iδ·Ĵ_z)|s⟩ = exp(-iδ(j-s))|s⟩.

Setting `δ = 2π/d` gives phase `exp(-i·2π(j-s)/d) = exp(+i·2πs/d)·exp(-i·2πj/d)`
= `ω^s · global`. The j-dependent global phase lives in SU(d) (CLAUDE.md
"Global Phase and Universality"). At d=2 this collapses bit-identically
to the qubit `Z!` (`q.φ += π` ↔ `q.φ += 2π/2`).

`Z_d^d = I` up to a state-independent global phase: applying d times
gives `q.φ += 2π·j` which is `exp(-i·2π·integer)` (or `e^{-iπ}` at
half-integer j, even d) — still state-independent ⇒ identity-as-channel.

# Refs
* `docs/physics/gottesman_1998_qudit_fault_tolerant.pdf` Eq. (G4): `Z_d`
  definition.
* `docs/physics/bartlett_deGuise_sanders_2002_qudit_simulation.pdf` Eq. (5)
  (spin-j `Ĵ_z` convention).
"""
function Z_d!(q::QMod{d, K}) where {d, K}
    q.φ += 2π / d
    return q
end

# ═══════════════════════════════════════════════════════════════════════════
# X_d! — Shift gate
# ═══════════════════════════════════════════════════════════════════════════

"""
    X_d!(q::QMod{d, K}) -> q

Apply the qudit X (shift) gate `X_d|k⟩ = |(k+1) mod d⟩`.

# v0.1 scope

Currently shipped at **d = 2 only**, where the Rz · Ry · Rz Euler
decomposition `q.φ += π/2; q.θ += -π; q.φ -= π/2` gives X up to a
global phase (the `+i·X` channel — same `ρ ↦ XρX` map as `X!`/`not!`).

For d ≥ 3, Bartlett Eq. 13's identity `X_d = exp(2πi·Ĵ_x/d)` does NOT
hold in the computational |s⟩ = |1, j-s⟩_z basis: numerically,
`exp(+2πi·Ĵ_x/3)|s=0⟩ = (1/4, i√6/4, -3/4)`, while `X_3|0⟩ = |1⟩ =
(0, 1, 0)`. The identity is in a different (phase-Fourier) basis. The
correct construction for d ≥ 3 is `X_d = F_d† · Z_d · F_d` — but `F_d`
at d ≥ 3 is itself research (its own follow-up bead). Alternative
Bennett-style "increment mod d" requires the jba bead (QMod{d}-Bennett
interop). Both deferred.

Calls at d ≥ 3 error loudly with this rationale.

# Refs
* `docs/physics/gottesman_1998_qudit_fault_tolerant.pdf` Eq. (G4): X_d
  definition.
* `docs/physics/bartlett_deGuise_sanders_2002_qudit_simulation.pdf`
  Eqs. (7), (12), (13): spin-j ↔ Fourier-basis relations (the basis
  caveat).
"""
function X_d!(q::QMod{d, K}) where {d, K}
    if d == 2
        # X_d at d=2 = qubit X gate via Rz(π/2)·Ry(-π)·Rz(-π/2) (= +i·X
        # up to global phase). Same channel as `X!`/`not!`.
        q.φ += π / 2
        q.θ += -π
        q.φ -= π / 2
        return q
    else
        error(
            "X_d!(q::QMod{$d}) is not yet implemented at d ≥ 3. The naive " *
            "Bartlett-Eq-13 spin-j Ĵ_x rotation does NOT compute the " *
            "computational-basis shift at d ≥ 3 (the identity holds in the " *
            "phase-Fourier basis, not the |s⟩=|1,j-s⟩_z basis Sturm uses). " *
            "Correct construction X_d = F_d†·Z_d·F_d requires the F_d follow-" *
            "on bead; alternative Bennett-style 'increment mod d' requires " *
            "Sturm.jl-jba. Both deferred. d = 2 ships."
        )
    end
end

# ═══════════════════════════════════════════════════════════════════════════
# F_d! — Quantum Fourier Transform on a single qudit
# ═══════════════════════════════════════════════════════════════════════════

"""
    F_d!(q::QMod{d, K}) -> q

Apply the qudit QFT (Fourier) gate
`F_d|k⟩ = (1/√d) Σ_{j=0}^{d-1} ω^{jk}|j⟩` where `ω = e^{2πi/d}`.

Defined as the Hadamard-analogue: `F_d†·X_d·F_d = Z_d` (basis change
between the X_d shift basis and the Z_d clock basis).

# v0.1 scope

Currently shipped at **d = 2 only** (`F_2 = H`, a single-qubit
Hadamard built from `q.φ += π; q.θ += π/2` — the existing `H!`
channel). For d ≥ 3 the closed-form decomposition into Sturm
primitives is research-grade and deferred to a follow-on bead. Calls
at d ≥ 3 error loudly with the bead reference.

# Refs
* `docs/physics/gottesman_1998_qudit_fault_tolerant.pdf` Eq. (G10): `F_d`
  definition, Clifford role.
* `docs/physics/muthukrishnan_stroud_2000_multivalued_logic.pdf`
  Eqs. 5–17: 2-level decomposition (basis for the deferred d ≥ 3 work).
"""
function F_d!(q::QMod{d, K}) where {d, K}
    if d == 2
        # F_2 = H = Rz(π) · Ry(π/2) up to global phase. Identical to the
        # qubit H! channel.
        q.φ += π
        q.θ += π / 2
        return q
    else
        error(
            "F_d!(q::QMod{$d}) is not yet implemented at d ≥ 3. The QFT " *
            "decomposition into Sturm's spin-j + quadratic-phase primitives " *
            "is research-grade and filed as a follow-on bead. d = 2 ships " *
            "(equivalent to `H!`)."
        )
    end
end
