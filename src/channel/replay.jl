# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M8 (bead Sturm.jl-szx1), design gate
# `docs/design/m8-5hr7-unitary-block-design.md` §1.4/§4: the REFERENCE SEMANTICS of
# a `UnitaryBlock` — `denoted_matrix` by small-scale matrix replay on `ancilla=|0⟩`.
#
# `denoted_matrix(::UnitaryBlock{N})` replays `body` with every ancilla wire
# initialized to `|0⟩`, materializes the full `2^{N+A} × 2^{N+A}` unitary `W`, and
# reads off the `2^N × 2^N` block on the clean subspace `H_D ⊗ |0⟩_A` (the cert
# guarantees the ancilla factors out — `(I−ιι†)Wι = 0`, design §2.4). This is a
# TEST/Ad CROSS-CHECK tool (like every other `denoted_matrix`), gated by a MEMORY
# BUDGET cap (TR8 — NOT the 30-qubit pure ceiling): above it, error loudly rather
# than allocate an intractable dense matrix (CLAUDE.md #1). Pure Base linear algebra
# (`kron`/`*`/index arithmetic) — core takes no `LinearAlgebra` dependency
# (CLAUDE.md conv 4; `_eye`, `src/kernel/numerics.jl`).
#
# WIRE CONVENTION (wire 1 = MSB, shared with Perm/Ctrl): the N external boundary
# wires are the MSBs (wires 1..N in boundary order), the A ancilla wires are the
# trailing LSBs (wires N+1..N+A in allocation order). So `ancilla=|0⟩` ⟺ the low A
# bits are 0, and the clean block is the sub-lattice of indices `ext * 2^A`.
#
# Physics grounding:
#   docs/physics/wharton_koch_quaternion_bloch.md — the phase-carrying denotation
#     `e^{iφ}U(q)` a block inherits from its leaf `ApplyN`s (phase never quotiented).
#   docs/physics/tang_wright_2025_controlled_unitaries.md — why the block must keep
#     its full U(d) representative (control promotes global phase to observable).

"""
    UBLOCK_DENOTE_MAXWIRES

Memory-budget cap on the total wire count `N + A` for `denoted_matrix(::UnitaryBlock)`
(design TR8 / F25). A `2^n × 2^n` `ComplexF64` matrix is `16·2^{2n}` bytes; at
`n = 12` that is ~256 MiB, the ceiling for the dense replay. Above it, replay errors
LOUDLY (randomized reference-assisted probes are the intended larger-scale route,
a follow-on). Reference semantics only — never the execution path.
"""
const UBLOCK_DENOTE_MAXWIRES = 12

"""
    _embed_on_wires(M, wires::Vector{Int}, n::Int) -> Matrix{ComplexF64}

Embed the `2^k × 2^k` operator `M` (acting on `k = length(wires)` qubits, with
`wires[1]` as `M`'s MSB) into the `2^n × 2^n` operator on an `n`-wire register
(wire 1 = MSB). `Full[i,j] = M[a(i),a(j)]` when `i,j` agree on all non-`wires` bits,
else 0 — the standard tensor embedding, written with bit arithmetic so core needs
no `LinearAlgebra`. O(2^{2n}) — fine at the replay's small (capped) scale.
"""
function _embed_on_wires(M::AbstractMatrix, wires::Vector{Int}, n::Int)
    k = length(wires)
    N = 1 << n
    # bit position of wire c in an n-wire index (wire 1 = MSB): shift (n - c).
    shifts = Int[n - c for c in wires]
    # mask of the acted bits (to compute "rest" agreement quickly).
    actedmask = 0
    for s in shifts
        actedmask |= (1 << s)
    end
    restmask = (N - 1) & ~actedmask
    subidx = idx -> begin
        a = 0
        @inbounds for t in 1:k
            a |= ((idx >> shifts[t]) & 1) << (k - t)   # wires[1] → MSB of a
        end
        return a
    end
    Full = zeros(ComplexF64, N, N)
    @inbounds for j in 0:(N - 1)
        aj = subidx(j)
        rj = j & restmask
        for i in 0:(N - 1)
            (i & restmask) == rj || continue
            Full[i + 1, j + 1] = M[subidx(i) + 1, aj + 1]
        end
    end
    return Full
end

