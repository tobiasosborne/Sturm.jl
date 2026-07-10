# ASDF — A Compiler for Qwerty, a Basis-Oriented Quantum Language

Source: A. J. Adams, S. Khan, A. S. Bhamra, R. R. Abusaada, A. M. Cabrera,
C. C. Hoechst, T. S. Humble, J. S. Young, T. M. Conte, "Asdf: A Compiler
for Qwerty, a Basis-Oriented Quantum Programming Language",
*Proc. 2025 Int. Symp. on Code Generation and Optimization* (CGO '25).
arXiv:2501.13262v1 [quant-ph], 22 Jan 2025. MIT-licensed compiler at
`github.com/gt-tinker/qwerty`. PDF in `docs/physics/asdf_2501.13262.pdf`.
("Asdf" is a keyboard pun on "Qwerty" — footnote 1, p. 2; it is **not** an
acronym, and in particular has **nothing to do with automatic
differentiation.**)

This is the citation PRD-v2 §3.3 attaches — alongside the Qwerty language
paper (Adams et al., arXiv:2404.12603, in `docs/physics/qwerty_2404.12603.pdf`)
— to the `dual` conjugate view, as the "nearest prior art": ASDF is the
**companion compiler** for Qwerty, and it is the concrete evidence that
Qwerty's basis change `>>` is realised by *circuit synthesis*, which is
exactly what Sturm's passive `dual` view avoids. The PRD wording is exact
and deliberate (§9 citations list): "`>>` is synthesized — never claim
they 'considered and rejected' the view reading, they simply don't discuss
it; the canonicity-buys-the-view point is ours."

**What the paper actually is** (read honestly, per CLAUDE.md principle 9):
a *quantum compiler engineering* paper. It builds an MLIR-based compiler
(two custom dialects, "Qwerty IR" and "QCircuit IR") that lowers the
high-level basis-oriented Qwerty language down to OpenQASM 3 / QIR. Its two
headline compilation problems are (1) **synthesizing quantum circuits from
basis translations** and (2) **automatically specializing adjoint /
predicated forms of functions**. It contains **no automatic
differentiation, no new physics, no new quantum algorithm** — it is a
resource-competitive lowering pipeline evaluated against Qiskit / Quipper /
Q# (§8). For Sturm we distill only §2.2 (the basis-translation semantics),
§5.2–5.3 and §6.3–6.4 (the synthesis / specialization mechanics) — these
are the parts that ground the view-vs-synthesis differentiation.

---

## Qwerty's core primitive: the basis translation `b_in >> b_out` (§2.2, pp. 2–4)

Qwerty is *basis-oriented*: programs are written in terms of orthonormal
bases and functions, not gates (§1, §2.2). Every basis is built from four
**primitive bases** (p. 3): `std` (the Z eigenbasis), `pm` (X eigenbasis),
`ij` (Y eigenbasis), and `fourier[N]` (the N-qubit Fourier basis). Bases
compose by tensor product (`b1 + b2`) and N-fold tensor (`b[N]`), and may
list explicit **basis literals** `{bv1, …, bvm}` of qubit literals with
optional phases (`bv @ theta`).

The **basis translation** `b_in >> b_out` is "the core computational
primitive of Qwerty" (p. 3). Given input basis `b_in` with vectors
`|b_in^(i)⟩` and output basis `b_out` with vectors `|b_out^(i)⟩`, it maps

```
Σ αᵢ |b_in^(i)⟩  ↦  Σ αᵢ |b_out^(i)⟩          (p. 3, unnumbered)
```

i.e. it **preserves the amplitudes** and re-labels the basis vectors
positionally. It is unitary precisely because both bases are orthonormal
and span the same subspace: `span(b_in) = span(b_out)` (the well-typedness
condition, §4.1). Example (p. 4): `{'01','10'} >> {'10','01'}` **is** a SWAP
gate — the translation is written as a permutation of basis vectors, and
the compiler must produce the gate circuit.

**Type checking a translation is span-equivalence checking** (§4.1, p. 4),
which is nontrivial: a naïve product-of-vectors check is `O(2^64)` on wide
bases, so ASDF factors the tensor structure and checks span equivalence in
`O(k² log k)` (Fig. 3; Appendix B). *This cost is itself a signal:* even
deciding that a basis change is well-typed is superpolynomial-naïve for
arbitrary user bases — the generality is expensive from the front door.

---

## The central compilation problem: synthesizing gates from a basis translation (§6.3, pp. 8–10)

> "The toughest challenge in lowering Qwerty IR to QCircuit IR is
> synthesizing the quantum gates that achieve a basis translation. **This
> is the most novel part of Asdf, in fact, as we are not aware of prior
> compilers that synthesize basis translations, only implementations that
> do more general (and more expensive) unitary synthesis** [44]." (§6.3, p. 8)

This is the sentence the PRD §3.3 leans on. A basis translation is **not** a
reinterpretation in ASDF; it is compiled into an explicit gate sequence.
The synthesized circuit has a fixed seven-stage structure (Fig. 6, p. 9,
read left to right):

1. **Standardize (unconditional)** — translate qubits from their primitive
   basis (`pm`, `ij`, `fourier`) into `std` (the computational/Z basis)
   using `H`, `S`, or N-bit inverse QFT gates (p. 9).
2. **Standardize (conditional)** — controlled forms of the above, needed
   when the translation is predicated (see §5.3).
3. **Vector phases (left)** — re-introduce input-side phases via
   X-conjugated multi-controlled-`P(θ)` gates (p. 10; Fig. 8 gives the
   three-qubit Grover-diffuser example).
4. **Permute std basis vectors** — the residual reversible classical
   permutation `f : 𝔹ⁿ → 𝔹ⁿ` on `std[n]` vectors, synthesized by the
   **Tweedledum** transformation-based synthesis library [40] (p. 10;
   Fig. 9). Alignment/factoring precedes it when the two basis lists differ
   in shape (Appendix F).
5. **Vector phases (right)** — output-side phases, same mechanism as (3).
6. **Destandardize (conditional)** — adjoint of stage (2).
7. **Destandardize (unconditional)** — adjoint of stage (1); undoes the
   standardization on the output side.

Key structural fact (p. 9): unconditional (de)standardizations of a
*predicated* translation need **not** be controlled — they cancel against
their own inverses on states outside the predicate ("conjugated by
unconditional (de)standardizations"); only the *conditional* ones carry
controls. Span-equivalence (§4.1) is what guarantees all predicates live in
unconditional standardizations (p. 10). The net cost is a genuine
multi-gate circuit: `H`/`S`/IQFT layers + a Tweedledum-synthesized
permutation + multi-controlled-`P(θ)` phase gates, with multi-controlled
gates finally decomposed via Selinger's controlled-`iX` scheme to cut
T-count (§6.5, p. 11).

**Takeaway for the differentiator:** Qwerty's `>>` between *arbitrary*
user-named bases is a maximally general construct, and ASDF pays for that
generality with per-translation circuit synthesis — the paper explicitly
states no cheaper route than their basis-translation-specific synthesizer
is known, the alternative being *even more expensive* general unitary
synthesis [44].

---

## Automatic specialization: adjoint and predicated function forms (§5.2–5.3, pp. 6–7)

The second headline problem. A Qwerty function of reversible type
`T1 →rev T2` can be invoked backward (`~f`, adjoint) or in a subspace
(`b & f`, predicated). ASDF generates these *specializations* structurally
on the Qwerty IR:

- **Adjoint** (§5.2, p. 6; Fig. 4): `buildAdjoint()` traverses the def-use
  DAG of a basic block backward from the terminator, rebuilding a reversed
  form top-down via an `Adjointable` op interface. Classical `arith` ops
  that define `f64` phase angles are **stationary** — they stay in place
  and are inverted *around*, not adjointed (p. 6). No hardware run-backward
  capability is assumed; the adjoint is a compile-time rewrite.
- **Predicated** (§5.3, pp. 6–7; Fig. 5): `buildPredicated()` adds a
  control basis element (e.g. `{'111'}`) to *both sides* of each basis
  translation. Because SSA-renaming can realise swaps for free, predication
  must then *undo* renaming-based swaps that lie outside the predicate — the
  "SWAP / unswap in orthogonal spaces" trick (one uncontrolled SWAP to undo
  the logical swap globally, one predicated SWAP to redo it inside the
  predicate; p. 7).
- **Specialization analysis** (§6.2, pp. 7–8): an interprocedural dataflow
  pass labels each callable with the `(funcName, isAdjoint, numControls)`
  tuples it is invoked under, iteratively closing transitive call-graph
  edges (Appendix D), so only the needed specializations are generated.

## Classical-function / Bennett-embedding synthesis (§6.4, p. 10)

`@classical` Qwerty functions are lowered to a reversible logic network
(mockturtle) and handed to **Tweedledum** [40], which produces the
**Bennett embedding**

```
U_f |x⟩|y⟩ = |x⟩ |y ⊕ f(x)⟩          (§6.4, p. 10)
```

The phase (sign) oracle `f.sign` is `U'_f |x⟩ = (−1)^{f(x)} |x⟩`, obtained
by feeding a `|−⟩` ancilla into `U_f` (phase kickback; p. 10). This is the
standard Bennett construction — the same bridge Sturm's `oracle(f, x)` /
`bennett/` layer provides (Perm process values), and a useful external
confirmation of the phase-kickback lowering.

---

## Relevance to Sturm v2

1. **The view-vs-synthesis differentiator (PRD §3.3, milestone M4).** Sturm's
   `dual(q)` is a *lazy, zero-cost, involutive addressing mode* (the
   `transpose` idiom): ops **through** a view lower by conjugating the
   kernel process, and `dual` itself unwraps at dispatch time
   (`dual(v::DualView) = v.parent`) — it never applies the basis-change
   unitary. ASDF is the concrete prior art that shows the alternative:
   Qwerty's basis change `>>` is compiled into an actual synthesized gate
   circuit (§6.3 seven-stage structure above). Cite ASDF for **"`>>` is
   synthesized, not reinterpreted."** The differentiation is
   *canonicity-buys-the-view*: `>>` maps between *arbitrary* user bases (a
   strictly more general construct that structurally *requires* synthesis),
   whereas `dual` narrows to the **one canonical character-group dual**, and
   that narrowing is exactly what makes a passive reinterpretation possible.
   Follow the PRD's exact framing: ASDF and Qwerty **do not discuss** the
   view reading — do NOT write that they "considered and rejected" it; the
   view point is Sturm's, the synthesis fact is theirs.

2. **`F² = parity as a process` (PRD §3.3) is consistent with ASDF's
   stance, not contradicted by it.** In Sturm, `dual(dual(x)) === x`
   structurally (views unwrap), while materialising the view as a *process*
   (applying its unitary F) composes and yields F² = parity. ASDF only ever
   has the *process* side — it must emit the standardization circuit (`H`,
   IQFT, …) every time — because it lacks the canonical-dual restriction
   that lets Sturm keep the structural unwrap. ASDF thus grounds the "if you
   lower `dual` by applying F you have the synthesis cost (and the integer-
   negation bug signature)" warning by exhibiting a system that pays that
   cost as its normal mode of operation.

3. **`when(dual(q))` / predication (PRD §3.3, §3.5).** ASDF's §5.3
   predication — adding controls to both sides of a translation, with the
   SWAP/unswap orthogonal-space cleanup — is the synthesis-side analogue of
   Sturm's coherent control in a conjugate basis. Sturm lowers this through
   the single `ctrl` homomorphism choke point (PRD §4.2) and basis-change
   conjugation of the control wire, rather than rebuilding a block per
   predicate. Useful contrast, not a dependency.

4. **Adjoint = conjugate view vs. `buildAdjoint()` (PRD §3.3 / §4.1).**
   ASDF specializes adjoints by a backward def-use DAG rebuild (§5.2), with
   classical phase ops held *stationary*. Sturm gets `adjoint` for free from
   the `U2` quaternion conjugate (kernel, `docs/physics/wharton_koch_*.md`)
   and the view-unwrap discipline — no per-function DAG rebuild. The
   "stationary classical ops are inverted around, not adjointed" observation
   (p. 6) echoes Sturm's phase-discipline invariant that the phase quotient
   is crossed once, at application, not in library rewrites.

5. **Bennett bridge (§6.4).** External confirmation of the
   `U_f|x⟩|y⟩ = |x⟩|y⊕f(x)⟩` embedding and the `|−⟩`-ancilla phase oracle
   `(−1)^{f(x)}` that Sturm's `bennett/` layer (`oracle(f, x)`, Perm values)
   implements. Cite as corroborating prior art for the oracle lowering, not
   as a novel result.

---

## ⚠ Caveats — read before citing

- **NOT an automatic-differentiation paper.** The tasking that reached this
  distillation floated "automatic differentiation" as possible content.
  There is none. "Asdf" is a keyboard pun on "Qwerty" (footnote 1, p. 2).
  The paper's "automatically specializing" refers to auto-generating
  **adjoint (`~f`) and predicated (`b & f`) forms of functions** (§5.2–5.3)
  — reverse/subspace execution, *not* differential calculus. Any Sturm
  docstring that cites 2501.13262 for AD would be an inverted citation of
  the CSW class r6 caught. Do not.

- **The PRD's actual citation is SOUND — no mismatch.** PRD §3.3 cites ASDF
  for the single claim that Qwerty's `>>` is compiled by circuit synthesis
  and that this is the language's central compilation problem. The paper
  supports this at full strength: abstract ("synthesizing circuits from
  basis translations"), §1 ("which the compiler must synthesize as a
  quantum circuit"), and §6.3 ("the toughest challenge … the most novel
  part of Asdf … we are not aware of prior compilers that synthesize basis
  translations"). The PRD's paraphrase "names 'synthesizing circuits from
  basis translations' as the core compilation problem" is accurate.

- **Cite ASDF for the *synthesis fact*, never for the *view idea*.** The
  passive-view / canonicity-buys-the-view contribution is Sturm's. ASDF
  does not treat a basis change as a view and does not argue against doing
  so — it simply operates in the synthesis regime because its `>>` is more
  general. State the contrast as "they synthesize; we, having restricted to
  the canonical dual, reinterpret," never as "they rejected the view."

- **Engineering, not physics.** Per CLAUDE.md principle 4, this paper
  grounds a *compilation strategy contrast*, not a quantum-mechanical law.
  It carries no theorem Sturm's kernel depends on (the span-equivalence
  `O(k² log k)` result, Appendix B, is Qwerty-type-checking-specific and
  irrelevant to Sturm's narrowed `dual`). Keep its citations scoped to the
  view-vs-synthesis differentiation and the Bennett-embedding corroboration.
