<!--
SPDX-License-Identifier: AGPL-3.0-only
Copyright (C) 2026 Tobias Osborne
Part of Sturm.jl.
-->

# Shor order finding — phase sampling, continued-fraction recovery, LCM

**Citation**: P. W. Shor, "Polynomial-Time Algorithms for Prime
Factorization and Discrete Logarithms on a Quantum Computer",
*SIAM J. Comput.* **26**(5):1484–1509 (1997); preliminary version FOCS
1994. **arXiv:quant-ph/9508027v3** ("Factoring with a Quantum Computer",
the expanded 1996 preprint that became the SICOMP paper).

**Local PDF**: `docs/physics/shor_1995_factoring.pdf` (28 pp.; from
`https://arxiv.org/pdf/quant-ph/9508027`). **All equation and page numbers
below verified against this PDF** (its printed page numbers, header
"FACTORING WITH A QUANTUM COMPUTER" / "P. W. SHOR", match the locators).

**Status in pipeline**: ground-truth source for **M9 §7.7 `shor_order`**
(`docs/design/m9-addq-inplace-perm-design.md` §4). It grounds: the
phase-sample structure (§4.2), the exact continued-fraction candidate step
(§4.3, design eqs 5/6), the divisor-denominator issue and LCM/`powermod`
protocol (§4.4), and the **N ≥ 1000 statistical threshold** of test
`M9.SHOR.END-TO-END-STATISTICAL` (§9.6) via the per-sample success bound.
Docstrings on `shor_order`, `_shor_phase_sample`, and the CF/LCM
post-processing cite THIS file (CLAUDE.md principle 4/5), never the design
doc or an unlocated textbook.

---

## Notation map (Shor → Sturm/design)

Shor's letters differ from the M9 design's; the map is exact:

| Shor 1995 | Sturm / M9 design | meaning |
|---|---|---|
| `n` | `N` | the modulus / number being factored |
| `x` | `a` (= `a₀`) | the base element whose order is sought |
| `r` | `r` | the order: least `r ≥ 1` with `a^r ≡ 1 (mod N)` |
| `q = 2^l` | `Q = 2^{2W}` | the QFT modulus, a power of two |
| `c` | `z` (`= BigInt(dual(k))`) | the measured phase sample |
| `d` | `s` | the (unknown) numerator, `c/q ≈ d/r` |
| `A_q` | `F_{2^{2W}}` (register dual) | the quantum Fourier transform, Eq (4.1) |

Sturm sizes the phase register at `2W` wires, so `Q = 2^{2W} ≥ N²`
(`W = ⌈log₂N⌉` ⇒ `2^{2W} ≥ (N-1)² · 4 ≥ N²`), meeting Shor's `n² ≤ q < 2n²`
requirement (p. 16); the design's `2W` schedule closes F21.

---

## What this paper does (one line)

Factoring reduces (classically, by randomization) to **order finding**;
order finding is done by preparing a uniform phase register, computing
`a^k mod N` into a work register, applying the QFT `A_q`, measuring, and
recovering `r` from the sampled `c` by a **continued-fraction** expansion of
`c/q`. M9 ships the order-finding half; the factoring reduction is stated
only for the precondition/caveat grounding (§ below).

---

## The QFT, Eq (4.1), §4 p. 13

`A_q` sends `|a⟩` to `(1/q^{1/2}) Σ_{c=0}^{q-1} exp(2πi a c / q) |c⟩`
(p. 13, Eq (4.1)) — the `(a,c)` entry is `q^{-1/2} exp(2πi a c/q)`. This is
the **register dual** `F_{2^{2W}}` = `Int/BigInt(dual(k))` in Sturm (the
cyclic-group Fourier transform, distinct from per-wire `H^{⊗n}`; see
`docs/physics/bernstein_vazirani_1997.md` for why the two must not be
confused). NB (p. 14): the direct network output is the **bit-reversal** of
`c`; Sturm's kernel dual handles the ordering, but this is the standard
reversed-bit gotcha.

## The order-finding state, Eqs (5.1)–(5.4), §5 pp. 16–17

Pick `q = 2^l` with `n² ≤ q < 2n²` (p. 16). Then:

- **Eq (5.1), p. 16**: uniform phase register
  `(1/q^{1/2}) Σ_{a=0}^{q-1} |a⟩|0⟩` — Sturm's `superpose!(k)`.
- **Eq (5.2), p. 16**: compute `x^a mod n` reversibly (§3, keeping `a`):
  `(1/q^{1/2}) Σ_{a=0}^{q-1} |a⟩|x^a (mod n)⟩` — Sturm's controlled
  `mulmod!` ladder, `y` accumulating `a₀^k mod N`.
- **Eq (5.3)/(5.4), pp. 16–17**: apply `A_q` to the first register:
  `(1/q) Σ_{a,c} exp(2πi a c/q) |c⟩|x^a (mod n)⟩`.
