# M4 Proposal A — Views, `dual`, the action family, teleportation

**Lens: Pontryagin semantics first.** Every lowering below is fixed by one
theorem (§3.3): `dual(q)` addresses a register through its character group Ĝ,
and the basis change is the Fourier transform F_G on G. For `QBool`, G = ℤ₂,
Ĝ = ℤ₂ (self-dual), F_G = **H** (Hermitian, so F = F†). The whole M4 surface
is: (i) a lazy view whose ops lower by kernel conjugation, (ii) the ℤ₂
translation family (`not!`, `⊻=`) and its Ĝ-dual (Z, CZ, X-readout), (iii)
teleportation as the acceptance gate. Nothing here mentions a gate, an angle,
or a process value on the surface.

Files: `src/kernel/views.jl` (new), `src/surface/dual.jl` (new),
`src/surface/actions.jl` (new), `test/choi.jl` (extend to `nin=2`),
`test/test_m4_views.jl` (new). Distillations cited first (already landed):
`docs/physics/adams_qwerty_basis_oriented.md`,
`docs/physics/adams_asdf_basis_translation_synthesis.md` (the
view-vs-synthesis differentiator), `docs/physics/wharton_koch_quaternion_bloch.md`
(HXH = Z, self-dual H).

---

## 1. The view mechanism — `src/kernel/views.jl`

### 1.1 Two wrapper types, deliberately (the `adjtrans.jl` split)

Base does **not** have one generic lazy-matrix wrapper; it has `Transpose` and
`Adjoint` as *distinct nominal types*, each with its own involutive unwrap
(`transpose(A::Transpose) = A.parent`). We follow that exactly:

```julia
# The general parametric view — carries an explicit process value V.
# Library-only (QSVT SELECT conjugates by a Y-axis value this way, §3.3/§5).
struct View{V<:ProcessValue, Q} <: AbstractView
    transform::V     # the basis-change process value
    parent::Q        # the BORROWED handle (never owned; §3.9)
end

# The canonical conjugate view — the surface `dual`. Like `Transpose`:
# a distinct nominal type, storing ONLY the parent. Its transform is
# supplied by the parent's register TYPE (F_G is canonical), never stored
# as data — that canonicity is exactly what buys the passive view (§3.3,
# the Qwerty/ASDF differentiator).
struct DualView{Q} <: AbstractView
    parent::Q
end
```

`AbstractView` is a marker supertype so the aliasing hook (§4) and the M5
`when`-guardrail can dispatch on "any view".

**Why `dual` is NOT `view(F_G, q)` in code** — the load-bearing Pontryagin
point. If `dual` were the composing general view, `dual(dual(x))` would be
`view(F∘F, x) = view(F², x)`, and F² = parity (x ↦ −x). That is precisely the
normative integer-negation bug (§3.3: "an implementation that lowers `dual` by
applying F is wrong… the signature of the error is integer negation under
double duals"). `DualView` being its own nominal type with a *dispatch-time
unwrap* is what makes `dual(dual(q)) === q` structural — Pontryagin's canonical
double-dual identification ev: G → Ĝ̂, no antipode. Conceptually
`dual(q) ≡ view(F_G, q)`; structurally it must be a separate type so the unwrap
is dispatch, not F² evaluation. (For `QBool` the trap is *masked* — H² ≈ +I —
which is exactly why the operational integer-negation test is deferred to M6;
see §6.)

### 1.2 The transform trait (register type declares F_G)

```julia
_dual_transform(::QBool) = H            # ℤ₂, self-dual: F = H = F†
# M6 adds: _dual_transform(::QInt{W}) = QFT{W}   (F ≠ F†; sign fixed by the
#          M6 Pontryagin unit test — see §2/§6)
```

### 1.3 Surface `dual` and the involutive unwrap

```julia
dual(q::QBool)          = DualView(q)                 # fresh wrapper, zero-cost
dual(v::DualView)       = v.parent                    # UNWRAP (adjtrans pattern)
# generic composition (library): stacking `view` composes the processes —
view(V::ProcessValue, q)              = View(V, q)
view(W::ProcessValue, v::View)        = View(W ∘ v.transform, v.parent)  # compose
```

- `dual(dual(q)) === q` (unwrap; no process applied — **no H is emitted**).
- `dual(q) === dual(q)` is `false` (each call constructs a fresh wrapper), so
  consumed-set / aliasing bookkeeping keys on `(parent wire, transform)`, never
  on wrapper identity (§3.3, review r6 (ii)).

**Prior-art framing (cite in the docstring).** Qwerty's `>>` is the *opposite*
denotation — a synthesized circuit (ASDF §6.3, seven-stage
standardize/permute/destandardize), because it maps between *arbitrary*
user-named bases. `dual` narrows to the one canonical character-group dual, and
that narrowing is what makes a pure reinterpretation possible
(`adams_qwerty_basis_oriented.md` §Relevance-2). Cite Qwerty's own §IV
disclaimer (representation-change vs value-change), never "they rejected the
view". `dual` ≠ Qwerty `∼` (`∼` adjoints a *function*; `dual` reinterprets a
*wire* — `adams_qwerty…` §Relevance-3).

