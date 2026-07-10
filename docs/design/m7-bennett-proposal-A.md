# M7 Proposal A — the Bennett bridge: `oracle(f, x)` as a `Perm`-citizen

**Lens: semantics first.** I start from what `oracle(f, x)` *denotes*, derive
the query value and the `⊻=` law from the denotation, and let the mechanics
(remap, ancilla plumbing, control-awareness) fall out as forced consequences.
Every "DECISION" below is a corollary of §0–§2, not a taste call. Ground truth
for the two empirical facts I lean on — bit order and loop-check dirtiness — is
`docs/design/bennett-bit-order-probe.md`; the API shape is
`docs/design/bennett-v2-compat-audit.md`. D9 and D14 are RESOLVED and binding.

---

## 0. What `oracle(f, x)` denotes

`f : ℤ_{2^W} → ℤ_{2^{Wout}}` is an ordinary Julia function. Bennett's theorem
(logical reversibility, `docs/physics/bennett_1973_logical_reversibility.md`,
compute–copy–uncompute) turns it into a **reversible permutation** `P_f` on
`n = W + Wout + A` wires that acts, on the computational basis, as

```
      P_f :  |x⟩_in |t⟩_out |0⟩_anc  ↦  |x⟩_in |t ⊕ f(x)⟩_out |0⟩_anc      (★)
```

for **every** `t` — the input block is preserved, the ancilla block returns to
`|0⟩`, and the output block is XOR-accumulated. (★) is the entire denotation.
Three facts about it are load-bearing and each is verified, not assumed:

- **P1 — it is a permutation on all `n` wires.** ⇒ it is a phase-free unitary
  ⇒ it is exactly a kernel `Perm` (perm.jl). Bennett's NOT/CNOT/Toffoli are the
  0/1/2-control cases of `MCX` (audit Q2; a lossless embedding).
- **P2 — the output block is only ever a CNOT/Toffoli *target*, never read as a
  control** (D9 ruling, gate-verified against the v0.1 quarry). This is *why*
  (★) holds for arbitrary `t`: XOR-accumulation is `t ↦ t ⊕ f(x)` by linearity
  (Nielsen–Chuang §1.4.4), independent of `t`. If P2 failed, (★) would hold only
  for `t = 0`.
- **P3 — the input and ancilla blocks are restored.** ⇒ after application, `x`
  is bit-for-bit its original self and every scratch wire is a clean `|0⟩`.

**The query value IS a process-value citizen.** `oracle(f, x)` denotes the pair
`(P_f, ρ)` where `P_f : Perm` is the compiled permutation and `ρ` is the
*role map* pinning which of `P_f`'s wires are the input block (bound to `x`),
which are the output block (bound at `⊻=`), and which are scratch. It is a
`Perm` plus an addressing — nothing more. It is not a channel, not a
measurement, not a new axiom.

---

## 1. The kickback law is the CNOT law lifted (D9)

`b ⊻= oracle(f, x)` must denote, by (★) with the output block bound to `b`'s
wires:

```
      |x⟩ |b⟩  ↦  |x⟩ |b ⊕ f(x)⟩          (kickback law)
```

This is **literally the same `Base.xor` action family as `a ⊻= b`** (surface
construct 3): `a ⊻= b` is the `W=1, Wout=1, f=identity, P_f = CNOT` case of the
exact same method (D9: "not a separate construct"). The generalisation is:
replace the single `ctrl(X)` with a `Perm`, and the single control/target wire
pair with the input/output *blocks*. Everything else — the return-value
discipline, the in-place semantics, the aliasing check — is inherited verbatim
from actions.jl.

With `b = |−⟩` (DJ/BV), (★) gives `|x⟩|−⟩ ↦ (−1)^{f(x)}|x⟩|−⟩` — the phase
kicks onto `x`, and `b` factors out unchanged to be traced at scope exit (§3.9).
That is phase kickback with **no new vocabulary**: `minus()` (D1 literal) +
`⊻=` (construct 3) + `oracle` (construct 7) + `Int(dual(x))` (construct 4).

**Composition with `dual` (D9).** The query value does not compose with `dual`
directly — by P3, `x` is *live and unchanged* after `⊻=`, so `dual(x)` is an
ordinary subsequent operation on an ordinary register. D9 interoperability is a
consequence of input-preservation (P3), not a special code path. Register dual
`Int(dual(x))` (DJ, §7.4) and per-wire duals `Bool(dual(x[i]))` (BV, §7.5) are
both just casts on the preserved `x` — the §7.4-vs-§7.5 distinction is D2, and
lives entirely in the cast layer, invisible to the bridge.

