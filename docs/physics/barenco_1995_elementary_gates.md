# Elementary Gates for Quantum Computation

Source: A. Barenco, C. H. Bennett, R. Cleve, D. P. DiVincenzo, N. Margolus,
P. Shor, T. Sleator, J. Smolin, H. Weinfurter, "Elementary gates for quantum
computation", *Phys. Rev. A* **52**, 3457 (1995).
DOI: 10.1103/PhysRevA.52.3457. arXiv:quant-ph/9503016v1, 23 Mar 1995.
PDF in `docs/physics/barenco_1995_elementary_gates.pdf`.

This is the canonical reference for **controlled-unitary decomposition**. It
is the rule-4 physics gate for the M2 application kernel (`src/kernel/ad.jl`):
the code path that lowers a `Ctrl{U2}` process value to Orkan's native gate
set {1q rotations, CX, CCX} cites the lemmas transcribed below. The single
load-bearing result is the **ABC + phase** decomposition of a controlled
U(2) matrix (Lemmas 4.3, 5.1, 5.2 + Corollary 5.3), because it is exactly the
step where the inner value's *global* phase becomes a *controlled* phase on
the control line — the step v0.1's surface ABC dropped.

Notation throughout (theirs): `∧_k(U)` is the gate applying the 1-qubit
unitary `U` to one target bit iff the logical AND of `k` control bits is 1.
So `∧₀(U)` = a bare 1-bit gate, `∧₁(U)` = controlled-U (their "C-U"),
`∧₂(σ_x)` = Toffoli/CCX, `∧₁(σ_x)` = XOR/CNOT. A *basic* operation means one
`∧₀(U)` **or** one XOR (`∧₁(σ_x)`) gate. Time flows left→right in every
network (leftmost gate acts first).

---

## §4 — Matrix properties: the ZYZ + phase charts

**Rotation / phase primitives (definitions, p. 9):**

```
R_y(θ) = [[ cos θ/2 , sin θ/2 ],      R_z(α) = [[ e^{iα/2} ,    0     ],
          [−sin θ/2 , cos θ/2 ]]                [    0     , e^{−iα/2}]]

Ph(δ)  = [[ e^{iδ} ,   0   ],   = e^{iδ}·I   (a GLOBAL phase, not diag(1,e^{iδ}))
          [   0    , e^{iδ}]]
```

**Lemma 4.1 (p. 8) — universal 1q chart.** *Every* unitary 2×2 matrix
factors as

```
U = Ph(δ) · R_z(α) · R_y(θ) · R_z(β)                    (δ,α,θ,β ∈ ℝ)
```

and *every* **special** unitary (det = 1, `W ∈ SU(2)`) factors WITHOUT the
phase, `W = R_z(α)·R_y(θ)·R_z(β)`, because det = 1 forces `e^{iδ} = ±1`,
absorbable into the SU(2) part. **This `Ph(δ)` is the U(2)-vs-SU(2)
bookkeeping term** — the fifth float of Sturm's `U2` — and it is the sole
difference between an SU(2) chart and a full U(2) chart.

**Lemma 4.2 (p. 9) — the conjugation identities the ABC proof runs on.**
`R_y(θ₁)R_y(θ₂)=R_y(θ₁+θ₂)`, likewise `R_z`, `Ph`; and the σ_x sandwiches
`σ_x·R_y(θ)·σ_x = R_y(−θ)`, `σ_x·R_z(α)·σ_x = R_z(−α)`, `σ_x·σ_x = I`.

**Lemma 4.3 (p. 9) — the ABC decomposition (load-bearing).**
For any `W ∈ SU(2)` there exist `A, B, C ∈ SU(2)` with

```
A·B·C = I        and        A · σ_x · B · σ_x · C = W.
```

Explicit witnesses (from the proof, with `W = R_z(α)R_y(θ)R_z(β)`):

