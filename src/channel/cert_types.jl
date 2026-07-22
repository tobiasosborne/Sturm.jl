# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M8 (bead Sturm.jl-szx1), design gate
# `docs/design/m8-5hr7-unitary-block-design.md` §2: the CLEAN-ANCILLA CERTIFICATE
# type set (F1). A `CleanCert` is an ALGEBRAIC PROOF TERM, minted only by this
# closed constructor set, that discharges the universal containment invariant
#
#       (I − ιι†) W ι = 0                                        (design §2.2)
#
# for the block's frozen, phase-fixed program `W` — i.e. `W` maps the clean
# subspace `H_D ⊗ |0⟩_A` back into itself for ALL inputs, so `alloc → W → trace`
# is a fixed-port unitary on the surviving wires. This is a property of the
# PROGRAM STRUCTURE, universally quantified over inputs — NOT a statevector
# marginal on one run (the M5 `_clean_ancilla_assert!`, demoted to a debug
# cross-check, design §2.5). Under `TracingContext` there is no state at all, so a
# state assertion is not merely weak, it is inapplicable (design §2.1).
#
# NO `isapprox`, statevector, density matrix, Choi matrix, or sampled execution
# participates in CONSTRUCTING a certificate (design §2.2). Dense/Choi checks are
# TESTS of the structural checker, never construction routes (ruling TR4). The
# checkers (`src/channel/cert.jl`) validate rules against exact node identities,
# port roles, and frozen process values.
#
# The struct definitions live here (before `dag.jl`, which references `CleanCert`
# in `TraceN`); `MatchedPair` — the one cert that references `UnitaryBlock` — is
# defined with the `UnitaryBlock` struct (`src/kernel/unitary_block.jl`). The
# checkers and `certify` live in `src/channel/cert.jl` (after `ctrl.jl`, since the
# port-role analysis inspects `Ctrl`).
#
# Physics grounding:
#   docs/physics/bennett_1973_logical_reversibility.md — compute/copy/uncompute
#     (`PermClean` (★); the eq (3) inverse-pair in-place theorem for `MatchedPair`).
#   docs/physics/badescu_panangaden_quantum_alternation.md — control is undefined
#     on channel equivalence classes (they have quotiented the phase control needs);
#     the certificate is what promotes a frozen unitary trace back to a process value.

"""
    CleanCert

Abstract supertype of the closed clean-ancilla certificate constructor set
(design §2.2). Each concrete subtype is a proof RULE discharging the universal
containment `(I−ιι†)Wι = 0` on a structural fragment:

  • `NoAncilla`   — the body allocates no ancilla (closure of U(d) under ∘).
  • `PermClean`   — a Bennett `Perm` restores its declared scratch for every
                    input (the `(★)` theorem; `docs/physics/bennett_1973_...md`).
  • `MatchedPair` — the general alloc rule = `within`: `C† ∘ M ∘ C` with the
                    scratch read ONLY as control by `M` (defined with `UnitaryBlock`).
  • `SeqCert`/`ParCert` — certificates compose along `∘` / `⊗`.
  • `AdjointCert` — the adjoint of a clean block is clean (unitarity forces the
                    subspace invariance to be an equality, design §2.2 rule 6).
  • `XportCert`   — an exact boundary-preserving pass rewrite transports a cert
                    (RESERVED SEAM for the part-6 pass framework, design §2.2 rule 7).

All `CleanCert`s are deeply immutable (F28).
"""
abstract type CleanCert end

"""
    NoAncilla()

Rule 1 (design §2.2): the body allocates no ancilla; every node is an `ApplyN` of
a fixed-port process value, so the composite is a product of unitaries — unitary
by closure of U(d) under multiplication. Covers the COMMON `when` body
(teleportation Pauli corrections, kickback, `not!(dual(r))` = CZ, nested `when`).
"""
struct NoAncilla <: CleanCert end

"""
    PermClean(anc::NTuple{K,PortID})

Rule 2 (design §2.2): the covered body is a single `Perm` (Bennett artifact) with
declared ancilla ports `anc`. Bennett's `(★)`
(`docs/physics/bennett_1973_logical_reversibility.md`) guarantees
`P_f : |x⟩|t⟩|0⟩_anc ↦ |x⟩|t⊕f(x)⟩|0⟩_anc` for EVERY input — a theorem about the
GENERATOR STRUCTURE (no output wire is ever read as a control), not a runtime
observation. `ctrl(Perm) = Perm` keeps the block phase-free under control. This is
the term M8 puts in place of the `oracle` per-run `_free_clean!` assert
(`src/bennett/bridge.jl`). Frozen tuple of ancilla `PortID`s (F28).
"""
struct PermClean <: CleanCert
    anc::NTuple{K,PortID} where {K}
    PermClean(anc::Tuple{Vararg{PortID}}) = new(anc)
end
PermClean(anc::AbstractVector{PortID}) = PermClean(Tuple(anc))

"""
    SeqCert(a::CleanCert, b::CleanCert)

Rule 4 (design §2.2): a clean block ∘ a clean block on the same ports is clean
(each block's ancillas are local to it). Lets `certify` fold a `ChannelDAG`
bottom-up; carried by `∘(::UnitaryBlock, ::UnitaryBlock)`. `a` is the later
(outer) block, `b` the earlier (∘ is right-to-left).
"""
struct SeqCert <: CleanCert
    a::CleanCert
    b::CleanCert
end

"""
    ParCert(a::CleanCert, b::CleanCert)

Rule 5 (design §2.2): `⊗` of two clean blocks on DISJOINT ports is clean. Carried
by `⊗(::UnitaryBlock, ::UnitaryBlock)`.
"""
struct ParCert <: CleanCert
    a::CleanCert
    b::CleanCert
end

"""
    AdjointCert(src::CleanCert)

Rule 6 (design §2.2, from proposal A). If `W` leaves the clean subspace invariant,
unitarity forces EQUALITY (not mere inclusion), so `W†` leaves it invariant too.
`adjoint(::UnitaryBlock)` reverses the program, adjoints every `ApplyN`, and
swaps the alloc/trace ends; the resulting cert is `AdjointCert(src)`.
"""
struct AdjointCert <: CleanCert
    src::CleanCert
end

"""
    XportCert(src::CleanCert, rewrite::Symbol)

Rule 7 (design §2.2, from proposal A). RESERVED SEAM for the part-6 unitary-pass
framework: an exact, boundary-preserving pass rewrite (`rewrite` names the rule)
transports the certificate of its input. Defined here so the constructor set is
closed and the type is stable; `certify`/`commit` wiring lands with the pass
registry (NOT this slice).
"""
struct XportCert <: CleanCert
    src::CleanCert
    rewrite::Symbol
end
