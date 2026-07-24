# M11 design proposal A — noise values, the Stinespring dilation contract, and QECC superchannel typing

**Bead:** `Sturm.jl-82su` · **Round:** 3+1, proposer A (blind) · **Gates:** review findings F8, F33
· **Plan:** `Sturm-v2-IMPLEMENTATION-PLAN.md` §M11 + §7 verdict (c) · **Spec:** `Sturm-PRD-v2.md`
§3.6, §3.9, §4.1a, §4.2, §4.3, §4.4, §6

> **Reading discipline.** Everything below was derived against the *shipped* code
> (`src/channel/`, `src/kernel/ctrl.jl`, `src/context/`, `src/surface/tokens.jl`,
> `src/surface/cases.jl`, `src/orkan/ffi.jl`) and the *actual* Orkan headers
> (`../orkan/include/channel.h`, `gate.h`). No Julia was executed (exclusive-Julia
> rule, session 102). Where I found a gap in shipped code I say so in §0 rather
> than assuming it away.

---

## Decisions at a glance

| # | Question | Decision |
|---|---|---|
| D1 | Noise value type | A **mirror-image channel-value algebra**: `abstract type ChannelValue end` with `KrausFamily{N,R,L}`, `MixedUnitary{N,R}`, `ChannelTensor`, `ChannelSeq` — structurally parallel to `U2`/`Perm`/`Tensor`/`Seq`, but with **no `ctrl` method, ever**, and **no mixed-signature `∘`/`⊗` with `ProcessValue`** |
| D2 | Denotation map | `channel(v::ProcessValue) -> KrausFamily` is §4.4's quotient made a function: total, one-way, no inverse exists (type-level) |
| D3 | CPTP obligation | CP is free (operator-sum form); **TP is checked at construction**, toleranced at `KRAUS_TP_ATOL = 1e-12`, `ArgumentError` naming the max deviation. Never silently renormalised |
| D4 | Application | `apply!(ctx, ::ChannelValue, wires)` — same surface (§4.3), plus a handle-level `apply_noise!`. `public`, **not exported**: the seven surface constructs are untouched |
| D5 | Dilation artifact rule | The dilation unitary **is never a `ProcessValue` and subtypes nothing**. It lives in a `Dilation` struct holding a raw `Matrix{ComplexF64}` reachable only by a private emitter. `ctrl` gets `MethodError` at zero cost; a "wrapper `ctrl` refuses" is **rejected** (§2.5) |
| D6 | Completion algorithm | Hand-rolled **Householder QR + diagonal phase fix** (no `LinearAlgebra` — core has none). Deterministic, tolerance-free *in the algorithm*; tolerances appear only in post-condition asserts |
| D7 | When the fallback fires | **Never implicitly, in any context.** `stinespring = true` is a required, greppable opt-in; without it a context that has no native path errors loudly and names the flag |
| D8 | Superchannel typing (F8) | `effective_logical_noise` is a **compiler transformation on `ChannelDAG`**, not a runtime value: `Superchannel` is a callable comb, `Θ(𝓝::ChannelDAG)::ChannelDAG`. Justified by the comb formalism (a comb *is* a circuit with a hole) and by §4.4 |
| D9 | Logical/physical labels | Ride the **register-handle type** (`Encoded{C}`), never the `PortKind`. A logical qubit is a property of a *bundle + code*, not of a wire — adding a `LogicalPort` would be a physics lie |
| D10 | `fault_tolerant_lift` | Ships as **interface + loud refusal only**. No concrete method exists in M11. Named, not implemented |
| D11 | M11 executable scope | Full generality for *construction + verification*; **execution of a dilation ships only for the mixed-unitary family** (Orkan has no dense-unitary entry — §0.3). Honest gap, named unblock |

---

## §0 — Findings in shipped code (read before designing)

These are things M11 must fix or work around. Each is a defect or a missing
promise I found while reading, not a hypothetical.

### 0.1 Guardrail 1 does **not** cover noise (a real hole)

`src/surface/when.jl`'s coverage map row 9 says
`apply_channel! (DM noise) | Kraus | _apply_channel_1q! | BANNED — forward hook (M8/M11)`.
It is still a *forward hook*: `apply_channel!` (`src/context/density.jl:86`) calls
`_flush_wire!` and `_apply_channel_1q!` and **never calls `_assert_no_control`**
(verified: the only call sites are qmod/qint/casts/casts/ptrace!/actions/cases —
`grep -n '_assert_no_control' src/`). So today

```julia
when(c) do
    Sturm.apply_channel!(ctx, kmats, w)   # silently applies noise under a live control frame
end
```

is *silent*, and the emitted noise is uncontrolled while the user wrote it inside
a control body. That is a P4 violation shipping quietly. **M11 closes row 9**: the
new `apply_noise!` funnel calls `_assert_no_control` *first*, and the legacy
`apply_channel!` gains the same assert. Named test `M11.NOISE.GUARDRAIL-1`.

### 0.2 §4.4 promises channel-level `∘` and `⊗`; neither exists

The §4.4 stratification table row 2 reads: *Channels · denotations; casts, noise,
`ptrace!`, `cases`, `ChannelDAG` · **composition, tensor** · ✘ ctrl*. There is no
`Base.:∘(::ChannelDAG, ::ChannelDAG)` and no `⊗` in `src/channel/`. The
superchannel of §3 cannot be built without them, so M11 ships them (§3.4).

### 0.3 Orkan has **no** general dense-unitary entry, and **no** multi-qubit channel

Verified against the live headers, not from memory:

- `../orkan/include/channel.h`: exactly two symbols — `kraus_to_superop(const kraus_t*)`
  and `channel_1q(state_t*, const superop_t*, qubit_t)`. **1-local only.**
  `src/orkan/ffi.jl:243` even *guards* `sop.n_qubits == 1`.
- `../orkan/include/gate.h`: `x y z h s sdg t tdg hy rx ry rz p cx cy cz swap_gate ccx`.
  **No `unitary_kq`, no dense-matrix apply.**

Two consequences that shape the whole M11 scope:

1. A **k-local (k ≥ 2) Kraus channel has no native lowering on any context.**
   Correlated 2-qubit noise cannot be applied except through a dilation.
2. A general dilation unitary `U ∈ U(2^{N+E})` **cannot be applied at all**, because
   applying a dense unitary would need either an Orkan entry or a KAK/QSD synthesis
   pass. Neither exists.

This is why D11 splits the dilation into "constructed + verified, fully general"
vs "executable, mixed-unitary only". Pretending otherwise would be the exact
overreach the brief warns against.

### 0.4 `select` has no host-scalar methods, so the syndrome example is not Eager-portable

`src/surface/tokens.jl` defines `select(::ClassicalBit, ::Integer, ::Integer)`,
`select(::ClassicalBit, ::Bool, ::Bool)`, `select(::ClassicalWord, ::AbstractVector)`,
`select(::ClassicalWord, ::ClassicalTable)`. Under **Eager** the measurement casts
return real scalars (§3.6), so `select(syn, table)` with `syn::Int` is a
`MethodError`. The M11 acceptance example (§5.3) is the first program that needs
`select` to be portable across all three contexts. M11 adds three tiny methods with
the *same* totality checks (§5.4, work item W4).

### 0.5 `_replay_dm!` errors on `NoiseN`

`src/context/tracing.jl:492` — `error("_replay_dm!: unsupported node $(typeof(nd))")`.
A traced program containing noise cannot be replayed, so the Choi law tests for
noise-bearing DAGs (and hence for `effective_logical_noise`) do not run. M11 adds
the `NoiseN` branch.

### 0.6 `KrausFamily` is a one-field stub and `NoiseN` must change shape

`src/channel/dag.jl:85` — `struct KrausFamily; nwires::Int; end`, carried by
`NoiseN(kraus::KrausFamily, ports)`. Replacing the stub is a **core change**
(`src/channel/`) and is exactly what this 3+1 round is for. Blast radius is small
and enumerable: `src/channel/dag.jl` (struct + `NoiseN` field), `src/channel/builder.jl`
(`noise!`), `src/Sturm.jl` (`public` list), `src/context/tracing.jl` (replay branch).
Nothing else in `src/` references `KrausFamily` (verified by grep).

### 0.7 `src/` deliberately has no `LinearAlgebra` dependency

`src/kernel/numerics.jl:196` and `src/channel/replay.jl:16` both say so explicitly,
and `_eye(n)` exists *because* `Matrix{ComplexF64}(I,n,n)` would pull it in.
`Project.toml` lists `LinearAlgebra` only under `[extras]`/`test`. Therefore **the
unitary completion must be hand-rolled**, and Kraus-rank compression (which needs an
eigendecomposition of the Choi matrix) is out of scope for M11.

---

## §1 — Kraus channel values (design question 1)

### 1.1 The type tree: a mirror of the process-value tree

The clearest way to make §4.4's stratification *legible in the code* is to give the
channel level the same shape as the process level, and to let the **absence** of
methods carry the theorem.

```julia
# src/channel/channel_values.jl  (STRUCTS; included after kernel/perm.jl, before channel/ports.jl)

"""
    ChannelValue

Supertype of the CHANNEL-LEVEL values (PRD-v2 §4.4 row 2): syntactic
representations of CPTP maps. Deliberately NOT `<: ProcessValue`.

The stratification is enforced by ABSENCE, not by refusal:

  • `ctrl` has no method for any `ChannelValue` and never will — control on a
    non-unitary effect is unrepresentable (P4, §1.1 theorem), and the shipped
    no-catch-all `ctrl` discipline (`src/kernel/ctrl.jl`) makes that a
    `MethodError` at zero cost.
  • `∘`/`⊗` have no MIXED signature (`ProcessValue` × `ChannelValue`). To compose
    a unitary with a channel you must first DENOTE it: `channel(v)` (§1.4). That
    is §4.4's "denotation is a quotient, always available, never invertible",
    made a type-level fact rather than a comment.
  • `ApplyN` takes a `ProcessValue`, so a `ChannelValue` cannot enter a unitary
    node; `NoiseN` is its only carrier, and `NoiseN` is a barrier `certify`
    already refuses (`src/channel/cert.jl:141`).
"""
abstract type ChannelValue end
```

Four concrete kinds:

