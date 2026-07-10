# M6 Proposal B — `QInt{W}`, wire handles (D2), the two arithmetic worlds (D12)

**Lens:** Julia dispatch, method-table hygiene, and misuse topology first. The
whole milestone is a dispatch problem: *the same `Base.:+` generic must mean
"fresh output" on one receiver type and "in-place physical op" on another*, and
every wrong program a user can type must land on a loud, identity-bearing error
rather than a silent wrong channel. I design the method table first, then make
the physics fit it.

---

## 1. Executive summary (the 10 lines)

1. `QInt{W}` is a **bare immutable struct** `(ctx, wires::NTuple{W,WireID})`,
   stored **LSB-first** (`wires[i]` = bit `i-1`), **not** `<: Integer/Number` —
   continue M3's D-A-1 deferral; P9 is honored by *selective operator overloads*,
   not subtyping (subtyping imports Base fallbacks that clone/measure).
2. The two worlds are **one dispatch fact**: `Base.:+(::QInt,…)` returns a
   **fresh** register (value world); `Base.:+(::DualView{<:QInt},…)` mutates and
   **returns the same view** (action world). `x += a` rebinds → lost binding;
   `x̂ += a` is `x̂ = x̂` → physical. Nothing else distinguishes them.
3. Value-world `s = x + a` **cannot clone** — it is a reversible out-of-place
   adder: `s = QInt{W}(0); s ⊻= x; add!(s, a)` → `|x⟩|x+a⟩`, `x` stays live.
4. `x[i]` returns a **new borrow type `WireRef`** (not a bare `QBool`); single-
   wire surface ops widen to `const Qubit1 = Union{QBool,WireRef}` via two
   accessors — DRY (principle 13), and the distinct type is the §8.5 aliasing hook.
5. `dual(x)` reuses M4's `DualView`; `_dual_transform(::QInt{W}) = QFT_W`, a new
   `QFT <: ProcessValue` node applied **uncontrolled** through the existing
   `apply!`.
6. **Reassociation for free:** `add! = F ; M_a(via _act!) ; F†` — F/F† bypass the
   control stack (like the M4 `dual`-view basis change), so `when(c) do add! end`
   controls only `M_a` — the §4.2 law realized at M6 with no M8 pass.
7. Two sign pins, both derived on paper here: `add!(x,1)|0⟩ ⇒ Int(x)==1` fixes
   `T_a = F†M_aF`; `x̂ += a; Int(dual(x)) == a` fixes the view as `M_{-a}`.
8. `dual(dual(x)) === x` is a **structural unwrap** (no F applied) while
   `denoted_matrix(F∘F) ≈ parity-Perm` (integer negation) — the normative
   F²-vs-unwrap signature test.
9. **Strict mode** completes on the scaffolded `core.parent`/`core.strict`:
   record child→parent edges on value-world ops only; at region exit flag a
   *traced parent with a surviving child*. Default silent; returning the fresh
   output never false-positives (the parent stays live).
10. M6's gate is the **sign pins + F²-signature + strict-mode + wrap/partial-
    consumption/aliasing** law tests. No worked example is owed (DJ/BV are M7);
    `superpose!` lands here only because the Pontryagin test needs it.

---

## 2. The method table (the centerpiece)

`x, y : QInt{W}`; `a, n : Integer`; `x̂ = dual(x) : DualView{QInt{W}}`;
`r = x[i] : WireRef`. "self" = returns the mutated first handle (the op-assign
no-op that makes it physical); "fresh" = returns a new handle (a real `=`).

### 2a. Value world — fresh output, inputs stay live (P9 generic path)

| Surface | Base method (signature) | Returns | Lowering |
|---|---|---|---|
| `s = x + a` | `Base.:+(x::QInt{W}, a::Integer) where W` | **fresh** `QInt{W}` | `s=QInt{W}(0); s ⊻= x; add!(s,a)` |
| `s = a + x` | `Base.:+(a::Integer, x::QInt{W})` | fresh | `+(x,a)` |
| `s = x + y` | `Base.:+(x::QInt{W}, y::QInt{W}) where W` | fresh | `s=QInt{W}(0); s ⊻= x; add!(s,y)` |
| `s = x - a` | `Base.:-(x::QInt{W}, a::Integer)` | fresh | `+(x, -a)` (mod 2^W) |
| `s = x - y` | `Base.:-(x::QInt{W}, y::QInt{W})` | fresh | `s⊻=x; sub!(s,y)` |
| `x * y`, `x^2` | **not defined at M6** | — | MethodError (no catch-all); mulmod = M9 |
| `x == y`, `x < a` | **not defined at M6** | — | comparator = oracle, M7 (see §11 footgun) |

Return-type is `QInt{W}`, never `Int` — the result is a live register (Draper
adds keep it quantum). Mixed `QInt{W} + QInt{V}` (V≠W): a define-to-throw
`ArgumentError` (§11), never silent promotion.

### 2b. Action world — in-place bijection, handle stable (the registered exception)

