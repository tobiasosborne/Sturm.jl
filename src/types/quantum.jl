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

Nests correctly: the previous silent state is restored on exit.

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
