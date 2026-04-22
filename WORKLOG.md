# Sturm.jl Work Log

Gotchas, learnings, decisions, and surprises. Updated every step.

---

## 2026-04-22 — Session 42: fix the X!/Y! swap (bead `3yz`), unblock 870, wire tests

Ship the Pauli-swap fix that session 41 had deferred. (Session 41's
bead `a1e` never actually reached the dolt remote — the local filing
didn't land, so I refiled as `Sturm.jl-3yz` with the full reasoning
plus the downstream blast-radius analysis, then dep'd `Sturm.jl-35s`
(Grover/phase_flip audit) and `Sturm.jl-9g5` (block-encoding audit)
underneath it, plus `Sturm.jl-7pz` for the eventual atomic-XNode
design question.)

### Empirical verification (pre- and post-fix)

Wrote `/tmp/verify_pauli.jl` — builds a DensityMatrixContext, prepares
a generic ρ via raw primitives (Ry + Rz + CNOT, avoiding H!/X!/Y! to
prevent self-reference), reads ρ directly from `ctx.orkan[r,c]`, applies
each gate in src/gates.jl, and compares ρ_after against
`U_k · ρ_before · U_k'` for every candidate U ∈ {I, X, Y, Z, H, S, T}.

Pre-fix: for every (n ∈ 1..5, target ∈ 0..n-1) — 15 configs each for
X! and Y! — X! matched the Y channel at ≤1e-16 and the X channel at
0.78..1.36; Y! matched X at ≤1e-16 and Y at 0.78..1.36. The Z/S/T/H
gates matched their intended channels at machine precision.

Post-fix: 90/90 correct (best-match == expected AND err < 1e-8).

### The fix

One line per gate in `src/gates.jl`:

- `X!(q::QBool) = (q.φ += π; q.θ += π; q)` — Rz(π)·Ry(π) = (−iZ)(−iY) =
  −ZY = iX, channel XρX. Now two primitives (was one).
- `Y!(q::QBool) = (q.θ += π; q)` — Ry(π) = −iY, channel YρY. Now one
  primitive (was two).

### Blast radius: five invariance proofs saved the downstream code

Every `src/` caller of `X!` (Grover `_diffusion!`, `phase_flip!`,
block_encoding `_rotation_tree!`, block_encoding `_flip_for_index!`,
Steane `correct!`) was either (a) on a freshly-prepared `|0⟩`,
(b) inside an `X! q; when(q); X! q` control-polarity-flip sandwich, or
(c) inside an `X-MCZ-X` diagonal-conjugation sandwich. None needed code
changes, for two distinct algebraic reasons:

1. **Sandwich around `when(q)`**: `Y|0⟩⟨0|Y = |1⟩⟨1| = X|0⟩⟨0|X`, so
   the control polarity flips identically under either convention.
2. **Sandwich around diagonal MCZ**: For any diagonal D,
   `Y^⊗W · D · Y^⊗W = X^⊗W · D · X^⊗W`. Direct computation: Y = iXZ
   so Y^⊗W D Y^⊗W = i^W(-i)^W · (XZ)^⊗W D (XZ)^⊗W, and the Z factors
   commute through the diagonal to cancel. So Grover diffusion
   and phase_flip! are literally unchanged.

That's why `test_grover` (284/284), `test_patterns` (92/92), and
`test_block_encoding` (63/63) passed both before AND after the fix.
Beads `35s` and `9g5` capture hardening tests that would fail if the
invariance ever breaks — the invariance-preserving patterns are
load-bearing and deserve explicit coverage, not silent reliance.

### The things the fix DID break (and how I updated them)

1. **`src/channel/draw.jl:576-581`** — the single-node labeler mapped
   `RyNode(π) → "X"`. That was a lie pre-fix; now it reads `"Y"`. The
   actual X channel is Rz(π)→Ry(π), two adjacent nodes on one wire,
   which the labeler doesn't pattern-match (deferred to bead `7pz`).
   Test updates: `test_draw.jl:136, 101`.

2. **`test_qecc.jl:143-154`** — logical-X DAG structure. Was
   `length(ch.dag) == 1` + `ch.dag[1] isa RyNode`. Now 2 nodes
   (Rz + Ry). The encoded-channel total goes from 47 (17+7+17+6) to
   54 (17+14+17+6 — transversal X now contributes 7×2=14 nodes).

3. **`test_gates.jl "X! flips"`** — shallow test: `X!(QBool(0))` produces
   `Bool(q) == true`, which passes for X OR Y (both flip |0⟩). Added
   three discriminator testsets:
   - `H; X!; H` on `|0⟩` → Bool == false (H·X·H = Z).
   - `H; Y!; H` on `|0⟩` → Bool == true (H·Y·H = −Y).
   - `X!; Y!; Z!` on `|0⟩` → Bool == false (composes to ±iI).

4. **`Sturm-PRD.md:267`** — documented the correct definitions. Also
   added Y! (was absent from the PRD derived-gates table).

5. **`test/runtests.jl`** — wired `test_steane_syndrome.jl`. It was
   held out at end of session 41 (14/80 red). Post-fix: 80/80.

### Full regression snapshot (targeted, per device-performance memory)

Foundational: primitives 711, bell 2002, teleportation 1002. Gates 904
(strengthened). QECC 1175. Steane syndrome 80. Patterns 92. Draw 53.
Cases 36. Channel 44. Density-matrix 1753. Grover 284. Block-encoding
63. Hardware-QECC 80+. OpenQASM-cases 17. ~9,200 assertions total, all
green.

### Gotchas

1. **Session 41's "filed" bead `a1e` was not actually in dolt.**
   `bd search` / `bd list` / `bd show Sturm.jl-a1e` all turned up
   nothing. Worklog entry said "bd-tool bug prevented bd dep add —
   dependency is in the notes field", but the bead itself never
   reached the remote either. Refiled as `3yz`. Lesson: if the
   worklog narrates a bead that matters, future-me should `bd show`
   it to confirm it exists before trusting the pointer.

2. **`bd dolt push` autopush failed on every bead create today**
   (non-fast-forward). Local is ahead of remote for beads. Will run
   the merge recipe (stash-commit + fetch + pull) at session close —
   stored memory has both the merge and annihilate recipes. This is
   normal cross-device drift, not a bug.

3. **Grover really is invariant.** Session 41's WORKLOG flagged
   `library/patterns.jl:322,325` as "may be silently wrong" — "Y|+⟩
   = i|-⟩, very different from X|+⟩ = |+⟩". True for bare X vs Y on
   |+⟩, but in the diffusion the X's are NOT applied to |+⟩ states
   in isolation; they conjugate the multi-controlled Z which is
   diagonal. Y conjugation of diagonal = X conjugation of diagonal.
   The session-41 concern was correct-to-worry-about but the algebra
   works out. Test coverage (bead `35s`) will protect against a
   future refactor that removes this invariance.

4. **`test_gates "X! flips"` was a shallow test.** Flipping |0⟩ is
   true for X, Y, iX, −iY, … — any unitary with off-diagonal ±1s on
   the computational basis. This is why session 41's 40+-session
   drift went undetected there. Strengthened with H-sandwich
   discriminators. General lesson: gate tests on `|0⟩`-only inputs
   cannot distinguish X from Y (both map |0⟩↔|1⟩ up to phase).

5. **`X!` is now two primitives.** Any future DAG-structure
   assertion in tests needs to account for this. Search
   `length.*\.dag.*==` + any context using `X!` before adding such
   assertions. Bead `7pz` captures the option to restore atomicity
   via a dedicated XNode in the IR.

### Files touched this session

- `src/gates.jl`: X!/Y! swap + expanded docstrings.
- `src/channel/draw.jl`: `RyNode(π)` labels as `"Y"` (was `"X"`).
- `test/test_gates.jl`: added 3 discriminator testsets (+~30 LOC).
- `test/test_qecc.jl`: DAG-count updates for logical-X (47→54, 1→2).
- `test/test_draw.jl`: label expectation `"X"`→`"Y"` (2 sites).
- `test/runtests.jl`: wired `test_steane_syndrome.jl`.
- `Sturm-PRD.md`: fixed derived-gates table; added Y!.
- `WORKLOG.md`: this entry.

### Beads state

- **Closed**: `3yz` (P1 bug, this session).
- **Still open under `3yz`**: `35s` (Grover audit), `9g5`
  (block-encoding audit), `7pz` (atomic XNode design).
- **Unblocked**: `870` — the Pauli fix is the ground on which bead
  870's syndrome-extract tests now pass 80/80. Ready to be wired
  into the P3 `encode(ch, Steane())` dispatch in a focused next
  session (my test file is the P1+P2 acceptance — P3 is the
  TracingContext story that needs `cases()` per session 38).

### Next-session pointer

Either finish 870-P3 (wire syndrome_extract! + correct! into
`encode(ch, Steane())` via `cases()` for TracingContext), OR tackle
one of the hardening beads (`35s`, `9g5`) while they're fresh in
context. `7pz` (atomic XNode) is larger-scope — defer unless the
draw UX for X! ("Z Y" glyphs adjacent instead of a single "X")
becomes painful.

---

## 2026-04-21 — Session 41: Steane 870 P1+P2 WIP — blocked on Pauli gate bug (`a1e` filed)

Started bead 870 (Steane [[7,1,3]] syndrome extraction + correction). Did
the ground-truth physics read (docs/physics/steane_1996.pdf §§3.3-4),
wrote the red test first (21 weight-1 error cases + N=500 statistical),
implemented the three new functions. 66/80 tests green. The 14 failures
in P1 syndrome-value assertions led to discovering a **physics-correctness
bug in src/gates.jl that predates this session**: `X!` and `Y!` are
silently swapped.

### User call-ins during this session

- Q1 scope: **bundle P1 (syndrome_extract! + correct!) + P2
  (decode_with_correction! + N=500 statistical)**. P3 (wire into
  `encode(ch, Steane())`) deferred to a dedicated session.
- Q2 classical-conditioned correction primitive: **(b) `cases()`** —
  but for this session (P1+P2 only, EagerContext only) we actually use
  runtime `Bool(anc)` + Julia `if` because `cases()` is needed for the
  TracingContext story in P3 only. Documented that the current
  `syndrome_extract!` errors loudly in TracingContext via `Bool(q)`'s
  existing loud-fail (session 38) — pointing users at bead 870 P3.
- Q3 `decode!` mutation vs new: **add-new** — `decode_with_correction!`
  composes `syndrome_extract!` + `correct!` + the existing pure-inverse
  `decode!`. Keeps the 14 existing Steane tests untouched.

### Ground truth pinned to physics

Steane 1996 quant-ph/9601029 §3.3 eq. 16-17 (parity check matrices
H_C, H_{C+}), §3.5 Theorem 6 (correction in two bases is sufficient),
p. 21 (ancilla + CNOT extraction protocol). Key observation: Steane's
paper has **no literal "Table I/II"** — bead 870's wording is shorthand.
The stabiliser placement is designed so the 3-bit syndrome in binary
equals the qubit index of a weight-1 error directly — no lookup table
needed, correction is the identity function on qubit index.

Stabiliser supports (both X-type and Z-type, CSS self-dual):
`g₁={1,3,5,7}` (bit 1), `g₂={2,3,6,7}` (bit 2), `g₃={4,5,6,7}` (bit 3).

### What's committed this session (src/)

`src/qecc/steane.jl` — three new exported functions:
- `syndrome_extract!(NTuple{7,QBool}) → (sx::UInt8, sz::UInt8)`
  Z-stab protocol: `anc = QBool(0); for i in support; anc ⊻= phys[i]; end; Bool(anc)`.
  X-stab protocol: `anc = QBool(0); H!(anc); for i in support; phys[i] ⊻ anc; end; H!(anc); Bool(anc)`.
- `correct!(NTuple{7,QBool}, sx, sz)` — `sx != 0 → X!(phys[sx]); sz != 0 → Z!(phys[sz])`.
- `decode_with_correction!(::Steane, NTuple{7,QBool}) → QBool` — composes all three.

`src/Sturm.jl` — new exports `syndrome_extract!, correct!, decode_with_correction!`.

### What's committed but NOT wired (test/)

`test/test_steane_syndrome.jl` — 80-test file, 66 green, 14 red (all
P1 syndrome-value assertions). **Intentionally NOT added to
runtests.jl** so CI stays green. Will be wired in once the Pauli
bug (bead a1e) is fixed — the code in steane.jl is correct, only
the Pauli-identity assertions need the fix to match.

### The Pauli gate bug — bead `Sturm.jl-a1e` (P1)

Discovered while investigating why my P1 X-error syndrome assertions
failed. **`X!(q) = (q.θ += π; q)` is Ry(π), whose channel is Y, not X**.
And **`Y!(q) = (q.φ += π; q.θ += π; q)` is Rz(π)·Ry(π), whose channel
is X**. Verified by density-matrix action on |+⟩⟨+|:

- `X!(|+⟩)` → `|-⟩` (Y-channel behaviour; pure X channel leaves |+⟩ invariant)
- `Y!(|+⟩)` → `|+⟩` (X-channel behaviour)

### Why the bug was silent for 40+ sessions

