# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M10 (bead Sturm.jl-8fo5): the Grover
# library HOFs `amplify` / `find`, plus `interfere!` (the closing Walsh–Hadamard
# interference, the DJ/BV twin of `superpose!`). These are LIBRARY code (PRD-v2
# §5): they may touch kernel process values, but every user-facing example stays
# surface-only (no gate, no rotation angle in any docstring).
#
# ── THE D5 PORT (session-92, resolved) ──────────────────────────────────────
# v0.1's `_multi_controlled_z!` (a Toffoli-cascade with a borrowed ancilla) and
# `_cz!` DISSOLVE into nested `when` + `not!(dual(·))`: an (n−1)-ctrl Z is
#   when(q₁) do
#     when(q₂) do
#       …
#         when(q_{n-1}) do not!(dual(q_n)) end
#       …
#     end
#   end
# (each `when` on its own line: the one-line spelling `when(a) do when(b) do …`
# MIS-parses — the inner do-block becomes the outer lambda's parameter tuple)
# — EXACT, because CZ's angle is π and the kernel `ctrl` is closed (`ctrl^k(Z)`).
# No cascade, no borrowed ancilla, no folklore. The diffusion's Walsh–Hadamard
# conjugation is the D4 materialization: the kernel value `H` wrapped by a library
# name — here reusing the shipped `superpose!`/`interfere!` (CLAUDE.md #13), never
# re-emitting H by hand.
#
# ── THE TWO REFLECTIONS (docs/physics/grover_1996_search.md) ────────────────
# Grover iterate G = D · O. O (the oracle) flips the sign of the marked states;
# D (diffusion, eq (D)) = W R W = 2|s⟩⟨s| − I, with W = H^⊗n the Walsh–Hadamard
# and R (eq (R)) the zero-reflection 2|0⟩⟨0| − I. Sturm builds R from
# `X^⊗n · MCZ · X^⊗n` (= I − 2|0⟩⟨0| = −R): the global −1 per iteration is
# unobservable (does not change any Born probability — the amplify test compares
# up to phase). Success amplitude after k iterations from |s⟩ is sin((2k+1)θ),
# θ = arcsin(√(M/N)) (eq (rot), BBHT), maximized at k* = round(π/(4θ) − 1/2).

# ---------------------------------------------------------------------------
# interfere! — the closing Walsh–Hadamard (the DJ/BV twin of superpose!)
# ---------------------------------------------------------------------------

"""
    interfere!(x::QInt{W}) -> x

Recombine amplitudes by the transversal Walsh–Hadamard `H^⊗W`, in place, returning
the same handle — the CLOSING interference step of Deutsch–Jozsa / Bernstein–
Vazirani (the twin of `superpose!`, which OPENS from `|0…0⟩`). Physically the same
kernel materialization `H^⊗W` (D4; `superpose!`, surface/arithmetic.jl) — `H` is
its own inverse — so `interfere!` delegates to it rather than re-emitting the
gate (CLAUDE.md #13); the distinct name marks the distinct INTENT (open vs close).
The D5 note "DJ's trailing interfere!+measure collapses into a dual-basis read"
refers to the per-wire `(ℤ₂)^W` Hadamard basis (`Bool(dual(x[i]))` per wire), NOT
the register QFT `Int(dual(x))` (which is the ℤ_{2^W} character group — a different
group; test_m7_bennett.jl's D2 negative control shows the register dual does not
recover the BV string). docs/physics/grover_1996_search.md (op 2, the transform W).
"""
interfere!(x::QInt{W}) where {W} = superpose!(x)

# ---------------------------------------------------------------------------
# The exact multi-ctrl Z (MCZ) — nested `when` + `not!(dual(·))` (no cascade)
# ---------------------------------------------------------------------------