```
A = R_z(α) · R_y(θ/2)
B = R_y(−θ/2) · R_z(−(α+β)/2)
C = R_z((β−α)/2)
```

Check: `ABC = R_z(α)R_z(−α) = I`; and inserting the two σ_x's flips the sign
of the inner `R_y` and `R_z` arguments (Lemma 4.2), recombining to `W`. Note
`A,B,C ∈ SU(2)` — no phase appears here; phase is handled separately below.

---

## §5 — Two-bit networks: controlled-U with the phase made explicit

**Lemma 5.1 (p. 10) — ∧₁(W) for W ∈ SU(2).** A controlled-`W` gate equals

```
∧₁(W)  =  [C on target] · CNOT · [B on target] · CNOT · [A on target]
```

(control = first bit; `A,B,C` the Lemma-4.3 matrices on the target; leftmost
acts first, so read the product right-to-left as `A·σ_x·B·σ_x·C`). **This
holds iff `W ∈ SU(2)`** — the "only if" is because `det(A σ_x B σ_x C)=1`
forces `W` special unitary. A controlled gate on a non-special `U` therefore
CANNOT be built from A/CNOT/B/CNOT/C alone; it needs the phase gate of
Lemma 5.2. This is the exact hinge.

**Lemma 5.2 (p. 11) — the controlled GLOBAL phase collapses to a 1-bit gate
on the CONTROL.** For any `δ` and `S = Ph(δ)`,

```
∧₁(Ph(δ))  =  a single 1-bit gate  E  applied to the CONTROL line alone,
   where   E = R_z(−δ) · Ph(δ/2) = [[1,      0   ],
                                    [0,  e^{iδ}  ]]  = diag(1, e^{iδ}).
```

The 4×4 unitary of both sides is `diag(1, 1, e^{iδ}, e^{iδ})` (p. 11). i.e.
controlling a *global* phase `e^{iδ}` on the target produces a phase `e^{iδ}`
that fires **only when the control is 1, and touches the control, not the
target**. THIS is the controlled-phase `p(control, δ)`. The target-side
matrix is identity — the control absorbs the whole effect.

**Corollary 5.3 (p. 11) — arbitrary controlled-U(2).** Since any unitary
`U = Ph(δ)·W` with `W ∈ SU(2)` (Lemma 4.1), and `∧₁` distributes over the
product, `∧₁(U) = ∧₁(Ph(δ)) · ∧₁(W)`:

```
∧₁(U)  =  E(control)  ·  [ C·CNOT·B·CNOT·A on target ]
```

= at most **six basic gates**: four 1-bit gates (`E, A, B, C`) and two XORs.
The δ from `U`'s determinant lands entirely in `E = diag(1,e^{iδ})` on the
control. **Dropping `E` gives the SU(2) part only — the exact v0.1 bug.**

*Efficient special cases (context, one line each):* Lemma 5.4 (p. 12) —
if `W = R_z(α)R_y(θ)R_z(α)` then one CNOT can be saved (`B = A†`, `C = I`).
Lemma 5.5 / Corollary 5.6 (p. 13) — a `∧₁(V)` with `V = R_z(α)R_y(θ)R_z(α)σ_x`
needs one CNOT; used to build cheap `∧₂(U)`.

---

## §6 — Three-bit networks: C²(U) via a square root

**Lemma 6.1 (p. 14) — ∧₂(U) from any V with V² = U (EXACT, any unitary).**
For *any* unitary 2×2 `U`, pick *any* unitary `V` with `V² = U`. Then

```
∧₂(U)  =  ∧₁(V)[ctrl b2] · CNOT[b1→b2] · ∧₁(V†)[ctrl b2]
                         · CNOT[b1→b2] · ∧₁(V)[ctrl b1]
```

