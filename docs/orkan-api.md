# Orkan C Library — API Reference for Sturm.jl FFI

Library: `liborkan.so` (always shared, no static target)
Built binary: `../orkan/cmake-build-release/src/liborkan.so`
Headers: `../orkan/include/{qlib.h, q_types.h, state.h, gate.h, channel.h}`

---

## 1. Primitive Types

| C typedef | C type | Julia type | Size | Notes |
|-----------|--------|------------|------|-------|
| `qubit_t` | `unsigned char` | `UInt8` | 1 byte | Qubit index, 0-based, max 255 |
| `cplx_t` | `double _Complex` | `ComplexF64` | 16 bytes | C99 complex, ABI-compatible |
| `idx_t` | `uint64_t` | `UInt64` | 8 bytes | Array index / dimension |

## 2. Enums

### `state_type_t`

```c
typedef enum { PURE = 0, MIXED_PACKED = 1, MIXED_TILED = 2 } state_type_t;
```

Julia: `Cint`. Constants: `PURE = Cint(0)`, `MIXED_PACKED = Cint(1)`, `MIXED_TILED = Cint(2)`.

### `qs_error_t`

```c
typedef enum {
    QS_OK = 0, QS_ERR_NULL = -1, QS_ERR_OOM = -2, QS_ERR_QUBIT = -3,
    QS_ERR_TYPE = -4, QS_ERR_FILE = -5, QS_ERR_FORMAT = -6, QS_ERR_PARAM = -7
} qs_error_t;
```

Currently unused by any public function. Reserved for future use.

## 3. Structs

### `state_t` (24 bytes, x86-64 SysV ABI)

```c
typedef struct {
    state_type_t type;    // offset 0, 4 bytes (Cint)
    // 4 bytes padding
    cplx_t      *data;    // offset 8, 8 bytes (Ptr{ComplexF64})
    qubit_t      qubits;  // offset 16, 1 byte (UInt8)
    // 7 bytes padding
} state_t;
```

Julia struct (must match 24-byte layout):
```julia
mutable struct OrkanState
    type::Cint              # 0: PURE, 1: MIXED_PACKED, 2: MIXED_TILED
    _pad1::UInt32           # explicit padding
    data::Ptr{ComplexF64}   # 64-byte aligned, owned
    qubits::UInt8           # number of qubits
    _pad2::NTuple{7,UInt8}  # trailing padding
end
```

**Memory ownership:** `data` is owned by the struct after `state_init`. Always free via `state_free`, never `free(data)` directly. `state_free` does NOT free the struct itself.

### `kraus_t` (24 bytes)

```c
typedef struct {
    qubit_t  n_qubits;   // offset 0, 1 byte
    // 7 bytes padding
    uint64_t n_terms;    // offset 8, 8 bytes
    cplx_t  *data;       // offset 16, 8 bytes — row-major Kraus matrices
} kraus_t;
```

Data layout: `n_terms` matrices, each `(2^n_qubits)^2` elements, **row-major**.
Caller owns `data`. Library reads but does not free it.

### `superop_t` (16 bytes)

```c
typedef struct {
    qubit_t  n_qubits;   // offset 0, 1 byte
    // 7 bytes padding
    cplx_t  *data;       // offset 8, 8 bytes — (2^n)^2 x (2^n)^2 matrix, row-major
} superop_t;
```

Allocated by `kraus_to_superop`. Caller must `free(sop.data)`.

## 4. State API

### `state_init`
```c
void state_init(state_t *state, qubit_t qubits, cplx_t **data);
```
- `state->type` MUST be set before calling
- `data == NULL` or `*data == NULL`: allocates 64-byte-aligned zeroed storage
- `*data != NULL`: ownership transfer, `*data` set to NULL after call
- If `state->data` was non-NULL, it is freed first (safe to reinitialize)
- On OOM: `state->data = NULL`, `state->qubits = 0` (no exit)

### `state_free`
```c
void state_free(state_t *state);
```
- Frees `state->data`, sets `data = NULL`, `qubits = 0`
- Safe on NULL state. Idempotent (safe to call multiple times)
- Does NOT free the `state_t` struct itself

### `state_plus`
```c
void state_plus(state_t *state, qubit_t qubits);
```
- PURE: all amplitudes = `1/sqrt(2^n)`
- MIXED: all elements = `1/2^n`
- Calls `state_init` internally (frees old data)

### `state_cp`
```c
state_t state_cp(const state_t *state);
```
- Deep copy, returns by value (24 bytes, hidden pointer on x86-64)
- Independently owned `data`. Both source and copy must be freed
- On OOM: returns with `data == NULL`

