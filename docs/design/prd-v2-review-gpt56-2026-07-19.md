# GPT-5.6-sol xhigh adversarial review — Sturm-PRD-v2 + implementation plan

> Provenance: run 2026-07-19 via `codex exec -m gpt-5.6-sol -c model_reasoning_effort=xhigh -s read-only`
> at the request of Tobias (session 97). 37 findings; triage + bead mapping in
> `worklog/session-97.md`. The 6xdk endianness ruling (F20/F21) was applied same-day.

## Verdict

The core thesis—phase-fixed process values beneath a channel-denoting surface, consuming quantum/classical casts, and Pontryagin views—is sound and worth preserving. The specification is not safe to build past M7, however: M5’s state-dependent `when` witness is unsound, M8 lacks a phase-preserving/effect-typed IR and workable classical-control semantics, and M9’s proposed modular multiplication is not unitary. I recommend an architectural reset of M5’s witness and M8–M11, not a wholesale restart of the project.

## Findings

### F1 — The eager clean-ancilla “witness” is state-dependent, not a process witness

- **Severity:** P0
- **Location:** [PRD §3.5, lines 465–508](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:465); [plan M5, lines 221–235](/home/tobiasosborne/Projects/Sturm.jl/Sturm-v2-IMPLEMENTATION-PLAN.md:221).
- **Claim:** Checking the ancilla’s current \(|1\rangle\)-block norm cannot certify that a `when` body denotes a unitary process.
- **Argument:** For body unitary \(U\) on data \(D\) and ancilla \(A\), the required condition is
  \[
  U(\mathcal H_D\otimes |0\rangle_A)\subseteq \mathcal H_D\otimes |0\rangle_A
  \]
  for every input state, equivalently
  \[
  (I_D\otimes\langle a|)U(I_D\otimes|0\rangle)=0
  \quad\forall a\ne0.
  \]
  Testing the marginal on the current state proves this only for that state. For example, allocate \(a=|0\rangle\), apply CNOT \(r\to a\), then drop \(a\). An eager execution with \(r=|0\rangle\) passes; the same program on \(|+\rangle_r\) entangles and dephases \(r\). Thus program acceptance and denotation depend on runtime input. The current code performs exactly this state test at [src/surface/when.jl:230](/home/tobiasosborne/Projects/Sturm.jl/src/surface/when.jl:230).
- **Consequence:** M5 is not a sound implementation of the stated channel semantics, and M8’s streaming ≡ materialized law must fail for an adversarial body.
- **Fix sketch:** Require a structural certificate—matched compute/uncompute, a certified Bennett `Perm`, or a traced fixed-port unitary proof. A statevector cleanliness assertion may remain as a debug check of a certificate, never as the certificate itself.

### F2 — `UnitaryDAG` has no defined fixed-port or allocation semantics

- **Severity:** P0
- **Location:** [PRD §4.1, lines 823–831](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:823); [PRD §3.9, lines 753–760](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:753); [plan M8, lines 298–308](/home/tobiasosborne/Projects/Sturm.jl/Sturm-v2-IMPLEMENTATION-PLAN.md:298).
- **Claim:** A “Channel-style DAG carrying a unitarity witness” is insufficiently typed to be a process value.
- **Argument:** A process value must denote \(U:\mathcal H_{\rm in}\to\mathcal H_{\rm in}\). Allocation is instead the isometry \(A|\psi\rangle=|\psi\rangle|0\rangle\); deallocation is not itself unitary or CPTP on the enlarged space. Their composite may induce a unitary on surviving ports only when a universally quantified clean-ancilla theorem holds. A Boolean `unitary=true` flag does not encode port equality, ancilla preconditions, or the proof that the coisometry is valid.
- **Consequence:** `ctrl(::UnitaryDAG)`, `adjoint`, composition, hardware lowering, and the M8 streaming/materialized theorem have no defined mathematical domain.
- **Fix sketch:** Separate `ChannelDAG` from an opaque `UnitaryBlock{InPorts,OutPorts}`. Only construct the latter when ports match and every allocation/deallocation pair has a structural clean-ancilla certificate. This part of M8 needs redesign before implementation.

### F3 — Choi-level pass correctness is too weak for DAGs that may later be controlled

- **Severity:** P0
- **Location:** [PRD §2 lowering contract, lines 144–158](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:144); [PRD §4.2–§4.4, lines 843–929](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:843); [plan M8, lines 307–316](/home/tobiasosborne/Projects/Sturm.jl/Sturm-v2-IMPLEMENTATION-PLAN.md:307).
- **Claim:** Channel/Choi equivalence cannot certify a pass over a `UnitaryDAG` that remains a process value.
- **Argument:** \(\mathrm{Ad}_U=\mathrm{Ad}_{e^{i\alpha}U}\), so their Choi matrices are identical. But
  \[
  C(U)=|0\rangle\!\langle0|\otimes I+|1\rangle\!\langle1|\otimes U
  \]
  differs observably from \(C(e^{i\alpha}U)\). A pass that preserves only the Choi matrix may silently add or delete global phase and become wrong when its output is passed to `ctrl`. The required streaming/materialized Choi comparison is blind to precisely this bug class.
- **Consequence:** Reassociation, quaternion fusion, view fusion, synthesis, and future QSVT passes can all be channel-correct yet process-incorrect under M8/M10 coherent control.
- **Fix sketch:** Give unitary-block passes a stronger contract: preserve the phase-fixed \(U(d)\) representative, or return an explicit phase delta. Test them by controlling both pre- and post-pass values and comparing the resulting channel. Channel-only passes may continue using Choi equivalence.