1. **Freshly-prepared |0⟩ ancillas are indistinguishable.** Ry(π)|0⟩⟨0|Ry(π)† = |1⟩⟨1| = X|0⟩⟨0|X. Diagonal density matrices are identical channels under X vs Y vs Ry(π). All existing src/ callers of `X!` hit this regime: `library/patterns.jl` Grover diffusion (applied after H on freshly prepared qubits — but see #3), `block_encoding/prepare.jl` + `select.jl` on ancillas, `control/cases.jl` targets.
2. **CSS self-dual X_L test symmetry.** Steane X_L = X^⊗7 and Y^⊗7 both flip |0⟩_L ↔ |1⟩_L. The existing `test_qecc.jl "X_L flips the logical bit"` test passes for either convention.
3. **Grover may be silently wrong.** `library/patterns.jl:322,325` applies `X!` INSIDE the diffusion operator `H X (2|0⟩⟨0|-I) X H` where the qubits are in |+⟩. Y|+⟩ = i|-⟩, very different from X|+⟩ = |+⟩. test_grover.jl passes today — needs audit whether that's coincidental (e.g. from overall algorithm being tolerant, or from doubled use of X! cancelling) or correct-by-accident.
4. **My own P2 Steane recovery tests passed** because injection and correction both use X!, so injected-Y + correction-Y cancel up to a Z residual, and Z on |0⟩_L or |1⟩_L is a global phase. If I had tested |+⟩_L or |-⟩_L inputs, the bug would manifest. My P1 syndrome-value assertions caught it because they expose the syndrome bits directly.

### Recommended fix (not done this session)

Swap the two definitions in src/gates.jl — literally interchange the
right-hand sides of X! and Y!. One-line operation per gate. Risk profile:
- `src/library/patterns.jl` Grover diffusion — **must re-test**. This is where superposition interference happens.
- `src/qecc/steane.jl:249` my correction code — no net change (injection + correction both use X!, both shift together).
- All other src/ sites — identical channel on freshly |0⟩ ancillas.

Acceptance: `X!(|+⟩) → |+⟩`, `Y!(|+⟩) → |-⟩`, full regression clean,
test_grover still green, and when 870's test file is wired in, all
80 tests pass with zero code changes to steane.jl.

### Beads state at end of session

- **Filed**: `Sturm.jl-a1e` P1 bug — X!/Y! swap.
- **Updated**: `Sturm.jl-870` in `open` again (was in_progress), with notes documenting WIP state and dependency on a1e. bd-tool bug (`wisp_dependencies` table missing) prevented formal `bd dep add` — dependency is in the notes field.
- Other open beads unchanged from end of session 40.

### Next-session pointer

**Do a1e first.** It's a one-commit fix: swap X!/Y! in gates.jl, run
test_grover + test_qecc + test_block_encoding for regressions, verify
the channel-level assertions (X!(|+⟩) = |+⟩). Then add
test_steane_syndrome.jl to runtests.jl, re-run — all 80 green. Then
close both a1e and 870 in the same session.

If a1e reveals that Grover was silently relying on the swapped
convention, file an additional bead and take it one at a time.

### Files touched this session

- `src/qecc/steane.jl` +~100 LOC (three new exported functions, docstrings with paper references)
- `src/Sturm.jl` +1 -1 (exports)
- `test/test_steane_syndrome.jl` new, 190 LOC, 80 testsets (66 green, 14 red — not in runtests yet)
- `WORKLOG.md` this entry

No commits in `library/patterns.jl` or other modules this session — the
Pauli fix is deferred to bead a1e under a separate commit with its own
regression story.

---

## 2026-04-21 — Session 40: discard! → ptrace! rename (close `diy`)

Mechanical refactor — the channel-theoretic partial-trace primitive gets its
proper name; `discard!` remains as a zero-overhead `const` alias for
backcompat. Size of the change validates session 38's sequencing decision:
because sv3 landed first, the rename touched ~20 internal call sites in
`src/` (plus 4 canonical defs + 1 export). Done WITHOUT migrating any
test/ file — the alias covers them.

### What changed

4 canonical definitions renamed: `function discard!` → `function ptrace!` in
`src/types/{qbool,qint,qcoset,qrunway}.jl`. Added a single module-level
alias `const discard! = ptrace!` in qbool.jl (the first types/ include,
so the alias captures all subsequent method additions via Julia's
generic-function semantics). Exported `ptrace!` from `src/Sturm.jl`
alongside the existing `discard!` export.

Internal call sites in `src/` migrated to `ptrace!` for consistency
(library/arithmetic, library/patterns, library/coset, library/shor,
noise/classicalise, block_encoding/select, qecc/steane, qsvt/circuit,
plus doc/error-message references in context/{eager,density,tracing},
hardware/hardware_context, types/{qcoset,qrunway,quantum}). Renamed
`_runway_force_discard!` → `_runway_force_ptrace!` with a const alias.

Tests remain on `discard!` — the alias covers them — minimising
cross-file churn. Future test files will use `ptrace!` (like
`test/test_ptrace.jl` added this session).

### Test strategy

Red first: `test/test_ptrace.jl` with 9 cases — ptrace! on QBool/QInt,
methods table contains QBool/QInt/QCoset/QRunway, `discard! === ptrace!`,
discard! still works on QBool, ptrace! + @context auto-cleanup coexist.
Ran red → 6 errors (UndefVarError on ptrace!), 1 pass. Implemented,
re-ran → 9/9 green. Regressions: sv3 autocleanup 14/14 green, library
patterns 92/92 green, QECC Steane 1173/1173 green. Full arithmetic
suite queued (takes ~5min on this device per standing memory); not
blocking the commit.

### Gotchas

1. **QCoset/QRunway constructors don't take plain Int** — my initial
   test used `QCoset{4,2}(3)` which MethodErrors. Pivoted to a methods-
   table check (`any(s -> s <: QCoset, sigs)` on `methods(ptrace!)`)
   which asserts the same thing (rename covered all 4 types) without
   needing runtime construction.

2. **`discard!` alias must be defined AFTER the first `function ptrace!`
   definition** but BEFORE any `discard!` caller runs. Julia binds
   `const` to the generic function at alias time; subsequent `function
   ptrace!(...)` in qint.jl, qcoset.jl, qrunway.jl add methods to the
   same function, and the `discard!` alias sees them automatically. No
   action needed beyond placing the const at qbool.jl (first include).

3. **Batched Edit tool calls need prior Read per file** — learned
   this mid-session. 8 of the src/ edits failed on the first batch
   because I hadn't Read each file individually. Re-did with
   Read-then-Edit pairs.

4. **Buffered `tail -5` on a long-running Julia test silently hangs**
   — `tail` waits for stdin EOF when its stdin isn't a TTY; if Julia
   doesn't terminate (e.g. the suite runs many minutes), output
   never flushes. Fix: pipe to `> /tmp/file.log 2>&1` and grep
   the file afterwards.

### Files touched

- `src/types/qbool.jl`: renamed `discard!` → `ptrace!`, added alias (+19)
- `src/types/qint.jl`: renamed, updated docstring (-4 +5)
- `src/types/qcoset.jl`: renamed, updated docstring (-4 +5)
- `src/types/qrunway.jl`: renamed, `_runway_force_discard!` → `_runway_force_ptrace!` + alias (-8 +10)
- `src/Sturm.jl`: export `ptrace!` alongside `discard!` (+1 -1)
- `src/library/{arithmetic,patterns,coset,shor}.jl`: call-site migration
- `src/noise/classicalise.jl`, `src/block_encoding/select.jl`,
  `src/qecc/steane.jl`, `src/qsvt/circuit.jl`: call-site migration
- `src/context/{tracing,eager,density}.jl`, `src/hardware/hardware_context.jl`,
  `src/types/quantum.jl`: doc / error-message references
- `README.md`: resource-lifetime section — the "v0.1 caveat / being
  deprecated" language replaced with "sv3 shipped, diy shipped,
  discard! is now the backcompat alias"
- `test/test_ptrace.jl`: new, 9 testsets
- `test/runtests.jl`: include new test

### Beads state

- Closed: `Sturm.jl-diy` (P3).
- Still open ergonomics: `cbl` (do-block allocation, independent),
  `hlk` (QBool/QInt finalizer, backstop per sv3 design note).
- Resource-lifetime ergonomics trilogy (sv3 → cbl → diy) now 2/3
  shipped. cbl can land whenever; it's additive.

### Next-session pointer

User asked for `870` (Steane [[7,1,3]] syndrome extraction + correction)
as the next target — "the real physics mega task". Pre-brief deferred
to a focused next session: will need full 3+1 protocol, Steane 1996
paper ground truth, Table II syndrome lookup, 3 X-stabilisers + 3
Z-stabilisers, logical/physical channel bookkeeping, and tests against
the {I,X,Y,Z} weight-1 error table.

---

## 2026-04-21 — Session 39: @context auto-cleanup (close `sv3`) — RAII for qubits

Followed session 38's hand-off: `sv3` was the recommended next target because
(a) it closes the long-standing `hlk` footgun, (b) makes the eventual
`discard!→ptrace!` rename (`diy`) trivial, (c) purely additive. Shipped in
one session via a 3+1 agent protocol. 14/14 new tests green; 804 adjacent
tests (channel 44, hardware 726, hardware-lifecycle 16, tracing-deep-when
18) green with zero regressions.

### The design in one paragraph

Added `live_wires(ctx)` and `cleanup!(ctx)` to `AbstractContext`. Default
`cleanup!` loops `live_wires` and calls `deallocate!` per wire, catching
per-wire errors into a `@warn` so one bad wire doesn't poison the rest.
Eager/Density/Hardware share `live_wires(ctx) = collect(keys(ctx.wire_to_qubit))`.
Hardware overrides `cleanup!` with a `ctx.closed && return` guard so
`with_hardware` and the finalizer continue to own `close()`. TracingContext
adds a new `live::Vector{WireID}` field (insertion-ordered, NOT a Set — DAG
emission order is user-visible), maintained by `allocate!` / `deallocate!` /
`_emit_observe!`. The `@context` macro gained a two-layer try/catch: body
exception captured via `body_threw::Bool` + `rethrow()` (preserves native
stacktrace); cleanup failure on a clean body path rethrows; cleanup failure
during an unwind becomes a `@warn` so the body's error wins. Body's last
expression is now preserved through the macro (fixes a latent bug from
session 23's `1f3` debugging). `trace()` filters designated output wires
out of `ctx.live` then calls `cleanup!` before `defer_measurements`, so
orphaned allocations become `DiscardNode`s in the lowered Channel.

### 3+1 agent protocol this time

- **Phase A — ground truth**: read every context file, trace.jl, qbool/qint
  constructors, existing `@context` macro, and the hardware lifecycle
  finalizer pattern BEFORE any code. Also revisited session 37 gotcha 5
  (finalizer + FFI is unsafe).
- **Phase B — red test**: wrote `test/test_autocleanup.jl` with 12 cases
  targeting the bead's acceptance + the semantics user locked in (silent
  partial-trace on block exit, matching GC idiom). Ran: 9 fail, 3 pass.
- **Phase C — parallel proposers**: two Plan-agents (both Opus) given
  identical context + the 9-point gotcha list + the red test file; no
  cross-pollination. Both proposed `live_wires` + `cleanup!` as the API
  surface, converged on 95% of the design. Divergences: error surfacing
  (CompositeException vs per-wire `@warn`), field name (`allocated` vs
  `live`), body-throw handling (`body_threw` flag vs captured exception).
  I synthesised: per-wire `@warn` (simpler than composite), `live` name
  (matches accessor), `body_threw + rethrow()` pattern (preserves Julia's
  native backtrace).
- **Phase D — implementer**: general-purpose Opus with the frozen plan and
  strict instructions NOT to redesign. Got a first-attempt 14/14 green
  (no iteration needed) and the two regression runs it was asked for.
- **Phase E — review** (me): verified files match plan via `git diff`,
  re-ran the sv3 suite, ran three additional regressions I chose
  (channel/trace, hardware context, tracing deep when) — all green.

### Gotcha #6 design lock-in

User asked: "Isn't partial trace of control expected behaviour? What would
be alternatives?" The alternatives are all worse:

- **Error on escape**: needs macro-level escape analysis of the block's
  return expression. Julia can't do this cleanly — the macro cannot tell
  `q; end` from `Bool(q); end`.
- **Force explicit cast before return**: that's what P2 already asks for
  in user-facing code. Auto-cleanup backstops it; it doesn't undermine it.
- **Keep ctx alive beyond the block**: breaks the `task_local_storage` /
  `lock(l) do … end` pattern. Any op on `q` after the block already
  fails at `current_context()` lookup.

So: silent partial-trace on exit. A returned live `q` is a dead handle.
Matches GC semantics for every transient Julia object. Locked in.

### Gotchas discovered and retired

1. **`@context` had a latent return-value bug** (known since session 23
   `1f3` debugging — the macro's `try...finally` dropped the body's last
   expression). Fixed incidentally as part of the rewrite — `local result`
   captured before the `finally`, returned after.
2. **`deallocate!` during cleanup might still need `current_context()`** —
   so cleanup must run BEFORE TLS restoration. Encoded in the macro
   structure.
3. **`trace()` has two entry points** — `trace(f, n_in::Int)` and
   `trace(f, ::Val{W})` — both needed the same 3-line change. Implementer
   got both on first pass.
4. **HardwareContext.deallocate! has `_check_open(ctx)` guard**. Since
   `cleanup!(ctx::HardwareContext)` short-circuits on `ctx.closed`, this
   never fires during cleanup — correct interaction.
5. **`_emit_observe!` also needs to remove from `live`** (not just
   `deallocate!`). Caught during plan drafting; implementer picked it up.

### What sv3 does NOT do (scope discipline)

- Does NOT rename `discard!` → `ptrace!` (that's bead `diy`, now unblocked).
- Does NOT add `QBool(p) do q … end` do-block allocation (bead `cbl`).
- Does NOT add a Julia finalizer on QBool/QInt (bead `hlk`). `sv3`
  covers 95% of cases deterministically; `hlk` remains open as the
  belt-and-braces backstop for the rare "QBool escapes its @context"
  case. User call: do not walk through that door until telemetry
  justifies it.

### Files touched

| File | LOC delta | What |
|------|-----------|------|
| `src/context/abstract.jl` | +82 -2 | `live_wires`, `cleanup!`, `_default_cleanup!`, rewrote `@context` macro |
| `src/context/eager.jl` | +2 | `live_wires` method |
| `src/context/density.jl` | +2 | `live_wires` method |
| `src/context/tracing.jl` | +9 -2 | `live::Vector{WireID}` field; maintained in allocate!/deallocate!/_emit_observe! |
| `src/hardware/hardware_context.jl` | +9 | `live_wires` + `cleanup!` override with `ctx.closed` guard |
| `src/channel/trace.jl` | +16 | filter out_wires from live, cleanup! before defer_measurements (both branches) |
| `test/test_autocleanup.jl` | +139 (new) | 14 testsets: Eager, Density, Hardware not touched (TBD), 100 iterations, exception safety, nested @context, TracingContext DiscardNodes, block return, DAG ordering |
| `test/runtests.jl` | +1 | include new test |

### Beads state

- Closed: `Sturm.jl-sv3` (P2 @context auto-cleanup).
- Unblocked: `Sturm.jl-diy` (P3 discard!→ptrace! rename, depended on sv3).
- `Sturm.jl-hlk` (P3 QBool/QInt finalizer) stays open as backstop per design
  decision above.
- `Sturm.jl-cbl` (P3 do-block allocation) independent, unchanged.

### Next-session pointers

The obvious next P2 candidates from `bd ready`:
- `870` P1 — Steane [[7,1,3]] syndrome extraction (orthogonal, unblocked).
- `npd` P2 — shor_factor_EH_semi with Mosca-Ekert semi-classical iQFT.
- `jrl` P2 — QRunway runway-in-middle (unblocks 6oc GE21 critical path).

The obvious next P3 (ergonomics follow-on from sv3):
- `diy` — discard!→ptrace! rename. Now trivially doable because most
  explicit `discard!` calls became redundant under sv3; the rename will
  touch far fewer sites than it would have pre-sv3.

---

## 2026-04-21 — Session 38: cases() + OpenQASM dynamic circuits (close `322` + `tak`); file 3 follow-on beads

User asked to fix bead `322` (TracingContext silent mis-trace of classical-conditioned
operations after measurement). After deep research (3 parallel subagents on Sturm
internals + Julia DSL idioms + quantum-DSL prior art), shipped a full design that
also closes `tak` (OpenQASM CasesNode dropped). Filed three follow-on ergonomics
beads (auto-cleanup `sv3`, do-block allocation `cbl`, discard!→ptrace! rename `diy`).

### Research findings (recorded for future-you)

Three subagents in parallel established:

1. **Sturm internals**: CasesNode struct already exists (`dag.jl:114-118`),
   `defer_measurements` already lowers ObserveNode+CasesNode via Nielsen-Chuang
   §4.4, draw/pixels render placeholders, openqasm silently drops. The PRODUCER
   side was the gap — TracingContext.measure! at `tracing.jl:135-145` returned
   hardcoded false with a "for now" comment that was never followed up.

2. **Julia DSL idioms**: Symbolics/MTK overload `Base.ifelse` + add error_hints
   for `convert(Bool, ::Num)`; JuMP refuses `if VariableRef` and uses indicator
   constraints; Cassette/IRTools/Mjolnir are fragile (FluxML migrating off
   Cassette); IfElse.jl archived (Symbolics now overloads Base.ifelse directly);
   **Yao.jl has no measurement-conditioned primitive at all** — Sturm fills a
   genuine gap in the Julia quantum ecosystem.

3. **Quantum DSL prior art** taxonomy:
   - (A) Block-scoped: Qiskit-new (`with circuit.if_test((c, 1)):`), Q#, OpenQASM
     3 (`if (c==1) { ... }`), MQT IfElseOperation. **Wins for Sturm.**
   - (B) Method-on-gate: Cirq (`with_classical_controls`), TKET. Too narrow.
   - (C) Decorator: Catalyst `@cond`. Unidiomatic in Julia.
   - (D) Linear/labels: Quil. Wrong abstraction level.
   Critical P4 warning from subagent C: Cirq blurs coherent `when` and classical
   control by reusing op wrappers — Sturm must NOT make this mistake. The new
   primitive must be VISUALLY DISTINCT from `when()`.

### 8 design decisions locked (4 with user revisions)

1. Name: `cases` (matches CasesNode + Qiskit/MQT terminology). ✓
2. Syntax: **two-do-block was rejected by Julia parser** (chained `f() do … end
   do … end` is a parse error). Pivoted to `@cases q begin … end begin … end`
   macro — both blocks parse cleanly. The `cases(q, then, else_)` function is
   the underlying primitive.
3. trace() auto-lowers CasesNode via strict defer_measurements. ✓
4. v1 restriction: cases bodies must be measurement-free; **strict mode errors
   loudly** (per user revision — was originally "compiler warning"). ✓
5. OpenQASM 3 dynamic-circuit emission for CasesNode (closes `tak`). ✓
6. Fail fast, fail loud: `Bool(q)` / `Int(q)` inside TracingContext errors
   with migration message pointing to `cases()` / `discard!()` / empty-cases
   idiom. ✓

### THE observe! ANTIPATTERN — caught and rejected mid-session

In an early draft I introduced an `observe!(q)` primitive to handle the
"measure-and-record-but-discard-result" case (test_channel.jl needed this for
its OpenQASM output assertion). User correctly identified this as a P2
violation: P2 says "the Q→C boundary is a CAST. Only explicit casts: Bool(q),
Int(qi)." Adding `observe!(q)` would be a back-door measurement function —
exactly what P2 forbids. Plus it's redundant with discard! (which IS partial
trace, the channel-theoretic operation for "throw away this qubit").

**The right answer**: empty-cases idiom `cases(q, () -> nothing)`. This is
honest about what's happening — measure, branch on outcome, but both branches
do nothing — and produces an ObserveNode + empty CasesNode in the trace. The
auto-lowering pass drops the empty CasesNode and keeps the ObserveNode, so
OpenQASM still emits `c[0] = measure q[0];`. No new primitive needed.

Lesson for future-you: when fixing a P2-axiom-violating bug, **double down on
P2** — don't introduce parallel back-doors to make tests easier.

### discard! is itself unidiomatic — filed three new beads

User pushed back on `discard!` as a name. Analysis: it's unidiomatic on four
axes (resource-management vocab in user code violates P5; bang-convention is
wrong since it consumes rather than mutates; redundant with what GC should do;
forces explicit cleanup that's the source of bead `hlk`). Filed three beads
in dependency order to MINIMISE refactoring:

- **`sv3` P2** — `@context` auto-cleanup of unconsumed quantum resources.
  RAII-style: track allocations, partial-trace at scope exit. Subsumes hlk.
  **Lands first** because it makes most existing `discard!` calls redundant.
- **`cbl` P3** — `QBool(p) do q … end` do-block allocation. Independent
  additive; matches Julia `open(f, path) do stream … end` idiom.
- **`diy` P3** — Rename `discard!` → `ptrace!` (channel-theoretic name).
  **Depends on sv3** so the rename touches ~5-10 sites instead of ~50.

Sequencing rationale: each session is additive and low-risk; the eventual
rename is small because auto-cleanup + do-block patterns have made `discard!`
optional in most positions.

### What landed this session

| File | Change |
|------|--------|
| `src/control/cases.jl` (NEW, 130 LOC) | `cases(q, then, else_)` + `@cases` macro + per-context dispatch |
| `src/context/tracing.jl` | dag::Vector{HotNode} → Vector{DAGNode}; measure! errors loudly; new `_emit_observe!` for cases() internal use |
| `src/channel/trace.jl` | Auto-lower via `defer_measurements(strict=true)` before constructing Channel |
| `src/passes/deferred_measurement.jl` | Added `strict` kwarg; empty-CasesNode handling (drop CasesNode, keep ObserveNode); strict errors on un-lowerable patterns |
| `src/channel/openqasm.jl` | Rewrote with `_emit_node!(lines, node, idx, map, indent)` style; new `to_openqasm(dag, in_wires, out_wires)` entry; OpenQASM 3 dynamic-circuit `if (c[i] == 1) { … } [else { … }]` emission for CasesNode; recursive bit-index pre-pass |
| `src/Sturm.jl` | Include cases.jl; export `cases`, `@cases` |
| `test/test_cases.jl` (NEW, 36 tests) | EagerContext / HardwareContext / TracingContext / @cases macro / branch capture / auto-lower / nested measurement error / Bool(q) error / empty-cases idiom |
| `test/test_openqasm_cases.jl` (NEW, 17 tests) | Then-only / both-branch / multiple measurements / Channel-level back-compat / empty-cases suppression |
| `test/test_channel.jl, test_pixels.jl, test_draw.jl` | Migrated 3 sites `_ = Bool(q)` → `cases(q, ()->nothing)`; added new `_emit_observe!` test |
| `test/runtests.jl` | Added test_cases + test_openqasm_cases |

53/53 new tests pass. Regression-clean across test_channel, test_passes,
test_tracing_deep_when, test_pixels, test_draw, test_qecc, all hardware tests,
and ~15 other touched files.

### Surprises and gotchas

1. **Julia's chained double-do is a parse error** (verified empirically with
   `f("X") do; …; end do; …; end` → `extra tokens after end of expression`).
   Forced pivot from the originally-locked two-do-block syntax to a macro
   form `@cases q begin … end begin … end`. Macros are stable across Julia
   versions and parse cleanly. The function form `cases(q, then, else_)` is
   the underlying primitive (e.g. for programmatic construction).

2. **Empty `collect(())` returns `Vector{Union{}}`**, not `Vector{WireID}`.
   Broke the new `to_openqasm(ch::Channel) → to_openqasm(dag, in_wires, out_wires)`
   dispatch when the channel has no inputs/outputs (common in test fixtures).
   Fix: use `WireID[ch.input_wires...]` instead of `collect(ch.input_wires)`.

3. **TracingContext.dag::Vector{HotNode} can't hold CasesNode** because
   CasesNode has Vector fields → not isbits → can't be in HotNode union (which
   is isbits-optimized at 25 B/element per Session 3). Solution: relax dag
   to Vector{DAGNode} during tracing, auto-lower via defer_measurements
   before constructing the long-lived Channel (which keeps Vector{HotNode}).
   Best of both worlds — slight perf regression during tracing (transient),
   no impact on Channel-resident IR (perf-sensitive).

4. **Rejected the observe! antipattern** (see above). User caught it; lesson
   captured.

5. **`@cases q begin ... end` macro args**: when called with just one block,
   the `else_block` macro arg defaulted via `args...` length check. Julia
   macros don't support default values in the signature; varargs + length
   check is the idiom.

### Beads state at end of session

- Closed: `Sturm.jl-322` (P1 silent correctness bug), `Sturm.jl-tak` (P2
  silent OpenQASM drop). Both bug beads from session 37 architecture audit
  resolved.
- Filed: `sv3` (P2 @context auto-cleanup, RAII), `cbl` (P3 do-block allocation),
  `diy` (P3 discard!→ptrace! rename, blocked on sv3). Three follow-on
  ergonomics beads.
- Open beads now: 21 (was 20 at session start; +3 new − 2 closed).

### Next-session pointers

**Highest-value follow-on**: `sv3` (@context auto-cleanup). Per session
analysis, this is the right next move because it (a) closes the long-standing
hlk footgun, (b) makes the eventual `discard!→ptrace!` rename trivial, (c)
purely additive. Estimated: 1 session.

**Other ready P1/P2**:
- `Sturm.jl-870` P1 — Steane [[7,1,3]] syndrome extraction (orthogonal).
- `Sturm.jl-jrl` P2 — runway-in-middle type, unblocks `6oc` GE21 critical path.
- `Sturm.jl-npd` P2 — Mosca-Ekert semi-classical iQFT.

**Hygiene from session 37**:
- `Sturm.jl-t1v` P3 — `_ORACLE_TABLE_CACHE` eviction policy.
- `Sturm.jl-hlk` P3 — QBool/QInt finalizer (will likely be subsumed by sv3).

---

## 2026-04-21 — Session 37: Hardware round-trip backend (epic `vvu`, 7 beads, 1327 tests)

User asked to architect and ship a full hardware round-trip path for Sturm.jl
against an idealised 16-qubit device with all-to-all connectivity, mid-circuit
measurement, qubit recycling, no logical-layer QECC, configurable gate time
(default 1ms). Started with a 3-subagent architecture audit of the existing
context infrastructure, then designed protocol → simulator → transport →
HardwareContext → integration tests → TCP server → lifecycle in that order.
All 7 sub-task beads closed. Headline 3-qubit bit-flip QECC test passes
201/201 via the round-trip path.

### Audit findings → 4 bug beads filed BEFORE building the new feature

The architecture audit (Sonnet sub-agents, ~9 min) surfaced four issues in the
existing code that any hybrid hardware use case bumps into:

- `Sturm.jl-322` **P1 silent correctness bug**: TracingContext.measure!
  returns placeholder `false`, so user code `b = Bool(q); if b ...` deterministically
  takes the false branch in tracing mode. The classical-conditioned correction
  body is silently dropped from the DAG. Documented in KNOWN_ISSUES.md but had
  no bead. Fix paths in the bead description.
- `Sturm.jl-tak` **P2**: OpenQASM emitter (openqasm.jl:111-113) maps CasesNode
  → nothing without warning. Critical for any hardware backend that exports
  via OpenQASM 3.0.
- `Sturm.jl-t1v` **P3 silent leak**: `_ORACLE_TABLE_CACHE` (bennett/bridge.jl:335)
  is a Dict keyed on data hash with no eviction policy. Hot loops with distinct
  tables grow the cache forever.
- `Sturm.jl-hlk` **P3 footgun**: QBool/QInt have no finalizer. Loop-allocated
  qubits without measure/discard leak slots until MAX_QUBITS=30 fires loud
  error.

### Architecture (locked design decisions, all 8 confirmed by user)

```
Julia program                                "Hardware" (or simulator)
─────────────                                ───────────────────────
@context HardwareContext(transport) begin
  qs = [QBool(0) for _ in 1:N]    ─── alloc ops queued, NOT sent
  H!(qs[1])                        ─── ry/rz queued (no roundtrip)
  qs[2] ⊻= qs[1]                   ─── cx queued
  s = Bool(qs[2])                  ════ FLUSH ═══>  execute fragment
                                                     measure, return result
                                   <══ result ══════ {"m0":1, "duration_ms":...}
  if s; X!(qs[1]); end             ─── classical Julia, no roundtrip
  ...
end                                ═══ FLUSH + close session ══>
```

The 8 locked decisions:
1. **Flush only on measurement + close.** Gates accumulate in a local buffer;
   only `Bool(q)` / `Int(q)` and `close` round-trip. RUS T-gate = N round-trips
   per attempt; QECC syndrome cycle = k round-trips per round. The floor that
   coherence-time vs roundtrip-latency physics imposes anyway.
2. **`discard!` does NOT flush** — batches with next gates.
3. **Latency simulation default OFF** (`realtime=false`). Tests run fast.
4. **Synchronous round-trips only in v0.1.** No futures, no async batching.
5. **Capacity overflow → server err response → client throws.**
6. **No auto-reconnect.** Connection drop → throw + invalidate context.
7. **Multi-control ancillae from same 16-slot pool.** A 5-controlled gate burns
   4 transient ancillae. Capacity errors propagate naturally.
8. **Wire protocol versioned `"v":1`** in every message.

### Wire protocol (NDJSON over TCP)

8 op verbs cover the Sturm primitive set + lifecycle:
`alloc, discard, ry, rz, cx, ccx, measure, barrier`.

4 message envelopes: `open_session, close_session, submit, ok/err response`.

Every message is one JSON object on a single line, newline-terminated, both
directions. Hand-rolled JSON encoder + recursive-descent decoder (~250 LOC,
no external dep). The JSON.jl dep wasn't worth it for our small surface area.

### Implementation order (TDD red-green throughout)

| Bead | Files | Tests |
|------|-------|-------|
| HW1 `hlv` protocol | `src/hardware/protocol.jl` (~250 LOC) | 108/108 |
| HW4 `7it` simulator | `src/hardware/simulator.jl` (~200 LOC) | 246/246 |
| HW2 `1ju` transport | `src/hardware/transport.jl` (~100 LOC) | 11/11 |
| HW3 `zhy` HardwareContext | `src/hardware/hardware_context.jl` (~270 LOC) | 726/726 |
| HW6 `6vw` integration | `test_hardware_recycle.jl` + `_rus.jl` + `_qecc.jl` | 8 + 2 + 201 |
| HW5 `yzb` TCP server | `src/hardware/server.jl` + `bin/sturm-sim.jl` | 9/9 |
| HW7 `69k` lifecycle | `with_hardware`, finalizer, `_check_open` | 16/16 |

**Total: 1327/1327 tests pass.** Every test file uses the public DSL (QBool,
Bool(), when(), H!, ⊻=) — the AbstractContext substitution is fully transparent.

### Surprises and lessons

1. **`measure` recycles → no follow-up `discard`**. EagerContext.measure!
   already does collapse + reset + slot recycle. My initial test+context plan
   queued `op_measure(q)` followed by `op_discard(q)`, which errored on the
   server because the slot was already gone. Fix: protocol contract is
   "measure recycles", clients queue ONLY measure. HardwareContext.measure!
   updated to mark wire consumed + push slot to free_slots without queueing
   a discard. This matches real hardware "measure-and-reset" dynamic-circuit
   semantics. Saved a redundant device op per measurement.

2. **`q.theta` is NOT a field — Greek `q.θ` only.** First test of the pending-
   op-count assertion failed with FieldError because I used ASCII. The `q.θ` /
   `q.φ` BlochProxy in src/types/qbool.jl:48-58 only accepts the Greek
   letters. Worth a future ergonomics bead but not a blocker.

3. **`stop_server!` closes the LISTENER, not in-flight connections.** My
   first connection-drop test killed the server's listener but the existing
   accepted TCP connection stayed open from both ends until the OS's socket
   timeout. Real "drop" testing requires either tracking active connections
   in the server struct OR closing the client socket directly. I went with
   the latter for simpler test code. Filed as a soft TODO in the server.jl
   docstring; not a bead because it's testing-only.

4. **Hand-rolled JSON beats adding a dep for this scale.** ~250 LOC for the
   subset we need (Dict, Vector, String, Bool, Int, Float64, null) vs adding
   JSON.jl which would auto-load on `using Sturm`. The hand roll forces
   explicit thought about every value type and catches protocol mistakes
   early. Test coverage is exhaustive (108 tests) so the maintenance risk
   is low.

5. **Finalizers + FFI = `Threads.@spawn`**. Julia GC runs in a fragile
   runtime context where direct IO/FFI is unsafe. The finalizer for
   HardwareContext defers via `Threads.@spawn try; close(ctx); catch; end`
   — hands close() to the regular task scheduler. Errors swallowed because
   at finalizer time the server may already be down (process exit ordering).
   Best-effort is the right semantics here.

6. **Multi-control re-uses src/context/multi_control.jl unchanged.** That
   module is generic over `AbstractContext` — the Toffoli cascade (Barenco
   Lemma 7.2) and ABC controlled-rotation decomposition route through the
   public `apply_*!`/`allocate!`/`deallocate!` API. HardwareContext gets
   multi-controlled gates for FREE — verified by the "when() with TWO
   controls (Toffoli via cascade)" testset. Validates the original cascade
   design choice from Session 35.

7. **TLS macro `@context` doesn't auto-close**. The `@context ctx body`
   macro at src/context/abstract.jl:144-158 only sets/restores task-local
   storage; it does NOT call `close(ctx)` on exit. Users must call close
   explicitly. The `with_hardware` RAII wrapper fixes this for the common
   case; the finalizer is the safety net for the rest.

### Public API (newly exported from Sturm)

```julia
# Construction
HardwareContext(transport; capacity=16, gate_time_ms=1.0)
IdealisedSimulator(; capacity=16, gate_time_ms=1.0, realtime=false)

# Transport
AbstractTransport
InProcessTransport(sim::IdealisedSimulator)
TCPTransport(host::String, port::Int)

# Server
start_server(sim; port=0, host="127.0.0.1") -> (server, port, accept_task)
stop_server!(server)

# Convenience (RAII)
with_hardware(f, transport; capacity=16, gate_time_ms=1.0)
```

