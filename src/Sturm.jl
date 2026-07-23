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
# --- M8 channel IR: STRUCTS (bead Sturm.jl-szx1; design m8-5hr7 §1/§2) ------
# Included BEFORE ctrl.jl so the single new method `ctrl(::UnitaryBlock)` can
# dispatch (design §1.4: the one edit to the choke-point file). Dependency order:
# ports (PortID/Port) → cert-type structs (CleanCert, referenced by TraceN) → the
# channel-IR node structs + ChannelDAG → the UnitaryBlock struct + MatchedPair
# (which closes the UnitaryBlock↔CleanCert mutual recursion). Only STRUCTS here;
# the rich methods (replay, certify, block algebra) are included after
# ctrl/algebra/constants, mirroring the Tensor/Seq struct(u2)/method(algebra) split.
include("channel/ports.jl")
include("channel/cert_types.jl")
include("channel/dag.jl")
include("kernel/unitary_block.jl")
include("kernel/ctrl.jl")
include("kernel/algebra.jl")
include("kernel/constants.jl")
# --- M8 channel IR: METHODS (after the kernel algebra they build on) --------
# `replay.jl` = denoted_matrix(::UnitaryBlock) (small-scale matrix replay on
# ancilla=|0⟩, TR8 cap); `cert.jl` = certify + port-role/effect-footprint analysis
# (needs Ctrl, so after ctrl.jl); `block_algebra.jl` = adjoint/∘/⊗ producing
# certified blocks (AdjointCert/SeqCert/ParCert); `builder.jl` = the mutable
# DAG builder (freeze on certify — F28) that tests use to build DAGs directly.
include("channel/replay.jl")
include("channel/cert.jl")
include("channel/block_algebra.jl")
include("channel/builder.jl")
# --- M8 pass frameworks (parts 5–6; design m8-5hr7 §3): the ChannelPass /
# UnitaryPass abstractions, `apply_pass`, the trusted phase-faithful `_commit`
# (XportCert transport + tier-1b gphase reattach), the three concrete unitary
# passes (fuse1q / view-fusion / reassoc) + PASS_REGISTRY, the FuseUnitaryRuns
# channel pass + the deferred-measurement framework slot, and the `within`
# combinator. Included after builder.jl (uses DAGBuilder/certify/block algebra/ctrl).
include("channel/passes.jl")

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

# --- M8: i4ri classical-control (bead Sturm.jl-szx1; DM/Eager slice) ---------
# Classical outcome TOKENS + T2/T3 finite SSA (`surface/tokens.jl`), then
# `cases`/`@cases` + `select`/`shots`/`discard!` (`surface/cases.jl`). Included
# LAST: the DM `_cast_bool`/`_cast_int` token seams (Ruling D) are called from
# M3/M6 casts by forward reference (resolved at call time), and the executor
# reuses `_instrument_record!` (density.jl), `_push_control!`/`_act!` (when.jl),
# and `_trace_and_free!`/region ownership (M2) — no new physics primitive.
# Reserved seams for the next slice: TracingContext token variant, MeasureNode/
# CasesNode emission, the DeferMeasurementPass rewrite body, the tracer pre-flight lint.
include("surface/tokens.jl")
include("surface/cases.jl")

# --- M8: i4ri classical-control, TRACING half (bead Sturm.jl-szx1) -----------
# The `TracingContext` (the COMPILER context — executes nothing, materializes a
# `ChannelDAG`; no Orkan/FFI), the Ruling-D measurement-cast seams
# (`_cast_bool`/`_cast_int(::TracingContext, …)` → MeasureN + wire token), the
# `cases` materializer (`_cases_ctx_run(::TracingContext, …)` → nested CasesN), the
# tracer pre-flight lint (`_note_nonportable!`), the `trace(f, nin)` HOF, and the DM
# REPLAY (`_replay_dm!`) that executes a traced DAG (the materialize half of the
# stream≡materialized round-trip + the channel-pass Choi laws). Included LAST: it
# overrides `apply!`/`allocate!`/`trace_wire!`/`teardown!` and dispatches the cast/
# cases seams that M3/M6/cases.jl forward-reference — all resolved at call time.
include("context/tracing.jl")

