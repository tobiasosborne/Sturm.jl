"""
    Quantum

Abstract supertype of every Sturm-owned quantum register type (QBool, QInt{W},
future QDit{D}, QField{…}, anyonic registers). Used to:

  * scope the P9 auto-dispatch catch-all (`(f::Function)(q::Quantum)`) so it
    only fires on Sturm-owned types — avoids method piracy on `Base.Function`;
  * anchor the `classical_type` / `classical_compile_kwargs` trait functions
    that map a quantum register to the classical Julia type Bennett should
    compile against.

See PRD §1 P9 and CLAUDE.md rule 14.
"""
abstract type Quantum end

"""
    classical_type(::Type{<:Quantum}) -> Type

The classical Julia type a quantum register type maps to when a plain Julia
function is lifted to an oracle via Bennett.jl. QBool → Int8 (interpreted at
bit_width=1); QInt{W} → Int8 (at bit_width=W).

Every `T <: Quantum` must define this. Subtypes that have no classical shadow
(e.g. a future quantum-only type) should not be used with P9 auto-dispatch.
"""
function classical_type end

"""
    classical_compile_kwargs(::Type{<:Quantum}) -> NamedTuple

Keyword arguments for `reversible_compile(f, classical_type(T); kw...)` that
are determined by the quantum type alone (e.g. bit_width). Strategy knobs
(add=:qcla, mul=:qcla_tree) are NOT set here — they travel via the explicit
`oracle(f, q; kw...)` path.
"""
classical_compile_kwargs(::Type{<:Quantum}) = NamedTuple()

# ── P2: implicit quantum→classical cast warning ──────────────────────────────
#
# P2 axiom: crossing the quantum/classical boundary is a cast with implied
# information loss — same discipline as float→int truncation. Two dispatch
# paths exist today:
#
#   Bool(q)          → constructor, the BLESSED explicit cast (silent).
#   x::Bool = q      → `convert(Bool, q)`, an IMPLICIT cast (warns).
#
# The split is: `Bool(q::QBool)` / `Int(q::QInt)` contain the measurement and
# return the result directly; `Base.convert(::Type{Bool}, q::QBool)` and its
# QInt counterpart emit the P2 warning then delegate to the constructor.
# Explicit calls never route through `convert`, so they stay silent.
#
# `if q` currently errors with a Julia TypeError ("non-boolean used in
# boolean context") — Julia does not auto-convert at if-sites, so the PRD
# §P4 promise of "implicit warning on if q" cannot be kept without macro
# rewriting. Out of scope for this bead (Sturm.jl-f23).
#
# `classicalise(ch)` has no implicit entry point (only invoked by name), so
# no warning machinery is needed on the channel-level cast. See WORKLOG
# Session 24C.

const _STURM_SRC_ROOT = normpath(joinpath(@__DIR__, ".."))

"""
Find the first stack frame outside the Sturm source tree — that is the
user's call site. Falls back to the innermost frame if none match.
"""
function _first_user_frame(frames::Vector{<:Base.StackTraces.StackFrame})
    for f in frames
        path = string(f.file)
        if isempty(path)
            continue
        end
        if !startswith(normpath(path), _STURM_SRC_ROOT)
            return f
        end
    end
    return isempty(frames) ? Base.StackTraces.UNKNOWN : frames[1]
end

"""
    _warn_implicit_cast(::Type{From}, ::Type{To})

Emit a one-per-source-location warning when a quantum register is silently
converted to a classical type via an implicit path (`x::Bool = q`,
`y::Int = qi`). Suppressed inside [`with_silent_casts`](@ref).

Dedup id is `(file, line)` of the first user stack frame, so distinct
source sites each warn once and loop iterations at the same site share the
id. Explicit `Bool(q)` / `Int(q)` constructors do not route through
`convert` and never warn.

See PRD §P2, bead Sturm.jl-f23.
"""
function _warn_implicit_cast(::Type{From}, ::Type{To}) where {From, To}
    get(task_local_storage(), :sturm_implicit_cast_silent, false) && return nothing
    site = _first_user_frame(stacktrace(backtrace()))
    explicit = To === Bool ? "Bool(q)" : To === Int ? "Int(q)" : "$(nameof(To))(q)"
    @warn "Implicit quantum→classical cast $From → $To. This measures the " *
          "register silently (P2 information loss). Wrap the RHS in an " *
          "explicit cast: `$explicit`." maxlog=1 _id=(:sturm_implicit_cast, site.file, site.line) _file=string(site.file) _line=Int(site.line)
    return nothing
