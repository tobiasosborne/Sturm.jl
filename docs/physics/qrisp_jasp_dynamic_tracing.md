# Qrisp / Jasp — Dynamic Tracing for Real-Time Classical Control

**Type of source**: *shipped-software precedent* (not a theorem). This is
the D3 "precedent citation" — the working system that demonstrates the token
discipline PRD-v2 §3.6 adopts. Two sources, both fetched and pinned below:

1. **Paper** (context, not the shipped Jasp feature): R. Seidel, S. Bock,
   R. Zander, M. Petrič, N. Steinmann, N. Tcholtchev, M. Hauswirth, "Qrisp:
   A Framework for Compilable High-Level Programming of Gate-Based Quantum
   Computers", arXiv:2406.14792v1 [quant-ph], 20 Jun 2024. (Fraunhofer FOKUS
   / TU Berlin. The Eclipse-Qrisp framework paper.)
   **Local PDF**: `docs/physics/qrisp_2406.14792.pdf` (PDF-verified; the
   two-column layout makes `pdfinfo` report "1 page" but the file is the
   full ~15-page article. Page pins below are the article's printed page
   numbers.) **Caveat**: this 2024 paper only *foreshadows* Jax integration
   in its §6 Outlook; the shipped **Jasp** module and its dynamic control
   flow are documented in the online docs (source 2), which post-date it.

2. **Docs** (the shipped Jasp behaviour — the load-bearing precedent):
   qrisp.eu online documentation, fetched 2026-07-22:
   - Tutorial "How to think in Jasp" — `qrisp.eu/general/tutorial/Jasp.html`
   - Jasp reference index — `qrisp.eu/reference/Jasp/index.html`
   - Hybrid Control Flow index — `qrisp.eu/reference/Jasp/Control Flow/index.html`
   - `jrange` reference — `qrisp.eu/reference/Jasp/Control Flow/jrange.html`
   - `ClControlEnvironment` reference — `qrisp.eu/reference/Jasp/Control Flow/ClControl.html`

   Docs are versioned software, not a stable PDF; every quoted string below
   is tagged with the page it was fetched from so a future agent can
   re-verify. Claims I could **not** confirm from a fetched source are marked
   **TODO** and stated as such — never from memory.

**Status in pipeline**: the shipped-precedent half of the D3 ruling and
PRD-v2 §3.6's token discipline (milestone M8 part 7). Where Fu et al.
(`docs/physics/fu_proto_quipper_dyn.md`) give the *type-theoretic* account
of parameter-vs-state and the boxing barrier, Qrisp/Jasp gives the
*implemented* account: a measured value is a **dynamic tracer**; ordinary
host control flow on it is not the mechanism; branching and looping go
through **dedicated constructs** (`control(...)`, `jrange`); and a dynamic
loop bound **compiles once**, with no `2^W` unrolling. That is the concrete
engineering shape §3.6's `Tracing`-context tokens (T1–T4 restricted SSA)
follow.

---

## What Jasp is (one line)

Jasp is the Qrisp submodule that makes Qrisp code **Jax-traceable**, so a
hybrid quantum/classical program compiles once into a Jax IR (**Jaxpr**) and
lowers to machine code — enabling *real-time* classical computation
(decoding, arithmetic, branching) inside the quantum program's timeline
rather than by re-running the Python interpreter. The mechanism is Jax
**tracing**.

---

## Tracing and the "dynamic value" (the tracer)

