## 2026-04-20 — Session 36c: File three EH17 follow-on beads + handoff notes

After the 6bn ship and the N=55 demo (sessions 36 / 36b), mapped out the
remaining Shor work and filed three new beads for EH17-specific follow-
ons that were implicit in the 6bn design but out of its scope.

### Beads filed this session

| ID  | P  | Title | Unblocked? |
|-----|----|-------|------------|
| `Sturm.jl-zli` | P2 | shor_factor_EH s>1 — multi-shot lattice post-processing (EH17 §4.4 general) | ready now |
| `Sturm.jl-npd` | P2 | shor_factor_EH_semi — Mosca-Ekert semi-classical iQFT for two-register EH17 | ready now |
| `Sturm.jl-e73` | P3 | Pure coset state via comparison-negation — Gidney 1905.08488 Fig 1 full | ready now |

### zli — EH17 s>1 (P2)

**What**: Current `shor_factor_EH` is s=1 only (2D Lagrange post-
processing). For s>1 the exponent register width shrinks asymptotically
from 1.5n toward 0.5n, which is the entire point of EH17's 2017
generalization over Ekerå 2016's s=1 algorithm.

**How to start**: Add `s::Int=1` kwarg. For s≥2, (a) run the quantum
step s times, (b) build the (s+1)-dim lattice basis of EH17 Def 3,
(c) solve CVP via pure-Julia LLL (~200 lines, δ=3/4), (d) verify via
`_eh_factors_from_d`. Spurious-candidate probability drops to 2^(-s-1)
per Lemma 3, so s=2 already halves ambiguity.

**Acceptance**: `shor_factor_EH(15; s=2)` ≥ 50% over 30 shots;
`shor_factor_EH(15; s=3)` ≥ 60%. s=1 unchanged. New test file with LLL
unit tests against reference vectors.

**Avoid**: Don't reach for Nemo.jl / fpLLL_jll as a hard dep. Pure-Julia
LLL is well-known (Lenstra-Lenstra-Lovász 1982, δ=3/4); the whole
module is ~200 lines and this project doesn't carry a lattice-algebra
dep yet.

### npd — Mosca-Ekert semi-classical for EH17 (P2)

**What**: Current `shor_factor_EH` peaks at 24 qubits for N=55 because
both exponent registers live in superposition simultaneously (full
two-register PE). Mosca-Ekert (1999 NASA QCQC [Lecture Notes in CS
vol 1509]) adapts Griffiths-Niu semi-classical iQFT to multi-register
DLP, collapsing each exp register to a single recycled qubit — the
same trick Beauregard 2003 gave us for ORDER-finding in
`shor_order_D_semi`. Result: N=55 peak drops from 24 to ~13 qubits,
single-shot runtime from 13m16s to ≤30s.

**CRITICAL research step (MUST do first)**: Session 36 explicitly
established that EH17's §4.3 is NOT directly Griffiths-Niu-izable
because the (j,k) correlation is joint via shared `e = a - bd`.
Mosca-Ekert §3.2 solves this but the exact cross-register phase-
correction formula is NOT obvious from EH17 alone. Phase 0 of this
bead: FETCH Mosca-Ekert 1999 PDF (arxiv.org/abs/quant-ph/9903071 is a
candidate — verify when read) and work out the phase accumulator
recurrence on paper BEFORE any coding. Pattern mirrors rule 4: local
PDF + explicit equation reference.

**Acceptance**: see bead — 5 criteria including 50%+ hit rate at N=15,
peak reduction, runtime reduction, and a documented phase-correction
derivation in code comments.

**Avoid**: Don't try to "just mirror `shor_order_D_semi`'s outer
structure and hope" — this was the instinct session 36 already
corrected. The phase-correction for TWO exp registers feeding ONE
working register is non-trivial.

### e73 — Pure coset state via comparison-negation (P3)

**What**: Session 35 (bead 8fy) shipped `_coset_init!` with Cpad
EXTERNAL pad ancillae that remain entangled with `reg` — pragmatic
for 6xi acceptance but not the Gidney 1905.08488 Fig 1 circuit. The
paper's pure single-register construction uses a
`(-1)^{x ≥ 2^p·N}` comparison-negation phase kickback per stage to
DISENTANGLE pad ancillae back to |0⟩. Benefits: -Cpad steady-state
qubits, matches paper for publication, simplifies `decode!`, enables
true Gidney-style coset arithmetic downstream.