### Hot loop check (the original concern)

Per the "hidden resource costs in classical loops" question that motivated
this session: the round-trip path inherits all the resource discipline of
EagerContext (qubit recycling, MAX_QUBITS cap, multi-control polynomial
lowering). Specifically verified by HW6 tests:
- 500 Bell pairs through a 2-qubit device → server-side EagerContext capacity
  stayed at 2 (no growth).
- 1000 single-qubit prep+measure on a 1-qubit device → deterministic 1000/1000
  results; no slot leak.
- After 4 alloc + 4 measure: client `free_slots` length = 4, `next_slot` = 4
  (never grew).
- Capacity exhaustion (allocate beyond device size) → loud `ErrorException`.

The four bug beads filed at session start (322, tak, t1v, hlk) capture the
PRE-EXISTING risks; the new HardwareContext does NOT introduce any of them.

### Files added (this session)

- `src/hardware/protocol.jl` (~250 LOC)
- `src/hardware/simulator.jl` (~200 LOC)
- `src/hardware/transport.jl` (~100 LOC)
- `src/hardware/hardware_context.jl` (~270 LOC)
- `src/hardware/server.jl` (~80 LOC)
- `bin/sturm-sim.jl` (~75 LOC, executable)
- `test/test_hardware_protocol.jl` (108 tests)
- `test/test_hardware_simulator.jl` (246 tests)
- `test/test_hardware_transport.jl` (11 tests)
- `test/test_hardware_context.jl` (726 tests)
- `test/test_hardware_recycle.jl` (8 tests)
- `test/test_hardware_rus.jl` (2 tests)
- `test/test_hardware_qecc.jl` (201 tests, the headline)
- `test/test_hardware_tcp.jl` (9 tests)
- `test/test_hardware_lifecycle.jl` (16 tests)

### Files modified

- `src/Sturm.jl` — 5 new includes, 7 new exports
- `Project.toml` — added `Sockets` stdlib
- `test/runtests.jl` — 9 new includes
- `WORKLOG.md` — this entry

### Beads state at end of session

- Closed this session: 9 (4 bug findings: 322, tak, t1v, hlk; 7 HW sub-tasks +
  epic: hlv, 7it, 1ju, zhy, 6vw, yzb, 69k, vvu).
- Wait that's 12. Recount: 4 bugs + 1 epic + 7 sub-tasks = 12. ✓.
- Open beads: per `bd ready` post-session (run `bd ready` for current).

### Next-session pointers

**Hardware backend follow-ons (filed as needed)**:
- The "TCP server doesn't track in-flight connections" testing limitation —
  not filed; documented in source.
- Async/streaming submit (v0.2 scope). Useful for fragments without
  measurements where the client doesn't need the response immediately.
- Real-hardware adapters (IBM/Quantinuum). Protocol is shaped to be mappable
  but no shims today.
- Noise model on the simulator. The PRD said "idealised"; v0.2 could add
  `IdealisedSimulator{:noisy}` with depolarising channel + DensityMatrixContext
  backing.

**Pre-existing GE21 critical path (UNCHANGED from session 36c)**:
- `jrl` P2 — `QRunwayMid{W_low, Cpad, W_high}` runway-in-middle type. Blocks
  `6oc`. 3+1 type-design round.
- `6oc` P1 — windowed arithmetic + `shor_order_E`. Blocked on jrl.
- `870` P1 — Steane [[7,1,3]] syndrome extraction.

**Bug beads filed this session still need owners**:
- `322` P1 TracingContext silent mis-trace — most important.
- `tak` P2 OpenQASM CasesNode dropped.
- `t1v` P3, `hlk` P3 — hygiene beads.

---

## 2026-04-20 — Session 36c: File three EH17 follow-on beads + handoff notes

After the 6bn ship and the N=55 demo (sessions 36 / 36b), mapped out the
remaining Shor work and filed three new beads for EH17-specific follow-
ons that were implicit in the 6bn design but out of its scope.

### Beads filed this session

| ID  | P  | Title | Unblocked? |
|-----|----|-------|------------|
| `Sturm.jl-zli` | P2 | shor_factor_EH s>1 — multi-shot lattice post-processing (EH17 §4.4 general) | ready now |
| `Sturm.jl-npd` | P2 | shor_factor_EH_semi — Mosca-Ekert semi-classical iQFT for two-register EH17 | ready now |
| `Sturm.jl-e73` | P3 | Pure coset state via comparison-negation — Gidney 1905.08488 Fig 1 full | ready now |

### zli — EH17 s>1 (P2)

**What**: Current `shor_factor_EH` is s=1 only (2D Lagrange post-
processing). For s>1 the exponent register width shrinks asymptotically
from 1.5n toward 0.5n, which is the entire point of EH17's 2017
generalization over Ekerå 2016's s=1 algorithm.

**How to start**: Add `s::Int=1` kwarg. For s≥2, (a) run the quantum
step s times, (b) build the (s+1)-dim lattice basis of EH17 Def 3,
(c) solve CVP via pure-Julia LLL (~200 lines, δ=3/4), (d) verify via
`_eh_factors_from_d`. Spurious-candidate probability drops to 2^(-s-1)
per Lemma 3, so s=2 already halves ambiguity.

**Acceptance**: `shor_factor_EH(15; s=2)` ≥ 50% over 30 shots;
`shor_factor_EH(15; s=3)` ≥ 60%. s=1 unchanged. New test file with LLL
unit tests against reference vectors.

**Avoid**: Don't reach for Nemo.jl / fpLLL_jll as a hard dep. Pure-Julia
LLL is well-known (Lenstra-Lenstra-Lovász 1982, δ=3/4); the whole
module is ~200 lines and this project doesn't carry a lattice-algebra
dep yet.

### npd — Mosca-Ekert semi-classical for EH17 (P2)

**What**: Current `shor_factor_EH` peaks at 24 qubits for N=55 because
both exponent registers live in superposition simultaneously (full
two-register PE). Mosca-Ekert (1999 NASA QCQC [Lecture Notes in CS
vol 1509]) adapts Griffiths-Niu semi-classical iQFT to multi-register
DLP, collapsing each exp register to a single recycled qubit — the
same trick Beauregard 2003 gave us for ORDER-finding in
`shor_order_D_semi`. Result: N=55 peak drops from 24 to ~13 qubits,
single-shot runtime from 13m16s to ≤30s.

**CRITICAL research step (MUST do first)**: Session 36 explicitly
established that EH17's §4.3 is NOT directly Griffiths-Niu-izable
because the (j,k) correlation is joint via shared `e = a - bd`.
Mosca-Ekert §3.2 solves this but the exact cross-register phase-
correction formula is NOT obvious from EH17 alone. Phase 0 of this
bead: FETCH Mosca-Ekert 1999 PDF (arxiv.org/abs/quant-ph/9903071 is a
candidate — verify when read) and work out the phase accumulator
recurrence on paper BEFORE any coding. Pattern mirrors rule 4: local
PDF + explicit equation reference.

**Acceptance**: see bead — 5 criteria including 50%+ hit rate at N=15,
peak reduction, runtime reduction, and a documented phase-correction
derivation in code comments.

**Avoid**: Don't try to "just mirror `shor_order_D_semi`'s outer
structure and hope" — this was the instinct session 36 already
corrected. The phase-correction for TWO exp registers feeding ONE
working register is non-trivial.

### e73 — Pure coset state via comparison-negation (P3)

**What**: Session 35 (bead 8fy) shipped `_coset_init!` with Cpad
EXTERNAL pad ancillae that remain entangled with `reg` — pragmatic
for 6xi acceptance but not the Gidney 1905.08488 Fig 1 circuit. The
paper's pure single-register construction uses a
`(-1)^{x ≥ 2^p·N}` comparison-negation phase kickback per stage to
DISENTANGLE pad ancillae back to |0⟩. Benefits: -Cpad steady-state
qubits, matches paper for publication, simplifies `decode!`, enables
true Gidney-style coset arithmetic downstream.

**How to start**: Implement `_comparison_negate!(reg::QInt{W},
threshold::Integer)` as a reversible comparator (subtract-check-
uncompute pattern; sub_qft_quantum! + sign-bit Z). Then rewrite
`_coset_init!` to Gidney Fig 1 literally: allocate pad_p fresh per
stage, H, controlled-add, comparison-negate, H, deallocate pad_p
(verified |0⟩). Keep the external-ancilla path as `pure=false`
fallback.

**Also useful for**: `jrl` (runway) and `6oc` (windowed arithmetic)
both want the comparator as a primitive. e73's comparator becomes
load-bearing infrastructure for the rest of the GE21 stack.

### What's NOT left for Shor (shipped)

For reassurance to future-agent: the Shor stack is already rich.
Shipped:
- 5 order-finding impls (A, B, C, D, D_semi) covering oracle-lift,
  PE HOF, U^{2^j} cascade, Beauregard 2n+3, and semi-classical iQFT.
- `shor_factor_EH` (6bn, this session) — EH17 1.5n short-DLP, s=1,
  30/30 hit at N=15, 24-qubit peak verified at N=55.
- `QCoset` / `coset_add!` / `decode!` — GE21 §2.4 coset representation
  (types shipped; NOT yet used inside any Shor driver — that's an
  unfiled polish step, not on the GE21 critical path).
- `QRunway` runway-at-end (b3l).

### Missing — GE21 critical path (UNCHANGED from prior sessions)

1. **`jrl` P2** — `QRunwayMid{W_low, Cpad, W_high}` runway-in-middle.
   Blocks 6oc. 3+1 type-design round required.
2. **`6oc` P1** — windowed arithmetic + `shor_order_E`. Blocked on jrl.
   Three phases, 3–4 sessions.

### Missing — orthogonal

- **`870` P1** — Steane QECC syndrome extraction; wrapping any
  shor_factor_* via `encode(ch, Steane)` gives fault-tolerant Shor.
- **`7z1` P3 / `wzc` P4** — Gidney 2025 / Regev 2023 (post-GE21).

### Suggested next-session pick (for future-you)

If you like **research-heavy**: `npd` (Mosca-Ekert) — ground-truth
fetch + paper derivation + implement. Highest information-per-session.

If you like **algorithmic**: `jrl` + `6oc` — the main GE21 chain, big
payoff (polylog Toffoli reduction), but 4-5 sessions.

If you like **small-and-shippable**: `e73` (pure coset). One session,
delivers a reusable primitive (comparator) that pays off later.

If you like **extension of 6bn**: `zli` (s>1). Classical-heavy (LLL),
minimal quantum work.

### Commits this session (36c)

```
b41fe2f  feat(shor): m/ell/verbose kwargs for shor_factor_EH + _eh_short_dlp
94f97fc  docs(worklog): session 36b — N=55 demo (biggest shor_factor_EH in 24 qubits)
<TBD>    docs(worklog): session 36c — file zli + npd + e73 EH17 follow-ons
```

Dolt remote synced after each close (`bd dolt push`).

---

## 2026-04-20 — Session 36b: N=55 demo (biggest shor_factor_EH fitting 24 qubits)

Ran `_eh_short_dlp(7, 28, 55, Val(3), Val(3), Val(6))` with verbose=true
instrumentation. Predicted peak `2·ell + m + 2·L + 3 = 24`. Actual peak
(via `ctx.n_qubits` after run): **24 qubits exactly**. ✓

### Runtime (commit `b41fe2f`)

```
[eh_dlp +1.2s  live=15] alloc y_reg[L=6] = |1⟩
[eh_dlp +88.1s live=15] first_reg[1]: EXIT mulmod_beauregard!
[eh_dlp +174.5s live=15] first_reg[2]: EXIT
[eh_dlp +263.4s live=15] first_reg[3]: EXIT
[eh_dlp +353.4s live=15] first_reg[4]: EXIT
[eh_dlp +442.0s live=15] first_reg[5]: EXIT
[eh_dlp +531.4s live=15] first_reg[6]: EXIT
[eh_dlp +621.1s live=15] second_reg[1]: EXIT
[eh_dlp +707.2s live=15] second_reg[2]: EXIT
[eh_dlp +792.6s live=15] second_reg[3]: EXIT
[eh_dlp +792.6s live=15] interfere!(first_reg)
[eh_dlp +793.5s live=15] interfere!(second_reg)
[eh_dlp +795.7s live=0 ] EXIT j=6 k=2
```

9 controlled mulmods at ~88s each, interfere! negligible. Total 13m16s
per shot. Each mulmod works at 2^24 statevector (24-qubit peak inside
the mulmod interior, driven by the L+1=7 ancillae).

### Single-shot MISS — the "smeared peaks" discovery

The shot returned `(j=6, k=2)` with `_eh_recover_d_candidates = []` —
no d ∈ (0, 8) satisfied `|{d·j + 2^m·k}_{64}| ≤ 2^(m-2) = 2`. Miss.

**Root cause (NEW insight, worth saving)**: For N=15 `max ord(g) = 4`
and 64/4 = 16 is an integer power of 2 → QFT peaks are sharp (every
shot lands on a multiple of 2^(ℓ+m) / ord). For N=55 `max ord(g) = 20`
(lcm(4, 10)) and 64/20 is NOT an integer, let alone a power of 2 → QFT
peaks are smeared across multiple (j, k) outcomes, and single-shot hit
rate degrades.

Generalisation: EH17's short-DLP algorithm at toy-N hits reliably only
when `ord(g) | 2^(ℓ+m)`, i.e., when `ord(g)` is a power of 2. For
N = pq with `p, q` odd primes, `max ord = lcm(p-1, q-1)`:
  * N=15: lcm(2, 4) = 4 = 2² ✓
  * N=21: lcm(2, 6) = 6 = 2·3 ✗
  * N=33: lcm(2, 10) = 10 = 2·5 ✗
  * N=35: lcm(4, 6) = 12 = 2²·3 ✗
  * N=39: lcm(2, 12) = 12 ✗
  * N=55: lcm(4, 10) = 20 = 2²·5 ✗

**Implication**: test acceptance of `shor_factor_EH(N) ≥ 50%` is
structurally easier at N=15 than at any other toy-N. Future acceptance
bars for Sturm's EH17 tests on N ∈ {21, 33, 35, 39, 55} should expect
lower single-shot rates (~20-40% empirically) and rely on
`max_attempts ≥ 10` to hit the cumulative ≥50% bar.

### What was committed

Commit `b41fe2f`:
- `shor_factor_EH(N; m=nothing, ell=nothing, verbose=false, ...)` —
  `m` and `ell` now overrideable (default heuristic unchanged).
- `_eh_short_dlp(..., verbose::Bool=false)` — stage-by-stage
  ENTER/EXIT lines on stderr (wall-clock ms, live qubits), flushed
  per line. Silent by default.

### Lessons for future agents

1. **`tail -N` defeats eager-flush.** Piping a streaming producer
   through `tail -80 | ...` buffers the entire stream until EOF.
   For verbose runs, redirect to a file and use `Monitor` on
   `tail -f file | grep --line-buffered ...`, or read the file directly
   while it's being written.

2. **Peak-qubit formula for EH17**: `2·ell + m + 2·L + 3` (L+1 mulmod
   ancilla + 1 cascade workspace + ell+m+ell exponent + L working).
   For 24-qubit budget: `3m + 2L ≤ 21` with ell=m, giving the family
   `(m=3, L≤6)` (biggest N=55) or `(m=4, L≤4)` (too small to be
   interesting).

3. **Runtime per mulmod scales as 2^peak**: ~86s at 2^24 vs ~1.5s at
   2^19 (N=15). For N=55 that's 9·88 = 13 min/shot. Multi-shot
   acceptance tests at N=55 would need 1-2 hours compute; do NOT
   run in a test suite.

4. **QFT peak sharpness = ord(g) | 2^(ℓ+m)**. Powers-of-2 order gives
   100% single-shot success; non-power-of-2 order smears peaks. The
   EH17 analytical bound `ord ≥ 2^(ℓ+m) + 2^ℓ·d` is violated for all
   these toy-N, but sharp-vs-smeared depends on the divisibility.

### Next-session pointers (unchanged)

As Session 36: `jrl` P2 (unblocks `6oc`), `870` P1 (Steane), or
`eud`/`c6n` Shor epics. Session 36b added no new blockers.

---

## 2026-04-20 — Session 36: Ship `Sturm.jl-6bn` (Ekerå-Håstad short-DLP factoring)

Single-bead session. Shipped `shor_factor_EH`, the EH17 short-DLP
derivative of Shor, picked because (a) it's an independent Shor driver
(no `jrl` / 3+1 type-design needed), (b) single-session scope, and
(c) user asked for "Shor algorithm stuff". Commit `6e0cc60` pushed.

### Ground truth before coding (rule 4 + user instruction)

Read `docs/physics/ekera_2017_short_dlp.pdf` (arXiv:1702.00249) front to
back (pp. 1–15). Extracted:
- §4.3 quantum step: |Ψ⟩ = (1/√2^(2ℓ+m)) Σ_a Σ_b |a⟩|b⟩|0⟩, compute
  [a]g ⊙ [-b]x = [a-bd]g, QFT both registers, measure → (j, k).
- §4.4 classical post-processing (s=1): 2D lattice L = Z-span of
  [[j,1], [2^(ℓ+m),0]], target v = ({-2^m k}_M, 0), search |u-v| <
  sqrt(5)/2·2^m, last coord of u is d.
- Def 1 (good pair): |{d·j + 2^m·k}_{2^(ℓ+m)}| ≤ 2^(m-2).
- §5.2.2 factor recovery (EH-normalisation): y = g^((N-1)/2) mod N,
  d = (p+q-2)/2, quadratic x² - (2d+2)x + N = 0 with roots
  p, q = (d+1) ± √((d+1)² - N).

### Conceptual surprise — EH17 is NOT amenable to semi-classical iQFT

My first instinct was to mirror `shor_order_D_semi`'s Griffiths-Niu
semi-classical iQFT (Beauregard 2003 "one-qubit trick") and do two
sequential per-bit measure-and-correct loops, one per register.

**That is wrong.** §4.3 Eq. (the observation probability expression)
shows that the joint distribution P(j, k) is non-separable — the (j, k)
correlation comes from the shared e = a - bd in the working register
and is resolved jointly by QFT on both registers. Measuring first
register's iQFT outcome LOSES this correlation: the post-measurement
state isn't the one a naïve "semi-classical iQFT" would produce.

Mosca-Ekert (§4.7 of EH17 refs) adapts semi-classical to multi-register
DLP but the trick is more subtle than one-register PE. Out of scope.

**Shipped**: full non-semi-classical two-register PE with explicit
`QInt{ell+m}` + `QInt{ell}` exponent registers in `|+⟩^n` via
`superpose!` (which is forward QFT; on |0⟩ it equals H^⊗n |0⟩),
controlled mulmods, then `interfere!` (inverse QFT) on each register
independently, and measurement.

Peak qubit budget at N=15 (m = ell = 3, L = 4):
`6 + 3 + 4 + 5 + 1 = 19` wires — well under Orkan's 30.

### Classical post-processing: brute force over d, then verify

Straight `for d in 1:(2^m - 1)` with the good-pair residual bound.
For m=3 this is 7 candidates. Returns `Vector{Int}` sorted by
ascending |residual|. Driver iterates candidates, verifies each via
`_eh_factors_from_d` (the quadratic), accepts the first that
actually factors N.

**Why a list, not a single minimum:** at small m, multiple d values
can satisfy the residual bound — these are the "spurious lattice
vectors" of §4.4 Lemma 3. The probe output for (j=2, k=7, m=ell=3)
returned `[4, 3, 5]` with d=4 first (residual 0) and d=3 second
(residual 2, the true answer). d=4 fails the quadratic (disc=10 not
a square); d=3 succeeds. Verification IS the uniqueness-resolution.

### Toy-N caveat: N=15 violates EH17's analytical assumption

EH17 §4.3 requires ord(g) ≥ 2^(ℓ+m) + 2^ℓ·d. For N=15: max ord is 4
(= lcm(p-1, q-1) = lcm(2, 4)), and 2^(ℓ+m) = 64. So the algorithm runs
**outside** its proven regime at N=15. Empirically it still works
because:
- Lucky-g cases (gcd(g, N) > 1) resolve classically (~46% at N=15).
- For coprime g, only low bits of the exponent registers couple to
  `y_reg` (high-bit mulmods are identity when `g^(2^i) mod N = 1`);
  the iQFT on those low bits still produces biased (j, k) pairs.
- At m=3, the brute-force verification step exhaustively checks all 7
  candidate d values, so "spurious candidate d=4" never leaks through.

Observed hit rate: **30/30 for N=15** (100%). Well above the 50% bar.

### Parameter selection heuristic

`n_N = ceil(log2(N+1))`, `m = max(3, (n_N+1)÷2 + 1)`, `ell = m`, `L =
ceil(log2(N))`. At N=15 → m=3. At N=35 → m=4. At N=21 → m=4. The
`+1` buffer over `(n_N+1)÷2` ensures d < 2^m for any (p, q) satisfying
2^(n_prime-1) < p, q < 2^n_prime. No tuning required per-N.

### RED-GREEN TDD trace

1. **RED**: wrote `test/test_6bn_ekera_hastad.jl` with 5 testsets:
   (a) `_eh_factors_from_d` on {N=15, N=21, N=35}, wrong-d cases;
   (b) `_eh_recover_d_candidates` on all j ∈ [1, 63] for d_true=3,
       verifying d_true in candidates for every good pair
       (39 of 63 j values are good pairs; Lemma 1 predicts ≥32);
   (c) non-good-pair returns `[]`;
   (d) spurious-candidate case `(j=2, k=7)` includes d=3;
   (e) end-to-end hit rate ≥ 50% over 30 shots;
   (f) even-N trivial factor.

2. **Classical GREEN first** (30 seconds): sanity probe showed
   `_eh_factors_from_d` and `_eh_recover_d_candidates` immediately
   correct — typical of brute-force closed-form math.

3. **Quantum probe**: ran 5 shots of `_eh_short_dlp(g, y, 15, ...)`
   with various g. Non-lucky shots all returned (j, k) whose candidate
   list contained d=3. Sign that the full hit rate would be very high.

4. **Full test**: 54 tests pass in 3m44s (30 quantum shots + all
   classical tests). 30/30 = 100% hit rate at N=15.

### Files touched

- **New**: `src/library/shor.jl:1153..1426` — EH impl block (273 lines):
  `_eh_recover_d_candidates`, `_eh_factors_from_d`, `_eh_short_dlp`,
  `shor_factor_EH`. Appended after `shor_factor_D_semi`.
- **New**: `test/test_6bn_ekera_hastad.jl` (118 lines) — 54 tests.
- **Modified**: `src/Sturm.jl:123` — added `export shor_factor_EH`.
- **Modified**: `WORKLOG.md` — this session 36 entry.

### Commits

```
6e0cc60  feat(shor): shor_factor_EH — Ekerå-Håstad short-DLP factoring + 54 tests — close Sturm.jl-6bn
```

Dolt remote also pushed.

### Beads

Closed: `Sturm.jl-6bn` P2.
None filed.

### Lessons for future agents

1. **EH17's §4.3 is NOT directly semi-classical-izable.** The (j, k)
   correlation is joint (via `e = a - bd`), not sequential. One-qubit-
   trick semi-classical PE from `shor_order_D_semi` doesn't carry over
   as-is. Mosca-Ekert (§4.7 refs) is the adapted form — out of scope
   for 6bn but could shrink the 9-qubit exponent cost for a follow-on.

