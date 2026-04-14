"""
    QBool

Single-qubit quantum boolean. The control type for `when` blocks.
Wraps a WireID in a context. Tracks linear resource usage.
"""
mutable struct QBool <: Quantum
    wire::WireID
    ctx::AbstractContext
    consumed::Bool
end

classical_type(::Type{QBool}) = Int8
classical_compile_kwargs(::Type{QBool}) = (bit_width = 1,)

"""Check that a QBool has not been consumed (measured, discarded, or otherwise destroyed)."""
function check_live!(q::QBool)
    q.consumed && error("Linear resource violation: QBool on wire $(q.wire) already consumed")
end

"""Mark a QBool as consumed. Errors if already consumed."""
function consume!(q::QBool)
    check_live!(q)
    q.consumed = true
end

"""Explicitly discard a QBool (partial trace)."""
function discard!(q::QBool)
    consume!(q)
    deallocate!(q.ctx, q.wire)
end

# ── BlochProxy: enables q.θ += δ and q.φ += δ syntax ─────────────────────────

"""
    BlochProxy

Returned by `q.θ` and `q.φ`. Only `+=` and `-=` are meaningful operations.
You cannot read the Bloch angles — that would require measurement.
"""
struct BlochProxy
    wire::WireID
    axis::Symbol   # :θ or :φ
    ctx::AbstractContext
    parent::QBool  # to check liveness
end

@inline function Base.getproperty(q::QBool, s::Symbol)
    if s === :θ
        check_live!(q)
        return BlochProxy(getfield(q, :wire), :θ, getfield(q, :ctx), q)
    elseif s === :φ
        check_live!(q)
        return BlochProxy(getfield(q, :wire), :φ, getfield(q, :ctx), q)
    else
        return getfield(q, s)
    end
end

# ── q.θ += δ  /  q.φ += δ syntax ─────────────────────────────────────────────
# Julia desugars `q.θ += δ` into `q.θ = q.θ + δ`.
# `q.θ` returns a BlochProxy. `BlochProxy + δ` applies the rotation and returns
# a sentinel. `q.θ = sentinel` is a no-op (the rotation already happened).

struct _RotationApplied end
const ROTATION_APPLIED = _RotationApplied()

@inline function Base.:+(proxy::BlochProxy, δ::Real)
    check_live!(proxy.parent)
    if proxy.axis === :θ
        apply_ry!(proxy.ctx, proxy.wire, δ)
    else
        apply_rz!(proxy.ctx, proxy.wire, δ)
    end
    return ROTATION_APPLIED
end

function Base.:-(proxy::BlochProxy, δ::Real)
    return proxy + (-δ)
end

function Base.setproperty!(q::QBool, s::Symbol, val::_RotationApplied)
    # No-op: the rotation was already applied in Base.:+
    return val
end

# ── Measurement via type boundary ─────────────────────────────────────────────

function Base.convert(::Type{Bool}, q::QBool)
    check_live!(q)
    result = measure!(q.ctx, q.wire)
    q.consumed = true
    return result
end

Base.Bool(q::QBool) = convert(Bool, q)

# ── Entanglement: a ⊻= b (CNOT: b controls, a target) ───────────────────────

function Base.xor(a::QBool, b::QBool)
    check_live!(a)
    check_live!(b)
    a.ctx === b.ctx || error("Cannot entangle qubits from different contexts")
    apply_cx!(a.ctx, b.wire, a.wire)  # b controls, a is target
    return a
end

# ── Mixed-type XOR: quantum promotion (P8) ──────────────────────────────────

"""
    xor(a::QBool, b::Bool)

Mixed quantum-classical XOR (P8). If b is true, flip a (X gate via Ry(π)).
If b is false, no-op. Returns a. No new qubit allocated — the classical
value is a known constant, so no entanglement is needed.
"""
function Base.xor(a::QBool, b::Bool)
    check_live!(a)
    if b
        apply_ry!(a.ctx, a.wire, π)  # X gate: flip a
    end
    return a
end

"""
    xor(a::Bool, b::QBool)

Mixed classical-quantum XOR (P8). Promotes classical `a` to a fresh QBool,
then applies CNOT with b as control. Returns a new QBool holding a ⊻ b.
b is not consumed (used as control only, same as QBool-QBool xor).
Context is extracted from the quantum operand b.
"""
function Base.xor(a::Bool, b::QBool)
    check_live!(b)
    ctx = b.ctx
    target = QBool(ctx, Float64(a))
    apply_cx!(ctx, b.wire, target.wire)  # b controls, target is target
    return target
end

# ── Preparation ───────────────────────────────────────────────────────────────

"""
    QBool(ctx::AbstractContext, p::Real)

Prepare a qubit with P(|1>) = p.
Applies Ry(2 * asin(√p)) to |0>.
"""
function QBool(ctx::AbstractContext, p::Real)
    (0 <= p <= 1) || error("Preparation probability p must be in [0, 1], got $p")
    wire = allocate!(ctx)
    if p > 0
        angle = 2 * asin(sqrt(Float64(p)))
        apply_ry!(ctx, wire, angle)
    end
    QBool(wire, ctx, false)
end

"""
    QBool(p::Real)

Prepare a qubit using the current context (from task-local storage).
"""
QBool(p::Real) = QBool(current_context(), p)
