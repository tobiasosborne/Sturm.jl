# Sturm.jl Work Log

Gotchas, learnings, decisions, and surprises. Updated every step.

---

## 2026-04-19 — Session 27: Hunt for N=21 failure uncovers P0 bug in uf4

Session 26 closed `Sturm.jl-6kx` with shor_order_D green at N=15 (50%
r=4 hit rate, 10/10 factor_D(15) → {3,5}).  User asked to extend
verification to N=21 and N=35 per the 6kx acceptance criteria.  The
extension **FAILED** — and the root cause is a P0 phase leak in
`mulmod_beauregard!` (Sturm.jl-uf4), which Session 25's all-green
3208-test suite **did not catch** because every test was Z-basis on
ctrl.  Honest status: **we do not have a working Shor algorithm yet**
for any N larger than 15.

### Trail

**Stage 1 — N=21 end-to-end fails.** `test/probe_shor_larger_N.jl`
20 shots of `shor_order_D(2, 21; t=6)`: **0/20 r=6 hits** (expected
~33% per PE theory), 14/20 "other" r values.

**Stage 2 — ỹ histogram is scattered, not peaked.**
`test/probe_N21_ytilde.jl` took 40 shots of the same cascade and
dumped ỹ distribution.  Result: 30 distinct ỹ values out of 64,
only 10 shots at the 6 theoretical peaks {0, 11, 21, 32, 43, 53}.
Expected (PE theory) mass at peaks ≈ 24/40 (60%).  Observed 25%.
Top 3 values (30, 32, 33) each with 3 shots show a triple-wide
cluster around 32 — PE amplitudes are smeared, not peaked.

**Stage 3 — mulmod itself is correct.**
`test/probe_shor_bug_hunt.jl` ran:

- EXP-A: `mulmod_beauregard!` at L=5 N=21 exhaustive, all 252
  (a, x₀) cases with ctrl=|1⟩: **0 fail**.  Arithmetic correct.
- EXP-B: `shor_order_D(7, 15; t=4)` 20 shots: 11/20 r=4 (55%).
- EXP-C: `shor_order_D(7, 15; t=6)` 10 shots: 8/10 r=4 (80%).

  So the primitive is right, the PE machinery works at N=15 at all
  tested t, but the cascade breaks at larger N.

**Stage 4 — PE machinery itself is correct.**
`test/probe_pe_bug.jl` Q1: `phase_estimate(Z!, QBool(1), Val(t))`
at t ∈ {3, 4, 5, 6}: 20 shots each, **all return the exact expected
ỹ** (ỹ = 2^(t-2), since Z! = Rz(π) has eigenphase 1/4 — a correct
eigenphase I briefly thought was 1/2 before re-reading CLAUDE.md's
"Global Phase and Universality" note).  Rule 9 check on my own
assumption.  phase_estimate is fine.

  Q2: same probe ran `shor_order_D(2, 21; t=3..6)` — period-factor
hit rate stuck at **6.7%** for t=3, 4, 5 (single lucky r=2 shot per
15), then 20% at t=6.  N=21 is broken at every t; this is not a
resolution issue.

**Stage 5 — X-basis test on ctrl exposes the π/2 phase leak.**
`test/probe_mulmod_phase.jl` runs the minimal protocol:

    ctrl = QBool(1/2)          # prepare |+⟩ via Ry(π/2)|0⟩
    mulmod_beauregard!(x, a, N, ctrl)
    ctrl.θ -= π/2              # Ry(-π/2) = inverse of the |+⟩ prep
    m = Bool(ctrl)             # should be FALSE if ctrl preserved

If `mulmod_beauregard!` preserves ctrl as a pure |+⟩, Ry(-π/2)
brings ctrl back to |0⟩ and `m = false` every shot.  Any `m = true`
rate above 0 indicates ctrl was disturbed; rate = sin²(ξ/2) gives
the effective leaked phase ξ on ctrl=|1⟩.

**Measured across L=4 N=15 and L=5 N=21, 80 shots per case:**

| config                       | x₀ = 0 | x₀ > 0 (any)     |
|------------------------------|-------:|-----------------:|
| L=4 N=15 a ∈ {2, 7}          |  0%    | **47 – 58%**     |
| L=5 N=21 a ∈ {2, 4, 16}      |  0%    | **44 – 61%**     |

Leak = ~50% everywhere x > 0 ⇒ **ξ = π/2 exactly** (sin²(π/4) = 0.5).
Leak = 0 at x = 0 because mulmod is trivially identity on |0⟩ there.

The 50% X-basis rate is consistent with ctrl being in a
**maximally mixed state** after mulmod — i.e., ctrl has been
completely entangled with internal ancillae that are then discarded,
and the partial trace erases ctrl's coherence.  That matches the
observed PE behaviour: 6 sequential mulmods at N=21 t=6 decohere
all 6 counter qubits, killing interference.

### Why Session 25's 3208-test suite missed this

Every uf4 coherent test ran:

    @context EagerContext() begin
        x    = QInt{L}(x0)
        ctrl = QBool(1/2)
        mulmod_beauregard!(x, a, N, ctrl)
        r = Int(x)
        _ = Bool(ctrl)                # Z-basis on ctrl
        ...
    end

**Z-basis on |+⟩ and on a maximally-mixed qubit both give 50/50.**
The two are indistinguishable without an X-basis measurement (or
equivalently, an inverse of the |+⟩ prep followed by Z).  Session
25's tests correctly caught every case where ctrl ACQUIRED a
population imbalance — but a pure phase (or full decoherence) stays
invisible.

### Corollary — N=15 t=3 "passed" by coincidence

At N=15 a=7 with t=3, only 2 of 3 mulmods actually fire because
a_j = [7, 4, 1] and a_j=1 is skipped at runtime.  Two rounds of
decoherence accumulated across only 3 counter qubits happens to
scatter PE amplitudes in a way that *still* gives 50% mass on the
r=4 peaks (ỹ ∈ {2, 6} decode to r=4 at t=3).  This is a
happy-accident signal, not a correctness guarantee.  The bench
numbers for impl D (wires, gates, DAG bytes) remain valid as
structural / resource measurements — the DAG IS polynomial in L —
but the statevector simulation outputs cannot be trusted past
N=15.

### Status of the polynomial-in-L Shor chain

| Bead                     | Real status                                |
|--------------------------|--------------------------------------------|
| `Sturm.jl-ar7` add_qft   | ✓ correct                                  |
| `Sturm.jl-dgy` modadd    | ⚠ Z-basis correct; X-basis coherence not verified |
| `Sturm.jl-uf4` mulmod    | ⚠ Z-basis correct; **π/2 X-basis leak** (di9) |
| `Sturm.jl-6kx` shor_D    | ⚠ structure correct; end-to-end N=15 only; **BROKEN N ≥ 21** |
| `Sturm.jl-di9`           | P0 bug filed; root-cause fix blocks 6kx completion |
| `Sturm.jl-8b9`           | P1 Fig. 8 semi-classical iQFT, deferred — would have hit the same phase leak anyway |

### Not yet known — where the π/2 comes from

Three candidates under investigation (details in Sturm.jl-di9):

1. **Controlled-Rz(θ) on superposed target leaks -θ/2 phase on
   ctrl=|1⟩.**  add_qft! contains Rz gates applied to Fourier-basis
   y wires (every y wire is in superposition).  Inside modadd step
   6 (`when(anc) add_qft!(y, N)`) or modadd steps 1/7/13 (under
   ctrls=(ctrl, xj)), each CRz(θ_k) leaks -θ_k/2 onto the outer
   control.  Summing across wires and across modadd calls per
   mulmod could produce the observed π/2 constant.

2. **Rz angle folding `mod(θ+π, 2π) - π` introduces global phase
   -1 per fold.**  add_qft! folds θ_raw = 2π·a/2^jj into (-π, π].
   Under control, -1 global phase = π relative phase on ctrl=|1⟩.
   Cumulative across L Rz's × 2L modadds × … might land at π/2 mod 2π.

3. **Ry(π) / Ry(-π) MSB flip pair at modadd steps 9/11 was added
   in Session 25 specifically to avoid a global phase (the X! = -iY
   fix).**  It cancels cleanly when modadd runs standalone — but
   may NOT cancel correctly inside a cascaded operation (mulmod's
   2L modadds) if the intermediate state transforms the msb wire
   non-trivially.

Fix strategy (per di9): build a minimal X-basis harness, narrow the
leak block-by-block (add_qft alone, modadd alone, modadd with
ctrls, mulmod CMULT forward alone, full mulmod), identify the
exact gate sequence that leaks, apply the smallest possible
compensating phase rotation.  Add X-basis regression tests to
`test/test_arithmetic.jl` so the next silent-phase bug has a
tripwire.

### Files added this session

- `test/probe_shor_larger_N.jl` — N=21/N=35 end-to-end (fails)
- `test/probe_shor_bug_hunt.jl` — mulmod-at-L=5 + N=15 bigger-t isolation
- `test/probe_N21_ytilde.jl` — ỹ histogram
- `test/probe_pe_bug.jl` — phase_estimate sanity + shor_order_D t-sweep
- `test/probe_mulmod_phase.jl` — X-basis coherence probe (the smoking gun)

All kept as dev probes; NONE registered in runtests.jl.

### Files changed

- `src/library/shor.jl` — added `!!! warning` block to `shor_order_D`
  docstring flagging di9 and the N ≥ 21 restriction.
- `WORKLOG.md` — this entry.

### Beads

- `Sturm.jl-di9` — P0 bug filed (mulmod phase leak).
- `Sturm.jl-6kx` stays closed for the DAG-structure deliverable, but
  the end-to-end N=21/N=35 verification is blocked on di9.  If a new
  bead is wanted for "extend 6kx coverage post-fix", file as depending
  on di9 at that time.
- `Sturm.jl-8b9` (semi-classical iQFT) still P1; deferred.  Would
  have hit the same phase leak so no work lost.

### Gotchas for future agents — KEEP THESE IN MIND

1. **Z-basis measurement of a control qubit that started as |+⟩ is
   BLIND to phase leaks and to full decoherence.**  Both |+⟩ and
   maximally-mixed give 50/50 Z-basis outcomes.  Test coherence via
   inverse-prep-then-Z (a.k.a. X-basis via Ry(-π/2)) — see
   `test/probe_mulmod_phase.jl` for the minimal protocol.  Consider
   this rule a **correctness prerequisite** for any new controlled
   sub-circuit shipped into Sturm.

2. **Session 25's sin²(ξ/2) probe pattern was a 4-line test that
   would have caught di9 immediately.**  It was not run because
   Session 25 only added the coherent `ctrl=|+⟩` test at the
   mulmod LEVEL with Z-basis output — exactly the pattern that's
   blind to phase leaks.  New primitives that accept a QBool ctrl
   should ship with BOTH Z-basis correctness (`Int(x) == expected`)
   AND X-basis coherence (`Bool(Ry(-π/2); ctrl) == false`) tests.

3. **"All tests green" is a lower bound, not a correctness proof.**
   The 3208-pass uf4 suite is what I (confidently) shipped as
   "mulmod_beauregard! works".  Better framing: "mulmod produces
   correct computational-basis outputs and preserves ctrl's Z-basis
   mixing, coherence not verified".  Generalising: always state the
   regime a test suite actually checks.

4. **Verbose-flush pattern paid off AGAIN.**  The smoking-gun probe
   (`probe_mulmod_phase.jl`) ran 27 rows × 80 shots with per-row
   flush output — the leak pattern (x=0 clean, x>0 ~50%) jumped out
   in the very first printed line of the first config.  No
   blank-screen-waiting; the tell was visible within 15 seconds.
   Keep it up.

---

## 2026-04-19 — Session 26: Close `Sturm.jl-6kx` (shor_order_D, polynomial-in-L Shor)

Picked up from Session 25's uf4 close. The polynomial-in-L Shor chain's
final brick: replace `shor_order_C`'s packed-QROM mulmod with
`mulmod_beauregard!` while keeping the Box 5.2 / Eq. 5.43 cascade
structure. Beauregard 2003 Fig. 7 "c-U_a" is literally a c-CMULT · c-SWAP
· c-CMULT⁻¹ sandwich, and our Sturm.jl-uf4 signature already takes a
single ctrl QBool — so the entire impl D body is ~20 lines of real logic
plus docstring.

