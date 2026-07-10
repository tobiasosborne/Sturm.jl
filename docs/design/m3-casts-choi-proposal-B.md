# M3 Proposal B — QBool, consuming casts, D1 literal, Choi harness

**Author:** Proposer B (3+1 round, bead Sturm.jl-77m2). Lens: **API seams and
failure modes first.** Written against landed M1 (`src/kernel/`) + M2
(`src/context/`, `src/orkan/`, `src/types/wire.jl`). No Julia was run.

---

## 0. Executive summary (10 lines)

1. **Handle = `(ctx, wire)`.** A register is *"a handle into a context that
   owns the state"* (§4.3, verbatim). `QBool` stores `ctx::AbstractContext` +
   `wire::WireID`. QInt{W}/views inherit this: leaf = `(ctx, wires…)`; a view
   wraps a parent handle + transform. **Storing `ctx` closes the cross-context
   `WireID`-collision hole** that a bare-`WireID` handle leaves open (ids are
   per-context monotone, so id 1 exists in every context).
2. **Preparation is `Rz(φ) ∘ Ry(θ)`, `θ = 2·asin(√p)`** — reuse M1's
   fuzz-tested `∘`; never hand-transcribe a quaternion. Global phase is dropped
   by Ad (§4.3), which is *why* the poles degenerate.
3. **`DomainError` for `p∉[0,1]`, checked before `sqrt`** (fail-fast, good
   message); never widen to `Complex` (D1). `Float64(φ)` before any emit.
4. **`Bool(q::QBool)` is Eager-only in M3**; on DM a scalar outcome is the D3
   token problem (deferred to M8) — DM `Bool` throws a descriptive error. This
   is PRD-consistent, not a shortcut: §4.4 makes measurement-scalars route
   through `cases`/tokens.
5. **The `cq∘qc = pinching` Choi law is delivered two ways**: (a) one-pass,
   deterministic, coherent-probe **channel-level** pinch on DM (harness);
   (b) statistical surface-composite `QBool(Bool(q))` on Eager. The fully
   deterministic *surface* DM Choi is an explicit **M8 IOU**.
6. **P2 implicit-cast warning lives on `Base.convert(Bool, ::QBool)`** (the
   compiler-inserted path), not on explicit `Bool(q)`. Neither is type piracy
   (`QBool` is ours).
7. **Consumption reuses M2's single-sourced set + slot recycling**; `Bool`
   measures-keeps-outcome-retires-recycles, mirroring `trace_wire!` minus the
   discard. Region exit already skips consumed/retired wires — no double-trace.
8. **Error taxonomy (S13):** `DomainError` (chart), `ArgumentError`
   (well-formed-but-forbidden: wrong-context handle, DM scalar `Bool`),
   `error()` w/ `WireID` (guardrails: use-after-consume, double-consume).
9. **`choi(f, nin)` is test-side** (`test/choi.jl`), pure Julia over
   `density_matrix`, tracking f's **output wires from the returned handle** and
   Julia-side partial-tracing to the `(out, ref)` block. Needs one src-side
   seam: an internal **adopt constructor** so the harness can wrap a
   pre-prepared Bell-half in a `QBool`.
10. **First exports of the rebuild:** `QBool, plus, minus, magic_T`
    (`Base.Bool`/`convert` methods need no export). `choi` stays in `test/`.

---

## 1. `QBool` type — `src/types/qbool.jl`

### 1.1 The register-handle pattern (the M4/M6-load-bearing decision)

```julia
struct QBool
    ctx::AbstractContext   # the owning context (§4.3: a register IS a handle into a context)
    wire::WireID           # the identity core from M2 types/wire.jl
end
```

**Why store `ctx` and not rely on `current_context()`:** `WireID`s are minted
from a *per-context* `wire_counter` (M2 `abstract.jl:70`, `allocate!`). So
`WireID(1)` exists in **every** context. A bare-`WireID` handle from context A,
used while context B is bound, would pass B's `haskey(wire_to_slot, w)` liveness
check and **silently target a different physical qubit** — exactly the
"...or from another context" hazard the `WireID` docstring
(`types/wire.jl:30`) and `q()` error (`abstract.jl:137`) already flag but
cannot *prevent* on identity alone. Storing `ctx` lets every surface op assert
`q.ctx === current_context()` and fail loud (`ArgumentError`) on a cross-context
handle. This is the seam my lens exists to catch.

