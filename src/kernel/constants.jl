# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M1: the named kernel gate constants
# and rotation families — U(2) elements written out under the PINNED
# convention. These are kernel values exported to LIBRARY authors, NOT surface
# vocabulary (PRD-v2 §5): surface code has no gates, no rotation angles, no
# process values (CLAUDE.md #11). They live behind the `public` wall.
#
# Each `M = e^{iφ} U(q)` with U(q) = w·I − i(x σx + y σy + z σz). The U(q) part
# is always det +1 (SU(2)); the det-fixing phase φ is what lifts a bare
# quaternion (which cannot represent the det −1 textbook gates on the nose) to
# the U(2) element. All components verified against the exact-element law tests
# (test_kernel_u2.jl, T4). Physics:
#   docs/physics/wharton_koch_quaternion_bloch.md — the gate table, verbatim.
#     X=i, Y=j, Z=k, H=(i+k)/√2 in the SU(2) part; S,T are the only diagonal
#     gates with det ≠ 1 (hence the only fractional φ). NOT the paper's M_i /
#     Table 1 state labels (X↔k, Z↔i) — those are state-map artifacts.
#   docs/physics/tang_wright_2025_controlled_unitaries.md — why NEG_I ≠ I2 and
#     why gphase(α) is a real object: control promotes global to relative phase.
#
# Fixed-angle constants use cospi/sinpi (exactly-rounded rational multiples of
# π); Ry/Rz/Rx use one sincos call (a consistently-rounded (sin,cos) pair).

"""
    I2

The 1-qubit identity `+I`: `U2(1,0,0,0, 0)`, denoting `I`.
"""
const I2 = U2(1.0, 0.0, 0.0, 0.0, 0.0)

"""
    NEG_I

The canonical form of `−I`: `U2(1,0,0,0, π)`, denoting `e^{iπ} I = −I`.
NEVER merged with `I2`: `−I ≠ I` is physics (`Ry(2π) = −I`, spinor
4π-periodicity) and `ctrl(−I) = diag(1,1,−1,−1)` is a real CZ-grade operation
(`docs/physics/wharton_koch_quaternion_bloch.md`;
`docs/physics/tang_wright_2025_controlled_unitaries.md` Thm 1.1).
"""
const NEG_I = U2(1.0, 0.0, 0.0, 0.0, π)

"""
    X, Y, Z

The Pauli gates. `X = e^{iπ/2} U(i) = i·(−iσx) = σx` (and Y, Z identically with
j, k). `docs/physics/wharton_koch_quaternion_bloch.md`, gate table.
"""
const X = U2(0.0, 1.0, 0.0, 0.0, π / 2)
const Y = U2(0.0, 0.0, 1.0, 0.0, π / 2)
const Z = U2(0.0, 0.0, 0.0, 1.0, π / 2)

"""
    H

Hadamard: `e^{iπ/2} U((i+k)/√2) = i·(−i)(σx+σz)/√2 = (σx+σz)/√2`. Exact H² lands
on `(−1_quat, π) ≡ +I` (`docs/physics/wharton_koch_quaternion_bloch.md`).
"""
const H = U2(0.0, INV_SQRT2, 0.0, INV_SQRT2, π / 2)

"""
    S, T

Phase gates. `S = e^{iπ/4} U(Rz(π/2)) = diag(1, i)` ⇒ `S∘S ≈ Z`.
`T = e^{iπ/8} U(Rz(π/4)) = diag(1, e^{iπ/4})` ⇒ `T∘T ≈ S`. These are the only
diagonal gates with det ≠ 1, hence the only fractional phases
(`docs/physics/wharton_koch_quaternion_bloch.md`).
"""
const S = U2(INV_SQRT2, 0.0, 0.0, INV_SQRT2, π / 4)
const T = U2(cospi(1 / 8), 0.0, 0.0, sinpi(1 / 8), π / 8)

"""
    Ry(γ) -> U2

Rotation about ŷ by `γ`: `q = (cos(γ/2), 0, sin(γ/2), 0)`, `φ = 0` (already
det-1 SU(2)). `Ry(a)∘Ry(b) = Ry(a+b)`, and `Ry(2π) = −I ≠ I`, `Ry(4π) = I`
— dynamics as a representation of (ℝ,+) plus spinor periodicity
(`docs/physics/wharton_koch_quaternion_bloch.md`, Eq 8).
"""
Ry(γ::Real) = (sc = sincos(γ / 2); U2(sc[2], 0.0, sc[1], 0.0, 0.0))

"""
    Rz(γ) -> U2

Rotation about ẑ by `γ`: `q = (cos(γ/2), 0, 0, sin(γ/2))`, `φ = 0`, denoting
`diag(e^{−iγ/2}, e^{iγ/2})` (`docs/physics/wharton_koch_quaternion_bloch.md`).
"""
Rz(γ::Real) = (sc = sincos(γ / 2); U2(sc[2], 0.0, 0.0, sc[1], 0.0))

"""
    Rx(γ) -> U2

Rotation about x̂ by `γ`: `q = (cos(γ/2), sin(γ/2), 0, 0)`, `φ = 0`, denoting
`cos(γ/2) I − i sin(γ/2) σx` (`docs/physics/wharton_koch_quaternion_bloch.md`,
Eq 8).
"""
Rx(γ::Real) = (sc = sincos(γ / 2); U2(sc[2], sc[1], 0.0, 0.0, 0.0))

"""
    gphase(α) -> U2

Global phase `e^{iα} I`: `U2(1,0,0,0, α)`. Invisible under application (Ad's
kernel, PRD-v2 §4.3) but VISIBLE under `ctrl` — `ctrl(gphase(α))` is a
Z-rotation on the control (`docs/physics/delorme_control_as_constructor.md` §5;
`docs/physics/tang_wright_2025_controlled_unitaries.md`). Carried in the
algebra, never quotiented.
"""
gphase(α::Real) = U2(1.0, 0.0, 0.0, 0.0, α)
