# M5 Proposal B — `when`: streaming coherent control + the deferred-teleport gate
### Lens: mechanics, edge cases, and failure topology first (bead Sturm.jl-o5yh)

---

## Executive summary (10 lines)

1. **Control lives in a `Vector{WireID}` on `ContextCore`** (per-context, flat), consulted at **exactly one new internal choke point `_act!`** — the control-aware sibling of `apply!` that the action family (and only the action family) calls.
2. **The partition is the whole design.** Preparation (`QBool`) and basis-changes keep calling raw `apply!` → naturally *uncontrolled* (the compute–uncompute lemma demands "alloc uncontrolled"); measurement casts get a separate `_assert_no_control` guard (guardrail 1); actions route through `_act!` (guardrail 2 + `ctrl^k` wrap).
3. **`_act!` builds `ctrl^k(v)` via the public `ctrl`** (flat count; `ctrl(ctrl(X))=Ctrl(2,X)`), prepends the k stack-control wires, runs the externality check, then calls the *unchanged* `apply!` — inheriting its aliasing/liveness/flush discipline and the whole `ad.jl` lowering (cx/cz/ccx/Barenco/AND-ladder).
4. **`when` opens a region and uses nested try/finally** so the control stack unwinds and the basis-change reverts on *any* thrown error mid-body; the region-exit trace of body-owned ancillas runs the **clean-ancilla assertion** while the control is still on the stack.
5. **Guardrail 1** (`_assert_no_control`): `Bool`/`Bool(dual)`/`ptrace!`/(M8)`cases` under nonzero stack = loud error *before any backaction* — the §8.1 regression closed by construction.
6. **Guardrail 2** (inside `_act!`): any op wire (control *or* target, already view-resolved to parent `WireID`s) that aliases a stack control = loud error; both sides resolving to parent wires is what "sees through views".
7. **Kickback is legal and automatic**: the body never names the control as a target, yet the control is input+output through the `ctrl` mechanism (`when(q){not!(dual(r))}` = one `cz`, control picks up phase). `when(q){not!(q)}` is guardrail-2, not kickback.
8. **`when(dual(q))`** = apply `F_G` (=H for QBool) to the control wire uncontrolled, push, stream, pop, apply `F_G†` — the inner `H·H` cancellations make streaming exact (fires on `|−⟩`).
9. **Clean-ancilla check**: masked-block-norm-0 in the *controls-all-1* subspace via the existing `_with_amps`/`density_matrix` sweep (O(2^cap)/O(4^cap), test scale), paid only when a body leaves an owned ancilla.
10. **Deferred teleport §7.1b runs one DM pass to `choi ≈ |Ω⟩⟨Ω|`** (no casts → fully DM-portable); the streaming≡materialized cross-check is the sole honest IOU to M8.

---

## 1. The do-block plumbing

### 1.1 Signatures

```
when(f::Function, q::QBool)          # when(q) do … end
when(f::Function, v::DualView)       # when(dual(q)) do … end
```

Julia's `do` lowers `when(q) do … end` to `when(<closure>, q)` — the closure is the **first** positional argument, so the signature order is `(f, q)`. The closure **captures by reference** every surrounding local it touches (the register handles, any Julia arrays for classical side effects). It runs **exactly once** under either strategy (streaming here; materialized in M8) — a stated §3.5 semantic footnote; classical side effects (printing, `push!`) are stream-time effects, not controlled effects.

`when` returns **`nothing`**. Rationale: the body's Julia return value ran once, unconditionally, at stream time — surfacing it invites the reader to treat it as a controlled result, which it is not. `when` is a control-flow *statement*; its denotation is the applied channel, not a value. (Deviation from `region(f)`, which returns `f()`; noted in §11.)

### 1.2 The try/finally topology (stack unwinds on throw)

```
function _when_core(ctx, control_wire::WireID, f)
    haskey(_core(ctx).wire_to_slot, control_wire) ||
        error("when: control wire $control_wire is not live (traced/consumed)")
    _push_control!(ctx, control_wire)
    try
        _enter_region!(ctx)
        try
            f()
        finally
            _exit_region!(ctx)          # clean-ancilla assert runs HERE (control still up)
        end
    finally
        _pop_control!(ctx, control_wire) # ALWAYS runs, even if _exit_region! threw
    end
    return nothing
end

when(f, q::QBool) = _when_core(current_context()===q.ctx ? q.ctx : _here(q), q.wire, f)

function when(f, v::DualView)
    p   = v.parent
    ctx = _here(p)
    F   = _dual_transform(p)                # H for QBool
    apply!(ctx, F, (p.wire,))              # basis-change control, UNCONTROLLED (fuses, M2)
    try
        _when_core(ctx, p.wire, f)
    finally
        apply!(ctx, adjoint(F), (p.wire,)) # undo basis-change, UNCONTROLLED
    end
    return nothing
end
```

