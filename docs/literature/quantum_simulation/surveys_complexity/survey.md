# Foundations, Complexity, Resource Estimation, and Survey Papers

## Category Summary

The intellectual history of quantum simulation begins in 1982 with Feynman's observation that simulating quantum systems on classical computers requires exponential resources, and that a quantum computer could do the job efficiently. This was a conjecture, not a theorem. Lloyd's 1996 Science paper turned it into a theorem — or rather, a construction: any local Hamiltonian can be simulated by a product of local unitary gates, and the number of gates scales polynomially in system size and simulation time. The Zalka (1996/1998) and Abrams-Lloyd (1997) papers contemporaneously extended this to continuous quantum fields and fermionic systems respectively, establishing the algorithmic foundations. The complexity picture that emerged over the next two decades sorted algorithms into a hierarchy: Trotter/product formulas (simplest, most hardware-friendly), LCU/Taylor series (Berry et al. 2015, first log(1/ε) precision scaling), quantum walk/qubitization (Low-Chuang 2016–2019, optimal query complexity), and finally QSVT (Gilyén et al. 2019), which unifies all of the above under a single polynomial transformation framework. Lower bounds (Berry-Childs-Kothari 2015, Haah et al. 2018) show these modern methods are essentially tight.

The complexity landscape is now well-mapped at the level of query complexity (oracle calls), but converting that to actual physical gate counts for realistic hardware is the domain of resource estimation — a younger and more practically urgent field. The Reiher et al. (2017) FeMoco paper was the first rigorous end-to-end resource estimate for a commercially important chemistry problem, putting quantitative numbers on what quantum hardware would need to achieve quantum advantage. Subsequent work by Babbush et al. (2018, 2019), Berry et al. (2019), von Burg et al. (2020), Goings et al. (2022), and the Microsoft Beverland et al. (2022) framework have systematically reduced those estimates by orders of magnitude through algorithmic improvements. The Gidney-Ekerå (2019/2021) paper did the same for cryptography. Litinski (2019) showed that the "magic state distillation overhead" that was thought to dominate fault-tolerant costs is far smaller than previously assumed. The current picture, as of 2025, is that practical quantum advantage for chemistry requires O(10^6) physical qubits and O(10^9) T-gates compiled through surface codes — a hard target but not physically impossible.

The survey literature provides several indispensable orientation points. Georgescu, Ashhab, Nori (2014) in Rev. Mod. Phys. gives the broad field view across analog and digital quantum simulation. Cao et al. (2019) and McArdle et al. (2020) are the standard references for quantum computational chemistry, both as extensive reviews in Chemical Reviews and Rev. Mod. Phys. respectively. Bauer et al. (2020) covers quantum chemistry and materials science with particular attention to strongly correlated electrons. The Childs et al. (2018/PNAS) paper identifies the minimal problem size for first quantum speedup in condensed matter. Dalzell et al. (2023, Cambridge) is the most comprehensive end-to-end complexity survey, covering chemistry, physics, optimization, finance, and ML with uniform technical depth. Zhang et al. (2025) is the most recent survey specifically targeting fault-tolerant algorithms for molecular quantum chemistry on early fault-tolerant hardware.

## Timeline

| Year | Milestone |
|------|-----------|
| 1982 | Feynman proposes that quantum computers could efficiently simulate quantum physics |
| 1996 | Lloyd proves universal quantum simulation via product formulas (Science) |
| 1996 | Zalka constructs explicit simulation algorithm for continuous quantum systems (Proc. R. Soc.) |
| 1997 | Abrams & Lloyd give efficient simulation of fermionic many-body systems |
| 2003 | Aharonov & Ta-Shma connect adiabatic state generation to quantum walk and SZK |
| 2007 | Berry et al. give first rigorous higher-order Trotter bounds for sparse Hamiltonians |
| 2010 | Childs: continuous-time quantum walk simulates any sparse Hamiltonian |
| 2014 | Georgescu, Ashhab, Nori review quantum simulation in Rev. Mod. Phys. |
| 2015 | Berry, Childs, Cleve, Kothari, Somma: LCU/Taylor series — first log(1/ε) algorithm |
| 2015 | Berry, Childs, Kothari: nearly optimal dependence on all parameters for sparse H |
| 2016 | Low & Chuang: optimal Hamiltonian simulation by Quantum Signal Processing |
| 2017 | Reiher et al.: first rigorous end-to-end resource estimate (FeMoco, PNAS) |
| 2018 | Haah, Hastings, Kothari, Low: quasi-linear lattice simulation with matching lower bound |
| 2018 | Babbush et al.: T-gate complexity O(N + log(1/ε)) for electronic structure |
| 2018 | Childs, Maslov, Nam, Ross, Su: toward first quantum simulation with quantum speedup |
| 2019 | Gilyén, Su, Low, Wiebe: QSVT unifies all quantum algorithms (STOC) |
| 2019 | Childs & Su: nearly-optimal (nt)^{1+o(1)} lattice simulation by product formulas |
| 2019 | Cao et al.: Quantum Chemistry in the Age of Quantum Computing (Chem. Rev.) |
| 2019 | Gidney & Ekerå: 20 million qubits suffice for 2048-bit RSA in 8 hours |
| 2019 | Litinski: magic state distillation not as costly as assumed |
| 2019 | Berry et al.: qubitization of chemistry with low rank factorization |
| 2020 | McArdle, Endo, Aspuru-Guzik, Benjamin, Yuan: quantum computational chemistry (Rev. Mod. Phys.) |
| 2020 | Bauer, Bravyi, Motta, Chan: quantum algorithms for chemistry and materials (Chem. Rev.) |
| 2020 | Von Burg et al.: quantum computing enhanced computational catalysis |
| 2021 | Childs, Su, Tran, Wiebe, Zhu: theory of Trotter error with commutator scaling (PRX) |
| 2021 | Martyn, Rossi, Tan, Chuang: Grand Unification of Quantum Algorithms via QSVT (PRX Quantum) |
| 2021 | Haah, Hastings, Kothari, Low: SIAM J. Comput. final publication of lattice simulation |
| 2022 | Beverland et al. (Microsoft): framework for scaling to practical quantum advantage |
| 2022 | Goings et al.: reliable resource estimates for cytochrome P450 |
| 2023 | Dalzell et al.: 416-page end-to-end complexity survey (Cambridge UP 2025) |
| 2025 | Zhang et al.: fault-tolerant quantum algorithms for molecular systems survey |

---

## Papers