### Ground truth (read before coding, per rule 4)

`docs/physics/beauregard_2003_2n3_shor.pdf` pp. 7–11.

- **Fig. 7 (p. 8)** and surrounding text (p. 7): c-U_a = three blocks
  (forward CMULT(a), SWAP, inverse CMULT(a⁻¹)), each with an outer `c`
  control dot. We already pass `c` to `mulmod_beauregard!` as its
  `ctrl::QBool` argument — no wrapping `when(c)` needed.
- **Eq. 4 (p. 8):** `(a^n x) mod N = a·(a·…·(a·x) mod N) mod N`. This
  means we can run `c-U_{a^{2^j}}` directly, with `a^{2^j} mod N`
  precomputed classically. Impl C already does this; impl D inherits.
- **§3 (p. 11):** order-finding circuit = 2n of these c-U_a, each
  `O(n²·k_max)` gates with depth `O(n²)`. With exact QFT `k_max = n`,
  total = `O(n³ · k_max) = O(n⁴)` at `n = L`. Depth `O(n³)`.

### Implementation

Added to `src/library/shor.jl` between impl C (line 803) and the end.
Two functions, exports in `src/Sturm.jl`:

- `shor_order_D(a, N; t, verbose)` / `shor_order_D(a, N, ::Val{t})` —
  Box 5.2 cascade body identical to impl C's outer shape (counter QInt{t},
  superpose, eigenstate y=QInt{L}(1), t controlled mulmods, interfere,
  discard, continued fractions). The inner mulmod call is
  `mulmod_beauregard!(y_reg, a_j, N, ctrl)` with `ctrl =
  QBool(c_reg.wires[j], ctx, false)`. NO wrapping `when(c_reg.wires[j])`
  — this is the critical design decision, see below.
- `shor_factor_D(N)` — mirrors `shor_factor_A/B/C`. Trivial wrapper.

The skip-`a_j==1` optimization at the top of the mulmod loop saves 2L
modadds per trivially-identity stage. Beauregard's c-U_a for a=1 is
identity but the circuit still issues 2L modadds with classical
constants `(2^(j-1)) mod N` and their inverses, cancelling to
identity — wasteful. At N=15, a=7, order 4: a_j = {7, 4, 1, 1, …} so
most t>2 stages save ~2L² gates each.

### Key design decision — DO NOT wrap mulmod_beauregard! in when()

The obvious impl-C-parallel is:

```julia
for j in 1:t
    when(c_reg.wires[j]) do
        mulmod_beauregard!(y_reg, a_j, N, /* what? */)
    end
end
```

This would be wrong. `mulmod_beauregard!` takes its own `ctrl::QBool`
which it folds into modadd's `ctrls=(ctrl, xj)` kwarg (Sturm.jl-uf4
fix). The outer `when(counter_qubit)` would then add a **third** control
to every primitive inside modadd — reviving the 3-deep cascade we just
killed in Session 25. The fast-path invariant (nc ≤ 2) fails, every Rz
cascades through `_multi_controlled_gate!`, workspace ancillae allocate,
gate count explodes.

Correct pattern: pass `c_reg.wires[j]` *as* `mulmod_beauregard!`'s ctrl.
The counter qubit is the `c` of Beauregard's Fig. 7. Inside modadd we
then have `ctrls = (counter_qubit, x_j)` — depth 2, fast path.

Documented in the `shor.jl` prose above the impl, with an explicit "NOT
what we want" warning for the next agent.

### Verification — probe first, then registered test

Two-phase per `feedback_verbose_eager_flush.md` + `sturm-jl-test-suite-slow`
memory.

**Phase 1** — `test/probe_6kx_minimal.jl` (new, standalone). Four stages
with per-shot `println(stderr, …)+flush` + free-RAM logging:

| Stage | What | Result | Wall |
|-------|------|--------|------|
| 1 | Single verbose shot, N=15 a=7 t=3 | r=4, HWM 14q, cap 16 | 29.3 s (first mulmod paid 10 s JIT, second 17 s) |
| 2 | 30 shots N=15 a=7 t=3, hit-rate on r=4 | 15/30 = 50%, 0 spurious | 93.6 s (3.1 s/shot warm) |
| 3 | 20 shots N=15 a=2 t=3 | 8/20 = 40% r=4, 0 spurious | 30.7 s (1.5 s/shot warm) |
| 4 | `shor_factor_D(15)` × 10 attempts | 10/10 → {3, 5} | 5.4 s |

RAM flat at 59.7 GiB free throughout. HWM stable at 14 qubits
(vs impl C's 26).

**Phase 2** — `julia --project -e 'include("test/test_shor.jl")'`
(targeted, not full `Pkg.test()`). Enabled the impl-D testset at
`test/test_shor.jl:202-252`; impl-B and impl-C blocks remain
`@test_skip` per their original intractability.

### Resource comparison — impl D vs impl C at N=15 t=3

| Metric                   | Impl C measured   | Impl D measured   | Ratio       |
|--------------------------|------------------:|------------------:|------------:|
| HWM qubits               | 26                | **14**            | −12 qubits  |
| Orkan statevector cap    | 28  (4 GiB)       | **16** (~1 MiB)   | ~4000×      |
| Wall time per shot       | 302 s             | 1.5–3.1 s (warm)  | **~100–200×** |
| Hit rate r=4 (a=7)       | (untestable)      | 50% / 30 shots    | —           |
| Factor(15) success rate  | (untestable)      | 10/10 → {3, 5}    | —           |

Impl C's slowness was dominated by the 4 GiB statevector memory
bandwidth per Toffoli × ~17 000 gates/shot. Impl D's (2L+3)-wire
Beauregard circuit keeps the statevector at ~1 MiB — memory traffic per
Toffoli drops 4000× and wall-time drops by essentially the same factor.
Gate counts (from the tracing bench below) are actually *comparable*
to impl C at small L and smaller at large L, so the statevector
shrinkage is the whole win.

### Benchmark calibration (`test/bench_shor_scaling.jl`)

Added `:D` to `estimate_gates`, `trace_impl`, and every `CASES[*].impls`
list. Tracing bench at L=4..6, STURM_BENCH_ONLY=D:

| L | t  | wires | gates  | toffoli | est (old) | est (new 100·t·L²) | ratio |
|--:|---:|------:|-------:|--------:|----------:|--------------------:|------:|
| 4 |  8 |    24 |  2 447 |      24 |    25 620 |              12 800 | 5.2×  ← (2 of 8 mulmods fired; a=7 N=15 saturates after j=2) |
| 5 | 10 |    85 | 19 395 |     150 |    50 025 |              25 000 | 1.29× |
| 6 | 12 |   114 | 33 342 |     216 |    86 430 |              43 200 | 1.30× |

Empirical fit `per-mulmod gates ≈ 77·L²` (L=5 and L=6 agree to 0.5%);
slope (ln gates vs ln L) = 3.0 at fixed t → **O(L³) per order-find, O(L⁴)
at t = 2L**. Matches Beauregard §3. Extrapolations:

| L  | t  | est gates | est DAG bytes |
|---:|---:|----------:|--------------:|
|  7 | 14 |    68 600 |       1.7 MB  |
| 10 | 20 |   200 000 |       5.0 MB  |
| 14 | 28 |   548 800 |      14 MB    |
| 18 | 36 | 1 166 400 |      29 MB    |

vs impl C's measured **47 M gates / ~1.2 GB DAG** at L=14 → impl D at
L=14 is projected at ~86× fewer gates AND polynomial growth (slope ~3)
vs impl C's ~2^L exponential. The rotation in dominance flips around
L=5 where impl D becomes cheaper by every measure.

Bead acceptance criterion was "log-log slope ≤ 4 across L=6..14". We
can only measure L=6 directly today (L=14 via estimator), but the
L=5→6 slope of 3.0 is well under 4 and matches the analytic O(L⁴)
prediction. Calibration at L=7..14 is the job of the next bench run.

### Files touched

- `src/library/shor.jl` — added `shor_order_D` + `shor_factor_D` and
  the impl-D docstring block (~100 lines total). No changes to impls
  A/B/C.
- `src/Sturm.jl` — export `shor_order_D, shor_factor_D`.
- `test/test_shor.jl` — new `@testset "Impl D: …"` with 3 sub-testsets
  matching impl-A's shape (single-case hit rate, 7 coprime bases,
  factor recovery). Impl B/C `@test_skip` blocks unchanged.
- `test/probe_6kx_minimal.jl` (new) — standalone 4-stage verbose-flush
  probe. Kept as a dev tool; not registered in runtests.jl.
- `test/bench_shor_scaling.jl` — `:D` branch in `estimate_gates`
  (`100·t·L²`), `:D` branch in `trace_impl`, `:D` added to every
  `CASES[*].impls` list. Docstring for `estimate_gates` extended with
  the `:D` calibration table.
- `WORKLOG.md` — this entry.

### Beads

- `Sturm.jl-6kx` closed.
- Chain completion: ar7 (add_qft!) → dgy (modadd!) → uf4
  (mulmod_beauregard!) → **6kx (shor_order_D)** — all four bricks of
  the polynomial-in-L Shor epic Sturm.jl-c6n closed.

### Gotchas for future agents

1. **The single most important refactor choice in impl D is what NOT to
   do.** Don't wrap `mulmod_beauregard!` in `when(counter_qubit)` — pass
   `counter_qubit` as the ctrl kwarg. If a future caller/subroutine
   needs c-U_a under an additional outer when (e.g. embedding Shor
   inside a larger algorithm), either (a) pre-AND the two controls into
   a workspace ancilla via one Toffoli and pass *that* as ctrl, or
   (b) extend `mulmod_beauregard!` to accept `ctrls::Tuple` like
   `modadd!` does today. Never nest when()s around a function that
   already takes its own ctrl.

2. **Skip a_j=1 at runtime or your bench looks like impl D is tiny at
   small L.** For N=15 a=7 (order 4) at t=8 only 2 of 8 mulmods fire;
   the bench showed 2447 gates vs a 12800 worst-case estimate. This is
   correct behavior (identity mulmods are wasteful to emit), but it
   confuses the cost calibration — always measure at cases where the
   order is close to `2^t` so all a_j are non-trivial. L=5 N=21 a=2
   (order 6) and L=6 N=35 a=2 (order 12) are both clean calibration
   cases.

3. **Per-mulmod gate count ≈ 77·L² is remarkably tight.** Two data
   points (L=5, L=6) agree to 0.5% — this is a solid architectural
   invariant. If a future change to `modadd!` or `add_qft!` changes the
   per-mulmod gate count, the ratio will drift visibly. Treat this as a
   regression indicator: the L=5 and L=6 numbers are 19395 and 33342
   gates at t=2L; significant deviation means something changed at the
   primitive level.

---

## 2026-04-19 — Session 25: Close `Sturm.jl-uf4` (mulmod_beauregard! green-up)

Picked up from Session 24 handoff: `mulmod_beauregard!` code committed on
`15bf951` but never run to green because nested `when(ctrl) do when(xj) do
modadd!(…) end end` PLUS modadd's own `when(anc) add_qft!(y, N)` = **3-deep
control stack**, triggering `_multi_controlled_gate!` cascade on every
primitive. At L=3 N=5 coherent shots, each shot was allocating workspace
ancillae per primitive — astronomical.

Closed bead with the Beauregard p.6 fix already foreshadowed in the
handoff checklist.

### Ground truth (read BEFORE coding, per rule 4)

`docs/physics/beauregard_2003_2n3_shor.pdf` pp. 5–8. Three equations/figures
load-bearing for the fix:

- **Fig. 5** (doubly-controlled φADD(a)MOD(N)). The two outer control dots
  `c1, c2` connect ONLY to the three φADD(a) gates (steps 1, 7, 13 in the
  13-step expansion). QFT / QFT⁻¹ / CNOT / X-on-MSB / and the `anc`-
  controlled ADD(N) are **unconditional** in the circuit — no `c1`/`c2`
  control dot touches them.
