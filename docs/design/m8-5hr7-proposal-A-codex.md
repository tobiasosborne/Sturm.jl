# Sturm.jl M8 Design Gate: Typed Channel IR, Certified Unitary Blocks, and Phase-Exact Passes

**Bead:** `5hr7`  
**Status:** Independent design proposal  
**Scope:** F1, F2, and F3 from `docs/design/prd-v2-review-gpt56-2026-07-19.md`  
**Repository changes:** None

## Decision summary

M8 should not implement a `Channel` DAG with a `unitary=true` flag. It should introduce two disjoint semantic types:

- `ChannelDAG{InPorts,OutPorts}` represents general typed channels and is **not** a `ProcessValue`.
- `UnitaryBlock{Ports,Certificate} <: ProcessValue` is an opaque, fixed-boundary endomorphism obtained only by a trusted structural sealer.

`UnitaryBlock` deliberately has one boundary signature rather than independent input and output signatures. This is stronger than `UnitaryBlock{InPorts,OutPorts}`: a controllable process value must be an endomorphism on the same ordered physical boundary resources. General isometries, port replacement, preparation, measurement, discard, and classical outputs remain `ChannelDAG`s.

A clean-ancilla certificate proves the universally quantified invariant

\[
(I-\iota\iota^\dagger)\,W\,\iota=0,
\qquad
\iota|\psi\rangle=|\psi\rangle_S|0\cdots0\rangle_A ,
\tag{1}
\]

where \(W\) is the phase-fixed unitary program on surviving ports \(S\) and local ancillas \(A\). The current Eager \(|1\rangle\)-marginal check remains useful only as a debug assertion against backend or lowering defects. It is not evidence for (1).

Passes are split by semantic domain. A channel pass preserves a CPTP map and may be tested by Choi comparison. A unitary-block pass must preserve the chosen \(U(d)\) representative, not merely its adjoint channel. It either proves \(U'=U\), or proves an explicit phase delta \(U'=e^{i\delta}U\) and reattaches \(e^{-i\delta}\) before it can return another `UnitaryBlock`. Every unitary pass is tested both directly and after `ctrl`.

This preserves the constitution’s three load-bearing constraints:

- physics, not input-specific observations, determines validity (`CLAUDE.md:61-66`);
- \(U(2)\) representatives retain observable phase until `Ad` (`CLAUDE.md:161-186`, `src/orkan/ad.jl:5-9`);
- `ctrl` remains the sole controlled-construction choke point (`CLAUDE.md:167-173`, `src/kernel/ctrl.jl:13-27`).

---

## 1. Type design

### 1.1 Typed ports

The IR needs graph-local port identities distinct from runtime `WireID`s. A `WireID` identifies a live resource in one execution context (`src/types/wire.jl:21-37`); a `PortID` identifies an SSA edge or local slot in a reusable graph.

A concrete sketch is:

```julia
struct PortID
    id::Int
end

abstract type AbstractPortSchema end
abstract type QuantumSchema <: AbstractPortSchema end

"Runtime-width homogeneous qubit boundary; width is data, not a type explosion."
struct QubitPorts <: QuantumSchema
    n::Int
end

"Future finite-dimensional homogeneous ports."
struct QuditPorts{D} <: QuantumSchema
    n::Int
end

"Quantum/classical product signature for measurements and cases."
struct MixedPorts <: AbstractPortSchema
    atoms::Tuple  # immutable QuantumPort/ClassicalPort descriptors
end

struct PortList{S<:AbstractPortSchema}
    schema::S
    ids::Tuple{Vararg{PortID}}
end
```

Constructors must validate that `ids` and `schema` have the same arity and dimensions. Width remains runtime data for large `Perm` and oracle blocks, matching the existing vector application seam (`src/orkan/ad.jl:365-388`) and avoiding a distinct Julia specialization for every oracle width.

A node carries typed incoming and outgoing edges:

```julia
abstract type AbstractIRNode end

struct ApplyNode{I<:Tuple,O<:Tuple,V<:ProcessValue} <: AbstractIRNode
    inputs::I
    outputs::O
    value::V
end

struct AllocateZeroNode{O<:Tuple} <: AbstractIRNode
    outputs::O
end

struct DiscardNode{I<:Tuple} <: AbstractIRNode
    inputs::I
end

struct InstrumentNode{I<:Tuple,O<:Tuple} <: AbstractIRNode
    inputs::I
    outputs::O
    instrument::Symbol
end

struct CasesNode{I<:Tuple,O<:Tuple} <: AbstractIRNode
    inputs::I
    outputs::O
    branches::Tuple
end
```

Unitary mutation may keep the same source handle at the surface, but the trace should still version it as input and output SSA edges. A separate resource-lineage identifier records that both versions belong to the same physical boundary resource. That is how the sealer distinguishes “same handle after a unitary” from “input discarded and a same-shaped fresh output returned.”

### 1.2 Immutable storage

Frozen IR and process values must be deeply immutable. An immutable Julia struct containing a mutable `Vector` is not sufficient; review F28 correctly notes that later mutation would invalidate certificates, equality, caching, and pass results (`docs/design/prd-v2-review-gpt56-2026-07-19.md:312-319`).

A dependency-free representation can use an immutable chunked sequence:

```julia
struct FrozenSeq{T}
    chunks::Tuple{Vararg{Tuple{Vararg{T}}}}
    length::Int
end
```

Mutable `Vector`-backed builders are permitted during tracing and pass construction. Freezing copies into immutable nodes and then discards the builder.

This requires one M8 prerequisite for the existing reversible corner:

```julia
struct MCX
    controls::Tuple{Vararg{Int}}
    target::Int
end

struct Perm <: ProcessValue
    n::Int
    gates::Tuple{Vararg{MCX}}
end
```

Public constructors may continue accepting vectors and defensively copy them into tuples. Iteration-based denotation and emission remain unchanged. The current fields are mutable vectors (`src/kernel/perm.jl:36-52`), so sealing a block that embeds the current representation without copying would be unsound.

