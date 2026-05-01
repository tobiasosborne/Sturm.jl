## 2026-04-20 — Session 34: Release `Sturm.jl-6xi` (coset representation) — ground-truth research punted

After closing `p1z` (session 33 — `add_qft_quantum!`), tried to pick up `6xi`
(coset representation of modular integers). Claimed the bead, read Zalka
1998 §3 + GE21 §2.4 + Gidney 2019 (windowed arithmetic). Discovered that
none of these give an **explicit coset-encoding preparation circuit**:

- **GE21 §2.4** defines the target state (`√(2^-c_pad) · Σ_{j=0..2^c_pad-1}
  |jN+k⟩`) but not the preparation procedure. Says "following Zalka [91]".
- **Zalka 1998** (the fast-versions paper we have locally) §3 discusses
  approximate-modular arithmetic (Eq. 15: "wrong for some small fraction
  of inputs is OK") but the specific coset construction GE21 references
  is in a later Gidney paper.
- **Gidney 2019 "Windowed quantum arithmetic"** (1905.07682, local)
  references coset but leaves the preparation circuit to Gidney's
  follow-up paper "Approximate encoded permutations" (1905.08488). We
  did NOT have that paper locally.

Naive attempts fail: Hadamard the `c_pad` high-order pad qubits gives a
period-`2^W` superposition `Σ_p |k + p·2^W⟩`, not period-`N`. Converting
period-`2^W` → period-`N` is the non-trivial step that `1905.08488` handles.

**Honest assessment:** the coset encoding is a multi-session research
bead. Ground truth fetched this session (see below); next agent can begin
from a complete reference set.

### Actions taken

1. **Fetched three primary-source PDFs** to `docs/physics/` (all from arXiv):
   - `gidney_2019_approximate_encoded_permutations.pdf` (arXiv:1905.08488)
     — THE missing coset-encoding circuit reference. Defines approximate
     encoded permutations, including the coset representation as a
     special case. Cited by GE21 as the preparation-circuit source.
   - `ekera_2017_short_dlp.pdf` (arXiv:1702.00249) — Ekerå's short-DLP
     derivative of Shor. Background for `Sturm.jl-6bn`.
   - `ekera_hastad_2017_n_plus_half_n.pdf` (arXiv:1707.08494) — the
     canonical Ekerå-Håstad "n + ½n" paper. Primary reference for `6bn`.
2. **Released the `Sturm.jl-6xi` claim** — scope mismatch with one session.
3. **Did NOT touch any code.** All changes this session are documentation
   (WORKLOG entries, this file) and the three new PDFs.

### Next-agent research round for the GE21 coset + windowed stack

**Phase A — Ground-truth reading (no code).** Expected 1 session. Produce
a design doc `docs/coset_encoding.md` with:

1. **Read `gidney_2019_approximate_encoded_permutations.pdf` end to end.**
   Extract the explicit preparation circuit for a coset-encoded register
   — specifically the circuit that takes `|k⟩ ⊗ |0⟩^c_pad` and produces
   the periodic superposition `Σ_j |jN + k⟩`. This paper's Section on
   "approximate cosets" is the key citation.
2. **Read GE21 §2.4–2.7 with attention to the interaction clauses.**
   GE21 §2.7 explicitly notes "interactions between optimisations" — the
   coset-padding length `c_pad` and the oblivious-carry-runway length are
   the SAME parameter; windowing changes the optimal `c_pad`. Record
   these cross-constraints before implementing anything in isolation.
3. **Re-read `gidney_2019_windowed_arithmetic.pdf` §3.1** with coset in
   mind. The `plus_equal_product` construction (Fig 1 there) is
   non-modular `+=` into a target register — the modular behaviour is
   IMPLIED by coset encoding of the target, not added explicitly.
4. **Derive the approximation-error formula.** Gidney 1905.08488 gives
   `ε = O(2^-c_pad)` in some norm. State it with the constant, cite the
   lemma number.
5. **Map Zalka's 1998 §3 "3L qubits are enough" idea to Sturm.** Zalka's
   §3.0.1 uses semi-classical QFT — Sturm already has this (`D_semi`).
   Document how the coset compression interacts with `D_semi`.
6. **Produce a concrete preparation circuit in Sturm idiom** — i.e.,
   expressed in primitives 1–4 only, no raw matrices. Include a textual
   "circuit sketch" before any Julia.

**Phase B — Implementation (subsequent session).** Red-green TDD for:

- `coset_encode!(q::QInt{W+Cpad}, N::Int, ::Val{Cpad})`
- `coset_decode!(q)` — measurement-based classical post-processing
- Property tests: `ε = Pr[decode != correct_mod_N]` scales as `2^-c_pad`
- Integration: `coset_encode!` + `add_qft!` + `coset_decode!` approximates
  modular addition to within `ε`

**Phase C — Windowed arithmetic follow-up** (still separate, `Sturm.jl-6oc`):
Once coset is landed, windowed modular add becomes `oracle_table → fresh
register → add_qft_quantum! (already shipped in session 33)`. The
modular reduction is automatic via the coset encoding — **that's the
interaction the naive "6oc first" order missed**.

**Critical reminder for next agent:** do NOT spawn proposer subagents
(CLAUDE.md rule 2 three-plus-one) for these beads unless the
implementation touches a core surface (`types/`, `context/abstract.jl`,
`primitives/`, `src/orkan/`). Coset + windowed are library-level work;
single-agent TDD is correct.

**Device reminder:** 16-qubit simulation cap. Coset tests at L=3, c_pad=3
= 6 qubits is fine. L=6, c_pad=6 = 12 qubits fine. Avoid large `c_pad`
statevector probes — 2^(L+c_pad) grows fast.

### Files touched

- `docs/physics/gidney_2019_approximate_encoded_permutations.pdf` (new)
- `docs/physics/ekera_2017_short_dlp.pdf` (new)
- `docs/physics/ekera_hastad_2017_n_plus_half_n.pdf` (new)
- `WORKLOG.md` — this entry.

### Beads

- `Sturm.jl-6xi` claim released (status back to open). Notes updated
  with the three new PDF paths and the Phase A/B/C research plan above.
- `Sturm.jl-6oc` NOT claimed this session. Its full speedup depends on
  6xi landing first (windowing alone without coset is much-reduced gain);
  notes updated to record the cross-dependency.
- `Sturm.jl-b3l` (oblivious runways) also benefits from
  `gidney_2019_approximate_encoded_permutations.pdf` landing in physics/.
  Updated.

---

## 2026-04-20 — Session 35: Close `Sturm.jl-q84` (QCoset / QRunway / QROMTable type definitions + init circuits)

Implementer pass for the three-plus-one round on bead q84. Two proposers
(A, B) produced independent designs; the orchestrator synthesised them into
a single spec. This session ships the agreed design.

### What was implemented

**4 new files:**

1. `src/types/qcoset.jl` — `QCoset{W, Cpad, Wtot}` mutable struct, linearity
   machinery, wire access, constructors. Three type params (Wtot = W+Cpad)
   following the same pattern used to avoid `W+Cpad` in struct field annotations.

2. `src/types/qrunway.jl` — `QRunway{W, Cpad, Wtot}`. `discard!` unconditionally
   errors (CLAUDE.md fail-loud rule; runway must be classically uncomputed first).
   `_runway_force_discard!` is the safe cleanup path after `runway_fold!`.

3. `src/types/qrom_table.jl` — `QROMTable{Ccmul, W, Nentries}` (NTuple, max
   Ccmul≤20) and `QROMTableLarge{Ccmul, W}` (Vector, no size limit). NOT subtypes
   of `Quantum`. `_canonicalize_table_entries` handles mod-N reduction.
   **Gotcha** (see below): infinite dispatch recursion on `QROMTableLarge`.

4. `src/library/coset.jl` — `_coset_init!` (QFT-sandwich approach), `_runway_init!`
   (trivial `|+⟩` init). Both are internal `_`-prefix, not exported.

**Modified files:**
- `src/Sturm.jl` — added includes for the 4 new files, added exports
  `QCoset, QRunway, QROMTable, QROMTableLarge`.
- `test/test_q84_types.jl` — 60 smoke tests, all passing.

### Key decisions and gotchas

**`_coset_init!` approach — QFT sandwich, not Gidney Fig. 1 literally:**
Gidney 1905.08488 Figure 1 uses comparison-negation operations
(`(-1)^{x≥N}`) which require a reversible comparator (Cuccaro-style).
That circuit is out of scope for this bead. The QFT-sandwich variant
achieves the SAME coset superposition `|Coset_m(r)⟩ = (1/√2^m) Σ_j |r+jN⟩`
via controlled QFT-basis additions of `2^p·N` for each padding bit p,
which directly implements Definition 3.1 encoder `f(g,c) = g + c·N`.

**Orkan ctrl==target rejection:**
When `when(pad)` wraps `add_qft!(reg, addend)`, the rotation loop inside
`add_qft!` applies `Rz(θ)` to EVERY wire in the register including `pad`'s
own wire (k = W+p+1). This creates `ctrl=pad, target=pad` — Orkan rejects
it (`"qubits must be distinct"`). Fix: manually unroll the `add_qft!` loop,
applying `when(pad) { Rz(θ) }` to all wires except `pad`'s own wire, and
applying `Rz(θ)` unconditionally to `pad`'s wire (because controlled-self-
rotation is equivalent to the unconditional rotation).

