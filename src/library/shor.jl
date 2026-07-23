# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M9 (bead Sturm.jl-8oo9, design
# `docs/design/m9-addq-inplace-perm-design.md` §4, closes F21/F22): `shor_order` —
# the order-finding capstone. ONE quantum experiment (coherent modular
# multiplication conditioned on a uniform phase register, then a Fourier sample)
# wrapped in a BOUNDED classical driver with exact `BigInt` continued fractions,
# `lcm` accumulation, `powermod` verification, and exact prime-strip minimization.
#
# THE QUANTUM KERNEL (`_shor_phase_sample`, PRD-v2 §7.7 verbatim) lives in a fresh
# `region` so the work register `y` is TRACED at exit — that trace is *why* order
# finding works (the Stinespring boundary, §3.9). The control schedule is
# `2W:-1:1`: wire `2W` is the LSB carrying `a^{2⁰}` (M6 wire-1=MSB pin, F21 fix).
# `mulmod!(y, c)` is the full-space in-place permutation; every `c` is a power of
# the coprime base, so its `gcd(c,N)=1` precondition holds.
#
# THE DRIVER (`shor_order`, PRD-v2 §7.7 verbatim) never returns `nothing`, a raw
# denominator, or an unverified LCM: every successful return is `powermod`-verified
# and prime-strip-minimized, or it throws — `NonCoprimeBaseError` (the base shares a
# factor with N, already found) or `OrderFindingFailure` (the retry limit).
#
# GROUNDING (CLAUDE.md #4/#5): docs/physics/shor_order_finding.md — the phase-
# sample structure (Eq 5.1–5.4), the continued-fraction bound (Eq 5.13 / design
# eq 5), the divisor-denominator issue (eq 6) and LCM/`powermod` protocol, the
# order-1 guard, and the per-sample success bound `≥ φ(r)/3r` that justifies the
# §9.6 statistical threshold.

# --- Exceptions (loud, never `nothing`) -------------------------------------

"""
    NonCoprimeBaseError(a, N, factor)

`gcd(a, N) = factor ≠ 1` — the base shares a factor with the modulus, so `factor`
is a NONTRIVIAL FACTOR of `N`, found classically by Euclid (Shor's reduction, p.15:
"choose a random `x (mod n)` … `gcd(x,n) ≠ 1` returns the factor directly"). There
is no order to find; the caller already has what factoring wanted. `public`.
"""
struct NonCoprimeBaseError <: Exception
    a::Int
    N::Int
    factor::Int
end
Base.showerror(io::IO, e::NonCoprimeBaseError) = print(io,
    "NonCoprimeBaseError: gcd($(e.a), $(e.N)) = $(e.factor) ≠ 1 — the base shares a " *
    "factor with the modulus, so $(e.factor) is a nontrivial factor of $(e.N) (found " *
    "classically). No order to find (Shor 1995, p.15 reduction).")

"""
    OrderFindingFailure(a, N, max_samples)

The bounded driver drew `max_samples` fresh phase samples without accumulating a
`powermod`-verified order (all uninformative, or the candidate LCMs never verified,
or only contaminated histories). Loud and terminal — the driver never falls back to
`nothing`, a raw denominator, or an unverified LCM. Runtime *success* is
probabilistic (per-sample `≥ φ(r)/3r`, docs/physics/shor_order_finding.md); the
returned value, when it returns, is always exact. `public`.
"""
struct OrderFindingFailure <: Exception
    a::Int
    N::Int
    max_samples::Int
end
Base.showerror(io::IO, e::OrderFindingFailure) = print(io,
    "OrderFindingFailure: no `powermod`-verified order for a=$(e.a) (mod $(e.N)) after " *
    "$(e.max_samples) fresh phase samples. Increase `max_samples`, or the sampling was " *
    "unlucky (per-sample success ≥ φ(r)/3r; re-run). Never returns nothing/raw denom.")

# --- The one quantum sample (fresh region per attempt; PRD-v2 §7.7 verbatim) -

"""
    _shor_phase_sample(a₀, ::Val{N}, ::Val{W}) -> BigInt

One order-finding phase sample (docs/physics/shor_order_finding.md, Eq 5.1–5.4):
a uniform phase register `k` (`2W` wires), a work register `y ≡ 1 (mod N)`, the
conditional modular-multiplication ladder (`when(k[j]) do mulmod!(y, c) end` with
`c = a₀^{2^{2W-j}}`), and a Fourier sample `BigInt(dual(k))`. Lives in a fresh
`region` so `y` is traced at exit (that trace is *why* order finding works, §3.9).
The `2W:-1:1` schedule places `a^{2⁰}` on the LSB wire `2W` (M6 pin, F21). This
body is normative — PRD-v2 §7.7.
"""
function _shor_phase_sample(a₀, ::Val{N}, ::Val{W}) where {N,W}
    region() do
        k = QInt{2W}(0); superpose!(k)     # phase register, uniform over 0:2^{2W}-1
        y = QMod{N}(1)                      # work register ≡ 1 (mod N)
        c = a₀
        for j in 2W:-1:1                    # LSB-upward: wire j weighs 2^(2W-j);
            when(k[j]) do                   # wire 2W ↦ a^(2^0), wire 1 ↦ top (F21 fix)
                mulmod!(y, c)               # in-place y ← c·y (mod N), bijective
            end
            c = Int(powermod(big(c), 2, big(N)))
        end
        return BigInt(dual(k))              # Fourier-sample; y traced at region exit
    end
end

# --- Exact continued-fraction denominator (design §4.3, eq 5) ---------------

