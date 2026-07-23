# M12 Hamiltonian-Simulation Module — Proposal B (host-language-first)

Proposer B, 2026-07-23, bead `Sturm.jl-bog7`. Lens: Julia idiomaticity,
type stability, dispatch elegance, forward compatibility (M11 mixtures,
future ctrl-`evolve!`), bench/Auto ergonomics. Physics constraints are
non-negotiable; within them, the most Julian API wins.

Ground truth read: `docs/literature/2607.19852_src/lbhs.tex` (frontier,
Fact HW = their Fact 4 / HW Thm 2.1, optimal-K Lemma = their Lemma 7),
`2206.06409_src/main.tex` (HW Def 5.1 higher-order outer loop, Thm 2.1
cost, Lemma 5.2/5.3), `1811.08017_src/qDRIFT_arXiv_V2submit.tex` (Thm 1
derivation, App. eqs for ε ≤ (2λ²t²/N)e^{2λt/N}), `suzuki_1991_JMP32_400`
(fractal recursion), plus `src/library/evolve.jl`, `grover.jl`, `qpe.jl`,
`surface/cases.jl` (`shots`), `context/{eager,density,abstract}.jl`,
`surface/when.jl` (`_act!`, control stack), `channel/dag.jl` (KrausFamily /
NoiseN barrier), `test/{test_m10_library.jl,choi.jl,runtests.jl}`,
PRD-v2 §1.3/§2/§5/§4.1/§3.9.

Citation names used below are the Phase-0 distillations
(`docs/physics/<name>.md`): `campbell_2019_qdrift`,
`campbell_2017_mixing_unitaries`, `hastings_2016_incoherent_errors`,
`hagan_wiebe_2023_composite`, `chen_2021_concentration_random_products`,
`zlokapa_2026_hamsim_lower_bounds`, `suzuki_1991_fractal_decomposition`,
plus the existing `childs_2019_trotter_error`.

---

## 0. The load-bearing idea: plan / trajectory / execute

Everything in this proposal hangs off one architectural split, chosen
because it is simultaneously the most Julian shape and the shape that
answers Q8 (verification), Q9 (counting), and Q10 (M11 lowering) for free:

```
 user surface        classical planning              quantum execution
 ───────────────     ─────────────────────────       ─────────────────────
 evolve!(x,H,t;…) →  plan = plan_evolution(alg,      for (j, θ) in
                        ham, t, ε)  :: EvolvePlan       trajectory(plan, rng)
                     (pure, RNG-free, testable          _pauli_exp!(ctx, x,
                      without any context)                 term_j, θ)
```

1. **`plan_evolution` is a pure classical function.** It validates, fills
   every defaulted parameter (steps, N, K, N_B) from the *cited* bounds,
   and returns a fully concrete, immutable plan. No `Union{Int,Nothing}`
   survives past planning — the executor sees only concrete `Int`s and
   `Float64`s (type stability where it matters; the planning layer is cold
   and may be `Union`-typed for ergonomics).
2. **A trajectory is an iterator of `(term_index::Int, θ::Float64)`.**
   Deterministic plans iterate without an RNG; randomized plans require
   one (`trajectory(plan)` on a randomized plan throws — no hidden global
   RNG, explicit threading per the hard constraint). Execution is a fold
   of `_pauli_exp!` over the trajectory. One trajectory = one unitary =
   one `apply!` sequence: nothing is ever wrapped as a
   `UnitaryBlock`/ProcessValue for the ensemble (hard constraint), and the
   stochastic *average* exists only in the analysis and the tests.
3. **`exp_count(plan)` is arithmetic on plan fields**, and
   `length(collect(trajectory(plan, rng)))` must equal it (a named test).
   The bench counter is therefore *not instrumented in the hot path at
   all* — the paper's cost unit (operator exponentials,
   zlokapa_2026_hamsim_lower_bounds.md Eq. (composite)) is a property of
   the plan, verified once against the iterator length.
4. **M11 lowering** (Q10): `trajectory(plan, rng)` is the Eager/`shots`
   unravelling of the channel the plan denotes. When M11 mixture values
   land, the same plan grows a `channel(plan)` lowering (per-step
   mixed-unitary KrausFamily → NoiseN, already a seam in
   `src/channel/dag.jl`). The surface signature does not move — Tobias's
   decision 3 is satisfied structurally, not by promise.

Everything below instantiates this skeleton.

---

## 1. Q1 — Strategy types, surface, sugar, file layout

### 1.1 The strategy layer

```julia
"Supertype of `evolve!` strategy descriptors (library values, PRD-v2 §5)."
abstract type EvolveAlg end            # public, not exported

struct Trotter <: EvolveAlg            # exported
    order::Int                         # 1 or even 2p (2,4,6,…) — validated
    steps::Union{Int,Nothing}          # explicit r, or nothing ⇒ derived from ε
end
Trotter(; order::Integer = 2, steps::Union{Integer,Nothing} = nothing) =
    Trotter(_check_order(order), _check_steps(steps))

struct QDrift <: EvolveAlg             # exported
    N::Union{Int,Nothing}              # sample count, or nothing ⇒ ⌈4λ²t²/ε⌉
    rng::Union{Random.AbstractRNG,Nothing}  # nothing ⇒ context rng (shots-friendly)
end
QDrift(; N = nothing, rng = nothing) = QDrift(_check_N(N), rng)

struct Composite <: EvolveAlg          # exported
    order::Int                         # 2p of the HEAD Suzuki formula (even ≥ 2)
    K::Union{Int,Nothing}              # head size, or nothing ⇒ optimal-K rule (§6)
    N_B::Union{Int,Nothing}            # qDrift samples per B-slot, or nothing ⇒ max(K,1)
    steps::Union{Int,Nothing}          # outer iterations r, or nothing ⇒ from ε
    rng::Union{Random.AbstractRNG,Nothing}
end
Composite(; order = 2, K = nothing, N_B = nothing, steps = nothing, rng = nothing) = …

struct Auto <: EvolveAlg end           # exported; zero-field singleton
```

Notes, in lens order:

- **Descriptors, not engines.** A strategy object is a *request*; the
  plan is the *contract*. `Union{Int,Nothing}` fields are fine here (cold
  path, resolved once); the plans are fully concrete structs.