**`QROMTableLarge` infinite dispatch loop:**
The outer convenience constructor `QROMTableLarge{C,W}(entries::AbstractVector{<:Integer}, ...)`
calls `_canonicalize_table_entries` which returns `Vector{UInt64}`. Then
it calls `QROMTableLarge{C,W}(processed, modulus)` — but `Vector{UInt64}
<: AbstractVector{<:Integer}`, so this re-dispatches to the OUTER constructor
again, causing infinite recursion and a stack overflow. Fix: define an
**inner constructor** in the struct body (`new{Ccmul,W}(data, modulus)`) 
that is more specific (`Vector{UInt64}`) and is matched preferentially by Julia's
dispatch to break the cycle.

**`QROMTable{Ccmul,W}` needs third type param `Nentries`:**
`NTuple{1 << Ccmul, UInt64}` is not valid in a struct field annotation —
Julia evaluates `<<` at type-definition time with `Ccmul` as a TypeVar,
producing `MethodError: <<(::Int64, ::TypeVar)`. Fix: add third type param
`Nentries` (must equal `1 << Ccmul`, enforced by constructor), same
Wtot-pattern as QCoset/QRunway.

**`_runway_force_discard!` import in tests:**
Internal `_`-prefix functions are not exported. Tests import explicitly via
`import Sturm: _runway_force_discard!`.

