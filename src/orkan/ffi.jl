# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M2 (bead Sturm.jl-dc6i): the raw
# Orkan FFI shim — thin, guarded `ccall` wrappers around `liborkan`. This layer
# is INTERNAL (P5: an FFI is not a language); nothing here is exported or
# `public`. It is a near-verbatim re-port of v0.1's `ffi.jl`, certified by the
# ABI audit (`docs/design/orkan-abi-audit-m2.md`, §4: 24/24 ccall shapes
# VERIFIED-STILL-CURRENT, 0 drifted) — but the guards are RE-DERIVED from the
# fatal-error model, not trusted.
#
# THE SHARP EDGE (audit §5, §8.6): Orkan's `GATE_VALIDATE`/`CHANNEL_VALIDATE`
# macros call `exit(EXIT_FAILURE)` on a bad qubit index or NULL state. A bad
# index therefore KILLS THE JULIA PROCESS with no recoverable signal (`qs_error_t`
# exists but is decorative — nothing returns it). So EVERY wrapper validates
# Julia-side, BEFORE the ccall (CLAUDE.md #1 FAIL LOUD). A missed guard is not a
# bug, it is process death — v0.1 shipped the `channel_1q` omission twice (beads
# Sturm.jl-1oy). DSL-level aliasing checks (§8.4) fire ABOVE these shims, on
# WireID identity (see context/abstract.jl).
#
# GOTCHA (verified 2026-07-10): `state_init(state, n, NULL)` ZERO-allocates — it
# does NOT set |0…0⟩. The statevector is all-zeros until the caller sets
# amplitude 0 (`state_set(0,0,1)`); that initialization is a context concern
# (state.jl), never a bare-FFI one.
#
# Physics/spec grounding: `docs/design/orkan-abi-audit-m2.md` (the audited ABI
# truth); PRD-v2 §8.4 (aliasing before the shim), D7 (ZYZ boundary).

# --- State-type enum (state.h: PURE=0, MIXED_PACKED=1, MIXED_TILED=2) ---
const ORKAN_PURE = Cint(0)
const ORKAN_MIXED_PACKED = Cint(1)
const ORKAN_MIXED_TILED = Cint(2)

# --- Runtime-resolved library path -------------------------------------
#
# A `const Ref{String}` set in `__init__`, NOT a top-level `const` string:
# top-level resolution runs during PRECOMPILATION and would bake a possibly
# wrong path into the `.ji`. `__init__` runs at load time. Every ccall
# references `LIBORKAN[]` directly in the library position (a global const Ref
# is legal there; a local variable is NOT — "ccall library expression cannot
# reference local variables", verified 2026-07-10).
const LIBORKAN = Ref{String}()

"""
    _resolve_liborkan() -> String

Resolve the Orkan shared library, audit §9 search order:
1. `ENV["LIBORKAN_PATH"]` (explicit override; errors loud if set-but-missing),
2. sibling release build `../../../orkan/cmake-build-release/src/liborkan.so`,
3. the bare soname `"liborkan"` (system loader / RPATH; resolved lazily at the
   first ccall — a missing library there fails loud at that call).

No `dlopen` probing (avoids a `Libdl` dependency — CLAUDE.md #4 / M2 directive
"src/ gains NO dependencies"; `ccall`/`Libc` are Base): explicit candidates are
verified by `isfile`, the bare fallback defers to the dynamic loader. Because
we never `dlopen`, the v0.1 `InterruptException`-swallow class (bead
Sturm.jl-011f) cannot occur here.
"""
function _resolve_liborkan()
    if haskey(ENV, "LIBORKAN_PATH") && !isempty(ENV["LIBORKAN_PATH"])
        p = ENV["LIBORKAN_PATH"]
        isfile(p) || error("LIBORKAN_PATH=$p is set but does not exist. Fix it, unset it, or build:\n  cd ../orkan && cmake --preset release && cmake --build cmake-build-release")
        return p
    end
    sib = joinpath(@__DIR__, "..", "..", "..", "orkan", "cmake-build-release", "src", "liborkan.so")
    isfile(sib) && return sib
    # System loader / RPATH fallback; verified at first ccall.
    return "liborkan"
