# Sturm.jl-uf4 minimal probe — smallest viable test for mulmod_beauregard!.
#
# Per WORKLOG handoff (L4105-4118): start with L=2, N=3, a=2, x₀=1 → 2 (ctrl=|1⟩),
# identity under ctrl=|0⟩, with per-stage eager flush. Seconds, not minutes.
#
# Run directly:
#   LIBORKAN_PATH=… julia --project test/probe_uf4_minimal.jl
# NOT via Pkg.test — too slow on this device.

const T0 = time_ns()
_ms() = round((time_ns() - T0) / 1e6; digits=1)
function _log(stage::AbstractString)
    free_gib = round(Sys.free_memory() / 1024^3; digits=2)
    println(stderr, "[", rpad(_ms(), 8), " ms] [free=", free_gib, " GiB] ", stage)
    flush(stderr)
end

_log("ENTER probe_uf4_minimal.jl")

_log("using Sturm (precompile + Orkan init)…")
using Sturm
using Test
_log("using Sturm OK")

# ──────────────────────────────────────────────────────────────────────────
# Stage 1: modadd! backward-compat sanity — one case at L=2, N=3.
# If the ctrls-kwarg refactor broke the no-kwarg path, we catch it here before
# spending time on mulmod.
# ──────────────────────────────────────────────────────────────────────────

_log("STAGE 1: modadd! no-ctrls sanity  (L=2, N=3, a=2, b=1 → 3 mod 3 = 0)")
@context EagerContext() begin
    y   = QInt{3}(1)              # L+1 = 3 qubits, b=1 < N=3
    anc = QBool(0)
    superpose!(y)
    modadd!(y, anc, 2, 3)         # no ctrls kwarg — old path
    interfere!(y)
    got_y   = Int(y)
    got_anc = Bool(anc)
    _log("  Int(y)=$got_y (expect 0),  Bool(anc)=$got_anc (expect false)")
    @test got_y == 0
    @test got_anc == false
end
_log("STAGE 1 GREEN")

# ──────────────────────────────────────────────────────────────────────────
# Stage 2: modadd! with ctrls=(c,) — backward semantics should match
# `when(c) do modadd! end`.
# ──────────────────────────────────────────────────────────────────────────

_log("STAGE 2: modadd! ctrls=(c,) with c=|1⟩  (L=2, N=3, a=2, b=1 → 0)")
@context EagerContext() begin
    y   = QInt{3}(1)
    anc = QBool(0)
    c   = QBool(1)
    superpose!(y)
    modadd!(y, anc, 2, 3; ctrls=(c,))
    interfere!(y)
    got_y   = Int(y)
    got_anc = Bool(anc)
    got_c   = Bool(c)
    _log("  Int(y)=$got_y (expect 0),  Bool(anc)=$got_anc,  Bool(c)=$got_c (expect true)")
    @test got_y == 0
    @test got_anc == false
    @test got_c == true
end
_log("STAGE 2 GREEN")

_log("STAGE 2b: modadd! ctrls=(c,) with c=|0⟩  should be identity — b stays 1")
@context EagerContext() begin
    y   = QInt{3}(1)
    anc = QBool(0)
    c   = QBool(0)
    superpose!(y)
    modadd!(y, anc, 2, 3; ctrls=(c,))
    interfere!(y)
    got_y   = Int(y)
    got_anc = Bool(anc)
    _log("  Int(y)=$got_y (expect 1, identity),  Bool(anc)=$got_anc (expect false)")
    @test got_y == 1
    @test got_anc == false
end
_log("STAGE 2b GREEN")

# ──────────────────────────────────────────────────────────────────────────
# Stage 3: modadd! with ctrls=(c1, c2) — the new double-control path.
# Both |1⟩ → act; either |0⟩ → identity.
# ──────────────────────────────────────────────────────────────────────────

_log("STAGE 3: modadd! ctrls=(c1,c2) with both |1⟩ — a=2, b=1 → 0")
@context EagerContext() begin
    y   = QInt{3}(1)
    anc = QBool(0)
    c1  = QBool(1)
    c2  = QBool(1)
    superpose!(y)
    modadd!(y, anc, 2, 3; ctrls=(c1, c2))
    interfere!(y)
    got_y = Int(y)
    _log("  Int(y)=$got_y (expect 0)")
    @test got_y == 0
    @test Bool(anc) == false
    @test Bool(c1) == true
    @test Bool(c2) == true
