"""
    QMod{d, K}

Single d-level quantum register ("qudit"). Stores the computational-basis
label k ∈ {0, …, d−1} in K = ⌈log₂ d⌉ contiguous qubit wires using a
little-endian binary encoding (`wires[1]` = LSB, `wires[K]` = MSB).

Parallels the classical `Mod{d}` from Mods.jl: the user-facing API is
modular arithmetic on Z/dZ. At d=2, `QMod{2, 1}` is *layout*-isomorphic to
[`QBool`](@ref) but a distinct type — same reason Julia keeps `Bool` and
`Mod{2}` separate (logical vs. arithmetic API). Use `QBool` for boolean
controls (`when`, `xor`); reach for `QMod{2}` only when modular semantics
matter. `Bool(::QMod{2})` is intentionally not defined.

# Type parameters
  * `d` — dimension; must be an `Int` and ≥ 2. Validated at construction.
  * `K` — derived storage width in qubits, `K = ⌈log₂ d⌉`. Hidden second
    parameter present because Julia cannot evaluate `K = ⌈log₂ d⌉` inside
    a struct field type annotation. Same trick `QCoset{W, Cpad, Wtot}`
    uses (`src/types/qcoset.jl:45-50`). Users normally write `QMod{d}`
    and let dispatch fill in K via `where {d, K}` or `where {d}`.

# Wire layout
Identical little-endian binary encoding to `QInt{W}`, so a future
`QInt{W, d}` register may aggregate `QMod{d}` digits without re-deriving
the encoding.

# Leakage at non-power-of-2 d
For d ∉ {2, 4, 8, 16, …}, the K-bit binary encoding has unused patterns
(e.g. `|11⟩` at d=3, K=2 represents label 3 ≥ d). A buggy primitive could
drive amplitude into these unused levels. Three layers protect against
this:

  1. **Trust prep.** Fresh wires from `allocate!` are `|0⟩`, always
     in-subspace. No runtime check at prep time.
  2. **Primitive proof obligation** (later beads `Sturm.jl-{ak2, os4, mle,
     p38}`). Each subsequent primitive must preserve the d-level subspace
     by construction (spin-`j` rotations close on the (2j+1)-dimensional
     irrep; SUM is mod-d arithmetic).
  3. **Unconditional post-measurement check** (this bead). [`Base.Int`](@ref)
     errors loudly with a clear message if the decoded bitstring is ≥ d.
     O(1) classical-side check, runs on every measurement.

A debug-mode amplitude-buffer sweep (TLS-toggled, default off) is filed
as a follow-on bead.

# Bennett interop
[`classical_type`](@ref) is intentionally NOT defined for `QMod`. Bennett.jl
currently lowers classical functions with mod-2^W arithmetic, not mod-d, so
`oracle(f, q::QMod{d})` would silently produce wrong results. The missing
method makes the failure loud (`MethodError`) instead. Tracked as
`Sturm.jl-jba` ("QMod{d} Bennett interop — modular arithmetic in
reversible IR"). Use `QBool` / `QInt` for Bennett-compiled oracles.

# References
  * `docs/physics/qudit_magic_gate_survey.md` §8 (locked design decisions).
  * `docs/physics/qudit_primitives_survey.md` (spin-`j` justification).
  * `docs/design/qmod_design_proposer_{a,b}.md` (3+1 design round).

See bead `Sturm.jl-9aa`.
"""
mutable struct QMod{d, K} <: Quantum
    wires::NTuple{K, WireID}
    ctx::AbstractContext
    consumed::Bool
end

"""
    _qmod_nbits(d::Int) -> Int

Storage width in qubits for a d-level register: `K = ⌈log₂ d⌉`. Pure
integer arithmetic via `leading_zeros(d - 1)` — no `log2` call. Returns
1 at d=2; 2 at d∈{3,4}; 3 at d∈{5,6,7,8}; etc.
"""
@inline function _qmod_nbits(d::Int)
    d >= 2 || error("_qmod_nbits: d must be ≥ 2, got $d")
    return 64 - leading_zeros(d - 1)
end

