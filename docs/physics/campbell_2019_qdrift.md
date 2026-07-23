# Campbell 2019 — qDRIFT, a random compiler for Hamiltonian simulation

**Source (local):** `docs/physics/campbell_2019_qdrift.pdf` — E. Campbell,
*A random compiler for fast Hamiltonian simulation*, Phys. Rev. Lett. 123, 070503
(2019) (arXiv:1811.08017). Tex source: `docs/literature/1811.08017_src/
qDRIFT_arXiv_V2submit.tex`.

## What Sturm uses it for

A future randomized-compiling STRATEGY for `evolve!` (`src/library/evolve.jl`),
alongside the deterministic Trotter strategy already there
(`docs/physics/childs_2019_trotter_error.md`). Where Trotter's gate count scales
with the NUMBER OF TERMS `L` in the Hamiltonian, qDRIFT's scales only with the
absolute-value sum of the couplings `λ` — a genuinely different resource trade the
library should expose as an alternative `evolve!` compilation strategy, not a
replacement. It is also the load-bearing example of a NON-unitary library
generator: qDRIFT's output is a mixed-unitary CHANNEL by construction (the
sampled gate sequence is randomized and, if the sample record is discarded, the
result is a probabilistic mixture) — this is exactly the "library HOFs touch
kernel process values but the composite is judged at the channel level" pattern
CLAUDE.md principle 12 requires tests for (Choi/diamond, never a single-sample
unitary comparison).

## The Hamiltonian and the protocol (paper, main text and Fig. 1, "Pseudocode for
the qDRIFT protocol")

`H = Σ_{j=1}^L h_j H_j`, each `H_j` Hermitian with `‖H_j‖ = 1` (largest singular
value normalized to 1) and `h_j > 0` real. Define

    λ := Σ_j h_j                                                          (λ)

(this upper-bounds `‖H‖`). The qDRIFT channel for a single step (paper's
`𝓔`, main-text Eq. after "The evolution is mathematically represented..."):

    𝓔(ρ) = Σ_j p_j e^{iτH_j} ρ e^{-iτH_j},      p_j = h_j / λ            (E)

i.e. gate `j` is sampled i.i.d. with probability PROPORTIONAL TO ITS OWN
HAMILTONIAN WEIGHT (not uniformly over the `L` terms), and every sampled gate uses
the SAME fixed rotation angle `τ := tλ/N` — independent of which `j` was drawn.
This is the "quantum stochastic drift" picture: `N` steps of `𝓔` form a Markov
chain that stochastically drifts toward `U = e^{iHt}` (paper uses the physics
sign convention `e^{+iHt}`; Sturm's kernel uses `e^{-iHt}` — the distillation below
keeps the paper's sign and flags the flip at the point `evolve!` would apply it).

Pseudocode (Fig. 1, `MyALGo`):

1. `λ ← Σ_j h_j`
2. `N ← ⌈2λ²t²/ε⌉` (or solve the exact expression — see below)
3. Sample `N` indices `j_1, …, j_N` i.i.d. from `p_j = h_j/λ`
4. Append `e^{iτH_{j_k}}` to the gate list, `τ = tλ/N` fixed for every gate
5. Return the ordered list

The realized circuit for a sampled index sequence `j⃗` is
`V_{j⃗} = Π_{k=1}^N e^{iτH_{j_k}}` (paper Eq. (Vj_unitary)), drawn from
`P_{j⃗} = λ^{-N} Π_k h_{j_k}`.

## Theorem 1 — the diamond-norm bound (paper App. A "Error measures" / App. B
"Bounding higher order error terms", Eq. `\eqref{deltaBound}` main text, Eq.
before "This gives the result stated in the main text" appendix)

Single-step bound. Let `𝓤_N(ρ) := e^{iHt/N} ρ e^{-iHt/N}` (one `N`-th of the
target evolution) and `𝓔` as in (E) with `τ = tλ/N`. Then

    d(𝓤_N, 𝓔) ≤ (2λ²t²/N²) · e^{2λt/N}   ≈ 2λ²t²/N²   (for large N)          (δ)

where `d(·,·) = ½‖·‖_◇` is the diamond DISTANCE (the paper's `d`, App. A eq.
before "Bounding higher order error terms" — note the factor 1/2 is already
folded in; the RAW diamond-norm-of-the-difference bound before that folding is
`4λ²t²/N² · e^{2λt/N}`). The proof (App. B, verified against the tex): expand
`𝓤_N = e^{tℒ/N}` and `𝓔 = Σ_j p_j e^{τℒ_j}` in the Liouvillian representation
(`ℒ(ρ) = i(Hρ - ρH)`, `‖ℒ‖_◇ ≤ 2‖H‖ ≤ 2λ`; `‖ℒ_j‖_◇ ≤ 2`), match zeroth/first order
terms at `τ = λt/N`, bound the diamond norm of the REMAINDER series termwise by
sub-multiplicativity, and apply the exponential tail bound `Σ_{n≥2} x^n/n! ≤
(x²/2)e^x` (cited to Lemma F.2 of Childs–Maslov–Nam–Ross–Su, arXiv:1805.08385)
with `x = 2λt/N`.

