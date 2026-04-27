"""
    QInt{W}

A W-qubit quantum integer register. Stores W wires in little-endian order:
wires[1] is the least-significant bit (weight 2^0), wires[W] is the MSB.

Linear resource semantics: a QInt{W} is consumed when converted to Int
(measured via type boundary) or explicitly discarded. Individual wires
can be accessed via getindex to get a QBool view.

Width W is a type parameter — Julia specialises on it. Use `where {W}`
dispatch, not runtime branching on width.
"""
mutable struct QInt{W} <: Quantum
    wires::NTuple{W, WireID}
    ctx::AbstractContext
    consumed::Bool
end

classical_type(::Type{QInt{W}}) where {W} = _bennett_arg_type(W; signed=true)
classical_compile_kwargs(::Type{<:QInt{W}}) where {W} = (bit_width = W,)

# ── Linearity checks ─────────────────────────────────────────────────────────

function check_live!(q::QInt{W}) where {W}
    q.consumed && error("Linear resource violation: QInt{$W} already consumed")
end

function consume!(q::QInt{W}) where {W}
    check_live!(q)
    q.consumed = true
end

# ── Wire views ───────────────────────────────────────────────────────────────

"""
    _qbool_views(reg::QInt{W}) -> NTuple{W, QBool}

Create non-owning QBool views of each wire in a QInt register.
Stack-allocated (NTuple), zero heap allocation for W ≤ 30.

These views alias the register's wires. They must NOT be consumed or
discarded — they are borrowed references for applying per-wire operations.
"""
@inline function _qbool_views(reg::QInt{W}) where {W}
    ctx = reg.ctx
    ntuple(i -> QBool(reg.wires[i], ctx, false), Val(W))
end

# ── Constructors ─────────────────────────────────────────────────────────────

"""
    QInt{W}(ctx::AbstractContext, value::Integer)

Allocate W qubits, prepare the classical value in computational basis.
Little-endian: wire i holds bit (i-1) of value. Bits set to 1 get X = Ry(π).
"""
function QInt{W}(ctx::AbstractContext, value::Integer) where {W}
    W >= 1 || error("QInt width must be ≥ 1, got $W")
    maxval = 1 << W
    (0 <= value < maxval) || error(
        "QInt{$W}: value $value out of range [0, $(maxval - 1)]"
    )

    wires = ntuple(W) do i
        wire = allocate!(ctx)
        if (value >> (i - 1)) & 1 == 1
            apply_ry!(ctx, wire, π)  # X gate: |0⟩ → |1⟩
        end
        wire
    end
    QInt{W}(wires, ctx, false)
end

# ── Internal: promote classical → QInt{W} for mixed operations (P8) ──────────

"""
    _promote_to_qint(ctx::AbstractContext, value::Integer, ::Val{W}) -> QInt{W}

Promote a classical Integer to QInt{W} for mixed-type operations (P8).
Applies mod 2^W to handle overflow (same semantics as modular arithmetic
in the adder circuit). Context is provided explicitly from the quantum operand.
"""
@inline function _promote_to_qint(ctx::AbstractContext, value::Integer, ::Val{W}) where {W}
    QInt{W}(ctx, mod(value, 1 << W))
end

"""
    QInt{W}(value::Integer)

Prepare QInt{W} in the current context.
"""
QInt{W}(value::Integer) where {W} = QInt{W}(current_context(), value)

"""
    QInt{W}(f::Function, ctx::AbstractContext, value::Integer)
    QInt{W}(f::Function, value::Integer)

Do-block constructor (bead Sturm.jl-cbl). Allocates a `QInt{W}` register
holding `value`, runs `f(reg)` with `reg` in scope, and partial-traces
`reg` at block exit — regardless of normal return OR exception. Mirrors
Julia's `open(f, path) do stream … end` pattern.

```julia
@context EagerContext() begin
    result = QInt{8}(42) do reg
        Int(reg)        # consumes reg; do-block returns the measurement
    end
end
```

If the body consumes `reg` (via `Int(reg)` or an explicit `ptrace!(reg)`),
the finally clause skips the partial-trace — no double-consume. The
body's return value is propagated.
"""
function QInt{W}(f::Function, ctx::AbstractContext, value::Integer) where {W}
    q = QInt{W}(ctx, value)
    try
        return f(q)
    finally
        if !q.consumed
            ptrace!(q)
        end
    end
end

QInt{W}(f::Function, value::Integer) where {W} = QInt{W}(f, current_context(), value)

