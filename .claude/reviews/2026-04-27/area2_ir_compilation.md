# Code Review: Area 2 — IR and compilation pipeline

**Reviewer agent:** Sonnet (read-only pass; subagent could not Write to disk; this is the inlined summary + finding table)
**Date:** 2026-04-27
**Scope:** `src/orkan/`, `src/channel/`, `src/passes/`, `src/bennett/`, `src/noise/`

## Severity Counts

| Severity | Count |
|----------|-------|
| P0 | 4 |
| P1 | 9 |
| P2 | 14 |
| P3 | 4 |
| **Total** | **31** |

## P0/P1 detailed findings (verified by orchestrator)

### P0-A2.1 — `src/bennett/bridge.jl:81` — NOTGate emits Ry(π), not X
```julia
@inline function _apply_bennett_gate!(ctx::AbstractContext, g::NOTGate,
                                       wm::Dict{WireIndex, WireID})
    apply_ry!(ctx, wm[g.target], π)   # comment claims "X gate" but Ry(π) = -iY
end
```
**VERIFIED** — bridge.jl line 4 even has the bug in the design comment: `NOTGate(t) → apply_ry!(ctx, t, π)     [X gate]`.

`Ry(π)` is `-iY`, not `X`. The two differ by global phase, which is irrelevant for unconditional gates but **becomes a relative phase** when Bennett's NOTGate runs inside `when(ctrl)` — exactly the Session 8 bug documented in CLAUDE.md "Global Phase and Universality". Every `oracle(f, q)` call inside `when(ctrl)` with `ctrl` in superposition produces wrong relative phase between the `ctrl=|0⟩` and `ctrl=|1⟩` branches. Invisible in any computational-basis test; corrupts every controlled oracle path. All tests in `test_bennett_integration.jl` are basis-only and will not catch this.

**Fix:** emit X via the Sturm two-primitive sequence (`q.φ += π; q.θ += π` or use `X!` / library X gate from `gates.jl`), not via raw `apply_ry!(ctx, t, π)`.

### P0-A2.2 — `src/noise/channels.jl` — `pointer(data)` without `GC.@preserve`
`_apply_kraus!` captures a raw Julia pointer into `OrkanKrausRaw` and calls into C with no `GC.@preserve`. The GC may collect `data` between pointer capture and the `ccall`, producing a dangling read that silently corrupts the density matrix. Zero `GC.@preserve` calls exist in the entire codebase (verified).

**Fix:** wrap the FFI call in `GC.@preserve data ...`.

### P0-A2.3 — `src/passes/deferred_measurement.jl:51,55` — RyNode(wire, π) labeled as "X gate"
```julia
push!(result, RyNode(wire, π))  # X gate
push!(result, RyNode(wire, π))  # X gate (undo)
```
**VERIFIED.** Same Y-vs-X error as P0-A2.1. The false-branch anti-control construction (`X · controlled_op · X`) uses `RyNode(wire, π)`. Any circuit with a non-empty `CasesNode` false-branch through `defer_measurements` produces a physically incorrect channel. The `defer_measurements` pass is the lowering for `cases(q, then, else_)` to controlled gates — it's a hot path for tracing-export workflows.

**Fix:** emit the textbook X — either `RzNode(wire, π)` then `RyNode(wire, π)` (composition giving det=−1), or introduce an `XNode` first-class atomic (bead `7pz` already covers this).

### P0-A2.4 — `src/orkan/ffi.jl:247` — `orkan_channel_1q!` missing `_check_qubit`
**VERIFIED.** Every other gate wrapper calls `_check_qubit` before the ccall (lines 154, 173, 186, 200, 201, 213, 214, 226, 227, 228). The file's own comment states Orkan calls `exit()` on bad qubit index, killing the Julia process. `orkan_channel_1q!` (line 247+) is the only wrapper that omits this guard. An OOB index in any noise channel call SIGABRT-kills Julia with no exception, no recoverable signal.

**Fix:** add `_check_qubit(state, target, :channel_1q)` before the ccall.

### P1-A2.1 — `src/bennett/bridge.jl` — `_QROM_LOOKUP_XOR_CACHE` unbounded
`oracle_table` has an LRU with cap 64 (bead `t1v`). The sibling `_QROM_LOOKUP_XOR_CACHE` for `qrom_lookup_xor!` is a plain `Dict` with no eviction. A Shor sweep accumulates one `ReversibleCircuit` per unique `(hash(data), Ccmul, W)` triple indefinitely; each circuit holds O(2^Ccmul) gates. OOMs Julia in long sessions.

### P1-A2.2 — `src/orkan/state.jl` — `sample()` allocates O(2^n) per call
`sample()` allocates a O(2ⁿ) probability vector per call; non-normalised path silent (returns last index without warning).

