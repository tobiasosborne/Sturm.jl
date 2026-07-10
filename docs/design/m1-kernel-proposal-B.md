# M1 Kernel Process Values — Design Proposal B

**Round:** 3+1 for bead `Sturm.jl-c52g` (M1 kernel process values).
**Proposer:** B. **Angle:** mechanical sympathy and API seams — type
stability, zero-allocation composition, and dispatch that M2 (Ad/FFI),
M4 (views), and M8 (UnitaryDAG) consume without a refactor. Independent
design; I have not seen Proposer A's output.

All physics claims are grounded in one of the four M1 distillations
(`wharton_koch_quaternion_bloch.md` [WK], `tang_wright_2025_controlled_unitaries.md`
[TW], `delorme_control_as_constructor.md` [DP], `stuelpnagel_1964_rotation_parametrization.md`
[St]) or a named PRD-v2 §.

---

## 0. The type lattice (the seam that decides everything)

```julia
abstract type ProcessValue end        # §4.1: "One abstract type, trait-stratified"

struct U2 <: ProcessValue             # element of U(2)  (WK §"U(2) = (SU(2)×U(1))/ℤ₂")
    w::Float64; x::Float64; y::Float64; z::Float64   # unit quaternion (i,j,k in x,y,z)
    φ::Float64                                        # U(1) coset phase
end

struct MCX                            # one reversible instruction (not a ProcessValue)
    controls::Vector{Int}             # 1-based wire indices; empty ⇒ bare X
    target::Int
end
struct Perm <: ProcessValue           # §4.1: canonical 0/1, no phase freedom
    n::Int                            # wire count
    ops::Vector{MCX}                  # applied left-to-right (= right-to-left in ∘ order)
end

struct Ctrl{V<:ProcessValue} <: ProcessValue   # §4.2 single choke point
    k::Int                            # number of |1⟩-control wires (FLATTENED, see §5)
    inner::V
end

struct Tensor{F<:Tuple} <: ProcessValue   # ⊗ combinator (parallel)
    factors::F                        # tuple of ProcessValues, control-MSB order
end
struct Seq{F<:Tuple} <: ProcessValue      # ∘ fallback (series), right-to-left
    factors::F                        # factors[end] applied FIRST
end
```

**Why these six and not more.** `U2`, `Perm`, `Ctrl` are the three §4.1
values M1 must ship. `Tensor`/`Seq` are the two monoidal combinators
(`⊗`, `∘`) that make the algebra *total* on multi-wire operands the law
tests require, while remaining the smallest possible seed of M8's
`UnitaryDAG`: a `UnitaryDAG` is exactly `Seq`/`Tensor` nodes plus a
unitarity witness plus non-unitary node kinds (measurement, discard).
M1 defers *application* of `Tensor`/`Seq` (that is M2/M8) — it only
needs their `denoted_matrix`, `nqubits`, `adjoint`, and flattening smart
constructors for the law tests. This is the opposite of cornering M8:
its two structural node kinds already exist with the flattening M8 wants.

**Arity is a kernel invariant.** Every value knows its width; `∘`
asserts equal width, `Ad`/wiring in M2 needs it, `Ctrl` computes it:

```julia
nqubits(u::U2)      = 1
nqubits(p::Perm)    = p.n
nqubits(c::Ctrl)    = c.k + nqubits(c.inner)
nqubits(t::Tensor)  = sum(nqubits, t.factors)
nqubits(s::Seq)     = nqubits(first(s.factors))   # all factors equal (asserted at build)
```

`U2`, and `Ctrl{U2}`, are `isbits` ⇒ stack-allocated, zero-heap. `Perm`,
`Tensor`, `Seq` hold collections (heap) but are **never on the 1q hot
path** — that path is `U2 ∘ U2` only (§8).

---

## 1. `U2` — construction, convention, algebra

### 1.1 Pinned quaternion → matrix convention (WK, adopt verbatim)

Store `q = (w, x, y, z)`, `w` real, `(x,y,z)` = the `(i,j,k)` components;
`(i,j,k) ↔ −i(σx,σy,σz)` (the **operator** convention — **NOT** the
paper's `M_i`/Table-1 state labels `X↔k, Z↔i`, which are state-map
artifacts; WK §"CONVENTION WARNING"). The single load-bearing map:

```
U(q) = w·I − i(x σx + y σy + z σz) = [[ w − i z ,  −y − i x ],
                                      [  y − i x ,   w + i z ]]     (WK, det = +1, SU(2))
```

A U(2) element is `M = e^{iφ}·U(q)`. Because `U(q)` is always det +1,
the U(1) phase float is *why* the textbook gates (which have det −1)
need `φ` at all (WK §"Why U2 needs a separate U(1) phase"). The map
`(q,φ) ↦ e^{iφ}U(q)` is 2-to-1: `(q,φ) ~ (−q, φ+π)` (WK; St Thm 1
`γ(u)=γ(v) ⇔ u=−v`).

### 1.2 Constructor and validation policy

```julia
# Trusted inner constructor: no normalization, no branch (hot path).
U2(w,x,y,z,φ) = new(w,x,y,z,φ)     # default struct ctor

# Guarded smart constructor for USER/library entry (not hot):
function u2(w,x,y,z,φ; normalize=true)
    n2 = w*w + x*x + y*y + z*z
    normalize || (@assert abs(n2-1) ≤ ATOL_RENORM "U2: non-unit quaternion")
    s = normalize ? inv(sqrt(n2)) : 1.0
    U2(s*w, s*x, s*y, s*z, φ)         # φ NOT folded here — folding is an equality concern
end
```

