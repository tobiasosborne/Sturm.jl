# Variational / Hybrid Quantum-Classical Simulation Methods

## Category Summary

Variational hybrid quantum-classical algorithms occupy the central position in near-term quantum computing research. The core idea, crystallised by the Variational Quantum Eigensolver (VQE) of Peruzzo et al. (2014), is to offload the hardest part of quantum simulation — state preparation and expectation-value measurement — onto a quantum device, while delegating all optimisation to a classical computer. The quantum device prepares a parametrised ansatz state |ψ(θ)⟩ from a circuit whose gate rotations are controlled by a real-valued parameter vector θ; the classical computer evaluates a cost function (typically ⟨H⟩ = ⟨ψ(θ)|H|ψ(θ)⟩) and proposes an updated θ. At convergence the variational principle guarantees ⟨H⟩ ≥ E₀, bounding the ground state from above. This removes the requirement for deep, fully coherent phase-estimation circuits and was the first convincing proposal for "useful quantum advantage" on noisy, pre-fault-tolerant hardware (NISQ).

The field rapidly bifurcated into two regimes: static problems (ground-state energies of molecular and condensed-matter Hamiltonians, combinatorial optimisation) and dynamic problems (real-time Hamiltonian evolution, imaginary-time cooling, open-system dynamics). For dynamics the McLachlan variational principle replaces the Rayleigh-Ritz bound, and the parameters evolve according to equations of motion derived from the quantum geometric tensor. Both regimes share the same circuit template: a sequence of parametrised single-qubit rotation layers interleaved with entangling CNOT layers. This template maps directly onto Sturm.jl's four primitives.

The decade following the first VQE experiment produced a rich landscape: adaptive ansatz construction (ADAPT-VQE) that grows the circuit only where it matters; hardware-efficient variants that respect connectivity constraints; quantum natural gradient that accounts for the curvature of the parameter manifold; and the disturbing discovery of barren plateaus — exponentially vanishing gradients that make training infeasible at scale for generic, random ansätze. Error mitigation (zero-noise extrapolation, quasi-probability decomposition) emerged as the critical enabler that separates "evidence of utility" on 127-qubit processors from noise-dominated gibberish. The field now understands both the power and the fundamental trainability limits of variational methods, with ongoing work on structured ansätze, Lie-algebraic diagnostics, and channel-level extensions.

---

## Timeline

| Year | Milestone |
|------|-----------|
| 2013 (posted) / 2014 (pub.) | Peruzzo et al. — first VQE experiment on photonic processor (HeH⁺) |
| 2014 | Farhi, Goldstone, Gutmann — QAOA introduced for combinatorial optimisation |
| 2016 | McClean et al. — full variational hybrid theory, UCC ansatz formalised |
| 2016 | O'Malley et al. — VQE on superconducting qubits (H₂), first scalable chemistry |
| 2016 (posted) / 2017 (pub.) | Temme, Bravyi, Gambetta — zero-noise extrapolation for error mitigation |
| 2016 (posted) / 2017 (pub.) | Li & Yuan — variational quantum simulator for dynamics |
| 2017 | Kandala et al. (IBM) — hardware-efficient VQE on 6 qubits (BeH₂) |
| 2017 (posted) / 2018 (pub.) | Endo, Benjamin, Li — practical quasi-probability error mitigation |
| 2017 (posted) / 2019 (pub.) | Hadfield et al. — Quantum Alternating Operator Ansatz (QAOA²) |
| 2018 | McClean et al. — barren plateaus discovered |
| 2018 (posted) | Yuan et al. — unified theory of variational quantum simulation |
| 2018 (posted) | Grimsley et al. — ADAPT-VQE: circuit grows operator by operator |
| 2018 (posted) | Lee et al. — k-UpCCGSD: generalized UCC with O(kN) circuit depth |
| 2018 (posted) | Endo et al. — variational simulation of general (non-unitary) processes |
| 2019 | Motta et al. — quantum imaginary time evolution (QITE) |
| 2019 | Stokes et al. — quantum natural gradient via Fubini-Study metric |
| 2019 (posted) / 2021 (pub.) | Tang et al. — qubit-ADAPT-VQE, order-of-magnitude depth reduction |
| 2020 | Cerezo et al. — cost-function-dependent barren plateau analysis |
| 2020 | Wiersema et al. — Hamiltonian variational ansatz: near-trap-free landscape |
| 2020 (posted) / 2021 (pub.) | Yao et al. — adaptive variational quantum dynamics (AVQDS) |
| 2021 | Cerezo et al. — comprehensive variational quantum algorithms review (Nat. Rev. Phys.) |
| 2021 | Tilly et al. — VQE review: methods and best practices |
| 2022 | Larocca et al. — Lie-algebraic barren plateau diagnosis via dynamical algebra |
| 2023 | Kim et al. (IBM) — 127-qubit evidence of utility, error mitigation at scale |

---

## Papers

---

### [VQE-ORIG] Peruzzo et al. (2014) — A variational eigenvalue solver on a photonic quantum processor

