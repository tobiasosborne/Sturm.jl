# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M2 (bead Sturm.jl-dc6i): `Ad` — the
# application kernel. `Ad : U(d) → CPTP`, `Ad_g(ρ) = g ρ g†`, `ker(Ad) = U(1)`.
# THIS IS WHERE THE PHASE QUOTIENT IS CROSSED EXACTLY ONCE (PRD-v2 §4.3). One
# generic entry, `apply!`, dispatching on value kind and threading the context
# explicitly (never re-reading the ScopedValue in a loop — CLAUDE.md conv 6).
# INTERNAL apart from `apply!`; lives under `src/orkan/` so the controlled-
# lowering grep-lint (`orkan_cx`/`controlled` tokens only under `src/kernel/` +
# `src/orkan/`) confines it — this file's whole job IS that lowering.
#
# Everything here is grounded on paper in
# `docs/physics/barenco_1995_elementary_gates.md` (the REAL lemma numbering):
#   • ZYZ chart .................... Lemma 4.1
#   • ABC witnesses ................ Lemma 4.3 (A=Rz(α)Ry(θ/2), B=Ry(−θ/2)Rz(−(α+β)/2), C=Rz((β−α)/2))
#   • ∧₁(W)=C·CX·B·CX·A ............ Lemma 5.1  (W ∈ SU(2))
#   • ∧₁(Ph(δ)) = diag(1,e^{iδ}) on the CONTROL .. Lemma 5.2  (the phase line)
#   • ∧₁(U) = E(ctrl)·[SU(2) skeleton] .. Corollary 5.3
#   • ∧₂(U) via exact V²=U ......... Lemma 6.1  (ancilla-free sqrt-V)
#   • clean-|0⟩ AND-ladder for phase-carrying ∧_k(U) .. Lemma 7.11 / Cor 7.12
# The chart singularity is Stuelpnagel 1964
# (`docs/physics/stuelpnagel_1964_rotation_parametrization.md`); the physicality
# of the controlled phase is Tang–Wright Thm 1.1
# (`docs/physics/tang_wright_2025_controlled_unitaries.md`); the ctrl homomorphism
# / non-distribution over ⊗ is Delorme
# (`docs/physics/delorme_control_as_constructor.md`). Convention:
# `docs/physics/wharton_koch_quaternion_bloch.md`.

# --- Entangling primitive emitters (confined here by the choke-point lint) --
# The 2q/3q emitters (they name Orkan's native controlled gates) live in this
# file — the single controlled-lowering site under `src/orkan/`. The 1q emitters
# are in `context/abstract.jl` (their tokens are unrestricted).
_emit_cx!(ctx::AbstractContext, c::Int, t::Int) = orkan_cx!(_core(ctx).state, c, t)
_emit_cy!(ctx::AbstractContext, c::Int, t::Int) = orkan_cy!(_core(ctx).state, c, t)
_emit_cz!(ctx::AbstractContext, c::Int, t::Int) = orkan_cz!(_core(ctx).state, c, t)
_emit_ccx!(ctx::AbstractContext, a::Int, b::Int, t::Int) = orkan_ccx!(_core(ctx).state, a, b, t)
_emit_swap!(ctx::AbstractContext, a::Int, b::Int) = orkan_swap!(_core(ctx).state, a, b)

# --- ZYZ extraction (Lemma 4.1; the ONE chart-singularity site, D7) -----

