# AbstractPass — extension point for user-defined DAG transformation passes.
#
# Realises Pillar 3 (extensibility): a new pass — ZX simplification, phase
# polynomial re-synthesis, MCGS-guided rewrite, anything from a fresh paper —
# ships as a `<: AbstractPass` declaration and a `run_pass` method, without
# editing core. The Symbol API (`optimise(ch, :cancel)`) stays as a
# convenience layer on top of the registry.
#
# Hard constraints encoded here:
#   * `handles_non_unitary` is a per-Type trait, not an instance field.
#     The safety property belongs to the algorithm, not to a configured
#     instance — two `MyPass()` values must agree.
#   * The runtime gate runs once per pass, not once per node — the inner
#     loops of registered passes are unaffected (Session 3's 31 B/node
#     HotNode storage and 336 ms gate_cancel-on-2000-qubit-QFT baseline
#     are not regressed).
#   * Channel-IR-vs-unitary discipline (CLAUDE.md "Channel IR vs Unitary
#     Methods — HALLUCINATION RISK"): `handles_non_unitary = false` (the
#     default) prevents naive unitary methods from silently corrupting
#     channels containing measurement.

"""
    abstract type AbstractPass end

Base type for DAG transformation passes. A concrete pass `P` must define:

  * `run_pass(::P, dag::Vector{DAGNode}) -> Vector{DAGNode}` — the
    transformation itself.
  * `pass_name(::Type{P}) -> Symbol` — the canonical short name used by
    the Symbol-dispatch `optimise(ch, :name)` API and in error messages.

A pass MAY override:

  * `handles_non_unitary(::Type{P}) -> Bool` — defaults to `false`. Set
    `true` if the pass either (a) operates correctly across `ObserveNode`,
    `CasesNode`, and `DiscardNode` (channel-aware) OR (b) treats them as
    hard barriers and only optimises within unitary subblocks
    (barrier-aware). Setting `false` (the default) opts the pass into a
    runtime gate that refuses to apply it to a DAG containing any
    non-unitary node.

# Why the trait dispatches on Type, not instance

The channel-safety property is a property of the algorithm, not the
configuration. `MyPass(strict=true)` and `MyPass(strict=false)` cannot
sensibly disagree on whether the algorithm itself is barrier-aware.
"""
abstract type AbstractPass end

"""
    run_pass(pass::AbstractPass, dag::Vector{DAGNode}) -> Vector{DAGNode}

Apply `pass` to `dag` and return the transformed DAG. The boundary type
is `Vector{DAGNode}` so passes may emit non-`HotNode` nodes (e.g. a future
pass that introduces fresh `CasesNode` for speculative branching). The
final `Channel` constructor narrows back to `Vector{HotNode}` and rejects
residuals loudly.
"""
function run_pass end

"""
    pass_name(::Type{P}) -> Symbol where P <: AbstractPass

Canonical short name for the pass. Used by the registry, by the Symbol
back-compat dispatch, and in error messages.
"""
function pass_name end

pass_name(p::AbstractPass) = pass_name(typeof(p))

"""
    handles_non_unitary(::Type{P}) -> Bool where P <: AbstractPass
    handles_non_unitary(p::AbstractPass) -> Bool

Trait declaring whether `P` can safely process a DAG containing
`ObserveNode`, `CasesNode`, or `DiscardNode`. Default: `false`. See
[`AbstractPass`](@ref) for the precise semantics.
"""
handles_non_unitary(::Type{<:AbstractPass}) = false
handles_non_unitary(p::AbstractPass) = handles_non_unitary(typeof(p))

# ── Registry ────────────────────────────────────────────────────────────────
#
# The registry stores INSTANCES (not types) so the `Sturm.jl-7kg`
# simulation-equivalence harness can iterate without having to construct
# fresh instances itself. The Symbol back-compat path also wants
# instances so kwargs (e.g. `DeferMeasurementsPass(strict=true)`) can be
# defaulted at registration time.

const _PASS_REGISTRY = Dict{Symbol, AbstractPass}()

"""
    register_pass!(name::Symbol, pass::AbstractPass) -> AbstractPass

Add `pass` to the registry under `name`. Overwrites silently if `name`
already exists — a pass author updating their `MyPass` definition during
interactive development can re-register without restarting Julia.
"""
function register_pass!(name::Symbol, pass::AbstractPass)
    _PASS_REGISTRY[name] = pass
    pass
end

"""
    registered_passes() -> Vector{AbstractPass}

All currently registered passes, as instances, in deterministic order
(sorted by registration name). Used by the simulation-equivalence
harness (`Sturm.jl-7kg`) to enumerate; also any reproducibility-sensitive
caller that hashes pass output. Pre-fix this returned `values(Dict)`
iteration order, which Julia's hash randomisation makes
platform/run-dependent (bead Sturm.jl-4dd6).
"""
registered_passes() = [_PASS_REGISTRY[k] for k in sort!(collect(keys(_PASS_REGISTRY)))]

"""
    get_pass(name::Symbol) -> AbstractPass

Look up the registered pass instance for `name`. Errors with the full
list of registered names if `name` is unknown.
"""
function get_pass(name::Symbol)
    haskey(_PASS_REGISTRY, name) || error(
        "Unknown optimisation pass: :$name. Registered passes: " *
        join(sort!([":$k" for k in keys(_PASS_REGISTRY)]), ", ")
    )
    _PASS_REGISTRY[name]
end

# ── Non-unitary detection ───────────────────────────────────────────────────

@inline _is_non_unitary(n::DAGNode) =
    n isa ObserveNode || n isa CasesNode || n isa DiscardNode
