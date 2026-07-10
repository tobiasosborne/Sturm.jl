# M5 Proposal A — `when`: streaming coherent control + guardrails + deferred teleport

**Proposer A. Lens: SEMANTICS AND GUARDRAIL COMPLETENESS FIRST.**
Bead Sturm.jl-o5yh. Files: `src/surface/when.jl` (new), a minimal refactor of
`src/orkan/ad.jl` (the `apply!` choke point), one new field on `ContextCore`
(`src/context/abstract.jl`), and guardrail checks threaded into the existing
consuming/tracing sites. 3+1 is required because this touches the context
interface (a new field), the `apply!` path, and the trace lowering.

The governing idea in one sentence: **`when` is a control-stack push/pop
around the body closure, and `apply!` is the ONE place that reads the stack
and wraps each op in `ctrl^k` — every guardrail is then a check placed at the
exact surface funnel that a banned effect must pass through, and I prove below
that those funnels are exhaustive against the current surface.**

---

## 0. What already exists (so M5 adds almost no lowering)

- `ctrl.jl`: `Ctrl{V}` (flat count `k`), `ctrl(::U2|::Ctrl|::Tensor|::Seq)`,
  `ctrl(::Perm)::Perm`, `∘(Ctrl,Ctrl)` fusing on equal `k`, `adjoint`. The
  homomorphism `ctrl(g∘h)=ctrl(g)∘ctrl(h)` (Delorme functoriality, Def 1 /
  p.7) **is** the streaming license (D13/§3.5).
- `ad.jl`: `_apply_controlled!` lowers `Ctrl` of `U2`/`Perm`/`Tensor`/`Seq`
  onto Orkan qubits — phase-exact (ABC skeleton + Lemma 5.2 phase line),
  `k=2` via ancilla-free √V (Lemma 6.1), `k≥3` via clean-|0⟩ AND-ladder
  (Cor 7.12). `apply!(ctx, v, wires)` does aliasing → liveness → flush →
  `_emit!`. There is also a `U2` 1-wire **fast path** that fuses into the
  per-wire buffer without `_emit!`.
- `abstract.jl`: `ContextCore` with `region_stack::Vector{Vector{WireID}}`
  (push/pop model to imitate), `_marginal_p1`, `_flush_all!`, slot allocator.
- `views.jl`: `_parent_wire(handle)::WireID` resolves any view to its parent
  wire (the M4 hook the guardrails consume); `_dual_transform(::QBool)=H`;
  `_conj`.
- `regions.jl`: `_exit_region!` traces owned wires via `_trace_and_free!`;
  `ptrace!`; `region() do…end`.

**M5 writes NO new controlled-lowering code.** It adds: one field, one
stack-consulting wrapper on `apply!`, `when`, and four one-line guardrail
checks. Every controlled op reaches Orkan through the *existing* `ad.jl`
paths, so streaming is phase-exact by construction (§3, below).

---

## 1. `when(q) do … end` semantics

### 1.1 Where the control stack lives — a **field on `ContextCore`**

Add `control_stack::Vector{WireID}` to `ContextCore` (initialised `WireID[]`),
sitting beside `region_stack` and threaded through exactly the same way.

Rejected alternative: a `ScopedValue` holding an immutable stack, rebound per
`when` with `with(...)`. Rejected because `apply!` — the hot per-op choke
point — would then have to *read* a `ScopedValue` on every op, and
`ScopedValue` access allocates (CLAUDE.md conv 6, explicit). `apply!` already
receives `ctx` (surface ops pass `_here(q)`, asserted `=== current_context()`),
so `ctx.core.control_stack` is reachable with zero allocation and zero extra
lookup. The field is the choke-point-friendly choice.

**Nesting.** `when` pushes one `WireID`, pops it in `finally`. Depth = `k`.
Nested `when` ⇒ stack `[c₁,…,c_k]` ⇒ `ctrl^k` (flat `Ctrl(k,·)`). Push/pop
mirrors `region_stack`, so nesting composes for free.

**`Threads.@spawn`.** The control stack rides on the *ctx object*, which is
already propagated to spawned children by the `CURRENT_CONTEXT` ScopedValue
(regions.jl). A child therefore observes the **same, consistent** control
stack — never the silent-missing-context bug class that killed
`task_local_storage` (conv 6). This is *strictly better* than a
ScopedValue-of-stack, and it is identical to how `region_stack` already
behaves. Genuinely-parallel `when` bodies remain out of scope (risk register
item 5: "one region, one task", stated not enforced); M5 does not regress
that boundary, it inherits it.

