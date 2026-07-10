# The Quantum Fourier Transform Has Small Entanglement

Source: J. Chen (陈捷伦), E. M. Stoudenmire, and S. R. White, "Quantum
Fourier Transform Has Small Entanglement", *PRX Quantum* **4**, 040318
(2023). DOI: 10.1103/PRXQuantum.4.040318. arXiv:2210.08468v3 [quant-ph],
27 Oct 2023 (v1 16 Oct 2022). PDF in
`docs/physics/chen_stoudenmire_white_2210.08468.pdf`.

This is the citation PRD-v2 §3.3/§3.4 and D2 (§9) attach to `dual(x)` for
`x::QInt{W}` — the QFT-on-ℤ_{2^W} basis change that underlies the
conjugate view, the Draper adder lowering (`add! = F†∘phases∘F`), and the
modulation family. It grounds ONE load-bearing fact: the QFT is a genuine
entangling basis change — **not a tensor product across any register
cut** — so `dual(x)` (Fourier on ℤ_{2^W}) is a provably different unitary
from the per-wire duals (Fourier on (ℤ₂)^W). Everything else the paper
proves is *good news* about the cost of that basis change, not a claim
Sturm makes on the surface.

**⚠ CITATION HISTORY (r6).** An earlier PRD draft cited this paper
INVERTED — for "maximal entanglement". The paper's title and thesis say
the opposite: the QFT's *core* has SMALL entanglement, and the maximality
seen in the standard QFT is entirely a **bit-reversal artifact**. The
r6-corrected rule (PRD-v2 §9 citation list): cite this paper for
"not a tensor product across any cut / small core entanglement"; if a
*maximality* claim is ever genuinely needed, cite the earlier exact
Schmidt-decomposition results (Tyson 2003; Nielsen et al. 2003 — the
paper's refs [7,8]), NOT Chen–Stoudenmire–White. See the audit note at
the bottom.

---

## The one decomposition everything hangs on (Eqs. 1, 3; pp. 1–2)

The QFT on n qubits is the DFT on the cyclic group ℤ_{2^n} (Eq. 1, p. 2):

```
F_n = (1/√2ⁿ) Σ_{q,q'} exp(i 2π q q' / 2ⁿ) |q⟩⟨q'|         (Eq. 1)
```

with `q = q₁q₂…qₙ` the bit decomposition. The paper's central structural
fact (Eq. 3, p. 2, and Fig. 1 for the 4-qubit circuit):

```
F_n = R_n Q_n                                              (Eq. 3)
```

- `R_n` = the **bit-reversal** permutation `R_n|q₁…qₙ⟩ = |qₙ…q₁⟩`. Pure
  wire relabeling — a permutation (`Perm`), zero gate cost as a
  reindexing.
- `Q_n` = the **core** QFT (the Hadamard + controlled-phase ladder with
  the *output order left reversed*, no swaps).

The entire paper is the contrast between these two factors.

## Result 1 — Standard QFT `F_n` IS maximally entangled, but that is the bit reversal (p. 3)

The paper defines the **operator Schmidt decomposition** (Definition 1,
Eq. 4, p. 2–3): a unitary `U` on `A⊗B` factors as
`U = √N Σ_k σ_k A_k ⊗ B_k`, with `Σσ_k² = 1`, Schmidt rank
`χ ≤ min(dim(A)², dim(B)²)`. The MPO bond dimension needed to represent
`U` is exactly this Schmidt rank across each cut.

Earlier work (refs [7,8] = Tyson 2003; Nielsen et al. 2003) computed the
*exact* operator Schmidt decomposition of `F_n` and found **uniform**
Schmidt coefficients ⇒ `F_n` is **maximally operator-entangled** ⇒ its MPO
bond dimension grows exponentially with n (p. 3). This maximality is real
— but the paper's whole point (abstract, p. 1; Conclusion, p. 13) is that
it is **entirely due to the bit reversal `R_n`**, not to the Fourier
structure.

## Result 2 (THE headline) — the core `Q_n` has exponentially decaying Schmidt coefficients (Theorem 1, Corollary 1; p. 3)

Partition into `A` = qubits `1..j`, `B` = qubits `j+1..n`. The core
factorizes as `Q_n = √2ⁿ Σ_k σ^k_{n,j} A^k_{n,j} ⊗ B^k_{n,j}` (Eq. 5).

**Theorem 1** (exponential decay, p. 3): as `n → ∞`, for `k ≥ 2`,

```
σ̃^k_j ≤ (1/√k) exp( −((2k+1)/2) log( (4k+4)/(eπ) ) )        (Eq. 6)
```

i.e. the Schmidt coefficients fall off faster than exponentially in the
index `k`. Eq. 26 (p. 5) extends this to finite `n` under a mild
assumption. Eq. 7 (majorization, p. 3) shows *smaller* systems are *more*
concentrated: `Σ_k(σ^k_{n+1,j})² ≤ Σ_k(σ^k_{n,j})²`.

**Corollary 1** (Constant entanglement in the QFT, p. 3): the operator
Rényi entropy `H_α(n,j)` of the core `Q_n` is bounded by a **constant for
all α>0 and all n, j** (Eq. 8). The core entanglement does not grow with
qubit count.

*Proof route (§II B, pp. 4–6):* `Q_n = (I_j⊗Q_{n-j}) Ω_{n,j} (Q_j⊗I_{n-j})`
(Eq. 9); the flanking sub-QFTs are local unitaries, so the cut's Schmidt
spectrum is carried entirely by the diagonal cross-partition
controlled-phase block `Ω_{n,j}` (Eq. 10). Its Schmidt coefficients equal
the singular values of the top-left `2^j × 2^{n-j}` **submatrix**
`F_{n,j} = F_n[0:2^j−1, 0:2^{n-j}−1]` (Eqs. 11, 17, 18). The positive
matrix `T_{n,j} = F_{n,j}F_{n,j}†` (Eq. 19) is the discrete **spectral
concentration** operator whose eigenvectors are the (periodic) **discrete
prolate spheroidal sequences** (DPSS / P-DPSS, Eqs. 21–24) — a classic
signal-processing object whose eigenvalue decay bounds (Eq. 25) are known.
That is where the exp-decay bound comes from.

## Result 3 — the area-law intuition (§II C, p. 6)

Stripping the H gates from `Q_n` gives `Q^P_n`, a product of
controlled-phase gates, which equals **time evolution for time `t = π`**
under

```
H^P_n = − Σ_{l<m} (1/2)^{m−l} |1⟩⟨1|_l ⊗ |1⟩⟨1|_m               (Eq. 36)
```

— a Z–Z Hamiltonian with **exponentially decaying** (1/2^{m−l}, faster
than 1/r²) interactions. Dynamics under such short-range interactions
obey a variant of the area law, so the entanglement change is bounded by a
constant: `ΔS_j = |S_j(Q^P_n|ψ⟩) − S_j(|ψ⟩)| ≤ O(1)` (Eq. 37). This is
the physical *why* behind Theorem 1.

## Result 4 — the QFT-MPO and classical timing (§III–IV, pp. 7–13)

The core compresses to a **matrix product operator of tiny, essentially
constant bond dimension**. Constructing the QFT-MPO from the QFT tensor
network (zip-up algorithm) costs `O(χ³ n²)` time with truncation error
`O(n e^{−χ log(χ/3)} / √χ)` (§III B, p. 8). Concrete numbers (p. 10):

- **Bond dimension χ = 8 is sufficient for double precision** (abstract;
  at n=9, χ=8 gives error 3.2 × 10⁻¹⁶). Error decays *exponentially* in χ
  at fixed n (n=9: χ=5,6,7,8 → 3.1e-8, 9.4e-10, 2.0e-13, 3.2e-16) and only
  *linearly* in n at fixed χ (χ=4: n=7..10 → 2.3e-6 … 8.3e-6).
- A **50-qubit** QFT-MPO builds in ≈ 1 second on a laptop (ITensor).
- QFT-as-classical-transform beats the FFT for *compressible* data past a
  crossover near **n ≈ 18**, by orders of magnitude at large n (Fig. 4).

**Hard limit the paper states itself (Conclusion, p. 13):** this does
**NOT** mean the QFT is efficiently classically simulable in general.
Applied to a *general* input state (e.g. the states inside Shor's
algorithm) the MPS blows up exponentially; only the **operator** `Q_n` is
low-entanglement, not every state it acts on. For random data the MPS
bond dimensions saturate and the QFT gives no advantage over FFT (p. 12).

---

## Relevance to Sturm v2

1. **Grounds D2's load-bearing claim: `dual(x)` ≠ per-wire duals.**
   `dual(x)` for `x::QInt{W}` is `F_W` = the DFT on ℤ_{2^W} (Eq. 1); the
   per-wire duals are the (ℤ₂)^W Fourier `H^⊗W` = `pm^⊗W` (Qwerty's
   `fourier[N] ≠ pm^⊗N`). Result 1 (uniform Schmidt spectrum ⇒ the QFT
   is **not a tensor product across any register cut**) is exactly what
   makes these **provably different unitaries** — so `dual(x[3])` (ℤ₂ dual
   of a slice) is genuinely not "wire 3 of `dual(x)`" (no such local
   object exists). Cite Chen–Stoudenmire–White for the
   *not-a-tensor-product* half of this; that half is the fact D2 actually
   needs.

2. **Small core entanglement is GOOD NEWS for the M6 lowerings.** The
   Draper adder lowers as `add!(x, a) = F† ∘ D_a ∘ F` (`F†D_aF = T_a`,
   re-derived in r6). Result 2/4 says the operator `F` — its core `Q_n` —
   has **constant** operator entanglement and a **χ ≈ 8 MPO**; the
   bit-reversal `R_n` is a pure `Perm` (wire relabel), never an entangling
   cost. So materializing the conjugate-view basis change as a *process*
   value, or representing `F` in the channel IR, is cheap in bond
   dimension — the "100 lines that die in the kernel" lower to a
   well-conditioned, low-rank object. This licenses Sturm to treat the
   QFT-basis view as a lightweight addressing mode, not a heavyweight
   circuit.

3. **The DFT definition (Eq. 1) is the group F_G that fixes the view.**
   The paper confirms `F_W` is the character-group Fourier transform on
   ℤ_{2^W} — the F_G that PRD §3.3 (Pontryagin duality table) hands to
   `view(F_G, q)`. It underwrites, at the level of *what F is*, the
   process-vs-view distinction: as a DFT matrix `F²` is the parity/reversal
   permutation and `F⁴ = 1` (standard DFT fact, visible from Eq. 1 — the
   paper does not prove this but its definition entails it), so applying
   `F` twice negates every integer, while the *view* `dual(dual(x)) === x`
   unwraps structurally. That is the normative integer-negation signature
   test (M6).

4. **What the paper does NOT license — three guardrails.**
   - It does **NOT** license calling the QFT "maximally entangling" as an
     intrinsic property. Per the paper the maximality is a **bit-reversal
     artifact**; the Fourier structure itself (`Q_n`) is small. For a
     *maximality* claim, cite Tyson 2003 / Nielsen et al. 2003 (refs
     [7,8]), never this paper.
   - It does **NOT** license any "the QFT / Draper adder is classically
     cheap" *algorithmic* claim. The small entanglement is of the
     **operator** `Q_n`; on the entangled states inside real algorithms
     (Shor) the MPS is exponential (Conclusion, p. 13). Sturm may say the
     *basis-change operator* is low-bond-dimension; it may not say the
     computation using it is classically simulable.
   - It bears on `QInt{W}`'s ℤ_{2^W} dual only. It says nothing about the
     per-wire (ℤ₂)^W duals, nor about `dual` being a *passive view* — that
     zero-cost involutive reading is Sturm's own contribution (with Qwerty
     / ASDF as the nearest, non-view, prior art). The decay bound
     Eq. 6 is for `k ≥ 2` (the leading σ⁰ is not covered); quote "χ ≈ 8
     for double precision", not "rank 8 exactly".