- **Constructors validate eagerly** (`DomainError` at construction, not at
  `evolve!` time): `order == 1 || (iseven(order) && order ≤ 12)` for
  `Trotter`; `iseven(order) && 2 ≤ order ≤ 12` for `Composite`;
  `steps ≥ 1`, `N ≥ 1`, `K ≥ 0`, `N_B ≥ 1` when given. Order 12
  (p = 6, Υ = 6250) is the loud cap — beyond it Suzuki coefficients are
  numerically and practically useless; `throw`, never clamp.
- **RNG on the randomized strategies, defaulting to the context RNG.**
  `rng === nothing` means "draw from `Sturm.rng(ctx)` via the existing
  `_draw`/`core.rng` machinery" — so `shots(f, cap; rng = MersenneTwister(7))`
  reproduces distinct-but-seeded trajectories per shot with zero user
  effort (the `shots` contract, `surface/cases.jl`). Passing an explicit
  RNG *pins the sampled circuit* independently of measurement randomness —
  needed by the tests (§8) and by anyone studying a fixed trajectory.
- Why not `Trotter{Order}` with `Val`-style order in the type? Because the
  order never needs dispatch — planning turns it into a coefficient
  vector (§3), and parameterizing would force needless specialization and
  compile latency for a value used O(1) times per plan. Width `W` stays a
  type parameter where it earns its keep (the Hamiltonian, §2); `order`
  does not.

### 1.2 Plans (concrete, immutable, public)

```julia
abstract type EvolvePlan{W} end        # public

struct TrotterPlan{W} <: EvolvePlan{W}
    ham::PauliSum{W}
    t::Float64
    steps::Int
    sweep::Vector{Tuple{Int,Float64}}  # ONE step's (term, θ) schedule, materialized
end                                    #   trajectory = repeat sweep `steps` times

struct QDriftPlan{W} <: EvolvePlan{W}
    ham::PauliSum{W}
    t::Float64
    N::Int
    τ::Float64                         # = λ t / N  (campbell_2019_qdrift.md, Thm 1)
    cumw::Vector{Float64}              # cumulative |a_j| for searchsortedfirst sampling
end

struct CompositePlan{W} <: EvolvePlan{W}
    ham::PauliSum{W}
    t::Float64
    steps::Int                         # outer iterations r
    K::Int                             # head size (terms 1:K of the sorted ham)
    N_B::Int
    outer::Vector{Tuple{Symbol,Float64}}   # (:A|:B, scale) — HW Def 5.1, exact (§5)
    head_sweep::Vector{Tuple{Int,Float64}} # order-2p inner sweep over terms 1:K, unit τ
    τ_B::Float64                       # per-sample tail angle at unit outer scale
    cumw_tail::Vector{Float64}
end
```

`trajectory(plan[, rng])` returns a lazy, type-stable iterator
(`Base.Iterators` composition for Trotter; a small custom stateful
iterator for the randomized plans — element type
`Tuple{Int,Float64}` in all cases). Memory never scales with `steps × L`:
the one-step sweep is shared across steps (the angles are step-independent
by construction), and qDrift samples stream.

`exp_count(plan)`:
- Trotter: `steps * length(sweep)` (= r·Υ·L′, L′ = non-identity terms);
- QDrift: `N`;
- Composite: `steps * (n_A * length(head_sweep) + n_B * N_B)` where
  `n_A`, `n_B` count `:A`/`:B` slots in `outer` — matching HW's
  Υ(ΥL_A + N_B) per iteration when `order` matches
  (hagan_wiebe_2023_composite.md, Thm 2.1 cost line).

### 1.3 Surface signature and the M10 sugar

```julia
function evolve!(x::QInt{W}, H, t::Real;
                 alg::Union{EvolveAlg,Nothing} = nothing,
                 ε::Union{Real,Nothing} = nothing,
                 steps::Union{Integer,Nothing} = nothing,
                 order::Union{Integer,Nothing} = nothing) where {W}
```

Resolution rules (all violations `throw` — fail fast, no silent
precedence):

1. `steps`/`order` given **and** `alg === nothing` ⇒ sugar:
   `alg = Trotter(order = something(order, 2), steps = something(steps, 1))`.
   This is *exactly* the M10 semantics for the calls M10 accepted
   (`steps` given ⇒ same circuit, bit for bit), so `test_m10_library.jl`
   and the PRD §7 examples pass unchanged.
