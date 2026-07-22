# F16 Design Proposal: Context-Parameterized Register Handles

**Bead:** `Sturm.jl-vanm`  
**Scope:** `QBool{C}`, `QInt{W,C}`, borrowed handles, views, cast dispatch, F15/F19 traits  
**Status:** Independent blind proposal  
**Target:** Julia ≥1.11; verified against Julia 1.12.5

## 1. Decision

Use the concrete context type as the trailing type parameter of every owning or borrowed register handle:

```julia
QBool{C}
QInt{W,C}
WireRef{C}
```

where `C <: AbstractContext` is the concrete type of the context object stored in the handle.

The context **instance** remains a field and is checked by object identity. The type parameter selects compiled code; it does not establish ownership by itself. Two different `EagerContext` objects have the same `C` and must still be rejected when mixed.

Existing source signatures remain valid:

```julia
f(q::QBool) = ...
f(x::QInt{W}) where {W} = ...
```

After the change, `QBool` and `QInt{W}` are partial `UnionAll` types matching every context parameter. Julia 1.12.5 verifies that `QInt{W}` matches `QInt{W,C}` without exposing `C` in ordinary user annotations.

Views and Bennett query values do not need a redundant context parameter: their concrete parent-handle type already contains `C`.

The cast implementation uses multiple dispatch on the concrete stored context:

```julia
Bool(::QBool{EagerContext})             -> Bool
Bool(::QBool{DensityMatrixContext})     -> ClassicalBit record
Bool(::QBool{TracingContext})           -> ClassicalBit IR wire

Int(::QInt{W,EagerContext})             -> Int
Int(::QInt{W,DensityMatrixContext})     -> ClassicalWord{W} record
Int(::QInt{W,TracingContext})           -> ClassicalWord{W} IR wire
```

`TracingContext` is not introduced by this refactor. The method boundary is reserved for M8.

## 2. Physics and semantic invariants

This is a representation and dispatch refactor. It must not change a quantum channel.

The following remain byte-for-byte equivalent in denotation:

- allocation order and canonical `|0⟩` initialization;
- `QBool(p, φ)` preparation;
- exact-X preparation of classical literals;
- wire order, including wire 1 = MSB for `QInt`;
- every emitted `U2`, `Perm`, `Ctrl`, QFT, and Orkan operation;
- action-family direction and return-handle discipline;
- view conjugation and double-dual unwrapping;
- measurement bases, collapse, pinching, reset, and partial trace;
- the consumed set and region ownership rules;
- control-stack behavior and all `when` guardrails;
- Bennett compute/accumulate/uncompute semantics.

The new bicharacter and number-like traits make existing mathematical obligations explicit. They do not add gates, rotations, or surface constructs.

For the initial F16 landing, the shipped DM cast may continue to throw exactly as it does today. Implementing its Ruling-D `ClassicalBit`/`ClassicalWord` record is M8 work because it requires classical-record ownership and `cases` liveness. F16 supplies the inference-clean dispatch slot for that implementation.

## 3. Exact core types

Add `src/types/register.jl`, included after the context definitions and before `qbool.jl`:

```julia
"""
    AbstractQRegister{C}

Supertype of quantum register handles owned by a concrete context type `C`.
Registers are number-like handles, not `Number` or `Integer` subtypes.
"""
abstract type AbstractQRegister{C<:AbstractContext} end

"""
    AbstractQubit{C}

A one-wire register or borrow whose owning context has concrete type `C`.
"""
abstract type AbstractQubit{C<:AbstractContext} <:
    AbstractQRegister{C} end

abstract type RegisterStyle end
struct NumberLikeHandleStyle <: RegisterStyle end
struct AddressingModeStyle   <: RegisterStyle end

register_style(::Type{<:AbstractQRegister}) = NumberLikeHandleStyle()

@inline contextof(x::AbstractQRegister{C}) where {C} =
    getfield(x, :ctx)::C
```

`AbstractQRegister`, `register_style`, and the style types should be `public`, not exported. `AbstractQubit` remains `public` as today.

### 3.1 `QBool{C}`

```julia
struct QBool{C<:AbstractContext} <: AbstractQubit{C}
    ctx::C
    wire::WireID

    function QBool{C}(ctx::C, wire::WireID) where {C<:AbstractContext}
        isconcretetype(C) || throw(ArgumentError(
            "QBool context parameter must be concrete; got $C"))
        return new{C}(ctx, wire)
    end
end
```

Preparation constructors:

```julia
function QBool(b::Bool)
    return QBool(current_context(), b)
end

function QBool(p::Real, φ::Real = 0.0)
    pp, phase = _checked_qbool_literal(p, φ)  # validate before context lookup
    return _prepare_qbool(current_context(), pp, phase)
end

function QBool(ctx::C, b::Bool) where {C<:AbstractContext}
    _require_open(ctx, "QBool")
    w = allocate!(ctx)
    b && apply!(ctx, X, (w,))
    return QBool{C}(ctx, w)
end

function QBool(ctx::C, p::Real, φ::Real = 0.0) where {C<:AbstractContext}
    pp, phase = _checked_qbool_literal(p, φ)
    return _prepare_qbool(ctx, pp, phase)
end

function _prepare_qbool(ctx::C, p::Float64, φ::Float64) where
        {C<:AbstractContext}
    _require_open(ctx, "QBool")
    w = allocate!(ctx)
    apply!(ctx, _prep_u2(p, φ), (w,))
    return QBool{C}(ctx, w)
end

_adopt_qbool(ctx::C, w::WireID) where {C<:AbstractContext} =
    QBool{C}(ctx, w)
```

`_checked_qbool_literal` retains the current range check and conversion order. In particular, an invalid `p` continues to throw `DomainError` before a missing-context error.

The context-explicit forms are the advanced/context-layer forms. They are the preparation-cast analogue of `apply!(ctx, ...)`: no new surface construct is introduced.

Named literals remain unchanged:

```julia
plus()    = QBool(0.5)
minus()   = QBool(0.5, π)
magic_T() = QBool(0.5, π / 4)
```

