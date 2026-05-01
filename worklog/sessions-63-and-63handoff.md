## 2026-04-25 — Session 63 handoff (superseded by Session 64 above)

Two beads closed this session — `eiq` (CasesNode consumer fail-loud,
Session 62) and `vbz` (Berry App B clean-ancilla forward QROM, Session 63).
**6oc criterion (d) is now ✓ at L=8 (exact 0.500×), L=10, and L=12.**

Orient yourself before touching anything:

```bash
git log --oneline -8       # 2026-04-25 commits start at 9d95ef0
bd ready -n 10              # open work queue (30 ready as of session end)
bd list --status=open -n 30 # full open set (38 open, 8 blocked, 0 in progress)
bd stats                    # high-level counts
```

### Where the project stands as of this commit (9d95ef0)

  * **`vbz` closed** — Berry App B Thm 2 (Eq. 66) clean-ancilla forward
    QROM landed end-to-end. New primitives:
    `qrom_lookup_xor_cleanancilla!` (public) and
    `qrom_lookup_uncompute_meas_cleanancilla!`. New kwarg
    `mbu_compute::Bool=false` on `plus_equal_product_mod!` and
    `_shor_mulmod_E_controlled!`. Dynamic `k_b ∈ {2, 4, 8, …}` selection
    inside `_pep_mod_iter!` (cost-gated, auto-falls-back to no-App-B
    when it doesn't pay). Bench
    `probe_toffoli_vbz_sweep.jl` confirms 6oc(d) closure across L ∈
    {8, 10, 12}. Tests: 317 net-new assertions, all green; no regressions.
  * **`eiq` closed** — CasesNode consumer fail-loud / warn-once policy.
    Channel compat ctor and `gate_cancel(::Vector{DAGNode})` overload
    now error on non-HotNode (was silent strip). `_draw_node!` /
    `_paint_node_px!` for CasesNode add `@warn maxlog=1`. New test file
    `test/test_cases_consumer_policy.jl` pins the four behaviours.
    Note: bead's criterion (a) [openqasm.jl errors] was OBSOLETE — the
    `tak` bead landed dynamic-circuit emission earlier; preserved.
  * **6oc(d) — DONE.** vbz bench at session-end weighting:

    | L  | best ratio (mbu_compute=true) | c_mul | k_b |
    |----|--------|---|---|
    | 8  | **0.500×** (exact) | 5 | 4 |
    | 10 | 0.456× | 4 | 2 |
    | 12 | 0.414× | 5 | 4 |

    L=8 closure is *tight* under Session 50b T-proxy weighting
    (`7·CCX + 14·CCCX + rot + 2·crot + 6·ccrot`). Future tightening:
    `Sturm.jl-ao1` (filed this session, P3) — hand-rolled
    Babbush-Gidney unary iteration would bypass Bennett's 4× overhead
    on the inner T lookup and unlock another ~75% on forward cost.

### Open beads most worth picking up next

The `vbz`-was-the-headline P2 has been retired. Top of the queue now:

1. **`Sturm.jl-059` (P2)** — perf bug. `_shor_mulmod_E_controlled!` at
   N=15 takes ~21 min/call. Structural simulator-guts work; blocks
   6oc(a)(b)(c). Hard but high-value. Session 49 WORKLOG has profiler
   notes; Session 50 pivoted to Toffoli-count metrics because of this.
   Related: `Sturm.jl-2i0` (task_local_storage → ScopedValue).
2. **`Sturm.jl-ao1` (P3, NEW)** — hand-rolled Babbush-Gidney unary
   iteration to bypass Bennett's 4× overhead. Filed at vbz close.
   Would push the L=8 6oc(d) ratio well below 0.500× (current
   closure is exact). Ground truth at
   `docs/physics/babbush_2018_qrom_linear_T.pdf` §III.C Fig 10. Scope:
   one new primitive (`qrom_lookup_xor_unary!` or kwarg on existing)
   built directly from the 4 primitives + when() / `_fredkin!`.
3. **Qudit track** (`csw, 2bf, p38, mle, os4, jba, dj3, …`) — all
   unblocked since Session 57's QMod{5} Ry land; parallel to the
   Shor critical path. Good if you want a bead with no dependencies
   on the windowed-arithmetic / Bennett surface.
4. **`Sturm.jl-7ab` (P2)** — Pass registry / DAG transformation API.
   Sturm wants to ship publishable circuit-construction passes as
   first-class IR transforms. This bead sets up the API.
5. **`Sturm.jl-bkv` (P2, speculative)** — TracingContext speculative
   execution tracer for `if Bool(q)`. Research-y; would unlock the
   PRD §P4 promise of "if q emits the implicit-cast warning then
   takes both arms in tracing". Cassette/IRTools territory.

### Non-obvious traps from this session (write these down)

  * **Stale bead descriptions decay fast.** `vbz` cited Berry "Fig 4"
    — Fig 4 is App A (dirty); App B is text-only on p.25. `eiq`
    cited an `openqasm.jl` line that had already been fixed by the
    `tak` bead months earlier. **Lesson: diff every old bead's
    description against the current source before scoping.**
  * **Sturm's `qrom_lookup_xor!` carries a 4× Bennett-compile
    overhead** vs the bare Babbush-Gidney unary iteration tree the
    Berry paper assumes. Practical Sturm savings from App B at k_b=2
    are ~25%, not the ~70% the paper's bare counts imply. The
    dynamic-k_b heuristic is what made up the rest of the difference
    at L=8. Saved as `bd memories app-b-vs-bennett-overhead`.
  * **App B's swap subroutine S** is described as "a series of Mk
    controlled swaps" in the paper but is actually a *descending
    tree of pair-block-swaps* with k−1 register-level swaps total.
    Closed-form σ_l permutation: `σ_l(i) = i ⊻ (l & mask_i)` with
    `mask_i = ~((1<<h_i) - 1) & (k−1)`. Verified k ∈ {1..4}
    brute-force; `_app_b_sigma_perm` ships this.
  * **Hardcoded k_b regresses at small w.** When `M ≥ 2^(w+1)`,
    App B at k_b=2 costs MORE than the no-App-B baseline. The
    dynamic-k_b cost-gate auto-falls-back. If a future caller uses
    `mbu_compute=true` directly without the analytical gate, the
    same regression returns. Saved as `bd memories vbz-dynamic-k-b`.
  * **`@cases` macro existed but I almost missed it.** When writing
    the new vbz primitives I considered a custom `if is_tracing`
    branch on Bool(q); checked `qrom_lookup_uncompute_meas!` and
    saw the existing TracingContext fallback (X-basis substitution
    + canonical phase_bits). That path inherits cleanly through the
    `qrom_lookup_uncompute_meas_cleanancilla!` delegate. No new
    tracing branch needed.
  * **The Read tool can't open WORKLOG.md whole** (now ~360 KB,
    over the 256 KB cap). Read the head + tail with `offset/limit`
    to orient — handoff entries always live near the top, archived
    sessions are linked from `WORKLOG-archive.md`.

