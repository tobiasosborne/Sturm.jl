# M4 Proposal B — Views, `dual`, the action family, teleportation
**Lens: Julia dispatch mechanics and misuse paths first.**
Proposer B, 3+1 round for bead `Sturm.jl-3nld`. Written against landed
M1–M3 (`src/kernel/`, `src/context/`, `src/types/qbool.jl`,
`src/surface/casts.jl`, `test/choi.jl`) and PRD-v2 §3.3/§3.4/§3.8,
D11/D12, and the §7.1 acceptance gate. No `src/`/`test/` writes here;
every parser/dispatch claim below was executed against Julia 1.x.

---

## 0. Executive summary (10 lines)

1. **Two wrapper types, Base's `adjtrans.jl` pattern.** `DualView{H}`
   (the character-group dual, `dual`) and a generic `View{V,H}` (kernel
   `view(V,q)`, library-only). `dual(v::DualView)=v.parent` unwraps by
   **nominal type at dispatch time** — never by applying F.
2. **Zero M1/M2/M3 kernel edits.** Every view op lowers to an *existing*
   `apply!(::ProcessValue, ::NTuple{N,WireID})` call on the parent's
   wire(s) with a conjugated process value. New code is two surface files.
3. **The conjugation is exact and reuses M1 `∘`:** an op `g` through the
   dual lowers to `adjoint(V) ∘ g ∘ V`; for `QBool`, V=H, so
   `H∘X∘H ≈ Z` (hits the native `cz`/`z` fast paths in `ad.jl`).
4. **`Base.xor` return-value discipline is the whole game.** `a ⊻= b`
   lowers to `a = a ⊻ b`; every action-family `xor` method **returns its
   mutated first handle** so the rebind is a no-op. Fresh-output
   `c = false ⊻ b` is a *plain* `=`, so it may (and must) return a fresh
   handle. Full signature table in §3.
5. **B1 (`dual(q) ⊻= r`) parses but is a `Meta.lower` error**
   (`invalid assignment location "dual(q)"`) — caught by the M0 PRD
   lower-lint, never reaching runtime. Verified. `q̂=dual(q); q̂⊻=r` works
   (q̂ is a plain variable; rebinds to the returned self).
6. **Aliasing `q̂ ⊻= q` errors NOW, at `apply!`.** Surface resolves views
   to parent `WireID`s before calling `apply!`; the landed
   `_check_wire_aliasing` (ad.jl:372) fires on the doubled `WireID` with a
   register-identity message. M5 inherits this via a `_parent_wire` hook.
7. **Fusion path is untouched:** `Bool(dual(q))` = `apply!(H,(w,))`
   (1q → `_fuse!`), then `Bool(q)` → `_flush_all!` emits H via ZYZ, then
   measure. `|+⟩ ↦ false` falls out of "apply H, measure Z" — the PRD's
   pinned X-labeling, for free.
8. **Misuse is honest `MethodError` where the PRD wants a wall** (ring
   ops on views, P9 promotion) and `error()`+identity where it is a
   liveness/aliasing guard. No custom exception type (S13).
9. **LOUD FLAG — §7.1 teleport:** M4 can *write* it (all seven line-ops
   are M4), but its **exact one-run DM Choi cannot run in M4**: scalar
   `Bool` throws on DM (casts.jl:112), and the branchless form needs
   `when` (M5, §7.1b) or DM-cases-with-feedforward (M8). M4's teleport ✓
   is an **Eager statistical** state-probe on |i⟩/|+⟩. Details §8.
10. **Namespace:** `export dual, not!`; `Base.xor`/`Base.Bool` extensions
    need no export; `public view, View, DualView`.

---

## 1. The view type design (dispatch mechanics)

### 1.1 Two nominal types, mirroring `Base.adjtrans.jl`

```
# src/kernel/views.jl  (new; kernel machinery, `public`)

struct DualView{H}          # the Pontryagin/character-group dual view
    parent::H               # BORROWED handle (QBool now; QInt/x[i] at M6)
end

struct View{V<:ProcessValue,H}   # generic parametric view, library-only
    transform::V
    parent::H
end
```