- **Citation**: A. Peruzzo, J. McClean, P. Shadbolt, M.-H. Yung, X.-Q. Zhou, P. J. Love, A. Aspuru-Guzik, J. L. O'Brien. *Nature Communications* 5, 4213 (2014).
- **arXiv**: https://arxiv.org/abs/1304.3061
- **Contribution**: Introduced the Variational Quantum Eigensolver (VQE). Demonstrated on a photonic chip that a parametrised quantum state can be optimised classically to approximate the ground-state energy of HeH⁺, requiring only shallow circuits and no full phase estimation.
- **Complexity**: O(poly(N)) classical evaluations; circuit depth far below QPE requirements; polynomial measurement overhead per Pauli term.
- **Limitations**: Measurement overhead grows with Hamiltonian size (O(N⁴) Pauli terms for molecular Hamiltonians in the STO-3G basis); no noise analysis; hardware limited to 2 qubits in initial experiment.
- **Depends on**: QPE theory (Kitaev 1995), unitary coupled-cluster (Bartlett 1989), variational principle.
- **Superseded by**: McClean et al. 2016 (theory), Kandala et al. 2017 (hardware scale), ADAPT-VQE (ansatz quality), Tilly et al. 2022 (review).

---

### [VQE-THEORY] McClean, Romero, Babbush, Aspuru-Guzik (2016) — The theory of variational hybrid quantum-classical algorithms

- **Citation**: J. R. McClean, J. Romero, R. Babbush, A. Aspuru-Guzik. *New Journal of Physics* 18, 023023 (2016).
- **arXiv**: https://arxiv.org/abs/1509.04279
- **Contribution**: Established the general theoretical framework for all variational hybrid algorithms. Proved the variational bound E(θ) ≥ E₀ for any parametrised ansatz, introduced the unitary coupled-cluster (UCC) family formally, derived the parameter-shift rule for gradient estimation, and analysed the variational adiabatic ansatz. Connects second-order UCC to universal gate sets via Trotter splitting relaxation.
- **Complexity**: General VQE with k-UCCSD: O(N⁵) terms, O(N⁴) circuit depth per Trotter step; gradient via parameter-shift requires 2p evaluations for p parameters.
- **Limitations**: UCCSD circuit depth is prohibitive for current hardware; no treatment of noise; classical optimisation landscape not analysed.
- **Depends on**: [VQE-ORIG], UCC theory, adiabatic quantum computation.
- **Superseded by**: [ADAPT] for ansatz quality; [BARREN-ORIG] for landscape understanding; [QNG] for optimiser.

---

### [HE-VQE] Kandala et al. (2017) — Hardware-efficient variational quantum eigensolver for small molecules and quantum magnets

- **Citation**: A. Kandala, A. Mezzacapo, K. Temme, M. Takita, M. Brink, J. M. Chow, J. M. Gambetta. *Nature* 549, 242–246 (2017).
- **arXiv**: https://arxiv.org/abs/1704.05018
- **Contribution**: Introduced hardware-efficient ansätze (HEA) tailored to native gate sets and qubit connectivity, bypassing the need for chemistry-derived UCC. First VQE on superconducting hardware at scale (6 qubits, >100 Pauli terms, molecules up to BeH₂). Demonstrated zero-noise extrapolation as a practical error-mitigation strategy.
- **Complexity**: O(d·n) circuit depth for d layers and n qubits; parameters scale as O(d·n). Circuit depth 10–100× shallower than UCC at the cost of ansatz expressibility.
- **Limitations**: HEA often barren at large scale ([BARREN-ORIG]); expressibility vs. trainability tradeoff is severe; accuracy limited by hardware noise.
- **Depends on**: [VQE-ORIG], [VQE-THEORY], [ZNE] (zero-noise extrapolation).
- **Superseded by**: [ADAPT] for ansatz quality; [BARREN-LOCAL] for understanding why HEA fails at scale.

---

### [VQE-H2] O'Malley et al. (2016) — Scalable quantum simulation of molecular energies

- **Citation**: P. J. J. O'Malley et al. (Google / UCSB / Harvard). *Physical Review X* 6, 031007 (2016).
- **arXiv**: https://arxiv.org/abs/1512.06860
- **Contribution**: First VQE demonstration on superconducting qubits (Google Xmon processor). Computed the H₂ potential energy surface using both UCC-VQE and QPE. Demonstrated VQE at chemical accuracy (1 kcal/mol) without exponentially costly precompilation, the first such result on superconducting hardware.
- **Complexity**: 2-qubit system; UCC-VQE with 1 variational parameter; QPE with 6–9 ancilla qubits.
- **Limitations**: Only 2 spatial orbitals (minimal basis); no error mitigation; does not scale directly to larger molecules.
- **Depends on**: [VQE-ORIG], [VQE-THEORY], Jordan-Wigner encoding.
- **Superseded by**: [HE-VQE] for hardware scale; [VQE-REVIEW] for systematic methodology.

---

### [VQE-REVIEW] Tilly et al. (2022) — The variational quantum eigensolver: a review of methods and best practices

- **Citation**: J. Tilly, H. Chen, S. Cao, D. Picozzi, K. Setia, Y. Li, E. Grant, L. Wossnig, I. Rungger, G. H. Booth, J. Tennyson. *Physics Reports* 986, 1–128 (2022).
- **arXiv**: https://arxiv.org/abs/2111.05176
- **Contribution**: Comprehensive 128-page review of VQE: Hamiltonian encoding (Jordan-Wigner, Bravyi-Kitaev, parity), ansatz families (UCC, hardware-efficient, problem-inspired), gradient methods (parameter-shift, SPSA, natural gradient), error mitigation integration, and classical post-processing. Best-practices guide for practitioners.
- **Complexity**: Survey covers O(N⁴)–O(N⁸) UCCSD scaling through O(kN) k-UpCCGSD.
- **Limitations**: As a review, does not introduce new algorithms. Rapid-obsolescence risk for NISQ-era results as hardware improves.
- **Depends on**: All prior VQE literature.
- **Superseded by**: Ongoing experimental literature (2022–present).