| Surface | Base/Sturm method | Returns | Lowering |
|---|---|---|---|
| `add!(x, a)` | `add!(x::QInt{W}, a::Integer)` | self `x` | `apply!(F); M_{+a} via _act!; apply!(F†)` (Draper) |
| `sub!(x, a)` | `sub!(x::QInt{W}, a::Integer)` | self | `add!(x, -a)` |
| `add!(y, x)` | `add!(y::QInt{W}, x::QInt{W})` | self `y` | `apply!(F on y); ctrl-modulation from x's wires via _act!; apply!(F† on y)` |
| `x ⊻= n` | `Base.xor(x::QInt{W}, n::Integer)` | self `x` | per-wire exact `X` for set bits of `n` |
| `x ⊻= y` | `Base.xor(x::QInt{W}, y::QInt{W}) where W` | self `x` | W parallel `_act!(ctrl(X))`, target=x[i], control=y[i] |
| `not!(x)` | `not!(x::QInt{W})` | self `x` | bitwise-NOT = `x ⊻= (2^W−1)` (the (ℤ₂)^W flip; ≠ `add!(x,1)`) |

`add!`/`⊻` route **through `_act!`** for the *controlled* part (see §7) so
`when(c) do add!(x,a) end` = controlled addition, correct by construction.

### 2c. Dual-view (bound-view) world — Ĝ-modulation, in-place, returns the view

| Surface | Base method | Returns | Lowering |
|---|---|---|---|
| `x̂ = dual(x)` | `dual(x::QInt{W})` | `DualView{QInt{W}}` | fresh wrapper, borrows |
| `dual(x̂)` | `dual(v::DualView) = v.parent` (M4) | `x` | structural unwrap, no F |
| `x̂ += a` | `Base.:+(v::DualView{<:QInt}, a::Integer)` | **self** `v` | `M_{-a} via _act!` (per-wire `Rz`); no F |
| `x̂ += x2` | `Base.:+(v::DualView{<:QInt}, x2::QInt{W})` | self `v` | ctrl-modulation ω^{x2·k} via `_act!` |
| `Int(x̂)` | `Base.Int(v::DualView{<:QInt})` | `Int` (consumes) | `apply!(F); Int(parent)` |

`x̂ -= a` = `+(v, -a)`. Ring ops on `x̂` (`x̂ * 2`, `x̂ & 1`): **undefined** →
MethodError (views are not numbers; §3.3 honest wall).

### 2d. Casts & slices

| Surface | Base method | Returns | Notes |
|---|---|---|---|
| `QInt{W}(n)` | `QInt{W}(n::Integer) where W` | `QInt{W}` | prep; `DomainError` if `n ∉ 0:2^W−1` |
| `Int(x)` | `Base.Int(x::QInt{W})` | `Int` (consumes all W) | partial-consumption check first |
| `x[i]` | `Base.getindex(x::QInt{W}, i::Integer)` | `WireRef` (borrow) | `BoundsError` if `i ∉ 1:W` |
| `dual(x[i])` | `dual(r::WireRef)` | `DualView{WireRef}` | ℤ₂ dual of the slice (F=H) |
| `dual(x)[i]` | `Base.getindex(v::DualView{<:QInt}, i)` | **throws** | define-to-throw `ArgumentError` (D2) |
| `Bool(x[i])`, `not!(x[i])`, `x[i] ⊻= r`, `Bool(dual(x[i]))` | via `Qubit1` union | — | reuse M3/M4 single-wire methods (§5) |
| `superpose!(x)` | `superpose!(x::QInt{W})` | self | library materialization `H^⊗W` (uncontrolled) |

---

## 3. `QInt{W}` — the type and the one endianness pin

```
struct QInt{W}
    ctx::AbstractContext      # owning context (leaf-handle pattern, as QBool)
    wires::NTuple{W,WireID}   # LSB-first: wires[i] holds bit (i-1)
end
```

`W` is the **only** type parameter (§3.1; QBool's header already forecast
`QInt{W} = (ctx, NTuple{W,WireID})`). `ctx` abstract-typed exactly as QBool —
handle construction is not the hot loop; the `@code_warntype` gate stays on the
wire-level `apply!`/`_act!` path.

**Endianness (one function owns it).** Two conventions collide: surface `x[i]`
and BV's `evalpoly(2, bits)` want **LSB-first** (`x[1]` = bit 0); the kernel
`Perm`/`Ctrl`/`apply!` want **position 1 = MSB**. I store LSB-first and cross
the boundary in exactly one place, mirroring `q(ctx,·)`:

```
_msb_wires(x::QInt{W}) where W = reverse(x.wires)   # kernel-position order (MSB first)
_bit_wire(x, j)               = x.wires[j+1]        # the wire carrying bit weight 2^j
```

Every multi-wire process value handed to `apply!` (QFT, transversal `⊻`) goes
through `_msb_wires`; every per-wire phase schedule indexes with `_bit_wire`.
A bit-order slip localizes to these two helpers.