- Observe. The probability of the state `|c, x^k (mod n)⟩` (Eq (5.5), p. 17;
  `0 ≤ k < r`) sums the amplitudes over all `a ≡ k (mod r)`; writing
  `a = br + k` (Eq (5.6)) and reducing `rc` to `{rc}_q ∈ (−q/2, q/2]`
  (Eq (5.7)) gives a geometric sum peaked wherever `{rc}_q` is small.

**Phase-sample structure (the grounding for design §4.2).** The peaks sit
"near an integer multiple of `q/r`" (p. 19), i.e. `c ≈ (d/r)·q` with `d`
ranging (roughly uniformly) over `0,…,r-1`. In Sturm's letters:
`z ≈ (s/r)·Q`, `s` uniform over `0..r-1`. The `d = 0` peak (i.e. `c = 0`) is
the design's uninformative `z = 0` sample.

## Continued-fraction recovery, Eqs (5.11)–(5.13), pp. 18–19

The per-outcome probability is `≥ 1/3r²` exactly when `{rc}_q ∈ [−r/2, r/2]`
(p. 18):

- **Eq (5.11), p. 18**: `−r/2 ≤ {rc}_q ≤ r/2`.
- **Eq (5.12), p. 18**: equivalently `∃ d: −r/2 ≤ rc − dq ≤ r/2`.
- **Eq (5.13), p. 18** (divide (5.12) by `rq`):
  **`|c/q − d/r| ≤ 1/2q`.**

This is the **exact source bound**. In Sturm's letters it reads
`|z/Q − s/r| ≤ 1/2Q`. The design's §4.3 eq (5) uses the *weaker* integer
form `2N²·|z·q − p·Q| ≤ Q·q` i.e. `|z/Q − p/q| ≤ 1/2N²` — valid because
`Q ≥ N²` (`(p,q)` there = `(d,r)` here). Either bound is below `1/2r²`
since `r < N ≤ √Q`, so:

**Continued-fraction theorem (uniqueness / recovery).** Shor: "Because
`q > n²`, there is at most one fraction `d/r` with `r < n` that satisfies
[Eq (5.13)] … obtain `d/r` in lowest terms by rounding `c/q` to the nearest
fraction having denominator smaller than `n` … found in polynomial time
using a continued fraction expansion of `c/q`" (pp. 18–19). Shor cites the
"all best approximations" property of continued fractions as
[Hardy and Wright 1979, **Chapter X**; Knuth 1981] (p. 19).

- The classical statement is **Hardy & Wright, *An Introduction to the
  Theory of Numbers*, Theorem 184**: if `|ξ − p/q| < 1/(2q²)` with
  `gcd(p,q)=1`, then `p/q` is a convergent of the simple continued fraction
  of `ξ`. Here `|c/q − d/r| ≤ 1/2q < 1/2r²` (since `r² < n² ≤ q`), so `d/r`
  **is** a convergent of `c/q`; Sturm enumerates convergents and keeps the
  largest denominator `< N` satisfying the bound.
  *(Provenance: the "Theorem 184" number is the standard Hardy & Wright
  numbering; Shor's own local citation is "Chapter X". The Hardy & Wright
  volume is NOT held in `docs/physics/`; the locally-verified anchor is Shor
  Eq (5.13) + the Chapter X reference on p. 19.)*

## Why a single denominator is only a DIVISOR CANDIDATE of `r`

Recovering `r` from `d/r` works **only "if `d` happens to be relatively
prime to `r`"** (p. 19). In general the convergent `d/r` returned *in lowest
terms* has denominator

  `q_reduced = r / gcd(d, r)`     (Sturm design eq (6): `q = r/gcd(s,r)`),

a **proper divisor** of `r` when `gcd(d,r) > 1`; and the `d = 0`
(`c = 0`, `s = 0`) sample gives denominator `1`. Hence a single sample's
denominator is only a divisor candidate — NOT the order. This is exactly why
Sturm's driver must (§4.4): accumulate `L ← lcm(L, q_reduced)`, verify
`a₀^L ≡ 1 (mod N)` by `powermod` (passing proves the true order *divides*
`L`), and prime-strip-minimize. Shor's own remedies (p. 19): "if two
candidate `r`'s have been found, say `r₁` and `r₂`, test the least common
multiple of `r₁` and `r₂` as a candidate `r` [Knill 1995]" — the LCM step —
plus trying small multiples `2r', 3r', …` and neighbours `c ± 1, c ± 2`.

## Success-probability lower bound per sample (grounds the N ≥ 1000 threshold)

- Per useful outcome, probability `≥ 1/3r²` (p. 18: `|` integral `(5.10)|`
  is minimized at `2/(πr)`, so the probability `≥ 4/(π²r²) ≥ 1/3r²` for
  large `n`).
- There are `r` residues `k` and, among the `d` coprime to `r`, `φ(r)`
  useful numerators, giving `r·φ(r)` good states `|c, x^k⟩`; each with
  probability `≥ 1/3r²`, so **one run yields `r` with probability
  `≥ φ(r)/3r`** (p. 19).
