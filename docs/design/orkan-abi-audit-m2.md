# Orkan C ABI Audit for Sturm.jl v2 — Milestone M2 (FFI + contexts + regions)

**Date:** 2026-07-10
**Scope:** current Orkan headers/source at `/home/tobias/Projects/orkan` vs
Sturm v2 M2 needs vs v0.1's deprecated FFI layer. Read-only; nothing built or run.
**Purpose:** feed the M2 3+1 design round; resolve PRD-v2 decision **D7**.

Headers audited (the ONLY truth per CLAUDE.md / plan §6 risk 2):
`include/q_types.h`, `state.h`, `gate.h`, `channel.h`, `qlib.h` (umbrella).
Sources consulted to disambiguate semantics: `src/gate/gate.c`,
`src/gate/tiled/gate_tiled.h`, `src/gate/tiled/gate_tiled_1q.c`,
`src/channel/channel.c`, `src/state/state.c`, `CMakeLists.txt`, `CMakePresets.json`.
Exported-symbol truth cross-checked with `nm -D` on the built
`cmake-build-release/src/liborkan.so` (SONAME `liborkan.so.0`, LOG_TILE_DIM=5).

---

## 0. Headline results

1. **D7 is effectively decided by the storage model, not by benchmarking.**
   On the **PURE statevector** path (the EagerContext primary path), Orkan
   exposes **NO** general-1q-unitary entry — no matrix, no quaternion. The
   only universal single-qubit route on pure states is the **Euler chart**:
   named gates + `rz`/`ry`/`rz` + `p` (phase). A general-matrix entry
   (`single_from_mat`) *does* exist and *is* exported, but it is implemented
   **only for MIXED_TILED density-matrix storage** (`ρ' = UρU†`) — calling it
   on a PURE state would index tiled offsets into a flat statevector and
   corrupt memory. So: ZYZ-decomposition for pure; matrix-entry available
   (bonus) for the DM context.

2. **Every v0.1 ccall shape survives.** All 24 distinct C entry points the
   v0.1 `ffi.jl` bound are still present with identical signatures and struct
   layouts. Verdict: **24/24 VERIFIED-STILL-CURRENT, 0 DRIFTED, 0 REMOVED.**
   The ABI has not drifted since v0.1 was written.

3. **No measurement / sampling / RNG anywhere in the C API.** v0.1 did all
   sampling Julia-side (`rand()` cumulative over `state_get`). This is
   unchanged and is the correct model: **Julia owns reproducibility**
   (`Random.seed!` / a seeded RNG), Orkan owns only linear algebra.

4. **Biggest M2 risk:** the general-1q matrix entry point is a *tiled-DM-only,
   header-private* symbol whose correctness silently depends on the compiled
   `LOG_TILE_DIM` (baked to 5 in the release `.so`). It is undeclared in
   `include/`, so it is not part of the stable ABI contract and could vanish
   or change shape without a header diff — exactly the "ABI drift" the risk
   register warns about, but for a symbol the headers don't even acknowledge.
   See §8.

---

## 1. Inventory — exact signatures (from `include/`, confirmed against `.so`)

### Error codes (`q_types.h`)
```c
typedef enum {
  QS_OK=0, QS_ERR_NULL=-1, QS_ERR_OOM=-2, QS_ERR_QUBIT=-3,
  QS_ERR_TYPE=-4, QS_ERR_FILE=-5, QS_ERR_FORMAT=-6, QS_ERR_PARAM=-7
} qs_error_t;
```
Scalar typedefs:
```c
typedef unsigned char   qubit_t;   // 1 byte — qubit index
typedef double _Complex cplx_t;    // ComplexF64, BLAS-ABI-compatible
typedef uint64_t        idx_t;     // dim/index (UInt64)
```
**Note:** the `qs_error_t` enum is *defined* but **no gate/state/channel
function returns it** — see §5. It is currently decorative.

