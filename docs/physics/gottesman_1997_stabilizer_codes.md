# Gottesman 1997 — Stabilizer Codes and Quantum Error Correction (PhD thesis)

**Source (local, gitignored):** `docs/literature/quant-ph_9705052.pdf`, with the
**LaTeX source** at `docs/literature/quant-ph_9705052_src/Thesis.tex` (6304
lines) + `Thesis.sty` + `Capacity.eps`. Per rule 4 (changed 2026-07-25) neither
the PDF nor the source is committed; a fresh clone will not have them.

**Version pin (read off the document itself).** arXiv stamp in the left margin
of p. 1: **`arXiv:quant-ph/9705052v1  28 May 1997`** (this is also the PDF's
`Title` metadata). LaTeX source: `\title{Stabilizer Codes and Quantum Error
Correction}`, `\author{Daniel Gottesman}`, `\date{May 21, 1997}`. California
Institute of Technology, Pasadena; submitted 21 May 1997; advisor John Preskill.

⚠ **Two build traps.** (1) The title page and copyright page of the local PDF
read **"2024"**, not 1997 — `Thesis.sty` typesets `\the\year`, and arXiv
regenerates the PDF from TeX on download (Producer: `GPL Ghostscript 10.01.2`,
CreationDate 2024-11-26, dvips 5.86). The document is still v1 of May 1997; the
year on the cover is an artifact of *when you downloaded it*. (2) Because the
PDF is regenerated from source, **page numbers are in principle build-dependent**
while **section and equation numbers come from the source and are stable.**
Prefer equation numbers. Page numbers below are from the local 122-page build
and are given as a convenience.

**Quoting policy.** This project quotes `.tex` where it can (it removes
transcription risk). Displayed equations below were taken from `Thesis.tex` and
cross-checked against the compiled PDF for their numbers.

## What Sturm uses it for

The **only** external source M11's QECC slice needs (synthesis
`docs/design/m11-82su-synthesis.md` §7 item **P2**; PRD-v2 §9 Citations TODO).
It grounds, section by section:

| Sturm object (M11) | Grounded by |
|---|---|
| `StabilizerCode{N,K,S}` and its six construction invariants (ruling S17) | §3.2, eqs (3.4)–(3.13) |
| `signs::NTuple{S,Int8}` — why a sign-free `PauliWord` is *not* enough | §3.4, "Overall phase factors get dropped" (p. 23) |
| GF(2) validation with **no floats** (commuting, symplectic rank) | §3.4, eqs (3.23)–(3.25) |
| `syndrome(code, err) -> Int` | §3.2, eq (3.9) and the paragraph after it |
| the recovery table, and why "apply *an* equivalent operator" is legitimate | §3.2, p. 20 ("or one equivalent to it by multiplication by `S`") |
| `logical_x` / `logical_z` and their commutation invariants | §3.2, eqs (3.10)–(3.13) |
| `verify_distance` (brute force over `N(S) − S`) and `M11.CODE.DISTANCE-IS-ONE` | §2.3 p. 15 + §3.2 pp. 19–20 |
| `[[n,k,d]]` notation | §2.3, p. 15 |
| the correctability condition a table decoder is exact on | §2.3, eq (2.10) |
| `fault_tolerant_lift`'s refusal: what "fault-tolerant" would require | §5.1–§5.2, §6.1–§6.2 |
| S27's honesty clause — M11 makes **no** threshold claim | §6.2, eqs (6.1)–(6.3) |

---

## Notation

- `G` (`\G` = `{\cal G}` in the source) — the **Pauli group** on `n` qubits:
  all tensor products of `σx, σy, σz, I` with an overall factor `±1, ±i`
  (§2.3, p. 13). Written `G_n` when the qubit count matters.
  *"`G₁` is just the quaternionic group; `G_n` is the direct product of `n`
  copies of the quaternions modulo all but a global phase factor."* (p. 13)
- **weight** of an element of `G` — the number of qubits on which it differs
  from the identity (§2.3, p. 13).
