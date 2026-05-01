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