### 1.3 `ChannelDAG`

```julia
struct ChannelDAG{
    I<:AbstractPortSchema,
    O<:AbstractPortSchema,
}
    inputs::PortList{I}
    outputs::PortList{O}
    nodes::FrozenSeq{AbstractIRNode}
end
```

Invariants:

1. Every node consumes existing input edges and creates fresh output edges.
2. Each edge has exactly one producer.
3. Quantum resource ownership is linear; classical edges may be copied according to the later classical-IR contract.
4. The declared outputs are live edges after the last node.
5. Allocation changes the quantum port signature by an isometry.
6. Discard changes it by partial trace.
7. Measurement, classical records, `cases`, noise, and reset remain channel nodes.
8. `ChannelDAG` is not a subtype of `ProcessValue`.
9. There is no `ctrl(::ChannelDAG)` method.

This is the mechanical form of PRD §4.4: control is undefined on channel equivalence classes because those classes have already quotiented the phase needed by control. Bădescu–Panangaden’s controlled-phase counterexample states exactly this obstruction (`docs/physics/badescu_panangaden_quantum_alternation.md:82-104`).

### 1.4 `UnitaryBlock`

A unitary block contains an execution program distinct from channel nodes:

```julia
abstract type AbstractUnitaryInstr end

struct UApply{V<:ProcessValue} <: AbstractUnitaryInstr
    value::V
    ports::Tuple{Vararg{PortID}}
end

struct UAllocateZero <: AbstractUnitaryInstr
    ports::Tuple{Vararg{PortID}}
end

struct UReleaseZero <: AbstractUnitaryInstr
    ports::Tuple{Vararg{PortID}}
    proof_index::Int
end

abstract type UnitaryCertificate end

struct UnitaryBlock{
    P<:QuantumSchema,
    C<:UnitaryCertificate,
} <: ProcessValue
    boundary::PortList{P}
    program::FrozenSeq{AbstractUnitaryInstr}
    certificate::C

    # Only the structural sealer may call this.
    global _sealed_unitary_block(boundary, program, certificate) =
        new{typeof(boundary.schema),typeof(certificate)}(
            boundary, program, certificate)
end
```

The sketch is intentionally `UnitaryBlock{Ports,Certificate}`, not `UnitaryBlock{InPorts,OutPorts}`. Its invariants are:

1. Its input and output boundary have the same schema, ordering, and resource lineage.
2. Boundary ports are all quantum.
3. No boundary port is allocated, discarded, measured, replaced, or returned under a new identity.
4. All local ports are canonical-\(|0\rangle\) allocations paired with certified zero releases.
5. All executable leaves are frozen, phase-fixed process values.
6. Every leaf is control-lowerable, either directly or through an exact expansion into control-lowerable leaves.
7. The certificate is tied to the exact frozen program.
8. No public constructor can mint the value.

A graph that maps equal-dimensional but different physical boundary resources is potentially a unitary morphism \(H_{\rm in}\to H_{\rm out}\), but it is not an in-place Sturm process value. It remains a `ChannelDAG` in M8. A later `UnitaryMorphism{In,Out}` could model that case without weakening `ctrl`.

### 1.5 Integration with the existing kernel

The design extends rather than replaces the existing kernel idioms:

- `UnitaryBlock <: ProcessValue`, matching the current `ProcessValue` role (`src/kernel/u2.jl:23-45`).
- `nwires(::UnitaryBlock)` derives from its flattened quantum boundary.
- The generic algebra gains a `portschema` compatibility check in addition to the current wire-count assertion (`src/kernel/algebra.jl:31-40`).
- `adjoint(::UnitaryBlock)`, `⊗`, and block composition return certified process values or existing `Seq`/`Tensor` nodes.
- `ctrl(::UnitaryBlock)` is an explicit exhaustive method in `src/kernel/ctrl.jl`; the no-catch-all discipline remains.
- No method is added for `ChannelDAG`.
- `_emit!(::UnitaryBlock)` and `_apply_controlled!(..., ::UnitaryBlock, ...)` live with the existing `Ad` lowering under `src/orkan/`, not in passes or the surface.
- Controlled replay allocates block-local scratch unconditionally, controls only the `UApply` instructions, and releases scratch without measurement after certificate validation. This implements the same allocation/control/deallocation identity currently intended in `src/surface/when.jl:193-214`.
- Source lint should require `_sealed_unitary_block` to appear only in the sealer, just as `_ctrl` construction is confined today (`test/runtests.jl:151-190`).

`QFT` currently has no `ctrl` method by design (`src/kernel/qft.jl:26-28`). Before a block containing `QFT` can be sealed as control-ready, M8 must expand it into the exact phase-bearing `H`, `ctrl(P(θ))`, and phase-free swap process values. The expansion must be tested as a \(U(d)\) equality, not merely an `Ad` equality.

---

## 2. Structural clean-ancilla certificate

### 2.1 Physics statement

Let \(S\) denote the surviving boundary system and \(A\) all local ancillas. Canonical allocation is the isometry

\[
\iota:\mathcal H_S\rightarrow\mathcal H_S\otimes\mathcal H_A,
\qquad
\iota|\psi\rangle=|\psi\rangle|0_A\rangle .
\tag{2}
\]

Let \(W\in U(\mathcal H_S\otimes\mathcal H_A)\) be the ordered product of the body’s phase-fixed process values. A clean release is the coisometry \(\iota^\dagger=I_S\otimes\langle0_A|\), but it is valid only on the reachable image.

The certificate must establish one of the equivalent universal statements

\[
W\bigl(\mathcal H_S\otimes|0_A\rangle\bigr)
\subseteq
\mathcal H_S\otimes|0_A\rangle ,
\tag{3}
\]

or

\[
(I-\iota\iota^\dagger)\,W\,\iota=0 .
\tag{4}
\]

