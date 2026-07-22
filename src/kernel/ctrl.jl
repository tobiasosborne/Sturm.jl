# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M1: `Ctrl` and the `ctrl`
# constructor — THE SINGLE CHOKE POINT (PRD-v2 §4.2). `ctrl` is the only
# constructor of controlled lowerings in the entire system: Cirq/Qiskit/pytket
# each carried a global-phase field yet shipped controlled-decomposition phase
# bugs for years because the bug lived at whichever of many call sites built
# the controlled circuit. One total code path on phase-carrying values is the
# structural invariant they lacked.
#
# THE `_ctrl`/`Ctrl` CONSTRUCTION CHOKE POINT IS MECHANICALLY ENFORCED: the
# only constructor is `_ctrl` (a private inner constructor), and a boot lint
# (test/runtests.jl) asserts that `_ctrl(` and `Ctrl(` appear in src/ ONLY in
# this file. A second boot lint asserts controlled-lowering tokens
# (`orkan_cx`, `controlled`) appear only under src/kernel/ or src/orkan/.
#
# NO `ctrl(::ProcessValue)` CATCH-ALL (Proposal B §5.4, chosen over a generic
# fallback). Totality is by exhaustive concrete methods — `ctrl(::U2)`,
# `ctrl(::Perm)`, `ctrl(::Ctrl)`, `ctrl(::Tensor)`, `ctrl(::Seq)` — so an
# unhandled kind is a `MethodError`, not a silent wrong wrap. This is
# load-bearing: a catch-all would silently wrap future non-unitary
# channel-DAG nodes, and control on a measurement is UNREPRESENTABLE by axiom
# P4 (PRD-v2 §4.4) — `MethodError` is the correct failure. Mirrors P9's
# no-catch-all-on-`Function` rule. M8 adds exactly one method,
# `ctrl(::UnitaryDAG)`, with no change to existing code.
#
# Physics grounding:
#   docs/physics/delorme_control_as_constructor.md — control as a constructor:
#     homomorphism over ∘ (Def 1 / p.6), adjoint compatibility (Prop 1, p.12),
#     conjugation law Eq 16, NON-functoriality over ⊗ (Caveats), nested
#     controls commute (Eq 14) ⇒ the flat count is the faithful representation.
#   docs/physics/tang_wright_2025_controlled_unitaries.md — Thm 1.1: control
#     makes global phase physical (ctrl(−I) = diag(1,1,−1,−1) ≠ I); the
#     phase-carrying representation is load-bearing exactly at ctrl's denotation.

"""
    Ctrl{V}(k, inner)   [constructed only via `ctrl`]

A `k`-fold `|1…1⟩`-controlled process value: `k` control wires (the leading
wires) gate `inner`, firing when all controls are `1`. FLAT control count, not
nesting: `ctrl(ctrl(u))` is `Ctrl(2, u)`, never `Ctrl(1, Ctrl(1, u))`. The `k`
controls are interchangeable (nested controls commute — Delorme Eq 14,
`docs/physics/delorme_control_as_constructor.md`), so a count is the faithful
normal form of the nest, and `Ctrl{V}` stays one concrete type regardless of
depth (type-stable `ctrl(::Ctrl{U2})::Ctrl{U2}`).

`inner` is the BASE value (never itself a `Ctrl`). Its only constructor is the
private `_ctrl`; user/library code reaches it exclusively through `ctrl`.
"""
struct Ctrl{V<:ProcessValue} <: ProcessValue
    k::Int
    inner::V
    # PRIVATE constructor — the choke point. `ctrl` is the only caller.
    global _ctrl(k::Int, inner::V) where {V<:ProcessValue} = new{V}(k, inner)
end

nwires(c::Ctrl) = c.k + nwires(c.inner)

"""
    ctrl(u::U2)   -> Ctrl{U2}
    ctrl(c::Ctrl) -> Ctrl
    ctrl(t::Tensor)
    ctrl(s::Seq)
    ctrl(p::Perm) -> Perm     [in perm.jl: the reversible corner absorbs]

Add one `|1⟩` control. A controlled 1q gate is a 2-wire operator that carries
`inner`'s global phase into an observable relative phase — so it is NOT a `U2`
and must wrap (`docs/physics/tang_wright_2025_controlled_unitaries.md`). On a
`Ctrl`, bump the flat count (Toffoli-grade). On `Perm`, the result stays a
`Perm` (closure, perm.jl).

`ctrl` is deliberately NOT pushed through `⊗`: `ctrl(a⊗b)` is stored as
`Ctrl{Tensor}` (one shared control gating both), never `Tensor(ctrl a, ctrl b)`
(two controls) — exactly Delorme's `C(f⊗g) ≠ C(f)⊗C(g)`
(`docs/physics/delorme_control_as_constructor.md`, Caveats). `Seq` likewise
wraps (denotation-correct); the executable homomorphism lives in `∘(::Ctrl,::Ctrl)`.
"""
ctrl(u::U2) = _ctrl(1, u)
ctrl(c::Ctrl) = _ctrl(c.k + 1, c.inner)
ctrl(t::Tensor) = _ctrl(1, t)
ctrl(s::Seq) = _ctrl(1, s)

