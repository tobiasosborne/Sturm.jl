# Laneve (2025) — GQSP and Non-Linear Fourier Transform are equivalent

**Citation**: Laneve, A. *Generalized Quantum Signal Processing and Non-Linear
Fourier Transform are equivalent*. arXiv:2503.03026v2 (July 2025).

**Local PDF**: `docs/literature/quantum_simulation/qsp_qsvt/2503.03026.pdf`.

**Status in pipeline**: ⚠ CANONICAL for the *factorisation* step
`(P, Q) → phase factors`. Replaces Haah-19 root-finding, Dong-21
optimisation, Ying-22 Prony, and Motlagh-24 recursive formula for new
Sturm.jl QSVT work.

---

## What this paper proves (one-line)

GQSP **is** the Non-Linear Fourier Transform (NLFT) over SU(2). The
phase-factor inversion `(P, Q) → (λ, ϕ_j, θ_j)` is the inverse NLFT — a
classical problem with a **provably stable** algorithm (generalised
Riemann-Hilbert-Weiss / RHW, §4.3).

## The setup (Section 2)

A GQSP protocol on a single signal qubit with signal operator
`w̃ = diag(z, 1)` and processing operators `A_k ∈ SU(2)` is

```
e^{iλZ} · A_0 · w̃ · A_1 · w̃ · ··· · w̃ · A_n |0⟩  =  P(z)|0⟩ + Q(z)|1⟩      (1)
```

with `A_k = e^{iϕ_k X} · e^{iθ_k Z}` (full SU(2) parameterisation; standard
QSP fixes either `θ_k = 0` or `ϕ_k = 0`). The output polynomials satisfy
`|P|² + |Q|² ≡ 1` on 𝕋 (the unitarity constraint = Eq. (1.1) of BS-25).

**Theorem 2 (Laneve-25).** Every `(P, Q)` of degree n with `|P|² + |Q|² ≡ 1`
on 𝕋 is realisable by a GQSP protocol of degree n. The phase factors live in
`λ, ϕ_k, θ_k ∈ [-π/2, π/2)`.

This is essentially Motlagh-Wiebe GQSP rewritten in SU(2) form — the
equivalence to other QSP variants (analytic, Laurent, Chebyshev/reflection,
QSVT) is summarised in Figure 1 (page 5) and proved in §2.1.

## §2.1 — The QSP zoo: analytic ↔ Laurent ↔ Chebyshev ↔ reflection

This is the **conversion chain that connects every QSP variant**. Critical for
QSVT implementations because the NLFT inverse (§3, §4) computes phases for the
*analytic* QSP signal `w̃ = diag(z, 1)`, while the QSVT block-encoding theorem
(GSLW Theorem 17) uses the *reflection* signal
`r̃ = [[x, √(1−x²)]; [√(1−x²), −x]]`.

### Step 1 — Analytic ↔ Laurent (Lemma 1, p.4)

Same processing operators `A_k`. If analytic-QSP with phases `φ_k` and signal
`w̃ = diag(z, 1)` gives `(P, Q)`, then Laurent-QSP with the **same phases**
and signal `ṽ = diag(z, z⁻¹)` gives

```
(P', Q') = (z⁻ⁿ P(z²), z⁻ⁿ Q(z²))
```

i.e. the analytic polynomial pair, with `z → z²` and overall `z⁻ⁿ` shift.

### Step 2 — Laurent (X-constrained) ↔ Chebyshev (Z-constrained, H sandwich) (p.5)

Using `x̃ = HṽH` and `e^{iφX} = H e^{iφZ} H`, the **same phase values** give:

```
e^{iφ_0 X} ṽ e^{iφ_1 X} ⋯ ṽ e^{iφ_n X}
  = H · [e^{iφ_0 Z} x̃ e^{iφ_1 Z} ⋯ x̃ e^{iφ_n Z}] · H
```

The matrix output of the Chebyshev body **alone** (without the H sandwich) is
the same `[[P', Q']; [−Q'*, P'*]]` as the X-Laurent body. The H sandwich
applies the **Hadamard transformation** to the matrix:

```
P'' = (P' + P'*)/2 + (Q' − Q'*)/2
Q'' = (P' − P'*)/2 − (Q' + Q'*)/2
```

so the H-sandwiched Chebyshev body produces

```
[[P''(x),  iQ''(x)√(1−x²)];
 [−iQ''*(x)√(1−x²),  P''*(x)]]
```