---

### [ADAPT] Grimsley, Economou, Barnes, Mayhall (2019) — An adaptive variational algorithm for exact molecular simulations on a quantum computer

- **Citation**: H. R. Grimsley, S. E. Economou, E. Barnes, N. J. Mayhall. *Nature Communications* 10, 3007 (2019).
- **arXiv**: https://arxiv.org/abs/1812.11173
- **Contribution**: Introduced ADAPT-VQE: rather than fixing an ansatz before optimisation, the circuit grows by appending the operator from a predefined pool that has the largest gradient at each step. The result is a compact, molecule-specific ansatz that achieves chemical accuracy with far fewer parameters than UCCSD. Gradient screening identifies the "most needed" operator at each growth step.
- **Complexity**: Converges with O(N) operators for many molecular systems; each growth step requires O(|pool|) gradient evaluations. Circuit depth scales with number of growth steps, typically N–5N for N orbitals.
- **Limitations**: Greedy growth does not guarantee globally optimal ordering; pool choice determines reachable states; gradient screening requires O(|pool|) circuits per step (measurement overhead); original fermionic pool has large CNOT counts.
- **Depends on**: [VQE-THEORY], UCCSD theory, Trotterized UCC.
- **Superseded by**: [Q-ADAPT] (hardware-efficient pool with O(N) minimal pool operators).

---

### [Q-ADAPT] Tang et al. (2021) — qubit-ADAPT-VQE: an adaptive algorithm for constructing hardware-efficient ansätze on a quantum processor

- **Citation**: H. L. Tang, V. O. Shkolnikov, G. S. Barron, H. R. Grimsley, N. J. Mayhall, E. Barnes, S. E. Economou. *PRX Quantum* 2, 020310 (2021).
- **arXiv**: https://arxiv.org/abs/1911.10205
- **Contribution**: Reformulated ADAPT-VQE using qubit operators (Pauli strings) rather than fermionic operators. Proved that a pool satisfying a completeness criterion of size O(N) suffices. Demonstrated an order-of-magnitude reduction in CNOT count compared to fermionic-ADAPT while maintaining the same energy accuracy. Introduced the pool completeness criterion as a rigorous theoretical tool.
- **Complexity**: Minimal complete pool size: O(N) operators; CNOT count per operator: O(1) vs O(N) for fermionic pool; overall circuit depth reduction: 10×–100× over fermionic-ADAPT.
- **Limitations**: Qubit pools may have weaker physical intuition; completeness does not imply efficiency for all molecules; gradient screening overhead unchanged.
- **Depends on**: [ADAPT], Jordan-Wigner/Bravyi-Kitaev encodings.
- **Superseded by**: Active development; see generalised ADAPT variants (2022–present).

---

### [GUCC] Lee, Huggins, Head-Gordon, Whaley (2019) — Generalized unitary coupled cluster wavefunctions for quantum computation

- **Citation**: J. Lee, W. J. Huggins, M. Head-Gordon, K. B. Whaley. *Journal of Chemical Theory and Computation* 15, 311–324 (2019).
- **arXiv**: https://arxiv.org/abs/1810.02327
- **Contribution**: Introduced the k-UpCCGSD family: k products of pair coupled-cluster double (pCCD) exponentials together with generalised single excitations. Established O(kN) circuit depth — polynomial in N, not O(N³) as for UCCGSD. Demonstrated that k=2 or k=3 achieves near-UCCSD accuracy on benchmark molecules with far shallower circuits. Provides a systematic route to improvability by increasing k.
- **Complexity**: Circuit depth O(kN); O(kN) parameters; k-UpCCGSD is strictly better scaling than O((N-η)²η) UCCSD (η = electron number).
- **Limitations**: Not adaptive (pre-fixed structure); for strongly correlated systems may need large k; does not exploit problem structure the way ADAPT does.
- **Depends on**: [VQE-THEORY], UCCSD, pCCD methods from quantum chemistry.
- **Superseded by**: [ADAPT], [Q-ADAPT] for adaptivity; used as a baseline in comparative studies.

---

### [VQS-LI] Li, Yuan (2017) — Efficient variational quantum simulator incorporating active error minimisation

- **Citation**: Y. Li, S. C. Benjamin. *Physical Review X* 7, 021050 (2017).
- **arXiv**: https://arxiv.org/abs/1611.09301

  > **Note**: The originally listed ID 1611.09696 is a lattice QCD paper (Λc form factors). The correct ID for this paper is 1611.09301.

- **Contribution**: First variational approach to quantum dynamics simulation. Encodes the time-evolved state |ψ(t)⟩ in a parametrised circuit and evolves the parameters θ(t) according to McLachlan's variational principle. Also introduced active error minimisation: artificial noise boosting followed by zero-noise extrapolation, anticipating [ZNE] independently and from a simulation perspective.
- **Complexity**: O(poly(N)) classical work per time step; circuit depth bounded by ansatz complexity; each time step requires solving a linear system of size p×p (p = number of parameters).
- **Limitations**: Variational manifold may not contain the true time-evolved state; p×p linear solve becomes ill-conditioned; error from finite-size variational manifold accumulates over time.
- **Depends on**: McLachlan's variational principle (McLachlan 1964), TDVP (Dirac 1930).
- **Superseded by**: [VQS-YUAN] (unified theory), [AVQDS] (adaptive dynamics).