# ── Type boundary: measurement ───────────────────────────────────────────────
#
# P2: `Int(q)` is the EXPLICIT cast (silent). `convert(Int, q)` — which Julia
# invokes for implicit `x::Int = qi` assignments — emits a one-per-site
# warning then delegates to the constructor. See src/types/quantum.jl for the
# warning helper + `with_silent_casts` opt-out, and bead Sturm.jl-f23.

"""
    Base.Int(q::QInt{W}) -> Int

Measure all W qubits, assemble the classical integer in little-endian order.
Consumes the QInt (linear resource).
"""
function Base.Int(q::QInt{W}) where {W}
    check_live!(q)
    result = 0
    for i in 1:W
        outcome = _blessed_measure!(q.ctx, q.wires[i])   # blessed cast path
        if outcome
            result |= (1 << (i - 1))
        end
    end
    q.consumed = true
    return result
end

function Base.convert(::Type{Int}, q::QInt{W}) where {W}
    _warn_implicit_cast(QInt{W}, Int)
    return Int(q)
end

# ── Wire access ──────────────────────────────────────────────────────────────

"""
    Base.getindex(q::QInt{W}, i::Int) -> QBool

Return a QBool view of wire i (1-indexed, LSB=1). The QBool shares the
same WireID — consuming the QBool consumes that wire in the QInt.
"""
function Base.getindex(q::QInt{W}, i::Int) where {W}
    check_live!(q)
    (1 <= i <= W) || error("QInt{$W}: index $i out of range [1, $W]")
    QBool(q.wires[i], q.ctx, false)
end

"""Width of the quantum integer register."""
Base.length(::QInt{W}) where {W} = W

"""
    ptrace!(q::QInt{W})

Partial trace — discard all W wires of the register (measure-and-discard each,
outcomes thrown away). Marks the register consumed.

`discard!` remains as a backcompat alias. Prefer `ptrace!` (bead diy).
"""
function ptrace!(q::QInt{W}) where {W}
    check_live!(q)
    for i in 1:W
        deallocate!(q.ctx, q.wires[i])
    end
    q.consumed = true
end

# ── Quantum ripple-carry adder ───────────────────────────────────────────────
# Ref: Vedral, Barenco, Ekert (1996), "Quantum Networks for Elementary
# Arithmetic Operations", Phys. Rev. A 54(1):147-153.
# See docs/physics/vedral_1996_adder.md
#
# Computes s = (a + b) mod 2^W using the 4 primitives only:
#   ⊻= (CNOT) and when() { ⊻= } (Toffoli)

"""
    _carry_compute!(ctx, c_in, a, b, c_out)

Compute carry-out = majority(a, b, c_in) into c_out (which starts at |0⟩).
Does NOT modify a, b, or c_in — they are used as controls only.

carry_out = a∧b ⊕ a∧c_in ⊕ b∧c_in = majority(a, b, c_in)

Uses 3 Toffoli gates (when(){⊻=}).
"""
function _carry_compute!(ctx::AbstractContext, c_in::WireID, a::WireID, b::WireID, c_out::WireID)
    push_control!(ctx, a); apply_cx!(ctx, b, c_out); pop_control!(ctx)
    push_control!(ctx, a); apply_cx!(ctx, c_in, c_out); pop_control!(ctx)
    push_control!(ctx, b); apply_cx!(ctx, c_in, c_out); pop_control!(ctx)
end

"""
    _carry_uncompute!(ctx, c_in, a, b, c_out)

Inverse of _carry_compute!. Restores c_out to |0⟩.
Each Toffoli is self-inverse; apply in reverse order.
a, b, c_in must be in their ORIGINAL states (unmodified by sum computation).
"""
function _carry_uncompute!(ctx::AbstractContext, c_in::WireID, a::WireID, b::WireID, c_out::WireID)
    push_control!(ctx, b); apply_cx!(ctx, c_in, c_out); pop_control!(ctx)
    push_control!(ctx, a); apply_cx!(ctx, c_in, c_out); pop_control!(ctx)
    push_control!(ctx, a); apply_cx!(ctx, b, c_out); pop_control!(ctx)
end

"""
    Base.:+(a::QInt{W}, b::QInt{W}) -> QInt{W}

Quantum ripple-carry addition. Returns (a + b) mod 2^W.
Both a and b are consumed (linear resources).

Circuit structure:
  1. Forward: compute all carries using only Toffolis (a, b untouched)
  2. Sum: compute sum bits into b (b[i] ⊻= a[i] ⊻= carry[i])
  3. Backward: uncompute carries using original a, b_orig
     (b was modified in step 2, but we undo that temporarily per stage)
"""
function Base.:+(a::QInt{W}, b::QInt{W}) where {W}
    a.ctx === b.ctx || error("Cannot add QInts from different contexts")
    check_live!(a)
    check_live!(b)
    ctx = a.ctx
    sum_wires = _add_with_carry_in!(ctx, a.wires, b.wires, false)
    a.consumed = true
    result = QInt{W}(sum_wires, ctx, false)
    b.consumed = true
    return result