### F4 — “Ordinary Julia arithmetic/indexing” on runtime measurement tokens cannot compile once

- **Severity:** P0
- **Location:** [PRD §3.6, lines 519–539](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:519); [plan M8, lines 303–306](/home/tobiasosborne/Projects/Sturm.jl/Sturm-v2-IMPLEMENTATION-PLAN.md:303).
- **Claim:** A `ClassicalInt` cannot simultaneously be an unknown runtime outcome, flow through arbitrary Julia indexing/loop bounds, and produce one static DAG without a classical compiler IR.
- **Argument:** Arithmetic can be overloaded to construct symbolic expressions. Julia array indexing, `iterate(1:n)`, bounds checks, dispatch on values, allocation sizes, and host branches require concrete runtime values during execution of the tracing closure. Dynamic lifting instead either:
  1. stops execution, obtains the outcome, and resumes/retraces a continuation; or
  2. compiles a restricted classical SSA/CFG with dynamic loops, memory, phi nodes, and quantum operations parameterized by SSA values.
  
  Neither is “ordinary Julia code compiled once” for arbitrary Julia functions. A graph containing dynamic loops is also not literally a DAG.
- **Consequence:** M8 cannot implement the promised wide QROM/MBU path, and the mistake becomes embedded in hardware transport and OpenQASM lowering at M12.
- **Fix sketch:** Choose explicitly between staged dynamic lifting and a restricted classical-control IR. Define supported arithmetic, indexing, memory, loops, and hardware capabilities; reject arbitrary Julia uses outside that subset.

### F5 — Density-matrix scalar branching contradicts exact-channel execution

- **Severity:** P0
- **Location:** [PRD §3.8, lines 600–619](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:600); [teleportation portability claim, lines 1082–1090](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:1082).
- **Claim:** The table permits `if`/`&&` on a measured outcome in `DensityMatrixContext`, while the next paragraph requires DM execution to evolve all instrument branches exactly.
- **Argument:** For instrument maps \(\mathcal M_i(\rho)=P_i\rho P_i\), exact branching denotes
  \[
  \mathcal E(\rho)=\sum_i \mathcal E_i(\mathcal M_i(\rho)).
  \]
  Producing an ordinary `Bool` chooses one \(i\), normalizes that branch, and yields a trajectory. Ordinary Julia `if` can execute only that selected branch; it cannot apply the sum. The existing implementation correctly rejects DM `Bool`, directly contradicting the normative table and the claim that the `&&` teleportation listing is DM-portable.
- **Consequence:** The normative teleportation example cannot have the claimed deterministic DM Choi test, and M8 has no consistent context-portability contract.
- **Fix sketch:** Make DM measurement return a symbolic classical token and require `cases`, just like Tracing. Keep scalar `Bool` only in explicit trajectory/shot mode.

### F6 — `cases` lacks a linear join and persistent classical-record semantics

- **Severity:** P0
- **Location:** [PRD §3.6, lines 519–539](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:519); [PRD §3.8, lines 609–616](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:609); [plan M8, lines 314–316](/home/tobiasosborne/Projects/Sturm.jl/Sturm-v2-IMPLEMENTATION-PLAN.md:314).
- **Claim:** “Trace branch ancillae to a common signature, then block-accumulate” does not define which quantum handles or classical tokens remain live after a branch.
- **Argument:** If one branch consumes a handle and another leaves it live, the post-`cases` Julia binding cannot be assigned a valid linear type. If branches return different registers, the IR needs explicit quantum phi/port mappings. Moreover, a measurement token is classical and copyable: if the same token controls two later `cases`, the executor must retain
  \[
  \sum_i |i\rangle\!\langle i|_C\otimes\rho_i
  \]
  until its last use. Summing quantum branches immediately loses the correlation and makes a second use branch independently.
- **Consequence:** Repeated feed-forward, MBU, syndrome processing, QECC, and channel composition are undefined in M8.
- **Fix sketch:** Specify branch typing: identical live quantum port sets and compatible ownership at every join. Represent live classical records explicitly in the IR/executor, or make tokens affine and force all uses into one structured `cases`.

### F7 — M9’s `QMod` modular multiplication is not a permutation

- **Severity:** P0
- **Location:** [plan M9, lines 324–329](/home/tobiasosborne/Projects/Sturm.jl/Sturm-v2-IMPLEMENTATION-PLAN.md:324); [PRD §7.7, lines 1261–1268](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:1261).
- **Claim:** Embedding \(\mathbb Z_N\) in \(2^{\lceil\log_2N\rceil}\) basis states does not make \(v\mapsto cv\bmod N\) a permutation of the physical Hilbert basis.
- **Argument:** Coprimality makes the map bijective only on \(0,\ldots,N-1\). For \(N=15\), the 4-bit states \(0\) and \(15\) both map to \(0\); the proposed map is many-to-one and cannot be unitary. Additionally, M7’s Bennett bridge constructs the target-accumulating permutation
  \[
  |v\rangle|b\rangle\mapsto|v\rangle|b\oplus f(v)\rangle,
  \]
  not the in-place permutation \(|v\rangle\mapsto|f(v)\rangle\). Dropping the original input would dephase superpositions.
- **Consequence:** The M9 `mulmod!` lowering and therefore the Shor capstone cannot exist as planned.
- **Fix sketch:** Define the full-space permutation
  \[
  v\mapsto\begin{cases}cv\bmod N,&v<N\\v,&v\ge N,\end{cases}
  \]
  and add a distinct in-place-permutation compiler contract, including an inverse or verified permutation table/circuit. The existing `oracle` API is insufficient.

