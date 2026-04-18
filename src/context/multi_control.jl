# Multi-controlled gate decomposition — works on ANY AbstractContext.
#
# The cascade routes through the PUBLIC `apply_ry!`/`apply_rz!`/`apply_cx!`/
# `apply_ccx!` API, wrapped in `with_empty_controls` to prevent infinite
# recursion when a single-controlled decomposition is called from inside
# `apply_ry!` at depth 1. Each context's `apply_*!` then handles the
# unconditional (nc=0) case in whatever way is cheapest:
#
#   - EagerContext / DensityMatrixContext: direct `orkan_*!` calls (Orkan
#     gate ABI dispatches on state type internally, so `ccx` works as
#     `UρU†` on MIXED states with no special handling).
#   - TracingContext: emits standard `RyNode`/`RzNode`/`CXNode` with the
#     explicit control inlined — no new `DeepCtrlNode` type needed because
#     the cascade fully lowers every deep-controlled op to depth-≤2 nodes.
#
# Refs:
#   - Nielsen & Chuang §4.3, Eq. (4.6)–(4.7) — ABC decomposition of
#     controlled rotations. Local: docs/physics/nielsen_chuang_4.3.md.
#   - Barenco et al. (1995) Phys. Rev. A 52(5):3457, Lemma 7.2 — Toffoli
#     cascade for N-controlled gates with N−1 workspace qubits. Self-
#     contained derivation: docs/physics/toffoli_cascade.md.

# ── Controlled rotations (1 explicit control) ───────────────────────────────

"""
    _controlled_ry!(ctx, ctrl_wire, target_wire, angle)

Single-controlled Ry via NC&C ABC: `C-Ry(θ) = Ry(θ/2)·CX·Ry(−θ/2)·CX`.

Runs with an EMPTY stack so that inner `apply_ry!` / `apply_cx!` calls hit
their `nc=0` fast paths (no recursive controlled-rotation expansion). The
caller-supplied `ctrl_wire` is the single active control.
"""
function _controlled_ry!(ctx::AbstractContext, ctrl_wire::WireID,
                         target_wire::WireID, angle::Real)
    with_empty_controls(ctx) do
        apply_ry!(ctx, target_wire,  angle / 2)
        apply_cx!(ctx, ctrl_wire, target_wire)
        apply_ry!(ctx, target_wire, -angle / 2)
        apply_cx!(ctx, ctrl_wire, target_wire)
    end
end

"""
    _controlled_rz!(ctx, ctrl_wire, target_wire, angle)

Single-controlled Rz via NC&C ABC: `C-Rz(θ) = Rz(θ/2)·CX·Rz(−θ/2)·CX`.
See `_controlled_ry!` for the empty-stack rationale.
"""
function _controlled_rz!(ctx::AbstractContext, ctrl_wire::WireID,
                         target_wire::WireID, angle::Real)
    with_empty_controls(ctx) do
        apply_rz!(ctx, target_wire,  angle / 2)
        apply_cx!(ctx, ctrl_wire, target_wire)
        apply_rz!(ctx, target_wire, -angle / 2)
        apply_cx!(ctx, ctrl_wire, target_wire)
    end
end

# ── Toffoli cascade (N ≥ 2 controls) ────────────────────────────────────────
#
# AND-reduce N controls onto workspace[N−1] via a CCX ladder. Each CCX runs
# with the stack empty (the caller has already cleared it), so tracing
# emits plain 2-control CXNodes and eager/DM dispatch straight to Orkan's
# ccx.
#
# Preconditions: `controls` has length nc ≥ 2; `workspace` has length
# nc − 1; all workspace wires start in |0⟩.

function _toffoli_cascade_forward!(ctx::AbstractContext, controls::Vector{WireID},
                                   workspace::Vector{WireID})
    nc = length(controls)
    apply_ccx!(ctx, controls[1], controls[2], workspace[1])
    for k in 2:nc-1
        apply_ccx!(ctx, workspace[k - 1], controls[k + 1], workspace[k])
    end
end

function _toffoli_cascade_reverse!(ctx::AbstractContext, controls::Vector{WireID},
                                   workspace::Vector{WireID})
    nc = length(controls)
    for k in nc-1:-1:2
        apply_ccx!(ctx, workspace[k - 1], controls[k + 1], workspace[k])
    end
    apply_ccx!(ctx, controls[1], controls[2], workspace[1])
end

function _multi_controlled_gate!(ctx::AbstractContext, target_wire::WireID,
                                 angle::Real, single_ctrl_fn!::Function)
    saved = current_controls(ctx)
    nc = length(saved)
    nc >= 2 || error("_multi_controlled_gate!: need ≥2 controls, got $nc")

    # Workspace must be allocated BEFORE clearing the stack, because
    # allocate!() on TracingContext emits a fresh WireID unaffected by
    # controls, but on Eager/DM it touches Orkan state and should be
    # unambiguously unconditional. We immediately enter with_empty_controls
    # so every downstream `apply_*!` sees nc=0.
    workspace = WireID[allocate!(ctx) for _ in 1:(nc - 1)]
    try
        with_empty_controls(ctx) do
            _toffoli_cascade_forward!(ctx, saved, workspace)
            single_ctrl_fn!(ctx, workspace[end], target_wire, angle)
            _toffoli_cascade_reverse!(ctx, saved, workspace)
        end
    finally
        for ws in workspace
            deallocate!(ctx, ws)
        end
    end
end

function _multi_controlled_cx!(ctx::AbstractContext, cx_ctrl_wire::WireID,
                               target_wire::WireID)
    saved = current_controls(ctx)
    nc = length(saved)
    nc >= 2 || error("_multi_controlled_cx!: need ≥2 stack controls, got $nc")

    workspace = WireID[allocate!(ctx) for _ in 1:(nc - 1)]
    try
        with_empty_controls(ctx) do
            _toffoli_cascade_forward!(ctx, saved, workspace)
            # CCX(workspace_out, cx_ctrl, target) — Toffoli at 2 controls,
            # one from the reduced workspace, one the explicit cx-control.
            apply_ccx!(ctx, workspace[end], cx_ctrl_wire, target_wire)
            _toffoli_cascade_reverse!(ctx, saved, workspace)
        end
    finally
        for ws in workspace
            deallocate!(ctx, ws)
        end
    end
end
