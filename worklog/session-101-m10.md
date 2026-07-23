# Session 101 — 2026-07-23 — M10 library HOFs (bead Sturm.jl-8fo5)

Implementer session (orchestrator reviews the diff; not committed by me). M10:
`amplify`/`find` (Grover), `phase_estimate` (QPE), `evolve!` (Trotter), `interfere!`.

## What shipped

- **src/library/grover.jl** — `amplify(mark!, x; iterations)` (amplitude
  amplification, caller-supplied phase-marking body), `find(p, ::Val{W}; nsolutions)`
  (Bennett-bridge kickback marker + optimal count + measurement), `interfere!`,
  `_mcz_all_ones!` (the exact (n−1)-ctrl Z as nested `when` + `not!(dual(·))` — the
  D5 dissolution of v0.1's `_multi_controlled_z!` cascade, NO ancilla, NO folklore),
  `_grover_diffuse!` (D = W·(X^⊗W MCZ X^⊗W)·W via `interfere!` = the D4 H^⊗W
  materialization), `grover_iterations`, `_phase_mark_oracle!`.
- **src/library/qpe.jl** — `phase_estimate(U::U2, ψ; nbits)`: the §7.7
  `_shor_phase_sample` structure with the conditioned op generalized from `mulmod!`
  to a caller U2 (squared in the kernel, `U ← U∘U`); `Int(dual(k))` Fourier readout.
- **src/library/evolve.jl** — `evolve!(x, H, t; steps, order)`: first/second-order
  (Strang) Trotter over weighted Pauli words; `PauliTerm`, `_pauli_exp!` (N&C §4.7.3
  single-word exponential: basis-change to Z, CNOT parity ladder, `Rz(2θ)`, uncompute).
- **docs/physics/** — `grover_1996_search.{pdf,md}` (Grover STOC96 + BBHT rotation
  bound; D = W R W eq, sin²((2k+1)θ)), `childs_2019_trotter_error.{pdf,md}`
  (arXiv:1912.08854; commutator-scaling E1/E2 bounds + the Pauli-word exp construction).
- **test/test_m10_library.jl** wired into runtests.jl.

## D5-port fidelity (session-92 §Round 2 / D4/D5)

- Grover MCZ = nested `when` + `not!(dual(·))` — EXACTLY as the notes say (CZ angle
  π, ctrl closed). No cascade, no borrowed ancilla. Seals fine (the nested-`when`
  bodies are NoAncilla; the kernel ctrl^k(Z) AND-ladder scratch is freed inside
  `apply!`/ad.jl, not surfaced to the when-frame). **No seal/guardrail finding** —
  the M8 seal held naturally for every Grover body.
- D4 diffusion materialization = the kernel value `H` wrapped by a library name:
  reused the shipped `superpose!`/`interfere!` (CLAUDE.md #13), NOT `within`/a fresh
  UnitaryBlock — `within` is for ancilla-bearing compute/uncompute, and both the H^⊗W
  and the nested-`when` MCZ are ancilla-free, so `within` was not the natural carrier
  here. (Documented as a deliberate choice.)
- `interfere!` = `superpose!` (H^⊗W is its own inverse) — delegates rather than
  re-emitting. **Corrected the D5 note's imprecision**: DJ's trailing interfere is the
  per-wire (ℤ₂)^W Hadamard, NOT the register QFT `Int(dual(x))` (different group; the
  register dual does not recover the BV string — test_m7 D2 negative control). The
  note conflated them; the code and docstring pin the per-wire reading.
- QPE shares the §7.7 structure but shor.jl is PRD-normative-VERBATIM, so I did NOT
  refactor it — `phase_estimate` is a sibling, not a common-lowering extraction
  (the two conditioned ops — `mulmod!` Perm vs a caller U2 — are genuinely different
  process-value families; nothing duplicated).

## Gotchas / findings

- **QPE readout sign**: the register dual is the FORWARD QFT `F`, whose peak sits at
  `y = N − a` for dyadic `φ = a/N` (F reads the negative frequency). So
  `phase_estimate` negates: `n = (N − Int(dual(k))) mod N`. Shor is insensitive
  (`(N−a)/N = (r−s)/r`, same CF denominator) — which is why §7.7's `BigInt(dual(k))`
  needs no negation. Verified exact on φ ∈ {3/8,5/16,1/4,7/8,11/16,0}.
- **`\bcontrolled\b` boot lint** bans the whole word "controlled" outside
  src/kernel|orkan (matches hyphenated "multi-controlled", "ctrl-power" etc., but NOT
  "uncontrolled" nor underscored `_multi_controlled_z!`). Rephrased all library-file
  docstrings/comments to "ctrl"/"conditional"/"multi-ctrl". (Existing library files
  carefully avoid the word — I hadn't noticed until the lint caught my first draft.)
- **Bennett can't compile `count_ones`** (shift-out-of-range) — used `v & 1` (LSB) as
  the balanced DJ predicate instead.
- **Capacity budget (Bennett `find`)**: probe found min wires — W=2 `v==2` → 14;
  W=3 single-solution → 20; a COMPOUND predicate (`v==3||v==5`) blows past 24 (the OR
  widens the oracle). So the M2 case is tested via the caller marker (amplify), and
  the ≥1000-trial statistical Grover test uses the CHEAP caller-marker path
  (`eager(14)`, no Bennett), not `find`. `eager(cap)` = 2^cap statevector — an
  eager(30) in my first draft would have been 16 GB; caught before the full run.

## Closed-form values the tests pin

- Grover amplitude (marked-state Born weight, statevector read, atol 1e-8):
  W=2/M=1/k=1 → **1.0** (exact); W=3/M=1/k=2 → sin²(5·asin√⅛) = **0.9453125**;
  W=4/M=1/k=3 → sin²(7·asin¼) ≈ **0.9613189**; W=3/M=2/k=1 → **1.0**.
- `grover_iterations`: (1,2)=1, (1,3)=2, (1,4)=3, (2,3)=1.
- Grover channel-level (W=2, m=2): realized amplify(k=1) ≈ analytic D·O up to phase;
  diffusion alone ≈ 2|s⟩⟨s|−I up to phase.
- Grover pipeline statistical (amplify+measure, W=3 M=1, 1000 seeded): rate 0.95 vs
  sin²((2k+1)θ)=0.9453 (probe); test asserts within ±0.05 both sides.
- QPE dyadic exact: φ=a/2^m ⇒ n=a for (a,m) ∈ {(3,3),(5,4),(1,2),(7,3),(11,4),(0,3)}.
  QPE φ=1/3 nbits=5 statistical (1000 seeded): P(nearest=11) ≈ 0.69 (≥0.40 asserted),
  within ±1 LSB ≈ 0.90 (≥0.80 asserted) — N&C §5.2.1 single-shot bound 4/π².
- Trotter `evolve!` (H = Z⊗Z + ½X⊗I, t=1): first-order err 0.00403 at r=100 ≤ the
  eq-E1 bound (t²/2r)·‖[H₁,H₂]‖ = 0.005 (‖[ZZ,½XI]‖=1); order-1 scaling ratio
  (r:50→100) ≈ 2.0; order-2 ratio (r:20→40) ≈ 4.0 — the O(t²/r) / O(t³/r²) signatures.
  3-qubit mixed-word (ZZI+IXX+YIY+III, t=0.5, order-2 r=80): ‖U−expm‖ ≈ 1e-5 ≤ 1e-4.

## Open questions

- Controlled `evolve!` (under `when`) is a follow-on — `_pauli_exp!` uses uncontrolled
  `apply!` throughout (the basis-changes would need to stay uncontrolled with only the
  core `Rz` controlled, à la `add!`'s F/D_a split). Not required by M10.
- `find`'s classical `count(p, …)` fallback for the optimal iteration count is an
  O(2^W) convenience (documented); real use supplies `nsolutions` or estimates M via
  quantum counting (a `phase_estimate`-on-Grover follow-on).
- QSVT/QDrift deliberately deferred to M12 (per bead/PRD).
