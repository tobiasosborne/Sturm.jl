# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M8 (bead Sturm.jl-szx1), the i4ri
# classical-control gate (`docs/design/m8-i4ri-classical-control-design.md`) and
# the 5hr7 channel-IR gate (`docs/design/m8-5hr7-unitary-block-design.md`),
# TRACING slice (part 7, Tracing half): the `TracingContext` — the COMPILER
# context that executes NOTHING and materializes a program into a `ChannelDAG`.
#
# ── WHY A THIRD CONTEXT (the trichotomy, i4ri §13) ──────────────────────────
# Eager is the RUNTIME semantics (mid-circuit measurement + feed-forward, real
# scalar outcomes, host `if`); DM is the PHYSICAL DENOTATION (the platonic state
# under channels, where one-run Choi law tests live); Tracing is the COMPILER —
# the IR for optimization reasoning. Under Tracing there is NO STATE AT ALL
# (design §2.1): a program with no eager/DM execution allocates no Orkan state
# and makes NO FFI call. The context materializes the program STRUCTURE:
#   • allocations            → `AllocN`
#   • actions / `apply!`      → `ApplyN` (PROCESS VALUES, never gate names)
#   • scope-exit traces       → `TraceN`
#   • `Bool(q)` / `Int(x)`    → `MeasureN` (a Bool-typed classical out-port),
#                               returning a WIRE token (`ClassicalBit{TracingContext}`
#                               / `ClassicalWord{W,TracingContext}` — the F16/slice-4
#                               token types with `C=TracingContext`, Ruling D)
#   • `cases` / `@cases`      → an acyclic `CasesN` with nested arm regions
#
# ── THE ORDINARY-JULIA-RUNS-ONCE MODEL (design §1.2) ────────────────────────
# The circuit is built by ordinary Julia executed ONCE at trace time. Static
# loops/indices/widths are concrete and unroll; the ONLY non-concrete value is a
# measurement TOKEN. Tokens flow through the T1–T4 restricted classical SSA
# (surface/tokens.jl) exactly as under DM — the token type/algebra is generic
# over the context parameter `C`; ONLY the measurement-cast seam and the `cases`
# executor differ. Under Tracing a derivation is the SAME lazy evaluator over
# base record wires (surface/tokens.jl); the `CasesN` materializer enumerates the
# selector's base-wire configurations and records one nested arm `ChannelDAG` per
# config, so a K-record selector lowers to a K-deep balanced tree of BINARY
# `CasesN` (each with the shipped single-`sel` classical port). This reuses the
# lazy-derivation structure AND records the SSA node (the CasesN), per the task's
# option; the design's flat classical-SSA node vocabulary (BitOp/WordOp, §2.4)
# is a follow-on (filed).
#
# ── NO ORKAN (design §2.1) ──────────────────────────────────────────────────
# `TracingContext` holds a `ContextCore` for the SHARED bookkeeping (the
# single-sourced `consumed` set, `region_stack`, `control_stack`, `wire_counter`,
# the `closed` lifecycle flag, and a wire→liveness map), but its Orkan `state` is
# a NULL `OrkanStateRaw` that is NEVER touched: every state-reading op (`apply!`,
# `allocate!`, `trace_wire!`, the measurement casts) is OVERRIDDEN to RECORD a
# node, and `teardown!` frees nothing (there is no FFI handle to free).
#
# Physics/spec grounding: PRD-v2 §3.6/§3.8 (classical outcomes, portability;
# Tracing yields tokens), §4.4 (channel IR). Token discipline as circuit-
# generation-time parameters: docs/physics/fu_proto_quipper_dyn.md (dynamic
# lifting; tokens are Proto-Quipper PARAMETERS, discardable/duplicable). The
# host-source-tracer alternative Sturm rejects (a whole-language metacircular
# compiler Julia lacks natively): docs/physics/qrisp_jasp_dynamic_tracing.md.

