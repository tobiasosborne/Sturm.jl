# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M10 (bead Sturm.jl-8fo5): `evolve!` —
# Trotter-first Hamiltonian simulation of `e^{−iHt}` for a Hamiltonian given as a
# sum of weighted Pauli words. QSVT is the M12 horizon (through the reimport gates)
# and is NOT built here.
#
# LIBRARY code (PRD-v2 §5): `evolve!` is where generators live. It touches kernel
# process values (Rz, H, S, ctrl(X), gphase) — that is sanctioned for a library
# HOF — but has NO surface spelling for the angles; a user writes `evolve!(x, H, t)`
# with `H` a list of `(coefficient, pauli-word)` pairs, never a rotation.
#
# ── THE DECOMPOSITION (docs/physics/childs_2019_trotter_error.md) ────────────
# H = Σ_k c_k P_k (each P_k a Hermitian Pauli word, c_k real). First-order (S1):
#   S₁(τ) = Π_k exp(−i c_k P_k τ),   e^{−iHt} ≈ S₁(t/r)^r,   err = O(t²/r).
# Second-order symmetric Strang (S2):
#   S₂(τ) = Π_{k=1..Γ} exp(−i c_k P_k τ/2) · Π_{k=Γ..1} exp(−i c_k P_k τ/2),
#   e^{−iHt} ≈ S₂(t/r)^r,   err = O(t³/r²).
# Each factor exp(−i c P τ) is the standard Pauli-word exponential (N&C §4.7.3):
# rotate each letter into the Z basis, a CNOT ladder onto one parity wire, a single
# exp(−iθZ)=Rz(2θ) there, then uncompute. exp(−iθZ)=Rz(2θ) is EXACT in Sturm's U(2)
# convention (Rz carries no global phase), so no phase-quotient slip.

# ---------------------------------------------------------------------------
# The Hamiltonian representation
# ---------------------------------------------------------------------------

"A single weighted Pauli word `(coeff, word)` where `word` is a length-W string over
`\"IXYZ\"` (char 1 = wire 1 = MSB). The public Hamiltonian type is `Vector{PauliTerm}`
or any iterable of `(::Real, ::AbstractString)` pairs — `evolve!` normalizes both."
struct PauliTerm
    coeff::Float64
    word::String
end
PauliTerm(c::Real, w::AbstractString) = PauliTerm(Float64(c), String(w))

# Normalize a user Hamiltonian (Vector of PauliTerm, or of (coeff, word) pairs) to
# Vector{PauliTerm}, checking every word has length W over the alphabet IXYZ.
function _normalize_hamiltonian(H, W::Integer)
    terms = PauliTerm[]
    for t in H
        pt = t isa PauliTerm ? t : PauliTerm(t[1], t[2])
        length(pt.word) == W || throw(DimensionMismatch(
            "evolve!: Pauli word \"$(pt.word)\" has length $(length(pt.word)) ≠ register " *
            "width $W."))
        all(c -> c in ('I', 'X', 'Y', 'Z'), pt.word) || throw(ArgumentError(
            "evolve!: Pauli word \"$(pt.word)\" has a letter outside \"IXYZ\"."))
        push!(terms, pt)
    end
    return terms
end

# ---------------------------------------------------------------------------
# The single Pauli-word exponential exp(−i c P τ)  (N&C §4.7.3)
# ---------------------------------------------------------------------------

# Basis change bringing Pauli letter `P` into the Z basis: B with B P B† = Z, applied
# as the pair (pre, post) of U2 values (pre acts first, post = B† undoes). For X:
# B = H. For Y: B = H S† (so (HS†) Y (HS†)† = Z), pre-sequence S† then H.
# Returns nothing for I/Z (no change) via the caller's letter switch.

