# Common gotchas

*A symptom index. Each entry is: what you saw → why it happens → what to do.
Sturm fails loudly by design, so most of these arrive as an error message you
can search this page for.*

The counter-intuitive facts collected here are not rough edges waiting to be
smoothed. Almost every one is a place where a plausible-looking alternative
would be silently wrong, and the loudness is the feature.

---

## Surface language

### `UndefVarError: eager not defined`

**Symptom**

```
UndefVarError: `eager` not defined in `Main`
Hint: a global variable of this name also exists in Sturm.
```

**Why.** `using Sturm` exports only the seven surface constructs and their
sugar. Contexts, the kernel and the library internals are *public but not
exported* — supported and documented, just not dumped into your namespace.

**Fix.** Qualify it, or import it explicitly.

```julia
using Sturm
Sturm.eager(2) do ctx; Bool(QBool(true)) end   # => true

# or, once, at the top of a script:
using Sturm: eager, density, shots
```

### `register … already consumed`

**Symptom**

```
register WireID(1) already consumed — a measurement cast consumes its input;
a live handle to measured (now classical) data is a type lie, and you cannot
read it again
```

**Why.** `Bool(q)` and `Int(x)` are *consuming* casts. There is no
measure-and-keep, because there is no measure-and-keep in physics. This is
no-cloning surfacing as a use-after-free.

**Fix.** Bind the result once and reuse the classical value.

```julia
# WRONG — for illustration
m = Bool(q)
if Bool(q) …          # q is already gone

# RIGHT
m = Bool(q)
if m …
```

### `quantum registers have no value equality`

**Symptom**

```
ArgumentError: quantum registers have no value equality — measuring is the only
way to read quantum content, and it consumes the handle. Use `===` for handle
identity, or measure explicitly (`Bool(q)` / `Int(x)`).
```

**Why.** A register is a *handle*, not a number. Comparing two of them would
have to mean either "same physical wire" or "same quantum state", and the
second one is not a thing you can ask without measuring.

**Fix.** `===` for identity; measure if you want the value.

### `register … is partially consumed`

**Symptom**

```
Int(x): register (WireID(1), WireID(2), WireID(3)) is partially consumed —
wire(s) [WireID(3)] are dead (a slice `x[i]` was measured via `Bool(x[i])`, or
the register was traced). Measure the remaining wires explicitly; do not
`Int(x)` a holed register.
```

**Why.** `x[i]` is a *borrowed* single-wire handle into the parent. Measuring
it consumes that wire of the parent, so the parent is now full of holes and
`Int(x)` would have to invent bits.

**Fix.** Measure the whole register first, or measure every slice you need.

```julia
using Sturm

Sturm.eager(4) do ctx
    x = QInt{3}(5)                        # 0b101; wire 1 is the MSB
    (Bool(x[1]), Bool(x[2]), Bool(x[3]))
end
# => (true, false, true)
```

### `x = x + a` quietly drops a register

**Symptom.** No error by default. Your program's statistics are subtly wrong.

**Why.** `x + a` is *value-world* arithmetic: it allocates a **fresh** register
and leaves `x` live. `x += a` lowers to `x = x + a`, which rebinds the name and
drops the original — still live, still entangled with the sum, now unreachable
and destined to be traced.

**Fix.** `add!(x, a)` for in-place addition. Arm the detector with
`strict = true` while you are hunting:

```
lost binding (strict): register wire(s) [WireID(1)] are being traced at region
exit, but a fresh value-world output (wire WireID(3)) derived from them by a
ring op (`x + a` / `x + y`) survives and is entangled with them — the sum has
decohered. You likely wrote `x = x + a` … Use `add!(x, a)` for in-place
addition, `x̂ += a` for a dual-view modulation, or keep BOTH handles live.
```

### `x̂ += a` does not change `Int(x)`

**Symptom.** You added something and the register still reads the same.

**Why.** Through the conjugate view, addition is *modulation*, not translation
— it attaches value-dependent phases. It is a different physical operation
from `add!`, and it shows up in `Int(dual(x))`, never in `Int(x)`.

**Fix.** Decide which one you meant. Full comparison in
[views and duality](views_and_duality.md).

### `syntax: invalid assignment location "dual(q)"`

**Why.** Julia needs an assignable location on the left of `⊻=`. A function
call is not one.

**Fix.** Bind the view first.

```julia
# WRONG — for illustration
dual(q) ⊻= r

# RIGHT
q̂ = dual(q)
q̂ ⊻= r
```

### `dual(x) = y` silently shadows `dual`

**Symptom.** No error. `dual` stops working correctly, somewhere in the same
function.

**Why.** Inside a function body, `dual(x) = y` is a short-form *method
definition*. It defines a local function named `dual` for the whole body.

```julia
# WRONG — for illustration
function trap(q)
    dual(x) = 7
    return dual(q)
end
trap(3)
# => 7
```