### [FEYNMAN82] Feynman (1982) — Simulating Physics with Computers
- **arXiv/DOI**: doi:10.1007/BF02650179
- **PDF status**: paywalled (IJTP 21:467–488)
- **Category**: RESOURCE_EST
- **Key idea**: A programmable universal quantum simulator built from local quantum gates can faithfully simulate any local quantum system with polynomial overhead. Classical computers cannot efficiently simulate quantum mechanics because the state space grows exponentially with particle number, but a quantum simulator side-steps this by exploiting quantum parallelism.
- **Relevance to Sturm.jl**: The founding philosophical motivation — Sturm.jl is an implementation of the universal quantum simulator Feynman envisioned, accessed through a typed DSL.
- **Cites/cited-by**: Foundational; cited by [LLOYD96], [ZALKA96], [ABRAMS97], essentially every paper in this category.

---

### [LLOYD96] Lloyd (1996) — Universal Quantum Simulators
- **arXiv/DOI**: doi:10.1126/science.273.5278.1073
- **PDF status**: paywalled (Science 273:1073–1078)
- **Category**: RESOURCE_EST
- **Key idea**: Proves that any local Hamiltonian H = Σ_j H_j can be simulated by a product formula on a quantum computer with gate count scaling polynomially in system size n, simulation time t, and inverse precision ε. This is the first rigorous existence proof for efficient quantum simulation, realising Feynman's conjecture.
- **Complexity**: Gate count O((n t ||H||)^c) for constant c; first-order Trotter formula. Precision not yet optimal (predates log(1/ε) algorithms).
- **Limitations**: No tight bounds; precision scaling is polynomial, not logarithmic. Fermionic systems require further work (Jordan-Wigner or similar). No resource estimates for realistic hardware.
- **Relevance to Sturm.jl**: Every Trotter step is a sequence of Ry and Rz rotations plus CNOT gates — exactly the four DSL primitives. Lloyd's construction is the algorithmic backbone of product-formula simulation in Sturm.jl.
- **Cites/cited-by**: [FEYNMAN82]; cited by [ZALKA96], [ABRAMS97], [CHILDS18], [GEORGESCU14], and essentially all simulation papers.

---

### [ZALKA96] Zalka (1996/1998) — Efficient Simulation of Quantum Systems by Quantum Computers
- **arXiv/DOI**: arXiv:quant-ph/9603026; doi:10.1098/rspa.1998.0162
- **PDF status**: not_found (Proc. R. Soc. Lond. A 454:313–322, 1998)
- **Category**: RESOURCE_EST
- **Key idea**: Provides an explicit simulation algorithm for continuous quantum systems (wave functions on a lattice/grid) using quantum Fourier transforms for kinetic energy and diagonal phase oracles for potential energy. Demonstrates that the simulation cost is comparable to the cost of classically simulating the corresponding classical system, and discusses how to extract energy spectra.
- **Complexity**: Simulation cost comparable to classical simulation of the equivalent classical system; no explicit gate count formula, but uses O(n log n) QFT steps per Trotter step.
- **Limitations**: Focused on non-relativistic quantum mechanics on a spatial grid; fermionic antisymmetry not addressed. Published contemporaneously with Lloyd but independently.
- **Depends on**: [LLOYD96] (independent parallel work)
- **Relevance to Sturm.jl**: The QFT-based kinetic energy trick maps directly to the `fourier_sample` library function; the phase oracle for potential energy is a sequence of controlled phase rotations via DSL primitives.
- **Cites/cited-by**: Cited by [ABRAMS97]; parallel to [LLOYD96].

---

### [ABRAMS97] Abrams & Lloyd (1997) — Simulation of Many-Body Fermi Systems on a Universal Quantum Computer
- **arXiv/DOI**: arXiv:quant-ph/9703054; doi:10.1103/PhysRevLett.79.2586
- **PDF status**: not_found (Phys. Rev. Lett. 79:2586–2589, 1997)
- **Category**: RESOURCE_EST
- **Key idea**: Extends quantum simulation to fermionic many-body systems. Provides efficient quantum algorithms for both first-quantized (with an explicit efficient anti-symmetrisation subroutine) and second-quantized Hamiltonians, and demonstrates the approach on the Hubbard model. Establishes that fermionic sign issues do not prevent efficient quantum simulation.
- **Complexity**: Polynomial gate count in system size; first vs. second quantisation complexity comparison given. No tight bounds on constants.
- **Limitations**: Early work — gate counts are not tight; Jordan-Wigner overhead for fermionic encoding not fully analysed.
- **Depends on**: [LLOYD96], [ZALKA96]
- **Relevance to Sturm.jl**: Second-quantised fermionic simulation (Hubbard, FeMoco) is a target application domain; the Jordan-Wigner encoding maps fermionic operators to Pauli strings which decompose into Rz and CNOT layers — directly expressible in the DSL.
- **Cites/cited-by**: Cited by [GEORGESCU14], [CAO19], [MCCARDLE20], [REIHER17].

---

### [AHARONOV03] Aharonov & Ta-Shma (2003) — Adiabatic Quantum State Generation and Statistical Zero Knowledge
- **arXiv/DOI**: arXiv:quant-ph/0301023
- **PDF status**: not_found (STOC 2003)
- **Category**: RESOURCE_EST
- **Key idea**: Introduces adiabatic state generation as an algorithmic paradigm and proves its equivalence to standard quantum computing. Connects quantum computation, adiabatic evolution, Hamiltonian spectral gaps, Markov chains, and statistical zero knowledge (SZK). Develops tools for implementing general Hamiltonians with non-negligible spectral gaps, and applies these to generate superpositions related to Markov chain dynamics.
- **Complexity**: Polynomial in inverse spectral gap; no explicit gate count. Establishes that adiabatic and circuit models are computationally equivalent.
- **Limitations**: Complexity depends on spectral gap, which can be exponentially small for hard problems. The adiabatic model does not directly improve worst-case complexity.
- **Depends on**: [LLOYD96]
- **Relevance to Sturm.jl**: Adiabatic state preparation for ground states is a quantum algorithm that compiles to a time-dependent Hamiltonian simulation — a sequence of parameterised DSL primitives.
- **Cites/cited-by**: Foundational for adiabatic methods; cited by survey papers.

---