### State (`state.h`) — struct + 8 functions
```c
typedef enum state_type { PURE, MIXED_PACKED, MIXED_TILED } state_type_t; // 0,1,2
typedef struct state {
  state_type_t type;   // enum (4 bytes) + 4 pad
  cplx_t      *data;   // 8 bytes
  qubit_t      qubits; // 1 byte + 7 pad
} state_t;             // 24 bytes on x86-64

idx_t   state_len (const state_t *state);
void    state_init(state_t *state, qubit_t qubits, cplx_t **data); // data NULL => zero-alloc; else ownership transfer
void    state_free(state_t *state);                                // NULL-safe, idempotent
void    state_plus(state_t *state, qubit_t qubits);                // |+>^n (PURE) / maximally-mixed (MIXED)
state_t state_cp  (const state_t *state);                          // deep copy BY VALUE; data==NULL on OOM
void    state_print(const state_t *state);
cplx_t  state_get (const state_t *state, idx_t row, idx_t col);    // PURE: data[row], col ignored; MIXED: ρ[row,col] w/ Hermitian symmetry
void    state_set (state_t *state, idx_t row, idx_t col, cplx_t val);
```
Also exported (per-type internals, not in headers — do NOT bind): `state_pure_*`,
`state_packed_*`, `state_tiled_*` (`_get/_set/_len/_plus/_print`).

### Gates (`gate.h`) — 22 functions, all `void`, index-validated, `exit()` on bad input
```c
// 1q, no param:
void x,y,z,h,s,sdg,t,tdg,hy (state_t*, qubit_t target);
// 1q rotations (radians):
void rx,ry,rz,p (state_t*, qubit_t target, double theta);
// 2q:
void cx,cy,cz (state_t*, qubit_t control, qubit_t target);
void swap_gate(state_t*, qubit_t q1, qubit_t q2);              // NB name is swap_gate, not swap
// 3q:
void ccx(state_t*, qubit_t ctrl1, qubit_t ctrl2, qubit_t target);
```
All dispatch three ways (PURE/PACKED/TILED) internally via `gate.c`.

### General-matrix entries — EXPORTED but NOT in `include/`
```c
// declared only in src/gate/tiled/gate_tiled.h (internal); TILED-DM ONLY (ρ'=UρU†)
void single_from_mat(state_t *state, qubit_t target, const cplx_t *mat);        // mat = 2x2 COL-MAJOR
void two_from_mat   (state_t *state, qubit_t q1, qubit_t q2, const cplx_t *mat); // mat = 4x4
```
`single_from_mat` reads `mat[0]=U00, mat[1]=U10, mat[2]=U01, mat[3]=U11`
(column-major). It assumes `state->type == MIXED_TILED` — it indexes tile
offsets directly, no dispatcher, no validation. **Unsafe on PURE/PACKED.**

### Channels (`channel.h`) — Kraus/superop, DM only
```c
typedef struct { qubit_t n_qubits; uint64_t n_terms; cplx_t *data; } kraus_t;   // 24 bytes; data = n_terms Kraus mats, ROW-MAJOR concat
typedef struct { qubit_t n_qubits;                    cplx_t *data; } superop_t; // 16 bytes; ROW-MAJOR
superop_t kraus_to_superop(const kraus_t *kraus);                 // callee calloc's out.data (free via libc free)
void      channel_1q(state_t *state, const superop_t *sop, qubit_t target); // requires sop->n_qubits==1; EXITS on PURE state
```
Internal (exported, not in headers): `channel_packed_1q`, `channel_tiled_1q`
`(state_t*, const cplx_t *sop, qubit_t target)`.

---

## 2. D7 answer — general 1q entry vs Euler triples

**The current API exposes BOTH shapes, but they live on disjoint storage
models, so there is no benchmark trade-off to run for the pure path:**