---

## 2. Conjugation lowering (direction pinned once)

### 2.1 The single rule, grounded in §3.3

An op routed through a view lowers by **kernel** conjugation, computed at the
process-value level (exact Hamilton products) *before* anything reaches Orkan:

```julia
# Ad_{V†} ∘ op ∘ Ad_V  (§3.3)  ⇒  effective process value V† · g · V
_conj(V::ProcessValue, g::ProcessValue) = adjoint(V) ∘ g ∘ V   # kernel ∘
```

`∘` is right-to-left (§4.2): `adjoint(V) ∘ g ∘ V` applies V first, then g, then
V†; matrix `V†·g·V`. For `QBool`, V = H = H†:

- `_conj(H, X) = H ∘ X ∘ H ≈ Z`  (HXH = Z; `wharton_koch…`, verified by the
  M1 fuzz-certified `∘`). **One fused `U2` (≈ Z) is emitted, not a literal
  H·X·H sandwich** — "views unwrap; processes compose": the conjugation is
  process-value algebra, matrix-free and exact, and the result fuses into the
  M2 per-wire buffer (a `U2∘U2` fuse). This is the M2 fusion buffer eating H
  *as a U2*.

**Direction pin (for general G where F ≠ F†).** The convention is `V†·g·V`
(Ad_{V†}∘op∘Ad_V, §3.3). For `QBool` this is *unobservable* — H is
self-adjoint, so `V†gV = VgV† = HXH = Z` either way. The sign is genuinely
disambiguated only at M6, by the Pontryagin unit test
(`superpose!(x); x̂=dual(x); x̂+=a; Int(dual(x))==a`, and `add!(x,1)` on |0⟩ ⇒
`Int(x)==1`, not `2^W−1`). We pin `V†gV` now; M6 verifies it. (This is a
deliberate, honest limitation of what M4 can certify — recorded in Deviations.)

### 2.2 Measurement through a view = conjugated instrument

`Bool(dual(q))` is the X-basis (conjugate-basis) *consuming* cast — never
gate-then-measure as two surface acts (§3.2), but the instrument
`{P_k} ↦ {V†P_kV}` lowered on the register. Operationally on Eager/DM it is:
apply V (= H) into the standard picture, then the standard Z-instrument (the
handle dies — no restore):

```julia
function Base.Bool(v::DualView{QBool})
    q = v.parent
    q.ctx === current_context() || throw(ArgumentError(...cross-context...))
    apply!(q.ctx, _dual_transform(q), (q.wire,))   # H fuses as a U2 (M2)
    return Bool(q)                                  # M3 qc: flush, measure, consume
end
```

**Labeling pin: |+⟩ ↦ false** (forced by F†P_kF; §7.1). |+⟩ —(H)→ |0⟩ —Z→
outcome 0 → M3 `Bool` returns `out==1` = `false`. |−⟩ ↦ `true`. A fresh |0⟩
read through `dual` is uniformly random (complementarity, §3.9). On DM, `Bool`
throws (inherited from M3 — a scalar outcome is a trajectory; §3.8); the
channel statement uses the Choi harness / M8 tokens.

**Fusion composition.** Because H enters via `apply!(…, H, …)`, it *fuses* with
any pending 1q op on the wire; the flush inside M3 `Bool` realizes exactly one
Orkan gate group. No extra cost, no double flush.

---

## 3. The action family — `src/surface/actions.jl`

All forms mutate in place and return the same handle/view — the **registered
mutation exception** (Julia conv 2; julialang #249/#3217 adopted knowingly:
no-cloning means there is no caller value to clobber, and the exception is
scoped to the bijective action family, never ring ops).

