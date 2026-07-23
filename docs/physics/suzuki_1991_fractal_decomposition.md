# Suzuki 1991 — General Theory of Fractal Path Integrals

**Source (local):** `docs/physics/suzuki_1991_fractal_decomposition.pdf` — M.
Suzuki, *General theory of fractal path integrals with applications to
many-body theories and statistical physics*, J. Math. Phys. 32 (2), 400–407
(February 1991). SCANNED PDF, no `.tex` — read page-by-page with the Read
tool; all equation numbers below are transcribed directly off the scan
(pp. 400–403).

## What Sturm uses it for

`evolve!` (`src/library/evolve.jl`) ships first- and second-order Trotter
today (`docs/physics/childs_2019_trotter_error.md`). This paper is the
CITATION for the planned Suzuki-2k coefficients — the recursive
"triple-jump" construction that builds an order-`2m` product formula out of
five copies of the order-`(2m−2)` formula, at three distinct (and, past
order 2, sometimes NEGATIVE) sub-step sizes. `evolve!`'s higher-order
Trotter strategy (M11+) should compute its sub-step multipliers directly
from Eq. (3.16)'s `p_m`, not a hand-tuned table.

## The general fractal-decomposition ansatz (Eq. 1.1 / 1.2, p. 400)

    f_m(A,B) = e^{t₁A} e^{t₂B} e^{t₃A} e^{t₄B} ⋯ e^{t_M A}              (1.1)

a finite product of exponentials of `A` and `B` alone (real or complex
`{t_j}`, finite `M`), such that

    exp[x(A+B)] = f_m(A,B) + O(x^{m+1})                                (1.2)

for small `x` — i.e. `f_m` agrees with the true exponential to order `m`.
Abstract (p. 400, verbatim): "A general scheme of fractal decomposition of
exponential operators is presented in any order `m` … A general recursive
scheme of construction of `{t_j}` is given explicitly. It is proven that
some of `{t_j}` should be negative for `m ≥ 3` and for any finite `M`
(nonexistence theorem of positive decomposition)."

## Theorem 1 — construction theorem (§II, p. 400–401, Eqs. 2.1–2.3)

For `exp(x Σ_{j=1}^q A_j)`, given the `(m−1)`th approximant, the `m`th
approximant is built as

    exp(x Σ_j A_j) = Q_{m-1}(x) + O(x^m)                               (2.1)
    Q_m(x) = Π_{j=1}^r Q_{m-1}(p_{m,j} x),   r ≥ 2                      (2.2)

where `{p_{m,j}}` solve the decomposition condition

    Σ_{j=1}^r p_{m,j}^m = 0,   with   Σ_{j=1}^r p_{m,j} = 1.            (2.3)

This is the load-bearing recursion: raising the order by composing
rescaled copies of the lower-order approximant, matched by killing the
leading-order error term (Eq. 2.3's two conditions come from requiring both
the `x^m (Σp_{m,j} A_j)^m` term and the corresponding cross-term sum in
each factor to vanish — see the proof at Eqs. 2.4–2.8).

## Theorem 2 — symmetry theorem (Eqs. 2.9–2.16, p. 401)

If `F(x)F(−x) = 1`, `F(0) = 1` (a "symmetric" operator family), and
`G_{2m-1}(x)` is its symmetric `(2m−1)`th approximant (`F(x) = G_{2m-1}(x) +
O(x^{2m})`, `G_{2m-1}(x)G_{2m-1}(−x) = 1`), then `G_{2m-1}(x)` is ALSO
correct to order `x^{2m}`:

    G_{2m-1}(x) = G_{2m}(x).                                           (2.13)

This is why the recursion below can jump the labeled order by 3
(`S*_{2m}` built from `S*_{2m-3}`) rather than by 2: the odd `(2m−3)`th
symmetric approximant already equals the even `(2m−2)`th one.

## The order-`2m` real symmetric decomposition — Eqs. (3.13)–(3.16), p. 402

