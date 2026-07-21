# Design Proposal — M8 typed IR, structural clean-ancilla certificate, phase-preserving passes

**Bead:** 5hr7 (P0, gates all M8 code) · **Proposer:** Claude (blind proposer A/B) · **Round:** 3+1 design gate
**Answers:** F2 (UnitaryDAG port typing), F1 (structural clean-ancilla certificate), F3 (phase-preserving pass contract)
from `docs/design/prd-v2-review-gpt56-2026-07-19.md`.

---

## 0. Thesis in one paragraph

The three findings are one finding wearing three hats. A `when` body (or a traced library circuit)
is a **channel** while it is being built — it allocates ancillas (isometry `A|ψ⟩=|ψ⟩|0⟩`), acts, and
deallocates (coisometry, not unitary or even CPTP on the enlarged space, F2). It becomes a **process
value** — a fixed-port unitary that `ctrl` may touch — only when a *state-independent, structural*
proof discharges the clean-ancilla precondition (F1). And once it is a process value, every rewrite
over it must preserve the **U(d) representative including its global phase**, because `ctrl` promotes
that phase to observable physics (Tang–Wright Thm 1.1; F3) — Choi equivalence, which quotients U(1),
cannot see it. The single object that resolves all three is a **certificate**: an algebraic proof term,
built only by a fixed set of physics-grounded constructors, that (a) types the promotion `ChannelDAG →
UnitaryBlock`, (b) *is* the clean-ancilla witness (no state needed), and (c) makes `ctrl(UnitaryBlock)`
sound by the §4.2 control-scope-reassociation law. Passes are then constrained to preserve process-level
`≈` (phase-inclusive), mechanically, via a pass registry + boot lint mirroring the `ctrl` choke point.

Everything below fits the existing kernel: `UnitaryBlock <: ProcessValue`, so it inherits the M1 algebra
(`∘`, `⊗`, `adjoint`, `denoted_matrix`, `≈`) for free (u2.jl:36 docstring already anticipates this), and
`ctrl(::UnitaryBlock)` is *the single method M8 adds* (ctrl.jl:27 promises exactly this).

---

## 1. Type design (F2)

### 1.1 The split: `ChannelDAG` (a channel) vs `UnitaryBlock` (a process value)

The current `ProcessValue` tree (`U2`, `Perm`, `Ctrl`, `Tensor`, `Seq`; u2.jl:36) is *already* a family
of fixed-port, phase-fixed unitaries with `nwires`. A boolean `unitary=true` flag on a DAG (PRD §4.1
l.823) throws that hard-won typing away. Replace it with **two nominal types on two different levels of
the §4.4 stratification** (Process values vs Channels):

```julia
# ---- src/channel/dag.jl : the CHANNEL IR (NOT a ProcessValue) -----------

"Typed ports. Quantum ports carry a width; classical ports carry a token type."
struct QPort;  id::Int; width::Int end         # a quantum wire-bundle port
struct CPort;  id::Int; ttype::DataType end     # a classical token port (ClassicalBit/Int)

"""
    ChannelDAG

A CPTP map denoted by a DAG of effect nodes. Explicitly NOT `<: ProcessValue`:
it lives on the CHANNEL level of §4.4 and `ctrl(::ChannelDAG)` is a deliberate
`MethodError` (P4 — control on a non-unitary effect is UNREPRESENTABLE, mirroring
ctrl.jl's no-catch-all discipline, ctrl.jl:19-27).

Port signature is the isometry/coisometry-honest typing F2 demands: quantum
inputs need not equal quantum outputs (alloc adds an out-port with no in-port;
trace removes one), and measurement produces classical out-ports.
"""
struct ChannelDAG
    nodes   :: Vector{Node}      # topologically ordered; frozen on construction (F28)
    qin     :: Vector{QPort}
    qout    :: Vector{QPort}
    cout    :: Vector{CPort}     # measurement/token outputs
end
```

The node vocabulary is *effect-typed*, deliberately NOT the v0.1 gate-named nodes (the plan warns:
"do not import the node vocabulary", plan l.321). Nodes carry **process values**, never gate names:

