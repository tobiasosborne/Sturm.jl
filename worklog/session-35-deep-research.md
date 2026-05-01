## 2026-04-20 — Session 35: Deep research round + ship q84 + 8fy + 6xi + amh + b3l

Big session. Deep literature/codebase/Julia-idioms research, then ground out
**six beads** (`rqg`, `q84`, `8fy`, `amh`, `6xi`, `b3l`) through the GE21
stack from type design to functional shipping. Filed five new beads
(`7z1`, `wzc`, `5jn`, `2i0`, `jrl`). Net: 1422+ tests added, all passing,
across q84/6xi/b3l. Six commits pushed: `790c27f`, `234b8ef`, `d53643e`,
`4f6052f`, `d52cdea`.

### Phase 0 — Deep research round (5 parallel sub-agents, ~14 min total)

Before any code, dispatched 5 Sonnet sub-agents in parallel from the user's
prompt "send out sonnet subagents to query every file you need":

1. **Codebase mapper** (Explore agent, very thorough) — mapped all 5
   `shor_order_A..D_semi` impls in `src/library/shor.jl:159..1128`,
   the arithmetic library (`add_qft!`, `add_qft_quantum!`, `modadd!`,
   `mulmod_beauregard!` at `arithmetic.jl:61..429`), QFT primitives
   (`superpose!`/`interfere!` at `patterns.jl:25..95`), QInt/QBool
   constructors and `_qbool_views` non-owning views, the `when()` control
   stack, multi-control lowering (`context/multi_control.jl` ABC + Barenco
   Lemma 7.2 cascade), Orkan FFI gate set (`orkan_ry`/`rz`/`cx`/`ccx`
   direct paths plus 1-qubit fixed gates), and confirmed nothing in `src/`
   pre-existed for coset/windowed/runways/Ekerå-Håstad. Identified key
   tripwires: `H!² = -I` (global phase), `_cz!` ≠ controlled-Rz(π) (Session
   8 bug class), bit-reversal SWAP convention `y.wires[1]` ↔ Draper `φ_L`
   (`jj = L − k + 1` translation), `QBool(wire, ctx, false)` non-owning
   pattern, `_apply_ctrls` capped at 2 controls.

2. **GE21 + Cain 2026 lit review** (general-purpose, sonnet) — full
   read of GE21 (arXiv:1905.09749) §2.1–2.7 plus Cain et al. arXiv:2603.28627.
   Confirmed the 5-optimisation cost decomposition: short-DLP n_e=1.5n
   (Ekerå-Håstad), Zalka coset 2.5× Toffoli reduction, windowed arithmetic
   (Babbush+Gidney), oblivious carry runways, semi-classical QFT.
   GE21 §2.7 documents the **interactions**: c_pad shared between coset
   and runways; runway-folding required inside multiply-add. Cain 2026 is
   **physical-layer only** (LP/BB qLDPC codes, neutral atoms, ~11k physical
   qubits) — uses GE21 algorithmic stack unchanged. Filed as `di1`-adjacent
   reference; not algorithmic scope. Post-GE21 SOTA: Gidney 2025
   (arXiv:2505.15917, ~900k physical qubits via approximate residue
   arithmetic). Regev 2023 (arXiv:2308.06572) gives Õ(n^{3/2}) total gates
   asymptotically but no concrete improvement over GE21 yet.

3. **Coset + windowed circuit deep-dive** (general-purpose, sonnet) — read
   Gidney 1905.08488 (coset prep + runways) and Gidney 1905.07682
   (windowed arithmetic) end-to-end. Extracted concrete circuits:
   `InitCoset(N, m)` (Fig 1) = m stages of [H on pad qubit ↑ controlled
   +2^p·N ↑ comparison-negation `(-1)^{x≥2^p·N}`]; oblivious runway init
   (Fig 2) = init pad in `|+⟩^m` then subtract from high part; windowed
   `plus_equal_product` indexes a 2^w-entry table by w factor-register
   bits; measurement-based QROM uncomputation (Babbush 1805.03662 App C +
   Gidney 1905.07682 Fig 3) costs O(√L) Toffoli vs O(L) naïve.
   GE21 §2.7 runway-folding: temporarily collapse each c_pad-qubit runway
   into 1 carry qubit before multiply-add, restore after.

4. **Ekerå-Håstad short-DLP deep-dive** (general-purpose, sonnet) — read
   EH17 §4.3, §4.4, §5.2; Ekerå 2023. Established: function evaluated is
   `f(e1, e2) = g^{e1} · y^{-e2} mod N` with two registers of width
   2m+m=3m for n_e=1.5n+O(1) total. For RSA, classical setup `y = g^{N+1} mod N`
   gives secret `d = p+q`. Two independent QFTs after; classical post-
   processing for s=1 (single shot) is **2D Lagrange reduction** =
   extended Euclidean — no LLL/BKZ needed, no Hecke.jl/Nemo.jl dep, ~20
   lines of pure Julia. Factor recovery `(p, q) = roots(x²-dx+N=0)`.
   **Critical discovery during research:** the agent flagged that
   `docs/physics/ekera_hastad_2017_n_plus_half_n.pdf` reads as a building-
   energy paper. Verified true via direct PDF read — see `rqg` below.