2. `steps`/`order` given **and** `alg` given ⇒ `ArgumentError` ("pass the
   parameters inside the strategy: `Trotter(order=…, steps=…)`"). One
   spelling per meaning.
3. `alg === nothing` and no `steps`/`order` ⇒ `alg = Auto()`.
4. Any plan-side `nothing` (Auto always; `Trotter(steps=nothing)`;
   `QDrift(N=nothing)`; Composite gaps) requires `ε`; absent ⇒
   `ArgumentError("evolve!: give a target accuracy ε=… or explicit
   resources (steps=…/N=…)")`. **The bare call `evolve!(x, H, t)` now
   errors.** M10's silent `steps = 1` default was an unbounded-error
   placeholder; carrying it forward would be exactly the silent-fallback
   class the prompt bans. (M10's shipped tests always pass `steps`; the
   PRD example passes `steps = 40`.)
5. `ε` given **and** the plan has no free parameter ⇒ `ArgumentError`
   (a tolerance that cannot influence anything is a bug in the caller).
6. `ε` validation: `0 < ε`, finite. For `QDrift`-with-derived-N,
   additionally enforce Campbell's validity range `ε < λ|t| ln(2)/2`
   (campbell_2019_qdrift.md, Thm 1 / HW Thm 2.3 restatement) — outside
   it, `error()` naming the range; do not quietly return an N the theorem
   does not cover.
7. `t == 0` ⇒ return `x` untouched (exact). `t < 0` is legal everywhere
   (all bounds use `|t|`; angles carry the sign).

Execution: `ctx = _here(x)`; **DM context + randomized strategy ⇒
`error()`** ("a sampled trajectory is one unravelling, not the channel;
the DM lowering is M11's mixture value") — running one trajectory under
`density` would silently misrepresent the CPTP average, the exact bug
class Principle 1 exists to kill. Deterministic strategies run under
Eager and DM alike (unitary Ad, as today).

### 1.4 Control frames (forward ctrl-`evolve!`, Q10 half)

- `_pauli_exp!` switches its five emission sites from `apply!` to `_act!`
  (`surface/when.jl` — the control-aware sibling; controls become leading
  wires through the kernel `ctrl` choke point). The identity-word branch
  `gphase(−θ)` under a live frame correctly becomes a relative phase:
  `ctrl(gphase(α))` is already a real kernel operation
  (`kernel/constants.jl`). This makes **deterministic** `evolve!` legal
  inside `when` today — the QPE-on-`e^{−iHt}` follow-on needs no API
  change, only this substitution. Named test §8 (T9).
- **Randomized strategies assert an empty control stack**
  (`_assert_no_control`, same mechanism as the Bennett MBU exclusion,
  PRD-v2 §3.4). Physics: the qDrift guarantee is a *channel* statement
  (mixture of unitaries); `ctrl` of a mixture ≠ mixture of `ctrl`s —
  conditioning amplifies per-branch phase differences that the mixing
  lemma (campbell_2017_mixing_unitaries.md;
  hastings_2016_incoherent_errors.md) averages away only when
  unconditioned. Measurement-free, but still a non-unitary *effect* at
  the ensemble level: banned under a live frame (hard constraint), loud.

### 1.5 File layout and namespace

`src/library/evolve.jl` becomes a directory; `Sturm.jl` includes in
dependency order (matching the existing kernel/channel include style):

```
src/library/evolve/
  pauli.jl         # PauliWord{W} symplectic algebra (§2)
  hamiltonian.jl   # PauliTerm (kept), PauliSum{W}, normalization, tails
  alpha_comm.jl    # exact DP α_comm, first-order commutator sum (§4)
  suzuki.jl        # γ-recursion, sweep builder, Υ (§3)
  strategies.jl    # EvolveAlg types + validation (§1.1)
  plans.jl         # EvolvePlan structs, plan_evolution, exp_count, trajectory
  auto.jl          # the Auto dispatch rule (§6)
  evolve.jl        # _pauli_exp! (moved from M10 file, _act! switch), evolve! entry
```

- **Exported** (surface-adjacent library vocabulary, like `amplify`):
  `Trotter`, `QDrift`, `Composite`, `Auto` (`evolve!` already exported).
- **`public`** (reachable as `Sturm.…`, never dumped): `EvolveAlg`,
  `EvolvePlan`, `PauliSum`, `PauliWord`, `plan_evolution`, `trajectory`,
  `exp_count`, `trotter_steps`, `alpha_comm`, `qdrift_samples`,
  `suzuki_stage_scales`, plus the kept `PauliTerm`, `_pauli_exp!`.
- Core `Project.toml` unchanged: `Random` is a stdlib already implied by
  existing seeded machinery; **no new deps** (hard constraint).

---

## 2. Q2 — Hamiltonian representation: keep `PauliTerm` at the door, bitmask inside

**Decision: keep `(coeff, word::String)` as the *user input format*;
normalize once into a light library value `PauliSum{W}` whose terms carry
a symplectic bitmask `PauliWord{W}`.** No `Hamiltonian` kernel value
(hard constraint): `PauliSum` lives in `src/library/evolve/`, is `public`
not exported, and is accepted anywhere `H` is (idempotent
re-normalization).

```julia
"Symplectic (X|Z-mask) Pauli word on W wires; bit j (j=1 ⇒ MSB, matching the
M10 string convention char 1 = wire 1 = MSB) set in `x`/`z` iff the letter has
an X/Z component. Y = X∧Z. W ≤ 64 (error loudly beyond — UInt64 masks)."
struct PauliWord{W}
    x::UInt64
    z::UInt64
end

struct PauliSum{W}
    coeffs::Vector{Float64}       # SIGNED, sorted by |coeff| DESCENDING, merged
    words::Vector{PauliWord{W}}   # parallel; unique (duplicates summed, zeros dropped)
    λ::Float64                    # Σ |coeffs|  (identity excluded)
    c_I::Float64                  # identity-word coefficient, split out exactly
    tail_λ::Vector{Float64}       # tail_λ[K+1] = Σ_{j>K} |a_j|  (λ_K prefix table)
    tail_m2::Vector{Float64}      # tail second moments Σ_{j>K} a_j²  (optimal-K rule)
end
```

Why this and not strings all the way down / not a full symbolic layer:

- Every M12 requirement lands on one operation: **the product of two
  Pauli words is a Pauli word with a phase i^k, computed by two XORs and
  a popcount**; commutation is the symplectic form
  `popcount(p.x & q.z) − popcount(p.z & q.x) (mod 2)`. That single fact
  makes `‖[P,Q]‖ ∈ {0, 2}` *exact* and makes α_comm exactly computable
  (§4) — the "exact nested-commutator norms" requirement is unmeetable on
  strings without repeated O(W) parses, and overmet by any general
  symbolic-algebra dependency (banned anyway).
- Sorting, λ, `λ_K`, and tail second moments are precomputed prefix
  tables — `Auto` (§6) and the optimal-K rule read them in O(1) per K
  (zlokapa_2026_hamsim_lower_bounds.md, Lemma 7).
- **Identity handling is a correctness point, not an optimization**: the
  identity word commutes with everything and contributes only
  `gphase(−c_I t)`. It is split out and applied *once, exactly*, at the
  start of execution (through `_act!`, so it is a conditional phase under
  a future ctrl-`evolve!`). It is excluded from λ and from qDrift
  sampling — sampling the identity would waste budget and *loosen* the
  realized error relative to the quoted bound; excluding it is WLOG in
  campbell_2019_qdrift.md's own normalization. (M10 applied it per
  Trotter step; per-plan once is exactly equal and cheaper.)
- Negative coefficients: qDrift samples by |a_j| and folds `sign(a_j)`
  into the applied angle (the distribution `p_j = |a_j|/λ` with
  `exp(−i sign(a_j) τ P_j)`; campbell_2019_qdrift.md states the
  positive-coefficient form — the sign fold is the standard reduction,
  recorded in the distillation).

Migration from M10: `_normalize_hamiltonian(H, W)` becomes
`PauliSum{W}(H)` (accepting `Vector{PauliTerm}`, iterables of pairs, or a
`PauliSum` pass-through); the M10 function name is kept as a deprecated
internal alias for one milestone. `PauliTerm` remains `public` — its
docstring gains "input format; normalized to `PauliSum`". String↔mask
conversion is pinned in ONE place (`pauli.jl`) with a round-trip test —
the endianness pin (v0.1 lesson 6) lives there and nowhere else.

Merging changes observable behavior in one edge case: M10 applied
duplicate words as separate factors (equal circuit anyway, since equal
words commute) — merged is exactly equal by `e^{−iaP}e^{−ibP} =
e^{−i(a+b)P}`; document in the changelog note.

---

## 3. Q3 — Suzuki order-2p: runtime γ-recursion, not `Val` towers

The order-2p formula is represented as **a vector of stage scales**
`γ::Vector{Float64}` of length `5^{p−1}`, where each γᵢ scales one
*Strang* factor: `S_{2p}(τ) = Πᵢ S₂(γᵢ τ)` — the flattening of Suzuki's
fractal recursion (suzuki_1991_fractal_decomposition.md, Eqs. (1.1),
(3.14)–(3.16); the same recursion HW re-state as Def 5.1):

```julia
"suzuki_stage_scales(p) -> Vector{Float64}: the 5^{p−1} Strang scale factors of
the order-2p Suzuki formula. p=1 ⇒ [1.0]. Recursion: γ_{p} = [u_p·γ_{p−1};
u_p·γ_{p−1}; (1−4u_p)·γ_{p−1}; u_p·γ_{p−1}; u_p·γ_{p−1}], u_p = 1/(4−4^{1/(2p−1)})."
function suzuki_stage_scales(p::Int)::Vector{Float64}
```

- **Stage count**: each Strang factor is 2 sweeps of the term list, so
  the sweep count is Υ = 2·5^{p−1}, matching HW/ZAH exactly; the
  materialized one-step `sweep` in `TrotterPlan` has Υ·L′ entries built
  by `_build_sweep(ham, γ, τ)` — forward half-sweep then reverse
  half-sweep per γᵢ, i.e. M10's order-2 body under `γᵢτ`. M10's order-1
  and order-2 paths are the `p`-degenerate cases (order 1 = single
  forward sweep; order 2 = γ=[1.0]) — one code path, no special-casing
  beyond order 1's non-palindromic sweep.
- **Runtime, not `Val`-dispatch**: generation is O(5^{p−1}) ≤ 3125
  Float64s at the p ≤ 6 cap, done once per plan. No memoization, no
  global cache, no generated functions — recompute is cheaper than any
  cache's complexity. (`Val{p}` would buy nothing: no hot-path dispatch
  ever sees `p`.)
