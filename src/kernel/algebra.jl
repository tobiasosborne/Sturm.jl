# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M1: the monoidal combinators that
# make the algebra TOTAL — the general `⊗`, the generic `∘` fallback, and the
# `adjoint`/`denoted_matrix`/`≈` methods for the structural nodes `Tensor` and
# `Seq` (whose struct definitions live in u2.jl for include-order reasons). `∘`
# fuses only the two exact group multiplications (U2∘U2 Hamilton, Perm∘Perm
# concat, Ctrl∘Ctrl same-count homomorphism); everything else composes into a
# lazy, denotation-correct `Seq`. Correctness by denotation now, rewrite/fusion
# is an M8 pass — the laws-first spine (each fast path is cross-checked against
# `denoted_matrix`).
#
# Physics grounding:
#   docs/physics/wharton_koch_quaternion_bloch.md — ‾(pq)=q̄ p̄ ⇒
#     adjoint(V∘W)=adjoint(W)∘adjoint(V); reflected in Seq/Tensor adjoints.
#   docs/physics/delorme_control_as_constructor.md — ⊗ does NOT distribute
#     over ctrl (Caveats); the kernel assumes nothing of the sort.

"""
    ⊗(a::ProcessValue, b::ProcessValue) -> Tensor

Parallel composition: `a` on the leading (most-significant) wire block, `b` on
the trailing block. Returns a `Tensor` node (a `U2⊗U2` is a 2-qubit operator,
NOT a `U2`). `Perm ⊗ Perm` has its own closure method (perm.jl).
"""
⊗(a::ProcessValue, b::ProcessValue) = Tensor(a, b)

"""
    ∘(a::ProcessValue, b::ProcessValue) -> Seq

Generic composition fallback for operands that do not fuse to an exact group
element (the specialized `U2/Perm/Ctrl` methods take precedence). Same wires;
denotation-correct lazy node. Widths must match (fail loud).
"""
function Base.:∘(a::ProcessValue, b::ProcessValue)
    @assert nwires(a) == nwires(b) "∘: wire-count mismatch ($(nwires(a)) vs $(nwires(b)))"
    return Seq(a, b)
end

"""
    adjoint(t::Tensor) -> Tensor

`(A⊗B)† = A†⊗B†` — adjoint distributes over `⊗`.
"""
Base.adjoint(t::Tensor) = Tensor(adjoint(t.a), adjoint(t.b))

"""
    adjoint(s::Seq) -> Seq

`(A∘B)† = B†∘A†` — adjoint reverses composition order
(`docs/physics/wharton_koch_quaternion_bloch.md`, ‾(pq)=q̄ p̄).
"""
Base.adjoint(s::Seq) = Seq(adjoint(s.b), adjoint(s.a))

"""
    denoted_matrix(t::Tensor) -> Matrix{ComplexF64}

`kron(matrix(a), matrix(b))` — `a` is the most-significant (leftmost) factor.
"""
denoted_matrix(t::Tensor) = kron(denoted_matrix(t.a), denoted_matrix(t.b))

"""
    denoted_matrix(s::Seq) -> Matrix{ComplexF64}

`matrix(a) * matrix(b)` — `∘` is right-to-left, so `b` applies first.
"""
denoted_matrix(s::Seq) = denoted_matrix(s.a) * denoted_matrix(s.b)

"""
    isapprox(a::ProcessValue, b::ProcessValue; atol=U2_ATOL, rtol=0) -> Bool

Generic multi-wire U(2)-quotient equality: compare the denoted matrices (the
double-cover-safe reference semantics). `U2`/`Perm` pairs have cheaper
specialized methods; this covers `Ctrl`/`Tensor`/`Seq` and mixed kinds.
Different wire counts ⇒ `false` (never a `DimensionMismatch`).
"""
function Base.isapprox(a::ProcessValue, b::ProcessValue; atol::Real=U2_ATOL, rtol::Real=0)
    nwires(a) == nwires(b) || return false
    return isapprox(denoted_matrix(a), denoted_matrix(b); atol=atol, rtol=rtol)
end
