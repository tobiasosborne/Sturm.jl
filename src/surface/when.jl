# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M5 (bead Sturm.jl-o5yh): `when` —
# STREAMING coherent control (surface construct 5), its three theorem-shaped
# guardrails, and the clean-ancilla exit witness (PRD-v2 §3.5/§3.4/§3.9/D13).
#
# ── THE SEMANTICS (§3.5) ────────────────────────────────────────────────
#   when(q, body)  ≡  trace `body` to a unitary-witnessed value V; apply
#                     ctrl(V) to (q, wires of body).
# The §4.2 homomorphism `ctrl(g∘h) = ctrl(g)∘ctrl(h)` (Delorme functoriality,
# Def 1 / p.6, docs/physics/delorme_control_as_constructor.md) is the LICENSE to
# implement this STREAMINGLY: push the control wire onto `ctx.control_stack`, run
# the body's ordinary surface ops, and let each action-family op lower as
# ctrl^k(op) op-by-op. No body is materialized; the DAG/materialize strategy is
# M8. Nested `when` ⇒ stack depth k ⇒ a flat count-k `Ctrl` value ⇒ the EXISTING
# ad.jl lowering (cx/cz/ccx/Barenco √V/AND-ladder). M5 writes ZERO new
# ctrl-lowering code.
#
# ── THE PARTITION (why `_act!`, not a control-aware `apply!`) ────────────
# `apply!` and ad.jl stay BYTE-FOR-BYTE the M2/M4 functions. The control/no-
# control split lives ABOVE `apply!`, at the action-family boundary, in the new
# `_act!`. Two surface effects deliberately keep calling raw `apply!` and so stay
# UNCONTROLLED, each on its own physics license:
#
#   • Preparation (`QBool`) — the §3.9 compute–uncompute lemma REQUIRES "alloc
#     (uncontrolled)": the fresh ancilla must be |0⟩ = |e_G⟩ in ALL control
#     branches at body entry (that is what the uncompute witness below relies on).
#     Controlling the prep gate would break the lemma.
#   • The `when(dual(q))` basis-change — Delorme Eq 16 (the conjugation law, p.9,
#     docs/physics/delorme_control_as_constructor.md): a control read in the
#     conjugate basis is `F_G · C_{|1⟩}(V) · F_G†`, and applying `F_G` (=H for
#     QBool) UNCONTROLLED then controlling in the computational basis denotes the
#     same channel as `C(F_G·V·F_G†)` — but is cheaper (3 vs ~10 gate emissions)
#     because the H is a fused 1q op, not a ctrl decomposition. Both routes equal
#     `C(VWV†)`; the sandwich is the economical one.
#
# ── THE GUARDRAILS — THREE FUNNELS, PROVEN EXHAUSTIVE ───────────────────
# Guardrail 1 (unitary-witness) and guardrail 2 (guard-externality) are Bădescu–
# Panangaden's own Conditions III (reversibility, p.35) and I (guard-externality,
# p.34; docs/physics/badescu_panangaden_quantum_alternation.md); the unitary-
# witness requirement is Yuan–Villanyi–Carbin's soundness/completeness pair
# (Thms 4.8/4.9, p.17, docs/physics/yuan_villanyi_carbin_control_flow.md); the
# no-embedding of a non-injective transition is their Thm 4.4 (p.15). Ying–Yu–
# Feng contribute ONLY guard-externality (Def 2.1(4), p.11, glossed p.12;
# docs/physics/ying_yu_feng_alternation.md). Guardrail 3 (bounded unrolling) is
# the non-monotonicity result (Bădescu–Panangaden Proposition, p.39) — a user-bug
# boundary with no active M5 detector (streaming unrolls whatever the closure
# does).
#
# COMPLETENESS (Proposal A's argument). Every NON-UNITARY surface effect funnels
# through exactly one of three context primitives — measurement `_measure_wire!`,
# trace `_trace_and_free!`, noise `_apply_channel_1q!` — so placing the control-
# stack check at those funnels is exhaustive OVER THE CURRENT SURFACE. Everything
# else the surface can do is unitary (`apply!`), and unitary is exactly what
# `ctrl` represents. The maintained coverage map (extend it when M7/M8 land):
#
#   # | surface entry            | effect      | reaches ctx via     | under `when`
#  ---|--------------------------|-------------|---------------------|-------------
#   1 | QBool(p,φ)/QBool(b)/plus… | prep        | allocate! + apply!  | alloc |0⟩ uncontrolled; prep uncontrolled (§3.9)
#   2 | not!(q) / not!(dual q)    | flip / mod  | _act!               | CONTROLLED (streaming)
#   3 | a⊻=b / q⊻=Bool / false⊻b / q̂⊻=r | entangle | _act! (+alloc for false⊻b) | CONTROLLED (fresh-prep of false⊻b uncontrolled)
#   4 | Bool(q::QBool)            | qc measure  | _measure_wire!      | BANNED — guardrail 1
#   5 | Bool(dual q)             | conj measure | _measure_wire!      | BANNED — guardrail 1 (top of Bool(::DualView))
#   6 | convert(Bool,q)          | implicit meas| _measure_wire!      | BANNED — funnels through #4
#   7 | ptrace!(w)               | explicit trace| _trace_and_free!   | BANNED — guardrail 1 (top of ptrace!)
#   8 | region-exit trace of an owned ancilla | dealloc | _trace_and_free! | CLEAN-ANCILLA ASSERT (§3.9), not banned
#   9 | apply_channel! (DM noise)| Kraus       | _apply_channel_1q!  | BANNED — forward hook (M8/M11)
#  10 | cases / @cases           | class. branch| (M8)               | BANNED — forward hook (guardrail 1)
#  11 | oracle(f,x) + MBU        | Bennett     | (M7)                | MBU EXCLUDED — reads control_stack (§3.4)
#
# ── FORWARD FLAGS (later milestones must NOT assume M5 proved these) ─────
#   • M7: `when`-control of `oracle`/`Perm` and the measurement-based-uncompute
#     EXCLUSION under a nonzero control stack (§3.4) are NOT proven by M5. M5
#     provides the `control_stack` an MBU strategy selector reads; the named test
#     and the `ctrl(::Perm)` wire-shift alignment land WITH M7.
#   • M8: `cases`/`@cases` and the Bool→token path must call `_assert_no_control`
#     (guardrail 1, row 10); DM `apply_channel!` gets the same under noise (row 9).
#     The §3.5 REQUIRED law test — streaming ≡ materialized, Choi-compared — needs
#     `UnitaryDAG`/Tracing (M8); M5 discharges only the STREAMING half.
#
# Physics distillations cited (audit-corrected loci): Delorme Def 1 p.6 / Eq 16
# p.9; Bădescu–Panangaden Conditions I p.34 / III p.35 / non-monotonicity p.39;
# Yuan–Villanyi–Carbin Thm 4.4 p.15 / Def 4.7 p.16 / Thms 4.8–4.9 p.17; Ying–Yu–
# Feng Def 2.1(4) p.11; Gavorová Lemma 1 (the controlization no-go that makes the
# unitary witness load-bearing — docs/physics/gavorova_controlization_no_go.md).

