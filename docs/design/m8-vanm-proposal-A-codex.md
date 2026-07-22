# F16 Design Proposal: Context-Parameterized Register Handles

**Bead:** `Sturm.jl-vanm`  
**Scope:** `QBool{C}`, `QInt{W,C}`, wire references, views, casts, context safety, F15 numeric contract, and F19 bicharacter trait  
**Target:** Julia ≥ 1.11; verified against Julia 1.12.5  
**Status:** Independent blind proposal

## 1. Decision

Parameterize every quantum register handle by the concrete type of its owning context:

```julia
QBool{C}
QInt{W,C}
WireRef{C}
```

where `C <: AbstractContext` is concrete. Keep the owning context object as a field: the type parameter makes dispatch inferable, while the object identity distinguishes two different `EagerContext` instances of the same type.

Introduce a common context-indexed register hierarchy:

```julia
abstract type AbstractRegister{C<:AbstractContext} end
abstract type AbstractQubit{C<:AbstractContext} <: AbstractRegister{C} end
```

`QBool`, `QInt`, and `WireRef` belong to this hierarchy. Views do not: they remain addressing modes, not number-like handles, but their parent type carries `C`.

This is a representation-only refactor. It must not change:

- allocated `WireID`s;
- process values or their order of application;
- measurement instruments or Born probabilities;
- trace, reset, control, arithmetic, or Bennett channel denotations;
- the seven surface constructs;
- any Orkan ABI call;
- any phase convention.

That is the GROUND = PHYSICS invariant: for every existing program and context, the before/after channels must have the same Choi matrix, and phase-sensitive process paths must emit the same process values. No rotations or gate-named surface operations are introduced.

## 2. Common register definitions

Add `src/types/register.jl`, included after the context layer and before `qbool.jl`:

```julia
"""
    AbstractRegister{C}

A quantum register handle owned by a concrete context type `C`.
Registers are number-like handles, not subtypes of `Number` or `Integer`.
"""
abstract type AbstractRegister{C<:AbstractContext} end

"""
    AbstractQubit{C}

A one-wire register or borrow, currently `QBool{C}` and `WireRef{C}`.
"""
abstract type AbstractQubit{C<:AbstractContext} <: AbstractRegister{C} end

abstract type RegisterStyle end
struct NumberLikeHandle <: RegisterStyle end

registerstyle(::Type{<:AbstractRegister}) = NumberLikeHandle()
registerstyle(x::AbstractRegister) = registerstyle(typeof(x))

contexttype(::Type{<:AbstractRegister{C}}) where {C} = C
contexttype(x::AbstractRegister) = contexttype(typeof(x))
```

These names should be `public`, not exported. They are extension traits for library and future register authors, not additional surface constructs.

Concrete context parameters are an invariant. Explicit construction with an abstract `C`, such as `QBool{AbstractContext}`, must throw:

```julia
@inline function _require_concrete_context_type(::Type{C}) where {C<:AbstractContext}
    isconcretetype(C) || throw(ArgumentError(
        "register context parameter must be concrete; got $C"))
    return nothing
end
```

### 2.1 `QBool{C}`

```julia
struct QBool{C<:AbstractContext} <: AbstractQubit{C}
    ctx::C
    wire::WireID

    function QBool{C}(ctx::C, wire::WireID) where {C<:AbstractContext}
        _require_concrete_context_type(C)
        new{C}(ctx, wire)
    end
end
```

`QBool` without parameters remains the ergonomic partial `UnionAll` covering all contexts. Existing annotations such as:

```julia
function teleport(q::QBool)
```

continue to match every `QBool{C}` and specialize on the actual concrete argument.

### 2.2 `QInt{W,C}`

Place `C` last so existing `QInt{W}` syntax remains valid:

```julia
struct QInt{W,C<:AbstractContext} <: AbstractRegister{C}
    ctx::C
    wires::NTuple{W,WireID}

    function QInt{W,C}(
        ctx::C,
        wires::NTuple{W,WireID},
    ) where {W,C<:AbstractContext}
        W >= 1 || throw(ArgumentError("QInt width must be positive; got W=$W"))
        _require_concrete_context_type(C)
        new{W,C}(ctx, wires)
    end
end
```

On Julia 1.12.5, `QInt{3}` is a partial `UnionAll`, and:

```julia
QInt{3,EagerContext} <: QInt{3}
```

is true. Therefore existing signatures such as `x::QInt{W}` remain source-compatible. Hot methods should nevertheless spell both parameters when they use the context:

```julia
function add!(x::QInt{W,C}, a::Integer) where {W,C}
```

### 2.3 `QMod`

No `QMod` type exists in the shipped M0–M7 source. This refactor should not invent its representation. Reserve the parameter order:

```julia
QMod{D,C}
```

with the modulus or dimension first and the context last, matching `QInt{W,C}`.

### 2.4 `WireID`

Keep `WireID` unchanged and unparameterized. It is an opaque per-context allocation identity, while `C` belongs to the handle that interprets it. Parameterizing `WireID` would spread context parameters through all context-core dictionaries without distinguishing two instances of the same context type.

## 3. Construction and the `ScopedValue` boundary

`CURRENT_CONTEXT` must remain:

```julia
const CURRENT_CONTEXT = ScopedValue{AbstractContext}()
```

A global `ScopedValue` capable of holding several concrete context kinds cannot give `current_context()` a statically concrete return type. This is intrinsic to dynamically scoped context selection, not something generated functions or a type parameter can honestly remove.

The public constructor is therefore a narrow dynamic boundary followed by a concrete function barrier.

### 3.1 `QBool` constructors