end

"""
    with_silent_casts(f)

Run `f()` with P2 implicit-cast warnings suppressed within the current task.
Use sparingly — intended for tight loops where the measurement is obviously
intentional and re-wrapping every assignment in an explicit cast would be
pure noise. Prefer explicit casts (`Bool(q)`, `Int(qi)`) in normal code.

Nests correctly: the previous silent state is restored on exit. Also
suppresses [`_warn_direct_measure`](@ref) (the `measure!` antipattern
warning) — both warnings share this escape hatch.

```julia
result = with_silent_casts() do
    map(1:1000) do _
        @context EagerContext() begin
            q = QBool(0.5)
            x::Bool = q          # no warning inside this block
            x
        end
    end
end
```
"""
function with_silent_casts(f)
    old = get(task_local_storage(), :sturm_implicit_cast_silent, false)
    task_local_storage(:sturm_implicit_cast_silent, true)
    try
        return f()
    finally
        task_local_storage(:sturm_implicit_cast_silent, old)
    end
end

# ── P2: direct `measure!` antipattern warning ────────────────────────────────
#
# `measure!(ctx, wire)` is the FFI-level measurement primitive — internal back-
# end of the blessed `Bool(q)` / `Int(qi)` casts. Calling it directly from user
# or library code violates P2 (the quantum→classical boundary should be a
# CAST, not a function call) and bypasses the implicit-cast warning system.
#
# Per user policy 2026-04-20: prototyping antipatterns are OK with warnings —
# same discipline as float→int truncation. This helper fires once per source
# location whenever measure! is called outside the blessed cast path.
#
# Suppression mechanisms (any one disables the warning):
#   * `:sturm_measure_blessed` task-local flag — set by `_blessed_measure!`,
#     used by `Bool(::QBool)` / `Int(::QInt)` so casts stay silent.
#   * `with_silent_casts(do ... end)` — user opt-out shared with implicit-cast
#     warnings.
#
# Bead: Sturm.jl-amh.

"""
    _warn_direct_measure()

Emit a one-per-source-location warning when `measure!(ctx, wire)` is called
directly. Suppressed when `:sturm_measure_blessed` is true (i.e. inside
`Bool(q)` / `Int(qi)` casts via [`_blessed_measure!`](@ref)) or inside
[`with_silent_casts`](@ref).

Dedup id is `(file, line)` of the first user stack frame.

See README §P2, bead Sturm.jl-amh.
"""
function _warn_direct_measure()
    get(task_local_storage(), :sturm_measure_blessed, false) && return nothing
    get(task_local_storage(), :sturm_implicit_cast_silent, false) && return nothing
    site = _first_user_frame(stacktrace(backtrace()))
    @warn "Direct call to `measure!(ctx, wire)` — this is a P2 antipattern. " *
          "The quantum→classical boundary should be a CAST: use `Bool(q)` " *
          "or `Int(qi)` for measurement, or `discard!(q)` for partial trace. " *
          "Wrap a non-owning view as `Bool(QBool(wire, ctx, false))` if you " *
          "only have a raw WireID. Suppress per-task with `with_silent_casts`." maxlog=1 _id=(:sturm_direct_measure, site.file, site.line) _file=string(site.file) _line=Int(site.line)
    return nothing
end

"""
    _blessed_measure!(ctx::AbstractContext, wire::WireID) -> Bool

Internal: invoke `measure!(ctx, wire)` with the `:sturm_measure_blessed`
task-local flag set, suppressing the [`_warn_direct_measure`](@ref) warning
for this call only. Used by `Bool(::QBool)` and `Int(::QInt)` so the blessed
cast path does not warn while the raw `measure!` path does.

Nests correctly via try/finally; restores the previous flag on exit.
"""
@inline function _blessed_measure!(ctx, wire)
    old = get(task_local_storage(), :sturm_measure_blessed, false)
    task_local_storage(:sturm_measure_blessed, true)
    try
        return measure!(ctx, wire)
    finally
        task_local_storage(:sturm_measure_blessed, old)
    end
end
