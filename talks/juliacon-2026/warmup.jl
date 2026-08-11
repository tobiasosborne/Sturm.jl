# SPDX-License-Identifier: AGPL-3.0-only
#
# warmup.jl — backstage warm-up for "Given an Oracle for f" (JuliaCon 2026)
#
# WHAT THIS IS: every JIT/precompile/LLVM cost the live demo will ever pay,
# paid HERE, backstage, as throwaway calls — never on stage. It also
# `Base.include`s (well, defines top-level in Main) every helper function
# the four live beats call, so that after this script runs, the ONLY thing
# left to do is retype the nine live command lines once (see the printed
# cheat-sheet at the end) so they land in REPL history for ↑+Enter.
#
# THIS SCRIPT DOES NOT AND CANNOT POPULATE REPL HISTORY. `include()` runs
# code; it does not feed lines through the interactive readline history
# mechanism. That is why the backstage procedure has a manual retype step
# AFTER this script finishes — see DEMO-RUNBOOK.md §(b).
#
# USAGE (from a Julia REPL, NOT `julia warmup.jl` — you want the resulting
# session, including bindings, still open afterwards):
#
#   $ export OMP_NUM_THREADS=16
#   $ export LIBORKAN_PATH=/home/tobiasosborne/Projects/orkan/cmake-build-release/src/liborkan.so
#   $ julia --project=talks/juliacon-2026/demoenv
#   julia> include("talks/juliacon-2026/warmup.jl")
#
# Expected total wall time: ~30 s (dominated by the first `oracle()` call,
# ~20.8 s cold — this is normal, do not interrupt it).

using Printf

# ─── Stage 0: environment — FAIL LOUD, not silently wrong ──────────────────
#
# LIBORKAN_PATH is read in Sturm's `__init__` (src/orkan/ffi.jl), i.e. at
# `using Sturm` time — setting it AFTER the fact does nothing for this
# session. If either var is wrong, refuse to proceed rather than run an
# uncapped/misconfigured demo in front of an audience.

const EXPECTED_OMP = "16"
const EXPECTED_LIBORKAN = "/home/tobiasosborne/Projects/orkan/cmake-build-release/src/liborkan.so"

println("="^72)
println("JuliaCon 2026 — \"Given an Oracle for f\" — backstage warm-up")
println("="^72)
flush(stdout)

let omp = get(ENV, "OMP_NUM_THREADS", "")
    if omp != EXPECTED_OMP
        error("""
        OMP_NUM_THREADS is \"$omp\" (want \"$EXPECTED_OMP\"). Set it BEFORE \
        starting julia and restart:
          export OMP_NUM_THREADS=16
        Uncapped Orkan uses ~56 cores and hammers the machine.
        """)
    end
    println("  [env] OMP_NUM_THREADS = $omp  ✅")
    flush(stdout)
end

let lib = get(ENV, "LIBORKAN_PATH", "")
    if lib != EXPECTED_LIBORKAN
        error("""
        LIBORKAN_PATH is \"$lib\" (want \"$EXPECTED_LIBORKAN\"). It is read \
        in Sturm's __init__ — setting it now, after `using Sturm` has \
        already run in this session, has no effect. Fix it and start a \
        FRESH julia process:
          export LIBORKAN_PATH=$EXPECTED_LIBORKAN
        """)
    end
    isfile(lib) || error("""
    LIBORKAN_PATH=$lib is set but the file does not exist. Build orkan:
      cd ../orkan && cmake --preset release && cmake --build cmake-build-release
    """)
    println("  [env] LIBORKAN_PATH = $lib  ✅")
    flush(stdout)
end
println()
flush(stdout)

# ─── stage() — eager-flushed, per-stage timing ─────────────────────────────

"""
    stage(name) do ... end

Run a warm-up step, print `name`, flush BEFORE running (so the terminal
never sits blank while something slow happens), then print elapsed ms.
"""
function stage(f, name::AbstractString)
    print(rpad("→ " * name, 58))
    flush(stdout)
    t0 = time_ns()
    val = f()
    dt = (time_ns() - t0) / 1e6
    @printf("%9.1f ms  ✅\n", dt)
    flush(stdout)
    return val
