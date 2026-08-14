# SPDX-License-Identifier: AGPL-3.0-only
#
# warmup.jl: backstage warm-up for "Quantum programming in ordinary Julia" (JuliaCon 2026)
#
# WHAT THIS IS: every JIT/precompile/LLVM cost the live demo will ever pay,
# paid HERE, backstage, as throwaway calls, never on stage. It also
# `Base.include`s (well, defines top-level in Main) every helper function
# the four live beats call, so that after this script runs, the ONLY thing
# left to do is retype the nine live command lines once (see the printed
# cheat-sheet at the end) so they land in REPL history for PREFIX recall
# (type 2–3 characters, press ↑).
#
# THIS SCRIPT DOES NOT AND CANNOT POPULATE REPL HISTORY. `include()` runs
# code; it does not feed lines through the interactive readline history
# mechanism. That is why the backstage procedure has a manual retype step
# AFTER this script finishes, see DEMO-RUNBOOK.md §(b).
#
# USAGE (from a Julia REPL, NOT `julia warmup.jl`, you want the resulting
# session, including bindings, still open afterwards):
#
#   $ export OMP_NUM_THREADS=16
#   $ export LIBORKAN_PATH=/home/tobias/Projects/orkan/cmake-build-release/src/liborkan.so
#   $ julia --project=talks/juliacon-2026/demoenv
#   julia> include("talks/juliacon-2026/warmup.jl")
#
# Expected total wall time: ~30 s (dominated by the first `oracle()` call,
# ~20.8 s cold, this is normal, do not interrupt it).

using Printf

# ─── Stage 0: environment. FAIL LOUD, not silently wrong ──────────────────
#
# LIBORKAN_PATH is read in Sturm's `__init__` (src/orkan/ffi.jl), i.e. at
# `using Sturm` time, setting it AFTER the fact does nothing for this
# session. If either var is wrong, refuse to proceed rather than run an
# uncapped/misconfigured demo in front of an audience.

const EXPECTED_LIBORKAN = "/home/tobias/Projects/orkan/cmake-build-release/src/liborkan.so"

println("="^72)
println("JuliaCon 2026 · \"Quantum programming in ordinary Julia\" backstage warm-up")
println("="^72)
flush(stdout)

# The check's purpose is "capped, and capped BEFORE julia started", not a
# magic number: uncapped Orkan grabs every core and hammers the machine.
# (An earlier version pinned "16", a value from a bigger box; any explicit
# cap between 1 and this machine's thread count is fine.)
let omp = get(ENV, "OMP_NUM_THREADS", "")
    n = tryparse(Int, omp)
    if n === nothing || n < 1
        error("""
        OMP_NUM_THREADS is \"$omp\" (want an explicit cap). Set it BEFORE \
        starting julia and restart:
          export OMP_NUM_THREADS=$(Sys.CPU_THREADS)
        Uncapped Orkan uses every core and hammers the machine.
        """)
    end
    if n > Sys.CPU_THREADS
        error("""
        OMP_NUM_THREADS=$n oversubscribes this machine \
        (Sys.CPU_THREADS = $(Sys.CPU_THREADS)). Set it BEFORE starting \
        julia and restart:
          export OMP_NUM_THREADS=$(Sys.CPU_THREADS)
        """)
    end
    println("  [env] OMP_NUM_THREADS = $omp  ✅  ($(Sys.CPU_THREADS) hardware threads)")
    flush(stdout)
end

