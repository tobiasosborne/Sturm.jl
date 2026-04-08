# Sturm.jl Work Log

Gotchas, learnings, decisions, and surprises. Updated every step.

---

## 2026-04-08 — Session 9: Literature re-download + QSVT deprecation + Block Encoding Phase 1

### Literature re-download (new machine)
- Re-downloaded 90 arXiv PDFs via `download_all.sh`, 0 failures
- Downloaded Trotter 1959 (AMS, free), Feynman 1982 (Springer via TIB), Lloyd 1996 (arXiv preprint)
- Suzuki 1985/1990 need headed browser (Playwright) — skipped this session

### QSVT landscape change — Motlagh GQSP deprecated
- Downloaded two new canonical papers:
  - **Berntson, Sünderhauf (CMP 2025)**: FFT-based complementary polynomial Q from target P. O(N log N), rigorous error bounds (Theorem 3). Solves the "completion step" of QSP.
  - **Laneve (arXiv:2503.03026, July 2025)**: Proves GQSP ≡ NLFT over SU(2). The Riemann-Hilbert-Weiss algorithm gives provably stable GQSP phase factors. Machine precision (10⁻¹⁵) up to degree 10⁴.
- Also downloaded: Motlagh GQSP (2308.01501), Alexis et al. NLFA (2407.05634), Ni-Ying fast RHW (2410.06409), Yamamoto-Yoshioka (2402.03016), Ni et al. fast inverse NLFT (2505.12615), Sünderhauf generalized QSVT (2312.00723)
- Updated `qsp_qsvt/survey.md`: MOTLAGH-24 marked ⚠ DEPRECATED, BERNTSON-SUNDERHAUF-25 and LANEVE-25 marked ⚠ CANONICAL, all superseded-by chains updated, implementation roadmap rewritten

### Block Encoding Phase 1 — COMPLETE (48 tests)

**Created 18 beads issues** for the full Tier 0 plan (block encoding + QSVT). BD dependency system broken (missing wisp_dependencies table from prior DB wipe). Dependencies documented in issue descriptions only.

**Files created:**
```
src/block_encoding/
    types.jl      # BlockEncoding{N,A} struct
    prepare.jl    # PREPARE oracle (binary rotation tree)
    select.jl     # SELECT oracle (via _pauli_exp!, Toffoli cascade)
    lcu.jl        # LCU assembly: PREPARE†·SELECT·PREPARE
src/qsvt/
    conventions.jl   # QSVTPhases struct, processing operator decomposition
    polynomials.jl   # Jacobi-Anger Chebyshev approximation, Clenshaw eval
    phase_factors.jl # Berntson-Sunderhauf completion (Chebyshev→analytic→BS→Chebyshev)
test/
    test_block_encoding.jl       # 48 tests
    test_qsvt_conventions.jl     # 24 tests
    test_qsvt_polynomials.jl     # 215 tests
    test_qsvt_phase_factors.jl   # 31 tests
```

**PREPARE oracle:** Binary rotation tree on ⌈log₂ L⌉ ancilla qubits. Amplitude verification, statistical N=10000, adjoint roundtrip — all pass.

**SELECT oracle — the Session 8 bug and its resolution:**

Three failed approaches before finding the correct one:
1. ❌ Using X!/Z!/Y! inside when() — controlled-Ry(π) ≠ CX, controlled-Rz(π) ≠ CZ
2. ❌ Using _cz! for controlled-Z — leaves Rz(π/2) local phase on the ancilla
3. ❌ Using explicit CNOT + _cz! decompositions — _cz! phase still corrupts ancilla
4. ✅ **Using `_pauli_exp!` with θ=π/2** — the proven pattern from Session 7

The key insight: `exp(-i(π/2)·P) = -iP` (channel-equivalent to P). The `-i` is a uniform global phase across all terms, factoring out of the LCU sum. The `_pauli_exp!` control stack optimization handles everything correctly: basis changes and CNOT staircase run unconditionally, only the Rz pivot is controlled. The ancilla never gets a local phase.

For multi-qubit ancilla registers: Toffoli cascade (Barenco et al.) reduces all controls to a single workspace qubit, which becomes the sole entry in the control stack. This avoids the EagerContext >1 control limit.

