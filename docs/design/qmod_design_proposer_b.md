# QMod{d} Design — Proposer B

## 0. Summary (3–5 lines)

`QMod{d}` is a single d-level quantum register, carried by a qubit-encoded
fallback (each `QMod{d}` is `W = ⌈log₂ d⌉` contiguous underlying wires). The
type parameter `d::Int` is the sole piece of dimension information; the
context stays dimension-agnostic at the wire level (`apply_cx!` etc. still
operate on `WireID`s). For non-power-of-two `d`, leakage into unused levels
`{d, …, 2^W − 1}` is prevented by a **construction-side invariant**
(primitives/entanglers must preserve the subspace) plus an
EagerContext-only **debug-mode assertion** at every `Int(::QMod{d})` / SUM
/ `ptrace!` boundary. No per-gate projection. Rule 11 is preserved: at
`d=2`, `W=1`, `QMod{2}` is *layout-isomorphic* to `QBool` (same single-wire
storage, same ccalls on primitives 2/3/6).

## 1. Wire layout — Q1 answer

### Choice

**Option B, with a hidden width witness `W` to satisfy Julia's struct
arithmetic rules** (same trick `QCoset{W, Cpad, Wtot}` uses at
`src/types/qcoset.jl:45` — Julia cannot compute `W = ⌈log₂ d⌉` inside
field annotations, so `W` is plumbed as a second type parameter whose
value is enforced by the constructor):

```
mutable struct QMod{d, W} <: Quantum
    wires::NTuple{W, WireID}
    ctx::AbstractContext
    consumed::Bool
end
```

User-facing API writes `QMod{d}` (one parameter). The constructor is
the only thing that mentions `W`:

```
QMod{d}(ctx::AbstractContext) where {d} = begin
    d >= 2 || error("QMod{d}: d must be ≥ 2, got $d")
    W = _qmod_width(d)           # ⌈log₂ d⌉
    QMod{d, W}(ntuple(_ -> allocate!(ctx), Val(W)), ctx, false)
end
```

where `@inline _qmod_width(d::Int) = d <= 1 ? 1 : (64 - leading_zeros(d - 1))`.
The `NTuple{W, WireID}` field is concretely typed via `Val(W)` —
same pattern `QInt{W}(ctx, value)` uses at `src/types/qint.jl:65–71`.
Users never spell `QMod{3, 2}` — the type is normally constructed and
matched on `QMod{d}` via `where {d}` dispatch (Julia treats unbound
tail parameters as wildcards).

### Rationale

1. **Rule 11 at d=2**. `d=2` → `W=1`, so `QMod{2}` stores one `WireID`
   — same layout as `QBool` (`src/types/qbool.jl:7–11`). `q.θ += δ` on
   `QMod{2}` is a bare `apply_ry!` on `wires[1]`: bit-identical to
   qubit dispatch. The "primitives 4+5 collapse at d=2" clause from
   `qudit_magic_gate_survey.md` §8.1 falls out mechanically.

2. **Rule 5 (literate)**: `NTuple{W, WireID}` self-documents the
   qubit-encoded fallback (`qudit_magic_gate_survey.md` §8.8). No
   context-side dim map to consult.

3. **P5 (no qubits in user code)**: `wires` is non-exported plumbing.
   User-facing surface is `QMod{d}(ctx)`, `Int(q)`, `q.θ += δ`, `q ⊻=
   r` — parallel to `QBool`. Library authors see the group like
   `QInt{W}.wires` at `src/types/qint.jl:14–18`.

4. **Context stays dim-unaware**. `AbstractContext`'s wire-keyed API
   (`src/context/abstract.jl:34–56`) needs no change. Each wire is
   "just a qubit" to `EagerContext.wire_to_qubit`
   (`src/context/eager.jl:15`). No `wire_dims` dict, no dispatch on
   `d` at gate-apply level. Options A and C lose this.

