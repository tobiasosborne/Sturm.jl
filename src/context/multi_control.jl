# Multi-controlled gate decomposition shared by EagerContext and
# DensityMatrixContext. Both contexts own an Orkan state handle plus a
# control stack; Orkan's gate functions (ry, rz, cx, ccx) dispatch on the
# state type at the C level (ORKAN_PURE / ORKAN_MIXED_PACKED), so the same
# Toffoli cascade computes U |ψ⟩ on a statevector and U ρ U† on a density
# matrix with no code duplication.
#
# Refs:
#   - Nielsen & Chuang §4.3, Eq. (4.6)–(4.7) — ABC decomposition of controlled
#     rotations. Local derivation: docs/physics/nielsen_chuang_4.3.md.
#   - Barenco et al. (1995) Phys. Rev. A 52(5):3457 — Lemma 7.2, Toffoli
#     cascade for n-controlled gates with n−1 workspace qubits. Self-contained
#     derivation (classical-basis + linearity + density-matrix extension):
#     docs/physics/toffoli_cascade.md.

const _MCTX = Union{EagerContext, DensityMatrixContext}

# ── Controlled rotations (1 control) ────────────────────────────────────────

# C-Ry(θ) = Ry(θ/2) · CX · Ry(−θ/2) · CX
function _controlled_ry!(ctx::_MCTX, ctrl_wire::WireID, target_wire::WireID, angle::Real)
    ctrl = _resolve(ctx, ctrl_wire)
    tgt  = _resolve(ctx, target_wire)
    orkan_ry!(ctx.orkan.raw, tgt,  angle / 2)
    orkan_cx!(ctx.orkan.raw, ctrl, tgt)
    orkan_ry!(ctx.orkan.raw, tgt, -angle / 2)
    orkan_cx!(ctx.orkan.raw, ctrl, tgt)
end

# C-Rz(θ) = Rz(θ/2) · CX · Rz(−θ/2) · CX
function _controlled_rz!(ctx::_MCTX, ctrl_wire::WireID, target_wire::WireID, angle::Real)
    ctrl = _resolve(ctx, ctrl_wire)
    tgt  = _resolve(ctx, target_wire)
    orkan_rz!(ctx.orkan.raw, tgt,  angle / 2)
    orkan_cx!(ctx.orkan.raw, ctrl, tgt)
    orkan_rz!(ctx.orkan.raw, tgt, -angle / 2)
    orkan_cx!(ctx.orkan.raw, ctrl, tgt)
end

# ── Toffoli cascade (N ≥ 2 controls) ────────────────────────────────────────
#
# AND-reduce N controls into a single workspace qubit via CCX ladder:
#   CCX(c[1], c[2],  ws[1])
#   CCX(ws[1], c[3], ws[2])
#   …
#   CCX(ws[N−2], c[N], ws[N−1])
# The final ws[N−1] = ⋀ c[i]. Apply the single-controlled gate with ws[N−1]
# as the control, then run the cascade in reverse to uncompute the workspace
# (each CCX is its own inverse).
#
# Cost: 2(N−1) Toffoli + one single-controlled gate; N−1 workspace qubits.

function _toffoli_cascade_forward!(ctx::_MCTX, controls::Vector{WireID},
                                   workspace::Vector{WireID})
    nc = length(controls)
    c1 = _resolve(ctx, controls[1])
    c2 = _resolve(ctx, controls[2])
    w1 = _resolve(ctx, workspace[1])
    orkan_ccx!(ctx.orkan.raw, c1, c2, w1)
    for k in 2:nc-1
        wp = _resolve(ctx, workspace[k - 1])
        ck = _resolve(ctx, controls[k + 1])
        wk = _resolve(ctx, workspace[k])
        orkan_ccx!(ctx.orkan.raw, wp, ck, wk)
    end
end

function _toffoli_cascade_reverse!(ctx::_MCTX, controls::Vector{WireID},
                                   workspace::Vector{WireID})
    nc = length(controls)
    for k in nc-1:-1:2
        wp = _resolve(ctx, workspace[k - 1])
        ck = _resolve(ctx, controls[k + 1])
        wk = _resolve(ctx, workspace[k])
        orkan_ccx!(ctx.orkan.raw, wp, ck, wk)
    end
    c1 = _resolve(ctx, controls[1])
    c2 = _resolve(ctx, controls[2])
    w1 = _resolve(ctx, workspace[1])
    orkan_ccx!(ctx.orkan.raw, c1, c2, w1)
end

function _multi_controlled_gate!(ctx::_MCTX, target_wire::WireID,
                                 angle::Real, single_ctrl_fn!::Function)
    controls = copy(ctx.control_stack)
    nc = length(controls)
    nc >= 2 || error("_multi_controlled_gate!: need ≥2 controls, got $nc")

    workspace = WireID[allocate!(ctx) for _ in 1:(nc - 1)]
    try
        _toffoli_cascade_forward!(ctx, controls, workspace)
        single_ctrl_fn!(ctx, workspace[end], target_wire, angle)
        _toffoli_cascade_reverse!(ctx, controls, workspace)
    finally
        for ws in workspace
            deallocate!(ctx, ws)
        end
    end
end

function _multi_controlled_cx!(ctx::_MCTX, cx_ctrl_wire::WireID, target_wire::WireID)
    controls = copy(ctx.control_stack)
    nc = length(controls)
    nc >= 2 || error("_multi_controlled_cx!: need ≥2 stack controls, got $nc")

    workspace = WireID[allocate!(ctx) for _ in 1:(nc - 1)]
    try
        _toffoli_cascade_forward!(ctx, controls, workspace)
        ws_out  = _resolve(ctx, workspace[end])
        cx_ctrl = _resolve(ctx, cx_ctrl_wire)
        tgt     = _resolve(ctx, target_wire)
        orkan_ccx!(ctx.orkan.raw, ws_out, cx_ctrl, tgt)
        _toffoli_cascade_reverse!(ctx, controls, workspace)
    finally
        for ws in workspace
            deallocate!(ctx, ws)
        end
    end
end
