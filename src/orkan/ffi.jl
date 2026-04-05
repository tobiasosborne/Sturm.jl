# Raw ccall wrappers for liborkan.
# Every function here is a thin wrapper — validation happens in the Julia layer above.

using Libdl

# ── OpenMP thread cap ────────────────────────────────────────────────────────
# Orkan links libgomp. Without OMP_NUM_THREADS it spawns one thread per HW thread,
# which combined with Julia's threads causes oversubscription and memory pressure.
# Cap to quarter of HW threads (leaving room for Julia), minimum 1.
# Must run in __init__ (not top-level) so it executes at load time, not precompile time.
function _set_omp_threads!()
    if !haskey(ENV, "OMP_NUM_THREADS")
        _omp_threads = max(1, Sys.CPU_THREADS ÷ 4)
        ENV["OMP_NUM_THREADS"] = string(_omp_threads)
    end
end

# ── Library path ──────────────────────────────────────────────────────────────

const _LIBORKAN_PATH = let
    # Search order: env var, sibling repo build, installed system lib
    candidates = [
        get(ENV, "LIBORKAN_PATH", ""),
        joinpath(@__DIR__, "..", "..", "..", "orkan", "cmake-build-release", "src", "liborkan.so"),
        "liborkan",
    ]
    found = ""
    for c in candidates
        isempty(c) && continue
        if isfile(c)
            found = c
            break
        end
        # Try dlopen for system-installed libs
        try
            dlopen(c)
            found = c
            break
        catch
        end
    end
    isempty(found) && error("""
        Cannot find liborkan.so. Set LIBORKAN_PATH or build Orkan:
          cd ../orkan && cmake --preset release && cmake --build cmake-build-release
        """)
    found
end

const LIBORKAN = _LIBORKAN_PATH

# ── State type enum ───────────────────────────────────────────────────────────

const ORKAN_PURE         = Cint(0)
const ORKAN_MIXED_PACKED = Cint(1)
const ORKAN_MIXED_TILED  = Cint(2)

# ── Raw structs (must match C ABI exactly) ────────────────────────────────────

"""
Matches C `state_t` — 24 bytes on x86-64.
Fields: type (Cint, 4B), pad (4B), data (Ptr, 8B), qubits (UInt8, 1B), pad (7B).
"""
mutable struct OrkanStateRaw
    type::Cint
    _pad1::UInt32
    data::Ptr{ComplexF64}
    qubits::UInt8
    _pad2::NTuple{7,UInt8}

    function OrkanStateRaw(type::Cint)
        new(type, UInt32(0), C_NULL, UInt8(0), ntuple(_ -> UInt8(0), 7))
    end
end

"""
Matches C `kraus_t` — 24 bytes on x86-64.
Fields: n_qubits (UInt8, 1B), pad (7B), n_terms (UInt64, 8B), data (Ptr, 8B).
"""
struct OrkanKrausRaw
    n_qubits::UInt8
    _pad1::NTuple{7,UInt8}
    n_terms::UInt64
    data::Ptr{ComplexF64}
end

"""
Matches C `superop_t` — 16 bytes on x86-64.
Fields: n_qubits (UInt8, 1B), pad (7B), data (Ptr, 8B).
"""
mutable struct OrkanSuperopRaw
    n_qubits::UInt8
    _pad1::NTuple{7,UInt8}
    data::Ptr{ComplexF64}
end

# ── State functions ───────────────────────────────────────────────────────────

"""Initialise an OrkanStateRaw with zeroed storage. `state.type` must be set first."""
function orkan_state_init!(state::OrkanStateRaw, qubits::Integer)
    @ccall LIBORKAN.state_init(
        Ref(state)::Ptr{OrkanStateRaw},
        UInt8(qubits)::UInt8,
        C_NULL::Ptr{Ptr{ComplexF64}}
    )::Cvoid
    state.data == C_NULL && error("Orkan: state_init failed (out of memory for $qubits qubits)")
    nothing
end

"""Free the data buffer inside an OrkanStateRaw. Safe to call multiple times."""
function orkan_state_free!(state::OrkanStateRaw)
    @ccall LIBORKAN.state_free(Ref(state)::Ptr{OrkanStateRaw})::Cvoid
    nothing
end

"""Initialise state to uniform superposition |+>^n."""
function orkan_state_plus!(state::OrkanStateRaw, qubits::Integer)
    @ccall LIBORKAN.state_plus(
        Ref(state)::Ptr{OrkanStateRaw},
        UInt8(qubits)::UInt8
    )::Cvoid
    state.data == C_NULL && error("Orkan: state_plus failed (out of memory for $qubits qubits)")
    nothing
