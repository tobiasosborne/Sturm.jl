## 2026-04-23 — Session 55: `nrs` (Sturm.jl-nrs) — Rz at all d, Ry split off to k8u

Claimed `Sturm.jl-nrs` (qubit-encoded fallback simulator for QMod{d}).
Full 3+1 round ran in one session: 2 proposer subagents in parallel,
synthesis, implementation. Designs at
`docs/design/nrs_design_proposer_{a,b}.md` (925 + 936 lines).

### The design-round outcome was unexpected

Both proposers converged cleanly on the Rz path — per-wire binary
factorisation, closed-form, O(K) gates, provably leakage-free. Both
proposers ALSO agreed to ship Ry at d ∈ {3, 5} via a Givens / Wigner-
small-d decomposition. **But neither actually derived the Ry sequence.**

  * Proposer A's §5 sketched a 3-Givens ladder (G_{0,1} · G_{1,2} · G_{0,1})
    with hand-wavy angles; §6 then worried the X-bracket trick leaks,
    self-corrected, but the algebra isn't closed.
  * Proposer B's §5 proposed a 4-Ry + 3-CX template citing "Klappenecker-
    Rötteler 2003" but admitted: "exact closed-form angles for this
    7-gate sequence at d=3 are NOT derived in this design doc — I do not
    have a paper giving the exact sequence".

Rule 6 ("quantum bugs are deep and interlocked") + Rule 1 (fail loud,
not quietly-wrong) forced a split. Shipping an un-derived Ry
decomposition that LOOKS right but leaks a fraction of 2^{-K} amplitude
at every gate is exactly the Session-8-Python-Grover failure mode
CLAUDE.md calls out.

### Synthesis (orchestrator's narrower scope)

  * **Rz path (`q.φ += δ`), all d ≥ 3**: SHIP. Per-wire factorisation of
    `exp(-i δ (j - s))` using `s = Σ b_i 2^i`. K single-qubit Rz's per
    call. Provably diagonal → zero leakage. Differs from the ideal by a
    global phase that becomes a controlled relative phase under `when()`
    per locked §8.4 policy.
  * **Ry path (`q.θ += δ`), d ≥ 3**: DEFER to new bead `Sturm.jl-k8u`
    with explicit acceptance criteria (amplitude match against hand-
    computed Wigner d-matrix to 1e-10). k8u owns the derivation work
    that neither proposer completed.
  * **apply_sum_d (SUM backend)**: DEFER to bead `p38` (SUM is cyclic
    shift mod d — reversible permutation, not a spin-j rotation; p38 is
    its own bead with its own proposer round).
  * **Leakage-guard TLS flag**: still deferred. Not needed for
    correctness — Rz is provably diagonal.

### Rz factorisation — the math

Bartlett Eq. 5: `|s⟩ = |j, j-s⟩_z`, so `Ĵ_z|s⟩ = (j - s)|s⟩`. With
`s = Σ_{i=0}^{K-1} b_i 2^i` (LE encoding):

    exp(-iδ(j - s)) = exp(-iδj) · Π_i exp(+iδ b_i 2^i)

The `exp(-iδj)` prefactor is a global phase. Each `exp(+iδ b_i 2^i)` on
wire `i+1` is implemented by `apply_rz!(ctx, wires[i+1], δ·2^i)`:

    apply_rz!(ctx, wire, θ) = diag(e^{-iθ/2}, e^{+iθ/2})

gives `e^{+iθ/2}` on `b=1` — matches the target `e^{+iδ 2^i}` up to a
per-wire global phase `e^{+iθ/2}` that accumulates to ANOTHER global
phase. Net: ratio (ours / ideal) = `e^{+iδj - iδ(2^K-1)/2}`, same
across all |s⟩ = a true global phase. Verified by hand at d=3 for
s ∈ {0, 1, 2}: all three get the same phase `e^{-iδ/2}`.

