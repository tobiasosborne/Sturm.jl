"""
    trace(f::Function, n_in::Int) -> Channel

Trace a quantum function to produce a Channel.

Creates a TracingContext with `n_in` symbolic input wires, runs `f`
with those wires wrapped as QBools, and captures the resulting DAG.

`f` should accept `n_in` QBool arguments and may return QBools
(the output wires of the channel).

Example:
    ch = trace(1) do q
        H!(q)
        q
    end
"""
function trace(f::Function, n_in::Int)
    ctx = TracingContext()

    # Allocate input wires
    in_wires = ntuple(_ -> allocate!(ctx), n_in)

    # Create QBool wrappers for inputs
    in_qbools = ntuple(i -> QBool(in_wires[i], ctx, false), n_in)

    # Run the function in this tracing context
    result = task_local_storage(:sturm_context, ctx) do
        if n_in == 1
            f(in_qbools[1])
        else
            f(in_qbools...)
        end
    end

    # Collect output wires
    out_wires = if result isa QBool
        (result.wire,)
    elseif result isa Tuple
        ntuple(length(result)) do i
            r = result[i]
            r isa QBool || error("trace: return value $i is not a QBool")
            r.wire
        end
    elseif result === nothing
        ()
    else
        error("trace: unexpected return type $(typeof(result))")
    end

    N_out = length(out_wires)
    return Channel{n_in, N_out}(ctx.dag, in_wires, out_wires)
end