end

# ── Mixed-type addition: quantum promotion (P8) ─────────────────────────────

Base.:+(a::QInt{W}, b::Integer) where {W} = (check_live!(a); a + _promote_to_qint(a.ctx, b, Val(W)))
Base.:+(a::Integer, b::QInt{W}) where {W} = (check_live!(b); _promote_to_qint(b.ctx, a, Val(W)) + b)

# ── Subtraction ──────────────────────────────────────────────────────────────

"""
    _add_with_carry_in!(ctx, a_wires, b_wires, carry_in::Bool) -> NTuple{W, WireID}

Internal: ripple-carry add a + b with an initial carry-in bit.
Returns b_wires (now holding sum bits). Discards a_wires and carry ancillas.
"""
function _add_with_carry_in!(ctx::AbstractContext, a_wires::NTuple{W, WireID},
                              b_wires::NTuple{W, WireID}, carry_in::Bool) where {W}
    carries = ntuple(_ -> allocate!(ctx), W)

    # Set initial carry if carry_in
    if carry_in
        apply_ry!(ctx, carries[1], π)  # carry[1] = |1⟩
    end

    # Phase 1: Forward carry propagation
    for i in 1:(W - 1)
        _carry_compute!(ctx, carries[i], a_wires[i], b_wires[i], carries[i + 1])
    end

    # Phase 2: Compute sum bits
    for i in 1:W
        apply_cx!(ctx, a_wires[i], b_wires[i])
        apply_cx!(ctx, carries[i], b_wires[i])
    end

    # Phase 3: Uncompute carries
    for i in (W - 1):-1:1
        apply_cx!(ctx, carries[i], b_wires[i])
        apply_cx!(ctx, a_wires[i], b_wires[i])
        _carry_uncompute!(ctx, carries[i], a_wires[i], b_wires[i], carries[i + 1])
        apply_cx!(ctx, a_wires[i], b_wires[i])
        apply_cx!(ctx, carries[i], b_wires[i])
    end

    # Discard carries (carry[1] may be |1⟩ if carry_in was true and not consumed)
    for i in 1:W
        deallocate!(ctx, carries[i])
    end

    # Discard a's wires
    for i in 1:W
        deallocate!(ctx, a_wires[i])
    end

    return b_wires
end

"""
    Base.:-(a::QInt{W}, b::QInt{W}) -> QInt{W}

Quantum subtraction: (a - b) mod 2^W via 2's complement.
a - b = a + ~b + 1, with +1 folded as initial carry-in.

Both a and b are consumed.
"""
function Base.:-(a::QInt{W}, b::QInt{W}) where {W}
    a.ctx === b.ctx || error("Cannot subtract QInts from different contexts")
    check_live!(a)
    check_live!(b)
    ctx = a.ctx

    # Flip all bits of b: ~b
    for i in 1:W
        apply_ry!(ctx, b.wires[i], π)
    end

    # a + ~b + 1 (carry_in=true provides the +1)
    sum_wires = _add_with_carry_in!(ctx, a.wires, b.wires, true)
    a.consumed = true
    result = QInt{W}(sum_wires, ctx, false)
    b.consumed = true
    return result
end

# ── Mixed-type subtraction: quantum promotion (P8) ──────────────────────────

Base.:-(a::QInt{W}, b::Integer) where {W} = (check_live!(a); a - _promote_to_qint(a.ctx, b, Val(W)))
Base.:-(a::Integer, b::QInt{W}) where {W} = (check_live!(b); _promote_to_qint(b.ctx, a, Val(W)) - b)

# ── Bitwise XOR: W parallel CNOTs (primitive 4) ─────────────────────────────
# Matches QBool.xor semantics: mutate left, preserve right. `a ⊻ b` is a
# reversible bit-parallel operation — the W CNOTs never need ancillae.