This is precisely review F1’s condition (`docs/design/prd-v2-review-gpt56-2026-07-19.md:18-26`).

Define

\[
U=\iota^\dagger W\iota .
\tag{5}
\]

Since \(W\) is unitary and the finite-dimensional clean subspace is invariant, \(U\) is a unitary on \(\mathcal H_S\). Moreover,

\[
\operatorname{Tr}_A
\left[
W(\rho\otimes|0_A\rangle\langle0_A|)W^\dagger
\right]
=U\rho U^\dagger .
\tag{6}
\]

Without (3), the left side is merely a Stinespring channel and need not lie in the image of `Ad`. The counterexample

\[
|x\rangle_S|0\rangle_A\mapsto|x\rangle_S|x\rangle_A
\]

followed by tracing \(A\) dephases \(S\). It happens to look clean on input \(|0\rangle\), which is why a current-state marginal cannot certify the program.

Yuan–Villanyi–Carbin Definition 4.7 universally quantifies synchronization over every input, and Theorems 4.8/4.9 connect synchronization to a unitary induced data map (`docs/physics/yuan_villanyi_carbin_control_flow.md:103-159`). The user’s semantic guard qubit is not the synchronized scratch: it remains a live output and may be entangled. Only internal path state and ancillas must factor out.

### 2.2 Certificate representation

```julia
abstract type CleanRule end

struct UntouchedZeroRule <: CleanRule
    ancillas::Tuple{Vararg{PortID}}
end

struct ExactCancellationRule{V<:ProcessValue} <: CleanRule
    ancillas::Tuple{Vararg{PortID}}
    forward::V
    ports::Tuple{Vararg{PortID}}
    forward_index::Int
    inverse_index::Int
end

struct ComputeUseUncomputeRule <: CleanRule
    ancillas::Tuple{Vararg{PortID}}
    sources::Tuple{Vararg{PortID}}
    compute_range::UnitRange{Int}
    use_range::UnitRange{Int}
    uncompute_range::UnitRange{Int}
end

struct CleanPermContract <: CleanRule
    sources::Tuple{Vararg{PortID}}
    targets::Tuple{Vararg{PortID}}
    ancillas::Tuple{Vararg{PortID}}
    compute::Perm
    copy::Perm
    uncompute::Perm
end

struct BoundaryIdentity
    inputs::Tuple{Vararg{PortID}}
    outputs::Tuple{Vararg{PortID}}
    resource_map::Tuple
end

struct CleanSubspaceCertificate{R<:Tuple} <: UnitaryCertificate
    boundary::BoundaryIdentity
    rules::R
end

struct SequentialCertificate{A,B} <: UnitaryCertificate
    first::A
    second::B
end

struct TensorCertificate{A,B} <: UnitaryCertificate
    left::A
    right::B
end

struct AdjointCertificate{A} <: UnitaryCertificate
    source::A
end

struct TransportedCertificate{C,R} <: UnitaryCertificate
    source::C
    exact_rewrite::R
end
```

These are proof terms, not user assertions. Constructors remain internal. The checker validates them against exact node identities, exact port roles, and frozen process values.

No `isapprox`, statevector, density matrix, Choi matrix, or sampled execution participates in construction of a certificate.

### 2.3 Trusted structural rules

M8 should initially recognize a conservative proof language.

#### Rule Z0 — untouched canonical zero

An ancilla allocated in \(|0\rangle\) remains clean if it is never a target of an operation. Appearing only as a control is safe because control does not modify the control port.

This requires an exact port-role analysis:

- `U2` targets its sole port.
- `Ctrl{V}` treats its leading ports as read-only controls and delegates target roles to `V`.
- `Perm` derives control and target roles from each `MCX`.
- `Tensor` unions disjoint footprints.
- `Seq` composes footprints.
- Unknown process-value kinds are conservatively “target every port” unless they implement an audited effect trait.

#### Rule INV — exact compute/cancel

A frozen instruction and its exact kernel-constructed adjoint cancel when adjacent. Disjoint instructions may commute only when their complete supports are disjoint.

This proves cases such as the current legal M5 body

```julia
a = QBool(false)
not!(a)
not!(a)
```

without consulting the state. Structural equality or exact provenance is used; approximate semantic equality is not a proof.

#### Rule CUU — classical compute, control-only use, uncompute

Let \(C\) be a phase-free permutation satisfying:

- its targets are entirely in fresh scratch \(A\);
- its controls lie in unchanged source ports \(S\) or prior scratch ports;
- it therefore maps \(|x\rangle_S|0\rangle_A\) to
  \(|x\rangle_S|f(x)\rangle_A\).

Allow a middle block \(M\) provided every occurrence of \(S\cup A\) is control-only and all targets lie in a disjoint set \(T\). Require the final block to be the exact `adjoint(C)` on the same ordered ports.

Then

\[
|x\rangle|0\rangle|\psi\rangle
\xrightarrow{C}
|x\rangle|f(x)\rangle|\psi\rangle
\xrightarrow{M}
|x\rangle|f(x)\rangle M_{x,f(x)}|\psi\rangle
\xrightarrow{C^\dagger}
|x\rangle|0\rangle M_{x,f(x)}|\psi\rangle .
\tag{7}
\]

By linearity the proof holds for arbitrary superpositions and entanglement with external references. This is the useful matched ctrl compute/uncompute rule; merely seeing `C` and `C†` around arbitrary quantum code is not enough.

#### Rule BENNETT — certified clean permutation

Bennett compute-copy-uncompute provides the structural theorem

\[
(I;B;B)\longmapsto(I;B;P),
\tag{8}
\]

with input restored, history/scratch blank, and only the output changed (`docs/physics/bennett_1973_logical_reversibility.md:42-99`).

A Bennett clean contract must therefore contain or reconstruct:

1. a frozen forward compute permutation;
2. an output-XOR copy whose output ports are never read as controls;
3. the exact reversed inverse compute;
4. immutable source, target, and scratch role tables.

