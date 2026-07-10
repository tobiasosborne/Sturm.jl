# Quantum Circuits Cannot Control Unknown Operations

Source: M. Araújo, A. Feix, F. Costa, Č. Brukner, "Quantum circuits
cannot control unknown operations", *New J. Phys.* **16**, 093026
(2014). DOI: 10.1088/1367-2630/16/9/093026. arXiv:1309.7976v2
[quant-ph], submitted 30 Sep 2013, revised 31 Jan 2014 (the PDF is the
published/typeset version, dated "3rd February 2014", 4 pages).
PDF in `docs/physics/araujo_1309.7976.pdf`.

This is the citation PRD-v2 §1.1 attaches to the formal tension that
motivates the kernel: "Controlled-U cannot be constructed from
black-box access to U (Araújo–Feix–Costa–Brukner, arXiv:1309.7976, the
original single-exact-query no-go; strongest form Gavorová–Seidel–Touati,
arXiv:2011.10031 ...)." The paper supplies (a) the original no-go proof
that a quantum circuit cannot build a control-U gate from one black-box
call to an unknown unitary U, even up to global phase, and (b) the
paper's own *constructive* escape — control IS possible once you have
side-information about *where* the physical implementation of U acts
non-trivially (the `1_d ⊕ U` extension). PRD-v2's reading is that a
kernel process value (`U2`, `Perm`, `UnitaryDAG`) IS that side-information,
made explicit and typed, and that `ctrl` is the single choke point
licensed to consume it.

---

## The no-go argument (pp. 1–2)

**Setup (p. 1, unnumbered circuit identity).** The question posed: does
there exist an ancilla-based circuit — unitaries `A`, `B` acting on an
ancilla register (initial state `|0⟩_a`) plus the control qubit, and a
single black-box call to the unknown `d×d` unitary `U` — that reproduces
the ideal control-U gate up to an arbitrary ancilla-only unitary `W_U`
(itself possibly `U`-dependent)? Formally: do `A`, `B` exist such that

```
B (1_a ⊗ 1_2 ⊗ U) A |0⟩_a  "=?="  (ancilla → W_U|0⟩_a) ⊗ control-U
```

with the ancilla wire carrying `W_U|0⟩_a` on the target side. This is
explicitly "the most general transformation that a quantum circuit can
effect on U" (p. 2, citing Chiribella–D'Ariano–Perinotti's process-matrix
framework, ref. [11] = arXiv:0904.4483) — i.e. the proof is not about one
naive ansatz, it forecloses every circuit topology.

**The phase step — the crux (p. 2, top).** Observe: substituting
`U → e^{iφ}U` in the *lhs* changes nothing physical (the two circuits
differ only by an unobservable global phase `e^{iφ}` on the whole
state). The *same* substitution on the *rhs* (the ideal control-U,
matrix `1_d ⊕ U`) produces a **measurable relative phase** between the
control-0 and control-1 branches. Since `U` is only physically defined
up to a phase, the only question that can be asked is whether a circuit
implements control-U *modulo that global phase* — i.e. whether, for
`|U⟩_a := W_U|0⟩_a`,

```
B(1_a ⊗ 1_2 ⊗ U)A|0⟩_a = |U⟩_a (1_d ⊕ e^{iu}U)          (Eq. 1, p. 2)
```

for *some* U-dependent phase `e^{iu}`. The paper states this is still
impossible "due to the non-linearity of the transformation
`U ↦ 1_d ⊕ e^{iu}U`" (p. 2) — the phase `u` a working circuit would need
to attach cannot be assigned consistently because that assignment map
is forced to be linear in `U` (by Eq. 1 applied to a sum) but the target
object `1_d ⊕ e^{iu}U` is manifestly non-linear in `U`.

**The qubit contradiction, spelled out (p. 2, Eqs. 2–6).** The general
non-linearity claim is made airtight by an explicit qubit computation:
assume Eq. 1 holds for the three unitaries `X`, `Z`, and
`H = αX + βZ` (`α²+β²=1`, real):

- Eq. (2): `B(1_a ⊗ 1_2 ⊗ (αX+βZ))A|0⟩_a = |H⟩_a(1_2 ⊕ e^{ih}H)`.
- Expand the lhs by linearity, reapply Eq. (1) to `X` and `Z`
  separately → Eq. (3):
  `α|X⟩_a(1_2⊕e^{ix}X) + β|Z⟩_a(1_2⊕e^{iz}Z) = |H⟩_a(1_2⊕e^{ih}H)`.
