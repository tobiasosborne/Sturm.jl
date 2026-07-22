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
    isempty(core.when_frames) || _tee_record_apply!(ctx, v, wires)   # M8 tee-tracing (design §5)
    cv = v
    for _ in 1:length(core.control_stack)
        cv = ctrl(cv)                                   # flat ctrl^k via the public combinator
    end
    return apply!(ctx, cv, (core.control_stack..., wires...))   # controls are the LEADING wires
end

"""
    _act!(ctx, v::ProcessValue, wires::AbstractVector{WireID}) -> ctx

The VECTOR-typed sibling (M7 kernel seam, bead Sturm.jl-7a0v): identical control-
awareness over a `Vector` of wires — the data-width `Perm` oracle path (the one
value whose wire count is runtime data; see the Vector `apply!` in ad.jl). Under
a depth-`k` stack `cv = ctrl^k(Perm) = Perm` (the perm.jl closure), applied with
the `k` stack controls prepended as the LEADING wires. ADDITIVE; the tuple `_act!`
above stays the fixed-arity action-family path.
"""
function _act!(ctx::AbstractContext, v::ProcessValue, wires::AbstractVector{WireID})
    core = _core(ctx)
    isempty(core.control_stack) && return apply!(ctx, v, wires)
    _guard_externality(ctx, wires)
    isempty(core.when_frames) || _tee_record_apply!(ctx, v, wires)   # M8 tee-tracing (design §5)
    cv = v
    for _ in 1:length(core.control_stack)
        cv = ctrl(cv)
    end
    return apply!(ctx, cv, vcat(core.control_stack, wires))   # controls are the LEADING wires
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
        w === c && _guard_externality_fail(w)
    end
    nothing
end

# The M7 Vector-typed sibling (data-width `Perm` oracle path); same guardrail 2.
function _guard_externality(ctx::AbstractContext, wires::AbstractVector{WireID})
    for w in wires, c in _core(ctx).control_stack
        w === c && _guard_externality_fail(w)
    end
    nothing
end

@noinline _guard_externality_fail(w::WireID) = error(
    "the `when` body operates on its control register $w (guardrail 2, " *
    "§3.5 / Bădescu–Panangaden Condition I, p.34): a body must not read or " *
    "write its guard — not as a target, not as an op-control, not through a " *
    "view. (Legal kickback names a DIFFERENT register as the target and lets " *
    "the control pick up phase through the `ctrl` mechanism.)")

# --- The clean-ancilla witness: STRUCTURAL SEAL + demoted debug marginal ----
#
# M8 design gate (`docs/design/m8-5hr7-unitary-block-design.md` §2.5/§5, D13 as
# shipped in PRD §3.5/§3.9). F1's lesson: a statevector |1⟩-marginal on ONE run
# certifies the *run*, not the *program* — the adversary `a = QBool(false); a ⊻= r;
# drop a` passes the marginal with `r = |0⟩` yet dephases `r = |+⟩`. The WITNESS is
# now the STRUCTURAL body-exit seal (`_seal_when_frame!` below): a property of the
# program transcript, universally quantified over inputs. The runtime |1⟩-marginal
# survives ONLY as a demoted DEBUG cross-check "that the certificate was honoured —
# sound fail-fast per run, never itself the witness" (PRD §3.5 Eager bullet):
# a structurally-certified body whose marginal nonetheless leaks indicates an
# executor/lowering/numeric/cert-checker defect (a mis-built certificate).
#
# The marginal methods (`_clean_ancilla_assert!`) are UNCHANGED — they remain the
# M7 Bennett-oracle scratch witness (`_free_clean!`, bennett/bridge.jl), whose
# structural backing is Bennett's `(★)` PermClean by construction, and they back
# the `when` DEBUG cross-check (`_clean_ancilla_debug!`, flag-gated). The `when`
# region-exit path (`_trace_and_free!`) no longer calls the marginal as the witness.

"""
    DEBUG_CLEAN_ANCILLA

Toggle (default `false`) for the demoted `when` clean-ancilla DEBUG cross-check
(design §2.5). When `true`, the runtime |1⟩-marginal is asserted at every `when`
scratch release as an independent fail-fast — defense in depth over the structural
seal. Never the witness (a single input cannot certify a universal containment).
"""
const DEBUG_CLEAN_ANCILLA = Ref(false)

"Full |1⟩-marginal clean-ancilla check on a PURE state (Eager). M7-oracle witness / `when` debug cross-check."
function _clean_ancilla_assert!(ctx::EagerContext, w::WireID)
    core = _core(ctx)
    _flush_all!(ctx)
    leak = _marginal_p1(core.state, core.wire_to_slot[w])
    leak < CLEAN_EPS || _clean_ancilla_fail(w, leak)
    nothing