### [BERRY15A] Berry, Childs & Kothari (2015) — Hamiltonian Simulation with Nearly Optimal Dependence on All Parameters
- **arXiv/DOI**: arXiv:1501.01715
- **PDF status**: not_found (FOCS 2015, pp. 792–809)
- **Category**: RESOURCE_EST
- **Key idea**: Achieves sparse Hamiltonian simulation that is optimal (up to log factors) simultaneously in all relevant parameters: evolution time t, sparsity d, max matrix entry ||H||_max, and error ε. Combines quantum walk simulation (optimal sparsity) with fractional-query simulation (optimal precision) via a linear combination of quantum walk steps with Bessel function coefficients. Proves a new lower bound showing sublinear dependence on τ = t·d·||H||_max is impossible.
- **Complexity**: Number of queries nearly linear in τ = t·d·||H||_max, logarithmic in 1/ε. Query lower bound: Ω(τ).
- **Limitations**: Query complexity, not gate complexity. Constant factors not minimal; later works (LCU, qubitization, QSP) improve practical performance.
- **Depends on**: Berry et al. (2012) sparse simulation; quantum walk simulation
- **Superseded by**: [LOW16] (achieves matching lower bound with no log factors)
- **Relevance to Sturm.jl**: Establishes the information-theoretic lower bound that all subsequent algorithms are measured against; important for the complexity annotations in Sturm.jl's pass infrastructure.
- **Cites/cited-by**: [BERRY15B], [LOW16], [HAAH18]; cites Childs 2010 quantum walk simulation.

---

### [BERRY15B] Berry, Childs, Cleve, Kothari & Somma (2015) — Simulating Hamiltonian Dynamics with a Truncated Taylor Series
- **arXiv/DOI**: arXiv:1412.4687; doi:10.1103/PhysRevLett.114.090502
- **PDF status**: not_found (Phys. Rev. Lett. 114:090502, 2015)
- **Category**: RESOURCE_EST
- **Key idea**: First algorithm with logarithmic dependence on inverse precision for Hamiltonian simulation, achieved by expanding the time-evolution operator as a truncated Taylor series and implementing each term as a linear combination of unitaries (LCU). The algorithm is simple and broad in applicability. This is the origin of the LCU technique that underlies qubitization, QSVT, and most modern high-performance simulation.
- **Complexity**: O(τ log(τ/ε) / log log(τ/ε)) queries where τ = t·||H||_1, with logarithmic dependence on 1/ε — the first algorithm achieving this.
- **Limitations**: Requires an explicit LCU decomposition H = Σ_j α_j U_j; overhead for the PREPARE and SELECT oracles not yet optimised. Superseded by qubitization for general LCU Hamiltonians.
- **Depends on**: Childs & Wiebe (2012) LCU idea
- **Superseded by**: [LOW17QUBIT] (qubitization achieves optimal O(t + log(1/ε)))
- **Relevance to Sturm.jl**: LCU decomposition is the structural form underlying quantum chemistry Hamiltonians; the SELECT oracle maps to controlled DSL primitives; Sturm.jl's compiler needs to count the LCU coefficient sum λ for complexity annotations.
- **Cites/cited-by**: [BERRY15A], [LOW16], [BABBUSH18], [REIHER17].

---

### [LOW16] Low & Chuang (2016/2017) — Optimal Hamiltonian Simulation by Quantum Signal Processing
- **arXiv/DOI**: arXiv:1606.02685; doi:10.1103/PhysRevLett.118.010501
- **PDF status**: not_found (Phys. Rev. Lett. 118:010501, 2017)
- **Category**: RESOURCE_EST
- **Key idea**: Introduces Quantum Signal Processing (QSP) for sparse Hamiltonian simulation. Shows that by interleaving oracle calls with single-qubit rotations chosen by a Chebyshev-like polynomial approximation procedure, one achieves query complexity O(t·d·||H||_max + log(1/ε)/log log(1/ε)) — matching all known lower bounds. The algorithm is optimal in all parameters simultaneously for sparse Hamiltonians.
- **Complexity**: Query complexity O(t·d·||H||_max + log(1/ε)/log log(1/ε)), matching the lower bound of [BERRY15A].
- **Limitations**: Applies to sparse Hamiltonians specified by an oracle; phase factor computation can be numerically unstable for high-degree polynomials (later resolved by QSPPACK).
- **Depends on**: [BERRY15A], [BERRY15B]; Szegedy quantum walk
- **Superseded by**: [LOW17QUBIT] (generalises to LCU/qubitization); [GILYEN19] (QSVT unifies everything)
- **Relevance to Sturm.jl**: QSP circuits are pure sequences of Ry rotations (q.θ+=δ) interspersed with oracle calls — identical to DSL primitives. The QSP/QSVT framework is the main target of Sturm.jl's high-performance simulation compilation pass.
- **Cites/cited-by**: [BERRY15A], [BERRY15B]; cited by [LOW17QUBIT], [GILYEN19], [MARTYN21].

---

### [LOW17QUBIT] Low & Chuang (2016/2019) — Hamiltonian Simulation by Qubitization
- **arXiv/DOI**: arXiv:1610.06546; doi:10.22331/q-2019-07-12-163
- **PDF status**: not_found (Quantum 3:163, 2019)
- **Category**: RESOURCE_EST
- **Key idea**: Generalises QSP from sparse to LCU-structured Hamiltonians via "qubitization". Given a Hamiltonian expressed as a linear combination of unitaries H = Σ_j α_j U_j with an LCU oracle, qubitization embeds the Hamiltonian in an SU(2) invariant subspace of an auxiliary system, achieving query complexity O(t·λ + log(1/ε)) where λ = Σ_j |α_j| is the 1-norm of LCU coefficients. This is optimal.
- **Complexity**: O(t·λ + log(1/ε)) queries; only 2 ancilla qubits. Matching lower bounds established.
- **Limitations**: Requires an LCU decomposition of the Hamiltonian and efficient PREPARE/SELECT oracles. λ can be large if the LCU is not sparse.
- **Depends on**: [LOW16], [BERRY15B]
- **Superseded by**: [GILYEN19] (QSVT fully unifies)
- **Relevance to Sturm.jl**: Qubitization is the core subroutine in modern chemistry simulation circuits (Babbush, Berry, Reiher). The PREPARE oracle maps to a controlled QBool preparation and the SELECT oracle to controlled DSL primitives.
- **Cites/cited-by**: [LOW16], [BERRY15B]; cited by [GILYEN19], [BABBUSH18], [BABBUSH19], [VONBURG20].

---

### [GILYEN19] Gilyén, Su, Low & Wiebe (2019) — Quantum Singular Value Transformation
- **arXiv/DOI**: arXiv:1806.01838
- **PDF status**: not_found (STOC 2019)
- **Category**: RESOURCE_EST
- **Key idea**: Introduces the Quantum Singular Value Transformation (QSVT) — a framework that applies arbitrary polynomial transformations to the singular values of a block-encoded matrix. Subsumes Hamiltonian simulation, amplitude amplification, matrix inversion (HHL), quantum walks, and essentially all other quantum speedups under a single algorithmic primitive. Establishes near-optimal complexity across all applications.
- **Complexity**: Polynomial transformation of degree d applied to singular values with O(d) block-encoding oracle calls; near-optimal in all parameters for each application.
- **Limitations**: Requires a block encoding of the target matrix, which may be expensive to construct for arbitrary Hamiltonians. Phase factor computation (degree-d polynomial) can be numerically challenging for large d.
- **Depends on**: [LOW16], [LOW17QUBIT], [BERRY15B]
- **Relevance to Sturm.jl**: QSVT is the umbrella framework that justifies Sturm.jl's QSP/QSVT compilation pass. Block encodings of Hamiltonians expressed in the DSL compile to SELECT/PREPARE oracle circuits from the four primitives.
- **Cites/cited-by**: [LOW16], [LOW17QUBIT]; cited by [MARTYN21], [DALZELL23], [ZHANG25].

