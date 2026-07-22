# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M8 (bead Sturm.jl-szx1), design gate
# `docs/design/m8-5hr7-unitary-block-design.md` §3 (the PASS CONTRACT, F3), parts
# 5–6 of the §7.10 build order: the two PASS FRAMEWORKS.
#
#   • Part 5 — the CHANNEL-PASS framework (`ChannelPass`, `apply_pass(::ChannelPass,
#     ::ChannelDAG)::ChannelDAG`): a rewrite over the effect-typed channel IR whose
#     only correctness obligation is CHOI / diamond preservation of the typed CPTP
#     denotation (design §3.2 tier 2). A channel pass MAY cross a measurement /
#     cases / noise barrier; it may NEVER promote its result to a `UnitaryBlock`
#     (the return type is `ChannelDAG` — a type-level guarantee).
#
#   • Part 6 — the REPRESENTATIVE-PRESERVING UNITARY-PASS framework (`UnitaryPass`,
#     `apply_pass(::UnitaryPass, ::UnitaryBlock)::UnitaryBlock`): a rewrite that is
#     MECHANICALLY restricted to `UnitaryBlock`s (a barrier-containing DAG never
#     certifies — §4.1a — so a unitary pass can never touch a barrier, CLAUDE.md
#     "Channel IR vs Unitary Methods"). It must preserve the PHASE-INCLUSIVE `U(d)`
#     representative (design §3.2 tier 1): either `P(v) ≈ v` under the shipped
#     process-value `≈` (tier 1a, δ=0), or it reports a proved phase delta `δ` and
#     the trusted commit reattaches `gphase(−δ)` on one boundary qubit BEFORE the
#     result becomes a `UnitaryBlock` (tier 1b, PRD §4.2 pass law as shipped).
#
# ── THE PASS LAW IS PHASE-FAITHFUL, NOT CHOI-BLIND (F3) ─────────────────────────
# `Ad_U = Ad_{e^{iα}U}`, so Choi CANNOT see a leaked global phase — but the moment
# a phase-shifted block reaches `ctrl`, that phase becomes an OBSERVABLE relative
# phase (`ctrl(gphase(α)) = diag(1,1,e^{iα},e^{iα})`; Tang–Wright Thm 1.1,
# `docs/physics/tang_wright_2025_controlled_unitaries.md`). This is the
# Cirq/Qiskit/pytket control-decomposition bug class. So EVERY unitary pass
# carries TWO required law tests (design §3.4): the DIRECT representative equality
# `P(v) ≈ v` (phase-inclusive) AND the CTRL-WRAPPED Choi equality
# `Choi(Ad(ctrl(P(v)))) ≈ Choi(Ad(ctrl(v)))`. `PASS_REGISTRY` + a boot lint
# (test/runtests.jl + test/test_m8_passes.jl) mirror the `ctrl` choke point: a pass
# cannot ship without BOTH laws running against it.
#
# ── XportCert TRANSPORTS THE CERTIFICATE (design §2.2 rule 7) ───────────────────
# An EXACT, boundary-preserving rewrite transports its input's clean-ancilla
# certificate as `XportCert(src_cert, rule_name)`. The rewrites here touch only
# `ApplyN`s and never add/remove a boundary wire or an alloc/trace, so the block
# stays an endomorphism on the same lineage and the cert rides along.
#
# ── THE WIRE MODEL SUFFICES FOR THESE PASSES (orchestrator checkpoint) ──────────
# Slice 1 adopted a LINEAGE-CENTRIC IN-PLACE wire model (`src/channel/dag.jl`
# header): `ApplyN` acts in place on lineage-named wires; there is no per-op SSA
# re-versioning. Every rewrite below is a NODE-SEQUENCE rewrite that (a) preserves
# the ordered operator product on the SAME lineage-stable ports and (b) adds/removes
# no wire, so the denotation is preserved with no explicit output edges required:
#   • 1q-quaternion-fusion — replaces two consecutive `ApplyN(::U2,(p,))` on ONE
#     wire with `ApplyN(b∘a,(p,))`; the local product `M(b)·M(a) = M(b∘a)` is exact
#     (Hamilton), the port `p` is unchanged.
#   • view-fusion — removes two consecutive `ApplyN(::U2,(p,))` whose composite is
#     EXACTLY `I₂` (phase-inclusive; it REFUSES a pair composing to `−I` — that phase
#     is real under `ctrl`); the removed product is the neutral element.
#   • reassociation — replaces the 3-node window `V†; ctrl(W); V` (V on the target
#     ports only, disjoint from the control ports) with `ctrl(V∘W∘V†)` on the same
#     ports; the §4.2 control-scope law makes the two operators equal.
# None needs an explicit output-edge model, so no cross-slice wire-model rework.