```julia
function QBool(p::Real, φ::Real = 0.0)
    (0.0 <= p <= 1.0) || throw(DomainError(p, "..."))
    return _prepare_qbool(current_context(), Float64(p), Float64(φ))
end

QBool(b::Bool) = _prepare_qbool(current_context(), b)

function _prepare_qbool(ctx::C, b::Bool)::QBool{C} where {C<:AbstractContext}
    _assert_context_open(ctx)
    wire = allocate!(ctx)
    b && apply!(ctx, X, (wire,))
    return QBool{C}(ctx, wire)
end

function _prepare_qbool(
    ctx::C,
    p::Float64,
    φ::Float64,
)::QBool{C} where {C<:AbstractContext}
    _assert_context_open(ctx)
    wire = allocate!(ctx)
    apply!(ctx, _prep_u2(p, φ), (wire,))
    return QBool{C}(ctx, wire)
end
```

The adoption seam is similarly typed:

```julia
function _adopt_qbool(ctx::C, wire::WireID)::QBool{C} where {C<:AbstractContext}
    _assert_context_open(ctx)
    _assert_live(ctx, wire)
    return QBool{C}(ctx, wire)
end
```

### 3.2 `QInt` constructor

```julia
function QInt{W}(n::Integer) where {W}
    return _prepare_qint(current_context(), Val(W), n)
end

function _prepare_qint(
    ctx::C,
    ::Val{W},
    n::Integer,
)::QInt{W,C} where {W,C<:AbstractContext}
    _assert_context_open(ctx)
    0 <= n < (1 << W) || throw(DomainError(n, "..."))

    wires = ntuple(_ -> allocate!(ctx), Val(W))
    x = QInt{W,C}(ctx, wires)

    @inbounds for j in 1:W
        ((n >> (W - j)) & 1) == 1 &&
            apply!(ctx, X, (wires[j],))
    end
    return x
end

function _adopt_qint(
    ctx::C,
    wires::NTuple{W,WireID},
)::QInt{W,C} where {W,C<:AbstractContext}
    _assert_context_open(ctx)
    all(w -> _assert_live(ctx, w) === nothing, wires)
    return QInt{W,C}(ctx, wires)
end
```

### 3.3 What is and is not inferred

For concrete arguments:

```julia
Core.Compiler.return_type(_prepare_qbool, Tuple{EagerContext,Bool})
# QBool{EagerContext}

Core.Compiler.return_type(
    _prepare_qint,
    Tuple{EagerContext,Val{3},Int},
)
# QInt{3,EagerContext}
```

The public zero-context-argument constructor necessarily has an existential result at the dynamic boundary:

```julia
Core.Compiler.return_type(QBool, Tuple{Bool})
# QBool
```

That does not invalidate the design. It means the dynamic lookup must not sit inside a hot loop.

The documented user idiom is:

```julia
function setup(args...)
    q = QBool(false)
    x = QInt{8}(0)
    return hot_algorithm!(q, x, args...)
end

function hot_algorithm!(
    q::QBool{C},
    x::QInt{W,C},
    args...,
) where {W,C<:AbstractContext}
    for item in args
        # inference-clean loop
        add!(x, item)
        # ...
    end
    return x
end
```

There is one dynamic dispatch into `hot_algorithm!`; the loop specializes on `C`.

Library internals that already receive a concrete `ctx::C` should call `_prepare_qbool(ctx, ...)` or `_prepare_qint(ctx, Val(W), ...)` directly. They must not reread `current_context()`.

In particular:

```julia
false ⊻ r
```

must allocate its fresh output with `_prepare_qbool(ctx, false)`, and `_fresh_copy(x)` must use `_prepare_qint(ctx, Val(W), 0)`. Those are current repeated `ScopedValue` reads that this migration should remove.

No new explicit-context surface constructor such as `QBool(ctx, false)` should be exported. Context objects remain execution machinery, not an eighth surface construct.

## 4. Wire handles and views

### 4.1 `x[i]`

```julia
struct WireRef{C<:AbstractContext} <: AbstractQubit{C}
    ctx::C
    wire::WireID
    reg::WireID
    idx::Int

    function WireRef{C}(
        ctx::C,
        wire::WireID,
        reg::WireID,
        idx::Int,
    ) where {C<:AbstractContext}
        _require_concrete_context_type(C)
        new{C}(ctx, wire, reg, idx)
    end
end

function Base.getindex(
    x::QInt{W,C},
    i::Integer,
)::WireRef{C} where {W,C}
    1 <= i <= W || throw(BoundsError(x, i))
    _preflight("x[i]", x)
    return WireRef{C}(x.ctx, x.wires[i], x.wires[1], Int(i))
end
```

The borrowed wire has the same `C` as its parent and the identical `WireID`. Measuring it continues to consume the shared wire in the context’s single-sourced consumed set.

### 4.2 `DualView` and general `View`

Keep the existing parent-typed representation:

```julia
mutable struct DualView{H} <: AbstractView
    parent::H
end

struct View{V<:ProcessValue,H} <: AbstractView
    transform::V
    parent::H
end
```

A `DualView{QBool{C}}`, `DualView{QInt{W,C}}`, or `DualView{WireRef{C}}` already carries `C` in `H`; duplicating it as another field or parameter would create two sources of truth.

Expose recursive traits:

```julia
contexttype(::Type{<:DualView{H}}) where {H} = contexttype(H)
contexttype(::Type{<:View{V,H}}) where {V,H} = contexttype(H)

ownercontext(v::AbstractView) = ownercontext(v.parent)
ownercontext(r::AbstractRegister) = r.ctx
```

Thus a bound view has a concrete type:

```julia
x̂ = dual(x)  # DualView{QInt{W,C}}
```

and its effectful `+` method specializes on the same `C`.

Structural involution remains unchanged:

```julia
dual(x::QInt{W,C}) where {W,C} = DualView(x)
dual(q::AbstractQubit{C}) where {C} = DualView(q)
dual(v::DualView) = v.parent
```

No Fourier operation is performed by `dual`; views still unwrap while process values compose.

General views remain parent-parametric:

```julia
view(V::ProcessValue, q) = View(V, q)
view(V::ProcessValue, w::View) =
    View(V ∘ w.transform, w.parent)
```

### 4.3 View casts

Context-sensitive casts dispatch through the concrete parent:

```julia
function Base.Bool(v::DualView{H}) where {C,H<:AbstractQubit{C}}
    q = v.parent
    ctx = _preflight("Bool(dual(q))", q)
    _assert_no_control(ctx, "conjugate-basis measurement cast")
    apply!(ctx, _dual_transform(q), (q.wire,))
    return Bool(q)
end

function Base.Int(v::DualView{H}) where {W,C,H<:QInt{W,C}}
    x = v.parent
    ctx = _preflight("Int(dual(x))", x)
    _assert_no_control(ctx, "Fourier-basis measurement cast")
    apply!(ctx, _dual_transform(x), x.wires)
    return Int(x)
end
```

The return type follows from the parent’s `C`.

## 5. Measurement casts under Ruling D

Use dispatch, not a runtime `casttype(C)` switch. A second return-type table would duplicate the method table and could drift from the actual implementation.

The common public entry performs all context, liveness, partial-consumption, and guardrail checks, then invokes a context-specific hook:

```julia
function Base.Bool(q::AbstractQubit{C}) where {C<:AbstractContext}
    ctx = _preflight("Bool(q)", q)
    _assert_no_control(ctx, "measurement cast Bool(q)")
    return _cast_bool(ctx, q)
end

function Base.Int(x::QInt{W,C}) where {W,C<:AbstractContext}
    ctx = _preflight("Int(x)", x)
    _assert_no_control(ctx, "measurement cast Int(x)")
    _assert_whole_register_live(ctx, x)
    return _cast_word(ctx, Val(W), x)
end
```

### 5.1 Eager

```julia
function _cast_bool(
    ctx::EagerContext,
    q::AbstractQubit{EagerContext},
)::Bool
    b = _measure_wire!(ctx, q.wire)
    mark_consumed!(ctx, q.wire)
    return b
end

function _cast_word(
    ctx::EagerContext,
    ::Val{W},
    x::QInt{W,EagerContext},
)::Int where {W}
    # Existing MSB-first measurement loop.
end
```

Therefore:

```julia
Bool(q::QBool{EagerContext})::Bool
Bool(r::WireRef{EagerContext})::Bool
Int(x::QInt{W,EagerContext})::Int
```

are inference-clean.

### 5.2 Exact density matrix

M8 should introduce context-indexed classical handles:

```julia
abstract type AbstractClassicalValue{C<:AbstractContext} end

struct ClassicalBit{C<:AbstractContext} <: AbstractClassicalValue{C}
    ctx::C
    id::ClassicalID
end

struct ClassicalWord{W,C<:AbstractContext} <: AbstractClassicalValue{C}
    ctx::C
    id::ClassicalID
end
```

`ClassicalID` names a context-owned classical record. Under the density context it maps to the pinched, still-live c-wire; under tracing it maps to an SSA result. The storage and lifetime maps belong to M8, not this refactor.

The reserved cast contracts are:

```julia
_cast_bool(
    ctx::DensityMatrixContext,
    q::AbstractQubit{DensityMatrixContext},
)::ClassicalBit{DensityMatrixContext}

_cast_word(
    ctx::DensityMatrixContext,
    ::Val{W},
    x::QInt{W,DensityMatrixContext},
)::ClassicalWord{W,DensityMatrixContext} where {W}
```

These methods apply the TP instrument, consume the quantum handle, and return ownership of the retained classical record. They must not sample.

The pre-M8 F16 commit should retain the current loud density-cast placeholder rather than invent a half-implemented record type. M8 replaces only these hooks; the register types and public cast entries do not change again.

### 5.3 Tracing

`TracingContext` does not exist yet. M8 adds:

```julia
_cast_bool(
    ctx::TracingContext,
    q::AbstractQubit{TracingContext},
)::ClassicalBit{TracingContext}

_cast_word(
    ctx::TracingContext,
    ::Val{W},
    x::QInt{W,TracingContext},
)::ClassicalWord{W,TracingContext} where {W}
```

Those methods emit a `MeasureNode` and return its classical SSA/wire handle. No tracing code belongs in `vanm`.

A future hardware context follows the same hook without changing `QBool` or `QInt`.

### 5.4 Implicit conversion

Ruling D applies to explicit `Bool(q)` and `Int(x)`. Typed Julia storage still requires a real host scalar. Therefore implicit `convert` remains Eager-only and warns:

```julia
function Base.convert(
    ::Type{Bool},
    q::AbstractQubit{EagerContext},
)::Bool
    @warn "implicit measurement ..."
    return Bool(q)
end

function Base.convert(
    ::Type{Bool},
    q::AbstractQubit{C},
) where {C<:AbstractContext}
    throw(ArgumentError(
        "implicit conversion to host Bool is unavailable in $C; " *
        "Bool(q) returns a classical record/token here; use cases"))
end
```

Apply the same rule to `convert(Int, x)` if that P2 path is added.

## 6. Mixed-context and escaped-handle safety