5. **Forward-compat with QInt{W,d}** (bead `dj3`). `QInt{W_digit, d}`
   is naturally `W_digit` `QMod{d}` digits — aggregates the existing
   `NTuple{W, WireID}` groups. Option A would force per-digit dim-map
   coordination with every backend.

### Rejected alternatives

- **Option A** (one WireID + `ctx.wire_dims::Dict{WireID, Int}`):
  `WireID` is a pure-value handle (`src/types/wire.jl:7–9`); forcing
  every context (EagerContext, DensityMatrixContext, TracingContext,
  HardwareContext) to carry a side-map is leaky. Backend has to know
  d whenever QMod is used — violates "Julia owns the type system".
- **Option C** (WireID + `dims::Int` on struct, WireID is secretly a
  group): type-lies. `apply_cx!(ctx, qmod_wire, other)` has no clean
  semantics.
- **Option D** (Int basis index + qudit-layer context): needs native
  d-level Orkan; ruled out by `qudit_magic_gate_survey.md` §8.8.

### Forward-compat with QInt{W,d} (bead dj3)

```
mutable struct QInt{W_digit, d} <: Quantum
    digits::NTuple{W_digit, QMod{d}}
    # ... or equivalently a flattened NTuple{W_digit*_qmod_width(d), WireID}
end
```

Either way, every mod-d arithmetic operation (bead `Sturm.jl-p38` SUM,
mulmod, adder) sees a clean `QMod{d}` per digit. No context negotiation.

## 2. Context integration — Q2 answer

### Choice

**Compile-time `d` via the type parameter; no context-side dim map.**

Each `QMod{d}`-aware primitive is a new method set on `AbstractContext`
parameterised by `d`. For this bead, the only primitive is the prep
(`QMod{d}(ctx)`), which is implemented entirely as `W` calls to
`allocate!(ctx)` — no new context method is needed at all. The other
5 primitives (`q.θ`, `q.φ`, `q.θ₂`, `q.θ₃`, `⊻=`) are introduced in
follow-on beads (`ak2`, `os4`, `mle`, `p38`) and will add their own
`apply_qmod_*!` methods there. This bead lays only the plumbing.

### API surface (this bead only)

The prep path uses existing `AbstractContext` methods — specifically
`allocate!(ctx)` from `src/context/abstract.jl:12`. No new method on
`AbstractContext` is added in this bead. Zero-initialisation of the
d-level ground state `|0⟩_d` is free: Orkan allocates fresh wires in
|0⟩ (qubit-zero), and the qubit basis state `|0…0⟩` *is* the d-level
`|0⟩_d` by encoding convention — independent of whether `d` is a power
of two.

The `classical_compile_kwargs` trait and `classical_type` trait (on
`Quantum` subtypes at `src/types/quantum.jl:17–37`) are extended for
`QMod{d}`. See §5.

### Mixed-d error detection (where SUM lives, bead p38)

Bead `p38` will define `Base.xor(a::QMod{d}, b::QMod{d}) where {d}` —
the only legal dispatch. `QMod{3}(…) ⊻= QMod{5}(…)` then MethodErrors
from Julia's dispatch machinery (Rule 1: fail loud). This requires `d`
at the type level, which Choice 1 provides. This bead ships a
structural test (§6 Testset 6) asserting no `xor(::QMod{d1},
::QMod{d2}) where {d1,d2}` catch-all exists.

### P8 promotion (bead p38 concern, filed here)

`_promote_to_qmod(ctx, v, ::Val{d})` mirrors `_promote_to_qint` at
`src/types/qint.jl:84–86`. Belongs in bead `p38` with the arithmetic
operators. Flagged as a dependency.

## 3. Prep primitive — Q3 answer

### QMod{d}(ctx) signature

```
QMod{d}(ctx::AbstractContext) where {d}
QMod{d}() where {d} = QMod{d}(current_context())
```