**Why this exact nesting.**
- `_push_control!` is *outside* the inner try, `_pop_control!` in the *outer* finally → the stack is popped whether the body throws, `_exit_region!` throws (a clean-ancilla failure), or both. The context is never left with a stale control frame.
- `_exit_region!` is in the *inner* finally so it runs **while the control frame is still on the stack** — the clean-ancilla assertion needs `k` to know the firing subspace. Popping first would erase that.
- For `when(dual)`, the basis-change undo is in an *even outer* finally, so `F†` is re-applied even if `_pop_control!` somehow threw — the control wire is always returned to the computational basis.
- **Masking caveat (flagged honestly):** if the body throws AND `_exit_region!`'s clean-ancilla check also throws, Julia's `finally` surfaces the clean-ancilla error and masks the body's. Both are fail-loud, so the user still gets a crash, but the *first* error is hidden. Accepted for M5 (Julia ≤1.12 has no clean in-flight-exception introspection to demote the secondary check). Recorded in WORKLOG on landing.

### 1.3 Re-entrancy (nested `when`)

The stack is a `Vector{WireID}` on `ContextCore`. `when(a) do when(b) do … end end` pushes `[a.wire]`, then `[a.wire, b.wire]`; the inner body's `_act!` sees `k=2` and prepends both → `Ctrl(2, op)` (Toffoli-grade). Inner exit pops `b`, outer pops `a`. Because `Ctrl` is a **flat count** (`ctrl(ctrl(u))=Ctrl(2,u)`, kernel/ctrl.jl) and nested controls commute (Delorme Eq 14), the stack-as-vector *is* the faithful normal form — no nesting object, no ordering ambiguity.

**Per-context isolation.** The stack lives on `ContextCore`, so `when` on context A cannot leak control into ops targeting context B. If a body does `@context ctxB begin … end` and acts on B's handles, `_act!` reads `ctxB`'s (empty) stack via `_here(q).core` → those ops are uncontrolled — pathological but *correctly* localized (B's ops are genuinely not under A's `when`).

### 1.4 Nested regions / `@context` either way

- `region() do … end` **inside** a `when` body: opens a nested frame on the same ctx; its owned locals are traced at *its* exit, still under the control stack → clean-ancilla check applies to them too. Correct.
- `when` **inside** `region()`/`@context`: the region is just lexical scope; nothing special.
- The control wire cannot be freed by an inner `region()` exit — it was allocated in an *outer* scope, so no inner frame owns it (`allocate!` pushes to `region_stack[end]` at *its* allocation time). The only ways to retire it — `Bool(control)`, `ptrace!(control)` — are guardrail-1 loud errors. So **the control stays live for the whole body by construction**; `_act!`'s `q(ctx, control)` re-resolves the slot each op and would fail loud if it somehow died.

---

## 2. WHERE the stack is consulted — the minimal choke-point set

I traced every surface mutation path in the landed code (`surface/actions.jl`, `surface/casts.jl`, `types/qbool.jl`, `context/regions.jl`) to its `apply!`/measure/trace call. The paths partition into **three** disjoint control-behaviours, giving three (not one) touch-points — but each is a single function:

| Path | Landed call | Under `when` must be | Routes through |
|---|---|---|---|
| `not!(q)` | `apply!(X,(q,))` | **controlled** | `_act!` |
| `not!(dual(q))` | `apply!(_conj(H,X),(q,))` | **controlled** | `_act!` |
| `a ⊻= b` | `apply!(ctrl(X),(b,a))` | **controlled** | `_act!` |
| `q ⊻= true` | `apply!(X,(q,))` | **controlled** | `_act!` |
| `c = false ⊻ b` (entangle step) | `apply!(ctrl(X),(r,f))` | **controlled** | `_act!` |
| `c = false ⊻ b` (fresh prep step) | `apply!(X,(f,))` for the `b==true` flip | **uncontrolled** (prep) | raw `apply!` |
| `q̂ ⊻= r` | `apply!(ctrl(Z),(r,q̂.parent))` | **controlled** | `_act!` |
| `QBool(p,φ)` / `QBool(b)` | `apply!(_prep_u2,(w,))` | **uncontrolled** (clean alloc) | raw `apply!` (unchanged) |
| `Bool(q)` | `_measure_wire!` | **banned** | `_assert_no_control` |
| `Bool(dual(q))` | `apply!(H,(q,))` then `Bool(q)` | **banned** | `_assert_no_control` (at top, before the H) |
| `ptrace!(w)` | `_trace_and_free!` | **banned** (explicit) | `_assert_no_control` |
| region-exit trace of a body ancilla | `_trace_and_free!` | **allowed + asserted** | clean-ancilla in `_trace_and_free!` |

