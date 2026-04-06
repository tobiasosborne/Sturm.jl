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

### Choi phase polynomials — potential architecture change
- **Key insight (Tobias Osborne)**: Phase polynomials — which he co-invented with Michael Nielsen — should extend to channels via the Choi-Jamiołkowski isomorphism. Channel C with Kraus ops {K_i} maps to Choi state J(C) = Σ K_i ⊗ K̄_i in doubled Hilbert space. If K_i are CNOT+Rz+projectors, then J(C) has phase polynomial structure in the doubled space.
- **Consequence**: If this works, the measurement barrier partitioner becomes UNNECESSARY. Phase polynomial methods (TPAR, TODD, T-count optimization) would operate on channels directly — no partitioning, no special-casing of ObserveNode/DiscardNode. The optimization layer would be natively channel-aware, consistent with P1.
- **P0 research issue** `Sturm.jl-d99` created. Barrier partitioner `Sturm.jl-vmd` now depends on this research — build the partitioner only if Choi approach doesn't work.
- **This is the architectural fork**: resolve Choi phase polys first, then decide the entire passes infrastructure. If it works, Sturm.jl's optimization story becomes: "we optimize channels, not circuits."

### Session 2 final status
- **72 total issues** (14 closed, 58 open)
- **P0**: 2 (Choi phase poly research, barrier partitioner — latter blocked on former)
- **P1**: 7 (PassManager, run(ch), phase poly extraction, gate cancel, SABRE, pass traits, channel equiv)
- **P2**: 18 (MCGS, ODQCR, ZX, TPAR, SAT layout, gridsynth, ring arithmetic, + bugs + research)
- **P3**: 20 (TODD, neural, SAT Clifford, MaxSAT, resource est, DD equiv, + existing gaps)
- **P4**: 9 (existing cleanup/deferred items)
- **Research**: 6 (Choi phase polys, subcircuit partitioning, ZX vs phase poly, NISQ vs FTQC, compute graph, verified passes)
- 8452 tests pass across 12 phases + Grover/AA
- 100 papers surveyed, sorted into 9 taxonomy folders (140 MB)
- All code committed and pushed to `tobiasosborne/Sturm.jl`

### What the next session should do
1. **Resolve Sturm.jl-d99** (Choi phase polynomials) — this determines the entire passes architecture
2. **Implement P1 infrastructure**: PassManager, run(ch), phase polynomial extraction
3. **Implement MCGS** (Sturm.jl-qfx) — the unique competitive advantage
4. **Fix P1 bugs**: Steane encoding (ewv), density matrix measure! (fq5)

## 2026-04-06 — Session 3: Standard optimisation passes

### Extended gate cancellation with commutation (Sturm.jl-8x3, closed)
- **Rewrote `gate_cancel.jl`** from 60 LOC adjacent-only merging to ~100 LOC commutation-aware pass.
- **Commutation rules implemented:**
  1. Gates on disjoint wire sets always commute.
  2. Rz on the control wire of a CX commutes with that CX — physics: (Rz(θ)⊗I)·CNOT = CNOT·(Rz(θ)⊗I).
  3. Non-unitary nodes (ObserveNode, DiscardNode, CasesNode) never commute — conservative correctness.
- **CX-CX cancellation added.** CX(c,t)·CX(c,t) = I, including through commuting intermediate gates.
- **Algorithm:** backward scan through result list, skipping commuting nodes until a merge partner or blocker is found. Iterates until convergence to handle cascading cancellations.
- **Gotcha: `Channel` name collision with `Base.Channel`.** Tests must use `Sturm.Channel` explicitly. Julia 1.12 added `Base.Channel` for async tasks — same name, different concept.
- **Dependency fix:** Removed incorrect dependency of 8x3 on dt7 (PassManager). Gate cancellation is a standalone pass — it doesn't need a PassManager to function.
- 22 new tests, 39 total pass tests.

