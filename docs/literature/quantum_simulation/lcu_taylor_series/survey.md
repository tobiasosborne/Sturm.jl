# Linear Combination of Unitaries / Taylor Series Methods

## Category Summary

The Linear Combination of Unitaries (LCU) framework is a paradigm for Hamiltonian simulation in which the evolution operator e^{-iHt} is approximated not by a product of small unitaries (as in Trotter decompositions) but by a weighted sum of unitaries. The key idea, crystallised by Childs and Wiebe (2012), is that if H = sum_k alpha_k U_k with U_k unitary, then the truncated Taylor series of e^{-iHt} is itself a linear combination of products of the U_k. An LCU can be implemented on a quantum computer using two oracles — PREPARE (which loads the coefficient vector as a quantum superposition) and SELECT (which applies the correct U_k controlled on the index register) — followed by oblivious amplitude amplification to project onto the desired output state. The overhead of this post-selection step is a constant factor of O(1/||alpha||_1 * lambda), making the total cost proportional to the 1-norm lambda = sum_k |alpha_k| of the coefficient vector.

The breakthrough of Berry, Childs, Cleve, Kothari, and Somma (2013/2015) was to observe that the truncated Taylor series of e^{-iHt} to order K has 1-norm scaling as O((lambda * t)^K / K!) — by choosing K ~ log(1/epsilon)/loglog(1/epsilon) this is made essentially 1, so the total gate complexity scales as O(lambda * t * log(1/epsilon) / loglog(1/epsilon)). This is an exponential improvement over product formulas in the precision parameter epsilon and is essentially tight (there is a matching lower bound in lambda * t). The subsequent paper (arXiv:1501.01715) achieved near-optimal dependence on all parameters simultaneously — time, sparsity, and precision — by combining LCU with quantum walk steps weighted by Bessel function coefficients.

The state of the art has evolved in several directions: (1) qubitization and quantum signal processing (Low-Chuang 2017, 2019) unified LCU with quantum walk methods, achieving O(lambda * t + log(1/epsilon)) query complexity, essentially information-theoretically optimal; (2) the quantum singular value transformation (Gilyen-Su-Low-Wiebe 2019) subsumed all of these into a single algorithmic framework; (3) for time-dependent Hamiltonians, the truncated Dyson series (Kieferova-Scherer-Berry 2019) and L1-norm scaling (Berry et al. 2020) provide natural generalisations; (4) the interaction picture framework (Low-Wiebe 2019, Babbush et al. 2019) exploits structure in Hamiltonians (e.g. kinetic vs. potential in chemistry) to reduce lambda dramatically; and (5) stochastic/randomised variants (Campbell 2019, qDRIFT) trade deterministic compilation for probabilistic sampling with better practical constants.

## Timeline

- **1996** Lloyd: product formulas (Trotter) for local Hamiltonians — the starting baseline
- **2007** Berry-Ahokas-Cleve-Sanders: first efficient sparse Hamiltonian simulation (product formula, superlinear in t)
- **2010** Childs: continuous quantum walk gives universal quantum simulation
- **2012** Childs-Wiebe: first LCU-based simulation, superior error scaling over product formulas
- **2013/2014** Berry-Childs-Cleve-Kothari-Somma (arXiv:1312.1414, STOC 2014): exponential improvement in epsilon, first O(polylog(1/epsilon)) algorithm via truncated Taylor series
- **2015a** Berry-Childs-Cleve-Kothari-Somma (arXiv:1412.4687, PRL 2015): simplified, streamlined version of the Taylor series method
- **2015b** Berry-Childs-Kothari (arXiv:1501.01715, FOCS 2015): near-optimal in all parameters via Bessel-function-weighted quantum walk LCU
- **2016/2017** Low-Chuang (arXiv:1606.02685, PRL 2017): quantum signal processing achieves optimal complexity for sparse Hamiltonians
- **2016/2019** Low-Chuang (arXiv:1610.06546, Quantum 2019): qubitization, O(t + log(1/epsilon)), optimal in both t and epsilon
- **2018/2019** Gilyen-Su-Low-Wiebe (arXiv:1806.01838, STOC 2019): QSVT unifies all prior frameworks
- **2018** Babbush et al. (arXiv:1805.03662, PRX 2018): linear T-complexity encoding of electronic spectra via qubitization
- **2018/2019** Kieferova-Scherer-Berry (arXiv:1805.00582, PRA 2019): Dyson series for time-dependent Hamiltonians
- **2018/2019** Babbush et al. (arXiv:1807.09802, npj QI 2019): chemistry with sublinear scaling via interaction picture
- **2018/2019** Low-Wiebe (arXiv:1805.00675): interaction picture for time-independent Hamiltonians
- **2019** Low-Chuang qubitization applied to chemistry: Berry et al. (arXiv:1902.02134, Quantum 2019)
- **2019** Campbell (arXiv:1811.08017, PRL 2019): qDRIFT stochastic LCU
- **2020** Berry-Childs-Su-Wang-Wiebe (arXiv:1906.07115, Quantum 2020): L1-norm scaling for time-dependent H
- **2021** Su-Berry-Wiebe-Rubin-Babbush (arXiv:2105.12767, PRX Quantum 2021): fault-tolerant resource estimates in first quantization
- **2023** An-Liu-Lin (arXiv:2303.01029, PRL 2023): LCHS for non-unitary (open system) dynamics