**Why not make `apply!` itself control-aware (the tempting one-choke-point answer)?** Because preparation and basis-changes call `apply!` and must stay uncontrolled — controlling a fresh-ancilla prep breaks the compute–uncompute lemma (§3.5: "alloc (uncontrolled) → ctrl(U) → dealloc (uncontrolled)"). The control/no-control split is *above* `apply!`, at the action-family boundary. Hence `_act!` is the correct level and `apply!` stays byte-for-byte the M2 function.

### 2.1 `_act!` — the control application choke point

```
function _act!(ctx::AbstractContext, v::ProcessValue, wires::NTuple{N,WireID}) where {N}
    core = _core(ctx)
    isempty(core.control_stack) && return apply!(ctx, v, wires)   # fast path: no control
    _guard_externality(ctx, wires)                                # guardrail 2 (clear message)
    cs = core.control_stack
    cv = v
    for _ in 1:length(cs)                                         # ctrl^k via the PUBLIC ctrl
        cv = ctrl(cv)                                             # flat: Ctrl(k, base)
    end
    return apply!(ctx, cv, (cs..., wires...))                    # stack controls are leading wires
end
```

- `ctrl(cv)` is the *public* combinator; the choke-point lint forbids `_ctrl(`/`Ctrl(` outside `kernel/ctrl.jl`, and `_act!` uses neither — clean.
- `(cs..., wires...)` matches `apply!`'s "position 1 = MSB / leading wire" and `Ctrl`'s "k controls are the leading wires" (ad.jl `_emit!(::Ctrl)` slices `qs[1:k]` as controls). Ordering is exact.
- The op's own control (e.g. `ctrl(X)` from `a ⊻= b`) is *inside* `wires`; controlling it k more times via `ctrl^k` gives `Ctrl(k+1, X)` on `(cs…, b, a)` — Toffoli-grade, correct.

### 2.2 `_guard_externality` — guardrail 2

```
function _guard_externality(ctx, wires)
    cs = _core(ctx).control_stack
    for w in wires, c in cs
        w === c && error("when: the body operates on the control register $w " *
            "(guardrail 2, §3.5 / Bădescu–Panangaden Condition I) — a `when` body " *
            "must not read or write its guard, even as an op-control or through a view")
    end
end
```

`wires` and `cs` are already parent `WireID`s (the action methods resolve `dual(·)` to `.parent` before calling `_act!`; the stack stored `_parent_wire(control)` at `when` entry). So the check "sees through views" on **both** sides without any view logic here — that is the §3.5 example `when(q) do not!(dual(q)) end` (target-side view) and `when(dual(q)) do not!(q) end` (control-side view) both erroring. `apply!`'s `_check_wire_aliasing` remains a backstop with its generic message.

---

## 3. The control wire's liveness / aliasing — the precise legal/illegal map

- **`when(q) do not!(q) end`** — body *acts on* control ⇒ guardrail-2 error: "body operates on control register q". (Not aliasing-cryptic; `_guard_externality` fires before `apply!`.)
- **`when(q) do a ⊻= q end`** — body reads q *as its op-control* ⇒ guardrail-2 error (q is in `wires`). Per Bădescu Condition I, the guard must be *inaccessible*, including as a control — this is **not** legal kickback.
- **`when(q) do q ⊻= b end`** — body targets q ⇒ guardrail-2 error.
- **`when(q) do not!(dual(r)) end`, r≠q** — LEGAL kickback: body targets r (as Z); q gates it as a control; q picks up a relative phase (`cz` backaction). The control is input+output **through the `ctrl` mechanism**, never as a body target. One `cz`.
- **`when(s) do a ⊻= r end`, all distinct** — LEGAL: `Ctrl(2,X)` on `(s, r, a)` = Toffoli; s and r are both controls, a the target.
- **`Bool(q)` where q IS the control** — guardrail **1** fires first (`_assert_no_control` at the top of `Bool`), message names it a *measurement under control*; it never reaches guardrail-2. So the two illegal families get *distinct* messages: **measurement-of-anything under control → guardrail 1; action-on-the-control → guardrail 2.** (No need to special-case "and it's the control" in the guardrail-1 text.)
- **Control freed by a region exiting inside the body** — impossible (§1.4): the control is outer-scope-owned; inner frames don't own it; `ptrace!`/`Bool` are banned.