Mirrors `QBool(ctx::AbstractContext, p::Real)` at
`src/types/qbool.jl:183–191` and `QBool(p::Real)` at
`src/types/qbool.jl:198`. **No amplitude argument** (locked decision,
`qudit_magic_gate_survey.md` §8.1 — prep is always `|0⟩_d`). A user
who wants a superposition writes `q = QMod{d}(); q.θ += δ` or
`q.θ₂ += δ` using primitives 2/4, once those exist.

### Allocation pattern

See constructor pseudocode under §1 "Choice". W calls to `allocate!(ctx)`,
minus the X-gate branch `QInt{W}(ctx, value)` uses for classical-value
prep at `src/types/qint.jl:65–71` (we always prep `|0⟩_d`). `Val(W)`
ensures `ntuple` unrolls.

**Reuse vs new `allocate_group!(ctx, n)`** (Rule 13): there is an
existing `allocate_batch!(ctx, n)::Vector{WireID}` at
`src/context/abstract.jl:22–24`, but it returns a `Vector` (heap
allocation). For `QMod{d}` we want a stack-allocated `NTuple`, and
`QInt{W}` has already established the `ntuple(_ -> allocate!(ctx),
Val(W))` idiom (`src/types/qint.jl:65`). Use that; do **not** add a
new `allocate_group!`. The existing API is already sufficient.

### Leakage guard strategy (d not a power of two)

**Problem**. At `d=3`, `W=2`, `|11⟩_qubit` (binary 3) is outside the
logical subspace `span{|0⟩_d, |1⟩_d, |2⟩_d}`.

**Chosen strategy**: construction invariant + debug-mode boundary
assertion + **unconditional post-measurement value check**.

1. **Construction invariant (per-primitive proof obligation).** Each
   follow-on bead (`ak2`, `os4`, `mle`, `p38`) must docstring + test
   that its action preserves `span{|0⟩_d, …, |d−1⟩_d}`:
   - `q.θ += δ`: spin-j `R_y(δ)` on the (2j+1)-dim irrep
     (`d = 2j+1`) — subspace-preserving by construction.
   - SUM: `|a⟩|b⟩ → |a⟩|(a+b) mod d⟩` — modular arithmetic in `Z/dZ`
     keeps outputs in `{0,…,d−1}`.
   - Prep: all wires `|0⟩_qubit`, and `|0…0⟩ = |0⟩_d` always valid.
   Discipline already demanded by CLAUDE.md Rule 3.

2. **Debug-mode boundary assertion (EagerContext only, opt-in).** A
   task-local flag `:sturm_qmod_check_leakage` (default `false`) gates
   a full-subspace sweep at `Int(::QMod{d})` / `ptrace!(::QMod{d})` /
   post-SUM. Sum `|amp|²` over qubit-basis indices whose W-bit
   pattern decodes to `≥ d`; tolerance `1e-12`, `error()` on
   violation. Uses the `unsafe_wrap` trick at
   `src/context/eager.jl:230` — zero FFI crossings, one O(2^n) pass.

3. **Unconditional post-measurement value check**. `Int(::QMod{d})`
   errors if the decoded classical result ≥ d (see §4). O(1).

4. **Rejected: per-gate projection.** Changes channel semantics, not
   hardware-implementable, O(2^n) per gate. Construction invariant +
   boundary check is the same correctness at O(1)/gate + O(2^n)/measure.

5. **Rejected: static-only.** Rule 1 demands a cheap runtime net when
   available.

## 4. Measurement / P2 cast — Q4 answer

### Cast target type(s)

**`Int` only for v0.1.** `Base.Int(q::QMod{d})` returns an `Int` in
`[0, d)`, paralleling `Base.Int(q::QInt{W})` at
`src/types/qint.jl:108–119`. No `Mod{d}` target:
- Mods.jl dep violates CLAUDE.md §Julia Conventions #4.
- `mod(Int(q), d)` is the trivial wrap, already in-range by §3
  leakage-guard invariants.
- Non-breaking to add later (see §8.1).

### Implicit warning