At d=2 (K=1), the formula collapses to `apply_rz!(wires[1], δ)` —
exactly what the QBool BlochProxy already does. Regression-tested by
re-running the ak2 d=2 parity test (QMod{2}.φ += δ ≡ QBool(0.0).φ += δ
bit-identically).

### Testing

16 new testsets, 48 new assertions for the Rz Path:
  * d=3 / d=5 diagonal behaviour — no amplitude redistribution
  * d=3 / d=5 relative-phase match against Ĵ_z spectrum
  * d=2 ak2 regression (QMod{2}/QBool parity preserved)
  * Rz cannot leak (10 random rotations on QMod{3}, |11⟩ amp stays 0)
  * `when(ctrl) q.φ += δ` — controlled-Rz on a 3-qubit product state
  * `when(ctrl) q.φ += δ` — leakage preserved under coherent control
  * ak2 Ry deferral test updated: error message now points to `Sturm.jl-k8u`
    instead of the old `Sturm.jl-nrs` pointer
  * ak2 Rz deferral test REMOVED (φ works now)

Total test_qmod.jl: 147 assertions, 5.8s wall. All GREEN.

Adjacent-test sanity (Rule 9): `test_qint` (562/562), `test_primitives`
(711/711), `test_when` (507/507), `test_implicit_cast` (14/14). Zero
regressions. 1794 adjacent + 147 QMod = 1941 clean assertions.

### Why this is the right cut

Shipping the Rz path alone:
  * Unblocks `q.φ += δ` at ALL d — every library gate that's diagonal
    (`Z_d!`, parts of `F_d!`, phase kickback in QFT) now has a real
    backend.
  * Keeps Rule 1 honest — no under-derived Ry that might pass some tests
    and corrupt others.
  * Makes the follow-on bead (`k8u`) clean and focused: one specific
    piece of math, one specific acceptance test.

The `csw` v0.1 acceptance bead needs Ry at d=3 and d=5 — so k8u is
still on the critical path. But splitting means k8u gets its own 3+1
round without re-litigating the Rz decisions.

### k8u acceptance criteria (filed in the bead description)

  (a) d=3 `q.θ += π/3` produces amplitudes matching Wigner d^1(π/3)
      column 0 to 1e-10: (0.75, sin(π/3)/√2, 0.25) on labels (0, 1, 2)
      with |11⟩_qubit amplitude < 1e-12.
  (b) d=5 `q.θ += π/4` matches d^2(π/4) column 0.
  (c) Subspace preservation verified statistically over 1000 random
      rotation sequences.

Options for the k8u implementer (to be explored in the 3+1 round):
  * KAK / cosine-sine decomposition of the block-diagonal 2-qubit
    unitary `[d^1(δ), 0; 0, 1]`.
  * Derive the 4-Ry + 3-CX template angles numerically from Sakurai
    Eq. 3.8.33 via a 4-variable solve with 4 independent constraints.

### Files touched

  * `src/types/qmod.jl` — replace the `_apply_spin_j_rotation!` stub's
    unconditional error with an axis-dispatched implementation:
    Rz per-wire factorisation for `:φ`; Ry still errors for `:θ` with
    the updated k8u pointer. +20 lines of code, +15 lines of docstring.
  * `test/test_qmod.jl` — delete the obsolete `q.φ += δ` deferral
    testset (Rz now works); update the Ry deferral testset to check for
    `Sturm.jl-k8u` in the error message; add 9 new nrs Rz testsets.
    +~150 lines, −30 lines.
  * `docs/design/nrs_design_proposer_{a,b}.md` — durable copies.

No edits to `src/Sturm.jl` (helper internal), `src/types/qbool.jl`
(Rule 11 frozen), or any context file.

### `bd dolt push` STILL BLOCKED

Same GH secret-scanning URL as Sessions 51-54. Local beads: `nrs`
closed, `k8u` created, `nrs_design_*.md` added. Re-attempt next session.

