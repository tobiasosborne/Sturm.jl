# Sturm-PRD-v2 — Design Review, Round 6

**Status: REVIEW INPUT for the next PRD revision.** Produced 2026-07-10
against `Sturm-PRD-v2.md` @ `8226855`. Method: first-hand consequence
analysis of every design choice (main thread), plus four research
subagents (citation verification, prior-art/novelty, independent physics
audit, Julia-idiom/ecosystem), plus **parser ground truth on Julia 1.12.5**
— every surface form in the PRD was fed to `Meta.parse`/`Meta.lower`.
Findings are classified **B** (blocking: the PRD as written cannot be
implemented), **M** (major: underspecified in a way that will bite during
implementation), **S** (secondary: polish, precision, additions).

**Overall verdict up front.** The architecture survives review intact.
The three-layer design, the process-value kernel with `ctrl` as sole
choke point, `dual` as Pontryagin view, consuming casts, and
scope-as-Stinespring are mutually consistent and each earned its place;
nothing below touches the foundations — the independent physics audit
verified every derivation-level claim in the document (teleport, DJ,
universality, the kernel laws, the scope mechanics). But three surface
findings are severe: the PRD's two most-photographed lines of code are
not valid Julia (B1); the Draper row of the view table assigns the
wrong operation — under the PRD's own lowering rule it denotes
modulation, not addition (B2); and the arithmetic surface rests on a
semantic decision the PRD has not noticed it needs to make (B3). One
citation is inverted (§5.2). All are fixable, and B2's fix makes the
design *more* uniform, not less.

---

## 1. Blocking findings

### B1. `dual(x) += a` and `dual(q) ⊻= r` are not valid Julia

**Ground truth (Julia 1.12.5):**

```
dual(x) += a   →  ERROR: syntax: invalid assignment location "dual(x)"
dual(q) ⊻= r   →  ERROR: syntax: invalid assignment location "dual(q)"
```

Julia's op-assignment is pure syntax: `lhs op= rhs` lowers to
`lhs = lhs op rhs`, and the LHS must be an *assignable location* — a
variable, a field (`a.b`, lowers to `setproperty!`), or an index
(`a[i]`, lowers to `setindex!`). A function call is none of these.
There is no `setcall!` protocol and no hook; this cannot be overloaded
from a package — and it is not an oversight but a defended language
invariant: `f(x) = v` already *means* method definition, the
restriction is enforced at nine separate sites in `julia-syntax.scm`,
and the core team declined to reopen it across fifteen years
(julialang/julia#227, 2011; #249; #3217 — see also B3, which quotes
*why* they declined). Worse, the plain-assignment cousin is a trap that
*parses*: `dual(x) = y` inside a function body is a **local method
definition** that shadows `dual` for the *entire enclosing function
body* (Julia hoists local bindings), so even *earlier* lines calling
`dual` in the same function die with
`UndefVarError: 'dual' not defined in local scope`. Verified live.

**Blast radius.** §3.3 semantics table (CZ and Draper rows, lines
202/204), the Pontryagin corollary paragraph (220–222), §3.4 quantum-
addend paragraph (298: `dual(y) += x`), §3.7 universality text (368),
§7.2 (755) and §7.3 (761) — two of the four normative worked examples —
the D5 summary (922), and CLAUDE.md rule 11 (118–119). Five refinement
rounds, including a dedicated Julia-idiom round, did not catch this
because the examples lived in prose. (See the process recommendation,
§7.)

**What survives untouched.** The *semantics* of both table rows — the
operations exist, the Pontryagin corollaries (Draper = translation ↔
modulation; CZ symmetry = symmetry of the pairing) are unaffected; the
D9 ruling `b ⊻= oracle(f, x)` parses fine (variable LHS); `Bool(dual(q))`,
`not!(dual(q))`, `Int(dual(x))`, `when(dual(q))` all parse fine. Only
the two *op-assign-through-a-call* spellings are unwritable.

**Options considered.**