Same P2 discipline as `QBool` and `QInt{W}`
(`src/types/quantum.jl:39–103`):

```
Base.convert(::Type{Int}, q::QMod{d}) where {d} = begin
    _warn_implicit_cast(QMod{d}, Int)
    return Int(q)
end
```

The `_warn_implicit_cast` helper is already dedup-per-(file,line) and
already escape-hatched via `with_silent_casts`. No new infrastructure
needed — just register the new type pair.

### Measurement mechanics & leakage at measurement time

Pseudocode:
```
function Base.Int(q::QMod{d}) where {d}
    check_live!(q); W = _qmod_width(d); result = 0
    for i in 1:W
        _blessed_measure!(q.ctx, q.wires[i]) && (result |= 1 << (i-1))
    end
    q.consumed = true
    result >= d && error("QMod{$d} leakage: measured $result ≥ $d")
    return result
end
```
The `result >= d` check is unconditional (O(1), classical-side). Rule 1:
returning a garbage value would silently corrupt `powermod(a, k, N)`-
style downstream. `_blessed_measure!` is at
`src/types/quantum.jl:192–200` — same blessed path `QBool`/`QInt` use,
suppressing the `_warn_direct_measure` antipattern warning.

## 5. P9 / Bennett — Q5 answer

### classical_type

```
classical_type(::Type{<:QMod{d}}) where {d} = begin
    d <= (1 << 8)  ? Int8 :
    d <= (1 << 16) ? Int16 :
    d <= (1 << 32) ? Int32 :
                     Int64
end
classical_compile_kwargs(::Type{<:QMod{d}}) where {d} =
    (bit_width = _qmod_width(d), dim = d)
```

Reasoning: `QInt{W}` uses `Int8` + `bit_width=W`
(`src/types/qint.jl:20–21`). `QMod{d}` follows the same family and
adds a `dim = d` kwarg signalling "arithmetic is mod d, not mod 2^W".
`classical_type` steps up to Int16/Int32/Int64 past d=256/2^16/2^32 to
avoid overflow in `f`'s body under natural Julia promotion.

### Modular arithmetic gap (honest flag)

**Bennett.jl today does not support mod-by-non-power-of-2 arithmetic.**
`src/bennett/bridge.jl:212` emits `reversible_compile(f, arg_type;
bit_width=W, …)`. Arithmetic on that register is inherently `mod 2^W`;
no `dim`/`modulus` kwarg exists.
- `QMod{2^k}`: `bit_width=k` is mod-2^k is mod-d. Oracle path works.
- `QMod{d}` with non-power-of-two d: **gap**. `oracle(x -> x+1,
  q::QMod{3})` would give mod 4, not mod 3 — a real bug.

**Disposition for this bead**: emit the traits (forward-proof), and
add a loud boundary check in an `oracle(f, q::QMod{d})` stub:
`ispow2(d) || error("…requires power-of-two d; track bead
Sturm.jl-<new>")`. File non-power-of-two support as a new Bennett-side
bead (naming at orchestrator discretion). `dim = d` in
`classical_compile_kwargs` is inert plumbing today; unlocks the path
once Bennett learns `dim`.

## 6. Test sketch — Q6 answer

File: `test/test_qmod.jl`, included from `test/runtests.jl`.

### Testset 1: `QMod{d}` construction, type, liveness

```
@testset "QMod construction" begin
    @context EagerContext() begin
        q3 = QMod{3}()
        @test q3 isa QMod{3}
        @test q3 isa Quantum
        @test !q3.consumed
        @test length(q3.wires) == 2             # W = ⌈log₂ 3⌉
        ptrace!(q3)
        @test q3.consumed
    end
end
```

### Testset 2: prep is |0⟩_d for d=3, d=5

```
@testset "QMod prep is |0⟩_d" begin
    @context EagerContext() begin
        for d in (2, 3, 4, 5, 7, 8)
            @eval q = QMod{$d}()
            @test Int(q) == 0
        end
    end
end
```