**Paper, §6 Outlook (p. 15), verbatim** — the mechanism Jasp is built on:
"A third approach has been presented with the **Jax** framework. … Jax is
able to compile Python code by leveraging a mechanism called **tracing**.
**Tracing means sending so called tracers instead of values through the
code, which record the instructions instead of actually executing them.**
The recordings are stored within an intermediate representation called
**Jaxpr**, which is subsequently lowered into a singular C call." The goal
(p. 15): "we aim to make Qrisp code Jax traceable such that algorithm
subroutines (such as adders within Shor's algorithm) have to be **traced
only once** and are subsequently called only 'symbolically', i.e. the Python
interpreter doesn't have to traverse them again." Item 4 of the advantages
(p. 15): "Since the **Jaxpr IR is built as a functional programming
language**, static investigation (such as formal verification) is
facilitated."

**Tutorial "How to think in Jasp", verbatim** — a measured value is a
tracer, i.e. **dynamic**: "Every `QuantumVariable` and its `.size`
attribute are dynamic. Furthermore classical values can also be dynamic.
For classical values, we can use the Python native `isinstance` check for
the **`jax.core.Tracer`** class, whether a variable is dynamic." Code cell
[11] on that page:

```python
k = measure(qf)
print("k is dynamic?: ", isinstance(k, Tracer))
# Output: k is dynamic?: True
```

So **`measure(...)` returns a `jax.core.Tracer`** — a placeholder recorded
into the Jaxpr, not a concrete Python `int`/`bool`. (Tutorial also notes:
"even though `QuantumVariables` behave dynamic, they are not tracers
themselves.")

---

## Host `if` on a measured value: refused — branch via `control(...)`

The measured value being a tracer is exactly *why* an ordinary Python `if`
is not the branching mechanism: a tracer has no concrete boolean value at
trace time. Instead of a host `if`, Jasp conditions quantum operations with
a **dedicated control construct**.

**Tutorial "How to think in Jasp", verbatim**: "Jasp code can be
conditioned on **classically known values**. For that we simply use the
**`control` feature from base-Qrisp but with dynamical, classical bools**."
Idiom shown:

```python
with control(ctrl_bl):
    qf -= 4
```

**`ClControl.html` reference, verbatim** — the environment behind
`control(...)` on a classical/measurement-derived condition: the
`ClControlEnvironment` "works with similar semantics as the
`ControlEnvironment`, implying this environment can also be entered using
the **`control`** keyword." Its documented example conditions a gate on a
measurement outcome:

```python
def test_f(i):
    a = QuantumFloat(3)
    a[:] = i
    b = measure(a)
    with control(b == 4):
        x(a[0])
    return measure(a)
```

Here `b = measure(a)` is a dynamic tracer, and the branch is written
`with control(b == 4): …` — **not** `if b == 4:`. The comparison feeds the
control environment; it is not resolved to a Python bool.

**Documented restriction (`ClControl.html`, verbatim)**: "Contrary to the
`ControlEnvironment` the `ClControlEnvironment` **must not have 'carry
values'**. This means that **no value that is created inside this
environment may be used outside of the environment**." (This mirrors, at the
engineering level, Proto-Quipper's boxing/modality barrier — see the Fu
distillation.)

**TODO — the exact refusal message for a host `if`.** The qrisp docs I
fetched (tutorial, `ClControl.html`, `jrange.html`, the Control-Flow index)
demonstrate the `control(...)` **replacement** and state that `measure(...)`
returns a `jax.core.Tracer`, but **none of the fetched pages quotes the
verbatim exception raised when a raw Python `if`/`bool()` is applied to a
tracer** (the underlying Jax error — a `TracerBoolConversionError` /
"Attempted boolean conversion of traced array" — is Jax behaviour, not
stated on the fetched qrisp pages). Do **not** cite a specific error string
until a source is fetched that prints it. What *is* verified: (i)
`measure()` yields a `jax.core.Tracer`; (ii) the sanctioned branch construct
is `with control(cond): …`, not host `if`.

---

## Dynamic loops: `jrange`, "same instructions every iteration", no `2^W` table

**Tutorial "How to think in Jasp", verbatim**: "Dynamical code is **scale
invariant**! For this we can use the **`jrange`** iterator, which allows you
to execute a **dynamic amount of loop iterations**." Idiom shown:

```python
for i in jrange(c):
    b += c // 5
```

`jrange` **replaces Python's `range`** so the iteration count can be a
dynamic tracer (e.g. a measurement result or `qv.size`) — a Python `for i in
range(k)` cannot, because `k` is a tracer with no concrete value at trace
time.

**`jrange` reference, verbatim restrictions and their exact error strings**
(`jrange.html`):

- "**Each loop iteration must perform exactly the same instructions** — the
  only thing that changes is the loop index." Violating this (e.g. flipping
  behaviour via a flag) raises: **`"Jax semantics changed during jrange
  iteration"`**.
- "this feature **must not have external carry values**, implying values
  computed within the loop **can't be used outside of the loop**." Returning
  the incremented loop index raises: **`"Found jrange with external carry
  value"`**.