The checker verifies the three parts rather than trusting `perm isa Perm`.

A general `Perm` proves that all of its listed ports undergo a unitary permutation. It does **not** prove that an arbitrary subset designated as scratch returns to zero. The latter is the additional Bennett contract.

The existing `CompiledOracle` stores a `Perm` and mutable role vectors (`src/bennett/bridge.jl:73-80`). Its small exhaustive tests establish cleanliness only within tractable widths (`test/test_m7_bennett.jl:70-103`). M8 must freeze the role data and carry the construction proof for unbounded widths.

An under-sized oracle target is especially important. High output “tail” wires are not Bennett scratch and are not generally clean. They may be released only if the compiler supplies a structural range proof that those bits are zero for every input. Current per-input zero-tail checking (`test/test_m7_bennett.jl:334-348`) cannot certify a unitary block.

### 2.4 Sealing algorithm

A unitary trace uses a mutable builder but does not expose a value until sealing:

1. Snapshot the external live resource identities.
2. Record each process application and its exact ordered port roles.
3. Record only canonical \(|0\rangle\) scratch allocation.
4. Reject measurement, arbitrary preparation, `ptrace!`, noise, reset, or `cases`.
5. At region exit, collect all scratch release requests before releasing any port.
6. Normalize every process leaf to a frozen, control-ready representation.
7. Prove each scratch scope with Z0, INV, CUU, BENNETT, or a composition of already certified blocks.
8. Verify that no scratch escapes.
9. Verify that the output boundary is the same ordered resource boundary as the input.
10. Freeze the program and certificate.
11. Call the private `_sealed_unitary_block` constructor.

Failure at any step is loud. The trace remains a `ChannelDAG` if it is being reified as a general channel; it cannot be silently promoted to a process value.

A no-ancilla body receives a trivial certificate because a composition of phase-fixed process values on a fixed boundary is already unitary.

### 2.5 Composition, tensor, adjoint, and control

Certificates compose algebraically:

- Sequential composition of two blocks on the same boundary is certified by `SequentialCertificate`; each block releases its own clean environment before the next begins.
- Tensor composition renames local ports apart and uses `TensorCertificate`.
- For adjoint, reverse the unitary program and adjoint every `UApply`. If \(W\) leaves the clean subspace invariant, unitarity gives equality rather than strict inclusion, so \(W^\dagger\) also leaves it invariant. Scratch is freshly allocated at the start of the adjoint block and released at its end.
- Exact pass rewrites transport the certificate with `TransportedCertificate`.

Control is sound because

\[
\widetilde W
=
|0\rangle\langle0|_C\otimes I_{SA}
+
|1\rangle\langle1|_C\otimes W
\tag{9}
\]

leaves \(A\) in zero in both branches: trivially in the zero branch and by (3) in the firing branch. Therefore

\[
(I_C\otimes\iota^\dagger)\widetilde W(I_C\otimes\iota)
=
|0\rangle\langle0|_C\otimes I_S
+
|1\rangle\langle1|_C\otimes U
=
\operatorname{ctrl}(U).
\tag{10}
\]

This is the precise streaming license. Delorme–Perdrix functoriality gives
\(C(g\circ f)=C(g)\circ C(f)\), while Equation 16 gives the control-scope reassociation law (`docs/physics/delorme_control_as_constructor.md:54-103`).

### 2.6 Eager execution and the existing marginal check

Eager streaming must tee-record the same structural events used by `TracingContext`.

For a `when` frame:

1. Surface operations continue streaming through `_act!`.
2. The frame simultaneously records a unitary candidate.
3. Region exit first attempts structural sealing for the whole frame.
4. Only a successful certificate licenses scratch release.
5. In debug mode, Eager/DM then checks the actual \(|1\rangle\) marginal of every released ancilla.
6. A structurally certified block whose debug state check fails indicates an executor, lowering, numerical, or certificate-checker defect.

The current functions at `src/surface/when.jl:217-235` should be renamed conceptually from “witness” to “debug assertion.” `CLEAN_EPS` remains a numerical diagnostic tolerance, not a theorem threshold.

The adversarial program from review F1 must fail structurally even when its present input is \(|0\rangle\):

```julia
a = QBool(false)
a ⊻= r
# drop a without uncompute
```

On \(r=|0\rangle\), the current marginal check passes. The structural checker sees an unmatched target write to `a` and rejects it. Program acceptance therefore no longer depends on runtime input.

Because a streaming executor may discover an unmatched pattern only at frame exit, a failed structural seal occurs after some Eager effects have executed. The safe policy is to poison that context so caught exceptions cannot continue from partially executed invalid state. Whether to accept that policy or make the first Eager invocation materialize before applying is a Tobias-level ruling below.

---

## 3. Pass contract

### 3.1 Two pass domains

```julia
abstract type PassDomain end
struct ChannelDomain <: PassDomain end
struct UnitaryRepresentativeDomain <: PassDomain end

abstract type AbstractPass{D<:PassDomain} end

struct ChannelRewrite{I,O}
    source::ChannelDAG{I,O}
    candidate::ChannelDAG{I,O}
    derivation::FrozenSeq
end

struct PhaseDelta
    δ::Float64
    rule::Symbol
end

struct UnitaryRewrite{P,C}
    source::UnitaryBlock{P,C}
    candidate_program::FrozenSeq{AbstractUnitaryInstr}
    delta::PhaseDelta
    derivation::FrozenSeq
end
```

There is no common “DAG pass” entry that accepts either domain.

A channel pass must preserve:

1. exact input/output port schemas and ordering;
2. quantum ownership and classical-record correlations;
3. complete positivity and trace preservation;
4. the channel denotation;
5. measurement, discard, noise, and branch barriers unless a specific channel rewrite theorem crosses them.

A unitary pass must preserve:

1. the exact fixed boundary and resource lineage;
2. the clean-subspace certificate;
3. the chosen \(U(d)\) representative, including global phase;
4. `adjoint` and future `ctrl` behavior;
5. deep immutability;
6. any declared numerical error budget.

A unitary-only algorithm has no method for `ChannelDAG`, mechanically enforcing the constitution’s measurement-barrier rule (`CLAUDE.md:191-202`).

Deferred measurement is a `ChannelDomain` pass. Reassociation, view fusion, and 1q quaternion fusion are `UnitaryRepresentativeDomain` passes.

### 3.2 Proof-producing rewrite rules

Production passes must be assembled from audited rewrite rules. Each rule:

1. matches exact frozen source nodes;
2. constructs replacement nodes;
3. states a representative-level equation;
4. returns its phase delta;
5. states how it transports the clean certificate.

Examples:

- Quaternion fusion uses the existing phase-adding Hamilton product (`src/kernel/u2.jl:99-121`):

  \[
  U(a\circ b)=U(a)U(b),\qquad\delta=0 .
  \]

- View fusion uses exact \(V^\dagger V=I\), not channel cancellation.
- Reassociation uses Delorme–Perdrix Equation 16, so its equality is in the controlled unitary algebra, not only after `Ad`.
- A synthesis rule that chooses a different phase must report it explicitly.

The only way to turn a `UnitaryRewrite` back into a `UnitaryBlock` is a trusted `commit` function that replays and validates every proof step.

### 3.3 Explicit phase delta

Suppose a rewrite proves

\[
U_{\rm candidate}=e^{i\delta}U_{\rm source}.
\tag{11}
\]

Before sealing, `commit` composes `gphase(-δ)` on one canonical boundary qubit. On an \(n\)-qubit boundary,

\[
\bigl(e^{-i\delta}I_2\bigr)\otimes I_{2^{n-1}}
=
e^{-i\delta}I_{2^n},
\tag{12}
\]

so the committed result denotes exactly \(U_{\rm source}\).

This uses the existing phase-bearing `U2` machinery and routes any later control through the existing `ctrl(gphase(...))` path. A pass may not silently set \(\delta=0\), infer it from Choi data, or discard it because the uncontrolled channel is unchanged.

For M8’s three planned unitary passes, the expected delta is analytically zero. The explicit mechanism prevents future synthesis, QSVT, or external passes from weakening the contract.

### 3.4 Mechanical enforcement

The contract is enforced by construction:

- `ChannelDAG` is outside `ProcessValue`, so it cannot reach `ctrl`.
- `UnitaryBlock` has a private constructor.
- Passes return unsealed rewrite objects, never raw `UnitaryBlock`s.
- Only audited rule constructors can create representative proofs.
- `commit` validates port equality, proof steps, phase ledger, frozen storage, and certificate transport.
- A source lint confines `_sealed_unitary_block` and unitary-proof constructors to the sealer and pass verifier.
- A unitary pass has no dispatch method for `ChannelDAG`.
- A channel pass cannot promote its result to `UnitaryBlock` from Choi equality.
- Unit-only passes cannot cross `AllocateZero`/`UReleaseZero` boundaries unless their proof explicitly transports the clean certificate.
- Unknown process leaves or unknown rewrite rules fail loudly.

Tests remain necessary, but they verify the trusted proof kernel rather than serving as the proof mechanism.

### 3.5 Named law tests

All direct unitary comparisons below mean ordinary matrix comparison with phase included. `approx_upto_phase` is forbidden.

