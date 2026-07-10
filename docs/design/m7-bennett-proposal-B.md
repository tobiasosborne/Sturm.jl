# M7 Proposal B — the Bennett bridge (`oracle`), mechanics first

**Lens:** the concrete conversion pipeline and the wire-allocation choreography,
derived gate-by-gate, then checked against the semantic laws. The milestone is a
*plumbing* problem wearing a physics hat: a `ReversibleCircuit` on Bennett-numbered
wires must become a kernel `Perm` applied to *Sturm-numbered* wires, with a preset
target `b`, fresh ancilla, and the whole thing flowing through the §4.2 `ctrl`
choke point unmodified. Get the plumbing exactly right — one bit-order remap, one
accumulate substitution, one clean-free of scratch — and the physics (kickback,
D9, ctrl-homomorphism) falls out for free. Get it 1-wire wrong and you ship the
wm28 bug. So I design the plumbing first and prove the physics against it.

Empirical ground truth is fixed by two committed probes (`bennett-v2-compat-audit.md`,
`bennett-bit-order-probe.md`) and three additional Bennett compiles I ran for this
proposal (narrow `bit_width`, Bool-return width, decoupled I/O width — §4 below).

---

## 1. Executive summary (the decisions)

1. **`oracle(f, x)` compiles EAGERLY** (at the `oracle` call, not at `⊻=`) into an
   opaque **`OracleQuery`** value = a cached, x-independent **`CompiledOracle`**
   (the `Perm` + role tables) paired with the live handle `x`. Fail-fast: VM/loop/
   type/overlap errors surface at `oracle(f,x)`, the earliest surface point, naming `f`.
2. **Gate map is the audit's lossless one:** `NOTGate→MCX([],t)`, `CNOTGate→MCX([c],t)`,
   `ToffoliGate→MCX([c1,c2],t)`; `Perm(n_wires, gates)` with **Bennett wire indices
   verbatim** (no reversal in the gates).
3. **The bit-order remap lives in EXACTLY ONE function** (`_role_tables`, in the
   extension), and it never touches gate indices — it maps *register bit → Bennett
   wire index* (`sturm bit j ↔ bennett position W−j+1`, the probe formula). The
   Perm's own numbering `1:n_wires` is the tuple position; the reversal is entirely
   in how the apply-tuple is assembled.
4. **Accumulate by substitution (D9):** at `⊻=`, the tuple slot for each Bennett
   *output* wire points at `b`'s wire (low bits) or fresh clean scratch (high tail);
   input slots point at `x`; ancilla slots at fresh |0⟩. Because no output wire is
   ever a control (D9, re-asserted per-circuit), applying the Perm gives
   `|x⟩|b⟩|0⟩ → |x⟩|b⊕f(x)⟩|0⟩` by linearity — phase kickback is ordinary.
5. **Width contract (forced by §7.4):** `b`'s type sets the target width `Wb`
   (`QBool`→1, `QInt{Wb}`→`Wb`). Bennett couples output width to the compute width
   `W` (= input width). We accumulate the **low `Wb`** output bits into `b` and
   **assert the high `W−Wb` output bits clean |0⟩** before freeing them. `Wb>W` is a
   loud width error. This zero-tail witness is what makes an under-sized target
   (`f` overflows `b`) fail LOUD instead of silently decohering `x`.
6. **`x` supports `QInt{W}` (W∈1:64) via `bit_width=W`;** narrow widths verified
   (§4). Multi-register `oracle(f, xs...)` is designed-in (Bennett's `input_widths`
   is already a vector) but only single-register is on the M7 required path.
7. **Scratch is freed by `_free_clean!` — assert-|0⟩-then-drop-slot, NEVER
   measure-and-discard.** This is uniform under and outside `when` (no measurement =
   no guardrail-1 trip; a violated cleanliness assumption is loud, not silent).
