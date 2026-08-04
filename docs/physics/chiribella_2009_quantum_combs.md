# Chiribella–D'Ariano–Perinotti 2008–2009 — Quantum Combs and Supermaps (the superchannel factorisation)

One distillation, three papers — the P4 claim set (superchannel = circuit
with a hole; the factorisation `Θ(𝓝) = Tr_M[D ∘ (𝓝 ⊗ id_M) ∘ E]`; the
memoryless case) is split across them, and **which paper proves what is
itself a trap** (G1).

**Sources (local, gitignored; per rule 4 a fresh clone re-downloads):**

1. `docs/physics/chiribella_2008_quantum_circuit_architecture.pdf` —
   margin stamp **`arXiv:0712.1325v1 [quant-ph] 9 Dec 2007`**, *"Quantum
   Circuits Architecture"*; published as **PRL 101, 060401 (2008)**
   (*"Quantum Circuit Architecture"*). 4 pp. Below: **[PRL]**.
2. `docs/physics/chiribella_2008_quantum_supermaps.pdf` — margin stamp
   **`arXiv:0804.0180v2 [quant-ph] 22 Oct 2008`**, *"Transforming quantum
   operations: quantum supermaps"*; published as **EPL 83, 30004 (2008)**.
   6 pp. Below: **[EPL]**.
3. `docs/physics/chiribella_2009_quantum_networks.pdf` — margin stamp
   **`arXiv:0904.4483v2 [quant-ph] 21 Dec 2009`**, *"A theoretical
   framework for quantum networks"*; published as **PRA 80, 022339
   (2009)**. Below: **[PRA]**.

⚠ **Build-date trap (same genus as Gottesman's).** The [EPL] header reads
*"(Dated: October 22, 2018)"* and the [PRA] header *"(Dated: November 26,
2024)"* — `\today` re-expanded when arXiv regenerated the PDFs. The margin
stamps above are authoritative; the header dates are artifacts of when the
file was built. Cite by numbered theorem/equation, never by header date.

## What Sturm uses it for

Synthesis §7 item **P4** (`qecc/superchannel.jl`): the argument that
licenses `effective_logical_noise` as a transformation of channels — a
stratum-2 → stratum-2 map that is neither a channel nor a pass (PRD §4.4),
implemented as a `ChannelDAG` compiler transformation (ruling 82su).

| Sturm claim | Grounded by |
|---|---|
| "superchannel = circuit with a hole" is a real mathematical object | [PRL] pp. 1–3 (circuit board, comb, supermap coined); [EPL] pp. 1–2 (axiomatic def) |
| the factorisation `Θ(𝓝) = Tr_M[D ∘ (𝓝 ⊗ id_M) ∘ E]` — every admissible channel→channel map has this form | **[EPL] Theorem 1, eq. (23)** (proved); N-slot: [PRA] Theorem 3 |
| the memoryless case **is** error correction, in the source's own words | [EPL] Application 1, p. 4 (`dim B = 1`) |
| `Θ = D∘R∘𝓝∘E` *is* a deterministic supermap (the typing direction) | [EPL] axioms: linear + CP + channels→channels, pp. 1–2 |
| a superchannel is not a channel (different type, uncontrollable — PRD §4.4) | the whole framework: supermaps act **on** Choi operators of channels, [EPL] eqs (6)–(7) |
| probabilistic supermaps land in CP-TNI — the postselection regime (PRD §3.6/P1; bead eyho) | [EPL] Theorem 2 + Corollary 1; [PRA] Theorem 4 |

## [PRL] 0712.1325 — combs, link product, and the word "supermap"

- **Circuit board** (p. 1): a network of gates with `N` slots with open
  ports for variable sub-circuits; every board can be reshaped into a
  **comb** — an ordered sequence of slots between teeth (Fig. 3), the order
  being the causal order of information flow. Wires: inputs `2n`, outputs
  `2n+1`, `n = 0..N`.
- **Choi and link product** (p. 2): `C = Choi(𝒞) = 𝒞 ⊗ I(|Ω⟩⟨Ω|)` (eq. 1);
  connecting circuits composes Choi operators by the **link product**
  `C = A ∗ B = Tr_J[A^{θ_J} B]` (eq. 3, Rules 1–3), `θ_J` partial
  transposition over the connected wires. Commutative; `𝒞(ρ) = C ∗ ρ`.
- **Comb normalization** (p. 3, eq. 4): `R ≥ 0` is a deterministic comb iff
  the recursive causality constraints
  `Tr_{2n+1}[R^{(n)}] = I_{2n} ⊗ R^{(n−1)}`, `n = 0..N` hold. **Theorem 1**:
  every such `R` is the Choi operator of a deterministic comb.