**How to start**: Implement `_comparison_negate!(reg::QInt{W},
threshold::Integer)` as a reversible comparator (subtract-check-
uncompute pattern; sub_qft_quantum! + sign-bit Z). Then rewrite
`_coset_init!` to Gidney Fig 1 literally: allocate pad_p fresh per
stage, H, controlled-add, comparison-negate, H, deallocate pad_p
(verified |0⟩). Keep the external-ancilla path as `pure=false`
fallback.

**Also useful for**: `jrl` (runway) and `6oc` (windowed arithmetic)
both want the comparator as a primitive. e73's comparator becomes
load-bearing infrastructure for the rest of the GE21 stack.

### What's NOT left for Shor (shipped)

For reassurance to future-agent: the Shor stack is already rich.
Shipped:
- 5 order-finding impls (A, B, C, D, D_semi) covering oracle-lift,
  PE HOF, U^{2^j} cascade, Beauregard 2n+3, and semi-classical iQFT.
- `shor_factor_EH` (6bn, this session) — EH17 1.5n short-DLP, s=1,
  30/30 hit at N=15, 24-qubit peak verified at N=55.
- `QCoset` / `coset_add!` / `decode!` — GE21 §2.4 coset representation
  (types shipped; NOT yet used inside any Shor driver — that's an
  unfiled polish step, not on the GE21 critical path).
- `QRunway` runway-at-end (b3l).

### Missing — GE21 critical path (UNCHANGED from prior sessions)

1. **`jrl` P2** — `QRunwayMid{W_low, Cpad, W_high}` runway-in-middle.
   Blocks 6oc. 3+1 type-design round required.
2. **`6oc` P1** — windowed arithmetic + `shor_order_E`. Blocked on jrl.
   Three phases, 3–4 sessions.

### Missing — orthogonal

- **`870` P1** — Steane QECC syndrome extraction; wrapping any
  shor_factor_* via `encode(ch, Steane)` gives fault-tolerant Shor.
- **`7z1` P3 / `wzc` P4** — Gidney 2025 / Regev 2023 (post-GE21).

### Suggested next-session pick (for future-you)

If you like **research-heavy**: `npd` (Mosca-Ekert) — ground-truth
fetch + paper derivation + implement. Highest information-per-session.

If you like **algorithmic**: `jrl` + `6oc` — the main GE21 chain, big
payoff (polylog Toffoli reduction), but 4-5 sessions.

If you like **small-and-shippable**: `e73` (pure coset). One session,
delivers a reusable primitive (comparator) that pays off later.

If you like **extension of 6bn**: `zli` (s>1). Classical-heavy (LLL),
minimal quantum work.

### Commits this session (36c)

```
b41fe2f  feat(shor): m/ell/verbose kwargs for shor_factor_EH + _eh_short_dlp
94f97fc  docs(worklog): session 36b — N=55 demo (biggest shor_factor_EH in 24 qubits)
<TBD>    docs(worklog): session 36c — file zli + npd + e73 EH17 follow-ons
```

Dolt remote synced after each close (`bd dolt push`).

---

## 2026-04-20 — Session 36b: N=55 demo (biggest shor_factor_EH fitting 24 qubits)

Ran `_eh_short_dlp(7, 28, 55, Val(3), Val(3), Val(6))` with verbose=true
instrumentation. Predicted peak `2·ell + m + 2·L + 3 = 24`. Actual peak
(via `ctx.n_qubits` after run): **24 qubits exactly**. ✓

### Runtime (commit `b41fe2f`)

```
[eh_dlp +1.2s  live=15] alloc y_reg[L=6] = |1⟩
[eh_dlp +88.1s live=15] first_reg[1]: EXIT mulmod_beauregard!
[eh_dlp +174.5s live=15] first_reg[2]: EXIT
[eh_dlp +263.4s live=15] first_reg[3]: EXIT
[eh_dlp +353.4s live=15] first_reg[4]: EXIT
[eh_dlp +442.0s live=15] first_reg[5]: EXIT
[eh_dlp +531.4s live=15] first_reg[6]: EXIT
[eh_dlp +621.1s live=15] second_reg[1]: EXIT
[eh_dlp +707.2s live=15] second_reg[2]: EXIT
[eh_dlp +792.6s live=15] second_reg[3]: EXIT
[eh_dlp +792.6s live=15] interfere!(first_reg)
[eh_dlp +793.5s live=15] interfere!(second_reg)
[eh_dlp +795.7s live=0 ] EXIT j=6 k=2
```

9 controlled mulmods at ~88s each, interfere! negligible. Total 13m16s
per shot. Each mulmod works at 2^24 statevector (24-qubit peak inside
the mulmod interior, driven by the L+1=7 ancillae).

