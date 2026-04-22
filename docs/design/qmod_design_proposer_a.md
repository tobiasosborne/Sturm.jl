# QMod{d} Design — Proposer A

## 0. Summary

This bead (`Sturm.jl-9aa`) adds a single new user-facing quantum register type,
`QMod{d} <: Quantum`, plus the preparation primitive `QMod{d}(ctx)` / `QMod{d}()`.
Scope is type + context wiring + prep only — no rotations, no SUM, no library
gates. Storage is qubit-encoded (⌈log₂ d⌉ qubits per wire) because Orkan is
qubit-only (`docs/physics/qudit_magic_gate_survey.md` §8.8). I recommend wire
layout **(B): `QMod{d}` holds an `NTuple{K, WireID}` where `K = ⌈log₂ d⌉`** —
mirrors `QInt{W}` exactly, keeps the context dim-agnostic, and makes the
forward port to `QInt{W,d}` a mechanical rename. Leakage (d not a power of 2)
is handled by a **post-prep assertion in simulator/eager paths only**, cheap,
and a dedicated `_leakage_guard!` hook the later primitive beads can invoke
after gate application.

## 1. Wire layout — Q1 answer

### Choice: (B) `NTuple{K, WireID}`

```
mutable struct QMod{d} <: Quantum
    wires::NTuple{K, WireID}    # K = ⌈log₂ d⌉; invariant asserted in inner ctor
    ctx::AbstractContext
    consumed::Bool
end
```

Binary encoding of the computational label k ∈ {0, …, d−1}: `wires[1]` is the
LSB of the binary representation of k, `wires[K]` the MSB. This is the
identical little-endian ordering used by `QInt{W}` (`src/types/qint.jl:4-5`),
so a d=2^W `QMod{d}` and a `QInt{W}` have bit-compatible layouts — the later
`QInt{W,d}` bead (`Sturm.jl-dj3`) can alias or reinterpret at the type level
instead of re-deriving the encoding.

### Rationale

- **Rule 5 (literate) + Rule 14/P5 (no qubits in user code):** `d` is the
  user-facing semantic parameter — the PRD §8.1 qudit primitives are defined
  over `|k⟩`, k ∈ {0, …, d−1}, not over underlying qubits. `d` belongs in the
  type signature. The NTuple is an implementation detail (same status as
  `QInt{W}.wires::NTuple{W, WireID}` at `src/types/qint.jl:14-18` — users never
  see it).
- **Rule 11 (4 primitives at d=2):** at d=2, K=1 and the NTuple degenerates to
  a single wire. `QMod{2}` is isomorphic to `QBool` at the physical layer but
  distinct at the type layer — exactly the `Bool` vs `Mod{2}` split the survey
  notes (§8.5 bullet 1). No existing qubit code is touched.
- **Context stays dim-unaware.** Every gate call still takes a `WireID` and
  hits the existing `apply_ry!` / `apply_rz!` / `apply_cx!` path
  (`src/context/abstract.jl:33-46`). The d-level semantics live in the type
  + the soon-to-come primitive implementations, not in the backend.
- **K as a derived compile-time quantity.** Julia does not allow expressions
  like `QMod{d} where {d}` to contain `K = ceil(Int, log2(d))` in the struct
  definition itself (it would need to be a second parameter). Two options
  resolve this:
  - (B1) Add a second type parameter: `QMod{d, K} <: Quantum`, asserting
    `K == _qmod_nbits(d)` in the inner constructor. Matches `QCoset{W, Cpad,
    Wtot}` exactly (`src/types/qcoset.jl:45-50` — Wtot is a derived parameter
    present only because Julia cannot do `W + Cpad` in field types).
  - (B2) Use an abstract-typed field `wires::NTuple{N, WireID} where N`. Slower
    dispatch; violates the "width in the type parameter" discipline of
    `QInt{W}` (quantum.jl:14).
  - **Pick B1.** `QMod{d, K}` with inner constructor asserting derived K. User
    writes `QMod{3}` — we provide a convenience `QMod{d}(...)` outer
    constructor that computes K and delegates to the K-annotated inner ctor.
- **Forward-compat with QInt{W, d} (bead dj3):**
  ```
  mutable struct QInt{W, d} <: Quantum
      digits::NTuple{W, QMod{d, K}}   # W digits, each d-level
      # or equivalently NTuple{W*K, WireID}
  end
  ```
  W-digit base-d integer. At `d=2`, `QInt{W, 2}` collapses to existing
  `QInt{W}` layout (`W*1 = W` wires). The NTuple-of-QMod vs flat-NTuple is a
  later call; what matters here is that the building block — `QMod{d}` as a
  contiguous K-wire bundle — already matches.

