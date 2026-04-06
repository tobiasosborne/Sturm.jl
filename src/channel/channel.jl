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

# Backward compat: accept Vector{DAGNode} (from tests with CasesNode)
function Channel{In, Out}(dag::Vector{DAGNode}, iw::NTuple{In,WireID}, ow::NTuple{Out,WireID}) where {In, Out}
    Channel{In, Out}(HotNode[n for n in dag if n isa HotNode], iw, ow)
end