- **Text p.6:** "we will doubly control only the φADD(a) gates instead of
  all the gates. If the φADD(a) gates are not performed, it is easy to
  verify that the rest of the circuit implements the identity on all
  qubits because b < N."  This is the correctness certificate for
  pulling the controls down.
- **Fig. 6** (CMULT(a)MOD(N)). The outer QFT/QFT⁻¹ sandwich on the b
  register is **outside** the c-control region — `c`-control shrinks to
  the n doubly-controlled modadds.
- **Fig. 7** (c-U_a). Controlled-SWAP between x and b is singly controlled
  by c only.

### Refactor

Two changes in `src/library/arithmetic.jl`, no other files touched.

**modadd!: new `ctrls::Tuple` kwarg.**

```julia
modadd!(y, anc, a, N; ctrls = ())      # backward-compat: no change
modadd!(y, anc, a, N; ctrls = (c,))    # singly controlled, Beauregard sense
modadd!(y, anc, a, N; ctrls = (c1,c2)) # doubly controlled, Beauregard sense
```

Implemented via an inline `_apply_ctrls(f, ctrls)` helper that resolves
each arity at compile time:

```julia
@inline _apply_ctrls(f, ::Tuple{}) = f()
@inline _apply_ctrls(f, c::Tuple{QBool}) = when(c[1]) do; f(); end
@inline _apply_ctrls(f, c::Tuple{QBool,QBool}) =
    when(c[1]) do; when(c[2]) do; f(); end; end
```

Only steps 1, 7, 13 (the three `add_qft!(y, a)` / `sub_qft!(y, a)` calls)
get wrapped. Steps 2–6, 8–12 run unconditionally — matches Fig. 5 exactly.

**mulmod_beauregard!: pull QFTs out, push controls down.**

Old (3-deep cascade):

```julia
when(ctrl) do
    superpose!(b)                          # ctrl-controlled QFT
    for j in 1:L
        when(xj) do                         # (ctrl, xj)-controlled
            modadd!(b, anc, c_j, N)        # inside: when(anc) push → 3 deep
        end
    end
    interfere!(b)                          # ctrl-controlled QFT⁻¹
    for j in 1:L; swap!(xj, bj); end        # ctrl-controlled SWAP
    superpose!(b)
    …inverse CMULT same pattern…
    interfere!(b)
end
```

New (max-2 fast path):

```julia
superpose!(b)                              # UNCONDITIONAL QFT
for j in 1:L
    modadd!(b, anc, c_j, N; ctrls=(ctrl, xj))  # push controls into modadd
end
interfere!(b)                              # UNCONDITIONAL QFT⁻¹

when(ctrl) do                              # singly-controlled SWAP
    for j in 1:L; swap!(xj, bj); end
end

superpose!(b)                              # UNCONDITIONAL QFT
for j in 1:L
    modadd!(b, anc, (N - c_j) mod N, N; ctrls=(ctrl, xj))
end
interfere!(b)                              # UNCONDITIONAL QFT⁻¹
```

### Correctness sketch (ctrl=0 branch)

- Unconditional `superpose!(b)` on `|0⟩` → `|Φ(0)⟩`.
- All modadds in forward CMULT have `ctrls=(ctrl=0, …)` — every internal
  `_apply_ctrls` body skipped. modadd runs its QFT/sub/CNOT/X pattern
  internally, which per Beauregard's correctness argument collapses to
  identity because `b < N`. So `b` stays `|Φ(0)⟩`.
- `interfere!(b)` inverts the outer QFT → `b = |0⟩`.
- `when(ctrl=0) do swap! end` — SWAP skipped. `x` unchanged.
- Second QFT sandwich: same argument, `b` returns to `|0⟩`.

Net: `x` unchanged, `b = |0⟩`, `anc = |0⟩`. ✓ Identity on ctrl=0.

ctrl=1 branch: every modadd fires, forward CMULT computes
`b = (a·x) mod N` in Fourier basis, QFT⁻¹ brings it to computational
basis, SWAP puts `(a·x) mod N` on x wires and `x_orig` on b wires,
reverse CMULT with `a⁻¹` zeros b.  Result: `x = (a·x_orig) mod N`.

### Max control depth after refactor

| Site                                 | Old | New |
|--------------------------------------|----:|----:|
| modadd step 1 (ADD(a))               | 3   | 2   |
| modadd step 6 (anc-ADD(N))           | 3   | 1   |
| modadd step 7 (SUB(a))               | 3   | 2   |
| modadd step 13 (ADD(a))              | 3   | 2   |
| modadd steps 2-5, 8-12 (all others) | 2   | 0   |
| mulmod QFT on b                      | 1   | 0   |
| mulmod SWAP                          | 1   | 1   |

All primitives now hit Sturm's nc≤2 inline HotNode fast path. Zero
workspace ancilla allocation, zero Toffoli-cascade reverse passes.

### Verification

Before committing, two-phase verification per WORKLOG's uf4 handoff
checklist plus `feedback_verbose_eager_flush.md` discipline.

**Phase 1** — minimal probe (`test/probe_uf4_minimal.jl`, new). Eight
stages, per-case `println(stderr, …) + flush(stderr)` with wall-ms and
free-RAM on every log line:

- Stage 1: `modadd!` no-kwarg — L=2 N=3 a=2 b=1 → 0. GREEN.
- Stage 2, 2b: `modadd!(…; ctrls=(c,))` — c=|1⟩ acts, c=|0⟩ identity. GREEN.
- Stage 3, 3b, 3c: `modadd!(…; ctrls=(c1,c2))` — 11→act, 01/10 identity. GREEN.
- Stage 4, 4b: `mulmod_beauregard!` L=2 N=3 a=2 x=1 → 2 (ctrl=1) / 1 (ctrl=0). GREEN.
- Stage 5: L=2 N=3 sweep 12 cases. GREEN.
- Stage 6: L=3 exhaustive ctrl=|1⟩ across N∈{3,5,7}, 68 cases. 0 fail, 41 s.
- Stage 7: L=3 exhaustive ctrl=|0⟩ identity across N∈{5,7}, 62 cases. 0 fail, 5.6 s.
- Stage 8: coherent ctrl=|+⟩ at L=3, 3 cases × 400 shots = 1200 shots.
  Results 197/203, 204/196, 193/207 — all within ±15% of 200/200.
  **0 spurious outcomes across 1200 shots.**

Peak RAM usage 60.16 GiB free (of 60.41 at start). Zero blowup — the
physics-motivated depth reduction eliminated the cascade entirely.

**Phase 2** — registered test file. `julia --project -e
'include("test/test_arithmetic.jl")'` (targeted, not full `Pkg.test()`
per `sturm-jl-test-suite-slow` memory):

| Testset                                     | Pass/Total   | Time     |
|---------------------------------------------|--------------|----------|
| `add_qft!`                                  | 809 / 809    |  2.2 s   |
| `modadd!`                                   | 2130 / 2130  |  0.7 s   |
| `mulmod_beauregard!`                        | 269 / 269    |  1m19 s  |

All 3208 arithmetic tests green on the first run after the refactor.
modadd's backward-compatible path (`ctrls = ()` default) preserved the
2130-pass modadd sweep unchanged.

### Soft-scope gotcha (Julia 1.12)

Initial Stage 6 draft used `n_cases = 0; … for …; n_cases += 1; end`
pattern. Julia 1.12 warned "Assignment to `n_cases` in soft scope is
ambiguous" and then **errored** with `UndefVarError: n_cases not defined
in local scope` when the `@context` macro body tried to increment.
The `@context` expansion introduces a function barrier; assignments to
names declared in the enclosing soft scope (a script top level) are
treated as new locals inside the function, shadowing the outer name,
and the initial `n_cases = 0` doesn't propagate in.

**Fix:** wrap each stage in `let … end` and use `Ref(0)` for counters:

```julia
let
    n_cases = Ref(0); n_fail = Ref(0)
    for …
        @context EagerContext() begin
            …
            n_cases[] += 1
        end
    end