"""
    TracingContext

The COMPILER context (design §2.1, i4ri §13): executes NOTHING, materializes a
program into a `ChannelDAG`. Holds a `ContextCore` for shared wire/region/
consumed bookkeeping (its Orkan `state` is a NULL handle, never touched — no
FFI), plus the recording state: the boundary `inputs`, a STACK of node lists
(`nodes_stack` — the top is the current recording target; `cases` arms push a
sub-list), the classical `couts`, the global `w2port` wire↔`Port` identity
(id == lineage, stable per wire, SHARED across the top DAG and every arm sub-DAG
so a `CasesN` branch references the same `PortID`s the parent does), the
`rec2out` record-wire → classical-`MeasureN`-out-port map (the `CasesN.sel`
resolution), and the `nonportable` pre-flight lint accumulator (Ruling D).

Construct + drive with the `trace(f, nin)` HOF; never touch the raw context.
"""
mutable struct TracingContext <: AbstractContext
    core::ContextCore
    inputs::Vector{Port}
    couts::Vector{Port}
    nodes_stack::Vector{Vector{Node}}
    w2port::Dict{WireID,Port}
    rec2out::Dict{WireID,PortID}
    nonportable::Vector{String}
    idc::Base.RefValue{Int}
end

"""
    TracingContext() -> TracingContext

A fresh compiler context. Its Orkan `state` field is a NULL `OrkanStateRaw`
(`OrkanStateRaw(ORKAN_PURE)` allocates NOTHING and makes no FFI call — design
§2.1: no state); capacity `0` (the slot allocator is never reached, since
`allocate!` is overridden to record an `AllocN`). One top-level recording list.
"""
function TracingContext()
    st = OrkanStateRaw(ORKAN_PURE)                       # NULL handle — no FFI, no alloc
    core = ContextCore(st, ORKAN_PURE, 0)
    return TracingContext(core, Port[], Port[], Vector{Node}[Node[]],
                          Dict{WireID,Port}(), Dict{WireID,PortID}(), String[], Ref(0))
end

# --- Port minting + recording helpers ---------------------------------------

_next_id!(ctx::TracingContext) = (ctx.idc[] += 1; ctx.idc[])

# A fresh width-1 quantum Port (id == lineage: a Tracing wire's SSA name and its
# physical lineage coincide — there is no per-op re-versioning here).
function _qport!(ctx::TracingContext)
    i = _next_id!(ctx)
    return Port(PortID(i), QuantumPort(1), i)
end

_trec(ctx::TracingContext) = ctx.nodes_stack[end]   # current recording target

"The `PortID` of a live wire in the trace (its global SSA/lineage name)."
_pid(ctx::TracingContext, w::WireID) = ctx.w2port[w].id

"""
    _trace_input!(ctx) -> WireID

Declare a boundary quantum INPUT wire (a `qin` port): a fresh live wire + `Port`,
added to `inputs`, but NO `AllocN` (an input is present at the boundary, not
allocated by the body). Used by the `trace` HOF to build the channel's input
handles.
"""
function _trace_input!(ctx::TracingContext)
    core = ctx.core
    core.wire_counter += 1
    w = WireID(core.wire_counter)
    p = _qport!(ctx)
    ctx.w2port[w] = p
    core.wire_to_slot[w] = 0                 # liveness marker (0 is never used as a slot index)
    push!(ctx.inputs, p)
    return w
end

# --- allocate! / apply! / trace_wire! overrides (RECORD, never emit) ---------

"""
    allocate!(ctx::TracingContext) -> WireID

Materialize an ancilla birth as an `AllocN` (the Stinespring dilation): a fresh
live wire + `Port`, region-owned (§3.9, so scope exit traces it), NO Orkan slot.
"""
function allocate!(ctx::TracingContext)
    core = ctx.core
    core.wire_counter += 1
    w = WireID(core.wire_counter)
    p = _qport!(ctx)
    ctx.w2port[w] = p
    core.wire_to_slot[w] = 0
    isempty(core.region_stack) || push!(core.region_stack[end], w)
    push!(_trec(ctx), AllocN(p))
    return w
end