---

## Papers

### [BERRY07] Berry et al. (2007) — Efficient Quantum Algorithms for Simulating Sparse Hamiltonians
- **Citation**: D. W. Berry, G. Ahokas, R. Cleve, B. C. Sanders. "Efficient quantum algorithms for simulating sparse Hamiltonians." Communications in Mathematical Physics 270, 359–371 (2007).
- **arXiv**: https://arxiv.org/abs/quant-ph/0508139
- **Contribution**: First efficient quantum algorithm for simulating d-sparse Hamiltonians, using high-order product formulas (Suzuki decomposition). Achieves O((log* n) t^{1+1/2k}) matrix-entry queries where k is a selectable integer — sublinear time exponent is impossible (matching lower bound proved).
- **Complexity**: O(d^2 ||H||_max t^{1+1/2k}) queries; polynomial in 1/epsilon via choosing k.
- **Limitations**: Product-formula based — scaling in precision epsilon is polynomial, not logarithmic. No LCU. Predates the exponential improvement in epsilon that LCU provides.
- **Depends on**: Lloyd 1996 (Trotter simulation); Aharonov-Ta-Shma 2003 (quantum walk ideas)
- **Superseded by**: BCKS-STOC14 (1312.1414), BCKS-PRL15 (1412.4687)

### [CHILDS-WIEBE12] Childs & Wiebe (2012) — Hamiltonian Simulation Using Linear Combinations of Unitary Operations
- **Citation**: A. M. Childs, N. Wiebe. "Hamiltonian simulation using linear combinations of unitary operations." Quantum Information and Computation 12, 901–924 (2012).
- **arXiv**: https://arxiv.org/abs/1202.5822
- **Contribution**: Introduced the LCU framework for Hamiltonian simulation. If H = sum_k alpha_k U_k, then implementing the LCU via PREPARE+SELECT+oblivious amplitude amplification achieves superior scaling in simulation error compared to any product-formula method known at the time.
- **Complexity**: Scales better with epsilon than product formulas; exact form involves the 1-norm lambda = sum_k |alpha_k|. First paper to show epsilon scaling can be improved beyond polynomial.
- **Limitations**: Does not yet achieve the full exponential improvement in epsilon; that required the Taylor truncation insight of BCKS-STOC14. Also does not handle the ancilla projection optimally.
- **Depends on**: Berry07 (sparse simulation), Grover-Rudolph 2002 (state preparation)
- **Superseded by**: BCKS-STOC14, BCKS-PRL15

### [BCKS-STOC14] Berry et al. (2014) — Exponential Improvement in Precision for Simulating Sparse Hamiltonians
- **Citation**: D. W. Berry, A. M. Childs, R. Cleve, R. Kothari, R. D. Somma. "Exponential improvement in precision for simulating sparse Hamiltonians." Proceedings of the 46th ACM STOC, 283–292 (2014). Journal version: Forum of Mathematics, Sigma (2017).
- **arXiv**: https://arxiv.org/abs/1312.1414
- **Contribution**: First algorithm with complexity sublogarithmic (polylog) in 1/epsilon for sparse Hamiltonian simulation, by combining LCU with the truncated Taylor series of e^{-iHt}. Introduces the PREPARE-SELECT-oblivious-amplification architecture in full generality.
- **Complexity**: O(tau * log(tau/epsilon) / loglog(tau/epsilon)) queries and O(tau * log^2(tau/epsilon) / loglog(tau/epsilon) * n) 2-qubit gates, where tau = d^2 ||H||_max * t. Exponential improvement over prior methods in epsilon.
- **Limitations**: Suboptimal in the sparsity d (scales as d^2 in tau). Does not simultaneously optimise all parameters; superseded in that sense by BCK-FOCS15.
- **Depends on**: Childs-Wiebe12
- **Superseded by**: BCK-FOCS15 (1501.01715) for all-parameter optimality