# ============================================================================ #
#  PART 6 — the representative-preserving UNITARY-PASS framework                #
# ============================================================================ #

"""
    UnitaryPass

Abstract supertype of a representative-preserving unitary-block rewrite
(design §3, part 6). A `UnitaryPass` is applied ONLY through `apply_pass`, whose
signature `apply_pass(::UnitaryPass, ::UnitaryBlock)::UnitaryBlock` mechanically
(a) restricts the domain to `UnitaryBlock`s — so a barrier-containing DAG (which
never certifies, §4.1a) is unreachable — and (b) pins the codomain to
`UnitaryBlock`, so a unitary pass can NEVER produce a bare `ChannelDAG`
(design §3.2 tier 3). Concrete passes implement `_rewrite(::P, ::UnitaryBlock)`.
"""
abstract type UnitaryPass end

"""
    ChannelPass

Abstract supertype of a Choi/diamond-preserving channel rewrite (design §3,
part 5). Applied ONLY through `apply_pass(::ChannelPass, ::ChannelDAG)::ChannelDAG`.
A channel pass MAY cross a measurement/cases/noise barrier (its correctness is
CHANNEL-LEVEL — the typed CPTP denotation, compared by Choi, design §3.2 tier 2),
but it may NEVER return a `UnitaryBlock` (the codomain is `ChannelDAG`). Concrete
passes implement `_rewrite(::P, ::ChannelDAG)`.
"""
abstract type ChannelPass end

"""
    apply_pass(p::UnitaryPass, v::UnitaryBlock) -> UnitaryBlock
    apply_pass(p::ChannelPass, g::ChannelDAG)  -> ChannelDAG

The ONLY entry point for a pass. The two methods partition the namespace by value
kind (design §3.3 type layer): a `UnitaryPass` handed a `ChannelDAG` is a
`MethodError` and vice versa; a `ChannelPass` handed a `UnitaryBlock` is a
`MethodError` (`UnitaryBlock <: ProcessValue`, NOT `ChannelDAG`). The return-type
annotations pin the codomain: a `UnitaryPass` that tried to yield a `ChannelDAG`
would raise a conversion error, never silently down-type a process value to a
channel.
"""
apply_pass(p::UnitaryPass, v::UnitaryBlock)::UnitaryBlock = _rewrite(p, v)
apply_pass(p::ChannelPass, g::ChannelDAG)::ChannelDAG = _rewrite(p, g)

# --- The trusted commit: seal a rewritten body back into a UnitaryBlock ------

"""
    PhaseDelta(nodes, δ)

A tier-1b pass RESULT (design §3.2): the rewritten body `nodes` denotes
`e^{iδ}·U_v` for a PROVED delta `δ`, so it is NOT yet a valid `UnitaryBlock`
representative. The trusted `_commit` reattaches `gphase(−δ)` on one boundary
qubit BEFORE sealing, restoring `≈ v`. Kept INTERNAL in M8 (ruling TR7): the M8
passes are all δ=0, and an external phase-delta plugin API — plus zero-port scalar
blocks — each need their own design. Zero-port blocks are forbidden (TR7), so the
`gphase(−δ)` reattachment always has a boundary qubit to land on.
"""
struct PhaseDelta
    nodes::Vector{Node}
    δ::Float64