```julia
"""
    KrausFamily{N,R,L}(data::NTuple{L,ComplexF64})

An `N`-wire channel in operator-sum form with `R` Kraus operators, stored as `R`
row-major `2^N × 2^N` blocks flattened into ONE frozen tuple (`L == R * 4^N`).

FROZEN STORAGE (F28). A `KrausFamily` is embedded in a `NoiseN` inside a deeply
immutable `ChannelDAG`, so it may not wrap a live `Vector`/`Matrix` — the same
reason `Perm`/`MCX` were refactored to `NTuple` (TR5). `L` is a type parameter so
the field is CONCRETE; the practical (N,R) set is tiny (1q rank 1–4, 2q rank ≤ 4),
so the specialisation cost is bounded (guard: `KRAUS_MAX_ENTRIES`, §1.3).

Physics: any family with `Σᵢ Kᵢ†Kᵢ = I` is CP by the operator-sum theorem
(`docs/physics/stinespring_1955_dilation.md`, Kraus/N&C Thm 8.1) and TP by that
identity; CP therefore needs NO check and TP is the ONLY construction obligation.
"""
struct KrausFamily{N,R,L} <: ChannelValue
    data::NTuple{L,ComplexF64}
end

"""
    MixedUnitary{N,R}(weights::NTuple{R,Float64}, unitaries::NTuple{R,ProcessValue})

A random-unitary (mixed-unitary) channel `ρ ↦ Σᵢ pᵢ Uᵢ ρ Uᵢ†` with `Σ pᵢ = 1`,
`pᵢ ≥ 0`, each `Uᵢ` a kernel process value on `N` wires.

WHY A DISTINCT TYPE, not a flag on `KrausFamily`: this is the family whose
Stinespring dilation is EXPRESSIBLE IN SHIPPED KERNEL VALUES (an environment
"which-branch" register plus a multiplexed `ctrl^E` — §2.6), so it is the family
whose dilation M11 can actually EXECUTE. Making that a type distinction means an
unexecutable dilation is a dispatch-level fact with a specific error message, not
a runtime surprise (CLAUDE.md #1). It is also closed under `∘` and `⊗` (§1.3) —
the channel-level analogue of `ctrl(Perm) = Perm`.

`unitaries` has an ABSTRACT element type on purpose: a Pauli mixture's factors are
heterogeneous `Tensor` shapes, and channel application is a cold path (one superop
build or a handful of emissions), so a pointer chase is cheaper than fragmenting
the type. Documented trade-off, not an oversight.
"""
struct MixedUnitary{N,R} <: ChannelValue
    weights::NTuple{R,Float64}
    unitaries::NTuple{R,ProcessValue}
end

"""
    ChannelTensor(a, b)   —  𝓐 ⊗ 𝓑 on disjoint wires (a.wires lead / MSB)
    ChannelSeq(a, b)      —  𝓐 ∘ 𝓑 on the same wires (b applied FIRST, matching `∘`)

Structure-PRESERVING composites, mirroring `Tensor`/`Seq`. They deliberately do NOT
flatten to a single `KrausFamily`: locality is what lets a density context lower a
product of 1-local factors through `R` cheap native `channel_1q` calls instead of a
`4^N`-sized superop Orkan does not have (§0.3). Flatten on demand with `kraus(ch)`.
"""
struct ChannelTensor{A<:ChannelValue,B<:ChannelValue} <: ChannelValue
    a::A
    b::B
end
struct ChannelSeq{A<:ChannelValue,B<:ChannelValue} <: ChannelValue
    a::A
    b::B
end

nwires(k::KrausFamily{N}) where {N} = N
nwires(m::MixedUnitary{N}) where {N} = N
nwires(t::ChannelTensor) = nwires(t.a) + nwires(t.b)
nwires(s::ChannelSeq)    = nwires(s.a)
```

### 1.2 The construction obligation: TP, toleranced, loud

**Physics.** CP is automatic: a map written in operator-sum form is completely
positive for *any* operator list (Kraus's theorem; `docs/physics/stinespring_1955_dilation.md`,
N&C Thm 8.1). The only condition distinguishing a channel from a general CP map is
trace preservation, `Σᵢ Kᵢ†Kᵢ = I`. So there is exactly one check, and it is the
*same* identity that makes the Stinespring isometry an isometry (§2.2) — one
physical fact, one check, two consumers.

**Exact or toleranced?** Toleranced, and here is the derivation of the number. A
legitimate family's entries are formed from square roots of probabilities; the sum
`Σ Kᵢ†Kᵢ` accumulates at most `R·4^N` float operations, so the residual for `R ≤ 16`,
`N ≤ 3` is `≲ 10^{-15}`. A *user error* (unnormalised probabilities, a wrong √) is
`O(10^{-2})`. So:

```julia
"""
    KRAUS_TP_ATOL

Absolute tolerance on `‖Σᵢ Kᵢ†Kᵢ − I‖_∞` at `KrausFamily` construction. Distinct
from `U2_ATOL` (1e-10, the accumulated-group-product scale, `src/kernel/numerics.jl`):
this is a SUM of products of near-exact inputs, whose residual is ≲ 1e-15 for the
shipped size range, while a real user error is O(1e-2). 1e-12 sits three decades
above the noise floor and ten below any physical non-TP-ness.
"""
const KRAUS_TP_ATOL = 1e-12

function KrausFamily(ops::AbstractVector{<:AbstractMatrix})
    isempty(ops) && throw(ArgumentError("KrausFamily: need ≥ 1 Kraus operator."))
    d = size(ops[1], 1)
    ...
    dev = _tp_deviation(ops)                       # ‖Σ K†K − I‖_∞
    dev ≤ KRAUS_TP_ATOL || throw(ArgumentError(
        "KrausFamily: the family is not trace-preserving — ‖Σᵢ Kᵢ†Kᵢ − I‖_∞ = $dev " *
        "exceeds KRAUS_TP_ATOL = $KRAUS_TP_ATOL. Σ Kᵢ†Kᵢ = I is the ONLY channel " *
        "obligation (complete positivity is free in operator-sum form — " *
        "docs/physics/stinespring_1955_dilation.md, Kraus/N&C Thm 8.1). Sturm does " *
        "NOT renormalise a broken family: a silently rescaled channel is a different " *
        "physical process. Check your probabilities, or use `postselect` semantics — " *
        "which M11 does not ship (CP trace-NON-increasing is reachable only through " *
        "the explicit effect surface, PRD-v2 §6 P1)."))
    ...
end
```

Trace-**non**-increasing families (effects/postselection) are **out of scope**:
`postselect` is not shipped (grep: absent from `src/`), and admitting subnormalised
Kraus families before the effect surface exists would let the CP-TNI regime in
silently — precisely what §6 P1 forbids.

### 1.3 Composition and tensor

```julia
Base.:∘(a::ChannelValue, b::ChannelValue) = (_assert_same_width(a, b); ChannelSeq(a, b))
⊗(a::ChannelValue, b::ChannelValue) = ChannelTensor(a, b)

# The mixed-unitary corner is CLOSED (the channel-level analogue of ctrl(Perm)=Perm):
Base.:∘(a::MixedUnitary{N,Ra}, b::MixedUnitary{N,Rb}) where {N,Ra,Rb} =
    MixedUnitary{N,Ra*Rb}(_outer(a.weights, b.weights),
                          ntuple(k -> a.unitaries[_i(k)] ∘ b.unitaries[_j(k)], Ra*Rb))
⊗(a::MixedUnitary{Na,Ra}, b::MixedUnitary{Nb,Rb}) where {Na,Nb,Ra,Rb} =
    MixedUnitary{Na+Nb,Ra*Rb}(_outer(a.weights, b.weights),
                              ntuple(k -> a.unitaries[_i(k)] ⊗ b.unitaries[_j(k)], Ra*Rb))
```

**There is no `∘(::ProcessValue, ::ChannelValue)` and no `⊗(::ProcessValue, ::ChannelValue)`.**
A user who wants `U` then noise writes `channel(U) ∘ 𝓝` — the denotation is
*visible in the source*, which is the whole point of §4.4.

Kraus rank multiplies under `∘` and `⊗`. Rank *compression* (the Choi-rank bound
`r ≤ d²`) requires an eigendecomposition of the Choi matrix and hence
`LinearAlgebra`, which core does not take (§0.7). So M11 **does not compress**, and
guards instead:

```julia
"Maximum flattened Kraus entries (R·4^N) `kraus(ch)` will materialise."
const KRAUS_MAX_ENTRIES = 4096      # e.g. 3-wire rank-16, or 2-wire rank-64
```

with a loud error naming `ChannelTensor` (which never flattens) as the fix. Rank
compression is filed as a follow-on requiring either a `SturmLinearAlgebraExt`
package extension or an Orkan entry.

### 1.4 `channel` — the denotation quotient, made a function

```julia
"""
    channel(v::ProcessValue) -> KrausFamily{nwires(v),1,·}

DENOTATION (PRD-v2 §4.3/§4.4): the rank-1 family `{U}` with `U = denoted_matrix(v)`.
This is `Ad` written as a value-to-value map, and it is where the U(1) phase quotient
is crossed — `ker(Ad) = U(1)`, so `channel(gphase(α))` and `channel(I2)` are DIFFERENT
DATA but the SAME CHANNEL.

It is TOTAL on process values and has NO INVERSE — there is deliberately no
`process(::ChannelValue)` anywhere in Sturm. That absence IS §4.4's "denotation is a
quotient, always available, never invertible", enforced by the method table rather
than by prose.
"""
channel(v::ProcessValue) = KrausFamily([denoted_matrix(v)])

"""
    same_channel(a::ChannelValue, b::ChannelValue; atol = CHOI_ATOL) -> Bool

Semantic channel equality: `Choi(a) ≈ Choi(b)`. Mirrors the shipped `==`
(exact-structural) vs `same_process` (semantic `≈`) split EXACTLY (F26: never put a
tolerance into `Base.==` — it is not transitive and would corrupt any dict keyed on
channel values). Two families related by the unitary freedom of the operator-sum
representation (N&C Thm 8.2 — `Kᵢ = Σⱼ uᵢⱼ Lⱼ`, `u` an isometry) are `same_channel`
but not `==`.
"""
```

Named test `M11.CHANNEL.AD-KERNEL`:
`same_channel(channel(gphase(π/3)), channel(I2))` is `true` while
`channel(gphase(π/3)) != channel(I2)` structurally — a direct restatement of
`ker(Ad) = U(1)`, and the companion of the shipped `π/3` phase sentinel in the
pass-law battery (`src/channel/passes.jl` header).

### 1.5 The named noise constructors (all with pinned conventions)

Ambiguous conventions are where physics bugs hide, so every constructor pins one
and says which:

```julia
bit_flip(p)            # MixedUnitary{1,2}: (1−p)·I + p·X            — X w.p. p
phase_flip(p)          # MixedUnitary{1,2}: (1−p)·I + p·Z
pauli_channel(px,py,pz)# MixedUnitary{1,4}: the UNAMBIGUOUS primitive
depolarizing(p)        # ρ ↦ (1−p)ρ + p·I/2  ⇔  MixedUnitary weights (1−3p/4, p/4, p/4, p/4)
                       #   PINNED: p is the probability the state is REPLACED by I/2.
                       #   The other convention in the wild — (1−p)ρ + (p/3)ΣPρP —
                       #   differs by p ↦ 3p/4 and is NOT offered under this name;
                       #   spell it `pauli_channel(p/3,p/3,p/3)`.
dephasing(λ)           # MixedUnitary{1,2}: (1−λ/2)·I + (λ/2)·Z   (λ = coherence decay)
amplitude_damping(γ)   # KrausFamily{1,2}: K₀ = [1 0; 0 √(1−γ)], K₁ = [0 √γ; 0 0]
                       #   NOT mixed-unitary (non-unital) — the honest witness that
                       #   the two types are physically, not cosmetically, distinct.
reset_channel()        # KrausFamily{1,2}: the shipped `_RESET_KRAUS`, re-homed
pinch_channel()        # KrausFamily{1,2}: the shipped `_PINCH_KRAUS`, re-homed
```