### `state_len`
```c
idx_t state_len(const state_t *state);
```
- PURE: `2^n`
- MIXED_PACKED: `dim*(dim+1)/2`
- MIXED_TILED: `(n_tiles*(n_tiles+1)/2) * TILE_SIZE`

### `state_get` / `state_set`
```c
cplx_t state_get(const state_t *state, idx_t row, idx_t col);
void   state_set(state_t *state, idx_t row, idx_t col, cplx_t val);
```
- PURE: `col` ignored (must be 0)
- MIXED: Hermitian symmetry — upper triangle returns/stores conjugate
- Asserts on NULL/out-of-range (abort in debug, UB in release)

### `state_print`
```c
void state_print(const state_t *state);
```
Diagnostic only. Prints to stdout.

## 5. Gate API

All gates: `void`, mutate `state_t` in-place, dispatch on `state->type`.

**Error handling: `exit(EXIT_FAILURE)` on invalid input.** Validate in Julia before calling.

### 1-qubit (no parameter)
```c
void x(state_t *state, qubit_t target);     // Pauli-X
void y(state_t *state, qubit_t target);     // Pauli-Y
void z(state_t *state, qubit_t target);     // Pauli-Z
void h(state_t *state, qubit_t target);     // Hadamard
void s(state_t *state, qubit_t target);     // S = sqrt(Z)
void sdg(state_t *state, qubit_t target);   // S-dagger
void t(state_t *state, qubit_t target);     // T = sqrt(S)
void tdg(state_t *state, qubit_t target);   // T-dagger
void hy(state_t *state, qubit_t target);    // Hadamard-Y
```

### 1-qubit rotation (theta in radians)
```c
void rx(state_t *state, qubit_t target, double theta);  // exp(-i theta/2 X)
void ry(state_t *state, qubit_t target, double theta);  // exp(-i theta/2 Y)
void rz(state_t *state, qubit_t target, double theta);  // exp(-i theta/2 Z)
void p(state_t *state, qubit_t target, double theta);   // Phase gate P(theta)
```

### 2-qubit
```c
void cx(state_t *state, qubit_t control, qubit_t target);  // CNOT
void cy(state_t *state, qubit_t control, qubit_t target);  // Controlled-Y
void cz(state_t *state, qubit_t control, qubit_t target);  // Controlled-Z
void swap_gate(state_t *state, qubit_t q1, qubit_t q2);    // SWAP
```
Constraint: `control != target` / `q1 != q2` (enforced via exit).

### 3-qubit
```c
void ccx(state_t *state, qubit_t c1, qubit_t c2, qubit_t target);  // Toffoli
```
All three must be distinct.

## 6. Channel API

### `kraus_to_superop`
```c
superop_t kraus_to_superop(const kraus_t *kraus);
```
- Returns `superop_t` by value (16 bytes, in registers on x86-64)
- `sop.data` is `calloc`'d — caller must `free(sop.data)`
- Exits on NULL input or OOM

### `channel_1q`
```c
void channel_1q(state_t *state, const superop_t *sop, qubit_t target);
```
- **MIXED_PACKED and MIXED_TILED only.** Exits on PURE state.
- `sop->n_qubits` must be 1

## 7. Error Handling Summary

| Function | On bad input |
|----------|-------------|
| `state_init` | Returns with `data=NULL` (recoverable) |
| `state_cp` | Returns with `data=NULL` (recoverable) |
| `state_len/get/set` | `assert()` — abort in debug, UB in release |
| All gates | `exit(EXIT_FAILURE)` — **process dies** |
| `channel_1q` | `exit(EXIT_FAILURE)` |
| `kraus_to_superop` | `exit(EXIT_FAILURE)` |

**Julia rule: validate ALL inputs before ccall. Never let Orkan see bad data.**

## 8. No `measure()` Function

Orkan has no measurement function. "Measurement" means:
- PURE: read `|state.data[i]|^2` for probabilities, sample in Julia
- MIXED: read diagonal `state_get(state, i, i)` for probabilities, sample in Julia

Sturm.jl implements measurement sampling in Julia, reading probabilities from Orkan state data.

## 9. Build Info

- Library: `liborkan.so.0.1.0` (SONAME `liborkan.so.0`)
- Release binary: `../orkan/cmake-build-release/src/liborkan.so` (328 KB)
- Dependencies: `libm`, `libgomp` (OpenMP), `libc`
- Compiled with `-march=native` — not portable across CPU generations
- `LOG_TILE_DIM=5` (release) → `TILE_DIM=32`, `TILE_SIZE=1024`
- No struct packing pragmas. Standard System V AMD64 ABI