### F8 — `encode(ch, code)::Channel→Channel` does not specify a QECC superchannel

- **Severity:** P0
- **Location:** [PRD §5, line 1003](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:1003); [plan M11, lines 357–364](/home/tobiasosborne/Projects/Sturm.jl/Sturm-v2-IMPLEMENTATION-PLAN.md:357).
- **Claim:** An untyped `Channel → Channel` signature conflates protecting physical noise, encoding a state, and lifting a logical algorithm fault-tolerantly.
- **Argument:** For encoding \(E:L\to P\), recovery \(R:P\to P\), decoding \(D:P\to L\), an effective logical-noise superchannel has type
  \[
  \Theta:\mathrm{Chan}(P,P)\to\mathrm{Chan}(L,L),\qquad
  \Theta(\mathcal N)=D\circ R\circ\mathcal N\circ E.
  \]
  By contrast, lifting an arbitrary logical channel \(\Phi:L\to L\) to a fault-tolerant physical implementation \(\bar\Phi:P\to P\) is not canonical; the code alone does not determine transversal gadgets, magic-state protocols, scheduling, or fault model.
- **Consequence:** P6 cannot be tested or implemented meaningfully in M11, and hardware/noise port types will be wrong.
- **Fix sketch:** Replace the single HOF with typed operations such as `encode_state`, `effective_logical_noise(::Channel{P,P}, code)`, and `fault_tolerant_lift(::LogicalProcess, implementation)`. Model these as superchannels/combs with explicit port types and memory.

### F9 — Future `SU(d)` values repeat the global-phase error v2 was designed to remove

- **Severity:** P0
- **Location:** [PRD §4.1, lines 823–828](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:823).
- **Claim:** `SU(d)` alone cannot be the process-value representation for `QMod{d}` when `ctrl` must preserve global phase.
- **Argument:** Controlled operations distinguish \(U\) from \(e^{i\alpha}U\). A general \(U(d)\) value should be represented by phase plus \(S\in SU(d)\), with the center quotient
  \[
  (S,\phi)\sim(\zeta S,\phi-\arg\zeta),\qquad \zeta^d=1.
  \]
  Keeping only \(S\) discards exactly the phase information required by P4. Fourier, Weyl, and Clifford representatives also have determinant-dependent phases that become observable under control.
- **Consequence:** D6/M12 would reintroduce the same controlled-phase unsoundness that U2 fixes for qubits.
- **Fix sketch:** Specify a `Ud` representation—or `SU(d)+phase` modulo \(\mathbb Z_d\)—and require all register-specific process structures to preserve a definite \(U(d)\) representative.

### F10 — A user control is not required to be disentangled at exit

- **Severity:** P1
- **Location:** [PRD §1.1, lines 84–94](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:84).
- **Claim:** The statement that sound coherent control must “leave control disentangled at exit” is false for Sturm’s user guard.
- **Argument:** A controlled unitary maps
  \[
  (\alpha|0\rangle+\beta|1\rangle)|\psi\rangle
  \mapsto
  \alpha|0\rangle|\psi\rangle+\beta|1\rangle U|\psi\rangle,
  \]
  which is generally entangled. CNOT on \(|+\rangle|0\rangle\) is the simplest counterexample and is explicitly required elsewhere in the PRD. Synchronization results concern control-machine/path workspace disentangling from program data, not the user’s semantic control qubit.
- **Consequence:** The cited theorem is misapplied and contradicts the kickback and Bell-state requirements of M5.
- **Fix sketch:** Say that internal control-flow/path and scratch state must be synchronized and cleaned; the user guard remains a live quantum output and may be entangled.

### F11 — P1 incorrectly says all programs lie in the image of `Ad`

- **Severity:** P1
- **Location:** [PRD §6, lines 1009–1015](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:1009).
- **Claim:** A program containing measurement, discard, reset, or noise is not a composite in the image of the adjoint representation.
- **Argument:** The image of
  \[
  \mathrm{Ad}:U(d)\to\mathrm{CPTP},\qquad U\mapsto(\rho\mapsto U\rho U^\dagger)
  \]
  contains only unitary conjugation channels. Pinching, amplitude damping, partial trace, and classical instruments are CPTP but not in that image.
- **Consequence:** The foundational P1 restatement contradicts the channel/process stratification in §4.4.
- **Fix sketch:** Replace the sentence with: process applications lie in `im(Ad)`; programs lie in the symmetric monoidal category generated by those applications plus preparation, instruments, classical control, and trace.

### F12 — Preparation casts inside `when` are simultaneously forbidden and required

- **Severity:** P1
- **Location:** [PRD §3.5, lines 474–503](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:474); [PRD §3.9, lines 631–639 and 753–760](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:631); [plan M5, lines 221–227](/home/tobiasosborne/Projects/Sturm.jl/Sturm-v2-IMPLEMENTATION-PLAN.md:221).
- **Claim:** Guardrail 1 bans “any cast”, yet allocation inside `when` is permitted and there is no bare allocation form.
- **Argument:** `QBool(false)` is both the only surface spelling of a fresh canonical ancilla and a preparation cast. Arbitrary `QBool(p,φ)` is worse: preparation is a channel/isometry with no canonical controlled implementation because different unitary extensions differ by phase under outer control.
- **Consequence:** The legal syntax for clean scratch in M5/M8 is undefined, and implementations will inconsistently bypass the control stack.
- **Fix sketch:** Permit only canonical fresh-\(|0\rangle\) allocation inside `when`, either through an explicitly derived scratch form or a tightly specified exception for `QBool(false)`. Ban arbitrary literals inside `when` unless lowered as part of a certified compute/uncompute unitary.