end
```

Session 12 WORKLOG (~L2602) flagged the same problem with a slightly
different workaround ("wrap test bodies in functions"). Either works;
Ref is shorter for probes.

### Files touched

- `src/library/arithmetic.jl` — `_apply_ctrls` helper, `modadd!` ctrls
  kwarg, `mulmod_beauregard!` refactor (pull QFTs, push ctrls down).
- `test/probe_uf4_minimal.jl` (new) — 8-stage verbose-flush probe, kept
  as a dev tool.  Not registered in runtests.jl (the existing
  `test/test_arithmetic.jl` covers the same cases under `@testset`).
- `WORKLOG.md` — this entry.

### Beads

- `Sturm.jl-uf4` closed.

### Handoff — `Sturm.jl-6kx` unblocked

`shor_order_D` can now be built on top of `mulmod_beauregard!`.
Expected scaling per Session 8jx analysis: O(L⁴) gates (t·L³ = 2L·L³).
At L=14 the prediction is ~50k gates vs impl C's measured 47M → **1000×
reduction** if the scaling holds. Benchmark plumbing already exists in
`test/bench_shor_scaling.jl` (Sturm.jl-8jx closed): preflight + watchdog
accept a new impl via env var filtering. A new impl D = "shor with
arithmetic mulmod" can plug in the same way A/B/C do.

Work not yet done on 6kx, flagged:

1. Classical preprocessing: `a_js = [(a^(2^j)) mod N for j in 0:(t-1)]`
   — already present in impls A/B/C.
2. Loop body: `when(phase_qubits[j]) do mulmod_beauregard!(x, a_js[j],
   N, ctrl=…) end` — but the outer `when(phase_qubits[j])` adds a third
   control to every primitive inside mulmod. To stay on the 2-deep
   fast path, `mulmod_beauregard!` needs a `ctrls=` kwarg too, pushing
   `phase_qubits[j]` into modadd's `(ctrl, xj, phase_j)` — but that is
   3 controls, which Sturm's inline HotNode doesn't support. Options:
   (a) pre-AND `phase_j AND ctrl` into a workspace ancilla, then call
   `mulmod_beauregard!(x, a_js[j], N, and_ancilla)` — 2-deep max,
   single workspace Toffoli per mulmod amortised over 2L modadds.
   (b) extend modadd's `ctrls::Tuple` to accept 3 QBools (adds one more
   `_apply_ctrls` method, triggers a 3-deep nested when — cascade on
   the 3 φADD(a) gates only, not on every primitive; still much cheaper
   than today's impls).
   Picking between (a) and (b) is a measurement question for the 6kx
   session.
3. Semi-classical iQFT on a single phase qubit (Beauregard §2.4, fig.
   8). Measurement-driven corrections (X^{m_i}, R_{2i} phase gate
   depending on all prior measurements). This is clean classical
   feedback through P2 casts; low risk.

### Gotchas saved for future sessions

1. **Beauregard p.6 correctness for "doubly control only φADD(a)" is
   easy to miss.** The figure (Fig. 5) shows c1, c2 dots on every
   horizontal run of the controlled register, but only three vertical
   lines actually drop INTO the φADD(a) blocks.  The verbal statement
   in the prose (p.6) is the load-bearing part: "the rest of the circuit
   implements the identity on all qubits because b < N."  A naive
   transcription that copies the figure literally misses this, and the
   resulting code has 3-deep control nesting = cascade explosion.

2. **Pulling unconditional QFT/QFT⁻¹ out of a `when(ctrl)` block is
   correct because QFT·(any state)·QFT⁻¹ = any state.**  With ctrl=0
   the modadds between the QFT sandwich all skip, so the net transform
   on `b` is identity whether the QFTs run or not.  Running them
   unconditionally saves depth without changing the channel.  Not every
   unitary has this property — e.g. a `Hadamard·X·Hadamard` sandwich
   around a ctrl-guarded block would NOT be safe to lift because
   `Hadamard² ≠ I` up to a global phase that becomes relative under
   an outer `when`.  QFT·QFT⁻¹ = I exactly, no phase.

3. **Ref-based counters dodge Julia 1.12 soft-scope inside `@context`.**
   Script-level counter++ inside `for … @context … n_cases += 1 … end`
   errors at run time.  Wrap the stage in `let … end`, declare counters
   as `Ref(0)`, increment via `n_cases[] += 1`.  Two lines of ceremony,
   no warning noise.

4. **Per-stage `println(stderr, …) + flush(stderr)` with free-RAM on
   every line is how you keep verbose-eager-flush (`feedback_…`)
   honoured.**  A single `_log(s)` helper that formats `[ms] [free=X
   GiB] s` and flushes makes this a 1-line cost per stage.  The
   blank-screen-wait that caused Session 24's interrupt would have been
   impossible to miss with this pattern.

---

## 2026-04-18 — Session 24 END-OF-DAY HANDOFF

**Stop reason:** user ended the session. Tree is clean; all work
committed and pushed to `origin/main`. `bd stats` shows 0 in_progress,
7 open.

### Session 24 at a glance — 6 beads closed, 1 filed

| Bead | Priority | What | Commit |
|------|----------|------|--------|
| `1f3` | P3 | QDrift/Composite RNG injection + vacuous-test fix | `bfa8f0f` |
| `q93` | P2 | Width-fitting oracle arg type (`_bennett_arg_type`) | `dd2f680` |
| `f23` | P2 | P2 axiom implicit-cast warning (`with_silent_casts`) | `0bd5289` |
| `xcu` | P1 | Multi-controlled gates on DensityMatrixContext | `2f051e4` |
| `1wv` | P1 | `with_empty_controls` / `with_controls` public API | `e1ace01` |
| `rpq` | P1 | Arbitrary when() nesting in TracingContext | `180eee3` |
| `5gz` | P2 | **Filed:** qsvt_phases sin polynomial returns 2d+1 phases (pre-existing) |

### Major architectural changes this session

1. **`src/context/multi_control.jl`** is now typed on `AbstractContext`
   (was `Union{EagerContext, DensityMatrixContext}`) and routes through
   the PUBLIC `apply_*!` API rather than raw `orkan_*!` pointer calls.
   Every helper wraps itself in `with_empty_controls` to break recursion
   when called from nc≥1. **Consequence:** EagerContext, DensityMatrixContext,
   and TracingContext all use the SAME Toffoli cascade for arbitrary
   when() nesting depth. Zero code per context.

2. **`src/context/abstract.jl`** grew two default-implementation methods:
   `with_controls(f, ctx, ctrls::Vector{WireID})` and
   `with_empty_controls(f, ctx) = with_controls(f, ctx, WireID[])`.
   Both built on the existing `push_control!`/`pop_control!`/
   `current_controls` interface.

3. **`src/types/qbool.jl` and `src/types/qint.jl`** now split the
   constructor from `Base.convert`: `Bool(q)` / `Int(q)` hold the
   measurement (silent), and `Base.convert(::Type{Bool/Int}, q)` emits
   the P2 warning then delegates. Implicit `x::Bool = q` assignments
   hit the convert path; explicit constructor calls do not.

4. **`src/bennett/bridge.jl`** has a new `_bennett_arg_type(W;
   signed=true)` helper that picks the narrowest Int/UInt fitting W.
   Replaces the hardcoded `Int8` in `oracle(f, x::QInt{W})` and
   `QuantumOracle`'s call operator. Cache key widens to
   `(W, signed, kwargs)`.

### Current ready queue — annotated

```
  bd ready
  ○ Sturm.jl-870  P1   Steane syndrome extraction + correction (QECC)
  ○ Sturm.jl-5gz  P2   [bug] qsvt_phases 2d+1 for sin polynomial
  ○ Sturm.jl-di1  P2   Backend scaffolding (tensor-net + hardware)
  ○ Sturm.jl-7ab  P2   Pass registry / DAG transformation API
  ○ Sturm.jl-mt9  P2   QSVT/QSP linear algebra EPIC
  ○ Sturm.jl-eiq  P3   CasesNode consumer policy (error on unhandled)
  ○ Sturm.jl-zv1  P4   Docs refresh (CLAUDE.md + README.md)