### [BCKS-PRL15] Berry et al. (2015) — Simulating Hamiltonian Dynamics with a Truncated Taylor Series
- **Citation**: D. W. Berry, A. M. Childs, R. Cleve, R. Kothari, R. D. Somma. "Simulating Hamiltonian dynamics with a truncated Taylor series." Physical Review Letters 114, 090502 (2015).
- **arXiv**: https://arxiv.org/abs/1412.4687
- **Contribution**: Streamlined, self-contained presentation of the Taylor series LCU method. Shows that truncating e^{-iHt} = sum_{k=0}^{K} (-iHt)^k / k! to order K ~ log(1/epsilon)/loglog(1/epsilon) gives a near-unitary LCU implementable with polylog(1/epsilon) overhead and robust oblivious amplitude amplification. The cost is O(lambda * t * log(1/epsilon) / loglog(1/epsilon)).
- **Complexity**: O(lambda * t * log(1/epsilon) / loglog(1/epsilon)) calls to H-oracle; lambda = sum of LCU coefficients. Logarithmic (essentially optimal) in 1/epsilon.
- **Limitations**: The method requires implementing controlled-U_k gates (controlled Hamiltonian terms), which adds constant-factor overhead per term. Lambda can be large for dense Hamiltonians — qubitization later achieves the same epsilon scaling with fewer ancilla overheads.
- **Depends on**: BCKS-STOC14, Childs-Wiebe12
- **Superseded by**: Low-Chuang17 (QSP), Low-Chuang19 (qubitization) for optimal query complexity

### [BCK-FOCS15] Berry, Childs & Kothari (2015) — Hamiltonian Simulation with Nearly Optimal Dependence on All Parameters
- **Citation**: D. W. Berry, A. M. Childs, R. Kothari. "Hamiltonian simulation with nearly optimal dependence on all parameters." Proceedings of the 56th IEEE FOCS, 792–809 (2015).
- **arXiv**: https://arxiv.org/abs/1501.01715
- **Contribution**: Achieves near-optimal query complexity in all parameters simultaneously (time t, sparsity d, precision epsilon) by implementing a linear combination of quantum walk steps with Bessel-function coefficients. Proves a matching lower bound: no algorithm can achieve sublinear dependence on tau = d ||H||_max t.
- **Complexity**: O(tau * log(1/epsilon) / loglog(1/epsilon)) queries and gates (logarithmic in 1/epsilon, nearly linear in tau). Matches lower bound up to loglog factors.
- **Limitations**: Combines quantum walk and LCU techniques in a complex way; somewhat harder to implement than the pure Taylor series method. Sparsity d appears linearly (improvement over d^2 in BCKS-STOC14) but still requires d-sparse oracle access.
- **Depends on**: BCKS-STOC14, BCKS-PRL15, Childs 2010 (quantum walk)
- **Superseded by**: Low-Chuang19 (qubitization) achieves O(t + log(1/epsilon)) — additive rather than multiplicative

### [LOW-CHUANG17] Low & Chuang (2017) — Optimal Hamiltonian Simulation by Quantum Signal Processing
- **Citation**: G. H. Low, I. L. Chuang. "Optimal Hamiltonian simulation by quantum signal processing." Physical Review Letters 118, 010501 (2017).
- **arXiv**: https://arxiv.org/abs/1606.02685
- **Contribution**: Introduced quantum signal processing (QSP) for Hamiltonian simulation. Single-qubit rotation sequences with classically precomputed phase angles implement optimal-degree polynomial transformations of Hamiltonian eigenvalues, achieving query complexity O(td||H||_max + log(1/epsilon)/loglog(1/epsilon)) — optimal in all parameters for sparse Hamiltonians.
- **Complexity**: O(td||H||_max + log(1/epsilon)/loglog(1/epsilon)) oracle queries; matches lower bounds in all parameters.
- **Limitations**: Requires classical precomputation of QSP phase angles (solving a polynomial approximation problem); the precomputation was initially expensive but has since been resolved (Haah 2019, Dong et al. 2021). Primarily formulated for sparse Hamiltonians rather than LCU-decomposed ones.
- **Depends on**: BCK-FOCS15, quantum walk theory
- **Superseded by**: Low-Chuang19 (qubitization) extends QSP to the block-encoding setting, subsuming LCU