---

### [VQS-YUAN] Yuan, Endo, Zhao, Li, Benjamin (2019) — Theory of variational quantum simulation

- **Citation**: X. Yuan, S. Endo, Q. Zhao, Y. Li, S. C. Benjamin. *Quantum* 3, 191 (2019).
- **arXiv**: https://arxiv.org/abs/1812.08767
- **Contribution**: Unified theoretical framework for all variational quantum simulation tasks. Derives McLachlan's variational principle, the Dirac-Frenkel principle, and TDVP from a common geometric picture. Shows they are equivalent for pure states. Addresses both real-time and imaginary-time dynamics, energy minimisation (VQE as a special case), and variational cooling. Establishes conditions for efficient classical simulation of the equation-of-motion matrices.
- **Complexity**: Per time step: O(p²) quantum circuits for p-parameter ansatz (to compute the quantum geometric tensor and force vector); O(p³) classical linear-algebra.
- **Limitations**: Quantum geometric tensor estimation adds significant measurement overhead; assumes ansatz can represent the target state; error accumulation not systematically bounded.
- **Depends on**: [VQS-LI], [VQE-THEORY], variational principles in classical mechanics.
- **Superseded by**: [AVQDS] for adaptive circuit growth during dynamics; [QNG] for geometric optimisation (static case).

---

### [VQS-GENERAL] Endo, Sun, Li, Benjamin, Yuan (2020) — Variational quantum simulation of general processes

- **Citation**: S. Endo, J. Sun, Y. Li, S. C. Benjamin, X. Yuan. *Physical Review Letters* 125, 010501 (2020).
- **arXiv**: https://arxiv.org/abs/1812.08778

  > **Note**: The originally listed ID 1812.03023 does not correspond to this paper. The correct arXiv ID is 1812.08778.

- **Contribution**: Extended variational quantum simulation beyond unitary dynamics. Derives variational algorithms for: (1) non-Hermitian Hamiltonian evolution (open systems); (2) linear algebra problems (solving Ax = b on quantum hardware); (3) general Lindblad master equations for open quantum system dynamics. This is the key paper establishing that variational methods can handle non-unitary (channel) evolution.
- **Complexity**: Non-Hermitian evolution: O(p²) circuits per step as in [VQS-YUAN]; open-system (Lindblad): same structure with density-matrix ansatz, 4× overhead for mixed states.
- **Limitations**: Non-unitary circuit evaluation requires ancilla qubits and ancilla-measurement; Lindblad simulation requires density matrix representation; assumes ansatz remains within physical (CPTP) manifold.
- **Depends on**: [VQS-YUAN], Lindblad master equation theory, dilation methods.
- **Superseded by**: [AVQDS] for adaptive dynamics; active research area for open-system simulation.

---

### [AVQDS] Yao et al. (2021) — Adaptive variational quantum dynamics simulations

- **Citation**: Y.-X. Yao, N. Gomes, F. Zhang, C.-Z. Wang, K.-M. Ho, T. Iadecola, P. P. Orth. *PRX Quantum* 2, 030307 (2021).
- **arXiv**: https://arxiv.org/abs/2011.00622

  > **Note**: The originally listed ID 2011.09185 does not correspond to this paper. The correct arXiv ID is 2011.00622.

- **Contribution**: Combined ADAPT-style circuit growth with variational dynamics. The ansatz expands during time evolution by adding operators whenever the McLachlan distance (a measure of simulation accuracy) exceeds a threshold. Applied to Lieb-Schultz-Mattis spin chains and post-quench dynamics of the mixed-field Ising model. Demonstrated accurate long-time dynamics with far fewer parameters than fixed-structure ansätze.
- **Complexity**: Adaptive: circuit depth grows as needed; each expansion step tests O(|pool|) candidate operators; overhead controlled by the McLachlan distance threshold ε.
- **Limitations**: Pool choice determines expressibility ceiling; McLachlan distance computation still requires O(p²) measurements; no rigorous bound on total circuit depth for general Hamiltonians.
- **Depends on**: [ADAPT], [VQS-YUAN], McLachlan's variational principle.
- **Superseded by**: Active development; see compressed circuit variants (Yao et al. 2024, arXiv:2408.06590).

---

### [BARREN-ORIG] McClean, Boixo, Smelyanskiy, Babbush, Neven (2018) — Barren plateaus in quantum neural network training landscapes

- **Citation**: J. R. McClean, S. Boixo, V. N. Smelyanskiy, R. Babbush, H. Neven. *Nature Communications* 9, 4812 (2018).
- **arXiv**: https://arxiv.org/abs/1803.11173
- **Contribution**: Proved that for a broad class of parametrised quantum circuits (those forming a 2-design, e.g. random deep circuits), the variance of any gradient component vanishes exponentially in the number of qubits: Var[∂θ C] = O(2^{-n}). This means gradient-based optimisation becomes exponentially hard for large n — the parameter landscape is flat almost everywhere ("barren plateau"). Analytic proof using unitary t-design theory.
- **Complexity**: Gradient magnitude: O(2^{-n}); required measurements to resolve gradient: O(2^n) — exponential.
- **Limitations**: Worst-case result for random circuits; structured ansätze (ADAPT, HVA) may evade barren plateaus; result uses global cost function.
- **Depends on**: Unitary t-designs, random matrix theory, 2-design circuit families.
- **Superseded by**: [BARREN-LOCAL] (local cost functions avoid barren plateaus), [BARREN-LIE] (Lie-algebraic diagnosis), [BARREN-REVIEW] (comprehensive framework).

