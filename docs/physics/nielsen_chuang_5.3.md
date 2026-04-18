# Nielsen & Chuang §5.3 — Order-finding and factoring

Source: Nielsen & Chuang, *Quantum Computation and Quantum Information*,
Cambridge University Press, 2000. Book pages 226–235 (djvu pages 254–263 in
`docs/physics/Nielsen and Chuang 2000.djvu`). Equation numbers are quoted
verbatim from the book. Use this note as the Rule‑4 anchor for every
Shor-related function in `src/library/shor.jl`; cite the specific equation.

Supplementary: Beauregard, *Circuit for Shor's algorithm using 2n+3 qubits*,
arXiv:quant‑ph/0205095 (2003) — `docs/physics/beauregard_2003_2n3_shor.pdf`.
Used only for the minimum-width compilation; the baseline algorithm below is
strictly N&C.

## §5.3.1 Order-finding

For positive integers `x < N` with `gcd(x, N) = 1`, the *order* of `x`
modulo `N` is the least positive integer `r` with `xʳ ≡ 1 (mod N)`.
Order-finding is believed classically hard in `L = ⌈log₂ N⌉`.

### The unitary (Eq. 5.36)

```
U |y⟩ = |xy mod N⟩          with U = I on |y⟩ for N ≤ y ≤ 2^L − 1.
```

`U` is unitary because `x` is coprime to `N` and therefore has an inverse
mod `N` (Exercise 5.12).

### Eigenstates (Eqs. 5.37–5.39)

For each integer `0 ≤ s ≤ r−1`,

```
|u_s⟩ = (1/√r) Σ_{k=0}^{r−1} exp(−2πi s k / r) |xᵏ mod N⟩
```

is an eigenstate of `U` with eigenvalue `exp(2πi s / r)`:

```
U |u_s⟩ = exp(2πi s / r) |u_s⟩.
```

So running phase estimation on `U` with `|u_s⟩` as eigenstate returns an
integer estimate of `s/r`. Applying the continued-fractions algorithm to
the measured phase extracts `r`.

### The |1⟩ trick (Eq. 5.44)

Preparing `|u_s⟩` directly requires knowing `r`. Fortunately,

```
(1/√r) Σ_{s=0}^{r−1} |u_s⟩ = |1⟩                                  (5.44)
```

so **initialising the second register to `|1⟩` is an equal superposition
of all `r` eigenstates**. Phase estimation then samples `s` uniformly in
`{0, 1, …, r−1}`.

### Modular exponentiation (Box 5.2, Eqs. 5.40–5.43)

The controlled-`U^{2^j}` sequence used by phase estimation computes

```
|z⟩|y⟩  ↦  |z⟩ U^{z_{t−1} 2^{t−1}} … U^{z_0 2^0} |y⟩
       =  |z⟩ |x^{z_{t−1} 2^{t−1}} · … · x^{z_0} · y  mod N⟩      (5.41)
       =  |z⟩ |xᶻ y mod N⟩.                                       (5.42)
```

That is, **the full sequence of controlled-`U^{2^j}` operations is just
modular exponentiation of `x` raised to the contents of the counting
register**. Box 5.2 notes this can be computed reversibly in `O(L³)`
gates. Exercise 5.14 shows the same state is produced if we instead use
a unitary `V` that computes

```
V |j⟩|k⟩ = |j⟩|k + xʲ mod N⟩                                      (5.47)
```

and start the second register at `|0⟩`.

### Precision (Fig. 5.4)

To resolve `s/r` with probability ≥ `(1−ε)/r` we need `t` counting
qubits with

```
t = 2L + 1 + ⌈log₂(2 + 1/(2ε))⌉.
```

For the canonical factoring-15 example `L = 4`, `t = 11` in N&C's Box
5.4 (ε ≤ ¼). Sturm's textbook factoring-15 circuit can use `t = 2L = 8`
for good success probability per shot and repeat to amplify.

### The continued-fractions step (Box 5.3, Theorem 5.1)