### [LOW-CHUANG19] Low & Chuang (2019) — Hamiltonian Simulation by Qubitization
- **Citation**: G. H. Low, I. L. Chuang. "Hamiltonian simulation by qubitization." Quantum 3, 163 (2019).
- **arXiv**: https://arxiv.org/abs/1610.06546
- **Contribution**: Introduced qubitization: given oracles that implement PREPARE (loading coefficients) and SELECT (applying terms), the controlled versions embed H in an invariant SU(2) subspace. Combined with QSP, this achieves query complexity O(t + log(1/epsilon)) — additive in t and log(1/epsilon), optimal with respect to both. Directly subsumes LCU-based simulation.
- **Complexity**: O(lambda * t + log(1/epsilon)) queries to PREPARE and SELECT, using only 2 additional ancilla qubits. Optimal in all parameters.
- **Limitations**: Requires classical precomputation of QSP phases. Implements time-independent simulation only directly; time-dependent variants require additional techniques (Low-Wiebe 2019, Kieferova et al. 2019).
- **Depends on**: Low-Chuang17, BCKS-PRL15, BCK-FOCS15
- **Superseded by**: Gilyen-Su-Low-Wiebe19 (QSVT) for the most general framework

### [QSVT19] Gilyen, Su, Low & Wiebe (2019) — Quantum Singular Value Transformation
- **Citation**: A. Gilyén, Y. Su, G. H. Low, N. Wiebe. "Quantum singular value transformation and beyond: exponential improvements for quantum matrix arithmetics." Proceedings of STOC 2019, 193–204.
- **arXiv**: https://arxiv.org/abs/1806.01838
- **Contribution**: Unified framework (QSVT) that subsumes optimal Hamiltonian simulation, amplitude amplification, quantum walks, phase estimation, matrix inversion, and machine learning primitives. Any polynomial transformation of singular values of a block-encoded matrix can be implemented using a simple alternating circuit of controlled unitaries and single-qubit rotations. Hamiltonian simulation is the special case of implementing e^{-iHt} via Chebyshev polynomial approximation.
- **Complexity**: For Hamiltonian simulation: O(lambda * t + log(1/epsilon)) — same as qubitization. The framework achieves this with a clean, unified circuit structure.
- **Limitations**: Abstracts away many specifics behind block-encoding; practical gate counts depend heavily on how the block-encoding is implemented. The framework is theoretical — concrete chemistry applications require careful analysis of the block-encoding cost.
- **Depends on**: Low-Chuang17, Low-Chuang19, Jordan-Shor 2009 (quantum walk), Grover-Rudolph 2002
- **Superseded by**: Active area — extensions to open systems, non-unitary LCHS (An-Liu-Lin23)

### [KIEFEROVA19] Kieferova, Scherer & Berry (2019) — Simulating Time-Dependent Hamiltonians with a Truncated Dyson Series
- **Citation**: M. Kieferova, A. Scherer, D. W. Berry. "Simulating the dynamics of time-dependent Hamiltonians with a truncated Dyson series." Physical Review A 99, 042314 (2019).
- **arXiv**: https://arxiv.org/abs/1805.00582
- **Contribution**: Extended the Taylor series / LCU approach to explicitly time-dependent H(t) via the Dyson series expansion of the time-ordered exponential. Two strategies for time-ordering are proposed, both using quantum superposition to sample H at different times. Retains optimal polylog(1/epsilon) dependence on precision.
- **Complexity**: O(lambda_int * polylog(1/epsilon)) where lambda_int is an integral norm of the time-dependent Hamiltonian; exact form scales with the integral of the spectral norm over the simulation interval.
- **Limitations**: Gate complexity scales with max_t ||H(t)|| rather than a time-averaged norm — Berry et al. (2020, arXiv:1906.07115) later improved this to the L1 norm. Requires access to H(t) at multiple times simultaneously.
- **Depends on**: BCKS-PRL15, BCKS-STOC14
- **Superseded by**: Berry-Childs-Su-Wang-Wiebe20 (1906.07115) for L1-norm scaling

