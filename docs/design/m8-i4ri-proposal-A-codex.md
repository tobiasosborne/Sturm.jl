# Sturm.jl M8 Design Gate Proposal  
## Classical control, branch joins, density semantics, and measurement spelling

**Bead:** `i4ri`  
**Scope:** M8 design only; no implementation  
**Status:** Proposed, with one explicitly reserved Tobias ruling on measurement spelling

## 1. Decisions at a glance

| Finding | Proposed resolution |
|---|---|
| F4 | Use a **restricted, structured classical SSA/CFG IR**, not staged dynamic lifting. The IR has finite typed values, pure total operations, acyclic `cases`, and no dynamic host loops or arbitrary Julia indexing. |
| F6 | Tokens are **copyable**, not affine. Preserve an explicit joint classical–quantum correlation record \(\sum_\gamma |\gamma\rangle\langle\gamma|\otimes\rho_\gamma\). Branch joins require identical live quantum port and ownership signatures. |
| F5 | Exact `DensityMatrixContext` observation returns a token and requires `cases`. Scalar outcomes exist only in trajectory contexts or completed shot results. |
| F13 | **Tobias ruling required.** Recommendation: `measure(q)` is context-polymorphic; `Bool(q)`/`Int(x)` are scalar-only conveniences for trajectory contexts and otherwise throw. |
| F30 | `@cases` must not measure a bare quantum register. Its selector must be an already-classical value or an explicit observation expression, preferably `@cases measure(m)`. |

The remainder of this document uses `measure` as the recommended spelling. That spelling is conditional on the F13 ruling; the underlying IR and physics do not depend on the name.

---

## 2. Mechanism choice: restricted classical SSA/CFG

### 2.1 Why staged dynamic lifting is rejected for M8

Staged dynamic lifting pauses after measurement, obtains an outcome, and resumes or retraces the Julia continuation for that outcome. It makes arbitrary Julia indexing and dynamic loops possible, but it has the wrong core properties for Sturm:

1. It does not produce one compiled channel independent of outcomes.
2. Exact density execution would have to resume every outcome continuation and retain their joint history anyway.
3. Hardware execution may require an unbounded number of host/device round trips.
4. Compilation cost and emitted circuit shape become outcome-dependent.
5. Channel inspection, optimization, and export cease to operate on one stable IR.

Staged lifting remains a possible future, explicitly trajectory-only execution strategy. It is not the meaning of a traced Sturm channel.

### 2.2 Chosen representation

`TracingContext` constructs a structured, acyclic channel IR containing both quantum effects and a restricted classical SSA graph.

The relevant node families are:

```text
MeasureNode{T}
    instrument
    quantum_inputs
    classical_output::ValueID
    consumed_quantum_ports

ClassicalNode{T}
    opcode
    operands::ValueID...
    output::ValueID

ClassicalSelectNode{T}
    predicate::ValueID
    false_value::ValueID
    true_value::ValueID
    output::ValueID

CasesNode
    selector::ValueID
    arms::ArmRegion...
    join::JoinSignature

ArmRegion
    labels
    channel_region

JoinSignature
    live_quantum_ports
    consumed_quantum_ports
    ownership
    register_shapes
```

`MeasureNode`, `CasesNode`, discard, reset, and noise are channel nodes and therefore barriers to unitary-only passes. A maximal unitary region may still carry a phase-fixed process witness; the containing channel IR must not.

The CFG is deliberately structured:

- `CasesNode` is the only runtime branch.
- There are no arbitrary jumps.
- There are no backedges or token-dependent loops in M8.
- Classical conditional values use `ClassicalSelectNode`, not general φ nodes.
- `cases` is statement-valued and returns `nothing`; it does not create quantum φ values.

This remains a DAG with nested branch regions, rather than a general cyclic compiler CFG.

### 2.3 Classical token types

The minimum M8 types are:

- `ClassicalBit`
- `ClassicalWord{W}`, an unsigned \(W\)-bit word with \(W\ge1\)

Neither type subtypes `Bool`, `Integer`, or `Number`. A token is an opaque reference to an SSA `ValueID`, not a placeholder host value.

`ClassicalWord{W}` is preferable to `ClassicalInt`: the measurement domain is the finite computational basis \(\mathbb Z_{2^W}\), while Julia `Int` is machine-sized. Width is part of the IR type, arithmetic wraps modulo \(2^W\), and hardware lowering has an explicit bit width.