### Testset 3: power-of-two d (d=4 in 2 qubits, d=8 in 3 qubits, no leakage)

```
@testset "QMod power-of-two d, no forbidden levels" begin
    @context EagerContext() begin
        q4 = QMod{4}()
        @test length(q4.wires) == 2
        @test Int(q4) == 0
        q8 = QMod{8}()
        @test length(q8.wires) == 3
        @test Int(q8) == 0
    end
end
```

### Testset 4: non-power-of-two d, leakage guard active at measurement

```
@testset "QMod{3} measurement leakage guard" begin
    @context EagerContext() begin
        q = QMod{3}()
        # Manually populate |11⟩_qubit via raw wire gates — simulates
        # a buggy primitive. This is intentional misuse of internals.
        ctx = current_context()
        apply_ry!(ctx, q.wires[1], π)     # wires[1] = |1⟩
        apply_ry!(ctx, q.wires[2], π)     # wires[2] = |1⟩
        # Now state is |11⟩_qubit = forbidden level 3 for QMod{3}
        @test_throws ErrorException Int(q)
    end
end
```

### Testset 5: Backwards-compat — QBool and QInt tests unchanged

```
@testset "QBool / QInt backwards compat" begin
    # Sanity re-run of the Bell pair + GHZ cases that predate QMod.
    include("test_bell.jl")
    include("test_qint.jl")
end
```

(In practice, `runtests.jl` already includes these; this testset is a
comment/placeholder asserting that the top-level test dispatch order
does not depend on `test_qmod.jl` side effects.)

### Testset 6: Mixed-d SUM dispatch is absent (structural guard)

```
@testset "QMod mixed-d SUM is not silently defined" begin
    # Bead p38 adds Base.xor(::QMod{d}, ::QMod{d}) where {d}. This test
    # protects against a later agent accidentally shipping a wider
    # catch-all. Lives in this bead as a placeholder structural test.
    ms = collect(methods(Base.xor))
    has_mixed = any(m -> begin
        sig = m.sig
        sig isa UnionAll || return false
        try
            Tuple{QMod{3}, QMod{5}} <: sig.body
        catch
            false
        end
    end, ms)
    @test !has_mixed
end
```

### Testset 7: `ptrace!(::QMod{d})` frees all W wires

```
@testset "QMod ptrace! cleanup" begin
    @context EagerContext() begin
        ctx = current_context()
        n_before = length(live_wires(ctx))
        q = QMod{3}()                         # allocates 2 wires
        @test length(live_wires(ctx)) == n_before + 2
        ptrace!(q)
        @test length(live_wires(ctx)) == n_before
    end
end
```

### Testset 8: TLS context capture

```
@testset "QMod{d}() pulls context from TLS" begin
    ctx = EagerContext()
    @context ctx begin
        q = QMod{4}()                        # no explicit ctx arg
        @test q.ctx === ctx
        ptrace!(q)
    end
end
```

### Testset 9: Explicit vs implicit cast (P2 warning contract)

```
@testset "QMod P2 implicit-cast warning" begin
    @context EagerContext() begin
        q = QMod{3}()
        # Explicit Int(q) is silent.
        # convert(Int, q) warns once (dedup by file:line).
        @test_logs (:warn, r"Implicit quantum→classical cast") begin
            q2 = QMod{3}()
            x::Int = q2
        end
    end
end
```

### Testset 10: Construction validation errors

```
@testset "QMod validation errors" begin
    @context EagerContext() begin
        @test_throws ErrorException QMod{1}()     # d < 2
        @test_throws ErrorException QMod{0}()
        # d is a type parameter so non-Int d is rejected by Julia’s
        # type system — no runtime check needed.
    end
end
```

## 7. Files to touch

### New: `src/types/qmod.jl` (~140–170 lines)

