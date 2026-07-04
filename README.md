# Sturm.jl

A Julia quantum programming language where **functions are channels**, the
**quantum-classical boundary is a type cast**, and **QECC is a higher-order
function**.

## Status: v2 rebuild in progress (2026-07)

This branch is being rebuilt from scratch against
[`Sturm-PRD-v2.md`](Sturm-PRD-v2.md) — the ground-up redesign that replaces
the v0.1 rotation primitives with a three-layer architecture: a surface
that is normal programming (casts, `⊻=`, `dual` conjugate views, `when`),
a kernel of definite process values where control and adjoint are
well-defined by theorem, and a library of physicist conveniences.

- **Spec:** [`Sturm-PRD-v2.md`](Sturm-PRD-v2.md) (normative) and
  [`Sturm-PRD.md`](Sturm-PRD.md) (v0.1, for the carried-over parts).
- **The complete v0.1 prototype** (Shor, QSVT, Steane [[7,1,3]], hardware
  transport, ~60 test files) lives on the
  [`v0.1-deprecated`](../../tree/v0.1-deprecated) branch.
- **Why the reboot:** PRD-v2 §1 — the Bloch-angle primitive layer was
  condemned on physics, Julia-idiom, and dimension-agnosticism grounds;
  the axioms survived, the primitives did not.

## License

AGPL-3.0.
