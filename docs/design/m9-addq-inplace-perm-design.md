<!--
SPDX-License-Identifier: AGPL-3.0-only
Copyright (C) 2026 Tobias Osborne
Part of Sturm.jl.
-->

# M9 synthesis — full-space modular permutations, the in-place-`Perm` compiler, and correct order finding

**Bead:** `Sturm.jl-addq` (P1, blocks the M9 QMod/Shor capstone)
**Findings closed:** F7 (P0), F22, F23, F24
**Status:** authoritative synthesis of proposals A (`m9-addq-proposal-A-codex.md`)
and B (`m9-addq-proposal-B-codex.md`). Reviewed by orchestrator after writing;
**not committed by the synthesizer.** PRD amendments in §8 are **staged** — they
are listed here with exact replacement text and applied post-`vanm` under the
doctest lint, never edited into `Sturm-PRD-v2.md` by this round.

---

## 0. Decision summary

1. `mulmod!(y::QMod{N,W,C}, c)` denotes the **full-space** permutation
   `π_{c̄,N}` — `c̄·v mod N` for `v < N`, identity on the padded tail `N ≤ v < 2^W`.
   Precondition `gcd(c̄,N)=1`, `N ≥ 2`; a non-unit multiplier is a loud
   `DomainError` naming `c`, `N`, `gcd`, thrown before any allocation/mutation.
2. A new Bennett-backed compiler `compile_inplace_perm` composes a separately
   compiled `f` and `f⁻¹` (both through the **existing** `_BENNETT_BACKEND`
   accumulate bridge) into **one frozen kernel `Perm`** via compute/swap/uncompute.
   Inverse agreement is proved **before any quantum action**.
3. Verification is **tiered**: exhaustive-exact below the existing kernel ceiling
   `PERM_EQ_MAXW` (=20); a **closed, library-owned analytic/structural proof**
   above it. No open witness trait, no `check=false`, no sampling-as-proof.
4. `shor_order(a, ::Val{N}; max_samples)` is a bounded repeated-sampling driver:
   exact `BigInt` continued fractions, `lcm` accumulation, `powermod` verification,
   exact prime-strip minimization. Every successful return is verified and minimal;
   otherwise it throws (`NonCoprimeBaseError` / `OrderFindingFailure`), never
   `nothing` or a raw denominator.
5. **F23:** `Int(x)` stays an honest machine-`Int` cast and throws **before**
   backaction when `W ≥ Sys.WORD_SIZE`; the wide consuming cast is **`BigInt(x)`**
   (adopted from B) — an idiomatic constructor-spelled qc cast, not a new verb.
6. **F24:** modulus stays static in the type. Public entry `shor_order(a, ::Val{N})`;
   the handle is **`QMod{N,W,C}`** (matching the *already shipped* `QInt{W,C}`
   F16/`vanm` convention), no runtime modulus field.
7. **§4.1a:** the composite carries a **`PermClean`** certificate whose declared
   clean ports are the copy block ∪ the shared Bennett-ancilla pool, justified by
   the inverse-pair theorem (eq 3) rather than Bennett's `(★)`. No new `CleanCert`
   variant; a second combinator-carried acquisition route
   (`compile_inplace_perm ⇒ PermClean`) alongside `oracle ⇒ PermClean`.

---

## 1. Adjudication of the seven deltas (with rationale)

The proposals **converge** on the padded full-space permutation, dual-compilation
of `f`/`f⁻¹`, one-`Perm` compute/swap/uncompute, the bounded `shor_order` driver,
static modulus via `Val(N)`, and honest `Int(x)`. Those are adopted verbatim in
spirit; the resolved deltas follow.

### Δ1 — verification tiers, cutoff, and complexity budget

A caps exhaustive verification at a fresh `INPLACE_EXHAUSTIVE_MAXW = 16` and
replays the *compiled* `Perm`; B caps at `INPLACE_INVERSE_MAXW = 20` (explicitly
matching a kernel ceiling) and evaluates the *classical specs*, cross-checking
`Bennett.simulate` for small widths.

**Ruling (synthesis).** One tiered contract with **two independent obligations**:

- **(a) inverse agreement of the specifications** — `g(f(x))=x ∧ f(g(x))=x` on
  all of `S_W`, exact integer semantics; and
- **(b) faithful compilation** — each compiled `Perm` realizes its spec and
  cleans its ancilla.

Tier structure:

- **Tier E (exhaustive), `W ≤ PERM_EQ_MAXW`.** Replay **each compiled `Perm`**
  classically on all `2^W` inputs (output/ancilla ports zeroed), extract the
  realized width-`W` image, and check (a) and (b) exactly. Replaying the compiled
  artifact (A's method) is strictly stronger than checking specs alone (B's
  generic tier): it discharges (a) *and* (b) in one pass and would catch a
  faithful-spec / broken-compilation mismatch. First counterexample → loud
  `InverseContractError(W, x, img_f, img_g, direction)`. No `isapprox`, no
  sampling.
- **Tier P (registered proof), any `W`.** A **closed, compiler-owned** proof type
  supplies (a) analytically; (b) rests on the shipped M7 Bennett contract for each
  compilation. For the modular family this is `FullSpaceMulProof{N,W}` storing
  `c̄` and `d = c̄⁻¹ mod N`, validating `c̄·d ≡ 1 (mod N)` with widened arithmetic,
  and **generating both callables from the one immutable spec** (eq 1). It is not
  attachable to an arbitrary user closure through a keyword — that is what
  "registered" means.

**Cutoff registration & budget.** The ceiling is the **existing** kernel constant
`PERM_EQ_MAXW = 20` (`src/kernel/numerics.jl:87`), not a new magic number: it is
already the project's "semantic denotation is tractable" line for a `Perm`, and
Tier E's replay is exactly a `denoted_permutation`-class computation. Budget:
Tier E is `2^W` classical evaluations **plus** `2^W` `Perm` replays, each replay
`O(#gates)`. Above `PERM_EQ_MAXW` only Tier P is admissible; a generic user pair
at `W > 20` is **rejected loudly** — M9 ships no solver for (3) and finite probes
are not a certificate.