### 2.4 Exact supported classical subset

All supported operations are pure, deterministic, total on their declared finite domains, and side-effect free.

| Type | Supported operations |
|---|---|
| `ClassicalBit` | `!`, `&`, `|`, `xor`/`⊻`, `==`, `!=` |
| `ClassicalWord{W}` | modular `+`, `-`, `*`; bitwise `&`, `|`, `xor`, `~`; unsigned comparisons; shifts by a concrete nonnegative integer; bit extraction at a concrete index |
| Either | equality with representable literals; `select(predicate, a, b)` |
| Static tables | lookup in an immutable `ClassicalTable` with a total result for every possible index |

Width-changing operations require explicit helpers such as zero extension, truncation, or concatenation. They must never occur by implicit Julia conversion.

A `ClassicalTable` is an immutable snapshot captured when tracing begins. Token indexing is supported only on this wrapper:

```julia
decoder = ClassicalTable((0, 3, 1, 2))
location = decoder[syndrome]
```

Lookup must be total. If the token domain exceeds the table, construction requires an explicit default; otherwise tracing fails.

Ordinary arrays, dictionaries, strings, mutable objects, and foreign memory cannot be indexed by a token.

### 2.5 Loops and indexing

A Julia loop is supported only when its bounds and iteration protocol are concrete during tracing:

```julia
for j in 1:N
    flag = location == j
    @cases flag begin
        correct!(data[j])
    end
end
```

Here `N` and `j` are host integers and the loop is statically unrolled. `location` remains symbolic.

The following are outside M8:

- a token as a range endpoint or loop bound;
- token-dependent `while`;
- token-dependent recursion;
- allocation whose size depends on a token;
- token-dependent dispatch or `Val(token)`;
- a token as a dictionary/hash key;
- arbitrary array indexing with a token;
- mutation of host memory selected by a token;
- floating-point token computation;
- exceptions or I/O conditioned on a token;
- interpolation of a token into an arbitrary `U2`, process value, type parameter, or FFI call.

Classical results influence quantum execution through `cases`. A backend may lower a single-arm Boolean case to a compact classically-controlled process node, but that is a lowering, not another surface construct.

This subset is enough for scalable syndrome processing without an implicit \(2^W\)-arm branch:

```julia
syndrome = measure(syndrome_register)
location = decoder[syndrome]

for j in 1:N
    @cases location == j begin
        correct!(data[j])
    end
end
```

IR size follows the written static computation. The tracer must never enumerate every value of a word merely because its domain has size \(2^W\).

### 2.6 Loud-rejection boundary

There is no fallback concretization, default value, or hard-coded `false`.

When Sturm controls dispatch, unsupported operations throw `ArgumentError` naming the unsupported operation and its supported replacement. Dangerous host conversions and protocols should have explicit throwing methods, including:

- `Bool(token)` and `Int(token)`;
- `iterate(token)`;
- token-derived ranges;
- `Val(token)`;
- hashing a token;
- ordinary array indexing by a token.

Where Julia itself owns the operation, native failure is the normative behavior:

- `if token` throws Julia’s non-boolean `TypeError`;
- `token && rhs` and `token || rhs` throw the same `TypeError`;
- an unregistered generic function normally throws `MethodError`.

These are loud failures, although the `if` error cannot reliably be replaced at token dispatch with a Sturm-specific message. Documentation must not promise otherwise.

---

## 3. Token and branch-join semantics

### 3.1 Tokens are copyable, not affine

Classical measurement records are ordinary classical information and may legitimately control multiple later corrections. QECC syndrome bits are the canonical customer.

Therefore tokens are copyable references to SSA values:

```julia
s2 = syndrome
```

does not create a new measurement or consume `syndrome`; both bindings reference the same `ValueID`.

An affine-token design would avoid maintaining correlations, but would force users to combine all feed-forward into one syntactic branch and would obstruct repeated syndrome use, Pauli-frame processing, and independent correction stages. It is rejected.

### 3.2 Physical meaning of a live classical record

A consumed measurement with outcomes \(i\) is an instrument, not merely a pinching channel. If the measured quantum port is not returned, its branch map is

\[
\mathcal M_i(\rho)
=
\operatorname{Tr}_{M}
\!\left[
(P_i\otimes I)\rho(P_i\otimes I)
\right].
\]

The exact post-measurement state is the hybrid classical–quantum record

