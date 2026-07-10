# Qwerty — A Basis-Oriented Quantum Programming Language

Source: A. J. Adams, S. Khan, A. S. Bhamra, R. R. Abusaada, J. S. Young,
and T. M. Conte, "Qwerty: A Basis-Oriented Quantum Programming Language",
arXiv:2404.12603v2 [quant-ph], submitted 19 Apr 2024, last revised
17 Jun 2025. DOI: 10.48550/arXiv.2404.12603. CC-BY-4.0. PDF in
`docs/physics/qwerty_2404.12603.pdf` (21 pages, 38 figures). Georgia Tech
(Adams, Bhamra, Abusaada, Young, Conte) + Google (Khan). Companion
compiler paper (the circuit-synthesis mechanics): ASDF, arXiv:2501.13262
(not distilled here; cited by reference).

This is the citation PRD-v2 §3.3 attaches to `dual`/the conjugate view as
**nearest prior art**: "The nearest neighbour is Qwerty (Adams et al.,
arXiv:2404.12603) … its basis translation `>>` is compiled to a
*synthesized circuit* … and Qwerty never treats a basis change as a
passive view." This distillation grounds that differentiation against the
actual constructs, and — per CLAUDE.md principle 9 — verifies each PRD
claim against the paper (see the mismatch audit at the end; session-92's
"considered and rejected" wording was found unsupported and has already
been corrected in the PRD, but the audit re-confirms the current wording).

Qwerty is a Python-embedded DSL. The whole design pivots on one idea
(§I): **programs are expressed through basis translations instead of
low-level circuitry.** That idea is the closest thing in the literature
to Sturm's conjugate-view surface — and precisely where the two diverge.

---

## The surface constructs (§III–VII)

### Qubit literals and tilt (§III, Figs. 2, 6)
State *preparation* is written as string-like literals: `'0'`, `'1'` are
`|0⟩,|1⟩`; `'p'`, `'m'` are `|+⟩,|−⟩`; `'i'`, `'j'` are the Y-eigenstates
`|+i⟩,|−i⟩`; `*` is tensor product (`'01' == '0'*'1'`). A phase is applied
with **tilt** `@`: `'1'@45` is `e^{iπ·45/180}|1⟩` (degrees); `-'1'` is
sugar for `'1'@180`. Superposition literal: `('0'+'1') == 'p'`, with
optional probabilities `(0.75*'0'+0.25*'1')`. **Ensemble literal** `^`
(written `∧` in prose, §III-B, Fig. 3) is a *mixed* state (classical
distribution, no interference) as distinct from the pure superposition
`+`. `qubit` is a **linear type** (§III-C, refs [19]–[21]); discard must
be explicit (`discard`, Fig. 4).

### Basis literals (§IV-A, Fig. 6)
A **basis** is a first-class value: an ordered list of orthonormal basis
vectors, each a qubit/superposition literal. `std = {'0','1'}`,
`pm = {'p','m'}`, `ij = {'i','j'}`, `bell = {'00'+'11', '00'+-'11',
'10'+'01', '01'+-'10'}` (Fig. 6). Tensor/power: `{'0','1'}**2`. The type
checker enforces mutual orthogonality (T-BLIT, Fig. 25).

### Basis translation `>>` — THE state-evolution primitive (§IV)
`bin >> bout` is Qwerty's *fundamental state-evolution primitive*
(§II, §IV). It is a **substitution rule**: `{'0','1'} >> {'m','p'}`
replaces `'0'↦'m'` and `'1'↦'p'` simultaneously. Sugar: single-vector
bases collapse (`'1' >> -'1'`); element-wise form `{'0'>>'1','1'>>'0'}`.
The Grover diffuser is literally `'pppp' >> -'pppp'` — "replace |+⟩⊗4 with
−|+⟩⊗4" (§II, Fig. 1/2).

**Type checking (§IV-B):** the checker demands `span(bin) = span(bout)` —
this is what guarantees `>>` denotes a **unitary**. `{'0'} >> {'1','0'}`
is rejected (spans differ). Both bases must carry padding `'?'` atoms at
the same positions.