*Rationale:* B's cutoff is right (reuse the shipped constant, no drift), A's
replay-the-artifact check is right (subsumes both obligations). Take both.

### Δ2 — artifact name and placement

**`CompiledInplacePerm{W}`** (both agree), in **`src/bennett/inplace.jl`**
(pure-Sturm: artifact type, tiered verification, composition, application). The
two compilations go through **`ext/SturmBennettExt.jl`** (the existing weakdep);
`mulmod!` and `FullSpaceMulProof` live in **`src/library/modular.jl`**. It is
**not** in `src/kernel/`: `Perm` is already the compile target, `ctrl(Perm)=Perm`
already holds, no new process kind is introduced.

API (B's two-phase shape + A's private choke point):

```julia
verify_inverse_pair(f, finv, ::Val{W}; proof=nothing) -> VerifiedInversePair{W}
compile_inplace_perm(pair::VerifiedInversePair{W}; kwargs...) -> CompiledInplacePerm{W}
_apply_inplace_perm!(ctx::AbstractContext,
                     data::NTuple{W,WireID},
                     compiled::CompiledInplacePerm{W}) -> ctx
```

`verify_inverse_pair` and `compile_inplace_perm` are `public`, **not exported**,
and are **not an eighth surface construct** — surface code reaches them only
through registered library actions such as `mulmod!`. The concrete artifact is
minted through a **private construction choke point** `_compiled_inplace_perm`
restricted by a boot lint to `src/bennett/inplace.jl`, exactly as `_ctrl` is
restricted to the control constructor and matching the §4.1a "closed set of
constructors" discipline. Its contained `Perm`/`MCX` data are deeply frozen
(M8/TR5).

```julia
struct CompiledInplacePerm{W}
    perm::Perm            # the one composite Perm on 2W + max(A_f,A_g) wires
    scratch_width::Int    # W + max(A_f,A_g) fresh |0⟩ wires the seam allocates
    clean_ports::Vector{Int}   # declared copy-block ∪ ancilla-pool positions
    # private inner constructor _compiled_inplace_perm(...) — boot-lint gated
end
```

### Δ3 — B's wide `BigInt(x)` consuming cast: **ADOPT**

`BigInt(x::QInt{W})` and `BigInt(dual(x::QInt{W}))` are adopted as the **wide
consuming (qc) cast**. Rationale: `BigInt` is a Base constructor; returning a
`BigInt` from `BigInt(x)` is *honest* (unlike making `Int(x)` return `BigInt`,
which A rightly rejects). It is the same measurement-cast construct spelled with a
constructor — fully consistent with Ruling D (`Bool(q)`/`Int(x)` casts, no
`measure` verb) — and it is the clean resolution of F23 for arbitrary width while
letting `Int(x)` stay strict. It reconstructs the outcome with `big(1) << bit`,
supports every positive width, and is the natural spelling for Shor's phase
sample (`BigInt(dual(k))`). See §6 for the full F23 policy.

### Δ4 — `QMod` parameterization: **`QMod{N,W,C}`**

**Catch:** both proposals frame the F16 context-parameter refactor as
*in-flight/anticipated*. It is **already shipped**: `src/types/register.jl` carries
`QInt{W,C}` (C trailing, so `QInt{W}` stays a valid partial `UnionAll`) and
`QBool{C}`. The F16-consistent final form is therefore **`QMod{N,W,C}`** —
modulus, derived width, context — directly paralleling `QInt{W,C}`.

A's `QMod{N,R,C}` (a `BinaryPadded{W}` representation layer) is rejected for M9:
it does *not* parallel the shipped `QInt{W,C}` and adds an encoding indirection
M9 does not need. `W = ndigits(N-1; base=2)` is derived; the inner constructor
rejects any inconsistent `(N,W)`. There is **no** `modulus::Int` field and **no**
`QMod(N::Integer, v)` constructor forming `QMod{N}` from a runtime value.

*Dependency:* if `vanm` finalizes a different position/convention for the context
parameter, `QMod` tracks it — the invariant is "context is a trailing type
parameter, exactly as `QInt`," not the literal letter `C`.

### Δ5 — the §4.1a certificate interface

Verified against the shipped §4.1a text (`Sturm-PRD-v2.md:1099–1151`): the
expected constructor is **`PermClean`** — "the body is a single `Perm` (or `ctrl^k`
of one) with declared ancilla ports," acquired **combinator-carried**
(`oracle ⇒ PermClean`). The in-place composite is a single `Perm` on
`2W + max(A_f,A_g)` wires, so `PermClean` is the right *type*.

**Catch / staged amendment (§8.4).** The shipped `PermClean` bullet grounds its
theorem specifically in Bennett's **input-preserving** `(★)`
(`|x⟩|t⟩|0⟩ ↦ |x⟩|t⊕f(x)⟩|0⟩`). The in-place artifact is **not** that form: it
maps `|x⟩_D|0⟩_B|0⟩_A ↦ |f(x)⟩_D|0⟩_B|0⟩_A` — the data block is *transformed in
place*, and the clean ports are the copy block `B` ∪ the ancilla pool `A`. The
**general** §4.1a containment `(I − ιι†)Wι = 0` (data = `D`, ancilla = `B∪A`) does
cover it, but the *bullet's justification* does not. The staged amendment
generalizes the `PermClean` bullet to name **two** generator-structure theorems
— Bennett `(★)` (oracle) **or** the inverse-pair compute/swap/uncompute theorem
(eq 3, in-place) — and **two** acquisition combinators. No new `CleanCert`
variant; no runtime observation enters certificate construction.

**What the checked construction records** for the `PermClean` proof:
(i) the composite `Perm`; (ii) the declared clean ports
`clean_ports = {copy-block positions W+1:2W} ∪ {ancilla-pool positions}`;
(iii) provenance = the private `_compiled_inplace_perm` origin (the boot-lint
choke point the checker trusts, exactly as it trusts `oracle`); (iv) the recorded
generator group order (forward-embed ; width-`W` swap ; inverse-embed) on which
the theorem depends. Under Tracing the `PermClean` proof is materialized on the
actually-allocated ports and licenses the certified free; the Eager/DM
`_clean_ancilla_assert!` remains a **debug cross-check**, never the witness.