### 3.1 Flips (ℤ₂ translation and its Ĝ-dual)

```julia
not!(q::QBool)              = (apply!(q.ctx, X, (q.wire,)); q)          # exact X
not!(v::DualView{QBool})    = (apply!(p.ctx, _conj(H, X), (p.wire,)); v)  # ≈ Z
                              # p = v.parent; _conj(H,X) ≈ Z (one fused U2)
```

`not!(q)` ↦ X (ℤ₂ translation); `not!(dual(q))` ↦ Z (the ℤ₂ **modulation**) —
the Pontryagin translation↔modulation swap, self-dual pair for ℤ₂ (§3.3). Both
exact (X, Z are exact U(2) elements; M1). `not!` is no longer a *constitutional
exception* — it is the ℤ₂ case of the action family (§3.4/D12); the function
stays, its specialness dissolves.

### 3.2 `Base.xor` register methods (entanglement)

```julia
# CNOT: `q ⊻= r` ≡ `q = xor(q, r)`. TARGET = q (LHS), CONTROL = r.
function Base.xor(q::QBool, r::QBool)
    apply!(q.ctx, ctrl(X), (r.wire, q.wire))   # ctrl wires = (control, target)
    return q                                    # same handle — physical CNOT
end

# Mixed: `q ⊻= true` = exact X (NOT Ry(π) — §3.4 fix / §8.3 regression).
Base.xor(q::QBool, b::Bool) = (b && apply!(q.ctx, X, (q.wire,)); q)

# Classical-to-fresh promotion: `false ⊻ b` allocates a FRESH |0⟩ and
# entangles (the Bell idiom, §7.1). fresh = TARGET, r = CONTROL.
function Base.xor(b::Bool, r::QBool)
    f = QBool(b)                                 # fresh, region-owned (§3.9)
    apply!(r.ctx, ctrl(X), (r.wire, f.wire))
    return f
end
```

**Direction pin: `a ⊻= b` = CNOT, target a, control b** — verified against §7.1
usage (`b ⊻= ψ` correlates payload b with control ψ; `c = false ⊻ b` builds the
Bell pair on (b, c)). Aliasing `q ⊻= q` → `apply!(ctrl(X), (w, w))` → M2
`_check_wire_aliasing` fires with register identity (§8.4) — free.

### 3.3 Bound-view action — CZ

`q̂ = dual(q); q̂ ⊻= r` is controlled-Z. The op is a *controlled* X with only
the **target** wire viewed (the control r is ordinary). Conjugating just the
target wire of a controlled gate is the §4.2 reassociation law
`(1⊗V)∘ctrl(W)∘(1⊗V†) == ctrl(V∘W∘V†)` with V = H on the target:

```julia
# q̂ ⊻= r : target-view = q, control = r  →  ctrl(_conj(H,X)) = ctrl(Z)
function Base.xor(v::DualView{QBool}, r::QBool)
    p = v.parent
    apply!(p.ctx, ctrl(_conj(H, X)), (r.wire, p.wire))   # ctrl(Z), one CZ
    return v
end
```

`ctrl(_conj(H,X))` = `ctrl(U2 ≈ Z)` = `Ctrl{U2}`; `ad.jl`'s
`_apply_controlled_u2!` hits its `u ≈ Z → cz` fast path — one native `orkan_cz`.
**CZ symmetry** `q̂ ⊻= r ≡ r̂ ⊻= q` (symmetry of the pairing G × Ĝ → U(1)) is a
required Choi test (§6): both lower to `ctrl(Z)`, which is symmetric in its two
wires. Equivalent spelling `when(r) do not!(dual(q)) end` lands M5.

### 3.4 Views are NOT numbers (P9 wall)

No ring ops on a view — we simply **do not define** `+`, `*`, `^`, `&`,
`Base.promote_rule`, or `Number` on `AbstractView`, so generic numeric code
handed a view `MethodError`s honestly, the same wall as `g(x::Int)` (§3.3:
"registers are numbers; views are addressing modes"). The mutate-in-place
convention on views can therefore never leak into generic value code. `x̂ += a`
(Ĝ-modulation) is QInt-only and lands M6 — for `QBool` the only bound-view
action is `q̂ ⊻= r`.

### 3.5 Parser traps (dual's docstring — Julia conv 2 / D11 / plan §4-Docs)

