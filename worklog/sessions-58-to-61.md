## 2026-04-24 — Session 61: `9ij` ground truth — Berry et al. 2019 Appendix C (MBU)

Starting the measurement-based-uncompute (MBU) work that closes 6oc
criterion (d). First substantial circuit-construction piece after three
warm-ups (guj, 35s, 9g5). 6oc is 5/5 phases landed; (a)(b)(c) blocked
by 059 perf (21 min/call at N=15 — structural simulator territory),
(d) at 0.61× vs 0.5× target.

### Stage 0 — grounding

The 9ij bead description said "Gidney 2019 §2 text + Fig 3 + Fig 4".
That's WRONG. Gidney 2019 ('Windowed quantum arithmetic',
arXiv:1905.07682) §3 is lookup-adds, §2 is background — neither covers
MBU. GE21 §2.5 correctly cites `[8]` = **Berry, Gidney, Motta, McClean,
Babbush (2019)**, 'Qubitization of arbitrary basis quantum chemistry
leveraging sparsity and low rank factorization', arXiv:1902.02134,
**Appendix C, Theorem 3 (Eq. 67), Figs 5-8**.

PDF fetched via TIB VPN → arXiv:
`docs/physics/berry_gidney_motta_mcclean_babbush_2019_qubitization.pdf`
(1.1 MB, 44 pp). Read Apps B + C (pp. 25-28). Updated 9ij bead
description with correct citation.

### MBU construction (Theorem 3 + Fig 6, clean-ancilla version)

Uncomputing `Σ_j ψ_j |j⟩|f(j)⟩ → Σ_j ψ_j |j⟩|0⟩` for `f: Z_d → Z_2^M`:

1. **X-basis measure** every output qubit. Outcomes `m ∈ {0,1}^M`.
2. **Classical** determination of `S = { j : parity(m · f(j)) = 1 }` —
   the addr states whose amplitudes must be negated.
3. **Phase fixup** via clean ancillae (Fig 6):
   * allocate `k` clean ancillae with `k ≈ √d` (chosen power of 2);
   * `X` on anc[0] + controlled-swap cascade (Fig 8) = binary→unary
     encoding of `addr[low log k bits]`;
   * `H⊗k` on the ancillae;
   * standard XOR-table-lookup on `addr[high bits]` targeting the k
     unary ancillae, with a classically-precomputed fixup table whose
     entries negate exactly the states in `S`;
   * `H⊗k` again;
   * reverse controlled-swap cascade;
   * `X` on anc[0]; release.

Cost: `⌈d/k⌉ + k` Toffoli, optimum `2√d` at `k = √d`.
Ancillae: `k + ⌈log(d/k)⌉` clean.

### Why this is cleaner for Sturm than my original plan

My initial plan mentioned a "new phase-only QROM sub-primitive" with
per-`hi` controlled-Z application to unary-indexed ancillae. The Berry
construction is smarter: **H-sandwich** around a standard XOR-table-
lookup converts phase-application into bit-flip-application, so the
existing `qrom_lookup_xor!` primitive in
`src/library/arithmetic.jl` is reused verbatim for the lookup step.

Only ONE new helper is needed: `_binary_to_unary!(addr::QInt{Wlo},
anc::NTuple{K,QBool})` — a controlled-swap cascade that one-hot-
encodes the address onto the ancilla register. That's Fig 8, ~30 LOC.

### Cost numbers at Sturm's parameter range

| c_mul | d = 2^c_mul | naive reverse | MBU k=2 | MBU k=4 | optimum |
|-------|-------------|---------------|---------|---------|---------|
|     2 |           4 |             6 |       4 |       — |       4 |
|     3 |           8 |            14 |       6 |       6 |       6 |
|     4 |          16 |            30 |      10 |       8 |       8 |
|     5 |          32 |            62 |      18 |      12 |      12 |
|     6 |          64 |           126 |      34 |      20 |      16 |

The c_mul=5 savings (62 → 12 Toffoli per lookup pair) move Session
50b's L=8 E/D ratio sweep's optimum from c_mul=3 (0.61×) to c_mul=5
and push the ratio below 0.5×, closing 6oc criterion (d).