**Skeptical reviewer (Opus) findings:**
- C2 (CRITICAL): All-identity terms (e.g., -2.0·II) can't get the -i phase from `_pauli_exp!` because `_pauli_exp!` skips them. No Ry/Rz decomposition of scalar×I exists. **Resolution:** Error loudly (Rule 1). Identity terms are classical energy offsets — subtract before block encoding.
- W2/W6 (WARNING): Block encoding can't be used inside `when()` — the X! gates in PREPARE's rotation tree and Toffoli cascade would pick up outer controls. Doesn't block QSVT (oracle called directly, not inside when), but matters for future amplitude amplification.

**LCU assembly:** U = PREPARE†·SELECT·PREPARE, U† = PREPARE·SELECT†·PREPARE†. Tests verify ⟨0|^a U |0⟩^a |ψ⟩ ∝ (H/λ)|ψ⟩ and U·U† = I.

### QSVT Phase 2 — Convention adapter + Polynomials + BS completion

**QSP convention adapter (24 tests):** Processing operator A_k = e^{iφ_k X}·e^{iθ_k Z} decomposed into 3 Sturm primitives: Rz(-2θ+π/2), Ry(-2φ), Rz(-π/2). Verified against matrix definition at 8 test points. Ref: Laneve Theorem 9.

**Jacobi-Anger polynomials (215 tests):** e^{-ixt} = J₀(t)T₀(x) + 2Σ(-i)^k J_k(t)T_k(x). Uses SpecialFunctions.jl for Bessel functions. Clenshaw recurrence for evaluation. Tested: convergence for t=0.5..5.0, boundary values, |P|≤1 constraint. Ref: Martyn et al. 2021 Eq. (29)-(30).

**Berntson-Sünderhauf completion (31 tests):**

Gotcha: **Chebyshev vs analytic polynomial convention.** The Jacobi-Anger coefficients are in the Chebyshev basis (P(x) = Σ c_k T_k(x) for x∈[-1,1]). The BS algorithm expects monomial coefficients P(z) = Σ p_k z^k with |P(z)|≤1 on the unit circle. Chebyshev T_k(x) = (z^k+z^{-k})/2 are Laurent polynomials — evaluating the Chebyshev coefficients as monomial gives |P(z)| up to 1.92 on the circle, violating the BS precondition.

**Fix:** Convert Chebyshev → analytic via Laneve Lemma 1. The Laurent polynomial P_L(z) = c₀ + Σ c_k(z^k+z^{-k})/2 becomes the analytic polynomial P_a(z) = z^d·P_L(z) of degree 2d, with |P_a| = |P_L| ≤ 1 on the circle. After BS computes Q_a, convert back via `analytic_to_chebyshev`. Degree doubles internally (d→2d) but the returned Q has degree d.

Algorithm 2 (downscaling) used for robustness: P_scaled = (1-ε/4)·P gives delta=ε/4 gap, avoiding log(0) singularities.

### Gotcha: NEVER run two Julia processes simultaneously
- Background agents (3 separate incidents) spawned `Pkg.test()` concurrently
- Both hit the same `.julia/compiled/` cache → potential corruption
- Killed immediately each time. **Hard rule:** all Julia runs sequential, from main conversation only. Subagents FORBIDDEN from running Julia. Saved to memory.

### Gotcha: Subagents ignore instructions about Pkg.test()
- Despite explicit "DO NOT run Pkg.test()" in the prompt, both Opus subagents ran full test suites
- The full suite takes ~15 minutes (N=24 qubit simulations)
- **Hard rule:** subagents must not run Julia at all. Test execution happens in main conversation only.

### Beads DB status
- DB was wiped by a prior agent. Reinitialized in embedded mode.
- `bd dep` is broken (missing wisp_dependencies table). Dependencies documented in issue descriptions only.
- 18 issues total: 7 closed, 11 open.

### Session 9 final status

**Closed issues (7):** z0b (BE types), di6 (PREPARE), qce (SELECT), suc (LCU), yz8 (BE tests), oik (BS completion), rm8 (Chebyshev conversion research)