Policy: **the raw struct constructor validates nothing** (it is called
millions of times by `∘`); a *separate* guarded `u2(...)` normalizes on
user entry. This is the standard Julia "trusted inner ctor + guarded
outer ctor" split and it is what keeps `∘` branch-free (§8). Phase is
**not** folded at construction — folding mod 2π is purely an *equality*
operation (§2); a stored `φ` may legitimately exceed 2π mid-fusion and
that carries no error (phases add, WK §"U(2)").

### 1.3 Composition `∘`, `adjoint`, `⊗`

`∘` is right-to-left (§4.2: "apply the right operand first"). For `U2`,
composition is the Hamilton product (WK, 16 real mul / 12 add) with
phases added:

```julia
@inline function Base.:∘(a::U2, b::U2)          # a after b
    aw,ax,ay,az = a.w,a.x,a.y,a.z
    bw,bx,by,bz = b.w,b.x,b.y,b.z
    U2(aw*bw - ax*bx - ay*by - az*bz,           # (WK Hamilton product, verbatim)
       aw*bx + ax*bw + ay*bz - az*by,
       aw*by - ax*bz + ay*bw + az*bx,
       aw*bz + ax*by - ay*bx + az*bw,
       a.φ + b.φ)                               # phases ADD (WK); no fold (§1.2)
end

@inline Base.adjoint(a::U2) = U2(a.w, -a.x, -a.y, -a.z, -a.φ)   # WK: q̄, and e^{-iφ}
```

