# Sturm.jl Work Log

Gotchas, learnings, decisions, and surprises. Updated every step.

---

## 2026-04-05 — Session 1: Project bootstrap

### Steps 1.1–1.6 — Project scaffold + Orkan FFI (all complete)
- **Gotcha: `Libdl` is a stdlib but still needs `[deps]` entry** in Project.toml on Julia 1.12. Otherwise `using Libdl` fails at precompile time.
- **Gotcha: Julia `π` is `Irrational`, not `Float64`.** Rotation wrapper signatures must accept `Real`, not `Float64`. Convert via `Float64(theta)` at the `@ccall` boundary.
- **Gotcha: Orkan qubit ordering = LSB.** Qubit 0 is the least significant bit of the basis state index. `|011>` = index 3 means q0=1, q1=1, q2=0. This is standard (same as Qiskit), but must be kept in mind for all multi-qubit tests.
- **Decision: single `ffi.jl` file** for all raw ccall wrappers (state + gates + channels). Used `@eval` loop to generate the 18 gate wrappers from name lists — avoids boilerplate.
- **Decision: `OrkanState` managed handle** uses Julia finalizer for automatic cleanup. The `OrkanStateRaw` is embedded (not heap-allocated separately), so no double-indirection.
- **No `measure()` in Orkan** — confirmed. Sturm.jl implements `probabilities()` and `sample()` in Julia by reading amplitudes from the Orkan state data pointer.
- 44 tests pass: struct sizes, state lifecycle, all gate types, Kraus→superop, managed handle, sampling.

## 2026-04-05 — Session 2: OOM crash recovery + memory safety

### WSL2 OOM crash investigation
- **Root cause: capacity doubling is exponential-on-exponential.** EagerContext doubled capacity (8→16→32 qubits). State memory is 2^n × 16 bytes, so doubling n from 16→32 goes from 1 MB to 64 GB. WSL2 has ~62 GB — OOM.
- **Contributing factor: OpenMP thread oversubscription.** No `OMP_NUM_THREADS` set, so Orkan spawned 64 threads (Threadripper 3970X) on top of Julia's threads.
- **Contributing factor: Orkan calls `exit()` on validation failure** via `GATE_VALIDATE`, killing the whole Julia process with no chance to catch.

### Fixes applied
- **Replaced doubling with additive growth.** `_grow_state!` now adds `GROW_STEP=4` qubits per resize, not 2×. Growth from 8→12→16→20 instead of 8→16→32.
- **Added `MAX_QUBITS=30` hard cap** (16 GB). `error()` with clear message if exceeded.
- **Added memory check before allocation.** Refuses to grow if new state would consume >50% of free RAM.
- **Set `OMP_NUM_THREADS` automatically** to `CPU_THREADS ÷ 4` (16 on this machine) in `__init__()`.
- **Gotcha: `ENV` mutations in top-level module code run at precompile time, not load time.** Must use `__init__()` for runtime side effects like setting environment variables.
- **Added `EagerContext` constructor guard** — rejects initial capacity > MAX_QUBITS.
- 8 new tests in `test_memory_safety.jl`. 4668 total tests pass.

### Bug fixes and missing tests
- **Bug: `Base.copy(::OrkanState)` called `new()` outside inner constructor.** Added private `OrkanState(::OrkanStateRaw)` inner constructor. Added copy test.
- **Missing tests added:** T! phase test (H·T·H gives P(1)≈sin²(π/8)), phi+theta deterministic combo (Ry(π/2)·Rz(π)·QBool(0.5) = |0⟩ deterministically — NOT |1⟩ as naively expected; Ry(π/2)|-> = |0⟩), XOR with consumed qubit throws.
- **Gotcha: Ry(π/2)|-> = |0⟩, not |1⟩.** Easy to get wrong by thinking "Ry rotates toward |1⟩". The Bloch sphere rotation direction matters: Ry(+π/2) rotates from -X toward +Z, i.e. |-> → |0⟩.