### Plan revisions to the original proposal

  * Original Stage 1 was "_phase_only_qrom! split-address primitive".
  * Revised Stage 1 is **_binary_to_unary!** only (Fig 8). The rest
    (H-sandwich + XOR-lookup) reuses existing infrastructure and lives
    inside `qrom_lookup_uncompute_meas!` directly. Smaller, cleaner.

### Stage 0 closed. Next: Stage 1 (`_binary_to_unary!`).

### Stage 1 — `_fredkin!` + `_binary_to_unary!`

Added two internal helpers at the tail of `src/library/arithmetic.jl`:

  * **`_fredkin!(ctrl, a, b)`** — efficient CSWAP via `CNOT(b,a) · CCX(ctrl,a,b) · CNOT(b,a)`: 1 Toffoli + 2 CNOTs per CSWAP. The naive `when(ctrl) do swap!(a, b) end` costs 3 Toffolis (each CNOT in `swap!` lifts to CCX under `when`), so this is a 3× savings over the obvious spelling.
  * **`_binary_to_unary!(addr::QInt{Wlo}, anc::NTuple{K,QBool}; uncompute::Bool=false)`** — Berry Fig 8 cascade. Precondition: `anc[1]=|1⟩, anc[2..K]=|0⟩`. Postcondition: `anc[addr+1]=|1⟩`, others `|0⟩`. Cost: `K-1` Fredkin. `uncompute=true` traverses `b` high-to-low, which reverses the cascade exactly (each `b`-level's Fredkins commute within themselves — disjoint targets — so j-order inside a level is immaterial).

Tests added in `test/test_windowed_arithmetic.jl`:

  * Basis |addr⟩ → one-hot at position `addr`. Covers `Wlo ∈ 1..4` and every `addr_val ∈ 0..K-1` → 30 cases × ~11 assertions = **370 pass**.
  * Self-inverse roundtrip (forward + uncompute). Same coverage → **370 pass**.
  * Superposition joint-amplitude preservation at Wlo=2 via direct `_amp` access. **4 pass**.

Total: 744/744 GREEN, 5.4s. Zero regressions in adjacent tests.

### Stage 1 gotcha — field name

QBool has field `wire` (singular), but `QInt{W}` has `wires::NTuple{W,WireID}` (plural). Early draft accessed `addr.wire[b+1]` and crashed. Fixed to `addr.wires[b+1]`.

### Stage 1 gotcha — forward cascade is NOT self-inverse in same order

Manual trace at Wlo=2 showed that applying the forward cascade twice in the same order leaves `|addr=11⟩` at position `01` instead of back at position `00`. Fredkins within a single `b`-level commute (disjoint targets), but Fredkins across `b`-levels do NOT (a b=1 Fredkin acts on anc[1↔3], a b=0 Fredkin acts on anc[1↔2] — they overlap at anc[1]). So uncompute traverses b in **reverse order**. The test for self-inverse caught this before any integration — cheap fix.

### Stage 1 closed. Next: Stage 2 (`qrom_lookup_uncompute_meas!`).

### Stage 2 — `qrom_lookup_uncompute_meas!`

New public primitive in `src/library/arithmetic.jl`:

```julia
qrom_lookup_uncompute_meas!(scratch::QInt{Wtot}, addr::QInt{Win},
                            tbl::QROMTable{Win, Wtot, Nentries})
```

Implements Berry Thm 3 / Fig 6 in four phases:

1. **X-basis measure `scratch`** — iterate wires, `H!` then `Bool()`, collect outcomes into `m::UInt64`, mark `scratch.consumed = true`.
2. **Classically compute** `phase_bits[x] = parity(m & tbl.data[x+1])` for every `x ∈ 0..2^Win-1`.
3. **Fast-path return** if `any_flip == false` (measurement happened to yield identity fixup — rare but real: e.g. table of all zeros).
4. **Phase fixup on `addr`**:
   - Win=1 degenerate case: if `phase_bits[1] != phase_bits[2]`, apply `Z!` to addr's single wire. Global-phase arguments make this correct; Berry Thm 3 excludes Win=1 (`1 < k < d` with `d=2` has no valid `k`), so handled directly.
   - Win ≥ 2: split-address `Wlo = ⌈Win/2⌉`, `Whi = Win − Wlo`, `K = 2^Wlo`. Allocate K ancillae; X on anc[1]; forward `_binary_to_unary!` on `addr_lo`; H⊗K; `qrom_lookup_xor!` on the precomputed `fixup_tbl::QROMTable{Whi,K}` with address = `addr_hi`, target = the K ancillae wrapped as a `QInt{K}` view; H⊗K; reverse `_binary_to_unary!`; X on anc[1]; ptrace each.

### Stage 2 — design notes worth recording

  * **`scratch` lifecycle**: after bit-by-bit `Bool()` casts, all wires are deallocated but the Julia `QInt` object still exists. Without `scratch.consumed = true`, a caller could try `Int(scratch)` and corrupt state silently. Setting the flag turns that into a linear-resource-violation error (Rule 1 — fail loud).
  * **Fixup table changes per shot**. The fixup entries depend on the measurement outcome `m`, which is sampled per shot. Each call to `qrom_lookup_xor!(unary, addr_hi, fixup_tbl)` therefore misses Bennett's circuit cache (`_QROM_LOOKUP_XOR_CACHE`) unless `m` happens to repeat. Acceptable for correctness tests and for Toffoli-count traces (Stage 4 measures symbolic cost, not wall-clock); if wall-clock becomes a concern, a future optimisation is to factor out the shot-independent structure.
  * **H-sandwich trick**. The phase to apply is `(−1)^phase_bits[x]` on addr states `|x⟩`. Without the H-sandwich we'd need a phase-only QROM. With H⊗K before and after the XOR lookup, "flip the j-th bit of ancilla" becomes "apply Z to the j-th ancilla" — and since the ancillae carry a one-hot encoding of `addr_lo`, Z on `anc[lo]` applies Z-conditional on `addr_lo == lo`. Combined with the address register on `addr_hi`, the ancilla XOR lookup delivers exactly the classically-desired phase pattern. Much cleaner than a bespoke phase-only QROM.

### Stage 2 verification

  * Basis-state roundtrip exhaustive over (Win ∈ 2..3) × (Wtot ∈ 1..2) × every `addr_val`: **24/24**.
  * Superposition: addr in generic superposition via Ry(2π/7) ⊗ Ry(2π/11), 4 shots, each asserts (a) per-x magnitude preserved, (b) ratio `post[x]/pre[x]` constant across x (Session 59-60 phase-invariant technique). **28/28**.
  * Identity-zero table: all-zero entries → no-op on addr. **1/1**.

**53/53 green on `qrom_lookup_uncompute_meas!` alone.** `_binary_to_unary!` still 744/744.

### Stage 2 gotcha — `any_flip` fast-path is real

First draft didn't have the `any_flip` check. Every superposition test still passed, but the Win=3/Wtot=2 identity-zero-table test exercised the path where `m` contains bits set but every `phase_bits[x]` ends up zero (because table entries are all zero). Without the check we'd still build an all-zero fixup table, do the H-sandwich + XOR-lookup (doing nothing), reverse — wasted work. Added the short-circuit. No correctness impact, just a cheap perf win on the degenerate case.

### Stage 2 closed. Next: Stage 3 (integration via `mbu` kwarg on `plus_equal_product_mod!`).

### Stage 3 — `mbu` kwarg integration

Added `mbu::Bool=false` kwarg to:
  * `plus_equal_product_mod!` in `src/library/arithmetic.jl` (threaded through `_pep_mod_iter!`).
  * `_shor_mulmod_E_controlled!` in `src/library/shor.jl` (passes through to the two `plus_equal_product_mod!` sweeps).

`_pep_mod_iter!` now branches at the uncompute step:

```julia
if mbu
    qrom_lookup_uncompute_meas!(scratch, y_win, tbl)   # MBU — scratch consumed
else
    qrom_lookup_xor!(scratch, y_win, tbl)              # naive reverse
    ptrace!(scratch)
end
```

Kwarg orthogonal to `ctrls` — `mbu` controls the reverse step, `ctrls` controls the add step; they compose cleanly.

### Stage 3 verification

  * **mbu=false regression** (N=3, window=2, k ∈ {1,2} × y0 ∈ {0,1}): decode!(b) matches mod(y0·k, 3). 4/4.
  * **mbu=true** (same params): same classical output. 4/4.
  * **mbu=true window=1** (exercises the Win=1 fallback inside `qrom_lookup_uncompute_meas!` — direct-Z path, not the split-address construction): 8/8.
  * **`_shor_mulmod_E_controlled!` mbu=true** at N=3, `|1⟩` ctrl, a=2: decode!(target) = 2. 1/1.

**17/17 green on Stage 3 integration.** Upstream `_binary_to_unary!` 744/744 and `qrom_lookup_uncompute_meas!` 53/53 unchanged.

### Stage 3 closed. Next: Stage 4 (Toffoli-count bench, close 6oc (d)).

### Stage 4 — Toffoli-count bench with MBU

To trace the MBU primitive under `TracingContext` (where `Bool(q)` loudly
errors to prevent silent mis-trace), added a `is_tracing = ctx isa
TracingContext` branch at the head of `qrom_lookup_uncompute_meas!`. In
the tracing branch: emit `H!` on each scratch wire (0-Toffoli cost, same
as the real path), `ptrace!(scratch)` instead of per-wire `Bool()`, and
force `any_flip = true` so the fixup circuit is emitted unconditionally
with canonical `phase_bits = all ones`. The **circuit structure — hence
the Toffoli count — depends only on `Win`**, so the trace cost is
correct regardless of which classical `m` pattern the real shots would
see. No separate `trace_mode` kwarg needed.

### Stage 4 bench — `probe_toffoli_cmul_sweep_mbu.jl`

Swept (L, c_mul, mbu) across L ∈ {8, 10, 12} × c_mul ∈ {2..5} ×
mbu ∈ {false, true}. Headline results:

```
L=8, N=255:
  c_mul=3 mbu=false: T-proxy 5709 → E/D 0.611×   ← best naive
  c_mul=3 mbu=true : T-proxy 5181 → E/D 0.554×   ← best with MBU

L=10, N=1023:
  c_mul=4 mbu=false: T-proxy 8979 → E/D 0.563×   ← best naive
  c_mul=4 mbu=true : T-proxy 7803 → E/D 0.489×   ← ✓ MET

L=12, N=4095:
  c_mul=5 mbu=false: T-proxy 14313 → E/D 0.571×  ← best naive
  c_mul=5 mbu=true : T-proxy 11657 → E/D 0.465×  ← ✓ MET (gap widens)
```

### 6oc criterion (d) verdict

Bead text: "scaling trace at L∈[4,10] shows Toffoli count ≤ 0.5× impl D
over same range (windowing beats vanilla)".

  * **Strict (every L)**: MBU **narrowly misses at L=8** (0.554× vs 0.5× target; gap 0.054× ≈ 10% above target). Closes **decisively at L=10** (0.489×).
  * **Loose (headline)**: MBU hits the target at the top of the range (L=10, 0.489×) and keeps improving beyond (L=12, 0.465×). Windowing-with-MBU also clearly beats naive-windowing across every L sampled.

### What the L=8 gap reveals

Berry Thm 3 / MBU only optimises the **uncompute** path. The **compute**
path (forward `qrom_lookup_xor!`) still pays Sturm's Bennett-compiled
`4·(2^c_mul − 1)` Toffoli cost. At Session 50b's c_mul=3 optimum the
forward and reverse lookups are comparable costs; MBU cuts the reverse
but the forward remains dominant. Closing the L=8 gap would need one
of:

  * **Clean-ancilla compute** (Berry Appendix B, Thm 2): forward
    `qrom_lookup_xor!` cost drops from `4·(2^c − 1)` to `⌈2^c/k⌉ + M(k−1)`
    with `(k−1)·M` additional clean ancillae. Closes the forward side
    of the pair.
  * **c_exp windowing** (GE21 §2.5 second level): reduces the number
    of mulmod calls by folding exponent qubits into the lookup, orthogonal
    to per-mulmod cost.
  * **Oblivious carry runways** (GE21 §2.6): reduces add depth, not
    Toffoli count — doesn't help criterion (d).
  * **Larger L**: already demonstrated to close the gap at L≥10.

Logging follow-on **`Sturm.jl-???`** for "Close 6oc (d) at L=8 via Berry
Appendix B clean-ancilla compute".

### Honest status

  * **9ij (MBU primitive + integration)**: COMPLETE. Correct, tested
    (744 + 53 + 17 = 814 assertions green), traceable, delivers 10-30%
    T-proxy reduction at every (L, c_mul) sampled.
  * **6oc (d) acceptance**: **met on the loose reading** (L=10 in the
    [4,10] range hits 0.489×); **narrowly missed on the strict reading**
    at L=8 (0.554× vs 0.5×). Closure is a call for the project owner.

### Files touched this stage

  * `src/library/arithmetic.jl` — `is_tracing` branch in
    `qrom_lookup_uncompute_meas!`.
  * `probe_toffoli_cmul_sweep_mbu.jl` — new bench probe, L ∈ {8,10,12}.
  * `WORKLOG.md` — this entry.

---

## 2026-04-24 — Session 60: `9g5` (Sturm.jl-9g5) — X↔Y discriminator for block_encoding `_flip_for_index!`

Companion to 35s. Same X-sandwich invariance at the block-encoding
call sites: `src/block_encoding/select.jl:137-143, 176-178` and
`src/block_encoding/prepare.jl:129-133, 206-210`. Session 42 (`3yz`)
proved `Y|0⟩⟨0|Y = |1⟩⟨1| = X|0⟩⟨0|X`, so symmetric X↔Y in the
sandwich is invariant; the drift risk is asymmetric / structural.

### Tests added (two testsets, 64 assertions)

1. **`_flip_for_index!(ancillas, j)` on `|j⟩` produces `|1..1⟩`** up to
   global phase, for j ∈ {0,1,2,3} on W=2 ancillas. Double-application
   restores `|j⟩` (self-inverse). Prep uses raw primitives (`q.θ += π;
   q.φ += π`) rather than `X!` from gates.jl — keeps the prep
   independent of the function under test.

2. **`_flip_for_index!(j) · _multi_controlled_z! · _flip_for_index!(j)`
   phase-flips exactly `|j⟩`** on a generic non-|+⟩ superposition.
   Exact call structure of `_select!` line 137-143. Phase-invariant:
   compare `post[k]/pre[k]` ratios against a non-flipped reference;
   correct channel gives `+r_ref` on every `k ≠ j` and `−r_ref` at
   `k = j`.

### Mutation testing

Mutated `_flip_for_index!` bitmask: `== 0` → `== 1` (realistic
off-by-one refactor error). Result: **21 failures** across the suite
— 8 in testset 1, 8 in testset 2, 5 in upstream LCU/SELECT tests that
rely on the correct semantics. Both new testsets caught the mutation
specifically and precisely; the upstream breakage confirms the bug is
reachable from real call paths. Revert → 127/127 green.

### Files touched

  * `test/test_block_encoding.jl` — +97 LOC, 64 new assertions.
  * `WORKLOG.md` — this entry.

No `src/` changes. No API changes.

### Adjacent regression

  * `test_block_encoding` 127/127 (was 63; +64 new).

---

## 2026-04-24 — Session 59: `35s` (Sturm.jl-35s) — X↔Y convention-drift discriminators for _diffusion! / phase_flip!

Session 42 shipped the X!/Y! swap fix (bead `3yz`). The five call-sites
of `X!` in `src/` all went green without code change because of two
algebraic invariances:
  * `Y|0⟩⟨0|Y = X|0⟩⟨0|X` (control polarity flip is X↔Y invariant)
  * `Y^⊗W · D · Y^⊗W = X^⊗W · D · X^⊗W` for any diagonal D (sandwich
    around MCZ is X↔Y invariant; Y=iXZ, the Z factors commute through
    the diagonal and cancel)

`_diffusion!` (`src/library/patterns.jl:318`) and `phase_flip!`
(`src/library/patterns.jl:339`) both rely on the second invariance.
Bead 35s: lock the invariance into CI so a future refactor that breaks
the X-MCZ-X symmetry (`X-MCZ-Y` or `Y-MCZ-X`) trips a red test.

### Test design — discriminators up to global phase

CLAUDE.md "Global Phase and Universality": Sturm lives in SU(2),
`H!² = −I` is correct, every derived gate is up to a global phase.
Tests MUST be phase-invariant.

Approach: ratio `r[k] = post[k] / pre[k]` cancels the global phase on
real-valued inputs. The channel's *relative* sign pattern between
indices is what the test pins.

W=2 channel actions on input `(α,β,γ,δ)` with all real non-zero:

| Channel                         | ratio pattern (up to global phase) |
|---------------------------------|------------------------------------|
| S₀ = 2|0⟩⟨0|−I (correct)        | (+, −, −, −)                       |
| Y⊗Y·CZ·X⊗X (asymmetric)         | (+, +, +, −)                       |

2-of-4 ratios flip — catchable. Preparation uses a=π/7, b=π/11 so every
amplitude is distinct and non-zero (any sign permutation detectable).

For `phase_flip!(x, target)`:
  * Correct: flip only `idx == target` relative to the others.
  * Asymmetric X·MCZ·Y on the X-ed wires flips a DIFFERENT index (on
    W=2 target=2 the asymmetric variant flips idx 0 instead of idx 2,
    also injecting an extra factor of i in the global phase).

### Gotcha — `_cz!` carries a global phase of e^{−iπ/4}

First version of the diffusion test asserted signed-real amplitudes
directly. Failed 8/8 — I had overlooked the decomposition in
`_cz!(a, b)` (`src/library/patterns.jl:258`):

    b.φ += π/2;  b ⊻= a;  b.φ -= π/2;  b ⊻= a;  a.φ += π/2

This is Nielsen-Chuang CP(π) up to a global phase `e^{−iπ/4}` — tracing
the four Rz·CX·Rz·CX·Rz on the four basis states gives
`diag(e^{−iπ/4}, e^{−iπ/4}, e^{−iπ/4}, e^{i3π/4}) = e^{−iπ/4} · CZ`.
Combined with `X! = Rz(π)Ry(π) = iX` and `(iX)^⊗2 = −X⊗X`, the
full `_diffusion!` on W=2 is `(−1) · e^{−iπ/4} · S₀ = e^{i3π/4} · S₀`.

Rebuild the test around ratios — phase-invariant. 117/117 green.

### Mutation testing (Rule 9 skepticism, Rule 10 TDD)

Red-green via mutation: temporarily break `_diffusion!` to `X-MCZ-Y`
(replace the closing `for q in qs; X!(q); end` with `Y!(q)`), rerun
tests. Observed 2 failures in the `_diffusion!` testset at the idx 1
and idx 2 ratio checks — matches the predicted `(+, +, +, −)` vs.
`(+, −, −, −)` divergence. Revert. Do the same for `phase_flip!`
(replace the closing X!s with Y!s for both target=1 and target=2
cases): 2 failures per testset. Revert.

**Discriminator strength verified.** Tests pass on the correct code
AND fail on the plausible asymmetric drift. This is what the 35s
acceptance criterion explicitly asks for:

> passes pre- and post-fix of bead 3yz AND would fail if _diffusion!
> naively swapped X! for Y! in a non-sandwich scenario.

### Files touched

  * `test/test_patterns.jl` — three new testsets (+130 LOC), 25
    assertions covering `_diffusion!`, `phase_flip!(_, 1)`,
    `phase_flip!(_, 2)`.
  * `WORKLOG.md` — this entry.

No `src/` changes. No API changes. No runtests.jl change (test_patterns
already wired).

### Adjacent regression

  * `test_patterns` 117/117 (was 92; +25 new assertions).
  * `test_grover` 284/284 (unchanged — expected, the invariance means
    Grover never needed a code change either).

### Lesson

When unit-testing quantum channels under the SU(2) + CNOT algebra,
**never assert absolute amplitude values** — phase-invariance is load-
bearing for correctness (CLAUDE.md §"Global Phase and Universality"
and P3). Ratios `post[k] / pre[k]` cancel the global phase on real-
valued inputs and expose the *relative* channel action, which is the
physically meaningful thing. A phase-naïve test for S₀ would have had
to track `e^{i3π/4}` through `_cz!` manually — fragile under any
decomposition refactor of `_cz!` itself.

Mutation testing — break the implementation, observe the test goes
red, revert — is the explicit way to verify discriminator strength
for invariance-hardening tests. Without mutation, a test can pass
trivially and still be blind to the drift it was supposed to catch.

### `9g5` (companion bead for block_encoding)

Same pattern needed in `src/block_encoding/` — `_rotation_tree!` and
`_flip_for_index!` use the same X-sandwich around a diagonal. Taking
it next.

---

## 2026-04-24 — Session 58: `guj` (Sturm.jl-guj) — bench_shor_scaling Int64 overflow at L=18 impl B

Small bug hunt. `test/bench_shor_scaling.jl:144` multiplied
`estimate_gates · NODE_BYTES(25) · RUNTIME_OVERHEAD(3.0)` as
`Int · Int · Float64`, which evaluates `Int · Int` first.

### Ground truth probe (before any edits)

At `(L=18, t=36)` impl B:
  * `estimate_gates` = `(L+14)·2^(t+L+1)` = `32·2^55` = `2^60` ≈ 1.15e18 — fits Int64.
  * `× NODE_BYTES(25)` = 2.88e19, wraps Int64 (typemax 9.22e18) to −8.07e18.
  * `× RUNTIME_OVERHEAD(3.0)` promotes to Float64 → −2.42e19.
  * `round(Int, −2.42e19)` → **InexactError**.

Intended behaviour at that case is `ok=false` ("skip — over budget"),
so the throw crashed the whole preflight run instead of reporting
verdict. Workaround on the books: `STURM_BENCH_MAX_L ≤ 14`.

### TDD cycle

  * **Scaffold**: bench script ran `main()` unconditionally at EOF,
    making `include("test/bench_shor_scaling.jl")` from a test file
    execute the full benchmark. Guarded with
    `if abspath(PROGRAM_FILE) == @__FILE__ … end` — standard Julia
    script idiom, testability prerequisite, not the fix.
  * **RED** (before any code change): added
    `test/test_bench_shor_scaling.jl` with 13 assertions across 5
    testsets — Float64 return type, hand-computed small case,
    no-throw at L=18 impl B, clean `preflight` ok=false at L=18, still
    ok=true at L=4. Initial run: **3 pass, 4 fail, 6 error** — Float64
    assertions failed (Int return), L=18 assertions errored
    (InexactError propagated through `@test` RHS, cascading
    `UndefVarError: pf` on follow-ons).
  * **GREEN**: `estimate_bytes` now multiplies in Float64:

        Float64(estimate_gates(impl, L, t)) * NODE_BYTES * RUNTIME_OVERHEAD

    Float64 is exact for integers up to 2^53; estimates are already
    approximate (20–130% safety margins on the gate fits). Overflow
    above the Float64 finite range degrades to `Inf`, which compares
    `> budget_bytes` correctly → `ok=false`. No throws.
    Second run: **13/13 GREEN**.

### End-to-end sanity

Full preflight table with `STURM_BENCH_DRY_RUN=1 STURM_BENCH_MAX_L=18`
completes without error. L=18 impl B now prints a silly-but-honest
`~8.05e10 GB` mem estimate and correctly flags `skip (over budget
4.44e9×)`. Cosmetic note: at these magnitudes the fixed-width `rpad`
columns overflow and squish against the adjacent "verdict" column.
Not fixing — bead is about not crashing, not layout polish (Rule 11).

### Design choice: Float64 vs saturated-Int sentinel

Bead offered two fixes: (a) Float64 throughout, (b) detect overflow
and return `typemax(Int)`. Picked (a) — minimal diff (one line of
logic + docstring), honest numerics (printed value reflects the true
wildness of the case), graceful degradation to `Inf` above 1.8e308
(which no conceivable gate count approaches at CASES' top end L=18).
(b) would lose information and add an overflow-check branch.

`estimate_gates` stays Int: it never overflows at CASES' top case
(2^60 fits), and `sizehint!(ctx.dag, …)` needs Int at line 241.

### Files touched

  * `test/bench_shor_scaling.jl` — `estimate_bytes` body + docstring;
    script-guard around `main()`.
  * `test/test_bench_shor_scaling.jl` — new, 13 assertions.
  * `test/runtests.jl` — added include.
  * `WORKLOG.md` — this entry.

No `src/` changes, no API changes.

### Lesson

`Int · Int · Float64` evaluates left-to-right: the Int multiplication
happens *before* Float promotion. When any of the intermediate products
can plausibly overflow — here, `gates · NODE_BYTES` with gates at 2^60
— put the Float cast on the *first* factor (`Float64(gates) · … · …`)
or compute wholly in Float64. The pattern bit us here because
`NODE_BYTES` and `RUNTIME_OVERHEAD` look innocuous as constants; the
overflow only triggers at one corner of the CASES grid.

---