### Smoke tests

All 60 tests pass. Covers: construction, validation errors, wire access,
discard/force-discard, QROMTable canonical reduction, type parameter assertions,
double-discard protection.

### Beads

- `Sturm.jl-q84` — close (this session ships the type definitions).
- `Sturm.jl-6xi` (`coset_add!`), `Sturm.jl-b3l` (`runway_fold!`),
  `Sturm.jl-6oc` (`qrom_lookup!`) — downstream, still open.

---

## 2026-04-20 — Session 33: Close `Sturm.jl-p1z` (add_qft_quantum! — two-quantum-register Draper adder)

P1 prerequisite for `Sturm.jl-6oc` (windowed arithmetic / `shor_order_E`). Sturm's
`add_qft!` (arithmetic.jl:61) only handles the CLASSICAL-constant addend —
Draper 2000's degenerate case where the n²/2 controlled rotations collapse
to n unconditional Rz. Windowed arithmetic, coset representation, and any
QROM-addend construction need the full Draper §5 "Transform Addition" with
both registers quantum.

### Sturm.jl's Shor circuit stack relative to GE 2021 (session-32 assessment)

GE21 (arXiv:1905.09749) combines 5 optimisations:
1. Ekerå-Håstad 2017 short-DLP derivative (n_e = 1.5n)
2. Coset representation (Zalka 1998) — 2.5× fewer Toffolis per add
3. **Windowed arithmetic (Gidney 2019 arXiv:1905.07682)** — polylog reduction
4. Oblivious carry runways
5. Semi-classical QFT — ✓ `D_semi` in Sturm

At the end of session 32 Sturm had 1 of the 5. Tier-1 roadmap now filed
as 4 beads: `Sturm.jl-6oc`, `-6xi`, `-b3l`, `-6bn`. Session 33 lands the
foundational primitive (quantum-addend Draper adder) that unblocks 6oc.

### Ground truth

- Draper 2000 quant-ph/0008033 §5 "Quantum Addition", Fig. "Transform
  Addition" p.6. Local PDF: `docs/physics/draper_2000_qft_adder.pdf`.
- Full construction: for target wire `|φ_{jj}(y)⟩`, apply `R_d` with
  `d = jj − j + 1` controlled on `b.wires[j]`, for each `j = 1..jj`.
  `R_d` is conditional phase `diag(1, e^(2πi/2^d))`.