**Open issues (11):**
- a6r (QSP conventions) — DONE, not yet closed (needs commit)
- 80q (Jacobi-Anger) — DONE, not yet closed
- 6e3 (Weiss algorithm) — next
- mxr (RHW factorization) — next
- 27n (Phase extraction) — next
- 897 (qsvt! core circuit) — blocked on phase factors
- x3m (QSVT evolve! integration) — blocked on qsvt! circuit
- 2ra (QSVT phase factor tests) — blocked on phase factors
- 4wh (QSVT simulation tests) — blocked on evolve!
- 4x1 (QSVT DAG tests) — blocked on qsvt!
- gdh (BE algebra product) — deferred

**New test count this session:** 318 (48 + 24 + 215 + 31)

**New dependencies:** SpecialFunctions.jl (Bessel functions), FFTW.jl (FFT for BS algorithm)

### What the next session should do

1. **Implement Weiss algorithm** (Sturm.jl-6e3) — b → c_hat Fourier coefficients. For Hamiltonian simulation (real P), b = -iP is purely imaginary, simplifying to standard X-constrained QSP.
2. **Implement RHW factorization** (Sturm.jl-mxr) — c_hat → F_k via Toeplitz system solve. Start with naive O(n³), optimize to Half-Cholesky O(n²) later.
3. **Implement phase extraction** (Sturm.jl-27n) — F_k → (λ, φ_k, θ_k). For real P, F_k purely imaginary → ψ_k=0, massive simplification.
4. **Implement qsvt! core circuit** (Sturm.jl-897) — alternating processing operators + oracle calls.
5. **Implement evolve! integration** (Sturm.jl-x3m) — `evolve!(reg, H, t, QSVT(epsilon=1e-6))`.
6. **End-to-end test** — QSVT vs exact exp(-iHt) on 2-qubit Ising.

## 2026-04-08 — Session 8: PDE paper formalization (Childs et al. 2604.05098)

### Paper: Quantum Algorithms for Heterogeneous PDEs — Neutron Diffusion Eigenvalue Problem

Downloaded Childs, Johnston, Kiedrowski, Vempati, Yu (arXiv:2604.05098, April 8 2026) to `docs/literature/quantum_pde/2604.05098.pdf`. Andrew Childs et al. (UMD/Michigan) present a hybrid classical-quantum algorithm for solving the neutron diffusion k-eigenvalue PDE with piecewise-constant coefficients on [0,1]^3 using uniform FEM. Main result: O(z/ε poly(log 1/ε)) gate complexity where z = number of material regions, vs classical Ω(ε^{-3π/γ}) mesh elements.

### Algorithm pipeline (Figure 1)

1. **Classical**: Solve coarse-grid eigenvalue problem classically → coarse eigenvector
2. **Quantum state prep**: Interpolate coarse eigenvector onto fine grid, apply C^{1/2}
3. **Quantum core**: QPE on block-encoded H = C^{1/2}(L+A)^{-1}C^{1/2} using quantum preconditioning (BPX preconditioner F such that F(F^T L F)^+ F^T = L^{-1} with O(1) condition number)
4. **Measurement**: Read out eigenvalue k

Key insight: the fast-inversion preconditioning technique (TAWL21) rewrites (L+A)^{-1} as (I + L^{-1}A)^{-1}L^{-1}, and the BPX preconditioner (DP25) gives L^{-1} with O(1) effective condition number, bypassing the κ = Θ(1/h²) condition number of direct inversion.

### Formalization via `af` (adversarial proof framework)

Initialized `af` workspace at `docs/literature/quantum_pde/formalization/` with 26 nodes decomposing the algorithm into quantum subroutines mapped against Sturm.jl capabilities.

### Gap analysis: Sturm.jl subroutine readiness

**EXISTS (sufficient or needs minor extension):**
- QPE (`src/library/patterns.jl:136`) — needs extension for block-encoded operators
- Hamiltonian simulation (`src/simulation/`) — Trotter/qDRIFT work on PauliHamiltonian, not block-encoded matrices
- Controlled operations (`when()`) — sufficient as-is
- Quantum arithmetic (QInt add/sub/compare) — partial; missing modular arithmetic, integer division

