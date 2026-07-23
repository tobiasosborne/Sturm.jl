# Campbell 2017 — shorter gate sequences by mixing unitaries

**Source (local):** `docs/physics/campbell_2017_mixing_unitaries.pdf` —
E. Campbell, *Shorter gate sequences for quantum computing by mixing unitaries*,
Phys. Rev. A 95, 042306 (2017) (arXiv:1612.02689). Tex source:
`docs/literature/1612.02689_src/Diamond_GS_resub.tex`.

## What Sturm uses it for

The general MIXING LEMMA underlying qDRIFT-style randomized compiling
(`docs/physics/campbell_2019_qdrift.md` cites this paper's Lemma directly as an
alternative derivation route — "a very similar upperbound can be found by
employing the Hastings-Campbell mixing lemma"). Sturm's use is the ABSTRACT
pattern, not gate synthesis specifically: whenever a library HOF (`evolve!`,
future gate-synthesis passes) has several candidate unitaries near a target and
can choose among them with some probability distribution, this lemma is the
generic tool converting "each candidate is `a`-close" + "the WEIGHTED AVERAGE is
`b`-close" into a diamond-norm bound `a² + 2b` on the resulting MIXED CHANNEL —
strictly better than the `O(a)` bound any single deterministic choice gets. This
is the formal justification for why Sturm should prefer channel-level
(Choi/diamond) composition over unitary-level comparison whenever randomization
is in play (CLAUDE.md principle 12).

## Setup and norms (paper §"Notation")

Operator norm `‖X‖` = largest singular value; Schatten-1 (trace) norm `‖X‖₁` =
sum of singular values; diamond norm
`‖𝓔‖_◇ := sup{‖(𝓔⊗id)(X)‖₁ : ‖X‖₁ ≤ 1}`; diamond DISTANCE
`d_◇(𝓔,𝓔') := ½‖𝓔-𝓔'‖_◇`. Key general fact used throughout (paper Eq. after
"Notation", citing Wang '13/'15): for unitary channels `𝓤,𝓥` induced by unitaries
`U,V`,

    d_◇(𝓤, 𝓥) ≤ ‖U - V‖                                                    (UB)

— unitary-operator-norm closeness UPPER-bounds diamond distance (never a lower
bound in general: `U = -V` gives `‖U-V‖=2` but `𝓤=𝓥` exactly, `d_◇=0` — the
global-phase-invisible-to-channels fact, directly resonant with Sturm's own U(2)
double-cover discipline, PRD-v2 §4.3/CLAUDE.md phase discipline).

## The mixing lemma (paper §"The mixing lemma", `Lem. mainLem`, page 3)

**Statement (verified against the tex, exact constants).** Let `V` be a target
unitary with channel `𝓥(ρ) = VρV†`. Let `a, b > 0` and `{U_1,…,U_n}` unitaries
such that:

1. `‖U_j - V‖ ≤ a` for all `j` (every candidate is individually `a`-close);
2. there exist `p_j > 0`, `Σ_j p_j = 1`, with `‖(Σ_j p_j U_j) - V‖ ≤ b` (the
   WEIGHTED-AVERAGE OPERATOR is `b`-close — note this is an operator-norm bound
   on the average of the unitaries themselves, not yet a channel statement).

Then the mixed channel `𝓔 = Σ_j p_j 𝓤_j` (i.e. `𝓔(ρ) = Σ_j p_j U_j ρ U_j†`)
satisfies

    ‖𝓔 - 𝓥‖_◇  ≤  a² + 2b                                                  (ML)

**Proof sketch (paper, immediately following the lemma statement — verified).**
Set `δ_j := U_j - V` (so `‖δ_j‖ ≤ a`); condition (2) gives `‖Σ_j p_j δ_j‖ ≤ b`.
Diamond norm is unitarily invariant, so `d_◇(𝓔,𝓥) = d_◇(𝓥†∘𝓔, id)`. Expanding
`𝓥†∘𝓔` in `δ̃_j := V†δ_j` and dropping the identity term leaves three pieces per
`j`: `p_j(δ̃_j X + Xδ̃_j† + δ̃_j X δ̃_j†)`. Hölder + `‖X‖₁ ≤ 1` bounds the first two
summed pieces by `b` each (via condition 2, cross terms sum to `2b`) and the third
by `Σ_j p_j‖δ̃_j‖‖δ̃_j†‖ ≤ a²` (via condition 1, since `‖δ̃_j‖ = ‖δ_j‖ ≤ a` — unitary
invariance again). Tensoring with the identity to promote to the diamond norm
does not change the bound. Total: `a² + 2b`, exactly as claimed — this is the
"norm used" the task asks to pin: the RHS is diamond norm `‖·‖_◇` (not distance;
no extra `1/2`), and the two contributing terms are literally `a²` (one power,
squared) and `2b` (linear, doubled) — an asymmetric bound that rewards making the
AVERAGE close (`b` enters linearly-times-2) even more than making every candidate
individually close (`a` enters quadratically, so small `a` helps twice as much
per unit as one might naively guess, but `b` is the term you can drive to `O(a²)`
by choice of weights, which is exactly what the paper's two theorems do).

## The two headline theorems built on the lemma (paper §"Results")

**Theorem `genThm`** (general unitary synthesis, e.g. arbitrary `SU(D)`/single-
qubit rotations from Clifford+T): given a synthesis algorithm achieving
`‖U-V‖ ≤ ε` at worst-case cost `f(ε)`, there is a mixed channel of `U_j`'s each
still costing ≤ `f(ε)` with

    d_◇(𝓔, 𝓥) ≤ 10ε²   (for ε < 0.01)                                     (GenDD)

via a convex-hull-finding construction (`c := ‖H_j‖ ≤ 3ε + 7ε²` for the principal
log `H_j := -i log(V†U_j)`, then `a = c + c²/2`, `b = c²/2` fed into (ML), giving
`½(a²+2b) ≤ 10ε²` after the `ε<0.01` simplification — note `d_◇`, the DISTANCE,
picks up the extra `½` here relative to raw (ML)).

**Theorem `axialThm`** (single-qubit axial/Z-rotations specifically, with Pauli Z
free): a cheaper 4-unitary mixture (`U_1,U_2` plus their Z-conjugates `U_3=ZU_1Z`,
`U_4=ZU_2Z`) gives `a = 2ε`, `b = 3ε²`, hence

    d_◇(𝓔, 𝓥) ≤ 5ε²   (for ε < 0.01)                                      (AxialDD)

**Note on the source tex:** the theorem STATEMENT (labeled `AxialDD`, in the
`axialThm` environment) gives `5ε²`, but the final derivation sentence right
after (unlabeled, following "Applying the Lemma, our channel satisfies") has a
typo reading `d_◇(𝓔,𝓥) ≤ ½(a²+2b) ≤ 5ε⁵`. Arithmetic check: `a=2ε ⇒ a²=4ε²`,
`b=3ε² ⇒ 2b=6ε²`, so `½(a²+2b) = ½(4ε²+6ε²) = 5ε²` — confirms `5ε²` (matching the
theorem statement and the abstract's "factor 1/2 reduction... $5\epsilon^2$"
framing) is correct and `5ε⁵` is a stray typo in that one line of the arXiv
source, not a second result.

Either way the scaling is the paper's headline: **mixing turns `O(ε)`-close
unitary approximants into an `O(ε²)`-close CHANNEL**, at no extra resource cost —
the same coherent-to-incoherent error conversion Hastings proves independently
(`docs/physics/hastings_2016_incoherent_errors.md`) and qDRIFT exploits at scale.

## Used by Sturm for

- **qDrift strategy in `evolve!`**: this paper's mixing lemma is the alternate,
  general-purpose derivation route qDRIFT's own Theorem 1 cites as equivalent —
  useful if Sturm ever needs a bound for a NON-uniform-angle randomized
  Hamiltonian-simulation channel that doesn't fit qDRIFT's fixed-`τ` structure
  exactly; (ML) is the tool to reach for.
- **Diamond-norm error composition of the composite channel**: (ML)'s exact
  constants (`a² + 2b`, no extra factors) are the reusable inequality for any
  Sturm library HOF that mixes several near-target unitaries into a channel —
  the general template is "bound each candidate's unitary distance (`a`), bound
  the weighted-average operator's distance (`b`), get an `a²+2b` diamond bound
  on the mixed channel" — and the worked `axialThm` case is a template for the
  common special case of mixing a small FIXED-SIZE ensemble (4 unitaries here)
  rather than solving a general convex-hull search.