Internal code that already possesses a typed context should use the context-explicit form. For example, `false ⊻ r` should allocate with `QBool(ctx, false)`, not re-read the `ScopedValue`.

### 3.2 `QInt{W,C}`

```julia
struct QInt{W,C<:AbstractContext} <: AbstractQRegister{C}
    ctx::C
    wires::NTuple{W,WireID}

    function QInt{W,C}(ctx::C, wires::NTuple{W,WireID}) where
            {W,C<:AbstractContext}
        isconcretetype(C) || throw(ArgumentError(
            "QInt context parameter must be concrete; got $C"))
        return new{W,C}(ctx, wires)
    end
end
```

Preparation and adoption:

```julia
function QInt{W}(n::Integer) where {W}
    checked = _checked_qint_literal(Val(W), n)
    return QInt{W}(current_context(), checked)
end

function QInt{W}(ctx::C, n::Integer) where {W,C<:AbstractContext}
    checked = _checked_qint_literal(Val(W), n)
    _require_open(ctx, "QInt{$W}")
    ws = ntuple(_ -> allocate!(ctx), W)
    x = QInt{W,C}(ctx, ws)

    @inbounds for j in 1:W
        ((checked >> (W - j)) & 1) == 1 &&
            apply!(ctx, X, (ws[j],))
    end
    return x
end

_adopt_qint(ctx::C, ws::NTuple{W,WireID}) where
        {W,C<:AbstractContext} =
    QInt{W,C}(ctx, ws)
```

Existing width-generic signatures remain valid:

```julia
function add!(x::QInt{W}, a::Integer) where {W}
    ...
end
```

Methods that need the context type explicitly may use:

```julia
function f(x::QInt{W,C}) where {W,C<:AbstractContext}
    ...
end
```

Fresh-output arithmetic must retain `C` without returning through the dynamically scoped constructor:

```julia
function _fresh_copy(x::QInt{W,C}) where {W,C}
    ctx = _here(x)
    s = QInt{W}(ctx, 0)
    xor(s, x)
    return s
end
```

### 3.3 `WireRef{C}`

```julia
struct WireRef{C<:AbstractContext} <: AbstractQubit{C}
    ctx::C
    wire::WireID
    reg::WireID
    idx::Int

    function WireRef{C}(
        ctx::C, wire::WireID, reg::WireID, idx::Int
    ) where {C<:AbstractContext}
        isconcretetype(C) || throw(ArgumentError(
            "WireRef context parameter must be concrete; got $C"))
        return new{C}(ctx, wire, reg, idx)
    end
end

function Base.getindex(x::QInt{W,C}, i::Integer) where {W,C}
    1 ≤ i ≤ W || throw(BoundsError(x, i))
    return WireRef{C}(x.ctx, x.wires[i], x.wires[1], Int(i))
end
```

Thus:

```julia
x                  :: QInt{W,C}
x[i]               :: WireRef{C}
dual(x[i])         :: DualView{WireRef{C}}
Bool(x[i])         # dispatches from C
```

Borrowing and partial-consumption semantics are unchanged.

### 3.4 `QMod`

There is no `QMod` implementation in the shipped M0–M7 tree, so F16 must not add one.

When introduced, its context parameter should also be last:

```julia
QMod{D,C}
```

or, if a representation parameter is later required:

```julia
QMod{D,R,C}
```

This preserves `QMod{D}` as the ergonomic partial type. The runtime-vs-static modulus question from F24 must be ruled before fixing its complete parameter list.

## 4. Scoped construction and inference

The global binding remains:

```julia
const CURRENT_CONTEXT = ScopedValue{AbstractContext}()
```

This is the correct Julia ≥1.11 mechanism: `with` provides dynamic scope and inherited bindings for child tasks. Its static element type is nevertheless `AbstractContext`.

Julia cannot infer a concrete dynamic binding through that global. This was verified on Julia 1.12.5 with the equivalent minimal example:

```text
return_types(current_context)       = AbstractContext
return_types(context_barrier, B)    = Q{B}
return_types(ergonomic_constructor) = Q
runtime typeof(result)              = Q{B}
```

Therefore:

```julia
QBool(false)
QInt{8}(0)
```

construct runtime values of type `QBool{EagerContext}` and
`QInt{8,EagerContext}`, but inference at the caller may only report `QBool` or
`QInt{8}` because the concrete context came from dynamic scope.

That limitation cannot be removed with an inline annotation, generated
function, or return assertion without lying to the compiler.

### 4.1 Function-barrier rule

The ergonomic constructor is a cold dynamic boundary. A typed worker is the hot path:

```julia
function algorithm()
    x = QInt{16}(0)       # one dynamic construction boundary
    return _algorithm!(x)
end

function _algorithm!(x::QInt{W,C}) where {W,C<:AbstractContext}
    # x.ctx is C here; all actions, views, and casts specialize on C.
    for _ in 1:1000
        add!(x, 1)
    end
    return x
end
```

For allocation-heavy loops, pass the typed context and use the context-explicit constructor:

```julia
function allocation_loop!(ctx::C, n) where {C<:AbstractContext}
    for _ in 1:n
        q = QBool(ctx, false)
        # work with q::QBool{C}
    end
end

eager(capacity) do ctx
    allocation_loop!(ctx, n)
end
```

This is the documented hot-loop idiom:

1. read or receive the context once;
2. cross a function barrier whose argument has concrete type `C`;
3. use context-explicit construction and explicit context threading inside;
4. never call `current_context()` in the per-operation loop.

Surface actions still check that the explicit context is the currently active one when a handle is used.

## 5. Context identity and fail-loud safety

`C` distinguishes context implementations, not context instances. Every surface operation must retain an object-identity check.

Centralize the check instead of duplicating it across actions and casts:

```julia
@inline function _here(x::AbstractQRegister{C}, op::AbstractString) where {C}
    owner = contextof(x)              # statically C
    _require_open(owner, op)

    active = current_context()        # statically AbstractContext
    active === owner || _context_mismatch(op, owner, active)

    return owner                      # return the typed owner, not `active`
end

@noinline function _context_mismatch(op, owner, active)
    throw(ArgumentError(
        "$op: register belongs to a different context instance than the " *
        "active context; a handle crossed a context/region boundary"))
end

@inline function _require_same_context(
    op::AbstractString, ctx::AbstractContext, xs...
)
    for x in xs
        contextof(x) === ctx ||
            _operand_context_mismatch(op, ctx, contextof(x))
    end
    return ctx
end
```

Returning `owner`, whose type is `C`, is essential. Returning
`current_context()` would reintroduce `AbstractContext` into the hot path.

Multi-register methods validate every operand before any operation is emitted:

```julia
function Base.xor(
    a::AbstractQubit{CA}, b::AbstractQubit{CB}
) where {CA,CB}
    ctx = _here(a, "a ⊻= b")
    _require_same_context("a ⊻= b", ctx, b)
    _act!(ctx, ctrl(X), (b.wire, a.wire))
    return a
end
```

The same rule applies to:

- `add!(y, x)`;
- `x + y`;
- `q̂ ⊻= r`;
- `when`;
- Bennett query application;
- measurement through views;
- future token/register operations.

All context, liveness, partial-consumption, control, width, and alias checks must run before the first `apply!`, basis change, measurement, or ownership mutation.

### 5.1 Closed contexts

A handle returned from the outer `eager` or `density` resource block points to a torn-down Orkan state. Rebinding that old context manually must not reach freed FFI storage.

Add a lifecycle flag to `ContextCore`:

```julia
mutable struct ContextCore
    # existing fields...
    closed::Bool
end
```

and:

```julia
@inline function _require_open(ctx::AbstractContext, op)
    _core(ctx).closed && error(
        "$op: the owning context has been torn down; this is a dangling handle")
    return ctx
end

function teardown!(ctx::AbstractContext)
    core = _core(ctx)
    core.closed && return nothing
    orkan_state_free!(core.state)
    core.closed = true
    return nothing
end
```

This is a safety check only; it does not alter a live context’s channel.

### 5.2 Nested regions and contexts

The required behavior is:

| Situation | Result |
|---|---|
| Handle returned directly from `region()` under the same context | Valid; existing `_escaped_wires` re-homes it |
| View or `WireRef` returned directly | Valid; parent wires are re-homed |
| Handle hidden in a mutable container while region returns `nothing` | Region traces it; later use fails liveness |
| Outer handle used inside nested `@context inner` | Immediate context-identity error |
| Inner handle used after returning to outer context | Immediate context-identity error |
| Handles from two different `EagerContext` objects combined | Immediate error despite equal `C` |
| Handle from a torn-down outer resource rebound manually | Closed-context error before FFI |
| Consumed or traced handle used under its original context | Existing consumed/liveness error |
| Bennett query built from one context applied to a target in another | Context error before scratch allocation |

F17’s broader escape-analysis problem remains: Julia permits hiding handles in arbitrary user containers and closures. F16 guarantees that such a dangling alias fails when next used; it does not claim to discover every hidden alias at region exit.

## 6. Views and bound views

Keep the current wrapper arities:

```julia
abstract type AbstractView end

mutable struct DualView{H} <: AbstractView
    parent::H
end

struct View{V<:ProcessValue,H} <: AbstractView
    transform::V
    parent::H
end

register_style(::Type{<:AbstractView}) = AddressingModeStyle()
```

A redundant `C` parameter is unnecessary:

```julia
q::QBool{C}        -> DualView{QBool{C}}
x::QInt{W,C}       -> DualView{QInt{W,C}}
x[i]::WireRef{C}   -> DualView{WireRef{C}}
view(V, x)          -> View{typeof(V),QInt{W,C}}
```

This preserves existing method forms such as:

```julia
Base.Int(v::DualView{<:QInt{W}}) where {W}
Base.getindex(v::DualView{<:QInt}, i::Integer)
```

`DualView` remains mutable solely for wrapper identity:

```julia
dual(q) !== dual(q)
dual(dual(q)) === q
```

Context lookup for a view is delegated to its parent:

```julia
contextof(v::AbstractView) = contextof(v.parent)
```

View construction remains total and side-effect free. A dead or wrong-context
parent is rejected at the first operation through the view, not while wrapping
it.

Bound-view op-assign remains unchanged:

```julia
q̂ = dual(q)
q̂ ⊻= r

x̂ = dual(x)
x̂ += a
```

Each method returns the same view object so Julia’s assignment rewrite remains a no-op rebind.

## 7. Ruling-D cast dispatch

Do not encode the return type with a separate `casttype(C)` table. That would duplicate the method table and create two sources of truth. Concrete context dispatch is sufficient and inference understands it once `C` is present in the handle type.

### 7.1 Common cast front end

```julia
function Base.Bool(q::AbstractQubit{C}) where {C<:AbstractContext}
    ctx = _here(q, "Bool(q)")
    _assert_no_control(ctx, "measurement cast Bool(q)")
    _assert_live(ctx, q.wire)

    result = _measure_bit!(ctx, q.wire)
    mark_consumed!(ctx, q.wire)
    return result
end
```

For integers, use one context-dispatched word operation rather than assembling host `Int` from context-dependent per-wire results:

```julia
function Base.Int(x::QInt{W,C}) where {W,C<:AbstractContext}
    ctx = _here(x, "Int(x)")
    _assert_no_control(ctx, "measurement cast Int(x)")
    _assert_all_live(ctx, x.wires)  # includes partial-consumption check

    result = _measure_word!(ctx, x.wires)
    foreach(w -> mark_consumed!(ctx, w), x.wires)
    return result
end
```

This gives each context an atomic word-level boundary and avoids a
`Vector{Union{Bool,ClassicalBit}}` design.

### 7.2 Eager methods