end

# --- Raw structs (byte-exact, audit §1/§4) -----------------------------

"""
Matches C `state_t` — 24 bytes on x86-64: `type` (Cint, 4B) + pad (4B) +
`data` (Ptr, 8B) + `qubits` (UInt8, 1B) + pad (7B). Mutable so Orkan can write
`data`/`qubits` through a `Ref`.
"""
mutable struct OrkanStateRaw
    type::Cint
    _pad1::UInt32
    data::Ptr{ComplexF64}
    qubits::UInt8
    _pad2::NTuple{7,UInt8}
    OrkanStateRaw(type::Cint) = new(type, UInt32(0), C_NULL, UInt8(0), ntuple(_ -> UInt8(0), 7))
end

"""
Matches C `kraus_t` — 24 bytes: `n_qubits` (UInt8, 1B) + pad (7B) + `n_terms`
(UInt64, 8B) + `data` (Ptr, 8B). Immutable: `data` references a Julia-owned
`Vector{ComplexF64}` (the caller wraps the ccall in `GC.@preserve` so the
buffer outlives the call). `data` = `n_terms` Kraus matrices, ROW-MAJOR concat.
"""
struct OrkanKrausRaw
    n_qubits::UInt8
    _pad1::NTuple{7,UInt8}
    n_terms::UInt64
    data::Ptr{ComplexF64}
end

"""
Matches C `superop_t` — 16 bytes: `n_qubits` (UInt8, 1B) + pad (7B) + `data`
(Ptr, 8B). Mutable so the owned buffer pointer can be niled after freeing. The
buffer is Orkan-`calloc`'d by `kraus_to_superop`; there is NO `superop_free` in
Orkan (audit §5) — free it with `Libc.free`.
"""
mutable struct OrkanSuperopRaw
    n_qubits::UInt8
    _pad1::NTuple{7,UInt8}
    data::Ptr{ComplexF64}
end

# --- Julia-side guards (Orkan exit()s on bad input — audit §5) ----------

@inline function _check_qubit(state::OrkanStateRaw, q::Integer, name::Symbol)
    state.data == C_NULL && error("Orkan.$name: state data is NULL")
    (0 <= q < state.qubits) || error("Orkan.$name: qubit $q out of range [0, $(Int(state.qubits)))")
end

@inline function _check_distinct(a::Integer, b::Integer, name::Symbol)
    a != b || error("Orkan.$name: qubits must be distinct (got $a, $b)")
end

@inline function _check_distinct3(a::Integer, b::Integer, c::Integer, name::Symbol)
    (a != b && a != c && b != c) || error("Orkan.$name: qubits must be distinct (got $a, $b, $c)")
end

# --- State lifecycle ---------------------------------------------------

"""
    orkan_state_init!(state, qubits)

Allocate a ZEROED `2^qubits` buffer (data NULL ⇒ zero-alloc). Does NOT set
|0…0⟩ — the caller sets amplitude 0 (state.jl). OOM is silent-ish (Orkan prints
to stderr, leaves `data == NULL`); we check and `error()` (audit §5).
"""
function orkan_state_init!(state::OrkanStateRaw, qubits::Integer)
    @ccall LIBORKAN[].state_init(Ref(state)::Ptr{OrkanStateRaw}, UInt8(qubits)::UInt8, C_NULL::Ptr{Ptr{ComplexF64}})::Cvoid
    state.data == C_NULL && error("Orkan: state_init failed (out of memory for $qubits qubits)")
    nothing
end

