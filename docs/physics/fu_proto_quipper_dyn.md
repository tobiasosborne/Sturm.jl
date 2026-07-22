# Proto-Quipper with Dynamic Lifting

**Citation**: P. Fu, K. Kishida, N. J. Ross, P. Selinger, "Proto-Quipper
with dynamic lifting", *Proc. ACM Program. Lang.* **7**(POPL), Article 33
(2023), pp. 309–334. DOI: 10.1145/3571204. arXiv:2204.13041. (Fu &
Kishida: Dalhousie University; Ross & Selinger: Dalhousie University. The
POPL 2023 line of the Proto-Quipper family.)

**Local PDF**: `docs/physics/fu_2204.13041.pdf` (40 pp., the arXiv v-final
preprint; **PDF-verified against every locator below** — page numbers below
are the PDF's own printed page numbers, which match the arXiv pagination).

**Status in pipeline**: ground-truth source for the **§3.6 token
discipline** (milestone M8 part 7). Sturm's classical-outcome tokens
(`ClassicalBit`, `ClassicalWord{W}`) are exactly Proto-Quipper
**parameters** — circuit-generation-time values, duplicable and
discardable — as opposed to **states** (the live quantum/classical wires).
This paper is the formal source for that parameter-vs-state boundary, for
*why* a measurement outcome is a *state* that only a monadic "lifting"
operation may promote to a parameter, and for *why the type system forbids
boxing a computation that has lifted* — the discipline PRD-v2 §3.6 mirrors
with its T1–T4 restricted SSA and the D3 ruling (tokens under `Tracing`).
It does **not** ground the kernel or the channel algebra; it grounds the
classical-control token layer only.

---

## What this paper does (one line)

It extends Proto-Quipper-M (a functional quantum *circuit-description*
language with a sound categorical semantics) with **dynamic lifting**: the
operation that takes a measurement outcome — a `Bit` *state*, known only at
circuit-execution time — and lifts it to a `Bool` *parameter*, known at
circuit-generation time, so it can steer the generation of the next part of
the circuit (Abstract, p. 1). The type system tracks every use of lifting
with a **modality** `α ∈ {0,1}`, and the semantics models it as a **monad
`T`** (the "dynamic lifting monad") on a single category `A`, with lifting
living in the **Kleisli category `Kl_T(A)`**. Type system and operational
semantics are proved sound against the categorical model.

---

## The parameter / state distinction (the load-bearing dichotomy)

**Abstract (p. 1), verbatim.** "Proto-Quipper has two separate runtimes:
circuit generation time and circuit execution time. Values that are known
at circuit generation time are called **parameters**, and values that are
known at circuit execution time are called **states**." (emphasis on the
two named tiers.)

**§1.2 (p. 2), the two runtimes and their reflection in the type system.**

- A **parameter** "is a value that is known at circuit generation time,
  such as a boolean value for an if-then-else expression." (p. 2)
- A **state** "is a value that is only known at circuit execution time,
  such as the actual state of a qubit or classical bit in a circuit." (p. 2)
- The linearity split is the type-level content of the dichotomy (p. 2):
  "there is a subset of **parameter types**, such as `Nat` and `Bool`,
  whose elements can be **duplicated and discarded**. There is also a
  subset of **state types**, such as `Qubit` and `Bit`, which are **linear**
  so that their elements cannot in general be duplicated or discarded."
- Parameter and state types share **one universe** (p. 2): "One of the
  fundamental design decisions of Proto-Quipper is that parameter types and
  state types belong to the same universe of types, so that one can form
  compound types that are part parameter and part state." Example: the
  length of a list of qubits is a *parameter*, its qubits are *states*
  (p. 2). This is why Sturm can have `ClassicalWord{W}` (a parameter) sit
  in the same type system as live registers (states).

**The asymmetry of the two directions (§1.2, p. 2).** Parameter → state is
easy: "we can initialize a qubit based on a boolean parameter, simply by
inserting a gate at circuit generation time to initialize the qubit in one
state or another." State → parameter is the hard direction: "the opposite
direction is more complicated. Usually, circuit execution happens after
circuit generation, and in this case, it is clear that a state cannot be
converted to a parameter." Dynamic lifting is precisely the *guarded*
crossing of this hard direction.