### `optimise(ch, :pass)` convenience API (Sturm.jl-yj1, closed)
- **Implemented `src/passes/optimise.jl`** — user-facing `optimise(ch::Channel, pass::Symbol) -> Channel` wrapper.
- Supports `:cancel` (gate_cancel), `:deferred` (defer_measurements), `:all` (both in sequence).
- Matches PRD §5.3 API: `optimise(ch, :cancel_adjacent)`, `optimise(ch, :deferred)`.
- 4 new tests, 8484 total tests pass.

### QFT benchmark (benchmarks/bench_qft.jl)
- **Benchmarked against Wilkening's speed-oriented-quantum-circuit-backend** — 15 frameworks, QFT up to 2000 qubits.
- **DAG construction: 693ms at 2000 qubits** — faster than all Python frameworks, comparable to C backends.
- **Memory: 149 MB live, 353 MB allocated** — 31x less than Qiskit (4.7 GB), comparable to Ket (180 MB).
- **78 bytes/node** vs 16-byte theoretical minimum (4.9× overhead) — `controls::Vector{WireID}` and abstract-typed boxing.
- **Node counts match theory exactly**: 2n + n(n-1)/2 + 3⌊n/2⌋.
- Benchmark script avoids `trace()` NTuple specialisation overhead for large n by using TracingContext directly.

### gate_cancel O(n) rewrite: 149× speedup
- **Replaced backward linear scan with per-wire candidate tracking.**
- Three candidate tables: `ry_cand[wire]`, `rz_cand[wire]`, `cx_cand[(ctrl,tgt)]` — O(1) lookup per wire.
- **Blocking rules encode commutation physics:**
  - Ry on wire w blocks: rz_cand[w], all CX involving w
  - Rz on wire w blocks: ry_cand[w], CX where w is target (NOT control — Rz commutes through CX control!)
  - CX(c,t) blocks: ry_cand[c], ry_cand[t], rz_cand[t] (NOT rz_cand[c]!)
  - Non-unitary nodes: barrier on all touched wires
  - Nodes on when()-control wires invalidate candidates controlled by that wire
- **Function barrier pattern** for type-stable dispatch: separate `_try_merge_node!` methods per node type.
- **Gotcha: `_collect_wires!` was already defined in openqasm.jl** — duplicating it in gate_cancel.jl caused method overwrite warnings. Removed duplicates, reuse the existing methods.
- **Performance: 43.7s → 293ms at 2000 qubits (149×).** Total trace+cancel: 44.5s → 986ms (45×).
- **Limitation**: per-wire single-candidate tracking can miss merges when multiple controlled rotations on the same wire have different controls. Multi-pass iteration compensates — typically converges in 1-2 passes.
- Research agents surveyed: Julia union-splitting (4 types), LightSumTypes.jl (0-alloc tagged union), StaticArrays.jl, Bumper.jl, StructArrays.jl. Qiskit/tket/quilc all use per-wire forward tables — same design we adopted.

