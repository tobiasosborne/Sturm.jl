# Tang & Wright (2025) — Are Controlled Unitaries Helpful?

**Citation**: Tang, E. & Wright, J. *Are controlled unitaries helpful?*
arXiv:2508.00055v2 (23 Apr 2026; submitted 31 Jul 2025). quant-ph / cs.CC /
cs.DS. UC Berkeley.

**Local PDF**: `docs/physics/tang_wright_2508.00055.pdf`.

**Status in pipeline**: ground-truth source for the **U(2) phase discipline of
the kernel** — specifically *why the process-value representation must carry
global phase explicitly and why `ctrl` is the choke point where that phase
becomes physical* (milestone M1, beads `Sturm.jl-kvtb`). Cited by PRD-v2 §4.2
(line ~863): "Tang–Wright, arXiv:2508.00055 Thm 1.1, is the formal statement of
why control makes global phase physical." Grounds PRD-v2 §4.1 (U2 = quaternion +
phase, double-cover equality, `+I ≠ −I`) and §4.3 (the phase quotient is crossed
exactly once, at application).

---

## What this paper does (one line)

It proves that access to the **controlled** version `cU` of a black-box unitary
`U` is **no more powerful than access to `U` itself for any problem that is
invariant under the global phase of `U`** — i.e. `cU` is useful *only* because
it exposes information about the global phase of `U`. Any circuit querying `cU`
(and `cU†`, `cU*`, `cUᵀ`) is mechanically "decontrolled" into one querying only
`U`, `U†`, `U*`, `Uᵀ`, at the cost of outputting the state for a **uniformly
random global phase** `φ` applied to `U`.

This is a *negative / complexity* result about oracle access models. It is **not**
a recipe for representing a 1-qubit unitary, and it never mentions quaternions,
SU(2), or the U2 data structure. Its relevance to Sturm is that it is the
rigorous, quantitative statement of the single fact the U2 design turns on:
**global phase is exactly the information that control — and only control —
makes physical.** See "Relevance to Sturm v2" for the honest scope note.

---

## Definitions and the central question

**The controlled unitary** (p. 2, unlabeled display):

>   `cU = |0⟩⟨0| ⊗ I + |1⟩⟨1| ⊗ U = [[I, 0], [0, U]]`  (block-diagonal).

**The canonical separating example** (p. 2): given oracle `U`, decide whether
`U = I` or `U = −I`. With access to `U` alone this is **impossible** — a
quantum circuit querying `U` "cannot distinguish the difference in global phase
between the two cases." With `cU`, a **single query** solves it. This is the
paper's own compact statement of `+I ≠ −I` **as an observable fact under
control**, and it is precisely Sturm's `ctrl(−I) ≠ ctrl(+I)`.

**The question the paper answers** (p. 2, displayed):

>   "Is `cU` ever useful for a problem which is invariant under global phase?"

Answer: **no**.

**Notation** (p. 3, "Notation"): `i = √−1`; `C_q = { e^{2πik/q} : k = 0,…,q−1 }`
the group of `q`-th roots of unity; `C_∞ = { e^{iθ} : 0 ≤ θ < 2π }` the complex
unit circle. `M*, Mᵀ, M†` are conjugate, transpose, conjugate-transpose.

---

## The main theorem

**Theorem 1.1 (Wresting quantum control from a quantum circuit)** — p. 3.

> Consider a quantum circuit (possibly with ancilla, measurements, partial
> traces) which queries `cU, cU†, cU*, cUᵀ` a cumulative total of `n` times and
> produces output state `ρ(U)`. Then there is a method to convert this circuit
> into one which outputs
>
>   `ρ̂ = E_{φ ∼ C_∞} [ ρ(φU) ]`
>
> and which replaces every controlled query with its **un**-controlled variant.
> Further, for every `q > n`, `ρ̂ = E_{φ ∼ C_q} [ ρ(φU) ]`.
>
> When `U` acts on `log₂(d)` qubits, the simulation uses `⌈log₂(n)⌉ + 2·log₂(d)`
> additional qubits and `O(n·(log(n) + log(d)))` additional gates. (Overhead
> reducible; see Proposition 2.8.)

The key structural fact (p. 3): the random phase `φ` in the decontrolled circuit
is **consistent across all queries** — the simulated circuit "can expect the
same controlled unitary every time it queries it." The output is the original
circuit run with `c(φU)` for one random `φ`, not an independent phase per query.

**Corollary 1.2** (p. 3): quantum control of **state-preparation unitaries** does
not help for distinguishing-class tasks — `n` queries to `cU, cU†` ⇒ `n` queries
to `U, U†`, because a state-preparation unitary for `σ` remains one for any `φU`.

**Corollary 1.3** (p. 4): quantum control does not help for **property-testing
commutativity** of `U, V` (answers Montanaro–de Wolf [MW16] Question 10 in the
negative). Applies Theorem 1.1 twice; uses that `‖(φU)(φV) − (φV)(φU)‖_F =
‖UV − VU‖_F` (Frobenius norm is phase-invariant).

