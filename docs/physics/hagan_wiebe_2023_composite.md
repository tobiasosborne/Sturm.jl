# Hagan–Wiebe 2023 — Composite Quantum Simulations

**Source (local):** `docs/physics/hagan_wiebe_2023_composite.pdf` — M. Hagan,
N. Wiebe, *Composite Quantum Simulations* (arXiv:2206.06409). LaTeX source at
`docs/literature/2206.06409_src/main.tex` (all equation/theorem numbers below
are this source's own `\label`s, cross-checked against the compiled section
numbering: §1 Introduction, §2 Main Results, §3 Preliminaries, §4 First-Order
Trotter with QDrift, §5 Higher-Order Trotter Formulas, §6 General Composite
Channels, §7 Discussion). Depends on: Childs–Su–Tran–Wiebe–Zhu, *Theory of
Trotter Error* (`childs2021theory` in the bib — `docs/physics/childs_2019_trotter_error.md`,
the commutator-scaling Trotter bound this paper cites for `C_Trott`); Campbell,
*Random Compiler for Fast Hamiltonian Simulation* (`qdrift` in the bib — the
original QDrift channel, Def. 2.4/Thm. `thm:QDrift` below restate it).

## What Sturm uses this for

This is the **centerpiece paper for the Composite (Trotter+qDrift) simulation
mode** that `evolve!` will grow into (M11+, beyond the pure-Trotter M10
baseline documented in `childs_2019_trotter_error.md`). The paper gives: how
to split `H` into a Trotter part and a qDrift part (head/tail partition), the
exact one-step channel to implement once split, a diamond-norm cost bound
(Theorem 2.1) to size `r` and `N_B`, and two concrete partitioning schemes
(deterministic coefficient-threshold, probabilistic). Sturm's Composite
`evolve!` variant follows the operational construction in §(b) below
literally — this is not a paraphrase, it is the recipe the implementation
must match term-for-term.

## Setup and notation (§3, Preliminaries)

`H = Σ_{i=1}^{L} h_i H_i`, each `H_i` Hermitian with `‖H_i‖ = 1`, `h_i ≥ 0`
(WLOG — absorb any phase into `H_i`), `λ := Σ_i h_i` (total spectral weight).
`U(t) := e^{iHt}`, channel `𝒰(t)(ρ) := U(t) ρ U(t)†`. (Sign convention note:
the paper writes `e^{+iHt}`, not `e^{-iHt}` — a bookkeeping choice, physically
inert since only `‖·‖` and `‖·‖_⋄` of differences appear in every bound.)

A **partition** is `H = A + B`, `A = Σ_i a_i A_i` (the Trotter part), `B = Σ_j
b_j B_j` (the qDrift part) — just a relabeling of a subset of the `h_i, H_i`
into `a`'s/`A`'s vs `b`'s/`B`'s. `λ_A := Σ a_i`, `λ_B := Σ b_j`, `L_A := |A|`
(number of Trotter terms), `L_B := |B| = L - L_A`.

`α_comm(H, 2k)` (Eq. `def:alpha_comm`, following Childs et al.'s
`α̃_comm`), the nested-commutator sum that drives Trotter error:

    α_comm(H, 2k) := Σ_{γ_i ∈ {1,…,L}} (Π h_{γ_i}) ‖[H_{γ_{2k+1}}, [H_{γ_{2k}}, …[H_{γ_2}, H_{γ_1}]…]]‖_∞      (def:alpha_comm)

and its restriction to a partition splits additively:

    α_comm({A,B}, 2k) = α_comm(H, 2k) − α_comm(A, 2k) − α_comm(B, 2k)          (line 249)

— `α_comm({A,B}, 2k)` is exactly the *cross* commutator structure: every
nested commutator using at least one term from each of `A` and `B`.

**QDrift channel** (Def. `def:qdrift_channel`, restating Campbell): with
`p_i = h_i/λ`,

    𝒰_QD(t) : ρ ↦ Σ_i p_i e^{i H_i λt} ρ e^{−i H_i λt}                        (QD)