| Path (context)                  | General 1q entry            | Euler / named-gate entry            |
|---------------------------------|-----------------------------|-------------------------------------|
| **PURE statevector** (Eager)    | **NONE** (no matrix, no quat)| `x,y,z,h,s,sdg,t,tdg,hy,rx,ry,rz,p` |
| **MIXED_TILED** (DensityMatrix) | `single_from_mat` (2x2 mat) | same named gates + rotations        |
| **MIXED_PACKED**                | **NONE**                    | same named gates + rotations        |

Consequences for M2's Ad-application lowering (`U2 → Orkan`):

- **EagerContext (pure) must lower `U2` through the ZYZ Euler chart**:
  `U2` quaternion → `(α, β, γ)` Euler angles → `rz(γ); ry(β); rz(α)` (+ the
  U(2) phase handled by `p` or dropped on the uncontrolled path per PRD §4.3).
  This is **3 ccalls per 1q application** on pure states — there is no
  1-call alternative available, so D7's "measure both" reduces to "there is
  only one option; measure its cost for the record."
- **DensityMatrixContext MAY use `single_from_mat`** as a 1-call path (feed
  the 2x2 `U` column-major) — *if* M2 elects to bind the header-private
  symbol and pin `LOG_TILE_DIM`. Otherwise it too uses ZYZ. This is the only
  place a genuine 1-vs-3 benchmark exists, and it only matters for the DM
  path (not the primary Eager path).

**Where the ZYZ θ≈0/π singularity handling lives:** at the FFI boundary in
`src/orkan/`, in the `U2 → (α,β,γ)` extraction — exactly as PRD §4.1 / D7
mandate ("this boundary and only here"). Because pure states have no matrix
entry, this branch is **unavoidable and load-bearing** on the primary path:
when `β≈0` or `β≈π` the z-rotation split is ill-conditioned and the code
must fold the two `rz` angles into a single well-defined `rz`+phase. It
cannot be sidestepped by "just pass the matrix" (that escape hatch only
exists for tiled DM). Write it once here; test it at θ∈{0, π, ±ε}.

---

## 3. Controlled ops — what Orkan does natively

| Construct                         | Native Orkan? | Symbol            |
|-----------------------------------|---------------|-------------------|
| Controlled-X (CNOT)               | **yes**       | `cx`              |
| Controlled-Y                      | **yes**       | `cy`              |
| Controlled-Z                      | **yes**       | `cz`              |
| SWAP                              | yes           | `swap_gate`       |
| Toffoli (CCX, 2-control X)        | **yes**       | `ccx`             |
| Arbitrary controlled-1q (`C-U`)   | **NO**        | —                 |
| Controlled rotations (CRz, etc.)  | **NO**        | —                 |
| Multi-controlled (≥3 ctrl), MCX   | **NO**        | —                 |
| Controlled-`single_from_mat`      | **NO**        | —                 |

**Story for the kernel's `ctrl` choke point (Sturm's single controlled-lowering
site, plan §M1):** Orkan gives exactly four controlled primitives — CX, CY, CZ,
CCX. Everything richer must be **decomposed kernel-side** and lowered to those
+ the 1q Euler gates:

- `Ctrl{U2}` (single control, arbitrary 1q) → standard ABC decomposition:
  `U = e^{iα} A X B X C` with `ABC=I`, controlled via `cz`/`cx` sandwich →
  `p` (phase) + `ry`/`rz` + `cx`. No native C-U shortcut exists.
- `Ctrl{Ctrl{U2}}` / MCX / MCU → decompose to CX/CCX + ancilla (Toffoli
  ladder) or the standard multi-control constructions; Orkan tops out at CCX.
- `Ctrl{Perm}` → the v2 Perm "prepend control to every instruction" rule
  (plan §M1) lowers to `cx`/`ccx` replay directly — this is the clean case.

This is precisely why the plan makes `ctrl` the **single choke point** with a
CI grep-lint (`orkan_cx|controlled` only under `src/kernel/` + `src/orkan/`):
Orkan's controlled vocabulary is small, so all the decomposition intelligence
must live in one auditable place. The FFI shim only exposes the four native
controlled ccalls; the kernel builds everything else on top.

