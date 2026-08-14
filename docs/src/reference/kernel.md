# Reference — the kernel

```@meta
CurrentModule = Sturm
```

*Dry, exhaustive lookup for the layer under the surface. None of this is
surface vocabulary — a Sturm program never names a process value. See
[phase discipline](../explanation/phase_discipline.md) for why the kernel
looks the way it does.*

A **process value** is a definite operation: a specific element of a unitary
group, not a channel. Everything here is `public` but not exported, reachable
as `Sturm.U2`, `Sturm.ctrl`, and so on.

Two facts to carry into every docstring below:

- **Wire 1 is the most significant bit**, and for a controlled value the
  leading wires are the controls. One convention, everywhere.
- **`==` is exact structural equality; `≈` is the physically meaningful
  comparison.** They genuinely differ — `H ∘ H == I2` is `false` and
  `H ∘ H ≈ I2` is `true`.

---

## The value tree

`U2` is an element of `U(2)` stored as a unit quaternion plus an explicit
phase; the phase is kept, never quotiented away, because it becomes observable
under control. `Perm` is the phase-free classical-reversible corner. `Tensor`
and `Seq` are the lazy parallel and series combinators. `QFT` is the discrete
Fourier transform that `dual` addresses through.

```@docs
ProcessValue
U2
Perm
Tensor
Seq
QFT
nwires
denoted_matrix
```

## Composition, adjoint and control

`ctrl` is **the single construction site for controlled operations in the whole
system** — a build-time check refuses any other file that names the underlying
constructor. Controls are flat, not nested. There is no catch-all method, so
control on a channel is an honest `MethodError` rather than a plausible wrong
answer.

```@docs
Ctrl
ctrl
⊗
```

Series composition rides `Base.:∘` (right to left: `a ∘ b` applies `b` first)
and adjoint rides `Base.adjoint`, both with methods for every process-value
kind. Wire-count mismatch fails loud.

## Named constants

The kernel's exact gate vocabulary. `X`, `Y` and `Z` share one docstring, as do
`S` and `T`. `I2` and `NEG_I` are deliberately distinct constants and are never
merged: `Ry(2π) ≈ NEG_I`, which is spinor 4π-periodicity, not a rounding
artefact.

```@docs
I2
NEG_I
X
H
S
Ry
Rz
Rx
gphase
P
```

## See also

- [Phase discipline](../explanation/phase_discipline.md) — global phase,
  double-cover equality, and the one choke point.
- [Reference: channels](channels.md) — `UnitaryBlock`, `certify`, the channel
  IR and the optimisation passes.
- [The seven constructs](../explanation/seven_constructs.md) — why none of this
  appears in surface code.