- Inner product with `|H⟩_a` on the ancilla factor → Eqs. (4a)/(4b):
  `α⟨H|X⟩ + β⟨H|Z⟩ = 1` (4a); `α⟨H|X⟩e^{ix}X + β⟨H|Z⟩e^{iz}Z = e^{ih}(αX+βZ)` (4b).
- `X ⊥ Z` (as basis directions of the 2-dim real span) ⇒ from (4b),
  `⟨H|X⟩ = e^{i(h-x)}`, `⟨H|Z⟩ = e^{i(h-z)}`. Substituting into (4a) →
  Eq. (5): `e^{i(h-x)}(α + βe^{i(x-z)}) = 1`.
- Take `|·|²` of Eq. (5): `cos(x−z) = 0`. Repeat the *identical*
  argument for the pairs `αX+βY` and `αY+βZ` → also `cos(x−y) = 0` and
  `cos(y−z) = 0`. Together this is Eq. (6):
  `cos(x−z) = cos(x−y) = cos(y−z) = 0` — **no real angles `x,y,z`
  satisfy all three simultaneously** (p. 2). Contradiction closes the
  proof: *"This shows that one cannot control an arbitrary unknown
  unitary in the quantum circuit model"* (p. 2), restated in the
  conclusion (p. 4) as holding **even modulo a global phase**.

This is a **single-copy / single-query** result throughout — `U` is
supplied to the circuit exactly once (p. 1: "given as input a single
copy of the unknown `d×d` gate `U`"); PRD-v2's "single-exact-query
no-go" label is accurate to the paper's own framing.

## What the no-go does NOT forbid (p. 2, immediately after Eq. 6)

Three explicit exceptions, stated right after the theorem:

1. **Known eigenvector + eigenvalue of `U`**: a circuit exists (cites
   Kitaev's phase-estimation-adjacent construction, ref. [3] =
   quant-ph/9511026).
2. **`U` known to belong to a fixed set of mutually orthogonal
   unitaries**: control is possible (ref. [12], Bisio–Perinotti–Sedlák,
   "in preparation" at time of writing).
3. **Classical control of classical (permutation) operations on
   computational-basis inputs**: control-`U_cl` for a classically
   allowed (permutation-matrix) `U_cl` IS realizable by a circuit using
   a classical-cloning (CNOT-style) primitive `C` (p. 2–3, circuit
   diagram) — because classical bit strings CAN be copied, unlike
   general quantum states. The paper notes this doubles as an
   alternative proof of no-cloning: if arbitrary `|ψ⟩` cloning were
   possible, the same circuit would control unknown *quantum*
   operations too, contradicting the theorem just proved (p. 2–3).

## The constructive half — physical implementations DO allow control (p. 3)

**Key distinction (p. 3):** the unitary matrix `U` that appears
*abstractly* in a circuit diagram is completely unknown; the *physical
device* implementing it, `U_physical`, is not — its *position* (which
modes/subspace it acts on) is known. Extending the description of `U`
to include the subspace it acts trivially on gives

```
U_physical = ( 1_d   0  ; 0   U )  =  1_d ⊕ U          (displayed eq., p. 3)
```

— exactly the control-U matrix. `U` is still fully unknown, but
`U_physical` is not (some of its eigenvalues — the `1_d` block's — are
known a priori), so the no-go theorem simply does not apply to it.

**Interferometric realization (p. 2–3, Fig. 1, Eq. 7).** A single
photon in polarization state `α|H⟩_C + β|V⟩_C` carrying an auxiliary
qudit `|ψ⟩` (OAM, spatial/temporal bin, etc.) is routed through a
polarizing-beam-splitter (PBS) interferometer so that only the `|V⟩`
(blue) path passes through the black-box `U`:

```
(α|H⟩_C + β|V⟩_C)|ψ⟩  ↦  α|H⟩_C|ψ⟩ + β|V⟩_C U|ψ⟩          (Eq. 7, p. 2–3)
```

for **any** blackbox `U` — because the interferometer's geometry (which
path goes through the box) supplies exactly the `1_d ⊕ U` side-information,
not any knowledge of `U`'s matrix elements. Fig. 2 (p. 3) gives a scalable
generalization to an `n`-qubit blackbox: the control qubit is encoded
across `n` photons as `α|H⟩^{⊗n} + β|V⟩^{⊗n}`, each photon through its
own interferometer, `U` acting jointly across all the upper (blue) arms;
total PBS count `2n`.

