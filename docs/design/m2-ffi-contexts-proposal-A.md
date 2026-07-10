# M2 Design — Proposal A (SEMANTICS FIRST)

**Milestone:** M2 — Orkan FFI + contexts + regions (bead `Sturm.jl-dc6i`).
**Proposer:** A. Lens: the Stinespring reading of scope, consumed-set
linearity, trace-lowering correctness, and the *phase-exactness* of `Ad`
and the controlled decomposition — every equation derived on paper here,
grounded in the pinned kernel convention
(`docs/physics/wharton_koch_quaternion_bloch.md`) and the audited Orkan C
API (`docs/design/orkan-abi-audit-m2.md`).

**One-paragraph thesis.** The U2 = (unit quaternion `q`, phase `φ`) split
is not a storage trick — it is *exactly* what makes `Ad` clean. On the
uncontrolled path, `Ad` must forget `φ` (ker Ad = U(1), §4.3) and reproduce
only the **SU(2)** part `S = U(q)`; because `S` is det-1, its ZYZ Euler
decomposition is **exact with no residual phase**, so "drop `φ`" is
literally "don't emit a `p(φ)` call" and nothing else leaks. On the
controlled path, `ctrl` promotes `φ` to an observable relative phase
(Tang–Wright Thm 1.1), and the *entire* subtlety collapses to a **single
`p(φ)` gate on the control (or on the AND-ancilla)** — one line, at one
choke point. Everything below is the careful spelling-out of those two
sentences plus the plumbing (FFI guards, contexts, regions) that carries
them.

---

## 0. Scope, files, and one deviation from the plan baseline

Plan M2 file list: `src/orkan/ffi.jl`, `src/orkan/state.jl`;
`src/context/abstract.jl`, `eager.jl`, `density.jl` (minimal),
`regions.jl`.