### [LOW-WIEBE19] Low & Wiebe (2019) — Hamiltonian Simulation in the Interaction Picture
- **Citation**: G. H. Low, N. Wiebe. "Hamiltonian simulation in the interaction picture." arXiv preprint (2018–2019).
- **arXiv**: https://arxiv.org/abs/1805.00675
- **Contribution**: Algorithms for simulating H = H_0 + V where H_0 is easy to exponentiate (e.g., diagonal kinetic operator). By moving to the interaction picture (rotating frame of e^{-iH_0 t}), V becomes time-dependent but has reduced effective norm. Uses a truncated Dyson series with quasilinear gate complexity. Reduces quantum chemistry simulation from Õ(N^{11/3}t) to Õ(N^2 t) for N-site Hubbard models.
- **Complexity**: Exponential improvement for diagonally dominant Hamiltonians; polynomial improvement (typically 2–3 powers of N) for quantum chemistry. Scales with the norm of the interaction term V rather than the full H.
- **Limitations**: Requires the free Hamiltonian H_0 to be efficiently exponentiable; not applicable when H has no useful decomposition H_0 + V. Time-dependent interaction picture Hamiltonian must be queried at multiple times.
- **Depends on**: Low-Chuang19 (qubitization), Kieferova19
- **Superseded by**: Babbush et al. (1807.09802) applied this to first-quantized chemistry with further improvements

### [BERRY20] Berry, Childs, Su, Wang & Wiebe (2020) — Time-Dependent Hamiltonian Simulation with L1-Norm Scaling
- **Citation**: D. W. Berry, A. M. Childs, Y. Su, X. Wang, N. Wiebe. "Time-dependent Hamiltonian simulation with L^1-norm scaling." Quantum 4, 254 (2020).
- **arXiv**: https://arxiv.org/abs/1906.07115
- **Contribution**: For time-dependent Hamiltonian simulation, replaces the worst-case norm t * max_tau ||H(tau)|| with the integrated (L1) norm int_0^t dτ ||H(τ)||. Introduces a classical sampler for time-dependent Hamiltonians and a rescaling principle for the Schrödinger equation. Results in a "nearly optimal" rescaled Dyson series algorithm.
- **Complexity**: Gate complexity scales with int_0^t dτ ||H(τ)||_max (the L1 norm) rather than t * max_tau ||H(tau)||_max. For Hamiltonians that vary significantly in magnitude over time, this gives an asymptotic improvement proportional to the ratio of L1 to L-infinity norm.
- **Limitations**: Requires the time-dependent LCU decomposition to be efficiently samplable. The improvement over Kieferova19 is primarily asymptotic; practical gains depend on the specific Hamiltonian's temporal variation.
- **Depends on**: Kieferova19, Low-Wiebe19, BCKS-PRL15
- **Superseded by**: Active frontier — no known improvement in general yet

### [BABBUSH18-SPECTRA] Babbush et al. (2018) — Encoding Electronic Spectra in Quantum Circuits with Linear T Complexity
- **Citation**: R. Babbush, C. Gidney, D. W. Berry, N. Wiebe, J. McClean, A. Paler, A. Fowler, H. Neven. "Encoding electronic spectra in quantum circuits with linear T complexity." Physical Review X 8, 041015 (2018).
- **arXiv**: https://arxiv.org/abs/1805.03662
- **Contribution**: Constructed explicit quantum circuits implementing the PREPARE and SELECT oracles for electronic structure Hamiltonians (Hubbard model and molecular orbital basis) with T-gate complexity linear in N (number of orbitals). Invoking these within the qubitization framework gives quantum phase estimation with total T-gate count O(N/epsilon).
- **Complexity**: O(N + log(1/epsilon)) T-gates per walk step; full phase estimation requires O(N/epsilon) T-gates total. "Linear T complexity" in N is the key achievement.
- **Limitations**: Requires approximately a million logical qubits for interesting molecules after error correction overhead. Circuit constructions are specific to second-quantized electronic structure.
- **Depends on**: Low-Chuang19 (qubitization), BCKS-PRL15
- **Superseded by**: Babbush et al. (1902.02134) for arbitrary basis with sparsity/low-rank exploitation