"""
    _cf_denominator(z, Q, N) -> Union{Int,Nothing}

The largest continued-fraction denominator `q < N` of the exact rational `z/Q`
(`Q = 2^{2W}`) satisfying the integer form of the source bound (design eq 5;
Shor Eq 5.13):

    2N²·|z·q − p·Q|  ≤  Q·q .

Returns that `q`, or `nothing` if none exists or the only candidate is `q = 1`
(the uninformative `z = 0` sample — it no longer masquerades as order 1). Exact
`BigInt` arithmetic throughout — never `Float64` division, never `rationalize`.
For an ideal phase `s/r` this returns `r / gcd(s, r)`, a DIVISOR of the true order
(eq 6), which is why LCM accumulation is needed.
docs/physics/shor_order_finding.md.
"""
function _cf_denominator(z::Integer, Q::Integer, N::Integer)
    zb = big(z); Qb = big(Q); Nb = big(N)
    a = zb; b = Qb
    p0, p1 = big(0), big(1)      # convergent numerators (h_{-2}, h_{-1})
    q0, q1 = big(1), big(0)      # convergent denominators (k_{-2}, k_{-1})
    best = nothing
    while b != 0
        h = a ÷ b
        a, b = b, a - h * b
        p0, p1 = p1, h * p1 + p0
        q0, q1 = q1, h * q1 + q0
        if q1 ≥ Nb
            break                # denominators are increasing; past N is useless
        end
        if q1 > 1 && 2 * Nb * Nb * abs(zb * q1 - p1 * Qb) ≤ Qb * q1
            best = q1            # keep the largest satisfying denom (< N)
        end
    end
    return best === nothing ? nothing : Int(best)
end

# --- Exact prime-strip order minimization (design §1.Δ7) --------------------

"""
    _distinct_primes(n) -> Vector{BigInt}

The distinct prime factors of `n` by trial division (`n < N` for the capstone, so
trial division suffices; a scalable factoring primitive is a later, semantics-
preserving swap — design open item 4).
"""
function _distinct_primes(n::Integer)
    m = big(n)
    ps = BigInt[]
    d = big(2)
    while d * d ≤ m
        if m % d == 0
            push!(ps, d)
            while m % d == 0
                m ÷= d
            end
        end
        d += 1
    end
    m > 1 && push!(ps, m)
    return ps
end

"""
    _minimize_order(a₀, N, L) -> BigInt

Prime-strip descent (design §1.Δ7): given a verified multiple `L` of the true order
`r` (`a₀^L ≡ 1 (mod N)`), strip each distinct prime `p | L` maximally while
`a₀^{L/p} ≡ 1 (mod N)` still holds. The result is exactly `r`: if it were a proper
multiple, `L/r > 1` would have a prime factor `p` with `L/p` still a multiple of
`r`, so the strip loop would not have terminated (contradiction). `powermod`
throughout — never form `a₀^L`.
"""
function _minimize_order(a₀::Integer, N::Integer, L::Integer)
    Lb = big(L)
    ab = big(a₀)
    Nb = big(N)
    for p in _distinct_primes(Lb)
        while Lb % p == 0 && powermod(ab, Lb ÷ p, Nb) == 1
            Lb ÷= p
        end
    end
    return Lb
end

# --- The bounded classical driver (PRD-v2 §7.7 verbatim) --------------------

"""
    shor_order(a, ::Val{N}; max_samples = 32) -> Int

Multiplicative order of `a` modulo `N`: the quantum kernel `_shor_phase_sample`
(coherent modular multiplication + Fourier sampling) wrapped in a bounded classical
driver — exact `BigInt` continued fractions, `lcm` accumulation, `powermod`
verification, prime-strip minimization. Every successful return is verified and
minimal.

Returns the exact multiplicative order after verification and minimization, or
throws `OrderFindingFailure` after `max_samples`; throws `NonCoprimeBaseError`
(carrying the factor) if `gcd(a, N) ≠ 1`. `W = ndigits(N-1; base=2)` is derived, so
a caller cannot supply an inconsistent `(N, W)`; `N` is static in `QMod{N,W,C}`
(§3.1). The driver is `BigInt`-clean end to end (`Q = big(1) << (2W)`, never `4^W`
in `Int`). docs/physics/shor_order_finding.md. This body is normative — PRD-v2 §7.7.
"""
function shor_order(a::Integer, ::Val{N}; max_samples::Int = 32) where {N}
    N ≥ 2           || throw(DomainError(N, "modulus must be ≥ 2"))
    max_samples ≥ 1 || throw(DomainError(max_samples, "need ≥ 1 sample"))
    W  = ndigits(N - 1; base = 2)           # width derived from N, never passed in
    a₀ = mod(a, N)
    g  = gcd(a₀, N)
    g == 1 || throw(NonCoprimeBaseError(a, N, g))   # gcd(a,N)≠1 ⇒ a factor is in hand
    a₀ == 1 && return 1                              # order-1 guard (no false failure)

    Q = big(1) << (2W)                      # exact 2^{2W}; never 4^W in Int, never Float
    L = big(1)                              # lcm accumulator of verified denominators
    for _ in 1:max_samples
        z = _shor_phase_sample(a₀, Val(N), Val(W))   # one fresh experiment
        q = _cf_denominator(z, Q, N)                 # largest CF denom, eq (5); skips q=1
        q === nothing && continue                    # z = 0 / uninformative sample
        L = lcm(L, q)
        L ≥ N && (L = q)                             # contaminated history → reset (§4.4)
        if powermod(big(a₀), L, big(N)) == 1         # verified: the true order divides L
            return Int(_minimize_order(a₀, N, L))    # exact prime-strip minimization
        end
    end
    throw(OrderFindingFailure(a₀, N, max_samples))   # loud, never nothing / raw denom
end