- **`φ(r)/r > δ/log log r`** for a constant `δ` [Hardy & Wright 1979,
  **Theorem 328**] (cited p. 19), so a single run succeeds with probability
  `≥ δ/(3 log log r)`; **"repeating this experiment only `O(log log r)`
  times, we are assured of a high probability of success"** (p. 19).
  With the LCM-of-two-candidates refinement [Knill 1995], the expected
  number of trials drops to a **constant** (p. 19).

**Ground for the M9 test threshold (§9.6).** The per-driver-run success is a
bounded-below constant (each internal phase sample is useful with
probability `≥ φ(r)/3r`, and `max_samples` internal samples with LCM
accumulation compound geometrically toward 1). This is why `shor_order` can
be held to a one-sided 99% binomial lower bound `≥ 0.95` over `≥ 1000`
seeded trials without post-hoc tuning: the number is derived from
`φ(r)/3r` + `φ(r)/r > δ/log log r` + the LCM refinement, not chosen to fit.
For the tested `(N,a,r) = (15,2,4)` and `(21,2,6)`, `φ(4)/4 = 1/2` and
`φ(6)/6 = 1/3`, both comfortably above the level needed for constant-few
internal samples to clear 0.95.

## Factoring reduction — precondition and caveats (M9 ships order finding only)

The reduction is stated for grounding `NonCoprimeBaseError` and the
even-order caveat; the factoring wrapper itself is out of M9 scope.

- **Coprimality precondition (p. 15).** "choose a random `x (mod n)`, find
  its order `r`, and compute `gcd(x^{r/2} − 1, n)`." A random `x` with
  `gcd(x, n) ≠ 1` is not a group element — Euclid returns the factor
  directly (Sturm's `NonCoprimeBaseError(a, N, g)`, the caller "has already
  found a factor").
- **Even-order / `a^{r/2} ≡ −1` caveat (pp. 15–16).** Since
  `(x^{r/2}−1)(x^{r/2}+1) = x^r − 1 ≡ 0 (mod n)`, the `gcd` "fails to be a
  non-trivial divisor of `n` only if `r` is odd or if `x^{r/2} ≡ −1
  (mod n)`" (p. 16). The procedure yields a factor with probability
  **`≥ 1 − 1/2^{k−1}`**, `k` = number of distinct odd prime factors of `n`
  (p. 16, via the Chinese remainder theorem [Knuth 1981; Hardy & Wright
  1979, Theorem 121]). `n` must be odd and not a prime power.

## Order finding is generic in `f` (grounds `mulmod!` as the oracle)

Final paragraph, p. 19, verbatim in force: "if we have a permutation `f`
mapping the set `{0,1,2,…,n−1}` into itself such that its `k`th iterate
`f^{(k)}(a)` is computable in time polynomial in `log n` and `log k`, the
same algorithm will be able to find the order of an element `a` under `f`,
i.e., the minimum `r` such that `f^{(r)}(a) = a`." Sturm's `mulmod!`
(multiply-by-`a₀^{2^j} mod N`, a full-space `Perm`, design §2) is exactly
such an efficiently-iterable permutation; the phase-estimation order-finder
applies unchanged.

---

## Relevance to Sturm v2 (M9 §4, §9)

| M9 design line | Shor locator | what it grounds |
|---|---|---|
| `superpose!(k)`, `Q = big(1)<<(2W)` | Eq (5.1), p. 16; `n²≤q<2n²`, p. 16 | uniform phase register, QFT modulus `≥ N²` |
| controlled `mulmod!` ladder | Eq (5.2), p. 16 | `y = a₀^k mod N` reversibly, `a₀` coprime |
| `BigInt(dual(k))` | Eqs (4.1) p.13, (5.3) p.16 | register-dual QFT `A_q`, sample `z = c` |
| `z ≈ (s/r)·Q`, `s` uniform `0..r-1` | p. 19 ("near a multiple of `q/r`") | phase-sample structure |
| CF convergents `p/q`, `q < N`; eq (5) | Eq (5.13) p.18; HW Thm 184; p.19 | `d/r` is a convergent, unique for `q > n²` |
| design eq (6): `q = r/gcd(s,r)` | p. 19 ("if `d` relatively prime to `r`") | denominator is a divisor candidate |
| `lcm` accumulation + `powermod` verify | p. 19 (Knill 1995 LCM); | true order divides `L`; verify then minimize |
| `max_samples`, ≥1000-trial ≥0.95 test | p. 18 (`1/3r²`), p. 19 (`φ(r)/3r`, Thm 328) | per-sample success bound → threshold |
| `NonCoprimeBaseError(a,N,g)` | p. 15 (`gcd(x^{r/2}−1,n)` reduction) | non-unit base is already a factor |
| `a₀ == 1 ⇒ return 1` guard (Δ7) | order defn, p. 15 | order-1 case (all `z=0`), not a failure |