---

## 4. Drift table — v0.1 ccall shape vs current header

Struct layouts (v0.1 `OrkanStateRaw`/`OrkanKrausRaw`/`OrkanSuperopRaw`) match
the current C structs byte-for-byte (24/24/16 bytes, x86-64). All function
signatures identical.

| v0.1 wrapper (`ffi.jl`)        | C symbol            | Current signature match | Verdict |
|--------------------------------|---------------------|-------------------------|---------|
| `orkan_state_init!`            | `state_init`        | `(state_t*, qubit_t, cplx_t**)` | **VERIFIED** |
| `orkan_state_free!`            | `state_free`        | `(state_t*)`            | **VERIFIED** |
| `orkan_state_plus!`            | `state_plus`        | `(state_t*, qubit_t)`   | **VERIFIED** |
| `orkan_state_len`              | `state_len`         | `(const state_t*)->idx_t` | **VERIFIED** |
| `orkan_state_get`              | `state_get`         | `(const state_t*, idx_t, idx_t)->cplx_t` | **VERIFIED** |
| `orkan_state_set!`             | `state_set`         | `(state_t*, idx_t, idx_t, cplx_t)` | **VERIFIED** |
| `Base.copy` (inline ccall)     | `state_cp`          | `(const state_t*)->state_t` (by value) | **VERIFIED** |
| `orkan_x!`…`orkan_hy!` (9)     | `x,y,z,h,s,sdg,t,tdg,hy` | `(state_t*, qubit_t)` | **VERIFIED** (9/9) |
| `orkan_rx!`…`orkan_p!` (4)     | `rx,ry,rz,p`        | `(state_t*, qubit_t, double)` | **VERIFIED** (4/4) |
| `orkan_cx!`,`orkan_cy!`,`orkan_cz!` | `cx,cy,cz`     | `(state_t*, qubit_t, qubit_t)` | **VERIFIED** (3/3) |
| `orkan_swap!`                  | `swap_gate`         | `(state_t*, qubit_t, qubit_t)` | **VERIFIED** (name = `swap_gate`) |
| `orkan_ccx!`                   | `ccx`               | `(state_t*, qubit_t×3)` | **VERIFIED** |
| `orkan_kraus_to_superop`       | `kraus_to_superop`  | `(const kraus_t*)->superop_t` | **VERIFIED** |
| `orkan_channel_1q!`            | `channel_1q`        | `(state_t*, const superop_t*, qubit_t)` | **VERIFIED** |
| `orkan_superop_free!`          | *(none — libc free)*| callee `calloc`s `out.data`; free via `Libc.free` | **VERIFIED** (no Orkan free fn; libc free correct) |

**0 drifted, 0 removed.** The only *additions* since v0.1 are `single_from_mat`
and `two_from_mat` (general-matrix, tiled DM) and the per-type internal
`state_*_*` / `channel_*_1q` symbols — none of which v0.1 bound.

---

## 5. Error / ownership conventions — bears on region cleanup

- **Ownership.** `state_init`/`state_plus` allocate `state->data` (aligned
  alloc; `state.c`). `state_free` frees it (NULL-safe, idempotent). `state_cp`
  returns a fresh deep copy by value (caller owns the returned struct's
  `data`, frees via `state_free`). `kraus_to_superop` `calloc`s `out.data` —
  **there is no `superop_free`**; free it with libc `free` (v0.1 did exactly
  this via `Libc.free`). `kraus_t.data` is caller-owned (Julia buffer,
  `GC.@preserve` around the ccall). **Model: Julia allocates the struct
  shells, Orkan allocates the data buffers, Julia frees them via the matching
  Orkan/libc free.** This maps cleanly onto M2's region model: the context
  owns each `state_t`, and deterministic region exit (`try/finally`, not GC
  finalizers) calls `state_free`. v0.1's finalizer-based `OrkanState` is the
  *anti-pattern* the plan replaces (sv3 prior art) — keep the free, drop the
  finalizer, drive it from the region.

