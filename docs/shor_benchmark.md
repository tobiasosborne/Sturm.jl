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
| C | controlled-`U^{2^j}` cascade (Box 5.2 literal) with packed-QROM controlled mulmod | **26** | **28** | **302 s (≈ 5.0 min)** | correctness ✓ (one-shot verified r=4 for a=7, N=15); test-infeasible on this box |

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

- Design choice: for each counter qubit `j`, precompute `a_j = a^{2^{j−1}} mod N` classically (replaces Box 5.2's quantum squaring with a plain `powermod`), then emit exactly one controlled "multiply `y` by `a_j` mod `N`" circuit per counter qubit. Total mulmod calls per shot: `t = 3` (vs impl B's `2^t − 1 = 7`).
- **Packed-QROM optimisation for the controlled mulmod.** Naively wrapping `_shor_mulmod_a!` in `when(counter[j])` (impl B-style) produces multi-controlled gates on every QROM gate and reproduces impl B's resource profile. Instead, `_shor_mulmod_controlled!` folds the control wire **into the QROM's classical truth table** as an extra index bit:
  ```
  f_j : (ctrl, y) ↦ ctrl ? (a_j · y) mod N : y
  ```
  The two QROMs run under `with_empty_controls` — every gate is a direct `orkan_ccx!` / `orkan_cx!`, never multi-controlled. The index width grows from `L = 4` to `L + 1 = 5`, so the table has `2^5 = 32` entries (vs impl B's 16) and the unary-iteration tree is one level deeper.
- **Measured one verbose shot** (2026-04-18, `a=7, N=15, t=3`):
  - `ỹ = 2`, decoded `φ = 2/8 = 1/4` → **r = 4** ✓ (correct; Box 5.4 canonical).
  - Total elapsed: **302.4 s (5 min 2 s)**.
  - Per-stage wall time (eager-flush log, `src/library/shor.jl`):
    - classical precompute + QROM compile + superpose + eigenstate: < 10 s.
    - mulby `a_1 = 7`: **101.8 s**  (QROM_f + QROM_g + half-swap + dealloc).
    - mulby `a_2 = 4`: **97.8 s**.
    - mulby `a_3 = 1` (identity, but still emits the full packed-QROM circuit): **92.8 s**.
    - interfere!: 2.8 s. discard! + measure + decode: 1.5 s.
  - `ctx.n_qubits` HWM: **26** (one higher than impl B); Orkan capacity: **28** (same as B).
- **Test verdict:** correctness verified by one shot, but 302 s/shot makes any hit-rate test multi-hour. Tests `@test_skip`-ed like impl B.

#### Why the packed-QROM optimisation didn't change the resource class

The optimisation target was the right one — impl B's gates become multi-controlled via the `when()` stack and each Orkan `apply_ccx!` inside the QROM decomposes into a cascade. Packing the control into the index makes those gates unconditional.

However, **peak qubits are dominated by the QROM unary-iteration tree, not the gate cascade**. Extending the index from 4 to 5 bits grows the tree from ~11 to ~15 ancillae (roughly `2·(2^{W_in} − 1)`) with compute-uncompute allocated simultaneously. Live HWM goes **up**: impl B's peak inside a mulmod is 25, impl C's is 26.

Orkan's additive `GROW_STEP = 4` then pushes capacity to the same 28 qubits in both cases, and **every Toffoli touches 2^28 ≈ 268 M amplitudes regardless of whether it was unconditional or multi-controlled**. The 46% wall-time saving (302 s vs 562 s) comes from impl C's fewer mulmod calls (`t = 3` vs `2^t − 1 = 7`); the "unconditional vs multi-controlled" dimension of the optimisation was essentially a wash on Orkan.

**Lesson for Sturm idiom discovery:** on a statevector simulator, peak qubit count is the dominant cost. Any mulmod construction that keeps an L-qubit ancilla simultaneously live alongside the QROM's index tree will share the resource class of impl B / impl C regardless of control-stack cleverness. Matching impl A's class requires either (a) no ancilla register (direct permutation circuit via Grassl synthesis, or in-place Beauregard QFT-adder) or (b) dropping the cascade structure entirely (impl A's single-oracle approach). Neither is a tweak — both are full re-architectures.

## Reproducing

```bash
# Impl A, fast
LIBORKAN_PATH=/home/tobiasosborne/Projects/orkan/cmake-build-release/src/liborkan.so \
  julia --project -e 'using Sturm; @context EagerContext() begin; for _ in 1:50; shor_order_A(7, 15; t=3); end; end'

# Impl B, one verbose shot (≈ 10 min)
LIBORKAN_PATH=/home/tobiasosborne/Projects/orkan/cmake-build-release/src/liborkan.so \
  julia --project -e 'using Sturm; @context EagerContext() begin; shor_order_B(7, 15; t=3, verbose=true); end'
```