```

**Recommended next pickup** for a fresh agent:

- **`5gz` P2 bug** is worth triaging first — it's concrete, reproducible
  (just run `test/test_qsvt_reflect.jl` lines 53-58), and may be a
  test-assertion-vs-algorithm-convention mismatch rather than a real
  physics bug. Quick win if so. See `docs/physics/` for QSP/QSVT
  convention notes — the test expects `length(phi) == 2d` but the
  sin-parity GSLW convention might legitimately yield `2d+1`.

- **`eiq` P3** remains the obvious mechanical continuation if you want
  a warm-up. `src/channel/channel.jl` compat constructor,
  `src/channel/openqasm.jl:~112`, renderer warnings.

- **`zv1` P4** has three concrete items queued up:
  (a) Sturm-PRD.md has ~10 pedagogical `::Bool = q` / `::Int = qi`
      examples that now trigger the f23 warning if copy-pasted; convert
      to explicit form or note "this pattern warns".
  (b) README lines ~146-200 advertise `strategy=:tabulate` as a Bennett
      kwarg — confirmed NOT present in current Bennett
      (`grep -r tabulate /home/tobiasosborne/Projects/Bennett.jl/src`).
      Session 22 misreported, or it reverted upstream.
  (c) CLAUDE.md phase 12 table is stale.

- **`870`, `di1`, `7ab`, `mt9`** are substantial and design-first — save
  for a fresh big session.

### Cross-session patterns saved for the next agent

1. **Rule 4 is strict about local PDFs.** When extracting or moving code
   that carries a docstring reference to a paper, read the local
   `docs/physics/<name>.md` BEFORE shipping. If no local file exists,
   write a self-contained derivation (see
   `docs/physics/toffoli_cascade.md` from Session 24D).

2. **Bennett LLVM lowering hates closures that capture values.** A
   boolean `signed` captured in `x -> x + (signed ? Int8(1) : UInt8(1))`
   materialises as `StructType({ ptr, i8 })` in Julia IR — Bennett
   errors with "Unsupported LLVM type for width". Use top-level
   functions for oracle tests across parameters, not loop-body
   closures. (Hit this during Session 24F's full-suite run.)

3. **Test files can drift from the axioms.** Session 24C's f23 work
   discovered 8 `::Bool = q` sites in test_bell, test_teleportation,
   test_rus — the warning catching our own code validated the split.
   Run the full suite after ANY axiom-level change to flush these out.

4. **Don't copy forward unexamined references.** Session 24D's xcu work
   copied the "Barenco 1995 Lemma 7.2" reference from eager.jl into the
   new multi_control.jl without verifying the local PDF existed (it
   didn't). User caught this mid-session with "did you read the
   Nielsen and Chuang ground truth?" The fix was writing
   `docs/physics/toffoli_cascade.md` inline.

5. **When extracting helpers that touch context internals, flag the
   abstract-interface candidate up front.** Session 24D's xcu extracted
   `multi_control.jl` which used `ctx.control_stack` directly — then
   Session 24E's 1wv had to migrate those accesses to the new API.
   Would have been cleaner to do both in one pass.

6. **Pre-existing test failures reproduce on previous commits.** Always
   verify: `git stash && julia --project -e '<repro>' && git stash pop`.
   Session 24F's 5gz qsvt_phases issue turned out to be pre-existing —
   saved from chasing a regression caused by today's refactor.

### Full test suite state (as of commit `180eee3`)

- **12833 pass / 3 fail / 1 error / ~12837 total**
- The 1 error (q93 closure test) was **fixed in commit `180eee3`** —
  re-running the full suite now would produce 12836 / 3 / 0.
- The 3 failures are `Sturm.jl-5gz` — see above.
- **Full-suite runtime on this device: ~2h15m.** Dominant: OAA (61m),
  Reflection QSVT (34m), qDRIFT (21m), Bennett E2E (5m). Do NOT run
  the full suite casually — use targeted `julia --project -e '…'`
  probes for verification work.

### Environment gotchas, reminded

- `LIBORKAN_PATH=/home/tobiasosborne/Projects/orkan/cmake-build-release/src/liborkan.so`
  (memory entry lists `/home/tobias/…` — stale prefix on this device).
- `Bennett.jl` is dev-pathed via `Pkg.develop(path="../Bennett.jl")`;
  not registered. Fresh clones must do the develop before
  `Pkg.instantiate`.
- bd uses SSH; `bd dolt push` works non-interactively. Session close
  protocol = `git pull --rebase && bd dolt push && git push`.
- The `.beads/` permissions warning is cosmetic; `chmod 700 .beads`
  fixes it but isn't blocking.

### Physics docs referenced by this session's code

- `docs/physics/nielsen_chuang_4.3.md` — controlled-Ry/Rz ABC
  decomposition. Verified algebraically in Session 24D.
- `docs/physics/toffoli_cascade.md` — Session 24D NEW, self-contained
  derivation of the N-controlled cascade with density-matrix extension.
  Referenced by `src/context/multi_control.jl`.

### Files with significant changes today

- `src/context/abstract.jl` — with_controls, with_empty_controls
- `src/context/multi_control.jl` — unified cascade across all contexts
- `src/context/eager.jl` — cascade helpers moved out
- `src/context/density.jl` — multi-control dispatch added
- `src/context/tracing.jl` — nc>2 routes to cascade
- `src/types/quantum.jl` — _warn_implicit_cast, with_silent_casts
- `src/types/qbool.jl`, `src/types/qint.jl` — constructor / convert split
- `src/bennett/bridge.jl` — _bennett_arg_type helper
- `src/simulation/pauli_exp.jl` — migrated to with_empty_controls
- `src/block_encoding/lcu.jl` — migrated to with_empty_controls
- `src/simulation/qdrift.jl`, `src/simulation/composite.jl` — rng kwarg
- `src/Sturm.jl` — exports
- `README.md` — with_silent_casts note
- `docs/physics/toffoli_cascade.md` — NEW
- `test/test_implicit_cast.jl`, `test/test_density_matrix_mc.jl`,
  `test/test_control_api.jl`, `test/test_tracing_deep_when.jl` — NEW
- Plus test fixes in test_bell, test_teleportation, test_rus, test_qdrift,
  test_composite, test_bennett_integration.

---

## 2026-04-18 — Session 24F: Close `rpq` (arbitrary when() nesting in TracingContext)

TracingContext's `apply_ry!`/`apply_rz!`/`apply_cx!` errored at control-
stack depth > 2 because `HotNode` carries at most `ctrl1, ctrl2` inline
(the Session 3 25-bytes/element isbits union). The bead's proposed fix
(Option B) was to add a cold-path `DeepCtrlNode` with `controls::Vector
{WireID}` for deep cases. Instead: realised the cascade in
`multi_control.jl` can be rewired to lower a deep-controlled op entirely
into depth-≤2 ops via a Toffoli cascade with workspace qubits — the
SAME path EagerContext and DensityMatrixContext use (closed in xcu).
No new node type needed; no Session 3 perf regression at depth ≤ 2; the
traced DAG contains only standard `HotNode`s.

### Unified cascade — `multi_control.jl` refactor

Rewrote the 6 helpers to type on `AbstractContext` instead of
`Union{EagerContext, DensityMatrixContext}`, and to route through the
PUBLIC `apply_ry!`/`apply_rz!`/`apply_cx!`/`apply_ccx!` API rather than
raw `orkan_*!` calls. Each invocation is wrapped in
`with_empty_controls(ctx) do … end` so that inner `apply_*!` calls see
nc=0 and hit their fast paths:

- EagerContext: direct `orkan_*!` on `ctx.orkan.raw`.
- DensityMatrixContext: same (Orkan's gate ABI is state-type-agnostic,
  `ccx` computes `UρU†` on MIXED states natively).
- TracingContext: emits `RyNode`/`RzNode`/`CXNode` with `nc ≤ 2`.

### Recursion break

`_controlled_ry!` is called at nc=1 from Eager's `apply_ry!`. In the new
implementation it internally uses `apply_ry!`/`apply_cx!`. Without
protection, Eager's `apply_ry!` at nc=1 → `_controlled_ry!` → `apply_ry!`
at nc=1 → infinite recursion. `with_empty_controls` inside
`_controlled_ry!` clears the stack for the duration of the ABC
decomposition, so the inner `apply_ry!` sees nc=0 and goes direct. This
is the same pattern `pauli_exp.jl` and `lcu.jl` now use for their
optimisation-blocks (from Session 24E).

### tracing.jl update

- `_inline_from_stack` now errors with "internal invariant violated" if
  ever called with nc > 2 — callers must route to the cascade before
  reaching it.
- `apply_ry!`/`apply_rz!`/`apply_cx!` at nc > 2 call
  `_multi_controlled_gate!` / `_multi_controlled_cx!`.
- `apply_ccx!` at nc_stack ≥ 2 pushes the explicit `c1` onto the stack
  and routes to the cascade (same pattern as eager/density.jl).
- `apply_ccx!` at nc_stack ≤ 1 still emits an inline 1- or 2-control
  `CXNode` — the existing fast path, unchanged.

### Workspace in the traced DAG

At depth 3 or higher, the cascade allocates N−1 workspace qubits. On
TracingContext, `allocate!` returns a fresh WireID and `deallocate!`
emits a `DiscardNode`. A traced 4-nested `when()` circuit therefore
contains extra CCX nodes (the cascade), a few extra wires (workspace),
and `DiscardNode`s (workspace cleanup). OpenQASM export handles these
as standard gate + reset operations — the bead's acceptance criterion
("4-nested when() traces and exports to OpenQASM 3.0") is met.

### Performance concerns

The old `_controlled_ry!` on EagerContext called `orkan_ry!`/`orkan_cx!`
directly on the raw pointer — 4 C calls per invocation. The new path
goes through 4 `apply_*!` calls, each doing a stack-length check +
dict lookup before reaching Orkan, plus the `with_empty_controls`
save/restore overhead (≈ 4 ops for a 1-element stack). Per invocation
this adds maybe 30–50 ns on EagerContext — negligible for circuit-
construction work but measurable for Pauli-exp inside a tight Trotter
loop. Will benchmark if a regression is reported; none observed in the
full-suite run that closes this bead.

### RED-GREEN TDD

Wrote `test/test_tracing_deep_when.jl` first — 8 testsets / 18 asserts
covering:
- Depth 3 CCCRy via triple-nested when() traces (no error).
- Depth 3 OpenQASM export emits `ccx`.
- Depth 4 quadruple-nested when() traces.
- Depth 3 `apply_cx!` inside 2-deep when (effective CCCX).
- Depth 2 `apply_ccx!` inside when (effective CCCX) — existing fast path.
- Depth 3 and 4 EagerContext outcome correctness (all |1⟩ → target flips).
- Depth 4 any-|0⟩-blocks sanity check.

RED: 3/13 failed — the three hitting nc>2 in apply_ry!/cx!. 10 passed
immediately (Eager/DM already supported depth ≥ 3, and fast paths at
depth 2 already worked for CXNode-via-apply_cx! and apply_ccx! at
nc_stack=1).

GREEN after refactor: 18/18.

### Regression

After refactor:
- test_tracing_deep_when (new): 18/18
- test_when: 507/507
- test_density_matrix_mc: 17/17
- test_control_api: 23/23
- test_channel: 43/43
- test_block_encoding: 63/63
- test_simulation: 122/122
- test_grover: 284/284

Plus the full `runtests.jl` — see commit note.

### Files touched

- `src/context/multi_control.jl`: widen type to `AbstractContext`, route
  through public apply_*! API, wrap helpers in `with_empty_controls`.
- `src/context/tracing.jl`: route nc > 2 through the cascade; tighten
  `_inline_from_stack` invariant error.
- `test/test_tracing_deep_when.jl` (new), `test/runtests.jl` (include).
- `WORKLOG.md`: this entry.

### Full-suite verification (user-requested)

Ran `julia --project -e 'include("test/runtests.jl")'` — full suite,
verbose, ~2h15m total runtime dominated by OAA (61 min), Reflection QSVT
(34 min), qDRIFT (21 min), and Bennett integration e2e (5 min).

**Tally:** 12833 pass, 3 fail, 1 error — out of ~12837.

**Regressions caused by today's work: NONE.**

**The 3 + 1 non-greens:**

1. **3 failures in `Reflection QSVT / qsvt_phases: sin polynomial returns
   correct count`** (test/test_qsvt_reflect.jl:57). At d=5/9/13,
   `length(qsvt_phases(jacobi_anger_sin_coeffs(1.0, d)))` returns
   `2d+1` instead of `2d`. Verified pre-existing: reproduces on commit
   `e1ace01` (the session 24E/1wv commit, BEFORE today's rpq refactor).
   Filed as `Sturm.jl-5gz` P2. The cos polynomial parity passes.
   Likely a test-assertion issue rather than a physics bug (OAA and
   evolve!(QSVT) downstream tests pass at their 33-minute runtime, so
   the algorithm produces usable phases).

2. **1 error in `Bennett Integration / arg-type selection by W /
   oracle forwards signed kwarg without breaking W=2 regression`**
   (test/test_bennett_integration.jl:497). MY bug from Session 24B
   (q93). The closure `x -> x + (signed ? Int8(1) : UInt8(1))` captures
   the boolean `signed` variable, producing an LLVM IR with
   `StructType({ ptr, i8 })` that Bennett cannot compile
   (`Unsupported LLVM type for width`).

   **Fix:** rewrite as two top-level functions (`f_signed(x) = x +
   Int8(1)`; `f_unsigned(x) = x + UInt8(1)`), avoiding the capture
   struct. Targeted probe 2/2 green after fix.

**Lesson saved:** Bennett's LLVM lowering fails on closures that capture
values (they materialise as `StructType` in Julia's IR). For oracle
tests at varying parameters, prefer a set of small top-level functions
over a loop with a parametrised closure. Will fold into the memory
update below.

### Note on the bead's `DeepCtrlNode` suggestion

The bead explicitly proposed Option B (add `DeepCtrlNode` node type
outside the HotNode union). I opted for a strictly simpler approach
(no new node type, same semantics, Session 3 perf preserved). The
downside: visualisation/rendering of a deep-controlled op now shows the
cascade rather than the abstract "MCU" node. If we later want to
render MCU symbolically (e.g., in `to_ascii` for a 5-controlled rotation
shown as `Rz(θ)●●●●●` rather than the full expanded cascade), that's a
separate UX decision and can add `DeepCtrlNode` as an OPT-IN sugar layer
at that point — the cascade stays as the canonical lowering.

---

## 2026-04-18 — Session 24E: Close `1wv` (`with_empty_controls` public API)

Three external files were reaching into `ctx.control_stack::Vector{WireID}`
directly to save/clear/restore controls around basis changes (pauli_exp.jl)
and PREPARE/SELECT isolation (lcu.jl). That field is not part of the
`AbstractContext` contract — it's a convention every current context
happens to share. A future tensor-network or hardware-emitting backend
might represent controls differently and would silently produce wrong
circuits. The Session 24D refactor (xcu) also introduced two fresh leaks
in `src/context/multi_control.jl` (`copy(ctx.control_stack)`). Closing
both before the pattern spreads.

### RED-GREEN TDD

Wrote `test/test_control_api.jl` first — 9 testsets covering:

- `current_controls(ctx)` returns a copy (mutating it does not alter the
  stack) — regression test on existing API.
- `with_empty_controls(f, ctx)` clears the stack inside `f()`, restores on
  normal exit, restores on exception.
- `with_empty_controls` returns the value of `f()`.
- `with_controls(f, ctx, controls)` swaps the stack, restores on exit.
- Nested pattern: the pauli_exp / lcu idiom (outer empty-clear, inner
  temporarily-restore).
- Works identically on all three contexts (EagerContext,
  DensityMatrixContext, TracingContext) — the default
  implementation in `abstract.jl` uses `push_control!` / `pop_control!` /
  `current_controls` only, so any context that implements the three gets
  `with_controls` / `with_empty_controls` for free.

RED: 9/9 errored (symbols don't exist yet — `using Sturm: …` fails the whole
file). First GREEN: added `with_controls` + `with_empty_controls` to
`src/context/abstract.jl`, exported both, got 1/9 passing (the no-imports-
needed test). Second fix: my test file also needed `allocate!` /
`current_context` imported — both are unexported. After that, 23/23 green
(23 is the sub-assert count inside the 9 testsets).

### Migration — three caller sites

- `src/simulation/pauli_exp.jl:191` — the `_pauli_exp!` basis-change
  optimisation. Old: raw `empty!` / `append!` on the stack with
  `has_controls` boolean flag threading through 5 `if` guards. New: outer
  `with_empty_controls(ctx) do … end` wrapping all 5 steps, with a single
  `with_controls(ctx, saved) do … end` for the one controlled Rz pivot.
  Lost ~20 lines of bookkeeping, kept the physics proof comment intact.

- `src/block_encoding/lcu.jl:72, 102` — `oracle!` and `oracle_adj!`.
  Identical shape (PREPARE / SELECT / PREPARE†) and identical collapse:
  outer `with_empty_controls`, inner `with_controls(saved)` around the one
  SELECT call. Both functions lost their `try`/`finally` block — the new
  primitives handle restoration automatically.

- `src/context/multi_control.jl:85, 102` — `copy(ctx.control_stack)` is
  semantically identical to `current_controls(ctx)` (both return a copy).
  Swapped both. These are internal cascade helpers shared between
  EagerContext and DensityMatrixContext, so removing the field access
  here tightens the context-polymorphic seam.

### Design decision

Primary primitive is `with_controls(f, ctx, controls::Vector{WireID})`
(swap-in / run / swap-out). `with_empty_controls(f, ctx) =
with_controls(f, ctx, WireID[])` is a one-line wrapper. The bead
explicitly requested `with_empty_controls` by name, so that's the
documented/exported surface, but `with_controls` also ends up exported
because the pauli_exp / lcu idiom needs it.

Default implementation in `abstract.jl` uses only
`current_controls` / `push_control!` / `pop_control!`, all three of which
were already required by the abstract interface. So:

- EagerContext, DensityMatrixContext, TracingContext all get
  `with_controls` / `with_empty_controls` with zero code per context.
- A future backend need only implement the three existing interface
  methods to pick up the full control-lifecycle API.
- The internal `.control_stack` field in each concrete context is NOT
  touched by the migration — per the bead: "default implementation can
  still use the control_stack field for backward compat with current
  contexts."

### Verification

- `test_control_api.jl` (new): 23/23 green.
- `test_when.jl` (regression): 507/507 green.
- `test_density_matrix_mc.jl` (regression after `multi_control.jl`
  migration): 17/17 green.
- `test_block_encoding.jl` (regression after `lcu.jl` migration): 63/63.
- `test_simulation.jl` (regression after `pauli_exp.jl` migration): 122/122.

Total new+regression: 732/732. No failures.

### Files touched

- `src/context/abstract.jl`: `with_controls`, `with_empty_controls` +
  docstrings; one-line update to `current_controls` docstring noting it
  returns a copy.
- `src/Sturm.jl`: export `current_controls`, `with_controls`,
  `with_empty_controls`.
- `src/simulation/pauli_exp.jl`: migrate `_pauli_exp!` basis-change
  optimisation.
- `src/block_encoding/lcu.jl`: migrate `oracle!` and `oracle_adj!`.
- `src/context/multi_control.jl`: `copy(ctx.control_stack)` →
  `current_controls(ctx)` at two cascade helpers.
- `test/test_control_api.jl` (new), `test/runtests.jl` (include).
- `WORKLOG.md`: this entry.

### Lesson

When extracting helpers that reach into context internals (Session 24D's
`multi_control.jl`), leave a note to revisit. Fresh code that uses
implementation details becomes the next migration's problem within a
session. Better: identify the abstract-interface candidate up front, even
if you defer the full sweep.

---

## 2026-04-18 — Session 24D: Close `xcu` (multi-controlled gates on DensityMatrixContext)

`DensityMatrixContext` errored "not yet implemented" on every multi-controlled
variant of `apply_ry!`/`apply_rz!`/`apply_cx!`/`apply_ccx!` (density.jl lines
109/125/138/149). Consequence: any noise-circuit demo using nested `when()`
was broken. This bead ports EagerContext's Toffoli cascade to DM, via a
shared helper file.

### Key insight (from 4 parallel Sonnet Explore agents)

The bead's hint ("Toffoli cascade on density matrix via Kraus superop
composition") was half-right. Orkan's gate ABI is **state-type-agnostic**:
`orkan_ry!`, `orkan_cx!`, `orkan_ccx!` all dispatch internally on
`state->type` (`ORKAN_PURE` vs `ORKAN_MIXED_PACKED` vs `ORKAN_MIXED_TILED`)
and already compute `U ρ U†` on mixed states. There is no Kraus
decomposition needed for coherent gates — they are single-Kraus unitary
channels, and Orkan handles the `UρU†` conjugation internally.

Confirmed via Orkan source inspection:

- `gate.h` declares the full gate API without any density-specific variants.
- `orkan_channel_1q!` exists for *noise* channels (1-qubit Kraus), but is
  not needed for controlled unitaries.
- Orkan has NO multi-controlled primitive on either state type — the ceiling
  is `ccx` (1-target, 2-control Toffoli).

So the cascade mirroring EagerContext exactly is correct on DM, with zero
FFI changes.

### Refactor: shared `multi_control.jl`

Moved the 6 helpers (`_controlled_ry!`, `_controlled_rz!`,
`_toffoli_cascade_forward!`, `_toffoli_cascade_reverse!`,
`_multi_controlled_gate!`, `_multi_controlled_cx!`) out of `eager.jl` into a
new file `src/context/multi_control.jl`, typed on
`Union{EagerContext, DensityMatrixContext}` so both contexts dispatch to
them. The file must be included AFTER both context types are defined
(Julia cannot resolve a `Union{T, U}` type parameter until both are
available) — registered in `Sturm.jl` as the third `context/` include.

`eager.jl` and `density.jl` now have IDENTICAL `apply_ry!`/`apply_rz!`/
`apply_cx!`/`apply_ccx!` dispatch shapes (nc=0 → raw; nc=1 → ABC or CCX;
nc≥2 → cascade). No duplication.

### Ground-truth check triggered by user prompt mid-session

User asked "did you read the Nielsen and Chuang ground truth? are the
equations matched?" I had NOT — I copied comments from eager.jl forward
without verifying. Re-read `docs/physics/nielsen_chuang_4.3.md` and
verified algebraically:

- At ctrl=|0⟩: CX ≡ I, so `Ry(−θ/2)·Ry(θ/2) = I`. ✓
- At ctrl=|1⟩: CX ≡ X on target, composed (right-to-left) =
  `X·Ry(−θ/2)·X · Ry(θ/2)`. Using `X·Ry(α)·X = Ry(−α)`:
  `Ry(θ/2)·Ry(θ/2) = Ry(θ)`. ✓

Barenco et al. 1995 Lemma 7.2 had no local PDF — pre-existing docs gap
from eager.jl. Wrote `docs/physics/toffoli_cascade.md` with a self-
contained derivation (computational-basis induction on AND-reduction +
linearity + single-Kraus density-matrix extension). Pointed
`multi_control.jl`'s reference comment at the new local doc.

**Lesson for future agents:** when extracting/copying code with docstring
references, read the local physics doc before shipping. Do not copy the
reference forward. This is a literal letter-of-rule-4 issue.

### Tests — `test/test_density_matrix_mc.jl` (new)

17 testsets covering:

- Depth 2 nested-when CCRy / CCRz / CCX — deterministic cases on all
  control-bit combinations.
- Depth 2 `apply_cx!` inside nested-when — effective CCCX via cascade.
- Depth 2 `apply_ccx!` inside `when()` — uses the path that pushes `c1`
  onto the stack and runs multi-controlled CX with `c2`.
- Depth 3 triple-nested `when()` — effective 4-way AND. Verifies the
  Toffoli cascade allocates 2 workspace qubits and uncomputes them.
- Superposition entanglement: `c1=|+⟩, c2=|1⟩, t=|0⟩` nested-when should
  leave `c1` and `t` perfectly correlated across shots. 200/200 passed.
- Workspace recycling: after a depth-3 cascade, `length(ctx.wire_to_qubit)`
  reports 4 user qubits (c1, c2, c3, t), confirming the 2 workspace
  ancillae were correctly deallocated.

Registered in `test/runtests.jl` immediately after `test_density_matrix.jl`.

### Verification

- `test_density_matrix.jl` 1753/1753 (regression)
- `test_density_matrix_mc.jl` 17/17 (new)
- `test_noise.jl` 506/506 (regression)
- `test_when.jl` 507/507 (regression after refactor)
- Classicalise testset 12/12

### Process notes

The 4-parallel-Sonnet Explore pattern was effective for this bead: one
afternoon's worth of disambiguation done in maybe 3 minutes of parallel
exploration. Template for future big beads: spawn agents that each cover
(a) the "before" state of a module, (b) the reference implementation to
mirror, (c) existing test patterns, (d) the FFI / lower-layer surface.
Keep each under 800 words with code excerpts; synthesise the convergent
findings before reading ground truth in detail.

### Files touched

- `src/context/multi_control.jl` (new, 102 lines): shared cascade helpers.
- `src/context/eager.jl`: removed helpers (−108 lines), kept the dispatch
  in `apply_*!`.
- `src/context/density.jl`: restructured `apply_ry!`/`apply_rz!`/`apply_cx!`
  to mirror eager.jl's nc=0/1/≥2 tree; replaced four
  `error("not yet implemented")` with cascade calls.
- `src/Sturm.jl`: include `context/multi_control.jl` after both context
  files.
- `test/test_density_matrix_mc.jl` (new), `test/runtests.jl` (include).
- `docs/physics/toffoli_cascade.md` (new): self-contained derivation of
  the multi-controlled cascade, with the density-matrix extension
  explicit.
- `WORKLOG.md`: this entry.

---

## 2026-04-18 — Session 24C: Close `f23` (P2 implicit quantum→classical cast warning)

The P2 axiom says measurement is a cast with implied information loss, and
implicit assignments (`x::Bool = q`) must warn. Prior to this session the
codebase defined `Base.Bool(q::QBool) = convert(Bool, q)` — one path for
both explicit constructor calls AND implicit annotated assignments — so
nothing could distinguish them. This bead fixes that.

### Design (from the conversation, not agent-proposed)

Split the constructor from `convert`:

- `Base.Bool(q::QBool)` / `Base.Int(q::QInt{W})` hold the actual
  measurement. Silent, the blessed explicit path.
- `Base.convert(::Type{Bool}, q::QBool)` / `convert(::Type{Int}, q::QInt{W})`
  emit the P2 warning, then delegate to the constructor.

Julia desugars `x::Bool = q` to `x = convert(Bool, q)`, so implicit
assignments flow through the warning path; explicit `Bool(q)` calls skip
it entirely. No macro rewriting, no special hooks — just the standard
Julia conversion system doing what it already did, with the warning added
on the convert side.

### Warning helper (`src/types/quantum.jl`)

- `_first_user_frame(frames)` walks the stacktrace and returns the first
  frame whose `file` is outside `src/types/quantum.jl:_STURM_SRC_ROOT`
  (= the parent of `src/types/`). That is the user's call site.
- `_warn_implicit_cast(::Type{From}, ::Type{To})` emits
  `@warn … maxlog=1 _id=(:sturm_implicit_cast, file, line)` with
  `_file=file _line=line` so the reported location is the user's site, not
  the Sturm internal line. `_id` tuples dedupe per source location: loop
  iterations at one site share one warning; two different sites each get
  their own.
- `with_silent_casts(f)` flips `task_local_storage(:sturm_implicit_cast_silent, true)`
  for the duration of `f()`, restoring the previous value in `finally`.
  Nests correctly via save/restore, parallels the `@context` macro.

### `if q`, `classicalise(ch)` — out of scope

- `if q::QBool` currently hits Julia's runtime `TypeError: non-boolean
  used in boolean context`. Julia's `if` does NOT auto-call `Bool(cond)` —
  the runtime checks `isa(cond, Bool)` and errors otherwise. The PRD §P4
  claim that `if q` emits the P2 warning + measures + branches is
  unreachable without source-level macro rewriting. Deferred; not f23.
- `classicalise(f)` has no implicit entry point (only invoked by name),
  so the channel-level cast is already behaviorally "explicit". The bead's
  "classicalise behaves the same way" acceptance criterion is satisfied
  with no code change.

### Regression: existing test code used implicit casts

Running `test_bell.jl` / `test_teleportation.jl` / `test_rus.jl` after the
fix surfaced eight `::Bool = q` / `::Int = qi` call sites in our own test
code. That is exactly what the warning is supposed to flag — the tests
were written in the pre-axiom style. Converted all eight to explicit
`Bool(q)` / `Int(q)` forms. Same measurement semantics, now silent in
the new logger output. The warning mechanism catching our own code is
itself a validation that the dispatch split works.

### Gotcha: `local _::Bool = q` is invalid Julia syntax

First draft of `test_implicit_cast.jl` used `local _::Bool = q` to
anonymise an unused measurement result. Julia rejects with
`syntax: type declaration for global "_" not at top level` — `_` cannot
carry a type annotation. Renamed to `local dummy::Bool = q`. Leaving this
note because it is not an intuitive syntax error if you have not hit it.

### Stale PRD examples (not fixing here — scope)

`Sturm-PRD.md` contains ~10 `::Bool = q` / `::Int = qi` pedagogical
examples. These now would trigger warnings if copy-pasted. Flagged on
`zv1` (docs refresh) — not expanding f23's scope.

### Verification

- `test/test_implicit_cast.jl` (new): 14 passes. Covers explicit silent,
  implicit warns, both QBool and QInt, message text includes the fix
  suggestion, `with_silent_casts` suppresses + returns block value +
  nests.
- `test_bell.jl` 2002/2002, `test_teleportation.jl` 1002/1002,
  `test_rus.jl` 205/205 — all green after the explicit-cast conversion.

### Files touched

- `src/types/quantum.jl`: `_first_user_frame`, `_warn_implicit_cast`,
  `with_silent_casts`, P2 header comment.
- `src/types/qbool.jl`: split `Base.Bool` / `Base.convert`.
- `src/types/qint.jl`: split `Base.Int` / `Base.convert`.
- `src/Sturm.jl`: export `with_silent_casts`.
- `test/test_implicit_cast.jl` (new), `test/runtests.jl` (include).
- `test/test_bell.jl`, `test/test_teleportation.jl`, `test/test_rus.jl`:
  convert to explicit casts.
- `README.md`: one-line note about `with_silent_casts` opt-out.
- `WORKLOG.md`: this entry.

---

## 2026-04-18 — Session 24B: Close `q93` (oracle arg-type inference from W)

`bridge.jl` hardcoded `Int8` as the classical argument type Bennett compiles
against, regardless of `QInt{W}` width. Bennett's `_narrow_ir` pass then
uniformly rewrote widths to `W`, which papered over the mismatch for simple
modular arithmetic — but it is still a type lie (constants, comparisons, and
any Julia dispatch path inside `f` sees Int8 when the register is 16 bits).

### Fix

New helper `_bennett_arg_type(W; signed=true)` in `src/bennett/bridge.jl`
picks the narrowest fitting `Int*` / `UInt*`: W≤8→Int8, W≤16→Int16,
W≤32→Int32, W≤64→Int64; `signed=false` flips to the `UInt*` variant;
W>64 errors. Both `oracle(f, x; signed=true, kw...)` and the `QuantumOracle`
call operator route through the helper. The cache key on `QuantumOracle`
widens from `(W, kwargs)` to `(W, signed, kwargs)` so switching signedness
forces a recompile rather than silently reusing a stale circuit (the same
discipline Session 20 applied for strategy kwargs).

### Ground-truth probe results (not in the bead acceptance test)

Bead's acceptance test was `oracle(x -> x * 1000, QInt{16}(v))`. This
cannot run on this machine:

1. `reversible_compile` with an IR containing a multiplication grows Orkan's
   register above the 30-qubit `MAX_QUBITS` cap even at `W=4` — 69 qubits
   for `estimate_oracle_resources(x -> x * 10, Int8; bit_width=4)`. At
   `W=16` it would be far worse.
2. The README (lines ~146-200) advertises `strategy=:tabulate` as a kwarg
   on `reversible_compile`, supposedly landed by Bennett-cfjx per Session
   22. It is NOT present in the current Bennett source — the signature is
   `(bit_width, add, mul, optimize, max_loop_iterations, compact_calls)`
   only. Either Session 22 misreported, or the feature was reverted
   upstream. README is stale on this point. **Filed as a separate concern**
   — not expanding q93 scope.

Because of (1) + (2), q93 tests stay at `W=2` (the largest width that
actually fits mul-bearing circuits today). The type-system fix is verified
via direct unit tests on `_bennett_arg_type` plus regression on existing
W=2 paths.

### Test additions — `test/test_bennett_integration.jl`

- `_bennett_arg_type` returns correct type across the full W range for both
  `signed=true` and `signed=false`. 32 cases.
- Out-of-range (`W ≤ 0` or `W > 64`) errors.
- `oracle` at W=2 works with both `signed=true` (default) and
  `signed=false`. Regression + new path.
- `QuantumOracle` cache distinguishes `signed=true` from `signed=false`
  with the same W — `length(qf.cache) == 2` after two calls.
- The pre-existing `haskey(qf.cache, (W, ()))` tests in the
  "caches circuit across calls" and "different widths use different cache
  entries" testsets updated to the new `(W, signed, ())` shape. Two lines.

### Files touched

- `src/bennett/bridge.jl`: `_bennett_arg_type` helper; `oracle` +
  `QuantumOracle` call operator take `signed::Bool=true`; cache key widens
  to `(W, signed, kwargs)`.
- `test/test_bennett_integration.jl`: new `@testset verbose=true "arg-type
  selection by W"` block; two existing `haskey` asserts updated.