- **Error style = FATAL, not return codes.** This is the sharp edge. Despite
  the `qs_error_t` enum existing, **gates/channels return `void` and call
  `exit(EXIT_FAILURE)`** on bad input via the `GATE_VALIDATE`/`CHANNEL_VALIDATE`
  macros (`gate.c` §Error handling; `channel.c`). A bad qubit index or NULL
  state **kills the whole Julia process** with no recoverable signal. v0.1
  learned this twice the hard way (beads `Sturm.jl-1oy`, `-1oy` channel
  omission): **every wrapper must validate Julia-side BEFORE the ccall** —
  range-check the qubit against `state.qubits`, check `data != C_NULL`, check
  distinctness for 2q/3q, check `sop->n_qubits==1` and non-PURE for
  `channel_1q`. Re-port v0.1's `_check_qubit`/`_check_distinct`/
  `_check_distinct3` guards verbatim. This is also where PRD §8.4 DSL-level
  aliasing checks fire (before the FFI shim), per CLAUDE.md.

- **State allocation failure is silent-ish:** `state_init`/`state_plus` on OOM
  print to stderr and leave `data == NULL`. v0.1 checked `state.data == C_NULL`
  after the call and `error()`ed. Keep that.

---

## 6. Measurement / sampling / RNG

- **The C API has NONE.** No `measure`, `sample`, `collapse`, `probabilities`,
  `expect`, `rand`, or `seed` symbol exists in headers or in the `.so`
  (verified via `nm -D`). This is by design: Orkan is a state-evolution engine.
- **v0.1 did it all Julia-side:** `probabilities(s)` = `abs2(state_get(i,0))`
  over PURE, or `real(state_get(i,i))` over MIXED; `sample(s)` = inverse-CDF
  over `rand()`. **RNG is Julia's `Random`**, so **seeded reproducibility is
  purely a Julia concern** — `Random.seed!` / a `StableRNG` passed through the
  context gives deterministic tests. Orkan need not (and cannot) be seeded.
- **Cost note for M2:** `sample`/`probabilities` are `O(2^n)` FFI round-trips
  through `state_get` (one ccall per amplitude). v0.1 flagged 16 MB/call
  allocation at n=20 and moved to an allocation-free cumulative scan (bead
  `Sturm.jl-5z3r`). For M2's measurement casts and the Choi harness, consider
  reading `state->data` as a single `unsafe_wrap`'d array (the pointer and
  `state_len` are exposed) instead of per-element `state_get` — big constant
  win, and it sidesteps the per-call ccall overhead. (PURE data is a flat
  `2^n` vector; MIXED packed/tiled storage is triangular — use `state_get`'s
  Hermitian-aware accessor there, or replicate the layout.)

---

## 7. OpenMP / threading

- **No thread-config API.** No `omp_set_num_threads` or equivalent is exported.
  Threading is controlled **only** via the `OMP_NUM_THREADS` environment
  variable (Orkan links `OpenMP::OpenMP_C`, `ENABLE_OPENMP=ON` by default).
