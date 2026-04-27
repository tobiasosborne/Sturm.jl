# Phase Estimation

Source: Nielsen & Chuang, *Quantum Computation and Quantum Information*,
10th Anniversary Edition, Cambridge University Press, 2010.

Section 5.2, "Phase estimation", pp. 221-225. Source djvu in
`docs/physics/Nielsen and Chuang 2000.djvu`.

> **Note:** The local source is in djvu format; this distillation was
> written from the canonical textbook description of phase estimation
> AND from the verified Sturm.jl implementation in
> `src/library/patterns.jl::phase_estimate`. The N&C djvu remains the
> authority — please cross-check this file against the source if
> editing.

## Setting

Suppose `U` is a unitary with eigenvector `|u⟩` and eigenvalue
`exp(2πi·φ)` for some unknown `φ ∈ [0, 1)`. Phase estimation is the
algorithm that produces a `t`-bit approximation of `φ`. The accuracy
depends on `t`: with `t = n + ⌈log(2 + 1/(2ε))⌉` bits, phase estimation
yields `n` correct bits with probability at least `1 - ε`.

## Circuit (Fig. 5.2 in N&C)

The algorithm uses two registers:

  - First register: `t` qubits, initialised to `|0⟩^⊗t`.
  - Second register: enough qubits to hold `|u⟩`, initialised to `|u⟩`.

Three stages:

  1. **Hadamard the first register.** Apply `H^⊗t` to get
     `(1/√(2^t)) · Σ_{k=0}^{2^t-1} |k⟩|u⟩`.

  2. **Apply controlled-U^{2^j}.** For `j = 0..t-1`, apply
     controlled-`U^{2^j}` with qubit `j` of the first register as
     control and the second register as target. Because `|u⟩` is an
     eigenvector, `U^{2^j}|u⟩ = exp(2πi·φ·2^j)|u⟩`, so the phase kicks
     back to the control:
     ```
     (1/√(2^t)) · Σ_{k=0}^{2^t-1} exp(2πi·φ·k) |k⟩ |u⟩
     ```
     This is exactly the Fourier transform of a `t`-bit register
     holding the value `2^t · φ` (up to rounding) — see Eq. 5.2 in
     §5.1.

  3. **Apply inverse QFT** to the first register. The inverse QFT maps
     the phase-encoded state to the computational basis:
     ```
     |2^t · φ̃⟩ |u⟩
     ```
     where `φ̃` is the closest `t`-bit fraction to `φ`.

  4. **Measure the first register.** The outcome `m` is interpreted as
     `φ̃ = m / 2^t`.

## Accuracy (Theorem 5.1.4 in N&C)

For phase `φ` and `t = n + ⌈log(2 + 1/(2ε))⌉` qubits:

  Pr[ |φ̃ - φ| ≤ 2^{-n} ] ≥ 1 - ε

When `2^t · φ` is exactly an integer (i.e. `φ` is exactly representable
in `t` bits), the algorithm returns the exact answer with probability 1.
Otherwise the probability concentrates on the two nearest representable
values, with the bulk on the closer one.

## Sturm.jl mapping

Sturm.jl's `phase_estimate(U, |u⟩, ::Val{t})` in
`src/library/patterns.jl` implements this circuit verbatim:

  1. Allocate `t` qubits, prepare each in `|+⟩` via `q.θ += π/2` (=
     `Ry(π/2)|0⟩` = `H|0⟩` up to global phase). This is the explicit
     QBool primitive form of `H^⊗t`.

  2. For each control bit `j`, the user-supplied `U` is applied
     `2^j` times with `when(ctrl_bit_j) do U(target) end`. The
     paper's "controlled-U^{2^j}" is realised by repeated controlled-U
     application — clean and avoids hand-rolling controlled powers.

  3. `interfere!` (Sturm's name for inverse QFT, see
     `nielsen_chuang_5.1.md`) is applied to the first register.

  4. Each first-register qubit is cast to `Bool` via the P2 cast
     `Bool(q)` and the bits are assembled little-endian into the
     returned `Int`. The result is `m`, where `φ̃ = m / 2^t`.

The single-qubit `Z` eigenvector test in patterns docstring example —
`phase_estimate(Z!, QBool(1), Val(3))` returns `4`, giving
`φ̃ = 4/8 = 0.5` — matches the expected eigenvalue `Z|1⟩ = -|1⟩ =
exp(2πi · 0.5)|1⟩`.

## Complexity

  - Gate count: `O(t² + t · cost(U))` (the `t²` is from the inverse
    QFT; the `t · cost(U)` is from `t` controlled powers up to `U^{2^{t-1}}`,
    each a separate controlled-U if implemented naively, but
    asymptotically dominated by the largest power).
  - Qubit count: `t + |u⟩` register width.
  - Measurement shots: 1 (single shot suffices for the high-probability
    accuracy bound; multiple shots refine confidence).

## Use in Shor (forward reference to §5.3)

Phase estimation on the modular-exponentiation operator
`U_a |x⟩ = |ax mod N⟩` (for an eigenvector that is a sum of `N`-th
roots of unity supported on the order subgroup) yields the order `r`
of `a` modulo `N` with high probability. See `nielsen_chuang_5.3.md`.