\[
\sigma_{CQ}
=
\sum_i |i\rangle\!\langle i|_C\otimes\widetilde\rho_i,
\qquad
\widetilde\rho_i=\mathcal M_i(\rho).
\]

The branch states are unnormalized; \(\operatorname{Tr}\widetilde\rho_i\) is the Born weight.

With several measurements, \(\gamma\) denotes the complete joint assignment of live root outcomes:

\[
\sigma_{CQ}
=
\sum_\gamma
|\gamma\rangle\!\langle\gamma|_C
\otimes\widetilde\rho_\gamma .
\]

A deterministic classical SSA operation \(y=f(\gamma)\) extends the record as

\[
\sum_\gamma
|\gamma,f(\gamma)\rangle\!\langle\gamma,f(\gamma)|
\otimes\widetilde\rho_\gamma .
\]

It does not split or sample the state.

### 3.3 Semantics of `cases`

For a selector \(g(\gamma)\) and branch channels \(\mathcal E_v\),

\[
\sigma'_{CQ}
=
\sum_\gamma
|\gamma\rangle\!\langle\gamma|_C
\otimes
\mathcal E_{g(\gamma)}(\widetilde\rho_\gamma).
\]

The classical record remains present after the branch. A second `cases` using the same token therefore sees the same outcome.

This is the critical correction to “trace branch ancillae, then block-accumulate.” Branch-local quantum ancillae may be traced before joining, but rows with distinguishable live classical records must not be summed.

Rows may be coalesced only when:

1. no future node reads a classical value that distinguishes them; and
2. the distinguishing value is not a classical channel output.

At final quantum-only output, tracing the classical record gives the expected channel:

\[
\operatorname{Tr}_C(\sigma_{CQ})=\sum_\gamma\widetilde\rho_\gamma.
\]

### 3.4 Exact density execution

`DensityMatrixContext` must maintain a sparse hybrid record, logically equivalent to rows

```text
(classical assignment, Born weight, normalized density state)
```

or, equivalently, assignments paired with unnormalized density operators.

Every quantum operation is applied independently to every compatible row. Measurement extends each assignment with an outcome. `cases` selects a branch using the row’s assignment. Deterministic SSA expressions are evaluated against that assignment.

The implementation may retain all rows until region exit or perform SSA-liveness-based coalescing earlier. Coalescing is an optimization and must not change correlation semantics.

If a channel returns classical data, the result is a hybrid cq output, not a bare density matrix. A Choi harness expecting only quantum output must explicitly trace or reject classical outputs.

### 3.5 Branch syntax

The general form is:

```julia
@cases selector begin
    false => begin
        ...
    end
    true => begin
        ...
    end
end
```

For finite words:

```julia
@cases opcode begin
    0 => begin ... end
    1 => begin ... end
    _ => begin ... end
end
```

Labels must be concrete, disjoint literals. A final `_` is the only wildcard. Arms must cover the selector domain, except for the existing binary shorthand:

```julia
@cases flag begin
    body
end
```

which means `true => body`, `false => identity`.

The selector expression is evaluated exactly once.

### 3.6 Quantum join-typing rule

Let the quantum signature of a branch be the ordered collection of:

```text
(port identity,
 register type and width,
 live/consumed status,
 owning region,
 borrow/view parent)
```

For

\[
\operatorname{cases}(s,\{v\mapsto B_v\})
\]

to type-check, every branch must finish with exactly the same quantum signature.

Formally:

\[
\frac{
\Gamma_C\vdash s:T
\qquad
\forall v,\;
\Gamma_C;\Gamma_Q\vdash B_v\dashv\Gamma_C^v;\Gamma_Q'
}{
\Gamma_C;\Gamma_Q
\vdash
\operatorname{cases}(s,\{B_v\})
\dashv
\Gamma_C;\Gamma_Q'
}
\]

subject to:

1. The same pre-existing quantum port is live in every arm or consumed in every arm.
2. A port may not be consumed in only some arms.
3. A surviving pre-existing port retains the same `WireID` and register grouping.
4. Branch-local owned registers must be consumed or traced before branch exit.
5. A branch-local register cannot escape the join.
6. Views and `WireRef`s retain the same parent relationships.
7. Each arm returns `nothing`; `cases` returns `nothing`.
8. Branch-local classical SSA values do not escape. A conditional classical value must be constructed explicitly with `select`.

Examples of loud join errors include:

- measuring `q` in only the `true` arm;
- returning a new `QBool` from each arm;
- leaving a branch-local ancilla live;
- changing a `QInt{W}` into a partially consumed register in one arm;
- rebinding an outer handle to a different register in one arm.

