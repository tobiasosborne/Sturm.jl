# M3 Proposal A — QBool, the consuming casts, D1 literal, Choi harness

**Proposer A · bead Sturm.jl-77m2 · lens: BOUNDARY ALGEBRA FIRST**

Design target: `src/types/qbool.jl`, `src/surface/casts.jl`, `test/choi.jl`,
built on the landed M1 kernel (U2/∘/ctrl/constants) and M2 layer (WireID,
ContextCore, `allocate!`/`apply!`/`q`/`mark_consumed!`, regions, Eager/DM,
`density_matrix`/`statevector`). Grounded on PRD-v2 §3.1–3.2, §3.8, §3.9, §4.5,
D1 (§9), and the S13 error policy.

The governing idea of this proposal: **the two casts are the P2 boundary, and
everything downstream (M4 teleport, M5 `when`, M8 `cases`) is measured through
the Choi harness.** So the airtight items are (a) consumption single-sourced and
ordered against region exit, (b) the pinching law realized as a *channel* on DM
without sampling, and (c) a Choi harness that is deterministic in one DM run by
construction. Ergonomics and the literal follow.

---

## 0. The register-handle pattern (decision that M4/M6 inherit)

A surface register handle is **a typed wrapper over wire identity; the context is
implicit** (read from the `CURRENT_CONTEXT` ScopedValue at each surface entry).

```julia
struct QBool
    wire::WireID
end
```

**Why context-implicit, not a stored `ctx` field.** M2 deliberately made
`WireID` context-free and routed the single-argument `ptrace!(w::WireID)` through
`current_context()` (regions.jl:147). QBool follows that precedent exactly:
`Bool(q)` reads `current_context()`, and `q(ctx, w)` already fails loud on a wire
from another context (abstract.jl:133 — "not live in this context"), so
cross-context misuse is caught without a redundant back-reference. The v2
concurrency assumption is "one region, one task" (§3.9), under which the implicit
context is unambiguous. Storing a context pointer would (i) duplicate a source of
truth the consumed/liveness sets already own and (ii) bloat every handle and
every future view/slice.

**How this generalizes (so the pattern is decided once):**

| Milestone | Handle | Wraps | Owns? |
|---|---|---|---|
| M3 | `QBool` | one `WireID` | yes (region-registered) |
| M4 | `DualView`/`view(V,·)` | a parent handle + transform | **borrows** (§3.9) |
| M6 | `QInt{W}` | `NTuple{W,WireID}` (MSB-first) | yes |
| M6 | `x[i]` slice | parent id + wire index | borrows (D2) |

The consumed/aliasing bookkeeping keys on `WireID` for owned handles and on
`(parent wire, transform)` for views (§3.3, D2) — a Sturm-owned hook, never
Base's non-public `dataids`/`mightalias`. QBool establishes the owned case; M4
adds the borrowed case; nothing in M3 needs reworking.

An **internal re-wrap constructor** is required by the harness (and by M4/M6) to
wrap an *already-live* wire without preparing anything:

```julia
"""Internal: wrap an existing live wire as a QBool handle (NO preparation).
Used by the Choi harness and by M4 views/M6 slices. NOT the surface literal."""
_wrap_qbool(w::WireID) = QBool(w)
```

I keep this a named internal helper rather than a public `QBool(::WireID)` method,
so the surface literal surface stays exactly `{QBool(::Real[,::Real]), QBool(::Bool)}`
and a stray `WireID` can never be mistaken for a literal. `_wire(q::QBool) = q.wire`
is the one accessor.