### Step 4.6: RUS T-gate
- **PRD §8.3 has a physics error.** The `rus_T!` code applies `anc ⊻= target` twice — CX·CX = I, so the ancilla is never entangled with the target. The protocol becomes a random phase walk, not a T gate. Verified numerically: P(1) ≈ 0.46 vs expected 0.15.
- **Implemented correct `t_inject!` via magic state injection.** Prepare |T⟩ = (|0⟩+e^{iπ/4}|1⟩)/√2 on ancilla, CX(target→anc), measure anc. If anc=1, apply S correction (T²·T†=T). Deterministic — always succeeds in 1 shot. Verified: matches direct T! to within statistical noise (N=10000).
- Kept PRD version as DSL control-flow demo (tests loop mechanics, dynamic allocation in loops).
- 5079 total tests pass.

### Phase 6: QInt{W} type and arithmetic (Steps 6.1–6.3)
- **3+1 agent protocol used** for core type design. Two independent proposers (Sonnet), orchestrator synthesised best elements from both.
- **Key design decision: separated carry computation from sum computation** in the ripple-carry adder. Initial implementation mixed them, causing `_carry_uncompute!` to corrupt sum bits. Fix: carry-only forward pass (3 Toffolis per stage, a/b untouched), then sum computation (2 CNOTs per stage), then carry uncompute with temporary b restoration.
- **Gotcha: subtraction via `QInt{W}(ctx, 1)` blows up qubit count.** Creating a full W-bit register just for +1 adds W qubits + W carry ancillas. Solution: `_add_with_carry_in!(ctx, a_wires, b_wires, true)` — fold +1 as initial carry-in, eliminating the extra register entirely.
- **Comparison operators use measure-then-compare for v0.1.** Fully quantum comparison (without measurement) requires the Bennett trick for garbage uncomputation — deferred to Phase 8 (TracingContext can express this cleanly). Current implementation consumes both inputs and returns a fresh QBool.
- **Proposer A** designed per-wire `Vector{Bool}` tracking and VBE-style 3-Toffoli+2-CNOT carry stages.
- **Proposer B** designed lazy QBool caching (`_bits` NTuple), non-destructive comparison (invalid — violates no-cloning for superposed inputs), and carry-in parameter trick.
- **Synthesis**: simple struct (no per-wire tracking), carry-in trick from B, carry-only forward pass (own design after both proposals had bugs), measure-based comparison (honest about v0.1 limitations).
- 5646 total tests pass (exhaustive QInt{4} addition: 256 cases, subtraction: 256 cases).

### Phase 7: Library patterns (Steps 7.1–7.3)
- **QFT uses CRz, not CP.** `when(ctrl) { qj.φ += angle }` produces CRz(angle), not the standard CP(angle). These differ by a local phase on the control qubit. For QFT measurement statistics they are equivalent, but eigenvalues differ — affects QPE tests.
- **Gotcha: Z!/S!/T! are Rz, not standard Z/S/T.** Z! = Rz(π) has eigenvalue e^{iπ/2} on |1⟩, not -1. This is correct per our gate definitions (gates.jl: Z! = q.φ += π), but QPE tests must use Rz eigenvalues, not standard gate eigenvalues. Cost me a test debugging cycle.
- **Research: Python `../sturm/` project has parallel QFT/QPE implementations.** Key findings: Python uses CP decomposition (5 primitive ops) while Julia uses CRz (1 when+φ op, simpler). Python has `cutoff` parameter for approximate QFT and `power` callback for QPE — both deferred to future work. Python flagged virtual-frame absorption as a pitfall (Session 8 bug) — not yet relevant to Julia but worth watching.
- **Physics citation: Nielsen & Chuang §5.1 (QFT), §5.2 (QPE).** N&C textbook PDF not in `../sturm/docs/physics/` — reference doc written from equations.
- `superpose!`, `interfere!`, `fourier_sample`, `phase_estimate` all implemented and tested.
- QFT-iQFT roundtrip verified for all 3-bit states (8 cases, deterministic).
- Deutsch-Jozsa: constant oracle → 0 (100%), balanced oracle → nonzero (100%).
- QPE: Z! on |1⟩ → result=2 (φ=0.25), S! on |1⟩ → result=1 (φ=0.125). Correct for Rz eigenvalues.
- 5738 total tests pass.

