# M12 Proposal A — Hamiltonian-Simulation Strategy Layer (bead Sturm.jl-bog7)

**Proposer A. Lens: PHYSICS-FIRST.** Exactness of the error-bound machinery is
the organizing principle: exact Suzuki coefficients (closed form, never
tabulated decimals), exact symbolic Pauli-algebra commutator sums (no norm
estimation, no cancellation subtleties), and provable conformance of every
strategy to its cited bound. The API serves the physics; every derived
resource count (steps, samples, partition) carries its formula and citation
as data.

Ground truth read for this proposal: `src/library/evolve.jl` (M10 seed),
`src/library/{grover.jl,qpe.jl}`, `src/surface/cases.jl` (`shots`),
`src/context/{abstract,eager,density}.jl`, `src/channel/dag.jl`,
`test/test_m10_library.jl` (op_matrix harness), `test/choi.jl`,
`test/runtests.jl` (boot lints); papers 2607.19852 (`lbhs.tex`, Fact HW =
Hagan–Wiebe Thm 2.1 as re-derived in their Appendix A, Lemma `optimal_k`),
2206.06409 (`main.tex`, Thm `higher_order_cost_fixed`, Def
`higher_order_loop`, Thm `trotter_cost`, Thm `QDrift`, Eq `def:alpha_comm`),
1811.08017 (`qDRIFT_arXiv_V2submit.tex`, Thm 1 + the exact appendix series),
1912.08854 via `docs/physics/childs_2019_trotter_error.md`, Suzuki 1991
(recursive fractal decomposition), 1612.02689, 1612.01011, 2008.11751.

Citations below use the Phase-0 distillation names (per the proposer prompt):
`campbell_2019_qdrift.md`, `campbell_2017_mixing_unitaries.md`,
`hastings_2016_incoherent_errors.md`, `hagan_wiebe_2023_composite.md`,
`chen_2021_concentration_random_products.md`,
`zlokapa_2026_hamsim_lower_bounds.md`, `suzuki_1991_fractal_decomposition.md`,
plus the existing `childs_2019_trotter_error.md`.

---

## 0. The four structural decisions (everything else follows)

**D-A1. Pure schedule builders; dumb executor.** Every strategy compiles to a
`Schedule::Vector{StageExp}` by a PURE classical function — all Suzuki stage
arithmetic, all interleaving, all random sampling (explicit RNG in, schedule
out) happens with no quantum context in sight. The quantum executor is a
trivial interpreter: one `_word_exp!` per entry. Consequences: (a) v0.1
lesson 3 (silently truncated interleave remainders) becomes a *unit-testable
arithmetic property* — exact exponential counts, exact duration sums, no
`max(1, total÷steps)` class of bug can hide; (b) the operator-exponential
count (the papers' cost unit) is `length(schedule)` — the benchmark counter
costs nothing and cannot pollute the hot path; (c) M11 forward-compatibility
is the schedule, not the executor (§10).

**D-A2. Exact symbolic Pauli algebra.** `PauliWord{W}` is a symplectic
(x,z)-bitmask pair. Products, commutators, and nested-commutator norms of
Pauli strings are exact integer/scalar computations. `alpha_comm` is computed
EXACTLY by a transfer-map over product words (§4) — possible only because
α_comm is a sum of per-tuple norms (all nonnegative, no cancellation), and
the nested commutator of Pauli strings is again a single Pauli string up to
scalar. No norm is ever numerically estimated in a bound.

**D-A3. One ε convention, pinned: the FULL diamond norm ‖·‖_⋄.** Campbell
1811.08017 states his Thm 1 in the halved diamond *distance* d_⋄ = ½‖·‖_⋄;
Hagan–Wiebe and Zlokapa use the full norm. Mixing conventions is a silent
factor-of-2 — exactly the class of slip Principle 3 exists to kill. M12 pins:
`ε` everywhere means full ‖·‖_⋄; the unitary-spectral-to-diamond conversion
‖U − V‖_⋄ ≤ 2‖U − V‖_∞ lives in ONE function (`_diamond_from_spectral`,
bounds.jl) with the derivation cited (hagan_wiebe_2023_composite.md, Eqs
`diamond_to_spectral_start`–`TS_intermediate_1`). Under this convention
Campbell's N and HW's N agree: N = 4λ²t²/ε (asymptotic), and the exact
criterion is 2N(e^{2λt/N} − 1 − 2λt/N) ≤ ε (§5).

**D-A4. Bounds are auditable data.** Every derived resource passes through a
`BoundReport` (value, formula symbol, citation string, input NamedTuple);
`Auto` returns an `EvolvePlan` whose comparison table is a first-class public
object. Bound-conformance tests assert against these reports, so a formula
change that breaks a bound breaks a named test, not a benchmark someday.

---

## 1. Strategy types, surface, and file layout (Q1)

### 1.1 Files

`src/library/evolve.jl` becomes a subdirectory (include order as listed):

```
src/library/evolve/
  pauli.jl      # PauliWord{W}, PauliSum{W}, symplectic algebra, parsing
  suzuki.jl     # Sweep, suzuki_sweeps(p), u_p closed form, BigFloat twin
  bounds.jl     # alpha_comm engine, trotter_steps, qdrift_samples,
                #   composite resources (Fact HW), BoundReport,
                #   _diamond_from_spectral (THE factor-2 pin)
  schedule.jl   # StageExp, Schedule, build_schedule methods (pure)
  executor.jl   # _word_exp! (M10 _pauli_exp! generalized), _execute!
  evolve.jl     # strategy structs, validation, sugar, evolve! entry
  auto.jl       # evolve_plan, Auto dispatch
```

`_pauli_exp!`'s N&C §4.7.3 lowering (basis change → CNOT ladder → Rz(2θ) →
uncompute) moves to `executor.jl` verbatim as `_word_exp!(ctx, x,
w::PauliWord{W}, θ)` — the angle is the full θ of exp(−iθP), coefficient and
duration pre-folded by the schedule builder. It is already tested (M10) and is
NOT redesigned. Library layer only: kernel, types, contexts, FFI untouched —
so this round is 2-proposer by prudence (novel error-bound machinery), not
because the 3+1 rule forces it; the implementer synthesises as usual.