**Adoption seam** (for the Choi harness / `+`'s fresh output):
`_adopt_qint(ctx, ws::NTuple{W,WireID}) = QInt{W}(ctx, ws)` — wrap already-live
wires without preparing, the analogue of `_adopt_qbool`.

---

## 4. Casts

**Preparation** `QInt{W}(n::Integer)`:

```
function QInt{W}(n::Integer) where W
    (0 ≤ n < (1 << W)) || throw(DomainError(n,
        "QInt{$W}(n): n must be in 0:$(2^W-1) (ℤ_{2^$W}); a literal names a point. " *
        "Arithmetic wraps (add!), but a preparation literal outside the ring is a bug."))
    ctx = current_context()
    ws = ntuple(i -> allocate!(ctx), W)          # W fresh |0⟩, region-owned (§3.9)
    x = QInt{W}(ctx, ws)
    for j in 0:W-1
        (n >> j) & 1 == 1 && apply!(ctx, X, (_bit_wire(x, j),))   # exact kernel X, not Ry(π)
    end
    return x
end
```

Literal-out-of-range is `DomainError` (chart violation, exactly QBool's `p∉[0,1]`
policy); `add!` overflow **wraps** (ℤ_{2^W} is the group — documented, tested,
never an error). This asymmetry is deliberate and stated in both docstrings.

**Measurement** `Int(x::QInt{W})` — consuming, with the D2 partial-consumption
guard *before* any collapse:

```
function Base.Int(x::QInt{W}) where W
    ctx = x.ctx; ctx === current_context() || throw(ArgumentError(...cross-context...))
    _assert_no_control(ctx, "measurement cast Int(x)")          # guardrail 1
    dead = filter(w -> is_consumed(ctx, w) || !haskey(_core(ctx).wire_to_slot, w), collect(x.wires))
    isempty(dead) || error("register $(x) partially consumed: wire(s) $dead are dead " *
        "(a slice was measured via Bool(x[i]) or the register was traced); measure the " *
        "remaining wires explicitly, do not Int(x) a holed register (D2/§8.5).")
    v = 0
    for j in 0:W-1
        Bool(_wireref(x, j+1)) && (v |= (1 << j))    # LSB-first reassembly; each Bool consumes
    end
    return v
end
```

The partial-consumption check is a **set-intersection on the single-sourced
consumed set** (§8.5) — never a silent reinterpretation of `Int`. It reuses
`Bool(::WireRef)` (§5) so consumption is single-sourced automatically.

---

## 5. `x[i]` — the borrow wrapper (D2), and why not a bare `QBool`

### The type decision, argued from dispatch

`x[i]` returns a **new `WireRef`**, not a bare `QBool`:

```
struct WireRef                     # a borrow of ONE wire of a parent register
    ctx::AbstractContext
    wire::WireID
    reg::WireID                    # provenance = the parent's LSB wire, for messages only
    idx::Int                       # 1-based slice index, for messages only
end
```

**Why not reuse `QBool` (the tempting option).** Functionally, QBool-as-slice
*would work* — consumption is single-sourced on `WireID`, so `Bool(x[i])` marks
`x.wires[i]` on `ctx.consumed` and `Int(x)`'s partial-consumption check catches
it regardless of the wrapper type. But two dispatch facts kill it:

1. **Ownership is a type lie.** `QBool`'s constructor *allocates and prepares*;
   its docstring promises "traced at region exit if neither consumed nor
   returned." A slice is a **borrow** — its death must trace nothing (§3.9
   "views borrow"). A QBool-slice handed to a function typed `f(::QBool)` looks
   like an owned register; if `f` returns or measures it, it silently partial-
   consumes `x` with no type boundary having flagged the ownership transfer.
   A distinct `WireRef` lets `f(::QBool)` **reject** a slice (or accept it only
   via the deliberate `Qubit1` widening) — the ownership distinction becomes a
   dispatch distinction, which is the whole point of §8.5's "SubArray-vs-Array
   type split."
2. **The aliasing hook wants provenance.** §8.5 asks for a
   `dataids`/`mightalias`-shaped dispatchable hook "at the DSL level (owner id +
   wire index)." A bare QBool carries only the wire; `WireRef` carries `reg`+`idx`,
   so `x ⊻= x[i]` and the "wire 3 of register x" messages are expressible. (The
   *aliasing safety* is already guaranteed by `WireID` uniqueness — `x[i].wire
   === x.wires[i]`, so `_check_wire_aliasing` fires on the collision regardless;
   `reg`/`idx` buy the *good message*, not the safety.)

**Bounds check** in `getindex` (Base idiom, `BoundsError`):

```
function Base.getindex(x::QInt{W}, i::Integer) where W
    (1 ≤ i ≤ W) || throw(BoundsError(x, i))
    return WireRef(x.ctx, x.wires[i], x.wires[1], Int(i))
end
```

### Generalizing single-wire ops — the DRY move (principle 13)

`WireRef` and `QBool` are both "one live wire in a context." Rather than
duplicate `not!`/`xor`/`Bool`/`dual`, I widen the M3/M4 single-wire methods to a
union via two accessors:

```
const Qubit1 = Union{QBool, WireRef}
_wireid(h::Qubit1) = h.wire
_ctxof(h::Qubit1)  = h.ctx
```

