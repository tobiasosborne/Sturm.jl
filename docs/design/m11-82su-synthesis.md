# M11 Synthesis — noise values, the Stinespring contract, QECC superchannel typing

**Bead:** `Sturm.jl-82su` · **Gates:** review findings **F8** (QECC superchannel
typing) + **F33** (Stinespring dilation contract) · **Plan:**
`Sturm-v2-IMPLEMENTATION-PLAN.md` §M11 and §7 verdict (c) — *the single remaining
(c) in the carried-contract table* · **Round:** 3+1, implementer/synthesiser.

Inputs: `m11-82su-proposal-A.md` (1471 lines), `m11-82su-proposal-B.md` (1274
lines), both blind, both against the shipped M0–M12 tree.
**Verdict: synthesis.** A owns the *channel-value algebra and the numerics*
(because A read the Orkan headers and let them shape the design); B owns the
*typed superchannel surface, the code representation, and the anti-tests*.
Neither is discarded; every ruling names its source.

Reviewer note (law 9): every claim either proposal makes about shipped code was
re-checked against the code before being built on. The audit is §1; two claims
did not survive contact and one claim the brief itself carried was wrong.

---

## §1 — Verification log (what I checked, and what changed as a result)

Read directly: `src/channel/{dag,cert,builder,passes,block_algebra}.jl`,
`src/context/{density,tracing,abstract}.jl`, `src/kernel/{ctrl,u2,perm}.jl`,
`src/surface/{when,cases,tokens,casts}.jl`, `src/library/evolve/pauli.jl`,
`Project.toml`, `.gitignore`, `CLAUDE.md`, `Sturm-v2-IMPLEMENTATION-PLAN.md`
§M11/§7, and the live Orkan headers `/home/tobias/Projects/orkan/include/*.h`.

| # | Claim | Verdict |
|---|---|---|
| V1 | `apply_channel!` never calls `_assert_no_control` (`density.jl:86`) | **TRUE.** `_flush_wire!` then `_apply_channel_1q!`, no guard. `when.jl` row 9 is still marked "forward hook (M8/M11)". Bead `Sturm.jl-udtl`. |
| V2 | `_apply_channel_1q!` is shared by `apply_channel!`, `trace_wire!` and `_instrument!` | **TRUE**, and this settles where the guard goes — see S3. |
| V3 | Orkan exposes only `kraus_to_superop` + `channel_1q` (1-local), and no dense-unitary gate entry | **TRUE, verbatim.** `channel.h` has exactly those two symbols; `gate.h` has `x y z h s sdg t tdg hy rx ry rz p cx cy cz swap_gate ccx` and nothing else. `ffi.jl:243–244` additionally guards `sop.n_qubits == 1` and `state.type != ORKAN_PURE`. A read the headers; B inferred correctly from `ffi.jl`. |
| V4 | `src/` takes no `LinearAlgebra` dependency | **TRUE.** `Project.toml` lists it only under `[extras]`/`test`; `numerics.jl:196` and `replay.jl:16` say so explicitly. Respected — see S9. |
| V5 | `KrausFamily` is a one-field stub (`dag.jl:85`) carried by `NoiseN`; nothing else in `src/` uses it except `builder.jl:128` and the `public` list | **TRUE.** Blast radius of the reshape is 4 files. |
| V6 | `_replay_dm!` errors on `NoiseN` (`tracing.jl:492`) | **TRUE** — the `else` of `_replay_nodes!`. M11 must add the branch. |
| V7 | B: `_replay_branch_controlled!` "gains a loud refusal" for `NoiseN` | **ALREADY SHIPPED.** `tracing.jl:530` fails closed on anything that is not `ApplyN`/`CasesN`, with the guardrail-1 message. No code change — a test only. Correction to B. |
| V8 | `select` has no host-scalar methods | **TRUE.** Only `(::ClassicalBit,…)` and `(::ClassicalWord,…)`. The syndrome program is not Eager-portable today. |
| V9 | A: `_footprint` has a fail-closed catch-all on `ProcessValue` | **TRUE** (`cert.jl:100`: `_footprint(::ProcessValue, ports) = (∅, Set(ports))`). This *strengthens* A's §2.5 argument: a dilation subtyping `ProcessValue` would be silently absorbed by `within`'s `MatchedPair` checker rather than erroring. |
| V10 | B: `classicalise` is **not** in the v2 plan; it is an unlogged v0.1 carried contract with a silent single-qubit defect | **TRUE, and the brief was wrong.** Zero hits in `Sturm-v2-IMPLEMENTATION-PLAN.md` and `Sturm-PRD-v2.md`; the only source is `Sturm-PRD.md` (v0.1), and `Sturm-PRD.md:457` literally reads *"`classicalise(f)` returns 2×2 column-stochastic matrix"* — the arity defect is in the contract text itself. A inherited the brief's error. See S24 and ruling **T2**. |
| V11 | B: `noise!` collides with a shipped name | **TRUE.** `noise!(b::DAGBuilder, ports...)` exists (`builder.jl:127`) and is in the `public` list (`Sturm.jl:337`). See S13. |
| V12 | B: exported physicist verbs are the M10/M12 precedent | **TRUE.** `evolve!`, `amplify`, `find`, `phase_estimate`, `interfere!`, `Trotter`, `QDrift`, `Composite`, `Auto` are all `export`ed. A's "export nothing" is therefore a deviation from precedent, not the status quo. See ruling **T5**. |
| V13 | A: `PauliWord` carries no sign | **TRUE.** `struct PauliWord{W}; x::UInt64; z::UInt64; end`, convention `Op(w) = i^{\|x∧z\|}X^x Z^z` (Hermitian). B's `StabilizerCode` has no `signs` field — a real gap. See S17. |
| V14 | `certify` refuses any barrier incl. `NoiseN`; `ApplyN.v::ProcessValue`; `ctrl` has no catch-all; `ctrl(::UnitaryBlock)` IS shipped (`ctrl.jl:107`) | **ALL TRUE.** The last one is what makes A's §9.2 item 2 decisive: a `ProcessValue`-wrapped dilation reaches `ctrl` in two composition steps via `Tensor` → `certify` → `ctrl(::UnitaryBlock)`. |
| V15 | `Base.adjoint(::UnitaryBlock)`, `∘`, `⊗`, `_remap_nodes`, `_rebase` all shipped (`block_algebra.jl:44,68,95,133,150`); `trace(f, nin)` shipped (`tracing.jl:406`) | **TRUE.** B's "encoder = `certify(trace(program))`, decoder = `adjoint`" costs zero new machinery. |
| V16 | CLAUDE.md rule 4 now says **commit the `.md`, never the PDF**; `docs/physics/*.pdf` are untracked (`git ls-files` → 0 PDFs) | **TRUE.** Both proposals' "PDF + distillation" work items are stale. See §7. |
| V17 | Watrous ToQI and Gottesman thesis are on disk in gitignored `docs/literature/` | **TRUE** (`watrous_2018_theory_of_quantum_information.pdf`, `quant-ph_9705052.pdf` + `_src`). Knill–Laflamme, Chiribella and Eastin–Knill are **not** on disk. See §7. |

**Physics re-derived independently** (not taken from either proposal):
`p_L = 3p²(1−p) + p³ = 3p² − 2p³`; `p_L − p = −p(1−p)(1−2p)`, so break-even is
exactly `p = ½` (`(2p−1)(p−1) = 0`); phase-noise amplification
`(1 − (1−2p)³)/2 ≈ 3p` (every `Z_i` is a logical `Z̄` and commutes with both
`Z`-type generators, so the syndrome is always 0 and *no correction ever fires* —
the residual is `Z̄` iff an odd number of `Z`s landed); and B's damping dilation
circuit, which I checked gate-by-gate and which reproduces
`K₀ = diag(1,√(1−γ))`, `K₁ = √γ|0⟩⟨1|` exactly. All correct.

---

## §2 — Convergent core (settled by the round; not re-litigated)

1. The dilation lives **outside the process-value tree entirely** — not a
   `ProcessValue` that `ctrl` refuses. Refusal is a runtime guard on one door;
   `Tensor`, `Seq`, `ApplyN`, `_footprint`'s catch-all, `certify`, `within` and
   `ctrl(::UnitaryBlock)` are the other doors (V9, V14).
2. `effective_logical_noise` is a **compiler transformation on `ChannelDAG`**,
   and explicitly **not** a `ChannelPass`: the pass law is Choi-preserving with
   an unchanged boundary, and a superchannel changes both by design.
3. Physical/logical labels ride the **register/handle type** and a thin
   channel wrapper — never the `Port`. A wire is not logical; a *bundle relative
   to a code* is.
4. `fault_tolerant_lift` ships as **interface + loud refusal**, grounded on
   **Eastin–Knill** — non-canonical *by theorem*, not by implementation gap.
5. **TP checked at construction; CP free** from the operator-sum form; a broken
   family is **never silently renormalised**.
6. Scope honesty: the dilation *mathematics* is general; the *executable*
   lowering is a named catalogue, with a loud error naming what is missing.
7. `ctrl` on any channel-level value is a **`MethodError` by construction** —
   zero lines added to the choke point.