"""Free the data buffer (NULL-safe, idempotent — audit §5)."""
function orkan_state_free!(state::OrkanStateRaw)
    @ccall LIBORKAN[].state_free(Ref(state)::Ptr{OrkanStateRaw})::Cvoid
    nothing
end

"""Initialise to `|+⟩^n` (PURE) / maximally mixed (MIXED). OOM-checked."""
function orkan_state_plus!(state::OrkanStateRaw, qubits::Integer)
    @ccall LIBORKAN[].state_plus(Ref(state)::Ptr{OrkanStateRaw}, UInt8(qubits)::UInt8)::Cvoid
    state.data == C_NULL && error("Orkan: state_plus failed (out of memory for $qubits qubits)")
    nothing
end

"""Number of ComplexF64 elements in the state's data array."""
orkan_state_len(state::OrkanStateRaw)::UInt64 =
    @ccall LIBORKAN[].state_len(Ref(state)::Ptr{OrkanStateRaw})::UInt64

"""Get element `(row, col)`. PURE: `data[row]`, col ignored. MIXED: `ρ[row,col]` (Hermitian)."""
orkan_state_get(state::OrkanStateRaw, row::Integer, col::Integer)::ComplexF64 =
    @ccall LIBORKAN[].state_get(Ref(state)::Ptr{OrkanStateRaw}, UInt64(row)::UInt64, UInt64(col)::UInt64)::ComplexF64

"""Set element `(row, col)`."""
function orkan_state_set!(state::OrkanStateRaw, row::Integer, col::Integer, val::ComplexF64)
    @ccall LIBORKAN[].state_set(Ref(state)::Ptr{OrkanStateRaw}, UInt64(row)::UInt64, UInt64(col)::UInt64, val::ComplexF64)::Cvoid
    nothing
end

# --- Gate wrappers (generated; every one guards first) ------------------

# 1q, no parameter.
for gate in (:x, :y, :z, :h, :s, :sdg, :t, :tdg, :hy)
    fname = Symbol(:orkan_, gate, :!)
    @eval function $(fname)(state::OrkanStateRaw, target::Integer)
        _check_qubit(state, target, $(QuoteNode(gate)))
        @ccall LIBORKAN[].$(gate)(Ref(state)::Ptr{OrkanStateRaw}, UInt8(target)::UInt8)::Cvoid
        nothing
    end
end

# 1q, one angle (radians).
for gate in (:rx, :ry, :rz, :p)
    fname = Symbol(:orkan_, gate, :!)
    @eval function $(fname)(state::OrkanStateRaw, target::Integer, theta::Real)
        _check_qubit(state, target, $(QuoteNode(gate)))
        @ccall LIBORKAN[].$(gate)(Ref(state)::Ptr{OrkanStateRaw}, UInt8(target)::UInt8, Float64(theta)::Float64)::Cvoid
        nothing
    end
end

# 2q controlled (native).
for gate in (:cx, :cy, :cz)
    fname = Symbol(:orkan_, gate, :!)
    @eval function $(fname)(state::OrkanStateRaw, control::Integer, target::Integer)
        _check_qubit(state, control, $(QuoteNode(gate)))
        _check_qubit(state, target, $(QuoteNode(gate)))
        _check_distinct(control, target, $(QuoteNode(gate)))
        @ccall LIBORKAN[].$(gate)(Ref(state)::Ptr{OrkanStateRaw}, UInt8(control)::UInt8, UInt8(target)::UInt8)::Cvoid
        nothing
    end
end

"""SWAP — NB the C symbol is `swap_gate`, not `swap` (audit §4)."""
function orkan_swap!(state::OrkanStateRaw, q1::Integer, q2::Integer)
    _check_qubit(state, q1, :swap)
    _check_qubit(state, q2, :swap)
    _check_distinct(q1, q2, :swap)
    @ccall LIBORKAN[].swap_gate(Ref(state)::Ptr{OrkanStateRaw}, UInt8(q1)::UInt8, UInt8(q2)::UInt8)::Cvoid
    nothing