| # | Spelling | Parses? | Verdict |
|---|---|---|---|
| 1 | `x̂ = dual(x); x̂ += a` (bind the view, then var-LHS op-assign) | ✓ (verified, incl. mutate-and-return-self mechanics) | **Recommended** |
| 2 | `when(r) do not!(dual(q)) end` for CZ | ✓ (existing vocabulary) | **Recommended** as the compositional form |
| 3 | `q.dual ⊻= r` (property sugar → `setproperty!`) | ✓ | Rejected (close call): DataFrames-scale precedent exists for zero-copy property views, and `dual` is cheap/total/involutive — but it resurrects the property-as-operation idiom §1.2.3 just executed, and Julia's view idiom is functions (`transpose`, `adjoint`) |
| 4 | `q[dual] ⊻= r` (selector indexing → `setindex!`) | ✓ | **Runner-up.** Strongest *mechanical* precedent (the idiom agent's pick): `Base.Colon` is exactly a singleton selector-token in `[]`, and it reuses the same `getindex`/`setindex!` machinery D2 already commits to for `x[i]` — and it keeps one-line symmetry (`q[dual] ⊻= r ≡ r[dual] ⊻= q`). Held back because `[]` then means both *part-selection* (`x[3]`) and *chart-reinterpretation* (`x[dual]`) on the same type, and Julia spells reinterpretation as a function (`transpose(A)`, not `A[transpose]`); also needs an `x[dual][i]` twin of D2's define-and-throw |
| 5 | `dual(x) .+= a` (broadcast-assign) | ✓ | Rejected: broadcast means *elementwise* in Julia; mod-2^W translation is not elementwise; semantically dishonest (and per-wire connotation is exactly D2's ℤ₂^W-vs-ℤ_{2^W} confusion, weaponized) |
| 6 | `@q dual(x) += a` macro layer | ✓ | Rejected: the thesis is that the surface is plain Julia; one rewriting macro concedes it |
| 7 | `xor!(dual(q), r)` / `add!(dual(x), a)` bang verbs | ✓ | Keep as the *named methods underneath* option 1; not the flagship spelling |
| 8 | bare `dual(q) ⊻ r` statement (xor already mutates its first argument per §3.4's registered exception) | ✓ | Rejected as flagship: an operator expression-statement with discarded value reads as dead code to every human and linter |

**Recommendation (proposed ruling for a new D11).** Note the stakes
drop after B2: the Draper row needed no one-liner anyway (addition's
spelling is `add!`/`+`; the view op-assign turns out to be modulation),
so D11 is really deciding the CZ/modulation aesthetics. Between the
view-bind idiom (below) and the `q[dual]` selector (option 4), the
recommendation is view-bind — reinterpretation-is-a-function is the
deeper Julia idiom — but both are defensible and this is a genuine
taste call for the D11 ruling. Views are first-class borrowable values
(§3.9 already says so); *binding* one is the idiom for working in a
picture:

```julia
q̂ = dual(q)
q̂ ⊻= r             # CZ; the law q̂ ⊻= r ≡ r̂ ⊻= q is §3.3's pairing symmetry

x̂ = dual(x)
x̂ += a             # modulation — see B2: this is the phase program,
x̂ += b             # NOT Draper addition; batching visible either way
```

Mechanics: `+(v::DualView, a)` mutates the viewed register in place
(the operation is bijective — physical) and returns the *same view*,
so Julia's rebind `x̂ = x̂ + a` is a no-op on the binding — exactly the
§3.4 registration that already makes `a ⊻= b` physical, extended from
`xor`-on-registers to the *translation family on views* (`+=`, `-=`,
`⊻=`). Verified mechanically (mutate-and-return-self through a view
struct behaves as required). `when(r) do not!(dual(q)) end` remains the
zero-new-mechanism compositional spelling of CZ.

One principled line makes this coherent rather than ad hoc — add it to
§3.3: **registers are numbers; views are addressing modes.** Views do
NOT ride P9: no ring operations (`*`, `^`, `&`) exist on views, so
generic numeric code hitting a view MethodErrors honestly (same wall as
`g(x::Int)` in the P9 section), and the mutate-in-place convention on
views never leaks into generic value code. The two-line spelling is
also *better pedagogy* than the dead one-liner: it makes "enter the
picture once, do several things there" visible, which is exactly the
fusion structure the kernel wants anyway (S3).

Consequential edits: §3.3 table rows 3–4; §3.4 ¶2; §3.7 CZ mention;
§7.2; §7.3; D5 bullet; D9 cross-reference; CLAUDE.md rule 11. The CZ
"symmetric, and the notation shows it" claim softens to "symmetric by
theorem (required test); the paired spellings `q̂ ⊻= r` / `r̂ ⊻= q` are
both writable." Add the `dual(x) = y` shadowing trap to the `dual`
docstring (it cannot be caught by the library; Julia's own error message
is decent, but the docstring should name it).

### B2. The Draper row assigns the wrong operation to the view — under the PRD's own lowering rule, `dual(x) += a` is modulation, not addition

Apply §3.3's normative lowering ("unitaries lower as
Ad_{V†} ∘ op ∘ Ad_V") to the Draper row. Adding `a` *to the dual
coordinate* lowers to F† ∘ T_a ∘ F where T_a is translation
|x⟩ ↦ |x+a⟩. Compute it (one line, the Fourier intertwining relation
the PRD itself cites): **a translation conjugated by the Fourier
transform is a modulation** — F† T_a F = M_∓a with
M_b : |x⟩ ↦ ω^{bx}|x⟩. Diagonal phases. `Int(x)` unchanged. So the
table row "`dual(x::QInt) += a` = Draper addition" is **backwards**:
the operation that spelling denotes (were it writable, B1) kicks
phases; it does not add. There is no direction convention that saves
it — F T_a F† is also a modulation; conjugated translation is
modulation, period. That *is* the intertwining theorem, pointed the
right way.

Note the internal evidence that the rest of the table is right and
only this row broke the rule: for `QBool`, `not!(q)` is T₁ on ℤ₂
(translation) and `not!(dual(q))` is M₁ = Z (modulation) — the view
*swaps translation and modulation*, exactly as Pontryagin demands. The
Draper row is the one row that tried to make the view *preserve*
translation, because it was reverse-engineered from the v0.1 function
name (`add_qft!`) rather than derived from the view semantics.

**The correction strengthens the design.** The honest v2 story:

- **Addition's surface spelling is addition**: in-place translation is
  `add!(x, a)` (bang verb; and see B3 — the value-world `s = x + a`
  also exists). Whether the *kernel lowers* T_a through the Fourier
  picture (Draper: F† ∘ phases ∘ F) or as a ripple adder is a
  lowering/context choice — the 100 lines of `add_qft!` still die,
  they just die *in the kernel*, which is where "no gates in surface
  code" wanted them all along. §7.2's moral improves from "Draper
  addition is addition" to **"addition is addition — Draper is how the
  kernel does it"**.
- **The dual-view op-assign gets its true meaning**: `x̂ += a` is the
  modulation program — the phase-kick primitive that phase estimation,
  Draper's own inner loop, and the quantum-addend cross-phase are made
  of. §3.4's quantum-addend row corrects the same way: `ŷ += x` is
  *controlled* modulation ω^{xy} (the QFT-multiply kernel), while
  quantum-addend *addition* is `add!(y, x)` (in-place, bijective).
- **Construct #3 generalizes into one theorem.** `not!` is translation
  by 1 on ℤ₂; `add!` is translation on ℤ_{2^W}; `⊻=` is translation in
  (ℤ₂)^W by a register (and `b ⊻= oracle(f,x)` its Perm form); the
  dual-view versions are the corresponding modulations. Surface
  construct #3 "flips/entanglement" is properly **"G-translations,
  their Ĝ-duals, and their controlled/Perm forms"** — one
  P7-parametric family (the group acting on itself), which is also
  exactly the bijective-in-place "action world" of B3's registry. The
  three findings B1+B2+B3 resolve into *one* coherent surface rule
  instead of three patches.
- **The Pontryagin unit test** (required; pins every sign convention
  at once): `superpose!(x); x̂ = dual(x); x̂ += a; Int(dual(x)) == a` —
  modulation shifts the dual outcome by exactly a (this is phase
  estimation in one line). Fix the F-vs-F† convention in the register
  type so this reads `+a`, once.

Consequential edits: §3.3 table (Draper row → two rows: `add!(x, a)`
translation / `x̂ += a` modulation), §3.3 Pontryagin ¶ (the corollary
sentence currently equates the wrong pair), §3.4 quantum-addend ¶,
§7.2 (rewrite around `add!`), D5 Draper bullet, CLAUDE.md 119.

### B3. The register arithmetic surface rests on an unmade decision — and Julia's `+=` ≡ `+` identity forces it

The PRD registers exactly one mutation exception (§3.4: `Base.xor` on
registers mutates its first argument) and otherwise inherits v0.1
arithmetic (P8/P9 "unchanged", v0.1 §8.4: `s = a + b` allocates a fresh
sum register with both inputs live). It also teaches — §3.4 ("`+=` on a
dual view is honest where `q.θ +=` was not") and §7.2 — that `+=` on
registers/views is a physical in-place operation. These commitments
contradict, and Julia will not let the contradiction float: `x += a`
IS `x = x + a`, always, by syntax. One `+` must serve both.

Work through both branches:

- **If `+` allocates a fresh output** (v0.1 semantics, what P9 generic
  code needs): then `x += a` on a bare register is a *rebind*: the name
  `x` moves to the fresh sum register; the old register becomes an
  unreferenced local, silently traced at region exit (§3.9). If `x` was
  in superposition, the adder entangled old-x with the sum, so the trace
  leaves the surviving sum register **classically mixed — the
  superposition arithmetic is destroyed, silently, by the most innocent
  line in all of programming.** This is the §3.4 generic-f caveat
  hiding under `x += 1`.
- **If `+` mutates its first quantum operand** (extending the xor
  registration): then `s = a + b` aliases (`s === a`, mutated), and
  generic P9 code breaks *wrongly*, not just impurely: any read-reuse
  pattern (`y = x + h; z = x * y`) silently uses a clobbered `x`.
  Non-starter — P9 is a pillar.

There is no third option on bare registers; the resolution is a
**two-world registry** (proposed ruling for a new D12):

| Form | World | Effect |
|---|---|---|
| `s = a + b`, `p = a * b`, generic P9 code | **value** | fresh output register; inputs live (reversible dataflow); garbage discipline via §3.4/oracle |
| `a ⊻= b`, `b ⊻= oracle(f, x)`, `not!(a)` | **action** (registered) | in-place flip/entangle; handle stable |
| `x̂ += a`, `x̂ -= a`, `x̂ ⊻= r` on a **bound view** (B1) | **action** (registered, D11) | in-place translation/modulation through the view |
| `x += a` on a **bare register** | value **rebind** — the lost-binding pattern | legal; old register silently traced at region exit; D10 strict mode flags it (see below) |

Three further consequences the PRD must absorb:

1. **§3.4's caveat paragraph contradicts its own registration two
   paragraphs up.** The caveat says a naive XOR-fold "allocates fresh
   intermediates that are never uncomputed" — that is *value-world*
   xor. Under the registered *action-world* xor, `reduce(⊻, wires)`
   allocates nothing: it accumulates the parity into the first wire,
   corrupting the input register in place. Either failure mode condemns
   hand-written generic `f`, so the conclusion ("use `oracle`") stands,
   but the mechanism description is wrong as written. Fix the paragraph.
2. **P9's generic-path promise must drop "bitwise".** v0.1 PRD P9 lists
   "arithmetic, comparison, bitwise" as the operator table generic code
   rides. With action-world `⊻`, generic bitwise code does not have
   value semantics — `x ⊻ y` mutates `x`. Scope the P9 generic path to
   arithmetic/comparison; route generic bitwise logic through
   `oracle(f, x)`, where Bennett's compute-copy-uncompute gives the
   value semantics *by construction*. This is honest and on-philosophy
   (Bennett-centric).

   The ecosystem research adds teeth to this: Julia's core team spent
   2011–2016 (julialang/julia#249, #3217) rejecting mutating update
   operators for *exactly* this failure mode — Karpinski: "if you write
   `x += y` in some generic code … you expect this to have no effect on
   the caller's value of `x`. Then if you call the code on something
   mutable … you're inadvertently mutating the caller's value";
   Bezanson: "`x += y` would become a bit of a trap … work fine for
   numbers, but if the same code were called on arrays it would mutate
   `x` unexpectedly." No registered package ships a bare mutating
   operator; the ecosystem's answer is `!`/`!!` suffixes or `.op=`
   broadcast. Sturm's §3.4 xor registration is therefore a *known,
   upstream-rejected* pattern adopted deliberately — the registration
   paragraph should cite #249/#3217 and say "we understood why this was
   rejected and here is why quantum registers differ" (no-cloning means
   there IS no value reading a caller could have expected for the
   entangler), rather than reading as a stylistic footnote. And it
   should stay scoped to the translation family — never generalized to
   ring ops, per the analysis above.
3. **D10's strict mode gets a precise job.** The `x += a` rebind trap,
   the §3.4 XOR-fold trap, and D10's "handle survives to teardown ⇒
   probably a lost binding" concern are the *same* defect signature:
   *at region exit, a traced register that is an entangling-op parent of
   a surviving register*. Track one parent edge per fresh-output op and
   the strict-mode detector catches all three with one mechanism —
   flagged, per D10's own framing, as a **classical** programming error
   (lost binding), not quantum nagging. §3.9's silent-trace doctrine is
   untouched: the *default* stays silent; strict mode is opt-in
   diagnostics.

---

## 2. Major findings

### M1. `when`'s operational semantics per context is unspecified — and the homomorphism law is the missing license

§3.5 defines `when(q, body)` as "trace body to a unitary-witnessed value
V; apply ctrl(V)". Taken literally, that mandates tracing machinery
inside EagerContext (symbolic execution of the body against live
handles) — heavyweight, and unnecessary. The §4.2 law
`ctrl(g ∘ h) == ctrl(g) ∘ ctrl(h)` is *exactly* the license to run the
body **streamingly**, applying `ctrl(op)` op-by-op as the body executes
(v0.1's control stack, now justified by a law instead of an accident).
The PRD should say this explicitly, because the two strategies differ in
*enforcement mechanics*, and each context needs its assignment:

- **Eager (streaming):** guardrail 1 becomes a runtime law — any
  cast/`ptrace!`/`cases`/noise attempt while the control stack is
  nonempty is a loud error (this is precisely v0.1 defect §8.1's fix,
  promoted to semantics). Guardrail 2 is a per-op aliasing check
  (views resolve to parent wires — note: guardrail 2 must see through
  `dual`; `when(q) do not!(dual(q)) end` is aliased). Clean-ancilla
  exit (§3.9): assert the ancilla's |1⟩-block norm is 0 before
  dealloc — exact and cheap on a statevector.
- **Tracing (materialize):** body traces to `UnitaryDAG` with witness;
  guardrails checked on the DAG; enables the §4.2 reassociation pass
  and `ctrl`-of-DAG fusion.
- **Required law test:** streaming and materialized execution of the
  same body denote the same channel (Choi-compare on small instances).

Two one-sentence semantic notes belong in §3.5: (i) *classical* side
effects in a `when` body (printing, pushing to a Julia array) are
trace/stream-time effects, not controlled effects — every embedded
circuit DSL shares this wart; name it rather than let users discover
it. (ii) Julia closures capture the body's registers; the body runs
exactly once under either strategy.

Also worth stating (it strengthens the design): under streaming, the
clean-ancilla soundness argument is the standard compute–uncompute
lemma — `alloc` (uncontrolled) → `ctrl(U)` → `dealloc` (uncontrolled)
equals `ctrl(dealloc ∘ U ∘ alloc)` *provided* U returns the ancilla to
|0⟩ in the control=1 branch, while the control=0 branch leaves it |0⟩
trivially. The §3.9 witness is exactly this proviso.

### M2. `U2` equality is double-cover equality — the law tests as written would fail on the flagship identity

U(2) ≅ (SU(2) × U(1))/ℤ₂: the 5-float representation (unit quaternion
q, phase φ) is **two-to-one** — `(q, φ)` and `(−q, φ+π)` are the same
U(2) element. Concretely: H = (q_H, π/2) with q_H the π-rotation about
(x̂+ẑ)/√2; the Hamilton product gives H² = (−1, π) — which is the
*other* representative of the identity `(1, 0)`. So the normative test
"H ∘ H == identity" **fails under naive 5-float equality**, and every
§4.2 law test has the same exposure. `ctrl` is unaffected (it factors
through the U(2) element: e^{i(φ+π)}·(−R) = e^{iφ}·R), which is why the
bug would be invisible until an equality-based pass or law test trips.

Fix: define process-value equality on `U2` as equality mod
(q, φ) ~ (−q, φ+π) — canonicalize (e.g., first nonzero quaternion
component positive, φ folded accordingly), compare both
representatives, or (cheapest to state correctly, per the physics
audit) compare the denoted 2×2 matrices e^{iφ}R(q); and all float laws
use ≈ with stated tolerance (also: `Ry(a) ∘ Ry(b) == Ry(a+b)` is
float-approximate, not exact — the PRD's "exact" claims are about
*group structure* (X, Z, H land on exact elements; no SU(2)-section
residue), not float arithmetic; one sentence distinguishing the two
prevents a naive implementer from asserting `==`). §4.1 should carry
this as a normative numerics note next to the existing rescale policy.

**Critical refinement (physics audit): the quotient must keep
+I ≠ −I.** The equivalence classes are +I = {(1, 0), (−1, π)} and
−I = {(1, π), (−1, 0)} — never merge across them. `Ry(2π) = −I` is
physics (spinor 4π-periodicity), and it is *why `ctrl` works*:
ctrl(−I) = diag(1,1,−1,−1) is a real operation (CZ-grade). A law test
must NOT assert `Ry(2π) == identity` — an implementer "fixing" that
"failure" by quotienting out the global sign would reintroduce the
SU(2)-section disease v2 exists to kill, this time at the equality
predicate.

### M3. Context portability of the surface is undeclared — and §7 never exercises `cases`

§7.1's corrections (`m_value && not!(c)`) branch on a measured Bool with
`&&` — valid under Eager/DM/Hardware, but under TracingContext `Bool(q)`
returns the D3 token, on which `if`/`&&` MethodErrors *by design*. So
the flagship example is Eager-only as written, and no §7 example uses
`cases` — construct #6 of seven has zero worked examples. Neither fact
is a bug, but both must be *stated*, or the first thing a new user
learns is that the normative example doesn't trace.

Recommendations: (i) print the portability matrix — it is exactly one
row: every construct is context-portable except classical branching on
outcomes, where Tracing demands `cases`/`@cases` (D3, by design);
(ii) add the deferred-measurement teleport as §7.1b (it is
context-portable, exercises `when(dual(ψ))` — control conjugated in the
view — and the PRD already owes it as "a free second test"); (iii) add
one `cases`-using example — the natural candidate is the §3.7
magic-state injection ladder (T-gadget with S-correction), which would
also close the current gap that *nothing* in §7 uses a phase literal.

### M4. Bennett strategy selection must be control-aware: measurement-based uncompute cannot go under `when`

The v0.1 Bennett bridge (and D3's QROM discussion) includes
measurement-based uncompute (MBU): measure ancillas, branch classically,
apply a fix-up. MBU's *composite channel* equals the unitary uncompute —
but it is not a process value, and §4.4 makes measurement-under-`ctrl`
unrepresentable. Consequence: `when(c) do b ⊻= oracle(f, x) end` is
sound only if the oracle's lowering avoided MBU. So: **the Bennett cost
model's strategy choice is control-context-dependent** — under a
nonzero control stack (or inside a traced `when` body), MBU-flavored
strategies are excluded; outside, they remain available. This is not a
wart; it is §1.1's theorem walking: two implementations equal *as
channels* are distinguishable *under control* — the PRD should cite its
own no-go here, because it is the cleanest live illustration of why the
channel/process-value stratification exists. One paragraph in §3.4 or
the Bennett bridge section; without it, the first `when`-wrapped QROM
oracle ships a soundness bug.

### M5. DensityMatrixContext should execute channels, not trajectories — this is what makes the Choi test discipline cheap

v0.1's DM context *samples* measurements (trajectory semantics). For
the v2 test discipline — whose centerpiece is Choi-level equality
(rule 12; the wm28 lesson) — that is the wrong default: a Choi test of
teleportation under trajectory semantics needs statistical averaging
over shots. If DM instead applies the full instrument (evolve **all**
branches, weighted — block-diagonal accumulation; `cases` becomes a
weighted sum over branch channels), then the DM context computes the
*exact* channel deterministically, and `Choi(teleport) ≈ Choi(id)` is a
one-run, tolerance-only test. Sampling stays available as an explicit
`sample(ctx)`/shot API. Cost note for the harness: the Choi state of a
W-wire channel needs 2W wires (maximally entangled input), so the
30-qubit Orkan cap tests channels up to 15 wires — ample for law tests.
One implementation subtlety from the physics audit: variable-width
`cases` branches cannot thread one fixed-dimension density matrix —
evolve each branch at its own intermediate dimension, trace its
branch-local ancillas to the common output signature (§3.9 does this
anyway), *then* block-accumulate; the Born weights ride along in the
unnormalized branches, no reweighting. Recommend: one normative
paragraph in the contexts section + a `choi(f, dims)` test utility in
the §3.2/§4.2 law-test spec. (Also from the audit, for the test spec:
the cq∘qc pinching test must probe a *coherent* input — on diagonal
inputs pinching and identity coincide; and channel-level teleport tests
must probe a Z-*sensitive* state (|i⟩ or |+⟩) — the outcome-labeling
bug class turns teleport into a Z-error channel that Z-basis probes
cannot see, which is precisely wm28.)

### M6. §8 is stale post-reboot

§8's preamble says "to be fixed on main regardless of v2's schedule" —
but round 4 gutted main; the eight file:line references now resolve only
on `v0.1-deprecated`. The list's *value* survived the reboot in a
different role: it is the defect ledger that motivates v2 requirements.
Retitle to "v0.1 defect ledger (evidence base; branch
`v0.1-deprecated`)" and convert each entry into the v2 requirement it
implies (§8.1 → M1's runtime guardrail; §8.3 → §3.4's exact-X law;
§8.4 → DSL-level aliasing with register identity; §8.5 → single-sourced
consumed set; §8.8 → the §7.1 Choi test). Each becomes a *named
regression test* v2 must ship — the ledger then does work instead of
pointing at deleted files.

### M7. The D2 ruling needs two additions: Bernstein–Vazirani, and the partially-consumed register

- **BV is the missing worked example for the two-groups theorem.** DJ
  §7.4 is (deliberately) robust to the ℤ_{2^N}-vs-(ℤ₂)^N distinction —
  after kickback the constant case is ±F|0⟩ for *either* F, so
  `Int(dual(x)) == 0` decides it (worth one sentence in §7.4 saying
  *why* it is robust: the k=0 row of the QFT *is* the uniform-average
  row of H^⊗N; DJ interrogates only that component, and the test is
  even F-vs-F†-insensitive for outcome 0 — though not for any other
  outcome). BV is the algorithm that *feels* the difference: the
  post-kickback state is H^⊗N|s⟩, which the ℤ_{2^N} Fourier basis does
  NOT resolve — physics-audit numbers for N=3, s=5: QFT-basis outcomes
  spread as {1: 0.073, 3: 0.427, 5: 0.427, 7: 0.073}, a *tie* between
  3 and 5, while the per-wire duals recover s with probability 1.
  Recovering s requires `[Bool(dual(x[i])) for i in 1:N]`, legal under
  D2's ruling. Add it as §7.5: it is three lines, it exercises `x[i]`,
  `dual`-of-slice, and comprehension-over-measurements, and it turns
  D2's "provably different unitaries" from a warning into a program —
  and it defuses a live copy-paste hazard: users porting the §7.4
  pattern to BV get an algorithm that silently returns the right s
  less than half the time (and ambiguously even then).
- **Consuming a slice leaves the parent partial.** `Bool(dual(x[3]))`
  consumes wire 3. What is `Int(x)` now? Recommend: loud error
  ("register partially consumed: wire 3 of x is dead; measure the
  remaining wires explicitly") — fail-fast, and the single-sourced
  consumed set makes it a set-intersection check. The alternative
  (measure survivors, return a partial integer) is a silent
  reinterpretation of `Int`'s meaning. One sentence in D2.

### M8. Replace `task_local_storage` with `Base.ScopedValues` for `@context`

Verified live: `task_local_storage` does **not** inherit into
`Threads.@spawn`/`@async` children (a bare `current_context()` in a
spawned task errors), while a `ScopedValue` binding **does** inherit
into both, and `with(sv => ctx) do ... end` has exactly the
deterministic-scope-exit shape §3.9 regions want (it expands to a
genuine `try/finally`). ScopedValues is stdlib since Julia 1.11, and
the direction of travel is unambiguous: Julia 1.12's own NEWS migrates
`setprecision` to ScopedValue and tells types to follow; the TLS
usability complaint (julialang/julia#14135, "task_local_storage() is
un-Julian") has sat open since 2015. Caveats from the research:
ScopedValue *access* allocates slightly (irrelevant at `@context`
entry; measure before putting `current_context()` in a hot loop — an
argument for passing the context through kernel-internal call chains
rather than re-reading it per op), and bindings are immutable within a
scope (correct for context propagation; the context object's own
thread safety is a separate, existing question — worth one sentence
stating the v2 assumption, e.g. "one region, one task" until a
concurrency story is designed). Edit CLAUDE.md Julia convention 6 and
the contexts section. This is the rare finding that *deletes* a future
bug class (silently-missing context in spawned tasks) for free.

---

## 3. Secondary findings and polish

- **S1 — CV allocation state.** §3.9 says allocation is "|e_G⟩, the
  basis state of the group identity … the vacuum for CV". For G = ℝ the
  identity's "basis state" |x=0⟩ is non-normalizable and is *not* the
  vacuum. The finite-G phrasing doesn't generalize; say "the register
  type's declared canonical state: |e_G⟩ for finite G, the vacuum for
  CV, the trivial charge for anyons" and drop the implication that the
  vacuum is a group-basis state.
- **S2 — Trace timing is denotationally invisible; say so, and D10
  gets lighter.** Because traces have no backaction, *when* an owned
  local is traced (helper-function exit vs enclosing region exit) is
  unobservable in the denotation — the choice is purely a
  resource/DAG-shape question. Stating this as a one-line meta-theorem
  in §3.9 defuses most of D10's apparent weight (eager helpers
  inheriting the enclosing region is *provably* harmless, not a
  compromise). Corollary worth one more sentence: on Eager, the
  measure-and-discard lowering advances the RNG, so *seeded* tests must
  not assert trace placement — statistics are invariant, streams are
  not.
- **S3 — Name the view-fusion pass.** Lazy views lower per-operation;
  adjacent dual-picture operations produce F† … F pairs that must
  cancel (Tracing: a kernel pass; Eager: a per-wire "current picture"
  tag, flushed on basis-crossing ops — this is v0.1's `add_qft!`
  batching, generalized). Without naming it, `x̂ += a; x̂ += b` costs
  four QFTs instead of two.
- **S4 — `ctrl(Perm) is a Perm`.** A controlled permutation is a
  permutation. State it in §4.1: the Bennett corner is closed under
  `ctrl` — the "best-behaved under control" claim then has its
  one-line proof, and controlled oracles stay in the zero-phase-freedom
  representation by construction.
- **S5 — The two mixed-xor directions differ; say it.** `q ⊻= true`
  flips in place (kernel X); `c = false ⊻ b` promotes the classical
  side to a fresh |0⟩ register and entangles (teleport §7.1 depends on
  this reading). Both are wanted; the asymmetry (mutate-LHS vs
  allocate-fresh) is currently implicit in one comment.
- **S6 — View wrapper identity.** `dual(q)` constructs a fresh wrapper
  each call: `dual(dual(q)) === q` holds (unwrap), but
  `dual(q) === dual(q)` is false. Consumed-set and aliasing bookkeeping
  must key on (parent wire, transform), not wrapper identity —
  `Base.dataids`-style. One sentence in D2's wire-handle design. Caveat
  from the ecosystem research: `dataids`/`mightalias`/`unalias` are
  documented but **not** exported/`public` in Base — D2's existing
  "-style" phrasing is exactly right; build a Sturm-owned hook shaped
  like the protocol, don't call Base's internals.
- **S7 — Anti-control.** `when` has no else/anti-controlled form;
  the idiom is the `not!` sandwich (`not!(q); when(q) do … end;
  not!(q)`) or `cases` after measurement. Either bless the sandwich in
  §3.5's text or note a possible future `when(q; else=…)` — currently
  the PRD is silent and Grover-style zero-reflections will make users
  ask.
- **S8 — Name `conjugated_by` now, and note the Q# precedent.** §4.2's
  combinator ("name open") is Q#'s `within…apply` — the one construct
  from the mainstream languages that matches a v2 kernel law exactly.
  Suggest `within(V) do … end` or `conjugated_by`; either way the
  distillation should cite Q# as precedent (prior-art honesty, and it
  strengthens the "most-repeated idiom must not be hand-rolled" claim).
- **S9 — §7 additions.** (i) The deferred-measurement teleport (M3);
  (ii) magic-state injection ladder with `cases` and the `magic_T()`
  literal (M3) — this also exhibits repeat-until-success/Kleisli
  patterns that v0.1's §8.3 had and v2 lost; (iii) a Shor
  order-finding sketch as the capstone — D5 already ported the pieces
  (Draper, coset); §7 currently shows no composite algorithm.
- **S10 — BennettVM is absent.** The project pairs Sturm with Bennett.jl
  *and* BennettVM.jl (session-91 ran a BennettVM retrospective), but
  PRD-v2 never mentions BennettVM. The PRD needs a short normative
  paragraph on the execution contract: what artifact crosses the
  boundary (Perm values? compiled reversible programs?), who owns
  replay, and whether BennettVM is a context or a lowering target.
  (Needs Tobias's input — flagged, not drafted.)
- **S11 — `oracle(f, x)` result opacity.** §2's layer table bans
  process values from the surface, yet construct #7 returns a `Perm`
  that `⊻=` consumes. Resolve the letter-vs-spirit tension in one
  sentence: `oracle(f, x)` returns an *opaque query object* (typed,
  say, `OracleQuery`); the only surface operation on it is `⊻=`
  application; naming it in a variable is legal but there is nothing
  else to do with it. Also state explicitly that `b ⊻= oracle(f, x)`
  leaves `x` live (the Perm reads it control-like; nothing consumes).
- **S12 — Pin the sign conventions with two tests.** DJ is insensitive
  to the Fourier direction (outcome 0 only); nothing else is. Two
  required tests pin everything §3.3 calls "fixed-once": (i)
  translation sign — `add!(x, 1)` on |0⟩ ⇒ `Int(x) == 1` (not 2^W−1);
  (ii) modulation/character sign — the Pontryagin unit test from B2:
  `superpose!(x); x̂ = dual(x); x̂ += a; Int(dual(x)) == a`.
- **S13 — Exceptions taxonomy.** DomainError (D1), ArgumentError (D2),
  and "loud error" (guardrails) are all specified; consider one line
  declaring the policy: Base exception types with rich messages, no
  custom exception hierarchy (matches the D2 YAGNI ruling).
- **S14 — The inverse slogan.** §2's test ("reads like a circuit
  diagram ⇒ wrong") deserves its converse in print: "if it reads like
  ordinary Julia with a few casts and views, it is probably right."
  Cheap, and it states the actual acceptance bar D5 used.
- **S15 — D10's spelling question has an answer: `region() do … end`.**
  The idiom research settles it: Base's do-block resource family
  (`open`, `cd`, `lock`, `mktempdir`, `withenv`, `ScopedValues.with`)
  uses bare concrete nouns/verbs; "scope" is now *doubly* claimed in
  Julia (lexical scope + `Base.ScopedValues`' "dynamic scope"), so
  `@scope`/`scope()` would collide in readers' heads with the very
  stdlib mechanism M8 adopts; and `region` is already §3.9's own
  vocabulary (used five-plus times). Function-first signature so
  `region() do … end` falls out of do-block sugar.
- **S16 — Julia 1.11/1.12 features to design around from day zero.**
  The `public` keyword is tailor-made for §2's layering: kernel API
  (`U2`, `Perm`, `ctrl`, `view`, named constants) marked `public` (
  documented, reachable as `Sturm.ctrl`, *not* exported into `using
  Sturm`), surface constructs exported — the three-layer table gets
  mechanical enforcement at the namespace level. Also on the radar:
  `Memory` (if any Julia-side buffer ever backs a register type) and
  `FieldError` (clean `getproperty` fallthrough if any property sugar
  is ever adopted).
- **S17 — String-macro literals: note for the future, not for D1.**
  QuantumClifford.jl's `S"XXX ZZI"` proves quantum string-macro
  literals are idiomatic Julia — but for *discrete* vocabularies. D1's
  continuous (p, φ) chart is the `Complex(re, im)` shape and its
  constructor ruling stands; if a compact *multi-qubit named-state*
  literal is ever wanted, the string-macro route is the precedented
  one. One line in D1's file, so the next research round doesn't
  re-open it.

---

## 4. Physics audit

*(Two independent passes: main-thread derivations, and a dedicated
physics subagent instructed to re-derive everything from scratch with
numerical cross-checks (numpy). The two passes agreed on every item.
Bottom line: no derivation-level claim in the PRD is wrong; six
conventions/qualifications must be pinned by tests or text — most are
folded into B3/M2/M5/M7 above.)*

- **§7.1 teleportation: correct — denotes the identity channel**
  (Choi(teleport) = Choi(id) verified numerically on |0⟩, |1⟩, |±⟩,
  |i⟩, T, and random states). Two pins: (i) the X-measurement labeling
  is *forced* to |+⟩ ↦ `false` by the instrument lowering F†P_kF;
  reversing it turns teleport into a **Z-error channel that Z-marginal
  tests cannot see** — the wm28 failure class, reproduced from the
  convention side; hence the channel test must probe |i⟩ or |+⟩.
  (ii) The (1,1) correction branch carries a −1 global phase —
  harmless at channel level, fatal to any statevector-equality test;
  the PRD's Choi-only mandate already covers this, keep it strict.
- **§7.4 DJ: correct, for a reason worth printing.** The outcome-0
  amplitude is the uniform average (1/2^N)Σ(−1)^{f(x)} = ±1 (constant)
  / 0 (balanced), because the k=0 row of the ℤ_{2^N} QFT *is* the
  uniform row of H^⊗N — DJ interrogates only that component. Verified
  N = 1..3. F vs F† does not matter *for outcome 0* (it would for any
  other outcome). The BV contrast is M7.
- **§3.7 universality: the chain checks out**, with one implementer
  caveat. RBB wire gadget verified (|+⟩, CZ, X-measure ⇒ X^m H|ψ⟩);
  {H, X, Z, CNOT} are all *real* matrices, so S genuinely must be
  injected (the complex unit enters only through literals — the
  entailment §3.7 states); S-injection (|i⟩ resource, Z-correction)
  and T-injection (|T⟩ resource, S-correction) verified. Caveat: the
  T-gadget's correction S is a **non-Pauli Clifford**, so Pauli-frame
  tracking alone is insufficient — the correction ladder needs live
  classical feedback (available in the generating set) or a recursive
  S-gadget. One sentence in §3.7's proof-obligation note.
- **§4.2 laws: verified** (reassociation — the "V on target wires
  only" precondition is essential; homomorphism; adjoint-ctrl;
  ctrl distinguishing g from e^{iα}g). Pin in text: ∘ is right-to-left
  matrix composition ("apply right operand first").
- **Boundary algebra: verified.** qc∘cq = id on bits; cq∘qc = Z-basis
  pinching with Choi = |00⟩⟨00| + |11⟩⟨11| (unnormalized convention:
  diag of the identity's Choi) as the test target. Test-design note:
  pinching and identity coincide on diagonal inputs — the required
  test must feed a coherent input (|+⟩).
- **§3.9 trace mechanics: verified.** (a) No-backaction is exactly
  no-signaling (Tr_B[(I⊗Λ)ρ] = Tr_B ρ for any CPTP Λ). (b)
  Measure-and-discard = ptrace exactly, *in distribution over shots*,
  including all correlations with prior/subsequent classical records —
  with the sharp edge that the outcome must be truly discarded: the
  moment it conditions anything, it is `cases`, a different channel.
  (c) Streaming clean-ancilla soundness verified including entangled
  controls: control=0 leaves the ancilla |0⟩ trivially, control=1
  requires U to clean it *for all body inputs* — and an unclean
  ancilla under a superposed control decoheres the control, which is
  exactly why §3.9 makes the unwitnessed case a loud guardrail error
  rather than a quiet trace. The PRD's "trace under ctrl is
  unrepresentable" is the right call and now has its operational
  proof.
- **Draper lowering identity: verified** — F†·diag(ω^{ak})·F = T_{+a}
  (and F·diag·F† = T_{−a}: the sign is load-bearing; pin with the
  `add!(x, 1)` on |0⟩ ⇒ Int(x) == 1 test). This is the identity the
  *kernel* uses to lower `add!`; what the *view spelling* denotes is
  B2.
- **U2 double cover: verified** (H² = (−1_quat, π), the other
  representative of +I; ker of the 2:1 map = {(1,0), (−1,π)}), plus
  the +I ≠ −I refinement now in M2.
- **DM branch semantics: verified** — exact ensemble evolution is
  deterministic and yields the exact Choi in one run; trajectory
  sampling needs O(1/ε²) shots; the variable-width subtlety is in M5.
- **Deferred-measurement teleport: verified** — `when(b){not!(c)}` +
  `when(dual(ψ)){not!(dual(c))}` before the casts denotes the same
  identity channel, and `when(dual(ψ))` lowers to exactly
  |+⟩⟨+|⊗I + |−⟩⟨−|⊗Z — the coherent form of "if m_phase then Z". The
  conjugated-control-wire lowering is doing precisely its job; this
  example belongs in §7 (M3).
- **D6 traps: correctly characterized** (Gauss-sum normalization
  bifurcates by d mod 4; 2⁻¹ mod d exists only for odd d — the
  even/odd-d split in the Weyl–Heisenberg machinery is real and "one
  theorem, at least two code paths" is right).

## 5. Citations and prior art

*(From the citation-verification and prior-art subagents; PRD already
survived one audit round, so these are the residuals. Items P1–P7 from
the prior-art/novelty agent; C-items from the citation agent.)*

### 5.1 Prior art and novelty (two corrections, one defense gap, one de-risk)

- **P1 — Qwerty (§3.3 prior-art ¶): one clause is unsupported.**
  Both Qwerty papers (2404.12603; compiler companion ASDF, arXiv:
  2501.13262) confirm `>>` is a *synthesized* circuit — ASDF names
  "synthesizing circuits from basis translations" as its core problem —
  but **no passage considers and rejects a view reading**; the claim
  "its authors considered and rejected the view reading" must go.
  Replace with the accurate, *stronger* differentiator: Qwerty's `>>`
  maps between *arbitrary* user bases (a strictly more general
  construct, which is *why* it must synthesize); Sturm's `dual` is the
  one canonical character-group dual, and exactly that narrowing is
  what makes a zero-cost involutive view possible. Add ASDF
  (2501.13262) to §9's citation list.
- **P2 — §4.2 must cite "Control as a Constructor" (arXiv:2508.21756).**
  The categorical concept — control as a single constructor ("control
  functors" extending props to controlled props, with a completeness
  payoff on ≤3 qubits) — is 2025 prior art whose title nearly names
  Sturm's §4.2 claim. Reframe Sturm's contribution as the
  *implementation instantiation*: one total code path on phase-fixed
  process values, versus the per-gate `.controlled()`/`.control()`
  architectures whose distributed call sites produced the
  Cirq/Qiskit/pytket bug history. Also note the mainstream is
  converging (Qiskit 2.3's `control(annotated=true)` defers controlled
  construction to the transpiler — partial centralization, still
  per-gate-entry, still not total on phase-carrying values).
- **P3 — §3.9 is under-defended against Silq; add "Why not
  auto-uncompute?".** Silq (PLDI 2020) silently *uncomputes* `qfree`/
  `lifted` temporaries at scope exit (running the classical-reversible
  computation backwards) and **rejects** dropping anything else as a
  type error — so a forgotten Grover-oracle ancilla is *saved* in Silq
  and *silently mixes the survivors* in Sturm. The no-backaction
  argument defends the trace's *silence*, not the decision *not to
  uncompute*; the PRD never says why it accepts that trade. The honest
  paragraph: (i) qfree-scope is narrow — genuinely quantum locals
  (discarded syndromes, environment modes) are *rejected* by Silq and
  correctly traced by Sturm; (ii) auto-uncompute silently ~doubles the
  block's gate cost — Sturm makes the expensive thing (uncompute)
  explicit and the free thing (trace) implicit, Silq the reverse;
  (iii) purity-on-demand is available *by construction* through
  Bennett's `oracle`; (iv) D10's strict mode is the opt-in safety net
  (and B3's detector gives it teeth). Cite Qurts (arXiv:2411.10835,
  affine types + lifetimes for uncomputation) as the newest point in
  this design space.
- **P4 — the scope-discipline landscape table (add to §3.9).** Survey
  result: QWIRE/Proto-Quipper give *explicit* `discard` exactly the
  partial-trace denotation (prior art for the semantics); Quipper has
  assertive termination; Q# (current QDK) **runtime-enforces**
  reset-to-|0⟩ at `use`-block release; ProjectQ's simulator *raises* on
  deallocating a superposed qubit; Guppy (arXiv:2510.13082) makes
  implicit discard a *compile error* (owned qubits must be consumed).
  No surveyed language makes the trace automatic + silent + the P1
  denotation at region exit — Sturm's discipline is novel *and
  contrarian* (it inverts the dominant "superposed at scope exit =
  probable bug" stance); the PRD should print the table and own the
  inversion explicitly. **Factual fix:** §3.2's "Q#'s convention-only
  stance" is outdated — current Q# runtime-enforces clean release
  (Q# still has no linear *typing*, so §4.5's characterization
  stands).
- **P5 — consuming-cast spelling: novelty confirmed, keep the hedge.**
  Consuming *semantics* is well-precedented (Twist T-Measure, Guppy
  `@owned` move on measure, Silq/Quipper linear consumption);
  no surveyed system spells measurement as the host's own
  type-constructor cast. OpenQASM 3 is the near-miss that proves the
  gap: it has *both* a classical cast system *and* `measure`, never
  merged. Add Guppy as the closest move-semantics neighbor in §3.2.
- **P6 — quaternion+phase persistent IR: claim survives, scope it.**
  Qiskit fuses 1q runs via `OneQubitEulerDecomposer` (Euler + phase);
  tket's `EulerAngleReduction` fuses to matrix then re-decomposes;
  VOQC/SQIR are matrix-semantics; Fraxis/FQS quaternions parameterize
  ansätze, not IR. Append the surveyed-list parenthetical to §4.1 and
  cite Wharton–Koch (arXiv:1411.4999) as the textbook quaternion↔SU(2)
  source, so the claim reads "novel as an *IR choice*", not "novel
  representation".
- **P7 — D3 is de-risked by a shipped precedent.** qrisp's Jasp is
  *exactly* the leading candidate, working today: measurement under
  tracing returns a dynamic token; plain Python `if` on it is refused;
  branching goes through a dedicated `control()` construct; and — the
  answer to D3's QROM scale worry — an integer outcome flows into
  *traced classical computation* that parameterizes circuit
  construction (dynamic indexing, dynamic loop bounds), compiled once,
  width-scalable, with **no 2^W branch table**. Proto-Quipper-Dyn's
  parameter/state modality is the type-theoretic backing. Recommended
  D3 ruling: `ClassicalBit`/`ClassicalInt` tokens; `if token` errors
  descriptively toward `cases`; **do not scale `cases` to 2^W** —
  bless "measure → classical computation → classically-parameterized
  circuit" as ordinary code (the PRD's own second option), citing Jasp
  as the shipped precedent.

### 5.2 Citation verification

Thirteen load-bearing citations re-verified *as used* against primary
sources. Twelve hold — including the precise theorem/definition
numbering for Yuan–Villanyi–Carbin (Thm 4.4 / Def 4.7 / Thms 4.8–4.9,
OOPSLA1 2024), the Bădescu–Panangaden Condition I/III ↔ guardrail 2/1
mapping, Ying–Yu–Feng Def 2.1(4), Tang–Wright Thm 1.1 (exists; states
that circuits using cU can be converted to uncontrolled-U circuits
whose output is averaged over a random global phase — the PRD's
"control makes global phase physical" is the correct contrapositive),
Araújo's 1⊕U constructive half, the VOQC §3.3 quote (verbatim: "we were
surprised to find that we had tremendous difficulty proving that even
simple transformations were correct"), and RBB-vs-ZLC. One is wrong,
one needs a nuance fix, and four carry small nuances:

- **C1 — WRONG (inverted citation): Chen–Stoudenmire–White
  2210.08468.** The paper is titled "Quantum Fourier Transform Has
  **Small** Entanglement" — its thesis is that the apparent maximal
  operator entanglement of the QFT is *entirely a bit-reversal
  artifact*, and the core QFT's Schmidt coefficients decay
  exponentially (constant entanglement). D2 cites it for "the QFT has
  maximal operator entanglement across every register cut" — the
  claim the paper exists to debunk. **D2's conclusion is unaffected**
  (QFT on ℤ_{2^W} ≠ per-wire Fourier on (ℤ₂)^W is true and elementary —
  cross-wire controlled phases; and M7's BV distribution makes it
  operational), but the sentence must be rewritten: either drop the
  entanglement claim, or cite the "early results" CSW themselves
  attribute maximality to (Tyson 2003; Nielsen et al. 2003), or cite
  CSW *correctly* — "not a tensor product across any cut, though its
  core operator entanglement is in fact small (CSW 2210.08468)".
  Ironically the *correct* CSW reading is friendlier to Sturm: small
  operator entanglement is why QFT-based lowerings simulate/compress
  well.
- **C2 — nuance: Gavorová et al. 2011.10031.** The general obstruction
  is their homogeneous-function **Lemma 1** (continuous m-homogeneous
  U(d) → S¹ exists only if d | m), proved by an elementary
  homotopy/winding argument. Borsuk–Ulam supplies only the
  even-dimension *intuition* / an alternative even-d proof. §1.1's
  "Borsuk–Ulam via their 'Topological Lemma'" overstates; the
  "survives approximation, postselection, relaxed causal order — all
  three literal" clause is verbatim-confirmed. Reword the mechanism,
  keep the strength claim.
- **C3 — minor:** Bravyi–Kitaev 0403025's headline is *distillation*;
  the injection circuit is Gottesman–Chuang/ZLC gate teleportation.
  The PRD cites the ensemble together, which is defensible; the
  distillation-vs-injection roles could be one clause sharper.
- **C4 — minor:** Stuelpnagel 1964 treats SO(3); the SU(2) extension
  is standard but not literally in the paper. "Cf." it.
- **C5 — minor (SDK archaeology):** all bug reports are real, verbatim
  confirmed (Cirq #4275's body is a textbook statement of the exact
  bug class). Two tightenings: pytket's QControlBox fix *landed in*
  0.17.0, so buggy is **< 0.17**, not "≤ 0.17"; and Qiskit #7167 is a
  general global-phase-tracking bug — the cleaner
  controlled-decomposition exhibit is **#4949** (diagonal gate's
  global phase wrong *when used in a controlling circuit*). Swap or
  add.
- **C6 — locator spot-check:** Bădescu–Panangaden's Conditions are
  invoked across the paper, not verifiably all in "their §1"; keep
  the mapping (verified correct), soften the section pointer when the
  distillation is written.

## 6. Proposed new decision points (and two existing ones that closed)

- **D11 — spelling of view mutation (from B1).** Proposed ruling in B1:
  bind-the-view idiom (runner-up: `q[dual]` selector); translation-
  family ops on views are registered in-place actions; views are not
  numeric. Stakes reduced by B2 to CZ/modulation aesthetics.
- **D12 — the arithmetic registry (from B2 + B3).** Proposed ruling:
  value world vs action world; construct #3 generalized to the
  G-translation/Ĝ-modulation family; P9 generic path scoped to
  arithmetic/comparison; D10 strict mode gets the
  garbage-decoheres-survivor detector; the §3.4 registration cites
  julialang#249/#3217 as informed deviation.
- **D13 — `when` operational semantics (from M1).** Streaming licensed
  by the homomorphism law; per-context enforcement table; the
  streaming≡materialized law test.
- **D3 — can now be ruled** (per §5.1 P7): adopt the Jasp-shaped
  design — `ClassicalBit`/`ClassicalInt` tokens under Tracing,
  `if token` errors descriptively toward `cases`, and *bless*
  measure → traced classical computation → classically-parameterized
  circuit instead of scaling `cases` to 2^W tables. Shipped precedent
  (qrisp/Jasp) + type-theoretic backing (Proto-Quipper-Dyn).
- **D10 — can now be ruled** (per S15 + S2 + B3): spelling
  `region() do … end`; eager helpers inheriting the enclosing region
  is provably harmless (trace timing is denotationally invisible);
  strict mode = the lost-binding detector, framed as a classical
  error.

## 7. Process recommendation: the PRD's examples must compile

B1 survived five review rounds because normative code lived in prose.
The fix is mechanical: **every fenced Julia block in the PRD marked
normative becomes a doctest** — `test/test_prd_examples.jl` at minimum
`Meta.parse`s every block (catching B1-class rot forever), and §7
examples execute under EagerContext once milestone 0 lands. The PRD is
the constitution; constitutions get continuous integration too.