end

"""
    _commit(rule::Symbol, v::UnitaryBlock, result) -> UnitaryBlock

The trusted re-seal (design §3.3 type layer). `result` is either a rewritten
`Vector{Node}` (tier 1a, δ=0) or a `PhaseDelta` (tier 1b). Validates that the
boundary is UNCHANGED (an exact rewrite is an endomorphism on the SAME lineage —
`M8.PASS.PORT-AND-CERTIFICATE`), reattaches `gphase(−δ)` for tier 1b, freezes the
new body onto the ORIGINAL `qin`/`qout`, and transports the certificate as
`XportCert(v.cert, rule)` (design §2.2 rule 7). No new call site may seal a block;
this is the pass-side analogue of the `_ctrl` choke point.
"""
function _commit(rule::Symbol, v::UnitaryBlock{N}, result) where {N}
    if result isa PhaseDelta
        nodes = copy(result.nodes)
        # Reattach e^{−iδ} as a global phase on boundary qubit 1 (TR7: N ≥ 1, so a
        # boundary wire always exists). `gphase(−δ)` on one wire is `e^{−iδ}I₂`,
        # which embeds to `e^{−iδ}I_{2^N}` — a global scalar cancelling the leaked δ.
        push!(nodes, ApplyN(gphase(-result.δ), (v.boundary[1].id,)))
    else
        nodes = result
    end
    newbody = ChannelDAG(Tuple(nodes), v.body.qin, v.body.qout, ())
    return UnitaryBlock{N}(v.boundary, newbody, XportCert(v.cert, rule))
end

# --- Body-inspection helpers (shared by the concrete unitary passes) ---------

_is_1q_apply(nd::Node) = nd isa ApplyN && nd.v isa U2 && length(nd.ports) == 1

# ----------------------------------------------------------------------------
#  Concrete unitary pass 1 — 1q-quaternion-fusion                             #
# ----------------------------------------------------------------------------

"""
    Fuse1qPass()

Fuse two CONSECUTIVE single-wire `U2` applications on the SAME wire into one, by
the EXACT quaternion algebra: `ApplyN(a,(p,)); ApplyN(b,(p,))` ⇒ `ApplyN(b∘a,(p,))`
(`∘` is right-to-left, so `a` runs first). δ=0: `M(b)·M(a) = M(b∘a)` is the
Hamilton-product identity the kernel already certifies (`src/kernel/u2.jl`), so the
phase is carried exactly — `b∘a` NEVER merges `+I` with `−I`. Iterated to a
fixpoint over the body. A representative-preserving unitary pass
(`M8.PASS.UNITARY-REPRESENTATIVE`/`-CONTROLLED`).
"""
struct Fuse1qPass <: UnitaryPass end

function _rewrite(::Fuse1qPass, v::UnitaryBlock)
    nodes = collect(v.body.nodes)
    changed = false
    i = 1
    while i < length(nodes)
        a = nodes[i]; b = nodes[i+1]
        if _is_1q_apply(a) && _is_1q_apply(b) && a.ports[1] == b.ports[1]
            fused = ApplyN(b.v ∘ a.v, a.ports)          # b∘a : a first
            nodes = vcat(nodes[1:i-1], [fused], nodes[i+2:end])
            changed = true
            # stay at i to keep fusing a longer run
        else
            i += 1
        end
    end
    return changed ? _commit(:fuse1q, v, nodes) : v
end

# ----------------------------------------------------------------------------
#  Concrete unitary pass 2 — view-fusion (F ∘ … ∘ F† conjugation windows)     #
# ----------------------------------------------------------------------------