This conservative rule deliberately avoids quantum φ nodes. Quantum φ/ownership transfer can be proposed later as a separate design gate.

### 3.7 Fit with the current context model

The rule aligns with existing Sturm machinery:

- `WireID` remains the quantum port identity.
- The context’s consumed set remains the single source of liveness.
- Branch construction snapshots or forks region ownership and consumption metadata.
- Measurement still consumes the handle.
- Branch-local region exit traces only branch-local owned wires.
- Existing `when` guardrail 1 remains: `measure` and `cases` under coherent control are loud errors.
- The classical record is new state attached to exact density and tracing contexts; it must not be encoded by pretending measured wires remain ordinary quantum handles.

---

## 4. Corrected context portability

### 4.1 Normative table

The table below assumes the recommended `measure` spelling.

| Construct | EagerContext | DensityMatrixContext | TracingContext | Hardware compilation | Explicit density trajectory |
|---|---:|---:|---:|---:|---:|
| Preparation, actions, `dual`, `when`, `oracle` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `measure(q)` result | scalar `Bool`/integer | token | token | token | scalar `Bool`/integer |
| `Bool(q)` / `Int(x)` | scalar convenience | ✗ throws before backaction | ✗ throws before emitting a token | ✗ during program construction | scalar convenience |
| Host `if`, `&&`, `||` on an observation | ✓ | ✗ non-Boolean token | ✗ non-Boolean token | ✗ runtime outcome unavailable to host | ✓ |
| Whitelisted classical SSA operations | ordinary Julia values | symbolic/exact | symbolic IR | capability-checked IR | ordinary Julia values |
| `cases` | execute selected arm | execute all correlated arms exactly | emit `CasesNode` | dynamic branch if supported | execute selected arm |
| Concrete-bounded Julia loop | execute | trace-time unroll | trace-time unroll | compile-time unroll | execute |
| Token-bounded loop or arbitrary token indexing | ordinary only after scalar measurement | ✗ | ✗ | ✗ | ordinary only after scalar measurement |
| Exact one-run channel/Choi semantics | ✗ trajectory | ✓ | IR only | target-dependent execution | ✗ trajectory |

A hardware target must advertise the supported classical opcodes, word widths, branch depth, and dynamic-control capability. Unsupported classical operations or `cases` are compile errors before submission. No backend may silently replace dynamic control with independent shots or host retracing.

Completed hardware shot results are ordinary Julia values after program execution. Host `if` is valid in post-processing; it is not mid-circuit control.

### 4.2 Explicit trajectory surface

`EagerContext` is already a trajectory context: it samples and normalizes one instrument branch.

Density trajectories require a distinct wrapper type rather than a Boolean mode flag:

```julia
trajectory(DensityMatrixContext, capacity; rng, strict=false) do ctx
    ...
end
```

This constructs a `TrajectoryContext{DensityMatrixContext}`. Its observation operation samples one branch and returns a scalar. It must not be accepted by exact-channel or Choi APIs.

Repeated execution is exposed separately:

```julia
results = shots(1_000, program; backend=backend)
```

`shots` returns completed classical records. It does not change the compiled program’s use of tokens and `cases`.

For an exact density context, the channel remains

\[
\mathcal E(\rho)
=
\sum_i \mathcal E_i(\mathcal M_i(\rho)).
\]

A trajectory context samples one \(i\), normalizes that branch, and runs only \(\mathcal E_i\). These are different execution modes and must have different types.

---

## 5. F13: measurement spelling — Tobias ruling required

### 5.1 Verified Julia facts

Tested on Julia 1.12.5:

1. Julia technically permits a method such as `Bool(::Token)` to return a non-`Bool`. This is not enforced by the function object.
2. Doing so violates the normal meaning of a type constructor and conflicts with typed conversion use.
3. Lowered `if x` contains a `goto ... if not x`; it does not dispatch through `Bool(x)`.
4. `if Token()` and `Token() && true` raise Julia’s native:

   ```text
   TypeError: non-boolean (Token) used in boolean context
   ```

5. That control-flow check cannot be intercepted by a `Bool(::Token)` method.
6. `convert(Bool, x)` is expected to produce a real `Bool` for typed fields, arrays, and annotated returns.

The PRD therefore cannot promise that a token type itself throws a descriptive Sturm error from `if token`.

