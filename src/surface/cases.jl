# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M8 (bead Sturm.jl-szx1), the i4ri
# classical-control gate (`docs/design/m8-i4ri-classical-control-design.md`),
# DM/Eager slice: `cases` / `@cases` (surface construct 6), the T3 `select`
# multiplexer executor, the `shots` trajectory HOF, and explicit record
# `discard!`.
#
# ── THE ONE PORTABLE BRANCH CONSTRUCT (design §3.2) ─────────────────────────
# `cases` is the single fully-portable runtime branch. Its behaviour is set by
# the SELECTOR TYPE, which is the scalar-vs-token axis (§3.8):
#   • EAGER — the selector is a real scalar (`Bool`/`Int`; Eager unravels one
#     trajectory). `cases` runs the SELECTED arm; this IS the trajectory contract
#     (host `if` is the Eager-only shorthand). No sum, one branch.
#   • DM — the selector is a TOKEN (a handle to the pinched classical record).
#     `cases` runs ALL correlated arms, block-accumulated, Born-weighted: the
#     EXACT instrument-sum channel 𝓔(ρ) = Σᵢ 𝓔ᵢ(𝓜ᵢ(ρ)) (F5, law L2). It is
#     realised by CONDITIONING each arm off the record c-wires — `ctrl` off an
#     already-dephased wire is EXACTLY classical control (deferred-measurement
#     principle: the off-diagonals are already zero, design §2.1) — reusing the
#     shipped `_instrument!`/`_act!`(ctrl)/`_trace_and_free!` with NO new physics
#     primitive.
#
# ── THE DM EXECUTOR (design §2.1 realisation, L5 correction) ────────────────
# A token is a lazy derivation over its BASE record wires with a pure evaluator
# `f` (surface/tokens.jl). `cases` enumerates the base-wire CONFIGURATIONS (2^K,
# K = #record wires the selector depends on — proportional to the WRITTEN fan-in,
# NOT the word domain: a per-bit `@cases w[j]` is K=1; law L13), evaluates `f` on
# each config to pick the arm, and applies that arm's body CONTROLLED on the
# config (a `_push_control!` off the base c-wires, with an X-sandwich anti-control
# for the config's 0-bits). Because the record wires are pinched (diagonal) and
# the arm bodies act on DATA wires, the sequential ctrl-conditioned applications
# realise exactly Σ_γ|γ⟩⟨γ|_C ⊗ 𝓔_{arm(γ)}(ρ̃_γ). The record is traced (summed)
# only at region exit / `discard!` — NEVER mid-`cases` (immediate summation
# destroys feed-forward correlation, law L7). L5's population-vs-phase subtlety
# is a PROBE issue (the executor is basis-agnostic): a repeated token driving
# X on one wire and Z on another gives a correlated X⊗Z record, invisible to a
# Z-blind (population-only) probe — the wm28 lesson (test file).
#
# ── THE JOIN-TYPING RULE (design §2.3) ──────────────────────────────────────
# Every arm must present the IDENTICAL live quantum port signature (WireIDs,
# consumed status). `cases` returns `nothing`; there is no quantum φ — a
# branch-dependent CLASSICAL value is built with `select`, never a phi. Under DM
# the arms are unitary corrections (guardrail 1 bans measurement/trace under the
# control stack), so the executor enforces the join by asserting each arm PRESERVES
# the pre-`cases` signature (leaked scratch or a consumed port is a loud join
# error). Cross-arm-consumption joins and branch-local scratch are a Tracing-slice
# seam (documented). A bare quantum register selector is rejected (F30): measure
# first (`@cases Bool(q)`).
#
# Physics/spec grounding: PRD-v2 §3.6 (cases, T1–T4), §3.8 (portability), §3.5
# (guardrail 1 — cases under `when` banned). Denotation:
# docs/physics/badescu_panangaden_quantum_alternation.md (quantum alternation /
# guarded commands; the classical-control record is its guard).

"Guard rail (design §1): a token selector may depend on at most this many record wires (2^K configs)."
const CASES_MAX_FANIN = 16

# ---------------------------------------------------------------------------
# `cases` — the do-block BINARY form (surface construct 6)
# ---------------------------------------------------------------------------

"""
    cases(body::Function, sel) -> nothing

The do-block binary form `cases(sel) do … end`: `true => body`, `false =>
identity`. `sel` is a scalar `Bool` (Eager — run `body` iff `sel`) or a
`ClassicalBit` token (DM — the instrument-sum executor conditions `body` off the
record). Returns `nothing` (§2.3: no quantum φ). A raw quantum register is
rejected (F30 — measure first: `cases(Bool(q)) do … end`).
"""
function cases(body::Function, sel::Bool)
    _cases_guard_scalar()
    sel && body()
    return nothing
