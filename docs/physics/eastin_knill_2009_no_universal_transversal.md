# Eastin & Knill 2009 — Restrictions on Transversal Encoded Quantum Gate Sets

**Source (local, gitignored):**
`docs/physics/eastin_knill_2009_no_universal_transversal.pdf`. Per rule 4 the
PDF is not committed; a fresh clone will not have it — re-download from
arXiv:0811.4262, do not commit it.

**Version pin (read off the document itself).** Margin stamp:
**`arXiv:0811.4262v2 [quant-ph] 9 Jul 2009`**. Bryan Eastin and Emanuel
Knill, NIST Boulder. Published as **PRL 102, 110502 (2009)**. Four pages;
the only *numbered* display is Eq. (1) — everything else is pinned below by
lemma/theorem/corollary and page of the local v2 build. The paper is a US
government (NIST) work — the last line of the acknowledgments states it is
*"not subject to US copyright"* — but rule 4 is uniform: the PDF stays
untracked regardless.

## What Sturm uses it for

The **only** result this file is cited for: `fault_tolerant_lift`'s refusal
(PRD-v2 §5, P6 restatement; synthesis §7 item **P5**; `qecc/ft.jl`) is a
**theorem**, not an engineering gap.

| Sturm claim | Grounded by |
|---|---|
| no universal transversal encoded gate set exists (for any code that detects an arbitrary single-subsystem error) | Corollary 1 (p. 3) |
| ...even for product (not just transversal) logical unitaries | Theorem 1 (pp. 2–3) |
| the refusal's five-ingredient list is the paper's own circumvention catalogue | pp. 3–4 (see below) |
| finite transversal logical groups (e.g. transversal Cliffords) are *consistent* with the theorem | proof of Theorem 1 (F is finite) + p. 4 |
| ⚠ the hypothesis is load-bearing: the M11 bit-flip code does **not** satisfy it | G1/G2 below |

## Definitions (p. 1, all verbatim-close)

- **Detectable:** an error `E` is detectable iff `PEP ∝ P`, `P` the projector
  onto the logical subspace (unnumbered display, p. 1).
- **Block:** *"a collection of subsystems for which errors on subsystems in
  the collection are detected independently of those on subsystems outside
  of it."*
- **Transversal partition:** *"any partition of the physical subsystems of a
  code such that each part contains one subsystem from each code block."*
  An operator is **transversal** if *"it exclusively couples subsystems
  within the same part"* — equivalently, it couples no subsystem of a block
  to any but the corresponding subsystem in another block.
- Why transversal ⇒ fault tolerant (p. 1): transversal operators *"can
  spread errors between code blocks ... but, since errors on different code
  blocks are treated independently, the total number of errors necessary to
  cause a failure is unchanged."*
- **Local-error-detecting code** (p. 2): a code *"capable of detecting an
  arbitrary error on any single subsystem."* For a distance-`d` code this is
  exactly `d ≥ 2`.
- **Logical unitary** (p. 2, Eq. (1)): `U` preserves the code space iff
  `(I − P)UP = 0`.

## The result

**Lemma 1** (p. 2). The logical unitaries form a group. (Direct
verification; the closure step is `PUVP = PUPVP = UPVP = UVP`.)

**Lemma 2** (p. 2). The logical operators contained in a Lie group of
unitaries form a Lie subgroup. (Logical-ness, Eq. (1), is a closed condition;
Cartan's closed-subgroup theorem — their ref [11], Sepanski, *Compact Lie
Groups*, p. 3.)

**Theorem 1** (pp. 2–3). *For any nontrivial local-error-detecting quantum
code, the set of logical unitary product operators is not universal.*

Proof skeleton, kept here because every step is load-bearing for G1/G2:

1. `T = ⊗ⱼ U(dⱼ)` (product unitaries) is a compact Lie group; `G = T ∩ L`
   is a Lie subgroup (Lemma 2). Let `C` be the identity component of `G`,
   `c` its Lie algebra.
2. For `D ∈ c`, differentiating `(I − P)e^{iεD}P = 0` at `ε = 0` gives
   `(I − P)DP = 0`.
3. `c ⊆ t`, so `D = Σⱼ αⱼHⱼ` with `Hⱼ` Hermitian **on subsystem j alone**.
   *"Any local Hermitian operator can be written as a sum over local error
   operators, so `PHⱼP ∝ P`"* — **this is the only step that uses local
   error detection.**
4. Hence `DP = PDP ∝ P`, so every `C ∈ C` has `CP ∝ P` with constant 1 by
   unitarity: **the identity component acts trivially on the code space.**
5. `Q = G/C` is discrete; a set `F` of coset representatives is a discrete
   subset of the compact `T`, hence **finite**; every `G ∈ G` acts on the
   code space as some `F ∈ F`.
6. A nontrivial encoded system has uncountably many logical unitaries; a
   finite set cannot approximate them to arbitrary precision. Footnote 2:
   this does *not* contradict Solovay–Kitaev — the induced logical set is
   finite **and closed under composition**, so *"composition yields nothing
   new."*