### 1.2 The single choke point — `apply!` wraps in `ctrl`

Refactor `ad.jl` minimally: rename the current body of
`apply!(ctx, v::ProcessValue, wires)` to `_apply_uncontrolled!(ctx, v, wires)`
(unchanged: aliasing → liveness → flush → `_emit!`). The public `apply!`
becomes a thin stack-consulting wrapper:

```
apply!(ctx, v, wires):
    cs = _core(ctx).control_stack
    isempty(cs) && return _apply_uncontrolled!(ctx, v, wires)
    _guard1_no_cast_under_control(...)   # (v is unitary; no check needed here — casts never call apply!)
    cv = v; for _ in cs: cv = ctrl(cv)   # ctrl^k → flat Ctrl(k, base)
    allwires = (cs..., wires...)         # controls FIRST (MSB), matching _emit!(Ctrl)'s qs[1:k] split
    return _apply_uncontrolled!(ctx, cv, allwires)
```

The `U2` 1-wire **fast path** must also consult the stack **before fusing**:

```
apply!(ctx, u::U2, (w,)):
    cs = _core(ctx).control_stack
    isempty(cs) && return _fuse!(ctx, w, u)      # unchanged fast path
    return apply!(ctx, u, (w,)::wrapped-general)  # i.e. wrap ctrl^k, emit immediately
```

This is the load-bearing correctness point the lens demands: **a bare `U2`
must never enter the per-wire fusion buffer while the control stack is
nonempty**, or it would later flush as an *uncontrolled* op — silently
dropping the control (a §8.1-class hole). Under control, the U2 is wrapped
and emitted immediately.

Because `_apply_uncontrolled!` runs `_check_wire_aliasing` on the full
`(controls…, targets…)` tuple, guardrail 2 (below) is enforced here for free,
with an explicit better-message check layered in front.

Re-entrancy safety: the wrapper calls `_apply_uncontrolled!` (which does *not*
re-read the stack), never `apply!` — so no double-wrapping.

### 1.3 `when(dual(q))` — conjugated control wire

Control in the conjugate basis = conjugate the control wire by its character
transform `F_G` (Delorme §7, p.8: "recover the various examples … by
conjugating the control qubit with NOT or Hadamard gates"; for `QBool`,
`F_G = _dual_transform(::QBool) = H`). Mechanics, entirely through existing M4
machinery:

```
when(f, v::DualView):
    p = v.parent; ctx = _here(p); V = _dual_transform(p)     # H for QBool
    apply!(ctx, V, (p.wire,))          # rotate dual basis → computational (fuses as U2, M2)
    _push_control!(ctx, p.wire)
    try f() finally _pop_control!(ctx, p.wire) end
    apply!(ctx, adjoint(V), (p.wire,)) # restore
    return nothing
```

Proof it is `C_{|−⟩}`: `(H⊗I)·C_{|1⟩}(U)·(H⊗I) = H|1⟩⟨1|H⊗U + H|0⟩⟨0|H⊗I =
|−⟩⟨−|⊗U + |+⟩⟨+|⊗I`. Fires exactly when `q` is in the dual's "true" state
`|−⟩` — which is the §7.1b Z-correction (`|−⟩⟨−|⊗Z`). The pushed control wire
is the *parent* `p.wire`, so guardrail 2 (`_parent_wire`-based) still sees `q`:
`when(dual(q)) do not!(dual(q)) end` aliases and errors. Direction (`V`
before / `V†` after) is unobservable for self-adjoint `H`; for `QInt` (M6,
`F≠F†`) it is pinned by the Pontryagin unit test, consistent with `_conj`'s
`adjoint(V)∘g∘V` convention.

Note: the first controlled op in the body flushes `p.wire`'s buffer (emitting
`V` to Orkan) before its `CX`/`CZ` — so ordering is correct without a forced
flush on entry.

### 1.4 Nested `when` = Toffoli-grade

`when(a) do when(b) do not!(c) end end`: stack grows to `[a,b]`, so `not!(c)`
(base `X`) is applied as `ctrl(ctrl(X)) = Ctrl(2,X)` on `(a,b,c)` →
`_apply_controlled!` k=2 X-branch → native `_emit_ccx!` (Toffoli). Deeper
nests ride the `k≥3` AND-ladder. The two controls are interchangeable
(Delorme Eq 14) — flat count is the faithful normal form (already in
`ctrl.jl`).

