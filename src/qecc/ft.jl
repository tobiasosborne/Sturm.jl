# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M11 (bead Sturm.jl-qmpo), design
# `docs/design/m11-82su-synthesis.md` ruling S26: `fault_tolerant_lift` as
# INTERFACE + THEOREM-GROUNDED REFUSAL. Lifting a logical algorithm to a
# fault-tolerant physical implementation is NOT canonical — the code alone
# does not determine it — and for the universal case it CANNOT be transversal:
# Eastin–Knill (PRL 102 110502,
# docs/physics/eastin_knill_2009_no_universal_transversal.md; NB the theorem's
# hypothesis needs distance ≥ 2 — the M11 bit-flip code, d = 1, sits BELOW it
# and genuinely carries a continuous transversal logical family e^{iθZ̄}, the
# session-105 G1/G2 finding). The refusal is a theorem, not an implementation
# gap; the five ingredients below are what any real lift must supply.

"Abstract fault model (S26): which physical faults occur, where, and how often."
abstract type FaultModel end

"Abstract gadget set (S26): the per-code implementations of logical operations."
abstract type GadgetSet end

"""
    FTImplementation{C<:StabilizerCode}

Abstract supertype for a concrete fault-tolerant implementation recipe. M11
ships NO concrete subtype (S26) — the type exists so the signature of
[`fault_tolerant_lift`](@ref) is honest about what it would take.
"""
abstract type FTImplementation{C<:StabilizerCode} end

"""
    fault_tolerant_lift(Φ::LogicalChannel, impl) -> never returns

LOUD refusal (S26, grounded on Eastin–Knill): lifting a logical channel to a
fault-tolerant physical implementation is not canonical and M11 does not
pretend otherwise. The message names the five missing ingredients; a test
asserts the message content (`M11.QECC.FT-LIFT-HONEST`).
"""
fault_tolerant_lift(Φ::LogicalChannel, impl) = throw(ArgumentError(
    "fault_tolerant_lift: not available — a fault-tolerant lift is NOT canonical " *
    "(the code alone does not determine it), and for universal gate sets no code " *
    "of distance ≥ 2 admits an all-transversal implementation (Eastin–Knill, " *
    "docs/physics/eastin_knill_2009_no_universal_transversal.md). Supplying one " *
    "needs FIVE ingredients M11 does not have: (1) a fault model; (2) a gadget " *
    "set with a per-code transversality declaration; (3) a magic-state / " *
    "gate-teleportation protocol for the non-transversal remainder; (4) a " *
    "syndrome-extraction schedule sound under a NOISY-syndrome model (M11's " *
    "recovery assumes perfect extraction — the code-capacity model, S27); and " *
    "(5) threshold accounting. File the FT epic; do not fake it here."))
