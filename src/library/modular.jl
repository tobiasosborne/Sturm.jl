# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M9 (bead Sturm.jl-8oo9, design
# `docs/design/m9-addq-inplace-perm-design.md` §2, closes F7): `mulmod!(y, c)` —
# the FULL-SPACE modular multiplication permutation, and its registered structural
# proof `FullSpaceMulProof{N,W}`.
#
# THE FIX (F7). The M9-as-first-written `mulmod!` = Bennett-compiled `v -> (c*v)%N`
# is NOT a permutation of the physical Hilbert basis: for N=15 in 4 wires, basis
# states 0 and 15 both map to 0 — many-to-one, not unitary. The full-space
# permutation (design eq 1) repairs it:
#
#                ⎧ c̄·v mod N ,   0 ≤ v < N
#   π_{c̄,N}(v) = ⎨                                                       (1)
#                ⎩ v         ,   N ≤ v < 2^W       (identity on the padded tail)
#
# with `c̄ = mod(c, N)`. Precondition `gcd(c̄,N)=1` (a unique inverse `d` exists) and
# `N ≥ 2`; a non-unit multiplier is a LOUD `DomainError` naming `c/N/gcd`, thrown
# BEFORE any allocation, because NO tail convention repairs a non-injective map.
#
# BIJECTIVITY (design §2). With `gcd(c̄,N)=1`, `d = c̄⁻¹ mod N` gives
# `π_d ∘ π_{c̄} = id` on `A = {0..N-1}` and both are the identity on `T = {N..2^W-1}`,
# so `π_{c̄}` is a two-sided-invertible permutation of the WHOLE physical space —
# `P†P = I`. The N=15 collision is removed: `0 ↦ 0`, padded `15 ↦ 15`.
#
# OVERFLOW-FREE CLASSICAL CALLABLE (design §2, both proposals). The Bennett
# function must NOT be `(c*v)%N` at `bit_width=W`: Bennett narrows arithmetic mod
# `2^W`, so `c*v` can wrap before `%N`. The registered callable is a fixed-`W`
# overflow-free double-and-add using the modular-add primitive (design eq 2):
#
#                 ⎧ a - (N-b) ,   a ≥ N-b
#   a ⊕_N b   =   ⎨                                                       (2)
#                 ⎩ a + b     ,   a < N-b       (second branch proves a+b < N)
#
# so every intermediate stays `< N ≤ 2^W`. The N=2^W (power-of-two, tail-empty)
# case is native multiply mod 2^W — handled by a separate Julia-level closure so
# Bennett never sees a `N ≡ 0 (mod 2^W)` literal.
#
# Physics/spec grounding: docs/physics/shor_order_finding.md ("Order finding is
# generic in f" — mulmod! is the efficiently-iterable permutation); PRD-v2 §3.4
# (registered in-place `Perm` action). The in-place compiler contract:
# `src/bennett/inplace.jl`.

# --- The registered structural proof (Tier P; closed set) -------------------

"""
    FullSpaceMulProof{N,W}(c̄, d)

The registered, compiler-owned structural proof (design §3.3, Tier P) that the
full-space multiply-by-`c̄` and multiply-by-`d` maps (eq 1) are two-sided inverses
on `S_W`, valid at ANY width: it stores `c̄` and `d = c̄⁻¹ mod N` and validates
`c̄·d ≡ 1 (mod N)` with widened arithmetic. Inverse agreement (3-inv) then rests on
eq (1)'s algebra (`π_d ∘ π_{c̄} = id`), and faithful compilation on the shipped M7
Bennett contract. It is NOT attachable to an arbitrary closure through a keyword —
that is what "registered" means. `public`, not exported.
"""
struct FullSpaceMulProof{N,W} <: AbstractInplaceProof
    c::Int
    d::Int
    function FullSpaceMulProof{N,W}(c::Integer, d::Integer) where {N,W}
        _check_qmod_params(N, W)
        cc = Int(mod(c, N))
        dd = Int(mod(d, N))
        mod(big(cc) * big(dd), N) == 1 || throw(ArgumentError(
            "FullSpaceMulProof{$N,$W}: c=$c and d=$d are not inverse mod $N " *
            "(c̄·d ≡ $(mod(big(cc)*big(dd), N)) ≠ 1)."))
        return new{N,W}(cc, dd)
    end
end

# Tier-P validation hook (dispatch on the registered subtype; inplace.jl fallback
# rejects everything else). Re-checks the number-theoretic witness at the width.
function _validate_inplace_proof(p::FullSpaceMulProof{N,W}, ::Val{Wv}) where {N,W,Wv}
    W == Wv || throw(ArgumentError(
        "FullSpaceMulProof{$N,$W} supplied for a width-$Wv verification — width mismatch."))
    mod(big(p.c) * big(p.d), N) == 1 || throw(ArgumentError(
        "FullSpaceMulProof{$N,$W}: c̄·d ≢ 1 (mod $N)."))
    return nothing
end

# --- The overflow-free double-and-add callable (fed to Bennett) -------------