### Phase 2: Inline controls — 42 bytes/node, 80 MB live (Session 3 continued)
- **Replaced `controls::Vector{WireID}` with inline fields** `ncontrols::UInt8, ctrl1::WireID, ctrl2::WireID` in all node types (RyNode, RzNode, CXNode, PrepNode).
- **Eliminated `copy(ctx.control_stack)` entirely** — tracing reads stack directly into inline fields. Zero allocation per gate.
- **Added `get_controls(node)` accessor** returning a tuple (zero-alloc iteration).
- **Added `_same_controls(a, b)`** for efficient controls comparison.
- **All node types now `isbitstype = true`** (24 bytes each). Still boxed in `Vector{DAGNode}` (abstract type), but the controls Vector allocation is gone.
- **Updated 52 lines across 7 files** — dag.jl, tracing.jl, gate_cancel.jl, deferred_measurement.jl, openqasm.jl, compose.jl, tests.
- **Gotcha: `Symbol` is NOT `isbitstype` in Julia.** Original BlochProxy redesign used Bool → no improvement because the proxy was already being stack-allocated via escape analysis. Reverted BlochProxy to original (with @inline).
- **Gotcha: TLS lookup overhead.** Replacing `proxy.ctx` with `current_context()` (task_local_storage) added ~60ms for 2M calls. Net loss vs allocation saving. Reverted.
- **Results at 2000 qubits:**
  - Trace: 693ms → 514ms (1.35x faster)
  - DAG live (summarysize): 149 MB → 80 MB (1.86x less)
  - Peak RSS: ~554 MB (Julia runtime ~200 MB + DAG + GC churn). NOT comparable to cq_impr's 95 MB RSS (C process, no runtime overhead). The per-node data is comparable: Sturm 42 bytes/node vs cq_impr 40 bytes/gate.
  - Bytes/node: 78 → 42 (1.86x smaller)
  - Allocations: 353 MB → 261 MB (1.35x less)
- **Max 2 when()-controls limitation** — covers all current use cases (deepest nesting = 1). Error on >2 with message pointing to Phase 3.
- 8484 tests pass.

### Phase 3: Isbits-union inline DAG — 31 bytes/node, 332ms trace
- **3+1 agent protocol used.** Two Sonnet proposers (independent designs), orchestrator synthesised.
- **Proposer A**: `const HotNode = Union{6 types}`, keep abstract type, no field reordering. 33 bytes/element. CasesNode in separate sparse position-indexed list.
- **Proposer B**: Remove abstract type, replace with `const DAGNode = Union{7 types}` alias. Field reordering (Float64 first) for 24-byte sizeof → 25 bytes/element. CasesRef isbits + side table for CasesNode.
- **Synthesis**: Keep abstract type (A, for P7 extensibility and `<: DAGNode` safety). Take field reordering (B, 32→24 bytes). Take HotNode naming (A, clear separation from DAGNode). Simplify CasesNode — neither CasesRef nor position list needed because TracingContext never produces CasesNode (only test fixtures do).
- **`const HotNode = Union{RyNode, RzNode, CXNode, PrepNode, ObserveNode, DiscardNode}`** — 6 isbits types. Julia stores inline at `max(sizeof) + 1 tag = 25` bytes/element. Verified: `summarysize` confirms 33→25 bytes/element.
- **Field reordering**: Float64 first eliminates padding. RyNode/RzNode/PrepNode: sizeof 32 → 24. CXNode stays at 20.
- **TracingContext.dag and Channel.dag changed to `Vector{HotNode}`**. Backward-compat overloads for `gate_cancel(::Vector{DAGNode})` and `Channel{In,Out}(::Vector{DAGNode}, ...)` for test fixtures that use CasesNode.
- **Gotcha: benchmark script had `Vector{DAGNode}` hardcoded** — needed updating to `Vector{HotNode}`.
- **Gotcha: `_cancel_pass` signature still said `Vector{DAGNode}`** — missed in first pass, caught by MethodError.
- **Results at 2000 qubits (full session arc):**
  - Trace: 693ms → 332ms (2.1x)
  - gate_cancel: 43.7s → 336ms (130x)
  - DAG live: 149 MB → 59 MB (2.5x)
  - Bytes/node: 78 → 31 (2.5x)
  - Now faster than cq (434ms), 5.1x gap to cq_impr (65ms)
- 8484 tests pass.

### Remaining performance opportunities (registered as beads issues)
1. **Sturm.jl-6mq (P1)**: `sizehint!` for TracingContext.dag — avoid reallocation during trace. Quick win, ~5 lines.
2. **Sturm.jl-7i4 (P2)**: Eliminate when() closure allocation — @when macro or callable-struct for internal hot paths. Potential ~100ms saving.
3. **Sturm.jl-y2k (P2)**: Reduce trace allocation churn (270 MB allocated, 59 MB retained) — BlochProxy not elided (Symbol not isbitstype, TLS lookup adds overhead), when() closures, Vector resizing.
4. **Sturm.jl-uod (P3)**: LightSumTypes.jl @sumtype or StructArrays.jl SoA for sub-25 bytes/node. Architectural change affecting all DAG consumers. Target: close remaining 5.1x gap to cq_impr.