For `F(x) = exp[x(A_1 + A_2 + ⋯ + A_q)]`, the SYMMETRIC real decomposition
(`|t_j| < 1` throughout — the "practical" scheme, unlike the earlier `k_m >
1` scheme of Eqs. 3.11–3.12 which the paper explicitly says "is not
practical for large `m`"):

    F(x) = S*_{2m}(x) + O(x^{2m+1})                                    (3.13)

Recursion:

    S*_{2m}(x) = S*_{2m-1}(x)
               = [S*_{2m-3}(p_m x)]² S*_{2m-3}((1−4p_m)x) [S*_{2m-3}(p_m x)]²   (3.14)

with base case the first- (or, by Thm. 2, second-) order symmetrized
decomposition

    S₁*(x) = S(x) ≡ e^{(x/2)A_1} e^{(x/2)A_2} ⋯ e^{(x/2)A_q} e^{xA_q} ⋯ e^{(x/2)A_2} e^{(x/2)A_1}   (3.15)

and `p_m` the REAL solution of

    4 p_m^{2m-1} + (1 − 4p_m)^{2m-1} = 0,   i.e.,   p_m = (4 − 4^{1/(2m-1)})^{-1}.   (3.16)

**This is the exact "Suzuki-2k" coefficient** — confirmed at Eqs.
(3.14)–(3.16) exactly as the task brief anticipated. Each recursion step
uses THREE distinct sub-step multipliers per level: `p_m` (used four times,
as the two squared bracket factors) and `1 − 4p_m` (used once, the middle
factor) — five copies of the previous-order formula total per level, at
three distinct rescaled step sizes.

Immediate consequences the paper draws (Eqs. 3.17–3.19, p. 402):

    1/2 < p_m < 2/3   and   |1 − 4p_m| < 2/3,   for all m ≥ 2           (3.17)
    lim_{m→∞} t_j = 0   for all j                                       (3.19)

— i.e. EVERY individual sub-step size shrinks to zero as the order `m →
∞`, which the paper identifies as the origin of the "fractal" name: "each
separation of the present decomposition becomes infinitesimally small for
`m → ∞`, and its structure is asymptotically fractal" (p. 402, citing
refs. 8,9), illustrated in the paper's Fig. 1.

**Numeric values (Fig. 1 caption, p. 402):** for `m = 2`, `p_2 =
0.414 490 771 794 375 7…`; for `m = 3`, `p_3 = 0.373 065 827 733 272 8…` —
both independently reproduced by evaluating Eq. (3.16) directly
(`p_2 = (4 − 4^{1/3})⁻¹ ≈ 0.41449`, `p_3 = (4 − 4^{1/5})⁻¹ ≈ 0.37307`),
confirming Eq. (3.16) is read correctly here. (The scan's Fig. 1 caption
itself labels the second value "`p_1`" rather than "`p_3`" — almost
certainly a typo/OCR artifact in the 1991 print, since the value matches
`p_3` from (3.16) and not any natural reading of `p_1`; flagged below, do
not propagate the "`p_1`" label into code.)

## Stage-count growth