function apply!(ctx::TracingContext, v::ProcessValue, wires::NTuple{N,WireID}) where {N}
    nwires(v) == N || error("apply!: value $(typeof(v)) has $(nwires(v)) wires but $N given")
    _check_wire_aliasing(wires, v)
    for w in wires
        haskey(ctx.core.wire_to_slot, w) || error("apply!: wire $w is not live in this context")
    end
    push!(_trec(ctx), ApplyN(v, ntuple(i -> _pid(ctx, wires[i]), N)))
    return ctx
end

# The 1q `U2` fast path is NOT a fusion buffer here (Tracing records exact nodes;
# the fusion passes run LATER over the frozen DAG) — record an `ApplyN` directly.
function apply!(ctx::TracingContext, u::U2, wires::NTuple{1,WireID})
    haskey(ctx.core.wire_to_slot, wires[1]) || error("apply!: wire $(wires[1]) is not live in this context")
    push!(_trec(ctx), ApplyN(u, (_pid(ctx, wires[1]),)))
    return ctx
end

# The M7 Vector-typed sibling (data-width `Perm` oracle path).
function apply!(ctx::TracingContext, v::ProcessValue, wires::AbstractVector{WireID})
    nwires(v) == length(wires) || error("apply!: value $(typeof(v)) has $(nwires(v)) wires but $(length(wires)) given")
    _check_wire_aliasing(wires, v)
    for w in wires
        haskey(ctx.core.wire_to_slot, w) || error("apply!: wire $w is not live in this context")
    end
    push!(_trec(ctx), ApplyN(v, Tuple(_pid(ctx, w) for w in wires)))
    return ctx
end

"""
    trace_wire!(ctx::TracingContext, w) -> nothing

Materialize a partial trace as a `TraceN` (the coisometry). The generic
`_trace_and_free!` handles the liveness bookkeeping (delete + recycle); this
override only RECORDS the node. `cert = nothing` (a raw region-exit discard; a
combinator-carried certificate rides the tee-frame path, not this one).
"""
function trace_wire!(ctx::TracingContext, w::WireID)
    push!(_trec(ctx), TraceN(_pid(ctx, w), nothing))
    nothing
end

"""
    teardown!(ctx::TracingContext) -> nothing

Free NOTHING (there is no Orkan `state_t` — design §2.1). Only arm the
dangling-handle guard (`closed`). Overrides the FFI-calling generic `teardown!`.
"""
teardown!(ctx::TracingContext) = (ctx.core.closed = true; nothing)

# --- The measurement casts (Ruling D) → MeasureN + wire token ---------------

"""
    _cast_bool(ctx::TracingContext, w) -> ClassicalBit{TracingContext}

The Tracing measurement cast (Ruling D, §3.6): record a `MeasureN` (instrument /
qc cast) with a `Bool`-typed classical out-port, retire the quantum wire (affine
— the handle DIES, single-sourced consumed set), and return a WIRE token naming a
FRESH record wire mapped to that out-port. The `MeasureN` is a UNITARY-PASS
BARRIER; the token is the compiler-visible classical value (T1–T4).
"""
function _cast_bool(ctx::TracingContext, w::WireID)
    inp = _pid(ctx, w)
    outp = _classical_out!(ctx)
    push!(_trec(ctx), MeasureN(inp, outp.id))
    delete!(ctx.core.wire_to_slot, w)                  # the quantum identity dies (affine)
    mark_consumed!(ctx, w)                             # single-sourced consumed set (§4.5)
    rec = _fresh_record!(ctx, outp.id)
    return _cbit_base(ctx, rec)
end

"""
    _cast_int(ctx::TracingContext, Val(W), wires) -> ClassicalWord{W,TracingContext}

Width-`W` Tracing measurement cast: `W` `MeasureN`s (MSB-first), each retiring its
wire, returning a `ClassicalWord{W}` record token over the `W` fresh record wires.
"""
function _cast_int(ctx::TracingContext, ::Val{W}, wires::NTuple{W,WireID}) where {W}
    recs = WireID[]
    for w in wires
        inp = _pid(ctx, w)
        outp = _classical_out!(ctx)
        push!(_trec(ctx), MeasureN(inp, outp.id))
        delete!(ctx.core.wire_to_slot, w)
        mark_consumed!(ctx, w)
        push!(recs, _fresh_record!(ctx, outp.id))
    end
    return _cword_base(Val(W), ctx, recs)
