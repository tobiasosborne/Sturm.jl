# M7 ruling — Bennett bridge (orchestrator adjudication, 2026-07-10)

Inputs: `m7-bennett-proposal-A.md` (semantics-first), `m7-bennett-proposal-B.md`
(mechanics-first), both written blind. Empirical ground truth:
`bennett-v2-compat-audit.md` + `bennett-bit-order-probe.md` (re-validated at
Bennett HEAD `b6f13802`). D9/D14 are binding.

## Convergence (adopted as-is — the cross-validation signal)

Both proposers independently arrived at:

1. **Eager compile at `oracle()`** — fail-fast, errors name `f` at the user's
   call site; `⊻=` validates only `b`.
2. **`oracle` exported (construct 7); the query value `public`, never a surface
   noun** — not an eighth construct: 7 produces, 3 applies (D9 verbatim).
3. **Weakdep + package extension** (`ext/SturmBennettExt.jl`): core owns the
   accumulate physics and the `Base.xor` methods (testable without Bennett);
   the extension owns the `f → Perm` compile and is the ONLY place a Bennett
   type is named. Keeps LLVM.jl out of `using Sturm` (CLAUDE.md conv 4).
4. **`ctrl(Perm) = Perm` through the existing `_act!`** — zero new
   ctrl-lowering code; the M5 `when`-oracle IOU is discharged by the choke
   point itself. Guardrail 2 and aliasing inherited.
5. **The MSB/LSB remap lives in exactly ONE function** (`_role_tables`, in the
   extension); the `Perm` keeps Bennett wire numbering verbatim; the reversal
   is only in how the apply wire-list is assembled (probe formula
   `sturm bit j ↔ bennett position W−j+1`, per register block).
6. **`auto_self_reversing=false` forced + assert `in ∩ out = ∅`** post-compile.
7. **Loop-check circuits rejected ALWAYS, at compile** — both proposers argued
   past the audit's weaker "under control only" rule from the same physics:
   the convergence flag is x-correlated garbage the user cannot reach; tracing
   it decoheres superposed inputs silently (wm28 class), and Sturm's types
   cannot distinguish definite from superposed `x`. Fail-loud-always.
8. **MBU-exclusion is structural** (Bennett emits no measurement; only
   `ReversibleCircuit` crosses; `Perm` is unitary by construction); the §3.4
   named test asserts the boundary, not a strategy selector.
9. **Verification at the permutation/Choi level, never marginals** (wm28
   discipline); DJ §7.4 and BV §7.5 run verbatim, including the D2 negative
   control `{1:.073, 3:.427, 5:.427, 7:.073}` (exact on DM).

## Divergences — rulings

- **Width contract: ADOPT B (§4), decisive.** B's fresh empirical probes
  showed Bennett couples output width to the compute width `W` (a Bool-valued
  `f` at `bit_width=W` emits a W-bit output block, `f(x)` in bit 0,
  zero-extended). A's exact-`Wout`-match contract cannot express DJ
  (N-bit input, 1-bit target). Ruling: `b`'s type sets `Wb ≤ W`; low `Wb`
  output bits accumulate into `b` (MSB-first on the Sturm side); the high
  `W−Wb` tail goes to fresh scratch **asserted clean |0⟩** before freeing —
  the zero-tail witness is the wm28 guard for an under-sized target, and it
  has NO opt-out. `Wb > W` is a loud error.
- **Scratch lifecycle: ADOPT B's `_free_clean!`** (assert-|0⟩-then-drop-slot,
  NEVER measure-and-discard) — uniform under and outside `when`; a dirty wire
  is loud, not silently collapsed. A's region-exit trace would measure-and-
  discard outside `when` and MISS the under-sized-`b` bug. Synthesis with A:
  the scratch must still be region/ownership-registered (or try/finally-
  guarded) so an error mid-apply cannot leak slots.
- **Kernel seam: ADOPT A's Vector-typed `apply!`/`_act!` siblings**
  (`AbstractVector{WireID}`), additive, confined to the process-value path.
  B's `Tuple(wt)` materializes `NTuple{n}` for data-dependent `n` (observed up
  to 749) — per-width recompilation and dynamic dispatch. `Perm.gates` is
  already a `Vector` for exactly this reason. This is the milestone's one core
  change; this 3+1 round is its gate.
- **Caching: ADOPT A — no Sturm-side cache in M7.** B's
  `objectid(f)`-keyed Dict is a correctness footgun: GC can recycle an
  objectid for a different closure → silent wrong-oracle hit (wm28-adjacent).
  Bennett's own caches already prevent recompiles; the Sturm-side MCX/role
  rebuild is O(gate count) and cheap. Value-level reuse (`q = oracle(f,x)`;
  apply `q` twice) is the shipped caching. Revisit only with a key that roots
  `f` itself.
- **Loop-reject error text: ADOPT A's phrasing.** B's escape hatch ("raise
  `max_loop_iterations` so `loop_check_wires` is empty") overpromises — the
  probe shows a genuinely data-dependent loop keeps its guard at any K;
  only a compiler-provable constant trip count eliminates it. A's message is
  honest: "increasing max_loop_iterations fixes overflow, not the garbage
  flag; rewrite `f` with a statically-bounded loop."
- **Per-circuit D9 assert: ADOPT B** — re-verify "no output wire is ever read
  as a control" on every compiled circuit (one gate-list scan), so a future
  Bennett strategy change breaks loud, not silent.
- **Boot-lint: ADOPT B** — `input_wires[`/`output_wires[` indexing may appear
  only in `_role_tables` (single-remap enforcement, mirrors the ctrl
  choke-point lint).
- **Input types: `x::QInt{W}` (W ∈ 1:64) is the M7 required path.** QBool
  input and multi-register `oracle(f, xs...)` are designed-in (B's
  `in_positions::Vector{Vector{Int}}` shape) but deferred — file follow-on
  beads, do not ship untested paths.
- **Structure: ADOPT B's `CompiledOracle` (x-independent) + `OracleQuery`
  (adds the live handles)** — cleaner than A's flat struct given the reuse
  story, and it is what the extension naturally builds.

## Test plan

Union of A-T1..T12 and B-1..12 (they overlap heavily). Non-negotiables:
- DJ §7.4 / BV §7.5 **verbatim** (PRD examples must execute), incl. the D2
  negative control (exact on DM).
- `denoted_permutation` vs classical `f`, exhaustive, for `n_wires ≤ 20`;
  three-way Sturm/`Bennett.simulate`/classical-`f` agreement above that.
- Bit-order tripwire on an **asymmetric** `f` (increment — carry direction).
- Oracle-under-`when` Choi ≡ `ctrl`(oracle) (M5 IOU), one-run DM.
- Zero-tail witness fires loud for an under-sized `b`.
- Loop-reject test compiled with **`optimize=false`** (probe gotcha — the
  default optimizer folds simple loops and silently tests the wrong path).
- MBU-exclusion named test (§3.4); accumulate law `Int(b) == v ⊻ f(x)`;
  full error-path sweep; ancilla full-marginal cleanliness witness.

## Standing IOUs this milestone discharges / creates

- Discharges: M5 `when`-controlled-oracle IOU; the §3.4 MBU-exclusion named
  test.
- Creates: QBool-input + multi-register oracle (follow-on bead); loop-oracle
  admission via all-converged witness (documented forward path, not M7);
  Bennett full-suite re-run on project Julia as a hardening gate (audit Q5).