"""
    CLEAN_EPS

Tolerance for the clean-ancilla |1⟩-marginal witness (§3.9). A genuinely clean
scratch ancilla — allocated |0⟩, matched ctrl compute/uncompute — returns
to |0⟩ EXACTLY when the compute is a basis permutation (cx/ccx are exact) and to
within accumulated ZYZ float noise (`~1e-15`) when it routes through the ABC
skeleton. `1e-10` (the §4.1 float-law scale, = `U2_ATOL`) sits far above that
noise yet far below any physically meaningful |1⟩ weight (a dirty ancilla under a
superposed control leaks `~0.5`), so it never false-positives and always catches
a real leak.
"""
const CLEAN_EPS = 1e-10

# --- _act! : the control-aware apply! sibling (action family ONLY) -------

"""
    _act!(ctx, v::ProcessValue, wires) -> ctx

Apply `v` to `wires`, CONTROLLED by the live `when` stack. With an empty stack it
is exactly `apply!` (the uncontrolled fast paths — 1q fusion included — are
untouched). With depth `k` it (1) runs guardrail 2, (2) builds `ctrl^k(v)` via
the PUBLIC `ctrl` (a flat count-`k` `Ctrl` value; built ONLY through the public
`ctrl` combinator, never the private kernel constructor — the choke-point lint
stays honest), (3) prepends the `k` stack controls as the LEADING wires and calls
the UNCHANGED `apply!` — inheriting its aliasing/liveness/flush discipline and the
entire ad.jl lowering.

Because a control-wrapped op is ≥2 wires, `apply!` takes the general path (never the
1q fusion fast path), so a bare `U2` action can NEVER linger in the per-wire
buffer to flush uncontrolled later — the §8.1-class hole is closed by
construction (named test in test_m5_when.jl). Called ONLY by the action family
(surface/actions.jl); preps and view basis-changes keep calling raw `apply!`.
"""
function _act!(ctx::AbstractContext, v::ProcessValue, wires::NTuple{N,WireID}) where {N}
    core = _core(ctx)
    isempty(core.control_stack) && return apply!(ctx, v, wires)
    _guard_externality(ctx, wires)
    cv = v
    for _ in 1:length(core.control_stack)
        cv = ctrl(cv)                                   # flat ctrl^k via the public combinator
    end
    return apply!(ctx, cv, (core.control_stack..., wires...))   # controls are the LEADING wires