---

## 4. Superposed/entangled control correctness through the Orkan lowering

Traced each op kind through `ad.jl`'s existing `_apply_controlled!` (no ad.jl edits needed):

| Body op | `_act!` builds | `apply!`→`_emit!(::Ctrl)`→`_apply_controlled!` | Orkan |
|---|---|---|---|
| `not!(r)` (X) under `when(q)` | `Ctrl(1,X)` on (q,r) | k=1, `u≈X` fast path | 1 `cx` |
| `not!(dual(r))` (Z) under `when(q)` | `Ctrl(1,Z)` on (q,r) | k=1, `u≈Z` fast path | 1 `cz` ✔ view-conjugation composes with control |
| `a ⊻= b` (ctrl X) under `when(q)` | `Ctrl(2,X)` on (q,b,a) | k=2, `inner≈X` | 1 `ccx` |
| `q̂ ⊻= r` (ctrl Z) under `when(s)` | `Ctrl(2,Z)` on (s,r,q̂.parent) | k=2 non-X: Barenco 6.1, V=√Z=S | CCZ, phase-exact |
| generic 1q `U2` under depth-3 `when` | `Ctrl(3,U2)` | k≥3: clean-\|0⟩ AND-ladder (Cor 7.12) + `_apply_controlled_u2!` off the AND wire | ccx-ladder + ABC + `p(control,φ)` |
| `oracle` `Perm` under `when(q)` (M7) | `ctrl(::Perm)` absorbs → `Perm` with prepended controls (perm.jl), OR `Ctrl{Perm}` — see note | `_apply_controlled!(::Perm)` replays each MCX with outer controls prepended | mcx-ladder |