# --- M9: QMod, the in-place-Perm compiler, mulmod!, shor_order (bead 8oo9) ---
# `types/qmod.jl` (the ℤ_N register handle, static modulus F24) needs the M2
# context layer + kernel `X`. `bennett/inplace.jl` (the in-place-Perm compiler
# contract: verify_inverse_pair / compile_inplace_perm / CompiledInplacePerm, its
# private `_compiled_inplace_perm` choke point) needs `CompiledOracle` +
# `_BENNETT_BACKEND` (M7), `Perm`/`MCX`/`PERM_EQ_MAXW` (M1), `_act!`/`_free_clean!`
# (M5/M7), `PortID`/`PermClean` (M8). `library/modular.jl` (`mulmod!` + the
# registered `FullSpaceMulProof`) needs both. `library/shor.jl` (`shor_order` +
# `_shor_phase_sample`) needs `QMod`/`mulmod!`/`when`/`region`/`BigInt(dual)`.
include("types/qmod.jl")
include("bennett/inplace.jl")
include("library/modular.jl")
include("library/shor.jl")

# --- M10: library HOFs — Grover (amplify/find), phase estimation, Trotter
# (bead Sturm.jl-8fo5) --------------------------------------------------------
# `library/grover.jl` (`amplify`/`find`/`interfere!` — nested-`when` + `not!(dual)`
# multi-ctrl Z, `superpose!`/`interfere!` H^⊗n materialization, Bennett-bridge
# marker); `library/qpe.jl` (`phase_estimate` — the §7.7 phase-sample structure with
# a caller unitary, `Int(dual(k))` readout). All reuse shipped surface/kernel verbs
# (`when`, `dual`, `not!`, `superpose!`, `oracle`, `region`, `_act!`, kernel U2
# values) — no new surface construct, no duplicated primitive.
include("library/grover.jl")
include("library/qpe.jl")

# --- M12: Hamiltonian-simulation strategy layer (beads Sturm.jl-elsf/8yzf) ---
# `library/evolve/` supersedes the M10 single-file `evolve.jl` (design:
# docs/design/m12-synthesis.md, S14 layout). Dependency order: symplectic Pauli
# algebra → PauliTerm + canonical PauliSum{W} (+ model families) → Suzuki stage
# scales + sweep/outer-slot builders → bounds (exact α_comm DP, Trotter/qDrift/
# composite step + error rules, BoundReport, THE diamond↔spectral ×2 pin) →
# strategy descriptors → plans (plan_evolution / trajectory / exp_count for
# Trotter + QDrift + Composite) → Auto dispatch (evolve_plan, S8 merge) →
# executor + `evolve!` entry (S3/S9/S10 as ruled). bench/ is bead Sturm.jl-gmx0.
include("library/evolve/pauli.jl")
include("library/evolve/hamiltonian.jl")
include("library/evolve/suzuki.jl")
include("library/evolve/bounds.jl")
include("library/evolve/strategies.jl")
include("library/evolve/plans.jl")
include("library/evolve/auto.jl")
include("library/evolve/evolve.jl")

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

# --- Surface classical control (exported; PRD-v2 §3.6/§3.8, M8 i4ri) ---------
# `cases`/`@cases` (surface construct 6): classical branching on outcomes. The
# outcome TOKENS (`ClassicalBit`/`ClassicalWord`), the `select`/`shots`/`discard!`
# library HOFs, and `ClassicalTable`/width helpers are kernel/library `public`
# (reachable as `Sturm.select`, never `using`-dumped) — `select`/`shots` are
# library, NOT an 8th surface construct.
export cases, @cases

# --- Surface M9 capstones (exported; PRD-v2 §3.1/§3.4/§7.7, M9) ---------------
# `QMod` (the ℤ_N register + preparation cast), the registered in-place action
# `mulmod!`, and the order-finding entry `shor_order`. The in-place-Perm compiler
# machinery, the exceptions, the CF/LCM helpers, and `_shor_phase_sample` are
# kernel/library `public` (reachable as `Sturm.…`, never `using`-dumped).
export QMod, mulmod!, shor_order

# --- Surface M10 library HOFs (exported; PRD-v2 §5, M10) ----------------------
# The physicist-facing HOFs of §5, exported to match the M9 library verbs
# (`mulmod!`/`shor_order`): `amplify`/`find` (Grover), `phase_estimate` (QPE),
# `evolve!` (Trotter Hamiltonian simulation), `interfere!` (the DJ/BV closing
# Walsh–Hadamard). The internal builders (`grover_iterations`, `_mcz_all_ones!`,
# `PauliTerm`) are kernel/library `public` — reachable as `Sturm.…`, not dumped.
export amplify, find, phase_estimate, evolve!, interfere!