- **Exactness discipline**: `u_p` is irrational; coefficients are Float64
  evaluations of the *defining recursion* (not literals, not fitted).
  Two loud invariants at plan time (`error()` on violation, they cost
  microseconds): `|Σᵢ γᵢ − 1| ≤ 64·eps()·length(γ)` (first-order
  consistency) and palindromicity `γ == reverse(γ)` **exactly** (the
  recursion is structurally palindromic in exact arithmetic; the float
  evaluation preserves it bit-for-bit because mirrored entries are
  computed from identical subexpressions — assert `===`-level equality,
  and if an implementation detail ever breaks it, we want the crash).
  The *order* itself is pinned by the scaling signature test (§8 T2),
  which is immune to coefficient-magnitude conventions.
- `steps` derivation (`Trotter(steps=nothing)`): `trotter_steps(H, t, ε;
  order)` (public) returns
  `r = max(1, ceil(Int, (P̃(|t|)/ε)^{1/(2p)}))` with
  `P̃(t) = t^{2p+1} · (2Υ^{2p+1}/(2p+1)) · 2·α_comm(H, 2p)` — the HW
  Thm 2.1 head term specialized to the pure-Trotter partition (B = ∅), by
  default with **exact** α_comm (§4). Order 1 and 2 use the tight E1/E2
  bounds already distilled (childs_2019_trotter_error.md) — continuity
  with the M10 tests. RESEARCH STEP (R1): the order-2p prefactor must be
  transcribed from the hagan_wiebe_2023_composite.md distillation when
  Phase 0 lands, and cross-checked against Childs 2021 Thm 10/Eq. (189);
  the formula above is my reading of HW's proof chain
  (`main.tex` lines 536–539) and the implementer must verify the factor-2
  diamond-vs-spectral bookkeeping before shipping.

---

## 4. Q4 — Exact α_comm by symplectic dynamic programming

`α_comm(F, 2p) = Σ_{γ₁…γ_{2p+1}} (Π f_{γᵣ}) ‖[F_{γ_{2p+1}},[…,[F_{γ₂},F_{γ₁}]…]]‖`
(hagan_wiebe_2023_composite.md, Eq. def:alpha_comm; restated
zlokapa_2026_hamsim_lower_bounds.md App. A).

**Key fact**: for unit Pauli words, every nested commutator is either 0
or `2^{2p} ×` (a unit Pauli word) — each layer `[P, Q]` is `2·P·Q` when
the symplectic form is odd, 0 when even. So the (2p+1)-fold sum collapses
to a **measure propagation over words**:

```
μ₁(w_j)   = |a_j|                                    (merged ham ⇒ words unique)
μ_{r+1}(v) = Σ_{j} Σ_{w : anticomm(w_j, w), w_j·w = v}  |a_j| · μ_r(w)
α_comm(F, 2p) = 2^{2p} · Σ_v μ_{2p+1}(v)
```

Exactness: distinct index tuples reaching the same word simply add mass —
which is precisely what the defining sum does (each tuple contributes
`Πf · 2^{2p} · 1`). No norms of *sums* are ever taken, so no triangle
slack: this is the exact α_comm, not a bound.

- **Data structure**: `Dict{PauliWord{W},Float64}` per layer;
  `PauliWord` is `isbits`, hashes on two UInt64s. Cost per layer:
  `O(L · |support(μ_r)|)` dict ops.
- **Complexity guard (fail loud)**: `|support(μ_r)|` can grow toward
  `min(4^W, L^r)`. `alpha_comm(H; order, maxwords = 4_000_000)` tracks
  support size and **throws** a dedicated `AlphaCommBlowup <: Exception`
  (message: support size, layer reached, and the two explicit outs) when
  exceeded. The two outs are *explicit opt-ins*, never substitutions:
  `alpha_comm(H; order, mode = :norm1)` returns the HW Lemma 5.2 bound
  `2^{2p} λ^{2p+1}` (and mixed variant), clearly a **bound, not the
  value**, and callers of `trotter_steps`/`plan_evolution` must pass
  `alpha_mode = :norm1` themselves to use it. The v0.1 `alpha_comm` p≥3
  silent-1e9×-substitution bug (prompt, banned class) is structurally
  impossible: there is no code path from `:exact` to `:norm1` without the
  caller spelling it.