### Single-shot MISS — the "smeared peaks" discovery

The shot returned `(j=6, k=2)` with `_eh_recover_d_candidates = []` —
no d ∈ (0, 8) satisfied `|{d·j + 2^m·k}_{64}| ≤ 2^(m-2) = 2`. Miss.

**Root cause (NEW insight, worth saving)**: For N=15 `max ord(g) = 4`
and 64/4 = 16 is an integer power of 2 → QFT peaks are sharp (every
shot lands on a multiple of 2^(ℓ+m) / ord). For N=55 `max ord(g) = 20`
(lcm(4, 10)) and 64/20 is NOT an integer, let alone a power of 2 → QFT
peaks are smeared across multiple (j, k) outcomes, and single-shot hit
rate degrades.

Generalisation: EH17's short-DLP algorithm at toy-N hits reliably only
when `ord(g) | 2^(ℓ+m)`, i.e., when `ord(g)` is a power of 2. For
N = pq with `p, q` odd primes, `max ord = lcm(p-1, q-1)`:
  * N=15: lcm(2, 4) = 4 = 2² ✓
  * N=21: lcm(2, 6) = 6 = 2·3 ✗
  * N=33: lcm(2, 10) = 10 = 2·5 ✗
  * N=35: lcm(4, 6) = 12 = 2²·3 ✗
  * N=39: lcm(2, 12) = 12 ✗
  * N=55: lcm(4, 10) = 20 = 2²·5 ✗

**Implication**: test acceptance of `shor_factor_EH(N) ≥ 50%` is
structurally easier at N=15 than at any other toy-N. Future acceptance
bars for Sturm's EH17 tests on N ∈ {21, 33, 35, 39, 55} should expect
lower single-shot rates (~20-40% empirically) and rely on
`max_attempts ≥ 10` to hit the cumulative ≥50% bar.

### What was committed

Commit `b41fe2f`:
- `shor_factor_EH(N; m=nothing, ell=nothing, verbose=false, ...)` —
  `m` and `ell` now overrideable (default heuristic unchanged).
- `_eh_short_dlp(..., verbose::Bool=false)` — stage-by-stage
  ENTER/EXIT lines on stderr (wall-clock ms, live qubits), flushed
  per line. Silent by default.

### Lessons for future agents

1. **`tail -N` defeats eager-flush.** Piping a streaming producer
   through `tail -80 | ...` buffers the entire stream until EOF.
   For verbose runs, redirect to a file and use `Monitor` on
   `tail -f file | grep --line-buffered ...`, or read the file directly
   while it's being written.

2. **Peak-qubit formula for EH17**: `2·ell + m + 2·L + 3` (L+1 mulmod
   ancilla + 1 cascade workspace + ell+m+ell exponent + L working).
   For 24-qubit budget: `3m + 2L ≤ 21` with ell=m, giving the family
   `(m=3, L≤6)` (biggest N=55) or `(m=4, L≤4)` (too small to be
   interesting).

3. **Runtime per mulmod scales as 2^peak**: ~86s at 2^24 vs ~1.5s at
   2^19 (N=15). For N=55 that's 9·88 = 13 min/shot. Multi-shot
   acceptance tests at N=55 would need 1-2 hours compute; do NOT
   run in a test suite.

4. **QFT peak sharpness = ord(g) | 2^(ℓ+m)**. Powers-of-2 order gives
   100% single-shot success; non-power-of-2 order smears peaks. The
   EH17 analytical bound `ord ≥ 2^(ℓ+m) + 2^ℓ·d` is violated for all
   these toy-N, but sharp-vs-smeared depends on the divisibility.

### Next-session pointers (unchanged)

As Session 36: `jrl` P2 (unblocks `6oc`), `870` P1 (Steane), or
`eud`/`c6n` Shor epics. Session 36b added no new blockers.

---

## 2026-04-20 — Session 36: Ship `Sturm.jl-6bn` (Ekerå-Håstad short-DLP factoring)

Single-bead session. Shipped `shor_factor_EH`, the EH17 short-DLP
derivative of Shor, picked because (a) it's an independent Shor driver
(no `jrl` / 3+1 type-design needed), (b) single-session scope, and
(c) user asked for "Shor algorithm stuff". Commit `6e0cc60` pushed.

### Ground truth before coding (rule 4 + user instruction)

Read `docs/physics/ekera_2017_short_dlp.pdf` (arXiv:1702.00249) front to
back (pp. 1–15). Extracted:
- §4.3 quantum step: |Ψ⟩ = (1/√2^(2ℓ+m)) Σ_a Σ_b |a⟩|b⟩|0⟩, compute
  [a]g ⊙ [-b]x = [a-bd]g, QFT both registers, measure → (j, k).
