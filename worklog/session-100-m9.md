<!--
SPDX-License-Identifier: AGPL-3.0-only
Copyright (C) 2026 Tobias Osborne
Part of Sturm.jl.
-->

# Session 100 — M9 capstones implemented (bead 8oo9 + ctw2)

**Date:** 2026-07-23. **Role:** implementer (orchestrator reviews the diff; NOT
committed by this session). Design spec: `docs/design/m9-addq-inplace-perm-design.md`.

## What shipped

- `QMod{N,W,C}` (`src/types/qmod.jl`) — static modulus F24, `W = ndigits(N-1;base=2)`
  derived (`_modwidth`, `@assume_effects :foldable` so the WORKER `QMod{N}(ctx,v)` is
  `@inferred`-clean; the zero-context barrier is dynamic like `QInt{W}(n)`). `Int(y::QMod)`
  measurement cast added for readout.
- In-place-`Perm` compiler contract (`src/bennett/inplace.jl`): `verify_inverse_pair`
  → `compile_inplace_perm` → `CompiledInplacePerm{W}`, private `_compiled_inplace_perm`
  choke point (new boot lint in runtests.jl, mirrors `_ctrl`). Compute/swap/uncompute
  of two separately-compiled oracles into one frozen `Perm` on `2W+max(A_f,A_g)` wires
  (shared pool). Tier E = single-basis replay of each compiled Perm (`_replay_perm_basis`,
  gated by DATA width `W`, never `2^n`) + composite self-check. Tier P = registered
  `FullSpaceMulProof{N,W}`.
- `mulmod!` (`src/library/modular.jl`), `shor_order`/`_shor_phase_sample`/CF/LCM
  (`src/library/shor.jl`) — PRD §7.7 blocks execute verbatim.
- F23/ctw2: `BigInt(x)`/`BigInt(dual(x))` wide casts; `Int(x)` host-width guard;
  `_shift_width_guard` at add!/dual-modulation/qint-lit/pairing_exponent.

Full suite **26055/26055** (baseline 25750 → +305). N=3 statistical: 1000/1000, 0 wrong.

## GOTCHAS (load-bearing — read before touching mulmod!/Shor)

1. **Bennett v0.5 CANNOT compile the design's double-and-add.** The overflow-free
   fixed-`W` double-and-add (design §2 eq 2, using only +/−/compare) fails Bennett's
   LLVM IR extractor with `UndefValue operand: i8 undef` (loop/branch-carried
   accumulation → undef phi), and even a single branchy `a≥nb ? a-nb : a+b` hits
   `_narrow_inst: no method for Bennett.IRLoad`. **The only compilable modular multiply
   is `ifelse(v<N, (c*v)%N, v)`** (variant E). DEVIATION from the design, documented in
   modular.jl header: overflow-freedom is secured instead by (a) the covering type
   having ≥2W bits for the supported range (UInt8 ≥ 2·4 for W≤4; `(N-1)²≤225<256`) and
   (b) Tier-E exhaustive replay against `_ideal_mulmod_perm` — ANY silent overflow is a
   LOUD InverseContractError/self-check failure, so the fail-loud guarantee moved from
   the callable's internal form to verification.
2. **Bennett cannot narrow `*`/`%` to non-nibble `bit_width`.** W=3,4 work; **W≥5 fails**
   (`IRLoad` narrowing). So **mulmod! is supported only for N≤16 (W≤4)**. N=21 (W=5) does
   NOT compile — a Bennett limitation, not a qubit-budget one. `inc`/`+1` DO narrow at
   any W (addition-only), which is why the in-place *compiler* tests (inc/dec) run at W=2,3.
3. **Qubit budget for end-to-end Shor.** Peak = 2W(phase)+W(work)+scratch(B=W ∪ Bennett
   ancilla)+ctrl-borrow. N=3→16q (~31ms/sample, 1000-trial suite feasible); N=5→23q
   (~3-4s/sample, few exact calls only); **N=15→30q (~16GB, seconds-minutes/sample ×
   multiple samples = OVER the practical Orkan statevector budget)**. So N=15's capstone
   is verified at the PERM level (mulmod! bijectivity, cheap replay); its quantum order is
   not run in-suite. Statistical ≥1000 test is N=3; exact quantum orders at N=5/N=7.
4. **`BigInt(dual(k))` on |0…0⟩ is RANDOM** (F|0⟩ = uniform superposition), not 0. Do not
   assert a fixed value.
5. **Bennett is NOT on the main `--project` path.** Run the suite in an env that dev-deps
   both Sturm and Bennett (scratch env), or `Pkg.test()`. Direct `julia --project
   test/runtests.jl` cannot `using Bennett`.
6. The extension (`ext/SturmBennettExt.jl`) needed **no** changes — the existing
   `_BENNETT_BACKEND` already returns a `CompiledOracle`, exactly what the in-place
   compiler consumes twice (design's "ext additions" turned out unnecessary).

## Open / deferred

- N=17..? (W≥5) mulmod! blocked on Bennett `*`/`%` narrowing — needs a Bennett fix or an
  addition-only multiply Bennett can extract. File a follow-on if N=21 Shor is wanted.
- N=15 end-to-end quantum order needs a wider-than-statevector backend (or fewer ancilla).