"""
    _mcz_all_ones!(qs::AbstractVector{<:AbstractQubit})

The (|qs|−1)-ctrl Z (MCZ) on `qs` — flips the sign of the all-`|1⟩` component and
leaves every other basis state fixed (`diag(1,…,1,−1)`), EXACTLY. Built as nested
`when` bottoming out in `not!(dual(·))` (= Z): `when(q₁) … when(q_{n-1}) do
not!(dual(q_n)) end …`. Streaming nested `when` gives a flat `ctrl^{n-1}(Z)` (the
§4.2 homomorphism), so there is no Toffoli cascade and no borrowed ancilla — the
D5 dissolution of v0.1's `_multi_controlled_z!`. `public` (reused by `find`'s
diffusion and by callers building their own phase markers).
docs/physics/grover_1996_search.md (op 3 / the R reflection).
"""
function _mcz_all_ones!(qs::AbstractVector{<:AbstractQubit})
    n = length(qs)
    n ≥ 1 || error("_mcz_all_ones!: need ≥1 wire")
    if n == 1
        not!(dual(qs[1]))                 # ctrl^0(Z) = Z on the lone wire
    else
        when(qs[1]) do
            _mcz_all_ones!(@view qs[2:end])
        end
    end
    return nothing
end

# ---------------------------------------------------------------------------
# The diffusion operator D = 2|s⟩⟨s| − I (materialized, up to global phase)
# ---------------------------------------------------------------------------

"""
    _grover_diffuse!(x::QInt{W}) -> x

Grover diffusion `2|s⟩⟨s| − I` (inversion about the uniform mean, `|s⟩ = H^⊗W|0⟩`),
up to a global phase — materialized as `W · (X^⊗W · MCZ · X^⊗W) · W` (eq (D)):
the closing/opening `interfere!` (= `H^⊗W`, the D4 kernel-value wrap), the bit-flip
`x ⊻= (2^W−1)` (`X^⊗W`, mapping `|0…0⟩ ↔ |1…1⟩`), and the exact `_mcz_all_ones!`
zero-reflection. The `X^⊗W MCZ X^⊗W = I − 2|0⟩⟨0|` differs from Grover's `R` by a
global `−1`, harmless (Born-invariant). Uses only shipped surface/library verbs.
docs/physics/grover_1996_search.md (D = W R W).
"""
function _grover_diffuse!(x::QInt{W}) where {W}
    allones = (1 << W) - 1
    interfere!(x)                              # W = H^⊗W
    xor(x, allones)                            # X^⊗W  (x ⊻= 1…1)
    _mcz_all_ones!([x[i] for i in 1:W])        # MCZ (nested when + not!(dual))
    xor(x, allones)                            # X^⊗W
    interfere!(x)                              # W = H^⊗W
    return x
end

# ---------------------------------------------------------------------------
# amplify — the Grover amplitude-amplification core (caller-supplied marker)
# ---------------------------------------------------------------------------

"""
    amplify(mark!, x::QInt{W}; iterations::Integer) -> x

Grover amplitude amplification about the uniform superposition: apply the iterate
`diffusion ∘ mark!` `iterations` times, in place, returning `x`. `mark!(x)` is a
CALLER-SUPPLIED phase-marking body (a `do` block) that flips the sign of the states
to amplify — e.g. a coherent `when(x[i]) do not!(dual(x[j])) end` phase kick, or the
Bennett-bridge kickback `b ⊻= oracle(f, x)` with `b = minus()` (see `find`). The
body must be a UNITARY phase op — NO measurement inside the loop (it would collapse
the interference; guardrail 1 forbids a cast under control anyway).

`x` must already hold the state to amplify about — for textbook Grover,
`superpose!(x)` first (the diffusion reflects about `|s⟩ = H^⊗W|0⟩`). After the
optimal `k* = round(π/(4θ) − 1/2)` iterations (`θ = arcsin(√(M/2^W))`, `M` = number
of marked states) the marked-subspace weight is `sin²((2k*+1)θ)` (eq (rot)).
`find` wraps this with an oracle marker + optimal count + measurement.
docs/physics/grover_1996_search.md.

```julia
# amplify a QInt about its marked state, then read it out
x = QInt{3}(0); superpose!(x)
amplify(x; iterations = 2) do reg
    when(reg[1]) do          # phase-flip |111⟩ — each `when` on its own
        when(reg[2]) do      # line: the one-line nesting `do when(...) do`
            not!(dual(reg[3]))   # mis-parses (inner block becomes the outer
        end                  # lambda's parameter tuple)
    end
end
```
"""
function amplify(mark!, x::QInt{W}; iterations::Integer) where {W}
    iterations ≥ 0 || throw(DomainError(iterations,
        "amplify: iteration count must be ≥ 0 (got $iterations)."))
    _here(x)                                   # fail-fast: bind/verify x's context
    for _ in 1:iterations
        mark!(x)                               # O: caller phase-flips the marked states
        _grover_diffuse!(x)                    # D: inversion about the mean
    end
    return x
