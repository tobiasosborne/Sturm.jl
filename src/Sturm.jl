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
# Process values (U2, Perm, UnitaryDAG) and the choke-point combinators
# (ctrl, view, Ad) are internal machinery: documented and reachable as
# `Sturm.ctrl` etc., but never dumped into `using Sturm`. This stanza is
# populated starting M1 (U2/ctrl) — `public` is a Julia 1.11 keyword, so
# leave it commented until there is something real to mark.
#
# public U2, Perm, ctrl, view, Ad, ...

end # module Sturm
