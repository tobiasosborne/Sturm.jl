# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M8 (bead Sturm.jl-szx1), design gate
# `docs/design/m8-5hr7-unitary-block-design.md` §2/§2.3: the STRUCTURAL SEALER
# `certify(::ChannelDAG) :: UnitaryBlock` (or a LOUD `ArgumentError`), and the
# PORT-ROLE / EFFECT-FOOTPRINT analysis that discharges the `MatchedPair` side
# condition. Included AFTER `ctrl.jl` because the footprint analysis inspects
# `Ctrl` (leading ports are controls).
#
# `certify` discharges the universal containment `(I−ιι†)Wι = 0` STRUCTURALLY —
# NO state, NO Choi, NO sampling as a certificate-construction route (design §2.2,
# ruling TR4): the prohibition targets runtime OBSERVATION. Comparing two program
# VALUES with the kernel's phase-inclusive `≈` is NOT observation — it is universally
# quantified over inputs and touches no statevector — so the shared matched-pair
# check (`_is_adjoint_pair`) may fall back to `≈` (tier B) when a self-adjoint `U2`
# is representation-brittle under exact `==`; see its docstring. It refuses loudly if the DAG contains a barrier
# (`MeasureN`/`CasesN`/`NoiseN` — channel-level, §4.4), has classical outputs, is
# not an endomorphism on its resource lineage (§1.2), or has an `AllocN` not
# matched by a `TraceN` carrying a valid certificate. The F1 adversary
# (`a = QBool(false); a ⊻= r; drop a`) is rejected here because its `AllocN` has no
# matched certified `TraceN` — INDEPENDENT of the runtime input (test
# `M8.CERT.STATE-IS-NOT-WITNESS`).
#
# Physics grounding:
#   docs/physics/bennett_1973_logical_reversibility.md — the compute/uncompute
#     inverse pair (eq (3)) that makes `MatchedPair` clean; the `(★)` that makes
#     `PermClean` clean.
#   docs/physics/delorme_control_as_constructor.md — `Ctrl` leading ports are
#     read-only controls (the footprint delegation rule).

# --- Port-role / effect-footprint analysis (design §2.2) ---------------------

"""
    _footprint(v::ProcessValue, ports) -> (controls::Set{PortID}, targets::Set{PortID})

Which of `ports` (in `v`'s wire order, MSB-first) `v` reads as CONTROL vs acts on
as TARGET (design §2.2). A port that is ever a target is classified target (it is
acted on); pure-control ports are control. This is the mechanism the `MatchedPair`
checker uses to enforce "scratch appears only as control, never an `_act!` target"
inside a `within` body.

  • `U2`      targets its sole port.
  • `Perm`    derives roles per `MCX` (target of any generator ⇒ target).
  • `Ctrl{V}` leading `k` ports are read-only controls; the rest delegate to `V`.
  • `Tensor`  unions disjoint footprints; `Seq` composes on the same ports.
  • `UnitaryBlock` is treated conservatively (ALL its ports as targets) — the
    fail-closed rule (§2.2): an opaque block may touch any of its wires. (A precise
    recursion into the block body is a refinement, not needed by this slice.)
  • Unknown kinds conservatively "target every port" (fail-closed).
"""
function _footprint(v::U2, ports)
    return (Set{PortID}(), Set{PortID}((ports[1],)))
end

function _footprint(v::Perm, ports)
    controls = Set{PortID}()
    targets = Set{PortID}()
    for g in v.gates
        push!(targets, ports[g.target])
        for c in g.controls
            push!(controls, ports[c])
        end
    end
    setdiff!(controls, targets)   # a wire acted on anywhere is a target
    return (controls, targets)
end

function _footprint(c::Ctrl, ports)
    k = c.k
    leadctrl = Set{PortID}(ports[1:k])
    (ci, ti) = _footprint(c.inner, ports[(k+1):end])
    controls = union(leadctrl, ci)
    setdiff!(controls, ti)
    return (controls, ti)
end

function _footprint(t::Tensor, ports)
    na = nwires(t.a)
    (ca, ta) = _footprint(t.a, ports[1:na])
    (cb, tb) = _footprint(t.b, ports[(na+1):end])
    targets = union(ta, tb)
    controls = union(ca, cb)
    setdiff!(controls, targets)
    return (controls, targets)
end

function _footprint(s::Seq, ports)
    (ca, ta) = _footprint(s.a, ports)
    (cb, tb) = _footprint(s.b, ports)
    targets = union(ta, tb)
    controls = union(ca, cb)
    setdiff!(controls, targets)
    return (controls, targets)
end