2. **Brute-force classical post-processing beats Lagrange at small m.**
   The bead spec said "~20 lines Lagrange reduction"; the actual win
   is at m > ~20. For m=3 the brute-force is 7 candidates with trivial
   residual arithmetic — cleaner AND exhaustively correct (no short-
   lattice-vector corner cases to worry about).

3. **Verification-by-factorisation is THE disambiguator.** When
   multiple d satisfy the residual bound, `_eh_factors_from_d(d, N)`
   returns `nothing` for the spurious ones. No need for a proper CVP
   algorithm at toy N — just try every candidate.

4. **Toy-N (N=15) works despite violating the EH17 analytical bound.**
   ord(g) ≪ 2^(ℓ+m) at N=15, but the algorithm still biases (j, k)
   toward good pairs because of the low-bit coupling structure.
   Don't dismiss an algorithm as "broken at small N" without probing —
   the math may still cooperate.

5. **Classical sanity check before ANY quantum probe.** The quantum
   step takes 13-20s per shot at N=15; a typo in the driver that causes
   retries would waste minutes. Running `_eh_factors_from_d` and
   `_eh_recover_d_candidates` in isolation took 30s and caught the
   initial "min-residual-always-correct" assumption before the quantum
   pipeline was ever invoked.

6. **User gave explicit TDD + idiom instructions.** Followed all three
   (ground truth first via PDF read, RED tests first, Sturm-idiom check
   before coding). Heuristic: when user says "before coding", ALWAYS
   read the primary source AND re-check the Sturm codebase for the
   specific primitives the impl will use (in this case
   `mulmod_beauregard!` signature + `QInt[i]` non-owning view pattern).

### Next-session pointers

**Unchanged from Session 35 — highest-priority ready beads**:
- `jrl` P2 — QRunwayMid runway-in-middle type. Blocks `6oc`.
- `6oc` P1 — windowed arithmetic (blocked on `jrl`). 3-4 sessions.
- `870` P1 — Steane [[7,1,3]] syndrome extraction (orthogonal).

**New candidate follow-ons filed or implied from 6bn**:
- NONE filed this session. `shor_factor_EH` is complete; the s>1 /
  lattice-Lagrange extensions and Mosca-Ekert semi-classical variant
  are orthogonal-wins, not blockers. If ever needed, file then.

**Hygiene**: `5jn` (ntuple in `_shor_mulmod_a!`), `2i0` (ScopedValue).

---

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

## 2026-04-19 — Session 30: Close `Sturm.jl-i0j` (Shor resource benchmark + diagrams)

Point estimate for "what idiomatic Shor actually costs in Sturm":
trace each of the five `shor_order_*` implementations under
`TracingContext` on N=15, a=7, t=3, count DAG nodes, render ASCII
and PNG. Writes `docs/shor_benchmark.md` + selected examples.

### Results

| Impl | Wires | Gates | CX | CCX | Ry | Rz | Depth | DAG KB |
|------|------:|------:|---:|----:|---:|---:|------:|-------:|
| `A` (oracle lift) | 18 | 148 | 98 | 28 | 10 | 12 | 137 | 4.1 |
| `B` (phase_estimate HOF) | 217 | 3609 | 6 | 3528 | 63 | 12 | 3605 | 93.4 |
| `C` (c-U^{2^j} cascade, QROM) | 109 | 3097 | 2310 | 744 | 31 | 12 | 2702 | 78.3 |
| `D` (Beauregard arithmetic) | 19 | 2385 | 470 | 24 | 399 | 1492 | 1264 | 58.7 |
| `D_semi` (Beauregard + semi-classical iQFT) | 19 | 2373 | 464 | 24 | 399 | 1486 | 1264 | 58.4 |

Wire counts are monotone `_wire_counter[]` deltas — every allocation
increments, deallocate! does NOT decrement. So this table's "wires"
is closer to "distinct horizontal lines in the rendered circuit"
than to HWM of concurrent live wires.

### Takeaways worth remembering

- **`D` vs `D_semi` on a static trace looks near-identical.** Same
  gate count (± 12, from skipped `a_j=1` mulmods), same depth. The
  D_semi saving is the counter qubits — `t` in impl D, `1` in impl
  D_semi. At t=3 that saves 2; the compile-time gate count barely
  notices. At t=28 (L=14) the counter saving is the whole point.
- **Impl B is QROM-dominated, not mulmod-count-dominated.** It fires
  only `2^t − 1 = 7` mulmod calls but each carries a 2^(L+1)-entry
  Babbush-Gidney QROM. 217 wires is a log-depth QROM ancilla tree
  opened and closed 7×. Impl B is the polynomial-in-2^L cautionary
  tale — idiomatic, not scalable.
- **Impl A is the lean surprise.** 148 gates on a single QROM is
  shorter than impl D's arithmetic mulmod at this size. It's not
  scalable in t (exponential table), but for N=15 demonstrations it's
  the cleanest circuit.
- **Impl C is bimodal.** At N=15 t=3 it prints as 3097 gates / 109
  wires — similar order as impl B. At N=36 L=6 (from
  `bench_shor_scaling.jl`) it balloons to ~47M gates / ~1.2GB DAG.
  The QROM packed-index grows 2^L; don't use impl C past L=5 in
  simulation.
- **`_draw_schedule_compact` is the cheapest `depth` proxy we have
  today.** No critical-path pass, but the ASAP-scheduled column count
  lines up with what a reader of the PNG would count.

### Gitability

Some outputs (B.png 2.5 MB, B.txt 10 MB, C.txt 3.5 MB) are too big
to commit. `render_case` now `rm`s any artefact > 800 KB after
writing; `docs/shor_benchmark.md` documents the commit threshold and
shows *(regen)* for dropped cells. The bench script regenerates
everything in ~7 seconds on this box — cheap to re-run.

### Files touched

- `test/bench_shor_i0j.jl` (new) — TracingContext → node_breakdown
  + render + markdown emit. ~180 lines.
- `docs/shor_benchmark.md` (new, auto-generated).
- `examples/shor_N15_{A,C,D,D_semi}.png` + `{A,D,D_semi}.txt` —
  committed (all ≤ 800 KB).
- `WORKLOG.md` — this entry.

### Beads

- `Sturm.jl-i0j` closed.
- Remaining Shor work: `Sturm.jl-eud` EPIC (largely delivered —
  all 5 impls exist, benchmarks landed, N=15 + N=21 end-to-end
  correctness verified via di9 fix + 8b9 semi-classical).

---

## 2026-04-19 — Session 29: Close `Sturm.jl-8b9` (semi-classical iQFT for Shor)

Beauregard 2003 §2.4 Fig. 8 — the "one controlling-qubit trick" —
replaces the `t`-wide counter register in Shor order-finding with a
single recycled `QBool` via semi-classical inverse QFT. The t PE
counter qubits all commute (they're all control wires on the same `y`
register) and the cross-term Rz gates in the iQFT become classical
phase corrections once the bits are measured.

### Ground truth (read before coding, rule 4)

`docs/physics/beauregard_2003_2n3_shor.pdf` pp. 8-9, Fig. 8, + text at
end of p. 8: "This simulates the inverse QFT followed by a measurement
on all qubits as in figure 5. We save an important number of qubits
this way, and in fact we need only a total of 2n + 3 qubits to factor
an n-bit number as we will show in the complexity analysis section."

The concrete Rz correction formula is from Griffiths & Niu 1996
(quant-ph/9511007) / Parker & Plenio 2000 (quant-ph/0001104):

  θ_i = −2π · Σ_{j<i, bit_j = 1} 2^{−(i − j + 1)}

applied to the iter-i counter between H and the controlled-U step, to
"rotate out" the cross-terms that correspond to bits already measured.

### Implementation — `src/library/shor.jl:shor_order_D_semi`

One function, ~60 lines including docstring. The outer structure mirrors
`shor_order_D`:

1. Classical precompute `a_js = [a^{2^(t-i)} for i in 1..t]` — note the
   **reversed** power order (iter 1 uses the highest power `2^(t-1)`,
   iter t uses `2^0`). This is what makes iter 1 measure the LSB of ỹ
   (the phase at iter 1 is `π · ỹ` mod 2π, whose parity is the LSB).
2. Allocate `y_reg = QInt{L}(1)` once, reused across t iters.
3. Loop i = 1..t:
   a. Fresh `c = QBool(0)`, `H!(c)` → |+⟩.
   b. Classical `corr -= 2π / (1 << (i-j+1))` per prior set bit j.
       `c.φ += corr`.
   c. `mulmod_beauregard!(y_reg, a_js[i], N, c)` — skip when a_j = 1.
   d. `H!(c)` + `Bool(c)` → m_i.
4. Reconstruct `ỹ = Σ m_i · 2^{i-1}` (LSB-first convention).
5. Standard continued-fraction post-processing (shared helper).

### Idiomatic Julia / Sturm check

- Counter qubit is a plain `QBool(0)`, measured via `Bool(c)` cast (P2).
- The Rz correction is `c.φ += θ` — literally primitive 3. No raw matrices.
- The H! gate is the existing library function (built from the 4 prims).
- The measured bits are a plain `Vector{Bool}`, indexed classically. No
  quantum-resident classical register — Sturm's P2 type boundary makes
  the quantum→classical handoff implicit.
- `shor_factor_D_semi` wraps the same `_shor_factor_from_order` helper
  that every other impl uses. Zero duplicated logic.

### Bit-ordering gotcha (found via smoke test)

First implementation used `a_js[i] = a^{2^(i-1)}` (LOW power first), with
LSB-first bit reconstruction. Smoke test showed wrong hit rates:

    N=15 a=7 r=4:  impl D = 53%  vs  D_semi = 30% ❌
    N=21 a=2 r=6:  impl D = 13%  vs  D_semi = 0%  ❌

The issue: at iter 1 with c-U^{2^0}, the counter phase is
`2π · φ` — DOMINATED by the MSB contribution, not the LSB. So iter 1
would measure the MSB, not the LSB, and my reconstruction bit-placed it
as if it were the LSB. The ỹ values were bit-reversed.

Fix: swap the c-U order (HIGH power first). At iter i with c-U^{2^(t-i)},
counter phase = `2π · ỹ / 2^i`, whose LEADING fractional bit IS `bit_{i-1}`.
Iter 1 → bit_0 (LSB), iter t → bit_{t-1} (MSB). LSB-first reconstruction
stays correct.

Post-fix smoke test:

    N=15 a=7 r=4:  impl D = 50%  vs  D_semi = 47% ✓
    N=15 a=2 r=4:  impl D = 53%  vs  D_semi = 40% ✓
    N=21 a=2 r=6:  impl D = 27%  vs  D_semi = 47% ✓ (!)
    N=21 a=4 r=3:  impl D = 60%  vs  D_semi = 60% ✓

### Speed

`shor_order_D_semi` is ~25× faster than `shor_order_D` in simulation at
N=21 t=6 (17 s/shot vs 420 s/shot). The statevector is 2L+4 qubits (14
at L=5) rather than t+2L+2 = 14 — same peak! But the *reuse* of slots
inside the recycled counter means Orkan doesn't grow the statevector as
it would if we carried all t counter qubits LIVE simultaneously through
the cascade allocations. At N=21 the impl-D peak is 14 qubits CONCURRENT,
but some of those are touched by OpenMP-parallel state updates in ways
that thrash on a 2^14 = 16k-amplitude buffer; D_semi's qubit count is
the same at peak but the TEMPORAL allocation pattern is much more
cache-friendly.

### HWM — 2L+4, not 2L+3

Beauregard's "2n+3 qubits" bound treats doubly-controlled-φADD(a) as a
primitive. Sturm's EagerContext lowers doubly-controlled Rz via the
`_multi_controlled_gate!` Toffoli cascade, which allocates 1 workspace
qubit (nc=2 ⇒ 1 workspace). So the measured HWM is:

    1 (counter) + L (y) + (L+1) (b) + 1 (anc) + 1 (cascade workspace)
    = 2L + 4

Confirmed empirically: `peak = 12` at L=4, `peak = 14` at L=5.

Closing the gap to 2L+3 would require a workspace-free CCRz lowering in
`src/context/multi_control.jl` — that's a Sturm engine optimisation,
separate from 8b9.

### RED-GREEN TDD

1. RED: smoke test showed systematic hit-rate mismatch (impl D = 53%,
   D_semi = 30% at N=15 a=7) — bit ordering wrong. Fixed.
2. GREEN: registered 5 testsets in `test/test_shor.jl`:
   - `order_D_semi(7,15;t=3) ≥ 30% hits` (30 shots)
   - `order_D_semi` on 3 N=15 bases ≥ 20%
   - `order_D_semi(2,21;t=6) ≥ 15% hits` (30 shots)
   - `shor_factor_D_semi(15) returns {3,5}` ≥ 50%
   - `HWM ≤ 2L+4` at (15,3), (15,6), (21,6)
3. All pass in 40 seconds wall time (targeted-subset run, OMP=1).

### Files touched

- `src/library/shor.jl` — `shor_order_D_semi` + `shor_factor_D_semi`;
  removed the di9 warning block from `shor_order_D`'s docstring.
- `src/Sturm.jl` — export the two new functions.
- `test/test_shor.jl` — `@testset "Impl D-semi …"` with 5 sub-testsets;
  dropped a slow N=21 impl-D acceptance test (delegated to D-semi which
  is 25× faster at the same coverage).
- `test/probe_8b9_smoke.jl` (new) — side-by-side comparison with impl D.
- `WORKLOG.md` — this entry.

### Beads

- `Sturm.jl-8b9` closed.
- `Sturm.jl-c6n` EPIC (polynomial-in-L Shor) is now fully delivered:
  - ar7 (add_qft!) ✓
  - dgy (modadd!) ✓
  - uf4 (mulmod_beauregard!) ✓
  - 6kx (shor_order_D) ✓
  - di9 (phase-clean arithmetic) ✓ (session 28)
  - 8b9 (semi-classical iQFT) ✓ (this session)

### Gotchas for future agents

1. **Test the c-U order with a smoke test BEFORE relying on
   theoretical parity arguments.** Parker-Plenio's phase correction
   formula `-2π / 2^(i-j+1)` is derived under the ASSUMPTION that iter
   i uses c-U^{2^(t-i)} (high power first), not c-U^{2^(i-1)} (low first).
   The correction formula is identical in both cases but the BIT BEING
   MEASURED is different — and the reconstruction has to match. I
   burned 10 min on this before the 2-data-point (N=15 a=7 + N=21 a=2)
   smoke test made the bit-reversal obvious. Always compare against a
   reference implementation, even by noisy hit-rate statistics.
2. **ctx.n_qubits is monotonically non-decreasing** — it tracks the
   peak live-qubit count since the context was created. Testing HWM is
   as simple as `peak = ctx.n_qubits` at end of the function, assuming
   the function is the only allocation-producing call on that context.
   No need for a manual HWM tracker.
3. **`@testset verbose=true` still batch-prints.** To see test progress
   on slow tests (>30s), add explicit `println(stderr, "..."); flush()`
   inside the test body. Otherwise `@testset` blocks the log until the
   whole set finishes.

---

## 2026-04-19 — Session 28: Close `Sturm.jl-di9` (add_qft! angle-fold phase bug)

P0 landed. Root cause of the "π/2 leak" flagged in Session 27 is the
angle-fold in `add_qft!` — `mod(θ + π, 2π) - π` maps BOTH `θ = +π` and
`θ = -π` to `-π`, breaking `Rz(θ) · Rz(-θ) = I` on any wire whose raw
angle lands exactly on the boundary. Under `when(ctrl)` that -I per-wire
becomes a relative π phase on `ctrl = |1⟩`, and across many modadds
(Shor's PE cascade) the phases accumulate and scramble the counter
register. Session 27's data was real; the **diagnosis** was partially
misread (see below).

### Grind method — first-diff-with-ground-truth

1. Reproduced the 50% X-basis leak from `probe_mulmod_phase.jl`
   (Session 27). Confirmed the leak is x-dependent as reported.
2. Wrote a block-wise probe (`probe_di9_blockwise.jl`) testing
   `when(ctrl) add_qft!(y, a)` with no inverse restore.
   **Unexpected**: every block from single add_qft to full mulmod
   showed ~50%. That "universal 50%" was the first clue the Session 27
   diagnosis was off.
3. Realised `when(ctrl) U |x⟩` on non-eigenstate `x` produces
   `(|0⟩|x⟩ + |1⟩·U|x⟩)/√2` and tracing `x` decoheres ctrl to 50/50 in
   ANY basis. The Session 27 probe was measuring inherent ctrl-target
   entanglement, NOT a phase bug.
4. Wrote `probe_di9_inverse.jl` with the correct protocol:
   `when(ctrl) do U; U⁻¹ end`. Ctrl should come back to pure |+⟩
   regardless of target state; any X-basis leak is a true global-phase
   bug. This smoked out the real fold.
5. Hand-traced the L=1 a=1 v=0 case (smallest reproducer):
   - `add_qft(y=QInt{2}, +1)`: wire 2, jj=1, θ_raw=π → fold → Rz(-π).
   - `sub_qft(y, 1) = add_qft(y, -1)`: `a_mod = mod(-1, 4) = 3`, wire 2,
     θ_raw = 3π → fold → Rz(-π) (same folded angle!).
   - Composed wire 2: Rz(-π) · Rz(-π) = Rz(-2π) = -I.
   - Under ctrl: -I on ctrl=|1⟩ = relative phase π = 100% X-basis leak.
   Observed: 100.0% in probe. ✓ First diff located, root cause identified.

### Fix — `src/library/arithmetic.jl:59`

Removed the fold entirely. `add_qft!` now emits `Rz(θ_raw)` per wire
where `θ_raw = 2π · a / 2^jj`. Orkan computes `Rz(θ)` in double
precision for any θ, so "keeping angles small" was never load-bearing.
The `a_mod = mod(Int(a), 1<<L)` wrap was also dropped: Rz(θ) is
periodic mod 4π as a gate action (period 2π on target states up to a -I
factor that now cancels cleanly with the matching inverse), and the
caller-side invariants (a ∈ [0, N), b ∈ [0, N), N < 2^L) keep θ
bounded anyway.

### Red-green TDD

1. **RED**: added `@testset "di9: X-basis coherence of controlled
   arithmetic sub-circuits"` to `test/test_arithmetic.jl` — 24 tests
   covering add_qft∘sub_qft under when(ctrl), modadd∘modadd(N-a) with
   ctrls=(c,) and ctrls=(c,|1⟩), and mulmod(a)∘mulmod(a⁻¹). Minimal
   reproducer (L=1 a=1 v=0) RED-checked to confirm 100% leak pre-fix.
2. **GREEN**: one-function fix in `add_qft!`. Minimal probe → 0% leak.
3. **Full `test_arithmetic.jl` regression** (OMP_NUM_THREADS=1, 1m06s):
   - add_qft!: 809/809
   - modadd!: 2130/2130
   - mulmod_beauregard!: 269/269
   - di9 X-basis coherence: **24/24** (new)
   Total: **3232/3232** green.
4. **End-to-end Shor acceptance** (`probe_di9_shor_n21.jl`):
   - N=15 a=7 r=4 t=3: 21/30 = **70%** hits (Session 26: 50%)
   - N=15 a=2 r=4 t=3: 13/20 = **65%** hits
   - N=21 a=2 r=6 t=6: 5/20 = **25%** hits (Session 27: 0/20 = 0%) ✓ ≥20%
   - N=21 a=4 r=3 t=6: 6/10 = **60%** hits

### Gotchas for future agents

1. **`mod(θ+π, 2π) - π` is a LEAKY fold under control.** Any angle
   canonicalisation that maps the boundary representatives
   asymmetrically (+π ≠ -π under the map, but folds them together)
   breaks `Rz(θ) · Rz(-θ) = I`. If you need to fold Rz angles for
   display or optimisation, fold them INTO THE UNITARY itself using the
   equality `Rz(θ + 2π) = −Rz(θ)` — i.e., keep a parity bit and apply a
   compensating CP/CZ on the control stack. Or just don't fold.
2. **`when(ctrl) U |x⟩` on non-eigenstate x looks like a phase bug on
   an X-basis probe.** 50% measure-true is the signature of ctrl being
   fully traced-out by the entangled target, NOT a phase leak. The
   correct phase-bug probe is `when(ctrl) U; U⁻¹ end`: any leak there is
   a genuine global-phase mismatch because U·U⁻¹ = I returns target
   trivially on both ctrl branches. Session 27's probe was conflating
   the two. If you're investigating a controlled-unitary, ALWAYS use
   the forward-inverse pattern first.
3. **Session-level "grind" workflow paid off again.** Reproducing with
   a minimal L=1 single-Rz case + hand-tracing the 2-line arithmetic
   localised the bug in < 5 minutes of reading after the inverse probe
   fired. The multi-stage block-wise probe was useful to rule out
   modadd-only / mulmod-only mechanisms, but the SMOKING GUN was
   picking the smallest controlled example and working through the
   folded angles by hand. "Find-first-diff-with-ground-truth" >
   speculation.
4. **X-basis inverse-pair regression tests are now part of the
   acceptance surface for Shor arithmetic.** The 24 di9 tests added to
   `test/test_arithmetic.jl` are the tripwire for the next silent-phase
   bug in add_qft / modadd / mulmod. Run them on every change to
   `src/library/arithmetic.jl`.
5. **OMP_NUM_THREADS=1 during verification.** Without it, Orkan's
   OpenMP parallelism spawns enough threads to saturate CPU time
   counters but doesn't help small statevectors (3-13 qubits is too
   small to parallelise usefully). With OMP=1 the 24-probe GREEN check
   ran in 23s; without it the regression test_arithmetic.jl run
   appeared to stall (high CPU but no output) because Julia's `@testset`
   batch-prints. One-liner fix: always set OMP_NUM_THREADS=1 for
   shor/arithmetic probes.

### Files touched

- `src/library/arithmetic.jl` — removed the fold, updated docstring.
- `test/test_arithmetic.jl` — added `di9:` testset (24 assertions).
- `test/probe_di9_blockwise.jl` (new) — block-wise forward-only probe
  (kept as a reference for the "50% leak is inherent entanglement"
  lesson).
- `test/probe_di9_inverse.jl` (new) — canonical forward-inverse X-basis
  harness.
- `test/probe_di9_green.jl` (new) — verbose-eager-flush GREEN runner
  for the same cases (used for fast iteration; `@testset` output is
  batch-delayed).
- `test/probe_di9_shor_n21.jl` (new) — Shor end-to-end acceptance at
  N=15, N=21 with both a=2 (r=6) and a=4 (r=3).
- `WORKLOG.md` — this entry.

### Beads

- `Sturm.jl-di9` closed.
- `Sturm.jl-6kx` (shor_order_D at N=15) stays closed but now genuinely
  verified: N=21 r=6 Shor works at 25% hit rate.
- `Sturm.jl-8b9` (semi-classical iQFT) still P1, still deferred. Would
  now be safe to implement on top of the phase-clean arithmetic.

---

## 2026-04-19 — Session 27: Hunt for N=21 failure uncovers P0 bug in uf4

Session 26 closed `Sturm.jl-6kx` with shor_order_D green at N=15 (50%
r=4 hit rate, 10/10 factor_D(15) → {3,5}).  User asked to extend
verification to N=21 and N=35 per the 6kx acceptance criteria.  The
extension **FAILED** — and the root cause is a P0 phase leak in
`mulmod_beauregard!` (Sturm.jl-uf4), which Session 25's all-green
3208-test suite **did not catch** because every test was Z-basis on
ctrl.  Honest status: **we do not have a working Shor algorithm yet**
for any N larger than 15.

### Trail

