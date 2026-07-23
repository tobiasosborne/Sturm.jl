# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M10 (bead Sturm.jl-8fo5): the
# `phase_estimate` library HOF — the §7.7 `_shor_phase_sample` structure
# generalized off the modular-multiplication special case.
#
# ── THE SHARED STRUCTURE (with shor.jl §7.7) ────────────────────────────────
# Both are the SAME quantum experiment: a uniform phase register `k` (m wires,
# `superpose!`); a conditional-power ladder `when(k[j]) do «apply U^{2^p} to the
# eigenstate» end` with the power doubling as `j` runs LSB→MSB; and a Fourier
# readout `Int(dual(k))`. In Shor the conditioned op is the registered action
# `mulmod!(y, c)` (the process value squared classically, `c ← c² mod N`); here
# it is a caller-supplied single-qubit unitary `U` (the process value squared in
# the kernel, `U ← U ∘ U`). shor.jl is PRD-§7.7-normative and stays VERBATIM;
# `phase_estimate` is its sibling, not a refactor of it (CLAUDE.md #13: the
# structure is shared in spirit; the two conditioned ops are genuinely different
# process-value families, so no common lowering is duplicated).
#
# ── WHY Int(dual(k)) READS THE PHASE (and the negation) ─────────────────────
# With U|ψ⟩ = e^{2πiφ}|ψ⟩, the ctrl-power ladder writes the phase register to
# Σ_x e^{2πi φ x}|x⟩ (phase kickback: ctrl-U^{2^p} kicks e^{2πi φ 2^p} onto the
# |1⟩ branch of the wire carrying register-weight 2^p). The register dual is the
# FORWARD QFT `F` (`F[y,x] = ω^{+xy}/√N`, kernel/qft.jl), whose peak sits at
# `y = N·(1−φ) mod N = N − a` for a dyadic `φ = a/N` — F reads the NEGATIVE
# frequency. So `phase_estimate` negates: `n = (N − Int(dual(k))) mod N = a`. (Shor
# is insensitive to this — `(N−a)/N = 1 − s/r = (r−s)/r` has the SAME continued-
# fraction denominator `r` — which is why §7.7's `BigInt(dual(k))` needs no negation;
# the M9 statistical suite validates that.) docs/physics/shor_order_finding.md
# (Eq 5.1–5.4); Nielsen–Chuang §5.2 (phase estimation, the inverse-QFT readout).

"""
    phase_estimate(U::U2, ψ::AbstractQubit; nbits::Integer) -> Int

Quantum phase estimation of a single-qubit unitary `U` on its eigenstate `ψ`
(`U|ψ⟩ = e^{2πiφ}|ψ⟩`): returns the integer numerator `n ∈ 0:2^{nbits}−1` of the
`nbits`-bit dyadic estimate `φ̂ = n / 2^{nbits}` of the eigenphase `φ ∈ [0,1)`.

The §7.7 `_shor_phase_sample` structure with the conditioned op generalized from
`mulmod!` to the caller's `U`: a fresh `region` holds a uniform `nbits`-wire phase
register `k` (`superpose!`), the eigenstate `ψ`, the conditional-power ladder
`when(k[j]) do «U^{2^p}» end` (LSB wire `nbits` ↦ `U^{2^0}`, squaring up to MSB wire
`1` ↦ `U^{2^{nbits-1}}` — the F21 endianness pin), and the Fourier readout
`Int(dual(k))`. `ψ` is left in its eigenstate (a global phase kicked onto `k`) and
traced at region exit — clean, since an eigenstate stays DISENTANGLED from `k`
(§3.9, no backaction). `ψ` must be prepared by the caller and stay live across the
call.

If `φ = a/2^{nbits}` is dyadic, `n = a` EXACTLY (deterministic). Otherwise `n` is
the best `nbits`-bit estimate, correct to `±1` LSB with probability `≥ 4/π² ≈ 0.405`
in a single shot and `→ 1` as `nbits` grows past the needed precision (Nielsen–
Chuang §5.2.1). Runs under the active context (`eager(cap) do … end`).
docs/physics/shor_order_finding.md.

```julia
# estimate the eigenphase of a phase gate on |1⟩ (its e^{iθ} eigenvector),
# reported as an nbits-bit dyadic numerator
n = eager(6) do ctx
    ψ = QBool(true)                       # |1⟩, the phase-gate eigenstate
    phase_estimate(Sturm.P(2π * 3 / 8), ψ; nbits = 3)   # φ = 3/8 ⇒ n = 3 exactly
end
```
"""
function phase_estimate(U::U2, ψ::AbstractQubit; nbits::Integer)
    nbits ≥ 1 || throw(DomainError(nbits, "phase_estimate: nbits must be ≥ 1."))
    _here(ψ)                                          # fail-fast: ψ's context is active
    return region() do
        k = QInt{nbits}(0)
        superpose!(k)                                # uniform phase register
        Upow = U                                     # U^{2^0}
        for j in nbits:-1:1                           # LSB wire nbits ↦ U^{2^0} (F21 pin)
            when(k[j]) do
                _act!(_here(ψ), Upow, (ψ.wire,))     # ctrl-U^{2^{nbits-j}} (phase kickback)
            end
            Upow = Upow ∘ Upow                        # square: U^{2^{p+1}} = (U^{2^p})²
        end
        raw = Int(dual(k))                           # register dual = FORWARD QFT F
        return mod((1 << nbits) - raw, 1 << nbits)    # F reads the negative frequency
    end                                              #   (peak at N−a); negate to get a
end