### Δ6 — control stack / MBU exclusion

Both respect the §3.4 MBU-under-`ctrl` exclusion. **Adopt B's framing** (it is
strictly the safer statement and matches the shipped `oracle` bridge's own
reasoning, `src/bennett/bridge.jl:34–42`): the composite is a **phase-free `Perm`**,
so there is *nothing MBU-flavoured to construct* — MBU is excluded **by
construction, unconditionally**, not merely "when applied under control." That is
what makes a `CompiledInplacePerm` a controllable process value in *every* context
and safe to reuse inside a later `when`. Under a depth-`k` stack `_act!` applies
`ctrl^k(perm) = Perm`; the non-firing branch leaves scratch at `|0⟩`, the firing
branch cleans it by eq (3). Only fixed `ReversibleCircuit → Perm` artifacts cross
this boundary. A's §2.7 (composite crosses the choke point as one `Perm`,
`PermClean` under nonzero stack) is consistent and folded in.

### Δ7 — `shor_order` exact-order minimization

**Both proposals use the identical algorithm** — prime-strip descent — despite
different framing; there is no real "divisor-lattice vs other" disagreement. The
provably-correct minimal-cost version:

1. Precondition `gcd(a₀,N)=1` (else the gcd *is* a factor → `NonCoprimeBaseError`).
2. Accumulate a verified multiple `L` with `lcm`, `a₀^L ≡ 1 (mod N)` by `powermod`.
3. Factor `L` (`L < N`; trial division suffices for the capstone), then for each
   distinct prime `p | L`: `while L%p==0 && powermod(a₀, L÷p, N)==1; L ÷= p; end`.
4. Re-verify `a₀^L ≡ 1 (mod N)`; return `Int(L)`.

Correctness: if the result `L` were a proper multiple of the true order `r`, then
`L/r > 1` has a prime factor `p` with `L/p` still a multiple of `r`, so the strip
loop would not have terminated — contradiction. Cost: one factorization of `L`
plus `O(Ω(L))` `powermod`s.

**Catch (A order-1 bug).** A normalizes `aa = mod(a,N)`, requires `1 ≤ aa < N`,
then samples. For `a ≡ 1 (mod N)` (true order 1) every multiplier is `1`, the
phase is always `0`, every sample is `z=0` (uninformative) — so **A throws
`OrderFindingFailure` for the legitimate order-1 case**. B is correct: special-case
`a₀ == 1 ⇒ return 1` before sampling. **Adopt B's guard.**

---

## 2. Corrected `mulmod!` semantics

Let `W = ndigits(N-1; base=2)` (`= ⌈log₂N⌉` for `N ≥ 2`) and
`S_W = {0,…,2^W-1}`. `QMod{N,W,C}` uses a binary padded representation on `W`
wires; its logical subspace is `span{|0⟩,…,|N-1⟩}`, the remaining basis states are
physical padding that must still receive a **unitary** semantics.

Normalize `c̄ = mod(c, N)`. The process denotation is the full-space permutation

```
                ⎧ c̄·v mod N ,   0 ≤ v < N
  π_{c̄,N}(v) = ⎨                                                      (1)
                ⎩ v         ,   N ≤ v < 2^W
```

Surface action (registered, in-place, returns the same handle):

```julia
mulmod!(y::QMod{N,W,C}, c::Integer) -> y      # |v⟩ ↦ |π_{c̄,N}(v)⟩ on all of S_W
```

**Preconditions / failure (before compile, allocation, or application):**
`N isa Int`, `N ≥ 2`, `W == ndigits(N-1;base=2)`, and `g = gcd(c̄,N) == 1`.
Non-coprimality throws `DomainError` naming `c`, `N`, `g`:

> `mulmod!(QMod{15}, 3): multiplier not invertible mod 15 (gcd = 3); no in-place unitary permutation exists`

It fails **before** scratch allocation or mutation, including inside `when`.
There is **no** fallback to the many-to-one map, no implicit restriction to the
logical subspace, no measurement-based cleanup.

### Bijectivity proof

Let `A = {0,…,N-1}`, `T = {N,…,2^W-1}`; both are invariant under (1). Since
`gcd(c̄,N)=1`, a unique `d ∈ Z_N` has `d·c̄ ≡ 1 (mod N)`. For `v ∈ A`,
`π_{d,N}(π_{c̄,N}(v)) = d·(c̄v mod N) mod N = v`; for `v ∈ T` both maps are the
identity. Hence `π_{d,N} ∘ π_{c̄,N} = π_{c̄,N} ∘ π_{d,N} = id_{S_W}`. So `π_{c̄,N}`
has a two-sided inverse and is a permutation; its 0/1 matrix
`P = Σ_v |π(v)⟩⟨v|` has one `1` per row/column, so `P†P = PP† = I` on the entire
physical Hilbert space. The `N=15` collision is removed: `0 ↦ 0`, padded `15 ↦ 15`.
If `N` is a power of two, `T = ∅` and the proof is unchanged. If the gcd
precondition fails, multiplication is not injective on `Z_N` and **no** tail
convention repairs it.

### Overflow-free classical callable supplied to Bennett

**Warning (both proposals, correct).** The Bennett function must **not** be
`(c*v) % N` at `bit_width = W`: Bennett narrows arithmetic mod `2^W`, so `c*v` can
wrap before `% N`. The registered callable uses a fixed-`W`, overflow-free
double-and-add: for `0 ≤ a,b < N`,

```
              ⎧ a - (N - b) ,   a ≥ N - b        (second branch proves a+b < N)
  a ⊕_N b  =  ⎨                                                            (2)
              ⎩ a + b       ,   a < N - b
```

Expanding `c̄` in binary and applying (2) for exactly `W` statically-bounded
iterations computes `c̄v mod N` with no intermediate `≥ 2^W`. The implementation
gate must **empirically verify Bennett compiles this fixed-loop helper**;
falling back to overflowing native multiply is forbidden (fail-loud). Exhaustive
truth-table tests (§9.1) are the tripwire for this *independent* correctness
hazard.

---

## 3. The in-place-`Perm` compiler contract

### 3.1 Required accumulate oracles (verified against shipped code)