- `S` — the stabilizer, an abelian subgroup of `G`. `T` — the coding space.
- `N(S)`, `C(S)` — normalizer and centralizer of `S` in `G`.
- `[n,k,d]` — Gottesman's own notation for a **quantum** code. He notes
  (§2.3, p. 15): *"a quantum `[n,k,d]` code is often written in the literature
  as `[[n,k,d]]` to distinguish it from a classical `[n,k,d]` code."* Sturm uses
  the double-bracket form; when reading this thesis, single brackets are
  quantum.
- Gottesman writes `σx/σy/σz`; Sturm's `PauliWord` writes `X/Y/Z`. The
  convention `Op(w) = i^{|x∧z|} X^x Z^z` in `src/library/evolve/pauli.jl` makes
  Sturm's words Hermitian, matching Gottesman's generators (which he notes are
  phase-free — see §3.4 below).

---

## §2.3 Properties of Any Quantum Code (pp. 13–15) — the correctability condition

The error-correction condition, derived in two halves and then combined:

    ⟨ψ_i| E_a† E_b |ψ_j⟩ = 0            (i ≠ j)                        (2.8)
    ⟨ψ_i| E_a† E_b |ψ_i⟩ = ⟨ψ_j| E_a† E_b |ψ_j⟩                        (2.9)
    ⟨ψ_i| E_a† E_b |ψ_j⟩ = C_{ab} δ_{ij}                              (2.10)

(2.8) is distinguishability: `E_a|ψ_1⟩ ⊥ E_b|ψ_2⟩`, else there is some chance of
confusing them. (2.9) is the *no-information* requirement: *"When we make a
measurement to find out about the error, we must learn nothing about the actual
state of the code within the coding space. If we did learn something, we would
be disturbing superpositions of the basis states."* (p. 14). `C_{ab}` is
independent of `i` and `j`.

> **Attribution** (p. 14, immediately after (2.10)): *"This condition was found
> by Knill and Laflamme [16] and Bennett et al. [17]."*

**Both necessary and sufficient** (p. 14): `C_{ab}` is Hermitian, so diagonalise
and rescale to a new error basis `{F_a}` with either

    ⟨ψ_i| F_a† F_b |ψ_j⟩ = δ_{ab} δ_{ij}                               (2.11)
    ⟨ψ_i| F_a† F_b |ψ_j⟩ = 0                                           (2.12)

The `(2.12)` errors annihilate every codeword (probability strictly zero); the
`(2.11)` errors always produce orthogonal states, *"so we can make some
measurement that will tell us exactly which error occurred, at which point it is
a simple matter to correct it. Therefore, a code satisfies equation (2.10) for
all `E_a` and `E_b` in some set `E` **iff** the code can correct all errors in
`E`."*

**This is the sentence M11 needs for `TableDecoder`.** It says a table decoder is
*exact* on the declared correctable set — the syndrome→correction lookup is not
an approximation whose quality has to be argued, it is the measurement whose
existence (2.10) guarantees. Everything outside the declared set is uncovered by
the theorem, which is why the table's self-validation (ruling S20) checks
*well-formedness*, and why the docstring must say it does **not** check
minimum-weight-ness (that is decoder *quality*, a different claim).

**Degeneracy** (p. 14): a code is *degenerate* iff `C_{ab}` is singular, i.e.
two distinct errors act identically on codewords. Whether a code is degenerate
depends on the error set it is meant to correct.

**Distance** (p. 15): *"The weight of the smallest `E` in `G` for which (2.10)
does **not** hold is called the distance of the code. A quantum code to correct
up to `t` errors must have distance at least `2t+1`. **Every code has distance at
least one.** A distance `d` code encoding `k` qubits in `n` qubits is described
as an `[n,k,d]` code."*

Also (p. 15): detecting `s` errors needs `d ≥ s+1`; correcting `r` *located*
(erasure) errors needs `d ≥ r+1`; the combined bound is `d ≥ r + s + 2t + 1`.

⚠ **Direct consequence for M11.** The bit-flip code has `d = 1` (derivation in
`repetition_code_effective_noise.md` §1), so by this paragraph it corrects
`t = 0` arbitrary errors. `M11.CODE.DISTANCE-IS-ONE` is not pedantry: calling it
"distance 3" would be a claim this source refutes in one line.

## §2.4 Error Models (p. 15) — the noise model M11 uses