---

### [BARREN-LOCAL] Cerezo, Sone, Volkoff, Cincio, Coles (2021) — Cost function dependent barren plateaus in shallow parametrised quantum circuits

- **Citation**: M. Cerezo, A. Sone, T. Volkoff, L. Cincio, P. J. Coles. *Nature Communications* 12, 1791 (2021).
- **arXiv**: https://arxiv.org/abs/2001.00550

  > **Note**: The originally listed ID 2001.02550 does not correspond to this paper. The correct arXiv ID is 2001.00550.

- **Contribution**: Proved that the barren plateau phenomenon depends critically on whether the cost function is global (all-qubit observable) or local (few-qubit observable). For local cost functions and circuits of depth O(log n), gradients vanish at most polynomially — the problem is poly-hard, not exponentially hard. Provided a concrete design principle: use local cost functions where possible. Proved the first positive result distinguishing trainable from untrainable VQA regimes.
- **Complexity**: Local cost, depth O(log n): Var[∂θ C] = O(1/poly(n)) — polynomial overhead; Global cost, any depth: Var[∂θ C] = O(2^{-n}) — exponential overhead.
- **Limitations**: O(log n) depth restriction is severe for quantum chemistry; local cost functions may not capture the physical quantity of interest; concentration bound may still be impractical at moderate n.
- **Depends on**: [BARREN-ORIG], Levy's lemma, polynomial approximation theory.
- **Superseded by**: [BARREN-LIE] for general ansatz-agnostic diagnostics.

---

### [VQA-REVIEW] Cerezo et al. (2021) — Variational quantum algorithms (Nature Reviews Physics)

- **Citation**: M. Cerezo, A. Arrasmith, R. Babbush, S. C. Benjamin, S. Endo, K. Fujii, J. R. McClean, K. Mitarai, X. Yuan, L. Cincio, P. J. Coles. *Nature Reviews Physics* 3, 625–644 (2021).
- **arXiv**: https://arxiv.org/abs/2012.09265
- **Contribution**: The canonical review of the entire variational quantum algorithms landscape. Covers: ansatz families (chemistry-inspired, hardware-efficient, problem-inspired, machine-learning); cost function design; optimisation (gradient-free, gradient-based, quantum natural gradient); error mitigation integration; applications (chemistry, optimisation, linear systems, machine learning, quantum simulation); trainability (barren plateaus, noise-induced barren plateaus); and prospects for quantum advantage. 20-author consensus document from the leading groups.
- **Complexity**: Review paper; surveys O(1)–O(2^n) regimes depending on ansatz and cost.
- **Limitations**: Review snapshot from late 2020; pre-dates IBM utility (2023) and recent Lie-algebraic barren plateau theory.
- **Depends on**: Entire prior VQA literature.
- **Superseded by**: [VQE-REVIEW] (VQE-specific depth); active literature 2022–present.

---

### [BARREN-LIE] Larocca, Czarnik, Sharma, Muraleedharan, Coles, Cerezo (2022) — Diagnosing barren plateaus with tools from quantum optimal control

- **Citation**: M. Larocca, P. Czarnik, K. Sharma, G. Muraleedharan, P. J. Coles, M. Cerezo. *Quantum* 6, 824 (2022).
- **arXiv**: https://arxiv.org/abs/2105.14377
- **Contribution**: Proved that the presence or absence of barren plateaus is determined by the dimension of the dynamical Lie algebra (DLA) of the ansatz generators. Large DLA (dim ∝ 4^n) → barren plateau; small DLA (dim ∝ poly(n)) → at most polynomial gradient suppression. Gives a clean, ansatz-specific diagnostic via Lie bracket closure computation. Applied to QAOA, Hamiltonian Variational Ansatz (HVA), and hardware-efficient ansätze; shows HVA has small DLA for many physical Hamiltonians.
- **Complexity**: DLA dimension determines trainability; computing DLA: O(poly(n)) for structured Hamiltonians, but DLA can be exponential in general.
- **Limitations**: DLA computation may itself be expensive; does not address noise-induced barren plateaus; assumes noiseless circuits.
- **Depends on**: [BARREN-ORIG], [BARREN-LOCAL], Lie group theory, quantum optimal control (GRAPE).
- **Superseded by**: Active development in Lie-algebraic VQA theory (Larocca et al. 2023+).

---

### [ZNE] Temme, Bravyi, Gambetta (2017) — Error mitigation for short-depth quantum circuits

