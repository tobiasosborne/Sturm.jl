# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M8 (bead Sturm.jl-szx1), the i4ri
# classical-control gate (`docs/design/m8-i4ri-classical-control-design.md`),
# DM/Eager slice: the CLASSICAL OUTCOME TOKENS `ClassicalBit`/`ClassicalWord{W}`
# and the T2 restricted finite classical SSA on them.
#
# ── WHAT A TOKEN IS (design §2.1, Ruling D / §14) ───────────────────────────
# Under a `DensityMatrixContext` (and, in the NEXT slice, `TracingContext`) a
# measurement cast `Bool(q)` / `Int(x)` does NOT return a scalar (a scalar
# outcome is a trajectory, not a channel — §3.8). It returns a TOKEN: a handle
# to the instrument's CLASSICAL RECORD Σᵢ|i⟩⟨i|_C ⊗ ρ̃ᵢ, physically the measured
# wire PINCHED (complete-dephasing) and kept LIVE (`_instrument!`, density.jl —
# NO new physics primitive). The token names the pinched "c-wire(s)". Under
# `EagerContext` tokens do NOT exist: `Bool`/`Int` return real scalars (the
# trajectory contract), unchanged from M3/M6.
#
# ── COPYABLE, NOT AFFINE (design §2.2) ──────────────────────────────────────
# A classical outcome is physically copyable (fan-out is free), so tokens are
# freely reusable: `s = m` copies the handle and makes NO new measurement — both
# refer to the SAME record. This is the customer the M11 syndrome path needs
# (one syndrome drives several corrections). The QUANTUM handle stays affine (the
# shipped single-sourced `consumed` set); only the classical record is copyable.
#
# ── THE T2 SSA IS A LAZY DERIVATION OVER THE RECORD (design §1.2/§2.1) ───────
# A token carries (a) the BASE record wires it depends on and (b) a PURE
# evaluator `f(assignment) -> value`. A deterministic classical op y = g(x) (T2)
# is NOT a new measurement and NOT a new stochastic record: it EXTENDS the record
# to Σ_γ|γ,g(γ)⟩⟨γ,g(γ)|⊗ρ̃_γ — operationally, a NEW token whose base wires are
# the union and whose evaluator composes `g` after the operands' evaluators. No
# circuit is emitted for a derivation; the DM executor (surface/cases.jl) realises
# a `cases`/`select` by conditioning off the base c-wires, evaluating `f` per
# base-configuration. This is why derived-token correlation (`n = !m` ⇒ `m`,`n`
# perfectly anticorrelated — law L6) is EXACT and free: `m` and `n` share the one
# base record wire (design §2.1, "classical SSA creates no new stochastic record").
#
# ── THE RESTRICTION IS THE POINT (design §1, F4) ────────────────────────────
# A token is neither `Bool`, `Integer`, nor `Number`. It may sit in DATA position
# (T1 `cases`, T2 SSA, T3 `select`, T4 return) but NEVER in control-flow or
# indexing position. `if token` / `token && …` throw Julia's OWN non-boolean
# `TypeError` (naming the descriptive type — law L11); we do not and cannot
# intercept it (§9.0, F13 constraint 3 — the PRD-promised descriptive error was
# withdrawn as unimplementable). Where SturM owns the method (`arr[token]`,
# `iterate`, `convert`) we throw a loud, descriptive Sturm error pointing at
# `cases`/`select` (law L12).
#
# Physics/spec grounding: PRD-v2 §3.6 (classical outcomes and `cases`, Ruling D),
# §3.8 (portability — DM returns tokens), §3.2 (instrument/pinching). Token
# semantics as dynamic lifting with a bounded classical layer:
# docs/physics/fu_proto_quipper_dyn.md (dynamic lifting) and
# docs/physics/qrisp_jasp_dynamic_tracing.md (why a host-source tracer is the
# rejected alternative — §1.1).

# ---------------------------------------------------------------------------
# The token types (context-parameterized, F16 pattern)
# ---------------------------------------------------------------------------