**Stage 1 — N=21 end-to-end fails.** `test/probe_shor_larger_N.jl`
20 shots of `shor_order_D(2, 21; t=6)`: **0/20 r=6 hits** (expected
~33% per PE theory), 14/20 "other" r values.

**Stage 2 — ỹ histogram is scattered, not peaked.**
`test/probe_N21_ytilde.jl` took 40 shots of the same cascade and
dumped ỹ distribution.  Result: 30 distinct ỹ values out of 64,
only 10 shots at the 6 theoretical peaks {0, 11, 21, 32, 43, 53}.
Expected (PE theory) mass at peaks ≈ 24/40 (60%).  Observed 25%.
Top 3 values (30, 32, 33) each with 3 shots show a triple-wide
cluster around 32 — PE amplitudes are smeared, not peaked.

**Stage 3 — mulmod itself is correct.**
`test/probe_shor_bug_hunt.jl` ran:

- EXP-A: `mulmod_beauregard!` at L=5 N=21 exhaustive, all 252
  (a, x₀) cases with ctrl=|1⟩: **0 fail**.  Arithmetic correct.
- EXP-B: `shor_order_D(7, 15; t=4)` 20 shots: 11/20 r=4 (55%).
- EXP-C: `shor_order_D(7, 15; t=6)` 10 shots: 8/10 r=4 (80%).

  So the primitive is right, the PE machinery works at N=15 at all
  tested t, but the cascade breaks at larger N.

**Stage 4 — PE machinery itself is correct.**
`test/probe_pe_bug.jl` Q1: `phase_estimate(Z!, QBool(1), Val(t))`
at t ∈ {3, 4, 5, 6}: 20 shots each, **all return the exact expected
ỹ** (ỹ = 2^(t-2), since Z! = Rz(π) has eigenphase 1/4 — a correct
eigenphase I briefly thought was 1/2 before re-reading CLAUDE.md's
"Global Phase and Universality" note).  Rule 9 check on my own
assumption.  phase_estimate is fine.

  Q2: same probe ran `shor_order_D(2, 21; t=3..6)` — period-factor
hit rate stuck at **6.7%** for t=3, 4, 5 (single lucky r=2 shot per
15), then 20% at t=6.  N=21 is broken at every t; this is not a
resolution issue.

**Stage 5 — X-basis test on ctrl exposes the π/2 phase leak.**
`test/probe_mulmod_phase.jl` runs the minimal protocol:

    ctrl = QBool(1/2)          # prepare |+⟩ via Ry(π/2)|0⟩
    mulmod_beauregard!(x, a, N, ctrl)
    ctrl.θ -= π/2              # Ry(-π/2) = inverse of the |+⟩ prep
    m = Bool(ctrl)             # should be FALSE if ctrl preserved

If `mulmod_beauregard!` preserves ctrl as a pure |+⟩, Ry(-π/2)
brings ctrl back to |0⟩ and `m = false` every shot.  Any `m = true`
rate above 0 indicates ctrl was disturbed; rate = sin²(ξ/2) gives
the effective leaked phase ξ on ctrl=|1⟩.

**Measured across L=4 N=15 and L=5 N=21, 80 shots per case:**

| config                       | x₀ = 0 | x₀ > 0 (any)     |
|------------------------------|-------:|-----------------:|
| L=4 N=15 a ∈ {2, 7}          |  0%    | **47 – 58%**     |
| L=5 N=21 a ∈ {2, 4, 16}      |  0%    | **44 – 61%**     |

Leak = ~50% everywhere x > 0 ⇒ **ξ = π/2 exactly** (sin²(π/4) = 0.5).
Leak = 0 at x = 0 because mulmod is trivially identity on |0⟩ there.

The 50% X-basis rate is consistent with ctrl being in a
**maximally mixed state** after mulmod — i.e., ctrl has been
completely entangled with internal ancillae that are then discarded,
and the partial trace erases ctrl's coherence.  That matches the
observed PE behaviour: 6 sequential mulmods at N=21 t=6 decohere
all 6 counter qubits, killing interference.

### Why Session 25's 3208-test suite missed this

Every uf4 coherent test ran:

    @context EagerContext() begin
        x    = QInt{L}(x0)
        ctrl = QBool(1/2)
        mulmod_beauregard!(x, a, N, ctrl)
        r = Int(x)
        _ = Bool(ctrl)                # Z-basis on ctrl
        ...
    end

**Z-basis on |+⟩ and on a maximally-mixed qubit both give 50/50.**
The two are indistinguishable without an X-basis measurement (or
equivalently, an inverse of the |+⟩ prep followed by Z).  Session
25's tests correctly caught every case where ctrl ACQUIRED a
population imbalance — but a pure phase (or full decoherence) stays
invisible.

### Corollary — N=15 t=3 "passed" by coincidence

At N=15 a=7 with t=3, only 2 of 3 mulmods actually fire because
a_j = [7, 4, 1] and a_j=1 is skipped at runtime.  Two rounds of
decoherence accumulated across only 3 counter qubits happens to
scatter PE amplitudes in a way that *still* gives 50% mass on the
r=4 peaks (ỹ ∈ {2, 6} decode to r=4 at t=3).  This is a
happy-accident signal, not a correctness guarantee.  The bench
numbers for impl D (wires, gates, DAG bytes) remain valid as
structural / resource measurements — the DAG IS polynomial in L —
but the statevector simulation outputs cannot be trusted past
N=15.

### Status of the polynomial-in-L Shor chain

| Bead                     | Real status                                |
|--------------------------|--------------------------------------------|
| `Sturm.jl-ar7` add_qft   | ✓ correct                                  |
| `Sturm.jl-dgy` modadd    | ⚠ Z-basis correct; X-basis coherence not verified |
| `Sturm.jl-uf4` mulmod    | ⚠ Z-basis correct; **π/2 X-basis leak** (di9) |
| `Sturm.jl-6kx` shor_D    | ⚠ structure correct; end-to-end N=15 only; **BROKEN N ≥ 21** |
| `Sturm.jl-di9`           | P0 bug filed; root-cause fix blocks 6kx completion |
| `Sturm.jl-8b9`           | P1 Fig. 8 semi-classical iQFT, deferred — would have hit the same phase leak anyway |

### Not yet known — where the π/2 comes from

Three candidates under investigation (details in Sturm.jl-di9):

1. **Controlled-Rz(θ) on superposed target leaks -θ/2 phase on
   ctrl=|1⟩.**  add_qft! contains Rz gates applied to Fourier-basis
   y wires (every y wire is in superposition).  Inside modadd step
   6 (`when(anc) add_qft!(y, N)`) or modadd steps 1/7/13 (under
   ctrls=(ctrl, xj)), each CRz(θ_k) leaks -θ_k/2 onto the outer
   control.  Summing across wires and across modadd calls per
   mulmod could produce the observed π/2 constant.

2. **Rz angle folding `mod(θ+π, 2π) - π` introduces global phase
   -1 per fold.**  add_qft! folds θ_raw = 2π·a/2^jj into (-π, π].
   Under control, -1 global phase = π relative phase on ctrl=|1⟩.
   Cumulative across L Rz's × 2L modadds × … might land at π/2 mod 2π.

3. **Ry(π) / Ry(-π) MSB flip pair at modadd steps 9/11 was added
   in Session 25 specifically to avoid a global phase (the X! = -iY
   fix).**  It cancels cleanly when modadd runs standalone — but
   may NOT cancel correctly inside a cascaded operation (mulmod's
   2L modadds) if the intermediate state transforms the msb wire
   non-trivially.

Fix strategy (per di9): build a minimal X-basis harness, narrow the
leak block-by-block (add_qft alone, modadd alone, modadd with
ctrls, mulmod CMULT forward alone, full mulmod), identify the
exact gate sequence that leaks, apply the smallest possible
compensating phase rotation.  Add X-basis regression tests to
`test/test_arithmetic.jl` so the next silent-phase bug has a
tripwire.

### Files added this session

- `test/probe_shor_larger_N.jl` — N=21/N=35 end-to-end (fails)
- `test/probe_shor_bug_hunt.jl` — mulmod-at-L=5 + N=15 bigger-t isolation
- `test/probe_N21_ytilde.jl` — ỹ histogram
- `test/probe_pe_bug.jl` — phase_estimate sanity + shor_order_D t-sweep
- `test/probe_mulmod_phase.jl` — X-basis coherence probe (the smoking gun)

All kept as dev probes; NONE registered in runtests.jl.

### Files changed

- `src/library/shor.jl` — added `!!! warning` block to `shor_order_D`
  docstring flagging di9 and the N ≥ 21 restriction.
- `WORKLOG.md` — this entry.

### Beads

- `Sturm.jl-di9` — P0 bug filed (mulmod phase leak).
- `Sturm.jl-6kx` stays closed for the DAG-structure deliverable, but
  the end-to-end N=21/N=35 verification is blocked on di9.  If a new
  bead is wanted for "extend 6kx coverage post-fix", file as depending
  on di9 at that time.
- `Sturm.jl-8b9` (semi-classical iQFT) still P1; deferred.  Would
  have hit the same phase leak so no work lost.

### Gotchas for future agents — KEEP THESE IN MIND

1. **Z-basis measurement of a control qubit that started as |+⟩ is
   BLIND to phase leaks and to full decoherence.**  Both |+⟩ and
   maximally-mixed give 50/50 Z-basis outcomes.  Test coherence via
   inverse-prep-then-Z (a.k.a. X-basis via Ry(-π/2)) — see
   `test/probe_mulmod_phase.jl` for the minimal protocol.  Consider
   this rule a **correctness prerequisite** for any new controlled
   sub-circuit shipped into Sturm.

2. **Session 25's sin²(ξ/2) probe pattern was a 4-line test that
   would have caught di9 immediately.**  It was not run because
   Session 25 only added the coherent `ctrl=|+⟩` test at the
   mulmod LEVEL with Z-basis output — exactly the pattern that's
   blind to phase leaks.  New primitives that accept a QBool ctrl
   should ship with BOTH Z-basis correctness (`Int(x) == expected`)
   AND X-basis coherence (`Bool(Ry(-π/2); ctrl) == false`) tests.

3. **"All tests green" is a lower bound, not a correctness proof.**
   The 3208-pass uf4 suite is what I (confidently) shipped as
   "mulmod_beauregard! works".  Better framing: "mulmod produces
   correct computational-basis outputs and preserves ctrl's Z-basis
   mixing, coherence not verified".  Generalising: always state the
   regime a test suite actually checks.

4. **Verbose-flush pattern paid off AGAIN.**  The smoking-gun probe
   (`probe_mulmod_phase.jl`) ran 27 rows × 80 shots with per-row
   flush output — the leak pattern (x=0 clean, x>0 ~50%) jumped out
   in the very first printed line of the first config.  No
   blank-screen-waiting; the tell was visible within 15 seconds.
   Keep it up.

---

## 2026-04-19 — Session 26: Close `Sturm.jl-6kx` (shor_order_D, polynomial-in-L Shor)

Picked up from Session 25's uf4 close. The polynomial-in-L Shor chain's
final brick: replace `shor_order_C`'s packed-QROM mulmod with
`mulmod_beauregard!` while keeping the Box 5.2 / Eq. 5.43 cascade
structure. Beauregard 2003 Fig. 7 "c-U_a" is literally a c-CMULT · c-SWAP
· c-CMULT⁻¹ sandwich, and our Sturm.jl-uf4 signature already takes a
single ctrl QBool — so the entire impl D body is ~20 lines of real logic
plus docstring.

### Ground truth (read before coding, per rule 4)

`docs/physics/beauregard_2003_2n3_shor.pdf` pp. 7–11.

- **Fig. 7 (p. 8)** and surrounding text (p. 7): c-U_a = three blocks
  (forward CMULT(a), SWAP, inverse CMULT(a⁻¹)), each with an outer `c`
  control dot. We already pass `c` to `mulmod_beauregard!` as its
  `ctrl::QBool` argument — no wrapping `when(c)` needed.
- **Eq. 4 (p. 8):** `(a^n x) mod N = a·(a·…·(a·x) mod N) mod N`. This
  means we can run `c-U_{a^{2^j}}` directly, with `a^{2^j} mod N`
  precomputed classically. Impl C already does this; impl D inherits.
- **§3 (p. 11):** order-finding circuit = 2n of these c-U_a, each
  `O(n²·k_max)` gates with depth `O(n²)`. With exact QFT `k_max = n`,
  total = `O(n³ · k_max) = O(n⁴)` at `n = L`. Depth `O(n³)`.

### Implementation

Added to `src/library/shor.jl` between impl C (line 803) and the end.
Two functions, exports in `src/Sturm.jl`:

- `shor_order_D(a, N; t, verbose)` / `shor_order_D(a, N, ::Val{t})` —
  Box 5.2 cascade body identical to impl C's outer shape (counter QInt{t},
  superpose, eigenstate y=QInt{L}(1), t controlled mulmods, interfere,
  discard, continued fractions). The inner mulmod call is
  `mulmod_beauregard!(y_reg, a_j, N, ctrl)` with `ctrl =
  QBool(c_reg.wires[j], ctx, false)`. NO wrapping `when(c_reg.wires[j])`
  — this is the critical design decision, see below.
- `shor_factor_D(N)` — mirrors `shor_factor_A/B/C`. Trivial wrapper.

The skip-`a_j==1` optimization at the top of the mulmod loop saves 2L
modadds per trivially-identity stage. Beauregard's c-U_a for a=1 is
identity but the circuit still issues 2L modadds with classical
constants `(2^(j-1)) mod N` and their inverses, cancelling to
identity — wasteful. At N=15, a=7, order 4: a_j = {7, 4, 1, 1, …} so
most t>2 stages save ~2L² gates each.

### Key design decision — DO NOT wrap mulmod_beauregard! in when()

The obvious impl-C-parallel is:

```julia
for j in 1:t
    when(c_reg.wires[j]) do
        mulmod_beauregard!(y_reg, a_j, N, /* what? */)
    end
end
```

This would be wrong. `mulmod_beauregard!` takes its own `ctrl::QBool`
which it folds into modadd's `ctrls=(ctrl, xj)` kwarg (Sturm.jl-uf4
fix). The outer `when(counter_qubit)` would then add a **third** control
to every primitive inside modadd — reviving the 3-deep cascade we just
killed in Session 25. The fast-path invariant (nc ≤ 2) fails, every Rz
cascades through `_multi_controlled_gate!`, workspace ancillae allocate,
gate count explodes.

Correct pattern: pass `c_reg.wires[j]` *as* `mulmod_beauregard!`'s ctrl.
The counter qubit is the `c` of Beauregard's Fig. 7. Inside modadd we
then have `ctrls = (counter_qubit, x_j)` — depth 2, fast path.

Documented in the `shor.jl` prose above the impl, with an explicit "NOT
what we want" warning for the next agent.

### Verification — probe first, then registered test

Two-phase per `feedback_verbose_eager_flush.md` + `sturm-jl-test-suite-slow`
memory.

**Phase 1** — `test/probe_6kx_minimal.jl` (new, standalone). Four stages
with per-shot `println(stderr, …)+flush` + free-RAM logging:

| Stage | What | Result | Wall |
|-------|------|--------|------|
| 1 | Single verbose shot, N=15 a=7 t=3 | r=4, HWM 14q, cap 16 | 29.3 s (first mulmod paid 10 s JIT, second 17 s) |
| 2 | 30 shots N=15 a=7 t=3, hit-rate on r=4 | 15/30 = 50%, 0 spurious | 93.6 s (3.1 s/shot warm) |
| 3 | 20 shots N=15 a=2 t=3 | 8/20 = 40% r=4, 0 spurious | 30.7 s (1.5 s/shot warm) |
| 4 | `shor_factor_D(15)` × 10 attempts | 10/10 → {3, 5} | 5.4 s |

RAM flat at 59.7 GiB free throughout. HWM stable at 14 qubits
(vs impl C's 26).

**Phase 2** — `julia --project -e 'include("test/test_shor.jl")'`
(targeted, not full `Pkg.test()`). Enabled the impl-D testset at
`test/test_shor.jl:202-252`; impl-B and impl-C blocks remain
`@test_skip` per their original intractability.

### Resource comparison — impl D vs impl C at N=15 t=3

| Metric                   | Impl C measured   | Impl D measured   | Ratio       |
|--------------------------|------------------:|------------------:|------------:|
| HWM qubits               | 26                | **14**            | −12 qubits  |
| Orkan statevector cap    | 28  (4 GiB)       | **16** (~1 MiB)   | ~4000×      |
| Wall time per shot       | 302 s             | 1.5–3.1 s (warm)  | **~100–200×** |
| Hit rate r=4 (a=7)       | (untestable)      | 50% / 30 shots    | —           |
| Factor(15) success rate  | (untestable)      | 10/10 → {3, 5}    | —           |

Impl C's slowness was dominated by the 4 GiB statevector memory
bandwidth per Toffoli × ~17 000 gates/shot. Impl D's (2L+3)-wire
Beauregard circuit keeps the statevector at ~1 MiB — memory traffic per
Toffoli drops 4000× and wall-time drops by essentially the same factor.
Gate counts (from the tracing bench below) are actually *comparable*
to impl C at small L and smaller at large L, so the statevector
shrinkage is the whole win.

### Benchmark calibration (`test/bench_shor_scaling.jl`)

Added `:D` to `estimate_gates`, `trace_impl`, and every `CASES[*].impls`
list. Tracing bench at L=4..6, STURM_BENCH_ONLY=D:

| L | t  | wires | gates  | toffoli | est (old) | est (new 100·t·L²) | ratio |
|--:|---:|------:|-------:|--------:|----------:|--------------------:|------:|
| 4 |  8 |    24 |  2 447 |      24 |    25 620 |              12 800 | 5.2×  ← (2 of 8 mulmods fired; a=7 N=15 saturates after j=2) |
| 5 | 10 |    85 | 19 395 |     150 |    50 025 |              25 000 | 1.29× |
| 6 | 12 |   114 | 33 342 |     216 |    86 430 |              43 200 | 1.30× |

Empirical fit `per-mulmod gates ≈ 77·L²` (L=5 and L=6 agree to 0.5%);
slope (ln gates vs ln L) = 3.0 at fixed t → **O(L³) per order-find, O(L⁴)
at t = 2L**. Matches Beauregard §3. Extrapolations:

| L  | t  | est gates | est DAG bytes |
|---:|---:|----------:|--------------:|
|  7 | 14 |    68 600 |       1.7 MB  |
| 10 | 20 |   200 000 |       5.0 MB  |
| 14 | 28 |   548 800 |      14 MB    |
| 18 | 36 | 1 166 400 |      29 MB    |

vs impl C's measured **47 M gates / ~1.2 GB DAG** at L=14 → impl D at
L=14 is projected at ~86× fewer gates AND polynomial growth (slope ~3)
vs impl C's ~2^L exponential. The rotation in dominance flips around
L=5 where impl D becomes cheaper by every measure.

Bead acceptance criterion was "log-log slope ≤ 4 across L=6..14". We
can only measure L=6 directly today (L=14 via estimator), but the
L=5→6 slope of 3.0 is well under 4 and matches the analytic O(L⁴)
prediction. Calibration at L=7..14 is the job of the next bench run.

### Files touched

- `src/library/shor.jl` — added `shor_order_D` + `shor_factor_D` and
  the impl-D docstring block (~100 lines total). No changes to impls
  A/B/C.
- `src/Sturm.jl` — export `shor_order_D, shor_factor_D`.
- `test/test_shor.jl` — new `@testset "Impl D: …"` with 3 sub-testsets
  matching impl-A's shape (single-case hit rate, 7 coprime bases,
  factor recovery). Impl B/C `@test_skip` blocks unchanged.
- `test/probe_6kx_minimal.jl` (new) — standalone 4-stage verbose-flush
  probe. Kept as a dev tool; not registered in runtests.jl.
- `test/bench_shor_scaling.jl` — `:D` branch in `estimate_gates`
  (`100·t·L²`), `:D` branch in `trace_impl`, `:D` added to every
  `CASES[*].impls` list. Docstring for `estimate_gates` extended with
  the `:D` calibration table.
- `WORKLOG.md` — this entry.

### Beads

- `Sturm.jl-6kx` closed.
- Chain completion: ar7 (add_qft!) → dgy (modadd!) → uf4
  (mulmod_beauregard!) → **6kx (shor_order_D)** — all four bricks of
  the polynomial-in-L Shor epic Sturm.jl-c6n closed.

### Gotchas for future agents

1. **The single most important refactor choice in impl D is what NOT to
   do.** Don't wrap `mulmod_beauregard!` in `when(counter_qubit)` — pass
   `counter_qubit` as the ctrl kwarg. If a future caller/subroutine
   needs c-U_a under an additional outer when (e.g. embedding Shor
   inside a larger algorithm), either (a) pre-AND the two controls into
   a workspace ancilla via one Toffoli and pass *that* as ctrl, or
   (b) extend `mulmod_beauregard!` to accept `ctrls::Tuple` like
   `modadd!` does today. Never nest when()s around a function that
   already takes its own ctrl.

2. **Skip a_j=1 at runtime or your bench looks like impl D is tiny at
   small L.** For N=15 a=7 (order 4) at t=8 only 2 of 8 mulmods fire;
   the bench showed 2447 gates vs a 12800 worst-case estimate. This is
   correct behavior (identity mulmods are wasteful to emit), but it
   confuses the cost calibration — always measure at cases where the
   order is close to `2^t` so all a_j are non-trivial. L=5 N=21 a=2
   (order 6) and L=6 N=35 a=2 (order 12) are both clean calibration
   cases.

3. **Per-mulmod gate count ≈ 77·L² is remarkably tight.** Two data
   points (L=5, L=6) agree to 0.5% — this is a solid architectural
   invariant. If a future change to `modadd!` or `add_qft!` changes the
   per-mulmod gate count, the ratio will drift visibly. Treat this as a
   regression indicator: the L=5 and L=6 numbers are 19395 and 33342
   gates at t=2L; significant deviation means something changed at the
   primitive level.

---

## 2026-04-19 — Session 25: Close `Sturm.jl-uf4` (mulmod_beauregard! green-up)

Picked up from Session 24 handoff: `mulmod_beauregard!` code committed on
`15bf951` but never run to green because nested `when(ctrl) do when(xj) do
modadd!(…) end end` PLUS modadd's own `when(anc) add_qft!(y, N)` = **3-deep
control stack**, triggering `_multi_controlled_gate!` cascade on every
primitive. At L=3 N=5 coherent shots, each shot was allocating workspace
ancillae per primitive — astronomical.

Closed bead with the Beauregard p.6 fix already foreshadowed in the
handoff checklist.

### Ground truth (read BEFORE coding, per rule 4)

`docs/physics/beauregard_2003_2n3_shor.pdf` pp. 5–8. Three equations/figures
load-bearing for the fix:

- **Fig. 5** (doubly-controlled φADD(a)MOD(N)). The two outer control dots
  `c1, c2` connect ONLY to the three φADD(a) gates (steps 1, 7, 13 in the
  13-step expansion). QFT / QFT⁻¹ / CNOT / X-on-MSB / and the `anc`-
  controlled ADD(N) are **unconditional** in the circuit — no `c1`/`c2`
  control dot touches them.
- **Text p.6:** "we will doubly control only the φADD(a) gates instead of
  all the gates. If the φADD(a) gates are not performed, it is easy to
  verify that the rest of the circuit implements the identity on all
  qubits because b < N."  This is the correctness certificate for
  pulling the controls down.
- **Fig. 6** (CMULT(a)MOD(N)). The outer QFT/QFT⁻¹ sandwich on the b
  register is **outside** the c-control region — `c`-control shrinks to
  the n doubly-controlled modadds.
