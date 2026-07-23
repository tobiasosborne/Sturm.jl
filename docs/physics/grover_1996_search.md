# Grover 1996 — quantum search / amplitude amplification

**Source (local):** `docs/physics/grover_1996_search.pdf` — L. K. Grover, *A fast
quantum mechanical algorithm for database search*, STOC 1996 (arXiv:quant-ph/9605043).
Rotation/optimal-iteration bound: Boyer–Brassard–Høyer–Tapp (BBHT), *Tight bounds
on quantum searching*, Fortsch. Phys. 46 (1998) 493 (arXiv:quant-ph/9605034) —
Grover's [BBHT96] reference for "the precise number of repetitions."

## What Sturm uses it for

`amplify` / `find` (`src/library/grover.jl`). The Grover iterate is two
reflections; both are built EXACTLY from the v2 surface (nested `when` +
`not!(dual(·))` for the multi-controlled Z, and the library H^⊗n materialization
`superpose!`/`interfere!` for the Walsh–Hadamard conjugation — the D4 answer).

## The three operations (paper §1.2, p.2)

1. The uniform superposition: `M` (the 1-bit Walsh–Hadamard `= (1/√2)[[1,1],[1,−1]]`)
   applied per bit; on `|0…0⟩` it produces amplitude `2^{−n/2}` in each of the `2^n`
   states. (Sturm: `superpose!`, the library H^⊗n materialization.)
2. The Walsh–Hadamard transform `W`, `W_{ij} = 2^{−n/2} (−1)^{i·j}` (bitwise dot
   product) — its own inverse.
3. The selective phase rotation: `diag(e^{iφ_1}, …)`; the marked states get their
   phase rotated by `π` (sign flip). (Sturm: the caller-supplied phase-marking body,
   or the Bennett-bridge kickback `b ⊻= oracle(f,x)` with `b = minus()`.)

## The diffusion transform (paper §3–4)

Zero-reflection (paper's `R`, §3):

    R_ii = +1 if i = 0,   R_ii = −1 if i ≠ 0,   R_ij = 0 (i ≠ j)          (R)

i.e. `R = 2|0⟩⟨0| − I` — flips the sign of every state EXCEPT `|0…0⟩`.

Diffusion (paper §3, "D = W R W"; equivalently eq (4.0) `D_ij = 2/N (i≠j)`,
`D_ii = −1 + 2/N`):

    D = W · R · W = 2|s⟩⟨s| − I,   |s⟩ = W|0⟩ (the uniform state)          (D)

Grover's own proof (§4): `D = −I + 2P`, `P_ij = 1/N` a projector (`P² = P`), so
`D² = I` (unitary) and `D` is the "inversion about average." **Sign note (Sturm
lowering):** the zero-reflection built from `X^⊗n · MCZ · X^⊗n` equals
`I − 2|0⟩⟨0| = −R`, so Sturm's materialized diffusion `H^⊗n (X^⊗n MCZ X^⊗n) H^⊗n`
equals `−D`. The extra global `−1` per iteration is unobservable and does not
change any Born probability (§6 / the M10 amplify test compares up-to-phase).

## Rotation picture and optimal iteration count (BBHT)

With `M` marked items out of `N = 2^n`, set `θ = arcsin(√(M/N))`. The Grover
iterate `G = D · O` (O = the marked-state sign flip `I − 2Σ_m|m⟩⟨m|`) acts on the
2-D span of {marked, unmarked} as a rotation by `2θ`. Starting from `|s⟩` (angle
`θ` from the unmarked axis), after `k` iterations the amplitude in the marked
subspace is

    ⟨marked | Gᵏ | s⟩  =  sin((2k+1)θ),   P_success(k) = sin²((2k+1)θ).     (rot)

The success probability is maximized near `(2k+1)θ = π/2`, i.e. the optimal integer
count is `k* = round(π/(4θ) − 1/2)`; for `M ≪ N`, `k* ≈ (π/4)√(N/M)` (the `O(√N)`
speedup). Paper §3(iii): for the single-solution case one iteration already gives
`P ≥ 1/2` at `N = 4` (`θ = π/6`, `sin²(π/2) = 1` exactly at `k=1`).

## The M10 pinned closed-form checks

- `n = 2, M = 1`: `θ = arcsin(1/2) = π/6`, `k* = round(π/(4·π/6) − 1/2) =
  round(1) = 1`, `P_success = sin²(3·π/6) = sin²(π/2) = 1` — **exact** (deterministic
  Grover at N=4).
- `n = 3, M = 1`: `θ = arcsin(1/√8) ≈ 0.36136`, `k* = round(π/(4θ) − 1/2) =
  round(1.674) = 2`, `P_success = sin²(5θ) = sin²(1.8068) ≈ 0.9453`.
- `n = 4, M = 1`: `θ = arcsin(1/4) ≈ 0.25268`, `k* = round(2.608) = 3`,
  `P_success = sin²(7θ) ≈ 0.96131`.
- `n = 3, M = 2`: `θ = arcsin(1/2) = π/6`, `k* = round(1) = 1`,
  `P_success = sin²(π/2) = 1` — exact.

## Why the trace-free phase (paper §3, last note)

Grover stresses the phase rotation "would do it in a way so that no trace of the
state is left … so that paths leading to the same final state … could interfere.
The implementation does *not* involve a classical measurement." This is exactly
Sturm's coherent `when` + `not!(dual(·))` (a unitary phase kick, no measurement) —
NOT a `cases` branch. Measurement inside the amplification loop would collapse the
interference (§3.5 guardrail 1 forbids it under control anyway).