# ── Linearity checks ─────────────────────────────────────────────────────────

function check_live!(q::QMod{d, K}) where {d, K}
    q.consumed && error("Linear resource violation: QMod{$d} already consumed")
end

function consume!(q::QMod{d, K}) where {d, K}
    check_live!(q)
    q.consumed = true
end

"""
    ptrace!(q::QMod{d, K})

Partial trace — discard all K underlying qubit wires (measure-and-discard
each, outcomes thrown away). Marks the register consumed.

`discard!` remains as a backcompat alias. Prefer `ptrace!` (bead diy).
"""
function ptrace!(q::QMod{d, K}) where {d, K}
    check_live!(q)
    for i in 1:K
        deallocate!(q.ctx, q.wires[i])
    end
    q.consumed = true
end

"""Storage width of the QMod register (K underlying qubit wires)."""
Base.length(::QMod{d, K}) where {d, K} = K

# ── Constructors ─────────────────────────────────────────────────────────────

"""
    QMod{d}(ctx::AbstractContext)

Allocate K = ⌈log₂ d⌉ fresh qubit wires and prepare the d-level register
in `|0⟩_d` (every underlying qubit at `|0⟩`, encoding the classical label
0). Per `qudit_magic_gate_survey.md` §8.1, prep is always `|0⟩_d`;
superpositions come from later primitives 2–6.

# Validation (fail loud, Rule 1)
  * `d` must be an `Int`. Non-Int type parameters error here rather than
    later in `_qmod_nbits` with a confusing message.
  * `d ≥ 2`. A 1-level "system" has no state to manipulate.
"""
function QMod{d}(ctx::AbstractContext) where {d}
    (d isa Int) || error(
        "QMod{d}: d must be an Int, got $d::$(typeof(d))"
    )
    d >= 2 || error("QMod{d}: d must be ≥ 2, got $d")
    K = _qmod_nbits(d)
    wires = ntuple(_ -> allocate!(ctx), Val(K))
    return QMod{d, K}(wires, ctx, false)
end

"""
    QMod{d}()

Convenience constructor: prepares using the current context (TLS).
Errors if no `@context` block is active.
"""
QMod{d}() where {d} = QMod{d}(current_context())

# ── P2: measurement via type-boundary cast ───────────────────────────────────
#
# `Int(q::QMod{d})` is the EXPLICIT cast (silent). `convert(Int, q)` —
# Julia's path for `x::Int = q` — emits the implicit-cast warning then
# delegates to the constructor. Same discipline as QBool/QInt; see
# `src/types/quantum.jl` for the warning helper + `with_silent_casts`
# escape hatch.

"""
    Base.Int(q::QMod{d, K}) -> Int

Measure all K underlying qubits and assemble the classical label in
`[0, d)`. Consumes `q` (linear resource).

If the decoded bitstring is ≥ d, errors loudly: this indicates leakage
into encoded basis states outside the d-level subspace (see type docstring,
Leakage layer 3). At power-of-2 d the check is statically unreachable
(every K-bit pattern is in-range) and Julia will constant-fold it away.
"""
function Base.Int(q::QMod{d, K}) where {d, K}
    check_live!(q)
    result = 0
    for i in 1:K
        outcome = _blessed_measure!(q.ctx, q.wires[i])
        if outcome
            result |= (1 << (i - 1))
        end
    end
    q.consumed = true
    if result >= d
        error(
            "QMod{$d} measurement produced out-of-range bitstring $result " *
            "(≥ d=$d). This indicates leakage into encoded basis states " *
            "outside the d-level subspace. Possible causes: (1) a custom " *
            "primitive violated the d-level invariant; (2) state corruption " *
            "by a non-subspace-preserving operation; (3) a backend bug."
        )
    end
    return result
end

function Base.convert(::Type{Int}, q::QMod{d, K}) where {d, K}
    _warn_implicit_cast(QMod{d}, Int)
    return Int(q)
end