### Why not (A) / (C)

- (A) "context carries a wire → dim map": forces every context implementation
  (Eager, Density, Tracing, Hardware — grep shows four) to add a new field and
  keep it in sync. Breaks the Rule 13 discipline "check what already exists
  first": `WireID → Int` qubit-mapping dicts already exist
  (`src/context/eager.jl:14`, `src/context/density.jl:15`), and adding a
  parallel `WireID → d` map is redundant with the type parameter.
- (C) "single WireID + cached d on the struct": makes every d-level operation
  need a backend-internal "expand this virtual wire to its underlying qubits"
  step. That lookup has to live somewhere — either the context (option A) or
  the FFI layer. Either way, it's a second map not already built.
- (B) is the minimum-surprise choice: the NTuple of qubits *is* the storage,
  `d` is the semantic label, and no context field changes.

### Forward-compat with QInt{W,d} (bead dj3)

Under (B), `QInt{W, d}` is `NTuple{W, QMod{d, K}}` (or flat NTuple). Mod-d
ripple-carry arithmetic (Gottesman 1998 SUM) is defined per-digit on QMod{d}
wires. At d=2 the arithmetic degenerates to the existing boolean ripple-carry
adder (`src/types/qint.jl:208-273`). **Key point**: nothing in this bead
forecloses d-level digit aggregation.

## 2. Context integration — Q2 answer

### Choice: **compile-time d via the type parameter**

The context remains wire-keyed and dim-unaware. When a d-level primitive needs
to do work it dispatches on `QMod{d}` at the Julia level, and the gate call
into the context is still per-qubit:

```
apply_qmod_prep!(ctx::AbstractContext, q::QMod{d}) where {d} = ...
```

Inside this method, the primitive decomposes the d-level operation into
qubit-level `apply_ry!` / `apply_cx!` calls on `q.wires`. Julia specialises on
`d` — zero runtime cost.

### Justification

- **Rule 1 + Rule 13**: no new context field is invented when the existing
  type-parameter channel works. `QInt{W}` has been running this pattern for
  months (width is a type parameter; the context never knows W) and it is
  stable (`src/types/qint.jl:12-13`).
- **Mixed-d error detection (P8 / Rule 1):** because `d` is in the type,
  mixed-d SUM is a Julia method-dispatch issue, not a runtime check:
  ```
  Base.xor(a::QMod{d}, b::QMod{d}) where {d} = ...   # homogeneous OK
  Base.xor(a::QMod{d1}, b::QMod{d2}) where {d1, d2} =
      error("Mixed-d SUM not defined: $d1 vs $d2")
  ```
  (Not this bead's scope — SUM lives at `Sturm.jl-p38` — but the pattern is
  established here.) If we used a runtime `wire_dims` map (option A of Q1) the
  error would be a dict lookup per op. The type-parameter path is type-stable
  and catches the error at compile time whenever d1, d2 are known statics.
- **P8 promotion (`QBool + 3` still works):** unaffected. `QMod{d}` does not
  touch QBool/QInt dispatch rules. Future `QMod{d}` + `Integer` promotion
  (e.g. a classical constant k ∈ [0, d) auto-prep'd) is straightforward by
  following `_promote_to_qint` (`src/types/qint.jl:84-86`).
- **QInt{W, d} interop:** when we later need a QInt{W, d}(v::Integer) ctor, it
  just materialises W × QMod{d}s with each digit prep'd from base-d
  expansion of v. All handled via `where {W, d}`.

### API surface (this bead)

No new `AbstractContext` methods. **One** optional hook added:

```
_leakage_guard!(ctx, q::QMod{d}) where {d} = nothing   # default no-op
```

This gets overloaded by `EagerContext` in a later bead if we decide to do
dynamic leakage checking on simulator paths only. It is NOT part of the
`AbstractContext` contract — it's an internal helper living in
`src/types/qmod.jl`.

## 3. Prep primitive — Q3 answer

### Signatures

```
QMod{d}(ctx::AbstractContext) where {d}   # explicit ctx
QMod{d}() where {d}                        # via current_context() TLS
```

Both return a `QMod{d, K}` in `|0⟩` (all underlying qubits at `|0⟩`). Mirrors
`QInt{W}(ctx, 0)` at the zero-value specialisation.

### Allocation pattern

Call `allocate!` K times via `ntuple(_ -> allocate!(ctx), Val(K))`, exactly the
pattern from `QInt{W}` at `src/types/qint.jl:65-71` (minus the bit-setting loop
— the locked decision drops the amplitude knob, always preps `|0⟩`). Do **not**
invent `allocate_group!`; `allocate_batch!` (`src/context/abstract.jl:22-24`)
returns `Vector{WireID}` — wrong shape (heap-allocated; we need stack-allocated
NTuple for `where {K}` specialisation). Validation `d >= 2` at ctor entry per
Rule 1. `_qmod_nbits(d) = ceil(Int, log2(d))`, wrapped in `Val(K)` for type-
level K. Post-prep `_leakage_guard!(ctx, q)` is a no-op hook for later beads.

### Leakage guard strategy (d not a power of 2)

The survey locks "qubit-encoded fallback simulator ... unused levels (e.g.
|3⟩ for d=3 encoded in 2 qubits) carry leakage guards"
(`docs/physics/qudit_magic_gate_survey.md` §8.8 + this bead brief).