### Implementation — `src/library/arithmetic.jl:92-142`

```julia
function _add_qft_quantum_signed!(y::QInt{L}, b::QInt{L}, sign::Int)
    for k in 1:L
        jj = L - k + 1                       # Sturm wires[k] ↔ Draper φ_{jj}
        qk = QBool(y.wires[k], ctx, false)
        for j in 1:jj
            d = jj - j + 1
            θ = sign * 2π / (1 << d)
            bj = QBool(b.wires[j], ctx, false)
            when(bj) do
                qk.φ += θ
            end
        end
    end
end
```

Nested `when` around `.φ +=` — two primitives (when, Rz). Under an outer
`when(ctrl)`, each emission picks up one more control via Sturm's control
stack — still a single primitive-3 call, decomposition handled by the
context's multi-control lowering.

Signed helper (`+1` / `-1`) lets `sub_qft_quantum!` reuse the same code
with negated angles. Pair composes to per-wire `Rz(θ) · Rz(−θ) = I` — no
di9-style global-phase leak even under `when(ctrl)`.

### RED-GREEN

1. **RED** — `test/test_p1z_add_qft_quantum.jl` with seven testsets.
   First run pre-implementation: 3 errors, "`add_qft_quantum!` not defined".
2. **GREEN** on first implementation attempt. **576/576 PASS in 6.3s**:
   - Exhaustive L=3 forward `y += b` over 64 pairs.
   - Inverse: `add_qft_quantum! ∘ sub_qft_quantum!` is identity on 64 pairs.
   - Double-add: `y += 2b mod 2^L` on 64 pairs.
   - Under `when(ctrl=|1⟩)`: addition fires, ctrl preserved (64 pairs).
   - Under `when(ctrl=|0⟩)`: identity, ctrl preserved (64 pairs).
   - Under `when(ctrl=|+⟩)`: forward + inverse leaves ctrl pure — X-basis
     coherence clean (di9 tripwire) on 16 pairs.
   - L=4 spot-check: 32 targeted `(y0, b0)` pairs.

### Gotchas for future agents

1. **Wire-convention mapping from Draper to Sturm.** Draper numbers the
   target QFT output as `φ_1, φ_2, ..., φ_n` with `φ_n` the full-precision
   wire (denominator `2^n`). Sturm's `superpose!` includes a bit-reversal
   SWAP so that `y.wires[1]` holds `|φ_L⟩` and `y.wires[L]` holds `|φ_1⟩`.
   Every reader of `add_qft!` / `add_qft_quantum!` needs to juggle
   `jj = L − k + 1` to translate between the two indexing conventions.
2. **`QBool(wire, ctx, false)` is the safe lightweight handle.** The
   third arg (`is_owned`) defaults matter: `false` means "the caller owns
   the wire, don't touch the allocator on drop". The classical `add_qft!`
   and `modadd!` both use this pattern — see arithmetic.jl:75, 183.
   Constructing a QBool inside a tight loop with `is_owned=true` would
   double-free wires when the loop body exits.
3. **`Rz(θ) · Rz(−θ) = I` is the inverse law relied on by the di9 fix.**
   Any canonicalisation of the angle (`mod` into a half-open interval)
   that maps the boundary representatives asymmetrically would break this
   and leak a `−I` global phase per wire, which becomes a `π` relative
   phase on the outer control under `when`. This is why
   `_add_qft_quantum_signed!` emits raw `2π / 2^d`, identical to
   `add_qft!`'s di9 fix. See arithmetic.jl:72 for the ruler.

### Files touched

- `src/library/arithmetic.jl` — `add_qft_quantum!`, `sub_qft_quantum!`,
  `_add_qft_quantum_signed!` internal helper (+70 lines).
- `src/Sturm.jl` — export the two new functions.
- `test/test_p1z_add_qft_quantum.jl` (new) — 7 testsets, 576 tests.
- `WORKLOG.md` — this entry.

### Beads

- `Sturm.jl-p1z` closed.
- `Sturm.jl-6oc` (windowed arithmetic) unblocked.
- Related open beads, now reachable once 6oc lands: `Sturm.jl-6xi`
  (coset representation), `Sturm.jl-b3l` (oblivious runways),
  `Sturm.jl-6bn` (Ekerå-Håstad).

---

## 2026-04-20 — Session 32: Close `Sturm.jl-c6n` (polynomial-in-L Shor scaling doc)