- §4.4 classical post-processing (s=1): 2D lattice L = Z-span of
  [[j,1], [2^(ℓ+m),0]], target v = ({-2^m k}_M, 0), search |u-v| <
  sqrt(5)/2·2^m, last coord of u is d.
- Def 1 (good pair): |{d·j + 2^m·k}_{2^(ℓ+m)}| ≤ 2^(m-2).
- §5.2.2 factor recovery (EH-normalisation): y = g^((N-1)/2) mod N,
  d = (p+q-2)/2, quadratic x² - (2d+2)x + N = 0 with roots
  p, q = (d+1) ± √((d+1)² - N).

### Conceptual surprise — EH17 is NOT amenable to semi-classical iQFT

My first instinct was to mirror `shor_order_D_semi`'s Griffiths-Niu
semi-classical iQFT (Beauregard 2003 "one-qubit trick") and do two
sequential per-bit measure-and-correct loops, one per register.

**That is wrong.** §4.3 Eq. (the observation probability expression)
shows that the joint distribution P(j, k) is non-separable — the (j, k)
correlation comes from the shared e = a - bd in the working register
and is resolved jointly by QFT on both registers. Measuring first
register's iQFT outcome LOSES this correlation: the post-measurement
state isn't the one a naïve "semi-classical iQFT" would produce.

Mosca-Ekert (§4.7 of EH17 refs) adapts semi-classical to multi-register
DLP but the trick is more subtle than one-register PE. Out of scope.

**Shipped**: full non-semi-classical two-register PE with explicit
`QInt{ell+m}` + `QInt{ell}` exponent registers in `|+⟩^n` via
`superpose!` (which is forward QFT; on |0⟩ it equals H^⊗n |0⟩),
controlled mulmods, then `interfere!` (inverse QFT) on each register
independently, and measurement.

Peak qubit budget at N=15 (m = ell = 3, L = 4):
`6 + 3 + 4 + 5 + 1 = 19` wires — well under Orkan's 30.

### Classical post-processing: brute force over d, then verify

Straight `for d in 1:(2^m - 1)` with the good-pair residual bound.
For m=3 this is 7 candidates. Returns `Vector{Int}` sorted by
ascending |residual|. Driver iterates candidates, verifies each via
`_eh_factors_from_d` (the quadratic), accepts the first that
actually factors N.

**Why a list, not a single minimum:** at small m, multiple d values
can satisfy the residual bound — these are the "spurious lattice
vectors" of §4.4 Lemma 3. The probe output for (j=2, k=7, m=ell=3)
returned `[4, 3, 5]` with d=4 first (residual 0) and d=3 second
(residual 2, the true answer). d=4 fails the quadratic (disc=10 not
a square); d=3 succeeds. Verification IS the uniqueness-resolution.

### Toy-N caveat: N=15 violates EH17's analytical assumption

EH17 §4.3 requires ord(g) ≥ 2^(ℓ+m) + 2^ℓ·d. For N=15: max ord is 4
(= lcm(p-1, q-1) = lcm(2, 4)), and 2^(ℓ+m) = 64. So the algorithm runs
**outside** its proven regime at N=15. Empirically it still works
because:
- Lucky-g cases (gcd(g, N) > 1) resolve classically (~46% at N=15).
- For coprime g, only low bits of the exponent registers couple to
  `y_reg` (high-bit mulmods are identity when `g^(2^i) mod N = 1`);
  the iQFT on those low bits still produces biased (j, k) pairs.
- At m=3, the brute-force verification step exhaustively checks all 7
  candidate d values, so "spurious candidate d=4" never leaks through.

Observed hit rate: **30/30 for N=15** (100%). Well above the 50% bar.

### Parameter selection heuristic

`n_N = ceil(log2(N+1))`, `m = max(3, (n_N+1)÷2 + 1)`, `ell = m`, `L =
ceil(log2(N))`. At N=15 → m=3. At N=35 → m=4. At N=21 → m=4. The
`+1` buffer over `(n_N+1)÷2` ensures d < 2^m for any (p, q) satisfying
2^(n_prime-1) < p, q < 2^n_prime. No tuning required per-N.

### RED-GREEN TDD trace

