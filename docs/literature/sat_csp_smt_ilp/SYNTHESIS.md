# SAT/CSP/SMT/ILP Literature Synthesis (18 papers)

Synthesized 2026-04-05. All 18 PDFs in this directory read (pages 1-5 each).

---

## Method overview

The 18 papers span four interrelated problem domains.

**1. Quantum layout synthesis (QLS)** — the largest cluster. Maps logical qubits onto physical hardware with limited connectivity by inserting SWAP gates. NP-hard. Exact solver formulations in SMT (OLSQ-TAN-CONG, OLSQ2-LIN-CONG), SAT (AMAZON-SAT-MAPPING, SHAIK-SAT-DEEP-100Q, JAKOBSEN-SAT-DEPTH-OPT), MaxSAT (MAXSAT-QUBIT-MAP), ILP/BIP (NANNICINI-ILP-ROUTING), and classical planning/PDDL (SHAIK-PLANNING-LAYOUT, VENTURELLI-TEMPORAL, BOOTH-CP-TEMPORAL).

Trajectory: early SMT (OLSQ, 2020) → pure SAT with bit-vector CNF (OLSQ2, 692x speedup) → incremental + parallel SAT (AMAZON-SAT-MAPPING, Q-Synth v2, another 26-100x). Two competing objectives: SWAP/CX-count minimization (size-optimal) vs. CX-depth minimization (depth-optimal). JAKOBSEN-SAT-DEPTH-OPT finds combined CX-count + CX-depth reduction best predicts actual noise reduction.

**2. Circuit synthesis** — finding the shortest gate sequence for a target unitary. Clifford subgroup is the tractable frontier (Clifford synthesis ∈ NP, general unitary synthesis is QMA-hard). BERENT-CLIFFORD-SAT and BERENT-CLIFFORD-DEPTH-SAT use stabilizer tableaux (Gottesman-Knill) as SAT state: O(n²d_max) variables, O(n⁴d_max) constraints. MEULI-SAT-CNOT-T handles {CNOT, T} circuits via phase polynomial representation. GROSSE-SAT-EXACT-REV uses 4-value encoding (0, 1, V0, V1) for reversible functions. NAGARAJAN-MIP-OPTIMAL uses MILP with real-encoded unitary matrices + McCormick linearization + rolling-horizon optimization (RHO) for provably optimal general synthesis.

**3. Fault-tolerant / post-NISQ** — LASSYNTH-SAT-LATTICE (Google) encodes lattice surgery subroutine optimization as SAT, targeting spacetime volume minimization for surface-code FTQC. Representation: tiles, pipes, correlation surfaces, ZX calculus. Core engine: iterative SAT with shrinking volume bounds.

**4. CP and temporal planning** — BOOTH-CP-TEMPORAL and VENTURELLI-TEMPORAL model QCC as scheduling with durative PDDL actions, global constraints (NoOverlap, Alternative), and makespan objectives. Useful when gate commutation flexibility is high.

---

## Pros

- **Optimality guarantees**: OLSQ2 achieves 7x depth and 12x SWAP reduction over SABRE (OLSQ2-LIN-CONG). Q-Synth v2 outperforms TB-OLSQ2 by up to 100x while maintaining optimality (SHAIK-SAT-DEEP-100Q).

- **Incremental SAT reuses learned clauses**: CaDiCaL and MapleSAT support assumption-based incremental solving. AMAZON-SAT-MAPPING reports 26x speedup over TB-OLSQ2; SHAIK-SAT-DEEP-100Q and JAKOBSEN-SAT-DEPTH-OPT confirm 10-100x gains.

- **Parallel SAT portfolios scale on multicores**: AMAZON-SAT-MAPPING uses portfolio-style parallel solving (ManySAT, Mallob, ParKissat-RS) with inter-thread learned clause sharing.

- **Encoding diversity enables tradeoff tuning**: OLSQ2 switching Z3 from integer arithmetic to bit-vectors achieves 692x speedup with no quality loss (OLSQ2-LIN-CONG Table I). MaxSAT (MAXSAT-QUBIT-MAP) gives best-effort optimal results efficiently — unlike plain SAT, which is all-or-nothing.

- **Clifford synthesis complexity matches SAT**: BERENT-SAT-JOURNEY proves Clifford synthesis ∈ NP (not QMA-hard), so SAT is the right tool with no theoretical overhead. Directly exploitable for QECC synthesis in Sturm.jl.