"""
    _zyz_angles(u::U2) -> (α, β, γ)

Euler angles with `U(q) = Rz(α)·Ry(β)·Rz(γ)` (the SU(2) part; `φ` dropped — ker
Ad). Because `U(q)` is det-1, this is EXACT with NO residual phase (Lemma 4.1) —
the whole payoff of the quaternion+phase split. Verified against Orkan:
`rz(γ);ry(β);rz(α)` realises `Rz(α)Ry(β)Rz(γ)`.

Derivation (PINNED convention `Rz(γ)=(cos γ/2,0,0,sin γ/2)`,
`Ry(β)=(cos β/2,0,sin β/2,0)`): the Hamilton product `Rz(α)∘Ry(β)∘Rz(γ)` has
`w=cos(β/2)cos((α+γ)/2)`, `x=−sin(β/2)sin((α−γ)/2)`, `y=sin(β/2)cos((α−γ)/2)`,
`z=cos(β/2)sin((α+γ)/2)`. Inverting: `β=2·atan(hypot(x,y),hypot(w,z))`,
`(α+γ)/2=atan(z,w)`, `(α−γ)/2=atan(−x,y)`.

Chart singularity (Stuelpnagel 1964; a topological fact about SO(3), NOT a
convention). At `β≈0` only `α+γ` is determined (gimbal lock, `U(q)` diagonal);
at `β≈π` only `α−γ` (`U(q)` antidiagonal). The fold is written HERE and nowhere
else (D7):
- `β≈0`: `U(q)=diag(w−iz,w+iz)=Rz(2·atan(z,w))` → `(α=2atan(z,w), β=0, γ=0)`.
- `β≈π`: `U(q)` antidiagonal `=Rz(2·atan(−x,y))·Ry(π)` → `(α=2atan(−x,y), β=π, γ=0)`.
"""
function _zyz_angles(u::U2)
    w, x, y, z = u.w, u.x, u.y, u.z
    s = hypot(x, y)   # |sin(β/2)|
    c = hypot(w, z)   # |cos(β/2)|
    if s < CHART_EPS
        return (2 * atan(z, w), 0.0, 0.0)
    elseif c < CHART_EPS
        return (2 * atan(-x, y), Float64(π), 0.0)
    else
        β = 2 * atan(s, c)
        p = atan(z, w)
        m = atan(-x, y)
        return (p + m, β, p - m)
    end
end

"""
    _emit_u2!(ctx, u, qb)

Apply the SU(2) part of `u` to Orkan qubit `qb` via ZYZ (φ DROPPED here — this
is §4.3's single phase-quotient crossing on the uncontrolled path). 3 ccalls
(`rz(γ);ry(β);rz(α)`, time-order = leftmost first); the singular folds emit a
single `rz` (β≈0) or `ry(π);rz(α)` (β≈π).
"""
function _emit_u2!(ctx::AbstractContext, u::U2, qb::Int)
    w, x, y, z = u.w, u.x, u.y, u.z
    s = hypot(x, y)
    c = hypot(w, z)
    if s < CHART_EPS
        _emit_rz!(ctx, qb, 2 * atan(z, w))
    elseif c < CHART_EPS
        _emit_ry!(ctx, qb, π)
        _emit_rz!(ctx, qb, 2 * atan(-x, y))
    else
        β = 2 * atan(s, c)
        p = atan(z, w)
        m = atan(-x, y)
        _emit_rz!(ctx, qb, p - m)   # rz(γ)
        _emit_ry!(ctx, qb, β)       # ry(β)
        _emit_rz!(ctx, qb, p + m)   # rz(α)
    end
    nothing
end

# --- U(2) square root (Barenco Lemma 6.1's exact V, V²=U) ---------------

"""
    sqrt_u2(u::U2) -> U2

A `U2` value `V` with `V ∘ V ≈ u` — half phase (`φ/2`) and the principal
quaternion square root (`√q = (q + 1_quat)` normalized: `|(w+1,x,y,z)| =
√(2(w+1))`, giving `w-part = cos(Ω/4)`, `vector = sin(Ω/4)·n̂`). Exact for any
`u` except `u = −I` exactly, where the SU(2) part is `−I` and the axis is free:
pick `√(−I) = i` (any pure unit quaternion) with `φ/2`. Barenco Lemma 6.1 needs
only *some* `V` with `V²=U`, so any branch is legitimate; `V∘V≈u` (which reuses
the M1 Hamilton `∘` and `≈`) is the witness. Lives here, not in the frozen M1
`kernel/u2.jl`: it is a lowering helper for the controlled decomposition, not a
group-algebra surface operation.
"""
function sqrt_u2(u::U2)
    φV = u.φ / 2
    w, x, y, z = u.w, u.x, u.y, u.z
    n2 = (w + 1)^2 + x^2 + y^2 + z^2   # = 2(w+1)
    if n2 < CHART_EPS^2
        # u ≈ −I: vanishing (w+1,x,y,z); axis free.
        return U2(0.0, 1.0, 0.0, 0.0, φV)
    end
    s = inv(sqrt(n2))
    return U2((w + 1) * s, x * s, y * s, z * s, φV)
end

# --- Multi-controlled-X AND ladders (Perm replay + phase-carrying ctrl) --