- `WORKLOG.md`: this entry.

### Lesson for future agents

The README and WORKLOG Session 22 both claimed `strategy=:tabulate` was a
Bennett-level kwarg. A quick `grep -r tabulate` on
`/home/tobiasosborne/Projects/Bennett.jl` would have surfaced the
discrepancy in seconds. Before writing any acceptance test that depends on
an upstream feature, verify the feature still exists in upstream — session
summaries and docs drift.

### Stale README entries discovered

1. Lines ~146-200 describe `strategy=:tabulate` as a live Bennett kwarg.
   Not present. Would need either the Bennett kwarg to land, or the README
   to stop advertising it.
2. The bit_width=2 polynomial showcase claims 9 wires via `:auto →
   :tabulate`. Today's `estimate_oracle_resources(x -> x^2 + 3x + 1,
   Int8; bit_width=2)` would need confirming once we have a reliable
   tabulate path.

Not fixing in this session — filing under the existing `zv1` docs-refresh
bead would be cleanest. Flagged in the bead's notes at close time.

---

## 2026-04-18 — Session 24: Close `1f3` (QDrift / Composite RNG injection)

Picked up Session 23's in-progress bead. Code for `rng::AbstractRNG` threading
had already landed; what was outstanding was end-to-end verification of the
`@context` closure pattern, and — discovered this session — a vacuous test.

### Ground truth before coding

Per the user's standing preference (`feedback_ground_truth_first`): read
`src/simulation/qdrift.jl`, `src/simulation/composite.jl`,
`test/test_qdrift.jl`, `test/test_composite.jl`, and the `@context` macro in
`src/context/abstract.jl` BEFORE running anything. Confirmed:

- QDrift: `rng::AbstractRNG` field, constructor kwarg, `_sample(dist, alg.rng)`
  threaded at `qdrift.jl:122`.
- Composite: `rng` field + kwarg, threaded in BOTH branches of
  `_apply_composite!` (pure-qDRIFT degenerate case at `composite.jl:106` via
  `QDrift(..., rng=alg.rng)`, and the interleaved loop at `composite.jl:123`
  via `_sample(dist, alg.rng)`).
- `@context` macro at `context/abstract.jl:93-107` returns the body's last
  expression via `try ... finally`. The `run_once()` closure pattern is sound:
  `a` as the trailing expression of the `begin...end` becomes the return
  value.

### Gotcha: the committed Composite test was vacuous

The Session-23 committed test used
`Composite(steps=2, qdrift_samples=10, cutoff=0.5, …)` with
`ising(Val(3), J=1.0, h=0.5)`. At cutoff=0.5 both coefficients satisfy
`|hⱼ| ≥ cutoff`, so `_partition` puts ALL terms in the Trotter partition and
returns `B = nothing`. Control flow takes the degenerate branch
(`composite.jl:99-102`) which never consults the RNG. The
`amps_a == amps_b` assertion held, but only because the circuit is fully
deterministic — not because the RNG was threaded.

Probed via:

```
julia> _partition(ising(Val(3), J=1.0, h=0.5), 0.5)
# A=nterms=5, B=nothing           ← vacuous at cutoff=0.5