### Session 3 final status
- **Issues closed**: Sturm.jl-8x3 (extended gate cancellation), Sturm.jl-yj1 (optimise API)
- **Issues created**: Sturm.jl-6mq, 7i4, y2k, uod (remaining perf opportunities)
- **8484 tests pass**
- **All code committed and pushed**

## 2026-04-06 — Session 4: Literature Survey + Simulation Module

### Literature survey: quantum simulation algorithms (~170 papers, 8 categories)

Comprehensive survey of the entire quantum simulation field. **8 parallel Sonnet research agents** produced standardized reports, each with per-paper entries (citation, arXiv, contribution, complexity, limitations, dependencies).

**Categories and paper counts:**
1. `product_formulas/` (28 papers): Trotter 1959 → Kulkarni 2026 (Trotter scars, entanglement-dependent bounds)
2. `randomized_methods/` (21 papers): qDRIFT (Campbell 2019) → stochastic QSP (Martyn-Rall 2025), random-LCHS
3. `lcu_taylor_series/` (18 papers): Berry-Childs lineage 2007→QSVT, interaction picture, time-dependent, LCHS
4. `qsp_qsvt/` (28 papers): Low-Chuang → GQSP (Motlagh 2024, degree 10^7 in <1min), grand unification
5. `quantum_walks/` (18 papers): Szegedy → qubitization (walk operators ARE block encodings for QSVT)
6. `variational_hybrid/` (24 papers): VQE, ADAPT-VQE, VQS, barren plateaus, error mitigation, QAOA
7. `applications_chemistry/` (23 papers): 10^6× T-gate reduction from Reiher 2017 to Lee 2021 (THC)
8. `surveys_complexity/` (28 papers): Feynman 1982 → Dalzell 2023 (337-page comprehensive survey)

**Paper downloads:**
- **95 unique arXiv PDFs** (141 MB total) + 46 cross-category symlinks
- **6 paywalled papers** fetched via Playwright + TIB VPN (Trotter, Feynman, Suzuki ×3, Lloyd)
- **Portable download script**: `bash docs/literature/quantum_simulation/download_all.sh`
  - Phase 1: all arXiv papers via curl (no VPN)
  - Phase 2: paywalled papers via `node docs/literature/quantum_simulation/fetch_paywalled.mjs` (needs TIB VPN + Playwright from `../qvls-sturm/viz/node_modules/playwright`)

**Key findings for Sturm.jl:**
- QSP signal processing rotations ARE the θ/φ primitives. Block encoding uses controlled ops (when/⊻=). No new primitives needed.
- GQSP (Motlagh 2024) is the recommended classical preprocessor for QSP phase angles.
- Szegedy walk operators decompose exactly into 4 primitives (reflections = state prep + CNOT + phase kick + uncompute).
- `pauli_exp!` is the universal building block: every simulation algorithm (Trotter, qDRIFT, LCU) compiles to Pauli exponentials.
- Variational circuits (VQE/ADAPT) are directly expressible as θ/φ rotation + CNOT entangling layers.

### Simulation module: `src/simulation/` (3+1 agent protocol, Opus proposers)

**3+1 protocol executed with two Opus proposers:**
- **Proposer A**: Symbol-based Pauli encoding (`:I,:X,:Y,:Z`), `Ry(-π/2)` for X→Z basis change, single `Trotterize` struct with order field, `simulate!` naming.
- **Proposer B**: PauliOp struct with bit encoding, `H!` for X→Z basis change, separate `Trotter1/Trotter2/Suzuki` structs, `evolve!` naming, `solve` channel factory.

