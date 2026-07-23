# Zlokapa–Allen–Harrow 2026 — Optimal Lower Bounds for Hamiltonian Simulation

**Source (local):** `docs/physics/zlokapa_2026_hamsim_lower_bounds.pdf` /
`docs/literature/2607.19852_src/lbhs.tex` — A. Zlokapa, R. R. Allen, A. W.
Harrow, *Optimal Lower Bounds for Hamiltonian Simulation* (arXiv:2607.19852,
MIT-CTP/6075). Cited upper-bound reference: Hagan–Wiebe, *composite qDRIFT*
(cited in-paper as Theorem 2.1, reproduced here as Fact HW, Appendix A). This
paper is dated **after** the assistant's knowledge cutoff — every claim below
is read from the local `.tex`, not recalled.

## What Sturm uses it for

`evolve!` (`src/library/evolve.jl`) currently ships first- and second-order
Trotter only (see `docs/physics/childs_2019_trotter_error.md`). This paper is
the citation for TWO planned M11+ extensions: (1) the Suzuki-2k coefficients
for higher-order product formulas in `evolve!`'s Trotter strategy family (the
`p` in Appendix A's "order `2p` Suzuki formula" — see
`docs/physics/suzuki_1991_fractal_decomposition.md` for the coefficients
themselves), and (2) an `Auto` dispatch strategy that picks a deterministic/
randomized split `K` (Trotter the largest-`K` terms, qDRIFT the tail) using
the frontier envelope `min_K(Kt + t²λ_K²/ε)` and the optimal-`K*` rule
(Lemma "Optimal deterministic-randomized split", below) — plus a bench-suite
assertion that `evolve!`'s achieved gate count tracks this envelope and never
beats the Ω(·) lower bound of Theorem "Gate lower bound". This is a
GROUNDING citation (Principle 3/9): it is what makes "our composite-qDRIFT
dispatcher is asymptotically optimal" a checkable claim rather than an
aspiration.

## The setup (§ "Summary of results", eq. (1)/(2) in the `.tex`, labels
`eq:h-main-indep` / `eq:h-main`)

Hamiltonian with SORTED, normalized coefficients:

    H = Σ_{j=1}^L a_j h_j,   a_1 ≥ a_2 ≥ … ≥ a_L > 0,   Σ_j a_j = 1      (eq:h-main-indep)

each `h_j` a distinct `k`-local (`k ≥ 2`) Hermitian operator, `‖h_j‖ = 1`
(e.g. a Pauli string). The paper also treats the time-dependent generalization
`H(τ) = Σ_j a_j h_j(τ)` (eq:h-main) with `a` fixed but `h_j` changing on
`Θ(1)`-length intervals; results carry over via the time-dependent→
time-independent reduction (Lemma `time_dep_to_ind_reduction`, App. B).

**Tail mass** (eq:lambda):

    λ_K = Σ_{j>K} a_j ≤ 1                                                (eq:lambda)

The target is a channel `E_H` approximating the ideal evolution channel
`U_H = T exp(−i ∫₀ᵗ H(τ) dτ)` to TRACE-DISTANCE error `ε`:
`(1/2)‖E_H(ρ) − U_H(ρ)‖_1 ≤ ε` for all density matrices `ρ`.

## The gate lower bound (Theorem "Gate lower bound", `thm:gate`)

> Given `t`, `a⃗`, and sufficiently small `ε`, there exists a time-dependent
> Hamiltonian `H(τ) = Σ_j a_j h_j(τ)` with `‖h_j(τ)‖ = 1` such that: if a
> channel `E_H` using `G` two-qubit gates satisfies
> `(1/2)‖E_H(ρ) − U_H(ρ)‖_1 ≤ ε` for all density matrices `ρ`, then

    G ≥ Ω( min_{0≤K≤L} ( Kt + t²λ_K²/ε ) )                               (eq:lb)

The channel `E_H` is not assumed unitary: the theorem covers any convex
mixture `E_H = Σ_r p_r E_{H,r}` of channels, each with a Stinespring
dilation `E_{H,r}(ρ) = tr_{A_r}(W_r (ρ ⊗ |0⟩⟨0|_{A_r}) W_r†)` using at most
`G` two-qubit gates on system+ancilla (arbitrarily many one-qubit gates
allowed). This is the CHANNEL FRAMING Sturm's own Choi/diamond-level
philosophy matches (Principle 3/12): the bound is stated and proved at the
level of the induced channel and its dilation, never "the circuit looks
like X." `thm:gate` immediately implies every mixed-unitary algorithm
(`E_H(ρ) = Σ_r p_r V_r ρ V_r†` — Trotterization, QSP, qDRIFT, composite
qDRIFT all have this form) must have at least one branch `V_r` using ≥ `G`
two-qubit gates.

Proved as two separate lemmas (App. `sec:gate`), a HEAD bound and a TAIL
bound, that together give (eq:lb):

