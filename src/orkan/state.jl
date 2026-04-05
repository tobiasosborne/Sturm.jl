# Managed Orkan state handle with finalizer and Julia-friendly interface.

"""
    OrkanState

Managed wrapper around Orkan's `state_t`. Automatically frees the C-side data buffer
when garbage collected. Use `OrkanState(type, qubits)` to create.
"""
mutable struct OrkanState
    raw::OrkanStateRaw

    function OrkanState(type::Cint, qubits::Integer)
        raw = OrkanStateRaw(type)
        orkan_state_init!(raw, qubits)
        obj = new(raw)
        finalizer(obj) do s
            orkan_state_free!(s.raw)
        end
        obj
    end
end

n_qubits(s::OrkanState) = Int(s.raw.qubits)
state_type(s::OrkanState) = s.raw.type
state_length(s::OrkanState) = Int(orkan_state_len(s.raw))

"""Get amplitude/element at (row, col). For PURE states, col defaults to 0."""
function Base.getindex(s::OrkanState, row::Integer, col::Integer=0)
    orkan_state_get(s.raw, row, col)
end

"""Set amplitude/element at (row, col). For PURE states, col defaults to 0."""
function Base.setindex!(s::OrkanState, val, row::Integer, col::Integer=0)
    orkan_state_set!(s.raw, row, col, ComplexF64(val))
end

"""Deep copy of the Orkan state."""
function Base.copy(s::OrkanState)
    raw_copy = @ccall LIBORKAN.state_cp(Ref(s.raw)::Ptr{OrkanStateRaw})::OrkanStateRaw
    raw_copy.data == C_NULL && error("Orkan: state_cp failed (out of memory)")
    obj = new(raw_copy)
    finalizer(obj) do s2
        orkan_state_free!(s2.raw)
    end
    obj
end

"""
    probabilities(s::OrkanState) -> Vector{Float64}

Extract measurement probabilities for each computational basis state.
- PURE: |amplitude|^2 for each basis state
- MIXED: real part of diagonal elements
"""
function probabilities(s::OrkanState)
    dim = 1 << n_qubits(s)
    probs = Vector{Float64}(undef, dim)
    if s.raw.type == ORKAN_PURE
        for i in 0:dim-1
            amp = orkan_state_get(s.raw, i, 0)
            probs[i+1] = abs2(amp)
        end
    else
        for i in 0:dim-1
            probs[i+1] = real(orkan_state_get(s.raw, i, i))
        end
    end
    probs
end

"""
    sample(s::OrkanState) -> Int

Sample one computational basis state index (0-based) from the probability distribution.
"""
function sample(s::OrkanState)
    probs = probabilities(s)
    r = rand()
    cumulative = 0.0
    for i in eachindex(probs)
        cumulative += probs[i]
        if r <= cumulative
            return i - 1  # 0-based index
        end
    end
    return length(probs) - 1  # numerical safety
end