- `dual(q) ⊻= r` and `dual(x) += a` are **syntax errors** ("invalid assignment
  location"; a 15-year invariant, julialang #227/#249/#3217). Bind first:
  `q̂ = dual(q); q̂ ⊻= r`.
- `dual(x) = y` inside a function body **silently defines a local method**
  shadowing `dual` for the whole body — a Julia footgun (JuliaLang#20978's
  cousin).
- Cite JuliaLang#20978 ("taking transposes seriously"): defining an operation
  as the *evaluation* of a composition rather than structurally is the same
  category of bug as lowering `dual` by applying F (§1.1 here).

---

## 4. Identity / aliasing — the mightalias-shaped hook

Views borrow (§3.9): a `DualView` registers no owned wire (it is never
`allocate!`d), so its death traces nothing. Bookkeeping resolves views to
parent wires uniformly:

```julia
# Sturm-owned, shaped like Base.dataids/mightalias (do NOT call Base internals).
wireids(q::QBool)          = (q.wire,)
wireids(v::DualView)       = wireids(v.parent)
wireids(v::View)           = wireids(v.parent)
```

- **Consumption / cross-context** inherit from the parent `QBool`: `Bool(dual(q))`
  calls `Bool(q.parent)`, which asserts `q.ctx === current_context()` (M3) and
  marks `q.wire` on the single-sourced consumed set (§4.5). `dual(q) === dual(q)`
  being `false` is harmless because the key is `parent.wire`, not the wrapper.
- **Aliasing already sees through views** at the `apply!` boundary: every action
  extracts `.parent.wire` before calling `apply!`, so M2's `_check_wire_aliasing`
  (which keys on `WireID`) fires on `q̂ ⊻= q` and the M5 shadow
  `when(q) do not!(dual(q)) end`. M4 lays the resolution (`wireids`); M5 uses it
  in the per-op guardrail. This is the §8.4 regression (through views).

---

## 5. Teleportation — §7.1 verbatim + the test

### 5.1 The program (quoted exactly from PRD §7.1)

```julia
"""
    teleport(ψ::QBool) -> QBool

Denotes the identity channel — that is the theorem, and the test:
Choi(trace(teleport, 1)) ≈ Choi(id).
"""
function teleport(ψ::QBool)
    b = QBool(0.5)                # a fair quantum coin
    c = false ⊻ b                 # xor into a fresh false: Bell pair

    b ⊻= ψ                        # correlate payload with Alice's half
    m_phase = Bool(dual(ψ))       # conjugate-basis readout (consumes ψ)
    m_value = Bool(b)

    m_value && not!(c)            # ordinary conditionals, ordinary flips —
    m_phase && not!(dual(c))      # one of them in the dual view
    return c
end
```

Every construct is M4 surface (+ M3 casts): `QBool(0.5)`, `false ⊻ b`, `b ⊻= ψ`,
`Bool(dual(ψ))`, `Bool(b)`, `not!(c)`, `not!(dual(c))`. No gates, no rotations,
no process values. No-cloning is visible: ψ dies at its cast; "teleport and
keep" is unwritable. Classical plumbing is **ordinary Julia Bools + `&&`** —
confirmed against §7.1's text; no `when` needed (that's the deferred §7.1b
variant, M5).

### 5.2 What M4 can actually certify — Eager statistical full-channel probe

The one-run **`Choi(teleport) ≈ Choi(id)`** is *not achievable at M4*, and this
is forced by the landed code, not a shortcut: the Choi harness runs on the DM
context, but §7.1 uses scalar `Bool` + `&&`, and DM `Bool` **throws** by design
(`density.jl`: a scalar outcome on a channel-executing context is a trajectory,
§3.8). A one-run DM Choi of a branching-measurement channel needs either
coherent deferral (`when`, M5) or DM `cases`/instrument semantics (M8). Hence,
per the plan's own split (M4 "probed on |i⟩ and |+⟩"; M5 "deferred teleport
§7.1b — same Choi"), **M4 ships the Eager statistical full-channel probe** and
**M5 ships the deterministic `Choi(teleport_deferred) ≈ Choi(id)`**.

The M4 test is the wm28 killer and is *stronger than any marginal test*: it
probes **Z-sensitive** states (the class wm28's broken teleport turns into a
silent Z-error channel):