**Confirmations:**
- `when(q){not!(dual(r))}` = `ctrl(Z on r)` = **one CZ** ✔ (the task's litmus). The view lowered Z *before* `_act!` sees it; `_act!` just controls the Z; ad.jl's `u≈Z→cz` fires. View-conjugation and control compose *for free* because they act at different layers (view→process value, then `ctrl`→controlled lowering).
- **Superposed control** is handled *by construction*: the controlled lowerings are genuine unitaries on the joint space (`cx`, Barenco, AND-ladder are all exact unitaries), so a control in `α|0⟩+β|1⟩` produces the correct entangled branch. Nothing special is needed — this is why streaming is licensed by the homomorphism law, not an approximation.
- **`ctrl(::Perm)` note (M7 depth, flagged):** `ctrl(::Perm)` returns a `Perm` (perm.jl closure) by *shifting local controls +1 and prepending wire 0*. Under `_act!`'s `ctrl^k` loop this stacks k prepended controls, and the wire tuple `(cs…, perm_wires…)` must line up with the shift convention. For M5 the Perm path is exercised only if a body applies a Perm; the *oracle* customer is M7 (with the MBU-exclusion rule). **Recommend a targeted `when(q){b ⊻= somePerm}` unit test land with M7**, not M5, and M5's Perm coverage be the trivial `ctrl(::Perm)` closure round-trip already in `test_kernel_perm.jl`. (Flagged so M7 doesn't assume M5 proved it.)

---

## 5. Fusion buffer policy under control — recommendation with numbers

**Recommendation: do nothing special. Rely on the existing per-op flush in `apply!`.** No flush-at-entry, no disable-inside, no Ctrl-aware buffer.

Why it is already correct:
- Every controlled op is ≥2 wires (entangling); `apply!` flushes each touched wire's fusion *before* emitting (`for w in wires; _flush_wire!`). So a pending 1q buffer on a control or target is realized in the right order, then the controlled op emits. No 1q op can linger in the buffer "underneath" a controlled op.
- Under control, 1q surface ops (`not!(q)`) become 2q (`cx`) → they flush-and-emit immediately; fusion is effectively (and correctly) *disabled* for controlled ops, since two controlled ops cannot fuse as a 1q `U2`.
- The one uncontrolled buffered op inside a `when(dual)` is the basis-change `H` on the control: it fuses at entry (0 ccalls), is flushed by the first controlled op's `apply!` (which touches the control), lands *before* the controlled ops — exactly `H·[ctrl ops]·H†`.

**ccall counts, typical bodies (Eager):**
- `when(b){not!(c)}` (teleport X-correction): 1 `cx`. **1 ccall.**
- `when(dual(ψ)){not!(dual(c))}` (teleport Z-correction): entry `H` buffers on ψ (0); body `ctrl(Z)` flushes ψ's `H` (~2–3 `rz/ry`) + emits `cz` (1); exit `H` buffers (flushed later ~2–3). **≈ 5–7 ccalls.** (The `cz` fast path avoids the ABC skeleton entirely.)
- Depth-2 `when(a){when(b){not!(c)}}`: `Ctrl(2,X)` = 1 `ccx`. **1 ccall.**

A Ctrl-aware buffer would let two adjacent same-control ops fuse under the control, but the win is marginal and it would *duplicate* the `ctrl`/composition logic the kernel already owns — rejected on the "no duplicated primitives" principle (CLAUDE.md #13). The op-level fusion the kernel *does* want (fusing the streamed body into one `UnitaryDAG` before `ctrl`) is the **materialize** strategy — that is M8, not a buffer hack.

---

## 6. Clean-ancilla check mechanics

**When it runs.** Only inside `_trace_and_free!(ctx, w)` when `!isempty(core.control_stack)`. This is reached by the `when`-region's `_exit_region!` for each body-owned, unconsumed, unreturned wire (a body ancilla), and by an inner `region()`'s exit inside the body. **It never runs when the body allocates nothing** (the teleport case: the `when` bodies allocate no locals — `not!(c)`/`not!(dual(c))` target outer-scope wires — so `_exit_region!` traces an empty frame, zero cost). Pay only when you use an ancilla.

**What it asserts.** In the subspace where **all k control-stack wires = 1** (the firing block, i.e. the frame the controlled ops actually ran in), the ancilla `w` must be `|0⟩`: the mass with `slot(w)=1 ∧ ⋀ slot(cᵢ)=1` is 0. (YVC Def 4.7 synchronization / §3.5 "|1⟩-block norm exactly 0".) A dirty ancilla in the firing block, entangled with a superposed control, would decohere the control at trace time → a **silent wrong channel** — exactly the class this catches, fail-loud, *before* the trace's backaction.

**Eager implementation** (reuse `_with_amps`, the `_marginal_p1` pattern):

```
function _clean_ancilla_assert!(ctx::EagerContext, w::WireID)
    core = _core(ctx)
    _flush_all!(ctx)
    amask = 1 << core.wire_to_slot[w]
    cmask = 0
    for c in core.control_stack; cmask |= (1 << core.wire_to_slot[c]); end
    leak = _with_amps(core.state) do amps
        s = 0.0
        @inbounds for i in eachindex(amps)
            b = i - 1
            ((b & cmask) == cmask) && ((b & amask) != 0) && (s += abs2(amps[i]))
        end
        return s
    end
    leak < CLEAN_EPS || error("when: ancilla $w is not returned to |0⟩ in the " *
        "control-firing subspace (|1⟩-block leakage $(leak) > $(CLEAN_EPS); §3.9 / " *
        "YVC synchronization). Tracing it would decohere the control — uncompute the " *
        "ancilla inside the `when` body before it leaves scope.")
end
```

Cost O(2^cap), pure Julia, no new FFI — mirrors `_ptrace_keep`'s test-scale sweep. `CLEAN_EPS` ≈ `CHART_EPS^2` (≈1e-24) or a pinned `1e-18` (float-law tolerance, PRD §4.1). **DM implementation:** identical mask logic over `density_matrix(ctx)`'s diagonal — sum `real(ρ[i,i])` for `i` in the `cmask ∧ amask` set; assert `< CLEAN_EPS`. O(4^cap).

**Failure timing.** Fires in `_trace_and_free!` *before* `trace_wire!` — no state mutation on the failure path, so the error is clean (no half-traced ancilla).

**Superposed / entangled control coverage** (named tests): (a) product control `|+⟩`, clean ancilla → passes, correct channel; (b) `|+⟩` control, deliberately un-uncomputed ancilla → loud error; (c) control pre-entangled with a reference (the Choi Bell probe) → the check is on the *joint* firing block, so an unclean ancilla still fails and a clean one still passes (the entanglement with the reference is orthogonal to the control-ancilla synchronization).

---

## 7. Deferred teleport §7.1b — verbatim + line-by-line mapping

**Verbatim (Sturm-PRD-v2.md lines 1104–1116):**

```julia
function teleport_deferred(ψ::QBool)
    b = QBool(0.5)                # Bell pair on (b, c)  [comment: b prep]
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

| Line | Surface | Lowering | Status |
|---|---|---|---|
| `b = QBool(0.5)` | cq prep → `\|+⟩` | `apply!(_prep_u2(0.5,0),(b,))` | **LANDED** (qbool.jl) |
| `c = false ⊻ b` | Bell pair on (b,c) | fresh `\|0⟩`; `apply!(ctrl(X),(b,c))` → Φ⁺ | **LANDED** (actions.jl `xor(::Bool,::QBool)`) |
| `b ⊻= ψ` | CNOT target b, control ψ | `apply!(ctrl(X),(ψ,b))` | **LANDED** (actions.jl `xor(::QBool,::QBool)`) |
| `when(b) do not!(c) end` | ctrl(X) control b target c | `_act!(X,(c,))` w/ stack=[b] → `Ctrl(1,X)` on (b,c) → `cx` | **NEW M5** (`when(::QBool)` + `_act!`) |
| `when(dual(ψ)) do not!(dual(c)) end` | `\|−⟩⟨−\|_ψ ⊗ Z_c` | `apply!(H,(ψ,))`; `_act!(Z,(c,))` stack=[ψ] → `cz`; `apply!(H,(ψ,))` | **NEW M5** (`when(::DualView)` + `_act!`; not!(dual) LANDED) |
| `return c` | ψ,b unreturned → traced | caller's region exit traces ψ,b (deferred measurement) | **LANDED** (regions.jl §3.9) |

**Denotation check.** `when(dual(ψ)){not!(dual(c))}` = `H_ψ · CZ(ψ,c) · H_ψ` = `|+⟩⟨+|_ψ⊗I + |−⟩⟨−|_ψ⊗Z_c` = the §7.1b comment "|−⟩⟨−| ⊗ Z, exactly" ✔. Composed with `when(b){not!(c)}` (X-correction) and the Bell/CNOT front end, the whole map is the **identity channel** ψ↦c.

**One-run DM Choi.** `choi(teleport_deferred, 1)` (harness `_choi1`, DM): preps Bell (sys,ref), `qin=ψ=sys`, `c=f(qin)`, reads `ρ`, `_ptrace_keep(ρ,(c.wire,ref),cap)`. Expected `J ≈ bell = |Ω⟩⟨Ω|` (identity). Runs **fully on DM** because `teleport_deferred` has **no casts, no `Bool`** — only unitary ops + region traces (DM traces exactly, deterministic, one pass). Assertions: `J ≈ bell`; `tr(J)≈1`; `!(J ≈ Diagonal(diag(J)))` (off-diagonals present → Z-sensitive, catches the wm28 class); `!(J ≈ choi(pinch_channel,1))`.

**GAPS — flagged LOUDLY:**
- **[GAP-1] `teleport_deferred` opens no region of its own.** As written it is a plain `function`; `b` (local) and `ψ` (unreturned arg) are owned by the **caller's** region and traced at *its* exit — not at `teleport_deferred`'s return. This is the §3.9 "helpers that don't open a region inherit the enclosing one — provably harmless (trace timing is denotationally invisible)" rule. For the Choi harness it is fine: `_choi1` reads `ρ` *before* its `density`-do region exits, and `_ptrace_keep` over `(c,ref)` *is* the discard of ψ,b. **But** direct callers must be inside some region (`eager`/`density`/`region`/`@context`) or ψ,b never trace. **Not a bug — but the test must wrap the call in the harness's region (it does) and a direct-use test must supply one.**
- **[GAP-2] capacity.** `choi(f,1)` default `cap = 2·1+2 = 4`. `teleport_deferred` live wires = ψ(sys), ref, b, c = **exactly 4**; single-control `when`s need no scratch (k=1). Fits, but *tight* — any added ancilla or a k≥3 `when` in a variant needs `cap` bumped. Note in the test.
- **[GAP-3] streaming≡materialized cross-check is deferred to M8.** §3.5's required law test ("streaming and materialized execution denote the same channel, Choi-compared") can only run its **streaming** half in M5 (no `UnitaryDAG`/Tracing yet). M5 lands the streaming Choi (`≈ identity`); the equivalence assertion is an explicit **IOU to M8** (plan §M5 acknowledges this; mark the materialized side `@test_broken`/skipped with a pointer bead).
- **[GAP-4] `false ⊻ b` under a future controlled variant.** In `teleport_deferred` the Bell pair is built *outside* any `when`, so `xor(::Bool,::QBool)`'s fresh-prep-then-entangle split (§2, row 6) is never exercised under control here. If a variant nests it inside `when`, the fresh-prep (`X(f)`) must stay uncontrolled and only the entangle (`ctrl(X)(r,f)`) route through `_act!` — the edit in §9.3 handles it, but it is **untested by §7.1b**; add a dedicated test if a customer appears.

---

## 8. Named tests (`test/test_m5_when.jl`, included under an M5 `@testset` in runtests.jl)

1. **`guardrail 1 — cast/ptrace/cases under control is a loud error (§8.1 regression)`**: `when(q){ Bool(q) }`, `when(q){ Bool(dual(r)) }`, `when(q){ ptrace!(r) }`, `when(q){ Bool(r) }` each `@test_throws`; assert the **statevector is unchanged** across the throw (fail-before-backaction) — the headline v0.1 §8.1 fix.
2. **`guardrail 2 — body may not access the control (external + through views)`**: `when(q){not!(q)}`, `when(dual(q)){not!(q)}`, `when(q){not!(dual(q))}`, `when(q){a ⊻= q}`, `when(q){q ⊻= true}` each `@test_throws` with the guardrail-2 message; contrast a legal body passes.
3. **`streaming ctrl(X): when(q){not!(r)} = CX`**: `choi(_->…, 2)` (2-in/2-out wrapper returning (q,r)) `≈ analytic_choi2(CX)`.
4. **`kickback / CZ symmetry: when(q){not!(dual(r))} = CZ, control is input+output`**: `choi2 ≈ analytic_choi2(CZ)`; and the symmetric spelling `when(r){not!(dual(q))}` gives the *same* Choi (§7.3 theorem); verify the control's reduced state changes (phase kickback visible).
5. **`nested when = Toffoli-grade`**: `when(a){when(b){not!(c)}}` vs a dense `ccx` reference on all 8 computational basis inputs (statevector truth table, since the Choi harness is nin≤2); assert equal to `denoted_matrix(ctrl(ctrl(X)))`.
6. **`anti-control sandwich`**: `not!(q); when(q){not!(r)}; not!(q)` fires on the original `|0⟩_q` branch (the §3.5 blessed idiom); Choi vs anti-controlled-X.
7. **`clean-ancilla soundness`**: (a) alloc-inside-`when` + matched uncompute → passes, correct channel; (b) un-uncomputed ancilla → guardrail loud error; (c) **superposed control** `|+⟩`; (d) **entangled control** (Bell probe) — (b) still errors, (a) still passes under (c)/(d).
8. **`when(dual(q)) = control in conjugate basis`**: `choi2` of `when(dual(q)){not!(r)}` ≈ `|−⟩⟨−|_q⊗X_r + |+⟩⟨+|_q⊗I` reference.
9. **`deferred teleport §7.1b — one DM run`**: `choi(teleport_deferred,1) ≈ bell`; `tr≈1`; off-diagonals present; `≠ choi(pinch_channel,1)` (Z-sensitive; wm28 gate).
10. **`control stack unwinds on thrown error mid-body`**: body throws a user error; assert `isempty(ctx.core.control_stack)` afterward and a subsequent `not!(r)` is **uncontrolled** (Choi = X, not ctrl-X); for `when(dual)`, assert the control returned to the computational basis.
11. **`streaming ≡ materialized (IOU→M8)`**: streaming Choi recorded; materialized side `@test_broken`/skipped with a bead pointer.

Statistical note: all channel statements are **Choi/diamond** (DM, deterministic one pass) — never marginals (the §7.1/wm28 discipline). No N≥1000 sampling needed for the law tests; sampling tests (if any Eager trajectory checks) use N≥1000 + tolerance.

---

## 9. The minimal-edit list (file, function, exact change)

**Core-type / kernel-adjacent changes (these are why 3+1 is invoked):**

1. **`src/context/abstract.jl` — `ContextCore`**: add field `control_stack::Vector{WireID}`; initialize `WireID[]` in the inner constructor. Add `_under_control(ctx) = !isempty(_core(ctx).control_stack)`, `_push_control!(ctx,w) = push!(_core(ctx).control_stack, w)`, `_pop_control!(ctx,w) = (@assert last(...)===w; pop!(...))` (assert LIFO integrity), `_assert_no_control(ctx, what) = _under_control(ctx) && error("… $what under nonzero control stack is unrepresentable (§3.5 guardrail 1 / §4.4)…")`.
2. **`src/context/abstract.jl` — `_trace_and_free!`**: insert, before `trace_wire!`, `_under_control(ctx) && _clean_ancilla_assert!(ctx, w)`. Add `_clean_ancilla_assert!(::EagerContext, w)` and `(::DensityMatrixContext, w)` (§6). Add `const CLEAN_EPS`.

**Surface routing (mechanical, ~8 call-site edits):**

3. **`src/surface/actions.jl`**: replace the `apply!` call with `_act!` in `not!(::QBool)`, `not!(::DualView)`, `xor(::QBool,::QBool)`, the `true`-flip in `xor(::QBool,::Bool)`, the **entangle step** of `xor(::Bool,::QBool)` (leave that method's *fresh-prep* `apply!(X,(f,))` as raw `apply!`), and `xor(::DualView,::QBool)`. Add `_assert_no_control(_here(p),"conjugate-basis measurement")` at the **top** of `Bool(::DualView)` (before the H basis-change).
4. **`src/surface/casts.jl` — `Bool(::QBool)`**: add `_assert_no_control(ctx, "measurement")` immediately after the context-identity check, before `_measure_wire!`.
5. **`src/context/regions.jl` — `ptrace!(ctx,w)`**: add `_assert_no_control(ctx, "explicit ptrace!")` at the top (guardrail 1 for explicit trace). The internal `_exit_region!`→`_trace_and_free!` path is untouched, so region-exit clean-ancilla trace still works.

**New file + wiring:**

6. **`src/surface/when.jl` (NEW)**: `_act!`, `_guard_externality`, `_when_core`, `when(f,::QBool)`, `when(f,::DualView)` (§1–§2).
7. **`src/Sturm.jl`**: `include("surface/when.jl")` after `surface/actions.jl`; add `when` to the surface `export` line.
8. **`test/test_m5_when.jl` (NEW)** + `include` under an M5 `@testset` in `test/runtests.jl` (after the M4 block).

**Deferred to M8 (noted, not an M5 edit):** `cases`/`@cases` call `_assert_no_control(ctx,"cases")` (guardrail 1); `ctrl(::UnitaryDAG)` + the materialize path (streaming≡materialized closure). **Deferred to M7:** the `when`-controlled `oracle`/`Perm` test + MBU-exclusion under a nonzero control stack (§3.4).

Total src edits: **2 core-type/context functions changed, ~8 surface call-sites rerouted, 1 new surface file.** Zero edits to `kernel/` and `orkan/ad.jl` — the entire controlled lowering is reached through the *unchanged* `apply!` + public `ctrl`.

---

## 10. Namespace

- `export when` (surface construct 5) — joins `@context, region, ptrace!, QBool, plus, minus, magic_T, dual, not!`.
- Keep **internal** (no `public`, no `export`): `_act!`, `_guard_externality`, `_when_core`, `_push_control!`, `_pop_control!`, `_under_control`, `_assert_no_control`, `_clean_ancilla_assert!`, `CLEAN_EPS`, the `control_stack` field. These are machinery, not layer API — consistent with CLAUDE.md conv 8 (surface `export`ed; kernel `public`; internals neither).
- No new `public` names: `when` is the only user-visible addition, and it is surface.

---

## 11. Deviations & open decisions (skepticism, CLAUDE.md #9)

- **D-B1: `when` returns `nothing`** (not `f()` like `region`). Rationale: the body value ran once at stream time; surfacing it invites misreading it as a controlled result. If the reviewer wants parity with `region`, the alternative is returning `f()` with a docstring warning — I recommend `nothing`.
- **D-B2: three touch-points, not one.** I deliberately reject a single control-aware `apply!` because prep/basis-change must stay uncontrolled. The three are each one function (`_act!`, `_assert_no_control`, clean-ancilla-in-`_trace_and_free!`) — minimal given the physics, not minimal by raw count.
- **D-B3: masking on double-throw** (§1.2) — clean-ancilla error can mask a body error during unwind. Accepted (both fail-loud); no clean Julia fix at 1.12. Recorded for WORKLOG.
- **D-B4: clean-ancilla is O(2^cap)/O(4^cap)** per body-owned ancilla trace under control. Fine at law-test scale; a production concern only if `when` bodies routinely allocate under deep control. A future Orkan `masked_block_norm` primitive would make it O(1)-ish — a bead, not M5.
- **D-B5: `false ⊻ b` fresh-prep/entangle split under control** (§7 GAP-4) — the entangle step controls, the prep does not. Correct per the compute–uncompute lemma but untested by §7.1b; recommend a dedicated test if a customer appears (else M5 leaves it as reasoned-but-unexercised).
- **D-B6: Perm-under-`when` depth** (§4 note) — I scope real coverage to M7 (oracle), M5 covers only the U2/Ctrl/view-conjugated paths that the surface action family produces today. Flagged so M7 doesn't inherit a false "already tested".
- **D-B7: `_pop_control!` asserts LIFO** (`@assert last === w`) — a cheap corruption tripwire; if it ever fires, a `try/finally` nesting bug exists. Kept as a fail-loud invariant, not a silent `pop!`.
