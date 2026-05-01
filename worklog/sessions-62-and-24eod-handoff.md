## 2026-04-25 — Session 62: close `eiq` (CasesNode consumer fail-loud policy)

Warm-up bead picked from the Session 61 handoff list. Closed cleanly in
one pass. Touch points: 4 source files, 1 new test file (15 assertions),
0 physics changes (this is IR plumbing, no Hamiltonian on file).

### What I changed

| File | Change |
|------|--------|
| `src/channel/channel.jl:20-32` | `Channel{In,Out}(::Vector{DAGNode}, ...)` compat ctor errors loudly on any non-`HotNode` (was: silent strip). Migration message points at `optimise(ch, :deferred)` and the raw-DAG `to_openqasm`. |
| `src/passes/gate_cancel.jl:33-49` | `gate_cancel(::Vector{DAGNode})` compat overload errors loudly on any non-`HotNode` (was: silent strip). Same migration message. |
| `src/channel/draw.jl:310-326` | `_draw_node!(::CasesNode, …)` adds `@warn maxlog=1 _id=(:sturm_cases_render_ascii, file, line)`, reusing the `_first_user_frame` helper from `f23`. Placeholder glyph preserved. |
| `src/channel/pixels.jl:415-426` | `_paint_node_px!(::CasesNode, …)` same warn idiom, `_id=:sturm_cases_render_pixels`. Magenta stripe preserved. |
| `test/test_cases_consumer_policy.jl` (new, 15 tests) | Pins all four behaviours plus a sanity test for the openqasm dynamic-circuit path that bead criterion (a) wanted erroring (see "Stale bead criterion" below). |
| `test/runtests.jl:58` | Wires the new test file in after `test_openqasm_cases.jl`. |

### Stale bead criterion (a) — openqasm.jl

The bead description from 2026-04-17 said openqasm.jl "silently emits
nothing (line ~112)" for CasesNode and asked for it to error. That is
**stale** — a later session (the `tak` bead, see
`src/channel/openqasm.jl:148-172`) added OpenQASM 3 dynamic-circuit
emission so a raw-DAG `to_openqasm` now emits
`if (c[i] == 1) { ... } else { ... }` for IBM/Quantinuum hardware. The
docstring at line 9-13 explicitly documents this as the design.

If I had implemented criterion (a) as written I would have regressed the
hardware-export path. **Lesson: when picking up an old bead, always
diff the bead description against the current source before scoping**.
The other three criteria (b)(c)(d) were all live; (a) was obsolete.

The `to_openqasm raw-DAG form emits dynamic-circuit if for CasesNode`
test inside the new test file is a sanity pin so a future "fail-loud
sweep" doesn't accidentally re-regress it.

### Bead criterion (b) — gate_cancel "already correct"

The bead text says `(b) gate_cancel leaves CasesNode untouched (already
correct)`. The bead writer was thinking of the main per-wire pass —
which **does** treat CasesNode as a barrier via
`_barrier_wires(n::CasesNode)` at `src/passes/gate_cancel.jl:216-221`.
What they missed was the `gate_cancel(::Vector{DAGNode})` compat
overload at line 34-36 which silently filtered non-HotNode nodes out
*before* they reached the pass internals. Same footgun shape as the
Channel compat ctor at `channel.jl:20-22`.

I treated "(b) already correct" as describing-the-spec, not
describing-the-implementation: the spec says "leave CasesNode
untouched", and the right way to satisfy that without silent data loss
is to error. Existing test_passes.jl tests that pass `Vector{DAGNode}`
with HotNode-only contents (the standard idiom) still work — the check
fires only when a non-HotNode is actually present.

### Pattern reuse: warn-once-per-source-location

Both renderer warnings use the same `_first_user_frame` +
`maxlog=1 _id=(:..., file, line)` pattern that f23 (P2 implicit-cast
warning) introduced. The dedup id keys on the user's source location, so
loop iterations at one site share one warning, two distinct sites each
warn once. `_first_user_frame` walks the stacktrace and returns the
first frame outside the Sturm source tree.