- **Citation**: K. Temme, S. Bravyi, J. M. Gambetta. *Physical Review Letters* 119, 180509 (2017).
- **arXiv**: https://arxiv.org/abs/1612.02058
- **Contribution**: Introduced two foundational error mitigation schemes: (1) Zero-noise extrapolation (ZNE): artificially boost the noise level by gate folding or time-scaling, measure ⟨O⟩ at multiple noise levels, extrapolate to zero noise via Richardson or polynomial extrapolation; (2) Probabilistic error cancellation (PEC) / quasi-probability decomposition: invert the noise channel by sampling a quasi-probability distribution over Clifford operations. Both require no additional qubits and work with general Markovian noise models.
- **Complexity**: ZNE: O(k) circuit evaluations for k extrapolation points; PEC: O(γ²/ε²) shots to achieve ε accuracy, where γ = 1-norm of the quasi-probability (grows exponentially with gate count).
- **Limitations**: ZNE assumes noise is simply amplifiable; extrapolation breaks down for deeply noisy circuits; PEC overhead is exponential in circuit volume.
- **Depends on**: Richardson extrapolation (classical numerical analysis), quantum channels, Clifford decompositions.
- **Superseded by**: [QEM-ENDO] (practical implementation), [IBM-UTILITY] (large-scale demonstration).

---

### [QEM-ENDO] Endo, Benjamin, Li (2018) — Practical quantum error mitigation for near-future applications

- **Citation**: S. Endo, S. C. Benjamin, Y. Li. *Physical Review X* 8, 031027 (2018).
- **arXiv**: https://arxiv.org/abs/1712.09271
- **Contribution**: Made ZNE and quasi-probability decomposition practically implementable by: (1) providing a systematic protocol to measure the error model from the hardware itself; (2) showing that Markovian errors can be corrected by inserting single-qubit Clifford gates + measurements; (3) extending the framework to coherent errors; (4) introducing symmetry verification as a post-selection strategy. Bridged the gap between the theoretical proposals of [ZNE] and experimental implementation.
- **Complexity**: O(N_gate) circuits for error characterisation; O(γ²) overhead for quasi-probability cancellation as in [ZNE].
- **Limitations**: Requires accurate noise characterisation, which may be itself expensive; assumes gate noise is sufficiently local; coherent errors require additional Clifford twirling.
- **Depends on**: [ZNE], randomised benchmarking, Clifford group theory.
- **Superseded by**: Clifford data regression (Czarnik et al. 2021), probabilistic error amplification (IBM 2021).

---

### [IBM-UTILITY] Kim et al. (2023) — Evidence for the utility of quantum computing before fault tolerance

- **Citation**: Y. Kim, A. Eddins, S. Anand et al. (IBM Quantum). *Nature* 618, 500–505 (2023).
- **arXiv**: Not available — published directly in Nature. DOI: https://doi.org/10.1038/s41586-023-06096-3
- **Contribution**: Ran 127-qubit Trotterised time-evolution circuits (up to 60 two-qubit layers) on the IBM Eagle processor with Pauli noise learning + probabilistic error amplification (PEA). Measured expectation values that classical tensor-network methods (MPS, isoTNS) could not reproduce accurately. First credible claim of "quantum utility" — quantum hardware producing useful results beyond classical brute-force simulation. The error mitigation protocol was central: without it, results were noise-dominated.
- **Complexity**: 127 qubits; 60 Trotter layers; circuit volume at the edge of classical simulation capability; error mitigation overhead: O(N_Pauli) characterisation circuits.
- **Limitations**: Significant subsequent debate over classical simulability (Beguŝić & Chan arXiv:2306.16372 showed fast classical simulation of the same circuits); utility claim contingent on specific classical methods chosen as baselines; PEA error mitigation is bespoke and hardware-specific.
- **Depends on**: [ZNE], [QEM-ENDO], Clifford data regression, Pauli noise learning.
- **Superseded by**: Ongoing debate; larger utility experiments (2024+).

---

### [QAOA] Farhi, Goldstone, Gutmann (2014) — A quantum approximate optimization algorithm

- **Citation**: E. Farhi, J. Goldstone, S. Gutmann. Preprint (2014). arXiv only — not peer-reviewed journal publication.
- **arXiv**: https://arxiv.org/abs/1411.4028
- **Contribution**: Introduced the Quantum Approximate Optimization Algorithm (QAOA). For a combinatorial objective function C(z) on n bits, the QAOA circuit of depth p alternates between e^{-iγC} (phase separator) and e^{-iβB} (mixing unitary, B = Σᵢ Xᵢ). As p → ∞, QAOA approximates adiabatic evolution and converges to the optimum. For p=1, analytical approximation ratios are derived for MaxCut on 3-regular graphs: ≥ 0.6924. The circuit structure is a parametrised alternating operator sequence — a natural special case of VQE.
- **Complexity**: Circuit depth O(p) per round; 2p free parameters (γ, β for each layer); evaluation of C requires O(n) measurements per Pauli term.
- **Limitations**: Approximation ratio improvement with p is not monotone; no polynomial-time classical bound on optimal p; barren plateaus for large p ([BARREN-LIE]); does not achieve QPTAS for MaxCut in general.
- **Depends on**: Adiabatic quantum computation, quantum phase estimation, combinatorial optimisation.
- **Superseded by**: [QAOA-EXT] for constrained problems; active optimisation research (2020+).

---

### [QAOA-EXT] Hadfield et al. (2019) — From the quantum approximate optimization algorithm to a quantum alternating operator ansatz