```julia
abstract type Node end
struct ApplyN   <: Node; v::ProcessValue; ports::Vector{QPort} end   # unitary application
struct AllocN   <: Node; out::QPort end                              # isometry |ψ⟩↦|ψ⟩|0⟩ (§3.9)
struct TraceN   <: Node; in::QPort; cert::Union{Nothing,CleanCert} end # coisometry / ptrace
struct MeasureN <: Node; in::QPort; out::CPort end                   # instrument (qc cast)
struct CasesN   <: Node; sel::CPort; branches::Vector{ChannelDAG} end # Kleisli join (F6 — separate bead)
struct NoiseN   <: Node; kraus::KrausFamily; ports::Vector{QPort} end # channel-level value
```

`MeasureN`/`CasesN`/`NoiseN` are exactly the nodes CLAUDE.md's "Channel IR vs Unitary Methods"
section names as the barriers unitary passes must never cross. Their presence is what disqualifies a
sub-DAG from promotion.

### 1.2 `UnitaryBlock{N}` — the promoted, opaque process value

```julia
# ---- src/kernel/unitary_block.jl : joins the ProcessValue tree ----------

"""
    UnitaryBlock{N} <: ProcessValue

A fixed-port unitary on `N` *external* (surviving) wires, obtained by CERTIFYING
a `ChannelDAG`. The internal alloc/act/dealloc structure is EXISTENTIALLY HIDDEN
behind `cert`: `N` in-ports == `N` out-ports (a unitary is square — F2's port
equality), and the isometry/coisometry ancilla ports are internal, discharged by
`cert`. `UnitaryBlock` is `<: ProcessValue`, so it inherits `∘`/`⊗`/`adjoint`/
`denoted_matrix`/`≈` from algebra.jl generically (u2.jl:31-35), and it is the ONE
new value the M8 `ctrl` method wraps (ctrl.jl:27).

INVARIANTS (checked at construction, frozen after — F28):
  • `nwires(::UnitaryBlock{N}) == N`  (external ports only).
  • `body` contains ONLY `ApplyN`/`AllocN`/`TraceN` nodes — no Measure/Cases/Noise
    (those keep it on the channel level; §4.4).
  • every `AllocN` is matched by a `TraceN` whose `cert` is non-nothing, and the
    per-block `cert` witnesses that the composite is unitary on the N ports.
"""
struct UnitaryBlock{N} <: ProcessValue
    body :: ChannelDAG        # frozen; qin==qout as widths, cout empty
    cert :: CleanCert         # the structural witness (§2)
end

nwires(::UnitaryBlock{N}) where {N} = N
```

`N` is a *type parameter* (like `QInt{W}`, CLAUDE.md Julia-conv 5) so `ctrl`, `⊗`, and `apply!`'s
wire-count checks stay type-stable (`ctrl(::UnitaryBlock{N})` width is known statically). It is a single
integer, not `{InPorts,OutPorts}` as F2 tentatively wrote, because **a unitary is square**: in-ports and
out-ports are the same N surviving wires. F2's two-parameter form is right for the *isometry fragments*
inside a `ChannelDAG` (where `qin ≠ qout`), and that asymmetry lives on `ChannelDAG.qin/qout`, not on the
promoted block. (Ruling item R4.)

### 1.3 `ctrl(::UnitaryBlock)` — the one added method, and why it is sound

```julia
# src/kernel/ctrl.jl  (THE ONLY edit to the choke-point file)
ctrl(b::UnitaryBlock) = _ctrl(1, b)          # → Ctrl{UnitaryBlock{N}}, exactly like ctrl(::Tensor)
```

Lowering adds one `_apply_controlled!` method in ad.jl, structurally recursive over `body` (no
catch-all — ad.jl:234-237), and **this is where the certificate earns its keep**:

```julia
function _apply_controlled!(ctx, k, controls, inner::UnitaryBlock, targets)
    replay(inner.body) do node
        node isa AllocN  && return _alloc_uncontrolled(node)   # alloc stays UNCONTROLLED
        node isa TraceN  && return _dealloc_certified(node)    # dealloc stays UNCONTROLLED
        node isa ApplyN  && return _apply_controlled!(ctx, k, controls, node.v, slots(node))
    end
end
```