### P1-A2.3 — `src/channel/compose.jl` — `⊗` does not check wire-ID collisions
Silent aliasing if user composes two channels that share wire IDs (e.g. by accident from two independent `trace()` calls).

### P1-A2.4 — `src/channel/openqasm.jl` — Unchecked `map[]` in `_emit_node!(CasesNode)`
KeyError on orphaned classical-control wire reference. Should error with a useful message naming the missing wire.

### P1-A2.5 — `src/noise/channels.jl` — `depolarise!` p > 4/3 → NaN density matrix
No precondition check. `sqrt(negative)` → NaN propagates through the entire density matrix.

### P1-A2.6 — `src/bennett/bridge.jl` — `QuantumOracle.cache` per-instance unbounded Dict, not thread-safe.

### P1-A2.7 — `src/orkan/ffi.jl` — dlopen bare `catch` swallows `InterruptException`
User Ctrl+C during library load is silently absorbed.

### P1-A2.8 — `src/channel/pixels.jl` — `_draw_schedule_compact` defined in wrong file
Fragile include order; should live near its callers.

### P1-A2.9 — `src/passes/abstract.jl` — `registered_passes()` non-deterministic
Returns Dict iteration order. Pass execution order in `optimise(ch, :all)` becomes platform/run-dependent. Switch to ordered Vector or sort by Symbol name.

## Full P2/P3 finding table (31 total — see counts above)

| ID | File | Severity | Short description |
|----|------|----------|-------------------|
| P0-A2.1 | bridge.jl | P0 | NOTGate → Ry(π) = Y gate, not X |
| P0-A2.2 | noise/channels.jl | P0 | pointer(data) without GC.@preserve |
| P0-A2.3 | passes/deferred_measurement.jl | P0 | RyNode(wire,π) as "X gate" in false-branch |
| P0-A2.4 | orkan/ffi.jl | P0 | orkan_channel_1q! missing _check_qubit |
| P1-A2.1 | bridge.jl | P1 | _QROM_LOOKUP_XOR_CACHE unbounded Dict |
| P1-A2.2 | orkan/state.jl | P1 | sample() allocates O(2ⁿ) per call |
| P1-A2.3 | channel/compose.jl | P1 | ⊗ does not check wire-ID collisions |
| P1-A2.4 | channel/openqasm.jl | P1 | Unchecked map[] in _emit_node!(CasesNode) |
| P1-A2.5 | noise/channels.jl | P1 | depolarise! p > 4/3 → NaN |
| P1-A2.6 | bridge.jl | P1 | QuantumOracle.cache unbounded, not thread-safe |
| P1-A2.7 | orkan/ffi.jl | P1 | dlopen bare catch swallows InterruptException |
| P1-A2.8 | channel/pixels.jl | P1 | _draw_schedule_compact in wrong file |
| P1-A2.9 | passes/abstract.jl | P1 | registered_passes() non-deterministic |
| P2-A2.1 | channel/dag.jl | P2 | _ZERO_WIRE sentinel/allocator invariant undocumented |
| P2-A2.2 | passes/gate_cancel.jl | P2 | Dead _wires_of helpers — Set per call |
| P2-A2.3 | channel/trace.jl | P2 | trace(f, ::Val{W}) missing QBool return arm |
| P2-A2.4 | noise/classicalise.jl | P2 | classicalise silently single-qubit only |
| P2-A2.5 | channel/pixels.jl | P2 | _maybe_shadow_flanks! fires on gate rows |
| P2-A2.6 | channel/dag.jl | P2 | CasesNode abstract Vector eltype asymmetry |
| P2-A2.7 | channel/channel.jl | P2 | Backward-compat constructor double-pass |
| P2-A2.8 | passes/optimise.jl | P2 | :all hardcodes [deferred, cancel] — ignores user passes |
| P2-A2.9 | orkan/ffi.jl | P2 | OrkanKrausRaw/OrkanSuperopRaw mutability asymmetry |
| P2-A2.10 | channel/draw.jl | P2 | stacktrace(backtrace()) in render loop |
| P2-A2.11 | bridge.jl | P2 | oracle_table calls f(k::Int); oracle uses _bennett_arg_type(W) — latent MethodError |
| P2-A2.12 | orkan/state.jl | P2 | sample() non-normalised fallthrough returns last index |
| P2-A2.13 | passes/deferred_measurement.jl | P2 | strict=false silently skips un-lowerable patterns |
| P2-A2.14 | passes/deferred_measurement.jl | P2 | _add_control error message lacks circuit context |
| P3-A2.1 | passes/gate_cancel.jl | P3 | _barrier_wires(PrepNode) treatment unexplained |
| P3-A2.2 | channel/dag.jl | P3 | _ZERO_WIRE inline comment missing |
| P3-A2.3 | passes/abstract.jl | P3 | pass_name instance overload absent from docstring |
| P3-A2.4 | noise/classicalise.jl | P3 | Docstring should warn single-qubit limitation |