"""
    Base.xor(a::QInt{W}, b::QInt{W}) -> QInt{W}

Bitwise XOR: `a_i ⊻= b_i` for every bit `i`, via W parallel CNOTs with
`b[i]` as control and `a[i]` as target (primitive 4). Mutates `a`
in place; `b` is preserved and remains live. Returns `a`.

The in-place / preserving convention matches [`Base.xor`](@ref) on
`QBool` — reversible CNOT semantics, no ancillae.
"""
function Base.xor(a::QInt{W}, b::QInt{W}) where {W}
    a.ctx === b.ctx || error("Cannot xor QInts from different contexts")
    check_live!(a)
    check_live!(b)
    ctx = a.ctx
    for i in 1:W
        apply_cx!(ctx, b.wires[i], a.wires[i])
    end
    return a
end

# Mixed-type XOR: quantum promotion (P8). Classical operand is a known
# constant, so there's no entanglement — each set bit becomes an X gate.

"""
    Base.xor(a::QInt{W}, b::Integer) -> QInt{W}

Bitwise XOR with a classical constant. For every bit `i` of `b` that is 1,
apply X to `a.wires[i]`. Mutates `a` in place; returns `a`. No ancillae.
`b` is reduced mod 2^W (matches the P8 promotion rule in `_promote_to_qint`).
"""
function Base.xor(a::QInt{W}, b::Integer) where {W}
    check_live!(a)
    bmod = mod(b, 1 << W)
    for i in 1:W
        if (bmod >> (i - 1)) & 1 == 1
            apply_ry!(a.ctx, a.wires[i], π)
        end
    end
    return a
end

"""
    Base.xor(a::Integer, b::QInt{W}) -> QInt{W}

Mirror of [`Base.xor(::Bool, ::QBool)`](@ref): prepare a fresh `QInt{W}`
holding the classical value (mod 2^W), then CNOT the quantum operand
into it bit-for-bit. The quantum operand is preserved (used only as a
control). Returns the fresh QInt.
"""
function Base.xor(a::Integer, b::QInt{W}) where {W}
    check_live!(b)
    ctx = b.ctx
    target = QInt{W}(ctx, mod(a, 1 << W))
    for i in 1:W
        apply_cx!(ctx, b.wires[i], target.wires[i])
    end
    return target
end

# ── Bitwise AND: Toffoli into fresh register ─────────────────────────────────
# AND is not reversible in place — `c = a ∧ b` from (a, b) is a 2-to-1 map.
# Reversible construction: allocate a fresh target register at |0⟩ and
# Toffoli each bit into it. Both operands remain alive (used as controls).

"""
    Base.:&(a::QInt{W}, b::QInt{W}) -> QInt{W}

Bitwise AND. Allocates a fresh `QInt{W}` at `|0⟩` and Toffolis each pair
`(a_i, b_i)` into it, so the result holds `a ∧ b`. Both `a` and `b` are
preserved — used only as Toffoli controls.
"""
function Base.:&(a::QInt{W}, b::QInt{W}) where {W}
    a.ctx === b.ctx || error("Cannot AND QInts from different contexts")
    check_live!(a)
    check_live!(b)
    ctx = a.ctx
    target_wires = ntuple(_ -> allocate!(ctx), Val(W))
    for i in 1:W
        apply_ccx!(ctx, a.wires[i], b.wires[i], target_wires[i])
    end
    return QInt{W}(target_wires, ctx, false)
end

"""
    Base.:&(a::QInt{W}, b::Integer) -> QInt{W}

Bitwise AND with a classical constant. Allocates a fresh target at `|0⟩`
and CNOTs `a_i` into it for every bit of `b` that is 1; bits where `b`
is 0 stay at `|0⟩`. `a` is preserved. `b` is reduced mod 2^W.
"""
function Base.:&(a::QInt{W}, b::Integer) where {W}
    check_live!(a)
    ctx = a.ctx
    bmod = mod(b, 1 << W)
    target_wires = ntuple(_ -> allocate!(ctx), Val(W))
    for i in 1:W
        if (bmod >> (i - 1)) & 1 == 1
            apply_cx!(ctx, a.wires[i], target_wires[i])
        end
    end
    return QInt{W}(target_wires, ctx, false)
end

Base.:&(a::Integer, b::QInt{W}) where {W} = b & a

# ── Bitwise OR: a ⊕ b ⊕ (a ∧ b) into fresh register ──────────────────────────
# Identity: a ∨ b = a ⊕ b ⊕ (a ∧ b). With target starting at |0⟩ this is
# 2 CNOTs then a Toffoli — no temporary X gates, both operands preserved.