```julia
function _measure_bit!(
    ctx::EagerContext, w::WireID
)::Bool
    # Existing sample/collapse/reset/retire implementation.
end

function _measure_word!(
    ctx::EagerContext, ws::NTuple{W,WireID}
)::Int where {W}
    # Existing MSB-first sampling and assembly.
end
```

Therefore inference sees:

```julia
Bool(::QBool{EagerContext})       :: Bool
Bool(::WireRef{EagerContext})     :: Bool
Int(::QInt{W,EagerContext})       :: Int
```

### 7.3 DM record methods

M8 should use concrete classical handle types of this general shape:

```julia
struct ClassicalBit{C<:AbstractContext,R}
    ctx::C
    record::R
end

struct ClassicalWord{W,C<:AbstractContext,R}
    ctx::C
    record::R
end
```

For the shipped dense DM executor:

```julia
function _measure_bit!(
    ctx::DensityMatrixContext, w::WireID
)::ClassicalBit{DensityMatrixContext,WireID}
    # Pinch w with _instrument!, transfer it from quantum ownership to
    # classical-record ownership, and return the record handle.
end

function _measure_word!(
    ctx::DensityMatrixContext, ws::NTuple{W,WireID}
)::ClassicalWord{
    W,DensityMatrixContext,NTuple{W,WireID}
} where {W}
    # Pinch the word and transfer its record ownership atomically.
end
```

The quantum handle is consumed. The c-wire remains live only through the
classical token’s ownership machinery. Classical operations must not use the
quantum `_assert_live` path.

### 7.4 Tracing slot

M8 adds, rather than F16 inventing:

```julia
function _measure_bit!(
    ctx::TracingContext, w::WireID
)::ClassicalBit{TracingContext,ValueID}
    # Emit MeasureNode, return its SSA record value.
end

function _measure_word!(
    ctx::TracingContext, ws::NTuple{W,WireID}
)::ClassicalWord{W,TracingContext,ValueID} where {W}
    # Emit word measurement or a typed pack of bit-measure nodes.
end
```

No `TracingContext`, `ValueID`, or trace node is added by F16. The reserved
method names and handle parameter are the clean extension point.

### 7.5 Measurement through views

The view method remains a basis change followed by the same consuming cast:

```julia
function Base.Bool(v::DualView{H}) where {H<:AbstractQubit}
    p = v.parent
    ctx = _here(p, "Bool(dual(q))")
    _assert_no_control(ctx, "conjugate-basis measurement")
    _assert_live(ctx, p.wire)
    apply!(ctx, _dual_transform(p), (p.wire,))
    return Bool(p)
end

function Base.Int(v::DualView{<:QInt{W}}) where {W}
    x = v.parent
    ctx = _here(x, "Int(dual(x))")
    _assert_no_control(ctx, "Fourier-basis measurement")
    _assert_all_live(ctx, x.wires)
    apply!(ctx, _dual_transform(x), x.wires)
    return Int(x)
end
```

Thus the view’s return type follows the parent’s `C` automatically.

### 7.6 Implicit `convert`

Ruling D does not permit a token to occupy a typed `Bool` slot. The existing implicit cast must be Eager-only:

```julia
function Base.convert(
    ::Type{Bool}, q::AbstractQubit{EagerContext}
)::Bool
    @warn "implicit measurement of a QBool (P2): ..."
    return Bool(q)
end

function Base.convert(
    ::Type{Bool}, q::AbstractQubit{C}
) where {C<:AbstractContext}
    throw(ArgumentError(
        "implicit conversion to Bool is valid only in an eager/trajectory " *
        "context; explicit Bool(q) in this context returns a classical record"))
end
```

A future trajectory context registers its own actual-`Bool` method. No
`convert(Int, ::QInt)` method should be added merely for symmetry; one does not
exist today because `QInt` is not an `Integer`.

## 8. F15: published number-like-handle surface

Registers do **not** subtype `Number` or `Integer`:

```julia
QBool{C}   <: AbstractQRegister{C}
QInt{W,C}  <: AbstractQRegister{C}
```

The exact shipped operator surface is:

| Type | Value/fresh-output world | In-place action world | Other supported operations |
|---|---|---|---|
| `QBool{C}` / `WireRef{C}` | `false ⊻ q` / `true ⊻ q` produce a fresh `QBool{C}` | `not!`, `q ⊻= r`, `q ⊻= b::Bool` | `Bool`, `dual`, `when` |
| `QInt{W,C}` | `x + a`, `a + x`, `x - a`, `x + y` produce fresh `QInt{W,C}` | `add!(x,a)`, `sub!`, `add!(y,x)`, `x ⊻= y`, `x ⊻= n`, `superpose!` | `Int`, `dual`, `x[i]`, `oracle` |
| `DualView{QBool{C}}` | none | `not!`, `q̂ ⊻= r` | `Bool`, `when` |
| `DualView{QInt{W,C}}` | none | `x̂ += a`, `x̂ -= a` | `Int`, `when` where defined |
| `OracleQuery` | none | RHS of `b ⊻= query` | no other surface operation |

Not supported:

- nominal `Number`/`Integer` dispatch;
- `zero`, `one`, `promote_rule`, or scalar conversion;
- state/value equality;
- hashing by quantum value;
- ordinary total ordering;
- arbitrary ring operators not explicitly implemented;
- generic bitwise folds with value semantics;
- views in generic value APIs.

Physical identity is `(context instance, WireID tuple)` and is tested internally.
User code may use `===` to ask whether two bindings are the same handle. `==`,
`isequal`, and `hash` are not state comparisons and should fail descriptively
rather than acquire Base’s fallback value appearance. Identity-keyed internal
collections continue to use the explicit context/wire identity.

`QInt` has no shipped `<` implementation. When coherent comparison is added,
its declared result is:

```julia
Base.:<(
    x::QInt{W,C}, y::QInt{W,C}
)::QBool{C}
```

not `Bool`. It therefore cannot drive host `if` without an explicit consuming
cast. Branch-heavy generic functions remain routed through `oracle`.

A small public trait records this contract:

