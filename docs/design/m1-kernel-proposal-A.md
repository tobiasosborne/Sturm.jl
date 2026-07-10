# M1 Kernel Process Values — PROPOSAL A

**Round:** 3+1 for milestone M1 (bead `Sturm.jl-c52g`). Proposer A.
**Lens:** *algebraic laws first* — the group theory and the equality
quotient must be bulletproof before any performance concern. Every
numeric fast path in this design is anchored by a denotation-level
cross-check test, so correctness never rests on an arithmetic identity I
merely believe.

**Physics grounding used throughout** (all four M1 distillations):
`wharton_koch_quaternion_bloch.md` (the PINNED quaternion→U(2)
convention, verbatim, §"PINNED CONVENTION"), `stuelpnagel_1964…md`
(Thm 1: `γ(u)=γ(v) ⇔ u=−v`, the double cover is topological, not a
representational artifact), `tang_wright_2025…md` (Thm 1.1 / the
I-vs-−I example: control makes global phase physical), and
`delorme_control_as_constructor.md` (functoriality of `ctrl` over `∘`,
NON-functoriality over `⊗`, conjugation law Eq 16, `C(⊙_α)`=Z-rotation).

---

## 0. Design thesis (the one idea the rest follows from)

> **A process value's *meaning* is its denoted matrix. Every fast,
> matrix-free path (Hamilton product, quaternion-sign canonicalization,
> `ctrl` pushing) is an *optimization* whose obligation is to agree with
> the denotation — and each carries a fuzz test that proves it does.**

This framing makes the two hardest requirements *automatic* rather than
hand-argued:

- `H∘H == I` passes because the two denote the same matrix `I` (per
  Wharton–Koch: `q_H² = −1_quat`, phases sum to `π`, and
  `e^{iπ}U(−1_quat)=(−1)(−I)=I`).
- `+I ≠ −I` survives because they denote *different* matrices
  (`e^{i0}I` vs `e^{iπ}I`), and `ctrl` observes that difference
  (Tang–Wright I-vs-−I).

The quaternion-sign canonicalization (§2) is then just the *efficient*
way to decide "same matrix?" without building matrices, proven
equivalent to the matrix test by a fuzz cross-check. This is the
laws-first spine.

---

## 1. The `U2` type

### 1.1 Abstract supertype and traits

```julia
abstract type ProcessValue end

# wire count (Hilbert dim = 2^nwires for the qubit types of M1)
nwires(::ProcessValue) = error("nwires undefined")
dim(v::ProcessValue) = 1 << nwires(v)   # 2^nwires; overridable for P7 qudits
```

