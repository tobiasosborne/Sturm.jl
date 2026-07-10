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

public U2, Perm, Ctrl, Tensor, Seq, ProcessValue,
    ctrl, ⊗, denoted_matrix, nwires,
    X, Y, Z, H, S, T, Ry, Rz, Rx, I2, NEG_I, gphase

end # module Sturm