end

# A fresh classical (Bool-typed) out Port for a MeasureN; recorded as a channel cout.
function _classical_out!(ctx::TracingContext)
    i = _next_id!(ctx)
    p = Port(PortID(i), ClassicalPort(Bool), i)
    push!(ctx.couts, p)
    return p
end

# A fresh RECORD wire naming a MeasureN out-port (the token's base wire). NOT
# registered in a quantum region owned-set (it is classical — no quantum TraceN).
function _fresh_record!(ctx::TracingContext, outpid::PortID)
    ctx.core.wire_counter += 1
    rec = WireID(ctx.core.wire_counter)
    ctx.rec2out[rec] = outpid
    return rec
end

# --- cases → CasesN (nested arm regions) ------------------------------------

"""
    _cases_ctx_run(ctx::TracingContext, t, wires, arms; binary, default) -> nothing

Materialize `cases` as a `CasesN` (design §2.4, §13). Enumerate the selector
token's `K` base record wires into a K-deep balanced tree of BINARY `CasesN`
(each with the shipped single-`sel` classical port = the record's `MeasureN`
out-port); at each leaf the fully-determined config picks the firing arm body
(`t.f`/`_match_arm`), recorded as a nested arm `ChannelDAG`. Every arm must
present the identical live-quantum PORT SIGNATURE (the join-typing rule §2.3):
a branch-local register that escapes (leaked scratch) or a consumed pre-existing
port is a loud join error. `cases` returns `nothing` (no quantum φ).
"""
function _cases_ctx_run(ctx::TracingContext, t::ClassicalToken,
                        wires::Vector{WireID}, arms::Vector{Tuple{Any,Any}}; binary::Bool, default)
    node = _trace_casesn(ctx, t, wires, 1, Dict{WireID,Bool}(), arms, binary, default)
    push!(_trec(ctx), node)
    return nothing
end

# Build a binary CasesN branching on wires[i], recursing on wires[i+1:] until the
# config is fully determined at the leaf.
function _trace_casesn(ctx::TracingContext, t, wires, i::Int, config, arms, binary, default)
    w = wires[i]
    haskey(ctx.rec2out, w) || error(
        "cases (Tracing): the selector's base wire $w is not a measurement record — " *
        "a `cases` selector under Tracing must derive from `Bool(q)`/`Int(x)` records.")
    sel = ctx.rec2out[w]
    b0 = _trace_arm_branch(ctx, t, wires, i, false, config, arms, binary, default)
    b1 = _trace_arm_branch(ctx, t, wires, i, true, config, arms, binary, default)
    return CasesN(sel, (b0, b1))
end

function _trace_arm_branch(ctx::TracingContext, t, wires, i::Int, bit::Bool, config, arms, binary, default)
    cfg = copy(config)
    cfg[wires[i]] = bit
    if i == length(wires)
        body = _match_arm(t.f(cfg), arms, binary, default)
        return _record_arm(ctx, body)
    else
        inner = _trace_casesn(ctx, t, wires, i + 1, cfg, arms, binary, default)
        live = _live_qports(ctx)
        return ChannelDAG((inner,), live, live, ())
    end
end

# Record one arm body into a fresh sub-DAG, enforcing the join-typing rule.
function _record_arm(ctx::TracingContext, body)
    baseline_live = _live_qset(ctx)
    baseline_consumed = copy(ctx.core.consumed)
    push!(ctx.nodes_stack, Node[])
    try
        body === nothing || body()
    catch e
        pop!(ctx.nodes_stack)
        rethrow(e)
    end
    armnodes = pop!(ctx.nodes_stack)
    _check_trace_join!(ctx, baseline_live, baseline_consumed)
    live = _live_qports(ctx)
    return ChannelDAG(Tuple(armnodes), live, live, ())