### F13 — `Bool`/`Int` tokens fight Julia constructor and branch semantics

- **Severity:** P1
- **Location:** [PRD §3.6, lines 523–537](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:523); [plan M8, lines 303–306](/home/tobiasosborne/Projects/Sturm.jl/Sturm-v2-IMPLEMENTATION-PLAN.md:303).
- **Claim:** `Bool(q)` returning `ClassicalBit` and `Int(x)` returning `ClassicalInt` violates normal constructor expectations, while the promised descriptive `if token` error is not dispatchable.
- **Argument:** Julia lowers `if x` and `x && y` to boolean control-flow checks; it does not call an overloadable `Bool(x)` conversion at that point. A non-`Bool` token receives Julia’s native non-boolean `TypeError`, not a Sturm-defined explanatory exception. Separately, `convert(Bool,q)` must return an actual `Bool` for typed fields/arrays, so it cannot share the token behavior.
- **Consequence:** The specified error UX is unimplementable without source/IR rewriting, and cast return types become context-dependent.
- **Fix sketch:** Accept/document Julia’s native `TypeError`, or trace/rewrite a containing macro. Specify explicit casts, implicit `convert`, and token-producing observations separately.

### F14 — Bound-view `+=` necessarily leaks mutation into ordinary `+`

- **Severity:** P1
- **Location:** [PRD §3.3, lines 228–238 and 302–307](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:228); [PRD §3.4, lines 397–424](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:397).
- **Claim:** The claim that mutating view operations “can never leak into generic value code” is false.
- **Argument:** Julia implements `x̂ += a` as `x̂ = +(x̂,a)`. Therefore `+` itself must mutate the underlying quantum register. Direct `+(x̂,a)`, higher-order `map(+, ...)`, a reduction, or generic code accepting the view all acquire side effects even if `DualView` is not `<:Number`. The same issue exists for bare `xor(a,b)`, although the PRD acknowledges that case more clearly.
- **Consequence:** D11 fixes parsing but not the deeper host-language semantic trap; library-generic code can mutate through a supposedly value-like operator.
- **Fix sketch:** Prefer explicit `modulate!`/`translate!`, or state normatively that every `+` method on a view is effectful and exclude views from all generic APIs. The current “cannot leak” claim must go.

### F15 — “Registers are numeric types” is not a workable Julia contract as written

- **Severity:** P1
- **Location:** [PRD §3.1, lines 163–168](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:163); [PRD P8/P9, lines 1029–1035](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:1029).
- **Claim:** The spec does not say whether registers subtype `Number`/`Integer`; either choice breaks part of P9.
- **Argument:** Without nominal subtyping, methods such as `f(x::Integer)` do not dispatch on `QInt`. With `QInt <: Integer`, Julia’s numeric ecosystem assumes non-effectful arithmetic, usable equality/hash, conversions, and concrete scalar comparisons. Quantum `<` cannot honestly return a classical `Bool` without measurement; a coherent comparator returns a `QBool`, which cannot drive ordinary Julia `if`.
- **Consequence:** “Generic arithmetic and comparison code rides P8/P9” is not a decidable promise and will fail unpredictably in M7–M10.
- **Fix sketch:** Call registers “number-like handles”, not numeric types, and publish the exact supported operator/trait interface. Specify coherent comparison results and route branch-heavy generic functions through `oracle`.

### F16 — The planned cast path cannot be type-stable across contexts

- **Severity:** P1
- **Location:** [plan cross-cutting performance, lines 385–389](/home/tobiasosborne/Projects/Sturm.jl/Sturm-v2-IMPLEMENTATION-PLAN.md:385); [PRD context table, lines 600–607](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:600).
- **Claim:** The `@code_warntype` goal conflicts with handles that erase context type while casts return `Bool`, errors, or tokens depending on runtime context.
- **Argument:** The implemented `QBool` stores `ctx::AbstractContext` at [src/types/qbool.jl:67](/home/tobiasosborne/Projects/Sturm.jl/src/types/qbool.jl:67), explicitly forcing dynamic dispatch. M8 would make the cast return type context-dependent as well. Julia can hide a context parameter from surface spelling while retaining it in the concrete type: signatures `QInt{W}` can still match `QInt{W,C}` as a partial UnionAll.
- **Consequence:** Cast, action, and tracing paths acquire inference failures exactly where M8 adds substantially more dispatch.
- **Fix sketch:** Parameterize handles by context/mode internally—`QBool{C}`, `QInt{W,C}`—while preserving ergonomic constructors and partially parameterized method signatures.

### F17 — Return-value inspection is not sufficient ownership/escape analysis in Julia

- **Severity:** P1
- **Location:** [PRD §3.9, lines 642–649 and 761–765](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:642).
- **Claim:** The spec does not cover handles escaping through mutable containers, closures, tasks, globals, custom structs, or opaque query values.
- **Argument:** A region may execute `box[] = q; nothing`, after which return-value-based cleanup traces `q` and leaves a dangling alias in `box`. A returned custom `struct` containing a handle has the same problem unless every container participates in an ownership protocol. `OracleQuery` is explicitly bindable and borrows its input, but its escape semantics are not specified. Current code recognizes only selected handle types and tuples at [src/context/regions.jl:53](/home/tobiasosborne/Projects/Sturm.jl/src/context/regions.jl:53).
- **Consequence:** P1 channel signatures and D2 ownership transfers are incomplete; users can silently return dead quantum resources in M8 HOFs.
- **Fix sketch:** Introduce an explicit, extensible quantum-ownership traversal/transfer protocol or require `own!/return_quantum` at region boundaries. Reject mutation-based escape in strict mode where detectable.