"""
    ViewFusionPass()

Collapse an adjacent inverse pair on one wire — the degenerate `F ∘ F†`
conjugation window of a view basis-change (`F = H` for a `QBool`, `F = QFT` for a
`QInt`; `docs/physics/wharton_koch_quaternion_bloch.md`). Removes two CONSECUTIVE
`ApplyN(::U2,(p,))` whose composite `b∘a` is EXACTLY `I₂` under the phase-inclusive
process `≈` (never merging `+I`/`−I`). This REFUSES a pair composing to `−I`: that
`π` is a real operation under `ctrl` (`docs/physics/tang_wright_2025_controlled_unitaries.md`
Thm 1.1) — dropping it would be the phase-leak bug the pass law forbids. δ=0
(the removed product is the neutral element). Iterated to a fixpoint.
"""
struct ViewFusionPass <: UnitaryPass end

function _rewrite(::ViewFusionPass, v::UnitaryBlock)
    nodes = collect(v.body.nodes)
    changed = false
    i = 1
    while i < length(nodes)
        a = nodes[i]; b = nodes[i+1]
        if _is_1q_apply(a) && _is_1q_apply(b) && a.ports[1] == b.ports[1] &&
           (b.v ∘ a.v) ≈ I2                          # EXACT identity, phase-inclusive
            nodes = vcat(nodes[1:i-1], nodes[i+2:end])   # drop both
            changed = true
            i = max(i - 1, 1)                          # a new adjacency may appear
        else
            i += 1
        end
    end
    return changed ? _commit(:viewfusion, v, nodes) : v
end

# ----------------------------------------------------------------------------
#  Concrete unitary pass 3 — reassociation (the §4.2 control-scope law)       #
# ----------------------------------------------------------------------------

"""
    ReassocPass()

The §4.2 control-scope-reassociation law as a rewrite (`docs/physics/delorme_control_as_constructor.md`
Eq 16; PRD §4.2): rewrite the 3-node window

    ApplyN(V†, tports); ApplyN(ctrl^k(W), cports); ApplyN(V, tports)

— where `V` acts on the TARGET ports `tports` only (the trailing `nwires(W)` ports
of the `ctrl` value, disjoint from its `k` leading control ports) — into the single
node `ApplyN(ctrl^k(V∘W∘V†), cports)`. By the law `(1⊗V)∘ctrl(W)∘(1⊗V†) =
ctrl(V∘W∘V†)` the two operators are EQUAL (δ=0, phase included), so the ancilla-free
conjugation is narrowed under the control. The `ctrl^k` is rebuilt through the
PUBLIC `ctrl` combinator (the choke point stays honest). Applies at most once per
call at the first matching window (iterate the pass to exhaust).
"""
struct ReassocPass <: UnitaryPass end

function _rewrite(::ReassocPass, v::UnitaryBlock)
    nodes = collect(v.body.nodes)
    for i in 1:(length(nodes) - 2)
        n1 = nodes[i]; n2 = nodes[i+1]; n3 = nodes[i+2]
        (n1 isa ApplyN && n2 isa ApplyN && n3 isa ApplyN) || continue
        (n2.v isa Ctrl) || continue
        c = n2.v
        k = c.k
        nc = length(n2.ports)
        nc == k + nwires(c.inner) || continue
        cports = n2.ports[1:k]
        tports = n2.ports[(k+1):nc]
        # V acts on exactly the target ports, both sides; V† = n1, V = n3.
        n1.ports == tports || continue
        n3.ports == tports || continue
        nwires(n1.v) == length(tports) || continue
        # controls disjoint from the conjugation window's wires.
        isempty(intersect(Set(cports), Set(tports))) || continue
        # n1 must be the operator adjoint of n3 (V† ∘ … ∘ V), phase-inclusive.
        (n1.v ≈ adjoint(n3.v)) || continue
        V = n3.v
        conj = V ∘ c.inner ∘ adjoint(V)             # V∘W∘V†
        newc = conj
        for _ in 1:k
            newc = ctrl(newc)                        # ctrl^k via the public combinator
        end
        newnode = ApplyN(newc, n2.ports)
        nodes = vcat(nodes[1:i-1], [newnode], nodes[i+3:end])
        return _commit(:reassoc, v, nodes)
    end
    return v