**CRITICAL PHYSICS FINDING during orchestrator review:**
- **Proposer B's X basis change using H! has a sign error.** H! = Rz(π)·Ry(π/2) in Sturm is NOT proportional to the standard Hadamard H. H!² = -I ≠ I. Conjugation H!†·Z·H! = -X (not X). This means exp(-iθ·(-X)) = exp(+iθX) — wrong sign for X terms.
- **Proposer A's `Ry(-π/2)` is correct**: Ry(-π/2)·X·Ry(π/2) = Z ✓. Verified by explicit matrix computation.
- The sign error is undetectable in single-qubit measurement tests (|⟨k|exp(±iθP)|ψ⟩|² are identical) but would cause Trotter simulation to evolve under the WRONG Hamiltonian (X coefficients negated).
- **This is why the ground truth literature check matters.** The bug would have shipped if we'd only tested with measurement statistics.

**Synthesis: A's physics + B's API structure.**

**Files created:**
```
src/simulation/
    hamiltonian.jl      # PauliOp (@enum), PauliTerm{N}, PauliHamiltonian{N}
    pauli_exp.jl        # exp(-iθP) → 4 primitives (Ry(-π/2) for X, Rx(π/2) for Y)
    trotter.jl          # Trotter1, Trotter2, Suzuki structs + recursion
    models.jl           # ising(Val(N)), heisenberg(Val(N))
    evolve.jl           # evolve!(reg, H, t, alg) API
test/
    test_simulation.jl  # 78 tests: Orkan amplitudes + matrix ground truth + DAG emit
```

**Physics derivations (in pauli_exp.jl comments):**
- X→Z: V = Ry(-π/2), proof: Ry(-π/2)·X·Ry(π/2) = Z. In primitives: `q.θ -= π/2`.
- Y→Z: V = Rx(π/2) = Rz(-π/2)·Ry(π/2)·Rz(π/2), proof: Rx(-π/2)·Z·Rx(π/2) = Y. In primitives: `q.φ += π/2; q.θ += π/2; q.φ -= π/2`.
- CNOT staircase: Z^⊗m eigenvalue = (-1)^parity, compute parity via CNOT chain, Rz(2θ) on pivot.
- Suzuki recursion: S₂ₖ(t) = [S₂ₖ₋₂(pₖt)]² · S₂ₖ₋₂((1-4pₖ)t) · [S₂ₖ₋₂(pₖt)]², pₖ = 1/(4-4^{1/(2k-1)}). Cited: Suzuki 1991 Eqs. (3.14)-(3.16).

**Three-pipeline test verification:**
1. **Orkan amplitudes**: exact state vectors match analytical exp(-iθP)|ψ⟩ for Z, X, Y, ZZ, XX, YY, XZ, XYZ (all to 1e-11).
2. **Linear algebra ground truth**: matrix exp(-iHt) via eigendecomposition matches Trotter evolution. Convergence: error(T1) > error(T2) > error(S4).
3. **DAG emit**: TracingContext captures simulation circuits as Channel, exports to OpenQASM.

**Gotcha: Orkan LSB qubit ordering.** PauliTerm position i maps to Orkan qubit (i-1), which is bit (i-1) in the state vector index. `|10⟩` in term notation (qubit 1 flipped) = Orkan index 1 (not 2). Matrix ground truth tests must use `kron(qubit1_op, qubit0_op)` to match Orkan ordering. Cost one debugging cycle.

### Benchmark results: Trotter-Suzuki convergence (verified against Suzuki 1991)

**Convergence rates (N=8 Ising, t=1.0, doubling steps):**

| Algorithm | Expected rate | Measured rate |
|-----------|--------------|---------------|
| Trotter1 (order 1) | 2× | **2.0×** |
| Trotter2 (order 2) | 4× | **4.0×** |
| Suzuki-4 (order 4) | 16× | **16.0×** |
| Suzuki-6 (order 6) | 64× | **64-66×** |