8. **`loop_check_wires` non-empty ⇒ LOUD reject at compile, UNCONDITIONALLY**
   (stricter than the audit's "under control only" — argued in §7). The convergence
   flag is a dirty ancilla entangled with a superposed input; Sturm cannot certify
   it disentangled, so tracing it decoheres the oracle whether or not a `when` is up.
9. **MBU-exclusion is satisfied structurally, for free:** Bennett emits no
   measurement; the only accepted artifact is a `ReversibleCircuit`; a `Perm` is
   unitary by construction; `ctrl(Perm)=Perm`. There is nothing to exclude. The §3.4
   named test asserts the *type boundary* is the enforcement.
10. **`ctrl` flows unmodified:** `b ⊻= oracle(f,x)` under `when` lowers via the M5
    `_act!` → `ctrl^k(Perm) = Perm` (the perm.jl closure) → the existing ad.jl
    replay. M7 writes **zero new ctrl-lowering code** (the M5 IOU, discharged).
11. **Dependency wiring: weak dep + package extension** `ext/SturmBennettExt.jl`.
    LLVM.jl (Bennett's dep) must not infect `using Sturm`. Core owns the accumulate
    physics; the extension owns the `f→Perm` compile. Mirrors Bennett↔BennettVM's
    own write-once backend hook.
12. **Equivalence is checked at the CHANNEL level, never marginals:** `denoted_permutation`
    for `n_wires ≤ 20`, else exhaustive basis replay with **Bennett's own `simulate`
    as the classical ground truth**, plus a DM-context **Choi** check that catches
    any spurious phase. DJ §7.4 runs verbatim as the end-to-end phase witness.

**Three riskiest calls (flagged for the reviewer):**
- **(R1)** Unconditional `loop_check` rejection — deviates from the binding audit's
  "reject under control" toward strictly-more-conservative. Justified by the
  superposed-input entanglement argument (§7); the reviewer should confirm no
  milestone needs a definite-input loop oracle.
- **(R2)** The always-on **zero-tail clean witness** as the correctness backbone of
  the width contract (§4). It is a marginal read per tail wire on every `⊻=`; I
  argue correctness beats the cost (bounded: `W−Wb` wires, small for DJ), but it is
  a load-bearing per-op assertion.
- **(R3)** **Eager compile at `oracle()`** rather than lazy at `⊻=`. Cleaner errors
  and decoupled from `b`, but it means `q = oracle(f,x)` pays compile even if never
  applied, and it fixes `f`'s compile before `b`'s width is seen (the `Wb` check is
  deferred to `⊻=` regardless).

---

## 2. The conversion pipeline: `ReversibleCircuit → Perm`

```
Bennett                                  Sturm kernel
────────                                 ────────────
NOTGate(t)                       ──▶      MCX(Int[],        t)
CNOTGate(c, t)                   ──▶      MCX([c],          t)
ToffoliGate(c1, c2, t)           ──▶      MCX([c1, c2],     t)
ReversibleCircuit(n_wires, gs…)  ──▶      Perm(n_wires, [MCX…])
```

`MCX` is strictly more general than Bennett's three gates (arbitrary control
count), so the map is **total and lossless** and Bennett needs no change (audit
Q2). Crucially the Perm carries Bennett's wire indices **unchanged** — `Perm`
numbering `1:n_wires` *is* Bennett numbering. The `Perm` is then applied to a
`wires_tuple :: NTuple{n_wires, WireID}` whose position `i` is the Sturm wire that
plays Bennett wire `i`; `apply!`/`_emit!(::Perm)` already maps position→slot
(`ad.jl:299`). **Nothing about MSB/LSB appears in the gate list.**

`DECISION:` the extension builds the `Perm` and a set of **role tables** (§4)
once per `(f, W, kwargs)`, cached; the core reads the tables to assemble the tuple
per call. This is the single-remap discipline: the only place a bit index is
reversed is `_role_tables`, and a boot-lint can grep that `input_wires[`/
`output_wires[` indexing appears only there.

---

## 3. The opaque query value

```julia
# core (src/bennett/bridge.jl) — no Bennett types mentioned:
struct CompiledOracle
    perm::Perm                       # Bennett gates as MCX, n_wires numbering
    n_wires::Int
    in_positions::Vector{Vector{Int}}  # [reg][bit j MSB-first] → Bennett wire idx
    out_positions::Vector{Int}         # [bit β LSB-first, 0..W-1] → Bennett wire idx
    W::Int                             # Bennett output/compute width
    anc_positions::Vector{Int}         # Bennett ancilla wire indices
end

struct OracleQuery{Xs<:Tuple}
    compiled::CompiledOracle
    xs::Xs                            # the live input handle(s), e.g. (x::QInt{W},)
end
```

`DECISION:` **`oracle` is exported (surface construct 7); `OracleQuery` /
`CompiledOracle` are `public`** (documented, reachable as `Sturm.OracleQuery`, never
`using`-dumped). The user *binds* the value (`q = oracle(f, x)`) but never annotates
the type. Laziness: **compiled eagerly**, x-independent part cached (§9).

**Why not an eighth construct.** `oracle` is construct 7; the query is its *return*,
and the ONLY operation on it is `⊻=` (construct 3, the action family). It introduces
no new surface verb. This is exactly D9's ruling: `oracle!(f,x,b)` was rejected as an
eighth construct that "reads like a gate call"; `apply(oracle(f),(x,b))` was rejected
as naming a process value on the surface (§2). Our `OracleQuery` names nothing — it is
consumed by the existing `Base.xor` family, W=1,f=id being the plain `a ⊻= b` case.

---

## 4. Accepted `x` types and the width contract

**Empirical facts** (probes + my three compiles, `narrow_probe.jl`/`narrow2.jl`/`wid3.jl`):
- `reversible_compile(f, U; bit_width=W)` yields `input_widths=[W]`, `output_elem_widths=[W]`
  — **input and output widths are coupled** to the compute width `W`. Narrow `W`
  (tested `W=3`) works and trims to `W` I/O wires.
- A **Bool-returning** `f` is **zero-extended** to the full compute width: at native
  `UInt8`, `x->iseven(x)` gives `output_elem_widths=[8]`, with `f(x)` in bit 0 and
  bits 1..7 provably 0. There is **no** independent 1-bit output width.
- Multi-arg: `(x,y)->x+y` gives `input_widths=[8,8]`, `output_elem_widths=[8]`.

This forces the contract, because §7.4 *requires* `b::QBool ⊻= oracle(f, x::QInt{N})`
to work with an N-bit-input / 1-bit-valued `f`:

`DECISION:` **the target `b`'s type sets the target width `Wb`, and it may be
narrower than Bennett's output width `W`.** We accumulate the **low `Wb`** output
bits into `b` and route the **high `W−Wb`** output bits to fresh scratch that is
**asserted clean |0⟩** before being freed.

| target `b`         | `Wb` | output bits into `b`         | tail bits (asserted |0⟩) |
|--------------------|------|------------------------------|--------------------------|
| `QBool`, `WireRef` | 1    | bit 0 (Bennett out pos 1)    | bits 1..W−1              |
| `QInt{Wb}`         | Wb   | bits 0..Wb−1                 | bits Wb..W−1            |

- `Wb > W` → **loud** `ArgumentError` (target wider than the oracle output).
- `Wb == W` → no tail, no witness cost (the modular-arithmetic case).
- `Wb < W` and a tail bit is nonzero (i.e. `f`'s value doesn't fit `Wb`) → the
  **zero-tail witness fires loud**: "oracle output exceeds target width `Wb`; some
  f(x) ≥ 2^Wb". This is the **wm28 guard** — without it, an under-sized target would
  silently trace a nonzero, x-entangled wire and decohere the register.

**Input width.** `x::QInt{W}` compiles with `bit_width=W` (any covering native arg
type; the width comes from `bit_width`). `W∈1:64`; `W∉1:64` → loud (Bennett's own
`bit_width` bound). Multi-register `oracle(f, x::QInt{Wx}, y::QInt{Wy})` maps to
`input_widths=[Wx,Wy]`, one role table per register; **single-register is the M7
required path**, multi is designed-in and left for a follow-on bead.

`DECISION:` **reject `input_wires ∩ output_wires ≠ ∅`** (loud) — a self-reversing
prim writing results onto its input is incompatible with `b ⊻= oracle(f,x)` (b is a
*separate* target). Belt-and-braces: the bridge passes `auto_self_reversing=false`
so the default never produces overlap, and asserts disjointness anyway.

---

## 5. The `Base.xor` method table (return-value discipline)

Following `actions.jl`'s "THE RETURN-VALUE DISCIPLINE IS THE WHOLE GAME": every
method **mutates and returns its FIRST handle**, so `b = xor(b, q)` (what `b ⊻= q`
lowers to) is a true in-place no-op rebind; `x` stays live.

```julia
# 1-bit target (QBool or a borrowed slice x[i]):
Base.xor(b::AbstractQubit, q::OracleQuery) -> b        #  b ⊻= oracle(f, x)

# multi-bit target:
Base.xor(b::QInt{Wb}, q::OracleQuery) where {Wb} -> b  #  y ⊻= oracle(f, x)  (Wb bits)
```

Both dispatch into one shared `_apply_oracle!(ctx, b_wires, q)`; the only difference
is `Wb = 1` vs `Wb = W_of(b)` and the target wire vector `b_wires`. `a ⊻= b` (M4,
already landed) is the `W=1, f=id` degenerate case of the *same* family — no new
surface construct, exactly D9. There is **no** `xor(::OracleQuery, ::AbstractQubit)`
(the query is always the RHS); a swapped call is a `MethodError` (fail-loud, no
catch-all — mirrors P9).

---

## 6. Wire-allocation choreography (the core mechanic)

`_apply_oracle!(ctx, b_wires::NTuple{Wb,WireID}, q::OracleQuery)`:

```
0. ctx = _here(b);  _here.(q.xs)                       # context match, fail-loud
1. c = q.compiled
   Wb ≤ c.W                                             || width error
   b_wires disjoint from every x wire                   || "target aliases input x"
   (loop-free, no-output-as-control, in∩out disjoint    already asserted at compile)
2. # allocate fresh |0⟩ scratch: one per Bennett ancilla + one per tail output bit
   tail = c.W - Wb
   scratch = [ allocate!(ctx) for _ in 1:(length(c.anc_positions) + tail) ]   # region-owned |0⟩
3. # assemble wires_tuple[1:n_wires]: Bennett wire i → Sturm WireID
   wt = Vector{WireID}(undef, c.n_wires)
   for (reg, x) in zip(c.in_positions, q.xs), (j, pos) in enumerate(reg)
       wt[pos] = x.wires[j]              # input: MSB-first j already remapped in `pos`
   for β in 0:Wb-1                       # low output bits → b   (b MSB-first)
       wt[c.out_positions[β+1]] = b_wires[Wb-β]
   for β in Wb:c.W-1                     # high tail → scratch
       wt[c.out_positions[β+1]] = scratch[...]
   for a in c.anc_positions              # ancilla → scratch
       wt[a] = scratch[...]
4. _act!(ctx, c.perm, Tuple(wt))         # ← THE CHOKE POINT. empty stack: apply!;
                                         #   depth k: ctrl^k(Perm)=Perm, controls prepended
5. # free scratch, cleanest-possible: assert |0⟩ then drop slot (NO measurement)
   #   – tail wires: correctness witness (catches under-sized b) — ALWAYS
   #   – ancilla   : Bennett-guaranteed clean; asserted by default, opt-out for hot loops
   for w in scratch;  _free_clean!(ctx, w)  end
6. return b
```

Notes on each step, grounded:

- **Step 2/5 — why `allocate!` + `_free_clean!`, not `_alloc_scratch!`.** `apply!`
  needs `WireID`s (not raw slots), so scratch must be real wires. `_free_clean!(ctx,w)`
  = `_clean_ancilla_assert!(ctx, w)` (the M5 |1⟩-marginal witness, control-agnostic)
  then delete `wire_to_slot[w]` + `_return_slot!`. It **never measures**. This is
  strictly safer than `deallocate!`, which *outside* control does measure-and-discard
  — spending RNG and, on a wrongly-dirty wire, silently collapsing `x`. Inside
  control `deallocate!` already routes to the same clean-assert (via
  `_trace_and_free!`), so `_free_clean!` just unifies both regimes. The already-
  registered region-owned scratch wire is skipped by `_exit_region!` (it checks
  `haskey(wire_to_slot,·)`), so no double-free.
- **Step 4 — the ctrl choke point, unmodified.** `_act!` (surface/when.jl) is the
  M5 action-family sibling of `apply!`. Empty control stack ⇒ plain `apply!(Perm)`.
  Depth-k stack ⇒ `ctrl^k(c.perm)` built through the **public `ctrl` combinator**
  (perm.jl's `ctrl(::Perm)=Perm` closure: prepend one control wire to every MCX,
  shift indices) then `apply!` with the k control wires as the leading tuple slots.
  `ctrl(Perm)` is still a `Perm` — **no measurement, no phase** — so the controlled
  oracle stays in the zero-phase-freedom corner (perm.jl header). M7 adds **no**
  ctrl-lowering code. Guardrail 2 (guard-externality) fires for free: `_act!` runs
  `_guard_externality` over `Tuple(wt)`, so an oracle touching the `when` control
  register is a loud error.
- **Step 4 — aliasing.** `apply!`'s `_check_wire_aliasing` requires every tuple slot
  distinct; input(x), output(b), and scratch are distinct `WireID`s by construction
  (step-1 disjointness + fresh scratch), so it passes; a `b ⊻= oracle(id, b)` (b
  aliases x) is caught at step 1 with a bridge-specific message before the generic
  backstop.

This is the v0.1 `apply_reversible!` shape (ancilla alloc → apply gates → dealloc
ancilla; "inside when() gates auto-control via the stack") re-expressed against the
v2 kernel: one atomic `Perm` value through `_act!` instead of a hand gate loop, and
the **condemned `NOT→Rz(π);Ry(π)` lowering replaced by the exact `MCX([],t)`** (the
v0.1 latent-phase bug the deprecated header itself flags is structurally impossible
here — `Perm` denotes a 0/1 matrix).

---

## 7. Control-awareness

### 7a. `loop_check_wires` — LOUD reject at compile, unconditionally (R1)

The probe (§2e-ii) and `gates.jl`'s `LoopGuard` doc establish: a data-dependent loop
leaves a **convergence flag** wire (`1` iff the loop converged within `K` for *this*
input) that **survives the reverse pass** — it is not uncomputed, and it is
input-dependent (`x=3 → 1`, `x=200 → 0`).

`DECISION:` `_role_tables` (compile) **rejects any circuit with `!isempty(loop_check_wires)`**,
loud:

> `oracle(f, x): f compiles to a data-dependent loop whose convergence flag is a`
> `dirty ancilla (loop header :L2, K=6). It survives as a wire entangled with a`
> `superposed input, and Sturm cannot certify it disentangled — tracing it would`
> `silently decohere the oracle (wm28 class). Restructure f to be loop-free /`
> `statically-bounded, or raise max_loop_iterations so the loop fully unrolls to a`
> `constant trip count (then loop_check_wires is empty).`

**Physics, both cases (why unconditional, stricter than the audit):**
- *Under a `when` control:* the flag is entangled with a superposed *control*; tracing
  it decoheres the guard — measurement under `ctrl` is unrepresentable (§3.4/§4.4).
  This is the audit's stated rule.
- *Outside control:* the actual oracle use is a *superposed* input (`superpose!(x)` in
  DJ/BV). The flag is entangled with `x`; `_free_clean!`'s assert would fire (it's not
  |0⟩), and even measure-and-discard would collapse `x`. It is safe **only** if every
  input in the superposition converges within `K` — a property Sturm cannot verify
  without exponential exhaustive simulation. Since the type system cannot distinguish a
  definite from a superposed `x`, FAIL-LOUD-ALWAYS (constitution #1, #3) is the only
  sound rule. Loop-free / statically-bounded `f` (all of DJ, BV, adders, mulmod) have
  **empty** `loop_check_wires` and are entirely unaffected.

**Reviewer check (R1):** confirm no M7–M11 milestone needs a loop-carrying oracle on a
*definite* input outside `when` (I claim none does; Shor's mulmod is statically-sized).

### 7b. MBU exclusion (§3.4) — structural, the named test asserts the boundary

MBU does not exist in the accepted artifact: Bennett's `ReversibleCircuit` has only
`NOTGate/CNOTGate/ToffoliGate` (audit Q3), every `BennettStrategy` emits only those,
and `Perm` is unitary by construction. So the §3.4 "exclude MBU under a nonzero
control stack" requirement is met by the **type boundary itself** — an MBU lowering is
not a permutation, cannot be a `Perm`, cannot cross into a `when` body. There is
nothing to select-against.

`DECISION:` `oracle` accepts **only** `ReversibleCircuit` (D14 ruling A). A future
`VMProgram` (or any non-`ReversibleCircuit`) → **loud error** ("f requires the Bennett
VM (unbounded loop / dynamic memory); the VM lowering is not a fixed permutation and
is out of scope for the reversible bridge — D14"). If Bennett ever grows MBU, D14
mandates it be a **distinct return type**, and the same `isa ReversibleCircuit` gate
keeps enforcing exclusion with no bridge change.

**Named test `test_m7_mbu_exclusion` (content):** (1) compile a real 3-bit oracle;
apply `b ⊻= oracle(f,x)` *inside* `when(c) do … end`; assert it runs, `x` stays live,
and the resulting channel equals `ctrl(classical-f permutation)` at the **Choi** level
(DM context); (2) assert `all(g -> g isa MCX, q.compiled.perm.gates)` — the unitary
witness is the `Perm` itself; (3) a construction-level assertion that the accepted
artifact type is `ReversibleCircuit` and that a stubbed non-circuit return is rejected
loud. The test's docstring states: *MBU-exclusion holds because the boundary admits
only phase-free permutations; this test guards the boundary, not a strategy selector.*

---

## 8. Dependency wiring — weak dep + package extension

`DECISION:` **`[weakdeps] Bennett` + `[extensions] SturmBennettExt = "Bennett"`.**

Rationale (Julia-idiomatic, CLAUDE.md conv 4/7):
- Bennett pulls **LLVM.jl**. Forcing every `using Sturm` (M0–M6, all non-oracle work)
  to precompile LLVM.jl is an unacceptable, unnecessary dependency. A hard `[deps]`
  path/registry dep is wrong.
- Package **extensions** (Julia ≥ 1.9; Sturm's floor is 1.11) are *the* modern
  mechanism for "optional glue that only activates when a second package is present."
  The extension loads exactly when the user does `using Bennett` alongside `using
  Sturm`.
- It mirrors Bennett's OWN pattern: BennettVM registers itself into Bennett's
  write-once `_REVERSIBLE_VM_BACKEND::Ref{Any}` hook to avoid a dependency cycle
  (audit Q4). We use the identical shape.
- **Reject** Requires.jl (pre-1.9 legacy, superseded). **Reject** a hard path dep
  (LLVM infection).

**Split of responsibilities:**
- **Core** `src/bennett/bridge.jl` — pure Sturm, no Bennett type named: `OracleQuery`,
  `CompiledOracle`, `oracle(f, x...)`, the `Base.xor(b, ::OracleQuery)` methods, the
  step-6 choreography, `_free_clean!`, and a backend hook
  `const _BENNETT_BACKEND = Ref{Any}(nothing)`. `oracle` calls
  `_BENNETT_BACKEND[] === nothing && error("oracle(f,x) needs Bennett — add `using Bennett`")`
  then `_BENNETT_BACKEND[](f, W, kw)`.
- **Extension** `ext/SturmBennettExt.jl` — `using Bennett`; `__init__` sets
  `Sturm._BENNETT_BACKEND[] = _compile`. `_compile(f, W, kw)` calls
  `reversible_compile(f, _covering_type(W); bit_width=W, auto_self_reversing=false, kw...)`,
  runs the four compile-time rejections (VM/non-circuit, loop_check, in∩out overlap,
  output-as-control), and builds the `CompiledOracle` via `_role_tables` (the **single
  bit-order remap**). The `ReversibleCircuit`, `NOTGate`, … names appear ONLY here.

This keeps the physics (accumulate, ctrl, clean-free) in core where the law tests
live, and quarantines the LLVM-touching compile behind the extension.

---

## 9. Caching

- **Bennett-side (free):** `_extract_parsed_ir_cached` memoises IR extraction on
  `(f, types, optimize, mem)` and returns the *same* `ParsedIR` instance, so the
  lowering `_compile_cache` (keyed on `objectid(parsed)+kwargs`) also hits on repeat
  `reversible_compile(f, T; kw)`. Same `(f,types,kw)` ⇒ no recompile.
- **Sturm-side:** `const _ORACLE_CACHE = Dict{Any,CompiledOracle}()` behind a
  `ReentrantLock`, keyed on **`(objectid(f), W, kw_tuple)`** — the x-independent part.
  Avoids rebuilding the MCX list + role tables (O(gate count), up to ~2000 gates)
  per `oracle` call. `x`'s actual `WireID`s are bound per call in `OracleQuery`, never
  cached. Caveat (documented, matches Bennett's own): a **fresh anonymous closure**
  each call has a new `objectid` ⇒ cache miss; a named `f` / `const` closure hits.

---

## 10. Error-path enumeration (all fail-loud)

| # | condition | when caught | message gist |
|---|-----------|-------------|--------------|
| 1 | Bennett not loaded | `oracle` | "needs Bennett — `using Bennett`" |
| 2 | `f` returns/needs VM (non-`ReversibleCircuit`) | compile | "requires Bennett VM; out of scope (D14)" |
| 3 | `!isempty(loop_check_wires)` | compile | dirty convergence flag (§7a, R1) |
| 4 | `input_wires ∩ output_wires ≠ ∅` | compile | "self-reversing; incompatible with `b ⊻= oracle`" |
| 5 | an output wire appears as a control in some gate | compile | "circuit reads its own output; accumulate unsound (D9)" |
| 6 | `W ∉ 1:64` | compile | Bennett `bit_width` bound |
| 7 | unsupported arg type / no method `f(::T)` | compile | Bennett's own `ArgumentError` (surfaced at `oracle`) |
| 8 | `Wb > W` | `⊻=` | "target wider than oracle output" |
| 9 | `b` aliases `x` (shared wire) | `⊻=` step 1 | "target aliases oracle input x" |
| 10 | tail output bit ≠ |0⟩ (f overflows `Wb`) | `⊻=` step 5 | "some f(x) ≥ 2^Wb; widen b" (wm28 guard) |
| 11 | Bennett ancilla returns dirty (should never) | `⊻=` step 5 | clean-ancilla witness FAILED |
| 12 | oracle touches the `when` control register | `⊻=` step 4 | guardrail 2 (inherited from `_act!`) |
| 13 | cross-context handle | `⊻=` step 0 | `_here` ArgumentError (inherited) |

Errors 2–7 at **compile** = fail-fast at `oracle(f,x)`. Errors 8–13 at **apply**.
None is a silent fallback (D14: "never a silent fallback").

---

## 11. Verification against the semantic laws

- **Kickback linearity (D9 / Nielsen–Chuang §1.4.4).** Because (error #5 guarantees)
  no output wire is a control, each output wire `β` accumulates a fixed boolean
  function `g_β(input, ancilla)` by XOR, independent of the output wire's incoming
  value. So `|x⟩|b⟩|0⟩ → |x⟩|b ⊕ f(x)⟩|0⟩` for *any* `b`, and with `b=|−⟩` on a 1-bit
  target the map is `(−1)^{f(x)}|x⟩|−⟩`. The proof is the audit's D9 argument made a
  *per-circuit runtime assertion*, not a trusted invariant.
- **`ctrl` homomorphism (§4.2, Delorme Def 1).** The Perm crosses the choke point
  **unmodified**: `_act!` builds `ctrl^k` only through the public `ctrl(::Perm)`, and
  `ctrl(Perm)=Perm` closure means the controlled oracle is the same permutation with
  `k` leading controls prepended to every MCX. `ctrl(g∘h)=ctrl(g)∘ctrl(h)` is realised
  gate-by-gate by ad.jl's `_apply_controlled!(::Perm)` replay (`ad.jl:269`).
- **D9 dual composition.** DJ (`Int(dual(x))`, register/Fourier dual) and BV
  (`Bool(dual(x[i]))`, per-wire ℤ₂ duals) differ **only in readout** (M6 surface,
  already landed); the bridge is dual-agnostic — it just leaves `x` correctly
  phase-kicked. The bridge never applies `F`; it never double-covers a phase.

---

## 12. Verification plan (named tests, `test/test_m7_bennett.jl`)

All under `EagerContext` (probabilistic, seeded RNG) and, for channel claims,
`DensityMatrixContext` (exact Choi). **Never** an output marginal as the sole witness
(wm28).

1. **`test_gate_map`** — `NOT/CNOT/Toffoli → MCX([],t)/([c],t)/([c1,c2],t)`;
   `denoted_permutation(Perm) == denoted_permutation(hand-built MCX)` on tiny circuits.
2. **`test_bitorder_remap`** — compile `x->x` at W=3; assert `denoted_permutation`
   of the assembled Perm (input+output, ancilla=0) is the identity on 0:7 — i.e.
   Sturm executes `x↦x`, not the bit-reversal. Drives `x=0b001` and `x=0b100` and
   checks the *right* output wire lit (the wm28 tripwire).
3. **`test_oracle_equiv_denoted`** — for every small `f` (n_wires ≤ `PERM_EQ_MAXW`=20:
   const-0, const-1, a balanced 3-bit `f`, `x->x&1`): `denoted_permutation` of the
   full Perm equals the classical truth table (output block == f(x), ancilla → 0) for
   all `2^W` inputs. **This is the channel-level (permutation) equivalence**, exhaustive.
4. **`test_oracle_equiv_simulate`** — for wider `f` (n_wires > 20, e.g. an 8-bit adder,
   49 wires): use **Bennett's own `simulate(circuit, x)` as ground truth**; prepare
   `|x⟩` definite on Eager, apply the oracle into `b=|0⟩`, measure `b`, assert
   `Int(b)==simulate(circuit,x)==f(x)` over a basis probe set. Three-way agreement
   catches a reversed remap (Sturm ≠ f while Bennett == f).
5. **`test_accumulate`** — `b=QInt{W}(v); b ⊻= oracle(f,x)` gives `Int(b)==(v ⊻ f(x))`
   over a probe set — the D9 accumulate for nonzero `b`.
6. **`test_deutsch_jozsa`** — the §7.4 code **runs verbatim** (parsed by
   `test_prd_examples.jl` and executed): `deutsch_jozsa(const, Val(N))==true`,
   `deutsch_jozsa(balanced, Val(N))==false`, for N=2,3. On Eager: outcome 0 w.p. 1 for
   constant across N≥1000 shots. On DM: exact. This is the **end-to-end phase witness**
   — a spurious Z on the accumulate breaks it.
7. **`test_bernstein_vazirani`** — the §7.5 code verbatim: recovers `s` exactly for
   several `s`; **and the negative-control:** `Int(dual(x))` (register dual, the §7.4
   pattern) on the BV state for N=3,s=5 gives the spread/tied distribution
   `{1:0.073, 3:0.427, 5:0.427, 7:0.073}` (exact on DM) — proving the register dual and
   per-wire duals are inequivalent (D2), i.e. the bridge leaves the *correct*
   phase-kicked state and only the readout differs.
8. **`test_oracle_under_when`** (M5 IOU) — `when(c) do b ⊻= oracle(f,x) end`: assert
   the channel equals `ctrl(oracle channel)` at the **Choi** level (DM), streaming ≡
   the controlled Perm; assert `x`/`b` live after; assert scratch clean-freed under
   control (no guardrail-1 trip, since `_free_clean!` never measures).
9. **`test_m7_mbu_exclusion`** — §7b content.
10. **`test_ancilla_clean`** — full-marginal witness (not sampled): after `b ⊻= oracle(f,x)`
    over a probe set, every scratch/ancilla wire's |1⟩-marginal `< CLEAN_EPS`; and the
    **zero-tail** witness fires loud for an intentionally under-sized `b` (error #10).
11. **`test_loop_reject`** — a data-dependent-loop `f` **compiled with `optimize=false`**
    (the probe gotcha — the default optimizer folds simple countdowns to closed form,
    empty `loop_check_wires`, testing the wrong path) → `oracle(f,x)` throws error #3,
    both outside and inside `when`.
12. **`test_error_paths`** — errors #1,4,5,6,8,9,12,13 each fire with the right type.

`GOTCHA (must be in the test file header):` **`optimize=false`** is required to
exercise loop guards (probe §2e-ii); a naive suite silently tests the wrong code path.

---

## 13. File layout, exports, citations

```
src/bennett/bridge.jl        # core: OracleQuery/CompiledOracle, oracle, Base.xor
                             #   methods, _apply_oracle!, _free_clean!, backend hook
ext/SturmBennettExt.jl       # weakdep glue: _compile, _role_tables (THE remap),
                             #   the 4 compile-time rejections
test/test_m7_bennett.jl      # the §12 named tests
Project.toml                 # [weakdeps] Bennett; [extensions] SturmBennettExt="Bennett"
```

`src/Sturm.jl`: `include("bennett/bridge.jl")` after the M6 block; `export oracle`;
add `OracleQuery, CompiledOracle` to the `public` list. The boot-lint gains one grep:
`input_wires[` / `output_wires[` indexing appears only in `_role_tables`
(single-remap enforcement, wm28 discipline — mirrors the ctrl `_ctrl(` choke-point lint).

**Docstring citations** (§9 two-tier policy; distillations being written in parallel):
- `oracle` / `_apply_oracle!` → `docs/physics/bennett_1973_logical_reversibility.md`
  (compute-copy-uncompute; ancillas return to |e_G⟩), Nielsen–Chuang §1.4.4 (kickback).
- `deutsch_jozsa` → `docs/physics/deutsch_jozsa_1992.md` (one-query constant/balanced;
  outcome-0 amplitude `(1/2^N)Σ(−1)^{f(x)}`).
- `bernstein_vazirani` → `docs/physics/bernstein_vazirani_1997.md` (one-query `s`
  recovery; the per-wire ℤ₂ dual readout).
- D9 no-output-as-control assertion → the audit + Bennett gate-level verification;
  `ctrl(::Perm)` closure → `docs/physics/delorme_control_as_constructor.md` (already cited by perm.jl).

---

## 14. Performance notes

- **Perm size.** Real arithmetic is large: `x+3` at 8 bits ≈ **25 ancilla / 49
  wires** (probe 2d); a bounded 3-iteration loop unrolls to 220 gates / 225 wires
  (probe 2e). The `Perm` gate list is O(Bennett gate count); `apply!` emits each MCX
  through ad.jl's AND-ladder for `k>2` controls. Under `when` depth `d`, every MCX
  gains `d` controls → `(k+d)`-controlled X → more Barenco/AND-ladder scratch. Real
  but structurally bounded.
- **Sturm cache** (§9) keyed on `(objectid(f), W, kw)` amortises the MCX-list +
  role-table build across repeat `oracle(f, x)` calls; the compile itself is
  Bennett-cached. `denoted_permutation` in tests is gated at `PERM_EQ_MAXW=20` — DJ
  N=3 oracles (≤19 wires) are exhaustively checkable; wider oracles use the
  simulate-comparison path (test #4).
- **Zero-tail witness cost (R2).** One `_marginal_p1` (Eager, O(2^n)) per tail wire
  per `⊻=`. Bounded by `W−Wb` (small for DJ: N−1). Bennett-ancilla witness is default-on
  but carries a `check_ancilla=false` opt-out for production hot loops (Bennett
  *guarantees* those clean; the tail witness has no opt-out — it is correctness, not
  defense-in-depth).

---

## 15. Open risks & mitigations

| risk | mitigation |
|---|---|
| **R1** unconditional loop reject may be over-strict for a definite-input oracle | reviewer confirms no milestone needs it; the escape hatch is `max_loop_iterations` large enough to fully unroll (→ empty `loop_check_wires`) |
| **R2** always-on tail witness cost | bounded to `W−Wb` wires; no opt-out (correctness); the `Wb==W` common case has zero tail |
| **R3** eager compile pays for unused `oracle(f,x)` | rare; the Bennett+Sturm caches make a re-`oracle` free; keeps errors fail-fast |
| **objectid(f)** cache misses on anonymous closures | documented; matches Bennett's own limitation; named/`const` `f` hits |
| **Bennett couples I/O width** via `bit_width` | resolved by the low-bits/zero-tail contract (§4); empirically verified; DJ's 1-bit-valued `f` is the driving case |
| **future Bennett `auto_self_reversing`/strategy** produces input∩output overlap or reads outputs | bridge passes `auto_self_reversing=false` **and** asserts both invariants per-circuit (errors #4,#5) — a Bennett change breaks loud, not silent |
| **Bennett 1.12 CI** floor only (`julia="1.10"`, no green artifact) | audit Q5 recommends re-running Bennett's suite on the project 1.12.x as a hardening gate; the extension load is itself smoke-tested (probe: loads clean on 1.12.5) |
| **VMProgram / MBU future** | D14 ruling A: only `ReversibleCircuit` crosses; a distinct future type is auto-rejected by the `isa` gate; revisit as a new decision point |

---

## Appendix — the remap formula (from `bennett-bit-order-probe.md`, pinned)

For input/output register bit position `j` (Sturm MSB-first, 1..W) of a width-`W`
block with base offset in Bennett's `input_wires`/`output_wires`:
```
sturm register bit j  ↔  bennett positional index (W − j + 1)     # a per-block reversal
```
Bennett is positionally **little-endian** (position 1 = LSB); Sturm is **MSB-first**
(wire 1 = MSB). The reversal is a plain end-to-end flip *within each register block*,
never a bit-twiddle on wire values, and it lives in `_role_tables` **only**. Ancilla
and (rejected) loop-check wires carry no significance — any consistent slot placement,
applied uniformly across every gate via the `wires_tuple` map.
```
in_positions[reg][j]  = input_wires[ offset_reg + (W_reg − j + 1) ]     # j = 1..W_reg, MSB-first
out_positions[β+1]    = output_wires[ start_out + (β + 1) ]             # β = 0..W−1, LSB-first
```