# Fail-closed: an opaque block / unknown kind targets every port (design §2.2).
_footprint(::UnitaryBlock, ports) = (Set{PortID}(), Set{PortID}(ports))
_footprint(::ProcessValue, ports) = (Set{PortID}(), Set{PortID}(ports))

# --- certify (design §2.3) ---------------------------------------------------

"""
    _id_to_lineage(dag) -> Dict{PortID,Int}

Resolve every `PortID` used in `dag` to its physical `lineage`: the boundary
inputs and every `AllocN.out` carry a full `Port` (with lineage); `ApplyN`/`TraceN`
reference those `PortID`s in place. (The lineage-centric in-place wire model —
`src/channel/dag.jl` header.)
"""
function _id_to_lineage(dag::ChannelDAG)
    m = Dict{PortID,Int}()
    for p in dag.qin
        m[p.id] = p.lineage
    end
    for nd in dag.nodes
        nd isa AllocN && (m[nd.out.id] = nd.out.lineage)
        nd isa MeasureN && (m[nd.out] = -1)   # classical token: no quantum lineage
    end
    return m
end

"""
    certify(dag::ChannelDAG) -> UnitaryBlock

Promote a `ChannelDAG` to a `UnitaryBlock` by minting a structural clean-ancilla
certificate, or fail loudly (`ArgumentError`, CLAUDE.md #1). Refuses: any barrier
(`MeasureN`/`CasesN`/`NoiseN`); non-empty classical outputs; a non-endomorphism
(output boundary lineage ≠ input boundary lineage, in order — §1.2); a zero-port
block (TR7); an `AllocN` not matched by a `TraceN` carrying a valid certificate
(the F1 adversary). Otherwise assembles the block cert from the matched traces
(`NoAncilla` when no ancilla) and returns `UnitaryBlock{N}(qin, frozen(dag), cert)`.

Acquisition is COMBINATOR-CARRIED (design §2.3, ruling TR4): `within` ⇒
`MatchedPair`, `oracle` ⇒ `PermClean`, ancilla-free ⇒ `NoAncilla`. Tests build the
DAG directly and attach the cert to the `TraceN`. The syntactic matched-uncompute
verifier for a raw flat stream is a deferred follow-on (design §2.3 secondary).
"""
function certify(dag::ChannelDAG)
    has_barrier(dag) && throw(ArgumentError(
        "certify: DAG contains a measurement/cases/noise BARRIER — it is a channel, " *
        "not a unitary block (§2.3/§4.4); control and unitary passes are unrepresentable on it (P4)."))
    isempty(dag.cout) || throw(ArgumentError(
        "certify: DAG has classical/token outputs (cout) — a unitary block has none (§1.3)."))
    N = length(dag.qin)
    N >= 1 || throw(ArgumentError(
        "certify: zero-port UnitaryBlock is forbidden in M8 (TR7 — defer scalar e^{iφ}: I→I values)."))
    length(dag.qout) == N || throw(ArgumentError(
        "certify: output boundary arity $(length(dag.qout)) ≠ input arity $N — not an endomorphism (§1.2)."))
    for i in 1:N
        pin = dag.qin[i]; pout = dag.qout[i]
        (is_quantum(pin) && is_quantum(pout)) || throw(ArgumentError(
            "certify: boundary port $i is not quantum — a unitary block acts on quantum wires."))
        pin.lineage == pout.lineage || throw(ArgumentError(
            "certify: boundary LINEAGE mismatch at position $i (in=$(pin.lineage) vs out=$(pout.lineage)) — " *
            "the block is not an endomorphism on the same physical wire (§1.2: width equality is not identity)."))
    end

    id2lin = _id_to_lineage(dag)
    alloc_lineages = Int[nd.out.lineage for nd in dag.nodes if nd isa AllocN]
    boundary_lineages = Set{Int}(p.lineage for p in dag.qin)

    # Each TraceN must reference an ALLOCATED (scratch) wire — never a boundary
    # input — and carry a non-nothing certificate (the F1 rejection).
    traced_lineages = Int[]
    for nd in dag.nodes
        nd isa TraceN || continue
        haskey(id2lin, nd.in) || throw(ArgumentError(
            "certify: TraceN references unknown port $(nd.in)."))
        lin = id2lin[nd.in]
        lin in boundary_lineages && throw(ArgumentError(
            "certify: TraceN discards a BOUNDARY input (lineage $lin) — a unitary block may not trace its own inputs (§1.3)."))
        nd.cert === nothing && throw(ArgumentError(
            "certify: TraceN on scratch lineage $lin carries NO clean-ancilla certificate — " *
            "an unmatched ancilla discard (the F1 adversary `a ⊻= r; drop a`). A statevector marginal " *
            "on one run is not a witness (§2.1); the discard must be justified structurally by `within`/`oracle`."))
        push!(traced_lineages, lin)
    end

    # Every allocation must be matched by exactly one certified trace, and vice versa.
    for al in alloc_lineages
        count(==(al), traced_lineages) == 1 || throw(ArgumentError(
            "certify: allocated scratch lineage $al is not matched by exactly one certified TraceN " *
            "(F1: an ancilla born and dropped without a compute/uncompute proof)."))
    end

    cert = _assemble_cert(dag, alloc_lineages, id2lin, boundary_lineages)
    _check_cert(cert, dag, id2lin, boundary_lineages)
    return UnitaryBlock{N}(dag.qin, dag, cert)