```julia
abstract type ComparisonStyle end
struct NoComparisonStyle       <: ComparisonStyle end
struct CoherentComparisonStyle <: ComparisonStyle end

comparison_style(::Type{<:QBool}) = NoComparisonStyle()
comparison_style(::Type{<:QInt})  = CoherentComparisonStyle()

abstract type HashStyle end
struct UnhashableHandleStyle <: HashStyle end

hash_style(::Type{<:AbstractQRegister}) = UnhashableHandleStyle()
```

The operator methods remain the authoritative implementation. The trait is for
generic Sturm/library dispatch and documentation; it does not promise arbitrary
`f(x::Integer)` compatibility.

No catch-all method on `Function` is introduced. In particular:

```julia
oracle(f, x::QInt{W,C}; kwargs...)
```

remains the only shipped Bennett entry, and `oracle(f, q::QBool)` remains a
`MethodError` until explicitly designed.

## 9. F19: explicit symmetric bicharacter trait

The dual trait belongs in `src/kernel/views.jl`, because it supplies kernel
mathematics to views. It is keyed by register type and does not depend on `C`.

The action-family group index belongs in `src/types/register.jl`:

```julia
abstract type ActionFamily end
struct XorActionFamily <: ActionFamily end
struct AddActionFamily <: ActionFamily end

abstract type LabelGroup end
struct Z2Group <: LabelGroup end
struct BitVectorGroup{W} <: LabelGroup end       # (Z₂)^W
struct Cyclic2PowerGroup{W} <: LabelGroup end    # Z_(2^W)

action_group(::Type{<:AbstractQubit}, ::XorActionFamily) =
    Z2Group()

action_group(::Type{<:QInt{W}}, ::XorActionFamily) where {W} =
    BitVectorGroup{W}()

action_group(::Type{<:QInt{W}}, ::AddActionFamily) where {W} =
    Cyclic2PowerGroup{W}()
```

This prevents the cyclic `dual(x)` group from being silently conflated with
`QInt`’s transversal bitwise-XOR group.

The dual trait carries the transform, selected bicharacter, nondegeneracy claim,
and symmetry claim:

```julia
abstract type AbstractBicharacter end
struct Z2Bicharacter <: AbstractBicharacter end
struct CyclicBicharacter{W} <: AbstractBicharacter end

abstract type NondegeneracyLaw end
struct NondegenerateLaw <: NondegeneracyLaw end

abstract type SymmetryLaw end
struct SymmetricLaw   <: SymmetryLaw end
struct UnspecifiedLaw <: SymmetryLaw end

struct BicharacterSpec{
    B<:AbstractBicharacter,
    N<:NondegeneracyLaw,
    S<:SymmetryLaw,
}
    form::B
    nondegeneracy::N
    symmetry::S
end

struct DualTrait{
    G<:LabelGroup,
    F<:ProcessValue,
    B<:BicharacterSpec,
}
    group::G
    transform::F
    bicharacter::B
end
```

Shipped traits:

```julia
dual_trait(::Type{<:AbstractQubit}) =
    DualTrait(
        Z2Group(),
        H,
        BicharacterSpec(
            Z2Bicharacter(),
            NondegenerateLaw(),
            SymmetricLaw(),
        ),
    )

dual_trait(::Type{<:QInt{W}}) where {W} =
    DualTrait(
        Cyclic2PowerGroup{W}(),
        QFT(W, false),
        BicharacterSpec(
            CyclicBicharacter{W}(),
            NondegenerateLaw(),
            SymmetricLaw(),
        ),
    )

_dual_transform(x) = dual_trait(typeof(x)).transform
```

The selected forms are:

\[
B_{\mathbb Z_2}(x,y)=(-1)^{xy},
\]

and, for \(N=2^W\),

\[
B_{\mathbb Z_N}(x,y)=\omega_N^{xy},
\qquad
\omega_N=e^{2\pi i/N}.
\]

Both satisfy:

1. character law in the first argument;
2. character law in the second argument;
3. nondegeneracy;
4. the additional symmetry law
   \[
   B(x,y)=B(y,x).
   \]

The bitwise action family on `QInt` is separately indexed by
\((\mathbb Z_2)^W\), whose corresponding per-wire pairing is
\((-1)^{x\cdot y}\). It must not be substituted for the cyclic pairing used by
`dual(x)`.

A symmetric phase-entangler must require a `SymmetricLaw` witness. A future
user-defined dual trait with `UnspecifiedLaw` may still support translation and
modulation, but `q̂ ⊻= r` symmetry must either be unavailable or fail loudly
until the symmetry law is supplied and tested.

The operational law remains:

```julia
q̂ = dual(q); q̂ ⊻= r
r̂ = dual(r); r̂ ⊻= q
```

These denote the same channel only because the shipped trait explicitly claims
and satisfies symmetry.

## 10. File-by-file migration

### `src/Sturm.jl`

- Include new `types/register.jl` after `context/regions.jl` and before
  `types/qbool.jl`.
- Publish `AbstractQRegister`, `register_style`, comparison/hash styles, action
  families, label groups, and dual-trait types as kernel/type API.
- Keep `QBool`, `QInt`, `dual`, actions, `when`, and `oracle` exports unchanged.
- Update comments that currently claim `W` is the only `QInt` type parameter.
  `W` remains the only user-semantic parameter; `C` is an internal execution
  parameter.

### `src/types/wire.jl`

- No type change.
- Keep `WireID` context-local and opaque.
- Update comments to state that typed handles, not raw `WireID`, carry context
  ownership.

### `src/types/qbool.jl`

- Add `C` to `AbstractQubit` and `QBool`.
- Replace `ctx::AbstractContext` with `ctx::C`.
- Delete the existing commentary defending context erasure.
- Add ergonomic and context-explicit constructor barriers.
- Make `_adopt_qbool` infer `C`.
- Keep preparation lowering and `_escaped_wires` unchanged.

### `src/types/qint.jl`