Then the M4 `_here`, `not!`, `Base.xor(::QBool,…)`, `Base.Bool(::QBool)`,
`dual(::QBool)`, `_dual_transform(::QBool)`, `_parent_wire(::QBool)` signatures
widen `QBool → Qubit1` (mechanical — they already only touch `.ctx`/`.wire`).
`_dual_transform(::WireRef) = H` (a slice's dual is the conjugate basis of that
one ℤ₂ wire). This **edits landed M3/M4 files** (actions.jl, casts.jl, views.jl,
qbool.jl's `_here`) — in-scope for a core 3+1 milestone, and it is the correct
anti-duplication choice. *Fallback if the implementer wants a smaller blast
radius:* give `WireRef` its own thin methods delegating to shared
`_flip1!(ctx,wire)`/`_meas1!`/`_conj`-emit helpers (option B) — same physics,
more lines. I recommend the union.

`_parent_wire(r::WireRef) = r.wire` (already the generic view pattern), so
`when` guardrail-2 and aliasing "see through" slices for free.

---

## 6. `dual(x::QInt{W})` and the QFT node — how `F_G` reaches `ad.jl`

`dual(x)` reuses M4's `DualView{QInt{W}}` verbatim (parametric on parent type;
the unwrap `dual(v::DualView)=v.parent` is already generic → `dual(dual(x))===x`
falls out with **zero new code**, and this is the F²-vs-unwrap invariant).

`_dual_transform(::QInt{W}) = QFT(W, false)`. The question is what `QFT` *is*.

### Decision: a new `QFT <: ProcessValue` node (option c), applied uncontrolled

```
struct QFT <: ProcessValue
    n::Int
    inv::Bool          # false = F (forward, ω=e^{+2πi/2^n}); true = F†
end
nwires(f::QFT) = f.n
Base.adjoint(f::QFT) = QFT(f.n, !f.inv)
denoted_matrix(f::QFT) = <dense DFT (or its conjugate) — test/Ad cross-check only>
```

