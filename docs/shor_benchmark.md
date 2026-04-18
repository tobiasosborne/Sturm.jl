# Shor's algorithm benchmark — three implementations on N = 15

Per-implementation resource accounting and runtime on Orkan statevector
simulation (`EagerContext`). All measurements: `t = 3` counter qubits,
`L = 4` register qubits, `LIBORKAN_PATH=…/liborkan.so`, one machine
(the Sturm.jl-dev WSL2 box, 2026-04-18).

Ground truth for all three: N&C §5.3 at `docs/physics/nielsen_chuang_5.3.md`.

## Summary

| Impl | Idiom | HWM qubits | Capacity | Single-shot | Verdict |
|------|-------|-----------:|---------:|------------:|---------|
| A | value-oracle lift (`oracle_table(powermod(a,·,N), k)`) | 18 | 20 | **~75 ms** | practical; ~50% hit-on-`r=4` for `a=7` |
| B | phase-estimation HOF (`phase_estimate(U!, \|1⟩_L, Val(t))`) with in-place mulmod via compute-copy-uncompute QROM pair | **25** | **28** | **562 s (≈ 9.4 min)** | **test-infeasible** on this box; *not run* against the success-rate matrix |
| C | controlled-`U^{2^j}` cascade (Box 5.2 literal) | *TBD* | *TBD* | *TBD* | *pending* |

## Details

### Impl A — value-oracle lift (Exercise 5.14 / Eq 5.47)

- Peak live qubits: 7 (inside QROM); HWM 18 (QROM unary tree); capacity 20.
- One QROM call per shot (of `k ↦ aᵏ mod N`), `bit_width = t = 3`.
- 50-shot `a=7`: 46% hit on `r = 4`, 26% `r = 2` (divisor), 18% trivial `r = 1`.
- All seven coprime bases `{2, 4, 7, 8, 11, 13, 14}` at 30 shots each hit their expected order with 40–60% probability. End-to-end `shor_factor_A(15)` returns `{3, 5}` in ≥50% of trials.
- Tests: `test/test_shor.jl` `"Impl A: value-oracle lift (Ex 5.14)"` — all green.

### Impl B — phase-estimation HOF (§5.3.1 verbatim)

- Design choice: `_shor_mulmod_a!(y)` reversibly in-place, via compute–copy–uncompute:
  1. Allocate fresh L-qubit `z = |0⟩^L`.
  2. QROM forward: `z ⊻= f(y)` where `f(y) = (a·y) % N` (identity on `y ≥ N`).
  3. QROM inverse: `y ⊻= g(z)` where `g = f⁻¹` uses `a⁻¹ = invmod(a, N)`; `y` ends as `|0⟩`.
  4. Half-swap `y ↔ z` via 2L CNOTs.
  5. Deallocate `z`.
- `phase_estimate` then invokes `_shor_mulmod_a!` `1 + 2 + 4 + … + 2^{t-1} = 2ᵗ − 1 = 7` times under nested `when()` controls.
- **Measured one verbose shot** (2026-04-18, `a=7, N=15, t=3`):
  - `ỹ = 0` (decoded to trivial `r = 1`)
  - Elapsed: **562 225 ms = 9 min 22 s** for a single shot
  - `ctx.n_qubits` HWM: **25**
  - Orkan capacity: **28** (≈ 4 GB statevector)
  - Process RSS at kill: **9.6 GB**, 42 cores saturated
- **Test verdict: infeasible.** Even 1 shot per `@testset` would make the suite > 30 min; correctness never validated at scale. The phase-estimation HOF idiom combined with a QROM-backed in-place mulmod is expressive but resource-catastrophic for simulator benchmarking.
- Tests: `test/test_shor.jl` `"Impl B: phase-estimation HOF (§5.3.1)"` — skipped via `@test_skip` with a pointer to this benchmark.
- The impl B *code* is landed and exported (`shor_order_B`, `shor_factor_B`). It will run a single shot if invoked directly; callers are warned.

#### Why the blow-up

Per mulmod call, live qubits are `t + L (y) + L (z) + QROM_tree_ancillae ≈ 3 + 4 + 4 + 11 = 22`. 7 mulmod calls per shot, the peak inside any one call is 25 (observed). Orkan grows capacity additively (GROW_STEP = 4) to 28 during the first mulmod and stays there. Each Toffoli now iterates 2^28 = 268 M amplitudes (~ 4 GB). 14 QROM circuits per shot × ~30 Toffolis per QROM × 4 GB ≈ 1.7 TB of sequential memory traffic per shot. At ~20 GB/s RAM bandwidth on this box, that's the 9-minute floor.

A future re-implementation of impl B could replace the compute-copy-uncompute mulmod with an in-place permutation circuit (O(2^L) CNOT/Toffoli, no ancillae) — e.g. Grassl permutation synthesis or the Beauregard QFT-adder construction. That would keep the phase-estimation HOF idiom while dropping the peak to ~7 qubits like impl A. Deferred for now.

### Impl C — controlled-U^{2^j} cascade (Box 5.2 literal)

*Pending — to be filled by Opus proposer subagent #2.*

## Reproducing

```bash
# Impl A, fast
LIBORKAN_PATH=/home/tobiasosborne/Projects/orkan/cmake-build-release/src/liborkan.so \
  julia --project -e 'using Sturm; @context EagerContext() begin; for _ in 1:50; shor_order_A(7, 15; t=3); end; end'

# Impl B, one verbose shot (≈ 10 min)
LIBORKAN_PATH=/home/tobiasosborne/Projects/orkan/cmake-build-release/src/liborkan.so \
  julia --project -e 'using Sturm; @context EagerContext() begin; shor_order_B(7, 15; t=3, verbose=true); end'
```