"""
    ClassicalBit{C<:AbstractContext}

An opaque handle to a 1-bit classical RECORD produced by a measurement cast
under a `DensityMatrixContext` (Ruling D, PRD-v2 §3.6). It is NOT a `Bool`, NOT
an `Integer`, NOT a `Number` — it is a token in the restricted finite classical
SSA (T1–T4). Fields:

- `ctx::C` — the owning context (concrete type `C`, F16), for the active-context
  identity guard the executor runs.
- `wires::Vector{WireID}` — the BASE record c-wires this value depends on (a
  primitive measurement bit depends on ONE; a derived bit `m ⊻ n` on the union).
- `f::Function` — the PURE evaluator `Dict{WireID,Bool} -> Bool` giving this
  bit's value as a deterministic function of the base record assignment (design
  §2.1 — a T2 op composes evaluators, it does not sample).

`ClassicalBit` is COPYABLE (fan-out is free): reusing one in several `cases`
refers to the same record. Its record wires are traced (summed) only at region
exit or explicit `discard!` (last-use, design §2.2) — never while the token is
live (immediate summation destroys feed-forward correlation, law L7).
"""
struct ClassicalBit{C<:AbstractContext}
    ctx::C
    wires::Vector{WireID}
    f::Function          # Dict{WireID,Bool} -> Bool  (pure; cold classical path)
end

"""
    ClassicalWord{W,C<:AbstractContext}

An opaque handle to a `W`-bit classical RECORD (an unsigned word in ℤ_{2^W},
`W` the user-semantic width, `C` the trailing F16 context parameter — matching
`QInt{W,C}`). Chosen over a machine-`Int` `ClassicalInt` (design §1.3): the
measurement domain is the finite basis ℤ_{2^W}, width lives in the type,
arithmetic wraps mod 2^W, and hardware lowering carries an explicit bit width.
`wires` are the `W` base record c-wires (MSB-first), `f` the pure evaluator
`Dict{WireID,Bool} -> Int` (value in `0:2^W-1`). Neither a `Number` nor an
`Integer`; the same T1–T4 restriction as `ClassicalBit`.
"""
struct ClassicalWord{W,C<:AbstractContext}
    ctx::C
    wires::Vector{WireID}
    f::Function          # Dict{WireID,Bool} -> Int  (in 0:2^W-1)
end

const ClassicalToken = Union{ClassicalBit,ClassicalWord}

"The declared bit width of a token: 1 for a `ClassicalBit`, `W` for a `ClassicalWord{W}`."
width(::ClassicalBit) = 1
width(::ClassicalWord{W}) where {W} = W

contextof(t::ClassicalToken) = getfield(t, :ctx)

# --- Internal constructors (the measurement-cast + derivation seams) --------

_cbit(ctx::C, wires::Vector{WireID}, f::Function) where {C<:AbstractContext} =
    ClassicalBit{C}(ctx, wires, f)
_cword(::Val{W}, ctx::C, wires::Vector{WireID}, f::Function) where {W,C<:AbstractContext} =
    ClassicalWord{W,C}(ctx, wires, f)

"A primitive measurement bit on record wire `rec`: evaluator = read that wire."
_cbit_base(ctx::C, rec::WireID) where {C<:AbstractContext} =
    _cbit(ctx, [rec], d -> d[rec])

"""
    _cword_base(Val(W), ctx, recs) -> ClassicalWord{W,C}

A primitive measurement word on the `W` record wires `recs` (MSB-first, matching
the `QInt` endianness pin `n = Σ_j recs[j]·2^{W-j}`): evaluator reassembles the
integer from the base assignment.
"""
function _cword_base(::Val{W}, ctx::C, recs::Vector{WireID}) where {W,C<:AbstractContext}
    length(recs) == W || error("_cword_base: $(length(recs)) record wires for width $W")
    rw = copy(recs)
    f = d -> begin
        n = 0
        @inbounds for j in 1:W
            d[rw[j]] && (n |= (1 << (W - j)))
        end
        n
    end
    return _cword(Val(W), ctx, rw, f)
end

# --- The DM measurement-cast seam (Ruling D; the Eager siblings are in ------
# surface/casts.jl / types/qint.jl). Under DM the cast returns the RECORD as a
# token: `_instrument_record!` (density.jl) pinches + re-homes the slot to a
# fresh record wire, which the token names.