end

"""
    _guard_externality(ctx, wires)

Guardrail 2 (§3.5): the body must not operate on the control register — as a
target OR as an op-control, and THROUGH VIEWS. Both `wires` and the stack are
already parent `WireID`s (the action methods resolve `dual(·)` to `.parent`
before calling `_act!`; `when` stored the parent wire), so a plain identity
compare "sees through views" on both sides — no view logic here. This is
Bădescu–Panangaden Condition I (guard-externality, p.34) / Ying–Yu–Feng
Def 2.1(4) (p.11). `apply!`'s `_check_wire_aliasing` remains a generic backstop.

The illegal families get DISTINCT messages: measurement-of-anything under
control → guardrail 1 (`_assert_no_control`, fires earlier at the cast);
action-on-the-control → guardrail 2 (here). So `when(q) do Bool(q) end` is a
guardrail-1 error, while `when(q) do not!(q) end` is a guardrail-2 error.
"""
function _guard_externality(ctx::AbstractContext, wires::NTuple{N,WireID}) where {N}
    for w in wires, c in _core(ctx).control_stack
        w === c && error(
            "the `when` body operates on its control register $w (guardrail 2, " *
            "§3.5 / Bădescu–Panangaden Condition I, p.34): a body must not read or " *
            "write its guard — not as a target, not as an op-control, not through a " *
            "view. (Legal kickback names a DIFFERENT register as the target and lets " *
            "the control pick up phase through the `ctrl` mechanism.)")
    end
    nothing
end

# --- The clean-ancilla exit witness (§3.9) ------------------------------
#
# When a body-owned ancilla leaves a `when` region, `_trace_and_free!`
# (abstract.jl) calls this WHILE the control is still on the stack. Physics
# (Proposal A's necessity+sufficiency proof, = Yuan–Villanyi–Carbin
# synchronization, Def 4.7 p.16 / Thm 4.8 p.17): the streaming identity
#     alloc → ctrl(U) → dealloc  =  ctrl(dealloc ∘ U ∘ alloc)
# holds IFF `U` returns the ancilla to |0⟩ in the control=1 branch. Since alloc is
# uncontrolled (the ancilla is |0⟩ in ALL branches at entry) and every body op on
# it is control-wrapped (routes through `_act!`), the ancilla is |0⟩ in the control=0
# branch automatically. Hence "|0⟩ in the control-firing block" and "the ancilla's
# FULL |1⟩ marginal is 0" COINCIDE under the alloc-uncontrolled discipline. We
# assert the FULL marginal (`_marginal_p1` on Eager; the ancilla=1 diagonal block
# of ρ on DM): it is exactly "the ancilla is a DISENTANGLED |0⟩", which is
# necessary AND sufficient for freeing the slot without measuring AND for
# recycling it as a clean |0⟩. (It is strictly safer than the control-firing-block
# restriction: it additionally catches the pathological case of an uncontrolled
# non-|0⟩ prep inside the body — |1⟩ in the control=0 branch — where freeing
# without measuring would corrupt the recycled slot and decohere the control. See
# the deviation note in WORKLOG.) An unclean ancilla under a superposed control is
# entangled with it, so tracing it would decohere the control — a silent wrong
# channel, which is why the unwitnessed case is a LOUD error (§3.5).

"Full |1⟩-marginal clean-ancilla witness on a PURE state (Eager)."
function _clean_ancilla_assert!(ctx::EagerContext, w::WireID)
    core = _core(ctx)
    _flush_all!(ctx)
    leak = _marginal_p1(core.state, core.wire_to_slot[w])
    leak < CLEAN_EPS || _clean_ancilla_fail(w, leak)
    nothing
end