# ── ak2: spin-j Ry/Rz primitives (q.θ += δ, q.φ += δ) ────────────────────────
#
# Primitives #2 and #3 of the locked 6-primitive qudit set
# (docs/physics/qudit_magic_gate_survey.md §8.1):
#
#   q.θ += δ ↦ exp(-i δ Ĵ_y)  on the spin-j = (d-1)/2 irrep of SU(2)
#   q.φ += δ ↦ exp(-i δ Ĵ_z)  on the same irrep
#
# At d=2 (K=1), both rotations are the existing qubit Ry/Rz on the single
# underlying wire (Rule 11 preserved bit-identically). The dispatch path is:
#
#   q.θ += δ
#   → getproperty(q::QMod{2, 1}, :θ)   → returns `BlochProxy`
#     (reuses the QBool proxy from src/types/qbool.jl:67-111, aliased to
#     wires[1]; zero new code path at d=2 — same apply_ry!/apply_rz! the
#     qubit primitives use, control stack respected identically)
#   → Base.:+(::BlochProxy, ::Real) at src/types/qbool.jl:94-102
#     → apply_ry!(ctx, wires[1], δ)
#
# At d>2, getproperty returns a new `QModBlochProxy{d, K}` carrying the full
# wire group. The spin-j decomposition into multi-qubit gates (Bartlett Eqs.
# 5-7, Givens-style) is filed as bead `Sturm.jl-nrs` (qubit-encoded fallback
# simulator). Until nrs lands, d>2 calls error loudly with a pointer.

"""
    QModBlochProxy{d, K}

Bloch-axis proxy for `QMod{d, K}` at d>2. Parallel to `BlochProxy`
(src/types/qbool.jl:67-72) but carries the full `NTuple{K, WireID}` wire
group and the dimension witness `d` needed for the spin-j decomposition.

Only `+=` and `-=` on a numeric axis (`q.θ`, `q.φ`) are meaningful; reading
the angle would require measurement. `parent::QMod{d, K}` is held for the
`check_live!` invariant before each rotation.

At d=2 (K=1) the proxy is not used — `getproperty(::QMod{2, 1}, ::Symbol)`
returns the existing `BlochProxy` directly.
"""
struct QModBlochProxy{d, K}
    wires::NTuple{K, WireID}
    axis::Symbol            # :θ or :φ
    ctx::AbstractContext
    parent::QMod{d, K}
end

# d=2 specialization: route q.θ / q.φ through the existing qubit BlochProxy
# on the single underlying wire. Julia picks this more-specific method over
# the generic `where {d, K}` method below for QMod{2, 1} instances.
@inline function Base.getproperty(q::QMod{2, 1}, s::Symbol)
    if s === :θ || s === :φ
        check_live!(q)
        wire = getfield(q, :wires)[1]
        ctx  = getfield(q, :ctx)
        # Build a non-owning QBool view (consumed=false) so BlochProxy's
        # `parent::QBool` liveness check has a concrete target. Same aliasing
        # idiom as `_qbool_views` in src/types/qint.jl:45-48. The view's
        # consumed flag is independent of the owning QMod; liveness was just
        # checked above via `check_live!(q)`.
        return BlochProxy(wire, s, ctx, QBool(wire, ctx, false))
    else
        return getfield(q, s)
    end
end

# Generic d>2 case: return a QModBlochProxy carrying the full wire group.
@inline function Base.getproperty(q::QMod{d, K}, s::Symbol) where {d, K}
    if s === :θ || s === :φ
        check_live!(q)
        return QModBlochProxy{d, K}(
            getfield(q, :wires), s, getfield(q, :ctx), q,
        )
    else
        return getfield(q, s)
    end
end

# `q.θ += δ` desugars to `q.θ = q.θ + δ`. The `+` applies the rotation and
# returns the `_RotationApplied` sentinel (shared with QBool via qbool.jl).
# The setproperty! below is the final no-op step that makes the assignment
# syntax legal. Mirrors `Base.setproperty!(::QBool, ...)` at
# src/types/qbool.jl:108-111.
function Base.setproperty!(q::QMod{d, K}, s::Symbol, val::_RotationApplied) where {d, K}
    return val
end