8. The seven surface constructs are untouched. No eighth construct.

---

## §3 — Rulings

### 3.1 Channel values and the §4.4 stratification

| # | Question | Ruling | Source | Rationale |
|---|---|---|---|---|
| **S1** | Value tree | `abstract type ChannelValue end` with **four** concretes: `KrausFamily{W,R,L}`, `MixedUnitary{W,R}`, `ChannelTensor`, `ChannelSeq`. Not `<: ProcessValue`. | **A** | B's single-type design flattens `⊗` eagerly, which given V3 produces a `KrausFamily{2}` that **cannot be applied at all**. A's lazy `ChannelTensor` is the only shape that lowers i.i.d. noise through the one channel entry Orkan actually has. This is the clearest case in the round where reading the headers changed the design. |
| **S2** | `MixedUnitary` as a distinct type | **Keep it distinct**, not a flag. | **A** | It is exactly the family whose dilation is executable; making that a *dispatch* fact turns "your dilation cannot run" from a runtime surprise into a method-table fact with a specific message (principle 1). It is also closed under `∘`/`⊗` — the channel-level analogue of `ctrl(Perm) = Perm`. |
| **S3** | Where the missing guardrail goes (bead `udtl`) | `_assert_no_control(ctx, "noise channel application")` at the top of **`apply_channel!`** and at the top of every new `apply!(::ChannelValue)`/`apply_noise!` path — **NOT** in `_apply_channel_1q!`. | **new** (both proposals said "every noise path"; neither resolved the shared-lowering question) | Verified V2: `_apply_channel_1q!` is also the lowering for `trace_wire!` and `_instrument!`. `when.jl` row 8 states that a region-exit trace of a clean owned ancilla under a live control frame is **legitimate** (clean-ancilla assert, not banned); `ptrace!` guards itself at `regions.jl:216` and the measurement casts guard at `casts.jl:79`/`qint.jl:163`. A guard at the 1q lowering would therefore *break* a sanctioned path. The guard belongs one level up. |
| **S4** | TP tolerance | `KRAUS_TP_ATOL = 1e-12`, `ArgumentError` naming `‖Σ Kᵢ†Kᵢ − I‖_∞`. Never renormalise. | **A** | A derives the number (residual ≲1e-15 for the shipped size range; a real user error is O(1e-2); 1e-12 sits three decades above the noise floor and ten below any physical non-TP-ness). B's 1e-10 is asserted by analogy to `U2_ATOL`, which is the *accumulated-group-product* scale — a different quantity. |
| **S5** | Storage | Frozen `NTuple{L,ComplexF64}`, `L = R·4^W`, **row-major concatenated**, ceiling `KRAUS_MAXDATA = 1024`. | **B** (ceiling + layout), A (F28 framing) | B's ceiling is the right order (an `NTuple{4096}` destroys inference; A itself flags this as risk R3), and B's observation that the layout *is* Orkan's `kraus_t` layout is verified against `density.jl:61–70` — the DM path copies once. |
| **S6** | Semantic equality | **`same_channel(a, b; atol) = Choi(a) ≈ Choi(b)`. `Base.isapprox` on channel values stays UNDEFINED.** `==` stays exact-structural. | **A** spelling, **B** content; resolves B's own ruling Q8 | F26 forbids tolerance in `==`; and an O(4^W) Choi construction behind an operator that *looks* cheap is a footgun. `same_process` is the shipped precedent for exactly this split. |
| **S7** | Denotation | `channel(v::ProcessValue) -> KrausFamily{·,1,·}`, total, **no inverse anywhere** (no `process(::ChannelValue)` method exists). No mixed `∘`/`⊗` between a `ProcessValue` and a `ChannelValue`. | **A** | §4.4's "denotation is a quotient, always available, never invertible" becomes a method-table fact. Forcing `channel(U) ∘ 𝓝` makes the quotient visible in the source. |
| **S8** | Named constructors | `bit_flip`, `phase_flip`, `pauli_channel`, `depolarizing`, `dephasing`, `phase_damping`, `amplitude_damping`, plus `reset_channel()`/`pinch_channel()` **re-homing the shipped `_RESET_KRAUS`/`_PINCH_KRAUS`**. `depolarizing(p)` PINNED to `ρ ↦ (1−p)ρ + p·I/2`; the `(p/3)ΣPρP` convention is *not* offered under that name. | **A** | Convention-pinning in the constructor is where the physics bugs are killed. The re-homing is principle 13: one representation of "the pinch", not two. |

### 3.2 The Stinespring contract (F33)

