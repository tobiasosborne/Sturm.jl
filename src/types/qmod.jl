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