**Why two types, not one.** `dual` must *unwrap* by dispatch
(`dual(dual(q)) === q`), while a generic `view(V, view(W, q))` must
*compose*. Base solves the identical problem with two nominal types:
`Adjoint`/`Transpose` each carry an unwrap method (`adjoint(A::Adjoint)=A.parent`,
`adjtrans.jl:280`), and generic wrappers compose. Collapsing both into one
type would force `dual` to inspect a stored transform at runtime and would
lose the type-level `dual(dual(q)) === q` guarantee. PRD-v2 §3.3 names this
exact pattern ("`dual(v::DualView) = v.parent`, Base's exact `adjtrans.jl`
pattern") and the JuliaLang#20978 cautionary tale (defining an op as the
*evaluation* of a composition rather than structurally).

### 1.2 Parametric on the parent handle type `H`

`DualView{H}` is parametric on the **parent handle type**, not on a
process value. That is load-bearing three ways:

- **`dual(dual(q)) === q` by object identity.** `dual(q)` builds
  `DualView(q)`; `dual(DualView(q))` returns the field `.parent`, i.e. the
  *same* `q` object → `===` holds. `dual(q) === dual(q)` is `false` (two
  allocations) — PRD-v2 §3.3, both required.
- **F_G is supplied by the parent *type*, not stored** (P7). The dual's
  basis change is a property of the register's group, so:
  ```
  _char_dual(::Type{QBool}) = H          # ℤ₂ self-dual, basis change H
  # M6: _char_dual(::Type{QInt{W}}) = QFT_W ;  D6 gates QMod
  ```
  A `DualView{QBool}` needs no runtime transform field — dispatch on
  `typeof(parent)` recovers it. `View{V,H}` *does* store `V` (arbitrary,
  library-chosen, e.g. QSVT's Y-axis SELECT).
- **`isbits`:** `DualView{QBool}` is **not** isbits, because `QBool` is not
  isbits (its `ctx::AbstractContext` field is abstract — deliberate, see
  `qbool.jl` header). This is acceptable and consistent: views, like
  handles, are never in the hot loop. The hot loop is `apply!` over raw
  `WireID`s + the per-wire `U2` fusion buffer (M2), which the view never
  enters — it *produces* `apply!` calls, it is not an `apply!` argument.

### 1.3 `dual` / `view` constructors and the unwrap

```
dual(q::QBool) = DualView(q)
dual(v::DualView) = v.parent            # DISPATCH-TIME unwrap (involution)

view(V::ProcessValue, q) = View(V, q)                 # generic
view(V::ProcessValue, w::View) = View(V ∘ w.transform, w.parent)   # compose
```

`dual` construction is **total** — it never throws, even on a consumed or
dead parent (PRD-v2 D2: "construction stays total; rejection lives at the
point of use", the LinearMaps `adjoint(::FunctionMap)` lesson). Rejection
happens when you *operate* on the view (§4).

**`view` naming (namespace nicety, flagged for the reviewer).** `Base.view`
exists (array views). I propose a **fresh `Sturm.view` generic function**
(not a `Base.view` method), marked `public`, so `using Sturm` never
shadows `Base.view` and library authors write `Sturm.view(V, q)`
explicitly. Extending `Base.view` would not be piracy (we own
`ProcessValue`) but would blur two unrelated meanings on one name. Final
call is the implementer's; it does not touch core semantics.

---

## 2. Lowering: ops through a view (ZERO kernel change)

The invariant that buys "zero M1/M2/M3 edits": **a view never becomes an
`apply!` argument.** The surface method for each view op computes a
concrete `ProcessValue` and a tuple of *parent* `WireID`s, then calls the
already-landed `apply!`. The kernel sees only `U2`/`Ctrl`/`Perm` on
`WireID`s, exactly as today.

### 2.1 Unitary op through the dual (conjugation)

PRD-v2 §3.3: "Unitaries lower as Ad_{V†} ∘ op ∘ Ad_V." The applied process
value is therefore `adjoint(V) ∘ g ∘ V`:

```
function _apply_dual_unitary!(v::DualView, g::U2)
    p = v.parent
    V = _char_dual(typeof(p))                 # H for QBool
    apply!(p.ctx, adjoint(V) ∘ g ∘ V, (p.wire,))   # M1 ∘, M2 apply!
    return v                                   # bound-view: return self
end
```

For `QBool`: `adjoint(H) ∘ X ∘ H = H∘X∘H`. Using M1's fuzz-certified
Hamilton `∘`, this `≈ Z` (the exact kernel constant, within `U2_ATOL`), so
in `ad.jl:_apply_controlled_u2!`/`_emit_u2!` it takes the **native path**
(`u ≈ Z → _emit_cz!` when controlled; a single fused `U2` when not). The
direction (`adjoint(V) ∘ · ∘ V` vs its reverse) is **immaterial for QBool**
because H is self-adjoint; it is *pinned* for non-self-adjoint V at M6 by
the Pontryagin unit test (`x̂ += a; Int(dual(x)) == a`). Stated here so the
implementer writes the general form now and M6 only supplies `_char_dual`.

### 2.2 Measurement through the dual (conjugated instrument)

```
function Base.Bool(v::DualView)             # in src/surface/dual.jl
    p = v.parent
    V = _char_dual(typeof(p))               # H
    apply!(p.ctx, V, (p.wire,))             # basis change into computational
    return Bool(p)                          # M3 consuming cast; consumes p
end
```

`Bool(dual(q))` = "rotate the X-basis into the Z-basis (apply H), then
measure Z, consuming." Two facts fall out **for free**:

- **`|+⟩ ↦ false` (the PRD's forced X-labeling).** `H|+⟩ = |0⟩ →` outcome
  0 → `false`. This is precisely the F†P_kF labeling PRD-v2 §7.1 pins; no
  extra code, and reversing it would reproduce wm28 from the convention
  side. This is a **required test** (§7 below).
- **Post-rotation is correctly dropped.** The full conjugated instrument
  is `V† ∘ M_Z ∘ V`; the trailing `V†` acts on an already-collapsed,
  about-to-be-retired wire, so a consuming measurement legitimately omits
  it. `Bool(p)` retires the wire (measure-and-flip → |0⟩ recycle), so no
  `V†` is observable.

**Fusion trace (M2/M3 call path, named).** `apply!(ctx, H, (p.wire,))`
matches the 1q fast path `apply!(::AbstractContext,::U2,::NTuple{1,WireID})`
(ad.jl:335) → `_fuse!` (abstract.jl:189): H accumulates in `core.fusion`.
Then `Bool(p)` → `_measure_wire!` (casts.jl:90) → `_flush_all!`
(abstract.jl:215) → `_flush_wire!` → `_emit_u2!` (ZYZ, ad.jl:88) → Orkan →
`_marginal_p1` → `_draw` → `_collapse!`. **No seam needed** — the flush
barrier at measurement already exists and does exactly the right thing.

---

## 3. The action family — `Base.xor` method table and returns

`a ⊻= b` **lowers to `a = xor(a, b)`** (verified). For the rebind to be a
physical in-place op and not a Julia rebinding-of-a-copy, **`xor` must
return the mutated first handle**. This is the registered convention
(PRD-v2 §3.4, alongside `not!`), adopted knowing julialang#249/#3217.

### 3.1 Exact signature × return table

| Surface | Method (in `src/surface/actions.jl`) | Lowering | Returns | In-place? |
|---|---|---|---|---|
| `a ⊻= b`, both `QBool` | `Base.xor(a::QBool, b::QBool)` | `apply!(ctx, ctrl(X), (b.wire, a.wire))` — CNOT ctrl `b`, target `a` | **`a`** (same struct) | yes |
| `q ⊻= true` / `false` | `Base.xor(q::QBool, b::Bool)` | `b && apply!(ctx, X, (q.wire,))` — **exact X** | **`q`** | yes |
| `c = false ⊻ b` (Bell idiom) | `Base.xor(a::Bool, b::QBool)` | alloc fresh `r`=|0⟩; `a && apply!(X,(r,))`; `apply!(ctrl(X),(b.wire,r))` | **fresh `QBool(ctx,r)`** | no (value world) |
| `q̂ ⊻= r`, `q̂::DualView`, `r::QBool` | `Base.xor(v::DualView, r::QBool)` | `apply!(ctx, ctrl(adjoint(V)∘X∘V), (r.wire, v.parent.wire))` = CZ | **`v`** (same DualView) | yes |
| `not!(q::QBool)` | `not!(q::QBool)` | `apply!(ctx, X, (q.wire,))` | **`q`** | yes |
| `not!(dual(q))` | `not!(v::DualView)` | `_apply_dual_unitary!(v, X)` → Z | **`v`** | yes |

`Base.xor(::QBool, ::Perm)` and the register/`⊻=`-oracle forms are **M7**,
not M4 — noted so the method table is not "completed" prematurely.

### 3.2 The two mixed directions are genuinely different (both wanted)

PRD-v2 §3.4 demands the asymmetry, and dispatch delivers it cleanly:

- `xor(q::QBool, b::Bool)` — RHS classical, **flip `q` in place**
  (returns `q`). Appears as `q ⊻= true`.
- `xor(a::Bool, b::QBool)` — LHS classical, **promote to a fresh |0⟩
  register and entangle** (returns fresh). Appears as `c = false ⊻ b`.

Verified: `false ⊻ x` with a non-`Bool` `x` dispatches to the
`xor(::Bool, ::·)` method and returns the method's value (not a `Bool`).
So `c = false ⊻ b` gives a fresh `QBool`, exactly the teleport Bell-pair
line. `xor(::Bool,::Bool)` stays Base's classical xor — we never touch it.

**Normative fix carried in (defect 8.3).** `xor(q::QBool, ::Bool)` lowers
to the **exact kernel `X`** (constants.jl), never `Ry(π)` (=−iY, the v0.1
`qbool.jl:154` latent-phase bug). Required test: the applied value's Choi
= J(Ad_X). Because `X` here is the same exact element used by `QBool(true)`
(qbool.jl:94), this is consistent by construction.

### 3.3 Why the rebind is a no-op — spelled out

`q ⊻= r` → `q = xor(q, r)`. `xor(q,r)` mutates Orkan state via `apply!`
and returns the *same* `QBool` object `q`. The assignment `q = q` rebinds
the local to the identical object: a true no-op. `QBool` being `immutable`
is fine — we return the same instance, we don't mutate the struct. For
`q̂ ⊻= r` → `q̂ = xor(q̂, r)`, `xor` returns the same `DualView` `v`; `q̂`
rebinds to it. The bound-view idiom (D11) is exactly this rebind-to-self.

### 3.4 B1 vs the bound-view idiom — verified parser behavior

- **B1 `dual(q) ⊻= r` — INVALID, caught at lowering.** It *parses*
  (`Meta.parse` succeeds), but `Meta.lower(Main, :(dual(q) ⊻= r))` returns
  `Expr(:error, "invalid assignment location \"dual(q)\"")`. So it dies in
  the M0 PRD **lower**-lint (which does Meta.parse *and* Meta.lower —
  "lowering is essential, B1 was a lowering error", plan §1.4), never at
  runtime. `dual`'s docstring must name this trap **and** its sibling
  `dual(x) = y` (a short-form *method definition* shadowing `dual` for the
  body — a silent trap, not an error).
- **`q̂ = dual(q); q̂ ⊻= r` — WORKS.** `q̂` is a plain local; `q̂ ⊻= r` →
  `q̂ = xor(q̂, r)` → `xor(::DualView,::QBool)` applies CZ, returns `q̂`,
  rebinds to self. Verified end-to-end on a stub.

A required **negative doctest** (extend `test_prd_examples.jl`): assert
`Meta.lower(@__MODULE__, :(dual(q) ⊻= r))` is an `:error` expr with
"invalid assignment location". This pins B1 as a language fact, so no
future edit "helpfully" makes it parse.

---

## 4. Misuse paths, each with S13 classification

| Misuse | Mechanism | Class (S13) |
|---|---|---|
| `dual(q) * x`, `dual(q) + a`, `dual(q) & r` | no `*`/`+`/`^`/`&`/`promote_rule` on `DualView`; not `<:Number` | **`MethodError`** — the honest P9 wall (PRD §3.3: "generic numeric code handed one MethodErrors honestly", same as `g(x::Int)`). Do NOT define-to-throw here; a bare `MethodError` is *correct*. |
| P9 promotion of a view | `DualView`/`View` are not `<:Number`, no `promote_rule` | `MethodError` (views don't ride P9 — §3.3) |
| `Bool(dual(q))` after `q` consumed | lowering calls `apply!(H,(w,))`; `w` was deleted from `wire_to_slot` at consume | **`error()`** "wire … not live" (apply! liveness, ad.jl:336/354) |
| `not!(dual(q))` after consume | same liveness path | `error()` + identity |
| `dual` of a consumed/dead handle | construction is **total** (no check); fails at first *use* as above | (deferred to use-site) |
| view escaping its region | region exit traces the owned **parent** wire; a returned view then references a dead wire → errors at next use | `error()` at use. Full at-*return* detection (ownership transfer) is D2/later — **flagged as a known M4 gap**, at-use safety holds |
| `dual(dual(q)) === q` | dispatch unwrap `dual(::DualView)=parent` | required test (`===` true); `dual(q)===dual(q)` false |
| cross-context view use | `Bool(::DualView)` → `Bool(parent)` → `q.ctx === current_context()` check (casts.jl:67) | **`ArgumentError`** (cross-context handle) |
| **aliasing `q̂ ⊻= q`** (view of the same wire as target) | lowers to `apply!(ctrl(Z), (q.wire, q.wire))`; landed `_check_wire_aliasing` (ad.jl:372) sees the doubled `WireID` | **`error()`** with register identity — **fires NOW in M4**, not deferred to M5. See §5. |
| ring op on `View{V,H}` | same as `DualView` — no numeric methods | `MethodError` |

No custom exception hierarchy (S13/plan §4): `DomainError` (chart),
`ArgumentError` (well-formed-but-forbidden), `error()`+identity (guards).

---

## 5. Identity key + the `mightalias`-shaped hook M5 consumes

Wrapper identity ≠ view identity (PRD §3.3): bookkeeping keys on
**(parent wire, transform)**. The Sturm-owned, `dataids`/`mightalias`-shaped
hook (do NOT call Base internals) is a single resolver:

```
_parent_wire(q::QBool)      = q.wire
_parent_wire(v::DualView)   = _parent_wire(v.parent)
_parent_wire(v::View)       = _parent_wire(v.parent)
# M6: _parent_wire(x[i]) = the slice's WireID
```

**M4 already gets aliasing-through-views for free**, because the surface
op methods resolve views to *parent* `WireID`s before calling `apply!`, and
`apply!`'s `_check_wire_aliasing` (ad.jl:372) keys on `WireID`. So
`q̂ ⊻= q` → `apply!(ctrl(Z), (q.wire, q.wire))` → the doubled `WireID`
errors with a register-identity message today. The kernel shadow
`apply!(ctx, ctrl(X), (w, w))` is already tested (`_check_wire_aliasing`
docstring cites `when(a){not!(a)}`).

**What M5 consumes:** guardrail 2 (`when(q) do not!(dual(q)) end` is
aliased — "views resolve to parent wires", §3.5) is *exactly*
`_parent_wire(control) == _parent_wire(any body target)`. M4 ships
`_parent_wire`; M5's per-op aliasing check calls it. This is the
"aliasing check that sees through views" the PRD names. No `(wire,
transform)` *pair* comparison is needed for aliasing (two ops on the same
wire in different pictures still alias the wire) — the transform half of
the key is for *fusion*/*consumed-set* bookkeeping, which M4 needs only for
the consumed set (already keyed on bare `WireID`, single-sourced §4.5).

---

## 6. Fusion-buffer interaction (M2/M3 seam audit)

Traced in §2.2 for measurement. For the entangling/unitary view ops:

- `not!(dual(q))` → `apply!(adjoint(H)∘X∘H, (w,))` → 1q fast path →
  `_fuse!` accumulates a `U2 ≈ Z`. Flushed at the next entangling/measure
  boundary via `_flush_wire!` → `_emit_u2!`. Exact.
- `q̂ ⊻= r` → `apply!(ctrl(Z), (r.wire, q.wire))` → the multi-wire
  `apply!` (ad.jl:349) → `_check_wire_aliasing`, liveness, then
  `_flush_wire!` on **both** touched wires (flushes any pending 1q fusion
  before the 2q op — correctness: fusion commutes only with disjoint ops),
  then `_emit!(::Ctrl,…)` → `_apply_controlled_u2!` sees `Z` → native
  `_emit_cz!`. Exact, native, phase-correct.

**No new seam.** The one design constraint on the implementer: view op
methods must call the *public* `apply!` (not poke `_fuse!`/`_emit!`
directly), so the flush discipline is inherited rather than re-derived.

---

## 7. Named law tests (M4)

All pure-unitary channel tests are **exact one-run DM Choi**; teleport is
the exception (§8). The Choi harness must be **extended to `nin=2`** (the
plan flags this: "multi-input arrives with M4") — prepare 2 Bell pairs,
wrap both system halves, pass a 2-tuple, read reduced ρ over
`(out₁,out₂,ref₁,ref₂)`.

1. **X↔Z view swap (§3.3 Pontryagin, QBool arm).**
   `choi(not!) ≈ J(Ad_X)` and `choi(q->not!(dual(q))) ≈ J(Ad_Z)`, and the
   two differ. (`not!` returns `q`; the channel is the in-place unitary.)
2. **CZ symmetry (§7.3, required Choi test).** `nin=2`:
   `choi((q,r)->(q̂=dual(q); q̂⊻=r; (q,r))) ≈ choi((q,r)->(r̂=dual(r); r̂⊻=q; (q,r)))`,
   both `= J(CZ)`. Also: running both in sequence = identity (two CZs).
3. **Bell prep (`false ⊻ b`).** State-level: `b=QBool(0.5); c=false⊻b`
   leaves (b,c) in Φ⁺ (check `density_matrix` ≈ Bell projector), and
   `xor(true, b)` gives Ψ-type. Fresh-handle identity: `c !== b`.
4. **`dual` involution & wrapper identity.** `dual(dual(q)) === q` (true);
   `dual(q) === dual(q)` (false). Pure Julia unit test.
5. **Mixed-xor exact X (defect 8.3).** `choi(q->(q ⊻= true; q)) ≈ J(Ad_X)`
   (not `Ry(π)`); assert the emitted value `≈ X` at the U2 level too.
6. **B1 negative doctest.** `Meta.lower` of `dual(q) ⊻= r` is an `:error`
   with "invalid assignment location" (extend `test_prd_examples.jl`).
7. **Aliasing.** `q̂=dual(q); q̂ ⊻= q` throws `error()` with the register
   identity in the message (kernel `_check_wire_aliasing`, via
   `_parent_wire` resolution).
8. **Views not numeric.** `dual(q) * 2`, `dual(q) + 1`, `dual(q) & r` each
   throw `MethodError` (the honest P9 wall — a *positive* test that no
   numeric method leaked onto the view).
9. **X-labeling pin.** `Bool(dual(plus()))` on Eager over N≥1000 shots →
   `false` deterministically (|+⟩ ↦ H|+⟩=|0⟩); `Bool(dual(minus()))` →
   `true`. Pins the F†P_kF convention (wm28 convention-side guard).
10. **Teleport** — see §8 (Eager statistical; the exact DM Choi is M5/M8).

*Deferred to M6* (per plan): the F²=parity vs views-unwrap
integer-negation signature test (needs `QInt`).

---

## 8. §7.1 teleportation — transcription, line map, and the LOUD gap

### 8.1 The program, verbatim (PRD §7.1)

```julia
function teleport(ψ::QBool)
    b = QBool(0.5)                # a fair quantum coin  (|+⟩)
    c = false ⊻ b                 # xor into a fresh false: Bell pair
    b ⊻= ψ                        # correlate payload with Alice's half
    m_phase = Bool(dual(ψ))       # conjugate-basis readout (consumes ψ)
    m_value = Bool(b)
    m_value && not!(c)            # ordinary conditionals, ordinary flips —
    m_phase && not!(dual(c))      # one of them in the dual view
    return c
end
```

### 8.2 Line → M-construct map

| Line | Surface op | Provided by | New in M4? |
|---|---|---|---|
| `b = QBool(0.5)` | preparation cast (|+⟩) | M3 `qbool.jl` | no |
| `c = false ⊻ b` | `xor(::Bool,::QBool)` → fresh Bell partner | **M4** actions.jl | **yes** |
| `b ⊻= ψ` | `xor(::QBool,::QBool)` → CNOT, return `b` | **M4** | **yes** |
| `m_phase = Bool(dual(ψ))` | `dual(::QBool)`; `Bool(::DualView)` → H+measure, consume ψ; |+⟩↦false | **M4** | **yes** |
| `m_value = Bool(b)` | qc cast (Eager) | M3 casts.jl | no |
| `m_value && not!(c)` | `not!(::QBool)` → X; Julia `&&` on Bool | **M4** (`not!`) + host | **yes** |
| `m_phase && not!(dual(c))` | `not!(::DualView)` → Z | **M4** | **yes** |
| `return c` | value handle out; ψ,b consumed; region traces nothing else | M2/M3 | no |

**Physics check (GROUND=PHYSICS).** `b=|+⟩`; `false⊻b` = CNOT(b→c) gives
Φ⁺ on (b,c). `b ⊻= ψ` = CNOT(ψ→b). `Bool(dual(ψ))` = H then measure ψ
(the Alice-side Bell measurement's H+Z half). Corrections on Bob's `c`: X
gated by `m_value` (b's Z-outcome), Z gated by `m_phase` (ψ's X-outcome).
This is the textbook one-bit teleportation; it denotes `id`. `Bool(dual(ψ))`
is the exact construct v0.1 lacked (wm28 — it measured Z and teleported
only the diagonal).

### 8.3 What §7.1 needs that M4 lacks — flagged LOUDLY

**M4 can WRITE `teleport` fully** — every op is M4. **M4 cannot run its
exact one-run DM Choi**, for two independent, verified reasons:

- **Scalar `Bool` throws on the DM (channel) context** — `_measure_wire!(::DensityMatrixContext)`
  raises `ArgumentError` (casts.jl:112: "a scalar outcome on a
  density-matrix context is a trajectory, not a channel"). The `choi`
  harness runs `f(qin)` **inside `density(cap)`** (choi.jl:76), so
  `choi(teleport)` throws at the first `Bool(dual(ψ))`.
- **The branchless (Choi-able) form is not M4.** Making teleport a
  single-run channel requires either (a) the deferred variant §7.1b, which
  replaces `&&`-corrections with `when(b) … / when(dual(ψ)) …` — **`when`
  is M5**; or (b) DM measurement-instrument-with-classical-feedforward
  (both outcome branches evolved, weighted, steering the corrections) —
  **DM `cases` is M8** ("DM `cases`: exact instrument semantics").

Neither exists in M4. There is **no M4-only route** to an exact channel
comparison: the corrections are *outcome-conditioned* Paulis, and without
`when` or `cases` you cannot apply an outcome-conditioned correction
coherently (branchlessly). Confirmed.

**Consequence — M4's teleport ✓ is an Eager statistical state-probe test,
not a Choi:**

- Prepare a **Z-sensitive** probe on Eager (the §3.8 rule — a Z-error
  channel is invisible to Z-basis probes): |i⟩ = `QBool(0.5, π/2)` and
  |+⟩ = `plus()`.
- Run `teleport(probe)` on Eager (scalar `Bool` + `&&` both work here);
  measure the output `c` in the **probe-sensitive** basis over N≥1000
  shots — for |i⟩ input, `P(Y=+1) ≈ 1` (the wm28 discriminator: the broken
  v0.1 protocol gave ≈0.5); for |+⟩ input, `Bool(dual(c)) == false`
  deterministically. Both correction-branch combinations are naturally
  sampled across shots. ±3σ tolerance (plan §4).
- Pin `|+⟩ ↦ false` labeling (test 9 above) — the convention-side wm28
  guard.

**The exact one-run DM Choi `Choi(teleport) ≈ J(id)` lands at M5** via
§7.1b (`when`), which the milestone graph already shows as "deferred
teleport ✓ at M5". The plan's phrase "**Choi(teleport) ≈ Choi(id) probed
on |i⟩ and |+⟩**" is only literally satisfiable for the *deferred* form;
for the §7.1 `&&`-form in M4, read it as the **Eager statistical** probe on
|i⟩/|+⟩. I recommend the reviewer either (i) accept the Eager-statistical
teleport test as the M4 gate and place the exact Choi at M5 (matches the
graph), or (ii) pull `when` forward — not advised; M4 is already the
critical core milestone.

### 8.4 §7.1b (for the record — NOT M4)

`teleport_deferred` uses `when(b) do not!(c) end` and
`when(dual(ψ)) do not!(dual(c)) end`, returns `c`, and lets ψ,b trace at
region exit (no casts). It is fully context-portable and DM-Choi-able —
but `when` is M5. `when(dual(ψ))` (control read in the conjugate basis)
also lands at M5, lowered by conjugating `ctrl`'s control wire — the
`_parent_wire`/`_char_dual` hooks M4 ships are exactly what M5 reuses.

---

## 9. Namespace (layering)

- **`export dual, not!`** — surface constructs (rows 3–4 of §3.8).
- **`Base.xor` methods** (QBool×QBool, QBool×Bool, Bool×QBool, DualView×QBool)
  and **`Base.Bool(::DualView)`** — Base extensions, own types → no piracy,
  no new exported name (`⊻=`/`Bool(…)` are host syntax).
- **`public view, View, DualView`** — kernel view machinery, reachable as
  `Sturm.view` etc., absent from `using Sturm` (convention 8).
- **Internal (no export/public):** `_char_dual`, `_parent_wire`,
  `_apply_dual_unitary!`.
- `not!`, `dual`, `view` (as a fresh Sturm generic) collide with **nothing**
  in Base (`isdefined(Base,:not!)`/`:dual` both false; `Base.view` untouched
  if we define our own generic). Verified.

File placement (plan §M4): `src/kernel/views.jl` (`View`, `DualView`,
`view`, `dual` + unwrap, `_char_dual`, `_parent_wire`); `src/surface/dual.jl`
(`Bool(::DualView)`, `_apply_dual_unitary!`, `not!(::DualView)`,
`xor(::DualView,::QBool)`); `src/surface/actions.jl` (`not!(::QBool)`,
`xor` QBool/Bool forms). Include after `surface/casts.jl`. **No edits to any
M1/M2/M3 file** except the two additive `export`/`public` lines in
`Sturm.jl` and the `choi` `nin=2` extension in `test/choi.jl` (test-side).

---

## 10. Deviations from the plan / PRD

- **D-B1 (harness):** M4 must extend `test/choi.jl` `choi` to `nin=2` for
  the CZ-symmetry Choi test. The plan anticipates this ("multi-input
  arrives with M4"); calling it out as an explicit deliverable.
- **D-B2 (teleport test form):** M4's teleport gate is **Eager
  statistical** (|i⟩,|+⟩), *not* the exact DM Choi — forced by scalar-`Bool`
  on DM + `when`∉M4 (§8.3). The exact Choi is M5/§7.1b. This is a
  *reading* of the plan's teleport line, surfaced for the reviewer to
  ratify, not a silent reinterpretation.
- **D-B3 (`view` naming):** propose a fresh `Sturm.view` rather than a
  `Base.view` method, to avoid shadowing array views. Reviewer's call;
  non-core.
- **D-B4 (view-escape detection):** at-*return* ownership-transfer
  detection for a view of a dying local is deferred to D2/later; M4
  guarantees at-*use* safety (dead-wire `error()`). Consistent with PRD
  §3.9's "returning a view of a dying local is a loud error (or explicit
  ownership transfer — D2)".
- **No deviation** on the core semantics: dual unwraps by dispatch (never
  applies F), views lower by conjugation through existing `apply!`, the
  action family returns mutated self, aliasing fires at `apply!` today.

---

## 11. Prior-art citation (docstrings)

`dual`/`views.jl` docstrings cite `docs/physics/adams_qwerty_basis_oriented.md`
and `docs/physics/adams_asdf_basis_translation_synthesis.md` for the
**view-vs-synthesis differentiator**: Qwerty's `>>` is a *synthesized
circuit* (ASDF §6.3, seven-stage structure), never a passive view; the
**canonicity-buys-the-view** point (narrowing to the one character-group
dual) is Sturm's. Do **not** write "they considered and rejected the view"
(unsupported — the distillations' explicit warning); cite Qwerty §IV's own
representation-vs-value disclaimer instead. `∼e` (Qwerty adjoint) is
`Sturm.adjoint` on a process value, **not** `dual` — do not conflate. The
unwrap-not-apply discipline cites JuliaLang#20978 (the
`ctranspose=conj∘transpose`-by-fiat bug) as the cautionary precedent, per
PRD §3.3.