end

# The set / ordered ports of currently-live quantum wires (all wire_to_slot keys
# are quantum under Tracing — records are classical and never enter the slot map).
_live_qset(ctx::TracingContext) = Set{WireID}(keys(ctx.core.wire_to_slot))
function _live_qports(ctx::TracingContext)
    ws = sort!(collect(keys(ctx.core.wire_to_slot)); by = w -> ctx.w2port[w].id.id)
    return Tuple(ctx.w2port[w] for w in ws)
end

"""
    _check_trace_join!(ctx, baseline_live, baseline_consumed)

The trace-time join-typing check (design §2.3): every arm must end with the
identical live-quantum port signature and consumed status. A branch-local
register left live (leaked scratch, L10), a pre-existing port consumed in the arm
(partial-consumption join, L9), or a fresh returned register (no quantum φ, L10)
is a loud join error.
"""
function _check_trace_join!(ctx::TracingContext, baseline_live::Set{WireID}, baseline_consumed::Set{WireID})
    live = _live_qset(ctx)
    if live != baseline_live
        extra = collect(setdiff(live, baseline_live))
        gone = collect(setdiff(baseline_live, live))
        error("cases join error (§2.3 port-signature join, Tracing): a branch changed the " *
              "live quantum port set — new live wire(s) $(extra) / retired wire(s) $(gone). " *
              "Every arm must end with the identical signature: no branch-local register may " *
              "escape (leaked scratch, L10) and no pre-existing port may be consumed in only " *
              "some arms (L9). `cases` returns nothing — a branch-dependent classical value is " *
              "built with `select`, never a quantum φ.")
    end
    ctx.core.consumed == baseline_consumed || error(
        "cases join error (§2.3, Tracing): a branch consumed a quantum port (a nested " *
        "measurement in an arm) — the join requires identical consumed status across all arms.")
    nothing
end

# --- The tracer pre-flight lint (Ruling D §14, PRD §3.8 traceable-subset) ----
#
# Ruling D makes the traceable-subset boundary USE-SITE-DEPENDENT (§13): a program
# is compiler-food iff its outcomes flow only through T1–T4. This cannot be
# lexical, so the mandate (§14) is a tracer PRE-FLIGHT LINT that reports each
# non-portable use site. A token in host `if`/`&&`/`||` throws Julia's OWN native
# `TypeError` (uncatchable, only the descriptive type name surfaces — §9.0), so
# those sites cannot be recorded; the lint's LISTING form covers every site Sturm
# OWNS the method for (`arr[token]`, `iterate`, `convert`, `w[token]`): it records
# the site into `ctx.nonportable` and then throws the descriptive error pointing at
# `cases` (error-at-first-site + a documented listing mechanism, per the ruling).

"""
    _note_nonportable!(ctx, what)

Record a non-portable token use site (the pre-flight lint accumulator). A no-op on
non-Tracing contexts (where the token IS a live scalar/record and the position is
the ordinary error); on a `TracingContext` it appends `what` to `nonportable`
before the descriptive throw, so `trace_nonportable(ctx)` can list it.
"""
_note_nonportable!(::AbstractContext, ::AbstractString) = nothing
_note_nonportable!(ctx::TracingContext, what::AbstractString) = (push!(ctx.nonportable, what); nothing)

"""
    trace_nonportable(ctx::TracingContext) -> Vector{String}

The pre-flight lint's LISTING: every non-portable token use site seen so far
(Ruling D §14). Because each such site also throws at first occurrence, a listing
accumulates one entry per surfaced site; the descriptive error names `cases`.
`public`.
"""
trace_nonportable(ctx::TracingContext) = copy(ctx.nonportable)

# --- The `trace` HOF + freeze ------------------------------------------------