**Composition with `when`/`ctrl` (§4.2, the marquee fact).** A controlled
oracle must flow through the single `ctrl` choke point. It already does, for
free, because **`ctrl(Perm) = Perm`** (perm.jl closure): the reversible corner
is closed under control. So `b ⊻= oracle(f, x)` under a depth-`k` control stack
lowers — via the *existing* `_act!` — to `ctrl^k(P_f)`, still a `Perm`, applied
with the `k` control wires prepended. **M7 writes zero new ctrl-lowering code**
(exactly the M5 forward-flag). Measurement-based uncompute cannot arise because
a `Perm` is phase-free-unitary by construction (§7).

---

## 2. The query value

**DECISION (type):** a small immutable struct, `OracleQuery`, holding the
compiled `Perm` and the role map — a *pure Sturm object* (no Bennett types leak
into it):

```julia
struct OracleQuery
    perm::Perm                      # P_f on n = W + Wout + A wires (kernel-numbered)
    in_slots::Vector{Int}           # Perm-wire indices of the input block, MSB-first
    out_slots::Vector{Int}          # Perm-wire indices of the output block, MSB-first
    anc_slots::Vector{Int}          # Perm-wire indices of scratch (return to |0⟩, P3)
    xwires::NTuple{W,WireID} where W # the bound input register's wires (x stays live)
    W::Int                          # input width
    Wout::Int                       # output width  → dictates the b type at ⊻=
end
```

`in/out/anc_slots` are 1-based indices into `perm`'s own `1:n` wire numbering;
`perm` keeps Bennett's wire numbering unchanged (no gate rewriting — see §3, the
remap lives only in *which physical wire each slot binds to*, not in the gate
list). The struct is a `Perm` + addressing, exactly the §0 denotation.

**DECISION (laziness — compile eagerly at `oracle()`):** `reversible_compile`
needs only `f` and `W` (both known at `oracle(f, x)`), so compilation and *all
f-dependent validation* (compilability, loop-check rejection §5, VM rejection
§6, `W ≤ 64`) happen at the `oracle()` call site — errors point at the user's
`oracle(...)`, not a downstream `⊻=`. The `⊻=` is then pure wire-plumbing and
only *b-dependent* validation (width, aliasing, liveness). This is the honest
split: `oracle()` validates `f`; `⊻=` validates `b`. Binding `q = oracle(f, x)`
and applying it to several targets (`b1 ⊻= q; b2 ⊻= q`) reuses the one compiled
`Perm` — value-level reuse is the *only* caching M7 ships (see §8).

**DECISION (layer — surface-produced, kernel-Perm-backed, NOT exported as a
type):** `oracle` is exported (construct 7). `OracleQuery` is marked `public`
(Julia 1.11) — reachable as `Sturm.OracleQuery` for resource introspection, but
never dumped into `using Sturm` and never a *named surface noun*. Users write
`oracle(f, x)` and `⊻=` it; they never spell the type. This is precisely why it
is **not an eighth construct**: it is the *lowering vehicle* of an existing pair
of constructs (7 produces it, 3 applies it), exactly as `Perm` itself is a
kernel value banned from the surface by §2. The two D9-rejected spellings
(`oracle!(f, x, b)`; `apply(oracle(f), (x, b))`) are rejected here for the same
reason: they would make the vehicle a surface noun.

---

## 3. Argument types, widths, and the ONE remap

**DECISION (accepted `x`):** ship and test `x::QInt{W}` (DJ/BV/Shor) and
`x::QBool` (the `W=1` case, Bennett arg type `Bool`). *Design for* multi-register
`oracle(f, x, y, …)` (store a tuple of input registers, use Bennett's per-element
offset from probe §4) but **defer it past M7** — no shipped milestone (M7 IOUs
are single-input) needs tuple-arg Bennett compilation on the critical path. No
catch-all on `x`: any other type is a `MethodError` (P9 discipline).

