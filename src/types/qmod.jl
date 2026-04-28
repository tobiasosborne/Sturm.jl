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

"""
    QModPhaseProxy{d, K, P}

Diagonal-phase-primitive proxy for `QMod{d, K}`. P=2 routes
[`q.θ₂ += δ`](@ref) (bead `Sturm.jl-os4`, quadratic phase / squeezing); P=3
will route `q.θ₃ += δ` (bead `Sturm.jl-mle`, cubic phase / magic) once that
ships. The proxy parallels [`QModBlochProxy`](@ref) but for the polynomial-
in-`n̂` primitives (Clifford-hierarchy levels 2 and 3) rather than the
spin-j rotations (level 1).

The `P` parameter lifts the polynomial degree into the type so dispatch on
`Base.:+(::QModPhaseProxy{..., P}, ::Real)` can pick the right kernel
(`_apply_n_squared!` for P=2, `_apply_n_cubed!` for P=3) without runtime
branching. At `d=2` (K=1) the gate collapses to an Rz-equivalent single
`apply_rz!` (n̂² = n̂³ = n̂ on `{0,1}`); the type machinery is uniform across
all d ≥ 2.

Refs: `docs/physics/qudit_magic_gate_survey.md` §8.1 (locked primitive set);
`docs/physics/qudit_magic_gate_survey.md` §8.2 (n̂ vs Ĵ_z convention);
`docs/physics/qudit_magic_gate_survey.md` §8.4 (SU(d) controlled-phase
policy under `when()`).
"""
struct QModPhaseProxy{d, K, P}
    wires::NTuple{K, WireID}
    ctx::AbstractContext
    parent::QMod{d, K}
end

