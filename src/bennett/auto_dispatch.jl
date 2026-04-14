# P9 auto-dispatch — BLOCKED by Julia language constraint.
#
# The P9 axiom (CLAUDE.md rule 14, PRD §1) specifies:
#   "(f::Function)(q::Quantum) MUST dispatch automatically to oracle(f, q)
#    via a compile-time generated fallback on <:Quantum argument types."
#
# Julia rejects this with `cannot add methods to builtin function Function`:
# the abstract `Function` type is treated as a builtin and cannot have methods
# attached from user code (confirmed on Julia 1.12.5). This blocks the literal
# P9 syntax `f(q)` for arbitrary classical `f`.
#
# What this file DOES provide:
#   * `Quantum` abstract type (in src/types/quantum.jl) with QBool, QInt{W}
#     as subtypes — piracy-scoping primitive for any future design;
#   * `classical_type(::Type{<:Quantum})` + `classical_compile_kwargs` traits
#     that map a quantum type to its Bennett classical type + kwargs;
#   * `clear_auto_cache!()` / `_P9_CACHE` — shared cache infrastructure ready
#     for whichever design lands once P9's surface syntax is re-defined.
#
# Candidate re-definitions of P9 (pending decision):
#   1. `@quantum_lift` macro: `@quantum_lift f(x::Int8) = …` expands to add a
#      specific `f(q::QInt{W})` method that routes through the cache.
#   2. Pipe operator: `q |> f` overloads `|>` to route via oracle.
#   3. Keep `quantum(f)(q)` / `oracle(f, q)` as the primary UX; P9 becomes
#      aspirational documentation.
#
# See bead Sturm.jl-k3m for discussion and decision.

const _P9_CACHE = Dict{Tuple{UInt, DataType}, ReversibleCircuit}()
const _P9_LOCK  = ReentrantLock()

"""
    clear_auto_cache!()

Empty the P9 auto-dispatch circuit cache (shared infrastructure — currently
populated only by experimental entry points; see bead k3m for the blocking
Julia constraint on the `f(q)` catch-all).
"""
function clear_auto_cache!()
    lock(_P9_LOCK) do
        empty!(_P9_CACHE)
    end
    return nothing
end
