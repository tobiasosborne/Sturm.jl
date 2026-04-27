# Code Review: Area 1 — Core types, context, control, gates

**Reviewer agent:** Sonnet (read-only pass; subagent could not Write to disk; this is the inlined summary)
**Date:** 2026-04-27
**Scope:** `src/Sturm.jl`, `src/types/`, `src/context/`, `src/control/`, `src/gates.jl`

## Severity Counts

| Severity | Count |
|---|---|
| P0 | 3 |
| P1 | 11 |
| P2 | 18 |
| P3 | 5 |
| **Total** | **37** |

## Top P0/P1 findings (5 most critical, returned by agent)

### P0-A1.1 — `src/types/wire.jl` — non-atomic wire counter
`_wire_counter = Ref{UInt32}(0)`; `fresh_wire!` does `_wire_counter[] += 1`. Under Julia multi-threading, two tasks read the same value and produce identical `WireID`s. Silent state corruption, no assertion fires. (Sturm's stance on threading isn't fully documented; even single-threaded the assertion-free pattern is brittle. Mitigation: `Threads.Atomic{UInt32}` + `Threads.atomic_add!`.)

### P0-A1.2 — `src/types/qint.jl:20` — `classical_type` returns Int8 for all widths
`classical_type(::Type{<:QInt}) = Int8` regardless of `W`. Any path that routes through `classical_type` (rather than `_bennett_arg_type` from session-24B) compiles a Bennett reversible circuit with 8-bit shadow type for a 16-/32-/64-bit register. Upper bits silently discarded. Same bug in `QCoset`. The `bridge.jl` direct path was fixed in `Sturm.jl-q93` (session 24B); this slice's claim is that `classical_type` itself remains the wrong contract.

### P0-A1.3 — `src/context/density.jl` — `measure!` corrupts MIXED_PACKED upper triangle
`DensityMatrixContext.measure!` reset-to-|0⟩ iterates all `(r,c)` indices including the upper triangle via `ctx.orkan[r,c] = val`. In MIXED_PACKED format the upper-triangle setter may silently no-op or write to wrong memory, leaving the post-measurement state corrupted. Needs verification against orkan's MIXED_PACKED layout.

### P1-A1.1 — `src/context/density.jl` — `measure!` per-element FFI in O(4^n) loop
Same root cause as bead Sturm.jl-059 (already fixed for EagerContext). Catastrophic at n ≥ 6. Fix: `unsafe_wrap` over the packed buffer.

### P1-A1.2 — `src/control/cases.jl` — `_cases_dispatch(::TracingContext)` no try/finally
DAG swap is not exception-safe. Any exception inside `then()` or `else_()` leaves `ctx.dag` pointing at a partial branch vector, permanently corrupting the `TracingContext`.

## Status

The agent could not write the full per-file report to disk due to a permission denial on Write inside the subagent (bypass-permissions did not propagate). The 5-bullet summary above represents the most critical findings; the agent's full P2/P3 list (32 additional items) was not extracted before the agent terminated. Re-running the agent with explicit Write permission would recover them; alternatively, the cross-cutting concerns above are sufficient to file the most impactful beads.