### F18 — “Every function is a channel” lacks a channel-reification API and contradicts plain helper semantics

- **Severity:** P1
- **Location:** [PRD §3.9, lines 702–716](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:702); [PRD §5, line 1003](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:1003); [plan M8](/home/tobiasosborne/Projects/Sturm.jl/Sturm-v2-IMPLEMENTATION-PLAN.md:298).
- **Claim:** Plain Julia helper calls explicitly have no region boundary, while QECC and passes require first-class typed `Channel` values that v2 never normatively specifies how to obtain.
- **Argument:** A Julia `Function` does not carry quantum input/output arity, width, ownership, or a phase representative. `trace(f, signature)` is mentioned in examples and inherited prose, but its v2 signature and effect rules are absent. Therefore “functions are channels” is true only for designated reification/region boundaries, not for every Julia call.
- **Consequence:** M8’s `Channel` construction and M11’s `encode(ch,code)` cannot be implemented from the v2 text alone.
- **Fix sketch:** Narrow P1 to “reified quantum functions denote channels” and specify the full `trace`/invocation API, typed ports, return ownership traversal, and classical-output representation.

### F19 — CZ symmetry is not a theorem of Pontryagin duality alone

- **Severity:** P1
- **Location:** [PRD §3.3, lines 252–277](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:252); [PRD §3.4, lines 364–381](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:364).
- **Claim:** The canonical pairing \(G\times\widehat G\to U(1)\) is evaluative, not intrinsically symmetric.
- **Argument:** Given a chosen self-duality \(j:G\to\widehat G\), the induced bicharacter is \(B(x,y)=j(y)(x)\). Symmetry requires the additional law \(B(x,y)=B(y,x)\); it does not follow from Pontryagin duality. It holds for the pinned cyclic pairing \(B(x,y)=\omega^{xy}\). Also, `QInt` supports the additive group \(\mathbb Z_{2^W}\) and bitwise XOR group \((\mathbb Z_2)^W\), so there is not one unique “register group” underlying every action.
- **Consequence:** The P7 generalization and the claimed universal CZ-symmetry test are under-specified for user-defined finite abelian registers.
- **Fix sketch:** Make the dual trait carry a selected nondegenerate bicharacter and state whether it is symmetric. Index each action family by its group structure.

### F20 — The Bernstein–Vazirani example is bit-reversed

- **Severity:** P1
- **Location:** [PRD §7.5, lines 1202–1211](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:1202).
- **Claim:** `evalpoly(2, bits)` interprets `bits[1]` as the least-significant coefficient, while Sturm pins `x[1]` as the MSB.
- **Argument:** After per-wire dual measurement, `bits = [s_{N-1},\ldots,s_0]`. `evalpoly(2,bits)` returns \(\sum_{j=1}^N bits[j]2^{j-1}\), i.e. the bit reversal of \(s\). The wire-1=MSB convention should win because it is kernel-wide. Existing tests use only palindromic 3-bit secrets \(000,010,101\), as visible at [test/test_m7_bennett.jl:223](/home/tobiasosborne/Projects/Sturm.jl/test/test_m7_bennett.jl:223), so they cannot expose the bug.
- **Consequence:** The normative example fails for secrets such as \(001,011,100,110\).
- **Fix sketch:** Use `evalpoly(2, reverse(bits))` or a left fold `n = (n << 1) | bit`. Add exhaustive secrets for small \(N\), including a non-palindrome.

### F21 — Shor controls the modular powers from the wrong end

- **Severity:** P1
- **Location:** [PRD §7.7, lines 1258–1269](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:1258).
- **Claim:** With wire 1 = MSB, `k[1]` is controlled by \(a\) rather than \(a^{2^{2W-1}}\).
- **Argument:** For numerical register value
  \[
  k=\sum_{j=1}^{2W}k_j2^{2W-j},
  \]
  modular exponentiation needs multiplication by \(a^{2^{2W-j}}\) controlled on wire \(j\). The listing instead assigns \(a^{2^{j-1}}\), computing \(a^{\operatorname{bitreverse}(k)}\). Bit reversal is not an automorphism of the cyclic additive index used by the QFT, so the usual period peaks are destroyed.
- **Consequence:** M9’s Shor acceptance test can pass only accidentally or through matched test mistakes.
- **Fix sketch:** Reverse the controlled-wire order or initialize each factor as `powermod(a, 1 << (2W-j), N)`.

### F22 — `shor_order` does not return the order from one sample

