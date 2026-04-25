"""
    Channel{In,Out}

A traced quantum channel: a DAG of operations with typed input and output wires.
Produced by `trace()`. Can be composed (≫, ⊗) and exported to OpenQASM.

- `In`: number of input wires
- `Out`: number of output wires
"""
struct Channel{In, Out}
    dag::Vector{HotNode}
    input_wires::NTuple{In, WireID}
    output_wires::NTuple{Out, WireID}
end

n_inputs(::Channel{In, Out}) where {In, Out} = In
n_outputs(::Channel{In, Out}) where {In, Out} = Out

# Backward compat: accept Vector{DAGNode}. Errors loudly on any non-HotNode
# (typically a CasesNode) — Channel.dag stores HotNode only, so silently
# stripping would lose user-meaningful structure (Rule 1: fail fast, fail
# loud). See Sturm.jl-eiq.
function Channel{In, Out}(dag::Vector{DAGNode}, iw::NTuple{In,WireID}, ow::NTuple{Out,WireID}) where {In, Out}
    bad = findfirst(n -> !(n isa HotNode), dag)
    if bad !== nothing
        node = dag[bad]
        error("Channel.dag stores HotNode only; got $(typeof(node)) at index $bad. " *
              "Lower classical-control IR first via `optimise(ch, :deferred)` " *
              "(Nielsen-Chuang deferred measurement), or use the raw-DAG export " *
              "`to_openqasm(dag, in_wires, out_wires)` for OpenQASM 3 dynamic-circuit " *
              "output.")
    end
    Channel{In, Out}(HotNode[n for n in dag], iw, ow)
end