# --- Surface M12 strategy vocabulary (exported; PRD-v2 §5, M12 phase 1) -------
# The `evolve!` strategy descriptors (synthesis S2: strategies carry resources;
# ε is an `evolve!` kwarg). Exported like `amplify`: they ARE the user-facing
# vocabulary of the HOF signature. The plans/bounds machinery stays `public`.
export Trotter, QDrift, Composite, Auto

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
    OracleQuery, CompiledOracle,
    # M9 QMod + in-place-Perm compiler + order finding (kernel/library `public`)
    modulus, _modwidth,
    verify_inverse_pair, compile_inplace_perm, VerifiedInversePair,
    CompiledInplacePerm, AbstractInplaceProof, FullSpaceMulProof,
    InverseContractError, permclean_cert,
    NonCoprimeBaseError, OrderFindingFailure,
    _cf_denominator, _minimize_order, _shor_phase_sample, _ideal_mulmod_perm,
    # M10 library HOF internals (kernel/library `public`, reachable as `Sturm.…`)
    grover_iterations, _mcz_all_ones!, _grover_diffuse!, _phase_mark_oracle!,
    PauliTerm, _pauli_exp!,
    # M12 hamsim machinery (library `public`, reachable as `Sturm.…`, not
    # dumped; bead Sturm.jl-elsf): symplectic Pauli algebra, canonical
    # Hamiltonian value, Suzuki scales, exact α_comm + step/error bounds
    # (BoundReport), plans, and the model families.
    PauliWord, PauliSum, letter_at, commutes, mulword, mulword_word,
    is_identity, nterms, iscommuting,
    suzuki_stage_scales, suzuki_sweep_count, SUZUKI_MAX_P,
    alpha_comm, alpha_comm_pairs, alpha_comm_cross, AlphaCommBlowup,
    ALPHA_MAXWORDS_DEFAULT, trotter_steps, trotter_error_bound, BoundReport,
    EvolveAlg, EvolvePlan, TrotterPlan, plan_evolution, trajectory, exp_count,
    ising_chain, heisenberg_chain, powerlaw_chain,
    # M12 phase 2 (bead Sturm.jl-8yzf): randomized plans + resource rules +
    # Auto dispatch (all library `public`, reachable as `Sturm.…`, not dumped)
    QDriftPlan, CompositePlan, qdrift_samples, qdrift_error_bound,
    composite_steps, composite_error_bound, composite_nb, composite_k,
    composite_outer_slots, evolve_plan, EvolveChoice, PlanRow,
    AUTO_COMMUTING_GATE

# --- M8 channel IR (bead Sturm.jl-szx1; kernel `public`, not exported) -------
# The effect-typed `ChannelDAG` (NOT a process value), its port vocabulary and
# effect nodes, the certified `UnitaryBlock` process value + `certify` sealer, the
# closed `CleanCert` constructor set, and the mutable `DAGBuilder` tooling. All
# reachable as `Sturm.certify`, `Sturm.UnitaryBlock`, …, never `using`-dumped.
public ChannelDAG, UnitaryBlock, certify, denoted_full, boundary,
    PortID, Port, PortKind, QuantumPort, ClassicalPort, is_quantum, portwidth,
    Node, ApplyN, AllocN, TraceN, MeasureN, CasesN, NoiseN, KrausFamily,
    is_barrier, has_barrier,
    CleanCert, NoAncilla, PermClean, MatchedPair, SeqCert, ParCert, AdjointCert, XportCert,
    DAGBuilder, input!, alloc!, apply_node!, trace!, measure!, noise!, freeze

# --- M8 pass frameworks (parts 5–6; kernel `public`, not exported) -----------
# The two pass abstractions + `apply_pass`, the registered representative-preserving
# unitary passes and `PASS_REGISTRY`, the channel passes, and the `within`
# combinator (a `public` kernel/library API — NOT an 8th surface construct, TR3).
public UnitaryPass, ChannelPass, apply_pass, PASS_REGISTRY,
    Fuse1qPass, ViewFusionPass, ReassocPass,
    FuseUnitaryRunsPass, DeferMeasurementPass, DeadRecordEliminationPass, within

# --- M8 i4ri classical-control tokens + library (kernel/library `public`) ----
# The measurement-record tokens and the T2/T3 finite classical SSA + trajectory
# HOF. `cases`/`@cases` are the exported surface; these are the token vocabulary
# (Ruling D returns) and the library multiplexer/shot/lifetime helpers.
public ClassicalBit, ClassicalWord, ClassicalToken, ClassicalTable,
    select, shots, discard!, width, zext, truncate_word,
    # M8 TRACING half: the compiler context + trace/replay + pre-flight lint
    TracingContext, trace, trace_nonportable

end # module Sturm