If a future bead adds more "this is a v1 placeholder, beware" warnings,
keep using this idiom and add a fresh `_id` symbol per warning class
(`:sturm_cases_render_ascii`, `:sturm_cases_render_pixels` here).

### Surprising find: the renderer CasesNode methods are currently dead code

`Channel.dag` is typed `Vector{HotNode}` (`channel.jl:11`), and
`to_ascii(::Channel)` / `to_png(::Channel)` are the only public renderer
entries. Trace-emitted Channels never carry CasesNode (the constructor
now errors if anyone tries to insert one). So the `_draw_node!(::CasesNode, …)`
placeholder at `draw.jl:310` and `_paint_node_px!(::CasesNode, …)` at
`pixels.jl:415` are unreachable from the public API today.

Why did I add the warning anyway? (a) cheap insurance — if a future
raw-DAG renderer entry ships, the warning lights up automatically;
(b) the bead spec explicitly asked for it; (c) the dead-code sites also
lack `_draw_touches(::CasesNode)` / `_glyph_width(::CasesNode)` methods,
so any plumbing that bypasses the Channel ctor would `MethodError`
before the warning fired — which is itself fail-loud. Defence in
depth.

To exercise the warning anyway, the new test file calls
`_draw_node!` and `_paint_node_px!` directly with a hand-rolled
`CasesNode`. This also serves as the API contract: the warning fires on
the dispatched method, not on a wrapper.

### Verification

```text
test_cases_consumer_policy.jl   15/15  (new)
test_passes.jl                  49/49
test_cases.jl                   36/36
test_openqasm_cases.jl          17/17
test_channel.jl                 44/44
test_draw.jl                    53/53
test_pixels.jl                  74/74
```

288 assertions across the affected consumer surface, no regressions.
Per memory `sturm-jl-test-suite-slow` the full suite was not run; the
six existing files cover every consumer site I touched.

### Other lessons

- **`@test_logs (:warn, regex) begin … end` is the right idiom** for
  warn-once tests. First draft used `Test.TestLogger` directly with two
  back-to-back calls — verbose, and `@test_logs` already gives the
  right matcher. Reference: `test/test_implicit_cast.jl:40-46`.
- **`Sturm._resolve_scheme(:birren_dark)` is the public-internal scheme
  accessor**, not `_pixel_scheme` (which I guessed at first). Pixel
  scheme fields: `bg`, `q_wire`, `c_wire`, `control`, `target`, `gate`,
  `prep`, `measurement`, `discard`, `connector`, `shadow`. See
  `src/channel/pixels.jl:79-88` for the struct.
- **`_first_user_frame` is in `src/types/quantum.jl:68` and exported
  module-internally** — callable from anywhere in `src/` as the
  unqualified `_first_user_frame`. Two existing call sites
  (`_warn_implicit_cast`, `_warn_direct_measure`) plus the two new
  renderer warnings. If a third class of warning shows up, this is the
  hook.

### Files touched

- `src/channel/channel.jl`, `src/passes/gate_cancel.jl`,
  `src/channel/draw.jl`, `src/channel/pixels.jl`
- `test/test_cases_consumer_policy.jl` (new),
  `test/runtests.jl` (include line)
- `WORKLOG.md` (this entry)

---

## 2026-04-24 — Session end: handoff for next agent

Orient yourself before touching anything:

```bash
git log --oneline -10       # 2026-04-24 commits start at af480e8 and below
bd ready -n 10              # open work queue
bd list --status=open -n 30 # full open set
```