`U2`, `Perm`, `Ctrl`, `Tensor`, `Seq` (and M8's `UnitaryDAG`) are all
`<: ProcessValue`. **Laws (`∘`, `⊗`, `adjoint`, `ctrl`, `denoted_matrix`,
`isapprox`) are declared on the abstract type**, with concrete methods
specializing the fast cases — this is precisely what keeps M8 out of a
corner (§5.4).

### 1.2 The struct — immutable, 5 × Float64, isbits

```julia
struct U2 <: ProcessValue
    w::Float64; x::Float64; y::Float64; z::Float64   # unit quaternion q
    φ::Float64                                        # U(1) phase
    # unchecked internal constructor (used by the Hamilton hot path)
    global _u2(w,x,y,z,φ) = new(w,x,y,z,φ)
    # public checked constructor: FAIL LOUD on garbage, do NOT silently fix
    function U2(w,x,y,z,φ)
        @assert isfinite(w) & isfinite(x) & isfinite(y) & isfinite(z) & isfinite(φ) "U2: non-finite component"
        n2 = w*w + x*x + y*y + z*z
        @assert abs(n2 - 1) < U2_NORM_GROSS "U2: quaternion norm²=$n2 far from unit; build via Ry/Rz/constants or normalize first"
        new(w,x,y,z,φ)
    end
end
nwires(::U2) = 1
```

`U2` is `isbits` (40 bytes, stack-allocatable, no heap) — the property
the 1-qubit hot path lives on.

**Validation policy (CLAUDE.md #1 FAIL FAST):**

- The public constructor asserts finiteness and *gross* unit norm
  (`U2_NORM_GROSS = 2⁻²⁰ ≈ 9.5e-7`, §8). It **checks, never fixes** —
  renormalization (§3) is a distinct, deliberate step. The gross bound
  sits far above legitimate drift (renorm keeps drift `< 2⁻⁴⁰ ≈ 9e-13`,
  §3), so it never fires spuriously, but it catches the real bug class:
  a caller passing an un-normalized *axis* (e.g. `(0,1,1,0,·)`, norm 2)
  instead of a unit quaternion. The check costs 4 mul + 3 add + 1 cmp,
  negligible against a 16-mul Hamilton product.
- The **hot path** (`∘`) constructs results through `_u2` (unchecked)
  and applies the renorm-cadence logic itself, so the gross assert is
  paid once at *user* construction, not per fused product.
- No constructor renormalizes silently: a `U2` off the unit sphere by
  more than `U2_NORM_GROSS` is a *bug*, and bugs must be loud.

### 1.3 Pinned quaternion → U(2) denotation (Wharton–Koch, verbatim)

`U(q) = w·I − i(x σ_x + y σ_y + z σ_z)`, so the SU(2) part is the exact
2×2 of the distillation, and the U(2) element is `e^{iφ}U(q)`:

```julia
# local isbits 2×2 — NO StaticArrays dependency (CLAUDE.md Julia-conv #4)
struct Mat2; a::ComplexF64; b::ComplexF64; c::ComplexF64; d::ComplexF64; end

function denoted_matrix(u::U2)::Mat2
    ph = cis(u.φ)                       # e^{iφ}
    # U(q) = [[w−iz, −y−ix],[y−ix, w+iz]]   (Wharton–Koch, PINNED)
    Mat2(ph*complex(u.w, -u.z), ph*complex(-u.y, -u.x),
         ph*complex( u.y, -u.x), ph*complex( u.w,  u.z))
end
```

`Mat2` carries `*` (2×2 product), `adjoint`, `≈`, `kron`→`Matrix`, and a
converter to `Matrix{ComplexF64}` for the multi-wire path. **`denoted_matrix`
is the semantics; the Hamilton product below is the optimization.**

> Note: the plan requests `SMatrix`-style. I deliberately keep a local
> `Mat2` rather than take a StaticArrays dependency (principle 4: core
> depends only on Orkan). `Mat2` is isbits and equally fast. *(Deviation
> #4, minor — see report.)*

### 1.4 Composition `∘` — Hamilton product (the fast path)

`∘` is right-to-left (`V ∘ W` applies `W` first); by the isomorphism
`U(pq)=U(p)U(q)`, `denoted(V∘W)=denoted(V)·denoted(W)`. The 16-multiply
Hamilton product is transcribed verbatim from the distillation:

```julia
function Base.:∘(V::U2, W::U2)::U2
    pw,px,py,pz = V.w,V.x,V.y,V.z
    qw,qx,qy,qz = W.w,W.x,W.y,W.z
    rw = pw*qw - px*qx - py*qy - pz*qz
    rx = pw*qx + px*qw + py*qz - pz*qy
    ry = pw*qy - px*qz + py*qw + pz*qx
    rz = pw*qz + px*qy - py*qx + pz*qw
    φ  = fold_phase(V.φ + W.φ)                       # rem2pi, RoundNearest
    return renorm_if_needed(_u2(rw,rx,ry,rz,φ))      # §3
end
```

I do **not** hand-verify the 16 signs. The convention-anchor test
(§7 T0: `denoted(a∘b) ≈ denoted(a)*denoted(b)` on random `a,b`) is what
certifies the formula *and* the `U(q)` matrix *and* the `∘` order
simultaneously — one failing test localizes any convention slip. This is
the laws-first discipline: the group homomorphism is a *tested* fact.

### 1.5 `adjoint`

`(e^{iφ}U(q))† = e^{−iφ}U(q̄)`, and `U(q̄)=U(q)†` with `q̄=(w,−x,−y,−z)`:

```julia
Base.adjoint(u::U2)::U2 = _u2(u.w, -u.x, -u.y, -u.z, fold_phase(-u.φ))
```

Norm-preserving (sign flips only) ⇒ no renorm needed. Test T-adj:
`denoted(adjoint(u)) ≈ denoted(u)'`, and `u ∘ adjoint(u) ≈ I`.

### 1.6 `⊗` at the kernel level — decision and justification

`U2 ⊗ U2` is a **general** 2-qubit unitary (`kron` of two 1-qubit
operators is not itself a `U2` — `U2` parametrizes only U(2), one wire).
Therefore `⊗` **cannot** return a `U2`. Decision:

```julia
struct Tensor{A<:ProcessValue,B<:ProcessValue} <: ProcessValue
    a::A; b::B                      # disjoint, ordered wire blocks: a first
end
Base.:⊗(a::ProcessValue, b::ProcessValue) = Tensor(a, b)
nwires(t::Tensor) = nwires(t.a) + nwires(t.b)
denoted_matrix(t::Tensor) = kron(matrix(t.a), matrix(t.b))   # tests/multi-wire
```

`Tensor` is a **thin, wire-positional, lazy** node — the *degenerate
two-leaf case of M8's `UnitaryDAG`*. Justification and the anti-corner
argument are in §5.4. Wire order is pinned: **`Tensor(a,b)` denotes
`kron(a,b)` with `a` the most-significant (leftmost) factor** — the
single convention the reassociation test (§7 T8) needs.

Parametrizing `Tensor{A,B}` on concrete leaf types keeps `Tensor{U2,U2}`
isbits and type-stable; deeper trees degrade gracefully (multi-wire is
off the 1q hot path, and M8 owns the DAG rewrite).

### 1.7 Identity and global phase

- **Identity:** `const I2 = U2(1.0,0.0,0.0,0.0, 0.0)` — `denoted = I`.
  `I2 ∘ u == u` (Hamilton by `1_quat` is identity, `φ` adds 0).
- **Global phase `e^{iα}`** (Delorme's `⊙_α`): `phase(α) =
  _u2(1.0,0.0,0.0,0.0, fold_phase(α))`. `phasemul(u,α)` adds `α` to
  `u.φ`. `const NEG_I = U2(1.0,0.0,0.0,0.0, π)` (canonical form of `−I`;
  equivalently `_u2(-1,0,0,0,0)`).
- Global phase is the ker(Ad) direction (§4.3): invisible under Ad,
  **visible under `ctrl`** (`ctrl(phase(α))` is a Z-rotation on the
  control — Delorme §5). It is carried, never quotiented in the algebra.

---

## 2. Equality mod the double cover — the bulletproof core

### 2.1 What equality *means*

The 5-float representation is **2-to-1** onto U(2): `(q,φ)` and
`(−q,φ+π)` denote the *same* matrix `e^{iφ}U(q)` (since `U(−q)=−U(q)`,
Wharton–Koch; Stuelpnagel Thm 1: `γ(u)=γ(−u)`). Equality must quotient
that ℤ₂ **and nothing else** — in particular it must keep `+I ≠ −I`.

**Definitional semantics:** `a ≈ b  ⟺  denoted(a) ≈ denoted(b)` (matrix
`isapprox`, atol on complex entries). This is trivially correct on both
guardrails (`H∘H` and `I` are the same matrix; `+I`,`−I` are different
matrices). The canonical-form algorithm below is a *faster equivalent*,
and §7 T-canon fuzz-proves `canon_equal(a,b) == (denoted(a)≈denoted(b))`.

### 2.2 `==` vs `≈` policy — the idiomatic-Julia call

Because components are `Float64`, exact `==` is never the right test
(`H∘H` yields `w=−1+O(2⁻⁵²)`; `sin(Float64 π)=1.2e-16≠0`). Overloading
`Base.:(==)` to be *approximate* would break Julia's `==`/`hash`/
transitivity contract (principle 7, #11 idiomaticity). Therefore:

- **`Base.isapprox(a::U2, b::U2; atol=U2_ATOL, rtol=0)` is the normative
  U(2)-quotient equality** — used in *every* M1 law test.
- **`Base.:(==)` is left as default** (exact field `===`): honest
  "same representation," transitive, hashable. It is *not* the U(2)
  equality and the law tests do not use it.

> *(Deviation #1 from the plan's `==` prose — the plan writes law tests
> as `H∘H == I`. I route all law equalities through `≈`, justified by
> the `==`/`hash` contract. The plan's regression intent — "H∘H FAILS
> under naive tuple equality" — is preserved exactly: naive field `==`
> on `H∘H` vs `I` is `false`; `≈` is `true`.)*

### 2.3 Canonicalization — precise, boundary-safe pseudocode

Two refinements over the plan baseline, each addressing a hazard the
task names:

**(R1) Sign pivot = largest-magnitude component, not first-nonzero.** A
unit quaternion always has a component with `|·| ≥ 1/2`, so the pivot is
*never* near a sign-crossing — this eliminates the plan's "first nonzero"
threshold-tuning entirely and makes `canon(q) ≈ canon(−q)` provable.

**(R2) Phase compared on the circle, not the line.** Fold-boundary
hazard (`φ≈0` vs `φ≈2π−ε`) is killed by comparing via
`rem2pi(Δφ, RoundNearest)`, never `|fold(φa)−fold(φb)|`.

```
# pivot sign-fix: map (q,φ) to the ℤ₂ representative with the
# largest-|·| quaternion component positive. Deterministic tie-break =
# lowest index (stable across drift; see proof below).
function signfix(w,x,y,z,φ):
    i = argmax_lowest_index(|w|,|x|,|y|,|z|)     # ∈ {w,x,y,z}
    if component_i < 0:
        return (−w,−x,−y,−z, φ+π)                # ℤ₂ flip couples q-sign and +π
    else:
        return ( w, x, y, z, φ)

circdist(a,b) = abs(rem2pi(a − b, RoundNearest)) # phase distance on the circle

function canon_equal(A, B; atol=U2_ATOL):
    (wa,xa,ya,za,φa) = signfix(A)                # both now in SAME ℤ₂ rep
    (wb,xb,yb,zb,φb) = signfix(B)
    return  abs(wa−wb)<atol && abs(xa−xb)<atol &&
            abs(ya−yb)<atol && abs(za−zb)<atol &&
            circdist(φa,φb) < atol               # residual is a genuine phase
```

`Base.isapprox(a::U2,b::U2)` calls `canon_equal`. (Renormalize inputs
first only if a caller hands in a drifted value; internally produced
values are already renormed by §3.)

**Stability proof (why R1 works).** Let element `E` have reps `R=(q,φ)`
and `R'=(−q,φ+π)`. `signfix` picks pivot index `i` by `argmax|·|`; since
`|q_i|=|(−q)_i|`, both reps pick the *same* `i` (same magnitudes, same
tie-break). If `q_i>0`: `R` unflipped→`q`; `R'` has `(−q)_i<0`→flipped→
`−(−q)=q`. Both land on `q`. If `q_i<0`: symmetric, both land on `−q`.
∴ `canon(R)=canon(R')` exactly (up to float drift `≪ atol`). ∎

**Guardrail: `+I ≠ −I` survives.**
`I=(1,0,0,0,0)`: pivot `w=1>0`, no flip → `(1,0,0,0,0)`.
`−I=(−1,0,0,0,0)`: pivot `w=−1<0`, flip → `(1,0,0,0,π)`.
Quaternions equal, but `circdist(0,π)=π > atol` → **not equal.** ✓
(Tang–Wright: this π is exactly what `ctrl` turns into an observable Z.)

**Worked guardrail checks (the two named regressions).**
- `H∘H`: `q_H² = −1_quat`, `φ = π/2+π/2 = π` ⇒ `(−1,0,0,0,π)`. signfix
  flips → `(1,0,0,0,2π)`. Vs `I=(1,0,0,0,0)`: quats equal;
  `circdist(2π,0)=|rem2pi(2π,RoundNearest)|=0<atol` ⇒ **`H∘H ≈ I`.** ✓
  Naive field `==`: `(−1,0,0,0,π)≠(1,0,0,0,0)` ⇒ false (regression). ✓
- `Ry(2π)`: `q=(cos π,0,sin π,0)=(−1.0,0,1.2e-16,0)`, `φ=0`. signfix
  (pivot `|w|=1`) flips → `(1,0,−1.2e-16,0,π)`. Vs `NEG_I` canon
  `(1,0,0,0,π)`: quats equal within atol; `circdist(π,π)=0` ⇒
  **`Ry(2π) ≈ −I`;** vs `I` ⇒ `circdist(π,0)=π` ⇒ **`≠ I`.** ✓
  (`Ry(4π) ≈ I` likewise — spinor 4π-periodicity, Wharton–Koch.)

### 2.4 Canonical *form* (for display / potential hashing)

`canonical(u) = let (w,x,y,z,φ)=signfix(u); U2(w,x,y,z, mod2pi(φ)) end`
— a total function into a single representative. Not used by `≈` (which
uses `circdist` to stay boundary-safe) but available for logging and, if
ever needed, a `≈`-consistent bucketed hash. **Not** overloaded onto
`Base.hash` (approximate hashing is a trap; we key nothing by U(2)
element in M1).

---

## 3. Renormalization policy

**When.** Drift off the unit sphere is grown *only* by the Hamilton
product (`adjoint` sign-flips, `⊗`/constants are exact). So the *single*
renorm site is `∘`. Threshold **`RENORM_TOL = 2⁻⁴⁰ ≈ 9.09e-13`** (plan
baseline — **endorsed**, justified below):

```julia
@inline function renorm_if_needed(u::U2)::U2
    n2 = u.w*u.w + u.x*u.x + u.y*u.y + u.z*u.z
    if abs(n2 - 1) > RENORM_TOL
        s = inv(sqrt(n2))                    # ONE scalar rescale (§4.1)
        return _u2(u.w*s, u.x*s, u.y*s, u.z*s, u.φ)   # φ untouched
    end
    return u
end
```

**Why 2⁻⁴⁰.** A single product of two exactly-unit quaternions perturbs
`n2` by `O(few·ε) ≈ 1e-15 ≪ 2⁻⁴⁰`, so **the common path never rescales**
(one compare, no sqrt). Drift reaches `2⁻⁴⁰` only after thousands of
composes, so rescales are rare. Yet the residual denoted-matrix error is
bounded: `√(1+2⁻⁴⁰)−1 ≈ 2⁻⁴¹ ≈ 4.5e-13`, i.e. entry error `≪ U2_ATOL =
1e-10`. So `2⁻⁴⁰` is the sweet spot: never on the hot path, always below
test tolerance. `2⁻⁴⁰` is ~4096·ε — comfortably above single-product
noise, comfortably below any law's atol.

**How.** One scalar rescale of the quaternion (`inv(sqrt(n2))`, 4 mul).
Wharton–Koch §"Numerics": this is cheaper and better-conditioned than
re-orthogonalizing a drifting 2×2. `φ` carries no norm — untouched.

**Testing the cadence** (§7 T-renorm):
1. *It fires when it should*: feed a deliberately denormalized `U2`
   (norm 1.5 via `_u2`), `∘ I2`, assert result norm² within `RENORM_TOL`.
2. *It stays clean over long chains*: compose a non-commuting generic
   pair `Ry(0.1)∘Rz(0.1)` 10⁶ times; assert `|‖q‖²−1| < 1e-10` AND
   `‖denoted(result)† denoted(result) − I‖ < 1e-10` (unitarity preserved).
3. *It doesn't fire needlessly*: instrument a rescale counter; over 1000
   composes of unit inputs assert the counter is small (drift-limited),
   documenting the "rare rescale" claim quantitatively.

---

## 4. `Perm` — the phase-free classical corner

### 4.1 Representation

**Baseline (stored reversible instruction list) accepted, unified and
sharpened.** Every reversible generator is a **multiply-controlled NOT**:

```julia
struct MCX; controls::Vector{Int}; target::Int; end     # X=[]; CX=[c]; CCX=[c1,c2]
struct Perm <: ProcessValue
    nwires::Int
    gates::Vector{MCX}          # EXECUTION ORDER: gates[1] applied first
end
nwires(p::Perm) = p.nwires
```

- Compact (linear in circuit size — a Bennett artifact stays small; the
  explicit `2^n` permutation vector is exponential and rejected for
  storage).
- Matches the Bennett bridge's output vocabulary (X/CX/CCX/MCX).
- **Phase-free by construction** (§4.1: `Perm` has *no phase freedom*).
- Negative controls (control-on-`|0⟩`) are achieved by conjugating the
  control wire with `X` gates in the list, not a polarity flag — keeps
  the generator uniformly "MCX on `|1…1⟩`" and the `ctrl` closure a
  one-liner. (SWAP is derived = 3 CX; not a primitive.)

### 4.2 The operations

```julia
# ctrl: prepend ONE new control wire to EVERY gate. Controlled MCX is an
# MCX (more controls) ⇒ still a permutation. §4.1 one-line closure fact.
ctrl(p::Perm)::Perm = Perm(p.nwires + 1,
        [MCX([CTRL_WIRE; g.controls], g.target) for g in p.gates])

# adjoint: reverse execution order. Every MCX is an involution ⇒ no
# per-gate inversion. Denotes (G_k⋯G_1)† = G_1†⋯G_k† = G_1⋯G_k. ✓
Base.adjoint(p::Perm)::Perm = Perm(p.nwires, reverse(p.gates))

# ∘ (apply right first): run W's gates then V's gates
Base.:∘(V::Perm, W::Perm)::Perm =
        (@assert V.nwires==W.nwires; Perm(V.nwires, vcat(W.gates, V.gates)))

# ⊗: disjoint wires, offset the second block's indices
Base.:⊗(a::Perm, b::Perm)::Perm = Perm(a.nwires + b.nwires,
        vcat(a.gates, [MCX(c .+ a.nwires, t + a.nwires) for (c,t) in b.gates]))
```

`ctrl(::Perm)::Perm` closure is the marquee test T9 (`ctrl(p) isa Perm`;
`ctrl(CX) isa Perm` and denotes CCX; `ctrl(ctrl(X))` denotes Toffoli).
This is the §4.1 claim that "the classical-reversible corner is the
best-behaved under control" made mechanical.

### 4.3 Equality

`Perm` equality is *semantic* (two lists can denote one permutation), so
`==` on the instruction list is too strong (false negatives) and the
full `2^n` action is exponential. Resolution:

- `denoted_permutation(p)::Vector{Int}` replays the gate list over basis
  indices `0:2^n−1` with cheap bit-ops (the permutation's *normal form*).
- `Base.:(==)(a::Perm,b::Perm)` = `nwires` equal AND
  `denoted_permutation(a) == denoted_permutation(b)`, gated to
  `nwires ≤ PERM_EQ_MAXW` (default 20 ⇒ ≤10⁶ entries — ample for M1
  tests); above that it `error`s loudly ("semantic Perm equality
  intractable at n=$nwires; compare via denotation on a probe set")
  rather than silently returning a structural mis-answer (FAIL LOUD).
- `denoted_matrix(p)` (for cross-checks) builds the `2^n×2^n` 0/1
  matrix from `denoted_permutation` — tests only, small `n`.

The kernel never needs large-`Perm` equality — it *composes* and
*controls* them; equality is a test-time predicate.

---

## 5. `ctrl` — the single choke point

### 5.1 Representation: `Ctrl{V}` with a flat control count

```julia
struct Ctrl{V<:ProcessValue} <: ProcessValue
    inner::V
    k::Int                 # number of |1…1⟩-basis control wires, k ≥ 1
    # PRIVATE constructor — only `ctrl` may build a Ctrl (choke point)
    global _ctrl(inner::V, k::Int) where {V} = new{V}(inner, k)
end
nwires(c::Ctrl) = c.k + nwires(c.inner)
```

**Flat count, not nesting.** `ctrl(ctrl(u))` = `Ctrl(u, 2)`, not
`Ctrl(Ctrl(u,1),1)`. Justification: the `k` control wires are
*interchangeable* (Delorme Eq 14: nested controls commute — swapping
control wires is a symmetry), so nesting has a spurious associativity
that a count normalizes away. `Ctrl(u,2)` *is* the canonical form of the
Toffoli-grade control. `Ctrl{U2}` is isbits (`U2` + `Int`), preserving
type stability on the controlled 1q path. *(Refinement of the plan's
"wraps again" wording — the flat count is the normal form of the nest;
Deviation #3, benign.)*

### 5.2 `ctrl` — total, dispatched, the ONLY builder

```julia
ctrl(u::U2)          = _ctrl(u, 1)              # a controlled 1q gate is 2-wire
ctrl(p::Perm)::Perm  = <§4.2 absorb>            # closed in the classical corner
ctrl(c::Ctrl)        = _ctrl(c.inner, c.k + 1)  # ctrl∘ctrl ⇒ increment  (Toffoli-grade)
ctrl(v::ProcessValue) = _ctrl(v, 1)             # GENERIC fallback: total on the abstract type
```

- **`Perm` absorbs** (stays a `Perm`, §4.1).
- **`U2` and every multi-wire value wrap** (a controlled unitary carries
  the inner's global phase into an observable relative phase — it is NOT
  a `U2`).
- **Totality** on `U2`, `Perm`, `Ctrl`, and (M8) `UnitaryDAG` via the
  generic fallback (§5.4).

### 5.3 Denotation of `Ctrl` — where phase becomes physical

`k` controls, all-`|1⟩` fire; controls are the leading wires:

```julia
function denoted_matrix(c::Ctrl)
    U = matrix(c.inner)                     # d×d
    d = size(U,1);  K = 1 << c.k            # 2^k control block
    M = Matrix{ComplexF64}(I, K*d, K*d)     # identity on non-firing subspaces
    M[(K-1)*d+1 : K*d, (K-1)*d+1 : K*d] = U # inner acts on the |1…1⟩ block
    return M
end
```

This is `(I_K − |1…1⟩⟨1…1|)⊗I_d + |1…1⟩⟨1…1|⊗U`. Because `U` here is the
*denoted matrix* (phase included), `ctrl(e^{iα}g) ≠ ctrl(g)` — the
global phase of `g` lands on the diagonal of the firing block as a
*relative* phase (Delorme §5: `C(⊙_α)` = Z-rotation; Tang–Wright: this
is why `ctrl(−I)=diag(1,1,−1,−1)≠I`). **The phase-carrying representation
is load-bearing exactly here** — an SU(2)-section kernel would drop `α`
and compute the wrong controlled gate (a `Z` on the control, off).

### 5.4 The extension seam for M8 (anti-corner argument)

`Tensor` and `Seq` (§6) are the **two-leaf degenerate cases of M8's
`UnitaryDAG`**. The corner is avoided by three structural choices:

1. **Laws live on `ProcessValue`, not on `U2`.** `adjoint`, `denoted_matrix`,
   `isapprox`(-by-denotation for multi-wire), and the `ctrl` generic
   fallback all dispatch on the abstract type. When
   `UnitaryDAG <: ProcessValue` lands in M8, it inherits `ctrl` (wrap),
   `adjoint` (generic), and denotation *for free* — the laws are already
   proven on the supertype.
2. **`ctrl` respects Delorme's functoriality boundary.** `ctrl`
   distributes over `∘` (`Seq`) — the streaming law (§3.9/D13) — but is
   deliberately **not** pushed through `⊗` (`Tensor`): `ctrl(a⊗b)` is
   stored as `Ctrl{Tensor}` (one shared control wire gating both), NOT
   `Tensor(ctrl a, ctrl b)` (which is two control wires). This is exactly
   Delorme's `C(f⊗g) ≠ C(f)⊗C(g)` (distillation §"Caveats"). M8's DAG
   rewrite can later push controls where sound; M1 stores the honest
   wrapper.
3. **`Ctrl`'s constructor is private (`_ctrl`).** M8's `ctrl(::UnitaryDAG)`
   either hits the generic wrap or defines a homomorphism-pushing method
   — either way it goes *through* `ctrl`, never around it.

### 5.5 Single-choke-point — mechanical enforcement

Two layers, both mechanical (CLAUDE.md #2 spirit; plan grep-lint):

- **Language-level:** `Ctrl`'s only public builder is `ctrl` (the field
  constructor `_ctrl` is `global`-scoped inside the struct, not exported,
  not `public`). No call site outside `src/kernel/ctrl.jl` can name
  `_ctrl`. A boot-time lint greps `src/` for `_ctrl(` / `Ctrl(` outside
  `kernel/ctrl.jl` and errors.
- **Lowering-level (plan lint):** a runtests boot pass greps `src/` for
  `orkan_cx|controlled` and asserts matches occur *only* under
  `src/kernel/` and `src/orkan/`. Anything building a controlled
  decomposition elsewhere fails CI. (This is the invariant Cirq/Qiskit/
  pytket lacked — §4.2; Tang–Wright is *why* it matters.)

---

## 6. `∘`/`⊗` totality and the `Seq` node

`∘` **fuses only the two exact group multiplications** the algebra
highlights (§4.2 "gate fusion becomes quaternion arithmetic"): `U2∘U2→U2`
(Hamilton) and `Perm∘Perm→Perm` (concat). Everything else composes into a
lazy, denotation-correct node:

```julia
struct Seq{A<:ProcessValue,B<:ProcessValue} <: ProcessValue
    a::A; b::B                       # a ∘ b: apply b first, then a (same wires)
end
Base.:∘(a::ProcessValue, b::ProcessValue) =
        (@assert nwires(a)==nwires(b) "∘: wire-count mismatch"; Seq(a,b))
nwires(s::Seq) = nwires(s.a)
denoted_matrix(s::Seq) = matrix(s.a) * matrix(s.b)
Base.adjoint(s::Seq) = Seq(adjoint(s.b), adjoint(s.a))   # reverse + dagger
Base.adjoint(t::Tensor) = Tensor(adjoint(t.a), adjoint(t.b))
Base.adjoint(c::Ctrl)  = _ctrl(adjoint(c.inner), c.k)    # §4.2 adjoint∘ctrl law
```

I do **not** fuse `Ctrl∘Ctrl` or attempt homomorphism rewrites at M1:
the homomorphism law is a *tested* fact (§7 T5) verified through
denotation, and rewrite/fusion is an M8 pass. Laws-first: correctness by
denotation now, optimization later. `Seq`/`Tensor` are the seed nodes M8
generalizes — kept intentionally minimal.

**Wire model for M1 (scoped).** M1 process values are *wire-agnostic
operators* denoted in a **canonical positional order**: `Tensor(a,b)` →
`a` leftmost; `Ctrl(v,k)` → `k` controls leftmost, then `v`'s wires;
`Seq` shares its children's layout. This positional convention is
sufficient for every M1 law (they are shape identities, not placement
identities). Wire *binding* (WireID, aliasing) is M2+/M8. Stated
explicitly so the reassociation test's `1⊗V` vs `ctrl(W)` share wire 1 =
control, wire 2 = target unambiguously.

---

## 7. Test plan — every named law → a `@testset`

Dense matrices are built **in tests only**, from `denoted_matrix` and
explicit literals (`σx=[0 1;1 0]`, etc.). Each testset is *named after
its PRD section* (plan's grep-able coverage map).

**T0 — convention anchor** (`§4.1 quaternion↔U(2)`): random unit
`a,b::U2` ⇒ `denoted(a∘b) ≈ denoted(a)*denoted(b)`;
`denoted(adjoint(a)) ≈ denoted(a)'`; `denoted(I2) ≈ I`. *This single
testset certifies the entire pinned convention (matrix form + Hamilton
signs + `∘` order) — if any is transcribed wrong, T0 fails first.*

**T-canon — equality-predicate cross-check** (`§4.1 double cover`): fuzz
1000 random pairs, assert `canon_equal(a,b) == (denoted(a)≈denoted(b))`;
assert `canon_equal(a, phasemul(a,0)) ` reflexive; `canon(a)≈canon(negquat(a,+π))`
stability; **wrap-boundary**: `a` with `φ=1e-13` vs `φ=2π−1e-13` ⇒ equal.

**T1 — Ry additivity** (`§4.2 (ℝ,+) representation`): random `α,β` ⇒
`Ry(α)∘Ry(β) ≈ Ry(α+β)`; boundary `Ry(π)∘Ry(π) ≈ NEG_I`; same for `Rz`.

**T2 — H² lands on other rep of +I** (`§4.1`): `H∘H ≈ I2` (**passes**);
`fieldtuple(H∘H) != fieldtuple(I2)` (**naive `==` fails** — regresses the
predicate itself, plan's explicit ask); `denoted(H∘H) ≈ I` (matrix
cross-check).

**T3 — double cover / spinor periodicity** (`§4.1`): `Ry(2π) ≈ NEG_I`;
`!(Ry(2π) ≈ I2)`; `Ry(4π) ≈ I2`; `!(NEG_I ≈ I2)`.

**T4 — exact gate elements** (`§4.1`): `denoted(X)≈σx`, `Y≈σy`, `Z≈σz`,
`denoted(H)≈[1 1;1 −1]/√2`; involutions `X∘X≈I2, Z∘Z≈I2, H∘H≈I2`;
phase-stress fusions `S∘S ≈ Z`, `T∘T ≈ S`, `H∘X∘H ≈ Z`, `H∘Z∘H ≈ X`,
`X∘Y ≈ phasemul(Z,·)` (Pauli algebra with tracked phase).

**T5 — ctrl homomorphism over ∘** (`§4.2`): random `g,h::U2` ⇒
`denoted(ctrl(g∘h)) ≈ denoted(ctrl(g) ∘ ctrl(h))` (4×4); repeat for
`Perm` (`denoted_permutation`). Grounds Delorme functoriality.

**T6 — ctrl / adjoint commute** (`§4.2`): `denoted(adjoint(ctrl(g))) ≈
denoted(ctrl(adjoint(g)))`; also structurally `adjoint(ctrl(g)) ==
ctrl(adjoint(g))` by construction (§6). Grounds Delorme `(C f)†=C(f†)`.

**T7 — ctrl exposes global phase** (`§4.2`; Tang–Wright I-vs-−I):
`ctrl(NEG_I)` denotes `diag(1,1,−1,−1)`; `!(denoted(ctrl(NEG_I)) ≈
denoted(ctrl(I2)))`; for random `g,α≠0`: `!(denoted(ctrl(phasemul(g,α)))
≈ denoted(ctrl(g)))` — control distinguishes `g` from `e^{iα}g`.

**T8 — control-scope reassociation** (`§4.2 within`; Delorme Eq 16):
random `V,W::U2` ⇒ `denoted( (I2⊗V) ∘ ctrl(W) ∘ (I2⊗adjoint(V)) ) ≈
denoted( ctrl( V∘W∘adjoint(V) ) )` (4×4), with wire 1 = control.

**T9 — classical corner closed under ctrl** (`§4.1`): `ctrl(cx) isa
Perm`; `denoted_permutation(ctrl(cx))` = Toffoli; `ctrl(ctrl(x)) isa
Perm` = Toffoli; `p ∘ adjoint(p)` denotes identity permutation;
`ctrl(p)` denotes the block-controlled permutation matrix.

**T-renorm** (`§4.1 numerics`): the three cadence tests of §3.

**T-stability** (`§4.1`): `@code_warntype`/`@inferred` on `∘(::U2,::U2)`,
`adjoint(::U2)`, `denoted_matrix(::U2)`, `ctrl(::U2)`,
`isapprox(::U2,::U2)`, `ctrl(::Ctrl{U2})` — assert concrete
`U2`/`Ctrl{U2}`/`Mat2`/`Bool` returns, no `Any`.

---

## 8. Numerics / type stability

**Centralized constants** (`src/kernel/numerics.jl`, loaded first;
documented against §4.1):

```julia
const U2_ATOL       = 1e-10      # quaternion & circular-phase compare tolerance
const RENORM_TOL    = 2.0^-40    # ≈9.09e-13; renorm cadence (§3, plan baseline)
const U2_NORM_GROSS = 2.0^-20    # ≈9.5e-7; constructor bug-catch bound (§1.2)
const PERM_EQ_MAXW  = 20         # semantic Perm equality wire ceiling (§4.3)
```

`U2_ATOL = 1e-10` justification: above worst accumulated drift (renorm
holds `<2⁻⁴⁰`) and above the irrational-π residue (`sin(Float64 π)≈1.2e-16`),
below any physically meaningful gate difference. `rtol=0` (components are
`O(1)`, atol suffices). `numerics.jl` also houses `signfix`, `circdist`,
`renorm_if_needed`, `canonical` — one file, per the plan's cross-cutting
numerics policy.

**Allocation-free hot paths.** `U2`, `Ctrl{U2}`, `Tensor{U2,U2}`,
`Mat2` are all `isbits` ⇒ stack-allocated, no GC. `∘(::U2,::U2)` is 16
mul + 12 add + 1 branch (the renorm compare, predictable) + a `rem2pi`
for the phase; `adjoint`/`ctrl(::U2)` are field shuffles. `Perm`/`Seq`/
`Tensor`-of-abstract hold `Vector`/abstract fields (heap) — but these are
the *multi-wire / Bennett-replay* paths, not the 1q fusion hot loop; M8
owns their performance. `@code_warntype` gate (T-stability) enforces
concrete inference on the 1q path.

**Float-vs-irrational (π) hazards.**
- Constructors use **`sincos(γ/2)`** (one call, consistently rounded
  pair) for `Ry`/`Rz`/`Rx`; and **`cospi`/`sinpi`** for the fixed-angle
  constants `S`,`T`,`H` (exactly-rounded rational multiples of π).
- `Float64 π` makes `sin(π)=1.2e-16≠0`, so `Ry(2π)` is `(−1,0,1.2e-16,0)`
  not `(−1,0,0,0)`. **`U2_ATOL` absorbs it** (T3 passes). *Never compare
  `U2` with `==`* — always `≈`. This is the operational meaning of §4.1's
  "the exact claims are group-structural, never claims about float
  arithmetic."
- `circdist` uses `rem2pi(·,RoundNearest)` (Payne–Hanek accurate) — no
  catastrophic cancellation near multiples of 2π.

---

## 9. Namespace & file layout

Everything here is **kernel** → Julia 1.11 `public`, **never `export`ed**
(reachable as `Sturm.U2`, `Sturm.ctrl`, `Sturm.X`, …; not dumped into
`using Sturm`). Include order (dependency-respecting):

```
src/kernel/numerics.jl   # atol consts, signfix, circdist, renorm, canonical
src/kernel/u2.jl         # abstract ProcessValue; U2; Mat2; ∘,adjoint,denoted; isapprox
src/kernel/perm.jl       # MCX, Perm; ctrl(::Perm), adjoint, ∘, ⊗, denoted_permutation
src/kernel/ctrl.jl       # Ctrl{V} (+ private _ctrl); ctrl(::U2/::Perm/::Ctrl/::PV); denoted
src/kernel/algebra.jl    # Tensor, Seq; generic ∘/⊗/adjoint on ProcessValue; matrix()
src/kernel/constants.jl  # X,Y,Z,H,S,T, Ry(θ),Rz(θ),Rx(θ), I2, NEG_I, phase()
```

`public U2, Perm, Ctrl, Tensor, Seq, ProcessValue, ctrl, ⊗, denoted_matrix,
X, Y, Z, H, S, T, Ry, Rz, Rx, I2, NEG_I, phase, adjoint`
(`∘`, `adjoint`, `isapprox`, `==` are `Base` methods, no re-export).

### 9.1 The gate constants — components WRITTEN OUT under the pinned convention

Computed from `denoted = e^{iφ}U(q)` with `U(q)=w I − i(xσx+yσy+zσz)`
(all verified against §7 T4; the det-fixing `φ` is what lifts SU(2)→U(2)):

| gate | `w` | `x` | `y` | `z` | `φ` | denotes |
|---|---|---|---|---|---|---|
| `X`  | 0 | 1 | 0 | 0 | `π/2` | `σx=[0 1;1 0]` |
| `Y`  | 0 | 0 | 1 | 0 | `π/2` | `σy=[0 −i;i 0]` |
| `Z`  | 0 | 0 | 0 | 1 | `π/2` | `σz=[1 0;0 −1]` |
| `H`  | 0 | `1/√2` | 0 | `1/√2` | `π/2` | `[1 1;1 −1]/√2` |
| `S`  | `1/√2` | 0 | 0 | `1/√2` | `π/4` | `diag(1, i)` |
| `T`  | `cos(π/8)` | 0 | 0 | `sin(π/8)` | `π/8` | `diag(1, e^{iπ/4})` |
| `Ry(γ)` | `cos(γ/2)` | 0 | `sin(γ/2)` | 0 | 0 | `[[cγ,−sγ],[sγ,cγ]]` |
| `Rz(γ)` | `cos(γ/2)` | 0 | 0 | `sin(γ/2)` | 0 | `diag(e^{−iγ/2},e^{iγ/2})` |
| `Rx(γ)` | `cos(γ/2)` | `sin(γ/2)` | 0 | 0 | 0 | `cγ I − i sγ σx` |

Worked derivations (the sites where convention bugs die):
- `X`: `e^{iπ/2}U(i) = i·(−iσx) = σx`. ✓  (Y, Z identical pattern.)
- `H`: `e^{iπ/2}U((0,1/√2,0,1/√2)) = i·(−i)(σx+σz)/√2 = (σx+σz)/√2`. ✓
- `S`: `U(Rz(π/2)) = diag(e^{−iπ/4},e^{iπ/4})`; `e^{iπ/4}·` that `=
  diag(1,e^{iπ/2}) = diag(1,i)`. ✓  ⇒ `S∘S ≈ Z` (T4).
- `T`: `e^{iπ/8}·diag(e^{−iπ/8},e^{iπ/8}) = diag(1,e^{iπ/4})`. ✓  ⇒
  `T∘T ≈ S` (T4).
- `Ry(γ)`: `φ=0`, SU(2), `U(q)=[[cos γ/2, −sin γ/2],[sin γ/2, cos γ/2]]`. ✓

```julia
const X = U2(0.0, 1.0, 0.0, 0.0, π/2)
const Y = U2(0.0, 0.0, 1.0, 0.0, π/2)
const Z = U2(0.0, 0.0, 0.0, 1.0, π/2)
const H = U2(0.0, cospi(1/4), 0.0, cospi(1/4), π/2)          # cospi(1/4)=1/√2
const S = U2(cospi(1/4), 0.0, 0.0, sinpi(1/4), π/4)
const T = U2(cospi(1/8), 0.0, 0.0, sinpi(1/8), π/8)
Ry(γ) = (s = sincos(γ/2); U2(s[2], 0.0, s[1], 0.0, 0.0))     # sincos ⇒ (sin,cos)
Rz(γ) = (s = sincos(γ/2); U2(s[2], 0.0, 0.0, s[1], 0.0))
Rx(γ) = (s = sincos(γ/2); U2(s[2], s[1], 0.0, 0.0, 0.0))
```

*(`cospi(1/4)=sinpi(1/4)=0.7071067811865476`; `cospi(1/8)=0.9238795325112867`,
`sinpi(1/8)=0.3826834323650898`.)*

---

## 10. Summary of deviations from the plan baseline

1. **Equality via `≈`, not `==`** (§2.2). `==` kept as exact-field
   (honest, hashable, transitive); all law tests use `≈`. Justified by
   Julia's `==`/`hash` contract (principle 7/#11). Plan's regression
   intent preserved verbatim.
2. **Sign pivot = largest-|·| component, not first-nonzero** (§2.3, R1).
   A unit quaternion always has a component `≥1/2`, so the pivot is never
   near a sign-crossing — makes `canon(q)≈canon(−q)` *provable* and
   deletes the threshold-tuning the plan's "first nonzero" invites.
   Phase compared circularly (`rem2pi`) to kill the `φ≈0`/`φ≈2π` boundary.
3. **`Ctrl` = flat control count**, not nested wrappers (§5.1) — the
   count is the normal form of the nest (Delorme Eq 14: controls
   commute). Benign refinement of "wraps again."
4. **`Mat2` (local isbits 2×2), not StaticArrays `SMatrix`** (§1.3) —
   honors "core depends only on Orkan" (Julia-conv #4). Equally fast.
5. **`⊗`/`∘` totality via minimal `Tensor`/`Seq` seed nodes** (§1.6,
   §6) — needed to *test* the multi-wire laws (T8) at M1 while explicitly
   deferring the general DAG to M8; laws declared on `ProcessValue` so
   M8's `UnitaryDAG` inherits them (anti-corner, §5.4).

Everything else — `2⁻⁴⁰` renorm threshold, 5-float struct, Hamilton
16-mul, instruction-list `Perm`, grep-lint choke point, the named law
test list — follows the plan baseline.