let lib = get(ENV, "LIBORKAN_PATH", "")
    if lib != EXPECTED_LIBORKAN
        error("""
        LIBORKAN_PATH is \"$lib\" (want \"$EXPECTED_LIBORKAN\"). It is read \
        in Sturm's __init__, setting it now, after `using Sturm` has \
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

# ─── stage(): eager-flushed, per-stage timing ─────────────────────────────

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

"""
    expect(actual, wanted, what) -> actual

Hard assertion for a warm-up stage. A stage that merely *doesn't throw* is
NOT evidence the demo works, the ✅ printed by `stage` must mean "produced
the value the deck's pre-baked transcript claims", not "returned something".
On mismatch: print the actual value loudly and `exit(1)` BEFORE the stage's
✅ (and therefore before "STAGE READY") can ever be printed.
"""
function expect(actual, wanted, what::AbstractString)
    if actual != wanted
        println()                       # break out of stage()'s pending line
        println("!"^72)
        println("❌ WARM-UP ASSERTION FAILED: ", what)
        println("   expected: ", repr(wanted))
        println("   actual:   ", repr(actual))
        println()
        println("   DO NOT WALK ON STAGE with this session. The pre-baked")
        println("   shadow transcripts in the deck no longer match reality.")
        println("   Diagnose in a FRESH julia process (stale demoenv? rebuilt")
        println("   liborkan.so? changed Bennett/Sturm on disk?).")
        println("!"^72)
        flush(stdout)
        exit(1)
    end
    return actual
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
# stage, transcribed verbatim from Sturm-PRD-v2.md §7.4 (deutsch_jozsa),
# test/test_m4_views.jl:25-34 (teleport), and DECK-SPEC.md (f, dj_const,
# dj_bal). `f` gets RETYPED live at s10/s15 (harmless method redefinition);
# dj_const/dj_bal/deutsch_jozsa/teleport/teleport_ok are defined ONCE here
# and never retyped, the live s13 and Q&A #teleport commands just call them by name.

stage("define f, dj_const, dj_bal, deutsch_jozsa, teleport, teleport_ok") do
    @eval begin
        # s10 / s15: "every Julia function is already a quantum gate"
        f(x::Int8) = x*x + Int8(3)*x + Int8(1)

        # s13: Deutsch–Jozsa predicates. GENERIC (no ::Int8/::UInt8 on the
        # argument), the bridge compiles at UInt8; a typed signature fails
        # loudly at `oracle()`. Verbatim from test/test_m7_bennett.jl:39-40.
        dj_const(x) = false
        dj_bal(x)   = (x & 0x01) == 0x01

        # s13: verbatim Sturm-PRD-v2.md §7.4.
        function deutsch_jozsa(f, ::Val{N}) where {N}
            x = QInt{N}(0)
            superpose!(x)            # library materialization: H^⊗N on |0⟩
            b = minus()              # |−⟩ literal: QBool(0.5, π)

            b ⊻= oracle(f, x)        # ordinary Julia f, compiled by Bennett;
                                      # kickback on x

            return Int(dual(x)) == 0 # Fourier-sample x; all-zero ⇔ constant
        end

        # Q&A #teleport: verbatim test/test_m4_views.jl:25-34 (PRD §7.1).
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

        # Q&A #teleport shadow/optional-live beat: |+⟩ probe, X-basis (dual) readout;
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
# These calls are NOT what gets typed live, they exercise the SAME code
# paths under throwaway bindings (`_warm*`) so Bennett's/Sturm's compiler
# machinery, LLVM.jl, and Orkan's ccall boundary are all hot before the
# presenter ever types the real thing.

_warmc = stage("warm: reversible_compile(f, Int8)  [pays s10's live command]") do
    Bennett.reversible_compile(f, Int8)
end

stage("warm: simulate(_warmc, Int8(5)) == 41  [FIRST simulate, ~2.8s JIT]") do
    # f(5) = 25 + 15 + 1 = 41, the number pinned in DECK-SPEC §numbers.
    expect(Int(Bennett.simulate(_warmc, Int8(5))), 41,
           "simulate(c, Int8(5)): f(5) must be 41")
end

stage("warm: verify_reversibility(_warmc) == true") do
    expect(Bennett.verify_reversibility(_warmc), true,
           "verify_reversibility(c): compiled circuit must be reversible")
end

_warmc1 = stage("warm: reversible_compile(x+1, UInt8; bit_width=3, ...)  [pays s9]") do
    Bennett.reversible_compile(x -> x + UInt8(1), UInt8; bit_width=3, add=:ripple,
                                fold_constants=true)
end

stage("warm: gs[14:23] == reverse(gs[1:10])  [mirror equality]") do
    gs = _warmc1.gates
    expect(gs[14:23] == reverse(gs[1:10]), true,
           "s9 mirror equality: uncompute must be the compute half reversed")
end

_warmcc = stage("warm: controlled(reversible_compile(!x, Bool))  [pays s12]") do
    Bennett.controlled(Bennett.reversible_compile(x -> !x, Bool))
end

stage("warm: simulate(_warmcc, true, false)==true / (false,false)==false") do
    # `Bool(·)` normalises a 1/0 return as well as a true/false one; anything
    # else (a tuple, say) throws loudly here rather than on stage.
    on  = Bennett.simulate(_warmcc, true, false)
    off = Bennett.simulate(_warmcc, false, false)
    expect(Bool(on), true,
           "simulate(cc, true, false): control set ⇒ target flips")
    expect(Bool(off), false,
           "simulate(cc, false, false): control clear ⇒ target unchanged")
    (on, off)
end
println()
flush(stdout)

println("  ⚠ next step calls oracle() for the FIRST time this session.")
println("    Measured cold: ~20.8 s. This is EXPECTED, do not interrupt.")
flush(stdout)

stage("warm: FIRST oracle() call via deutsch_jozsa(dj_const, Val(2))  [~20.8s COLD]") do
    got = Sturm.eager(18) do _
        deutsch_jozsa(dj_const, Val(2))
    end
    expect(got, true, "deutsch_jozsa(dj_const, Val(2)): constant ⇒ true")
end

stage("warm: deutsch_jozsa(dj_bal, Val(2))  [now warm, pays s13's 2nd line]") do
    got = Sturm.eager(18) do _
        deutsch_jozsa(dj_bal, Val(2))
    end
    expect(got, false, "deutsch_jozsa(dj_bal, Val(2)): balanced ⇒ false")
end

stage("warm: teleport 200-shot probe == 200  [optional Q&A #teleport live beat]") do
    expect(count(_ -> teleport_ok(), 1:200), 200,
           "200-shot teleport probe: every shot must read false in the dual view")
end
println()
flush(stdout)

# ─── Stage 4a: pre-bind the names the SEEDING lines reference ──────────────
#
# The seeding list is typed in REVERSE stage order, so the lines that USE
# `c1` and `cc` get retyped BEFORE the lines that DEFINE them. Without these
# bindings `simulate(cc, ...)` and `gs = c1.gates` would throw UndefVarError
# during seeding, which still seeds history, but noisily, and leaves you
# reading a stack trace minutes before walking on. Bind them here from the
# already-warm objects so EVERY seeding line executes cleanly. (`c` too, for
# symmetry; its own seeding line rebinds it identically.)

c  = _warmc
c1 = _warmc1
cc = _warmcc

# ─── Stage 4b: cheat-sheet: retype these NINE lines once, in this order ───
#
# Retype every live line ONCE, in REVERSE stage order (last-used first).
# Reason: REPL history is LIFO, so reverse-stage seeding leaves each beat's
# line as the MOST RECENT match for its own prefix, recency still helps.
#
# What it does NOT buy you is a fixed ↑-count: executing a recalled command
# APPENDS it to history, so every count drifts by one after every beat, and
# the optional teleport beat shifts everything after it. Fixed counts are a trap.
# Recall by PREFIX instead (type 2–3 chars, then ↑, Julia's prefix history
# search), with Ctrl+R incremental search as the backup. The printed table
# below gives the exact prefix per beat; DEMO-RUNBOOK.md §(b)/§(c) repeat it.

println("="^72)
println("STAGE READY ✅: all JIT paid, all helpers defined.")
println("="^72)
println()
println("Now RETYPE these 9 lines, ONE AT A TIME, in this exact (REVERSE")
println("stage) order, pressing Enter after each. This is what populates")
println("REPL history for prefix-recall on stage, see DEMO-RUNBOOK.md §(b).")
println("`c`, `c1` and `cc` are already bound to the warm objects, so every")
println("line below executes cleanly as you seed it.")
println()

for line in [
    "Sturm.eager(18) do _; deutsch_jozsa(dj_bal, Val(2)); end",
    "Sturm.eager(18) do _; deutsch_jozsa(dj_const, Val(2)); end",
    "simulate(cc, false, false)",
    "simulate(cc, true, false)",
    "cc = controlled(reversible_compile(x -> !x, Bool))",
    "c = reversible_compile(f, Int8)",
    "f(x::Int8) = x*x + Int8(3)*x + Int8(1)",
    "gs = c1.gates; gs[14:23] == reverse(gs[1:10])",
    "c1 = reversible_compile(x -> x + UInt8(1), UInt8; bit_width=3, add=:ripple, fold_constants=true)",
]
    println("    ", line)
end
println()

println("-"^72)
println("RECALL ON STAGE: BY PREFIX, NEVER BY A FIXED ↑-COUNT.")
println("-"^72)
println("Running a recalled line APPENDS it to history, so any ↑-count you")
println("memorised drifts by one after every beat (and the optional teleport beat")
println("shifts the rest). Instead: type the prefix, press ↑, READ the line")
println("on screen, press Enter.")
println()
println("    beat   type this       then ↑ recalls")
println("    -----  --------------  --------------------------------------")
for (beat, prefix, what) in [
    ("s9  a", "c1",             "c1 = reversible_compile(x -> x + UInt8(1), ...)"),
    ("s9  b", "gs",             "gs = c1.gates; gs[14:23] == reverse(gs[1:10])"),
    ("s10 a", "f(x",            "f(x::Int8) = x*x + Int8(3)*x + Int8(1)"),
    ("s10 b", "c = ",           "c = reversible_compile(f, Int8)"),
    ("s12 a", "cc",             "cc = controlled(reversible_compile(x -> !x, Bool))"),
    ("s12 b", "simulate(cc, t", "simulate(cc, true, false)"),
    ("s12 c", "simulate(cc, f", "simulate(cc, false, false)"),
    ("s13 a", "Stu",            "... deutsch_jozsa(dj_const, Val(2)) ..."),
    ("s13 b", "Ctrl+R, dj_b",   "... deutsch_jozsa(dj_bal, Val(2)) ..."),
    ("Q&A  ", "cou",            "count(_ -> teleport_ok(), 1:200)   [#teleport, optional]"),
]
    println("    ", rpad(beat, 7), rpad(prefix, 16), what)
end
println()
println("Notes: the trailing space in `c = ` is what skips `c1 = ...` and")
println("`count(...)`. `Stu` matches BOTH s13 lines, it recalls the more")
println("recent one first, so use Ctrl+R + `dj_b` for the second rather than")
println("counting ↑ presses. Ctrl+R is the general fallback for every beat:")
println("Ctrl+R, type a distinctive substring, accept the match, check the")
println("line, run it. Rehearse both backstage so you know which keystroke")
println("your build uses to accept vs. execute.")
println()
println("Then Ctrl-L to clear the visible screen (history is unaffected).")
println("Then open the deck in the browser and you are ready to walk on:")
println("    file://", joinpath(@__DIR__, "talk.html"))
flush(stdout)