- **Supermap coined** (p. 3): the comb sends input circuits to
  `C′ = C_1 ∗ ⋯ ∗ C_N ∗ R`; *"we call the mapping between circuits ...
  supermap as it sends channels into channels, rather than states into
  states."*
- **Probabilistic combs** (p. 4): outcome-`i` combs `R_i` with
  `Σ_i R_i = R` deterministic; realized by a classical register +
  measurement + postselection.

## [EPL] 0804.0180 — the axioms and THE realization theorem

**Axiomatic definition** (pp. 1–2): a **deterministic supermap** sends
channels to channels and must be (i) **linear** (probabilistic mixing of
inputs must commute with the map) and (ii) **completely positive** in the
supermap sense: `S̃ ⊗ I_B` applied to one leg of a *bipartite* quantum
operation must yield a legitimate quantum operation. In the Choi picture
`S̃` induces a linear CP map `S` on Choi operators (eqs (6)–(7)).
Lemma 1 characterises the normalization; **Lemma 2**: `S` is deterministic
iff `S_∗(I ⊗ ρ) = I ⊗ N_∗(ρ)` for a channel `N_∗` — the same structure as
**semi-causal** bipartite operations (Eggeling–Schlingemann–Werner, their
ref [7]): the causality of input-output relations is what forbids the
transformed effect from depending on anything but the input effect
(Lemma 3, eq. (13)).

> **Theorem 1 (realization)** (p. 3, eq. (23), proof eqs (15)–(22)):
> *Every deterministic supermap `S̃` can be realized by a four-port quantum
> circuit where the input operation `E` is inserted between two isometries
> `V` and `W` and a final ancilla is discarded:*
>
>     S̃(E)(ρ) = Tr_A[ W (E ⊗ I_B) (V ρ V†) W† ]
>
> `V : K_in → H_in ⊗ B` and `W : H_out ⊗ B → K_out ⊗ A` isometries, `B` the
> **memory** wire threaded around the hole, `A` discarded at the end
> (Fig. 1).

This is the load-bearing theorem. Dictionary to Sturm's spelling (G2 for
the fine print): `E` (encoding side) `= V·V†`; `D` (decoding side, discard
absorbed) `= Tr_A ∘ W·W†`; memory `M = B`; hence
`Θ(𝓝) = D ∘ (𝓝 ⊗ id_M) ∘ E`. Watrous Exercise 2.6(c), eq. (2.316), is this
theorem at exercise strength (`Ψ = Ξ₁(Φ ⊗ 1_V)Ξ₀`) — and Watrous's p. 123
credit *"a related result of Chiribella, D'Ariano, and Perinotti (2008)"*
resolves to **this** paper, not to [PRL] (see
`watrous_2018_channel_representations.md` G7).

**Application 1 — error correction, memoryless, verbatim** (p. 4):

> *"error correction can be seen as a supermap, now turning a noisy channel
> on a larger Hilbert space into a noiseless channel acting on a smaller
> space. In both cases the supermap is given by the insertion of the input
> channel `E` between two deterministic channels `C` and `D` (the coding and
> decoding maps, respectively), namely `S̃(E) = DEC`, **with the additional
> constraint that the ancilla `B` in Fig. 1 must be one-dimensional**."*

That sentence is P4's whole burden discharged by the primary source:
`effective_logical_noise`'s `Θ(𝓝) = D ∘ R ∘ 𝓝 ∘ E` is the `dim B = 1`
(memoryless) instance of Theorem 1, and CDP themselves name QEC as exactly
this instance. The direction M11 actually *types* with is the easy one —
`D∘R∘𝓝∘E` is linear and CP in `𝓝` and sends channels to channels, so `Θ`
**is** a deterministic supermap. The realization theorem supplies the
converse modelling license: nothing more general than
isometry–memory–isometry exists among admissible channel→channel maps, so
in choosing the memoryless form M11 is giving up **memory across the hole
and nothing else** (the S27 "no correlated / non-Markovian noise"
restriction, stated where the superchannel is defined).

**Probabilistic supermaps** (p. 4): **Theorem 2** — every probabilistic
supermap is the same four-port scheme with an orthogonal projector `P` on
the ancilla `A` (eq. (24), postselection); **Corollary 1 (delayed reading
principle)**: every probabilistic quantum circuit is equivalent to a unitary
circuit with a single orthogonal measurement at the output. This is the
channel-level home of the CP-TNI regime PRD §3.6 reserves for explicit
`postselect` (bead eyho); M11 itself stays deterministic.

## [PRA] 0904.4483 — the general framework (used as the N-slot backstop)

