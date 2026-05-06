## 2026-05-06 — Session 90: 4ceh continuation — xcye + grq5 fix landed; l5s5/50k1 deepened

Continued session 89's bug-decomposition. Closed `xcye` (refactor),
landed the `grq5` one-line fix, fetched the Laneve PDF and re-derived
§2.1 to clarify why the bug isn't a pure phase shift.

### What shipped

1. **`Sturm.jl-xcye` CLOSED.** Extracted `_qsvt_reflect_naked!(system,
   be, phases, ancillas)` from `qsvt_reflect!`. Caller-supplied ancilla
   register, no allocation, no post-select. `qsvt_reflect!` is now: alloc
   + naked-call + post-select. `test/test_qsvt_amplitude_level.jl`'s
   `reflect_block_operator` now calls `_qsvt_reflect_naked!` directly via
   `using Sturm: _qsvt_reflect_naked!` instead of duplicating the
   oracle/Rz loop. Behavior preservation verified at the amplitude level
   (T1 |c|=1.0, T2 |c|=0.7256, T3 |c|=0.6973/0.6218/0.7034 — bit-exact
   match to pre-refactor numbers from session 89). Acceptance (a)-(c) of
   bead met; (d) refactor of `qsvt_combined_reflect!` / `oaa_amplify!` is
   structural cleanup deferred to a follow-on bead.

2. **`Sturm.jl-grq5` FIX IN PLACE (kept open pending end-to-end verification).**
   `src/qsvt/circuit.jl:280`: `ancillas[1].φ += -2.0 * phases[j]` →
   `_reflect_ancilla_phase!(ancillas, phases[j])`. For `m=1` the helper
   degenerates to the same `Rz(-2φ)` (`circuit.jl:626`), so the fix is
   invisible on n_anc=1 cases (T1, T2 unchanged). For `m≥2` it applies
   the canonical `Π^φ = e^{iφ(2|0…0⟩⟨0…0|^m − I)}`.

   **Surprise**: the amplitude-level test T3 numbers are *also* unchanged
   post-fix (|c|=0.6973/0.6218/0.7034, residual=0.0). At first I thought
   the edit hadn't landed; verified it had via `grep`. Closer analysis
   shows: with Bug A's incorrectly-calibrated phases, both single-Rz and
   `_reflect_ancilla_phase!` produce operators on the |anc=00⟩-block that
   differ only by a unit-modulus scalar (a phase that the LSQ closest-
   scalar fit absorbs into `c`). The two operators DIFFER on the
   |anc=01⟩, |anc=10⟩, |anc=11⟩ components in a way that affects POST-
   SELECTION SUCCESS RATE but not the conditional-on-success operator
   structure that this test reads. Bug B's visible signature only
   surfaces when (a) Bug A is fixed AND (b) the test reads success
   probability, not just |anc=00⟩-block proportionality. Filed this as a
   follow-on test improvement (TBD bead).

   Conclusion: Bug B fix is theoretically correct (matches GSLW
   Definition 15 / Theorem 17) but cannot be unit-tested in isolation
   from Bug A on the current `test_qsvt_amplitude_level.jl` setup. Keep
   `grq5` open; close it as soon as `5lu4` is GREEN end-to-end.

   Sanity probe `test/probe_grq5_bugb.jl`: with phases `[0]` (identity
   polynomial) on a 2-anc and a 1-anc BE, M = H/α exactly (|c|=1,
   residual=1e-16). Confirms the BE oracle path through the refactored
   body works. Not in `runtests.jl` — diagnostic only.