"""
    _block_wire_map(b::UnitaryBlock{N}) -> (id2wire, n, A)

Assign wire indices to the block's ports: the `N` external boundary ports get
wires `1..N` (MSB-first, boundary order); each `AllocN.out` ancilla gets a trailing
wire `N+1 …` in allocation order. Returns the `PortID → wire` map, the total wire
count `n = N+A`, and the ancilla count `A`. Asserts width-1 quantum ports (the
wider-bundle replay is a reserved seam) and the TR8 cap.
"""
function _block_wire_map(b::UnitaryBlock{N}) where {N}
    id2wire = Dict{PortID,Int}()
    for (t, p) in enumerate(b.boundary)
        is_quantum(p) || error("denoted_matrix(UnitaryBlock): non-quantum boundary port $(p)")
        portwidth(p) == 1 || error("denoted_matrix(UnitaryBlock): boundary port width $(portwidth(p)) ≠ 1 — wide-bundle replay is a reserved M8 seam")
        id2wire[p.id] = t
    end
    A = 0
    for nd in b.body.nodes
        if nd isa AllocN
            is_quantum(nd.out) || error("denoted_matrix(UnitaryBlock): non-quantum AllocN $(nd.out)")
            portwidth(nd.out) == 1 || error("denoted_matrix(UnitaryBlock): ancilla port width ≠ 1 — reserved seam")
            A += 1
            id2wire[nd.out.id] = N + A
        end
    end
    n = N + A
    n <= UBLOCK_DENOTE_MAXWIRES || error(
        "denoted_matrix(UnitaryBlock): $n wires (N=$N external + A=$A ancilla) exceeds " *
        "UBLOCK_DENOTE_MAXWIRES=$UBLOCK_DENOTE_MAXWIRES memory budget (TR8) — dense replay " *
        "intractable; use randomized reference-assisted probes for wider blocks.")
    return (id2wire, n, A)
end

"""
    denoted_matrix(b::UnitaryBlock{N}) -> Matrix{ComplexF64}

The `2^N × 2^N` unitary this block denotes (phase included — the U(d)
representative). Replays `body` on `ancilla=|0⟩`, building the full `2^n` unitary
`W = ∏ node`, then extracts the clean-subspace block (ancilla in/out `|0⟩`). The
certificate guarantees `W(H_D ⊗ |0⟩_A) ⊆ H_D ⊗ |0⟩_A`, so the extracted block is
unitary (verified by `M8.CERT.CLEAN-SUBSPACE`). `AllocN`/`TraceN` contribute the
identity to `W` (the ancilla is present-and-|0⟩ from the start; the discard is the
final projection); only `ApplyN`s act.
"""
function denoted_matrix(b::UnitaryBlock{N}) where {N}
    N >= 1 || error("denoted_matrix(UnitaryBlock): zero-port blocks are forbidden in M8 (TR7)")
    (id2wire, n, A) = _block_wire_map(b)
    W = _eye(1 << n)
    for nd in b.body.nodes
        if nd isa ApplyN
            wires = Int[id2wire[p] for p in nd.ports]
            length(wires) == nwires(nd.v) || error(
                "denoted_matrix(UnitaryBlock): ApplyN value $(typeof(nd.v)) has $(nwires(nd.v)) wires but $(length(wires)) ports")
            Mv = denoted_matrix(nd.v)
            W = _embed_on_wires(Mv, wires, n) * W
        elseif nd isa AllocN || nd isa TraceN
            # structural: alloc = ι (ancilla born |0⟩, already in the register);
            # trace = ι† (final projection, applied by block extraction below).
        else
            error("denoted_matrix(UnitaryBlock): body holds a non-unitary node $(typeof(nd)) — certify should have rejected it")
        end
    end
    # Extract the clean-subspace block: ancilla are the trailing A wires (LSBs), so
    # ancilla=|0⟩ ⟺ index ≡ 0 (mod 2^A). Clean index of external e is e * 2^A.
    step = 1 << A
    Ne = 1 << N
    U = Matrix{ComplexF64}(undef, Ne, Ne)
    @inbounds for j in 0:(Ne - 1), i in 0:(Ne - 1)
        U[i + 1, j + 1] = W[i * step + 1, j * step + 1]
    end
    return U
end

"""
    denoted_full(b::UnitaryBlock) -> Matrix{ComplexF64}

The FULL `2^{N+A} × 2^{N+A}` replay unitary `W` (external + ancilla), BEFORE the
clean-subspace projection. `public` test hook for `M8.CERT.CLEAN-SUBSPACE`, which
checks `‖(I−ιι†)Wι‖ ≈ 0` and `U = ι†Wι` unitary directly. Not used by execution.
"""
function denoted_full(b::UnitaryBlock)
    (id2wire, n, _A) = _block_wire_map(b)
    W = _eye(1 << n)
    for nd in b.body.nodes
        if nd isa ApplyN
            wires = Int[id2wire[p] for p in nd.ports]
            W = _embed_on_wires(denoted_matrix(nd.v), wires, n) * W
        end
    end
    return W
end