The shipped `_BENNETT_BACKEND[]` (`src/bennett/bridge.jl:109,139`) is
`backend(f, W, kwargs) :: CompiledOracle`, where `CompiledOracle` carries
`perm`, `n_wires`, `in_positions`, `out_positions` (full width `W`), `W`,
`anc_positions`, and denotes the phase-free permutation

```
  U_f : |x⟩_in |t⟩_out |0⟩_anc  ↦  |x⟩_in |t ⊕ f(x)⟩_out |0⟩_anc            (★)
```

for **every** `t` (no output wire read as control — D9). The in-place compiler
calls this backend **twice, directly** (once for `f`, once for `f⁻¹`); it does
**not** call `oracle(f,x)` — it needs the x-independent `CompiledOracle`, not a
live-bound `OracleQuery`. Requirements on each artifact (M7-inherited): exactly
one width-`W` input block, one **full**-width-`W` output block, disjoint in/out,
no output-as-control, no loop-check wires, every ancilla structurally clean,
`ReversibleCircuit → Perm` output only. The `Wb == W` (no-tail) accumulate case
the bridge already documents (`bridge.jl:172-184`) is exactly what the modular
output needs. All `kwargs` pass identically to both compilations
(`auto_self_reversing=false`, circuit-only, etc.).

### 3.2 Requirements on `f` and `f⁻¹`

Both must be total on `S_W`, return width-`W` values, Bennett-compile through the
circuit-only backend, preserve their input, clean every ancilla, and satisfy as
compiled permutations

```
  f⁻¹(f(x)) = x    and    f(f⁻¹(x)) = x      ∀ x ∈ S_W.                     (3-inv)
```

### 3.3 Inverse verification — the tiered contract (Δ1)

Eager, inside `verify_inverse_pair`, **before** the private artifact constructor
and any quantum application:

- **Tier E** (`W ≤ PERM_EQ_MAXW = 20`): replay each compiled `Perm` on all `2^W`
  inputs (output/ancilla zeroed); verify input preserved, ancillas return to `0`,
  full width-`W` output extracted without truncation, and both directions of
  (3-inv). First counterexample → `InverseContractError`. No sampling, no
  `isapprox`.
- **Tier P** (any `W`, registered proof only): the closed, compiler-owned
  `FullSpaceMulProof{N,W}` (stores `c̄`, `d=c̄⁻¹ mod N`, validates `c̄d≡1 mod N`,
  generates both callables from eq 1). (3-inv) rests on eq (1)'s algebra;
  faithful compilation rests on the shipped M7 Bennett contract. For
  `W ≤ PERM_EQ_MAXW` a registered proof **additionally** receives the Tier-E
  cross-check; above it, correctness rests on the analytic witness + M7.

A generic user pair with `W > PERM_EQ_MAXW` is rejected loudly. There is no
`check=false`, no sampling verifier, no open `AbstractInverseWitness` subtype
users could lie through — this preserves M8's closed-certificate discipline.

### 3.4 Compute / swap / uncompute construction

Layout: slots `1:W` = external data `D`; slots `W+1:2W` = copy block `B`;
remaining slots = a **shared** ancilla pool `A` (shareable because `U_f` returns
its ancillas to `0` before `U_{f⁻¹}` runs), size `A = max(A_f, A_g)`,
`g = f⁻¹`. The composite generator order is:

1. embedded `U_f` (input `D`, output `B`);
2. a genuine width-`W` **bitwise swap** of `D` and `B` (real gates — so the data
   physically ends in the declared `D` ports);
3. embedded `U_g` (input `D = f(x)`, output `B = x`).

On basis states, starting clean:

```
  |x⟩_D |0⟩_B |0⟩_A  --U_f-->   |x⟩_D |f(x)⟩_B |0⟩_A
                     --swap-->  |f(x)⟩_D |x⟩_B |0⟩_A
                     --U_g-->   |f(x)⟩_D |x ⊕ f⁻¹(f(x))⟩_B |0⟩_A
                             =  |f(x)⟩_D |0⟩_B |0⟩_A                        (3)
```

Linearity extends (3) to every superposition with no residual entanglement:
`Σ_x α_x|x⟩ ↦ Σ_x α_x|f(x)⟩`. Using `adjoint(U_f)` after the swap is **not**
sufficient — it accumulates `f(f(x))`, not `f⁻¹(f(x))`; the separately compiled
inverse is load-bearing. The M7 `_role_tables` remains the **only** Bennett
MSB/LSB remap; the embedding pass merely renumbers already-remapped `Perm`
positions into the composite layout — **no second bit reversal** (wm28 guard).
The output is one frozen kernel `Perm`, not three surface operations.

### 3.5 Wire / scratch budget

For forward/inverse ancilla counts `A_f, A_g`:

- external data: `W` live wires;
- persistent clean scratch allocated by `_apply_inplace_perm!`:
  `W + max(A_f, A_g)` fresh `|0⟩`;
- underlying `Perm` width: `2W + max(A_f, A_g)` (the pool is **shared**, not summed).

Application: (1) liveness/context/aliasing checks; (2) allocate scratch as fresh
`|0⟩`, uncontrolled; (3) one `_act!(ctx, compiled.perm, wires)`; (4)
`_free_clean!` every scratch wire. A depth-`k` control stack prepends the existing
`k` control wires via `_act!` (no new contract-level ancilla). Backend `Perm`
lowering may transiently borrow `max(0, k+m-2)` clean raw slots per `m`-control
generator for multi-control reduction — that is the existing `Perm` emission
budget, recycled per generator, not part of the artifact.

### 3.6 Certificate interface (Δ5) and control-stack rules (Δ6)

The composite crosses the action choke point as **one `Perm`**, so
`ctrl^k(perm) = Perm`. It carries a **`PermClean`** certificate with declared
clean ports `clean_ports = {W+1:2W} ∪ {ancilla-pool positions}`, provenance =
the private `_compiled_inplace_perm` origin, justified by the inverse-pair theorem
(3). No new `CleanCert` variant. MBU is excluded **by construction,
unconditionally** (a `Perm` has no measurement node), so the artifact is a
controllable process value in every context and is safe to reuse inside `when`.
Non-firing branch: scratch stays `|0⟩`; firing branch: (3) cleans it — scratch
release is valid in both. `_clean_ancilla_assert!` at `_free_clean!` is defensive
execution checking, never the certificate.