### Phase 8: TracingContext, DAG, Channel, OpenQASM (Steps 8.1–8.6)
- **DAG nodes**: PrepNode, RyNode, RzNode, CXNode, ObserveNode, CasesNode, DiscardNode. Each carries a `controls::Vector{WireID}` for when() context.
- **TracingContext** implements all AbstractContext methods symbolically: allocate!/deallocate! manage WireIDs, apply_ry!/rz!/cx! append nodes, measure! appends ObserveNode and returns a placeholder Bool (false = default branch in tracing).
- **ClassicalRef** for symbolic measurement results (stub — full classical branching deferred).
- **trace(f, n_in)** creates TracingContext, runs f with n_in symbolic QBool inputs, returns Channel{In,Out} with captured DAG.
- **Channel composition**: `>>` (sequential, wire renaming), `⊗` (parallel, concatenation).
- **to_openqasm(ch)** exports to OpenQASM 3.0: Ry→ry, Rz→rz, CX→cx, controlled→cry/crz/ccx, ObserveNode→measure.
- **Decision: measure! returns false as default path in tracing.** Full classical branching (CasesNode with both paths) requires running f twice — deferred to a future enhancement.
- 5781 total tests pass.

### Phases 8-12 (continued in same session)
- **Phase 8**: TracingContext, DAG, Channel, trace(), >>, ⊗, to_openqasm(). 
- **Phase 9**: gate_cancel (rotation merging), defer_measurements (measure→control rewrite).
- **Phase 10**: DensityMatrixContext using MIXED_PACKED Orkan state. Same interface as EagerContext.
- **Phase 11**: depolarise!, dephase!, amplitude_damp! via Kraus→superop pipeline. classicalise() for stochastic maps. **Gotcha: plan's depolarising Kraus operators {√(1-p)I, √(p/3)X, √(p/3)Y, √(p/3)Z} are non-standard.** Fixed to {√(1-3p/4)I, √(p/4)X, √(p/4)Y, √(p/4)Z} so p=1→I/2 (maximally mixed).
- **Phase 12**: AbstractCode, Steane [[7,1,3]]. Encode/decode roundtrip verified for |0⟩, |1⟩, |+⟩. **Steane encoding circuit needs physics verification** — logical X_L test failed, indicating the CNOT network may not produce canonical codewords. Deferred to future work with full stabilizer verification.
- 8171 total tests pass across all 12 phases.

### Grover search & amplitude amplification
- **3+1 agent protocol used.** Two Opus proposers, orchestrator synthesised.
- **Proposer A** designed QBool-predicate API (oracle returns QBool, library handles phase kickback). **Physics bug:** discard! = measure = decoherence, so the predicate's garbage qubits collapse the superposition. Deferred to future API.
- **Proposer B** designed `find` naming (matches Julia `findfirst`) with `phase_flip!(x, target)` helper (no garbage qubits, physically correct).
- **Synthesis:** B's `find` + `phase_flip!` + `amplify`, B's Toffoli cascade, A's iteration formula.
- **Critical bug found: controlled-Rz(π) ≠ CZ.** `when(ctrl) { target.φ += π }` gives diag(1,1,-i,i), NOT diag(1,1,1,-1). The diffusion operator was applying wrong phases to non-target states. **Fix: `_cz!` function using CP(π) decomposition (2 CX + 3 Rz).** This is the same issue the Python sturm project documented as "Session 8 bug" — Rz vs P gate semantics.
- **Gotcha: H! = Rz(π)·Ry(π/2) is NOT self-inverse.** H!² = -I (not I). For Grover diffusion, H^⊗W works because -I is a global phase. But superpose!/interfere! (QFT) ≠ H^⊗W on arbitrary states — must use `_hadamard_all!` for Grover.
- `find(Val(3), target=5)` achieves 95% success rate (theory: 94.5%). 2-bit: 100%.
- 8452 total tests pass.