Proof by casework on the two control bits `x₁,x₂`: the target sees `V` iff
`x₂=1`, `V†` iff `x₁⊕x₂=1`, `V` iff `x₁=1`; since
`x₁+x₂−(x₁⊕x₂) = 2·(x₁∧x₂)`, the net is `V²=U` iff `x₁∧x₂=1`, else `I` or
`V·V†=I` (p. 15). **This is exact for any square root `V` of any unitary `U`
— no SU(2) restriction, no approximation** (unlike the eigenvalue-halving
`V` used later for the *approximate* linear construction, Lemma 7.8). Each
`∧₁(V)`/`∧₁(V†)` expands by Corollary 5.3 (phase included). Generalises to
`∧_m(V^{2^{m-1}})` (p. 15) — the seed of §7.

**Corollary 6.2 (p. 15).** `∧₂(U)` for any unitary `U` = at most **sixteen
basic gates** (eight 1-bit + eight XOR) after merging adjacent
`∧₀(C)∧₀(C†)=I` pairs. Special case `U=σ_x` = the Toffoli `∧₂(σ_x)`.

---

## §7 — n-bit networks: multi-controlled ladders and ancilla policy

**Grey-code / no-ancilla base (§7 opening + Lemma 7.1, p. 17).**
`∧_{n-1}(U)` for any unitary `U`, `V^{2^{n-2}} = U`, is built from
`2^{n-1}−1` copies of `∧₁(V)` and `2^{n-1}−2` copies of `∧₁(σ_x)` (CNOTs), no
ancilla, arranged as a grey-code sequence. **Cost Θ(2ⁿ)** — exact but
exponential. (Taking mergers into account: `3·2^{n-1}−4` XORs and `2·2^{n-1}`
1-bit gates.)

**Lemma 7.2 (p. 18) — Toffoli ladder for `∧_m(σ_x)` with BORROWED work
bits.** If `n ≥ 5` and `m ∈ {3, …, ⌈n/2⌉}`, then a `∧_m(σ_x)` gate on an
`n`-bit network can be simulated by `4(m−2)` Toffoli (`∧₂(σ_x)`) gates. It
uses `n−m−1` *work* bits. **Crucially these ancillae are DIRTY / BORROWED:**
"the gate operation is performed correctly independent of the initial state
of the bits (they do not have to be cleared to 0 first), and they are reset
to their initial values after" (p. 20). No clean-zero requirement.

**Lemma 7.3 (p. 19) — split a big MCX into two smaller ones.** For `n ≥ 5`,
`m ∈ {2,…,n−3}`, a `∧_{n-2}(σ_x)` = two `∧_m(σ_x)` + two `∧_{n-m-1}(σ_x)`,
again on borrowed (uncleared, restored) bits.

**Corollary 7.4 (p. 20) — the linear Toffoli count.** For `n ≥ 7`,
`∧_{n-2}(σ_x)` (an `(n−1)`-input Toffoli on an `n`-bit register, i.e. **one
borrowed ancilla**) = `8(n−5)` Toffoli gates = `48n − 204` basic operations.
Combines 7.2 (with `m₁=⌈n/2⌉`, `m₂=n−m₁−1`) and 7.3; only the 4 Toffolis
touching the last bit need the exact (16-op) Corollary-6.2 expansion, the
rest use the phase-modulo (6-op) form of §6.2.

**Lemma 7.5 (p. 21) — quadratic `∧_{n-1}(U)`, NO ancilla.** For any unitary
`U`, with `V²=U`:
`∧_{n-1}(U) = ∧₁(V)[ctrl last ctrl-bit] · ∧_{n-2}(σ_x) · ∧₁(V†) · ∧_{n-2}(σ_x) · ∧₁(V)`
(same shape as Lemma 6.1, the two CNOTs promoted to `∧_{n-2}(σ_x)`).
**Corollary 7.6 (p. 21):** recursing gives `∧_{n-1}(U)` in **Θ(n²)** basic
ops (`48n² + O(n)`), no ancilla — recurrence `C_{n-1} = C_{n-2} + Θ(n)`.