**Design**: three-layer defence, only layer 1 active in this bead:

1. **Prep is trusted.** Fresh-allocated wires come from `allocate!` at |0⟩
   (guaranteed by Orkan's `orkan_state_init!` zeroing and by recycled-slot
   reset on measurement — `src/context/eager.jl:264-276`). So a newly prep'd
   `QMod{d}` is always in |0…0⟩, which is always inside the d-level subspace
   regardless of d. **No runtime check needed at prep time.** This is cheap
   and correct.

2. **Primitive-level assertions (later beads).** Each of primitives 2-6
   (`Sturm.jl-ak2, os4, mle, p38`) is responsible for preserving the
   invariant `k < d` on every wire group it touches. At d=2^K there is nothing
   to preserve (all bit-patterns legal); at non-power-of-2 d, each primitive
   will use the spin-j rotations that analytically stay in the subspace (the
   Wigner-rotation block of $SU(2j+1)$ is closed on $\{|0⟩,…,|d−1⟩\}$ by
   construction — survey §5, `docs/physics/qudit_primitives_survey.md`). No
   per-gate projection needed on simulator paths.

3. **Debug-mode measurement-time assertion (simulator only, later bead).**
   `_leakage_guard!` will grow a method `::EagerContext, ::QMod{d}` that, when
   `d` is not a power of 2 AND `d != 2^K`, runs through the amplitude buffer
   checking that amplitudes at basis indices `≥ d` are zero. Runs O(2^n)
   across the whole state — hence simulator-debug-only. A user-facing
   `Sturm.check_leakage=true` kwarg on EagerContext toggles it; default off.

**This bead implements only layer 1.** Layers 2 and 3 are follow-on beads and
mentioned in §8 of this doc. The critical thing is that `_leakage_guard!`
exists as a hook callable at prep time — even though it's a no-op — so that
the later beads can overload it without changing call sites.

**Not doing:** projection onto the d-level subspace at each step. Expensive,
doesn't run on real hardware, and would silently fix physics bugs that Rule 1
says should crash. The whole point of Rule 1 (fail loud) is we want leakage
to surface as a test failure, not be papered over.

## 4. Measurement / P2 cast — Q4 answer

### Cast target type: `Int`

Not `Mod{d}` — that would mean adding a dependency on `Mods.jl` just for the
cast return type. CLAUDE.md Julia Convention 4: "Core Sturm.jl depends only on
Orkan (via `ccall`). No Qiskit, no Cirq, no other quantum frameworks." Adding
Mods.jl is inconsistent with that discipline.

**Return plain `Int` in `[0, d)`**, following the `Base.Int(q::QInt{W})`
convention (`src/types/qint.jl:108-119`). Downstream users can `mod(n, d)` if
they want the modular semantics; most measurement-consuming code will feed the
result to a classical Julia operation that doesn't care about the Mod wrapper.

(If a future bead wants a strongly-typed `Mod{d}` cast, it can be added as a
second method — `Base.convert(::Type{Mod{d}}, q::QMod{d})` — without breaking
the Int path. Not scope here.)

### Signature

```
Base.Int(q::QMod{d, K}) where {d, K} = ...       # blessed, silent
Base.convert(::Type{Int}, q::QMod{d, K}) where {d, K} = begin
    _warn_implicit_cast(QMod{d}, Int)
    Int(q)
end
```

