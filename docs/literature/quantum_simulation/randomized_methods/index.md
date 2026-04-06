# Randomized Methods / qDRIFT — Index (REPORTING_STANDARD format)

See `survey.md` for full narrative. This file provides the per-paper entries in the
format required by `docs/literature/REPORTING_STANDARD.md` for cross-referencing.

---

### [CAMPBELL-qDRIFT] Campbell (2019) — A Random Compiler for Fast Hamiltonian Simulation
- **arXiv/DOI**: arXiv:1811.08017 / doi:10.1103/PhysRevLett.123.070503
- **PDF status**: not_found (PRL paywalled; arXiv version freely available)
- **Category**: OTHER (randomized simulation / HAMILTONIAN_SIM)
- **Key idea**: Samples Hamiltonian terms proportional to coefficient magnitude (ℓ₁ norm λ), making gate count O(λ²t²/ε) and independent of number of terms L; average channel approximates target evolution in diamond norm.
- **Relevance to Sturm.jl**: Each sampled exponential maps directly to the 4 primitives (Ry/Rz/CNOT); qDRIFT produces a CPTP channel, fully consistent with Sturm's channel-first DAG IR.
- **Cites/cited-by**: Supersedes [LLOYD-1996], [CHILDS-RANDOMIZE]; superseded by [NAKAJI-qSWIFT], [HAGAN-COMPOSITE]

---

### [CHILDS-RANDOMIZE] Childs, Ostrander, Su (2019) — Faster Quantum Simulation by Randomization
- **arXiv/DOI**: arXiv:1805.08385 / doi:10.22331/q-2019-09-02-182
- **PDF status**: not_found (open access via Quantum journal)
- **Category**: OTHER
- **Key idea**: Randomizing summand ordering in product formulas of any order gives bounds asymptotically better than commutator-based bounds, without requiring detailed Hamiltonian structure.
- **Relevance to Sturm.jl**: Random ordering of DAG gate blocks at compile time; applicable inside `passes/` as a circuit reordering pass.
- **Cites/cited-by**: Precedes [CAMPBELL-qDRIFT]; superseded for high-order by [FAEHRMANN-MPF]

---

### [CHILDS-TROTTER-ERROR] Childs, Su, Tran, Wiebe, Zhu (2021) — Theory of Trotter Error with Commutator Scaling
- **arXiv/DOI**: arXiv:1912.08854 / doi:10.1103/PhysRevX.11.011020
- **PDF status**: not_found (open access PRX)
- **Category**: OTHER
- **Key idea**: Tight Trotter error bounds exploiting commutator structure directly, without BCH truncation; reproduces known tight bounds for 1st/2nd order and gives near-tight higher-order bounds.
- **Relevance to Sturm.jl**: Informs which Trotter decompositions to use in the deterministic block of composite methods; useful for `passes/clifford_simp` cost estimates.
- **Cites/cited-by**: Extends Berry et al. (2007, 2015); cited by [HAGAN-COMPOSITE], [GUNTHER-PARTIAL]

---

### [CHEN-CONCENTRATION] Chen, Huang, Kueng, Tropp (2021) — Concentration for Random Product Formulas
- **arXiv/DOI**: arXiv:2008.11751 / doi:10.1103/PRXQuantum.2.040305
- **PDF status**: not_found (open access PRX Quantum)
- **Category**: OTHER
- **Key idea**: Individual qDRIFT circuit realizations concentrate around the ideal unitary in diamond norm; a single random draw is a good simulation, not just the ensemble average.
- **Relevance to Sturm.jl**: Justifies implementing qDRIFT as a single-shot `Channel` factory without averaging; reduces sampling overhead in the `EagerContext`.
- **Cites/cited-by**: Depends on [CAMPBELL-qDRIFT]; cited by [KISS-IMPORTANCE], [FAEHRMANN-MPF]

---

### [BERRY-TIMEDEP] Berry, Childs, Su, Wang, Wiebe (2020) — Time-Dependent Hamiltonian Simulation with L¹-Norm Scaling
- **arXiv/DOI**: arXiv:1906.07115 / doi:10.22331/q-2020-04-20-254
- **PDF status**: not_found (open access Quantum journal)
- **Category**: OTHER
- **Key idea**: Gate complexity scales with integral ∫‖H(τ)‖dτ rather than t·max‖H‖; classical sampler + Schrödinger rescaling principle.
- **Relevance to Sturm.jl**: Time-dependent simulation maps to a sequence of `Channel` compositions with varying coefficients; relevant to adiabatic paths in the DSL.
- **Cites/cited-by**: Depends on LCU (Berry et al. 2015); cited by [DUBUS-MARKOV]

---

