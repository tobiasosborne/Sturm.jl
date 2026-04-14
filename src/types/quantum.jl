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