## 2026-04-05 — Literature Survey: Routing, CNOT Opt, Peephole

Completed systematic survey of qubit routing/mapping, CNOT optimization, peephole optimization, and pattern matching. 13 PDFs downloaded to `docs/literature/`.

Key findings for Sturm.jl DAG passes:
- SABRE (arXiv:1809.02573) is the canonical NISQ routing algorithm — bidirectional heuristic with decay effect for SWAP/depth tradeoff. Central insight: the "look-ahead" cost function over the front layer of the dependency DAG.
- Pattern matching (arXiv:1909.05270) works on DAG with commutativity — the Sturm DAG IR is exactly the right representation to apply this.
- Phase gadgets (arXiv:1906.01734) are directly implementable from Sturm's 4 primitives: a phase gadget on n qubits = (n-1) CNOTs + 1 Rz. CNOT tree synthesis is just the 4th primitive.
- ZX T-count (arXiv:1903.10477): ZX rewriting = generalized peephole on the ZX-diagram (which is a superset of the circuit DAG). High relevance to `passes/` optimization.
- DAG vs phase polynomial comparison (arXiv:2304.08814): phase polynomials outperform DAG for deep circuits on CNOT count. Relevant to future `passes/clifford_simp.jl`.
- OLSQ (arXiv:2007.15671): optimal routing via SMT — useful as a ground truth for correctness testing of SABRE-style heuristic in Sturm.

**Physics note:** Patel-Markov-Hayes (quant-ph/0302002) O(n²/log n) CNOT synthesis uses row reduction on the parity matrix — directly applicable to linear reversible subcircuits in the Clifford+T passes.

## 2026-04-05 — Literature Survey: Quantum Compiler Frameworks & Toolchains

Systematic survey of major quantum compiler frameworks, toolchain architectures, and survey/review papers. 12 new PDFs downloaded to `docs/literature/` (some duplicating existing files under canonical names).

### Papers surveyed (new to this session)

**QCOPT-SURVEY-2024** (arXiv:2408.08941): Karuppasamy et al. 2024 comprehensive review of circuit optimization — hardware-independent vs hardware-dependent, ML methods. Best broad entry point to the field.

**SYNTHESIS-SURVEY-2024** (arXiv:2407.00736): Yan et al. 2024 survey of synthesis+compilation — covers AI-driven qubit mapping, routing, QAS. Useful for understanding how DAG IR fits into the full synthesis-to-hardware pipeline.

**TKET-2020** (arXiv:2003.10611, already at `tket_Sivarajah2020.pdf`): Sivarajah et al. — t|ket⟩ retargetable NISQ compiler. Key architecture: language-agnostic, DAG IR, passes for routing + gate synthesis. The Sturm TracingContext+DAG design mirrors this architecture.

**QUILC-2020** (arXiv:2003.13961, already at `Quilc_Smith2020.pdf`): Smith et al. — quilc, Rigetti's open-source optimizing compiler for Quil/QASM. Uses a DAG with resource conflicts as the IR. Relevant: quilc's "nativization" pass (gate-set lowering) is exactly what Sturm needs for future hardware targeting.

**VOQC-2019** (arXiv:1912.02250): Hietala et al. — first fully verified quantum circuit optimizer in Coq. Uses SQIR (Simple Quantum IR). Key insight: a deep embedding of circuits in a proof assistant allows correctness guarantees on optimization passes. Directly relevant to Sturm's pass infrastructure if we ever want verified passes.

**STAQ-2019** (arXiv:1912.06070): Amy & Gheorghiu — staq C++ full-stack toolkit. Unix pipeline philosophy: each tool does one thing. AST-based (preserves source structure, not a DAG). Notable contrast with Sturm/Qiskit/tket's DAG approach.