### 3.7 Literature grounding and missing-distillation work items

`docs/physics/bennett_1973_logical_reversibility.{md,pdf}` **exist** (verified;
the `.md` covers Table 1 p.528 compute/copy/uncompute and Table 2 p.530
input-erasure two-oracle pattern). **Prerequisite work item BEFORE M9 code:**
amend that distillation with a subsection **"Inverse-assisted in-place
permutation,"** stating eq (★) and eq (3) explicitly and identifying the copy
block, width-`W` swap, and inverse accumulate. Code docstrings cite that
subsection (CLAUDE.md principle 4/5), **not** this design doc or an unlocated
textbook.

**Missing distillation (CLAUDE.md principle 4 — name it, do not silently cite):**
there is **no** Shor/order-finding distillation in `docs/physics/`. Before §7.7
code lands, add a **local primary-source PDF** and
**`docs/physics/shor_order_finding.md`** covering: the phase-sample equation, the
continued-fraction convergence theorem (`Q ≥ N²` / `|z/Q − p/q| ≤ 1/2N²` locator),
the divisor-denominator issue (eq 6 below), repetition + LCM, `powermod`
verification, and the success-probability equations used to justify the §9.5
statistical threshold. This is mandatory and blocks §7.7.

---

## 4. Corrected `shor_order`

### 4.1 Signature and preconditions

```julia
shor_order(a::Integer, ::Val{N}; max_samples::Int = 32) -> Int   where {N}
```

`W = ndigits(N-1; base=2)` is derived internally (a caller-supplied `Val{W}` would
duplicate the invariant and permit inconsistent `(N,W)`). Before any register
allocation: `N isa Int`, `N ≥ 2`, `max_samples ≥ 1`, `a₀ = mod(a,N)`,
`g = gcd(a₀,N)`. If `g ≠ 1`, throw `NonCoprimeBaseError(a, N, g)` — the caller has
already found a factor. **If `a₀ == 1`, return `1` without sampling** (Δ7 catch —
the order-1 case A mishandles).

*(Overflow: the classical driver is `BigInt`-clean end-to-end (§4.3–4.4), so no
`2W < Sys.WORD_SIZE` arithmetic cap is imposed — see §6/Δ3 catch. The real bound
on `W` for the capstone is the backend qubit budget, checked at register
allocation, not a word-size arithmetic bound.)*

### 4.2 One quantum sample (fresh region per attempt)

```julia
function _shor_phase_sample(a₀, ::Val{N}, ::Val{W}) where {N,W}
    region() do
        k = QInt{2W}(0); superpose!(k)     # phase register, uniform over 0:2^{2W}-1
        y = QMod{N}(1)                      # work register ≡ 1 (mod N)
        c = a₀
        for j in 2W:-1:1                    # LSB-upward: wire j weighs 2^(2W-j);
            when(k[j]) do                   # wire 2W ↦ a^(2^0), wire 1 ↦ top (F21 fix)
                mulmod!(y, c)
            end
            c = Int(powermod(big(c), 2, big(N)))
        end
        return BigInt(dual(k))              # Fourier-sample; y traced at region exit
    end
end
```

Each attempt allocates fresh `k`, `y`; the cast consumes `k`; `y` is traced at
region exit (that trace is *why* order finding works). A sample is never reused as
a fresh experiment. Every `c` is a power of the coprime base, so each `mulmod!`
precondition holds; it is nonetheless re-checked. Uses the corrected `2W:-1:1`
control schedule (closes F21).

### 4.3 Exact continued-fraction candidates

`Q = big(1) << (2W)` — never `4^W` in `Int`, never `Float64` division, never
`rationalize`. For sample `z = BigInt(dual(k))`, enumerate the simple
continued-fraction convergents `p/q` of the exact rational `z/Q` with `q < N`,
and retain the **largest** `q` satisfying the exact integer form of
`|z/Q − p/q| ≤ 1/2N²`:

```
  2N² · |z·q − p·Q|  ≤  Q·q.                                                (5)
```

If none exists, or `q = 1`, the sample is uninformative and the loop continues —
in particular the `z=0` outcome no longer returns order `1`. For an ideal phase
`s/r`, reduction gives

```
  q = r / gcd(s, r),                                                        (6)
```

a *divisor* of the true order, which is why `q=1` for `s=0` and why LCM
accumulation is needed.

### 4.4 LCM, verification, exact minimization, termination

Maintain a `BigInt` accumulator `L₀ = 1`, `L ← lcm(L, q)`. Genuine candidates
(6) all divide `r`, so `L | r < N`; if a new LCM would reach `≥ N`, treat the
history as contaminated and **restart the accumulator from the current `q`** (no
unbounded growth). After every update test `a₀^L ≡ 1 (mod N)` with
`powermod(BigInt(a₀), L, BigInt(N))` — never form `a₀^L`. Passing proves the true
order **divides** `L`; then apply the §1.Δ7 prime-strip minimization and return
`Int(L)`.

Termination — exactly one of:
- returns the exact, verified, minimized order;
- throws `NonCoprimeBaseError(a, N, g)` (factor already found);
- throws `OrderFindingFailure(a₀, N, max_samples, history)` after `max_samples`,
  distinguishing "no useful candidate," "candidates never verified," and
  "only contaminated histories."

It never returns `nothing`, a raw denominator, an unverified LCM, or `1` from an
uninformative sample. Runtime *success* is probabilistic; the returned value is
always verified and minimal.

---

## 5. F23 overflow policy

**Decision.** `Int(x)` is an honest machine-`Int` cast: it returns an actual `Int`
or throws **before** backaction. It never silently returns `BigInt`. The wide
consuming cast is `BigInt(x)` (Δ3).

```julia
Int(x::QInt{W,C})            -> Int      # admits 1 ≤ W ≤ Sys.WORD_SIZE - 1
Int(v::DualView{<:QInt{W,C}}) -> Int
BigInt(x::QInt{W,C})            -> BigInt  # every W ≥ 1
BigInt(v::DualView{<:QInt{W,C}}) -> BigInt
```

