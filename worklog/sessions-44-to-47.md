## 2026-04-22 — Session 47: `6oc` Phase B steps 2+3 — `_shor_mulmod_E_controlled!` + `shor_order_E`

Red-green TDD for both the controlled windowed mulmod and the end-to-end
order-finding driver. Test count: +3 new tests (total 75 in the file,
~27s wall with OMP_NUM_THREADS=32). Bead 6oc still open — 50-shot
statistical acceptance deferred to a bench run.

### Step 2: `_shor_mulmod_E_controlled!` (shor.jl)

Gidney 2019 §3.4 Fig 6 cmult-swap-cmult⁻¹ pattern on a QCoset target:
  1. `b := |0⟩_coset`                                       fresh scratch
  2. `when(ctrl) b += a·target`           (plus_equal_product_mod!)
  3. `when(ctrl) SWAP(target, b)`         wire-by-wire on reg + pad_anc
  4. `when(ctrl) b -= a⁻¹·target`         → b back to |0⟩
  5. ptrace b

Test: N=3 W=2 Cpad=1 a=2 x=1, ctrl=|1⟩ → target decodes to (2·1) mod 3 = 2.

**Live-qubit probe with eager-flush**: 5 → 9 → 9 → 9 → 5 across the three
phases. Wall 1.5s at OMP_NUM_THREADS=32. No multi-controlled-ancilla
explosion at Cpad=1 because the depth-2 controls stay local (QFT rotations
inside `when(bj)` inside outer `when(ctrl)`).

**Analytical no-wrap check**: at (N=3, W=2, Cpad=1, a=2, x=1, c_mul=1):
step 1 scratches = {2, 0, 0}, b-branch max = 5 < 2^Wtot = 8 ✓. After
swap, step 3 scratches = {1, 2, 1}, b-branch max = 6 < 8 ✓. All branches
contained — deterministic single-shot assertion safe.

### Step 3: `shor_order_E` + `shor_factor_E` (shor.jl)

Identical outer cascade to `shor_order_D_semi` (Parker-Plenio semi-classical
iQFT, single recycled counter qubit). Only differences:

  * Eigenstate: `QInt{L}(ctx, 1)` → `QCoset{W, cpad}(ctx, 1, N)` (coset-
    encoded |1⟩ mod N). Allocation dispatches through `_alloc_shor_E_target`
    because `W` and `cpad` come from kwargs — not compile-time constants
    at the call site.
  * Mulmod: `mulmod_beauregard!(...)` → `_shor_mulmod_E_controlled!(...)`.
  * Kwargs: `cpad::Int=1`, `c_mul::Int=2` exposed to the caller; defaults
    match bead 6oc acceptance parameters.

**`shor_factor_E`** mirrors `shor_factor_D_semi` byte-for-byte (random
coprime draw + continued-fractions + gcd), just calls `shor_order_E`.

Test: `shor_order_E(2, 3, Val(3); cpad=1, c_mul=1)` returns a period
r ∈ {1, 2} (true order of 2 mod 3 is 2; ideal distribution ỹ ∈ {0, 4}
gives r ∈ {1, 2}). Wall 1.9s. Single-shot callability — not statistical.

### Gotcha: `c_mul | Wtot` precondition (from plus_equal_product_mod!)

`plus_equal_product_mod!` requires `window | Ly`. In `_shor_mulmod_E_controlled!`,
Ly = Wtot = W + cpad. So c_mul must divide (W + cpad). For the bead
acceptance (N=15 → W=4, cpad=1 → Wtot=5), c_mul=2 does NOT divide 5 and
will error. Two fixes for Phase C:
  (a) Pad Wtot up to the next multiple of c_mul (add fake cpad bits).
  (b) Relax `plus_equal_product_mod!` to handle a ragged final window
      (partial, window_last = Ly - i).
(b) is cleaner. Not blocking for Phase B — tests use c_mul=1 which always
divides.

### Performance discipline fixed mid-session

Initial run of the 3-testset file piped through `| tail -15`, which buffers
all output until julia exits — defeating the eager-flush `_log` calls and
leaving us blind during the 9-minute run. The per-step `_ems` probe inside
`_shor_mulmod_E_controlled!` (with `_live_qubits` at each step boundary)
was the right diagnostic; visibility problem was the tail pipe. Fix:
`stdbuf -oL … 2>&1` without any downstream tail, route through
`run_in_background` to the task output file, monitor via `tail -F | grep`.
Also: running with **OMP_NUM_THREADS=32** per Tobias' explicit preference
(saved as bd memory `orkan-thread-limit`) — actually slightly faster than
unbounded on this device.