"Full |1⟩-marginal (ancilla=1 diagonal block trace of ρ) witness on DM."
function _clean_ancilla_assert!(ctx::DensityMatrixContext, w::WireID)
    core = _core(ctx)
    _flush_all!(ctx)
    amask = 1 << core.wire_to_slot[w]
    ρ = _density(core.state, core.capacity)
    leak = 0.0
    @inbounds for i in 0:((1 << core.capacity) - 1)
        (i & amask) != 0 && (leak += real(ρ[i+1, i+1]))
    end
    leak < CLEAN_EPS || _clean_ancilla_fail(w, leak)
    nothing
end

@noinline _clean_ancilla_fail(w::WireID, leak::Real) = error(
    "clean-ancilla witness FAILED for $w: its |1⟩-marginal is $(leak) > $(CLEAN_EPS) " *
    "(§3.9 / Yuan–Villanyi–Carbin synchronization, Def 4.7). A scratch ancilla must " *
    "be uncomputed to a DISENTANGLED |0⟩ before it leaves a `when` body — otherwise " *
    "tracing it would decohere the control (a silent wrong channel). Uncompute it " *
    "inside the body (matched ctrl compute/uncompute).")

# --- The do-block plumbing ----------------------------------------------

"""
    _when_core(ctx, control_wire::WireID, f)

The nested try/finally that (a) pushes the control frame, (b) opens a region so
body-owned ancillas are clean-ancilla-asserted at body exit WHILE the control is
still up, and (c) pops the control on ANY throw. The topology is load-bearing:
`_push_control!` outside the inner `try` and `_pop_control!` in the OUTER
`finally` guarantee the stack is popped even if the body OR the region-exit
clean-ancilla assert throws — the context is never left with a stale control
frame. `_exit_region!` is in the INNER `finally` so the clean-ancilla assert runs
with the control still on the stack.

Masking caveat (accepted for M5): if the body throws AND the region-exit witness
also throws, Julia's `finally` surfaces the witness error and masks the body's.
Both are fail-loud, so the user still crashes; the FIRST error is hidden (no
clean in-flight-exception introspection at Julia 1.12). Recorded in WORKLOG.
"""
function _when_core(ctx::AbstractContext, control_wire::WireID, f)
    haskey(_core(ctx).wire_to_slot, control_wire) ||
        error("when: control wire $control_wire is not live (already traced/consumed)")
    _push_control!(ctx, control_wire)
    try
        _enter_region!(ctx)
        try
            f()
        finally
            _exit_region!(ctx)           # clean-ancilla assert runs HERE (control still up)
        end
    finally
        _pop_control!(ctx, control_wire) # ALWAYS runs, even if _exit_region! threw
    end
    return nothing
end

"""
    when(q::QBool) do … end
    when(dual(q)) do … end

Coherent control (surface construct 5, §3.5): run the do-block's ops CONTROLLED
by `q`, streamingly. The body reads as ordinary control flow; its ops apply as
`ctrl^k(op)`. The control register participates as input AND output — kickback is
physics (`when(q) do not!(dual(r)) end` is a CZ; `q` picks up the relative phase).
Returns `nothing` (the body ran once at stream time; there is no control-gated
return value to surface — `when` is a control-flow statement, its denotation is
the applied channel).

Guardrails (loud errors): (1) no cast / `ptrace!` / noise inside the body; (2) the
body may not touch the control register (target, op-control, or through a view);
(3) bounded unrolling only. Body-owned scratch ancillas must be uncomputed to a
disentangled |0⟩ before body exit (the §3.9 clean-ancilla witness). The
anti-control idiom is the `not!` sandwich (`not!(q); when(q) do … end; not!(q)`).

`when(dual(q))` reads the control in the conjugate basis (fires on `|−⟩` for a
`QBool`): the character transform `F_G` (=H) is applied uncontrolled, the body
streams under `|1⟩`-control, then `F_G†` restores the basis (Delorme Eq 16). The
pushed control is the PARENT wire, so guardrail 2 still sees `q` through the view.
"""
when(f, q::AbstractQubit) = _when_core(_here(q), q.wire, f)

function when(f, v::DualView)
    p = v.parent
    ctx = _here(p)
    F = _dual_transform(p)                   # H for QBool (ℤ₂ self-dual, F = F†)
    apply!(ctx, F, (p.wire,))                # basis-change control, UNCONTROLLED (fuses; Delorme Eq 16)
    try
        _when_core(ctx, p.wire, f)
    finally
        apply!(ctx, adjoint(F), (p.wire,))   # restore basis, UNCONTROLLED (even-outer finally)
    end
    return nothing
end