### Where the project stands as of this commit (48640e8)

  * **Warm-ups landed** — `guj` (bench_shor_scaling Int64 overflow),
    `35s` (X↔Y discriminator for Grover/phase_flip!), `9g5` (same for
    block_encoding _flip_for_index!). All three ship phase-invariant
    ratio-based test patterns (Sessions 58–60 technique); future drift
    hardening in other circuits should reuse this idiom rather than
    reinventing it.
  * **`9ij` (MBU) closed** — Berry et al. 2019 arXiv:1902.02134 App C
    Thm 3 measurement-based QROM uncomputation landed end-to-end
    across 5 stages (bvq/123/1q9/7cl/4hz). Public API:
    `qrom_lookup_uncompute_meas!(scratch, addr, tbl)` in
    `src/library/arithmetic.jl`, plus a new `mbu::Bool=false` kwarg on
    `plus_equal_product_mod!` and `_shor_mulmod_E_controlled!`. Full
    test story: 744 + 53 + 17 = 814 assertions, plus a dedicated
    `probe_toffoli_cmul_sweep_mbu.jl` bench across L ∈ {8,10,12}.
  * **6oc status as of this commit**:
      * Criterion (a)(b)(c): still blocked by `Sturm.jl-059` (perf —
        `_shor_mulmod_E_controlled!` at N=15 is ~21 min/call,
        distributed cost across JIT + FFI + many small gates; Session
        49 already did the zero-copy `unsafe_wrap` fix and `@profile`
        found no single hotspot).
      * Criterion (d): 0.554× at L=8 (c_mul=3, mbu=true) — **0.054×
        short of the 0.5× target under strict reading**. At L=10 and
        L=12 the criterion is met (0.489×, 0.465×). Gap driven by
        forward QROM cost — MBU only halves the reverse. Next lever
        filed as `Sturm.jl-vbz` (Berry App B Thm 2 clean-ancilla
        forward compute).

### Open beads most worth picking up next

1. **`Sturm.jl-vbz` (P2)** — close 6oc (d) at L=8 via Berry Appendix B
   Theorem 2 / Figure 4, the clean-ancilla-assisted forward QROM. With
   MBU already in place on the reverse, adding the forward sqrt-Toffoli
   construction should drop L=8 c_mul=3 T-proxy from 5181 (current
   mbu=true) to ~3500–4000, putting E/D below 0.5×. Ground truth is
   `docs/physics/berry_gidney_motta_mcclean_babbush_2019_qubitization.pdf`
   App B Thm 2 (Eq. 66) + Fig 4. Scope ≈ one more primitive
   (`qrom_lookup_xor_cleanancilla!`), new `mbu_compute::Bool=false`
   kwarg, mirrors the stage-shape of 9ij.
2. **`Sturm.jl-059` (P2)** — 21 min/call perf bug. Harder, structural.
   Session 49 WORKLOG has the profiler notes; Session 50 pivoted to
   Toffoli-count metrics as a result. Only pick this up if you enjoy
   simulator-guts spelunking and have time to read Orkan's FFI story.
   Related lead: `Sturm.jl-2i0` (task_local_storage → ScopedValue).
3. Qudit track **`csw`, `2bf`, `os4`, `mle`, `p38`** — all unblocked by
   Session 57's QMod{5} Ry land; no MBU dependency. Good parallel work
   if someone wants to avoid the Shor critical path.
4. `eiq` — CasesNode consumer fail-loud policy. Mechanical, four files,
   matches Rule 1. Session 61 considered this but took 6oc instead.