```julia
# N ≥ 1000 shots per probe; ±3σ tolerance (cross-cutting policy).
# Probe set is tomographically informative and Z/Y-sensitive.
for (prep, readout, expect) in [
    (() -> QBool(0.5),        :Xbasis, false),   # |+⟩  → Bool(dual(out)) == false
    (() -> QBool(0.5, π),     :Xbasis, true),    # |−⟩  → Bool(dual(out)) == true
    (() -> QBool(0.5, π/2),   :Ybasis, +1),      # |i⟩  → Y-readout == +i  (wm28)
    (() -> QBool(true),       :Zbasis, true),    # |1⟩  → Bool(out) == true
    (() -> QBool(false),      :Zbasis, false),   # |0⟩  → Bool(out) == false
]
    hits = 0
    for _ in 1:N
        eager(cap) do ctx
            out = teleport(prep())
            hits += _matches(readout, out, expect)   # test-side readout
        end
    end
    @test hits/N ≈ 1.0 atol = 3*sqrt(N)/N           # recovery ≈ 1
end
```

- **X-basis readout** = the surface `Bool(dual(out))` (M4).
- **Y-basis readout** for the |i⟩ probe has no surface cast (QBool's only dual is
  X-basis). The *test* is licensed to reach kernel values (exactly as
  `test/choi.jl` does: `using Sturm: H, S, apply!, …`): apply `adjoint(S)` then
  `H` to `out.wire`, then Z-measure — the standard Y-basis instrument. **This is
  the sharpest wm28 probe**: v0.1's diagonal-only teleport reads P(Y=+i) ≈ 0.5
  (verified during the D5 port); the correct channel reads ≈ 1.
- **Labeling pin** falls out: |+⟩ ↦ `false`, |−⟩ ↦ `true` (§2.2). Reversing the
  X-outcome labeling reproduces wm28's failure *from the convention side* (a
  Z-error channel invisible to Z-marginals) — which is why the probe set
  includes |+⟩/|−⟩/|i⟩ and not only Z-states.

### 5.3 The M5 companion (documented here for the reviewer's arc)

`teleport_deferred` (§7.1b, corrections under `when` before any cast, no
branching, no casts — ψ and b traced at region exit) traces as-is and gives the
deterministic **`Choi(teleport_deferred) ≈ Choi(id)`** one-run DM test. It
denotes the same identity channel (a free second test). M5 deliverable; noted so
the reviewer sees that M4's statistical probe is the *available* half of a
two-part acceptance gate, not a weaker substitute.

---

## 6. Named tests — `test/test_m4_views.jl` (+ `choi.jl` extension)

Each `@testset` is named after its PRD section (grep-able coverage map).

1. **`dual` unwrap / wrapper identity (§3.3)** — `dual(dual(q)) === q` (`===`,
   structural); `dual(q) === dual(q)` is `false`; **no Orkan op emitted by
   `dual(dual(q))`** (assert the wire's fusion buffer is empty and the
   statevector is bit-identical after `dual(dual(q))` — the unwrap applied *no*
   process). Pure Julia + a trivial Eager context.

2. **views-unwrap vs processes-compose (§3.3), QBool-scoped** — type-level:
   `dual(dual(q)) isa QBool` (=== q) while `view(H, view(H, q)) isa View` and
   equals `view(H∘H, q)` (composition, *not* unwrap). For `QBool` H² ≈ +I so
   both leave the state ≈ unchanged — the trap is **masked**; the sharp
   *integer-negation signature* test (`dual(dual(x)) == x` while F² negates)
   arrives with M6/QInt, per plan. Assert here that the two constructions have
   **different types**, and record the M6 IOU in the testset comment.

3. **X ↔ Z swap (§3.3/§3.4)** — DM Choi (unitary channels, one-run):
   `choi(q -> (not!(q); q), 1) ≈ Choi(X)` and
   `choi(q -> (not!(dual(q)); q), 1) ≈ Choi(Z)`, and the two Chois differ.
   (`Choi(X)`/`Choi(Z)` = denoted references built test-side from `X`/`Z`.)

4. **`Bool(dual(q))` X-readout statistics + labeling pin (§3.3/§7.1)** —
   Eager, N ≥ 1000, ±3σ: `plus()` → `false` (P ≈ 1); `minus()` → `true`
   (P ≈ 1); `QBool(false)` → 50/50 (complementarity — a |0⟩ read through `dual`
   is uniform). Pins |+⟩ ↦ `false`. DM: `Bool(dual(q))` throws (trajectory,
   §3.8) — an error-path test.