end

# ---------------------------------------------------------------------------
# find — Grover search for a predicate over W-bit inputs (Bennett marker)
# ---------------------------------------------------------------------------

"""
    grover_iterations(M::Integer, W::Integer) -> Int

The Grover-optimal iteration count `k* = round(π/(4θ) − 1/2)`, `θ = arcsin(√(M/2^W))`
(eq (rot), BBHT), clamped to `≥ 0`. `M` = number of marked states, `2^W` = search
space. For `M ≪ 2^W`, `k* ≈ (π/4)√(2^W/M)` (the O(√N) speedup). `public`.
docs/physics/grover_1996_search.md.
"""
function grover_iterations(M::Integer, W::Integer)
    N = 1 << W
    (1 ≤ M ≤ N) || throw(DomainError(M,
        "grover_iterations: need 1 ≤ M ≤ 2^$W = $N marked states (got $M)."))
    θ = asin(sqrt(M / N))
    return max(0, round(Int, (π / 4) / θ - 0.5))
end

"""
    _phase_mark_oracle!(x::QInt{W}, f) -> x

The Bennett-bridge phase marker (the DJ/§7.4 kickback): allocate a `|−⟩` ancilla,
`b ⊻= oracle(f, x)` kicks the phase `(−1)^{f(x)}` onto `x` (`f(x) ∈ {0,1}`), then
the ancilla is traced at region exit — clean, because kickback leaves `b` in `|−⟩`
DISENTANGLED from `x` (input preservation `(★)`; no backaction on trace, §3.9).
`x` stays live. Runs in a fresh `region` so the ancilla wire is bounded per mark.
docs/physics/bennett_1973_logical_reversibility.md.
"""
function _phase_mark_oracle!(x::QInt{W}, f) where {W}
    region() do
        b = minus()                            # |−⟩ = (|0⟩−|1⟩)/√2
        b ⊻= oracle(f, x)                      # (−1)^{f(x)} phase kick; x preserved
        nothing                                # b traced at region exit (disentangled)
    end
    return x
end

"""
    find(p, ::Val{W}; nsolutions = nothing) -> Int

Grover search: return a `W`-bit integer `v ∈ 0:2^W−1` with `p(v) == true`, found by
amplitude amplification of the predicate `p` and a single measurement. Runs in a
fresh `region` under the active context (`eager(cap) do … end`, as `shor_order`).
Marking is the Bennett-bridge kickback `b ⊻= oracle(v -> p(v) ? 1 : 0, x)`
(requires `using Bennett`). The iteration count is `grover_iterations(M, W)` with
`M = nsolutions` (supply it when known); if omitted, `M` is counted classically over
`0:2^W−1` — a convenience for correctness demos, NOT part of the quantum speedup
(real use supplies `M`, or estimates it via `phase_estimate`/quantum counting).

Runtime success is probabilistic (`sin²((2k*+1)θ)`, eq (rot)); the return is a
genuine measurement, so it may (rarely) be a non-solution — the caller verifies
`p` (the standard Grover amplify-verify-repeat wrapper is a follow-on). For the
deterministic small cases (`N=4, M=1`; `N=8, M=2`) `sin²((2k*+1)θ) = 1`.
docs/physics/grover_1996_search.md.

```julia
# find a 3-bit v with v*v ≡ 1 (mod 8) — the caller writes an ordinary predicate
r = eager(24) do ctx
    find(v -> mod(v*v, 8) == 1, Val(3))
end
```
"""
function find(p, ::Val{W}; nsolutions = nothing) where {W}
    N = 1 << W
    M = nsolutions === nothing ? count(p, 0:(N - 1)) : Int(nsolutions)
    (1 ≤ M ≤ N) || throw(DomainError(M,
        "find: the predicate marks $M of $N states — need 1 ≤ M ≤ $N (unsatisfiable " *
        "or all-true predicate has no Grover amplification)."))
    k = grover_iterations(M, W)
    f = v -> (p(v) ? 1 : 0)
    return region() do
        x = QInt{W}(0)
        superpose!(x)                          # |s⟩ = H^⊗W|0⟩
        amplify(x; iterations = k) do reg
            _phase_mark_oracle!(reg, f)        # O: (−1)^{p(v)} via the Bennett bridge
        end
        Int(x)                                 # measure (region traces nothing else)
    end
end