| Required test name | Exact statement |
|---|---|
| `M8.PORT.TYPED-COMPOSITION` | Every node’s output schema equals the next consumer’s input schema; malformed dimension, arity, or resource-lineage composition is rejected before lowering. |
| `M8.PORT.CHANNEL-NOT-PROCESS` | `ChannelDAG <: ProcessValue` is false; no `ctrl(::ChannelDAG)` or unitary-pass method exists. Allocation and discard alone cannot be applied as process values. |
| `M8.PORT.ENDOMORPHIC-BLOCK` | Sealing fails unless output boundary schema, order, and resource lineage equal the input boundary exactly. |
| `M8.CERT.CLEAN-SUBSPACE` | For each small certified fixture, dense \(W\) satisfies \(\|(I-\iota\iota^\dagger)W\iota\|\approx0\), and \(U=\iota^\dagger W\iota\) satisfies \(U^\dagger U\approx UU^\dagger\approx I\). |
| `M8.CERT.STATE-IS-NOT-WITNESS` | The unmatched `r → a` compute is rejected structurally even on an Eager run with \(r=|0\rangle\), where the debug marginal is zero. |
| `M8.CERT.MATCHED-COMPUTE-UNCOMPUTE` | A valid CUU fixture is accepted for arbitrary superposed and reference-entangled sources; dense comparison verifies Equation (7). |
| `M8.CERT.PERM-SUBSET-NEEDS-CONTRACT` | A bare `Perm` is accepted as unitary when every port is boundary, but cannot justify releasing designated scratch without a checked `CleanPermContract`. |
| `M8.CERT.BENNETT` | A structurally checked compute-copy-uncompute artifact restores every declared scratch port and preserves its sources for every input; exhaustive truth-table comparison is added for small widths as a checker test. |
| `M8.CERT.COMPOSITION` | Certified sequential, tensor, and adjoint blocks retain valid certificates and denote \(U_2U_1\), \(U_1\otimes U_2\), and \(U^\dagger\), respectively. |
| `M8.CTRL.BLOCK-HOMOMORPHISM` | For certified blocks \(g,h\), `denoted_matrix(ctrl(g∘h)) ≈ denoted_matrix(ctrl(g)∘ctrl(h))`. |
| `M8.CTRL.BLOCK-ADJOINT` | `denoted_matrix(adjoint(ctrl(g))) ≈ denoted_matrix(ctrl(adjoint(g)))`. |
| `M8.WHEN.STREAM-MATERIALIZED-AD` | If \(S(b)\) is the phase-fixed streamed body value and \(M(b)\) its sealed materialization, then \(S(b)\approx M(b)\) as \(U(d)\) representatives, not merely `Choi(Ad(S)) ≈ Choi(Ad(M))`. |
| `M8.WHEN.STREAM-MATERIALIZED-CTRL` | `Choi(Ad(ctrl(S(b)))) ≈ Choi(Ad(ctrl(M(b))))` on small instances. This is mandatory even if the preceding uncontrolled Choi test passes. |
| `M8.PASS.PORT-AND-CERTIFICATE` | Every committed unitary pass result has the same boundary and a valid original or transported certificate. |
| `M8.PASS.UNITARY-REPRESENTATIVE` | For each of reassociation, view fusion, and U2 fusion, \(U_{P(B)}\approx U_B\) directly, including phase. |
| `M8.PASS.UNITARY-CONTROLLED` | For every unitary pass \(P\), `Choi(Ad(ctrl(P(B)))) ≈ Choi(Ad(ctrl(B)))`. |
| `M8.PASS.PHASE-DELTA` | For a rule reporting \(\delta\), the uncommitted candidate satisfies \(U'=e^{i\delta}U\); the committed result satisfies \(U_{\rm committed}\approx U\), and the controlled Chois agree. |
| `M8.PASS.PHASE-SENTINEL` | For \(\alpha=\pi/3\), verify `Choi(Ad(I)) ≈ Choi(Ad(gphase(α)))` but `Choi(Ad(ctrl(I))) ≉ Choi(Ad(ctrl(gphase(α))))`. A fabricated phase-dropping rewrite must be rejected or fail the controlled law. |
| `M8.PASS.CHANNEL-DENOTATION` | For every channel pass, input/output signatures are identical and `Choi(P(G)) ≈ Choi(G)` on exact small fixtures. |
| `M8.PASS.MEASUREMENT-BARRIER` | No unitary pass visits a block spanning an instrument, `DiscardNode`, noise node, or `CasesNode`; deferred measurement is exercised only through the channel-pass interface. |

The phase sentinel is the test of the test. Delorme’s standard control is

\[
C(U)=|0\rangle\langle0|\otimes I+|1\rangle\langle1|\otimes U,
\tag{13}
\]

and a controlled global phase becomes an observable \(Z\)-rotation (`docs/physics/delorme_control_as_constructor.md:116-142`). Tang–Wright’s \(I\) versus \(-I\) example is the canonical separation (`docs/physics/tang_wright_2025_controlled_unitaries.md:39-50`).

Dense matrix and Choi tests should remain small. Review F25 correctly rejects the PRD’s claimed 15-wire dense-DM Choi capacity; larger tests need randomized reference-assisted probes rather than exponential dense matrices (`docs/design/prd-v2-review-gpt56-2026-07-19.md:285-292`).

---

## 4. Required PRD wording changes

### 4.1 Replace §2 “The lowering contract” (`Sturm-PRD-v2.md:145-150`)

> **The lowering contract.** Every surface construct lowers either to a typed channel graph or to application of a phase-fixed process value. A `ChannelDAG{InPorts,OutPorts}` denotes a CPTP map and is compared at channel level. A `UnitaryBlock{Ports,Certificate}` is an opaque, fixed-boundary process value and preserves a definite \(U(d)\) representative. Control and adjoint are defined only on process values. Channel equivalence is insufficient for any value that may later be controlled: unitary-block lowering and passes preserve the \(U(d)\) representative, including global phase, or report and reattach an explicit phase delta. The phase quotient is crossed exactly once by `Ad` at application.

### 4.2 Correct §1.1’s control-disentanglement statement (`Sturm-PRD-v2.md:84-94`)

Replace “must leave control disentangled at exit” with:

> Sound coherent-control bodies must be reversible, must not access the user’s guard, and must synchronize all internal control-flow/path and scratch state before exit. The user’s guard remains a live quantum output and may be entangled with the data; CNOT on \(|+\rangle|0\rangle\) is the elementary example. The synchronization theorem applies to internal machine state that is discarded, not to the semantic guard qubit.

This avoids review F10’s contradiction while preserving the actual synchronization requirement.

### 4.3 Replace §3.5’s semantic and operational text (`Sturm-PRD-v2.md:465-508`)

> `when(q, body)` is defined as follows:
>
> 1. trace `body` over its touched non-guard ports;
> 2. structurally certify the result as an opaque `UnitaryBlock{Ports,Certificate}`;
> 3. apply `ctrl(block)` to the guard and the block’s ordered boundary ports.
>
> The certificate is a universally quantified process proof. If the body allocates canonical scratch \(A\), its frozen unitary program \(W\) must establish
>
> \[
> (I-\iota\iota^\dagger)W\iota=0,\qquad
> \iota|\psi\rangle=|\psi\rangle|0_A\rangle ,
> \]
>
> for every input \(|\psi\rangle\). A statevector or density-matrix observation on the current run is not a certificate.
>
> The guardrails are soundness requirements:
>
> 1. The body must seal as a `UnitaryBlock`. Measurement casts, arbitrary preparation casts, `ptrace!`, `cases`, noise, reset, and channel nodes are loud errors. Canonical fresh-\(|0\rangle\) scratch allocation is the sole preparation exception.
> 2. The body must not operate on the guard register, including through a view or alias. Nested controls must resolve to pairwise-distinct physical parent resources.
> 3. Unbounded recursion or iteration under `when` is forbidden; only bounded unrolling is permitted.
>
> Eager execution may implement a certified body streamingly because
> `ctrl(g ∘ h) = ctrl(g) ∘ ctrl(h)`. While streaming, it records the same immutable structural transcript consumed by the certifier. Scratch is not released until the complete frame is certified. In debug mode only, Eager and density contexts additionally assert that each certified scratch port has zero non-canonical marginal; failure indicates a lowering/backend defect. `TracingContext` materializes and seals the same transcript without executing a state assertion.
>
> Required laws:
>
> - the streamed and materialized bodies preserve the same \(U(d)\) representative;
> - their `ctrl`-wrapped applications denote the same channel.
>
> An uncontrolled Choi comparison alone is insufficient because `Ad` quotients \(U(1)\).

### 4.4 Replace §3.9 “Inside `when`” (`Sturm-PRD-v2.md:753-760`)

> **Inside `when`, ordinary trace is forbidden.** A body-local canonical ancilla may leave scope only through a certified `ReleaseZero`, interpreted as the coisometry \(I\otimes\langle0|\) on the structurally proved reachable clean subspace. If no structural clean-subspace proof exists, the body is a channel with an environment and cannot become a process value; guardrail 1 fires loudly. The Eager \(|1\rangle\)-marginal check is retained only as a debug assertion of a previously established certificate. Bennett artifacts may supply a clean certificate by checked compute-copy-uncompute construction; a bare `Perm` proves unitarity on all of its ports but not cleanliness of an arbitrarily designated subset.

The surrounding default rule remains unchanged: outside a process-valued `when` trace, unreturned owned locals are silently partially traced as the Stinespring environment.

### 4.5 Replace the `UnitaryDAG` bullet in §4.1 (`Sturm-PRD-v2.md:823-828`)

> - `ChannelDAG{InPorts,OutPorts}` — immutable typed channel IR containing process applications, allocation, instruments, classical records, branching, noise, reset, and discard. It is not a `ProcessValue`; `ctrl` and unitary-only passes have no methods for it.
> - `UnitaryBlock{Ports,Certificate} <: ProcessValue` — an opaque fixed-boundary endomorphism whose frozen program contains only phase-fixed unitary applications plus canonical scratch allocation/release pairs covered by a structural clean-subspace certificate. It carries one boundary signature because its ordered output resources are definitionally the same as its ordered input resources. Only the trusted sealer constructs it.
> - Future finite-dimensional process values carry definite \(U(d)\) representatives; an `SU(d)` value without its \(U(1)\) phase is insufficient under control.

The last sentence records review F9’s unavoidable phase requirement without prescribing a particular future \(U(d)\) representation.

### 4.6 Add to §4.2 after the existing algebra laws

> **Pass law.** Pass correctness is stratified by value kind:
>
> - a channel pass preserves the typed CPTP denotation;
> - a unitary-block pass preserves the phase-fixed \(U(d)\) representative.
>
> A unitary pass may alternatively return a proved phase delta
> \(U'=e^{i\delta}U\), but it must reattach \(e^{-i\delta}\) before returning a process value. Every unitary pass has two required law tests: direct representative equality and equality of the `ctrl`-wrapped pre/post channels. Choi equality of the uncontrolled values is not a unitary-pass proof.
>
> Unit-only passes are mechanically restricted to `UnitaryBlock`s and cannot cross measurement, discard, noise, or classical-control barriers. Channel passes cannot promote a result to `UnitaryBlock` from Choi equality.

### 4.7 Amend §4.3’s dispatch table (`Sturm-PRD-v2.md:906-918`)

Replace `UnitaryDAG` with:

| Value | Pure context | Density context |
|---|---|---|
| `UnitaryBlock` | allocate certified local scratch; replay phase-fixed unitary instructions; certified zero-release; uncontrolled `Ad` may quotient phase only at leaf application | same as conjugation |
| `ChannelDAG` | channel executor or explicit unsupported-channel error; never `ctrl` | exact channel execution |

The Stinespring fallback remains an execution artifact for a channel. It must not be reclassified as a controllable representative of that channel.

### 4.8 Replace §4.4’s stratification table

| Level | Objects | Operations | `ctrl` |
|---|---|---|---|
| Process values | `U2`, frozen `Perm`, `QFT` after exact control-ready expansion, `UnitaryBlock`, `Tensor`, `Seq`, `Ctrl` | `∘`, `⊗`, `adjoint`, `ctrl` | defined by explicit exhaustive methods |
| Channels | `ChannelDAG`, casts, instruments, noise, trace, reset, `cases` | typed composition and tensor | unrepresentable |

Add:

> A certificate promotes one particular frozen, fixed-port unitary trace to a process value. It does not invert `Ad`, control a channel, or infer a phase representative from a Choi matrix.

### 4.9 Replace D13’s resolved wording (`Sturm-PRD-v2.md:1537-1543`)

> **D13 — `when` operational semantics: AMENDED by M8 design gate.** Streaming remains licensed by the `ctrl` homomorphism, but the Eager \(|1\rangle\)-marginal observation is a debug assertion, not a witness. Both Eager and Tracing record a structural unitary transcript. A body with scratch is accepted only when the transcript seals as a fixed-boundary `UnitaryBlock` with a universal clean-subspace certificate. The required law is representative-preserving streaming equivalence plus a `ctrl`-wrapped Choi comparison.

### 4.10 Implementation-plan corollary

M8’s current wording at `Sturm-v2-IMPLEMENTATION-PLAN.md:298-322` should be split into:

1. typed immutable `ChannelDAG`;
2. unitary candidate tracing and structural sealer;
3. `UnitaryBlock` application/adjoint/control;
4. Eager tee tracing and debug assertions;
5. channel-pass framework;
6. representative-preserving unitary-pass framework;
7. tokens and `cases` only after F4–F6 receive their own design resolution.

The current “Channel DAG with unitarity witness” wording must be removed.

---

## 5. Risks, alternatives, and Tobias-level rulings

### 5.1 Rulings required

#### R1 — Eager failure topology

Options:

- **A. Tee-record while streaming, then poison the context if structural sealing fails.**
- **B. Materialize and certify before applying on the first Eager invocation.**
- **C. Execute the closure twice: once to trace, once to stream.**

**Recommendation:** A. It preserves one closure execution and the streaming path. The context must become unusable after a failed late seal because its state may already contain effects from an invalid body. B is safer transactionally but turns Eager `when` into materialized execution. C violates the “closure runs exactly once” contract and duplicates classical side effects.

#### R2 — Surface spelling for canonical scratch

Options:

- Continue allowing `QBool(false)` inside `when` as the sole preparation exception.
- Introduce a distinct `scratch(QBool)` or `ancilla(QBool)` form.
- Ban all allocation inside `when`.

**Recommendation:** retain `QBool(false)` as a tightly specified canonical-zero exception. Arbitrary `QBool(p,φ)`, including `QBool(true)`, remains forbidden. A new scratch spelling risks becoming an eighth surface construct; banning allocation would reject necessary compute/uncompute patterns.

#### R3 — Certificate completeness

Options:

- Conservative Z0/INV/CUU/BENNETT rules.
- Dense universal verification below a width cutoff.
- General symbolic or SMT-based invariant proving in M8.

**Recommendation:** conservative structural rules only. Dense checks belong in tests, not certificate construction. Valid but unrecognized programs should fail with an error explaining which scratch scope lacks an accepted proof and suggesting a certified Bennett/compute-uncompute form.

#### R4 — `Perm` immutability

Options:

- Refactor `MCX`/`Perm` to tuples while retaining vector-accepting constructors.
- Copy every `Perm` into a private frozen snapshot when inserted into IR.
- Trust caller discipline around the existing vectors.

**Recommendation:** refactor the kernel types. Trusting caller discipline makes certificate validity mutable. Private snapshots duplicate the reversible process hierarchy and complicate `ctrl`, `adjoint`, and equality.

#### R5 — Under-sized oracle targets

Options:

- Require a full-width target in all unitary contexts.
- Allow a smaller target only with a compiler-supplied universal range certificate.
- Exhaustively infer the range below a width threshold.
- Retain current per-run zero-tail acceptance.

**Recommendation:** full width by default; permit smaller targets only with a structural range certificate. Exhaustive enumeration may test a certificate for small widths but must not define semantics. Per-run acceptance repeats F1.

#### R6 — Equal-dimensional port replacement

Options:

- M8 `UnitaryBlock` requires identical resource lineage at input and output.
- Permit `UnitaryBlock{InPorts,OutPorts}` with different physical identities.
- Add a separate `UnitaryMorphism{InPorts,OutPorts}` later.

**Recommendation:** identical resource lineage for M8, with the third option reserved. Existing `ProcessValue` and `apply!` semantics are in-place on stable handles (`src/context/abstract.jl:31-32`, `src/orkan/ad.jl:342-360`). General port replacement would require a separate consuming/producing application API.

#### R7 — Phase-delta extensibility

Options:

- Keep `PhaseDelta` and proof constructors internal in M8.
- Expose them immediately as a plugin pass API.
- Forbid nonzero deltas entirely.

**Recommendation:** internal initially. The mechanism should exist so the representation is correct, but an external proof API needs a separate trust and versioning design.

#### R8 — Zero-port scalar process values

Equation (12) uses one boundary qubit to reattach phase. Options are:

- forbid zero-port `UnitaryBlock`s in M8;
- add a phase scalar process value \(e^{i\phi}:I\to I\);
- special-case the phase ledger.

**Recommendation:** forbid zero-port blocks in M8 and design scalar process values alongside future general \(U(d)\) support.

### 5.2 Alternatives rejected

**One DAG plus `unitary::Bool`.** Rejected because it proves neither port equality nor the clean-subspace theorem. It also permits accidental unitary-only dispatch on channel nodes.

**A statevector marginal as certificate.** Rejected by the universal counterexample in F1. It remains valuable as a debug assertion.

**Numerical matrix verification as certificate.** Rejected because it scales exponentially, is tolerance-dependent, and cannot support large Bennett artifacts. It is appropriate for testing the structural checker.

**Any `Perm` as a clean-subset witness.** Rejected. A permutation is unitary on all ports but may freely move information into ports a caller intends to discard.

**Choi-only unitary pass verification.** Rejected because

\[
\operatorname{Ad}_U=\operatorname{Ad}_{e^{i\alpha}U}
\]

while Equation (13) distinguishes their controlled forms. This is precisely F3.

**Pretrace plus a second Eager execution.** Rejected as the default because classical side effects would run twice and closure identity does not imply stable captured values.

**Allowing arbitrary preparation inside `when`.** Rejected. The current constructor allocates and applies its preparation process uncontrolled (`src/types/qbool.jl:91-110`), which does not implement control of the traced body. Canonical zero allocation is the only justified exception.

### 5.3 Residual M8 blockers outside this proposal

This proposal resolves the unitary half of M8 but does not resolve review findings F4–F6:

- runtime classical arithmetic and dynamic loops still require a restricted classical SSA/CFG or staged retracing;
- exact density-matrix branching cannot return an ordinary scalar `Bool`;
- `cases` still needs linear quantum joins and persistent correlated classical records.

Typed `ChannelDAG` ports are necessary groundwork for those decisions, not their solution. M8 should not implement tokens or `cases` merely because the unitary block design is settled.

Two additional prerequisites should be tracked:

- pairwise alias checks among nested controls, including dual views, are required before relying on a flat distinct-control interpretation;
- future `SU(d)`-only process values are incompatible with this pass contract unless accompanied by their \(U(1)\) phase.

## Acceptance criterion

The design gate is satisfied when M8 can demonstrate all of the following without a Boolean unitarity flag:

1. an adversarial input-dependent clean-state program is rejected structurally;
2. a valid matched compute/uncompute body seals as a phase-fixed `UnitaryBlock`;
3. a channel graph cannot be passed to `ctrl` or a unitary-only pass;
4. unitary passes return only proof-checked, phase-correct blocks;
5. streaming and materialized bodies agree both as \(U(d)\) representatives and after control;
6. the Eager marginal check is documented and tested solely as a debug assertion.