**MISSING — must build (ordered by dependency):**
1. **Block Encoding Framework** (P0, ~1000 LOC) — types, sparse-access construction (GSLW19 Lemma 47-48), multiplication, linear combination, tensor product. Everything depends on this.
2. **QSVT** (P0, ~500 LOC) — matrix inversion (pseudoinverse) and square root via polynomial singular value transformation. Depends on block encoding.
3. **Grover-Rudolph State Preparation** (P1, ~200 LOC) — arbitrary amplitude state prep from classical vector. Needed for LCU coefficients and initial state.
4. **Sparse-Access Oracle Construction** (P1, ~400 LOC) — row/column/entry oracles for FEM matrices. Reversible classical computations with region identification.
5. **LCU Module** (P2, ~300 LOC) — linear combination of block-encoded unitaries via state-preparation pairs.

### Key physics/math from the paper

- **FEM matrices**: L (diffusion, 27-point stencil, κ=O(1/h²)), A (absorption, mass-type, κ=O(1)), C (fission, block-diagonal with zero+nonzero blocks, κ=O(1) on nonzero block). All sparse with ≤27 nonzeros/row.
- **BPX preconditioner**: F^d_L = Σ 2^{-l(2-d)/2} I''_{l→L} where I_{l→l+1} is multigrid interpolation. Spectral norm O((1/h)^{d/2}). Block encoding via O(L) interpolation operator BEs combined with LCU.
- **Convergence rate**: eigenvalue error |λ - λ_h| = O(h^{γ/π}) where γ = √(D_min/D_max). For checkerboard with D_max=100, γ/π ≈ 0.032 → classical needs N = Ω(ε^{-31}) mesh elements! Quantum: O(1/ε).
- **Interpolation operator**: 1D I_{l→l+1} is a (2n_{l+1}) × n_l matrix with entries {0, 1/2, 1}. Block encoding factor √2 per level, 2^{d(L-l)/2} for l→L.

### Gotchas

- **Block encodings are NOT unitaries.** A block encoding U is a unitary that encodes matrix A in its top-left block: A = α⟨0|^⊗q U |0⟩^⊗q. The Sturm.jl channel IR (DAG with non-unitary nodes) could represent block encodings naturally — the ancilla qubits are prepared in |0⟩ and post-selected.
- **QSVT is a meta-algorithm, not a single circuit.** It requires classical preprocessing (computing phase angles Φ from a target polynomial P) and then constructs a circuit of alternating signal/processing operators. The phase angle computation is itself nontrivial (optimization or Remez algorithm).
- **The paper uses GSLW19 extensively** — at least Lemmas 20, 22, 41, 47, 48 and Theorems 41, 56. Should download GSLW19 to `docs/literature/` if not already there.

---

## 2026-04-07 — Session 7: Simulation refactors + qDRIFT + Composite

### Simulation refactors (4 issues, all closed)

1. **Extracted `_pauli_exp!` (unchecked internal)** — Trotter step functions now call `_pauli_exp!` instead of `pauli_exp!`, eliminating 156,000 redundant `check_live!` calls per 20-qubit, 100-step Ising simulation. Public `pauli_exp!` validates then delegates.

2. **Zero-allocation QInt path** — All internal simulation functions (`_pauli_exp!`, `_trotter1_step!`, `_trotter2_step!`, `_suzuki_step!`, `_apply_formula!`) are now generic over qubits type. QInt overloads pass `_qbool_views(reg)` NTuple directly — no `collect()`, zero heap allocation.

3. **`Suzuki{K}` type parameter** — Order K is now a type parameter, not a runtime Int. `Val(K)` resolves at compile time, so the full Suzuki recursion tree is inlined. Convenience constructor `Suzuki(order=4, steps=1)` preserves API.

4. **P0: Controlled-pauli_exp! optimisation** — When `_pauli_exp!` detects a non-empty control stack (inside `when()` block), it temporarily clears the stack for basis changes and CNOT staircase, restoring it ONLY for the Rz pivot. Proof: V·controlled(Rz)·V† = controlled(V·Rz·V†) since V acts on target qubits only and V·V†=I. Reduces 7 controlled ops per term to 6 unconditional + 1 controlled-Rz. 32 new tests.

### qDRIFT implementation (Campbell 2019, arXiv:1811.08017)