"""
    ctrl(b::UnitaryBlock) -> Ctrl{UnitaryBlock{N}}

THE ONE method M8 adds to the choke point (design `m8-5hr7` §1.4). A certified
`UnitaryBlock` is a process value (only a certified block may be controlled — P4,
§4.4), so it wraps exactly like `ctrl(::Tensor)`: `Ctrl{UnitaryBlock{N}}`, one
shared control gating the whole block. Soundness is the §4.2 control-scope-
reassociation law: under control, the block's internal `AllocN`/`TraceN` stay
UNCONTROLLED and only its `ApplyN`s are control-wrapped, because a `MatchedPair`
body `C†∘M∘C` satisfies `ctrl(C†∘M∘C) = (1⊗C†)∘ctrl(M)∘(1⊗C)` — the ancilla
round-trips `|0⟩→…→|0⟩` in BOTH control branches (control=0: `ctrl(M)=I` so
`C†∘C=I` on the ancilla; control=1: `C†` uncomputes what `C` wrote). Cleanliness is
ALGEBRAIC, not state-dependent (design §1.4) — the property F1's `|1⟩`-marginal
assert lacks. The certificate is what makes this the ONE sound `ctrl` extension;
`denoted_matrix(::Ctrl{UnitaryBlock})` reads off the block's phase-fixed U(d)
representative and controls it (`docs/physics/tang_wright_2025_controlled_unitaries.md`).

(The uncontrolled execution lowering `_emit!(ctx, ::UnitaryBlock, …)` — replaying
the body against a live context, and its controlled sibling that leaves alloc/trace
uncontrolled — is the M8 part-4 Eager tee-tracing seam, deliberately NOT in this
slice; see the fail-loud stub in `src/orkan/ad.jl`.)
"""
ctrl(b::UnitaryBlock) = _ctrl(1, b)

"""
    adjoint(c::Ctrl) -> Ctrl

`(C_k g)† = C_k(g†)` — control and adjoint commute (PRD-v2 §4.2; Delorme
Prop 1, `docs/physics/delorme_control_as_constructor.md`). Same control count,
inner daggered.
"""
Base.adjoint(c::Ctrl) = _ctrl(c.k, adjoint(c.inner))

"""
    ∘(a::Ctrl, b::Ctrl)

Same control count ⇒ FUSE: `Ctrl(k, a.inner) ∘ Ctrl(k, b.inner) =
Ctrl(k, a.inner ∘ b.inner)` — the §4.2 homomorphism `ctrl(g)∘ctrl(h) =
ctrl(g∘h)` made into the composition rule, and the streaming license D13/§3.5
needs (apply `ctrl(op)` op-by-op). Type-stable on the `Ctrl{U2}` path since
`U2∘U2→U2`. Differing counts on equal width are a genuinely different operator
⇒ lazy `Seq` fallback, never a wrong fusion.
"""
function Base.:∘(a::Ctrl, b::Ctrl)
    a.k == b.k && return _ctrl(a.k, a.inner ∘ b.inner)
    @assert nwires(a) == nwires(b) "Ctrl ∘: width mismatch ($(nwires(a)) vs $(nwires(b)))"
    return Seq(a, b)
end

"""
    denoted_matrix(c::Ctrl) -> Matrix{ComplexF64}

`(I_K − |1…1⟩⟨1…1|) ⊗ I_d + |1…1⟩⟨1…1| ⊗ U`, with `K = 2^k` and `U =
denoted_matrix(inner)` (d×d): identity on every non-firing block, `inner` in
the leading-controls-all-`1` block (the LAST block, controls as MSBs).

Because `U` is the DENOTED matrix (phase included), `ctrl(e^{iα}g) ≠ ctrl(g)`
— the global phase of `g` lands on the firing block's diagonal as a relative
phase (`ctrl(gphase(α)) = diag(1,1,e^{iα},e^{iα})`, a Z-rotation on the
control; `docs/physics/delorme_control_as_constructor.md` §5;
`docs/physics/tang_wright_2025_controlled_unitaries.md` Thm 1.1). The
phase-carrying representation is load-bearing exactly here.
"""
function denoted_matrix(c::Ctrl)
    U = denoted_matrix(c.inner)
    d = size(U, 1)
    K = 1 << c.k
    N = K * d
    M = _eye(N)
    r0 = (K - 1) * d
    for j in 1:d, i in 1:d
        M[r0+i, r0+j] = U[i, j]
    end
    return M
end