The type parameter is not the safety check. Two contexts of the same type remain distinct objects, so every surface entry must retain an identity check.

### 6.1 Preflight

Centralize preflight:

```julia
@inline function _preflight(op::AbstractString, h::AbstractRegister{C})::C where {C}
    ctx = h.ctx
    active = current_context()

    ctx === active || throw(ArgumentError(
        "$op: handle belongs to a different context instance than the active context"))

    _assert_context_open(ctx)
    for w in _handle_wires(h)
        _assert_live(ctx, w)
    end
    return ctx
end

@inline function _preflight(
    op::AbstractString,
    a::AbstractRegister{C1},
    b::AbstractRegister{C2},
) where {C1,C2}
    a.ctx === b.ctx || throw(ArgumentError(
        "$op: operands belong to different context instances"))
    ctx = _preflight(op, a)
    for w in _handle_wires(b)
        _assert_live(ctx, w)
    end
    return ctx
end
```

Views recurse to their parent before this check.

All checks, including width and alias validation, must complete before the first `apply!`. This matters for multi-step methods such as `add!(y, x)`: a dead or foreign `x` must be detected before applying the opening QFT to `y`.

### 6.2 Closed contexts

Add:

```julia
closed::Bool
```

to `ContextCore`. `teardown!` marks it closed, and `_assert_context_open` throws before any allocation, state read, or FFI call.

This closes a current hole: a handle returned by `eager do ... end` stores the torn-down context. Using it under another context already fails by identity, but rebinding the old context with `@context` could otherwise reach freed Orkan storage.

### 6.3 Nested contexts

The rules are:

- Nested `region()` using the same context is legal.
- Returning a handle/view from an inner region transfers or re-homes its underlying owned wires to the enclosing region.
- A non-returned inner owned handle is traced. Any hidden alias retained through a closure or mutable container becomes dead and fails `_assert_live` on first use.
- Nested `@context` with a different context rejects every outer handle, even when both are `EagerContext`.
- Binary operations reject operands from different context instances before mutation.
- A handle from a closed resource context rejects before FFI.
- A view or `WireRef` follows its parent/shared wire.
- Classical records introduced in M8 follow the same context identity rule.

Use `ArgumentError` for well-formed but context-forbidden operations and ordinary `error()` with the relevant `WireID`s for liveness/consumption failures. No custom exception hierarchy is needed.

### 6.4 Bennett borrows

Give `OracleQuery` an explicit context parameter and object:

```julia
struct OracleQuery{C<:AbstractContext,Xs<:Tuple}
    ctx::C
    compiled::CompiledOracle
    xs::Xs
end
```

Construction verifies every input belongs to the same context:

```julia
function oracle(f, x::QInt{W,C}; kwargs...) where {W,C}
    ctx = _preflight("oracle(f, x)", x)
    compiled = _compile_oracle(f, W, kwargs)
    return OracleQuery{C,typeof((x,))}(ctx, compiled, (x,))
end
```

Application verifies `target.ctx === query.ctx === current_context()` before allocating scratch. Add:

```julia
_escaped_wires(q::OracleQuery) = _escaped_wires(q.xs)
```

so returning a query from an inner region preserves its borrowed input instead of silently returning a query to a traced register.

## 7. F15: exact number-like-handle contract

Neither `QBool` nor `QInt` subtypes `Number` or `Integer`. Views do not subtype `AbstractRegister` and do not receive `NumberLikeHandle`.

The published shipped surface is:

| Type | Supported operation | Contract |
|---|---|---|
| `QBool{C}` / `WireRef{C}` | `Bool(q)` | consuming measurement; context-dependent return |
| | `not!(q)` | in-place ℤ₂ translation; same handle |
| | `q ⊻= r` | in-place controlled translation; same LHS handle |
| | `q ⊻= b::Bool` | exact-X mixed action; same handle |
| | `b::Bool ⊻ q` | fresh `QBool{C}` output |
| | `dual`, `when` | borrow/view and coherent control |
| `QInt{W,C}` | `Int(x)` | consuming measurement; context-dependent return |
| | `x[i]` | borrowed `WireRef{C}` |
| | `add!`, `sub!` | in-place cyclic translation; same handle |
| | `x ⊻= y`, `x ⊻= n` | in-place bitwise action; same handle |
| | `x + n`, `n + x`, `x - n`, `x + y` | fresh output; inputs remain live |
| | `superpose!` | in-place library materialization |
| | `dual`, `when`, `oracle` | view, control, Bennett bridge |
| `DualView{QInt{W,C}}` | effectful `+`/`-` with integer | modulation; same view |
| `DualView{<:AbstractQubit{C}}` | `not!`, `⊻`, cast, `when` | conjugate-view action/cast |

Not supported unless separately designed and implemented:

- `QInt <: Integer` or `Number`;
- `zero`, `one`, `typemin`, `typemax`, numeric promotion, or scalar conversion;
- `*`, `/`, `%`, `^`, shifts, broadcast numeric semantics, or iteration on quantum handles;
- host-valued `==`, `isequal`, `hash`, `isless`, `<`, `<=`, `>`, `>=`;
- using a quantum register as a dictionary key;
- arbitrary generic code constrained as `f(x::Integer)`;
- generic bitwise folds with value semantics.

This refactor should make accidental value interpretation fail loudly:

```julia
Base.:(==)(::AbstractRegister, ::Any) =
    throw(ArgumentError("quantum registers have no value equality; use `===` for handle identity or measure explicitly"))
Base.:(==)(::Any, ::AbstractRegister) =
    throw(ArgumentError("quantum registers have no value equality; measure explicitly"))
Base.isequal(::AbstractRegister, ::Any) =
    throw(ArgumentError("quantum registers have no value equality/hash semantics"))
Base.hash(::AbstractRegister, ::UInt) =
    throw(ArgumentError("quantum registers are not hashable values"))
Base.isless(::AbstractRegister, ::AbstractRegister) =
    throw(ArgumentError("quantum registers have no host ordering"))
```