*"In this thesis, I will mostly assume that errors occur independently on
different qubits, and that when an error occurs on a qubit, it is equally likely
to be a `σx`, `σy`, or `σz` error. If the probability `ε` of error per qubit is
fairly small, it is often useful to simply ignore the possibility of more than
`t` errors, since this only occurs with probability `O(ε^{t+1})`."*

That is exactly `physical_iid(enc, 𝓝)`: an i.i.d. product of one-qubit channels,
which in Sturm is a `ChannelTensor` of 1-local factors (ruling S1). Note that
M11 does **not** truncate at `t` errors — the DM path is exact — so the
`O(ε^{t+1})` approximation in this paragraph is *not* imported.

## §3.2 The General Stabilizer Code (pp. 18–21) — the whole `StabilizerCode` type

> *"In general, the stabilizer `S` is some Abelian subgroup of `G` and the coding
> space `T` is the space of vectors fixed by `S`."* (p. 18)

**Dimension counting** (p. 18): *"For a code to encode `k` qubits in `n`, `T`
has `2^k` dimensions and `S` has `2^{n−k}` elements. `S` must be an Abelian
group, since only commuting operators can have simultaneous eigenvectors, but
provided it is Abelian and **neither `i` nor `−1` is in `S`**, the space
`T = { |ψ⟩ s.t. M|ψ⟩ = |ψ⟩ ∀M ∈ S }` does have dimension `2^k`."*

This single sentence is Sturm's **S17 invariants (1)–(3)**:
`S == N − K` generators; the group they generate must be abelian; and it must
not contain `−1` (equivalently: the generators are independent — symplectic rank
`== S` — and no generator is the identity). The `−1 ∉ S` condition is why
`signs` is a real field and not decoration: a set of generators can be pairwise
commuting and independent and still generate a group containing `−1`.

**Properties of `G`** (pp. 18–19): every element squares to `±1`; any two
elements either commute or anticommute; `A ∈ G ⇒ A† ∈ G`; every element is
unitary. The "commute or anticommute, never anything else" dichotomy is what
makes the syndrome a **bit**, and what lets the whole validation run over GF(2).

**Detection / correction criterion** (pp. 19–20). If `M ∈ S` and `{M, E} = 0`,

    ⟨ψ_i| E |ψ_j⟩ = ⟨ψ_i| M E |ψ_j⟩ = −⟨ψ_i| E |ψ_j⟩ = 0               (3.4)

and if `E ∈ S`,

    ⟨ψ_i| E |ψ_j⟩ = ⟨ψ_i|ψ_j⟩ = δ_{ij}                                 (3.5)

so both cases satisfy (2.10). **Normalizer = centralizer** (p. 19): for
`A ∈ G, M ∈ S`,

    A† M A = ± A† A M = ± M                                            (3.6)

and since `−1 ∉ S`, `A ∈ N(S) ⟺ A ∈ C(S)`, so `N(S) = C(S)`, `S ⊆ N(S)`, and
`S` is a normal subgroup of `N(S)`. `N(S)` has `4·2^{n+k}` elements (the 4 is the
global phase, usually ignored). For `E ∈ N(S) − S` (p. 19),

    M E |ψ⟩ = E M |ψ⟩ = E |ψ⟩                                          (3.7)

so `E` moves codewords **within** `T` and is undetectable.

> *"a quantum code with stabilizer `S` will detect all errors `E` that are
> either in `S` or anticommute with some element of `S`. In other words,
> `E ∈ S ∪ (G − N(S))`. This code will correct any set of errors `{E_i}` iff
> `E_a E_b ∈ S ∪ (G − N(S))` ∀ `E_a, E_b`."* (p. 19)

> *"the code will have distance `d` iff `N(S) − S` contains no elements of weight
> less than `d`. If `S` has elements of weight less than `d` (except the
> identity), it is a degenerate code; otherwise it is a nondegenerate code."*
> (pp. 19–20)

**That sentence is the specification of `verify_distance`**: enumerate `G_n`,
keep the elements that commute with every generator (`N(S)`) and are not in `S`,
and take the minimum weight. Brute force is `4^n` and is fine for `n ≤ 8`
(synthesis §5).