"""
    Base.:|(a::QInt{W}, b::QInt{W}) -> QInt{W}

Bitwise OR. Allocates a fresh `QInt{W}` at `|0⟩` and applies
`CNOT(a_i) ; CNOT(b_i) ; Toffoli(a_i, b_i)` to each target bit so that
`c_i = a_i ⊕ b_i ⊕ (a_i ∧ b_i) = a_i ∨ b_i`. Both operands preserved.
"""
function Base.:|(a::QInt{W}, b::QInt{W}) where {W}
    a.ctx === b.ctx || error("Cannot OR QInts from different contexts")
    check_live!(a)
    check_live!(b)
    ctx = a.ctx
    target_wires = ntuple(_ -> allocate!(ctx), Val(W))
    for i in 1:W
        apply_cx!(ctx, a.wires[i], target_wires[i])                  # target = a
        apply_cx!(ctx, b.wires[i], target_wires[i])                  # target = a ⊕ b
        apply_ccx!(ctx, a.wires[i], b.wires[i], target_wires[i])     # target = a ⊕ b ⊕ ab = a ∨ b
    end
    return QInt{W}(target_wires, ctx, false)
end

"""
    Base.:|(a::QInt{W}, b::Integer) -> QInt{W}

Bitwise OR with a classical constant. Where the classical bit is 1 the
target bit is forced to 1 (X on `|0⟩`); where the classical bit is 0 the
target bit becomes `a_i` (CNOT from `a`). Preserves `a`. `b` is reduced
mod 2^W.
"""
function Base.:|(a::QInt{W}, b::Integer) where {W}
    check_live!(a)
    ctx = a.ctx
    bmod = mod(b, 1 << W)
    target_wires = ntuple(_ -> allocate!(ctx), Val(W))
    for i in 1:W
        if (bmod >> (i - 1)) & 1 == 1
            apply_ry!(ctx, target_wires[i], π)          # target_i = 1
        else
            apply_cx!(ctx, a.wires[i], target_wires[i])  # target_i = a_i
        end
    end
    return QInt{W}(target_wires, ctx, false)
end

Base.:|(a::Integer, b::QInt{W}) where {W} = b | a

# ── Shifts with classical amount: wire permutation into fresh register ───────
# Logical (zero-fill) shifts matching Julia's UInt semantics. n ≥ W collapses
# to all zeros. Operand preserved; classical amount parameterises the CNOT
# pattern — no mux, no quantum shift amount.

"""
    Base.:<<(a::QInt{W}, n::Integer) -> QInt{W}

Logical left shift by the classical amount `n`. Allocates a fresh `QInt{W}`
at `|0⟩` and CNOTs `a.wires[j] → target.wires[j+n]` for each `j` whose
shifted position still lies inside the register. `n ≥ W` returns an
all-zero register. Preserves `a`.
"""
function Base.:<<(a::QInt{W}, n::Integer) where {W}
    check_live!(a)
    n >= 0 || error("QInt shift amount must be non-negative; got $n")
    ctx = a.ctx
    target_wires = ntuple(_ -> allocate!(ctx), Val(W))
    if n < W
        for j in 1:(W - n)
            apply_cx!(ctx, a.wires[j], target_wires[j + n])
        end
    end
    return QInt{W}(target_wires, ctx, false)
end

"""
    Base.:>>(a::QInt{W}, n::Integer) -> QInt{W}

Logical right shift by the classical amount `n`. Mirror of [`Base.:<<`](@ref)
on `QInt`: bits `a.wires[j]` for `j > n` land at `target.wires[j-n]`; the
top `n` bits stay at `|0⟩`. `n ≥ W` returns an all-zero register.
Preserves `a`.
"""
function Base.:>>(a::QInt{W}, n::Integer) where {W}
    check_live!(a)
    n >= 0 || error("QInt shift amount must be non-negative; got $n")
    ctx = a.ctx
    target_wires = ntuple(_ -> allocate!(ctx), Val(W))
    if n < W
        for j in (n + 1):W
            apply_cx!(ctx, a.wires[j], target_wires[j - n])
        end
    end
    return QInt{W}(target_wires, ctx, false)
end

# ── Comparison ───────────────────────────────────────────────────────────────

# ── Comparison operators (`<`, `==`) intentionally NOT defined ──────────────
#
# Quantum `<` and `==` have no single unitary meaning. A prior v0.1 hack
# measured both operands classically and returned a deterministic QBool;
# that silently collapsed entanglement and violated P1 (functions are channels)
# and P9 (quantum registers are a numeric type for reversible dispatch).
# Users who want a quantum comparator write a classical Julia function and
# route it through `oracle(f, q)` from Bennett.jl, which compiles to a
# reversible circuit. See Sturm.jl-w4g.
