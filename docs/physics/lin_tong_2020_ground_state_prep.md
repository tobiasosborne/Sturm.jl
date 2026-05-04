# Lin & Tong (2020) — Near-Optimal Ground State Preparation

**Citation**: Lin, L. & Tong, Y. *Near-optimal ground state preparation*.
arXiv:2002.12508v3 (6 Dec 2020). Published: Quantum **4**:372 (2020).

**Local PDF**: `docs/literature/quantum_simulation/qsp_qsvt/2002.12508.pdf`.

**Status in pipeline**: ground-truth source for the **eigenvalue filter / sign-
function polynomial** primitive that Sturm.jl uses for ground-state preparation
and energy-gap algorithms (bead `Sturm.jl-u1er`). For the orthogonal phase-
factor pipeline see `berntson_sunderhauf_2025_complementary_polynomials.md`
and `laneve_2025_gqsp_nlft.md`.

---

## What this paper does (one-line)

Given a block-encoded Hermitian `H` with a known a-priori bound on the ground
energy, prepares the ground state with `O((1/Δ)·log(1/ε))` queries to the block
encoding, where `Δ` is the spectral gap and `ε` the target fidelity error.
This is the asymptotically optimal scaling.

The construction has two ingredients we extract for Sturm.jl:

1. **Sign-function polynomial** (Lemma 3) — the QSVT polynomial that turns a
   block-encoded `(H − µI)/α` into a (block-encoded) reflector through
   eigenstates with eigenvalue `< µ`. **This is what Sturm.jl uses.**
2. **Reflector → projector** (Lemma 5) — an LCU of `±REF(µ)` to extract the
   projector onto eigenstates `< µ`. Not yet shipped in Sturm.jl; will land
   when ground-state-prep is needed end-to-end.

## The sign-function polynomial (Lemma 3, the one Sturm.jl uses)

> **Lemma 3 (Polynomial approximation of the sign function).** For all
> `0 < δ < 1` and `0 < ε < 1`, there exists an efficiently computable *odd*
> polynomial `S(·; δ, ε) ∈ ℝ[x]` of degree `ℓ = O((1/δ)·log(1/ε))` such that
>
>   (1) `|S(x; δ, ε)| ≤ 1`              for all `x ∈ [-1, 1]`, and
>   (2) `|S(x; δ, ε) − sign(x)| ≤ ε`    for all `x ∈ [-1, -δ] ∪ [δ, 1]`.

Lin-Tong cite GSLW19 Lemma 14 for the existence; the rescaling from `[-2, 2]`
to `[-1, 1]` is theirs, and is the right interval for QSVT-on-block-encodings
(eigenvalues of `A/α` lie in `[-1, 1]`).

### Construction (the one Sturm.jl uses)

Truncated Chebyshev expansion of `erf(K·x)`. Picking `K = √(log(2/ε))/δ`
satisfies `1 - erf(K·δ) ≤ ε/2` (plateau bound). The truncation degree is
chosen so the Chebyshev tail is below `ε/8`; the result is rescaled by
`1 - ε/4` to give `|S(x)| ≤ 1 - ε/4 < 1` strictly. This rescale leaves the
QSVT phase pipeline's own downscaling step (BS-25 → Laneve-25 RHW) some
headroom.

The expansion is computed via DCT-I of `erf(K·x)` sampled at Chebyshev–Lobatto
nodes — direct `O(N²)` evaluation since `N` stays small (≲ 1024) at typical
`(δ, ε)`.

## How Sturm.jl uses Lemma 3

```julia
using Sturm: sign_polynomial, qsvt_phases, qsvt_reflect!

cheb = sign_polynomial(δ, ε)              # Lemma 3, odd-parity Chebyshev
phi  = qsvt_phases(cheb; epsilon = ε/4)   # BS-25 → Laneve-25 → 2d+1 phases

@context EagerContext() begin
    sys = [QBool(0.0) for _ in 1:N]        # initial state on system register
    success = qsvt_reflect!(sys, BE_of_H_minus_µ, phi)
    # On success, sys carries S((H-µ)/α)·|ψ⟩.
    # Eigenstates with eigenvalue < µ get factor +1, > µ get -1.
end
```

### Where the parts live

| Step | Sturm function | This-paper ref |
|---|---|---|
| Sign polynomial | `sign_polynomial(δ, ε)` | Lemma 3 |
| Completion P→Q | `complementary_polynomial` | (BS-25, paper-orthogonal) |
| Factorisation (P,Q)→phases | `rhw_factorize` + `extract_phases` | (Laneve-25, paper-orthogonal) |
| Phase wrapper | `qsvt_phases(cheb)` | (combines BS-25 + Laneve-25) |
| QSVT circuit | `qsvt_reflect!(sys, BE, phases)` | GSLW Definition 15 / Theorem 17 |

## Reflector and projector (Lemma 5 — *not yet implemented*)

> Given `H` with `(α, m, 0)`-block-encoding `U_H` and `µ ∈ ℝ` separated from
> the spectrum of `H` by `Δ/2`, applying `qsvt_reflect!` with the sign-
> polynomial phases gives a `(1, m+2, ε)`-block-encoding of the reflector
>
>   `R_{<µ} = Σ_{λ_k < µ} |ψ_k⟩⟨ψ_k| − Σ_{λ_k > µ} |ψ_k⟩⟨ψ_k|`,
>
> and an LCU of `±R_{<µ}` gives a block encoding of the projector `Π_{<µ}`.

Sturm.jl currently exposes `R_{<µ}` (via the pipeline above) but not the
projector LCU. The latter is one bead away (LCU primitive already shipped
in `src/block_encoding/lcu.jl`).

## Page / equation index

| Citation in Sturm code | Where in paper |
|---|---|
| "Lin-Tong 2020 Lemma 3 / sign polynomial" | §2, p. 9, Lemma 3 |
| "Lin-Tong 2020 Lemma 5 / reflector→projector" | §2, p. 12, Lemma 5 |
| "Lin-Tong 2020 Theorem 6 / GSP a-priori" | §3 |
| "Lin-Tong 2020 Theorem 8 / ground energy" | §4 |

## What this paper does NOT do

- **No QSVT phase finding.** Lemma 3 is purely the polynomial side; the QSP
  phase factors that realise `S(·; δ, ε)` come from BS-25 + Laneve-25.
- **No HHL.** Lin-Tong is ground-state preparation, a strictly more useful
  primitive than HHL for most chemistry/physics workloads. (User reminder
  on bead `Sturm.jl-u1er`: HHL is excluded from the QSVT epic by design.)