- **Tail** (Lemma "Gate complexity tail lower bound"): `G + 1 ≥ C_t
  λ_{K*}²/ε` for a constant `C_t > 0`, witnessed by cat states superposing
  `|0…0⟩` with strings that flip tail-coefficient pairs; the algorithm must
  physically touch enough pairs with two-qubit gates to reproduce the
  accumulated relative phase, or a subset-correlation-ratio argument (a
  KL-divergence/Pinsker distinguishing argument between two biased-sign
  distributions) detects the shortfall.
- **Head** (Lemma "Gate complexity head lower bound"): `G + C_{h,1} ≥
  C_{h,2} K* − C_{h,3} λ_{K*}²/ε`, witnessed by the product state `|+⟩^{⊗2L}`
  — too few two-qubit gates leaves too many `(A_j,B_j)` pairs
  disconnected, and disconnected pairs stay product across some bipartition
  while the ideal evolution entangles them, capped via
  `cos(x) ≤ e^{−x²/2}` on the Schmidt coefficients.

## The query lower bound (Theorem "Query lower bound", `thm:query`)

> Let `t, a⃗, ε, U_H` as in `thm:gate`. There is a distribution over
> Hamiltonians `H(τ)` with corresponding CLASSICAL oracles `O_H` such that
> any algorithm `E_H` making `Q` classical queries to `O_H` and satisfying
> `E_H[ (1/2)‖E_H(ρ) − U_H(ρ)‖_1 ] ≤ ε` for all `ρ` must satisfy

    Q ≥ Ω( min_{0≤K≤L} ( Kt + t²λ_K²/ε ) )

Same right-hand side as the gate bound — the paper's punchline. The oracle
model (Def. "Classical oracle access") is deliberately WEAK: `O_H(j, τ)`
returns a classical description of `a_j` and `h_j(τ)`; it CANNOT be queried
in superposition. This is explicitly contrasted (§ "Prior algorithms" /
right after `thm:query`) with the SELECT/PREPARE block-encoding oracle
model, where `H` can be block-encoded in `O(1)` queries — the paper's stated
moral is that counting SELECT/PREPARE queries "does not capture the full
complexity of quantum simulation" because building SELECT itself costs
`O(L)` gates; QSP's true cost (eq:qsp in the `.tex`) carries this `L`
factor openly. Proved by the same head/tail split (App. `sec:query`, Lemmas
"Query complexity tail/head lower bound"), using a 1-local, NON-INTERACTING
hard Hamiltonian family `H_s = Σ_j s_j a_j |1⟩⟨1|_j`, `s ∈ {±1}^L` random
signs (Def. `time_ind_query_rra`) — an algorithm that doesn't query a term's
sign cannot reproduce its relative phase.

## The optimal-split lemma (Lemma "Optimal deterministic-randomized split")

> Let `K* ∈ argmin_{0≤K≤L} (K + λ_K²/ε)`. Then `Σ_{j>K*} a_j² ≤ ε` and (if
> `K* > 0`) `ε ≤ a_{K*}² + 2 a_{K*} λ_{K*}`.

This is the exact pin the task calls for: the OPTIMAL split condition is
`Σ_{j>K*} a_j² ≤ ε` (upper half — the tail is small enough in the ℓ²-sense
that qDRIFT-ing it costs ≤ ε), and the MATCHING lower condition is `ε ≤
a_{K*}² + 2 a_{K*} λ_{K*}` (if you moved the split one term further, the
tail would no longer be cheap enough). Proved by comparing the discrete
minimum's two neighboring finite differences (`K*+1` vs `K*` and `K*−1` vs
`K*` in `K + λ_K²/ε`) and using `a_{K*+1} ≤ λ_{K*}` (sorted coefficients).
This is the exact rule Sturm's `Auto` dispatch should implement to CHOOSE
`K` (Trotter-vs-qDRIFT split point) from a sorted coefficient list and a
target `ε` — not a heuristic, a proved-optimal closed-form condition.

## Appendix A — Fact HW (the composite-qDRIFT upper bound)

Reproduced from Hagan–Wiebe (their Theorem 2.1); stated as **Fact
[Hagan–Wiebe, Theorem 2.1]** (`fact:HW`). For `H = A + B`, `A = Σ_ℓ α_ℓ A_ℓ`
(`‖A_ℓ‖=1`), `B = Σ_ℓ β_ℓ B_ℓ` (`‖B_ℓ‖=1`), `λ_B = Σ_ℓ β_ℓ`, `Υ = 2·5^{p−1}`
the stage count of an order-`2p` Suzuki formula, `N_B ≥ 1` an integer: the
order-`2p` composite channel (Suzuki on `A`, qDRIFT on `B`) reaches diamond-
norm error ≤ ε using at most

    C_HW(A,B,t,ε,2p) ≤ Υ(Υ L_A + N_B) ⌈ (Υt)^{1+1/2p} 4^{1/2p} / ε^{1/2p}
                          · ( (Υ α_comm(A,2p) + α_comm({A,B},2p)) / (2p+1) )^{1/2p}
                          + 4Υλ_B²t² / (N_B ε) ⌉                          (eq:HW-cost)

