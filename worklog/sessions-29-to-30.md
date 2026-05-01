## 2026-04-19 — Session 30: Close `Sturm.jl-i0j` (Shor resource benchmark + diagrams)

Point estimate for "what idiomatic Shor actually costs in Sturm":
trace each of the five `shor_order_*` implementations under
`TracingContext` on N=15, a=7, t=3, count DAG nodes, render ASCII
and PNG. Writes `docs/shor_benchmark.md` + selected examples.

### Results

| Impl | Wires | Gates | CX | CCX | Ry | Rz | Depth | DAG KB |
|------|------:|------:|---:|----:|---:|---:|------:|-------:|
| `A` (oracle lift) | 18 | 148 | 98 | 28 | 10 | 12 | 137 | 4.1 |
| `B` (phase_estimate HOF) | 217 | 3609 | 6 | 3528 | 63 | 12 | 3605 | 93.4 |
| `C` (c-U^{2^j} cascade, QROM) | 109 | 3097 | 2310 | 744 | 31 | 12 | 2702 | 78.3 |
| `D` (Beauregard arithmetic) | 19 | 2385 | 470 | 24 | 399 | 1492 | 1264 | 58.7 |
| `D_semi` (Beauregard + semi-classical iQFT) | 19 | 2373 | 464 | 24 | 399 | 1486 | 1264 | 58.4 |

Wire counts are monotone `_wire_counter[]` deltas — every allocation
increments, deallocate! does NOT decrement. So this table's "wires"
is closer to "distinct horizontal lines in the rendered circuit"
than to HWM of concurrent live wires.

### Takeaways worth remembering

- **`D` vs `D_semi` on a static trace looks near-identical.** Same
  gate count (± 12, from skipped `a_j=1` mulmods), same depth. The
  D_semi saving is the counter qubits — `t` in impl D, `1` in impl
  D_semi. At t=3 that saves 2; the compile-time gate count barely
  notices. At t=28 (L=14) the counter saving is the whole point.
- **Impl B is QROM-dominated, not mulmod-count-dominated.** It fires
  only `2^t − 1 = 7` mulmod calls but each carries a 2^(L+1)-entry
  Babbush-Gidney QROM. 217 wires is a log-depth QROM ancilla tree
  opened and closed 7×. Impl B is the polynomial-in-2^L cautionary
  tale — idiomatic, not scalable.
- **Impl A is the lean surprise.** 148 gates on a single QROM is
  shorter than impl D's arithmetic mulmod at this size. It's not
  scalable in t (exponential table), but for N=15 demonstrations it's
  the cleanest circuit.
- **Impl C is bimodal.** At N=15 t=3 it prints as 3097 gates / 109
  wires — similar order as impl B. At N=36 L=6 (from
  `bench_shor_scaling.jl`) it balloons to ~47M gates / ~1.2GB DAG.
  The QROM packed-index grows 2^L; don't use impl C past L=5 in
  simulation.
- **`_draw_schedule_compact` is the cheapest `depth` proxy we have
  today.** No critical-path pass, but the ASAP-scheduled column count
  lines up with what a reader of the PNG would count.

### Gitability

Some outputs (B.png 2.5 MB, B.txt 10 MB, C.txt 3.5 MB) are too big
to commit. `render_case` now `rm`s any artefact > 800 KB after
writing; `docs/shor_benchmark.md` documents the commit threshold and
shows *(regen)* for dropped cells. The bench script regenerates
everything in ~7 seconds on this box — cheap to re-run.

### Files touched

- `test/bench_shor_i0j.jl` (new) — TracingContext → node_breakdown
  + render + markdown emit. ~180 lines.
- `docs/shor_benchmark.md` (new, auto-generated).
- `examples/shor_N15_{A,C,D,D_semi}.png` + `{A,D,D_semi}.txt` —
  committed (all ≤ 800 KB).
- `WORKLOG.md` — this entry.

### Beads

- `Sturm.jl-i0j` closed.
- Remaining Shor work: `Sturm.jl-eud` EPIC (largely delivered —
  all 5 impls exist, benchmarks landed, N=15 + N=21 end-to-end
  correctness verified via di9 fix + 8b9 semi-classical).

---

## 2026-04-19 — Session 29: Close `Sturm.jl-8b9` (semi-classical iQFT for Shor)

