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

    # Private constructor for wrapping a pre-initialized OrkanStateRaw (used by Base.copy)
    function OrkanState(raw::OrkanStateRaw)
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
    OrkanState(raw_copy)
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

Allocation-free: cumulative-sum is taken directly against the FFI getter, no
intermediate probability vector is constructed. At n=20 qubits the previous
implementation allocated 16 MB per call (`Vector{Float64}` of length `2^n`).

Errors loudly on a non-normalised state. The previous implementation silently
returned the last index when the cumulative probability fell short of `r`,
which masked upstream state-preparation bugs. A 1e-10 tolerance absorbs FP
round-off on truly normalised states.

# Refs
- Bead `Sturm.jl-5z3r` (P1, 2026-04-27 area2 review).
"""
function sample(s::OrkanState)
    dim = 1 << n_qubits(s)
    r = rand()
    cumulative = 0.0
    if s.raw.type == ORKAN_PURE
        @inbounds for i in 0:dim-1
            amp = orkan_state_get(s.raw, i, 0)
            cumulative += abs2(amp)
            r <= cumulative && return i
        end
    else
        @inbounds for i in 0:dim-1
            cumulative += real(orkan_state_get(s.raw, i, i))
            r <= cumulative && return i
        end
    end
    # Loop completed without an early return: either FP round-off on a
    # normalised state (cumulative ≈ 1 - ε) or a genuinely non-normalised
    # state. Distinguish by tolerance: 1e-10 covers FP slack at n≤30.
    if cumulative > 1.0 - 1e-10
        return dim - 1
    end
    error(
        "Sturm: sample(::OrkanState) called on a non-normalised state " *
        "(cumulative probability = $cumulative after iterating all $dim " *
        "basis states; expected 1.0 ± 1e-10). PURE states must satisfy " *
        "Σ|amp|² = 1; MIXED states must satisfy Σρ_ii = 1. This usually " *
        "indicates a bug in upstream gate application or state preparation."
    )
end