"DM `Bool(q)`: the pinched classical RECORD as a `ClassicalBit` token (Ruling D)."
_cast_bool(ctx::DensityMatrixContext, w::WireID) = _cbit_base(ctx, _instrument_record!(ctx, w))

"DM `Int(x)`: the pinched width-`W` classical RECORD as a `ClassicalWord{W}` token (Ruling D)."
function _cast_int(ctx::DensityMatrixContext, ::Val{W}, wires::NTuple{W,WireID}) where {W}
    recs = WireID[_instrument_record!(ctx, w) for w in wires]
    return _cword_base(Val(W), ctx, recs)
end

# --- Evaluator plumbing -----------------------------------------------------

_union_wires(ws...) = unique(reduce(vcat, ws))

_tokenctx(t::ClassicalBit) = t.ctx
_tokenctx(t::ClassicalWord) = t.ctx

"""
    _here_token(t) -> ctx

The token analogue of `_here`: assert the token's owning context is the active
one and OPEN, returning it. A token that escaped its context (used under a
different bound context) is a loud `ArgumentError` (its record wires are
per-context — the same guard the quantum handles run).
"""
function _here_token(t::ClassicalToken)
    ctx = _tokenctx(t)
    ctx === current_context() || throw(ArgumentError(
        "classical token operation: the token belongs to a different context than " *
        "the active one — a record handle escaped its context/region."))
    _require_open(ctx, "classical token operation")
    return ctx
end

# ---------------------------------------------------------------------------
# T2 — the whitelisted finite classical SSA (PRD-v2 §3.6 T2)
# ---------------------------------------------------------------------------
#
# Every op below is PURE, TOTAL on the finite domain, side-effect-free, and
# produces a NEW token whose evaluator composes the operands' — no measurement,
# no circuit, no stochastic record (design §2.1). A `ClassicalBit`/`ClassicalWord`
# is a lazy derivation over the base record wires; the DM executor realises it.

# ── ClassicalBit: bit algebra (!, ~, &, |, xor/⊻, == against a literal) ──────

Base.:!(a::ClassicalBit) = _cbit(a.ctx, a.wires, d -> !a.f(d))
Base.:~(a::ClassicalBit) = _cbit(a.ctx, a.wires, d -> !a.f(d))

for (op, jl) in ((:&, :&), (:|, :|), (:⊻, :⊻))
    @eval function Base.$op(a::ClassicalBit, b::ClassicalBit)
        a.ctx === b.ctx || throw(ArgumentError("classical bit op across two contexts"))
        _cbit(a.ctx, _union_wires(a.wires, b.wires), d -> $jl(a.f(d), b.f(d)))
    end
    # A token combined with a build-time-constant `Bool` folds the constant in.
    @eval Base.$op(a::ClassicalBit, c::Bool) = _cbit(a.ctx, a.wires, d -> $jl(a.f(d), c))
    @eval Base.$op(c::Bool, a::ClassicalBit) = _cbit(a.ctx, a.wires, d -> $jl(c, a.f(d)))
end
# NOTE: `⊻` IS `Base.xor`, so the `(:⊻, :⊻)` loop above already defines `xor` on
# `ClassicalBit` for the (bit,bit)/(bit,Bool)/(Bool,bit) cases — no separate
# `Base.xor` methods (a duplicate would be a method-overwrite error).

# Comparison of a bit against a build-time-constant `Bool` → a new bit (T2).
Base.:(==)(a::ClassicalBit, c::Bool) = _cbit(a.ctx, a.wires, d -> a.f(d) == c)
Base.:(==)(c::Bool, a::ClassicalBit) = a == c
_neq(a::ClassicalBit, c::Bool) = _cbit(a.ctx, a.wires, d -> a.f(d) != c)
Base.:(!=)(a::ClassicalBit, c::Bool) = _neq(a, c)
Base.:(!=)(c::Bool, a::ClassicalBit) = _neq(a, c)

# ── ClassicalWord: modular arithmetic, bitwise, shifts, slice, compare ───────

_wrap(::Val{W}, n::Integer) where {W} = Int(mod(n, 1 << W))