---

## 2. The guardrails as runtime laws — and a completeness proof

### 2.1 Enumerate EVERY surface entry point that reaches the context

Grepping `src/surface/`, `src/types/qbool.jl`, `src/kernel/views.jl` for every
mutating/consuming/allocating surface funnel (the lens's central task):

| # | Surface entry | Effect class | Reaches ctx via | Under control |
|---|---|---|---|---|
| 1 | `QBool(p,φ)`, `QBool(b)`, `plus/minus/magic_T` | prep (alloc + unitary) | `allocate!` (alloc) + `apply!` (prep) | **allowed** — alloc uncontrolled \|0⟩; prep `apply!` becomes controlled (choke-point uniform) |
| 2 | `not!(q)`, `not!(dual q)` | unitary flip / modulation | `apply!` | **controlled** (streaming) |
| 3 | `xor(q,q)`, `xor(q,Bool)`, `xor(Bool,q)`, `xor(dualView,q)` | unitary entangle / mixed / CZ | `apply!` (+ `allocate!` in the fresh form) | **controlled** |
| 4 | `Bool(q::QBool)` | **qc measurement cast** | `_measure_wire!` | **BANNED — loud error (guardrail 1; §8.1 #1)** |
| 5 | `Bool(v::DualView)` | conjugate-basis measurement | calls `apply!(H)` then `Bool(parent)` | **BANNED** (funnels through #4) |
| 6 | `convert(Bool, q)` | implicit measurement (P2) | calls `Bool(q)` | **BANNED** (funnels through #4) |
| 7 | `ptrace!(w)` / `ptrace!(ctx,w)` | explicit trace + consume | `_trace_and_free!` + `mark_consumed!` | **BANNED — explicit consumption under control** |
| 8 | `deallocate!(w)` / region-exit `_trace_and_free!` | dealloc of owned local | `_trace_and_free!` → `trace_wire!` | **clean-ancilla assertion** (not banned; §3.9) |
| 9 | `apply_channel!` (DM noise) | non-unitary Kraus | `_apply_channel_1q!` | **BANNED — noise under control** |
| 10 | `cases`/`@cases` | classical branch (M8) | (M8) | **BANNED — forward hook (guardrail 1)** |
| 11 | `oracle(f,x)` + MBU strategy (M7) | Bennett | (M7) | **MBU excluded** — reads `control_stack` (§3.4) |

**Completeness argument.** Guardrail 1 must ban every *non-injective /
non-unitary* transition inside `when` (YVC Thm 4.4 No-Embedding: non-injective
⟹ NO quantum embedding, full stop; BP Condition III: reversibility). The only
non-unitary surface effects are: (a) measurement collapse, (b) partial trace
that forgets, (c) noise. **Every one of these funnels through exactly one of
three context primitives**: measurement → `_measure_wire!` (#4–6); trace →
`_trace_and_free!` (#7, #8); noise → `_apply_channel_1q!` (#9). Placing the
control-stack check at those three funnels (plus the `cases` forward hook #10)
is therefore *exhaustive over the current surface* — nothing non-unitary can
reach Orkan under control without passing one of them. Everything else the
surface can do is unitary (`apply!`), and unitary is exactly what `ctrl`
represents. QED for the M5 surface. (When M8 adds `cases` and M7 adds
`oracle`/MBU, each adds its own entry to this table and its own check — the
table is the maintained coverage map.)

Note #8 vs #7 is the subtle line the lens must get right: **explicit** trace
(`ptrace!`, `Bool`) is banned; **implicit** region-exit dealloc of an owned
local is the clean-ancilla pattern (§3.9) — asserted, not banned. Same
mechanism (`_trace_and_free!`) but branched on the *caller's intent*: `ptrace!`
guards and errors before calling `_trace_and_free!`; `_exit_region!` lets it
through to the clean-ancilla path.

### 2.2 Placement (minimal, funnel-level)

- **Guardrail 1a (measurement):** one check at the top of `Bool(q::QBool)`
  (casts.jl): `isempty(ctx.control_stack) || error(...)`. Covers #4, #5
  (`Bool(dual)` calls it), #6 (`convert` calls it). Grounds: YVC Thm 4.4;
  BP Condition III (p.35); §4.4 measurement-under-ctrl unrepresentable; the
  §8.1 "most dangerous hole".
- **Guardrail 1b (explicit trace):** one check at the top of `ptrace!`
  (regions.jl) before `_trace_and_free!`.
- **Guardrail 1c (noise):** one check in `apply_channel!` / `_apply_channel_1q!`
  (density.jl).
- **Guardrail 1d (cases, M8):** forward hook — documented requirement that
  M8's `cases`/`@cases` and the `Bool→ClassicalBit` token path check the
  control stack. Not testable in M5 (no `cases` yet); named in the M8 bead.
- **Guardrail 2 (guard-externality):** the control wires prepended by §1.2 are
  *resolved parent* `WireID`s; `_apply_uncontrolled!`'s existing
  `_check_wire_aliasing` fires if a control equals a target. Layer an explicit
  when-specific check in the wrapper (resolve via `_parent_wire`, error citing
  YYF Def 2.1(4) / BP Condition I) so the message names guard-externality, not
  generic §8.4. Grounds: YYF Def 2.1(4) (`q ∩ ⋃ qVar(Pᵢ)=∅`); BP Condition I;
  YVC guardrail 2 = the `C×D` split.
- **Guardrail 3 (bounded unrolling):** streaming naturally unrolls whatever the
  closure does; unbounded recursion under `when` streams forever — the user's
  bug (matches "bounded unrolling only"). No dedicated M5 detector; grounded in
  BP non-monotonicity Proposition (p.39).

### 2.3 The clean-ancilla check — physically exact, cheaply implemented

**The physics (get it right — lens deliverable).** §3.9 / YVC synchronization
(Def 4.7, Thm 4.8): the streaming identity `alloc → ctrl(U) → dealloc =
ctrl(dealloc∘U∘alloc)` holds **iff** `U` returns the ancilla to `|0⟩` in the
control=1 branch. In the control=0 branch `ctrl(U)=I`, so the ancilla is still
the fresh `|0⟩` from `alloc`. Therefore, at dealloc, the ancilla is `|0⟩` in
*every* control branch **iff** the total probability weight on ancilla=1 is
zero:
```
p1 = Σ_{i : bit(anc)=1} |ψ_i|²  =  _marginal_p1(state, slot)   (Eager)
```
`p1 = 0` ⟺ the state has zero amplitude on all ancilla=1 basis states ⟺
`ψ = |0⟩_anc ⊗ (rest)`, i.e. the ancilla is `|0⟩` **and fully disentangled**
from everything (control included). This is both necessary and sufficient for
cleanliness — it is *exactly* YVC synchronization at the wire level. An unclean
ancilla under a superposed control would leave the ancilla entangled with the
control and **decohere the control** on trace — which is why the unwitnessed
case must error loudly (§3.5).

**Orkan-level implementation & cost.** Reuse the *existing* `_marginal_p1`
(Eager) — one O(2^cap) pass, identical cost to a measurement's marginal, no
new FFI. On DM, the analogous quantity is the ancilla=1 diagonal block trace of
ρ (from the reset-channel machinery / `density_matrix` diagonal). If
`p1 ≥ CLEAN_EPS` (a numerics-file tolerance, ≈ the U2 atol) → **loud error**
naming the wire and pointing at "uncompute your scratch before it leaves the
`when` body (§3.9 witness / YVC synchronization)". If clean: **free the slot
without measuring** — no RNG draw, no collapse, no measure-and-flip (it is
certified `|0⟩`); just `delete!(wire_to_slot, w)` + `_return_slot!`. This
distinct dealloc path is the direct implementation of "under the witness, the
deallocation is not a trace at all" (§3.9).

```
_trace_and_free!(ctx, w):
    if isempty(control_stack):  <existing measure-and-discard path>
    else:                       _clean_ancilla_free!(ctx, w)   # assert p1≈0, free, no measure
```

**`region()` opened inside a `when` body.** Its `_exit_region!` traces owned
wires via `_trace_and_free!` → under the nonzero control stack → each owned
wire gets the clean-ancilla assertion (must be uncomputed to `|0⟩`), not a
measure-discard. The `_strict_check!` hook runs (inert). So a nested `region`
inside `when` is the sanctioned scratch-scope: allocate, compute, uncompute,
exit — clean or loud. This is the answer to "what happens to `region()` inside
a `when` body."

---

## 3. Exactness of streaming

**No new lowering.** The body's ops lower through the *existing* `ad.jl`
`_apply_controlled!` / `_apply_controlled_u2!` — ABC skeleton + Lemma 5.2 phase
line (phase-exact; dropping that line is the multi-year Cirq/Qiskit/pytket bug,
Tang–Wright Thm 1.1). `when` supplies only stack push/pop + the `apply!`
wrapper. The homomorphism `ctrl(g∘h)=ctrl(g)∘ctrl(h)` (Delorme functoriality)
is precisely what licenses "apply `ctrl(op)` op-by-op" = streaming (D13/§3.5).
Confirmed by reading `ad.jl`: it already dispatches `Ctrl{U2}`, `Ctrl{Perm}`,
`Ctrl{Tensor}`, `Ctrl{Seq}`, and `k≥3`. **Zero controlled-lowering code is
added in M5.**

**Fusion-buffer interaction (correctness first).** Under a nonzero control
stack, controlled ops **do not fuse** — the per-wire buffer holds a 1q `U2`,
and a `Ctrl{U2}` is a ≥2-wire operator that cannot live there. Each controlled
op flushes its involved wires (the general path already does) and emits
immediately. I reject a "controlled fusion buffer" for M5 on correctness
grounds: fusing two `Ctrl{U2}` via `∘(Ctrl,Ctrl)` requires equal control
*wires* (not just count), and getting that keying wrong mis-fuses across
distinct control sets — a silent phase/logic bug of exactly the class §3.5
exists to prevent. The right place to fuse controlled blocks is M8's
materialize-and-reassociate pass over the DAG (which already has the
`∘(Ctrl,Ctrl)` law and the conjugation/reassociation law, Delorme Eq 16). So:
**M5 = flush-and-emit, no controlled fusion; do NOT flush globally on `when`
entry** (per-op flush of involved wires suffices, and unrelated wires' 1q
buffers commute with a controlled op on disjoint wires). The uncontrolled
fast-path fusion is untouched — only *bypassed* while the stack is nonempty.

Consequence noted for M8: `when(q) do not!(dual r); not!(dual r) end`
(two `ctrl(Z)` = identity) is emitted as two gates in M5, optimized to nothing
in M8. Correct either way.

---

## 4. Deferred teleport §7.1b — THE acceptance gate

Verbatim from PRD-v2 §7.1b (lines 1104–1116):

```julia
function teleport_deferred(ψ::QBool)
    b = QBool(0.5)
    c = false ⊻ b                # Bell pair on (b, c)
    b ⊻= ψ

    when(b) do                   # deferred X-correction
        not!(c)
    end
    when(dual(ψ)) do             # deferred Z-correction: control read in the
        not!(dual(c))            # conjugate basis — |−⟩⟨−| ⊗ Z, exactly
    end
    return c                     # ψ, b: owned, unreturned — traced, silently
end
```

**Construct inventory after M5 — nothing missing:**

| Construct | Provided by | Status |
|---|---|---|
| `QBool(0.5)` | M3 | ✓ |
| `false ⊻ b` (`xor(::Bool,::QBool)`, fresh Bell half) | M4 | ✓ |
| `b ⊻= ψ` (`xor(::QBool,::QBool)`) | M4 | ✓ |
| `when(b) do … end` (`when(::Function,::QBool)`) | **M5** | new |
| `not!(c)` | M4 | ✓ |
| `when(dual(ψ)) do … end` (`when(::Function,::DualView)`) | **M5** | new |
| `not!(dual(c))` (Z) | M4 | ✓ |
| region-exit trace of ψ, b | M2 | ✓ |

**LOUD FLAG:** every §7.1b construct exists after M5. No gap.

**Why it runs one-shot on DM.** All body ops are unitary — `when(b){not!(c)}` =
`ctrl(X)` = CX, `when(dual ψ){not!(dual c)}` = `C_{|−⟩}(Z)`. **No `Bool` inside
any `when`** (guardrail 1 never trips), and the two corrections are deferred
*before* any cast, so there is no classical branching. ψ and b are traced at
the **function region's** exit — which is *outside* both `when` blocks (control
stack already empty), so those are ordinary exact ptraces on DM, not
clean-ancilla asserts. DM executes the whole channel exactly.

**The test:** `choi(teleport_deferred, 1) ≈ bell` (= `J(id)`, the coherent
rank-1 projector) in one DM run, AND `!(≈ pinched)` (proves it is coherent, not
the wm28-style diagonal-only teleport). The harness reads `J` over the returned
handle `c`'s wire (output wire ≠ input wire — already supported by `_choi1`).
Skeptic's note: a wrong Z-correction basis (computational instead of `dual`)
would show as off-diagonal error in `J` — the Choi probe catches it where a
Z-marginal could not (the §8.8/wm28 lesson).

---

## 5. Named tests

1. **nested `when` = Toffoli** — `when(a) do when(b) do not!(c) end end`
   emits `Ctrl(2,X)`; compare Eager `statevector` against dense CCX·|v⟩ over
   all 8 basis inputs + entangled probes. (Choi harness caps `nin≤2`, so
   Toffoli uses dense-statevector comparison, not Choi. Kernel-level
   `ctrl(ctrl(X))=CCX` is already tested in `test_kernel_ctrl.jl`; this test
   asserts the *surface* `when∘when` emits it.)
2. **kickback (control is input AND output)** — `when(q) do not!(dual(r)) end`
   ≡ CZ(q,r): with `r=|−⟩` the phase `−1` kicks onto `q` (`|+⟩→|−⟩`), read
   back by `Bool(dual(q))==true`. Also `choi2(...) ≈ analytic_choi2(CZ)`.
3. **anti-control sandwich** — `not!(q); when(q) do not!(r) end; not!(q)` =
   anti-controlled-X (fires on `q=0`); truth table on Eager, and
   `choi2 ≈ analytic_choi2((X⊗I)·CX·(X⊗I))`.
4. **clean-ancilla soundness** — (a) **superposed control** `q=|+⟩`:
   `when(q) do a=QBool(false); not!(a); …; not!(a) end` with matched
   uncompute → region-exit clean-ancilla assert **passes**; *unmatched*
   (`not!(a)` once) → `p1(a)=0.5` → **loud error**. (b) **entangled control**:
   `q` in a Bell pair used as `when` control — matched uncompute passes,
   unmatched errors, even though the marginal is taken over the entangled
   whole. Verifies `_marginal_p1`-based check under both superposition and
   entanglement.
5. **cast-under-control loud error (the §8.1 named regression)** —
   `when(q) do Bool(r) end` errors; also `Bool(dual(r))`, `convert(Bool,r)`,
   `ptrace!(r)`, and DM `apply_channel!` under control each error. THE most
   dangerous v0.1 hole, closed by construction.
6. **`when(dual(q))` conjugated control** — `when(dual(q)) do not!(r) end` =
   `C_{|−⟩}X`: `q=|−⟩`⇒`r` flips, `q=|+⟩`⇒`r` unchanged;
   `choi2 ≈ analytic_choi2((H⊗I)·CX·(H⊗I))`.
7. **guardrail-2 aliasing error** — `when(q) do not!(dual(q)) end`,
   `when(q) do not!(q) end`, `when(q) do q ⊻= r end`,
   `when(dual(q)) do not!(dual(q)) end` all error (control aliases target via
   `_parent_wire`), with a when-specific guard-externality message.
8. **deferred teleport Choi** — `choi(teleport_deferred,1) ≈ bell` exactly,
   one DM run; and `!≈ pinched` (coherent). The acceptance gate.
9. **homomorphism spot-check** — a body of several 1q ops under `when`
   emits the same channel as `ctrl` of their composite (Eager statevector vs
   `denoted_matrix(ctrl(g_composite))`), a direct check of the streaming
   license before M8's full Choi law.
10. **streaming ≡ materialized cross-check — IOU to M8.** The PRD §3.5
    "required law test" (streaming and materialized denote the same channel,
    Choi-compared) needs `TracingContext`/`UnitaryDAG` (M8). M5 discharges the
    *streaming* half against dense/`denoted_matrix` references (tests 1–9);
    the two-strategy Choi equality lands in M8 (plan §M8: "streaming ≡
    materialized Choi law test closes M5's IOU"). Flag carried in the M8 bead.

---

## 6. Namespace

- `when` — **surface export** (add `export when` to the M5 stanza in
  `src/Sturm.jl`, beside `dual, not!`).
- Everything else **internal, unmarked** (not even `public`): the
  `control_stack` field, `_push_control!`/`_pop_control!`,
  `_apply_uncontrolled!`, `_clean_ancilla_free!`, and the guardrail helpers.
  `when` is the only new name crossing the visibility wall — the §2 layer table
  stays mechanically honest.

---

## 7. Forward hooks recorded (so later milestones inherit cleanly)

- **M7 MBU exclusion (§3.4):** `oracle`'s strategy selector reads
  `!isempty(ctx.control_stack)` to exclude measurement-based uncompute under
  control (measurement-under-ctrl unrepresentable, §4.4 / BP p.39). M5 provides
  the stack it reads; named test lands in M7.
- **M8 `cases` guard (guardrail 1d) + streaming≡materialized law:** the
  `cases`/token path checks the control stack; the two-strategy Choi law closes
  test #10's IOU.

---

## 8. Executive summary (10 lines)

1. Control stack = a `Vector{WireID}` **field on `ContextCore`** (mirrors
   `region_stack`), push/popped by `when` in `try/finally`; rides the
   ScopedValue-propagated ctx into `@spawn` children, read by `apply!` with
   zero allocation (conv 6).
2. **`apply!` is the single choke point**: it reads the stack and wraps each op
   in `ctrl^k` on `(controls…, targets…)` — including bypassing the U2
   fast-path fusion so a bare U2 never flushes uncontrolled.
3. `when(dual(q))` = sandwich `F_G=H` on the control wire, then `|1⟩`-control;
   pushes the *parent* wire so guardrail 2 still sees `q`.
4. Nested `when` → flat `ctrl^k` → existing `ad.jl` k=2/k≥3 lowering; **no new
   controlled-lowering code**.
5. Guardrails placed at **three funnels** (measurement `_measure_wire!`, trace
   `_trace_and_free!`, noise `_apply_channel_1q!`) + a `cases` forward hook —
   proven exhaustive over the current surface (every non-unitary effect passes
   one funnel; YVC Thm 4.4).
6. Guardrail 2 is enforced by the existing `_check_wire_aliasing` on the
   prepended control wires (resolved via `_parent_wire`), plus an explicit
   when-specific message.
7. Clean-ancilla check = `_marginal_p1(slot) ≈ 0` (necessary+sufficient for
   `|0⟩`-and-disentangled; = YVC synchronization); reuses existing FFI, one
   O(2^cap) pass; clean ⇒ free without measuring; dirty ⇒ loud error.
8. `region()` inside a `when` body ⇒ its owned locals get the clean-ancilla
   assertion instead of measure-discard.
9. Streaming is phase-exact via the existing ABC+phase-line path; fusion of
   controlled ops is deferred to M8's DAG pass (correctness-first).
10. Deferred teleport §7.1b transcribes verbatim, **every construct exists
    after M5**, and `choi(teleport_deferred,1) ≈ J(id)` in one DM run is the
    acceptance gate.

## 9. Deviations from the prompt / PRD

- **Toffoli test is dense-statevector, not Choi.** The Choi harness supports
  `nin ∈ {1,2}` only (choi.jl); a 3-in Toffoli would need `nin=3`. I test
  nested `when` against a dense CCX reference on Eager over basis + entangled
  probes rather than extending the harness. (Extending `choi` to `nin=3` is a
  larger, orthogonal change; flagged, not taken.)
- **Preparation-under-control is choke-point-uniform, not special-cased.**
  `QBool(true)`/`QBool(p)` inside `when` allocate `|0⟩` uncontrolled but apply
  their prep gate *controlled* (a fresh copy-from-control / controlled-prep).
  This is a deliberate reading of "alloc uncontrolled, body controlled" (§3.9)
  that keeps `apply!` the single choke point rather than forking a
  prep-specific path. The clean-ancilla witness is the safety net if such an
  ancilla is not uncomputed. (An alternative — uncontrolled prep inside `when`
  — would fork the choke point; rejected. The acceptance gate §7.1b does not
  prep inside `when`, so this choice is not on the critical path, but it must
  be pinned; a proposer disagreement here is worth the implementer's attention.)
- **Guardrail 3 (unbounded recursion) has no active detector in M5** — it is a
  documented user-bug boundary ("bounded unrolling only"), grounded in BP
  non-monotonicity. No PRD requirement to detect it mechanically at M5.
- **`_apply_uncontrolled!` refactor of `apply!`** touches the M2/ad.jl choke
  path (rename current body, add wrapper). Behaviorally identical when the
  stack is empty; called out because it edits landed kernel-adjacent code and
  so is squarely in 3+1 scope.