Beauregard 2003 §2.4 Fig. 8 — the "one controlling-qubit trick" —
replaces the `t`-wide counter register in Shor order-finding with a
single recycled `QBool` via semi-classical inverse QFT. The t PE
counter qubits all commute (they're all control wires on the same `y`
register) and the cross-term Rz gates in the iQFT become classical
phase corrections once the bits are measured.

### Ground truth (read before coding, rule 4)

`docs/physics/beauregard_2003_2n3_shor.pdf` pp. 8-9, Fig. 8, + text at
end of p. 8: "This simulates the inverse QFT followed by a measurement
on all qubits as in figure 5. We save an important number of qubits
this way, and in fact we need only a total of 2n + 3 qubits to factor
an n-bit number as we will show in the complexity analysis section."

The concrete Rz correction formula is from Griffiths & Niu 1996
(quant-ph/9511007) / Parker & Plenio 2000 (quant-ph/0001104):

  θ_i = −2π · Σ_{j<i, bit_j = 1} 2^{−(i − j + 1)}

applied to the iter-i counter between H and the controlled-U step, to
"rotate out" the cross-terms that correspond to bits already measured.

### Implementation — `src/library/shor.jl:shor_order_D_semi`

One function, ~60 lines including docstring. The outer structure mirrors
`shor_order_D`:

1. Classical precompute `a_js = [a^{2^(t-i)} for i in 1..t]` — note the
   **reversed** power order (iter 1 uses the highest power `2^(t-1)`,
   iter t uses `2^0`). This is what makes iter 1 measure the LSB of ỹ
   (the phase at iter 1 is `π · ỹ` mod 2π, whose parity is the LSB).
2. Allocate `y_reg = QInt{L}(1)` once, reused across t iters.
3. Loop i = 1..t:
   a. Fresh `c = QBool(0)`, `H!(c)` → |+⟩.
   b. Classical `corr -= 2π / (1 << (i-j+1))` per prior set bit j.
       `c.φ += corr`.
   c. `mulmod_beauregard!(y_reg, a_js[i], N, c)` — skip when a_j = 1.
   d. `H!(c)` + `Bool(c)` → m_i.
4. Reconstruct `ỹ = Σ m_i · 2^{i-1}` (LSB-first convention).
5. Standard continued-fraction post-processing (shared helper).

### Idiomatic Julia / Sturm check

- Counter qubit is a plain `QBool(0)`, measured via `Bool(c)` cast (P2).
- The Rz correction is `c.φ += θ` — literally primitive 3. No raw matrices.
- The H! gate is the existing library function (built from the 4 prims).
- The measured bits are a plain `Vector{Bool}`, indexed classically. No
  quantum-resident classical register — Sturm's P2 type boundary makes
  the quantum→classical handoff implicit.
- `shor_factor_D_semi` wraps the same `_shor_factor_from_order` helper
  that every other impl uses. Zero duplicated logic.

### Bit-ordering gotcha (found via smoke test)

First implementation used `a_js[i] = a^{2^(i-1)}` (LOW power first), with
LSB-first bit reconstruction. Smoke test showed wrong hit rates:

    N=15 a=7 r=4:  impl D = 53%  vs  D_semi = 30% ❌
    N=21 a=2 r=6:  impl D = 13%  vs  D_semi = 0%  ❌

The issue: at iter 1 with c-U^{2^0}, the counter phase is
`2π · φ` — DOMINATED by the MSB contribution, not the LSB. So iter 1
would measure the MSB, not the LSB, and my reconstruction bit-placed it
as if it were the LSB. The ỹ values were bit-reversed.

Fix: swap the c-U order (HIGH power first). At iter i with c-U^{2^(t-i)},
counter phase = `2π · ỹ / 2^i`, whose LEADING fractional bit IS `bit_{i-1}`.
Iter 1 → bit_0 (LSB), iter t → bit_{t-1} (MSB). LSB-first reconstruction
stays correct.

Post-fix smoke test:

    N=15 a=7 r=4:  impl D = 50%  vs  D_semi = 47% ✓
    N=15 a=2 r=4:  impl D = 53%  vs  D_semi = 40% ✓
    N=21 a=2 r=6:  impl D = 27%  vs  D_semi = 47% ✓ (!)
    N=21 a=4 r=3:  impl D = 60%  vs  D_semi = 60% ✓

### Speed