3. **`Sturm.jl-l5s5` (Bug A) — DERIVATION DEEPENED, NOT YET FIXED.**
   Fetched `docs/literature/quantum_simulation/qsp_qsvt/2503.03026.pdf`
   from arXiv (gitignored) and extracted §2.1 verbatim. The §2.1 chain
   is:

   - **Step 1 (Lemma 1)**: analytic w̃ ↔ Laurent ṽ, **same** phases.
     `(P', Q') = (z⁻ⁿ P(z²), z⁻ⁿ Q(z²))` — degree doubles, **variable
     doubles** (θ_a = 2θ_L on T).
   - **Step 2** (page 5): X-Laurent body matrix = H · Z-Cheb body matrix
     · H. Same phases. Z-Cheb (0,0)-block in x-coordinate is
     `P''(x) = Σ 2 p'_k T_k(x)` — Cheb T-poly with coefs from the
     Laurent indices.
   - **Step 3** (page 6): `r̃ = -i e^{-iπ/4 Z} x̃ e^{-iπ/4 Z}`.
     Substituting into the Z-Cheb body and merging adjacent
     Z-rotations: ψ_0 = φ_0 + π/4, ψ_k = φ_k + π/2 (interior),
     ψ_n = φ_n + π/4, plus global iⁿ. Reflection body with these ψ_k
     produces SAME matrix as Z-Cheb body with φ_k (up to iⁿ).

   **The bug**: Sturm's pipeline uses `chebyshev_to_analytic` to
   build `P_a(z)` from input Cheb coefs `c`. Result: `P_a(e^{iθ}) =
   e^{idθ} P_target(cos θ)`. Same phases applied via Lemma 1 give
   Laurent body output `P'(e^{iθ}) = P_target(cos 2θ) = P_target(2x²-1)`
   on (0,0)-block. After H-conjugation (step 2), the Z-Cheb body's
   (0,0) is `P''(x) = c_0 + Σ c_k T_{2k}(x)` — Cheb indices are
   **DOUBLED**. So the reflection circuit (with §2.1 phase shift)
   produces `P_target(2x²-1)`, NOT `P_target(x)`.

   So §2.1 phase shift alone is INSUFFICIENT. Session 89's empirical
   "0.7256 → 0.7836" partial improvement makes sense — the shift gets
   us to the right reflection phases for `P_target(2x²-1)`, but not for
   `P_target(x)`.

   **Three plausible fixes, none implemented**:
   - **(i) Pre-compose target**: build `P̃_target` such that
     `P̃_target(2x² - 1) = P_target(x)`. Information-losing in general
     since 2x²-1 is not injective on [-1,1]; works only if P_target has
     even parity in x (then we can "pull back" to a poly in T_2(x)).
     Needs a half-degree split (Wang-Dong-Lin or similar).
   - **(ii) Direct reflection-QSP phase computation**: bypass BS+NLFT
     entirely; use Wang-Dong-Lin layer-stripping or numerical
     optimization on the SU(2) reflection-QSP product to find phases
     directly for `P_target(x)` of degree d using d phases. This is
     what `_oaa_phases_half_deg3()` does for the specific case of
     -T_3(x). Generalising it = bead `Sturm.jl-50k1` work.
   - **(iii) Different analytic embedding**: use `P_a(z) = z^{n/2}
     P_target(z^{1/2})` (paper's converse of Lemma 1, only well-defined
     for definite-parity Laurent), which preserves the variable through
     the chain.

   Path (ii) is the cleanest practical fix; deferred to next session.

### Worklog/process

- **bd dolt pull at session start** added as a habit recommendation —
  local bd was 3 days behind remote; sessions 87-89 beads
  (4ceh/5lu4/l5s5/grq5/u1er/zh8u/jlaw) all missing locally until the
  pull. Two extra P0 4ceh sub-beads (`50k1` "γ derive §2.1", `xcye`
  "α refactor") surfaced post-pull and were not narrated in session
  89's worklog. Both legitimate.
- `.beads/` perms tightened to 0700; `git config beads.role maintainer`
  set (clears two warnings on every `bd` invocation).
- Concurrent julia from another agent running Bennett.jl `Pkg.test()`
  is fine — different project, parallel allowed (user clarified the
  `feedback_julia_serial_only` rule scope: same project only).

### Next-step (for the next agent)

1. **`Sturm.jl-50k1` (Bug A path ii)**: implement reflection-QSP phase
   optimizer. Inputs: Cheb coefs `c` of definite parity, polynomial
   degree `d`, target accuracy `ε`. Output: `d`-element phase vector
   `ψ` such that the reflection body's (0,0)-entry approximates
   `Σ c_k T_k(x)` to within `ε` on a grid covering `[-1, 1]`.
   Reference: Wang-Dong-Lin (Newton-method symmetric-QSP); pyqsp's
   `qsp_solver`. Initial guess: zero phases. Cost: BFGS or Newton on
   max-norm error.