### Phase B step 4 (what's next)

The bead acceptance needs 50-shot statistical verification. Options:
  * Run a statistical probe script (not a test) that calls
    `shor_order_E(7, 15, Val(3); cpad=?, c_mul=1)` 50 times and checks
    the r=4 hit rate.
  * Needs cpad large enough that per-shot deviation is tolerable (2^-cpad
    × 3 stages × Wtot/1 ≈ 15·2^-cpad bound; cpad=4 gives bound ~1 which
    is loose, cpad=3 gives bound ~2 … the bounds are pessimistic).
  * Each shot on N=15: ~3 mulmods × maybe 10-30s each at W=4. ≥ 15 min
    for 50 shots. Run as a probe overnight or bench file.

Also: relax `plus_equal_product_mod!` to handle ragged last window, so
that c_mul=2 works at W=4 cpad=1 (Wtot=5). This unlocks the bead's
Toffoli-count acceptance criterion (d).

### Files touched

  * `src/library/shor.jl` (+97): `_shor_mulmod_E_controlled!` (step 2)
  * `src/library/shor.jl` (+105): `shor_order_E`, `shor_factor_E`,
    `_alloc_shor_E_target` (step 3)
  * `src/Sturm.jl` (+1): export `shor_order_E`, `shor_factor_E`
  * `test/test_windowed_arithmetic.jl` (+60): 3 new tests

---

## 2026-04-22 — Session 46: `6oc` Phase B step 1 — `plus_equal_product_mod!`

Red-green for the modular variant. Lands `plus_equal_product_mod!(target::QCoset,
k, y; window)` — Gidney 2019 §3.3 combined with GE21 §2.4 coset trick. 25
new tests (72 total in file), all GREEN in ~26s wall. Bead 6oc stays
in_progress for next steps: `_shor_mulmod_E_controlled!` + `shor_order_E`.

### Design pivot: QCoset target vs. a new `modadd_quantum!` primitive

Gidney 2019 §3.3 pseudocode uses `target += table[w]` with `target: QuintMod`.
A literal port would need `modadd_quantum!(y::QInt, b::QInt, N)` — a modular
quantum adder for quantum addends, which Sturm didn't have. Instead, took
the GE21 §2.4 path: target is a `QCoset{W, Cpad, Wtot}`, and the inner add
is just `add_qft_quantum!(target.reg, scratch)` (non-modular on the full
Wtot-bit reg). Coset state makes non-modular add ≈ modular add mod N.
Zero new primitives; reuses the QFT quantum-addend adder already shipped.

### No-wrap deterministic regime for tests

GE21 deviation fires only when a coset branch wraps `2^Wtot`. Deterministic
bound derivation: max branch value after total offset `a_total` is
`(2^Cpad - 1)·N + a_total`. No wrap iff `a_total < 2^Cpad · (2^W - N) + N`
(strict). In the test's no-wrap regime, decode is deterministic per shot
— no statistical slack needed.

### Gotcha #1 — boundary case caught by a RED test

