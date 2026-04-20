# Shor polynomial-in-L scaling — impl D vs impl C

Trace-only DAG scaling for Shor's order-finding across L ∈ [4, 14].
Measured 2026-04-20 via `test/bench_shor_scaling.jl` on
`TracingContext` (no statevector, no Orkan simulation). Closes the
scaling half of [`Sturm.jl-c6n`](../WORKLOG.md).

## Summary

**Impl D (Beauregard 2003 QFT-adder + modular arithmetic) grows
polynomially in L; impl C (precomputed c-U^{2^j} cascade with QROM)
grows exponentially.** At `L = 14 / t = 28`, impl D uses **83×
fewer total gates** and **6,240× fewer Toffolis** than impl C, and the
gap widens quadratically with L.

| Impl | Gate-count scaling (`t = 2L`) | Toffoli scaling (`t = 2L`) |
|------|------|------|
| **D** | `82.7 · L^3.36`  (R² = 0.997) | `5.72 · L^2.03` ≈ 6 L² (R² = 0.999) |
| **C** | exponential (see table; ~2^L) | exponential |

## Method

- **Context:** `TracingContext` records every gate as a DAG node. No
  Orkan statevector — RAM bounded by `node_count · 25 bytes` (per
  `src/channel/dag.jl` HotNode union). Device-cap irrelevant.
- **Cases:** for `L ∈ [4, 14]`, `t = 2L`, `N = 2^L − small_k`, `a = 2`
  (except L=4 which uses `N=15, a=7` for regression continuity with
  the original N&C Box 5.4 test). See `CASES` in `bench_shor_scaling.jl:303`.
- **Fit:** log-log linear regression over L ∈ {5, 6, 7, 8, 10, 11, 12,
  13, 14}. **L=4 and L=9 excluded as a_j-saturation outliers (see
  Caveats).**
- **Comparison target:** Gidney-Ekerå 2021 (arXiv:1905.09749,
  `docs/physics/gidney_ekera_2021_rsa2048.pdf`), abstract-circuit
  formula `0.3·n³ + 0.0005·n³·lg n` Toffolis for n-bit RSA factoring.

## Raw data

Columns are as captured by the bench trace. `wires` is the TracingContext
WireID-allocation count (not live HWM). `toff` is the CCX node count
(3+-wire gate with `ncontrols ≥ 1`). `est_gates` is the preflight cost
model's projection used to decide whether to run the case.

### Impl D (Beauregard arithmetic)

| L | t | wires | gates | toff | CX | Ry | Rz | wall_ms |
|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| 4 | 8 | 24 | 2,473 | 24 | 488 | 409 | 1,552 | 1,066 |
| 5 | 10 | 85 | 19,551 | 150 | 4,190 | 2,861 | 12,350 | 601 |
| 6 | 12 | 114 | 33,505 | 216 | 5,940 | 4,681 | 22,668 | 757 |
| 7 | 14 | 147 | 56,239 | 294 | — | — | — | 674 |
| 8 | 16 | 184 | 85,089 | 384 | 13,616 | 10,337 | 60,752 | 636 |
| 9 | 18 | 71 | 28,749 | 108 | — | — | — | 547 |
| 10 | 20 | 270 | 179,281 | 600 | — | — | — | 827 |
| 11 | 22 | 319 | 250,911 | 726 | — | — | — | 556 |
| 12 | 24 | 372 | 334,129 | 864 | — | — | — | 977 |
| 13 | 26 | 456 | 529,933 | 1,092 | — | — | — | 791 |
| 14 | 28 | 490 | 570,753 | 1,176 | 69,860 | 50,345 | 449,372 | 286 |

### Impl C (c-U^{2^j} cascade with QROM)

