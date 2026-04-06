# Quantum Signal Processing / QSVT

## Category Summary

Quantum Signal Processing (QSP) and its generalisation, the Quantum Singular Value Transformation (QSVT), constitute the currently dominant unifying framework for quantum algorithms. The core insight is elegant: given a unitary oracle that encodes a matrix A as a block (a "block encoding"), one can apply an arbitrary polynomial transformation to the singular values of A by interleaving the oracle and its inverse with precisely chosen single-qubit phase rotations on an ancilla register. These rotations — parameterised by a sequence of real angles called "phase factors" — are exactly the θ and φ primitives of Sturm.jl's DSL. The polynomial approximation theory (Chebyshev, Jackson kernels, etc.) then determines which functions of A can be computed, and with what circuit depth.

The framework subsumes an impressive catalogue of quantum algorithms: Hamiltonian simulation (e^{-iHt} applied via Jacobi-Anger expansion), quantum phase estimation (eigenvalue thresholding), amplitude amplification (Grover's algorithm as a degree-1 QSP circuit), HHL matrix inversion (polynomial approximation to 1/x), quantum walks (the Szegedy walk operator IS a block encoding), and ground-state preparation (low-pass eigenvalue filters). The "grand unification" framing of Martyn et al. (2021) makes this explicit with a single pedagogical framework.

The state of the art as of 2026 is: (1) QSVT achieves optimal or near-optimal query complexity for essentially every known quantum simulation task; (2) the practical bottleneck has shifted from circuit structure to phase-factor computation — stable double-precision algorithms (QSPPACK, Ying's Prony method, GQSP's recursive formula) now handle polynomial degrees up to 10^7; (3) the framework has been extended to multiple variables (M-QSP), non-polynomial functions via infinite sequences (infinite QSP), and non-normal operators (quantum eigenvalue processing / QEVT); (4) hardware demonstrations on trapped-ion processors have validated the approach at circuit depths up to 360 layers.

## Timeline

- **2004**: Szegedy introduces the quantum walk quantisation of Markov chains — the walk operator is the conceptual ancestor of the qubitized oracle.
- **2010**: Childs shows continuous-time quantum walk can simulate arbitrary sparse Hamiltonians; Berry and Childs prove lower bounds for black-box Hamiltonian simulation.
- **2012**: Berry, Childs et al. prove the first nearly-optimal sparse Hamiltonian simulation algorithms.
- **2015**: Berry, Childs, Cleve, Kothari, Somma introduce LCU (Linear Combination of Unitaries) / Taylor-series Hamiltonian simulation — first algorithm with log(1/ε) dependence on precision.
- **2016–2017**: Low and Chuang introduce Quantum Signal Processing (QSP) for sparse Hamiltonians and prove it achieves the information-theoretic lower bound.
- **2016–2019**: Low and Chuang develop qubitization — the generalisation from sparse to LCU-structured Hamiltonians — achieving O(t + log(1/ε)) query complexity.
- **2018–2019**: Gilyén, Su, Low, Wiebe unify everything under QSVT: polynomial transformations of block-encoded singular values, a single framework for all quantum matrix arithmetic.
- **2019**: Haah proves that QSP phase-factor computation is efficient (O(N³ polylog)) under the RAM model.
- **2000/2002**: Brassard, Hoyer, Mosca, Tapp formalise amplitude amplification and estimation — now understood as degree-1 QSP instances.
- **2020–2021**: Dong, Meng, Whaley, Lin (QSPPACK); Chao, Ding, Gilyén, Huang, Szegedy give practical double-precision algorithms for phase-factor computation; Martyn et al. write the pedagogical grand-unification tutorial.
- **2021**: Lin and Tong achieve near-optimal ground-state preparation; first chemistry simulations with explicit QSVT resource counts (Su, Berry, Babbush et al.).
- **2022**: Wang, Dong, Lin analyse the benign energy landscape of symmetric QSP; Ying gives a Prony-based stable factorisation; Rossi and Chuang extend to multi-variable QSP; Lin's UC Berkeley lecture notes become the standard graduate reference.
- **2023–2024**: Motlagh and Wiebe introduce Generalized QSP (GQSP) lifting all polynomial restrictions; Low and Su extend to non-normal operators (QEVT/quantum eigenvalue processing); Dong, Lin et al. extend QSP to infinite sequences (Szegő functions); hardware experiments on trapped-ion devices demonstrate deep QSP circuits.
- **2025–2026**: Ongoing work on adversary bounds, multi-variable constructive algorithms, and noise-resilient QSP ensembles.

---

## Papers

### [LOW-CHUANG-17] Low, Chuang (2017) — Optimal Hamiltonian Simulation by Quantum Signal Processing
- **arXiv/DOI**: arXiv:1606.02685 / doi:10.1103/PhysRevLett.118.010501
- **PDF status**: not_found (available at https://arxiv.org/pdf/1606.02685)
- **Category**: PHASE_POLY | RESOURCE_EST
- **Key idea**: Introduces the three-step QSP methodology — transduce Hamiltonian eigenvalues into an ancilla qubit, transform them via a sequence of single-qubit Rz/Ry rotations interleaved with oracle calls, then project. Proves query complexity O(td||H||_max + log(1/ε)/log log(1/ε)) for d-sparse Hamiltonians, matching lower bounds in ALL parameters simultaneously.
- **Complexity**: O(td||H||_max + log(1/ε)/log log(1/ε)) — optimal in t, d, ||H||, ε.
- **Limitations**: Requires sparse-oracle access model; does not directly handle general LCU Hamiltonians; phase-factor computation treated as given.
- **Relevance to Sturm.jl**: The QSP signal processing rotations are literally `q.theta += delta` and `q.phi += delta` primitives. A QSP Hamiltonian simulation block maps directly to a sequence of Sturm.jl phase rotations interleaved with `a xor= b` (CNOT) controlled oracle calls.
- **Depends on**: Szegedy 2004 (quantum walks), Berry-Childs sparse simulation lower bounds
- **Superseded by**: LOW-CHUANG-19 (qubitization, handles LCU), GILYEN-19 (full QSVT)
- **Cites/cited-by**: SZEGEDY-04, CHILDS-10, BERRY-15; cited by essentially all subsequent QSP/QSVT work

### [LOW-CHUANG-19] Low, Chuang (2019) — Hamiltonian Simulation by Qubitization
- **arXiv/DOI**: arXiv:1610.06546 / doi:10.22331/q-2019-07-12-163
- **PDF status**: not_found (available at https://arxiv.org/pdf/1610.06546)
- **Category**: PHASE_POLY | RESOURCE_EST
- **Key idea**: Introduces the "qubitization" framework: given a Hamiltonian H = (⟨G|⊗I)U(|G⟩⊗I) expressed as a projection of a unitary oracle U onto a state |G⟩ prepared by a second oracle, constructs an invariant SU(2) subspace (the "qubitized walk") and uses QSP to apply e^{-iHt} within it. Achieves query complexity O(t + log(1/ε)) — the optimal additive form — using at most two ancilla qubits.
- **Complexity**: O(t + log(1/ε)) to both oracles — optimal in all parameters, additive rather than multiplicative in t and log(1/ε).
- **Limitations**: Requires the Hamiltonian to be expressible in the "LCU + block encoding" form; direct construction of the oracle can add overhead.
- **Relevance to Sturm.jl**: The oracle U encodes H; accessing it twice (forward + inverse) with interleaved phase rotations is the `when()` + phase-rotation structure of Sturm.jl. The two ancilla qubits are `QBool` registers.
- **Depends on**: LOW-CHUANG-17, Berry-Childs LCU framework
- **Superseded by**: GILYEN-19 (generalises to full QSVT)
- **Cites/cited-by**: LOW-CHUANG-17, BERRY-15; cited by GILYEN-19, MARTYN-21, SU-21

### [GILYEN-19] Gilyén, Su, Low, Wiebe (2019) — Quantum Singular Value Transformation and Beyond
- **arXiv/DOI**: arXiv:1806.01838 / doi:10.1145/3313276.3316366
- **PDF status**: not_found (available at https://arxiv.org/pdf/1806.01838)
- **Category**: PHASE_POLY | SYNTHESIS | RESOURCE_EST
- **Key idea**: The foundational QSVT paper. Given a unitary U that block-encodes a matrix A (meaning A appears as the top-left block of U), constructs quantum circuits applying an arbitrary degree-d polynomial transformation P to the SINGULAR VALUES of A, using O(d) queries to U and its inverse plus O(d) single-qubit rotations and a constant number of ancilla qubits. Proves this is optimal. Unifies Hamiltonian simulation, amplitude amplification, HHL, quantum walk, phase estimation, and quantum machine learning into a single framework.
- **Complexity**: O(d) queries to block encoding + O(d) single-qubit rotations for degree-d polynomial; constant ancilla overhead.
- **Limitations**: Requires a block encoding of A (constructing this can dominate the cost); phase-factor computation was not yet practically stable for large degree at publication time.
- **Relevance to Sturm.jl**: This IS the theoretical basis for a QSVT compilation pass in Sturm.jl. Each QSP rotation step is a `q.theta += delta` or `q.phi += delta` gate; oracle access uses `a xor= b` controlled operations via `when()`. The QSVT circuit structure maps 1-1 to the Sturm.jl 4-primitive basis.
- **Depends on**: LOW-CHUANG-17, LOW-CHUANG-19, BRASSARD-02 (amplitude amplification), Jordan's lemma
- **Superseded by**: MOTLAGH-24 (GQSP lifts polynomial restrictions); LOW-SU-24 (non-normal operators)
- **Cites/cited-by**: Cited by MARTYN-21, LIN-20, DONG-21, CAMPS-22, DALZELL-23, and hundreds more

### [MARTYN-21] Martyn, Rossi, Tan, Chuang (2021) — Grand Unification of Quantum Algorithms
- **arXiv/DOI**: arXiv:2105.02859 / doi:10.1103/PRXQuantum.2.040203
- **PDF status**: not_found (available at https://arxiv.org/pdf/2105.02859)
- **Category**: SYNTHESIS | RESOURCE_EST
- **Key idea**: Pedagogical tutorial showing how QSVT subsumes quantum search, quantum phase estimation, and Hamiltonian simulation as special cases. Introduces the "quantum eigenvalue transform" viewpoint. Works through explicit construction of degree-d polynomial approximations for each algorithm and shows how to read off the QSP phase factors. Essential reference for understanding QSVT from first principles.
- **Complexity**: Recapitulates optimal results from GILYEN-19 in a more accessible form.
- **Limitations**: Tutorial paper; no new complexity results.
- **Relevance to Sturm.jl**: Best starting point for implementing a QSVT compiler pass: shows exactly how to build QSP circuits for Hamiltonian simulation, amplitude amplification, and phase estimation from polynomial approximations. The phase-rotation sequences it derives map directly to Sturm.jl primitives.
- **Depends on**: GILYEN-19, LOW-CHUANG-17, LOW-CHUANG-19
- **Superseded by**: LIN-22 (lecture notes, more complete); TANG-23 (CS-theoretic simplification)
- **Cites/cited-by**: GILYEN-19; cited by essentially all subsequent pedagogical and implementation work

### [HAAH-19] Haah (2019) — Product Decomposition of Periodic Functions in Quantum Signal Processing
- **arXiv/DOI**: arXiv:1806.10236 / doi:10.22331/q-2019-10-07-190
- **PDF status**: not_found (available at https://arxiv.org/pdf/1806.10236)
- **Category**: SYNTHESIS | PHASE_POLY
- **Key idea**: Proves that the classical preprocessing step for QSP — computing the SU(2)-valued product decomposition of a target polynomial — runs in time O(N³ polylog(N/ε)) under the random-access memory model, where N is the polynomial degree. Provides rigorous numerical stability analysis that was lacking in prior efficiency claims which assumed a strong arithmetic model.
- **Complexity**: O(N³ polylog(N/ε)) classical preprocessing for degree-N polynomial.
- **Limitations**: Cubic classical cost can be expensive for N > 10^4; subsequent work (DONG-21, YING-22) improves the practical algorithm.
- **Relevance to Sturm.jl**: Establishes that a QSVT compiler pass is classically tractable — the phase-factor computation is not a bottleneck in principle, though degree bounds matter in practice.
- **Depends on**: LOW-CHUANG-17, GILYEN-19
- **Superseded by**: DONG-21 (optimization-based, more practical), YING-22 (Prony-based, faster)
- **Cites/cited-by**: LOW-CHUANG-17; cited by DONG-21, CHAO-20, YING-22

### [DONG-21] Dong, Meng, Whaley, Lin (2021) — Efficient Phase-Factor Evaluation in Quantum Signal Processing
- **arXiv/DOI**: arXiv:2002.11649 / doi:10.1103/PhysRevA.103.042419
- **PDF status**: not_found (available at https://arxiv.org/pdf/2002.11649)
- **Category**: SYNTHESIS | PHASE_POLY
- **Key idea**: Introduces an optimization-based algorithm (gradient descent on a non-convex objective) for computing QSP phase factors in standard double-precision arithmetic. Previous methods required variable-precision arithmetic. Achieves phase factors for polynomials of degree > 10,000 with error below 10^{-12}. Demonstrated on Hamiltonian simulation, eigenvalue filtering, and quantum linear system problems. Implements QSPPACK toolbox (github.com/qsppack/QSPPACK).
- **Complexity**: Practical: polynomial degrees up to ~10^4 in double precision; O(N) per gradient step.
- **Limitations**: Optimization landscape is non-convex; convergence relies on the benign landscape result later characterised by WANG-22; not guaranteed to converge from arbitrary initialisation.
- **Relevance to Sturm.jl**: QSPPACK directly provides the classical preprocessing for any QSVT compilation pass in Sturm.jl. The output phase angles are the `delta` parameters in `q.theta += delta` and `q.phi += delta`.
- **Depends on**: HAAH-19, GILYEN-19
- **Superseded by**: YING-22 (Prony-based, more stable), MOTLAGH-24 (analytic recursive formula for GQSP)
- **Cites/cited-by**: HAAH-19, GILYEN-19; cited by WANG-22, YING-22, MARTYN-21

### [CHAO-20] Chao, Ding, Gilyén, Huang, Szegedy (2020) — Finding Angles for Quantum Signal Processing with Machine Precision
- **arXiv/DOI**: arXiv:2003.02831
- **PDF status**: not_found (available at https://arxiv.org/pdf/2003.02831)
- **Category**: SYNTHESIS | PHASE_POLY
- **Key idea**: Develops two algorithmic primitives — "halving" (based on a new algebraic uniqueness theorem) and "capitalization" — to find QSP angle sequences of more than 3000 elements within 5 minutes in standard double precision. Uses a divide-and-conquer structure that avoids the root-finding instabilities of prior methods.
- **Complexity**: Practical: handles sequences of 3000+ angles; comparable to DONG-21 but via a different algorithmic path.
- **Limitations**: The "halving" step requires the polynomial to satisfy certain symmetry properties; less general than YING-22 or GQSP.
- **Relevance to Sturm.jl**: Alternative (complementary) classical preprocessing algorithm for QSVT compiler pass. Can be used for Hamiltonian simulation angle sequences when QSPPACK is not available.
- **Depends on**: HAAH-19, LOW-CHUANG-17
- **Superseded by**: YING-22, MOTLAGH-24
- **Cites/cited-by**: HAAH-19; cited by DONG-21, WANG-22, MOTLAGH-24

### [WANG-22] Wang, Dong, Lin (2022) — On the Energy Landscape of Symmetric Quantum Signal Processing
- **arXiv/DOI**: arXiv:2110.04993 / doi:10.22331/q-2022-11-03-850
- **PDF status**: not_found (available at https://arxiv.org/abs/2110.04993)
- **Category**: SYNTHESIS | PHASE_POLY
- **Key idea**: Proves that the (highly non-convex) objective function used by DONG-21 for symmetric QSP phase finding has a benign landscape with no spurious local minima in practice. Explains empirically why gradient descent works robustly from a fixed zero-initialisation despite the non-convexity. Proves global convergence for the fixed-point iteration method.
- **Complexity**: Provides convergence guarantees for the optimization in DONG-21.
- **Limitations**: Analysis specific to the symmetric QSP case; extensions to non-symmetric and GQSP landscapes are ongoing work.
- **Relevance to Sturm.jl**: Provides theoretical justification that the classical preprocessing step for a QSVT compiler pass will converge reliably. Informs choice of optimization algorithm for phase-factor computation.
- **Depends on**: DONG-21, HAAH-19
- **Superseded by**: MOTLAGH-24 (GQSP has a direct analytic formula, no optimization needed)
- **Cites/cited-by**: DONG-21; cited by YING-22, MOTLAGH-24

### [YING-22] Ying (2022) — Stable Factorization for Phase Factors of Quantum Signal Processing
- **arXiv/DOI**: arXiv:2202.02671 / doi:10.22331/q-2022-10-20-842
- **PDF status**: not_found (available at https://arxiv.org/abs/2202.02671)
- **Category**: SYNTHESIS | PHASE_POLY
- **Key idea**: Gives a new factorisation algorithm for QSP phase factors based on Prony's method — avoids root-finding of high-degree polynomials entirely. Numerically stable in double precision. Demonstrated on Hamiltonian simulation, eigenstate filtering, matrix inversion, and Fermi-Dirac operators. Faster than DONG-21 in many regimes.
- **Complexity**: Sub-cubic in polynomial degree; Prony's method is O(N²) in dominant cost.
- **Limitations**: Requires the polynomial to be of definite parity (symmetric case); less general than GQSP.
- **Relevance to Sturm.jl**: The most practically reliable classical algorithm for generating QSP phase sequences for Sturm.jl's QSVT compilation pass. Prony stability means phase factors for degree-1000+ Hamiltonian simulation polynomials can be precomputed reliably.
- **Depends on**: HAAH-19, DONG-21
- **Superseded by**: MOTLAGH-24 (GQSP with analytic formula removes need for numerical phase finding)
- **Cites/cited-by**: DONG-21, HAAH-19; cited by MOTLAGH-24

### [MOTLAGH-24] Motlagh, Wiebe (2024) — Generalized Quantum Signal Processing
- **arXiv/DOI**: arXiv:2308.01501 / doi:10.1103/PRXQuantum.5.020368
- **PDF status**: not_found (available at https://arxiv.org/pdf/2308.01501)
- **Category**: SYNTHESIS | PHASE_POLY
- **Key idea**: Replaces QSP signal processing operators (rotations in a single basis, Rz) with general SU(2) rotations. This lifts ALL practical restrictions on achievable polynomials — the only remaining constraint is |P| ≤ 1 (unitarity). Provides a simple recursive formula for computing the required angles. Can find phase factors for polynomials of degree 10^7 in under a minute of GPU time. Subsumes standard QSP, QSVT, and enables new applications (bosonic operators, convolution algorithms).
- **Complexity**: Degree-10^7 phase finding in < 1 min GPU time (O(N log N) via recursive formula).
- **Limitations**: The generalised SU(2) rotations require implementing arbitrary single-qubit gates, not just Rz; adds minor hardware overhead compared to standard QSP (only Rz + Ry in the DSL).
- **Relevance to Sturm.jl**: CRITICAL. GQSP phase angles decompose naturally into `q.theta += delta` followed by `q.phi += delta` (since SU(2) = Ry·Rz). The recursive angle formula eliminates the need for expensive numerical optimization in the QSVT compilation pass. This is the recommended classical preprocessing algorithm.
- **Depends on**: GILYEN-19, HAAH-19, DONG-21
- **Superseded by**: Nothing yet (current state of the art for phase finding)
- **Cites/cited-by**: GILYEN-19, DONG-21, YING-22; see also companion paper arXiv:2401.10321 (Doubling efficiency via GQSP)

### [ROSSI-22] Rossi, Chuang (2022) — Multivariable Quantum Signal Processing (M-QSP)
- **arXiv/DOI**: arXiv:2205.06261 / doi:10.22331/q-2022-09-20-811
- **PDF status**: not_found (available at https://arxiv.org/abs/2205.06261)
- **Category**: SYNTHESIS | PHASE_POLY
- **Key idea**: Extends QSP to multiple signal variables (two oracle types, "two-headed oracle"). Characterises exactly which multivariable polynomial transformations are achievable with M-QSP despite the non-existence of the fundamental theorem of algebra for multivariate polynomials. Gives necessary and sufficient conditions for stable multivariable polynomial transformation.
- **Complexity**: Circuit depth linear in polynomial degree per variable; exponential in number of variables in worst case.
- **Limitations**: Constructive algorithms for M-QSP phase factors are harder; see arXiv:2410.02332 (2024) for polynomial-time constructive algorithm.
- **Relevance to Sturm.jl**: Relevant for simulating Hamiltonians with multiple independent parameters (e.g., multi-body terms); M-QSP maps to interleaved oracle calls with separate phase-rotation sequences.
- **Depends on**: GILYEN-19, LOW-CHUANG-17
- **Superseded by**: Ongoing — polynomial-time constructive algorithm arXiv:2410.02332 makes M-QSP practical
- **Cites/cited-by**: GILYEN-19; cited by multivariable QSP follow-ups (arXiv:2309.16665, arXiv:2312.09072)

### [DONG-LIN-24] Dong, Lin, Ni, Wang (2024) — Infinite Quantum Signal Processing
- **arXiv/DOI**: arXiv:2209.10162 / doi:10.22331/q-2024-12-10-1558
- **PDF status**: not_found (available at https://arxiv.org/abs/2209.10162)
- **Category**: SYNTHESIS | PHASE_POLY
- **Key idea**: Extends QSP beyond polynomials to infinite series (limits of degree-d QSP as d→∞). Shows that if the target function is sufficiently regular, the phase factors have a well-defined limit in ℓ¹ space, giving a genuine "infinite QSP" representation. Extended to the full class of Szegő functions (satisfying logarithmic integrability) in arXiv:2407.05634 (Alexis, Lin, et al., 2024).
- **Complexity**: Infinite circuit depth; but finite truncations give controlled approximation error.
- **Limitations**: Requires the target function to satisfy the Szegő condition; not all functions of interest satisfy this.
- **Relevance to Sturm.jl**: Establishes the mathematical foundation for implementing non-polynomial functions (e.g., discontinuous step functions for eigenvalue projection) in QSVT compilation passes.
- **Depends on**: GILYEN-19, DONG-21
- **Superseded by**: arXiv:2407.05634 (Szegő function extension)
- **Cites/cited-by**: DONG-21, WANG-22

### [LOW-SU-24] Low, Su (2024) — Quantum Eigenvalue Processing
- **arXiv/DOI**: arXiv:2401.06240 / doi:10.1137/24M1689363
- **PDF status**: not_found (available at https://arxiv.org/pdf/2401.06240)
- **Category**: SYNTHESIS | RESOURCE_EST
- **Key idea**: Extends the QSVT framework from Hermitian/normal operators (where singular values = eigenvalues) to general non-normal operators. Introduces the Quantum EigenValue Transformation (QEVT) framework using Faber polynomials (optimal uniform approximation on non-disk domains in ℂ). Achieves Heisenberg-limited scaling for quantum eigenvalue estimation (QEVE) of diagonalizable operators with real spectra.
- **Complexity**: Heisenberg-limited for QEVE; query complexity recovering that of QSVT for Hermitian inputs.
- **Limitations**: Requires diagonalizability assumption for real-spectra guarantee; Faber polynomial computation adds classical overhead.
- **Relevance to Sturm.jl**: Relevant for open quantum systems simulation where the Liouvillian is non-normal. The QEVT circuit structure still maps to the 4-primitive basis.
- **Depends on**: GILYEN-19, LIN-20
- **Superseded by**: Nothing yet (current state of the art for non-normal operators)
- **Cites/cited-by**: GILYEN-19, LIN-20; cited by 2024-2026 linear differential equations work

### [LIN-20] Lin, Tong (2020) — Near-Optimal Ground State Preparation
- **arXiv/DOI**: arXiv:2002.12508 / doi:10.22331/q-2020-12-14-372
- **PDF status**: not_found (available at https://arxiv.org/abs/2002.12508)
- **Category**: RESOURCE_EST | SYNTHESIS
- **Key idea**: Applies QSVT to design a near-optimal ground-state preparation algorithm. Uses a polynomial filter function (a Chebyshev approximation to the indicator function for the ground eigenvalue band) to project an initial state onto the ground subspace. Achieves O(1/Δ · polylog(1/ε)) complexity where Δ is the spectral gap — nearly optimal for all parameters.
- **Complexity**: O(1/Δ · polylog(1/ε)) queries to block encoding.
- **Limitations**: Requires initial overlap with ground state bounded below; needs spectral gap lower bound.
- **Relevance to Sturm.jl**: A canonical example of "QSVT as a filter" — the polynomial filter maps to a sequence of `q.theta +=` and `q.phi +=` rotations in Sturm.jl. Relevant for variational/chemistry applications.
- **Depends on**: GILYEN-19, BRASSARD-02
- **Superseded by**: DONG-LIN-TONG-22 (QET-U, works without full block encoding for EFTQC)
- **Cites/cited-by**: GILYEN-19; cited by DONG-LIN-TONG-22, SU-21

### [DONG-LIN-TONG-22] Dong, Lin, Tong (2022) — Ground-State Preparation and Energy Estimation on Early Fault-Tolerant Quantum Computers via QET-U
- **arXiv/DOI**: arXiv:2204.05955 / doi:10.1103/PRXQuantum.3.040305
- **PDF status**: not_found (available at https://arxiv.org/abs/2204.05955)
- **Category**: RESOURCE_EST | SYNTHESIS
- **Key idea**: Introduces QET-U (Quantum Eigenvalue Transformation of Unitary matrices with Real polynomials) — a variant of QSVT that uses a controlled Hamiltonian evolution directly (rather than a full block encoding) as the input model. Requires only a single ancilla qubit and no multi-qubit controlled operations, making it suitable for early fault-tolerant devices.
- **Complexity**: Outperforms all prior algorithms with comparable circuit structure; Heisenberg-limited ground-state energy estimation.
- **Limitations**: Requires controlled-Hamiltonian-evolution as primitive, which may itself be costly; applies mainly to the symmetric polynomial case.
- **Relevance to Sturm.jl**: QET-U's reliance on controlled-unitary evolution maps naturally to Sturm.jl's `when()` construct — the controlled-Hamiltonian-evolution IS `when(ctrl) { simulate_H!(target) }`.
- **Depends on**: LIN-20, GILYEN-19
- **Superseded by**: Nothing yet for early FTQC
- **Cites/cited-by**: LIN-20, GILYEN-19; cited by energy estimation literature 2022-2026

### [LIN-LIN-22] Lin (2022) — Lecture Notes on Quantum Algorithms for Scientific Computation
- **arXiv/DOI**: arXiv:2201.08309
- **PDF status**: not_found (available at https://arxiv.org/pdf/2201.08309)
- **Category**: RESOURCE_EST | SYNTHESIS
- **Key idea**: Comprehensive graduate-level lecture notes covering block encoding, QSP, QSVT, and applications to eigenvalue problems, linear systems, and differential equations. Used in UC Berkeley Math graduate course. Currently the most complete pedagogical reference integrating all components of the QSVT pipeline.
- **Complexity**: Survey/tutorial; covers optimal complexity results from original papers.
- **Limitations**: Notes, not a research paper.
- **Relevance to Sturm.jl**: Essential reference for implementing a QSVT compilation pass. Chapters on block encoding directly address how to construct the oracle U from a Hamiltonian description.
- **Depends on**: GILYEN-19, MARTYN-21, LIN-20
- **Superseded by**: Nothing — the reference notes (maintained online)
- **Cites/cited-by**: All major QSVT papers

### [TANG-23] Tang, Tian (2023) — A CS Guide to the Quantum Singular Value Transformation
- **arXiv/DOI**: arXiv:2302.14324 / doi:10.1137/1.9781611977936.13
- **PDF status**: not_found (available at https://arxiv.org/pdf/2302.14324)
- **Category**: SYNTHESIS
- **Key idea**: Presents a CS-theoretic simplification of QSVT. Proposes viewing the QSP-to-QSVT lift through the cosine-sine decomposition rather than Jordan's lemma (the original GILYEN-19 approach). Unifies polynomial approximation constructions under "truncation of Chebyshev series" via a bounded variant of Trefethen's meta-theorem. Published at SOSA 2024.
- **Complexity**: Same as GILYEN-19; simplification of proof technique only.
- **Limitations**: Expository; no new algorithms.
- **Relevance to Sturm.jl**: The Chebyshev-series viewpoint is practically important — Sturm.jl can use Jackson-kernel-smoothed Chebyshev truncations to design QSP polynomial approximations with rigorous error bounds.
- **Depends on**: GILYEN-19, MARTYN-21
- **Superseded by**: Nothing (current best CS-theoretic exposition)
- **Cites/cited-by**: GILYEN-19, MARTYN-21

### [BERRY-15] Berry, Childs, Cleve, Kothari, Somma (2015) — Simulating Hamiltonian Dynamics with a Truncated Taylor Series
- **arXiv/DOI**: arXiv:1412.4687 / doi:10.1103/PhysRevLett.114.090502
- **PDF status**: not_found (available at https://arxiv.org/pdf/1412.4687)
- **Category**: RESOURCE_EST | FAULT_TOLERANT
- **Key idea**: Introduces the LCU (Linear Combination of Unitaries) method for Hamiltonian simulation via a truncated Taylor series of e^{-iHt}. Each term in the Taylor series is a tensor product of unitaries implementable from a sparse Hamiltonian description; a "SELECT" oracle applies them in superposition. Cost depends logarithmically on 1/ε — the first algorithm to achieve this.
- **Complexity**: O(τ log(τ/ε) / log log(τ/ε)) where τ = t·||H||₁ — optimal log(1/ε) scaling.
- **Limitations**: Superseded by qubitization for constant overhead; the LCU ancilla overhead is larger than QSVT.
- **Relevance to Sturm.jl**: LCU is the conceptual predecessor to block encoding. The "SELECT" oracle — which applies different unitaries conditioned on an ancilla register state — maps to Sturm.jl's `when()` + classical case branching.
- **Depends on**: Aharonov-Ta-Shma (LCU original), Berry-Childs sparse simulation
- **Superseded by**: LOW-CHUANG-19, GILYEN-19
- **Cites/cited-by**: Cited by LOW-CHUANG-19, GILYEN-19, SU-21

### [SU-21] Su, Berry, Wiebe, Rubin, Babbush (2021) — Fault-Tolerant Quantum Simulations of Chemistry in First Quantization
- **arXiv/DOI**: arXiv:2105.12767 / doi:10.1103/PRXQuantum.2.040332
- **PDF status**: not_found (available at https://arxiv.org/pdf/2105.12767)
- **Category**: RESOURCE_EST | FAULT_TOLERANT
- **Key idea**: Provides the first explicit circuit constructions and constant-factor resource estimates for first-quantized chemistry simulation using qubitization and interaction-picture frameworks. Reduces circuit complexity by ~1000x over naive implementations. Shows qubitization often dominates interaction-picture methods in terms of spacetime volume despite worse asymptotic scaling.
- **Complexity**: Explicit T-gate and qubit counts for molecular Hamiltonians at relevant problem sizes.
- **Limitations**: First quantization requires N^{1/3} qubits scaling with basis size; second quantization often more practical for small systems.
- **Relevance to Sturm.jl**: The explicit circuit constructions provide a blueprint for implementing chemistry-targeted QSVT blocks in Sturm.jl. The block encoding structure uses CNOT + phase rotation patterns identical to Sturm.jl primitives.
- **Depends on**: GILYEN-19, LOW-CHUANG-19, BERRY-15, BABBUSH-19
- **Superseded by**: Ongoing resource estimation refinements
- **Cites/cited-by**: LOW-CHUANG-19, GILYEN-19, BERRY-15

### [BABBUSH-19] Babbush, Berry, McClean, Neven (2019) — Quantum Simulation of Chemistry with Sublinear Scaling in Basis Size
- **arXiv/DOI**: arXiv:1807.09802 / doi:10.1038/s41534-019-0199-y
- **PDF status**: not_found (available at https://arxiv.org/abs/1807.09802)
- **Category**: RESOURCE_EST | FAULT_TOLERANT
- **Key idea**: Achieves gate complexity O(N^{1/3} η^{8/3}) for chemistry simulation in first quantization using the interaction picture and qubitization block encodings. The sublinear scaling in basis size N (vs. O(N) for second quantization) comes from working in the rotating frame of the kinetic operator.
- **Complexity**: O(N^{1/3} η^{8/3}) where N is plane-wave orbitals, η is electron count.
- **Limitations**: Tight only for certain Hamiltonians; practical overhead from interaction-picture switching.
- **Relevance to Sturm.jl**: Establishes the interaction picture as a key technique for reducing oracle complexity; relevant for implementing efficient block encodings in Sturm.jl chemistry applications.
- **Depends on**: LOW-CHUANG-19, BERRY-15
- **Superseded by**: SU-21 (explicit constants, circuits)
- **Cites/cited-by**: LOW-CHUANG-19; cited by SU-21

### [BRASSARD-02] Brassard, Hoyer, Mosca, Tapp (2002) — Quantum Amplitude Amplification and Estimation
- **arXiv/DOI**: arXiv:quant-ph/0005055 / AMS Contemporary Mathematics 305 (2002)
- **PDF status**: not_found (available at https://arxiv.org/pdf/quant-ph/0005055)
- **Category**: SYNTHESIS | RESOURCE_EST
- **Key idea**: Generalises Grover's algorithm to arbitrary amplitude amplification (for any starting-state oracle A, not just |0⟩), achieving quadratic speedup in the "good" amplitude. Introduces quantum amplitude estimation (QAE) achieving error ε with O(1/ε) oracle calls — quadratically better than classical Monte Carlo O(1/ε²). QSVT reveals these as degree-1 and degree-d QSP instances respectively.
- **Complexity**: Amplitude amplification: O(1/√a) oracle calls. Amplitude estimation: O(1/ε) oracle calls.
- **Limitations**: Requires exact knowledge of the amplitude for optimal amplification; QAE requires QPE (deep circuits). Subsequent work (GRINKO-21) removes QPE.
- **Relevance to Sturm.jl**: Amplitude amplification is directly expressible in Sturm.jl as alternating `when()` reflections. `QBool(p)` preparation + `a xor= b` CNOT + phase rotations implement the Grover diffusion operator.
- **Depends on**: Grover 1996
- **Superseded by**: GILYEN-19 (QSP/QSVT as unified framework), GRINKO-21 (QPE-free QAE)
- **Cites/cited-by**: Cited by GILYEN-19, LIN-20, MARTYN-21, and essentially all quantum finance/ML applications

### [GRINKO-21] Grinko, Gacon, Zoufal, Woerner (2021) — Iterative Quantum Amplitude Estimation
- **arXiv/DOI**: arXiv:1912.05559 / doi:10.1038/s41534-021-00379-1
- **PDF status**: not_found (available at https://arxiv.org/abs/1912.05559)
- **Category**: RESOURCE_EST
- **Key idea**: Eliminates QPE from quantum amplitude estimation by using an iterative Grover-based protocol (IQAE). Achieves quadratic speedup over classical Monte Carlo up to a double-logarithmic factor, with significantly fewer ancilla qubits and shallower circuits than standard QAE.
- **Complexity**: O(1/ε · log log(1/ε)) oracle calls — near-optimal, no QPE overhead.
- **Limitations**: Uses classical post-processing; circuit depth proportional to the Grover power used in each iteration.
- **Relevance to Sturm.jl**: IQAE's Grover iterations map to repeated `when()` reflections in Sturm.jl — a good test case for the `when()` primitive and for validating qubitized amplitude estimation.
- **Depends on**: BRASSARD-02, Grover 1996
- **Superseded by**: Further QPE-free QAE variants 2022-2024
- **Cites/cited-by**: BRASSARD-02; widely cited in quantum finance and chemistry resource estimation

### [HHL-09] Harrow, Hassidim, Lloyd (2009) — Quantum Algorithm for Linear Systems of Equations
- **arXiv/DOI**: arXiv:0811.3171 / doi:10.1103/PhysRevLett.103.150502
- **PDF status**: not_found (available at https://arxiv.org/abs/0811.3171)
- **Category**: RESOURCE_EST | SYNTHESIS
- **Key idea**: The first quantum algorithm (HHL) for solving linear systems Ax = b with exponential speedup over classical direct methods — poly(log N, κ) time where κ is the condition number, vs. O(Nκ) classically. Uses QPE to decompose b in the eigenbasis of A, applies 1/λ_j rotations, then uncomputes QPE.
- **Complexity**: O(κ² polylog(N/ε)) — later improved to O(κ polylog(N/ε)) by GILYEN-19 via polynomial approximation of 1/x.
- **Limitations**: The exponential speedup requires specific readout assumptions and QRAM input model; Tang (2019) showed classical dequantization achieves similar speedups for sampling tasks.
- **Relevance to Sturm.jl**: QSVT-based matrix inversion is HHL's optimal successor — it uses polynomial approximation of 1/x and implements via QSVT in Sturm.jl as QSP phase rotations + block encoding oracles.
- **Depends on**: QPE, Hamiltonian simulation
- **Superseded by**: GILYEN-19 (O(κ) improvement, cleaner framework)
- **Cites/cited-by**: Cited by GILYEN-19, MARTYN-21, LIN-LIN-22; widely cited in quantum machine learning literature

### [CHILDS-KOTHARI-10] Childs, Kothari (2010) — Simulating Sparse Hamiltonians with Star Decompositions
- **arXiv/DOI**: arXiv:1003.3683 / TQC 2010
- **PDF status**: not_found (available at https://arxiv.org/abs/1003.3683)
- **Category**: RESOURCE_EST
- **Key idea**: Improves sparse Hamiltonian simulation to O(d²(d + log* N)||Ht||)^{1+o(1)} queries via a decomposition of sparse Hamiltonians into star graphs + quantum walk simulation of each piece. The "quantum walk" approach is the direct predecessor of qubitization.
- **Complexity**: O(d²(d + log* N)||Ht||)^{1+o(1)} — better than prior O(d⁴) methods.
- **Limitations**: Superseded by QSP-based methods (LOW-CHUANG-17) which achieve optimal dependence on all parameters.
- **Relevance to Sturm.jl**: Historical — establishes the quantum walk lineage that became qubitization.
- **Depends on**: Szegedy 2004, Berry-Ahokas-Cleve-Sanders sparse simulation
- **Superseded by**: LOW-CHUANG-17
- **Cites/cited-by**: Szegedy 2004; cited by LOW-CHUANG-17

### [SZEGEDY-04] Szegedy (2004) — Quantum Speed-Up of Markov Chain Based Algorithms
- **arXiv/DOI**: FOCS 2004, pp. 32-41 / IEEE doi:10.1109/FOCS.2004.53
- **PDF status**: not_found (available at https://www.researchgate.net/publication/4109377)
- **Category**: SYNTHESIS
- **Key idea**: Constructs a "quantum walk" quantisation of any reversible Markov chain as a product of two non-commuting reflections, achieving quadratic speedups in mixing and hitting times. The Szegedy walk operator is conceptually the precursor to the qubitized walk operator in LOW-CHUANG-19.
- **Complexity**: Quadratic speedup over classical Markov chain algorithms.
- **Limitations**: Quadratic speedup (not exponential); limited to problems where the Markov chain structure is available.
- **Relevance to Sturm.jl**: Foundational concept — the walk operator structure (two reflections, invariant 2D subspaces) is what qubitization generalises.
- **Depends on**: Grover 1996, Ambainis quantum walks
- **Superseded by**: LOW-CHUANG-19 (qubitization generalises to arbitrary LCU Hamiltonians)
- **Cites/cited-by**: Cited by CHILDS-KOTHARI-10, LOW-CHUANG-19

### [CAMPS-22A] Camps, Van Beeumen (2022) — FABLE: Fast Approximate Quantum Circuits for Block-Encodings
- **arXiv/DOI**: arXiv:2205.00081
- **PDF status**: not_found (available at https://arxiv.org/abs/2205.00081)
- **Category**: SYNTHESIS | RESOURCE_EST
- **Key idea**: FABLE generates approximate block-encoding circuits for arbitrary dense matrices. Circuits are formulated directly in terms of one- and two-qubit gates. Provides a simple structure with controlled approximation error, enabling "fast approximate" block encoding as input to QSVT pipelines. Competes with the LCU oracle approach for structured matrices.
- **Complexity**: O(N²) two-qubit gates for N×N matrix; approximation reduces gate count.
- **Limitations**: For unstructured matrices, exponential qubit overhead is unavoidable; requires classical description of the full matrix.
- **Relevance to Sturm.jl**: FABLE provides a path from a classically-specified matrix to a block-encoding circuit expressed in Sturm.jl's 4 primitives (CNOT + phase rotations + state preparation). Essential for implementing QSVT algorithms end-to-end.
- **Depends on**: GILYEN-19, Mottonen et al. state preparation
- **Superseded by**: Nothing for approximate block encoding of dense matrices
- **Cites/cited-by**: GILYEN-19; cited by 2023-2024 block encoding papers

### [DALZELL-23] Dalzell, McArdle, Berta, et al. (2023) — Quantum Algorithms: A Survey of Applications and End-to-End Complexities
- **arXiv/DOI**: arXiv:2310.03011
- **PDF status**: not_found (available at https://arxiv.org/pdf/2310.03011)
- **Category**: RESOURCE_EST | FAULT_TOLERANT
- **Key idea**: 337-page comprehensive survey of quantum algorithm applications with end-to-end complexity analysis — not just asymptotic query complexity but full fault-tolerant resource estimates including T-gate counts, qubit numbers, and QECC overhead. Covers chemistry, materials, optimization, finance, ML. QSVT is the dominant framework throughout.
- **Complexity**: Survey paper.
- **Limitations**: Resource estimates are often pessimistic; rapidly superseded in specific domains.
- **Relevance to Sturm.jl**: The most complete reference for what Sturm.jl will need to compile to in practice — T-gate counts, qubit numbers, error budgets. Should be consulted when designing resource estimation passes.
- **Depends on**: All major QSVT and fault tolerance papers
- **Superseded by**: Domain-specific updates post-2023
- **Cites/cited-by**: Cites essentially all papers in this survey

### [REALIZATION-23] Kikuchi et al. (2023) — Realization of Quantum Signal Processing on a Noisy Quantum Computer
- **arXiv/DOI**: arXiv:2303.05533 / doi:10.1038/s41534-023-00762-0
- **PDF status**: not_found (available at https://arxiv.org/abs/2303.05533)
- **Category**: RESOURCE_EST | FAULT_TOLERANT
- **Key idea**: First experimental realization of QSP-based Hamiltonian simulation on a real quantum computer (Quantinuum H1-1 trapped-ion processor). Computes bipartite entanglement entropies of Ising spin chains, finding good agreement with exact diagonalization. Determines optimal experimental parameters by modeling the error-vs-degree trade-off.
- **Complexity**: Experimental validation on hardware.
- **Limitations**: Only shallow circuits demonstrated (limited by decoherence); degree/time trade-off must be optimised for each device.
- **Relevance to Sturm.jl**: Validates that QSP circuits compiled to Ry/Rz/CNOT (= Sturm.jl 4 primitives) execute correctly on hardware. Provides error model parameters for Sturm.jl's noise simulation via the DensityMatrixContext.
- **Depends on**: LOW-CHUANG-17, DONG-21
- **Superseded by**: arXiv:2502.20199 (deeper circuits, trapped-ion, circuit depth 360)
- **Cites/cited-by**: DONG-21, LOW-CHUANG-17

---

## Open Problems

**Phase-finding at scale**: GQSP (MOTLAGH-24) provides a recursive formula that in principle handles degree 10^7, but numerical stability for ultra-high-degree polynomials in finite precision remains an active area. The 2025 paper arXiv:2510.00443 (Lin, ICM 2026 submission) surveys the current mathematical status.

**Multi-variable QSP**: M-QSP (ROSSI-22) gives existence conditions, but polynomial-time constructive algorithms for angle sequences are only just appearing (arXiv:2410.02332, 2024). Full automation for multi-variable Hamiltonians is not yet available.

**Channel-level QSP**: Standard QSVT applies to UNITARY subcircuits. Extending QSP/QSVT natively to quantum channels (completely positive trace-preserving maps, including measurements and decoherence) is an open problem. The Choi-Jamiołkowski representation (Sturm.jl-d99) may be the key — but no complete polynomial transformation theory for Choi matrices exists yet. The Lindblad/density-matrix version of QSP is studied in the context of open quantum systems but the analogue of the "signal processing" completeness theorem has not been established.

**Block encoding construction**: For Hamiltonians not in LCU form, constructing the block-encoding oracle U is the practical bottleneck. FABLE (CAMPS-22A) addresses dense matrices; sparse structured matrices have ad-hoc solutions; but a general, automated pipeline from arbitrary Hamiltonian description to block-encoding circuit in O(polylog N) gates does not exist.

**Noise robustness**: The 2026 arXiv:2601.20073 proposes ensemble-based QSP for coherent error mitigation, but a complete theory of noise effects on QSP phase factors (and how to correct for them at the circuit level) is lacking.

**QSP vs Trotter crossover**: Empirical studies (arXiv:2408.11550) show that QSVT and Trotter simulation give qualitatively different errors for the same circuit depth. Understanding when each method is practically superior — and designing hybrid approaches — is an active area (see Childs et al. 2021 "Theory of Trotter Error", arXiv:1912.08854 for the Trotter side).

---

## Relevance to Sturm.jl

QSP and QSVT are of direct and deep relevance to Sturm.jl in three ways:

**1. The 4 primitives ARE QSP.** The QSP signal processing rotations are literally Ry(θ) and Rz(φ) interleaved with oracle applications. In Sturm.jl notation, a length-d QSP circuit for Hamiltonian simulation is:

```julia
# QSP Hamiltonian simulation circuit (pseudocode in Sturm.jl style)
for i in 1:d
    ancilla.phi += phi_angles[i]     # Rz phase rotation
    ancilla.theta += theta_angles[i] # Ry amplitude rotation
    when(ancilla) { apply_oracle!(target) }  # controlled oracle
end
```

The angles `phi_angles` and `theta_angles` are computed classically by GQSP/QSPPACK from the target polynomial approximation to e^{-iHt}. This is a natural fit with Sturm.jl: the DSL already expresses exactly this structure.

**2. Block encoding uses `when()` and `a xor= b`.** The block-encoding oracle U that encodes Hamiltonian H is constructed from a SELECT oracle (applying individual Pauli strings conditioned on ancilla register values) and a PREPARE oracle (loading LCU coefficients into superposition). SELECT is a sequence of `when(ancilla_bits) { a xor= b }` CNOT gates; PREPARE is a `QBool(p)` preparation + `q.theta +=` rotation tree. Both fit the 4-primitive DSL exactly.

**3. CRITICAL: QSVT applies only to UNITARY subcircuits.** Per CLAUDE.md's mandatory protocol, a QSVT compilation pass in Sturm.jl MUST partition the channel DAG at measurement barriers (ObserveNode/DiscardNode boundaries) before applying QSP polynomial transformations. QSVT is defined only for block-encoded UNITARY operators; applying it across a measurement is mathematically undefined. The interaction picture and qubitization frameworks (BABBUSH-19, LOW-CHUANG-19) only address unitary evolution. For full channel DAGs including measurements, the active research direction (Sturm.jl-d99) on Choi-based phase polynomials is the only candidate — and it is not yet established.

**Implementation roadmap for a QSVT pass in Sturm.jl:**
1. Partition DAG at ObserveNode/DiscardNode boundaries (unitary subcircuits).
2. For each unitary block: identify the block-encoding structure (LCU decomposition or sparse oracle).
3. Compute the polynomial approximation to the target function (e.g., Jacobi-Anger for e^{-iHt}).
4. Run GQSP (MOTLAGH-24) or QSPPACK (DONG-21/YING-22) to find QSP phase angles.
5. Emit QSP circuit: sequence of `q.phi +=` and `q.theta +=` rotations interleaved with oracle calls.
6. Verify correctness against EagerContext statevector simulation.

**Key identities for implementers:**
- Ry(2arcsin(√p))|0⟩ = √(1-p)|0⟩ + √p|1⟩ — this is `QBool(p)`, the PREPARE oracle state for amplitude p.
- Rz(φ) = e^{-iφZ/2} — the phase rotation `q.phi += φ`.
- Ry(θ) = e^{-iθY/2} — the amplitude rotation `q.theta += θ`.
- CX(b, a) = CNOT with b control, a target — this is `a xor= b`.
- The QSP "signal unitary" W(x) = [[x, i√(1-x²)], [i√(1-x²), x]] is implemented as Rz followed by a controlled-oracle followed by Rz⁻¹.