The paper does not give a single closed-form `M(m)` in the main text, but
the recursive structure of Eq. (3.14) makes the growth explicit: each step
from order `2(m−1)` to order `2m` replaces every factor of the previous
formula with FIVE rescaled copies (the `[·]² · (·) · [·]²` pattern). Fig. 1
gives the paper's own worked stage counts for `q = 2` (`H = A + B`): the
order-4 formula `S*_4(x)` uses 11 stages (`t_1, …, t_11`, some equal by the
formula's own symmetry, e.g. `t_1 = t_11 = p_2/2`), and the order-6 formula
`S*_6(x)` uses up to 51 stages (`t_1, …, t_51`) — consistent with
(pre-merge) 5× growth per recursion level, reduced by merging adjacent
same-operator exponentials at block boundaries (`e^{(x/2)A}·e^{(x/2)A} →
e^{xA}`), which is why 11 (not 15) and ~51 (not 75) are the reported counts.

## Theorem 3 — nonexistence of positive decomposition (§V, p. 403, Eq. 5.1)

> **Theorem 3 (nonexistence theorem of positive decomposition):** There
> exists no decomposition of the form
>
>     e^{x(A+B)} = e^{t_1 A} e^{t_2 B} e^{t_3 A} e^{t_4 B} ⋯ e^{t_M A} + O(x^{m+1})     (5.1)
>
> with all `t_j` positive and finite `M` for `m ≥ 3` and for
> noncommutable operators `A` and `B`.

Corollary (Eq. 5.2): the same holds for `exp(x Σ_{j=1}^q A_j) =
e^{t_{i1}A_1} e^{t_{i2}A_2} ⋯ e^{t_{iq}A_q} + O(x^{m+1})` for `m ≥ 3` and
finite products, `q ≥ 2`. Proved by reducing to `m = 3` and showing the two
necessary sum-rule conditions on the coefficients (Eqs. 5.5–5.6, derived
via the time-ordering sum-rule method of §VI) admit no simultaneous
positive real solution once the maximum of a bounded quadratic form
`f({s_j})` (Eqs. 5.13–5.17) is shown to stay below the threshold `4/3`
required for a real solution to exist (`R < 1/√3` in Eq. 5.13's distance
condition) — i.e. it's not merely "no decomposition has been found," it's
proved impossible for ANY finite `M`.

**Practical consequence for implementers (this is the gotcha):** any
order-`≥3` symmetric product formula — including every `S*_{2m}` for `m ≥
2` from Eq. (3.14), since `1 − 4p_m < 0` whenever `p_m > 1/4`, which holds
for every `m ≥ 2` per (3.17) — MUST include at least one NEGATIVE
sub-step. A Trotter/Suzuki implementation that evolves every substep
forward in (simulated) time is not just suboptimal, it is provably
impossible past second order. `evolve!`'s higher-order strategy must accept
signed `t/r` substeps.

## Used by Sturm for

- **Suzuki-2k coefficients in `evolve!`'s Trotter strategy** (M11+): the
  `p_m` of Eq. (3.16) and the five-fold recursive substep pattern of Eq.
  (3.14) are the exact source of the sub-step multipliers for any
  higher-than-second-order deterministic Trotter strategy `evolve!` adds —
  computed from the formula, not hard-coded per order.
- Together with `docs/physics/zlokapa_2026_hamsim_lower_bounds.md`'s
  Appendix-A Fact HW (`Υ = 2·5^{p-1}` stage count, `α_comm(·, 2p)` at
  order `2p`), this paper is the primitive `evolve!`/`Auto`-dispatch and
  bench suite cite for the deterministic (Trotter) half of the composite
  qDRIFT split — Zlokapa et al.'s `p` IS this paper's `m`.
- Theorem 3 is the grounding citation (Principle 3/9) for why `evolve!`'s
  higher-order code path must allow negative Trotter substeps — a test
  asserting "all Suzuki-2k substeps are positive" would be asserting
  something this paper proves is impossible for order ≥ 3.

## Discrepancy check

The task brief's expectation matches the scan closely, with one thing to
flag loudly: the brief said "the recursive fractal decomposition (Eq. 1.1
and the order-2k recursion with the `p_k = (4 − 4^{1/(2k-1)})^{-1}`
coefficient — verify the exact equation numbers from the scan, likely Eqs.
(3.14)-(3.16))" — CONFIRMED exactly: Eq. (3.14) is the recursion, Eq.
(3.15) the base case, Eq. (3.16) the `p_m` formula, letter-for-letter
matching `(4 − 4^{1/(2m-1)})^{-1}` (paper uses index `m`, not `k`; harmless
renaming). The one genuine anomaly is internal to the paper itself, not a
mismatch with the brief: Fig. 1's caption labels its second numeric
constant `p_1 = 0.373 065 827 733 272 8…`, but this value equals `p_3` when
Eq. (3.16) is evaluated at `m = 3` (and does NOT match any sensible value
of a would-be `p_1`, e.g. `m=1` gives division by `4^0=1` types of
degenerate cases) — almost certainly a `p_3`→`p_1` typo/OCR slip in the
original 1991 print. Do not copy the "`p_1`" label into Sturm's coefficient
table; use `p_m` from Eq. (3.16) directly.

## Files copied

- `docs/physics/suzuki_1991_fractal_decomposition.pdf` (copied from
  `docs/literature/suzuki_1991_JMP32_400.pdf`)