end
_log("STAGE 3 GREEN")

_log("STAGE 3b: modadd! ctrls=(c1,c2), c1=|0⟩, c2=|1⟩ — identity (b=1 stays 1)")
@context EagerContext() begin
    y   = QInt{3}(1)
    anc = QBool(0)
    c1  = QBool(0)
    c2  = QBool(1)
    superpose!(y)
    modadd!(y, anc, 2, 3; ctrls=(c1, c2))
    interfere!(y)
    got_y = Int(y)
    _log("  Int(y)=$got_y (expect 1)")
    @test got_y == 1
    @test Bool(anc) == false
end
_log("STAGE 3b GREEN")

_log("STAGE 3c: modadd! ctrls=(c1,c2), c1=|1⟩, c2=|0⟩ — identity")
@context EagerContext() begin
    y   = QInt{3}(1)
    anc = QBool(0)
    c1  = QBool(1)
    c2  = QBool(0)
    superpose!(y)
    modadd!(y, anc, 2, 3; ctrls=(c1, c2))
    interfere!(y)
    got_y = Int(y)
    _log("  Int(y)=$got_y (expect 1)")
    @test got_y == 1
    @test Bool(anc) == false
end
_log("STAGE 3c GREEN")

# ──────────────────────────────────────────────────────────────────────────
# Stage 4: mulmod_beauregard! — the WIP. Minimum case: L=2, N=3, a=2, x=1.
#   (2 * 1) mod 3 = 2 with ctrl=|1⟩
#   x unchanged           with ctrl=|0⟩
# ──────────────────────────────────────────────────────────────────────────

_log("STAGE 4: mulmod_beauregard! L=2 N=3 a=2 x=1 ctrl=|1⟩  (expect x → 2)")
@context EagerContext() begin
    x    = QInt{2}(1)
    ctrl = QBool(1)
    mulmod_beauregard!(x, 2, 3, ctrl)
    got_x    = Int(x)
    got_ctrl = Bool(ctrl)
    _log("  Int(x)=$got_x (expect 2),  Bool(ctrl)=$got_ctrl (expect true)")
    @test got_x == 2
    @test got_ctrl == true
end
_log("STAGE 4 GREEN")

_log("STAGE 4b: mulmod_beauregard! L=2 N=3 a=2 x=1 ctrl=|0⟩  (expect x → 1 identity)")
@context EagerContext() begin
    x    = QInt{2}(1)
    ctrl = QBool(0)
    mulmod_beauregard!(x, 2, 3, ctrl)
    got_x    = Int(x)
    got_ctrl = Bool(ctrl)
    _log("  Int(x)=$got_x (expect 1),  Bool(ctrl)=$got_ctrl (expect false)")
    @test got_x == 1
    @test got_ctrl == false
end
_log("STAGE 4b GREEN")

# ──────────────────────────────────────────────────────────────────────────
# Stage 5: mulmod_beauregard! L=2 — a few more deterministic cases.
# ──────────────────────────────────────────────────────────────────────────

_log("STAGE 5: L=2 N=3, full sweep over x ∈ {0,1,2}, a ∈ {1,2}, both ctrl values")
for a in 1:2, x0 in 0:2, cval in (0, 1)
    expected = cval == 1 ? (a * x0) % 3 : x0
    @context EagerContext() begin
        x    = QInt{2}(x0)
        ctrl = QBool(cval)
        mulmod_beauregard!(x, a, 3, ctrl)
        got_x = Int(x)
        ok = got_x == expected
        _log("  a=$a x0=$x0 ctrl=$cval  got=$got_x  expect=$expected  " *
             (ok ? "OK" : "MISMATCH"))
        @test got_x == expected
    end
end
_log("STAGE 5 GREEN")

# ──────────────────────────────────────────────────────────────────────────
# Stage 6: L=3 exhaustive, ctrl=|1⟩.  N ∈ {3, 5, 7}; all gcd(a,N)=1 pairs;
# x ∈ {0..N-1}.  Expect x → (a·x) mod N.
# ──────────────────────────────────────────────────────────────────────────