- **Severity:** P1
- **Location:** [PRD §7.7, lines 1271–1275](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:1271); [plan M9, lines 333–336](/home/tobiasosborne/Projects/Sturm.jl/Sturm-v2-IMPLEMENTATION-PLAN.md:333).
- **Claim:** A single continued-fraction denominator is only a candidate divisor, not necessarily the order.
- **Argument:** A phase sample approximates \(s/r\). After reduction, its denominator is \(r/\gcd(s,r)\); \(s=0\) returns 1, and other samples may yield proper divisors. Standard order finding repeats, verifies \(a^{r'}\equiv1\pmod N\), and combines candidates, often by LCM. The example also omits the precondition \(\gcd(a,N)=1\).
- **Consequence:** The normative return contract is false and seeded small-\(N\) tests are liable to overfit lucky samples.
- **Fix sketch:** Rename it `order_candidate` or implement repetition, modular verification, and LCM accumulation with an explicit failure result.

### F23 — `Int(x)` cannot represent unconstrained `QInt{W}`

- **Severity:** P1
- **Location:** [PRD §3.1–§3.2, lines 165–185](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:165); [PRD §7.7, line 1259](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:1259).
- **Claim:** No width bound is specified even though Julia `Int` is machine-sized.
- **Argument:** For \(W\ge\texttt{Sys.WORD_SIZE}\), values in \(\mathbb Z_{2^W}\) do not fit in `Int`; shifts such as `1 << W` overflow or wrap. Shor doubles the width immediately with `QInt{2W}`.
- **Consequence:** Large arithmetic, hardware registers, and generic constructors become platform-dependent.
- **Fix sketch:** Either normatively bound `QInt{W}` measurement to machine width, return `BigInt`/a fixed-width bit-vector for large \(W\), or introduce a separate consuming cast spelling for wide results. Reject \(W\le0\) as well.

### F24 — `QMod{N}` is type-unstable when `N` is an ordinary runtime argument

- **Severity:** P1
- **Location:** [PRD §7.7, lines 1258–1262](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:1258).
- **Claim:** `shor_order(a, N, ::Val{W})` constructs `QMod{N}` even though `N` is not a static parameter.
- **Argument:** Julia can construct a runtime-applied parametric type, but inference cannot generally know the resulting concrete type, and many distinct runtime moduli cause specialization/cache pressure. This conflicts with the plan’s type-stability goals.
- **Consequence:** M9’s capstone acquires dynamic dispatch throughout modular arithmetic.
- **Fix sketch:** Pass `N` as `Val{N}` if static specialization is intended, or make modulus a runtime field while reserving type parameters for representation class/width.

### F25 — The claimed 15-wire Choi capacity ignores density-matrix scaling

- **Severity:** P1
- **Location:** [PRD §3.8, lines 617–619](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:617); [plan risk 4, lines 432–433](/home/tobiasosborne/Projects/Sturm.jl/Sturm-v2-IMPLEMENTATION-PLAN.md:432).
- **Claim:** A 30-qubit backend cap does not make a 15-wire density-matrix Choi test practical.
- **Argument:** A \(W\)-wire Choi state uses \(2W\) qubits, and its dense density matrix has \(2^{4W}\) complex entries. At \(W=15\), that is \(2^{60}\) complex numbers, about \(2^{64}\) bytes—16 EiB with `ComplexF64`.
- **Consequence:** The M3/M8 test strategy and risk register badly overstate feasible law-test sizes.
- **Fix sketch:** Set the cap from a memory budget, not the pure-state qubit ceiling. Use small exact Chois, randomized reference-assisted tests, stabilizer methods, tensor networks, or local process tomography for larger channels.

### F26 — Process equality confuses semantic `≈` with Julia `==`

- **Severity:** P1
- **Location:** [PRD §4.1–§4.2, lines 794–842](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:794); [plan M1, lines 111–135](/home/tobiasosborne/Projects/Sturm.jl/Sturm-v2-IMPLEMENTATION-PLAN.md:111).
- **Claim:** The text simultaneously requires quotient equality, approximate float comparison, and `==` law tests.
- **Argument:** Tolerance-based equality is not transitive and therefore must not implement Julia `==`/`hash`. Exact structural equality cannot identify drifted double-cover representatives. The current implementation correctly keeps `==` structural and uses `≈`, contradicting the normative examples.
- **Consequence:** Required tests are ambiguous, and future dictionaries/caches of process values could become invalid if the plan’s approximate `==` is implemented.
- **Fix sketch:** Reserve `==` for exact structural/canonical representation equality and use `isapprox` or `same_process` for quotient-semantic comparison. Rewrite every float-valued kernel law accordingly.

### F27 — The literal pole-degeneracy `==` test compares handles, not states

- **Severity:** P1
- **Location:** [PRD D1, lines 1352–1356](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:1352); [plan M3, lines 175–178](/home/tobiasosborne/Projects/Sturm.jl/Sturm-v2-IMPLEMENTATION-PLAN.md:175).
- **Claim:** `QBool(1,φ) == QBool(true)` is not a valid state equality test.
- **Argument:** The two calls allocate distinct physical registers and therefore distinct handles. Defining handle `==` by current state would require context inspection, fail under entanglement, and destroy identity semantics. Only the prepared density operators/channels are equal up to global phase.
- **Consequence:** The normative required test is false under the otherwise correct handle model.
- **Fix sketch:** Compare the prepared one-wire density matrices or preparation-channel Chois, while asserting that the handles themselves are distinct.

### F28 — Process values need deep immutability or freezing

- **Severity:** P2
- **Location:** [PRD §4.1, lines 778–824](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:778); [plan M1 `Perm`, lines 117–121](/home/tobiasosborne/Projects/Sturm.jl/Sturm-v2-IMPLEMENTATION-PLAN.md:117).
- **Claim:** “Definite representative—data” is incompatible with mutable instruction vectors or mutable DAG storage.
- **Argument:** An immutable Julia struct containing mutable `Vector`s is not deeply immutable. Mutation after a `Perm`/DAG has been embedded in a trace can invalidate equality, cached lowerings, unitarity witnesses, and pass results.
- **Consequence:** M8 caching and concurrent compilation become unsound even if the mathematical representation is correct.
- **Fix sketch:** Freeze process values on construction using tuples/persistent storage or defensive copies with inaccessible mutation. Keep mutable builders distinct from frozen process values.

### F29 — Nested controls need alias rules among controls, not just control-vs-target checks

- **Severity:** P1
- **Location:** [PRD §3.5, lines 474–482](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:474); [PRD §4.5, lines 966–969](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:966).
- **Claim:** `ctrl(ctrl(g))` assumes distinct control subsystems, but the surface permits nesting the same parent wire or its dual view.
- **Argument:** `when(q) do when(q) ... end end` should algebraically reduce to one projector, not a two-control Toffoli. `when(q)` nested with `when(dual(q))` is worse: the two projectors do not commute and cannot be represented by a flat control count. Target-only alias checks do not state this restriction.
- **Consequence:** M5/M8 may build process values with duplicated physical wires or mis-lower incompatible-basis controls.
- **Fix sketch:** Resolve every control through views, require pairwise-disjoint control parents, and issue a dedicated error for repeated or conjugate aliases.

### F30 — `@cases m` creates a second measurement syntax

- **Severity:** P1
- **Location:** [PRD surface table, lines 582–590](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:582); [PRD §7.6, lines 1214–1227](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:1214).
- **Claim:** The table says measurement is exclusively `Bool(q)`/`Int(x)` and `cases` branches on classical outcomes, but the normative injection example says `@cases m` itself measures and consumes a quantum register.
- **Argument:** If `@cases` accepts a register, measurement is no longer only a cast. If it accepts a token, the example must pass `Bool(m)`. This choice also changes DM and Tracing semantics materially.
- **Consequence:** M8’s macro API, token lifetime, and P2 boundary claim are ambiguous.
- **Fix sketch:** Prefer `@cases Bool(m) begin ... end`, or declare register-accepting `@cases` to be syntactic sugar that expands visibly to the consuming cast plus `cases`.

### F31 — v2 is not self-contained and imports contradictory v0.1 semantics wholesale

- **Severity:** P1
- **Location:** [PRD introduction, lines 26–29](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:26).
- **Claim:** “Everything not explicitly changed carries over” is not a safe normative incorporation rule.
- **Argument:** v0.1 contains sampled DM measurement, task-local context propagation, gate-named DAG nodes, and different tracing/cases assumptions; several are changed only implicitly elsewhere in v2. A reader cannot mechanically decide which inherited clauses remain normative.
- **Consequence:** M8–M12 implementers can satisfy different internally plausible specifications.
- **Fix sketch:** Consolidate the retained Channel/Tracing/QECC/hardware contracts into v2 and make v0.1 purely historical. At minimum, enumerate exact inherited sections and explicit overrides.

### F32 — P7 overclaims CV and anyons as ordinary instances

- **Severity:** P1
- **Location:** [PRD P7, lines 1024–1028](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:1024); [PRD §4.1, lines 825–828](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:825).
- **Claim:** The current tensor/control/trace/register interface is not dimension-parametric enough to make CV and anyons mere instances.
- **Argument:** A symplectic-plus-displacement value represents only Gaussian CV processes; controlling one with a qubit is generally non-Gaussian. CV also lacks finite normalized Choi states. Anyonic fusion spaces do not generally factor as per-particle tensor products, and partial trace/control must respect superselection sectors and braided monoidal structure. A braid word alone does not provide the ordinary-register `⊗`, allocation, and control laws assumed here.
- **Consequence:** M12 would require category- and backend-level extensions despite P7 claiming otherwise.
- **Fix sketch:** Narrow v2’s proved scope to finite-dimensional abelian-label registers. State CV/anyons as research extensions requiring new tensor, sector, measurement, and control traits.

### F33 — The Stinespring fallback omits the actual dilation contract

- **Severity:** P2
- **Location:** [PRD §4.3, lines 913–918](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:913); [plan M11, lines 357–364](/home/tobiasosborne/Projects/Sturm.jl/Sturm-v2-IMPLEMENTATION-PLAN.md:357).
- **Claim:** “Allocate environment, apply dilated process value” does not specify how a Kraus family becomes a phase-fixed unitary value.
- **Argument:** Given Kraus operators \(K_i\), the canonical part is the isometry
  \[
  V|\psi\rangle=\sum_i K_i|\psi\rangle|i\rangle.
  \]
  Extending \(V\) to a unitary requires padding the environment and choosing a nonunique orthonormal completion. That completion must remain internal; controlling it would expose an arbitrary choice.
- **Consequence:** M11 has no deterministic numerical construction, resource bound, or interaction with the process/channel stratification.
- **Fix sketch:** Specify Kraus-rank padding, isometry synthesis, unitary completion tolerances, environment ownership, and a rule that the dilation is an execution artifact—not a controllable representative of the original channel.

### F34 — The implementation plan schedules proof and semantic decisions too late

- **Severity:** P2
- **Location:** [PRD §3.7, lines 566–575](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:566); [plan M9, lines 330–336](/home/tobiasosborne/Projects/Sturm.jl/Sturm-v2-IMPLEMENTATION-PLAN.md:330); [plan dependency claim, lines 417–418](/home/tobiasosborne/Projects/Sturm.jl/Sturm-v2-IMPLEMENTATION-PLAN.md:417).
- **Claim:** A proof mandated “before v2 implementation begins” is deferred to M9, and M8 is declared parallelizable with M7 based only on file overlap.
- **Argument:** The universality/adaptivity proof constrains `cases` and literals, so it should precede the M8 IR. M8 also needs the traced semantics of M7 `OracleQuery`/`Perm`, control-aware strategy behavior, and borrow ownership; semantic dependencies exist even if files differ.
- **Consequence:** M8 may harden around assumptions that M7/M9 later invalidate.
- **Fix sketch:** Freeze M8 work until F1–F9 are resolved and the universality note lands. Split M8 into classical/effect IR, certified unitary blocks, execution semantics, then optimization passes.

### F35 — The plan and risk register are materially stale

- **Severity:** P2
- **Location:** [plan header, lines 3–6](/home/tobiasosborne/Projects/Sturm.jl/Sturm-v2-IMPLEMENTATION-PLAN.md:3); [plan bead map, lines 399–415](/home/tobiasosborne/Projects/Sturm.jl/Sturm-v2-IMPLEMENTATION-PLAN.md:399); [plan risk register, lines 422–436](/home/tobiasosborne/Projects/Sturm.jl/Sturm-v2-IMPLEMENTATION-PLAN.md:422).
- **Claim:** The plan says D14 is open and M0–M7 are unstarted even though D14 is resolved and M0–M7 exist.
- **Argument:** More importantly, the risk register omits the state-dependent witness, phase-sensitive pass correctness, classical SSA/CFG requirement, branch joins, and padded-space modular permutation.
- **Consequence:** It is not currently usable as the authoritative M8–M12 execution plan.
- **Fix sketch:** Rebaseline the plan after this review, mark actual milestone state, and promote the P0 issues above into explicit research/design gates.

### F36 — Weak-dependency activation is absent from the normative examples

- **Severity:** P2
- **Location:** [PRD §7.4–§7.5, lines 1152–1211](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:1152); [plan dependency rule, lines 48–50](/home/tobiasosborne/Projects/Sturm.jl/Sturm-v2-IMPLEMENTATION-PLAN.md:48).
- **Claim:** The shipped Bennett integration is a package extension, but the verbatim examples do not load Bennett.
- **Argument:** With the current `[weakdeps]/[extensions]` design at [Project.toml:7](/home/tobiasosborne/Projects/Sturm.jl/Project.toml:7), `using Sturm` alone does not activate `SturmBennettExt`; users must also load Bennett. The extension architecture itself is appropriate, but it changes example preconditions.
- **Consequence:** The “examples execute verbatim” rule depends on an unstated test harness import and fails in an ordinary Sturm-only session.
- **Fix sketch:** Add `using Bennett` to oracle examples/documentation or make Bennett a hard dependency. Keep the extension if optional compilation is intentional.

### F37 — D6 applies odd/even Weyl complications too broadly to `dual`

- **Severity:** P2
- **Location:** [PRD D6, lines 1449–1457](/home/tobiasosborne/Projects/Sturm.jl/Sturm-PRD-v2.md:1449); [plan risk 3, lines 428–431](/home/tobiasosborne/Projects/Sturm.jl/Sturm-v2-IMPLEMENTATION-PLAN.md:428).
- **Claim:** The cited \(2^{-1}\bmod d\) and quadratic Gauss-sum complications do not obstruct the basic Fourier dual of \(\mathbb Z_d\).
- **Argument:** For every \(d\),
  \[
  F_d|x\rangle=d^{-1/2}\sum_k e^{2\pi ikx/d}|k\rangle
  \]
  exists uniformly and interchanges cyclic shift and clock operators up to the pinned sign. Odd/even complications arise in discrete Wigner conventions, quadratic Clifford/metaplectic phases, and some displacement normalizations—not in the existence of `dual(::QMod{d})` itself.
- **Consequence:** D6 may unnecessarily delay the simple cyclic Fourier view while still failing to specify the harder Clifford structure separately.
- **Fix sketch:** Split D6 into a uniform cyclic-dual milestone and a later parity-sensitive Weyl/Clifford/metaplectic milestone.

## Non-findings

- The boundary algebra is sound when the intermediate classical outcome is internal: \(\mathrm{qc}\circ\mathrm{cq}=\mathrm{id}\), while reprepare-after-measure gives \(\rho\mapsto\sum_i P_i\rho P_i\).
- The U2 representation itself is sound: \((q,\phi)\sim(-q,\phi+\pi)\) represents the same \(U(2)\) element, while \(+I\) and \(-I\) remain distinct process values. The implementation’s choice to use semantic `≈` rather than approximate `==` is the right repair.
- `ctrl(g\circ h)=ctrl(g)\circ ctrl(h)`, adjoint compatibility, nested control on distinct subsystems, and the stated reassociation identity are mathematically correct for phase-fixed process values.
- `ctrl(Perm)` is correctly closed: controlling every MCX in a reversible generator sequence implements control of the composite permutation by homomorphism.
- The distinction between \(F^2=\) parity as a process and `dual(dual(x)) === x` as the canonical double-dual view is coherent.
- The translation/modulation correction is sound: `add!` is a translation, while mutation through the dual view is a modulation. The QInt register dual \(\mathbb Z_{2^W}\) is genuinely different from the per-wire \((\mathbb Z_2)^W\) dual.
- Excluding measurement-based uncompute beneath coherent control is correct. Channel-equivalent implementations are not interchangeable under `ctrl`.
- Silent scope-exit trace is a valid channel denotation, and trace timing is invisible to later operations on surviving systems. The distinction between partial trace and reset is also correct.
- The teleportation and S/T injection circuits are physically correct, modulo the separate DM/`cases` semantic problems above.
- Deutsch–Jozsa’s use of the cyclic QFT is sound specifically because only the zero Fourier component is inspected.
- The weakdep/package-extension architecture used for Bennett is Julia-idiomatic; the finding concerns activation/documentation, not the mechanism itself.