`Int` admits exactly `1 ≤ W ≤ Sys.WORD_SIZE - 1` (all unsigned `W`-bit values fit
a signed machine `Int`; on 64-bit, `W ≤ 63`). For `W ≥ Sys.WORD_SIZE` it throws
**before** any `_measure_wire!`/basis transform:

> `Int(QInt{64}) cannot represent every 64-bit outcome on this 64-bit host; use BigInt(x). Rejected before measurement.`

For `Int(dual(x))` the check must fire **before** the Fourier basis transform is
applied — applying it and *then* failing would mutate the state before the error.
Exact DM/Tracing contexts still produce a fixed-width record/wire token; the limit
is on projection to a host scalar, not on wide registers or record wires. After
F16 the width/requested representation are carried in the classical handle and
remain inference-visible.

**Adjacent constructor repair (both proposals + synthesizer catch).** `1 << W`
overflows at boundary widths. Confirmed sites:
`src/types/qint.jl:66–67` (preparation range check — both proposals flagged) **and**
`src/surface/arithmetic.jl:79` and `:167` (`mod(a, 1 << W)` — **neither proposal
flagged; same overflow class**). All three must move to checked/widened arithmetic
(`big(1) << W`) and reject `W ≤ 0`. `src/` edits are out of this doc's write
scope; they are listed as M9 work items in the plan.

**Rejected:** auto-`BigInt` from `Int(x)` (breaks `Int(x) isa Int`); a new wide
*verb* (contradicts the no-`measure` ruling — `BigInt(x)` is a cast, not a verb);
silent wrap (categorically).

---

## 6. F24 `QMod` decision

**Static modulus in the type.** Concrete handle `QMod{N,W,C}` (Δ4), public partial
spelling `QMod{N}`; `W = ndigits(N-1;base=2)` derived, inner constructor rejects
inconsistent `(N,W)`. No `modulus` field. Public constructors:

```julia
QMod{N}(v::Integer = 0) where {N}          # -> QMod{N,W,C}
QMod(::Val{N}, v::Integer = 0) where {N}   # -> QMod{N,W,C}
```

No `QMod(N::Integer, v)` dynamic constructor; no runtime-`N` `shor_order` wrapper
in M9 (`Val(N)` at a high-cardinality site would cause unbounded specialization
while hiding the static-program contract).

*Rationale.* `N` fixes the logical Hilbert dimension `C^N`, the group `Z_N`, which
multipliers are units, the conjugate transform `F_N`, promotion/mixed-modulus
laws, and the padded permutation (1). Two width-4 registers with moduli 13 and 15
do **not** carry the same symmetry structure; a runtime field would collapse them
to one concrete type and defer algebra/dispatch/lowering to runtime branches —
contradicting the same reasoning that puts `W` in `QInt{W}` and P7's requirement
that the register type *declare* its symmetry structure. Per-modulus
specialization is an accepted cost (modular multiplication already needs an
`N`-specific compiled permutation). A future unbounded-modulus service may
introduce a *distinct* dynamic register type; it must not weaken `QMod`. The
modular process value is a canonical zero-phase `Perm` on `2^W` states and remains
`U(N)` (F9/`rlhj`) — nothing here reintroduces a phase quotient.

---

## 7. Catches — where a proposal was wrong or contradicted shipped code

1. **A: order-1 bug (Δ7).** No `a₀ == 1 ⇒ return 1` guard; A throws
   `OrderFindingFailure` for the legitimate order-1 case (all samples `z=0`).
   Adopt B's guard.
2. **A: `QMod{N,R,C}` mismatches shipped convention (Δ4).** F16/`vanm` is
   **already shipped** (`QInt{W,C}`, `QBool{C}` in `src/types/register.jl`);
   A's `BinaryPadded{W}` repr layer does not parallel it. Adopt B's `QMod{N,W,C}`.
   Both proposals also mis-frame F16 as future/in-flight.
3. **Both: missed `src/surface/arithmetic.jl:79,167` overflow (§5).**
   `mod(a, 1 << W)` wraps for `W ≥ WORD_SIZE` — same class as the `qint.jl:66-67`
   bug both flagged. List all three repair sites.
4. **A: `2W < Sys.WORD_SIZE` Shor precondition is the wrong constraint (§4.1).**
   Redundant once `BigInt(x)` + `BigInt` CF arithmetic are adopted, and it never
   binds in practice — the Orkan qubit budget (`2W ≲ 30 ⇒ W ≲ 15`) is far tighter.
   The real precondition is the backend qubit budget, checked at allocation.
5. **A: `INPLACE_EXHAUSTIVE_MAXW = 16` is a fresh magic number (Δ1).** The
   codebase already has `PERM_EQ_MAXW = 20` (`src/kernel/numerics.jl:87`) as the
   `Perm` semantic-tractability ceiling; reuse it. B ties to it correctly.
6. **Both/shipped: §4.1a `PermClean` bullet is too narrow (Δ5).** It grounds the
   certificate in Bennett's *input-preserving* `(★)`; the in-place artifact
   transforms data in place (`|x⟩_D|0⟩ ↦ |f(x)⟩_D|0⟩`) and needs the general
   `(I−ιι†)Wι=0` containment justified by the inverse-pair theorem. Requires the
   staged §4.1a generalization (§8.4) — no new `CleanCert` variant.

---

## 8. Staged PRD amendments — apply post-`vanm`, under the doctest lint

These are **not** applied by this round. Each block gives exact replacement text a
later wording pass installs while the `test/test_prd_examples.jl` doctest lint is
green. Line anchors are as of commit `e834d36`.

### 8.1 §7.7 — replace the `shor_order` listing (`Sturm-PRD-v2.md:1636–1669`)

Replace the docstring signature line and the function body:

- Signature → `shor_order(a, ::Val{N}; max_samples=32) -> Int`; derive `W` from `N`.
- Add the `gcd(a,N)=1` precondition (→ `NonCoprimeBaseError`) and `a₀==1 ⇒ 1`.
- Split the one-shot quantum kernel (`_shor_phase_sample`, §4.2) from the repeated
  classical driver (§4.3–4.4).
