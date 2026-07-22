# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl, a quantum programming DSL where
# functions are channels, the quantum-classical boundary is a type
# boundary, and QECC is a higher-order function.

"""
    Sturm

A quantum programming DSL for Julia.

Functions are channels; the quantum-classical boundary is a type boundary
(a *cast*, not an `if`); error correction is a higher-order function over
channels, not a circuit transform bolted on afterwards.

This module is currently a scaffold (v2 milestone 0, bead `23o1` +
`2o0y`): no quantum functionality exists yet. The normative specification
is `Sturm-PRD-v2.md` at the repository root — read it before writing or
reviewing any code that lands here. `Sturm-PRD.md` (v0.1) remains
relevant only for the parts v2 explicitly carries over (see
`Sturm-PRD-v2.md` §0 and `CLAUDE.md`).

Build order and milestone plan: `Sturm-v2-IMPLEMENTATION-PLAN.md`.
"""
module Sturm

# --- Surface layer (exported; PRD-v2 §3.8, CLAUDE.md convention 8) ---
# The seven surface constructs — QBool/Bool/QInt casts, the action
# family (not!, ⊻=, add!), dual, when, cases/@cases, oracle — will be
# `export`ed from here as they land (starting M3). Nothing is exported
# yet: there is no quantum code in milestone 0.
#
# export QBool, not!, dual, when, cases, oracle, ...

# --- Kernel layer (public, not exported; CLAUDE.md convention 8) ---
# Process values and the choke-point combinators are internal machinery:
# documented and reachable as `Sturm.U2`, `Sturm.ctrl`, `Sturm.X`, …, but
# never dumped into `using Sturm`. `public` is a Julia 1.11 keyword.
#
# Include order is dependency-respecting (numerics → u2 → perm → ctrl →
# algebra → constants); see each file's header. `ctrl.jl` (the single
# choke point) precedes `algebra.jl`, so the `Tensor`/`Seq` STRUCTS are
# defined in `u2.jl` (their rich methods stay in `algebra.jl`).
include("kernel/numerics.jl")
include("kernel/u2.jl")
include("kernel/perm.jl")
include("kernel/ctrl.jl")
include("kernel/algebra.jl")
include("kernel/constants.jl")

# --- M2: FFI, Ad application, contexts, regions (bead Sturm.jl-dc6i) ---
# Dependency-respecting order: wire identity → raw FFI → state lifecycle →
# context core + primitive emitters → Ad emitter (uses the emitters + kernel
# values) → concrete contexts (trace lowerings) → regions (resource forms,
# ScopedValue, @context/region/ptrace!). The `orkan/` layer stays INTERNAL
# (P5: an FFI is not a language); only `apply!` and the context/region surface
# cross the visibility wall.
include("types/wire.jl")
include("orkan/ffi.jl")
include("orkan/state.jl")
include("context/abstract.jl")
include("orkan/ad.jl")
include("context/eager.jl")
include("context/density.jl")
include("context/regions.jl")

# --- M3: QBool, the boundary casts (bead Sturm.jl-77m2) ---------------
# The FIRST surface vocabulary of the rebuild. `types/register.jl` (the F16
# context-indexed handle hierarchy `AbstractQRegister{C}`/`AbstractQubit{C}` +
# the F15 number-like-handle contract) before `types/qbool.jl` (the register
# handle + preparation cast) before `surface/casts.jl` (the measurement cast
# dispatches on QBool); all after the M2 context layer they call into.
include("types/register.jl")
include("types/qbool.jl")
include("surface/casts.jl")

# --- M4: views, dual, the action family (bead Sturm.jl-3nld) ----------
# `kernel/views.jl` lives under kernel/ (LAYERING: view machinery is `public`,
# not surface) but is included HERE, in dependency order: `_dual_transform(::QBool)`
# and `dual(::QBool)` need `QBool` (M3) and the kernel `H`/`∘` (M1). No M1/M2/M3
# logic is edited — a view is never an `apply!` argument; each surface view-op
# computes a concrete process value + parent WireIDs and calls the landed `apply!`.
include("kernel/views.jl")
include("surface/actions.jl")

# --- M5: `when` — streaming coherent control (bead Sturm.jl-o5yh) ------
# Control-stack push/pop + `_act!` (the control-aware apply! sibling) + the three
# §3.5 guardrails + the §3.9 clean-ancilla exit witness. Included AFTER actions.jl
# (whose action-family methods now call `_act!`, forward-referenced — resolved at
# call time) and after the M2 context/region layer it reads (`control_stack`,
# `_trace_and_free!`, `_marginal_p1`, `_density`). No new ctrl-lowering code:
# nested `when` ⇒ flat `ctrl^k` ⇒ the existing ad.jl lowering.
include("surface/when.jl")