- Change `QInt{W}` to `QInt{W,C}` with trailing `C`.
- Change `WireRef` to `WireRef{C}`.
- Add context-explicit preparation.
- Change `_adopt_qint`, `getindex`, `_here`, casts, and dual methods accordingly.
- Attach the cyclic `DualTrait` specialization.
- Preserve all `QInt{W}` partial signatures where `C` is irrelevant.
- Keep MSB order, partial-consumption checks, and dual-indexing rejection intact.

### `src/context/abstract.jl`

- Add the `closed` lifecycle flag to `ContextCore`.
- Add `_require_open`.
- Make `teardown!` mark the context closed.
- Do not parameterize `ContextCore`; F16 is about handle field inference, not
  RNG or state-storage specialization.
- No change to `allocate!`, `apply!`, wire maps, consumed sets, or emitters.

### `src/context/eager.jl`

- Provide concrete `_measure_bit!` and `_measure_word!` methods, or retain them
  in `surface/casts.jl` with `EagerContext` dispatch.
- Preserve the existing sampling, collapse, reset, and RNG sequence.

### `src/context/density.jl`

- For the F16-only landing, retain the current loud cast rejection.
- Reserve `_measure_bit!`/`_measure_word!` for M8 record production.
- Continue using `_instrument!` as the physical pinching primitive.
- Do not implement `cases` or classical-record ownership in this bead.

### `src/context/regions.jl`

- Keep `ScopedValue{AbstractContext}` and `current_context()` unchanged.
- Update `_escaped_wires` signatures for parameterized handles.
- Document the context-explicit hot-loop idiom.
- Add closed-context tests to resource teardown.
- Do not attempt to solve arbitrary-container ownership traversal here.

### `src/kernel/views.jl`

- Keep `DualView{H}` and `View{V,H}` arities.
- Add `register_style(::Type{<:AbstractView})`.
- Replace the transform-only trait with `DualTrait`, including group,
  bicharacter, nondegeneracy, and symmetry.
- Make `contextof(view)` delegate to the parent.
- Keep `_parent_wire`, `_escaped_wires`, `_conj`, wrapper identity, and structural
  unwrapping unchanged.

No other kernel process type or lowering should change.

### `src/surface/actions.jl`

- Replace the duplicated `_here` implementation with the typed central helper.
- Validate every operand context before `_act!`.
- Allocate the fresh target of `false ⊻ r` with `QBool(ctx, false)`.
- Require the symmetric bicharacter witness for the phase-entangler.
- Preserve all existing `Base.xor` signatures and return values.

### `src/surface/arithmetic.jl`

- Let existing `QInt{W}` signatures continue to match every `C`.
- Use `QInt{W,C}` where a method must expose the result type.
- Use context-explicit construction in `_fresh_copy`.
- Check every multi-register operand before applying QFT or a controlled phase.
- Keep all signs, phase angles, wire order, and fresh-output semantics unchanged.
- Add the F15 interface documentation alongside the method table.

### `src/surface/casts.jl`

- Dispatch the common cast front end from `AbstractQubit{C}` and `QInt{W,C}`.
- Split bit and word backends by concrete context.
- Keep `convert(Bool, ...)` Eager-only.
- Ensure every check precedes a view basis change or measurement.
- Document the future DM/Tracing result types without implementing M8.

### `src/surface/when.jl`

- Accept parameterized `AbstractQubit` transparently.
- Use `_here` on controls and view parents.
- No change to `_act!`, control-stack representation, clean-ancilla witnesses,
  or control lowering.

### `src/bennett/bridge.jl`

`OracleQuery{Xs}` already stores its register handles in a concrete tuple:

```julia
OracleQuery{Tuple{QInt{W,C}}}
```

Therefore it already carries `C` transitively. Do not add a redundant query
parameter.

Changes:

- update signatures and docstrings to show `QInt{W,C}` where useful;
- validate the target and every `q.xs` context before allocating scratch;
- preserve the absence of any catch-all on `Function`;
- preserve `CompiledOracle`, which stores no handle;
- keep all `Perm` and scratch-wire choreography unchanged.

### `ext/SturmBennettExt.jl`

The extension constructs `CompiledOracle`, not register handles. No structural
change is required. Audit any annotations mentioning `QInt{W}`, but retain them
as valid partial signatures.

### Every handle construction/storage site

The complete shipped list is:

- `QBool` preparation constructors in `src/types/qbool.jl`;
- `_adopt_qbool` in `src/types/qbool.jl`;
- `QInt` preparation constructors in `src/types/qint.jl`;
- `_adopt_qint` in `src/types/qint.jl`;
- `WireRef` construction in `getindex`;
- `DualView` and `View` parent storage in `src/kernel/views.jl`;
- fresh `QBool` construction in `Bool ⊻ AbstractQubit`;
- fresh `QInt` construction in `_fresh_copy`;
- `OracleQuery.xs` in `src/bennett/bridge.jl`;
- Choi harness adoption in `test/choi.jl`;
- manual `OracleQuery(comp, (x,))` fixtures in `test/test_m7_bennett.jl`.

`ContextCore`, `CompiledOracle`, kernel process values, and Orkan state objects
store raw wire/process data, not register handles.

## 11. Inference verification

### 11.1 Baseline

On the current code under Julia 1.12.5:

```text
typeof(q)                    = QBool
fieldtype(typeof(q), :ctx)   = AbstractContext
return_types(_here, QBool)   = AbstractContext

typeof(x)                    = QInt{1}
fieldtype(typeof(x), :ctx)   = AbstractContext
return_types(_here, QInt{1}) = AbstractContext
```

The existing combined M4 helper infers a `QBool` return but loses the concrete
context at every `.ctx` load and `_here` call. M6 has the same problem.

### 11.2 Targets

Add small, stable inspection helpers:

```julia
function _m4_hot!(q::QBool{C}, r::QBool{C}) where {C}
    not!(q)
    q̂ = dual(q)
    q̂ ⊻= r
    return q
end

function _m6_hot!(
    x::QInt{W,C}, y::QInt{W,C}
) where {W,C}
    add!(x, 3)
    x ⊻= y
    x̂ = dual(x)
    x̂ += 1
    return x
end
```