- `QDrift(samples=N)` struct extending `AbstractStochasticAlgorithm`
- `qdrift_samples(H, t, ε)` computes N = ⌈2λ²t²/ε⌉ from Campbell's Theorem 1
- `_QDriftDist` precomputes cumulative distribution for importance sampling
- Algorithm: sample term j with probability |hⱼ|/λ, apply exp(-iλτ·sign(hⱼ)·Pⱼ)
- Implementation detail: `_pauli_exp!(qubits, term_j, λτ/|hⱼ|)` gives correct rotation because angle = 2·θ·hⱼ = 2·λτ·sign(hⱼ)
- Inherits controlled-evolve optimisation automatically
- **65 tests**: single-term exact (Z,X,Y, negative coeff), Ising ground truth (N=2–10 via eigendecomposition), O(λ²t²/N) scaling verification, qDRIFT vs Trotter2 cross-validation (N=2–24), Heisenberg model (N=2–14), controlled qDRIFT, DAG emit, OpenQASM export

### Composite Trotter+qDRIFT (Hagan & Wiebe 2023, arXiv:2206.06409)

- `Composite(steps=r, qdrift_samples=N_B, cutoff=χ, trotter_order=2)`
- Partitions H by coefficient magnitude: |hⱼ| ≥ cutoff → Trotter, < cutoff → qDRIFT
- Each composite step: one Trotter step on partition A, then N_B/r qDRIFT samples on partition B
- Degenerate cases handled: all terms in A → pure Trotter; all in B → pure qDRIFT
- Ref: Theorem 2.1 (Eq. 1) gate cost bound; Section 5 p.5 deterministic cutoff partitioning
- Tests: partitioning, degenerate cases, bimodal H ground truth, Ising N=4–24, order comparison, controlled, DAG emit

### Gotchas

- **Test helper redefinition warnings**: `_amp` and `_probs` helpers defined in `test_simulation.jl` were duplicated in `test_qdrift.jl`. Julia warns on method overwrite. Fix: removed duplicates, rely on inclusion order.
- **Julia background output buffering**: `Pkg.test()` output is fully buffered — no intermediate output visible until process completes. Makes progress monitoring of long test runs impossible via file watching.
- **`searchsortedfirst` for sampling**: Julia's `searchsortedfirst(cumprobs, r)` is O(log L) binary search — correct for importance sampling from cumulative distribution. No need for custom walker/alias method at current scale.

### Beads issues

- **Closed (6)**: d1r (extract _pauli_exp!), ooo (QBool alloc), r9j (_qbool_views), byx (Suzuki{K}), k3u (P0 controlled-evolve), wog (qDRIFT)
- **Created (4)**: 7m5 (Composite, claimed), 0gx (commutator error bounds), 6h0 (qSWIFT), k3u (controlled-evolve, closed)
- **Test count**: 10,626 → 10,7XX (pending composite test results)

## 2026-04-07 — Session 6: Simulation module idiomatic review

### Rigorous review of src/simulation/ (product formulas, Trotter algorithms)

Reviewed all 5 simulation files against CLAUDE.md rules and DSL idioms. Key findings:

**Passes (good):**
- All quantum operations use the 4 primitives only (Rule 11) ✓
- Physics grounding exemplary — full proofs for X→Z and Y→Z basis changes in pauli_exp.jl, Suzuki 1991 equation citations (Rule 3-4) ✓
- `Val{K}` dispatch for Suzuki recursion (compile-time inlining) — textbook Julia ✓
- `@enum PauliOp::UInt8`, `NTuple{N, PauliOp}` — zero-overhead, stack-allocated ✓
- DiffEq-style `evolve!(state, H, t, alg)` API — idiomatic Julia ✓
- Correctly uses `Ry(-π/2)` for X basis change, NOT `H!` (which has sign error) ✓

**Issues found (4 real, 1 retracted):**

1. **`Vector{QBool}` in public API breaks P5.** `evolve!(::Vector{QBool})` and `pauli_exp!(::Vector{QBool})` are exported. P5 says no qubits in user code. `QInt{W}` overloads should be the primary API. Vector overloads kept for TracingContext compatibility (trace() creates QBools, not QInts) but should be secondary.