P1 EPIC. Primary acceptance: "`shor_order_D` correct on N=15,21,35 AND
bench at L=14 shows polynomial (not exponential) gate count." N=15 and
N=21 were verified in sessions 26 and 28 (end-to-end Orkan shots).
N=35 is device-blocked on the current box (HWM ≈ 20–21 qubits >
16-qubit cap). This session closes the polynomial-scaling half.

### Deliverable

New `docs/shor_scaling.md` with:
- Trace-only bench data for impl C and impl D across L ∈ [4, 14]
- log-log fit: `gates(L) ≈ 82.7·L^3.358` (R²=0.997),
  `toff(L) ≈ 5.72·L^2.026` ≈ 6L² (R²=0.999)
- Extrapolation to L=1024 with honest comparison to Gidney-Ekerå 2021's
  `0.3n³ + 0.0005n³ lg n` Toffoli formula
- Caveats: a_j-saturation outliers at L=4 and L=9, counting-convention
  gap between Sturm CCX count and GE "abstract Toffoli"

### Results table (impl D, t=2L)

| L | gates | toff |
|--:|--:|--:|
|  4 |   2,473 |    24 |  ← outlier (N=15 a=7, only 2/8 mulmods fire)
|  5 |  19,551 |   150 |
|  6 |  33,505 |   216 |
|  7 |  56,239 |   294 |
|  8 |  85,089 |   384 |
|  9 |  28,749 |   108 |  ← outlier (N=257 a=2, ord(2 mod 257)=16)
| 10 | 179,281 |   600 |
| 11 | 250,911 |   726 |
| 12 | 334,129 |   864 |
| 13 | 529,933 | 1,092 |
| 14 | 570,753 | 1,176 |

Impl C over the same range: 8k → **47.7M** gates (5,750× growth).
Impl D over the same range: 2.5k → **571k** gates (230× growth). At
L=14 the impl C / impl D gate ratio is 83×; at L=18 the preflight
projects ~200×.

### "Nice-to-have" verdict: NOT met, expected

The bead optionally asked for the L=1024 extrapolation to be "within
an order of magnitude of Gidney-Ekerå 2021". Honest read:
- Sturm CCX count at L=1024 = ~7 × 10⁶, GE Toff = ~3.3 × 10⁸. Looks
  like Sturm is *cheaper* but that's a metric mismatch — Sturm doesn't
  fold Rz into its Toffoli count; GE does.
- Sturm total gates at L=1024 = ~1.06 × 10¹² vs GE Toff 3.3 × 10⁸.
  Sturm is ~3,200× more expensive on this axis. This is consistent
  with GE's own abstract stating they reduce Toffoli count by 10×+
  vs prior art via windowed arithmetic, Zalka coset, oblivious carry
  runways — optimisations NOT present in vanilla Beauregard (impl D).

The primary acceptance — "polynomial not exponential" — is met with
R²=0.997 on the fit.

### Fixes landed this session

1. **`test/bench_shor_scaling.jl` default impl filter now includes :D.**
   Without this, `STURM_BENCH_ONLY` had to be set manually; :D was a
   post-landing addition that was never folded into the default. One
   line, `parse_impl_filter()`.
2. Filed `Sturm.jl-guj` P3 for the Int64 overflow in `estimate_bytes`
   at L ≥ 16 for impl B. Not triggered under `STURM_BENCH_MAX_L ≤ 14`.

### Gotchas for future agents

1. **`a_j = a^{2^{t-i}} mod N` saturates early for bases with small
   multiplicative order.** At N=15 a=7 (ord=4) or N=257 a=2 (ord=16 —
   257 is a Fermat prime!), many mulmod calls become identity and get
   short-circuited by the impl D mulmod dispatch. Observed: L=9 gate
   count (28,749) is *lower* than L=8 gate count (85,089), which is
   the clearest non-monotone dip in the series. Always EXCLUDE
   small-order cases from any scaling fit OR choose non-pathological
   bases (`a` coprime with no unusually-short order mod N).
2. **Sturm CCX count ≠ GE abstract Toffoli count.** Sturm reports CCX
   as 3+-wire-with-`ncontrols ≥ 1` DAG nodes only; multi-controlled
   Rz is counted as RzNode with `ncontrols=2`, NOT as CCX. GE's
   abstract-circuit Toffoli count folds ALL non-Clifford operations
   into a single number. Cross-framework comparison requires either
   (a) synthesising Sturm's Rz to Clifford+T and counting T gates, or
   (b) running GE's formula in total-gate mode. Neither is done here.