---

## ⚠ CITATION AUDIT — verdict against the r6-corrected wording

The r6 rule (PRD-v2 §9, ~line 1558): *"corrected use — the paper shows the
QFT's core operator entanglement is SMALL (bit-reversal artifact aside);
cite it for 'not a tensor product across any cut', or cite the early
results (Tyson 2003; Nielsen et al. 2003) if a maximality claim is ever
needed; the small-entanglement reading is good news for QFT-based
lowerings."* This distillation **confirms** that wording is faithful to
the paper: title, abstract, Theorem 1, Corollary 1, and the Conclusion all
support "small core entanglement, maximality = bit-reversal artifact."

**One residual inversion still in the PRD body.** D2's prose (PRD-v2
§9, ~line 1360) reads: *"…provably different unitaries (**the QFT has
maximal operator entanglement across every register cut**:
Chen–Stoudenmire–White, arXiv:2210.08468…)."* This attributes a
**maximality** claim to this paper — precisely the attribution r6's own
§9 list says to avoid (use Tyson/Nielsen for maximality). The *factual*
statement is not wrong (the standard `F_n` genuinely is maximally
entangled across cuts — Result 1), but D2 does not need "maximal": its
argument only needs "not a tensor product / entangles across every cut",
which is the honest Chen–Stoudenmire–White reading. Recommended fix
(non-normative, flagged for the M6 3+1 round, not applied here — I own only
`docs/physics/`): in D2, either soften "maximal operator entanglement" →
"is not a tensor product across any register cut" (keeping the
Chen–Stoudenmire–White cite), or keep "maximal" and re-attribute to Tyson
2003 / Nielsen et al. 2003. The corrected §9 citation-list entry itself is
sound and needs no change.