# `+` on a QModBlochProxy either applies the spin-j rotation (d>2 path,
# delegated to the `_apply_spin_j_rotation!` stub until nrs lands) or, in
# the d=2 case, is unreachable because the d=2 getproperty returned a
# `BlochProxy` instead. The d=2 branch is kept as a defensive Rule-1 guard.
@inline function Base.:+(proxy::QModBlochProxy{d, K}, δ::Real) where {d, K}
    check_live!(proxy.parent)
    _apply_spin_j_rotation!(proxy.ctx, proxy.wires, proxy.axis, δ, Val(d))
    return ROTATION_APPLIED
end

@inline Base.:-(proxy::QModBlochProxy, δ::Real) = proxy + (-δ)

"""
    _apply_spin_j_rotation!(ctx, wires::NTuple{K, WireID}, axis::Symbol, δ::Real, ::Val{d})

Apply the spin-`j = (d-1)/2` rotation `exp(-i δ Ĵ_{axis})` to the d-level
register stored in `wires`. At d=2 this never runs (the d=2 getproperty
routes through `BlochProxy` to `apply_ry!`/`apply_rz!` directly); at d>2:

  * **axis `:φ` (Rz)** — IMPLEMENTED via per-wire binary factorisation.
    In Bartlett's labelling `|s⟩ = |j, j-s⟩_z` (Bartlett Eq. 5), Ĵ_z is
    diagonal: `Ĵ_z |s⟩ = (j - s) |s⟩`. With `s = Σ_{i=0}^{K-1} b_i 2^i`
    in the LE binary encoding, `exp(-i δ (j - s))` factors as
    `exp(-i δ j) · Π_i exp(+i δ b_i 2^i)`. The `exp(-i δ j)` prefactor is
    a global phase (SU(d) convention, CLAUDE.md "Global Phase and
    Universality" — becomes a controlled relative phase under `when()`,
    per locked policy §8.4). Each `exp(+i δ b_i 2^i)` on wire `i+1` is
    `apply_rz!(ctx, wires[i+1], δ * 2^i)` (up to a per-wire global phase
    that sums to another overall global phase). Gate count: K single-
    qubit Rz's per call. Zero amplitude movement → no leakage at any d.
  * **axis `:θ` (Ry)** — NOT YET IMPLEMENTED. Filed as bead `Sturm.jl-k8u`
    (QMod{d} Ry rotation). Errors loudly with a pointer. The multi-qubit
    decomposition of `exp(-i δ Ĵ_y)` on the (2j+1)-dim spin-j irrep was
    left unresolved by both `nrs` proposer designs; k8u owns the
    derivation + amplitude-level tests against the Wigner d-matrix.

See `docs/physics/bartlett_deGuise_sanders_2002_qudit_simulation.pdf` and
`docs/design/nrs_design_proposer_{a,b}.md` for the decomposition sketch
and the open Ry question.
"""
function _apply_spin_j_rotation!(
    ctx::AbstractContext,
    wires::NTuple{K, WireID},
    axis::Symbol,
    δ::Real,
    ::Val{d},
) where {K, d}
    if axis === :φ
        # Per-wire binary factorisation of exp(-i δ Ĵ_z) = exp(-i δ (j - s)).
        # wires[i] carries bit b_{i-1} at weight 2^{i-1}; apply_rz! at angle
        # δ·2^{i-1} contributes exp(±i δ 2^{i-1}/2) on each branch.
        @inbounds for i in 1:K
            apply_rz!(ctx, wires[i], δ * (1 << (i - 1)))
        end
        return nothing
    elseif axis === :θ
        error(
            "spin-j θ (Ry) rotation on QMod{$d} (K=$K) is not yet implemented. " *
            "The decomposition of exp(-i δ Ĵ_y) on the (2j+1)-dim spin-j irrep " *
            "into multi-qubit gates is filed as bead `Sturm.jl-k8u` (QMod{d} " *
            "Ry rotation). The φ (Rz) primitive on this register DOES work — " *
            "use `q.φ += δ`. Use d=2 for full Ry support."
        )
    else
        error("internal: _apply_spin_j_rotation! axis must be :θ or :φ, got $axis")
    end
end