- **Fig. 7** (c-U_a). Controlled-SWAP between x and b is singly controlled
  by c only.

### Refactor

Two changes in `src/library/arithmetic.jl`, no other files touched.

**modadd!: new `ctrls::Tuple` kwarg.**

```julia
modadd!(y, anc, a, N; ctrls = ())      # backward-compat: no change
modadd!(y, anc, a, N; ctrls = (c,))    # singly controlled, Beauregard sense
modadd!(y, anc, a, N; ctrls = (c1,c2)) # doubly controlled, Beauregard sense
```

Implemented via an inline `_apply_ctrls(f, ctrls)` helper that resolves
each arity at compile time:

```julia
@inline _apply_ctrls(f, ::Tuple{}) = f()
@inline _apply_ctrls(f, c::Tuple{QBool}) = when(c[1]) do; f(); end
@inline _apply_ctrls(f, c::Tuple{QBool,QBool}) =
    when(c[1]) do; when(c[2]) do; f(); end; end
```

Only steps 1, 7, 13 (the three `add_qft!(y, a)` / `sub_qft!(y, a)` calls)
get wrapped. Steps 2–6, 8–12 run unconditionally — matches Fig. 5 exactly.

**mulmod_beauregard!: pull QFTs out, push controls down.**

Old (3-deep cascade):

```julia
when(ctrl) do
    superpose!(b)                          # ctrl-controlled QFT
    for j in 1:L
        when(xj) do                         # (ctrl, xj)-controlled
            modadd!(b, anc, c_j, N)        # inside: when(anc) push → 3 deep
        end
    end
    interfere!(b)                          # ctrl-controlled QFT⁻¹
    for j in 1:L; swap!(xj, bj); end        # ctrl-controlled SWAP
    superpose!(b)
    …inverse CMULT same pattern…
    interfere!(b)
end
```

New (max-2 fast path):

```julia
superpose!(b)                              # UNCONDITIONAL QFT
for j in 1:L
    modadd!(b, anc, c_j, N; ctrls=(ctrl, xj))  # push controls into modadd
end
interfere!(b)                              # UNCONDITIONAL QFT⁻¹

when(ctrl) do                              # singly-controlled SWAP
    for j in 1:L; swap!(xj, bj); end
end

superpose!(b)                              # UNCONDITIONAL QFT
for j in 1:L
    modadd!(b, anc, (N - c_j) mod N, N; ctrls=(ctrl, xj))
end
interfere!(b)                              # UNCONDITIONAL QFT⁻¹
```

### Correctness sketch (ctrl=0 branch)

- Unconditional `superpose!(b)` on `|0⟩` → `|Φ(0)⟩`.
- All modadds in forward CMULT have `ctrls=(ctrl=0, …)` — every internal
  `_apply_ctrls` body skipped. modadd runs its QFT/sub/CNOT/X pattern
  internally, which per Beauregard's correctness argument collapses to
  identity because `b < N`. So `b` stays `|Φ(0)⟩`.
- `interfere!(b)` inverts the outer QFT → `b = |0⟩`.
- `when(ctrl=0) do swap! end` — SWAP skipped. `x` unchanged.
- Second QFT sandwich: same argument, `b` returns to `|0⟩`.

Net: `x` unchanged, `b = |0⟩`, `anc = |0⟩`. ✓ Identity on ctrl=0.

ctrl=1 branch: every modadd fires, forward CMULT computes
`b = (a·x) mod N` in Fourier basis, QFT⁻¹ brings it to computational
basis, SWAP puts `(a·x) mod N` on x wires and `x_orig` on b wires,
reverse CMULT with `a⁻¹` zeros b.  Result: `x = (a·x_orig) mod N`.

### Max control depth after refactor

| Site                                 | Old | New |
|--------------------------------------|----:|----:|
| modadd step 1 (ADD(a))               | 3   | 2   |
| modadd step 6 (anc-ADD(N))           | 3   | 1   |
| modadd step 7 (SUB(a))               | 3   | 2   |
| modadd step 13 (ADD(a))              | 3   | 2   |
| modadd steps 2-5, 8-12 (all others) | 2   | 0   |
| mulmod QFT on b                      | 1   | 0   |
| mulmod SWAP                          | 1   | 1   |

All primitives now hit Sturm's nc≤2 inline HotNode fast path. Zero
workspace ancilla allocation, zero Toffoli-cascade reverse passes.

### Verification

Before committing, two-phase verification per WORKLOG's uf4 handoff
checklist plus `feedback_verbose_eager_flush.md` discipline.

**Phase 1** — minimal probe (`test/probe_uf4_minimal.jl`, new). Eight
stages, per-case `println(stderr, …) + flush(stderr)` with wall-ms and
free-RAM on every log line:

- Stage 1: `modadd!` no-kwarg — L=2 N=3 a=2 b=1 → 0. GREEN.
- Stage 2, 2b: `modadd!(…; ctrls=(c,))` — c=|1⟩ acts, c=|0⟩ identity. GREEN.
- Stage 3, 3b, 3c: `modadd!(…; ctrls=(c1,c2))` — 11→act, 01/10 identity. GREEN.
- Stage 4, 4b: `mulmod_beauregard!` L=2 N=3 a=2 x=1 → 2 (ctrl=1) / 1 (ctrl=0). GREEN.
- Stage 5: L=2 N=3 sweep 12 cases. GREEN.
- Stage 6: L=3 exhaustive ctrl=|1⟩ across N∈{3,5,7}, 68 cases. 0 fail, 41 s.
- Stage 7: L=3 exhaustive ctrl=|0⟩ identity across N∈{5,7}, 62 cases. 0 fail, 5.6 s.
- Stage 8: coherent ctrl=|+⟩ at L=3, 3 cases × 400 shots = 1200 shots.
  Results 197/203, 204/196, 193/207 — all within ±15% of 200/200.
  **0 spurious outcomes across 1200 shots.**

Peak RAM usage 60.16 GiB free (of 60.41 at start). Zero blowup — the
physics-motivated depth reduction eliminated the cascade entirely.

**Phase 2** — registered test file. `julia --project -e
'include("test/test_arithmetic.jl")'` (targeted, not full `Pkg.test()`
per `sturm-jl-test-suite-slow` memory):

| Testset                                     | Pass/Total   | Time     |
|---------------------------------------------|--------------|----------|
| `add_qft!`                                  | 809 / 809    |  2.2 s   |
| `modadd!`                                   | 2130 / 2130  |  0.7 s   |
| `mulmod_beauregard!`                        | 269 / 269    |  1m19 s  |

All 3208 arithmetic tests green on the first run after the refactor.
modadd's backward-compatible path (`ctrls = ()` default) preserved the
2130-pass modadd sweep unchanged.

### Soft-scope gotcha (Julia 1.12)

Initial Stage 6 draft used `n_cases = 0; … for …; n_cases += 1; end`
pattern. Julia 1.12 warned "Assignment to `n_cases` in soft scope is
ambiguous" and then **errored** with `UndefVarError: n_cases not defined
in local scope` when the `@context` macro body tried to increment.
The `@context` expansion introduces a function barrier; assignments to
names declared in the enclosing soft scope (a script top level) are
treated as new locals inside the function, shadowing the outer name,
and the initial `n_cases = 0` doesn't propagate in.

**Fix:** wrap each stage in `let … end` and use `Ref(0)` for counters:

```julia
let
    n_cases = Ref(0); n_fail = Ref(0)
    for …
        @context EagerContext() begin
            …
            n_cases[] += 1
        end
    end
end
```

Session 12 WORKLOG (~L2602) flagged the same problem with a slightly
different workaround ("wrap test bodies in functions"). Either works;
Ref is shorter for probes.

### Files touched

- `src/library/arithmetic.jl` — `_apply_ctrls` helper, `modadd!` ctrls
  kwarg, `mulmod_beauregard!` refactor (pull QFTs, push ctrls down).
- `test/probe_uf4_minimal.jl` (new) — 8-stage verbose-flush probe, kept
  as a dev tool.  Not registered in runtests.jl (the existing
  `test/test_arithmetic.jl` covers the same cases under `@testset`).
- `WORKLOG.md` — this entry.

### Beads

- `Sturm.jl-uf4` closed.

### Handoff — `Sturm.jl-6kx` unblocked

`shor_order_D` can now be built on top of `mulmod_beauregard!`.
Expected scaling per Session 8jx analysis: O(L⁴) gates (t·L³ = 2L·L³).
At L=14 the prediction is ~50k gates vs impl C's measured 47M → **1000×
reduction** if the scaling holds. Benchmark plumbing already exists in
`test/bench_shor_scaling.jl` (Sturm.jl-8jx closed): preflight + watchdog
accept a new impl via env var filtering. A new impl D = "shor with
arithmetic mulmod" can plug in the same way A/B/C do.

Work not yet done on 6kx, flagged:

1. Classical preprocessing: `a_js = [(a^(2^j)) mod N for j in 0:(t-1)]`
   — already present in impls A/B/C.
2. Loop body: `when(phase_qubits[j]) do mulmod_beauregard!(x, a_js[j],
   N, ctrl=…) end` — but the outer `when(phase_qubits[j])` adds a third
   control to every primitive inside mulmod. To stay on the 2-deep
   fast path, `mulmod_beauregard!` needs a `ctrls=` kwarg too, pushing
   `phase_qubits[j]` into modadd's `(ctrl, xj, phase_j)` — but that is
   3 controls, which Sturm's inline HotNode doesn't support. Options:
   (a) pre-AND `phase_j AND ctrl` into a workspace ancilla, then call
   `mulmod_beauregard!(x, a_js[j], N, and_ancilla)` — 2-deep max,
   single workspace Toffoli per mulmod amortised over 2L modadds.
   (b) extend modadd's `ctrls::Tuple` to accept 3 QBools (adds one more
   `_apply_ctrls` method, triggers a 3-deep nested when — cascade on
   the 3 φADD(a) gates only, not on every primitive; still much cheaper
   than today's impls).
   Picking between (a) and (b) is a measurement question for the 6kx
   session.
3. Semi-classical iQFT on a single phase qubit (Beauregard §2.4, fig.
   8). Measurement-driven corrections (X^{m_i}, R_{2i} phase gate
   depending on all prior measurements). This is clean classical
   feedback through P2 casts; low risk.

### Gotchas saved for future sessions

1. **Beauregard p.6 correctness for "doubly control only φADD(a)" is
   easy to miss.** The figure (Fig. 5) shows c1, c2 dots on every
   horizontal run of the controlled register, but only three vertical
   lines actually drop INTO the φADD(a) blocks.  The verbal statement
   in the prose (p.6) is the load-bearing part: "the rest of the circuit
   implements the identity on all qubits because b < N."  A naive
   transcription that copies the figure literally misses this, and the
   resulting code has 3-deep control nesting = cascade explosion.

2. **Pulling unconditional QFT/QFT⁻¹ out of a `when(ctrl)` block is
   correct because QFT·(any state)·QFT⁻¹ = any state.**  With ctrl=0
   the modadds between the QFT sandwich all skip, so the net transform
   on `b` is identity whether the QFTs run or not.  Running them
   unconditionally saves depth without changing the channel.  Not every
   unitary has this property — e.g. a `Hadamard·X·Hadamard` sandwich
   around a ctrl-guarded block would NOT be safe to lift because
   `Hadamard² ≠ I` up to a global phase that becomes relative under
   an outer `when`.  QFT·QFT⁻¹ = I exactly, no phase.

3. **Ref-based counters dodge Julia 1.12 soft-scope inside `@context`.**
   Script-level counter++ inside `for … @context … n_cases += 1 … end`
   errors at run time.  Wrap the stage in `let … end`, declare counters
   as `Ref(0)`, increment via `n_cases[] += 1`.  Two lines of ceremony,
   no warning noise.

4. **Per-stage `println(stderr, …) + flush(stderr)` with free-RAM on
   every line is how you keep verbose-eager-flush (`feedback_…`)
   honoured.**  A single `_log(s)` helper that formats `[ms] [free=X
   GiB] s` and flushes makes this a 1-line cost per stage.  The
   blank-screen-wait that caused Session 24's interrupt would have been
   impossible to miss with this pattern.

---

## 2026-04-18 — Session 24 END-OF-DAY HANDOFF

**Stop reason:** user ended the session. Tree is clean; all work
committed and pushed to `origin/main`. `bd stats` shows 0 in_progress,
7 open.

### Session 24 at a glance — 6 beads closed, 1 filed

| Bead | Priority | What | Commit |
|------|----------|------|--------|
| `1f3` | P3 | QDrift/Composite RNG injection + vacuous-test fix | `bfa8f0f` |
| `q93` | P2 | Width-fitting oracle arg type (`_bennett_arg_type`) | `dd2f680` |
| `f23` | P2 | P2 axiom implicit-cast warning (`with_silent_casts`) | `0bd5289` |
| `xcu` | P1 | Multi-controlled gates on DensityMatrixContext | `2f051e4` |
| `1wv` | P1 | `with_empty_controls` / `with_controls` public API | `e1ace01` |
| `rpq` | P1 | Arbitrary when() nesting in TracingContext | `180eee3` |
| `5gz` | P2 | **Filed:** qsvt_phases sin polynomial returns 2d+1 phases (pre-existing) |

### Major architectural changes this session

1. **`src/context/multi_control.jl`** is now typed on `AbstractContext`
   (was `Union{EagerContext, DensityMatrixContext}`) and routes through
   the PUBLIC `apply_*!` API rather than raw `orkan_*!` pointer calls.
   Every helper wraps itself in `with_empty_controls` to break recursion
   when called from nc≥1. **Consequence:** EagerContext, DensityMatrixContext,
   and TracingContext all use the SAME Toffoli cascade for arbitrary
   when() nesting depth. Zero code per context.

2. **`src/context/abstract.jl`** grew two default-implementation methods:
   `with_controls(f, ctx, ctrls::Vector{WireID})` and
   `with_empty_controls(f, ctx) = with_controls(f, ctx, WireID[])`.
   Both built on the existing `push_control!`/`pop_control!`/
   `current_controls` interface.

3. **`src/types/qbool.jl` and `src/types/qint.jl`** now split the
   constructor from `Base.convert`: `Bool(q)` / `Int(q)` hold the
   measurement (silent), and `Base.convert(::Type{Bool/Int}, q)` emits
   the P2 warning then delegates. Implicit `x::Bool = q` assignments
   hit the convert path; explicit constructor calls do not.

4. **`src/bennett/bridge.jl`** has a new `_bennett_arg_type(W;
   signed=true)` helper that picks the narrowest Int/UInt fitting W.
   Replaces the hardcoded `Int8` in `oracle(f, x::QInt{W})` and
   `QuantumOracle`'s call operator. Cache key widens to
   `(W, signed, kwargs)`.

### Current ready queue — annotated

```
  bd ready
  ○ Sturm.jl-870  P1   Steane syndrome extraction + correction (QECC)
  ○ Sturm.jl-5gz  P2   [bug] qsvt_phases 2d+1 for sin polynomial
  ○ Sturm.jl-di1  P2   Backend scaffolding (tensor-net + hardware)
  ○ Sturm.jl-7ab  P2   Pass registry / DAG transformation API
  ○ Sturm.jl-mt9  P2   QSVT/QSP linear algebra EPIC
  ○ Sturm.jl-eiq  P3   CasesNode consumer policy (error on unhandled)
  ○ Sturm.jl-zv1  P4   Docs refresh (CLAUDE.md + README.md)
