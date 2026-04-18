# Multi-Controlled Gate via Toffoli Cascade

Implementation ref: `src/context/multi_control.jl` — `_toffoli_cascade_forward!`,
`_toffoli_cascade_reverse!`, `_multi_controlled_gate!`, `_multi_controlled_cx!`.

Historical source: Barenco, Bennett, Cleve, DiVincenzo, Margolus, Shor, Sleator,
Smolin, Weinfurter (1995), *"Elementary gates for quantum computation"*,
Phys. Rev. A **52**(5):3457, §7 ("Simulation of arbitrary gates"), Lemma 7.2.
(No local PDF yet; derivation below is self-contained.)

## Statement

Let `c₁, …, c_N` be N ≥ 2 control qubits and `t` be the target. Given single-
controlled `C-U(·, t)`, we can implement the N-controlled gate

    Λ_N(U) |c₁⟩…|c_N⟩ |t⟩ = |c₁⟩…|c_N⟩ U^{c₁∧…∧c_N} |t⟩

using `N − 1` workspace qubits `w₁, …, w_{N−1}` all initialised to `|0⟩`, plus
`2(N−1)` Toffoli (CCX) gates and one single-controlled `C-U`.

## Construction

**Forward cascade** — AND-reduce the N controls onto `w_{N−1}`:

    CCX(c₁,     c₂, w₁)
    CCX(w₁,     c₃, w₂)
    CCX(w₂,     c₄, w₃)
    ⋮
    CCX(w_{N−2}, c_N, w_{N−1})

After the forward cascade (on computational-basis inputs):

- `w_k = c₁ ∧ c₂ ∧ … ∧ c_{k+1}` for `k = 1, …, N−1`
- In particular `w_{N−1} = c₁ ∧ … ∧ c_N`

**Apply** `C-U(w_{N−1}, t)` — fires iff all original controls are |1⟩.

**Reverse cascade** — run the same CCX sequence in reverse order:

    CCX(w_{N−2}, c_N, w_{N−1})        (undo last AND)
    ⋮
    CCX(w₁,     c₃, w₂)
    CCX(c₁,     c₂, w₁)

Each CCX is its own inverse (it is a permutation of computational basis states
with CCX² = I). After the reverse cascade every `w_k` returns to `|0⟩`.

## Correctness

**Computational basis:** By induction over the cascade steps, `w_k =
c₁ ∧ … ∧ c_{k+1}` after step `k` of the forward cascade. The final `w_{N−1}` is
the AND of all N controls. `C-U(w_{N−1}, t)` therefore fires exactly on the
all-ones branch, giving `U |t⟩`; on any other branch at least one `c_i = 0`, so
`w_{N−1} = 0` and `C-U` is identity on `t`.

The reverse cascade is the inverse of the forward cascade (reverse order of
self-inverse gates), so it takes every workspace qubit back to `|0⟩`.

**Superpositions:** The forward cascade, `C-U`, and reverse cascade are all
unitary. By linearity, if the decomposition maps every computational-basis
input `|c⟩|0⟩_w|t⟩` to the correct output `|c⟩|0⟩_w (U^{⋀c_i} |t⟩)`, it maps
superpositions correctly too.

**Density matrices:** All the gates used (`CCX`, `CX`, single-qubit rotations)
are unitary. On a density matrix `ρ`, each gate `V` acts as `ρ ↦ VρV†` — a
single-Kraus channel. Composition of single-Kraus channels is still a single-
Kraus channel with the product unitary. So applying the decomposition on `ρ`
yields `MCU · ρ · MCU†` where `MCU` is the N-controlled unitary — exactly the
correct coherent operation. This is why `src/context/multi_control.jl` can be
shared between `EagerContext` (statevector) and `DensityMatrixContext` (density
matrix): Orkan's gate functions dispatch on state type at the C level, but the
*decomposition* is identical because it only uses unitary primitives.

## Workspace invariants

- Workspace qubits must be `|0⟩` at entry. `allocate!` on both contexts returns
  a fresh or recycled-and-reset qubit in `|0⟩`, so this is satisfied.
- After the reverse cascade, workspace qubits are `|0⟩` again — they are safely
  returned via `deallocate!` (which itself measures, confirming `|0⟩` with
  probability 1, and recycles the slot).

## Cost

- `2(N − 1)` Toffoli gates.
- One single-controlled `C-U` (which itself decomposes into 2 CX + 2 single-
  qubit rotations via NC&C §4.3 for U ∈ {Ry, Rz}).
- `N − 1` workspace qubits (recycled on exit).
- Depth: `O(N)` (sequential cascade).

For `C-X` specifically (the cascade is applied with one more "cx-control"
wire), the single-controlled gate is already a CCX; total cost `2(N − 1) + 1`
Toffoli. This is `_multi_controlled_cx!`.

## Where used

- `apply_ry!` / `apply_rz!` at control-stack depth ≥ 2 — via `_multi_controlled_gate!`
- `apply_cx!` at depth ≥ 2 — via `_multi_controlled_cx!`
- `apply_ccx!` at depth ≥ 1 — pushes `c1` onto the control stack, then
  `_multi_controlled_cx!(c2, target)`.

Single-control fast paths (depth = 1) bypass the cascade — the AND of one
control is itself, so no workspace is needed and the ABC decomposition (for
rotations) or a direct `CCX` (for CX) suffices.