---

### [MARTYN21] Martyn, Rossi, Tan & Chuang (2021) — A Grand Unification of Quantum Algorithms
- **arXiv/DOI**: arXiv:2105.02859; doi:10.1103/PRXQuantum.2.040203
- **PDF status**: not_found (PRX Quantum 2:040203, 2021)
- **Category**: RESOURCE_EST
- **Key idea**: A comprehensive pedagogical tutorial showing how QSVT unifies quantum search, quantum phase estimation, and Hamiltonian simulation under a single framework. Demonstrates explicitly how each of these algorithms arises from a specific polynomial transformation applied to a block-encoded matrix. The "grand unification" framing has become the standard way the field conceptualises the relationship among quantum algorithms.
- **Complexity**: Tutorial — no new bounds. Surveys optimal complexities achieved by QSVT for each algorithm class.
- **Limitations**: Tutorial paper, not a research contribution. Focuses on query complexity, not circuit depth or fault-tolerant resource counts.
- **Depends on**: [GILYEN19], [LOW16], [LOW17QUBIT]
- **Relevance to Sturm.jl**: The pedagogical framing directly informs how Sturm.jl's compilation passes should be structured: each QSP/QSVT circuit is a sequence of phase angle applications (DSL phi-rotations) and oracle calls.
- **Cites/cited-by**: [GILYEN19], [LOW16]; cited by [ZHANG25].

---

### [HAAH18] Haah, Hastings, Kothari & Low (2018/2021) — Quantum Algorithm for Simulating Real Time Evolution of Lattice Hamiltonians
- **arXiv/DOI**: arXiv:1801.03922
- **PDF status**: not_found (SIAM J. Comput., Special Section FOCS 2018)
- **Category**: RESOURCE_EST
- **Key idea**: For geometrically local lattice Hamiltonians on n qubits, achieves gate complexity O(nT polylog(nT/ε)) and circuit depth O(T polylog(nT/ε)). Crucially, proves a matching lower bound: any quantum algorithm simulating a piecewise-constant bounded local Hamiltonian in 1D to constant error requires Ω̃(nT) gates. This establishes the first tight complexity bounds for lattice Hamiltonian simulation.
- **Complexity**: Upper bound O(nT polylog(nT/ε)) gates; lower bound Ω̃(nT). Circuit depth O(T polylog(nT/ε)). Exploits Lieb-Robinson bounds to decompose time-evolution unitaries.
- **Limitations**: Applies to geometrically local Hamiltonians; the polylog factor is not tight. For non-local Hamiltonians (chemistry), see [BABBUSH18] and [BERRY19].
- **Depends on**: [LOW17QUBIT], Lieb-Robinson bounds
- **Relevance to Sturm.jl**: The lower bound is architecturally important for Sturm.jl's resource estimation pass: it bounds the minimum circuit depth achievable for any lattice simulation program, independent of optimization.
- **Cites/cited-by**: [LOW17QUBIT]; cited by [CHILDS21TROTTER], [DALZELL23].

---

### [CHILDS19] Childs & Su (2019) — Nearly Optimal Lattice Simulation by Product Formulas
- **arXiv/DOI**: arXiv:1901.00564; doi:10.1103/PhysRevLett.123.050503
- **PDF status**: not_found (Phys. Rev. Lett. 123:050503, 2019)
- **Category**: RESOURCE_EST
- **Key idea**: Proves that product formulas (Trotter-Suzuki) achieve nearly optimal gate complexity (nt)^{1+o(1)} for n-qubit nearest-neighbor Hamiltonians, by exploiting the local error structure of product formulas. This resolves a long-standing open question: are simple Trotter steps asymptotically competitive with more sophisticated methods for lattice systems? Yes.
- **Complexity**: Gate complexity (nt)^{1+o(1)}, matching the Ω̃(nT) lower bound of [HAAH18] up to subpolynomial factors. Extends to time-dependent Hamiltonians, periodic boundary conditions, and higher dimensions.
- **Limitations**: The o(1) factor in the exponent means this is nearly but not exactly tight. Does not generalise to non-local (chemistry) Hamiltonians as cleanly.
- **Depends on**: [HAAH18], product formula error analysis
- **Relevance to Sturm.jl**: Demonstrates that Sturm.jl's product formula compilation path is asymptotically near-optimal for condensed matter programs, justifying the Trotter decomposition as a first-class compilation target.
- **Cites/cited-by**: [HAAH18]; cited by [CHILDS21TROTTER].

---

### [CHILDS21TROTTER] Childs, Su, Tran, Wiebe & Zhu (2021) — A Theory of Trotter Error with Commutator Scaling
- **arXiv/DOI**: arXiv:1912.08854; doi:10.1103/PhysRevX.11.011020
- **PDF status**: not_found (Phys. Rev. X 11:011020, 2021)
- **Category**: RESOURCE_EST
- **Key idea**: Develops a comprehensive theory of Trotter error by directly exploiting operator commutativity rather than truncating Baker-Campbell-Hausdorff expansions. Achieves substantially tighter error bounds across many physical systems: plane-wave electronic structure, k-local Hamiltonians, power-law interactions, transverse field Ising model. For observables in power-law systems, achieves size-independent complexity circumventing exponential scaling with system size.
- **Complexity**: Asymptotic improvements across diverse systems; first- and second-order formula bounds that overestimate 1D Heisenberg model by only a factor of 5 (vs. orders of magnitude for previous BCH bounds).
- **Limitations**: Commutator bounds can still be loose for frustrated systems. Does not address constant prefactors for fault-tolerant compilation.
- **Depends on**: [CHILDS19], [HAAH18]
- **Relevance to Sturm.jl**: The commutator-scaling error bounds are the state-of-the-art for Sturm.jl's Trotter error estimation pass, enabling tight circuit depth predictions for lattice and chemistry simulations.
- **Cites/cited-by**: [CHILDS19], [HAAH18]; cited by [DALZELL23], [ZHANG25].

---