_log("STAGE 6: mulmod_beauregard! L=3 exhaustive ctrl=|1⟩ (N ∈ {3,5,7})")
let
    n_cases = Ref(0); n_fail = Ref(0); t_stage = time_ns()
    for N in (3, 5, 7), a in 1:(N-1), x0 in 0:(N-1)
        gcd(a, N) == 1 || continue
        @context EagerContext() begin
            x    = QInt{3}(x0)
            ctrl = QBool(1)
            mulmod_beauregard!(x, a, N, ctrl)
            got = Int(x)
            expected = (a * x0) % N
            ok = got == expected
            n_cases[] += 1
            if !ok
                n_fail[] += 1
                _log("  FAIL N=$N a=$a x0=$x0  got=$got  expect=$expected")
            end
            @test got == expected
            @test Bool(ctrl) == true
        end
    end
    t_stage_ms = round((time_ns() - t_stage) / 1e6; digits=1)
    _log("STAGE 6 done: $(n_cases[]) cases, $(n_fail[]) fail, $(t_stage_ms) ms " *
         "($(round(t_stage_ms / max(n_cases[], 1); digits=2)) ms/case)")
    @test n_fail[] == 0
end

# ──────────────────────────────────────────────────────────────────────────
# Stage 7: L=3 exhaustive, ctrl=|0⟩ → identity.
# ──────────────────────────────────────────────────────────────────────────

_log("STAGE 7: mulmod_beauregard! L=3 exhaustive ctrl=|0⟩ — identity (N ∈ {5,7})")
let
    n_cases = Ref(0); n_fail = Ref(0); t_stage = time_ns()
    for N in (5, 7), a in 1:(N-1), x0 in 0:(N-1)
        gcd(a, N) == 1 || continue
        @context EagerContext() begin
            x    = QInt{3}(x0)
            ctrl = QBool(0)
            mulmod_beauregard!(x, a, N, ctrl)
            got = Int(x)
            ok = got == x0
            n_cases[] += 1
            if !ok
                n_fail[] += 1
                _log("  FAIL N=$N a=$a x0=$x0  got=$got  expect=$x0")
            end
            @test got == x0
            @test Bool(ctrl) == false
        end
    end
    t_stage_ms = round((time_ns() - t_stage) / 1e6; digits=1)
    _log("STAGE 7 done: $(n_cases[]) cases, $(n_fail[]) fail, $(t_stage_ms) ms " *
         "($(round(t_stage_ms / max(n_cases[], 1); digits=2)) ms/case)")
    @test n_fail[] == 0
end

# ──────────────────────────────────────────────────────────────────────────
# Stage 8: Coherent ctrl=|+⟩.  Expect 50/50 mixture of (x0, (a·x0) mod N) with
# ±15% window over 400 shots.  Any other outcome flags decoherence bug.
# ──────────────────────────────────────────────────────────────────────────

_log("STAGE 8: coherent ctrl=|+⟩ at L=3  (3 cases × 400 shots)")
let
    L = 3
    cases = [(N=5, a=2, x0=3), (N=7, a=3, x0=4), (N=5, a=4, x0=2)]
    t_stage = time_ns()
    for c in cases
        expected = (c.a * c.x0) % c.N
        n_id = Ref(0); n_mul = Ref(0); n_other = Ref(0)
        t_case = time_ns()
        for _ in 1:400
            @context EagerContext() begin
                x    = QInt{L}(c.x0)
                ctrl = QBool(1/2)                # |+⟩
                mulmod_beauregard!(x, c.a, c.N, ctrl)
                r = Int(x)
                _ = Bool(ctrl)
                if r == c.x0
                    n_id[] += 1
                elseif r == expected
                    n_mul[] += 1
                else
                    n_other[] += 1
                end
            end
        end
        t_case_ms = round((time_ns() - t_case) / 1e6; digits=1)
        _log("  case N=$(c.N) a=$(c.a) x0=$(c.x0) expect=$expected  " *
             "id=$(n_id[])  mul=$(n_mul[])  other=$(n_other[])  " *
             "($(t_case_ms) ms / 400 shots, $(round(t_case_ms / 400; digits=2)) ms/shot)")
        @test n_other[] == 0
        @test 140 <= n_id[]  <= 260
        @test 140 <= n_mul[] <= 260
    end
    t_stage_ms = round((time_ns() - t_stage) / 1e6; digits=1)
    _log("STAGE 8 done: 3 cases × 400 shots = 1200 shots total in $(t_stage_ms) ms")
end

_log("EXIT probe_uf4_minimal.jl")
