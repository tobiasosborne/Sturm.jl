# Berntson & Sünderhauf (2025) — Complementary Polynomials in QSP

**Citation**: Berntson, B.K. & Sünderhauf, C. *Complementary Polynomials in
Quantum Signal Processing*, Commun. Math. Phys. **406**:161 (2025).
DOI: 10.1007/s00220-025-05302-9. arXiv:2406.04246v2 (13 Jun 2025).

**Local PDF**: `docs/literature/quantum_simulation/qsp_qsvt/2406.04246.pdf`.

**Status in pipeline**: ⚠ CANONICAL for the *completion* step `P → Q`.
Replaces root-finding (Haah-19), Prony (Ying-22), and optimisation (Motlagh-24);
those are deprecated for new Sturm.jl QSVT work.

---

## What problem this paper solves

In QSP / GQSP one wants to implement a polynomial `P ∈ ℂ[z]`, deg P = d, with
`|P(z)| ≤ 1` on the unit circle 𝕋. Theorem 1 (a restatement of Motlagh-Wiebe
GQSP) says such a `P` is realisable by a depth-d signal-processing circuit
**iff** there exists a *complementary polynomial* `Q ∈ ℂ[z]`, deg Q = d, with

```
|P(z)|² + |Q(z)|² = 1     for all z ∈ 𝕋.                       (1.1)
```

Given `(P, Q)`, the GQSP phase factors `(λ, ϕ_j, θ_j)` follow from an exact
iterative method (Motlagh-24 Alg. 1, or — the better choice — Laneve-25 NLFT
inverse). **The bottleneck is constructing `Q` from `P`.** Existing approaches
(root-finding, Prony, optimisation) are heuristic and have no rigorous error
analysis.

## The contour-integral representation (Theorem 2)

Let `P(z) = Σ_{n=0}^d p_n z^n` with `p_0 ≠ 0` (WLOG, since |z^n P(z)| = |P(z)|
on 𝕋). Let `{(t_j, 2α_j)}_{j=1..d_0}` be the roots of `1 - |P(z)|²` on 𝕋
together with their (necessarily even) multiplicities. Then a *canonical*
complementary polynomial `Q` is given by

```
Q(z) = Q_0(z) · exp[ S(z) ]                                    (1.4)
```

where

* `Q_0(z) = Π_{j=1..d_0} (z - t_j)^{α_j} · z^{(d - Σ α_j)}` encodes the on-circle
  roots of `1 - |P|²` (each with half their multiplicity, ensuring `|Q_0|² · |...|`
  vanishes correctly), and
* `S(z)` is a Schwarz-type integral

```
S(z) = (1/4π) ∮_𝕋 (z'+z)/(z'-z) · log( (1-|P(z')|²) / |Q_0(z')|² ) dz'/z'
```

picking out the analytic continuation of `½ log(1-|P|²/|Q_0|²)` on `𝔻`.

The integral is over the unit circle and converges as long as `1 - |P(z)|²`
has no on-circle zeros of odd multiplicity (which is forbidden by Theorem 1).

## Algorithm 1: known-δ FFT method (the one Sturm.jl uses)

Assume `||P||_{∞,𝕋} ≤ 1 - δ` for known `δ > 0` (so `1 - |P|² ≥ δ²` everywhere
on 𝕋, which means `Q_0 = z^d` and the log is bounded).

```
Input  : monomial coefficients p_0..p_d ∈ ℂ, threshold δ, target error ε.
Output : monomial coefficients q_0..q_d of canonical Q.

Choose N = O((d/δ) · log(d / (δε)))   # FFT length, even
1. Sample P on N-th roots of unity:    p̂_k = P(ω^k),  ω = exp(2πi/N).
2. Form r_k = log(1 - |p̂_k|²)            (real, well-defined since 1-|P|² ≥ δ²).
3. FFT r_k → r̃_n.
4. Apply the Schwarz multiplier Π:
       r̃_n ← { r̃_n        n > 0
              { r̃_n / 2    n = 0
              { 0           n < 0     }    (projection onto positive frequencies + ½ at zero)
5. IFFT r̃_n → s_k = S(ω^k).
6. Form q̂_k = exp(s_k) · ω^{kd}.        # multiplication by Q_0(z) = z^d on 𝕋
7. FFT q̂_k → q_n     and truncate to degrees 0..d.
```

Total cost: **O(N log N)** with N as above.

### Error bound (Theorem 3)

Algorithm 1 returns `Q̃` with

```
||Q̃ - Q||_∞,𝕋 ≤ ε
```

provided N grows as stated. The bound is *explicit and dimension-free* in `ε`,
unlike all prior approaches.

### Implementation notes for Sturm.jl

* Sturm.jl's existing `complementary_polynomial(cheb_coeffs; ...)` in
  `src/qsvt/phase_factors.jl` (line 109) is the implementation of this algorithm.
  The `MAX_BS_SAMPLES = 2²⁰` const there is the cap on N.
* The `δ` parameter ("eta" / `η` in the Sturm code) is the user-specified
  separation from the boundary `||P||_∞ = 1`; smaller δ = more samples = slower.
* For polynomials produced by Chebyshev approximation of analytic functions on
  `[-1, 1]`, δ is typically `1 - max|P|` measured directly from the coefficients.

## Algorithm 2 (unknown-δ adaptive)

If δ is unknown, BS-25 §3.2 gives an adaptive variant that probes `||P||_∞`
via repeated FFTs and grows N until the error bound is met. Sturm.jl currently
uses Algorithm 1 only (caller supplies `eta`); Algorithm 2 is a follow-on if a
caller arises that genuinely cannot bound δ.

## What this paper does NOT solve

**The factorisation step `(P, Q) → (λ, ϕ_j, θ_j)`.** That is the job of
Laneve-25 (NLFT inverse / generalised Riemann-Hilbert-Weiss); see
`docs/physics/laneve_2025_gqsp_nlft.md`.

## Where Sturm.jl uses this

* `src/qsvt/phase_factors.jl::complementary_polynomial` — Algorithm 1.
* `src/qsvt/phase_factors.jl::rhw_factorize` — feeds the Q from this algorithm
  into the Laneve-25 RHW step.
* `src/qsvt/phase_factors.jl::extract_phases` — final `(P,Q) → phases` extraction.

## Page / equation index

| Citation in Sturm code | Where in paper |
|---|---|
| "BS-25 Theorem 1 / GQSP statement" | p. 1, Eq. (1.1)–(1.2) |
| "BS-25 Theorem 2 / contour-integral" | p. 2, Eq. (1.4) |
| "BS-25 Algorithm 1" | §2.1, p. 5 |
| "BS-25 Theorem 3 / error bound" | §2.2 |
| "BS-25 Algorithm 2 / adaptive" | §3.2 |
