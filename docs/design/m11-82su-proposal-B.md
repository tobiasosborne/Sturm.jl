# M11 — Noise, Stinespring dilation, QECC superchannel typing — Proposal B

> Bead `Sturm.jl-82su`; review findings **F8** (QECC superchannel typing) and
> **F33** (the Stinespring dilation contract). Independent blind proposal,
> written against the shipped M0–M12 tree (suite 27328 green).
> Nothing here is applied to the repo; PRD amendments are **staged**, not made.

---

## 0. The load-bearing ideas (three, and everything else follows)

**(I) A channel never becomes a process value, but its *representations* are
ordinary data.** The §4.4 slogan "channels are denotations, not values" is
sharpened, not broken, by M11. There are three strata, and M11 makes the middle
one explicit:

| stratum | objects | non-uniqueness | `ctrl`? |
|---|---|---|---|
| 1. process values | `U2`, `Perm`, `UnitaryBlock{N}` | *none* — a definite `U(d)` representative | ✔ closed |
| 2. **channel representations** | `KrausFamily{W,K}` (algebraic), `ChannelDAG` (syntactic) | **massive** — Kraus unitary freedom, dilation freedom, IR shape | ✘ by theorem |
| 3. denotations | CPTP maps | — (this *is* the quotient) | ✘ not an object at all |

The theorem that forbids `ctrl` on stratum 2 is one line, and it is the same
line for both members: *a channel's representation is non-unique in exactly the
ways `ctrl` can see.* Choi's unitary freedom (`docs/physics/choi_1975_cp_maps.md`,
Thm 2 — `{K_i}` and `{K'_j = Σ_i u_{ji}K_i}` denote the same channel) and
Stinespring's uniqueness-up-to-partial-isometry
(`docs/physics/stinespring_1955_dilation.md`, Thm 1 + the minimality corollary)
say two representations of *one* channel differ by an environment-side unitary
and a global phase; Tang–Wright Thm 1.1
(`docs/physics/tang_wright_2025_controlled_unitaries.md`) says control makes a
global phase — a fortiori an environment-side unitary — **observable**. So
controlling any representation of a channel would make an arbitrary bookkeeping
choice physically observable. That is the P4 no-go, re-derived for noise.

**(II) The Stinespring dilation is a *lowering artifact*, exactly like ZYZ.**
`U2` is chart-free until it hits Orkan, where Euler extraction happens **once,
at one boundary** (§4.1, D7). A `KrausFamily` is dilation-free until it hits a
pure context, where the dilation is synthesized **once, at one boundary**, used,
and dropped. It is never stored in the IR, never returned to user code, and —
the F33 rule — never a controllable value. The parallel is exact and it is how
the whole contract should be read.

**(III) A superchannel is a transformation on the channel IR, not a value of a
channel type.** `Θ(𝓝) = D∘R∘𝓝∘E` is a quantum comb — a circuit with a hole
(Chiribella–D'Ariano–Perinotti, `docs/physics/chiribella_2009_combs.md`,
PRA 80 022339 §II). A hole in a circuit is a *syntactic* object; filling it is
*substitution*. Sturm already ships the syntax (`ChannelDAG`) and the
reification API (`trace(f, nin)`), so `effective_logical_noise` is a compiler
transformation `ChannelDAG → ChannelDAG` with typed boundaries — and the
superchannel *value* that names it (`Protect(code, decoder)`) carries the comb's
**teeth**, never the hole's contents. §3 argues this at length; it is the answer
to the hardest question in the brief.

---

## 1. Q1 — Kraus channel values

### 1.1 The type

New kernel abstract type, deliberately **not** under `ProcessValue`:

```julia
"""
    ChannelValue

Supertype of ALGEBRAIC channel representations (stratum 2 of §4.4). A
`ChannelValue` is data — composable, tensorable, printable — but it is NOT a
process value: it has no `ctrl` method (a `MethodError` by construction, the
shipped no-catch-all discipline of `src/kernel/ctrl.jl`), it cannot sit in an
`ApplyN` (whose `v` field is typed `ProcessValue`), and it therefore can never
be certified into a `UnitaryBlock`. See §4.4 and `docs/physics/choi_1975_cp_maps.md`.
"""
abstract type ChannelValue end

"""
    KrausFamily{W,K,L} <: ChannelValue

A `K`-term Kraus family on `W` wires: `𝓝(ρ) = Σᵢ Kᵢ ρ Kᵢ†` with
`Σᵢ Kᵢ†Kᵢ = I` (CPTP). Storage is a FROZEN `NTuple{L,ComplexF64}` of the `K`
operators concatenated ROW-MAJOR (`L == K·4^W`) — deep immutability (F28: no
immutable struct wrapping a live `Vector`) AND, not by accident, the exact
byte layout Orkan's `kraus_t` wants (`src/orkan/ffi.jl`), so the DM path copies
once into a pinned buffer and calls `kraus_to_superop`.

CP is BY CONSTRUCTION (Choi 1975 Thm 1: a map is completely positive iff it
admits a Kraus form — `docs/physics/choi_1975_cp_maps.md`); only TP is checked.
"""
struct KrausFamily{W,K,L} <: ChannelValue
    data::NTuple{L,ComplexF64}
    label::Symbol                      # provenance for messages/printing
    function KrausFamily{W,K,L}(data::NTuple{L,ComplexF64}, label::Symbol) where {W,K,L}
        L == K * (1 << (2W)) || error(
            "KrausFamily{$W,$K,$L}: payload length $L ≠ K·4^W = $(K * (1 << (2W))) — " *
            "an internal packing bug.")
        return new{W,K,L}(data, label)
    end
end
```

Users never write the parameters; the validating outer constructor does:

```julia
"""
    KrausFamily(ops::AbstractVector{<:AbstractMatrix}; label=:custom, atol=KRAUS_TP_ATOL)

Freeze `ops` into a `KrausFamily`, checking TRACE PRESERVATION `Σ Kᵢ†Kᵢ ≈ I`
to `atol` (§4.1 float-law policy: exactness is a group-structural claim, never a
float claim). FAILS LOUD with the actual defect `maximum(abs, ΣK†K − I)` — the
family is NEVER silently renormalized (a renormalized "noise model" is a
different channel, and silently substituting it is the wm28 pattern).
"""
function KrausFamily(ops::AbstractVector{<:AbstractMatrix{<:Number}};
                     label::Symbol = :custom, atol::Float64 = KRAUS_TP_ATOL)
```

Validation, in order (all `ArgumentError`/`DomainError`, S13 taxonomy):

1. `isempty(ops)` → loud (a channel has at least one Kraus operator);
2. all operators the same size, square, dimension a power of two ⇒ `W`;
3. `K·4^W ≤ KRAUS_MAXDATA` (=1024) — the frozen-tuple ceiling; above it, loud,
   pointing at `⊗`/wire-by-wire application (an `NTuple{4096}` destroys
   inference; a silent slow path would be worse);
4. TP as above.

Accessors (`public`): `nwires(::KrausFamily{W}) = W`,
`krausrank(::KrausFamily{W,K}) = K`, `kraus_matrices(𝓝) -> Vector{Matrix{ComplexF64}}`
(cold path — materializes from the frozen tuple), `label(𝓝)`.

### 1.2 Equality, and why `≈` must be Choi-level

Per F26, `==` stays **exact-structural** (tuple equality — usable in dicts/caches).
`≈` is the **semantic** predicate, and here semantic equality is *channel*
equality, which is coarser than op-wise closeness because of Kraus freedom:

```julia
Base.isapprox(a::KrausFamily{W}, b::KrausFamily{W}; atol=KRAUS_TP_ATOL) =
    isapprox(choi_matrix(a), choi_matrix(b); atol=atol)
```

`choi_matrix(𝓝)` is the **canonical** representative (the Choi matrix is unique
for a channel; the Kraus family is not — `docs/physics/choi_1975_cp_maps.md`
Thm 1/2). Basis convention (`out` = MSB, normalized to trace 1) is pinned in
**one** function and cross-checked by a test against `test/choi.jl`'s harness —
the project's standard endianness discipline (§8.4/M7 single-remap lint).

### 1.3 Algebra

```julia
Base.:∘(a::KrausFamily{W}, b::KrausFamily{W})                       # a after b (right-to-left, §4.2)
⊗(a::KrausFamily{Wa,Ka}, b::KrausFamily{Wb,Kb})                     # → KrausFamily{Wa+Wb, Ka·Kb}
```

Both are closed on CPTP (products/tensors of Kraus families satisfy
`Σ = I` by the same computation), so the composite's TP check is a
cheap re-assertion, not a re-derivation. Rank multiplies: `∘` of two rank-4
families is rank 16, and iterating explodes — documented, with a **loud** rank
cap (`KRAUS_MAXRANK`, tied to `KRAUS_MAXDATA`) and Choi-eigendecomposition
compression named as a deferred item (§8).

**No `adjoint`.** The adjoint map `𝓝*` is unital, not trace-preserving; it is
not a channel. `adjoint(::KrausFamily)` is a `MethodError` — the correct
failure, not a wrong answer.

**No `ctrl`.** No method is written. This is the P4 boundary, and it is free:
`src/kernel/ctrl.jl` deliberately has no `ctrl(::ProcessValue)` catch-all, and
`KrausFamily` is not even in that tree. Required test:
`@test_throws MethodError ctrl(bit_flip(0.1))`.

### 1.4 Application — the §4.3 dispatch table, extended