| # | Question | Ruling | Source | Rationale |
|---|---|---|---|---|
| **S9** | Unitary completion algorithm | **Householder QR, with the first `d` columns then overwritten by `Ṽ` verbatim.** No `LinearAlgebra` (V4). No `diag(R̃)` phase fix is needed in this variant. | **synthesis** (A's algorithm + B's exactness property, and *simpler than either*) | A is right on the decisive point: **Gram–Schmidt puts a rank-detection tolerance inside the algorithm.** B's `GS_PIVOT_TOL = 1e-8` is a discrete accept/reject on a float: a legitimately independent basis vector with a genuine residual near τ is *rejected*, the sweep comes up short, and the construction **fails loud on valid input**, data-dependently. Householder cannot fail — it is `d` reflections and always yields a unitary `Q`; the only tolerances are post-conditions. But B is also right that its first `d` columns are *bit-exact* `Ṽ` while A's are `Q[:,1:d]·R̃ = Ṽ + O(Mε)`. Both properties are obtainable at once: run Householder, take `U[:, d+1:M] := Q[:, d+1:M]`, and set `U[:, 1:d] := Ṽ` directly. `span(Q[:,d+1:M]) = span(Ṽ)^⊥` exactly by construction, so unitarity still holds to `O(Mε)`, the contract assertion `U[:,1:d] == Ṽ` becomes **exact equality** (a stronger test), and A's `diag(R̃)` correction — the fiddliest part of A's proposal and the easiest to get subtly wrong — disappears entirely. |
| **S10** | Environment wire ordering | **Environment wires LEAD (MSB).** `Ṽ[i·d + s + 1, t + 1] = Kᵢ[s+1, t+1]`. | **A** (B pinned system-first and did not argue it) | Three reasons, the third decisive. (i) With env leading, the `env = \|0…0⟩` input columns are exactly columns `1:d`, so the contract is literally `U[:, 1:d] == Ṽ` and `Kᵢ = U[i·d+1 : i·d+d, 1:d]` — no strided extraction, no permutation. B's system-first convention makes those columns `1, 2^e+1, 2·2^e+1, …`, i.e. every extraction carries index arithmetic that can be silently wrong. (ii) It matches `apply!`'s "position 1 = MSB wire". (iii) **It matches `Ctrl`'s "leading wires are controls"** — and in the executable tier the environment *is* the control (`Σᵢ\|i⟩⟨i\|_E ⊗ Uᵢ` is a multiplexed control). So the dense artifact and the structured emission agree with **no** permutation between them, which is precisely the property that lets the three-way agreement test (S27) detect an ordering bug instead of being fooled by two compensating ones. |
| **S11** | Artifact rule | `abstract type ChannelArtifact end`; `StinespringDilation{W,E} <: ChannelArtifact`, subtyping neither `ProcessValue` nor `ChannelValue` nor `Node`. Raw `Matrix{ComplexF64}` inside. Single consumer `_emit_dilation!`, confined by a **boot lint** mirroring the shipped `_ctrl` lint. | **B** (the named supertype) + **A** (the three-way "subtypes nothing" argument) | B's `ChannelArtifact` supertype is worth having: it gives future lowering artifacts (a synthesised QSD block, a hardware pulse schedule) a home that is already outside both trees. A's argument list is the better justification, now strengthened by V9/V14: a `ProcessValue`-wrapped dilation reaches `ctrl` in two steps (`Tensor` → `certify` → `ctrl(::UnitaryBlock)`) and is silently absorbed by `_footprint`'s fail-closed catch-all on the way. |
| **S12** | When the fallback fires | **Never implicitly, in any context.** `stinespring = true` is a required, greppable **call-site kwarg**. A context-level policy (`eager(cap; noise=:dilate)`) is rejected. Under Tracing, `stinespring=true` is a **loud error** — the IR records the channel, never a dilation. | **A + B** (identical conclusions, merged messages) | Both proposals reject context policy for the same reason and it is the right one. A adds the resource argument (an implicit dilation makes a channel application fail at a distance as "capacity exceeded"); B adds the ZYZ parallel (the chart is chosen at the boundary, never in the IR). Both go in the docstring. |
| **S13** | Verb spelling | `apply!(ctx, ch, wires; stinespring=false)` at the context/wire layer (PRD §4.3's "same surface"), **`apply_noise!(reg, ch; stinespring=false)`** at the handle layer. `noise!(::DAGBuilder, …)` is left untouched. | **A**; resolves B's ruling Q6 | V11: `noise!` is already taken by shipped, `public` IR-construction vocabulary. Renaming a shipped name to free up a spelling is worse than picking an unambiguous one, and `apply_noise!` says what it does. |
| **S14** | Executable catalogue | **Class P** (mixed-unitary / Pauli): PREPARE `\|χ⟩_E = Σ√pᵢ\|i⟩` by the real-amplitude binary `Ry` tree, then multiplexed `ctrl^E(Uᵢ)` with X-sandwich anti-controls. **Class D** (damping): `ctrl(Ry(2θ))` sys→env with `sinθ = √γ`, then `ctrl(X)` env→sys. **Class X** (everything else): loud error naming the missing capability. | **A** (class P) **+ B** (class D) | I verified B's damping circuit gate-by-gate: it yields `K₀ = diag(1,√(1−γ))`, `K₁ = √γ\|0⟩⟨1\|` exactly, using only `U2` + `ctrl` — **no dense-unitary entry required**, so it does not contradict V3. A wrongly concluded that `amplitude_damping` is unexecutable because it is not mixed-unitary; non-unitality does not imply non-emittability. This matters beyond convenience: amplitude damping is A's own chosen sentinel for the env-ordering pin (S10) *precisely because* it is non-unital and asymmetric, and class D is what promotes that test from matrix-level to end-to-end. **Research step R1:** the kernel's `Ry` sign convention must be *checked*, not assumed, before the class-D emitter is trusted. |
| **S15** | Environment ownership | `_emit_dilation!` opens an internal `region() do … end`; env wires are `allocate!`d inside and **traced at its exit** (§3.9). Nothing escapes. `keep_environment=true` is **rejected** for M11. | **A + B** | Identical. §3.9's Stinespring boundary made literal with no new mechanism. A adds `_require_env_capacity` pre-checking so the failure names the right operation; keep it. B's rejection of `keep_environment` is right and its reason is right: an escaping environment means "noise" is no longer a channel on its signature. |
| **S16** | Eager honesty | On Eager, dilation + region-exit trace **is** the quantum-jump unravelling: **one run is one trajectory, not the channel.** Stated in the docstring and in the error message; `shots` named as the recovery. A separate "jump/unravel" mode is rejected as *redundant*, not wrong. | **B** (the redundancy argument) + **A** (the S10-guard precedent) | B's observation that the third mode is already (b) composed with a shipped lowering is the cleaner disposal. A's pointer to M12's `_assert_randomized_legal` is the precedent for why the flag must be explicit. |

### 3.3 QECC typing (F8)

| # | Question | Ruling | Source | Rationale |
|---|---|---|---|---|
| **S17** | Code value | `StabilizerCode{N,K,S}` carrying `stabilizers::NTuple{S,PauliWord{N}}`, **`signs::NTuple{S,Int8}`**, `logical_x`, `logical_z`, `declared_distance`. Validated at construction over **GF(2), no floats**: (1) `S == N−K`, no identity generator; (2) pairwise commuting (shipped `commutes`); (3) symplectic rank `== S`; (4) logicals in the normaliser; (5) `commutes(X̄ᵢ, Z̄ⱼ)` iff `i ≠ j`; (6) no logical inside `S`. | **B** shape + **A** `signs` | V13: `PauliWord` is sign-free, so a code with a `−1` generator is unrepresentable without A's field. It does not bite for the bit-flip code (all `+1`), which is exactly why omitting it would ship a latent defect that the M11 test suite could not see. |
| **S18** | Encoder representation | The encoder is a surface program on `N` wires (logical in slots `1..K`, fresh `\|0⟩` in `K+1..N`), reified by the shipped `trace(f, N)` and minted by `certify` into a **`UnitaryBlock{N}`**; the **decoder is `adjoint(encoder)`**, free from `block_algebra.jl`. | **B** | A rejected this on the grounds that an encoder is an isometry `L → P` and a `UnitaryBlock` is square. A is right about the isometry but missed the factorisation: `E = (apply the N-wire unitary) ∘ (allocate \|0⟩^{N−K})`, and the *unitary part* certifies cleanly (V15). B's version is strictly better because `decode = adjoint(encode)` is then **exactly** inverse by construction, whereas A's `EncoderSpec` carries two independent `Function` fields whose relationship is only ever checked by a test — two representations of one thing, which principle 13 forbids and which admits an encode/decode mismatch no type prevents. |
| **S19** | Where the encoder lives | **Not a field of the code.** Split into two values: `StabilizerCode{N,K,S}` (the gauge-free code space + logical operators) and `CodeEncoding{C,N,K}` holding `code`, `encoder::UnitaryBlock{N}`, and the syndrome table. `Protect` takes a `CodeEncoding`. `bit_flip_code()` returns the `CodeEncoding`; `code(enc)` projects. | **synthesis** (B's representation, A's separation) | A's objection is sound at the level it operates: the encoder is a **gauge choice** (Cleve–Gottesman gives *an* algorithm, not *the* encoder), so folding it into the code value re-imports the F8 conflation one level down — two codes with identical stabilizers but different encoding circuits would be `!=`. B's counter-argument (zero new machinery) is answered by keeping B's representation and moving it into its own struct, which costs one struct. The forward payoff is concrete: a later epic adds `standard_form_encoding(code)` producing a *different* `CodeEncoding` for the *same* `StabilizerCode`, and the types say so. |
| **S20** | Syndrome table | **Self-validating at construction**: for every syndrome `σ ∈ 0:2^S−1`, `syndrome(code, corrections[σ]) == σ`. | **B** | This directly discharges A's own top risk (R5: "`p_L = 3p²−2p³` is only right if the recovery table is right"), converting a mis-entered table from a silent physics bug into a construction error. Note what it does *not* check — that each entry is minimum-weight. That is decoder quality, not well-formedness; the docstring must say so. |
| **S21** | Superchannel typing | Typed wrappers `PhysicalChannel{C}` / `LogicalChannel{C}` (each a validated `ChannelDAG`); `abstract type ChannelTransform end`; `Protect{C,R<:RecoveryPolicy} <: ChannelTransform`, callable; `effective_logical_noise(𝓝::PhysicalChannel{C}, θ::Protect{C})::LogicalChannel{C}`. Body is literally `D ∘ R ∘ 𝓝.dag ∘ E`. | **B** | This is the better answer to F8's *"explicit port types"* demand: the P→L typing is in the signature, and a code mismatch is a `MethodError` rather than a runtime arity check. A's version takes a bare `ChannelDAG` and validates at runtime. |
| **S22** | `PhysicalChannel` preconditions | Validating constructor: `length(qin) == length(qout) == nphysical(code)`; **boundary lineage `in == out`, in order** (reuse `certify`'s check, factored out as `_assert_endomorphic`); `isempty(cout)`; no alloc/trace boundary imbalance. | **A** | A's preconditions are more thorough than B's and reuse a shipped checker. The `cout` check is the one that matters most: a "physical noise model" with a classical output is an *instrument*, and admitting one would smuggle a second measurement record into the syndrome path. |
| **S23** | Transform law + registry | `TRANSFORM_REGISTRY` + a boot lint mirroring `PASS_REGISTRY`. Two required laws per registered transform: (a) **spec law** `Choi(θ(g)) ≈ Choi(spec(θ)(g))` with the composite assembled independently in the test file; (b) **identity law** `Choi(θ(id_P)) ≈ Choi(id_L)`. A transform cannot ship without both running. | **B** | Makes "a superchannel is not a pass, and has its own obligation" mechanical rather than documentary. Also promotes F8's "encode∘decode = id on the code subspace" from a one-off test to a registry-enforced obligation. |
| **S24** | Entry hygiene | `physical_iid(code, 𝓝::KrausFamily{1}) -> PhysicalChannel` for i.i.d. noise; `effective_logical_noise(::ChannelValue, ::AbstractCode)` is a **loud refusal** — *"a family says WHAT the noise is, not WHERE it acts"*. | **B** | A lacks this and would have let a bare family be auto-lifted. The refusal is the F8 discipline applied to the noise argument. |
| **S25** | Surface constructs on an encoded block | **M11 ships NO logical operations.** A `CodeBlock` supports exactly `decode_state`, the recovery program, and introspection. `not!(blk)`, `Bool(blk)`, `blk₁ ⊻= blk₂`, `dual(blk)`, `when(blk)`, `oracle(f, blk)` are **all loud refusals**, each naming what it would need. B's construct-by-construct table ships as the docstring — it *is* F8's argument — with all rows refused. | **A** (strict line); B's table kept as documentation. **Escalated as T3.** | B proposed shipping `not!` (as `X̄`) and `Bool` (transversal measure + majority). `not!` is defensible — a declared logical Pauli is unambiguous. `Bool(blk)` is not: A's §9.2 item 13 is sharp and correct — "transversal measure + majority vote" and "decode, then measure" are **two different channels** on a noisy block, and offering one under the cast spelling silently picks a fault-tolerance-flavoured protocol. That is F8 reappearing at the cast level in the milestone whose job is to close F8. B itself flags this as its ruling Q3 and calls the conservative line defensible; I take the conservative line, and escalate because B recommended otherwise. |
| **S26** | `fault_tolerant_lift` | Interface only (`FaultModel`, `GadgetSet`, `FTImplementation{C}` — **no concrete subtype in M11**) + a loud refusal whose message names **five** missing ingredients: fault model; gadget set with a per-code transversality declaration; magic-state / gate-teleportation protocol for the non-transversal remainder; extraction schedule under a *noisy*-syndrome model; threshold accounting. Grounded on **Eastin–Knill**. A required test asserts the message content. | **B** (Eastin–Knill + message test) + **A** (accounting ingredient) | Eastin–Knill makes the refusal a *theorem*, not a gap — the strongest available framing. Merging A's and B's ingredient lists gives five; the message-content test makes the under-promise testable. |
| **S27** | Modelling assumption, named | `Θ(𝓝) = D∘R∘𝓝∘E` is the **code-capacity model**: noiseless encoder, recovery and decoder; perfect syndrome extraction. Stated in the docstring, in the staged PRD amendment, and in the `fault_tolerant_lift` message. **M11 makes no fault-tolerance claim and no threshold claim.** | **B** | A implies this but never states it. Naming it is what keeps the `p_L < p` result from being read as a threshold result. |

### 3.4 IR machinery

| # | Question | Ruling | Source | Rationale |
|---|---|---|---|---|
| **S28** | Channel-level `∘` / `⊗` on `ChannelDAG` | Ship **both** (§4.4 promises both; neither exists — V5/§4.4 audit). `∘`: `b` runs first. Relabel **`PortID`s AND lineages** into a fresh namespace before splicing; **identify `g.qin[i]` with `f.qout[i]` including lineage** (the seam is one physical resource, which is what lets a composite of endomorphisms certify); **remap nested `CasesN` branch DAGs recursively**; refuse a classical seam loudly in M11; `cout` is the ordered union. Reuse `block_algebra.jl`'s `_remap_nodes`/`_rebase`. | **A** (`⊗`, relabel test) + **B** (seam lineage, recursive `CasesN`, classical-seam refusal) | Both flagged the collision hazard; B has the harder details right (nested branches, seam lineage identification). A's negative-control test — *naive concatenation silently fuses unrelated wires and must be shown to fail* — is the wm28-class guard and is kept. This is the most intricate new code in M11 (both proposals' top-3 risk). |
| **S29** | `_replay_dm!` | Add the `NoiseN` branch. **No change** to `_replay_branch_controlled!` — V7: it already fails closed with the guardrail-1 message. Ship a test pinning that, not a patch. | **A** finding, **corrected** | Correction to B. |
| **S30** | `select` portability | Add host-scalar methods `select(::Bool, a, b)`, `select(::Integer, ::AbstractVector{<:Integer})`, `select(::Integer, ::ClassicalTable)` with the *same* totality checks and the *same* messages. | **A** | V8: without these the M11 acceptance example `MethodError`s on Eager, and the §3.8 portability contract is that one listing runs in all three contexts. |
| **S31** | `classicalise` vs record introspection | **Two names, two operations.** `classicalise(g::ChannelDAG \| ::ChannelValue \| ::LogicalChannel) -> Matrix{Float64}`: the decohered channel `Δ_out ∘ 𝓔 ∘ Δ_in` as a column-stochastic matrix, **arity taken from the ports** (the v0.1 defect cannot recur), exact by replay, loud above `CLASSICALISE_MAXWIRES`, docstring-flagged **PHASE-BLIND, never a channel-equivalence test**. `record_distribution(t::ClassicalToken)`: the token-record introspection. | **B**'s split, **A**'s contract for the token side | V10 is decisive: `classicalise` is a v0.1 name with a v0.1 meaning, and A silently repurposed it (following the brief) for a *different* operation — the exact sample/record/assert conflation §3.6 spends a page killing. From A, the token side inherits the better-specified contract: no backaction (the record wires are already pinched, so `density_matrix` is bitwise identical before/after — a named test); does not consume (tokens are copyable); DM-only with `MethodError` on Eager and a descriptive error on Tracing; asserts the record is still live; fan-in capped at the shipped `CASES_MAX_FANIN` with the same message shape; **returns a distribution, not a value**, so there is no scalar to branch on. |

---

## §4 — M11 scope cut

### 4.1 Ships

| Slice | Content |
|---|---|
| **0** | Physics distillations (§7) — **before** the code that cites them. |
| **1** | `ChannelValue` tree (S1/S2), TP check (S4), frozen storage (S5), `∘`/`⊗` closure, `channel`/`same_channel` (S6/S7), named constructors (S8); `KrausFamily` stub → real value; `NoiseN` reshape; `builder.jl` `noise!` updated. |
| **2** | Application: `apply!(ctx, ::ChannelValue, wires)` + `apply_noise!` (S13); DM 1-local native; `ChannelTensor` recursion into 1-local factors; Tracing `NoiseN`; Eager loud; **guardrail wiring (S3, closes `udtl`)**; `_replay_dm!` `NoiseN` branch (S29). |
| **3** | Stinespring: isometry, Householder completion with exact first-`d` columns (S9), env-leading pin (S10), `ChannelArtifact`/`StinespringDilation` (S11), the opt-in policy (S12), catalogue classes P + D (S14), region-owned environment (S15), the choke-point emitter + boot lint. |
| **4** | `∘`/`⊗` on `ChannelDAG` (S28) + `channel_dag(ch, n)`. |
| **5** | `StabilizerCode` + GF(2) validation (S17), `CodeEncoding` (S19), self-validating table (S20), `bit_flip_code()`, `CodeBlock`, `encode_state`/`decode_state` (S18), the six loud refusals (S25). |
| **6** | `PhysicalChannel`/`LogicalChannel` (S21/S22), `ChannelTransform`/`Protect`/`TableDecoder`/`NoRecovery`, `effective_logical_noise`, `physical_iid` + the refusal (S24), `TRANSFORM_REGISTRY` + lint (S23), `fault_tolerant_lift` interface + refusal (S26). |
| **7** | `classicalise` + `record_distribution` (S31); `select` host-scalar methods (S30). |
| **8** | Tests (§6); staged PRD amendments (written, not applied); worklog. |

### 4.2 Defers — with the reason, not a shrug

- **Steane `[[7,1,3]]`** — its own reimport-gated epic (plan §M11), with its own
  distillations and Choi-level tests.
- **Encoder synthesis** (Cleve–Gottesman standard form) and CSS structure.
- **Decoders beyond table lookup** (MWPM / BP / union-find).
- **Executable general dilation (class X)** — blocked on an Orkan `unitary_kq`
  entry or a KAK/QSD synthesis round (V3). Cross-repo work item, ruling **T4**.
- **k-local DM noise (`W ≥ 2`)** — **loud error in M11.** B proposed a dense
  Julia-side path but correctly gated it on an unverified research step (does
  `state_set` round-trip on `MIXED_TILED`, Hermitian partner included?). It buys
  nothing M11 needs: i.i.d. physical noise is a `ChannelTensor` of 1-local
  factors, which is the acceptance example's entire requirement. Deferring is
  free; shipping an unverified write-back path is not.
- **Kraus-rank compression** — needs a Choi eigendecomposition, hence
  `LinearAlgebra`, which core does not take (V4). A `SturmLinearAlgebraExt`
  package extension is the named route.
- **CP trace-non-increasing families / `postselect`** — the effect surface is not
  shipped; admitting subnormalised families first would let the CP-TNI regime in
  silently (P1).
- **Fault tolerance of any kind**; noisy syndrome extraction; any threshold claim.
- **Correlated / non-Markovian noise** — needs combs with memory wires. The
  `ChannelTransform` category is shaped for it; M11 ships only the memoryless case.
- **`TrajectoryContext{DM}`.**
- **Large-`R` ensemble channels — M12 over-promised.** `evolve.jl:123`'s
  `_assert_randomized_legal` message states that "the DM lowering of the ensemble
  is M11's mixture value". **M11 as scoped does not close that**: `MixedUnitary{W,R}`
  targets the enumerated `R ≤ 16` case, while a qDrift step has `R ~ 10⁴` samples
  of `W`-wire values with no 1-local native path. Closing it needs a distinct
  `EnsembleChannel` with a sampling lowering. **Soften the M12 message in the same
  commit** rather than leaving a stale forward reference (A's Q6; ruling **T6**).

---

## §5 — Concrete signatures

```julia
# ── src/channel/channel_values.jl (structs; after kernel/perm.jl, before channel/ports.jl)
abstract type ChannelValue end
struct KrausFamily{W,R,L}  <: ChannelValue; data::NTuple{L,ComplexF64}; label::Symbol; end
struct MixedUnitary{W,R}   <: ChannelValue; weights::NTuple{R,Float64}; unitaries::NTuple{R,ProcessValue}; end
struct ChannelTensor{A<:ChannelValue,B<:ChannelValue} <: ChannelValue; a::A; b::B; end   # a leads (MSB)
struct ChannelSeq{A<:ChannelValue,B<:ChannelValue}    <: ChannelValue; a::A; b::B; end   # b runs first

const KRAUS_TP_ATOL   = 1e-12          # S4, derived
const KRAUS_MAXDATA   = 1024           # S5, R·4^W ceiling
const STINESPRING_ATOL = U2_ATOL       # 1e-10, §4.1 float-law scale
const DILATION_MAXWIRES = 8

KrausFamily(ops::AbstractVector{<:AbstractMatrix}; label=:custom) -> KrausFamily
nwires(::ChannelValue) -> Int ; krausrank(::KrausFamily{W,R}) where {W,R} = R
kraus_matrices(::ChannelValue) -> Vector{Matrix{ComplexF64}}      # cold path
choi_matrix(::ChannelValue) -> Matrix{ComplexF64}                 # canonical representative
channel(v::ProcessValue) -> KrausFamily{·,1,·}                    # S7: total, no inverse
same_channel(a::ChannelValue, b::ChannelValue; atol=CHOI_ATOL) -> Bool   # S6; NO Base.isapprox
Base.:∘(::ChannelValue, ::ChannelValue) ; ⊗(::ChannelValue, ::ChannelValue)
# NO ∘/⊗ mixing ProcessValue × ChannelValue.  NO ctrl.  NO adjoint.

bit_flip(p) ; phase_flip(p) ; pauli_channel(px,py,pz) ; depolarizing(p) ; dephasing(λ)
amplitude_damping(γ) ; phase_damping(λ) ; reset_channel() ; pinch_channel()

# ── src/context/noise.jl
apply!(ctx::AbstractContext, ch::ChannelValue, wires::NTuple{K,WireID}; stinespring::Bool=false)
apply_noise!(q::AbstractQubit, ch::ChannelValue; stinespring::Bool=false)   # handle layer
apply_noise!(x::QInt{W},      ch::ChannelValue; stinespring::Bool=false)    # i.i.d. on all W wires
# both call _assert_no_control(ctx, "noise channel application") FIRST  (S3)

# ── src/channel/stinespring.jl  (CHOKE POINT; boot-linted)
abstract type ChannelArtifact end
struct StinespringDilation{W,E} <: ChannelArtifact       # subtypes nothing else
    isometry::Matrix{ComplexF64}
    unitary ::Matrix{ComplexF64}                          # env LEADING; unitary[:,1:d] == isometry
    rank::Int
    program::Union{Nothing,DilationProgram}               # class P/D only
end
dilate(ch::ChannelValue) -> StinespringDilation           # general: math always; program sometimes
# _emit_dilation!  — private, single consumer, asserts an empty control stack (defence in depth)

# ── src/qecc/codes.jl
abstract type AbstractCode end
struct StabilizerCode{N,K,S} <: AbstractCode
    name::Symbol
    stabilizers::NTuple{S,PauliWord{N}}
    signs::NTuple{S,Int8}                                 # S17 — PauliWord is sign-free
    logical_x::NTuple{K,PauliWord{N}}
    logical_z::NTuple{K,PauliWord{N}}
    declared_distance::Int
end
struct CodeEncoding{C<:AbstractCode,N,K}                  # S19 — the gauge choice, separated
    code::C
    encoder::UnitaryBlock{N}                              # certify(trace(program, N))
    corrections::NTuple{M,PauliWord{N}} where {M}         # M = 2^S; self-validating (S20)
end
decoder(e::CodeEncoding) = adjoint(e.encoder)             # S18 — exact by construction
syndrome(code, err::PauliWord{N}) -> Int
nphysical, nlogical, stabilizers, distance, verify_distance   # verify_distance: brute force, N ≤ 8
bit_flip_code() -> CodeEncoding                           # the validated [[3,1,1]]

# ── src/qecc/blocks.jl
struct CodeBlock{C<:AbstractCode,N,Ctx<:AbstractContext} <: AbstractQRegister{Ctx}
    ctx::Ctx ; enc::CodeEncoding{C,N,K} where {K} ; wires::NTuple{N,WireID}
end
encode_state(e::CodeEncoding{C,N,K}, qs...) -> CodeBlock{C,N}
decode_state(blk::CodeBlock{C,N}) -> NTuple{K,QBool}
# S25: not!/Bool/⊻=/dual/when/oracle on a CodeBlock are all loud refusals in M11.

# ── src/qecc/superchannel.jl
struct PhysicalChannel{C<:AbstractCode}; code::C; dag::ChannelDAG; end   # validated (S22)
struct LogicalChannel{C<:AbstractCode};  code::C; dag::ChannelDAG; end
abstract type ChannelTransform end
abstract type RecoveryPolicy end
struct TableDecoder <: RecoveryPolicy end ; struct NoRecovery <: RecoveryPolicy end
struct Protect{C<:AbstractCode,R<:RecoveryPolicy} <: ChannelTransform; enc::CodeEncoding; recovery::R; end
(θ::Protect{C})(𝓝::PhysicalChannel{C}) where {C} = effective_logical_noise(𝓝, θ)
effective_logical_noise(𝓝::PhysicalChannel{C}, θ::Protect{C}) where {C} -> LogicalChannel{C}
physical_iid(e::CodeEncoding, 𝓝::ChannelValue) -> PhysicalChannel
const TRANSFORM_REGISTRY = …                                # S23 + boot lint

# ── src/qecc/ft.jl
abstract type FaultModel end ; abstract type GadgetSet end
abstract type FTImplementation{C<:AbstractCode} end          # NO concrete subtype in M11
fault_tolerant_lift(Φ::LogicalChannel, impl) = throw(ArgumentError(…five ingredients…))

# ── src/channel/dag_algebra.jl
Base.:∘(a::ChannelDAG, b::ChannelDAG) -> ChannelDAG ; ⊗(a::ChannelDAG, b::ChannelDAG) -> ChannelDAG
channel_dag(ch::ChannelValue, n::Int) -> ChannelDAG

# ── analysis (S31)
classicalise(g) -> Matrix{Float64}                           # column-stochastic; arity from ports
record_distribution(t::ClassicalToken) -> Vector{Float64}    # DM only; no backaction; non-consuming
```

### The acceptance example (surface vocabulary only)

```julia
"Encode |ψ⟩ ↦ α|000⟩ + β|111⟩ — two actions, no gates, no angles."
function bitflip_encode!(q1, q2, q3)
    q2 ⊻= q1
    q3 ⊻= q1
    return (q1, q2, q3)
end

"""
Recovery: measure the two parity checks Z₁Z₂ and Z₂Z₃ into fresh ancillas, then
correct. ONE syndrome record drives all three corrections — the canonical
copyable-token customer (§3.6, i4ri §2.2).
"""
function bitflip_recover!(q1, q2, q3)
    a1 = QBool(false); a2 = QBool(false)     # construct 1
    a1 ⊻= q1; a1 ⊻= q2                       # construct 3 — parity(q1,q2)
    a2 ⊻= q2; a2 ⊻= q3                       # construct 3 — parity(q2,q3)
    s = syndrome(Bool(a1), Bool(a2))         # construct 2 (×2) + a T2 derivation
    @cases s begin                           # construct 6
        0 => nothing
        1 => not!(q1)
        3 => not!(q2)
        2 => not!(q3)
    end
    return (q1, q2, q3)
end
```

The arm map is the code's **validated** table (S20), not folklore: `X` on `q1`
anticommutes with `Z₁Z₂` only ⇒ `s = 1`; on `q2` with both ⇒ `s = 3`; on `q3`
with `Z₂Z₃` only ⇒ `s = 2`.

```julia
enc = bit_flip_code()
𝓝  = physical_iid(enc, bit_flip(p))          # PhysicalChannel: bit_flip(p)^{⊗3}
Φ   = Protect(enc)(𝓝)                         # LogicalChannel — Θ(𝓝) = D∘R∘𝓝∘E
J   = choi(Φ)                                 # exact 4×4 logical Choi, one DM run
```

**Wire budget:** 1 Bell reference + 3 data + 2 syndrome ancillas = **6 wires**
(2⁶×2⁶ DM), comfortably inside the ~7-wire Choi cap (F25/TR8). `cases` fan-in is
2 record wires ⇒ 4 configurations, far under `CASES_MAX_FANIN = 16`. The
**physical** 3-qubit Choi would need 6 Bell wires and a 2¹²×2¹² matrix (≈2 GB)
and is never required — worth stating, because reaching for it is the obvious
mistake.

---

## §6 — Test plan

Named `@testset`s, grep-able, in `test/test_m11_noise.jl`,
`test_m11_stinespring.jl`, `test_m11_qecc.jl`.

**Channel values**

| Test | Statement |
|---|---|
| `M11.KRAUS.TP-CHECK` | `‖ΣK†K−I‖ = 1e-3` throws naming the deviation; `1e-16` constructs |
| `M11.KRAUS.NO-SILENT-RENORM` | the message does not offer to rescale; no method rescales |
| `M11.CHANNEL.AD-KERNEL` | `same_channel(channel(gphase(π/3)), channel(I2))` **and** `channel(gphase(π/3)) != channel(I2)` — `ker(Ad) = U(1)` at the value level |
| `M11.CHANNEL.CHOI-1Q` | `choi` of `bit_flip(p)` ≈ analytic `(1−p)J(id) + p·J(Ad_X)`, several `p` |
| `M11.CHANNEL.COMPOSE` | `same_channel(bit_flip(p) ∘ bit_flip(q), bit_flip(p+q−2pq))` — exact, analytic |
| `M11.CHANNEL.KRAUS-FREEDOM` | a *different* family produced by a unitary mixing `u` satisfies `same_channel(a,b)` while `a != b` (the F26 split, with teeth) |
| `M11.CHANNEL.TENSOR-LOCALITY` | a `ChannelTensor` of three 1-local factors lowers to **three** `channel_1q` calls, never one `4³` superop — a structural regression test for V3 |
| `M11.CHANNEL.STRATIFICATION` | `MethodError` for `ctrl(bit_flip(0.1))`, `adjoint(𝓝)`, `X ∘ bit_flip(0.1)`, `bit_flip(0.1) ⊗ X`; `!(KrausFamily <: ProcessValue)`; `ApplyN(𝓝, …)` throws; `certify` of a real-family-bearing `NoiseN` DAG throws |
| `M11.NOISE.GUARDRAIL-1` | `when(c) do apply_noise!(q, ch) end` throws the guardrail-1 message on Eager **and** DM, **and** via `apply_channel!` directly — **closes `udtl`** |
| `M11.NOISE.REPLAY-CONTROLLED-REFUSES` | a `NoiseN` inside a `cases` arm under replay throws (pins V7's existing fail-closed branch) |
| `M11.NOISE.PASS-BARRIER` | `FuseUnitaryRunsPass` fuses on both sides of a `NoiseN` and moves nothing across it |
| `M11.NOISE.EAGER-LOUD` | Eager without the flag errors, naming `density`, `shots`, `stinespring=true` |
| `M11.NOISE.TRACING-RECORDS-CHANNEL` | a traced noisy program yields `NoiseN` with the real family **and no `AllocN`**, even when `stinespring=true` was passed |

**Stinespring**

| Test | Statement |
|---|---|
| `M11.DILATE.KRAUS-RECONSTRUCT` | `U[i·d+1 : i·d+d, 1:d] ≈ Kᵢ` for `i < R`, `≈ 0` for padded `i` — **this assertion IS the contract**; everything else follows algebraically |
| `M11.DILATE.ISOMETRY` | `V†V ≈ I` for every catalogue family and for random valid families (TP ⟺ isometry) |
| `M11.DILATE.EXACT-COLUMNS` | `U[:, 1:d] == Ṽ` **bitwise** (S9 makes this exact, not toleranced) |
| `M11.DILATE.UNITARY` | `‖U†U − I‖_∞ ≤ STINESPRING_ATOL` |
| `M11.DILATE.DETERMINISM` | `dilate(ch).unitary == dilate(ch).unitary` bitwise — no RNG, no tie-break drift |
| `M11.DILATE.ENV-LEADING` | the S10 pin, on `amplitude_damping(0.3)` — non-unital and asymmetric, so a swapped env/data ordering yields a **different channel** the test can see (a Pauli channel cannot detect it) |
| `M11.DILATE.DENOTES-THE-CHANNEL` | matrix level, general families incl. ones **outside** the executable catalogue: `Tr_E[U(\|0⟩⟨0\|_E ⊗ ρ)U†] ≈ 𝓝(ρ)` for random ρ |
| `M11.DILATE.CHOI-EQUALS-KRAUS` | **three-way** DM agreement — structured emission ≡ dense artifact ≡ native `channel_1q` ≡ analytic, for `bit_flip`, `depolarizing`, **`amplitude_damping`** (class D, S14) |
| `M11.DILATE.CTRL-UNREACHABLE` | `@test_throws MethodError ctrl(dilate(ch))`; subtypes neither `ProcessValue` nor `ChannelValue`; `ApplyN(dilation, …)` throws; `apply_pass` cannot see it; **source lint** on `_emit_dilation!(` / `StinespringDilation(` |
| `M11.DILATE.NOT-IN-IR` | `apply_noise!(::TracingContext, ch; stinespring=true)` throws |
| `M11.DILATE.ENV-OWNERSHIP` | `live_wires` returns to baseline; 100 sequential dilated applications do not grow the slot high-water mark |
| `M11.DILATE.CATALOGUE-BOUNDARY` | a class-X family throws, naming the missing kernel capability and the two escapes |
| `M11.DILATE.EAGER-TRAJECTORY` | Eager with the flag runs; `shots(…; N ≥ 2000)` agrees with the DM-exact marginal at ±3σ |

**QECC**

| Test | Statement |
|---|---|
| `M11.CODE.VALIDATION` | each of the six invariants (S17) rejected on a purpose-built bad code; the **table** self-validation (S20) rejected on a mis-entered table |
| `M11.CODE.DISTANCE-IS-ONE` | `verify_distance(bit_flip_code()) == 1` (witness `Z₁`). The suite refuses to imply "distance 3" |
| `M11.QECC.CODESPACE` | the encoder maps into the joint `+1` eigenspace: applying each stabilizer to an encoded state leaves the DM invariant |
| `M11.QECC.ENCODE-DECODE-ID` | `Choi(decode_state ∘ encode_state) ≈ Choi(id)`, 4×4 logical Choi, **coherently probed** (a Bell half — the wm28 gate) |
| `M11.QECC.EFFECTIVE-NOISE-EXACT` | `Θ(physical_iid(enc, bit_flip(p))) ≈ bit_flip(3p² − 2p³)` at the Choi level, `p ∈ {0.01, 0.05, 0.1, 0.3, 0.5, 0.7}`, `atol = 1e-12` |
| `M11.QECC.BREAK-EVEN` | **two-sided**: `p_L < p` for `p < ½` (`p=0.1`: `0.028 < 0.1`) **and** `p_L > p` for `p > ½` (`p=0.6`: `0.648 > 0.6`); exact break-even `(2p−1)(p−1)=0`. Correction that *hurts* above break-even is physics; a one-sided "protection helps" test would pass a sign-flipped recovery table |
| `M11.QECC.PHASE-NOISE-IS-WORSE` | **the wm28-shaped anti-test.** `Θ(physical_iid(enc, phase_flip(p))) ≈ phase_flip((1−(1−2p)³)/2) ≈ 3p`: the bit-flip code **amplifies** phase noise. A population-only probe is blind to this; the Choi test is not |
| `M11.QECC.INDEPENDENT-REFERENCE` | for `depolarizing(p)`, the expected logical Pauli channel is computed by a **test-side brute-force enumerator** over all `4³` Pauli patterns (syndrome → table correction → residual class) and compared to the executed Choi — an independent reference implementation, not a pinned number (principle 3) |
| `M11.QECC.SYNDROME-DISTRIBUTION` | `record_distribution(s)` gives `P(0) = (1−p)³ + p³`, `P(1)=P(2)=P(3)=p(1−p)²+p²(1−p)` |
| `M11.QECC.SYNDROME-TOKEN-REUSE` | one token drives all three corrections and the resulting record/data correlation is probed **coherently** (X on one wire, Z on another). Re-measuring per correction would decohere the record and change the logical channel — and a population-only probe would not notice |
| `M11.QECC.SURFACE-BOUNDARY` | all six S25 refusals throw with their code-specific messages |
| `M11.QECC.SUPERCHANNEL-TYPING` | arity mismatch loud; `effective_logical_noise(::ChannelValue, code)` points at `physical_iid`; result is `LogicalChannel{C}` with `K` ports; `MethodError` for `ctrl(Φ)` and `ctrl(Protect(enc))` |
| `M11.QECC.FT-LIFT-HONEST` | throws; the message names all five ingredients |
| `M11.TRANSFORM.LAW` / `.IDENTITY` | the two registry-enforced laws (S23) + the boot lint asserting every registered transform has both |
| `M11.DAG.COMPOSE-RELABEL` | `∘` on two independently traced DAGs with colliding `PortID`s gives the right channel (Choi-checked); **negative control**: naive concatenation does not |
| `M11.PORTABLE.SYNDROME` | the acceptance example runs unchanged under Eager (`shots`, N≥1000, ±3σ), DM (exact), Tracing (materialises `MeasureN` + `CasesN`), and the DM replay of the traced DAG reproduces the DM-streamed Choi |

**Analysis**

| Test | Statement |
|---|---|
| `M11.CLASSICALISE.STOCHASTIC` | columns sum to 1; id / bit-flip / Hadamard channels give the expected matrices; a 2-in/2-out DAG gives a **4×4** — the v0.1 silent-single-qubit defect cannot recur |
| `M11.CLASSICALISE.IS-PHASE-BLIND` | `classicalise(id) == classicalise(Ad_Z)`, asserted **deliberately**, with the comment naming why `classicalise` is never a channel-equivalence test (the F3-barred criterion) |
| `M11.CLASSICALISE.QECC` | `classicalise(Θ(𝓝_p))[2,1] ≈ 3p² − 2p³` — the quantitative statement read off a value |
| `M11.RECORD.NO-BACKACTION` | `density_matrix` bitwise identical before/after |
| `M11.RECORD.DERIVED-CORRELATION` | for `n = !m`, the two distributions are exact complements (shared-base-wire law L6); the joint form matches the joint diagonal |
| `M11.RECORD.LOUD` | Eager → `MethodError`; Tracing → descriptive error; after `discard!` → loud, naming the last-use rule; over-wide fan-in → the `CASES_MAX_FANIN` message |
| `M11.RECORD.NOT-A-VALUE` | the return type has no truth value, so `if record_distribution(t) …` cannot compile into a branch on an outcome |

---

## §7 — Physics prerequisites (deduplicated; **new CLAUDE.md rule 4**)

⚠ **Policy changed this session.** Rule 4 now reads: **commit the `.md`
distillation; the PDF stays local and gitignored** (`git ls-files docs/physics/`
→ 0 PDFs, V16). Both proposals' work items say "PDF + distillation" — **stale**.
No work item below asks for a PDF to be committed.

A named 6 distillations, B named 8. Deduplicated and re-sourced: **6**, of which
**2 are already sourced on disk**.

| # | Distillation | Source status | Must pin | Cited by |
|---|---|---|---|---|
| **P1** | `watrous_2018_channel_representations.md` | ✅ **on disk** — `docs/literature/watrous_2018_theory_of_quantum_information.pdf` | §2.2.2: **Thm 2.22** (Kraus ↔ Stinespring ↔ Choi equivalence); **Cor. 2.21 / 2.27** (minimal Kraus rank = Choi rank); **Cor. 2.27(5)** (the isometry form — *literally F33's* `V\|ψ⟩ = Σᵢ Kᵢ\|ψ⟩\|i⟩_E`); **Cor. 2.23 / 2.24** (non-uniqueness / unitary freedom) | `channel_values.jl` (TP is the only obligation), `stinespring.jl` (isometry, padding, completion ambiguity), `same_channel` |
| **P2** | `gottesman_1997_stabilizer_codes.md` | ✅ **on disk** — `docs/literature/quant-ph_9705052.pdf` + `_src` | §3.2 stabilizer formalism, `[[n,k,d]]`, syndrome measurement, logical operators; §5 transversality; **§6.2–6.3 the threshold theorem** | `qecc/codes.jl`, `qecc/ft.jl` |
| **P3** | `knill_laflamme_1997_qec_conditions.md` | ❌ **needs a source** — PRA 55 900 is paywalled; use **arXiv quant-ph/9604034** | the QEC conditions `P Kᵢ†Kⱼ P = α_{ij} P` — why a table decoder is *exact* on the declared correctable set, and why `Θ(𝓝) = id_L` is the correctability statement rather than a precondition | `qecc/codes.jl`, `qecc/superchannel.jl` |
| **P4** | `chiribella_2009_quantum_combs.md` | ❌ **needs a source** — arXiv:0712.1325 (PRL 101 060401) + arXiv:0904.4483 (PRA 80 022339) | superchannel = circuit with a hole; the factorisation `Θ(𝓝) = Tr_M[D∘(𝓝⊗id_M)∘E]`; the memoryless case | `qecc/superchannel.jl` — the argument that licenses the DAG-transformation modelling |
| **P5** | `eastin_knill_2009_no_universal_transversal.md` | ❌ **needs a source** — arXiv:0811.4262 (PRL 102 110502) | the no-go: no code admits a universal transversal gate set | `qecc/ft.jl` — makes the `fault_tolerant_lift` refusal a **theorem**, not a gap |
| **P6** | `repetition_code_effective_noise.md` | n/a — **an in-repo derivation note, not a paper distillation**; label it as such | `p_L = 3p² − 2p³`; `p_L − p = −p(1−p)(1−2p)` so break-even is exactly `p = ½`; the phase amplification `(1−(1−2p)³)/2 ≈ 3p` and *why* (every `Z_i` is a logical `Z̄` with trivial syndrome, so no correction ever fires); the `4³` depolarizing enumeration | the QECC tests |

**Dropped from the proposals, with reasons:**
- A's `stinespring_1955_dilation.md` — **superseded by P1.** Stinespring 1955 is
  a C\*-algebra paper; Watrous is finite-dimensional, free, author-hosted, and
  covers the exact equation F33 names.
- B's `choi_1975_cp_maps.md` — **folded into P1** (Watrous Thm 2.22 gives the
  CP ⟺ Kraus ⟺ Choi equivalence and the non-uniqueness in one place).
- A's `shor_1995_reducing_decoherence.md` — **dropped.** Its only job was
  `p_L = 3p²−2p³`, which is two lines of combinatorics; P2 covers the code content.
- A's/B's `aliferis_2006_ft_threshold.md` — **dropped from M11.** Per V17/P2, the
  threshold theorem is derived in Gottesman §6.2–6.3, so no separate source is
  needed for a *refusal message*. AGP (quant-ph/0504218) is cited by arXiv id in
  prose only — **no `docs/physics/` path**, so the lint is unaffected. Deferred
  to the FT epic.
- **Already present, no work item:** `tang_wright_2025_controlled_unitaries.md`
  (Thm 1.1 — control makes representation-level freedom observable; the artifact
  rule's teeth), `delorme_control_as_constructor.md`,
  `hagan_wiebe_2023_composite.md` (the `PauliWord` provenance).
- **No distillation is owed** for the Householder completion (numerical linear
  algebra; Golub & Van Loan §5.1–5.2 in a code comment) or for the
  real-amplitude preparation tree (a two-line induction, proved inline). S9's
  choice of Householder over Gram–Schmidt also dissolves B's flagged two-tier
  awkwardness about a "twice is enough" reorthogonalisation note.

---

## §8 — Research steps carried into implementation (rule 8)

- **R1 (S14).** Verify the kernel's `Ry` sign/phase convention against the class-D
  damping circuit *before* trusting the emitter: `Ry(2θ)|0⟩ = cosθ|0⟩ + sinθ|1⟩`
  is assumed. A wrong sign yields `K₁ = −√γ|0⟩⟨1|`, which is the *same channel*
  and would pass a Choi test — so this must be pinned at the **matrix** level
  (`M11.DILATE.KRAUS-RECONSTRUCT`), not at the channel level.
- **R2 (S28).** Confirm that `_remap_nodes`/`_rebase` in `block_algebra.jl`
  generalise to nodes carrying `PortID`s that `UnitaryBlock` never holds
  (`MeasureN.out`, `CasesN.sel`, `NoiseN.ports`, nested branch DAGs) before
  reusing them, rather than assuming it.
- **R3 (S25/S18).** `certify(trace(bitflip_encode!, 3))` must mint a `NoAncilla`
  certificate — verify the traced DAG really has matching in/out lineage in order
  and contains only `ApplyN`s. If it does not, S18 needs the alloc/trace pair
  handled explicitly, and the encoder-as-`UnitaryBlock` ruling needs revisiting.
- **R4 (S31).** Confirm `record_distribution`'s reduced-diagonal read against
  `test/choi.jl`'s `_ptrace_keep` index convention — this is a third endianness
  site and must be cross-checked, not assumed.
- **R5 (deferred k-local).** If the k-local DM path is ever revived: verify
  `state_set` round-trips on `MIXED_TILED` including the Hermitian partner
  (`set(get(ρ)) == ρ`) before relying on write-back. B correctly refused to
  assume this.

---

## §9 — Risks

| # | Risk | Mitigation |
|---|---|---|
| R-a | The `NoiseN`/`KrausFamily` reshape touches a shipped frozen IR struct | Blast radius enumerated (V5: 4 files, no algorithm changes). Land it as its own slice with `test_m8_channel.jl` green before anything else. |
| R-b | **Three endianness conventions must agree**: `apply!` MSB-first, `_ptrace_keep`'s `keep[1]`-MSB, and the dilation's env-leading rows | One function per pin, one named test per pin; the dilation test uses a non-unital asymmetric channel so a swap is *visible* (S10); R4 cross-checks the third. |
| R-c | `∘(::ChannelDAG, ::ChannelDAG)` is the most intricate new code and a silent bug there is wm28-class | Choi law test + a **negative control** that naive concatenation fails; recursive `CasesN` remapping called out explicitly (S28); R2. |
| R-d | `p_L = 3p²−2p³` is only right if the recovery table is right, and a sign-flipped table still "looks protective" at small `p` | **Four** independent pins: table self-validation at construction (S20), the two-sided break-even test, the exact syndrome distribution, and the brute-force independent reference enumerator. |
| R-e | Someone reads the Eager dilation as the channel | Required greppable flag; docstring says "one unravelling"; `shots` named in the message; M12's S10 guard is the precedent. |
| R-f | Scope creep into fault tolerance via encoded-block methods | S25 ships **zero** logical operations; every construct is a refusal naming what it would need. |
| R-g | `NTuple` specialisation blowup across many `(W,R)` combinations | `KRAUS_MAXDATA = 1024`; the realistic concrete set is ~6 types; documented fallback to a non-concrete `NTuple{L,ComplexF64} where L` field. |
| R-h | The M12 forward reference to "M11's mixture value" stays stale | Softened in the same commit (§4.2 / **T6**). |

---

## §10 — Open questions needing a Tobias ruling

> ## ✅ ALL SIX RULED — Tobias, 2026-07-25 (session 103): *"approve it all"*
>
> Every recommendation in the table below is **APPROVED AS RECOMMENDED**. M11
> implementation is unblocked. Specifically:
>
> - **T1 APPROVED.** Replace the PRD §5 QECC text (`Sturm-PRD-v2.md:1415`,
>   *"QECC (P6): unchanged — `encode(ch, code)` is `Channel → Channel`"*) and
>   the §1445 P6 restatement with the three typed operations. **This closes
>   carried-contract verdict (c)** — the last one in plan §7 — so after this
>   pass every carried v0.1 contract is either re-derived or re-verified, and
>   the reboot's contract audit is COMPLETE. Do it as its own reviewed pass,
>   NOT folded into M11 implementation commits (round 6's lesson: normative
>   content buried in prose escapes review). Carries §4.3, §3.8, §9 edits.
>   The **§4.4 two-strata → three-strata** table is the high-value edit:
>   process values / channel **representations** / denotations. Rationale to
>   preserve in the PRD text — today "`ctrl` cannot touch a channel" is true
>   partly *for lack of any object to try it on*; `KrausFamily` destroys that
>   accident, so the middle stratum must carry the explicit theorem that a
>   channel's representation is non-unique exactly in the ways `ctrl` can see
>   (Kraus freedom; Stinespring uniqueness only up to partial isometry;
>   Tang–Wright), hence controlling one would make the observable result
>   depend on an arbitrary representative.
> - **T2 APPROVED**, both parts: `classicalise` gets an explicit §7
>   carried-contract verdict **(c) re-derived** per S31, AND the name split
>   `classicalise` (v0.1 meaning: channel → column-stochastic matrix, arity
>   from ports) vs `record_distribution` (token introspection) stands. No
>   `-ize` alias.
> - **T3 APPROVED as recommended: ship NO logical operations on a
>   `CodeBlock`.** `not!`, `Bool`, `⊻=`, `dual`, `when`, `oracle` all refuse
>   loudly. This overrides proposer B's recommendation to ship `not!`/`Bool`.
>   Reason of record: on a noisy block "transversal measure + majority" and
>   "decode then measure" are DIFFERENT CHANNELS, so offering either under the
>   `Bool` cast spelling silently picks a protocol — F8 reappearing at the
>   cast level, inside the milestone whose job is to close F8.
> - **T4 APPROVED:** `encode_state` is an **ownership transfer**, not a third
>   consumption site. Implement on the shipped consumed set so misuse is loud
>   today; §4.5's "exactly two places" count stands unchanged.
> - **T5 APPROVED:** the line is *"export what a program does to itself; keep
>   `public` what the experimenter does to a program."* ⇒ `export
>   encode_state, decode_state`; everything else `public` (`apply_noise!`, the
>   named families, `StabilizerCode`, `CodeEncoding`, `Protect`,
>   `effective_logical_noise`, `classicalise`, `record_distribution`,
>   `StinespringDilation`, `fault_tolerant_lift`).
> - **T6 APPROVED in principle, scheduled AFTER M11.** Orkan `unitary_kq` is
>   cross-repo work with its own ABI re-verification discipline (plan §7
>   verdict (b): re-verified against live headers, never trusted from a
>   branch). The KAK/QSD alternative needs its own 3+1 round, because it would
>   be a new constructor of controlled lowerings and must go through the
>   `ctrl` choke point.
>
> Not a ruling, recorded for awareness: M12's `_assert_randomized_legal`
> over-promises that M11 closes DM-randomized `evolve!`. It does not
> (`MixedUnitary{W,R}` targets enumerated `R ≤ 16`; qDrift needs `R ~ 10⁴`).
> The S10 guard is sound and stays; only the forward promise needs softening.
> Bead `Sturm.jl-83a8`.

A raised 7, B raised 9. Nine of those I decided (S3, S6, S9, S13, S14, S25 with
escalation, S28, S31, plus the `LinearAlgebra` question — the ruling *keeps*
CLAUDE.md conv 4 unchanged, so there is nothing to rule on). Six remain that
genuinely need you.

| # | Question | Recommendation |
|---|---|---|
| **T1** | **PRD §5 normative edit.** `Sturm-PRD-v2.md` §5 still reads *"QECC (P6): unchanged — `encode(ch, code)` is `Channel → Channel`"*. This design deletes it. Replacing it **is** the closure of carried-contract verdict **(c)** — the single remaining (c) in plan §7. Related staged edits: §4.3 (the `ChannelValue` application row + pure-context policy), §4.4 (the two-row stratification becomes three: process values / channel **representations** / denotations), §3.8 (a noise row in the portability table), §9 (the six distillations). | Stage the text in this design doc; apply it in a dedicated PRD pass with its own review, not inside the M11 implementation commits. The three-stratum §4.4 table is the highest-value edit — it is what makes "no `ctrl` on stratum 2" a stated theorem rather than an emergent property. |
| **T2** | **`classicalise` is an unlogged v0.1 carried contract.** Verified (V10): it appears **nowhere** in the v2 plan or PRD-v2; it exists only in `Sturm-PRD.md` §Noise, and its v0.1 contract text carries a silent single-qubit defect in the *spec itself* (`Sturm-PRD.md:457`: *"returns 2×2 column-stochastic matrix"*). So it needs a §7 verdict like the other six carried contracts, and the brief's framing ("the plan names it") was wrong. S31 re-derives it (channel → column-stochastic matrix, arity from ports) and gives the token introspection the separate name `record_distribution`. | Ruling wanted on **two** things: (i) that `classicalise` gets an explicit §7 carried-contract verdict — I recommend **(c) re-derived**, as spec'd in S31; (ii) the name split. I recommend keeping `classicalise` for the v0.1 meaning and `record_distribution` for the token side — merging them would be exactly the sample/record/assert conflation §3.6 exists to prevent. Single spelling, no `-ize` alias. |
| **T3** | **How much surface survives encoding.** S25 ships **no** logical operations on a `CodeBlock` — `not!`, `Bool`, `⊻=`, `dual`, `when`, `oracle` are all refusals. Proposer B recommended shipping `not!(blk)` (as the declared `X̄`) and `Bool(blk)` (transversal measure + majority). | **Ship none.** `not!(blk)` alone is defensible, but `Bool(blk)` is not: "transversal measure + majority" and "decode, then measure" are two *different channels* on a noisy block, and offering one under the cast spelling silently picks a protocol — F8 reappearing at the cast level, in the milestone whose job is to close F8. Shipping `not!` without `Bool` is an odd half-measure that invites the general case. B itself calls the conservative line defensible. Escalated because B recommended otherwise. |
| **T4** | **`encode_state` ownership.** PRD §4.5 says consumption happens in "exactly two places" (qc casts and `ptrace!`). `encode_state` is neither — information is not leaving the program, it is being *re-homed* into a block. §3.9 already contemplates "an explicit ownership transfer (D2)". | Implement it on the shipped consumed set either way (so misuse is loud today) and rule the **wording**: I recommend **ownership transfer**, not a third consumption site. Consumption means the quantum handle's information left; here it did not — it changed owner. Calling it consumption would make §4.5's count a lie in a different direction. |
| **T5** | **Export vs `public`.** A recommends exporting **nothing** new ("a program does not apply noise to itself; the environment does"). B recommends exporting the physicist verbs, citing the M10/M12 precedent — which is real (V12: `evolve!`, `amplify`, `Trotter`, `QDrift` are all exported). | Neither, quite. I recommend the line **"export what a program does to itself; keep `public` what the experimenter does to a program"**: `export encode_state, decode_state` (a program genuinely encodes its own state — that is the P6 promise); everything else `public` — `apply_noise!`, the named families, `StabilizerCode`, `CodeEncoding`, `Protect`, `effective_logical_noise`, `classicalise`, `record_distribution`, `StinespringDilation`, `fault_tolerant_lift`. This keeps A's physics argument for noise while honouring B's precedent where the precedent actually applies. |
| **T6** | **Orkan `unitary_kq` cross-repo work item.** It is the difference between "general dilation constructed and verified" (what M11 ships) and "general dilation executable", and it would also unblock correlated multi-qubit noise. Sketch: `void unitary_kq(state_t*, const cplx_t* u, const qubit_t* targets, uint8_t k)`. | **Approve in principle, schedule after M11 ships.** It is an Orkan-side change with its own ABI verification discipline (plan §7 verdict (b): never trusted from a branch, always re-verified against live headers), and M11's honest gap is narrow — general 1-local channels on a *pure* context (answer today: use `density`) and genuinely correlated multi-qubit noise (not needed by anything in M11). The alternative route, a KAK/QSD synthesis pass, must be its own 3+1 round because it would be a **new constructor of controlled lowerings** and must go through the `ctrl` choke point. |

**Also for your awareness (not a ruling, a disclosure):** M12's
`_assert_randomized_legal` (`src/library/evolve/evolve.jl:123`) tells users that
"the DM lowering of the ensemble is M11's mixture value". **M11 as scoped here
does not close that** — `MixedUnitary{W,R}` targets the enumerated `R ≤ 16` case,
not qDrift's `R ~ 10⁴`. I recommend softening that message in the same commit and
filing `EnsembleChannel` as its own bead, rather than leaving a stale forward
reference in a shipped error string.
