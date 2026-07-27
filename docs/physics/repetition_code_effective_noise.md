# Effective logical noise of the `[[3,1,1]]` bit-flip code — in-repo derivation

> ⚠ **This is an IN-REPO DERIVATION NOTE, not a paper distillation.** No paper
> is being summarised and nothing here is quoted from a source. Everything below
> is derived from the stabilizer machinery distilled in
> `docs/physics/gottesman_1997_stabilizer_codes.md` (§3.2, eqs (3.9)–(3.13)) and
> the channel formalism in
> `docs/physics/watrous_2018_channel_representations.md` (§2.2.2). Synthesis
> `docs/design/m11-82su-synthesis.md` §7 item **P6** asks for exactly this file
> and asks that it be labelled as such; PRD-v2 §9 lists it the same way.
>
> **Cite it as a derivation.** A docstring pointing here is saying "the algebra
> is written out and checked in the repo", not "a paper says so".

**Verification status.** Every closed form below was checked by exact rational
(`fractions.Fraction`) enumeration over the full error group — all `2³` bit-flip
patterns, all `2³` phase patterns and all `4³ = 64` Pauli patterns — at
`p ∈ {1/100, 1/10, 3/10, 1/2, 3/5, 1}`, agreeing exactly (no floats involved).
The endpoint `p = 1` is the sharpest of these: physical `depolarizing(1)` must
give the **logical** completely depolarizing channel, and it does
(`p_I = p_X = p_Y = p_Z = 1/4`).

---

## 1. The code

`n = 3`, `k = 1`, so `S` has `n − k = 2` generators
(`gottesman_1997_stabilizer_codes.md` §3.2, p. 18):

    M₁ = Z₁Z₂,   M₂ = Z₂Z₃          (both sign +1)
    X̄  = X₁X₂X₃
    Z̄  = Z₁      (≡ Z₂ ≡ Z₃ mod S)

`S = {I, Z₁Z₂, Z₂Z₃, Z₁Z₃}` — abelian, `−1 ∉ S`, the two generators are
independent over GF(2), so `dim T = 2^k = 2` (§3.2 p. 18).

Invariant checks (S17 (4)–(6)): `X̄` commutes with both generators (`X₁X₂X₃` vs
`Z₁Z₂` anticommutes twice ⇒ commutes; same for `Z₂Z₃`), so `X̄ ∈ N(S)`; `Z̄ = Z₁`
commutes with both (all `Z`-type), so `Z̄ ∈ N(S)`; neither is in `S`; and
`{X̄, Z̄} = 0` because `X₁X₂X₃` and `Z₁` anticommute on qubit 1 only. ✓ (3.13).

**Distance is 1.** By §3.2 (pp. 19–20), the distance is `d` iff `N(S) − S`
contains no element of weight `< d`. `Z₁ ∈ N(S) − S` has weight 1, so `d = 1`
— and by §2.3 (p. 15) *every* code has distance at least one, so `d = 1` exactly.
By the same paragraph, a code correcting `t` arbitrary errors needs `d ≥ 2t+1`,
so this code corrects **`t = 0` arbitrary errors**. It corrects the *declared*
set `{I, X₁, X₂, X₃}`, which is a different (weaker) statement.

This is what `M11.CODE.DISTANCE-IS-ONE` pins, and why the suite must refuse to
call this a "distance 3" code. The `[[3,1,3]]` you may remember does not exist;
`[[3,1,1]]` is a **bit-flip-only** code.

## 2. Encoder and codewords

    |0̄⟩ = |000⟩,   |1̄⟩ = |111⟩,   α|0⟩ + β|1⟩ ↦ α|000⟩ + β|111⟩

realised in surface vocabulary by two entangling actions and nothing else:

```julia
q2 ⊻= q1
q3 ⊻= q1
```

Both `|000⟩` and `|111⟩` are `+1` eigenvectors of `Z₁Z₂` and `Z₂Z₃`, so the image
is the joint `+1` eigenspace `T`, as `M11.QECC.CODESPACE` asserts. `X̄` maps
`|0̄⟩ ↔ |1̄⟩`; `Z̄ = Z₁` gives `|0̄⟩ ↦ |0̄⟩`, `|1̄⟩ ↦ −|1̄⟩`. ✓

## 3. Syndrome and the recovery table