`adjoint` = quaternion conjugate + phase negate: `U(q̄)=U(q)†` and
`(e^{iφ}U(q))† = e^{-iφ}U(q̄)` (WK §"Adjoint"). This is the "16
multiplies vs ~50" fusion win of §4.1, and it makes 1q gate fusion
*exact group arithmetic before anything touches Orkan* (§4.2 —
subsumes v0.1's `gate_cancel` table).

**`⊗`.** `U2 ⊗ U2` is a **2-qubit** operator, so it is *not* a `U2`
(`U2` is 1-qubit by construction). It returns a `Tensor` (§3). Deciding
this now, rather than deferring, is what keeps M8 uncornered: the
`⊗` smart constructor **flattens** (`Tensor` never nests) exactly as
M8's parallel-node builder will want:

```julia
⊗(a::ProcessValue, b::ProcessValue) = Tensor((a, b))
⊗(a::Tensor, b::ProcessValue)       = Tensor((a.factors..., b))
⊗(a::ProcessValue, b::Tensor)       = Tensor((a, b.factors...))
⊗(a::Tensor, b::Tensor)             = Tensor((a.factors..., b.factors...))
⊗(a::Perm, b::Perm)                 = Perm(a.n + b.n,                    # BONUS closure:
    vcat(a.ops, [MCX(c.controls .+ a.n, c.target + a.n) for c in b.ops]))# Perm⊗Perm is a Perm
```

`⊗` is a kernel-public operator we define (not in Base). Factors are in
**control-MSB order** (first factor = most-significant tensor leg),
matching the `cU = |0⟩⟨0|⊗I + |1⟩⟨1|⊗U` convention (TW p.2 / DP Example
2). `⊗` does **not** distribute over `ctrl` — `ctrl(f⊗g) ≠ ctrl(f)⊗ctrl(g)`
(DP §"Caveats": functoriality is over `∘` only). Nothing in the kernel
assumes it does.

### 1.4 Identity and global phase

```julia
const ID1 = U2(1.0, 0.0, 0.0, 0.0, 0.0)          # +I on 1 qubit
id(n::Int) = n == 1 ? ID1 : Perm(n, MCX[])       # n-wire identity as an empty Perm
gphase(α::Float64) = U2(1.0, 0.0, 0.0, 0.0, α)   # e^{iα}·I  (global phase, 1 qubit)
```

`gphase(α)` is the object DP §5 turns into a Z-rotation under control
(`ctrl(gphase(α))` = `diag(1,1,e^{iα},e^{iα})`, §5 test). `−I` is
`gphase(π)` = `U2(1,0,0,0,π)`; equivalently `U2(-1,0,0,0,0)` — the two
double-cover reps of `−I`, **distinct from +I** (§2).

---

## 2. Equality mod the double cover

Two independent predicates, chosen for **mechanical robustness**:

| predicate | backs | semantics | hazard-free? |
|---|---|---|---|
| `canonical(u)` + field `==` | `Base.:(==)`, `hash` | exact structural double-cover eq | fold-safe (mod), sign-flip needs snap tol |
| denoted-matrix `isapprox`  | `Base.:≈`, **all law tests** | numeric double-cover eq | **fully** (e^{iφ}U continuous, 2-to-1) |

**Design decision (deviation from the plan baseline — justified).** The
plan says "canonicalize … and compare with atol." I keep `canonical` for
`==`/`hash`, but route the *approximate* predicate `≈` through the
**denoted matrices**, which §4.1 explicitly sanctions ("or compare the
denoted matrices `e^{iφ}R(q)`"). Reason: canonicalize-then-atol has the
**fold-boundary hazard** the task flags — after `φ ← mod(φ,2π)`, the
values `φ≈0` and `φ≈2π−ε` are numerically far apart yet denote the same
element; a plain `|φa−φb|<atol` test *wrongly fails*. Comparing `e^{iφ}U`
is immune because `e^{iφ}` is continuous across the seam and the map is
2-to-1 onto the same matrix for `±q`. All named law tests use `≈`; this
kills the hazard structurally rather than patching it.

### 2.1 `canonical` (for `==`/`hash`) — precise pseudocode

```
const CANON_ZERO = ATOL           # |component| below this counts as 0 for sign choice

function canonical(u::U2)::U2
    w,x,y,z,φ = u.w,u.x,u.y,u.z,u.φ
    # (a) double-cover representative: make first NON-negligible component > 0
    s = 1.0
    for c in (w,x,y,z)
        if abs(c) > CANON_ZERO
            s = sign(c); break                 # unit norm ⇒ some |c| ≈ 1 ⇒ loop always sets s
        end
    end
    if s < 0
        w,x,y,z = -w,-x,-y,-z
        φ = φ + π                              # the ℤ₂ transform (q,φ)~(−q,φ+π), WK
    end
    # (b) fold φ into [0, 2π)
    φ = mod(φ, 2π)
    return U2(w,x,y,z,φ)
end

Base.:(==)(a::U2, b::U2) = (ca=canonical(a); cb=canonical(b);
    ca.w==cb.w && ca.x==cb.x && ca.y==cb.y && ca.z==cb.z && ca.φ==cb.φ)
Base.hash(u::U2, h::UInt) = (c=canonical(u); hash((c.w,c.x,c.y,c.z,c.φ), h))
```

`==` is **exact float equality after canonicalization** — reliable only
for values produced by identical exact construction paths (e.g. `X == X`,
or a constant vs a snapped literal). Its documented purpose is
structural reasoning and hashing, **not** post-arithmetic comparison —
for that, use `≈`. (This mirrors Base: `0.1+0.2 == 0.3` is `false`; we
do not pretend floats are exact.) The `CANON_ZERO` snap tol handles the
sign-flip ambiguity when a component that "should" be 0 is `±1e-16`.

**+I ≠ −I survives.** `canonical(+I) = canonical(U2(1,0,0,0,0)) =
U2(1,0,0,0,0)`. `canonical(−I) = canonical(U2(1,0,0,0,π)) =
U2(1,0,0,0,π)` (w>0, no flip, φ=π). Distinct fields ⇒ `+I ≠ −I` ✓ (WK
§"NEVER merge +I with −I"; St Thm 1; TW p.2 `I`-vs-`−I` under control).

### 2.2 `≈` (backs every law test) — precise pseudocode

```julia
function Base.isapprox(a::U2, b::U2; atol::Real=ATOL, rtol::Real=RTOL)
    # double-cover-safe by construction: both reps of ±q map to the SAME matrix.
    return isapprox(denoted_matrix(a), denoted_matrix(b); atol=atol, rtol=rtol)
end

function denoted_matrix(u::U2)::Matrix{ComplexF64}    # 2×2; TEST/Ad-only, not hot
    w,x,y,z = u.w,u.x,u.y,u.z
    e = cis(u.φ)                                       # e^{iφ}
    return e .* ComplexF64[ w-im*z   -y-im*x ;         # WK U(q), pinned convention
                            y-im*x    w+im*z ]
end
```

`denoted_matrix` returns a plain `Matrix{ComplexF64}` (heap) to keep
core Sturm **dependency-free** (convention 4: only Orkan; no StaticArrays).
It is used only in tests and, in M2, at the Ad boundary (which will go
quaternion→ZYZ directly and never materialize this in the hot path). If
M2 profiling wants an isbits 2×2, add a tiny `Mat2` struct then — not now.

**Optional alloc-free `≈` (offered, not primary).** A quaternion-native
predicate avoids the two matrix allocations; the reference predicate
stays denoted-matrix because it is trivially provable and used in law
tests:

```julia
function approx_native(a::U2, b::U2; atol)
    qa = (a.w,a.x,a.y,a.z); qb = (b.w,b.x,b.y,b.z); φb = b.φ
    if qa[1]*qb[1]+qa[2]*qb[2]+qa[3]*qb[3]+qa[4]*qb[4] < 0   # align across the cover
        qb = (-qb[1],-qb[2],-qb[3],-qb[4]); φb += π
    end
    dφ = rem(a.φ - φb, 2π, RoundNearest)                     # circle distance — fold-safe
    return all(abs.(qa .- qb) .< atol) && abs(dφ) < atol
end
```

The `rem(·,2π,RoundNearest)` is the fold-boundary-safe angular compare;
sign alignment via the dot product is correct because `dot<0` can only
occur when `a,b` are genuinely different elements (locally the map is an
immersion — quaternion+phase distance is Lipschitz-equivalent to matrix
distance).

---

## 3. Renormalization policy

**When.** Trigger on `|‖q‖² − 1| > ATOL_RENORM`, `ATOL_RENORM = 2.0^-40`
(≈ 9.1e-13, plan baseline — **accepted**). Justification: machine
epsilon is `2^-52`; per-Hamilton-product norm error is `O(eps)` and
accumulates ~`O(√N·eps)` (random-walk) to `O(N·eps)` (worst case). A
`2^-40` budget tolerates ~`2^12 ≈ 4096` fused products worst-case before
the norm drifts past threshold — comfortably more than any 1q fusion run
between Orkan flushes, so the check almost never fires and the branch
predictor learns the not-taken path.

**How.** A single scalar rescale (§4.1; WK §"Numerics": cheaper and
better-conditioned than re-orthogonalizing a drifting complex 2×2):

```julia
function renormalize(u::U2)::U2
    n2 = u.w*u.w + u.x*u.x + u.y*u.y + u.z*u.z
    s  = inv(sqrt(n2))
    U2(s*u.w, s*u.x, s*u.y, s*u.z, u.φ)          # φ untouched
end
maybe_renormalize(u::U2) = ( (u.w^2+u.x^2+u.y^2+u.z^2) - 1 |> abs ) > ATOL_RENORM ?
                           renormalize(u) : u
```

**Where (refinement of the plan — mild, justified).** The plan implies
renorm sits inside `∘`. I place `maybe_renormalize` at the **flush /
application seam**, NOT inside every Hamilton product. Reason (mechanical
sympathy): the norm check is 4 mul + 3 add + branch on top of `∘`'s 16
mul + 12 add — a ~25% tax on the hottest kernel, paid to guard against
drift that is negligible until thousands of products accumulate. So `∘`
stays a pure branch-free `@inline`; the Eager 1q fusion buffer (§4
workstreams) and the Ad boundary call `maybe_renormalize` once per flush
— exactly where a drifted quaternion would actually reach Orkan and
matter. The `2^-40` *threshold* is unchanged; only the *call site* moves
to where it is cheap and sufficient.

**Tested cadence.** `test_numerics_renorm.jl`:
1. Fuse `H` (or a fixed irrational-axis `Ry(θ)`) `N` times; assert
   `‖q‖²` stays within `ATOL_RENORM` for `N` up to the derived bound
   (≈4096) *without* renorm, and drifts past it beyond — pins the budget
   justification to a number.
2. Assert `maybe_renormalize` is a **no-op** (`===`-preserving where
   possible, or `≈` within `2^-52`) below threshold and restores unit
   norm above it.
3. `renormalize` leaves `denoted_matrix` unchanged to `≈` (rescale is a
   projection along the fiber, not a rotation).

---

## 4. `Perm`

**Representation (improved from the plan baseline — justified).** Plan
baseline: instruction list of `X/CX/CCX`. I collapse the three fixed-arity
instructions into **one variable-arity `MCX(controls, target)`**. Reason:
`ctrl(Perm)` must be **closed** (§4.1 — the one-line closure fact is the
proof), but `ctrl(CCX)` is a `C³X`, which is *not* in `{X,CX,CCX}`. A
fixed 0/1/2-control set is **not closed under `ctrl`**; a variable-arity
`MCX` is. This is a real correctness fix, not a preference. (Lowering an
`MCX` to Orkan's ≤2-control primitives via ancillae is M2's job — the
kernel value stays exact and closed.)

```julia
ctrl(p::Perm) = Perm(p.n + 1,                             # new control = wire 1 (MSB)
    [ MCX(pushfirst!(op.controls .+ 1, 1), op.target + 1) for op in p.ops ])
    # every instruction gains wire 1 as a control; all existing indices shift +1.
    # closure: result isa Perm ✓  (§4.1). O(#ops · arity).

Base.adjoint(p::Perm) = Perm(p.n, reverse(p.ops))
    # each MCX is an INVOLUTION (MCX² = I), so inverting an instruction is a no-op;
    # adjoint = reverse the list. One-liner. (plan: "reversed inverse list")

Base.:∘(a::Perm, b::Perm) = ( @assert a.n == b.n "Perm ∘: width mismatch";
    Perm(a.n, vcat(b.ops, a.ops)) )                       # b FIRST (right-to-left ∘)

nqubits(p::Perm) = p.n
```

**Phase freedom: none** (§4.1 — canonical 0/1 matrices). `Perm` carries
no `φ`; `adjoint`/`ctrl`/`∘` never touch a phase, which is precisely why
"the classical-reversible corner is the best-behaved under control"
(§4.1). `ctrl(Perm) isa Perm` closure is a named test (§7).

**Equality: definitional (permutation-level), not list-level.** Two
different `ops` lists can denote the same permutation (reversible-circuit
equivalence). `==` compares the *induced permutation*:

```julia
function permvector(p::Perm)::Vector{Int}                 # materialize; assert small n
    @assert p.n ≤ MAXPERM_N "Perm ==: width $(p.n) too large to materialize"
    perm = collect(0:(1<<p.n - 1))
    for i in eachindex(perm)
        s = perm[i]
        for op in p.ops                                   # apply left-to-right
            if all(((s >> (c-1)) & 1) == 1 for c in op.controls)
                s ⊻= (1 << (op.target-1))
            end
        end
        perm[i] = s
    end
    perm
end
Base.:(==)(a::Perm, b::Perm) = a.n==b.n && permvector(a)==permvector(b)
```

`MAXPERM_N` ≈ 16 (2^16 states). Documented: `Perm` equality is
definitional and computed by materialization; law tests use small `n`.
For large `n`, equality is intentionally unavailable (exact
reversible-circuit equivalence is intractable — fail loud, don't guess).
`denoted_matrix(p::Perm)` = the 0/1 permutation matrix from `permvector`
(tests only).

**Seam.** `Perm.ops` (an ordered `MCX` list) is *exactly* what M7's
Bennett bridge emits and M2's application replays ("replay stored
reversible circuit", §4.3). No translation layer.

---

## 5. `ctrl` — the single choke point

### 5.1 The `Ctrl{V}` wrapper and the flattening decision

```julia
ctrl(u::U2)            = Ctrl{U2}(1, u)                    # 1-control on a U2
ctrl(c::Ctrl{V}) where V = Ctrl{V}(c.k + 1, c.inner)      # FLATTEN: bump count, keep base
ctrl(p::Perm)          = <the Perm method of §4>          # closure: returns a Perm, NOT Ctrl
# ctrl(d::UnitaryDAG)  = Ctrl{UnitaryDAG}(1, d)           # M8 seam — one method, added later

Base.adjoint(c::Ctrl) = Ctrl(c.k, adjoint(c.inner))       # §4.2 adjoint(ctrl g)=ctrl(adjoint g)
nqubits(c::Ctrl)      = c.k + nqubits(c.inner)
```

**The load-bearing mechanical decision.** `ctrl(ctrl(g))` must be
Toffoli-grade control (§4.2 "closed: no special case"). The naive
`Ctrl(inner)` wrapper would make `ctrl(ctrl(ctrl(u)))` have type
`Ctrl{Ctrl{Ctrl{U2}}}` — a **new concrete type per nesting depth**,
which explodes dispatch specialization and makes any loop that builds
`ctrl^k(g)` type-unstable (return type depends on the runtime `k`). I
**flatten**: `Ctrl{V}` carries an `Int k` control count and `V` is the
**base** value (never another `Ctrl`). Then `ctrl(::Ctrl{U2})::Ctrl{U2}`
— *stable*, one concrete type regardless of depth. This is the single
place where `Ctrl{V}` parametricity strains Julia, and flattening is the
resolution. It also matches the physics: DP Eq 14 (nested controls
commute) means the `k` controls are an *unordered set on the same
footing*, so a count is the faithful representation, not a tower.

**Why `k` is a count, not a wire list.** Process values are
**wire-agnostic** until `Ad`/context assigns wires (§4.3: "a register is
a handle into a context that owns the state"). `Ctrl` records *how many*
controls, not *which* wires; wiring is M2's job. This keeps `Ctrl{U2}`
`isbits` and lets the same value be applied to different wire tuples.

**Multi-basis control is NOT in the kernel `Ctrl`.** DP §7 / p.8:
`C_{|0⟩}`, `C_{|+⟩}` are `C_{|1⟩}` conjugated by a basis change on the
control wire. Kernel `ctrl` is the single `C_{|1⟩}` functor; other bases
are *derived* at the surface/view layer by a `U2` sandwich on the control
(the CZ / `Bool(dual(q))` family, §3.3). The kernel stays one functor —
this is the categorical single-choke-point (DP §"single-choke-point
thesis").

### 5.2 Composition of `Ctrl` = the homomorphism law, executable

```julia
function Base.:∘(a::Ctrl, b::Ctrl)
    if a.k == b.k
        Ctrl(a.k, a.inner ∘ b.inner)          # §4.2: ctrl(g)∘ctrl(h) == ctrl(g∘h)
    else
        @assert nqubits(a)==nqubits(b) "Ctrl ∘: width mismatch"
        Seq((a, b))                            # different control counts on equal width
    end
end
```

When both have the same `k` (same controls, wire-agnostic level),
`Ctrl(k,a)∘Ctrl(k,b) = Ctrl(k, a∘b)` — this **is** the §4.2 homomorphism
`ctrl(g)∘ctrl(h)==ctrl(g∘h)` *made into the composition rule*, and it is
the streaming license D13/§3.5 needs (apply `ctrl(op)` op-by-op). It is
also type-stable (`Ctrl(k,U2)∘Ctrl(k,U2)→Ctrl(k,U2)` since `U2∘U2→U2`).
Different `k` but equal width is a genuinely different operator ⇒ `Seq`
fallback, not a wrong fusion.

### 5.3 `denoted_matrix(Ctrl)` (tests / Ad)

Controls are MSBs; the all-controls-set block is the *last* block:

```julia
function denoted_matrix(c::Ctrl)::Matrix{ComplexF64}
    M  = denoted_matrix(c.inner)                 # d×d, d = 2^nqubits(inner)
    d  = size(M,1)
    N  = (1 << c.k) * d                          # 2^k · d
    A  = Matrix{ComplexF64}(I, N, N)             # identity on all non-fully-controlled blocks
    A[N-d+1:N, N-d+1:N] .= M                     # inner acts iff all k controls = 1
    A
end
```

For `k=1`: `blockdiag(I_d, M)` = `|0⟩⟨0|⊗I + |1⟩⟨1|⊗M` (TW p.2; DP
Example 2) ✓. `ctrl(gphase(α))` → `diag(1,1,e^{iα},e^{iα})` = a
Z-rotation on the control (DP §5) — the "distinguishes g from e^{iα}g"
law (§7).

### 5.4 Totality and the M8 seam

`ctrl` is total on M1 values by three methods: `ctrl(::U2)`,
`ctrl(::Perm)`, `ctrl(::Ctrl)`. There is **no** `ctrl(::ProcessValue)`
catch-all — totality is by exhaustive concrete methods, so an
un-handled kind is a `MethodError` (fail loud), not a silent wrong
wrap. M8 adds exactly one method, `ctrl(::UnitaryDAG)`, with no change
to existing code — the seam is a single method, not a refactor.

### 5.5 Mechanical single-choke-point lint (plan grep-lint)

A `runtests.jl` boot pass (same shape as the `docs/physics/*.md`
citation lint, CLAUDE.md principle 4):

```
1. Assert `function ctrl(` / `ctrl(...) =` DEFINITIONS occur only in src/kernel/ctrl.jl
   (and the M8 UnitaryDAG method, also under src/kernel/).
2. Grep src/ for  /\borkan_cx\b|\bcontrolled\b/  — assert every hit is under
   src/kernel/ or src/orkan/  (§4.2 invariant).
```

Because *constructing a controlled lowering* is only reachable through
`ctrl` (the only producer of `Ctrl`) and Orkan's controlled primitives
are only named under `src/orkan/`, the lint mechanically enforces "`ctrl`
is the only constructor of controlled lowerings" (§4.2). The `Ctrl` inner
constructor can additionally be made `private`-by-convention (only `ctrl`
methods call it) and a second lint asserts `Ctrl(` appears only in
ctrl.jl.

---

## 6. Namespace and file layout

Everything here is **kernel**: `public`, never `export`ed (convention 8;
plan M1). In `src/Sturm.jl`: `public U2, Perm, Ctrl, ctrl, ⊗, id,
gphase, denoted_matrix, nqubits, X, Y, Z, H, S, T, Ry, Rz, Rx`. (`∘`,
`adjoint` are Base methods on our types — reachable via the operators.)

Files (plan layout):

| file | contents |
|---|---|
| `src/kernel/u2.jl` | `abstract type ProcessValue`, `U2`, `u2`, `∘`, `adjoint`, `renormalize`, `maybe_renormalize`, `canonical`, `==`, `hash`, `isapprox`, `denoted_matrix(::U2)`, `nqubits(::U2)` |
| `src/kernel/perm.jl` | `MCX`, `Perm`, `ctrl(::Perm)`, `adjoint`, `∘`, `==`, `permvector`, `denoted_matrix(::Perm)`, `nqubits(::Perm)` |
| `src/kernel/ctrl.jl` | `Ctrl`, `ctrl(::U2)`, `ctrl(::Ctrl)`, `adjoint(::Ctrl)`, `∘(::Ctrl,::Ctrl)`, `denoted_matrix(::Ctrl)`, `nqubits(::Ctrl)`; **the choke-point lint spec** |
| `src/kernel/algebra.jl` | `Tensor`, `Seq`, `⊗` (+ flattening), generic `∘` fallback → `Seq`, `denoted_matrix`/`adjoint`/`nqubits` for both, `id` |
| `src/kernel/constants.jl` | `X, Y, Z, H, S, T`, `Ry, Rz, Rx`, `ID1`, `gphase` |
| `src/kernel/numerics.jl` | `ATOL`, `RTOL`, `ATOL_RENORM`, `CANON_ZERO`, `MAXPERM_N`, `INV_SQRT2` |

### 6.1 The gate constants — components WRITTEN OUT (convention bugs die here)

Computed under the pinned convention (§1.1). Each is `M = e^{iφ}U(q)`;
verified against the textbook 2×2 in comments (WK §"the gates, in THIS
convention"):

```julia
const INV_SQRT2 = 0.7071067811865476        # = sqrt(0.5)

const X = U2(0.0,        1.0, 0.0, 0.0,        π/2)   # e^{iπ/2}·U(i)  = i·(−iσx) = σx
const Y = U2(0.0,        0.0, 1.0, 0.0,        π/2)   # e^{iπ/2}·U(j)  = σy
const Z = U2(0.0,        0.0, 0.0, 1.0,        π/2)   # e^{iπ/2}·U(k)  = σz
const H = U2(0.0, INV_SQRT2, 0.0, INV_SQRT2,   π/2)   # e^{iπ/2}·U((i+k)/√2) = (σx+σz)/√2
const S = U2(INV_SQRT2, 0.0, 0.0, INV_SQRT2,   π/4)   # e^{iπ/4}·Rz(π/2) = diag(1, i)
const T = U2(cos(π/8),  0.0, 0.0, sin(π/8),    π/8)   # e^{iπ/8}·Rz(π/4) = diag(1, e^{iπ/4})
const ID1 = U2(1.0, 0.0, 0.0, 0.0, 0.0)              # +I

Ry(γ::Float64) = U2(cos(γ/2), 0.0,        sin(γ/2), 0.0,        0.0)   # φ=0: SU(2), det 1
Rz(γ::Float64) = U2(cos(γ/2), 0.0,        0.0,      sin(γ/2),   0.0)
Rx(γ::Float64) = U2(cos(γ/2), sin(γ/2),   0.0,      0.0,        0.0)
gphase(α::Float64) = U2(1.0, 0.0, 0.0, 0.0, α)
```

**Derivations (each a one-line proof — the load-bearing part of M1):**
- `X`: `U(i)=−iσx` ⇒ `σx = i·U(i) = e^{iπ/2}U(i)` ⇒ `φ=π/2, q=(0,1,0,0)`.
  `Y`,`Z` identically with `j`,`k` (WK gates table).
- `H`: `U((i+k)/√2) = −i(σx+σz)/√2 = −iH` ⇒ `H = e^{iπ/2}U(q_H)`.
- `S = diag(1,i)`: `Rz(π/2)=diag(e^{−iπ/4},e^{iπ/4})`; `e^{iπ/4}·Rz(π/2)
  = diag(1, e^{iπ/2}) = diag(1,i)` ⇒ `φ=π/4, q=(cos π/4,0,0,sin π/4)`.
- `T = diag(1,e^{iπ/4})`: `e^{iπ/8}·Rz(π/4) = diag(1, e^{iπ/4})` ⇒
  `φ=π/8, q=(cos π/8,0,0,sin π/8)`.
- `Ry/Rz/Rx`: `R_n̂(γ)=cos(γ/2)I − i sin(γ/2)(n̂·σ)` is already det-1
  SU(2), so `φ=0` (WK Eq 8). `S,T` are the only diagonal gates whose
  det is not 1, hence the only fractional `φ`.

**H² sanity (embedded as a comment + §7 meta-test):** `q_H q_H =
(−1,0,0,0)` (Hamilton, WK §"Exact H²"), `φ = π/2+π/2 = π` ⇒
`H∘H = U2(-1,0,0,0,π)`; `denoted_matrix` = `e^{iπ}·(−I) = I`.
`canonical(H∘H) = U2(1,0,0,0,0) = canonical(ID1)` ✓.

---

## 7. Test plan — every named law → a `@testset`

Tests live in `test/test_kernel_*.jl`; each `@testset` is **named after
its PRD §** for the grep-able coverage map (§4 workstreams). Dense 2×2/
4×4 matrices are built **in tests only** (via `denoted_matrix` and hand
literals). All comparisons `≈` unless noted.

| # | law (plan M1 list / §4.2) | `@testset` design | ground |
|---|---|---|---|
| 1 | `Ry(a)∘Ry(b) ≈ Ry(a+b)` | random `a,b`; also `Ry(2π) ≈ −I` and `!(Ry(2π) ≈ ID1)` and `Ry(4π) ≈ ID1` | §4.2; WK §"NEVER merge"; St Thm 1 |
| 2 | `H∘H == I` (**and FAILS naive tuple eq**) | assert `H∘H ≈ ID1`; assert `canonical(H∘H)==canonical(ID1)`; **meta:** assert the *naive* 5-tuple compare `(-1,0,0,0,π) !≈ (1,0,0,0,0)` returns false → regression-guards the predicate | §4.1; WK §"Exact H²" |
| 3 | X/Z/H/S/T exact elements | `denoted_matrix(X) ≈ [0 1;1 0]`, `Z ≈ [1 0;0 -1]`, `H ≈ [1 1;1 -1]/√2`, `S ≈ [1 0;0 im]`, `T ≈ [1 0;0 cis(π/4)]`; and `X∘X ≈ ID1`, `Z∘Z ≈ ID1`, `S∘S ≈ Z`, `T∘T ≈ S` | §1.1 convention pin — **where convention bugs die** |
| 4 | `+I ≠ −I` survives quotient | `!(gphase(π) ≈ ID1)`; `gphase(π) ≈ U2(-1,0,0,0,0)` (other rep of −I); `canonical(gphase(π)) != canonical(ID1)` | §4.1; TW p.2; WK |
| 5 | `adjoint`: `g∘g† ≈ ID1` | random `U2`; `denoted_matrix(g') ≈ denoted_matrix(g)'` (conj-transpose) | §4.1; WK §"Adjoint" |
| 6 | `ctrl(g∘h) == ctrl(g)∘ctrl(h)` | random `g,h::U2`; compare `denoted_matrix(ctrl(g∘h)) ≈ denoted_matrix(ctrl(g)∘ctrl(h))` (4×4) | §4.2; DP §"functoriality" |
| 7 | `adjoint(ctrl(g)) == ctrl(adjoint(g))` | 4×4 denoted compare | §4.2; DP Prop 1 |
| 8 | `ctrl` distinguishes `g` from `e^{iα}g` | `!(denoted_matrix(ctrl(ID1)) ≈ denoted_matrix(ctrl(gphase(α))))` for `α∉2πℤ`; check the latter ≈ `diag(1,1,cis α,cis α)` | §4.2; DP §5 "C(⊙_α)=Z-rot"; TW Thm 1.1 |
| 9 | `ctrl(ctrl(g))` Toffoli-grade, **type-stable** | `ctrl(ctrl(X)) isa Ctrl{U2}` with `k==2`; `denoted_matrix` ≈ 8×8 Toffoli-on-X block; `@inferred ctrl(ctrl(X))` | §4.2 "closed, no special case"; §5.1 |
| 10 | reassociation `(1⊗V)∘ctrl(W)∘(1⊗V†) == ctrl(V∘W∘V†)` | `V,W::U2` random; build LHS = `(ID1⊗V) ∘ ctrl(W) ∘ (ID1⊗V')` (produces `Seq`), RHS = `ctrl(V∘W∘V')`; 4×4 denoted compare | §4.2 (`within` law); DP Eq 16 |
| 11 | `ctrl(Perm) isa Perm` (closure) | build a CX as `Perm(2,[MCX([1],2)])`; `ctrl(CX) isa Perm`; `nqubits==3`; `denoted_matrix ≈` Toffoli permutation matrix | §4.1 closure |
| 12 | `Perm` adjoint / involution | `adjoint(p) ∘ p == id(n)` (permutation-eq); each `MCX` self-inverse | §4; §4.1 |
| 13 | double-cover eq predicate itself | `U2(1,0,0,0,0) == canonical(U2(-1,0,0,0,π))`; `hash` agrees; fold-boundary: `U2(q...,1e-15) ≈ U2(q...,2π-1e-15)` (denoted route passes; assert a naive-φ-atol compare would fail) | §4.1; §2 hazard |
| 14 | renorm cadence | §3 tests (drift budget, no-op below threshold, matrix-preserving) | §4.1; WK §"Numerics" |
| 15 | streaming≈materialized (seam) | for a fixed small `Ctrl` chain, `∘`-fused value ≈ op-by-op applied product (denoted) | §3.5 D13 |

The **meta-test (row 2)** is the crux the plan calls out: it constructs
the naive comparison inline (`isapprox` on the 5 raw fields) and asserts
it returns `false` for `H∘H` vs `ID1`, then asserts the real `≈` returns
`true` — so a future regression that "simplifies" `≈` back to naive
tuple compare fails loudly.

---

## 8. Numerics / type-stability

**Centralized atols** (`numerics.jl`, one file, per §4 workstreams):

```julia
const ATOL        = 1e-12          # default isapprox atol (denoted-matrix, canonical snap)
const RTOL        = sqrt(eps())    # default isapprox rtol (Base-consistent)
const ATOL_RENORM = 2.0^-40        # renorm trigger on |‖q‖²−1|  (§3)
const CANON_ZERO  = ATOL           # sign-of-first-nonzero snap tol (§2.1)
const MAXPERM_N   = 16             # Perm == materialization ceiling (§4)
const INV_SQRT2   = 0.7071067811865476
```

**Hot path is alloc-free.** The only hot path is 1q fusion:
`Base.:∘(::U2,::U2)` and `Base.adjoint(::U2)`. Both are `@inline`,
consume `isbits` `U2`, and return `isbits` `U2` constructed from scalar
arithmetic — **no heap allocation** (the returned `U2` lives in the
caller's frame / register file). `ctrl(::U2)` → `Ctrl{U2}(k, u)` is
`isbits` (both fields bits) — stack. `@code_warntype` gate (§4) targets:
`∘(::U2,::U2)`, `adjoint(::U2)`, `ctrl(::U2)`, `ctrl(::Ctrl{U2})`,
`∘(::Ctrl{U2},::Ctrl{U2})` — each must show a concrete return type
(no `Union`, no `Any`).

**Type stability is per-method, not per-runtime-branch.** `∘` returns
`U2` for `(::U2,::U2)`, `Perm` for `(::Perm,::Perm)`, `Ctrl{V}` for
`(::Ctrl{V},::Ctrl{V})` same-`k`, and `Seq` for the generic fallback —
each a **distinct method with a fixed return type**. A `Union` return
only appears if you compose values of statically-unknown type; in the
fusion buffer types are concrete `U2` ⇒ fully inferred. This is why the
`Seq`/`Tensor` totality (§0) costs nothing on the hot path: those methods
are never instantiated for `U2∘U2`.

**`denoted_matrix` allocates (heap `Matrix`) — and that is fine.** It is
test/Ad-only; the 1q hot path never calls it. Keeping it a plain
`Matrix{ComplexF64}` keeps core Sturm dependency-free (no StaticArrays;
convention 4). M2's Ad goes `U2 → ZYZ → Orkan rz/ry/rz` **without**
materializing a matrix at all (St: the ZYZ chart singularity at θ≈0/π is
quarantined to that one extraction site; composition stays chart-free on
the quaternion cover).

**Float-vs-irrational (π) hazards.**
- `Ry(2π)`: `γ/2 = π = Float64(π)`; `cos(π) = -1.0` exactly in Julia but
  `sin(π) = 1.2246e-16 ≠ 0`, so `Ry(2π) = U2(-1, 0, 1.2e-16, 0, 0)`,
  `‖q‖² = 1 + 1.5e-32`. `≈ −I` passes, `≈ I` fails — **exactly the
  physics** (WK; St). Consequence: the `Ry(2π) == −I` law MUST be `≈`
  (row 1), never exact `==` — CLAUDE.md "float laws compare with ≈".
- `H, S, INV_SQRT2`: `1/√2` is irrational ⇒ stored as the nearest
  Float64 (`0.7071067811865476`); `H∘H` gives `‖q‖² = 1.0000000000000002`
  (the `(1/√2)²` rounding), so `H∘H` is `≈ I`, not bit-`I` — again `≈`,
  and the renorm budget (§3) absorbs the drift.
- `T`: `cos(π/8), sin(π/8)` are irrational; components are best-Float64,
  compared with `≈`. `S,T` are the only constants with a fractional `φ`
  (`π/4, π/8`) because they are the only non-det-1 diagonal gates (§6.1).

No constant is asserted bit-exact; the "exact element" claims (§4.1) are
**group-structural** (X,Z,H,S,T land on the true U(2) elements, no SU(2)-
section residue), never claims about float arithmetic (WK §"float laws
compare with ≈"; CLAUDE.md Phase Discipline).