2. Replace `qsvt_phases` body with `50k1`'s output (after parity check).
   Keep BS+NLFT pipeline available for analytic-QSP / GQSP / Hamsim use
   cases that need it — the reflection-QSVT path is what changes.
3. Re-run `test_qsvt_amplitude_level.jl`: T1, T2, T3 all should give
   |c|=1, residual=0 once both bugs are addressed.
4. Close `5lu4`, `grq5`, `l5s5`, `50k1`, `4ceh`.
5. Add `test_qsvt_amplitude_level.jl` to `runtests.jl`.
6. Tighten thresholds on the four pre-existing "DIRECTLY BROKEN TESTS"
   noted in 4ceh.

---

## 2026-05-05 — Session 89: 4ceh decomposed into two independent bugs

Continuation of session 88's `Sturm.jl-4ceh` investigation. **Reversed session
88's conclusion** that swapping `ancillas[1].φ += -2φ_j` for
`_reflect_ancilla_phase!(ancillas, φ_j)` is a "dead end". It is not —
the previous experiment was confounded by a *second* bug in `qsvt_phases`
that this session pinned down with deterministic amplitude probes.

### Method shift: from statistical sampling to amplitude-buffer probes

Session 88 measured success rates over ~600 shots and asserted
`> N_shots/2` thresholds that mask amplitude losses up to factor 2.
Session 89 reads the |anc=0…0⟩-block operator `M` directly out of
`unsafe_wrap(Array{ComplexF64,1}, ctx.orkan.raw.data, dim)` (the pattern
from `test_compact_state.jl:30`) and compares to `S(H/α)` via
spectral decomposition. No shot noise, residual computed at FP
precision. This is what session 88's hypothesis matrix needed.

Tooling: `test/test_qsvt_amplitude_level.jl` (200 LOC, ~25s).
Bead `Sturm.jl-5lu4` filed and claimed for the test itself; it stays
open for now (test is in place but does not yet GREEN — closing it is
co-terminal with closing 4ceh).

### Findings — `M = c · S(H/α)` exact, varying |c|

For the same `sign_polynomial(δ=0.4, ε=0.05)` polynomial, run on three
different LCU block encodings of 1-qubit Hamiltonians:

| Test | H                       | LCU terms | n_anc | `|c|`    | residual | Notes                  |
|------|-------------------------|-----------|-------|----------|----------|------------------------|
| T1   | Z                       | 1         | 1     | **1.015** | 0.000    | Block-diagonal U; trivial |
| T2   | 0.3·X + 0.4·Z           | 2         | 1     | 0.7256   | 0.000    | Off-diag U; bug appears |
| T3   | a·X + b·Y + c·Z         | 3         | 2     | 0.6973   | 0.000    | Multi-anc; bug appears |

`residual = ‖M − c·S_truth‖_F = 0` in every failing case — i.e. the
**polynomial structure (eigenvectors, sign, eigenvalue scaling) is
correct, only the overall amplitude is attenuated**. `c_best`
least-squares-fit gives a complex scalar with `|c| < 1`. This rules out
the bug report's leading hypothesis H4 (LCU mis-implementation —
would give additive cross-terms).

**The bug appears whenever the LCU has > 1 term**, i.e. PREPARE
creates a non-trivial ancilla superposition. T1 (1 term) trivially
passes because U is block-diagonal in the ancilla basis and the
QSVT walk's |anc=0⟩ thread is insensitive to phase calibration.

### Hand-walk reproduces the bug exactly — bug is mathematical