| L | t | wires | gates | toff | wall_ms |
|--:|--:|--:|--:|--:|--:|
| 4 | 8 | 284 | 8,305 | 1,984 | 5,193 |
| 5 | 10 | 425 | 21,961 | 5,040 | 922 |
| 6 | 12 | 594 | 55,609 | 12,192 | 1,000 |
| 7 | 14 | 791 | 136,641 | 28,560 | 966 |
| 8 | 16 | 1,016 | 328,289 | 65,408 | 1,001 |
| 9 | 18 | 1,269 | 774,937 | 147,312 | 1,045 |
| 10 | 20 | 1,550 | 1,803,241 | 327,520 | 1,218 |
| 11 | 22 | 1,859 | 4,146,385 | 720,720 | 1,435 |
| 12 | 24 | 2,196 | 9,438,673 | 1,572,672 | 2,001 |
| 13 | 26 | 2,744 | 44,304,209 | 6,815,536 | 9,146 |
| 14 | 28 | 2,954 | 47,712,281 | 7,339,808 | 5,383 |

Impl A and B skipped by budget at L ≥ 11 and L ≥ 8 respectively; see
`bench_shor_scaling.jl` preflight table for projected memory.

## Fit

Log-log regression for impl D over L ∈ {5…14} \ {9}:

```
ln(gates(L))  = 4.41 + 3.358·ln(L)        →  gates(L)   ≈ 82.7 · L^3.358   R²=0.997
ln(toff(L))   = 1.75 + 2.026·ln(L)        →  toff(L)    ≈ 5.72 · L^2.026   R²=0.999
```

A slope of 3.36 on gates at `t = 2L` corresponds to an `O(L^{2.36})`
dependence at fixed `t`, matching Beauregard 2003 §3's `O(n³ · k_max)`
with `k_max = L` (exact QFT). Specifically the Rz-heavy QFT-adder
(`add_qft!`) dominates the gate total, and CCX count stays at the
`6·L²` clean rate because modadd's two-controlled-Rz lowering is the
only Toffoli-producing block per modadd.

## Extrapolation to L = 1024 (RSA-1024 bitwidth)

| metric | impl D extrapolated (L=1024, t=2048) |
|---|---:|
| total gates | **~1.06 × 10¹²** |
| Toffolis (CCX) | **~7.16 × 10⁶** |
| wires allocated (monotone) | ~(2L+3+t)·2L ≈ 8 × 10⁶ |
| est. peak live qubits | 2L + 4 ≈ 2052 (D_semi: 2L + 4 ≈ 2052 too) |

**Gidney-Ekerå 2021 at n = 1024 (abstract circuit model):**
`0.3·1024³ + 0.0005·1024³·10 = 3.27 × 10⁸` Toffolis.

### How do these compare?

**Toffoli-to-Toffoli directly:** impl D extrapolates to ~7 × 10⁶
Toffolis, GE reports ~3.3 × 10⁸ Toffolis. On the face of it, **impl D
is 46× fewer Toffolis**. This ratio is misleading — it does NOT mean
Sturm beats Gidney-Ekerå. It reflects a counting-convention
difference:

- GE's "Toffoli" is an abstract circuit resource. Every non-Clifford
  operation is a Toffoli in that model.
- Sturm's CCX (what `toffoli` reports above) counts only 3+-wire gate
  nodes with `ncontrols ≥ 1` in the DAG — literally CCX nodes.
- Impl D encodes most of its work as **Rz rotations** in the QFT-adder
  (449,372 Rz at L=14), which in Sturm's DAG are RzNode entries, not
  CCX. Under Clifford+T compilation every non-Clifford Rz gets
  synthesised to ~log(1/ε) T gates (Solovay-Kitaev).

**Total-gates-to-Toffolis (also not apples-to-apples, but more
honest):** impl D ~1.06 × 10¹² vs GE ~3.3 × 10⁸. **Impl D is ~3,200×
more expensive** on this axis — 3.5 orders of magnitude.

This is consistent with:

> GE 2021 §1.1: "We reduce the Toffoli count when factoring RSA
> integers by over 10× [vs prior works]. … We estimate … a hundredfold
> less spacetime volume than comparable earlier works."

Impl D is *vanilla* Beauregard with no windowed arithmetic, no Zalka
coset representation, no oblivious carry runways. Those optimisations
are exactly what GE applies on top of the Beauregard baseline. Four
orders of magnitude is the expected cost of skipping them.