### 1.2 Strategy structs

```julia
abstract type EvolveAlg end

"Deterministic Suzuki product formula. order ∈ {1} ∪ {2,4,6,…} (order = 2k)."
struct Trotter <: EvolveAlg
    order::Int
    steps::Union{Int,Nothing}      # explicit r …
    eps::Union{Float64,Nothing}    # … XOR target full-diamond ε (r derived, §4)
    alpha_upper::Union{Float64,Nothing}  # optional user-certified UPPER bound on α_comm
    budget::Int                    # α_comm state-space budget (§4); default ALPHA_BUDGET
end
Trotter(; order = 2, steps = nothing, eps = nothing,
          alpha_upper = nothing, budget = ALPHA_BUDGET)

"Campbell's qDRIFT: N i.i.d. samples j ~ |a_j|/λ, each exp(∓i (λt/N) P_j)."
struct QDrift <: EvolveAlg
    N::Union{Int,Nothing}          # explicit sample count …
    eps::Union{Float64,Nothing}    # … XOR target ε (N from the EXACT criterion, §5)
    rng::Any                       # nothing ⇒ the context core's rng (abstract.jl)
end
QDrift(; N = nothing, eps = nothing, rng = nothing)

"Hagan–Wiebe composite: order-2p Suzuki head (largest-K terms) ⊗ qDrift tail."
struct Composite <: EvolveAlg
    order::Int                     # 2p, head/outer Suzuki order (even ≥ 2)
    K::Union{Int,Nothing}          # head size in canonical (|a|-desc) order; nothing ⇒ scan (§6)
    N_B::Union{Int,Nothing}        # qDrift samples PER B-block; nothing ⇒ cost-optimal (§6)
    steps::Union{Int,Nothing}      # outer r; nothing ⇒ Fact HW from ε
    eps::Union{Float64,Nothing}
    rng::Any
    alpha_upper::Union{Float64,Nothing}
    budget::Int
end

"Pick the proven-cost argmin among candidate strategies (§7)."
struct Auto <: EvolveAlg
    eps::Float64                   # DEFAULT 1e-3 (documented; orchestrator may re-rule)
    budget::Int
    rng::Any
end
Auto(; eps = 1e-3, budget = ALPHA_BUDGET, rng = nothing)
```

Validation (inner constructors, FAIL FAST — every violation `throw`s):
- `Trotter`: `order == 1 || (iseven(order) && order ≥ 2)`; exactly one of
  `steps`/`eps` supplied; `steps ≥ 1`; `eps > 0`. There is NO order cap and
  NO silent order fallback — any even order runs (Suzuki recursion is closed
  form for all p); only the α_comm *budget* can refuse, and it refuses loudly.
- `QDrift`: exactly one of `N`/`eps`; `N ≥ 1`.
- `Composite`: if `eps === nothing` then ALL of `K`, `N_B`, `steps` must be
  given (fully manual); with `eps`, any subset of `K`/`N_B`/`steps` may be
  pinned and the rest is derived. `0 ≤ K ≤ L` checked at normalize time.
  `K == L` and `K == 0` are legal degenerations (pure Trotter / pure qDrift)
  and are TESTED to produce schedules identical to those strategies.
- ε is full diamond norm ‖·‖_⋄ (D-A3) — stated in every docstring.

Field spelling `eps` not `ε` in struct fields (ASCII fields, Unicode in docs);
kwarg accepts both via `ε = nothing` alias? No — ONE spelling, `eps`, to avoid
a dual-kwarg trap. (Julia idiomaticity: match `Base.eps` familiarity.)

### 1.3 Surface signature and sugar

```julia
evolve!(x::QInt{W}, H, t::Real;
        alg::Union{EvolveAlg,Nothing} = nothing,
        steps = nothing, order = nothing) -> x
```

- `steps`/`order` given (M10 sugar): `alg` must be `nothing` (else
  `ArgumentError` — over-specified); maps to
  `Trotter(order = something(order, 2), steps = something(steps, 1))`.
  Byte-for-byte M10 semantics for every existing call with kwargs (the M10
  default `steps = 1, order = 2` is reproduced by the sugar defaults).
