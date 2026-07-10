# Bernstein–Vazirani — one-query secret recovery, per-wire duals

**Primary local source (the one distilled here)**: R. Cleve, A. Ekert,
C. Macchiavello, M. Mosca, "Quantum Algorithms Revisited",
*Proc. R. Soc. Lond. A* **454**:339–354 (1998);
**arXiv:quant-ph/9708016v1** (8 Aug 1997) — abbreviated **CEMM**. CEMM §3
(pp. 7–8) derives the Bernstein–Vazirani (BV) algorithm as a variant of
Deutsch–Jozsa on the *same* network (Fig. 4), in the phase-kickback
language Sturm uses. **Shares the PDF with the DJ distillation.**

**Local PDF**: `docs/physics/cleve_9708016.pdf` (18 pp.; from
`https://arxiv.org/pdf/quant-ph/9708016`). **All equation and page numbers
below verified against this PDF.**

**Original reference (provenance, NOT the local PDF)**: E. Bernstein &
U. Vazirani, "Quantum Complexity Theory", *SIAM J. Comput.* **26**(5):
1411–1473 (1997); preliminary version STOC 1993. CEMM attributes the
problem to "Ethan Bernstein and Umesh Vazirani (1993)" (p. 7) and notes
(p. 7) that BV's own algorithm "employs **two** f-controlled-NOT operations
instead of one" — CEMM gives the one-query version. The BV 1997 SIAM paper
is not held locally; cite it only for provenance, cite CEMM for equations.

**Status in pipeline**: ground-truth for the **BV worked example, PRD-v2
§7.5** (milestone M7) — and, crucially, for §7.5's role as the **D2 negative
control**: BV is the protocol whose *nonzero* outcomes make the register
dual and the per-wire duals inequivalent, so the §7.4 `Int(dual(x))` idiom
would give the WRONG answer. The correct readout is per-wire:
`bits = [Bool(dual(x[i])) for i in 1:N]`.

---

## The problem and the one-query solution (Eqs 3.7–3.9, §3, pp. 7–8)

Secret string `s ∈ {0,1}^n` (CEMM writes it `a`), possibly a secret bit `b`.

- **Eq (3.7), p. 7** — the promised form:
  `f(x) = (a₁∧x₁) ⊕ ··· ⊕ (a_n∧x_n) ⊕ b = (a·x) ⊕ b`,
  the mod-2 inner product with the secret `a` (= Sturm's `s`), plus a bit.
  Classical recovery needs "at least n f-controlled-NOT operations (since a
  contains n bits of information and each classical evaluation of f yields a
  single bit)". Quantum: **one** query (Fig. 4, same network as DJ).
- **Eq (3.8), p. 7** — the post-oracle state (Eq 3.5 specialized to Eq 3.7):
  `Σ_x (−1)^{(a·x) ⊕ b} |x⟩(|0⟩−|1⟩)`. This is the **BV phase state**: a
  per-wire product of `(−1)^{a_i x_i}` phases. It is the state Sturm holds
  after `b ⊻= oracle(f, x)` in §7.5.
- **Eq (3.9), p. 7** — after the final `H^{⊗n}`:
  `(−1)^b Σ_{x,y} (−1)^{x·(a⊕y)} |y⟩(|0⟩−|1⟩)`, "which is equivalent to
  `(−1)^b |a⟩(|0⟩−|1⟩)`. Thus, **a measurement of the control register yields
  the value of a**." (The overall sign `(−1)^b` is unobservable.)

The clean collapse `Σ_x (−1)^{x·(a⊕y)} = 2^n δ_{y,a}` is exactly the
`(ℤ₂)^n` Fourier / **per-wire Hadamard** orthogonality (Eq 3.1/3.2). Each
output qubit `y_i` is read in the conjugate basis (a per-wire `H`), and the
`n` results ARE the bits of `a`. → Sturm's
`[Bool(dual(x[i])) for i in 1:N]`, `Bool(dual(·))` being the per-wire
conjugate-basis (X-basis) measurement.

CEMM also gives (p. 8) the multi-output generalization (Eqs 3.10–3.11) —
recover a full matrix `A` from `f(x)=(A·x)⊕b` in `m` queries — not needed
for §7.5 but the same per-wire-Hadamard mechanism.

---

## Why the register dual does NOT recover s (§7.5's D2 negative control)

PRD-v2 §7.5 warns: reusing §7.4's `Int(dual(x))` (the **register** dual)
here is "the canonical D2 bug", and states that for N=3, s=5 its outcome
distribution is `{1: 0.073, 3: 0.427, 5: 0.427, 7: 0.073}` — "spread and
tied". Here is the precise grounding.

