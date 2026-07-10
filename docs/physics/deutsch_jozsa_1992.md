# Deutsch–Jozsa — one-query exact, in the phase-kickback formulation

**Primary local source (the one distilled here)**: R. Cleve, A. Ekert,
C. Macchiavello, M. Mosca, "Quantum Algorithms Revisited",
*Proc. R. Soc. Lond. A* **454**:339–354 (1998); **arXiv:quant-ph/9708016v1**
(8 Aug 1997). This is the cleanest modern derivation of Deutsch–Jozsa in the
**phase-kickback** language that Sturm's `b ⊻= oracle(f, x)` (with `b` in the
dual basis) realizes directly. Abbreviated **CEMM**.

**Local PDF**: `docs/physics/cleve_9708016.pdf` (18 pp.; fetched from
`https://arxiv.org/pdf/quant-ph/9708016`). **All equation and page numbers
below verified against this PDF.**

**Original reference (provenance, NOT the local PDF)**: D. Deutsch &
R. Jozsa, "Rapid solution of problems by quantum computation",
*Proc. R. Soc. Lond. A* **439**:553–558 (1992). The N-bit constant-vs-
balanced problem and its single-query quantum solution are due to this
paper; CEMM §3 (p. 6) attributes it explicitly ("subsequently generalised
by Deutsch and Jozsa (1992)") and *improves* it to a single f-controlled-NOT
(Deutsch–Jozsa's original used two). The Deutsch–Jozsa 1992 PDF is not held
locally; cite it only for provenance of the problem, and cite CEMM for every
equation.

**Status in pipeline**: ground-truth for the **DJ worked example, PRD-v2
§7.4** (milestone M7). The Sturm program is `b = minus(); b ⊻= oracle(f, x);
return Int(dual(x)) == 0`. Eqs (2.2)/(3.5)/(3.6) below ARE the physics of
that three-line program.

---

## The kickback kernel (Eqs 1.1–1.2, §1, pp. 2–3)

CEMM's unifying observation: every algorithm here is a Mach–Zehnder
interferometer where a controlled-U writes a phase onto the control.

- **Eq (1.1), p. 2** — Hadamard: `|0⟩ → (|0⟩+|1⟩)/√2`, `|1⟩ → (|0⟩−|1⟩)/√2`.
- **Eq (1.2), p. 3** — the interferometer as gates, with `U|u⟩ = e^{iφ}|u⟩`:
  ```
  |0⟩|u⟩ --H--> (1/√2)(|0⟩+|1⟩)|u⟩ --c-U--> (1/√2)(|0⟩ + e^{iφ}|1⟩)|u⟩
             --H--> (cos(φ/2)|0⟩ − i sin(φ/2)|1⟩) e^{iφ/2}|u⟩
  ```
- **The kickback statement (p. 3, after Eq 1.2), verbatim**: "the state of
  the auxiliary register |u⟩, being an eigenstate of U, is not altered along
  this network, but its eigenvalue **e^{iφ} is 'kicked back' in front of the
  |1⟩ component in the first qubit**. The sequence (1.2) … is the **kernel of
  quantum algorithms**." (Fig. 2: `U_f(x)|u⟩ = e^{iφ(x)}|u⟩`.)

This is why Sturm prepares `b = minus()` (`|−⟩ = (|0⟩−|1⟩)/√2`, the
`QBool(0.5, π)` literal of D1): `|−⟩` is the −1 eigenstate of the bit-flip
`|y⟩ → |y⊕f(x)⟩`, so the oracle's action turns into a phase on the `x`
register — kickback — leaving `b` unchanged (then silently traced, §3.9).

---

## Deutsch's problem, single bit (Eqs 2.1–2.5, §2, pp. 4–5)

The N=1 warm-up; the algebra that the N-bit case (§3) repeats verbatim.

- **Eq (2.1), p. 4** — the reversible oracle ("f-controlled-NOT"):
  `|x⟩|y⟩ → |x⟩|y ⊕ f(x)⟩`. CEMM notes (p. 4) this is the controlled-NOT of
  Barenco et al. 1995 "except that the second bit is negated when f(x)=1".
- **Eq (2.2), p. 5** — kickback with the `|−⟩` ancilla, for each x∈{0,1}:
  `|x⟩(|0⟩−|1⟩) → |x⟩(|0⊕f(x)⟩−|1⊕f(x)⟩) = (−1)^{f(x)} |x⟩(|0⟩−|1⟩)`.
  This is the exact identity Sturm's D9 ruling invokes ("feeding a |−⟩ … 
  initial target implements `target ⊕= f(x)` by linearity … which is exactly
  phase kickback", §9). **The load-bearing equation for `b ⊻= oracle(f, x)`.**
- **Eq (2.3), p. 5** — after the oracle:
  `((−1)^{f(0)}|0⟩ + (−1)^{f(1)}|1⟩)(|0⟩−|1⟩)`.
- **Eq (2.4)/(2.5), p. 5** — rewrite and apply the final H:
  `(−1)^{f(0)}|f(0)⊕f(1)⟩`. So the control qubit is `|0⟩` iff f is constant,
  `|1⟩` iff balanced — decided with certainty by one measurement, one query.

---

## The N-bit Deutsch–Jozsa (Eqs 3.1–3.6, §3, pp. 6–7)

Problem (p. 6): `f : {0,1}^n → {0,1}`, promised constant or **balanced**
(equal number of 0s and 1s); decide which. Classical worst case: `2^{n-1}+1`
evaluations. Quantum: **one** query (Fig. 4).

- **Eq (3.1), p. 6** — n-qubit Hadamard: `|x⟩ → Σ_{y∈{0,1}^n} (−1)^{x·y}|y⟩`.
- **Eq (3.2), p. 6** — the exponent is the **mod-2 inner product**
  `x·y = (x₁∧y₁) ⊕ ··· ⊕ (x_n∧y_n)`, and CEMM states the key structural
  fact, verbatim: "This is **equivalent to performing a one-qubit Hadamard
  transform on each of the n qubits individually**." → `H^{⊗n}` = the
  **per-wire** transform = the `(ℤ₂)^n` Fourier transform. (This is Sturm's
  per-wire `dual(x[i])`, and it is a *different unitary* from the register
  Fourier transform `F_{2^n}` of Eq (4.1) — the point §7.5/BV turns on;
  see the BV distillation.)
- **Eq (3.3), p. 6** — oracle: `|x⟩|y⟩ → |x⟩|y ⊕ f(x)⟩`.
- **Eq (3.4), p. 7** — after first `H^{⊗n}` on `|0…0⟩`, ancilla `|−⟩`:
  `Σ_x |x⟩(|0⟩−|1⟩)`.
- **Eq (3.5), p. 7** — after the oracle (kickback, Eq 2.2 applied per x):
  `Σ_x (−1)^{f(x)} |x⟩(|0⟩−|1⟩)`. **This is the state Sturm holds right after
  `b ⊻= oracle(f, x)` in §7.4** — the phase `(−1)^{f(x)}` on the `x` register.
- **Eq (3.6), p. 7** — after the final `H^{⊗n}`:
  `Σ_{x,y} (−1)^{f(x) ⊕ (x·y)} |y⟩(|0⟩−|1⟩)`.
- **The decision (p. 7, after Eq 3.6), verbatim**: "the amplitude of
  `|00…0⟩` is `Σ_x (−1)^{f(x)} / 2^n` so if f is constant then this state is
  `(−1)^{f(00…0)}|00…0⟩(|0⟩−|1⟩)`; whereas, if f is balanced then … the
  amplitude of `|00…0⟩` is zero. Therefore, by measuring the first n qubits,
  it can be determined with certainty whether f is constant or balanced."

This is precisely PRD-v2 §7.4's `return Int(dual(x)) == 0`: the all-zero
outcome has amplitude `(1/2^n) Σ_x (−1)^{f(x)} = ±1` (constant) or `0`
(balanced). §7.4's aside ("outcome 0 has amplitude (1/2^N)Σ_x(−1)^{f(x)} =
±1 / 0") is Eq (3.6)'s `|00…0⟩` coefficient, verbatim-consistent with the
paper.

---

## Relevance to Sturm v2 (§7.4)

The three-line §7.4 program maps one-to-one onto CEMM's derivation:

| §7.4 surface line | CEMM equation | what it does |
|---|---|---|
| `superpose!(x)` on `QInt{N}(0)` | Eq (3.1)/(3.4) | `H^{⊗n}` on `|0…0⟩` → `Σ_x|x⟩` |
| `b = minus()` (`QBool(0.5,π)` = `|−⟩`) | kickback setup, Eqs 1.2/2.2 | −1 eigenstate of the flip |
| `b ⊻= oracle(f, x)` | Eqs (2.2)→(3.5) | kickback: `Σ_x (−1)^{f(x)}|x⟩` |
| `Int(dual(x)) == 0` | Eq (3.6), `|0…0⟩` amp | final `H^{⊗n}`; all-zero ⇔ constant |

- **Why `|−⟩` and not fresh `|0⟩`.** Eq (2.2) needs the −1-eigenstate `|−⟩`
  as the oracle target; the D9 ruling verified that Bennett-compiled circuits
  are target-accumulating and never read the output wire as a control (see
  `bennett_1973_logical_reversibility.md`, copy stage), so `target ⊕= f(x)`
  holds for `|−⟩` by linearity → phase kickback. v0.1's fresh-`|0⟩` `oracle`
  convention was a caller choice, not a gate constraint (D9, §9).

- **Which `dual`.** §7.4 reads `Int(dual(x))` — the register-level dual — and
  it works *only because DJ interrogates outcome 0*: the k=0 row of the
  register Fourier transform `F_{2^N}` coincides with the uniform-average row
  of `H^{⊗N}` (Eq 3.1 at `y=0`: `Σ_x(−1)^{x·0}=Σ_x 1`). For any protocol that
  reads a **nonzero** outcome, the register dual `F_{2^N}` (Eq 4.1) and the
  per-wire dual `H^{⊗N}` (Eq 3.1/3.2) are inequivalent unitaries — that is
  exactly the D2 pitfall §7.5 (Bernstein–Vazirani) exists to demonstrate. See
  `docs/physics/bernstein_vazirani_1997.md`.

- **One query is the theorem.** Fig. 4 uses a single `U_f` (CEMM's one-query
  improvement over DJ 1992's two); Sturm's §7.4 has a single
  `b ⊻= oracle(f, x)`.