**QISKIT-2024** (arXiv:2405.08810): Javadi-Abhari et al. — the definitive Qiskit SDK paper. Key for Sturm: confirms DAGCircuit as the canonical IR throughout the pass pipeline. PassManager pattern (sequence of passes on DAG) is the model Sturm's `passes/` should follow. Covers dynamic circuits (classical feed-forward) — relevant to Sturm's `when()` and `boundary`.

**MLIR-QUANTUM-2021** (arXiv:2101.11365): McCaskey & Nguyen — MLIR quantum dialect that compiles to LLVM IR adhering to QIR spec. Relevant: shows how to lower from a high-level DAG IR all the way to binary. Future direction if Sturm wants native compilation rather than OpenQASM export.

**OPENQASM3-2021** (arXiv:2104.14722): Cross et al. — OpenQASM 3 spec. Adds real-time classical control, timing, pulse control. Sturm's `to_openqasm()` targets OpenQASM 3 syntax. Key: the `when()` construct maps cleanly to OpenQASM 3 `if` statements with real-time measurement results.

**PYZX-ZX-2019** (arXiv:1902.03178, already at `KISSINGER_ZX.pdf`): Duncan, Kissinger et al. — ZX-calculus graph simplification. Asymptotically optimal Clifford circuits, T-count reduction. Already in library; re-tagged for compiler survey context.

**DAG-VS-PHASEPOLYNOMIAL-2023** (arXiv:2304.08814, already at `Meijer_DAG_vs_PhasePoly_2023.pdf`): Meijer-van de Griend — DAG (Qiskit/tket) vs phase polynomial IR comparison. Finding: phase polynomials outperform DAG for CNOT count in long circuits; DAG wins on speed and short circuits. Informs choice of IR for Sturm's `clifford_simp` pass.

**QUIL-ISA-2016** (arXiv:1608.03355): Smith, Curtis, Zeng — Quil instruction set architecture. The original hybrid classical-quantum memory model. Relevant as the conceptual predecessor to OpenQASM 3's classical control features.

**BQSKIT-QFACTOR-2023** (arXiv:2306.08152): Kukliansky et al. — QFactor domain-specific optimizer in BQSKit. Uses tensor networks + local iteration for circuit instantiation. Relevant: shows how numerical synthesis (not just rewrite rules) can be integrated into a compiler pipeline at 100+ qubit scale.

### Key architectural insights for Sturm.jl

1. **DAG is the right IR.** All major frameworks (Qiskit, tket, quilc, staq) converge on DAG as the canonical compilation IR. Sturm's TracingContext already produces a DAG. The `passes/` pipeline should operate on this DAG, not on a flat gate list.

2. **PassManager pattern.** Every framework uses some variant of: `circuit → DAGCircuit → [pass1, pass2, ...] → optimised DAGCircuit → circuit`. Sturm's `passes/` directory should expose this pattern explicitly, with a `run_passes(dag, [pass1, pass2])` entry point.

3. **Gate-set lowering ("nativization") is a separate pass from routing.** quilc makes this explicit. Sturm should follow suit: one pass lowers from 4-primitive DSL to target gate set, a separate pass handles qubit routing.

4. **OpenQASM 3 is the right export target.** Sturm's `when()` maps to OQ3 `if (cbit)` with real-time branching — OQ3 was designed for exactly this use case. The existing `to_openqasm()` in `channel/` is correct to target OQ3.

5. **Verified compilation is possible.** VOQC demonstrates that a small subset of optimization passes can be formally verified in Coq/SQIR. Sturm could adopt the same approach for its rotation-merging pass (gate_cancel.jl) — the proof would be straightforward since it only requires commutativity of Rz rotations on the same wire.

## 2026-04-05 — Session 2 continued: Grover, literature survey, channel safety