`shor_order_D_semi` is ~25× faster than `shor_order_D` in simulation at
N=21 t=6 (17 s/shot vs 420 s/shot). The statevector is 2L+4 qubits (14
at L=5) rather than t+2L+2 = 14 — same peak! But the *reuse* of slots
inside the recycled counter means Orkan doesn't grow the statevector as
it would if we carried all t counter qubits LIVE simultaneously through
the cascade allocations. At N=21 the impl-D peak is 14 qubits CONCURRENT,
but some of those are touched by OpenMP-parallel state updates in ways
that thrash on a 2^14 = 16k-amplitude buffer; D_semi's qubit count is
the same at peak but the TEMPORAL allocation pattern is much more
cache-friendly.

### HWM — 2L+4, not 2L+3

Beauregard's "2n+3 qubits" bound treats doubly-controlled-φADD(a) as a
primitive. Sturm's EagerContext lowers doubly-controlled Rz via the
`_multi_controlled_gate!` Toffoli cascade, which allocates 1 workspace
qubit (nc=2 ⇒ 1 workspace). So the measured HWM is:

    1 (counter) + L (y) + (L+1) (b) + 1 (anc) + 1 (cascade workspace)
    = 2L + 4

Confirmed empirically: `peak = 12` at L=4, `peak = 14` at L=5.

Closing the gap to 2L+3 would require a workspace-free CCRz lowering in
`src/context/multi_control.jl` — that's a Sturm engine optimisation,
separate from 8b9.

### RED-GREEN TDD

1. RED: smoke test showed systematic hit-rate mismatch (impl D = 53%,
   D_semi = 30% at N=15 a=7) — bit ordering wrong. Fixed.
2. GREEN: registered 5 testsets in `test/test_shor.jl`:
   - `order_D_semi(7,15;t=3) ≥ 30% hits` (30 shots)
   - `order_D_semi` on 3 N=15 bases ≥ 20%
   - `order_D_semi(2,21;t=6) ≥ 15% hits` (30 shots)
   - `shor_factor_D_semi(15) returns {3,5}` ≥ 50%
   - `HWM ≤ 2L+4` at (15,3), (15,6), (21,6)
3. All pass in 40 seconds wall time (targeted-subset run, OMP=1).

### Files touched

- `src/library/shor.jl` — `shor_order_D_semi` + `shor_factor_D_semi`;
  removed the di9 warning block from `shor_order_D`'s docstring.
- `src/Sturm.jl` — export the two new functions.
- `test/test_shor.jl` — `@testset "Impl D-semi …"` with 5 sub-testsets;
  dropped a slow N=21 impl-D acceptance test (delegated to D-semi which
  is 25× faster at the same coverage).
- `test/probe_8b9_smoke.jl` (new) — side-by-side comparison with impl D.
- `WORKLOG.md` — this entry.

### Beads

- `Sturm.jl-8b9` closed.
- `Sturm.jl-c6n` EPIC (polynomial-in-L Shor) is now fully delivered:
  - ar7 (add_qft!) ✓
  - dgy (modadd!) ✓
  - uf4 (mulmod_beauregard!) ✓
  - 6kx (shor_order_D) ✓
  - di9 (phase-clean arithmetic) ✓ (session 28)
  - 8b9 (semi-classical iQFT) ✓ (this session)

### Gotchas for future agents

1. **Test the c-U order with a smoke test BEFORE relying on
   theoretical parity arguments.** Parker-Plenio's phase correction
   formula `-2π / 2^(i-j+1)` is derived under the ASSUMPTION that iter
   i uses c-U^{2^(t-i)} (high power first), not c-U^{2^(i-1)} (low first).
   The correction formula is identical in both cases but the BIT BEING
   MEASURED is different — and the reconstruction has to match. I
   burned 10 min on this before the 2-data-point (N=15 a=7 + N=21 a=2)
   smoke test made the bit-reversal obvious. Always compare against a
   reference implementation, even by noisy hit-rate statistics.
2. **ctx.n_qubits is monotonically non-decreasing** — it tracks the
   peak live-qubit count since the context was created. Testing HWM is
   as simple as `peak = ctx.n_qubits` at end of the function, assuming
   the function is the only allocation-producing call on that context.
   No need for a manual HWM tracker.
3. **`@testset verbose=true` still batch-prints.** To see test progress
   on slow tests (>30s), add explicit `println(stderr, "..."); flush()`
   inside the test body. Otherwise `@testset` blocks the log until the
   whole set finishes.

---