**Nondegenerate codes** satisfy the sharpened form

    ⟨ψ_i| E_a† E_b |ψ_j⟩ = δ_{ab} δ_{ij}                               (3.8)

**Syndrome** (p. 20). Define `f_M : G → Z₂` by

    f_M(E) = 0   if [M, E] = 0
    f_M(E) = 1   if {M, E} = 0                                         (3.9)

and `f(E) = (f_{M_1}(E), …, f_{M_{n−k}}(E))` for generators `M_1, …, M_{n−k}`.
Then *"`f(E)` is some `(n−k)`-bit binary number which is 0 iff `E ∈ N(S)`.
`f(E_a) = f(E_b)` iff `f(E_a E_b) = 0`, so for a nondegenerate code, `f(E)` is
different for each correctable error `E`."*

This **is** `syndrome(code, err::PauliWord{N}) -> Int`, bit `j` = anticommutation
with generator `j`. The last clause — distinct syndromes for distinct correctable
errors — is the well-formedness property that ruling **S20**'s self-validation
(`syndrome(code, corrections[σ]) == σ` for every `σ`) turns into a construction
error rather than a silent physics bug.

**Recovery** (p. 20):

> *"In order to perform the error-correction operation for a stabilizer code,
> all we need to do is measure the eigenvalue of each generator of the
> stabilizer. The eigenvalue of `M_i` will be `(−1)^{f_{M_i}(E)}` ... Then we
> just apply the error operator (**or one equivalent to it by multiplication by
> `S`**) to fix the state. Note that even if the original error that occurred is
> a nontrivial linear combination of errors in `G`, the process of syndrome
> measurement will project onto one of the basis errors."*

Three things M11 depends on, all in that paragraph: (i) the correction need only
be right **modulo `S`** — the table stores one representative per syndrome, and
any coset representative works; (ii) syndrome measurement **projects** a
continuous error onto the Pauli basis, which is why a Pauli-channel analysis of
a Pauli noise model is exact rather than a first-order approximation; (iii) the
syndrome is obtained by measuring each generator — in the acceptance example,
`Z₁Z₂` and `Z₂Z₃`, giving the two record wires that `@cases` fans in on.

**Logical operators** (pp. 20–21). `S` acts trivially on `T`, so only `N(S)/S`
acts nontrivially; picking a basis of `T` gives an automorphism `N(S)/S → G_k`,
generated (modulo `i`) by `2k` classes `X̄_i, Z̄_i` mapping to `σ_{x,i}, σ_{z,i}`.
They satisfy

    [X̄_i, X̄_j] = 0                                                    (3.10)
    [Z̄_i, Z̄_j] = 0                                                    (3.11)
    [X̄_i, Z̄_j] = 0   (i ≠ j)                                          (3.12)
    {X̄_i, Z̄_i} = 0                                                    (3.13)

`(3.10)–(3.13)` are **verbatim** S17's invariant (5) (`commutes(X̄_i, Z̄_j)` iff
`i ≠ j`). Invariant (4) — logicals lie in the normalizer — is the definition of
`N(S)/S`; invariant (6) — no logical inside `S` — is the `−S` in `N(S) − S`,
i.e. the requirement that the class be nontrivial.

## §3.4 Alternate Languages for Stabilizers (pp. 23–25) — the GF(2) validation

> *"We can instead write the stabilizer using binary vector spaces ... a pair of
> `(n−k) × n` binary matrices (or often one `(n−k) × 2n` matrix with a line
> separating the two halves). ... One matrix has a 1 whenever the generator has a
> `σx` or a `σy` in the appropriate place, the other has a 1 whenever the
> generator has a `σy` or `σz`. **Overall phase factors get dropped.**"* (p. 23)

That is exactly Sturm's `PauliWord{W}(x::UInt64, z::UInt64)`. **The emphasised
clause is the grounding for ruling S17's `signs` field** (audit item V13): the
symplectic representation is *defined* to forget the sign, so a code with a `−1`
generator is **unrepresentable** in `PauliWord`s alone. Gottesman continues:
*"The generators formed this way will never have overall phase factors, although
other elements of the group might."* — i.e. converting back from binary always
yields `+`-signed generators. A code that genuinely needs `−P` as a generator
must carry the sign beside the word. (It does not bite for the bit-flip code, all
of whose generators are `+1`. That is precisely why omitting the field would ship
a latent defect the M11 suite could not see.)