# Modular +, - (word,word and word,build-time-constant); constant *.
for (op, jl) in ((:+, :+), (:-, :-))
    @eval function Base.$op(a::ClassicalWord{W}, b::ClassicalWord{W}) where {W}
        a.ctx === b.ctx || throw(ArgumentError("classical word op across two contexts"))
        _cword(Val(W), a.ctx, _union_wires(a.wires, b.wires),
               d -> _wrap(Val(W), $jl(a.f(d), b.f(d))))
    end
    @eval Base.$op(a::ClassicalWord{W}, c::Integer) where {W} =
        _cword(Val(W), a.ctx, a.wires, d -> _wrap(Val(W), $jl(a.f(d), Int(c))))
end
Base.:+(c::Integer, a::ClassicalWord{W}) where {W} = a + c
Base.:*(a::ClassicalWord{W}, c::Integer) where {W} =
    _cword(Val(W), a.ctx, a.wires, d -> _wrap(Val(W), a.f(d) * Int(c)))
Base.:*(c::Integer, a::ClassicalWord{W}) where {W} = a * c

# Two RUNTIME words through the NON-whitelisted `*` / `÷` is a loud error
# (design §1.4): the register's group has no such op; combine BEFORE measuring.
@noinline _no_two_runtime(op) = throw(ArgumentError(
    "combining two measurement outcomes with `$op` is not in the classical SSA " *
    "whitelist (§3.6 T2): the register's finite-group post-processing is bit ops, " *
    "modular ±, constant ×, constant shift, static slice, and comparison-against-a-" *
    "build-time-constant. Do the multiplication in a QUANTUM arithmetic circuit " *
    "BEFORE measuring, or branch with `cases`/`select`."))
Base.:*(::ClassicalWord, ::ClassicalWord) = _no_two_runtime("*")
Base.:÷(::ClassicalWord, ::Union{ClassicalWord,Integer}) = _no_two_runtime("÷")
Base.:÷(::Integer, ::ClassicalWord) = _no_two_runtime("÷")

# Bitwise word ops (per-wire; a build-time-constant mask, or two words).
for (op, jl) in ((:&, :&), (:|, :|), (:⊻, :⊻))
    @eval function Base.$op(a::ClassicalWord{W}, b::ClassicalWord{W}) where {W}
        a.ctx === b.ctx || throw(ArgumentError("classical word op across two contexts"))
        _cword(Val(W), a.ctx, _union_wires(a.wires, b.wires),
               d -> _wrap(Val(W), $jl(a.f(d), b.f(d))))
    end
    @eval Base.$op(a::ClassicalWord{W}, c::Integer) where {W} =
        _cword(Val(W), a.ctx, a.wires, d -> _wrap(Val(W), $jl(a.f(d), Int(c))))
    @eval Base.$op(c::Integer, a::ClassicalWord{W}) where {W} = $op(a, c)
end
Base.:~(a::ClassicalWord{W}) where {W} =
    _cword(Val(W), a.ctx, a.wires, d -> _wrap(Val(W), ~a.f(d)))

# Shift by a BUILD-TIME constant (mod 2^W); the shift amount is a host integer.
Base.:>>(a::ClassicalWord{W}, s::Integer) where {W} =
    _cword(Val(W), a.ctx, a.wires, d -> _wrap(Val(W), a.f(d) >> Int(s)))
Base.:<<(a::ClassicalWord{W}, s::Integer) where {W} =
    _cword(Val(W), a.ctx, a.wires, d -> _wrap(Val(W), a.f(d) << Int(s)))

"""
    _dep_reduce(wires, f) -> Vector{WireID}

The SUPPORT of a pure evaluator `f` over `wires`: the sub-list of `wires` whose
value actually changes `f` for some assignment of the others (found by flipping
each wire across the others' 2^{K-1} configs). This keeps a token's `wires` (and
hence the `cases` fan-in, law L13) MINIMAL: a static bit-slice `w[j]` of a base
measurement word depends on ONE record wire, not all `W`, so `@cases w[j]` is a
1-control feed-forward (not a `W`-fold one). Capped: above `12` base wires the
reduction itself would be costly, so it is skipped (the `cases` fan-in cap then
catches an over-wide selector).
"""
function _dep_reduce(wires::Vector{WireID}, f)
    K = length(wires)
    (K == 0 || K > 12) && return wires
    deps = WireID[]
    for wi in wires
        others = WireID[w for w in wires if w !== wi]
        Ko = length(others)
        changed = false
        @inbounds for a in 0:((1 << Ko) - 1)
            d = Dict{WireID,Bool}()
            for k in 1:Ko
                d[others[k]] = ((a >> (k - 1)) & 1) == 1
            end
            d[wi] = false; v0 = f(d)
            d[wi] = true;  v1 = f(d)
            if v0 != v1
                changed = true
                break
            end
        end
        changed && push!(deps, wi)
    end
    return isempty(deps) ? wires : deps