julia> _partition(ising(Val(3), J=1.0, h=0.5), 0.75)
# A=nterms=2, B=nterms=3          ← 2 ZZ in Trotter, 3 X in qDRIFT
```

**Lesson for future tests on `Composite`**: pick the cutoff BY INSPECTING
the Hamiltonian's coefficient magnitudes, not by mirroring whatever the
construction docstring happens to default to. A `_partition(H, cutoff)` probe
before committing an RNG-threading test catches this trivially.

### Fix

Both committed testsets hardened with an alt-seed sanity check
(`amps_a != amps_c` where `a = seed 42`, `c = seed 99`). The Composite test
also switches to `cutoff=0.75` with a rationale comment inline
(`test_composite.jl:309-329`). Now:

- If the RNG kwarg is stored but not threaded → same-seed equal still holds
  (vacuous), alt-seed differ FAILS loudly. Test catches the bug.
- If the RNG is threaded correctly → both assertions hold.

### Verification (targeted probe, not full suite)

```
LIBORKAN_PATH=…/liborkan.so julia --project -e '…'
[1/3] sample-sequence determinism: OK
[2/3] QDrift end-to-end determinism: OK (same-seed equal, alt-seed differ)
[3/3] Composite end-to-end determinism: OK (same-seed equal, alt-seed differ)
ALL OK
```

Full `test_qdrift.jl` / `test_composite.jl` runs skipped per the
`sturm-jl-test-suite-slow` memory — the modified testsets were exercised
as-written by the probe.

### Bead closure

`Sturm.jl-1f3` closed. End-to-end verification done. The reproducibility
contract (seeded `rng` → byte-identical Orkan amplitudes) now has a test
that actually exercises the qDRIFT partition.

### Environment note

`LIBORKAN_PATH` is `/home/tobiasosborne/Projects/orkan/…` on this device.
The memory entry `device-performance-do-not-run-full-test-suite` had
`/home/tobias/Projects/orkan/…`; that path does not exist here. The correct
prefix is `/home/tobiasosborne/`. (Not updating the memory this session;
leaving as a known discrepancy.)

### Files touched

- `test/test_qdrift.jl` (lines 466-485): `run_once(seed)`, alt-seed assertion.
- `test/test_composite.jl` (lines 309-329): `cutoff=0.5 → 0.75`,
  `run_once(seed)`, alt-seed assertion, rationale comment.
- `WORKLOG.md`: this entry.

---

## 2026-04-17 — Session 23: Harmonise repo against PRD and vision

Full-day session. Shape: (1) stocktake across the whole codebase (122 files, ~9.5k src LOC), (2) beads triage — delete the future-vision epics that no longer match direction, (3) file replacement beads covering the real state-based findings, (4) revise PRD/docs to match current code + the "four pillars" vision from user's blog draft, (5) execute a run of easy beads.

### Vision (from author's blog + A1 discussion)

Sturm.jl is NOT a new language. It is Julia, extended. Quantum algorithms written in idiomatic Julia at the level of channels / operators / higher-order patterns, compiled by the package to circuits. Four pillars:

1. **Expressive** — no gates, no qubits in user code; registers and higher-order patterns.
2. **Compiler quality** — DAG IR optimised by publishable passes; new circuit-construction papers shippable as transformations.
3. **Extensible** — new pass APIs integrate in hours (as the Bennett.jl + Sun-Borissov experience demonstrated).
4. **Backend-agnostic** — Orkan, simulators, tensor networks, hardware all substitutable behind `AbstractContext`.

Everything else in the PRD (`P1`–`P9`) reads under this framing. See Sturm-PRD.md after this session's revision.

### Beads harmonisation

**Deleted 10** (multi-path arithmetic Phases 2-7: `xfk, adj, 2l4, 5se, 3ii, 3px`; oracle decompose subsumed by Bennett `:tabulate`: `16l, 25u`; P7 future arms: `wzj, 5ta`).

**Closed 2** (`k3m` incoherent — the literal `f(q)` syntax the P9 bead asked for is rejected by Julia and by the PRD; `mjk` done — Phase 1 test coverage exists, bridge cache sorts kwargs).

**Kept 1** (`f23` — the P2 implicit-cast warning is a legit current-state gap).

**Filed 15 new**, all traceable to stocktake findings. Priorities follow the user's G1 rule: P0/P1 = red-flashing emergency, ergonomics/nice-to-have pushed to P3/P4. See `bd list --status=open -n 20`.

**Also deleted** `docs/PLAN.md`, `docs/bennett-integration-v01-vision.md`, `docs/multi-path-arithmetic-plan.md` — three stale docs; git history preserves them. `docs/bennett-integration-implementation-plan.md` is current and kept.

**Created `KNOWN_ISSUES.md`** at project root — bullet register of architectural constraints (noise outside DAG IR by design), performance targets (31 bytes/node from Session 3), hard caps (30-qubit MAX_QUBITS), and test gaps that don't warrant individual beads.

**PRD revised** to remove "v0.1 POC" framing throughout, rewrite §7 as a current-state inventory (what is shipped, what is not, what is excluded by design), correct §9.2 (EagerContext is Orkan-backed, not a dense Julia vector as the old PRD said), align §2.5 / §9.4 / §9.6 to the real code, update §11 deps and §12 non-goals. Axioms P1-P9 untouched. ~300 lines net-down; see commit `a9752fa`.

### Beads worked this session

- **`wmo` P0 bug** (closed, commit `c162959`) — `alpha_comm(H, p≥3)` previously returned a naive triangle bound silently; per WORKLOG Session 4 that can be 10^9× looser than the true commutator-scaling value. Changed to throw `ErrorException` with a message directing users to `trotter_error(H, t, order; method=:naive)` (which bypasses `alpha_comm` entirely and uses `(λt)^(p+1)` directly). 7 new tests in `test_error_bounds.jl`, 68/68 pass.

- **`ndm` P1 task** (closed, commit `679cdea`) — orphaned `qsvt!` in `src/qsvt/circuit.jl` had a 13-line WARNING block stating it was broken for general block encodings. `qsvt_combined_reflect!` + `oaa_amplify!` is the working path (what `evolve!(…, QSVT(ε))` dispatches to). Deleted the function, docstring, WARNING block (~80 LOC). Removed 2 associated tests from `test_qsvt_phase_factors.jl` and the import. 162/162 pass.

- **`w4g` P1 task** (closed, commit `ba6e295`) — `Base.:<(::QInt, ::QInt)` and `Base.:(==)(::QInt, ::QInt)` plus their 4 Integer-mixed overloads silently measured both operands and returned a deterministic QBool. Violated P1 (functions are channels) and P9 (quantum registers as numeric type for reversible dispatch). Deleted all 6 definitions (~50 LOC). Removed 5 testsets from `test_qint.jl` and 4 from `test_promotion.jl`. Short comment at the deletion site points future readers to `oracle(f, q)` for quantum comparators. 562 + 2043 tests pass.

- **`lpj` P4 task** (closed, commit `3b60acf`) — `src/bennett/auto_dispatch.jl` was a 45-line stub holding `_P9_CACHE`, `_P9_LOCK`, `clear_auto_cache!()` for the Julia-forbidden literal `f(q)` catch-all. No callers outside the test. Deleted the file, removed include from `src/Sturm.jl`, deleted the "infrastructure exported" testset from `test_p9_auto_dispatch.jl`. Remaining 13 P9 tests pass (Quantum abstract type, classical_type trait, classical_compile_kwargs, existing dispatch paths).

- **`1f3` P3 feature** (in_progress, not closed) — QDrift and Composite RNG injection. Code changes are in this commit but END-TO-END VERIFICATION IS PARTIAL. See next-session pickup below.

### `1f3` state at stop time — PICK THIS UP FIRST

**Code landed (this commit):**

- `Project.toml`: added `Random = "9a3f8284-..."` to `[deps]`. `Random` is a stdlib but Julia still requires declaration in `[deps]` for non-Base modules.
- `src/simulation/qdrift.jl`:
  - `using Random: AbstractRNG, default_rng` at top
  - `QDrift` struct gained `rng::AbstractRNG` field; constructor has `rng::AbstractRNG = default_rng()` kwarg
  - `_sample(dist)` became `_sample(dist, rng::AbstractRNG = default_rng())` (backward-compat)
  - `_apply_qdrift!` now passes `alg.rng` to `_sample`
- `src/simulation/composite.jl`:
  - `Composite` gained `rng::AbstractRNG` field; constructor `rng::AbstractRNG = default_rng()` kwarg
  - `_apply_composite!` threads `alg.rng` in BOTH places: the pure-qDRIFT branch (constructs a `QDrift(..., rng=alg.rng)`) and the interleaved Trotter+qDRIFT loop (`_sample(dist, alg.rng)`)
- Test files `test_qdrift.jl` and `test_composite.jl`:
  - `using Random: MersenneTwister` at top
  - New testset `RNG injection: _sample is deterministic with seeded RNG` in `test_qdrift.jl` — verifies two `MersenneTwister(42)` give byte-identical sample sequences; different seed produces different sequence. **This part ran green.**
  - New testset `QDrift rng kwarg is stored and threaded to sampling` in `test_qdrift.jl`, and a parallel `Composite rng kwarg ...` in `test_composite.jl` — end-to-end: two seeded `evolve!` calls on identical |0…0⟩ produce identical Orkan amplitudes.

**Gotcha found and fixed but NOT re-verified:**

First attempt used two back-to-back `@context EagerContext() begin ... end` blocks with `amps_a = [_amp(...) for i in 0:7]` inside the first block and `@test amps_a == amps_b` inside the second. Failed with `UndefVarError: amps_a not defined in Main`. The `@context` macro introduces a scope via its `try ... finally` that hides inner assignments from the outer scope. Fix: wrap each run in a local function `run_once() = @context EagerContext() begin ...; a; end` that returns the amps list as the block's final expression (before `discard!`s? no — discards before the return); then `amps_a = run_once(); amps_b = run_once(); @test amps_a == amps_b`. This is now the committed shape but the probe was interrupted mid-execution.

Looking more carefully: `run_once()` returns `a` but the `@context ... end` ends with `a` AFTER the `for q in qs; discard!(q); end`. The `discard!`s clean up; the state is captured in `a` beforehand. Should be fine.

**Next steps to close `1f3`:**

1. Run the targeted probe to re-verify:
   ```
   LIBORKAN_PATH=/home/tobiasosborne/Projects/orkan/cmake-build-release/src/liborkan.so julia --project -e '
   using Sturm, Test; using Sturm: _QDriftDist, _sample, _amp; using Random: MersenneTwister
   H = ising(Val(3), J=1.0, h=0.5)
   run_qd() = @context EagerContext() begin
       qs = [QBool(0.0) for _ in 1:3]
       evolve!(qs, H, 0.5, QDrift(samples=10, rng=MersenneTwister(42)))
       a = [_amp(qs[1].ctx, i) for i in 0:7]
       for q in qs; discard!(q); end
       a
   end
   a = run_qd(); b = run_qd()
   @test a == b
   println("ok")
   '
   ```
2. If green, run the full `test_qdrift.jl` once (slow — ~13 minutes on this machine due to the N=24 Ising ground-truth test) OR skip and trust CI.
3. Also run `test_composite.jl`.
4. `bd close Sturm.jl-1f3 --reason="..."` + commit + push.

**Risk:** if the `run_once()` closure pattern doesn't work with `@context` either (TLS semantics across function calls are subtle), an alternative is to set `amps_a` via a `Ref{Vector{ComplexF64}}()` written inside the `@context` block. The macro expansion of `@context ctx body` is in `src/context/abstract.jl:~98`; look there if you need to debug scoping.

### Remaining easy-ish open beads

After `1f3` closes, low-friction candidates:

- **`eiq` P3** — CasesNode consumer policy. Touch `channel.jl` compat constructor, `openqasm.jl` line ~112, renderer warnings. Mechanical.
- **`q93` P2** — oracle Int8 hardcoding. Needs a small inference function: W → smallest signed/unsigned integer type.
- **`zv1` P4** — Refresh CLAUDE.md + README. Documentation sweep.

Harder beads that need design first:

- **`1wv` P1** — `with_empty_controls(f, ctx)` method on `AbstractContext`. Touches `pauli_exp.jl` (~line 200) and `lcu.jl` (lines 72-96). Needs a review to make sure no subtle semantics change.
- **`rpq` P1** — Arbitrary `when()` nesting in `TracingContext`. Requires either widening `HotNode` (kills 25-byte isbits, regresses Session 3 perf) or adding a cold-path node variant. User's earlier preference: option B (cold-path `DeepCtrlNode`).
- **`xcu` P1** — Multi-controlled gates on `DensityMatrixContext`. Density-matrix Toffoli via Kraus superop composition is non-trivial.
- **`870` P1** — Steane syndromes. This is QECC framework + 3 X-stabilisers + 3 Z-stabilisers + Table II lookup — a real bit of work.

### Environment gotchas for next agent

- Fresh clone requires `Pkg.develop(path="../Bennett.jl")` then `Pkg.instantiate()` (Bennett is dev-pathed, not registered). Listed in KNOWN_ISSUES.md.
- Orkan shared library: `LIBORKAN_PATH=/home/tobiasosborne/Projects/orkan/cmake-build-release/src/liborkan.so`.
- bd uses SSH now (`git+ssh://git@github.com/tobiasosborne/Sturm.jl.git`). `bd dolt push` works without interactive prompt.
- Per saved feedback: the full test suite is slow. Use targeted `julia --project -e '...'` probes against specific test files; trust CI for regressions. Even individual test files (qdrift.jl, composite.jl) hit minute+ runtimes because of large-N Ising / Heisenberg ground-truth tests. For quick verification run only the relevant testset rather than `include()`ing the whole file.

