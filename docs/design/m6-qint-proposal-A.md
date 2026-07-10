# M6 Proposal A — QInt{W}, wire handles (D2), two arithmetic worlds (D12), Pontryagin sign pins

**Lens: group theory and sign conventions first.** Everything below is
derived from the two intertwining relations on ℤ_N (N = 2^W), *not* quarried
from v0.1's `add_qft!`. The single source relations, proven once in §0, fix
every sign in §4 and §6.

---

## 0. The group-theory kernel (all signs derive from here)

Convention (matches the kernel): **wire 1 = MSB**, so for a `QInt{W}` value
`n = Σ_{j=1}^{W} n_j · 2^{W−j}` — wire `j` carries bit-weight `2^{W−j}`
(`abstract.jl` endianness pin, `perm.jl` "wire 1 = MSB", `Ctrl` "controls are
leading/MSB wires"). Let `ω = e^{i2π/N}`, `N = 2^W`.

Define the two operator families on ℤ_N:

- **Translation** `T_a|x⟩ = |x+a mod N⟩` — this is `add!`.
- **Modulation** `D_b|x⟩ = ω^{bx}|x⟩` — diagonal phase kick.
- **Fourier** `F|x⟩ = N^{−1/2} Σ_y ω^{xy}|y⟩` (the DFT of CSW Eq 1). `F` is
  symmetric; `F† |x⟩ = N^{−1/2} Σ_y ω^{−xy}|y⟩`.

**Lemma 0.1 (the master intertwiner).** `D_a F = F T_a`, hence

```
      F† D_a F = T_a                    (I)   ← addition IS a Fourier-conjugated modulation
```

*Proof.* `D_a F|x⟩ = N^{−1/2} Σ_y ω^{ay}ω^{xy}|y⟩ = N^{−1/2} Σ_y ω^{(x+a)y}|y⟩
= F|x+a⟩ = F T_a|x⟩.* ∎

**Lemma 0.2 (the dual/twin).**

```
      F† T_a F = D_{−a}                 (II)  ← translating the DUAL label is a modulation by −a
```

*Proof.* `T_a F|x⟩ = N^{−1/2} Σ_y ω^{xy}|y+a⟩ = N^{−1/2} Σ_z ω^{x(z−a)}|z⟩
= ω^{−xa} F|x⟩`, so `F† T_a F|x⟩ = ω^{−xa}|x⟩ = D_{−a}|x⟩.* ∎

**Lemma 0.3 (separability of `D_b`).** `D_b|x⟩ = ω^{bx}|x⟩ =
Π_{j=1}^{W} exp(i2π · b · x_j / 2^{j})` (substitute `x = Σ x_j 2^{W−j}`,
`ω^{b·x_j·2^{W−j}} = exp(i2π b x_j/2^{j})`). So **`D_b` is W *uncontrolled*
single-wire phase gates**: wire `j` gets `P(2π b / 2^j)`, `P(θ)=diag(1,e^{iθ})`.
No Fourier, no entanglement — this is why modulation is cheap.

**Lemma 0.4 (F² = parity, F⁴ = 1).** `F²|x⟩ = |−x mod N⟩`.
*Proof.* `F²|x⟩ = N^{−1} Σ_{y,z} ω^{xy}ω^{yz}|z⟩ = Σ_z δ_{x+z≡0}|z⟩ =
|−x⟩`. ∎ (This is the normative M6 integer-negation signature, §6.3.)

These four facts pin **both** sign directions and settle the
addition-vs-modulation split exactly:

| Surface op | Kernel value | Sign | Effect |
|---|---|---|---|
| `add!(x, a)` | `F† ∘ D_{+a} ∘ F` (= `T_a`, Lemma 0.1) | **+a** | `Int(x)` ← `x+a` |
| `x̂ += a` (`x̂=dual(x)`) | `D_{−a}` directly (Lemma 0.2, 0.3) | **−a** | `Int(x)` unchanged; `Int(dual(x))` ← `+a` |

The minus sign on the modulation is the whole content of r6/B2: `x̂ += a`
lowers to `_conj(F, T_a) = F† T_a F = D_{−a}`, which by Lemma 0.3 is *bare
phases* — the implementation emits `D_{−a}` directly and NEVER builds a Fourier
sandwich for the view op-assign. Addition (`add!`) is the sandwich.

---

## 1. `QInt{W}` type

### 1.1 Struct (the M3 handle pattern, W the only type parameter)

```julia
struct QInt{W} <: AbstractRegister          # W in the type (CLAUDE.md conv 5)
    ctx::AbstractContext                     # OWNING context (§4.3), abstract field — deliberate (qbool.jl note)
    wires::NTuple{W,WireID}                  # wire 1 = MSB (endianness pin)
end
```

Mirrors `QBool = (ctx, wire)` exactly, generalized to a `W`-tuple. `W` is the
*only* type parameter (§3.1); the context is an abstract field (never a second
parameter — the qbool.jl "no `QInt{W,C}` metastasis" rule). `wires[1]` is the
MSB, `wires[W]` the LSB, consistent with `Int(x) = Σ x_j 2^{W−j}` and with the
kernel's MSB-leading `Ctrl`/`Perm`/`Tensor` conventions, so a value's denoted
matrix embeds through the same slot map with no reversal.

`AbstractRegister` is a new (empty) supertype so future `QMod{d}` and the
value-world generic code can dispatch on "a multi-wire register handle"; QBool
stays `AbstractQubit` (§2).

### 1.2 Preparation cast `QInt{W}(n::Integer)`

```julia
function QInt{W}(n::Integer) where {W}
    (0 ≤ n < (1 << W)) || throw(DomainError(n,
        "QInt{$W}(n): n must be in 0:$(1<<W)-1 (got $n)"))   # range check → DomainError
    ctx = current_context()
    ws = ntuple(_ -> allocate!(ctx), W)                      # W fresh |0⟩, region-owned (§3.9)
    @inbounds for j in 1:W
        ((n >> (W - j)) & 1) == 1 && apply!(ctx, X, (ws[j],))  # exact kernel X per set bit (wire j = bit 2^{W-j})
    end
    return QInt{W}(ctx, ws)
end
```

- **Range check → `DomainError`** (Base convention for domain violations; S13),
  named `n` in the message, before any allocation.
- **Exact X per set bit** — the kernel `X` (constants.jl), never `Ry(π)` (the
  §3.4/audit-8.3 latent-phase discipline QBool already follows).
- Allocation is initialization (§3.9): W fresh |0⟩ wires, each registered in the
  enclosing region's owned set by `allocate!` — traced at region exit unless
  consumed/returned.

### 1.3 Measurement cast `Int(x::QInt{W})`

```julia
function Int(x::QInt{W}) where {W}
    ctx = x.ctx
    ctx === current_context() || throw(ArgumentError("Int(x): register escaped its context …"))
    _assert_no_control(ctx, "measurement cast Int(x)")       # guardrail 1 (§3.5), before backaction
    # PARTIAL-CONSUMPTION CHECK (D2, single-sourced): every wire must still be live.
    for (j, w) in enumerate(x.wires)
        is_consumed(ctx, w) && error(
            "register partially consumed: wire $j of this QInt is dead " *
            "(a slice `x[$j]` was measured). Measure the remaining wires " *
            "explicitly, or don't slice-consume before Int(x) (D2).")
    end
    n = 0
    @inbounds for j in 1:W
        _measure_wire!(ctx, x.wires[j]) && (n |= (1 << (W - j)))   # single-sourced consumption per wire
        mark_consumed!(ctx, x.wires[j])
    end
    return n
end
```

- **Single-sourced consumption** (§4.5): `Int(x)` consumes *all* W wires via the
  same `_measure_wire!`/`mark_consumed!` path `Bool(q)` uses. The handle dies.
- **Partial consumption is a loud error** (D2, r6): if a slice `x[j]` was already
  consumed by `Bool(x[j])`, the set-membership check fires *before* any
  measurement — a `set-intersection` on the single-sourced consumed set, never a
  silent reinterpretation. This is the §8.5 regression closed by construction:
  the consumed set is the context's, so `Bool(x[3])` marking wire 3's `WireID`
  makes this check fail with no drifting per-object flag.
- **Assembly** MSB-first: wire `j` contributes bit `2^{W−j}`.
- On DM, `_measure_wire!` throws (scalar = trajectory, §3.8) — same as QBool;
  channel statements go through the Choi harness.

---

## 2. `x[i]` wire handles (D2)

### 2.1 The abstract-supertype refactor (SubArray-vs-Array, minimal churn)

D2 demands `x[i]` be a *distinguishable wire-handle wrapper — NOT a bare QBool*
(so it carries a dispatchable aliasing hook and a borrow marker). The idiomatic,
lowest-churn realization is an abstract single-wire supertype both handles share:

```julia
abstract type AbstractQubit end          # single-wire quantum handle: has `.ctx`, `.wire`
struct QBool <: AbstractQubit  … end     # M3, unchanged fields (add the supertype)
struct QIntSlice{W} <: AbstractQubit     # x[i]: a BORROWED handle on the parent's wire i
    ctx::AbstractContext
    wire::WireID                          # === parent.wires[i]  (the SAME wire — no clone)
    owner::WireID                         # parent identity (its wires[1]) — for messages + escape check
    i::Int                                # slice index — for messages
end
```

Then **generalize the M3/M4 method signatures from `::QBool` to
`::AbstractQubit`**: `_here`, `not!`, the `Base.xor` action family, `Base.Bool`
(comp-basis cast), `dual`, `_dual_transform` (= `H`), `_parent_wire`, and `when`.
Every one of these bodies already touches only `q.ctx` / `q.wire`, so the
generalization is a signature widening with *no logic change* — exactly Base's
`AbstractArray` reuse. `QIntSlice` inherits all of construct 3 + the casts + the
dual + `when` for free.

`x[i]` itself:

```julia
function Base.getindex(x::QInt{W}, i::Integer) where {W}
    1 ≤ i ≤ W || throw(BoundsError(x, i))
    return QIntSlice{W}(x.ctx, x.wires[i], x.wires[1], Int(i))   # BORROW: no allocate!, no owned-set entry
end
```

- **Borrow, not own** — `x[i]` never calls `allocate!`, so the slice registers
  no owned wire; its death traces nothing (§3.9 "views/slices borrow"). The wire
  is `x`'s; only `x` (or a slice consuming it) traces it.
- **No fresh consumed flags** (§8.5): the slice carries no `consumed` bit; the
  *only* consumed set is the context's, keyed by the shared `WireID`.
- **Aliasing hook**: `_parent_wire(s::QIntSlice) = s.wire` — so `apply!`'s
  `_check_wire_aliasing` and `when`'s guardrail 2 see through the slice to the
  real wire (e.g. `x[1] ⊻= x[1]` fires; `when(x[1]) do not!(x[1]) end` is a
  guardrail-2 error) with zero new alias logic.

### 2.2 Interactions

- **`Bool(x[i])`** — consumes ONE wire (partial consumption). Routes through the
  generalized `Bool(::AbstractQubit)` → `_measure_wire!` + `mark_consumed!` on
  the shared `WireID`. After it, `Int(x)` errors loudly (§1.3). Used in BV §7.5.
- **`not!(x[i])`, `x[i] ⊻= r`, `q ⊻= x[i]`** — legal actions on the slice
  (generalized action family), controllable inside `when`.
- **`when(x[i]) do … end`** — coherent control off one wire (the Shor idiom
  `when(k[j])`, §7.7). `when(::AbstractQubit)` pushes `s.wire` as the control.
- **`dual(x[i])`** — legal: the **ℤ₂** dual of the slice (single wire, self-dual,
  `_dual_transform(::QIntSlice)=H`). Routes straight through the existing
  `DualView` machinery (`dual(s)=DualView(s)`); `Bool(dual(x[i]))` is the
  conjugate-basis wire read of BV §7.5. This is a *provably different* object
  from "wire `i` of `dual(x)`" (see below) — grounded in CSW: the QInt dual
  `F_W` is not a tensor product across any cut, so no per-wire local exists.

### 2.3 `dual(x)[i]` — define-and-throw (D2 ruling (i))

```julia
Base.getindex(v::DualView{<:QInt}, i::Integer) = throw(ArgumentError(
    "dual(x)[i] is undefined: dual(x) for a QInt{W} is the Fourier view on " *
    "ℤ_{2^W} (the QFT), which is NOT a tensor product across any register cut " *
    "(Chen–Stoudenmire–White, arXiv:2210.08468, Thm 1/Cor 1) — so there is no " *
    "local `wire i` of it. Did you mean `dual(x[i])` (the ℤ₂ dual of one wire)?"))
```

A **defined** method that throws a descriptive `ArgumentError` (never a bare
`MethodError`) — the `Symmetric`/`UpperTriangular` `setindex!`-into-forbidden-
entry idiom (D2). `hasmethod(getindex, (DualView{QInt{3}}, Int))` stays `true`;
the message states the group-mismatch reason, cites CSW, and suggests
`dual(x[i])`. No custom exception type (S13 / D2 YAGNI). Note `dual(x)`
construction itself never throws — rejection lives at the point of use.

---

## 3. The register dual `dual(x::QInt{W})` — Fourier on ℤ_{2^W}

### 3.1 The `QFT` kernel process value (the F_G trait; W dynamic)

`_dual_transform(::QInt{W})` must return a definite process value for **F**. `W`
is a runtime width, so — mirroring `Perm` (width in a field, not a type param) —
add one kernel type:

```julia
struct QFT <: ProcessValue          # the DFT F_W on ℤ_{2^W}; kernel `public`, never surface
    W::Int
    inv::Bool                        # false = F, true = F† (adjoint flips the flag — no F applied)
end
nwires(f::QFT) = f.W
Base.adjoint(f::QFT) = QFT(f.W, !f.inv)
_dual_transform(::QInt{W}) where {W} = QFT(W, false)     # forward DFT; direction pinned by §6.2
```

**`denoted_matrix(::QFT)` = the analytic DFT** (Lemma 0 convention: `F[y,x] =
N^{−1/2} ω^{xy}`, conjugated when `inv`). THIS is the semantics; the emitted
circuit's obligation is to agree with it — one cross-check test localizes any
convention slip (the U2-T0 discipline).

**`_emit!(ctx, f::QFT, qs)`** — the standard exact H + controlled-phase ladder
**plus the bit-reversal**, so the *emitted* unitary equals the *denoted* DFT
(CSW Eq 3, `F_n = R_n Q_n`):

```
for j in 1:W                                  # wire j = MSB..LSB
    _emit_h!(ctx, qs[j])
    for k in j+1:W
        apply CP(±2π / 2^{k-j+1})  on (qs[k], qs[j])   # controlled phase, sign by f.inv
    end
end
# bit-reversal R_W: swap qs[j] ↔ qs[W+1-j]  (orkan_swap!; a pure Perm/reindex, CSW: free)
```

The controlled phase `CP(θ)` is built through the **existing** choke point:
`CP(θ) = ctrl(P(θ))` with `P(θ) = gphase(θ/2) ∘ Rz(θ)` (a `U2`; denotes
`diag(1,e^{iθ})`). `ctrl(P(θ))` → `Ctrl{U2}` → `ad.jl`'s `_apply_controlled_u2!`
(ABC skeleton on target + `_emit_p!(control, θ/2)` — Barenco Lemma 5.2); for
`θ=π`, `P(π)=Z` → native `cz`. **No new controlled-lowering code** — QFT rides
`ctrl`/`ad.jl` verbatim, keeping the choke-point lint honest.

*CSW licenses treating this as lightweight:* the core `Q_n` has constant
operator entanglement / a χ≈8 MPO, and `R_n` is a pure `Perm` — so the basis
change is a cheap addressing mode, not a heavyweight circuit (the "small core
entanglement" reading; NOT a classical-simulability claim).

Design note (implementer's pick): the bit-reversal can be a real `orkan_swap!`
network (M6, correctness-first) OR absorbed into a wire-tuple relabel (M8
optimization). M6 emits swaps and stays exact; the denotation includes `R_W`
either way.

### 3.2 The `DualView` for QInt (M4 parent pattern, reused)

`dual(x::QInt{W}) = DualView(x)` — the **same** mutable `DualView{H}` wrapper as
M4 (identity semantics: `dual(x) !== dual(x)`, `dual(dual(x)) === x` by the
`dual(v::DualView)=v.parent` unwrap). `_parent_wire`/consumed-set bookkeeping
key on the parent wires. **No F is ever applied by `dual`** — it unwraps
structurally; F is applied only when a *cast* / *op-assign* / *`when`* forces it
(§3.3 normative, and the M4 file header's whole point). The DualView carries a
`QInt`, so the reused machinery Just Works; the QInt-specific behavior is only
in `_dual_transform`, the `getindex`-throw (§2.3), and the bound-view op-assigns
(§4).

---

## 4. The two arithmetic worlds (D12)

### 4.1 ACTION world (registered in-place, returns self)

**`add!(x, a::Integer)` — classical addend (Draper, derived).**
By Lemma 0.1, `add!(x,a) = F† ∘ D_{+a} ∘ F`, and by Lemma 0.3 `D_{+a}` is W
uncontrolled phase gates. The lowering is emitted in three passes, and the
control-awareness falls out of the §4.2 reassociation law for free:

```julia
function add!(x::QInt{W}, a::Integer) where {W}
    ctx = _here(x); a = mod(a, 1 << W)
    F = QFT(W, false)
    apply!(ctx, F, x.wires)                                  # F : UNCONTROLLED (acts only on x's wires)
    @inbounds for j in 1:W
        _act!(ctx, P(2π * a / (1 << j)), (x.wires[j],))      # D_a : wire j gets angle 2πa/2^j — CONTROLLED if under `when`
    end
    apply!(ctx, adjoint(F), x.wires)                         # F† : UNCONTROLLED
    return x                                                 # in-place, same handle
end
sub!(x, a) = add!(x, -a)
```

- **Why F/F† are `apply!` (uncontrolled) but `D_a` is `_act!`:** the §4.2 kernel
  law `(1⊗V)∘ctrl(W)∘(1⊗V†) = ctrl(V∘W∘V†)` with `V=F` acting only on `x`'s
  wires (never the `when` control). So under a depth-`k` control stack this emits
  `F† ctrl^k(D_a) F = ctrl^k(T_a)` — *exactly* `ctrl^k(add!)`, with F/F†
  outside the control. Uncontrolled at empty stack (plain `T_a`). This is the
  hand-applied `within(F)` reassociation, identical in spirit to how
  `when(dual(q))` already applies its basis change uncontrolled (when.jl,
  Delorme Eq 16). **Draper's "100 lines" die inside `D_a`'s W-gate loop** (the
  kernel), where "no gates in surface code" always wanted them.
- **Return-self discipline** (the action-family whole game): `add!` returns `x`;
  no rebind, no fresh handle. Registered in-place exception (Julia conv 2, D12).

**`add!(y::QInt{W}, x::QInt{W})` — quantum addend.**
`|x⟩|y⟩ → |x⟩|y+x⟩ = F†_y ∘ D^{(y)}_{+x} ∘ F_y`, where `D^{(y)}_x|y⟩ = ω^{xy}|y⟩`.
By the same substitution as Lemma 0.3, `D^{(y)}_x = Π_{j,k} CP(2π·2^{W−k−j})`
between `x`-wire `k` (control) and `y`-wire `j` (target) — the triangular
cross-register phase network, nontrivial only when `k+j>W`:

```julia
function add!(y::QInt{W}, x::QInt{W}) where {W}
    ctx = _here(y); _here(x)
    F = QFT(W, false)
    apply!(ctx, F, y.wires)                                        # F on y, UNCONTROLLED
    @inbounds for j in 1:W, k in 1:W
        e = W - k - j
        e ≥ 0 && continue                                         # phase ≡ 1 (multiple of 2π)
        _act!(ctx, ctrl(P(2π * 2.0^e)), (x.wires[k], y.wires[j]))  # cross CP; +sign for addition
    end
    apply!(ctx, adjoint(F), y.wires)
    return y
end
```

(General mismatched widths: extend/truncate `x` against `y`'s modulus; M6 ships
equal-width, which is what Shor/BV/DJ need. `_act!` still controls only the
cross-phases; F/F† ride reassociation.)

**`x ⊻= y` — transversal (W parallel CNOTs).** `Base.xor(x::QInt{W},
y::QInt{W})`: `for j; _act!(ctx, ctrl(X), (y.wires[j], x.wires[j])); return x`.
In-place bijection `(ℤ₂)^W` translation-by-`y`; returns `x` (the registered
rebind no-op). This is the W=1-per-wire fan-out of the QBool `a ⊻= b` and is the
`(ℤ₂)^W` group, **not** ℤ_{2^W} — deliberately the per-wire duals' world.

**Modulation through views (the −a sign, r6/B2 — Lemmas 0.2/0.3).**
`x̂ += a` emits `D_{−a}` **directly** (bare phases, no Fourier):

```julia
function Base.:+(v::DualView{<:QInt{W}}, a::Integer) where {W}   # x̂ += a  ⇒  x̂ = x̂ + a
    x = v.parent; ctx = _here(x)
    @inbounds for j in 1:W
        _act!(ctx, P(-2π * a / (1 << j)), (x.wires[j],))          # D_{−a}: NEGATIVE angle (Lemma 0.2)
    end
    return v                                                      # MUTATE-AND-RETURN-SELF (registered, D11)
end
```

- **`Base.:+` on the view mutates-and-returns-self**: Julia rewrites `x̂ += a`
  to `x̂ = x̂ + a`, so `Base.:+(v::DualView{<:QInt}, a)` must apply `D_{−a}` in
  place and return `v` (`x̂ = v` is then a no-op rebind). This is the registered
  D11 exception, adopted knowing julialang#249/#3217 — documented in the
  docstring (no-cloning ⇒ no caller value clobbered; scoped to the action
  family). `dual(x) += a` as a bare call-LHS remains a *parse* error (D11), caught
  by the M0 lower-lint; the idiom is bind-then-op-assign.
- **The −a is the theorem**, not a convention: `x̂ += a = _conj(F, T_a) =
  F† T_a F = D_{−a}` (Lemma 0.2). An implementation with `D_{+a}` here is wrong
  and the signature is `Int(dual(x))` shifting by `−a` (the §6.2 pin catches it).

**`ŷ += x` — controlled modulation** (`Base.:+(v::DualView{<:QInt}, x::QInt)`):
`D^{(y)}_{−x} = Π CP(−2π·2^{W−k−j})` — the same triangular network as the quantum
adder but negated and *without* the F_y sandwich (it is pure cross-phase
`ω^{−xy}`, the kernel inside phase estimation / QFT-multiply). Note the clean
relation for the implementer: `add!(y, x) = F†_y ∘ adjoint(ŷ += x network) ∘ F_y`.

### 4.2 VALUE world (fresh outputs; inputs stay live)

Ring ops allocate a fresh output and copy-then-`add!`; inputs remain live
(reversible dataflow, P9):

```julia
function Base.:+(x::QInt{W}, a::Integer) where {W}          # s = x + a
    s = QInt{W}(0)                                          # fresh |0…0⟩, region-owned
    _copy_into!(s, x)                                       # s ← x  (W transversal CNOTs: s_j ⊻= x_j)
    add!(s, a)                                              # s ← x + a
    _record_parent!(s, x)                                   # strict-mode edge (§5)
    return s                                                # x stays LIVE (and entangled: reversible dataflow)
end
Base.:+(x::QInt{W}, y::QInt{W}) where {W} = (s = _copy(x); add!(s, y); _record_parent!(s, x); _record_parent!(s, y); s)
```

- `_copy_into!(s,x)` is the comp-basis CNOT fan-out `Σ α_x|x⟩ → Σ α_x|x⟩|x⟩` —
  not cloning; it is the reversible embedding `|x⟩|0⟩ → |x⟩|x+a⟩` that keeps `x`
  recoverable. P8 promotion (`a + x`, mixed `Int`/`QInt`) forwards to these.
- **NO in-place `+` on a bare register.** `x += a` (bare `x::QInt`) hits *this*
  value-world `+`, so Julia rebinds `x` to the fresh `s`; the **old** register
  becomes an unreferenced owned local — traced at region exit, and (if superposed)
  already entangled with the survivor, so the sum decoheres. Legal Julia, silent
  by default, and the §5 strict detector flags exactly it. Docs teach `add!(x,a)`
  (in-place) or `x̂ += a` (modulation) instead.
- Comparison operators (`<`, `==` between registers) are **deferred to M7**
  (comparator = `oracle` territory; plan §M6 "comparison deferred to M7").

---

## 5. Strict-mode lost-binding detector (completes the M2 scaffold)

**Signature (D10/§3.9):** *at region exit, a traced register that is an
entangling-op parent of a surviving register.* One mechanism catches the
`x += a` rebind trap, the generic-`f` fold trap, and lost handles — reported as
a **classical programming error**, never quantum nagging. Default off.

**Data structure** (the M2 hooks, now populated):

- `core.parent::Dict{WireID,WireID}` — child-wire → one entangling-parent-wire
  edge. Written *only* by fresh-output value-world ops via
  `_record_parent!(core, child_wire, parent_wire)` (per corresponding wire pair
  in `+`, and the M4 `false ⊻ b` gets a `_record_parent!(f.wire, r.wire)` added).
- `core.strict::Bool` — the flag, plumbed through
  `eager(cap; strict=true)` / `density(...; strict=true)` (already in the
  `ContextCore` constructor and the resource forms).
- **Escape set (new, small plumbing):** `region()`/`@context`/`eager`/`density`
  capture their block's **return value**; if it is a register/slice/QInt handle,
  its wires are the *escaped* set for that region's exit — wires that outlive the
  region (survivors) and must not be treated as "traced".

**The check** (`_strict_check!(ctx, frame)`, run before the trace loop):

```julia
function _strict_check!(ctx, frame::Vector{WireID})
    core = _core(ctx)
    (core.strict && !isempty(core.parent)) || return nothing
    tracing = Set(w for w in frame if haskey(core.wire_to_slot, w) && !(w in core.consumed) && !(w in escaped))
    for (child, par) in core.parent
        (par in tracing) || continue                 # the PARENT is about to be traced …
        survives = !(child in frame) || (child in escaped)   # … while the CHILD outlives the region
        survives && !(child in core.consumed) && _lost_binding_error(par, child)
    end
    return nothing
end
```

`_lost_binding_error` names both wires and prescribes the fix:

```
"lost binding: register <par> is being traced at region exit, but a fresh
 output <child> derived from it by a value-world ring op (`x + a` / `x + y`)
 survives and is entangled with it — the sum has decohered. You likely wrote
 `x = x + a`, which rebinds `x` to the fresh sum and drops the original. Use
 `add!(x, a)` for in-place addition, or keep BOTH handles live."
```

This is a **classical** error (a dropped Julia binding), fail-loud only under
strict; the silent-trace doctrine (§3.9) is untouched by default. It catches:
(a) `x = x + a` returned from a `region()`/function-with-region (child escaped,
parent traced); (b) the generic-`f` fold `x[1] ⊻ x[2] ⊻ …` when its
intermediates are value-world fresh outputs left entangled at exit; (c) any lost
handle that fathered a survivor.

---

## 6. The Pontryagin sign pins (named tests)

All in a `@testset "M6 Pontryagin sign pins (§3.3)"`, Eager unless noted;
statistical ones N≥1000 and assert the *exact* integer every shot (these are
deterministic outcomes, no tolerance on the value).

### 6.1 Translation direction — `add!(x,1)` on |0⟩ ⇒ `Int(x)==1`
`eager` → `x=QInt{W}(0); add!(x,1); @test Int(x)==1` (and general `add!(x,a)` on
`|0⟩` ⇒ `a`, and on `|n⟩` ⇒ `(n+a) mod 2^W`, all W∈2:4). Proof: §0, `T_a|0⟩=|a⟩`.
This pins `add! = F†D_{+a}F` (a `+a`, not `2^W−a`).

### 6.2 Modulation direction — `superpose!; x̂ += a; Int(dual(x)) == a`
```
x = QInt{W}(0); superpose!(x); x̂ = dual(x); x̂ += a; @test Int(dual(x)) == a
```
Proof: §0. `superpose!` gives `F|0⟩` (Int(dual)=0), `x̂+=a` applies `D_{−a}`,
which by Lemma 0.2 shifts the dual outcome to `0+a=a`. **This is the r6/B2
discriminator**: with the wrong `D_{+a}` sign it reads `−a mod 2^W`.
Companion: **modulation leaves `Int(x)` unchanged** — `x=QInt{W}(n); x̂=dual(x);
x̂ += a; @test Int(x)==n` (`D_{−a}|n⟩` is a global phase on a basis state).

### 6.3 F² = parity as a process vs views-unwrap (THE integer-negation signature)
Two halves that MUST disagree — the whole test's discriminating power:
```
# (a) the VIEW unwraps — NO op emitted, Int unchanged:
x = QInt{W}(n); @test dual(dual(x)) === x;  @test Int(x) == n
# (b) the PROCESS F applied twice negates (kernel test tooling, like choi.jl):
x = QInt{W}(n)
apply!(ctx, QFT(W,false), x.wires); apply!(ctx, QFT(W,false), x.wires)
@test Int(x) == mod(-n, 1 << W)            # F² = parity (Lemma 0.4)
```
Proof: §0 Lemma 0.4. If `dual` were (wrongly) lowered by *applying* F, then
`dual(dual(x))` in half (a) would run F² and `Int(x)` would read `mod(-n,2^W)` —
the exact bug §3.3 / JuliaLang#20978 names. Half (a) uses the *view* (structural
unwrap, `===`), half (b) uses the *process* `QFT` value through `apply!`; they
are genuinely different code paths and the test asserts they diverge.

### 6.4 Value world leaves inputs live
`x=QInt{W}(n); s = x + a; @test Int(s)==(n+a)%2^W; @test Int(x)==n` (basis-state
`|n⟩` ⇒ `x`,`s` are product `|n⟩|n+a⟩`, both independently measurable — `x`
stayed live and consumable).

### 6.5 `x += a` rebind — strict flags, default silent
`eager(cap; strict=true) do; x=QInt{W}(n); s = (x += a); return s end` ⇒
`@test_throws` lost-binding error (parent `x` traced, child `s` escaped). And
`eager(cap; strict=false)` (default) ⇒ no throw, silent (the doctrine).

---

## 7. Choi/statistical test plan + namespace

### 7.1 Channel-level (exact) tests
- **`add!(x,a)` is EXACTLY `T_a`** — a permutation channel. For W∈2:4, on every
  basis input `|n⟩`, apply `add!(·,a)` and assert the statevector is `e_{(n+a) mod 2^W}`
  (permutation exactness — no tolerance beyond U2 float atol). Equivalently, the
  strongest single check: `@test denoted_matrix(QFT-sandwich value) ≈
  denoted_matrix(Perm of T_a)` built in-test (like `perm.jl`'s permutation
  vector) — one failing test localizes any Draper convention slip.
- **`QFT` emission ≡ denotation** — `@test` the emitted circuit's action on each
  basis state matches `denoted_matrix(QFT(W,false))` (the analytic DFT), W∈2:4.
  This is the QFT convention anchor (U2-T0 discipline) — bit-reversal included.
- **`x ⊻= y` transversal** — Choi/basis check that it is the `(ℤ₂)^W` translation
  (per-wire CNOTs), NOT ℤ_{2^W} addition (guards the D2 two-groups distinction).
- **Quantum-addend `add!(y,x)`** — basis-state sweep `|m⟩|n⟩ → |m⟩|(n+m) mod 2^W⟩`,
  W∈2:3.
- **Choi harness extension:** generalize `choi(f, nin; …)` to accept a `W`-wire
  in/out channel (or add a `choi_reg(f, W)` that Bell-pairs W system+W ref wires
  and reduces over 2W kept slots) — needed for a channel-level `add!` Choi; the
  30-qubit cap covers W≤7 channels (2W in + scratch). Basis-sweep exactness
  above is the primary gate; Choi is the coherence backstop for `add!` under a
  Z-sensitive probe.

### 7.2 Statistical / integration
- Pontryagin pins §6.1–6.4 as N≥1000 shot-exact assertions.
- **BV §7.5 forward-looking hook (lands M7):** `Bool(dual(x[i]))` per-wire vs the
  wrong `Int(dual(x))` register-dual readout — the D2 copy-paste bug pinned as a
  negative test. M6 lands the *vocabulary* (`x[i]`, `dual(x[i])`, `Int(dual(x))`);
  the oracle is M7.

### 7.3 Namespace (CLAUDE.md conv 8; §2 layer table)
- **`export`** (surface): `QInt`, `add!`, `sub!`, `superpose!`. (`Int`, `+`, `⊻`,
  `getindex` are `Base` method extensions on our types — no new name; `dual`,
  `when`, `not!` already exported.)
- **`public`** (kernel/library): `QFT`, `QIntSlice`, `AbstractQubit`,
  `AbstractRegister`. `P` (the phase-gate constant builder `P(θ)`) joins the
  `public` kernel constants next to `Ry`/`Rz`/`gphase`.
- **NOT exported / internal:** `_dual_transform`, `_copy_into!`,
  `_record_parent!`, `_strict_check!`, the `Base.:+`/`Base.getindex` view/slice
  methods (host syntax).
- **`superpose!(x::QInt{W})`** lands here as a **library materialization** (§5):
  `for w in x.wires; _act!(ctx, H, (w,)); end; return x` — `H^{⊗W}` on |0⟩ (the
  (ℤ₂)^W Fourier, *not* the QFT), routed through `_act!` so it composes with
  `when`. It is the leading `superpose!` of DJ/BV, and the QFT-emission customer
  is `Int(dual(x))` (register dual), kept distinct.

---

## Executive summary (10 lines)

1. **All signs derive from two intertwiners** (§0): `F†D_aF = T_a` (addition) and
   `F†T_aF = D_{−a}` (modulation) — the r6/B2 minus sign is a *theorem*, not a convention.
2. **`add!(x,a)` = `F†∘D_{+a}∘F`** with F/F† via `apply!` (uncontrolled) and `D_a`
   via `_act!` — so control-under-`when` falls out of the §4.2 reassociation law with zero new ctrl code.
3. **`x̂ += a` emits `D_{−a}` directly** (bare phases, Lemma 0.3) — cheap modulation, NEVER a Fourier sandwich; `Base.:+` on the view mutates-and-returns-self (D11).
4. **`QInt{W} = (ctx, NTuple{W,WireID})`**, wire 1 = MSB; `QInt{W}(n)` range-checks→DomainError + exact-X per bit; `Int(x)` consumes all W wires single-sourced, errors loud on partial consumption.
5. **`x[i]` = a borrowed `QIntSlice <: AbstractQubit`** (SubArray-vs-Array); QBool/QBool-methods generalize `::QBool`→`::AbstractQubit` with no logic change — inherits actions/casts/dual/when free.
6. **`dual(x)` = `QFT(W)` kernel value** (F_G trait, width in a field like Perm); denotation = analytic DFT, emission = H/CP ladder + bit-reversal through the existing `ctrl` choke point; the view unwraps, the process F² negates.
7. **Two worlds (D12):** action-world `add!/sub!/⊻=/x̂+=a` in place return-self; value-world `x+a`/`x+y` fresh copy-then-`add!`, inputs live; bare `x += a` is the lost-binding rebind.
8. **Strict detector** populates the M2 `parent`/`strict` hooks: fresh-output ops record child→parent edges; region exit flags a traced parent with a surviving child (needs small return-value/escape-set plumbing) as a *classical* error.
9. **Pontryagin pins** (§6) each isolate one fixed-once sign; the F²-vs-unwrap test runs the *view* (`===`, no op) against the *process* (`apply!(QFT)²` = negation) on divergent code paths.
10. **Tests:** basis-sweep exactness (`add! ≡ T_a`, QFT emission ≡ DFT), W-wire Choi extension, strict-mode `@test_throws`, D2 partial-consumption + `dual(x)[i]`-throw; exports `QInt/add!/sub!/superpose!`, `public QFT/QIntSlice`.

## Deviations from the plan / PRD (flagged for the reviewer)

- **D-A1 (new kernel type `QFT`).** Plan §M6 says "Fourier lowering in
  `src/kernel/`, F_G supplied by the register type" without naming a type. I
  propose a dedicated `QFT <: ProcessValue` (width in a field, mirroring `Perm`;
  `inv::Bool` for adjoint) rather than a raw `Seq`/`Tensor` tree, because a named
  value gives clean `adjoint`/`denoted_matrix`/`ctrl` methods and a single
  convention-anchor test. It adds **one** `ProcessValue` type and **one** `_emit!`
  method (no new *controlled*-lowering code — CP rides `ctrl(P(θ))`), so the
  choke-point lint is unaffected. *Alternative the implementer may prefer:* a
  `_qft_tree(W)` builder returning `Seq`/`Ctrl`/`Tensor` of existing values — no
  new type, but heavier `denoted_matrix` and no clean `inv` flag.

- **D-A2 (abstract-supertype refactor for `x[i]`).** Introduces
  `AbstractQubit` (QBool + QIntSlice) and widens M3/M4 signatures `::QBool` →
  `::AbstractQubit`. This edits landed M3/M4 files (signatures only, no logic) —
  larger blast radius than a self-contained M6, but the idiomatic SubArray/Array
  realization of D2's "distinguishable wrapper, not a bare QBool". A lower-churn
  alternative (duplicate the handful of methods for `QIntSlice`) avoids touching
  M3/M4 at the cost of copy-paste; I recommend the supertype.

- **D-A3 (`P(θ)` phase-gate constant).** Adds a `public` `P(θ)=gphase(θ/2)∘Rz(θ)`
  to `constants.jl` (the QFT/Draper phase primitive). Trivial, but it is a new
  kernel constant not enumerated in M1.

- **D-A4 (strict-mode escape/return plumbing).** The lost-binding detector needs
  regions to know their block's *returned* handles (escape set) to distinguish a
  returned survivor from a traced local. This is a small new capability in
  `region()`/`@context`/`eager`/`density` beyond the M2 `parent`/`strict` hooks.
  Without it the detector only catches outer-region survivors, not
  `x = x+a; return x` from a `region() do…end`; with it, it catches both. Flagged
  because it lightly touches M2 region code.

- **D-A5 (Choi harness W-wire extension).** `choi` currently supports `nin∈{1,2}`
  QBool channels. A `QInt{W}` channel-level `add!` Choi needs a W-wire-in/out
  variant (or the basis-sweep exactness test as the primary gate, Choi as
  backstop). Extends test-side tooling only, but is beyond the M4 harness.

- **D-A6 (D2 prose inversion, non-code, per CSW distillation).** The CSW
  distillation flags that D2's PRD prose still says the QFT has "maximal operator
  entanglement" — the r6 citation ruling wants "not a tensor product across any
  cut" attributed to CSW (maximality → Tyson/Nielsen). My `dual(x)[i]`-throw
  message and the §2.2/§3 rationale use the corrected "not a tensor product"
  wording. Recommend the reviewer also soften D2's body text (a PRD edit, not M6
  code).