`===` remains the identity operation for debugging and internal ownership assertions. It does not inspect quantum state.

When a coherent comparator is added, its result must be `QBool{C}`, never host `Bool`; that work is not part of F16. Branch-heavy ordinary Julia functions continue to go through:

```julia
oracle(f, x::QInt{W,C})
```

There is no catch-all method on `Function`, and no attempt to make arbitrary `f(::Integer)` dispatch on `QInt`. Generic code rides only the published overloads above.

## 8. F19: explicit symmetric bicharacter trait

Replace the transform-only `_dual_transform` trait with a complete duality specification in `src/kernel/views.jl`.

```julia
abstract type AbstractActionGroup end
struct Z2Group <: AbstractActionGroup end
struct Pow2CyclicGroup{W} <: AbstractActionGroup end
struct BitVectorGroup{W} <: AbstractActionGroup end

abstract type AbstractBicharacter end
struct Pow2Bicharacter{W} <: AbstractBicharacter end

abstract type PairingSymmetry end
struct SymmetricPairing <: PairingSymmetry end
struct NonSymmetricPairing <: PairingSymmetry end

struct DualitySpec{
    G<:AbstractActionGroup,
    F<:ProcessValue,
    B<:AbstractBicharacter,
    S<:PairingSymmetry,
}
    group::G
    transform::F
    bicharacter::B
    symmetry::S
end
```

For \(N=2^W\), the selected pairing is:

\[
B_W(x,y)=\omega^{xy},\qquad \omega=e^{2\pi i/N}.
\]

An implementation may expose the phase exponent separately to avoid avoidable floating error:

```julia
pairing_exponent(::Pow2Bicharacter{W}, x::Integer, y::Integer) where {W} =
    mod(big(x) * big(y), big(1) << W)

function bicharacter(b::Pow2Bicharacter{W}, x::Integer, y::Integer) where {W}
    N = big(1) << W
    k = pairing_exponent(b, x, y)
    return cispi(2 * Float64(k) / Float64(N))
end
```

Stock traits:

```julia
duality(::Type{<:QBool}) =
    DualitySpec(
        Z2Group(),
        H,
        Pow2Bicharacter{1}(),
        SymmetricPairing(),
    )

duality(::Type{<:QInt{W}}) where {W} =
    DualitySpec(
        Pow2CyclicGroup{W}(),
        QFT(W, false),
        Pow2Bicharacter{W}(),
        SymmetricPairing(),
    )

_dual_transform(x) = duality(typeof(x)).transform
```

The context parameter is intentionally absent from the duality data: `QInt{W,EagerContext}` and `QInt{W,TracingContext}` describe the same Hilbert space, group, Fourier transform, and pairing.

Index the distinct `QInt` actions explicitly:

```julia
actiongroup(::Type{<:QInt{W}}, ::Val{:add}) where {W} =
    Pow2CyclicGroup{W}()

actiongroup(::Type{<:QInt{W}}, ::Val{:xor}) where {W} =
    BitVectorGroup{W}()
```

This prevents the additive \(\mathbb Z_{2^W}\) and bitwise \((\mathbb Z_2)^W\) structures from being conflated.

A generic symmetric phase-entangler method may only dispatch when:

```julia
duality(typeof(x)).symmetry isa SymmetricPairing
```

For a future user-defined register with a non-symmetric self-duality, `dual` may still exist, but the alternative operand order must not be asserted equivalent.

The required laws are:

1. Identity:
   \[
   B(0,y)=B(x,0)=1.
   \]

2. Bicharacter:
   \[
   B(x+x',y)=B(x,y)B(x',y),
   \quad
   B(x,y+y')=B(x,y)B(x,y').
   \]

3. Nondegeneracy:
   for every nonzero \(x\), some \(y\) has \(B(x,y)\ne1\).

4. Declared symmetry:
   \[
   B(x,y)=B(y,x)
   \]
   whenever the trait carries `SymmetricPairing`.

5. Channel consequence:
   `q̂ ⊻= r` and `r̂ ⊻= q` have equal Choi matrices for the shipped ℤ₂ pairing.

The bicharacter lives with the dual/view trait, not on each handle or context and not as an inferred property of the Fourier matrix.

## 9. File-by-file migration

### `src/Sturm.jl`

- Include `types/register.jl` after `context/regions.jl` and before `types/qbool.jl`.
- Add `AbstractRegister`, `RegisterStyle`, `NumberLikeHandle`, `registerstyle`, `contexttype`, and the duality trait types to the `public` list.
- Keep `QBool`, `QInt`, `dual`, actions, and casts exported exactly as today.
- Correct comments that currently say width is the only `QInt` type parameter.

### `src/types/wire.jl`

- Keep `WireID` unchanged.
- Update documentation to distinguish an unparameterized identity token from context-parameterized handles.

### `src/types/register.jl` — new

- Define the context-indexed hierarchy and F15 traits.
- Define shared handle/context accessors and negative equality/hash behavior.

### `src/types/qbool.jl`

- Change `QBool` to `QBool{C}`.
- Move `AbstractQubit` to `register.jl`.
- Replace abstract-field constructors with `_prepare_qbool(ctx::C, ...)`.
- Type `_adopt_qbool`.
- Remove the obsolete rationale arguing against `QBool{C}`.
- Keep preparation physics byte-for-byte equivalent.