end

function cases(body::Function, t::ClassicalBit)
    _cases_dm_run(t, Tuple{Any,Any}[(true, body)]; binary = true, default = nothing)
    return nothing
end

# An integer/word selector has no binary shorthand — its arms are concrete labels.
cases(::Function, sel::Integer) = throw(ArgumentError(
    "cases(::Integer) has no binary shorthand — an integer/word outcome needs concrete " *
    "arms: `@cases sel begin v => … ; _ => … end` (multiway with domain coverage, §3.6)."))
cases(::Function, ::ClassicalWord) = throw(ArgumentError(
    "cases(::ClassicalWord) has no binary shorthand — use `@cases word begin v => … ; _ => … end` " *
    "(multiway with concrete disjoint labels + optional `_` default, §3.6)."))

cases(::Function, ::AbstractQRegister) = _cases_register_error()
@noinline _cases_register_error() = throw(ArgumentError(
    "cases/@cases takes a CLASSICAL outcome, never a raw quantum register (F30, §3.6): " *
    "measure first — `cases(Bool(q)) do … end` / `@cases Bool(q) begin … end`. A register-" *
    "accepting form would hide the quantum→classical (measurement) instrument boundary."))

# ---------------------------------------------------------------------------
# `@cases` — the macro (binary shorthand OR multiway with concrete labels)
# ---------------------------------------------------------------------------

"""
    @cases selector begin body end                # binary: true => body, false => identity
    @cases selector begin v1 => b1; v2 => b2; _ => bd end   # multiway + optional default

Classical branching on `selector` (surface construct 6, §3.6). The selector is
evaluated EXACTLY ONCE. Binary shorthand runs `body` when the selector is true.
Multiway matches concrete disjoint labels; a final `_ => …` is the default, and
without one the arms must cover the selector domain (a loud error otherwise). The
selector must be a classical outcome — `@cases Bool(m) …` — never a bare quantum
register (F30). Under `when` (a live control frame) `@cases` is a loud guardrail-1
error (measurement/branch under coherent control is unrepresentable, §3.5).
"""
macro cases(sel, block)
    (block isa Expr && block.head === :block) ||
        error("@cases: expected `@cases selector begin … end`")
    arms = Tuple{Any,Any}[]           # (label_expr, body_expr)
    default_body = nothing
    body_stmts = Any[]
    is_multi = false
    for stmt in block.args
        stmt isa LineNumberNode && continue
        if stmt isa Expr && stmt.head === :call && length(stmt.args) == 3 && stmt.args[1] === :(=>)
            is_multi = true
            label = stmt.args[2]
            body = stmt.args[3]
            if label === :_
                default_body === nothing || error("@cases: multiple `_` default arms")
                default_body = body
            else
                push!(arms, (label, body))
            end
        else
            push!(body_stmts, stmt)
        end
    end
    if is_multi
        isempty(body_stmts) || error(
            "@cases: mix of `label => body` arms and bare statements — a multiway `@cases` " *
            "is ALL arms; a binary `@cases` is a single bare body (§3.6).")
        armvec = Expr(:vect,
            [:(($(esc(lab)), () -> $(esc(bd)))) for (lab, bd) in arms]...)
        defexpr = default_body === nothing ? :nothing : :(() -> $(esc(default_body)))
        return quote
            _cases_multi($(esc(sel)), Tuple{Any,Any}[$(armvec)...]; default = $defexpr)
        end
    else
        bodyexpr = esc(Expr(:block, body_stmts...))
        return quote
            cases($(esc(sel))) do
                $(bodyexpr)
            end
        end
    end
end

# ---------------------------------------------------------------------------
# Multiway dispatch (Eager scalar vs DM token vs register-rejection)
# ---------------------------------------------------------------------------

"""
    _cases_multi(sel, arms; default) -> nothing

Multiway `cases`. Eager (scalar `Bool`/`Integer`): run the arm whose label `==`
the selector, else the `default`, else a domain-coverage error. DM (token):
delegate to the instrument-sum executor.
"""
function _cases_multi(sel::Union{Bool,Integer}, arms::Vector{Tuple{Any,Any}}; default)
    _cases_guard_scalar()
    for (label, thunk) in arms
        sel == label && (thunk(); return nothing)
    end
    default === nothing || (default(); return nothing)
    throw(ArgumentError(
        "@cases: selector $(sel) matched no arm and there is no `_` default — the arms " *
        "must cover the selector domain (§3.6 domain coverage)."))