**Lemma 7.7 (p. 22) — lower bound.** Any *nonscalar* `∧_{n-1}(U)` (i.e.
`U ≠ Ph(δ)·I`) requires **at least `n−1` basic operations** (a connectivity
/ tensor-factor argument).

**Lemma 7.8 (p. 22) — approximate linear.** For any unitary `U` and `ε>0`,
`∧_{n-1}(U)` is approximated within `ε` by **Θ(n·log(1/ε))** basic ops,
truncating the 7.5 recursion after `⌈log₂(π/ε)⌉` levels with
`V_k = P† D_k P`, `D_k = diag(e^{id₁/2ᵏ}, e^{id₂/2ᵏ})` — the eigenvalue-
halving square-root chain (this `V` is *approximate*, contrast Lemma 6.1's
exact `V²=U`).

**Lemma 7.9 / Corollary 7.10 (p. 24) — SU(2) special case, linear.** For
`W ∈ SU(2)`, `∧_{n-1}(W)` = `A·MCX·B·MCX·C` form (multi-controlled analogue
of Lemma 5.1, `A,B,C ∈ SU(2)`); combined with Corollary 7.4 gives
`∧_{n-2}(W)` in **Θ(n)** basic ops (one borrowed bit). No phase term, since
`W ∈ SU(2)`.

**Lemma 7.11 / Corollary 7.12 (p. 25) — general `∧_{n-2}(U)`, linear, with
ONE CLEAN ancilla.** For any unitary `U`, `∧_{n-2}(U)` = Θ(n) basic ops on an
`n`-bit network **where the second-to-last bit is a clean bit fixed at 0 and
incurs no net change** (returned to 0, hence reusable across many
`∧_m(U)` calls). Construction: `CNOT`s copy the AND onto the clean bit, a
single `∧₁(U)` fires off it, uncomputed.

**Ancilla summary (the distinction M2 must respect):**
- `∧_{n-2}(σ_x)` (Toffoli) and `∧_{n-1}(W)`, `W∈SU(2)`: linear with **one
  BORROWED (dirty) bit** — any state, restored (Cor 7.4, 7.10).
- General `∧_{n-2}(U)` (phase-carrying `U`): linear needs **one CLEAN bit
  = |0⟩**, returned to |0⟩ (Cor 7.12). Without a clean bit the ancilla-free
  route is quadratic (Cor 7.6).

---

## Relevance to Sturm v2

Sturm represents each 1q unitary as a `U2` process value = unit quaternion +
U(1) phase `(q, φ)` (see `wharton_koch_quaternion_bloch.md`; PRD-v2 §4.1). The
phase float `φ` is precisely Lemma 4.1's `Ph(δ)` factor: `U = e^{iφ}·U(q)`
with `U(q) ∈ SU(2)`. The M2 `ctrl` value `Ctrl{U2}` at control-stack depth
`k` lowers to Orkan's {1q, CX, CCX} through the following map, **phase-exactly**
because the kernel carries `φ` explicitly and never quotients it in library
code (PRD-v2 §4.3, phase quotient crossed once at application).

1. **k = 1 → Lemmas 4.3 + 5.1 + 5.2 (Corollary 5.3).** Split the `U2` value:
   `q → (A,B,C) ∈ SU(2)` via the ZYZ chart (Lemma 4.1) and the ABC witnesses
   (Lemma 4.3, `A=R_z(α)R_y(θ/2)`, `B=R_y(−θ/2)R_z(−(α+β)/2)`,
   `C=R_z((β−α)/2)`); emit `A·CX·B·CX·C` on the target (Lemma 5.1), and emit
   the phase `φ` as **`E = diag(1, e^{iφ})` on the CONTROL line** (Lemma 5.2).
   That `E` is the controlled-phase `p(control, φ)`. The ZYZ extraction is the
   θ≈0/π chart singularity handled *only* at the FFI boundary (CLAUDE.md,
   PRD-v2 D7); Hamilton composition upstream is chart-free.