### 5.2 Option A — `measure` for context-polymorphic observation  
**Recommendation**

```julia
outcome = measure(q)
```

- Eager or trajectory context: returns an actual scalar.
- Exact density or tracing context: returns `ClassicalBit` or `ClassicalWord{W}`.
- Hardware compilation: returns a token.

`Bool(q)` and `Int(x)` remain trajectory-only conveniences. They must either return the named scalar type or throw before measurement; they never return a token.

Advantages:

- Respects Julia constructor expectations.
- Makes context-polymorphic observation visibly effectful.
- Separates scalar materialization from symbolic observation.
- Gives `@cases measure(m)` a single explicit measurement boundary.
- Allows `convert(Bool, q)` to keep its normal return contract and P2 warning.

Costs:

- Weakens the literal wording “the boundary is a cast.”
- Portable examples must migrate from `Bool(q)` to `measure(q)`.
- `measure` has a context-dependent return type, although that is unsurprising for an effectful execution API.

Recommended P2 wording: “The quantum–classical boundary is an explicit consuming observation; preparation remains a cast. Scalar trajectory materialization may use `Bool`/`Int` constructor syntax.”

### 5.3 Option B — dedicated result constructors

```julia
b = ClassicalBit(q)
w = ClassicalWord(x)
```

These constructors always return their named wrapper type. In a trajectory context, a separate operation extracts the scalar:

```julia
Bool(b)
```

Advantages:

- Strong constructor consistency.
- The observation result has one surface type across contexts.
- Potentially improves inference.

Costs:

- Two-step eager use is cumbersome.
- `if ClassicalBit(q)` still cannot work.
- The term “token” leaks into ordinary eager programming.
- It creates more surface types and conversions.

### 5.4 Option C — `observe` or `read`

This has the same semantics as Option A with a different verb.

`measure` has stronger quantum-language precedent and states the physical operation directly. `read` risks suggesting a non-destructive lookup; `observe` is accurate but less conventional.

### 5.5 Option D — retain `Bool(q)`/`Int(x)` returning tokens

Advantages:

- Minimal PRD and example churn.
- Preserves the cast slogan verbatim.

Costs:

- A constructor named `Bool` returns something that is not a `Bool`.
- Explicit and implicit conversion semantics diverge.
- Host `if` still produces only Julia’s generic `TypeError`.
- Return type depends on the runtime context.
- It teaches an exception to a central Julia convention.

This option is technically implementable but is not recommended.

### 5.6 Option E — rewrite host `if` through a macro/compiler overdub

A containing macro could rewrite `if`, loops, indexing, and φ values into a custom CFG.

This would approach Jasp/JAX-scale compiler work, make semantics depend on whether the containing function was rewritten, and conflict with the PRD’s explicit `cases` distinction. It is rejected for M8.

### 5.7 Requested ruling

Tobias must select the public observation spelling before M8 implementation begins.

This proposal recommends **Option A: `measure(q)` for portable observation; `Bool(q)`/`Int(x)` only for scalar trajectory materialization**.

The IR, join rule, and exact density semantics remain valid under Options B–D; only the surface spelling and PRD vocabulary row change.

---

## 6. F30 ruling: `@cases` never measures a bare register

The register form is rejected:

```julia
@cases m begin
    ...
end
```

if `m` is quantum.

The canonical form under the recommended F13 ruling is:

```julia
@cases measure(m) begin
    ...
end
```

If Tobias retains constructor syntax, the corresponding form is:

```julia
@cases Bool(m) begin
    ...
end
```

The macro evaluates the selector expression exactly once, so the quantum handle is consumed exactly once.

A raw register operand throws `ArgumentError` with a direct suggestion. It is not accepted as invisible or “visible” measurement sugar. Hiding measurement inside `@cases` would create a second qc boundary, contradict P2 and making token lifetime ambiguous.

The §7.6 injection examples therefore become:

```julia
@cases measure(m) begin
    not!(dual(ψ))
end
```

and:

```julia
@cases measure(m) begin
    inject_S!(ψ)
end
```

---

## 7. Named law tests

Each statement below is normative and should become a grep-able testset name.

### 7.1 Consuming Observation Law

`measure(q)` consumes every measured quantum port exactly once in every context. Any later operation through `q`, a view of `q`, or a parent register containing the port fails before state mutation.

### 7.2 Instrument Sum Law

For instrument maps \(\mathcal M_i\) and branch channels \(\mathcal E_i\), exact density execution of `cases` denotes