- `struct QMod{d} <: Quantum` + field declarations.
- `_qmod_width(d)` helper.
- `classical_type`, `classical_compile_kwargs` trait methods.
- `check_live!`, `consume!`, `ptrace!`.
- `QMod{d}(ctx::AbstractContext)` + `QMod{d}()` constructors.
- `Base.Int(q::QMod{d})` + `Base.convert(::Type{Int}, q::QMod{d})`.
- Leakage guard helper `_qmod_check_leakage_if_debug(ctx, wires, d)`
  (EagerContext-only implementation lives here; dispatches on
  `ctx::EagerContext`, no-op on other contexts for v0.1).
- Bennett oracle boundary guard (non-power-of-two error path).
- NO primitives 2–6. NO SUM. NO library gates.

### Edit: `src/types/quantum.jl`

- Line 5: update the "future QDit{D}" comment to "QMod{d} (implemented
  in qmod.jl), future QField{…}, anyonic registers" — the type is no
  longer aspirational.

### Edit: `src/context/eager.jl`

- No change. The Option B wire layout (Choice 1 above) means
  EagerContext stays dim-unaware. The leakage-guard debug helper
  lives in `qmod.jl`, not in `eager.jl`, because it is a
  QMod-semantic concern, not a context-semantic one. (If a future
  bead demands a dim-map on EagerContext — e.g. to support Orkan-
  native d-level — that edit happens then, not now. YAGNI.)

### Edit: `src/Sturm.jl`

- Line 14 area: `include("types/qmod.jl")` after `types/qbool.jl`
  and `types/qint.jl` (QMod has no cross-deps on qcoset/qrunway, but
  should appear before any library code that might want to use it;
  before `gates.jl`).
- Line 102 area: `export QMod` in the Types export block.

### New: `test/test_qmod.jl`

- 10 testsets as sketched in §6. Imports `Sturm`, `Test`, and
  `Sturm: _qmod_width` for the width-helper tests.

### Edit: `test/runtests.jl`

- Add `include("test_qmod.jl")` in the appropriate alphabetical
  position.

## 8. Open questions / risks

### Q8.1 — `Int` vs `Mod{d}` cast target
Ship `Int` only; Mods.jl dep would violate CLAUDE.md §Julia Conventions
#4. Non-breaking to add later. Revisit if qudit arithmetic library
noise from `mod(Int(q), d)` wrappers becomes painful.

### Q8.2 — Leakage guard opt-in vs default-on
Default-off (`:sturm_qmod_check_leakage = false`). Alternative: on
when `n_qubits ≤ 20`. Tradeoff: per-measurement O(2^n) sweep (~1 ms
at 20q) is per-cast, visible in tight loops. Recommendation:
default-off for v0.1; reconsider after `os4`/`mle` land and real
leakage bugs surface. **Least-confident decision — orchestrator call.**

### Q8.3 — `d` at type level: Int vs Val{d}
Propose raw `QMod{d}` (d::Int). Julia specialises correctly; matches
`QInt{W}` at `src/types/qint.jl:14`. Risk: compile-time specialisation
cost if a user instantiates many distinct `d`. v0.1 expected usage is
1–3 values per program — fine. Runtime-`dim::Int` refactor is a later
option, not a now-decision.

### Q8.4 — Fallback vs Orkan-native d-level
Future Orkan-native backend slots in *inside* the context's
`apply_ry!`, not at the QMod level. No risk for this bead; noted for
`os4`/`mle` implementers.

### Q8.5 — Cross-context interop
Same pattern as `QBool.xor` at `src/types/qbool.jl:137` — `a.ctx === b.ctx`
assertion lives in bead `p38`, not here. `QMod{d}(ctx)` trivially
stores ctx. No risk.

### Q8.6 — QInt{W,d} parameter-order tension (bead dj3)
`QInt{W, d}` needs `d=2` default for backcompat. Recommendation when
`dj3` lands: `const QInt{W} = QIntBase{W, 2}`. Not this bead's
problem, but flagged.

## 9. Confirmation

Design document written to `/tmp/qmod_design_B.md`. No source code
touched.