### [FAEHRMANN-MPF] Faehrmann, Steudtner, Kueng, Kieferova, Eisert (2022) — Randomizing Multi-Product Formulas
- **arXiv/DOI**: arXiv:2101.07808 / doi:10.22331/q-2022-09-19-806
- **PDF status**: not_found (open access Quantum journal)
- **Category**: OTHER
- **Key idea**: Randomized multi-product formulas eliminate need for oblivious amplitude amplification in LCU-based MPF; error shrinks exponentially with circuit depth.
- **Relevance to Sturm.jl**: MPF structure in DAG can be implemented as Richardson-extrapolated channel compositions; Sturm's `channel/` module is the natural home.
- **Cites/cited-by**: Depends on [CHEN-CONCENTRATION], [CHILDS-RANDOMIZE]; partially superseded by [NAKAJI-qSWIFT]

---

### [OUYANG-SPARSTO] Ouyang, White, Campbell (2020) — Compilation by Stochastic Hamiltonian Sparsification
- **arXiv/DOI**: arXiv:1910.06255 / doi:10.22331/q-2020-02-27-235
- **PDF status**: not_found (open access Quantum journal)
- **Category**: OTHER
- **Key idea**: Stochastically removes weak Hamiltonian terms via convex-optimization-derived probabilities, achieving quadratic error suppression and interpolating between qDRIFT and randomized Trotter.
- **Relevance to Sturm.jl**: Sparsification step is a classical preprocessing pass on the Hamiltonian data structure; output is a standard qDRIFT or Trotter circuit.
- **Cites/cited-by**: Depends on [CAMPBELL-qDRIFT], [CHILDS-RANDOMIZE]; superseded in spirit by [HAGAN-COMPOSITE]

---

### [KISS-IMPORTANCE] Kiss, Grossi, Roggero (2023) — Importance Sampling for Stochastic Quantum Simulations
- **arXiv/DOI**: arXiv:2212.05952 / doi:10.22331/q-2023-04-13-977
- **PDF status**: not_found (open access Quantum journal)
- **Category**: OTHER
- **Key idea**: Generalizes qDRIFT to arbitrary sampling distributions, controlling both bias and variance; reduces circuit count by sampling cheaper operations more frequently.
- **Relevance to Sturm.jl**: Sampling distribution is a compile-time parameter; can be implemented as a configurable option in the qDRIFT channel factory.
- **Cites/cited-by**: Depends on [CAMPBELL-qDRIFT], [CHEN-CONCENTRATION]

---

### [WAN-PHASE] Wan, Berta, Campbell (2022) — Randomized Quantum Algorithm for Statistical Phase Estimation
- **arXiv/DOI**: arXiv:2110.12071 / doi:10.1103/PhysRevLett.129.030503
- **PDF status**: not_found (PRL paywalled; arXiv version available)
- **Category**: OTHER
- **Key idea**: Phase estimation with L-independent circuit depth; all error suppressed by collecting more classical samples, not by increasing circuit depth.
- **Relevance to Sturm.jl**: Phase estimation subroutine in the DSL can use qDRIFT as simulation oracle; separation of circuit depth from precision improves near-term applicability.
- **Cites/cited-by**: Depends on [CAMPBELL-qDRIFT], [CHEN-CONCENTRATION]; superseded for chemistry by [GUNTHER-PARTIAL]

---

### [NAKAJI-qSWIFT] Nakaji, Bagherimehrab, Aspuru-Guzik (2024) — High-Order Randomized Compiler (qSWIFT)
- **arXiv/DOI**: arXiv:2302.14811 / doi:10.1103/PRXQuantum.5.020330
- **PDF status**: not_found (open access PRX Quantum)
- **Category**: OTHER
- **Key idea**: K-th order generalization of qDRIFT with gate count O(λt²/ε^{1/K}), independent of L; single ancilla; 1000× fewer gates than qDRIFT at 10⁻⁶ error.
- **Relevance to Sturm.jl**: Drop-in replacement for qDRIFT when higher precision is needed; same 4-primitive circuit structure, higher-order sampling scheme.
- **Cites/cited-by**: Supersedes [CAMPBELL-qDRIFT]; depends on [FAEHRMANN-MPF]

---

### [HAGAN-COMPOSITE] Hagan, Wiebe (2023) — Composite Quantum Simulations
- **arXiv/DOI**: arXiv:2206.06409 / doi:10.22331/q-2023-11-14-1181
- **PDF status**: not_found (open access Quantum journal)
- **Category**: OTHER
- **Key idea**: Framework for combining Trotter and qDRIFT into a composite channel, partitioning Hamiltonian terms by size; provably no worse than the better individual method, better at intermediate gate budgets.
- **Relevance to Sturm.jl**: Composite channel is a sequential composition of two `Channel` objects in the DAG; natural representation in Sturm's channel IR.
- **Cites/cited-by**: Depends on [CAMPBELL-qDRIFT], [CHILDS-TROTTER-ERROR]; extended by [POCRNIC-IMAGINARY]