The systematic treatment; M11 needs only the single-slot case, so pins are
kept to what a future multi-slot consumer (combs over `cases`, adaptive
protocols, QECC over sequences) would reach for:

- **Choi–Jamiołkowski + link product done carefully**: Def. 1, Lemmas 1–3
  (TP ⇔ `Tr_{H₁}[M] = I_{H₀}`; Hermitian-preserving ⇔ `M` Hermitian; CP ⇔
  `M ≥ 0`); Def. 2 (general link product, eq. (14));
  **Theorem 1 (composition rules)** `C = N ∗ M`; **Theorem 2** (properties:
  commutative up to swap, associative when each wire set is shared by at
  most two factors, Hermiticity- and positivity-preserving).
- **Networks**: DAG of circuits, total orderings, equivalence with
  sequences of **memory channels** (§III.C, Figs 1–2); Choi operator of a
  network = link product of its vertices (eq. (21)); **Lemma 4
  (normalization)** eqs (22)–(23) and Corollary 1 eq. (24) — the same
  recursive constraint as [PRL] eq. (4).
- **Theorem 3 (realization)** (p. 7): every positive `R^{(N)}` satisfying
  the recursive constraints is the Choi operator of a network realized as a
  **concatenation of `N` isometries `V_j` with the last followed by a
  partial trace over the ancilla** (Fig. 3; induction on the minimal
  Stinespring isometry, eq. (33) giving `W^{(N)} = (I ⊗ √(R^{(N)∗}))|I⟩⟩ ⊗
  I_in`). The `N = 1` case is Stinespring itself; the `N = 2` case
  reproduces [EPL] Theorem 1.
- **Theorem 4** (p. 8): probabilistic networks = `N` isometries + a von
  Neumann measurement on a `k`-dimensional ancilla. The abstract names the
  headline *"universality of quantum memory channels."*

## Gaps, divergences, and traps

**G1 — which paper proves what (do not mis-pin).** [PRL] *asserts* the
realization converse only in endnote **[16]** — *"This can be proved within
an axiomatic introduction of combs and supermaps, where a realization
theorem holds"* — with **no proof in the paper**. The single-slot proof is
[EPL] Theorem 1; the N-slot proof is [PRA] Theorem 3. A citation of the
factorisation to [PRL] alone pins an unproved assertion — exactly the
mis-pin rule 4 exists to prevent. Pin the factorisation to **[EPL] Thm 1**;
pin combs/normalization to [PRL] eq. (4)/Thm 1 or [PRA] Lemma 4/Thm 3.

**G2 — the `Tr_M` spelling.** The PRD writes
`Θ(𝓝) = Tr_M[D ∘ (𝓝 ⊗ id_M) ∘ E]` (D acting on the system leg, the memory
traced at the end); [EPL] eq. (23) writes `Tr_A[W(E ⊗ I_B)(VρV†)W†]` (the
memory `B` consumed *by* the second isometry, a different ancilla `A`
discarded). These are the same object: absorb the discard into the second
map (`D := Tr_A ∘ W·W†`) and no external trace remains, or keep isometries
and trace explicitly. In the memoryless instance the distinction vanishes —
`B = ℂ`, `E` and `D` are the encoding and recovery∘decoding channels, and
`Θ(𝓝) = D∘R∘𝓝∘E` composes as plain channels. Do not "fix" one spelling to
match the other; note the dictionary instead.

**G3 — supermap ≠ channel, structurally.** A supermap acts on the *Choi
operators of channels* ([EPL] eqs (6)–(7)); it is not itself a CPTP map on
states, has no Kraus family on the system, and `ctrl` of it is a type error,
not a missing feature — this is the grounding for PRD §4.4's "neither a
channel nor a pass ... not controllable" sentence. The one legitimate way a
supermap touches execution is *after* it is applied: `Θ(𝓝)` **is** a
channel, and everything downstream treats it as one.

**G4 — what M11 does not import.** The optimization machinery ([PRL]'s
actual headline: convex search over comb Choi operators, cloning of
unitaries `F = (d + √(d²−1))/d³`, algorithm learning/storing–retrieving),
the tester/PPOVM formalism ([EPL] Application 3, [PRA] §V), and the
memory-`B > 1` case are all out of M11's scope. The last is a *stated*
modelling restriction (S27: code-capacity, uncorrelated noise), and the
first two are optimization results, not semantics.

**G5 — finite dimensions.** All three papers work in finite dimension
([PRL] endnote [11]; [EPL] presents Theorem 2 "here presented in finite
dimensions"). Fine for Sturm (P7 registers are finite-d); an
infinite-dimensional generalisation would need different sources.