### Verdict on the "nice-to-have" target

The `c6n` acceptance criterion asked for the L=1024 extrapolation to
land "within an order of magnitude of the Gidney-Ekerå 2021 estimate".

**Not met, and the gap is expected.** Direct Toffoli-to-Toffoli is
deceptively under (metric mismatch); total-gates-to-Toffolis is
~3,200× over. Neither reading is within 10×. The polynomial scaling
claim — which *is* the primary acceptance criterion — **is met**
(R²=0.997 on an `L^3.36` fit out to L=14).

A closer-to-GE impl D would require: (a) Draper QCLA for the adder
(`Sturm.jl-adj`, open), (b) classical-operand adder / windowed
arithmetic (`Sturm.jl-3ii`, open), (c) coset representation. Those are
separate research beads.

## Caveats

### Outliers: a_j-saturation on small-order bases

Shor's phase-estimation cascade uses `a_j = a^{2^{t-i}} mod N`
precomputed classically per iteration. When `a` has small multiplicative
order mod `N`, many `a_j` values collapse to 1, and
`mulmod_beauregard!` in the Sturm impl D/D_semi short-circuits the
call (it's an identity). That deflates the observed gate count:

- **L=4, N=15, a=7:** `ord(7 mod 15) = 4`, so `a_j = [7, 4, 1, 1,
  1, 1, 1, 1]` at t=8. Only 2 of 8 mulmods fire. Bench gate count
  2,473 is ~3× under the no-skip projection.
- **L=9, N=257, a=2:** 257 is a Fermat prime, `ord(2 mod 257) = 16`,
  so at t=18 most `a_j` after the first four land on 1. Bench gate
  count 28,749 is **lower than L=8** (85,089), which is the clearest
  visible sign of the outlier.

Both cases were excluded from the log-log fit. The fit uses
L ∈ {5, 6, 7, 8, 10, 11, 12, 13, 14} — nine points, enough for a
statistically meaningful slope with R² = 0.997/0.999.

### Impl B and A gaps

Impls A (oracle-lift QROM) and B (phase-estimation HOF) were skipped
by the preflight at L ≥ 11 and L ≥ 8 respectively (14 GB and 52 GB
projected DAG memory on a 6.8 GB budget — see the `SHIP` summary in
`test/bench_shor_scaling.jl`). Their exponential dependence is
documented in `docs/shor_benchmark.md` (N=15 row) and in the `c6n`
bead body; the scaling-only bead ran C and D.

### Int64 overflow at L ≥ 18

The bench's preflight cost model uses `Int64` throughout and overflows
at L=18 for impl B (estimate ~2^60). Not triggered here
(`STURM_BENCH_MAX_L = 14`), but tracked as
[`Sturm.jl-guj`](../WORKLOG.md) P3.

## Reproducing

```bash
LIBORKAN_PATH=/path/to/liborkan.so \
  OMP_NUM_THREADS=1 \
  STURM_BENCH_MAX_L=14 \
  STURM_BENCH_ONLY=C,D \
  julia --project test/bench_shor_scaling.jl
```

~10–15 minutes on this device (30 GB, no GPU). All cases complete
inside the 6.8 GB per-case budget. The OOM watchdog at 4 GB free
never fires.

## References

- Beauregard (2003), *Circuit for Shor's algorithm using 2n+3 qubits*,
  quant-ph/0205095 — `docs/physics/beauregard_2003_2n3_shor.pdf`.
- Häner, Roetteler, Svore (2017), *Factoring using 2n+2 qubits with
  Toffoli based modular multiplication*, arXiv:1611.07995 —
  `docs/physics/haner_roetteler_svore_2017_2n2_shor.pdf`.
- Gidney, Ekerå (2021), *How to factor 2048 bit RSA integers in 8
  hours using 20 million noisy qubits*, arXiv:1905.09749 —
  `docs/physics/gidney_ekera_2021_rsa2048.pdf`.