### [BABBUSH19-CHEM] Babbush et al. (2019) — Qubitization of Arbitrary Basis Quantum Chemistry Leveraging Sparsity and Low Rank Factorization
- **Citation**: D. W. Berry, C. Gidney, M. Motta, J. R. McClean, R. Babbush. "Qubitization of arbitrary basis quantum chemistry leveraging sparsity and low rank factorization." Quantum 3, 208 (2019).
- **arXiv**: https://arxiv.org/abs/1902.02134
- **Contribution**: Applied qubitization to second-quantized chemistry in arbitrary (Gaussian orbital) basis sets by exploiting sparsity in the Coulomb operator and low-rank tensor factorization of the two-electron integrals. Achieved Õ(N^{3/2} lambda) T complexity, where lambda is the 1-norm of the Hamiltonian. Applied to FeMoco (nitrogen fixation), yielding ~700x reduction in surface code spacetime volume over prior methods.
- **Complexity**: Õ(N^{3/2} lambda) T-gate complexity where lambda = sum of absolute Hamiltonian coefficients. Improves to Õ(N lambda) with full low-rank factorization.
- **Limitations**: Lambda can still be large for strongly correlated molecules. First-quantized methods (1807.09802) can be more efficient when N >> eta.
- **Depends on**: Babbush18-SPECTRA, Low-Chuang19
- **Superseded by**: Su-Berry-Wiebe-Rubin-Babbush21 for detailed fault-tolerant resource estimates

### [BABBUSH19-SUBLIN] Babbush et al. (2019) — Quantum Simulation of Chemistry with Sublinear Scaling in Basis Size
- **Citation**: R. Babbush, D. W. Berry, J. R. McClean, H. Neven. "Quantum simulation of chemistry with sublinear scaling in basis size." npj Quantum Information 5, 92 (2019).
- **arXiv**: https://arxiv.org/abs/1807.09802
- **Contribution**: First-quantized chemistry simulation using interaction picture techniques (rotating frame of the kinetic operator). Gate complexity Õ(N^{1/3} eta^{8/3}) where eta is the number of electrons and N the number of plane-wave orbitals — far more efficient than prior approaches (Õ(N^{8/3}/eta^{2/3})) when N >> eta.
- **Complexity**: Õ(N^{1/3} eta^{8/3}) in first quantization with plane waves. Sublinear in N — the basis set size.
- **Limitations**: Benefits primarily accrue when N >> eta, as needed for fine discretization or without Born-Oppenheimer approximation. Plane-wave basis may require large N for chemical accuracy.
- **Depends on**: Low-Wiebe19 (interaction picture), Low-Chuang19 (qubitization)
- **Superseded by**: Su et al. (2105.12767) for fault-tolerant resource estimates

### [CAMPBELL19] Campbell (2019) — A Random Compiler for Fast Hamiltonian Simulation (qDRIFT)
- **Citation**: E. T. Campbell. "A random compiler for fast Hamiltonian simulation." Physical Review Letters 123, 070503 (2019).
- **arXiv**: https://arxiv.org/abs/1811.08017
- **Contribution**: Introduced the qDRIFT (quantum stochastic drift protocol): instead of deterministically implementing the LCU, sample Hamiltonian terms with probability proportional to their coefficient magnitudes and implement a random Trotter step. Circuit size depends only on the 1-norm lambda (not the number of terms L or the largest individual term), giving significant speedups for chemistry Hamiltonians.
- **Complexity**: O(lambda^2 t^2 / epsilon) random Trotter steps, each of cost O(1). Circuit size is independent of L. Practical speedups of 300x–1600x over standard Trotter for molecular systems.
- **Limitations**: Produces a mixed-state output (statistical mixture over random circuits); the algorithm is inherently probabilistic. Does not achieve polylog(1/epsilon) scaling — still polynomial in 1/epsilon. Cannot be straightforwardly concatenated with other LCU methods without losing the probabilistic nature.
- **Depends on**: BCKS-PRL15 (LCU idea), Childs-Su-Tran (randomised product formulas)
- **Superseded by**: Not strictly superseded; complementary to deterministic LCU

### [SU21] Su, Berry, Wiebe, Rubin & Babbush (2021) — Fault-Tolerant Quantum Simulations of Chemistry in First Quantization
- **Citation**: Y. Su, D. W. Berry, N. Wiebe, N. Rubin, R. Babbush. "Fault-tolerant quantum simulations of chemistry in first quantization." PRX Quantum 2, 040332 (2021).
- **arXiv**: https://arxiv.org/abs/2105.12767
- **Contribution**: End-to-end fault-tolerant resource analysis (T-gate counts, logical qubit counts, surface-code spacetime volumes) for first-quantized chemistry simulation using qubitization and interaction-picture frameworks. Provides concrete circuits and counts for industrially relevant molecules. Qubitized algorithm achieves gate complexities Õ(eta^{8/3} N^{1/3} t).
- **Complexity**: Õ(eta^{8/3} N^{1/3} t) for qubitized variant, Õ(eta^{8/3} N^{1/3} t) for interaction picture (same asymptotic but better constants). Qubitized algorithm often requires much less spacetime volume than second-quantized methods.
- **Limitations**: First-quantization requires anti-symmetrisation overhead (eta-qubit state preparation). Fault-tolerant cost still requires millions of physical qubits for classically hard molecules.
- **Depends on**: Babbush19-SUBLIN, Low-Chuang19, Low-Wiebe19
- **Superseded by**: Active ongoing improvements (2312.07654, 2408.03145)