end

"""Toffoli (CCX)."""
function orkan_ccx!(state::OrkanStateRaw, c1::Integer, c2::Integer, target::Integer)
    _check_qubit(state, c1, :ccx)
    _check_qubit(state, c2, :ccx)
    _check_qubit(state, target, :ccx)
    _check_distinct3(c1, c2, target, :ccx)
    @ccall LIBORKAN[].ccx(Ref(state)::Ptr{OrkanStateRaw}, UInt8(c1)::UInt8, UInt8(c2)::UInt8, UInt8(target)::UInt8)::Cvoid
    nothing
end

"""Deep copy BY VALUE (audit §4): the returned struct's `data` is caller-owned, freed via `orkan_state_free!`."""
orkan_state_cp(state::OrkanStateRaw)::OrkanStateRaw =
    @ccall LIBORKAN[].state_cp(Ref(state)::Ptr{OrkanStateRaw})::OrkanStateRaw

# --- Channel wrappers (DM only) ----------------------------------------

"""Kraus → superop. `out.data` is Orkan-calloc'd; free via `Libc.free` (no `superop_free`, audit §5)."""
orkan_kraus_to_superop(kraus::OrkanKrausRaw)::OrkanSuperopRaw =
    @ccall LIBORKAN[].kraus_to_superop(Ref(kraus)::Ptr{OrkanKrausRaw})::OrkanSuperopRaw

"""
    orkan_channel_1q!(state, sop, target)

Apply a 1-local channel to a MIXED state. Guards (audit §1/§8.6, bead
Sturm.jl-1oy — the sole missing guard shipped as a process-kill regression):
qubit range, `sop.n_qubits == 1`, and `state.type != PURE` (Orkan `exit()`s on
PURE).
"""
function orkan_channel_1q!(state::OrkanStateRaw, sop::OrkanSuperopRaw, target::Integer)
    _check_qubit(state, target, :channel_1q)
    sop.n_qubits == 1 || error("Orkan.channel_1q: superop must be 1-local (got n_qubits=$(Int(sop.n_qubits)))")
    state.type != ORKAN_PURE || error("Orkan.channel_1q: PURE states have no channel path (exit() in Orkan); use a MIXED context")
    @ccall LIBORKAN[].channel_1q(Ref(state)::Ptr{OrkanStateRaw}, Ref(sop)::Ptr{OrkanSuperopRaw}, UInt8(target)::UInt8)::Cvoid
    nothing
end

# --- Module init (path, OMP ceiling, ABI asserts) ----------------------

"""
    __init__()

Load-time (NOT precompile) setup: resolve the library path, set the OpenMP
ceiling if unset, and assert the raw-struct byte layout. Orkan has no
thread-config API (audit §7) — threading is `OMP_NUM_THREADS` only; the device
ceiling is 16 (project memory), and we cap at `CPU÷4` to avoid oversubscribing
against Julia's threads, never clobbering a user-set value.
"""
function __init__()
    LIBORKAN[] = _resolve_liborkan()
    if !haskey(ENV, "OMP_NUM_THREADS")
        ENV["OMP_NUM_THREADS"] = string(clamp(Sys.CPU_THREADS ÷ 4, 1, 16))
    end
    # Fail loud on any future ABI drift (plan §6.2 risk register).
    @assert sizeof(OrkanStateRaw) == 24 "OrkanStateRaw ABI drift: sizeof=$(sizeof(OrkanStateRaw)) ≠ 24"
    @assert sizeof(OrkanKrausRaw) == 24 "OrkanKrausRaw ABI drift: sizeof=$(sizeof(OrkanKrausRaw)) ≠ 24"
    @assert sizeof(OrkanSuperopRaw) == 16 "OrkanSuperopRaw ABI drift: sizeof=$(sizeof(OrkanSuperopRaw)) ≠ 16"
    nothing
end
