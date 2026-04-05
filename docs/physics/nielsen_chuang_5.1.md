# Quantum Fourier Transform

Source: Nielsen & Chuang, *Quantum Computation and Quantum Information*,
10th Anniversary Edition, Cambridge University Press, 2010.

Section 5.1, "The quantum Fourier transform", pp. 217-221.

## Definition (Eq. 5.2)

The QFT maps computational basis states:

  |j⟩ → (1/√N) Σ_{k=0}^{N-1} e^{2πijk/N} |k⟩

where N = 2^n.

## Product representation (Eq. 5.4)

  QFT|j₁j₂...jₙ⟩ = (1/√2ⁿ) ⊗_{l=1}^{n} (|0⟩ + e^{2πi·0.j_{n-l+1}...jₙ}|1⟩)

This leads directly to the circuit: for each qubit (MSB first),
apply H then controlled-R_k gates from subsequent qubits.

## Circuit (Fig. 5.1)

For qubit j (1-indexed from MSB):
1. Apply H to qubit j
2. For each k from j+1 to n:
   Apply controlled-R_{k-j+1} with qubit k as control, j as target
   where R_m = diag(1, e^{2πi/2^m})

3. After all qubits processed, apply SWAP to reverse bit order.

## Gate R_m in terms of primitives

R_m = Rz(2π/2^m) up to global phase.
In Sturm.jl: `q.φ += 2π/2^m` or equivalently `q.φ += π/2^{m-1}`.
Controlled-R_m: `when(ctrl) do q.φ += π/2^{m-1} end`.

Note: R_m as Rz gives CRz, not CP. These differ by a phase on the
control qubit: CP(θ) = Rz(θ/2)⊗I · CRz(θ). For QFT measurement
statistics, CRz and CP are equivalent (differ by local phases).

## Inverse QFT

Apply all gates in reverse order with negated rotation angles.
H is self-inverse. Controlled-R_m becomes controlled-R_m† = Rz(-2π/2^m).

## Implementation

Used in `src/library/patterns.jl`:
- `superpose!(x::QInt{W})` — forward QFT
- `interfere!(x::QInt{W})` — inverse QFT