Both use the same `_warn_implicit_cast` machinery as QBool/QInt
(`src/types/quantum.jl:95-103`). The `From` type argument should be `QMod{d}`
(not `QMod{d, K}`) for a clean warning message — minor: pattern-match
`QMod{d}` in the convert method, pass that as From.

### Measurement body

Measure each of the K underlying qubits via `_blessed_measure!`, assemble
little-endian:

```
result = 0
for i in 1:K
    outcome = _blessed_measure!(q.ctx, q.wires[i])
    if outcome
        result |= (1 << (i - 1))
    end
end
```

Identical to `Base.Int(::QInt{W})` (`src/types/qint.jl:108-119`), because the
underlying storage IS a little-endian qubit tuple.

### Leakage at measurement

If `result >= d` (i.e. observed a basis state outside the d-level subspace),
that is a physics bug. **Crash with a clear message** per Rule 1:

```
if result >= d
    error("QMod{$d} measurement produced out-of-range bitstring $result " *
          "(>= d). This indicates leakage into unused encoded basis states. " *
          "Possible causes: (1) a custom primitive violated the d-level " *
          "invariant; (2) the state was corrupted by a non-subspace-preserving " *
          "operation; (3) Orkan backend bug. Inspect the call site and/or " *
          "enable EagerContext(check_leakage=true).")
end
```

`q.consumed = true` only after the check so a leakage error leaves the
resource in a clearly-crashed state for the @context finally block.

Note: at `d = 2^K` exactly, `result < d` always holds — no check overhead
needed. Worth a small `@static if d != 2^K` trick or just an `if d != 2^K &&
result >= d`. Implementer's call. Julia will constant-fold either way given
the `where {d}` specialisation.

### Implicit-cast warning

Same `_warn_implicit_cast(QMod{d}, Int)` call. Dedup by source location is
handled by the existing machinery (`src/types/quantum.jl:96-102`). No changes
needed to `_warn_implicit_cast` itself.

## 5. P9 / Bennett — Q5 answer

### classical_type

```
classical_type(::Type{<:QMod}) = Int8
classical_compile_kwargs(::Type{<:QMod{d}}) where {d} =
    (bit_width = _qmod_nbits(d),)
```

Matches QBool / QInt exactly (`src/types/qbool.jl:13-14`,
`src/types/qint.jl:20-21`). Return type `Int8` is the common placeholder — the
`bit_width` kwarg tells Bennett how many bits are actually meaningful.

### The modular arithmetic gap (honest flag)

Bennett.jl (per the `docs/bennett-integration-v01-vision.md` referenced from
user memory + `src/bennett/bridge.jl`) compiles classical Julia functions to
reversible circuits via LLVM IR → Toffoli lowering. For QBool/QInt{W} the
compile target is W-bit bitvectors with modular arithmetic at 2^W.