end

"Full |1⟩-marginal (ancilla=1 diagonal block trace of ρ) check on DM."
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

"""
    _clean_ancilla_debug!(ctx, w)

The DEMOTED marginal cross-check (design §2.5): fires ONLY when
`DEBUG_CLEAN_ANCILLA[]` is set, cross-checking that the structural certificate was
honoured. Off by default — the structural body-exit seal is the sole witness.
"""
@inline function _clean_ancilla_debug!(ctx::AbstractContext, w::WireID)
    DEBUG_CLEAN_ANCILLA[] && _clean_ancilla_assert!(ctx, w)
    nothing
end

# --- M8 EAGER TEE-TRACING: the WhenFrame, the recorder, the structural seal ---
#
# A `when` body STREAMS (M5 semantics, unchanged) and SIMULTANEOUSLY tee-records a
# `ChannelDAG` transcript into the top `WhenFrame` (design §5). At body exit the
# transcript is structurally sealed: every body-owned scratch ancilla must be
# released by a matched compute/uncompute (`nothing`-cert region-exit scratch — the
# 2-mutual-adjoint form, reusing the shipped `_footprint`/`adjoint` checkers) or
# carry a combinator-supplied `PermClean` (the M7 oracle's Bennett `(★)` scratch,
# recorded by `_free_clean!`). A failed seal POISONS the context (TR2). The seal is
# `certify`'s scratch-matching logic applied to the streamed transcript; it does NOT
# wrap the whole body in a `UnitaryBlock` (a pure-scratch body denotes identity on
# zero external wires — a legitimate no-op that TR7 forbids REPRESENTING as a block).
# The independent `certify(::ChannelDAG) → UnitaryBlock` path (slice 1) is what the
# `M8.WHEN.STREAM-MATERIALIZED-*` law test materializes and controls.

"""
    WhenFrame()

One tee-tracing frame per live `when` region (design §5): a mutable `DAGBuilder`
accumulating the streamed body transcript, and `w2pid` mapping each live body
`WireID` to its port in that builder. Body-owned scratch is an `alloc!` port; a
first-touched external wire is an `input!` port. EMPTY-overhead: a frame exists only
inside a `when`.
"""
mutable struct WhenFrame
    builder::DAGBuilder
    w2pid::Dict{WireID,PortID}
end
WhenFrame() = WhenFrame(DAGBuilder(), Dict{WireID,PortID}())

_tee_top(core::ContextCore) = core.when_frames[end]::WhenFrame

"""
    _tee_pid!(frame, w) -> PortID

The port for body wire `w` in `frame.builder`: reuse if seen, else declare a fresh
boundary `input!` (an external wire the body reaches; scratch is declared by
`_tee_record_alloc!`).
"""
function _tee_pid!(frame::WhenFrame, w::WireID)
    haskey(frame.w2pid, w) && return frame.w2pid[w]
    pid = input!(frame.builder)
    frame.w2pid[w] = pid
    return pid
end

"Record a body-owned scratch `AllocN` (called from `allocate!` under a live frame)."
function _tee_record_alloc!(ctx::AbstractContext, w::WireID)
    frame = _tee_top(_core(ctx))
    frame.w2pid[w] = alloc!(frame.builder)
    nothing
end

"Record an `ApplyN` of the UNCONTROLLED body value `v` on `wires` (the transcript candidate)."
function _tee_record_apply!(ctx::AbstractContext, v::ProcessValue, wires)
    frame = _tee_top(_core(ctx))
    pids = PortID[_tee_pid!(frame, w) for w in wires]
    apply_node!(frame.builder, v, pids...)
    nothing
end

"""
    _tee_record_trace!(ctx, w, cert)

Record a scratch `TraceN` with the given certificate: `nothing` for a region-exit
release (the seal derives its matched-uncompute cert structurally), or a
combinator-supplied `PermClean` for the M7 oracle's Bennett-clean scratch.
"""
function _tee_record_trace!(ctx::AbstractContext, w::WireID, cert::Union{Nothing,CleanCert})
    frame = _tee_top(_core(ctx))
    haskey(frame.w2pid, w) || return nothing          # a wire the frame never recorded
    trace!(frame.builder, frame.w2pid[w]; cert = cert)
    delete!(frame.w2pid, w)
    nothing
end

@noinline function _poison_seal!(ctx::AbstractContext, msg::AbstractString)
    _core(ctx).poison = String(msg)
    error("`when`-body structural clean-ancilla seal FAILED (design §2.5/TR2 poison): $msg")
end