5. **CZ symmetry at Choi level (§3.3/§7.3)** — requires the **`nin=2` Choi
   harness extension** (M4 deliverable; the harness's own note says
   "multi-input arrives with M4"). Build
   `f1 = (q,r) -> (q̂=dual(q); q̂ ⊻= r; (q,r))` and
   `f2 = (q,r) -> (r̂=dual(r); r̂ ⊻= q; (q,r))`; assert
   `choi(f1, 2) ≈ choi(f2, 2)` and both `≈ Choi(ctrl(Z))` (test-side reference).
   Also: applying `q̂ ⊻= r` twice = identity (two CZs cancel).

6. **teleport — Eager full-channel probe (§7.1/§8.8, wm28)** — §5.2 above:
   {|+⟩, |−⟩, |i⟩, |0⟩, |1⟩}, recovery ≈ 1, |i⟩ Y-readout is the wm28 regression;
   labeling pin |+⟩ ↦ false. (M5 adds `Choi(teleport_deferred) ≈ Choi(id)`.)

7. **aliasing through views (§8.4)** — `q̂ = dual(q); q̂ ⊻= q` errors loudly with
   register identity (the M5 `when(q) do not!(dual(q)) end` shadow), via M2
   `_check_wire_aliasing` on the resolved parent wire.

**Choi harness extension (`test/choi.jl`).** `choi(f, 2; cap)`: prepare two Bell
pairs `(sys₁,ref₁),(sys₂,ref₂)`, wrap `sys₁,sys₂` as QBools, `(o₁,o₂)=f(qin₁,qin₂)`,
keep slots `(o₁,o₂,ref₁,ref₂)` (out MSBs), reduce to the 16×16 Choi. Cost:
4 kept wires ⇒ `_ptrace_keep` over `cap≈8` — well under the 15-wire cap. Reuse
`_ptrace_keep` (already slot-keyed and recycle-robust).

---

## 7. Namespace (Julia conv 8, layering)

- **Surface exports** (added to `src/Sturm.jl` `export`): `dual`, `not!`. The
  `⊻=` forms are `Base.xor` method extensions on our own types (`QBool`,
  `DualView`) — no new name to export; `⊻` is Base infix. `Bool(dual(q))` is a
  `Base.Bool` extension (no export).
- **Kernel public** (`public` stanza): `view`, `View`, `DualView`, `AbstractView`,
  `wireids`. `_conj`, `_dual_transform` stay internal (underscore).
- Not exported, not public: nothing surface-facing leaks a process value — F_G is
  reached only through the register type, and `dual` is the unique view
  constructor taking no process-value argument (its P5 surface privilege, §3.3).

---

## Appendix — grounding ledger (every lowering → its law)

| M4 lowering | Value emitted | Grounded in |
|---|---|---|
| `dual(dual(q)) === q` | (nothing) | Pontryagin double-dual ev; adjtrans unwrap (§3.3) |
| `not!(q)` | exact `X` | ℤ₂ translation; X exact in U(2) (§3.4, M1) |
| `not!(dual(q))` | `_conj(H,X) ≈ Z` | ℤ₂ modulation; HXH=Z (`wharton_koch…`) |
| `q ⊻= r` | `ctrl(X)` (r,q) | CNOT = ℤ₂-translation entangler (§3.4) |
| `q ⊻= true` | exact `X` | mixed form; NOT Ry(π) (§3.4/§8.3 fix) |
| `false ⊻ b` | fresh |0⟩ + `ctrl(X)` | classical→fresh promotion (§3.4/§7.1) |
| `q̂ ⊻= r` | `ctrl(_conj(H,X)) = ctrl(Z)` | §4.2 reassociation `(1⊗V)ctrl(W)(1⊗V†)=ctrl(VWV†)` |
| `q̂ ⊻= r ≡ r̂ ⊻= q` | ctrl(Z) symmetric | symmetry of G × Ĝ → U(1) (§3.3) |
| `Bool(dual(q))` | apply H, Z-instrument, consume | conjugated instrument V†P_kV (§3.3/§7.1) |
| `\|+⟩ ↦ false` | k=0 ↦ \|+⟩ | F†P_kF labeling (§7.1) |
| teleport ≈ id | full channel | §7.1 theorem; wm28 Z-sensitive probe (§8.8) |

Direction convention `V†·g·V` is pinned from §3.3; **not observable within M4**
(QBool self-dual, F = H = F†) and disambiguated by the M6 Pontryagin test.
