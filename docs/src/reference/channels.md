# Reference — channel values and the channel IR

```@meta
CurrentModule = Sturm
```

*Dry, exhaustive lookup. All `public`, none exported — spell it
`Sturm.depolarizing`, `Sturm.certify`, and so on.*

Sturm keeps three strata strictly apart, and the separation is enforced by the
type system rather than by policy:

1. **Process values** — definite operations. Live in
   [the kernel](kernel.md).
2. **Channel values** — definite *representations* of a physically realizable
   map. A representation is not unique, which is exactly why `ctrl` has no
   method here: controlling one would make the observable result depend on an
   arbitrary choice of representative.
3. **Channel artifacts** — execution-time choices that are not even part of a
   channel's identity, such as a Stinespring dilation.

The only crossings are named functions: `channel` takes a process value to a
channel value (total, and never inverted — there is no `process`), and `dilate`
takes a channel value to a dilation.

---

## Channel values

`KrausFamily` is trace-checked at construction and **never renormalised**.
`MixedUnitary` is kept as a distinct type because it is the class whose
dilation is executable. `ChannelTensor` and `ChannelSeq` are lazy, and the
laziness is load-bearing: the backend's channel entry point is one-local, so
i.i.d. noise on many wires must arrive as separate factors.

```@docs
ChannelValue
KrausFamily
MixedUnitary
ChannelTensor
ChannelSeq
krausrank
kraus_matrices
```

## Denotation and comparison

`choi_matrix` is the canonical matrix form used for all semantic comparison.
`same_channel` compares at that level and is deliberately blind to
representation freedom **and to global phase** — which is why it is barred from
ever being used to check that a rewrite of a value that may later be controlled
is correct. It is a named function and never `Base.isapprox`, because building
the matrix costs exponential work.

```@docs
channel
choi_matrix
same_channel
CHOI_ATOL
CHANNEL_CHOI_MAXWIRES
KRAUS_TP_ATOL
KRAUS_MAXDATA
```

## Named noise families

Convention-pinned constructors. Each validates its parameter range and throws
rather than clamping.

```@docs
bit_flip
phase_flip
pauli_channel
depolarizing
dephasing
phase_damping
amplitude_damping
reset_channel
pinch_channel
```

## Stinespring dilation

Every channel is a unitary on a larger system, with part of it forgotten.
`dilate` builds that unitary explicitly. Note the standing warning: on an eager
context, dilate-and-trace is **one quantum-jump trajectory, not the channel**.
Only some channel classes have an executable dilation; the rest raise an error
naming the missing capability, never a silent wrong answer.

```@docs
ChannelArtifact
StinespringDilation
dilate
```

## The channel IR

`ChannelDAG` is an effect-typed intermediate representation of a **channel**,
not a circuit. It is deliberately *not* a process value: there is no `ctrl`
method for it, which is the "you cannot control a measurement" law, for free.

`MeasureN`, `CasesN` and `NoiseN` are **barriers**. Optimisation methods from
the literature almost all assume unitary circuits and are wrong across a
barrier, so `is_barrier`/`has_barrier` is the predicate the whole pass
discipline hinges on.

```@docs
ChannelDAG
Node
ApplyN
AllocN
TraceN
MeasureN
CasesN
NoiseN
is_barrier
has_barrier
channel_dag
```

### Ports

A port carries a **lineage** tag as well as a width, which is how "two
registers of equal width are not the same register" is made precise.

```@docs
Port
PortID
PortKind
QuantumPort
ClassicalPort
is_quantum
portwidth
```

### Building a DAG

`DAGBuilder` is the mutable staging area; `freeze` and `certify` turn it into
an immutable value.

```@docs
DAGBuilder
input!
alloc!
apply_node!
trace!
measure!
noise!
freeze
```

## Certified unitary blocks

`certify` is the structural sealer: it takes a barrier-free, endomorphic DAG
whose every allocated ancilla has a matched, certified discard, and returns a
`UnitaryBlock` — an opaque unitary that rejoins the process-value tree and can
therefore be controlled. Nothing numerical participates in building a
certificate; it is a structural proof, not a measurement.

```@docs
UnitaryBlock
certify
boundary
denoted_full
```

### Certificates

The closed set of proof rules a `certify` result may carry.

```@docs
CleanCert
NoAncilla
PermClean
MatchedPair
SeqCert
ParCert
AdjointCert
XportCert
```

## Optimisation passes

Two abstractions, kept apart on purpose so a pass can never silently down-type
what it is transforming. Every registered unitary pass must prove **both**
required laws — representative equality *and* equality of its controlled form —
or the build fails. That second conjunct is the defence against the
controlled-phase bug class described in
[phase discipline](../explanation/phase_discipline.md).

```@docs
UnitaryPass
ChannelPass
apply_pass
PASS_REGISTRY
Fuse1qPass
ViewFusionPass
ReassocPass
FuseUnitaryRunsPass
DeferMeasurementPass
DeadRecordEliminationPass
```

## The compute/uncompute combinator

`within` is `public` kernel/library API and **not** an eighth surface
construct. It builds a certified compute/use/uncompute block with a fresh
ancilla. Mind the wire convention: `compute`'s *last* wire is the scratch it
writes, and `inner`'s *first* wire is that same scratch, read as a leading
control. Getting it backwards is a `certify` rejection, not a silent error.

```@docs
within
```

## See also

- [Reference: the kernel](kernel.md) — the process values these channels
  denote.
- [Reference: QECC](qecc.md) — the typed superchannel layer built on top.
- [Functions are channels](../explanation/functions_are_channels.md).
- [Phase discipline](../explanation/phase_discipline.md).
