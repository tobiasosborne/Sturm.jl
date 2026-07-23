# Hastings 2016 — turning gate synthesis errors into incoherent errors

**Source (local):** `docs/physics/hastings_2016_incoherent_errors.pdf` —
M. B. Hastings, *Turning Gate Synthesis Errors into Incoherent Errors*, Quantum
Info. Comput. 17, 488 (2017) (arXiv:1612.01011). Tex source:
`docs/literature/1612.01011_src/rot.tex`.

## What Sturm uses it for

The elementary, independently-derived version of the coherent-to-incoherent
error-conversion result that qDRIFT (`docs/physics/campbell_2019_qdrift.md`) and
Campbell's mixing lemma (`docs/physics/campbell_2017_mixing_unitaries.md`) both
build on — this paper is the "Hastings" half of the "Hastings-Campbell mixing
lemma" qDRIFT's appendix cites by name. Its toy model (repeated Z-rotations with
a random `±ε` angle error) is the SIMPLEST possible instance of exactly the
Trotter-simulation error-accumulation problem `evolve!` faces: apply the same
imperfect gate `N` times, and ask whether the error grows as `O(N)` (coherent,
worst case) or `O(√N)` (incoherent, if randomized). Sturm cites this for the
`ε → O(ε²)` per-gate-count scaling law as the second, independent grounding of
why randomized compiling is not a numerical curiosity but a provable channel-level
effect (CLAUDE.md principle 3: ground = physics, not "it works on the test
case").

## The toy example (paper §intro, verified against tex)

Apply `N` successive unitaries `exp(iθσ_Z)`. If instead one applies `N` copies of
`exp(iθ'σ_Z)` with a FIXED systematic offset `θ'-θ=ε`, the total angle error is
`Nε`, so keeping the evolution accurate needs `|ε| ≲ 1/N` — errors add COHERENTLY
(linearly in `N`). If instead each application independently uses
`exp(i(θ±ε)σ_Z)` with the sign chosen uniformly at random per gate, the errors
form a RANDOM WALK, and `|ε| ≲ 1/√N` suffices — errors add INCOHERENTLY (the
`√N` scaling of a random walk's typical displacement). This is the "roughly
`ε → ε²N` (coherent) vs `ε²N` accumulated-VARIANCE with the same tolerance
achievable at larger per-gate `ε` (incoherent)" scaling the abstract states, and
it explicitly generalizes the single-Pauli-term case of exactly the Trotter
setting Sturm's `evolve!` implements (paper §intro, explicit remark: "The effect
in this toy example would occur in simulating a Hamiltonian by Trotter-Suzuki
methods... since the same unitaries are applied repeatedly... small errors in
angle can add coherently... the toy example is an example of this method using
just a single term in the Trotter-Suzuki decomposition").

## Lemma 1 — the single-step diamond-norm bound (paper §"General Results",
`Lemma \ref{onel}`, verified against tex)

Let `{W_a}` be unitaries with probability distribution `q(a)`, mean
`W̄ := Σ_a q(a) W_a`, and variance-like quantity

    δ := Σ_a q(a) ‖W_a - W̄‖²                                               (δ-def)

Let `𝓔(σ) = UσU†` (target) and `𝓖(σ) = Σ_a q(a) W_a σ W_a†` (the mixed/sampled
channel). Then

    ‖𝓔 - 𝓖‖_◇  ≤  δ + 2‖W̄ - U‖                                            (L1)

**Proof structure (verified):** introduce the intermediate linear map
`𝓕(σ) = W̄σW̄†`. First, `‖𝓔-𝓕‖_◇ ≤ 2‖W̄-U‖` (unitary-invariance of the diamond
norm applied to the mean operator's closeness to `U` — an instance of the same
(UB)-type inequality used in the mixing-unitaries paper). Second, expand `𝓖⊗id`
around `W̄`: the cross terms (linear in `W_a - W̄`) vanish upon summing against
`q(a)` by definition of the mean, leaving only the QUADRATIC remainder term
`Σ_a q(a)(W_a-W̄)σ(W_a-W̄)†`, whose trace norm is bounded by `δ·‖σ‖₁` — giving
`‖𝓕-𝓖‖_◇ ≤ δ`. Triangle inequality closes the proof: `‖𝓔-𝓖‖_◇ ≤ ‖𝓔-𝓕‖_◇ +
‖𝓕-𝓖‖_◇ ≤ 2‖W̄-U‖ + δ`.

## Lemma 2 — composition over a circuit (paper §"General Results", `Lemma
\ref{twol}`, verified against tex)

Diamond distance is submultiplicative under channel COMPOSITION (paper Eq.
`compineq`, an explicit telescoping-triangle-inequality proof, not merely
cited): for channels `𝓔_1,…,𝓔_N` and `𝓖_1,…,𝓖_N`,

    ‖𝓔_N∘…∘𝓔_1 - 𝓖_N∘…∘𝓖_1‖_◇  ≤  Σ_{i=1}^N ‖𝓔_i - 𝓖_i‖_◇                (comp)

Chaining Lemma 1 per gate `i` (each with its own `δ_i` and mean-closeness
`‖W̄_i - U_i‖`) through (comp) gives Lemma 2's headline bound on the expected
error over an `N`-gate circuit `U = U_N…U_1` approximated by randomly resampled
`V_i = W_{i,a(i)}`:

    |E[VρV† - UρU†]|  ≤  Σ_{i=1}^N (δ_i + 2‖W̄_i - U_i‖)                    (L2)

## The worked single-qubit-rotation case (paper §"Applications", verified)

Each `U_i = exp(iθ_iσ_Z)` is approximated by one of two rotations
`W_{i,1}=exp(iθ_{i,1}σ_Z)`, `W_{i,2}=exp(iθ_{i,2}σ_Z)` with weights chosen so
`q_i(1)θ_{i,1}+q_i(2)θ_{i,2}=θ_i` exactly (the mean angle matches). Writing
`φ_{i,k}=θ_{i,k}-θ_i`, a small-angle expansion (`cos φ ≥ 1-φ²/2`) gives

    ‖W̄_i - U_i‖  ≤  ½(q_i(1)φ_{i,1}² + q_i(2)φ_{i,2}²) + O(φ⁴)             (eqd)
    δ_i          ≤  q_i(1)φ_{i,1}² + q_i(2)φ_{i,2}² + O(φ⁴)

so BOTH per-gate error contributions are `O(φ²)` — quadratic in the angle
deviation, confirming the headline claim: **to keep total circuit error `O(1)`
over `N` gates, per-gate angle deviation need only satisfy `φ ≲ 1/√N`**, not the
`1/N` a naive coherent-error argument would demand. This is the `ε → O(ε²)`
mechanism from the abstract, spelled out with exact leading-order coefficients
(no unproven asymptotic hand-waving — the `O(φ⁴)` remainder is explicit and
higher order).

## The magic-state / T-gate corollary (paper §"T Gates By State Injection")

A concrete case where this averaging happens AUTOMATICALLY, with no explicit
randomization needed by the circuit designer: T-gate-by-state-injection
(ancilla `2^{-1/2}(e^{iθ/2}|0⟩+e^{-iθ/2}|1⟩)`, CNOT, measure) implements
`exp(iθ/2·σ_Z)` on outcome `|0⟩` and `exp(-iθ/2·σ_Z)` on outcome `|1⟩`
(followed by an `S` correction) — the MEASUREMENT OUTCOME itself supplies the
random sign, so `θ ≈ π/4` systematic offsets in ancilla preparation are converted
into incoherent per-shot errors "for free." Over `S` injections with per-ancilla
angle variance `μ_2 := ⟨(θ-π/4)²⟩`, the accumulated trace-norm error is bounded
by `S·μ_2 + O(S·μ_4)` — again the `O(ε²)`-per-gate / linear-in-count-of-VARIANCE
(not linear-in-count-of-amplitude) accumulation law.

## Used by Sturm for

- **qDrift strategy in `evolve!`**: the independent, elementary derivation of
  WHY randomized/mixed compiling beats coherent accumulation — grounds the
  qDRIFT `N = ⌈2λ²t²/ε⌉` sample count (`docs/physics/campbell_2019_qdrift.md`,
  Eq. N) in a second, simpler argument: per-step angle/gate deviation
  contributes QUADRATICALLY (Eq. eqd/δ-def) rather than linearly, so `N` need
  only scale as `1/ε` in the variance budget rather than `1/ε` in the amplitude
  budget (the coherent worst case) — the qualitative reason qDRIFT's `1/ε`
  (not `1/ε²`) sample-count scaling is physically sensible, not merely an
  algebraic artifact.
- **Diamond-norm error composition of the composite channel**: Lemma 2's
  composition inequality (Eq. comp, `Σᵢ‖𝓔ᵢ-𝓖ᵢ‖_◇`) is the direct template — and,
  because the proof is a plain telescoping triangle inequality rather than a
  specialized qDRIFT/mixing-lemma argument, it is the right tool whenever Sturm
  needs to bound a CIRCUIT of several independently-imperfect library-generated
  gates (not just a single repeated randomized channel) by summing per-gate
  diamond distances.
