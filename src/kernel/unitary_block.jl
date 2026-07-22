# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M8 (bead Sturm.jl-szx1), design gate
# `docs/design/m8-5hr7-unitary-block-design.md` §1.3: `UnitaryBlock{N}` — the
# promoted, opaque, fixed-port unitary that JOINS THE `ProcessValue` TREE. It is
# the ONE value the M8 `ctrl` method wraps (P4: only a process value may be
# controlled). It is obtained by CERTIFYING a `ChannelDAG` (`src/channel/cert.jl`):
# the internal alloc/act/dealloc structure is existentially hidden behind `cert`,
# a structural clean-ancilla proof term (`src/channel/cert_types.jl`).
#
# This file holds the STRUCT + trivial accessors only (it is included BEFORE
# `ctrl.jl` so the choke point can define the single `ctrl(::UnitaryBlock)`
# method). The rich algebra — `denoted_matrix` (replay, `src/channel/replay.jl`)
# and `adjoint`/`∘`/`⊗` (`src/channel/block_algebra.jl`) — lives in files included
# AFTER `ctrl.jl`/`algebra.jl`, mirroring how `Tensor`/`Seq` split their struct
# (u2.jl) from their methods (algebra.jl).
#
# `MatchedPair` — the one `CleanCert` that references `UnitaryBlock` (its
# `compute` block) — is defined here too, closing the mutual recursion
# (`UnitaryBlock.cert::CleanCert` and `MatchedPair.compute::UnitaryBlock`).
#
# Physics grounding:
#   docs/physics/tang_wright_2025_controlled_unitaries.md — Thm 1.1: control
#     promotes global phase to observable physics, so a promoted block must carry
#     its full U(d) representative (phase included), and `≈` must never merge +I/−I.
#   docs/physics/bennett_1973_logical_reversibility.md — eq (3) inverse-pair /
#     compute-uncompute, the `MatchedPair` soundness (design §2.2 rule 3, §2.4).

"""
    UnitaryBlock{N} <: ProcessValue

A fixed-port unitary on `N` *external* (surviving) wires, obtained by CERTIFYING a
`ChannelDAG`. The internal alloc/act/dealloc structure is EXISTENTIALLY HIDDEN
behind `cert`. `N` in-ports == `N` out-ports (a unitary is SQUARE — design TR1),
and the ancilla ports are internal, discharged by `cert`. `<: ProcessValue`, so it
inherits the generic `∘`/`⊗`/`≈` from the kernel algebra and adds its own
`denoted_matrix`/`adjoint` (replay-based). It is the ONE value the M8 `ctrl`
method wraps (`ctrl(::UnitaryBlock)`, defined at the choke point `src/kernel/ctrl.jl`).

`{N}` is a TYPE PARAMETER (type-stable `ctrl`/`⊗`/apply width dispatch, mirroring
`QInt{W}`), and the boundary is a runtime `NTuple{N,Port}` carrying resource
lineage (rigorous endomorphism identity — design §1.2). The interior `Perm`/oracle
ancilla widths (which can be large) stay runtime data inside the frozen `body`, so
no distinct Julia method is specialized per oracle width (design §1.3).

INVARIANTS (checked at seal by `certify`, frozen after — F28):
  • `nwires(::UnitaryBlock{N}) == N == length(boundary)`  (external ports only)
  • boundary INPUT lineage == boundary OUTPUT lineage, in order (endomorphism §1.2)
  • `body` contains ONLY `ApplyN`/`AllocN`/`TraceN` — no barrier (those stay
    channel-level, design §1.3)
  • every `AllocN` is matched by a `TraceN` whose `cert` is non-`nothing`, and
    `cert` witnesses the composite is unitary on the `N` ports for ALL inputs (§2)

Never construct directly — `certify` is the only sound minter. The fields are
`public` for replay/adjoint/pass code but the invariants are only guaranteed on a
`certify` product.
"""
struct UnitaryBlock{N} <: ProcessValue
    boundary::NTuple{N,Port}   # ordered external ports; lineage in == lineage out
    body::ChannelDAG           # frozen; qin/qout lineage == boundary; cout empty
    cert::CleanCert            # the structural witness (§2)
end

"""
    nwires(::UnitaryBlock{N}) -> N

The external (surviving) wire count — the `N` type parameter. The internal ancilla
wires are hidden (they are allocated and traced inside `body`).
"""
nwires(::UnitaryBlock{N}) where {N} = N

"""
    boundary(b::UnitaryBlock) -> NTuple{N,Port}

The ordered external ports (input lineage == output lineage). `public` accessor
for replay / adjoint / pass code.
"""
boundary(b::UnitaryBlock) = b.boundary

# --- MatchedPair: the one CleanCert that names a UnitaryBlock -----------------

"""
    MatchedPair(compute::UnitaryBlock, inner::CleanCert)

Rule 3 (design §2.2) — the general alloc constructor = `within`. The ONLY
certificate that introduces fresh ancilla. Denotes `C† ∘ M ∘ C` where `C =
compute` allocs+computes scratch and `M` (certified by `inner`) acts on the
external wires reading scratch ONLY as control. The uncompute is `adjoint(C)` —
LITERALLY the same value reversed (`Base.adjoint(::Perm)` reverses generators,
`Base.adjoint(::Seq) = B†∘A†`), so whatever `C` wrote into scratch, `C†` erases,
for all inputs (`docs/physics/bennett_1973_logical_reversibility.md`, eq (3)
inverse pair). The load-bearing side condition — `M` does not disturb scratch's
computational value — is enforced STRUCTURALLY by the port-role / effect-footprint
analysis (`src/channel/cert.jl`): inside the `within` body, scratch handles appear
only as control, never as an `_act!` target.

Defined here (with `UnitaryBlock`) to close the mutual recursion. The `within`
surface combinator itself is a later slice; this slice ships the constructor +
checker, reachable by tests that build the DAG directly (task constraint).
"""
struct MatchedPair <: CleanCert
    compute::UnitaryBlock
    inner::CleanCert
end