**For QMod{d} with d not a power of 2, Bennett has no native mod-d primitive.**
A classical Julia `f(x::UInt8)` that the user intends as "mod 3 arithmetic"
will be compiled as mod 256 (UInt8's native width), and the results will be
wrong whenever the user's logic crosses the d-boundary.

**Mitigation options (none in this bead, all flagged for follow-on):**

- (i) Add a `mod::Int = d` kwarg to `classical_compile_kwargs` and teach
  Bennett to emit mod-d correction circuits after each add/mul. Structural
  change to Bennett.
- (ii) Forbid `@quantum_lift` / `oracle(f, q::QMod{d})` when `d` is not a
  power of 2, with a clear error directing users to per-prime tabulation or
  `qrom_lookup_xor!`. Cheapest.
- (iii) Compile the function as a classical table (QROM lookup) via
  `oracle_table` (exported in Sturm.jl:126). This is how arbitrary non-power-
  of-2 functions are handled in the existing codebase; a QMod{d} extension
  would need a d-aware table shape.

**Recommendation**: ship this bead with (ii) — `classical_compile_kwargs` for
a non-power-of-2 `d` raises an "unsupported" error if Bennett tries to use it
— and file a follow-on bead for (i) or (iii). This keeps P9 honest (the bridge
for typed functions) without promising mod-d arithmetic we can't deliver.

Concrete minimal change to `src/bennett/bridge.jl`: an assertion
`ispow2(d) || error(...)` inside the `QMod{d}`-specific `apply_oracle!` /
`oracle` dispatch. Not this bead's code, just a waypoint.

## 6. Test sketch — Q6 answer

New file: `test/test_qmod.jl`. Registered in `test/runtests.jl`.

### Testset 1 — construction and type

```
@testset "QMod{3} construction" begin
    @context EagerContext() begin
        q = QMod{3}(current_context())
        @test q isa QMod{3}
        @test q isa QMod{3, 2}    # K = 2
        @test q isa Quantum
        @test length(q.wires) == 2
        @test !q.consumed
        @test q.ctx === current_context()
        ptrace!(q)
        @test q.consumed
    end
end
```

### Testset 2 — |0⟩ prep (measurement = 0)

```
@testset "QMod{3} preps to |0>" begin
    @context EagerContext() begin
        for _ in 1:100   # deterministic — no randomness in prep
            q = QMod{3}()
            @test Int(q) == 0
        end
    end
end
```

### Testset 3 — d = 2^K exact (no leakage possible)

```
@testset "QMod{4} power-of-2 storage" begin
    @context EagerContext() begin
        q = QMod{4}()
        @test length(q.wires) == 2    # K = 2, perfectly packed
        @test Int(q) == 0
    end
    @context EagerContext() begin
        q = QMod{8}()
        @test length(q.wires) == 3    # K = 3
        @test Int(q) == 0
    end
end
```

### Testset 4 — d=2 recovers QBool-compatible wire shape

```
@testset "QMod{2} parallels QBool" begin
    @context EagerContext() begin
        q = QMod{2}()
        @test length(q.wires) == 1   # K = 1
        @test Int(q) == 0
        @test q isa QMod{2, 1}
        # NB: QMod{2} !== QBool. Bool(q) is NOT defined. See §8 open questions.
    end
end
```

### Testset 5 — d validation (fail loud)

```
@testset "QMod dimension validation" begin
    ctx = EagerContext()
    @test_throws ErrorException QMod{1}(ctx)     # d must be >= 2
    @test_throws ErrorException QMod{0}(ctx)
    # Non-integer d — Julia's type system rejects at type-construction time:
    @test_throws Exception eval(:(QMod{1.5}))    # not an integer
end
```

### Testset 6 — backwards-compat (QBool / QInt tests pass unchanged)

Not a new test — relies on existing `test/test_bell.jl`, `test/test_primitives.jl`,
`test/test_cases.jl`, etc. to still pass. If any break, the change to
`src/types/quantum.jl` / `src/Sturm.jl` has leaked into the qubit paths,
which would be a Rule 11 violation. Quality-gate: run `Pkg.test()` before
the PR closes.

### Testset 7 — ptrace!

```
@testset "QMod{d} partial trace frees all underlying wires" begin
    @context EagerContext() begin
        ctx = current_context()
        pre_slots = length(ctx.free_slots)
        pre_n = ctx.n_qubits
        q = QMod{3}()
        @test length(ctx.wire_to_qubit) >= 2   # at least K wires allocated
        ptrace!(q)
        @test q.consumed
        # Slots should be recycled back to free list
        @test length(ctx.free_slots) == pre_slots + 2
    end
end
```

### Testset 8 — TLS context (current_context())

```
@testset "QMod{d}() uses TLS context" begin
    @context EagerContext() begin
        q = QMod{3}()
        @test q.ctx === current_context()
        ptrace!(q)
    end
    # Outside @context block, must error
    @test_throws ErrorException QMod{3}()
end
```

### Testset 9 — implicit-cast P2 warning

```
@testset "QMod{d} implicit cast warns (P2)" begin
    @context EagerContext() begin
        q = QMod{3}()
        @test_logs (:warn, r"Implicit quantum.classical cast") begin
            x::Int = q
        end
    end
    # Explicit cast is silent
    @context EagerContext() begin
        q = QMod{3}()
        @test_nowarn (r = Int(q); r)
    end
end
```

### Testset 10 — mixed-d stub (P8 error site exists)

```
@testset "QMod{d1} ⊻ QMod{d2} errors loudly" begin
    # SUM is not in this bead's scope, but the error path must exist
    # so stale auto-dispatch doesn't silently create wrong circuits.
    @context EagerContext() begin
        a = QMod{3}()
        b = QMod{5}()
        @test_throws ErrorException (a ⊻= b)   # stub: "mixed-d SUM not defined"
        ptrace!(a); ptrace!(b)
    end
end
```

(If the SUM bead lands before this one, the stub is replaced; but shipping the
`Base.xor(::QMod{d1}, ::QMod{d2}) where {d1, d2}` method now — even as a pure
error — honours Rule 1.)

### Testset 11 — leakage crash at measurement (deferred; see §8 R4)

The prep primitive cannot itself produce leakage (|0⟩ is always in-subspace);
the measurement-time check is unreachable from any code in this bead. Test
deferred to the first bead that can drive state out of subspace. The runtime
check itself stays in the shipped code as a Rule-1 safety net.

## 7. Files to touch

### New: `src/types/qmod.jl` (~150 lines)

Contents:
- `struct QMod{d, K} <: Quantum` with inner ctor asserting `K == _qmod_nbits(d)`.
- `_qmod_nbits(d) = ... ; ispow2_d(d) = ...` helpers.
- `classical_type`, `classical_compile_kwargs` trait methods.
- `check_live!`, `consume!` for linear resource tracking.
- `ptrace!(q::QMod{d, K})` — loops over wires, deallocates each.
- Convenience outer ctor: `QMod{d}(args...) = QMod{d, _qmod_nbits(d)}(args...)`.
- Preparation: `QMod{d, K}(ctx::AbstractContext)`, `QMod{d}()` TLS variant.
- `Base.Int(q::QMod{d, K})`, `Base.convert(::Type{Int}, q::QMod{d, K})` with
  leakage crash.
- `Base.length(::QMod{d, K}) = K`.
- `_leakage_guard!(ctx, q::QMod{d}) = nothing` hook.

### Edit: `src/types/quantum.jl`

Update the docstring comment "future QDit{D}" on line 5 to reflect the actual
type name `QMod{d}`. No code change — just documentation.

### Edit: `src/context/eager.jl`

**None.** Context stays dim-unaware (Q2 choice). If a later bead chooses the
wire_dims map route it touches eager.jl and density.jl — not this bead.

### Edit: `src/Sturm.jl`

Add `include("types/qmod.jl")` after `include("types/qint.jl")` (line 15 of
`src/Sturm.jl`). Add `QMod` to the `# Types` export list (line 102).

### New: `test/test_qmod.jl`

Contents from §6 above.

### Edit: `test/runtests.jl`

Register `include("test_qmod.jl")`. (Verify the file uses `include`-style
test registration; standard Julia pattern is `include`.)

## 8. Open questions / risks

**R1. Two-parameter type (`QMod{d, K}`) visible to users?**

With Julia's partial type-parameter patching, `q::QMod{3}` (1-parameter form)
works for dispatch because K is derived — but `typeof(q)` prints as
`QMod{3, 2}`, which is visible in error messages and REPL output. Minor
cosmetic issue. `QCoset{W, Cpad, Wtot}` already exposes users to this — see
test `@test q isa QCoset{4, 3}` works even though the field type signature
uses `Wtot` too (`test/test_q84_types.jl:10`). Low-risk.

**R2. `Base.Bool(::QMod{2})` — should it exist?**

`QMod{2}` is a different type from `QBool` but structurally identical at d=2.
Users who do `Bool(q::QMod{2})` today get a MethodError. Options:
- (a) add `Base.Bool(q::QMod{2, 1}) = Bool(Int(q) == 1)` — quality-of-life.
- (b) don't — keep the types strictly separate, user measures as `Int(q)`.
- My lean: (b), in keeping with "`Bool` vs `Mod{2}` are distinct types by
  design" (survey §8.5 bullet 1). Document the non-interop in the `QMod`
  docstring so users aren't surprised.

**R3. d validation at type-param time or ctor time?**

`QMod{1}` is a valid Julia type (nothing stops the user writing it) — the
runtime error fires at the ctor. We could catch earlier by making `QMod` a
parametric abstract type with an inner-type guard via `@assert d isa Int &&
d >= 2`, but that's not a Julia idiom and tests would become ugly. Lean: fail
at ctor (current design). Matches `QInt{W}` (`src/types/qint.jl:59`) which
validates W >= 1 in the ctor.

**R4. Leakage-crash unit test is brittle / unreachable from this bead.**

Reaching into `ctx.orkan` to corrupt amplitudes couples the test to EagerContext
internals; and the prep primitive cannot produce leakage. My lean: defer the
crash-path unit test to the first bead that can drive the state out of
subspace (likely the SUM bead `Sturm.jl-p38` at d=3). The runtime check itself
stays — Rule 1 safety net — we just don't test an unreachable path here.

**R5. No initial-value ctor.**

`QMod{d}(ctx, k)` to prep `|k⟩` is locked out of this bead (brief §Q3: "prep
is always `|0⟩`"). Easy library-level add later via SUM, not a primitive.

---

**Design doc exists at: `/tmp/qmod_design_A.md`.**