- Keep the corrected `2W:-1:1` schedule (F21) and `BigInt(dual(k))`.
- Replace `Int(dual(k))`/`r / 4^W`/`rationalize`/`denominator(...)` with
  `Q = big(1) << (2W)`, exact continued fractions (eq 5), skip `q=1`, `lcm`
  accumulation, `powermod` verification, prime-strip minimization, and
  `OrderFindingFailure` at the retry limit.
- Document `mulmod!` as the full-space in-place permutation (eq 1, identity on the
  tail) and add the `using Bennett` weakdep precondition (as §§7.4–7.5).

Exact replacement body: the two listings in §4.2 (`_shor_phase_sample`) and a
driver stub whose contract is §4.4, with the return claim:

> Returns the exact multiplicative order after verification and minimization, or
> throws `OrderFindingFailure` after `max_samples`; throws `NonCoprimeBaseError`
> (carrying the factor) if `gcd(a,N) ≠ 1`.

### 8.2 §7.6 — wording only (`Sturm-PRD-v2.md:1603–1610`)

The example already uses `@cases Bool(m)` (Ruling D). Changes:
- state explicitly that `Bool(m)` is the consuming qc cast and `@cases` branches
  on its result; retain rejection of a bare quantum-register operand (F30);
- require both observation branches in the injection channel tests;
- remove any concurrent-edit residue mentioning a `measure` verb.
No modular-arithmetic change belongs in §7.6.

### 8.3 §3.4 — add a paragraph after the M7 accumulate form

- `b ⊻= oracle(f,x)` remains the two-register XOR-accumulating action;
- registered library actions may use `compile_inplace_perm(verify_inverse_pair(
  f, finv, Val(W)))`; the in-place contract is eq (3), **not** input discard;
- both directions must Bennett-compile and carry an exact inverse proof (Tier E
  ≤ `PERM_EQ_MAXW`, else a registered structural proof);
- only full-width accumulated outputs are admissible;
- the result is a phase-free `Perm`, hence closed under `ctrl`; MBU is excluded by
  construction in every context — only fixed `ReversibleCircuit → Perm` artifacts
  cross this boundary (qualify any prose suggesting MBU may be selected outside
  control).

### 8.4 §4.1a — generalize the `PermClean` bullet (`Sturm-PRD-v2.md:1116–1121`)

Replace the bullet with (exact staged text):

> - **`PermClean`** — the body is a single `Perm` (or `ctrl^k` of one) with
>   declared ancilla ports whose clean-subspace return `(I − ιι†)Wι = 0` is
>   guaranteed by a **closed generator-structure theorem** — either Bennett's
>   `(★)` `P_f : |x⟩|t⟩|0⟩ ↦ |x⟩|t⊕f(x)⟩|0⟩` (the accumulate form; the `oracle`
>   path), or the **inverse-pair compute/swap/uncompute theorem**
>   `|x⟩_D|0⟩_B|0⟩_A ↦ |f(x)⟩_D|0⟩_B|0⟩_A` (the in-place form; the
>   `compile_inplace_perm` path, with `f⁻¹` separately compiled and verified).
>   `ctrl(Perm)=Perm` keeps it phase-free under control. Acquisition stays
>   combinator-carried (`oracle ⇒ PermClean`, `compile_inplace_perm ⇒ PermClean`);
>   the checker validates the private-constructor provenance, never an arbitrary
>   `Perm` plus an assertion. No new certificate variant is introduced.

And in the acquisition sentence (`:1144`) add `compile_inplace_perm ⇒ PermClean`
alongside `oracle ⇒ PermClean`.

### 8.5 §3.1/§3.2 — F23/F24 representation and cast bounds

- concrete `QMod{N,W,C}` with derived-width invariant, `N` static;
- `Int(QInt{W})` admits `1 ≤ W ≤ Sys.WORD_SIZE-1`, rejecting wider **before**
  backaction; `BigInt(QInt{W})` is the explicit wide consuming cast for every
  `W ≥ 1`; reject `W ≤ 0`.

**Staged amendment titles (for the wording pass):**
1. §7.7 — `shor_order(a, ::Val{N})` bounded-driver rewrite.
2. §7.6 — `Bool(m)`/`@cases` wording, both-branch tests, drop `measure` residue.
3. §3.4 — in-place-`Perm` action paragraph + MBU qualifier.
4. §4.1a — generalized `PermClean` bullet (two theorems, two combinators).
5. §3.1/§3.2 — `QMod{N,W,C}`, static `N`, `Int`/`BigInt` width bounds.

---

## 9. Test plan

All equivalence at the permutation or channel level, never output marginals alone.

### 9.1 Full-space permutation laws
`M9.MULMOD.FULL-SPACE-BIJECTION` — for `(c,N)` in `(2,3),(2,5),(2,15),(4,15),
(7,15),(14,15),(3,16),(2,21),(5,21),(8,3),(8,5)` (incl. power-of-two tail-empty
cases): sorted image list `== 0:2^W-1`; every `v ≥ N` fixed; `v < N` agrees with
exact modular multiply; `π_d(π_c(v))==v` and `π_c(π_d(v))==v`; `P†P=I`. Explicit
`N=15` regression: `π(0)=0`, `π(15)=15`.
`M9.MULMOD.NONUNIT-FAILS-BEFORE-ACTION` — `(3,15),(5,15),(2,10)`: error names
`gcd`; no allocation/mutation/control emission occurred.
`M9.MULMOD.OVERFLOW-FREE-REFERENCE` — cross-check the fixed-loop helper vs
`BigInt(c)*BigInt(v) % N` near native-width boundaries.
Negative: `N<2`, inconsistent `W`, negative `c` (after normalize).

### 9.2 Compiler contract
`BOTH-COMPILE` (both artifacts pass every M7 structural check);
`EXHAUSTIVE-INVERSE` (asymmetric small perms, verify 3-inv on all inputs);
`WRONG-INVERSE-REJECTED` (bad `finv`; first counterexample before apply);
`ONE-SIDED-REJECTED` (opposite-composition check fires);
`NONBIJECTION-REJECTED` (many-to-one `f` fails even if both compile);
`GENERIC-WIDE-NEEDS-PROOF` (`W = 21 > PERM_EQ_MAXW` generic pair rejected, not
sampled); `REGISTERED-PROOF-ACCEPTED` (modular proof accepted above the ceiling
without a skip flag); `SHARED-ANCILLA-POOL` (`nwires == 2W + max(A_f,A_g)`, not
the sum); `BIT-ORDER-TRIPWIRE` (asymmetric carry perm so reversing either role
table changes the mapping — only `_role_tables` reverses); compile-failure
messages name the failing side.