# d=2 specialization: route q.θ / q.φ through the existing qubit BlochProxy
# on the single underlying wire. Julia picks this more-specific method over
# the generic `where {d, K}` method below for QMod{2, 1} instances.
#
# `:θ₂` (and the future `:θ₃`) goes through QModPhaseProxy at all d ≥ 2 —
# at d=2 (K=1) the underlying decomposition reduces to a single apply_rz!
# (n̂² = n̂ on {0,1}), so a separate fast path through BlochProxy would buy
# nothing. Same gate emitted; uniform code path.
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
    elseif s === :θ₂
        check_live!(q)
        return QModPhaseProxy{2, 1, 2}(
            getfield(q, :wires), getfield(q, :ctx), q,
        )
    elseif s === :θ₃
        check_live!(q)
        return QModPhaseProxy{2, 1, 3}(
            getfield(q, :wires), getfield(q, :ctx), q,
        )
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
    elseif s === :θ₂
        check_live!(q)
        return QModPhaseProxy{d, K, 2}(
            getfield(q, :wires), getfield(q, :ctx), q,
        )
    elseif s === :θ₃
        check_live!(q)
        return QModPhaseProxy{d, K, 3}(
            getfield(q, :wires), getfield(q, :ctx), q,
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

# `+` on a QModPhaseProxy{d, K, 2} applies the quadratic-phase primitive
# `exp(-i·δ·n̂²)`. The decomposition (see `_apply_n_squared!`) is uniform
# across all d ≥ 2; no d-dispatch needed at this layer.
@inline function Base.:+(proxy::QModPhaseProxy{d, K, 2}, δ::Real) where {d, K}
    check_live!(proxy.parent)
    _apply_n_squared!(proxy.ctx, proxy.wires, δ)
    return ROTATION_APPLIED
end

# `+` on a QModPhaseProxy{d, K, 3} applies the cubic-phase magic primitive
# `exp(-i·δ·n̂³)`. Uniform K-parametric kernel; trilinear term kicks in at K≥3.
@inline function Base.:+(proxy::QModPhaseProxy{d, K, 3}, δ::Real) where {d, K}
    check_live!(proxy.parent)
    _apply_n_cubed!(proxy.ctx, proxy.wires, δ)
    return ROTATION_APPLIED
end

@inline Base.:-(proxy::QModPhaseProxy, δ::Real) = proxy + (-δ)

"""
    _apply_spin_j_ry_d3!(ctx, wires::NTuple{2, WireID}, δ::Real)

Apply `exp(-i δ Ĵ_y)` on the spin-`j = 1` irrep stored in two qubit wires
(Bartlett-deGuise-Sanders convention `|s⟩ = |1, 1-s⟩_z`, s ∈ {0,1,2}; the
`|11⟩_qubit` pattern is the forbidden leakage state).

## Closed-form decomposition (orchestrator-verified, Session 56)

    d¹(δ) = G_{01}(2γ) · G_{12}(2β) · G_{01}(2γ)

where `G_{i,j}(θ)` is the 3×3 Ry(θ) embedded on levels `i ↔ j`:

    γ = atan2(sin(δ/2),                 √2 · cos(δ/2))
    β = atan2(sin(δ/2) · √(2−sin²(δ/2)), cos²(δ/2))

The algebraic identity was verified by direct matrix multiplication
(`docs/design/k8u_design_A.md` §1.1) and numerically to 1.1e-16 across
δ ∈ {π/3, π/4, ±π, ±π/2, 2.718, 2π−10⁻¹⁰}. Plain `atan` / `acos` fail
for δ < 0; `atan2` (`Julia atan(y,x)`) is mandatory.

## Qubit-level circuit

Encoding (`wires[1]`=LSB=`w_l`, `wires[2]`=MSB=`w_m`, little-endian):

    label 0 ↔ |00⟩ (w_l=0, w_m=0)
    label 1 ↔ |01⟩ (w_l=1, w_m=0)     [binary 01 with LSB on left = bit 0 = 1]
    label 2 ↔ |10⟩ (w_l=0, w_m=1)
    forbidden ↔ |11⟩ (w_l=1, w_m=1)

**G_{01}(2γ)** rotates (|00⟩ ↔ |01⟩), identity on (|10⟩, |11⟩). Realised by
an Ry(π) bracket on `w_m` (flipping the control frame) + controlled-Ry
on `w_l` with `w_m` as control:

    apply_ry!(w_m, π); push_control!(w_m); apply_ry!(w_l, 2γ); pop_control!; apply_ry!(w_m, -π)

The `Ry(±π)` pair cancels exactly (`Ry(π)·Ry(-π) = I`), producing no
global-phase drift under `when()` lifts.

**G_{12}(2β)** rotates (|01⟩ ↔ |10⟩), identity on (|00⟩, |11⟩). Realised
by a CX-scratch that routes `|01⟩` transiently through `|11⟩` (reversible
scratch — forbidden state is used but restored at block exit):

    apply_cx!(w_l, w_m); push_control!(w_m); apply_ry!(w_l, -2β); pop_control!; apply_cx!(w_l, w_m)

**CRITICAL: the angle is `-2β`, not `+2β`.** The CX-scratch + CRy
composition realises `G_{12}(-2β)`, not `G_{12}(+2β)`. Both k8u
proposer designs missed this; it was caught at synthesis by numerically
comparing the 4×4 qubit-circuit unitary against the target
`I ⊕ G_{12}(2β)`. Swapping the sign fixes it exactly.

## Gate count

Per call: **10 Ry + 8 CX** (2 × G_{01} = 8 Ry + 4 CX; 1 × G_{12} =
2 Ry + 4 CX).

## `when()` composition

`exp(-i δ Ĵ_y)` has determinant 1 on the spin-j irrep (Ĵ_y traceless),
so — unlike the `:φ` Rz path — there is NO SU(d) vs U(d) global-phase
cost to pay under control. The `Ry(±π)` brackets cancel identically in
both the uncontrolled and the `when()`-controlled case.

## References

  * `docs/physics/bartlett_deGuise_sanders_2002_qudit_simulation.pdf` Eq. 5.
  * `docs/design/k8u_design_{A,B}.md` (3+1 design round).
  * `docs/physics/qudit_magic_gate_survey.md` §8.4 (global-phase policy).
  * WORKLOG Session 56 (2026-04-23) — orchestrator synthesis + sign fix.

See bead `Sturm.jl-k8u`.
"""
@inline function _apply_spin_j_ry_d3!(
    ctx::AbstractContext,
    wires::NTuple{2, WireID},
    δ::Real,
)
    w_l, w_m = wires[1], wires[2]
    sh = sin(δ/2)
    ch = cos(δ/2)
    γ = atan(sh, sqrt(2) * ch)
    β = atan(sh * sqrt(2 - sh^2), ch^2)

    # G_{01}(2γ): rotate (|00⟩ ↔ |01⟩), identity on (|1x⟩).
    apply_ry!(ctx, w_m, π)
    push_control!(ctx, w_m)
    apply_ry!(ctx, w_l, 2γ)
    pop_control!(ctx)
    apply_ry!(ctx, w_m, -π)

    # G_{12}(2β): rotate (|01⟩ ↔ |10⟩), identity on (|00⟩, |11⟩).
    # SIGN FIX: CX·CRy·CX realises G_{12}(-2β), so negate the angle.
    apply_cx!(ctx, w_l, w_m)
    push_control!(ctx, w_m)
    apply_ry!(ctx, w_l, -2β)
    pop_control!(ctx)
    apply_cx!(ctx, w_l, w_m)

    # G_{01}(2γ) again (same as first block).
    apply_ry!(ctx, w_m, π)
    push_control!(ctx, w_m)
    apply_ry!(ctx, w_l, 2γ)
    pop_control!(ctx)
    apply_ry!(ctx, w_m, -π)
    return nothing
end

# d=5 Ry primitive (bead Sturm.jl-ixd). Depends on apply_ry!/apply_cx!/
# apply_rz!/push_control!/pop_control! and thus must come AFTER the type
# definitions above.
include("qmod_ry_d5.jl")

"""
    _apply_spin_j_rotation!(ctx, wires::NTuple{K, WireID}, axis::Symbol, δ::Real, ::Val{d})

Apply the spin-`j = (d-1)/2` rotation `exp(-i δ Ĵ_{axis})` to the d-level
register stored in `wires`. At d=2 this never runs (the d=2 getproperty
routes through `BlochProxy` to `apply_ry!`/`apply_rz!` directly); at d>2:

  * **axis `:φ` (Rz)** — IMPLEMENTED at all d ≥ 3 (bead `Sturm.jl-nrs`)
    via per-wire binary factorisation. In Bartlett's labelling
    `|s⟩ = |j, j-s⟩_z` (Bartlett Eq. 5), Ĵ_z is diagonal:
    `Ĵ_z |s⟩ = (j - s) |s⟩`. With `s = Σ_{i=0}^{K-1} b_i 2^i` in the LE
    binary encoding, `exp(-i δ (j - s))` factors as
    `exp(-i δ j) · Π_i exp(+i δ b_i 2^i)`. The `exp(-i δ j)` prefactor is
    a global phase (SU(d) convention, CLAUDE.md "Global Phase and
    Universality" — becomes a controlled relative phase under `when()`,
    per locked policy §8.4). Each `exp(+i δ b_i 2^i)` on wire `i+1` is
    `apply_rz!(ctx, wires[i+1], δ * 2^i)` (up to a per-wire global phase
    that sums to another overall global phase). Gate count: K single-
    qubit Rz's per call. Zero amplitude movement → no leakage at any d.
  * **axis `:θ` (Ry), d = 3** — IMPLEMENTED (bead `Sturm.jl-k8u`) via the
    closed-form 3-Givens decomposition. See [`_apply_spin_j_ry_d3!`](@ref).
  * **axis `:θ` (Ry), d = 5** — IMPLEMENTED (bead `Sturm.jl-ixd`) via the
    Euler sandwich `Rz(π/2)·Ry(π/2)·Rz(δ)·Ry(-π/2)·Rz(-π/2)` where
    `Ry(±π/2)` are δ-independent fixed qubit circuits (10-Givens
    factorisation of `d²(π/2)`). See [`_apply_spin_j_ry_d5!`](@ref).
  * **axis `:θ` (Ry), d = 4 or d ≥ 6** — NOT YET IMPLEMENTED. csw
    critical-path only needs d ∈ {3, 5}; d = 4 (power-of-2, no leakage,
    6-Givens V₄ decomposition — may beat sandwich) and d ≥ 6 are filed
    as follow-on beads. Errors loudly with a pointer.

See `docs/physics/bartlett_deGuise_sanders_2002_qudit_simulation.pdf`,
`docs/design/nrs_design_proposer_{a,b}.md`,
`docs/design/k8u_design_{A,B}.md`, and `docs/design/ixd_design_{A,B}.md`.
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
        if d == 3
            _apply_spin_j_ry_d3!(ctx, wires, δ)
            return nothing
        elseif d == 5
            _apply_spin_j_ry_d5!(ctx, wires, δ)
            return nothing
        else
            error(
                "spin-j θ (Ry) rotation on QMod{$d} (K=$K) is not yet " *
                "implemented. Shipped: d = 3 (bead `Sturm.jl-k8u`, closed-" *
                "form 3-Givens) and d = 5 (bead `Sturm.jl-ixd`, Euler " *
                "sandwich with fixed V(π/2) dressing). d = 4 is filed as " *
                "bead `Sturm.jl-2bf` (power-of-2, no leakage, 6-Givens " *
                "V_{3/2}(δ) — may beat sandwich). d ≥ 6 not yet scoped. " *
                "The φ (Rz) primitive on this register DOES work — use " *
                "`q.φ += δ`."
            )
        end
    else
        error("internal: _apply_spin_j_rotation! axis must be :θ or :φ, got $axis")
    end
end

# ── os4: q.θ₂ += δ — quadratic phase / squeezing primitive ────────────────
#
# Primitive #4 (Sturm.jl-os4). Applies `exp(-i·δ·n̂²)` to a `QMod{d, K}`
# register, where n̂ is the computational-basis label operator (n̂|k⟩ = k|k⟩
# for k ∈ {0, …, d−1}; see `qudit_magic_gate_survey.md` §8.2 for the n̂ vs.
# Ĵ_z choice). The gate is diagonal in the computational basis: it phases
# each |k⟩ by `exp(-i·δ·k²)` and moves no amplitude.

"""
    _apply_n_squared!(ctx, wires::NTuple{K, WireID}, δ::Real)

Apply `exp(-i·δ·n̂²)` to a register stored in the K-bit little-endian
qubit encoding (`wires[1]` = LSB = `b_0`, `wires[K]` = MSB = `b_{K-1}`,
label `k = Σ b_{i-1}·2^{i-1}`).

## Decomposition

Using `b² = b` for `b ∈ {0,1}`:

    k² = Σᵢ b_{i-1}·4^{i-1} + Σ_{i<j} b_{i-1}·b_{j-1}·2^{i+j-1}

so

    exp(-i·δ·k²) = Πᵢ exp(-i·δ·b_{i-1}·4^{i-1})
                 · Π_{i<j} exp(-i·δ·b_{i-1}·b_{j-1}·2^{i+j-1})

* **Linear term** per wire `i`: phase `exp(-i·δ·4^{i-1})` on `|1⟩`, none on
  `|0⟩`. Realised by `apply_rz!(wires[i], -δ·4^{i-1})` — `Rz(β)` produces
  relative phase `e^{+iβ}` on `|1⟩` over `|0⟩`, so `β = -δ·4^{i-1}` matches
  (up to a global `e^{+iδ·4^{i-1}/2}` absorbed into SU(d)).

* **Bilinear term** per pair `(i, j)` with `i < j`: phase `exp(-i·δ·c)`
  on `|11⟩` only, with `c = 2^{i+j-1}`. This is a controlled-phase /
  CZ(c·δ) gate on `(wires[i], wires[j])`, lowered by the standard ZZ-rotation
  identity `CZ(α) = Rz_i(-α/2)·Rz_j(-α/2)·CX_{i→j}·Rz_j(α/2)·CX_{i→j}`
  (up to a global `e^{+iα/4}` per pair, absorbed into SU(d)).

## d=2 collapse

At `K = 1` the bilinear loop is empty and the linear loop fires once with
`apply_rz!(wires[1], -δ)`. This recovers `exp(-i·δ·n̂)` (since `n̂² = n̂`
at d=2), matching the locked §8.1 reduction "primitive 4 collapses to
Rz-equivalent at d=2". Bit-identical to a single qubit `apply_rz!`.

## Subspace preservation

Diagonal in the {|k⟩}_qubit basis ⇒ no amplitude moves between basis
states. If forbidden labels (k ≥ d at non-power-of-2 d) start at zero
amplitude (Layer 1: prep is `|0⟩_d`; Layer 2: every primitive preserves
the d-subspace), they stay at zero after q.θ₂. ✓

## `when()` composition

All `apply_rz!`/`apply_cx!` calls auto-pick up Sturm's control stack via
`push_control!` / `pop_control!` (managed by `when()`). Per locked §8.4,
the per-pair global phase from the CZ decomposition becomes a relative
phase under `when()` — observable as a controlled phase shift, paid as
the SU(d) discipline ("live in SU(d), pay controlled-phase cost", same
as the qubit `H² = -I` precedent). Tests assert behavioural correctness,
not bit-equality with a specific lift.

## Gate count

K Rz (linear) + K(K−1)/2 controlled-phase (bilinear, each = 2 CX + 3 Rz)
= K + (5/2)·K(K−1) primitives. Specific:
* K=1: 1 Rz.
* K=2: 5 Rz + 2 CX.
* K=3: 12 Rz + 6 CX.

## References

* `docs/physics/qudit_magic_gate_survey.md` §8.1, §8.2, §8.4 (locked design).
* `docs/physics/qudit_primitives_survey.md` §3 (spin-j universality + the
  "needs nonlinear partner" argument that motivated primitive #4).
* `docs/physics/campbell_2014_enhanced_qudit_ft.pdf` §III.B (Z_{α,β} =
  ω^{α n̂ + β n̂²} as the Clifford diagonal — q.φ + q.θ₂ generates this).
"""
@inline function _apply_n_squared!(
    ctx::AbstractContext,
    wires::NTuple{K, WireID},
    δ::Real,
) where {K}
    # Linear term: K single-qubit Rz's.
    @inbounds for i in 1:K
        apply_rz!(ctx, wires[i], -δ * (1 << (2 * (i - 1))))   # 4^{i-1}
    end
    # Bilinear term: K(K-1)/2 controlled-phase pairs.
    @inbounds for i in 1:K-1
        for j in i+1:K
            α = δ * (1 << (i + j - 1))    # 2^{i+j-1}
            _apply_cphase!(ctx, wires[i], wires[j], α)
        end
    end
    return nothing
end

"""
    _apply_cphase!(ctx, wi::WireID, wj::WireID, α::Real)

Apply a controlled-phase `CZ(α) = diag(1, 1, 1, e^{-iα})` between qubit
wires `wi` and `wj` (basis order `|q_i q_j⟩` = `|00⟩, |01⟩, |10⟩, |11⟩`),
up to a global phase `e^{+iα/4}` absorbed into SU(d).

## Decomposition (ZZ-rotation identity)

`exp(-iα·|11⟩⟨11|) = exp(-(iα/4)·(I − Z_i)(I − Z_j))` expands to a sum of
single-qubit Z operators and one ZZ-coupling, giving the textbook lowering

    CZ(α) ≃ Rz_i(-α/2) · Rz_j(-α/2) · CX_{i→j} · Rz_j(α/2) · CX_{i→j}

(global phase `e^{-iα/4}` dropped; lives in SU(d) per CLAUDE.md "Global
Phase and Universality"). Verified by direct case analysis on each of the
four computational-basis states. Under `when()`, the global phase
becomes a relative phase between the control's `|0⟩` and `|1⟩` branches —
the SU(d) controlled-phase cost called out in `qudit_magic_gate_survey.md`
§8.4. Same discipline as `H² = -I`.

Helper for [`_apply_n_squared!`](@ref); also reusable for any future
primitive needing a continuous controlled-phase coupling.
"""
@inline function _apply_cphase!(ctx::AbstractContext, wi::WireID, wj::WireID, α::Real)
    apply_cx!(ctx, wi, wj)
    apply_rz!(ctx, wj, α / 2)
    apply_cx!(ctx, wi, wj)
    apply_rz!(ctx, wj, -α / 2)
    apply_rz!(ctx, wi, -α / 2)
    return nothing
end

# ── mle: q.θ₃ += δ — cubic phase / magic primitive ────────────────────────
#
# Primitive #5 (Sturm.jl-mle). Applies `exp(-i·δ·n̂³)` to a `QMod{d, K}`
# register, where n̂ is the computational-basis label operator. Diagonal
# in the computational basis: phases each |k⟩ by `exp(-i·δ·k³)`.
#
# Level-3 of the Clifford hierarchy at prime d ≥ 5 (magic). At
# δ = -2π/d gives the Campbell M_1 = ω^{n̂³} gate (qudit T-gate
# analogue). At d ∈ {2, 3, 6}, the cubic-on-bits structure is
# Clifford-degenerate (k³ ≡ k mod d for d ∈ {2}; or 3μ ≡ 0 mod 3 at
# d=3 collapses cubic to quadratic) — the primitive still applies
# correctly, but the level-3 MAGIC role requires a higher root of
# unity (Watson 2015 Eq. 7: γ^{n̂³} with γ = e^{2πi/9} at d=3) which
# is library-level (T_d! gate, separate bead).

"""
    _apply_n_cubed!(ctx, wires::NTuple{K, WireID}, δ::Real)

Apply `exp(-i·δ·n̂³)` to a register stored in the K-bit little-endian
qubit encoding (`wires[1]` = LSB, `wires[K]` = MSB; label
`k = Σ b_{i-1}·2^{i-1}`).

## Decomposition

Using `b² = b³ = b` for `b ∈ {0,1}`:

    k³ = Σᵢ b_{i-1}·8^{i-1}                                           (linear)
       + 3·Σ_{i<j} b_{i-1}·b_{j-1}·(2^{2(i-1)+(j-1)} + 2^{(i-1)+2(j-1)})  (bilinear)
       + 6·Σ_{i<j<l} b_{i-1}·b_{j-1}·b_{l-1}·2^{(i-1)+(j-1)+(l-1)}        (trilinear)

so

    exp(-i·δ·k³) = Πᵢ exp(-i·δ·b_{i-1}·8^{i-1})
                · Π_{i<j} exp(-i·δ·3·(2^{2i+j-3} + 2^{i+2j-3})·b_{i-1}·b_{j-1})
                · Π_{i<j<l} exp(-i·δ·6·2^{i+j+l-3}·b_{i-1}·b_{j-1}·b_{l-1})

* **Linear** per wire i: `apply_rz!(wires[i], -δ·8^{i-1})`. Same Rz
  pattern as os4 but with 8^i instead of 4^i.
* **Bilinear** per pair (i, j) with i < j: controlled-phase CZ with
  α = `3·δ·(2^{2i+j-3} + 2^{i+2j-3})`. Reuses [`_apply_cphase!`](@ref)
  from os4.
* **Trilinear** per triple (i, j, l) with i < j < l: doubly-controlled
  phase CCPhase with α = `6·δ·2^{i+j+l-3}`. Lowered by the standard
  CCX-sandwich identity in [`_apply_ccphase!`](@ref).

## d=2 collapse (K=1)

Linear loop fires once with `apply_rz!(wires[1], -δ·8^0)` =
`apply_rz!(wires[1], -δ)`. Bilinear and trilinear loops are empty. So
q.θ₃ at d=2 emits exactly the SAME apply_rz! as q.θ₂ at d=2 — both
collapse to Rz-equivalent (n̂² = n̂³ = n̂ on bits, per locked §8.1
read with the §8.2 n̂-vs-Ĵ_z lock-in).

## Subspace preservation

Diagonal in {|k⟩}_qubit ⇒ no amplitude movement ⇒ forbidden states
stay empty. Same as os4. ✓

## `when()` composition

Linear and bilinear pieces inherit the control stack as in os4 (each
`apply_rz!` / `apply_cx!` / `_apply_cphase!` is auto-controlled).
Trilinear: `_apply_ccphase!` allocates a workspace ancilla; the
`apply_ccx!` calls under `when(c)` become 3-controlled-CX (handled
via `_multi_controlled_cx!` in `multi_control.jl`); the inner
`_apply_cphase!` is auto-controlled. The ancilla returns to |0⟩ in
both control branches.

## Gate count

* K=1: 1 Rz.
* K=2: 1 Rz + 1 bilinear pair (5 gates) = 5 Rz + 2 CX.
* K=3: 3 Rz + 3 bilinear (each 5 gates) + 1 trilinear (∼10 gates incl.
  CCX-sandwich + ancilla) ≈ 12 Rz + 6 CX + ~3 CCX + 1 ancilla
  alloc/dealloc.

## References

* `docs/physics/qudit_magic_gate_survey.md` §1 (Howard-Vala / Campbell
  cubic magic gate); §8.1 (locked primitive set, level-3 role);
  §8.2 (n̂ convention).
* `docs/physics/campbell_2014_enhanced_qudit_ft.pdf` Eq. (1)
  (canonical M_μ = ω^{μ n̂³}).
* `docs/physics/howard_vala_2012_qudit_magic.pdf` Eq. (16)-(24)
  (qudit π/8 family).
"""
@inline function _apply_n_cubed!(
    ctx::AbstractContext,
    wires::NTuple{K, WireID},
    δ::Real,
) where {K}
    # Linear term: K single-qubit Rz's at angle -δ·8^{i-1}.
    @inbounds for i in 1:K
        apply_rz!(ctx, wires[i], -δ * (1 << (3 * (i - 1))))   # 8^{i-1}
    end
    # Bilinear term: K(K-1)/2 controlled-phase pairs.
    @inbounds for i in 1:K-1
        for j in i+1:K
            # α = 3·δ·(2^{2(i-1)+(j-1)} + 2^{(i-1)+2(j-1)})
            #   = 3·δ·(2^{2i+j-3} + 2^{i+2j-3})
            α = 3 * δ * ((1 << (2 * i + j - 3)) + (1 << (i + 2 * j - 3)))
            _apply_cphase!(ctx, wires[i], wires[j], α)
        end
    end
    # Trilinear term: C(K, 3) doubly-controlled-phase triples.
    @inbounds for i in 1:K-2
        for j in i+1:K-1
            for l in j+1:K
                # α = 6·δ·2^{(i-1)+(j-1)+(l-1)} = 6·δ·2^{i+j+l-3}
                α = 6 * δ * (1 << (i + j + l - 3))
                _apply_ccphase!(ctx, wires[i], wires[j], wires[l], α)
            end
        end
    end
    return nothing
end

"""
    _apply_ccphase!(ctx, wi, wj, wl, α)

Apply a doubly-controlled phase: `phase exp(-iα)` on `|111⟩` of
`(wi, wj, wl)`, identity on the other 7 computational states. Up to a
global phase absorbed into SU(d).

## Decomposition (CCX-sandwich)

    CCX(wi, wj → ws) · CPhase(ws, wl, α) · CCX(wi, wj → ws)

with `ws` a fresh allocated ancilla. Step-by-step:

1. `apply_ccx!(wi, wj, ws)` — sets `ws = b_i ∧ b_j`.
2. `_apply_cphase!(ws, wl, α)` — phase α on the |1_ws, 1_wl⟩ subspace
   = the |1_i, 1_j, 1_l⟩ subspace of the original triple.
3. `apply_ccx!(wi, wj, ws)` — undoes step 1; `ws` returns to `|0⟩`.

Ancilla deallocated in `finally` so it's clean even if a subroutine
errors mid-flight.

## Under `when()`

The outer control stack adds to each gate: `apply_ccx!` becomes
3-controlled-CX (handled by `_multi_controlled_cx!`); `_apply_cphase!`
becomes 3-controlled-phase (CX → CCX, Rz → CRz, all auto-routed).
The CCX-sandwich is symmetric: ancilla returns to |0⟩ in BOTH
control branches.

Helper for [`_apply_n_cubed!`](@ref); also reusable for any future
primitive needing a 3-bit AND-phase coupling.
"""
@inline function _apply_ccphase!(ctx::AbstractContext, wi::WireID, wj::WireID, wl::WireID, α::Real)
    ws = allocate!(ctx)
    try
        apply_ccx!(ctx, wi, wj, ws)
        _apply_cphase!(ctx, ws, wl, α)
        apply_ccx!(ctx, wi, wj, ws)
    finally
        deallocate!(ctx, ws)
    end
    return nothing
end

# ── p38: SUM entangler `a ⊻= b` on (QMod{d}, QMod{d}) ─────────────────────
#
# Primitive #6 (Sturm.jl-p38). SUM: |a, b⟩ → |a, (a + b) mod d⟩, with `b` the
# control and `a` the target (matching the existing QBool / QInt `a ⊻= b`
# convention: left is target, right is control). Reduces to qubit CNOT at
# d=2 (a ⊻= b on the single underlying wire pair). Reference: Gottesman
# 1998 Eq. G12 (SUM gate).
#
# v0.1 SCOPE: shipped at d = 2 only. At d > 2, modular addition on the
# qubit-encoded register requires either:
#   (a) Bennett-style classical-function compilation via Sturm.jl-jba
#       (QMod{d} Bennett interop, currently P3); or
#   (b) Direct Beauregard-style mod-d adder (allocate overflow ancilla,
#       3-bit ripple-add, conditional subtract d, uncompute) — substantial
#       work paralleling src/library/arithmetic.jl::modadd! but with
#       quantum (not classical) `a`.
# Both are deferred to a follow-on bead.

"""
    Base.xor(target::QMod{d, K}, ctrl::QMod{d, K}) -> target

SUM entangler: `target ← (ctrl + target) mod d`. Returns `target` after
mutation (mirrors `Base.xor(::QBool, ::QBool)` semantics so
`target ⊻= ctrl` desugars correctly to `target = target ⊻ ctrl` and the
in-place semantics match user expectation).

# v0.1: d = 2 only

At d = 2, K = 1, the gate is qubit CNOT on the single underlying wire
pair: `apply_cx!(ctx, ctrl.wires[1], target.wires[1])`. Bit-identical
to `target_qbool ⊻= ctrl_qbool` if the same wires were wrapped as
QBools.

At d > 2 errors loudly with the deferral rationale (see file header).

# Refs
* `docs/physics/gottesman_1998_qudit_fault_tolerant.pdf` Eq. (G12): SUM
  definition.
* `docs/physics/qudit_magic_gate_survey.md` §8.3: locked SUM choice.
"""
function Base.xor(target::QMod{d, K}, ctrl::QMod{d, K}) where {d, K}
    check_live!(target)
    check_live!(ctrl)
    target.ctx === ctrl.ctx ||
        error("SUM (a ⊻= b): target and ctrl must share a context")
    if d == 2
        # K = 1 at d = 2; collapse to qubit CNOT on the single wire pair.
        apply_cx!(target.ctx, ctrl.wires[1], target.wires[1])
        return target
    else
        error(
            "SUM (a ⊻= b) on QMod{$d, $K} is not yet implemented at d ≥ 3. " *
            "Modular addition on the qubit-encoded register requires either " *
            "(a) Bennett-style classical-function compilation (Sturm.jl-jba) " *
            "or (b) a Beauregard mod-d adder construction. Both deferred to " *
            "a follow-on bead. d = 2 ships."
        )
    end
end