The last two are important for coherence: `src/context/density.jl` already contains
`_RESET_KRAUS` and `_PINCH_KRAUS` as bare `Vector{Matrix{ComplexF64}}` constants.
M11 re-expresses them as `KrausFamily` values and keeps `trace_wire!`/`_instrument!`
calling the same lowering — one representation of "the pinch", not two (CLAUDE.md #13).

### 1.6 Application: same surface, three lowerings, one guardrail

```julia
"""
    apply!(ctx::AbstractContext, ch::ChannelValue, wires::NTuple{K,WireID};
           stinespring::Bool = false) -> ctx

Apply a channel value (PRD-v2 §4.3: "channel-level values apply through the same
surface"). Guardrail 1 (§3.5/§4.4) fires FIRST: noise under a live `when` frame is
unrepresentable, not merely unsupported. `stinespring` is the §2 opt-in.
"""
```

Lowering table (this is the F33 "when does the fallback fire" answer):

| context | value | `stinespring=false` (default) | `stinespring=true` |
|---|---|---|---|
| `DensityMatrixContext` | 1-local factor | **native** `kraus_to_superop` + `channel_1q` — exact | dilate, alloc env, unitary, **exact** ptrace ⇒ identical channel |
| `DensityMatrixContext` | k-local, k ≥ 2 | **loud error** naming `stinespring=true` and §0.3 | dilate; exact on DM |
| `DensityMatrixContext` | `ChannelTensor` | recurse into factors (locality preserved) | recurse |
| `EagerContext` | any | **loud error** naming `density(...)`, `shots`, and `stinespring=true` | legal, but it is **one unravelling**: the env's region-exit trace lowers to measure-and-discard. Wrap in `shots` for the channel |
| `TracingContext` | any | record `NoiseN(ch, ports)` | **loud error** — the IR records the CHANNEL, never its dilation (§2.5) |

**Why no implicit fallback anywhere.** Three reasons, in order of force:

1. A dilation allocates `E = ⌈log₂ R⌉` environment wires out of the context's fixed
   capacity. An implicit dilation turns a channel application into a resource
   decision that can fail *at a distance* as "context capacity exceeded" — the
   failure would name the wrong operation.
2. Under Eager, `dilate + trace` is a **trajectory**, not the channel. Silently
   giving a user one unravelling where they wrote a channel is exactly the S10 bug
   class M12 already guards against (`_assert_randomized_legal`,
   `src/library/evolve/evolve.jl:130`). One flag in the source removes the whole class.
3. A per-context *policy* (`density(cap; stinespring=true)`) was considered and
   **rejected**: it makes the same source line mean different things in different
   contexts, which is the silent-wrongness pattern this project exists to kill.

### 1.7 Slotting into §4.4 and the shipped `ChannelDAG` barrier

- `NoiseN` becomes `NoiseN(ch::ChannelValue, ports::NTuple{K,PortID})`; `is_barrier(::NoiseN) = true`
  is unchanged, so `certify` (`src/channel/cert.jl:141`) still refuses any DAG holding
  noise — a noise-bearing DAG **can never become a `UnitaryBlock`**, hence can never
  reach `ctrl(::UnitaryBlock)`, hence can never reach `ctrl` at all.
- `apply_pass(::UnitaryPass, ::UnitaryBlock)` is domain-restricted, so no unitary pass
  can touch noise. `FuseUnitaryRunsPass` already partitions at barriers and must not
  move a node across a `NoiseN` — M11 extends the shipped test to a *real*
  `ChannelValue`-bearing `NoiseN` (the current test uses the `KrausFamily(n)` stub).
- `ctrl(::ChannelValue)` → `MethodError` **by construction**: `src/kernel/ctrl.jl` has
  no catch-all (deliberately: "an unhandled kind is a `MethodError`, not a silent
  wrong wrap"). M11 adds **zero** lines to the choke point.

---

## §2 — The Stinespring dilation contract (design question 2, F33)

### 2.1 Statement of the contract

Given `𝓝` with Kraus family `{Kᵢ}_{i=0..R−1}` on `H_S`, `d = dim H_S = 2^N`:

> **Contract.** `dilate(𝓝)` returns a `Dilation` carrying an integer `E`, a unitary
> `U ∈ U(2^{N+E})` on `H_E ⊗ H_S` (environment wires **leading/MSB**), and the
> guarantee
> ```
> (⟨i|_E ⊗ I_S) · U · (|0⟩_E ⊗ I_S) = K_i     for all 0 ≤ i < 2^E,
> ```
> with `K_i := 0` for `i ≥ R` (zero padding). Consequently
> `Tr_E[ U (|0⟩⟨0|_E ⊗ ρ) U† ] = Σᵢ Kᵢ ρ Kᵢ† = 𝓝(ρ)` for every ρ.
> `U` is an **execution artifact**: it is not a value of the language, cannot be
> named by user code, cannot be composed, and cannot be controlled.

**Physics.** Stinespring's theorem (Stinespring, *Positive functions on C\*-algebras*,
Proc. AMS **6** (1955) 211–216, Thm 1) in its finite-dimensional Kraus form: every
CPTP map dilates to an isometry into a larger space followed by a partial trace
(prerequisite distillation `docs/physics/stinespring_1955_dilation.md`; N&C §8.2.3
Thm 8.1 for the operator-sum form, §8.2.4 Thm 8.2 for the unitary freedom that makes
zero-padding legitimate).

### 2.2 Step 1 — the isometry, and why the TP check *is* the isometry check

Define the `2^E·d × d` matrix

```
Ṽ[i·d + s + 1, t + 1] = K_i[s+1, t+1]        (env index i is the MSB block)
```

Then `Ṽ†Ṽ = Σᵢ Kᵢ†Kᵢ = I_d` — *the trace-preservation condition and the isometry
condition are literally the same equation*. This is why §1.2's construction check is
not duplicated here: a `KrausFamily` that exists is already an isometry, to
`KRAUS_TP_ATOL`.

**Padding.** `E = ⌈log₂ R⌉`, padded rank `m = 2^E ≥ R`; `K_i = 0` for `R ≤ i < m`.
Padding with zeros preserves `Σ K†K` exactly (it adds nothing) and is the canonical
embedding sanctioned by the unitary freedom of the operator-sum representation
(N&C Thm 8.2). We pad to a power of two because the environment must be a **qubit
register** — Sturm has no qudit context.

**Endianness pin (one function, one test).** Environment wires **lead** (MSB), so the
env=|0…0⟩ input columns are exactly columns `1:d` and no column permutation is ever
needed. This is not an arbitrary choice: it matches `apply!`'s "position 1 = the
value's MSB wire" and `Ctrl`'s "leading wires are controls", so the dilation is
applied on `(env…, data…)` with the same convention as everything else in the kernel.
A wrong ordering here is a silent wrong channel, so it gets a **test that can see it**:
the pin is checked on `amplitude_damping(γ)`, which is non-unital and asymmetric under
environment relabelling (a Pauli channel is too symmetric to detect the bug).

### 2.3 Step 2 — unitary completion: Householder QR with a diagonal phase fix

**Proposition.** Let `Ṽ ∈ ℂ^{M×d}` with `Ṽ†Ṽ = I_d`, and let `Ṽ = Q [R̃; 0]` be its
Householder QR (`Q ∈ U(M)`, `R̃ ∈ ℂ^{d×d}` upper triangular). Then `R̃` is a
**diagonal** matrix with `|R̃ⱼⱼ| = 1`, and
`U := Q · diag(R̃₁₁, …, R̃_dd, 1, …, 1)` is unitary with `U[:, 1:d] = Ṽ` exactly.

*Proof.* `Ṽ†Ṽ = R̃†Q†Q R̃ = R̃†R̃ = I`, so `R̃` is unitary; a unitary upper-triangular
matrix is diagonal (its first column has unit norm and its only nonzero entry is
`R̃₁₁`, hence `|R̃₁₁| = 1` and the rest of row 1 must vanish by orthogonality;
induct). Then `U[:,1:d] = Q[:,1:d]·R̃ = Ṽ`, and `U` is a product of unitaries. ∎

**Why this and not Gram–Schmidt on `I − ṼṼ†`.** The projector route needs a
*rank-detection tolerance* (accept a candidate completion vector iff its residual
norm exceeds τ), and τ is exactly the kind of tuned constant that silently changes a
result. Householder has **no tolerance inside the algorithm**: it is a fixed sequence
of `d` reflections, deterministic and bitwise reproducible for a given input, and
backward stable with `‖Q†Q − I‖ = O(Mε)` (Golub & Van Loan, *Matrix Computations* 4e
§5.1–5.2 — a textbook numerical fact, not a physics citation, so no distillation is
owed). Tolerances appear **only** as post-condition asserts.

**No `LinearAlgebra`** (§0.7): the reflections, the explicit `Q`, and the column
scaling are ~60 lines of plain loops in the `src/kernel/numerics.jl` / `replay.jl`
style. `M ≤ 2^8 = 256` under the cap below, so forming `Q` explicitly is trivial work
off any hot path.

```julia
"""
    STINESPRING_ATOL

Post-condition tolerance for the dilation (`‖U†U − I‖_∞` and `‖U[:,1:d] − Ṽ‖_∞`).
Set to `U2_ATOL` (1e-10, the §4.1 float-law scale): Householder is backward stable
with residual `O(Mε) ≈ 1e-14` at `M ≤ 256`, so 1e-10 sits four decades above the
numerics and far below any physical difference. A violation is an ErrorException
(an INTERNAL invariant break — the algorithm is wrong, not the user).
"""
const STINESPRING_ATOL = U2_ATOL

"Wire ceiling on a dilation (N + E). 8 ⇒ a 256×256 dense U (~1 MB) — ample for M11."
const DILATION_MAXWIRES = 8
```

### 2.4 Step 3 — environment allocation and ownership

The environment is region-owned and traced at region exit — **the §3.9 Stinespring
boundary made literal, using no new mechanism**:

```julia
function _apply_dilated!(ctx::AbstractContext, ch::ChannelValue, wires::NTuple{K,WireID})
    E = _env_width(ch)
    _require_env_capacity(ctx, E, ch)          # loud, names the dilation and the rank
    _enter_region!(ctx)                        # the env's life is EXACTLY this region
    try
        env = ntuple(_ -> allocate!(ctx), E)   # |0…0⟩ = |e_G⟩ (§3.9 allocation-is-initialisation)
        _emit_dilation!(ctx, ch, env, wires)   # the ONLY consumer of the artifact
    finally
        _exit_region!(ctx, nothing)            # returns nothing ⇒ every env wire is traced
    end
    return ctx
end
```

- The env wires are **never returned**, so `_escaped_wires(nothing) == []` and
  `_exit_region!` traces all of them (`src/context/regions.jl:79`). No new ownership
  rule, no new escape analysis.
- The trace lowering is per-context and already correct: exact reset channel on DM
  (`trace_wire!(::DensityMatrixContext)`), measure-and-discard on Eager. The
  Eager path is a *valid unravelling* — which is why §1.6 documents Eager+dilation as
  a trajectory rather than pretending it is the channel.
- Slots are recycled by `_return_slot!`, so `E` wires are transiently, not
  permanently, consumed.
- `_require_env_capacity` pre-checks rather than letting `_take_slot!` fail with the
  generic "context capacity exceeded", which would name the wrong operation.

### 2.5 The artifact rule — mechanism, and why *this* mechanism

> **Rule.** The dilation unitary is **never a `ProcessValue`**. It exists only inside
> `struct Dilation` (which subtypes **nothing**) as a raw `Matrix{ComplexF64}`, and it
> reaches the backend through a private emitter that takes a matrix or a node
> sequence — never through `Ad`/`apply!`/`ApplyN`.

```julia
"""
    Dilation(nsys, nenv, u::Matrix{ComplexF64})

An EXECUTION ARTIFACT. Deliberately subtypes NOTHING:
  • not a `ProcessValue` — it must be unreachable from `ctrl` (P4);
  • not a `ChannelValue` — it denotes a unitary, not a channel, so it must not
    enter a `NoiseN`, a `ChannelTensor`, or `same_channel`;
  • not a `Node` — it must never be materialised into the IR (§1.6 Tracing row).

Its single consumer is `_emit_dilation!`. A boot lint (mirroring the `_ctrl`
choke-point lint) asserts the tokens `Dilation(` and `_emit_dilation!` appear in
`src/` only in `src/channel/stinespring.jl` and the one context lowering site.
"""
struct Dilation
    nsys::Int
    nenv::Int
    u::Matrix{ComplexF64}      # env wires LEADING; u[:, 1:2^nsys] == Ṽ
end
```

**Why not "a `ProcessValue` wrapped in a type `ctrl` refuses"?** Three arguments, the
third decisive:

1. *Refusal is a runtime guarantee; absence is a type-level one.* `ctrl`'s shipped
   discipline is explicitly "totality by exhaustive concrete methods … an unhandled
   kind is a `MethodError`, not a silent wrong wrap" (`src/kernel/ctrl.jl:19`). A
   throwing method is strictly weaker: it is a *method*, and methods can be
   shadowed, forwarded, or reached through a generic path.
2. *It would have to be refused at many sites, not one.* If the dilation were
   `<: ProcessValue`, then `Tensor{A<:ProcessValue,B<:ProcessValue}`, `Seq`,
   `ApplyN(v::ProcessValue, …)`, `_footprint(::ProcessValue, …)` (the fail-closed
   catch-all!), `within`, and `_emit!` would each accept it. To keep it out of
   `ctrl` we would have to teach **every one of them** to refuse — which is exactly
   the "the bug lives at whichever of many call sites builds the controlled circuit"
   failure mode the `ctrl` choke point exists to eliminate (PRD §4.2; Cirq #1161/#4275,
   Qiskit #4949/#7167, pytket QControlBox). Keeping it outside the `ProcessValue`
   tree makes the refusal structural and **total, at zero sites**.
3. *The shipped certificate machinery already forbids it, and for the right reason.*
   A dilation is precisely an `AllocN`/`TraceN` pair **whose ancilla is dirty by
   construction** — carrying away the entropy is the entire point. There is therefore
   no `CleanCert` for it, and `certify` rejects a `TraceN` with `cert === nothing`
   (`src/channel/cert.jl:174`, the F1 adversary path). **So the §4.1a machinery
   already makes a dilation unpromotable; the artifact rule is not a new prohibition,
   it is the statement that we will not route around the one we have.**

**Physics of why control would be wrong.** Two distinct failures:

- *Composition/reuse makes the arbitrary columns physical.* The completion is unique
  only on the `env = |0⟩` block; the remaining `M − d` columns are an arbitrary
  orthonormal completion. They are unreachable from a fresh `|0⟩_E` — which is exactly
  why the dilation is a legitimate execution artifact — but become reachable the
  moment the unitary is composed with anything that can put the environment off
  `|0⟩` (env reuse, a second dilation on the same register, or embedding into a
  `UnitaryBlock` body whose ancilla is shared). F33's "that completion must remain
  internal" is precisely this.
- *`ctrl(U)` is not "controlled noise", and there is no such thing.* Controlled noise
  is unrepresentable (P4, §1.1 theorem). A user handed `ctrl(U)` would get a perfectly
  well-defined operator that is **not** conditional application of `𝓝`: with the
  control in superposition, the environment becomes entangled with the *control*, and
  the environment is then traced **unconditionally** — so the control register itself
  decoheres. That is the measurement-flavoured structure F33 warns is being smuggled
  past P4. Tang–Wright Thm 1.1
  (`docs/physics/tang_wright_2025_controlled_unitaries.md`) is the formal reason a
  representation that is fine under `Ad` can be catastrophic under `ctrl`: control
  promotes representation-level freedom to observable physics.

Guardrail 1 already bans `apply_noise!` inside `when` (§0.1 fixes the missing call);
the artifact rule makes the *representation* unavailable so there is nothing left to
ban.

### 2.6 Execution: the mixed-unitary tier ships; the general tier is constructed and verified

Because Orkan exposes no dense-unitary entry (§0.3), M11 splits execution honestly.

**Tier D1 — `MixedUnitary`: executable, all shipped machinery.**
`𝓝 = Σᵢ pᵢ Ad_{Uᵢ}` dilates to

```
U = [ Σᵢ |i⟩⟨i|_E ⊗ Uᵢ ] · [ P_E ⊗ I_S ],      P_E|0…0⟩ = Σᵢ √pᵢ |i⟩
```

emitted as: (a) an amplitude preparation on the `E` env wires, (b) a multiplexed
`ctrl^E(Uᵢ)` per branch with the standard X-sandwich anti-control for the zero bits
of `i` — the *same* anti-control trick the shipped `cases` executor already uses
(`_apply_arm_config!`, `src/surface/cases.jl:283`).

The amplitudes are real and non-negative (`√pᵢ`), so (a) is the elementary binary
rotation tree: at depth `j`, condition on the `j−1` already-prepared bits and apply
`Ry(2·arccos √(w_left / w_node))` where `w_node` is the summed weight of that
subtree. Correctness is a two-line induction on the tree (each node splits its
subtree mass exactly), so no paper is cited and no distillation is owed; the
Grover–Rudolph tree is prior art for the *complex-amplitude* generalisation, and its
distillation is deferred until a general `PREPARE` needs one.

Every emission goes through `apply!` (**not** `_act!`): a dilation must never be
control-wrapped, and combining that with guardrail 1 closes the path twice.
The per-branch `Uᵢ` are ordinary process values and remain legitimately `ctrl`-able —
it is the *composite* dilation that is never formed as a value.

Coverage: every Pauli channel, bit/phase flip, depolarizing, dephasing, and any
enumerated unitary mixture with `E ≤ 4` (`R ≤ 16`, guarded loudly).

**Tier D2 — general `KrausFamily`: constructed, verified, not executed.**
`dilate(ch)` builds and verifies `U` for any family within `DILATION_MAXWIRES`, and
the F33 contract is fully specified and *tested* (§6). `apply_noise!(…; stinespring=true)`
on a non-mixed-unitary family raises:

```
apply_noise!(stinespring=true): a general Kraus family's dilation is a dense
2^k × 2^k unitary, and there is no way to APPLY one today — Orkan exposes only
named 1q gates, rx/ry/rz/p, cx/cy/cz, swap and ccx (../orkan/include/gate.h), and
no k-local channel entry beyond channel_1q (channel.h). The dilation VALUE is
constructed and verified (`dilate(ch)`); executing it needs ONE of:
  (a) an Orkan `unitary_kq(state_t*, const cplx_t* u, const qubit_t* targets, uint8_t k)`
      entry — the natural home, since Orkan owns the linear algebra; or
  (b) a KAK/QSD synthesis pass producing kernel process values (a separate design
      round: it would be a new constructor of controlled lowerings and must go
      through the `ctrl` choke point).
For a 1-qubit channel on a density context, drop `stinespring=true` — the native
`channel_1q` path is exact. For a mixed-unitary channel, use `MixedUnitary`.
```

This costs little in practice: the only gaps are *general* 1q channels on a **pure**
context (answer: use `density`, or `shots`) and *correlated* multi-qubit noise
(answer: not M11).

### 2.7 What pins the contract (tests, in §6 detail)

- `M11.DILATE.KRAUS-RECONSTRUCT` — `U[i·d+1 : i·d+d, 1:d] ≈ Kᵢ` for every `i`, and
  `≈ 0` for padded `i`. This single assertion *is* the contract: it says the
  env-block extraction of `U` reproduces the family, from which
  `Tr_E[U(|0⟩⟨0|⊗ρ)U†] = 𝓝(ρ)` follows algebraically with no simulation.
- `M11.DILATE.UNITARY` / `.EXACT-COLUMNS` — the two post-conditions at `STINESPRING_ATOL`.
- `M11.DILATE.CHOI-EQUALS-KRAUS` — the end-to-end DM law: for a `MixedUnitary`,
  `choi(q -> apply_noise!(q, ch; stinespring=true))` ≈
  `choi(q -> apply_noise!(q, ch))` ≈ the analytic Choi. **Three-way** agreement
  (structured emission ≡ dense artifact ≡ Kraus).
- `M11.DILATE.CTRL-UNREACHABLE` — `@test_throws MethodError ctrl(dilate(ch))`, plus
  `@test !(Dilation <: Sturm.ProcessValue)`, `@test !(Dilation <: Sturm.ChannelValue)`,
  plus the **source lint** (a pure string function in `test/runtests.jl`, exactly the
  shape of the shipped `_ctrl` lint) asserting the artifact tokens appear in only the
  allowed files.
- `M11.DILATE.NOT-IN-IR` — `@test_throws ErrorException` for
  `apply_noise!(tracing_ctx, ch; stinespring=true)`.

---

## §3 — QECC typing (design question 3, F8)

This is the load-bearing section. F8's charge is that one `Channel → Channel`
signature conflates three physically different operations. The fix is not three
names on the same untyped thing; it is three operations **at three different levels
of the language**.

| Operation | Level | Type |
|---|---|---|
| `encode_state` | **register handles** (runtime) | `QBool` → `Encoded{C}`; a channel `L → P`, an isometry |
| `effective_logical_noise` | **compiler / IR** | `ChannelDAG` → `ChannelDAG`; a superchannel (comb) |
| `fault_tolerant_lift` | **not canonical** | interface only; a loud refusal in M11 |

That they land at different levels **is** the answer to F8: the conflation was only
possible because all three were spelled as one runtime function on one untyped
"Channel".

### 3.1 The `Code` value: stabilizer generators **plus** an explicitly chosen encoder

```julia
"""
    AbstractCode

Supertype of quantum error-correcting code values. A code value declares a CODE
SPACE and its logical operators; it does NOT declare an encoder — see below.
"""
abstract type AbstractCode end

"""
    StabilizerCode{N,K}

An `[[N, K, d]]` stabilizer code: an abelian subgroup `S ≤ P_N` with `−I ∉ S`,
generated by `N − K` independent Pauli generators, together with a chosen set of
logical representatives.

Reuses the M12 symplectic `PauliWord{N}` (`src/library/evolve/pauli.jl`) rather than
inventing a Pauli type (CLAUDE.md #13) — `commutes` is already the symplectic form.
`PauliWord` carries no sign, so signs ride a parallel tuple.

VALIDATED AT CONSTRUCTION (all loud — a mis-specified code is a physics bug that
would silently produce a wrong "logical" channel):
  1. generators pairwise commute (abelian — `commutes`);
  2. generators independent over GF(2) (rank of the N−K × 2N symplectic matrix);
  3. `length(stabilizers) == N − K`;
  4. each `logical_x[j]`/`logical_z[j]` commutes with every generator (normaliser);
  5. `logical_x[j]` anticommutes with `logical_z[j]` and commutes with `logical_z[k]`,
     `k ≠ j` (the symplectic pairing of the logical qubits);
  6. no logical is IN the stabilizer group (it would be trivial, not logical).
Grounding: `docs/physics/gottesman_1997_stabilizer_codes.md` (thesis Ch. 3).

`distance` is DECLARED, not derived: computing it is a minimum-weight search over
`N(S) \\ S`, `O(4^N)`. A test verifies it exhaustively for `N ≤ 8`; above that it is
the author's claim and the docstring says so.
"""
struct StabilizerCode{N,K} <: AbstractCode
    stabilizers::NTuple{S,PauliWord{N}} where {S}
    signs::NTuple{S,Int8} where {S}          # +1 / −1 per generator (M11 builds only +1)
    logical_x::NTuple{K,PauliWord{N}}
    logical_z::NTuple{K,PauliWord{N}}
    distance::Int
end
```

**Where is the encoder?** *Not in the code value*, on purpose. A stabilizer code
determines its code space; it determines an encoder only **up to a logical unitary
and a stabilizer element** — the encoding circuit is a gauge choice (Cleve–Gottesman,
quant-ph/9607030, gives *an* algorithm, not *the* encoder). Baking one into the code
value would re-import exactly the F8 conflation at the value level: it would let
"the code" silently mean "the code plus one arbitrary encoding circuit". So:

```julia
"""
    EncoderSpec{C<:AbstractCode,N,K}

A CHOSEN encoding program for a code: a Julia function written in the seven surface
constructs mapping `K` logical register handles to `N` physical ones, plus its
chosen inverse (the decoder). Storing the program (not a matrix) keeps the encoder
in the DSL, testable at the Choi level, and traceable to a `ChannelDAG` via the
shipped `trace(f, nin)`.

The pair `(encode, decode)` carries a PROOF OBLIGATION discharged by a required test,
never by construction: `Choi(decode ∘ encode) ≈ Choi(id_L)` (§6, M11.QECC.ENCODE-DECODE-ID).
"""
struct EncoderSpec{C<:AbstractCode,N,K}
    code::C
    encode::Function        # (logical…) -> physical NTuple  (surface vocabulary)
    decode::Function        # (physical…) -> logical         (surface vocabulary)
end
```

`Function` fields are a callback, not a P9 catch-all dispatch; the shipped precedent
is `ClassicalBit.f::Function` (`src/surface/tokens.jl:84`).

**Milestone split.**
M11 ships `StabilizerCode`, its validation, `bitflip_code()` (§5.3) and its hand-written
`EncoderSpec`. Deferred to the QECC epic: Cleve–Gottesman encoder *synthesis* from
generators, CSS structure, distance certification beyond exhaustive search, Steane
[[7,1,3]] (an explicit reimport gate, plan §M11).

### 3.2 `encode_state` — a register-handle operation

```julia
"""
    Encoded{C<:AbstractCode,N,K,Ctx<:AbstractContext} <: AbstractQRegister{Ctx}

A handle to `N` physical wires that DENOTE `K` logical qubits under code `C`.

THE LOGICAL/PHYSICAL LABEL LIVES HERE — not on a `PortKind`. A logical qubit is not
carried by any wire: it is a subspace of the JOINT Hilbert space of a bundle, defined
relative to a code. A `LogicalPort` PortKind would therefore be a physics lie (and
would break P7's dimension-agnostic parametricity for no benefit). The IR keeps
`QuantumPort(width)`; the claim "these N wires are a code block" is a property of the
surrounding program, which is exactly what a register handle records.

DELIBERATELY ABSENT (each a `MethodError`, never a silent reinterpretation):
`Bool`/`Int` casts, `⊻=`, `not!`, `dual`, arithmetic, `when` as a control. Every one
of those is a FAULT-TOLERANCE question (is the gadget transversal? what fault model?),
i.e. `fault_tolerant_lift` territory (§3.5) — and F8 exists precisely because those
were conflated. The only things you can do with an `Encoded` are `decode_state`,
`syndrome_extract!` and `correct!`.
"""
struct Encoded{C<:AbstractCode,N,K,Ctx<:AbstractContext} <: AbstractQRegister{Ctx}
    ctx::Ctx
    spec::EncoderSpec{C,N,K}
    wires::NTuple{N,WireID}
end

_escaped_wires(e::Encoded) = collect(e.wires)     # a returned block escapes its region

"""
    encode_state(spec::EncoderSpec{C,N,1}, ψ::QBool) -> Encoded{C,N,1}

The encoding channel `E : L → P` applied to a live register (a cq-flavoured
operation only in shape: it consumes the logical handle and produces the physical
block; it prepares no classical literal). `ψ` is CONSUMED in the §4.5 sense — its
handle is absorbed into the block; there is no way to hold both.

`E` is an ISOMETRY, not a unitary: `K` in-ports, `N` out-ports. That is why it is a
`ChannelDAG`-level object (whose `qin`/`qout` "need NOT match", `src/channel/dag.jl:93`)
and NOT a `UnitaryBlock` — a `UnitaryBlock` is square by construction (design TR1).
"""
```

`decode_state(enc) -> QBool` is the mirror. Note the honest asymmetry: `decode` is
*not* `adjoint(encode)` as a Sturm value — `ChannelDAG` has no adjoint (only
`UnitaryBlock` does), and the physical decode is "run the encoder's program in
reverse and trace the `N − K` residual wires", which is a channel, not an adjoint.
The `EncoderSpec` therefore carries both programs and pays for it with a required
Choi test.

### 3.3 `effective_logical_noise` — a superchannel as a compiler transformation

**The question:** how do you type `Θ : Chan(P,P) → Chan(L,L)` when §4.4 says channels
are denotations, not values?

**The answer:** you do not put it at the runtime-value level at all. `Θ` is a **map on
channel *representations*** — a transformation on `ChannelDAG` — and Sturm already has
exactly the right object.

```julia
"""
    Superchannel

A map on CHANNEL REPRESENTATIONS: `ChannelDAG → ChannelDAG`, with declared physical
(input) and logical (output) port arities. Concrete superchannels are CALLABLE, so
the code reads like the mathematics: `Θ(𝓝)`.

WHY THIS IS NOT A VIOLATION OF "channels are denotations, not values" (§4.4).

  1. §4.4 forbids REIFYING a channel as a first-class runtime value that can be
     passed around and (the real danger) CONTROLLED. It does not forbid a syntactic
     REPRESENTATION — `ChannelDAG` is exactly that, is already shipped, is already
     `public`, and is explicitly listed on §4.4's channel row. A superchannel is a
     map on representations, so it introduces NO new value level.
  2. It inherits the whole stratification for free: a `ChannelDAG` is not a
     `ProcessValue`, so nothing constructed here can ever reach `ctrl`; and a
     barrier-bearing DAG never certifies, so `Θ`'s output — which contains
     `MeasureN`/`CasesN` from the syndrome path — is structurally unpromotable.
  3. It is CHECKABLE. Its correctness law is a Choi identity between the output
     DAG's denotation and the composite of the four component denotations, and the
     shipped `_replay_dm!` + `choi` harness already execute channel DAGs on DM.
  4. It is the STANDARD FORMALISATION, not an engineering convenience. A
     superchannel is a quantum comb, and a comb IS a circuit with a hole
     (Chiribella–D'Ariano–Perinotti, PRL 101 060401 (2008) / PRA 80 022339 (2009);
     prerequisite distillation `docs/physics/chiribella_2009_quantum_combs.md`).
     "Plug the hole" is literally DAG substitution. Modelling a comb as a runtime
     value applied to a runtime channel value would be the LESS faithful rendering.

A `Superchannel` is NOT a `ChannelPass`. `apply_pass(::ChannelPass, ::ChannelDAG)`
carries the obligation "preserve the typed CPTP denotation (Choi/diamond)"
(`src/channel/passes.jl:82`). A superchannel deliberately CHANGES the denotation —
that is its job. Reusing the pass framework would be a category error and would put a
denotation-changing rewrite under a denotation-preserving boot lint.
"""
abstract type Superchannel end

(Θ::Superchannel)(𝓝::ChannelDAG) = _insert(Θ, 𝓝)      # `Θ(𝓝)` reads as the maths
(Θ::Superchannel)(ch::ChannelValue) = Θ(channel_dag(ch, nports_in(Θ)))

"""
    QECCProtect{C} <: Superchannel

The protecting superchannel of F8:  `Θ(𝓝) = D ∘ R ∘ 𝓝 ∘ E : Chan(P,P) → Chan(L,L)`.

Physics: correctability of the noise by `(code, recovery)` is the Knill–Laflamme
condition `P Kᵢ† Kⱼ P = c_ij P` (Knill & Laflamme, PRA 55, 900 (1997); prerequisite
distillation `docs/physics/knill_laflamme_1997_qec_conditions.md`). `Θ` does NOT
require correctability — its whole point is to compute the EFFECTIVE logical channel
whether or not correction succeeds. Correctability is exactly the statement
`Θ(𝓝) = id_L`, which is a TESTABLE consequence, not a precondition.
"""
struct QECCProtect{C<:AbstractCode,N,K} <: Superchannel
    spec::EncoderSpec{C,N,K}
    recovery::RecoveryProgram{C,N,K}
end

nports_in(::QECCProtect{C,N,K}) where {C,N,K}  = N     # physical
nports_out(::QECCProtect{C,N,K}) where {C,N,K} = K     # logical

"""
    effective_logical_noise(𝓝::ChannelDAG, spec::EncoderSpec, recovery) -> ChannelDAG
    effective_logical_noise(𝓝::ChannelValue, spec, recovery)            -> ChannelDAG

The named front door for `QECCProtect(spec, recovery)(𝓝)`.

PRECONDITIONS (loud, all of them — a mis-shaped 𝓝 would silently produce a
meaningless "logical" channel):
  • `length(𝓝.qin) == length(𝓝.qout) == N` and boundary LINEAGE in == out, in order
    — 𝓝 must be an ENDOMORPHISM on the physical block (the same check `certify`
    performs, factored out as `_assert_endomorphic`, `src/channel/cert.jl:149`);
  • `isempty(𝓝.cout)` — a physical noise model with a classical output is an
    INSTRUMENT, not a channel of type `Chan(P,P)`; admitting one would smuggle a
    second measurement record into the syndrome path;
  • no `AllocN`/`TraceN` imbalance that changes the boundary arity.
"""
function effective_logical_noise(𝓝::ChannelDAG,
                                 spec::EncoderSpec{C,N,K},
                                 recovery::RecoveryProgram{C,N,K}) :: ChannelDAG where {C,N,K}
    _assert_endomorphic(𝓝, N, "effective_logical_noise: the physical noise channel")
    isempty(𝓝.cout) || throw(ArgumentError(...))
    E = trace(spec.encode, K)          # K qin → N qout  (isometry)
    R = trace(_recover_program(recovery), N)   # N → N, contains MeasureN + CasesN
    D = trace(spec.decode, N)          # N qin → K qout
    return D ∘ R ∘ 𝓝 ∘ E               # channel-level ∘ (§3.4)
end
```

The whole implementation is four `trace` calls and three `∘`s. That is the payoff of
putting `Θ` at the IR level: **the superchannel is not an interpreter, it is a
concatenation**, and its correctness reduces to the correctness of `∘` on DAGs plus
the correctness of the four components — each of which has its own test.

**What `Θ` deliberately is not.** It is not `Θ : (Channel value) → (Channel value)`.
That would require the channel-reification API of F18 (a first-class `Channel{P,P}`
object with combs, memory, and a strategy typing). That is a genuinely bigger design
and it would put a channel-shaped object into runtime circulation, one refactor away
from someone asking for `ctrl` of it. **Rejected for M11**, filed as a research step.

### 3.4 Channel-level `∘` and `⊗` on `ChannelDAG` (§4.4's unkept promise)

```julia
"""
    ∘(a::ChannelDAG, b::ChannelDAG) -> ChannelDAG

Channel-level composition (PRD-v2 §4.4 row 2: channels support "composition,
tensor"). `b` runs FIRST (matching the kernel `∘` convention, §4.2). Requires
`length(b.qout) == length(a.qin)` and matching port widths; wires them positionally.

Both operands' `PortID`s AND lineages are renumbered into a fresh namespace before
concatenation — two independently traced DAGs both start at `PortID(1)`, so naive
concatenation would silently FUSE unrelated wires. This is a wire-identity bug of
exactly the wm28 class (it would pass a marginal test and fail a Choi test), so the
remap is one function with a named test (`M11.DAG.COMPOSE-RELABEL`).

`cout` of the result is the ordered union: classical records from BOTH operands
survive (a syndrome record must not vanish because the DAG was composed).
"""
Base.:∘(a::ChannelDAG, b::ChannelDAG) :: ChannelDAG

"""
    ⊗(a::ChannelDAG, b::ChannelDAG) -> ChannelDAG

Parallel composition on disjoint wires (`a` leads / MSB). Same relabelling
discipline.
"""
⊗(a::ChannelDAG, b::ChannelDAG) :: ChannelDAG
```

Also `channel_dag(ch::ChannelValue, n) -> ChannelDAG` — the one-`NoiseN` DAG, which is
how a `ChannelValue` enters the IR world (and how `Θ(bit_flip(p)⊗bit_flip(p)⊗bit_flip(p))`
works).

### 3.5 `fault_tolerant_lift` — named, scoped, refused

**M11 ships no implementation, and says so in the error message.** This is the
honest-scope item.

```julia
"""
    fault_tolerant_lift(logical, code, gadgets::GadgetSet, model::FaultModel)

NOT CANONICAL, and NOT IMPLEMENTED IN M11 (F8; plan §M11).

Lifting a logical channel `Φ : L → L` to a physical implementation `Φ̄ : P → P` that
is fault-tolerant is NOT determined by the code. The code fixes the code space; it
fixes NONE of:
  • the GADGET SET — which logical operations are transversal for this code, and by
    what construction the rest are built (magic-state injection + distillation,
    code deformation, lattice surgery, pieceable FT);
  • the FAULT MODEL — stochastic Pauli vs adversarial vs biased; the location set;
    whether measurement and idling are faulty; correlated vs i.i.d.;
  • the SCHEDULING — syndrome-extraction rounds, flag qubits, measurement repetition
    (which is what makes the extraction itself fault-tolerant);
  • the ACCOUNTING — level reduction / extended rectangles and the threshold claim
    (Aliferis–Gottesman–Preskill, quant-ph/0504218) that makes "fault-tolerant" mean
    anything quantitative.
A function that returned SOMETHING for `(logical, code)` alone would be asserting all
four by default — the F8 conflation with a new name. So M11 ships the INTERFACE
(`GadgetSet`, `FaultModel`, this signature) and refuses.

The moment a concrete gadget set exists, it gets its OWN method on its own concrete
types — mirroring the `ctrl` discipline (totality by exhaustive concrete methods, no
catch-all that silently does the wrong thing).
"""
abstract type GadgetSet end
abstract type FaultModel end

fault_tolerant_lift(::Any, ::AbstractCode, ::GadgetSet, ::FaultModel) = throw(ArgumentError(
    "fault_tolerant_lift is not implemented in M11 and is not canonical: a code does " *
    "not determine a fault-tolerant implementation. What a concrete method needs, and " *
    "what M11 does not have: (1) a transversal/gadget set verified against the code's " *
    "stabilizer group; (2) a declared fault model (location set, stochastic vs " *
    "adversarial, faulty measurement/idling); (3) an extraction schedule (rounds, flag " *
    "qubits, repetition); (4) a threshold/level-reduction accounting " *
    "(Aliferis–Gottesman–Preskill, quant-ph/0504218). Use `effective_logical_noise` for " *
    "the noise-protection question, which IS canonical given a code and a recovery."))
```

Note what is *deliberately not* offered even though it would be easy: a
`logical_not!(::Encoded)` for the repetition code (where `X̄ = X₁X₂X₃` is transversal
and trivially correct). Offering it for one code invites the general case, which is
the non-canonical thing. It is the natural first item of the FT epic, as a
`TransversalGadget` declaration on the code value **checked against the stabilizer
group**, not as a special case.

---

## §4 — `classicalise` (design question 4)

```julia
"""
    classicalise(t::ClassicalToken) -> Dict{V,Float64}

Extract the CLASSICAL DISTRIBUTION of a measurement-record token from a density
context: the Born weights of the token's value, marginalised over everything else.
`V` is `Bool` for a `ClassicalBit`, `Int` for a `ClassicalWord{W}`.

WHAT IT IS. A token is a lazy derivation `f` over its BASE RECORD c-wires
(`src/surface/tokens.jl`), which under DM are the PINCHED wires holding
`Σ_γ p_γ |γ⟩⟨γ|_C ⊗ ρ̃_γ`. `classicalise` reads the diagonal populations `{p_γ}` of
those wires and pushes them through `f`, accumulating equal values.

WHAT IT IS NOT — and this is the load-bearing part. §3.6 keeps THREE q→c meanings
distinct: SAMPLE (Eager dice), RECORD (the cast, everywhere), ASSERT (`postselect`).
`classicalise` is NOT a fourth: it is an OBSERVER of an already-existing record, in
exactly the same class as `density_matrix(ctx)` and `statevector(ctx)` — test and
analysis tooling that reads state without being an operation on it.

  • NO BACKACTION, and it is not the §3.9 "silent trace" exception either: the record
    wires were pinched at the cast, so their off-diagonals are ALREADY zero; reading
    the populations of an already-classical variable disturbs nothing. `density_matrix`
    before and after `classicalise` is bitwise identical (named test).
  • IT RETURNS A DISTRIBUTION, NOT A VALUE. That is the type-level defence against
    smuggling a token into host control flow: there is no scalar to branch on. A user
    who wants an outcome to branch on must use `cases` (record) or `shots` (sample).
  • IT DOES NOT CONSUME the token (tokens are copyable, §3.6 / i4ri §2.2).

LOUD RESTRICTIONS:
  • DM only. On Eager, tokens do not exist (outcomes are scalars) — `MethodError`.
    On Tracing there is no state at all — a descriptive `ErrorException` naming
    `density` and `shots`.
  • Every base record wire must still be LIVE: after `discard!(t)` or region exit the
    record has been summed away and its distribution is gone. Loud error naming
    `discard!` and the §3.6 last-use rule.
  • Fan-in capped at the shipped `CASES_MAX_FANIN` (2^K configurations), reusing the
    same constant and the same error text shape as `cases` — one cap, one meaning.

COST. `O(2^capacity)` to read the density matrix plus `O(2^K)` evaluator calls. That
is the same scale contract as the shipped `density_matrix`/`choi` harness (~7 wires),
and the docstring says so.
"""
function classicalise(t::ClassicalBit{DensityMatrixContext})::Dict{Bool,Float64}
function classicalise(t::ClassicalWord{W,DensityMatrixContext})::Dict{Int,Float64} where {W}
```

Internals: `_record_populations(ctx, wires) -> Vector{Float64}` sums `ρ`'s diagonal
over the mask complementary to the record slots — the same index arithmetic as
`test/choi.jl`'s `_ptrace_keep`, but written in `src/` (the test harness must stay
test-side; `src/` gets its own dependency-free helper, in the `replay.jl` style).

**Why M11 needs it.** Two reasons, both about testing physics rather than pinning
numbers: (i) the syndrome-distribution law (`P(syndrome = 0) = (1−p)³ + p³` for the
bit-flip code, §6) is a *channel-level* statement that must be checkable without
sampling; (ii) it is how a channel-level test reads the classical half of an
instrument's output, which is exactly the half a marginal test is blind to (the wm28
lesson at the classical boundary).

**Spelling.** `classicalise` as the plan names it — one spelling, no `classicalize`
alias (a silent second name is a second thing to keep correct). Open ruling R3.

---

## §5 — M11 scope (design question 5)

### 5.1 Ships in M11

| Slice | Content | Files |
|---|---|---|
| S1 | `ChannelValue` tree, TP check, `∘`/`⊗`, `channel`, `same_channel`, named constructors; `NoiseN`/`builder` reshape | `src/channel/channel_values.jl` (structs), `channel_algebra.jl` (methods), `dag.jl`, `builder.jl` |
| S2 | Application: `apply!(ctx, ::ChannelValue, …)` + `apply_noise!`, per-context lowering, **guardrail-1 wiring (§0.1)**, `_replay_dm!` NoiseN branch | `src/context/noise.jl`, `density.jl`, `tracing.jl` |
| S3 | Stinespring: `Dilation`, `dilate`, Householder completion, mixed-unitary emitter, artifact lint | `src/channel/stinespring.jl` |
| S4 | `classicalise` + `_record_populations` | `src/context/noise.jl` |
| S5 | Channel-level `∘`/`⊗` on `ChannelDAG` + `channel_dag` (**§0.2**) | `src/channel/dag_algebra.jl` |
| S6 | QECC typing: `AbstractCode`, `StabilizerCode` + validation, `EncoderSpec`, `Encoded`, `encode_state`/`decode_state`, `RecoveryProgram`, `Superchannel`/`QECCProtect`, `effective_logical_noise`, `fault_tolerant_lift` refusal | `src/qecc/{codes,encode,recover,protect}.jl` |
| S7 | `bitflip_code()` + its `EncoderSpec` + syndrome/correction program, in surface vocabulary | `src/qecc/repetition.jl` |
| S8 | Portability: `select` host-scalar methods (**§0.4**) | `src/surface/tokens.jl` |
| S9 | Physics distillations (§7) — **before** the code that cites them | `docs/physics/` |
| S10 | Tests (§6) | `test/test_m11_noise.jl`, `test_m11_qecc.jl` |

### 5.2 Gated to later epics (explicitly NOT M11)

- **Steane [[7,1,3]]** — a reimport gate of its own (plan §M11), with Choi-level
  encode∘decode tests and its own distillations.
- **Encoder synthesis** (Cleve–Gottesman) from stabilizer generators; CSS structure.
- **Executable general dilation** — blocked on an Orkan `unitary_kq` entry or a
  KAK/QSD synthesis round (§0.3, §2.6). Filed as a cross-repo work item with an ABI
  sketch.
- **Kraus-rank compression** — needs an eigendecomposition; `LinearAlgebra` is not a
  core dependency (§0.7).
- **CP trace-non-increasing families / `postselect`** — the effect surface is not
  shipped; admitting subnormalised families first would let the CP-TNI regime in
  silently (§6 P1).
- **Fault tolerance** of any kind (§3.5).
- **Large-`R` ensemble channels.** M12's `_assert_randomized_legal`
  (`src/library/evolve/evolve.jl:130`) promises that "the DM lowering of the ensemble
  is M11's mixture value (KrausFamily/NoiseN)". **M11 as scoped here does NOT close
  that reference** for realistic qDrift sizes (`R ~ 10⁴` samples of `W`-wire values):
  `MixedUnitary{N,R}` is designed for the `R ≤ 16` enumerated case, and a `W`-wire
  mixture has no 1-local native path. Closing it needs a distinct `EnsembleChannel`
  value with a sampling/DP lowering. **Filed; the M12 message should be softened in
  the same commit rather than left as an over-promise.**
- **`TrajectoryContext{DM}`** (noisy trajectories, i4ri §3.3).

### 5.3 The acceptance example — 3-qubit bit-flip code, in surface vocabulary

The `[[3,1,1]]` repetition code: `S = ⟨Z₁Z₂, Z₂Z₃⟩`, `X̄ = X₁X₂X₃`, `Z̄ = Z₁`.

> **Honest statement of what it does.** It corrects an arbitrary single **X** error.
> Its distance as a general stabilizer code is **1**, not 3: `Z₁ ∈ N(S) \ S` has
> weight 1, so a single phase error is a logical error. Every claim below is
> therefore made **relative to the bit-flip noise model**, and the docstring and the
> `distance` field say `1`. (Calling it "distance 3" is the standard sloppiness this
> project should not ship.)

```julia
# --- E : L → P ---------------------------------------------------------------
"""Encode one logical qubit into three physical ones: |ψ⟩ ↦ α|000⟩ + β|111⟩."""
function encode_bitflip(ψ::QBool)
    a = QBool(false)
    b = QBool(false)
    a ⊻= ψ                      # a ← a ⊕ ψ   (ψ controls)
    b ⊻= ψ
    return (ψ, a, b)
end

# --- R : P → P  (syndrome extraction + correction; the i4ri token customer) ---
"""
Extract the two Z-parity syndromes into a `QInt{2}` ancilla register, measure it
ONCE, and let that ONE record token drive all three corrections through
`select`/`ClassicalTable` — the canonical copyable-token customer (§3.6, i4ri §2.2).
"""
function recover_bitflip(d1::QBool, d2::QBool, d3::QBool)
    s  = QInt{2}(0)             # two fresh |0⟩ syndrome wires; wire 1 = MSB
    s1 = s[1]; s2 = s[2]        # borrowed single-wire handles (D2)

    s1 ⊻= d1; s1 ⊻= d2          # parity(d1,d2)  = the generator Z₁Z₂
    s2 ⊻= d2; s2 ⊻= d3          # parity(d2,d3)  = the generator Z₂Z₃

    syn = Int(s)                # ONE record: 2·s1 + s2   (consumes s)
    loc = select(syn, BITFLIP_RECOVERY)   # syndrome ↦ which qubit to flip (0 = none)

    data = (d1, d2, d3)
    for j in 1:3                # host loop over a host range — unrolls at trace time
        @cases loc == j begin
            not!(data[j])
        end
    end
    return (d1, d2, d3)
end

"""
Syndrome ↦ correction location, indexed by the syndrome VALUE 0:3.
  0b00 → no error         0b10 → X on d1
  0b11 → X on d2          0b01 → X on d3
"""
const BITFLIP_RECOVERY = ClassicalTable([0, 3, 1, 2])

# --- D : P → L ---------------------------------------------------------------
"""Decode by running the encoder's CNOTs in reverse; d2,d3 return to |0⟩ and are
traced at region exit (§3.9 — the residual wires are the environment)."""
function decode_bitflip(d1::QBool, d2::QBool, d3::QBool)
    d3 ⊻= d1
    d2 ⊻= d1
    return d1                   # d2, d3: owned, unreturned ⇒ silently traced
end
```

Check against CLAUDE.md #11: no gate, no rotation angle, no process value; casts
(`QBool`, `QInt`, `Int`), the action family (`⊻=`, `not!`), `cases`, and one library
helper (`select`). It reads like ordinary Julia. ✅

The whole protected channel is then

```julia
protected(ψ) = decode_bitflip(recover_bitflip(noisy(encode_bitflip(ψ))...)...)
```

and its `ChannelDAG` form is `effective_logical_noise(𝓝, BITFLIP_SPEC, BITFLIP_RECOVERY_PROG)`
with `𝓝 = bit_flip(p) ⊗ bit_flip(p) ⊗ bit_flip(p)` (a `ChannelTensor` of
`MixedUnitary`s, applied factor-wise through three native `channel_1q` calls on DM).

### 5.4 Portability work item (§0.4)

```julia
# Eager: a measurement cast returns a real scalar, so `select` must accept one.
select(pred::Bool, a, b) = pred ? a : b
function select(n::Integer, table::AbstractVector{<:Integer}) ... end   # same totality check
function select(n::Integer, tbl::ClassicalTable) ... end                # same totality check
```

Without these, §5.3 runs on DM and Tracing but `MethodError`s on Eager — and the
whole point of §3.8 portability is that this one listing runs in all three. Same
totality errors, same messages.

---

## §6 — Test plan (design question 6)

Every test is named after the law it pins, per the plan's grep-able coverage-map
discipline.

### 6.1 Channel values

| Test | Statement |
|---|---|
| `M11.KRAUS.TP-CHECK` | a family with `‖ΣK†K − I‖ = 1e-3` throws `ArgumentError` naming the deviation; a legitimate one at 1e-16 constructs |
| `M11.KRAUS.NO-SILENT-RENORM` | the thrown message does **not** offer to rescale; no method rescales |
| `M11.CHANNEL.AD-KERNEL` | `same_channel(channel(gphase(π/3)), channel(I2))` **and** `channel(gphase(π/3)) != channel(I2)` — `ker(Ad) = U(1)` at the value level |
| `M11.CHANNEL.CHOI-1Q` | `choi(q -> apply_noise!(q, bit_flip(p)))` ≈ `(1−p)J(id) + p·J(Ad_X)`, analytic, several `p` |
| `M11.CHANNEL.COMPOSE` | `same_channel(bit_flip(p) ∘ bit_flip(q), bit_flip(p+q−2pq))` — composition of independent bit flips is a bit flip with the XOR-convolved probability (exact, analytic) |
| `M11.CHANNEL.TENSOR-LOCALITY` | a `ChannelTensor` of three 1-local factors lowers to three `channel_1q` calls, not one `4^3` superop (Orkan has no such entry — a structural regression test for §0.3) |
| `M11.CHANNEL.STRATIFICATION` | `@test_throws MethodError ctrl(bit_flip(0.1))`; `@test_throws MethodError X ∘ bit_flip(0.1)`; `@test_throws MethodError bit_flip(0.1) ⊗ X`; `@test !(KrausFamily <: Sturm.ProcessValue)` |
| `M11.NOISE.GUARDRAIL-1` | `when(c) do apply_noise!(q, ch) end` → loud error mentioning P4/§3.5 (**closes §0.1**); ditto for the legacy `apply_channel!` |
| `M11.NOISE.CERT-REFUSES` | `certify` on a DAG holding a real `ChannelValue`-bearing `NoiseN` throws (re-pin with the non-stub value) |
| `M11.NOISE.PASS-BARRIER` | `FuseUnitaryRunsPass` fuses on both sides of a `NoiseN` and moves nothing across it |
| `M11.NOISE.EAGER-LOUD` | `apply_noise!` on Eager without the flag errors, naming `density`, `shots`, `stinespring=true` |

### 6.2 Stinespring

| Test | Statement |
|---|---|
| `M11.DILATE.KRAUS-RECONSTRUCT` | `U[i·d+1:i·d+d, 1:d] ≈ Kᵢ` for all `i < R`, `≈ 0` for `R ≤ i < 2^E` — **the contract itself** |
| `M11.DILATE.UNITARY` | `‖U†U − I‖_∞ ≤ STINESPRING_ATOL` |
| `M11.DILATE.EXACT-COLUMNS` | `‖U[:,1:d] − Ṽ‖_∞ ≤ STINESPRING_ATOL` (the phase-fix proposition of §2.3) |
| `M11.DILATE.ENV-LEADING` | the endianness pin, on `amplitude_damping(0.3)` — chosen because it is non-unital and asymmetric, so a swapped env/data ordering produces a *different channel* the test can see (a Pauli channel could not) |
| `M11.DILATE.CHOI-EQUALS-KRAUS` | three-way DM agreement: structured mixed-unitary emission ≡ dense `Dilation` ≡ native `channel_1q`, all ≈ analytic |
| `M11.DILATE.DETERMINISM` | `dilate(ch).u == dilate(ch).u` bitwise (no RNG, no tie-break drift) |
| `M11.DILATE.CTRL-UNREACHABLE` | `@test_throws MethodError ctrl(dilate(ch))`; `Dilation` subtypes neither `ProcessValue` nor `ChannelValue`; **source lint** on the artifact tokens |
| `M11.DILATE.NOT-IN-IR` | `apply_noise!(::TracingContext, ch; stinespring=true)` throws — the IR never holds a dilation |
| `M11.DILATE.ENV-TRACED` | after a dilated application, `live_wires(ctx)` is exactly the pre-call set (the env region closed) and the slot count is restored |
| `M11.DILATE.GENERAL-REFUSED` | `apply_noise!(q, amplitude_damping(0.3); stinespring=true)` throws the §2.6 message naming the Orkan/synthesis unblock — the honest-gap test |

### 6.3 QECC

| Test | Statement |
|---|---|
| `M11.CODE.VALIDATION` | each of the six `StabilizerCode` invariants rejected on a purpose-built bad code (non-commuting generators; dependent generators; a "logical" inside `S`; wrong pairing) |
| `M11.CODE.DISTANCE-EXHAUSTIVE` | for `bitflip_code()`, the minimum weight of `N(S) \ S` is **1** (witness `Z₁`) — pinning the *honest* distance, not the folklore 3 |
| `M11.QECC.ENCODE-DECODE-ID` | `Choi(trace(ψ -> decode_bitflip(encode_bitflip(ψ)...), 1)) ≈ Choi(id)` — encode∘decode is the identity **on the code subspace**, at the channel level |
| `M11.QECC.PROTECT-IDENTITY` | `Θ(id_P) ≈ id_L`, i.e. zero noise ⇒ identity logical channel |
| `M11.QECC.BELOW-THRESHOLD` | **the quantitative statement.** For i.i.d. bit-flip noise of strength `p`, the effective logical channel is exactly a logical bit flip of strength `p_L(p) = 3p²(1−p) + p³ = 3p² − 2p³`. Extracted from the 4×4 logical Choi as `p_L = ⟨Φ_X\|J\|Φ_X⟩`, `\|Φ_X⟩ = (X⊗I)\|Ω⟩`. Pinned to `atol = 1e-12` at `p ∈ {0.01, 0.05, 0.1}`. Derivation: majority vote fails iff ≥2 of the 3 qubits flip. |
| `M11.QECC.BREAK-EVEN` | the **two-sided** pin: `p_L(p) < p` for `p < 1/2` (checked at `p = 0.1`: `0.028 < 0.1`) and `p_L(p) > p` for `p > 1/2` (checked at `p = 0.6`: `0.648 > 0.6`), with the exact break-even `3p² − 2p³ = p ⟺ (2p−1)(p−1) = 0 ⟺ p = 1/2`. Correction that *hurts* above break-even is physics, and a test that only checks "protection helps" would miss a sign-flipped recovery table. |
| `M11.QECC.SYNDROME-DISTRIBUTION` | `classicalise(syn)` gives `P(0) = (1−p)³ + p³`, `P(1) = P(2) = P(3) = p(1−p)²+p²(1−p)`, analytic (syndrome 0 ⟺ all three agree) |
| `M11.QECC.TOKEN-REUSE` | one syndrome token drives three `@cases`; the resulting `p_L` matches the analytic value — which it would **not** if the token were re-measured per correction (that would decohere the record and change the logical channel). The copyable-token law with teeth |
| `M11.QECC.ENCODED-NO-LOGICAL-OPS` | `@test_throws MethodError` for `Bool(enc)`, `not!(enc)`, `dual(enc)`, `enc ⊻= q` — the F8 discipline at the type level |
| `M11.QECC.FT-LIFT-REFUSED` | `fault_tolerant_lift(...)` throws, and the message names the fault model / gadget set / schedule / threshold |
| `M11.DAG.COMPOSE-RELABEL` | `∘` on two independently traced DAGs whose `PortID`s collide produces the right channel (Choi-checked); the negative control is that naive concatenation does not |
| `M11.PORTABLE.SYNDROME` | §5.3 runs unchanged under Eager (`shots`, statistical, N≥1000, ±3σ), DM (exact), and Tracing (materialises `MeasureN` + `CasesN`), and the DM replay of the traced DAG reproduces the DM-streamed Choi |

### 6.4 `classicalise`

| Test | Statement |
|---|---|
| `M11.CLASSICALISE.NO-BACKACTION` | `density_matrix(ctx)` bitwise identical before/after |
| `M11.CLASSICALISE.DERIVED-CORRELATION` | for `n = !m`, `classicalise(m)` and `classicalise(n)` are exact complements (the shared-base-wire law L6) |
| `M11.CLASSICALISE.LOUD` | Eager → `MethodError`; Tracing → descriptive error; after `discard!(t)` → loud error naming the last-use rule; over-wide fan-in → the `CASES_MAX_FANIN` error |
| `M11.CLASSICALISE.NOT-A-VALUE` | the return type is a `Dict`, so `if classicalise(t) …` cannot compile into a branch on an outcome |

### 6.5 Sizing (so the tests actually run)

The Choi harness caps at ~7 wires (plan §4, F25/TR8). The **logical** channel is
1-in/1-out, so `choi(protected, 1; cap = 8)` needs: 2 Bell + 2 encoder-allocated + 2
syndrome = 6 live wires ⇒ a 2⁶×2⁶ density matrix. Comfortable. The **physical**
3-qubit Choi (which would need 6 Bell wires and a 2¹²×2¹² matrix ≈ 2 GB) is never
required — a point worth stating, because reaching for it is the obvious mistake.

---

## §7 — Physics prerequisites (CLAUDE.md principle 4)

`docs/physics/` currently has **none** of these. Each must be written (PDF +
distillation) **before** the code that cites it, per principle 4 and the plan's
§3.0 "proof/semantic decisions early" discipline.

| # | Distillation | Source | Cited by |
|---|---|---|---|
| P1 | `stinespring_1955_dilation.md` | Stinespring, Proc. AMS **6** (1955) 211–216, Thm 1; + Nielsen–Chuang §8.2.3 Thm 8.1 (operator-sum) and §8.2.4 Thm 8.2 (unitary freedom) | `KrausFamily` (TP-is-the-only-obligation), `dilate` (isometry, padding, completion ambiguity) |
| P2 | `knill_laflamme_1997_qec_conditions.md` | Knill & Laflamme, PRA **55**, 900 (1997), the `P Kᵢ†Kⱼ P = c_ij P` conditions | `QECCProtect` (why `Θ(𝓝) = id_L` is the correctability statement), the encode∘decode test |
| P3 | `gottesman_1997_stabilizer_codes.md` | Gottesman thesis, quant-ph/9705052, Ch. 3 (stabilizer formalism, syndrome measurement, `[[n,k,d]]`) + Cleve–Gottesman quant-ph/9607030 (encoder is an *algorithm*, hence a choice) | `StabilizerCode` validation, `EncoderSpec`'s "not in the code value" argument |
| P4 | `chiribella_2009_quantum_combs.md` | Chiribella–D'Ariano–Perinotti, PRL **101** 060401 (2008) and PRA **80** 022339 (2009) | `Superchannel` — the "a comb *is* a circuit with a hole" argument that licenses the DAG-transformation modelling |
| P5 | `shor_1995_reducing_decoherence.md` | Shor, PRA **52**, R2493 (1995) (the 9-qubit code; the repetition sub-block and majority vote) + N&C §10.1 for `p_L = 3p² − 2p³` | the acceptance example and its threshold pin |
| P6 (low priority) | `aliferis_gottesman_preskill_2006_threshold.md` | quant-ph/0504218 (rigorous fault model, level reduction, exRec) | **only** the `fault_tolerant_lift` refusal message. If the distillation is not written, the message must state the requirements without citing the paper — the lint would otherwise fail. |

No distillation is owed for the Householder completion (numerical linear algebra,
not physics; Golub & Van Loan is a textbook reference in a docstring) or for the
amplitude-preparation tree (proved inline in three lines for non-negative real
amplitudes, §2.6).

---

## §8 — File layout, include order, namespace

```
src/channel/
  channel_values.jl   # STRUCTS: ChannelValue, KrausFamily, MixedUnitary,
                      #   ChannelTensor, ChannelSeq, nwires  — needs U2/Perm only
  channel_algebra.jl  # METHODS: ∘/⊗ closure, kraus(), channel(), same_channel(),
                      #   the named constructors — needs denoted_matrix/Ctrl
  dag_algebra.jl      # ∘/⊗ on ChannelDAG, channel_dag, _assert_endomorphic
  stinespring.jl      # Dilation, dilate, _householder_complete!, _emit_dilation!
  superchannel.jl     # Superchannel, callable interface, _insert
src/qecc/
  codes.jl encode.jl recover.jl protect.jl repetition.jl
src/context/
  noise.jl            # apply!(::ChannelValue) per context, apply_noise!, classicalise
```

**Include order** (mirroring the shipped struct/method split of `u2.jl`/`algebra.jl`):
`channel_values.jl` goes **immediately after `kernel/perm.jl` and before
`channel/ports.jl`**, because `NoiseN` (in `dag.jl`) must be able to name
`ChannelValue`, and `dag.jl` is included before `ctrl.jl`. Its methods
(`channel_algebra.jl`, which needs `denoted_matrix`) go after `constants.jl`, next
to `replay.jl`/`cert.jl`. `qecc/` and `context/noise.jl` go last (they use the
surface, tokens, `cases`, and `trace`).

**Namespace (CLAUDE.md convention 8).** **Nothing new is exported.** The seven
surface constructs are unchanged; noise and QECC are library/kernel vocabulary
reachable as `Sturm.…`:

```julia
public ChannelValue, KrausFamily, MixedUnitary, ChannelTensor, ChannelSeq,
    kraus, channel, same_channel, nwires,
    bit_flip, phase_flip, pauli_channel, depolarizing, dephasing,
    amplitude_damping, reset_channel, pinch_channel,
    apply_noise!, Dilation, dilate, classicalise,
    AbstractCode, StabilizerCode, bitflip_code, stabilizers, logical_x, logical_z,
    code_distance, EncoderSpec, Encoded, encode_state, decode_state,
    RecoveryProgram, syndrome_table,
    Superchannel, QECCProtect, effective_logical_noise, nports_in, nports_out,
    GadgetSet, FaultModel, fault_tolerant_lift
```

Rationale for the strongest of these: **applying noise is not a surface construct.**
A program does not apply noise to itself; the *environment* does. Noise application
is a statement about the device or the experiment, so it belongs with `density_matrix`
and `shots` — analysis/harness vocabulary — not with `not!` and `when`.

---

## §9 — Risks, alternatives rejected, open rulings

### 9.1 Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | **`NoiseN` reshape is a core change** touching a shipped, frozen IR struct | Blast radius enumerated by grep (§0.6): four files, no algorithm changes. Land it as its own slice with the existing `test_m8_channel.jl` suite green before anything else in M11 |
| R2 | **Tensor-product endianness.** Three orderings must agree: `apply!` MSB-first, `_ptrace_keep` `keep[1]`-MSB, and the dilation's env-leading rows | One function per pin, one named test per pin; the dilation test uses a non-unital, asymmetric channel so a swap is *visible* |
| R3 | **`NTuple` storage compile-time blowup** if someone builds many `(N,R)` combinations | `KRAUS_MAX_ENTRIES` guard; realistic set is ~6 concrete types. If it bites, fall back to the `ChannelDAG.nodes` pattern (`NTuple{L,ComplexF64} where L`, non-concrete field, still frozen) |
| R4 | **The Eager dilation is a trajectory and someone will read it as the channel** | The flag is required and greppable; the docstring says "one unravelling"; `shots` is named in the message. Precedent: M12's S10 guard |
| R5 | **`p_L = 3p² − 2p³` is only right if the recovery table is right**, and a sign-flipped table can still "look protective" at small `p` | The two-sided break-even test (§6.3) plus the exact syndrome distribution via `classicalise` — three independent pins on the same table |
| R6 | **`effective_logical_noise` silently produces nonsense on a mis-shaped 𝓝** | Three loud preconditions (endomorphism on lineage, no `cout`, arity), reusing `certify`'s own checks |
| R7 | The M12 forward reference to "M11's mixture value" is **not** closed by this scope | Stated in §5.2; the M12 error message should be softened in the same commit |

### 9.2 Alternatives considered and rejected

1. **`KrausFamily <: ProcessValue` with a throwing `ctrl` method.** Rejected: a
   throwing method is weaker than no method (`src/kernel/ctrl.jl:19` is explicit
   about this), and subtyping `ProcessValue` would let it into `Tensor`, `Seq`,
   `ApplyN`, `_footprint`'s fail-closed catch-all, and `within` — six sites to teach
   refusal instead of zero.
2. **Dilation as a `ProcessValue` in a wrapper `ctrl` refuses** (the brief's option
   (a)). Rejected for the same reason, sharpened: the wrapper would still be
   absorbable by `Tensor{A<:ProcessValue,B<:ProcessValue}` and thence into a
   `UnitaryBlock` body, and `ctrl(::UnitaryBlock)` **is** a shipped method. That is
   the smuggling path P4 forbids, reachable in two composition steps.
3. **A `LogicalPort`/`PhysicalPort` `PortKind`.** Rejected on physics: a logical
   qubit is a subspace of a *bundle's* joint Hilbert space defined *relative to a
   code*; no individual wire is logical. It would also break P7's
   dimension-agnostic parametricity for no gain.
4. **`effective_logical_noise` as a `ChannelPass`.** Rejected: a pass must preserve
   the Choi denotation (`src/channel/passes.jl:82`); a superchannel must change it.
   Reusing the framework would put a denotation-changing rewrite under a
   denotation-preserving boot lint.
5. **`effective_logical_noise` as a runtime map on reified channel values.**
   Rejected for M11: it needs F18's channel-reification API (combs with memory,
   strategy typing) and puts a channel-shaped object into runtime circulation one
   refactor away from a `ctrl` request. Filed as a research step.