### Environment (inherit these — unchanged from Session 61)

  * `LIBORKAN_PATH=/home/tobiasosborne/Projects/orkan/cmake-build-release/src/liborkan.so`
  * `OMP_NUM_THREADS=16` (strict, per memory `orkan-thread-limit`)
  * Never run the full test suite — per memory `sturm-jl-test-suite-slow`.
    Run individual files via
    `julia --project -e 'using Sturm; include("test/test_X.jl")'`.
  * Julia runs strictly serial on this device (memory
    `feedback_julia_serial_only`).
  * Verbose output must eager-flush stage by stage (memory
    `feedback_verbose_eager_flush`).

### Memory entries worth knowing

```
bd memories beads-storage           # where beads live (Dolt-over-git)
bd memories beads-sync              # dolt merge recipe
bd memories orkan                   # OMP thread cap, LIBORKAN_PATH
bd memories test-suite-slow         # never run Pkg.test()
bd memories app-b-vs-bennett-overhead   # NEW: vbz Sturm-specific overhead
bd memories vbz-dynamic-k-b         # NEW: dynamic k_b heuristic + L=8 tight closure
bd memories oaa                     # BS+NLFT bug (Session 13)
bd memories p9-axiom                # P9 can't be literal per Julia rules
```

### Latest commits on main (origin/main up to date)

```
9d95ef0 feat(vbz): Berry App B Thm 2 clean-ancilla forward QROM — closes 6oc(d) at L=8
de79042 fix(eiq): CasesNode consumer fail-loud / warn-once policy
4dbc49f docs(worklog): session handoff entry for next agent
48640e8 feat(9ij-stage4): MBU Toffoli bench — closes 6oc (d) at L=10
f1375aa feat(9ij-stage3): mbu kwarg on plus_equal_product_mod! + _shor_mulmod_E_controlled!
99c845b feat(9ij-stage2): qrom_lookup_uncompute_meas! primitive
58b6320 feat(9ij-stage1): _binary_to_unary! + _fredkin! helpers
a7ad1ee docs(9ij-stage0): ground MBU construction in Berry et al. 2019 App C
```