**Mathematical view (§IV-E) — the actual operator.** For
`{bv₁,…,bvₘ} >> {bv′₁,…,bv′ₘ}` the represented unitary is
```
U = Σⱼ |bv′ⱼ⟩⟨bvⱼ|  +  Σₖ |bv⊥ₖ⟩⟨bv⊥ₖ|
```
where `{|bv⊥ₖ⟩}` is any orthonormal basis of `span(bv₁,…,bvₘ)⊥` — the
orthogonal complement **passes through unchanged**. The paper reads this
three ways: a classical permutation of computational basis vectors (when
all `bvᵢ,bv′ⱼ` are computational); "a classical permutation **conjugated
with changes of basis**" in general; or an **SVD with all singular values
1**. Mini-Qwerty formalizes exactly this as `U_{b1→b2}` (Appendix A.3,
E-BTRANS, Fig. 35) and evolves the state by *applying* it.

### Measurement (§IV-C) — compiles to a translation
Measurement is basis-parametric: `pm.measure` is an X-measurement,
`fourier[[N]].measure` a Fourier-basis measurement, `bell.measure` a
Bell-basis measurement (Fig. 5). **But it is not primitive:** "any
`b.measure` compiles to a basis translation `b >> {'0','1'}**N` followed
by `({'0','1'}**N).measure`" (§IV-C, verbatim). Fourier measurement =
synthesize the QFT-shaped translation, then measure in `std`.

### Basis generators and the Fourier basis (§V, Figs. 6–8)
`fourier[[N]]` is defined **recursively in the prelude** (not a hardware
intrinsic): `fourier[[1]] = pm`; `fourier[[N]] = fourier[[N-1]] //
std.revolve`, where `.revolve` is a **basis generator** producing the
list of tilted `'1'`s in steps of `360/2^N` degrees (Fig. 8, a
reinterpretation of Nielsen–Chuang Eq. 5.4). "The knowledge of basis
structure in the compiler provided by basis generators allows **efficient
synthesis of basis translations** as e.g. efficient quantum Fourier
transform circuits" (§V — the synthesis claim, in the authors' words).