---

### [POCRNIC-IMAGINARY] Pocrnic, Hagan, Carrasquilla, Segal, Wiebe (2024) — Composite QDrift in Imaginary Time
- **arXiv/DOI**: arXiv:2306.16572 / doi:10.1103/PhysRevResearch.6.013224
- **PDF status**: not_found (open access PRR)
- **Category**: OTHER
- **Key idea**: Extends composite qDRIFT-Trotter to imaginary-time evolution; enables quantum Monte Carlo acceleration; local composite channels exploit Lieb-Robinson bounds for 20× speedup on Jellium.
- **Relevance to Sturm.jl**: Imaginary-time channels are non-unitary; relevant to `DensityMatrixContext` and future QECC decoders that use imaginary-time preparation.
- **Cites/cited-by**: Extends [HAGAN-COMPOSITE]

---

### [RAJPUT-HYBRID] Rajput, Roggero, Wiebe (2022) — Hybridized Methods in the Interaction Picture
- **arXiv/DOI**: arXiv:2109.03308 / doi:10.22331/q-2022-08-17-780
- **PDF status**: not_found (open access Quantum journal)
- **Category**: OTHER
- **Key idea**: Combines interaction picture simulation (large asymptotic savings) with qubitization-compatible methods (small constants) by hybridizing them; achieves log²Λ scaling for Schwinger model.
- **Relevance to Sturm.jl**: Interaction picture split maps to two DAG blocks with different time scales; relevant for gauge theory simulation in Sturm.
- **Cites/cited-by**: Depends on Low-Wiebe interaction picture (2018); [CHILDS-RANDOMIZE]

---

### [DAVID-OPEN] David, Sinayskiy, Petruccione (2024) — Faster Simulation of Open Quantum Systems via Randomisation
- **arXiv/DOI**: arXiv:2408.11683
- **PDF status**: not_found (arXiv preprint)
- **Category**: OTHER
- **Key idea**: Extends qDRIFT to Lindblad open systems; QDRIFT channel maintains CPTP physicality; gate complexity L-independent; new error bounds bypass mixing lemma.
- **Relevance to Sturm.jl**: QDRIFT channel for Lindblad fits directly in `noise/` module using `DensityMatrixContext`; L-independence important for realistic noise models with many jump operators.
- **Cites/cited-by**: Depends on [CAMPBELL-qDRIFT]; extended by [YANG-LCHS]

---

### [DING-LOWER] Ding, Junge, Schleich, Wu (2025) — Lower Bounds for Open System Simulation
- **arXiv/DOI**: arXiv:2407.15357 / doi:10.1007/s00220-025-05240-6
- **PDF status**: not_found (paywalled; arXiv version available)
- **Category**: OTHER
- **Key idea**: General lower bounds on circuit depth for Markov semigroup simulation via convexified circuit depth and Lipschitz continuity; tight in several examples.
- **Relevance to Sturm.jl**: Establishes fundamental limits that Sturm's `DensityMatrixContext` simulation cannot beat; informs pass design for noise simulation.
- **Cites/cited-by**: Depends on open-system simulation theory; complements [DAVID-OPEN]

---

### [DUBUS-MARKOV] Dubus, Cunningham, Roland (2024) — New Random Compiler via Markov Chains
- **arXiv/DOI**: arXiv:2411.06485
- **PDF status**: not_found (arXiv preprint)
- **Category**: OTHER
- **Key idea**: Continuous-time Markov chain framework for random compilers generalizes qDRIFT to time-dependent and adiabatic settings; gate count Õ(C²T²/ε).
- **Relevance to Sturm.jl**: Most general first-order random compiler; relevant for adiabatic state preparation in Sturm DSL.
- **Cites/cited-by**: Generalizes [CAMPBELL-qDRIFT]; extends [BERRY-TIMEDEP]

---

### [WANG-RTS] Wang, Zhao (2024) — Randomization Accelerates Series-Truncated Algorithms
- **arXiv/DOI**: arXiv:2402.05595
- **PDF status**: not_found (arXiv preprint)
- **Category**: OTHER
- **Key idea**: RTS achieves quadratic error suppression for any algorithm using truncated series (LCU, QSP, Dyson); randomly mixes two circuits so their average has error ε².
- **Relevance to Sturm.jl**: Applicable to Sturm's LCU-based gates; reduces effective circuit depth for high-precision simulation in `passes/`.
- **Cites/cited-by**: Related to [MARTYN-STOCHASTIC-QSP]

---