### [AN-LIU-LIN23] An, Liu & Lin (2023) — Linear Combination of Hamiltonian Simulation for Nonunitary Dynamics
- **Citation**: D. An, J.-P. Liu, L. Lin. "Linear combination of Hamiltonian simulation for nonunitary dynamics with optimal state preparation cost." Physical Review Letters 131, 150603 (2023).
- **arXiv**: https://arxiv.org/abs/2303.01029
- **Contribution**: Introduced LCHS (linear combination of Hamiltonian simulation) for non-unitary (open quantum system) dynamics. Instead of dilating the problem to a larger Hilbert space or using QSVT, LCHS represents the non-unitary propagator directly as a linear combination of unitary Hamiltonian evolutions. Achieves optimal state preparation cost and near-optimal dependence on all parameters.
- **Complexity**: Near-optimal in all parameters for simulating general (non-unitary) dynamics. Applicable to open quantum dynamics via the complex absorbing potential method.
- **Limitations**: Requires the non-unitary evolution to admit a suitable integral representation as a mixture of Hamiltonian evolutions (this holds for a broad class including ODE solutions). Not yet a fully general framework for arbitrary CPTP maps.
- **Depends on**: BCKS-PRL15, QSVT19, Low-Chuang19
- **Superseded by**: Active area — extensions (arXiv:2312.03916, arXiv:2502.19688)

### [LOW17-QSP] Low & Chuang (2017) (see also [LOW-CHUANG19]) — note: entry above covers this

### [HAAH18] Haah, Hastings, Kothari & Low (2018) — Quantum Algorithm for Simulating Real Time Evolution of Lattice Hamiltonians
- **Citation**: J. Haah, M. B. Hastings, R. Kothari, G. H. Low. "Quantum algorithm for simulating real time evolution of lattice Hamiltonians." Proceedings of FOCS 2018; SIAM Journal on Computing (2021).
- **arXiv**: https://arxiv.org/abs/1801.03922
- **Contribution**: Exploits Lieb-Robinson bounds to simulate geometrically local lattice Hamiltonians on n qubits for time T with O(nT polylog(nT/epsilon)) gates — quasilinear in nT, polylogarithmic in 1/epsilon. Uses LCU (qubitization) within a clever decomposition of the time-evolution into a product of small unitaries supported on local patches.
- **Complexity**: O(nT polylog(nT/epsilon)) gates and depth O(T polylog(nT/epsilon)). First algorithm achieving gate cost quasilinear in nT and polylogarithmic in 1/epsilon for lattice systems.
- **Limitations**: Specific to geometrically local (lattice) Hamiltonians; not applicable to all-to-all or sparse but non-local systems. The Lieb-Robinson velocity is a system-dependent constant that enters the complexity.
- **Depends on**: Low-Chuang19, BCK-FOCS15, Lieb-Robinson bounds
- **Superseded by**: Active area with recent improvements using Magnus expansion

### [CHILDS-MASLOV18] Childs, Maslov, Nam, Ross & Su (2018) — Toward the First Quantum Simulation with Quantum Speedup
- **Citation**: A. M. Childs, D. Maslov, Y. Nam, N. J. Ross, Y. Su. "Toward the first quantum simulation with quantum speedup." Proceedings of the National Academy of Sciences 115, 9456–9461 (2018).
- **arXiv**: https://arxiv.org/abs/1711.10980
- **Contribution**: End-to-end explicit circuit synthesis and resource comparison of three leading simulation approaches (product formulas, quantum signal processing, LCU/Taylor series) for spin-system Hamiltonians. Quantum signal processing (QSP) dominates when rigorous error bounds are needed; higher-order product formulas prevail when empirical error estimates suffice.
- **Complexity**: Provides explicit gate counts (not just asymptotics) for a model system. QSP circuits are many orders of magnitude smaller than algorithms for factoring or quantum chemistry.
- **Limitations**: Study focuses on a specific spin-system testbed; chemistry Hamiltonians have different structure. Comparison does not include qDRIFT (predates it).
- **Depends on**: BCKS-PRL15, BCK-FOCS15, Low-Chuang17
- **Superseded by**: More detailed resource studies for chemistry (Su21, Babbush19-CHEM)