6. **Encoder stored inside the `Code` value.** Rejected: the encoder is a gauge
   choice (Cleve–Gottesman gives *an* algorithm), so baking one in re-imports the
   F8 conflation at the value level.
7. **Context-level noise policy** (`density(cap; stinespring=true)`). Rejected: the
   same source line would mean different things in different contexts.
8. **Gram–Schmidt completion on `I − ṼṼ†`.** Rejected: needs a tuned rank-detection
   tolerance inside the algorithm. Householder has none.
9. **Taking `LinearAlgebra` into core** for QR/eigen. Rejected (CLAUDE.md conv 4,
   and `src/` is explicit about avoiding it twice). Consequence accepted: no rank
   compression in M11.
10. **Flattening `⊗` of channel values into one `KrausFamily`.** Rejected: it
    destroys the locality that lets DM use the only channel entry Orkan has.
11. **Silently applying multi-qubit noise as a product of 1-local channels.**
    Rejected: correlated noise is not a product, and factorising it silently is a
    physics lie. `ChannelTensor` says "product" explicitly; a genuine `KrausFamily{2}`
    errors and names the dilation.
12. **Keeping `encode(ch, code)` as sugar over the three new operations.** Rejected:
    it *is* the conflation (F8), and a sugar spelling would let it back in through
    the door marked "convenience".