- **Citation**: S. Hadfield, Z. Wang, B. O'Gorman, E. G. Rieffel, D. Venturelli, R. Biswas. *Algorithms* 12, 34 (2019).
- **arXiv**: https://arxiv.org/abs/1709.03489
- **Contribution**: Generalised QAOA from MaxCut to arbitrary combinatorial problems with constraints. The key insight: the mixing unitary need not be Σᵢ Xᵢ — any parametrised family of unitaries that preserves the feasible subspace can serve as a mixer. Introduced problem-specific mixers for graph colouring, k-SAT, Max k-Vertex Cover, and portfolio optimisation. The "Quantum Alternating Operator Ansatz" (also QAOA) frames the algorithm as a general variational ansatz template, not tied to a specific problem structure.
- **Complexity**: Circuit depth O(p); number of free parameters 2p; mixer design is problem-specific and may add circuit depth.
- **Limitations**: No general performance guarantees beyond QAOA level; constraint-preserving mixer construction is non-trivial; barren plateaus persist for large p.
- **Depends on**: [QAOA], quantum walks, constraint satisfaction.
- **Superseded by**: Active research; see warm-start QAOA, recursive QAOA (RQAOA), 2021+.

---

### [QITE] Motta et al. (2020) — Determining eigenstates and thermal states on a quantum computer using quantum imaginary time evolution

- **Citation**: M. Motta, C. Sun, A. T. K. Tan, M. J. O'Rourke, E. Ye, A. J. Minnich, F. G. S. L. Brandão, G. K.-L. Chan. *Nature Physics* 16, 205–210 (2020).
- **arXiv**: https://arxiv.org/abs/1901.07653
- **Contribution**: Implemented imaginary-time evolution (e^{-τH}|ψ⟩) on a quantum computer by projecting onto a variational manifold using the McLachlan principle (as in [VQS-YUAN]) with imaginary rather than real time. Ground states are obtained as τ → ∞; thermal states via Gibbs averaging using minimally entangled typical thermal states (METTS). Demonstrated on Rigetti Aspen-1 (up to 4 qubits) and classical emulation (larger). First quantum implementation of QITE.
- **Complexity**: O(p²) circuits per imaginary-time step; convergence requires τ ~ 1/(E₁-E₀) (inverse gap); METTS thermal averaging adds a Monte Carlo overhead.
- **Limitations**: Gap dependence means slow convergence near degeneracies; requires knowledge of imaginary-time propagation direction; METTS sampling variance may be high.
- **Depends on**: [VQS-YUAN], imaginary-time evolution (Wick rotation), METTS (Stoudenmire & White 2010).
- **Superseded by**: Variational quantum imaginary-time ansatz methods; [AVQDS] for adaptive extension.

---

### [QNG] Stokes, Izaac, Killoran, Carleo (2020) — Quantum natural gradient

- **Citation**: J. Stokes, J. Izaac, N. Killoran, G. Carleo. *Quantum* 4, 269 (2020).
- **arXiv**: https://arxiv.org/abs/1909.02108
- **Contribution**: Applied natural gradient descent — gradient descent in the steepest direction under the Fisher information metric rather than Euclidean distance — to parametrised quantum circuits. The relevant metric is the Fubini-Study metric tensor (real part of the quantum geometric tensor), G_{ij}(θ) = Re[⟨∂ᵢψ|∂ⱼψ⟩ - ⟨∂ᵢψ|ψ⟩⟨ψ|∂ⱼψ⟩]. Update rule: θ ← θ - η G⁺ ∇C. Proved convergence speed-up over standard gradient descent on benchmark circuits. Introduced an efficient block-diagonal approximation to G.
- **Complexity**: Full QNG: O(p²) circuits to estimate G; block-diagonal approximation: O(p) circuits; matrix inversion: O(p³) classical.
- **Limitations**: Full G estimation is expensive for large p; ill-conditioning near plateaus (G^+ pseudoinverse); block-diagonal approximation sacrifices accuracy; still suffers from barren plateaus if ∇C itself vanishes.
- **Depends on**: Natural gradient (Amari 1998), Fubini-Study metric, [VQE-THEORY] parameter-shift rule.
- **Superseded by**: Stochastic approximation variants; projected quantum natural gradient (2022+).

---

### [HVA] Wiersema et al. (2020) — Exploring entanglement and optimization within the Hamiltonian variational ansatz

- **Citation**: R. Wiersema, C. Zhou, Y. de Sereville, J. F. Carrasquilla, Y. B. Kim, H. Yuen. *PRX Quantum* 1, 020319 (2020).
- **arXiv**: https://arxiv.org/abs/2008.02941
- **Contribution**: Studied the Hamiltonian Variational Ansatz (HVA), where the circuit alternates between exponentials of each term in the target Hamiltonian H = Σₖ hₖ Hₖ: U(θ) = Πₗ [Πₖ e^{-iθ_{lk}Hₖ}]. Showed via numerical experiments that HVA exhibits (1) mild or absent barren plateaus for physical Hamiltonians; (2) near-trap-free landscape in the over-parameterised regime; (3) entanglement structure that tracks the physics of the problem. Explained why HVA works better than hardware-efficient ansätze using DLA-related arguments (predating [BARREN-LIE]).
- **Complexity**: HVA depth proportional to number of Hamiltonian terms × number of layers; parameters O(|terms| × layers); DLA dimension is generically small for local Hamiltonians.
- **Limitations**: Numerical evidence only; does not prove absence of barren plateaus rigorously; assumes Hamiltonian locality; circuit depth grows with system size for fixed accuracy.
- **Depends on**: [QAOA] (HVA is the continuous generalisation), [VQE-THEORY], entanglement spectrum theory.
- **Superseded by**: [BARREN-LIE] (provides the Lie-algebraic explanation of why HVA avoids barren plateaus).