"""
    _and_onto_wire!(ctx, controls) -> (wire, ladder)

Compute the logical AND of `controls` (Orkan qubit indices) onto a single
returned wire, via a linear `ccx` chain using `length(controls)−1` fresh |0⟩
scratch ancillas (1 control ⇒ the control itself, no ancilla). Returns the AND
wire and the ccx `ladder` for `_uncompute_and!`. Clean-ancilla pattern (Barenco
Cor 7.12): matched compute/uncompute returns every ancilla to |0⟩.
"""
function _and_onto_wire!(ctx::AbstractContext, controls::Vector{Int})
    m = length(controls)
    m >= 1 || error("_and_onto_wire!: need ≥1 control")
    ladder = Tuple{Int,Int,Int}[]
    m == 1 && return (controls[1], ladder)
    core = _core(ctx)
    acc = controls[1]
    for i in 2:m
        anc = _alloc_scratch!(core)
        _emit_ccx!(ctx, acc, controls[i], anc)
        push!(ladder, (acc, controls[i], anc))
        acc = anc
    end
    return (acc, ladder)
end

"""Undo `_and_onto_wire!` (ccx is self-inverse), recycling each ancilla (now |0⟩)."""
function _uncompute_and!(ctx::AbstractContext, ladder::Vector{Tuple{Int,Int,Int}})
    core = _core(ctx)
    for (a, b, out) in Iterators.reverse(ladder)
        _emit_ccx!(ctx, a, b, out)
        _free_scratch!(core, out)
    end
    nothing
end

"""
    _emit_mcx!(ctx, controls, target)

Multi-controlled X: `0→x`, `1→cx`, `2→ccx` (native), `≥3→` AND-reduce the first
`m−1` controls onto one ancilla, `ccx(and, last, target)`, uncompute. Phase-free
by construction (used by `Perm` replay and controlled-`Perm` leaves).
"""
function _emit_mcx!(ctx::AbstractContext, controls::Vector{Int}, target::Int)
    m = length(controls)
    if m == 0
        _emit_x!(ctx, target)
    elseif m == 1
        _emit_cx!(ctx, controls[1], target)
    elseif m == 2
        _emit_ccx!(ctx, controls[1], controls[2], target)
    else
        (andw, ladder) = _and_onto_wire!(ctx, controls[1:end-1])
        _emit_ccx!(ctx, andw, controls[end], target)
        _uncompute_and!(ctx, ladder)
    end
    nothing
end

# --- Controlled-U2 lowering (the heart; phase-exact) --------------------

"""
    _apply_controlled_u2!(ctx, control, u, target)

`∧₁(U2)` on one control (Lemma 5.1 + 5.2 / Cor 5.3). Native fast paths (exact,
phase-correct): `u≈X→cx`, `u≈Y→cy`, `u≈Z→cz`. Otherwise ABC: `C·CX·B·CX·A` on
the target reproduces the SU(2) part, and the inner phase `u.φ` becomes
`p(control, φ)` — Lemma 5.2's `diag(1,e^{iφ})` on the CONTROL. THIS line is
phase-exactness: dropping it ships the multi-year Cirq/Qiskit/pytket controlled-
phase bug (Tang–Wright Thm 1.1). `ctrl(gphase(α))` reduces to a bare
`p(control,α)` (ABC is trivial, `β=0`), so `p` is skipped only when `|φ|<CHART_EPS`.
"""
function _apply_controlled_u2!(ctx::AbstractContext, control::Int, u::U2, target::Int)
    if u ≈ X
        _emit_cx!(ctx, control, target); return nothing
    elseif u ≈ Y
        _emit_cy!(ctx, control, target); return nothing
    elseif u ≈ Z
        _emit_cz!(ctx, control, target); return nothing
    end
    α, β, γ = _zyz_angles(u)
    A = Rz(α) ∘ Ry(β / 2)
    B = Ry(-β / 2) ∘ Rz(-(α + γ) / 2)
    C = Rz((γ - α) / 2)
    _emit_u2!(ctx, C, target)
    _emit_cx!(ctx, control, target)
    _emit_u2!(ctx, B, target)
    _emit_cx!(ctx, control, target)
    _emit_u2!(ctx, A, target)
    abs(u.φ) >= CHART_EPS && _emit_p!(ctx, control, u.φ)
    nothing
end