### What's unlocked / what's next

  * **`Sturm.jl-k8u`** (QMod{d} Ry rotation) — explicit critical-path
    follow-on. Deserves its own 3+1 round focused on the decomposition
    math. Blocks: csw acceptance; u2n library gates that use Ry (X_d!,
    H_d!, F_d!).
  * **`Sturm.jl-os4`** (squeezing `q.θ₂`) — diagonal, same pattern as
    our Rz (per-wire factorisation of exp(-iδ n̂²) reduces to per-pair
    controlled-Rz cascade). Unblocked.
  * **`Sturm.jl-mle`** (cubic-phase magic `q.θ₃`) — similar per-pair
    diagonal cascade. Unblocked.
  * **`Sturm.jl-p38`** (SUM `a ⊻= b` at d>2) — independent of nrs per
    the agreement. Unblocked.

Recommendation: next productive move is either k8u (critical path, hard
math) or os4/mle (diagonal, similar pattern to Rz, easy wins).

---

## 2026-04-23 — Session 54: `ak2` (Sturm.jl-ak2) — spin-j Ry/Rz, d=2 shipped, d>2 deferred

Claimed `Sturm.jl-ak2` (primitives 2 and 3 of the locked 6-primitive qudit
set — `q.θ += δ` = `exp(-iδĴ_y)` and `q.φ += δ` = `exp(-iδĴ_z)` on the
spin-j=(d-1)/2 irrep). Full 3+1 round in one session this time: dispatched
2 proposer subagents in parallel, both converged, I implemented.

Designs at `docs/design/ak2_design_proposer_{a,b}.md` (628 + 556 lines).

### Strong convergence across the two proposers

Both picked:
  * **Hybrid proxy**: reuse existing `BlochProxy` at d=2 (single-wire fast
    path, bit-identical to qubit Ry/Rz); new `QModBlochProxy{d, K}` at d>2
    carrying the full wire group + `d`.
  * **Defer d>2 to bead `Sturm.jl-nrs`** (qubit-encoded fallback simulator
    integration). Ship d=2 only this bead; d>2 errors loudly with a pointer.
  * **Subspace preservation by construction** (option a). No per-gate
    projection, no debug amp-sweep in this bead. The unconditional
    post-measurement check in `Base.Int` from bead 9aa is the safety net.
  * **Extend `src/types/qmod.jl`** rather than splitting into a new
    rotations file. Matches the `qbool.jl`/`qint.jl` precedent of keeping
    the type definition and its primitives colocated.

### Orchestrator picks where they differed

  * **Method-level dispatch over runtime branch for the d=2 case.**
    Proposer A used a single `getproperty(::QMod{d, K})` with `if d == 2`
    inside; Proposer B used two methods — `getproperty(::QMod{2, 1})` and
    the generic `where {d, K}` — and let Julia's multiple dispatch pick by
    specificity. Picked B's: type-stable, constant-folded, idiomatic.
  * **Extend existing `test/test_qmod.jl`** (B) rather than a new
    `test_qmod_rotations.jl` (A). Keeps all QMod tests in one file,
    matches `test_qint.jl`'s pattern.
  * **Kept Proposer A's `when()` test** (Testset 5 in A). Verifies that
    `when(ctrl) do qm.θ += δ end` at d=2 composes with the control stack
    exactly as the qubit primitive does. Worth having.
  * **Skipped both proposers' `@test_skip` scaffolds for nrs-deferred
    tests.** Clutters the report with permanent skips; nrs's implementer
    writes their own tests. The deferral-error tests cover the boundary.

### The d=2 trick — why Rule 11 holds bit-identically

`Base.getproperty(q::QMod{2, 1}, :θ)` returns a `BlochProxy`
(`src/types/qbool.jl:67-72`) aliased to `q.wires[1]`. Then
`BlochProxy + δ` calls `apply_ry!(ctx, wires[1], δ)` — the same qubit
primitive. Zero new code path at d=2. Verified by statevector-parity
tests: `QMod{2}().θ += δ` produces an amplitude vector equal to
`QBool(0.0).θ += δ` to 1e-12 across 6 angles (including π and 0). Same
for `φ`. Same for 4-gate chains.