By (3.9), the syndrome bit for generator `M` is `f_M(E) = 1` iff `{M, E} = 0`.
`X_i` anticommutes with `Z_j` iff `i = j`, so for a bit-flip pattern
`x = (x₁,x₂,x₃) ∈ F₂³` (meaning `E = X^x`):

    f(x) = ( x₁ ⊕ x₂ ,  x₂ ⊕ x₃ )

Writing the syndrome as the integer `σ = f₁ + 2f₂`:

| `x` | weight | `f(x)` | `σ` |
|---|---|---|---|
| `000` | 0 | (0,0) | 0 |
| `100` | 1 | (1,0) | 1 |
| `010` | 1 | (1,1) | 3 |
| `001` | 1 | (0,1) | 2 |
| `110` | 2 | (0,1) | 2 |
| `101` | 2 | (1,1) | 3 |
| `011` | 2 | (1,0) | 1 |
| `111` | 3 | (0,0) | 0 |

**Minimum-weight table** (this is the table `bit_flip_code()` must carry, and it
is what the acceptance example's `@cases` arms implement):

    σ = 0 → I      σ = 1 → X₁      σ = 3 → X₂      σ = 2 → X₃

Ruling **S20**'s self-validation is `syndrome(code, corrections[σ]) == σ` for
every `σ ∈ 0:3`, which the table above satisfies by construction. Note what it
does **not** check: that each entry is minimum-weight. Both `X₁` (σ=1) and `X₂X₃`
(σ=1) are valid coset representatives — Gottesman §3.2 p. 20 says any operator
*"equivalent to it by multiplication by `S`"* fixes the state — but they are
**not** in the same coset here (`X₁ · X₂X₃ = X̄ ∉ S`), so the choice between them
is a *decoder-quality* decision that changes `p_L`. Self-validation catches a
mis-transcribed table; only the physics below catches a *wrong* table.

## 4. Bit-flip noise: `p_L = 3p² − 2p³`

Physical noise `𝓝_p^{⊗3}` with `𝓝_p(ρ) = (1−p)ρ + p XρX`. Pattern `x` occurs
with probability `p^{|x|}(1−p)^{3−|x|}`. The residual after recovery is
`R(f(x)) · X^x`; from the table:

| `x` | correction | residual | logical |
|---|---|---|---|
| `000` | `I` | `I` | `Ī` |
| `100` | `X₁` | `I` | `Ī` |
| `010` | `X₂` | `I` | `Ī` |
| `001` | `X₃` | `I` | `Ī` |
| `110` | `X₃` | `X₁X₂X₃` | **`X̄`** |
| `101` | `X₂` | `X₁X₂X₃` | **`X̄`** |
| `011` | `X₁` | `X₁X₂X₃` | **`X̄`** |
| `111` | `I` | `X₁X₂X₃` | **`X̄`** |

The residual is `X̄` exactly when `|x| ≥ 2`. Hence

    p_L = 3p²(1−p) + p³ = 3p² − 2p³                                       (P1)

and the effective logical channel is **exactly** a logical bit-flip channel,

    Θ(𝓝_p^{⊗3}) = (1 − p_L)·id_L + p_L·Ad_{X̄}  =  bit_flip(3p² − 2p³)     (P2)

with no other Pauli component and no coherence between syndrome sectors. Two
reasons the "exactly" is earned: the physical channel is an *incoherent* Pauli
mixture (Watrous Thm 2.22(4) — the operator-sum is a sum, not a superposition),
and the correction is applied **conditioned on the recorded syndrome**, which is
then not an output port of the `LogicalChannel`, so the sectors add
probabilistically. A residual that differs from `X̄` by a phase is invisible
because `Ad` quotients the phase (PRD-v2 §4.3).

### Break-even

    p_L − p = 3p² − 2p³ − p = −p(1 − 3p + 2p²) = −p(1−p)(1−2p)            (P3)

so on `0 < p < 1`:

- `p < ½`  ⇒ `(1−p) > 0`, `(1−2p) > 0` ⇒ `p_L < p` — **protection**
- `p = ½`  ⇒ `p_L = p = ½` — **exact break-even**
- `p > ½`  ⇒ `(1−2p) < 0` ⇒ `p_L > p` — **correction actively harms**

Values for the tests: `p=0.01 → 0.000298`; `p=0.05 → 0.00725`;
`p=0.1 → 0.028`; `p=0.3 → 0.216`; `p=0.5 → 0.5`; `p=0.6 → 0.648`;
`p=0.7 → 0.784`.

⚠ **`M11.QECC.BREAK-EVEN` must be two-sided.** The `p > ½` branch is physics,
not a curiosity: above break-even the majority vote is more often wrong than
right, so recovery *adds* logical error. A one-sided "protection helps" test
would be passed by a **sign-flipped** recovery table (one that corrects the
majority instead of the minority), which is exactly risk R-d in synthesis §9.
Checking both sides, at the exact analytic values, kills that failure mode.

## 5. Phase noise: the code **amplifies** it

Physical noise `phase_flip(p)^{⊗3}`, `ρ ↦ (1−p)ρ + p ZρZ`, pattern `z ∈ F₂³`.

Every `Z_i` **commutes** with both generators (all `Z`-type), so

    f(z) = (0, 0)   for every z

— **the syndrome is always 0 and no correction ever fires.** The residual is
`Z^z` itself. And every `Z_i` is the logical `Z̄`: `Z₁ ∈ N(S) − S`, and
`Z₁ Z₂ ∈ S` so `Z₁ ≡ Z₂ ≡ Z₃ (mod S)`. Hence the residual acts on the code space
as `Z̄^{|z|}`, which is `Z̄` iff `|z|` is odd:

    p_L^{Z} = Σ_{k odd} C(3,k) p^k (1−p)^{3−k}
            = 3p(1−p)² + p³
            = (1 − (1−2p)³)/2
            = 3p − 6p² + 4p³                                              (P4)

    Θ(phase_flip(p)^{⊗3}) = phase_flip(3p − 6p² + 4p³)                    (P5)

To leading order `p_L^Z ≈ 3p` — **three times worse than doing nothing**. Exactly:

    p_L^{Z} − p = 2p(1−p)(1−2p) = −2 (p_L^{X} − p)                        (P6)

a pleasing exact relation: the phase-noise *excess* is exactly twice the
bit-noise *deficit*, with the opposite sign. (Both vanish at `p = 0, ½, 1`.)

Values: `p=0.1 → 0.244`; `p=0.3 → 0.468`; `p=0.5 → 0.5`; `p=0.6 → 0.504`.

⚠ **This is the wm28-shaped anti-test** (`M11.QECC.PHASE-NOISE-IS-WORSE`). A
population-only probe — encode `|0⟩`, apply noise, decode, measure — is
**completely blind** to it: `Z` errors do not change any computational-basis
population, and the syndrome distribution is identically `δ_{σ,0}`, so every
marginal statistic looks perfect while the logical channel is three times worse
than the bare qubit. Only a channel-level (Choi) comparison sees it. This is
v0.1's teleportation bug in a new costume, and it is why PRD-v2 §12 forbids
marginal-based channel tests.

## 6. Depolarizing noise: the `4³` enumeration

**Convention pin (ruling S8).** `depolarizing(p) : ρ ↦ (1−p)ρ + p·1/2`, i.e.
per-qubit Pauli weights

    q_I = 1 − 3p/4,    q_X = q_Y = q_Z = p/4

Under the `(p/3)ΣPρP` convention every number below changes; the closed forms are
**convention-dependent** and must not be reused without re-deriving.

### The enumerator (this is what the test implements)

For each of the `4³ = 64` patterns `P = P₁⊗P₂⊗P₃`, `P_k ∈ {I,X,Y,Z}` with
symplectic bits `(x_k, z_k)` (`I=(0,0)`, `X=(1,0)`, `Y=(1,1)`, `Z=(0,1)`):

1. probability `Π_k q_{P_k}`;
2. syndrome `σ = f(x)` from §3 — it depends on the **`x` bits only**, because the
   generators are `Z`-type;
3. correction `R(σ)` from the table (always `X`-type), giving residual bits
   `x' = x ⊕ c(σ)`, `z' = z`;
4. `x' ∈ {000, 111}` always, by construction of the table (the correction zeroes
   the syndrome). Assert this — it is a cheap internal consistency check;
5. logical class `X̄^a Z̄^b` with

       a = [x' = 111] = majority(x),    b = z₁ ⊕ z₂ ⊕ z₃

   (`a`: the `X`-part is in `N(S)` only for `000`/`111`, and `111 = X̄`. `b`: mod
   `S` the `Z`-part is defined only up to even-weight vectors, so only its parity
   survives; parity 1 is `Z̄`. Phases are irrelevant — `Ad` forgets them.)

Accumulate into `(p_I, p_X, p_Y, p_Z) = P(a,b)` for `(0,0), (1,0), (1,1), (0,1)`.
This is the **independent reference implementation**
`M11.QECC.INDEPENDENT-REFERENCE` demands — an enumerator, not a pinned number.

### Closed form (derived here as a cross-check, not as the test's oracle)

Let `u = P(x_k = 1) = 2·(p/4) = p/2` (the qubit was `X` or `Y`). Conditioned on
`x_k = 1` the qubit is `X` or `Y` with equal weight, so `z_k` is a **fair coin**;
conditioned on `x_k = 0` it is `I` or `Z` with weights `(1−3p/4, p/4)`. Hence
if **any** qubit has `x_k = 1`, the parity `b` is uniform. Writing
`A := P(a = 1) = P(|x| ≥ 2) = 3u² − 2u³` — the *same* repetition formula (P1),
evaluated at `u = p/2`:

    p_X = p_Y = A/2 = 3p²/8 − p³/8                                        (P7)
    p_Z = [ (1−p/2)³ − (1−p)³ ] / 2  +  (3/2)(p/2)(1−p/2)²
        = 3p/2 − 15p²/8 + 5p³/8                                           (P8)
    p_I = 1 − 3p/2 + 9p²/8 − 3p³/8                                        (P9)

Checks: at `p = 1`, `(p_I,p_X,p_Y,p_Z) = (¼,¼,¼,¼)` — the logical channel is
completely depolarizing, as it must be, since a physically maximally-mixed block
carries no logical information. At small `p`, `p_X = p_Y = O(p²)` (bit-type
errors *are* corrected) while `p_Z ≈ 3p/2 = 3·(p/2)` — three times the per-qubit
phase-error rate `P(z_k = 1) = p/2`, consistent with (P4). Enumerated values:
`p=0.1` gives `(6887/8000, 29/8000, 29/8000, 211/1600)`.

## 7. What the tests pin, and what a wrong implementation looks like

| Claim | Test | What a bug looks like |
|---|---|---|
| (P1)/(P2) | `M11.QECC.EFFECTIVE-NOISE-EXACT` | any deviation at `atol=1e-12` — the formula is exact, not asymptotic |
| (P3) | `M11.QECC.BREAK-EVEN` (two-sided) | a sign-flipped table passes the `p<½` side alone |
| (P4)/(P5) | `M11.QECC.PHASE-NOISE-IS-WORSE` | passes every marginal test while being 3× worse |
| §6 | `M11.QECC.INDEPENDENT-REFERENCE` | enumerator and executed Choi disagree ⇒ table or wiring bug |
| §3 | `M11.QECC.SYNDROME-DISTRIBUTION` | `P(0) = (1−p)³ + p³`, `P(1) = P(2) = P(3) = p(1−p)² + p²(1−p)` |
| §1 | `M11.CODE.DISTANCE-IS-ONE` | witness `Z₁` |

The syndrome distribution in the table above follows directly from §3: syndrome
`0` collects `x ∈ {000, 111}`, and each nonzero syndrome collects exactly one
weight-1 and one weight-2 pattern.

## 8. Scope — what this note does NOT claim

- **Code-capacity model only** (ruling S27). `Θ(𝓝) = D ∘ R ∘ 𝓝 ∘ E` assumes a
  **noiseless** encoder, recovery and decoder and **perfect** syndrome
  extraction. All the noise is in `𝓝`.
- **No fault-tolerance claim, no threshold claim.** The extraction circuit used
  (`a1 ⊻= q1; a1 ⊻= q2`, one ancilla, two entangling actions) is precisely the
  circuit Gottesman §5.2 (p. 38) identifies as **not transversal** — a single
  phase error on the ancilla can feed back into two data qubits. Under a noisy
  extraction model none of the numbers above hold.
- **`p_L < p` is not a threshold.** A threshold statement needs concatenation and
  a fault model (`gottesman_1997_stabilizer_codes.md` §6.2). This is one level,
  perfect gadgets, one code, one noise family.
- **Convention-dependent.** (P1)–(P6) depend on `bit_flip(p)`/`phase_flip(p)`
  meaning `(1−p)ρ + p PρP`; §6 additionally depends on S8's `depolarizing`
  convention. Change a convention and re-derive; do not rescale a number.
- **Not a distance-3 code and not Steane.** The `[[7,1,3]]` reimport is its own
  epic (synthesis §4.2) with its own derivation note.
