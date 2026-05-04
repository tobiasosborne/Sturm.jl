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
QSVT) is summarised in Figure 1 (page 5) and proved in §2.1–§2.4.

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

## Page / equation index

| Citation in Sturm code | Where in paper |
|---|---|
| "Laneve-25 Theorem 2 / GQSP" | §2, p. 4, Eq. (2) |
| "Laneve-25 Theorem 5 / NLFT bridge" | §3, p. 7 |
| "Laneve-25 §4.3 / RHW algorithm" | §4.3 |
| "Laneve-25 Theorem 8 / RHW stability" | §4.3, end |
| "Laneve-25 Theorem 9 / GQSP protocol" | §2, p. 4, Eq. (1) (the matrix product) |

## What this paper does NOT solve

**The completion step `P → Q`.** That is BS-25's job; see
`docs/physics/berntson_sunderhauf_2025_complementary_polynomials.md`.
The two papers compose to give the full canonical pipeline:

```
target P ──BS-25──► Q ──Laneve-25──► (λ, ϕ_k, θ_k) ──Sturm.jl GQSP──► circuit
```