**Corollary 1.5** (p. 6–7): PRUs (Definition 1.4) secure against
`U, U†, U*, Uᵀ` queries can be **upgraded** to PRUs secure against
`cU, cU†, cU*, cUᵀ` by tacking on a uniformly random global phase
`U_{n,(k,φ)} = φ · U_{n,k}` with `φ ∈ C_{q_n}`, `q_n = 2ⁿ`.

**The general principle** (p. 4, "By applying Theorem 1.1…"): problems on
**unitary matrices** have a canonical global phase (hence can benefit from `cU`);
problems on **unitary channels** `σ ↦ UσU†` have no canonical phase, so
`c(φU)` for random `φ` suffices — *"cU does not help for any 'physical' problem
involving U."* Where global phase **does** matter (p. 5–6): **phase estimation**
[Kit95] (spectrum of `U` depends on its global phase — mapping `|v⟩ ↦ |v⟩|λ⟩`);
**phase oracles** `Q|x⟩ = (−1)^{f(x)}|x⟩` where the sign of `Q` vs `−Q` matters;
and **LCU / linear combinations of unitaries** `αU + βV` (relative phase between
`U` and `V` is physical).

---

## The decontrolling mechanism (proof, §2, pp. 8–14)

The construction is Feynman-path bookkeeping of phase powers; this is the exact
"phase must be tracked" logic that Sturm centralizes.

**Sign of a query type — Definition 2.1** (p. 10): `σ : {1, †, *, ᵀ} → {±1}`
with `φ^? = φ^{σ(?)}`; concretely `σ(1) = σ(ᵀ) = +1`, `σ(†) = σ(*) = −1`. A query
to `U` or `Uᵀ` counts `+1` toward the phase power; `U†` or `U*` counts `−1`.

**Feynman-path decomposition — Claim 2.3** (p. 11): for `|φ| = 1`,

>   `|Circ(c(φU))⟩ = Σ_{b∈{0,1}ⁿ} φ^{?ₙbₙ}···φ^{?₁b₁} |FP_{b₁,…,bₙ}⟩ = Σ_k φ^k |FP(k)⟩`,

i.e. the output is graded by the net phase power `k` accumulated along control-set
branches. Because `cU = |0⟩⟨0|⊗I + |1⟩⟨1|⊗U`, only branches where the control bit
was `1` pick up a factor of `U` **and** of `φ` — the phase and the operator are
inseparable, which is the whole point.

**Averaging kills cross terms — Claim 2.4** (p. 11–12): `E_{φ∼C_q}[φ^{k−ℓ}] = 1`
iff `k ≡ ℓ (mod q)`, so `E_{φ∼C_q}[ |Circ(c(φU))⟩⟨·| ] = Σ_{k=0}^{q−1}
|FP(k mod q)⟩⟨FP(k mod q)|` — a **classical mixture** over phase-power sectors.

**The decontrol gadget `S(U, ?)` — Eq. (2)** (p. 12). Introduce a counter
register `K` (dimension `n+1`) and two "hold" registers `H, Hᵀ` (each dimension
`d`) initialized to the maximally entangled state `|Φ⟩ = (1/√d) Σᵢ |i⟩_H|i⟩_{Hᵀ}`.
Each controlled query is replaced by:

>   `S(U,1)  = |0⟩⟨0|_C ⊗ I_R ⊗ U_H     + |1⟩⟨1|_C ⊗ U_R  ⊗ Add(+1)_K`
>   `S(U,†)  = |0⟩⟨0|_C ⊗ I_R ⊗ U†_H    + |1⟩⟨1|_C ⊗ U†_R ⊗ Add(−1)_K`
>   `S(U,*)  = |0⟩⟨0|_C ⊗ I_R ⊗ U*_{Hᵀ} + |1⟩⟨1|_C ⊗ U*_R ⊗ Add(−1)_K`
>   `S(U,ᵀ)  = |0⟩⟨0|_C ⊗ I_R ⊗ Uᵀ_{Hᵀ} + |1⟩⟨1|_C ⊗ Uᵀ_R ⊗ Add(+1)_K`

When the control is `1`, apply the query to the real register `R` **and**
increment/decrement the counter (this reproduces the `φ^{±1}` bookkeeping without
ever knowing `φ`); when the control is `0`, apply the query to a **hold** register
so a decohered copy is still consumed. Tracing out `K, H, Hᵀ` yields
`Σ_k |FP(k)⟩⟨FP(k)|`, matching Claim 2.4.

**Ricochet property — Fact 2.5** (p. 13): for Choi state `|Φ(X)⟩ = (1/√d) Σ_{i,j}
X_{i,j} |i⟩|j⟩`,