end

# ─── Stage 1: load packages ─────────────────────────────────────────────────

stage("using Sturm") do
    @eval using Sturm
end

stage("using Bennett") do
    @eval using Bennett
end
println()
flush(stdout)

# ─── Stage 2: define everything the live beats and Q&A need ────────────────
#
# These are the SAME names/definitions the live commands will (re)use on
# stage — transcribed verbatim from Sturm-PRD-v2.md §7.4 (deutsch_jozsa),
# test/test_m4_views.jl:25-34 (teleport), and DECK-SPEC.md (f, dj_const,
# dj_bal). `f` gets RETYPED live at s2/s16 (harmless method redefinition);
# dj_const/dj_bal/deutsch_jozsa/teleport/teleport_ok are defined ONCE here
# and never retyped — the live s13/s12 commands just call them by name.

stage("define f, dj_const, dj_bal, deutsch_jozsa, teleport, teleport_ok") do
    @eval begin
        # s2 / s16 — "every Julia function is already a quantum gate"
        f(x::Int8) = x*x + Int8(3)*x + Int8(1)

        # s13 — Deutsch–Jozsa predicates. GENERIC (no ::Int8/::UInt8 on the
        # argument) — the bridge compiles at UInt8; a typed signature fails
        # loudly at `oracle()`. Verbatim from test/test_m7_bennett.jl:39-40.
        dj_const(x) = false
        dj_bal(x)   = (x & 0x01) == 0x01

        # s13 — verbatim Sturm-PRD-v2.md §7.4.
        function deutsch_jozsa(f, ::Val{N}) where {N}
            x = QInt{N}(0)
            superpose!(x)            # library materialization: H^⊗N on |0⟩
            b = minus()              # |−⟩ literal: QBool(0.5, π)

            b ⊻= oracle(f, x)        # ordinary Julia f, compiled by Bennett;
                                      # kickback on x

            return Int(dual(x)) == 0 # Fourier-sample x; all-zero ⇔ constant
        end

        # s12 — verbatim test/test_m4_views.jl:25-34 (PRD §7.1).
        function teleport(ψ::QBool)
            b = QBool(0.5)                # a fair quantum coin
            c = false ⊻ b                 # Bell pair
            b ⊻= ψ                        # correlate payload
            m_phase = Bool(dual(ψ))       # conjugate-basis readout (consumes ψ)
            m_value = Bool(b)
            m_value && not!(c)            # ordinary conditionals,
            m_phase && not!(dual(c))      # one in the dual view
            return c
        end

        # s12 shadow/optional-live beat: |+⟩ probe, X-basis (dual) readout —
        # the wm28-class probe (test_m4_views.jl:209): expect == false, always.
        teleport_ok() = Sturm.eager(4) do _
            Bool(dual(teleport(QBool(0.5)))) == false
        end
    end
    nothing
end
println()
flush(stdout)

# ─── Stage 3: pay every hidden JIT/compile cost, backstage ─────────────────
#
# These calls are NOT what gets typed live — they exercise the SAME code
# paths under throwaway bindings (`_warm*`) so Bennett's/Sturm's compiler
# machinery, LLVM.jl, and Orkan's ccall boundary are all hot before the
# presenter ever types the real thing.

_warmc = stage("warm: reversible_compile(f, Int8)  [pays s2's live command]") do
    Bennett.reversible_compile(f, Int8)
end

stage("warm: simulate(_warmc, Int8(5))  [FIRST simulate call — ~2.8s JIT expected]") do
    Bennett.simulate(_warmc, Int8(5))
end

stage("warm: verify_reversibility(_warmc)") do
    Bennett.verify_reversibility(_warmc)
end

_warmc1 = stage("warm: reversible_compile(x+1, UInt8; bit_width=3, ...)  [pays s7]") do
    Bennett.reversible_compile(x -> x + UInt8(1), UInt8; bit_width=3, add=:ripple,
                                fold_constants=true)