### Grover search & amplitude amplification
- **3+1 agent protocol (Opus proposers).** Proposer A: QBool-predicate API with phase kickback. Proposer B: `find`/`phase_flip!` naming with direct phase marking.
- **Proposer A's approach has a physics bug**: `discard!` = `measure!` = decoherence. The predicate's garbage qubits collapse the superposition when discarded. No general way to uncompute a predicate without reversible computation infrastructure.
- **Synthesis**: B's `find` + `phase_flip!` (physically correct, no garbage) + A's iteration formula.
- **Critical bug found and fixed: controlled-Rz(π) ≠ CZ.** `when(ctrl) { target.φ += π }` applies diag(1,1,-i,i), NOT diag(1,1,1,-1). The diffusion operator was applying wrong relative phases. Fix: `_cz!()` using CP(π) decomposition (2 CX + 3 Rz). Same bug as Python sturm "Session 8 bug."
- **Gotcha: superpose!/interfere! (QFT) ≠ H^⊗W on arbitrary states.** Both give uniform superposition on |0⟩, but they differ on non-|0⟩ inputs. Grover's diffusion requires H^⊗W (each qubit independently), not QFT. Created `_hadamard_all!` helper.
- **H!² = -I is physically correct.** H! = Rz(π)·Ry(π/2) = -i·H. The -i is a global phase (unobservable). The 4 primitives generate SU(2), not U(2). Channels are the physical maps, not unitaries — global phases don't exist at the channel level. Documented in CLAUDE.md to prevent future agents from "fixing" this.
- `find(Val(3), target=5)` achieves 95% success rate (theory: 94.5%). 2-bit: 100%.
- Infrastructure: `_multi_controlled_z!` via Toffoli cascade (Barenco et al. 1995), `_diffusion!`, `phase_flip!`.

### Literature survey: quantum circuit optimization (100 papers, 9 categories)
- **6 parallel Sonnet agents** (+ 1 follow-up for SAT/CSP) surveyed the complete field.
- **100 unique papers downloaded** (140 MB) to `docs/literature/`, sorted into 9 taxonomy subfolders:
  - `zx_calculus/` (18): Coecke-Duncan → van de Wetering. ZX rewriting, PyZX, phase gadgets, completeness theorems.
  - `t_count_synthesis/` (14): Amy TPAR/TODD, gridsynth, Solovay-Kitaev, exact synthesis. Phase polynomial framework.
  - `routing_cnot_peephole/` (6): SABRE, PMH CNOT synthesis, Iten pattern matching, Vandaele phase poly for NISQ.
  - `ml_search_mcgs/` (15): **Rosenhahn-Osborne MCGS trilogy** (2023→2025→2025), RL (Fosel, IBM Kremer), AlphaZero, MCTS variants, generative models.
  - `phase_poly_resource_ft/` (7): Litinski lattice surgery, Beverland resource estimation, Fowler surface codes, Wills constant-overhead distillation.
  - `compiler_frameworks/` (12): Qiskit, tket, quilc, VOQC (verified), staq, BQSKit, MLIR quantum, OpenQASM 3.
  - `sat_csp_smt_ilp/` (18): SAT/SMT layout synthesis (OLSQ → Q-Synth v2), SAT Clifford synthesis (Berent-Wille MQT line), MaxSAT routing, ILP (Nannicini), MILP unitary synthesis, AI planning (Venturelli, Booth), lattice surgery SAT (LaSynth).
  - `decision_diagrams_formal/` (6): QCEC, LIMDD, FeynmanDD, Wille DD review.
  - `category_theory/` (4): Abramsky-Coecke, Frobenius monoids, string diagram rewrite theory (DPO).
- **6 Sonnet synthesis agents** produced per-category summaries with pros/cons/limitations/implementability/metrics/recommended order/open problems.