**Fix.** Never assign to a call expression named `dual`. This is a Julia
footgun, not a Sturm one, but it bites hardest in view-heavy code.

---

## `when` and `cases`

### Something is "forbidden inside a `when` body"

**Symptom** (measurement, `ptrace!`, `cases` and noise all give this shape)

```
measurement cast Bool(q) is forbidden inside a `when` body (guardrail 1):
a control frame is live, and control on a non-unitary effect (measurement,
trace, noise) is unrepresentable by axiom P4 — the body must trace to a
unitary-witnessed value.
```

**Why.** Quantum control is an operation on *definite operations*, never on
channels. There is no such thing as a controlled measurement — not "we did not
implement it", but "it does not denote anything". The instinct "measure inside
the controlled block so it collapses conditionally" is backwards for this
language.

**Fix.** Measure first and use [`cases`](seven_constructs.md), or restructure
so the body is unitary.

### `the when body operates on its control register`

**Symptom**

```
the `when` body operates on its control register WireID(1) (guardrail 2):
a body must not read or write its guard — not as a target, not as an
op-control, not through a view. (Legal kickback names a DIFFERENT register as
the target and lets the control pick up phase through the `ctrl` mechanism.)
```

**Why.** A guard that is also a target is not a controlled operation; it is a
different operation nobody has defined.

**Fix.** Target a different register. For an *anti*-control — fire when the
guard is `|0⟩` — flip it around the block:

```julia
not!(q)
when(q) do
    # ...
end
not!(q)
```

Note that kickback is legal and expected: `when(q) do not!(dual(r)) end` gives
`q` a phase. That is physics, not a leak.

### `clean-ancilla witness FAILED`

**Symptom**

```
clean-ancilla witness FAILED for WireID(4): its |1⟩-marginal is 1.0 > 1.0e-10.
A scratch ancilla must be uncomputed to a DISENTANGLED |0⟩ before it leaves a
`when` body — otherwise tracing it would decohere the control (a silent wrong
channel).
```

**Why.** Scratch that leaves a controlled block still entangled would decohere
the control when it is eventually traced — turning a coherent operation into a
noisy one, quietly.

**Fix.** Uncompute the scratch inside the body. If you hit this from
[`oracle`](../howto/write_oracles.md), the usual cause is an accumulation
target too narrow for `f`'s output.

### `cases … takes a CLASSICAL outcome`

**Symptom**

```
cases/@cases takes a CLASSICAL outcome, never a raw quantum register:
measure first — `cases(Bool(q)) do … end`. A register-accepting form would
hide the quantum→classical (measurement) instrument boundary.
```

**Why.** A form that accepted a register would hide a measurement inside what
looks like a branch. Sturm makes every boundary crossing visible.

---

## Contexts and statistics

### `TypeError: non-boolean … used in boolean context`

**Symptom**

```
TypeError: non-boolean (Sturm.ClassicalBit{Sturm.DensityMatrixContext}) used in
boolean context
```

**Why.** Under a density context, `Bool(q)` returns a *record token*, not a
`Bool` — the exact channel has no single outcome. Julia's own type check fires,
which is exactly right: not silently wrong, just refused.

**Fix.** Branch with `cases`, choose a value with `Sturm.select`, and read
probabilities with `Sturm.record_distribution`. See
[getting probabilities out](../howto/measure_statistics.md).

### `no method matching record_distribution(::Bool)`

**Why.** There is nothing to introspect on an eager context: the scalar *is*
the answer, and no distribution survives it.

**Fix.** `Sturm.shots` for a sampled distribution on eager;
`Sturm.record_distribution` on density.

### `context capacity (N wires) exceeded`

**Why.** A context is created with a fixed qubit budget and every allocation —
including scratch you never see — comes out of it. An `oracle` call in
particular can need a dozen ancillas.

**Fix.** Raise the capacity, with the memory in mind: an eager context is
`2^capacity` complex amplitudes at 16 bytes each, so 20 wires is 16 MiB, 26 is
1 GiB, 30 is about 16 GiB. A density context stores the square of that, so its
practical ceiling is roughly half the qubit count.

### `a statevector cannot hold the mixed state a noise channel produces`

**Symptom**

```
apply!: a statevector cannot hold the mixed state a noise channel produces.
Choose explicitly: density(cap) executes the exact channel in one run;
shots(…) samples trajectories; stinespring=true dilates + traces — ONE
quantum-jump unravelling per run, NOT the channel.
```

**Why.** Refusing is better than approximating. Note the last clause: even with
dilation, **one run is one trajectory, not the channel**.

**Fix.** Use `Sturm.density` for the exact channel; `Sturm.shots` if you want
trajectories on purpose.

### An implicit measurement warned at me

**Symptom**

```
Warning: implicit measurement of a QBool: a quantum→classical cast collapses
state — write `Bool(q)` explicitly to silence this
```