"""
    _mulmod_callable(mult, N, W) -> Function

An ordinary Julia function `v ↦ π_{mult,N}(v)` (eq 1) that Bennett compiles into a
clean reversible accumulate oracle: `ifelse(v < N, (mult·v) % N, v)` — the modular
product on the logical block `v < N`, the identity on the padded tail (the `ifelse`
selects the tail branch WITHOUT reading uninitialised state, so it survives
Bennett's IR extraction).

OVERFLOW DISCIPLINE (design §2, adapted to Bennett v0.5's real capabilities —
see the deviation note in the file header / worklog): the design's ideal is a
fixed-`W` double-and-add so no intermediate reaches `2^W`. Bennett v0.5's LLVM IR
extractor, however, (a) rejects the loop/branch-carried double-and-add with an
`UndefValue` phi and (b) cannot narrow `*`/`%` to a non-nibble `bit_width`
(`W ≥ 5`). So the compilable form is `(mult·v) % N`, and overflow-freedom is
secured differently but EXACTLY: the Bennett COVERING type has `≥ 2W` bits for the
supported range `W ≤ 4` (`UInt8`; `(N-1)² ≤ 15² = 225 < 256`), so `mult·v` never
wraps before `% N`, and — the load-bearing guarantee — Tier-E verification replays
the compiled `Perm` against `_ideal_mulmod_perm` on ALL `2^W` inputs, so ANY silent
overflow is a LOUD `InverseContractError` / self-check failure, never a wrong ship.
`W ≥ 5` (`N ≥ 17`) fails LOUD at Bennett compile (no silent narrowing). The
overflow hazard is thus independent of the inverse-pair hazard and is caught by the
same exhaustive replay (design §9.1 tripwire).
"""
function _mulmod_callable(mult::Integer, N::Integer, W::Integer)
    m = Int(mod(mult, N))
    NN = Int(N)
    return let m = m, NN = NN
        v -> ifelse(v < oftype(v, NN), (oftype(v, m) * v) % oftype(v, NN), v)
    end
end

"""
    _ideal_mulmod_perm(N, W, c̄) -> Vector{Int}

The IDEAL full-space permutation vector (eq 1) on `0:2^W-1`, computed classically
with `BigInt` (no overflow): `out[v+1] = c̄·v mod N` for `v < N`, else `v`. The
Choi / permutation-matrix ground truth for the bijectivity tests (design §9.1/§9.4).
`public`.
"""
function _ideal_mulmod_perm(N::Integer, W::Integer, c̄::Integer)
    cc = mod(c̄, N)
    return Int[v < N ? Int(mod(big(cc) * v, N)) : v for v in 0:((1 << W) - 1)]
end

# --- Compilation cache (immutable value keys; design §9.6) ------------------

# Keyed by IMMUTABLE VALUE (N, W, c̄) — never `objectid(f)` — so a repeated
# `mulmod!(y, c)` (the 1000-trial Shor suite) reuses one compiled artifact and the
# test measures sampling, not compiler setup. The quantum state is recreated per call.
const _MULMOD_CACHE = Dict{Tuple{Int,Int,Int},CompiledInplacePerm}()

"""
    _get_mulmod_perm(::Val{N}, ::Val{W}, c̄) -> CompiledInplacePerm{W}

Compile (or fetch the cached) in-place `Perm` for `π_{c̄,N}` (eq 1): build the
overflow-free multiply-by-`c̄` and multiply-by-`d = c̄⁻¹` callables, verify the
inverse pair, and compose them into one frozen `Perm`. Cached by the immutable
value key `(N, W, c̄)`.
"""
function _get_mulmod_perm(::Val{N}, ::Val{W}, c̄::Int) where {N,W}
    key = (Int(N), Int(W), c̄)
    haskey(_MULMOD_CACHE, key) && return _MULMOD_CACHE[key]::CompiledInplacePerm{W}
    d = invmod(c̄, N)
    f = _mulmod_callable(c̄, N, W)
    finv = _mulmod_callable(d, N, W)
    proof = FullSpaceMulProof{N,W}(c̄, d)
    pair = verify_inverse_pair(f, finv, Val(W); proof = proof)
    compiled = compile_inplace_perm(pair)
    _MULMOD_CACHE[key] = compiled
    return compiled
end

# --- The surface action `mulmod!` -------------------------------------------

"""
    mulmod!(y::QMod{N,W,C}, c::Integer) -> y

The registered in-place action `|v⟩ ↦ |π_{c̄,N}(v)⟩` (eq 1) — the full-space
modular multiplication permutation `c̄·v mod N` for `v < N`, identity on the padded
tail `N ≤ v < 2^W` (`c̄ = mod(c, N)`). Preconditions, all checked BEFORE any
allocation/mutation/control emission: `N ≥ 2` and `gcd(c̄,N)=1` (a non-unit
multiplier is a loud `DomainError` naming `c`, `N`, `gcd` — no in-place unitary
permutation exists; NO fallback to the many-to-one map, no measurement-based
cleanup). Registered in-place: mutates and RETURNS THE SAME HANDLE (D12). The
process value is a phase-free `Perm`, so it is controllable in every context
(`ctrl^k(Perm)=Perm`) and MBU is excluded by construction — safe to use inside
`when` (the §7.7 Shor ladder). `docs/design/m9-addq-inplace-perm-design.md` §2.
"""
function mulmod!(y::QMod{N,W,C}, c::Integer) where {N,W,C}
    N ≥ 2 || throw(DomainError(N, "mulmod!(QMod{$N}, $c): modulus must be ≥ 2."))
    c̄ = Int(mod(c, N))
    g = gcd(c̄, N)
    g == 1 || throw(DomainError(c,
        "mulmod!(QMod{$N}, $c): multiplier not invertible mod $N (gcd = $g); " *
        "no in-place unitary permutation exists (§3.4). A non-unit multiplier is " *
        "many-to-one on ℤ_$N and no tail convention repairs it."))
    ctx = _here(y)                                   # validate context (no mutation)
    compiled = _get_mulmod_perm(Val(N), Val(W), c̄)   # classical compile (cached), no quantum action
    _apply_inplace_perm!(ctx, y.wires, compiled)
    return y
end
