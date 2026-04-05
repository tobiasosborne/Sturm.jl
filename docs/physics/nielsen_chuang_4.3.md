# Controlled Rotation Decompositions

Source: Nielsen & Chuang, *Quantum Computation and Quantum Information*,
10th Anniversary Edition, Cambridge University Press, 2010.

Section 4.3, "Controlled operations", pp. 180-184.

## Controlled-U Decomposition (Corollary 4.2)

Any single-qubit unitary U can be decomposed as U = e^{iα} AXBXC where
A, B, C satisfy ABC = I (Theorem 4.1, Eq. 4.4).

Controlled-U then decomposes into:
  C-U = (Phase(α) on control) · CX · C · CX · B · A on target

## Controlled-Ry(θ) — Eq. (4.6) equivalent

For Ry(θ) specifically, the decomposition simplifies because Ry has no
complex phases:

  C-Ry(θ) = Ry(θ/2) · CX(ctrl,tgt) · Ry(-θ/2) · CX(ctrl,tgt)

Verification: when control = |0⟩, both CX are identity, so Ry(θ/2)·Ry(-θ/2) = I.
When control = |1⟩, CX flips target between Ry applications:
  Ry(-θ/2) · X · Ry(θ/2) · X = Ry(-θ/2) · Ry(-θ/2) = ... which gives Ry(θ)
  (since X·Ry(α)·X = Ry(-α), so the sequence becomes Ry(θ/2)·Ry(θ/2) = Ry(θ)).

## Controlled-Rz(θ) — Eq. (4.7) equivalent

Same structure:

  C-Rz(θ) = Rz(θ/2) · CX(ctrl,tgt) · Rz(-θ/2) · CX(ctrl,tgt)

Verification identical, using X·Rz(α)·X = Rz(-α).

## Implementation

Used in `src/context/eager.jl`:
- `_controlled_ry!(ctx, ctrl_wire, target_wire, angle)`
- `_controlled_rz!(ctx, ctrl_wire, target_wire, angle)`