end

_cases_multi(t::ClassicalToken, arms::Vector{Tuple{Any,Any}}; default) =
    _cases_dm_run(t, arms; binary = false, default = default)

_cases_multi(::AbstractQRegister, ::Vector{Tuple{Any,Any}}; default) = _cases_register_error()

# ---------------------------------------------------------------------------
# The DM instrument-sum executor
# ---------------------------------------------------------------------------

"`true` iff a Sturm context is bound; if so, assert we are not under a `when` control (guardrail 1)."
function _cases_guard_scalar()
    v = Base.ScopedValues.get(CURRENT_CONTEXT)
    v === nothing && return nothing
    _assert_no_control(something(v), "cases (classical branching)")
    return nothing
end

# The K-bit configuration `a` as an assignment over `wires` (wire i ← bit i-1 of a).
function _config_dict(wires::Vector{WireID}, a::Int)
    d = Dict{WireID,Bool}()
    @inbounds for i in eachindex(wires)
        d[wires[i]] = ((a >> (i - 1)) & 1) == 1
    end
    return d
end

# Which arm body fires for value `val`? Binary: body iff `val` is true, else
# identity (`nothing`). Multiway: the matching label's body, else the default,
# else a loud domain-coverage error.
function _match_arm(val, arms::Vector{Tuple{Any,Any}}, binary::Bool, default)
    if binary
        return (val === true) ? arms[1][2] : nothing
    end
    for (label, thunk) in arms
        val == label && return thunk
    end
    default === nothing && throw(ArgumentError(
        "@cases: selector value $(val) matched no arm and there is no `_` default — the " *
        "arms must cover the selector domain (§3.6 domain coverage)."))
    return default
end

"""
    _cases_dm_run(t, arms; binary, default) -> nothing

Execute `cases` on a record token. Common front matter (context resolution,
guardrail 1, the fan-in cap), then DISPATCH on the owning context type
(`_cases_ctx_run`): a `DensityMatrixContext` runs the exact instrument sum
(this file); a `TracingContext` MATERIALIZES a `CasesN` into the DAG
(`src/context/tracing.jl`). `_assert_no_control` first — `cases` under `when`
is guardrail-1 forbidden (§3.5). The name is kept for source-compat with the
slice-4 call sites; the DM-specific work now lives in `_cases_ctx_run`.
"""
function _cases_dm_run(t::ClassicalToken, arms::Vector{Tuple{Any,Any}}; binary::Bool, default)
    ctx = _here_token(t)
    _assert_no_control(ctx, "cases (classical branching)")
    wires = t.wires
    K = length(wires)
    K <= CASES_MAX_FANIN || error(
        "cases: the selector depends on $K record wires (2^$K configurations) — this " *
        "exceeds the fan-in cap ($CASES_MAX_FANIN). Wide feed-forward is a finite classical " *
        "SSA over the WRITTEN structure (a per-bit `@cases w[j]` loop, K=1), never an " *
        "implicit branch over a whole word domain (§3.6 / law L13).")
    _cases_ctx_run(ctx, t, wires, arms; binary = binary, default = default)
    return nothing
end

"""
    _cases_ctx_run(ctx::DensityMatrixContext, t, wires, arms; binary, default) -> nothing

The EXACT instrument-sum executor (design §2.1). Enumerate the selector's 2^K
base-wire configs; for each, evaluate `t.f` to pick the arm and apply its body
CONTROLLED on that config (`_apply_arm_config!`). The join signature is asserted
preserved after each arm (design §2.3). The `TracingContext` sibling materializes
a `CasesN` instead (`src/context/tracing.jl`).
"""
function _cases_ctx_run(ctx::DensityMatrixContext, t::ClassicalToken,
                        wires::Vector{WireID}, arms::Vector{Tuple{Any,Any}}; binary::Bool, default)
    core = _core(ctx)
    K = length(wires)
    baseline_live = Set(keys(core.wire_to_slot))
    baseline_consumed = copy(core.consumed)
    @inbounds for a in 0:((1 << K) - 1)
        d = _config_dict(wires, a)
        body = _match_arm(t.f(d), arms, binary, default)
        body === nothing && continue
        _apply_arm_config!(ctx, wires, d, body)
        _check_join_signature!(ctx, baseline_live, baseline_consumed)
    end
    return nothing
end