\[
\mathcal E(\rho)=\sum_i\mathcal E_i(\mathcal M_i(\rho)).
\]

A one-run exact DM result must equal a direct dense reference for small systems.

### 7.3 Repeated-Token Correlation Law

For a fair measured bit `m`, two later cases controlled by the same token must retain the same outcome. If each true arm flips one of `a` and `b`, exact DM output is

\[
\frac12|00\rangle\!\langle00|
+
\frac12|11\rangle\!\langle11|,
\]

not the independent mixture over `00`, `01`, `10`, and `11`.

### 7.4 Derived-Token Correlation Law

If `n = !m`, then branches controlled by `m` and `n` are perfectly anticorrelated. Classical SSA construction must not create a new stochastic record.

### 7.5 Classical Record Forgetting Law

Summing hybrid rows is permitted only after the distinguishing classical SSA value and every value derived from it are dead. Early coalescing followed by token reuse must be rejected by the executor invariant or caught by the repeated-token test.

### 7.6 Branch Join Identity Law

A `CasesNode` is constructible iff all arms produce identical quantum join signatures: port identity, liveness, register shape, ownership, and borrow/view relationships.

### 7.7 Partial Consumption Join Rejection Law

If one arm consumes a port and another leaves it live, tracing fails at the join with an error naming the port and the disagreeing arms.

### 7.8 Branch-Local Escape Rejection Law

A branch-local owned quantum register may not survive a `cases` join. Allocating and returning distinct registers from different arms fails; no quantum φ is inferred.

### 7.9 Branch-Local Trace Law

Branch-local ancillae that do not escape are traced within their arm before the join. This trace does not justify discarding the classical correlation record.

### 7.10 Host Boolean Rejection Law

`if token`, `token && rhs`, and `token || rhs` raise Julia’s native non-Boolean `TypeError`. No test expects a Sturm-dispatched exception from these constructs.

### 7.11 No Constructor Token Law

If the recommended F13 ruling is accepted, `Bool(q)`, `Int(x)`, `Bool(token)`, and `Int(token)` never return a symbolic token. They return the named scalar type or throw.

### 7.12 Static Loop Law

A loop with concrete trace-time bounds is unrolled. A token used as a bound, range endpoint, iterator, allocation size, or recursion condition fails loudly and emits no partial channel.

### 7.13 No Implicit Domain Expansion Law

A `ClassicalWord{W}` operation emits a number of IR nodes proportional to the written expression. Merely branching on or comparing a word never creates \(2^W\) arms.

### 7.14 Static Table Totality Law

A symbolic table lookup is accepted only for `ClassicalTable` with a result defined for every possible index. Incomplete lookup without a default fails during tracing.

### 7.15 Cases Measurement Spelling Law

`@cases measure(m)` consumes `m` once. `@cases m` with quantum `m` fails with a suggestion to write the explicit observation.

### 7.16 Exact-vs-Trajectory Separation Law

An exact density run is deterministic and returns the instrument sum. A density trajectory selects one normalized branch. Shot averages converge to the exact result, but a single trajectory is never accepted as an exact Choi evaluation.

### 7.17 Hardware Capability Law

Compilation of classical opcodes or `cases` unsupported by a target fails before submission and names the missing capability. It never silently substitutes host retracing, outcome enumeration, or independent shots.

### 7.18 Channel Barrier Law

No unitary-only pass may move, fuse, cancel, or compare operations across `MeasureNode`, `CasesNode`, discard, reset, or noise. Classical constant folding and CSE may operate on the classical SSA graph without changing token provenance.

### 7.19 Streaming/Materialized Cases Agreement Law

For a program accepted by both Eager trajectories and exact DM/Tracing, the empirical eager channel converges to the exact materialized `CasesNode` channel. Comparison uses channel-sensitive probes, not only measurement marginals.

---

## 8. Proposed PRD replacement text

The following wording assumes Tobias accepts the recommended `measure` spelling.

### 8.1 Replacement for §3.6

