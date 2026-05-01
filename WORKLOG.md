# Sturm.jl Work Log

Gotchas, learnings, decisions, and surprises. Updated every step.

> **Layout note for future agents** — this file is now an index. Per-session
> entries live in `worklog/`, sharded into 200–500 LOC chunks. Sessions 1–22
> are archived separately in `WORKLOG-archive.md`.
>
> **Convention: newest entries at the TOP**, both in this index and within each
> shard. When you finish a session: write the new entry at the top of the
> most-recent shard (`worklog/sessions-80-to-82.md` as of this writing), or
> open a fresh shard with a session-range filename if the current one is over
> ~500 LOC.
>
> **Known anomaly** — two sessions are both labelled "Session 35" (both dated
> 2026-04-20, written by different agents). The deep-research one lives in
> [`worklog/session-35-deep-research.md`](worklog/session-35-deep-research.md);
> the q84/QCoset/QRunway one is inside
> [`worklog/sessions-31-to-35q84.md`](worklog/sessions-31-to-35q84.md). Do not
> try to disambiguate by re-numbering — both IDs are referenced from elsewhere.

---

## Shards (newest first)

| Sessions | File | Dates | Topics |
|---|---|---|---|
| 80 → 82 | [sessions-80-to-82.md](worklog/sessions-80-to-82.md) | 2026-04-28 → 05-01 | QMod primitives shipped (os4/mle/p38/tws/u2n); README primitives reframing (Four → Three); README antipattern cleanup (18 fixes); README example verification; bd audit-gap reconciliation; worklog shard; 5z3r orkan sample() fix; test-discipline relearn |
| 77 → 79 | [sessions-77-to-79.md](worklog/sessions-77-to-79.md) | 2026-04-27 → 04-28 | code-review sweep grind (4 sweep beads); P1 clusters 1, 2, 3 partial (12 closed) |
| 75 → 76 | [sessions-75-to-76.md](worklog/sessions-75-to-76.md) | 2026-04-27 | P0 grind (11 closed); code-review pass + idiom corrections |
| 73 → 74 | [sessions-73-to-74.md](worklog/sessions-73-to-74.md) | 2026-04-26 | AbstractPass + registry (`7ab`); `2qp` n_qubits-at-peak ratchet diagnosis |
| 68 → 72 | [sessions-68-to-72.md](worklog/sessions-68-to-72.md) | 2026-04-25 → 04-26 | `6oc` close + `2qp` filed; doc refresh; oracle-table LRU; contiguous-live; do-block alloc; STURM_COMPACT_VERIFY |
| 65 → 67 | [sessions-65-to-67.md](worklog/sessions-65-to-67.md) | 2026-04-25 | `compact_state!(::DensityMatrixContext)`; HWM tracker; STURM_COMPACT_VERIFY env-gate |
| 64 + 64-end | [sessions-64-and-64end.md](worklog/sessions-64-and-64end.md) | 2026-04-25 | `compact_state!` lands (`059`); EOD handoff |
| 63 + 63-handoff | [sessions-63-and-63handoff.md](worklog/sessions-63-and-63handoff.md) | 2026-04-25 | Berry App B clean-ancilla forward QROM (`vbz`); 63-handoff superseded by 64 |
| 62 + 24-EOD-handoff | [sessions-62-and-24eod-handoff.md](worklog/sessions-62-and-24eod-handoff.md) | 2026-04-24 | CasesNode consumer fail-loud (`eiq`); 04-24 EOD handoff |
| 58 → 61 | [sessions-58-to-61.md](worklog/sessions-58-to-61.md) | 2026-04-24 | Berry MBU ground truth (`9ij`); X↔Y discriminators (`9g5`, `35s`); bench Int64 overflow (`guj`) |
| 56 → 57 | [sessions-56-to-57.md](worklog/sessions-56-to-57.md) | 2026-04-23 | QMod{3} Ry shipped (`k8u`); QMod{5} Ry via Euler sandwich (`ixd`) |
| 53 → 55 | [sessions-53-to-55.md](worklog/sessions-53-to-55.md) | 2026-04-23 | Rz at all d (`nrs`); spin-j Ry/Rz d=2 (`ak2`); goi-type implementer (`9aa`) |
| 51 → 52 | [sessions-51-to-52.md](worklog/sessions-51-to-52.md) | 2026-04-22 | qudit research rounds 1+2 (`goi`); goi-type 3+1 proposer round |
| 48 → 50 | [sessions-48-to-50.md](worklog/sessions-48-to-50.md) | 2026-04-22 | `6oc` Phase C1+C2; perf fix + N=5 all-bases; Toffoli-count trace bench |
| 44 → 47 | [sessions-44-to-47.md](worklog/sessions-44-to-47.md) | 2026-04-22 | QRunwayMid (`jrl`); `6oc` Phase A/B atoms (qrom_lookup_xor!, plus_equal_product!, mulmod_E_controlled!) |
| 41 → 43 | [sessions-41-to-43.md](worklog/sessions-41-to-43.md) | 2026-04-21 → 04-22 | Steane 870 P1/P2/P3; X!/Y! swap fix (`3yz`); Pauli gate bug (`a1e`) |
| 38 → 40 | [sessions-38-to-40.md](worklog/sessions-38-to-40.md) | 2026-04-21 | `cases()` + OpenQASM dynamic circuits; @context auto-cleanup (`sv3`); `discard!` → `ptrace!` (`diy`) |
| 37 | [session-37.md](worklog/session-37.md) | 2026-04-21 | Hardware round-trip backend (epic `vvu`, 7 beads, 1327 tests) |
| 36 → 36c | [sessions-36-to-36c.md](worklog/sessions-36-to-36c.md) | 2026-04-20 | Ekerå-Håstad short-DLP factoring (`6bn`); N=55 demo; EH17 follow-on beads |
| **35-deep** | [session-35-deep-research.md](worklog/session-35-deep-research.md) | 2026-04-20 | Deep research round + ship q84 + 8fy + 6xi + amh + b3l (705 LOC, single unsplittable session) |
| 31 → 35-q84 | [sessions-31-to-35q84.md](worklog/sessions-31-to-35q84.md) | 2026-04-20 | qsvt sin parity (`5gz`); c6n scaling doc; `p1z` Draper adder; `6xi` coset; q84 init circuits ⚠ contains the **second** "Session 35" — see anomaly above |
| 29 → 30 | [sessions-29-to-30.md](worklog/sessions-29-to-30.md) | 2026-04-19 | Shor resource benchmark (`i0j`); semi-classical iQFT for Shor (`8b9`) |
| 27 → 28 | [sessions-27-to-28.md](worklog/sessions-27-to-28.md) | 2026-04-19 | N=21 hunt → P0 in `uf4`; `add_qft!` angle-fold phase bug (`di9`) |
| 25 → 26 | [sessions-25-to-26.md](worklog/sessions-25-to-26.md) | 2026-04-19 | `shor_order_D` polynomial-in-L (`6kx`); `mulmod_beauregard!` green-up (`uf4`) |
| 24-EOD → 24E | [sessions-24eod-to-24E.md](worklog/sessions-24eod-to-24E.md) | 2026-04-18 | EOD handoff; tracing-nesting (`rpq`); `with_empty_controls` public API (`1wv`) |
| 23 → 24D + archive | [sessions-23-to-24D-and-archive.md](worklog/sessions-23-to-24D-and-archive.md) | 2026-04-17 → 04-18 | DM multi-controlled (`xcu`); P2 implicit-cast warning (`f23`); oracle arg-type from W (`q93`); QDrift RNG injection (`1f3`); PRD harmonisation (23); + pointer to `WORKLOG-archive.md` (sessions 1–22) |

---

## Earlier sessions archived

Sessions 1–22 (2026-04-05 → 2026-04-15) live in [`WORKLOG-archive.md`](WORKLOG-archive.md). The per-session topic listing is duplicated at the bottom of [`worklog/sessions-23-to-24D-and-archive.md`](worklog/sessions-23-to-24D-and-archive.md).