**Not `<: Number` yet.** §3.1 calls registers "numeric types for dispatch (P9)",
but the P8 arithmetic overloads that would justify tower membership do not exist
until M6. Subtyping `Number` now, with no arithmetic, invites generic numeric
code to dispatch onto a QBool and misbehave silently — the opposite of fail-loud.
Per §3.3 ("generic numeric code handed [a view] MethodErrors honestly — the same
wall as `g(x::Int)`"), a bare struct MethodErrors honestly today; M6 promotes it
into the tower alongside the overloads that make membership meaningful.
**Deviation D-A-1** (documented below).

---

## 1. `src/types/qbool.jl` — the cq (preparation) cast

### 1.1 The exact preparation value (derived from |0⟩)

We prepare `√(1−p)|0⟩ + e^{iφ}√p|1⟩` on a fresh |0⟩ wire (allocation-is-
initialization, §3.9). Set the polar half-angle so the amplitudes are the real
square roots directly — this is what D1 means by "falls out of the real
`sqrt`/`asin` lowering": choose `θ/2 = asin(√p)`, i.e. `cos(θ/2)=√(1−p)`,
`sin(θ/2)=√p`, so the SU(2) magnitude value is literally

```
M(p) = U2(√(1−p), 0, √p, 0, φ=0)          # a unit quaternion: (1−p)+p = 1
```

(this is `Ry(2·asin(√p))` without ever calling `asin` — the amplitudes ARE the
quaternion components). Then add the relative phase with the kernel's `Rz`:

```
prep(p,φ) = Rz(φ) ∘ M(p)                   # kernel ∘ = matrix Rz·M, M applied first
```

**Verification (the required derivation, PRD rule 3).** With the pinned
convention `U(q)=[[w−iz,−y−ix],[y−ix,w+iz]]`, the Hamilton product
`Rz(φ)∘M(p)` has quaternion

```
q = ( √(1−p)·cos(φ/2),  −√p·sin(φ/2),  √p·cos(φ/2),  √(1−p)·sin(φ/2) ),  φ_g = 0
```

Applying `U(q)` to |0⟩ = `[1;0]` gives the first column `[w−iz ; y−ix]`:

```
a₀ = w − iz = √(1−p)(cos(φ/2) − i·sin(φ/2)) = √(1−p)·e^{−iφ/2}
a₁ = y − ix = √p (cos(φ/2) + i·sin(φ/2))    = √p·e^{+iφ/2}
```

So `|a₁|² = p` (Born), `a₁/a₀ = e^{iφ}` (relative phase φ), and the residual
`e^{−iφ/2}` is an unobservable **global** phase of a prepared *state* (a state's
global phase is not physical — this is preparation, not `Ad`, so §4.3's "phase
crossed once" is irrelevant here). ∎

**Why compose kernel values instead of hardcoding `q`.** `Rz(φ) ∘ M(p)` reuses
M1's tested Hamilton `∘` and its representation invariants; the explicit
quaternion above is the *witness* a unit test checks, not the code. The `prep`
value flows through the existing `apply!(ctx, ::U2, (w,))` fast path (ad.jl:335 —
it just fuses), so no new kernel emission code is added by M3.

### 1.2 The constructor

```julia
"""
    QBool(p::Real, φ::Real = 0.0) -> QBool

Preparation cast (cq). Allocate a fresh wire in |0⟩ and prepare
√(1−p)|0⟩ + e^{iφ}√p|1⟩ (Born prob p of `true`, relative phase φ).
`p ∉ [0,1]` throws `DomainError` (chart violation, never widened to Complex — D1).
PRD-v2 §3.2, D1 (§9).
"""
function QBool(p::Real, φ::Real = 0.0)
    (0.0 ≤ p ≤ 1.0) || throw(DomainError(p, "QBool: probability p must be in [0,1] (got $p); the (p,φ) chart never widens to Complex — see D1"))
    pf = Float64(p); φf = Float64(φ)        # Irrational (π) crosses to Float64 BEFORE any ccall (D1)
    ctx = current_context()
    w = allocate!(ctx)                      # |0⟩, registered in the enclosing region's owned set (§3.9)
    apply!(ctx, Rz(φf) ∘ U2(sqrt(1 - pf), 0.0, sqrt(pf), 0.0, 0.0), (w,))
    return QBool(w)
end
```

Notes:
- The explicit `0 ≤ p ≤ 1` guard precedes `sqrt`, so the DomainError message
  *names p* (fail-loud, rule 1) rather than surfacing `sqrt`'s opaque generic
  message. `NaN ≤ 1` is `false`, so NaN throws here too. (D1 observes DomainError
  "falls out of real sqrt for free"; the explicit guard is the better-message
  superset — same exception type, S13-compliant.)
- `Float64(φ)` and `Float64(p)` are taken *before* the kernel/ccall boundary, the
  D1 required test (`QBool` with an `Irrational` φ must not leak `π` to Orkan).
- φ is unrestricted (any real); only p is charted.

```julia
"""
    QBool(b::Bool) -> QBool

Definite-bit preparation. |0⟩ for `false`, |1⟩ for `true` (exact kernel X).
`Bool <: Integer <: Real`, so `QBool(true)` dispatches HERE, not the `(p,φ)`
method (more-specific wins — the D1 dispatch test).
"""
function QBool(b::Bool)
    ctx = current_context()
    w = allocate!(ctx)
    b && apply!(ctx, X, (w,))               # exact U(2) X (constants.jl); NOT Ry(π) — the §3.4 latent-phase fix
    return QBool(w)
end
```

`QBool(b::Bool)` uses the exact kernel `X` (not `Ry(π)`), pre-empting the v0.1
`qbool.jl:154` latent-phase bug that §3.4 names ("mixed forms must lower to the
kernel's exact X").

### 1.3 Pole degeneracy — operational meaning

`QBool(1, φ)` prepares `M(1) = U2(0,0,1,0,0)` then `Rz(φ)`: `M(1)|0⟩ = |1⟩`
(amplitude of |0⟩ is 0), and `Rz(φ)|1⟩ = e^{iφ/2}|1⟩` — a global phase. So the
**prepared state is |1⟩ for every φ**: φ is the relative phase between two
amplitudes, and at a pole one amplitude vanishes, making φ unobservable. Likewise
`QBool(0,φ)` ≡ |0⟩ ≡ `QBool(false)`.

This is a fact about *states*, made once (D1). It is **not** a fact about handles:
each `QBool(...)` call mints a distinct `WireID`, so `q1 == q2` on handles is
never true and never asked. The required test `QBool(1,φ)==QBool(1,φ′)==QBool(true)`
is therefore an **operational** equality — prepare each and compare the resulting
statevectors with `≈` (below, §4). QBool carries no stored φ; once prepared, the
wire holds the state and the literal's parameters are gone.

### 1.4 Named library constants (sugar on the constructor)

```julia
plus()    = QBool(0.5)          # (|0⟩+|1⟩)/√2   = |+⟩   ; prep = Ry(π/2)
minus()   = QBool(0.5, π)       # (|0⟩−|1⟩)/√2   = |−⟩   (up to global −i)
magic_T() = QBool(0.5, π/4)     # (|0⟩+e^{iπ/4}|1⟩)/√2 = |A⟩ (T magic state)
```

Exact prep quaternions (witnesses): `plus → (1/√2,0,1/√2,0,0)`;
`minus → (0,−1/√2,0,1/√2,0)`; `magic_T → (√.5·cospi(1/8), −√.5·sinpi(1/8),
√.5·cospi(1/8), √.5·sinpi(1/8), 0)`. These are Base's `im = Complex(false,true)`
pattern — thin names on the one constructor (D1). `magic_T` is the §3.7-entailed
phase-bearing literal (real stabilizer ops cannot manufacture `e^{iπ/4}`), the
reason the φ argument exists at all.

---

## 2. `src/surface/casts.jl` — the qc (measurement) cast, consumption, P2

### 2.1 `Bool(q)` — the consuming instrument

```julia
"""
    Bool(q::QBool) -> Bool

Measurement cast (qc). Measures `q` in the computational basis, CONSUMES the
handle (the register dies — a live quantum handle to now-classical data is a type
lie, §3.2), recycles the wire, and returns the outcome. Consumption is recorded
on the context's SINGLE-SOURCED consumed set (§4.5). Use-after-consume errors
with register identity.
"""
function Bool(q::QBool)
    ctx = current_context()
    w = _wire(q)
    _assert_live(ctx, w, "Bool")           # loud on use-after-consume / cross-context
    b = _measure_and_retire!(ctx, w)        # sample, collapse, reset slot to |0⟩, recycle, mark consumed
    return b
end
```

`_assert_live` (in casts.jl) checks liveness with a message naming the register:

```julia
function _assert_live(ctx, w::WireID, op::String)
    core = _core(ctx)
    if w in core.consumed
        error("$op: register $w already consumed (measured or traced) — a measurement cast dies at the boundary (§3.2/§4.5); you cannot read it again")
    elseif !haskey(core.wire_to_slot, w)
        error("$op: register $w is not live in this context (from another context, or already retired)")
    end
    nothing
end
```

This is `error()` (a guardrail with register identity), per S13. Double-consume
and use-after-consume are the *same* check firing on the consumed set — the
single-sourced set (§4.5) is what makes them one mechanism, not two drifting
flags (the v0.1 §8.5 desync, structurally excluded).

### 2.2 Measurement primitives (the one place Eager/DM diverge)

`Bool(q)` must return the OUTCOME (M2's `trace_wire!` discards it and re-draws —
reusing it would double-advance the RNG). So M3 factors a `_measure_and_retire!`
per context, sharing the retire bookkeeping:

```julia
# shared retire: delete the wire→slot entry, recycle the (already-|0⟩) slot, consume.
function _retire_wire!(ctx, w::WireID)
    core = _core(ctx)
    slot = core.wire_to_slot[w]
    delete!(core.wire_to_slot, w)
    _return_slot!(core, slot)               # slot is |0⟩ by the caller's reset (fresh=|e_G⟩ invariant)
    mark_consumed!(ctx, w)
    nothing
end
```

**Eager** (reuses M2's PURE primitives verbatim):

```julia
function _measure_and_retire!(ctx::EagerContext, w::WireID)
    core = _core(ctx)
    _flush_wire!(ctx, w)                     # pending 1q fusion → Orkan
    slot = core.wire_to_slot[w]
    p1 = _marginal_p1(core.state, slot)
    outcome = _draw(core) < p1 ? 1 : 0
    _collapse!(core.state, slot, outcome)    # projective collapse + renormalize
    outcome == 1 && _emit_x!(ctx, slot)      # reset slot to |0⟩ for recycling (measure-and-flip)
    _retire_wire!(ctx, w)
    return outcome == 1
end
```

**DM — the instrument story (the crux of my lens).** §3.8 is normative:
"DensityMatrixContext executes channels, not trajectories … one run yields the
*exact* channel." A standalone `Bool(q)` that returns a definite Julia `Bool`
*cannot* both return a definite value AND leave `ρ` holding both weighted
branches. I resolve the tension by **splitting the two claims cleanly** and I
justify it as the physically honest reading:

- **`Bool(q)` on DM is a trajectory unraveling**: sample the outcome from `ρ`'s
  Born diagonal via the context RNG, collapse `ρ` to that branch, consume. It
  returns a genuine `Bool`, so `if Bool(q)` works on DM exactly as the §3.8
  portability table promises (casts ✓ on DM; only *Tracing* turns the outcome
  into a token — D3). This is the "explicit shot API" the same paragraph
  reserves.
- **The one-run *deterministic* Choi** is a property of **channels**, delivered
  by (i) `cases` (M8, both branches block-accumulated) and (ii) measurement
  realized as an **instrument dilation** — CNOT-to-ancilla + exact `ptrace!`,
  both already in M2/M4 — which needs NO sampling. In M3, the pinching law is
  tested through path (ii) (§4.2 below), so it is one-run deterministic *without*
  a DM `Bool` that magically retains both branches, and *without* inventing a
  DM-side token (which D3 explicitly scopes to Tracing only).

Concretely, DM measurement needs one small readout addition (M2 built DM trace
and channels but no DM projective measurement):

```julia
# src/context/density.jl additions (M3):
"P(slot=1) from ρ's diagonal — the MIXED analogue of PURE _marginal_p1."
_diag_marginal_p1(ctx::DensityMatrixContext, slot::Int) = <sum of ρ[i,i] over basis i with bit `slot` set>

function _measure_and_retire!(ctx::DensityMatrixContext, w::WireID)
    core = _core(ctx); _flush_wire!(ctx, w); slot = core.wire_to_slot[w]
    p1 = _diag_marginal_p1(ctx, slot)
    outcome = _draw(core) < p1 ? 1 : 0
    # collapse: project onto |outcome⟩ then renormalize by 1/p — a 1-local channel
    _apply_channel_1q!(ctx, [_proj_kraus(outcome) ./ sqrt(outcome==1 ? p1 : 1-p1)], slot)
    outcome == 1 && _apply_channel_1q!(ctx, _RESET_KRAUS, slot)   # reset to |0⟩ for recycling
    _retire_wire!(ctx, w)
    return outcome == 1
end
```

(`_diag_marginal_p1` reads the diagonal — either through the existing
entrywise DM read used by `_density`, or a thin diagonal-only variant to avoid
materializing the full matrix. This is the *entire* M3 DM addition;
`_proj_kraus(b)` = `|b⟩⟨b|`.) **This is flagged for the reviewer: the
sampling-vs-channel split is a genuine design decision, and I have taken the
position that DM `Bool` is a trajectory while determinism comes from `cases`/
dilation — see Deviation D-A-2.**

### 2.3 The P2 implicit-cast warning — mapped onto Julia's own explicit/implicit line

Where do implicit casts arise in M3? **At `convert`.** Julia's own boundary
between *explicit* and *implicit* is precisely constructor-call vs `convert`: a
user typing `Bool(q)` is explicit intent; the runtime calling
`convert(Bool, q)` (assignment into a `Bool` slot, a `ccall` arg coercion, a
`Bool`-typed field/collection) is implicit. So the P2 rule maps exactly:

```julia
"""
    convert(::Type{Bool}, q::QBool) -> Bool

The IMPLICIT measurement cast. P2: implicit casts (with backaction — measurement
collapses) WARN, then measure. Explicit `Bool(q)` does not warn. §3.2/§3.9.
"""
function Base.convert(::Type{Bool}, q::QBool)
    @warn "implicit measurement of register $(_wire(q)): a QBool was coerced to Bool by the runtime (assignment/ccall/typed slot). This collapses the register (P2). Write `Bool(q)` to make the measurement explicit." _id=:sturm_implicit_cast
    return Bool(q)
end
```

This is the cleanest possible realization: no new machinery, and it is the
"static shadow of the runtime rule" §3.2 describes. The warning fires at
backaction sites only (§3.9's rule: *implicit ops with backaction warn; without
backaction — traces — are silent*; a QBool coerced to Bool has backaction, a
region-exit trace does not). I do **not** subtype `Number` in M3, so no *numeric*
promotion path can trigger an implicit cast yet; the `convert` route is the sole
M3 implicit site, and the P2 test targets it directly. (When M6 adds arithmetic
overloads, promotion becomes a second implicit site and routes through the same
warned `convert`.)

`@warn` (not `@info`, not a dedup by default) keeps the fail-loud spirit; an
optional `maxlog` can be added if a benchmark shows log spam, but the default is
loud.

---

## 3. `test/choi.jl` — the Choi harness (the measuring instrument for M4+)

**Placement: test-side** (`test/choi.jl`), per the plan. It is test tooling that
may use kernel values directly (H, `ctrl(X)`) — that is legitimate at the kernel
level; only *surface* code is gate-free.

### 3.1 Convention (pinned)

Choi matrix of a channel Φ on `m` qubits:

```
J(Φ) = (Φ ⊗ id)(|Ω⟩⟨Ω|),   |Ω⟩ = 2^{−m/2} Σ_{i∈{0,1}^m} |i⟩_sys |i⟩_ref
```

**Normalized** (trace-1 for TP maps). Then `J(id)` is the (normalized) maximally-
entangled projector `|Ω⟩⟨Ω|` (rank 1, off-diagonals present) and `J(pinching)` is
its complete dephasing (**diagonal**). Comparing these two catches the wm28 class,
which marginals cannot (a Z-error channel is invisible to Z-basis marginals).

### 3.2 Bell-pair preparation (kernel vocabulary — tests only)

Per input qubit i, allocate `(ref_i, sys_i)`, both |0⟩, and build
`(|00⟩+|11⟩)/√2`:

```julia
apply!(ctx, H, (ref_i,))              # H on the reference half
apply!(ctx, ctrl(X), (ref_i, sys_i))  # CNOT ref→sys  (ctrl is the kernel choke point)
```

`ctrl(X)` routes through the single controlled-lowering site (`_emit_cx!` in
ad.jl), so the harness inherits the M2-verified CNOT — no bespoke entangler.

### 3.3 The harness

```julia
"""
    choi(f, nin; cap = 2nin) -> Matrix{ComplexF64}

The (normalized) Choi matrix of the channel `f` on `nin` qubits, computed EXACTLY
in one DM run. Prepares `nin` Bell pairs (ref ⊗ sys, 2·nin wires), applies `f` to
the system halves (wrapped as QBool handles), and reads the reduced density
matrix over (output ⊗ ref). `f` may consume/trace/reallocate freely; its leftover
owned ancillae are traced at region exit (§3.9), returning their slots to |0⟩.

Cap: a W-wire channel needs 2W wires + f's peak ancillae ≤ 30 qubits (Orkan) ⇒
W ≤ 15 (PRD-v2 §3.8). Measurement-BRANCHING f is one-run-deterministic only once
`cases` exists (M8); measurement realized as instrument dilation is deterministic
now.
"""
function choi(f, nin::Int; cap::Int = 2nin)
    return density(cap) do ctx
        refs = [allocate!(ctx) for _ in 1:nin]
        syss = [allocate!(ctx) for _ in 1:nin]
        for i in 1:nin
            apply!(ctx, H, (refs[i],))
            apply!(ctx, ctrl(X), (refs[i], syss[i]))
        end
        outs = region() do                     # f runs in its own region: its owned ancillae trace here
            f((_wrap_qbool(w) for w in syss)...)   # pass system halves as QBool handles
        end
        out_wires = _wires_of(outs)            # the output handles f returned
        # reduced ρ over (out_wires ⊗ refs): all OTHER slots are |0⟩ (traced/recycled),
        # so the reduced matrix is the sub-block of the full ρ at those slots = 0.
        _reduce_to_slots(density_matrix(ctx), ctx, vcat(out_wires, refs), cap)
    end
end
```

`_reduce_to_slots(ρ, ctx, kept_wires, cap)` extracts the sub-matrix indexed by the
kept slots with **all other slots fixed to 0**. This is *exact*, not an
approximation, because M2 resets every traced/recycled slot to |0⟩ (the
"fresh = |0⟩" invariant, abstract.jl:99–101; density.jl reset channel): the full
ρ factorizes as `ρ_{kept} ⊗ |0…0⟩⟨0…0|_{rest}`, so the rest=0 block *is* the
reduced state. The helper also fixes the (output, ref) index ordering that pins
the Choi convention (one function owns bit-order — the §3.3 endianness discipline).

Single-input convenience: `choi(f) = choi(f, 1)`.

**Why one-run works for M3's tests.** The maps we Choi-test in M3 are
measurement-free (identity, X, prep-then-nothing) or the pinching channel realized
as dilation (CNOT+trace, §4.2) — all deterministic on DM. No shot averaging. The
harness is future-proof: once `cases` (M8) lands, measurement-branching channels
Choi-test in one run through the same `choi(f,nin)`.

---

## 4. Named law tests (`test/` — the §3.2 boundary algebra is the spine)

Each `@testset` is named after its PRD section (grep-able coverage map, plan §4).

### T1 — `qc ∘ cq = id` on classical data (§3.2): `Bool(QBool(b)) == b`
Deterministic (poles). For `b ∈ {false,true}`, seeded Eager and DM contexts:
`eager(1) do; Bool(QBool(b)) end == b`. Both outcomes, both contexts.

### T2 — pole degeneracy (D1): `QBool(1,φ) == QBool(1,φ′) == QBool(true)`
**Operational** state equality: prepare each in its own `eager(1)`, compare
`statevector` with `≈` (φ ∈ {0, π/3, π, 7.1}). Also `QBool(0,φ) ≈ QBool(false)`.
Assert handle identity is NOT used (`q1 == q2` on QBool is never invoked).

### T3 — dispatch (D1): `QBool(true)` hits the `Bool` method
`@test QBool(true)` prepares |1⟩ (statevector `≈ [0,1]`), and `QBool(1)` (Int) hits
the `(p,φ)` method preparing the same state — but via a different path;
`QBool(true)` must not go through `(p,φ)` (checked by a state `≈` plus a
method-instance assertion `which(QBool,(Bool,)) ≠ which(QBool,(Int,))`).

### T4 — Float64(φ) before ccall (D1)
`QBool(0.3, π)` (Irrational π) runs without error and matches
`QBool(0.3, Float64(π))` at the statevector level — the Irrational is converted at
the surface, never leaked to Orkan.

### T5 — DomainError (S13 chart violation): `QBool(1.5)`, `QBool(-0.1)`, `QBool(NaN)`
`@test_throws DomainError`. Assert the message names p (not the raw `sqrt` message)
and that NO widening to Complex occurred (the returned handle would be a `QBool`
over a real amplitude; here it throws before allocation).

### T6 — `cq ∘ qc = pinching`, probed on a COHERENT input (§3.2, §3.8; the wm28 point)
The headline test. Build the pinching channel as-a-channel (dilation) and Choi it:
```julia
pinch(q) = (o = _wrap_qbool(allocate!(current_context()));
            apply!(current_context(), ctrl(X), (_wire(q), _wire(o)));  # copy q's Z-value onto o
            ptrace!(_wire(q));                                          # trace input → dephasing
            o)
J = choi(pinch, 1)
@test J ≈ Diagonal(diag(J))                 # J is DIAGONAL  ⇔ pinching
@test !(J ≈ choi(identity_channel, 1))      # and NOT the identity Choi (rank-1, off-diagonals)
@test J ≈ (I(2)/2 ⊗ ... )  # explicit: diag(1/2,0,0,1/2) in the (out,ref) block, the dephasing Choi
```
The Choi input is the coherent Bell state, so pinching (diagonal Choi) is
distinguishable from identity — exactly the coherent-probe requirement (§3.8: "the
cq∘qc pinching test must probe a coherent input; pinching and identity coincide on
diagonal inputs"). **This is where marginals are blind and Choi is not** (the wm28
lesson made into the M3 acceptance gate).

Companion: **statistical convergence** — shot-averaged surface `q -> QBool(Bool(q))`
on seeded Eager over N ≥ 1000 shots, per basis-and-coherent input, converges to the
dephasing channel's statistics within ±3σ. This pins that the *surface* composite
(sampled) agrees with the *channel* (deterministic) realization.

### T7 — `qc ∘ cq = id` at Choi level (§3.2)
`choi(q -> QBool(Bool(q)), 1)` is NOT id — that's T6. The `qc∘cq=id`-at-Choi
statement is the *classical* channel: `choi(identity_channel,1) ≈ |Ω⟩⟨Ω|` and the
prepare-a-fixed-bit channel `choi(_ -> QBool(false), 1)` has the expected constant
Choi. (The genuine `qc∘cq=id` is T1 on classical data; at the channel level the
composite is pinching — the PRD is explicit that cq∘qc composes to decoherence, so
T6 IS the channel-level statement and T7 guards the identity/constant references.)

### T8 — error taxonomy policy (S13, one test)
- `@test_throws DomainError QBool(2.0)` (chart violation).
- `@test_throws ErrorException` on use-after-consume: `eager(1) do; q=QBool(0.5);
  Bool(q); Bool(q) end` — second `Bool(q)` errors, message contains the WireID.
- `@test_throws ErrorException` on double-path consume:
  `q=QBool(0.5); Bool(q); ptrace!(_wire(q))` — trace-after-consume errors on the
  single-sourced set.
- The message-content assertions verify register identity appears (guardrails
  carry identities). ArgumentError is documented as the M6+ slot (D2
  `dual(x)[i]`), asserted then; M3 has no well-formed-but-forbidden surface form,
  so the taxonomy test covers DomainError + `error()` and comments the
  ArgumentError arm as pending — honest, not padded.

### T9 — statistical prep frequencies (§4 policy, N≥1000, ±3σ, seeded)
For `p ∈ {0.1, 0.5, 0.9}`: N ≥ 1000 seeded `Bool(QBool(p))` draws; empirical
frequency of `true` within `p ± 3√(p(1−p)/N)`. Eager and DM (DM via its sampled
`Bool`). Seed fixed; **the test never asserts trace/RNG-stream placement** (§3.9
corollary — only frequencies, which are lowering-invariant).

### T10 — region interaction (§3.9)
- A `QBool(0.5)` allocated and neither consumed nor returned inside a `region()`
  is traced at exit: the slot is free and |0⟩ afterward (checked via `live_wires`
  count and a fresh-allocation landing on the recycled slot).
- `Bool(q)` before region exit: the wire is consumed, exit does NOT re-trace it
  (no double-draw — verified by seeded RNG-consumption count: exactly one draw).
- An entangled unconsumed local traces silently (mixes the survivor) — no warning
  (the §3.9 no-backaction silence; assert no `@warn` fired).

---

## 5. Namespace (the FIRST surface exports of the rebuild)

In `src/Sturm.jl`, after the M3 includes:

```julia
include("types/qbool.jl")
include("surface/casts.jl")

export QBool, plus, minus, magic_T        # surface (§3.2/§3.8 preparation cast + literals)
# Bool(q) is a Base.Bool METHOD — no new name, no export.
# convert(Bool, QBool) is a Base.convert method — no export.
```

- `QBool`, `plus`, `minus`, `magic_T` — **exported surface** (the preparation cast
  and its named literals, §3.2 "named library constants … are sugar on this
  constructor"; they yield QBool literals = pure surface vocabulary).
- `Bool(q)` / `convert` — Base method extensions, reachable by definition, not
  named exports.
- `choi` — **test tooling**, lives in `test/choi.jl`, `include`d by
  `test/runtests.jl`; never exported, never in `src/`.
- The M6 `Int(x::QInt)` cast joins `export`-nothing (Base.Int method) then.

Include order: `types/qbool.jl` before `surface/casts.jl` (casts dispatch on
QBool); both after the M2 context layer (they call `current_context`, `allocate!`,
`apply!`, `mark_consumed!`).

---

## 6. §3.9 region machinery interaction (ownership & ordering)

- **Allocation owns.** `QBool(p)` calls `allocate!`, which registers the wire in
  `region_stack[end]` (abstract.jl:123). So a QBool literal is *owned* by its
  enclosing region and traced at exit unless consumed or returned (§3.9 "exit:
  unconsumed owned locals are traced" — P1's closing parenthesis).
- **Consumption vs exit-trace ordering is conflict-free by the single-sourced
  set.** `Bool(q)` both deletes the wire from `wire_to_slot` AND `mark_consumed!`s
  it. `_exit_region!` traces a wire only if `haskey(wire_to_slot,w) && !(w in
  consumed)` (regions.jl:66) — both false after `Bool`, so it is skipped. There is
  no double-trace and no double-draw. Symmetric with `ptrace!` (which also marks
  consumed), so a QBool closed early by either cast is exit-safe.
- **Bool must NOT reuse `trace_wire!`.** `trace_wire!` draws its own outcome and
  discards it; `Bool` needs the outcome and must draw exactly once. Hence the
  separate `_measure_and_retire!` path (§2.2) that measures-then-retires, rather
  than routing through `_trace_and_free!`. This is the one place M3 must not "reuse
  the trace" — a subtle RNG-double-advance trap, called out for the implementer.
- **Views borrow (forward-compat, M4).** When `dual(q)` arrives, it registers no
  owned wire (borrows q's), so its death traces nothing (§3.9 "views borrow");
  `Bool(dual(q))` consumes the *parent* q on the same single-sourced set. QBool's
  owned-wire path and the future borrowed-view path share the consumed set — the
  pattern is fixed here.
- **Harness regioning.** `choi` runs `f` inside a nested `region()` so f's
  leftover owned ancillae trace back to |0⟩ before the reduced read — which is what
  makes `_reduce_to_slots` exact (rest slots guaranteed |0⟩). The refs/sys wires
  live in the outer `density(cap)` region and are torn down with the context.

---

## 7. Executive summary (10 lines) & deviations

1. QBool = typed wrapper over one `WireID`; **context implicit** via
   `current_context()` (the `ptrace!(w)` precedent), the pattern M4 views / M6
   `QInt{W}` inherit (owned vs borrowed keys the consumed/alias set).
2. Prep value `Rz(φ) ∘ U2(√(1−p),0,√p,0,0)` — derived from |0⟩, quaternion
   `(√(1−p)c_{φ/2}, −√p s_{φ/2}, √p c_{φ/2}, √(1−p)s_{φ/2}, 0)`, Born p, rel-phase
   φ, unobservable global phase; amplitudes ARE the real square roots (D1).
3. `p∉[0,1]` → explicit `DomainError` naming p (never widened to Complex);
   `Float64(p,φ)` before the ccall; `QBool(::Bool)` uses exact kernel `X`.
4. Pole degeneracy is operational state equality (|1⟩ ∀φ), tested by statevector
   `≈`, never by handle `==`; `plus/minus/magic_T` are sugar, `magic_T`=`|A⟩`.
5. `Bool(q)` consumes on the **single-sourced** consumed set; use/double-consume
   are one `error()` with register identity; ordered conflict-free against region
   exit (skipped when consumed — no double-trace, no double-draw).
6. **P2 implicit warning = `Base.convert(Bool,QBool)`** (`@warn` then measure);
   explicit `Bool(q)` is silent — maps onto Julia's own constructor-vs-`convert`
   line; sole M3 implicit site (no `Number` subtype yet).
7. **Instrument story on DM (my lens):** DM `Bool` is a trajectory sample
   (`if Bool(q)` ✓ per §3.8); one-run determinism comes from `cases` (M8) and from
   measurement-as-**dilation** (CNOT+trace) — no DM token invented (D3 keeps
   tokens Tracing-only).
8. Choi harness (`test/choi.jl`, normalized `J=(Φ⊗id)|Ω⟩⟨Ω|`): Bell pairs via
   kernel `H`,`ctrl(X)`; reduced read is **exact** via the fresh=|0⟩ invariant
   (rest-slots-0 sub-block); 2W≤30 ⇒ W≤15.
9. Headline test T6: pinching realized as dilation, `choi(pinch,1)` **diagonal**
   and ≠ identity Choi on the **coherent** Bell probe — the wm28 lesson as the M3
   gate; plus qc∘cq=id (T1), taxonomy (T8), N≥1000 ±3σ frequencies (T9).
10. Exports (first of the rebuild): `QBool, plus, minus, magic_T`; `Bool`/`convert`
    are Base methods; `choi` is test-only.

**Deviations from the plan baseline (Sturm-v2-IMPLEMENTATION-PLAN §M3):**

- **D-A-1 — QBool is NOT `<: Number` in M3.** The plan/§3.1 call registers
  "numeric types"; I defer numeric-tower membership to M6 (when P8 arithmetic
  overloads exist), so today generic numeric code MethodErrors honestly (§3.3's
  own "same wall as `g(x::Int)`") rather than dispatching onto an arithmetic-less
  register. Reviewer call.
- **D-A-2 — DM `Bool(q)` is a trajectory sample, not a both-branches channel.**
  The plan says "DM executes channels ⇒ Choi deterministic in one pass." I keep
  that property for `cases`-built and dilation-realized channels, but make
  *standalone* `Bool` a sampled unraveling (so `if Bool(q)` works on DM per the
  §3.8 table) and realize M3's pinching Choi via CNOT+trace dilation instead of
  executing `QBool(Bool(q))` per-shot. This needs one small DM readout addition
  (`_diag_marginal_p1` + projector-collapse channel), not a DM token. This is the
  substantive decision I flag for the 3+1 round.
- **D-A-3 — the pinching test is built as a dilation channel** (`pinch(q)` =
  CNOT-to-ancilla + `ptrace!(input)`), not as literal surface `QBool(Bool(q))`,
  to get one-run determinism in M3 before `cases`. The surface composite is
  covered by the ±3σ statistical companion. Consequence of D-A-2.
- **Minor:** M3 adds a factored `_measure_and_retire!` (Eager reuses M2 PURE
  primitives; DM gets the small readout addition) rather than reusing
  `trace_wire!` — required to avoid an RNG double-advance (Bool needs the outcome;
  trace discards+redraws). Plan-neutral but worth the reviewer's eye.