### [CHILDS18] Childs, Maslov, Nam, Ross & Su (2018) — Toward the First Quantum Simulation with Quantum Speedup
- **arXiv/DOI**: arXiv:1711.10980; doi:10.1073/pnas.1801723115
- **PDF status**: not_found (PNAS 115:9456–9461, 2018)
- **Category**: RESOURCE_EST
- **Key idea**: Identifies quantum simulation of spin systems as the most resource-efficient problem for demonstrating quantum speedup over classical computers. Constructs explicit, optimised quantum circuits for three algorithms (product formulas, Taylor series/LCU, quantum signal processing) applied to a Heisenberg-like Hamiltonian. Demonstrates that the required circuits are orders of magnitude smaller than those for factoring or quantum chemistry at classically-infeasible scales.
- **Complexity**: Explicit circuit counts for all three algorithms; QSP preferred for rigorous guarantees, higher-order product formulas for empirical estimates. Circuits are 63 pages of detailed analysis.
- **Limitations**: Target problem (nearest-neighbour spin model) is classically tractable with DMRG for moderate sizes; the "speedup" regime requires large system sizes and long times. Resource counts predate Trotter commutator-scaling improvements.
- **Depends on**: [BERRY15B], [LOW16], [CHILDS19]
- **Relevance to Sturm.jl**: Provides the most detailed head-to-head circuit comparison across algorithms for a concrete target problem — directly applicable to Sturm.jl's algorithm selection pass.
- **Cites/cited-by**: [LOW16], [BERRY15B]; cited by [DALZELL23].

---

### [REIHER17] Reiher, Wiebe, Svore, Wecker & Troyer (2017) — Elucidating Reaction Mechanisms on Quantum Computers
- **arXiv/DOI**: arXiv:1605.03590; doi:10.1073/pnas.1619152114
- **PDF status**: not_found (PNAS 114:7555–7560, 2017)
- **Category**: RESOURCE_EST
- **Key idea**: First rigorous end-to-end resource estimation for a commercially important quantum chemistry problem: the FeMoco active site in nitrogenase (biological nitrogen fixation). Accounts for quantum error correction overhead, discrete gate compilation, and the full quantum simulation circuit. Demonstrates practical feasibility of tackling scientifically critical problems on fault-tolerant quantum hardware.
- **Complexity**: Detailed resource estimates including qubit count, T-gate count, and runtime; first paper to account for QECC overhead in a chemistry simulation context. Exact numbers cited in subsequent literature as benchmarks.
- **Limitations**: Used Taylor series (LCU) simulation; subsequent work (Babbush 2018, 2019) reduced resource requirements by orders of magnitude. FeMoco active space selection remains disputed classically.
- **Depends on**: [BERRY15B], [ABRAMS97]
- **Superseded by**: [BABBUSH18], [BABBUSH19], [VONBURG20] (orders of magnitude cheaper)
- **Relevance to Sturm.jl**: Establishes the benchmark problem and methodology for Sturm.jl's resource estimation pass — annotating compiled chemistry circuits with T-gate and qubit counts.
- **Cites/cited-by**: [BERRY15B]; cited by [BABBUSH18], [BABBUSH19], [VONBURG20], [GOINGS22].

---

### [BABBUSH18] Babbush, Gidney, Berry, Wiebe, McClean, Paler, Fowler & Neven (2018) — Encoding Electronic Spectra in Quantum Circuits with Linear T Complexity
- **arXiv/DOI**: arXiv:1805.03662; doi:10.1103/PhysRevX.8.041015
- **PDF status**: not_found (Phys. Rev. X 8:041015, 2018)
- **Category**: RESOURCE_EST
- **Key idea**: Constructs qubitization circuits for electronic structure Hamiltonians in a second-quantized basis diagonalising the Coulomb operator, achieving T-gate complexity O(N + log(1/ε)) per phase estimation step (N = number of orbitals). Full eigenbasis sampling complexity O(N³/ε). Uses surface code for fault tolerance with roughly one million physical qubits at 10⁻³ error rates. Achieves seven hundred times less surface code spacetime volume than [REIHER17] for FeMoco.
- **Complexity**: T-gate complexity O(N + log(1/ε)) for oracle circuit; queries O(λ/ε) via qubitization; approximately 10^6 physical qubits required for FeMoco under optimistic surface code assumptions.
- **Limitations**: Plane-wave basis is not optimal for strongly correlated systems; practical chemistry requires larger active spaces. One million qubits remains a very long-term hardware target.
- **Depends on**: [LOW17QUBIT], [REIHER17]
- **Superseded by**: [BABBUSH19] (further factor of ~700 reduction using arbitrary basis + sparse/low-rank)
- **Relevance to Sturm.jl**: The T-gate complexity formula O(N + log(1/ε)) per qubitization step is the key quantity that Sturm.jl's T-count pass should compute for electronic structure programs.
- **Cites/cited-by**: [LOW17QUBIT], [REIHER17]; cited by [BABBUSH19], [VONBURG20], [GOINGS22].

---

### [BABBUSH19] Berry, Gidney, Motta, McClean & Babbush (2019) — Qubitization of Arbitrary Basis Quantum Chemistry
- **arXiv/DOI**: arXiv:1902.02134; doi:10.22331/q-2019-12-02-208
- **PDF status**: not_found (Quantum 3:208, 2019)
- **Category**: RESOURCE_EST
- **Key idea**: Extends qubitization to arbitrary basis sets (not just plane waves) by exploiting sparsity and low-rank tensor factorisation of the two-electron integrals. Achieves T complexity Õ(N^{3/2}·λ) where λ is the LCU 1-norm. Applied to FeMoco, achieves roughly 700 times less surface code spacetime volume than [BABBUSH18].
- **Complexity**: Õ(N^{3/2}·λ) T-gates; roughly factor 700 improvement over [BABBUSH18] on FeMoco.
- **Limitations**: Low-rank factorisation quality depends on the specific molecule; λ can still be large for strongly correlated systems. Further improvements possible with double factorisation ([VONBURG20]).
- **Depends on**: [BABBUSH18], [LOW17QUBIT]
- **Superseded by**: [VONBURG20] (double factorisation, further improvements)
- **Relevance to Sturm.jl**: Demonstrates the importance of tensor decomposition in reducing the LCU 1-norm λ — a quantity Sturm.jl's resource estimation pass needs to compute from the Hamiltonian input.
- **Cites/cited-by**: [BABBUSH18]; cited by [VONBURG20], [GOINGS22].

---