2. **Redundant `check_live!` in inner loop.** `evolve!` validates at boundary. Then `pauli_exp!` validates again on every qubit, for every term, for every Trotter step. For 20-qubit Ising, 100 Trotter2 steps: 156,000 redundant checks. Fix: extract `_pauli_exp!` (unchecked internal) called from Trotter steps; keep `pauli_exp!` (checked) for standalone use.

3. **`collect(_qbool_views(reg))` allocates per call.** The QInt overloads heap-allocate a Vector{QBool} each time. For `evolve!` this happens once (fine), but standalone `pauli_exp!(::QInt)` in a loop allocates repeatedly. Fix: internal path receives pre-collected vector.

4. **`Suzuki.order` is runtime Int, dispatched via `Val(alg.order)`.** Constructs `Val` from runtime Int on every step. Should be `Suzuki{K}` with K as type parameter (like `QInt{W}`), so `Val(K)` resolves at compile time. Convenience constructor `Suzuki(order=4, steps=1)` preserves existing API.

5. **~~No when() awareness~~ — RETRACTED.** Initially claimed `when(ctrl) do; evolve!(...); end` wouldn't work. WRONG. `when()` pushes to `ctx.control_stack`, and ALL primitives (regardless of call depth) check that stack. Control propagates transparently through function calls. Verified by tracing the call path: `when()` → `evolve!` → `_apply_formula!` → `_trotter1_step!` → `pauli_exp!` → `q.θ += ...` → `apply_ry!(ctx, ...)` → sees `control_stack` → applies controlled-Ry. Correctness: control=|0⟩ → identity, control=|1⟩ → full exp(-iHt). This is a STRENGTH of the DSL design.

### P0: Controlled-pauli_exp! efficiency (user-flagged)

**The when()+evolve! correctness is fine, but the EFFICIENCY is not.** When wrapped in `when()`, ALL operations become controlled — including basis changes and CNOT staircase. But only the Rz pivot needs to be controlled:

- **when()-wrapped** (current): 7 controlled ops per term (controlled-Ry, Toffoli, controlled-Rz...)
- **Optimal**: 6 unconditional + 1 controlled-Rz per term

Each Toffoli decomposes into ~6 CX + ~15 single-qubit, so the overhead is significant for QPE/QSP/LCU where controlled-U is the inner loop.

**User flagged this as P0.** Needs: a `_controlled_pauli_exp!` that checks `ctx.control_stack` and applies controls only to the Rz pivot, leaving basis changes and CNOT staircase unconditional.

### Beads v1.0 upgrade — database recovery needed

- Upgraded bd from 0.62.0 to 1.0.0
- v1.0 switched from server-mode Dolt to embedded mode
- The old server-mode database (104 issues, 37 closed, 67 open) was NOT migrated
- `bd dolt pull` pulled schema from GitHub (`refs/dolt/data`) but issues table is empty
- The old issues were pushed to GitHub via `bd dolt push` in previous sessions but appear to be in a different Dolt branch/commit that the embedded mode doesn't see
- **Recovery needed**: the 104 historical issues need to be restored from the GitHub remote
- **DO NOT run `bd init --force`** — it wipes the database

### Open tasks for next session

1. **Recover beads issues** from GitHub remote (104 issues, refs/dolt/data)
2. **Create P0 issue**: controlled-pauli_exp! efficiency for QPE/QSP
3. **Refactor simulation module** (4 issues above):
   - Extract `_pauli_exp!` (unchecked) from `pauli_exp!` (checked)
   - `Suzuki` → `Suzuki{K}` type parameter
   - `evolve!(::QInt)` as primary API, no redundant delegation
   - Update Trotter step functions to call `_pauli_exp!`
4. **Implement controlled_pauli_exp!** — only control the Rz pivot
5. Remaining from Session 5: qDRIFT, QBool{C} parameterization, MCGS, Choi phase polys

## 2026-04-07 — Session 5: P8 Quantum promotion (numeric tower)