`_emit!(ctx, f::QFT, qs)` (in `ad.jl`, under the choke-point lint umbrella)
emits the standard H + controlled-phase ladder **including the ⌊n/2⌋ bit-reversal
swaps** (via `_emit_swap!`), so `denoted_matrix(QFT(n,false))` **is** the exact
DFT matrix and is unit-testable at the matrix level. The controlled phases are
built as **`ctrl(P(θ))` process values** — `P(θ) = U2(cos(θ/2),0,0,sin(θ/2), θ/2)`
= diag(1, e^{iθ}) — and lowered by the **existing** `_apply_controlled_u2!`
(Lemma 5.2's phase line handles the diagonal exactly). This honors the choke
point mechanically: no new controlled-lowering code, controlled phases come only
from `ctrl` values.

**Why (c) over (a) a Seq/Tensor tree or (b) a bare `_emit_qft!`:**
- vs **(b)**: a bare emitter bypasses `apply!`'s aliasing/liveness/flush rails
  and has no `denoted_matrix` cross-check. The node flows through `apply!`
  uniformly and is matrix-testable — decisive for a milestone whose gate *is*
  the sign/parity pins.
- vs **(a)**: a per-call Seq/Tensor tree of H and Ctrl(P) values would work and
  compose, but `W` is runtime-dynamic within the type parameter, so we'd rebuild
  an O(W²)-node tree on every `add!`/`Int(dual)` call and lean on the generic
  `Seq` emit recursion. A single `QFT` node is O(1) to construct, self-describing
  for M8 (one node the reassociation/view-fusion passes can pattern-match), and
  keeps `_emit!` iterative. (a) is the honest fallback if we ever want QFT to be
  transparent to generic passes before M8; I judge the node cleaner.

**Emission count, W=4** (folding nothing): 4 H + 6 controlled-P + 2 swaps. Each
controlled-P lowers via the ABC+phase-line path (correct, ~6 primitive ccalls) —
a cheaper controlled-diagonal fast path (`CP(θ) = P(θ/2)⊗P(θ/2)·CX·(I⊗P(−θ/2))·CX`)
is a legitimate `ad.jl` optimization but **out of M6 scope** (note for M8 fusion).

**Is `QFT` ever controlled?** Not in M6 surface: `add!`/`Int(dual)` apply it
uncontrolled, and controlled `add!` needs only `ctrl(M_a)` (§7), not `ctrl(F)`.
So I add **no** `ctrl(::QFT)` method — an attempt is a `MethodError` (the
no-catch-all discipline), and M8/phase-estimation adds it when a controlled QFT
genuinely appears. Documented as a deliberate gap.

---

## 7. `add!` (Draper), modulation, and the sign pins — derived on paper

### The two operations are the same phase schedule, differently wrapped

**Modulation** `M_a` on the value register = the diagonal `diag_k(ω^{ak})`,
`ω = e^{2πi/2^W}`. Since `|k⟩ = Σ_j bit_j(k) 2^j`, `M_a` factors into **per-wire
1q phases**: wire `j` (bit weight `2^j`) gets `P(2π a 2^j / 2^W)`, i.e. as a U2
the relative-phase `Rz(2π a 2^j / 2^W)` (Ad drops the global half-phase, leaving
exactly the ω^{ak} ramp). **No F, no controls** — W single-wire ops that *fuse*
in the per-wire buffer (so `x̂ += a; x̂ += b` costs W fused Rz's, not two
sandwiches — the view-fusion win, free from the M2 fusion buffer).

```
_emit_modulation!(actor!, x::QInt{W}, a::Integer, s::Int)   # s = ±1 sign
    for j in 0:W-1
        actor!(ctx, Rz(s * 2π * a * (1<<j) / (1<<W)), (_bit_wire(x,j),))
    end
```

`actor!` is `_act!` (so the schedule is controlled under a live `when` stack) —
one helper, two callers (`add!` and the view `+=`), DRY.

### Draper translation `T_a = F† ∘ M_a ∘ F` (derived)

With `F|k⟩ = 2^{-W/2} Σ_m ω^{km}|m⟩` and `M_a|m⟩ = ω^{am}|m⟩`:
`F† M_a F |k⟩ = Σ_l (2^{-W} Σ_m ω^{(k+a−l)m}) |l⟩ = |k+a mod 2^W⟩`. ✔ So

```
function add!(x::QInt{W}, a::Integer) where W
    ctx = _here_qint(x)
    apply!(ctx, QFT(W,false), _msb_wires(x))      # F — UNCONTROLLED (basis change)
    _emit_modulation!(_act!, x, a, +1)            # M_{+a} — CONTROLLED part (via _act!)
    apply!(ctx, QFT(W,true),  _msb_wires(x))      # F† — UNCONTROLLED
    return x
end
```

**Sign pin #1:** `add!(x,1)` on `|0⟩` → `|1⟩` ⇒ `Int(x)==1` (not `2^W−1`). This
is a *required test* and it is what fixes `M_a = ω^{+am}` inside the sandwich.

**Reassociation for free.** F and F† call **`apply!` directly (uncontrolled)**,
exactly as the M4 `when(dual(q))` basis change and `QBool` prep do — only
`M_a` routes through `_act!`. So `when(c) do add!(x,a) end` streams as
`(1⊗F†) ctrl(M_a) (1⊗F)`, which equals `ctrl(F†M_aF) = ctrl(T_a)` (block-diagonal
identity: `F†·I·F = I` on the control=0 block). Controlled addition is correct
**and** the §4.2 reassociation is realized at M6 with no M8 pass — the same
license the M5 `when(dual(q))` H-sandwich already uses (Delorme Eq 16).

### The view `+=` is `M_{-a}` (the r6/B2 correction, derived)

`x̂ += a` translates the *dual label*, which is a **modulation of x** — no F.
For the Pontryagin unit test `superpose!(x); x̂ += a; Int(dual(x)) == a`: after
`superpose!`, `x = 2^{-W/2}Σ_k|k⟩`. We need `F(x') = |a⟩`, i.e.
`x' = F†|a⟩ = 2^{-W/2}Σ_k ω^{-ak}|k⟩`, so the modulation must be **`M_{-a}`**:

```
Base.:+(v::DualView{<:QInt{W}}, a::Integer) where W =
    (_emit_modulation!(_act!, v.parent, a, -1); v)     # M_{-a}; returns the VIEW (self)
```

**Sign pin #2:** `x̂ += a; Int(dual(x)) == a` — fixes the view ramp as `M_{-a}`.
The opposite sign vs `add!`'s inner `M_{+a}` is the "fixed-once convention" the
PRD promises; both are pinned by their named tests and cross-checked against
`denoted_matrix` in the implementer's tests (the M4 `_conj`-verification pattern).

`Int(dual(x))` = `apply!(F); Int(parent)` (consuming), exactly parallel to
`Bool(dual(q))`. Guardrail 1 asserted at the top (no Fourier-sampling under `when`).

**Quantum-addend `add!(y, x)`** = `|x⟩|y⟩ → |x⟩|y+x⟩`: `F on y`; then for each
wire `i` of `x` (bit weight `2^i`), a `_act!`-routed controlled-modulation
`ctrl(M_{2^i})` with control `x[i]`, target the Fourier register `y` — the
cross-phase `ω^{x·m}`; then `F† on y`. `x` read control-like (stays live), `y`
mutated. `ŷ += x` (dual view, quantum addend) is the same cross-phase **without**
the F/F† (direct controlled-modulation on `y`'s current basis).

---

## 8. Value-world adders cannot clone (the subtlety that shapes `+`)

`s = x + a` "leaves x live" is often misread as "copy x, then add" — but
**no-cloning forbids copying a superposed `x`**. The value-world adder is the
standard **reversible out-of-place** pattern:

```
Base.:+(x::QInt{W}, a::Integer) where W = (s = QInt{W}(0); s ⊻= x; add!(s, a); s)
```

`s ⊻= x` is the **transversal CNOT** (copy-in-basis / fanout: `|x⟩|0⟩ → |x⟩|x⟩`,
entangled, *not* a clone), then `add!(s,a)` translates `s` in place →
`|x⟩|x+a⟩`. `x` remains live and correct as a control-like register. This is why
value-world `+` **reuses `add!`** (principle 13) and why it necessarily
**entangles** `s` with `x` — which is precisely what makes the lost-binding trap
physical (§10). `x + y` is `s ⊻= x; add!(s, y)`.

---

## 9. P8/P9 — `QInt{W}` subtypes nothing (continue D-A-1)

`QInt{W}` is **not** `<: Integer` or `<: Number`. Reasons, dispatch-first:

- Subtyping `Integer` inherits Base's generic fallbacks — `+`, `promote`,
  `bitshift`, iteration, `zero/one`, `Bool`/`Int` conversions — many of which
  assume a concrete bits value and would either error deep in Base (bad message)
  or, worse, silently `convert`/clone. This is the P9 "**no catch-all**"
  hazard applied to inheritance.
- P9 "registers are numeric types" is a **dispatch/overload** statement, not a
  subtyping one. We honor it by defining exactly the operators §3.4/§6 scope to
  the generic path (`+`, `-`; comparison at M7). Untyped generic `f(x) = x + x + a`
  rides those overloads; a `g(x::Integer)` correctly **rejects** a `QInt` (the
  honest MethodError wall, identical to QBool's), pushing type-restricted code
  through `oracle` (M7). This is the PRD's own §3.1 mechanism.
- Consistency: M3 deferred QBool subtyping (D-A-1) for the same reason; QInt
  follows.

**Mixed promotion.** No `Base.promote_rule(QInt, Int)`, no `convert(QInt, ::Int)`
— implicit promotion of a classical `Int` into a quantum register would be a
surprise allocation. Mixed arithmetic is **explicit two-arg methods**
(`+(::QInt,::Integer)`, `+(::Integer,::QInt)`), mirroring how `false ⊻ b`
already spells classical→quantum promotion as a deliberate fresh allocation.

---

## 10. Strict-mode lost-binding detector (D10, completed here)

The scaffold is already in place: `ContextCore.parent` and `ContextCore.strict`,
plus the inert `_strict_check!(ctx, frame)` hook in `regions.jl`. M6 lights it up
because M6 is where **fresh-output ops first exist**.

**Data structure.** Widen `parent::Dict{WireID,WireID}` →
`parent::Dict{WireID,Vector{WireID}}` (child wire → its entangling source wires);
a `QInt` fresh output has W children, each with the source register's wires as
parents. (Field-type change to `ContextCore` — a core edit, in 3+1 scope.)

**When recorded — value-world ops only, and only when `strict`.** In
`+(::QInt,…)` / `-`, after building `s`, if `core.strict`:

```
if core.strict
    for w in s.wires, p in (x.wires..., (y isa QInt ? y.wires : ())...)
        push!(get!(core.parent, w, WireID[]), p)
    end
end
```

Action-world and view ops record **nothing** — they mutate in place, there is no
fresh child to lose. `add!`, `⊻=`, `x̂ += a` never populate `parent`.

**When checked — region exit** (`_strict_check!`, before the traces run):

```
function _strict_check!(ctx, frame)
    core = _core(ctx)
    (core.strict && !isempty(core.parent)) || return
    traced = Set(w for w in frame if haskey(core.wire_to_slot,w) && !(w in core.consumed))
    for (child, parents) in core.parent
        # child SURVIVES (live, not being traced) but a parent is TRACED ⇒ lost binding
        (haskey(core.wire_to_slot,child) && !(child in traced)) || continue
        any(p -> p in traced, parents) &&
            error("lost-binding (D10, strict): register wire $child survives but its " *
                  "entangling parent $(filter(p->p in traced,parents)) is being traced at " *
                  "region exit — you likely wrote `x += a` (rebinds x to the fresh sum and " *
                  "drops the old handle); the survivor is entangled with the traced register " *
                  "and its value decoheres. Use `add!(x,a)` (in-place) or `x̂ += a` (modulation).")
    end
end
```

Classified as a **classical programming error** (`error()`), never quantum
nagging — the default (`strict=false`) stays silent, honoring §3.9's doctrine.

**False-positive analysis (the deep part).**
- **Returning the fresh output is fine.** `s = x + a; return s` → `x` is live at
  exit (never lost) → `x ∉ traced` → no flag, even though `parent[s]=x`. The
  check keys on *parent ∈ traced*, and a live parent is never in `traced`. This
  is exactly "the check is on TRACED parents with SURVIVING children."
- **Both dropped** (`s=x+a` then neither used): `s ∈ traced` too → `s` is not a
  survivor → skipped. Useless work, but not the lost-binding bug (no survivor
  decoheres). Correctly no flag.
- **The real bug** `x = x + a`: Julia rebinds variable `x` to `s`; the old
  x-wires are owned+live+unconsumed → in `traced`; `parent[s_wire] = old_x_wire
  ∈ traced` and `s` survives → **flag**. ✔
- **Multi-parent** `s = x + y`, `x` lost but `y` returned: `x ∈ traced`, flag
  fires (any traced parent suffices) — correct, `s`'s value is corrupted.
- **Consumed parent** (`s = x + a; Int(x)`): `x ∈ consumed` ⇒ excluded from
  `traced` (the guard `!(w in core.consumed)`), so no flag — measuring `x` is a
  legitimate close, not a lost binding.

Cost: a `Dict` push per value-world op **only under `strict`**; zero on the
default path (the `isempty(core.parent)` short-circuit already guards it).

---

## 11. Misuse topology (every wrong program → S13 class + message)

| Wrong program | S13 class | Where caught | Message gist |
|---|---|---|---|
| `dual(x)[i]` | `ArgumentError` (define-to-throw) | `getindex(::DualView{<:QInt},i)` | "no wire-i of `dual(x)`: register dual is QFT on ℤ_{2^W}, not per-wire; use `dual(x[i])`" |
| `Int(x)` after `Bool(x[i])` | `error()` + identity | `Int(x)` partial-consumption scan | "register x partially consumed: wire i dead; measure remaining wires explicitly" |
| `x ⊻= x` | `error()` aliasing | `_check_wire_aliasing` (per-wire WireID collision) | "wire … appears more than once — register aliasing forbidden (§8.4)" |
| `x ⊻= x[i]` | `ArgumentError` | define-to-throw `xor(::QInt,::WireRef)` | "cannot ⊻ a whole register with one of its slices (width/aliasing); did you mean `x[i] ⊻= r`?" |
| `dual(x) += a` (unbound) | parse error | M0 lower-lint (D11) | "invalid assignment location" — never runtime; bind `x̂ = dual(x)` first |
| `x̂ * 2`, `x̂ & 1` (ring ops on view) | `MethodError` | no method (views ∉ P9) | honest wall (§3.3) |
| `x::QInt{4} ⊻= y::QInt{3}` | `ArgumentError` | define-to-throw `xor(::QInt{W},::QInt{V})` | "width mismatch: QInt{4} ⊻ QInt{3}; transversal ⊻ needs equal width" |
| `QInt{3}(-1)`, `QInt{3}(8)` | `DomainError` | `QInt{W}(n)` range guard | "n must be in 0:7 (ℤ_{2^3}); a literal names a point" |
| `add!(x::QInt{3}, 5)` on `|6⟩` | **not an error** | — | wraps → `|3⟩` (ℤ_{2^W}); documented + tested |
| `x[5]` on `QInt{4}` | `BoundsError` | `getindex` bounds guard | Base idiom |
| `not!(dual(x))` on QInt | `MethodError` | no method (ℤ_{2^W} modulation-by-1 undefined) | deferred; add if a use appears |
| `Int(x)` / `Bool(x[i])` under `when` | `error()` guardrail 1 | `_assert_no_control` | measurement-under-ctrl unrepresentable (§4.4) |
| `x == y`, `x == a` | see footgun ↓ | — | comparison is M7 (oracle) |

**The `==` footgun (flagged for the round).** Julia's `Base.:(==)` falls back to
`===` on structs, so `x == y` returns `false` *silently* (identity), and `x == a`
(QInt vs Int) is a `MethodError`. Value comparison is a reversible comparator =
oracle territory (M7). Options for M6: (i) leave `==`/`hash` at struct default
(collection-safe) and accept the `x == y ⇒ false` silent trap until M7; or
(ii) define a loud `Base.:(==)(::QInt,::QInt) = error("quantum comparison is a
reversible comparator (oracle, M7); …")` — but this breaks any internal `==` on
QInt (e.g. in a `Set`). I lean (i) + a WORKLOG note; the implementer/orchestrator
should rule. This is the one genuinely open method-table question I surface
rather than decide.

---

## 12. Namespace (§2 layering, mechanically enforced)

- **Export (surface):** `QInt`, `add!`, `sub!`, `superpose!`. `Int(x)`, `+`, `-`,
  `⊻`, `getindex`, `dual` are Base-method extensions on our own types — no new
  export (`dual`, `not!`, `when` already exported).
- **`public` (kernel/library, reachable as `Sturm.…`, not dumped into `using`):**
  `QFT`, `WireRef` (users get it from `x[i]` but never name the type — like
  `DualView`), `_adopt_qint` is internal (underscore).
- **Internal (underscored):** `_dual_transform(::QInt)`, `_emit!(::QFT)`,
  `_emit_modulation!`, `_msb_wires`, `_bit_wire`, `_wireid`/`_ctxof`, `Qubit1`.
- The M0 choke-point grep-lints stay honest: the only new controlled lowering is
  `ctrl(P(θ))` **inside** `_emit!(::QFT)` in `src/orkan/ad.jl` (allowed region),
  built through the public `ctrl` combinator — no new `_ctrl(`/`Ctrl(` call sites.

---

## 13. M6 acceptance gate (confirming what is owed)

Named law tests (`@testset`s named per PRD section), **no worked example**:

1. **Sign pin #1** — `add!(QInt{W}(0), 1)` then `Int == 1` (and `== W-bit wrap`
   on overflow: `add!(QInt{3}(6), 5) ⇒ Int == 3`).
2. **Pontryagin unit test (sign pin #2)** — `superpose!(x); x̂=dual(x); x̂+=a;
   Int(dual(x)) == a`, over several `(W,a)`.
3. **F²-vs-unwrap signature (normative)** — `dual(dual(x)) === x` **and** emits
   nothing (statevector bit-identical, fusion buffer empty — the M4 pattern);
   *separately* `denoted_matrix(QFT(W,false)) ∘ itself ≈ denoted_matrix(parity
   Perm)` (integer negation `x ↦ −x mod 2^W`) — proving the process F²=parity
   while the view unwraps.
4. **QFT is the DFT** — `denoted_matrix(QFT(W,false)) ≈` analytic DFT (matrix
   cross-check, W≤4).
5. **Two worlds** — `s = x + a` leaves `x` live (`Int(x)` still valid after,
   under a fresh region); `x += a` under `strict=true` throws the D10 error;
   under default is silent and traces at exit.
6. **Strict-mode false-positive guard** — `s = x + a; return s` does **not** flag
   (parent live); `s = x + a; Int(x)` does not flag (parent consumed).
7. **Partial consumption** — `Bool(x[i]); Int(x)` throws with identity.
8. **Aliasing** — `x ⊻= x` and `x ⊻= x[i]` throw at the DSL level.
9. **Per-wire dual mechanism** — `Bool(dual(x[i]))` runs (the BV readout
   primitive; BV *itself* is M7 §7.5).
10. **Wrap / DomainError / BoundsError** — the §11 table rows.

`superpose!` lands here **only** because tests 2/3 need it (library
materialization `H^⊗W` — a real op, not a view). DJ (§7.4), BV (§7.5), and
`oracle` are **M7**; teleport was closed in M4/M5. No Choi worked-example gate is
owed at M6 — the milestone is pins + traps.

---

## 14. Deviations from landed code / the plan (flagged for the reviewer)

1. **Edits landed M3/M4 files** to widen single-wire ops to `Qubit1` (actions.jl,
   casts.jl, views.jl, qbool.jl `_here`). Justified by principle 13; the
   alternative (WireRef-delegates-to-helpers) avoids the edit at the cost of
   duplication. Round should ratify which.
2. **`ContextCore.parent` type change** `Dict{WireID,WireID}` →
   `Dict{WireID,Vector{WireID}}` (multi-parent for `x + y`). Scaffold was
   single-parent; M6 needs the vector. Small, additive.
3. **`QFT` includes bit-reversal swaps** (matrix-honest node) rather than folding
   `R_n` into the endianness (Chen–Stoudenmire–White: `R_n` is a free reindex).
   Trades ⌊W/2⌋ cheap swaps for a testable `denoted_matrix`. The fold is an M8
   optimization; noted.
4. **No `ctrl(::QFT)`** at M6 (no controlled QFT in surface). MethodError until
   M8/phase-estimation — the no-catch-all discipline, made explicit.
5. **`==`/comparison left undefined** (M7 oracle territory); the `x==y ⇒ false`
   struct-default footgun is surfaced, not silently resolved (§11).
6. **`add!` F/F† bypass `_act!`** (uncontrolled), only `M_a` is controlled —
   realizing the §4.2 reassociation at M6 without the M8 pass. This mirrors M5's
   `when(dual(q))` sandwich exactly; if the reviewer prefers *no* reassociation
   before M8, the fallback is to route F/F† through `_act!` too (correct but
   controls the whole QFT — expensive, and it would make `when`-add emit a
   controlled QFT, which needs `ctrl(::QFT)` after all). I recommend keeping the
   bypass — it is strictly the cleaner physics and reuses a landed pattern.

## 15. File plan

- `src/types/qint.jl` — `QInt{W}`, `WireRef`, `_msb_wires`/`_bit_wire`,
  `_adopt_qint`, `Qubit1` + accessors, `getindex` (+ bounds), prep/`Int` casts,
  partial-consumption guard.
- `src/kernel/qft.jl` (or fold into `views.jl`) — `QFT` node, `adjoint`,
  `denoted_matrix`; `_dual_transform(::QInt)`, `_dual_transform(::WireRef)`.
- `src/orkan/ad.jl` (edit) — `_emit!(ctx, ::QFT, qs)` (H+CP+swap ladder via
  `ctrl(P)`); the one new controlled-lowering site, inside the allowed region.
- `src/surface/arithmetic.jl` — the two-world method table (§2): value-world
  `+`/`-`, action-world `add!`/`sub!`/`⊻`/`not!`, view-world `+=`/`Int(dual)`,
  `_emit_modulation!`, `superpose!`, the define-to-throw misuse methods.
- `src/context/regions.jl` (edit) — light up `_strict_check!`; `abstract.jl`
  edit — widen `parent`.
- widen `src/surface/actions.jl`, `src/surface/casts.jl`, `src/kernel/views.jl`
  signatures to `Qubit1`.
- `test/test_m6_qint.jl` — the §13 gate.
