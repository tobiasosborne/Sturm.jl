# Logical Reversibility of Computation

**Citation**: C. H. Bennett, "Logical Reversibility of Computation",
*IBM J. Res. Develop.* **17**(6):525–532 (November 1973).
DOI: 10.1147/rd.176.0525. Received April 12, 1973. (Bennett was at the
IBM Thomas J. Watson Research Center, Yorktown Heights, NY 10598.)

**Local PDF**: `docs/physics/bennett_1973_logical_reversibility.pdf`
(8 pp., the scanned IBM original, pp. 525–532). Obtained from the Wayback
Machine snapshot of the S. Buss course mirror
(`mathweb.ucsd.edu/~sbuss/CourseWeb/Math268_2013W/Bennett_Reversibiity.pdf`,
snapshot 20260304044601) after the live host served a hotlink placeholder
and the IBM/SIAM originals are paywalled. **PDF-verified against every
locator below.** (Provenance caution, session-95 class: a first candidate
from `pzuliani.github.io/papers/ibmjrd.pdf` was rejected — it is Paolo
Zuliani's *pGCL* paper "Logical reversibility", which merely *cites*
Bennett 1973 as its ref [2]; it is NOT this paper.)

**Status in pipeline**: ground-truth source for the **Bennett bridge**
(milestone M7). `oracle(f, x)` compiles an ordinary Julia function `f` to a
reversible circuit (via Bennett.jl) → a kernel `Perm` value; the
**compute–copy–uncompute** three-stage construction distilled here is
exactly what makes that circuit reversible *and* clean-ancilla, which is
in turn what licenses the `b ⊻= oracle(f, x)` kickback idiom of PRD-v2 §3.4
and the DJ/BV examples of §7.4/§7.5. Cited by PRD-v2 §3.4 ("Bennett's
compute-copy-uncompute", line ~443) and the D9/D14 rulings (§9).

---

## What this paper does (one line)

It proves that any general-purpose computer (a Turing machine), normally
**logically irreversible** (its transition function lacks a single-valued
inverse), can be made **logically reversible at every step** — at a modest
(≈2×) time cost and a large temporary-storage cost that a later argument
reduces. The reversible machine ends holding *only* the original input and
the desired output; all scratch is returned to blank. This is the
theoretical charter for reversible/quantum oracle compilation.

---

## The three-stage construction (compute – copy – uncompute)

**Abstract (p. 525), verbatim structure — the load-bearing trick.** The
reversible machine R emulates the irreversible machine S in three stages:

1. **Compute.** "the logically reversible automaton parallels the
   corresponding irreversible automaton, except that it saves all
   intermediate results, thereby avoiding the irreversible operation of
   erasure." (abstract, p. 525). Concretely R writes a **history tape**
   recording, at each step, the index of the transition applied, so the
   forward run is injective. (Heuristic argument, p. 526; formal quadruples
   Eq (11), p. 529.)
2. **Copy output.** "The second stage consists of printing out the desired
   output." (p. 525) — the output is copied onto a *separate, initially
   blank* third tape by CNOT-style copying: "the copying process can be
   done reversibly without writing anything more on the history tape. This
   shows that the generation (or erasure) of a duplicate copy of data
   requires no throwing away of information." (p. 528). This is why a
   *copy* (not a move) is the reversible way to expose the answer.
3. **Retrace / uncompute.** "The third stage then reversibly disposes of
   all the undesired intermediate results by retracing the steps of the
   first stage in backward order (a process which is only possible because
   the first stage has been carried out reversibly), thereby restoring the
   machine (except for the now-written output tape) to its original
   condition." (abstract, p. 525). Formally the third-stage quadruples are
   "the inverses of all first-stage transitions with C's substituted for
   A's" (p. 529).

**Table 1 (p. 528) — the three stages as tape contents** (this figure is
the picture the bridge implements). Three tapes: *Working*, *History*,
*Output*; initial control state A₁, final state C₁.

| Stage | after the stage: Working | History | Output |
|---|---|---|---|
| (start) | INPUT | — (blank) | — (blank) |
| **Compute** | OUTPUT | HISTORY | — |
| **Copy output** | OUTPUT | HISTORY | OUTPUT |
| **Retrace** | INPUT | — (blank) | OUTPUT |

The final row is the **clean-ancilla guarantee**: Working tape back to the
original INPUT, History tape back to blank, only the Output tape newly
written.

## The clean-ancilla guarantee (the Theorem)

**Theorem (p. 527), verbatim.** "For every standard one-tape Turing machine
S, there exists a three-tape reversible, deterministic Turing machine R
such that if I and P are strings on the alphabet of S, containing no
embedded blanks, then S halts on I if and only if R halts on (I;B;B), and
**S: I → P if and only if R: (I;B;B) → (I;B;P)**." (B denotes a blank
tape.)

