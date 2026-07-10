# M2 Design — Orkan FFI + contexts + regions (PROPOSER B)

**Bead:** Sturm.jl-dc6i · **Milestone:** M2 · **Lens:** systems & failure-modes first.
**Binding:** CLAUDE.md (esp. #1 fail-loud, #4 ctrl/P4, #11 no gates on surface, Julia-conv 6 ScopedValues);
PRD-v2 §3.9, §4.1, §4.2, §4.3, §4.4, §8.4; D7/D10/D11/D12/D13; `docs/design/orkan-abi-audit-m2.md`
(cited below as **AUDIT §n**); landed M1 kernel `src/kernel/*.jl`.

Everything below is grounded in the audited Orkan ABI and the M1 kernel that already exists. No Julia was run.

---

## 0. Executive summary (the ten decisions)

1. **One Orkan `state_t` per context, not per wire.** The context owns a single pre-sized register file;
   wires are *slots* inside it (v0.1 model, AUDIT §5). Region exit traces slots; only *context* teardown
   frees the `state_t`. This makes the try/finally topology trivially leak-safe.
2. **Deterministic lifecycle via a resource do-block** `eager(cap) do ctx … end` whose `finally` calls
   `state_free` — free happens even on a thrown exception mid-region. Finalizer is a *debug leak detector
   only* (warn, never `ccall` in GC context — AUDIT §5, v0.1 sv3 note: "finalizer + FFI is unsafe").
3. **Every ccall is guarded Julia-side BEFORE the call** (AUDIT §5: Orkan `exit()`s on bad input → process
   death). Re-port `_check_qubit`/`_check_distinct`/`_check_distinct3` verbatim; add NULL-data and
   OOM-after-alloc checks. The §8.4 DSL aliasing check (register identity) fires *above* these shims.
4. **D7 is closed by storage, not benchmark (AUDIT §2): pure path lowers `U2` through ZYZ only** — no
   matrix/quaternion entry exists on `PURE`. 3 ccalls (`rz;ry;rz`) per applied `U2`; the θ≈0/π chart
   singularity branch is written *here and nowhere else* (PRD §4.1/§4.3). `single_from_mat` is
   **NOT bound** (header-private, tiled-DM-only, `LOG_TILE_DIM`-coupled — AUDIT §8.5, the biggest risk).
5. **`ctrl(U2)` lowers by the ABC (Nielsen–Chuang) construction — legitimate *inside the kernel*** as the
   lowering of a phase-carrying `ctrl` *value*, not a surface convention. **The inner `U2.φ` becomes a
   `p(control, φ)` controlled-phase** — this is where phase-exactness lives (`ctrl(g) ≠ ctrl(e^{iα}g)`).
6. **Multi-control:** k=1 ABC; k=2 either sqrt-V (N&C C²(U), no ancilla) or a CCX-AND-ancilla ladder;
   k≥3 clean-ancilla Toffoli tree (k−1 ancillas from the context, compute/uncompute ⇒ returned to |0⟩).
   `Perm` replay reuses the same MCX→{x,cx,ccx,ladder} lowering. `Ctrl{Perm}` never forms (ctrl(Perm)=Perm).
7. **Wire convention pinned in ONE function** `q(ctx, wire)::qubit_t`. Orkan is **little-endian**
   (`stride = 1<<target`, qubit i = bit i, qubit 0 = LSB — confirmed in `gate_pure.c`); kernel is **wire 1
   = MSB**. Alignment: value-position `i` of an n-wire block → the block's descending Orkan slot. The
   round-trip test asserts "X on the MSB wire flips the *high* bit", catching any endianness/off-by-one slip.
8. **RNG is Julia's, single-sourced on the context** (`ctx.rng::AbstractRNG`). Orkan has no RNG (AUDIT §6).
   Seeded reproducibility = pass a seeded RNG in. Trace-timing caveat (§3.9): measure-and-discard advances
   the stream, so *seeded tests never assert trace placement* — a named policy test.
9. **Regions are bookkeeping + traces, not allocations.** `@context` binds a `Base.ScopedValue` via `with`
   (inherits into `Threads.@spawn`, TLS does not — Julia-conv 6). `region() do…end` owns a wire set; exit
   `ptrace!`s the owned-and-unconsumed wires (Eager: measure-and-discard; DM: exact ptrace) — **silent, no
   backaction** (§3.9 principled exception to #1). Consumed set is single-sourced on the context (§4.5/§8.5).
10. **DensityMatrix context is minimal but real** — enough for M3's Choi harness: `MIXED_TILED` storage,
    `U2` as conjugation via the *same* ZYZ path, `channel_1q` for 1-local Kraus, exact `ptrace!`. No
    `single_from_mat` (same risk); no multi-qubit channels (AUDIT §8.4 — 1-local only, Choi ≤15 wires).

### Deviations from the plan baseline
- **Plan says "if both a general-1q entry and rz/ry/rz exist, measure both" (line 150).** The audit shows the
  general entry does not exist on `PURE` and is unsafe to bind on DM (header-private). **Deviation: no
  benchmark; ZYZ is the sole path on both contexts, `single_from_mat` explicitly deferred behind an Orkan
  header-promotion request.** Rationale: AUDIT §8.5 — a header-private, tile-constant-coupled symbol on the
  critical path is exactly the "ABT drift with no header diff to detect it" risk the register (plan §6.2) warns of.
- **Plan lists `density.jl` "(minimal)".** I keep it minimal but insist it carry `ptrace!`-exact and 1-local
  `channel_1q` *now*, because M3's Choi harness (next milestone) needs channel execution — deferring it
  creates a false-green M2. Not a deviation in scope, a sharpening of "minimal".
- **Context lifecycle:** plan says "handles owned by the context, freed in deterministic cleanup" but does not
  fix the granularity. I fix it: **one `state_t` per context, freed at context teardown; regions free only
  slots.** This is the load-bearing failure-mode decision and I make it explicit.

---

## 1. FFI layer — `src/orkan/ffi.jl`, `src/orkan/state.jl`

### 1.1 Library discovery (re-port v0.1, AUDIT §9)
`src/orkan/ffi.jl` opens with the v0.1 loader **verbatim** (AUDIT §4 confirms 24/24 ccall shapes current):
```
search order: ENV["LIBORKAN_PATH"]  →
              joinpath(@__DIR__,"..","..","..","orkan","cmake-build-release","src","liborkan.so")  →
              "liborkan" via dlopen
```
`_try_dlopen` **must `rethrow()` `InterruptException`** (v0.1 bead `-011f`) — a bare `catch` swallowing Ctrl-C
is a regression test. Failure `error()`s with the build recipe. `const LIBORKAN = <resolved path>` at module
load. The path resolution runs at top level (it only touches the filesystem), but see §1.5 for what must move
to `__init__`.

### 1.2 Raw structs (byte-exact, AUDIT §1/§4)
Port `OrkanStateRaw` (24 B: `type::Cint`, pad, `data::Ptr{ComplexF64}`, `qubits::UInt8`, pad),
`OrkanKrausRaw` (24 B, immutable, Julia-owned buffer + `GC.@preserve`), `OrkanSuperopRaw` (16 B, mutable —
owns an Orkan-`calloc`'d buffer freed via `Libc.free`, **there is no `superop_free` in Orkan** — AUDIT §5).
Layout is asserted at load with a `@assert sizeof(OrkanStateRaw) == 24` boot check (fail-loud on any future
ABI drift — plan §6.2).

### 1.3 Wrapped ccalls — every one validates first (AUDIT §5, #1 FAIL LOUD)
Orkan gates are `void` and `exit(EXIT_FAILURE)` on bad index; a missed guard is **process death, not an
exception** (v0.1 learned this twice: beads `-1oy` channel omission, `-5z3r`). Guards, Julia-side, before
*every* ccall:
- `_check_qubit(state, q, name)` — `data != C_NULL` **and** `0 ≤ q < state.qubits`.
- `_check_distinct` / `_check_distinct3` for cx/cy/cz/swap and ccx.
- `channel_1q`: additionally `sop.n_qubits == 1` and `state.type != PURE` (it `exit()`s on PURE — AUDIT §1).
- `state_init`/`state_plus`: check `state.data == C_NULL` *after* the call → `error("OOM for n qubits")`
  (AUDIT §5, OOM is silent-ish: prints stderr, leaves NULL).

Wrapped set (names/shapes from AUDIT §4, all VERIFIED-STILL-CURRENT):
`state_init, state_free, state_plus, state_len, state_get, state_set, state_cp(by value),
x y z h s sdg t tdg hy, rx ry rz p, cx cy cz, swap_gate, ccx, kraus_to_superop, channel_1q`.
Generated by the same `@eval` loops v0.1 used. **`single_from_mat`/`two_from_mat` are deliberately NOT
wrapped** (AUDIT §8.5).

### 1.4 Handle lifecycle — the failure-mode core
- **Granularity: one `state_t` per context.** `state.jl` wraps `OrkanStateRaw` in an `OrkanState` that the
  context owns. Wires are *slots* (0-based qubit indices) inside this one state; **no per-wire Orkan handle**.
- **Who allocates:** context constructor calls `state_init`/`state_plus` once (capacity = declared max wires).
- **Who frees:** the context resource form's `finally` (§4.1) calls `state_free` exactly once. `state_free` is
  NULL-safe/idempotent (AUDIT §5) so a double-free is harmless, but the invariant is single-free.
- **`state_cp` (deep copy by value):** used by the DM Choi harness and any snapshot; the returned struct's
  `data` is caller-owned → freed via `state_free`. Wrap in the context's owned-snapshot list.
- **`kraus_to_superop`:** `out.data` is Orkan-`calloc`'d; free via `Libc.free` (no Orkan free fn). The
  superop is a transient inside the channel-apply call; free in that call's own `finally`.

### 1.5 `__init__` — OMP ceiling (AUDIT §7)
Orkan has **no thread-config API**; threading is `OMP_NUM_THREADS` only. In `__init__` (NOT top level —
precompile vs load-time):
```
if !haskey(ENV,"OMP_NUM_THREADS")
    ENV["OMP_NUM_THREADS"] = string(clamp(Sys.CPU_THREADS ÷ 4, 1, 16))   # 16 = device ceiling (project memory)
end
```
Also in `__init__`: the `sizeof` ABI assertions and any `STURM_*` env caches (v0.1 `_COMPACT_VERIFY_ENABLED`
pattern) read here so the hot path dereferences a `Ref`, never `ENV`.

### 1.6 Sampling / bulk reads (AUDIT §6 cost note)
No Orkan RNG. `probabilities`/`sample` are Julia-side. **Prefer `unsafe_wrap` of `state.data` over per-element
`state_get`** — the pointer and `state_len` are exposed, and PURE data is a flat `2^n` `ComplexF64` vector;
per-amplitude `state_get` is one ccall each (v0.1 flagged 16 MB/call at n=20, bead `-5z3r`). Guard the wrap
with `GC.@preserve state`. MIXED storage is triangular → use the Hermitian-aware `state_get` there.

---

## 2. Ad — the application kernel (PRD §4.3)

`Ad_g(ρ) = gρg†`, `ker(Ad) = U(1)`. **The phase quotient is crossed exactly once, here.** Dispatch is
(value-kind × context-kind); the pure (Eager) path is primary. Lives in `src/orkan/` (or a new
`src/kernel/ad.jl` included after the FFI) — the ONLY site of ZYZ extraction and the ONLY site of controlled
lowering (both grep-linted per M1 ctrl.jl: `orkan_cx|controlled` only under `src/kernel/`+`src/orkan/`).

### 2.1 `U2` → ZYZ extraction (the one chart-singularity site)
The M1 `U2 = (w,x,y,z,φ)` denotes `e^{iφ}·U(q)` with `U(q) = w·I − i(xσx+yσy+zσz) = e^{−iθ n·σ/2}` — the
standard rotation operator (constants.jl: `Rz(γ)=(cos γ/2,0,0,sin γ/2)`, `Ry(β)=(cos β/2,0,sin β/2,0)`;
Orkan `rz(θ)=diag(e^{−iθ/2},e^{iθ/2})`, `ry(θ)=[[c,−s],[s,c]]`, `p(θ)=diag(1,e^{iθ})`).

Goal: `U(q) = Rz(α)·Ry(β)·Rz(γ)` (all SU(2), det 1). Computing the quaternion of `Rz(α)∘Ry(β)∘Rz(γ)` with
the M1 Hamilton product gives, exactly:
```
w = cos(β/2)·cos((α+γ)/2)
x = −sin(β/2)·sin((α−γ)/2)
y =  sin(β/2)·cos((α−γ)/2)
z =  cos(β/2)·sin((α+γ)/2)
```
**Inversion (the extraction):** let `c = hypot(w,z) = |cos(β/2)|`, `s = hypot(x,y) = |sin(β/2)|`.
```
β = 2·atan(s, c)                     # ∈ [0, π]
p := (α+γ)/2 = atan(z, w)            # well-defined iff c ≳ ε
m := (α−γ)/2 = atan(−x, y)           # well-defined iff s ≳ ε
α = p + m ;  γ = p − m
```
Emit (right-to-left, `b` first): **`rz(γ); ry(β); rz(α)`** — 3 ccalls. **φ is dropped here** (uncontrolled
path: `e^{iφ}` cancels in `gρg†`, and `U(q)` is det 1 so the product `Rz·Ry·Rz` reproduces it with no residual
phase — nothing is lost).

**Singular branches (θ≈0/π gimbal lock — the load-bearing branch, PRD §4.1, Stuelpnagel 1964: a topological
fact about SO(3)/SU(2), not a convention):**
- **β ≈ 0** (`s < CHART_EPS`, i.e. `x,y ≈ 0`): only `α+γ = 2p` is determined; `m` is `atan(0,0)` garbage. Fold:
  set `γ = 0`, `α = 2·atan(z,w)`. Emit a **single `rz(α)`** (skip ry, skip second rz).
- **β ≈ π** (`c < CHART_EPS`, i.e. `w,z ≈ 0`): only `α−γ = 2m` is determined; `p` garbage. Fold: set `γ = 0`,
  `α = 2·atan(−x,y)`, `β = π`. Emit **`ry(π); rz(α)`** (2 ccalls).
`CHART_EPS` lives in `kernel/numerics.jl` next to `U2_ATOL` (~1e-12; the fold error is O(ε²)). The fuzz test
(§5) drives random `U2` *and* explicit θ ∈ {0, π, ±1e-9, ±1e-13} through extraction and asserts the dense
`rz·ry·rz` product ≈ `denoted_matrix(u)` up to global phase.

### 2.2 `Ctrl{U2}`, k=1 — ABC, phase-exact (the heart)
`ctrl(u)` denotes `|0⟩⟨0|⊗I + |1⟩⟨1|⊗(e^{iφ}U(q))` (M1 `denoted_matrix(::Ctrl)`). Factor the phase:
`= [ |1⟩⟨1|-phase e^{iφ} on control ] ∘ [ C-U(q), SU(2) ]`.

**Why ABC is legitimate here but was heresy in v0.1.** v0.1's `multi_control.jl` applied the ABC
decomposition as a *surface primitive on channels*, silently choosing an SU(2) section — the exact P1/P4
tension §1.1 condemns (the global phase was thrown away by convention in library code, so controlled circuits
lost it — the Cirq/Qiskit/pytket bug class, §4.2). **Here ABC is the lowering of a phase-carrying `ctrl`
*value* at the single choke point**, and the phase is carried *explicitly* into `p(control, φ)` — never
quotiented. The phase quotient is crossed once (at Ad, on the *uncontrolled* body pieces A/B/C), and `ctrl`'s
own phase survives as a physical controlled-phase. That is the structural invariant M1 ctrl.jl documents.

Construction (N&C 4.3): with `U(q) = Rz(α)Ry(β)Rz(γ)`,
```
A = Rz(α) ∘ Ry(β/2)
B = Ry(−β/2) ∘ Rz(−(α+γ)/2)
C = Rz((γ−α)/2)
```
so `A∘B∘C = I` and `A·X·B·X·C = U(q)`. Emit (A,B,C are U2 values → each via §2.1 uncontrolled ZYZ; their
own φ is 0):
```
apply C on target                 #  (≤3 ccalls)
cx(control, target)
apply B on target
cx(control, target)
apply A on target
p(control, φ)                     #  ← inner U2.φ becomes the controlled-phase.  THIS is phase-exactness.
```
`p(control, 0)` is a no-op and may be skipped when `|φ| < CHART_EPS` (fast path for SU(2) inners), but the
branch must exist so `ctrl(gphase(α))` lowers to a pure `p(control,α)` (a Z-rotation on the control —
M1 constants.jl `gphase` docstring; Tang–Wright Thm 1.1). Cross-check: `denoted_matrix` of the emitted
sequence ≈ `denoted_matrix(ctrl(u))` (§5).

### 2.3 `Ctrl{U2}`, k=2 and k≥3
- **k=2, no ancilla (default):** N&C C²(U): with `V` a `U2` s.t. `V∘V ≈ inner` (full-U2 sqrt — quaternion
  half-angle *and* φ/2; principal branch, flag the ± sqrt subtlety),
  ```
  CV(c2, target); cx(c1,c2); CV†(c2,target); cx(c1,c2); CV(c1,target)
  ```
  where each `CV`/`CV†` is the k=1 ABC of §2.2. The N&C identity is exact for *any* `U=V²` including phase, so
  `V`'s own φ (=φ/2) handled by CV's `p(control,·)` reproduces the block phase automatically — no separate
  phase term. `inner = X, φ∈{0,π}` special-cases to native `ccx` (+ optional `p` for the π).
- **k≥3, clean-ancilla Toffoli tree:** request `k−1` scratch wires from the context allocator; AND-reduce the
  `k` controls into one wire via a `ccx` tree (depth ⌈log₂k⌉); apply the k=1 ABC off that wire; **uncompute
  the tree** (reverse `ccx`) → ancillas provably return to |0⟩ (matched compute/uncompute), asserted and
  recycled. Barenco et al. 1995 (borrowed-ancilla / linear-depth) is the optimization *horizon*, not M2.
  **Ancilla policy:** scratch wires are context-owned, never surface-visible; under a future `when`/ctrl stack
  (M5) this is the clean-ancilla pattern (§3.9 witness); at M2 it is a pure kernel-internal borrow.

### 2.4 `Ctrl{Perm}` / `Perm` → replay
`ctrl(::Perm) = Perm` at the kernel (M1 perm.jl), so **`Ctrl{Perm}` never forms** — Ad only sees `Perm`.
Replay each `MCX(controls, target)` generator in order → lower by control count: `0 → x`, `1 → cx`,
`2 → ccx`, `≥3 → §2.3 k≥3 ladder with X as the inner`. Negative controls are already X-conjugated in the M1
representation (perm.jl), so replay is uniform. Wire indices map through `q(ctx, wire)` (§0.7).

### 2.5 `Ctrl{Tensor}` / `Ctrl{Seq}` / `Tensor` / `Seq` → recursion
- `Ad(Tensor(a,b))`: apply `Ad(a)` on the leading (MSB) wire block, `Ad(b)` on the trailing block.
- `Ad(Seq(a,b))`: apply `Ad(b)` then `Ad(a)` (right-to-left, matching `denoted_matrix(::Seq)=matrix(a)*matrix(b)`).
- `Ad(Ctrl(k, Tensor(a,b)))`: `Ctrl(k,a)` on controls+a-wires, then `Ctrl(k,b)` on controls+b-wires
  (disjoint targets commute — Delorme's `C(a⊗b) ≠ C(a)⊗C(b)` is respected: one *shared* control set, gating
  each factor, NOT two control sets — M1 ctrl.jl docstring).
- `Ad(Ctrl(k, Seq(a,b)))`: `Ctrl(k,b)` then `Ctrl(k,a)` (the §4.2 homomorphism `ctrl(g∘h)=ctrl(g)∘ctrl(h)`).
Totality is exhaustive concrete methods (mirrors M1 ctrl.jl's no-catch-all rule): an unhandled kind is a
`MethodError`, never a silent wrong lowering. M8's `UnitaryDAG` adds one `Ad` method with no change here.

### 2.6 Per-op overhead (lens)
Post 1q-fusion (kernel fuses `U2∘U2` to a single `U2` before Ad — plan §4 "per-wire 1q fusion buffer, flush at
entangling/measure/barrier"): **1 applied `U2` = 3 ccalls** (1 or 2 in the singular branches). k=1 ctrl ≈ 3×(A,B,C
ZYZ) + 2 cx + 1 p ≈ 12 ccalls. The fusion buffer is a per-wire `U2` accumulator in the Eager context; flushed
by entangling ops (`cx` etc.), measurement, and barriers. `current_context()` (ScopedValue) is read **once per
surface entry**; the context is then threaded through the kernel call chain (ScopedValue access allocates —
Julia-conv 6). `q(ctx,wire)` is one `Dict` lookup per wire per flush.

---

## 3. Context layer — `abstract.jl`, `eager.jl`, `density.jl`

### 3.1 `AbstractContext` interface (what a context MUST implement)
```
allocate!(ctx) -> WireID                 # fresh wire in canonical |e_G⟩ (=|0⟩); §3.9 entry
deallocate!(ctx, w::WireID)              # trace-and-recycle (measure-discard on Eager; exact ptrace on DM)
apply!(ctx, value::ProcessValue, wires)  # Ad dispatch (§2); wires is the position→WireID tuple
q(ctx, w::WireID) -> qubit_t             # THE wire→Orkan-index map (§0.7) — single source of truth
consumed(ctx) -> Set{WireID}             # single-sourced linearity set (§4.5); per-object flag is at most a cache
mark_consumed!(ctx, w)                   # qc casts + ptrace! only (the two consumption sites, §4.5)
rng(ctx) -> AbstractRNG                  # seeded reproducibility lives here (§0.8)
teardown!(ctx)                           # state_free; called by the resource form's finally
```
`live_wires(ctx)` (v0.1 sv3) returns the current owned-and-unconsumed wires for region cleanup. Region
machinery (§4) is context-agnostic and lives in `regions.jl` atop these.

### 3.2 `EagerContext` (pure statevector — primary path)
```
mutable struct EagerContext <: AbstractContext
    state::OrkanState            # ONE state_t, PURE, capacity qubits, allocated at construction
    wire_to_qubit::Dict{WireID,Int}   # WireID → 0-based Orkan slot
    consumed::Set{WireID}             # single-sourced (§8.5 fix)
    free_slots::Vector{Int}           # recycled slots, each reset to |0⟩ (reset-on-recycle invariant)
    n_qubits::Int                     # high-water live count
    capacity::Int
    fusion::Dict{WireID,U2}           # per-wire 1q fusion buffer (§2.6); flush at entangle/measure/barrier
    rng::AbstractRNG                  # default Random.default_rng(); pass a seeded RNG for reproducible tests
end
```
- **allocate!**: reuse a `free_slot` (already |0⟩) if any, else bump `n_qubits`; map the WireID. Wire is born
  in |0⟩ = |e_G⟩ (§3.9 entry: allocation is initialization; there is no bare-alloc surface form).
- **apply!**: flush the fusion buffer of any wire the value entangles/measures, then dispatch Ad (§2).
- **deallocate!**: measure-and-discard (§4.3), reset the slot to |0⟩, push to `free_slots` (reset-on-recycle:
  "fresh = |e_G⟩" invariant, §3.9 — `ptrace! ≠ reset`, so we actively reset before recycling).
- Logical compaction (v0.1 pw9: shrink active dim after ancilla bursts) is **deferred** — noted, not M2.

### 3.3 `q(ctx, wire)` and the endianness pin (the classic silent killer)
Orkan is **little-endian**: `gate_pure.c` uses `stride = 1<<target`, so Orkan qubit `t` = bit `t` of the flat
index, qubit 0 = LSB. Kernel is **wire 1 = MSB** (M1 perm.jl/ctrl.jl: wire `c` holds bit `n−c`). For a value
applied to a wire tuple `wires[1..m]` (position 1 = MSB), Ad addresses Orkan qubit `q(ctx, wires[i])`. The
**pin**: allocation/addressing arranges that value-position ordering (MSB→LSB) maps monotonically to *this
value's* Orkan slots so the denoted-matrix bit order matches the statevector bit order with **no reversal**.
The single source of truth is `q(ctx,wire)`; nothing else computes a qubit index. The reference-comparison
harness (§5) builds its dense operator by embedding value-position `i` at the global Orkan bit `q(ctx,wires[i])`
(LSB=0), so kernel `denoted_matrix` (MSB-first) and Orkan (LSB=qubit-index) are reconciled in exactly one place.
**Regression test:** apply `X` to the MSB wire of a 3-wire register in |0⟩, read the basis index via bulk
`unsafe_wrap`, assert the **high** bit set (index 4), not the low (index 1). An off-by-one/endianness slip
fails this and only this.

### 3.4 `DensityMatrixContext` (minimal, MIXED_TILED)
Enough for M3's Choi harness (DM executes *channels* → Choi deterministic in one run):
- `state_init` with `type = MIXED_TILED`; `state_plus` = maximally mixed.
- `U2` applies as conjugation `ρ ← UρU†` via the **same ZYZ named-gate path** (each Orkan gate dispatches
  PURE/PACKED/TILED internally — AUDIT §1). **Not** `single_from_mat` (AUDIT §8.5 risk).
- 1-local Kraus/noise: `kraus_to_superop` → `channel_1q` (guarded: `sop.n_qubits==1`, non-PURE). Multi-qubit
  channels are **not native** (AUDIT §8.4) — restrict to 1-local; Choi capped at 15 wires (plan §6.4).
- `ptrace!` is **exact** (partial trace on ρ), unlike Eager's measure-and-discard unraveling.

### 3.5 Wire allocation / free / recycle summary
Fresh = canonical |0⟩ (§3.9). Recycle resets to |0⟩ *before* returning to `free_slots` (reset-on-recycle;
`ptrace!≠reset` is a physics distinction, §3.9). The consumed set is single-sourced; a wire-handle/view (M4)
does not manufacture its own flag (§8.5 regression) — it defers to `consumed(ctx)`.

---

## 4. Regions — `src/context/regions.jl` (PRD §3.9, D10)

### 4.1 Lifecycle / resource do-block (leak-safe try/finally topology)
Two nested resource idioms, both Base-shaped (`open`, `lock`, `mktempdir`):
```
eager(capacity; rng=Random.default_rng()) do ctx      # OWNS the state_t
    ...                                                # body
end                                                    # finally: teardown!(ctx) → state_free (even on throw)
```
`eager`/`density` allocate the `state_t`, bind the ScopedValue (§4.2), run the body, and in `finally` call
`teardown!` → `state_free`. **This is the sole guarantee that Orkan memory is freed on an exception mid-region**
— the process-memory safety net. A GC finalizer on the context is a **debug-only leak detector**: it `@warn`s
if a live handle reached GC (AUDIT §5 / v0.1: "finalizer + FFI is unsafe" — it must NOT `ccall state_free` from
a GC context). `state_free` being NULL-safe/idempotent means the finally + a stray detector cannot double-fault.

### 4.2 `@context` and `region()`
- `@context ctx begin … end` binds `ctx` via `Base.ScopedValues.with(CURRENT_CONTEXT => ctx) do … end` — a
  genuine `try/finally` (deterministic exit, §3.9), inheriting into `Threads.@spawn`/`@async` children (TLS
  does *not* — Julia-conv 6; a silent-missing-context bug class deleted). It does **region cleanup** of wires
  the block owns, but does **not** free the `state_t` (that is `eager`/`density`'s job, §4.1). When `ctx` is
  created *and* bound by the same call, use the `eager(...) do ctx … end` form which fuses both.
- `region() do … end` (D10 — bare-noun Base idiom; "scope" rejected, doubly claimed by Julia) opens a nested
  owned-set. Exit `ptrace!`s the region's owned-and-unconsumed wires. **Eager helpers that don't open a
  region inherit the enclosing one** — provably harmless: traces have no backaction, so trace *timing* is
  denotationally invisible (§3.9); region boundaries are a resource/DAG-shape choice only.

### 4.3 Scope-exit trace — SILENT by design (principled exception to #1)
At region/`@context` exit, every owned-and-unconsumed wire is implicitly `ptrace!`d (§3.9: locals are the
Stinespring environment; scope is the dilation boundary; every function is a channel by construction). **This
is silent** — the one sanctioned exception to FAIL-LOUD (CLAUDE.md #1 / PRD §3.9): implicit ops *with*
backaction warn (P2 casts); implicit ops *without* backaction (traces) are silent. **Do not "fix" the silence.**
Lowerings (§3.9, mirroring §4.3):
- **Eager:** measure-and-discard the wire (draw with `ctx.rng`, collapse, reset, recycle) — exact for all
  downstream statistics by no-signaling, a valid per-shot unraveling.
- **DM:** exact partial trace.
`ptrace!(ctx, w)` is the explicit early-close form; it and qc casts are the two consumption sites (§4.5).

### 4.4 Strict-mode scaffold (D10 lost-binding detector — hooks now, detector M6)
The `x += a` rebind trap, the generic-f fold trap, and "a handle survived to teardown" are one signature: *at
region exit, a traced register that is an entangling-op parent of a surviving register* (§3.9). M2 lays the
**hooks**: one parent-edge slot per fresh-output op (recorded in the context), and a debug flag. The detector
*itself* lands M6 (when fresh-output arithmetic ops exist to track) — flagging it as a **classical**
programming error (a lost binding), never quantum nagging. Default stays silent.

### 4.5 Context propagation without per-op ScopedValue reads (lens)
`current_context()` reads the ScopedValue **once per surface entry** and the context is threaded through the
kernel call chain thereafter (ScopedValue access allocates — Julia-conv 6, plan §4). The per-op hot loop
(fusion flush → Ad → ccall) never touches the ScopedValue.

---

## 5. Test plan (`test/test_orkan_ffi.jl`, `test_ad.jl`, `test_contexts.jl`, `test_regions.jl`)

Law-tests-first (plan §1.1). All float comparisons `≈` (PRD §4.1; OpenMP reduction order perturbs bits —
AUDIT §7, so **never** assert bit-exact amplitudes across runs).

1. **Apply/measure round-trips vs dense reference (1–3 wires).** For each of X,Y,Z,H,S,T,Rz/Ry/Rx(random θ),
   apply on `EagerContext`, bulk-read the statevector (`unsafe_wrap`), compare to `denoted_matrix(value)·|0…0⟩`
   — embedding via `q(ctx,wire)` (§3.3). 2q: cx/cz + a composed CNOT-from-`when`-precursor (Tensor/Seq).
2. **ZYZ extraction fuzz (§2.1), incl. singular.** 10⁴ random `U2`; assert dense `rz(γ)ry(β)rz(α) ≈
   denoted_matrix(u)` up to global phase. **Explicitly seed** θ ∈ {0, π, ±1e-9, ±1e-13} and axis-degenerate
   quaternions (`x=y≈0`; `w=z≈0`) to hit both folds. This is the load-bearing branch (AUDIT §2/§8.1).
3. **Controlled-decomposition Choi-level checks (§2.2–2.5).** For k∈{1,2,3}, random inner `U2` (incl. nonzero
   φ and `gphase(α)`): assert `denoted_matrix(Ctrl(k,inner)) ≈` the dense product of the *emitted ccall
   sequence*. The nonzero-φ case is the phase-exactness gate: `ctrl(g) ≢ ctrl(e^{iα}g)` must be *visible*
   (the `p(control,φ)` term). `Perm` replay: `denoted_matrix(perm) ≈` emitted MCX lowering (k≥3 ladder).
4. **Endianness/off-by-one regression (§3.3).** X on the MSB wire of a 3-wire |0…0⟩ ⇒ basis index 4, not 1.
5. **ScopedValue propagation into `Threads.@spawn`.** Bind `@context`; assert a spawned child sees the same
   context (and a TLS-based straw-man would *not* — documents why ScopedValues, Julia-conv 6).
6. **Region-exit traces owned-only.** A region that allocates 2 locals and returns 1: exit traces exactly the
   1 unconsumed local; a *borrowed* view (M4 precursor) traces nothing; consumed wires skipped.
7. **Trace-timing invariance.** Two spellings — helper inherits the enclosing region vs helper opens its own
   `region()` — give **statistically equal** results (N≥1000, ±3σ) on a probe circuit. (§3.9 no-backaction.)
8. **Seeded-tests-never-assert-trace-placement (policy test).** With a fixed-seed RNG, assert *statistics*
   match a reference but do **not** assert RNG-stream identity or trace position — encoding the §3.9 corollary
   as an executable guard against a future test author pinning the stream.
9. **§8.4 aliasing regression hook.** `apply!(ctx, cx_value, (w, w))` (same wire as control and target) errors
   at the DSL level with **register identity** in the message (WireID, not raw "got 0, 0") — *before* the FFI
   `_check_distinct` shim fires. (Defect ledger §8.4; CLAUDE.md Orkan-FFI note.)
10. **FFI guard tests.** Each guard (`_check_qubit` out-of-range, NULL data, `_check_distinct`, `channel_1q`
    on PURE, OOM-after-alloc) raises a Julia `error()` — proving no path reaches Orkan's `exit()` (AUDIT §5).
11. **OMP ceiling.** `__init__` sets `OMP_NUM_THREADS ≤ 16` when unset, leaves a user value untouched (§1.5).

---

## 6. Namespace / files (plan §M2, Julia-conv 8)

```
src/orkan/ffi.jl      # raw ccall wrappers + guards + loader + __init__ OMP;  ALL internal
src/orkan/state.jl    # OrkanState handle wrapper, bulk unsafe_wrap read;     internal
src/orkan/ad.jl       # Ad application: ZYZ, ABC, multi-control, Perm replay; internal (grep-lint target)
src/context/abstract.jl  # AbstractContext + interface + live_wires;          public: AbstractContext
src/context/eager.jl     # EagerContext;                                       public: EagerContext, eager
src/context/density.jl   # DensityMatrixContext (minimal);                     public: DensityMatrixContext, density
src/context/regions.jl   # @context, region(), ptrace!, CURRENT_CONTEXT SV;    export: @context, region, ptrace!
```
- **Exported** (surface, `using Sturm`): `@context`, `region`, `ptrace!` (region vocabulary is user-facing).
- **`public`** (reachable as `Sturm.X`, not dumped): `EagerContext`, `DensityMatrixContext`, `eager`,
  `density`, `AbstractContext`, `current_context`, `apply!`, `allocate!`.
- **Internal** (unmarked): the whole `orkan/` layer, `q`, `wire_to_qubit`, the guards, ZYZ/ABC internals —
  no user or library author reaches these; the FFI is not a language (P5).
- **Grep-lints (boot, plan §M1 pattern):** `single_from_mat` appears **nowhere** in `src/`; `orkan_cx` /
  `controlled` tokens appear only under `src/kernel/` + `src/orkan/`; `ccall` appears only under `src/orkan/`.

---

## Appendix — physics/audit citations used
- **AUDIT §1–§9** (`docs/design/orkan-abi-audit-m2.md`): ABI inventory, D7-by-storage, exit()-error model,
  no-RNG, OMP-only threading, `single_from_mat` risk, loader order.
- **PRD-v2 §3.9** — scope = Stinespring boundary; silent trace; regions-not-GC; ScopedValues; reset-on-recycle.
- **PRD-v2 §4.1/§4.3** — U2 numerics, double cover, ZYZ once at the boundary, chart singularity confined here;
  Ad = adjoint rep, phase quotient crossed once.
- **PRD-v2 §4.2/§4.4** — ctrl homomorphism, single choke point; measurement-under-ctrl unrepresentable.
- **M1 kernel** — `u2.jl` (denoted convention, Hamilton product), `ctrl.jl` (Ctrl block phase, no-catch-all),
  `perm.jl` (MCX, wire 1 = MSB), `constants.jl` (Rz/Ry/p denotations, gphase).
- `docs/physics/wharton_koch_quaternion_bloch.md`, `stuelpnagel_1964_rotation_parametrization.md`,
  `tang_wright_2025_controlled_unitaries.md`, `delorme_control_as_constructor.md` (cited by M1, carried).
- **Orkan source** (`gate_pure.c` `stride=1<<target`) — the little-endian pin, confirmed read-only.
- Nielsen–Chuang §4.3 (ABC / C²(U) constructions); Barenco et al. 1995 (MCX ancilla horizon).