end

stage("warm: gs[14:23] == reverse(gs[1:10])  [mirror equality]") do
    gs = _warmc1.gates
    gs[14:23] == reverse(gs[1:10])
end

_warmcc = stage("warm: controlled(reversible_compile(!x, Bool))  [pays s11]") do
    Bennett.controlled(Bennett.reversible_compile(x -> !x, Bool))
end

stage("warm: simulate(_warmcc, true, false) / (false, false)") do
    (Bennett.simulate(_warmcc, true, false), Bennett.simulate(_warmcc, false, false))
end
println()
flush(stdout)

println("  ⚠ next step calls oracle() for the FIRST time this session.")
println("    Measured cold: ~20.8 s. This is EXPECTED — do not interrupt.")
flush(stdout)

stage("warm: FIRST oracle() call via deutsch_jozsa(dj_const, Val(2))  [~20.8s COLD]") do
    Sturm.eager(18) do _
        deutsch_jozsa(dj_const, Val(2))
    end
end

stage("warm: deutsch_jozsa(dj_bal, Val(2))  [now warm, pays s13's 2nd line]") do
    Sturm.eager(18) do _
        deutsch_jozsa(dj_bal, Val(2))
    end
end

stage("warm: teleport 200-shot probe  [optional s12 live beat]") do
    count(_ -> teleport_ok(), 1:200)
end
println()
flush(stdout)

# ─── Stage 4: cheat-sheet — retype these NINE lines once, in this order ────
#
# ↑ recall on stage is fastest and safest if you now retype every live line
# ONCE, in REVERSE stage order (last-used first). Reason: REPL history is
# LIFO — the LAST thing you type is the FIRST thing a single ↑ recalls.
# Typing in reverse stage order means the number of ↑ presses needed at
# each beat is small, fixed, and STRICTLY INCREASING through the talk:
#
#   s2  line 1 (f def)                 → 1×↑
#   s2  line 2 (c = reversible_compile) → 2×↑
#   s7  line 1 (c1 = reversible_compile) → 3×↑
#   s7  line 2 (gs = ...; gs[...]==...)  → 4×↑
#   s11 line 1 (cc = controlled(...))    → 5×↑
#   s11 line 2 (simulate(cc,true,false)) → 6×↑
#   s11 line 3 (simulate(cc,false,false))→ 7×↑
#   s13 line 1 (deutsch_jozsa dj_const)  → 8×↑
#   s13 line 2 (deutsch_jozsa dj_bal)    → 9×↑
#
# Practice the exact ↑-count backstage until it's reflex. See
# DEMO-RUNBOOK.md §(b) for the full retype procedure and §(c) for the
# live-beat table these lines feed.

println("="^72)
println("STAGE READY ✅ — all JIT paid, all helpers defined.")
println("="^72)
println()
println("Now RETYPE these 9 lines, ONE AT A TIME, in this exact (REVERSE")
println("stage) order, pressing Enter after each. This is what populates")
println("REPL history for ↑+Enter on stage — see DEMO-RUNBOOK.md §(b).")
println()

for line in [
    "Sturm.eager(18) do _; deutsch_jozsa(dj_bal, Val(2)); end",
    "Sturm.eager(18) do _; deutsch_jozsa(dj_const, Val(2)); end",
    "simulate(cc, false, false)",
    "simulate(cc, true, false)",
    "cc = controlled(reversible_compile(x -> !x, Bool))",
    "gs = c1.gates; gs[14:23] == reverse(gs[1:10])",
    "c1 = reversible_compile(x -> x + UInt8(1), UInt8; bit_width=3, add=:ripple, fold_constants=true)",
    "c = reversible_compile(f, Int8)",
    "f(x::Int8) = x*x + Int8(3)*x + Int8(1)",
]
    println("    ", line)
end
println()
println("Then Ctrl-L to clear the visible screen (history is unaffected).")
println("Then open ../talk.html in the browser and you are ready to walk on.")
flush(stdout)