**Two different unitaries.** The BV phase state (Eq 3.8, dropping the `b`
sign) is `|ψ⟩ = 2^{-n/2} Σ_x (−1)^{s·x} |x⟩`, where `s·x = Σ_i s_i x_i`
(mod 2) — a product of **real** `±1` characters of the group `(ℤ₂)^n`.

- The **per-wire dual** applies `H^{⊗n}` (Eqs 3.1/3.2), whose kernel is
  `(−1)^{x·y}` — the *same* real `(ℤ₂)^n` characters. Orthogonality gives
  `H^{⊗n}|ψ⟩ = |s⟩` exactly (Eq 3.9). ✔ recovers s with probability 1.
- The **register dual** `Int(dual(x))` applies the Fourier transform over
  `ℤ_{2^n}` — the QFT `F_{2^n}` of CEMM Eq (4.1), p. 8:
  `|a⟩ → 2^{-n/2} Σ_y e^{2πi a y / 2^n} |y⟩`. Its kernel is a **complex**
  root-of-unity `e^{2πi xy/2^n}`, NOT `(−1)^{x·y}`. These characters belong
  to the cyclic group `ℤ_{2^n}`, a *different* group from `(ℤ₂)^n`, so
  `F_{2^n}` is a provably different unitary from `H^{⊗n}` for `n ≥ 2` (they
  agree only for `n=1`). Applying `F_{2^n}` to the `(ℤ₂)^n`-character state
  `|ψ⟩` gives a Gauss-sum-like superposition, not a basis state.

**Amplitude computation (verified numerically, N=3, s=5).**
`|ψ⟩ = 2^{-3/2} Σ_{x=0}^{7} (−1)^{s·x}|x⟩` with `s=5=(101)₂`, so
`s·x = parity(x AND 5)`. Then:
- Per-wire `H^{⊗3}`: outcome `5` with probability `1.000` (all others 0). ✔
- Register `F_{2^3}` (and its inverse `F†`, identical here by symmetry):
  probabilities `{1: 0.073, 3: 0.427, 5: 0.427, 7: 0.073}` — **exactly the
  PRD-v2 §7.5 distribution**. Spread over four odd outcomes, and 3 ties 5,
  so even the mode does not single out `s`.

(Reproduced with a direct `numpy` computation of `|⟨k|F|ψ⟩|²`; the PRD's
numbers are verbatim-correct. The four nonzero outcomes are all odd because
`s=5` is odd, i.e. `s·x` has odd-parity structure that the cyclic transform
maps onto the odd cosets.)

So the register dual reads the BV phase state through the *wrong Fourier
transform*: it is not a bug of measurement but of choosing `F_{2^n}` where
the physics needs `H^{⊗n}`. §7.4's `Int(dual(x))` happened to work there
**only** because DJ reads outcome 0, where the `k=0` rows of `F_{2^n}` and
`H^{⊗n}` coincide (both are the uniform-sum row); BV reads a generic nonzero
`s`, where they diverge. This is the operational content of decision **D2**
(register dual vs per-wire duals) and why §7.5 is a *required* counter-
example, not a copy-paste of §7.4.

---

## Relevance to Sturm v2 (§7.5)

| §7.5 surface line | CEMM equation | what it does |
|---|---|---|
| `superpose!(x)` on `QInt{N}(0)` | Eq (3.1) | `H^{⊗n}` on `|0…0⟩` |
| `b = minus()` (`|−⟩`) | kickback setup | −1 eigenstate of the flip |
| `b ⊻= oracle(f, x)` | Eq (3.8) | `Σ_x (−1)^{s·x}|x⟩` (BV phase state) |
| `[Bool(dual(x[i])) for i in 1:N]` | Eq (3.9) | **per-wire** `H`; each qubit → bit of s |
| `evalpoly(2, bits)` | — | reassemble `s`, LSB-first |

- **`Bool(dual(x[i]))` is the per-wire conjugate-basis read** (X-basis /
  per-wire `H`), which Eq (3.9) proves recovers `s_i` exactly. `Int(dual(x))`
  (register dual, the §7.4 idiom) would apply `F_{2^n}` and spread the
  amplitude as computed above — the D2 bug. The two `dual`s are addressing
  modes onto different Fourier structures (PRD-v2 §3.3, D2/D11); the type
  system keeps them distinct.

- **One query is the theorem.** CEMM's Fig. 4 uses a single `U_f`; Sturm's
  §7.5 has a single `b ⊻= oracle(f, x)`. (CEMM's one-query version improves
  on BV 1993's two-query original — a provenance note, not a physics change.)

- **The kickback and clean-ancilla facts are shared with DJ**; see
  `docs/physics/deutsch_jozsa_1992.md` (Eqs 1.2/2.2 kickback) and
  `docs/physics/bennett_1973_logical_reversibility.md` (compute–copy–
  uncompute, why the compiled `Perm` is target-accumulating).