The `BlochProxy.parent::QBool` field gets a fresh non-owning view
`QBool(wires[1], ctx, false)` — same aliasing idiom `_qbool_views` uses
on QInt. Edge case acknowledged by both proposers: if someone stashes
`let p = q.θ` and later consumes the QMod, `p + δ` won't detect it
(the view's `consumed` flag is independent). Matches existing QInt
precedent; documented inline.

### d>2: deferral stub with Val(d) for future dispatch

`_apply_spin_j_rotation!(ctx, wires, axis, δ, ::Val{d})` takes a Val-d
so the future `nrs` implementer can add specialised methods per
dimension without changing call sites. Stub body is `error(...)` with a
pointer to bead `nrs`; tested at d ∈ {3, 4, 5, 8} (both power-of-2 and
non-power-of-2 cases defer — the pow2 case is NOT a shortcut because
the spin-j decomposition still requires multi-qubit gates, distinct
from straight `apply_ry!`).

### Ĵ_z convention note for `nrs` follow-on

Bartlett Eq. 5 puts `|s⟩ ≡ |j, j-s⟩_z`, so `Ĵ_z|s⟩ = (j - s)|s⟩`. At
d=2 this is exactly what orkan's `apply_rz!` does — phase `e^{-iδ/2}`
on `|0⟩`, `e^{+iδ/2}` on `|1⟩`. At d>2 `nrs` must honour the `j - s`
shift when deriving the diagonal Rz phases. Flagged in both proposer
designs, noted in the stub's docstring.

### TDD cycle

Tests extended test_qmod.jl from 21 testsets (56 assertions) to 29
testsets (99 assertions). First GREEN on first run — no retries.

Adjacent-test sanity (Rule 9): `test_primitives` (711/711), `test_when`
(507/507), `test_qint` (562/562), `test_ptrace` (9/9),
`test_implicit_cast` (14/14). No regressions. 1803 adjacent assertions +
99 QMod = 1902 clean.

### Files touched

  * `src/types/qmod.jl` — `QModBlochProxy{d, K}` struct, two-method
    `getproperty` (d=2 specialised, d>2 generic), `setproperty!`
    sentinel no-op, `Base.:+` / `Base.:-` on QModBlochProxy,
    `_apply_spin_j_rotation!` stub. +~115 lines.
  * `test/test_qmod.jl` — 8 new testsets for ak2 (parity × 3, `when()`,
    deferral errors × 2, proxy types, liveness). +~185 lines.
  * `docs/design/ak2_design_proposer_{a,b}.md` — durable copies of the
    proposer outputs (/tmp doesn't survive).

No edits to `src/Sturm.jl` (QModBlochProxy is internal — no export),
`src/types/qbool.jl` (Rule 11 — qubit primitives frozen), or any
context file (no new apply_* methods; d=2 rides existing paths).

### `bd dolt push` STILL BLOCKED

Same GH secret-scanning unblock URL as Sessions 51-53. Local beads
this session: `ak2` closed, `ak2_design_*.md` added. Re-attempt next
session.

### What's unlocked / what's next

The qudit syntax `q.θ += δ` / `q.φ += δ` now works at d=2. The remaining
qudit primitive beads are independent of each other — any order works:

  * **`Sturm.jl-nrs`** — the big one. Qubit-encoded fallback simulator
    integration: implements `_apply_spin_j_rotation!` for d>2 via the
    Givens / Wigner-small-d decomposition. Unblocks ak2 at d>2, plus
    os4, mle, p38 at d>2, plus all library gates `X_d!`, `Z_d!`, `F_d!`,
    `T_d!`, `QuditToffoli!`. Logically the critical path.
  * **`Sturm.jl-os4`** (squeezing `q.θ₂`) — diagonal primitive, could
    ship d=2 trivially (collapses to global phase per §8.1) and d>2 via
    nrs.
  * **`Sturm.jl-mle`** (cubic-phase magic `q.θ₃`) — same pattern as os4.
  * **`Sturm.jl-p38`** (SUM `a ⊻= b` at d>2) — cyclic shift mod d. At
    d=2 reduces to CNOT. At d>2 needs nrs's multi-qubit decomposition.

Recommendation: `nrs` next. Every remaining primitive bead builds on it.

---

## 2026-04-23 — Session 53: `goi-type` (Sturm.jl-9aa) — implementer phase, GREEN

Picked up where Session 52 left off. Two proposer designs already at
`docs/design/qmod_design_proposer_{a,b}.md`; my role this session is
implementer + orchestrator-as-reviewer per Rule 2 (3+1 protocol).

### Synthesis (orchestrator's pick across the two proposers)

Convergence was strong; the only real decisions were

  * **`QMod{d, K}` (K hidden)** — both proposers picked NTuple-of-WireID
    + a hidden second type parameter. Bikeshed: K vs W. Picked **K** per
    Session 52 WORKLOG (W is reserved for the future `QInt{W,d}` width,
    bead `goi-qint-d` / `dj3`).
  * **No mixed-d xor stub.** Proposer A wanted `Base.xor(::QMod{d1},
    ::QMod{d2}) where {d1,d2}` to error here; B deferred to bead `p38`
    (SUM). Picked B's path: a missing method gives a `MethodError` —
    loud-fail Rule 1 by Julia's dispatch machinery, with no risk of
    accidentally pre-shadowing `p38`'s eventual `where {d}` SUM method.
  * **`classical_type(::Type{<:QMod})` intentionally not defined.**
    Bennett.jl currently lowers with mod-2^W arithmetic only; calling
    `oracle(f, q::QMod{d})` would silently produce mod-2^K results
    rather than mod-d. Leaving the trait undefined makes the failure a
    `MethodError` instead of a wrong answer. Filed follow-on bead
    `Sturm.jl-jba` ("QMod{d} Bennett interop — modular arithmetic in
    reversible IR"). Tested explicitly: `@test_throws MethodError
    Sturm.classical_type(QMod{3, 2})`.
  * **No leakage TLS sweep this bead.** Layer 3 (unconditional O(1)
    post-measurement check in `Base.Int`) ships; layer 2 (per-primitive
    proof obligation) is later beads' responsibility; the dynamic
    amplitude-buffer sweep (`with_qmod_leakage_checks`) is filed later
    if real leakage bugs surface in `os4`/`mle`.
  * **No `Bool(::QMod{2})` interop.** Survey §8.5 — `QMod` is the
    arithmetic API on Z/dZ, `QBool` is the logical API. Tested:
    `@test_throws MethodError Bool(QMod{2}())`.

### Files

  * `src/types/qmod.jl` (new, 167 lines) — type, ctor, `Base.Int`,
    `Base.convert(::Type{Int}, ...)` with P2 warning, `ptrace!`,
    `Base.length`, `_qmod_nbits` helper.
  * `src/types/quantum.jl` — docstring lists `QMod{d, K}` instead of
    "future QDit{D}".
  * `src/Sturm.jl` — `include("types/qmod.jl")` after qint, export
    `QMod`.
  * `test/test_qmod.jl` (new, 244 lines) — 21 testsets, 56 assertions.
  * `test/runtests.jl` — register `test_qmod.jl` after `test_qint.jl`.

### TDD cycle

Tests written first, then implementation (Rule 10). First green run was
50/56 due to two unexported helpers used in the leakage-injection tests
(`apply_ry!`, `live_wires`); fixed by qualifying as `Sturm.apply_ry!`
and `Sturm.live_wires` per the existing private-symbol convention.
Final: **56/56 GREEN**, 4.1 s wall.

### Adjacent-test sanity (Rule 9 skepticism)

Risk that the new ptrace!/Int/convert methods could shadow QInt or
QBool dispatch. Verified by running:

  * `test_qint.jl` — 562/562 ✓
  * `test_ptrace.jl` — 9/9 ✓ (the `methods(ptrace!)` test uses
    `any(...)`, doesn't pin a count, so a 5th method is fine)
  * `test_implicit_cast.jl` — 14/14 ✓
  * `test_autocleanup.jl` — 14/14 ✓

No regressions. `Pkg.test()` not run (per device-perf memory: full
suite is multi-minute).

### Helper choice: `_qmod_nbits` via `leading_zeros`

Proposer A used `ceil(Int, log2(d))`; Proposer B used `64 -
leading_zeros(d - 1)`. Picked B's: pure integer arithmetic, no
floating-point round-off worry, faster. Behaviour: d=2→1, d∈{3,4}→2,
d∈{5..8}→3, d∈{9..16}→4. Matches `_qmod_nbits` semantics in both
designs.

### Subtle: `_warn_implicit_cast(QMod{d}, Int)` prints "QMod{3} → Int"

Confirmed by test
`@test_logs (:warn, r"Implicit quantum→classical cast QMod\{3\} → Int")`.
Inside `Base.convert(::Type{Int}, q::QMod{d, K}) where {d, K}`,
`QMod{d}` substitutes to `QMod{3}` which is the UnionAll `QMod{3} where
K`; Julia stringifies that as `QMod{3}`, not `QMod{3, 2}`. Same trick
QInt uses for its `QInt{W} → Int` warning text — minor surprise that
the K parameter doesn't leak into the message.

### `bd dolt push` STILL BLOCKED

Same GH secret-scanning unblock URL as Sessions 51/52, now pointing at
commit `37c10ae...` path `5kij7tbnvrv2aassnqpjmpbvbk45maci.darc:7715`.
Local-only beads this session: bead `Sturm.jl-9aa` will be closed,
`Sturm.jl-jba` (Bennett interop follow-on) was created. Re-attempt
`bd dolt push` next session in case user clears the block. Local dolt
ref `dq7a2s6a...` was already in sync at session start (clean
fast-forward from origin).

### What's unlocked / what's next

`QMod{d}` is now a real type. The remaining qudit primitive beads can
proceed in any order:

  * `Sturm.jl-ak2` — spin-`j` Ry/Rz primitives (`q.θ`, `q.φ`)
  * `Sturm.jl-os4` — squeezing primitive (`q.θ₂`)
  * `Sturm.jl-mle` — cubic-phase magic primitive (`q.θ₃`)
  * `Sturm.jl-p38` — SUM entangler (`a ⊻= b` at d>2)
  * `Sturm.jl-nrs` — qubit-encoded fallback simulator integration

P5 invariant (no qubits in user-facing code) requires that none of
those primitives expose `q.wires` to user code — they should dispatch
on `QMod{d, K}` and operate on the underlying NTuple internally, same
as `QInt{W}`'s `+`/`-` do today.

### `bd update Sturm.jl-9aa --close`

Closing post-merge. Acceptance criteria from the bead description met:

  * `QMod{3}(ctx)` constructs at d=3 (3-dim H via 2 qubit wires) ✓
  * `Int(QMod{3}(ctx)) == 0` for the |0⟩ prep ✓
  * Power-of-2 d packs perfectly, non-power-of-2 d has leakage guard ✓
  * Existing qubit path preserved (562 QInt tests, 9 ptrace tests,
    14 implicit-cast tests, 14 autocleanup tests all GREEN) ✓
  * P2 warning fires on `x::Int = q` ✓

The bead originally said "QMod{d,Ctx}<:Quantum parametric on dimension
d and context Ctx" — that's wrong (context is a runtime field, not a
type parameter, in Sturm's existing types). Fixed implicitly by
following the proposer designs and Session 52 WORKLOG.

---