### `src/types/qint.jl`

- Change `QInt{W}` to `QInt{W,C}`.
- Change `WireRef` to `WireRef{C}`.
- Type constructors, `_adopt_qint`, `_here`, casts, indexing, and dual methods.
- Keep `QInt{W}` partial signatures where ergonomic; use `{W,C}` in hot methods.
- Preserve MSB-first ordering and partial-consumption checks.

### `src/context/abstract.jl`

- Add `closed::Bool` to `ContextCore`.
- Add `_assert_context_open`.
- Make `teardown!` mark the context closed.
- Keep all context primitives on concrete `ctx` values passed from handles.
- No register handles are stored here; its maps remain keyed by `WireID`.

### `src/context/regions.jl`

- Keep `CURRENT_CONTEXT::ScopedValue{AbstractContext}`.
- Document the constructor/function-barrier boundary.
- Make `_escaped_wires` work through `AbstractRegister{C}`, views, tuples, and `OracleQuery`.
- Preserve returned-handle re-homing and silent trace semantics.

### `src/context/eager.jl`

- No representation change.
- Provide the eager `_cast_bool`/`_cast_word` methods.
- Ensure state reads reject closed contexts.

### `src/context/density.jl`

- No change to `_instrument!`, `_PINCH_KRAUS`, or channel semantics.
- Keep the pre-M8 placeholder error.
- M8 later supplies density record-producing cast hooks.

### `src/surface/casts.jl`

- Replace abstract-context local dispatch with context-indexed public entries and `_cast_*` hooks.
- Keep explicit casts silent and consuming.
- Keep implicit `convert` warning and restrict it to scalar-producing Eager.
- Perform all validation before measurement or basis change.

### `src/surface/actions.jl`

- Type unary and binary methods over `AbstractQubit{C}`.
- Centralize same-active-context preflight.
- Allocate `false ⊻ r` via `_prepare_qbool(ctx, false)`, avoiding another `ScopedValue` read.
- Keep exact X, `ctrl(X)`, and conjugate-view lowerings unchanged.
- Use the declared bicharacter symmetry for the CZ law instead of claiming Pontryagin duality alone.

### `src/surface/arithmetic.jl`

- Add `C` to every hot `QInt` signature.
- `_fresh_copy(x::QInt{W,C})::QInt{W,C}` allocates through the already-known `ctx`.
- Same-width, same-context checks occur before opening QFT sandwiches.
- Keep value/action/modulation return discipline unchanged.
- Add F15 fail-loud negative methods or import them from `types/register.jl`.

### `src/surface/when.jl`

- Change control signatures to `AbstractQubit{C}` and parent-indexed views.
- `_when_core` and `_act!` already receive a concrete context; keep threading it.
- Preflight the control before changing the stack.
- No control, certificate, or channel semantics change.

### `src/kernel/views.jl`

- Keep `DualView{H}` and `View{V,H}` parent-parametric.
- Add recursive `contexttype`.
- Replace `_dual_transform` as the primary trait with `duality(::Type)`.
- Store the selected bicharacter and explicit symmetry marker in `DualitySpec`.
- Preserve view identity and structural unwrapping.

### `src/kernel/qft.jl`

- No lowering change.
- Update documentation to say the QFT is the transform component of the `QInt{W,C}` duality trait.

### `src/bennett/bridge.jl`

- Change `oracle` signatures to `QInt{W,C}`.
- Change `OracleQuery` to carry `C` and `ctx::C`.
- Validate query inputs and targets before scratch allocation.
- Add `_escaped_wires(::OracleQuery)`.
- Update the hand-built-query constructor used by tests.
- Keep `CompiledOracle` unchanged; it stores no register handles.

### `ext/SturmBennettExt.jl`

- Existing `QInt{W}`-style documentation remains valid as partial syntax.
- The extension compiles from `W` and does not construct handles, so only annotations/comments should change if needed.

## 10. Complete handle construction/storage audit

The shipped source creates or stores handles at these locations:

| Location | Current role | Migration |
|---|---|---|
| `types/qbool.jl` public constructors | creates owned `QBool` | `_prepare_qbool(ctx::C) -> QBool{C}` |
| `types/qbool.jl::_adopt_qbool` | wraps Choi/system wire | return `QBool{C}` |
| `types/qint.jl` public constructor | creates owned `QInt` | `_prepare_qint(ctx::C) -> QInt{W,C}` |
| `types/qint.jl::_adopt_qint` | wraps existing wire tuple | return `QInt{W,C}` |
| `types/qint.jl::getindex` | creates borrowed `WireRef` | return `WireRef{C}` |
| `kernel/views.jl::dual` | stores parent in `DualView` | parent type carries `C` |
| `kernel/views.jl::view` | stores parent in `View` | parent type carries `C` |
| `surface/actions.jl::xor(Bool, qubit)` | creates fresh target | use known `ctx`, return `QBool{C}` |
| `surface/arithmetic.jl::_fresh_copy` | creates fresh integer output | use known `ctx`, return `QInt{W,C}` |
| `bennett/bridge.jl::OracleQuery` | stores borrowed input handles | add `C`, `ctx`, escape traversal |
| `test/choi.jl` | adopts Bell system wires | inferred `QBool{DensityMatrixContext}` |
| region return tuples/views | store escaping handles indirectly | recursive `_escaped_wires` remains parameter-agnostic |

No other shipped source struct stores `QBool`, `QInt`, or `WireRef`.

## 11. Inference verification

### 11.1 Baseline

On Julia 1.12.5, the current source shows:

- `fieldtype(QBool, :ctx) === AbstractContext`;
- `_here(::QBool)` has `Body::AbstractContext`;
- `not!(::QBool)`, `xor(::QBool,::QBool)`, `add!(::QInt{3},::Int)`, and `Int(::QInt{3})` carry `ctx::AbstractContext`;
- `getindex(::QInt{3}, ::Int)` returns a `WireRef` whose context field is inferred only as `AbstractContext`.

The wrapper’s final return may still be inferred as `QBool` or `QInt{3}`, but its context-dependent call chain remains dynamically dispatched. That is the F16 defect.

### 11.2 Required targets after migration

Run `@code_warntype` on:

```julia
Sturm._here(q::QBool{EagerContext})
not!(q)
xor(q, r)
not!(dual(q))
Bool(q)

getindex(x::QInt{3,EagerContext}, 1)
not!(x[1])
add!(x, 1)
add!(y, x)
x + 1
x + y
x̂ + 1
Int(x)

oracle(f, x)
xor(b, query)
```

Also inspect the density placeholders and, after M8:

```julia
Bool(qdm)::ClassicalBit{DensityMatrixContext}
Int(xdm)::ClassicalWord{W,DensityMatrixContext}
Bool(qtrace)::ClassicalBit{TracingContext}
Int(xtrace)::ClassicalWord{W,TracingContext}
```

“Clean” means:

- no `Any`;
- no `AbstractContext` local on a handle-specialized hot path;
- no runtime dispatch at `_core`, `_act!`, `apply!`, `_measure_wire!`, or `_cast_*`;
- exact return types such as `QBool{C}`, `QInt{W,C}`, `WireRef{C}`, `DualView{QInt{W,C}}`, `Bool`, or the exact token type;
- only normal loop iterator unions such as `Union{Nothing,Tuple{...}}`;
- no unexpected `Union{}` except methods whose entire contract is to throw.

Add `@inferred` assertions for the same operations. Do not assert that the zero-argument public constructor is inferred across `current_context()`; assert the concrete helper and the hot function entered through the function barrier.

## 12. Test plan

### 12.1 `test/test_m3_qbool.jl`

Add:

- `typeof(q) === QBool{EagerContext}`;
- `fieldtype(typeof(q), :ctx) === EagerContext`;
- `_prepare_qbool(ctx, false)` is `@inferred`;
- `Bool(::QBool{EagerContext})` is `@inferred Bool`;
- explicit `QBool{AbstractContext}` construction fails;
- different Eager instances fail before measurement;
- an Eager handle under a density context fails before mutation;
- a handle from a closed context fails even if that old context is rebound;
- existing boundary, consumption, statistical, and pole-degeneracy tests remain unchanged.

Until M8, keep the density cast’s transitional throw. After M8 replace it with an exact record-token assertion.

### 12.2 `test/test_m4_views.jl`

Add:

- `dual(q) isa DualView{QBool{EagerContext}}`;
- `contexttype(typeof(dual(q))) === EagerContext`;
- view operations are `@inferred`;
- a view from another context fails before basis change;
- the existing structural unwrap and fresh-wrapper identity laws;
- the bicharacter laws for ℤ₂;
- the declared-symmetry law;
- the existing CZ Choi symmetry test.

### 12.3 `test/test_m5_when.jl`

Add:

- typed controls and dual controls retain `C`;
- foreign-context control rejects before pushing `control_stack`;
- same-type/different-instance controls reject;
- no changes to streaming control channels.

### 12.4 `test/test_m6_qint.jl`

Add:

- `typeof(x) === QInt{W,EagerContext}`;
- `x[i] isa WireRef{EagerContext}`;
- `_fresh_copy` and value-world operations return `QInt{W,EagerContext}`;
- `add!`, view modulation, indexing, and casts are `@inferred`;
- additive action group is `Pow2CyclicGroup{W}`;
- XOR action group is `BitVectorGroup{W}`;
- exhaustive bicharacter identity, bilinearity, nondegeneracy, and symmetry for small `W`;
- `QInt` is not a subtype of `Number` or `Integer`;
- `==`, `hash`, and `<` reject loudly;
- existing sign pins, F²-versus-unwrap, partial-consumption, and lost-binding tests remain unchanged.

### 12.5 `test/test_m7_bennett.jl`

Add:

- `OracleQuery{EagerContext,...}` type assertions;
- manual-query construction with the context field;
- target/query different-context rejection before scratch allocation;
- a query returned from an inner region retains its borrowed input;
- a query whose input is dead rejects before applying its `Perm`;
- existing permutation, kickback, control, and ancilla-cleanliness laws remain unchanged.

### 12.6 `test/choi.jl`

Assert adopted types are `QBool{DensityMatrixContext}`. Re-run all existing boundary and M4/M5 channel laws unchanged. These are the strongest proof that F16 did not change physics.

### 12.7 Context/region tests

In `test/test_contexts.jl` and `test/test_regions.jl`, add:

- closed-context rejection;
- inner-region returned handle re-homing;
- non-returned inner handle becoming dead;
- returned view transferring its parent wire;
- same-type nested context mismatch;
- different-type nested context mismatch;
- failure before state mutation, checked by comparing statevector/density matrix before and after the rejected call.

Run the full M0–M7 suite, not only the modified milestone files.

## 13. Migration order

1. Add failing type-shape, mixed-context, and inference tests.
2. Add `types/register.jl` and parameterize `QBool`.
3. Parameterize `QInt` and `WireRef`.
4. Propagate parent types through views.
5. Convert surface casts and actions to typed preflight/hooks.
6. Convert arithmetic and eliminate repeated `current_context()` reads.
7. Parameterize `OracleQuery` and its escape traversal.
8. Add F15 fail-loud value-semantics guards.
9. Add the duality/bicharacter trait and F19 laws.
10. Run ambiguity detection, inference checks, milestone tests, and the full suite.