2. **THE v0.1-vs-v2 PHASE POINT (why this file gates the code).** Barenco's
   `∧₁(W)` (Lemma 5.1) holds **iff `W ∈ SU(2)`** — the A/CX/B/CX/C skeleton
   can only ever produce a det-1 target action. For a general
   `W = e^{iδ}·SU(2)` the determinant phase `δ` must be emitted **separately**
   as `∧₁(Ph(δ)) = diag(1,e^{iδ})` on the control (Lemma 5.2). v0.1's surface
   ABC lowered `dual`/controlled forms through the SU(2) skeleton and **dropped
   `δ`** — invisible on a single controlled gate (global phase), catastrophic
   once that gate sits under a further control or in superposition (the phase
   becomes relative). v2 is correct *by construction*: `φ` rides inside the
   `U2` value, and `ctrl` — the single choke point (CLAUDE.md, PRD-v2 §4.2) —
   lowers it to an explicit `p(δ)` on the control. This is the canonical
   controlled-phase-bug class of PRD-v2 §4.2 (the multi-year Cirq/Qiskit/pytket
   family), pre-empted at the type level.

3. **k = 2 → Lemma 6.1.** `Ctrl²{U2}` lowers via a square root `V` with
   `V² = U`: a `U2` square root is a quaternion half-angle + half-phase
   (`(q,φ) → (q^{1/2}, φ/2)`), which is **exact** (Lemma 6.1 needs only
   *some* unitary `V`, `V²=U` — Sturm always has one in closed form). Emit
   `∧₁(V)·CX·∧₁(V†)·CX·∧₁(V)`, each inner `∧₁` recursing into rule 1 (phase
   included). Do NOT use the *approximate* eigenvalue-halving `V` of Lemma 7.8
   here — that is only for the asymptotic linear-approx path.

4. **k ≥ 3 → §7 ladders + Perm MCX replay.** `Ctrl^k{U2}` for `k≥3` uses the
   Lemma 7.5 shape (`∧₁(V)·MCX·∧₁(V†)·MCX·∧₁(V)`), where the multi-controlled
   `MCX = ∧_{k}(σ_x)` is a **`Perm` value** (a pure permutation, no phase) and
   is replayed through the Toffoli ladders of Lemmas 7.2/7.3/Corollary 7.4.
   The Perm MCX carries no `U2` phase, so it needs no `p(δ)` — the phase lives
   entirely in the `∧₁(V)` factors. **Ancilla wiring the kernel must honour:**
   - MCX / Perm replay and SU(2)-target multi-controls take a **borrowed
     (dirty) ancilla** — any register in scope, restored on exit
     (Cor 7.4, 7.10). Cheapest; no allocation of a fresh `|0⟩`.
   - a general phase-carrying `Ctrl^k{U2}` linear lowering needs a **clean
     `|0⟩` ancilla** returned to `|0⟩` (Cor 7.12). If none is available, the
     ancilla-free route is Θ(n²) (Cor 7.6). The kernel picks borrowed-vs-clean
     by whether the controlled value is a `Perm`/SU(2) target (borrowed) or a
     genuine `U2` with nonzero phase (clean).

5. **Counting / bounds (for cost models, one line each).** `∧₁(U)` ≤ 6 basic
   (Cor 5.3); `∧₂(U)` ≤ 16 basic (Cor 6.2); `∧_{n-2}(σ_x)` = `8(n−5)` Toffoli
   = `48n−204` basic, 1 borrowed bit (Cor 7.4); `∧_{n-1}(U)` = `48n²+O(n)`
   basic, no ancilla (Cor 7.6); lower bound `n−1` basic for any nonscalar
   `∧_{n-1}(U)` (Lemma 7.7); ε-approx in `Θ(n log 1/ε)` (Lemma 7.8). These set
   the M2 lowering's expected op counts for regression tests — a lowering that
   beats Lemma 7.7's `n−1` floor is a bug.