### Session sequence for the full story

Read sessions 62 → 63 in this WORKLOG for the current session's full
narrative; 58 → 61 for the 9ij build-up that vbz lands on top of;
earlier sessions in `WORKLOG-archive.md`.

---

## 2026-04-25 — Session 63: close `vbz` — Berry App B clean-ancilla forward QROM

Next pickup after `eiq`. The Session 61 handoff explicitly tagged this bead
as the highest-value path to closing `6oc` criterion (d) at L=8. Phasing:
ground truth → red TDD → primitives → integration → bench → ship. About one
session of Opus time end-to-end.

### Headline result

The `mbu=true, mbu_compute=true` pair closes 6oc(d) at L=8 exactly:

| L  | best ratio (mbu_compute=true) | c_mul | Verdict |
|----|------|---|---|
| 8  | **0.500×** | 5 | ✓ meets 0.5× target |
| 10 | 0.456× | 4 | ✓ |
| 12 | 0.414× | 5 | ✓ |

vs the Session 61 Stage 4 baseline (`mbu=true` only):

| L  | mbu=true best | mbu_compute=true best | Δ |
|----|---|---|---|
| 8  | 0.554× | **0.500×** | 0.054 better |
| 10 | 0.489× | 0.456× | 0.033 |
| 12 | 0.465× | 0.414× | 0.051 |

The L=8 closure is *tight* under the Session 50b T-proxy weighting
(`7·CCX + 14·CCCX + rot + 2·crot + 6·ccrot`); the bench reports 0.500×
with `c_mul=5, k_b=4`. If the proxy weights shift the closure could go
either way — I noted this in `bd memories vbz-dynamic-k-b`.