**Dynamic lifting ≠ measurement (§1.2, p. 2), verbatim.** "The concept of
dynamic lifting is different from measurement, and the two should not be
confused. **Measurement is merely a gate in a circuit, turning a quantum
bit (a state) into a classical bit (also a state). Dynamic lifting is an
operation of the programming language, turning a classical bit (a state)
into a boolean (a parameter).**" So `Meas : Qubit → Bit` stays inside the
object language (state→state); `dynlift : Bit → Bool` is the meta-language
operation that crosses tiers.

**Why lifting is expensive (§1.2, p. 2).** "it requires **control to pass
from circuit evaluation time back to circuit generation** [time]" — the two
runtimes must interleave, which is exactly why it cannot be a free coercion.

---

## The dynamic-lifting typing: the `Bool`-typed lift, monadic / Kleisli

**The two categories (§1.3, p. 3).** The semantics starts from two small
symmetric monoidal categories with the **same objects**: `M`, whose
morphisms are **syntactic** circuits ("typically a category that is freely
generated (say by a collection of gates)"), and `Q`, whose morphisms are
**physical operations** "which can be performed on a quantum computer",
linked by a symmetric monoidal **interpretation functor `J : M → Q`**
(p. 3). `M` is the *boxable* world; `Q` is the *executable* world.

**The dynamic lifting monad (§1.3, p. 3), verbatim.** "The nondeterministic
nature of the dynamic lifting suggests that it should be modeled as a
**monadic operation**. We therefore conceptualize the types of
Proto-Quipper-Dyn as the objects of a single category `A`, with a monad
`T : A → A`, called the **dynamic lifting monad**. This will be done in
such a way that `M` is fully embedded in `A`, and `Q` is fully embedded in
the **Kleisli category `Kl_T(A)`** …" — with the given `J : M → Q` and the
canonical `E : A → Kl_T(A)` making the square `M→A`, `Q→Kl_T(A)` commute
(p. 3 diagram).

**The lift itself (§1.3, p. 3), verbatim.** "We then model dynamic lifting
as a map **`dynlift : Bit → T Bool ∈ Kl_T(A)`**" with the unit-of-the-monad
triangle (`init`, `η`, `dynlift`) commuting (p. 3). "Note that dynamic
lifting is a morphism of the Kleisli category; this makes sense because it
is essentially **a side-effecting read operation**. More generally, any
computation that potentially uses dynamic lifting will have type
**`A → T B`**." — i.e. lifted values are *monadic values in the Kleisli
category*, sequenced by Kleisli composition, never plain values.

**The modality (§1.3–§1.4, pp. 3–4).** Rather than write `T` everywhere,
the type system annotates each judgment with a modality: `Γ ⊢α M : A`,
`α ∈ {0,1}` (p. 3). Reading (p. 4, verbatim): "**When `α = 0`**, it means
that the term `M` represents a morphism `⟦Γ⟧ → T⟦A⟧` in the Kleisli
category `Kl_T(A)`. **When `α = 1`**, it means that the term `M` represents
a morphism `⟦Γ⟧ → ⟦A⟧` in `A`." The modality also decorates function and
exponential types: `A ⊸α B` and `!α A` (§3, p. 10). It "can be thought of
as denoting **"boxability"**": `Qubit ⊸1 Qubit` "represents a circuit that
can be boxed or executed", whereas `Qubit ⊸0 Qubit` "represents a quantum
operation that **can only be executed but not boxed**." (§1.3, p. 3.)

**The typing rule for the lift (§1.4, p. 4), verbatim** (with
`Meas : Qubit → Bit` the measurement gate):

```
        ℓ : Qubit ⊢1 Meas(ℓ) : Bit
    ───────────────────────────────────
    ℓ : Qubit ⊢0 dynlift(Meas(ℓ)) : Bool
```

"Note that the `dynlift` operation **sets the modality of the typing
judgment to 0**, and as a result, we have a map `Qubit → T Bool` in the
Kleisli category." (p. 4). Below the state (`Bit`) sits at modality 1
(boxable); the lifted parameter (`Bool`) is produced only at modality 0
(non-boxable).

---

## Why lifted values cannot flow freely: what the type system forbids, and how

The paper's barrier is **not** a ban on branching — dynamic lifting exists
precisely so "measurement results [can be brought] into the control flow of
the language" (§1.5 related work, p. 5). The barrier is **type-level and
two-fold**, and it is exactly the discipline Sturm imports:

1. **A `Bit` state may not be used where a `Bool` parameter is required.**
   Host control flow (if-then-else) is a *meta-language* construct that
   consumes a **parameter** `Bool` (§1.2, p. 2: "a boolean value for an
   if-then-else expression"). A measurement outcome is a **state** `Bit`.
   These are **different types** — `Bit` is linear and lives in the object
   language, `Bool` is duplicable and lives in the meta-language. The only
   bridge is the explicit `dynlift` cast; there is no silent coercion (the
   "state cannot be converted to a parameter" default of §1.2, p. 2). The
   two worlds are kept sharply apart: "classical expressions and control
   flow for the meta-language, and gates and measurements for the object
   language … The 'meta-language' of Proto-Quipper terms has almost nothing
   in common with the 'object language' of circuits." (§1.5, p. 5–6).

2. **Having lifted, you may no longer box.** The modality makes the cost
   type-visible. Verbatim (§1.4, p. 4): "The use of modalities in our type
   system ensures that the term `Meas(ℓ)` **can be turned into a boxed
   circuit**, whereas it will be a **compile time typing error to try to
   box the term `dynlift(Meas(ℓ))`**." A `dynlift` term is modality-0
   (`⊸0`), and boxing requires modality 1. So a computation that has
   consulted a measurement outcome loses its status as a reusable,
   inspectable circuit value.

**Why the boxing ban matters — the single-branch guarantee (§1.5, p. 5),
verbatim.** "in our setting, dynamic lifting ensures that **boxed circuits
are data structures that contain only one branch** (namely, the one
corresponding to the actual measurement result when the circuit is run),
whereas in Lee et al.'s setting, either all branches are evaluated, or the
circuit is a thunk." Contrast Lee et al. [LPVX21], whose measurement-
branching channels "must either be implemented as thunks, or as data
structures that are **exponentially large**" — "if the current gate is a
measurement, the list has two tails, one for each possible measurement
outcome" (p. 5). Proto-Quipper's modality is exactly what buys the
single-branch representation and avoids the exponential blow-up: a boxed
circuit is a *definite* object because it has *not* lifted. **This is the
`2^W`-table avoidance argument, at the type level.**

---

## The categorical semantics headline (distillation altitude)

The model is built in **enriched category theory** (§2, pp. 6–9). At
headline altitude, the three moving parts are:

- **Two categories, one interpretation functor.** `M` (freely-generated
  syntactic circuits, the *boxable* world) and `Q` (physical operations,
  the *executable* world), same objects, `J : M → Q` symmetric monoidal
  (§1.3, p. 3).
- **One ambient category `A` with a lifting monad `T`.** `M` fully embeds
  in `A`; `Q` fully embeds in the Kleisli category `Kl_T(A)`; the embeddings
  commute with `J` and the canonical `E : A → Kl_T(A)` (§1.3, p. 3 diagram).
  `A` is required to be a **linear-non-linear (LNL) programming-language
  model**: it has coproducts, is symmetric monoidal closed, and carries an
  LNL adjunction whose comonad `p` picks out the **parameter objects**
  "`pX ∈ A`, since they can be duplicated and discarded" (Def. 2.3, §2.1,
  pp. 7–8; Def. 2.2 symmetric-monoidal enrichment, p. 7). The parameter/
  state split of §1.2 is thus the image of the LNL adjunction — the same
  categorical structure Benton's LNL calculus gives to `!`.
- **Lifting is a Kleisli morphism.** `dynlift : Bit → T Bool` lives in
  `Kl_T(A)`; the monad `T` carries the non-determinism of the measurement
  read; soundness (Thm in §4, pp. 15–19) shows the operational semantics
  (circuit-generation-time and circuit-execution-time reduction, §4.1/§4.2,
  pp. 15–17) agrees with this denotation. The upshot at distillation
  altitude: **parameters are the non-linear / duplicable world, states are
  the linear world, and the *only* passage from state to parameter is a
  monadic (Kleisli) step that the modality makes visible and boxing-hostile.**

---

## What Sturm takes from this (PRD-v2 §3.6 / D3)

- **`ClassicalBit` / `ClassicalWord{W}` are Proto-Quipper *parameters*.**
  §3.6's tokens are circuit-generation-time values — duplicable, discardable
  `Bool`/`Nat`-class parameters (this paper, §1.2, p. 2) — **not** live
  states. That is what licenses them to steer subsequent generation
  (loop bounds, indices, `cases` selectors) while the register wires they
  came from are consumed. The parameter/state universe-sharing (§1.2, p. 2)
  is why a Sturm program can carry both a `ClassicalWord{W}` token and a
  `QInt{W}` register in one type system.

- **The `qc` cast is Proto-Quipper's `Meas`, not its `dynlift`.** Sturm's
  measurement cast (`Bool(q)`, `Int(x)`) turns a state into a classical
  outcome — Proto-Quipper's object-language `Meas : Qubit → Bit`, a gate
  (state→state), p. 2. Whether that outcome may then *inform generation* is
  the separate, disciplined step — Proto-Quipper's `dynlift`. Sturm's D3
  ruling that tokens live "under `Tracing`" is the analogue of confining the
  lift to a distinguished mode: the promotion is not a silent coercion.

- **T1–T4 restricted SSA = the monadic / boxability discipline.** Fu et
  al.'s two guarantees — (i) a lift is a *monadic* step in `Kl_T(A)`,
  sequenced explicitly, never a plain value (§1.3, p. 3); (ii) once you have
  lifted you may not box (§1.4, p. 4) — are the formal shadow of §3.6's
  restricted-SSA token rules: tokens flow forward in single-assignment form
  and gate later generation, but they are not free-floating classical values
  that dissolve the region/boxing structure. The single-branch guarantee
  (§1.5, p. 5) is precisely why §3.6 avoids materialising a `2^W` branch
  table: like a Proto-Quipper boxed circuit, a Sturm traced region carries
  the *one* realised branch, not all `2^W`.

- **`cases` / `@cases` is host-side branching on *parameters*, and that is
  legitimate.** Branching on a `Bool` parameter in an if-then-else is
  exactly what parameters are *for* (§1.2, p. 2). Sturm's `cases` (surface
  construct 6, D3) is this: it consumes tokens (parameters), not states, so
  it is the sanctioned meta-language control flow — the disciplined image of
  what `dynlift` unlocks, kept inside the token layer.

**Skeptical scope note.** This paper grounds the **classical-control token
layer only** (§3.6, D3). It says nothing about phase, `ctrl`, the U2
representation, or the Bennett bridge — do not cite it there. Its notion of
"circuit" is deliberately abstract (a morphism of a freely-generated
category, §1.3, p. 3), so it is a *design-shape* precedent for the
parameter/state boundary, not an operational specification of Sturm's
`Tracing` context. Where Sturm's tokens differ: Proto-Quipper's `dynlift`
freely admits the lifted `Bool` into arbitrary host control flow (paying
with lost boxability); Sturm's §3.6 goes **further**, restricting tokens to
T1–T4 SSA + `cases` even after promotion — a *stricter* discipline than
Proto-Quipper's, chosen so that the `Tracing` context stays statically
analysable. The shipped-software precedent for that stricter, tracer-based
choice is qrisp/Jasp — see `docs/physics/qrisp_jasp_dynamic_tracing.md`.