i.e. sample term `i` with probability proportional to its spectral weight,
evolve for a *fixed* duration `λt` regardless of which term was drawn (the
`λ` rescaling is what makes `𝔼[generator] = H/λ · λ = H` to leading order).
Theorem `thm:QDrift`: `N = 4λ²t²/ε` qDrift samples suffice for
`‖𝒰(t) − 𝒰_QD(t/N)^{∘N}‖_⋄ < ε` (for `ε ∈ (0, λt ln2/2)`), so
`C_QD(H,t,ε) ≤ 4λ²t²/ε` operator exponentials.

**Trotter-Suzuki channel** (Def. `def:TS`): `U_TS^{(1)}(t) := Π_{i=1}^{L}
e^{ih_iH_it}` (first order), `U_TS^{(2)}(t) := (Π_{i=L}^{1} e^{ih_iH_it/2})
(Π_{i=1}^{L} e^{ih_iH_it/2})` (second order/Strang), and recursively for
`2k`-th order:

    U_TS^{(2k)}(t) := U_TS^{(2k-2)}(u_k t)² · U_TS^{(2k-2)}((1−4u_k)t) · U_TS^{(2k-2)}(u_k t)²      (recursion)

`u_k := 1/(4 − 4^{1/(2k−1)})`. `Υ := 2·5^{k−1}` is the **number of stages**
(the count of first-order-formula evaluations one `2k`-th order step expands
into via this recursion — Υ=1 for k=0... in practice Υ=2 for k=1 second
order, Υ=10 for k=2 fourth order, etc.). Theorem `thm:trotter_cost`:
`C_Trott(H,t,ε,2k) = ΥLr ≤ ΥL⌈(Υt)^{1+1/2k}/ε^{1/2k} · (4α_comm(H,2k)/(2k+1))^{1/2k}⌉`.

## (a) The head/tail partition: deterministic vs randomized term sets

The whole paper is organized around **one structural choice**: every term
`h_iH_i` of `H` is assigned to exactly one of two disjoint sets,

- **`A` (the Trotter/deterministic set — the "head")**: terms simulated by a
  fixed, deterministic `2k`-th order Trotter-Suzuki product formula. Every
  term in `A` is applied at *every* Trotter stage, in a fixed order.
- **`B` (the qDrift/randomized set — the "tail")**: terms simulated by
  qDrift — at each of `N_B` samples, ONE term is drawn i.i.d. from `B`'s
  importance distribution `p_j = b_j/λ_B` and applied for a fixed duration.