### Predication / basis patterns (§VI, Figs. 10, 13) — control generalized
`f if b else id` runs `f` only on the subspace matching basis pattern `b`;
`'_'` is the **target** position acted on, `'?'` is padding neither matched
nor acted on. `(flip if '1_' else id)` is exactly a CNOT; general patterns
like `(pm >> std if {'p_p','m_m'} else id)` are strictly richer. Qwerty
frames predication as a *generalization of controls* ("run functions only
on states where a basis pattern is satisfied", §VI). This is Qwerty's
analogue of Sturm's `when` (construct 5).

### Adjoint `∼e` (Appendix A, Figs. 19, 33, 38)
`∼e` yields the **adjoint of a reversible function** e (§A.1: "The syntax
`∼e` yields the adjoint of a function e. (This syntax also exists in
Qwerty, although the main text omits discussion of it…)"). Typed by T-ADJ
on `qubit[m] --rev--> qubit[m]`, executed by conjugate-transposing the
represented unitary `U†` (E-ADJPIPE, Fig. 38). **Note carefully: `∼` is an
operator on FUNCTIONS, not a view on registers** — it adjoints a process,
it does not reinterpret a wire. This is the construct most easily confused
with Sturm's `dual`, and it is categorically different (see Relevance §3).

### Classical-function embeddings (§VII, VIII) — the Bennett analogue
A `@classical` function `f` has three quantum embeddings chosen by the
programmer: `f.sign` (phase/`|−⟩`-kickback oracle, `|x⟩↦(-1)^{f(x)}|x⟩`,
used by Grover & Bernstein–Vazirani), `f.xor` (`|x⟩|y⟩↦|x⟩|y⊕f(x)⟩`, the
Bennett/standard oracle), and `f.inplace` (reversible in-place, requires
`@reversible`). "the `f.sign` construct leaves synthesis of a Bennett
embedding of f and preparation of the |−⟩ ancilla to the compiler"
(§VIII-A). This is Qwerty's counterpart to Sturm's `oracle` / Bennett
bridge (construct 7).

### Compilation pipeline (§V)
`@qpu` function → **expand metaQwerty → Qwerty** (macro/prelude expansion,
dimension-variable inference) → **type check** → **circuit synthesis**.
The whole point of first-class bases + basis generators is to give the
compiler enough structure to *synthesize efficient circuits* from
declarative basis specs. The synthesis algorithms are the subject of the
companion paper ASDF (arXiv:2501.13262).

### Formal core (Appendix A: Mini-Qwerty)
A Selinger–Valiron-style quantum λ-calculus with linear types
(`qubit[m]` linear; `bit`, functions, `unit` nonlinear), `rev`/`irrev`
function kinds, small-step semantics `[|ψ⟩; e] --p--> [|ψ′⟩; e′]` over a
concrete state `|ψ⟩`, and progress/preservation + universality proofs
(A.4). The salient fact for Sturm: **every state-changing rule applies a
unitary to `|ψ⟩`** (E-BTRANS applies `U_{b1→b2}`, E-ADJPIPE applies `U†`,
E-PREDPIPE applies a block-diagonal predicated `U`). There is no lazy /
borrow / view value in the semantics at all — `>>` is denotationally an
operator that acts.

---

## Relevance to Sturm v2

### 1. Qwerty is the nearest prior art, and the honest overlap is real
Both languages replace gate/circuit surface syntax with a
basis/structure-oriented vocabulary, both make bases (or their character
duals) first-class-ish, both keep classical oracles as classical code
lifted by a compiler-synthesized Bennett embedding (`f.xor`/`f.sign` ≈
Sturm `oracle`), both generalize control to a richer predicate (`f if b
else id` ≈ `when`). PRD-v2 §3.3 must cite Qwerty *and* ASDF and must
**not** overclaim novelty on any of these axes. The distillation confirms
the overlap is genuine — the differentiation must be narrow and precise.

### 2. THE differentiator — view (unwrap) vs. translation (synthesize)
Sturm's `dual(q)` is a **lazy addressing mode**: a borrow-not-own wrapper
that *conjugates the operations routed through it*, unwrapping
involutively (`dual(dual(q)) === q` by dispatch, never by applying F² —
PRD-v2 §3.3, "views unwrap; processes compose"). No circuit is emitted by
`dual` itself; it re-routes the *next* op through the kernel's conjugation.

Qwerty's `>>` is the **opposite denotation**: it *is* a process. Its
meaning is the operator `U = Σ|bv′ⱼ⟩⟨bvⱼ| + Σ|bv⊥ₖ⟩⟨bv⊥ₖ|` (§IV-E), and
the compiler **synthesizes a circuit** realizing it (§V; ASDF). A basis
change in Qwerty is an *applied unitary*, not a passive reinterpretation.
Even `.measure`, the one place Qwerty could have made a basis a passive
readout frame, is *defined* to compile to `b >> std**N` then a std
measurement (§IV-C) — synthesis, again.

**Why Qwerty structurally cannot have Sturm's view.** `>>` maps between
*arbitrary user-named* orthonormal bases (`pm >> std`, `bell`,
`{'p_p','m_m'}`), a strictly more general construct than a canonical dual.
A pure reinterpretation (zero-cost, involutive) is only available when the
"other basis" is *canonically determined* by the register's type — Sturm
narrows to the **one character-group / Pontryagin dual** `Ĝ` of the
register's group `G`, and it is exactly that narrowing that buys the view.
Qwerty's generality forecloses it: there is no canonical `bout` to unwrap
to. This "canonicity-buys-the-view" point is Sturm's, and it is the one
sentence of the PRD-v2 §3.3 prior-art paragraph that carries the novelty.

### 3. `∼` (Qwerty adjoint) is NOT `dual` — the confusable near-miss
Qwerty *does* have a passive-looking unary operator, `∼e` (Appendix A).
It is tempting to read it as Sturm's `dual`. It is not: `∼` adjoints a
**function/process** (`U ↦ U†`, E-ADJPIPE), whereas `dual` wraps a
**register/wire** and swaps translation↔modulation (Pontryagin: `not!`↦X
becomes `not!(dual·)`↦Z; `add!` translates, `x̂ += a` modulates — PRD-v2
§3.3, review r6/B2). `∼` is `adjoint` on a `U2`-level process value (which
Sturm has in the kernel, `Sturm.adjoint`), not a surface addressing mode.
So Sturm's kernel `adjoint(V)` ≈ Qwerty `∼`; Sturm's surface `dual(q)` has
**no Qwerty counterpart**. Do not conflate them when citing.

### 4. What Qwerty does NOT have (claim these as absent in prior art)
- **Per-register lazy conjugate views** — no borrow/unwrap wrapper on a
  wire; every basis operation is an applied unitary (Appendix A semantics
  have no view value).
- **The Pontryagin / character-group framing** — no `Ĝ`, no
  translation↔modulation duality theorem; "duality" as a word does not
  appear. `dual`'s F²=parity / F⁴=1 process law and its involutive-unwrap
  distinction from it are entirely Sturm's.
- **The `transpose`-idiom law "views unwrap, processes compose"** — Qwerty
  has no analogue; a basis change is only ever the compose (synthesize)
  side.
- **Deterministic scope-as-Stinespring / silent-trace discipline** — out
  of Qwerty's scope (§X explicitly excludes Hamiltonian simulation and
  targets fault-tolerant synthesis).

### 5. One useful acknowledgment IN the paper (cite this, precisely)
§IV opens with the paper's own disclaimer: "(Traditionally, a basis
translation could be called a 'change of basis,' but this term may be
confused with the linear algebra operation that changes only the
**representation** of a vector, not its **value**.)" This is the closest
Qwerty comes to the view concept — and it is the *honest, supported*
version of the (retracted) "considered and rejected" claim: Qwerty
**names** the representation-only operation (which is exactly what Sturm's
`dual` is) and deliberately says `>>` is *not* that — `>>` changes the
value. Cite this line rather than any "they rejected the view" phrasing.