end

# Static bit-slice `w[i]` at a BUILD-TIME index → a ClassicalBit (T2). This is
# field access on the record register, NOT array indexing by a token (bit 1 =
# MSB, matching QInt). Its `wires` are minimized to the record wire(s) bit `i`
# actually depends on (a base word ⇒ one wire ⇒ 1-control feed-forward). A token
# index `w[i::ClassicalWord]` is the FORBIDDEN indexing-position use (loud below).
function Base.getindex(a::ClassicalWord{W}, i::Integer) where {W}
    (1 <= i <= W) || throw(BoundsError(a, i))
    ii = Int(i)
    f = d -> ((a.f(d) >> (W - ii)) & 1) == 1
    reduced = _dep_reduce(a.wires, f)
    # The reduced evaluator receives an assignment over `reduced` only; seed the
    # dropped (irrelevant, by construction) base wires to `false` so `a.f` — which
    # still reads the full word — evaluates correctly.
    allw = a.wires
    g = length(reduced) == length(allw) ? f :
        (d -> f(merge!(Dict{WireID,Bool}(w => false for w in allw), d)))
    return _cbit(a.ctx, reduced, g)
end

# Comparison of a word against a BUILD-TIME constant → a ClassicalBit (T2).
for (op, jl) in ((:(==), :(==)), (:(!=), :(!=)), (:<, :<), (:<=, :<=), (:>, :>), (:>=, :>=))
    @eval Base.$op(a::ClassicalWord{W}, c::Integer) where {W} =
        _cbit(a.ctx, a.wires, d -> $jl(a.f(d), Int(c)))
end

# Explicit width changes (design §1.3 — never by implicit Julia conversion).

"""
    zext(w::ClassicalWord{W}, ::Val{W2}) -> ClassicalWord{W2}

Zero-extend a word to a wider width `W2 ≥ W` (the value is preserved; the new
high bits are 0). An EXPLICIT width change (design §1.3): token widths never
change by implicit conversion.
"""
function zext(w::ClassicalWord{W}, ::Val{W2}) where {W,W2}
    W2 >= W || throw(ArgumentError("zext: target width $W2 < source width $W (use `truncate_word`)"))
    return _cword(Val(W2), w.ctx, w.wires, w.f)   # value unchanged; wider domain
end

"""
    truncate_word(w::ClassicalWord{W}, ::Val{W2}) -> ClassicalWord{W2}

Truncate a word to a narrower width `W2 ≤ W` (keep the low `W2` bits, mod 2^W2).
An EXPLICIT width change (design §1.3).
"""
function truncate_word(w::ClassicalWord{W}, ::Val{W2}) where {W,W2}
    W2 <= W || throw(ArgumentError("truncate_word: target width $W2 > source width $W (use `zext`)"))
    return _cword(Val(W2), w.ctx, w.wires, d -> _wrap(Val(W2), w.f(d)))
end

# ---------------------------------------------------------------------------
# T3 — bounded select / total ClassicalTable lookup (PRD-v2 §3.6 T3)
# ---------------------------------------------------------------------------

"""
    ClassicalTable(entries::AbstractVector; default=nothing)

An immutable, TOTAL lookup table over the token domain (design §1.3). `entries`
is captured at trace start; a lookup `select(t, table)` must be total — if the
token domain exceeds the table and no `default` was given, construction of the
lookup fails. This is the ONLY form of token-indexed lookup; ordinary
arrays/dicts CANNOT be indexed by a token.
"""
struct ClassicalTable{T}
    entries::Vector{T}
    default::Union{Nothing,T}
    ClassicalTable(entries::AbstractVector{T}; default=nothing) where {T} =
        new{T}(collect(entries), default)
end

Base.length(tbl::ClassicalTable) = length(tbl.entries)