**Generalization contract (so M4/M6 add without refactor):**
- **Leaf handle** = `(ctx, wire(s))`. `QInt{W}` (M6) = `(ctx, NTuple{W,WireID})`
  (or a contiguous slice descriptor); `x[i]` returns a wire-handle wrapper
  over `(ctx, wire_i)` (D2). Same `ctx` field, same liveness/consume plumbing.
- **View** (M4) = wrap a parent *handle* + a transform tag; `dual(v)` unwraps at
  dispatch time (`dual(v::DualView)=v.parent`, D2). Views borrow → they hold a
  parent handle, register **no** owned wire (§3.9). The `ctx` is reachable
  through the parent, so the `=== current_context()` guard still applies.
- Define an internal alias for the contract, used by cast/action code:
  `_owner(h) -> AbstractContext`, `_wires(h) -> Tuple{Vararg{WireID}}`. `QBool`:
  `_owner(q)=q.ctx`, `_wires(q)=(q.wire,)`. Surface ops translate handle →
  `(ctx, wires)` then call the M2 `apply!(ctx, value, wires)` (which is
  wire-level, never handle-level — clean layering already in `ad.jl`).

**Type-stability note.** `ctx::AbstractContext` is an abstract field, so `QBool`
is not concrete-leaf-typed; handle ops take a dynamic dispatch on `ctx`. This is
**acceptable**: handles are not in the hot loop (the hot loop is `apply!` over
raw wires + the per-wire fusion buffer, M2 `abstract.jl`). We deliberately do
**not** parameterize `QBool{C<:AbstractContext}` — the PRD's surface names are
`QBool` and `QInt{W}` (W is the *only* type parameter; §3.1), and a context
parameter would metastasize into `QInt{W,C}`. `@code_warntype` gate stays on the
`apply!`/cast wire-level path, not on handle construction.

### 1.2 Construction — the D1 literal

```julia
"""
    QBool(p::Real, φ::Real = 0.0)

Preparation cast (cq, §3.2). Allocates a fresh wire in |0⟩ (region-owned, §3.9)
and prepares  √(1−p)|0⟩ + √p·e^{iφ}|1⟩  by applying the U(2) value
`Rz(φ) ∘ Ry(2·asin(√p))`. `DomainError` if p ∉ [0,1] (D1: never widen to
Complex). φ is unrestricted. See docs/physics/... (D1 ruling, PRD §9).
"""
function QBool(p::Real, φ::Real = 0.0)
    ctx = current_context()
    (0 ≤ p ≤ 1) || throw(DomainError(p,
        "QBool(p, φ): p must be a probability in [0,1] (got $p). QBool never " *
        "widens to Complex (D1); pass an amplitude via a future Complex method if needed."))
    w = allocate!(ctx)                          # |0⟩ = |e_G⟩, pushed to region owned-set
    u = _prep_u2(Float64(p), Float64(φ))        # Float64(φ) BEFORE any emit (Irrational-safe, D1)
    p == 0 || apply!(ctx, u, (w,))              # p=0 ⇒ Rz(φ) is pure global phase on |0⟩ — skip the ccall
    return QBool(ctx, w)                        # the (ctx,wire) inner constructor = the adopt seam
end

"""definite-bit cast (§3.2). |0⟩ needs no gate; |1⟩ is one X (exact, no chart)."""
function QBool(b::Bool)
    ctx = current_context()
    w = allocate!(ctx)
    b && apply!(ctx, X, (w,))                   # X = U2(0,1,0,0,π/2); |0⟩→|1⟩ exactly
    return QBool(ctx, w)
end
```

**The exact preparation value.** With `θ = 2·asin(√p)`,
```
_prep_u2(p, φ) = Rz(φ) ∘ Ry(θ)
```
Reusing M1's Hamilton `∘` (fuzz-certified, `test_kernel_u2.jl` T0) is the whole
point — no hand-transcribed quaternion, no fresh convention-slip surface. For
the record, the resulting `U2` is (φ_U2 = 0, i.e. a bare SU(2) representative):
```
w =  cos(φ/2) cos(θ/2)
x = −sin(φ/2) sin(θ/2)
y =  cos(φ/2) sin(θ/2)
z =  sin(φ/2) cos(θ/2)
```
Derivation check via `denoted_matrix` first column (e=cis(0)=1):
`col₀ = (w − i z, y − i x) = (cos(θ/2)e^{−iφ/2}, sin(θ/2)e^{+iφ/2})`, so
`U|0⟩ = √(1−p) e^{−iφ/2}|0⟩ + √p e^{+iφ/2}|1⟩` — relative phase `e^{iφ}` on
`|1⟩`, Born weight `p`. ✓ (`sin(θ/2)=√p`, `cos(θ/2)=√(1−p)` since
`θ/2 = asin(√p)`). Global phase `e^{−iφ/2}` is dropped by Ad (§4.3, `ad.jl`
`_emit_u2!` drops φ) — harmless.