- nothing given: `alg = Auto()` (Tobias's decision 1). NOTE: this changes the
  meaning of a *bare* `evolve!(x, H, t)` from M10's single Strang step to
  Auto at ε = 1e-3. `test_prd_examples.jl` must be re-run; the §5/§7 PRD
  examples pass `steps`, so the sugar path preserves them. Flagged for the
  implementer to verify (research step R6).
- Entry guards: `_assert_no_control(ctx, "evolve! (Hamiltonian simulation)")`
  for ALL strategies (M10 stance: `evolve!` is a top-level generator;
  ctrl-`evolve!` is a follow-on — §10), then `_here(x)`, then Hamiltonian
  normalization, then `build_schedule`, then `_execute!`.

Exported: `Trotter`, `QDrift`, `Composite`, `Auto` (they are the user-facing
vocabulary of the HOF signature, exactly like `evolve!` itself; PRD-v2 §2
layer table: strategy *selection* is physicist-facing). Kernel/library
`public` (reachable as `Sturm.…`, never dumped): `PauliTerm` (already),
`PauliSum`, `alpha_comm`, `trotter_steps`, `qdrift_samples`,
`qdrift_distribution`, `evolve_plan`, `EvolvePlan`, `BoundReport`,
`suzuki_sweeps`, `exp_count`.

---

## 2. Hamiltonian representation (Q2)

**Verdict: upgrade to a symplectic bitmask `PauliSum{W}`; keep `PauliTerm`
as the string-facing input type.** The string type cannot support exact
commutator algebra without reparsing in inner loops; the bound machinery
(D-A2) is the whole point of M12.

```julia
"Pauli word on W wires as a symplectic pair: bit j of x/z set ⇒ X/Z component
on wire j. Y = both bits. Wire 1 = MSB = string char 1 (the F21/M10 pin);
mask bit for char j is (W − j) — pinned in _parse_word/_word_string ONLY."
struct PauliWord{W}
    x::UInt64
    z::UInt64
    # inner ctor asserts W ≤ 64 (fail fast; UInt128 is a future widening)
end

"Library-level Hamiltonian value (NOT a kernel value — hard constraint).
CANONICAL invariants, established by the constructor:
  • duplicate words merged (exp(−i(a+b)P) ≡ the merged factor — exact),
  • exact-zero coefficients dropped,
  • identity word split out into `c_id` (deterministic global phase),
  • terms sorted by |coeff| DESC, ties broken by (x,z) lexicographic —
    so `K`-cuts, λ_K tails, and schedules are reproducible."
struct PauliSum{W}
    words::Vector{PauliWord{W}}    # non-identity, canonical order
    coeffs::Vector{Float64}        # signed, same order
    c_id::Float64                  # identity-word coefficient (may be 0)
end
```

Algebra (all exact, all unit-tested against dense kron matrices):

- `commutes(p, q) = iseven(count_ones(p.x & q.z) + count_ones(p.z & q.x))`
  (the symplectic form).
- `mul(p, q) -> (phasepow::Int, ::PauliWord)`: product word `(p.x ⊻ q.x,
  p.z ⊻ q.z)` with the i^k phase tracked exactly as an integer mod 4. Norms
  never need the phase, but the test suite pins it anyway (v0.1 lesson 1:
  sign bugs ship silently — the algebra layer is where they'd enter).
- `[P,Q] = 0` if `commutes`, else `2·P·Q` up to phase, so
  ‖[P_{γ_{2p+1}},[…,[P_{γ₂},P_{γ₁}]…]]‖ ∈ {0, 2^{2p}} EXACTLY — the enabling
  fact for §4.

Derived quantities (trivial on the canonical vectors, each a one-liner with a
named test): `lambda(hs) = sum(abs, coeffs)` (identity EXCLUDED — it commutes
with everything, contributes the exact global phase `gphase(−c_id·t)` once,
and sampling it would waste qDrift budget; extracting it can only tighten
every bound and changes no physics — documented as a normalization lemma in
pauli.jl); `lambda_tail(hs, K) = Σ_{j>K}|a_j|` and
`tail_second_moment(hs, K) = Σ_{j>K} a_j²` via precomputed suffix sums.

Migration: `_normalize_hamiltonian(H, W)` becomes
`PauliSum{W}(H)` accepting `Vector{PauliTerm}`, any iterable of
`(::Real, ::AbstractString)`, or a `PauliSum{W}` (identity passthrough).
Same `DimensionMismatch`/`ArgumentError` messages as M10 (tests carry over).
`PauliTerm` stays the documented input spelling; `String(::PauliWord{W})`
round-trips for display/debug, with the endianness pinned by ONE test
(v0.1 lesson 6).

NOTE (ordering behavior change): M10 executed terms in user order; M12
executes in canonical order. Every published Trotter bound here (childs E1/E2,
HW Thm `trotter_cost`) is ordering-independent, so conformance tests are
unaffected; reproducibility improves. Documented in the `evolve!` docstring.

---

## 3. Suzuki order-2k machinery (Q3)

**Representation: an explicit sweep schedule, generated once per order by the
closed-form recursion — not Val-dispatch code generation, not runtime
recursion in the hot loop.**

```julia
"One directional sweep over the term list: duration dt·τ (dt SIGNED — Suzuki
p ≥ 2 has negative-time middle stages, that is the physics, do not 'fix' it),
covering each term once in `forward` or reverse canonical order."
struct Sweep
    dt::Float64
    forward::Bool
end

"suzuki_sweeps(p::Integer) -> Vector{Sweep} of length Υ = 2·5^{p−1}.
suzuki_sweeps(::Type{BigFloat}, p) — the arbitrary-precision twin (tests).
Memoized in a const IdDict{Int,Vector{Sweep}}."
```

Recursion (suzuki_1991_fractal_decomposition.md, Eq. (1.1)/(3.14–3.16);
hagan_wiebe_2023_composite.md Def. of `trotterU`):

- Base p = 1 (Strang): `[Sweep(1/2, true), Sweep(1/2, false)]` — exactly
  M10's order-2 loop.
- p ≥ 2: with `u_p = 1/(4 − 4^(1/(2p−1)))` computed in closed form at use,
  `S_{2p}(τ) = S_{2p−2}(u_p τ)² · S_{2p−2}((1−4u_p)τ) · S_{2p−2}(u_p τ)²`,
  i.e. concatenate the (p−1)-schedule five times with dt scaled by
  `u_p, u_p, 1−4u_p, u_p, u_p`.
- Order 1 (Lie–Trotter) is the special schedule `[Sweep(1.0, true)]`, Υ = 1.

Exactness properties, each a NAMED test (M12.SUZUKI.COEFFS):
- `length == 2·5^{p−1}`;
- `sum(dt) == 1` (BigFloat: to precision; Float64: ≤ 4·eps drift vs BigFloat);
- palindrome: `dt` sequence is symmetric, and direction strictly alternates
  `true,false,true,…` (provable by induction: every sub-block has even length,
  starts forward, ends reverse — the test asserts it structurally rather than
  trusting the induction);
- Float64 coefficients agree with the BigFloat twin to ≤ 4 eps relative — the
  transcription-typo guard.

One Trotter step of duration τ executes, for each `Sweep(dt, fwd)`, the
exponentials `exp(−i c_k P_k · dt·τ)` over terms in the given direction:
`Υ·L` operator exponentials per step (order 1: `L`). **No adjacent-stage
merging in M12**: merging the last exponential of one sweep with the first of
the next is algebraically exact but changes the counted cost away from the
papers' unit `Υ·L·r` and complicates conformance accounting. It is deferred
to the channel-DAG `FuseUnitaryRuns` pass, where it belongs (dag.jl already
fuses within barrier-free segments). Physics first; peephole later.

---

## 4. α_comm: the exact commutator-sum engine (Q4)

Definition (hagan_wiebe_2023_composite.md Eq. `def:alpha_comm`;
zlokapa_2026_hamsim_lower_bounds.md Fact HW):

    α_comm(F, 2p) = Σ_{γ₁…γ_{2p+1}} (Π_r f_{γ_r}) ·
                    ‖[F_{γ_{2p+1}}, [F_{γ_{2p}}, …, [F_{γ₂}, F_{γ₁}]…]]‖

with ‖F_γ‖ = 1 (Pauli words) and f_γ = |a_γ| ≥ 0 (signs live in the unit
operator; commutator norms are sign-insensitive, asserted by a test).

**Algorithm (exact; the load-bearing observation).** α_comm is a sum of
*per-tuple* norms — nonnegative, no interference between tuples. For Pauli
words the nested commutator survives iff every level anticommutes with the
running product word, and then its norm is exactly 2^{2p}. Whether level
d+1 survives depends ONLY on the current product word (Markov property), so
tuples can be aggregated by product word without loss:

```
layer[1] = Dict(P_j => |a_j| for j)               # depth-1 "words"
for d in 2:(2p+1)
    for (w, ω) in layer[d−1], j in 1:L
        commutes(w, P_j) && continue
        layer[d][w ⋆ P_j] += ω · |a_j|            # ⋆ = phase-free product word
    end
end
α_comm = 2^{2p} · sum(values(layer[2p+1]))
```

Complexity `O(2p · D · L)` with `D = maximum layer size` ≤ min(4^W, reachable
products) — small for structured Hamiltonians, potentially explosive for
dense random ones. **Complexity guard (hard constraint — no silent bound
fallback, the v0.1 `alpha_comm` p≥3 1e9×-looser-substitution bug class is
banned):** if any layer exceeds `budget` entries (`ALPHA_BUDGET = 2^22`
default), `error()` with the exact state: depth reached, D, budget, and the
three sanctioned exits — raise `budget=`, supply `alpha_upper=` (a
user-certified UPPER bound — sound, since every bound here is monotone
increasing in α_comm; the docstring says "upper" three times), or choose a
lower order / different strategy. Nothing is ever substituted.

API (`bounds.jl`):

```julia
alpha_comm(hs::PauliSum{W}, order2k::Int; budget = ALPHA_BUDGET) -> Float64
# Partition variants for Composite (HW's exact identity, Eq. after def:alpha_comm):
#   α({A,B}, 2p) = α(H, 2p) − α(A, 2p) − α(B, 2p)   — three engine calls, exact.
alpha_comm_cross(hs, K, order2k; budget) -> (αA, αAB)

"trotter_steps(hs, |t|, ε; order, alpha_upper=nothing, budget) -> BoundReport
 whose value is r. Order-specific formula registry:
   order 1 : E1 (childs_2019_trotter_error.md): spectral ≤ (t²/2r)·Σ_{i<j}‖[H_i,H_j]‖,
             exact pair sum = 2·Σ_{i<j, anticommuting}|a_i a_j|; diamond = 2× (D-A3).
   order 2 : min(E2 tight bound, generic 2k formula at k=1) — both proven, min is valid.
   order 2k: HW Thm trotter_cost / Eq TS_intermediate_3:
             r = ⌈ (Υt)^{1+1/2k} / ε^{1/2k} · (4·α_comm(H,2k)/(2k+1))^{1/2k} ⌉
             for full-diamond ε (their Eq trotter_diamond_error)."
trotter_steps(hs, t, ε; order, kwargs...) -> BoundReport

"The inverse direction, for conformance tests and reports: the proven error
 bound at given (r, order) — spectral (per HW Eq TS_intermediate_2 × r; E1/E2
 for orders 1/2) and diamond (×2)."
trotter_error_bound(hs, t, r; order, kwargs...) -> BoundReport
```

`BoundReport`:

```julia
struct BoundReport
    value::Float64      # r, N, N_B, or an error bound — as documented per formula
    formula::Symbol     # :childs_E1, :childs_E2, :hw_trotter_2k, :campbell_exact_N,
                        # :hw_fact_thm21, :nb_stationary, :zlokapa_proxy, …
    citation::String    # "docs/physics/hagan_wiebe_2023_composite.md — Thm 2.1"
    inputs::NamedTuple  # (λ = …, α = …, t = …, ε = …, Υ = …, …)
end
```

Time sign: bounds use `|t|` throughout (backwards evolution is legal; angles
carry the sign). `t == 0` yields an empty schedule (legal no-op).

**RESEARCH STEP R1 (explicit, Principle 8):** the E2 constant in
`childs_2019_trotter_error.md` currently abbreviates its index ranges
("Σ_{i<j≤k or…}"). Before implementing the order-2 tight path, the
distillation must be completed against Childs et al. Prop./Thm. 11 (the
(1/12)/(1/24) nested sums) with exact ranges, and the M10 E1 test extended to
E2. Until then, order 2 may soundly use the generic k = 1 HW formula alone
(it is a proven bound); the `min(…)` upgrade lands with the distillation.

---

## 5. QDrift (Q5)

Channel (campbell_2019_qdrift.md, Thm 1): per segment of duration t/N, sample
j with p_j = |a_j|/λ and apply `V_j = exp(−i sign(a_j)·(λt/N)·P_j)`; the
segment channel E satisfies (Campbell's appendix, the exact series — his own
pseudocode line "or solve exact expression in appendix"):

    ‖U_{t/N} − E‖_⋄ ≤ 2(e^{2λt/N} − 1 − 2λt/N),

so N segments obey, in the FULL diamond norm (D-A3),

    ‖U_t − E^{∘N}‖_⋄ ≤ 2N(e^{2λt/N} − 1 − 2λt/N)  →  4λ²t²/N as N → ∞.

**N selection is the EXACT transcendental criterion, not the asymptote:**

```julia
"qdrift_samples(λ, |t|, ε) -> BoundReport (value = N): the least integer N with
 2N(e^{2λt/N} − 1 − 2λt/N) ≤ ε. f(N) is strictly decreasing in N (proof in
 docstring: x ↦ (e^x−1−x)/x is increasing, x = 2λt/N); solved by doubling
 bracket + integer bisection. No validity-window caveats (the HW restatement's
 ε < λt·ln2/2 window exists only to license their closed form — the exact
 criterion needs none). Test: N_exact ≤ ⌈4λ²t²/ε⌉ always, ratio → 1."
qdrift_samples(λ::Float64, t::Float64, ε::Float64) -> BoundReport
```

Sampler (pure, rng-explicit — `schedule.jl`):

```julia
"qdrift_distribution(hs) -> (p::Vector{Float64}, cum::Vector{Float64}, λ)  [public]"
"_qdrift_indices(rng, cum, N) -> Vector{Int32}   # searchsortedfirst(cum, rand(rng))"
build_schedule(alg::QDrift, hs::PauliSum{W}, t, rng) -> Schedule
#   N entries StageExp(term = j_i, angle = sign(a_{j_i})·λ·t/N)
#   + one identity entry for c_id (excluded from exp_count)
```

RNG ownership: `alg.rng` if set, else the context core's rng (`rng(ctx)`,
abstract.jl — the same stream `Bool(q)` sampling draws from; `nothing` core
rng falls back to global `rand`, matching `_draw`). Precedence pinned by a
test. **The per-shot loop belongs to `shots`** (Tobias decision 3): one
`evolve!(…; alg = QDrift(...))` call = ONE sampled trajectory (a plain unitary
`apply!` sequence — never wrapped as a ProcessValue/`UnitaryBlock`, hard
constraint). Under `shots(f, cap; N, rng)` the shared rng threads through the
per-shot contexts, so trajectories are distinct and the whole experiment is
reproducible from one seed (a named test).

Docstring states the guarantee PRECISELY (Campbell's "Diamond norm distance"
paragraph; campbell_2017_mixing_unitaries.md + hastings_2016_incoherent_errors.md
for why mixture errors add in diamond norm; chen_2021_concentration_random_products.md
for typical-trajectory ~√ε vs ensemble ε): the ε bound is a property of the
ENSEMBLE channel — expectation values estimated over fresh trajectories
converge at precision ε; any single trajectory is only O(√ε)-close. This is
physics, not a caveat to hide: it is the reason trajectory-level realization
(decision 3) is sound *for sampling experiments* and why `evolve!(QDrift)` on
a DM context (legal — each trajectory is a unitary) documents the same
ensemble semantics.

---

## 6. Composite (Hagan–Wiebe) (Q6)

### 6.1 Partition (head/tail split)

Canonical order (§2) makes "head = first K terms" well-defined. Default K by
the optimal-K structure (zlokapa_2026_hamsim_lower_bounds.md, Lemma
`optimal_k`: K* ∈ argmin_K (K + λ_K²/ε) satisfies Σ_{j>K*} a_j² ≤ ε — cut
until the tail second moment is ε-small):

1. **Proxy scan (O(L), exact arithmetic, no α_comm):** minimize over
   K ∈ 0..L the frontier proxy `C̃(K) = Υ²·K·⌈R_P-proxy⌉ + …` — concretely,
   Zlokapa Eq. `eq:composite`: `K·t·(t/ε)^{1/2p}·c_p + 4λ_K²t²/ε` with
   suffix-sum λ_K. This is the shape the lower bound proves optimal; the
   scan is pure classical and unit-testable.
2. **Exact refinement:** evaluate the true Fact-HW cost (§6.3) at
   K ∈ {⌈K̃/2⌉, K̃, min(2K̃, L)} (each needs α_comm(A,2p) and the cross term
   — three budget-guarded engine calls per K) and keep the argmin. Bounded
   work, exact final choice, and the proxy-vs-exact agreement is itself a
   benchmark metric (§9).

User override: `Composite(K = k)` pins the cut. Custom (non-sorted)
partitions are a flagged future (HW's probabilistic partitioning, their Eq.
`eq:prob_def`, is NOT implemented in M12 — noted as a possible M13 strategy).

### 6.2 The interleaving schedule — exact by construction

HW Def. `higher_order_loop`: the OUTER loop applies the SAME Suzuki recursion
to the two-element list [A, B] that the inner formula applies to A's terms —
so `suzuki_sweeps(p)` is reused at both levels (one function, one set of
coefficients, one test surface). Per outer step of duration τ = t/r:

```
for (i, sw) in enumerate(suzuki_sweeps(p))        # Υ outer sweeps, dt signed
    blocks = sw.forward ? (:A, :B) : (:B, :A)     # a sweep over the pair
    for blk in blocks
        blk === :A : append one FULL inner order-2p Suzuki single step
                     of A at duration sw.dt·τ      (Υ·L_A exponentials)
        blk === :B : append N_B qDrift samples of the tail at duration
                     sw.dt·τ  — angles sign(a_j)·λ_B·(sw.dt·τ)/N_B
                     (N_B PER B-BLOCK: the Fact-HW cost Υ(ΥL_A + N_B)·r
                      counts Υ A-blocks AND Υ B-blocks per step)
    end
end
```

Exactness obligations, all NAMED schedule tests (no executor involved):
- exponential count == `r·Υ·(Υ·L_A + N_B)` EXACTLY (Fact HW's cost unit);
- signed durations: Σ over A-entries of each term's angle = a_k·t exactly
  (to fp), Σ over B-blocks of block durations = t;
- the outer structure is palindromic and alternation-correct;
- degenerations: K = L ⇒ schedule ≡ `Trotter(order = 2p)` schedule
  (elementwise); K = 0 ⇒ … ≡ `QDrift` schedule with N = Υ·r·N_B — wait, NO:
  K = 0 collapses the outer loop; ruled instead as: K = 0 normalizes to the
  plain `QDrift` strategy before scheduling (one code path, tested), K = L
  normalizes to plain `Trotter`. No remainder, no `÷`, anywhere (v0.1
  lesson 3).

Negative-dt B-blocks (p ≥ 2 outer stages): qDrift samples at negative
duration are legal unitaries (angle sign flips); the HW analysis is
|duration|-based (their Lemma `diamond_dist_higher_order` bounds t_i ≤ t via
|1−4u_k| ≤ 1). **RESEARCH STEP R2:** re-verify against HW's algorithm listing
that (a) N_B is per B-invocation (I derive it from the cost formula
Υ(ΥL_A + N_B) and Lemma `diamond_dist_higher_order`'s per-channel error
accounting; the algorithm environment in their §2 should confirm), and (b)
each B-block draws FRESH samples (independence is what the mixing lemma
consumes — campbell_2017_mixing_unitaries.md). Both are asserted by the
schedule tests once confirmed.

### 6.3 Resources from ε (Fact HW, verbatim)

zlokapa_2026_hamsim_lower_bounds.md Fact HW / hagan_wiebe_2023_composite.md
Thm 2.1: with P = product-formula error weight and Q = qDrift weight
(their Eqs. `def:p_of_t`/`def:q_of_t`),

    r = ⌈ (Υt)^{1+1/2p}·4^{1/2p}/ε^{1/2p} ·
          ((Υ·α_comm(A,2p) + α_comm({A,B},2p))/(2p+1))^{1/2p}
        + 4Υλ_B²t²/(N_B·ε) ⌉,
    cost = Υ·(Υ·L_A + N_B)·r.

N_B default: minimize the real-valued cost `Υ(ΥL_A + N_B)(R_P + R_Q/N_B)`
(R_P = the first bracket term, R_Q = 4Υλ_B²t²/ε): stationary point
`N_B* = √(Υ·L_A·R_Q/R_P)` (the same structure as HW's first-order N_B
lemma), then integer scan {⌊N_B*⌋−1 … ⌈N_B*⌉+1} ∩ [1,∞) on the true ⌈·⌉
cost. Exact, and the chosen (K, N_B, r) triple ships in the `BoundReport`
(`:hw_fact_thm21` + `:nb_stationary`).

---

## 7. Auto (Q7)

```julia
"evolve_plan(H, t, ε; order_candidates = (2, 4, 6), composite_orders = (2, 4),
             budget, rng = nothing) -> EvolvePlan          [public, PURE classical]"
struct EvolvePlan
    choice::EvolveAlg                        # fully-resourced concrete strategy
    cost::Int                                # proven op-exp count of `choice`
    table::Vector{PlanRow}                   # EVERY candidate, including skipped
end
struct PlanRow
    alg::EvolveAlg; report::Union{BoundReport,Nothing}; skipped::Union{String,Nothing}
end
```

Dispatch rule, grounded in the optimal-K lemma (the frontier
Θ(min_K(Kt + t²λ_K²/ε)) is *literally* the minimum over the candidate set,
since Composite(K) interpolates Trotter (K = L) and qDrift (K = 0)):

1. Candidates: `Trotter(order = 2k)` for 2k ∈ order_candidates;
   `QDrift`; `Composite(order = 2p)` for 2p ∈ composite_orders with K, N_B, r
   from §6. Costs: `Υ·L·r` (HW Thm `trotter_cost`), `N` (exact criterion §5),
   `Υ(ΥL_A + N_B)r` (Fact HW).
2. `choice` = argmin proven cost; ties → the DETERMINISTIC candidate
   (physics-first tiebreak: a unitary with a spectral-norm guarantee beats an
   ensemble guarantee at equal cost), then lower order.
3. An α_comm budget overflow for one candidate does NOT abort the plan: that
   row is recorded as `skipped = "alpha_comm budget …"` in the table (visible,
   never silent), and selection runs over the surviving rows. If ALL rows are
   skipped → `error()`. This is a selection heuristic degrading loudly, not a
   bound substitution — the chosen strategy's own bound is always exact.

`evolve!` with `Auto` = `_execute!(build_schedule(plan.choice, …))`. Because
`evolve_plan` is pure, the decision boundary is directly unit-testable
(M12.AUTO.PLAN): hand-constructed regimes per Campbell's numerics and HW §
"cost crossover" discussion — uniform coefficients / large t ⇒ Trotter;
strong-decay coefficients (λ ≪ Λ·L) / moderate t ⇒ qDrift; exponential-decay
head-heavy spectra near crossover ⇒ Composite — and the bench frontier
(§9) validates the same table against measured counts. `Auto.eps` default
1e-3 (Campbell's numerics value) — **orchestrator decision point O1**, since
FAIL-FAST purism would demand an explicit ε; decision 1 ("Auto() default")
requires SOME default.

---

## 8. Verification architecture (Q8)

Principles: deterministic full-operator tests are the DEFAULT (v0.1 lessons
1, 2, 4); ensemble tests are built by ENUMERATION (exact averages) wherever
the branch space permits, sampling only as a supplement; heavy statistics are
tier-gated (lesson 5). Harness reuse: `op_matrix`, `ham_mat`,
`dist_upto_phase` from test_m10_library.jl; Choi tooling from choi.jl.

Tiering: FAST = default `Pkg.test()` (each testset ≤ ~5 s); HEAVY = gated by
`ENV["STURM_TEST_HEAVY"] == "1"` inside the same files (skipped testsets log
one line). CI runs FAST always, HEAVY on a schedule/label.

Named tests (`test/test_m12_hamsim.jl` + `test/test_m12_bounds.jl`):

- **M12.PAULI.ALGEBRA** — symplectic product/phase/commutation vs dense kron
  on exhaustive 1–2 wire words + randomized W = 6 words; the MSB/string
  endianness pin (ONE test, lesson 6); canonicalization (merge, sort,
  identity split) invariants.
- **M12.SUZUKI.COEFFS** — §3's four properties; u_p closed form vs recursion
  in BigFloat.
- **M12.TROTTER.ORDER4/6-EXACT** — `op_matrix` of `Trotter(order = 4)` (and 6,
  HEAVY) vs dense `exp(−iHt)` on 2–3-qubit non-commuting H:
  `dist_upto_phase ≤ trotter_error_bound(...)` (untuned), plus the
  order-signature scaling ratio r → 2r ≈ 2^{2k} (16 for order 4) in a
  window — the M10 pattern extended.
- **M12.ALPHA.EXACT** — `alpha_comm` vs brute-force tuple enumeration with
  dense matrices (L ≤ 4, 2p ≤ 4, per-tuple opnorm summed): equality to 1e-9.
  Partition identity α(H) = α(A) + α(B) + α({A,B}). Budget guard: a dense
  random H at tiny budget throws with the documented message.
- **M12.BOUNDS.CONFORMANCE** — for orders 1, 2, 4 on ≥ 2 model Hamiltonians:
  realized spectral error ≤ spectral BoundReport; diamond report = 2×
  spectral (the D-A3 pin has its own test so the factor can never drift).
- **M12.QDRIFT.SAMPLER** — `_qdrift_indices` is a pure function: fixed-seed
  golden sequence; χ² frequency test vs p_j at N = 5000 (cheap — classical
  only); `qdrift_samples` exact-criterion properties (monotone, ≤ asymptotic
  ceil, boundary N = 1).
- **M12.QDRIFT.CHANNEL-ENUM (the wm28-class killer)** — deterministic, NO
  sampling: build the exact segment superoperator E = Σ_j p_j Ad(V_j) from
  dense V_j (test-side LinearAlgebra), power it N times, compare to
  Ad(e^{−iHt}) via the normalized Choi state (choi.jl convention):
  `‖J(E^N) − J(U)‖₁ ≤ ε` — valid conformance since trace-norm-of-Choi lower
  bounds the diamond norm (documented as a necessary-condition test; small
  1–2 qubit H). Catches phase/ordering bugs marginals cannot see.
- **M12.QDRIFT.TRAJECTORY-CONSISTENCY** — seeded `evolve!(QDrift)` inside
  `op_matrix` equals `Π V_{j_i}` for the recorded index sequence
  (full-operator, lesson 2), for several seeds; plus `shots` reproducibility
  (same seed ⇒ identical outcome vector).
- **M12.COMPOSITE.SCHEDULE-EXACT** — §6.2's count/duration/degeneration
  assertions, pure. Includes the "no remainder" property on adversarial
  (L_A, N_B, r, p) grids.
- **M12.COMPOSITE.CHANNEL-ENUM** — toy-size exact average: L_B = 2, N_B = 1,
  p = 1, r ≤ 2 ⇒ ≤ 4^2·… ≤ 256 branches enumerated by expanding each
  B-block over its L_B outcomes with weights; exact mixed superoperator vs
  Ad(expm) under the Fact-HW ε. Deterministic.
- **M12.COMPOSITE.MC (HEAVY)** — 3 qubits, M ≥ 1000 sampled trajectory
  matrices (CLAUDE.md #10), Monte-Carlo mean superoperator vs Ad(expm):
  distance ≤ ε + 3σ̂ (σ̂ bootstrapped); documents its runtime budget.
- **M12.EVOLVE.SUGAR** — kwargs path ≡ `Trotter` path (identical schedule,
  identical `op_matrix`); conflict kwargs throw; M10's DomainError tests
  carry over verbatim.
- **M12.AUTO.PLAN** — §7 regime tests; skipped-row visibility; tie-break.
- **M12.GUARDRAIL.CTRL** — `evolve!` (each strategy) inside `when(...)`
  throws via `_assert_no_control`; error message names the follow-on (§10).
- **Boot lints** — no `\bcontrolled\b` outside kernel/orkan in the new files;
  every cited `docs/physics/*.md` resolves (Phase 0 delivers the seven
  distillations BEFORE the code that cites them — hard ordering dependency).

---

## 9. bench/ design (Q9)

```
bench/
  Project.toml        # own env: Sturm (dev path), LinearAlgebra, Statistics,
                      #   Printf, DelimitedFiles. No plotting dep in-repo;
                      #   CSV out, plots are a notebook concern.
  hamiltonians.jl     # model families (below)
  frontier.jl         # cost curves — PURE (plans + schedules; no execution)
  empirical.jl        # small-W measured error vs bound slack (executes)
  report.jl           # CSV + Markdown emitter (bench/out/, gitignored)
```

**The counter is free (D-A1):** the paper's cost unit — operator-exponential
count — is `exp_count(schedule)` (identity/gphase entries excluded), and for
frontier curves not even a schedule is needed: `evolve_plan` reports proven
counts from the formulas. One integration assertion (bench-side, and one FAST
test) checks `exp_count(schedule) ==` the plan's formula count, and a
counting-shim context (bench-only wrapper that increments on `apply!`)
cross-checks executed count == schedule length ONCE. Nothing in `src/` hot
paths counts anything.

Model families (coefficient-tail structure is what the frontier probes;
zlokapa_2026_hamsim_lower_bounds.md):
- uniform: a_j = Λ (qDrift's worst case, λ = ΛL — Campbell's Heisenberg
  regime); words: 1-D nearest-neighbour ZZ + transverse X (structured
  commutators, cheap exact α_comm);
- power-law: a_j ∝ j^{−γ}, γ ∈ {1/2, 1, 2}; words random 2-local;
- exponential: a_j ∝ 2^{−j} (HW's head-heavy showcase); words random 2-local;
- one chemistry-shaped fixture (small frozen coefficient list checked into
  bench/, provenance noted) for the λ ≪ ΛL regime.

Frontier protocol: grid over L ∈ {10², 10³, 10⁴}, t ∈ logspace(±3 decades
around the crossover), ε ∈ {1e-2, 1e-3, 1e-4}; per point emit proven counts
for Trotter{2,4,6}, QDrift, Composite{2,4}, the Auto choice, and the Zlokapa
envelope `min_K(Kt + t²λ_K²/ε)` as the reference curve; report (a) each
strategy's ratio to the envelope, (b) Auto regret = chosen/best ≤ 1 by
construction (assert), (c) proxy-K vs exact-K disagreement rate (§6.1).
Deferred-scope note (decision 2): analytic QSVT/LCU cost curves may be
OVERLAID in the report from published formulas — no implementation.

Empirical tier (W ≤ 6, small grids): measured `dist_upto_phase` /
Choi-distance at the derived (r, N, N_B) vs the promised ε — the bound-slack
table (how loose are we, per family). Slack is REPORTED, never tuned against
(Principle 3).

---

## 10. Forward compatibility (Q10)

**The schedule is the M11 seam.** A `Schedule` is classical data:
deterministic entries (Trotter, composite A-blocks) and sampled entries
tagged by their provenance (strategy, rng state consumed at build time).
- *Deterministic strategies* lower today to `apply!` sequences and tomorrow,
  unchanged, to a `UnitaryBlock` (each `_word_exp!` is already a
  Clifford-conjugated `Rz` — certifiable, no barriers), giving DAG-level
  fusion and a ctrl story: a future ctrl-`evolve!` (QPE on e^{−iHt}) lifts
  the SAME schedule through the kernel's `ctrl` choke point (the only
  constructor of conditional lowerings — nothing in M12 builds one). The
  identity/gphase entry is the known subtlety: under ctrl it becomes a
  conditional phase — it is already an explicit StageExp, so the lift sees
  it (no silent global-phase drop; the M10 comment "a ctrl-evolve! is a
  follow-on" stays true and unblocked).
- *Randomized strategies* lower to M11 mixture/Kraus values by replacing the
  trajectory sampler with a mixture constructor over the SAME
  (p_j, V_j)-data (`qdrift_distribution` is already the public accessor);
  zero surface change (decision 3). The ensemble is a channel: it will carry
  a `NoiseN`-style barrier, `certify` refuses it by design, and ctrl of it is
  refused AT THE VALUE LEVEL — permanently. Physics: ctrl of a mixed-unitary
  channel is not the mixture of ctrl'd branches with the same bound; each
  branch's global phase (harmless in Ad) becomes a RELATIVE phase under
  control, and the mixing-lemma premises (campbell_2017_mixing_unitaries.md)
  do not condition. M12 enforces the honest subset today via
  `_assert_no_control` on all of `evolve!` (§1.3); when deterministic
  ctrl-`evolve!` lands, only the deterministic dispatch relaxes.
- `PauliSum{W}` stays a library value forever (hard constraint honored: no
  Hamiltonian kernel value; PRD-v2 §1.3 — Nature hands out processes).

---

## 11. Open research steps (Principle 8)

- **R1** — Complete the E2 (order-2 tight) index ranges in
  `childs_2019_trotter_error.md` from Childs et al. before wiring the
  order-2 `min(…)` path (§4). Sound interim: generic k = 1 formula.
- **R2** — Confirm from HW's algorithm listing: N_B is per B-invocation and
  B-blocks draw fresh samples (§6.2). My derivation from the cost formula
  and Lemma `diamond_dist_higher_order` says yes to both.
- **R3** — Negative-time B-blocks (outer p ≥ 2): verify HW's error accounting
  covers |dt| for the qDrift sub-channels (their t_i ≤ t argument uses
  |1−4u_k| ≤ 1, which suggests yes); if any doubt survives, restrict
  Composite to order = 2 outer (Υ = 2, all dt > 0) and file the extension.
- **R4** — ALPHA_BUDGET default (2^22 proposed): calibrate on the bench
  families so FAST tests never hit it and 10⁴-term power-law Hamiltonians at
  2p = 4 usually pass.
- **O1** (orchestrator) — `Auto(eps = 1e-3)` default vs mandatory explicit ε.
- **R6** (implementer) — sweep `test_prd_examples.jl` and worklog fixtures
  for bare `evolve!(x, H, t)` calls before the Auto default lands.
- Deliberately OUT of M12: 1805.08385 random-permutation Trotter and
  1910.06255 stochastic sparsification — they fit the `EvolveAlg`/schedule
  frame cleanly (a new builder each) but dilute the frontier focus; filed as
  future strategy beads, not smuggled in.