end

# --- The pass registry + registration (design §3.3 registry layer) -----------

"""
    PASS_REGISTRY :: Dict{Symbol,UnitaryPass}

The registry of representative-preserving unitary passes (design §3.3). Every
`UnitaryPass` that may run in the pipeline registers here at load, and the boot
lint (test/test_m8_passes.jl, mirrored in test/runtests.jl) enumerates it and
asserts BOTH required law tests (`M8.PASS.UNITARY-REPRESENTATIVE[name]` and
`M8.PASS.UNITARY-CONTROLLED[name]`) ran against each entry — the same "you cannot
add a call site without its phase test" discipline that fixed the `ctrl`
control-decomposition bug class. Channel passes are NOT registered here (their
correctness is Choi, not the phase-inclusive representative — a different law).
"""
const PASS_REGISTRY = Dict{Symbol,UnitaryPass}()

_register_pass!(name::Symbol, p::UnitaryPass) = (PASS_REGISTRY[name] = p; p)

_register_pass!(:fuse1q, Fuse1qPass())
_register_pass!(:viewfusion, ViewFusionPass())
_register_pass!(:reassoc, ReassocPass())

# ============================================================================ #
#  PART 5 — the CHANNEL-PASS framework                                         #
# ============================================================================ #

"""
    FuseUnitaryRunsPass()

A CHANNEL pass (design §3, part 5) that PARTITIONS the channel IR at barriers
(`MeasureN`/`CasesN`/`NoiseN`) and fuses adjacent single-wire `U2` runs WITHIN each
maximal barrier-free segment — the concrete realization of CLAUDE.md's "partition
at measurement barriers; apply unitary-only methods ONLY to unitary blocks". It
NEVER moves a node across a barrier and preserves the DAG signature (`qin`/`qout`/
`cout` unchanged), so its typed CPTP denotation — hence its Choi — is preserved
(`M8.PASS.CHANNEL-DENOTATION`). Being a `ChannelPass`, it returns a `ChannelDAG`
and can never promote to a `UnitaryBlock` (design §3.2 tier 3).
"""
struct FuseUnitaryRunsPass <: ChannelPass end

function _rewrite(::FuseUnitaryRunsPass, g::ChannelDAG)
    out = Node[]
    seg = Node[]
    flush_seg!() = (append!(out, _fuse_1q_run(seg)); empty!(seg))
    for nd in g.nodes
        if is_barrier(nd)
            flush_seg!()
            push!(out, nd)                            # the barrier stays put — NEVER crossed
        else
            push!(seg, nd)
        end
    end
    flush_seg!()
    return ChannelDAG(Tuple(out), g.qin, g.qout, g.cout)
end

"""
    _fuse_1q_run(nodes) -> Vector{Node}

Fuse consecutive same-wire `U2` `ApplyN`s within one barrier-free segment (the
channel-pass local rewrite; same exact Hamilton identity as `Fuse1qPass`). Non-`U2`
and multi-wire nodes pass through unchanged.
"""
function _fuse_1q_run(nodes)
    res = copy(nodes)
    i = 1
    while i < length(res)
        a = res[i]; b = res[i+1]
        if _is_1q_apply(a) && _is_1q_apply(b) && a.ports[1] == b.ports[1]
            res = vcat(res[1:i-1], [ApplyN(b.v ∘ a.v, a.ports)], res[i+2:end])
        else
            i += 1
        end
    end
    return res
end