"""
    trace(f, nin::Integer) -> ChannelDAG

Materialize the channel `f` — a function of `nin` single-qubit boundary inputs —
into a `ChannelDAG` (design §2.1, i4ri §13). Binds a fresh `TracingContext`,
declares `nin` boundary input handles (adopted, NOT prepared — they are `qin`
ports, not `AllocN`s), runs `f` ONCE (ordinary Julia; static structure unrolls;
only tokens are non-concrete), traces scope-exit locals, and freezes the recorded
node stream. `qout` = the returned handle(s)' wires; `cout` = the measurement
records. NO Orkan state, NO FFI (the compiler allocates nothing). `public`.
"""
function trace(f, nin::Integer)
    nin >= 0 || throw(ArgumentError("trace: nin must be ≥ 0 (got $nin)"))
    ctx = TracingContext()
    val = with(CURRENT_CONTEXT => ctx) do
        _enter_region!(ctx)
        local v = nothing
        local ok = false
        try
            ins = [_adopt_qbool(ctx, _trace_input!(ctx)) for _ in 1:nin]
            v = f(ins...)
            ok = true
        finally
            _exit_region!(ctx, ok ? v : nothing)
        end
        v
    end
    return _freeze_trace(ctx, val)
end

function _freeze_trace(ctx::TracingContext, result)
    length(ctx.nodes_stack) == 1 || error("trace: unbalanced recording stack (a `cases` arm leaked)")
    nodes = ctx.nodes_stack[1]
    qin = Tuple(ctx.inputs)
    escaped = _escaped_wires(result)
    qout = Tuple(ctx.w2port[w] for w in escaped if haskey(ctx.w2port, w))
    # cout = ONLY the records the return value carries out (T4). A record consumed
    # internally (by a `CasesN`) or dropped is NOT a cout — that is what lets
    # `DeadRecordEliminationPass` recognise a dead record (design §13).
    escaped_recs = Set{PortID}(_escaped_records(ctx, result))
    cout = Tuple(p for p in ctx.couts if p.id in escaped_recs)
    return ChannelDAG(Tuple(nodes), qin, qout, cout)
end

# The classical record out-ports the return value carries out of the trace (T4).
_escaped_records(::TracingContext, ::Any) = PortID[]
_escaped_records(ctx::TracingContext, t::ClassicalToken) =
    PortID[ctx.rec2out[w] for w in t.wires if haskey(ctx.rec2out, w)]
_escaped_records(ctx::TracingContext, t::Tuple) =
    isempty(t) ? PortID[] : reduce(vcat, (_escaped_records(ctx, x) for x in t))

# ============================================================================ #
#  DM REPLAY of a traced ChannelDAG (the materialize half of the round-trip)   #
# ============================================================================ #
#
# The compiler produces the DAG; the DENOTATION (DM, §13) EXECUTES it. Replay a
# `ChannelDAG` (possibly containing `MeasureN`/`CasesN` barriers) against a live
# `DensityMatrixContext`, reusing the slice-4 physics VERBATIM: `MeasureN` →
# `_instrument_record!` (pinch, keep the record c-wire live), `CasesN` → `ctrl`
# off that pinched c-wire (deferred-measurement principle: the off-diagonals are
# already zero, so coherent control IS exact classical control), `AllocN`/`ApplyN`/
# `TraceN` → the M2 primitives. NO new physics primitive. This is the executor the
# `M8.TRACE.STREAM-MATERIALIZED` law and the `DeferMeasurementPass` Choi law use.

"""
    _replay_dm!(ctx::DensityMatrixContext, dag::ChannelDAG, inwires) -> Vector{WireID}

Execute the traced `dag` against the live DM context, binding `dag.qin` ports to
`inwires` (in order). Returns the DM wires for `dag.qout` (the channel outputs).
"""
function _replay_dm!(ctx::DensityMatrixContext, dag::ChannelDAG, inwires::AbstractVector{WireID})
    length(inwires) == length(dag.qin) || error(
        "_replay_dm!: $(length(inwires)) input wires for a $(length(dag.qin))-input DAG")
    p2w = Dict{PortID,WireID}()
    for (i, p) in enumerate(dag.qin)
        p2w[p.id] = inwires[i]
    end
    p2rec = Dict{PortID,WireID}()
    _replay_nodes!(ctx, dag.nodes, p2w, p2rec)
    return WireID[p2w[p.id] for p in dag.qout]