with `P''(x) = Σ 2 p'_k T_k(x)` and `iQ''(x)√(1−x²) = Σ 2i q'_k U_{k−1}(x)√(1−x²)`.
This is the **Chebyshev-form polynomial in x = (z + z⁻¹)/2**.

### Step 3 — Chebyshev ↔ Reflection (p.6, the key identity)

```
r̃ = −i · e^{−iπ/4 Z} · x̃ · e^{−iπ/4 Z}
```

Equivalently `x̃ = i · e^{iπ/4 Z} · r̃ · e^{iπ/4 Z}`. Substituting into the
Chebyshev body and merging adjacent Z-rotations:

```
e^{iφ_0 Z} x̃ e^{iφ_1 Z} ⋯ x̃ e^{iφ_n Z}
  = iⁿ · e^{i(φ_0 + π/4) Z} · r̃ · e^{i(φ_1 + π/2) Z} · r̃ · ⋯ · r̃ · e^{i(φ_n + π/4) Z}
```

So the **reflection-QSP phases** `ψ_k` in terms of the Chebyshev-QSP phases `φ_k`:

```
ψ_0     = φ_0 + π/4
ψ_k     = φ_k + π/2     for 1 ≤ k ≤ n−1
ψ_n     = φ_n + π/4
+ global phase iⁿ
```

### Putting it together — the analytic→reflection conversion

For X-constrained analytic-QSP phases `φ_k` (from Laneve NLFT inverse on a real
Chebyshev target `S(x)`):

1. **Same phase values** map analytic ↔ Laurent ↔ Z-Chebyshev (steps 1, 2).
2. **Phase shift** maps Z-Chebyshev → reflection (step 3 above).

But the *output polynomial* changes between Z-Chebyshev (no H sandwich) and the
H-sandwiched form. The QSVT theorem (GSLW Thm 17) places the H sandwich
implicitly through the SVD of the block-encoded operator — the |0⟩^m-projection
extracts `P^{(SV)}(A/α)` directly from the singular values, which is the
Hadamard-transformed (P'', Q'') polynomial of the X-Laurent body, not the raw
(P', Q'). This is **the subtle mistake easy to make** in implementations that
assume "ship analytic-QSP phases unchanged to the reflection circuit".

**Bug Sturm.jl-4ceh**: a partial implementation that applies only the §4.3
Q→P swap (`phi[end] += π/2`) to the analytic phases and ships them to the
reflection-QSVT circuit produces an *attenuated* operator: experimentally
`M = c·S(H/α)` with `|c| < 1` whenever the block encoding's PREPARE produces
non-trivial off-diagonal coupling on the ancilla register. The `+π/4`/`+π/2`
phase shifts above are necessary; they may not be sufficient. See
`worklog/sessions-83-to-88.md` and the `5lu4` RED test for the diagnostic
amplitude-level probe.

## NLFT (Section 3)

The Non-Linear Fourier Transform takes a sequence `F = (F_k)_{k∈ℤ} ∈ ℓ²(ℤ)`
and produces a pair of functions `(a, b) : 𝕋 → ℂ` via the infinite product

```
∏_{k∈ℤ}  (1/√(1+|F_k|²)) · [ 1     F_k z^k ]                                 (3.1)
                            [ -F̄_k z^{-k}   1   ]
```

(matrix factors are SU(2) up to scaling). The pair `(a, b)` satisfies
`|a|² + |b|² = 1` on 𝕋 — the same unitarity constraint as `(P, Q)`.

**The key bridge (Theorem 5)**: with the substitution

```
   F_k = i tan(ϕ_k)  ·  e^{i·(prefix-sum of θ's and λ)},
```

the NLFT `(a, b)` *equals* `(P, Q)` produced by the GQSP protocol with phase
factors `(λ, ϕ_k, θ_k)`.

So the inverse NLFT — given `(a, b)` recover `F` — IS the QSP
phase-finding problem, in disguise.

## The Riemann-Hilbert-Weiss (RHW) algorithm (Section 4.3)

Inverse NLFT classically; **provably stable** even in the fully-coherent
regime `||P||_∞ ≈ 1` where Motlagh-24 / optimisation methods fail.

### Statement

Given `(P, Q)` of degree n with `|P|² + |Q|² ≡ 1` on 𝕋, RHW computes the
GQSP phase factors `(λ, (ϕ_k, θ_k)_{k=0..n})` to target accuracy ε.

### Outline of the algorithm (§4.3)

