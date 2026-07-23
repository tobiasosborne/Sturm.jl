# Childs–Su–Tran–Wiebe–Zhu 2019 — Theory of Trotter Error

**Source (local):** `docs/physics/childs_2019_trotter_error.pdf` — A. M. Childs,
Y. Su, M. C. Tran, N. Wiebe, S. Zhu, *A Theory of Trotter Error* (arXiv:1912.08854;
published as *Theory of Trotter Error with Commutator Scaling*, Phys. Rev. X 11,
011020 (2021)). Foundational product-formula references: Lloyd, *Universal quantum
simulators*, Science 273 (1996) 1073; Suzuki, *General theory of fractal path
integrals…*, J. Math. Phys. 32 (1991) 400; Nielsen & Chuang §4.7.3 (the single
Pauli-word exponential circuit).

## What Sturm uses it for

`evolve!(x, H, t)` (`src/library/evolve.jl`) — first- and second-order Trotter
simulation of `e^{−iHt}` for a Hamiltonian `H = Σ_k c_k P_k` given as weighted
Pauli words. The abstract states the paper "reproduces known tight bounds for
first- and second-order formulas" with COMMUTATOR SCALING — this is the bound the
M10 `evolve!` test asserts against (not a tuned-to-pass tolerance).

## The product formulas

For `H = Σ_{k=1}^{Γ} H_k` (each `H_k = c_k P_k`, a Hermitian Pauli word):

First-order Lie–Trotter, `r` steps of size `t/r`:

    S₁(t/r) = Π_{k=1}^{Γ} exp(−i H_k t/r),      U₁ = S₁(t/r)^r                (S1)

Second-order (Strang / symmetric Suzuki), `r` steps:

    S₂(t/r) = Π_{k=1}^{Γ} exp(−i H_k t/2r) · Π_{k=Γ}^{1} exp(−i H_k t/2r)      (S2)
    U₂ = S₂(t/r)^r

## The commutator-scaling error bounds (the assertable tolerances)

Additive spectral-norm error `‖U − e^{−iHt}‖`. Childs et al.'s commutator-scaling
theorem specializes, for these fixed-order formulas, to the classical tight bounds:

First order:

    ‖S₁(t/r)^r − e^{−iHt}‖  ≤  (t²/2r) · Σ_{i<j} ‖[H_i, H_j]‖                 (E1)

Second order:

    ‖S₂(t/r)^r − e^{−iHt}‖  ≤  (t³/r²) · ( (1/12) Σ_{i<j≤k or…} ‖[H_i,[H_i,H_j]]‖
                                          + (1/24) Σ ‖[H_j,[H_i,H_j]]‖ )       (E2)

The load-bearing physics (grounding, not a fitted number) is the SCALING:
first-order error is `O(t²/r)`, second-order `O(t³/r²)`. Halving the step (doubling
`r`) therefore reduces the first-order error by ≈2× and the second-order error by
≈4×. The M10 test asserts BOTH: (a) `‖U_Trotter − expm(−iHt)‖ ≤` the eq-(E1)/(E2)
right-hand side computed from the actual commutators of the test Hamiltonian, and
(b) the order-scaling ratio under `r → 2r` (≈2 for order 1, ≈4 for order 2) — the
signature of the correct Trotter order, immune to the exact prefactor.

## Single Pauli-word exponential (Nielsen–Chuang §4.7.3)

Each factor `exp(−i c_k P_k τ)` is realized by the standard construction: for each
qubit conjugate its Pauli letter into the `Z` basis (`X`: `H`; `Y`: `H S†` before /
`S H` after, since `(HS†) Y (HS†)† = Z`; `Z`: identity), a CNOT ladder onto one
"parity" wire, a single `Rz(2 c_k τ) = exp(−i c_k τ Z)` on it, then the ladder and
basis changes uncomputed. A pure-identity term contributes the global phase
`exp(−i c_k τ) = gphase(−c_k τ)`. `Rz` carries no global phase in Sturm's U(2)
convention (`Rz(γ) = diag(e^{−iγ/2}, e^{iγ/2})`, `kernel/constants.jl`), so
`exp(−iθZ) = Rz(2θ)` is EXACT (no phase-quotient slip).