Full-protocol bound. Diamond distance is SUBADDITIVE under channel composition
(cited to Watrous, *Theory of Quantum Information*), so `N` independent qDRIFT
steps compose to

    d(𝓤, 𝓔^N) ≤ N · d(𝓤_N, 𝓔) ≤ (2λ²t²/N) · e^{2λt/N}  ≈  2λ²t²/N           (ε)

where `𝓤(ρ) = e^{iHt}ρe^{-iHt}` is the target channel and `𝓔^N` is `N`
compositions of the sampled-channel-of-the-step (main text Eq.
`\eqref{deltaBound}` and the sentence immediately after: "the error of `N`
repetitions `𝓔^N` relative to the target unitary `U` is then `ε = Nδ ≲
2λ²t²/N`").

## The sample count `N` (main text, paragraph after Eq. (ε); pseudocode step 2)

Solving `2λ²t²/N ≤ ε` for `N` and rounding up:

    N_qD = ⌈2λ²t²/ε⌉                                                       (N)

**Verified exact constants** (both against the main-text statement and the
appendix derivation): the `2` is real (not absorbed/approximated), the exponents
on `λ` and `t` are both exactly `2`, and the bound is a single power of `1/ε` (no
square root) — because it is a DIAMOND-norm/composed-channel bound, not the
looser single-instance unitary-error bound (see below).

## The `L`-independence claim (main text, "Asymptotics comparison"; Table I)

`N_qD` depends on `H` only through `λ = Σ_j h_j` and the target `(t, ε)` — NOT on
`L` (number of terms) or `Λ := max_j h_j` (largest single term), the two
quantities standard Trotter-Suzuki gate counts depend on (`O(L^3(Λt)^2/ε)` for
1st-order deterministic Trotter, `O(L^{2+1/2k}(Λt)^{1+1/2k}/ε^{1/2k})` for
`2k`-order — Table I). Since `λ ≤ ΛL` always, qDRIFT's worst case (`λ = ΛL`,
e.g. 1D nearest-neighbor Heisenberg chains) still beats plain 1st-order Trotter's
`L`-scaling; and whenever a Hamiltonian has `λ ≪ ΛL` (long-range/electronic
structure Hamiltonians — the paper's propane/CO₂/ethane numerics, up to
`1591×` speedup at `t=6000`, `ε=10⁻³`), qDRIFT is the first known product formula
to beat the `O(L²)` floor common to every deterministic and randomly-PERMUTED
Trotter-Suzuki scheme (main text: "this is the only known product formulae to
beat the `O(L²)` barrier").

## The diamond-norm-vs-single-instance subtlety (main text, "Diamond norm
distance")

A crucial point the paper is explicit about and Sturm's tests must respect: if you
inspect a SINGLE sampled unitary `V_j⃗` (rather than the mixed/erased-record
channel `𝓔^N`), its typical error against `U` is close to `√ε`, NOT `ε` — because
`ε` is a bound on the DIAMOND distance of the averaged channel, which is generally
much tighter than any individual sample's unitary error. The favorable `ε` (not
`√ε`) scaling is available only if the sample index is discarded (traced out) —
i.e. only the CHANNEL-level object is `ε`-good. This is precisely why qDRIFT
belongs to the "judge at Choi/diamond level" discipline, not a per-shot unitary
comparison.

## Used by Sturm for

- **qDrift strategy in `evolve!`**: a second Hamiltonian-simulation compilation
  strategy alongside Trotter, selected by resource trade-off (`λ` vs `L`,
  `Λ`) rather than always defaulting to product formulas — the sampling
  distribution `p_j = h_j/λ` (Eq. λ/E) and fixed-angle-per-step rule
  (`τ = tλ/N`) are the exact spec to implement; `N = ⌈2λ²t²/ε⌉` (Eq. N) is the
  assertable sample-count formula (no tuned constant).
- **Diamond-norm error composition of the composite channel**: the M10/M11
  `evolve!` test suite's channel-level (not marginal) verification pattern
  generalizes directly — `d(𝓤, 𝓔^N) ≤ N·d(𝓤_N,𝓔)` (Eq. ε) is the template for
  "bound one step, multiply by step count, compare to `ε`" that any
  randomized-compiling library HOF in Sturm should follow, and the
  diamond-vs-single-instance distinction above is the reason the qDRIFT test
  MUST compare `evolve!`'s implicit channel (average over many independent
  samples, or an explicit Kraus/Choi construction) against `e^{-iHt}`'s channel,
  never a single realized circuit against the target unitary.