1. **Weiss step** — solve a Riemann-Hilbert problem to extract the phase
   factors one at a time, working from index `k = n` down to `k = 0`. Each
   step amounts to evaluating a contour integral / Cauchy projection on `𝕋`.
2. **Half-Cholesky** (Ni-Ying 24, arXiv:2410.06409) accelerates step 1 to
   `O(n² + (n/η) log(1/ε))` time, where `η` measures the separation from
   `||P||_∞ = 1`.
3. **O(n log² n) follow-on** (Ni–Sarkar–Ying–Lin 25, arXiv:2505.12615).

### Stability guarantee (Theorem 8)

RHW returns phase factors `(λ̃, ϕ̃_k, θ̃_k)` such that the resulting
GQSP polynomial `(P̃, Q̃)` satisfies

```
||P̃ - P||_∞,𝕋 + ||Q̃ - Q||_∞,𝕋 ≤ C(n) · ε                                   (Thm. 8)
```

with `C(n)` polynomial in `n` (no dependence on the gap to the boundary).
This is the property that fails for Motlagh-24 / Dong-21 optimisation —
their error blows up as `||P||_∞ → 1`.

## Implementation notes for Sturm.jl

* `src/qsvt/phase_factors.jl::weiss(b, η, ε)` — implements the Weiss step
  (single-pass RHW iteration).
* `src/qsvt/phase_factors.jl::rhw_factorize(b, η, ε)` — full inverse NLFT
  pipeline. Currently O(n³) for the naïve loop; bead `Sturm.jl-d0co` tracks
  the upgrade to Levinson-Durbin / Half-Cholesky for `O(n log² n)`.
* `src/qsvt/phase_factors.jl::extract_phases(F)` — `F → (λ, ϕ, θ)` final
  conversion using Theorem 5's substitution.

## Where Sturm.jl uses this

* `src/qsvt/phase_factors.jl::extract_phases` — Theorem 5 substitution.
* `src/qsvt/phase_factors.jl::rhw_factorize` — RHW algorithm (§4.3).
* `src/qsvt/circuit.jl::qsvt_protocol!` — Theorem 9 (GQSP protocol on signal
  qubit). The Ry/Rz decomposition lives in `src/qsvt/conventions.jl`.
* `src/qsvt/circuit.jl::qsvt_combined_reflect!` — Corollary of Theorem 9 for
  the reflection variant on a block-encoded operator (also references
  GSLW-19 / arXiv:1806.01838 Theorem 56).

## §4.3 — Switching the polynomials (Q→P swap)

Independent of the §2.1 chain. The NLFT computes phases for `(a, b)` where the
target is `b`; QSP convention puts the target in the **left** position `P` of
`(P, Q)`. The fix (p.11): **multiply the protocol on the right by `iX`**, which
transposes to a phase shift on the last processing operator:

```
e^{iφ_n X} e^{iθ_n Z} · iX = e^{i(φ_n + π/2) X} e^{−iθ_n Z}
```

So `φ_n ← φ_n + π/2`, `θ_n ← −θ_n` puts the target polynomial in the P
position. For real Chebyshev input (where `θ_k ≡ 0`), this reduces to just
`φ_n += π/2`. **Sturm has this correctly** (`src/qsvt/circuit.jl::qsvt_phases`
step 5).

## Page / equation index

| Citation in Sturm code | Where in paper |
|---|---|
| "Laneve-25 Theorem 2 / GQSP" | §2, p. 4, Eq. (2) |
| "Laneve-25 §2.1 / QSP zoo" | §2.1, p. 4–6 (Lemma 1, x̃ vs r̃, conversion identity) |
| "Laneve-25 Theorem 5 / NLFT bridge" | §3, p. 7 |
| "Laneve-25 §4.3 / Q→P swap" | §4.3, p. 11 |
| "Laneve-25 Algorithm 1 / Weiss" | Algorithm 1, p. 12 |
| "Laneve-25 Algorithm 2 / RHW" | Algorithm 2, p. 13 |
| "Laneve-25 Theorem 9 / GQSP protocol" | §4.1, p. 9, Eq. (4) |

## What this paper does NOT solve

**The completion step `P → Q`.** That is BS-25's job; see
`docs/physics/berntson_sunderhauf_2025_complementary_polynomials.md`.
The two papers compose to give the full canonical pipeline:

```
target P ──BS-25──► Q ──Laneve-25──► (λ, ϕ_k, θ_k) ──Sturm.jl GQSP──► circuit
```