- **ILP captures multi-objective tradeoffs**: NANNICINI-ILP-ROUTING simultaneously minimizes error rate, depth, and crosstalk in a single BIP. NAGARAJAN-MIP-OPTIMAL handles global-phase invariance linearly via real encoding — a unique MILP advantage over SAT.

- **Planning handles gate commutativity naturally**: VENTURELLI-TEMPORAL and BOOTH-CP-TEMPORAL exploit commuting gates in QAOA circuits for more parallel compilations with no additional encoding effort.

- **Lattice surgery optimization is unique to SAT**: LaSynth found 40% volume reduction for majority gates vs. human-designed implementations (LASSYNTH-SAT-LATTICE).

---

## Cons / Limitations

- **Exponential worst-case scaling**: BERENT-CLIFFORD-SAT scales only to 6 qubits optimally (corrected from originally claimed 27). BERENT-CLIFFORD-DEPTH-SAT to ~5 qubits. NAGARAJAN-MIP-OPTIMAL has Θ(4^Q) scaling. OLSQ fails on 36-gate / 9×9 circuits after 40+ hours (OLSQ2-LIN-CONG Figure 1).

- **Encoding quality is the bottleneck**: OLSQ2 demonstrates the original OLSQ encoding left 100-6,957x performance on the table. Getting a good encoding requires significant domain expertise.

- **Depth-optimal is fundamentally harder than count-optimal**: JAKOBSEN-SAT-DEPTH-OPT reports OLSQ2 is up to 5 orders of magnitude slower than Q-Synth v2 for CX-count; QuiLS is still slower than count-optimal tools despite being 10-100x faster than OLSQ2 for depth.

- **MaxSAT solvers are lighter but less predictable**: MAXSAT-QUBIT-MAP notes solver may not find globally optimal solution for large circuits. Local relaxation (slicing) sacrifices global optimality. SATMap cited as less efficient than TB-OLSQ2 due to encoding choices (AMAZON-SAT-MAPPING).

- **ILP requires commercial solvers for best performance**: NANNICINI-ILP-ROUTING and NAGARAJAN-MIP-OPTIMAL rely on Gurobi/CPLEX-class solvers. Open-source QuantumCircuitOpt.jl exists but performance gaps with commercial solvers exist.

- **CP and temporal planning lack scalability**: BOOTH-CP-TEMPORAL reports stand-alone CP is competitive only on small problems. VENTURELLI-TEMPORAL demonstrated only on 8/21-qubit architectures.

- **SMT theory-solver interaction is opaque**: OLSQ2 found using Z3's AtMost (pseudo-Boolean solver) *hurt* performance compared to plain CNF because the PB solver interfered with the SAT engine (OLSQ2-LIN-CONG Section IV-B).

- **Circuit synthesis and layout synthesis do not compose**: Papers address the two problems in isolation. No combined synthesis + layout framework exists as an off-the-shelf tool.

- **Lattice surgery methods are FTQC-specific**: LASSYNTH-SAT-LATTICE is deeply coupled to surface code geometry. Not applicable to NISQ routing problems.

---

## Implementability for Sturm.jl

### Tier 1 — High value, moderate effort (~500-1000 LOC, 1-2 weeks)

**SAT-based SWAP-optimal layout synthesis pass** in `src/passes/layout_sat.jl`. Algorithm (Q-Synth v2 / SHAIK-SAT-DEEP-100Q + AMAZON-SAT-MAPPING):

1. Extract CNOT dependency DAG from the channel's gate sequence.
2. Encode QLS as CNF: one SAT variable per (logical qubit, physical qubit, time step) for mapping; one per (edge, time step) for SWAP placement. Use parallel plans (exactly 1 SWAP + group of CNOTs per time step).
3. Incremental SAT: start at makespan = circuit depth, add one time step per iteration, re-solve with assumptions.
4. Extract satisfying assignment as updated gate sequence.

**Julia SAT solver options**: (a) `PicoSAT.jl` (wraps picosat via ccall, MIT license, ~100 LOC integration); (b) subprocess to CaDiCaL binary via DIMACS I/O; (c) `Satisfiability.jl`. PicoSAT.jl is lowest-friction. Estimated: 600-900 LOC total.

Architecture fit: All passes operate on abstract DAG representation, not raw matrices. The SAT pass takes the DAG, calls solver via ccall or subprocess, returns updated DAG. No changes to Orkan needed.

### Tier 2 — Moderate value, higher effort (~1500-2500 LOC, 2-4 weeks)