- **Mixed sum** `α_comm({A,B}, 2p)` ("at least one index from each
  side"): by inclusion–exclusion over three DP runs,
  `α_mixed = α_comm(A∪B) − α_comm(A) − α_comm(B)` — valid because each
  tuple's contribution is label-independent. Three runs share the guard.
- **First order** keeps the tight pair sum
  `Σ_{i<j} ‖[Hᵢ,Hⱼ]‖ = Σ_{i<j: anticomm} 2|aᵢ||aⱼ|` (E1,
  childs_2019_trotter_error.md) — O(L²) with an early-exit commuting
  check; also the O(L²) "is the whole Hamiltonian commuting?" predicate
  `iscommuting(ps)` that Auto's exact fast path uses (§6). L² at the cap
  `L ≤ 10⁴` is ~10⁸ popcounts — sub-second, and Auto only runs it below
  a size gate (`L ≤ 2048`, else skip the fast path — skipping a fast
  path is not a silent bound substitution).
- API: `trotter_steps(H, t, ε; order = 2, alpha_mode = :exact)` (public,
  Q4's requested entry), used by planning and directly by users sizing
  experiments.

---

## 5. Q5/Q6 — QDrift and Composite planning

### 5.1 QDrift

- **N selection** (`N === nothing`): `N = clamp(ceil(Int, 4λ²t²/ε), 1, typemax(Int))`
  under the validity check §1.3(6) (campbell_2019_qdrift.md Thm 1:
  ε_⋄ ≤ (2λ²t²/N)e^{2λt/N}; the clean sufficient choice N = ⌈4λ²t²/ε⌉ is
  HW's Thm 2.3 restatement, valid for ε < λt ln 2 / 2). The *full*
  bound with the `e^{2λt/N}` factor is what the conformance test asserts
  (§8 T5) — untuned.
- **Sampler**: `cumw` cumulative |a| table; one sample =
  `searchsortedfirst(cumw, ξ·λ)` with `ξ = rand(rng)` — O(log L),
  allocation-free, RNG explicit. Every sample applies angle
  `θ = sign(a_j) · λ|t|·sign(t)/N` — wait, uniformly: `θ_j = sign(a_j) · λ t / N`;
  the applied exponential is `exp(−i θ_j P_j)` via the existing
  `_pauli_exp!` with unit coefficient folded (implementation: call with
  `(term = j, θ = sign(a_j)·λt/N)`; `_pauli_exp!` takes the
  angle-resolved form in M12 — see §1.2 trajectory element type).
- **Who owns the shot loop**: `shots` does, unchanged. `evolve!` runs
  ONE trajectory per call; under `eager`/`shots` each run draws fresh
  samples from the context RNG (or the pinned strategy RNG). The
  docstring states the contract in one sentence: *the guarantee is for
  the shot-averaged channel (diamond ε); a single trajectory's operator
  error is typically ~√ε* (campbell_2019_qdrift.md "Diamond norm
  distance" discussion; chen_2021_concentration_random_products.md for
  why typical ≈ average — concentration of random products). This is the
  documented trajectory-level semantics of Tobias's decision 3.

### 5.2 Composite

- **Interleaving schedule — exact, materialized** (v0.1 lesson 3: the
  `max(1, total÷steps)` truncation class is banned). The outer schedule
  is HW Def 5.1 verbatim, built by the *same* recursion code as §3
  operating on slot lists instead of scalars:
  base `outer₂ = [(:A,½), (:B,½), (:B,½), (:A,½)]`; recursion
  `outer_{2p} = [u_p·outer_{2p−2}; u_p·…; (1−4u_p)·…; u_p·…; u_p·…]`
  (scales multiply). Invariants asserted at plan time:
  `Σ_{:A} scale == Σ_{:B} scale == 1` (within 64·eps·len), slot count
  `= 2Υ_outer`, palindromic. Adjacent `(:B,·),(:B,·)` slots are **not**
  merged — HW's error analysis composes them as separate channels and the
  cost count follows their Υ(ΥL_A + N_B); merging would be an unproven
  "optimization" of exactly the kind lesson 3 warns about.
- Per outer iteration (`steps = r` of them, each at time `t/r`): an `:A`
  slot replays `head_sweep` (the order-2p inner Suzuki over terms `1:K`)
  at `scale·t/r`; a `:B` slot draws `N_B` **fresh** samples from the tail
  distribution at per-sample angle `sign(a_j)·λ_B·scale·t/(r·N_B)`.
  Fresh randomness per slot per iteration — the qDrift channel bound is
  per-composition i.i.d. (campbell_2019_qdrift.md Thm 1 composition
  step).
- **Head/tail split** (`K === nothing`): the sorted-prefix rule from the
  optimal-K lemma (zlokapa_2026_hamsim_lower_bounds.md Lemma 7 — the cut
  is where the *tail second moment* crosses ε):
  normalize `s_j = a_j/λ`, `T = λ|t|`, and choose
  `K = min { K : Σ_{j>K} s_j² ≤ ε̂ }` with `ε̂ = ε/T²` — read off the
  precomputed `tail_m2` table in O(log L). Then refine by direct
  minimization of the surrogate cost
  `C(K) = Υ(ΥK + N_B(K)) · (r_head(K) + 4Υλ_K²t²/(N_B(K)ε))`-shaped
  objective over the O(log)-neighborhood of that K (cheap: prefix
  tables; the surrogate uses the norm-bound commutator term exactly as
  ZAH's App. A derivation does, Eqs. HW-comm-bound → fixed-p-bound).
  Endpoint degeneracies handled loudly: `K == 0` ⇒ plan is *identical* to
  `QDrift` (planning returns a `QDriftPlan` — one execution path, no
  duplicated code); `K == L` ⇒ `TrotterPlan`.
- **N_B** (`N_B === nothing`): `N_B = max(K, 1)` — ZAH App. A's choice
  ("Choosing N_B = K in Fact 4"), which balances Fact HW's last term
  `4Υλ_B²t²/(N_Bε)` against the head cost and yields the frontier
  Eq. (composite). Users may override; the plan records the realized
  per-iteration error split so bench can report it.
- **steps** (`steps === nothing`): HW's proof gives the exact recipe
  (main.tex Eqs. rminBound/intermediate):
  `r = ⌈ (P(t)/ε)^{1/2p} + Q(t)/ε ⌉` with
  `P(t) = t^{2p+1} (4Υ^{2p+1}/(2p+1)) (Υ α_comm(A,2p) + α_comm({A,B},2p))`
  and `Q(t) = 4Υλ_B²t²/N_B`. Default uses **exact** α_comm on the head
  (K is small by construction — that is the whole point of the
  composite; the DP guard §4 still applies), and exact mixed α via
  inclusion–exclusion. `alpha_mode = :norm1` opt-out as in §4.
- **User surface** (what may be overridden): `order`, `K`, `N_B`,
  `steps`, `rng` — every symbol in HW Thm 2.1, nothing else. No
  probabilistic partitioning (HW §5.2) in M12: it optimizes an
  *expected* cost with random partitions; the deterministic largest-K
  split is what ZAH prove sits on the frontier, it is reproducible, and
  it keeps `Composite` a value. (Flagged as a possible M13 strategy,
  alongside the optional 1805.08385/1910.06255 — none proposed now; they
  don't fit the "plan is deterministic-cost" invariant as cleanly:
  SparSto's gate count is a random variable, HW's own objection.)

---

## 6. Q7 — `Auto`: a decision rule you can read off the frontier

`plan_evolution(::Auto, ham, t, ε)` — pure, O(L log L), fully testable
without a context. In order:

1. **Exactness fast paths** (physics, not heuristics):
   `L′ == 1` ⇒ `Trotter(order=1, steps=1)` — a single Pauli exponential
   is exact. `iscommuting(ham)` (gated `L ≤ 2048`, §4) ⇒
   `Trotter(order=1, steps=1)` — commuting terms make S₁ exact
   (α_comm ≡ 0; the bound machinery must and does return r = 1 here
   without dividing by zero — a named test).
2. **Candidate costs** in the paper's unit (operator exponentials), using
   the *norm-bound* commutator surrogates (Auto never runs the DP — its
   job is O(L log L) dispatch; the chosen strategy's *planning* then uses
   exact α where §5 says so):
   - `C_QD = ⌈4λ²t²/ε⌉` (campbell_2019_qdrift.md Thm 1);
   - `C_Trott(2p)` for `p ∈ (1, 2, 3)` via §3's step rule with
     `:norm1` α (hagan_wiebe_2023_composite.md Lemma 5.2);
   - `C_comp(K*, 2p)` for `p ∈ (1, 2, 3)` with K* from §5.2's
     second-moment rule and `N_B = max(K*,1)` — the ZAH App. A
     instantiation of Fact HW, evaluated on prefix tables.
3. **Pick the argmin.** Tie-break order (lens: reproducibility first):
   deterministic beats randomized at equal cost; lower order beats
   higher (smaller constants, shallower recursion); `Trotter` beats
   `Composite` (fewer moving parts). Emit the chosen concrete plan.
4. The decision boundary is **testable against benchmarks by
   construction**: Auto minimizes the same `min_K(Kt(t/ε)^{1/2p} +
   t²λ_K²/ε)` objective that the bench frontier protocol (§9) measures —
   zlokapa_2026_hamsim_lower_bounds.md Eqs. (composite)/(lb) say no
   strategy in this class can beat that curve, so "Auto within a small
   factor of best measured" is a *stable* assertion, not a tuned one.
   Bench asserts factor ≤ 2 over the model-family grid (§9); CI asserts
   only the classical selection logic (§8 T7) — no quantum execution in
   the Auto CI tests.

`Auto` requires `ε` (§1.3 rule 4). `Auto` deliberately has **no
fields** in M12: anything tunable belongs on the concrete strategies;
if a future need appears (e.g. `Auto(prefer = :deterministic)`), fields
can be added without breaking `Auto()` — kwargs-with-defaults on a
zero-field struct is the forward-compatible Julia shape.

---

## 7. Q8 — Verification architecture

Design principle (v0.1 lessons 1/2/4): **deterministic full-operator and
full-superoperator comparisons are the default tier; statistics are a
supplement; marginals are never load-bearing.** The plan/trajectory split
makes the randomized strategies testable *without* sampling noise: the
ensemble average is built by exact superoperator arithmetic, and
individual trajectories are pinned by seeded replay.

Harness additions (test-side only, extending `test_m10_library.jl`'s
tooling; nothing ships in `src/`):

- `dense_word(w::PauliWord)` / `dense_step_channel(ham, plan)` — dense
  4^W×4^W superoperator `Φ_step = Σ_j p_j conj(U_j) ⊗ U_j` for one
  qDrift step; `Φ_N = Φ_step^N`. W ≤ 3 ⇒ ≤ 64×64 matrix powers:
  milliseconds, exact, no sampling (v0.1 lesson 5 killed by
  construction).
- Choi comparison via the existing normalized-Jamiołkowski conventions
  in `test/choi.jl`; the assertable direction is
  `‖J(Φ_impl) − J(Φ_ideal)‖₁ ≤ ‖Φ_impl − Φ_ideal‖_⋄ ≤ bound` — we assert
  the Choi-trace-norm consequence of the cited diamond bound (sound: Choi
  distance lower-bounds diamond), and separately assert the *scaling* in
  N, which no norm-gap can fake.

Named tests (CI tier unless marked HEAVY; every bound untuned — computed
from the cited inequality with the actual λ, α_comm, t, ε):

| ID | What | Method |
|---|---|---|
| T1 `M12.PAULI.ALGEBRA` | symplectic product/commutator/phase vs dense kron on random words, W ≤ 6; string↔mask round-trip; MSB pin | exact equality |
| T2 `M12.SUZUKI.COEFFS` | γ invariants (Σ=1, palindrome, count 5^{p−1}, u_p closed form, p=1,2,3); order-2p **scaling signature** vs `expm`: doubling r divides `dist_upto_phase` by ≈ 2^{2p} (order 4 ⇒ ≈16) | op_matrix (M10 harness) + ratio bands |
| T3 `M12.TROTTER.BOUND` | order 1/2 keep E1/E2 (M10 tests untouched); order 4: dist ≤ the §3 bound with **exact** α_comm | full-operator, untuned |
| T4 `M12.ALPHA.EXACT` | DP vs brute-force tuple enumeration (L ≤ 4, p ≤ 2); commuting family ⇒ 0; hand-computed 2-term value; `AlphaCommBlowup` fires at a tiny `maxwords`; `:norm1` ≥ `:exact` always | pure classical |
| T5 `M12.QDRIFT.CHANNEL` | exact `Φ_step^N` vs ideal: Choi distance ≤ 2·N·(2λ²t²/N²)e^{2λt/N} (campbell_2019_qdrift.md Thm 1 chain, full exponential form); **N-scaling**: error ∝ 1/N | superoperator power, deterministic |
| T6 `M12.QDRIFT.TRAJECTORY` | seeded `trajectory(plan, MersenneTwister(s))` replayed two ways: (a) `op_matrix` realized unitary == dense `Π exp(−iθP)` of the *same* sampled sequence (ordering pinned — v0.1 GQSP lesson 2), (b) sample histogram of term draws ≈ p_j (χ², supplement) | full-operator + statistical supplement |
| T7 `M12.AUTO.DISPATCH` | constructed coefficient families (uniform ⇒ pure QDrift or pure Trotter per regime; exponential tail ⇒ K ~ log₂L; power-law ⇒ interior K matching Lemma 7's second-moment window ε ∈ [Σ_{j>K}a_j², a_K²+2a_Kλ_K]); exactness fast paths | pure classical, no context |
| T8 `M12.COMPOSITE.SCHEDULE` | outer slot list vs HW Def 5.1 by hand for 2p = 2, 4; Σ scales exact; `exp_count(plan) == length(collect(trajectory(plan, rng)))` for all three strategies; no-truncation property under adversarial (r, N_B) | pure classical |
| T9 `M12.CTRL.EVOLVE` | deterministic `evolve!` inside `when(c)` == dense `ctrl(exp(−iHt))` block (op_matrix on control+register, up-to-phase); identity-term gphase becomes the correct relative phase | full-operator |
| T10 `M12.GUARDRAIL` | `QDrift`/`Composite` inside `when` ⇒ throws (`_assert_no_control`); randomized under `density()` ⇒ throws (M11 message); bare `evolve!(x,H,t)` ⇒ ArgumentError; steps+alg double-spec ⇒ ArgumentError; ε out of Campbell range ⇒ error | exception tests |
| T11 `M12.COMPOSITE.CHANNEL` | W = 2–3, K = 1, N_B ∈ {1,2}, 2p = 2: exact averaged superoperator (A-slots dense unitary, B-slots `Φ_step` powers, composed per the outer schedule) vs ideal; ≤ HW Thm 2.1 per-iteration bound composed r times; r-scaling | superoperator, deterministic |
| T12 `M12.EVOLVE.SUGAR` | `steps`/`order` kwargs produce circuits identical to M10 (op_matrix equality vs the frozen M10 expectation) | regression |
| H1 `M12.HEAVY.SHOTS` (HEAVY) | `shots`-level statistical validation: observable means over ≥ 1000 seeded trajectories within the diamond-implied 2ε of ideal (campbell_2019_qdrift.md measurement discussion); typicality spread ~√ε (chen_2021_concentration_random_products.md) | statistical, gated |

Tiering: T1–T12 are CI (all deterministic or tiny-χ²; W ≤ 3; total
target < 60 s added to the suite). H1 and everything in `bench/` run only
under `ENV["STURM_HEAVY"] == "1"` or from `bench/` — the 13-minute-CI-kill
class (lesson 5) is structurally out of CI. Citation lint: every new file
cites its `docs/physics/*.md` names; the runtests boot lint already
enforces resolution.

---

## 8. Q9 — `bench/` design

```
bench/
  Project.toml         # deps: Sturm (develop ..), LinearAlgebra, Random,
                       #   Printf, Statistics — stdlib-only beyond Sturm.
  hamsim/
    families.jl        # model Hamiltonians: coefficient tails × word ensembles
    groundtruth.jl     # dense expm / superoperator machinery (shared w/ tests via include)
    frontier.jl        # the frontier-curve protocol
    run.jl             # CLI entry: julia --project=bench bench/hamsim/run.jl > results.csv
```

- **Own environment** (hard constraint): core `Project.toml` untouched.
  No plotting dependency — emit CSV/TSV; plots are a human afterstep.
  (If Tobias wants in-repo plots later, that is a bench-env-only
  UnicodePlots line, one `Pkg.add` away — deliberately not proposed now.)
- **Metric**: operator-exponential count = `exp_count(plan)` — the
  paper's unit, computed from the plan (§0.3), *zero* hot-path
  instrumentation. A bench self-check re-asserts plan-count ==
  trajectory-length on every configuration it runs (cheap, and it is the
  one invariant that keeps the whole report honest).
- **Model families** (coefficient tails, per the prompt): for L ∈
  {16, 64, 256, 1024}: uniform `a_j = 1/L`; power-law `a_j ∝ j^{−γ}`,
  γ ∈ {0.5, 1, 2}; exponential `a_j ∝ 2^{−j}`. Words: random 2-local
  Pauli strings on W ∈ {2, 3} wires for *executed* runs; W ∈ {8, 12} for
  *analytic-only* cost curves (no execution needed — costs come from
  plans). Seeded generation, fixed in `families.jl`.
- **Frontier protocol**: for each (family, t, ε) on a log grid
  (t ∈ [0.5, 32], ε ∈ [1e-1, 1e-5]):
  1. *measured-error mode* (W ≤ 3 only): binary-search the minimal
     r (Trotter) / N (qDrift) / (r, fixed K, N_B) (Composite) whose exact
     superoperator Choi distance ≤ ε — the *empirical* cost;
  2. *bound mode* (all W, L): `exp_count(plan_evolution(alg, …, ε))` —
     the certified cost;
  3. report both against the frontier curve
     `min_K(Kt + t²λ_K²/ε)` (zlokapa_2026_hamsim_lower_bounds.md
     Eq. (lb)) and the analytic QSP/LCU curve `L(t + log(1/ε)/log log(1/ε))`
     (their Eq. (qsp)) as an overlay — analytic only, per Tobias's
     decision 2 (no implementation).
  The bound/empirical gap column is the standing measure of our
  constants' looseness — v0.1's 1e9× class would be a screaming outlier
  in this table, which is the point.
- **Auto boundary**: assert `exp_count(Auto plan) ≤ 2 × min(measured
  best)` across the executed grid; report (family, t, ε) cells where
  Auto's *choice* differs from the measured argmin (expected near
  crossovers; the report makes the boundary visible so the §6 tie-break
  can be revisited with data).

---

## 9. Q10 — Forward compatibility (M11 mixtures; ctrl-`evolve!`)

- **M11 lowering, per strategy**: the plan is the channel description.
  `TrotterPlan` denotes a unitary — already realizable as a certified
  `UnitaryBlock` via `trace`/`within` when someone needs it (no M12
  work). `QDriftPlan` denotes `(Σ_j p_j 𝒰_j)^{∘N}` — M11 lowers it to N
  `NoiseN` nodes each carrying the mixed-unitary `KrausFamily`
  `{√p_j U_j}` (the seam and the barrier semantics exist today in
  `channel/dag.jl`; `certify` refuses it by design — correct: the
  ensemble is not a process value, hard constraint). `CompositePlan`
  interleaves ApplyN runs (A-slots) with those NoiseN nodes per the
  `outer` schedule. The M12 deliverable that makes this zero-surface-cost
  is precisely that plans are *data*: M11 adds `channel(plan)` /
  `_replay_dm!` support without touching `evolve!`, the strategies, or
  any test above T-level.
- **ctrl-`evolve!`**: enabled for deterministic strategies in M12 itself
  (§1.4, `_act!` switch + T9). Nothing in the design assumes
  top-levelness: plans don't know about control; the executor's
  `_pauli_exp!` goes through the `ctrl` choke point like every other
  library body; the *only* control-sensitive decision is the randomized
  guardrail, which is physics (mixing lemma scope), not API debt — and
  when M11 mixture values exist, a future *derandomized* ctrl story
  (e.g. LCU-style) can lift it without changing `evolve!`'s signature.
- **Shape stability**: `Auto()` zero-field (§6), strategies
  kwargs-constructed (fields appendable), plans `public` (not exported —
  their fields may evolve), `ε` a kwarg (an `alg`-embedded tolerance was
  considered and rejected: the tolerance is a property of the *call*,
  the strategy is a property of the *method* — and this keeps
  `Trotter(order=4)` reusable across calls at different accuracy).

---

## 10. Error taxonomy (fail fast, one place)

New exception types (library-level, `public`): `AlphaCommBlowup` (§4).
Everything else uses stock types with mandatory-content messages:
`DomainError` (constructor validation), `ArgumentError` (call-shape
rules §1.3), `DimensionMismatch` (word length ≠ W, kept from M10),
`error()` with named-context strings for: DM+randomized (names M11),
Campbell ε-range, order cap, W > 64. No `@warn`-and-continue anywhere in
M12 — there is no implicit-cast analogue here; every degraded mode is an
explicit argument (`alpha_mode = :norm1`).

---

## 11. Open questions / explicit research steps (Principle 8)

- **R1** (§3): transcribe and verify the order-2p pure-Trotter step-count
  prefactor from hagan_wiebe_2023_composite.md ↔ Childs 2021 Thm 10 /
  Eq. (189) when the Phase-0 distillation lands; my P̃(t) above is
  derived from HW main.tex lines 536–539 and needs the diamond-vs-spectral
  factor-2 audit before any bound test cites it.
- **R2**: pin the mixing-lemma constants (Campbell 2017: diamond distance
  ≤ a² + 2b form) in campbell_2017_mixing_unitaries.md — used only in
  docstrings/derivation notes here (qDrift's own Thm 1 is self-contained),
  but the H1 typicality supplement's √ε claim should cite the exact
  statement from chen_2021_concentration_random_products.md.
- **R3**: verify the clean-ancilla/§3.9 interaction of `_pauli_exp!`
  under a live control frame (the CNOT-ladder wires are register wires,
  not ancillae, so the §3.9 witness should be untouched — verify against
  the M5 guardrail tests before landing T9).
- **R4**: `tail_m2`/`tail_λ` prefix tables assume the merged, sorted
  representation is the one all strategies index into — confirm no
  strategy ever needs the *user's* term order (I believe none does; the
  trajectory reports indices into the sorted `PauliSum`, and T6's replay
  uses the same indexing).
- **R5**: DP `maxwords` default (4e6 words ≈ 100 MB dict) and the Auto
  commuting-check gate (L ≤ 2048) are proposed engineering constants —
  implementer may tune with a benchmark, but both must stay *loud* caps.
- **R6**: whether `Composite` with `K = 0`/`K = L` returning
  `QDriftPlan`/`TrotterPlan` (§5.2) should be reflected in the *return
  type* of `plan_evolution` (small union) or via a wrapper plan — I
  propose the small union (3 concrete types; call sites are
  type-stable-enough behind a function barrier, standard Julia practice).

---

## 12. Citation map (code → docs/physics/)

| Code site | Citation |
|---|---|
| `suzuki.jl` γ-recursion, Υ | suzuki_1991_fractal_decomposition.md (Eqs. 1.1, 3.14–3.16) |
| `trotter_steps`, T3 bounds | childs_2019_trotter_error.md (E1/E2); hagan_wiebe_2023_composite.md (order-2p, R1) |
| `qdrift` N-rule, τ = λt/N, T5 | campbell_2019_qdrift.md (Thm 1, p_j = a_j/λ, ε-range) |
| trajectory-vs-channel docstring | campbell_2019_qdrift.md (diamond discussion); chen_2021_concentration_random_products.md |
| mixture soundness notes | campbell_2017_mixing_unitaries.md; hastings_2016_incoherent_errors.md |
| `composite.jl` outer schedule, cost, N_B | hagan_wiebe_2023_composite.md (Def 5.1, Thm 2.1); zlokapa_2026_hamsim_lower_bounds.md (App. A, N_B = K) |
| `auto.jl` K-rule, frontier | zlokapa_2026_hamsim_lower_bounds.md (Lemma 7, Eqs. composite/lb/qsp) |
| `alpha_comm.jl` definition | hagan_wiebe_2023_composite.md (Eq. def:alpha_comm, Lemma 5.2) |