end

function _replay_nodes!(ctx::DensityMatrixContext, nodes, p2w, p2rec)
    for nd in nodes
        if nd isa AllocN
            p2w[nd.out.id] = allocate!(ctx)
        elseif nd isa ApplyN
            apply!(ctx, nd.v, ntuple(i -> p2w[nd.ports[i]], length(nd.ports)))
        elseif nd isa TraceN
            if haskey(p2w, nd.in)
                _trace_and_free!(ctx, p2w[nd.in])
                delete!(p2w, nd.in)
            elseif haskey(p2rec, nd.in)
                # M11: a discarded classical record (`trace_record!`) — the
                # block-accumulation of the code-capacity model: trace the
                # pinched record wire (exact sum over record configurations).
                _trace_and_free!(ctx, p2rec[nd.in])
                delete!(p2rec, nd.in)
            else
                error("_replay_dm!: TraceN references unknown port $(nd.in)")
            end
        elseif nd isa MeasureN
            p2rec[nd.out] = _instrument_record!(ctx, p2w[nd.in])
            delete!(p2w, nd.in)
        elseif nd isa CasesN
            _replay_casesn!(ctx, nd, p2w, p2rec)
        elseif nd isa NoiseN
            # S29 (M11): execute the recorded channel value natively — the full
            # `apply!` entry, so the guardrail/liveness checks run (top-level
            # replay has an empty control stack; a NoiseN inside a `cases` arm
            # never reaches here — `_replay_branch_controlled!` refuses it).
            apply!(ctx, nd.ch, ntuple(i -> p2w[nd.ports[i]], length(nd.ports)))
        else
            error("_replay_dm!: unsupported node $(typeof(nd))")
        end
    end
    nothing
end

# Condition each branch off the record c-wire named by `sel` (the deferred-
# measurement principle, design §2.1): branch b (b=0/1) runs CONTROLLED on the
# record == b (an X-sandwich anti-controls b=0). Reuses `_push_control!` +
# `_act!` (the arm ApplyNs lower as ctrl^k off the pinched wire).
function _replay_casesn!(ctx::DensityMatrixContext, node::CasesN, p2w, p2rec)
    haskey(p2rec, node.sel) || error(
        "_replay_dm!: CasesN.sel $(node.sel) is not a live measurement record")
    recwire = p2rec[node.sel]
    for (bitval, branch) in enumerate(node.branches)
        bit = bitval - 1
        bit == 0 && apply!(ctx, X, (recwire,))          # anti-control the 0-branch
        _push_control!(ctx, recwire)
        try
            _replay_branch_controlled!(ctx, branch, p2w, p2rec)
        finally
            _pop_control!(ctx, recwire)
            bit == 0 && apply!(ctx, X, (recwire,))
        end
    end
    nothing
end

# Replay an arm's nodes under the active control frame: `ApplyN`s go through
# `_act!` (which reads the control stack and wraps ctrl^k); a nested `CasesN`
# recurses (its record conditions on top of the outer control).
function _replay_branch_controlled!(ctx::DensityMatrixContext, branch::ChannelDAG, p2w, p2rec)
    for nd in branch.nodes
        if nd isa ApplyN
            _act!(ctx, nd.v, ntuple(i -> p2w[nd.ports[i]], length(nd.ports)))
        elseif nd isa CasesN
            _replay_casesn!(ctx, nd, p2w, p2rec)
        else
            error("_replay_dm!: a `cases` arm under Tracing replay may hold only unitary " *
                  "corrections (ApplyN) or a nested CasesN, not $(typeof(nd)) (§2.3 join / " *
                  "guardrail 1: measurement/alloc under coherent control is unrepresentable)")
        end
    end
    nothing
end