**Corollary 1** (p. 3). Replace "subsystem" by "transversal part": *for any
nontrivial local-error-detecting quantum code, the set of transversal,
logical unitary operators is not universal.* (An arbitrary error on one
transversal part is a single-subsystem error on each block, so the
hypothesis transfers.)

**Assumptions, stated in the conclusion (p. 4):** subsystem dimensions
finite; the encoded system nontrivial (dimension > 1); *"the precise
structure of the quantum code and its initialization state are
unspecified"*; gates **unitary**.

## The circumvention catalogue (pp. 3–4) → the refusal's ingredient list

The paper closes by enumerating exactly the doors the theorem leaves open.
`fault_tolerant_lift`'s refusal (ruling S26) names five ingredients a caller
must supply; each is one of these doors:

1. **Non-unitary operations** (measurement, classical feed-forward,
   ancilla preparation/testing — their refs [14] Knill, [15] Bravyi–Kitaev,
   [16] Zhou–Leung–Chuang): *"The standard method of achieving universal
   fault-tolerant quantum computation takes this approach."* → the
   **magic-state / gate-teleportation protocol** ingredient.
2. **Non-transversal but fault-tolerant gates** — coordinate permutations
   (refs [6] Zeng–Cross–Chuang, [7] Chen et al., [17] Bacon). ⚠ Their
   warning: on Bacon–Shor codes *"some sequences of encoded Hadamard and
   controlled-NOT gates are not fault tolerant"* — strict fault tolerance
   needs error-checking *before* coupling blocks under a new transversal
   partition. → the **gadget set with a per-code transversality
   declaration** and the **extraction schedule** ingredients.
3. **Sub-universality**: finite transversal groups (e.g. Cliffords for
   suitable codes) are fine — the theorem itself only caps the logical
   action at a *finite group*, it does not forbid one. → why a
   transversality *declaration* is per-gate-per-code, not a boolean.
4. **Non-deterministic detection**: codes whose single-subsystem detection
   fails with vanishing probability evade the hypothesis. (No known
   construction is cited; listed as open.)

The remaining refusal ingredients — **fault model** and **threshold
accounting** — are outside this paper; Gottesman §5–§6
(`gottesman_1997_stabilizer_codes.md`) supplies their shape.

## Gaps, divergences, and traps

**G1 — the hypothesis is load-bearing, and the short slogan overclaims.**
"No code admits a universal transversal gate set" is **false** as an
unqualified sentence: a code that detects nothing escapes the theorem —
trivially, the identity encoding on one subsystem (one block, one part)
makes *every* unitary transversal and universality is immediate. The
theorem needs **nontrivial** (encoded dim > 1) and **local-error-detecting**
(arbitrary single-subsystem errors detectable; `d ≥ 2` for distance-`d`
codes). The PRD-v2 §5 refusal text was tightened to carry the hypothesis
(2026-08-04, this distillation's session). Step 3 of the proof is where a
`d = 1` code walks through: some local Hermitian `Hⱼ` has `PHⱼP ∝̸ P`, the
Lie algebra `c` picks up a nontrivial logical direction, and the identity
component acts *non*-trivially.

**G2 — the M11 acceptance-example code violates the hypothesis (sentinel).**
The `[[3,1,1]]` bit-flip code has `d = 1`: single-qubit `Z` is undetectable
(`PZ₁P = Z̄P`, not `∝ P`). And exactly as G1 predicts, it has a
**continuous transversal logical family**: `e^{iθZ₁}` acts on
`span{|000⟩, |111⟩}` as `e^{iθZ̄}` up to phase. So Eastin–Knill **does not
apply to the bit-flip code**, and `fault_tolerant_lift`'s docstring must not
imply that it does. The honest split: the *generic* refusal is E–K
(Corollary 1, for any `d ≥ 2` code a caller might bring); for the bit-flip
code itself, non-universality of transversal gates is elementary and
E–K-free — a product operator maps `|000⟩` to a product state, while
`α|000⟩ + β|111⟩` (`αβ ≠ 0`) is entangled, so the transversal logical group
is only `⟨e^{iθZ̄}, X̄⟩`, nowhere dense in `U(2)`. Either way the refusal
stands; only the *citation* differs.

**G3 — unitary-only, existence-only.** The theorem says nothing about
measurements or feed-forward (that door is its own circumvention #1), and
derives no quantitative accuracy bound — step 6 is a pure
finite-can't-approximate-infinite argument. Do not cite this file for
thresholds, noise models, or magic-state costs.

**G4 — stabilizer-code precursors.** Zeng–Cross–Chuang (arXiv:0706.1382)
proved the qubit stabilizer case, Chen–Chung–Cross–Zeng–Chuang (PRA 78,
012353 (2008)) the qudit stabilizer case. Eastin–Knill subsumes both: no
assumption on code structure, any finite subsystem dimensions. Cite this
file, not the precursors, for the general no-go.

**G5 — relation to Gottesman.** Gottesman §5.1 (p. 38) defines
transversality and exhibits transversal gate sets; Gottesman §5.2 (p. 38)
shows the naive shared-ancilla syndrome extraction is non-transversal.
Nothing in the 1997 thesis contains (or could contain) this 2009 no-go —
see `gottesman_1997_stabilizer_codes.md` **G2**, whose IOU this file
discharges.