**DECISION (width contract):** `x::QInt{W}` compiles at
`reversible_compile(f, T; bit_width=W, …)` with
`T = _bennett_arg_type(W; signed)`. Bennett's `bit_width` (verified: `1..64`,
`test_narrow.jl` exercises widths 2 and 4) is *genuine* narrowing — the oracle
computes mod `2^W`, matching `QInt{W}`'s `ℤ_{2^W}` ring exactly (so
`oracle(x->x+1, QInt{3})` wraps mod 8, not mod 256). `W > 64` is a loud error
(Bennett's native-width ceiling).

**DECISION (default `signed=false`, a correction from the v0.1 quarry):** `QInt`
is unsigned `ℤ_{2^W}`, so the honest Bennett type is `UInt*`. For `+/-/*` the
two's-complement bits are identical either way; the difference bites only on
`>>`/`÷`/comparison, where unsigned is what `QInt` means. The user may override
`signed=true`.

**DECISION (`auto_self_reversing=false`, forced):** the kickback law needs the
output block **disjoint from** the input block (P2/P3). Bennett's default
`auto_self_reversing=true` may, for provably-in-place-safe `f`, alias output onto
input — which would make `b ⊻= oracle(f, x)` ambiguous (b and x would share
wires). Passing `auto_self_reversing=false` engages the "forward + copy-out +
reverse" construction end-to-end (Bennett `bennett_transform.jl:188`,
`tabulate.jl:205`) ⇒ fresh disjoint output, `x` provably preserved. Belt-and-
suspenders: the bridge **asserts** `in_slots ∩ out_slots == ∅` post-compile —
a fail-loud witness that (★)'s precondition holds.

**DECISION (the MSB/LSB remap lives in exactly ONE function).** Sturm pins
wire 1 = MSB (qint.jl:13); Bennett is positionally little-endian, position 1 =
LSB (probe §3, proven by carry-chain signature — increment lights position 1 as
the LSB). The remap is the probe's §4 formula, applied only when building the
role map from a `ReversibleCircuit`:

```
    sturm_position j  ↔  Bennett_position (W − j + 1)      # per register block
```