>   `(X ⊗ I)|Φ⟩ = (I ⊗ Xᵀ)|Φ⟩ = |Φ(X)⟩`.

This is why the `*`/`ᵀ` gadgets act on `Hᵀ` via the transpose register.

**Correctness — Claim 2.6 + Theorem 1.1 proof** (p. 13–14): each gadget costs two
controlled-SWAPs and one adder mod `n+1`, `O(log(n) + log(d))` two-qubit gates
per query. **Remark 2.7** (p. 14): uncontrolled queries `U, U†, U*, Uᵀ` in the
original circuit pass through untouched — their `φ` is a genuine global phase and
adds no observable effect. **Proposition 2.8** (p. 14): variants with lower
space/gate overhead.

---

## Relevance to Sturm v2

The paper is the **formal grounding for why the kernel works in U(2), not in a
silent SU(2) section** (PRD-v2 §4.1–4.3). It supplies the *why*, not the *how* —
it says nothing about quaternions or the U2 struct; it is the rigorous statement
of the single invariant that forces the U2 design. Concretely:

1. **`ctrl` makes global phase physical — hence phase must be carried, not
   quotiented (PRD §4.1, `+I ≠ −I`).** `cU = |0⟩⟨0|⊗I + |1⟩⟨1|⊗U` is manifestly
   **not** invariant under `U ↦ φU`: `c(φU) = |0⟩⟨0|⊗I + |1⟩⟨1|⊗(φU) ≠ φ·cU`.
   The phase `φ` does **not** factor through the controlled construction. The
   paper's `I` vs `−I` example (p. 2) is exactly Sturm's `ctrl(+I) ≠ ctrl(−I)`
   and `ctrl(−I)` "is a real operation." Therefore a kernel that silently
   normalizes into an SU(2) section (dropping the U(1) phase) would compute
   `ctrl` of the **wrong** unitary — differing from the correct controlled
   operation by a `Z` on the control wire, a physically observable error. This
   is the precise mechanism behind CLAUDE.md's "`Ry(2π) = −I` is physics" and
   "NEVER merge +I with −I." The double-cover equality `(q, φ) ~ (−q, φ+π)` is
   the *safe* quotient (it preserves the U(2) element); the U(1) phase is **not**
   safely quotient-able because control observes it.

2. **`ctrl` as the single choke point (PRD §4.2, line 863).** The paper's whole
   decontrolling apparatus is phase bookkeeping — Definition 2.1's `σ` sign,
   Claim 2.3's `Σ_k φ^k |FP(k)⟩` grading, and the `Add(±1)` counter in Eq. (2).
   All the subtlety lives at the moment control is applied. Sturm's response is
   structural: **one** total code path (`ctrl` on phase-carrying process values)
   builds every controlled lowering, so the phase can be tracked exactly in one
   place instead of being re-derived at many call sites. The PRD's list of
   Cirq/Qiskit/pytket controlled-phase bugs is the empirical shadow of this
   paper's theorem: control is exactly where global phase leaks into
   observability, so it is exactly where a distributed representation gets it
   wrong.

3. **The phase quotient is crossed once, at application (PRD §4.3).** The paper
   distinguishes problems on unitary **matrices** (canonical phase — `cU` helps)
   from unitary **channels** (no canonical phase — decontrollable). Sturm carries
   the explicit phase through composition and crosses the U(1) quotient exactly
   once — at Ad's kernel on application, or when `ctrl` consumes it — mirroring
   the paper's line between "phase is physical here" (control / spectrum / LCU)
   and "phase is free here" (channel-level, phase-invariant output).

4. **Bennett / measurement-under-control (PRD §3.4) alignment.** Theorem 1.1's
   converse framing — control's power *is* global phase — reinforces that
   measurement-based uncompute is excluded under a nonzero control stack:
   inside a `when` body the phase must remain coherent, exactly the regime where
   `cU` (and its phase) is doing real work.

**Skeptical scope note (citation check — PASS with nuance).** The PRD's citation
is **accurate**: PRD-v2 §4.2 cites this as "the formal statement of why control
makes global phase physical," and that is precisely Theorem 1.1's content (via
the `I`-vs-`−I` example and the general unitary-matrix vs unitary-channel
principle). This is **not** an inverted citation (contrast the CSW 2210.08468
r6 finding). The only nuance a future agent should keep straight: the paper's
*thrust* is a **negative** result (control does **not** help for phase-invariant
problems, and can be mechanically removed). Sturm uses the **contrapositive** —
"control is the one place where global phase is observable, therefore the kernel
must preserve phase exactly and centralize `ctrl`." The paper grounds the *why*
of the U2 design; it is not an implementation reference and never discusses the
quaternion+phase representation itself. Do not cite it for U2 arithmetic,
double-cover mechanics, or the Ad-kernel phase-crossing — those need
Nielsen–Chuang §4.3 / the quaternion sources, not this paper.