`_prep_u2` lives in `qbool.jl` (a preparation helper, not surface); it is
**pure** (no context) → separately unit-testable, which is where the pole
degeneracy is asserted as a value fact (below). `asin`/`sqrt` stay real: for
`p>1` they would themselves throw `DomainError`, but we guard first for the
better message (the PRD's "falls out of real sqrt/asin for free" is the safety
net, not the primary check).

### 1.3 Pole degeneracy — `QBool(1,φ) == QBool(true)` (a seam I resolve differently)

At `p=1`: `θ=π`, `cos(θ/2)=0`, so `_prep_u2(1,φ) = (0, −sin(φ/2), cos(φ/2), 0)`
whose first column is `(0, e^{iφ/2})`, i.e. `U|0⟩ = e^{iφ/2}|1⟩` for **all** φ.
The φ-dependence is a pure **global** phase on a 1-D space → the prepared
**state** is `|1⟩` and the prepared **density matrix** is `|1⟩⟨1|`, exactly and
φ-independently.

**Decision: do NOT overload `Base.==` on `QBool`.** The PRD text
`QBool(1,φ) == QBool(1,φ′) == QBool(true)` (D1 required test) reads naturally as
a `==` but a `QBool` is a *live handle* over a *distinct wire* — two of them are
never structurally equal, and a `==` that secretly compared prepared *states*
would be:
- **dishonest after entanglement**: `q ⊻= r` (M4) leaves `q`'s (p,φ) stale, so a
  state-comparing `==` from cached literals would lie;
- **non-hashable-consistent** (a live-handle `==` with a `hash` that ignores the
  handle is exactly the trap M1 avoided by leaving `Base.==` as exact structural
  equality, `u2.jl:180`).

So the pole law is a **state-level** law, tested via readout (§4 below): the
prepared density matrices of `QBool(1,φ)`, `QBool(1,φ′)`, `QBool(true)` are all
`≈ [0 0; 0 1]`. This is **exact at the density level** (no global-phase
ambiguity — DM quotients it automatically). I record this as a **deviation from a
naïve reading of the PRD `==`**, grounded in §4.3 (Ad drops global phase) and
§4.5 (handles are identities). The value-level twin — `_prep_u2(1,φ)` denotes a
map sending `|0⟩ ↦ |1⟩` up to global phase for all φ — is *also* asserted as a
pure-function test on `_prep_u2` (via `statevector`-up-to-global-phase, or via
`denoted_matrix(_prep_u2(1,φ))[:,1]` up to phase). `p=0` degenerates identically
(`θ=0`, `Ry(0)=I2`, `Rz(φ)|0⟩=|0⟩` up to global phase).

### 1.4 Named library constants (sugar, exported)

```julia
plus()    = QBool(0.5)         # |+⟩ = (|0⟩+|1⟩)/√2         (φ=0)
minus()   = QBool(0.5, π)      # |−⟩ = (|0⟩−|1⟩)/√2         (φ=π)
magic_T() = QBool(0.5, π/4)    # |T⟩ = (|0⟩+e^{iπ/4}|1⟩)/√2
```
Thin sugar on the constructor (D1: "Base's `im = Complex(false,true)` pattern").
`π` here is `Irrational`; `QBool` does `Float64(φ)` before emit, so `minus()` /
`magic_T()` are Irrational-safe (D1 required test). `|i⟩ = QBool(0.5, π/2)` (the
`inject_S!` resource, §7.6) is left inline per the PRD — not named. Exported.

---

## 2. Consuming casts — `src/surface/casts.jl`

### 2.1 `Bool(q::QBool)` — the qc cast