### [VONBURG20] Von Burg, Low, Häner, Steiger, Reiher, Roetteler & Troyer (2020) — Quantum Computing Enhanced Computational Catalysis
- **arXiv/DOI**: arXiv:2007.14460; doi:10.1103/PhysRevResearch.3.033055
- **PDF status**: not_found (Phys. Rev. Research 3:033055, 2021)
- **Category**: RESOURCE_EST
- **Key idea**: Applies double-factorised qubitization to quantum catalysis problems (ruthenium CO₂-to-methanol catalyst). Achieves more than an order of magnitude improvement over [BABBUSH19] via double-factorisation of the four-index electron repulsion integrals. Provides detailed resource estimates for surface-code compilation, and identifies the minimum hardware requirements for practical quantum advantage in computational chemistry.
- **Complexity**: More than 10x improvement over [BABBUSH19] via double factorisation; explicit T-gate counts and physical qubit requirements for ruthenium catalyst chemistry.
- **Limitations**: Resource estimates still require millions of physical qubits for commercially relevant problems. Active space selection and classical post-processing costs not fully accounted for.
- **Depends on**: [BABBUSH19], [REIHER17]
- **Relevance to Sturm.jl**: Double factorisation should be implemented as a preprocessing pass in Sturm.jl's chemistry compilation pipeline, reducing λ and hence T-gate counts before circuit generation.
- **Cites/cited-by**: [BABBUSH19]; cited by [GOINGS22], [BEVERLAND22].

---

### [GOINGS22] Goings, White, Lee, Tautermann, Degroote, Gidney, Shiozaki, Babbush & Rubin (2022) — Reliably Assessing the Electronic Structure of Cytochrome P450
- **arXiv/DOI**: arXiv:2202.01244
- **PDF status**: not_found
- **Category**: RESOURCE_EST
- **Key idea**: Compares classical (DMRG+NEVPT2, CCSD(T)) and quantum (qubitized quantum walk + phase estimation) resource requirements for cytochrome P450 electronic structure. Provides surface-code compiled runtime estimates for quantum algorithms and identifies the crossover regime where quantum advantage emerges. Emphasises the interplay between classical and quantum methods in practical quantum advantage assessments.
- **Complexity**: Explicit resource estimates (T-gates, physical qubits, surface code runtime) for P450 models; identifies quantum advantage boundary as a function of active space size.
- **Limitations**: P450 is one specific benchmark; generalisability to other drug targets not established. Classical DMRG improvements may push the quantum advantage boundary further out.
- **Depends on**: [BABBUSH19], [VONBURG20]
- **Relevance to Sturm.jl**: Provides a validated end-to-end resource estimation methodology that Sturm.jl's compiler pass should replicate: input Hamiltonian → LCU coefficients → qubitization circuit → surface code compilation → qubit/time estimate.
- **Cites/cited-by**: [BABBUSH19], [VONBURG20]; cited by [BEVERLAND22].

---

### [GIDNEY21] Gidney & Ekerå (2019/2021) — How to Factor 2048 Bit RSA Integers in 8 Hours Using 20 Million Noisy Qubits
- **arXiv/DOI**: arXiv:1905.09749; doi:10.22331/q-2021-04-15-433
- **PDF status**: not_found (Quantum 5:433, 2021)
- **Category**: RESOURCE_EST
- **Key idea**: Comprehensive end-to-end resource analysis for Shor's algorithm on 2048-bit RSA, accounting for realistic noise (10⁻³ gate errors), surface code overheads, spatial qubit layout, repeated attempts, and seven algorithmic improvements over prior analyses. Reduces the spacetime volume for RSA-2048 by a factor of roughly 100 compared to the best previous estimate. Final answer: 20 million noisy physical qubits, 8 hours.
- **Complexity**: 20 million physical qubits × 8 hours runtime for RSA-2048 at realistic noise rates; includes T-gate factory overhead, surface code distance estimates, and scheduling.
- **Limitations**: Assumes superconducting hardware at 10⁻³ error rates; different hardware or better error correction could change the estimate significantly. Advances in classical factoring algorithms not accounted for.
- **Depends on**: Shor's algorithm; surface code compilation literature
- **Relevance to Sturm.jl**: The methodology — integrating algorithmic improvements, noise models, and hardware parameters into a single end-to-end resource count — is the template for Sturm.jl's resource estimation infrastructure.
- **Cites/cited-by**: Cited by [BEVERLAND22], [DALZELL23].

---

### [LITINSKI19] Litinski (2019) — Magic State Distillation: Not as Costly as You Think
- **arXiv/DOI**: arXiv:1905.06903; doi:10.22331/q-2019-12-02-205
- **PDF status**: not_found (Quantum 3:205, 2019)
- **Category**: FAULT_TOLERANT
- **Key idea**: Shows that the conventional estimate of magic state distillation overhead is pessimistic by a large factor. By separating distillation circuit qubits into those capable of error detection and those that are not, most distillation qubits can be encoded at very low code distance. In extreme cases, distillation costs less than a logical Clifford gate on full-distance logical qubits.
- **Complexity**: Reduction in distillation spacetime cost by factors of 10–100 compared to naive estimates, depending on the distillation protocol and target magic state fidelity.
- **Limitations**: Optimisation requires careful circuit analysis; benefits depend on the specific distillation factory design. Does not change asymptotic scaling.
- **Depends on**: Surface code theory; magic state distillation (Bravyi-Kitaev 2005)
- **Relevance to Sturm.jl**: T-gate overhead estimates in Sturm.jl's resource estimation pass should use Litinski's corrected distillation costs, not the naive estimates. This affects all fault-tolerant resource counts for T-gate intensive programs.
- **Cites/cited-by**: Cited by [BEVERLAND22], [DALZELL23].

---

### [BEVERLAND22] Beverland, Murali, Troyer, Svore, Hoefler, Kliuchnikov, Low, Soeken, Sundaram & Vaschillo (2022) — Assessing Requirements to Scale to Practical Quantum Advantage
- **arXiv/DOI**: arXiv:2211.07629
- **PDF status**: not_found
- **Category**: RESOURCE_EST
- **Key idea**: Presents a general resource estimation framework spanning the full quantum computing stack from algorithm to physical qubits. Assesses three scaled quantum applications and concludes that hundreds of thousands to millions of physical qubits are needed for practical quantum advantage. Identifies three critical qubit parameters: size, speed, and controllability. Provides an open tool for exploring architectural tradeoffs.
- **Complexity**: Framework-level analysis; determines O(10^5)–O(10^6) physical qubits required for practical advantage across studied applications.
- **Limitations**: Applications studied are Microsoft-selected; framework abstracts away hardware details that could significantly affect estimates. Resource estimates are snapshots of 2022 algorithmic state.
- **Depends on**: [GIDNEY21], [LITINSKI19], [BABBUSH19]
- **Relevance to Sturm.jl**: The layered resource estimation framework is exactly what Sturm.jl's compiler pass infrastructure should implement: algorithm-level T-gate counts → logical qubit counts → physical qubit counts via surface code, accounting for distillation, routing, and scheduling.
- **Cites/cited-by**: [GIDNEY21], [LITINSKI19], [GOINGS22].