# --- M6: QInt{W}, wire handles, two arithmetic worlds, QFT (bead Sturm.jl-80g6) ---
# `kernel/qft.jl` (the F_G process value + P(θ) + the DFT lowering) before
# `types/qint.jl` (whose `_dual_transform(::QInt)` returns a `QFT`) before
# `surface/arithmetic.jl` (the two-world method table). qft.jl lives under
# kernel/ (LAYERING: the DFT lowering is `public`, not surface) but is included
# HERE in dependency order — it needs M2's `_apply_controlled_u2!`/`_emit_h!`.
include("kernel/qft.jl")
include("types/qint.jl")
include("surface/arithmetic.jl")

# --- M7: the Bennett bridge — oracle(f,x) + b ⊻= oracle (bead Sturm.jl-7a0v) ---
# CORE half only (names no Bennett type): the `CompiledOracle`/`OracleQuery`
# values, the `oracle` entry + weakdep backend hook, the two `Base.xor`
# application methods, and the `_apply_oracle!` choreography. The `f → Perm`
# compile lives in `ext/SturmBennettExt.jl` (activated by `using Bennett`). This
# reads `_act!` (M5), `region()`/`allocate!` (M2), `_clean_ancilla_assert!` (M5),
# `_assert_live` (M3), and `QInt`/`AbstractQubit` (M6/M3), so it is included last.
include("bennett/bridge.jl")

# --- Surface scaffolding (exported; region vocabulary users type) -----
export @context, region, ptrace!

# --- Surface casts + literals (exported; PRD-v2 §3.2/§3.8, M3) ---------
# The preparation cast and its named library constants. `Bool(q)` /
# `convert(Bool, q)` are Base method extensions (no new name to export).
export QBool, plus, minus, magic_T

# --- Surface action family + view (exported; PRD-v2 §3.3/§3.4/§3.8, M4) -
# `dual` (construct 4) and `not!` (construct 3). The `⊻=` forms and
# `Bool(dual(q))` are `Base.xor`/`Base.Bool` method extensions on our own types
# (no new name to export; `⊻`/`Bool(…)` are host syntax).
export dual, not!

# --- Surface coherent control (exported; PRD-v2 §3.5/D13, M5) ----------
# `when` (construct 5). The control stack, `_act!`, the guardrail helpers, and
# the clean-ancilla witness stay INTERNAL (machinery, not layer API).
export when

# --- Surface integer registers + arithmetic (exported; §3.3/§3.4/D2/D12, M6) --
# `QInt` (the width-W register + preparation cast) and the ACTION-family names
# `add!`/`sub!`/`superpose!`. `Int(x)`, `x[i]`, `x + a`, `x ⊻= y`, `x̂ += a` are
# Base method extensions on our own types (no new name); `dual`/`not!`/`when`
# already exported. The `WireRef` slice type, the `QFT` value, and the `P(θ)`
# phase constant are kernel `public` (reachable as `Sturm.…`, never `using`-dumped).
export QInt, add!, sub!, superpose!

# --- Surface Bennett bridge (exported; PRD-v2 §3.4/§7.4/§7.5/D9/D14, M7) ---
# `oracle` (construct 7). `b ⊻= oracle(f, x)` is a `Base.xor` method extension on
# our own `OracleQuery` (no new name); the query value types are kernel `public`
# (reachable as `Sturm.OracleQuery`, never `using`-dumped — 7 produces, 3 applies).
export oracle

public U2, Perm, Ctrl, Tensor, Seq, ProcessValue,
    ctrl, ⊗, denoted_matrix, nwires,
    X, Y, Z, H, S, T, Ry, Rz, Rx, I2, NEG_I, gphase,
    # M2 kernel/context surface (reachable as `Sturm.X`, not dumped into `using`)
    WireID, AbstractContext, EagerContext, DensityMatrixContext,
    eager, density, current_context, apply!, allocate!, deallocate!,
    q, consumed, mark_consumed!, is_consumed, live_wires, teardown!,
    statevector, density_matrix, apply_channel!, sqrt_u2,
    # M4 view machinery (kernel `public`, reachable as `Sturm.view`, not dumped)
    view, View, DualView,
    # F16/F15 register hierarchy + traits (kernel `public`, not dumped)
    AbstractQRegister, contextof, contexttype, register_style,
    RegisterStyle, NumberLikeHandleStyle, AddressingModeStyle,
    # F19 duality/bicharacter trait (kernel `public`, reachable as `Sturm.duality`)
    duality, bicharacter, pairing_exponent, action_group,
    DualitySpec, ActionFamily, AddFamily, XorFamily,
    # M6 kernel/type surface (kernel `public`, reachable as `Sturm.QFT`, not dumped)
    QFT, P, WireRef, AbstractQubit,
    # M7 Bennett bridge query values (kernel `public`, 7 produces / 3 applies)
    OracleQuery, CompiledOracle

end # module Sturm