**Why this is the "compile once, no `2^W` table" property.** The two
restrictions are exactly what let the loop **body be traced a single time**
and emitted as one parametric Jaxpr block with a dynamic trip count, instead
of unrolled per concrete value: the body must be iteration-invariant ("same
instructions every iteration") and side-effect-closed ("no external carry").
The paper's "traced only once … called only symbolically" (§6, p. 15)
states the same compile-once property for subroutines; the tutorial's "scale
invariant" states it for `jrange`. So a Jasp program with a width-`W`
measurement-derived bound compiles to **one** loop over a dynamic integer,
**not** a `2^W`-entry dispatch table — the register width never enters the
compiled artifact's size.

**TODO — verbatim single-pass wording.** The specific phrase "compiled
once / no `2^W` table" is **Sturm's framing (D3)**. The fetched sources
support it via (a) "traced only once … symbolically" (paper §6, p. 15) and
(b) "Dynamical code is scale invariant" + `jrange`'s iteration-invariance
requirement (tutorial / `jrange.html`). A doc page that states in one
sentence "the loop body is compiled exactly once regardless of the bound"
was **not** located among the fetched pages; if a precise verbatim is later
needed, fetch the `jrange` source module or the changelog before quoting.

---

## The Jasp Hybrid Control-Flow catalogue (what ships)

From the Control-Flow reference index (`Control Flow/index.html`), verbatim
framing — "To enable a fully hybrid software stack, we need the ability to
perform quantum computations **based on the results of classical
conditions**" — the shipped constructs are:

- **`ClControlEnvironment`** (`ClControl.html`) — branch quantum ops on a
  classical/measurement-derived condition via `with control(cond): …`.
- **Loops** (`jrange.html`) — `jrange`, dynamic-trip-count loops.
- **Prefix Control** (`Prefix Control.html`).
- **Repeat-Until-Success (RUS)** (`RUS.html`) — measurement-conditioned
  retry.

(The names `cond`, `q_fori_loop`, `q_while_loop` were **not** confirmed on
the fetched index page — **TODO** if a per-primitive citation is needed.)

---

## What Sturm takes from this (PRD-v2 §3.6 / D3)

- **A token is a "dynamic value", not a concrete classical value.** Sturm's
  `ClassicalBit` / `ClassicalWord{W}` under `Tracing` are the analogue of a
  Jasp **`jax.core.Tracer`**: a symbolic outcome that steers later
  generation but is not resolved to a Python `Bool`/`Int` at construction
  time. This is the *implemented* face of Fu et al.'s parameter-vs-state
  boundary (`docs/physics/fu_proto_quipper_dyn.md`): the tracer is the
  runtime shape of a "state that has been admitted into generation under a
  discipline."

- **No host `if` on a token — go through `cases` / `control`, the way Jasp
  goes through `control(...)`.** Jasp demonstrates, in a shipped system,
  that branching on a measurement uses a *dedicated construct*
  (`with control(cond): …`), not a raw Python `if`. Sturm's D3 ruling —
  tokens branch through surface construct 6 (`cases` / `@cases`), never a
  bare host conditional — is the same design choice, and Jasp is its shipped
  precedent. The "must not have carry values" rule of `ClControlEnvironment`
  is the engineering cousin of §3.6's region/SSA confinement.

- **T1–T4 restricted SSA ≈ `jrange`'s two rules.** `jrange`'s "same
  instructions every iteration" + "no external carry value" are precisely a
  *restricted single-static-assignment* discipline on the loop body — the
  same shape as §3.6's T1–T4 restricted SSA on tokens. Both exist for the
  same reason: to keep the traced region **statically analysable and
  compiled once**.

- **No `2^W` branch table — the width never enters the artifact.** Jasp's
  dynamic-bound loop compiles to one parametric block (scale-invariant,
  traced once), not a `2^W` dispatch. Sturm's §3.6 token layer inherits this
  goal: a width-`W` classical outcome drives generation without
  materialising `2^W` branches — matching Fu et al.'s single-branch boxed
  circuit (that paper, §1.5, p. 5) from the *implementation* side.

**Skeptical scope note.** Qrisp/Jasp is cited as **shipped precedent for the
token discipline only** (§3.6 / D3) — that a real system represents measured
values as dynamic tracers, refuses to treat them as concrete host values,
and routes branching/looping through dedicated constructs that compile once.
It is **not** cited for Qrisp's gate set, its uncomputation/allocation
automation, or any correctness claim about Qrisp's compiler. Two honest
gaps, both flagged above as **TODO**: (1) no fetched qrisp page quotes the
verbatim exception for a host `if` on a tracer; (2) the exact "compiled once,
no `2^W` table" one-liner is Sturm's framing, supported but not verbatim in
the fetched sources. Neither gap is filled from memory. The *type-theoretic*
grounding for the same discipline is Fu et al.,
`docs/physics/fu_proto_quipper_dyn.md`.