### [MARTYN-STOCHASTIC-QSP] Martyn, Rall (2025) — Halving the Cost of Quantum Algorithms with Randomization
- **arXiv/DOI**: arXiv:2409.03744 / doi:10.1038/s41534-025-01003-2
- **PDF status**: not_found (npj open access)
- **Category**: OTHER
- **Key idea**: Stochastic QSP randomizes the QSP polynomial to achieve ε→O(ε²), reducing query complexity of all QSP-based algorithms by factor ~1/2 asymptotically.
- **Relevance to Sturm.jl**: Applicable to any QSP-based gate or simulation in Sturm; potential 2–4× reduction in ancilla-qubit circuit depth.
- **Cites/cited-by**: Depends on QSP (Low-Chuang); related to [WANG-RTS]

---

### [GUNTHER-PARTIAL] Günther et al. (2025) — Phase Estimation with Partially Randomized Time Evolution
- **arXiv/DOI**: arXiv:2503.05647
- **PDF status**: not_found (arXiv preprint)
- **Category**: OTHER
- **Key idea**: Partial randomization (some terms deterministic, some sampled) for phase estimation; orders-of-magnitude improvements over deterministic product formulas; competitive with qubitization scaling for hydrogen chains.
- **Relevance to Sturm.jl**: Best practical randomized approach for energy estimation; directly maps to `phase_estimate!` in `library/patterns.jl` with a qDRIFT-backed time-evolution `Channel`.
- **Cites/cited-by**: Depends on [WAN-PHASE], [CHILDS-TROTTER-ERROR], [CAMPBELL-qDRIFT]

---

### [YANG-LCHS] Yang, Liu (2025) — Randomized Quantum Simulation of Non-Unitary Dynamics
- **arXiv/DOI**: arXiv:2509.08030
- **PDF status**: not_found (arXiv preprint)
- **Category**: OTHER
- **Key idea**: Random-LCHS randomizes both outer LCU and inner Hamiltonian simulation (continuous qDRIFT) for non-unitary dynamics; observable-driven and symmetry-aware variants.
- **Relevance to Sturm.jl**: Non-unitary simulation maps to Sturm's `DensityMatrixContext`; observable-driven variant aligns with measurement-focused channel semantics.
- **Cites/cited-by**: Depends on LCHS (An-Liu 2023); [DAVID-OPEN]; [CAMPBELL-qDRIFT]

---

### [HASTINGS-INCOHERENT] Hastings (2016) — Turning Gate Synthesis Errors into Incoherent Errors
- **arXiv/DOI**: arXiv:1612.01011
- **PDF status**: not_found (arXiv preprint)
- **Category**: OTHER
- **Key idea**: Randomizing over gate synthesis alternatives converts coherent error accumulation O(Nε) to incoherent O(√N·ε); conceptual foundation for randomized compiling.
- **Relevance to Sturm.jl**: Relevant to Orkan FFI layer: if gate approximations are randomized, Sturm's EagerContext benefits from incoherent error accumulation.
- **Cites/cited-by**: Precedes [CAMPBELL-qDRIFT]

---

### [LAYDEN-SECOND-ORDER] Layden (2022) — First-Order Trotter Error from a Second-Order Perspective
- **arXiv/DOI**: arXiv:2107.08032 / doi:10.1103/PhysRevLett.128.210501
- **PDF status**: not_found (PRL paywalled; arXiv version available)
- **Category**: OTHER
- **Key idea**: First-order Trotter error explained via quantum interference between error components of first and second-order formulas; improved bounds match actual errors over many orders of magnitude.
- **Relevance to Sturm.jl**: Improved first-order bounds reduce circuit depth in the Trotter block of composite methods [HAGAN-COMPOSITE].
- **Cites/cited-by**: Depends on [CHILDS-TROTTER-ERROR]

---

### [LLOYD-1996] Lloyd (1996) — Universal Quantum Simulators
- **arXiv/DOI**: doi:10.1126/science.273.5278.1073
- **PDF status**: not_found (paywalled Science; widely redistributed)
- **Category**: OTHER
- **Key idea**: First proof that local quantum systems can be efficiently simulated on a quantum computer using Trotter product formulas; foundation for all subsequent Hamiltonian simulation work.
- **Relevance to Sturm.jl**: Historical foundation; the Trotter structure underlies all `Channel` decompositions in Sturm's simulator.
- **Cites/cited-by**: Depends on Trotter (1959), Suzuki (1990); superseded by all subsequent work

---

## TOPIC SUMMARY
- Papers found: 21
- Papers downloaded: 0 (all located on arXiv or open-access journals; PDFs not fetched)
- Top 3 most relevant to Sturm.jl: [CAMPBELL-qDRIFT], [HAGAN-COMPOSITE], [DAVID-OPEN]
- Key insight for implementation: qDRIFT maps directly to Sturm's 4-primitive DSL and channel IR; each sampled Hamiltonian term is a product of Ry/Rz/CNOT, and the average channel is CPTP — fully consistent with Sturm's design. Composite methods (Hagan-Wiebe) and the open-system extension (David et al.) are the highest-priority implementation targets.