`H = A + B`, `A ∩ B = ∅` term-wise. This is the paper's own vocabulary for
what the task calls "head/tail": `A` deterministically carries every term
every time (like a circuit's fixed head), `B` supplies one randomly-drawn
term per sample (a stochastic tail draw). The partition is chosen ONCE per
simulation (Section titles: "Hamiltonian Partitioning", §4.2/§5.3) — not
re-drawn per Trotter step; only the qDrift *sample identity* is randomized
per step, not the partition itself.

## (b) The operational construction — what one Composite step is

This is the exact recipe the implementation follows. Read bottom-up: first
the base case (first-order outer loop), then its recursive lift to any even
order `2k`, matching the *same* recursion used to build the pure-Trotter
formula in §3.1.

**First-order outer loop** (Theorem `thm:first_order_composite`, the base
case). Define `𝒰_A(t)` (exact evolution under `A` alone), `𝒰_B(t)` (exact
evolution under `B` alone). The exact channel decomposes as

    e^{-iHt} ρ e^{+iHt} = e^{-iBt} e^{-iAt} ρ e^{+iAt} e^{+iBt} + E_{A,B}(t)      (outer-loop, line 333)

(sign per the paper's `e^{+iHt}` convention) — i.e. to leading order,
evolving under `H` for time `t` = evolving under `A` for `t` THEN under `B`
for `t` (in that order — `B` is applied LAST, outermost), up to an
"outer-loop" error `E_{A,B}(t)` from `[A,B] ≠ 0` that is bookkept
separately from each factor's own approximation error. One **composite
step of size `t/r`** is then:

    Ũ(t/r) = Ũ_B(t/r) ∘ Ũ_A(t/r)

where `Ũ_A` is implemented by a first-order Trotter sweep through the `A`
terms (`L_A` exponentials, in the fixed order of `A`) and `Ũ_B` is
implemented by `N_B` i.i.d. qDrift samples from `B`'s distribution (`N_B`
exponentials, each a randomly-drawn `B_j` applied for duration `λ_B·(t/r)/N_B`).
This whole composite step is repeated `r` times: `Ũ(t/r)^{∘r} ≈ 𝒰(t)`.
**One "step" = one full Trotter sweep over `A` immediately followed by one
full batch of `N_B` qDrift draws from `B`; ordering is A-then-B within a
step; steps repeat `r` times; the qDrift draws are freshly resampled every
step** (this is what makes the average-channel argument for `𝒰_B` apply
per-step, and is exactly what licenses the concentration argument of
`chen_2021_concentration_random_products.md` being invoked per-step rather
than once globally).

**Higher-order outer loop** (Definition `def:higher_order_loop` — the
recursive generalization, mirroring the Trotter-Suzuki recursion above
term-for-term but treating `𝒰_A`/`𝒰_B` as the atomic first-order pieces
rather than individual `e^{ih_iH_it}` factors). Second-order outer loop:

    𝒰^{(2)}(t) := 𝒰_A(t/2) ∘ 𝒰_B(t/2) ∘ 𝒰_B(t/2) ∘ 𝒰_A(t/2)               (line 499)

i.e. the SYMMETRIZED (Strang) composite step: half-step of `A`, then a
FULL-step-equivalent of `B` split into two adjacent half-step `B`-batches
(each an independent `N_B`-sample qDrift batch for duration `t/2`), then
another half-step of `A` to close the sandwich. Recursively, for `2k`-th
order:

    𝒰^{(2k)}(t) := 𝒰^{(2k-2)}(u_k t)² ∘ 𝒰^{(2k-2)}((1-4u_k)t) ∘ 𝒰^{(2k-2)}(u_k t)²      (line 503)

with the SAME `u_k := 1/(4-4^{1/(2k-1)})`, `Υ := 2·5^{k-1}` as pure Trotter
(§3.1) — the paper deliberately reuses the Suzuki fractal recursion, just
substituting `𝒰_A ∘ 𝒰_B`-sandwiches for the individual-term exponentials at
the base of the recursion. Implemented (tilde) version: same recursion with
every `𝒰_A(τ)` replaced by its `L_A`-term first-order Trotter sweep and
every `𝒰_B(τ)` replaced by a *fresh* independent `N_B`-sample qDrift batch
of duration `τ` (freshly resampled at every leaf of the recursion — `Υ`
leaves total for `A`, `Υ` leaves total for `B`, per outer step). **Ordering
within a step is dictated by the recursion tree, always symmetric
(palindromic) about the center, exactly as for ordinary higher-order
Suzuki** — this is what gives the `O(t^{2k+1})` local error instead of
`O(t²)`.

Cost bookkeeping per outer step of size `t/r`: `ΥL_A` operator exponentials
for the `A`-sweeps (`Υ` leaves × `L_A` terms each) plus `ΥN_B` qDrift-sample
exponentials for the `B`-batches (`Υ` leaves × `N_B` samples each) — hence
`Υ(ΥL_A + N_B)`-shaped terms recur throughout the cost bounds below (the
paper's Theorem 2.1 cost bound, expanded, literally has this factor
structure).

## (c) Theorem 2.1's diamond-norm cost bound (Section 2, Main Results)

This is `\label{thm:higher_order_cost_fixed}`, restated `\assCost*` at
line 531, the FIRST theorem stated in §2 "Main Results" — i.e. Theorem 2.1
in the compiled numbering.

**Statement.** Given time `t`, error bound `ε`, partitioned Hamiltonian
`H = A + B`, let `Ũ^{(2k)}` denote the higher-order Composite channel
(§(b) above) approximating the exact evolution `𝒰(t)`. By using `r`
iterations of `Ũ^{(2k)}(t/r)`, the error requirement
`‖𝒰(t) − Ũ^{(2k)}(t/r)^{∘r}‖_⋄ ≤ ε` can be satisfied using at most

    C_comp(A,B,t,ε,2k)
      ≤ Υ(ΥL_A + N_B) ⌈ (Υt)^{1+1/2k} 4^{1/2k}/ε^{1/2k} · ((Υ·α_comm(A,2k) + α_comm({A,B},2k))/(2k+1))^{1/2k}
                        + 4Υλ_B²t²/(N_B ε) ⌉                                  (Thm 2.1)

operator exponentials of the form `e^{iH_it'}`.

**Every quantity, pinned:**

| symbol | meaning |
|---|---|
| `t` | total simulation time |
| `ε` | target diamond-distance error budget for the WHOLE `r`-step simulation |
| `2k` | Trotter order of the outer loop (matches innermost Trotter order — the paper's own convention, line 490) |
| `Υ = 2·5^{k-1}` | number of first-order-equivalent "stages" per outer step, from the Suzuki fractal recursion |
| `A`, `B` | the head (Trotter) / tail (qDrift) partition of `H` |
| `L_A` | number of terms in `A` (Trotter sweep length) |
| `N_B` | number of qDrift samples drawn per `B`-batch (a free/tunable parameter, NOT determined by the partition alone) |
| `λ_B = Σ_j b_j` | total spectral weight of the qDrift partition |
| `α_comm(A, 2k)` | nested-commutator sum restricted to `A`-only terms (Eq. def:alpha_comm) — drives the pure-Trotter part of the error |
| `α_comm({A,B}, 2k)` | cross commutator sum, ≥1 term from each of `A`,`B` in every nested bracket — drives the outer-loop/mixing error |
| `r` | number of outer-loop repetitions (folded into the ceiling via the derivation, not a free symbol in the final bound) |

**Reading the bound.** The two summands inside the ceiling are exactly the
two error sources: the first (`(Υt)^{1+1/2k}·(commutators)^{1/2k}`) is the
Trotter-formula truncation error for the `A`-sweep AND the outer-loop
mixing error together (both scale the same way in `t,ε,2k` — this is why
`α_comm(A)` and `α_comm({A,B})` appear summed inside one `(·)^{1/2k}`); the
second (`4Υλ_B²t²/(N_B ε)`) is exactly the qDrift channel error
(Theorem `thm:QDrift`'s `4λ²t²/ε` with `λ→λ_B`, `N→N_B`, scaled by `Υ`
because there are `Υ` independent `B`-batches per outer step). The prefactor
`Υ(ΥL_A + N_B)` is the per-repetition gate cost (§(b)'s bookkeeping) times
the resulting `r`.

A useful simplified packaging (line 140-143, same theorem's corollary form),
setting `q_B := α_comm(B,2k)/α_comm(H,2k)` and using `C_Trott`, `C_QD` from
Theorems 3.x (`thm:trotter_cost`, `thm:QDrift`) as reference costs:

    C_comp ≤ Υ(ΥL_A + N_B) ⌈ C_Trott(H,t,ε,2k) · (1-q_B)^{1/2k}/(Υ^{1-1/2k}L) + C_QD(H,t,ε) · (Υ/N_B) · (λ_B²/λ²) ⌉

— this is the form Sturm should use to sanity-check an implementation: as
`L_A → L` (everything Trotter, `q_B→0`, `λ_B→0`) the bound saturates to
`≈ C_Trott`; as `L_A → 0`, `λ_B → λ` (everything qDrift) it saturates to
`≈ C_QD` (paper states the exact limiting behavior, line 909: as `N_B→∞`,
`𝔼[C_comp] → C_QD` exactly; as `N_B` hits its lower bound (Eq. `eq:nb_lower_bound`),
`𝔼[C_comp] → (Υ^{1/2k}/2^{1-1/2k})·C_Trott ≤ 1.12·C_Trott`, with equality
factor `1` exactly at `k=1`/second order).

## (d) The two partitioning schemes the paper proposes

**1. Deterministic coefficient-threshold** (§4.2 for first order, general
guidance in §7 Discussion, line 195). Sort terms by spectral norm `h_i`;
place terms above a cutoff weight into `A` (Trotter), below into `B`
(qDrift). For the FIRST-ORDER case the paper derives an explicit per-term
optimality condition rather than a bare threshold: parametrize each term as
a convex split `h_iH_i ↦ w_i h_iH_i + (1-w_i)h_iH_i` (`w_i ∈ [0,1]`, `w_i=1`
⇒ fully Trotter, `w_i=0` ⇒ fully qDrift), and the stationary point of the
(relaxed, non-integer) cost `C̃_comp` w.r.t. `w_m` is (Eq. `eq:opt_first_order_weights`):

    w_m = 1 − Σ_{i≠m} (h_i/h_m) ( ‖[H_i,H_m]‖_∞/8 − (1-w_i) )

Two qualitative rules fall out (line 432): (i) a term that commutes with
everything (`[H_i,H_m]=0 ∀i`) gets `w_m > 1`, clamped to `1` — ALWAYS place
fully-commuting terms in the Trotter partition; (ii) small-`h_m` terms are
pushed toward `w_m → 0` (QDrift) as `h_m → 0`, i.e. small/weakly-commuting
terms belong in the tail. For higher order, the paper falls back to a
plain coefficient cutoff (no closed-form per-term optimum exists — the
`α_comm({A,B},2k)` gradient is a combinatorial "landmine", line 588):
pick a cutoff `h*` small compared to `λ` such that only `O(log₂L/L)` of the
terms exceed it (matches the assumption of Theorem `thm:exponential_decay`,
an exponentially-decaying-spectrum example where this fraction provably
gives asymptotic Composite-channel advantage at the `C_Trott=C_QD` crossover
time).

**2. Probabilistic partitioning** (Lemma `lem:prob_lemma`/`\assProb*`,
§5.2, `sec:probabilistic_partitioning`). Each term is placed in `A` with
probability `p_i` (i.i.d. Bernoulli decision per term), chosen as

    1 − p_i := min{ (λ/(h_iL)) · ( sqrt( N_B·(ε/(λt))^{1-1/2k}·((2k+Υ)/(2k+1))^{1/2k}·Υ^{1/2k}/2^{1-1/k} ) − 1 ), 1 }
             =: min{ χ/h_i, 1 }                                               (eq:prob_def)

with `χ` an "average strength" constant (line 694: if `N_B` is parametrized
as `(1+c)²` times its lower bound, `χ = cλ/L` exactly). This requires
choosing `N_B` to satisfy a LOWER bound first (Eq. `eq:nb_lower_bound`,
restated in §(e) below) so that `1-p_i` stays non-negative. Guarantees
(the Lemma's two clauses): (1) `p_i ∈ [0,1]` always; (2) the EXPECTED
qDrift-partition weight obeys `𝔼[λ_B]/λ ≤ (1/2)·sqrt(((4k+2Υ)/(2k+1))^{1/2k}·(2Υ)^{1+1/2k})·sqrt(N_B(ε/(λt))^{1-1/2k})`.
Derivation heuristic (line 630): choose `p_i` so the two error contributions
(Trotter-side `P(t)^{1/2k}/ε^{1/2k}` and qDrift-side `Q(t)/ε`, defined in
Eqs. `def:p_of_t`/`def:q_of_t`) are BALANCED in expectation — this is an
importance-sampling-like scheme on the INVERSE spectral norms `1/h_i`: small
terms (`h_i` small) get `1-p_i` near 1 (favor qDrift); large terms get
`p_i` near 1 (favor Trotter) once `h_i > χ`. As `c → ∞` (large `N_B`) all
`p_i → 0` (everything trends qDrift); as `c → 0` all `p_i → 1` (everything
trends Trotter) — exactly the saturation behavior noted under (c).

## (e) Guidance on choosing `N_B` and the Trotter order

**`N_B` for a FIXED (already-decided) partition.** First-order case, Lemma
`lem:first_order_opt_nb`: the non-integer cost `C̃_comp` is minimized at

    N_B = sqrt( 4λ_B²L_A / (Σ_{i,j} a_ia_j‖[A_i,A_j]‖_∞ + Σ_{i,j} a_ib_j‖[A_i,B_j]‖_∞) )

(undefined/should default to any `N_B>0` if every commutator in the
denominator vanishes — the paper notes this explicitly). Higher-order case,
Lemma `lem:optimal_nb_higher_order`:

    N_B = 2λ_B · sqrt( (Υt/ε)^{1-1/2k} · L_A · ((2k+1)/(Υ·α_comm(A,2k) + α_comm({A,B},2k)))^{1/2k} )

Both are found by setting `∂C̃_comp/∂N_B = 0` (verified as a genuine minimum
via `∂²C̃_comp/∂N_B² ≥ 0`, i.e. convex in `N_B`) — this is the value to use
when the partition is fixed and only `N_B` is being tuned.

**`N_B` for the PROBABILISTIC partitioning scheme.** `N_B` must additionally
satisfy the LOWER bound (Eq. `eq:nb_lower_bound`, needed for `1-p_i ≥ 0` to
be achievable at all):

    N_B ≥ (λt/ε)^{1-1/2k} · ((2k+1)/(2k+Υ))^{1/2k} · 2^{1-1/k}/Υ^{1/2k}

This scales as `Θ((λt/ε)^{1-1/2k})` — sublinear in `L` when `t,ε` are held
fixed as `L` grows (since `λ ≤ (max_i h_i)·L`), so moving a term from
Trotter to qDrift under this scheme does not automatically blow up `N_B`.
Practical rule of thumb given by the paper (line 691): parametrize
`N_B = (1+c)²·(lower bound)` for a small constant `c` — `c→0` biases toward
Trotter, `c→∞` biases toward qDrift; `c=O(1)` is the useful regime.

**Trotter order `2k`.** The paper gives no universal "best `k`" — it is
convenient to MATCH the outer-loop order to the innermost `A`-sweep order
(line 490, an analytical-convenience convention, not a requirement — "we
can choose any order formula we like"). Structurally: `k=1` (second order,
`Υ=2`) is the distinguished case where the higher-order composite
saturates EXACTLY to `C_Trott`/`C_QD` in the two limits (no `1.12×`
constant-factor penalty — line 909, `Υ^{1/2k}/2^{1-1/2k} = 1` exactly at
`k=1`). Larger `k` reduces the `t`-scaling exponent (`t^{1+1/2k} → t`) at
the cost of the `Υ = 2·5^{k-1}` stage-count prefactor growing geometrically
(`Υ=2,10,50,…` for `k=1,2,3,…`) — the same order-vs-prefactor tradeoff as
plain higher-order Trotter (`childs_2019_trotter_error.md`), now compounded
by `Υ` multiplying BOTH the `L_A` Trotter-sweep cost and the `N_B`
qDrift-batch count per outer step.

## Used by Sturm for

Design target for the post-M10 **Composite `evolve!` mode** (Trotter+qDrift
hybrid), gated behind M11+ per `CLAUDE.md`'s reboot status. When implemented,
the M11+ test should assert against Theorem 2.1's cost bound directly (§(c))
the same way the M10 pure-Trotter test asserts against Childs et al.'s
commutator-scaling bound — NOT a tuned-to-pass tolerance. The operational
construction in §(b) is the literal interleaving recipe the compiler/library
code must implement: A-sweep then B-batch per step (first order), or the
symmetrized `A/2, B/2, B/2, A/2` recursion (higher order) with FRESH qDrift
resampling at every leaf. The partitioning schemes in §(d) are candidate
`partition(H)` strategies to expose as library HOFs; §(e)'s `N_B` formulas
are the closed-form defaults for an auto-tuning `evolve!` variant. The
per-step qDrift resampling is exactly the setting
`chen_2021_concentration_random_products.md`'s concentration bound applies
to — see that file for why a single (not averaged) resampled qDrift
trajectory is a legitimate high-probability implementation, not merely an
expected-value one.