"""
    select(pred::ClassicalBit, a, b) -> token
    select(t::ClassicalWord{W}, table) -> token
    select(t::ClassicalWord{W}, tbl::ClassicalTable) -> token

The bounded classical multiplexer (T3): a NEW token whose value is chosen by the
discriminant token from a STATIC set of classical values `a`/`b`/`table`. It is a
pure derivation (design §1.3) — `select` does not branch quantum ops (that is
`cases`); it selects a classical VALUE that flows on through T2 or into a later
`cases`. `a`,`b`,`table` entries must be build-time classical values.
"""
function select(pred::ClassicalBit, a::Integer, b::Integer)
    va, vb = Int(a), Int(b)
    W = _min_width(max(va, vb))
    return _cword(Val(W), pred.ctx, pred.wires, d -> (pred.f(d) ? va : vb))
end
select(pred::ClassicalBit, a::Bool, b::Bool) =
    _cbit(pred.ctx, pred.wires, d -> (pred.f(d) ? a : b))

function select(t::ClassicalWord{W}, table::AbstractVector{<:Integer}) where {W}
    length(table) >= (1 << W) || throw(ArgumentError(
        "select(word, table): a raw-vector table must be TOTAL over the word domain " *
        "0:$( (1<<W)-1 ) (got length $(length(table))). Use a `ClassicalTable` with a " *
        "`default` for a partial table (T3 totality, §3.6)."))
    tab = collect(Int.(table))
    W2 = _min_width(maximum(tab))
    return _cword(Val(W2), t.ctx, t.wires, d -> tab[t.f(d) + 1])
end

function select(t::ClassicalWord{W}, tbl::ClassicalTable{<:Integer}) where {W}
    dom = 1 << W
    (length(tbl) >= dom || tbl.default !== nothing) || throw(ArgumentError(
        "select(word, ClassicalTable): lookup is not total over 0:$(dom-1) and the " *
        "table has no `default` — an incomplete lookup fails during tracing (T3, §3.6)."))
    entries = tbl.entries
    dflt = tbl.default
    hi = isempty(entries) ? 0 : maximum(entries)
    dflt !== nothing && (hi = max(hi, dflt))
    W2 = _min_width(hi)
    f = d -> begin
        v = t.f(d)
        (0 <= v < length(entries)) ? Int(entries[v + 1]) : Int(dflt)
    end
    return _cword(Val(W2), t.ctx, t.wires, f)
end

_min_width(maxval::Integer) = max(1, (maxval <= 0 ? 1 : (8 * sizeof(Int) - leading_zeros(Int(maxval)))))

# --- Host-scalar `select` (M11 ruling S30) -----------------------------------
# Under Eager a measurement yields a host `Bool`/`Int`, so the §3.8 portability
# contract ("one listing runs in all three contexts") needs `select` to accept
# host scalars with the SAME totality checks and the SAME messages as the token
# methods above — without these, the M11 syndrome program MethodErrors on Eager.

"Host-scalar `select` (S30): the Eager twin of the token multiplexer."
select(pred::Bool, a::Integer, b::Integer) = pred ? Int(a) : Int(b)
select(pred::Bool, a::Bool, b::Bool) = pred ? a : b

"""
    zext(v::Integer, ::Val{W}) -> Int

Host-scalar `zext` twin (S30): the Eager identity embedding with the SAME
domain check as the token version — `v` must already fit in `W` bits.
"""
function zext(v::Integer, ::Val{W}) where {W}
    0 <= v < (1 << W) || throw(ArgumentError(
        "zext: value $v does not fit in $W bits (domain 0:$((1 << W) - 1))"))
    return Int(v)
end

function select(v::Integer, table::AbstractVector{<:Integer})
    0 <= v || throw(ArgumentError("select(value, table): negative discriminant $v"))
    v < length(table) || throw(ArgumentError(
        "select(value, table): a raw-vector table must be TOTAL over the word domain " *
        "0:$(length(table) - 1) (got discriminant $v). Use a `ClassicalTable` with a " *
        "`default` for a partial table (T3 totality, §3.6)."))
    return Int(table[v + 1])
end