Given the measured integer `ỹ ∈ {0, 1, …, 2ᵗ−1}`, set `φ = ỹ / 2ᵗ`.
If `|s/r − φ| ≤ 1/(2r²)` (Eq. 5.48) — guaranteed when `t = 2L+1` — then
`s/r` appears as a convergent of the continued-fraction expansion of `φ`
(Theorem 5.1). Computed in `O(L³)` operations.

### Order-finding algorithm (summary, page 232)

```
Inputs:  A black box U_{x,N} with |j⟩|k⟩ ↦ |j⟩|xʲ k mod N⟩;
         t counting qubits initialised to |0⟩; L qubits initialised to |1⟩.
Output:  the least r ≥ 1 with xʳ ≡ 1 (mod N).
Runtime: O(L³), success probability Θ(1).

Procedure
  1. |0⟩|1⟩                                            initial
  2. (1/√2ᵗ) Σⱼ |j⟩|1⟩                                  Hadamards on reg1
  3. (1/√2ᵗ) Σⱼ |j⟩|xʲ mod N⟩                          modular exp
  4. ≈ (1/√r) Σ_s |˜s/r⟩|u_s⟩                          FT† on reg1
  5.    ↦ ỹ                                             measure reg1
  6.    ↦ r                                             continued fractions
```

## §5.3.2 Factoring reduction

Factoring reduces to order-finding via two classical number-theory facts.

### Theorem 5.2 (non-trivial root of unity ⇒ factor)

Suppose `N` is composite, `1 < x < N`, `x² ≡ 1 (mod N)`, and
`x ≢ ±1 (mod N)`. Then at least one of `gcd(x−1, N)` and `gcd(x+1, N)`
is a non-trivial factor of `N`, found in `O(L³)` classical operations.

### Theorem 5.3 (random `y` gives a useful `x`)

For odd composite `N = p₁^{α₁} … p_m^{α_m}` and `y` uniform in
`{1, …, N−1}` with `gcd(y, N) = 1`, let `r` be the order of `y mod N`.
Then

```
P(r is even AND y^{r/2} ≢ −1 mod N) ≥ 1 − 1/2^{m−1}.               (5.60)
```

For `m ≥ 2` (`N` not a prime power), this is ≥ ½.

### Reduction of factoring to order-finding (summary, pages 233–234)

```
Inputs:  a composite N.
Output:  a non-trivial factor of N.
Runtime: O((log N)³), success probability Θ(1).

Procedure
  1. If N even, return 2.
  2. If N = a^b for integers a > 1, b ≥ 2, return a (Exercise 5.17).
  3. Pick x uniformly in {1, …, N−1}. If gcd(x, N) > 1, return gcd(x, N).
  4. Compute the order r of x mod N via order-finding.
  5. If r is even AND x^{r/2} ≢ −1 mod N,
       return whichever of gcd(x^{r/2} ± 1, N) is a non-trivial factor.
     Otherwise the algorithm fails (retry from step 3).
```

Exercise 5.19 establishes that **N = 15 is the smallest composite where
step 4 is actually required** — everything below is either even or a
perfect prime power.

## Box 5.4 — Factoring 15 (the canonical worked example)

Take `x = 7`, `N = 15`. `gcd(7, 15) = 1` so we enter order-finding.
Book uses `t = 11` (ε ≤ ¼). After step 3 the state is

```
(1/√2ᵗ) Σ_k |k⟩|7ᵏ mod 15⟩
 = (1/√2ᵗ) [ |0⟩|1⟩ + |1⟩|7⟩ + |2⟩|4⟩ + |3⟩|13⟩
           + |4⟩|1⟩ + |5⟩|7⟩ + |6⟩|4⟩ + … ].                       (5.62)
```

Measuring register 2 collapses it to one of `{1, 7, 4, 13}`. Say we see
`4`; register 1 then sits on `(1/√N') [|2⟩ + |6⟩ + |10⟩ + |14⟩ + …]`
(the coset `k ≡ 2 (mod 4)`). After `FT†` on register 1, the distribution
peaks at multiples of `2^t / r = 2^t / 4`. For `t = 11` the outcomes
are `{0, 512, 1024, 1536}`, each with probability ≈ ¼.