13. **Giving `Encoded` a `Bool` cast** (transversal measure + majority vote).
    Rejected: transversal measurement is a fault-tolerance claim; conflating it with
    "decode then measure" is F8 at the cast level. Two different channels, and only
    one is offered in M11 (`decode_state` then `Bool`).

### 9.3 Open questions needing a Tobias ruling

| # | Question | Proposal A's recommendation |
|---|---|---|
| **Q1** | PRD §5 line 1415 still reads "QECC (P6): unchanged — `encode(ch, code)` is `Channel → Channel`". This design deletes it. A **normative PRD edit** is required. | Replace with the three typed operations + the level table of §3. This is a PRD action requiring its own review pass (as the F31 recommendation notes for the carried-contract table). |
| **Q2** | Should the noise-application verb be `apply!` (method on the existing name) only, or also `apply_noise!`? | Both: `apply!` at the context/wire layer (§4.3's "same surface"), `apply_noise!` at the handle layer. Neither exported. |
| **Q3** | `classicalise` vs `classicalize`; `Dict` vs sorted `Vector{Pair}` return. | `classicalise` (the plan's spelling), one spelling only; `Dict` (order-free is honest for a distribution). |
| **Q4** | Is the **Orkan `unitary_kq` entry** approved as a cross-repo work item? It is the difference between "general dilation constructed" and "general dilation executable", and it unblocks correlated multi-qubit noise too. | Yes, but **after** M11 ships: it is an Orkan-side change with its own ABI verification discipline (plan §7 verdict (b) — never trusted from a branch, always re-verified against live headers). |
| **Q5** | Does `Encoded` get *any* logical operation in M11 (e.g. transversal `logical_not!` for the repetition code)? | **No.** One code's easy case invites the general non-canonical case. First item of the FT epic instead. |
| **Q6** | M12's `_assert_randomized_legal` promises M11 closes the qDrift ensemble lowering. It does not (§5.2). Soften the message now, or file it? | Soften in the same commit, and file the `EnsembleChannel` design as its own bead — a stale forward reference in an error message is exactly the kind of drift the worklog discipline exists to catch. |
| **Q7** | Should the **`stinespring` opt-in** be a kwarg or a distinct verb (`apply_dilated!`)? | Kwarg: it is the same operation with a different lowering, and a distinct verb would suggest a distinct channel. But a verb is more greppable — worth a ruling. |