Everything else — ancilla slots, loop-check slots (rejected, §5), the gate list
itself — is carried through *identically* (`perm` keeps Bennett's numbering).
A silent bit-reversal survives every marginal test (wm28 class), so it is caught
at the **permutation** level on an *asymmetric* `f` (§7, T4: increment).

---

## 4. The `⊻=` application methods

Two methods on `Base.xor`, one per output arity, both obeying the actions.jl
return-value discipline (mutate-and-return-first-handle; `x` stays live):

```julia
# Wout == 1  (DJ, BV):  b::QBool receives f(x) ∈ {0,1}
function Base.xor(b::AbstractQubit, q::OracleQuery)
    q.Wout == 1 || error("oracle target arity: f has Wout=$(q.Wout) output bits; \
        bind a QInt{$(q.Wout)} target, not a QBool")
    _apply_oracle!(b.ctx, q, (b.wire,))          # target block = (b,)
    return b
end

# Wout == W:  b::QInt{Wout} receives f(x)
function Base.xor(b::QInt{Wout}, q::OracleQuery) where {Wout}
    q.Wout == Wout || error("oracle target width mismatch: f produces \
        $(q.Wout) bits but target is QInt{$Wout}")
    _apply_oracle!(b.ctx, q, b.wires)            # target block = b.wires, MSB-first
    return b
end
```

`_apply_oracle!` is the whole mechanism, and it is deliberately thin:

```julia
function _apply_oracle!(ctx, q::OracleQuery, targets::NTuple{Wout,WireID})
    _here(_adopt_qint(ctx, q.xwires))            # liveness + cross-context on x (inherits qint _here)
    # b ⊄ x — the kickback target must be a DISTINCT register (else output aliases input)
    isdisjoint(Set(targets), Set(q.xwires)) || error(
        "oracle target aliases its input register — b shares wire(s) \
        $(intersect(Set(targets), Set(q.xwires))) with x; the kickback target \
        must be a distinct register (D9, §8.4).")
    # (loop-check and VM already rejected at oracle() compile — §5/§6.)
    region() do                                   # scratch is born and dies here (§3.9)
        anc = ntuple(_ -> allocate!(ctx), length(q.anc_slots))   # fresh |0⟩, uncontrolled (§3.9)
        wires = _assemble(q, targets, anc)        # length-n tuple in Perm-slot order
        _act!(ctx, q.perm, wires)                 # control-aware: ctrl^k(Perm)=Perm (§1)
        # anc traced at region exit: outside `when` → measure-and-discard (P3: they're |0⟩);
        # under `when` → clean-ancilla assert (P3 guarantees it passes).
    end
    return ctx
end
```

Three inheritances make this thin:

- **Control-awareness for free.** `_act!` (surface/when.jl) already wraps
  `ctrl^k` via the *public* `ctrl` and prepends the stack controls. `ctrl(Perm)`
  stays a `Perm` (perm.jl), so a `when`-wrapped oracle is one bigger `Perm` —
  the M5 IOU discharged with no ctrl code.
- **Aliasing for free.** `apply!`'s `_check_wire_aliasing` fires on any repeated
  `WireID` in `wires` (§8.4). The explicit `isdisjoint` check above front-runs it
  with a *register-level* message (b vs x), per defect-ledger 8.4.
- **Scope for free.** The `region() do … end` makes scratch ancillas
  region-owned; P3 guarantees they exit as clean `|0⟩`, so the §3.9 exit-trace
  is a no-op outside `when` and passes the clean-ancilla witness under `when`.

**The Vector seam — the one kernel delta M7 needs.** `apply!`/`_act!` are typed
`NTuple{N,WireID}`; a `Perm` oracle has *data-dependent, unbounded* `n` (hundreds
of wires for arithmetic), so an `NTuple{N}` type parameter is actively wrong for
it (type explosion, per-`n` recompilation). **DECISION:** add exactly two
Vector-typed siblings, confined to the process-value path:
`apply!(ctx, v::ProcessValue, ws::AbstractVector{WireID})` and
`_act!(ctx, v::ProcessValue, ws::AbstractVector{WireID})`, each the byte-for-byte
logic of the tuple version over a `Vector`. Justification: `Perm.gates` is
already a `Vector` (not a tuple) for exactly this reason — the reversible corner
is the one corner whose width is runtime data. This is a core change (the 3+1
gate is why this proposal exists); it is *additive* (no existing signature moves)
and touches only the two entry points, not the emitter (`_emit!` already takes a
`Vector{Int}` of slots). For the small DJ/BV test circuits (`n ≈ 17`), the tuple
path would also work — the Vector seam is for the arithmetic oracles M9+ needs.

---

## 5. Loop-check wires: reject ALWAYS, and here is the physics

The probe (§2e-ii) proved the `loop_check_wires` class is **not** a clean
ancilla: the wire holds a convergence flag, `1` iff the input converged within
`max_loop_iterations`, `0` otherwise — an *input-dependent* value entangled with
`x`. The audit recommended rejecting it *under a control stack*. **I argue for a
stronger rule: reject it ALWAYS.**

The task asks whether tracing a dirty loop-check wire *outside* any control stack
is acceptable-silent (§3.9 no-backaction) or must be loud (fail-fast). Argue from
physics, not assertion:

§3.9's "forgotten uncompute is correct" licenses a *silent* trace **only** when
the traced wire is un-uncomputable garbage that the *algorithm* chose not to
clean — the trace then merely makes honest a decoherence the computation already
caused. The loop-check wire is a **different animal**: it is garbage the *user
cannot reach* (Bennett-internal), and it is `f`-correlated with `x`. For a
superposed `x` (DJ/BV feed a uniform superposition), tracing the loop-check wire
decoheres `x` along the converged/non-converged cut — destroying exactly the
interference the algorithm needs, and doing so **invisibly to any marginal test**
(wm28 class). This is not "the computation already did it"; it is the *bridge*
silently corrupting a superposition the user never asked to split.

Moreover, D14's binding contract is that the crossing artifact is a `Perm` that
is *a permutation on its full wire set with ancillas returning to `|0⟩`*. A
non-empty `loop_check_wires` means that contract is **violated** — the artifact
carries information out on a wire that is neither input, output, nor clean
scratch. It is not a clean reversible oracle at all.

**DECISION:** reject any circuit with non-empty `loop_check_wires` at
`oracle()` compile time (detected there, so the error is at the user's call
site), unconditionally:

```
oracle(f, x): f compiles to a data-dependent loop whose convergence flag cannot
be uncomputed — it is not a clean reversible oracle (its scratch does not return
to |0⟩; §3.9/D14). Increasing max_loop_iterations fixes overflow, not the garbage
flag. Rewrite f with a statically-bounded loop (a compile-time trip count is
fully unrolled with no guard, probe §2e), or restructure the computation.
```

Forward note (not M7): a loop oracle *can* be admitted if the bridge first
proves the convergence flag is a **constant** over the whole input domain — i.e.
every one of the `2^W` inputs converges within the bound — in which case the flag
is a disentangled `|1⟩` (a clean constant ancilla, uncomputable by `X`). That
whole-domain witness is the missing piece; it belongs to a later milestone with a
`denoted_permutation`-scale verifier (small `W`) or a Bennett-provided
all-converged certificate.

---

## 6. VM-needed, and the rest of the error taxonomy

**D14 is circuit-only.** If `f` requires the BennettVM (unbounded loops, dynamic
memory), Bennett either routes to `target=:reversible_vm` (a `VMProgram`, not a
`ReversibleCircuit`) or `reversible_compile` errors. Either way `oracle` raises a
loud error naming the limitation — never a silent fallback (D14):

```
oracle(f, x): f requires the BennettVM (unbounded loop / runtime-sized memory).
The VM lowering is not a fixed permutation and cannot cross into a Sturm process
value (D14, circuit-only bridge). Rewrite f with statically-bounded loops and
fixed-width state.
```

The bridge **never** passes `target=:reversible_vm`; it pins the circuit target.
Full taxonomy (all loud; each a named test §7):

| Trigger | When | Error |
|---|---|---|
| Bennett not loaded | `oracle()` | stub: "load Bennett.jl (`using Bennett`) to use `oracle`" (§8) |
| VM required | `oracle()` | D14 limitation (above) |
| `loop_check_wires` ≠ ∅ | `oracle()` | §5 (above) |
| `W > 64` | `oracle()` | "input width $W exceeds Bennett's 64-bit native ceiling" |
| `f` uncompilable | `oracle()` | wraps Bennett's error: "Bennett could not compile f: …" |
| `in ∩ out ≠ ∅` | `oracle()` | internal invariant (auto_self_reversing forced false) — assert |
| unsupported `x` type | `oracle()` | `MethodError` (no catch-all, P9) |
| target width ≠ `Wout` | `⊻=` | "oracle target width mismatch" |
| `b` aliases `x` | `⊻=` | "target aliases input register" (§4) |
| `x` consumed/dead | `⊻=` | inherited liveness error (qint `_here`) |
| MBU under control | — | **unrepresentable** (§7); no error path exists |

---

## 7. The MBU-exclusion test, and the verification plan

**MBU-exclusion (§3.4) is satisfied structurally, and the named test asserts the
structure.** Bennett has no measurement gate; every artifact is NOT/CNOT/Toffoli
⇒ every `OracleQuery.perm isa Perm` ⇒ phase-free unitary. Under `when`,
`ctrl(Perm) = Perm` — the op never routes through `_measure_wire!` or
`_assert_no_control`. There is nothing to exclude because nothing MBU-flavoured
can be constructed (D14: if Bennett ever grows MBU it must return a *distinct
type*, which the boundary rejects automatically). The named test asserts:
(a) `oracle(f,x).perm isa Perm` under every strategy kwarg; (b)
`when(c) do b ⊻= oracle(f,x) end` completes without a guardrail-1 throw;
(c) it Choi-equals the classically-controlled oracle.

**Named tests (`test/test_m7_oracle.jl`; PRD examples in `test_prd_examples.jl`):**

- **T1 — DJ §7.4 exact (the PRD example must RUN).** `deutsch_jozsa(const, Val(3))
  == true`, `deutsch_jozsa(balanced, Val(3)) == false`. One query. Constant ⇒
  outcome-0 amplitude `±1` (deterministic); balanced ⇒ `0` (never outcome 0).
- **T2 — BV §7.5 + the negative control.** `bernstein_vazirani(f_s, Val(3)) == s`
  for several `s` via per-wire `Bool(dual(x[i]))`. **Negative control:** the
  register-dual readout `Int(dual(x))` does *not* recover `s`; for `N=3, s=5` its
  distribution is `{1:0.073, 3:0.427, 5:0.427, 7:0.073}` — a statistical test
  (N ≥ 1000 shots, tolerance) proving register-dual ≠ per-wire-dual (D2, the
  spread/tied wm28-guard).
- **T3 — Perm-level correctness (NEVER marginals — wm28).** For small `f, W`:
  `denoted_permutation(q.perm)` realises `(x, t) ↦ (x, t ⊕ f(x))` for *all*
  `2^{W+Wout}` basis states, compared directly against classical `f`. The (★)
  ground truth at the permutation level.
- **T4 — MSB/LSB remap regression.** `f = x -> x + 1` (carry direction is
  asymmetric — the probe's decisive signature): assert `denoted_permutation`
  matches the classical increment under Sturm's MSB convention. A bit-reversal
  gives a *different* permutation ⇒ caught here, where marginals are blind.
- **T5 — input preserved + disjoint (P2/P3).** After `b ⊻= oracle(f,x)`,
  `Int(x)` returns the original `x`; assert `in_slots ∩ out_slots == ∅`.
- **T6 — oracle-under-`when` (the M5 IOU), Choi-level.** On a DM context,
  `Choi(when(c) do b ⊻= oracle(f,x) end) ≈ Choi(c-controlled f)`. Exercises
  `ctrl(Perm) = Perm`. Deterministic one-run Choi (§3.8), not shot averaging.
- **T7 — MBU-exclusion named test (§3.4).** As (a)/(b)/(c) above.
- **T8 — ancilla-cleanliness witness.** Outside `when`: after `⊻=`, `free_slots`
  is restored (no leaked wires). Under `when`: the clean-ancilla assert passes
  (P3). **Negative:** a data-dependent-loop `f` (compiled `optimize=false` so the
  guard is not folded away — probe §2e-ii) makes `oracle()` throw §5, always.
- **T9 — aliasing.** `b ⊻= oracle(f, x)` with `b` sharing a wire of `x` (e.g.
  `b = x[1]` widened) ⇒ loud error naming both registers.
- **T10 — width mismatch.** `b::QInt{Wout'}`, `Wout' ≠ q.Wout` ⇒ loud error.
- **T11 — VM-needed.** an unbounded-loop `f` ⇒ loud D14 error at `oracle()`.
- **T12 — Choi channel law.** `b ⊻= oracle(f,x)` as a channel on `(x, b)` Choi-
  equals the classical reversible map `(x,b) ↦ (x, b ⊕ f(x))` (beyond marginals).

Tests T3–T5, T9, T10 need *no* Bennett (build an `OracleQuery` by hand from a
known `Perm`) — the D9 law and control-awareness are tested in **core**; only
T1/T2/T6/T7/T8/T11 (the compile path) are gated on Bennett being loaded.

---

## 8. Dependency: a package extension (weakdep), not a hard dep

CLAUDE.md conv 4: "Core Sturm.jl depends only on Orkan; only `Test` in extras."
A hard `[deps] Bennett` violates that. **DECISION: a Julia 1.9+ package
extension.**

- `Project.toml`: `[weakdeps] Bennett = "…"`, `[extensions] SturmBennettExt =
  "Bennett"`, `[compat] Bennett = "0.5"`.
- **Core** (`src/bennett/bridge.jl`): the `OracleQuery` struct, the two
  `Base.xor` application methods, `_apply_oracle!`, `_assemble`, the disjointness
  and width/loop-check guards, `_bennett_arg_type`, resource-estimation on an
  `OracleQuery`, and a `oracle` **stub** that errors "load Bennett.jl…". These
  touch only `Perm`/`WireID` — pure Sturm.
- **Extension** (`ext/SturmBennettExt.jl`): the real
  `oracle(f, x::QInt{W}; signed, kw...)` — it calls `reversible_compile(f, T;
  bit_width=W, auto_self_reversing=false, target=:circuit, kw...)`, maps
  NOT/CNOT/Toffoli → `MCX`, applies the probe-§4 remap, and builds the
  `OracleQuery`. This is the *only* code that names a Bennett type.

Why idiomatic: (1) honors the minimal-deps rule — Sturm loads and its core
oracle *laws* test without Bennett present; (2) extensions are the 1.9+ answer
for optional heavy backends (superseding Requires.jl); (3) it mirrors Bennett's
own `_REVERSIBLE_VM_BACKEND` write-once hook — the *compiler frontend* is behind
the weakdep, the *lowering vehicle and application* are native. The surface
table's `oracle` row degrades to a loud "backend not loaded" error, never a
missing symbol.

**Caching — DECISION: none Sturm-side in M7.** Bennett already memoises at the
right granularity (`_extract_parsed_ir_cached` on `(f, types, optimize, mem)`;
`_compile_cache`). A Sturm-side cache keyed on `objectid(f)` is a footgun:
closures made fresh each call have distinct objectids (misses) and GC can reuse
an objectid for a *different* closure (silent wrong hit — a wm28-adjacent
correctness bug). The safe caching is **value-level**: bind `q = oracle(f, x)`
and reuse `q`. A `quantum(f)` pre-compiled wrapper (v0.1 sugar) keyed on
`(f, W, signed, sorted_kwargs)` is the right home for cross-call caching *if*
profiling demands it — deferred past M7.

---

## 9. Docstring citations (rule 4)

- `docs/physics/bennett_1973_logical_reversibility.md` — the compute–copy–
  uncompute construction: input preservation, clean ancilla, (★). Cited by
  `OracleQuery`, `_apply_oracle!`.
- `docs/physics/deutsch_jozsa_1992.md` — the one-query constant/balanced theorem;
  cited by the DJ example and T1.
- `docs/physics/bernstein_vazirani_1997.md` — per-wire dual readout of `s·x`;
  cited by the BV example, T2, and the D2 negative control.
- `docs/physics/delorme_control_as_constructor.md` — `ctrl(Perm) = Perm` closure;
  cited by the `when`-oracle path (§1) and T6.

All four exist in `docs/physics/` (bennett/deutsch_jozsa/bernstein_vazirani/
delorme). The runtests boot lint (CLAUDE.md #4) will resolve each cited path.

---

## 10. Open risks and mitigations

1. **Silent bit-reversal (wm28 class) — the top risk.** Mitigation: the remap is
   in *one* function (`SturmBennettExt._circuit_to_query`), it is the probe-§4
   formula (empirically grounded), and T3/T4 verify at the **permutation** level
   on an *asymmetric* `f` (increment) — never on marginals.
2. **`NTuple{N}` width explosion** for arithmetic oracles. Mitigation: the two
   Vector-typed `apply!`/`_act!` siblings (§4) — the one kernel delta, additive,
   confined to the process-value path; justified because `Perm` is the one value
   with runtime-data width (`Perm.gates` is already a `Vector`).
3. **`auto_self_reversing` / input-overlap.** Mitigation: force `false` + assert
   `in ∩ out = ∅`. Cost: a slightly larger circuit for in-place-safe `f`.
   Relaxable later by admitting overlap only when the target *is* the input.
4. **loop-check garbage.** Mitigation: reject always (§5). Risk: over-restrictive
   for future loop oracles — forward path (all-converged witness) documented.
5. **Bennett version/API drift.** Mitigation: `[compat] Bennett = "0.5"`; re-run
   Bennett's suite on the project's 1.12.x as a hardening gate (audit Q5); the
   field-name introspection (probe §5) is stable across the audited HEAD.
6. **Multi-register / QBool arg.** Mitigation: designed-for (tuple of input
   registers, probe-§4 per-element offset) but only single-register `QInt` is
   shipped and tested in M7. QBool is a thin `Bool`-arg method, low risk.
7. **DM-context oracle.** `Perm` applies identically on pure and mixed (§4.3
   table: "replay stored reversible circuit"); T6 needs it (Choi). No extra work
   — Orkan dispatches PURE/MIXED internally (abstract.jl header).

---

## 11. Summary of decisions

1. `oracle(f, x)` denotes `(P_f : Perm, role map)` — a `Perm`-citizen, (★).
2. `b ⊻= oracle(f, x)` is the `a ⊻= b` action family with `ctrl(X) → Perm` and
   wire → block; the kickback law is the CNOT law lifted (D9). Not an 8th
   construct — `oracle` (7) produces, `⊻=` (3) applies.
3. `OracleQuery` struct: `Perm` + slot role maps + bound `xwires` + `W/Wout`.
   Compile **eagerly** at `oracle()`; `public`, not exported.
4. `x::QInt{W}`/`QBool`; `bit_width=W` genuine narrowing; default `signed=false`;
   `auto_self_reversing=false` forced; the MSB/LSB remap in **one** function.
5. Control-awareness, aliasing, and scope are **inherited** from `_act!` /
   `apply!` / `region()`. `ctrl(Perm)=Perm` discharges the M5 `when`-oracle IOU
   with zero new ctrl code. One kernel delta: Vector-typed `apply!`/`_act!`.
6. Loop-check circuits rejected **always** (physics: un-uncomputable `x`-
   correlated garbage, wm28 class; D14 contract violation). VM rejected (D14).
7. Package **extension** (weakdep), not a hard dep; no Sturm-side cache in M7.
8. MBU-exclusion is structural (Bennett has no measurement ⇒ every query is a
   `Perm`); the named test asserts it. Twelve named tests, permutation/Choi-level.