- **M2 must set `OMP_NUM_THREADS` in `__init__`** (not top-level — precompile
  vs load-time), as v0.1 did (`_set_omp_threads!`, capping to `CPU_THREADS÷4`
  to avoid oversubscription against Julia's own threads). Project memory notes
  the device limit is `OMP_NUM_THREADS=16`; honor that as the ceiling.
- OpenMP only kicks in above `OMP_THRESHOLD` (per-file default 512, i.e. n≥9);
  small-register law tests run serial regardless.
- **Determinism caveat:** OpenMP reduction/summation order can perturb
  floating-point results run-to-run. Law tests compare with `≈` (PRD §4.1),
  so this is fine — but do **not** assert bit-exact amplitudes across runs.

---

## 8. Gaps — what M2 needs that Orkan lacks

1. **General 1q unitary on PURE states — ABSENT.** The primary Eager path has
   no matrix/quaternion entry; `U2` application MUST go through ZYZ (3 ccalls
   + the θ≈0/π branch). Not a blocker (ZYZ is complete), but it fixes D7 and
   means the singularity handling is on the hot path, not optional.

2. **Arbitrary controlled-1q, controlled-rotations, and multi-controlled
   (≥3 ctrl) gates — ABSENT.** Only CX/CY/CZ/CCX are native. `Ctrl{U2}`,
   MCX, and MCU require **kernel-side decomposition** (ABC / Toffoli ladders)
   lowered to the four native controlled ccalls + Euler 1q. This is expected
   and is exactly what the `ctrl` choke point is for — but it means M1's
   `Ctrl{V}` lowering does real work; Orkan is not going to shortcut it.

3. **Measurement / sampling / RNG — ABSENT (by design).** M2 implements these
   Julia-side with a seeded RNG. Prefer bulk `unsafe_wrap` over per-amplitude
   `state_get` for the O(2^n) scans.

4. **`channel_1q` is DM-only and PACKED/TILED-only** (`exit()`s on PURE, and
   there is no `channel_packed`/`_tiled` dispatch for >1 qubit). Multi-qubit
   channels are NOT natively supported — only 1-local superoperators. M2's
   minimal DensityMatrix context and the eventual Choi harness must build
   multi-qubit channel action from Kraus/superop themselves or restrict to
   1-local. (Plan §6 already caps Choi at 15 wires under the 30-qubit sim cap.)

5. **`single_from_mat`/`two_from_mat` are header-private, tiled-only, and
   `LOG_TILE_DIM`-coupled (baked to 5 in the release `.so`).** If M2 wants the
   1-call DM path, it binds an *undeclared* symbol whose ABI the headers don't
   guarantee and whose correctness depends on a compile-time tile constant.
   **This is the single biggest M2 risk** — it is "Orkan ABI drift" (plan §6
   risk 2) at its worst: a symbol that can change or disappear with *no header
   diff to detect it*. Recommendation: for M2, **lower everything (pure AND
   DM) through the public named-gate + ZYZ vocabulary**; treat
   `single_from_mat` as a future optimization gated behind (a) a request to
   Orkan to promote it into `include/gate.h` with a PURE/PACKED dispatcher,
   and (b) a runtime assertion that the linked `LOG_TILE_DIM` matches. Do not
   let a header-private symbol onto the critical path.

6. **No error return codes in practice.** `qs_error_t` exists but is unused by
   the callable surface; all failure is `exit()`. M2's fail-fast guards must
   be Julia-side and exhaustive — a missed guard is a process kill, not an
   exception (CLAUDE.md principle 1 / v0.1 beads `-1oy`, `-5z3r`).

---

## 9. Library location & build (for the FFI loader)

- Built artifact: `/home/tobias/Projects/orkan/cmake-build-release/src/liborkan.so`
  (`→ .so.0 → .so.0.1.0`, SONAME `liborkan.so.0`). Release preset: `LOG_TILE_DIM=5`
  (TILE_DIM=32), OpenMP ON, OpenBLAS backend.
- v0.1 loader search order (re-port for M2, it still works):
  1. `ENV["LIBORKAN_PATH"]`
  2. `joinpath(@__DIR__, "..","..","..","orkan","cmake-build-release","src","liborkan.so")`
     (sibling-repo release build — matches the actual layout here)
  3. `"liborkan"` via `dlopen` (system-installed)
  Errors loudly with build instructions if none resolve. `InterruptException`
  must rethrow during `dlopen` probing (v0.1 bead `Sturm.jl-011f`).
- Build to reproduce: `cd ../orkan && cmake --preset release && cmake --build cmake-build-release`.