Textbook perfect. Suzuki-6 hits machine precision (~10⁻¹²) at 32 steps.

**Error vs system size (t=0.5, 5 steps, exact diag reference up to N=14):**

| N | λ(H) | Trotter1 | Trotter2 | Suzuki-4 | Suzuki-6 |
|---|------|----------|----------|----------|----------|
| 4 | 5.0 | 6.7e-2 | 3.0e-3 | 3.4e-6 | 5.9e-10 |
| 8 | 11.0 | 1.1e-1 | 5.6e-3 | 6.3e-6 | 1.1e-9 |
| 14 | 20.0 | 1.7e-1 | 9.0e-3 | 9.5e-6 | 1.7e-9 |
| 20* | 29.0 | 2.2e-1 | 1.2e-2 | 1.2e-5 | 2.1e-9 |

Errors scale weakly (~linearly) with N. Suzuki-6 achieves 10⁻⁹ accuracy across all sizes with just 5 steps.

**Analytical bounds vs measured (N=8, t=1.0, 10 steps):**
Simple bound (λ·dt)^{2k+1} is conservative by 10×–10⁹× (commutator prefactors not computed). Childs et al. 2021 commutator-scaling bounds would be tighter but require nested commutator norms.

### Performance at N=24 (256 MB state vector)

- **~2.6 s per Trotter2 step** regardless of OMP thread count (16, 32, 48, or 64)
- **Bottleneck: memory bandwidth**, not parallelism. Each gate traverses 2^24 × 16 bytes = 256 MB (exceeds L3 cache). Single Ry takes ~10 ms, CX ~13 ms.
- 16 threads IS helping (vs 1 thread would be ~4× slower for Ry/Rz) — but scaling flattens beyond 16 because the bandwidth is saturated.
- 282 gates per Trotter2 step for N=24 Ising (47 terms × 2 sweeps × ~3 primitives/term).
- Circuit DAG is tiny: 282 nodes, 13 KB. The cost is ALL in statevector simulation.

### Code review (3 Sonnet reviewers: Architecture, Code Quality, Test Coverage)

**Reviewer A (Architecture):**
- C1: `nqubits/nterms/lambda` exports pollute namespace → **FIXED**: removed from exports
- C2: `evolve!` QInt overload accepted `AbstractSimAlgorithm` but only product formulas work → **FIXED**: narrowed to `AbstractProductFormula`
- C3: `fourier_sample` docstring wrong signature (Int vs Val) → **FIXED**
- C4: 2-control cap in TracingContext breaks n>2 Grover tracing → **DEFERRED** (needs DAG extension)
- W1: `when.jl` include order fragile → **FIXED**: moved before gates.jl
- W4: No `trace(f, ::Val{W})` for QInt circuits → **FIXED**: added

**Reviewer B (Code Quality):**
- C1: `_support` allocates Vector in hot loop → **FIXED**: replaced with inline iteration over ops tuple (zero allocation)
- C2: Global `_wire_counter` not thread-safe → **DEFERRED** (architectural)
- C3: QBool vector pattern allocates per call → **PARTIALLY FIXED**: added `_qbool_views` helper returning NTuple
- C4: Support not cached across Trotter steps → **FIXED**: eliminated _support entirely, iterate ops directly
- W1: `QBool.ctx` is AbstractContext → **DEFERRED** (requires 3+1 for core type change)
- W3: NaN/Inf not rejected by evolve! → **FIXED**: added `isfinite(t)` guard
- W4: Suzuki recursion dispatches on Int → **FIXED**: Val{K} dispatch for compile-time inlining
- W7: `_SYM_TO_PAULI` Dict → **FIXED**: replaced with `@inline _sym_to_pauli` function
- W8: `_diffusion!` rebuilds QBool vector unnecessarily → **FIXED**: reuse qs