Soundness is the **§4.2 control-scope-reassociation law** (PRD l.875, already a named kernel law and a
`within` combinator): controlling a matched-uncompute block narrows the control onto the acted-on part
and leaves the compute/uncompute uncontrolled —

> `ctrl(C† ∘ M ∘ C) == (1⊗C†) ∘ ctrl(M) ∘ (1⊗C†)† == within(C){ ctrl(M) }`   (V=C†, W=M in l.875)

so under `ctrl`, the ancilla still round-trips `|0⟩ → … → |0⟩` in **both** control branches (control=0:
`ctrl(M)=I`, so `C†∘C=I` on the ancilla; control=1: `C†` uncomputes). Cleanliness is **algebraic, not
state-dependent** — which is precisely the property F1 says the |1⟩-marginal assert lacks. The certificate
is exactly the structural record that the body has this narrowable form.

`denoted_matrix(::UnitaryBlock{N})` (needed by law tests and by `Ctrl`'s reference semantics, ctrl.jl:124)
is defined by replaying `body` on `ancilla = |0⟩` and reading off the `N`-port block; the cert guarantees
the ancilla factors out, so the `2^N × 2^N` block is well-defined. Gated at a small-`N` cap like `Perm`
(perm.jl:66), and F25 says set that cap from a **memory budget**, not the qubit ceiling.

---

## 2. Certificate mechanism (F1)

### 2.1 What is wrong with the status quo, precisely

The M5 Eager witness (`_clean_ancilla_assert!`, when.jl:217) flushes and reads the ancilla's
`|1⟩`-marginal on the *current statevector*. F1's counterexample: `alloc a=|0⟩; CNOT r→a; drop a`
passes with `r=|0⟩`, dephases `r` with `r=|+⟩`. The assert certifies the run, not the program.
Under `TracingContext` there is **no state at all** — the DAG is symbolic — so a state assertion is not
merely weak, it is *inapplicable*. M8 needs a witness that is a property of the **program text / DAG
structure**, universally quantified over inputs (F1's Eq: `(I_D⊗⟨a|)U(I_D⊗|0⟩)=0 ∀a≠0`).

Note the M5 assert is *not unsound as fail-fast* — it never accepts a dirty run. It is simply not a
*witness*. Our design keeps it, demoted to a debug cross-check (§2.5).

### 2.2 The certificate is an algebraic proof term with a closed constructor set

```julia
# ---- src/channel/cert.jl -----------------------------------------------

"A structural proof that a (sub-)DAG denotes a fixed-port unitary on its
 external ports, with every internal ancilla returned to |0⟩ for ALL inputs.
 Deeply immutable (frozen tuples/Perm; F28). The ONLY way to build one is via
 the constructors below — each pinned to a named physics theorem."
abstract type CleanCert end

struct NoAncilla   <: CleanCert end
struct PermClean   <: CleanCert; anc::NTuple{K,Int} where K end
struct MatchedPair <: CleanCert; compute::UnitaryBlock; inner::CleanCert end
struct SeqCert     <: CleanCert; a::CleanCert; b::CleanCert end
struct ParCert     <: CleanCert; a::CleanCert; b::CleanCert end
```

**Constructor 1 — `NoAncilla`.** The body allocates no ancilla; every node is an `ApplyN` of a fixed-port
`ProcessValue`. The composite is a product of unitaries ⇒ unitary, trivially. This covers the *common*
`when` body — teleportation Pauli corrections, kickback, `not!(dual(r))` (CZ), nested `when` — none of
which touch scratch. Soundness: closure of U(d) under multiplication.

**Constructor 2 — `PermClean`.** The body is a single `Perm` (or `ctrl^k` of one) with declared ancilla
ports. Bennett's `(★)` (bridge.jl:16-24; `docs/physics/bennett_1973_logical_reversibility.md`) guarantees
`P_f : |x⟩|t⟩|0⟩_anc ↦ |x⟩|t⊕f(x)⟩|0⟩_anc` for **every** input — the universal quantification is a
*theorem about the generator structure* (no output wire is ever read as a control), not a runtime
observation. And `ctrl(Perm)=Perm` (perm.jl:117) keeps the block in the zero-phase-freedom corner under
control. This is F2's "Perm-by-construction". The `oracle` path (bridge.jl) already produces exactly this
and already frees its scratch with the assert (`_free_clean!`, bridge.jl:279) — M8 replaces that per-run
assert with the `PermClean` term.

**Constructor 3 — `MatchedPair` (the general alloc constructor = `within`).** The *only* certificate
constructor that introduces a fresh ancilla. It is the surface/library combinator the PRD already
schedules for M8 (`within(V) do … end`, l.883):

```julia
within(C::UnitaryBlock) do        # "compute" C (allocs+computes scratch)
    M                             # "inner": acts on external wires, reads scratch ONLY as control
end   # ⇒ UnitaryBlock denoting  C† ∘ M ∘ C, cert = MatchedPair(C, cert(M))
```

Denotes `C† ∘ M ∘ C` (matching `_conj`, views.jl:201, and l.875's `V∘W∘V†` form). The uncompute is
`adjoint(C)` **literally the same value** (u2.jl adjoint / perm.jl:133 / algebra.jl:55 — exact, structural),
so whatever C wrote into scratch, C† erases it, for all inputs. The load-bearing side condition — *M does
not disturb scratch's computational value* — is enforced structurally: inside the `within` body, the
scratch handles are exposed only as `dual`-free **control** wires (`when(scratch) do … end`), never as an
`_act!` target; a write to a scratch handle is a guardrail-2-style aliasing error at trace time. Soundness:
Bennett compute/uncompute + the §4.2 narrowing law (§1.3). This is F1's "matched compute/uncompute" made a
*type*.

**Constructors 4/5 — `SeqCert`/`ParCert`.** Certificates compose along `∘` and `⊗`: a clean block ∘ a
clean block on the same ports is clean (ancillas are local to each); `⊗` likewise on disjoint ports.
This is what lets `certify` walk a `ChannelDAG` bottom-up.

### 2.3 How a `ChannelDAG` is promoted: `certify`

```julia
certify(dag::ChannelDAG) :: UnitaryBlock                     # or a LOUD error
```

`certify` refuses (loud `ArgumentError`, error policy S13, plan l.390) if the DAG contains any
`MeasureN`/`CasesN`/`NoiseN` (channel-level, §4.4) or any `AllocN` not matched to a certified `TraceN`.
Otherwise it folds the node stream into a `CleanCert` by the constructors above and returns
`UnitaryBlock{N}(frozen(dag), cert)`. Two acquisition routes for the cert, in priority order:

- **(Primary, recommended) combinator-carried.** `within`/`oracle`/plain action-op bodies emit their
  cert *directly* — `within` ⇒ `MatchedPair`, `oracle` ⇒ `PermClean`, ancilla-free ⇒ `NoAncilla`. No
  inference. This is sound by construction and is all M9's capstones need.
- **(Secondary, optional) syntactic matched-uncompute verifier.** For a raw flat op stream that
  hand-rolls `alloc; C; M; C†; dealloc`, a checker verifies the post-apex ops on each ancilla are the
  exact `adjoint`-reverse of the pre-apex ops (a palindrome over the ancilla's cone). Decidable, sound,
  but fragile against reordering — offered as a convenience, not the contract. (Ruling item R2.)

### 2.4 Why this is the right physics (isometry / coisometry / Stinespring)

`AllocN` is the Stinespring **dilation** step: environment birth, an isometry `V:H_D → H_D⊗|0⟩_A`
(§3.9; regions.jl header). `TraceN` is the environment **discard**. The composite `alloc → U → dealloc`
is unitary on `H_D` **iff** `U` maps `H_D⊗|0⟩_A` back into `H_D⊗|0⟩_A` for all data — F1's own
containment condition. A `MatchedPair` cert *is* a constructive proof of that containment: `C†∘M∘C`
maps `|ψ⟩|0⟩ ↦ C†M C|ψ⟩|0⟩`, and because M is control-only on the ancilla, `MC|ψ⟩|0⟩` stays in the image
of `C` restricted to `…|·⟩_A`, which `C†` returns to `…|0⟩_A`. The `PermClean` cert is the classical
shadow (`(★)`). Neither reads a state. This is the Stinespring contract F33 says the PRD currently omits,
supplied at exactly the boundary where it is needed.

### 2.5 The state check survives as a debug assertion

`_clean_ancilla_assert!` (when.jl:217, and the DM sibling:226) stays, guarded behind a debug flag / run
under Eager. Its new role, stated normatively: **it verifies the certificate was not lied to** — if a
`PermClean`/`MatchedPair` term is present but the ancilla is dirty at runtime, that is a *kernel bug*
(a mis-built cert), and the assert catches it fail-loud (CLAUDE.md #1, #9 skepticism). Defense in depth:
the structural cert is the *witness*; the state assert is the *cross-check*. This is F1's own fix sketch
("A statevector cleanliness assertion may remain as a debug check of a certificate, never as the
certificate itself") taken verbatim.

---

## 3. Pass contract (F3)

### 3.1 The observation, made exact

`Ad_U = Ad_{e^{iα}U}` (regions/ad.jl:6-8, `ker(Ad)=U(1)`), so `choi(U)=choi(e^{iα}U)`. Verified:
bare-matrix `isapprox(I, −I)` is `false`, but `Ad_I = Ad_{−I}` (both `ρ↦ρ`) so their Choi matrices are
**identical**. Meanwhile `C(I)=I₄` and `C(−I)=diag(1,1,−1,−1)` are `isapprox`-distinct. A pass that
preserves only Choi may silently insert or delete a global phase, and the moment its output reaches
`ctrl` (M8 `when`, M10 Grover/QPE, M12 QSVT) that phase becomes an observable relative phase — the exact
Cirq/Qiskit/pytket controlled-decomposition bug class (ad.jl:6-11; §4.2 l.854-873; Tang–Wright Thm 1.1).
The PRD's M8 law "streaming ≡ materialized, Choi-compared" (l.507, plan l.308) is **blind to it**.

### 3.2 The contract (mechanical, not conventional)

> **Pass contract (normative).** Let `P` be a pass. If `P` maps a `UnitaryBlock` to a `UnitaryBlock`
> (a *unitary-block pass*), then for all inputs `v`, `P(v) ≈ v` where `≈` is the **process-value
> equality** (u2.jl:192 / algebra.jl:79), which compares `denoted_matrix` **including the global phase**
> modulo only the physical ℤ₂ double cover. If `P` maps a `ChannelDAG` to a `ChannelDAG` and its domain
> contains a measurement/cases/noise barrier (a *channel pass*), it need only preserve Choi/diamond
> equivalence. A pass may NOT take a `UnitaryBlock` to a `ChannelDAG` (a type error).**

The crucial fact that makes this *free of new machinery*: **process `≈` is already phase-inclusive.**
`denoted_matrix(U2)=e^{iφ}U(q)` (u2.jl:160) carries the phase; `isapprox(::U2,::U2)` compares `circdist`
of the phases (u2.jl:197); the generic `isapprox(::ProcessValue,…)` compares full denoted matrices
(algebra.jl:79). So `gphase(α) ≉ I` (their denoted matrices differ) — the equality predicate that passes
must preserve is *the same one that already refuses to merge +I with −I* (u2.jl:178, the "π that ctrl
promotes to an observable Z"). The pass contract is therefore: **compare passes with the existing process
`≈`, never with `choi`.** No new equality is invented; F26's warning (don't put tolerance-`≈` into
`Base.==`) is respected because we use `isapprox`, not `==`.

Mechanical enforcement — three layers, mirroring the `ctrl` choke point (ctrl.jl:13-17):

1. **Type layer.** `apply_pass(p::UnitaryPass, b::UnitaryBlock)::UnitaryBlock` and
   `apply_pass(p::ChannelPass, d::ChannelDAG)::ChannelDAG` are the only signatures; the abstract
   supertypes `UnitaryPass`/`ChannelPass` partition the pass namespace. A `UnitaryPass` returning
   anything but a `UnitaryBlock` is a `MethodError`.
2. **Registry layer.** Every pass registers itself in a `const PASS_REGISTRY` at definition. A boot lint
   (test/runtests.jl, alongside the existing choke-point and physics-cite lints) asserts *every*
   `UnitaryPass` in the registry has a corresponding entry in the phase-faithful law-test battery
   (§3.3). A pass cannot ship without its phase test — the same "you cannot add a call site" discipline
   that fixed the controlled-phase bug for `ctrl`.
3. **Barrier layer.** `UnitaryPass` application is *structurally impossible* on a DAG containing a
   channel barrier, because such a DAG never promotes to a `UnitaryBlock` (§2.3). This is CLAUDE.md's
   "partition at measurement barriers; apply unitary-only methods ONLY to unitary blocks" made a type
   invariant rather than a discipline.

### 3.3 Named law tests (exact statements, PRD-style)

Let `apply(v)` mean lowering `v` on a small `EagerContext`/`density`, and `choi(f,n)` the one-run exact
Choi (plan l.377). Battery `V*` MUST include values whose *only* content is phase — `gphase(π)` (`=−I`),
`gphase(π/4)`, `S`, `T` — and their controlled forms, plus a `MatchedPair`/`PermClean` block with a live
ancilla.

- **`test_m8_pass_phase_faithful` (§4.2 / F3 — the strong contract).** For every `UnitaryPass P` in the
  registry and every `v ∈ V*`:
  `@test P(v) ≈ v`   (process `≈`, phase-inclusive; algebra.jl:79).
  *Rationale:* directly asserts the pass preserves the U(d) representative. One line, phase-exact,
  no simulation.

- **`test_m8_ctrl_survives_pass` (F3 — the observable consequence).** For every `UnitaryPass P` and
  `v ∈ V*`:
  `@test choi(apply∘ctrl, v) ≈ choi(apply∘ctrl, P(v))`.
  Controlling *promotes* any leaked phase to an observable, so even a Choi comparison now catches it.
  This is the test that would have caught the Qiskit #4949 "diagonal gate phase wrong only when used in
  a controlling circuit" bug.

- **`test_m8_stream_eq_materialized` (§3.5 l.507 — restated, strengthened).** For each certifiable
  `when` body `B` and small instance:
  `Vs = stream(B)` (M5 path, an applied channel) and `Vm = certify(trace(B))` (M8 path, a `UnitaryBlock`).
  `@test choi(apply, Vs) ≈ choi(apply, Vm)`   **AND**   `@test choi(apply, ctrl(Vm-as-applied)) ≈ choi(apply, ctrl(Vs-as-applied))`.
  The PRD's original law is the first conjunct; **F3's required addition is the second** — wrap both in
  `ctrl` before Choi-comparing, closing the phase hole.

- **`test_m8_channel_pass_choi_ok` (the negative control).** A `ChannelPass` over a DAG *with* a
  `MeasureN` barrier is asserted correct by Choi only, and asserted to *reject* (`MethodError`) when
  handed a `UnitaryBlock`. Confirms the partition is enforced, not merely documented.

---

## 4. PRD wording changes

### 4.1 §3.5 — the "witness" language (F1). Replace lines ~497–503 and guardrail 1 (l.474).

**Guardrail 1 (l.474), replace:**
> 1. The body must trace to a **unitary-witnessed** value: any cast, `ptrace!`, `cases`, or noise
>    channel inside `when` is a **loud error**.

**with:**
> 1. The body must trace to a value carrying a **structural clean-ancilla certificate** (§4.1a): a
>    state-independent proof — `NoAncilla`, `PermClean` (Bennett `(★)`), or `MatchedPair` (`within`
>    compute/uncompute) — that the composite is a fixed-port unitary on the surviving wires. Any cast,
>    `ptrace!`, `cases`, or noise channel inside `when` prevents certification and is a **loud error**.

**Eager bullet (l.497-503), replace the sentence:**
> Clean-ancilla exit (§3.9): assert the ancilla's |1⟩-block norm is exactly 0 before dealloc — cheap
> on a statevector. … the §3.9 witness is exactly that proviso

**with:**
> Clean-ancilla exit (§3.9): the **certificate** (§4.1a) is the witness — it proves, for *all* inputs,
> that `U` returns the ancilla to `|0⟩` in the control-firing branch, which is exactly the compute–
> uncompute proviso. On Eager the runtime `|1⟩`-marginal check is retained as a **debug cross-check
> that the certificate was honoured** — sound fail-fast per run, never itself the witness (a single
> input state cannot certify a universally-quantified containment condition).

### 4.2 §4.1 — `UnitaryDAG` (F2). Replace the bullet at l.823–824.

> - `UnitaryDAG` — a `Channel`-style DAG carrying a unitarity witness (produced by tracing `when`
>   bodies and library circuits).

**with:**
> - `ChannelDAG` — the effect-typed channel IR (typed quantum in/out ports that need not match, plus
>   classical token ports); nodes carry process values, never gate names. It is **not** a process
>   value: it sits on the channel level of §4.4 and `ctrl(::ChannelDAG)` is unrepresentable (P4).
> - `UnitaryBlock{N}` — a `ChannelDAG` **certified** (`certify`) to denote a fixed-port unitary on its
>   `N` surviving wires: `N` in-ports `== N` out-ports, every internal allocation matched by a
>   certified deallocation (§4.1a). Only `UnitaryBlock` is a process value; only it may be controlled.
>   Allocation is an isometry and deallocation a coisometry — the composite is unitary on surviving
>   ports *exactly when the clean-ancilla certificate holds*, which is why the boolean `unitary=true`
>   flag is rejected.

Add a new short subsection **§4.1a "The clean-ancilla certificate"** stating the three constructors and
the §4.2/Bennett soundness (the content of §2 above).

### 4.3 §4.2 — pass correctness (F3). Add to the "normative laws" list after l.891.

> - **Passes preserve the phase-fixed representative, not merely the channel.** A pass on a
>   `UnitaryBlock` must satisfy `P(v) ≈ v` under process-value equality (phase-inclusive, mod the ℤ₂
>   double cover); Choi/diamond equivalence is permitted **only** for passes on a `ChannelDAG` crossing
>   a measurement/cases/noise barrier. The streaming≡materialized law (§3.5) is tested with **both**
>   operands `ctrl`-wrapped, because `ctrl` promotes any leaked global phase to an observable
>   (Tang–Wright Thm 1.1). Enforced by a pass registry + boot lint, mirroring the `ctrl` choke point.

### 4.4 Plan (F35). M8 bullet (plan l.298-322): rename `UnitaryDAG`→`ChannelDAG`+`UnitaryBlock`,
add "certify + CleanCert" and "phase-faithful pass registry/lint" as explicit deliverables, and add the
`test_m8_ctrl_survives_pass` and strengthened `test_m8_stream_eq_materialized` to the named-test list.

---

## 5. Risks, alternatives, open questions (Tobias-level rulings)

**R1 — Is `MatchedPair`/`within` expressive enough to certify every *intended* clean `when` body?**
It certifies exactly the compute/uncompute and Perm shapes — which is everything the current surface
inside `when` can *legitimately* produce (action ops + nested `when` + Bennett + `within`). A body that
allocates scratch and cleans it by some *non-matched* unitary trick (e.g. a measurement-free uncompute
that isn't literally `adjoint(C)`) would be refused. *Risk:* over-refusal. *Alternative:* a semantic
certifier that checks the containment condition numerically on a spanning set — but that is a state check
in disguise and reintroduces F1. **Recommendation:** ship the three structural constructors; treat any
refused body as a user error pointing at `within`. **Ruling:** accept structural-only certification for M8?

**R2 — Combinator-carried cert vs syntactic inference (§2.3).** Primary path needs no inference; the
optional palindrome verifier adds convenience at the cost of a fragile matcher. **Recommendation:**
M8 ships combinator-carried only; file the verifier as a follow-on bead. **Ruling:** confirm scope.

**R3 — Where does `within`/`with_ancilla` live in the layer table (§2 / F12)?** PRD §4.2 already calls
`within` a *library* combinator, but it is now the *only* certifiable ancilla-introduction form inside
`when`, which brushes against F12 (prep-inside-`when` is simultaneously required and its cast banned).
**Options:** (a) `within` is `public` kernel/library, and a bare `QBool(false)` inside `when` is legal
only when the tracer can pair it into a `MatchedPair` (else loud error naming `within`); (b) add a
dedicated `with_ancilla` surface spelling (an 8th construct — a real surface-vocabulary change, needs its
own gate). **Recommendation:** (a) — keep the seven surface constructs; `within` stays `public`.
**Ruling required** (touches the surface-construct count, CLAUDE.md #11).

**R4 — `UnitaryBlock{N}` (square) vs `UnitaryBlock{InPorts,OutPorts}` (F2's literal phrasing).** I argue
square, with the isometric asymmetry confined to `ChannelDAG.qin/qout`. **Recommendation:** square `{N}`.
**Ruling:** confirm we never need a non-square "unitary" (we do not — a non-square map is an isometry, a
channel-level object).

**R5 — Rename `UnitaryDAG`.** The plan/PRD name is `UnitaryDAG`; a certified block may have zero internal
nodes (a lifted `U2`), so "DAG" misleads and "block" matches CLAUDE.md's Channel-IR wording.
**Recommendation:** adopt `ChannelDAG`/`UnitaryBlock`. **Ruling:** naming.

**R6 — Deep immutability (F28).** `ChannelDAG.nodes` and `CleanCert` must be frozen (tuples/`Perm`, no
live `Vector` aliasing) or caching, `ctrl`, and pass results become unsound under later mutation.
**Recommendation:** freeze on `certify`; keep mutable *builders* separate from frozen values (F28 fix
sketch). Low risk, flagged for the implementer.

**R7 — `denoted_matrix(::UnitaryBlock)` cost (F25).** Reference semantics for law tests replay on
`ancilla=|0⟩` at `2^N`; the cap must be a **memory budget**, not the 30-qubit pure ceiling. Randomized
reference-assisted (Choi on random probes) for larger blocks. **Recommendation:** adopt F25's budgeted
cap in `kernel/numerics.jl`. No ruling needed; noting for the test harness.

**Out of scope (separate beads, flagged so the certificate design does not silently assume them):** F4/F6
(classical-control IR, `cases` linear join / persistent records) — `CasesN` is typed here but its join
semantics is its own gate; F5 (DM `Bool` → token); F7 (`QMod` padded permutation). The certificate work
does not depend on their resolution, but `certify`'s refusal of `CasesN`/`MeasureN` is the seam where
they will attach.

---

## Appendix — grounding index

- Isometry/coisometry, Stinespring dilation as scope: PRD §3.9; regions.jl header; F2/F33.
- Compute/uncompute, `(★)`, clean ancilla: `docs/physics/bennett_1973_logical_reversibility.md`;
  bridge.jl:16-24, 279.
- `ctrl` homomorphism, `ctrl(Perm)=Perm`, non-distribution over `⊗`, control-scope reassociation
  (`within`, `V∘W∘V†`): PRD §4.2 l.843-891; ctrl.jl; perm.jl:117; ad.jl:279-292;
  `docs/physics/delorme_control_as_constructor.md`.
- Global phase becomes physical under control: PRD §4.2 l.854-873; ad.jl:196-227 (the `p(control,φ)`
  line); `docs/physics/tang_wright_2025_controlled_unitaries.md` Thm 1.1. Verified numerically:
  `isapprox(C(I),C(−I))=false` while `Ad_I=Ad_{−I}`.
- Process `≈` is phase-inclusive mod ℤ₂; `==` structural: u2.jl:160,178,192; algebra.jl:79; F26.
- `when` guardrails, streaming path, control stack: when.jl; abstract.jl:160-206.