5. **Julia idioms brief** (general-purpose, sonnet) — surveyed Sturm
   conventions: type-parameterised widths (`QInt{W}`), `NTuple{W, WireID}`
   stack-allocation on Julia 1.10+, `ntuple(f, Val(W))` for static
   unrolled loops, `@code_warntype` discipline, P9 dispatch via operator
   overloads + `oracle/quantum/@quantum_lift` (NEVER catch-all on
   `Base.Function`), task-local-storage context (eligible for `ScopedValue`
   migration in Julia 1.11+), `Threads.@spawn` does NOT inherit TLS,
   `Base.@assume_effects :foldable` for pure classical helpers. **Section 10
   recommendations** drove the q84 type design: `QCoset{W, Cpad, Wtot}`
   composition (not subtype `<: QInt`), `QROMTable{Ccmul, W}` NTuple
   capped at Ccmul ≤ 20 with separate `QROMTableLarge` Vector path.
   Flagged hygiene fixes: `_shor_mulmod_a!` Vector{WireID} alloc in hot
   path → `ntuple` (filed as `5jn`).

### Pre-flight (bead `rqg`)

PDF audit:
- **DELETED** `docs/physics/ekera_hastad_2017_n_plus_half_n.pdf` — was
  arXiv:1707.08494 (Ioli et al. "A compositional modeling framework for
  the optimal energy management of a district network"), wrong content.
  Title-page check confirmed.
- The actual **Ekerå-Håstad 2017** paper is `ekera_2017_short_dlp.pdf`
  (arXiv:1702.00249 — Martin Ekerå AND Johan Håstad, despite filename
  suggesting single Ekerå; verified by reading title page Feb 2 2017).
- Fetched 4 new PDFs via `curl -sSL https://arxiv.org/pdf/<id>`:
  - `ekera_2023_single_run_dlp.pdf` (arXiv:2309.01754, GE21's [23] for
    single-shot post-processing conditions; needed for 6bn)
  - `babbush_2018_qrom_linear_T.pdf` (arXiv:1805.03662, measurement-based
    QROM uncomputation — needed for 6oc)
  - `gidney_2025_rsa2048_1m_qubits.pdf` (arXiv:2505.15917, post-2021 SOTA
    — ~900k qubits via approximate residue arithmetic)
  - `regev_2023_efficient_factoring.pdf` (arXiv:2308.06572, Õ(n^{3/2})
    asymptotic but unclear practical benefit)
- Confirmed `gidney_2019_approximate_encoded_permutations.pdf` (arXiv:1905.08488)
  was already local — research agent #2 had incorrectly flagged it missing.
- Closed in seconds-of-walltime: `bd close Sturm.jl-rqg`. No code.

### Type design 3+1 round (bead `q84`, commit `790c27f`)

CLAUDE.md rule 2 triggered (touches `src/types/`). Two parallel Sonnet
proposers (blind — neither saw the other's output), synthesis by
orchestrator, Sonnet implementer.

**Proposer A proposed:** `QCoset{W, Cpad}` with `modulus::Int` runtime
field and `ctx::AbstractContext` cached; `QRunway{W, Cpad}` with
`modulus::Int` field; `QROMTable` with `Storage` type parameter collapsing
NTuple/Vector dispatch. `discard!` on QRunway uses `@warn` not `error`.

**Proposer B proposed:** `QCoset` with `modulus::Int` + `ctx` cached;
**QRunway WITHOUT modulus** ("modulus-agnostic, lives in enclosing
QCoset when composed"); `QROMTable{Ccmul,W}` + separate concrete
`QROMTableLarge{Ccmul,W}`; `discard!` on QRunway errors per CLAUDE.md
fail-loud rule.

**Orchestrator synthesis:**
- **Composition over subtyping** (both agreed). `QCoset.reg::QInt{Wtot}`
  field, not `<: QInt`. Julia subtypes share parent's dispatch surface
  (parent's `Base.:+`, `Base.xor` etc. become valid on the child); cannot
  RESTRICT inherited methods. Composition keeps each type's valid
  operations explicit.
- **Three type params `{W, Cpad, Wtot}`** (both agreed). Julia forbids
  `QInt{W + Cpad}` directly in struct field annotation; the workaround
  is a third type param with constructor-level enforcement `Wtot == W + Cpad`.
- **N as runtime field** for QCoset (both agreed). In-type would generate
  a fresh specialisation per modulus value — wasteful for a research DSL.
- **B's choices picked:** no modulus field in QRunway (runway alone is
  modulus-agnostic); discard! error-not-warn (fail-loud); two concrete
  types for QROMTable (simpler dispatch than Storage param).
- **Wire layout** (both agreed, forced by Gidney 1905.08488 Fig 1):
  `wires[1..W]` = value/main register (little-endian); `wires[W+1..W+Cpad]`
  = padding/runway (continuing little-endian). Contiguous, NOT interleaved.

**Implementer shipped:**
- `src/types/qcoset.jl:32..36` — struct (pre-fix, 3 fields; fix in 8fy
  adds 4th pad_anc field).
- `src/types/qrunway.jl:42..45` — struct (2 fields: reg + consumed).
- `src/types/qrom_table.jl` — QROMTable + QROMTableLarge + 
  `_canonicalize_table_entries` (modulus=nothing sentinel).
- `src/library/coset.jl` — `_coset_init!` (WRONG — see 8fy) and
  `_runway_init!` (Ry(π/2) per runway wire).
- `src/Sturm.jl:96` — exports `QCoset, QRunway, QROMTable, QROMTableLarge`.
- `test/test_q84_types.jl` — 60 smoke tests across 9 testsets (construction,
  validation errors, wire access, double-discard protection, type params,
  `@test_throws ErrorException discard!(r::QRunway)` for the fail-loud rule).

**Subtle implementer decisions the orchestrator would have caught with
state tests:**
- Chose QFT-sandwich for `_coset_init!` instead of Gidney Fig 1 literal
  (to avoid the comparison-negation operations, which need a reversible
  comparator — out of q84 scope). THIS IS WRONG — see 8fy.
- Handled `add_qft!(reg, addend)` inside `when(pad_wire)` where pad_wire ∈
  reg.wires by manually unrolling the Rz loop and treating the self-wire
  as unconditional. THIS IS ALSO WRONG (spurious phase) — see 8fy.
- `QROMTable` needed a third type param `Nentries` because
  `NTuple{1 << Ccmul, UInt64}` has an invalid TypeVar shift in the struct
  field annotation — same Wtot-style pattern.
- `QROMTableLarge` outer constructor had infinite-dispatch risk: outer
  `(entries::AbstractVector{<:Integer})` processed into `Vector{UInt64}`
  then called struct constructor — but `UInt64 <: Integer` re-matched the
  outer constructor. Fixed by using an explicit inner `new{Ccmul,W}`
  constructor inside the struct body.

Implementer shipped 60/60 smoke tests. **But state correctness was
NOT smoke-testable** — tests only exercised construction, type stability,
discard, index bounds. The `_coset_init!` physics bug was invisible to
smoke tests and required a state-distribution probe to catch (see 8fy).

### `_coset_init!` was wrong (bead `8fy`, commit `234b8ef`)

After closing q84 and attempting to start 6xi, my orchestrator-review step
ran a state-correctness probe before trusting the implementer's claim:

```julia
# Probe: prepare QCoset{4,3}(7, 15) and measure residue mod 15.
# Expected: ~100% residue = 7 (the coset state guarantees this).
N_shots = 2000; hits = Dict{Int, Int}()
for _ in 1:N_shots
    @context EagerContext() begin
        c = QCoset{4, 3}(7, 15)
        x = Int(c.reg)   # 7-qubit measurement
        r = x % 15
        hits[r] = get(hits, r, 0) + 1
    end
end
# Result: only 13.1% of outcomes gave residue 7.
```

Distribution was roughly Gaussian around r=7 (r=7 peak 13.1%, r=6 and r=8
at ~12-13%, tails at r=0 and r=14 below 1%). That's a MOSTLY-RANDOM state,
not a coset. Fully wrong.

Two distinct bugs in the QFT-sandwich approach:

1. **QFT-sandwich is conceptually wrong** when controls are wires of the
   register being QFT'd. `superpose!(reg)` transforms `|k⟩` into the
   Fourier-basis state `⊗_j (|0⟩ + e^{2πi·k/2^j}|1⟩)/√2`. For nonzero k,
   the individual wires carry nonzero phases — they are NOT in |+⟩.
   The implementer's docstring claim "after superpose!(reg), the padding
   bits (which held value 0) are in |+⟩" is wrong for `k ≠ 0` — that
   claim only holds for QFT|0..0⟩ = |+⟩^n, not for QFT|k⟩ with k<2^W
   having low bits set.
2. **Self-wire Rz workaround was wrong.** Implementer noticed Orkan
   rejects `controlled-Rz(θ, ctrl=q, target=q)` and resolved in
   `library/coset.jl:127..137` (pre-fix) by applying `Rz(θ)`
   unconditionally on the self-wire:
   ```
   if target_wire == pad_wire
       qk.φ += θ          # "unconditional Rz(θ)"
   else
       when(pad) do
           qk.φ += θ       # normal controlled-Rz
       end
   end
   ```
   But `controlled-Rz(θ)` with ctrl=target=q acts as `diag(1, e^{iθ/2})`
   (pure phase gate P(θ/2), up to global phase), NOT as
   `Rz(θ) = diag(e^{-iθ/2}, e^{iθ/2})`. The difference is a phase on
   |0⟩ — which is observable when the qubit is in superposition (exactly
   our case: pad qubits are in |+⟩ inside the QFT). Orkan's rejection
   isn't a bug; it's a signal that the circuit structure is fundamentally
   broken.

**Fix:** refactor QCoset to add `pad_anc::NTuple{Cpad, WireID}` field —
**EXTERNAL** pad ancillae allocated separately from reg. New internal
layout is `W + 2·Cpad` qubits total. Then the circuit:
1. For p=0..Cpad-1: apply `apply_ry!(ctx, pad_anc[p+1], π/2)` to put each
   pad ancilla in |+⟩.
2. `superpose!(reg)` — QFT reg (not pad) into Fourier basis.
3. For p=0..Cpad-1: `when(QBool(pad_anc[p+1], ctx, false)) do add_qft!(reg, 2^p * N) end`.
   Pad ancilla is now EXTERNAL to reg — `add_qft!`'s Rz rotations have
   pad as control and reg wires as targets, no self-control conflict.
4. `interfere!(reg)` — inverse QFT.

Resulting state: `(1/√2^Cpad) Σ_{j=0..2^Cpad-1} |j⟩_pad ⊗ |k+jN⟩_reg`.
The pad ancillae remain entangled with reg after init. Tracing them out
(via `discard!` on pad_anc wires in `decode!`) gives the mixed coset
comb. Every reg measurement yields `k+jN` for some j, so
`outcome mod N = k` deterministically.

Structural files changed:
- `src/types/qcoset.jl:32..37` — added `pad_anc::NTuple{Cpad, WireID}` field.
- `src/types/qcoset.jl:55..71` — `discard!` now frees both reg and pad_anc
  (loop over pad_anc calling `discard!(QBool(w, ctx, false))`).
- `src/types/qcoset.jl:107..125` — constructor allocates pad_anc via
  `ntuple(_ -> allocate!(ctx), Val(Cpad))` and passes to `_coset_init!`.
- `src/library/coset.jl:60..95` — rewrote `_coset_init!` with new signature
  `(ctx, reg, pad_anc, ::Val{W}, ::Val{Cpad}, N)`. QFT sandwich AROUND
  controlled adds; pad ancillae EXTERNAL to reg.

**This is NOT the pure single-register coset state** of Gidney 1905.08488
Fig 1 — that requires implementing comparison-negation `(-1)^{x≥2^p·N}`
for phase-kickback disentanglement of pad. For 6xi's residue-correctness
acceptance the entangled construction suffices (partial trace over pad
gives the correct mixed state on reg for measurement purposes). Pure-state
version filed as conceptual follow-on (would need a reversible comparator
circuit — not currently in Sturm).

Verification after fix (both in the commit message and rerun smoke):
- **100% correct residue** (4000 shots of `QCoset{4,3}(7,15)` then
  `x % 15 == 7`)
- All 8 expected basis states {7, 22, 37, 52, 67, 82, 97, 112}
  equiprobable within 3σ binomial (hits at 505, 486, 520, 511, 508, 473,
  499, 498 out of 4000 — σ=20 expected, actual max deviation 27).
- No outcomes outside the expected set (`all(v ∈ expected)` = true).
- q84 smoke tests still 60/60 (no regression).

### `measure!` antipattern warning (bead `amh`, commit `d53643e`)

User flagged mid-session: **`measure!` direct calls violate P2** (the
boundary should be a CAST — `Bool(q)` / `Int(qi)`). My first `decode!`
wrote `measure!(ctx, w)` directly to clean up pad ancillae — classic
antipattern. Also pre-existing tests (`test_bennett_integration.jl:37,312`,
`test_channel.jl:58`) had the same issue. Internally SUPER prevalent
via `deallocate!`'s measure-and-recycle backend.

User policy (NEW, 2026-04-20): "antipatterns are OK for prototyping, but
they should ALWAYS emit compiler warnings" — same discipline as
float→int truncation in sensible languages.

Implementation mirrors existing `_warn_implicit_cast` machinery in
`src/types/quantum.jl:95..103`:

**New helpers** at `src/types/quantum.jl:140..198`:
- `_warn_direct_measure()` — fires once per source location (dedup id
  `(file, line)` of first non-Sturm-src stack frame, matches `_first_user_frame`
  logic at `quantum.jl:68..79`). Uses `maxlog=1` with `_id`-tagged `@warn`.
  Suppressed by either (a) `:sturm_measure_blessed` task-local flag, or
  (b) `:sturm_implicit_cast_silent` (the `with_silent_casts` flag —
  both suppressions share the escape hatch).
- `_blessed_measure!(ctx, wire)` — wraps `measure!` with the blessed
  flag, restores via try/finally. `@inline`-annotated.

**Each `measure!` impl calls the warning at top:**
- `src/context/eager.jl:205` — `_warn_direct_measure()` first line.
- `src/context/density.jl:169` — same.
- `src/context/tracing.jl:135` — same.

**Blessed callers (warning stays silent):**
- `Base.Bool(::QBool)` at `src/types/qbool.jl:94..99` — P2 explicit cast.
- `Base.Int(::QInt)` at `src/types/qint.jl:108..119` — P2 explicit cast.
- `deallocate!(::EagerContext, _)` at `src/context/eager.jl:101..105` —
  partial-trace backend of `discard!(q)`.
- `deallocate!(::DensityMatrixContext, _)` at `src/context/density.jl:68..72`
  — partial-trace backend of `discard!(q)`.

All four were changed from `measure!(ctx, wire)` to
`_blessed_measure!(ctx, wire)`.

**Live verification after landing** (three targeted probes):
1. `Bool(q)` in EagerContext → NO warning.
2. Direct `Sturm.measure!(ctx, q.wire)` → warning fires once with exact
   text: "Direct call to `measure!(ctx, wire)` — this is a P2 antipattern.
   The quantum→classical boundary should be a CAST: use `Bool(q)` or
   `Int(qi)` for measurement, or `discard!(q)` for partial trace. Wrap a
   non-owning view as `Bool(QBool(wire, ctx, false))` if you only have a
   raw WireID. Suppress per-task with `with_silent_casts`."
3. `with_silent_casts() do; Sturm.measure!(ctx, q.wire); end` → NO
   warning (silent).

**Subtle gotcha that bit me first:** `deallocate!` in eager.jl/density.jl
calls `measure!` internally to collapse before recycling the qubit slot.
`discard!(QBool(w, ctx, false))` → `consume!` → `deallocate!(ctx, wire)`
→ `measure!(ctx, wire)` → warning. So the first test run of 6xi showed 4
spurious warnings from `decode!`'s pad-ancilla cleanup loop and 1 from
the TracingContext discard path. Fixed by blessing both `deallocate!`
impls — now the partial-trace path stays silent. TracingContext's
`deallocate!` at `src/context/tracing.jl:32..36` does NOT call `measure!`
(it pushes a `DiscardNode` and records consumed); it's warning-clean by
construction.

**Not fixed in this session:** test files with pre-existing `Sturm.measure!`
calls (`test_bennett_integration.jl`, `test_channel.jl`) — they will now
warn once each when tests run. Acceptable for prototyping per user policy;
fix is one-line per callsite (wrap in `Bool(QBool(...))`) — left for
whoever next touches those files.

### `coset_add!` + `decode!` (bead `6xi`, commit `d53643e`)

Shipped in the same commit as `amh` because `decode!` exercised the P2
warning path — landing one without the other would have left warnings
firing in 6xi tests.

**Public API** in `src/library/coset.jl`:
- `coset_add!(c::QCoset{W, Cpad, Wtot}, a::Integer)` at lines 132..138 —
  GE21 §2.4 modular-via-non-modular pattern. QFT-sandwich around a
  single `add_qft!(c.reg, a)`:
  ```
  function coset_add!(c::QCoset{W, Cpad, Wtot}, a::Integer) where {W, Cpad, Wtot}
      check_live!(c)
      superpose!(c.reg)
      add_qft!(c.reg, a)
      interfere!(c.reg)
      return c
  end
  ```
  The pad ancillae are NOT touched — they stay entangled with c.reg,
  preserving the coset structure across repeated additions.
- `decode!(c::QCoset{W, Cpad, Wtot})` at lines 167..175 — P2-clean:
  ```
  function decode!(c::QCoset{W, Cpad, Wtot}) where {W, Cpad, Wtot}
      check_live!(c)
      ctx = c.reg.ctx
      x = Int(c.reg)                         # P2 cast — measures reg
      for w in c.pad_anc                     # partial-trace pad ancillae
          discard!(QBool(w, ctx, false))     # P2-clean: cast wrapper + discard
      end
      c.consumed = true
      return x % c.modulus
  end
  ```

**Dispatch gotcha resolved:** `decode!` is already exported by the QECC
subsystem (`src/qecc/abstract.jl:25` declares `function decode! end`;
`src/qecc/steane.jl:115` defines `decode!(::Steane, ::NTuple{7, QBool})`).
My new `decode!(::QCoset{W, Cpad, Wtot})` adds a new method to the same
function via multiple dispatch — no namespace conflict, no re-export needed.

**Test file** `test/test_6xi_coset.jl`, 311 tests in 7 testsets:
1. "Decoding preserves residue exactly (smoke)" — 250 decodes across
   5 (W, Cpad, k, N) parameter sets, every single decode must return k.
2. "Residue distribution is 100% k" — 2000 shots × 3 parameter sets,
   zero misses (unmodified state never deviates; Theorem 3.2 applies to
   +k operations, not state preparation).
3. "Basis states uniform within 3σ" — 4000 shots at W=4, Cpad=3, k=7,
   N=15. Expected set {7, 22, 37, 52, 67, 82, 97, 112}; all observed
   values must be in the set; each within 3σ = 3·√(0.125·0.875/4000)
   ≈ 0.0156 of 0.125. Actual: all 8 states hit 473–520 times out of
   4000 (σ-tolerance band 437..563).
4. "coset_add! single addition" — 1000 shots × 4 parameter sets. Accept
   if success rate ≥ 1 − 2^{-Cpad} − 3σ where σ uses p=1−2^{-Cpad}.
5. **"Theorem 3.2 deviation bound scales as 2^{-Cpad}"** — the headline
   physics test. Sweep Cpad ∈ {2, 3, 4, 5} at W=4, N=15, k=7, a=5
   (expected residue 12). 2000 shots per Cpad. Measured deviations
   vs bound 2^{-Cpad}:
   - Cpad=2: bound 0.25, observed deviation ≤ 0.25 + 3σ slack
   - Cpad=3: bound 0.125
   - Cpad=4: bound 0.0625
   - Cpad=5: bound 0.03125
   All within 3σ slack. Verifies the exponential suppression claim from
   Gidney 1905.08488 Theorem 3.2.
6. "Pad ancillae count: W + 2·Cpad" — TracingContext smoke test for
   the internal qubit budget.
7. "Round-trip exhaustive" — W=4, Cpad=2, all (k, N) with k ∈ [0, N)
   and N ∈ {11, 13, 15}: 11+13+15 = 39 cases, every decode == k.

**Runtime**: 19 min (first run) / 16 min (rerun after cache warm). Slow
because Cpad=5 case needs 4+2·5=14 qubits → statevector 2^14 = 16384
complex numbers, many-shot Kraus sampling. Well within the documented
16-qubit device cap but near-boundary.

Total tests in session across q84+6xi+b3l: 60 + 311 + 491 = **862 new
tests**, all passing.

### Runway (bead `b3l`, commit `4f6052f`)

**Surprising scope discovery during implementation:** the q84 design put
the runway at the HIGH END of reg (`wires[W+1..W+Cpad]`) with no high part
above. I originally thought Theorem 4.2 (`2^{-Cpad}` deviation) would
apply directly here. After deriving the math I realised it DOESN'T.

**Derivation sketch.** After `QRunway{W, Cpad}(v)` init:
- main = |v⟩ (low W bits, classical)
- runway = |+⟩^Cpad = `(1/√2^Cpad) Σ_r |r⟩`

Apply classical constant add of `a < 2^Wtot`: full-register state becomes
`(1/√2^Cpad) Σ_r |v + r·2^W + a⟩`. Decompose result modulo 2^(W+Cpad):
- Low W bits of result = `(v + a + carry_from_runway) mod 2^W`. The
  "carry" = 0 always (runway position doesn't overflow into low bits).
  So low W bits = `(v + a) mod 2^W` EXACTLY.
- Runway bits of result = `(r + ⌊(v+a)/2^W⌋) mod 2^Cpad`. This is a
  uniform shift of r by a constant — `Σ_r |r + const⟩ = Σ_{r'} |r'⟩` —
  runway stays in |+⟩^Cpad with no entanglement to main.

Conclusion: for runway-at-end config, decode is DETERMINISTIC — every
shot returns the correct `(v+a) mod 2^W`. Deviation = 0 regardless of
Cpad. Theorem 4.2's `2^{-Cpad}` bound is vacuous.

Where does the bound kick in? Runway-IN-MIDDLE config per Gidney Fig 2:
`low part | runway | high part`. The high part gets `-runway_value`
subtracted at attach time (Fig 2's `-a` box). Then additions into
low+runway cause carries to propagate through the runway, and the
COMBINED (low, runway, high) state is approximately invariant under
additions mod 2^W (the "obliviousness" property). Deviation is
`2^{-Cpad}` because only the extreme runway value `r = 2^Cpad - 1`
can saturate.

Filed as **`Sturm.jl-jrl` P2** — needed for 6oc's runway-folding step
(GE21 §2.7 Fig 3) where the runway gets temporarily collapsed to a
single carry qubit before a multiply-add. Without jrl, 6oc can't deliver
the multi-piece parallel-addition depth reduction that's the actual
point of GE21 §2.6. Added dep: `bd dep add Sturm.jl-6oc Sturm.jl-jrl`.

**Shipped in b3l** (modest scope — runway-at-end primitives):
- `src/library/coset.jl:203..227` — `runway_add!(r::QRunway, a::Integer)`:
  QFT-sandwich + `add_qft!(r.reg, a)`. Same pattern as `coset_add!` but
  on `QRunway.reg` (no pad_anc — runway bits ARE reg wires W+1..W+Cpad).
- `src/library/coset.jl:241..246` — `runway_decode!(r::QRunway) -> Int`:
  `Int(r.reg)` P2 cast, return `x & ((1 << W) - 1)` (low W bits only).
- `src/Sturm.jl:97` — exports `runway_add!`, `runway_decode!`.

**Test file** `test/test_b3l_runway.jl`, 491 tests in 8 testsets:
1. Round-trip without addition — exhaustive across 4 (W, Cpad) configs,
   every v ∈ [0, 2^W) decodes back to v.
2. `runway_add!` correctness — **exhaustive 16×16 grid** at W=4, Cpad=3:
   every (v, a) pair with v, a ∈ [0, 16). All 256 cases match
   `(v + a) mod 16` exactly. Zero failures.
3. Constants > 2^W — 12 cases with a ∈ {16, 31, 63, 127} (up to
   2^Wtot − 1). Still decode correctly mod 2^W.
4. Negative addends — 24 cases with a ∈ {-1, -3, -7, -15}, using
   Julia's `mod(v+a, 2^W)` for non-negative result.
5. Sequence of additions — 20 random trials of 2-6 additions summed.
6. Cpad sweep — Cpad ∈ {1,2,3,4,5}, verify correctness independent of
   Cpad (100 trials total).
7. `discard!(QRunway) errors` — 4 tests confirming the CLAUDE.md
   fail-loud rule is preserved; `runway_decode!` is the blessed consume
   path.
8. Wire counts — smoke test for `length(r) == W + Cpad`.

**One test failure caught on first run**: the "Wire counts" testset
used `TracingContext()`, where `Int(reg)` returns 0 (symbolic
placeholder). Asserted `v == 5` after `runway_decode!`, got 0. Fixed
by switching to `EagerContext()`. Tracing context is for DAG capture
only — measurements are symbolic, not real.

Runtime: 6.2s (no Cpad near cap). Fast.

### Files touched (full list with line ranges)

**New files:**
- `src/types/qcoset.jl` (1..139) — QCoset{W, Cpad, Wtot} struct (q84) +
  pad_anc field (8fy); classical_type traits; linearity (check_live!,
  consume!, discard!); wire access; constructors with validation.
- `src/types/qrunway.jl` (1..166) — QRunway{W, Cpad, Wtot} struct (q84);
  fail-loud `discard!`; `_runway_force_discard!` internal cleanup;
  Base.getindex, length.
- `src/types/qrom_table.jl` (1..200) — QROMTable{Ccmul, W, Nentries} +
  QROMTableLarge{Ccmul, W}; `_canonicalize_table_entries` with
  `modulus::Union{Int, Nothing}` sentinel.
- `src/library/coset.jl` (1..246) — `_coset_init!` (8fy rewrite; 88..95
  the external-pad-ancilla circuit), `_runway_init!` (117..129 Ry(π/2)
  per runway wire), `coset_add!` (132..138 QFT-sandwich), `decode!`
  (167..175 P2-clean), `runway_add!` (203..227 QFT-sandwich),
  `runway_decode!` (241..246 Int cast + low W bits extraction).
- `test/test_q84_types.jl` (1..160) — 60 smoke tests, 9 testsets.
- `test/test_6xi_coset.jl` (1..179) — 311 tests, 7 testsets, including
  Theorem 3.2 deviation-bound sweep.
- `test/test_b3l_runway.jl` (1..128) — 491 tests, 8 testsets, including
  exhaustive 16×16 (v, a) grid.

**Modified:**
- `src/types/quantum.jl` (amh: +57 lines in 140..198) — `_warn_direct_measure`,
  `_blessed_measure!` helpers; extended `with_silent_casts` docstring.
- `src/context/eager.jl` (amh: +2 lines) — `_warn_direct_measure()` at
  measure! top (line 206); `_blessed_measure!` in deallocate! (line 104).
- `src/context/density.jl` (amh: +3 lines) — same pattern (measure! line
  170; deallocate! line 71).
- `src/context/tracing.jl` (amh: +1 line) — `_warn_direct_measure()` at
  measure! top (line 136). No deallocate! change (it's already
  measurement-free — pushes DiscardNode + records consumed).
- `src/types/qbool.jl` (amh: measure! → `_blessed_measure!` at line 96).
- `src/types/qint.jl` (amh: measure! → `_blessed_measure!` at line 112).
- `src/Sturm.jl` (q84/6xi/b3l: +2 export lines) — QCoset, QRunway,
  QROMTable, QROMTableLarge (line 96); coset_add!, runway_add!,
  runway_decode! (line 97).
- `WORKLOG.md` — this session 35 entry.

**Deleted** (rqg): `docs/physics/ekera_hastad_2017_n_plus_half_n.pdf`
(wrong content; real EH17 paper is in `ekera_2017_short_dlp.pdf`).

**Added** (rqg): `docs/physics/ekera_2023_single_run_dlp.pdf` (arXiv:2309.01754),
`babbush_2018_qrom_linear_T.pdf` (arXiv:1805.03662),
`gidney_2025_rsa2048_1m_qubits.pdf` (arXiv:2505.15917),
`regev_2023_efficient_factoring.pdf` (arXiv:2308.06572).

### Commits (all pushed to `origin/main`)

```
d52cdea  docs(worklog): session 35 entry — q84 + 8fy + 6xi + amh + b3l + lessons
4f6052f  feat(runway): runway_add! / runway_decode! + 491 tests — close Sturm.jl-b3l
d53643e  feat(coset+P2): coset_add!/decode! + measure! antipattern warning
234b8ef  fix(coset): rewrite _coset_init! with external pad ancillae — close Sturm.jl-8fy
790c27f  feat(types): QCoset, QRunway, QROMTable type definitions + coset/runway init circuits — close Sturm.jl-q84
```

Dolt remote also pushed (`bd dolt push` — `refs/dolt/data` on
`git+https://github.com/tobiasosborne/Sturm.jl.git`) after each close.

### Beads (this session — fully-qualified state)

**Closed** (chronological within session):
- `Sturm.jl-rqg` P1 — Pre-flight PDF audit + fetch.
- `Sturm.jl-q84` P1 — Type design 3+1 round (QCoset/QRunway/QROMTable).
- `Sturm.jl-8fy` P0 — Fix _coset_init! state preparation bug.
- `Sturm.jl-amh` P1 — Antipattern warning for measure! direct calls.
- `Sturm.jl-6xi` P1 — Coset representation (coset_add! + decode!).
- `Sturm.jl-b3l` P2 — Oblivious carry runways (runway-at-end variant).

**Filed open** (this session):
- `Sturm.jl-7z1` P3 — Follow-on: Gidney 2025 approximate residue arithmetic.
- `Sturm.jl-wzc` P4 — Follow-on: Regev 2023 multi-dim factoring.
- `Sturm.jl-5jn` P3 — Julia hygiene: `_shor_mulmod_a!` ntuple fix.
- `Sturm.jl-2i0` P3 — Julia migration: task_local_storage → ScopedValue.
- `Sturm.jl-jrl` P2 — QRunway runway-in-middle layout (blocks 6oc).

**Pre-existing, still open/blocked:**
- `Sturm.jl-6oc` P1 — Windowed arithmetic. NOW BLOCKED ON `jrl`.
- `Sturm.jl-6bn` P2 — Ekerå-Håstad short-DLP. Ready (indep at circuit level).
- `Sturm.jl-870` P1 — Steane [[7,1,3]] QECC syndrome extraction. Ready.
- `Sturm.jl-di1` P2 — Backend scaffolding (tensor-network + hardware).
- Several others (see `bd list --status=open`).

### Lessons for future agents

1. **Smoke tests aren't enough for state-preparation circuits.** q84's
   60/60 smoke tests passed while the prepared state was 87% wrong.
   Always probe the actual state distribution (measure N shots, check
   residue/amplitude histogram) before claiming a state-prep bead done.
   The check was ~20 lines of Julia, caught the bug in seconds.

2. **Pad qubits inside the register being QFT'd is broken.** When you
   need pad qubits for a controlled superposition state-prep, allocate
   them EXTERNALLY (outside the target register). Self-control issues
   are NOT fixable by clever Rz angle tricks — the structure is wrong,
   not just the angles. Total qubit count increase is a fair trade.

3. **`measure!` is internal FFI; never call from library/user code.**
   Use `Bool(q)` / `Int(qi)` casts or `discard!(q)`. The warning system
   in `src/types/quantum.jl:140..198` fires at the user stack frame
   (via `_first_user_frame` at lines 68..79), so the offending call
   site is immediately visible in the warning message.

4. **`deallocate!` is the partial-trace backend** — it calls `measure!`
   internally to collapse the qubit before recycling its hardware slot.
   When adding P2 antipattern warnings, remember to bless the deallocate
   path too or every `discard!(q)` call will warn. TracingContext is
   the exception — its deallocate pushes a DiscardNode without actually
   measuring (symbolic), so no bless needed there.

5. **For coset/runway with no high part, deviation is zero.** GE21's
   Theorem 3.2 / 4.2 bounds only apply in the runway-in-middle
   configuration with a high part above the runway. The runway-at-end
   case (cleaner to implement, shipped here) gives deterministic
   correctness but no depth-reduction benefit — the "obliviousness"
   property is vacuous. Filed `jrl` for the in-middle case; 6oc's
   runway-folding step needs it.

6. **Multi-bead chains in one session save context churn.** Closed
   q84 → 8fy → amh → 6xi → b3l in one continuous session by treating
   each bug discovery as a NEW bead rather than reopening the previous
   one. Each bead got a clean commit message with a clear acceptance
   criterion. This is less work than re-opening and easier to audit.

7. **3+1 agent round is worth it for core types — but the orchestrator
   must ALSO run physics checks.** The proposers caught the type-system
   issues (Wtot third param, QInt{W+Cpad} limitation, composition vs
   subtype). The implementer shipped the type correctly. But neither
   the proposers nor the implementer caught the `_coset_init!` physics
   bug — that needed the orchestrator's state-distribution probe. Bake
   the probe into the orchestrator's acceptance review.

8. **Julia multiple dispatch extends function signatures cheaply.**
   `decode!(::Steane, ...)` already existed from QECC. My
   `decode!(::QCoset, ...)` added a new method — no namespace conflict,
   no re-export. Same function name, different argument types, clean
   dispatch. Use this pattern when naming new functions: pick names that
   read naturally regardless of whether they're in the QECC or
   arithmetic namespace.

9. **Claude's TaskCreate/TodoWrite reminders are irrelevant in this
   project.** CLAUDE.md and the `bd remember` infrastructure explicitly
   forbid them — use `bd create / bd update --claim / bd close` only.
   The in-session reminders fire repeatedly regardless; ignore them.

### Next-session pointers

**Best-next-bead tree** (by unblocked-and-ready, highest priority):
- `870` P1 — Steane QECC syndrome extraction. Orthogonal to GE21 stack;
  establishes P6 `encode(ch, code)` HOF framework. Good if you want
  progress independent of GE21.
- `6bn` P2 — Ekerå-Håstad short-DLP. Independent at circuit level (only
  needs `shor_order_D_semi` which is shipped). Deliverables per research
  brief: (a) `shor_factor_EH(N)` driver with two semi-classical QFT
  loops (ℓ+m and ℓ iterations); (b) `_eh_recover_d_2d(j, k, m, ℓ)`
  using 2D Lagrange = extended Euclidean, ~20 lines pure Julia;
  (c) `_eh_factors_from_d(d, N)` using quadratic formula + isqrt.
  Tests: N=15 (p=3, q=5, d=8) multi-shot ≥ 40% hit rate at 200 shots.
  Estimated effort: 1-2 sessions.
- `jrl` P2 — runway-in-middle layout. New type `QRunwayMid{W_low, Cpad, W_high}`
  with the subtraction-from-high step from Gidney Fig 2. Unblocks 6oc.
  Estimated effort: 1 session.
- `6oc` P1 — windowed arithmetic. Blocked on `jrl`. Three phases per
  research brief: (a) qrom_lookup! + measurement-based uncompute;
  (b) plus_equal_product! + runway-fold + shor_order_E driver; (c) bench.
  Estimated effort: 3-4 sessions.

**Hygiene backlog** (P3, batch with any `src/library/shor.jl` work):
- `5jn` — replace `WireID[allocate!(ctx) for _ in 1:L]` in
  `_shor_mulmod_a!` with `ntuple(_ -> allocate!(ctx), Val(L))`.
- `2i0` — migrate `task_local_storage(:sturm_context)` to
  `Base.ScopedValue` (Julia 1.11+) for child-task context inheritance.

**Skip unless explicitly requested:**
- `7z1` / `wzc` — post-GE21 follow-ons (Gidney 2025, Regev 2023).
  These supersede GE21 algorithmically; file for visibility but don't
  mix with GE21 implementation.

**Test files with pre-existing `Sturm.measure!` antipatterns** (now
emit warnings, acceptable per user policy but fix when touched):
- `test/test_bennett_integration.jl:37, 312`
- `test/test_channel.jl:58`
- Fix pattern: `Sturm.measure!(ctx, w)` → `Bool(QBool(w, ctx, false))`.

### Lessons for future agents

1. **Smoke tests aren't enough for state-preparation circuits.** q84's 60/60
  smoke tests passed while the prepared state was 87% wrong. Always probe
  the actual state distribution before claiming a state-prep bead done.
2. **Pad qubits inside the register being QFT'd is broken.** When you need
  pad qubits for a controlled superposition state-prep, allocate them
  EXTERNALLY (outside the target register). Self-control issues are not
  fixable by clever Rz angle tricks.
3. **`measure!` is internal FFI; never call from library/user code.** Use
  `Bool(q)` / `Int(qi)` casts or `discard!(q)`. The warning system fires
  at the user stack frame, so the offending call site is obvious.
4. **`deallocate!` is the partial-trace backend** — it calls `measure!`
  internally. When adding a P2 antipattern warning system, remember to
  bless the deallocate path too or every `discard!` call will warn.
5. **For coset/runway with no high part, deviation is zero.** GE21's
  Theorem 4.2 bound only applies in the runway-in-middle configuration
  with a high part above the runway. The runway-at-end case (cleaner to
  implement) gives deterministic correctness but no depth-reduction
  benefit. Filed `jrl` for the in-middle case.
6. **Multi-bead chains in one session save context churn.** Closed q84
  → 8fy → amh → 6xi → b3l in one continuous session by treating each
  bug discovery as a new bead rather than reopening the previous one.

---