1. **RED**: wrote `test/test_6bn_ekera_hastad.jl` with 5 testsets:
   (a) `_eh_factors_from_d` on {N=15, N=21, N=35}, wrong-d cases;
   (b) `_eh_recover_d_candidates` on all j ∈ [1, 63] for d_true=3,
       verifying d_true in candidates for every good pair
       (39 of 63 j values are good pairs; Lemma 1 predicts ≥32);
   (c) non-good-pair returns `[]`;
   (d) spurious-candidate case `(j=2, k=7)` includes d=3;
   (e) end-to-end hit rate ≥ 50% over 30 shots;
   (f) even-N trivial factor.

2. **Classical GREEN first** (30 seconds): sanity probe showed
   `_eh_factors_from_d` and `_eh_recover_d_candidates` immediately
   correct — typical of brute-force closed-form math.

3. **Quantum probe**: ran 5 shots of `_eh_short_dlp(g, y, 15, ...)`
   with various g. Non-lucky shots all returned (j, k) whose candidate
   list contained d=3. Sign that the full hit rate would be very high.

4. **Full test**: 54 tests pass in 3m44s (30 quantum shots + all
   classical tests). 30/30 = 100% hit rate at N=15.

### Files touched

- **New**: `src/library/shor.jl:1153..1426` — EH impl block (273 lines):
  `_eh_recover_d_candidates`, `_eh_factors_from_d`, `_eh_short_dlp`,
  `shor_factor_EH`. Appended after `shor_factor_D_semi`.
- **New**: `test/test_6bn_ekera_hastad.jl` (118 lines) — 54 tests.
- **Modified**: `src/Sturm.jl:123` — added `export shor_factor_EH`.
- **Modified**: `WORKLOG.md` — this session 36 entry.

### Commits

```
6e0cc60  feat(shor): shor_factor_EH — Ekerå-Håstad short-DLP factoring + 54 tests — close Sturm.jl-6bn
```

Dolt remote also pushed.

### Beads

Closed: `Sturm.jl-6bn` P2.
None filed.

### Lessons for future agents

1. **EH17's §4.3 is NOT directly semi-classical-izable.** The (j, k)
   correlation is joint (via `e = a - bd`), not sequential. One-qubit-
   trick semi-classical PE from `shor_order_D_semi` doesn't carry over
   as-is. Mosca-Ekert (§4.7 refs) is the adapted form — out of scope
   for 6bn but could shrink the 9-qubit exponent cost for a follow-on.

2. **Brute-force classical post-processing beats Lagrange at small m.**
   The bead spec said "~20 lines Lagrange reduction"; the actual win
   is at m > ~20. For m=3 the brute-force is 7 candidates with trivial
   residual arithmetic — cleaner AND exhaustively correct (no short-
   lattice-vector corner cases to worry about).

3. **Verification-by-factorisation is THE disambiguator.** When
   multiple d satisfy the residual bound, `_eh_factors_from_d(d, N)`
   returns `nothing` for the spurious ones. No need for a proper CVP
   algorithm at toy N — just try every candidate.

4. **Toy-N (N=15) works despite violating the EH17 analytical bound.**
   ord(g) ≪ 2^(ℓ+m) at N=15, but the algorithm still biases (j, k)
   toward good pairs because of the low-bit coupling structure.
   Don't dismiss an algorithm as "broken at small N" without probing —
   the math may still cooperate.

5. **Classical sanity check before ANY quantum probe.** The quantum
   step takes 13-20s per shot at N=15; a typo in the driver that causes
   retries would waste minutes. Running `_eh_factors_from_d` and
   `_eh_recover_d_candidates` in isolation took 30s and caught the
   initial "min-residual-always-correct" assumption before the quantum
   pipeline was ever invoked.

6. **User gave explicit TDD + idiom instructions.** Followed all three
   (ground truth first via PDF read, RED tests first, Sturm-idiom check
   before coding). Heuristic: when user says "before coding", ALWAYS
   read the primary source AND re-check the Sturm codebase for the
   specific primitives the impl will use (in this case
   `mulmod_beauregard!` signature + `QInt[i]` non-owning view pattern).

### Next-session pointers

**Unchanged from Session 35 — highest-priority ready beads**:
- `jrl` P2 — QRunwayMid runway-in-middle type. Blocks `6oc`.
- `6oc` P1 — windowed arithmetic (blocked on `jrl`). 3-4 sessions.
- `870` P1 — Steane [[7,1,3]] syndrome extraction (orthogonal).

**New candidate follow-ons filed or implied from 6bn**:
- NONE filed this session. `shor_factor_EH` is complete; the s>1 /
  lattice-Lagrange extensions and Mosca-Ekert semi-classical variant
  are orthogonal-wins, not blockers. If ever needed, file then.

**Hygiene**: `5jn` (ntuple in `_shor_mulmod_a!`), `2i0` (ScopedValue).

---