"""
    _pauli_exp!(ctx, x::QInt{W}, term::PauliTerm, τ::Real)

Apply `exp(−i · term.coeff · P · τ)` (P = the Pauli word) in place on `x`'s wires
(N&C §4.7.3). Pure-identity word ⇒ the global phase `gphase(−cτ)`. Otherwise: rotate
each non-`I` letter into the Z basis (`X`: `H`; `Y`: `S†` then `H`), CNOT-ladder the
active wires' parity onto the LAST active wire, `Rz(2cτ) = exp(−icτ Z)` there,
uncompute the ladder and the basis changes. All uncontrolled `apply!` (an
`evolve!` is a top-level generator; a ctrl-`evolve!` is a follow-on).
docs/physics/childs_2019_trotter_error.md (single-word exponential).
"""
function _pauli_exp!(ctx::AbstractContext, x::QInt{W}, term::PauliTerm, τ::Real) where {W}
    θ = term.coeff * τ
    active = [j for j in 1:W if term.word[j] != 'I']    # wires the word acts on
    if isempty(active)
        apply!(ctx, gphase(-θ), (x.wires[1],))          # exp(−icτ I) = e^{−icτ} global
        return nothing
    end
    # 1. basis-change each active letter into Z (pre): X→H, Y→(S† then H)
    for j in active
        c = term.word[j]
        if c == 'X'
            apply!(ctx, H, (x.wires[j],))
        elseif c == 'Y'
            apply!(ctx, adjoint(S), (x.wires[j],))
            apply!(ctx, H, (x.wires[j],))
        end                                             # 'Z': no basis change
    end
    # 2. CNOT ladder: fold parity of the active wires onto the last active wire
    tgt = last(active)
    for i in 1:(length(active) - 1)
        apply!(ctx, ctrl(X), (x.wires[active[i]], x.wires[active[i + 1]]))
    end
    # 3. the single Z-rotation on the parity wire — exp(−iθ Z) = Rz(2θ), exact
    apply!(ctx, Rz(2θ), (x.wires[tgt],))
    # 4. uncompute the ladder (reverse order)
    for i in (length(active) - 1):-1:1
        apply!(ctx, ctrl(X), (x.wires[active[i]], x.wires[active[i + 1]]))
    end
    # 5. uncompute the basis changes (post = B†): X→H, Y→(H then S)
    for j in active
        c = term.word[j]
        if c == 'X'
            apply!(ctx, H, (x.wires[j],))
        elseif c == 'Y'
            apply!(ctx, H, (x.wires[j],))
            apply!(ctx, S, (x.wires[j],))
        end
    end
    return nothing
end

# ---------------------------------------------------------------------------
# evolve! — first/second-order Trotter of e^{−iHt}
# ---------------------------------------------------------------------------

"""
    evolve!(x::QInt{W}, H, t::Real; steps::Integer = 1, order::Integer = 2) -> x

Simulate `e^{−iHt}` in place on the register `x`, by an `order`-th (1 or 2) Trotter
product formula with `steps` (`r`) steps (`docs/physics/childs_2019_trotter_error.md`).
`H` is a sum of weighted Pauli words: any iterable of `(coefficient::Real,
word::AbstractString)` pairs (or `PauliTerm`s), each `word` a length-`W` string over
`\"IXYZ\"` (char 1 = wire 1 = MSB). Returns the same handle (in-place, D12).

First order (`order = 1`): `S₁(t/r) = Π_k exp(−i c_k P_k t/r)`, error `O(t²/r)` —
`(t²/2r) Σ_{i<j}‖[H_i,H_j]‖` (eq E1). Second order (`order = 2`, default): the
symmetric Strang sweep (forward half-steps then reverse), error `O(t³/r²)` (eq E2).
Increase `steps` to reach a target accuracy; the error scales as the Trotter bound,
NOT tuned to a test. QSVT/QDrift are the M12 horizon.

```julia
# evolve a 2-qubit register under H = Z⊗Z + ½ X⊗I for time t, second order
x = QInt{2}(0)
evolve!(x, [(1.0, "ZZ"), (0.5, "XI")], 1.0; steps = 40)
```
"""
function evolve!(x::QInt{W}, H, t::Real; steps::Integer = 1, order::Integer = 2) where {W}
    steps ≥ 1 || throw(DomainError(steps, "evolve!: steps must be ≥ 1."))
    (order == 1 || order == 2) || throw(DomainError(order,
        "evolve!: only first- and second-order Trotter (order ∈ {1,2}); QSVT is M12."))
    ctx = _here(x)
    terms = _normalize_hamiltonian(H, W)
    τ = t / steps
    if order == 1
        for _ in 1:steps
            for term in terms
                _pauli_exp!(ctx, x, term, τ)
            end
        end
    else                                                # symmetric Strang (S2)
        for _ in 1:steps
            for term in terms
                _pauli_exp!(ctx, x, term, τ / 2)
            end
            for term in Iterators.reverse(terms)
                _pauli_exp!(ctx, x, term, τ / 2)
            end
        end
    end
    return x
end