Inspect before and after:

```julia
@code_warntype _here(q, "test")
@code_warntype _m4_hot!(q, r)
@code_warntype Bool(q)
@code_warntype Bool(dual(q))

@code_warntype _here(x, "test")
@code_warntype _m6_hot!(x, y)
@code_warntype x + 1
@code_warntype Int(x)
@code_warntype Int(dual(x))

@code_warntype b ⊻ oracle_query
```

Test context-explicit constructors separately:

```julia
@inferred QBool(ctx, false)
@inferred QInt{4}(ctx, 0)
```

Do **not** require:

```julia
@inferred QBool(false)
```

because `ScopedValue{AbstractContext}` is intentionally dynamic.

### 11.3 Definition of “clean”

For M4/M6 action paths, clean means:

- `QBool{C}`, `QInt{W,C}`, `WireRef{C}`, and view parent types are concrete;
- `.ctx` loads as concrete `C`;
- `_here` returns concrete `C`;
- `_act!`, `apply!`, and context primitives are dispatched with concrete `C`;
- the returned handle/view type is concrete;
- no `Any`, `AbstractContext`, or context-derived union remains in typed IR;
- no dynamic dispatch is attributable to the register’s context field.

For Eager casts, the result must infer as `Bool` or `Int`. For M8 DM/Tracing
casts, it must infer as the exact `ClassicalBit` or `ClassicalWord` type.

The existing `ContextCore.rng::Any` is an independent cold sampling concern. It
must not be used to excuse an `AbstractContext` in action or cast dispatch.

## 12. Test plan

### 12.1 Type propagation

Add named tests covering:

```julia
typeof(QBool(ctx, false)) === QBool{EagerContext}
typeof(QInt{3}(ctx, 0)) === QInt{3,EagerContext}
typeof(x[2]) === WireRef{EagerContext}

dual(q) isa DualView{QBool{EagerContext}}
dual(x) isa DualView{QInt{3,EagerContext}}
view(H, q) isa View{typeof(H),QBool{EagerContext}}

fieldtype(QBool{EagerContext}, :ctx) === EagerContext
fieldtype(QInt{3,EagerContext}, :ctx) === EagerContext
```

Repeat for `DensityMatrixContext`.

Verify partial annotations:

```julia
q isa QBool
x isa QInt{3}
x isa QInt
```

### 12.2 Inference tests

Use `@inferred` on:

- context-explicit `QBool` and `QInt` construction;
- `_adopt_qbool` and `_adopt_qint`;
- `getindex`;
- `dual` and `view`;
- `not!`, register `xor`, dual-view `xor`;
- `add!`, QInt `xor`, fresh `+`, dual-view modulation;
- Eager `Bool`, `Int`, and view casts;
- `_m4_hot!` and `_m6_hot!`;
- `oracle(f,x)` after backend compilation and query application.

M8 later adds:

```julia
@inferred Bool(q_dm)    isa ClassicalBit{DensityMatrixContext,...}
@inferred Int(x_dm)     isa ClassicalWord{W,DensityMatrixContext,...}
@inferred Bool(q_trace) isa ClassicalBit{TracingContext,...}
```

### 12.3 Mixed-context errors

Add tests for:

1. outer Eager handle used inside a nested Eager context;
2. same context type but different context instances;
3. inner handle used after returning to the outer binding;
4. `QInt` arithmetic across contexts;
5. view parent from one context and control from another;
6. `WireRef` mixed with another context;
7. Bennett query input and target from different contexts;
8. context mismatch occurs before any state mutation;
9. direct nested-region return remains valid;
10. mutable-container hidden escape becomes dead and fails on next use;
11. manually rebound torn-down context fails through `_require_open`.

Error messages must name the operation, both context roles, and the boundary
violation. They must not expose raw Orkan slots.

### 12.4 F15 interface tests

- Registers are not subtypes of `Number` or `Integer`.
- `register_style(QBool{C})` and `register_style(QInt{W,C})` are
  `NumberLikeHandleStyle`.
- Views use `AddressingModeStyle`.
- Existing supported overloads remain applicable.
- Unsupported `<` currently fails; a future coherent implementation returns
  `QBool{C}`, never `Bool`.
- `hash` and value equality do not silently inspect or sample quantum state.
- `oracle(f, q::QBool)` remains unavailable; no `Function` catch-all appears.

### 12.5 Bicharacter laws

For each shipped finite trait, exhaust its small domain:

- left character law;
- right character law;
- identity;
- nondegeneracy;
- declared symmetry.

For `QInt`, test separately that:

```julia
action_group(QInt{W,C}, AddActionFamily()) isa Cyclic2PowerGroup{W}
action_group(QInt{W,C}, XorActionFamily()) isa BitVectorGroup{W}
```

Retain and strengthen:

- M4 Choi-level CZ symmetry;
- M6 Pontryagin sign tests;
- `dual(dual(x)) === x` versus QFT² parity;
- translation versus modulation separation.

### 12.6 Existing test files

- `test/test_m3_qbool.jl`: constructor types, concrete field type, Eager cast
  inference, current channel laws.
- `test/test_m4_views.jl`: view parent types, symmetric bicharacter law, CZ Choi
  equality, mixed-context views.
- `test/test_m5_when.jl`: parameterized controls, cross-context rejection,
  unchanged guardrails and clean-ancilla laws.
- `test/test_m6_qint.jl`: `QInt{W,C}`, `WireRef{C}`, fresh-result `C`,
  inference, action-group distinction.
- `test/test_m7_bennett.jl`: query tuple contains `QInt{W,C}`, cross-context
  target rejection before scratch allocation.
- `test/choi.jl`: adopted handles infer the DM context.
- `test/test_contexts.jl`: closed-context lifecycle and unchanged channel output.
- `test/test_regions.jl`: return/re-home, hidden escape, nested contexts.
- `test/test_prd_examples.jl`: existing `::QBool` and `::QInt{W}` annotations
  continue parsing and executing.