3. **`TracingContext.wire_counter` is monotone, not live-HWM.** Bench
   table's "wires" column is the number of allocated WireIDs (every
   `_alloc_wire!` bumps it, `_free_wire!` does not). Live HWM is
   maintained by `ctx.n_qubits` on Eager/Density contexts only. See
   `src/context/tracing.jl`.
4. **Per-case trace time on this device was 0.5–9s for L ≤ 14.** Much
   faster than expected — DAG construction is mostly pointer appends
   into a pre-sized `Vector{HotNode}`. The slow cases were impl C at
   L=13 (9.1s, 44M nodes) and L=4 (5.2s, first-run JIT warm-up).

### Files touched

- `docs/shor_scaling.md` (new, ~200 lines) — the deliverable.
- `test/bench_shor_scaling.jl` — default impl filter includes :D.
- `WORKLOG.md` — this entry.

### Beads

- `Sturm.jl-c6n` closed with a note that N=35 end-to-end verification
  remains device-blocked (16-qubit cap vs 20+ needed) — separate bead
  if anyone later wants to track it.
- `Sturm.jl-guj` filed for the Int64 overflow in the preflight cost
  model at L ≥ 16 for impl B. P3, not blocking.

---

## 2026-04-20 — Session 31: Close `Sturm.jl-5gz` (qsvt_phases sin parity, documentation bug)

P2 bug: `test/test_qsvt_reflect.jl:57` asserted `length(phi) == 2d` for sin
polynomials at `d ∈ {5, 9, 13}`, but `qsvt_phases` returns `2d+1`. The bead
author's hypothesis ("may be a test-assertion issue rather than a physics
issue") is correct. Confirmed via WORKLOG-archive.md:1561-1596 — the
`2d+1`-for-odd-parity behaviour is a deliberate fix from an earlier session:
GSLW Theorem 17 requires `n` and polynomial parity to match, or the SVT
collapses Hermitian eigenvalue signs (`P(|λ|)` instead of `P(λ)`). The fix
detects odd Chebyshev parity (even-indexed coefficients ≈ 0) and keeps
`φ₀`, yielding `2d+1` phases; cos stays at `2d`.

### Smoke confirmation (no fix needed in code)

    cos d=4  → 8  ✓   sin d=5  → 11 ✓
    cos d=8  → 16 ✓   sin d=9  → 19 ✓
    cos d=12 → 24 ✓   sin d=13 → 27 ✓

### Files touched

- `test/test_qsvt_reflect.jl` — sin testset expects `2d+1`; both cos and
  sin testsets now document the GSLW Thm 17 parity rule inline.
- `src/qsvt/circuit.jl` — `qsvt_phases` docstring's "Returns" section now
  states the two-arm length rule and cites Theorem 17. Pipeline step 6
  description changed from "drop φ₀" to "parity-matched trim".
- `src/qsvt/phase_factors.jl` — header comment gains a short parity-
  convention block with cross-ref to `qsvt_phases`. This is where the
  5gz bead author expected to find the convention documented.

### Gotchas for future agents

1. **`qsvt_phases` lives in `src/qsvt/circuit.jl`, not `phase_factors.jl`.**
   The 5gz bead body pointed at `phase_factors.jl` because that's where
   the phase-factor algorithm lives — but the user-facing trim rule (drop
   vs keep `φ₀`) is applied in `circuit.jl`. The new header comment in
   `phase_factors.jl` cross-references to avoid the next search-miss.
2. **Parity-matched `n` is load-bearing for ALL Hermitian QSVT.** Dropping
   `φ₀` unconditionally would pass the length test for cos and break sin
   silently (downstream `qsvt_reflect!` sin circuit would compute `|sin|`
   rather than `-sin`). Regression tripwire: the length asserts in
   `test_qsvt_reflect.jl`'s A-block AND the downstream `qsvt_reflect!:
   sin(Ht/α)` testset at line 230, which catches the sign-collapse case.
3. **"Test assertion wrong, algorithm right" bugs are easy to miss under
   a green suite.** The bead was only visible because the length-asserts
   happened to be the test — downstream functional tests passed (they
   consumed the actual 2d+1 phases and ran correct circuits). Lesson:
   when a length / count assertion fails but nothing else does, the
   assertion is the likely culprit.

### Beads

- `Sturm.jl-5gz` closed.

---