"""
    _apply_arm_config!(ctx, wires, config, body)

Apply `body` (a zero-arg thunk of surface ops) CONTROLLED on the base-wire
configuration `config` (design §2.1): an X-sandwich anti-controls the 0-bits, and
the base wires are pushed as `when`-style controls so each action-family op in the
body lowers as `ctrl^K` off the record c-wires. The sandwich and controls are
restored on ANY throw (matched `finally`). No `WhenFrame` is pushed — this is
classical control off an EXISTING dephased wire, not a new `when` region, so the
tee-tracing seal machinery stays inert (`_act!` skips it on an empty frame stack).
"""
function _apply_arm_config!(ctx::AbstractContext, wires::Vector{WireID}, config::Dict{WireID,Bool}, body)
    zeros = WireID[w for w in wires if !config[w]]
    for w in zeros
        apply!(ctx, X, (w,))            # anti-control: flip 0-bit up so |1⟩-ctrl fires on the config
    end
    for w in wires
        _push_control!(ctx, w)
    end
    try
        body()
    finally
        for w in Iterators.reverse(wires)
            _pop_control!(ctx, w)
        end
        for w in zeros
            apply!(ctx, X, (w,))        # close the sandwich (deferred-flushed before the record is read/traced)
        end
    end
    return nothing
end

"""
    _check_join_signature!(ctx, baseline_live, baseline_consumed)

The DM join-typing check (design §2.3): every arm must end with the identical
quantum port signature. Under DM the arms are unitary corrections, so the check
is that the arm PRESERVED the pre-`cases` live-wire and consumed sets — a leaked
branch-local register (L10) or a consumed port (L9) is a loud join error.
"""
function _check_join_signature!(ctx::AbstractContext, baseline_live::Set{WireID}, baseline_consumed::Set{WireID})
    core = _core(ctx)
    live = Set(keys(core.wire_to_slot))
    if live != baseline_live
        extra = collect(setdiff(live, baseline_live))
        gone = collect(setdiff(baseline_live, live))
        error("cases join error (§2.3 port-signature join): a branch changed the live " *
              "quantum port set — new live wire(s) $(extra) / retired wire(s) $(gone). Every " *
              "arm must end with the identical signature: no branch-local register may escape " *
              "(leaked scratch) and no pre-existing port may be consumed in only some arms. " *
              "Under DM the arms are unitary corrections; branch-local scratch/measurement is a " *
              "Tracing-slice seam.")
    end
    core.consumed == baseline_consumed || error(
        "cases join error (§2.3): a branch consumed a quantum port — the join requires " *
        "identical consumed status across all arms.")
    return nothing
end

# ---------------------------------------------------------------------------
# `discard!` — explicit last-use trace of a record (design §2.2)
# ---------------------------------------------------------------------------

"""
    discard!(t::ClassicalToken) -> nothing

Explicitly end a record's life (its LAST USE, design §2.2): trace (sum) the base
record wires of `t` NOW, rather than at region exit. Under DM this is the exact
partial trace (`_trace_and_free!`). Because derived tokens SHARE base wires,
`discard!` traces those wires — call it only when no other live token needs the
same record. The common use is discarding a base measurement token once its
feed-forward is complete (freeing its Orkan slot).
"""
function discard!(t::ClassicalToken)
    ctx = _here_token(t)
    core = _core(ctx)
    for w in t.wires
        haskey(core.wire_to_slot, w) && _trace_and_free!(ctx, w)
    end
    return nothing
end

# ---------------------------------------------------------------------------
# `shots` — the explicit trajectory / shot HOF over Eager (design §3.3)
# ---------------------------------------------------------------------------

"""
    shots(f, capacity; N=1000, rng=nothing) -> Vector

Sample `N` trajectories of `f` under a fresh `capacity`-qubit EAGER context
(design §3.3): Eager IS the trajectory (statevector-unravelling) contract — inside
`f`, ordinary `if`/`Bool(q)`/`Int(x)` work and each run returns SCALAR outcomes.
`shots` collects `f(ctx)`'s return value per run into a length-`N` vector. This is
the ONLY sanctioned scalar-outcome mode for a would-be-DM program: DM/Tracing stay
channel/circuit-valued (tokens + `cases`). A shared `rng` (e.g. a `MersenneTwister`)
threads across shots so the trajectories are distinct and reproducible.

Noisy (Kraus) density trajectories are a named future (`TrajectoryContext{DM}`,
design §3.3) — NOT M8; M8 ships only `shots` over the pure-state Eager unravelling.
"""
function shots(f, capacity::Integer; N::Integer = 1000, rng = nothing)
    N >= 1 || throw(ArgumentError("shots: N must be ≥ 1 (got $N)"))
    return [eager(capacity; rng = rng) do ctx
        f(ctx)
    end for _ in 1:N]
end