### Stage shape (mirrors 9ij)

  * **Stage A — primitives + classical helpers**, `src/library/arithmetic.jl`:
      * `_app_b_sigma_perm(l, i, c)` — closed-form σ_l permutation for the
        descending pair-block-swap S subroutine. `σ_l(i) = i ⊻ (l & mask_i)`,
        `mask_i = ~((1<<h_i) - 1) & (k − 1)`, `h_i = floor(log₂ i)` (h_0 ≡ -1
        ⇒ mask all c bits, σ_l(0) = l). Verified k ∈ {1,2,3,4} brute-force.
      * `_stacked_permuted_table(tbl, k)` — classical preprocessor: kM-bit
        stacked entries packed as `Σ_i tbl[h·k + σ_l(i)] · 2^(i·M)`.
      * `_app_b_swap_cascade!(scratch_full, addr_lo, M)` — quantum: high-bit-
        first level loop, `M·(k−1)` Fredkin gates total, calls into the
        9ij `_fredkin!` helper.
      * `qrom_lookup_xor_cleanancilla!(scratch_full, addr, tbl; k)` — App B
        forward (Berry Thm 2, Eq. 66). `T` (lookup at addr_hi targeting all
        `kM` scratch wires using the existing Bennett `qrom_lookup_xor!`)
        followed by `S` (the swap cascade). Public, exported.
      * `qrom_lookup_uncompute_meas_cleanancilla!(...)` — matching reverse.
        Builds the σ-permuted full-d table and delegates to the existing
        `qrom_lookup_uncompute_meas!` (App C clean-ancilla phase fixup).

  * **Stage B — integration**:
      * `mbu_compute::Bool=false` kwarg on `plus_equal_product_mod!` and
        on `_shor_mulmod_E_controlled!`. The kwarg is orthogonal to `mbu`
        but requires `mbu=true` (the App B forward post-state has no
        naive XOR-undo path; it must be consumed via X-basis measurement).
      * `_pep_mod_iter!` chooses `k_b` dynamically: search powers of 2
        with `k·Wtot ≤ 64`, pick the smallest analytical Sturm cost
        `4·(2^(w − log₂k) − 1) + Wtot·(k − 1)` vs the no-App-B baseline
        `4·(2^w − 1)`. Falls back to no-App-B when nothing wins —
        avoids the c_mul=2 regression that hardcoded `k_b=2` produced
        (W=9 ≥ 2^3=8 → App B doesn't pay).

  * **Bench** — `probe_toffoli_vbz_sweep.jl` (project root, sibling of
    Session 61's `probe_toffoli_cmul_sweep_mbu.jl`). Three-column table per
    L with (mbu=F, mbu_compute=F) baseline, (T,F) Session-61 best, (T,T)
    vbz target. ~10 s total runtime across L ∈ {8,10,12} × c_mul ∈ {2..5}.

### Tests — `test/test_windowed_arithmetic.jl`

317 net-new assertions across 5 testsets (TDD red-then-green):

```text
_app_b_sigma_perm                         | 114/114
_stacked_permuted_table                   |  34/34
qrom_lookup_xor_cleanancilla!             |  92/92
qrom_lookup_uncompute_meas_cleanancilla!  |  72/72
plus_equal_product_mod! mbu_compute kwarg |   5/5
```

Plus the existing 9ij Stage 1/2/3 testsets (744 + 53 + 17 = 814) and the
plus_equal_product_mod!/_shor_mulmod_E_controlled!/shor_order_E baselines
(30 + 2 + 1 = 33) — all still green.

### Stale-bead-text catches

The bead description's "Fig 4" reference points at App A (dirty ancillae).
App B (clean ancillae) is *text only* on page 25 of
`docs/physics/berry_*.pdf`. The matching figure shows the dirty variant —
not what we want. Lesson logged so future agents don't waste time
trying to derive Fig 4 directly.

The bead also predicted "forward cost drops from 28 CCX to ~8 CCX per
lookup" — this assumes the bare Berry count without Sturm's 4× Bennett
overhead on the inner table lookup. Practical Sturm savings are smaller.
See `bd memories app-b-vs-bennett-overhead`. The dynamic k_b heuristic
gets us to 0.500× exactly — a 9.7% improvement over mbu=true alone, not
the bead-projected 53%.

### Surprising finds

  * **App B's `S` is more elegant than the paper makes it look.** "Series
    of Mk controlled swaps" is misleading at first read: the actual
    construction is a *descending tree of pair-block-swaps* with k−1
    register-level swaps total (not Mk). Each register-level swap is M
    Fredkins. Worked out by tracing k=4 and k=8 by hand; closed-form σ_l
    derived from there.

  * **Code reuse via `tbl_eff` is the cleanest interface.** I worried for
    a while about whether the matching reverse needed its own primitive
    duplicating the App C Fig 6 phase-fixup logic. It does NOT — calling
    the existing `qrom_lookup_uncompute_meas!` with the σ-permuted
    full-d table (built classically) does exactly the right thing,
    because App C's phase-fixup pattern only depends on `(table, scratch
    width)` and works for any width that fits. The new
    `qrom_lookup_uncompute_meas_cleanancilla!` is mostly preconditions +
    table construction + delegation.

  * **`k_b` selection matters.** Hardcoded `k_b=2` left L=8 at 0.513×;
    dynamic `k_b ∈ {2, 4, 8, …}` selection brings it to 0.500×. The
    analytical heuristic also auto-disables App B at small w (where it
    regresses) — same code path handles the c_mul=2 fallback to
    no-App-B.

### Files touched

  * `src/library/arithmetic.jl` — five new functions (helpers + two
    primitives), `mbu_compute` kwarg on `plus_equal_product_mod!`,
    dynamic-k_b loop in `_pep_mod_iter!`.
  * `src/library/shor.jl` — `mbu_compute` kwarg on
    `_shor_mulmod_E_controlled!`, threaded into both
    `plus_equal_product_mod!` calls.
  * `src/Sturm.jl` — export `qrom_lookup_xor_cleanancilla!`.
  * `test/test_windowed_arithmetic.jl` — five new testsets.
  * `probe_toffoli_vbz_sweep.jl` (new at project root).
  * `WORKLOG.md` — this entry.

### Next levers (not in vbz scope)

  * **Hand-rolled Babbush-Gidney unary iteration** for the inner T
    lookup, bypassing Bennett's 4× compile overhead. Would cut App B
    forward cost by ~75% per lookup. Filing as follow-on bead.
  * **Extend `k·Wtot > 64`** via UInt128 (or Vector{UInt64}) stacked-
    table storage. Unlocks `k_b=8` at L=10, `k_b=16` at higher L. Useful
    above c_mul ≈ 6.
  * **`6oc(a)(b)(c)`** still blocked by `Sturm.jl-059` perf
    (~21 min/call at N=15).

### Memories updated

  * `app-b-vs-bennett-overhead` — added during ground-truth phase, lists
    the σ_l formula and the Sturm Bennett-overhead caveat.
  * `vbz-dynamic-k-b` — added after the bench, documents the dynamic
    k_b heuristic and the L=8 tight closure.

---

