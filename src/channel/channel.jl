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
#
# Single-pass: validate-and-narrow in one walk (pre-fix this did a
# `findfirst` then a separate comprehension, doubling the iteration over
# large DAGs — sweep bead ks0t).
function Channel{In, Out}(dag::Vector{DAGNode}, iw::NTuple{In,WireID}, ow::NTuple{Out,WireID}) where {In, Out}
    out = Vector{HotNode}(undef, length(dag))
    @inbounds for (i, n) in enumerate(dag)
        if !(n isa HotNode)
            error("Channel.dag stores HotNode only; got $(typeof(n)) at index $i. " *
                  "Lower classical-control IR first via `optimise(ch, :deferred)` " *
                  "(Nielsen-Chuang deferred measurement), or use the raw-DAG export " *
                  "`to_openqasm(dag, in_wires, out_wires)` for OpenQASM 3 dynamic-circuit " *
                  "output.")
        end
        out[i] = n
    end
    Channel{In, Out}(out, iw, ow)
end