**MaxSAT qubit mapping** (`src/passes/layout_maxsat.jl`, MAXSAT-QUBIT-MAP approach): Replace iterative SAT with single MaxSAT call where SWAP variables are soft constraints. Use circuit slicing for scalability. Requires MaxSAT solver (Open-WBO or RC2 via subprocess). Useful as a time-bounded compilation mode.

**SMT layout synthesis** (OLSQ2 style): Use Z3.jl (wraps libz3 via ccall, existing Julia package). Advantage: Z3.jl already available. Disadvantage: Z3 SMT is ~692x slower than SAT for equivalent problems (OLSQ2's own data). Not recommended as primary path.

**ILP routing via JuMP** (`src/passes/layout_ilp.jl`, NANNICINI-ILP-ROUTING): Use JuMP.jl + HiGHS (Apache 2 license, freely available). Most flexible for multi-objective optimization (error rate + depth + crosstalk) when gate fidelity data per hardware edge is available.

### Tier 3 — High value for QECC, significant effort (~2000-3000 LOC, 4-8 weeks)

**SAT-based Clifford synthesis** (`src/passes/clifford_synth.jl`, BERENT-CLIFFORD-SAT / BERENT-CLIFFORD-DEPTH-SAT):

1. Implement stabilizer tableau (2n×(2n+1) binary matrix) + Gottesman-Knill update rules for Sturm.jl's four primitives (Ry→H+S combinations, Rz→Z/S/T, CNOT directly).
2. Encode gate selection variables + tableau consistency constraints as CNF.
3. Binary search on gate count T.

Physics reference: BERENT-CLIFFORD-DEPTH-SAT equations (1)-(7) for stabilizer tableau SAT reduction. Directly supports `src/qecc/Steane` — synthesizes depth-optimal encoder/decoder circuits expressed via Sturm.jl's four primitives.

**MILP unitary synthesis** (`src/passes/unitary_milp.jl`): Evaluate integrating `QuantumCircuitOpt.jl` (Julia, open-source) directly as a package dependency for circuits up to ~8 qubits. Enables provably optimal synthesis for QECC syndrome extraction circuits.

---

## Adoption in production systems

| Tool | Method | Status | Source |
|------|---------|--------|--------|
| **MQT QMAP** (TUM/JKU) | SAT-based Clifford synthesis | Open-source, MIT, actively maintained | BERENT-CLIFFORD-SAT, BERENT-CLIFFORD-DEPTH-SAT |
| **IBM Qiskit BIPMapping** | ILP qubit assignment + routing | Public Qiskit 1.x pass | NANNICINI-ILP-ROUTING |
| **OLSQ / TB-OLSQ / OLSQ2** | SMT (Z3) layout synthesis | Open-source Python, widely cited baseline | OLSQ-TAN-CONG, OLSQ2-LIN-CONG |
| **Q-Synth v1/v2** | Planning + SAT, SWAP-optimal | Open-source Python (GitHub: irfansha/Q-Synth) | SHAIK-PLANNING-LAYOUT, SHAIK-SAT-DEEP-100Q |
| **QuiLS** | SAT, CX-depth-optimal | Open-source Python (GitHub: anbclausen/quills) | JAKOBSEN-SAT-DEPTH-OPT |
| **LaSynth** | SAT, lattice surgery | Internal Google Quantum AI tool | LASSYNTH-SAT-LATTICE |
| **QuantumCircuitOpt (QCOpt)** | MILP unitary synthesis | Open-source **Julia** (GitHub: harshangrjn/QuantumCircuitOpt) | NAGARAJAN-MIP-OPTIMAL |
| **Kvantify compiler** | Q-Synth + QuiLS backend | Commercial, Kvantify | SHAIK-SAT-DEEP-100Q, JAKOBSEN-SAT-DEPTH-OPT |

**Key for Sturm.jl**: QuantumCircuitOpt.jl is the most immediately reusable tool — already Julia, Apache 2 licensed.

---

## Key metrics from papers

| Metric | Value | Source |
|--------|-------|--------|
| AMAZON-SAT-MAPPING vs TB-OLSQ2 | 26x faster, 76% of instances improved | AMAZON-SAT-MAPPING |
| AMAZON-SAT-MAPPING vs SABRE | 26% fewer SWAPs on average | AMAZON-SAT-MAPPING |
| MAXSAT-QUBIT-MAP vs TB-OLSQ/EX-MQT | Solves 3x more benchmarks, 40x speedup | MAXSAT-QUBIT-MAP |
| MAXSAT-QUBIT-MAP vs SABRE | 3.6x to 7x SWAP reduction | MAXSAT-QUBIT-MAP |
| MAXSAT-QUBIT-MAP zero-SWAP instances | 14% of benchmarks | MAXSAT-QUBIT-MAP |
| OLSQ2 vs OLSQ | 692x speedup (SWAP opt), 6,957x average | OLSQ2-LIN-CONG Table I |
| OLSQ2 vs SABRE | 7x depth reduction, 12x SWAP reduction | OLSQ2-LIN-CONG |
| OLSQ2 largest solved | 54 qubits, 1726 gates in 11 hours | OLSQ2-LIN-CONG |
| Q-Synth v1 optimal capacity | 9-qubit circuits on 14-qubit platform | SHAIK-PLANNING-LAYOUT |
| Q-Synth v1 vs OLSQ | Up to 2 orders of magnitude faster | SHAIK-PLANNING-LAYOUT |
| Q-Synth v2 vs TB-OLSQ2 | Up to 100x faster, optimal guarantee | SHAIK-SAT-DEEP-100Q |
| Q-Synth v2 largest solved optimally | 127-qubit Eagle, up to 17 SWAPs | SHAIK-SAT-DEEP-100Q |
| QuiLS (depth-opt) vs OLSQ2 | 10-100x faster for depth-optimal | JAKOBSEN-SAT-DEPTH-OPT |
| OLSQ2 vs Q-Synth v2 (count) | OLSQ2 up to 5 orders of magnitude slower | JAKOBSEN-SAT-DEPTH-OPT |
| BERENT-CLIFFORD-SAT: Qiskit vs optimal | Qiskit uses >2x more 2-qubit gates | BERENT-CLIFFORD-SAT |
| BERENT-CLIFFORD-SAT scalability (corrected) | 6 qubits optimal | BERENT-CLIFFORD-SAT (correction Dec 2025) |
| BERENT-CLIFFORD-DEPTH-SAT: heuristic gap | ~2 orders of magnitude from optimal depth | BERENT-CLIFFORD-DEPTH-SAT |
| NANNICINI-ILP vs SABRE | ~10% fewer CNOTs, ~20% less depth | NANNICINI-ILP-ROUTING |
| NANNICINI-ILP on Clifford circuits | ~11% CNOT reduction | NANNICINI-ILP-ROUTING |
| NAGARAJAN-MIP valid inequalities speedup | Up to 43x on standard benchmarks | NAGARAJAN-MIP-OPTIMAL |
| NAGARAJAN-MIP RHO: 142-gate seed | 116 gates output (18.3% reduction) | NAGARAJAN-MIP-OPTIMAL |
| NAGARAJAN-MIP multi-body parity | 36% gate-count reduction | NAGARAJAN-MIP-OPTIMAL |
| MEULI-SAT-CNOT-T CNOT reduction | 26.84% average in T-optimized circuits | MEULI-SAT-CNOT-T |
| LASSYNTH majority gate | 40% volume reduction vs prior | LASSYNTH-SAT-LATTICE |
| LASSYNTH 15-to-1 T-factory | 8% and 18% volume reduction | LASSYNTH-SAT-LATTICE |
| GROSSE-SAT-EXACT-REV speedup | Up to 45x; 70-95% runtime reduction | GROSSE-SAT-EXACT-REV |
| TB-OLSQ vs TriQ fidelity | 1.30x improvement | OLSQ-TAN-CONG |
| QAOA-OLSQ vs tket | 70.2% depth reduction, 53.8% cost reduction | OLSQ-TAN-CONG |
| SABRE vs optimal SWAP count gap | 1.5-12x (and 5-45x in prior surveys) | SHAIK-PLANNING-LAYOUT |

---

## Recommended implementation order

**Step 1 — SAT solver wrapper in Julia** (~200 LOC, `src/solvers/picosat.jl` or `src/solvers/cadical.jl`)

Thin ccall wrapper around libpicosat, or subprocess interface to CaDiCaL binary in DIMACS format. Prerequisite for all subsequent SAT passes. Verify with a trivial 3-SAT instance.

**Step 2 — SWAP-optimal layout synthesis** (~600-900 LOC, `src/passes/layout_sat.jl`)

Q-Synth v2 style parallel-plan SAT encoding (SHAIK-SAT-DEEP-100Q Algorithm 1). Input: CNOT dependency DAG + coupling graph. Output: initial qubit mapping + SWAP-annotated gate sequence. Use incremental SAT. Highest-impact NISQ compilation pass; clear reference implementation available (Q-Synth v2 source on GitHub: irfansha/Q-Synth).

**Step 3 — Clifford circuit synthesis** (~1000-1500 LOC, `src/passes/clifford_synth.jl`)

Stabilizer tableau (2n×(2n+1) binary matrix) + Gottesman-Knill update rules for Sturm.jl's four primitives. CNF encoding following BERENT-CLIFFORD-SAT Section 4. Binary search on gate count T. Supports `src/qecc/Steane` directly — synthesizes depth-optimal encoder/decoder circuits using Sturm.jl primitives.

**Step 4 — MaxSAT mapping** (~800 LOC, `src/passes/layout_maxsat.jl`)

MAXSAT-QUBIT-MAP encoding. Useful as time-bounded "best effort optimal" compilation mode. Circuit slicing for large circuits. Requires Open-WBO or RC2 as subprocess.

**Step 5 — ILP routing via JuMP** (~800-1200 LOC, `src/passes/layout_ilp.jl`)

NANNICINI-ILP-ROUTING BIP using JuMP.jl + HiGHS (freely available, Apache 2). Best choice when per-edge gate fidelity data is available and multi-objective optimization (error rate + depth + crosstalk) is needed.

**Step 6 — Depth-optimal layout synthesis** (~600 LOC extension of Step 2, `src/passes/layout_sat_depth.jl`)

Extend Step 2's parallel-plan encoding to optimize CX-depth rather than SWAP count, following JAKOBSEN-SAT-DEPTH-OPT. Key change: parallel step encodes one layer of independent gates (SWAP gate handled over 3 time steps).

**Step 7 — MILP unitary synthesis** (~1000 LOC or reuse QCOpt, `src/passes/unitary_milp.jl`)

For QECC subroutine synthesis (up to ~8 qubits), evaluate integrating `QuantumCircuitOpt.jl` directly as a Julia package dependency. Enables provably optimal gate synthesis for error correction syndrome extraction circuits.

---

## Open problems

1. **Combined synthesis + layout co-optimization**: No tool jointly optimizes logical gate set (circuit synthesis) and physical mapping (layout synthesis). Sequential decomposition is suboptimal — co-optimization could exploit degrees of freedom in both problems simultaneously.

2. **Scaling exact synthesis beyond ~10 qubits**: Clifford synthesis limited to 6 qubits optimally (BERENT-CLIFFORD-SAT); general unitary synthesis limited to small circuits (NAGARAJAN-MIP-OPTIMAL). Search space grows as 2^Θ(n²) for Clifford and 4^Q for general unitaries. No approach has broken this barrier while maintaining optimality.

3. **Noise model fidelity in exact methods**: Most papers optimize SWAP count or CX-count as a noise proxy. NANNICINI-ILP-ROUTING incorporates per-edge fidelity weights; JAKOBSEN-SAT-DEPTH-OPT finds CX-count alone correlates better with noise than CX-depth alone. The ground-truth noise model (decoherence, crosstalk, non-Markovian errors) is not yet captured by any SAT/ILP objective function.

4. **Depth-optimal synthesis remains orders of magnitude slower than count-optimal**: Makespan for CX-depth-optimal encoding scales with the CX-depth of the solution, making it fundamentally harder. QuiLS is 10-100x faster than OLSQ2 for depth but still slower than Q-Synth v2 for count (JAKOBSEN-SAT-DEPTH-OPT).

5. **Warm-starting exact solvers from heuristics at scale**: BOOTH-CP-TEMPORAL demonstrates temporal planning solutions can warm-start CP solvers with significant quality gains. Systematic warm-starting of SAT/ILP mapping from SABRE into Q-Synth v2 or QuiLS has not been explored and could extend the solvable instance range.

6. **FTQC lattice surgery at algorithm scale**: LaSynth optimizes 5-20 qubit subroutines with 10-100 operations. Cryptographically relevant Shor's algorithm requires thousands of logical qubits and millions of operations. Scaling lattice surgery SAT optimization to algorithm-level circuits remains completely open.

7. **Tractable subclasses beyond Clifford**: BERENT-SAT-JOURNEY establishes that direct SAT encoding of arbitrary quantum circuits with entanglement is infeasible in general. Finding tractable subclasses beyond Clifford (bounded entanglement, specific algorithm families like QFT or QAOA) is an open theoretical and practical problem.

8. **Incremental + parallel solving for depth-optimal**: Incremental SAT techniques that make AMAZON-SAT-MAPPING and SHAIK-SAT-DEEP-100Q competitive have not been fully developed for depth-optimal encodings. Portfolio-style parallel solving across independent sub-problems is unexplored for QuiLS-style formulations.