**Commutation over GF(2)** (p. 24) — the symplectic form:

    Q(a|b, c|d) = Σ_{i=1}^{n} (a_i d_i + b_i c_i) = 0                  (3.23)

(binary arithmetic). The stabilizer matrix `(A|B)` is abelian iff

    Σ_{l=1}^{n} (A_{il} B_{jl} + B_{il} A_{jl}) = 0                     (3.24)

and the code is **real** (an even number of `σy`s in each generator) iff

    Σ_{l=1}^{n} A_{il} B_{il} = 0                                       (3.25)

`(3.23)` is the shipped `commutes(::PauliWord, ::PauliWord)`; `(3.24)` is S17's
pairwise-commuting check over all generator pairs. **No floats appear anywhere**
in the validation — this is why ruling S17 says "over GF(2), no floats", and why
the code-validation tests carry no tolerance.

Gottesman also gives the **GF(4)** formalism (p. 24, eqs (3.26)–(3.28), `1 ↔ σx`,
`ω ↔ σz`, `ω² ↔ σy`; the trace-inner-product commutation test (3.28)) and the
linear/additive distinction. Sturm uses the binary form; the GF(4) form is noted
only so a future CSS/classical-code bridge knows where it is.

Related, deferred: **§3.5 Making New Codes From Old Codes** (pp. 25–29) and
**§4.1 Standard Form for a Stabilizer Code** / **§4.2 Network for Encoding**
(pp. 31–35) — the Cleve–Gottesman standard-form encoder synthesis that synthesis
§4.2 explicitly **defers** out of M11. `CodeEncoding` (ruling S19) exists as a
separate struct precisely so that a later `standard_form_encoding(code)` from
§4.1–4.2 can produce a *different* encoding of the *same* `StabilizerCode`.

## §5.1–§5.2 Fault tolerance and syndrome extraction (pp. 37–40)

**Definition of fault-tolerant** (p. 37): *"I will define a fault-tolerant
operation as one for which a **single error introduces at most one error per
block** of the code."*

**Error propagation through CNOT** (p. 38): with the state
`(α|0⟩ + β|1⟩)(|0⟩ ± |1⟩)` (5.1), a CNOT gives

    α|0⟩(|0⟩ ± |1⟩) + β|1⟩(±1)(|0⟩ ± |1⟩) = (α|0⟩ ± β|1⟩)(|0⟩ ± |1⟩)   (5.2)

> *"In a CNOT, amplitude (bit flip) errors propagate forwards, and phase errors
> propagate backwards."*

**Transversality** (p. 38): *"Operations for which each qubit in a block only
interacts with the corresponding qubit, either in another block or in a
specialized ancilla, will be called **transversal** operations. Any transversal
operation is automatically fault-tolerant, although there are some fault-tolerant
operations which are not transversal."*

⚠ **§5.2 is the section that makes M11's honesty clause mandatory.** Gottesman
opens it (p. 38) with exactly the syndrome-extraction circuit the M11 acceptance
example uses — *"perform a CNOT from both qubits to a third ancilla qubit,
initially in the state `|0⟩`"* — and then says:

> *"However, this procedure is **not** a transversal operation. Both qubits
> interact with the same ancilla qubit, and a single phase error on the ancilla
> qubit could produce phase errors in both data qubits, producing two errors in
> the block."*