---

## PRD-claim audit (CLAUDE.md principle 9 — verify, don't trust)

Current PRD-v2 §3.3 "Prior art" ¶ and §9 Citations-TODO, checked against
the paper:

| PRD claim | Verdict |
|---|---|
| "first-class basis values (`std`, `pm`, `fourier[N]`)" | **TRUE**, modulo syntax: the Fourier basis is written `fourier[[N]]` (double bracket, Fig. 7), not `fourier[N]`. Minor; `std`/`pm` exact (Fig. 6). |
| "Fourier-basis measurement as a primitive" | **IMPRECISE.** It is a first-class *construct* (`fourier[[N]].measure`) but explicitly **not** a primitive: it compiles to `fourier[[N]] >> std**N` then std-measure (§IV-C), and `fourier[[N]]` is itself a recursively-defined prelude basis, not an intrinsic. Recommend "Fourier-basis measurement as a language construct (compiled to a basis translation + std measurement)." This actually *strengthens* Sturm's synthesis-vs-view point. |
| "its basis translation `>>` is compiled to a *synthesized circuit*" | **TRUE.** §IV-E gives the operator; §V says basis generators enable "efficient synthesis of basis translations"; ASDF (2501.13262) is the named synthesis paper. |
| "`>>` maps between *arbitrary* user-named bases — a strictly more general construct" | **TRUE** (§IV, §VI: `pm`, `bell`, `{'p_p','m_m'}`, arbitrary orthonormal literals). |
| "Qwerty never treats a basis change as a passive view … Structurally it cannot" | **TRUE**, and *directly supported* by the paper's own §IV disclaimer (representation-change vs value-change) — cite that line. |
| §9 note: "never claim they 'considered and rejected' the view reading, they simply don't discuss it" | **CORRECT and important.** The paper never discusses a view/reinterpretation reading of its own `>>`; the retracted session-92 claim ("explicitly REJECTS the zero-cost view reading") remains **unsupported** and would be a fabrication if reinstated. The current PRD wording is clean. The stale claim survives only in the historical `worklog/session-92.md` (line ~190) as a corrected-later record — do not propagate it forward. |
| "canonicity-buys-the-view point is ours" | **Novel vs Qwerty — confirmed.** No dual/character-group/Pontryagin content anywhere in the paper. |

**Net:** no fabricated claims in the current PRD. Two wording nits worth a
touch-up (`fourier[[N]]` bracket; "primitive" → "construct, compiled to a
translation"). The one genuine landmine — the "considered and rejected"
phrasing — was already caught in session-93/94 and is absent from the
live PRD; this audit re-confirms it must never return.