> ### 3.6 Classical outcomes and `cases`
>
> A consuming observation is written `measure(q)`. Under an eager or explicit trajectory context it returns an ordinary Julia scalar. Under `TracingContext`, exact `DensityMatrixContext`, and hardware compilation it returns a symbolic `ClassicalBit` or fixed-width `ClassicalWord{W}`.
>
> Symbolic classical values are not subtypes of `Bool`, `Integer`, or `Number`. They form a restricted finite SSA language. M8 supports pure total bit and fixed-width word operations: Boolean and bitwise operations, modular word addition/subtraction/multiplication, unsigned comparisons, constant shifts, constant bit extraction, explicit `select`, and total lookup in immutable `ClassicalTable` values. Width changes are explicit.
>
> Concrete Julia loops are permitted and unroll during tracing. A symbolic value may not control host `if`, `&&`, `||`, loop bounds, recursion, allocation size, dispatch, ordinary array indexing, mutable memory, I/O, exceptions, process-value construction, or FFI calls. Such uses fail loudly; `if token` and short-circuit Boolean syntax produce Julia’s native non-Boolean `TypeError`.
>
> Runtime classical branching is explicit:
>
> ```julia
> @cases selector begin
>     false => begin
>         ...
>     end
>     true => begin
>         ...
>     end
> end
> ```
>
> The binary shorthand
>
> ```julia
> @cases selector begin
>     body
> end
> ```
>
> means `true => body`, `false => identity`. Multiway cases use concrete disjoint labels plus an optional final `_` default. The selector expression is evaluated once.
>
> Tracing lowers observation to `MeasureNode`, classical computation to typed SSA nodes, and branching to an acyclic `CasesNode` with nested channel regions. There are no symbolic loop backedges or general φ nodes in M8.
>
> Tokens are copyable, not affine. Reusing a token in multiple `cases` refers to the same measurement record. Executors retain the joint cq state
>
> \[
> \sum_\gamma|\gamma\rangle\!\langle\gamma|_C\otimes\widetilde\rho_\gamma
> \]
>
> until the distinguishing classical values are dead or explicitly traced from the output. Immediate summation of measurement branches is forbidden while any token or derived value remains live.
>
> Every `cases` arm begins with the same quantum environment and must end with the same quantum signature: identical live port identities, register shapes, consumed status, ownership, and borrow/view relationships. A port consumed in only some arms, a surviving branch-local allocation, or a branch-dependent returned handle is a loud join error. `cases` returns `nothing`; quantum φ values are not inferred.
>
> Wide feedback is expressed by finite classical SSA plus concrete unrolled structure, not by an implicit \(2^W\)-arm outcome table. Dynamic token-dependent Julia loops and arbitrary token indexing are outside M8.

### 8.2 Replacement for §3.8

> ### 3.8 The v2 surface vocabulary and context portability
>
> | # | Surface form | Role | Lowering |
> |---|---|---|---|
> | 1 | `QBool(p, φ=0)` / `QBool(b)` | preparation cast | allocation plus literal process |
> | 2 | `measure(q)` — consuming; trajectory conveniences `Bool(q)` / `Int(x)` | quantum–classical observation | instrument plus classical result |
> | 3 | `a ⊻= b`, `not!(a)`, `add!(x, ±a)`, mixed forms | action family | process application |
> | 4 | `dual(q)` and bound-view actions | conjugate view and modulation | conjugation by \(F_G\) |
> | 5 | `when(q) do … end` | coherent quantum control | `ctrl` of a witnessed process |
> | 6 | `cases` / `@cases` | classical branching | structured `CasesNode` |
> | 7 | `oracle(f, x)` | Bennett bridge | `Perm` value |
>
> `@cases` accepts a classical selector or an explicit observation expression. A bare quantum register is rejected; write `@cases measure(m)`.
>
> Context portability is:
>
> | Construct | Eager | Exact DM | Tracing | Hardware compilation |
> |---|---:|---:|---:|---:|
> | preparation, actions, `dual`, `when`, `oracle` | ✓ | ✓ | ✓ | ✓ |
> | `measure(q)` | scalar | token | token | token |
> | host `if` / `&&` / `||` on the result | ✓ | ✗ | ✗ | ✗ |
> | whitelisted finite classical SSA | ordinary Julia | ✓ | ✓ | capability checked |
> | `cases` / `@cases` | selected arm | all correlated arms | `CasesNode` | dynamic branch if supported |
> | token-dependent host loop/index/allocation | n/a after scalar measurement | ✗ | ✗ | ✗ |
>
> `DensityMatrixContext` executes channels, not trajectories. For an instrument \(\{\mathcal M_i\}\) and branch channels \(\mathcal E_i\), exact branching denotes
>
> \[
> \rho\longmapsto\sum_i\mathcal E_i(\mathcal M_i(\rho)).
> \]
>
> The executor retains a joint diagonal classical record
>
> \[
> \sum_\gamma|\gamma\rangle\!\langle\gamma|_C\otimes\widetilde\rho_\gamma
> \]
>
> so that repeated use of a token remains correlated. Branch-local quantum ancillae are traced to the common join signature, but classically distinguishable rows are not summed until their distinguishing SSA values are dead.
>
> Scalar density-matrix measurement is available only through an explicit `TrajectoryContext{DensityMatrixContext}`. It samples and normalizes one branch and is not an exact channel execution mode. Completed hardware shot results are ordinary Julia values only after program execution; mid-circuit hardware feedback remains token-plus-`cases`.
>
> Hardware compilation checks classical opcode, width, table, and dynamic-branch capabilities before submission. An unsupported feature is a compile error, never a silent lowering to host retracing or independent shots.