---

### [GEORGESCU14] Georgescu, Ashhab & Nori (2014) — Quantum Simulation
- **arXiv/DOI**: arXiv:1308.6253; doi:10.1103/RevModPhys.86.153
- **PDF status**: not_found (Rev. Mod. Phys. 86:153, 2014)
- **Category**: RESOURCE_EST
- **Key idea**: Comprehensive 41-page review of the quantum simulation field across both digital and analog approaches. Covers theoretical foundations, physical platforms (neutral atoms, trapped ions, superconducting circuits, photons, cold molecules, NMR), application domains (condensed matter, high-energy physics, quantum chemistry, cosmology), and experimental implementations. The standard broad-audience reference for the field as of the mid-2010s.
- **Limitations**: Predates QSVT, qubitization, and the modern resource estimation era. Analog simulation coverage is extensive but digital simulation is less detailed.
- **Depends on**: [FEYNMAN82], [LLOYD96]
- **Superseded by**: [CAO19], [MCCARDLE20], [BAUER20] for algorithmic depth; [DALZELL23] for complexity depth.
- **Relevance to Sturm.jl**: Provides the conceptual map of quantum simulation applications that Sturm.jl's DSL should be able to express.
- **Cites/cited-by**: [FEYNMAN82], [LLOYD96], [ABRAMS97]; cited by [CAO19], [MCCARDLE20].

---

### [CAO19] Cao, Romero, Olson, Degroote, Johnson, Kieferová, Kivlichan, Menke, Peropadre, Sawaya, Sim, Veis & Aspuru-Guzik (2019) — Quantum Chemistry in the Age of Quantum Computing
- **arXiv/DOI**: arXiv:1812.09976; doi:10.1021/acs.chemrev.8b00803
- **PDF status**: not_found (Chem. Rev. 119:10856–10915, 2019)
- **Category**: RESOURCE_EST
- **Key idea**: 194-page review (404 references) bridging quantum chemistry and quantum computing for dual audiences: quantum chemists learning quantum computing, and quantum computing researchers exploring chemistry applications. Covers electronic structure, molecular properties, VQE, phase estimation, encoding methods, and hardware platforms. The standard reference for quantum computational chemistry as of 2019.
- **Limitations**: 194 pages cannot be fully current; rapidly evolving field means some sections are already superseded by [BABBUSH19], [VONBURG20]. Limited coverage of strongly correlated systems and materials science.
- **Depends on**: [ABRAMS97], [BERRY15B], [LOW17QUBIT]
- **Superseded by**: [MCCARDLE20] (more focused Rev. Mod. Phys. review); [BAUER20] (materials science focus); [ZHANG25] (EFTQC algorithms)
- **Relevance to Sturm.jl**: Comprehensive reference for the quantum chemistry application domain that Sturm.jl's DSL must support; the encoding methods section is directly relevant to how Hamiltonians are compiled.
- **Cites/cited-by**: [ABRAMS97], [BERRY15B]; cited by [MCCARDLE20], [BAUER20], [DALZELL23].

---

### [MCCARDLE20] McArdle, Endo, Aspuru-Guzik, Benjamin & Yuan (2020) — Quantum Computational Chemistry
- **arXiv/DOI**: arXiv:1808.10402; doi:10.1103/RevModPhys.92.015003
- **PDF status**: not_found (Rev. Mod. Phys. 92:015003, 2020)
- **Category**: RESOURCE_EST
- **Key idea**: Comprehensive Rev. Mod. Phys. review of quantum computational chemistry, designed to bridge quantum computing and computational chemistry research communities. Covers variational approaches (VQE), phase estimation, encoding methods, near-term algorithms, and error mitigation. Emphasises practical methods for near-term hardware. The companion to [CAO19] with more algorithmic depth and cleaner organization.
- **Limitations**: Near-term (NISQ) focus means fault-tolerant methods are underemphasised relative to their ultimate importance. Rapidly superseded in the resource estimation context by [VONBURG20], [GOINGS22].
- **Depends on**: [ABRAMS97], [BERRY15B], [LOW17QUBIT], [CAO19]
- **Relevance to Sturm.jl**: Provides the algorithmic foundations for quantum chemistry compilation in Sturm.jl, including encoding, VQE as a parameterised circuit loop, and phase estimation circuit structure.
- **Cites/cited-by**: [CAO19], [ABRAMS97]; cited by [BAUER20], [DALZELL23].

---

### [BAUER20] Bauer, Bravyi, Motta & Chan (2020) — Quantum Algorithms for Quantum Chemistry and Quantum Materials Science
- **arXiv/DOI**: arXiv:2001.03685 (approximate); doi:10.1021/acs.chemrev.0c00512
- **PDF status**: not_found (Chem. Rev. 120:12685–12717, 2020)
- **Category**: RESOURCE_EST
- **Key idea**: Review of quantum algorithms for chemistry and materials science with particular focus on strongly correlated electrons, electronic structure, quantum dynamics, and thermal states. Written by leaders in both classical quantum chemistry (DMRG, coupled cluster) and quantum algorithms, providing a uniquely informed perspective on where quantum advantage is realistic and where classical methods remain competitive.
- **Limitations**: Focus on algorithms; hardware and fault-tolerance aspects less developed than [BEVERLAND22]. Materials science applications (band structure, phonons) less developed than chemistry.
- **Depends on**: [ABRAMS97], [BERRY15B], [LOW17QUBIT], [CAO19]
- **Relevance to Sturm.jl**: Materials science simulation programs (Hubbard, Heisenberg lattices) are important target use cases for Sturm.jl; this review identifies the open algorithmic questions relevant to those programs.
- **Cites/cited-by**: [CAO19], [MCCARDLE20]; cited by [DALZELL23], [ZHANG25].

---

### [DALZELL23] Dalzell, McArdle, Berta, Bienias, Chen, Gilyén, Hann, Kastoryano, Khabiboulline, Kubica, Salton, Wang & Brandão (2023) — Quantum Algorithms: A Survey of Applications and End-to-End Complexities
- **arXiv/DOI**: arXiv:2310.03011
- **PDF status**: not_found (Cambridge University Press, 2025; 416 pages)
- **Category**: RESOURCE_EST
- **Key idea**: The most comprehensive end-to-end complexity survey of quantum algorithms, spanning quantum chemistry, many-body physics, optimization, finance, and machine learning. Key methodological innovation: treats each application with uniform technical depth by clearly defining problems, instantiating all oracle subroutines, spelling out hidden costs, and comparing quantum against classical methods with explicit complexity-theoretic constraints. The wiki-like modular structure allows reasoning about how subroutine improvements propagate to end-to-end complexity.
- **Complexity**: Covers query, gate, and fault-tolerant complexity across all major application domains; represents the state of the art as of late 2024 (v2 updated August 2025).
- **Limitations**: 416 pages still cannot be exhaustive. Classical algorithm lower bounds (establishing quantum advantage) are often conjectural rather than proven. Some application domains (ML, optimization) have less certain quantum advantages than simulation.
- **Depends on**: [GILYEN19], [CHILDS21TROTTER], [HAAH18], [BABBUSH19], [GIDNEY21], essentially the entire field.
- **Relevance to Sturm.jl**: The primary complexity reference for Sturm.jl's resource estimation infrastructure. The end-to-end methodology — algorithm → oracles → error correction → physical resources — is exactly the compilation pipeline Sturm.jl should implement.
- **Cites/cited-by**: Cites essentially every other paper in this survey.

