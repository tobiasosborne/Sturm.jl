# M8 Design Gate (bead 5hr7) — Typed channel IR, structural clean-ancilla certificate, phase-preserving passes

**Bead:** `5hr7` (P0 — gates all M8 code) · **Round:** 3+1 design gate · **Status:** canonical synthesized design (implementer's ruling)
**Answers review findings:** F1 (state-dependent `when` witness), F2 (`UnitaryDAG` port typing), F3 (Choi-blind pass correctness) from
`docs/design/prd-v2-review-gpt56-2026-07-19.md`. Touches F9, F10, F12, F25, F26, F28, F33.

**Provenance:** synthesized from two blind proposals — **A** = `m8-5hr7-proposal-A-codex.md` (codex gpt-5.6 xhigh),
**B** = `m8-5hr7-proposal-B-claude.md` (Claude Opus). Verbatim copies are archived beside this file (M7 pattern).
A per-piece provenance table is in §9. This is a **design** document: no source code and no PRD edits land here — the PRD
replacement blocks in §7 are staged for paste *after Tobias rules* on §8.

> **Line-number note.** PRD/plan/source line numbers drift between sessions. Every anchor below was re-verified against the
> working tree at synthesis time and is quoted by **content** (section + landmark), not just number. Where a proposal's cited
> line had drifted, the corrected content anchor is used.

---

## 0. Thesis

F1, F2, F3 are one defect viewed three ways. A `when` body (or a traced library circuit) is a **channel** while it is being
built: it allocates ancillas (isometry `ι|ψ⟩ = |ψ⟩|0⟩_A`), acts, and deallocates (a coisometry — *not* unitary or even CPTP on
the enlarged space, F2). It becomes a **process value** — the only kind of thing `ctrl` may touch (P4) — **only** when a
*state-independent, structural* proof discharges the clean-ancilla precondition (F1). Once it is a process value, every rewrite
over it must preserve the **U(d) representative including global phase**, because `ctrl` promotes that phase to observable
physics (`ctrl(gphase(α)) = diag(1,1,e^{iα},e^{iα})`; Tang–Wright Thm 1.1) and Choi comparison — which quotients U(1) at `Ad` —
cannot see it (F3).

The single object that closes all three holes is a **certificate**: an algebraic proof term, minted only by a closed set of
physics-grounded constructors, that (a) *types* the promotion `ChannelDAG → UnitaryBlock` (F2), (b) *is* the clean-ancilla
witness with no state required (F1), and (c) makes `ctrl(UnitaryBlock)` sound by the §4.2 control-scope-reassociation law (F3).
Passes are then constrained to preserve the phase-inclusive process equality `≈` (which the shipped kernel already implements),
enforced mechanically by a pass registry + boot lint that mirrors the `ctrl` choke point.

Everything fits the shipped kernel. `UnitaryBlock <: ProcessValue`, so it inherits the M1 algebra (`∘`, `⊗`, `adjoint`,
`denoted_matrix`, `≈`) for free — the `ProcessValue` docstring already anticipates this ("when `UnitaryDAG <: ProcessValue`
lands, it inherits the generic laws for free", `src/kernel/u2.jl` ProcessValue docstring) — and `ctrl(::UnitaryBlock)` is the
**single** method M8 adds to the choke point, exactly as `src/kernel/ctrl.jl`'s header already promises ("M8 adds exactly one
method, `ctrl(::UnitaryDAG)`, with no change to existing code").

---

## 1. Type design (F2)

### 1.1 The split — two nominal types on two levels of the §4.4 stratification

A boolean `unitary=true` flag on a DAG (current PRD §4.1 `UnitaryDAG` bullet) throws away the hard-won `ProcessValue` typing and
encodes neither port equality nor the ancilla precondition (F2). Replace it with two disjoint types:

- **`ChannelDAG`** — the effect-typed channel IR. **Not** a `ProcessValue`. `ctrl(::ChannelDAG)` is a deliberate `MethodError`
  (P4: control on a non-unitary effect is *unrepresentable*, §4.4), which the shipped no-catch-all `ctrl` discipline gives for
  free (`src/kernel/ctrl.jl`: "NO `ctrl(::ProcessValue)` catch-all … an unhandled kind is a `MethodError`").
- **`UnitaryBlock{N}`** — a `ChannelDAG` **certified** to denote a fixed-port unitary on its `N` surviving wires. `<: ProcessValue`;
  the one value the M8 `ctrl` method wraps.

This is the mechanical form of §4.4: control is undefined on channel equivalence classes because those classes have already
quotiented the phase that control needs (Bădescu–Panangaden's controlled-alternation obstruction,
`docs/physics/badescu_panangaden_quantum_alternation.md`).

### 1.2 Typed ports — SSA edges with resource lineage (from A), effect-node vocabulary (from B)

The IR needs graph-local port identities distinct from the runtime `WireID` (which names a live resource in one execution
context, `src/types/wire.jl`). A `PortID` names an SSA edge / local slot in a reusable graph:

```julia
# ---- src/channel/ports.jl : graph-local port identity ------------------
struct PortID; id::Int end                      # an SSA edge in a reusable graph

abstract type PortKind end
struct QuantumPort  <: PortKind; width::Int end # a quantum wire-bundle; width is runtime DATA
struct ClassicalPort<: PortKind; ttype::DataType end  # a classical token port (ClassicalBit/Int)

struct Port; id::PortID; kind::PortKind; lineage::Int end  # lineage = physical-resource identity
```

**Resource lineage (A, load-bearing).** A unitary block must be an *endomorphism on the same ordered physical boundary*. Width
equality is **not** identity equality — B's `UnitaryBlock{N}` invariant "qin == qout as widths" is necessary but insufficient:
it cannot tell "same handle after a unitary" from "input discarded and a same-shaped fresh output returned". Each `Port` carries a
`lineage` tag; the sealer's endomorphism check compares *lineage*, not width. A unitary body that keeps a surface handle across an
in-place op versions it as distinct input/output SSA edges sharing one lineage. (This closes the gap in B §1.2 and grounds test
`M8.PORT.ENDOMORPHIC-BLOCK`.)

Nodes are **effect-typed** (B's vocabulary — shorter than A's `ApplyNode/AllocateZeroNode/…` and matches CLAUDE.md's
"Channel IR vs Unitary Methods" barrier naming), never gate-named (the plan warns "do not import the [v0.1] node vocabulary"):

```julia
# ---- src/channel/dag.jl : the CHANNEL IR (NOT a ProcessValue) ----------
abstract type Node end
struct ApplyN   <: Node; v::ProcessValue;   ports::NTuple{K,PortID} where K end  # unitary application
struct AllocN   <: Node; out::PortID end                                          # isometry |ψ⟩↦|ψ⟩|0⟩ (§3.9)
struct TraceN   <: Node; in::PortID; cert::Union{Nothing,CleanCert} end           # coisometry / ptrace
struct MeasureN <: Node; in::PortID; out::PortID end                              # instrument (qc cast) — BARRIER
struct CasesN   <: Node; sel::PortID; branches::NTuple{B,ChannelDAG} where B end  # Kleisli join (i4ri) — BARRIER
struct NoiseN   <: Node; kraus::KrausFamily; ports::NTuple{K,PortID} where K end  # channel value — BARRIER

struct ChannelDAG
    nodes :: NTuple{M,Node} where M   # topologically ordered; FROZEN on construction (F28)
    qin   :: NTuple{A,Port} where A   # quantum inputs
    qout  :: NTuple{Bp,Port} where Bp # quantum outputs — need NOT equal qin (alloc adds, trace removes)
    cout  :: NTuple{C,Port} where C   # classical/token outputs (measurement/cases)
end
```

`MeasureN`/`CasesN`/`NoiseN` are exactly the barriers unitary passes must never cross (CLAUDE.md "Channel IR vs Unitary
Methods"). Their presence is what disqualifies a sub-DAG from promotion (§2.3). **Seam with the i4ri round:** `CasesN` is typed
here but its Kleisli-join semantics (tokens / correlation record) is the sibling `i4ri` gate — `certify` *refuses* any DAG
containing a `CasesN`/`MeasureN`/`NoiseN`, which is precisely the boundary where the classical-control IR attaches. `UnitaryBlock`
never contains an instrument node.

**ChannelDAG invariants** (each an SSA/linearity discipline): every node consumes existing edges and creates fresh ones; each edge
has exactly one producer; quantum ownership is linear (classical edges copy per the i4ri contract); declared outputs are the live
edges after the last node; allocation changes the quantum signature by an isometry, discard by partial trace; `ChannelDAG` is
**not** `<: ProcessValue` and has **no** `ctrl` method.

### 1.3 `UnitaryBlock{N}` — the promoted, opaque endomorphism

```julia
# ---- src/kernel/unitary_block.jl : joins the ProcessValue tree ---------
"""
    UnitaryBlock{N} <: ProcessValue

A fixed-port unitary on `N` *external* (surviving) wires, obtained by CERTIFYING a `ChannelDAG`.
The internal alloc/act/dealloc structure is EXISTENTIALLY HIDDEN behind `cert`. `N` in-ports ==
`N` out-ports (a unitary is SQUARE — F2's port equality), and the ancilla ports are internal,
discharged by `cert`. `<: ProcessValue`, so it inherits ∘/⊗/adjoint/denoted_matrix/≈ generically.
It is the ONE value the M8 `ctrl` method wraps.

INVARIANTS (checked at seal, frozen after — F28):
  • nwires(::UnitaryBlock{N}) == N == length(boundary)  (external ports only)
  • boundary INPUT lineage == boundary OUTPUT lineage, in order (endomorphism — §1.2)
  • body contains ONLY ApplyN/AllocN/TraceN — no Measure/Cases/Noise (those stay channel-level)
  • every AllocN is matched by a TraceN whose cert is non-nothing, and `cert` witnesses the
    composite is unitary on the N ports for ALL inputs (§2)
"""
struct UnitaryBlock{N} <: ProcessValue
    boundary :: NTuple{N,Port}   # ordered external ports; lineage in == lineage out
    body     :: ChannelDAG       # frozen; qin/qout lineage == boundary; cout empty
    cert     :: CleanCert        # the structural witness (§2)
end

nwires(::UnitaryBlock{N}) where {N} = N
```

**`{N}` is a type parameter, and the block is SQUARE — both proposers independently overrode F2's tentative
`{InPorts,OutPorts}`.** B: "a unitary is square … F2's two-parameter form is right for the *isometry fragments* inside a
`ChannelDAG`, and that asymmetry lives on `ChannelDAG.qin/qout`, not the promoted block." A: a single boundary is "stronger than
`UnitaryBlock{InPorts,OutPorts}`: a controllable process value must be an endomorphism on the same ordered physical boundary." The
synthesis keeps **both** virtues: `N` is the type parameter (type-stable `ctrl`/`⊗`/`apply!` width dispatch, mirroring `QInt{W}`,
CLAUDE.md Julia-conv 5) **and** the boundary is a runtime `NTuple{N,Port}` carrying A's resource lineage (rigorous identity).

**Width discipline (reconciling A's runtime-width point with B's type-param).** The *external* boundary `N` is small and bounded
(a `when`-body boundary is a handful of wires) — cheap as a type parameter. The *internal* `Perm`/oracle ancilla widths, which
can be large, stay **runtime data** inside the frozen `body` (matching the vector-application seam in `src/orkan/ad.jl`), so we
never specialize a distinct Julia method per oracle width. No conflict: type-param the boundary, runtime the interior.

### 1.4 `ctrl(::UnitaryBlock)` — the one added method, and why it is sound

```julia
# src/kernel/ctrl.jl  (THE ONLY edit to the choke-point file)
ctrl(b::UnitaryBlock) = _ctrl(1, b)        # → Ctrl{UnitaryBlock{N}}, exactly like ctrl(::Tensor)
```

Lowering adds one structurally-recursive `_apply_controlled!` method under `src/orkan/` (no catch-all), and **this is where the
certificate earns its keep**: under control, `AllocN` and `TraceN` stay **uncontrolled**; only `ApplyN`s are control-wrapped.

Soundness is the **§4.2 control-scope-reassociation law** (a *named kernel law*, already ruled, PRD §4.2:
`(1 ⊗ V) ∘ ctrl(W) ∘ (1 ⊗ V†) == ctrl(V ∘ W ∘ V†)` when `V` acts only outside the control) together with the `within`
combinator the PRD already schedules for M8. For a matched compute/use/uncompute body `C† ∘ M ∘ C` (with `V = C†`, `W = M`):

> `ctrl(C† ∘ M ∘ C) == (1 ⊗ C†) ∘ ctrl(M) ∘ (1 ⊗ C)`

so the ancilla still round-trips `|0⟩ → … → |0⟩` in **both** control branches (control = 0: `ctrl(M) = I`, so `C†∘C = I` on the
ancilla; control = 1: `C†` uncomputes what `C` wrote). Cleanliness is **algebraic, not state-dependent** — exactly the property
F1 says the `|1⟩`-marginal assert lacks. `denoted_matrix(::UnitaryBlock{N})` replays `body` on `ancilla = |0⟩` and reads off the
`2^N × 2^N` block (the cert guarantees the ancilla factors out); gated at a **memory-budget** cap (F25 — not the pure-state qubit
ceiling), with randomized reference-assisted probes above it.

This equals A's Eq. (9)/(10): `W̃ = |0⟩⟨0|_C ⊗ I_{SA} + |1⟩⟨1|_C ⊗ W` leaves `A` in `|0⟩` in both branches (trivially in the
zero branch, by the containment theorem in the firing branch), so `(I_C ⊗ ι†) W̃ (I_C ⊗ ι) = ctrl(U)`. The two proposals give the
same soundness argument in two notations; both are correct.

---

## 2. Certificate mechanism (F1)

### 2.1 What is wrong with the status quo, precisely

The M5 Eager witness `_clean_ancilla_assert!` (`src/surface/when.jl`) flushes and reads the ancilla's `|1⟩`-marginal on the
**current statevector**. F1's counterexample: `alloc a=|0⟩; a ⊻= r; drop a` passes with `r = |0⟩`, dephases `r` with `r = |+⟩`.
The assert certifies the *run*, not the *program*. Under `TracingContext` there is **no state at all** — the DAG is symbolic — so
a state assertion is not merely weak, it is *inapplicable*. M8 needs a witness that is a property of the **program structure**,
universally quantified over inputs: `(I_D ⊗ ⟨a|) U (I_D ⊗ |0⟩) = 0 ∀ a ≠ 0`, equivalently `U(H_D ⊗ |0⟩_A) ⊆ H_D ⊗ |0⟩_A` (F1's
containment condition; A's Eq. (3)/(4)).

The M5 assert is **not unsound as fail-fast** — it never *accepts* a dirty run. It is simply not a *witness*. It survives,
demoted to a debug cross-check (§2.5). This is F1's own fix sketch verbatim ("A statevector cleanliness assertion may remain as a
debug check of a certificate, never as the certificate itself").

### 2.2 The certificate is an algebraic proof term with a closed constructor set

**The meta-theorem (A's framing, adopted as the soundness spec).** A `CleanCert` is *valid* iff it proves the universal
containment `(I − ιι†) W ι = 0` for the block's frozen phase-fixed program `W`. Every constructor below is a proof *rule* that
discharges this spec on a structural fragment; the checker validates rules against exact node identities, port roles, and frozen
process values — **no `isapprox`, statevector, density matrix, Choi matrix, or sampled execution participates in constructing a
certificate.**

**The constructor set (B's concrete, idiomatic form, extended with A's two missing combinators).**

```julia
# ---- src/channel/cert.jl : structural proof terms (deeply immutable) ---
abstract type CleanCert end

struct NoAncilla   <: CleanCert end                                  # body allocates no ancilla
struct PermClean   <: CleanCert; anc::NTuple{K,PortID} where K end    # Bennett (★): Perm-by-construction
struct MatchedPair <: CleanCert; compute::UnitaryBlock; inner::CleanCert end  # within: C†∘M∘C
struct SeqCert     <: CleanCert; a::CleanCert; b::CleanCert end       # ∘ of two clean blocks
struct ParCert     <: CleanCert; a::CleanCert; b::CleanCert end       # ⊗ on disjoint ports
struct AdjointCert <: CleanCert; src::CleanCert end                   # (A) adjoint of a clean block
struct XportCert   <: CleanCert; src::CleanCert; rewrite::Symbol end  # (A) pass-transported cert
```

**1 — `NoAncilla`.** No ancilla is allocated; every node is an `ApplyN` of a fixed-port `ProcessValue`. The composite is a
product of unitaries ⇒ unitary. Covers the *common* `when` body — teleportation Pauli corrections, kickback, `not!(dual(r))`
(CZ), nested `when` — none of which touch scratch. Soundness: closure of U(d) under multiplication.

**2 — `PermClean`.** The body is a single `Perm` (or `ctrl^k` of one) with declared ancilla ports. Bennett's `(★)`
(`src/bennett/bridge.jl`; `docs/physics/bennett_1973_logical_reversibility.md`) guarantees
`P_f : |x⟩|t⟩|0⟩_anc ↦ |x⟩|t⊕f(x)⟩|0⟩_anc` for **every** input — a *theorem about the generator structure* (no output wire is
ever read as a control), not a runtime observation. `ctrl(Perm) = Perm` (`src/kernel/perm.jl`) keeps the block in the
phase-free corner under control. This is F2's "Perm-by-construction". The `oracle` path already produces exactly this and today
frees scratch with the per-run assert (`_free_clean!`, `src/bennett/bridge.jl`) — **M8 replaces that per-run assert with the
`PermClean` term.**

**3 — `MatchedPair` (the general alloc constructor = `within`).** The *only* constructor that introduces fresh ancilla. It is the
combinator the PRD already schedules for M8 ("`within(V) do … end` lands"):

```julia
within(C::UnitaryBlock) do   # "compute" C: allocs + computes scratch
    M                        # "inner": acts on external wires, reads scratch ONLY as control
end   # ⇒ UnitaryBlock denoting C† ∘ M ∘ C, cert = MatchedPair(C, cert(M))
```

Denotes `C† ∘ M ∘ C` — matching the shipped `_conj(V, g) = adjoint(V) ∘ g ∘ V` (`src/kernel/views.jl`) and the §4.2 law's
`V∘W∘V†` form. The uncompute is `adjoint(C)` — **literally the same value reversed** (exact/structural: `Base.adjoint(::Perm)`
reverses the generator list, `Base.adjoint(::Seq)` = `B†∘A†`), so whatever `C` wrote into scratch, `C†` erases, for all inputs.

The load-bearing side condition — *`M` does not disturb scratch's computational value* — is enforced **structurally** by the
**port-role / effect-footprint analysis** (A's mechanism, which B gestured at): each process leaf declares which of its ports it
*targets* vs reads as *control*:

- `U2` targets its sole port.
- `Ctrl{V}` treats leading ports as read-only controls, delegates target roles to `V`.
- `Perm` derives control/target roles per `MCX`.
- `Tensor` unions disjoint footprints; `Seq` composes them.
- **Unknown kinds conservatively "target every port"** unless they carry an audited effect trait — fail-closed.

Inside the `within` body, scratch handles must appear **only as control** (`when(scratch) do … end`), never as an `_act!`
target; a write to a scratch handle is a guardrail-2-style aliasing error at trace time. Soundness: Bennett compute/uncompute +
the §4.2 narrowing law (§1.4). This is F1's "matched compute/uncompute" made a *type*.

**4/5 — `SeqCert`/`ParCert`.** Certificates compose along `∘` and `⊗`: a clean block ∘ a clean block on the same ports is clean
(ancillas local to each); `⊗` likewise on disjoint ports. This lets `certify` fold a `ChannelDAG` bottom-up.

**6 — `AdjointCert` (from A).** If `W` leaves the clean subspace invariant then unitarity forces equality (not mere inclusion), so
`W†` also leaves it invariant. `adjoint(::UnitaryBlock)` reverses the program, adjoints every `ApplyN`, and re-allocates/releases
scratch at the reversed ends; the cert is `AdjointCert(src)`. B lacked an explicit adjoint cert — this is a genuine gap A closes.

**7 — `XportCert` (from A's `TransportedCertificate`).** An exact pass rewrite (§3) that preserves the boundary transports the
certificate as `XportCert(src, rule)`. Without this, no certified block could survive a pass. B lacked it; A supplies it.

> **On A's finer proof-language (Z0 / INV / CUU / BENNETT).** A's rules map onto this set: Z0 (untouched-zero) is the port-role
> analysis feeding `NoAncilla`/`MatchedPair`; INV (exact adjacent compute/cancel, e.g. `not!(a); not!(a)`) is the degenerate
> `MatchedPair(C = not!(a), M = I)`; CUU is `MatchedPair`; BENNETT is `PermClean`. They are the **same design at two altitudes**.
> We ship B's named constructor set (idiomatic Julia, maps to `within`/`oracle`) and adopt A's port-role analysis as the shared
> checker mechanism. The universal invariant `(I−ιι†)Wι=0` is the soundness spec each constructor discharges.

### 2.3 Promotion: `certify`

```julia
certify(dag::ChannelDAG) :: UnitaryBlock    # or a LOUD ArgumentError (fail-fast, CLAUDE.md #1)
```

`certify` refuses loudly if the DAG contains any `MeasureN`/`CasesN`/`NoiseN` (channel-level, §4.4) or any `AllocN` not matched
to a certified `TraceN`, or if boundary lineage in ≠ lineage out (not an endomorphism). Otherwise it folds the node stream into a
`CleanCert` and returns `UnitaryBlock{N}(boundary, frozen(dag), cert)`. Two acquisition routes, in priority order:

- **(Primary) combinator-carried.** `within` ⇒ `MatchedPair`, `oracle` ⇒ `PermClean`, ancilla-free ⇒ `NoAncilla`. No inference —
  sound by construction; all M9 capstones need only this.
- **(Secondary, deferred) syntactic matched-uncompute verifier.** For a raw flat `alloc; C; M; C†; dealloc` stream, a checker
  verifies the post-apex ops on each ancilla are the exact `adjoint`-reverse of the pre-apex ops (a palindrome over the ancilla's
  cone). Decidable and sound, but fragile against reordering — offered as a follow-on bead, not the M8 contract (ruling R4).

### 2.4 Why this is the right physics (isometry / coisometry / Stinespring)

`AllocN` is the Stinespring **dilation** step: environment birth, an isometry `ι : H_D → H_D ⊗ |0⟩_A` (§3.9; the region *is* the
Stinespring boundary). `TraceN` is the environment **discard** (coisometry `ι† = I ⊗ ⟨0|`), valid only on the reachable image.
The composite `alloc → W → dealloc` is unitary on `H_D` **iff** `W` maps `H_D ⊗ |0⟩_A` back into itself for all data — F1's own
containment. A `MatchedPair` cert *is* a constructive proof: `C†∘M∘C` maps `|ψ⟩|0⟩ ↦ C†MC|ψ⟩|0⟩`, and because `M` is control-only
on the ancilla, `MC|ψ⟩|0⟩` stays in the image of `C` restricted to `…|·⟩_A`, which `C†` returns to `…|0⟩_A`. `PermClean` is the
classical shadow `(★)`. Neither reads a state. Setting `U = ι† W ι`, unitarity of `W` + subspace invariance make `U` unitary on
`H_D`, and `Tr_A[W(ρ⊗|0⟩⟨0|)W†] = UρU†`. This is exactly the Stinespring dilation contract F33 says the PRD omits, supplied at
the boundary where it is needed.

### 2.5 The state check survives as a debug assertion

`_clean_ancilla_assert!` (Eager and DM siblings, `src/surface/when.jl`) stays, guarded behind a debug flag / Eager run. Its new
normative role: **it verifies the certificate was not lied to.** If a `PermClean`/`MatchedPair` term is present but the ancilla is
dirty at runtime, that is a *kernel bug* (a mis-built cert), and the assert catches it fail-loud (CLAUDE.md #1, #9). Defense in
depth: the structural cert is the *witness*; the state assert is the *cross-check*. `CLEAN_EPS` is a numerical diagnostic
tolerance, never a theorem threshold.

The adversarial F1 program `a = QBool(false); a ⊻= r; # drop a` must fail **structurally** even when the current input is `r=|0⟩`
(where the debug marginal is 0): the checker sees an unmatched target write to `a` (an `AllocN` with no matched certified
`TraceN`) and rejects. Program acceptance no longer depends on runtime input. Because a streaming executor may discover the
unmatched pattern only at frame exit, some Eager effects will already have run before the seal fails — the failure topology is a
Tobias ruling (R2).

---

## 3. Pass contract (F3)

### 3.1 The observation, made exact and verified

`Ad_U = Ad_{e^{iα}U}` (`ker(Ad) = U(1)`, `src/orkan/ad.jl`), so `choi(U) = choi(e^{iα}U)`. **Verified numerically at synthesis:**
bare-matrix `isapprox(I, −I)` is `false`, but `Ad_I = Ad_{−I}` (both `ρ↦ρ`) so their Choi matrices are *identical*; meanwhile
`C(I) = I₄` and `C(−I) = diag(1,1,−1,−1)` are `isapprox`-distinct. A pass that preserves only Choi may silently insert/delete a
global phase, and the moment its output reaches `ctrl` (M8 `when`, M10 Grover/QPE, M12 QSVT) that phase becomes an observable
relative phase — the exact Cirq/Qiskit/pytket controlled-decomposition bug class. The PRD's M8 law "streaming ≡ materialized,
Choi-compared" is **blind to it** (F3).

### 3.2 The contract (two-tier — B's default + A's escape hatch)

> **Pass contract (normative).** Let `P` be a pass.
>
> 1. **Unitary-block pass** (`UnitaryBlock → UnitaryBlock`): for all inputs `v`, either
>    (a) **`P(v) ≈ v`** under the shipped **process-value equality** (phase-inclusive, mod only the physical ℤ₂ double cover); or
>    (b) `P` returns an explicit **phase delta** `(candidate, δ)` proving `U_candidate = e^{iδ} U_v`, and the trusted `commit`
>    reattaches `e^{−iδ}` (a `gphase(−δ)` on one boundary qubit) **before** the result may become a `UnitaryBlock`, so the
>    committed value again satisfies `≈ v`.
> 2. **Channel pass** (`ChannelDAG → ChannelDAG`, domain crosses a measurement/cases/noise barrier): need only preserve
>    Choi/diamond equivalence.
> 3. A pass may **not** take a `UnitaryBlock` to a `ChannelDAG` (a type error).

**Why tier 1(a) needs no new machinery (B's key finding — verified).** Process `≈` is *already* phase-inclusive:
`denoted_matrix(::U2) = e^{iφ}U(q)` carries the phase; `isapprox(::U2,::U2)` compares the phase via `circdist`; the generic
`isapprox(::ProcessValue,…)` (`src/kernel/algebra.jl`) compares full denoted matrices. So `gphase(α) ≉ I`, and the predicate a
pass must preserve is *the same one that already refuses to merge +I with −I* (`src/kernel/u2.jl` isapprox: "the π that `ctrl`
promotes to an observable Z"). The contract is therefore: **compare passes with the existing process `≈`, never with `choi`.** No
new equality is invented; F26's warning (don't put tolerance-`≈` into `Base.==`) is respected because we use `isapprox`, not `==`.

**Why tier 1(b) exists (A's forward-looking mechanism).** For M8's three planned passes (reassociation, view-fusion, U2-fusion)
the phase delta is analytically `δ = 0`, so 1(a) suffices. Tier 1(b) is the sound escape hatch for a *future* synthesis / QSVT /
external pass that legitimately produces a phase-shifted candidate: it must **report and reattach** the phase, never silently set
`δ = 0`, infer it from Choi data, or drop it because the uncontrolled channel is unchanged. On an `n`-qubit boundary,
`(e^{−iδ}I₂) ⊗ I_{2^{n-1}} = e^{−iδ}I_{2^n}`, routed through the existing `ctrl(gphase(…))` path. (Zero-port scalar blocks are a
gap here — ruling R7.)

### 3.3 Mechanical enforcement — three layers mirroring the `ctrl` choke point

1. **Type layer.** `apply_pass(::UnitaryPass, ::UnitaryBlock)::UnitaryBlock` and
   `apply_pass(::ChannelPass, ::ChannelDAG)::ChannelDAG` are the only signatures; abstract supertypes `UnitaryPass`/`ChannelPass`
   partition the namespace. A `UnitaryPass` returning anything but a `UnitaryBlock` is a `MethodError`. Passes return *unsealed
   rewrite objects*; only the trusted `commit` (validating port equality, proof steps, phase ledger, frozen storage, and cert
   transport) re-seals a `UnitaryBlock`.
2. **Registry layer.** Every pass registers in `const PASS_REGISTRY` at definition. A **boot lint** (`test/runtests.jl`, beside the
   shipped `_ctrl`-confinement and physics-cite lints) asserts every `UnitaryPass` in the registry has a corresponding entry in
   the phase-faithful law-test battery (§3.4). **A pass cannot ship without its phase test** — the same "you cannot add a call
   site" discipline that fixed the controlled-phase bug for `ctrl`. (B's mechanism; A had only prose here.)
3. **Barrier layer.** `UnitaryPass` application is *structurally impossible* on a DAG containing a channel barrier, because such a
   DAG never promotes to a `UnitaryBlock` (§2.3). CLAUDE.md's "partition at measurement barriers; apply unitary-only methods ONLY
   to unitary blocks" is thereby a type invariant, not a discipline.

### 3.4 Named law tests (PRD-style exact statements)

All *direct* unitary comparisons mean matrix comparison with **phase included** (`approx_upto_phase` is forbidden). Dense/Choi
fixtures stay small — F25 rejects the PRD's 15-wire dense-Choi capacity (`2^{4W}` entries; 16 EiB at `W=15`); larger checks use
randomized reference-assisted probes. The battery `V*` MUST include phase-only values — `gphase(π)` (`=−I`), `gphase(π/4)`, `S`,
`T` — and their controlled forms, plus a `MatchedPair`/`PermClean` block with a live ancilla.

| Required test name | Exact statement |
|---|---|
| `M8.PORT.TYPED-COMPOSITION` | Every node's output schema equals the next consumer's input schema; malformed dimension, arity, or resource-lineage composition is rejected before lowering. |
| `M8.PORT.CHANNEL-NOT-PROCESS` | `ChannelDAG <: ProcessValue` is `false`; no `ctrl(::ChannelDAG)` and no unitary-pass method exists (a `MethodError`). Allocation and discard alone cannot be applied as process values. |
| `M8.PORT.ENDOMORPHIC-BLOCK` | Sealing fails unless output boundary schema, order, and **resource lineage** equal the input boundary exactly. |
| `M8.CERT.CLEAN-SUBSPACE` | For each small certified fixture, dense `W` satisfies `‖(I−ιι†)Wι‖ ≈ 0`, and `U = ι†Wι` satisfies `U†U ≈ UU† ≈ I`. |
| `M8.CERT.STATE-IS-NOT-WITNESS` | The unmatched `a ⊻= r` compute is rejected **structurally** even on an Eager run with `r=|0⟩` where the debug marginal is 0. (The F1 adversary.) |
| `M8.CERT.MATCHED-COMPUTE-UNCOMPUTE` | A valid `MatchedPair` fixture is accepted for arbitrary superposed and reference-entangled sources; dense comparison verifies `|x⟩|0⟩|ψ⟩ ↦ |x⟩|0⟩ M_{x} |ψ⟩`. |
| `M8.CERT.PERM-SUBSET-NEEDS-CONTRACT` | A bare `Perm` is accepted as unitary when every port is boundary, but cannot justify releasing designated scratch without a checked `PermClean` (Bennett) contract. |
| `M8.CERT.BENNETT` | A structurally checked compute-copy-uncompute artifact restores every declared scratch port and preserves its sources for every input; exhaustive truth-table comparison for small widths as a checker test. |
| `M8.CERT.COMPOSITION` | Certified `SeqCert`/`ParCert`/`AdjointCert` blocks retain valid certificates and denote `U₂U₁`, `U₁⊗U₂`, `U†` respectively. |
| `M8.CTRL.BLOCK-HOMOMORPHISM` | For certified blocks `g,h`: `denoted_matrix(ctrl(g∘h)) ≈ denoted_matrix(ctrl(g)∘ctrl(h))`. |
| `M8.CTRL.BLOCK-ADJOINT` | `denoted_matrix(adjoint(ctrl(g))) ≈ denoted_matrix(ctrl(adjoint(g)))`. |
| `M8.WHEN.STREAM-MATERIALIZED-AD` (`test_m8_stream_eq_materialized`, conjunct 1) | For each certifiable `when` body `B`, the phase-fixed streamed value `S(B)` and its sealed materialization `M(B)=certify(trace(B))` satisfy `S(B) ≈ M(B)` as **U(d) representatives**, not merely `Choi(Ad(S)) ≈ Choi(Ad(M))`. |
| `M8.WHEN.STREAM-MATERIALIZED-CTRL` (`test_m8_stream_eq_materialized`, conjunct 2) | `Choi(Ad(ctrl(M(B)))) ≈ Choi(Ad(ctrl(S(B))))` on small instances. **Mandatory even if the uncontrolled Choi test passes** — this is F3's required addition. |
| `M8.PASS.PORT-AND-CERTIFICATE` | Every committed unitary-pass result has the same boundary and a valid original or `XportCert`-transported certificate. |
| `M8.PASS.UNITARY-REPRESENTATIVE` (`test_m8_pass_phase_faithful`) | For each of reassociation, view-fusion, U2-fusion, and every `UnitaryPass P` in `PASS_REGISTRY`: `P(v) ≈ v` (process `≈`, phase-inclusive), directly. |
| `M8.PASS.UNITARY-CONTROLLED` (`test_m8_ctrl_survives_pass`) | For every `UnitaryPass P` and `v ∈ V*`: `Choi(Ad(ctrl(P(v)))) ≈ Choi(Ad(ctrl(v)))`. (Controlling promotes any leaked phase to an observable — the test that catches the Qiskit-#4949 class.) |
| `M8.PASS.PHASE-DELTA` | For a rule reporting `δ`: the uncommitted candidate satisfies `U' = e^{iδ}U`; the committed result satisfies `U_committed ≈ U`, and the controlled Chois agree. |
| `M8.PASS.PHASE-SENTINEL` | For `α = π/3`: `Choi(Ad(I)) ≈ Choi(Ad(gphase(α)))` **but** `Choi(Ad(ctrl(I))) ≉ Choi(Ad(ctrl(gphase(α))))`. A fabricated phase-dropping rewrite must be rejected or fail `M8.PASS.UNITARY-CONTROLLED`. (The "test of the test".) |
| `M8.PASS.CHANNEL-DENOTATION` (`test_m8_channel_pass_choi_ok`) | For every channel pass, input/output signatures are identical and `Choi(P(G)) ≈ Choi(G)` on exact small fixtures; a `ChannelPass` handed a `UnitaryBlock` rejects (`MethodError`). |
| `M8.PASS.MEASUREMENT-BARRIER` | No unitary pass visits a block spanning a `MeasureN`/`TraceN`-discard/`NoiseN`/`CasesN`; deferred measurement is exercised only through the channel-pass interface. |

Physics grounding for the sentinel: `C(U) = |0⟩⟨0|⊗I + |1⟩⟨1|⊗U`, a controlled global phase becomes an observable `Z`-rotation
(`docs/physics/delorme_control_as_constructor.md`); Tang–Wright's `I` vs `−I` is the canonical separation
(`docs/physics/tang_wright_2025_controlled_unitaries.md` Thm 1.1).

---

## 4. Deep immutability (F28)

`ChannelDAG.nodes`, all `Port` tuples, and every `CleanCert` are frozen (tuples / frozen `Perm`, no live `Vector` aliasing) — an
immutable struct wrapping a mutable `Vector` is **not** deeply immutable, and later mutation would invalidate certificates,
caching, `ctrl`, and pass results (F28). Mutable **builders** are used during tracing/pass construction; **freezing copies into
immutable nodes on `certify`/`commit` and discards the builder.** This requires one M8 prerequisite in the kernel: `MCX.controls`
and `Perm.gates` are currently `Vector`s (`src/kernel/perm.jl`), so sealing a block that embeds the current `Perm` without copy
is unsound. Refactor `MCX`/`Perm` to `NTuple` storage with vector-accepting, defensively-copying public constructors (ruling R5).

---

## 5. Eager execution and the marginal check

Eager streaming tee-records the same structural transcript `TracingContext` materializes. For a `when` frame: (1) surface ops
stream through `_act!`; (2) the frame simultaneously records a unitary candidate; (3) region exit first attempts structural
sealing for the whole frame; (4) only a successful certificate licenses scratch release; (5) in **debug** mode, Eager/DM then
cross-checks the actual `|1⟩` marginal of every released ancilla; (6) a structurally certified block whose debug check fails
indicates an executor/lowering/numeric/cert-checker defect. The functions at `src/surface/when.jl` are renamed conceptually from
"witness" to "debug assertion". Failure topology (poison vs materialize-first) is ruling R2.

---

## 6. i4ri seam (explicit, per task constraint)

This design keeps the boundary with the parallel `i4ri` classical-control round explicit and does not touch its files:

- **Measurement barriers partition `ChannelDAG`.** `MeasureN`/`CasesN`/`NoiseN` are barrier nodes; unitary passes never cross them
  (§3.3 barrier layer) and `certify` refuses any DAG containing them (§2.3).
- **`UnitaryBlock` never contains an instrument node** (§1.3 invariant).
- **`CasesN` is typed here, its join semantics is i4ri's gate.** The `sel::PortID` (a classical token port) and
  `branches::NTuple{…,ChannelDAG}` are the attach points; tokens / correlation record / Kleisli linear-join live in i4ri.
`certify`'s refusal of `CasesN`/`MeasureN` is the exact seam where the classical-control IR meets the unitary block.

---

## 7. PRD replacement wording (staged — paste only after §8 rulings)

> These blocks are written against the **current** working-tree text (re-verified; the shipped §3.5 guardrail-1 already reads
> "any **measurement (qc) cast** (`Bool`, `Int`), `ptrace!`, `cases`, or noise channel … is a **loud error**" and already
> permits `QBool(false)`). Line numbers will have drifted by paste time; match by landmark.

### 7.1 §3.5 semantics line (currently "trace `body` to a unitary-witnessed process value `V`")

> `when(q, body)` ≡ trace `body` to a value carrying a **structural clean-ancilla certificate** (§4.1a) — a state-independent
> proof (`NoAncilla`, `PermClean` (Bennett `(★)`), or `MatchedPair` (`within` compute/uncompute)) that the composite is a
> fixed-port unitary `V` on the surviving wires — then apply `ctrl(V)` to `(q, wires of body)`.

### 7.2 §3.5 guardrail 1 (replace "must trace to a **unitary-witnessed** value")

> 1. The body must trace to a value carrying a **structural clean-ancilla certificate** (§4.1a). Any **measurement (qc) cast**
>    (`Bool`, `Int`), `ptrace!`, `cases`, or noise channel inside `when` prevents certification and is a **loud error**. Canonical
>    fresh-`|0⟩` allocation — spelled `QBool(false)` — remains the blessed alloc-inside-`when` scratch pattern (the certified
>    compute–uncompute lemma), a preparation *without* backaction, not a qc cast. An arbitrary literal `QBool(p, φ)` under `when`
>    is a loud error naming **D15**.

### 7.3 §3.5 Eager bullet (replace the `|1⟩`-block-norm-0 sentence)

> Clean-ancilla exit (§3.9): the **certificate** (§4.1a) is the witness — it proves, for *all* inputs, that `V` returns the
> ancilla to `|0⟩` in the control-firing branch, which is exactly the compute–uncompute proviso. On Eager the runtime
> `|1⟩`-marginal check is retained as a **debug cross-check that the certificate was honoured** — sound fail-fast per run, never
> itself the witness (a single input state cannot certify a universally-quantified containment condition).

### 7.4 §1.1 control-disentanglement (F10 — replace "must leave control disentangled at exit")

> Sound coherent-control bodies must be reversible, must not access the user's guard, and must synchronize all **internal**
> control-flow/path and scratch state before exit. The user's guard remains a **live quantum output and may be entangled** with
> the data — CNOT on `|+⟩|0⟩` is the elementary example. The synchronization theorem applies to internal machine state that is
> discarded, not to the semantic guard qubit.

### 7.5 §3.9 "Inside `when`" (replace)

> **Inside `when`, ordinary trace is forbidden.** A body-local canonical ancilla may leave scope only through a certified
> `TraceN`, interpreted as the coisometry `I ⊗ ⟨0|` on the structurally-proved reachable clean subspace `(I−ιι†)Wι=0`. If no
> structural clean-subspace proof exists, the body is a channel with an environment and cannot become a process value; guardrail 1
> fires loudly. The Eager `|1⟩`-marginal check is retained only as a **debug assertion** of a previously established certificate.
> Bennett artifacts supply a clean certificate by checked compute-copy-uncompute construction; a bare `Perm` proves unitarity on
> **all** of its ports but not cleanliness of an arbitrarily designated subset.

### 7.6 §4.1 `UnitaryDAG` bullet (replace)

> - `ChannelDAG` — the effect-typed channel IR (typed quantum in/out ports that need not match, plus classical token ports);
>   nodes carry process values, never gate names. It is **not** a process value: it sits on the channel level of §4.4 and
>   `ctrl(::ChannelDAG)` is unrepresentable (P4).
> - `UnitaryBlock{N} <: ProcessValue` — a `ChannelDAG` **certified** (`certify`) to denote a fixed-port unitary on its `N`
>   surviving wires: `N` in-ports `== N` out-ports **with identical resource lineage**, every internal allocation matched by a
>   certified deallocation covered by a structural clean-subspace certificate (§4.1a). Only `UnitaryBlock` is a process value;
>   only it may be controlled. Allocation is an isometry and deallocation a coisometry — the composite is unitary on surviving
>   ports *exactly when the certificate holds*, which is why the boolean `unitary=true` flag is rejected.
> - Future finite-dimensional process values carry a definite `U(d)` representative; an `SU(d)` value without its `U(1)` phase is
>   insufficient under control (F9).

Plus a new **§4.1a "The clean-ancilla certificate"** stating the closed constructor set (`NoAncilla`/`PermClean`/`MatchedPair`/
`SeqCert`/`ParCert`/`AdjointCert`/`XportCert`), the universal invariant `(I−ιι†)Wι=0`, and the §4.2/Bennett soundness.

### 7.7 §4.2 pass law (append after the algebra laws)

> **Pass law.** Pass correctness is stratified by value kind: a **channel pass** preserves the typed CPTP denotation
> (Choi/diamond); a **unitary-block pass** preserves the phase-fixed `U(d)` representative — `P(v) ≈ v` under process-value
> equality (phase-inclusive, mod the ℤ₂ double cover), or returns a proved phase delta `U' = e^{iδ}U` and reattaches `e^{−iδ}`
> before returning a process value. Every unitary pass has two required law tests: direct representative equality and equality of
> the `ctrl`-wrapped pre/post channels. Choi equality of the uncontrolled values is **not** a unitary-pass proof (Tang–Wright
> Thm 1.1). Unitary passes are mechanically restricted to `UnitaryBlock`s and cannot cross measurement/discard/noise/`cases`
> barriers; channel passes cannot promote a result to `UnitaryBlock` from Choi equality. Enforced by `PASS_REGISTRY` + a boot
> lint mirroring the `ctrl` choke point.

### 7.8 §4.3 dispatch table & §4.4 stratification (amend)

Replace the `UnitaryDAG | replay nodes | replay nodes` row with `UnitaryBlock` (certified scratch alloc; replay phase-fixed
instructions; certified zero-release; uncontrolled `Ad` may quotient phase only at leaf application) and a `ChannelDAG` row
(channel executor; **never** `ctrl`). In §4.4's stratification table, list `UnitaryBlock` among process values and `ChannelDAG`
among channels, and add: *"A certificate promotes one particular frozen, fixed-port unitary trace to a process value. It does not
invert `Ad`, control a channel, or infer a phase representative from a Choi matrix."*

### 7.9 D13 (amend the resolved wording)

> **D13 — `when` operational semantics: AMENDED by M8 design gate.** Streaming remains licensed by the `ctrl` homomorphism, but
> the Eager `|1⟩`-marginal observation is a **debug assertion, not a witness**. Both Eager and Tracing record a structural unitary
> transcript. A body with scratch is accepted only when the transcript seals as a fixed-boundary `UnitaryBlock` with a universal
> clean-subspace certificate. The required law is representative-preserving streaming equivalence **plus** a `ctrl`-wrapped Choi
> comparison.

### 7.10 Implementation-plan corollary (F35)

Split the M8 plan bullet into: (1) typed immutable `ChannelDAG`; (2) unitary-candidate tracing + structural sealer; (3)
`UnitaryBlock` application/adjoint/control; (4) Eager tee tracing + debug assertions; (5) channel-pass framework; (6)
representative-preserving unitary-pass framework (`PASS_REGISTRY` + boot lint); (7) tokens/`cases` only after the i4ri round
resolves. Rename `UnitaryDAG` → `ChannelDAG`+`UnitaryBlock`; add `certify`+`CleanCert`, the phase-faithful pass registry/lint, and
`test_m8_ctrl_survives_pass` + strengthened `test_m8_stream_eq_materialized` to the named-test list. Remove "Channel DAG with
unitarity witness".

---

## 8. ⚠ TOBIAS RULINGS (consolidated, deduplicated)

Merged from A's R1–R8 and B's R1–R7. Each: options + recommendation.

**TR1 — `UnitaryBlock` shape & naming.** *(A-R6 + B-R4 + B-R5; both proposers agree square, overriding F2's `{InPorts,OutPorts}`.)*
Options: (a) square `UnitaryBlock{N}` with a runtime `NTuple{N,Port}` boundary (isometric asymmetry confined to
`ChannelDAG.qin/qout`); (b) F2's literal `UnitaryBlock{InPorts,OutPorts}`; (c) add a separate future `UnitaryMorphism{In,Out}` for
non-square unitary maps. Also: rename `UnitaryDAG` → `ChannelDAG` + `UnitaryBlock`?
**Recommendation:** (a) — square `{N}`, keep `{InPorts,OutPorts}` off the block (a non-square map is an isometry = a channel-level
object); reserve (c) for later; **adopt the rename** (a certified block may have zero internal nodes, so "DAG" misleads).

**TR2 — Eager failure topology.** *(A-R1.)* When a streaming Eager `when` fails to seal at frame exit, some effects have already
run. Options: (a) tee-record while streaming, then **poison** the context on a failed seal; (b) materialize-and-certify **before**
applying on the first Eager invocation; (c) execute the closure twice (trace, then stream).
**Recommendation:** (a) — preserves one closure execution and the streaming path; the context must become unusable after a failed
late seal. (b) turns Eager `when` into materialized execution; (c) runs classical side effects twice.

**TR3 — Canonical scratch spelling & `within`'s layer placement (touches the surface-construct count — CLAUDE.md #11).**
*(A-R2 + B-R3 + F12.)* Options: (a) keep `QBool(false)` as the blessed `|0⟩` exception inside `when`, and make `within` a `public`
kernel/library combinator (**not** an 8th surface construct) — the only certifiable ancilla-introduction form; (b) add a dedicated
`with_ancilla`/`scratch(QBool)` surface spelling (a genuine surface-vocabulary change needing its own gate); (c) ban all allocation
inside `when`.
**Recommendation:** (a) — retain `QBool(false)` (arbitrary `QBool(p,φ)` incl. `QBool(true)` stays forbidden, D15); `within` stays
`public`, keeping the seven surface constructs. **This is a genuine ruling** because it fixes how F12's "prep required yet its cast
banned" tension resolves.

**TR4 — Certificate completeness & acquisition.** *(A-R3 + B-R1 + B-R2.)* Options for the recognized proof language: (a)
conservative closed constructors (`NoAncilla`/`PermClean`/`MatchedPair`/`SeqCert`/`ParCert`/`AdjointCert`/`XportCert`) only,
combinator-carried, with the syntactic palindrome verifier deferred to a follow-on bead; (b) add dense universal verification below
a width cutoff *as a construction route* (not just a test); (c) general symbolic/SMT invariant proving in M8.
**Recommendation:** (a) — conservative structural constructors, combinator-carried primary. Dense checks belong in tests, not
certificate construction. A refused-but-valid body is a **loud** user error pointing at `within`.

**TR5 — `Perm`/`MCX` immutability refactor (F28).** *(A-R4 + B-R6.)* `MCX.controls`/`Perm.gates` are `Vector`s today; a sealed
block embedding them is mutable-through-aliasing. Options: (a) refactor `MCX`/`Perm` to `NTuple` storage with vector-accepting
defensively-copying constructors; (b) copy every `Perm` into a private frozen snapshot on IR insertion; (c) trust caller
discipline.
**Recommendation:** (a) — trusting discipline makes certificate validity mutable; private snapshots duplicate the reversible
hierarchy and complicate `ctrl`/`adjoint`/equality.

**TR6 — Under-sized oracle targets.** *(A-R5.)* Options: (a) require a full-width target in all unitary contexts; (b) permit a
smaller target only with a compiler-supplied **structural range certificate** that the tail bits are `0` for every input; (c)
exhaustively infer the range below a width threshold; (d) retain current per-run zero-tail acceptance.
**Recommendation:** (a)+(b) — full width by default, smaller only with a structural range cert. (c) may *test* a cert for small
widths but must not *define* semantics; (d) repeats F1.

**TR7 — Phase-delta scope + zero-port scalar blocks.** *(A-R7 + A-R8.)* Tier-1(b) reattaches `e^{−iδ}` via `gphase` on a boundary
qubit, which fails for a zero-port block. Options: (a) keep `PhaseDelta`/proof constructors **internal** in M8 **and forbid
zero-port `UnitaryBlock`s** in M8 (defer a scalar `e^{iφ}: I→I` process value to future general `U(d)` support); (b) expose the
phase-delta path as a plugin pass API now; (c) forbid nonzero deltas entirely (drop the escape hatch).
**Recommendation:** (a) — the mechanism exists so the representation is correct, but an external proof API and scalar process
values each need their own design.

**TR8 — `denoted_matrix` cost cap (F25).** *(B-R7.)* Reference semantics replay on `ancilla=|0⟩` at `2^N`. Options: (a) cap by a
**memory budget** (not the 30-qubit pure ceiling), randomized reference-assisted probes above it; (b) keep the pure-state ceiling.
**Recommendation:** (a). Minor / test-harness — flagged, no deep ruling needed.

---

## 9. Provenance (which pieces from A vs B vs new)

| Piece | Source | Notes |
|---|---|---|
| `ChannelDAG` (not `ProcessValue`, `ctrl`→`MethodError`) vs `UnitaryBlock <: ProcessValue` | **A + B converge** | verified against `u2.jl` ProcessValue docstring + `ctrl.jl` no-catch-all |
| `UnitaryBlock` is **square** (override F2's `{In,Out}`) | **A + B converge independently** | notable: both overrode the review's tentative type |
| `{N}` type parameter (type-stable dispatch) | **B** | grounded in `QInt{W}` convention |
| Runtime `PortList`/`Port` boundary + **resource lineage** for the endomorphism check | **A** | closes B's width≠identity gap |
| Effect-node vocabulary `ApplyN/AllocN/TraceN/MeasureN/CasesN/NoiseN` | **B** | shorter, matches CLAUDE.md barrier naming |
| Closed cert constructor set `NoAncilla/PermClean/MatchedPair/SeqCert/ParCert` + `within` = `C†∘M∘C` | **B** | idiomatic; maps to shipped `within`/`oracle` |
| `AdjointCert`, `XportCert` (pass-transported cert) | **A** | genuine gaps in B |
| Port-role / effect-footprint analysis (the `MatchedPair` side-condition mechanism) | **A** | B only gestured at it |
| Universal invariant `(I−ιι†)Wι=0` as the soundness spec | **A** | each B-constructor discharges it |
| Marginal assert demoted to debug cross-check | **A + B converge** | F1 fix sketch verbatim |
| Pass tier-1(a): phase-inclusive process `≈`, no new machinery | **B** | verified: `algebra.jl`/`u2.jl` `isapprox` already phase-inclusive |
| Pass tier-1(b): explicit `PhaseDelta` reattach escape hatch | **A** | for future synthesis/QSVT passes |
| `PASS_REGISTRY` + boot lint (mechanical enforcement) | **B** | A had only prose |
| Named law-test battery (19 tests, PRD-style) incl. phase sentinel, state-is-not-witness | **A** (base) + **B** (CI names, ctrl-survives-pass, strengthened stream≡materialized) | merged |
| PRD reword blocks (§3.5/§3.9/§4.1/§4.2/§4.3/§4.4/D13) | **A** (comprehensive base) | re-verified against current text; §3.5 quote corrected |
| §1.1 control-disentanglement reword (F10) | **A** | B omitted F10 entirely |
| i4ri seam statement | **new** (per task constraint) | `CasesN` typed here, join semantics deferred |

---

## 10. Risks & alternatives rejected

- **One DAG + `unitary::Bool`** — rejected: proves neither port equality nor the clean-subspace theorem; permits accidental
  unitary-only dispatch on channel nodes (F2).
- **Statevector marginal as certificate** — rejected by the F1 universal counterexample; kept as debug assertion.
- **Numerical matrix verification as certificate** — rejected: exponential, tolerance-dependent, cannot support large Bennett
  artifacts; appropriate only for *testing* the structural checker.
- **Any `Perm` as a clean-subset witness** — rejected: a permutation is unitary on all ports but may move information into ports a
  caller intends to discard; the Bennett contract (`PermClean`) is the additional proof (`M8.CERT.PERM-SUBSET-NEEDS-CONTRACT`).
- **Choi-only unitary-pass verification** — rejected: `Ad_U = Ad_{e^{iα}U}` while `C(U) ≠ C(e^{iα}U)` (F3).
- **Width equality as boundary identity** (B's literal `{N}` invariant) — insufficient; replaced by resource lineage (A).
- **`global _sealed_unitary_block` inner-constructor idiom** (A's sketch) — an obscure (if valid) Julia pattern; prefer a
  lint-confined private constructor mirroring the shipped `_ctrl` confinement (`ctrl.jl` + `runtests.jl` boot lint). Implementer's
  choice; noted.

**Residual M8 blockers outside this proposal** (F4–F6, owned by the i4ri round): runtime classical arithmetic / dynamic loops
(restricted classical SSA/CFG or staged retracing); exact DM branching cannot return a scalar `Bool`; `cases` linear quantum joins
+ persistent correlated records. Typed `ChannelDAG` ports are groundwork, not their solution. Also flagged: pairwise alias checks
among nested controls incl. dual views (F29) before relying on a flat control count; future `SU(d)`-only values are incompatible
with this pass contract unless carrying their `U(1)` phase (F9).

## 11. Acceptance criterion

The gate is satisfied when M8 can demonstrate, **without a boolean unitarity flag**: (1) the adversarial input-dependent
clean-state program is rejected structurally; (2) a valid matched compute/uncompute body seals as a phase-fixed `UnitaryBlock`;
(3) a channel graph cannot reach `ctrl` or a unitary-only pass; (4) unitary passes return only proof-checked, phase-correct
blocks; (5) streaming and materialized bodies agree both as `U(d)` representatives **and** after control; (6) the Eager marginal
check is documented and tested solely as a debug assertion.