---

## Open Problems

1. **Optimal time-dependent simulation**: The L1-norm algorithm of Berry et al. (2020) is near-optimal but a tight lower bound for the time-dependent case has not been proved. Is the L1 norm the right measure?

2. **Interaction picture for general Hamiltonians**: The interaction picture gives dramatic improvements when H = H_0 + V with H_0 easily exponentiable. Finding canonical decompositions for general Hamiltonians remains open.

3. **Non-unitary LCU (LCHS)**: The LCHS framework (An-Liu-Lin 2023) handles a broad class of open-system dynamics but is not yet fully general for arbitrary CPTP maps. Extension to Lindblad evolution with jump operators requires further work.

4. **Classical preprocessing of QSP phases**: Computing the polynomial phase angles for QSP/qubitization classically is now tractable (Haah 2019, Dong et al. 2021) but remains a bottleneck for large lambda values. Symbolic precomputation integrated into a DSL compiler is unexplored.

5. **Constant-factor optimisation**: Most results are stated up to polylog factors. For fault-tolerant chemistry applications, the prefactors in the T-gate count are critical. Systematic reduction of lambda (1-norm) via Hamiltonian partitioning, symmetry, and tensor factorization is an active area (Loaiza et al. 2022).

6. **Channel-level LCU**: Applying LCU to channels (CPTP maps) rather than unitaries — especially circuits with measurements — is largely open. The Choi-Jamiołkowski representation may allow a phase-polynomial or LCU treatment of full channel circuits, directly relevant to Sturm.jl's DAG IR.

---

## Relevance to Sturm.jl

LCU-based Hamiltonian simulation maps directly onto the Sturm.jl 4-primitive DSL. The two core operations are:

**PREPARE oracle** — loads the coefficient vector |alpha| / ||alpha||_1 as a superposition. In Sturm.jl primitives: `QBool(p)` (preparation) followed by sequences of `q.theta += delta` (amplitude rotations) implement arbitrary single-qubit state preparation. An ancilla register of log(L) qubits can be prepared in the superposition sum_k sqrt(alpha_k / lambda) |k> via a sequence of QBool preparations and CNOT-controlled rotations (a.k.a. unary iteration or QROM).

**SELECT oracle** — applies U_k controlled on ancilla index |k>. In Sturm.jl: `a xor= b` (CNOT) is the only entangling primitive, and `when(c) { ... }` implements controlled blocks. The SELECT oracle for a Pauli-decomposed Hamiltonian reduces to controlled-X, controlled-Y (= X then phase correction), and controlled-Z gates — all expressible from `a xor= b` and `q.phi += delta` within `when()` blocks.

**Oblivious amplitude amplification** — three applications of the walk operator G = (2 PREPARE PREPARE† - I) composed with the reflection on the good subspace. This is a sequence of controlled rotations and CNOT gates, implementable entirely in the DSL.

The critical subtlety for Sturm.jl is the CLAUDE.md note on channel IR: LCU methods as described assume unitary simulation. In circuits with measurements (ObserveNode) or discards (DiscardNode), LCU must be applied only to unitary subcircuits partitioned at measurement barriers — unless the Choi-phase-polynomial research direction (Sturm.jl-d99) succeeds in extending LCU natively to channels. The interaction picture decomposition H = H_0 + V also maps to Sturm.jl naturally: H_0 contributes a time-evolution channel expressible as QBool + rotations, while V is compiled as an LCU subcircuit within the same context.

---

## TOPIC SUMMARY
- Papers found: 18
- Papers downloaded: 0 (all available on arXiv open access)
- Top 3 most relevant to Sturm.jl: [BCKS-PRL15], [QSVT19], [AN-LIU-LIN23]
- Key insight for implementation: The LCU PREPARE+SELECT architecture maps cleanly to Sturm.jl's 4 primitives — PREPARE is QBool + angle rotations, SELECT is `when()`-controlled Pauli applications via `a xor= b` and `q.phi += delta`. The 1-norm lambda of the Hamiltonian coefficient vector is the key complexity parameter: minimising lambda (via symmetry, tensor factorization, or interaction-picture splitting) directly minimises circuit depth.