### Investigation: "classical by default, quantum on demand"
- **User proposed radical design change**: classical variables (Int64, Bool) should auto-promote to quantum when quantum operations are applied.
- **5 parallel investigation agents launched**: (1) codebase type system map, (2) simulation/noise/QECC impact, (3) Opus deep design analysis, (4) prior art research across 12 quantum languages, (5) Julia type system feasibility analysis.
- **Unanimous finding: lazy bit-level promotion is infeasible.** Three independent reasons:
  1. **Physics**: "partially quantum integer" doesn't exist. Carry propagation in addition makes quantum taint spread to ALL higher bits. Precise taint analysis is undecidable.
  2. **Julia**: Variables are bindings, not boxes. Can't mutate Int64 to QInt in place. All 6 approaches (wrapper, return-value, mutable container, macro, compiler plugin, two-phase) have fatal tradeoffs.
  3. **Language design**: Breaks P2 (type boundary = measurement) and P4 (when vs if). No prior quantum language does lazy promotion — only Qutes (2025) does auto-promotion, but its auto-measurement contradicts P2.
- **But the intuition was sound.** Reframed as Julia numeric tower convention: `Int + Float64 → Float64` becomes `Integer + QInt{W} → QInt{W}`. Initial construction is explicit (like `complex(1)`), then mixed operations auto-promote.

### P8 design decisions
- **NO `promote_rule`/`Base.convert`**. `convert(QInt{W}, ::Integer)` would need a quantum context (side-effect in convert is un-Julian). Instead: direct method overloads.
- **Context from quantum operand.** All mixed methods extract `ctx` from the quantum argument (`a.ctx`), never from `current_context()`. Makes the dependency explicit and traceable.
- **`mod` before constructor.** `_promote_to_qint` applies `mod(value, 1 << W)` before calling `QInt{W}(ctx, modded)`. The constructor's range check stays strict — only the promotion path wraps.
- **`xor(QBool, true)` = X gate, not CNOT.** When the classical operand is a known constant, no qubit allocation needed. `true` → `Ry(π)` (flip). `false` → identity. Strictly more efficient.
- **`xor(Bool, QBool)` allocates a new qubit.** Prepare fresh QBool from classical value, CNOT from quantum operand as control. The quantum operand stays live (control wire, consistent with QBool-QBool xor semantics).
- **Gates and when() do NOT participate.** `H!(true)` → MethodError. `when(true)` → MethodError. This preserves P4 and P5.
- **Cross-width QInt promotion deferred.** `QInt{4} + QInt{8}` not defined — would need choosing max(W,V) and zero-extending. Not needed for P8 (classical-quantum, not quantum-quantum width mismatch).

### Implementation
- Added P8 to PRD (Sturm-PRD.md) and CLAUDE.md
- Added `_promote_to_qint` helper to `src/types/qint.jl`
- Added 10 mixed-type method overloads: `+`, `-`, `<`, `==` × {QInt+Int, Int+QInt}
- Added 2 mixed-type xor methods: `xor(QBool, Bool)`, `xor(Bool, QBool)` to `src/types/qbool.jl`
- Added `test/test_promotion.jl`: 2,052 tests (exhaustive QInt{4} + deterministic + Bell-pair entanglement + negative tests)
- **10,626 total tests pass** (up from 8,530)

### Prior art survey highlights (from research agent)
- **12 quantum languages surveyed**: Silq, Qwerty, Tower, Twist, Quipper, Q#, Classiq, Yao.jl, Bloqade, Qrisp, Qunity, GUPPY
- **Only Qutes (PLanQC 2025) does auto-promotion** — but with auto-measurement (contradicts P2)
- **Silq**: quantum-by-default with `!T` classical restriction (opposite direction)
- **Qwerty**: explicit `.sign`/`.xor`/`.inplace` embedding (sophisticated but manual)
- **Qunity (POPL 2023)**: "classical IS quantum" via unified syntax — philosophically closest
- **"Quantum taint analysis" is a novel concept** — no prior art under any name

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
- ~~GQSP (Motlagh 2024) is the recommended classical preprocessor for QSP phase angles.~~ **DEPRECATED (Session 9, 2026-04-08)**: The canonical pipeline is now Berntson-Sünderhauf (CMP 2025, FFT completion) + Laneve (arXiv:2503.03026, NLFT factorization). See `docs/literature/quantum_simulation/qsp_qsvt/survey.md`.
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