Use `Test.detect_ambiguities(Sturm; recursive=true)` because partial `QInt{W}` signatures plus `{W,C}` overloads can create accidental ambiguities if broad mismatch fallbacks are added carelessly.

## 14. Risks and mitigations

### Constructor-boundary instability

`current_context()` cannot infer a concrete `C` from an abstractly typed global `ScopedValue`. Pretending otherwise with generated functions, `Val(current_context())`, or source rewriting would fight Julia.

Mitigation: one function barrier, documented explicitly; context-threaded internal constructors for library hot paths.

### Same-type context confusion

`QBool{EagerContext}` alone cannot distinguish two Eager instances.

Mitigation: retain `ctx::C` and use `===` against the active context and other operands.

### Specialization growth

Every surface method now specializes once per concrete context type.

This is intentional and bounded by the small set of context kinds. It is far cheaper than dynamic dispatch on every operation. Future highly parameterized wrapper contexts should keep irrelevant configuration in fields rather than type parameters.

### Abstract collections

`Vector{QBool}` becomes an abstract-element collection. It remains legal but dynamic by intent.

Document concrete storage:

```julia
Vector{QBool{C}}
Vector{QInt{W,C}}
struct RegisterBundle{C}
    flag::QBool{C}
    data::QInt{8,C}
end
```

Generic APIs may accept `AbstractVector{<:QBool}`.

### Method ambiguity

Context-equal methods and mismatch fallbacks can overlap, especially for width mismatch.

Mitigation: use broad methods with centralized preflight where possible, add only narrowly justified mismatch overloads, and run ambiguity detection.

### Raw constructor misuse

Julia has no true private constructors. A caller can reach internal names through `Sturm.`.

Mitigation: inner constructors reject abstract `C`; adoption helpers validate open context and live wires; every use still performs active-context and liveness checks.

### Concurrent use

`C` does not make a mutable context safe for concurrent mutation. The existing “one region, one task” assumption remains. ScopedValue inheritance and context typing are propagation mechanisms, not a synchronization design.

## 15. Alternatives rejected

### Keep `ctx::AbstractContext`

Rejected: it preserves dynamic dispatch and cannot express Ruling D’s cast return type.

### Store only a type parameter, not the context object

Rejected: two `EagerContext` instances would be indistinguishable and cross-context `WireID` collisions could silently target the wrong state.

### Parameterize only `WireID`

Rejected: casts dispatch on register handles, and `WireID{C}` still would not identify the owning context instance.

### Use a runtime `casttype(ctx)` table

Rejected: the method table already expresses the return contract. A parallel trait table would duplicate the source of truth and would not improve dispatch.

### Make `QInt <: Integer`

Rejected by F15: Julia’s integer ecosystem assumes value equality, hashability, total conversion, and host-valued ordering that a quantum handle cannot provide.

### Infer CZ symmetry from Pontryagin duality

Rejected by F19: evaluation \(G\times\widehat G\to U(1)\) is not intrinsically symmetric. Symmetry belongs to the selected bicharacter trait.

### Put `C` directly on `DualView` in addition to its parent

Rejected: `DualView{QInt{W,C}}` already carries `C`. Duplicating it permits inconsistent parameters and adds no inference value.

### Replace `ScopedValue` with task-local storage or an explicit global

Rejected: `Base.ScopedValues` is available since Julia 1.11, inherits bindings into spawned tasks, and provides the required dynamic `with` extent. Task-local storage reintroduces the propagation bug class already ruled out.

## 16. Open questions requiring human confirmation

1. **Wide `Int(x)`:** F23 remains unresolved. For `W >= Sys.WORD_SIZE`, should explicit `Int(x)` reject, return `BigInt`, or use another fixed-width classical result? F16 should not silently choose.

2. **Classical token arity:** This proposal reserves `ClassicalBit{C}` and `ClassicalWord{W,C}`. M8 must confirm whether a common `ClassicalID` is sufficient or whether a backend representation parameter is required.

3. **F15 failure policy:** Recommended: explicit loud errors for `==`, `hash`, and ordering. The alternative is documentation-only absence, but Base fallbacks can yield misleading identity-like results; fail-loud is safer.

4. **Closed-context tracking:** Recommended: add `ContextCore.closed`. Confirm whether this lands in `vanm` as mixed-context safety or in a separate lifecycle bead; omitting it leaves a real rebound-after-teardown hole.

5. **Public trait names:** Confirm the final names `registerstyle`, `duality`, `actiongroup`, and `bicharacter`. Their semantics should be frozen here even if naming is adjusted during implementation.

## 17. Acceptance criteria

The refactor is acceptable when all of the following hold:

- every owned or borrowed quantum handle has a concrete context parameter;
- the owning context field has concrete type `C`;
- `QInt{W}` and `QBool` remain ergonomic partial type spellings;
- every hot M4/M6 method is free of `AbstractContext` and `Any`;
- public construction uses a documented function barrier;
- library hot paths reuse their concrete context instead of rereading the `ScopedValue`;
- Ruling D casts dispatch to exact context-specific result types;
- views, wire references, and Bennett queries preserve `C`;
- mixed-context, dead-handle, and closed-context failures occur before physical mutation;
- the F15 operator surface is explicit and no register claims `Number`/`Integer` semantics;
- the duality trait carries a selected nondegenerate bicharacter and an explicit symmetry marker;
- all existing Choi, sign, control, Bennett, and boundary laws pass unchanged.