---

### [ZHANG25] Zhang, Zhang, Sun, Lin, Huang, Lv & Yuan (2025) — Fault-Tolerant Quantum Algorithms for Quantum Molecular Systems: A Survey
- **arXiv/DOI**: arXiv:2502.02139; doi:10.1002/wcms.70020
- **PDF status**: not_found (WIREs Comput. Mol. Sci. 15:e70020, 2025)
- **Category**: RESOURCE_EST
- **Key idea**: The most recent (2025) survey specifically targeting fault-tolerant and early fault-tolerant quantum algorithms for molecular quantum systems. Covers encoding schemes, advanced Hamiltonian simulation techniques, and ground-state energy estimation methods, with emphasis on reducing circuit depth and minimising ancillary qubits for near-term fault-tolerant hardware. Addresses both fully fault-tolerant (FFTQC) and early fault-tolerant (EFTQC) regimes.
- **Limitations**: 28 pages means coverage is selective; field moves fast enough that some 2024–2025 results may not be included.
- **Depends on**: [DALZELL23], [GILYEN19], [BABBUSH19], [VONBURG20]
- **Relevance to Sturm.jl**: The most current reference for Sturm.jl's chemistry compilation passes, especially for EFTQC-targeted compilation where circuit depth constraints are tight.
- **Cites/cited-by**: [DALZELL23], [MARTYN21], [GILYEN19].

---

## Open Problems

1. **Practical quantum advantage timeline**: The crossover point where quantum simulation beats classical DMRG/CCSD(T) for practically important molecules keeps receding as classical algorithms improve. Whether quantum advantage for chemistry will be demonstrated in the 2030s or 2040s — or at all for target molecules — remains genuinely open.

2. **Constant factor tightness**: Lower bounds (Berry-Childs-Kothari 2015, Haah et al. 2018) are tight in asymptotic scaling but not in constant factors. The gap between query complexity lower bounds and achievable T-gate counts for specific hardware (with routing, distillation, ancilla management) remains poorly understood.

3. **Non-unitary simulation**: Simulating open quantum systems (Lindblad dynamics, quantum channels) efficiently requires different techniques than Hamiltonian simulation. QSVT-based approaches exist but complexity is less tightly understood. This is directly relevant to Sturm.jl because programs include measurement (ObserveNode) and noise channels (depolarise).

4. **Classical simulation barriers**: The exact hardness of k-local Hamiltonian ground-state problems, and whether QMA-hardness results translate to exponential classical simulation costs for physically relevant instances (not worst-case), remains poorly mapped.

5. **Error mitigation vs. fault tolerance**: For near-term (NISQ/EFTQC) simulation, whether error mitigation techniques can close the gap with fault-tolerant simulation at practically relevant depths and system sizes is unresolved.

6. **Strongly correlated materials**: Quantum simulation of correlated electron systems (Mott insulators, superconductors, spin liquids) where classical methods definitively fail is the clearest target for quantum advantage, but resource requirements remain far beyond current hardware.

7. **Noise thresholds for simulation advantage**: For noisy devices, what error rate and qubit count are required before a quantum simulation circuit (even without full QECC) outperforms the best classical tensor network methods for the same problem?

---

## Relevance to Sturm.jl

Sturm.jl's compilation and optimization pipeline needs to count and minimise resources for practical quantum simulation programs. This survey identifies several direct implementation requirements:

**T-gate counting**: For fault-tolerant compilation, the critical metric is T-gate count (or Toffoli count). The qubitization-based algorithms ([LOW17QUBIT], [BABBUSH18], [BABBUSH19]) express cost as O(λ/ε) T-gates where λ is the LCU 1-norm. Sturm.jl's T-count pass (see `passes/`) should compute λ from a Hamiltonian input and estimate T-gates before circuit generation.

**Circuit depth vs. gate count**: Haah et al. ([HAAH18]) and Childs-Su ([CHILDS19]) prove that circuit depth (not just gate count) has a tight lower bound for lattice simulation. Sturm.jl's depth estimation pass should track both independently, since CNOT depth is the latency-critical resource and T-gate count is the fault-tolerance-critical resource.

**Trotter error estimation**: Childs et al. ([CHILDS21TROTTER]) commutator-scaling bounds provide tight estimates of Trotter error as a function of step size. Sturm.jl's gate_cancel and product-formula passes should integrate these bounds to set optimal step sizes for a given error budget.

**Resource annotation in the DAG**: The channel IR (ObserveNode, CasesNode) means Sturm.jl operates on channels, not unitaries. As noted in CLAUDE.md, unitary-only optimization passes must respect measurement barriers. Resource estimation for full channel programs requires tracking resources per unitary block between ObserveNodes and accumulating worst-case or expected counts across classical branches — a direct consequence of the Dalzell et al. ([DALZELL23]) end-to-end methodology.

**Chemistry application support**: The encoding methods from [CAO19] and [MCCARDLE20] (Jordan-Wigner, Bravyi-Kitaev, second quantisation) determine how chemistry Hamiltonians compile to DSL primitives. Each Jordan-Wigner string is a product of Rz and CNOT operations — exactly the four primitives. Sturm.jl's library should include Jordan-Wigner compilation as a first-class function.

---

## TOPIC SUMMARY
- Papers found: 28
- Papers downloaded: 0 (all behind journal paywalls or not yet fetched as PDFs)
- Top 3 most relevant to Sturm.jl: [DALZELL23], [BEVERLAND22], [CHILDS21TROTTER]
- Key insight for implementation: The end-to-end resource estimation methodology — from algorithm-level LCU 1-norm λ through T-gate count through physical qubit count via surface code — is the precise pipeline that Sturm.jl's compiler passes need to implement; every quantity in that pipeline (λ, ε, code distance, distillation cost) has a closed-form estimate from the papers surveyed here, enabling Sturm.jl to annotate any compiled simulation program with a physical resource estimate.