- `test/runtests.jl`: include new type/inference/law testsets.

The full existing M3–M7 suite remains the physics regression gate.

## 13. Migration sequence

1. Add failing type-propagation and mixed-context tests.
2. Add `AbstractQRegister{C}` and parameterize `AbstractQubit`.
3. Refactor `QBool` constructors and adoption.
4. Refactor `QInt`, `WireRef`, and fresh-output construction.
5. Centralize `_here`, same-context checks, and closed-context safety.
6. Propagate concrete parent types through views.
7. Refactor actions, arithmetic, `when`, and casts.
8. Add F15 and F19 trait types and law tests.
9. Audit Bennett query storage and application.
10. Run `@code_warntype` comparisons and the complete M0–M7 suite.
11. Land F16 without implementing Tracing or DM classical control.
12. Let M8 replace the DM cast stub and add Tracing methods at the prepared
    dispatch boundary.

## 14. Risks and mitigations

### Dynamic ergonomic construction remains visible to inference

This is inherent to `ScopedValue{AbstractContext}`. The mitigation is honest:
runtime objects are concrete, hot work crosses a typed function barrier, and
allocation-heavy internals use context-explicit constructors.

### Method specialization growth

Specialization is per context **type**, not per context instance. Thousands of
Eager context objects still share one `QBool{EagerContext}` specialization.
Parametric future contexts may create more method instances, but that is the
desired backend/mode specialization.

### Mistaking equal `C` for equal ownership

Two contexts of the same type are distinct state owners. Object-identity checks
remain mandatory and are tested explicitly.

### Redundant context parameters in wrappers

Adding `DualView{C,H}` or `OracleQuery{C,Xs}` would expose more parameters,
break existing partial signatures, and permit `C` to disagree with the parent.
The parent type is the single source of truth.

### Premature M8 coupling

Adding token/IR semantics during F16 would mix a type-stability refactor with
new channel execution and ownership rules. The proposal defines exact future
dispatch signatures but keeps implementation sequenced behind M8.

### Broad F15 guard methods

Fail-loud equality/hash guards may reveal generic code that accidentally treated
handles as values. That is desirable, but these methods should land with focused
tests for internal dictionaries and test helpers.

### User-defined contexts

A new context subtype must implement the appropriate cast backend and return a
concrete result. Absence of such a method should be a descriptive context
capability error, not fallback to Eager sampling or a union result.

## 15. Alternatives rejected

### Keep `ctx::AbstractContext`

Rejected: it forces abstract field loads and dynamic context dispatch on every
action and cast.

### Put the context instance in a value type parameter

Rejected: mutable context objects are not suitable value parameters, and
specializing per instance would be catastrophic even if encoded through IDs.

### Parameterize `WireID`

Rejected for F16. `WireID{C}` would distinguish context implementations but
still not distinguish two instances of the same context type. It would also
metastasize through every raw kernel tuple without removing the identity check.

### Change `CURRENT_CONTEXT` to `ScopedValue{Any}`

Rejected: strictly less information.

### One `ScopedValue` per concrete context type

Rejected: dynamic selection among those values recreates the same inference
problem and complicates task inheritance.

### Return `Union{Bool,ClassicalBit}` from casts

Rejected: it reintroduces context erasure at the busiest M8 boundary. The
handle’s `C` must select one concrete method and result.

### A separate `casttype(C)` execution trait

Rejected: it duplicates the context method table. Direct multiple dispatch is
the Julia-native single source of truth.

### Make registers subtype `Number` or `Integer`

Rejected by F15. It would imply value equality, hashing, total scalar comparison,
and non-effectful numeric behavior that quantum handles do not possess.

### Add `C` before `W`

Rejected because it breaks the public `QInt{W}` spelling and width-generic
dispatch. `C` must be trailing.

### Add `C` redundantly to views and queries

Rejected because the concrete parent handle already carries it.

## 16. Open questions requiring human ruling

1. **Wide `Int(x)` results (F23).** For `W ≥ Sys.WORD_SIZE`, a sampled value
   cannot fit in host `Int`. F16 must not silently choose between rejecting the
   width, returning `BigInt`, or defining a fixed-width classical word. This
   needs a separate ruling.

2. **Full ownership traversal (F17).** F16 makes hidden escaped aliases fail on
   use, but it does not discover handles buried in arbitrary structs,
   closures, globals, or tasks at region exit. The extensible ownership protocol
   remains separate work.

3. **`QMod` parameter policy (F24).** Static modulus, runtime modulus, and
   representation parameters must be decided before adding its trailing `C`.

4. **Identity API visibility.** This proposal makes `===` the user-visible
   binding-identity test and keeps context/wire identity helpers internal.
   If a public `same_register` predicate is wanted, it should be ruled
   separately; it must never inspect state.

5. **Coherent comparison surface.** F15 establishes that a comparator returns
   `QBool{C}`, not host `Bool`, but the exact set of comparison overloads and
   their reversible garbage discipline is not implemented in M0–M7. F16 should
   publish the trait contract without inventing the comparator circuit.

## 17. Acceptance criteria

The refactor is complete when:

- every owning or borrowed shipped register has concrete `ctx::C`;
- `QBool` and `QInt{W}` source annotations remain valid;
- views and Bennett queries retain `C` through concrete parent types;
- every mixed-context operation fails before backaction;
- torn-down handles cannot reach FFI;
- Eager casts infer `Bool`/`Int`;
- the DM and Tracing cast extension slots have concrete documented result types;
- M4/M6 hot paths contain no context-derived `AbstractContext` or `Any`;
- the number-like operator surface is explicit and no `Number`/`Integer`
  subtyping is added;
- dual traits carry a selected nondegenerate bicharacter and an explicit
  symmetry law;
- all existing Choi, Pontryagin, region, control, and Bennett laws remain
  unchanged.

The central rule is concise: **dynamic scope chooses the context instance once;
the register type carries its concrete context kind thereafter; every operation
still verifies the owning instance.**