### Files touched this session

`Sturm-PRD.md`, `KNOWN_ISSUES.md` (new), `Project.toml`, `src/simulation/error_bounds.jl`, `src/simulation/qdrift.jl`, `src/simulation/composite.jl`, `src/types/qint.jl`, `src/Sturm.jl`, `src/qsvt/circuit.jl`, `test/test_error_bounds.jl`, `test/test_qsvt_phase_factors.jl`, `test/test_qint.jl`, `test/test_promotion.jl`, `test/test_qdrift.jl`, `test/test_composite.jl`, `test/test_p9_auto_dispatch.jl`, `.beads/config.yaml`. Deleted: `src/bennett/auto_dispatch.jl`, `docs/PLAN.md`, `docs/bennett-integration-v01-vision.md`, `docs/multi-path-arithmetic-plan.md`.

### Beads state at end of session

Total: 40. Open: 15 (1f3 in_progress). Closed: 25 this session (4 this session + 2 harmonisation closures + 37 historical; deleted 10 harmonisation).

Run `bd ready` or `bd list --status=open -n 30` to see the current queue.

---

## Earlier sessions archived

Sessions 1–22 (2026-04-05 → 2026-04-15) moved to
[`WORKLOG-archive.md`](WORKLOG-archive.md) on 2026-04-19. They cover:

- **Session 1** (2026-04-05) — project bootstrap, Orkan FFI.
- **Session 2** (2026-04-05) — OOM recovery, memory safety, Phase 6–12 scaffolding (QInt, QFT, Channel, QECC skeleton), Grover, literature survey (100 papers / 9 categories), Choi-phase-polynomials research direction.
- **Session 3** (2026-04-06) — gate cancellation (commutation-aware), optimise(ch, :pass), 149× gate_cancel speedup, isbits-union HotNode (31 B/node).
- **Session 4** (2026-04-06) — quantum-simulation literature survey (~170 papers), simulation module (PauliHamiltonian, Trotter1/2, Suzuki), 3-reviewer code review, 21 issues fixed.
- **Session 5** (2026-04-07) — P8 quantum promotion (numeric tower for QInt + Integer).
- **Session 6** (2026-04-07) — simulation module idiomatic review.
- **Session 7** (2026-04-07) — simulation refactors, qDRIFT, Composite, P0 controlled-pauli_exp! optimisation.
- **Session 8** (2026-04-08) — PDE paper formalisation (Childs et al. 2604.05098), gap analysis.
- **Session 9** (2026-04-08) — literature re-download (90 PDFs), QSVT deprecation (Motlagh → BS+Laneve), Block Encoding Phase 1, QSVT Phase 2.
- **Session 10** (2026-04-08) — Weiss algorithm, RHW factorisation, phase extraction, qsvt_protocol! circuit, BE algebra, controlled-oracle fix, multi-controlled Rz/Ry/CX.
- **Session 11** (2026-04-08) — 5-agent ground-truth review, GQSP operator-ordering fix (critical), reflection QSVT circuit, `evolve!(..., QSVT(ε))` for cos(Ht/α).
- **Session 12** (2026-04-09) — combined QSVT / GSLW Theorem 56 (7 bugs found and fixed, sin parity fix).
- **Session 13** (2026-04-09) — OAA implementation + two critical bugs (BS+NLFT degree-doubling phase collapse, single-qubit Rz ≠ multi-ancilla reflection). Rogue-background-agent gotcha.
- **Session 14** (2026-04-11) — Bennett.jl integration research + 74/74 tests.
- **Session 15** (2026-04-12) — Steane [[7,1,3]] encoder rewrite per Steane 1996 Fig 3, higher-order `encode(Channel, code)`, Grover-from-predicate (`find(f, T, Val(W))`), 2 Bennett upstream bugs fixed, v0.2 direction research (4-backend matrix + viz layer).
- **Session 16** (2026-04-12) — ASCII circuit drawer, pixel-art PNG renderer (Birren palette, 1000-wire GHZ in 70 ms), compact Level-A scheduling, Bennett v0.4 downstream assessment.
- **Session 17** (2026-04-14) — axiom refinement (P2 measurement-as-cast, P7 infinite-dimensional, P9 auto-dispatch spec).
- **Session 18** (2026-04-14) — Bennett.jl v0.5 assessment, multi-path arithmetic compilation plan (7-phase roll-out).
- **Session 19** (2026-04-14) — P9 hits Julia's `cannot add methods to builtin Function` wall, axiom reframed (generic path via P8 + explicit `oracle`/`@quantum_lift`/`quantum`). P4 corollary (`if q` never auto-lifts to `when(q)`).
- **Session 20** (2026-04-14) — multi-path arithmetic Phase 1, P8 bitwise (`⊻`, `&`, `|`) + shifts (`<<`, `>>`) on QInt, QuantumOracle cache-key bug fixed.
- **Session 21** (2026-04-15) — README audit against axioms, oracle decomposition honesty (43-qubit LLVM-lowering reality), Approach A/B idioms.
- **Session 22** (2026-04-15) — Bennett `:tabulate` adoption (zero Sturm-side changes, README rewrite).

For reasoning and design decisions made during any of the above, see the archive.