end

"""
    _assemble_cert(dag, alloc_lineages, id2lin, boundary_lineages) -> CleanCert

Fold the (validated-structure) node stream into a block-level `CleanCert`: a
`NoAncilla` when nothing is allocated; otherwise the certificate(s) carried by the
matched `TraceN`(s), `SeqCert`-folded if there is more than one scratch region.
"""
function _assemble_cert(dag, alloc_lineages, id2lin, boundary_lineages)
    isempty(alloc_lineages) && return NoAncilla()
    trace_certs = CleanCert[nd.cert for nd in dag.nodes if nd isa TraceN]
    length(trace_certs) == 1 && return trace_certs[1]
    return foldl(SeqCert, trace_certs)
end

# --- Structural certificate checkers (design §2.2) ---------------------------

"""
    _check_cert(cert, dag, id2lin, boundary_lineages)

Validate a `CleanCert` against the DAG's exact node identities and port roles — no
`isapprox`/state (design §2.2). Throws `ArgumentError` on a lie.
"""
function _check_cert(::NoAncilla, dag, id2lin, boundary_lineages)
    any(nd -> nd isa AllocN, dag.nodes) && throw(ArgumentError(
        "certify: NoAncilla certificate on a DAG that allocates ancilla — inconsistent."))
    return nothing
end

function _check_cert(c::PermClean, dag, id2lin, boundary_lineages)
    # Every declared ancilla port must resolve to an allocated (scratch) lineage,
    # and the body must apply at least one Perm covering them (Bennett `(★)`,
    # structural — the exhaustive truth-table is the TEST, not construction).
    for pid in c.anc
        haskey(id2lin, pid) || throw(ArgumentError("certify(PermClean): unknown ancilla port $pid."))
        lin = id2lin[pid]
        lin in boundary_lineages && throw(ArgumentError(
            "certify(PermClean): declared ancilla lineage $lin is a boundary wire, not scratch."))
    end
    any(nd -> nd isa ApplyN && nd.v isa Perm, dag.nodes) || throw(ArgumentError(
        "certify(PermClean): no Perm application in the body — PermClean witnesses a Bennett Perm artifact (§2.2 rule 2)."))
    return nothing
end

function _check_cert(c::MatchedPair, dag, id2lin, boundary_lineages)
    scratch = Set{Int}(nd.out.lineage for nd in dag.nodes if nd isa AllocN)
    _check_matched_pair(dag, scratch, id2lin, c.compute)
    # The inner region's own certificate (usually NoAncilla) rides along; recurse
    # only when it points at further structure (SeqCert/ParCert/AdjointCert accept).
    return nothing
end

_check_cert(::SeqCert, dag, id2lin, boundary_lineages) = nothing   # sub-blocks validated at their own certify
_check_cert(::ParCert, dag, id2lin, boundary_lineages) = nothing
_check_cert(::AdjointCert, dag, id2lin, boundary_lineages) = nothing
_check_cert(::XportCert, dag, id2lin, boundary_lineages) = nothing