### 8.3 Consequential example edits

The following non-§3.6/§3.8 text must change consistently:

- §7.1’s `&&` teleportation is **Eager/trajectory only**, not DM-portable.
- Exact DM teleportation uses `measure` plus `cases`, or the deferred coherent variant.
- §7.6 replaces both `@cases m` occurrences with `@cases measure(m)`.
- D3 must no longer claim arbitrary Julia indexing or dynamic loop bounds.
- The promise of a descriptive Sturm exception from `if token` must be replaced by Julia’s native `TypeError`.
- CLAUDE.md’s surface row 2 must follow the Tobias F13 ruling.

---

## 9. Risks and alternatives considered

### 9.1 Exact classical records may grow exponentially

Exact channel execution necessarily retains every measurement history that remains distinguishable. No representation can erase that correlation without changing the channel.

Mitigations include SSA liveness, coalescing after last use, sparse assignments, decision diagrams, and symmetry-aware aggregation. These are optimizations; M8 correctness must work without them.

### 9.2 The restricted subset is less permissive than “ordinary Julia”

That restriction is intentional and honest. Full dynamic Julia requires continuation capture or a much larger compiler supporting memory, loops, dispatch, φ nodes, and effects.

The M8 promise should be “ordinary operator spelling over a documented finite token interface,” not “arbitrary Julia.”

### 9.3 Static table lookup can still be large

A table over every value of a wide syndrome has \(2^W\) data whether represented in Julia or hardware. Sturm must not create such a table implicitly. Users may instead compute predicates bitwise or use a problem-specific decoder.

### 9.4 Conservative joins reject useful branch-dependent allocation

Quantum φ nodes could join different arm-local registers of identical type, but ownership, aliasing, hardware mapping, and later consumption would all require a new semantics. M8 should reject this rather than guess.

Stable in-place handles make identical-port joins natural for corrections and syndrome processing.

### 9.5 Host side effects in branch closures

Exact DM and tracing must construct every branch, so ordinary Julia side effects in branch closures occur at construction time, not conditionally at quantum runtime. Portable `cases` bodies should contain Sturm operations and whitelisted SSA construction only.

A complete prohibition on arbitrary helper-function side effects would require source rewriting or effect analysis and is not claimed by this design. Crucially, a token cannot silently drive such a side effect because it cannot become a host `Bool`, index, or loop bound.

### 9.6 Hardware classical capabilities vary

OpenQASM-like targets differ in supported word widths, arithmetic, lookup, nesting, and latency. The IR therefore records explicit classical opcodes and requires capability negotiation. Lowering a table to comparisons is legal only when resource limits permit it.

### 9.7 Affine tokens

Affine tokens simplify exact execution but make legitimate repeated feedback awkward and undermine M11 syndrome processing. They are rejected in favor of explicit cq records.

### 9.8 Immediate branch accumulation

Replacing the cq record by \(\sum_i\rho_i\) immediately is valid only when outcome \(i\) is forgotten. Doing it while a token survives changes subsequent correlated feedback into independent feedback. It is physically wrong.

### 9.9 Staged dynamic lifting

Staged lifting remains useful for interactive experiments and trajectory-only simulators. It may later appear as a separate context with explicit pause/resume semantics. It must not masquerade as `TracingContext`, exact DM, or a compiled-once hardware channel.

### 9.10 Retaining `Bool(q)` tokens

Julia technically permits this, but the convention and conversion costs are substantial. Because idiomatic Julia is a constitutional priority, the recommendation is to move symbolic observation to `measure` and reserve `Bool`/`Int` for actual scalar results. This final spelling remains Tobias’s ruling.