"""
    _seal_when_frame!(ctx)

The STRUCTURAL WITNESS (design §5, F1): fold the streamed transcript and verify
every body-owned scratch ancilla is released by a matched compute/uncompute (the
certificate is the witness, not a runtime marginal). A failed seal POISONS the
context (TR2) and throws loud. A body with no scratch seals trivially (`NoAncilla`).
"""
function _seal_when_frame!(ctx::AbstractContext)
    frame = _tee_top(_core(ctx))
    any(nd -> nd isa AllocN, frame.builder.nodes) || return nothing   # NoAncilla — nothing to seal
    dag = freeze(frame.builder)
    has_barrier(dag) && _poison_seal!(ctx,
        "the body holds a measurement/cases/noise barrier under control (guardrail 1 should have caught this)")
    id2lin = _id_to_lineage(dag)
    scratch_lins = Set{Int}(nd.out.lineage for nd in dag.nodes if nd isa AllocN)
    traced_lins = Set{Int}()
    for nd in dag.nodes
        nd isa TraceN || continue
        lin = get(id2lin, nd.in, nothing)
        (lin === nothing || !(lin in scratch_lins)) && continue
        push!(traced_lins, lin)
        _seal_check_scratch(ctx, dag, nd, lin, id2lin, scratch_lins)
    end
    for al in scratch_lins
        al in traced_lins || _poison_seal!(ctx,
            "scratch lineage $al was allocated inside the body but never released — a leaked ancilla")
    end
    nothing
end

"""
    _seal_check_scratch(ctx, dag, tracenode, lin, id2lin, scratch_lins)

Discharge one scratch release. A `PermClean` cert on the trace (combinator-carried,
M7 oracle) trusts Bennett's `(★)`. Otherwise (region-exit `nothing`-cert scratch)
the matched compute/uncompute is checked structurally by the SHARED `_is_adjoint_pair`
(`src/channel/cert.jl` — the single discipline `certify`'s `_check_matched_pair` also
uses): the `ApplyN`s targeting `lin` must be either none (an untouched `|0⟩`) or
exactly two writers on the SAME ports whose values are operator adjoints (the compute
and its reversal — Bennett eq (3)). `_is_adjoint_pair` prefers exact structural
provenance (tier A) and falls back to phase-inclusive process `≈` (tier B) for a
self-adjoint `U2` (`X`, `H`, `Z`), whose `adjoint` differs in stored fields though
`X† = X` as an operator — a comparison of two PROGRAM VALUES (universally quantified
over inputs, no state), so F1's "the certificate, not the run, is the witness" holds.
The general palindrome over an arbitrarily-shaped scratch cone (and the case where the
inner `M` disturbs a data wire the compute read) is the deferred syntactic verifier
(design §2.3 secondary, TR4/R4); `within` is its combinator form.
"""
function _seal_check_scratch(ctx, dag::ChannelDAG, tracenode::TraceN, lin::Int, id2lin, scratch_lins)
    tracenode.cert isa PermClean && return nothing        # oracle: Bennett (★), trusted
    writers = ApplyN[]
    for nd in dag.nodes
        nd isa ApplyN || continue
        (_c, tgts) = _footprint(nd.v, collect(nd.ports))
        any(p -> get(id2lin, p, -1) == lin, tgts) && push!(writers, nd)
    end
    nw = length(writers)
    nw == 0 && return nothing                              # untouched |0⟩
    (nw == 2 && writers[1].ports == writers[2].ports &&
        _is_adjoint_pair(writers[1].v, writers[2].v)) && return nothing
    _poison_seal!(ctx,
        "scratch lineage $lin has $nw compute/uncompute writer(s) that are not a matched " *
        "pair (same ports, mutually-adjoint values) — the F1 adversary. A state marginal " *
        "cannot certify a universally-quantified clean-subspace containment. Uncompute the " *
        "scratch inside the body (matched ctrl compute/uncompute), or use the `within` combinator.")
end

# --- The do-block plumbing ----------------------------------------------