function select(v::Integer, tbl::ClassicalTable{<:Integer})
    0 <= v || throw(ArgumentError("select(value, ClassicalTable): negative discriminant $v"))
    if v < length(tbl.entries)
        return Int(tbl.entries[v + 1])
    end
    tbl.default === nothing && throw(ArgumentError(
        "select(value, ClassicalTable): lookup is not total (discriminant $v beyond " *
        "the $(length(tbl.entries)) entries) and the table has no `default` — an " *
        "incomplete lookup fails during tracing (T3, §3.6)."))
    return Int(tbl.default)
end

# ---------------------------------------------------------------------------
# The loud-rejection boundary (PRD-v2 §3.6, design §1.4 / law L12)
# ---------------------------------------------------------------------------
#
# A token in CONTROL-FLOW or INDEXING position. Most rejections are FREE — Julia
# throws first: `if t`/`t && x`/`t || x` raise the native non-boolean `TypeError`
# on the descriptive token type (law L11; we cannot and do not intercept it,
# §9.0). Where SturM OWNS the method we throw a descriptive Sturm error pointing
# at `cases`/`select` (law L12): array-index-by-token, iteration, and `convert`.

@noinline _token_control_flow_error(what) = throw(ArgumentError(
    "a measurement outcome (classical token) cannot be used in $what: it is not a " *
    "`Bool`/`Integer`/`Number` and may sit only in DATA position — `cases`/`@cases` " *
    "to branch, `select` to pick a value, `!`/`⊻`/`+`/`==`-against-a-constant for the " *
    "finite classical SSA (§3.6 T1–T4). `if token` / `token && …` are Julia's own " *
    "non-boolean errors; there is no host branch on a quantum outcome."))

# A token in a Sturm-owned forbidden position: RECORD the site into the tracer
# pre-flight lint (Ruling D §14 — a no-op off a TracingContext) BEFORE the
# descriptive throw. The `if`/`&&`/`||` sites are Julia-native `TypeError`s
# (uncatchable) and cannot be recorded — the lint covers what Sturm owns.
@noinline function _token_reject(t::ClassicalToken, what::AbstractString)
    _note_nonportable!(contextof(t), what)
    _token_control_flow_error(what)
end

# Array indexing by a token (Sturm-owned via the token type in the index slot).
# The single-index `getindex` is more specific than Base's varargs (no ambiguity);
# `to_index` is the funnel multi-index / `to_indices` forms route through — both
# loud, both descriptive.
Base.getindex(::AbstractArray, t::ClassicalToken) = _token_reject(t, "an array index (`arr[token]`)")
Base.to_index(t::ClassicalToken) = _token_reject(t, "an array index (`arr[token]`)")

# Iteration (a `for x in token` / splatting attempt).
Base.iterate(t::ClassicalToken) = _token_reject(t, "iteration (`for x in token`)")
Base.iterate(t::ClassicalToken, ::Any) = _token_reject(t, "iteration (`for x in token`)")

# Explicit host coercions to a scalar — the P2 implicit path stays loud and
# Eager-only (Ruling D / §14: `convert(Bool, ·)` never silently degrades). Note
# the pre-flight lint, then throw the record-specific message.
function Base.convert(::Type{Bool}, t::ClassicalBit)
    _note_nonportable!(contextof(t), "a host coercion (`convert(Bool, token)`)")
    throw(ArgumentError(
        "convert(Bool, ::ClassicalBit): a measurement outcome under a channel context is " *
        "a classical RECORD, not a host `Bool` (Ruling D, §3.6). Branch with `cases`; to " *
        "sample a scalar trajectory run under `shots` over an Eager context (§3.8)."))
end
function Base.convert(::Type{<:Integer}, t::ClassicalWord)
    _note_nonportable!(contextof(t), "a host coercion (`convert(Integer, token)`)")
    throw(ArgumentError(
        "convert(Integer, ::ClassicalWord): a measurement outcome under a channel context " *
        "is a classical RECORD, not a host integer (Ruling D, §3.6). Use `cases`/`select`, " *
        "or `shots` over Eager for a scalar trajectory."))
end

# Word-indexed by a TOKEN (the forbidden dynamic index) — distinct from the
# static build-time `w[i::Integer]` slice above.
Base.getindex(::ClassicalWord, t::ClassicalToken) = _token_reject(t, "a token index (`w[token]`)")