operator exponentials, where the COMMUTATOR quantity is

    α_comm(F,2p) = Σ_{γ1,…,γ_{2p+1}} (Π_r f_{γr}) ‖[F_{γ_{2p+1}},[F_{γ_{2p}},…,[F_{γ2},F_{γ1}]…]]‖

for `F = Σ_γ f_γ F_γ`, `‖F_γ‖=1` — the standard Trotter-error nested-
commutator sum (cf. `docs/physics/childs_2019_trotter_error.md`'s E1/E2, but
generalized to the order-`2p` recursive case); `α_comm({A,B},2p)` restricts
the sum to nested commutators touching BOTH `A` and `B`. NOTE (paper's own
caveat): `{A,B}` here is NOT an anticommutator, and Hagan–Wiebe's sign
convention is the opposite of this paper's — the bound is unaffected.

Zlokapa–Allen–Harrow specialize this to the sorted-Hamiltonian setting
(`A` = the top `K` terms, `B` = the tail `j > K`, `λ_B = λ_K`), bound
`α_comm(A,2p) ≤ 2^{2p}(1−λ_K)^{2p+1}` and the mixed term similarly (each
`h_j` has unit norm so any `(2p+1)`-fold nested commutator has norm ≤
`2^{2p}`), choose `N_B = K`, and optimize over `K` to get, for fixed `p`
(eq. `composite-fixed-p`) and then for arbitrary small `η` by taking `p`
large (final unlabeled display, end of App. A):

    C_comp = O( min_{0≤K≤L} { Kt(t/ε)^{o(1)} + t²λ_K²/ε } )              (eq:composite, main text)

— this is the matching UPPER bound to (eq:lb); the paper's core claim is
that (eq:lb) and (eq:composite) sandwich the true cost, so composite qDRIFT
is asymptotically optimal and no "higher-order qDRIFT" beating it can exist.

## The channel framing

Both lower bounds are proved directly against channels with an explicit
Stinespring-dilation gate-count budget, and the error metric throughout is
TRACE distance `(1/2)‖·‖_1` (not fidelity, not a diamond-norm proxy applied
loosely) — Theorem `thm:gate`/`thm:query` both state the hypothesis as
`(1/2)‖E_H(ρ) − U_H(ρ)‖_1 ≤ ε for all density matrices ρ`. The algorithm
class covered is explicitly a MIXTURE of Stinespring dilations,
`E_H = Σ_r p_r E_{H,r} = E_r[E_{H,r}]`, each `E_{H,r}` its own dilation
`tr_{A_r}(W_r(ρ⊗|0⟩⟨0|)W_r†)` — this is the same "compare at the channel
level, not at the level of a single circuit" discipline Sturm's own
Principle 3/12 (Choi/diamond, never marginals or a single unitary
comparison) already enforces; this paper is independent confirmation that
the CORRECT lower-bound target for a Hamiltonian-simulation cost claim is a
channel-level trace-distance/diamond statement, not a per-branch unitary
comparison.

## The physical moral (abstract; § "In what sense is composite qDRIFT
`optimal`?")

Quoting the abstract directly: "for many physical systems (e.g., power-law
interactions), gate count must scale polynomially in `1/ε`, CONTRARY to the
complexity suggested by counting coherent oracle queries such as those in
the block-encoding model." The mechanism (§ "Prior algorithms", right after
eq:qsp): QSP's query cost `O(L(t + log(1/ε)/log log(1/ε)))` to SELECT/PREPARE
looks like `polylog(1/ε)`, but building SELECT itself costs up to `O(L)`
GATES — a cost the query model hides. The paper's classical-oracle model
(§ "Summary of results", after `thm:query`) is chosen precisely so that this
hidden `L`-dependent construction cost cannot be papered over, and the
resulting lower bound shows the TRUE gate cost is `poly(1/ε)` for
power-law-type coefficient tails, not the `polylog(1/ε)` the query count
alone would suggest. This is the caution Sturm's bench suite (M11+) should
encode: reporting a block-encoding QUERY count for `evolve!`'s QSP path
(when it lands) without also reporting the SELECT-construction gate cost is
a misleading benchmark by this paper's own stated thesis.

## Discrepancy check

None found between the task's brief and the actual `.tex`: the setup, both
theorem statements (gate `thm:gate`, query `thm:query`), the optimal-split
lemma (`lemma: optimal_k`, both directions), Fact HW / `eq:HW-cost` with
`α_comm`, and the channel/Stinespring/trace-distance framing all match
verbatim what is asked for. One nuance worth flagging: the paper's own
in-text label for the gate bound is `\Cref{thm:gate}` / eq. label `eq:lb`
(not a separately named "eq (G)"), and Fact HW is cited as "Hagan–Wiebe,
Theorem 2.1" (their Theorem, reproduced here as this paper's `Fact
\ref{fact:HW}`) — both are exactly as named in the tex, just noting for a
future reader who greps for a differently-spelled label.

## Files copied

- `docs/physics/zlokapa_2026_hamsim_lower_bounds.pdf` (copied from
  `docs/literature/2607.19852.pdf`)