Read the map `(I;B;B) → (I;B;P)`: the input I is **regenerated**, the
history/working scratch tape returns to **blank B**, and the output tape
holds P. This — scratch in, scratch out at its initial value — is precisely
the "ancillas return to |0⟩" property Sturm's bridge relies on
(`docs/design/bennett-v2-compat-audit.md` Q1: "Bennett's construction
guarantees they return to |0⟩").

**Resource counts (p. 527), verbatim.** "if in a particular computation S
requires ν steps and uses s squares of tape, producing an output of length
λ, then R will require **4ν + 4λ + 5 states, 4N + 2z + 3 quadruples** and
tape alphabets of z, N+1, and z letters, respectively. Finally … R will
use s, ν+1, and λ+2 squares on its three tapes." So R's step count is
≈ the same order as S (the abstract's "about twice as many steps"), but the
history tape grows **linearly in the number of steps ν** — the temporary-
storage cost.

## The space–time tradeoff (seed of the pebble game)

The linear-in-ν history is the drawback; the paper then shows it is
tradeable. **p. 526** flags it: "by performing a job in many stages rather
than just three, the required amount of temporary storage can often be
greatly reduced." **pp. 529–530** make it quantitative:

- Immediately after the theorem (p. 527): "It will later be argued that
  where ν ≫ s, total space requirement can be reduced to less than
  **2√(νs)**."
- **p. 529–530**, verbatim: "the temporary storage requirement can be cut
  down by breaking the job into a sequence of **n** segments, each one …
  performed and retraced (and the history tape thereby erased and made
  ready for reuse) before proceeding to the next." "For a job with ν steps
  and a restart dump of size s, the total temporary storage requirement
  (minimized by choosing **n = √(ν/s)**) is **2√(νs)** squares … A
  (½√(ν/s))-fold reduction in space can thus be bought by a twofold
  increase in time."
- The recursive conjecture (p. 530): "By systematic reversal of
  progressively larger nested sequences of segments one might hope to reach
  an absolute minimum temporary storage requirement growing **only as
  log ν**, for sufficiently large ν, with the time increasing perhaps as
  **ν²**." — This nested-segment reversal is exactly the pebble-game
  strategy that Bennett 1989 formalizes (see below) and that Bennett.jl's
  `PebbledStrategy`/`CheckpointStrategy` implement.

**Table 2 (p. 530)** gives a companion **seven-stage** construction for the
special case where the input is itself a *known computable function of the
output* (compute S₁ forward → copy → retrace S₁ → interchange in/out →
compute S₂ forward → reversibly erase the extra input copy → retrace S₂),
leaving only the desired output. This is the two-oracle "uncompute the
input" pattern, not needed for the DJ/BV cases (which keep the input live).

## Physical grounding (why reversibility is not free)

Landauer's principle motivates the whole paper: "a computer must dissipate
at least **kT ln 2** of energy (about 3×10⁻²¹ joule at room temperature)
for each bit of information it erases or otherwise throws away." (p. 525).
The reversible construction avoids erasure, so it can in principle dissipate
arbitrarily little (physical-reversibility discussion, pp. 530–531). The
paper closes with the biochemical analogy — messenger-RNA transcription by
RNA polymerase as a physically reversible tape-copying computation, and its
sequence-checked degradation as the irreversible counterpart (pp. 531–532).
These physics sections are not load-bearing for the M7 code; they are the
"why erasure costs energy" backdrop of PRD-v2's garbage discipline.

---

## Bennett 1989 — the pebble-game formalization (NOT locally sourced)

**Citation**: C. H. Bennett, "Time/Space Trade-Offs for Reversible
Computation", *SIAM J. Comput.* **18**(4):766–776 (1989).
DOI: 10.1137/0218053. (Bibliographic locators verified via SIAM/ACM/IBM
Research catalog entries; the abstract result is: an irreversible
computation of time T and space S can be simulated reversibly in time
O(T^{1+ε}) and space O(S log T), or in linear time and space O(S T^ε).)

**PDF NOT obtained** — the SIAM/ACM originals are paywalled and no free
mirror or Wayback snapshot was locatable (checked 2026-07-10). This section
is therefore grounded in the **1973 paper's own** p. 530 nested-segment
passage (verified above), which is the strategy Bennett 1989 turns into a
reversible **pebble game** on a chain: with k pebbles one can reversibly
traverse a chain of 2^k − 1 forward steps using k units of storage,
yielding the general space O(S log T) / time O(T^{1+ε}) tradeoff and its
"log ν space, ν² time" limit. **Bennett.jl's `PebbledStrategy(max_pebbles)`
and `PebbledGroupStrategy` are named after this pebble game**
(`docs/design/bennett-v2-compat-audit.md` Q1). If a distillation with
verified 1989 equation/page locators is later required, the PDF must be
sourced first — do NOT cite 1989 theorem/equation numbers from this file,
which has none.

---

## Relevance to Sturm v2

- **The bridge IS compute–copy–uncompute.** Bennett.jl's `bennett(lr)`
  back-end (the `DefaultStrategy` and its variants) emit exactly this
  three-stage structure over NOT/CNOT/Toffoli gates; the "copy output"
  stage is the CNOT-copy of §II above, which is *why* the compiled `Perm`
  never reads an output wire as a control (D9 ruling, §9). That gate-level
  fact is what makes `b ⊻= oracle(f, x)` implement `|x⟩|b⟩ → |x⟩|b⊕f(x)⟩`
  for *any* initial `b` — feed `b = |−⟩` and the copy stage becomes phase
  kickback `(−1)^{f(x)}` (PRD-v2 §3.4; DJ/BV, §7.4/§7.5). See the CEMM
  distillation `docs/physics/deutsch_jozsa_1992.md` for the kickback side.

- **Clean-ancilla exit = the Theorem's `(I;B;B) → (I;B;P)`.** The retrace
  stage returns every scratch/history wire to blank; in Sturm's kernel this
  is the ancilla returned to |0⟩ that §3.5/§3.9 demand at region exit and
  that the `when`-body clean-ancilla assertion (|1⟩-block norm = 0) checks.
  A Bennett circuit that skipped its retrace would leave the ancilla
  entangled — the forbidden case. NB the one exception the audit flags:
  Bennett's `loop_check_wires` do **not** return to blank (they carry a
  convergence flag), so a loop-carrying oracle violates this guarantee and
  must be rejected under a control stack (`bennett-v2-compat-audit.md` Q2).

- **Space–time tradeoff = strategy selection.** The p. 530 nested-segment
  reduction is the cost knob Bennett.jl exposes as `PebbledStrategy` etc.;
  all such strategies still emit only unitary NOT/CNOT/Toffoli, so every
  artifact is a phase-free `Perm` and the MBU-exclusion of §3.4 holds
  structurally (`bennett-v2-compat-audit.md` Q3). The tradeoff is the
  reason M7's cost model has strategies to choose among at all.

- **D14 scope.** The 1973 machine is a *fixed* three-tape construction — the
  loop-free, bounded case. That is exactly the `target=:circuit` →
  `ReversibleCircuit` → `Perm` path Sturm consumes; the unbounded case
  (BennettVM `VMProgram`) is out of scope for M7 (D14 ruling (A)), and
  `oracle(f, x)` raises a loud error rather than lowering it.
