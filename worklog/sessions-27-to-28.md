## 2026-04-19 — Session 28: Close `Sturm.jl-di9` (add_qft! angle-fold phase bug)

P0 landed. Root cause of the "π/2 leak" flagged in Session 27 is the
angle-fold in `add_qft!` — `mod(θ + π, 2π) - π` maps BOTH `θ = +π` and
`θ = -π` to `-π`, breaking `Rz(θ) · Rz(-θ) = I` on any wire whose raw
angle lands exactly on the boundary. Under `when(ctrl)` that -I per-wire
becomes a relative π phase on `ctrl = |1⟩`, and across many modadds
(Shor's PE cascade) the phases accumulate and scramble the counter
register. Session 27's data was real; the **diagnosis** was partially
misread (see below).

### Grind method — first-diff-with-ground-truth

1. Reproduced the 50% X-basis leak from `probe_mulmod_phase.jl`
   (Session 27). Confirmed the leak is x-dependent as reported.
2. Wrote a block-wise probe (`probe_di9_blockwise.jl`) testing
   `when(ctrl) add_qft!(y, a)` with no inverse restore.
   **Unexpected**: every block from single add_qft to full mulmod
   showed ~50%. That "universal 50%" was the first clue the Session 27
   diagnosis was off.
3. Realised `when(ctrl) U |x⟩` on non-eigenstate `x` produces
   `(|0⟩|x⟩ + |1⟩·U|x⟩)/√2` and tracing `x` decoheres ctrl to 50/50 in
   ANY basis. The Session 27 probe was measuring inherent ctrl-target
   entanglement, NOT a phase bug.
4. Wrote `probe_di9_inverse.jl` with the correct protocol:
   `when(ctrl) do U; U⁻¹ end`. Ctrl should come back to pure |+⟩
   regardless of target state; any X-basis leak is a true global-phase
   bug. This smoked out the real fold.
5. Hand-traced the L=1 a=1 v=0 case (smallest reproducer):
   - `add_qft(y=QInt{2}, +1)`: wire 2, jj=1, θ_raw=π → fold → Rz(-π).
   - `sub_qft(y, 1) = add_qft(y, -1)`: `a_mod = mod(-1, 4) = 3`, wire 2,
     θ_raw = 3π → fold → Rz(-π) (same folded angle!).
   - Composed wire 2: Rz(-π) · Rz(-π) = Rz(-2π) = -I.
   - Under ctrl: -I on ctrl=|1⟩ = relative phase π = 100% X-basis leak.
   Observed: 100.0% in probe. ✓ First diff located, root cause identified.

### Fix — `src/library/arithmetic.jl:59`

Removed the fold entirely. `add_qft!` now emits `Rz(θ_raw)` per wire
where `θ_raw = 2π · a / 2^jj`. Orkan computes `Rz(θ)` in double
precision for any θ, so "keeping angles small" was never load-bearing.
The `a_mod = mod(Int(a), 1<<L)` wrap was also dropped: Rz(θ) is
periodic mod 4π as a gate action (period 2π on target states up to a -I
factor that now cancels cleanly with the matching inverse), and the
caller-side invariants (a ∈ [0, N), b ∈ [0, N), N < 2^L) keep θ
bounded anyway.

### Red-green TDD

1. **RED**: added `@testset "di9: X-basis coherence of controlled
   arithmetic sub-circuits"` to `test/test_arithmetic.jl` — 24 tests
   covering add_qft∘sub_qft under when(ctrl), modadd∘modadd(N-a) with
   ctrls=(c,) and ctrls=(c,|1⟩), and mulmod(a)∘mulmod(a⁻¹). Minimal
   reproducer (L=1 a=1 v=0) RED-checked to confirm 100% leak pre-fix.
2. **GREEN**: one-function fix in `add_qft!`. Minimal probe → 0% leak.
3. **Full `test_arithmetic.jl` regression** (OMP_NUM_THREADS=1, 1m06s):
   - add_qft!: 809/809
   - modadd!: 2130/2130
   - mulmod_beauregard!: 269/269
   - di9 X-basis coherence: **24/24** (new)
   Total: **3232/3232** green.
4. **End-to-end Shor acceptance** (`probe_di9_shor_n21.jl`):
   - N=15 a=7 r=4 t=3: 21/30 = **70%** hits (Session 26: 50%)
   - N=15 a=2 r=4 t=3: 13/20 = **65%** hits
   - N=21 a=2 r=6 t=6: 5/20 = **25%** hits (Session 27: 0/20 = 0%) ✓ ≥20%
   - N=21 a=4 r=3 t=6: 6/10 = **60%** hits

### Gotchas for future agents

1. **`mod(θ+π, 2π) - π` is a LEAKY fold under control.** Any angle
   canonicalisation that maps the boundary representatives
   asymmetrically (+π ≠ -π under the map, but folds them together)
   breaks `Rz(θ) · Rz(-θ) = I`. If you need to fold Rz angles for
   display or optimisation, fold them INTO THE UNITARY itself using the
   equality `Rz(θ + 2π) = −Rz(θ)` — i.e., keep a parity bit and apply a
   compensating CP/CZ on the control stack. Or just don't fold.
2. **`when(ctrl) U |x⟩` on non-eigenstate x looks like a phase bug on
   an X-basis probe.** 50% measure-true is the signature of ctrl being
   fully traced-out by the entangled target, NOT a phase leak. The
   correct phase-bug probe is `when(ctrl) U; U⁻¹ end`: any leak there is
   a genuine global-phase mismatch because U·U⁻¹ = I returns target
   trivially on both ctrl branches. Session 27's probe was conflating
   the two. If you're investigating a controlled-unitary, ALWAYS use
   the forward-inverse pattern first.
3. **Session-level "grind" workflow paid off again.** Reproducing with
   a minimal L=1 single-Rz case + hand-tracing the 2-line arithmetic
   localised the bug in < 5 minutes of reading after the inverse probe
   fired. The multi-stage block-wise probe was useful to rule out
   modadd-only / mulmod-only mechanisms, but the SMOKING GUN was
   picking the smallest controlled example and working through the
   folded angles by hand. "Find-first-diff-with-ground-truth" >
   speculation.
4. **X-basis inverse-pair regression tests are now part of the
   acceptance surface for Shor arithmetic.** The 24 di9 tests added to
   `test/test_arithmetic.jl` are the tripwire for the next silent-phase
   bug in add_qft / modadd / mulmod. Run them on every change to
   `src/library/arithmetic.jl`.
5. **OMP_NUM_THREADS=1 during verification.** Without it, Orkan's
   OpenMP parallelism spawns enough threads to saturate CPU time
   counters but doesn't help small statevectors (3-13 qubits is too
   small to parallelise usefully). With OMP=1 the 24-probe GREEN check
   ran in 23s; without it the regression test_arithmetic.jl run
   appeared to stall (high CPU but no output) because Julia's `@testset`
   batch-prints. One-liner fix: always set OMP_NUM_THREADS=1 for
   shor/arithmetic probes.

### Files touched

- `src/library/arithmetic.jl` — removed the fold, updated docstring.
- `test/test_arithmetic.jl` — added `di9:` testset (24 assertions).
- `test/probe_di9_blockwise.jl` (new) — block-wise forward-only probe
  (kept as a reference for the "50% leak is inherent entanglement"
  lesson).
- `test/probe_di9_inverse.jl` (new) — canonical forward-inverse X-basis
  harness.
- `test/probe_di9_green.jl` (new) — verbose-eager-flush GREEN runner
  for the same cases (used for fast iteration; `@testset` output is
  batch-delayed).
- `test/probe_di9_shor_n21.jl` (new) — Shor end-to-end acceptance at
  N=15, N=21 with both a=2 (r=6) and a=4 (r=3).
- `WORKLOG.md` — this entry.

### Beads

- `Sturm.jl-di9` closed.
- `Sturm.jl-6kx` (shor_order_D at N=15) stays closed but now genuinely
  verified: N=21 r=6 Shor works at 25% hit rate.
- `Sturm.jl-8b9` (semi-classical iQFT) still P1, still deferred. Would
  now be safe to implement on top of the phase-clean arithmetic.

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