**General statement (p. 3).** If the physical implementation of `U` is
known to act trivially on a `d′`-dimensional subspace, one can write it
as `1_{d′} ⊕ U`; even the minimal one-dimensional extension `1 ⊕ U`
suffices to build a control-U using Kitaev's known-eigenvector scheme
(ref. [3]), since `1 ⊕ U` has one manifestly known eigenvector/eigenvalue
pair. The paper draws the analogy explicit: the circuit model already
accounts for the fact that physical operations act on a *limited number
of subsystems* via extra wires (`U ↦ 1⊗U`); it argues the model should
symmetrically be extended to account for operations acting on a
*limited subspace* (`U ↦ 1⊕U`) — direct-sum extension, not just tensor
extension. This proposed extension is the paper's stated upshot (title
of the closing argument, p. 3, and restated in the conclusion, p. 4).
Experimental demonstrations of control of black-box gates are cited
(refs. [13]–[15]: Lanyon et al., *Nat. Phys.* 5, 134 (2009),
arXiv:0804.0272; Zhou et al., *Nat. Commun.* 2 (2011), arXiv:1006.2670;
Zhou et al., *Nature Photonics* 7, 223 (2013), arXiv:1110.4276).

## Conclusion, as stated (p. 4)

*"We have proved a no-go theorem that shows that an unknown arbitrary
unitary cannot be controlled in a quantum circuit, even modulo a global
phase. This control is, however, possible for any physical
implementation of a unitary transformation."* — the paper's own
one-sentence summary, and the cleanest single locus to cite for both
halves of the result.

Independent/related work noted in an end-of-paper addendum (p. 4, added
after submission): A. Soeda (ICQIT 2013 talk, ref. [22]) obtained
similar results independently; Thompson, Gu, Modi, Vedral (ref. [23],
arXiv:1310.2927) developed related work.

---

## Relevance to Sturm v2

1. **Grounds why `ctrl` must act on process values, never on channels
   (P4, PRD-v2 §1.1/§6).** The theorem is exactly "no circuit can build
   control-U from one opaque call to U" — i.e. from a *channel-level*
   black box. Sturm's kernel process values (`U2`, `Perm`, `UnitaryDAG`)
   are precisely the "side-information about where U acts" the paper's
   constructive half requires (the `1_d ⊕ U` datum) — a process value
   IS a typed, inspectable description of the operation's action, not
   an opaque call. This is the theorem PRD-v2 §1.1 cites to justify
   that `ctrl` is a homomorphism on process values and the *sole*
   construction path for controlled lowerings, system-wide.
2. **The global-phase step (p. 2, the `U → e^{iφ}U` substitution) is the
   physical seed of Sturm's phase discipline.** It is the reason a
   *bare* channel/black-box cannot be controlled even in principle:
   control requires fixing a phase representative of `U`, and no
   circuit-consistent (linear) way to do that exists for an arbitrary
   unknown `U` (Eqs. 1–6). PRD-v2's `U2` = (quaternion, phase) kernel
   value exists so that the phase is carried explicitly and crossed
   "exactly once, at application" (§4.3 `Ad`) — i.e. Sturm supplies by
   construction the phase-fixed representative the no-go shows cannot
   be extracted from a black box.
3. **The classical-permutation exception (p. 2–3, the `U_cl` circuit
   with classical cloning `C`) is the physical justification for
   Bennett-bridge control.** `oracle(f, x)` values are `Perm`
   (classical reversible / permutation) process values — exactly the
   class the paper shows CAN be controlled from black-box access,
   because classical basis states can be copied. This is independent
   physical grounding for why `when(q) do oracle(f,x) ... end`-style
   coherent control of an oracle is unproblematic while coherent
   control of an arbitrary *unknown quantum* channel is not.
