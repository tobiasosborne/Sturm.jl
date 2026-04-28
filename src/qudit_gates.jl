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

# ═══════════════════════════════════════════════════════════════════════════
# T_d! — Per-dimension magic gate (Clifford-hierarchy level 3)
# ═══════════════════════════════════════════════════════════════════════════

"""
    T_d!(q::QMod{d, K}) -> q

Apply the qudit T-gate analogue — the level-3-Clifford-hierarchy "magic"
gate per dimension. Per-d branch (locked design §8.5):

* **d = 2**: `T = diag(1, e^{iπ/4})`, the standard qubit T gate.
  Implemented as `q.θ₃ += -π/4` (which at d=2 collapses to
  `apply_rz!(wires[1], π/4)` up to global phase, exactly the qubit T).
* **d = 3** (Watson 2015 Eq. 7): `γ^{n̂³}` with `γ = e^{2πi/9}` (NOT
  ω = e^{2πi/3}, since 3μ ≡ 0 mod 3 collapses cubic to quadratic at
  the natural d-th root). Implemented as `q.θ₃ += -2π/9`.
* **prime d ≥ 5** (Campbell 2014 Eq. 1): `M_1 = ω^{n̂³}` with
  `ω = e^{2πi/d}`. Implemented as `q.θ₃ += -2π/d`.
* **d ∈ {4, 6, 8, 9, …}** (composite or non-prime non-3): errors loudly.
  The Clifford hierarchy structure fragments at non-prime d (CRT
  factorisation conflicts with the user-level mod-d semantics; see
  qudit_magic_gate_survey.md §1.5). Filed under follow-on
  bead "non-prime d magic gate" (locked §8.7).

# Magic-state strategy

T_d! is the EAGER path (locked §8.6): apply `exp(-i(2π/d)·n̂³)` directly
via the `q.θ₃` primitive. For TracingContext + QECC compilation, the
gate is the same channel; the lowering strategy differs (MSD + state
injection via Anwar-Campbell-Browne 2012 / Campbell 2014 Reed-Muller
codes). Both produce equivalent CPTP maps; users see one library gate.

# Refs
* `docs/physics/campbell_2014_enhanced_qudit_ft.pdf` Eq. (1).
* `docs/physics/howard_vala_2012_qudit_magic.pdf` Eq. (16)-(24).
* `docs/physics/watson_campbell_anwar_browne_2015_qudit_color_codes.pdf`
  Eq. (7) (d=3 higher-root remedy).
* `docs/physics/qudit_magic_gate_survey.md` §1, §5 (full derivation +
  per-d branch reasoning); §8.5 (locked T_d! scope).
"""
function T_d!(q::QMod{d, K}) where {d, K}
    if d == 2
        q.θ₃ += -π / 4
    elseif d == 3
        q.θ₃ += -2π / 9
    elseif _is_prime_ge_5(d)
        q.θ₃ += -2π / d
    else  # d ∈ {4, 6, 8, 9, 10, 12, ...} — composite or non-prime non-3
        error(
            "T_d!(q::QMod{$d}) is not yet implemented at d = $d. v0.1 ships " *
            "T_d! at d ∈ {2, 3} and prime d ≥ 5. At composite or " *
            "non-prime-non-3 dimensions the Clifford hierarchy structure " *
            "fragments (CRT factorisation conflicts with mod-d semantics; " *
            "see docs/physics/qudit_magic_gate_survey.md §1.5). Filed under " *
            "the non-prime-d magic-gate follow-on bead."
        )
    end
    return q
end

"""Internal: small primality test for `T_d!`'s d ≥ 5 branch.
Restricted to d ∈ {5, 7, 11, 13, …} which is exactly the v0.1 prime-d
target set. Stays inline-allocation-free (no Primes.jl dependency)."""
@inline function _is_prime_ge_5(d::Int)
    d < 5 && return false
    d == 5 && return true
    iseven(d) && return false
    # Trial-divide odd factors up to √d.
    i = 3
    while i * i <= d
        d % i == 0 && return false
        i += 2
    end
    return true
end