---

## Open Problems

1. **Barren plateau avoidance at scale**: Identifying general conditions under which ansätze remain trainable for n > 100 qubits. The [BARREN-LIE] Lie-algebraic criterion is promising but requires efficient DLA computation. Noise-induced barren plateaus (Wang et al. 2021) compound the problem.

2. **Classical simulability boundary**: The [IBM-UTILITY] experiment triggered debate about exactly where the classical/quantum boundary lies. Tensor network methods continue to improve; the boundary is not sharp and depends on entanglement structure, not qubit count alone.

3. **Convergence guarantees for ADAPT**: Greedy operator selection in [ADAPT] provably converges (gradient = 0 implies global minimum for the UCC ansatz), but convergence rate and circuit depth bounds for strongly correlated systems are open.

4. **Variational methods for open systems**: [VQS-GENERAL] extended to Lindblad dynamics but the variational manifold for mixed states (density matrices) is poorly understood. CPTP-preserving ansätze on parametrised circuits are not fully characterised.

5. **Error mitigation scaling**: [ZNE] and [QEM-ENDO] cost scales polynomially only under favourable noise models. For generic noise the overhead is exponential in circuit volume. Whether error mitigation can be combined with error correction to achieve polynomial overhead at scale is open.

6. **Quantum advantage for optimisation**: Despite the ubiquity of [QAOA], no polynomial quantum speedup over the best classical algorithms (Goemans-Williamson, semi-definite programming) has been proved for NP-hard combinatorial problems. The p → ∞ adiabatic limit is known to be efficient but circuits of polynomial depth are not.

7. **Hamiltonian encoding overhead**: Pauli decomposition of molecular Hamiltonians produces O(N⁴) terms. Each measurement round requires grouping into simultaneously measurable sets. Reducing this overhead (classical shadows, derandomised sampling) remains active research.

8. **Integration with fault tolerance**: As hardware quality improves, the NISQ / fault-tolerant boundary will be crossed. How variational methods compose with fault-tolerant primitives (magic state distillation, Clifford+T gates) is not yet clear. Can VQE be made fault-tolerant at lower overhead than QPE?

---

## Relevance to Sturm.jl

Variational hybrid methods are the most natural application domain for Sturm.jl's four-primitive DSL. Every parametrised quantum circuit in the variational literature is a sequence of the DSL's primitives:

| VQA concept | Sturm.jl construct |
|-------------|-------------------|
| Ansatz parameter rotation Ry(θ) | `q.theta += θ` |
| Phase kickback / Rz(φ) | `q.phi += φ` |
| Entangling layer (CNOT) | `a xor= b` |
| Initial state preparation | `QBool(p)` (p=0 for |0⟩, p=1 for |1⟩) |
| Hardware-efficient layer | alternating `q.theta +=` / `q.phi +=` / `a xor= b` |
| UCCSD double excitation | CNOT-ladder + Ry rotations from `gates.jl` |
| QAOA phase separator e^{-iγC} | Z-rotation layer `q.phi += 2γ*C_coeff` per Pauli Z term |
| QAOA mixer e^{-iβB} | `q.theta += 2β` on all qubits |

**Specific implementation notes:**

1. **Parameter-shift gradient**: The parameter-shift rule — ∂_θ ⟨C⟩ = [⟨C(θ+π/2)⟩ - ⟨C(θ-π/2)⟩] / 2 — applies directly to `q.theta += θ` and `q.phi += θ` primitives since Ry and Rz have eigenvalues ±1/2. No chain rule complications for the four-primitive basis.

2. **ADAPT-VQE pool construction**: The fermionic operator pool entries are products of Pauli strings, each expressible as CNOT-ladder + Ry rotation sequences via the standard Givens rotation decomposition. All pool operators are buildable from the four primitives as in `gates.jl`.

3. **Quantum geometric tensor estimation**: The [QNG] Fubini-Study metric tensor requires computing ⟨∂ᵢψ|∂ⱼψ⟩. The parameter-shift rule for the four primitives gives these derivatives analytically, enabling efficient QNG without automatic differentiation.

4. **Channel-level consideration**: [VQS-GENERAL] extends variational simulation to non-unitary dynamics (Lindblad, non-Hermitian). Sturm.jl's DAG IR is channel-based (not unitary-only), making it the natural home for this extension. Specifically: variational Lindblad simulation requires `ObserveNode` + `CasesNode` patterns within the variational loop — this is where Sturm.jl's barrier-partitioned optimisation protocol is relevant. Check Sturm.jl-d99 (Choi phase polynomials) before implementing; if that research matures, the barrier partitioning may be unnecessary for variational channel simulation.

5. **Error mitigation integration**: ZNE (artificial noise boosting via gate folding) maps to Sturm.jl's `noise/` module. Gate folding replaces `U` with `U·U†·U` — expressible as three invocations of the same primitive sequence. Quasi-probability decomposition (PEC) maps to a sampling loop over `DiscardNode` and `depolarise!` calls.

6. **Context model**: The EagerContext is appropriate for small-n VQE experiments (direct statevector). For noise-model studies, DensityMatrixContext (backed by Orkan's density matrix mode) is the right context for [VQS-GENERAL] and error mitigation benchmarks.
