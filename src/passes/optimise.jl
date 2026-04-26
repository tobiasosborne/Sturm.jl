# User-facing optimisation API. Three signatures:
#
#   optimise(ch, ::Symbol)                 — backward-compat dispatch
#   optimise(ch, ::AbstractPass)           — single-pass convenience
#   optimise(ch, ::Vector{<:AbstractPass}) — pipeline
#
# The pipeline form is the canonical entry point. The Symbol form looks
# names up in the pass registry. The single-pass form wraps in a Vector.
#
# Per CLAUDE.md "Channel IR vs Unitary Methods" (HALLUCINATION RISK
# section): each pass's `handles_non_unitary` trait is checked against
# the current DAG content before the pass runs. A `false` pass meeting a
# DAG that contains `ObserveNode`, `CasesNode`, or `DiscardNode` errors
# loudly with concrete remediation — never silently corrupts.

"""
    optimise(ch::Channel, passes::Vector{<:AbstractPass}) -> Channel
    optimise(ch::Channel, pass::AbstractPass)             -> Channel
    optimise(ch::Channel, pass::Symbol)                   -> Channel

Apply one or more optimisation passes to a channel and return the
result. Passes are applied in order.

# Symbol dispatch (backward compat)

Convenience names map into the registry — see `registered_passes()` for
the full list. Built-in:

  * `:cancel` / `:cancel_adjacent` — [`GateCancelPass`](@ref)
  * `:deferred` / `:defer_measurements` — [`DeferMeasurementsPass`](@ref)
  * `:all` — `[DeferMeasurementsPass(), GateCancelPass()]`

# Channel-IR discipline

Each pass declares [`handles_non_unitary`](@ref). A pass with `false`
(the default) will refuse to run on a DAG that contains `ObserveNode`,
`CasesNode`, or `DiscardNode` — channel-unsafe optimisations like ZX
rewriting and phase-polynomial extraction would silently produce wrong
results across measurement barriers. Built-in passes both opt in to
`true`: `GateCancelPass` is barrier-aware, `DeferMeasurementsPass` is
channel-aware.

# Example

```julia
ch = trace(1) do q
    H!(q); H!(q)
    q
end
optimise(ch, :cancel)              # Symbol dispatch
optimise(ch, GateCancelPass())     # single pass
optimise(ch, [DeferMeasurementsPass(), GateCancelPass()])  # pipeline
```
"""
function optimise(ch::Channel{In, Out},
                  passes::Vector{<:AbstractPass}) where {In, Out}
    dag = DAGNode[n for n in ch.dag]
    for p in passes
        if !handles_non_unitary(p)
            i = findfirst(_is_non_unitary, dag)
            if i !== nothing
                offender = dag[i]
                error("""
                Pass $(pass_name(p)) ($(typeof(p))) declares handles_non_unitary = false
                but the DAG contains $(typeof(offender)) at index $i.

                Channel-unsafe passes (gate cancellation without barrier
                awareness, ZX rewriting, phase polynomials, SAT synthesis,
                DD equivalence checking) are undefined on non-unitary nodes
                (ObserveNode, CasesNode, DiscardNode). See CLAUDE.md
                "Channel IR vs Unitary Methods — HALLUCINATION RISK".

                Resolve by one of:
                  * Lower measurements first: prepend DeferMeasurementsPass()
                    to the pipeline.
                  * Mark your pass channel-aware:
                      handles_non_unitary(::Type{$(typeof(p))}) = true
                    only if its algorithm genuinely tolerates barriers.
                  * Apply this pass to a partitioned unitary subblock
                    rather than the full channel.
                """)
            end
        end
        dag = run_pass(p, dag)
    end
    Channel{In, Out}(dag, ch.input_wires, ch.output_wires)
end

optimise(ch::Channel, p::AbstractPass) = optimise(ch, AbstractPass[p])

function optimise(ch::Channel, pass::Symbol)
    pass === :all && return optimise(
        ch,
        AbstractPass[get_pass(:deferred), get_pass(:cancel)],
    )
    optimise(ch, AbstractPass[get_pass(pass)])
end