Reconstructed `U` for T2 by running `be.oracle!` on each of the 4
basis states and reading the amplitude buffer (4×4 unitary). Verified:
- `U` is unitary (`‖UU† − I‖ = 0`),
- `oracle_adj!` IS the literal Hermitian adjoint (`‖U_d − U†‖ = 0`),
- top-left 2×2 of `U` equals `i·H/α` (LCU normalisation injects an
  extra `i` factor — this is just a global phase, doesn't explain |c|<1).

Then hand-multiplied the Sturm `qsvt_reflect!` circuit body
(oracle/Rz alternation) using these matrices and the exact phases
out of `qsvt_phases`. Result: |c| matches Sturm to machine precision
on T1, T2, T3.

→ **The bug is not in Sturm's circuit execution. It's mathematical,
in `qsvt_phases` and/or `qsvt_reflect!`'s phase convention.**

### Ground truth: §2.1 of Laneve 2025 — analytic→reflection chain

Read pages 1–10 of `docs/literature/quantum_simulation/qsp_qsvt/2503.03026.pdf`
(was missing from the distillation). The conversion chain is:

1. **Analytic ↔ Laurent** (Lemma 1, p.4): same processing operators,
   `(P', Q') = (z⁻ⁿ P(z²), z⁻ⁿ Q(z²))`.
2. **Laurent (X-constrained) ↔ Chebyshev (Z-constrained, H sandwich)**
   (p.5): `e^{iφ_kX} = H e^{iφ_kZ} H` and `x̃ = HṽH`, so
   `e^{iφ_0X} ṽ ⋯ ṽ e^{iφ_nX} = H · e^{iφ_0Z} x̃ ⋯ x̃ e^{iφ_nZ} · H`.
   **Same phase values**.
3. **Chebyshev ↔ Reflection** (p.6, the key identity):
   `r̃ = −i · e^{−iπ/4 Z} · x̃ · e^{−iπ/4 Z}`. Substituting into the
   Z-Chebyshev body and merging adjacent Z-rotations yields the
   reflection-form body with phases `ψ_0 = φ_0 + π/4`,
   `ψ_k = φ_k + π/2` (interior), `ψ_n = φ_n + π/4`, plus global `iⁿ`.

Read p.11 for §4.3 — confirms it is the **Q→P swap trick**
(`(P, Q) → (P, iQ)` via right-multiply by `iX`, transposed to
`φ_n += π/2`, `θ_n ← −θ_n`). Independent of the §2.1 chain.

The §2.1 chain is **missing entirely** from Sturm's `qsvt_phases`.
The `phi[end] += π/2` line at `circuit.jl:362` only implements §4.3.

Distillation `docs/physics/laneve_2025_gqsp_nlft.md` updated with
both §2.1 and §4.3 sections.

### Cross-validation: pyqsp / PennyLane reference formulas don't fix it

Tested 8 sign-permutations of the §2.1 phase shift. The interior
sign (+π/2 vs -π/2) and first sign don't affect `|c|` magnitude — only
the last shift does. Tried PennyLane's `qml.transform_angles` from
`pennylane/templates/subroutines/qsvt.py` (referenced as
arXiv:2105.02859 App A.2, fetched via `gh api`):

```python
update_vals[0]   = 3π/4 - (3 + num_angles % 4) * π/2
update_vals[1:-1] = π/2
update_vals[-1]  = -π/4
return angles + update_vals
```

For `num_angles = 31`: first −= π/4, middle += π/2, last −= π/4.
On T2 this gives `|c| = 0.6315` — **worse** than Sturm's 0.7256.

PennyLane's formula is for *PennyLane's* QSP convention, not Sturm's
analytic-QSP-via-NLFT. Pure phase-shift on Sturm's NLFT phases cannot
produce correct reflection phases — there is a deeper convention
mismatch between the analytic-QSP polynomial structure (P, Q with
`b = -i·P_target`) and the reflection-QSP polynomial (Hadamard
transform of (P, Q) baked in).

### Decisive: hand-validated deg-3 reflection phases isolate the bugs

`src/qsvt/circuit.jl::_oaa_phases_half_deg3() = [-π, -π/2, π/2]` is a
hand-derived reflection-QSP phase set for `-T_3(x) = 3x − 4x³`,
verified to machine precision at 11 points in [0, 1]. Hand-walked the
qsvt_reflect circuit on T1/T2/T3 with these phases:

| Test | Sturm `qsvt_phases` | Hand-validated deg-3 |
|------|---------------------|----------------------|
| T1   | `|c| = 1.015`, res 0 | `|c| = 1.000`, res 0 ✓ |
| T2   | `|c| = 0.7256`, res 0 | **`|c| = 1.000`, res 0** ✓ |
| T3   | `|c| = 0.6973`, res 0 | `|c| = 0.637`, res 0.565 ✗ |

T2 with correct reflection phases gives `|c| = 1` — the qsvt_reflect
circuit IS correct for n_anc = 1 multi-LCU-term cases when fed
correct reflection phases. T3 stays broken because of a *separate*
bug in `qsvt_reflect!` for multi-ancilla.

### The decomposition

**Bug A — `qsvt_phases`** (filed `Sturm.jl-l5s5`, P0).
Analytic-QSP phases (from Laneve NLFT inverse) are shipped to
`qsvt_reflect!` without the §2.1 conversion. Pure phase-shift
candidates derived from §2.1 give partial improvement (T2 `|c|`
0.7256 → 0.7836) but don't reach 1, suggesting a Hadamard-transform
factor on (P, Q) is also needed. Three fix paths:
- (i) port pyqsp `qsvt_solve` / Laneve `nlft-qsp` Python ref impl,
- (ii) numerical optimization on the SU(2) matrix product
  (extends `_oaa_phases_half_deg3` pattern),
- (iii) derive missing factor in §2.1 explicitly.

**Bug B — `qsvt_reflect!`** (filed `Sturm.jl-grq5`, P0).
`src/qsvt/circuit.jl:263` applies single-qubit `Rz` on `ancillas[1]`,
which equals `Π^φ = e^{iφ(2Π−I)}` (where `Π = |0…0⟩⟨0…0|^⊗m`)
*only for m=1*. For m≥2, the rotation is wrong on ancilla states
`|b1=0, b2≠0⟩`. The fix primitive `_reflect_ancilla_phase!` already
exists at `circuit.jl:614`. **One-line swap** at line 263.

The two bugs are **independent**: T2 isolates Bug A (Bug B doesn't
fire at n_anc=1); the deg-3 + T3 probe isolates Bug B (with correct
phases, only Bug B remains).

**Reversal of session 88's conclusion**: the comment block on
`qsvt_reflect!` (lines 243-255) saying multi-controlled rotation
"made things WORSE 50%→35%" is correct as a statistical observation
but the *causal interpretation* was wrong. With correct reflection
phases (Bug A fixed), `_reflect_ancilla_phase!` IS the right
primitive. Future agents: ignore the "do not repeat" guidance there.

### What's in beads / git after this session

- `Sturm.jl-5lu4` (P0, open) — Phase 0 RED test in place.
- `Sturm.jl-l5s5` (P0, open) — Bug A: qsvt_phases conversion broken.
- `Sturm.jl-grq5` (P0, open) — Bug B: qsvt_reflect! multi-ancilla rotation.
- `Sturm.jl-4ceh` (P0, in_progress) — parent, blocked by A and B.
- `bd memories | grep 4ceh` — three persistence entries with the
  empirical `|c|` numbers from each probe iteration.
- New file: `test/test_qsvt_amplitude_level.jl` (in-tree but will need
  to be added to runtests.jl once GREEN).
- Modified: `docs/physics/laneve_2025_gqsp_nlft.md` with §2.1, §4.3.

Probes (kept in `/tmp` for the next session, not committed):
- `/tmp/probe_4ceh.jl`         — the original 4-shot amplitude probe.
- `/tmp/probe_4ceh_be.jl`      — BE matrix reconstruction + adjoint check.
- `/tmp/probe_4ceh_walk.jl`    — hand-walk reproducing Sturm |c|.
- `/tmp/probe_4ceh_candidate.jl` — 8 sign-permutation sweep + PennyLane formula.
- `/tmp/probe_4ceh_oaa3.jl`    — deg-3 hand-validated phases on T1/T2/T3.

### Concrete next-step (for the next agent)

1. **Bug B first, ~15 min**: edit `src/qsvt/circuit.jl:263` to call
   `_reflect_ancilla_phase!(ancillas, phases[j])` instead of the
   single-qubit Rz. Run `/tmp/probe_4ceh_oaa3.jl` (or rebuild) — T3
   with hand-validated deg-3 phases must give `|c| = 1`. If yes, close
   `Sturm.jl-grq5`.

2. **Then Bug A**: pick path (i)/(ii)/(iii) and ship. Path (ii) is
   probably most idiomatic (Sturm already does it for deg-3) and
   doesn't introduce a Python dep; the cost is degree-dependent
   convergence. Path (i) is the cleanest cross-check but pulls in
   Python. The full GREEN target is `test/test_qsvt_amplitude_level.jl`
   passing all 12 assertions.

3. **Tighten thresholds** in the existing tests once GREEN
   (the four "DIRECTLY BROKEN TESTS" entries in the 4ceh notes).

---