"""
    _apply_controlled!(ctx, k, controls, inner, targets)

Lower a `k`-controlled `inner` (the `Ctrl` inner value) onto `targets`, with
`controls`/`targets` as Orkan qubit indices. Structural recursion, NO catch-all
(mirrors M1 `ctrl.jl`: an unhandled kind is a `MethodError`, never a silent
wrong lowering — control on a future non-unitary node is unrepresentable, P4).
Constructs NO `Ctrl` value (the kernel construction choke point stays in
`kernel/ctrl.jl` per the lint) — it threads `k`/`controls` explicitly instead.
"""
function _apply_controlled!(ctx::AbstractContext, k::Int, controls::Vector{Int}, inner::U2, targets::Vector{Int})
    target = only(targets)
    if k == 1
        _apply_controlled_u2!(ctx, controls[1], inner, target)
    elseif k == 2
        if inner ≈ X
            _emit_ccx!(ctx, controls[1], controls[2], target)      # Toffoli (Lemma 6.2 special case)
        else
            # Barenco Lemma 6.1, ancilla-free: CV(c2)·CX(c1,c2)·CV†(c2)·CX(c1,c2)·CV(c1).
            V = sqrt_u2(inner)
            Vd = adjoint(V)
            c1, c2 = controls[1], controls[2]
            _apply_controlled_u2!(ctx, c2, V, target)
            _emit_cx!(ctx, c1, c2)
            _apply_controlled_u2!(ctx, c2, Vd, target)
            _emit_cx!(ctx, c1, c2)
            _apply_controlled_u2!(ctx, c1, V, target)
        end
    else
        # k ≥ 3: clean-|0⟩ AND-ladder (Barenco Cor 7.12) — phase-carrying U needs
        # a clean bit. AND all k controls onto one wire, fire ∧₁(U) off it, uncompute.
        (andw, ladder) = _and_onto_wire!(ctx, controls)
        _apply_controlled_u2!(ctx, andw, inner, target)
        _uncompute_and!(ctx, ladder)
    end
    nothing
end

# ∧_k(Perm) leaf: replay each MCX with the k outer controls prepended (fires iff
# outer controls all 1 AND the generator's local controls all 1).
function _apply_controlled!(ctx::AbstractContext, k::Int, controls::Vector{Int}, inner::Perm, targets::Vector{Int})
    for g in inner.gates
        local_controls = Int[targets[c] for c in g.controls]
        _emit_mcx!(ctx, vcat(controls, local_controls), targets[g.target])
    end
    nothing
end

# ∧_k(A⊗B): ONE shared control set gating both factors on disjoint targets
# (Delorme: control does NOT distribute over ⊗). Disjoint targets commute.
function _apply_controlled!(ctx::AbstractContext, k::Int, controls::Vector{Int}, inner::Tensor, targets::Vector{Int})
    na = nwires(inner.a)
    _apply_controlled!(ctx, k, controls, inner.a, targets[1:na])
    _apply_controlled!(ctx, k, controls, inner.b, targets[na+1:end])
    nothing
end

# ∧_k(a∘b) = ∧_k(a)∘∧_k(b): the §4.2 homomorphism (control over ∘). Apply
# controlled-b first (∘ is right-to-left), then controlled-a; shared targets.
function _apply_controlled!(ctx::AbstractContext, k::Int, controls::Vector{Int}, inner::Seq, targets::Vector{Int})
    _apply_controlled!(ctx, k, controls, inner.b, targets)
    _apply_controlled!(ctx, k, controls, inner.a, targets)
    nothing
end

# --- Emitter dispatch (uncontrolled values) -----------------------------

_emit!(ctx::AbstractContext, u::U2, qs::Vector{Int}) =
    (length(qs) == 1 || error("U2 needs exactly 1 wire"); _emit_u2!(ctx, u, qs[1]))

function _emit!(ctx::AbstractContext, p::Perm, qs::Vector{Int})
    for g in p.gates
        _emit_mcx!(ctx, Int[qs[c] for c in g.controls], qs[g.target])
    end
    nothing
end

function _emit!(ctx::AbstractContext, t::Tensor, qs::Vector{Int})
    na = nwires(t.a)
    _emit!(ctx, t.a, qs[1:na])
    _emit!(ctx, t.b, qs[na+1:end])
    nothing
end

function _emit!(ctx::AbstractContext, s::Seq, qs::Vector{Int})
    _emit!(ctx, s.b, qs)   # apply b first (∘ is right-to-left)
    _emit!(ctx, s.a, qs)
    nothing
end

function _emit!(ctx::AbstractContext, c::Ctrl, qs::Vector{Int})
    k = c.k
    controls = qs[1:k]
    targets = qs[k+1:end]
    _apply_controlled!(ctx, k, controls, c.inner, targets)
    nothing
end