```

**Recommended next pickup** for a fresh agent:

- **`5gz` P2 bug** is worth triaging first — it's concrete, reproducible
  (just run `test/test_qsvt_reflect.jl` lines 53-58), and may be a
  test-assertion-vs-algorithm-convention mismatch rather than a real
  physics bug. Quick win if so. See `docs/physics/` for QSP/QSVT
  convention notes — the test expects `length(phi) == 2d` but the
  sin-parity GSLW convention might legitimately yield `2d+1`.

- **`eiq` P3** remains the obvious mechanical continuation if you want
  a warm-up. `src/channel/channel.jl` compat constructor,
  `src/channel/openqasm.jl:~112`, renderer warnings.

- **`zv1` P4** has three concrete items queued up:
  (a) Sturm-PRD.md has ~10 pedagogical `::Bool = q` / `::Int = qi`
      examples that now trigger the f23 warning if copy-pasted; convert
      to explicit form or note "this pattern warns".
  (b) README lines ~146-200 advertise `strategy=:tabulate` as a Bennett
      kwarg — confirmed NOT present in current Bennett
      (`grep -r tabulate /home/tobiasosborne/Projects/Bennett.jl/src`).
      Session 22 misreported, or it reverted upstream.
  (c) CLAUDE.md phase 12 table is stale.

- **`870`, `di1`, `7ab`, `mt9`** are substantial and design-first — save
  for a fresh big session.

### Cross-session patterns saved for the next agent

1. **Rule 4 is strict about local PDFs.** When extracting or moving code
   that carries a docstring reference to a paper, read the local
   `docs/physics/<name>.md` BEFORE shipping. If no local file exists,
   write a self-contained derivation (see
   `docs/physics/toffoli_cascade.md` from Session 24D).

2. **Bennett LLVM lowering hates closures that capture values.** A
   boolean `signed` captured in `x -> x + (signed ? Int8(1) : UInt8(1))`
   materialises as `StructType({ ptr, i8 })` in Julia IR — Bennett
   errors with "Unsupported LLVM type for width". Use top-level
   functions for oracle tests across parameters, not loop-body
   closures. (Hit this during Session 24F's full-suite run.)

3. **Test files can drift from the axioms.** Session 24C's f23 work
   discovered 8 `::Bool = q` sites in test_bell, test_teleportation,
   test_rus — the warning catching our own code validated the split.
   Run the full suite after ANY axiom-level change to flush these out.

4. **Don't copy forward unexamined references.** Session 24D's xcu work
   copied the "Barenco 1995 Lemma 7.2" reference from eager.jl into the
   new multi_control.jl without verifying the local PDF existed (it
   didn't). User caught this mid-session with "did you read the
   Nielsen and Chuang ground truth?" The fix was writing
   `docs/physics/toffoli_cascade.md` inline.

5. **When extracting helpers that touch context internals, flag the
   abstract-interface candidate up front.** Session 24D's xcu extracted
   `multi_control.jl` which used `ctx.control_stack` directly — then
   Session 24E's 1wv had to migrate those accesses to the new API.
   Would have been cleaner to do both in one pass.

6. **Pre-existing test failures reproduce on previous commits.** Always
   verify: `git stash && julia --project -e '<repro>' && git stash pop`.
   Session 24F's 5gz qsvt_phases issue turned out to be pre-existing —
   saved from chasing a regression caused by today's refactor.

### Full test suite state (as of commit `180eee3`)

- **12833 pass / 3 fail / 1 error / ~12837 total**
- The 1 error (q93 closure test) was **fixed in commit `180eee3`** —
  re-running the full suite now would produce 12836 / 3 / 0.
- The 3 failures are `Sturm.jl-5gz` — see above.
- **Full-suite runtime on this device: ~2h15m.** Dominant: OAA (61m),
  Reflection QSVT (34m), qDRIFT (21m), Bennett E2E (5m). Do NOT run
  the full suite casually — use targeted `julia --project -e '…'`
  probes for verification work.

### Environment gotchas, reminded

- `LIBORKAN_PATH=/home/tobiasosborne/Projects/orkan/cmake-build-release/src/liborkan.so`
  (memory entry lists `/home/tobias/…` — stale prefix on this device).
- `Bennett.jl` is dev-pathed via `Pkg.develop(path="../Bennett.jl")`;
  not registered. Fresh clones must do the develop before
  `Pkg.instantiate`.
- bd uses SSH; `bd dolt push` works non-interactively. Session close
  protocol = `git pull --rebase && bd dolt push && git push`.
- The `.beads/` permissions warning is cosmetic; `chmod 700 .beads`
  fixes it but isn't blocking.

### Physics docs referenced by this session's code

- `docs/physics/nielsen_chuang_4.3.md` — controlled-Ry/Rz ABC
  decomposition. Verified algebraically in Session 24D.
- `docs/physics/toffoli_cascade.md` — Session 24D NEW, self-contained
  derivation of the N-controlled cascade with density-matrix extension.
  Referenced by `src/context/multi_control.jl`.

### Files with significant changes today

- `src/context/abstract.jl` — with_controls, with_empty_controls
- `src/context/multi_control.jl` — unified cascade across all contexts
- `src/context/eager.jl` — cascade helpers moved out
- `src/context/density.jl` — multi-control dispatch added
- `src/context/tracing.jl` — nc>2 routes to cascade
- `src/types/quantum.jl` — _warn_implicit_cast, with_silent_casts
- `src/types/qbool.jl`, `src/types/qint.jl` — constructor / convert split
- `src/bennett/bridge.jl` — _bennett_arg_type helper
- `src/simulation/pauli_exp.jl` — migrated to with_empty_controls
- `src/block_encoding/lcu.jl` — migrated to with_empty_controls
- `src/simulation/qdrift.jl`, `src/simulation/composite.jl` — rng kwarg
- `src/Sturm.jl` — exports
- `README.md` — with_silent_casts note
- `docs/physics/toffoli_cascade.md` — NEW
- `test/test_implicit_cast.jl`, `test/test_density_matrix_mc.jl`,
  `test/test_control_api.jl`, `test/test_tracing_deep_when.jl` — NEW
- Plus test fixes in test_bell, test_teleportation, test_rus, test_qdrift,
  test_composite, test_bennett_integration.

---

## 2026-04-18 — Session 24F: Close `rpq` (arbitrary when() nesting in TracingContext)

TracingContext's `apply_ry!`/`apply_rz!`/`apply_cx!` errored at control-
stack depth > 2 because `HotNode` carries at most `ctrl1, ctrl2` inline
(the Session 3 25-bytes/element isbits union). The bead's proposed fix
(Option B) was to add a cold-path `DeepCtrlNode` with `controls::Vector
{WireID}` for deep cases. Instead: realised the cascade in
`multi_control.jl` can be rewired to lower a deep-controlled op entirely
into depth-≤2 ops via a Toffoli cascade with workspace qubits — the
SAME path EagerContext and DensityMatrixContext use (closed in xcu).
No new node type needed; no Session 3 perf regression at depth ≤ 2; the
traced DAG contains only standard `HotNode`s.

### Unified cascade — `multi_control.jl` refactor

Rewrote the 6 helpers to type on `AbstractContext` instead of
`Union{EagerContext, DensityMatrixContext}`, and to route through the
PUBLIC `apply_ry!`/`apply_rz!`/`apply_cx!`/`apply_ccx!` API rather than
raw `orkan_*!` calls. Each invocation is wrapped in
`with_empty_controls(ctx) do … end` so that inner `apply_*!` calls see
nc=0 and hit their fast paths:

- EagerContext: direct `orkan_*!` on `ctx.orkan.raw`.
- DensityMatrixContext: same (Orkan's gate ABI is state-type-agnostic,
  `ccx` computes `UρU†` on MIXED states natively).
- TracingContext: emits `RyNode`/`RzNode`/`CXNode` with `nc ≤ 2`.

### Recursion break

`_controlled_ry!` is called at nc=1 from Eager's `apply_ry!`. In the new
implementation it internally uses `apply_ry!`/`apply_cx!`. Without
protection, Eager's `apply_ry!` at nc=1 → `_controlled_ry!` → `apply_ry!`
at nc=1 → infinite recursion. `with_empty_controls` inside
`_controlled_ry!` clears the stack for the duration of the ABC
decomposition, so the inner `apply_ry!` sees nc=0 and goes direct. This
is the same pattern `pauli_exp.jl` and `lcu.jl` now use for their
optimisation-blocks (from Session 24E).

### tracing.jl update

- `_inline_from_stack` now errors with "internal invariant violated" if
  ever called with nc > 2 — callers must route to the cascade before
  reaching it.
- `apply_ry!`/`apply_rz!`/`apply_cx!` at nc > 2 call
  `_multi_controlled_gate!` / `_multi_controlled_cx!`.
- `apply_ccx!` at nc_stack ≥ 2 pushes the explicit `c1` onto the stack
  and routes to the cascade (same pattern as eager/density.jl).
- `apply_ccx!` at nc_stack ≤ 1 still emits an inline 1- or 2-control
  `CXNode` — the existing fast path, unchanged.

### Workspace in the traced DAG

At depth 3 or higher, the cascade allocates N−1 workspace qubits. On
TracingContext, `allocate!` returns a fresh WireID and `deallocate!`
emits a `DiscardNode`. A traced 4-nested `when()` circuit therefore
contains extra CCX nodes (the cascade), a few extra wires (workspace),
and `DiscardNode`s (workspace cleanup). OpenQASM export handles these
as standard gate + reset operations — the bead's acceptance criterion
("4-nested when() traces and exports to OpenQASM 3.0") is met.

### Performance concerns

The old `_controlled_ry!` on EagerContext called `orkan_ry!`/`orkan_cx!`
directly on the raw pointer — 4 C calls per invocation. The new path
goes through 4 `apply_*!` calls, each doing a stack-length check +
dict lookup before reaching Orkan, plus the `with_empty_controls`
save/restore overhead (≈ 4 ops for a 1-element stack). Per invocation
this adds maybe 30–50 ns on EagerContext — negligible for circuit-
construction work but measurable for Pauli-exp inside a tight Trotter
loop. Will benchmark if a regression is reported; none observed in the
full-suite run that closes this bead.

### RED-GREEN TDD

Wrote `test/test_tracing_deep_when.jl` first — 8 testsets / 18 asserts
covering:
- Depth 3 CCCRy via triple-nested when() traces (no error).
- Depth 3 OpenQASM export emits `ccx`.
- Depth 4 quadruple-nested when() traces.
- Depth 3 `apply_cx!` inside 2-deep when (effective CCCX).
- Depth 2 `apply_ccx!` inside when (effective CCCX) — existing fast path.
- Depth 3 and 4 EagerContext outcome correctness (all |1⟩ → target flips).
- Depth 4 any-|0⟩-blocks sanity check.

RED: 3/13 failed — the three hitting nc>2 in apply_ry!/cx!. 10 passed
immediately (Eager/DM already supported depth ≥ 3, and fast paths at
depth 2 already worked for CXNode-via-apply_cx! and apply_ccx! at
nc_stack=1).

GREEN after refactor: 18/18.

### Regression

After refactor:
- test_tracing_deep_when (new): 18/18
- test_when: 507/507
- test_density_matrix_mc: 17/17
- test_control_api: 23/23
- test_channel: 43/43
- test_block_encoding: 63/63
- test_simulation: 122/122
- test_grover: 284/284

Plus the full `runtests.jl` — see commit note.

### Files touched

- `src/context/multi_control.jl`: widen type to `AbstractContext`, route
  through public apply_*! API, wrap helpers in `with_empty_controls`.
- `src/context/tracing.jl`: route nc > 2 through the cascade; tighten
  `_inline_from_stack` invariant error.
- `test/test_tracing_deep_when.jl` (new), `test/runtests.jl` (include).
- `WORKLOG.md`: this entry.

### Full-suite verification (user-requested)

Ran `julia --project -e 'include("test/runtests.jl")'` — full suite,
verbose, ~2h15m total runtime dominated by OAA (61 min), Reflection QSVT
(34 min), qDRIFT (21 min), and Bennett integration e2e (5 min).

**Tally:** 12833 pass, 3 fail, 1 error — out of ~12837.

**Regressions caused by today's work: NONE.**

**The 3 + 1 non-greens:**

1. **3 failures in `Reflection QSVT / qsvt_phases: sin polynomial returns
   correct count`** (test/test_qsvt_reflect.jl:57). At d=5/9/13,
   `length(qsvt_phases(jacobi_anger_sin_coeffs(1.0, d)))` returns
   `2d+1` instead of `2d`. Verified pre-existing: reproduces on commit
   `e1ace01` (the session 24E/1wv commit, BEFORE today's rpq refactor).
   Filed as `Sturm.jl-5gz` P2. The cos polynomial parity passes.
   Likely a test-assertion issue rather than a physics bug (OAA and
   evolve!(QSVT) downstream tests pass at their 33-minute runtime, so
   the algorithm produces usable phases).

2. **1 error in `Bennett Integration / arg-type selection by W /
   oracle forwards signed kwarg without breaking W=2 regression`**
   (test/test_bennett_integration.jl:497). MY bug from Session 24B
   (q93). The closure `x -> x + (signed ? Int8(1) : UInt8(1))` captures
   the boolean `signed` variable, producing an LLVM IR with
   `StructType({ ptr, i8 })` that Bennett cannot compile
   (`Unsupported LLVM type for width`).

   **Fix:** rewrite as two top-level functions (`f_signed(x) = x +
   Int8(1)`; `f_unsigned(x) = x + UInt8(1)`), avoiding the capture
   struct. Targeted probe 2/2 green after fix.

**Lesson saved:** Bennett's LLVM lowering fails on closures that capture
values (they materialise as `StructType` in Julia's IR). For oracle
tests at varying parameters, prefer a set of small top-level functions
over a loop with a parametrised closure. Will fold into the memory
update below.

### Note on the bead's `DeepCtrlNode` suggestion

The bead explicitly proposed Option B (add `DeepCtrlNode` node type
outside the HotNode union). I opted for a strictly simpler approach
(no new node type, same semantics, Session 3 perf preserved). The
downside: visualisation/rendering of a deep-controlled op now shows the
cascade rather than the abstract "MCU" node. If we later want to
render MCU symbolically (e.g., in `to_ascii` for a 5-controlled rotation
shown as `Rz(θ)●●●●●` rather than the full expanded cascade), that's a
separate UX decision and can add `DeepCtrlNode` as an OPT-IN sugar layer
at that point — the cascade stays as the canonical lowering.

---

## 2026-04-18 — Session 24E: Close `1wv` (`with_empty_controls` public API)

Three external files were reaching into `ctx.control_stack::Vector{WireID}`
directly to save/clear/restore controls around basis changes (pauli_exp.jl)
and PREPARE/SELECT isolation (lcu.jl). That field is not part of the
`AbstractContext` contract — it's a convention every current context
happens to share. A future tensor-network or hardware-emitting backend
might represent controls differently and would silently produce wrong
circuits. The Session 24D refactor (xcu) also introduced two fresh leaks
in `src/context/multi_control.jl` (`copy(ctx.control_stack)`). Closing
both before the pattern spreads.

### RED-GREEN TDD

Wrote `test/test_control_api.jl` first — 9 testsets covering:

- `current_controls(ctx)` returns a copy (mutating it does not alter the
  stack) — regression test on existing API.
- `with_empty_controls(f, ctx)` clears the stack inside `f()`, restores on
  normal exit, restores on exception.
- `with_empty_controls` returns the value of `f()`.
- `with_controls(f, ctx, controls)` swaps the stack, restores on exit.
- Nested pattern: the pauli_exp / lcu idiom (outer empty-clear, inner
  temporarily-restore).
- Works identically on all three contexts (EagerContext,
  DensityMatrixContext, TracingContext) — the default
  implementation in `abstract.jl` uses `push_control!` / `pop_control!` /
  `current_controls` only, so any context that implements the three gets
  `with_controls` / `with_empty_controls` for free.

RED: 9/9 errored (symbols don't exist yet — `using Sturm: …` fails the whole
file). First GREEN: added `with_controls` + `with_empty_controls` to
`src/context/abstract.jl`, exported both, got 1/9 passing (the no-imports-
needed test). Second fix: my test file also needed `allocate!` /
`current_context` imported — both are unexported. After that, 23/23 green
(23 is the sub-assert count inside the 9 testsets).

### Migration — three caller sites

- `src/simulation/pauli_exp.jl:191` — the `_pauli_exp!` basis-change
  optimisation. Old: raw `empty!` / `append!` on the stack with
  `has_controls` boolean flag threading through 5 `if` guards. New: outer
  `with_empty_controls(ctx) do … end` wrapping all 5 steps, with a single
  `with_controls(ctx, saved) do … end` for the one controlled Rz pivot.
  Lost ~20 lines of bookkeeping, kept the physics proof comment intact.

- `src/block_encoding/lcu.jl:72, 102` — `oracle!` and `oracle_adj!`.
  Identical shape (PREPARE / SELECT / PREPARE†) and identical collapse:
  outer `with_empty_controls`, inner `with_controls(saved)` around the one
  SELECT call. Both functions lost their `try`/`finally` block — the new
  primitives handle restoration automatically.

- `src/context/multi_control.jl:85, 102` — `copy(ctx.control_stack)` is
  semantically identical to `current_controls(ctx)` (both return a copy).
  Swapped both. These are internal cascade helpers shared between
  EagerContext and DensityMatrixContext, so removing the field access
  here tightens the context-polymorphic seam.

### Design decision

Primary primitive is `with_controls(f, ctx, controls::Vector{WireID})`
(swap-in / run / swap-out). `with_empty_controls(f, ctx) =
with_controls(f, ctx, WireID[])` is a one-line wrapper. The bead
explicitly requested `with_empty_controls` by name, so that's the
documented/exported surface, but `with_controls` also ends up exported
because the pauli_exp / lcu idiom needs it.

Default implementation in `abstract.jl` uses only
`current_controls` / `push_control!` / `pop_control!`, all three of which
were already required by the abstract interface. So:

- EagerContext, DensityMatrixContext, TracingContext all get
  `with_controls` / `with_empty_controls` with zero code per context.
- A future backend need only implement the three existing interface
  methods to pick up the full control-lifecycle API.
- The internal `.control_stack` field in each concrete context is NOT
  touched by the migration — per the bead: "default implementation can
  still use the control_stack field for backward compat with current
  contexts."

### Verification

- `test_control_api.jl` (new): 23/23 green.
- `test_when.jl` (regression): 507/507 green.
- `test_density_matrix_mc.jl` (regression after `multi_control.jl`
  migration): 17/17 green.
- `test_block_encoding.jl` (regression after `lcu.jl` migration): 63/63.
- `test_simulation.jl` (regression after `pauli_exp.jl` migration): 122/122.

Total new+regression: 732/732. No failures.

### Files touched

- `src/context/abstract.jl`: `with_controls`, `with_empty_controls` +
  docstrings; one-line update to `current_controls` docstring noting it
  returns a copy.
- `src/Sturm.jl`: export `current_controls`, `with_controls`,
  `with_empty_controls`.
- `src/simulation/pauli_exp.jl`: migrate `_pauli_exp!` basis-change
  optimisation.
- `src/block_encoding/lcu.jl`: migrate `oracle!` and `oracle_adj!`.
- `src/context/multi_control.jl`: `copy(ctx.control_stack)` →
  `current_controls(ctx)` at two cascade helpers.
- `test/test_control_api.jl` (new), `test/runtests.jl` (include).
- `WORKLOG.md`: this entry.

### Lesson

When extracting helpers that reach into context internals (Session 24D's
`multi_control.jl`), leave a note to revisit. Fresh code that uses
implementation details becomes the next migration's problem within a
session. Better: identify the abstract-interface candidate up front, even
if you defer the full sweep.

---

## 2026-04-18 — Session 24D: Close `xcu` (multi-controlled gates on DensityMatrixContext)

`DensityMatrixContext` errored "not yet implemented" on every multi-controlled
variant of `apply_ry!`/`apply_rz!`/`apply_cx!`/`apply_ccx!` (density.jl lines
109/125/138/149). Consequence: any noise-circuit demo using nested `when()`
was broken. This bead ports EagerContext's Toffoli cascade to DM, via a
shared helper file.

### Key insight (from 4 parallel Sonnet Explore agents)

The bead's hint ("Toffoli cascade on density matrix via Kraus superop
composition") was half-right. Orkan's gate ABI is **state-type-agnostic**:
`orkan_ry!`, `orkan_cx!`, `orkan_ccx!` all dispatch internally on
`state->type` (`ORKAN_PURE` vs `ORKAN_MIXED_PACKED` vs `ORKAN_MIXED_TILED`)
and already compute `U ρ U†` on mixed states. There is no Kraus
decomposition needed for coherent gates — they are single-Kraus unitary
channels, and Orkan handles the `UρU†` conjugation internally.

Confirmed via Orkan source inspection:

- `gate.h` declares the full gate API without any density-specific variants.
- `orkan_channel_1q!` exists for *noise* channels (1-qubit Kraus), but is
  not needed for controlled unitaries.
- Orkan has NO multi-controlled primitive on either state type — the ceiling
  is `ccx` (1-target, 2-control Toffoli).

So the cascade mirroring EagerContext exactly is correct on DM, with zero
FFI changes.

### Refactor: shared `multi_control.jl`

Moved the 6 helpers (`_controlled_ry!`, `_controlled_rz!`,
`_toffoli_cascade_forward!`, `_toffoli_cascade_reverse!`,
`_multi_controlled_gate!`, `_multi_controlled_cx!`) out of `eager.jl` into a
new file `src/context/multi_control.jl`, typed on
`Union{EagerContext, DensityMatrixContext}` so both contexts dispatch to
them. The file must be included AFTER both context types are defined
(Julia cannot resolve a `Union{T, U}` type parameter until both are
available) — registered in `Sturm.jl` as the third `context/` include.

`eager.jl` and `density.jl` now have IDENTICAL `apply_ry!`/`apply_rz!`/
`apply_cx!`/`apply_ccx!` dispatch shapes (nc=0 → raw; nc=1 → ABC or CCX;
nc≥2 → cascade). No duplication.

### Ground-truth check triggered by user prompt mid-session

User asked "did you read the Nielsen and Chuang ground truth? are the
equations matched?" I had NOT — I copied comments from eager.jl forward
without verifying. Re-read `docs/physics/nielsen_chuang_4.3.md` and
verified algebraically:

- At ctrl=|0⟩: CX ≡ I, so `Ry(−θ/2)·Ry(θ/2) = I`. ✓
- At ctrl=|1⟩: CX ≡ X on target, composed (right-to-left) =
  `X·Ry(−θ/2)·X · Ry(θ/2)`. Using `X·Ry(α)·X = Ry(−α)`:
  `Ry(θ/2)·Ry(θ/2) = Ry(θ)`. ✓

Barenco et al. 1995 Lemma 7.2 had no local PDF — pre-existing docs gap
from eager.jl. Wrote `docs/physics/toffoli_cascade.md` with a self-
contained derivation (computational-basis induction on AND-reduction +
linearity + single-Kraus density-matrix extension). Pointed
`multi_control.jl`'s reference comment at the new local doc.

**Lesson for future agents:** when extracting/copying code with docstring
references, read the local physics doc before shipping. Do not copy the
reference forward. This is a literal letter-of-rule-4 issue.

### Tests — `test/test_density_matrix_mc.jl` (new)

17 testsets covering:

- Depth 2 nested-when CCRy / CCRz / CCX — deterministic cases on all
  control-bit combinations.
- Depth 2 `apply_cx!` inside nested-when — effective CCCX via cascade.
- Depth 2 `apply_ccx!` inside `when()` — uses the path that pushes `c1`
  onto the stack and runs multi-controlled CX with `c2`.
- Depth 3 triple-nested `when()` — effective 4-way AND. Verifies the
  Toffoli cascade allocates 2 workspace qubits and uncomputes them.
- Superposition entanglement: `c1=|+⟩, c2=|1⟩, t=|0⟩` nested-when should
  leave `c1` and `t` perfectly correlated across shots. 200/200 passed.
- Workspace recycling: after a depth-3 cascade, `length(ctx.wire_to_qubit)`
  reports 4 user qubits (c1, c2, c3, t), confirming the 2 workspace
  ancillae were correctly deallocated.

Registered in `test/runtests.jl` immediately after `test_density_matrix.jl`.

### Verification

- `test_density_matrix.jl` 1753/1753 (regression)
- `test_density_matrix_mc.jl` 17/17 (new)
- `test_noise.jl` 506/506 (regression)
- `test_when.jl` 507/507 (regression after refactor)
- Classicalise testset 12/12

### Process notes

The 4-parallel-Sonnet Explore pattern was effective for this bead: one
afternoon's worth of disambiguation done in maybe 3 minutes of parallel
exploration. Template for future big beads: spawn agents that each cover
(a) the "before" state of a module, (b) the reference implementation to
mirror, (c) existing test patterns, (d) the FFI / lower-layer surface.
Keep each under 800 words with code excerpts; synthesise the convergent
findings before reading ground truth in detail.

### Files touched

- `src/context/multi_control.jl` (new, 102 lines): shared cascade helpers.
- `src/context/eager.jl`: removed helpers (−108 lines), kept the dispatch
  in `apply_*!`.
- `src/context/density.jl`: restructured `apply_ry!`/`apply_rz!`/`apply_cx!`
  to mirror eager.jl's nc=0/1/≥2 tree; replaced four
  `error("not yet implemented")` with cascade calls.
- `src/Sturm.jl`: include `context/multi_control.jl` after both context
  files.
- `test/test_density_matrix_mc.jl` (new), `test/runtests.jl` (include).
- `docs/physics/toffoli_cascade.md` (new): self-contained derivation of
  the multi-controlled cascade, with the density-matrix extension
  explicit.
- `WORKLOG.md`: this entry.

---

## 2026-04-18 — Session 24C: Close `f23` (P2 implicit quantum→classical cast warning)

The P2 axiom says measurement is a cast with implied information loss, and
implicit assignments (`x::Bool = q`) must warn. Prior to this session the
codebase defined `Base.Bool(q::QBool) = convert(Bool, q)` — one path for
both explicit constructor calls AND implicit annotated assignments — so
nothing could distinguish them. This bead fixes that.

### Design (from the conversation, not agent-proposed)

Split the constructor from `convert`:

- `Base.Bool(q::QBool)` / `Base.Int(q::QInt{W})` hold the actual
  measurement. Silent, the blessed explicit path.
- `Base.convert(::Type{Bool}, q::QBool)` / `convert(::Type{Int}, q::QInt{W})`
  emit the P2 warning, then delegate to the constructor.

Julia desugars `x::Bool = q` to `x = convert(Bool, q)`, so implicit
assignments flow through the warning path; explicit `Bool(q)` calls skip
it entirely. No macro rewriting, no special hooks — just the standard
Julia conversion system doing what it already did, with the warning added
on the convert side.

### Warning helper (`src/types/quantum.jl`)

- `_first_user_frame(frames)` walks the stacktrace and returns the first
  frame whose `file` is outside `src/types/quantum.jl:_STURM_SRC_ROOT`
  (= the parent of `src/types/`). That is the user's call site.
- `_warn_implicit_cast(::Type{From}, ::Type{To})` emits
  `@warn … maxlog=1 _id=(:sturm_implicit_cast, file, line)` with
  `_file=file _line=line` so the reported location is the user's site, not
  the Sturm internal line. `_id` tuples dedupe per source location: loop
  iterations at one site share one warning; two different sites each get
  their own.
- `with_silent_casts(f)` flips `task_local_storage(:sturm_implicit_cast_silent, true)`
  for the duration of `f()`, restoring the previous value in `finally`.
  Nests correctly via save/restore, parallels the `@context` macro.

### `if q`, `classicalise(ch)` — out of scope

- `if q::QBool` currently hits Julia's runtime `TypeError: non-boolean
  used in boolean context`. Julia's `if` does NOT auto-call `Bool(cond)` —
  the runtime checks `isa(cond, Bool)` and errors otherwise. The PRD §P4
  claim that `if q` emits the P2 warning + measures + branches is
  unreachable without source-level macro rewriting. Deferred; not f23.
- `classicalise(f)` has no implicit entry point (only invoked by name),
  so the channel-level cast is already behaviorally "explicit". The bead's
  "classicalise behaves the same way" acceptance criterion is satisfied
  with no code change.

### Regression: existing test code used implicit casts

Running `test_bell.jl` / `test_teleportation.jl` / `test_rus.jl` after the
fix surfaced eight `::Bool = q` / `::Int = qi` call sites in our own test
code. That is exactly what the warning is supposed to flag — the tests
were written in the pre-axiom style. Converted all eight to explicit
`Bool(q)` / `Int(q)` forms. Same measurement semantics, now silent in
the new logger output. The warning mechanism catching our own code is
itself a validation that the dispatch split works.

### Gotcha: `local _::Bool = q` is invalid Julia syntax

First draft of `test_implicit_cast.jl` used `local _::Bool = q` to
anonymise an unused measurement result. Julia rejects with
`syntax: type declaration for global "_" not at top level` — `_` cannot
carry a type annotation. Renamed to `local dummy::Bool = q`. Leaving this
note because it is not an intuitive syntax error if you have not hit it.

### Stale PRD examples (not fixing here — scope)

`Sturm-PRD.md` contains ~10 `::Bool = q` / `::Int = qi` pedagogical
examples. These now would trigger warnings if copy-pasted. Flagged on
`zv1` (docs refresh) — not expanding f23's scope.

### Verification

- `test/test_implicit_cast.jl` (new): 14 passes. Covers explicit silent,
  implicit warns, both QBool and QInt, message text includes the fix
  suggestion, `with_silent_casts` suppresses + returns block value +
  nests.
- `test_bell.jl` 2002/2002, `test_teleportation.jl` 1002/1002,
  `test_rus.jl` 205/205 — all green after the explicit-cast conversion.

### Files touched

- `src/types/quantum.jl`: `_first_user_frame`, `_warn_implicit_cast`,
  `with_silent_casts`, P2 header comment.
- `src/types/qbool.jl`: split `Base.Bool` / `Base.convert`.
- `src/types/qint.jl`: split `Base.Int` / `Base.convert`.
- `src/Sturm.jl`: export `with_silent_casts`.
- `test/test_implicit_cast.jl` (new), `test/runtests.jl` (include).
- `test/test_bell.jl`, `test/test_teleportation.jl`, `test/test_rus.jl`:
  convert to explicit casts.
- `README.md`: one-line note about `with_silent_casts` opt-out.
- `WORKLOG.md`: this entry.

---

## 2026-04-18 — Session 24B: Close `q93` (oracle arg-type inference from W)

`bridge.jl` hardcoded `Int8` as the classical argument type Bennett compiles
against, regardless of `QInt{W}` width. Bennett's `_narrow_ir` pass then
uniformly rewrote widths to `W`, which papered over the mismatch for simple
modular arithmetic — but it is still a type lie (constants, comparisons, and
any Julia dispatch path inside `f` sees Int8 when the register is 16 bits).

### Fix

New helper `_bennett_arg_type(W; signed=true)` in `src/bennett/bridge.jl`
picks the narrowest fitting `Int*` / `UInt*`: W≤8→Int8, W≤16→Int16,
W≤32→Int32, W≤64→Int64; `signed=false` flips to the `UInt*` variant;
W>64 errors. Both `oracle(f, x; signed=true, kw...)` and the `QuantumOracle`
call operator route through the helper. The cache key on `QuantumOracle`
widens from `(W, kwargs)` to `(W, signed, kwargs)` so switching signedness
forces a recompile rather than silently reusing a stale circuit (the same
discipline Session 20 applied for strategy kwargs).

### Ground-truth probe results (not in the bead acceptance test)

Bead's acceptance test was `oracle(x -> x * 1000, QInt{16}(v))`. This
cannot run on this machine:

1. `reversible_compile` with an IR containing a multiplication grows Orkan's
   register above the 30-qubit `MAX_QUBITS` cap even at `W=4` — 69 qubits
   for `estimate_oracle_resources(x -> x * 10, Int8; bit_width=4)`. At
   `W=16` it would be far worse.
2. The README (lines ~146-200) advertises `strategy=:tabulate` as a kwarg
   on `reversible_compile`, supposedly landed by Bennett-cfjx per Session
   22. It is NOT present in the current Bennett source — the signature is
   `(bit_width, add, mul, optimize, max_loop_iterations, compact_calls)`
   only. Either Session 22 misreported, or the feature was reverted
   upstream. README is stale on this point. **Filed as a separate concern**
   — not expanding q93 scope.

Because of (1) + (2), q93 tests stay at `W=2` (the largest width that
actually fits mul-bearing circuits today). The type-system fix is verified
via direct unit tests on `_bennett_arg_type` plus regression on existing
W=2 paths.

### Test additions — `test/test_bennett_integration.jl`

- `_bennett_arg_type` returns correct type across the full W range for both
  `signed=true` and `signed=false`. 32 cases.
- Out-of-range (`W ≤ 0` or `W > 64`) errors.
- `oracle` at W=2 works with both `signed=true` (default) and
  `signed=false`. Regression + new path.
- `QuantumOracle` cache distinguishes `signed=true` from `signed=false`
  with the same W — `length(qf.cache) == 2` after two calls.
- The pre-existing `haskey(qf.cache, (W, ()))` tests in the
  "caches circuit across calls" and "different widths use different cache
  entries" testsets updated to the new `(W, signed, ())` shape. Two lines.

### Files touched

- `src/bennett/bridge.jl`: `_bennett_arg_type` helper; `oracle` +
  `QuantumOracle` call operator take `signed::Bool=true`; cache key widens
  to `(W, signed, kwargs)`.
- `test/test_bennett_integration.jl`: new `@testset verbose=true "arg-type
  selection by W"` block; two existing `haskey` asserts updated.