**Why.** You assigned a register into a `Bool`-typed slot and the compiler
inserted a cast. Collapse is a real effect, so it warns.

**Fix.** Write `Bool(q)` yourself. Explicit casts never warn.

### Nothing warned when my local register disappeared

**Symptom.** A register allocated in a `region` (or in a function body) is
gone afterwards, with no message.

**Why.** This is correct and deliberate. Locals are the environment; scope exit
traces them; a trace has no backaction, so nothing observable could have told
you. This is the one place Sturm is intentionally silent. See
[contexts and scope](contexts_and_scope.md).

**Fix.** If you want a register to survive, return it. If you want to close one
early and say so, `ptrace!`.

---

## Kernel and channels

### `==` said no when the physics said yes

**Symptom.** `Sturm.H ∘ Sturm.H == Sturm.I2` is `false`.
`Sturm.adjoint(Sturm.X) == Sturm.X` is `false`.

**Why.** `==` is exact structural equality on the stored representation. The
physically meaningful comparison is `≈`, which knows that a quaternion and its
negation with the phase shifted by π describe the same operation.

```julia
using Sturm

Sturm.H ∘ Sturm.H ≈ Sturm.I2         # => true
Sturm.adjoint(Sturm.X) ≈ Sturm.X     # => true
```

**Fix.** Physics questions use `≈`. `==` asks whether two values are literally
the same.

### `Ry(2π)` is not the identity

**Why.** It is `−I`, and that is spin-½ physics — a full turn does not restore
a spinor, two turns do.

```julia
using Sturm

Sturm.Ry(2π) ≈ Sturm.NEG_I   # => true
Sturm.Ry(2π) ≈ Sturm.I2      # => false
Sturm.Ry(4π) ≈ Sturm.I2      # => true
```

Under control the difference is observable, so the kernel never merges the two.
See [phase discipline](phase_discipline.md).

### `same_channel` said two things were equal that behave differently

**Why.** Channel-level comparison is blind to global phase. `−I` and `+I`
compare equal; their *controlled* forms do not.

```julia
using Sturm

Sturm.same_channel(Sturm.channel(Sturm.NEG_I), Sturm.channel(Sturm.I2))
# => true
Sturm.same_channel(Sturm.channel(Sturm.ctrl(Sturm.NEG_I)),
                   Sturm.channel(Sturm.ctrl(Sturm.I2)))
# => false
```

**Fix.** Never use channel-level comparison to check that a rewrite of a value
that may later be controlled was correct. This is the industry's long-running
controlled-phase bug class, re-entering through the test suite.

### `classicalise` says two different channels are the same

**Why.** It is a *classical shadow* and is deliberately phase-blind:

```julia
using Sturm

Sturm.classicalise(Sturm.channel(Sturm.I2))   # => [1.0 0.0; 0.0 1.0]
Sturm.classicalise(Sturm.channel(Sturm.Z))    # => [1.0 0.0; 0.0 1.0]
```

**Fix.** It is an analysis tool, never an equivalence test.

### `no method matching ctrl(::KrausFamily…)`

**Why.** Control is defined on definite operations, not on channels. The
absence of a method *is* the statement that controlling a channel is
meaningless — there is no catch-all to give you a plausible wrong answer.

### A cap fired instead of taking a long time

**Symptom.** One of

```
ArgumentError: classicalise: 4 wires exceeds CLASSICALISE_MAXWIRES = 3
```

**Why.** Several analysis routines build dense exponential-size objects, so
each carries a hard, named ceiling rather than quietly consuming your RAM. The
same discipline applies to permutation comparison, Choi construction and
dilation.

**Fix.** Work on smaller instances, or use a sampling probe.

### `KrausFamily … not trace-preserving`

**Symptom**

```
ArgumentError: KrausFamily(custom): not trace-preserving —
‖Σᵢ Kᵢ†Kᵢ − I‖_∞ = 0.75 (> KRAUS_TP_ATOL = 1.0e-12). Fix the family; Sturm
never renormalises.
```

**Why.** A channel that does not preserve trace is not a channel. Sturm will
not quietly rescale your operators into one.

---

## Oracles

### `the Bennett backend is not loaded`

**Fix.** `using Bennett` alongside `using Sturm`. The compiler front-end is a
weak dependency so that `using Sturm` stays light.

### `Bennett could not compile f`

**Why and fix.** Every documented limit — data-dependent loops, `count_ones`,
width bounds, single input register, aliasing, target width — is enumerated
with a failing/working pair in
[writing oracles](../howto/write_oracles.md).

---

## Where next

- [Functions are channels](functions_are_channels.md) — why the biggest
  gotcha of all is a passing test.
- [The seven constructs](seven_constructs.md).
- [Views and duality](views_and_duality.md).
- [Contexts and scope](contexts_and_scope.md).
- [Phase discipline](phase_discipline.md).