# --- Public entry: apply! ----------------------------------------------

"""
    apply!(ctx, u::U2, wires::NTuple{1,WireID}) -> ctx

Fast path: a 1q `U2` accumulates in the per-wire fusion buffer (exact Hamilton
fuse) and reaches Orkan only at the next flush.
"""
function apply!(ctx::AbstractContext, u::U2, wires::NTuple{1,WireID})
    haskey(_core(ctx).wire_to_slot, wires[1]) || error("apply!: wire $(wires[1]) is not live in this context")
    _fuse!(ctx, wires[1], u)
    return ctx
end

"""
    apply!(ctx, v::ProcessValue, wires::NTuple{N,WireID}) -> ctx

Apply a process value to a tuple of wires (position 1 = the value's MSB wire).
Order of operations, all fail-loud: wire-count match; the §8.4 aliasing check on
REGISTER IDENTITY (before any FFI index check); liveness; flush of the touched
wires' fusion buffers; then the `Ad` emitter (`_emit!`) in Orkan qubit indices.
"""
function apply!(ctx::AbstractContext, v::ProcessValue, wires::NTuple{N,WireID}) where {N}
    nwires(v) == N || error("apply!: value $(typeof(v)) has $(nwires(v)) wires but $N given")
    _check_wire_aliasing(wires, v)
    core = _core(ctx)
    for w in wires
        haskey(core.wire_to_slot, w) || error("apply!: wire $w is not live in this context")
    end
    for w in wires
        _flush_wire!(ctx, w)
    end
    qs = Int[core.wire_to_slot[w] for w in wires]
    _emit!(ctx, v, qs)
    return ctx
end

"""
    apply!(ctx, v::ProcessValue, wires::AbstractVector{WireID}) -> ctx

The VECTOR-typed sibling of the tuple `apply!` (M7 kernel seam, bead
Sturm.jl-7a0v). Byte-for-byte the same logic over a `Vector`: the reversible
corner is the ONE value whose wire count is runtime DATA — a Bennett `Perm`
oracle spans data-dependent, unbounded `n` (hundreds of wires for arithmetic), so
an `NTuple{N}` type parameter is actively wrong for it (type explosion, per-`n`
recompilation, dynamic dispatch). `Perm.gates` is already a `Vector` for exactly
this reason. ADDITIVE (no existing signature moves), confined to the process-value
path; the emitter (`_emit!`) already takes a `Vector{Int}` of slots. The tuple
`apply!` above stays the frozen M2/M4/M5 fast path for fixed-arity values.
"""
function apply!(ctx::AbstractContext, v::ProcessValue, wires::AbstractVector{WireID})
    nwires(v) == length(wires) || error("apply!: value $(typeof(v)) has $(nwires(v)) wires but $(length(wires)) given")
    _check_wire_aliasing(wires, v)
    core = _core(ctx)
    for w in wires
        haskey(core.wire_to_slot, w) || error("apply!: wire $w is not live in this context")
    end
    for w in wires
        _flush_wire!(ctx, w)
    end
    qs = Int[core.wire_to_slot[w] for w in wires]
    _emit!(ctx, v, qs)
    return ctx
end

"""
    _check_wire_aliasing(wires, v)

PRD-v2 §8.4: distinct wires must be distinct REGISTER identities. Fires on
`WireID` (not raw Orkan index), and BEFORE the FFI shim's `_check_distinct` — so
`apply!(ctx, ctrl(X), (w, w))` (the kernel shadow of `when(a){not!(a)}`) is a
clear DSL error, not a cryptic FFI one. Both the tuple and the M7 Vector `apply!`
route through the same check (the vector method shares the fail helper).
"""
function _check_wire_aliasing(wires::NTuple{N,WireID}, v::ProcessValue) where {N}
    seen = Set{WireID}()
    for w in wires
        w in seen && _aliasing_fail(w, v)
        push!(seen, w)
    end
    nothing
end

function _check_wire_aliasing(wires::AbstractVector{WireID}, v::ProcessValue)
    seen = Set{WireID}()
    for w in wires
        w in seen && _aliasing_fail(w, v)
        push!(seen, w)
    end
    nothing
end

@noinline _aliasing_fail(w::WireID, v::ProcessValue) = error(
    "apply!(::$(typeof(v))): wire $w appears more than once — register aliasing is " *
    "forbidden (PRD-v2 §8.4); a control and its target (or two tensor factors) must " *
    "be distinct registers")