Say we read `ỹ = 1536`. Then
`φ = 1536 / 2048 = 3 / 4`, and `3/4` appears as a convergent of `φ`, so
`r = 4`. Even, and `7^{r/2} mod 15 = 49 mod 15 = 4 ≢ −1 (mod 15)`, so
`gcd(4 − 1, 15) = 3` and `gcd(4 + 1, 15) = 5`. **15 = 3 × 5.**

## The seven coprime bases for N = 15

Every `a ∈ {2, 4, 7, 8, 11, 13, 14}` is coprime to 15 (the non-coprime
residues being `{0, 3, 5, 6, 9, 10, 12}`). Their orders and Shor
outcomes:

| `a` | `r` | `a^{r/2} mod 15` | ±1 mod 15? | `gcd(a^{r/2}−1, 15)`, `gcd(a^{r/2}+1, 15)` | Result |
|-----|-----|------------------|------------|---------------------------------------------|--------|
| 2   | 4   | 4                | neither    | 3, 5                                        | ✓ 15 = 3·5 |
| 4   | 2   | 4                | neither    | 3, 5                                        | ✓ |
| 7   | 4   | 4                | neither    | 3, 5                                        | ✓ (Box 5.4) |
| 8   | 4   | 4                | neither    | 3, 5                                        | ✓ |
| 11  | 2   | 11               | neither    | 5, 3                                        | ✓ |
| 13  | 4   | 4                | neither    | 3, 5                                        | ✓ |
| 14  | 2   | 14               | **−1**     | —                                           | **fails** Theorem 5.3 |

So **six of the seven bases factor 15 on success**; `a = 14` is the
Theorem 5.3 failure case (`a^{r/2} ≡ −1 mod N`) and must be rejected
classically. This is the full test matrix for the implementations.

## What Sturm.jl will build on top of

- `superpose!` / `interfere!` — forward / inverse QFT on `QInt{W}`
  (`src/library/patterns.jl:25`, `:64`). Maps directly to the
  `Hᵗ` + `FT†` columns in the Box 5.4 circuit.
- `phase_estimate(U!, |ψ⟩, Val(P))` — already auto-controls `U!` via the
  `when()` stack (`src/library/patterns.jl:136`). Operates on a `QBool`
  eigenstate; order-finding wants a multi-qubit eigenstate, so each
  implementation will either extend `phase_estimate` or inline the
  phase-estimation loop.
- `oracle(f, x::QInt{W})` — compiles a plain Julia function (e.g.
  `k -> powermod(a, k, N)`) via Bennett.jl into a reversible circuit
  (`src/bennett/bridge.jl:204`). Auto-controlled inside `when()`.
- `Base.Int(q::QInt{W})` — the P2 measurement cast
  (`src/types/qint.jl:108`). Classical post-processing (gcd, continued
  fractions) uses Julia stdlib `gcd`, `invmod`, and a handwritten
  convergent-finder since Sturm carries no `continued_fraction` helper.

## Consequences for the three implementations

Each Sturm.jl implementation of Shor's order-finding differs in **which
of the three N&C structures it lifts most directly**:

- **(A) Value-oracle / Exercise 5.14.** Lift `powermod(a, ·, N)` with
  `oracle(f, k)` and XOR the result into a fresh register, then `FT†` on
  the counting register — matches Eq. 5.47 / Exercise 5.14 with the `|0⟩`
  initial state.

- **(B) Phase-estimation higher-order / §5.3.1 verbatim.** Build a
  controlled "multiply by `a` mod `N`" subroutine `U!` and call
  `phase_estimate(U!, |1⟩_L, Val(t))` — matches Eqs. 5.36–5.44 directly
  with the `|1⟩` initial state.

- **(C) Controlled-`U^{2^j}` cascade / Box 5.2 literal.** Precompute
  `a_j = a^{2^j} mod N` classically; for each counting qubit `j`, apply
  `when(k[j]) do; y ← a_j · y mod N; end` on the register `y` — explicit
  Eq. 5.41 expansion, `t − 1` squarings done at compile time, no
  controlled-squaring circuit at runtime.

All three decode the measurement with the same continued-fractions step
and classical post-processing (Eq. 5.48, Theorem 5.1–5.3). The
benchmark compares qubit count, gate count, Toffoli count, and depth
across (A), (B), (C) on the same 7-base `N = 15` test matrix.
