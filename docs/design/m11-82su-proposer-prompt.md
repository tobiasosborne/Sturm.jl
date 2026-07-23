# DESIGN PROPOSAL TASK — M11 QECC superchannel typing + Stinespring dilation contract (bead Sturm.jl-82su; review findings F8/F33)

You are one of two INDEPENDENT blind proposers in a 3+1 design round for
Sturm.jl (quantum programming DSL in Julia; repo = cwd). Produce a complete,
self-contained design proposal as a Markdown document. Your FINAL MESSAGE is
captured verbatim as the proposal doc. Do not modify any files (read-only
sandbox).

## Context

M0–M10 are shipped (suite 26136 green): kernel process values (`U2`, `Perm`,
`UnitaryBlock{N}` + certificates), contexts (Eager / exact DM / Tracing with
`ChannelDAG`), the seven-construct surface, Bennett bridge, `QMod`/`mulmod!`/
`shor_order`, and the M10 library HOFs. M11 is the noise + QECC milestone.
Two review findings gate its design:

- **F8:** v0.1's single `encode(ch, code) :: Channel → Channel` HOF conflates
  three distinct operations: (a) protecting physical noise
  `Θ(𝓝) = D∘R∘𝓝∘E : Chan(P,P) → Chan(L,L)`; (b) encoding a state; (c)
  fault-tolerantly lifting a logical algorithm (not canonical — depends on
  transversal gadgets / magic-state protocols / fault model). The plan
  mandates replacing it with typed operations — `encode_state`,
  `effective_logical_noise(::Channel{P,P}, code)`, `fault_tolerant_lift` —
  modelled as superchannels/combs with explicit port types. This is a
  carried-contract re-derivation gate (plan §7, verdict (c)).
- **F33:** noise on a PURE context needs a policy: loud error (default) or an
  explicit **Stinespring dilation fallback**, whose contract must be
  specified: Kraus-rank padding, isometry synthesis `V|ψ⟩ = Σᵢ K_i|ψ⟩|i⟩_E`,
  unitary completion tolerances, environment wire ownership, and the rule
  that the dilation is an **execution artifact, never a controllable
  representative** of the channel (a dilation unitary must NOT become a
  `UnitaryBlock`/process value reachable by `ctrl` — that would smuggle
  measurement-flavored structure past P4).

## Design questions to answer (be concrete — real Julia signatures)

1. **Kraus channel values:** the kernel value type for noise (`KrausFamily`?
   — slice-1 reserved a `NoiseN` node and a KrausFamily stub; check
   `src/channel/` for what exists). Trait obligations (CPTP check at
   construction — exact or toleranced?), composition/tensor behavior,
   application through the same `apply!`/`Ad` surface, DM lowering
   (Kraus→superop), and the P4 boundary: noise is channel-level, `ctrl` is
   a MethodError by construction — show how your type slots into the §4.4
   stratification and the shipped `ChannelDAG` `NoiseN` barrier.
2. **The Stinespring fallback contract (F33):** exact algorithm (padding to
   Kraus rank r, V column construction, completion to a unitary on
   H_S ⊗ H_E — QR? Householder? — with what tolerance discipline per the
   §4.1 float-law ≈), environment allocation/ownership (region-owned, traced
   at exit per §3.9 — the environment IS the Stinespring boundary made
   literal), when the fallback fires (explicit opt-in `stinespring=true` vs
   context policy), and the artifact rule: the dilation unitary's
   representation must be UNREACHABLE from `ctrl` (not a `ProcessValue`; or
   a `ProcessValue` wrapped in a type `ctrl` refuses — pick one, justify
   against P4/Tang-Wright). What tests pin this (a `ctrl(dilation)`
   MethodError test; Choi equality dilated-vs-Kraus on DM).
3. **QECC typing (F8):** the three typed operations with signatures over
   physical/logical port types. How are `Channel{P,P}` / `Chan(L,L)` port
   types expressed in the v2 type system (the shipped ChannelDAG has typed
   quantum ports with lineage — do logical/physical labels ride the port
   type, a wrapper type, or a `Code` value)? What is a `code` value
   (stabilizer generators? encoder isometry? both?) and which milestone
   builds which representation? `encode_state` (cq-flavored? takes a logical
   register, returns physical), `effective_logical_noise` (a SUPERCHANNEL —
   how is a channel-to-channel map represented without violating "channels
   are not values"? The §4.4 stratification says channels are denotations —
   a superchannel applied at the DAG/pass level? Justify carefully — this is
   the hardest typing question; consider modelling it as a compiler
   transformation on `ChannelDAG` rather than a runtime value),
   `fault_tolerant_lift` (explicitly NOT canonical — your design should
   scope what M11 ships: likely a stub/interface + the honest statement of
   what it needs (fault model, gadget set) — do not overpromise).
4. **`classicalise`** (plan names it): the DM→classical-record extraction
   utility — spec its contract against the shipped token/record machinery.
5. **M11 scope cut:** what ships in M11 (noise values + Stinespring + the
   typed QECC interface + a repetition-code or 3-qubit bit-flip
   demonstration at the Choi level?) vs what gates on later epics (Steane
   re-derivation is explicitly a later reimport-gated epic). The i4ri
   token/`select` machinery is the syndrome-path substrate (one syndrome
   token drives corrections via `select`/`ClassicalTable` — the canonical
   copyable-token customer); show the syndrome-extraction + correction loop
   in surface vocabulary for the bit-flip code as the M11 acceptance
   example.
6. **Test plan:** Choi-level encode∘decode = id on the code subspace;
   effective-logical-noise of below-threshold bit-flip noise beats physical
   (the quantitative statement to pin); Stinespring dilated-vs-Kraus Choi
   equality; ctrl-unreachability MethodErrors; guardrail interactions
   (noise inside `when` is already a loud error — confirm the shipped
   guardrail covers your new value type).
7. Risks, alternatives considered and rejected, open questions needing a
   Tobias ruling.

## Required reading (repo root = cwd)

- `CLAUDE.md` (laws; the Channel IR vs Unitary Methods section; principle 4
  citation policy — name any missing distillation as a prerequisite work
  item: Stinespring, stabilizer codes / Gottesman, threshold theorem as
  needed).
- `Sturm-PRD-v2.md` §3.6/§3.8 (tokens/cases — the syndrome substrate), §3.9
  (scope/Stinespring boundary), §4.1a/§4.2/§4.4 (certificates, pass law,
  stratification), §6 P1–P9.
- `Sturm-v2-IMPLEMENTATION-PLAN.md` §M11 and §7 (carried-contract verdicts).
- `docs/design/prd-v2-review-gpt56-2026-07-19.md` findings F8, F33.
- Shipped code: `src/channel/` (NoiseN, ChannelDAG, certify, passes),
  `src/kernel/` (process values, ctrl choke point), `src/surface/tokens.jl`
  + `cases.jl` (the record machinery), `src/context/` (DM internals,
  `_apply_channel_1q!`), `src/orkan/` (what channel support the FFI has —
  read the actual ccall surface).
- `worklog/session-99.md`, `session-100-m9.md`, `session-101-m10.md` for
  current state.

## Ground rules

- GROUND = PHYSICS; every contract physically justified; no gates/rotations
  on any surface example; the seven constructs are fixed.
- Julia idiomaticity paramount; fail fast; `public` vs `export` namespace
  discipline.
- Be concrete: real signatures, not prose gestures. Scope honestly.