**Reviewer C (Test Coverage):**
- C2: No negative coefficient test → **FIXED**: added exp(-iθ(-Z)) and exp(-iθ(-X)) tests
- C3: No test for negative time guard → **FIXED**: added
- C4: Suzuki order 6/8 never exercised → **FIXED**: added order-6 convergence test
- W1: YY testset title missing `im` → **FIXED**
- W3: evolve! on QInt no state check → **FIXED**: added amplitude verification
- W4: No DensityMatrixContext + evolve! test → **FIXED**: added statistical test
- W5: No Trotter1==Trotter2 on 1-term test → **FIXED**: added
- W7: Matrix ground truth tolerance too loose → **FIXED**: 1e-4 → 1e-6 for Trotter2

**Gotcha: Unverified citations.** I initially cited "Sachdev (2011), Eq. (1.1)" without having the PDF or verifying the equation — violating Rule 4 (PHYSICS = LOCAL PDF + EQUATION). Caught and corrected: replaced with Childs et al. 2021 (arXiv:1912.08854) Eq. (99) for Ising and Eq. (288) for Heisenberg, both verified against the local PDF on pages 32 and 68 respectively. Sachdev QPT Ch.1 downloaded to docs/physics/ but doesn't contain the explicit Pauli-form Hamiltonian (it's in a later chapter).

**Additional fixes applied:**
- Added `AbstractStochasticAlgorithm`, `AbstractQueryAlgorithm` stub types for future qDRIFT/LCU
- Added `ising(N::Int)` and `heisenberg(N::Int)` convenience wrappers
- Added ABI exception comment to noise/channels.jl (Kraus operators bypass DSL primitives)
- Removed `_commutes` and `_weight` dead code from hamiltonian.jl
- Added `sizehint!(dag, 256)` to TracingContext constructor
- Fixed heisenberg tuple type stability (Float64 cast)
- Used `mapreduce` for `lambda()` (more idiomatic)

**Total: 21 review issues closed, 90 simulation tests pass.**

### Session 4 final status
- **8530+ tests pass** (90 simulation tests, up from 78)
- **Literature**: 95 PDFs + 6 paywalled + 8 survey reports + portable download script
- **Simulation module**: PauliHamiltonian, pauli_exp! (zero-alloc), Trotter1/2, Suzuki-4/6, evolve!, ising(), heisenberg()
- **Verified**: convergence rates match Suzuki 1991 exactly, 3-pipeline tests (Orkan + linalg + DAG)
- **Code review**: 3 reviewers, 21 issues fixed, 7 deferred (core type changes, architectural)
- **104 total beads issues** (37 closed, 67 open)

### What the next session should do
1. **Implement qDRIFT** — second algorithm, shares `pauli_exp!`, extends `AbstractStochasticAlgorithm`
2. **Parametrise QBool{C} on context type** — highest-impact perf fix, requires 3+1 (Sturm.jl-26s)
3. **Implement commutator-scaling error bounds** — Childs et al. 2021 Theorem 1
4. **Gate cancellation on simulation circuits** — adjacent Ry(-π/2)·Ry(π/2) from basis change/unchange should cancel
5. **MCGS integration** — the unique competitive advantage (Rosenhahn-Osborne trilogy)
6. **Resolve Sturm.jl-d99** — Choi phase polynomials (determines passes architecture)

### Paper download instructions for new machines
```bash
# From repo root:
# Phase 1: arXiv papers (no VPN, ~5 min)
bash docs/literature/quantum_simulation/download_all.sh

# Phase 2: Paywalled papers (needs TIB VPN + Node.js + Playwright)
# Playwright import in fetch_paywalled.mjs uses:
#   /home/tobiasosborne/Projects/qvls-sturm/viz/node_modules/playwright/index.mjs
# Edit line 10 to match your local Playwright install path, then:
node docs/literature/quantum_simulation/fetch_paywalled.mjs
```