### Non-obvious traps from this session (write these down, don't rediscover)

  * **TracingContext & measurement**: `Bool(q)` throws loudly inside
    `TracingContext` (`src/context/tracing.jl:145-156`). Any primitive
    that measures for classical post-processing (like MBU) needs an
    `is_tracing = ctx isa TracingContext` branch that substitutes
    `ptrace!` for the measurement and uses a canonical placeholder in
    any classical computation. The circuit Toffoli count is preserved
    because it only depends on dimensions, not on the classical values.
    See `qrom_lookup_uncompute_meas!` for the reference pattern.
  * **`_binary_to_unary!` is NOT same-order-self-inverse at Wlo ≥ 2**.
    Uncompute must traverse `b` from Wlo−1 down to 0 (kwarg
    `uncompute=true`). Within a single `b`-level the Fredkin order
    doesn't matter (disjoint targets commute); across levels it does.
  * **`_fredkin!(ctrl, a, b)` costs 1 Toffoli + 2 CNOTs**. The obvious
    spelling `when(ctrl) do swap!(a, b) end` costs 3 Toffolis because
    each of `swap!`'s 3 CNOTs gets lifted to CCX under `when`. Anywhere
    you need a controlled SWAP inside a `when`, use `_fredkin!`.
  * **`qrom_lookup_xor!` in Sturm costs `4·(2^c − 1)` Toffolis per
    call**, not the `2^c − 1` of the abstract Babbush-Gidney
    construction — the 4× overhead comes from Bennett's compile. So the
    WORKLOG Session 50b prediction that MBU alone would close L=8 to
    ≤0.5× was off by the forward-QROM cost; it closes at L=10 instead.
  * **Global phase in ratio assertions**. The Session 59–60 pattern is
    `r = post[ref_idx] / pre[ref_idx]; @test abs(post[k]/pre[k] − r) <
    tol` for k ≠ ref. CLAUDE.md "Global Phase and Universality" is
    load-bearing — do not write phase-naïve assertions in channel
    tests, ever.
  * **`bd create` + `::` in Bash prose**: `bd create ... --description="...
    mbu::Bool=false kwarg ..."` gets the `::` eaten by bash and the
    description truncated. Use `bd update --notes="..."` to complete
    descriptions that contain `::`, or avoid it in bash prose.
  * **`bd dolt push` from a stale local**: fails non-fast-forward until
    you `dolt fetch origin && dolt pull origin main` from inside
    `.beads/embeddeddolt/Sturm_jl/`. Memory `beads-sync-workaround-for
    -sturm-jl-bd-dolt` has the full recipe.

### Environment (inherit these)

  * `LIBORKAN_PATH=/home/tobiasosborne/Projects/orkan/cmake-build-release/src/liborkan.so`
  * `OMP_NUM_THREADS=16` (strict, per memory `orkan-thread-limit`)
  * Never run the full test suite on this device — per memory
    `sturm-jl-test-suite-slow`. Run individual test files via
    `julia --project -e 'using Sturm; include("test/test_X.jl")'`.
  * Julia runs strictly serial on this device (memory
    `feedback_julia_serial_only`) — no parallel `julia` processes.
  * Verbose output must eager-flush stage by stage (memory
    `feedback_verbose_eager_flush`) — blank waiting is a fail.

### Memory entries worth knowing

```
bd memories beads-storage       # where beads live
bd memories beads-sync          # dolt merge recipe
bd memories orkan               # thread limit + LIBORKAN_PATH
bd memories test-suite-slow     # never run Pkg.test() here
bd memories oaa                 # BS+NLFT tricky bug (Session 13)
bd memories p9-axiom            # P9 can't be literal per Julia rules
```

### Latest commits on main (origin/main up to date)

```
48640e8 feat(9ij-stage4): MBU Toffoli bench — closes 6oc (d) at L=10
f1375aa feat(9ij-stage3): mbu kwarg on plus_equal_product_mod! + _shor_mulmod_E_controlled!
99c845b feat(9ij-stage2): qrom_lookup_uncompute_meas! primitive
58b6320 feat(9ij-stage1): _binary_to_unary! + _fredkin! helpers
a7ad1ee docs(9ij-stage0): ground MBU construction in Berry et al. 2019 App C
514ac23 test(9g5): X↔Y drift discriminators for block_encoding _flip_for_index!
0258c80 test(35s): X↔Y convention-drift discriminators for _diffusion! / phase_flip!
3a32219 fix(guj): bench_shor_scaling estimate_bytes overflow at L=18 impl B
```

### Session sequence for the full story

Read sessions 58 → 61 for the current session's full narrative; 42 for
the X↔Y swap backstory that 35s/9g5 harden; 45–50 for the 6oc build-up
that 9ij slots into. Earlier sessions archived in `WORKLOG-archive.md`.

---