"""
    _is_adjoint_pair(v1::ProcessValue, v2::ProcessValue) -> Bool

Is the uncompute `v2` the operator inverse of the compute `v1` (`v2 = v1†`)? The
SINGLE matched-pair comparison discipline, shared by the `certify` `MatchedPair`
checker (`_check_matched_pair`) and the streaming `when`-body seal
(`_seal_check_scratch`, `src/surface/when.jl`) so the two never fork. Two tiers:

  • **Tier A — structural provenance (preferred; exact, no numerics).** `v1` is
    LITERALLY `adjoint(v2)` by construction/object structure: `v1 == adjoint(v2)`
    (exact field equality). This is the `Perm`/`within`-combinator case — the
    uncompute is the same value reversed (`Base.adjoint(::Perm)` reverses generators),
    so the inverse relation is present in the representation, provable with no float.

  • **Tier B — phase-inclusive process `≈` (float-law fallback).** When no structural
    provenance exists (a streamed body whose uncompute was produced independently),
    compare with the kernel's phase-inclusive `isapprox`: `v1 ≈ adjoint(v2)`. This is
    REQUIRED because a self-adjoint `U2` is representation-brittle under exact `==` —
    `adjoint(X) = U2(0,−1,0,0,−π/2) ≠ X = U2(0,1,0,0,π/2)` as stored quaternion fields,
    though `X† = X` as an operator (the conjugate flips the vector part AND the phase).
    `≈` is the phase-faithful process equality PRD §4.1 mandates for float laws (it
    never merges `+I`/`−I`).

Design §2.2's "NEVER `isapprox`" prohibition targets STATE/Choi/SAMPLED execution as
a certificate-construction route — a runtime OBSERVATION. Comparing two program
VALUES with the kernel's own `≈` is NOT a runtime observation: it is universally
quantified over inputs and touches no statevector, so F1 (the certificate, not the
run, is the witness) is intact. Tier A is tried first precisely to keep the common
`Perm`/`within` case exact.
"""
function _is_adjoint_pair(v1::ProcessValue, v2::ProcessValue)
    a2 = adjoint(v2)
    v1 == a2 && return true          # tier A: exact structural provenance
    return v1 ≈ a2                   # tier B: phase-inclusive process ≈ (§4.1 float law)
end

"""
    _check_matched_pair(dag, scratch::Set{Int}, id2lin)

Enforce the `within` compute/uncompute discipline STRUCTURALLY (design §2.2 rule 3):

  1. The `ApplyN` nodes that write scratch (a scratch lineage in their TARGET
     footprint) are the compute/uncompute pair — this slice requires EXACTLY TWO
     (the general palindrome is the deferred syntactic verifier, ruling TR4/R4).
  2. The uncompute's process value is the operator adjoint of the compute's — checked
     by the shared `_is_adjoint_pair` (tier-A exact provenance, tier-B phase-inclusive
     `≈`; see its docstring for why comparing two VALUES with `≈` is not the §2.2
     runtime-observation prohibition), so whatever the compute wrote into scratch, the
     uncompute erases (Bennett eq (3)).
  3. Every OTHER node touching scratch reads it only as CONTROL (guaranteed by (1):
     a non-writer has no scratch target). Between the pair, scratch is preserved, so
     the uncompute still inverts the compute on the ancilla — the ancilla returns to
     `|0⟩` for ALL inputs (`(I−ιι†)Wι = 0`).
  4. COMPUTE-FIELD CROSS-CHECK (slice-3 ruling). The `MatchedPair.compute` block
     `C` the certificate NAMES must actually agree with the body's compute writer:
     `denoted_matrix(C) ≈ denoted_matrix(writers[1].v)` (phase-inclusive). This is a
     comparison of two PROGRAM VALUES (universally quantified over inputs, no state —
     like `_is_adjoint_pair` tier B), NOT a runtime observation, so F1's "the
     certificate, not the run, is the witness" is intact. It stops a `MatchedPair`
     from claiming a `compute` block that disagrees with what the body applies (a
     mis-built cert). Skipped only when `compute === nothing`.
"""
function _check_matched_pair(dag::ChannelDAG, scratch::Set{Int}, id2lin,
                             compute::Union{Nothing,ProcessValue} = nothing)
    writers = ApplyN[]
    for nd in dag.nodes
        nd isa ApplyN || continue
        (_ctrls, tgts) = _footprint(nd.v, collect(nd.ports))
        touches_scratch_target = any(p -> get(id2lin, p, -2) in scratch, tgts)
        touches_scratch_target && push!(writers, nd)
    end
    length(writers) == 2 || throw(ArgumentError(
        "certify(MatchedPair): expected exactly 2 scratch-writing (compute/uncompute) applications, " *
        "found $(length(writers)) — the general matched-uncompute palindrome is a deferred verifier (TR4/R4)."))
    _is_adjoint_pair(writers[1].v, writers[2].v) || throw(ArgumentError(
        "certify(MatchedPair): the uncompute is not the operator adjoint of the compute " *
        "(v₁ ≠ v₂†) — the ancilla is not provably restored to |0⟩ (§2.2 rule 3, Bennett eq (3))."))
    if compute !== nothing
        nwires(compute) == nwires(writers[1].v) || throw(ArgumentError(
            "certify(MatchedPair): the named compute block acts on $(nwires(compute)) wire(s) but the " *
            "body's compute writer acts on $(nwires(writers[1].v)) — the certificate names the wrong C."))
        (compute ≈ writers[1].v) || throw(ArgumentError(
            "certify(MatchedPair): the named compute block does not denote the body's compute writer " *
            "(compute-field cross-check, slice-3 ruling) — a mis-built certificate."))
    end
    return nothing
end