```julia
function Base.Bool(q::QBool)                       # our type → NOT type piracy
    ctx = q.ctx
    ctx === current_context() ||
        throw(ArgumentError("Bool(q): register $(q.wire) belongs to a different " *
            "context than the active one — a handle escaped its region/context"))
    _assert_live(ctx, q.wire)                      # error() with WireID (§2.3)
    b = _measure_wire!(ctx, q.wire)                # Eager: sample+collapse+retire; DM: throws (§2.2)
    mark_consumed!(ctx, q.wire)                    # single-sourced set (§4.5) — M2 API
    return b
end
```

Consumption reuses M2 unchanged: `mark_consumed!` (`abstract.jl:146`) writes the
one consumed set; the wire is retired (removed from `wire_to_slot`, slot
recycled) by `_measure_wire!`. **The handle dies at the cast** — after collapse
the info is classical and a live quantum handle would be a type lie (§3.2).

**`_measure_wire!` (Eager)** — measure but *keep* the outcome (this is why we
can't reuse `trace_wire!`, which discards it, `eager.jl:46`):
```julia
function _measure_wire!(ctx::EagerContext, w::WireID)::Bool
    core = _core(ctx)
    _flush_wire!(ctx, w)                           # this wire's fused 1q op only — disjoint fusions commute
    slot = core.wire_to_slot[w]
    p1   = _marginal_p1(core.state, slot)          # state.jl
    out  = _draw(core) < p1 ? 1 : 0                # ctx.rng (seeded reproducibility)
    _collapse!(core.state, slot, out)              # state.jl (projective, renormalize)
    out == 1 && _emit_x!(ctx, slot)                # reset to |0⟩ for recycle (fresh = |e_G⟩ invariant)
    delete!(core.wire_to_slot, w); _return_slot!(core, slot)   # retire + recycle
    return out == 1
end
```
This is `trace_wire!` minus the discard: identical collapse+reset+recycle, but
the drawn outcome is returned instead of thrown away. All of `_marginal_p1`,
`_draw`, `_collapse!`, `_emit_x!`, `_return_slot!` already exist (M2).

### 2.2 `Bool(q)` on the DM context — instrument semantics bite (deferred, justified)

`_measure_wire!(ctx::DensityMatrixContext, ...)` **throws**:
```julia
_measure_wire!(::DensityMatrixContext, w::WireID) =
    throw(ArgumentError("Bool(q) returns a scalar outcome, which on a " *
        "density context is a trajectory, not a channel (§3.8: DM executes " *
        "channels). Use @cases (M8) for the instrument, or the shot API. " *
        "The Choi harness measures the instrument channel directly."))
```
**Justification (PRD-grounded, not a shortcut):** §4.4 — measurement was never a
process value, and a scalar classical outcome extracted from a
channel-executing context is precisely the **dynamic-lifting/token** situation
that §3.6/D3 route through `ClassicalBit` tokens under `TracingContext`
(**M8**). Producing a scalar Bool on DM in M3 would require sampling +
**conditioning** the density matrix (`P_out ρ P_out / p_out`) — and Orkan
exposes CPTP channels but **no state-rescale ccall**, so the `1/p_out`
renormalization is not cheaply available (verified against `orkan/ffi.jl`: no
scale entry; `state_set` per-element only). Conditioning a wire *entangled* with
others by resetting only that wire would silently drop the correlated
conditioning — a wrong trajectory. Rather than ship a subtly-wrong DM `Bool`, we
fail loud and route the deterministic Choi through the instrument channel (§3).

The **channel denotation** of the qc cast on DM *is* available and exact — the
pinching instrument (both branches, block-accumulated, §3.8) — exposed as an
internal used by the harness (§3.3), not as surface `Bool`.

### 2.3 The failure paths (my lens: every misuse enumerated)

```julia
function _assert_live(ctx, w::WireID)
    is_consumed(ctx, w) &&
        error("register $w already consumed — measurement casts consume their " *
              "input (§3.2); a live handle to measured data is a type lie")
    haskey(_core(ctx).wire_to_slot, w) ||
        error("register $w is not live in this context (traced at region exit, " *
              "or from another region)")
    nothing
end
```

| Misuse | Mechanism | Result |
|---|---|---|
| **Double consume** `Bool(q); Bool(q)` | 2nd call: `is_consumed` true | `error()` w/ `WireID` |
| **Cast a dead wire** (traced at region exit, then used) | `!haskey(wire_to_slot)` | `error()` w/ `WireID` |
| **Cross-context handle** (`q.ctx !== current`) | `===` guard in `Bool` | `ArgumentError` |
| **Wrong context, matching id** (collision) | `===` guard fires *before* liveness | `ArgumentError` (closed by storing `ctx`) |
| **`if q` / `q && …`** | Julia requires `isa Bool` — does **not** auto-cast | `TypeError` (Julia's own) — *not* an implicit cast |
| **Implicit `convert`** (`v::Bool = q`, `push!(::Vector{Bool}, q)`) | `Base.convert(Bool, ::QBool)` | **`@warn` (P2)** then consume (§2.4) |
| **QBool escaping its region** | returned handle → wire traced at exit → dangling | `error()` (dead wire) on next use |
| **DM scalar `Bool`** | `_measure_wire!(::DM)` | `ArgumentError` → @cases/shot |

Note `if q` is a **TypeError**, not an implicit cast — Julia's `if`/`&&` check
`isa Bool` and never insert `convert`. So the P2 warning site is **not** `if`; it
is `convert` (below).

### 2.4 The P2 implicit-cast warning — where it actually arises

The only *implicit* cast in M3 is the **compiler-inserted `convert`**:
assignment to a `Bool`-typed slot/field, `Vector{Bool}` insertion,
`return`-into-a-`::Bool`-annotated-function, etc. Explicit `Bool(q)` does **not**
route through `convert`, so it warns nothing (the user asked). We overload:
```julia
function Base.convert(::Type{Bool}, q::QBool)      # our type → not piracy
    @warn "implicit measurement of a QBool (P2): the quantum→classical cast " *
          "collapses state — write `Bool(q)` explicitly to silence this" maxlog=1
    return Bool(q)
end
```
This is the *static shadow of the runtime rule* (§3.2, verbatim) and honours the
normative rule (§3.9): **implicit ops with backaction WARN** (casts collapse);
only backaction-free traces are silent (do not add a warning to `Bool`/`Bool`'s
explicit path, and do not silence `convert`). `maxlog=1` keeps it from
drowning a loop, per Base's own `depwarn` ergonomics.

---

## 3. The Choi harness — `test/choi.jl` (test-side, per plan)

### 3.1 Placement + convention pin

Test-side (`test/choi.jl`): it is kernel-level test *tooling*, licensed to use
`apply!` with kernel values and to reach `Sturm.` internals (item 3). **Not**
`src/` — it is not surface, and shipping a Choi builder in `src` would invite
surface code to call it.

**Normalization convention (pinned):** the **Choi state** (Jamiołkowski),
`J(Φ) = (Φ ⊗ id)(|Ω⟩⟨Ω|)` with `|Ω⟩ = 2^{−nin/2} Σ_i |i⟩_sys |i⟩_ref` the
**normalized** maximally-entangled state ⇒ `J` is a trace-1 density matrix for
CPTP Φ, comparable with `≈` (atol). `Choi(id) = |Ω⟩⟨Ω|`. (We pin *normalized* so
DM's exact `density_matrix` gives `J` directly, no rescale.)

**Bell-pair preparation, v2 kernel vocabulary** (per pair on wires (s, r)):
```julia
apply!(ctx, H, (s,))                 # H = U2(0,1/√2,0,1/√2,π/2)  → (|0⟩+|1⟩)/√2 ⊗ |0⟩
apply!(ctx, ctrl(X), (s, r))         # kernel ctrl (the choke point) → (|00⟩+|11⟩)/√2
```
`ctrl(X)` on `(s,r)` lowers (via `ad.jl` `_apply_controlled_u2!`, `u≈X`) to a
native `cx(s→r)` — exact. This is the *only* place the harness touches kernel
control, and it is legitimate tooling.

### 3.2 The harness (output-wire tracking is the crux)

`f` operates on **handles** and may **consume** its input and **allocate** its
output on a *different* wire (e.g. `cq∘qc` allocates a fresh output wire). So the
harness must read `J` over **f's actual output wires**, discovered from the
returned handle — not the input wires.

```julia
# f :: QBool -> QBool  (1-in/1-out for M3; nin generalizes to a tuple)
function choi(f, nin::Int = 1; cap = 2*nin + 4)     # cap ≥ 2·nin + f's scratch; 15-wire law cap
    density(cap) do ctx
        sys = ntuple(_ -> allocate!(ctx), nin)
        ref = ntuple(_ -> allocate!(ctx), nin)
        for i in 1:nin
            apply!(ctx, H, (sys[i],))
            apply!(ctx, ctrl(X), (sys[i], ref[i]))          # normalized Bell pair
        end
        qin  = Sturm._adopt_qbool(ctx, sys[1])              # SEAM: wrap a pre-prepared wire (§3.4)
        qout = f(qin)                                       # f consumes qin, returns output handle
        outw = qout.wire                                    # f's true output wire (may ≠ sys[1])
        ρ    = density_matrix(ctx)                          # full 2^cap × 2^cap (M2 readout)
        keep = (q(ctx, outw), q(ctx, ref[1]))               # Orkan slots to keep (output MSB, ref LSB)
        return _ptrace_keep(ρ, keep, cap)                   # 4×4 J in (out, ref) basis
    end
end
```

### 3.3 The `cq∘qc = pinching` channel (one-pass, coherent probe)

Because DM surface `Bool` is deferred (§2.2), the harness realizes the qc cast's
**channel denotation** directly — the pinching instrument — via a src-side
internal (added in `density.jl`, reusing `_apply_channel_1q!`):
```julia
const _PINCH_KRAUS = Matrix{ComplexF64}[[1 0; 0 0], [0 0; 0 1]]     # {P0, P1}, CPTP
_instrument!(ctx::DensityMatrixContext, w::WireID) =                # qc denotation, classical bit traced
    (_flush_wire!(ctx, w); _apply_channel_1q!(ctx, _PINCH_KRAUS, q(ctx, w)); nothing)
```
Then the harness's channel is `pinch = q -> (Sturm._instrument!(q.ctx, q.wire);
QBool(q.ctx, q.wire))` — in-place dephasing, output wire == input wire. Its Choi:
```
J_pinch = ½(|00⟩⟨00| + |11⟩⟨11|)     # coherences |00⟩⟨11| killed
```
which the test asserts `≈` the analytic pinch Choi **and** `≉ Choi(id) =
|Φ⁺⟩⟨Φ⁺|`. The Bell input is maximally coherent, so this exercises exactly the
off-diagonal-killing that a diagonal probe is blind to (the wm28 lesson,
§3.8 r6 rule).

### 3.4 DM readout mechanics (the concrete triangular-storage path — my lens)

`density_matrix(ctx)` (`density.jl:110`) → `_density` (`state.jl:66`) reads the
**MIXED_TILED** state **entrywise** through `orkan_state_get(state,i,j)`
(`ffi.jl:161`), which is **Hermitian/tiled-aware** — the harness never touches
the triangular tiling directly; it gets a dense `2^cap × 2^cap` `Matrix`. The
only ABI concern is that `state_get`'s `(i,j)` are **full basis indices**, bit
`k` = Orkan slot `k` (little-endian, `state.jl`/`abstract.jl:15` endianness pin).
So the harness maps **wire → slot via `q(ctx, w)`** (public) and traces on
*slots*, robust to slot recycling by `f`.

`_ptrace_keep(ρ, keep_slots, cap)` — pure Julia, no ccall:
```julia
function _ptrace_keep(ρ, keep::NTuple{K,Int}, cap::Int) where {K}
    N = 1 << cap; M = 1 << K
    J = zeros(ComplexF64, M, M)
    kb(idx) = mapreduce(t -> ((idx >> t[2]) & 1) << (t[1]-1), |, enumerate(keep); init=0)  # keep-bits, MSB=keep[1]
    tb(idx) = idx & ~mapreduce(s -> 1<<s, |, keep; init=0)                                  # traced-bits
    for j in 0:N-1, i in 0:N-1
        tb(i) == tb(j) || continue                 # partial trace: diagonal on the traced block
        J[kb(i)+1, kb(j)+1] += ρ[i+1, j+1]
    end
    J
end
```
(`enumerate(keep)` → `(position, slot)`; output ordering = `keep[1]` MSB. A
straightforward `O(2^{2cap})` loop — fine at the ≤15-wire law-test scale;
`2·nin` wires ⇒ `cap ≤ 30` = Orkan's cap, so law channels ≤ 15 wires, item 4.)

**Src-side seam required by the harness (item 3 "you may need to specify a small
readout addition"):** the internal **adopt constructor** `_adopt_qbool(ctx, w) =
QBool(ctx, w)` (the struct's own 2-arg inner constructor, aliased for clarity;
`public`-marked, not exported). Without it the harness cannot wrap a
Bell-prepared wire in a handle to hand to `f` (the surface `QBool(p,φ)` would
*re-prepare*, destroying the Bell pair). This is the minimal addition; no new
readout ccall is needed (`density_matrix` suffices).

---

## 4. Named law tests — `test/test_m3_*.jl`

Each `@testset` is named after its PRD section (grep-able coverage map, plan §4).

**§3.2 boundary algebra:**
- `qc∘cq = id` (**deterministic poles**, Eager): `Bool(QBool(false))==false`,
  `Bool(QBool(true))==true` (no RNG). "at Choi level" here = the classical→
  classical identity; asserted deterministically on both bits (a classical
  channel's Choi is trivial — noted, not dressed up as a quantum Choi).
- `cq∘qc = pinching` — **two probes, both coherent**:
  - (a) **one-pass channel Choi** (DM, deterministic): `choi(pinch,1) ≈
    ½(|00⟩⟨00|+|11⟩⟨11|)` **and** `≉ choi(identity_channel,1)` — the coherent
    Bell probe makes off-diagonal loss visible (wm28 regression, §3.8).
  - (b) **surface-composite** (Eager, statistical, coherent probe |+⟩, N≥1000,
    seeded): average `|ψ_out⟩⟨ψ_out|` over trajectories of the *actual shipped*
    `QBool(Bool(q))` starting from `plus()` → `≈ I/2` within 3σ. This tests the
    real code path, not a hand-built channel.

**D1 (§9) literal:**
- **pole degeneracy** (state-level, §1.3): `prepared_density(QBool(1,φ)) ≈
  prepared_density(QBool(1,φ′)) ≈ [0 0;0 1]` for random φ,φ′; same at p=0 →
  `[1 0;0 0]`. (`prepared_density(qf) = density(1) do ctx; qf(); density_matrix(ctx) end`.)
- **dispatch**: `QBool(true)` hits `QBool(::Bool)` (more specific than
  `QBool(::Real)`) — assert prepared state is `|1⟩`, and that no `DomainError`
  path runs (`true` is not routed through `[0,1]` check).
- **Irrational safety**: `minus()`, `magic_T()` run without error (φ=π, π/4 are
  `Irrational`; `Float64(φ)` before emit).
- **`_prep_u2` value law** (pure): `denoted_matrix(_prep_u2(0.5,0))[:,1] ≈
  [1,1]/√2` (|+⟩), `_prep_u2(0.5,π)` → |−⟩, `_prep_u2(0.5,π/4)` → |T⟩.

**Statistical (§4, N≥1000, ±3σ, seeded):**
- `Bool(QBool(p))` frequency for p∈{0.3, 0.7}: `|freq − p| < 3√(p(1−p)/N)`.

**Error taxonomy (S13, one policy test):**
- `@test_throws DomainError QBool(1.5)`, `QBool(-0.1)` (chart).
- `@test_throws ArgumentError` — DM scalar `Bool(q)`; cross-context handle
  (well-formed, forbidden).
- `@test_throws ErrorException` — double consume `Bool(q); Bool(q)`; use of a
  region-traced (dead) handle (guardrails, `error()` + `WireID`).
- assert **no custom exception type** is introduced (grep the M3 sources for
  `struct .* <: Exception` → none; S13 "no custom hierarchy").

**§3.9 region interaction:**
- QBool allocated in a `region() do…end`, **not** consumed → traced at exit;
  the handle is dead afterward (dangling → `error()`).
- QBool consumed by `Bool` *before* exit → region exit is a no-op for it (its
  wire is already retired **and** in the consumed set; `_exit_region!`
  `regions.jl:66` skips on both counts — **no double-trace**). Assert the free
  slot count is consistent (one alloc, one free, whether by `Bool` or by trace).
- seeded test **must not** assert trace placement / RNG-stream identity (§3.9
  corollary; plan §4).

---

## 5. Namespace

```julia
# src/Sturm.jl — the FIRST surface exports of the rebuild
export QBool, plus, minus, magic_T
# Base.Bool(::QBool) and Base.convert(::Type{Bool},::QBool) extend Base — no export needed.
public _adopt_qbool          # internal handle-adopt seam for the harness (reachable as Sturm._adopt_qbool)
# choi / _ptrace_keep live in test/choi.jl — NOT exported, NOT src.
```
`plus`/`minus`/`magic_T` are common words but neither is a `Base` export, so no
clash; the PRD mandates these exact names (§3.2, D1). Include order:
`types/qbool.jl` after `types/wire.jl` and after the contexts (it calls
`current_context`/`allocate!`/`apply!`); `surface/casts.jl` after `qbool.jl`.
Add a `src/surface/` directory (first appearance).

---

## 6. §3.9 region machinery interaction (consolidated)

- **Allocation-in-region:** `QBool(p)` → `allocate!` pushes the wire onto
  `region_stack[end]` (M2 `abstract.jl:123`). The QBool is **owned** by the
  enclosing region.
- **Consume vs exit-trace ordering:** `Bool(q)` retires the wire (deletes from
  `wire_to_slot`, recycles slot) **and** `mark_consumed!`s it. `_exit_region!`
  guards `haskey(wire_to_slot,w) && !(w in consumed)` — a consumed QBool fails
  **both** predicates, so it is skipped: **no double-trace, no double-free**.
  The single-sourced consumed set (§4.5) makes this correct without a
  per-object flag (the §8.5 desync class stays closed).
- **Escape:** returning a `QBool` out of its `region`/`eager`/`density` block →
  its wire was traced at exit → the handle dangles → next op `error()`s ("not
  live"). Strict-mode *early* detection of the escape (before the dangling use)
  is the D10 lost-binding detector — **inert in M3** (`_strict_check!`
  `regions.jl:83` fires only once `parent` edges exist, M6). M3's behaviour is
  fail-loud-on-use, which is sufficient and honest.
- **Views borrow (forward-looking):** M4's `dual(q)` will register no owned
  wire; its death traces nothing (§3.9). The M3 handle contract (`_owner`,
  `_wires`) is exactly what lets a view reach the owning context through its
  parent without owning a wire.

---

## 7. Deviations from the plan baseline (§M3)

1. **DM surface `Bool(q)` is deferred to M8, not delivered in M3.** The plan
   lists `Bool(q)` consuming under M3 without splitting Eager/DM; I argue a
   *scalar* outcome on a channel-executing context is the D3 token problem
   (§3.6/§4.4) and cannot be one-pass in M3 (no Orkan state-rescale for
   trajectory conditioning). M3 ships Eager `Bool` fully; DM `Bool` throws a
   descriptive `ArgumentError`. **Impact:** the plan's "Choi(cq∘qc) == pinching
   probed on a coherent input" is delivered as a **channel-level** one-pass DM
   test (via `_instrument!`) **plus** a statistical surface-composite Eager test;
   the fully-deterministic *surface* `Choi(QBool(Bool(q)))` on DM is an explicit
   **M8 IOU** (arrives with `@cases`/tokens). Flagged for the reviewer as the
   single most consequential M3 scoping call.

2. **No `Base.==` on `QBool`; the D1 pole law is state-level.** The plan quotes
   `QBool(1,φ) == QBool(true)`. I decline to overload `==` (dishonest after
   entanglement; non-hashable-consistent) and instead assert prepared **density
   matrices** are equal (exact, global-phase-free). Grounded in §4.3 + §4.5.

3. **`QBool` stores its owning `ctx`** (not a bare `WireID` + `current_context()`
   lookup). Beyond the plan's "typed wire-handle wrapper" wording; motivated by
   the per-context `WireID`-collision hole. Adds one abstract field (handles are
   not hot). This is the handle-pattern M4/M6 inherit.

4. **One small src-side addition beyond the plan's file list:** the internal
   `_instrument!` (pinch channel) in `density.jl` and the `_adopt_qbool` seam in
   `qbool.jl`, both required by the Choi harness. Neither is surface; both reuse
   existing M2 primitives (`_apply_channel_1q!`, the struct constructor).

5. **`src/surface/` is created in M3** (first appearance) for `casts.jl`;
   `_prep_u2` + constants sit in `types/qbool.jl`. Consistent with the plan's
   target tree.

Everything else — DomainError/never-Complex, `Float64(φ)`, `QBool(::Bool)`
dispatch, plus/minus/magic_T, single-sourced consumption, test-side `choi`,
15-wire cap, S13 taxonomy — matches the plan baseline.