### Key finding: Rosenhahn-Osborne MCGS trilogy is the unique competitive advantage
- **MCGS-QUANTUM** (arXiv:2307.07353, Phys. Rev. A 108, 062615): Monte Carlo Graph Search on compute graphs for circuit optimization.
- **ODQCR** (arXiv:2502.14715): Optimization-Driven QC Reduction — stochastic/database/ML-guided term replacement.
- **NEURAL-GUIDED** (arXiv:2510.12430): Neural Guided Sampling — 2D CNN attention map accelerates ODQCR 10-100x.
- All three operate natively on DAG IRs. No other quantum DSL has this. The implementation path: MCGS core → ODQCR database → neural prior.

### Scalability limitations documented
- SAT Clifford synthesis: **≤6 qubits** (Berent 2023, corrected Dec 2025)
- TODD tensor T-count: **≤8 qubits** (Reed-Muller decoder limit)
- Exact unitary MILP: **≤8 qubits** (Nagarajan 2025)
- AlphaZero synthesis: **3+1 qubits** (Valcarce 2025)
- ODQCR compute graph: **3 qubits depth 5** = 137K nodes (Rosenhahn 2025)
- BQSKit QFactor: partitions into **3-qubit blocks** for resynthesis
- Created P1 research issue for subcircuit partitioning strategy.

### Optimization passes roadmap: 28 issues registered with dependency chains
- **Tier 1 (P0-P1)**: Barrier partitioner, PassManager, run(ch), phase polynomial, gate cancellation, SABRE routing
- **Tier 2 (P2)**: MCGS, ODQCR, ZX simplification, TPAR, SAT layout, gridsynth, PMH CNOT
- **Tier 3 (P3)**: TODD, neural-guided, SAT Clifford, MaxSAT, resource estimation, DD equiv checking
- **Research (P1-P2)**: Subcircuit partitioning, ZX vs phase poly selection, NISQ vs FTQC paths, compute graph precomputation, verified pass correctness

### CRITICAL: Channel-vs-unitary hallucination risk
- **The DAG IR is for channels, not unitaries.** 12 of 25 optimization issues have HIGH hallucination risk.
- `ObserveNode`, `CasesNode`, `DiscardNode` are non-unitary. Most literature methods assume unitarity.
- **Phase polynomials**: undefined for non-unitary subcircuits. **ZX completeness**: pure QM only; mixed-state ZX incomplete for Clifford+T. **SAT synthesis**: stabilizer tableaux encode unitaries only. **DD equivalence**: QMDDs represent unitaries, not channels. **MCGS compute graph**: nodes are unitaries; channels with measurement have no single unitary node.
- **Guardrails installed:**
  1. **P0 barrier partitioner** (`Sturm.jl-vmd`): splits DAG at measurement/discard barriers. Now blocks ALL unitary-only passes in dependency graph.
  2. **P1 pass trait system** (`Sturm.jl-d94`): each pass declares `UnitaryOnly` or `ChannelSafe`. PassManager refuses mismatched application.
  3. **P1 channel equivalence research** (`Sturm.jl-hny`): Choi matrix / diamond norm instead of unitary comparison.
  4. **9 issues annotated** with explicit HALLUCINATION RISK notes.
  5. **CLAUDE.md updated** with mandatory protocol for all future agents.
- **The fundamental principle**: functions are channels (P1). The optimization infrastructure must respect this. Unitary methods are subroutines applied to unitary BLOCKS within a channel, never to the channel itself.

### Issue tracker status
- **71 total issues** (14 closed, 57 open)
- **P0**: 1 (barrier partitioner)
- **P1**: 7 (PassManager, run(ch), phase poly, gate cancel, SABRE, pass traits, channel equiv)
- **P2**: 18 (MCGS, ODQCR, ZX, TPAR, SAT layout, gridsynth, ring arithmetic, + bugs + research)
- **P3**: 20 (TODD, neural, SAT Clifford, MaxSAT, resource est, DD equiv, + existing gaps)
- **P4**: 9 (existing cleanup/deferred items)
- 8452 tests pass. All code committed and pushed to `tobiasosborne/Sturm.jl`.