"""
    _when_core(ctx, control_wire::WireID, f)

The nested try/finally that (a) pushes the control frame + the M8 tee-tracing
`WhenFrame`, (b) opens a region so body-owned ancillas are recorded/released at body
exit WHILE the control is still up, (c) STRUCTURALLY SEALS the streamed transcript
on the SUCCESS path (the witness — design §5), and (d) pops the tee-frame and
control on ANY throw. The topology is load-bearing: the frame/control pushes precede
the inner `try` and their pops sit in the OUTER `finally`, so the stacks are restored
even if the body, the region-exit trace, OR the seal throws. `_exit_region!` (INNER
`finally`) traces body scratch — recording each `TraceN` into the tee-frame — BEFORE
the seal reads the completed transcript. `_seal_when_frame!` runs AFTER the inner
`try`/`finally` so it fires ONLY when the body ran to completion (a mid-body throw
skips the seal and surfaces the user's error; the transcript would be incomplete).

TR2 failure topology (design §8): the streaming path runs effects BEFORE this late
seal, so a failed seal cannot be unwound — `_seal_when_frame!` POISONS the context
and throws; every subsequent surface op fails loud naming the seal failure. The SAME
topology covers a mid-body throw: if a user exception escapes the body (or the
region-exit trace) with UN-SEALED scratch allocated, `_when_error_poison!` poisons the
context (a `catch` must not resume on a context whose scratch was recycled without a
cleanliness proof — the dirty-ancilla silent-wrongness class), then the ORIGINAL error
is rethrown. A body that allocated no scratch propagates its error unpoisoned (the
context stays usable — the M5 `not!(r); error()` unwind idiom).
"""
function _when_core(ctx::AbstractContext, control_wire::WireID, f)
    core = _core(ctx)
    haskey(core.wire_to_slot, control_wire) ||
        error("when: control wire $control_wire is not live (already traced/consumed)")
    _push_control!(ctx, control_wire)
    push!(core.when_frames, WhenFrame())           # M8 tee-tracing frame (design §5)
    try
        try
            _enter_region!(ctx)
            try
                f()
            finally
                _exit_region!(ctx)       # traces body scratch → records TraceNs (control still up)
            end
            _seal_when_frame!(ctx)       # STRUCTURAL WITNESS — success path (TR2 poison on seal failure)
        catch err
            _when_error_poison!(ctx, err)   # mid-body throw with un-sealed scratch ⇒ poison (TR2)
            rethrow()
        end
    finally
        pop!(core.when_frames)           # ALWAYS restore the tee-frame stack
        _pop_control!(ctx, control_wire) # ...and the control stack, even on a throw
    end
    return nothing
end

"""
    _when_error_poison!(ctx, err)

TR2 mid-body extension (design §8): an exception escaped a `when` body before its
transcript was sealed. If a failed SEAL already poisoned the context, keep that
message. Otherwise, if the frame recorded any `AllocN` (scratch was allocated — and,
on this error path, freed by the region-exit trace WITHOUT a cleanliness proof),
POISON so a user `catch` cannot resume on a context with recycled-but-unverified
scratch (the dirty-ancilla silent-wrongness class). A body that allocated nothing is
left unpoisoned — its error propagates and the context stays usable.
"""
function _when_error_poison!(ctx::AbstractContext, err)
    core = _core(ctx)
    core.poison === nothing || return nothing           # a failed seal already poisoned — keep its message
    any(nd -> nd isa AllocN, _tee_top(core).builder.nodes) || return nothing   # no scratch ⇒ propagate clean
    core.poison = "an exception escaped a `when` body with un-sealed scratch ancilla — the " *
        "transcript was never sealed, so scratch cleanliness is unverified and the region-exit " *
        "trace recycled it WITHOUT a proof (dirty-ancilla corruption risk, TR2). Escaped " *
        "exception: $(sprint(showerror, err))"
    nothing
end

"""
    _when_capture(ctx, control_wire, f) -> Union{UnitaryBlock,Nothing}

Stream `f` under `control_wire` exactly as `_when_core` does (same seal, same TR2
poison), AND return the sealed transcript as `M(B) = certify(trace(B))` — the
MATERIALIZED unitary block — captured from the SAME streaming run whose applied
channel is `S(B)`. This is the materialize half of the `M8.WHEN.STREAM-MATERIALIZED`
law (design §3.4, §7.10 part 4): the streamed value and its materialization denote
the same channel (compared ctrl-wrapped). Returns `nothing` for a body with no
external boundary (a pure-scratch identity — TR7 forbids a zero-port `UnitaryBlock`)
or one carrying scratch (whose per-run `nothing`-cert traces certify cannot re-seal
without the deferred verifier — the seal already witnessed cleanliness). Kernel-
internal materialize/test hook, NOT a surface construct (TR3).
"""
function _when_capture(ctx::AbstractContext, control_wire::WireID, f)
    core = _core(ctx)
    haskey(core.wire_to_slot, control_wire) ||
        error("when: control wire $control_wire is not live (already traced/consumed)")
    _push_control!(ctx, control_wire)
    push!(core.when_frames, WhenFrame())
    block = nothing
    try
        _enter_region!(ctx)
        try
            f()
        finally
            _exit_region!(ctx)
        end
        _seal_when_frame!(ctx)
        dag = freeze(_tee_top(core).builder)
        if !isempty(dag.qin) && !any(nd -> nd isa AllocN, dag.nodes)
            block = certify(dag)          # NoAncilla external-boundary body → UnitaryBlock
        end
    finally
        pop!(core.when_frames)
        _pop_control!(ctx, control_wire)
    end
    return block
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