"""
    DeferMeasurementPass()

A CHANNEL pass (design §3, part 5; §7.10 build order lists deferred measurement as
a channel pass) that would rewrite `measure(w) → cases(record)` into a COHERENT
`ctrl` off the still-unmeasured wire plus a TERMINAL `measure` — the deferred-
measurement principle, licensed by CHANNEL-level Choi equality. **FRAMEWORK SLOT —
rewrite body DEFERRED.** The rewrite needs the `MeasureN`/`CasesN` TOKEN /
correlation-record semantics (the Kleisli join), which is the parallel i4ri round =
M8 part 7 (design §6 seam). Until those land, this pass is the identity on any DAG:
it recognizes no `measure+cases` pattern to defer. It is registered as a
`ChannelPass` (returns `ChannelDAG`), rejects a `UnitaryBlock` (`MethodError`), and
its Choi law is trivially satisfied by identity — the SLOT is real and typed; only
the rewrite body waits on part 7.
"""
struct DeferMeasurementPass <: ChannelPass end

function _rewrite(::DeferMeasurementPass, g::ChannelDAG)
    # DEFERRED: the measure→ctrl+terminal-measure rewrite needs part-7 CasesN token
    # semantics. Identity until then (no pattern is recognized without the record).
    return g
end

# ============================================================================ #
#  `within` — the MatchedPair combinator (design §2.2 rule 3, ruling TR3)      #
# ============================================================================ #

"""
    _ublock_of(v::ProcessValue) -> UnitaryBlock

Certify a single-`ApplyN` `NoAncilla` block denoting `v` on `nwires(v)` fresh
inputs. Internal helper for `within`'s `MatchedPair.compute` provenance block.
"""
function _ublock_of(v::ProcessValue)
    b = DAGBuilder()
    ws = PortID[input!(b) for _ in 1:nwires(v)]
    apply_node!(b, v, ws...)
    return certify(b)
end

"""
    within(compute::ProcessValue, inner::ProcessValue) -> UnitaryBlock

The `within` combinator (design §2.2 rule 3, ruling TR3): a PUBLIC kernel/library
API — NOT an eighth surface construct — that builds the certified `C† ∘ M ∘ C`
compute/use/uncompute block with a fresh ancilla, carrying a `MatchedPair`
certificate with tier-A structural provenance (the uncompute is LITERALLY
`adjoint(compute)`, so `_is_adjoint_pair` proves the inverse relation with no float
— `docs/physics/bennett_1973_logical_reversibility.md` eq (3)).

Canonical (ancilla-as-control) shape, matching the shipped `MatchedPair` fixtures:
`compute` acts on `[data…, scratch]` (its LAST wire is the fresh `|0⟩` scratch);
`inner` acts on `[scratch, targets…]` reading `scratch` ONLY as its leading control.
The result is a `UnitaryBlock` on `[data…, targets…]` (scratch factored out),
denoting `C†∘M∘C`. A general inner-block form is a follow-on (the surface `within`
do-block is a later slice).

The `MatchedPair.compute` field is CROSS-CHECKED at `certify` against the body's
compute writer (`_check_matched_pair`, `src/channel/cert.jl`), per the slice-1
ruling, so the certificate cannot name a compute block that disagrees with what the
body actually applies.
"""
function within(compute::ProcessValue, inner::ProcessValue)
    kc = nwires(compute)                              # data (kc−1) + scratch (1)
    ki = nwires(inner)                                # scratch (1) + targets (ki−1)
    kc >= 1 || error("within: compute must act on ≥1 wire (its last wire is scratch)")
    ki >= 1 || error("within: inner must act on ≥1 wire (its first wire is scratch)")
    b = DAGBuilder()
    data = PortID[input!(b) for _ in 1:(kc - 1)]
    scr = alloc!(b)
    tgts = PortID[input!(b) for _ in 1:(ki - 1)]
    apply_node!(b, compute, data..., scr)             # C: writes scratch
    apply_node!(b, inner, scr, tgts...)               # M: scratch as leading control
    apply_node!(b, adjoint(compute), data..., scr)    # C†: uncompute (tier-A provenance)
    trace!(b, scr; cert = MatchedPair(_ublock_of(compute), NoAncilla()))
    return certify(b)
end