end

"""Return number of complex elements in state data array."""
function orkan_state_len(state::OrkanStateRaw)::UInt64
    @ccall LIBORKAN.state_len(Ref(state)::Ptr{OrkanStateRaw})::UInt64
end

"""Get element (row, col) from state. For PURE states, col must be 0."""
function orkan_state_get(state::OrkanStateRaw, row::Integer, col::Integer)::ComplexF64
    @ccall LIBORKAN.state_get(
        Ref(state)::Ptr{OrkanStateRaw},
        UInt64(row)::UInt64,
        UInt64(col)::UInt64
    )::ComplexF64
end

"""Set element (row, col) in state. For PURE states, col must be 0."""
function orkan_state_set!(state::OrkanStateRaw, row::Integer, col::Integer, val::ComplexF64)
    @ccall LIBORKAN.state_set(
        Ref(state)::Ptr{OrkanStateRaw},
        UInt64(row)::UInt64,
        UInt64(col)::UInt64,
        val::ComplexF64
    )::Cvoid
    nothing
end

# ── Gate functions ────────────────────────────────────────────────────────────

# 1-qubit gates (no parameter)
for gate in (:x, :y, :z, :h, :s, :sdg, :t, :tdg, :hy)
    fname = Symbol(:orkan_, gate, :!)
    @eval function $(fname)(state::OrkanStateRaw, target::Integer)
        @ccall LIBORKAN.$(gate)(
            Ref(state)::Ptr{OrkanStateRaw},
            UInt8(target)::UInt8
        )::Cvoid
        nothing
    end
end

# 1-qubit rotation gates (with angle)
for gate in (:rx, :ry, :rz, :p)
    fname = Symbol(:orkan_, gate, :!)
    @eval function $(fname)(state::OrkanStateRaw, target::Integer, theta::Real)
        @ccall LIBORKAN.$(gate)(
            Ref(state)::Ptr{OrkanStateRaw},
            UInt8(target)::UInt8,
            Float64(theta)::Float64
        )::Cvoid
        nothing
    end
end

# 2-qubit gates
for gate in (:cx, :cy, :cz)
    fname = Symbol(:orkan_, gate, :!)
    @eval function $(fname)(state::OrkanStateRaw, control::Integer, target::Integer)
        @ccall LIBORKAN.$(gate)(
            Ref(state)::Ptr{OrkanStateRaw},
            UInt8(control)::UInt8,
            UInt8(target)::UInt8
        )::Cvoid
        nothing
    end
end

function orkan_swap!(state::OrkanStateRaw, q1::Integer, q2::Integer)
    @ccall LIBORKAN.swap_gate(
        Ref(state)::Ptr{OrkanStateRaw},
        UInt8(q1)::UInt8,
        UInt8(q2)::UInt8
    )::Cvoid
    nothing
end

# 3-qubit gate
function orkan_ccx!(state::OrkanStateRaw, c1::Integer, c2::Integer, target::Integer)
    @ccall LIBORKAN.ccx(
        Ref(state)::Ptr{OrkanStateRaw},
        UInt8(c1)::UInt8,
        UInt8(c2)::UInt8,
        UInt8(target)::UInt8
    )::Cvoid
    nothing
end

# ── Channel functions ─────────────────────────────────────────────────────────

"""Convert Kraus representation to superoperator. Caller must free returned sop.data."""
function orkan_kraus_to_superop(kraus::OrkanKrausRaw)::OrkanSuperopRaw
    @ccall LIBORKAN.kraus_to_superop(Ref(kraus)::Ptr{OrkanKrausRaw})::OrkanSuperopRaw
end

"""Apply 1-qubit channel to a MIXED state. Exits on PURE state."""
function orkan_channel_1q!(state::OrkanStateRaw, sop::OrkanSuperopRaw, target::Integer)
    @ccall LIBORKAN.channel_1q(
        Ref(state)::Ptr{OrkanStateRaw},
        Ref(sop)::Ptr{OrkanSuperopRaw},
        UInt8(target)::UInt8
    )::Cvoid
    nothing
end

"""Free a superoperator's data buffer."""
function orkan_superop_free!(sop::OrkanSuperopRaw)
    if sop.data != C_NULL
        Libc.free(sop.data)
        sop.data = C_NULL
    end
    nothing
end