### 9.3 In-place denotation & scratch cleanliness
`CLEAN-SCRATCH` (every basis + several coherent inputs: all copy/ancilla wires
exactly `|0⟩` before release); `IN-PLACE-REPLACE` (data replaced in place, no
surviving input copy; application returns the identical handle);
`SUPERPOSITION-PHASE` (asymmetric superposition; compare full statevector incl.
relative phases). Larger artifacts: three-way agreement (exact classical `π` /
Bennett fwd+inv simulation / Sturm execution).

### 9.4 Channel & control
`M9.MULMOD.CHOI` — where the internal width fits a **memory budget** (not the
pure-state qubit ceiling — F25), compare external-channel Choi with the ideal
permutation channel (incl. padded `N=3,5`); above budget use exhaustive
phase-free basis replay (a `Perm` is a canonical 0/1 matrix) + randomized
reference-assisted coherent probes, and state that no fake large "Choi test" runs.
`CONTROLLED-CHOI` — `when(ctrl) do mulmod!(y,c) end` vs `ctrl(ideal Perm)` on a
superposed/reference-entangled control (spurious phase / decoherence visible;
compare phase-fixed process matrices too, since Choi alone is phase-blind).
`MBU-EXCLUDED` — recorded value is a `Perm`, no observation/classical node,
`PermClean` accepted under a nonzero control stack, altered-scratch declaration
rejected structurally. `TAIL-COHERENCE` — prepare coherence between a valid
residue and a padded state, apply, compare full state (detects tail collapse).
`GUARD-EXTERNALITY` — aliasing the controlling wire rejected; nested distinct
controls via `ctrl^k(Perm)`.

### 9.5 Order-finding post-processing (deterministic)
`ZERO-SAMPLE-IGNORED`; `LCM-PROPER-DIVISORS` (`N=21,a=2`: denominators 2,3 → 6);
`CONTAMINATION-RESET` (LCM reaching `≥ N` resets); `SPURIOUS-NEVER-RETURNED`
(no return without eq a₀^L≡1); `MINIMIZE-VERIFIED-MULTIPLE` (`12` for order `6` →
`6`); `ORDER-ONE` (`a₀≡1` returns `1`, not `OrderFindingFailure` — the A-catch
regression); `NONCOPRIME-REPORTS-FACTOR` (`a=3,N=15`: factor `3` before
allocation); `EXHAUSTION-LOUD` (`OrderFindingFailure`, never `nothing`/raw
denominator).

### 9.6 End-to-end statistical
`M9.SHOR.END-TO-END-STATISTICAL` — for `(N,a,r) = (15,2,4)` and `(21,2,6)`, ≥ 1000
independently seeded driver trials, fixed documented `max_samples`. Assert: every
successful return equals the exact classical order; no wrong order ever returned;
`OrderFindingFailure`s counted separately; one-sided 99% binomial lower bound on
success ≥ 0.95. The threshold is justified in `shor_order_finding.md` from the
good-approximation/coprime-numerator probabilities, not chosen post-hoc. Cache
compiled modular permutations by **immutable value keys** (`(N,c,W,kwargs)` — never
`objectid(f)`) so the 1000 trials test sampling, not compiler setup; quantum state
is recreated every sample.

### 9.7 Overflow boundaries
`INT.WIDTH-BOUNDARY` (`W=B-1` admitted, `W=B` rejected, `B=Sys.WORD_SIZE`);
`INT.DUAL-FAILS-BEFORE-TRANSFORM` (wide `Int(dual(x))` rejects before its basis
transform); `BIGINT.WIDE-RECONSTRUCT` (`BigInt` reconstructs widths `B` and `2B`);
`PHASE-DENOMINATOR` (`Q = big(1)<<(2W)`; `2W=62,64` exact); `NO-OVERFLOWING-POWER`
(no `4^W` / signed `1<<W` on affected paths — including the `arithmetic.jl:79,167`
repair); widths `0`/negative rejected.

### 9.8 Inference
`QMOD.INFERENCE` (`@inferred QMod{15}(1)` and `QMod(Val(15),1)` → concrete
`QMod{15,4,C}`); `MULMOD-INFERENCE` (`y2 = @inferred mulmod!(y,2); y2 === y;
typeof(y2)===typeof(y)`); `STATIC-MODULUS-ONLY` (`QMod(15,1)` has no method;
`QMod{15}`/`QMod{21}` reach distinct specialized methods; no runtime `modulus`
field); `POSTPROCESS-INFERENCE` (deterministic CF/LCM helper and the successful
`shor_order` return path `@inferred Int`; `@code_warntype` on `mulmod!` and the
post-processing loop shows no `Any` in hot paths).

---

## 10. Open items for human ruling (carried, non-blocking)

1. Ratify `verify_inverse_pair`/`compile_inplace_perm` as `public`-not-exported
   (recommend **yes** — library-author machinery, not an eighth surface construct).
2. Ratify the cutoff = the existing `PERM_EQ_MAXW = 20` rather than a fresh
   constant (recommend **yes** — no drift; changing it is a resource-policy, not a
   semantic, decision).
3. Ratify `BigInt(x)` as the wide qc cast spelling (recommend **yes** — Δ3).
4. Trial-factorization minimization is scoped to the small-`N` capstone; a scalable
   factoring primitive is a later, semantics-preserving swap.
5. Whether a separately named dynamic-modulus register type should be scheduled
   now (recommend **defer** — file a follow-on bead if a high-cardinality workload
   appears).

Subject to these, the design removes the F7 non-unitarity, gives the Bennett
bridge an explicit in-place contract with a closed verification/certificate story,
makes every `shor_order` return exact and minimal, resolves both overflow sites
loudly, and keeps `QMod` aligned with shipped `QInt{W,C}` inference and P7
parametricity.