| value | Eager (pure) | DM | Tracing |
|---|---|---|---|
| `U2`, `Perm`, `Ctrl`, `UnitaryBlock` | shipped | shipped | `ApplyN` (shipped) |
| **`KrausFamily{1}`** | **loud error** (default) / dilation (opt-in, §2) | `_apply_channel_1q!` (shipped Orkan superop) | **`NoiseN(𝓝, ports)`** |
| **`KrausFamily{W≥2}`** | dilation (opt-in) | dense embedded superoperator, capacity-capped (§1.6) | `NoiseN` |

Entry points:

```julia
apply!(ctx::AbstractContext, 𝓝::KrausFamily{W}, wires::NTuple{W,WireID}; stinespring::Bool=false)
```

— the same `apply!` verb PRD §4.3 mandates ("channel-level values apply through
the same surface"), plus the library verb a physicist types:

```julia
"""
    noise!(q::AbstractQubit, 𝓝::KrausFamily{1}; stinespring=false) -> q
    noise!(x::QInt{W},      𝓝::KrausFamily{1}; stinespring=false) -> x   # iid on all W wires
    noise!(r::WireRef,      𝓝::KrausFamily{1}; stinespring=false) -> r
```

`noise!` is a library verb (`!` = mutating, like `evolve!`/`mulmod!`), **not an
eighth surface construct**: noise is something you *do to* a program, and the
seven constructs are what a program *is*.

### 1.5 The guardrail the shipped tree does NOT yet have (a finding)

`src/surface/when.jl`'s guardrail table, row 9, marks DM `apply_channel!` as
**"BANNED — forward hook (M8/M11)"**, and `src/context/density.jl`'s
`apply_channel!`/`_apply_channel_1q!` contain **no** `_assert_no_control` call
today. Noise inside `when` is therefore *not* currently rejected — the guardrail
is specified but unwired. **M11 closes it**: `_assert_no_control(ctx, "noise
channel application")` at the top of every `KrausFamily` application path *and*
inside `apply_channel!` (before any backaction), with the shipped message
(P4/§4.4, Yuan–Villanyi–Carbin Thm 4.4, Bădescu–Panangaden Condition III).
Named test in §6.

### 1.6 The Orkan ceiling, stated honestly

`orkan_channel_1q!` guards `sop.n_qubits == 1` and `state.type != PURE`: Orkan
has **no** k-local channel entry and **no** pure-state channel path (audit §8.4).
So:

* `W == 1`, DM → native, shipped, fast.
* `W ≥ 2`, DM → a Julia-side dense application: read ρ (`density_matrix`),
  apply `Σ (Kᵢ⊗I) ρ (Kᵢ⊗I)†` with the operators embedded through the single
  `q(ctx, wire)` slot map, write back. O(4^cap) per application, hard-capped at
  `KRAUS_DENSE_MAXCAP = 10` (2²⁰ complex = 16 MiB) with a loud error above.
  **Research step (rule 8, gates this sub-slice):** verify that
  `orkan_state_set!` on `MIXED_TILED` round-trips (`set(get(ρ)) == ρ`,
  including the Hermitian partner) before relying on it. If the round-trip
  fails, `W ≥ 2` DM application ships as a loud error naming
  `⊗`-decomposition and the dilation route — no silent path either way.

---

## 2. Q2 — The Stinespring fallback contract (F33)

### 2.1 When it fires — never silently

Default on a pure context is **the loud error** (PRD §4.3 option (a)):

```
noise!(q, depolarizing(0.05)): a Kraus channel cannot be applied to a PURE
statevector context. Three sanctioned routes, all explicit:
  • run the program under `density(cap) do ctx … end` (exact CPTP execution);
  • opt in to the Stinespring dilation — `noise!(q, 𝓝; stinespring=true)` —
    which allocates an explicit environment, applies the dilation, and traces
    it at the enclosing region's exit; on Eager that exit trace is the §3.9
    measure-and-discard unravelling, so ONE RUN IS ONE TRAJECTORY, not the
    channel: average over `shots(f, cap; N=…)`;
  • sample trajectories yourself with `shots` over an Eager context.
```

The opt-in is a **call-site keyword**, not a context policy. Rejected
alternative (§8): a `eager(cap; noise=:dilate)` context flag — the *denotation*
would be unchanged (which is why §4.3 calls pure-vs-mixed "a performance
choice"), but the *resource behaviour* (environment wires, RNG draws, and the
possibility of a loud "no dilation program for this family" failure) is not, and
a program whose failure modes depend on invisible context state is the pattern
this project exists to kill.

On a DM context the flag is **accepted** and produces the identical channel;
that is not a nicety, it is how the headline law test is built (§6:
`Choi(dilated) ≈ Choi(Kraus)` computed on one DM context, both routes).

### 2.2 The algorithm, exactly

Given `𝓝 = {K₀…K_{K−1}}` on `W` wires, `d = 2^W`:

1. **Rank padding.** `e = ceil(Int, log2(K))`; pad with **zero** operators to
   `2^e` terms. Padding is harmless: `Σ Kᵢ†Kᵢ` is unchanged, so `V` stays an
   isometry. `K == 1` ⇒ `e = 0`: the channel is `Ad` of an isometry/unitary and
   **no environment is allocated** (special-cased, not papered over).
2. **Isometry synthesis.** `V : H_S → H_S ⊗ H_E`, `V|ψ⟩ = Σᵢ (Kᵢ|ψ⟩)⊗|i⟩_E`
   (`docs/physics/stinespring_1955_dilation.md` eq (1)/Thm 1). Wire order is
   pinned to the kernel convention **system wires first (MSB), environment last**;
   as a matrix, `V[s·2^e + i, s'] = (Kᵢ)[s, s']`. This lives in ONE function,
   `_dilation_isometry(𝓝)` — the single endianness site (M7 lint discipline).
3. **The TP check IS the isometry check.** `V†V = Σᵢ Kᵢ†Kᵢ = I_d`. Re-asserted
   here to `STINESPRING_ATOL` because it also catches a padding/packing bug.
4. **Unitary completion.** Extend `V`'s `d` orthonormal columns to an
   orthonormal basis of `C^{d·2^e}` by **deterministic modified Gram–Schmidt
   with one reorthogonalization pass** over the standard basis in fixed index
   order: for `j = 1…m`, project `e_j` off the accumulated columns (twice),
   accept if the residual norm exceeds `GS_PIVOT_TOL` relative to 1, normalize,
   append; stop at `m` columns; **fail loud** if fewer than `m` are produced.
   Two properties matter and both are consequences of the construction, not
   hopes: (i) the first `d` columns are **exactly** `V` (no `R`-diagonal phase
   correction is needed, unlike a LAPACK QR), and (ii) the scan order is fixed,
   so the completion is **reproducible** run-to-run — a requirement, since a
   nondeterministic completion would make seeded tests and traced circuits
   irreproducible.
   *Dependency note:* this is ~40 lines in `src/channel/stinespring.jl` and
   keeps `src/` free of `LinearAlgebra` (`src/kernel/numerics.jl` already
   refuses that dependency for `I`). See §8 for the ruling question.
5. **Tolerance discipline (§4.1 float law).** Post-conditions, asserted:
   `maximum(abs, W'W − I) ≤ STINESPRING_ATOL` and `W[:, 1:d] == V` (exact by
   construction). Constants land in `src/kernel/numerics.jl` beside `U2_ATOL`:
   `KRAUS_TP_ATOL = 1e-10`, `STINESPRING_ATOL = 1e-10`, `GS_PIVOT_TOL = 1e-8`.

### 2.3 The artifact rule — ONE mechanism, chosen and justified

```julia
"""
    ChannelArtifact

Supertype of EXECUTION ARTIFACTS: objects produced by a lowering, valid only
inside the boundary that produced them. NOT a `ProcessValue`, NOT a
`ChannelValue`; deliberately outside both trees.

    StinespringDilation{W,E} <: ChannelArtifact

The dilation of a `KrausFamily{W}` on `E` environment wires: the isometry `V`,
the completed unitary `W`, the Kraus rank, and (when available) an executable
`DilationProgram`. It is an ARTIFACT, never a representative of the channel.
"""
abstract type ChannelArtifact end
struct StinespringDilation{W,E} <: ChannelArtifact
    isometry::Matrix{ComplexF64}
    unitary::Matrix{ComplexF64}
    rank::Int
    program::Union{Nothing,DilationProgram}
end
```

**The mechanism: the dilation is not in the process-value tree.** Consequences,
each free from machinery already shipped:

* `ctrl(::StinespringDilation)` — `MethodError`. No method exists, and there is
  no catch-all (`src/kernel/ctrl.jl` header: totality by exhaustive concrete
  methods is *load-bearing* precisely so future non-unitary kinds cannot be
  silently wrapped).
* `ApplyN(v::ProcessValue, ports)` — the field is typed `ProcessValue`, so a
  dilation **cannot enter a `ChannelDAG` at all**. Therefore it cannot be
  `certify`d, cannot become a `UnitaryBlock`, and cannot reach `ctrl`
  *transitively*. This is the part that matters: the transitive path is closed
  by the type system, with no runtime check to forget.
* `apply_pass(::UnitaryPass, ::UnitaryBlock)` cannot see it either.
* Emission is confined to the private `_emit_dilation!` in
  `src/channel/stinespring.jl`, with a **boot lint** mirroring the `_ctrl`
  choke-point lint: the token `_emit_dilation!(` appears in `src/` only in that
  file. `_emit_dilation!` additionally asserts an empty control stack
  (defence in depth — guardrail 1 already fires earlier, at the noise entry).

**Why not "a `ProcessValue` wrapped in a type `ctrl` refuses".** A refusing
method is a runtime guard on *one* entry point; every other `ProcessValue`
affordance (`∘`, `⊗`, `Tensor`, `Seq`, `ApplyN`, `certify`, passes) would still
accept the wrapper, and a future refactor that unwraps "just to compose" silently
re-opens the hole. The shipped precedent is decisive: `ChannelDAG` is kept out of
`ctrl` by *having no method*, not by having an erroring one. Type-level exclusion
is the project's proven pattern, so M11 uses it.

**Second-order honesty.** The dilation *program* emits ordinary kernel values
(`Ry(θ)`, `ctrl(X)`, …), and those are of course controllable — they are gates.
The invariant is not "no controllable value is ever emitted"; it is **"the
composite dilation never becomes a value"**, so no code path can express
"control the noise". Tang–Wright Thm 1.1 is what makes that distinction real:
`ctrl` would resolve the arbitrary completion `W ↦ W·(I_d ⊕ Q)` and the
arbitrary Kraus basis into observable physics.

**Tracing records the channel, never the dilation.** Under `TracingContext`,
`apply!(𝓝)` emits `NoiseN(𝓝, ports)` — even when `stinespring=true` is passed
(the flag is an *execution* choice; the compiler must keep the canonical
representation). Recording a dilation into the IR would bake one arbitrary
completion into every downstream pass and hardware lowering. This is exactly the
ZYZ rule (§4.1/D7): the chart is chosen at the boundary, never in the IR.

### 2.4 The executable-lowering catalogue (the honest scope limit)

The completed `W` is a `(W+e)`-qubit unitary **matrix**. The kernel has no
general multi-qubit synthesis (no QSD/KAK pass exists; `_emit!` handles `U2`,
`Perm`, `Ctrl`, `Tensor`, `Seq`, `UnitaryBlock`). So the mathematics ships for
*every* family; the **executable** lowering ships for a catalogue:

* **Class P — mixed-unitary / Pauli families** `𝓝 = Σᵢ pᵢ Ad_{Uᵢ}`, Kraus
  `{√pᵢ Uᵢ}`. Program: PREPARE `|χ⟩_E = Σᵢ √pᵢ|i⟩` (an `Ry`/controlled-`Ry`
  tree — `e ≤ 2`, i.e. `K ≤ 4`, in M11; the general Grover–Rudolph tree is
  declared kernel territory by PRD §5 and is deferred), then SELECT
  `Σᵢ |i⟩⟨i|_E ⊗ Uᵢ` as `ctrl^e(Uᵢ)` with an X-sandwich anti-control per zero
  bit of `i`. Then `V|ψ⟩|0⟩ = Σᵢ √pᵢ (Uᵢ|ψ⟩)|i⟩` and `Tr_E` returns the family
  **verbatim** — for this class no arbitrary completion is involved at all.
  Covers `bit_flip`, `phase_flip`, `depolarizing`, any Pauli channel, and (the
  M12 hook) a qDrift step's mixture value.
* **Class D — damping.** `amplitude_damping(γ)`: `ctrl(Ry(2θ))` with control =
  system, target = environment, `sinθ = √γ`, then `ctrl(X)` control =
  environment, target = system. Check: `|0⟩|0⟩ ↦ |0⟩|0⟩`;
  `|1⟩|0⟩ ↦ cosθ|1⟩|0⟩ + sinθ|0⟩|1⟩` ⇒ `K₀ = diag(1,√(1−γ))`,
  `K₁ = √γ|0⟩⟨1|` — the textbook family, exactly.
  `phase_damping` is unitarily equivalent to `phase_flip` and routes to class P.
* **Class X — everything else.** Loud error naming the missing capability
  ("arbitrary `(W+e)`-qubit unitary synthesis (QSD/KAK) is not in the kernel")
  and the two escapes (supply `dilation_program=`, or run under `density`).

This split is the honest one: `StinespringDilation` is *complete and tested as
mathematics* (isometry + completion + `Tr_E ∘ Ad_W ∘ (·⊗|0⟩⟨0|) = 𝓝` verified
at the matrix level for arbitrary families), and *partial as execution*.

### 2.5 Environment ownership — the region IS the boundary

`_emit_dilation!` opens an internal `region() do … end`; the environment wires
are `allocate!`d inside it, so they are owned by that frame and **traced at its
exit** (§3.9, silent, no backaction). No environment handle escapes; `noise!`
returns the register handle, never an environment.

Physics of the two exit lowerings, stated plainly because a user will be bitten
by it otherwise:

* **DM** — the exit trace is the exact partial trace (`_RESET_KRAUS` path); the
  result is exactly `𝓝(ρ)`.
* **Eager** — the exit trace is measure-and-discard, the sanctioned §3.9 pure
  lowering. Composing the dilation with that trace **is** the quantum-jump
  unravelling: measuring the environment in the `|i⟩` basis yields branch `i`
  with probability `‖Kᵢ|ψ⟩‖²` and leaves `Kᵢ|ψ⟩/‖·‖`. So one Eager run is one
  trajectory, and `shots` recovers the channel. This also disposes of a
  tempting third mode: **a separate "jump/unravel" policy is unnecessary** —
  it is not different physics, it is (b) composed with a lowering the tree
  already ships.

`keep_environment=true` (returning the environment as live handles for
purification experiments) is **rejected** for M11: it would let the environment
escape the region, at which point "noise" is no longer a channel on its
signature and the P1 denotation breaks. A purification API is its own design.

---

## 3. Q3 — QECC typing (F8): the three typed operations

### 3.1 Where the physical/logical labels ride — and where they must not

F8 asks whether the P/L labels ride the port type, a wrapper, or a `Code` value.
**Answer: neither the port type nor a bare code value — they ride the object
whose interpretation they actually are.**

*Physical vs logical is not a property of a wire.* A single wire is just a wire;
calling it "physical" is meaningful only relative to a chosen code and a chosen
grouping. Putting a label on `Port` (a) would be a deeply invasive change to a
frozen, shipped, F28 structure used by every node, pass, and certificate, and
(b) would be *false* — it would let one wire be "logical" without naming which
code makes it so. So:

| level | carrier of the label | Julia |
|---|---|---|
| register | **the register type** (P7: a register type declares its Hilbert space and structure) | `CodeBlock{C,N,Ctx}` vs bare `QBool{Ctx}` |
| channel | **a thin wrapper carrying the `Code` value** | `PhysicalChannel{C}` / `LogicalChannel{C}` |
| port | *nothing* — ports stay untouched | `Port` unchanged |

This is P7 taken seriously: a code **is** a register type declaration (Hilbert
space = the code space; symmetry structure = the stabilizer group; conjugate
structure = *undefined for a general code*, which is exactly why `dual` is a
loud error on a code block — §3.5).

### 3.2 What a `code` value is

```julia
abstract type AbstractCode end

"""
    StabilizerCode{N,K,S} <: AbstractCode      # S = N − K

An [[N,K,d]] stabilizer code, as generators + logicals + a validated
syndrome→correction table + a certified encoder. Pauli data reuses the SHIPPED
M12 symplectic `PauliWord{N}` algebra (`commutes`, `mulword`, `letter_at`) —
Principle 13: the Pauli group already exists in this tree.
Physics: `docs/physics/gottesman_1997_stabilizer.md` §3 (stabilizer formalism,
[[n,k,d]] parameters, syndrome measurement) and
`docs/physics/knill_laflamme_1997_conditions.md` (the QEC conditions
`P Kᵢ†Kⱼ P = α_{ij} P`, which are what makes the table decoder exact for the
declared correctable set).
"""
struct StabilizerCode{N,K,S} <: AbstractCode
    name::Symbol
    stabilizers::NTuple{S,PauliWord{N}}
    logical_x::NTuple{K,PauliWord{N}}
    logical_z::NTuple{K,PauliWord{N}}
    corrections::NTuple{M,PauliWord{N}} where {M}   # M = 2^S, indexed by syndrome
    encoder::UnitaryBlock{N}                        # certified; decoder = adjoint(encoder)
    declared_distance::Int
end
```

**Construction validates, exactly and over GF(2) — no floats anywhere:**

1. `S == N − K`; no stabilizer is the identity;
2. pairwise commutation of all generators (shipped `commutes`);
3. independence: symplectic GF(2) rank of the `S × 2N` matrix `== S`
   (Gaussian elimination, ~20 lines);
4. every logical commutes with every stabilizer;
5. `commutes(logical_x[i], logical_z[j])` **iff** `i ≠ j` (the symplectic
   pairing of a valid logical basis);
6. **the correction table is self-validating**: for every syndrome `σ`,
   `syndrome(code, corrections[σ]) == σ`. A mis-entered table is a construction
   error, not a silent wrong answer at run time.

Supporting API (`public`): `nphysical`, `nlogical`, `stabilizers`,
`syndrome(code, err::PauliWord{N}) -> Int` (bit `j` set iff `err` anticommutes
with generator `j`), `distance(code)` (the *declared* value), and
`verify_distance(code)` — a brute-force minimum-weight undetectable-logical
search over all `4^N` Paulis, `N ≤ 8`, used in tests. **The bit-flip code's
verified distance is 1**, and the test asserts it (§6): the repetition code
corrects the *bit-flip channel*, not arbitrary single-qubit errors, and the
suite says so out loud.

**Which representation which milestone builds.** M11 builds
*generators + logicals + explicit encoder program + table decoder*. It does
**not** build the general encoder synthesis from generators (Gottesman's
standard-form algorithm / Cleve–Gottesman) nor any decoder beyond table lookup —
both are named, both are later epics (Steane arrives through the reimport gates
with its own distillations, per the plan).

**The encoder is a certified `UnitaryBlock`, obtained for free.** The encoder is
written as a *surface program* on `N` wires (logical in slots `1..K`, fresh
`|0⟩` in `K+1..N`) and reified by the shipped `trace(f, N)`; the traced DAG has
matching in/out lineage and contains only `ApplyN`s, so `certify` mints it with
a `NoAncilla` certificate. `decoder(code) = adjoint(encoder(code))` comes free
from `src/channel/block_algebra.jl`. Two shipped machines, zero new ones.

### 3.3 `encode_state` / `decode_state`

```julia
"""
    encode_state(code::AbstractCode, q::AbstractQubit) -> CodeBlock{typeof(code)}
    encode_state(code::AbstractCode, qs::NTuple{K,AbstractQubit}) -> CodeBlock

The encoding channel `E : L → P` applied to live handles: allocate the `N−K`
ancillas in `|0⟩` (§3.9 "allocation is initialization"), apply the code's
certified encoder block, and return a `CodeBlock` owning all `N` wires. The
input handle(s) are MOVED into the block: they name wires that are no longer
logical registers, so any later use is a loud error (enforced on the shipped
single-sourced consumed set, §4.5).
"""
struct CodeBlock{C<:AbstractCode,N,Ctx<:AbstractContext} <: AbstractQRegister{Ctx}
    ctx::Ctx
    code::C
    wires::NTuple{N,WireID}
end

decode_state(blk::CodeBlock{C,N}) -> NTuple{K,QBool}    # adjoint(encoder), then trace the N−K ancillas
```

`decode_state` applies `adjoint(encoder)` and then **traces** the `N−K` ancilla
wires (§3.9): `D = Tr_anc ∘ Ad_{E†}` — a genuine channel `P → L`, and the reason
`D∘E = id` only *on the code space* (off it, `D` is lossy — which is precisely
the content of the encode∘decode law test).

**Ownership question flagged for a ruling (§8, Q1).** §4.5 says consumption
happens in "exactly two places" (qc casts and `ptrace!`). `encode_state` is
neither: information is not leaving the program, it is being *re-homed*. §3.9
already contemplates "an explicit ownership transfer — D2". M11 implements the
transfer using the existing consumed set (so misuse is loud today) and asks for
a §4.5 wording ruling: *ownership transfer*, or *a third consumption site*.

### 3.4 `effective_logical_noise` — a superchannel as an IR transformation

This is the load-bearing typing decision. The signature:

```julia
"""
    PhysicalChannel{C<:AbstractCode}     # a reified channel whose boundary is ONE code block
    LogicalChannel{C<:AbstractCode}      # a reified channel on the code's K logical wires
"""
struct PhysicalChannel{C<:AbstractCode}
    code::C
    dag::ChannelDAG      # checked: length(qin) == length(qout) == nphysical(code), all quantum, cout empty
end
struct LogicalChannel{C<:AbstractCode}
    code::C
    dag::ChannelDAG      # length(qin) == length(qout) == nlogical(code)
end

"""
    ChannelTransform

A SUPERCHANNEL descriptor: a value naming a map on channel REPRESENTATIONS.
It carries the comb's TEETH (the code, the recovery policy) and never the hole's
contents. It is NOT a `ChannelPass` (§3.4.2) and not a process value.
"""
abstract type ChannelTransform end
abstract type RecoveryPolicy end
struct TableDecoder <: RecoveryPolicy end     # M11's only decoder
struct NoRecovery   <: RecoveryPolicy end     # for studying the bare code (tests)

struct Protect{C<:AbstractCode,R<:RecoveryPolicy} <: ChannelTransform
    code::C
    recovery::R
end
Protect(code::AbstractCode) = Protect(code, TableDecoder())

# The transform, spelled as the physics:
effective_logical_noise(𝓝::PhysicalChannel{C}, θ::Protect{C}) where {C} -> LogicalChannel{C}
(θ::Protect{C})(𝓝::PhysicalChannel{C}) where {C} = effective_logical_noise(𝓝, θ)
```

and the body reads like F8's equation, because `∘` on `ChannelDAG` is
right-to-left (§4.2):

```julia
function effective_logical_noise(𝓝::PhysicalChannel{C}, θ::Protect{C}) where {C}
    E = encode_dag(θ.code)             # K in  → N out   (alloc + certified encoder)
    R = recovery_dag(θ.code, θ.recovery)  # N in  → N out (traced surface program: syndrome + cases)
    D = decode_dag(θ.code)             # N in  → K out   (adjoint encoder + TraceN of the ancillas)
    return LogicalChannel(θ.code, D ∘ R ∘ 𝓝.dag ∘ E)
end
```

**Why an IR transformation and not a runtime higher-order function.** Five
reasons, in descending order of force:

1. **P4 safety.** A runtime `Channel` value handed to a superchannel is an
   object; objects reach `ctrl` (or reach a future combinator that reaches
   `ctrl`). Keeping the superchannel at the IR level means the only things it
   touches are `ChannelDAG` and `KrausFamily`, both of which are *already*
   outside the process-value tree and *already* policed by shipped mechanisms.
   M11 adds a superchannel **without adding a new thing to police**.
2. **The comb IS syntax.** A deterministic one-slot superchannel is exactly a
   circuit with a hole (`docs/physics/chiribella_2009_combs.md` §II, Thm 1:
   every deterministic superchannel factors as `Θ(𝓝) = Tr_M[D∘(𝓝⊗id_M)∘E]`).
   Our `Θ` is the memoryless case (the code's syndrome memory is *inside* `R`,
   not a side wire). Substituting into a hole is an IR operation; there is no
   coherent alternative reading in which it is a runtime value operation.
3. **Only the IR carries the types F8 demands.** A Julia `Function` has no
   arity, no port kinds, no widths, no ownership (F18). `𝓝.dag.qin`/`qout` have
   all four, so the `Θ`-typing check is a real check and not a comment.
4. **Testability.** A `ChannelDAG` replays exactly on DM (`_replay_dm!`,
   shipped), so `Choi(Θ(𝓝))` is computable in one pass and the acceptance tests
   are *channel-level*, never marginal-level (Principle 3, wm28).
5. **Composability.** After `Θ`, the result is an ordinary `ChannelDAG` that
   every shipped executor, pass, and Choi harness already handles.

**Cost, stated honestly:** `Θ` requires a *reified* `𝓝`, i.e. a traceable
program. Channels outside the T1–T4 traceable subset cannot be handed to `Θ` —
the tracer's pre-flight lint reports the offending site, and
`effective_logical_noise` fails loud there. That is a real limitation, and it is
the same limitation the entire M8 compiler story already has.

**Convenience, made explicit rather than implicit:**

```julia
physical_iid(code::AbstractCode, 𝓝::KrausFamily{1}) -> PhysicalChannel   # 𝓝^{⊗N}, one NoiseN per wire
effective_logical_noise(::KrausFamily, ::AbstractCode) =                  # loud, with guidance
    throw(ArgumentError("effective_logical_noise takes a reified PHYSICAL channel, not a bare \
        KrausFamily: a family says WHAT the noise is, not WHERE it acts. Use \
        `physical_iid(code, 𝓝)` for i.i.d. single-wire noise, or `trace(f, n)` for anything else."))
```

#### 3.4.1 `∘` on `ChannelDAG` — the one genuinely new piece of IR machinery

```julia
"""
    ∘(g::ChannelDAG, f::ChannelDAG) -> ChannelDAG      # apply `f` first (§4.2 convention)

Splice two channel graphs. Checks: `length(f.qout) == length(g.qin)`, matching
kinds and widths, all quantum (a CLASSICAL seam — feeding `f`'s record into
`g`'s `CasesN` — is NOT positional composition and is refused loudly in M11).
Relabels `g`'s `PortID`s AND lineages into a space disjoint from `f`'s, then
IDENTIFIES `g.qin[i]` with `f.qout[i]` including LINEAGE — the seam wires are
one physical resource, which is what lets a composite of two endomorphisms
certify as an endomorphism (§1.2). Nested `CasesN` branch DAGs are remapped
recursively. `qin = f.qin`, `qout = remapped(g.qout)`,
`cout = f.cout ++ remapped(g.cout)`.
"""
```

This mirrors `block_algebra.jl`'s `∘(::UnitaryBlock, ::UnitaryBlock)` remapper
(which already solves the disjoint-label problem for blocks) and is its
channel-level sibling. Required law: `Choi(g ∘ f) ≈ Choi(run f then g)` on DM.

#### 3.4.2 Why `Protect` is **not** a `ChannelPass`

The shipped `ChannelPass` contract is *Choi/diamond preservation* of the typed
CPTP denotation with an unchanged boundary. `Θ` deliberately **changes both**
(`N` ports → `K` ports; a different channel by design). Registering it as a pass
would falsify the pass law and poison the `PASS_REGISTRY` lint. So M11 adds a
sibling category with its **own** law and its own registry:

> **Transform law (required test per registered transform).** For every
> `θ::ChannelTransform` and admissible `g`:
> (a) `Choi(θ(g)) ≈ Choi(spec(θ)(g))`, where `spec(θ)` is the composite written
> in the docstring (for `Protect`: `D∘R∘𝓝∘E` assembled independently in the test
> file); and
> (b) the **identity law** `Choi(θ(id_P)) ≈ Choi(id_L)` — encode, recover with no
> noise, decode is the logical identity. This is F8's "encode∘decode = id on the
> code subspace", promoted to a registry-enforced obligation.
> `TRANSFORM_REGISTRY` + a boot lint mirror `PASS_REGISTRY`: a transform cannot
> ship without both laws running against it.

#### 3.4.3 The modelling assumption, named

`Θ(𝓝) = D∘R∘𝓝∘E` is the **code-capacity model**: encoder, recovery, and decoder
are *noiseless*, and syndrome extraction is *perfect*. This is a real, strong
assumption and M11 states it in the docstring, in the PRD amendment, and in the
`fault_tolerant_lift` error message. Nothing in M11 is a fault-tolerance claim
and no threshold statement is made or testable here.

### 3.5 Which surface constructs survive encoding (the F8 point, made concrete)

| surface construct | on `CodeBlock{C}` in M11 |
|---|---|
| 1. `QBool(b)` prep | ✔ as `encode_state(code, QBool(b))` — the cq cast composed with `E` |
| 2. `Bool(blk)` measure | ✔ *for codes that declare a logical readout*: measure all physical wires (casts) and combine the tokens with the shipped T2 classical SSA (for the repetition code, majority `(b₁&b₂)|(b₂&b₃)|(b₁&b₃)`). Returns a scalar (Eager) or a token (DM/Tracing), exactly like the bare cast. |
| 3. `not!(blk)` | ✔ the declared `X̄`, applied as the Pauli it is. **No fault-tolerance claim** (M11's noise model puts no faults on gadgets). |
| 3. `a ⊻= b` between two blocks | ✘ **loud** — transversality is a per-code declaration M11 does not carry. |
| 4. `dual(blk)` | ✘ **loud** — a code's conjugate structure is a *logical Hadamard gadget*, not a view; it is not transversal for the repetition code and not canonical in general. |
| 5. `when(blk)` | ✘ **loud** — a logical-controlled operation is a gadget, not `ctrl` of a declared value. |
| 6. `cases(Bool(blk))` | ✔ free (classical, once construct 2 works) |
| 7. `oracle(f, blk)` | ✘ **loud** — requires FT compilation of the Bennett artifact. |

This table *is* F8's argument, construct by construct: the three ✘ rows are
exactly the places where "lift a logical algorithm" stops being determined by
the code. **Eastin–Knill** (PRL 102 110502,
`docs/physics/eastin_knill_2009_no_universal_transversal.md`) is the theorem
behind the whole column: no code has a universal transversal gate set, so a lift
*must* make protocol choices the code alone does not determine. That is why
`fault_tolerant_lift` is not canonical — not an implementation gap, a theorem.

### 3.6 `fault_tolerant_lift` — interface only, and loudly so

```julia
abstract type FaultModel end
abstract type GadgetSet end
abstract type FTImplementation{C<:AbstractCode} end     # NO concrete subtype in M11

"""
    fault_tolerant_lift(Φ::LogicalChannel{C}, impl::FTImplementation{C}) -> PhysicalChannel{C}

NOT IMPLEMENTED IN M11, BY DESIGN. Lifting a logical channel to a
fault-tolerant physical implementation is NOT determined by the code
(Eastin–Knill: no code admits a universal transversal gate set —
`docs/physics/eastin_knill_2009_no_universal_transversal.md`). It requires FOUR
inputs M11 does not have:
  1. a FAULT MODEL — which locations fault (gate / measurement / idle /
     preparation), i.i.d. or correlated
     (`docs/physics/aliferis_2006_ft_threshold.md`, the ExRec framework);
  2. a GADGET SET — fault-tolerant implementations of the target generators,
     with a per-code transversality declaration (Gottesman 1997 §5);
  3. a MAGIC-STATE / gate-teleportation protocol for the non-transversal
     remainder (Bravyi–Kitaev quant-ph/0403025);
  4. a SCHEDULE — interleaving of syndrome extraction with logical operations,
     under a NOISY-syndrome model (M11's Θ assumes noiseless extraction).
Supply an `FTImplementation` (there is none yet) or use the code-capacity
`effective_logical_noise` and read its assumptions.
"""
fault_tolerant_lift(Φ::LogicalChannel, impl) = throw(ArgumentError(<the message above>))
```

A required test asserts the **message content** (the four ingredients) — an
under-promise, made testable.

---

## 4. Q4 — `classicalise`

### 4.1 A correction to the brief, first

`classicalise` is **not** in `Sturm-v2-IMPLEMENTATION-PLAN.md` (grep: zero
hits). It is a **v0.1 carried contract** from `Sturm-PRD.md` §"Noise":
*"`f_classical = classicalise(ch)` — higher-order cast `Channel → function`
(decoherence). Off-diagonal coherences of the process matrix are discarded,
leaving a classical stochastic map."* The v0.1 review also flagged it as
*"silently single-qubit only"* (`.claude/reviews/2026-04-27` P2-A2.4). So this
is a *fourth* carried contract needing an explicit verdict, and its v0.1 defect
(a silent arity restriction) must not come back.

The brief's phrasing ("the DM→classical-record extraction utility") describes a
**different**, also-useful operation. M11 ships both, under **distinct names**,
because conflating two q→c-flavoured meanings under one name is the exact
pattern §3.6 spends a page killing (sample / record / assert).

### 4.2 `classicalise` — channel → stochastic matrix (the re-derived v0.1 contract)

```julia
"""
    classicalise(g::ChannelDAG)      -> Matrix{Float64}
    classicalise(𝓝::KrausFamily{W})  -> Matrix{Float64}
    classicalise(Φ::LogicalChannel)  -> Matrix{Float64}

The DECOHERED channel `Δ_out ∘ 𝓔 ∘ Δ_in` as a column-stochastic matrix:
`S[b+1, a+1] = ⟨b| 𝓔(|a⟩⟨a|) |b⟩`, size `2^{n_out} × 2^{n_in}`. Computed
EXACTLY (no sampling) by replaying `g` once per computational-basis input on a
`DensityMatrixContext` and reading the output diagonal. Arity is taken from the
DAG's ports — never assumed (the v0.1 defect was a silent single-qubit
restriction); `n_in + n_out > CLASSICALISE_MAXWIRES` fails LOUD.

⚠ PHASE-BLIND BY CONSTRUCTION. `classicalise` discards coherences; it is an
ANALYSIS tool, never a channel-equivalence test. `classicalise(id)` and
`classicalise(Ad_Z)` are the SAME matrix (a required "test of the test").
Channel equality is Choi/diamond — Principle 3 / F3.
"""
```

The QECC payoff is immediate and is why this belongs in M11:
`classicalise(Θ(physical_iid(code, bit_flip(p))))` is a `2×2` matrix whose
off-diagonal **is** `p_L`, so the quantitative QEC statement is read off a
value rather than eyeballed — see §6.

### 4.3 `record_distribution` — the token/record introspection

```julia
"""
    record_distribution(t::ClassicalToken) -> Vector{Float64}

The exact distribution of a measurement RECORD under a `DensityMatrixContext`:
`p[v+1] = Pr(t == v)` over the token's value domain, obtained from the diagonal
of the record c-wires' reduced state (the pinched record
`Σ_γ |γ⟩⟨γ|_C ⊗ ρ̃_γ`, `src/context/density.jl`) with the token's pure evaluator
`t.f` applied per base configuration — exactly the enumeration `cases` already
does (`_config_dict`), so no new physics and no new machinery.

CONTRACT:
  • SIMULATOR INTROSPECTION, in the `statevector`/`density_matrix` family — NOT
    a program construct. It has no hardware meaning; a program that branches on
    its result is DM-only, and the docstring says so.
  • NO backaction: reading the diagonal is not an operation on the state. The
    record stays live and the token stays usable (tokens are copyable, §3.6).
  • Asserts the record wires are still live — a discarded record
    (`discard!`ed or region-exited) is a loud error, never a stale answer.
  • `EagerContext` → loud (outcomes are already scalars: there is no record).
    `TracingContext` → loud (no state exists).
  • Joint form `record_distribution(t1, t2, …)` returns the joint table, which
    is what a syndrome-correlation test needs (§6, the L5/L7 lesson).
"""
```

---

## 5. Q5 — M11 scope cut, and the acceptance example

### 5.1 Ships in M11

1. **Phase 0 — distillations** (before any code that cites them; §9).
2. `ChannelValue` / `KrausFamily{W,K,L}` + validation + `∘`/`⊗`/`≈`/`choi_matrix`;
   named families `bit_flip`, `phase_flip`, `depolarizing`, `amplitude_damping`,
   `phase_damping`, `pauli_channel`, `mixed_unitary`; the `noise!` library verb.
3. Application paths: DM 1-local (native), DM k-local (dense, capped, gated on
   the `state_set` round-trip research step), Tracing (`NoiseN` with the **real**
   family — the reserved stub `KrausFamily(nwires::Int)` is deleted), Eager
   (loud default + `stinespring=true`).
4. Guardrail wiring: `_assert_no_control` on every noise path (closes when.jl
   row 9); `_replay_dm!` gains a `NoiseN` branch, and its *controlled* sibling
   `_replay_branch_controlled!` gains a loud **refusal** for `NoiseN` (noise
   inside a `cases` arm under control is guardrail-1 territory).
5. Stinespring: isometry + completion + tolerances + the catalogue (classes P
   and D) + `StinespringDilation <: ChannelArtifact` + the choke-point emitter +
   its boot lint.
6. `∘(::ChannelDAG, ::ChannelDAG)` (§3.4.1).
7. QECC: `AbstractCode`, `StabilizerCode{N,K,S}` + validation, `bit_flip_code()`,
   `CodeBlock`, `encode_state`/`decode_state`, the surviving-construct methods
   and the four loud refusals (§3.5), `PhysicalChannel`/`LogicalChannel`,
   `ChannelTransform`/`Protect`/`TableDecoder`, `effective_logical_noise`,
   `TRANSFORM_REGISTRY` + lint, `fault_tolerant_lift` interface + loud stub.
8. `classicalise` + `record_distribution`.
9. Staged PRD amendments (§10.3) — written, not applied.

### 5.2 Gated on later epics (explicitly NOT M11)

Steane `[[7,1,3]]` (reimport-gated, its own epic); general encoder synthesis
from generators; decoders beyond table lookup (MWPM/BP/union-find); **noisy
syndrome extraction and any fault-tolerance/threshold statement**; general
`(W+e)`-qubit unitary synthesis (which is what makes the dilation catalogue
partial); `TrajectoryContext{DM}` (noisy trajectories with tokens); Kraus-rank
compression by Choi eigendecomposition; hardware noise transport; the M12
qDrift DM lowering (the *value* lands in M11; wiring `evolve!`'s randomized
strategies to it is an M12 follow-up); correlated/non-Markovian noise (needs
combs with memory wires — the `ChannelTransform` category is shaped for it, but
M11 ships only the memoryless case).

### 5.3 The acceptance example, in surface vocabulary

Encoder — two actions, no gates, no rotations, no process values:

```julia
"The [[3,1,1]] bit-flip encoder: |ψ⟩|00⟩ ↦ α|000⟩ + β|111⟩."
function bitflip_encode!(q1, q2, q3)
    q2 ⊻= q1                       # construct 3 (target LHS, control RHS)
    q3 ⊻= q1
    return (q1, q2, q3)
end
```

Syndrome extraction + correction — constructs 1, 2, 3, 6 and nothing else:

```julia
"""
Recovery for the bit-flip code: measure the two parity checks Z₁Z₂ and Z₂Z₃
into fresh ancillas, then correct. One syndrome value drives all three possible
corrections — the copyable-token customer (§3.6, i4ri §2.2).
"""
function bitflip_recover!(q1, q2, q3)
    a1 = QBool(false)                       # 1: preparation cast
    a2 = QBool(false)
    a1 ⊻= q1;  a1 ⊻= q2                     # 3: parity of (q1,q2) onto a1
    a2 ⊻= q2;  a2 ⊻= q3                     # 3: parity of (q2,q3) onto a2
    s = syndrome(Bool(a1), Bool(a2))        # 2 (twice) + a T2 derivation → 2-bit word
    @cases s begin                          # 6: classical branching on the outcome
        0 => nothing
        1 => not!(q1)
        3 => not!(q2)
        2 => not!(q3)
    end
    return (q1, q2, q3)
end
```

The arm map is the code's validated table, not folklore: `X` on `q1` anticommutes
with `Z₁Z₂` only ⇒ `s = 1`; on `q2` with both ⇒ `s = 3`; on `q3` with `Z₂Z₃`
only ⇒ `s = 2`. The constructor's self-validation (§3.2 rule 6) is what proves
the table above matches the generators.

`syndrome` is a tiny **library** helper (not a construct): a T2-legal derivation
that packs classical bits into a `ClassicalWord{K}`, with a scalar sibling so the
*same source* runs on Eager (scalars, host `if` inside `cases`) and on
DM/Tracing (tokens, instrument-sum executor) — the §3.8 portability contract:

```julia
syndrome(bits::ClassicalBit...) -> ClassicalWord{K}     # tokens: base wires unioned, evaluator composed
syndrome(bits::Bool...)         -> Int                  # Eager trajectory
```

Whole-pipeline use:

```julia
code = bit_flip_code()                              # validated [[3,1,1]]
𝓝   = physical_iid(code, bit_flip(p))               # PhysicalChannel: 𝓝_p^{⊗3}
Φ    = Protect(code)(𝓝)                             # LogicalChannel  — Θ(𝓝) = D∘R∘𝓝∘E
J    = choi(dag(Φ))                                 # exact 4×4 logical Choi (one DM run)
```

**Wire budget for the acceptance test** (it must fit the ≈7-wire exact-Choi cap,
F25/TR8): 1 reference wire + 3 data wires + 2 syndrome ancillas = **6 wires**,
`2⁶ × 2⁶` DM = 4096 complex entries. Comfortable. The `cases` fan-in is 2 record
wires ⇒ 4 configurations, far under `CASES_MAX_FANIN = 16`.

---

## 6. Q6 — Test plan

Named `@testset`s, PRD-section-grep-able, in `test/test_m11_noise.jl`,
`test/test_m11_stinespring.jl`, `test/test_m11_qecc.jl`.

**Noise values**

* `M11.NOISE.CPTP-AT-CONSTRUCTION` — a non-TP family throws, message contains
  `maximum(abs, ΣK†K − I)`; a valid one constructs; the check is toleranced at
  `KRAUS_TP_ATOL`; **no** silent renormalization (assert the thrown type).
* `M11.NOISE.CHOI-1LOCAL` — `Choi(noise!(q, bit_flip(p)))` ≈ the analytic
  `(1−p)J(id) + p·J(Ad_X)`, several `p`, exact on DM.
* `M11.NOISE.ALGEBRA` — `Choi(a ∘ b)` ≈ sequential application;
  `Choi(a ⊗ b)` on 2 wires; `≈` is Choi-level (a *different* Kraus family for
  the same channel, produced by a unitary mixing `u`, satisfies `a ≈ b` while
  `a != b` — the F26 split, tested).
* `M11.NOISE.CTRL-UNREPRESENTABLE` — `@test_throws MethodError ctrl(𝓝)`;
  `@test_throws MethodError adjoint(𝓝)`; `!(𝓝 isa Sturm.ProcessValue)`;
  `ApplyN(𝓝, (PortID(1),))` throws (type-level exclusion);
  `@test_throws ArgumentError certify(dag_with_NoiseN)` (shipped, re-asserted
  with a real family payload).
* `M11.NOISE.WHEN-GUARDRAIL` — `when(q) do noise!(r, bit_flip(0.1)) end` throws
  with the guardrail-1 message, on Eager **and** DM, and via `apply_channel!`
  directly (the currently-unwired path).
* `M11.NOISE.TRACING-RECORDS-CHANNEL` — `trace(f, 1)` of a noisy program yields a
  DAG with a `NoiseN` carrying the real family, **and no `AllocN`**, even when
  `stinespring=true` was requested (the compiler keeps the canonical form).

**Stinespring**

* `M11.STINE.ISOMETRY` — `V†V ≈ I` for every catalogue family and for random
  valid families (TP ⟺ isometry).
* `M11.STINE.COMPLETION` — `W†W ≈ I`; `W[:,1:d] == V` exactly; determinism
  (constructing twice gives identical matrices).
* `M11.STINE.DILATION-DENOTES-THE-CHANNEL` (matrix level, general families) —
  `Tr_E[W(ρ⊗|0⟩⟨0|)W†] ≈ 𝓝(ρ)` for random ρ and random valid families,
  including families **outside** the executable catalogue.
* `M11.STINE.CHOI-EQUALS-KRAUS` (execution level, headline law) — on ONE DM
  context, `Choi(noise!(q, 𝓝; stinespring=true)) ≈ Choi(noise!(q, 𝓝))` for
  `bit_flip`, `depolarizing`, `amplitude_damping`.
* `M11.STINE.ARTIFACT-UNREACHABLE` — `@test_throws MethodError ctrl(dilation)`;
  `!(dilation isa Sturm.ProcessValue)`; `ApplyN(dilation, …)` throws;
  `@test_throws MethodError apply_pass(Fuse1qPass(), dilation)`; the boot lint
  asserts `_emit_dilation!(` occurs in `src/` only in `channel/stinespring.jl`.
* `M11.STINE.EAGER-POLICY` — default Eager noise throws, and the message names
  all three escapes; with `stinespring=true` it runs; `shots(…; N=2000)`
  agreement with the DM-exact marginal at ±3σ.
* `M11.STINE.ENV-OWNERSHIP` — `live_wires` returns to baseline after the call;
  100 sequential applications do not grow the slot high-water mark (the region
  really does close the environment).
* `M11.STINE.CATALOGUE-BOUNDARY` — a family outside classes P/D throws, and the
  message names the missing kernel capability.

**QECC**

* `M11.QECC.CODE-VALIDATION` — commuting/independent generators; logical
  (anti)commutation; the self-validating correction table; four deliberately
  broken codes each throw the *specific* error.
* `M11.QECC.DISTANCE-IS-ONE` — `verify_distance(bit_flip_code()) == 1`. The
  repetition code is `[[3,1,1]]`; the suite refuses to imply otherwise.
* `M11.QECC.CODESPACE` — the encoder maps into the joint `+1` eigenspace:
  applying each stabilizer Pauli to an encoded state leaves the DM invariant.
* `M11.QECC.ENCODE-DECODE-ID` — `Choi(decode_state ∘ encode_state) ≈ Choi(id)`,
  the 4×4 logical Choi, coherently probed (a Bell half — the wm28 gate).
* `M11.QECC.EFFECTIVE-NOISE-EXACT` — **the quantitative pin**:
  `Θ(physical_iid(code, bit_flip(p)))` ≈ `bit_flip(3p² − 2p³)` **exactly** at
  the Choi level, for `p ∈ {0.01, 0.05, 0.1, 0.3, 0.5, 0.7}`.
  Derivation (in the test's docstring and the distillation): residual = `X̄` iff
  the error weight is ≥ 2 (weight 2 ⇒ syndrome points at the third qubit, and
  `X₁X₂·X₃ = X̄`; weight 3 ⇒ trivial syndrome, `X₁X₂X₃ = X̄`), so
  `p_L = 3p²(1−p) + p³ = 3p² − 2p³`.
* `M11.QECC.BELOW-AND-ABOVE-THRESHOLD` — `p_L < p` for `p < ½` **and**
  `p_L > p` for `p > ½` (`p_L − p = −p(1−p)(1−2p)`). Testing the *failure* side
  is what keeps the claim honest: the code makes things worse above threshold,
  and the suite says so.
* `M11.QECC.PHASE-NOISE-IS-WORSE` (the wm28-shaped anti-test) —
  `Θ(physical_iid(code, phase_flip(p)))` ≈ `phase_flip((1 − (1−2p)³)/2)`, which
  for small `p` is ≈ `3p`: the bit-flip code **amplifies** phase noise. A
  population-only probe cannot see this; the Choi test can.
* `M11.QECC.INDEPENDENT-REFERENCE` — for `depolarizing(p)` the expected logical
  Pauli channel is computed by a **test-side brute-force enumerator** over all
  `4³` Pauli error patterns (syndrome → table correction → residual class),
  and compared to the executed Choi. An independent reference implementation,
  not a pinned number (Principle 3).
* `M11.QECC.SUPERCHANNEL-TYPING` — arity mismatch is loud;
  `effective_logical_noise(::KrausFamily, code)` points at `physical_iid`;
  the result is a `LogicalChannel{C}` with `K` in/out ports;
  `@test_throws MethodError ctrl(Φ)`; `@test_throws MethodError ctrl(Protect(code))`.
* `M11.QECC.SURFACE-BOUNDARY` — the four refusals of §3.5 (`dual(blk)`,
  `when(blk)`, `blk₁ ⊻= blk₂`, `oracle(f, blk)`) each throw with their
  code-specific message; `not!(blk)` and `Bool(blk)` work and are verified
  against the logical operators.
* `M11.QECC.SYNDROME-TOKEN-REUSE` — one syndrome token drives two corrections;
  the resulting record/data correlation is probed **coherently** (X on one wire,
  Z on another — the L5 lesson: a population-only probe is blind to it).
* `M11.QECC.FT-LIFT-HONEST` — `fault_tolerant_lift` throws, and the message
  names all four missing ingredients.
* `M11.TRANSFORM.LAW` / `M11.TRANSFORM.IDENTITY` — the two registry-enforced
  laws (§3.4.2), plus the boot lint asserting every registered transform has
  both.

**`classicalise` / records**

* `M11.CLASSICALISE.STOCHASTIC` — columns sum to 1; identity/bit-flip/Hadamard
  channels give the expected matrices; arity taken from ports (a 2-in/2-out DAG
  gives a 4×4 — the v0.1 silent-single-qubit defect cannot recur).
* `M11.CLASSICALISE.IS-PHASE-BLIND` — `classicalise(id) == classicalise(Ad_Z)`,
  asserted deliberately, with a comment naming it as the reason `classicalise`
  is never a channel-equivalence test.
* `M11.CLASSICALISE.QECC` — `classicalise(Θ(𝓝_p))[2,1] ≈ 3p² − 2p³` (the
  quantitative statement read off a value).
* `M11.RECORD.DISTRIBUTION` — matches the DM diagonal computed independently;
  joint form matches the joint diagonal; loud on Eager/Tracing; loud on a
  discarded record.

**Boot lints added:** the dilation choke-point lint; the `TRANSFORM_REGISTRY`
law-coverage lint; and the physics-cite lint now has ~7 new citation paths to
resolve.

---

## 7. Error taxonomy (S13, one table)

| situation | exception | where |
|---|---|---|
| `Σ K†K ≠ I`, bad operator shapes, `p ∉ [0,1]` in a named family | `DomainError` / `ArgumentError` | `KrausFamily` constructor |
| rank/data above the frozen-tuple ceiling | `ArgumentError` naming `⊗`/wire-by-wire | constructor |
| noise on a pure context, no opt-in | `ErrorException` naming the three escapes | `apply!`/`noise!` |
| family outside the dilation catalogue | `ArgumentError` naming the missing kernel capability | `_stinespring_dilation` |
| completion failed to reach full rank / `W†W ≉ I` | `ErrorException` (numerics failure) | completion |
| noise under `when` | `ErrorException`, shipped guardrail-1 message | `_assert_no_control` |
| `ctrl` on a `KrausFamily`, `LogicalChannel`, `Protect`, or dilation | **`MethodError`** (no method exists) | — |
| invalid stabilizer set / logicals / table | `ArgumentError` naming the failed condition | code constructor |
| arity mismatch into `Θ` or `∘(::ChannelDAG,…)` | `ArgumentError` with both arities | transform / compose |
| `dual`/`when`/`⊻=`/`oracle` on a `CodeBlock` | `ArgumentError` naming the missing gadget | `src/qecc/blocks.jl` |
| `fault_tolerant_lift` | `ArgumentError` naming four missing inputs | `src/qecc/ft.jl` |
| `record_distribution` on Eager/Tracing or a dead record | `ArgumentError` | `src/channel/kraus.jl` |

---

## 8. Risks, alternatives rejected, open questions

### 8.1 Risks

1. **The Orkan 1-local ceiling** is the hardest external constraint: no k-local
   channel entry, no pure-state channel path. Mitigation: 1-local native +
   capped dense DM path + the dilation route; every fallback loud.
2. **No general unitary synthesis** ⇒ the dilation catalogue is partial. Users
   with a bespoke Kraus family on a pure context will hit the loud error. This
   is scoped honestly rather than papered over; the fix (a QSD/KAK synthesis
   pass producing a `UnitaryBlock`) is a well-defined later item — and note it
   would *not* weaken the artifact rule, since the synthesized block would be
   built inside the emitter and never returned.
3. **`∘(::ChannelDAG, ::ChannelDAG)` must remap nested `CasesN` branches** and
   unify seam lineage. This is the most intricate new code in M11 and is where
   a silent bug would hide; mitigated by a Choi law test and by mirroring the
   shipped `block_algebra.jl` remapper.
4. **`_replay_dm!` currently `error`s on `NoiseN`** — M11 must extend both the
   plain and the controlled replay paths (the latter to *refuse*).
5. **Rank explosion** under repeated `∘` of families; capped loudly, compression
   deferred.
6. **`state_set` on `MIXED_TILED`** is unverified for element-wise write-back
   (the dense DM path's gate; §1.6). Named as a research step, not assumed.
7. **wm28 class** — the entire QEC result could be "verified" by populations and
   be wrong. Mitigated structurally: every acceptance test is Choi-level, plus
   the deliberate phase-noise anti-test and the coherent syndrome-correlation
   probe.
8. **Scope creep into fault tolerance.** The `CodeBlock` surface methods (§3.5)
   are the thin end of that wedge. Mitigated by the four loud refusals and by
   the no-FT-claim docstrings — and it is the single most likely place a
   reviewer will want to cut further (see §8.3 Q3).

### 8.2 Alternatives considered and rejected

* **Kraus family as a `ProcessValue` with an erroring `ctrl`.** Rejected: a
  runtime refusal guards one door; `∘`, `⊗`, `Tensor`, `ApplyN`, `certify`, and
  passes are all other doors. Type-level exclusion is the shipped pattern
  (`ChannelDAG` has no `ctrl` method, not an erroring one).
* **Context-level noise policy (`eager(cap; noise=:dilate)`).** Rejected: the
  denotation is context-independent, but the resource behaviour and the failure
  modes are not, and invisible context state deciding whether a program throws
  is precisely the silent-wrongness pattern. Call-site opt-in wins.
* **A separate "jump/unravel" pure-context mode.** Rejected as *redundant*, not
  as wrong: dilation + the shipped §3.9 measure-and-discard trace **is** the
  jump unravelling. Two spellings of one physics is exactly what §3.6 warns
  against. (A `TrajectoryContext{DM}` remains a named future for *efficiency* —
  sampling a branch directly avoids needing a circuit — not for semantics.)
* **`effective_logical_noise` as a runtime HOF `Function → Function`.**
  Rejected: no port types (F18), no checkability, and it makes a channel an
  opaque object flowing through user code — the P4 hazard the stratification
  exists to prevent. It has exactly one advantage (works on untraceable
  programs), and those programs have no superchannel semantics anyway.
* **A first-class `Channel{In,Out}` runtime value type.** Rejected: it would be
  stratum-3 reified, duplicating `ChannelDAG` while *looking* controllable. F18
  asked for a reification API, and `trace(f, nin)` already is one.
* **Registering `Protect` as a `ChannelPass`.** Rejected: passes must preserve
  Choi and the boundary; `Θ` changes both by design. A new category with its own
  law and registry is the honest structure.
* **Labels on `Port`.** Rejected: invasive to a frozen shipped structure, and
  false — "logical" is a property of an interpretation of a *group* of wires
  relative to a code, not of a wire.
* **LAPACK QR (via `LinearAlgebra`) for the completion.** Rejected in favour of
  hand-rolled Gram–Schmidt: `src/` currently takes **no** stdlib dependency
  (`numerics.jl` refuses `LinearAlgebra` even for `I`), and the hand-rolled scan
  has a real advantage — the first `d` columns come out *exactly* `V`, with no
  `R`-diagonal phase correction to get subtly wrong. (Ruling question below.)
* **Auto-lifting a bare `KrausFamily` into a physical channel inside `Θ`.**
  Rejected: "where does the noise act" is information the family does not carry;
  `physical_iid` makes it explicit.

### 8.3 Open questions needing a Tobias ruling

1. **`encode_state` ownership.** Is moving a handle into a `CodeBlock` an
   *ownership transfer* (D2/§3.9) or a *third consumption site* (§4.5 says
   "exactly two")? M11 implements it on the shipped consumed set either way;
   the ruling decides the PRD wording and the error message.
2. **`classicalise` naming.** Ship the v0.1 meaning (channel → stochastic
   matrix, my proposal) under that name and `record_distribution` for the
   token introspection? Or rename? Two q→c-flavoured meanings must not share
   one name.
3. **How much surface survives encoding.** §3.5 ships `not!(blk)` and
   `Bool(blk)`; a stricter ruling would ship *no* logical operations in M11 and
   gate everything behind `fault_tolerant_lift`. I recommend shipping the two
   (they are unambiguous, and P6 asks for exactly this), but the conservative
   call is defensible.
4. **Export set.** `noise!`, `encode_state`, `decode_state`, and the named
   families exported (like `evolve!`/`amplify`/`Trotter`), with the IR-level
   superchannel machinery `public`? That is my proposal; the alternative is
   `public` throughout.
5. **`LinearAlgebra` in `src/`** — hand-rolled completion (proposed) vs adding
   the stdlib dependency (CLAUDE.md conv 4 says core depends only on Orkan).
6. **`noise!` name collision** with the shipped `noise!(::DAGBuilder, ports…)`.
   Rename the builder method to `noise_node!` (proposed) or keep both
   (dispatch is unambiguous, but the reader must think).
7. **k-local DM noise** — ship the dense capped path (gated on the `state_set`
   round-trip verification), or make `W ≥ 2` application a loud error until
   Orkan grows a `channel_kq`?
8. **`≈` on `KrausFamily` as Choi equality** — semantically right, but it is an
   O(4^W) computation behind an operator that *looks* cheap. Acceptable, or
   should it be spelled `same_channel(a, b)` with `≈` left undefined?
9. **Does `Θ` belong to M11 at all if `∘(::ChannelDAG,…)` slips?** If the
   splice turns out harder than estimated, the fallback is a *direct-execution*
   `Θ` (run E, 𝓝, R, D in one DM region and Choi the result) — same tests, no
   IR composition, but no reusable superchannel value. I recommend against
   pre-committing to the fallback; flagging it as the contingency.

---

## 9. Citation map — required distillations (prerequisite work items)

Per CLAUDE.md rule 4 (two-tier: local PDF **and** a `docs/physics/*.md`
distillation with theorem/equation/page numbers), and per the boot lint that
resolves every `docs/physics/...md` path appearing in `src/`. **None of these
exists today; each must be written before the code that cites it.**

| distillation (new) | what it must pin | cited by |
|---|---|---|
| `stinespring_1955_dilation.md` | Thm 1 (dilation existence), minimality, **uniqueness up to a partial isometry on the environment** | `stinespring.jl`, §2 |
| `choi_1975_cp_maps.md` | Thm 1 (CP ⟺ Kraus form), Thm 2 (**unitary freedom** of Kraus families), the Choi matrix as canonical | `kraus.jl`, `≈`, §0 |
| `gottesman_1997_stabilizer.md` | §3 stabilizer formalism, `[[n,k,d]]`, syndrome measurement, logical operators; §5 transversality | `qecc/codes.jl` |
| `knill_laflamme_1997_conditions.md` | the QEC conditions `P Kᵢ†Kⱼ P = α_{ij}P` (why a table decoder is exact on the declared correctable set) | `qecc/codes.jl`, `superchannel.jl` |
| `chiribella_2009_combs.md` | superchannel = circuit with a hole; the `Θ(𝓝) = Tr_M[D∘(𝓝⊗id)∘E]` factorization | `qecc/superchannel.jl`, §3 |
| `eastin_knill_2009_no_universal_transversal.md` | the no-go: no code has a universal transversal gate set | `qecc/ft.jl`, §3.5 |
| `aliferis_2006_ft_threshold.md` | the ExRec fault model + threshold framework (scoping only — M11 makes **no** FT claim) | `qecc/ft.jl` error message |
| `repetition_code_effective_noise.md` (derivation note) | `p_L = 3p² − 2p³`; the phase-noise amplification `(1−(1−2p)³)/2`; the depolarizing enumeration | the QECC tests |

Reused, already present: `tang_wright_2025_controlled_unitaries.md` (Thm 1.1 —
control makes phase physical: the artifact rule's teeth),
`bennett_1973_logical_reversibility.md`, `delorme_control_as_constructor.md`,
`hagan_wiebe_2023_composite.md` (the `PauliWord` provenance).

*Two-tier gap to flag:* the Gram–Schmidt "twice is enough" reorthogonalization
rule is numerical analysis, not physics. Either it gets a one-page
`docs/physics/` note (stretching the folder's charter) or it is cited only in a
code comment without a `docs/physics/` path. I propose the latter, and flag it
so the two-tier policy is applied by decision rather than by drift.

---

## 10. File layout, namespace, build order, staged PRD edits

### 10.1 Files

```
src/channel/kraus.jl         # ChannelValue, KrausFamily, algebra, choi_matrix, classicalise, record_distribution
src/channel/compose.jl       # ∘(::ChannelDAG, ::ChannelDAG) + recursive CasesN remapping
src/channel/stinespring.jl   # StinespringDilation, isometry, completion, catalogue, _emit_dilation! (CHOKE POINT)
src/library/noise.jl         # named families + the `noise!` verb
src/qecc/codes.jl            # AbstractCode, StabilizerCode + GF(2) validation, bit_flip_code, syndrome, distance
src/qecc/blocks.jl           # CodeBlock, encode_state/decode_state, surviving constructs + the four refusals
src/qecc/superchannel.jl     # Physical/LogicalChannel, ChannelTransform, Protect, effective_logical_noise, registry
src/qecc/ft.jl               # FaultModel/GadgetSet/FTImplementation + the loud fault_tolerant_lift
test/test_m11_noise.jl  test/test_m11_stinespring.jl  test/test_m11_qecc.jl
docs/physics/*.md            # the eight new distillations of §9
```

Include order (all after M8's channel IR and M12's `PauliWord`):
`kraus.jl → compose.jl → stinespring.jl → library/noise.jl → qecc/codes.jl →
qecc/blocks.jl → qecc/superchannel.jl → qecc/ft.jl`.

### 10.2 Namespace (CLAUDE.md conv 8)

* `export` — the physicist-facing verbs and vocabulary, matching the M10/M12
  precedent (`evolve!`, `amplify`, `Trotter`): `noise!`, `encode_state`,
  `decode_state`, `bit_flip`, `phase_flip`, `depolarizing`, `amplitude_damping`,
  `phase_damping`, `mixed_unitary`, `pauli_channel`.
* `public` — everything compiler/analysis-level: `ChannelValue`, `KrausFamily`,
  `krausrank`, `kraus_matrices`, `choi_matrix`, `classicalise`,
  `record_distribution`, `StinespringDilation`, `ChannelArtifact`,
  `AbstractCode`, `StabilizerCode`, `CodeBlock`, `bit_flip_code`, `syndrome`,
  `nphysical`, `nlogical`, `distance`, `verify_distance`, `PhysicalChannel`,
  `LogicalChannel`, `physical_iid`, `ChannelTransform`, `Protect`,
  `TableDecoder`, `NoRecovery`, `effective_logical_noise`, `TRANSFORM_REGISTRY`,
  `FaultModel`, `GadgetSet`, `FTImplementation`, `fault_tolerant_lift`.
* **No new surface construct.** The seven stand.

### 10.3 Staged PRD amendments (written in the design doc, applied by the PRD pass)

* **§4.3** — extend the application table with the `KrausFamily` row and the
  pure-context policy (default loud; explicit `stinespring=true`; the "one Eager
  run is one trajectory" note).
* **§4.4** — replace the two-row stratification with the three-stratum table of
  §0 (process values / channel **representations** / denotations) and state the
  one-line theorem that forbids `ctrl` on stratum 2.
* **§5** — replace *"QECC (P6): unchanged — `encode(ch, code)` is
  `Channel → Channel`"* with the three typed operations, the code-capacity
  assumption, and the Eastin–Knill statement of why the lift is not canonical.
  **This is the F8 carried-contract closure** (plan §7 verdict (c) — the single
  remaining (c) in the table).
* **§3.8** — add a noise row to the portability table
  (Eager: loud / opt-in dilation; DM: exact; Tracing: `NoiseN`).
* **§4.5 / §3.9** — the `encode_state` ownership-transfer wording, per ruling 1.
* **§9 Citations TODO** — add the eight distillations of §9.

### 10.4 Build order (slices, each ending green)

1. Distillations (§9) — no code.
2. `KrausFamily` + algebra + DM 1-local + Tracing `NoiseN` + guardrail wiring +
   `M11.NOISE.*`.
3. Stinespring mathematics + catalogue + artifact rule + choke-point lint +
   `M11.STINE.*`.
4. `∘(::ChannelDAG, ::ChannelDAG)` + its Choi law.
5. `StabilizerCode` + validation + `bit_flip_code` + `CodeBlock` +
   encode/decode + `M11.QECC.CODE-*`/`ENCODE-DECODE-ID`.
6. `Protect`/`effective_logical_noise` + registry + lint + the acceptance
   example + `M11.QECC.EFFECTIVE-*`/`PHASE-NOISE-IS-WORSE`/`INDEPENDENT-REFERENCE`.
7. `classicalise`, `record_distribution`, `fault_tolerant_lift` stub, staged PRD
   text, worklog.
