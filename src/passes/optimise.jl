# User-facing optimisation API for channels.
# Wraps individual DAG passes into a Channel → Channel interface.

"""
    optimise(ch::Channel, pass::Symbol) -> Channel

Apply an optimisation pass to a channel's DAG and return the optimised channel.

Available passes:
- `:cancel` — gate cancellation with commutation awareness (merges rotations, cancels CX pairs)
- `:deferred` — deferred measurement (replaces mid-circuit measurement + classical branch with quantum control)
- `:all` — apply all passes in sequence: cancel, then deferred measurement

# Example
```julia
ch = trace(1) do q
    H!(q); H!(q)  # should cancel
    q
end
ch_opt = optimise(ch, :cancel)
```
"""
function optimise(ch::Channel{In, Out}, pass::Symbol) where {In, Out}
    new_dag = _apply_pass(ch.dag, pass)
    Channel{In, Out}(new_dag, ch.input_wires, ch.output_wires)
end

function _apply_pass(dag::Vector{DAGNode}, pass::Symbol)
    if pass === :cancel || pass === :cancel_adjacent
        gate_cancel(dag)
    elseif pass === :deferred || pass === :defer_measurements
        defer_measurements(dag)
    elseif pass === :all
        gate_cancel(defer_measurements(dag))
    else
        error("Unknown optimisation pass: :$pass. Available: :cancel, :deferred, :all")
    end
end