**Deviation D-A1 (add one file): `src/orkan/ad.jl`.** The plan folds "Ad
application" into the FFI bullet, but the application kernel — ZYZ
extraction, the controlled decomposition, `sqrt_u2`, Perm replay — is ~250
lines of load-bearing, physics-derived math that is *not* raw ccall
plumbing and must be independently testable and lint-visible as a
controlled-lowering site. Giving it its own file keeps `ffi.jl` a thin,
audit-mirroring shim and makes the choke-point grep
(`orkan_cx|controlled` only under `src/kernel/` or `src/orkan/`) land on a
file whose whole job is that. `ad.jl` lives under `src/orkan/` so the lint
is satisfied. (Rationale for *not* putting it in `src/kernel/`: it emits
against the **context primitive interface**, so it is backend-adjacent, and
M8's TracingContext reuses the same emitter — see §2.6.)

**Deviation D-A2 (minimal `WireID` lands in M2, not M3).** M2's consumed
set, owned set, and §8.4 aliasing check all need a stable wire *identity*
now, but the plan assigns `src/types/wire.jl` to M3. Resolution: M2
introduces a *minimal* immutable `WireID` (an integer id + a back-reference
to the owning context) in `src/context/abstract.jl`; M3's `src/types/wire.jl`
wraps it with the typed handle and `x[i]` slice machinery. No rework — M3
adds a layer, it does not change the identity. Flagged for the reviewer.

Everything else follows the plan.

---

## 1. FFI layer (`src/orkan/ffi.jl`, `src/orkan/state.jl`)

This is a near-verbatim re-port of v0.1's `ffi.jl` — the audit certifies
**24/24 ccall shapes VERIFIED-STILL-CURRENT, 0 drifted**
(`orkan-abi-audit-m2.md` §1, §4). We keep the shapes and **re-derive the
guards from the fatal-error model**, not from trust.

### 1.1 Library discovery and load (`__init__`, precompile-safe)

The audit (§9) pins the search order; v0.1's is correct, with one
precompile-safety fix.

```
1. ENV["LIBORKAN_PATH"]                 (explicit override)
2. joinpath(@__DIR__,"..","..","..","orkan",
            "cmake-build-release","src","liborkan.so")   (sibling build)
3. "liborkan"                            (system loader / RPATH)
```

- **Resolution happens in `__init__`, not at top level.** v0.1 computed
  `const _LIBORKAN_PATH` in a top-level `let`, which runs during
  *precompilation* and bakes a possibly-wrong path into the `.ji`. M2
  resolves inside `__init__` and stores it: `const _LIBORKAN = Ref{String}()`.
  All ccalls interpolate the runtime string: `@ccall $(_LIBORKAN[]).state_init(...)`.
  (Julia accepts a runtime library-name expression in the ccall library
  slot; nothing dlopens at top level, so precompile stays pure.)
- **`_try_dlopen` rethrows `InterruptException`** during probing (v0.1 bead
  `Sturm.jl-011f`: a bare `catch` swallowed Ctrl-C mid-load). Any other
  failure → probe returns false and we fall through.
- **Fail loud with build instructions** if none resolve (CLAUDE.md #1):
  `error("Cannot find liborkan.so. Set LIBORKAN_PATH or build: cd ../orkan && cmake --preset release && cmake --build cmake-build-release")`.

### 1.2 OpenMP ceiling in `__init__`

Audit §7: no thread-config symbol exists; threading is `OMP_NUM_THREADS`
only, and it **must** be set in `__init__` (load time, not precompile).
Project memory pins the device ceiling at **16**. v0.1 capped at `CPU÷4`
to avoid oversubscribing against Julia's own threads. M2 combines both:

```julia
if !haskey(ENV, "OMP_NUM_THREADS")
    ENV["OMP_NUM_THREADS"] = string(clamp(Sys.CPU_THREADS ÷ 4, 1, 16))
end
```

Respect a user-set value (don't clobber). OpenMP only engages above
`OMP_THRESHOLD` (n ≥ 9), so law tests run serial regardless; and because
OpenMP reduction order perturbs floats run-to-run, **all law tests compare
with `≈`, never bit-exact amplitudes** (audit §7; PRD §4.1).

### 1.3 The raw structs (ABI-exact, from the audit)

Re-port v0.1's `OrkanStateRaw` (24 B: `Cint type` + 4 pad + `Ptr data` +
`UInt8 qubits` + 7 pad), `OrkanKrausRaw` (24 B, immutable — Julia-owned
buffer, `GC.@preserve` at the call), `OrkanSuperopRaw` (16 B, mutable so a
free can run; **but see §4.4 — we drive frees from the region, not a
finalizer**). Enum: `ORKAN_PURE=0, ORKAN_MIXED_PACKED=1, ORKAN_MIXED_TILED=2`.

### 1.4 Every wrapped ccall validates **Julia-side, BEFORE the call**

This is the sharpest edge in the whole milestone. Audit §5, §8.6: Orkan's
`GATE_VALIDATE`/`CHANNEL_VALIDATE` macros call **`exit(EXIT_FAILURE)`** on a
bad index or NULL state — a *bad qubit kills the whole Julia process* with
no recoverable signal. `qs_error_t` exists but is **decorative** (nothing
returns it). Therefore every wrapper re-checks v0.1's guards verbatim:

- `_check_qubit(state, q, name)`: `state.data != C_NULL` **and**
  `0 ≤ q < state.qubits`.
- `_check_distinct(a, b, name)` for 2q; `_check_distinct3(a,b,c,name)` for
  ccx.
- `channel_1q`: additionally assert `state.type != PURE` (Orkan `exit()`s
  on PURE — audit §1.4/§8.4) and `sop.n_qubits == 1`. **v0.1 bead
  `Sturm.jl-1oy` shipped this wrapper as the sole missing guard — a
  process-kill regression. It is a named M2 regression test (§5.10).**
- `state_init`/`state_plus`: OOM is silent-ish — Orkan prints to stderr and
  leaves `data == C_NULL`. Check `state.data == C_NULL` after and `error()`.

**Wrapper table (all re-ported, audit §4):** `state_init/free/plus/len/get/set`,
`state_cp` (deep copy by value, caller frees via `state_free`),
`x,y,z,h,s,sdg,t,tdg,hy` (1q), `rx,ry,rz,p` (1q param), `cx,cy,cz` (2q),
`swap_gate` (**C symbol is `swap_gate`, not `swap`**), `ccx` (3q),
`kraus_to_superop`, `channel_1q`. Superop free = **libc `free`** (there is
no `superop_free` in Orkan; `kraus_to_superop` calloc's `out.data`).

**DO NOT bind `single_from_mat`/`two_from_mat`** (audit §0.4, §8.5): they
are header-private, **tiled-DM-only**, and silently coupled to the
compiled `LOG_TILE_DIM` (=5 in the release `.so`) — a symbol that can
change or vanish with *no header diff to detect it*, the worst face of
"ABI drift." M2 lowers **everything** (pure and DM) through the public
named-gate + ZYZ vocabulary. The 1-call DM matrix path is a future
optimization gated on Orkan promoting the symbol into `include/` with a
PURE/PACKED dispatcher + a linked-`LOG_TILE_DIM` runtime assertion.

### 1.5 Bulk amplitude access (`state.jl`)

Audit §6: sampling/probabilities are Julia-side and cost `O(2^n)`. v0.1's
per-element `state_get` is one ccall per amplitude (bead `Sturm.jl-5z3r`
flagged 16 MB/call at n=20). For PURE storage the data is a flat `2^n`
vector: expose `amplitudes(ctx) = unsafe_wrap(Array, state.data, state_len)`
under `GC.@preserve`, and do probability/marginal scans over the wrapped
array — one bulk view, zero per-element ccalls. MIXED storage is
triangular; there we use the Hermitian-aware `state_get` accessor (or the
row scan `state_get(i,i)` for diagonals). This view is also how the M3 Choi
harness reads ρ.

### 1.6 The pinned wire↔Orkan-index map (load-bearing convention)

The kernel fixes **wire 1 = MSB**: for an `n`-wire block and basis index
`b`, wire `c` holds bit `(b >> (n − c)) & 1` (perm.jl header; Ctrl controls
are leading wires; Tensor factor 1 is leftmost). Orkan gate indices are
0-based and (like every flat-statevector sim) qubit `j` addresses bit `j`
of the basis index. To make `denoted_matrix` (kron, factor 1 = MSB) agree
with Orkan's indexing, the context pins:

> **kernel wire `c` (1-based, MSB=1) ⟷ Orkan qubit index `q = W − c`**
> for a `W`-wire register.

Then wire `c` addresses bit `W − c` of the basis index, exactly matching
the kernel's `(b >> (n − c)) & 1`. This convention is **verified, not
assumed**: the §5.2 round-trip test compares Orkan output against
`denoted_matrix`, and any bit-order slip localizes there to exactly this
one line. Aliasing/index checks (§8.4) use `WireID`s and fire *before* the
ffi shim's raw-index checks (CLAUDE.md Orkan-FFI section).

---

## 2. `Ad` — the application kernel (`src/orkan/ad.jl`, §4.3)

`Ad : U(d) → CPTP`, `Ad_g(ρ) = g ρ g†`, `ker(Ad) = U(1)`. Application is
where **the phase quotient is crossed exactly once** (§4.3; pinned-convention
distillation, "Phase discipline"). One generic entry, dispatching on
(value kind), threading the context explicitly (never re-reading the
ScopedValue in the loop — §4.7 / CLAUDE.md convention 6):

```julia
apply!(ctx, v::ProcessValue, wires::NTuple{N,WireID})
```

`apply!` emits against the **context primitive interface** (§3.1): the
named 1q gates, `rz/ry/rz/p`, `cx/cy/cz/ccx`. The decomposition math is
context-independent; only the emitter differs (Eager/DM ccall, Tracing DAG
node). This is why the choke point stays single and the same code is
phase-correct on every backend.

### 2.1 `U2` on the uncontrolled path — ZYZ extraction (THE chart singularity site)

Target: reproduce `denoted(u) = e^{iφ} S`, `S = U(q)`, but **drop `φ`**
(ker Ad). Because `S ∈ SU(2)`, decompose `S = Rz(a)·Ry(b)·Rz(c)`
(right-to-left: `Rz(c)` first) — **exact, det-1 in, det-1 out, no residual
phase**. This exactness is the entire payoff of the quaternion+phase split:
the *only* thing dropped is the fifth float; the SU(2) part decomposes on
the nose.

**Derivation (pinned convention).** With
`S = [[w−iz, −y−ix],[y−ix, w+iz]]` (wharton_koch md, "Quaternion → SU(2)"),
and Orkan's `rz(θ)=diag(e^{−iθ/2},e^{iθ/2})`, `ry(θ)=[[c,−s],[s,c]](θ/2)`
(both matching kernel `Rz`/`Ry` denotations — constants.jl), the product is

```
Rz(a)Ry(b)Rz(c) =
 [[ cos(b/2) e^{−i(a+c)/2} ,  −sin(b/2) e^{−i(a−c)/2} ],
  [ sin(b/2) e^{ i(a−c)/2} ,   cos(b/2) e^{ i(a+c)/2} ]]
```

Matching entries `s00 = w−iz`, `s10 = y−ix`:

```
b = 2·atan2( √(x²+y²), √(w²+z²) )          ∈ [0, π]
a = atan2(−x, y) − atan2(−z, w)            (= arg s10 − arg s00)
c = −atan2(−x, y) − atan2(−z, w)           (= −arg s10 − arg s00)
```

(from `(a+c)/2 = −arg s00`, `(a−c)/2 = arg s10`). Emission on the
uncontrolled path, in application order:

```
rz(ctx, wire, c);  ry(ctx, wire, b);  rz(ctx, wire, a)     # φ dropped: NO p() call
```

**The θ≈0/π singular branches (audit §2: unavoidable on the primary pure
path).** When `b ≈ 0` (i.e. `x²+y² < ε²`), `s10 ≈ 0`, so `atan2(−x,y)` is
`atan2(0,0)` — ill-conditioned; only the sum `a+c` is determined (gimbal
lock, `S` is diagonal). When `b ≈ π` (`w²+z² < ε²`), `s00 ≈ 0` and only the
difference `a−c` is determined (`S` is anti-diagonal). The fold, written
**once, here, and nowhere else** (§4.1, D7):

- `b ≈ 0`: `S = diag(w−iz, w+iz) = Rz(θ)` with `θ = 2·atan2(z, w)`. Set
  `b←0, c←0, a←2·atan2(z, w)` — emits a **single well-defined `rz(a)`**.
- `b ≈ π`: `S = [[0, −y−ix],[y−ix, 0]]`. Set `b←π, c←0,
  a←2·atan2(−x, y)` — emits `rz(a); ry(π)`.

Threshold `ε` chosen from the same numerics budget as `U2_ATOL` (drift
`< 2^-40`; pick `ε ≈ 1e-7` on the *squared* magnitude so the discarded
angle's contribution is `< U2_ATOL`). The branch is tested at
`θ ∈ {0, π, ±ε}` and on random near-poles (§5.3); the round-trip against
`denoted_matrix` is the correctness witness (a NaN or a wrong angle shows
up as a matrix mismatch, never silently).

**Native fast recognition (phase-safe).** Before ZYZ, if `u ≈ X` (resp. Y,
Z) under the kernel's double-cover `≈`, emit `x` (resp. `y`, `z`) directly.
`≈` is phase-aware, so `u ≈ X` means `denoted(u) = σx` **exactly** —
recognizing it drops nothing. `H`, `S`, `T` similarly map to the native
`h/s/t` calls. (Optimization only; ZYZ is always correct.)

### 2.2 `Ctrl{U2}`, k=1 — the ABC decomposition and where `φ` lands

Target: `denoted(Ctrl(1,u)) = diag(I₂, e^{iφ}S)` (ctrl.jl `denoted_matrix`).
Orkan has **no** controlled-U2 (audit §3), so we decompose. Standard ABC
(Nielsen–Chuang §4.3; distillation required — see §6): any SU(2) `S`
factors as `S = A·X·B·X·C` with `A·B·C = I`, using the ZYZ angles of §2.1:

```
A = Rz(a)·Ry(b/2)
B = Ry(−b/2)·Rz(−(a+c)/2)
C = Rz((c−a)/2)
```

**On-paper verification** (X-conjugation `X·Ry(θ)·X = Ry(−θ)`,
`X·Rz(θ)·X = Rz(−θ)`):

```
A·B·C = Rz(a)Ry(b/2)·Ry(−b/2)Rz(−(a+c)/2)·Rz((c−a)/2) = Rz(a)Rz(−a) = I  ✓
A·X·B·X·C = Rz(a)Ry(b/2)·[XRy(−b/2)X][XRz(−(a+c)/2)X]·Rz((c−a)/2)
          = Rz(a)Ry(b/2)·Ry(b/2)Rz((a+c)/2)·Rz((c−a)/2)
          = Rz(a)·Ry(b)·Rz(c) = S  ✓
```

Emission for `Ctrl(1,u)` on `(control, target)`:

```
zyz_emit(ctx, C, target)          # C = Rz((c−a)/2)
cx(ctx, control, target)          # the X, when control = 1
zyz_emit(ctx, B, target)
cx(ctx, control, target)
zyz_emit(ctx, A, target)
p(ctx, control, u.φ)              # ← THE line: inner φ becomes the controlled phase
```

**Phase-exactness — the whole point.** When `control = 0`: target sees
`A·C = Rz(a)Ry(b/2)Rz((c−a)/2)`... — no: with no X's it is `A·(I)·(I)·C`?
No. With `control = 0` the two `cx`'s are identity, so target sees
`A·B·C = I` (that is *why* `ABC = I` is required) and `p` does nothing →
the `|0⟩·` block is `I₂`. ✓ When `control = 1`: target sees `A·X·B·X·C = S`
and `p(φ)` multiplies the block by `e^{iφ}` → the `|1⟩·` block is
`e^{iφ}S`. ✓ Exactly `diag(I, e^{iφ}S)`.

**Drop `φ` here and you ship the Cirq/Qiskit/pytket bug.** Omitting `p(φ)`
gives `diag(I, S)` instead of `diag(I, e^{iφ}S)` — off by
`diag(1,1,e^{iφ},e^{iφ}) = p(φ)` on the control, a *physically observable*
`Z`-type error (Tang–Wright Thm 1.1; delorme §5; ctrl.jl docstring). The
canonical instance: `u = gphase(α)` ⇒ `a=b=c=0`, `A=B=C=I`, the ladder is
two cancelling `cx`'s, and the emission is **just `p(α)` on control** =
`diag(1,1,e^{iα},e^{iα})` = `denoted(Ctrl(1,gphase(α)))`. ✓ And `ctrl(NEG_I)`
(`φ=π`) ⇒ `p(π)` on control = `diag(1,1,−1,−1) = CZ`-grade ≠ `ctrl(I2)` —
the Tang–Wright `I`-vs-`−I` separating example, reproduced exactly (§5.4).

**Why this ABC is legitimate here but was heresy in v0.1.** In v0.1 the
rotation/ABC vocabulary was the **surface** language (users wrote
`q.θ += δ`) — condemned by PRD §1/§5 (no rotation angles on the surface). 
Here it is the **kernel's internal lowering of a definite `Ctrl{U2}` process
value at the single `ctrl` choke point** — an IR compilation artifact,
invisible to surface code, and *phase-exact because it carries `φ`*. P5:
"the kernel may hold definite unitaries; an IR is not a user language." The
difference is not the math, it is *who writes it and whether phase survives*.

### 2.3 `Ctrl{U2}`, k=2 — Toffoli-grade

- **Native:** if `u ≈ X`, emit `ccx(c1, c2, target)` (phase-exact:
  `denoted(Ctrl(2,X)) = diag(I₆, σx)` = Toffoli). No native ccy/ccz, so
  Y/Z fall through.
- **General C²(U2):** two phase-exact strategies, both cross-checked against
  `denoted_matrix(Ctrl(2,u))` (§5.4):

  1. **Ancilla reduction (PRIMARY).** Compute the AND of the two controls
     into a fresh ancilla with one `ccx(c1,c2,anc)` (anc starts |0⟩ →
     becomes `|c1∧c2⟩`), apply **`Ctrl(1,u)` controlled on `anc`** (§2.2 —
     ABC + `p(φ)` on `anc`), then uncompute with `ccx(c1,c2,anc)`. The
     phase `p(φ)` now fires **iff both controls were 1** — correct by
     construction, uniformly for any `k`. Ancilla policy: allocated from
     the context (fresh |0⟩), uncomputed to |0⟩, freed clean — the §3.9
     clean-ancilla witness holds (composite is unitary on survivors).
  2. **Ancilla-free (Barenco).** `C²(M) = C\!-\!V_{(c2,t)}·CX_{(c1,c2)}·
     C\!-\!V†_{(c2,t)}·CX_{(c1,c2)}·C\!-\!V_{(c1,t)}` with `V² = M` as a
     **U(2)** element. `V = sqrt_u2(u)` (§2.5) carries `φ/2`, so each `C-V`
     is a phase-exact k=1 controlled op (§2.2) and the product reproduces
     `M` with its phase in the all-ones block. Fallback when ancilla
     allocation is undesirable (adds gates, `O(1)` here; wins on wires).

### 2.4 `Ctrl{U2}`, k≥3 — MCU, and the ancilla policy

- **Native:** `u ≈ X` with k=2 → `ccx`; k≥3 X → the MCX ladder below.
- **General MCU (PRIMARY = ancilla ladder).** Compute the AND of all `k`
  controls into a single ancilla via a **Toffoli ladder**: `k−1` fresh
  ancillas `a₁..a_{k−1}`, `ccx(c1,c2,a1); ccx(c3,a1,a2); …` leaving
  `a_{k−1} = c1∧…∧ck`; apply `Ctrl(1,u)` on `a_{k−1}` (§2.2, `p(φ)` on
  `a_{k−1}` — fires iff all controls 1); then **uncompute the ladder in
  reverse** so every ancilla returns to |0⟩. Cost `O(k)` Toffolis + `k−1`
  clean ancillas.
- **Ancilla-free fallback (Barenco Lemma 7.5 recursion):** `O(k²)` gates,
  no extra wires; selected when the context signals a wire budget.
- **Ancilla policy (semantics).** Ancillas are context-allocated
  (fresh = |e_G⟩ = |0⟩), used, **uncomputed**, and freed inside the same
  region. Because they exit in |0⟩ under the unitarity witness, their
  region-exit "trace" is not a trace at all (composite unitary on
  survivors — §3.9 "Inside `when`, the boundary is checked"). This is the
  clean-ancilla pattern; a *forgotten* uncompute would trace a superposed
  ancilla and mix survivors — correct-but-mixed by §3.9, and flagged by the
  M6 strict-mode detector (§4.5).

### 2.5 `sqrt_u2` — the U(2) square root (kernel helper for Barenco)

`V = sqrt_u2(u)` with `V ∘ V ≈ u`. Split: `φ_V = φ/2`; quaternion
principal square root of the SU(2) part. For `q = (w,x,y,z)` (a rotation by
`Ω` about `n̂`, `w = cos(Ω/2)`), the half-rotation is `√q = (q + 1_quat)`
normalized, i.e. `√q = (w+1, x, y, z)/‖(w+1,x,y,z)‖` for `w ≠ −1`; at
`w = −1` (`Ω = 2π`, `S = −I`) the axis is free — pick `√(−I) = i` (any pure
unit quaternion) with `φ_V = φ/2`, since `Ctrl` cross-checks against
`denoted_matrix` regardless of the branch. Verified by `V∘V ≈ u` under the
kernel `≈` (§5, and it *reuses* the M1 Hamilton `∘`, no new arithmetic).

### 2.6 `Ctrl{Tensor}`, `Ctrl{Seq}`, `Ctrl{Perm}`/`Perm` — structural recursion

- **`Perm` replay** (the clean case, audit §3): `Ctrl` closes on `Perm`
  (`ctrl(::Perm)::Perm`, perm.jl), so **`Ctrl{Perm}` is unreachable from
  `ctrl`** — only `Perm` replay is needed. Replay each `MCX(controls,
  target)` in order: 0 controls → `x`; 1 → `cx`; 2 → `ccx`; **≥3 → the
  ancilla Toffoli ladder of §2.4** (compute AND of controls → single `cx`
  on the ancilla → uncompute). Phase-free by construction (Perm carries no
  `φ`). Wire indices are remapped through the pinned map (§1.6).
- **`Ctrl{Seq}(k, Seq(a,b))`** — control is a **homomorphism over `∘`**
  (delorme Def 1; ctrl.jl): `C_k(matrix(a)·matrix(b)) = C_k(a)·C_k(b)`
  (block-diagonal respects products). Lower by recursion: `apply!` the
  k-controlled `b` first, then the k-controlled `a`, sharing the `k`
  control wires. (Implementation: `apply!(ctx, _rewrap(k,b), wires);
  apply!(ctx, _rewrap(k,a), wires)`, where `_rewrap(k,v)` reconstructs the
  controlled value via the private `_ctrl` — inside `ad.jl`, which is a
  sanctioned choke-point file.)
- **`Ctrl{Tensor}(k, Tensor(a,b))`** — control does **not** distribute over
  `⊗` (delorme Caveats; ctrl.jl): it is one shared control gating *both*
  factors, `C_k(A⊗B) = (C_k A)·(C_k B)` with **shared controls, disjoint
  targets** (they commute). Lower by recursion on `a` over `(controls ⧺
  a-wires)` then `b` over `(controls ⧺ b-wires)`.

Recursion bottoms out at `Ctrl{U2}` (§2.2–2.4), the native gates, and
`Perm` replay. **No `apply!(::ProcessValue)` catch-all** — mirroring
ctrl.jl's totality-by-exhaustion: an unhandled kind is a `MethodError`, not
a silent wrong emission (a future non-unitary DAG node must *not* be
silently controlled — P4). M8 adds exactly `apply!(::UnitaryDAG)`.

---

## 3. Context layer (`abstract.jl`, `eager.jl`, `density.jl`)

### 3.1 `AbstractContext` — the required interface

The key simplification, from the audit: **Orkan's gate functions dispatch
internally on state type** (PURE/PACKED/TILED — `gate.c`, audit §1.3), so
the *same ccall sequence* implements `Ad` on a pure state and as a
conjugation `UρU†` on a density matrix. Therefore Eager and DM share the
**entire** `Ad` emitter and the primitive interface; they differ only in
(a) which `state_type` they allocate, (b) how they **trace**, and (c)
channel support. A concrete context MUST provide:

1. **Storage / allocation.** `alloc_wire!(ctx)::WireID` (fresh, canonical
   |0⟩), `orkan_index(ctx, w::WireID)::Int` (via §1.6 map), `nwires(ctx)`.
2. **Primitive gate vocabulary** (what `apply!` emits to): the generic
   functions `_x!/_y!/_z!/_h!/_s!/_t!`, `_rz!/_ry!/_rx!/_p!`,
   `_cx!/_cy!/_cz!/_ccx!/_swap!` — each taking `(ctx, wires...)`, mapping
   `WireID → Orkan index`, and calling the guarded ffi wrapper. The
   abstract fallback `error`s (CLAUDE.md #1) so a context missing one fails
   loud, not silent.
3. **Trace / free.** `trace!(ctx, w::WireID)` — the §3.9 partial trace,
   **silent, no backaction** (the principled exception, CLAUDE.md #1). Eager
   lowering = measure-and-discard; DM = exact ptrace.
4. **Linearity bookkeeping.** the single-sourced `consumed::Set{WireID}`,
   `consume!(ctx, w)`, `is_consumed(ctx, w)`; the region owned-set stack
   (§4).
5. **RNG.** `ctx.rng::AbstractRNG` — reproducibility is Julia-side (audit
   §6: Orkan has no RNG and cannot be seeded). The measure-and-discard
   trace and (M3) measurement casts draw from it.

`current_context()` reads the `ScopedValue` **once** at a surface entry;
`apply!` and the emitter thread `ctx` explicitly (never re-read in the hot
loop — CLAUDE.md convention 6; ScopedValue access allocates).

### 3.2 `EagerContext` (pure statevector — the primary path)

Holds one `OrkanStateRaw` of `state.type = PURE`, a `WireID→index` table, a
free list, the consumed set, the region stack, and an RNG.

- **Allocation grows the statevector by embedding |0⟩.** Orkan
  `state_init(n)` allocates `2^n`. `alloc_wire!` appends a new LSB wire:
  allocate a state of `n+1` qubits and copy `new[2b] = old[b]`,
  `new[2b+1] = 0` (index-preserving embedding of `ψ ↦ ψ⊗|0⟩` in the pinned
  bit order) via the bulk `unsafe_wrap` view (§1.5); free the old state.
  (M2 acceptable cost; a pre-sized-capacity optimization is a later note.)
- **`trace!` = measure-and-discard** (§3.9 sanctioned pure lowering): draw
  the traced wire's outcome from `ctx.rng` over the marginal (bulk scan),
  collapse to that branch, renormalize, and shrink the state by dropping
  the wire. **Exact for all downstream statistics by no-signaling**, a
  valid per-shot unraveling. *This advances the RNG* — hence the
  seeded-tests-never-assert-trace-placement policy (§5.8).
- **`reset-on-recycle`.** A recycled Orkan index must re-enter as |0⟩. The
  measure-and-discard already yields a definite branch; the allocator
  asserts the recycled slot is |0⟩ and, if the collapse landed |1⟩ before
  discard, that is fine (the wire is *removed*), but a slot returned to the
  free list is reset to |0⟩ so the "fresh = |e_G⟩" invariant holds. Note
  §3.9: `ptrace! ≠ reset` — reset is measure-and-**flip** (a physical
  channel); conflating them is a physics bug, so recycle does the flip
  explicitly.

### 3.3 `DensityMatrixContext` (minimal — enough for M3's Choi harness)

Holds one `OrkanStateRaw` of `state.type = MIXED_TILED` (or PACKED). "DM
executes channels" (§4.3 table; M3 Choi): it stores ρ, so a channel runs
deterministically in one pass.

- **Unitary `Ad` = the identical ccall sequence** (Orkan applies `UρU†`
  internally). No code duplication — same `apply!`.
- **`trace!` = exact partial trace, Julia-side.** Audit §6/§8.4: Orkan has
  no `ptrace` and `channel_1q` is 1-local only. So DM `ptrace!` reads ρ
  (via the accessor / bulk view) and sums over the traced index into a
  reduced ρ — exact, no collapse, no RNG. This is the honest §3.9
  denotation ("Density contexts trace exactly").
- **Channels (scaffold for M3/M11).** `apply_channel!(dm, kraus, w)` =
  `kraus_to_superop` (Julia buffer, `GC.@preserve`) → guarded `channel_1q`
  (assert non-PURE, `n_qubits==1`) → libc-free the superop. **1-local
  only** in M2 (audit §8.4); multi-qubit channels deferred to M11's
  Stinespring path. Enough for M3 to build `choi(f, nin)` on the DM state
  (prepare the maximally entangled input via `state_plus`/Bell prep, run
  `f`, read ρ — 2W-wire cost, 15-wire cap, plan §6).

### 3.4 The single-sourced consumed set (§4.5, §8.5)

One `Set{WireID}` on the context is the **sole** authority on consumption
(§4.5: "single-sourced on the context's consumed set"; v0.1's per-object
flag desync — QInt views manufacturing fresh flags, §8.5 — is thereby
deleted). Consumption happens at **exactly two places** (§4.5): qc casts
(M3 `Bool(q)`) and `ptrace!`. Region exit is the *derived* form of the
second (§3.9), not a third mechanism. Unitary `apply!` **never** consumes —
a handle is stable, application is a channel from the register to itself.
M2 lands the set + `consume!`/`is_consumed`; M3's casts are its first
customers, but `ptrace!` and region-exit trace use it now.

---

## 4. Regions (`regions.jl`, §3.9, D10)

**The semantics (Stinespring reading).** A function is a channel *on its
signature* (P1); locals it allocates and neither consumes nor returns are
the **Stinespring environment**, and function scope is the **dilation
boundary** — so they must be traced at region exit (§3.9). This is forced,
not chosen: without the trace the body would denote a channel on the wrong
(dilated) space. The trace has **no backaction** (no-signaling: for every
surviving observable, tracing a wire and never touching it again are
identical), so it is **silent by design** — the one principled exception to
FAIL-LOUD (CLAUDE.md #1; §3.9 "implicit ops *without* backaction are
silent"). Forgotten uncompute is therefore *correct behaviour*, not an
error (the survivors were already mixed by the entangling compute; the
trace only makes the bookkeeping honest).

### 4.1 `@context` on `Base.ScopedValues.with`

```julia
const CURRENT_CONTEXT = ScopedValue{AbstractContext}()

macro context(ctx, body)
  quote
    local c = $(esc(ctx))
    with(CURRENT_CONTEXT => c) do            # `with` IS try/finally — the
      _enter_region!(c)                      #   deterministic exit a region needs
      try
        $(esc(body))
      finally
        _exit_region!(c)                     # trace owned-and-unconsumed
      end
    end
  end
end
current_context() = @something(ScopedValues.get(CURRENT_CONTEXT),
  error("No active Sturm context — use @context or region()."))
```

- **Why `ScopedValue`, not `task_local_storage`** (CLAUDE.md convention 6;
  §3.9): ScopedValue bindings **inherit into `Threads.@spawn`/`@async`
  children**; TLS does **not** (a silent-missing-context bug class, deleted
  outright — v0.1 used TLS, quarry `abstract.jl:current_context`). And
  `with(...) do…end` is a genuine `try/finally` — the same deterministic
  cleanup v0.1 bead `sv3` built by hand (quarry: v0.1's `@context` macro
  wraps body in `try/finally cleanup!`, explicitly commenting "NOT a Julia
  finalizer. Finalizer + FFI is unsafe (runs in arbitrary GC contexts)").
  v2 keeps the deterministic free, **drops the finalizer, drives it from the
  region** (audit §5).

### 4.2 `region() do … end` (D10 manual form)

A bare-noun do-block in Base's resource idiom (`open`, `lock`,
`mktempdir`); "scope" was rejected as doubly-claimed by Julia's lexical
scope + `Base.ScopedValues` (D10, PRD §3.9). Operates on
`current_context()`; pushes an owned-set frame, runs the body, pops and
traces owned-unconsumed in `finally`:

```julia
function region(f)
  c = current_context(); _enter_region!(c)
  try f() finally _exit_region!(c) end
end
```

### 4.3 Per-region owned set and the exit trace

Each region frame records the `WireID`s **allocated inside it** (owned).
`_exit_region!` traces every owned wire that is **not** in the consumed set
and **not** a borrowed view — via `trace!` (Eager measure-discard / DM
ptrace, §3). Consumed handles are skipped for free by the single-sourced
set (§4.5). **Views borrow, never own** (§3.9): `dual(q)`, `view(V,q)`,
`x[i]` (M4/M6) register no owned wire, so their death traces nothing;
returning a view of a dying local is a loud error (M4). Eager helpers that
allocate but open no region **inherit** the enclosing region — *provably
harmless*, because trace **timing is denotationally invisible** (no
backaction): where a boundary falls is a resource/DAG-shape question only
(D10; §5.7 tests exactly this).

### 4.4 Deterministic frees, no finalizers

Each owned Orkan state buffer is freed by the region on exit (`state_free`
/ libc-free for superops), inside the `with`/`region` `try/finally` — never
a GC finalizer (nondeterministic; unsafe under FFI — quarry note). A debug
build **may** attach a finalizer that only *detects* a lost handle and
`@warn`s; it must never trace (the trace is part of the denotation and must
sit at a definite circuit position — §3.9 "Regions, not GC").

### 4.5 Strict-mode scaffold (detector lands M6)

The `x += a` rebind trap, the generic-`f` fold trap, and "a handle survived
to teardown" are **one** defect signature (D10; §3.9): *at region exit, a
traced register that is an entangling-op **parent** of a surviving
register* — a **classical** lost-binding error, never quantum nagging. M2
lays the **hooks**: one `parent::Dict{WireID,WireID}` (or per-wire field)
on the context, populated by fresh-output ops, and an `_exit_region!`
check point that is a no-op until M6 (there are no fresh-output ops before
M6's arithmetic). The default stays silent; strict mode is opt-in. Scaffold
= the field + the exit hook + a policy test that it is inert when empty.

---

## 5. Test plan

All statistical tests use N ≥ 1000 with tolerance; all float comparisons
`≈` (OpenMP nondeterminism, PRD §4.1); references are the M1
`denoted_matrix` (the reference semantics — §3.3 of ctrl/u2).

1. **FFI smoke + guards.** load `liborkan`; `state_init/free`; apply `x`,
   read amplitude; then out-of-range wire, NULL data, non-distinct 2q/3q,
   `channel_1q` on PURE, `channel_1q` with `n_qubits≠1` → each raises a
   **Julia error before the ccall** (can't observe `exit()`, so assert the
   guard fires — §1.4). The `channel_1q` guard is the named **§8.6/`1oy`
   regression** (§5.10).
2. **`Ad` U2 round-trip (1–3 wires).** random `U2 u` on a chosen wire,
   identity elsewhere; random input statevector; apply; compare resulting
   vector to `kron`(I,…,`denoted_matrix(u)`,…,I)·input. **This test pins the
   wire↔index map (§1.6) and the rz/ry convention (§2.1)** — any slip
   localizes here.
3. **ZYZ extraction fuzz, incl. near-singular.** random `U2` → `(a,b,c)` →
   dense `Rz(a)Ry(b)Rz(c)` (from kernel constants' `denoted_matrix`) ≈
   `denoted(U(q))` (SU(2) part, φ dropped). **Explicit poles:** `b≈0`
   (diagonal `u`: random `Rz`), `b≈π` (anti-diagonal: `X·Rz`), and `±ε`
   perturbations; assert reconstruction ≈ `S` **and** no `NaN` (the branch
   guard). θ ∈ {0, π, ±ε} exactly.
4. **Controlled-decomposition, denotation/Choi-level (k=1,2,3).** for random
   `u`, apply `Ctrl(k,u)` via `Ad` across a basis (or the maximally-entangled
   Choi input) and compare the realized operator to
   `denoted_matrix(Ctrl(k,u))`. **Phase-sensitive cases (the point):**
   `u=gphase(α)` ⇒ result = `diag(1,…,e^{iα})` (**catches dropped φ**);
   `u=X` ⇒ matches native `cx`/`ccx`; **`ctrl(NEG_I) ≠ ctrl(I2)`**
   (Tang–Wright `I`-vs-`−I`, distinguishable). Ancilla-ladder and Barenco
   k≥2 paths both checked. `sqrt_u2`: `V∘V ≈ u` on random `u`.
5. **Phase-exactness law.** `Ad(ctrl(gphase(α) ∘ u))` equals
   `Ad(ctrl(u))` followed by `p(α)` on the control — asserted at the
   statevector level. Directly encodes `ctrl(g) ≠ ctrl(e^{iα}g)`.
6. **ScopedValue propagation into `Threads.@spawn`.** inside `@context ctx`,
   spawn a child that reads `current_context()`; assert it sees `ctx`
   (not an error). Documented contrast: TLS would fail — the deleted bug
   class.
7. **Region-exit traces owned-only.** allocate several wires in a region;
   consume some (M3 `Bool`, or `ptrace!` in M2); leave one owned; borrow a
   view; assert on exit **only** the owned-unconsumed wire is traced (state
   shrinks / consumed set), the borrowed view traces nothing, consumed ones
   are skipped.
8. **Trace-timing invariance.** a helper allocates a local and either
   inherits the region or opens `region()`; assert output **statistics**
   equal (N≥1000, tol) across both — but **not** stream equality.
9. **Seeded-tests-never-assert-trace-placement (policy test).** same seed,
   two different region structures (inherit vs `region()`); assert marginal
   statistics equal; assert the test does **not** compare RNG draws /
   collapse order. (Encodes the D10 corollary: statistics invariant, streams
   not.)
10. **§8.4 aliasing regression hook.** apply a 2-wire controlled op (or
    `cx`) with the **same `WireID`** for control and target → raises a Julia
    error **naming the register identity**, **before** the ffi shim's
    raw-index check (§1.6, §4.5). This is the named 8.4 regression test
    (control=target aliasing, the kernel-level shadow of `when(a){not!(a)}`).
11. **reset-on-recycle.** trace a wire collapsed toward |1⟩, recycle its
    slot, assert a freshly-allocated wire reads |0⟩ (the "fresh = |e_G⟩"
    invariant; `ptrace! ≠ reset`).
12. **Strict-mode scaffold inert-when-empty.** `_exit_region!`'s detector
    hook is a no-op with an empty parent map (M6 activates it).

---

## 6. Namespace / files, public vs internal

| File | Contents | Visibility |
|---|---|---|
| `src/orkan/ffi.jl` | raw guarded ccall wrappers, structs, `__init__` (path + OMP) | **internal** (`orkan_*`, `OrkanStateRaw` — not exported, not `public`) |
| `src/orkan/state.jl` | state lifecycle, bulk `unsafe_wrap` view, grow/embed, readout | internal |
| `src/orkan/ad.jl` *(D-A1)* | `apply!`, ZYZ, ABC, `sqrt_u2`, Ctrl/Perm/Tensor/Seq lowering | `public apply!`; helpers internal. **Choke-point file** (lint target) |
| `src/context/abstract.jl` | `AbstractContext`, minimal `WireID` *(D-A2)*, primitive-gate generics, consumed set, `current_context` | `public AbstractContext, WireID, current_context, apply!`; `_x!`… internal |
| `src/context/eager.jl` | `EagerContext` (PURE), primitive impls, measure-discard trace | `public EagerContext` |
| `src/context/density.jl` | `DensityMatrixContext` (MIXED, minimal), exact ptrace, 1-local channel | `public DensityMatrixContext` |
| `src/context/regions.jl` | `@context`, `region`, `ptrace!`, enter/exit, owned set, strict hooks | **export** `@context`, `region`, `ptrace!` (surface scaffolding — used in PRD examples); `_enter_region!` internal |

**Layering (CLAUDE.md convention 8).** Surface scaffolding users type in
examples — `@context`, `region`, `ptrace!` — is **exported**. Context types
(`EagerContext`, `DensityMatrixContext`) and `apply!`/`WireID`/
`current_context` are **`public`** (reachable as `Sturm.EagerContext`,
documented, not dumped into `using Sturm`). The ffi shim and Ad internals
are neither. Boot lints (from M1) extend: `orkan_cx|controlled` tokens must
appear only under `src/kernel/` or `src/orkan/` — `ad.jl` satisfies this;
`eager.jl`/`density.jl` reach the controlled ccalls only *through* `ad.jl`'s
emitter, keeping the choke point single.

**Distillation owed before code (CLAUDE.md #4, PRD §9 Citations TODO).**
`Ad`'s ZYZ + ABC controlled-U decomposition cites **Nielsen–Chuang §4.3**
(Thm 4.1 ZYZ / Cor 4.2 ABC) and the C²/MCU constructions cite
**Barenco et al. 1995 (quant-ph/9503016), Lemmas 5.1/7.5** — neither is yet
in `docs/physics/`. Write `docs/physics/nielsen_chuang_ad_decomposition.md`
and `docs/physics/barenco_1995_controlled_decompositions.md` (theorem +
equation + page) **before** the `ad.jl` docstrings cite them. The phase
argument reuses the existing `tang_wright_2025_controlled_unitaries.md`
(Thm 1.1), `delorme_control_as_constructor.md` (Def 1, Caveats), and
`wharton_koch_quaternion_bloch.md` (pinned convention) — already present.

---

## Executive summary (key decisions + deviations)

1. **Ad splits cleanly because U2 splits.** Uncontrolled path drops `φ` by
   *not emitting* a `p()` call and reproduces `S=U(q)` via ZYZ — **exact,
   det-1, no residual phase**. That is the whole payoff of quaternion+phase.
2. **ZYZ derived on paper** from the pinned convention:
   `b=2·atan2(√(x²+y²),√(w²+z²))`, `a=atan2(−x,y)−atan2(−z,w)`,
   `c=−atan2(−x,y)−atan2(−z,w)`; singular folds at `b≈0` (`a=2atan2(z,w)`,
   `c=0`) and `b≈π` (`a=2atan2(−x,y)`, `c=0`) — written **once**, at the FFI
   boundary (D7), tested at θ∈{0,π,±ε}.
3. **Controlled-U2 = ABC ladder + one `p(φ)` on the control.** Derived and
   verified (`ABC=I`, `AXBXC=S`); `φ` becomes the controlled phase at that
   single line. Dropping it reproduces the exact Cirq/Qiskit/pytket bug;
   `ctrl(gphase(α))=p(α)`-on-control and `ctrl(NEG_I)≠ctrl(I2)` are named
   tests. ABC is legitimate here (kernel IR lowering of a `ctrl` VALUE), not
   v0.1 surface heresy (P5).
4. **k≥2 primary = ancilla AND-ladder** so `p(φ)` fires iff *all* controls
   are 1 (uniform, phase-correct); Barenco C-V (via `sqrt_u2`, `V∘V≈u`) is
   the ancilla-free fallback. Both cross-checked vs `denoted_matrix`.
5. **Structural recursion** for `Ctrl{Seq}` (homomorphism over `∘`),
   `Ctrl{Tensor}` (shared controls, no `⊗`-distribution — delorme), `Perm`
   replay (MCX→x/cx/ccx/ancilla-ladder). **No `apply!` catch-all** —
   `MethodError` on unhandled kinds (P4, mirrors ctrl.jl).
6. **One emitter, all contexts.** Orkan gate functions dispatch on
   state-type internally, so Eager and DM share the *entire* `Ad` emitter;
   they differ only in trace lowering (Eager measure-discard + RNG; DM exact
   Julia-side ptrace) and channel support. **Do NOT bind `single_from_mat`**
   (header-private, tiled-only, `LOG_TILE_DIM`-coupled — worst ABI-drift
   risk; audit §8.5).
7. **Regions = Stinespring boundary, silent trace.** `@context` on
   `ScopedValues.with` (inherits into `Threads.@spawn`; TLS bug class
   deleted), `region() do…end` (D10), deterministic `state_free` in
   `try/finally` (no finalizers — sv3), owned-only exit trace via the
   **single-sourced consumed set**; trace timing denotationally invisible.
8. **Fail-loud FFI guards re-derived from the `exit()` model** (24/24 shapes
   re-ported); the `channel_1q` guard is the `1oy` process-kill regression.
   The §8.4 aliasing check fires on `WireID` identity before the shim.
9. **Deviations from the plan baseline:** *D-A1* add `src/orkan/ad.jl` (Ad
   is substantial physics-derived math + the lint-visible choke point, not
   ffi plumbing); *D-A2* land a minimal `WireID` in M2 (the consumed set,
   owned set, and §8.4 check need identity now; M3 wraps it). Both flagged
   for the reviewer; neither forces M3 rework.
10. **Owed before code:** Nielsen–Chuang §4.3 and Barenco 1995 distillations
    (ZYZ/ABC/C²/MCU) must land in `docs/physics/` before `ad.jl` cites them
    (CLAUDE.md #4); the phase/convention citations already exist.