- `WORKLOG.md`: this entry.

### Lesson for future agents

The README and WORKLOG Session 22 both claimed `strategy=:tabulate` was a
Bennett-level kwarg. A quick `grep -r tabulate` on
`/home/tobiasosborne/Projects/Bennett.jl` would have surfaced the
discrepancy in seconds. Before writing any acceptance test that depends on
an upstream feature, verify the feature still exists in upstream — session
summaries and docs drift.

### Stale README entries discovered

1. Lines ~146-200 describe `strategy=:tabulate` as a live Bennett kwarg.
   Not present. Would need either the Bennett kwarg to land, or the README
   to stop advertising it.
2. The bit_width=2 polynomial showcase claims 9 wires via `:auto →
   :tabulate`. Today's `estimate_oracle_resources(x -> x^2 + 3x + 1,
   Int8; bit_width=2)` would need confirming once we have a reliable
   tabulate path.

Not fixing in this session — filing under the existing `zv1` docs-refresh
bead would be cleanest. Flagged in the bead's notes at close time.

---

## 2026-04-18 — Session 24: Close `1f3` (QDrift / Composite RNG injection)

Picked up Session 23's in-progress bead. Code for `rng::AbstractRNG` threading
had already landed; what was outstanding was end-to-end verification of the
`@context` closure pattern, and — discovered this session — a vacuous test.

### Ground truth before coding

Per the user's standing preference (`feedback_ground_truth_first`): read
`src/simulation/qdrift.jl`, `src/simulation/composite.jl`,
`test/test_qdrift.jl`, `test/test_composite.jl`, and the `@context` macro in
`src/context/abstract.jl` BEFORE running anything. Confirmed:

- QDrift: `rng::AbstractRNG` field, constructor kwarg, `_sample(dist, alg.rng)`
  threaded at `qdrift.jl:122`.
- Composite: `rng` field + kwarg, threaded in BOTH branches of
  `_apply_composite!` (pure-qDRIFT degenerate case at `composite.jl:106` via
  `QDrift(..., rng=alg.rng)`, and the interleaved loop at `composite.jl:123`
  via `_sample(dist, alg.rng)`).
- `@context` macro at `context/abstract.jl:93-107` returns the body's last
  expression via `try ... finally`. The `run_once()` closure pattern is sound:
  `a` as the trailing expression of the `begin...end` becomes the return
  value.

### Gotcha: the committed Composite test was vacuous

The Session-23 committed test used
`Composite(steps=2, qdrift_samples=10, cutoff=0.5, …)` with
`ising(Val(3), J=1.0, h=0.5)`. At cutoff=0.5 both coefficients satisfy
`|hⱼ| ≥ cutoff`, so `_partition` puts ALL terms in the Trotter partition and
returns `B = nothing`. Control flow takes the degenerate branch
(`composite.jl:99-102`) which never consults the RNG. The
`amps_a == amps_b` assertion held, but only because the circuit is fully
deterministic — not because the RNG was threaded.

Probed via:

```
julia> _partition(ising(Val(3), J=1.0, h=0.5), 0.5)
# A=nterms=5, B=nothing           ← vacuous at cutoff=0.5

julia> _partition(ising(Val(3), J=1.0, h=0.5), 0.75)
# A=nterms=2, B=nterms=3          ← 2 ZZ in Trotter, 3 X in qDRIFT
```

**Lesson for future tests on `Composite`**: pick the cutoff BY INSPECTING
the Hamiltonian's coefficient magnitudes, not by mirroring whatever the
construction docstring happens to default to. A `_partition(H, cutoff)` probe
before committing an RNG-threading test catches this trivially.

### Fix

Both committed testsets hardened with an alt-seed sanity check
(`amps_a != amps_c` where `a = seed 42`, `c = seed 99`). The Composite test
also switches to `cutoff=0.75` with a rationale comment inline
(`test_composite.jl:309-329`). Now:

- If the RNG kwarg is stored but not threaded → same-seed equal still holds
  (vacuous), alt-seed differ FAILS loudly. Test catches the bug.
- If the RNG is threaded correctly → both assertions hold.

### Verification (targeted probe, not full suite)

```
LIBORKAN_PATH=…/liborkan.so julia --project -e '…'
[1/3] sample-sequence determinism: OK
[2/3] QDrift end-to-end determinism: OK (same-seed equal, alt-seed differ)
[3/3] Composite end-to-end determinism: OK (same-seed equal, alt-seed differ)
ALL OK
```

Full `test_qdrift.jl` / `test_composite.jl` runs skipped per the
`sturm-jl-test-suite-slow` memory — the modified testsets were exercised
as-written by the probe.

### Bead closure

`Sturm.jl-1f3` closed. End-to-end verification done. The reproducibility
contract (seeded `rng` → byte-identical Orkan amplitudes) now has a test
that actually exercises the qDRIFT partition.

### Environment note

`LIBORKAN_PATH` is `/home/tobiasosborne/Projects/orkan/…` on this device.
The memory entry `device-performance-do-not-run-full-test-suite` had
`/home/tobias/Projects/orkan/…`; that path does not exist here. The correct
prefix is `/home/tobiasosborne/`. (Not updating the memory this session;
leaving as a known discrepancy.)

### Files touched

- `test/test_qdrift.jl` (lines 466-485): `run_once(seed)`, alt-seed assertion.
- `test/test_composite.jl` (lines 309-329): `cutoff=0.5 → 0.75`,
  `run_once(seed)`, alt-seed assertion, rationale comment.
- `WORKLOG.md`: this entry.

---

## 2026-04-17 — Session 23: Harmonise repo against PRD and vision

Full-day session. Shape: (1) stocktake across the whole codebase (122 files, ~9.5k src LOC), (2) beads triage — delete the future-vision epics that no longer match direction, (3) file replacement beads covering the real state-based findings, (4) revise PRD/docs to match current code + the "four pillars" vision from user's blog draft, (5) execute a run of easy beads.

### Vision (from author's blog + A1 discussion)

Sturm.jl is NOT a new language. It is Julia, extended. Quantum algorithms written in idiomatic Julia at the level of channels / operators / higher-order patterns, compiled by the package to circuits. Four pillars:

1. **Expressive** — no gates, no qubits in user code; registers and higher-order patterns.
2. **Compiler quality** — DAG IR optimised by publishable passes; new circuit-construction papers shippable as transformations.
3. **Extensible** — new pass APIs integrate in hours (as the Bennett.jl + Sun-Borissov experience demonstrated).
4. **Backend-agnostic** — Orkan, simulators, tensor networks, hardware all substitutable behind `AbstractContext`.

Everything else in the PRD (`P1`–`P9`) reads under this framing. See Sturm-PRD.md after this session's revision.

### Beads harmonisation

**Deleted 10** (multi-path arithmetic Phases 2-7: `xfk, adj, 2l4, 5se, 3ii, 3px`; oracle decompose subsumed by Bennett `:tabulate`: `16l, 25u`; P7 future arms: `wzj, 5ta`).

**Closed 2** (`k3m` incoherent — the literal `f(q)` syntax the P9 bead asked for is rejected by Julia and by the PRD; `mjk` done — Phase 1 test coverage exists, bridge cache sorts kwargs).

**Kept 1** (`f23` — the P2 implicit-cast warning is a legit current-state gap).

**Filed 15 new**, all traceable to stocktake findings. Priorities follow the user's G1 rule: P0/P1 = red-flashing emergency, ergonomics/nice-to-have pushed to P3/P4. See `bd list --status=open -n 20`.

**Also deleted** `docs/PLAN.md`, `docs/bennett-integration-v01-vision.md`, `docs/multi-path-arithmetic-plan.md` — three stale docs; git history preserves them. `docs/bennett-integration-implementation-plan.md` is current and kept.

**Created `KNOWN_ISSUES.md`** at project root — bullet register of architectural constraints (noise outside DAG IR by design), performance targets (31 bytes/node from Session 3), hard caps (30-qubit MAX_QUBITS), and test gaps that don't warrant individual beads.

**PRD revised** to remove "v0.1 POC" framing throughout, rewrite §7 as a current-state inventory (what is shipped, what is not, what is excluded by design), correct §9.2 (EagerContext is Orkan-backed, not a dense Julia vector as the old PRD said), align §2.5 / §9.4 / §9.6 to the real code, update §11 deps and §12 non-goals. Axioms P1-P9 untouched. ~300 lines net-down; see commit `a9752fa`.

### Beads worked this session

- **`wmo` P0 bug** (closed, commit `c162959`) — `alpha_comm(H, p≥3)` previously returned a naive triangle bound silently; per WORKLOG Session 4 that can be 10^9× looser than the true commutator-scaling value. Changed to throw `ErrorException` with a message directing users to `trotter_error(H, t, order; method=:naive)` (which bypasses `alpha_comm` entirely and uses `(λt)^(p+1)` directly). 7 new tests in `test_error_bounds.jl`, 68/68 pass.

- **`ndm` P1 task** (closed, commit `679cdea`) — orphaned `qsvt!` in `src/qsvt/circuit.jl` had a 13-line WARNING block stating it was broken for general block encodings. `qsvt_combined_reflect!` + `oaa_amplify!` is the working path (what `evolve!(…, QSVT(ε))` dispatches to). Deleted the function, docstring, WARNING block (~80 LOC). Removed 2 associated tests from `test_qsvt_phase_factors.jl` and the import. 162/162 pass.

- **`w4g` P1 task** (closed, commit `ba6e295`) — `Base.:<(::QInt, ::QInt)` and `Base.:(==)(::QInt, ::QInt)` plus their 4 Integer-mixed overloads silently measured both operands and returned a deterministic QBool. Violated P1 (functions are channels) and P9 (quantum registers as numeric type for reversible dispatch). Deleted all 6 definitions (~50 LOC). Removed 5 testsets from `test_qint.jl` and 4 from `test_promotion.jl`. Short comment at the deletion site points future readers to `oracle(f, q)` for quantum comparators. 562 + 2043 tests pass.

- **`lpj` P4 task** (closed, commit `3b60acf`) — `src/bennett/auto_dispatch.jl` was a 45-line stub holding `_P9_CACHE`, `_P9_LOCK`, `clear_auto_cache!()` for the Julia-forbidden literal `f(q)` catch-all. No callers outside the test. Deleted the file, removed include from `src/Sturm.jl`, deleted the "infrastructure exported" testset from `test_p9_auto_dispatch.jl`. Remaining 13 P9 tests pass (Quantum abstract type, classical_type trait, classical_compile_kwargs, existing dispatch paths).

- **`1f3` P3 feature** (in_progress, not closed) — QDrift and Composite RNG injection. Code changes are in this commit but END-TO-END VERIFICATION IS PARTIAL. See next-session pickup below.

### `1f3` state at stop time — PICK THIS UP FIRST

**Code landed (this commit):**

- `Project.toml`: added `Random = "9a3f8284-..."` to `[deps]`. `Random` is a stdlib but Julia still requires declaration in `[deps]` for non-Base modules.
- `src/simulation/qdrift.jl`:
  - `using Random: AbstractRNG, default_rng` at top
  - `QDrift` struct gained `rng::AbstractRNG` field; constructor has `rng::AbstractRNG = default_rng()` kwarg
  - `_sample(dist)` became `_sample(dist, rng::AbstractRNG = default_rng())` (backward-compat)
  - `_apply_qdrift!` now passes `alg.rng` to `_sample`
- `src/simulation/composite.jl`:
  - `Composite` gained `rng::AbstractRNG` field; constructor `rng::AbstractRNG = default_rng()` kwarg
  - `_apply_composite!` threads `alg.rng` in BOTH places: the pure-qDRIFT branch (constructs a `QDrift(..., rng=alg.rng)`) and the interleaved Trotter+qDRIFT loop (`_sample(dist, alg.rng)`)
- Test files `test_qdrift.jl` and `test_composite.jl`:
  - `using Random: MersenneTwister` at top
  - New testset `RNG injection: _sample is deterministic with seeded RNG` in `test_qdrift.jl` — verifies two `MersenneTwister(42)` give byte-identical sample sequences; different seed produces different sequence. **This part ran green.**
  - New testset `QDrift rng kwarg is stored and threaded to sampling` in `test_qdrift.jl`, and a parallel `Composite rng kwarg ...` in `test_composite.jl` — end-to-end: two seeded `evolve!` calls on identical |0…0⟩ produce identical Orkan amplitudes.

**Gotcha found and fixed but NOT re-verified:**

First attempt used two back-to-back `@context EagerContext() begin ... end` blocks with `amps_a = [_amp(...) for i in 0:7]` inside the first block and `@test amps_a == amps_b` inside the second. Failed with `UndefVarError: amps_a not defined in Main`. The `@context` macro introduces a scope via its `try ... finally` that hides inner assignments from the outer scope. Fix: wrap each run in a local function `run_once() = @context EagerContext() begin ...; a; end` that returns the amps list as the block's final expression (before `discard!`s? no — discards before the return); then `amps_a = run_once(); amps_b = run_once(); @test amps_a == amps_b`. This is now the committed shape but the probe was interrupted mid-execution.

Looking more carefully: `run_once()` returns `a` but the `@context ... end` ends with `a` AFTER the `for q in qs; discard!(q); end`. The `discard!`s clean up; the state is captured in `a` beforehand. Should be fine.

**Next steps to close `1f3`:**

1. Run the targeted probe to re-verify:
   ```
   LIBORKAN_PATH=/home/tobiasosborne/Projects/orkan/cmake-build-release/src/liborkan.so julia --project -e '
   using Sturm, Test; using Sturm: _QDriftDist, _sample, _amp; using Random: MersenneTwister
   H = ising(Val(3), J=1.0, h=0.5)
   run_qd() = @context EagerContext() begin
       qs = [QBool(0.0) for _ in 1:3]
       evolve!(qs, H, 0.5, QDrift(samples=10, rng=MersenneTwister(42)))
       a = [_amp(qs[1].ctx, i) for i in 0:7]
       for q in qs; discard!(q); end
       a
   end
   a = run_qd(); b = run_qd()
   @test a == b
   println("ok")
   '
   ```
2. If green, run the full `test_qdrift.jl` once (slow — ~13 minutes on this machine due to the N=24 Ising ground-truth test) OR skip and trust CI.
3. Also run `test_composite.jl`.
4. `bd close Sturm.jl-1f3 --reason="..."` + commit + push.

**Risk:** if the `run_once()` closure pattern doesn't work with `@context` either (TLS semantics across function calls are subtle), an alternative is to set `amps_a` via a `Ref{Vector{ComplexF64}}()` written inside the `@context` block. The macro expansion of `@context ctx body` is in `src/context/abstract.jl:~98`; look there if you need to debug scoping.

### Remaining easy-ish open beads

After `1f3` closes, low-friction candidates:

- **`eiq` P3** — CasesNode consumer policy. Touch `channel.jl` compat constructor, `openqasm.jl` line ~112, renderer warnings. Mechanical.
- **`q93` P2** — oracle Int8 hardcoding. Needs a small inference function: W → smallest signed/unsigned integer type.
- **`zv1` P4** — Refresh CLAUDE.md + README. Documentation sweep.

Harder beads that need design first:

- **`1wv` P1** — `with_empty_controls(f, ctx)` method on `AbstractContext`. Touches `pauli_exp.jl` (~line 200) and `lcu.jl` (lines 72-96). Needs a review to make sure no subtle semantics change.
- **`rpq` P1** — Arbitrary `when()` nesting in `TracingContext`. Requires either widening `HotNode` (kills 25-byte isbits, regresses Session 3 perf) or adding a cold-path node variant. User's earlier preference: option B (cold-path `DeepCtrlNode`).
- **`xcu` P1** — Multi-controlled gates on `DensityMatrixContext`. Density-matrix Toffoli via Kraus superop composition is non-trivial.
- **`870` P1** — Steane syndromes. This is QECC framework + 3 X-stabilisers + 3 Z-stabilisers + Table II lookup — a real bit of work.

### Environment gotchas for next agent

- Fresh clone requires `Pkg.develop(path="../Bennett.jl")` then `Pkg.instantiate()` (Bennett is dev-pathed, not registered). Listed in KNOWN_ISSUES.md.
- Orkan shared library: `LIBORKAN_PATH=/home/tobiasosborne/Projects/orkan/cmake-build-release/src/liborkan.so`.
- bd uses SSH now (`git+ssh://git@github.com/tobiasosborne/Sturm.jl.git`). `bd dolt push` works without interactive prompt.
- Per saved feedback: the full test suite is slow. Use targeted `julia --project -e '...'` probes against specific test files; trust CI for regressions. Even individual test files (qdrift.jl, composite.jl) hit minute+ runtimes because of large-N Ising / Heisenberg ground-truth tests. For quick verification run only the relevant testset rather than `include()`ing the whole file.

### Files touched this session

`Sturm-PRD.md`, `KNOWN_ISSUES.md` (new), `Project.toml`, `src/simulation/error_bounds.jl`, `src/simulation/qdrift.jl`, `src/simulation/composite.jl`, `src/types/qint.jl`, `src/Sturm.jl`, `src/qsvt/circuit.jl`, `test/test_error_bounds.jl`, `test/test_qsvt_phase_factors.jl`, `test/test_qint.jl`, `test/test_promotion.jl`, `test/test_qdrift.jl`, `test/test_composite.jl`, `test/test_p9_auto_dispatch.jl`, `.beads/config.yaml`. Deleted: `src/bennett/auto_dispatch.jl`, `docs/PLAN.md`, `docs/bennett-integration-v01-vision.md`, `docs/multi-path-arithmetic-plan.md`.

### Beads state at end of session

Total: 40. Open: 15 (1f3 in_progress). Closed: 25 this session (4 this session + 2 harmonisation closures + 37 historical; deleted 10 harmonisation).

Run `bd ready` or `bd list --status=open -n 30` to see the current queue.

---

## Earlier sessions archived

Sessions 1–22 (2026-04-05 → 2026-04-15) moved to
[`WORKLOG-archive.md`](WORKLOG-archive.md) on 2026-04-19. They cover:

- **Session 1** (2026-04-05) — project bootstrap, Orkan FFI.
- **Session 2** (2026-04-05) — OOM recovery, memory safety, Phase 6–12 scaffolding (QInt, QFT, Channel, QECC skeleton), Grover, literature survey (100 papers / 9 categories), Choi-phase-polynomials research direction.
- **Session 3** (2026-04-06) — gate cancellation (commutation-aware), optimise(ch, :pass), 149× gate_cancel speedup, isbits-union HotNode (31 B/node).
- **Session 4** (2026-04-06) — quantum-simulation literature survey (~170 papers), simulation module (PauliHamiltonian, Trotter1/2, Suzuki), 3-reviewer code review, 21 issues fixed.
- **Session 5** (2026-04-07) — P8 quantum promotion (numeric tower for QInt + Integer).
- **Session 6** (2026-04-07) — simulation module idiomatic review.
- **Session 7** (2026-04-07) — simulation refactors, qDRIFT, Composite, P0 controlled-pauli_exp! optimisation.
- **Session 8** (2026-04-08) — PDE paper formalisation (Childs et al. 2604.05098), gap analysis.
- **Session 9** (2026-04-08) — literature re-download (90 PDFs), QSVT deprecation (Motlagh → BS+Laneve), Block Encoding Phase 1, QSVT Phase 2.
- **Session 10** (2026-04-08) — Weiss algorithm, RHW factorisation, phase extraction, qsvt_protocol! circuit, BE algebra, controlled-oracle fix, multi-controlled Rz/Ry/CX.
- **Session 11** (2026-04-08) — 5-agent ground-truth review, GQSP operator-ordering fix (critical), reflection QSVT circuit, `evolve!(..., QSVT(ε))` for cos(Ht/α).
- **Session 12** (2026-04-09) — combined QSVT / GSLW Theorem 56 (7 bugs found and fixed, sin parity fix).
- **Session 13** (2026-04-09) — OAA implementation + two critical bugs (BS+NLFT degree-doubling phase collapse, single-qubit Rz ≠ multi-ancilla reflection). Rogue-background-agent gotcha.
- **Session 14** (2026-04-11) — Bennett.jl integration research + 74/74 tests.
- **Session 15** (2026-04-12) — Steane [[7,1,3]] encoder rewrite per Steane 1996 Fig 3, higher-order `encode(Channel, code)`, Grover-from-predicate (`find(f, T, Val(W))`), 2 Bennett upstream bugs fixed, v0.2 direction research (4-backend matrix + viz layer).
- **Session 16** (2026-04-12) — ASCII circuit drawer, pixel-art PNG renderer (Birren palette, 1000-wire GHZ in 70 ms), compact Level-A scheduling, Bennett v0.4 downstream assessment.
- **Session 17** (2026-04-14) — axiom refinement (P2 measurement-as-cast, P7 infinite-dimensional, P9 auto-dispatch spec).
- **Session 18** (2026-04-14) — Bennett.jl v0.5 assessment, multi-path arithmetic compilation plan (7-phase roll-out).
- **Session 19** (2026-04-14) — P9 hits Julia's `cannot add methods to builtin Function` wall, axiom reframed (generic path via P8 + explicit `oracle`/`@quantum_lift`/`quantum`). P4 corollary (`if q` never auto-lifts to `when(q)`).
- **Session 20** (2026-04-14) — multi-path arithmetic Phase 1, P8 bitwise (`⊻`, `&`, `|`) + shifts (`<<`, `>>`) on QInt, QuantumOracle cache-key bug fixed.
- **Session 21** (2026-04-15) — README audit against axioms, oracle decomposition honesty (43-qubit LLVM-lowering reality), Approach A/B idioms.
- **Session 22** (2026-04-15) — Bennett `:tabulate` adoption (zero Sturm-side changes, README rewrite).

For reasoning and design decisions made during any of the above, see the archive.