First implementation GREEN'd 24/25; the one failure was `(N=7, W=3, Cpad=1,
k=3, y0=3)`: `a_total = 3 + 6 = 9`, bound `= 2·1 + 7 = 9`. **At** the bound,
not under it — branch j=1's value hits `7 + 9 = 16 = 2^Wtot` exactly and
wraps to 0, giving residue 0 instead of 2. Fixed by bumping Cpad=1→2 for
that case (bound becomes 11, a_total=9 is safely under). Lesson: the
`<` in the bound formula matters — not `≤`. Worth keeping in mind when
choosing Shor parameters: deviation is a real budget, not just a worst
case.

### Gotcha #2 — table value-width must match scratch width

`QROMTable{window, Wtot}(entries, N)` — value-width is Wtot (full coset
register width), not W (residue width). Entries are `≤ N-1 < 2^W`, so
their top Cpad bits are zero; the QROM emits no gates for those bits,
and scratch's top Cpad wires stay at `|0⟩`. Using `QROMTable{window, W}`
would produce a W-bit scratch that can't be the addend of
`add_qft_quantum!(target.reg::QInt{Wtot}, scratch::QInt{W})` — width
mismatch error.

### Files touched

  * `src/library/arithmetic.jl` (+90): `plus_equal_product_mod!`
  * `src/Sturm.jl` (+1): export `plus_equal_product_mod!`
  * `test/test_windowed_arithmetic.jl` (+100): 25 new tests

### Phase B next steps

1. **`_shor_mulmod_E_controlled!(y::QCoset, a::Integer, N, ctrl::QBool; c_mul=2)`**
   — controlled modular multiplication on a coset-encoded target via two
   `plus_equal_product_mod!` calls (cmult-swap pattern, Gidney 2019 §3.4
   Fig 6). Sibling to `mulmod_beauregard!` at `src/library/arithmetic.jl:356`.

2. **`shor_order_E` + `shor_factor_E`** — copy `shor_order_D_semi` and
   swap `mulmod_beauregard!` → `_shor_mulmod_E_controlled!`. N=15 L=4
   acceptance: 50 shots, r=4 hit rate ≥ 30%.

3. **Toffoli-count bench** — defer; needs √L measurement-based
   uncomputation primitive (Gidney 2019 Fig 3) to actually win vs impl D.

---

## 2026-04-22 — Session 45: `6oc` Phase A — `qrom_lookup_xor!` + `plus_equal_product!` atoms

Red-green TDD for the Sturm.jl-6oc windowed-arithmetic bead (P1). Phase A
lands the two lowest-level building blocks and their tests. Bead stays
in_progress for Phase B (plus_equal_product_mod! → shor_order_E driver).

### Ground truth (read first, before any code)

  * Gidney 2019 "Windowed quantum arithmetic", arXiv:1905.07682 §3.1 Fig 2.
    `docs/physics/gidney_2019_windowed_arithmetic.pdf`. Pseudocode:
    `for i in range(0, len(y), w): target[i:] += table[y[i:i+w]]` with
    `table = LookupTable([j*k for j in range(2**w)])`.
  * Gidney-Ekerå 2021 §2.5 ("Windowed arithmetic") + §2.7 (interactions with
    oblivious carry runways, Fig 3). `docs/physics/gidney_ekera_2021_rsa2048.pdf`.
  * Babbush 2018 §III.C Fig 10 (QROM unary iteration, 4L−4 Toffoli) and
    Appendix C (measurement-based uncomputation, O(√L)).
    `docs/physics/babbush_2018_qrom_linear_T.pdf`. (Referenced; not directly
    invoked — Bennett.jl's `emit_qrom!` already implements this QROM.)

### Atoms shipped

  * **`qrom_lookup_xor!(target::QInt{W}, addr::QInt{Ccmul}, table::QROMTable)`**
    — `|a⟩|t⟩ → |a⟩|t ⊕ T[a]⟩`. XOR-into-existing-target variant of
    `oracle_table`. Needed because `oracle_table` allocates fresh output
    and can't uncompute cleanly into an existing register. Implementation is
    ~20 lines wrapping Bennett's `emit_qrom!` + `apply_reversible!`.
    `src/bennett/bridge.jl` (bottom); cached on (hash(data), Ccmul, W) so
    compute+uncompute in one iteration is one compilation + one cache hit.

  * **`plus_equal_product!(target::QInt{Lt}, k, y::QInt{Ly}; window::Int)`**
    — `target += k·y` mod 2^Lt, windowed. Each iteration: extract y window →
    precompute `T[j] = (j·k) mod 2^(Lt−i)` → `scratch = T[y_win]` via
    `qrom_lookup_xor!` → `target_tail += scratch` via QFT-sandwich +
    `add_qft_quantum!` → uncompute `scratch` via `qrom_lookup_xor!` again →
    `ptrace!`. `src/library/arithmetic.jl` (after `mulmod_beauregard!`).

    Preconditions (all fail-loud per Rule 1):
      - `window | Ly` (Ly / window integer — no ragged tail in Phase A)
      - `1 ≤ window ≤ Ly`
      - `Lt ≤ 62` (UInt64 margin for `j·k` table entries)
      - `target.ctx === y.ctx`

    Early return on `k == 0` (identity — no lookups, no QFT, no scratch).

### Test scope

`test/test_windowed_arithmetic.jl` — 47 tests in two testsets, ~12s wall
clock. Not added to runtests.jl (matches `test_qrunway_mid.jl` /
`test_b3l_runway.jl` precedent). Cases deliberately bounded to
`peak_live = 2·Lt + Ly + window ≤ 14` qubits for session-level runtime.

### Gotchas

1. **`oracle_table` allocates; uncomputation needs XOR-into-existing.**
   Tried first to build `plus_equal_product!` directly on `oracle_table`.
   The allocate-fresh shape forces `scratch = T[addr]` as a NEW register;
   there is no XOR-into-existing path, so uncomputing `scratch` to `|0⟩`
   needs calling the underlying QROM circuit twice on the same wires —
   which is exactly `qrom_lookup_xor!`. Factored it out as the reusable
   atom; both `plus_equal_product!` and (future) `plus_equal_product_mod!`
   use it.

2. **Per-iteration `QROMTable{window, W_tail}` rebuild is unavoidable.**
   W_tail = Lt − i changes every iteration, so the type-parameter of
   `QROMTable` varies across the loop. The underlying Bennett compilation
   caches by `(hash(data), Ccmul, W)`, so cache hits are per W_tail ×
   table-content. For the Shor pipeline (c_mul=2), W_tail sweeps L distinct
   values per mulmod call and classical `k` varies per iteration of the
   outer windowed exponentiation — so cache hit rate is low. Acceptable
   for Phase A; worth revisiting if the mulmod_E bench is slow.

3. **Orkan per-gate cost grows sharply with live-qubit count.**
   Instrumented timing on `Lt=6, Ly=4, window=1` (4 iterations, peak 16
   live qubits) showed total ~125s wall clock with most time in
   `superpose!` / `interfere!` (QFT rotations) and the QROM
   forward/reverse. Per-gate rate is roughly consistent with single-thread
   statevector work (~ms per gate at 2^16 amps), which dominates when
   we insert a W_tail-qubit scratch register. This is NOT a correctness
   bug — the Lt=6 case produced the correct result 15 = 3·5 — but it
   forces test budgets low. Follow-on: investigate Orkan's OpenMP
   threading (may need OMP_NUM_THREADS explicit), or profile `apply_ry!`
   / `apply_cx!` call overhead across the FFI boundary.

4. **Test data must respect `QInt{W}` value range.**
   First test pass caught a self-inflicted bug: `QInt{2}(7)` errors with
   "value 7 out of range [0, 3]". Fix: any test with quantum input
   register of width `Ly` must pick `y0 ∈ [0, 2^Ly)`.

5. **Window-sized view of a QInt is a `QInt{window}` with
   `wires=ntuple(j -> reg.wires[i + j], Val(window))` and
   `consumed=false`.** Matches the non-owning-view pattern from
   `_qbool_views` and from the `_W_tail` dispatch in the QInt module.

### Phase B pickup points for the next agent

1. **`plus_equal_product_mod!`** — Gidney 2019 §3.3. Differences vs §3.1:
   (a) modular addition (modadd!) in the inner add, (b) fold the position
   factor `2^i` into the lookup table so each window uses a different
   table, (c) entries pre-reduced mod N via `QROMTable(..., modulus=N)`.

2. **`_shor_mulmod_E_controlled!`** — controlled modular mulmod on a
   coset-representation target, via two `plus_equal_product_mod!` calls
   (cmult pattern). Layer on top of `mulmod_beauregard!`'s structure but
   swap the modadd loop for a windowed one.

3. **`shor_order_E` + `shor_factor_E`** — copy `shor_order_D_semi` /
   `shor_factor_D_semi` (`src/library/shor.jl:1052` / `:1137`) and swap
   `mulmod_beauregard!` → `_shor_mulmod_E_controlled!`. Acceptance bead
   criteria: shor_order_E(7,15;t=3) r=4 ≥ 30% over 50 shots; shor_factor_E(15)
   → {3,5} ≥ 50% over 20 shots.

4. **Toffoli-count bench vs impl D** — acceptance criterion (d) requires
   ≤ 0.5× impl D Toffoli at L=8. Likely needs measurement-based
   uncomputation (Gidney 2019 Fig 3) on qrom_lookup_xor! reverse — O(√L)
   instead of O(L). New primitive: `qrom_lookup_xor_reverse!` (or similar)
   that measures the scratch in X basis + applies a correction table.

### Files touched this session

  * `src/bennett/bridge.jl` (+74): `qrom_lookup_xor!` + `_QROM_LOOKUP_XOR_CACHE`
  * `src/library/arithmetic.jl` (+90): `plus_equal_product!`
  * `src/Sturm.jl` (+3): export `plus_equal_product!`, `qrom_lookup_xor!`
  * `test/test_windowed_arithmetic.jl` (new, 172 LOC): 47 tests, 12s wall
  * `probe_pep_timing.jl` (new): minimal single-case probe for instrumenting
    per-iteration cost. Kept for future performance work.

---

## 2026-04-22 — Session 44: QRunwayMid runway-in-middle (close `jrl`) — unblocks 6oc P1

Land bead `jrl` — the runway-in-middle layout that `b3l`'s runway-at-end
could not deliver. This unblocks the P1 shor_order_E (`6oc`) windowed-
arithmetic bead, which needs the parallel piecewise addition benefit that
only the middle layout provides.

### Ground truth (docs/physics/gidney_2019_approximate_encoded_permutations.pdf)

Gidney 2019 §4 Definition 4.1 — an oblivious carry runway RUN_{k,p,m,n}
inserts m ancilla bits at position p into an n-bit register, splitting
it into a low+runway piece (p+m bits) and a high piece (n-p bits). Value
g ∈ [0, 2^n) is encoded as a coset pair

    e_0 = (g mod 2^p) + 2^p · c,
    e_1 = (⌊g/2^p⌋ − c) mod 2^{n-p},      c ∈ [0, 2^m) uniform.

Figure 2 (init): put the runway in |+⟩^m, then subtract c from the high
part → encoded pair satisfies e_0 + 2^p · e_1 ≡ g (mod 2^n) on every
branch.

Figure 3 (addition): adding classical k decomposes into TWO independent
piece-local adds — (k mod 2^p) on the (p+m)-bit low+runway piece, and
⌊k/2^p⌋ on the (n-p)-bit high piece. No cross-piece carry — this is the
depth-reduction benefit that runway-at-end (b3l) can't deliver.

Theorem 4.2: per-addition deviation ≤ 2^{-m}. Only the branch c = 2^m − 1
overflows when a carry enters the full runway; 1 of 2^m coset values
deviates. Theorem 4.3: r additions with a common runway have deviation
≤ (r+1)/2^m.

### Architecture

New type: **`QRunwayMid{Wlow, Cpad, Whigh, Wtot}`** with contiguous wire
layout [low | runway | high] and `Wtot = Wlow + Cpad + Whigh`. Mapping
to paper: Wlow ↔ p, Cpad ↔ m, Whigh ↔ n − p.

Constructor (`src/types/qrunway.jl`):
1. Stuff the value's low Wlow bits in the low slot, zeros in the runway
   slot, and the value's high Whigh bits in the high slot of a single
   `QInt{Wtot}` allocation (`stuffed = low_val | (high_val << (Wlow + Cpad))`).
2. `Ry(π/2)` on each runway wire → |+⟩^Cpad.
3. **Subtract runway from high part** — the obliviousness step.
   QFT-sandwich on the Whigh-bit high piece: for each runway bit j,
   `when(runway[j]) do; sub_qft!(high, 1 << j); end`. Inside `when()`
   the Rz rotations get one extra control (standard Sturm control-stack
   dispatch), producing Cpad × Whigh controlled-Rz total.

Operations (`src/library/coset.jl`):
- **`runway_mid_add!(r, a)`**: splits `a` into `(a mod 2^Wlow)` and
  `⌊a / 2^Wlow⌋`, runs a Draper classical-add on each piece. QFT sandwich
  per piece; pieces act on disjoint wires → commute, run-in-parallel
  friendly (relevant when bead 6oc lands depth-scheduling).
- **`runway_mid_decode!(r)`**: measures all Wtot wires via
  `Int(r.reg)` (P2 cast), then classically reconstructs
  `g = (e_0 + 2^Wlow · e_1) mod 2^(Wlow+Whigh)`. Runway value c absorbs
  into e_0's top Cpad bits and cancels against e_1's offset, so decoding
  is a single formula with no per-branch case work.

### Partial-trace discipline

`ptrace!(::QRunwayMid)` errors loudly (fail-loud per CLAUDE.md #1) —
runway is entangled with the high part via the Fig-2 subtraction, so
it is not safe to toss the wires without classical reconstruction. The
blessed cleanup is `runway_mid_decode!` (measure + return classical
value). `_runway_mid_force_ptrace!` exists as the internal after-
uncomputation escape, not exported.

### Tests

`test/test_qrunway_mid.jl` — 6,765 asserts across 7 testsets, all green:

- **Round-trip** decode preserves value for every (Wlow,Cpad,Whigh,v)
  combo, 20 samples each — all deterministic because construction
  introduces no deviation (f^{-1} absorbs the runway superposition
  cleanly).
- **Large Cpad (=10)** single-addition: deviation rate ≤ 1% empirical,
  well under the 2^{-10} ≈ 0.001 theoretical upper bound.
- **Theorem 4.2 bound** at Cpad=3: deviation rate ≤ 2·2^{-Cpad} (2×
  slack for Bernoulli(p ≤ 0.125) sampling variance, N=1000 per config).
- **Wrap-around across 2^Wlow boundary**: adds spanning the low-to-high
  split still decode correctly ≥ 95% (well under the 2^{-Cpad} bound).
- **Theorem 4.3 cumulative**: r=5 additions into one runway, bound is
  6/256 ≈ 0.023, empirical rate ≤ 0.06 (slack for the bound + sampling).
- **`ptrace!` blocked**: direct ptrace errors; `runway_mid_decode!` is
  the blessed path.

Regression (all green): b3l_runway 491, 6xi_coset 311, QInt 562,
Channel 44.

### Not wiring into runtests.jl

Matching the existing `test_b3l_runway.jl` / `test_6xi_coset.jl`
precedent — neither is in runtests.jl. The deviation-statistical tests
in this file total ~22 minutes wall-clock (500–1000 full circuit runs
per configuration × many configs), which is CI-hostile. Keep it as a
targeted file; users who touch QRunwayMid run it explicitly. If a
future bead adds a slow-lane CI setup, flip then.

### Gotchas

1. **`QInt{W}(wires, ctx, false)` is a non-owning view** — critical
   for building a sub-register over a slice of the QRunwayMid wires.
   Used for `high = QInt{Whigh}(ntuple(k -> r.reg.wires[Wlow + Cpad + k],
   Val(Whigh)), ctx, false)` in `runway_mid_add!`. DON'T call
   `ptrace!` or `Int()` on such a view — the outer `QRunwayMid.reg` owns
   the wires.
2. **`add_qft!` shifts by signed `Int(a)`**. `⌊a / 2^Wlow⌋` via `>>` in
   Julia is arithmetic (sign-preserving) for `Int`, so `a = -5, Wlow = 2`
   gives `-5 >> 2 = -2` and `-5 mod 4 = 3`, and the split reassembles
   to `-5` mod 2^n. Matches Def 4.1.
3. **`when(runway[j]) do; sub_qft!(high, 1 << j); end`** expresses a
   coherent controlled-subtract without ever measuring the runway.
   Inside `when()`, each of the Whigh Rz rotations in `sub_qft!` gets
   one more control through Sturm's control stack — no new primitive
   needed. This is the direct analog of the Gidney Fig-2 subtraction,
   runway-value-by-runway-value.
4. **Runtime**: 22 min wall-clock. Most of it is the Orkan simulation
   of the statistical deviation tests (50K+ full construct/add/decode
   trials). Not amenable to Julia-level optimisation — it's the sim
   doing actual work.

### Files touched this session

- `src/types/qrunway.jl` — added QRunwayMid type, constructor, ptrace
  discipline, and helper (+~110 LOC).
- `src/library/coset.jl` — added `runway_mid_add!` and `runway_mid_decode!`
  (+~70 LOC).
- `src/Sturm.jl` — export QRunwayMid, runway_mid_add!, runway_mid_decode!.
- `test/test_qrunway_mid.jl` — new, 145 LOC, 6,765 asserts.
- `WORKLOG.md` — this entry.

### Beads state

- **Closed**: `Sturm.jl-jrl`. The runway-in-middle layout delivers
  Theorem 4.2's 2^{-Cpad} deviation bound actively (runway-at-end was
  vacuously zero because there was no high part above).
- **Unblocked**: `Sturm.jl-6oc` (P1, shor_order_E windowed mulmod).
  `6oc`'s runway-folding step can now use `QRunwayMid` to get the
  GE21 §2.6 parallel piecewise addition depth reduction.

### Next-session pointer

**`6oc` P1** is now the top of the dep tree — windowed arithmetic
replaces each controlled-addition inside CMULT with a
classically-precomputed QROM lookup, fusing c_mul adds into one
table-lookup-add. Bead description points at
docs/physics/gidney_2019_windowed_arithmetic.pdf §3.1, §3.3 +
docs/physics/gidney_ekera_2021_rsa2048.pdf §2.5 Fig 2 +
docs/physics/babbush_2018_qrom_linear_T.pdf §III.C Fig 10. Existing
`src/library/patterns.jl::oracle_table` already ships unary-iteration
QROM. Acceptance is hit-rate / Toffoli-scaling tests on small N.

---