He then develops the fix (separate ancillas → cat states `|00⟩+|11⟩` → verified
cat states, pp. 38–40). Sturm's `bitflip_recover!` (`a1 ⊻= q1; a1 ⊻= q2`) is the
**unfixed** version. That is correct for M11 — the model is code-capacity with
*noiseless* extraction (ruling S27) — but it means the program must never be
described as fault-tolerant, and it is one of the five ingredients
`fault_tolerant_lift` names as missing ("extraction schedule under a *noisy*-
syndrome model", ruling S26).

## §6.1–§6.2 Concatenation and the threshold (pp. 60–67)

**Why a threshold exists at all** (§6.1, p. 60): *"Since the gates involved in
error correction are themselves noisy, the process of error correction introduces
errors at the same time it is fixing them. If the basic gate error rate is low
enough, the error correction will fix more errors than it introduces on the
average ... If the error rate is too high, attempting to correct errors will
introduce more errors than are fixed, and error correction is actively doing
harm."*

Concatenation (p. 61): an `[n,k,d]` code whose qubits are each re-encoded in an
`[n₁,1,d₁]` code, etc., gives an `[n n₁ ⋯ n_{l−1}, k, d d₁ ⋯ d_{l−1}]` code, and
syndrome extraction costs the **sum** rather than the product of the levels'
costs. He fixes the `[7,1,3]` code as the running example, *"because any
operation in `N(G)` can be immediately performed transversally."*

**The recursion** (§6.2, p. 63), for `p_EC` the chance of an error on a data
qubit during one syndrome measurement:

    p_g^{(j)}    = 21 [ (p_g^{(j−1)})²    + 4 p_g^{(j−1)}    p_EC + 8 p_EC² ]   (6.1)
    p_stor^{(j)} = 21 [ (p_stor^{(j−1)})² + 4 p_stor^{(j−1)} p_EC + 8 p_EC² ]   (6.2)

> *"The salient aspect of these equations is that the probability of error at
> level `j` is of the order of the **square** of the error rate at level `j−1`."*

    p_g^{(l)} ~ p_g^{(0)} ( p_g^{(0)} / p_thresh )^{2^l}                        (6.3)

with the overhead only `polylog(p)` times the original qubit count.

**The numbers he derives** (pp. 66–67), each under stated assumptions:
`p_thresh = 1/25200 = 4.0 × 10⁻⁵` (gates only, negligible storage errors);
`≈ 2.2 × 10⁻⁶` (storage errors only); `2.3 × 10⁻⁵` / `1.3 × 10⁻⁵` (with ancillas
prepared just in time); and, optimising the number `N = √8 (p_EC / p_g)` (6.21)
of steps between corrections, `N = 34` and `p_thresh = 4.1 × 10⁻⁴` (6.22).
§6.3 (pp. 67–71) redoes the recursion for the Toffoli gate.

**Why M11 cites this section for a refusal.** Synthesis §7 drops a separate
Aliferis–Gottesman–Preskill distillation because this chapter derives a threshold
from scratch, which is all that is needed to justify the *message* of
`fault_tolerant_lift`'s refusal (S26). Note what these numbers are **not**: they
are specific to the `[7,1,3]` code, Shor's cat-state extraction, and Gottesman's
own accounting assumptions. They are not a threshold for anything Sturm ships.
**M11 makes no threshold claim** (S27), and no number from this section should
appear in a Sturm docstring as if it applied to Sturm.

---

## Gaps, divergences, and things NOT in this source

**G1 — the `[[3,1,1]]` bit-flip repetition code is not in this thesis.**
Gottesman's worked examples are Shor's `[[9,1,3]]` code (§2.2, §3.1), the
five-qubit `[[5,1,3]]` code (§3.3, Table 3.2), and the `[[7,1,3]]` CSS code. A
grep of the full text for "repetition" finds only a passing remark in §7.1
(p. 74) about concatenating a random code with a repetition code. **Every
concrete claim M11 makes about the bit-flip code** — its stabilizers, that its
distance is 1, `p_L = 3p² − 2p³`, the phase amplification — is therefore an
**in-repo derivation** using this thesis's §3.2 machinery, and lives in
`docs/physics/repetition_code_effective_noise.md` (synthesis §7 item **P6**,
explicitly labelled a derivation note, not a paper distillation). Do not cite
Gottesman for the numbers.

**G2 — Eastin–Knill is not here, and cannot be.**
Synthesis §7 item **P5** wants the no-go *"no code admits a universal transversal
gate set"* (Eastin–Knill, arXiv:0811.4262, PRL 102 110502 (2009)) to make
`fault_tolerant_lift`'s refusal a **theorem**. This thesis is from 1997 and
predates it by twelve years. What it *does* supply is the surrounding structure:
the definition of transversality (§5.1 p. 38), which operations *are* transversal
for which codes (§5.3–§5.9), and the Toffoli gadget (§5.7) — i.e. the shape of
the problem Eastin–Knill later closes. **The refusal message must not cite this
file for the no-go.** `eastin_knill_2009_no_universal_transversal.md` remains
owed.

**G3 — Knill–Laflamme: the condition is here, the paper is not.**
Synthesis §7 item **P3** wants `knill_laflamme_1997_qec_conditions.md`
(quant-ph/9604034). The **condition itself** is stated, derived, and proved
necessary *and* sufficient in §2.3 of this thesis (eq. (2.10), p. 14), with
explicit attribution to Knill–Laflamme and Bennett et al. So M11's *physics* is
covered by this file. What is **not** here: the Knill–Laflamme paper's own
numbering, its `P K_i† K_j P = α_{ij} P` projector form (Gottesman writes the
matrix-element form (2.10) instead — they are equivalent, `P = Σ_i |ψ_i⟩⟨ψ_i|`,
but the *equation number* the PRD wants to pin belongs to the paper, not here),
and any of its further results. Options for the orchestrator, in preference
order: (a) fetch quant-ph/9604034 (free on arXiv) and write P3 properly;
(b) retarget the PRD §9 / synthesis §7 entry to this file's §2.3 locator and
drop the separate filename — but note this is a **normative PRD edit**, so it is
a T1-class change, not a distillation decision. Until one of those happens, **no
`src/` file may cite `docs/physics/knill_laflamme_1997_qec_conditions.md`**, or
the rule-4 boot lint will fail.

**G4 — no channel/Choi language at all.**
Gottesman works with state vectors, error operators and the group `G`. He does
say (§2.1, p. 11) that a noisy channel *"applies a superoperator to the input
density matrix"* which can be diagonalised into non-unitary matrices acting on
pure states, and that correcting each pure branch corrects the mixture — but
there is no Kraus/Choi/Stinespring formalism here. For all channel-level
statements (including "`Θ(𝓝) = id_L` is the correctability statement") use
`docs/physics/watrous_2018_channel_representations.md`. This thesis grounds the
**code**; Watrous grounds the **channel**.

**G5 — the notion of a *superchannel* is absent.**
Nothing here licenses `effective_logical_noise` as a *transformation of channels*
(synthesis §7 item **P4**, `chiribella_2009_quantum_combs.md`, still unsourced —
though see `watrous_2018_channel_representations.md` **G7** for a partial,
on-disk locator). Gottesman gives the ingredients `E`, `R`, `D`; the claim that
`D ∘ R ∘ 𝓝 ∘ E` is the right *type* of object is imported from elsewhere.

**G6 — encoder gauge.**
§4.1–4.2 give **an** encoding network from the standard form, not **the**
encoder. This is the direct grounding for ruling S19's split of `StabilizerCode`
(gauge-free) from `CodeEncoding` (a gauge choice): two encoders for the same
stabilizer group are both legitimate, so folding the circuit into the code value
would make two identical codes compare unequal.

**G7 — `−1 ∈ S` is stated as a hypothesis, not as an algorithm; and what `signs`
is actually for.**
Gottesman requires *"neither `i` nor `−1` is in `S`"* (p. 18) but gives no
procedure for checking it from a generator list. The implementation must supply
one, and the argument is short enough to record here (derived in-repo, not
quoted): if every generator is a **Hermitian** Pauli word (squares to `+1`,
excluding the `i` factor) and the generators' **symplectic images are independent
over GF(2)** (S17 invariant (3)), then no nonempty product of generators has
trivial symplectic image, so no nonempty product is `±I`; hence `S ∩ {−1, ±i} =
∅`. Independence plus Hermiticity is therefore **sufficient**, and the sign
values do not enter this check at all.

What the signs *do* determine is **which** `2^k`-dimensional joint eigenspace is
the code space: `⟨Z₁Z₂, Z₂Z₃⟩` and `⟨−Z₁Z₂, Z₂Z₃⟩` are different codes with the
same words. That is the reason ruling S17 adds `signs` beside the sign-free
`PauliWord`s (§3.4's "overall phase factors get dropped"), and it is a
*correctness* field, not bookkeeping — a syndrome table validated against the
wrong eigenspace decodes to the wrong coset.