4. **The `1_d ⊕ U` datum is literally the guardrail-1 requirement,
   physically motivated.** §3.5 guardrail 1 requires the `when` body to
   trace to a *unitary-witnessed* value before `ctrl` is applied. The
   paper's constructive half says: control is possible precisely when
   you know the subspace/eigenstructure `U` sits inside (the witness);
   it is impossible when `U` is a bare, unwitnessed black box. The
   unitarity witness Sturm requires is the typed avatar of that
   physical knowledge.
5. **What NOT to over-read.** The paper does not discuss quantum
   alternation, non-monotonicity under recursion, or channel-level
   denotational semantics — those are Bădescu–Panangaden's and
   Yuan–Villanyi–Carbin's contributions (PRD-v2 §1.1, §3.5), cited
   alongside this paper but for different reasons. Do not attribute
   guardrails 2/3 (§3.5) to this paper; it supports only the *kernel
   process-value* argument (guardrail 1's unitary-witness requirement)
   and the general "control needs a phase-fixed / subspace-witnessed
   representative" principle.

---

## Caveats — wording audit against Sturm-PRD-v2.md

- **Section locus mismatch.** The task brief describes this paper as
  "§3.5 guard-lore for Sturm's `when` construct." In the actual document
  the citation occurs in **§1.1** ("The formal tension (P1 vs P4)", the
  diagnosis chapter motivating why v0.1's primitive layer must go — see
  lines ~57–71 of Sturm-PRD-v2.md), not inside §3.5's guardrail list
  itself (lines ~460–517, which cites only Bădescu–Panangaden and
  Yuan–Villanyi–Carbin by name). A second mention is in the "Citations
  TODO" ledger near the end of the document (D-list, "Araújo et al.
  1309.7976 (the single-query no-go AND the 1⊕U possibility — the kernel
  argument)"), which likewise does not pin it to §3.5. The paper's
  *content* does support §3.5's guardrail-1 rationale (unitary witness
  ⇔ the "where U acts" side-information), so the substance of the task
  brief is correct, but an implementer transcribing citations into §3.5
  itself should know the PRD's own text currently attaches this
  reference to §1.1/the citations ledger, not to §3.5's prose. Flag for
  whoever writes the §3.5 docstrings: either cite Araújo et al. in §1.1
  as the PRD already does, or add an explicit cross-reference in §3.5 if
  the guardrail-1 docstring wants a direct pointer — don't silently
  invent a §3.5 locator that isn't in the source document.
- **"Single-exact-query no-go" — confirmed accurate.** The paper's setup
  is explicitly one call to `U` (p. 1); PRD-v2's label is faithful.
- **"a section of U(d) → PU(d)"; "the papers phrase it as the
  non-existence of a continuous phase choice"** (PRD-v2 §1.1, line ~64–66)
  is PRD-v2's **own gloss**, explicitly flagged as such ("in our gloss").
  This paper's actual argument (Eqs. 1–6) is a finite-dimensional,
  discrete contradiction over three specific qubit unitaries
  (`X`, `Z`, `H`, then the `Y`-containing pairs) — it does not itself
  invoke sections, `PU(d)`, or continuity/topology language. The
  "continuous phase choice" / topological framing belongs properly to
  Gavorová–Seidel–Touati (arXiv:2011.10031), cited in the same PRD-v2
  sentence as the "strongest form" and whose own distillation should
  carry the winding/homotopy argument. Do not attribute the topological
  framing to Araújo et al. when writing docstrings — cite Araújo et al.
  1309.7976 only for the single-query linearity/phase contradiction
  (Eqs. 1–6) and the constructive `1_d⊕U` half; cite Gavorová et al. for
  the continuity/section language.
- **"the flip side is the constructive half... extending `1⊗U` to
  `1⊕U`"** (PRD-v2 §1.1, line ~67–69) — confirmed accurate; this is
  exactly the paper's p. 3 argument, down to the `1⊗U` (subsystems, the
  circuit model's existing wire mechanism) vs `1⊕U` (subspaces, the
  paper's proposed extension) contrast, which the paper itself draws
  explicitly.
- **Journal reference not previously in the PRD text.** Sturm-PRD-v2.md
  cites this work only by arXiv id (1309.7976); the published version is
  *New J. Phys.* **16**, 093026 (2014) — worth adding to whichever
  docstring/bibliography ultimately renders full citations.
