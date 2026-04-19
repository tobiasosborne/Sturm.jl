# di9 grind — forward+inverse X-basis probes.
#
# Theory: for ANY unitary U with NO global phase on the ctrl=|1⟩ branch,
#   when(ctrl) do U end; when(ctrl) do U⁻¹ end    ≡ identity ⊗ identity_on_target
# so ctrl is left as pure |+⟩. Measuring X-basis after should give 0%.
#
# If U or U⁻¹ has a global phase e^(iα) on some branch that doesn't cancel,
# ctrl acquires relative phase on |1⟩, leaking at rate sin²(α/2).
#
# Unlike probe_mulmod_phase.jl, this isolates GLOBAL PHASE bugs from the
# inherent ctrl-target entanglement that ctrl-U_a produces on non-eigenstate x.

const T0 = time_ns()
_log(s) = (println(stderr, "[", round((time_ns()-T0)/1e6; digits=1), " ms] ", s); flush(stderr))
_log("ENTER")
using Sturm
using Sturm: add_qft!, sub_qft!, modadd!, mulmod_beauregard!,
             superpose!, interfere!, discard!
_log("using Sturm OK")

function leak_rate(build!::Function; n_shots::Int=200)
    n_true = 0
    for _ in 1:n_shots
        @context EagerContext() begin
            ctrl = QBool(1/2)
            build!(ctrl)
            ctrl.θ -= π/2
            if Bool(ctrl); n_true += 1; end
        end
    end
    return n_true / n_shots
end

# ── Stage I: when(ctrl) add_qft(y, a); sub_qft(y, a) ─────────────────
# y returns to initial Fourier state on both branches. Phase-neutral test.
_log("=== STAGE I: when(ctrl) add_qft; sub_qft  (identity on y) ===")
let
    for (L, a, v) in [(1,1,0), (2,2,0), (3,3,1), (4,7,3), (4,2,5), (5,2,3), (5,4,7)]
        r = leak_rate(ctrl -> begin
            y = QInt{L+1}(v)
            superpose!(y)
            when(ctrl) do
                add_qft!(y, a)
                sub_qft!(y, a)
            end
            interfere!(y)
            discard!(y)
        end)
        tag = r > 0.05 ? "  ⚠ LEAK" : ""
        _log("  Stage I  L=$L a=$a v=$v  leak = $(round(r*100;digits=1))%$tag")
    end
end

# ── Stage II: modadd ∘ inverse modadd (singly controlled) ────────────
# modadd(y, a) · modadd(y, N-a) on ctrl=|1⟩ returns y to initial.
_log("=== STAGE II: ctrls=(c,) modadd(a) ∘ modadd(N-a) ===")
let
    for (L, N, a, b) in [(2,3,2,0), (3,5,2,0), (3,5,3,1), (3,5,4,3), (4,15,7,3), (4,15,2,5), (5,21,2,3), (5,21,4,7)]
        r = leak_rate(ctrl -> begin
            y = QInt{L+1}(b)
            anc = QBool(0)
            superpose!(y)
            modadd!(y, anc, a, N; ctrls=(ctrl,))
            modadd!(y, anc, mod(N - a, N), N; ctrls=(ctrl,))
            interfere!(y)
            discard!(y); discard!(anc)
        end)
        tag = r > 0.05 ? "  ⚠ LEAK" : ""
        _log("  Stage II  L=$L N=$N a=$a b=$b  leak = $(round(r*100;digits=1))%$tag")
    end
end

# ── Stage III: modadd ∘ inverse modadd (doubly controlled) ───────────
_log("=== STAGE III: ctrls=(c, |1⟩) modadd(a) ∘ modadd(N-a) ===")
let
    for (L, N, a, b) in [(3,5,2,1), (4,15,7,3), (4,15,2,5), (5,21,2,3), (5,21,4,7)]
        r = leak_rate(ctrl -> begin
            xj = QBool(1)
            y = QInt{L+1}(b)
            anc = QBool(0)
            superpose!(y)
            modadd!(y, anc, a, N; ctrls=(ctrl, xj))
            modadd!(y, anc, mod(N - a, N), N; ctrls=(ctrl, xj))
            interfere!(y)
            discard!(y); discard!(anc); discard!(xj)
        end)
        tag = r > 0.05 ? "  ⚠ LEAK" : ""
        _log("  Stage III  L=$L N=$N a=$a b=$b  leak = $(round(r*100;digits=1))%$tag")
    end
end

# ── Stage IV: mulmod ∘ inverse mulmod ────────────────────────────────
# U_a · U_{a⁻¹} = I on x, on both ctrl branches.
_log("=== STAGE IV: mulmod(x, a) ∘ mulmod(x, a⁻¹) ===")
let
    for (L, N, a, x0) in [(3,5,2,1), (3,5,2,3), (4,15,7,1), (4,15,7,11), (5,21,2,1), (5,21,2,11), (5,21,4,5)]
        a_inv = invmod(a, N)
        r = leak_rate(ctrl -> begin
            x = QInt{L}(x0)
            mulmod_beauregard!(x, a, N, ctrl)
            mulmod_beauregard!(x, a_inv, N, ctrl)
            discard!(x)
        end)
        tag = r > 0.05 ? "  ⚠ LEAK" : ""
        _log("  Stage IV  L=$L N=$N a=$a x0=$x0  leak = $(round(r*100;digits=1))%$tag")
    end
end

_log("EXIT")
